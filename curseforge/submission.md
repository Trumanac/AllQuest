# CurseForge submission sheet (AllQuest 1.0.0)

Fill these in on the "Create project" page (https://www.curseforge.com/project/create) for World of Warcraft.

| Field | Value |
|---|---|
| Project name | AllQuest |
| Summary (190 characters) | AllQuest puts a ! on your WoW Forever world map and minimap for every quest you can pick up right now - colour-coded by difficulty, filtered for your character, with a searchable quest list. |
| Category | Quests & Leveling (primary); Map & Minimap |
| License | GNU General Public License v3.0 |
| Logo | `curseforge/logo.png` (400x400) |
| Description | paste `curseforge/description.md` (the editor takes markdown / HTML; check the headings render) |
| Source / Issues links | https://github.com/Trumanac/AllQuest (issues: https://github.com/Trumanac/AllQuest/issues) |
| Screenshots | 8-10 cropped pictures from `devtools/shots` - put the map with the quest panel first |

## First file
- File: `.release/AllQuest-1.0.0.zip` (built by the release step; folder `AllQuest/` inside)
- Display name: AllQuest 1.0.0
- Release type: **Beta** for the first upload (switch to Release after a few days of feedback)
- Game version: the WoW Forever / Classic beta build matching Interface 16001 (pick the nearest entry the dropdown offers)
- Changelog: paste the "1.0.0" section of `CHANGELOG.md`

## Before pressing submit
- The zip contains no developer files (`devtools/`, screenshots, sources) - checked by the release step.
- Project review is by the CurseForge moderators; replies arrive by email / on the project page.
- If the packager is used instead of a manual upload, `.pkgmeta` is already set up (package-as AllQuest, ignores the rest).
