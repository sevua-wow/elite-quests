# EliteQuests

Every elite quest of **WoW Forever**, zone by zone, with its full prerequisite chain and your progress — in the spirit of Attune.

## Features

- **Elite quest list** grouped by continent and zone (dungeons, class quests, professions and world events have their own sections), each zone with its icon and a done/total counter.
- **Prerequisite chain** for every elite: required level, quests to complete ("all of" / "one of"), quest giver and zone.
- **Progress** per character: completed, in quest log, available or locked, with progress bars.
- **Tree view**: the whole chain as a graph. Drag to move, wheel to scroll, Ctrl+wheel to zoom.
- **Ctrl-click** a quest to drop a pin on the world map at its quest giver; **Shift-click** to link it in chat.
- Filters: search box, hide completed steps, show both factions, per-character view.
- Elite quests are filed under the zone where their **objective** takes place, not where the giver stands.
- Interface in English, French, German, Spanish (EU and Latin America), Italian, Brazilian Portuguese, Russian, Korean and Simplified and Traditional Chinese. Zone, dungeon and class names come from your game client, in its language. Quest names are translated only when your client already has the quest in its cache; otherwise they stay in English. NPC names stay in English.

## Commands

| Command | Effect |
|---|---|
| `/eq` | Open / close the window |
| `/eq minimap` | Show / hide the minimap button |
| `/eq reset` | Reset the window position |
| `/eq icons` | List zones whose icon was not found in the client |
| `/eq demo` | Toggle demo mode (fictitious data, preview only) |

## Known limits

- 347 elite quests are listed. About 80 elites specific to WoW Forever have no known prerequisites yet: they appear without a chain.
- Some quest givers have no coordinates, so Ctrl-click cannot pin them.

Corrections are welcome: quest ID, what is wrong, and what you saw in game.

## Data sources and license

- Prerequisites, quest givers, coordinates and objective zones come from **QuestieDB** (https://github.com/Questie/QuestieDB, GPLv3).
- The list of elite quests comes from the WoW Forever section of Wowhead.
- The scripts that rebuild `Data.lua` from those sources are kept in a separate project.

EliteQuests is free software released under the **GNU General Public License v3** (see `LICENSE`). It is not affiliated with Blizzard Entertainment, Wowhead, Questie or Attune.

---

**Français (Elite Quêtes)** — Toutes les quêtes élites de WoW Forever, zone par zone, avec leur chaîne de prérequis et votre progression. Vue liste et vue arbre, Ctrl-clic pour poser une épingle sur la carte, `/eq` pour ouvrir. Données issues de QuestieDB (GPLv3) et de Wowhead ; addon sous licence GPLv3.
