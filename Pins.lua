local AddOn, AQ = ...

-- World map markers: a MapCanvas data provider plus our own pin pool registered under a template name.
-- With the OpenMap addon's stitched map, neighbouring zones' markers are placed through OpenMap's
-- public coordinate API, so they show across zone borders on the one big map.
local Pins = {}
AQ.Pins = Pins

local TEMPLATE = "AllQuestPinTemplate"
local TEX_AVAILABLE = "Interface\\AddOns\\AllQuest\\images\\Marker64"
local BASE_SIZE = 18
local FADE_IN = 0.25

local live = {}          -- giver spot (entry) -> the pin showing it (so a redraw can move pins instead of remaking them)

local isForever = select(4, GetBuildInfo()) >= 16000 and select(4, GetBuildInfo()) < 17000

---------------------------------------------------------------------------------------------
-- Helpers

-- Difficulty colour of a quest level relative to the character, like the quest log:
-- red 5+ above, orange 3-4 above, yellow within 2, green below, grey trivial.
-- The colour-blind palette keeps red and green apart by hue and brightness (purple / orange / yellow / blue).
local PALETTES = {
    normal = { hard = { 1, 0.15, 0.15 }, harder = { 1, 0.55, 0.1 }, even = { 1, 0.9, 0.1 }, easy = { 0.3, 0.9, 0.3 },
        trivial = { 0.6, 0.6, 0.6 }, repeatable = { 0.3, 0.6, 1 } },
    colorblind = { hard = { 0.8, 0.4, 0.75 }, harder = { 0.9, 0.6, 0 }, even = { 0.95, 0.9, 0.25 }, easy = { 0.35, 0.7, 0.9 },
        trivial = { 0.6, 0.6, 0.6 }, repeatable = { 1, 1, 1 } },
}
local function Palette()
    return PALETTES[AQ.db and AQ.db.colorblind and "colorblind" or "normal"]
end

local function LevelColor(level, trivial)
    local p = Palette()
    local c
    if trivial then
        c = p.trivial
    else
        local diff = level - UnitLevel("player")
        c = diff >= 5 and p.hard or diff >= 3 and p.harder or diff >= -2 and p.even or p.easy
    end
    return c[1], c[2], c[3]
end
AQ.LevelColor = LevelColor

-- How far a quest is above (+) or below (-) the character, as text.
local function Relative(level)
    local diff = level - UnitLevel("player")
    return diff > 0 and ("+" .. diff) or tostring(diff)
end

-- The colour key shown in the settings, in the colours currently in use.
function AQ.LegendText()
    local p, L = Palette(), AQ.L
    local function hex(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
    local names = AQ.db.colorblind and { "Purple", "Orange", "Yellow", "Blue", "Grey", "White" }
        or { "Red", "Orange", "Yellow", "Green", "Grey", "Blue" }
    local function part(color, name, text) return hex(color) .. L[name] .. "|r " .. L[text] end
    return table.concat({ part(p.hard, names[1], "5+ above"), part(p.harder, names[2], "3-4"), part(p.even, names[3], "even"),
        part(p.easy, names[4], "below"), part(p.trivial, names[5], "trivial"), part(p.repeatable, names[6], "repeatable") }, "  ")
end

-- Quest types. The tag id comes from the bundled data (exported with the quests); when the data has none the
-- game's own quest tag is asked. Types that the data already tells (class, profession, holiday, repeatable,
-- dungeon, dropped item) are added to that. Each type has a badge letter (shown on the marker) and a name.
local TAGS = {
    [1] = { "G", "Group" }, [21] = { "C", "Class" }, [41] = { "P", "PvP" }, [62] = { "R", "Raid" },
    [81] = { "D", "Dungeon" }, [82] = { "E", "World event" }, [83] = { "L", "Legendary" },
    [84] = { "S", "Escort" }, [85] = { "H", "Heroic" }, [88] = { "R", "Raid" }, [89] = { "R", "Raid" },
}
local liveTags, liveTries = {}, {}

-- The game's quest tag id for a quest (nil: none or not known yet).
local function LiveTag(id)
    local cached = liveTags[id]
    if cached ~= nil then return cached or nil end
    local info = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(id)
    if info and info.tagID then
        liveTags[id] = info.tagID
        return info.tagID
    end
    -- the API can answer nil on the first call; give it a second chance before caching "none"
    liveTries[id] = (liveTries[id] or 0) + 1
    if liveTries[id] >= 2 then liveTags[id] = false end
end

