**Summary (short):** AllQuest puts a ! on your world map and minimap for every quest you can actually pick up right now - colour-coded by difficulty, filtered for your character, and nothing else. No tracker, no guide, no clutter.

---

# AllQuest - see every quest that's waiting for you

Ever run through a zone and only later find out you walked right past three quests? AllQuest fixes that. It marks each quest giver who has something **you** can accept, and hides everything you can't: wrong level, wrong race or class, already done, missing prerequisite, missing profession or reputation, or a holiday that isn't running.

It doesn't track your active quests or tell you how to complete them. It answers one question: **"what quests are available around me?"** - and it works out of the box, with its own built-in quest database and no other addon required.

## At a glance

- **Smart markers** on the world map *and* the minimap, only for quests available to your character
- **Difficulty colours** that match the game's own scale (red / orange / yellow / green / grey, blue for repeatables)
- **Quest-type letters** on each marker: **G** group, **D** dungeon, **R** raid, **P** PvP, **C** class, **T** profession, **H** heroic, **L** legendary, **S** escort, **E** world event, **i** dropped item
- **Rich hover panel**: giver, every quest's level and name, type, requirements, what drops a quest-starting item, and the quest before and after it in a chain
- **Quest list** with search, sorting (level, name, distance, zone) and type filters; click a row for a waypoint
- **New-quest notice**: a chat message when a level-up or a turned-in quest opens up new quests (can be switched off)
- **Click a marker** to set a waypoint (**Shift-click** points the arrow at it); **right-click** to hide a quest, a quest chain, a giver or a whole zone; bring them back from the options
- **Plays nicely with Quest Pilot and TomTom:** by default a click only moves the arrow when nothing else is using it, so it never hijacks your guided route. Choose "always move the arrow" or "mark the map only" in the options
- **Quick presets** (Minimal, Detailed, Show All) - or save your own

## Quests the usual map misses

- **Dungeon quests** appear at the dungeon entrance, so you know a quest is waiting inside
- **Dropped-item quests** appear where the item drops, with who drops it and how often
- **Holiday quests** show up only while the holiday is actually running (read from the in-game calendar)
- **Group quests** are labelled, with the suggested group size when known
- **Learns as you play**: if a giver offers a quest the built-in database doesn't know, AllQuest remembers it from then on

## Made for a seamless map (OpenMap)

AllQuest works with **OpenMap**. Markers sit correctly on its zoomable, borderless map, and zooming in loads the whole continent so nothing pops in as you pan. If your frame rate dips while zooming, an optional safeguard hides far-away markers until the view settles. Several givers on one spot? The hover panel cycles through them.

## Yours to tune

- Show quests up to **X levels above you** (the default of 4 covers yellow and orange), or every level
- Hide grey quests, repeatables, or quests needing a skill or reputation you don't have
- A **quest-type filter button** on the world map to switch whole categories on and off - hide it if you don't want it
- **"Only my current zone"** mode for a cleaner map
- **Colour-blind palette**, plus an optional **+3 / -2** difficulty number under each marker for when colour isn't enough
- **Profiles** per character, and **export / import** of your settings as a text string
- **Display options:** three marker shapes, an optional dark outline, marker opacity, text size on markers and the size of the quest panel
- Marker size, minimap button, and an option to hide Blizzard's objective tracker
- A short basic page, with everything else tucked under **Advanced**
- Translated into **German, French and Spanish** (first drafts - corrections welcome)

## Getting started

Install, log in, open the world map - the markers are already there. Type `/aq` (or right-click the AllQuest button on the map or minimap) for options.

**Useful commands:** `/aq list` opens the quest list - `/aq preset <name>` loads a preset - `/aq profile <name>` switches profile - `/aq toggle` turns markers on/off - `/aq restore` un-hides everything hidden - `/aq status` shows what's loaded and how old the quest data is.

## Good to know

- Quest and NPC names in the database are English. The database is a snapshot, so quests added by later patches are picked up by the learning feature as you meet their givers.
- Availability is worked out from the quest data (levels, races, classes, prerequisites, skills, reputation). A few hidden conditions can't be known, so an occasional marker may not be takeable.
- Free and open source (GPL-3.0). Bug reports and suggestions are very welcome.
