#!/usr/bin/env python3
"""Genere resources/models/models.json : numero de piece Garmin -> identifiant de montre (fr970...).

La montre ne connait que son numero de piece (DeviceSettings.partNumber, ex. 006-B4315-00) ;
cette table permet d'envoyer un nom lisible dans les statistiques. A relancer quand on ajoute
des montres (data/devices.txt) ou qu'on change de SDK.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEVICES = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Devices")


def main():
    ids = [l.split()[0] for l in open(os.path.join(ROOT, "data", "devices.txt"))
           if l.strip() and not l.startswith("#")]
    table = {}
    for dev in ids:
        j = json.load(open(os.path.join(DEVICES, dev, "compiler.json"), encoding="utf-8"))
        for p in j.get("partNumbers", []):
            if p.get("number"):
                table[p["number"]] = dev
    out = os.path.join(ROOT, "resources", "models")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "models.json"), "w", encoding="utf-8") as f:
        json.dump(table, f, sort_keys=True, separators=(",", ":"))
    with open(os.path.join(out, "models.xml"), "w", encoding="utf-8") as f:
        f.write('<resources>\n    <jsonData id="Models" filename="models.json"/>\n</resources>\n')
    print(f"{len(table)} numeros de piece pour {len(ids)} montres -> resources/models/models.json")


if __name__ == "__main__":
    main()
