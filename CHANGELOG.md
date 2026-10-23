# Changelog

## 1.0.1-beta
- Quest list is now a sortable table: Level, Quest, Giver, Zone, Distance, XP, Money and Rewards columns. Click a header
  to sort (click again to flip the direction); the Columns button switches columns on and off. Choices are remembered.
- Quest list: the sort menu lists every column, has an ascending / descending button, and unknown values sort last.
- Fix: drop-downs in the settings (presets, marker style, waypoints, restore, profiles) and the quest list showed nothing when
  clicked, because the game's menu opened behind the window. They now use AllQuest's own menu, which always opens on top.
- Quest list: a quest is listed once per giver (at the spot nearest you) instead of once per spawn or drop spot.
- Quest list: a gear button in the title bar opens the settings; the level column header is shortened to "Lvl".
- Public API (version 2): quests carry xp, money and reward item ids, and `AllQuestAPI.GetRewards(questId)` returns them.
- Hovering a reward icon in the quest list shows the game's own item tooltip (weapon, potion ...) instead of the quest panel.
- XP, money and reward items are learned from the quest windows you open in game (and shown in the row tooltip).
  The data export tool can also bundle them.

## 1.0.0 - first release
- Fix: the quest list and settings windows no longer blend when dragged over each other; clicking one brings it to the front.
- Everything from 0.x: markers on the world map and minimap, quest list, presets and profiles, hide lists, quest-type
  filter, waypoints that coexist with other arrow addons, display options, three languages, OpenMap support.

## 0.11.2
- Fix: the new-quest notice now waits a moment after a level-up or turn-in, so quests the game had not yet flagged as
  completed no longer hide the quests they unlock.
- Fix: the options and quest list windows open above the world map.
- CurseForge description refreshed.

## 0.11.1
- Waypoints work alongside Quest Pilot and TomTom: a click moves the arrow only when nothing else is using it
  (Shift-click always does); only one AllQuest waypoint exists at a time and it clears itself on arrival.
  The behaviour can be changed under Waypoints (smart / always move the arrow / mark the map only).
- Public API (`AllQuestAPI`) for other addons: available quests per map, nearest quests, hidden check, refresh callback.
- Settings window is wider, long labels wrap, and the profile / export / import buttons sit on their own lines.
- Quest data refreshed.

## 0.11.0
- Quest list window (`/aq list`, a button on the world map, middle-click on the minimap button): search, sort by
  level / name / distance / zone, filter by zone range and quest type, click a row for a waypoint.
- Chat notice when a level-up or a turned-in quest makes new quests available (can be switched off).
- The quest panel names the quest before and after in a chain (one line; can be switched off).
- Blacklist: hide a single quest, a quest and everything that follows it, a giver, or a whole zone; restore them one by one.
- Display options: marker shape (exclamation, diamond, round), dark outline, opacity, text size, quest panel size.
- Quest titles follow the client language when the game has them.
- More translated text (German, French, Spanish).

## 0.10.1
- Fix: a marker the map released on its own could stay invisible; it is drawn again now.
- Group sizes are also read with the older quest log API.
- New: Reset all settings button; the map and minimap button tooltips show how many quests are available in your zone.
- Pop-up texts are translated.

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
