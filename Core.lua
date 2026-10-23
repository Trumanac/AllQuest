local AddOn, AQ = ...

-- Settings (saved in AllQuestDB):
--   enabled         pins on the world map on/off
--   showAll         ignore the "levels above" limit and show every quest level
--   levelsAbove     show quests up to this many levels above the character (when showAll is off)
--   hideLowLevel    hide quests that are grey (trivial) for the character
--   showRepeatable  show repeatable quests
--   showLevelText   print the highest quest level on each pin
--   iconScale       pin size multiplier
-- Text for the interface: AQ.L["English text"] gives the translation for the client's language (Locales.lua),
-- or the English text itself.
AQ.L = setmetatable({}, { __index = function(_, key) return key end })

AQ.defaults = {
    enabled = true,
    colorByLevel = true,     -- tint markers by difficulty (red/orange/yellow/green/grey)
    colorblind = false,      -- colour-blind friendly palette (see Pins.lua)
    difficultyText = false,  -- difficulty as a number (+3, -2) on markers and in the quest panel, for when colour is not enough
    minimapPins = true,      -- also draw markers on the minimap
    minimapScale = 1.0,
    hideTracker = false,     -- hide Blizzard's objective tracker
    learnQuests = true,      -- remember quests the bundled database lacks when a giver offers them
    showFilterButton = true, -- small quest-type filter button on the world map
    hiddenTypes = {},        -- quest types switched off in the filter: type name -> true
    zoomSafeguard = true,    -- OpenMap: hide far markers while zooming when the frame rate drops
    notifyNewQuests = true,  -- chat message when a level-up or a turned-in quest makes new quests available
    showChainInfo = true,    -- one line in the quest panel: the quest before and after in its chain
    showListButton = true,   -- button on the world map that opens the quest list
    markerStyle = "exclaim", -- marker shape: exclaim, diamond, round
    markerOutline = false,   -- dark outline behind markers, for contrast
    markerAlpha = 1.0,       -- marker opacity
    labelSize = 10,          -- size of the text under and on markers
    tooltipScale = 1.0,      -- size of the quest panel
    waypointMode = "smart",  -- clicking a marker: smart (keep an arrow another addon is using), arrow, marker (map only)
}

-- Kept once for the whole account (not per profile).
--   learned      quests learned in game (see Learn.lua)
--   presets      presets saved by the player: name -> copy of the preset keys
--   ignored      quests and givers the player hid: { quests = { [id] = name }, givers = { ["n123"] = name } }
--   groupSizes   suggested group size per quest, learned from the quest log
--   profiles     settings profiles: name -> settings;  assign: "Name-Realm" -> profile name
AQ.sharedDefaults = { learned = {}, presets = {}, ignored = {}, groupSizes = {}, profiles = {}, assign = {},
    advancedOpen = false }

-- Presets. They set the "how much do I see" settings below; everything else (colours, minimap button,
-- tracker ...) is a personal choice a preset leaves alone. The Detailed preset is also the first-load default.
--   showAll          ignore the "levels above" limit and show every quest level
--   levelsAbove      show quests up to this many levels above the character (when showAll is off)
--   hideLowLevel     hide quests that are grey (trivial) for the character
--   showRepeatable   show repeatable quests
--   showEventQuests  holiday quests, shown only while the holiday is on
--   showDungeonQuests / showDropQuests   quests given inside dungeons / started by dropped items
--   checkSkills / checkReputation        hide quests needing a profession or reputation you lack
--   showTypeTags     small letter on the world map marker: G group, D dungeon, R raid, P pvp ...
--   showLevelText    print the highest quest level under each marker
--   showTooltips / tooltipDetails        hover panel on world map markers / with full details
--   minimapTooltips  hover panel on minimap markers
--   iconScale        marker size multiplier
--   currentZoneOnly  only the zone you are standing in (world map and minimap)
--   wholeContinent   OpenMap zoomed in: markers of the whole continent (off: viewed zone and yours)
AQ.presetKeys = { "showAll", "levelsAbove", "hideLowLevel", "showRepeatable", "showEventQuests", "showDungeonQuests",
    "showDropQuests", "checkSkills", "checkReputation", "showTypeTags", "showLevelText", "showTooltips",
    "tooltipDetails", "minimapTooltips", "iconScale", "wholeContinent", "currentZoneOnly" }
