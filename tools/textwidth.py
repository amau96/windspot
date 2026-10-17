#!/usr/bin/env python3
"""Largeur d'un texte sur chaque montre, sans simulateur.

Additionne les largeurs de caractere mesurees dans le simulateur (data/font_metrics.json,
genere par tools/build_font_metrics.py). Les polices vectorielles rapprochent parfois deux
lettres ; verifie sur 67 montres x 6 formats (402 cas) : ecart de 0 px avec la mesure directe.

Exemples :
  tools/textwidth.py "sam. 28 nd 15h" --windline        # ligne vent : « 19 nd » + fleche + « · » + texte
  tools/textwidth.py "Mazerolles" --font label --device fr970
"""
import argparse
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
METRICS = os.path.join(ROOT, "data", "font_metrics.json")


def width(text, font):
    """Largeur en pixels ; None si un caractere n'a pas ete mesure."""
    total = 0
    for ch in text:
        w = font["w"].get(ch)
        if w is None:
            return None
        total += w
    return total


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("text")
    ap.add_argument("--font", default="xtiny", choices=["xtiny", "label", "load"],
                    help="xtiny : ligne vent, date, ligne du haut ; label : nom du spot, reperes ; load : chargement")
    ap.add_argument("--windline", action="store_true",
                    help="texte apres la fleche de la ligne vent, compare a la place dans le cercle")
    ap.add_argument("--device", help="une seule montre")
    ap.add_argument("--all", action="store_true", help="afficher aussi les montres ou ca tient")
    args = ap.parse_args()

    devices = json.load(open(METRICS, encoding="utf-8"))
    rows = []
    for dev, m in sorted(devices.items()):
        if args.device and dev != args.device:
            continue
        font = m["fonts"][args.font]
        if args.windline:
            base = width("19 nd", m["fonts"]["xtiny"])
            text = width(" · " + args.text, font)
            w = None if text is None else base + m["arrow"] + text
            room = m["windline_room"]
        else:
            w = width(args.text, font)
            room = m["width"]
        rows.append((dev, m["width"], w, room))

    missing = [r[0] for r in rows if r[2] is None]
    if missing:
        print("caracteres non mesures pour :", ", ".join(missing))
    rows = [r for r in rows if r[2] is not None]
    over = [r for r in rows if r[2] > r[3]]
    tight = [r for r in rows if r[3] - 4 <= r[2] <= r[3]]
    shown = rows if (args.all or args.device) else over + tight
    for dev, res, w, room in sorted(shown, key=lambda r: r[2] - r[3], reverse=True):
        flag = "DEBORDE" if w > room else ("juste" if room - w <= 4 else "ok")
        print(f"{dev:28s} {res:4d}px  texte {w:4d}  place {room:4d}  marge {room - w:+4d}  {flag}")
    worst = min(rows, key=lambda r: r[3] - r[2]) if rows else None
    print(f"\n{len(rows)} montres : {len(over)} debordent, {len(tight)} a 4 px ou moins"
          + (f" ; pire marge {worst[3] - worst[2]:+d} px ({worst[0]})" if worst else ""))


if __name__ == "__main__":
    main()
