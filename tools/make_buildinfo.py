#!/usr/bin/env python3
"""Genere source/BuildInfo.mc (ignore par git) : version de l'app et identifiants Google Analytics.

A lancer avant chaque compilation de version :
  tools/make_buildinfo.py

- Version : lue dans manifest-public.xml (les deux manifestes doivent avoir la meme).
- Google Analytics : fichier ~/.windspot_ga, deux lignes : identifiant de mesure (G-...) puis
  cle « Measurement Protocol API secret ». Sans ce fichier, les statistiques sont desactivees
  (GA_ID vide) et le cadran n'envoie rien.
La cle se retrouve forcement dans l'app publiee ; elle reste seulement hors du depot public.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def manifest_version(name):
    s = open(os.path.join(ROOT, name), encoding="utf-8").read()
    return re.search(r'<iq:application[^>]*\sversion="([^"]+)"', s, re.S).group(1)


def main():
    version = manifest_version("manifest-public.xml")
    beta = manifest_version("manifest.xml")
    if beta != version:
        raise SystemExit(f"versions differentes : manifest.xml {beta}, manifest-public.xml {version}")
    ga_id, ga_secret = "", ""
    path = os.path.expanduser("~/.windspot_ga")
    if os.path.exists(path):
        lines = [l.strip() for l in open(path, encoding="utf-8") if l.strip()]
        if len(lines) >= 2:
            ga_id, ga_secret = lines[0], lines[1]
    for v in (version, ga_id, ga_secret):
        if '"' in v or "\\" in v:
            raise SystemExit("caractere interdit dans la version ou les identifiants")
    out = f'''// Genere par tools/make_buildinfo.py : ne pas modifier, ne pas publier (voir .gitignore)
import Toybox.Lang;

(:background) const APP_VERSION = "{version}";
(:background) const GA_ID = "{ga_id}";
(:background) const GA_SECRET = "{ga_secret}";
'''
    open(os.path.join(ROOT, "source", "BuildInfo.mc"), "w", encoding="utf-8").write(out)
    print(f"source/BuildInfo.mc : version {version}, statistiques {'activees' if ga_id else 'DESACTIVEES (pas de ~/.windspot_ga)'}")


if __name__ == "__main__":
    main()
