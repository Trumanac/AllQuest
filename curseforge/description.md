**Summary (short):** AllQuest is a lightweight, modular quest-giver tracker for the WoW Forever client. It places ! markers on your world map and minimap for quests you can actually pick up - no bloated trackers, no guides, just clean quest discovery.

---

# AllQuest

Find every quest worth picking up, right on the map. AllQuest shows a **!** marker for each quest giver that has a quest *you* can accept - filtered for your level, race, class, completed quests, prerequisites, professions, reputation and the current holidays. It doesn't track your active quests or tell you how to do them. It answers one question: **"what quests are available around me?"**

It is fully self-contained: it ships with its own quest database and needs no other addon.

## Features

**Markers**
- World map and minimap markers for quest givers (NPCs and objects)
- **Dungeon quests** shown at the dungeon entrance, tagged **D**
- **Dropped-item quests** shown where the item drops, tagged **i**
- Holiday quests appear only while the holiday is running (read from the in-game calendar)
- Works with **OpenMap**: markers sit correctly on its seamless zoomable map, and zooming in loads the whole continent so nothing pops in as you pan
- Optional **"only my current zone"** mode
- Several givers on the same spot? The hover panel cycles through them
- Optional zoom safeguard: with a low frame rate, far markers are hidden while you zoom the seamless map

**Know at a glance**
- Marker colour follows the game's own difficulty scale: red (5+ above you), orange (3-4), yellow (close to your level), green (below), grey (trivial), blue (repeatable); faded while you are too low level to accept it
- **Colour-blind palette** plus an optional **+3 / -2 level number** under each marker, for when colour isn't enough
- Quest-type letters on the marker: **C** class, **D** dungeon, **E** world event, **G** group, **H** heroic, **i** dropped item, **L** legendary, **P** PvP, **R** raid, **S** escort, **T** profession
- Hover a marker (world map or minimap) for a panel with the giver, each quest's level and name, its type, level / class / skill / reputation requirements, and for item quests what drops it and how often
- Group quests show the suggested group size when it is known
- Hover the AllQuest button on the map or minimap for a colour and letter key

**Click a marker**
- **Left-click:** set a waypoint (uses TomTom if you have it, otherwise the game's map pin)
- **Right-click:** hide a quest or a whole giver; bring them back anytime from the options

**Filters**
- A **quest-type filter button** on the world map: switch Group, Class, PvP, Raid, Heroic, Legendary, Escort, Profession, dungeon, dropped-item, repeatable and holiday quests on or off (can be hidden)
- Show quests up to X levels above you (or every level), hide grey quests, repeatable quests on/off
- Hide quests that need a profession skill or reputation you don't have (each can be switched off)
- Minimap markers for every nearby zone, not just the one you stand in

**Settings made simple**
- **Presets:** Minimal, Detailed, Show All - or save your own under any name and load it from a dropdown
- A short basic page, and an **Advanced** section for every option
- **Profiles** per character, and **export / import** of your settings as a text string
- Translated into **German, French and Spanish** (first drafts - corrections welcome)
- Minimap button (drag, lock, hide), world map on/off button, option to hide Blizzard's objective tracker

**Learns as you play:** if a quest giver offers a quest the built-in database doesn't know, AllQuest remembers it and shows it from then on.

## Commands
`/allquest` or `/aq` opens the options.
`/aq preset <name>` loads a preset, `/aq profile <name>` switches profile, `/aq restore` un-hides everything, `/aq toggle` turns markers on/off, `/aq all`, `/aq above <n>`, `/aq low`, `/aq minimap`, `/aq tracker`, `/aq events`, `/aq status`.

## Notes
- Quest and NPC names in the database are English. The built-in database is a snapshot; quests added later are picked up by the learning feature.
- Quest availability is worked out from the quest data (levels, races, classes, prerequisites, skills, reputation). A few hidden conditions can't be known, so an occasional marker may not be takeable.
- Open source (GPL-3.0). Bug reports and suggestions welcome.
