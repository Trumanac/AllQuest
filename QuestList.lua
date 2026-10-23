local AddOn, AQ = ...

-- A window listing the quests available to the player, with search, sort and filters.
-- Click a row for a waypoint, right-click it to hide the quest, giver, chain or zone.
local List = {}
AQ.QuestList = List

local L = AQ.L
local ROW_H, MAX_ROWS = 20, 250

local SCOPES = { { "zone", "This zone" }, { "continent", "This continent" }, { "all", "Everywhere" } }
local SORTS = { { "level", "Level" }, { "name", "Name" }, { "distance", "Distance" }, { "zone", "Zone" } }
-- Type filter: key as TypesFor names it, text shown.
local TYPE_FILTERS = { { "all", "All types" }, { "Group", "Group" }, { "Class", "Class" }, { "PvP", "PvP" }, { "Raid", "Raid" },
    { "Heroic", "Heroic" }, { "Legendary", "Legendary" }, { "Escort", "Escort" }, { "Profession", "Profession" },
    { "Dungeon", "Dungeon" }, { "Dropped item", "Dropped item" }, { "Repeatable", "Repeatable" } }

local state = { scope = "zone", sort = "level", filter = "all", text = "" }
local frame, content, status, search
local rows = {}
local dropdowns = {}

local function LabelOf(list, key)
    for _, item in ipairs(list) do
        if item[1] == key then return L[item[2]] end
    end
    return key
end

