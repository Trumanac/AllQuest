# Changelog

## 0.10.0
- Click a marker to set a waypoint (TomTom if installed, otherwise the game's map pin); right-click to hide a
  quest or a giver. Hidden items can be restored one by one or all at once in the options.
- Quest-type filter: a small button on the world map (and matching options) switches Group, Class, PvP, Raid,
  Heroic, Legendary, Escort and Profession quests, plus dungeon / dropped-item / repeatable / holiday quests, on and off.
- Profiles: every character can use its own settings profile. Settings can be exported and imported as text.
- Several givers on the same spot: the hover panel cycles through them.
- Group quests show the suggested group size when known (learned from your quest log; the data export can add more).
- Optional zoom safeguard for OpenMap: far markers are hidden while zooming only if the frame rate drops.
- `/aq status` shows the profile, preset and the age of the quest data; a one-time notice appears after a game patch.
- Translations: German, French and Spanish (first drafts).
- `/aq profile [name]`, `/aq restore`.

## 0.9.0 - first public beta
- Quest-giver markers on the world map and minimap, filtered for your character (level, race, class, completed
  quests, prerequisites, profession skill, reputation, holidays).
- Dungeon quests shown at the dungeon entrance; dropped-item quests shown where the item drops.
- Difficulty colours matching the game's scale, colour-blind palette, optional +/- level numbers,
  quest-type letters (Class, Dungeon, Event, Group, Heroic, Item, Legendary, PvP, Raid, Escort, Profession).
- Hover panel with giver, type, requirements and what drops an item; minimal or detailed.
- Presets (Minimal, Detailed, Show All) plus your own named presets; Advanced section for every option.
- "Only my current zone" mode; OpenMap support (whole-continent markers while zoomed in).
- Minimap button, optional hiding of Blizzard's objective tracker, learns quests missing from its database.
