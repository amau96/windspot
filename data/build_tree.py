"""Construit l'arbre de spots pour le menu de la montre a partir de data/spots_clean.csv
et des ajouts manuels de data/spots_extra.csv.

Facade > Departement > (Secteur si plus de MAX_ITEMS spots) > Spot.
Usage : python3 data/build_tree.py  (ecrit data/spots_tree.json et data/spots_tree.md)
"""
import csv, json, math, re, unicodedata
from collections import defaultdict

MAX_ITEMS = 10
MERGE_M = 1000   # spots a moins de 1 km : meme maille AROME, fusionnes
SECTOR_KM = 12   # rayon de regroupement des secteurs

FACADE_OF_DEPT = {"22": "Manche", "35": "Manche", "05": "Lacs", "74": "Lacs", "04": "Lacs"}
LAKE_PREFIX = ("Lac de Sainte-Croix", "Lac de Saint-Croix")  # lacs du Verdon classes en 83

# nom retenu pour chaque groupe fusionne (cle : un des spots du groupe)
MERGE_NAMES = {
    "Mazerolles": "Mazerolles",
    "Biscarrosse Plage": "Biscarrosse Plage",
    "Lac de Cazaux - Navarosse": "Lac de Cazaux - Navarosse",
    "Les Pêcheurs - Leucate": "Leucate - Les Pêcheurs",
    "Port-Leucate": "Port-Leucate",
    "Les Dosses - Etang de Leucate": "Etang de Leucate - Les Dosses",
    "Saint-Pierre (Locmariaquer)": "Locmariaquer - Saint-Pierre",
    "Mesperleuc'h": "Mesperleuc'h",
    "L'Almanarre": "L'Almanarre",
    "Ayguade": "Hyères - Ayguade",
    "Saint-Raphaël - Beau Rivage": "Saint-Raphaël - Beau Rivage",
    "Toulhars - Larmor Plage": "Larmor - Toulhars",
    "Pont Mahé": "Pont Mahé",
    "Locquirec - Sables Blancs": "Locquirec - Sables Blancs",
}


# nom de chaque secteur (cle : un spot du secteur)
SECTOR_NAMES = {
    "La Perroche": "Oléron Sud - Marennes", "Aytré": "Oléron Nord - Châtelaillon", "Diamond Head": "Île de Ré",
    "Kerleven": "Bénodet - Concarneau", "Pouldreuzic, Penhors": "La Torche - Bigouden",
    "Kervel": "Audierne - Douarnenez", "Sainte Marguerite": "Brest - Crozon",
    "Soustons": "Hossegor - Capbreton", "Contis": "Contis - Léon - Moliets",
    "Lac de Cazaux - Les Aigrettes": "Biscarrosse - Cazaux",
    "Vioreau": "Lacs nantais", "Saint Nazaire": "Saint-Brevin - Retz", "Batz sur Mer": "La Baule",
    "Etang Aumée": "Guérande - Pénestin",
    "Damgan": "Rhuys - Damgan", "Île de Houat - Treac'h er Goured": "Îles", "Penthièvre Baie": "Quiberon",
    "La Trinité": "Carnac - Trinité", "La Roche Sèche": "Erdeven - Plouharnel", "Arradon": "Golfe du Morbihan",
    "Lac de Ploermel": "Lac de Ploërmel", "Larmor - Toulhars": "Lorient - Gâvres - Étel",
    "Guidel-plage - La Falaise": "Guidel - Ploemeur",
    "Port Bourgenay - Le Veillon": "Jard - La Tranche", "La Sauzaie": "Les Sables - Brétignolles",
    "Notre Dame de Monts": "Saint-Jean-de-Monts", "Noirmoutier - La Luzéronde": "Noirmoutier - Fromentine",
    "Leucate - Les Pêcheurs": "Leucate - Barcarès", "Le Rouet": "La Franqui - La Palme",
    "La Nautique - Narbonne": "Narbonne - Sigean", "Etang de Mateille": "Gruissan - Port-la-Nouvelle",
    "Lac de Jouarres": "Lac de Jouarres",
    "Epluchures Beach": "Marseille - La Ciotat", "Fos": "Fos - Côte Bleue", "Beauduc": "Camargue",
    "Lac de Peyrolles": "Étang de Berre",
    "Marseillan": "Agde - Valras", "Sète": "Sète - Thau - Salagou", "La Grande Motte": "Palavas - Grande-Motte",
    "Canet en Roussillon": "Canet - Argelès", "Sainte-Marie": "Barcarès - Étang de Leucate",
    "Bandol": "Toulon - Bandol", "L'Almanarre": "Hyères - Giens", "Le Lavandou": "Le Lavandou - Bormes",
    "Pampelonne": "Saint-Tropez", "Fréjus Plage": "Fréjus - Saint-Raphaël",
}