-- All quests of the chosen zones that pass the search and the type filter.
local function Collect()
    local zones = {}
    local home = AQ.PlayerZone()
    if state.scope == "zone" then
        if home then zones[1] = home end
    elseif state.scope == "continent" then
        local continent = home and AQ.ContinentOf(home)
        for _, id in ipairs(AQ.Data.MapIds()) do
            if continent and AQ.ContinentOf(id) == continent then zones[#zones + 1] = id end
        end
    else
        zones = AQ.Data.MapIds()
    end

    local needle = state.text:lower()
    local out = {}
    for _, zone in ipairs(zones) do
        local zoneInfo = C_Map.GetMapInfo(zone)
        local zoneName = zoneInfo and zoneInfo.name or "?"
        for _, pin in ipairs(AQ.PinsFor(zone)) do
            local giver = AQ.Data.StarterInfo(pin.entry)
            for _, q in ipairs(pin.quests) do
                local name = AQ.Data.QuestName(q.id)
                local keep = needle == ""
                    or name:lower():find(needle, 1, true) or giver:lower():find(needle, 1, true)
                    or zoneName:lower():find(needle, 1, true)
                if keep and state.filter ~= "all" then
                    keep = false
                    for _, t in ipairs(AQ.TypesFor(q, pin.entry.kind)) do
                        if t[3] == state.filter then keep = true break end
                    end
                end
                if keep then
                    out[#out + 1] = { q = q, pin = pin, entry = pin.entry, zoneName = zoneName, giver = giver, name = name }
                end
            end
        end
    end
    return out
end

local function Sort(list)
    for _, item in ipairs(list) do
        if state.sort == "distance" then item.dist = AQ.Minimap.Distance(item.entry) end
    end
    table.sort(list, function(a, b)
        if state.sort == "name" then
            if a.name ~= b.name then return a.name < b.name end
        elseif state.sort == "distance" then
            if a.dist ~= b.dist then
                if not a.dist then return false end
                if not b.dist then return true end
                return a.dist < b.dist
            end
        elseif state.sort == "zone" then
            if a.zoneName ~= b.zoneName then return a.zoneName < b.zoneName end
        end
        if a.q.level ~= b.q.level then return a.q.level < b.q.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.q.id < b.q.id
    end)
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetWidth(240)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.where:SetPoint("RIGHT", -4, 0)
    row.where:SetWidth(150)
    row.where:SetJustifyH("RIGHT")
    row.where:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if self.item then
            AQ.ShowQuestTooltip(self, { entry = self.item.entry, quests = { self.item.q }, top = self.item.q }, "ANCHOR_RIGHT")
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        if not self.item then return end
        if button == "RightButton" then
            AQ.OpenPinMenu(self, { entry = self.item.entry, quests = { self.item.q }, top = self.item.q })
        else
            AQ.SetWaypoint(self.item.entry, IsShiftKeyDown() and "arrow" or nil)
        end
    end)
    rows[i] = row
    return row
end

local function Distance(yards)
    if not yards then return "" end
    if yards >= 1000 then return ("%.1fk yd"):format(yards / 1000) end
    return ("%d yd"):format(yards)
end

function List.Refresh()
    if not (frame and frame:IsShown()) then return end
    if not AQ.Data.ready then
        status:SetText(L["Quest database not loaded"])
        return
    end
    local items = Collect()
    Sort(items)
    local shown = math.min(#items, MAX_ROWS)
    for i = 1, shown do
        local item = items[i]
        local row = Row(i)
        row.item = item
        local r, g, b = AQ.LevelColor(item.q.level, item.q.trivial)
        row.name:SetText(("|cff%02x%02x%02x[%d]|r %s"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), item.q.level, item.name))
        local where = state.scope == "zone" and item.giver or (item.giver .. " - " .. item.zoneName)
        if state.sort == "distance" then
            local d = Distance(item.dist)
            if d ~= "" then where = d .. "  " .. item.giver end
        end
        row.where:SetText(where)
        row:Show()
    end
    for i = shown + 1, #rows do
        rows[i].item = nil
        rows[i]:Hide()
    end
    content:SetHeight(math.max(shown * ROW_H, 1))
    if #items > shown then
        status:SetText((L["Showing %d of %d - narrow it with the search"]):format(shown, #items))
    elseif #items == 0 then
        status:SetText(L["No quests match"])
    else
        status:SetText((L["%d quests"]):format(#items))
    end
    for _, dd in ipairs(dropdowns) do dd:Update() end
end

local function MakeDropdown(x, width, list, key)
    local dd = AQ.NewDropdown(frame, width, function() return LabelOf(list, state[key]) end, function(root)
        for _, item in ipairs(list) do
            root:CreateRadio(L[item[2]], function() return state[key] == item[1] end, function()
                state[key] = item[1]
                List.Refresh()
            end)
        end
    end, function()
        for i, item in ipairs(list) do
            if item[1] == state[key] then
                state[key] = list[i % #list + 1][1]
                break
            end
        end
        List.Refresh()
    end)
    dd:SetPoint("TOPLEFT", x, -82)
    dropdowns[#dropdowns + 1] = dd
end

local function Create()
    frame = CreateFrame("Frame", "AllQuestList", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(470, 540)
    frame:SetPoint("CENTER", 180, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "AllQuestList")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText(L["AllQuest - available quests"])

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 16, -32)
    label:SetText(L["Search quests, givers or zones"])
    search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(340, 22)
    search:SetPoint("TOPLEFT", 22, -46)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(box)
        state.text = box:GetText() or ""
        List.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(60, 22)
    clear:SetText(L["Clear"])
    clear:SetPoint("LEFT", search, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)

    MakeDropdown(12, 140, SCOPES, "scope")
    MakeDropdown(158, 120, SORTS, "sort")
    MakeDropdown(284, 160, TYPE_FILTERS, "filter")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -112)
    scroll:SetPoint("BOTTOMRIGHT", -30, 34)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(420, 10)
    scroll:SetScrollChild(content)

    status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 14)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -16, 14)
    hint:SetText(L["Click: waypoint  -  Shift-click: arrow  -  Right-click: more"])

    -- distances change as the player moves
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        if state.sort ~= "distance" then return end
        elapsed = elapsed + dt
        if elapsed > 2 then
            elapsed = 0
            List.Refresh()
        end
    end)
    frame:SetScript("OnShow", function() List.Refresh() end)
end

-- Put text in the search box (used by the screenshot tool).
function List.SetSearch(text)
    if not frame then Create() end
    search:SetText(text or "")
end

function List.Toggle()
    if not frame then Create() end
    if frame:IsShown() then
        frame:Hide()
    else
        AQ.RaiseOverMap(frame, "HIGH")
        frame:Show()
    end
end
