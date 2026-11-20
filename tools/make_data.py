#!/usr/bin/env python3
"""Génère Data.lua pour Forever Elites.

Sources :
  --list     liste des quêtes élites exportée de wowhead.com/forever (obligatoire)
  --questie  questie.json produit par tools/questie_extract.lua (prérequis + coordonnées)
  --pages    pages de quêtes Wowhead déjà récupérées (repli pour les quêtes absentes de Questie)

Usage :
  python3 make_data.py --list forever_elites_list.json --questie questie.json \
      --pages forever_quest_pages.json --out ../Data.lua
"""
import argparse
import json

CONTINENTS = {
    0: "Eastern Kingdoms", 1: "Kalimdor", 2: "Dungeons", 3: "Raids",
    4: "Class quests", 5: "Professions", 9: "World events", -2: "Miscellaneous",
}
WOWHEAD_SIDES = {1: "Alliance", 2: "Horde", "Alliance": "Alliance", "Horde": "Horde"}
ALLIANCE_RACES = 1 | 4 | 8 | 64   # humain, nain, elfe de la nuit, gnome
HORDE_RACES = 2 | 16 | 32 | 128   # orc, mort-vivant, tauren, troll


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def faction_from_races(mask):
    a, h = bool(mask & ALLIANCE_RACES), bool(mask & HORDE_RACES)
    if a and not h:
        return "Alliance"
    if h and not a:
        return "Horde"
    return None


def load(path):
    if not path:
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", required=True)
    ap.add_argument("--questie")
    ap.add_argument("--pages")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    listing = load(args.list)
    questie = load(args.questie)
    pages = load(args.pages)
    zones = listing["zoneNames"]

    quests = {}
    for e in listing["elites"]:
        quests[e["id"]] = {
            "name": e["name"], "level": e.get("level"), "minLevel": e.get("reqlevel"),
            "zone": zones.get(f"{e['cat2']}.{e['cat']}"),
            "continent": CONTINENTS.get(e["cat2"], "Other"),
            "faction": WOWHEAD_SIDES.get(e.get("side")), "elite": True,
            "_cat2": e["cat2"],
        }

    stats = {"questie": 0, "wowhead": 0, "none": 0}
    queue = list(quests)
    seen = set(queue)
    while queue:
        qid = queue.pop(0)
        q = quests.setdefault(qid, {})
        src = questie.get(str(qid))
        page = pages.get(str(qid))
        pre, pre_any = [], []
        if src:
            stats["questie"] += 1
            q.setdefault("name", src["name"])
            if not q.get("level"):
                q["level"] = src.get("level")
            if not q.get("minLevel"):
                q["minLevel"] = src.get("reqlevel")
            if "faction" not in q:
                q["faction"] = faction_from_races(int(src.get("races") or 0))
            for k in ("npc", "areaId", "x", "y"):
                if src.get(k) is not None:
                    q[k] = src[k]
            pre = src.get("group") or []
            pre_any = src.get("single") or []
            if len(pre_any) == 1:  # une seule alternative = prérequis obligatoire
                pre, pre_any = pre + pre_any, []
        elif page:
            stats["wowhead"] += 1
            q.setdefault("name", page.get("name") or f"#{qid}")
            if not q.get("level"):
                q["level"] = page.get("level")
            if not q.get("minLevel"):
                q["minLevel"] = page.get("reqlevel")
            if "faction" not in q:
                q["faction"] = WOWHEAD_SIDES.get(page.get("side"))
            for k in ("npc", "areaId", "x", "y"):
                if page.get(k) is not None:
                    q[k] = page[k]
            pre = [i for r in page.get("reqs", []) if r["head"].lower() == "requires" for i in r["ids"]]
        else:
            stats["none"] += 1
            q.setdefault("name", f"#{qid}")
        if pre:
            q["pre"] = pre
        if pre_any:
            q["preAny"] = pre_any
        for p in pre + pre_any:
            if p not in seen:
                seen.add(p)
                queue.append(p)

    # Zones connues : AreaTable ID -> (catégorie Wowhead, nom). Les zones du monde priment sur les donjons.
    zone_by_id = {}
    for key, name in zones.items():
        cat2, cat = key.split(".", 1)
        if cat2 in ("0", "1", "2") and (int(cat) not in zone_by_id or zone_by_id[int(cat)][0] == "2"):
            zone_by_id[int(cat)] = (cat2, name)
    area_names = {k: v[1] for k, v in zone_by_id.items() if v[0] in ("0", "1")}

    # Les quêtes élites de zone sont rangées là où se déroule leur objectif, pas chez leur donneur
    moved = 0
    for qid, q in quests.items():
        src = questie.get(str(qid)) or {}
        obj_zone = src.get("objZone")
        confident = (src.get("objShare") or 0) >= 0.6
        if q.get("elite") and q.get("_cat2") in (0, 1) and obj_zone in zone_by_id and confident:
            cat2, name = zone_by_id[obj_zone]
            if name != q.get("zone"):
                q["zone"], q["continent"] = name, CONTINENTS[int(cat2)]
                moved += 1
    print(f"{moved} quêtes élites rangées dans la zone de leur objectif")

    for q in quests.values():
        start = area_names.get(q.get("areaId"))
        if not q.get("zone") and start:
            q["zone"] = start
        elif start and start != q.get("zone"):
            q["startZone"] = start

    out = [
        "local _, ns = ...",
        "",
        "-- Généré par tools/make_data.py. Ne pas éditer à la main.",
        "-- Sources : liste des élites de wowhead.com/forever ; prérequis et donneurs de",
        "-- QuestieDB (https://github.com/Questie/QuestieDB, GPLv3), repli sur les pages Wowhead.",
        f"-- {sum(1 for q in quests.values() if q.get('elite'))} quêtes élites, {len(quests)} quêtes au total.",
        "ns.Quests = {",
    ]
    for qid in sorted(quests):
        q = quests[qid]
        f = [f"name = {lua_str(q['name'])}"]
        for k in ("level", "minLevel"):
            if q.get(k):
                f.append(f"{k} = {int(q[k])}")
        if q.get("areaId") and q.get("x") is not None:
            f.append(f"areaId = {int(q['areaId'])}, x = {round(float(q['x']), 1)}, y = {round(float(q['y']), 1)}")
        for k in ("zone", "continent", "faction", "npc", "startZone"):
            if q.get(k):
                f.append(f"{k} = {lua_str(q[k])}")
        if q.get("elite"):
            f.append("elite = true")
        for k in ("pre", "preAny"):
            if q.get(k):
                f.append(f"{k} = {{ " + ", ".join(map(str, q[k])) + " }")
        out.append(f"    [{qid}] = {{ " + ", ".join(f) + " },")
    out.append("}")
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print(f"{len(quests)} quêtes écrites dans {args.out} — sources : {stats}")


if __name__ == "__main__":
    main()