AQ.presetList = {
    { key = "minimal", name = "Minimal",
      tip = "Only quests up to 2 levels above you (the yellow ones), plain markers, a short hover panel (name and level). No repeatable, holiday, dungeon or dropped-item quests.",
      values = { showAll = false, levelsAbove = 2, hideLowLevel = true, showRepeatable = false, showEventQuests = false,
        showDungeonQuests = false, showDropQuests = false, checkSkills = true, checkReputation = true,
        showTypeTags = false, showLevelText = false, showTooltips = true, tooltipDetails = false,
        minimapTooltips = false, iconScale = 0.9, wholeContinent = false, currentZoneOnly = false } },
    { key = "detailed", name = "Detailed",
      tip = "The recommended setup: quests up to 4 levels above you (yellow and orange, not the red ones), every quest kind, type tags and a full hover panel.",
      values = { showAll = false, levelsAbove = 4, hideLowLevel = true, showRepeatable = true, showEventQuests = true,
        showDungeonQuests = true, showDropQuests = true, checkSkills = true, checkReputation = true,
        showTypeTags = true, showLevelText = false, showTooltips = true, tooltipDetails = true,
        minimapTooltips = true, iconScale = 1.0, wholeContinent = true, currentZoneOnly = false } },
    { key = "all", name = "Show All",
      tip = "Every quest of every level, including grey ones and ones you cannot take yet (skill and reputation requirements are not checked), with levels shown on the markers.",
      values = { showAll = true, levelsAbove = 4, hideLowLevel = false, showRepeatable = true, showEventQuests = true,
        showDungeonQuests = true, showDropQuests = true, checkSkills = false, checkReputation = false,
        showTypeTags = true, showLevelText = true, showTooltips = true, tooltipDetails = true,
        minimapTooltips = true, iconScale = 1.0, wholeContinent = true, currentZoneOnly = false } },
}
for _, preset in ipairs(AQ.presetList) do
    if preset.key == "detailed" then
        for k, v in pairs(preset.values) do AQ.defaults[k] = v end
    end
end

