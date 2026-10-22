# AllQuest

Lightweight quest-giver tracker for the WoW Forever client (Interface 16001): `!` markers on the world map and
minimap for quests your character can pick up. Self-contained quest database, OpenMap-aware.

See `curseforge/description.md` for the feature list, `CHANGELOG.md` for versions and `NOTICE.md` for credits and licensing.

## Layout
- `Core.lua` settings, presets, slash commands - `Data.lua` + `Data/DB_*.lua` quest database and filtering
- `Pins.lua` world map markers - `Minimap.lua` minimap markers and button - `Options.lua` settings UI
- `Events.lua` holidays - `Learn.lua` learns unknown quests - `Tracker.lua` hides the Blizzard tracker
- `devtools/` the in-game export addon and `build_data.py`, which regenerate `Data/DB_*.lua` (not shipped)

## Refreshing the data
Run `/aqdump` in game with the export addon enabled, `/reload`, then
`python devtools/build_data.py <SavedVariables/AllQuestDump.lua> Data`.

## License
GPL-3.0 (see `LICENSE`, and `NOTICE.md` for the data's origin).
