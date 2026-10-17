#!/usr/bin/env python3
"""Construit data/font_metrics.json a partir de la sortie de la mesure dans le simulateur.

La mesure (instrumentation provisoire de WingFaceView.drawWindLine, une montre a la fois) ecrit :
  DEV;<montre>
  DBGH;<largeur ecran>;<small>;<tiny>;<police vectorielle>;<place ligne vent>;<fleche>;<ascent>
  DBGF;<police>;<hauteur>;<largeur de chaque caractere de CHARS, separees par des virgules>

Usage : tools/build_font_metrics.py chars.txt
"""
import json
import os
import sys

# meme chaine, dans le meme ordre, que l'instrumentation Monkey C
CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ .,:;·%!?'-/()àâçéèêëîïôùûü…"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main(path):
    out = {}
    dev = None
    for line in open(path, encoding="utf-8"):
        p = line.rstrip("\n").split(";")
        if p[0] == "DEV":
            dev = p[1] if len(p) == 2 else None
        elif p[0] == "DBGH" and dev:
            out[dev] = {
                "width": int(p[1]), "small": p[2] == "true", "tiny": p[3] == "true",
                "vector": p[4] == "true", "windline_room": int(p[5]), "arrow": int(p[6]),
                "ascent": int(p[7]), "fonts": {},
            }
        elif p[0] == "DBGF" and dev in out:
            widths = [int(x) for x in p[3].split(",")]
            assert len(widths) == len(CHARS), (dev, p[1], len(widths))
            out[dev]["fonts"][p[1]] = {"height": int(p[2]), "w": dict(zip(CHARS, widths))}
    dest = os.path.join(ROOT, "data", "font_metrics.json")
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    print(f"{len(out)} montres -> {dest}")


if __name__ == "__main__":
    main(sys.argv[1])