local function SameValue(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 0.001 end
    return a == b
end

local function Wanted(values, key)
    if values[key] ~= nil then return values[key] end
    return AQ.defaults[key]      -- a preset saved before the setting existed
end

local function Matches(values)
    local db = AQ.db
    for _, key in ipairs(AQ.presetKeys) do
        -- with "every level" on, the levels-above number does not matter
        if not (key == "levelsAbove" and db.showAll and values.showAll) and not SameValue(db[key], Wanted(values, key)) then
            return false
        end
    end
    return true
end

-- Sorted names of the presets the player saved.
function AQ.UserPresetNames()
    local names = {}
    for name in pairs(AQ.shared.presets) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

-- The preset the settings match: "builtin", key, name  /  "user", name, name  /  nil (none: unsaved custom settings).
function AQ.CurrentPreset()
    for _, preset in ipairs(AQ.presetList) do
        if Matches(preset.values) then return "builtin", preset.key, preset.name end
    end
    for _, name in ipairs(AQ.UserPresetNames()) do
        if Matches(AQ.shared.presets[name]) then return "user", name, name end
    end
end

local function FindPreset(name)
    local wanted = name:lower()
    for _, preset in ipairs(AQ.presetList) do
        if preset.key == wanted or preset.name:lower() == wanted then return preset.values, preset.name end
    end
    for saved, values in pairs(AQ.shared.presets) do
        if saved:lower() == wanted then return values, saved end
    end
end

-- Apply a built-in preset (by key or name) or a saved one (by name).
function AQ.ApplyPreset(name)
    local values, shown = FindPreset(name or "")
    if not values then
        AQ.Print("no preset called '" .. tostring(name) .. "'.")
        return
    end
    for _, k in ipairs(AQ.presetKeys) do
        AQ.db[k] = Wanted(values, k)
    end
    AQ.SettingsChanged()
end

-- Save the current settings under a name (an existing saved preset of that name is replaced).
function AQ.SavePreset(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    for _, preset in ipairs(AQ.presetList) do
        if preset.name:lower() == name:lower() or preset.key == name:lower() then
            AQ.Print("'" .. name .. "' is a built-in preset - choose another name.")
            return
        end
    end
    for saved in pairs(AQ.shared.presets) do
        if saved:lower() == name:lower() then AQ.shared.presets[saved] = nil end
    end
    local copy = {}
    for _, k in ipairs(AQ.presetKeys) do copy[k] = AQ.db[k] end
    AQ.shared.presets[name] = copy
    AQ.Print("saved preset '" .. name .. "'.")
    AQ.SettingsChanged()
end

function AQ.DeletePreset(name)
    if AQ.shared.presets[name] then
        AQ.shared.presets[name] = nil
        AQ.Print("deleted preset '" .. name .. "'.")
        AQ.SettingsChanged()
    end
end

-- Minimap button settings (LibDBIcon): hide, lock, minimapPos (angle in degrees)
AQ.minimapDefaults = { hide = false, lock = false, minimapPos = 215 }

-- Bundled quest database, filled by Data/DB_*.lua (see Data.lua for the layout).
AQ.DB = { meta = {}, raceMask = {}, quests = {}, npcs = {}, objs = {}, items = {}, dungeons = {}, maps = {} }

function AQ.Print(...)
    print("|cff66ccffAllQuest|r:", ...)
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function FillDefaults(t)
    for k, v in pairs(AQ.defaults) do
        if t[k] == nil then t[k] = type(v) == "table" and {} or v end
    end
    return t
end

local function InitDB()
    AllQuestDB = AllQuestDB or {}
    local S = AllQuestDB
    -- up to 0.9.0 the settings lived in the saved table itself: they become the Default profile
    S.profiles = S.profiles or {}
    if not S.profiles.Default then
        local legacy = {}
        for k in pairs(AQ.defaults) do
            if S[k] ~= nil then legacy[k] = S[k] S[k] = nil end
        end
        S.profiles.Default = legacy
    end
    for k, v in pairs(AQ.sharedDefaults) do
        if S[k] == nil then S[k] = type(v) == "table" and {} or v end
    end
    S.ignored.quests = S.ignored.quests or {}
    S.ignored.givers = S.ignored.givers or {}
    S.ignored.zones = S.ignored.zones or {}
    S.ignored.chains = S.ignored.chains or {}
    if type(S.custom) == "table" then                    -- the single "Custom" slot of 0.8.0 - 0.8.2
        S.presets.Custom = S.presets.Custom or S.custom
    end
    S.custom = nil
    S.dropAllSpots = nil                                 -- setting removed in an earlier version
    S.minimap = S.minimap or {}
    for k, v in pairs(AQ.minimapDefaults) do
        if S.minimap[k] == nil then S.minimap[k] = v end
    end
    AQ.shared = S
    AQ.ProfileUse(S.assign[CharKey()], true)
end

---------------------------------------------------------------------------------------------
-- Profiles: every character uses one named settings profile (Default unless it picked another)

function AQ.ProfileNames()
    local names = {}
    for name in pairs(AQ.shared.profiles) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a == "Default" or b == "Default" then return a == "Default" and b ~= "Default" end
        return a:lower() < b:lower()
    end)
    return names
end

function AQ.ProfileName()
    return AQ.profile
end

-- Switch this character to a profile (an unknown name falls back to Default).
function AQ.ProfileUse(name, quiet)
    local S = AQ.shared
    if not (name and S.profiles[name]) then name = "Default" end
    S.profiles.Default = S.profiles.Default or {}
    AQ.profile = name
    AQ.db = FillDefaults(S.profiles[name])
    S.assign[CharKey()] = name
    if not quiet then
        AQ.Data.InvalidateAll()
        AQ.SettingsChanged()
    end
end

-- A new profile starts as a copy of the settings in use now, and this character switches to it.
function AQ.ProfileCreate(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local S = AQ.shared
    for existing in pairs(S.profiles) do
        if existing:lower() == name:lower() then
            AQ.Print("a profile called '" .. existing .. "' already exists.")
            return
        end
    end
    local copy = {}
    for k, v in pairs(AQ.db) do
        if type(v) == "table" then
            local t = {}
            for kk, vv in pairs(v) do t[kk] = vv end
            copy[k] = t
        else
            copy[k] = v
        end
    end
    S.profiles[name] = copy
    AQ.Print("created profile '" .. name .. "' for this character.")
    AQ.ProfileUse(name)
end

function AQ.ProfileDelete(name)
    local S = AQ.shared
    if name == "Default" or not S.profiles[name] then return end
    S.profiles[name] = nil
    for char, assigned in pairs(S.assign) do
        if assigned == name then S.assign[char] = "Default" end
    end
    AQ.Print("deleted profile '" .. name .. "'.")
    if AQ.profile == name then AQ.ProfileUse("Default") else AQ.SettingsChanged() end
end

---------------------------------------------------------------------------------------------
-- Hidden quests and givers (the ignore list; kept for the whole account)

function AQ.IgnoreQuest(id, name)
    AQ.shared.ignored.quests[id] = name or true
    AQ.Print(("hid quest: %s (restore it in the options)"):format(tostring(name or id)))
    AQ.SettingsChanged()
end

function AQ.IgnoreGiver(key, name)
    AQ.shared.ignored.givers[key] = name or true
    AQ.Print(("hid giver: %s (restore it in the options)"):format(tostring(name or key)))
    AQ.SettingsChanged()
end

function AQ.IgnoreZone(uiMapId, name)
    AQ.shared.ignored.zones[uiMapId] = name or true
    AQ.Print(("hid zone: %s (restore it in the options)"):format(tostring(name or uiMapId)))
    AQ.SettingsChanged()
end

-- A chain: the quest and every quest that follows from it.
function AQ.IgnoreChain(id, name)
    AQ.shared.ignored.chains[id] = name or true
    AQ.Data.DirtyIgnored()
    AQ.Print(("hid quest chain from: %s (restore it in the options)"):format(tostring(name or id)))
    AQ.SettingsChanged()
end

local IGNORE_SETS = { quest = "quests", giver = "givers", zone = "zones", chain = "chains" }

-- List of { kind = "quest"|"giver"|"zone"|"chain", key, name }, sorted by name.
function AQ.IgnoredList()
    local list = {}
    for kind, setName in pairs(IGNORE_SETS) do
        for key, name in pairs(AQ.shared.ignored[setName]) do
            local label = type(name) == "string" and name or (kind .. " " .. tostring(key))
            list[#list + 1] = { kind = kind, key = key, name = label }
        end
    end
    table.sort(list, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return a.kind < b.kind
    end)
    return list
end

function AQ.Unignore(kind, key)
    local set = AQ.shared.ignored[IGNORE_SETS[kind]]
    if not set then return end
    set[key] = nil
    if kind == "chain" then AQ.Data.DirtyIgnored() end
    AQ.SettingsChanged()
end

function AQ.RestoreAllIgnored()
    for _, setName in pairs(IGNORE_SETS) do AQ.shared.ignored[setName] = {} end
    AQ.Data.DirtyIgnored()
    AQ.Print("restored everything you hid.")
    AQ.SettingsChanged()
end

---------------------------------------------------------------------------------------------
-- Settings as a text string (to share or move to another account)

local RANGES = { iconScale = { 0.5, 2 }, minimapScale = { 0.5, 2.5 }, levelsAbove = { 0, 60 }, markerAlpha = { 0.3, 1 },
    labelSize = { 8, 16 }, tooltipScale = { 0.7, 1.6 } }
local CHOICES = { markerStyle = { exclaim = true, diamond = true, round = true }, waypointMode = { smart = true, arrow = true, marker = true } }
local EXPORT_PREFIX = "AQ1"

function AQ.ExportString()
    local keys = {}
    for k, v in pairs(AQ.defaults) do
        if type(v) ~= "table" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = { EXPORT_PREFIX }
    for _, k in ipairs(keys) do
        local v = AQ.db[k]
        if type(v) == "boolean" then v = v and "1" or "0" end
        parts[#parts + 1] = k .. "=" .. tostring(v)
    end
    local hidden = {}
    for name in pairs(AQ.db.hiddenTypes) do hidden[#hidden + 1] = name end
    table.sort(hidden)
    if #hidden > 0 then parts[#parts + 1] = "hiddenTypes=" .. table.concat(hidden, ",") end
    return table.concat(parts, ";")
end

-- Returns true and the number of settings read, or false and a reason.
function AQ.ImportString(text)
    text = (text or ""):gsub("%s+", "")
    local prefix = text:match("^([^;]*)")
    if prefix ~= EXPORT_PREFIX then return false, "that is not an AllQuest settings string" end
    local values, count, hidden = {}, 0, nil
    for key, value in text:gmatch(";(%w+)=([^;]*)") do
        local default = AQ.defaults[key]
        if key == "hiddenTypes" then
            hidden = {}
            for name in value:gmatch("[^,]+") do
                for _, t in ipairs(AQ.FilterTypes or {}) do
                    if t[1] == name then hidden[name] = true end
                end
            end
            count = count + 1
        elseif type(default) == "boolean" then
            values[key] = value == "1"
            count = count + 1
        elseif CHOICES[key] then
            if CHOICES[key][value] then values[key] = value count = count + 1 end
        elseif type(default) == "number" and tonumber(value) then
            local n = tonumber(value)
            local range = RANGES[key]
            if range then n = math.max(range[1], math.min(range[2], n)) end
            values[key] = n
            count = count + 1
        end
    end
    if count == 0 then return false, "no settings found in that string" end
    for k, v in pairs(values) do AQ.db[k] = v end
    AQ.db.hiddenTypes = hidden or {}
    AQ.SettingsChanged()
    return true, count
end

-- Every setting of the profile back to its default (hidden quests, saved presets and other profiles stay).
function AQ.ResetSettings()
    for k, v in pairs(AQ.defaults) do
        AQ.db[k] = type(v) == "table" and {} or v
    end
    AQ.Print("settings reset to the defaults.")
    AQ.SettingsChanged()
end

-- The database is a snapshot of one client build: say so once after the game was patched.
function AQ.CheckClientBuild()
    local current = select(2, GetBuildInfo())
    local made = AQ.DB.meta.build
    if not (current and made) or tostring(current) == tostring(made) then return end
    if AQ.shared.noticedBuild == current then return end
    AQ.shared.noticedBuild = current
    AQ.Print(("the game was updated since the quest database was made (%s). Quests the patch added are picked up as you meet their givers."):format(
        AQ.DB.meta.date or "unknown date"))
end

-- Redraw world map pins and minimap pins from the current data and settings.
function AQ.RefreshAll()
    if AQ.Pins then AQ.Pins.Refresh() end
    if AQ.Minimap then AQ.Minimap.Rebuild() end
    if AQ.QuestList then AQ.QuestList.Refresh() end
    if AQ.API and AQ.API.callbacks then AQ.API.callbacks:Fire("AllQuest_Refreshed") end
end

-- Called after any setting changed.
function AQ.SettingsChanged()
    AQ.RefreshAll()
    if AQ.Notify then AQ.Notify.Baseline() end
    if AQ.UpdateMapButton then AQ.UpdateMapButton() end
    if AQ.Minimap then AQ.Minimap.UpdateButton() end
    if AQ.Tracker then AQ.Tracker.Apply() end
    if AQ.RefreshOptions then AQ.RefreshOptions() end
end

-- Debounced redraw for quest/level events.
local pending = false
function AQ.RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        AQ.RefreshAll()
        if AQ.Notify then
            -- a level-up or a turned-in quest may have opened new quests: tell the player, otherwise just note the state
            if AQ.notifyNext then AQ.notifyNext = false AQ.Notify.Schedule() else AQ.Notify.Baseline() end
        end
    end)
end

-- Slower redraw for events that can arrive in bursts (reputation and skill gains): at most one every few seconds.
local slowPending = false
function AQ.RequestSlowRefresh()
    if slowPending then return end
    slowPending = true
    C_Timer.After(5, function()
        slowPending = false
        AQ.RefreshAll()
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_REMOVED")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_FACTION")         -- reputation requirements
frame:RegisterEvent("SKILL_LINES_CHANGED")    -- profession requirements
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == AddOn then InitDB() end
    elseif event == "PLAYER_LOGIN" then
        if AQ.Minimap then AQ.Minimap.RegisterButton() end
        if AQ.Tracker then AQ.Tracker.Apply() end
        AQ.Data.Init()
        AQ.Events.Start()
        AQ.CheckClientBuild()
        -- the screenshot dev tool, when it is installed, needs a way in
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        if isLoaded and isLoaded("AllQuestShots") then _G.AllQuestInternals = AQ end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- completed-quest flags can still be arriving at login or /reload: look again shortly after
        if arg1 or arg2 then C_Timer.After(3, AQ.RequestRefresh) end
    elseif event == "UPDATE_FACTION" or event == "SKILL_LINES_CHANGED" then
        AQ.RequestSlowRefresh()
    else
        if event == "PLAYER_LEVEL_UP" then AQ.playerLevel = arg1 end
        if event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" then AQ.notifyNext = true end
        AQ.RequestRefresh()
    end
end)

SLASH_ALLQUEST1 = "/allquest"
SLASH_ALLQUEST2 = "/aq"
SlashCmdList.ALLQUEST = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local db = AQ.db
    if cmd == "" or cmd == "options" or cmd == "config" then
        AQ.ToggleOptions()
        return
    elseif cmd == "toggle" then
        db.enabled = not db.enabled
    elseif cmd == "on" then
        db.enabled = true
    elseif cmd == "off" then
        db.enabled = false
    elseif cmd == "all" then
        db.showAll = not db.showAll
        AQ.Print("show all levels:", db.showAll and "on" or "off")
    elseif cmd == "above" then
        local n = tonumber(arg)
        if not n then AQ.Print("usage: /allquest above <number>") return end
        db.levelsAbove = math.max(0, math.min(60, math.floor(n)))
        db.showAll = false
    elseif cmd == "low" then
        db.hideLowLevel = not db.hideLowLevel
        AQ.Print("low level (grey) quests:", db.hideLowLevel and "hidden" or "shown")
    elseif cmd == "minimap" then
        AQ.shared.minimap.hide = not AQ.shared.minimap.hide
        AQ.Minimap.ApplyButton()
        AQ.Print("minimap button:", AQ.shared.minimap.hide and "hidden" or "shown")
    elseif cmd == "preset" then
        if arg == "" then
            local _, _, name = AQ.CurrentPreset()
            AQ.Print("current preset:", name or "custom (unsaved)")
            AQ.Print("usage: /allquest preset <name> (Minimal, Detailed, Show All, or one you saved)")
        else
            AQ.ApplyPreset(arg)
        end
        return
    elseif cmd == "list" then
        AQ.QuestList.Toggle()
        return
    elseif cmd == "restore" then
        AQ.RestoreAllIgnored()
        return
    elseif cmd == "profile" then
        if arg == "" then
            AQ.Print("current profile:", AQ.ProfileName(), "- profiles:", table.concat(AQ.ProfileNames(), ", "))
        else
            local found
            for _, name in ipairs(AQ.ProfileNames()) do
                if name:lower() == arg:lower() then found = name end
            end
            if found then AQ.ProfileUse(found) else AQ.ProfileCreate(arg) end
        end
        return
    elseif cmd == "tracker" then
        db.hideTracker = not db.hideTracker
        AQ.Print("Blizzard objective tracker:", db.hideTracker and "hidden" or "shown")
    elseif cmd == "events" then
        local list = AQ.Events.ActiveList()
        AQ.Print("holidays on now:", #list > 0 and table.concat(list, ", ") or "none")
        return
    elseif cmd == "learned" then
        AQ.Print(("%d quests learned in game"):format(AQ.Learn.Count()))
        return
    elseif cmd == "forget" then
        AQ.Learn.Forget()
        AQ.Print("forgot all learned quests")
    elseif cmd == "settings" then
        AQ.OpenGameOptions()
        return
    elseif cmd == "skills" then
        local list = {}
        for id, rank in pairs(AQ.Data.PlayerSkills()) do list[#list + 1] = id .. "=" .. rank end
        table.sort(list)
        AQ.Print("detected skills (id=level):", #list > 0 and table.concat(list, ", ") or "none")
        return
    elseif cmd == "status" then
        local d = AQ.Data
        AQ.Print(("profile: %s | markers %s | preset: %s"):format(AQ.ProfileName(), db.enabled and "on" or "off",
            select(3, AQ.CurrentPreset()) or "custom"))
        AQ.Print(("database: %s, %d maps, %d giver spots, %d quests learned, %d hidden"):format(
            d.ready and "loaded" or "missing", d.mapCount, d.entryCount, AQ.Learn.Count(), #AQ.IgnoredList()))
        local m = AQ.DB.meta
        if m.date then
            local current = select(2, GetBuildInfo())
            AQ.Print(("quest data from %s (client build %s)%s"):format(m.date, tostring(m.build),
                (current and tostring(current) ~= tostring(m.build)) and (" - the game is now on build " .. current .. ", newer quests are learned as you meet them") or ""))
        end
        return
    else
        AQ.Print("/allquest [options|list|preset|profile|restore|toggle|on|off|all|above N|low|minimap|tracker|events|learned|forget|settings|skills|status]")
        return
    end
    AQ.SettingsChanged()
end
