"""Nettoyage de spots_thegoodspots.csv : noms, departements, facades, doublons probables.

Usage : python3 data/clean_spots.py <source.csv> <communes.json> <sortie.csv>
Le fichier source n'est pas modifie.
"""
import csv, json, math, re, sys, unicodedata

DEPTS = {
    "04": "Alpes-de-Haute-Provence", "05": "Hautes-Alpes", "06": "Alpes-Maritimes", "11": "Aude",
    "13": "Bouches-du-Rhône", "17": "Charente-Maritime", "22": "Côtes-d'Armor", "29": "Finistère",
    "30": "Gard", "34": "Hérault", "35": "Ille-et-Vilaine", "40": "Landes", "44": "Loire-Atlantique",
    "56": "Morbihan", "66": "Pyrénées-Orientales", "74": "Haute-Savoie", "83": "Var", "85": "Vendée",
}
TYPOS = [("Biscarosse", "Biscarrosse"), ("Hières", "Hyères"), ("Séte", "Sète"),
         ("LaPiste", "La Piste"), ("LaPiscine", "La Piscine")]
# corrections verifiees (commune trouvee a partir des coordonnees, ou commune connue)
DEPT_FIX = {"CVAN": "44", "Eole - Etang de Leucate": "66"}
# lacs de montagne classes a tort en « Atlantique » : facade Atlantique a l'est de 3° E


def norm(s):
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def dist(a, b):
    la1, lo1, la2, lo2 = map(math.radians, [a[0], a[1], b[0], b[1]])
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(h))


def clean_name(s):
    s = s.replace("’", "'").strip()
    s = re.sub(r"\s+-\s*|\s*-\s+", " - ", s)  # « - » separateur (espace d'un cote) ; garde Saint-Malo
    s = re.sub(r"\s{2,}", " ", s)
    for a, b in TYPOS:
        s = s.replace(a, b)
    return s


def main(src, communes_path, dst):
    rows = list(csv.DictReader(open(src, encoding="utf-8-sig")))
    communes = json.load(open(communes_path, encoding="utf-8"))
    fields = list(rows[0].keys()) + ["Remarques"]
    notes = {r["id"]: [] for r in rows}

    for r in rows:
        old = r["Spot"]
        r["Spot"] = clean_name(old)
        if r["Spot"] != old:
            notes[r["id"]].append(f"nom corrigé (était « {old} »)")
        if r["Façade"] == "Aquitaine":
            r["Façade"] = "Atlantique"
        elif r["Façade"] == "Saint-Chamas":
            r["Façade"] = "Méditerranée"
            notes[r["id"]].append("façade corrigée")
        if r["Façade"] == "Atlantique" and float(r["Longitude"]) > 3.0:
            r["Façade"] = "Intérieur"
            notes[r["id"]].append("façade corrigée (lac de montagne)")
        if old.strip() in DEPT_FIX and r["Dép."] != DEPT_FIX[old.strip()]:
            notes[r["id"]].append(f"département corrigé (était {r['Dép.'] or 'vide'})")
            r["Dép."] = DEPT_FIX[old.strip()]
        c = communes.get(r["id"])
        if not r["Dép."].strip() and c:
            r["Dép."] = c["codeDepartement"]
            notes[r["id"]].append(f"département ajouté (commune {c['nom']})")

    # departements manquants : spot voisin le plus proche qui en a un
    known = [r for r in rows if r["Dép."].strip()]
    for r in rows:
        if r["Dép."].strip():
            continue
        p = (float(r["Latitude"]), float(r["Longitude"]))
        best = min(known, key=lambda k: dist(p, (float(k["Latitude"]), float(k["Longitude"]))))
        d = dist(p, (float(best["Latitude"]), float(best["Longitude"])))
        r["Dép."] = best["Dép."]
        notes[r["id"]].append(f"département déduit du spot voisin « {best['Spot']} » à {d / 1000:.1f} km")

    for r in rows:
        r["Dép."] = r["Dép."].zfill(2)
        name = DEPTS.get(r["Dép."], "")
        if name and r["Département"] != name:
            if r["Département"]:
                notes[r["id"]].append(f"nom de département corrigé (était « {r['Département']} »)")
            r["Département"] = name

    # Gruissan est dans l'Aude
    for r in rows:
        if norm(r["Spot"]).startswith("gruissan") and r["Dép."] != "11":
            notes[r["id"]].append(f"département corrigé (était {r['Dép.']})")
            r["Dép."], r["Département"] = "11", DEPTS["11"]

    # doublons probables : meme nom normalise, ou moins de 1 km (meme maille AROME)
    pts = [(float(r["Latitude"]), float(r["Longitude"])) for r in rows]
    for i, a in enumerate(rows):
        for j, b in enumerate(rows):
            if i == j:
                continue
            d = dist(pts[i], pts[j])
            if norm(a["Spot"]) == norm(b["Spot"]):
                notes[a["id"]].append(f"même nom que « {b['Spot']} » à {d / 1000:.1f} km")
            elif d < 1000:
                notes[a["id"]].append(f"doublon probable : « {b['Spot']} » à {round(d)} m")

    for r in rows:
        if all(r[k] in ("", "Non praticable") for k in ("Wingfoil", "Kitesurf", "Windsurf", "Surf")):
            notes[r["id"]].append("aucune pratique renseignée")
        r["Remarques"] = " ; ".join(notes[r["id"]])

    rows.sort(key=lambda r: (r["Façade"], r["Dép."], norm(r["Spot"])))
    with open(dst, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    main(*sys.argv[1:4])