def dist(a, b):
    la1, lo1, la2, lo2 = map(math.radians, [a[0], a[1], b[0], b[1]])
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(h))


def key(s):
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def load():
    rows = list(csv.DictReader(open("data/spots_clean.csv", encoding="utf-8")))
    # spots ajoutes a la main (groupe libre a la place du departement)
    for e in csv.DictReader(open("data/spots_extra.csv", encoding="utf-8")):
        rows.append({"Spot": e["Spot"], "Dép.": "zz", "Département": e["Groupe"], "Façade": e["Façade"],
                     "Latitude": e["Latitude"], "Longitude": e["Longitude"]})
    for r in rows:
        r["p"] = (float(r["Latitude"]), float(r["Longitude"]))
    return rows


def merge(rows):
    parent = list(range(len(rows)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            if dist(rows[i]["p"], rows[j]["p"]) < MERGE_M:
                parent[find(i)] = find(j)
    groups = defaultdict(list)
    for i, r in enumerate(rows):
        groups[find(i)].append(r)
    spots, merged = [], []
    for g in groups.values():
        rep = g[0]
        name = rep["Spot"]
        if len(g) > 1:
            named = [r for r in g if r["Spot"] in MERGE_NAMES]
            if not named:
                raise SystemExit("groupe sans nom : " + ", ".join(r["Spot"] for r in g))
            rep = named[0]
            name = MERGE_NAMES[rep["Spot"]]
            merged.append((name, [r["Spot"] for r in g]))
        spots.append({"name": name, "dept": rep["Dép."], "deptName": rep["Département"],
                      "facade": rep["Façade"], "p": rep["p"]})
    return spots, merged


def rename_homonyms(spots):
    by = defaultdict(list)
    for s in spots:
        by[key(re.sub(r"[-'\s]", "", s["name"]))].append(s)
    for g in by.values():
        if len(g) == 2:
            g.sort(key=lambda s: -s["p"][0])
            base = min((s["name"] for s in g), key=len) if len({s["name"] for s in g}) > 1 else g[0]["name"]
            base = base.replace("Sables d'Olonne", "Sables-d'Olonne")
            g[0]["name"] = base + " - Nord"
            g[1]["name"] = base + " - Sud"


def facade(s):
    if s["name"].startswith(LAKE_PREFIX):
        return "Lacs"
    if s["facade"] in ("Intérieur", "Lacs"):
        return "Lacs"
    return FACADE_OF_DEPT.get(s["dept"], s["facade"])


def sectors(spots, target=7):
    """Groupes geographiques equilibres (k-moyennes), chacun d'au plus MAX_ITEMS spots."""
    k = max(2, math.ceil(len(spots) / target))
    pts = sorted(spots, key=lambda s: (s["p"][0], s["p"][1]))
    centers = [pts[int((i + 0.5) * len(pts) / k)]["p"] for i in range(k)]
    for _ in range(50):
        groups = [[] for _ in range(k)]
        for s in spots:
            groups[min(range(k), key=lambda i: dist(s["p"], centers[i]))].append(s)
        groups = [g for g in groups if g]
        new = [(sum(s["p"][0] for s in g) / len(g), sum(s["p"][1] for s in g) / len(g)) for g in groups]
        if new == centers:
            break
        centers, k = new, len(new)
    out = []
    for g in groups:
        if len(g) > MAX_ITEMS:
            out.extend(sectors(g, target))
        else:
            out.append(g)
    return out


def sector_name(sec):
    for sp in sec:
        if sp["name"] in SECTOR_NAMES:
            return SECTOR_NAMES[sp["name"]]
    raise SystemExit("secteur sans nom : " + " | ".join(sp["name"] for sp in sec))


FACADE_ORDER = ["Atlantique", "Manche", "Méditerranée", "Lacs"]


def write_phone_settings(out, flat):
    """Liste « Spot » des reglages de l'app Connect IQ (telephone) et numero par defaut de chaque montre."""
    from xml.sax.saxutils import escape
    labels = []

    # Libelle court « 56 · Le Men Du » : numero de departement + nom (premiere partie si plus de 22 caracteres).
    # Si la coupe cree un doublon dans le departement : dernier mot-cle de la 1re partie + derniere partie
    # (« Lac de Cazaux - Navarosse » -> « Cazaux - Navarosse »).
    import collections
    items = []

    def walk(nodes, code):
        for nd in nodes:
            if isinstance(nd[1], list):
                walk(nd[1], code)
            else:
                items.append((code, nd))
    for facade, depts in out:
        for label, children in depts:
            m = re.search(r"\((\w+)\)$", label)
            walk(children, m.group(1) if m else label)

    def short(n):
        return n if len(n) <= 22 else re.split(r" - |, ", n)[0]
    count = collections.Counter((c, short(nd[0])) for c, nd in items)
    for c, nd in items:
        name = short(nd[0])
        if count[(c, name)] > 1 and name != nd[0]:
            parts = re.split(r" - |, ", nd[0])
            kw = [w for w in re.split(r"[ '-]", parts[0]) if len(w) >= 4]
            name = (kw[-1] + " - " if kw else "") + parts[-1]
        labels.append((nd[3], f"{c} · {name}"))
    entries = []
    strings = ['<resources>']
    for n, text in labels:
        entries.append(f'<listEntry value="{n}">@Strings.Spot{n}</listEntry>')
        strings.append(f'    <string id="Spot{n}">{escape(text)}</string>')
    strings.append("</resources>")
    # settings/phone : reglages avec la liste des spots (970) ; settings/basic : sans la liste
    # (la fenix 6 refuse plus de 254 textes, et n'a de toute facon pas les reglages telephone en sideload)
    tpl = open("data/settings.template.xml", encoding="utf-8").read()
    open("settings/phone/settings.xml", "w", encoding="utf-8").write(
        tpl.replace("<!--SPOTS-->", "\n                ".join(entries)))
    open("settings/phone/spots.xml", "w", encoding="utf-8").write("\n".join(strings) + "\n")
    basic = re.sub(r'\s*<setting propertyKey="@Properties.spotId"[\s\S]*?</setting>', "", tpl)
    open("settings/basic/settings.xml", "w", encoding="utf-8").write(basic)
    # spot par defaut de chaque montre
    for props, name in (("props/default/properties.xml", "Mazerolles"),):
        n = next(nd[3] for nd in flat if nd[0] == name)
        x = open(props, encoding="utf-8").read()
        x = re.sub(r'\s*<property id="spotId" type="number">\d+</property>', "", x)
        x = x.replace("<properties>", f'<properties>\n        <property id="spotId" type="number">{n}</property>', 1)
        open(props, "w", encoding="utf-8").write(x)


def write_watch_resources(out):
    """Ressources du menu montre : un index (facades > departements) et un fichier par departement,
    charge seulement a l'ouverture (memoire limitee sur fenix 6). Genere aussi source/SpotIndex.mc."""
    import os
    d = "resources/jsonData"
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        if f.startswith("spots_"):
            os.remove(os.path.join(d, f))
    index, n = [], 0
    xml = ['<resources>', '    <jsonData id="SpotIndex" filename="spots_index.json"/>']
    for facade, depts in out:
        entries = []
        for label, children in depts:
            json.dump(children, open(f"{d}/spots_{n}.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
            xml.append(f'    <jsonData id="Spots{n}" filename="spots_{n}.json"/>')
            entries.append([label, n])
            n += 1
        index.append([facade, entries])
    json.dump(index, open(f"{d}/spots_index.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    xml.append("</resources>")
    open(f"{d}/jsonData.xml", "w", encoding="utf-8").write("\n".join(xml) + "\n")
    refs = ",\n        ".join(f"Rez.JsonData.Spots{i}" for i in range(n))
    open("source/SpotIndex.mc", "w", encoding="utf-8").write(f"""// Genere par data/build_tree.py : ne pas modifier a la main.
import Toybox.Lang;
import Toybox.WatchUi;

// Liste des spots d'un departement (index n du fichier spots_index.json)
function spotGroupResource(n as Number) as ResourceId {{
    var all = [
        {refs}
    ];
    return all[n];
}}

const SPOT_GROUP_COUNT = {n};
""")

if __name__ == "__main__":
    rows = load()
    spots, merged = merge(rows)
    rename_homonyms(spots)
    for s in spots:
        s["facade"] = facade(s)
    tree = defaultdict(lambda: defaultdict(list))
    for s in spots:
        tree[s["facade"]][(s["dept"], s["deptName"])].append(s)

    # arbre : [nom, enfants] pour les noeuds, [nom, lat, lon] pour les spots
    def leaf(sp):
        return [sp["name"], round(sp["p"][0], 3), round(sp["p"][1], 3)]
    out, md = [], ["# Arbre des spots (menu montre)", "",
                   f"{len(rows)} spots dans le fichier nettoyé, {len(spots)} après fusion des spots à moins de 1 km.", ""]
    for f in FACADE_ORDER:
        depts = []
        md += [f"## {f}", ""]
        for (d, dn), lst in sorted(tree[f].items()):
            label = dn if d == "zz" else f"{dn} ({d})"
            lst.sort(key=lambda sp: key(sp["name"]))
            if len(lst) > MAX_ITEMS:
                secs = sorted(sectors(lst), key=lambda sec: -max(sp["p"][0] for sp in sec))
                children = []
                md += [f"### {label} — {len(lst)} spots, {len(secs)} secteurs", ""]
                for sec in secs:
                    sec.sort(key=lambda sp: key(sp["name"]))
                    name = sector_name(sec)
                    children.append([name, [leaf(sp) for sp in sec]])
                    md.append(f"- **{name}** ({len(sec)}) : " + ", ".join(sp["name"] for sp in sec))
                md.append("")
                depts.append([label, children])
            else:
                depts.append([label, [leaf(sp) for sp in lst]])
                md += [f"### {label} — {len(lst)} spots", "", ", ".join(sp["name"] for sp in lst), ""]
        out.append([f, depts])
    md += ["## Fusions (spots à moins de 1 km)", ""]
    md += [f"- **{n}** ← " + ", ".join(m) for n, m in sorted(merged)]
    long = sorted({sp["name"] for sp in spots if len(sp["name"]) > 20}, key=len, reverse=True)
    md += ["", f"## Noms de plus de 20 caractères ({len(long)}) — risquent d'être coupés sur la montre", "", ", ".join(long)]
    # numero de spot (1..N) dans l'ordre de l'arbre ; 0 = spot personnalise
    flat = []

    def number(nodes):
        for nd in nodes:
            if isinstance(nd[1], list):
                number(nd[1])
            else:
                flat.append(nd)
                nd.append(len(flat))
    for f in out:
        number(f[1])
    write_phone_settings(out, flat)
    json.dump(out, open("data/spots_tree.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    write_watch_resources(out)
    open("data/spots_tree.md", "w", encoding="utf-8").write("\n".join(md) + "\n")
    print(len(spots), "spots ->", "data/spots_tree.json", "et data/spots_tree.md")
