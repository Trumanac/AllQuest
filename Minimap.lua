local AddOn, AQ = ...

-- Minimap markers for the quest givers around you, from every nearby zone, and the minimap button (LibDBIcon).
local M = {}
AQ.Minimap = M

local BUTTON_NAME = "AllQuest"
local BASE_SIZE = 14
local EDGE = 0.9          -- fraction of the minimap radius where markers disappear (same as HereBeDragons)

-- Yards across the minimap per zoom level, used when the client has no C_Minimap.GetViewRadius.
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }

local active = {}         -- { frame, wx, wy, inst }
local free = {}
local currentMaps   -- signature of the zones the markers were built from

local function Acquire()
    local f = table.remove(free)
    if not f then
        f = CreateFrame("Frame", nil, Minimap)
        f:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.level = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.level:SetPoint("TOP", f, "BOTTOM", 0, 2)
        f.badge = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.badge:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -3)
        f.badge:SetTextColor(1, 1, 1)
        f:SetScript("OnEnter", function(pin)
            local all = {}
            for _, a in ipairs(active) do all[#all + 1] = a.frame end
            AQ.BeginHover(pin, "ANCHOR_LEFT", AQ.Overlapping(pin, all))
        end)
        f:SetScript("OnLeave", AQ.EndHover)
        AQ.MarkerClicks(f)
    end
    f:EnableMouse(AQ.db.minimapTooltips and true or false)
    return f
end

local function ReleaseAll()
    for i = #active, 1, -1 do
        local a = active[i]
        a.frame:Hide()
        a.frame:ClearAllPoints()
        free[#free + 1] = a.frame
        active[i] = nil
    end
end

-- World position (yards) of a quest giver: x/y are HereBeDragons' axes (x grows west, y grows north),
-- the same space as UnitPosition. Cached on the entry; entries belong to exactly one map.
local function WorldPos(entry, uiMapId)
    if entry.wx then return entry.winst, entry.wx, entry.wy end
    if entry.wfail then return end
    local instance, vec = C_Map.GetWorldPosFromMapPos(uiMapId, CreateVector2D(entry.x, entry.y))
    if not vec then
        entry.wfail = true
        return
    end
    local vx, vy = vec:GetXY()
    entry.winst, entry.wx, entry.wy = instance, vy, vx
    return instance, vy, vx
end

-- Which zones are near the player: the world rectangle of each zone with markers (cached) tested against
-- the player's position, so markers from a neighbouring zone show as soon as they come within reach.
local NEAR_MARGIN = 400   -- yards past a zone's edge that still count (the minimap sees at most ~240)
local bounds = {}

local function Bounds(uiMapId)
    local b = bounds[uiMapId]
    if b ~= nil then return b or nil end
    local inst, v1 = C_Map.GetWorldPosFromMapPos(uiMapId, CreateVector2D(0, 0))
    local _, v2 = C_Map.GetWorldPosFromMapPos(uiMapId, CreateVector2D(1, 1))
    if not (v1 and v2) then
        bounds[uiMapId] = false
        return nil
    end
    local ax, ay = v1:GetXY()
    local bx, by = v2:GetXY()
    b = { inst = inst, minA = math.min(ax, bx), maxA = math.max(ax, bx), minB = math.min(ay, by), maxB = math.max(ay, by) }
    bounds[uiMapId] = b
    return b
end

-- The zone with quest givers that the player stands in (its parents are followed up).
local function PlayerZone()
    local id = C_Map.GetBestMapForUnit("player")
    for _ = 1, 8 do
        if not id or id == 0 then return end
        if AQ.Data.HasMap(id) then return id end
        local info = C_Map.GetMapInfo(id)
        id = info and info.parentMapID
    end
end

local function NearbyMaps()
    local list = {}
    if AQ.db.currentZoneOnly then
        local zone = PlayerZone()
        if zone then list[1] = zone end
        return list
    end
    local py, px, _, inst = UnitPosition("player")   -- first value runs along the same axis as vec.x
    if not px then return list end
    for _, uiMapId in ipairs(AQ.Data.MapIds()) do
        local b = Bounds(uiMapId)
        if b and b.inst == inst
            and py >= b.minA - NEAR_MARGIN and py <= b.maxA + NEAR_MARGIN
            and px >= b.minB - NEAR_MARGIN and px <= b.maxB + NEAR_MARGIN then
            list[#list + 1] = uiMapId
        end
    end
    table.sort(list)
    return list
end

function M.Rebuild()
    ReleaseAll()
    currentMaps = nil
    local db = AQ.db
    if not (db and db.enabled and db.minimapPins and AQ.Data.ready) then return end
    local maps = NearbyMaps()
    currentMaps = table.concat(maps, ",")

    local size = BASE_SIZE * db.minimapScale
    for _, mapId in ipairs(maps) do
        for _, info in ipairs(AQ.PinsFor(mapId)) do
            local inst, wx, wy = WorldPos(info.entry, mapId)
            if inst then
                local f = Acquire()
                f:SetSize(size, size)
                f.info = info
                local tex, r, g, b, alpha, desat, badge = AQ.Style(info)
                f.icon:SetTexture(tex)
                f.icon:SetDesaturated(desat)
                f.icon:SetVertexColor(r, g, b)
                f.icon:SetAlpha(alpha)
                -- the same type letter and level / difficulty text as on the world map, when those are on
                if badge then f.badge:SetText(badge) f.badge:Show() else f.badge:Hide() end
                local label, lr, lg, lb = AQ.PinLabel(info)
                if label then
                    f.level:SetText(label)
                    f.level:SetTextColor(lr, lg, lb)
                    f.level:Show()
                else
                    f.level:Hide()
                end
                active[#active + 1] = { frame = f, wx = wx, wy = wy, inst = inst }
            end
        end
    end
end

local function Place()
    local py, px, _, inst = UnitPosition("player")
    if not px then
        for _, a in ipairs(active) do a.frame:Hide() end
        return
    end
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing() or 0
    local radius
    if C_Minimap and C_Minimap.GetViewRadius then
        radius = C_Minimap.GetViewRadius()
    else
        radius = OUTDOOR[Minimap:GetZoom()] / 2
    end
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    local sin, cos = math.sin(facing), math.cos(facing)

    for _, a in ipairs(active) do
        if a.inst ~= inst then
            a.frame:Hide()
        else
            local dx, dy = px - a.wx, py - a.wy
            if rotate then dx, dy = dx * cos - dy * sin, dx * sin + dy * cos end
            local fx, fy = dx / radius, dy / radius
            local dist
            if square then
                dist = math.max(fx * fx, fy * fy) / (EDGE * EDGE)
            else
                dist = (fx * fx + fy * fy) / (EDGE * EDGE)
            end
            if dist <= 1 then
                a.frame:ClearAllPoints()
                a.frame:SetPoint("CENTER", Minimap, "CENTER", fx * halfW, -fy * halfH)
                a.frame:Show()
            else
                a.frame:Hide()
            end
        end
    end
end

-- Reposition ~20 times a second, and notice zone changes without relying on events.
local ticker = CreateFrame("Frame")
local elapsed, mapElapsed = 0, 0
ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    mapElapsed = mapElapsed + dt
    if mapElapsed > 1 then
        mapElapsed = 0
        if AQ.db and AQ.db.enabled and AQ.db.minimapPins and AQ.Data.ready
            and table.concat(NearbyMaps(), ",") ~= currentMaps then
            M.Rebuild()
        end
    end
    if elapsed > 0.05 then
        elapsed = 0
        if #active > 0 then Place() end
    end
end)

---------------------------------------------------------------------------------------------
-- Minimap button

local icon = LibStub("LibDBIcon-1.0")

function M.RegisterButton()
    if M.registered then return end
    local ldb = LibStub("LibDataBroker-1.1"):NewDataObject(BUTTON_NAME, {
        type = "launcher",
        text = "AllQuest",
        icon = "Interface\\AddOns\\AllQuest\\images\\AllQuest64",
        OnClick = function(_, button)
            if button == "RightButton" then
                AQ.ToggleOptions()
            else
                AQ.db.enabled = not AQ.db.enabled
                AQ.SettingsChanged()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("AllQuest")
            local L = AQ.L
            tt:AddLine(L["Quest markers"] .. ": " .. (AQ.db.enabled and ("|cff00ff00" .. L["on"] .. "|r") or ("|cffff4040" .. L["off"] .. "|r")), 1, 1, 1)
            AQ.AddZoneCount(tt)
            tt:AddLine(L["Left-click: toggle markers"], 0.7, 0.7, 0.7)
            tt:AddLine(L["Right-click: options"], 0.7, 0.7, 0.7)
            tt:AddLine(L["Drag: move around the minimap"], 0.7, 0.7, 0.7)
            AQ.AddKeyLines(tt)
        end,
    })
    icon:Register(BUTTON_NAME, ldb, AQ.shared.minimap)
    M.registered = true
    M.UpdateButton()
end

-- Grey the button out while the markers are off, so it shows the state at a glance.
function M.UpdateButton()
    if not M.registered then return end
    local button = icon:GetMinimapButton(BUTTON_NAME)
    if not (button and button.icon) then return end
    local on = AQ.db.enabled
    button.icon:SetDesaturated(not on)
    button.icon:SetAlpha(on and 1 or 0.55)
end

-- Apply hide / lock / angle from the saved settings to the live button.
function M.ApplyButton()
    if not M.registered then return end
    local db = AQ.shared.minimap
    if db.hide then icon:Hide(BUTTON_NAME) else icon:Show(BUTTON_NAME) end
    if db.lock then icon:Lock(BUTTON_NAME) else icon:Unlock(BUTTON_NAME) end
    icon:Refresh(BUTTON_NAME, db)
end

function M.ResetButton()
    local db = AQ.shared.minimap
    db.minimapPos = AQ.minimapDefaults.minimapPos
    db.hide = false
    db.lock = false
    M.ApplyButton()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function() if AQ.db then M.Rebuild() end end)
