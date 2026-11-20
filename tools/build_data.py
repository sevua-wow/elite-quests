#!/usr/bin/env python3
"""Génère Data.lua à partir d'un CSV de quêtes.

Colonnes (en-tête obligatoire, séparateur virgule ou point-virgule) :
  id,name_enUS,name_frFR,level,minLevel,zone,continent,faction,elite,group,pre,preAny,npc,mapId,x,y,note
- pre / preAny : IDs séparés par des espaces ou des "|"
- elite : 1/0, true/false, oui/non
Usage : python3 build_data.py quetes.csv ../Data.lua
"""
import csv
import sys


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def ids(s):
    return [int(x) for x in s.replace("|", " ").replace(",", " ").split() if x.strip()]


def main(src, dst):
    with open(src, newline="", encoding="utf-8-sig") as f:
        sample = f.read(4096)
        f.seek(0)
        dialect = csv.Sniffer().sniff(sample, delimiters=",;")
        rows = list(csv.DictReader(f, dialect=dialect))

    out = ["local _, ns = ...", "", "-- Fichier généré par tools/build_data.py, ne pas éditer à la main.", "ns.Quests = {"]
    for r in sorted(rows, key=lambda r: int(r["id"])):
        g = lambda k: (r.get(k) or "").strip()
        fields = []
        en, fr = g("name_enUS"), g("name_frFR")
        names = []
        if en:
            names.append("enUS = " + lua_str(en))
        if fr:
            names.append("frFR = " + lua_str(fr))
        fields.append("name = { " + ", ".join(names) + " }")
        for k in ("level", "minLevel", "group", "mapId"):
            if g(k):
                fields.append(f"{k} = {int(g(k))}")
        for k in ("x", "y"):
            if g(k):
                fields.append(f"{k} = {float(g(k))}")
        for k in ("zone", "continent", "npc", "note"):
            if g(k):
                fields.append(f"{k} = {lua_str(g(k))}")
        if g("faction") in ("Alliance", "Horde"):
            fields.append(f'faction = "{g("faction")}"')
        if g("elite").lower() in ("1", "true", "oui", "yes", "x"):
            fields.append("elite = true")
        for k in ("pre", "preAny"):
            if ids(g(k)):
                fields.append(f"{k} = {{ " + ", ".join(map(str, ids(g(k)))) + " }")
        out.append(f"    [{int(r['id'])}] = {{ " + ", ".join(fields) + " },")
    out.append("}")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"{len(rows)} quêtes écrites dans {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