-- List of { letter, name } for one quest of a giver spot. `q` is an item of a pin's quest list.
local function TypesFor(q, kind)
    local list, seen = {}, {}
    local function add(letter, name, key)
        key = key or name
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = { letter, name, key }
        end
    end
    local tag = TAGS[q.tag or LiveTag(q.id) or 0]
    if tag then
        if tag[2] == "Group" and q.grp and q.grp > 1 then
            add(tag[1], (AQ.L["Group (%d players)"]):format(q.grp), "Group")
        else
            add(tag[1], tag[2])
        end
    end
    if kind == "d" then add("D", "Dungeon") elseif kind == "i" then add("i", "Dropped item") end
    if q.cls then add("C", "Class") end
    if q.prof then add("T", "Profession") end
    if q.ev then add("E", AQ.L["Holiday"] .. ": " .. q.ev, "Holiday") end
    if q.rep then add(nil, "Repeatable") end
    return list
end

-- Letters of a quest's types joined for the level label, and the first letter for the marker badge.
local function Letters(types)
    local letters = {}
    for _, t in ipairs(types) do
        if t[1] and not letters[t[1]] then letters[t[1]] = true letters[#letters + 1] = t[1] end
    end
    return table.concat(letters), letters[1]
end

-- Visual style for an available-quest pin: texture, colour, alpha, desaturate (always false: the art is a flat
-- white shape that takes the colour as it is), badge letter.
function AQ.Style(info)
    local db = AQ.db
    local q = info.top
    local r, g, b = 1, 0.85, 0.1
    if q.rep then
        r, g, b = unpack(Palette().repeatable)     -- repeatable: blue (white for the colour-blind palette)
    elseif db.colorByLevel then
        r, g, b = LevelColor(q.level, q.trivial)
    elseif q.trivial or q.locked then
        r, g, b = 0.6, 0.6, 0.6
    end
    if q.rep and q.trivial then r, g, b = 0.6, 0.6, 0.6 end
    local alpha = q.locked and 0.65 or 1           -- faded only while you are too low level to accept it
    local badge
    if db.showTypeTags then
        local _, first = Letters(TypesFor(q, info.entry.kind))
        badge = first
    end
    return TEX_AVAILABLE, r, g, b, alpha, false, badge
end

-- Adds the colour key and the type-letter key to a tooltip, each only while that display is turned on.
function AQ.AddKeyLines(tt)
    local db, L = AQ.db, AQ.L
    if db.colorByLevel then
        local p = Palette()
        local names = db.colorblind and { "Purple", "Orange", "Yellow", "Blue" } or { "Red", "Orange", "Yellow", "Green" }
        tt:AddLine(" ")
        tt:AddLine(L["Difficulty colours"], 1, 0.82, 0)
        local rows = {
            { p.hard, names[1], "5 or more levels above you" }, { p.harder, names[2], "3-4 levels above you" },
            { p.even, names[3], "close to your level" }, { p.easy, names[4], "below your level" },
            { p.trivial, "Grey", "trivial for you" }, { p.repeatable, db.colorblind and "White" or "Blue", "repeatable" },
        }
        for _, row in ipairs(rows) do
            tt:AddLine(L[row[2]] .. " - " .. L[row[3]], row[1][1], row[1][2], row[1][3])
        end
    end
    if db.showTypeTags then
        tt:AddLine(" ")
        tt:AddLine(L["Type letters"], 1, 0.82, 0)
        -- the letters stay as they are on the markers; the names are translated
        local rows = { { "C", "Class" }, { "D", "Dungeon" }, { "E", "World event / holiday" },
            { "G", "Group (needs a party)" }, { "H", "Heroic" }, { "i", "Dropped item" }, { "L", "Legendary" },
            { "P", "PvP" }, { "R", "Raid" }, { "S", "Escort" }, { "T", "Profession" } }
        for _, row in ipairs(rows) do
            tt:AddLine(row[1] .. " - " .. L[row[2]], 0.8, 0.8, 0.8)
        end
    end
end

-- Text under a marker (quest level and/or how far above or below you it is), with its colour; nil for none.
function AQ.PinLabel(info)
    local db = AQ.db
    local top = info.top
    local label
    if db.showLevelText then label = tostring(top.level) end
    if db.difficultyText then
        local rel = Relative(top.level)
        label = label and (label .. " (" .. rel .. ")") or rel
    end
    if not label then return end
    local r, g, b = LevelColor(top.level, top.trivial)
    return label, r, g, b
end

-- Names for the details panel.
local SKILL_NAMES = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
    [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
    [356] = "Fishing", [393] = "Skinning", [755] = "Jewelcrafting", [773] = "Inscription", [762] = "Riding",
}
local STANDINGS = { { 42000, "Exalted" }, { 21000, "Revered" }, { 9000, "Honored" }, { 3000, "Friendly" },
    { 0, "Neutral" }, { -3000, "Unfriendly" }, { -6000, "Hostile" } }

local function StandingName(value)
    for _, st in ipairs(STANDINGS) do
        if value >= st[1] then return st[2] end
    end
    return "Hated"
end

local function FactionName(id)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local d = C_Reputation.GetFactionDataByID(id)
        if d and d.name then return d.name end
    elseif GetFactionInfoByID then
        local name = GetFactionInfoByID(id)
        if name then return name end
    end
    return "faction " .. id
end

local function ClassNames(mask)
    local names = {}
    for classId = 1, 13 do
        local bit = 2 ^ (classId - 1)
        if (mask % (bit * 2)) >= bit then
            local name = GetClassInfo and GetClassInfo(classId)
            if name then names[#names + 1] = name end
        end
    end
    return table.concat(names, ", ")
end

local GREY, RED = { 0.65, 0.65, 0.65 }, { 1, 0.45, 0.4 }
local DIVIDER = "|TInterface\\Common\\UI-TooltipDivider-Transparent:8:170|t"

-- Detail lines of one quest: { text, colour }.
local function DetailLines(q)
    local lines = {}
    local function add(text, colour) lines[#lines + 1] = { text, colour or GREY } end
    if (q.req or 0) > 0 then
        if q.locked then
            add((AQ.L["Requires level %d (you are %d)"]):format(q.req, UnitLevel("player")), RED)
        else
            add((AQ.L["Requires level %d"]):format(q.req))
        end
    end
    if q.maxl and q.maxl > 0 then add((AQ.L["Only up to level %d"]):format(q.maxl)) end
    if q.scaled then add(AQ.L["Level scales with yours"]) end
    if q.clsMask then add(AQ.L["Class"] .. ": " .. ClassNames(q.clsMask)) end
    if q.sk then add((AQ.L["Skill: %s %d"]):format(SKILL_NAMES[q.sk[1]] and AQ.L[SKILL_NAMES[q.sk[1]]] or ("skill " .. q.sk[1]), q.sk[2] or 0)) end
    if q.mr then add((AQ.L["Reputation: %s, %s or better"]):format(FactionName(q.mr[1]), AQ.L[StandingName(q.mr[2])])) end
    if q.xr then add((AQ.L["Reputation: %s, below %s"]):format(FactionName(q.xr[1]), AQ.L[StandingName(q.xr[2])])) end
    return lines
end

---------------------------------------------------------------------------------------------
-- Quest-type filter

-- The types that can be switched off in the filter (name in the data, text shown).
local FILTER_TYPES = { { "Group", "Group" }, { "Class", "Class" }, { "PvP", "PvP" }, { "Raid", "Raid" },
    { "Heroic", "Heroic" }, { "Legendary", "Legendary" }, { "Escort", "Escort" }, { "Profession", "Profession" } }
AQ.FilterTypes = FILTER_TYPES

-- True when one of the quest's types is switched off.
function AQ.TypeHidden(q, kind)
    local hidden = AQ.db.hiddenTypes
    if not hidden or not next(hidden) then return false end
    for _, t in ipairs(TypesFor(q, kind)) do
        if hidden[t[3]] then return true end
    end
    return false
end

---------------------------------------------------------------------------------------------
-- Clicking markers: waypoint, hide, filter menu

function AQ.SetWaypoint(entry)
    local name = AQ.Data.StarterInfo(entry)
    local map, x, y = entry.map, entry.x, entry.y
    if not (map and x and y) then return end
    if _G.TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(map, x, y, { title = name, persistent = false, minimap = true, world = true })
        AQ.Print("waypoint set: " .. name)
    elseif C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(map) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        AQ.Print("waypoint set: " .. name)
    else
        AQ.Print("this client cannot place a waypoint there.")
    end
end

local function KeepOpen() return MenuResponse and MenuResponse.Refresh end

-- Right-click menu of a marker: waypoint, hide a quest, hide the giver.
function AQ.OpenPinMenu(owner, info)
    if not (info and MenuUtil and MenuUtil.CreateContextMenu) then return end
    GameTooltip:Hide()
    local entry = info.entry
    local name = AQ.Data.StarterInfo(entry)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(name)
        root:CreateButton(AQ.L["Set waypoint"], function() AQ.SetWaypoint(entry) end)
        root:CreateDivider()
        for i, q in ipairs(info.quests) do
            if i > 8 then break end
            local qname = AQ.Data.QuestName(q.id)
            root:CreateButton((AQ.L["Hide quest"] .. ": [%d] %s"):format(q.level, qname), function()
                AQ.IgnoreQuest(q.id, qname)
            end)
        end
        root:CreateButton(AQ.L["Hide this giver"], function() AQ.IgnoreGiver(entry.kind .. entry.id, name) end)
    end)
end

-- The quest-type filter menu of the world map button.
function AQ.OpenFilterMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        AQ.ToggleOptions()
        return
    end
    local db = AQ.db
    local function Box(root, label, get, set)
        root:CreateCheckbox(label, get, function() set() AQ.SettingsChanged() return KeepOpen() end)
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(AQ.L["Show quest types"])
        for _, t in ipairs(FILTER_TYPES) do
            local key = t[1]
            Box(root, AQ.L[t[2]], function() return not db.hiddenTypes[key] end,
                function() db.hiddenTypes[key] = (not db.hiddenTypes[key]) or nil end)
        end
        root:CreateDivider()
        Box(root, AQ.L["Dungeon quests"], function() return db.showDungeonQuests end, function() db.showDungeonQuests = not db.showDungeonQuests end)
        Box(root, AQ.L["Dropped-item quests"], function() return db.showDropQuests end, function() db.showDropQuests = not db.showDropQuests end)
        Box(root, AQ.L["Repeatable quests"], function() return db.showRepeatable end, function() db.showRepeatable = not db.showRepeatable end)
        Box(root, AQ.L["Holiday quests"], function() return db.showEventQuests end, function() db.showEventQuests = not db.showEventQuests end)
        root:CreateDivider()
        root:CreateButton(AQ.L["Show all types"], function()
            db.hiddenTypes = {}
            db.showDungeonQuests, db.showDropQuests, db.showRepeatable, db.showEventQuests = true, true, true, true
            AQ.SettingsChanged()
        end)
        root:CreateButton(AQ.L["Options..."], function() AQ.ToggleOptions() end)
    end)
end

-- Tooltip for a pin; also used by the minimap markers. Detailed by default; "minimal" mode shows only
-- the giver and each quest's level and name. `position`/`total`: this giver is one of several at the same spot.
function AQ.ShowQuestTooltip(owner, info, anchor, position, total)
    if not info then return end
    local L = AQ.L
    local detailed = AQ.db.tooltipDetails
    local kind = info.entry.kind
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local name, sub = AQ.Data.StarterInfo(info.entry)
    -- The giver line: the NPC or object, or for a dropped-item quest the item that starts it.
    GameTooltip:AddLine(name, 1, 1, 1)
    if detailed then
        if sub then
            GameTooltip:AddLine(kind == "n" and ("<" .. sub .. ">") or sub, 0.7, 0.7, 0.7, true)
        end
        -- a thin divider between the giver and what they offer
        GameTooltip:AddLine(DIVIDER)
    end
    local count = #info.quests
    for i, q in ipairs(info.quests) do
        local r, g, b = LevelColor(q.level, q.trivial)
        local title = ("[%d] %s"):format(q.level, AQ.Data.QuestName(q.id))
        if AQ.db.difficultyText then title = title .. "  (" .. Relative(q.level) .. ")" end
        GameTooltip:AddLine(title, r, g, b)
        if detailed then
            local types = TypesFor(q, kind)
            local names = {}
            for _, t in ipairs(types) do names[#names + 1] = L[t[2]] end
            GameTooltip:AddLine("   " .. L["Type"] .. ": " .. (#names > 0 and table.concat(names, ", ") or L["Normal"]), GREY[1], GREY[2], GREY[3])
            if kind == "i" then
                local drops, more = AQ.Data.ItemDrops(info.entry.id)
                if drops and #drops > 0 then
                    -- the first dropper sits on the label's line; any others follow, lined up under it
                    for index, line in ipairs(drops) do
                        if index == 1 then
                            GameTooltip:AddLine("   " .. L["Dropped by"] .. ": " .. line, GREY[1], GREY[2], GREY[3])
                        else
                            GameTooltip:AddLine("        " .. line, GREY[1], GREY[2], GREY[3])
                        end
                    end
                    if more and more > 0 then
                        GameTooltip:AddLine(("        " .. L["and %d more"]):format(more), GREY[1], GREY[2], GREY[3])
                    end
                end
            end
            for _, d in ipairs(DetailLines(q)) do
                GameTooltip:AddLine("   " .. d[1], d[2][1], d[2][2], d[2][3], true)
            end
            if i < count then GameTooltip:AddLine(" ") end
        end
    end
    if total and total > 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((L["Giver %d of %d at this spot"]):format(position, total), 0.5, 0.8, 1)
    end
    if detailed then
        GameTooltip:AddLine(L["Click: waypoint  -  Right-click: hide"], 0.45, 0.45, 0.45)
    end
    GameTooltip:Show()
end

-- Several markers can sit on the same spot: hovering shows each giver in turn.
local CYCLE_SECONDS = 3
local hover = {}
local cycler = CreateFrame("Frame")
local FrameGetCenter = (function()
    local mt = getmetatable(CreateFrame("Frame"))
    local index = mt and mt.__index
    if type(index) == "table" and index.GetCenter then return index.GetCenter end
    return function(frame) return frame:GetCenter() end
end)()

local function Show()
    AQ.ShowQuestTooltip(hover.owner, hover.list[hover.index], hover.anchor, hover.index, #hover.list)
end

function AQ.BeginHover(owner, anchor, neighbours)
    hover = { owner = owner, anchor = anchor, list = { owner.info }, index = 1, t = 0 }
    for _, other in ipairs(neighbours or {}) do hover.list[#hover.list + 1] = other.info end
    Show()
    if #hover.list > 1 then
        cycler:SetScript("OnUpdate", function(_, dt)
            hover.t = hover.t + dt
            if hover.t >= CYCLE_SECONDS then
                hover.t = 0
                hover.index = hover.index % #hover.list + 1
                Show()
            end
        end)
    end
end

function AQ.EndHover()
    cycler:SetScript("OnUpdate", nil)
    hover = {}
    GameTooltip:Hide()
end

-- Markers (frames carrying `.info`) lying on top of `pin`.
function AQ.Overlapping(pin, all)
    local list = {}
    local ok, cx, cy = pcall(FrameGetCenter, pin)
    if not (ok and cx) then return list end
    local scale = pin:GetEffectiveScale()
    cx, cy = cx * scale, cy * scale
    local limit = (pin:GetWidth() or 14) * scale * 0.8
    for _, other in ipairs(all) do
        if other ~= pin and other.info and other:IsShown() then
            local ok2, ox, oy = pcall(FrameGetCenter, other)
            if ok2 and ox then
                local s = other:GetEffectiveScale()
                local dx, dy = ox * s - cx, oy * s - cy
                if dx * dx + dy * dy < limit * limit then list[#list + 1] = other end
            end
        end
    end
    return list
end

-- Click on a marker: left = waypoint, right = menu. A drag that started on a marker does not count.
function AQ.MarkerClicks(frame)
    frame:SetScript("OnMouseDown", function(f)
        f.downX, f.downY = GetCursorPosition()
    end)
    frame:SetScript("OnMouseUp", function(f, button)
        local x, y = GetCursorPosition()
        if f.downX and (math.abs(x - f.downX) > 6 or math.abs(y - f.downY) > 6) then return end
        if not f.info then return end
        if button == "LeftButton" then
            AQ.SetWaypoint(f.info.entry)
        elseif button == "RightButton" then
            AQ.OpenPinMenu(f, f.info)
        end
    end)
end

-- Results of Data.GetPins per map, kept until something changes (settings, level, quests, holidays).
local cache = {}
function AQ.PinsFor(uiMapId)
    local pins = cache[uiMapId]
    if not pins then
        pins = AQ.Data.GetPins(uiMapId)
        cache[uiMapId] = pins
    end
    return pins
end

---------------------------------------------------------------------------------------------
-- Pin

local Pin = CreateFromMixins(MapCanvasPinMixin)

function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.2)
end

local function Build(self)
    self.icon = self:CreateTexture(nil, "ARTWORK")
    self.icon:SetAllPoints()
    self.level = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.level:SetPoint("TOP", self, "BOTTOM", 0, 2)
    self.badge = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.badge:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 4, -3)
    self.badge:SetTextColor(1, 1, 1)
    self:SetScript("OnEnter", function(pin)
        local all = {}
        for _, other in pairs(live) do all[#all + 1] = other end
        AQ.BeginHover(pin, "ANCHOR_RIGHT", AQ.Overlapping(pin, all))
    end)
    self:SetScript("OnLeave", AQ.EndHover)
    AQ.MarkerClicks(self)
    -- short fade-in so markers do not pop on
    self.fade = self:CreateAnimationGroup()
    local alpha = self.fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(FADE_IN)
    self.fade:SetToFinalAlpha(true)
    self.built = true
end

-- Size, position, colour, label and badge for `info` (also used to restyle a pin whose quests changed).
function Pin:Apply(info)
    self.info = info
    self:EnableMouse(AQ.db.showTooltips and true or false)
    local size = BASE_SIZE * AQ.db.iconScale
    self:SetSize(size, size)
    self:SetPosition(info.px or info.entry.x, info.py or info.entry.y)
    local tex, r, g, b, alpha, desat, badge = AQ.Style(info)
    self.icon:SetTexture(tex)
    self.icon:SetDesaturated(desat)
    self.icon:SetVertexColor(r, g, b)
    self.icon:SetAlpha(alpha)
    local label, lr, lg, lb = AQ.PinLabel(info)
    if label then
        self.level:SetText(label)
        self.level:SetTextColor(lr, lg, lb)
        self.level:Show()
    else
        self.level:Hide()
    end
    if badge then
        self.badge:SetText(badge)
        self.badge:Show()
    else
        self.badge:Hide()
    end
end

function Pin:OnAcquired(info)
    if not self.built then Build(self) end
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:Apply(info)
    self:SetAlpha(1)
    self.fade:Stop()
    self.fade:Play()
    self:Show()
end

function Pin:OnReleased()
    self.info = nil
    if self.fade then self.fade:Stop() end
end

-- Avoid the in-combat error some builds raise for pass-through buttons.
Pin.SetPassThroughButtons = function() end
if isForever then
    -- Blizzard's gamepad map cursor reads pins outside secure code; pins without a centre are skipped.
    Pin.GetCenter = function() return nil end
end

-- OpenMap's stitched art sits above the usual pin frame levels, which would wash the markers out: put them above it.
local function Lift(pin, extra)
    local API = _G.OpenMapAPI
    if not (pin and pin.SetFixedFrameLevel and API and API.IsStitched and API.ArtTopLevel and API.IsStitched()) then return end
    local top = API.ArtTopLevel()
    if not top then return end
    local want = top + 5 + (extra or 0)
    if pin:GetFrameLevel() < want then
        pin:SetFixedFrameLevel(false)
        pin:SetFrameLevel(want)
        pin:SetFixedFrameLevel(true)
    end
end

---------------------------------------------------------------------------------------------
-- Provider

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    live = {}
end

-- Position of an entry of map `uiMapId` on OpenMap's stitched world (cached on the entry).
local function StitchedUV(API, uiMapId, entry)
    if entry.su == false then return end
    if not entry.su then
        local ok, u, v = pcall(API.WorldFromMap, uiMapId, entry.x, entry.y)
        if ok and u then
            entry.su, entry.sv = u, v
        else
            entry.su = false
            return
        end
    end
    return entry.su, entry.sv
end

-- The nearest map (the map itself, else its parents) that has quest givers.
local function ClimbToData(id)
    for _ = 1, 8 do
        if not id or id == 0 then return end
        if AQ.Data.HasMap(id) then return id end
        local info = C_Map.GetMapInfo(id)
        id = info and info.parentMapID
    end
end

local function PlayerZone()
    local id = C_Map.GetBestMapForUnit("player")
    return id and ClimbToData(id)
end

-- The continent a map belongs to (its parents are followed up), cached.
local continentOf = {}
local function ContinentOf(id)
    local cached = continentOf[id]
    if cached ~= nil then return cached or nil end
    local current, found = id, false
    for _ = 1, 8 do
        if not current or current == 0 then break end
        local info = C_Map.GetMapInfo(current)
        if not info then break end
        if info.mapType == Enum.UIMapType.Continent then found = current break end
        current = info.parentMapID
    end
    continentOf[id] = found
    return found or nil
end

-- A point of `zone` on the (non-stitched) map `host`, going up through the parent maps.
local function ChainPosition(zone, host, x, y)
    local current = zone
    for _ = 1, 6 do
        if current == host then return x, y end
        local info = C_Map.GetMapInfo(current)
        local parent = info and info.parentMapID
        if not parent or parent == 0 then return end
        local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(current, parent)
        if not minX or maxX == minX then return end
        x, y = minX + x * (maxX - minX), minY + y * (maxY - minY)
        current = parent
    end
end

-- Zoom safeguard (OpenMap): with the whole continent loaded, zooming can make the frame rate fall. While the view
-- changes and the frame rate is low, the markers outside the player's zone are hidden, and shown again once the
-- view has been still for a moment. Drawing waits meanwhile.
local guard = { active = false }
local GUARD_FPS, GUARD_QUIET = 30, 0.35

local function ViewSignature()
    local parts = {}
    local canvas = WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if canvas then parts[#parts + 1] = tostring(canvas:GetScale()) end
    local API = _G.OpenMapAPI
    if API and API.GetView then
        local ok, a, b, c, d = pcall(API.GetView)
        if ok then parts[#parts + 1] = tostring(a) .. tostring(b) .. tostring(c) .. tostring(d) end
    end
    return table.concat(parts, "|")
end

local function GuardEngage()
    guard.active = true
    local home = PlayerZone()
    for entry, pin in pairs(live) do
        if entry.map ~= home then pin:Hide() end
    end
end

local function GuardRelease()
    guard.active = false
    guard.started = nil
    for _, pin in pairs(live) do pin:Show() end
    Pins.RequestDraw()
end

local guardFrame = CreateFrame("Frame")
guardFrame:SetScript("OnUpdate", function()
    local db = AQ.db
    if not (Pins.installed and WorldMapFrame:IsShown() and db and db.zoomSafeguard) then
        if guard.active then GuardRelease() end
        return
    end
    local API = _G.OpenMapAPI
    if not (API and API.IsStitched and API.IsStitched()) then return end
    local now = GetTime()
    local sig = ViewSignature()
    if sig ~= guard.sig then
        guard.sig = sig
        guard.quietAt = now + GUARD_QUIET
        guard.started = guard.started or now
        if not guard.active and now - guard.started > 0.2 and GetFramerate() < GUARD_FPS then GuardEngage() end
    elseif now >= (guard.quietAt or 0) then
        if guard.active then GuardRelease() else guard.started = nil end
    end
end)

-- Which zones show markers. Zoomed out (continent or world view): only the zone you stand in, so zooming out
-- never makes your own area's markers pop away. Zoomed in on OpenMap's stitched map: the whole continent, so
-- nothing pops in and out as you move around the map. Without OpenMap: the zone shown, plus your zone.
-- Redrawing moves the pins that are already there instead of remaking them.
function Provider:Draw()
    local map = self:GetMap()
    if not map then return end
    if guard.active then return end
    local db = AQ.db
    if not (db and db.enabled and AQ.Data.ready) then
        self:RemoveAllData()
        return
    end
    local host = map:GetMapID()
    if not host then return end

    local hostInfo = C_Map.GetMapInfo(host)
    local zoomedOut = hostInfo and hostInfo.mapType and hostInfo.mapType <= Enum.UIMapType.Continent
    local API = _G.OpenMapAPI
    local stitched = API and API.IsStitched and API.IsStitched()

    local zones, seen = {}, {}
    local function add(zone)
        if zone and not seen[zone] then
            seen[zone] = true
            zones[#zones + 1] = zone
        end
    end
    local playerZone = PlayerZone()
    if not zoomedOut and not db.currentZoneOnly then
        add(ClimbToData(host))
        if stitched and db.wholeContinent then
            local continent = ContinentOf(host) or (playerZone and ContinentOf(playerZone))
            if continent then
                local ids = AQ.Data.MapIds()
                table.sort(ids)
                for _, zone in ipairs(ids) do
                    if ContinentOf(zone) == continent then add(zone) end
                end
            end
        end
    end
    add(playerZone)

    -- what should be on the map now: entry -> { x, y } (nil x, y: the entry's own position on `host`)
    local wanted, order = {}, {}
    for _, zone in ipairs(zones) do
        for _, info in ipairs(AQ.PinsFor(zone)) do
            local x, y
            local place = true
            if zone ~= host then
                place = false
                if stitched then
                    local u, v = StitchedUV(API, zone, info.entry)
                    if u then
                        local ok, hx, hy = pcall(API.MapFromWorld, host, u, v)
                        if ok and hx then x, y, place = hx, hy, true end
                    end
                else
                    x, y = ChainPosition(zone, host, info.entry.x, info.entry.y)
                    place = x ~= nil
                end
            end
            if place then
                wanted[info.entry] = { x, y }
                order[#order + 1] = info
            end
        end
    end

    -- take away what is no longer wanted
    for entry, pin in pairs(live) do
        if not wanted[entry] then
            if pin.info then map:RemovePin(pin) end
            live[entry] = nil
        end
    end
    -- move what is there, add what is new. A giver spot keeps its pin when its quests change (a quest was
    -- taken, the level went up ...): the pin is restyled in place instead of fading in again.
    for _, info in ipairs(order) do
        local entry = info.entry
        local pos = wanted[entry]
        info.px, info.py = pos[1], pos[2]
        local pin = live[entry]
        if not pin or not pin.info then      -- none yet, or the map released it behind our back
            pin = map:AcquirePin(TEMPLATE, info)
            live[entry] = pin
        elseif pin.info ~= info then
            pin:Apply(info)
        else
            pin:SetPosition(pos[1] or entry.x, pos[2] or entry.y)
        end
        Lift(pin)
    end
end

-- The map asks for a refresh whenever it changes (often several times while zooming). Clearing is immediate so no
-- marker lingers in the wrong place; the drawing waits a frame so a burst of changes costs one redraw.
local drawQueued = false
function Pins.RequestDraw()
    if drawQueued then return end
    drawQueued = true
    C_Timer.After(0, function()
        drawQueued = false
        if Pins.installed and WorldMapFrame:IsShown() then Provider:Draw() end
    end)
end

function Provider:RefreshAllData()
    Pins.RequestDraw()
end

-- Redraw after something changed: forget the cached results first (settings, level, quests ...).
function Pins.Refresh()
    cache = {}
    if Pins.installed and WorldMapFrame:IsShown() then Provider:Draw() end
end

local zoneEvents = CreateFrame("Frame")
zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneEvents:SetScript("OnEvent", function() Pins.RequestDraw() end)

-- How many quests are available in the zone the player stands in (nil: unknown).
function AQ.ZoneQuestCount()
    local zone = PlayerZone()
    if not (zone and AQ.Data.ready) then return end
    local n = 0
    for _, info in ipairs(AQ.PinsFor(zone)) do n = n + #info.quests end
    return n, zone
end

function AQ.AddZoneCount(tt)
    local n, zone = AQ.ZoneQuestCount()
    if not n then return end
    local info = C_Map.GetMapInfo(zone)
    tt:AddLine((AQ.L["Available in %s: %d"]):format(info and info.name or "?", n), 0.6, 1, 0.6)
end

---------------------------------------------------------------------------------------------
-- World map on/off button

local function CreateMapButton()
    local anchor = WorldMapFrame.ScrollContainer or WorldMapFrame
    local btn = CreateFrame("Button", "AllQuestMapButton", WorldMapFrame)
    btn:SetSize(26, 26)
    btn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -12, -12)
    btn:SetFrameLevel(anchor:GetFrameLevel() + 50)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture("Interface\\AddOns\\AllQuest\\images\\AllQuest64")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            AQ.ToggleOptions()
        else
            AQ.db.enabled = not AQ.db.enabled
            AQ.SettingsChanged()
        end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("AllQuest")
        GameTooltip:AddLine(AQ.L["Quest markers"] .. ": " .. (AQ.db.enabled and ("|cff00ff00" .. AQ.L["on"] .. "|r") or ("|cffff4040" .. AQ.L["off"] .. "|r")), 1, 1, 1)
        if not AQ.Data.ready then
            GameTooltip:AddLine(AQ.L["Quest database not loaded"], 1, 0.8, 0)
        end
        AQ.AddZoneCount(GameTooltip)
        GameTooltip:AddLine(AQ.L["Left-click: toggle"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(AQ.L["Right-click: options"], 0.7, 0.7, 0.7)
        AQ.AddKeyLines(GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Pins.button = btn

    -- quest-type filter, left of it
    local filter = CreateFrame("Button", "AllQuestFilterButton", WorldMapFrame)
    filter:SetSize(22, 22)
    filter:SetPoint("RIGHT", btn, "LEFT", -4, 0)
    filter:SetFrameLevel(anchor:GetFrameLevel() + 50)
    filter.icon = filter:CreateTexture(nil, "ARTWORK")
    filter.icon:SetAllPoints()
    filter.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    filter:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    filter:SetScript("OnClick", function(self) AQ.OpenFilterMenu(self) end)
    filter:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(AQ.L["AllQuest quest types"])
        GameTooltip:AddLine(AQ.L["Click to choose which kinds of quests show"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    filter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Pins.filterButton = filter
end

function AQ.UpdateMapButton()
    local btn = Pins.button
    if not btn then return end
    local on = AQ.db.enabled
    btn.icon:SetDesaturated(not on)
    btn.icon:SetAlpha(on and 1 or 0.6)
    local filter = Pins.filterButton
    if filter then
        local db = AQ.db
        filter:SetShown(db.showFilterButton and true or false)
        -- orange while something is filtered out
        local filtering = next(db.hiddenTypes) ~= nil or not (db.showDungeonQuests and db.showDropQuests
            and db.showRepeatable and db.showEventQuests)
        if filtering then filter.icon:SetVertexColor(1, 0.6, 0.2) else filter.icon:SetVertexColor(1, 1, 1) end
    end
end

---------------------------------------------------------------------------------------------
-- Install into the world map

local function Install()
    if Pins.installed or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end

    local pool
    if CreateUnsecuredRegionPoolInstance then
        pool = CreateUnsecuredRegionPoolInstance(TEMPLATE)
    else
        pool = CreateFramePool("FRAME")
    end
    pool.parent = WorldMapFrame:GetCanvas()
    pool.createFunc = function()
        local frame = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
        frame:SetSize(BASE_SIZE, BASE_SIZE)
        return Mixin(frame, Pin)
    end
    pool.resetFunc = function(_, pin)
        pin:Hide()
        pin:ClearAllPoints()
        pin:OnReleased()
        if pin.SetFixedFrameLevel then pin:SetFixedFrameLevel(false) end
        pin.pinTemplate = nil
        pin.owningMap = nil
    end
    -- older pool API names
    pool.creationFunc = pool.createFunc
    pool.resetterFunc = pool.resetFunc
    WorldMapFrame.pinPools[TEMPLATE] = pool

    WorldMapFrame:AddDataProvider(Provider)
    CreateMapButton()
    Pins.installed = true
    local API = _G.OpenMapAPI
    if API and API.RegisterCallback then
        -- redraw when OpenMap switches between its stitched map and Blizzard's
        API.RegisterCallback(AQ, "OpenMap_StitchedChanged", function() Pins.Refresh() end)
    end
    AQ.UpdateMapButton()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    -- Saved variables are ready by now.
    Install()
    if not Pins.installed then
        AQ.Print("world map is not available; markers disabled.")
    end
end)
