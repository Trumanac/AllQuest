local AddOn, AQ = ...

-- A window listing the quests available to the player, with search, sort and filters.
-- Click a row for a waypoint, right-click it to hide the quest, giver, chain or zone.
-- The columns can be switched on and off (Columns button) and a click on a column header sorts by it.
local List = {}
AQ.QuestList = List

local L = AQ.L
local ROW_H, MAX_ROWS = 20, 250
local MIN_WIDTH, PAD = 560, 6

local SCOPES = { { "zone", "This zone" }, { "continent", "This continent" }, { "all", "Everywhere" } }
-- Type filter: key as TypesFor names it, text shown.
local TYPE_FILTERS = { { "all", "All types" }, { "Group", "Group" }, { "Class", "Class" }, { "PvP", "PvP" }, { "Raid", "Raid" },
    { "Heroic", "Heroic" }, { "Legendary", "Legendary" }, { "Escort", "Escort" }, { "Profession", "Profession" },
    { "Dungeon", "Dungeon" }, { "Dropped item", "Dropped item" }, { "Repeatable", "Repeatable" } }

-- Every column can be sorted. default: shown until the player changes it; always: cannot be switched off;
-- first: the direction a first click on the header sorts in (big numbers on top for rewards).
local COLUMNS = {
    { key = "level",    label = "Level",    short = "Lvl", w = 40,  align = "CENTER", default = true },
    { key = "name",     label = "Quest",    w = 190, align = "LEFT",   default = true, always = true },
    { key = "giver",    label = "Giver",    w = 120, align = "LEFT",   default = true },
    { key = "zone",     label = "Zone",     w = 110, align = "LEFT",   default = true },
    { key = "distance", label = "Distance", w = 66,  align = "RIGHT",  default = true },
    { key = "xp",       label = "XP",       w = 52,  align = "RIGHT",  descending = true },
    { key = "money",    label = "Money",    w = 84,  align = "RIGHT",  descending = true },
    { key = "rewards",  label = "Rewards",  w = 88,  align = "LEFT",   descending = true },
}
local REWARD_TIP = "Rewards come from the built-in data where it has them and from the quest windows you open in game. A dash means unknown."
local COLUMN_TIPS = { xp = REWARD_TIP, money = REWARD_TIP, rewards = REWARD_TIP }

local state = { scope = "zone", sort = "level", desc = false, filter = "all", text = "" }
local frame, content, status, search, headerBar
local rows, headers, buttons = {}, {}, {}
local items = {}           -- the quests currently listed (before sorting)
local layout = {}          -- visible columns with their x offset
local totalWidth = 0

local function ColumnOf(key)
    for _, c in ipairs(COLUMNS) do
        if c.key == key then return c end
    end
end

local function Prefs()
    local p = AQ.shared.list
    p.cols = p.cols or {}
    return p
end

local function IsOn(c)
    if c.always then return true end
    local v = Prefs().cols[c.key]
    if v == nil then return c.default == true end
    return v
end

local function LabelOf(list, key)
    for _, item in ipairs(list) do
        if item[1] == key then return L[item[2]] end
    end
    return key
end

---------------------------------------------------------------------------------------------
-- Data

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
    -- A quest can sit at many spots of one giver (a creature that spawns in several places, an item dropped all over a
    -- zone). The map marks every one; the list names the quest once per giver, at the spot nearest to the player.
    local byGiver = {}
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
                local key = q.id .. pin.entry.kind .. pin.entry.id
                local twin = keep and byGiver[key]
                if twin then
                    keep = false
                    local mine = AQ.Minimap.Distance(pin.entry)
                    twin.dist = twin.dist or AQ.Minimap.Distance(twin.entry)
                    if mine and (not twin.dist or mine < twin.dist) then
                        twin.pin, twin.entry, twin.zoneName, twin.dist = pin, pin.entry, zoneName, mine
                    elseif not twin.dist and pin.entry.rep then
                        twin.pin, twin.entry, twin.zoneName = pin, pin.entry, zoneName
                    end
                end
                if keep then
                    local xp, money, rewardItems, choices = AQ.Data.Rewards(q.id)
                    local row = { q = q, pin = pin, entry = pin.entry, zoneName = zoneName, giver = giver, name = name,
                        xp = xp, money = money, rewardItems = rewardItems, choices = choices,
                        rewardCount = rewardItems and (#rewardItems + #choices) or nil }
                    out[#out + 1] = row
                    byGiver[key] = row
                end
            end
        end
    end
    return out
end

local function SortValue(item, key)
    if key == "level" then return item.q.level
    elseif key == "name" then return item.name:lower()
    elseif key == "giver" then return item.giver:lower()
    elseif key == "zone" then return item.zoneName:lower()
    elseif key == "distance" then return item.dist
    elseif key == "xp" then return item.xp
    elseif key == "money" then return item.money
    elseif key == "rewards" then return item.rewardCount
    end
end

-- Unknown values (no distance, no reward data) always sit at the end, whichever way the list is sorted.
local function Sort(list)
    local key, desc = state.sort, state.desc
    if key == "distance" or ColumnOf("distance") and IsOn(ColumnOf("distance")) then
        for _, item in ipairs(list) do item.dist = AQ.Minimap.Distance(item.entry) end
    end
    table.sort(list, function(a, b)
        local va, vb = SortValue(a, key), SortValue(b, key)
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if desc then return va > vb end
            return va < vb
        end
        if a.q.level ~= b.q.level then return a.q.level < b.q.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.q.id < b.q.id
    end)
end

---------------------------------------------------------------------------------------------
-- Cell text

local function Distance(yards)
    if not yards then return "|cff808080-|r" end
    if yards >= 1000 then return ("%.1fk yd"):format(yards / 1000) end
    return ("%d yd"):format(yards)
end

local function Money(copper)
    if not copper then return "|cff808080-|r" end
    if copper <= 0 then return "|cff8080800|r" end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = ("|cffffd100%dg|r"):format(g) end
    if s > 0 then out[#out + 1] = ("|cffc7c7cf%ds|r"):format(s) end
    if c > 0 then out[#out + 1] = ("|cffeda55f%dc|r"):format(c) end
    return table.concat(out, " ")
end

local function ItemIcon(id)
    local icon
    if C_Item and C_Item.GetItemInfoInstant then
        icon = select(5, C_Item.GetItemInfoInstant(id))
    elseif GetItemInfoInstant then
        icon = select(5, GetItemInfoInstant(id))
    end
    return icon or 134400
end

local ICON, ICON_GAP, ICON_MAX = 16, 2, 4

-- The rewards cell shows a dash or "none" as text; with items it shows their icons (see ShowRewardIcons).
local function RewardText(item)
    if not item.rewardCount then return "|cff808080-|r" end
    if item.rewardCount == 0 then return "|cff808080" .. L["none"] .. "|r" end
    return ""
end

-- Hovering a reward icon replaces the quest panel with the game's own item tooltip.
local function IconButton(row, k)
    local b = row.icons[k]
    if b then return b end
    b = CreateFrame("Button", nil, row)
    b:SetSize(ICON, ICON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        if not self.itemId then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = C_Item and GameTooltip.SetItemByID and pcall(GameTooltip.SetItemByID, GameTooltip, self.itemId)
        if not ok then GameTooltip:SetHyperlink("item:" .. self.itemId) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- a click on an icon does what a click on the row does
    b:SetScript("OnClick", function(_, button)
        local handler = row:GetScript("OnClick")
        if handler then handler(row, button) end
    end)
    row.icons[k] = b
    return b
end

local function ShowRewardIcons(row, item, col)
    local shown = 0
    if col and item.rewardCount and item.rewardCount > 0 then
        for _, list in ipairs({ item.rewardItems, item.choices }) do
            for _, id in ipairs(list) do
                shown = shown + 1
                if shown <= ICON_MAX then
                    local b = IconButton(row, shown)
                    b.itemId = id
                    b.tex:SetTexture(ItemIcon(id))
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", row, "LEFT", col.x + 2 + (shown - 1) * (ICON + ICON_GAP), 0)
                    b:Show()
                end
            end
        end
    end
    for k = math.min(shown, ICON_MAX) + 1, #row.icons do
        row.icons[k].itemId = nil
        row.icons[k]:Hide()
    end
    if shown > ICON_MAX then
        row.more:ClearAllPoints()
        row.more:SetPoint("LEFT", row, "LEFT", col.x + 2 + ICON_MAX * (ICON + ICON_GAP), 0)
        row.more:SetText(("+%d"):format(shown - ICON_MAX))
        row.more:Show()
    else
        row.more:Hide()
    end
end

local function CellText(key, item)
    if key == "level" then
        local r, g, b = AQ.LevelColor(item.q.level, item.q.trivial)
        return ("|cff%02x%02x%02x%d|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), item.q.level)
    elseif key == "name" then return item.name
    elseif key == "giver" then return item.giver
    elseif key == "zone" then return item.zoneName
    elseif key == "distance" then return Distance(item.dist)
    elseif key == "xp" then return item.xp and tostring(item.xp) or "|cff808080-|r"
    elseif key == "money" then return Money(item.money)
    elseif key == "rewards" then return RewardText(item)
    end
end

-- Reward lines under the quest panel when hovering a row.
local function AddRewardLines(item)
    if not (item.xp or item.money or item.rewardCount) then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Rewards"], 1, 0.82, 0)
    if item.xp and item.xp > 0 then GameTooltip:AddLine("   " .. item.xp .. " " .. L["XP"], 1, 1, 1) end
    if item.money and item.money > 0 then GameTooltip:AddLine("   " .. Money(item.money), 1, 1, 1) end
    local function list(ids, heading)
        if not ids or #ids == 0 then return end
        if heading then GameTooltip:AddLine("   " .. heading, 0.7, 0.7, 0.7) end
        for _, id in ipairs(ids) do
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
            if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            GameTooltip:AddLine(("   |T%s:14|t %s"):format(ItemIcon(id), name or ("Item " .. id)), 1, 1, 1)
        end
    end
    list(item.rewardItems)
    list(item.choices, #(item.rewardItems or {}) > 0 and L["Choose one:"] or nil)
    if item.rewardCount == 0 and not (item.xp and item.xp > 0) and not (item.money and item.money > 0) then
        GameTooltip:AddLine("   " .. L["none"], 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------------------------
-- Layout: which columns are shown and where

local function PlaceRow(row)
    for _, c in ipairs(COLUMNS) do
        local cell = row.cells[c.key]
        local col
        for _, v in ipairs(layout) do
            if v.key == c.key then col = v end
        end
        if col then
            if not cell then
                cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cell:SetWordWrap(false)
                row.cells[c.key] = cell
            end
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", col.x + 2, 0)
            cell:SetWidth(c.w - PAD)
            cell:SetJustifyH(c.align)
            cell:Show()
        elseif cell then
            cell:Hide()
        end
    end
end

local function Header(c)
    local h = headers[c.key]
    if h then return h end
    h = CreateFrame("Button", nil, headerBar)
    h:SetHeight(18)
    h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.text:SetJustifyH(c.align)
    h.text:SetText(L[c.short or c.label])
    h.arrow = h:CreateTexture(nil, "OVERLAY")
    h.arrow:SetSize(9, 9)
    h.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    h.arrow:Hide()
    h:SetScript("OnClick", function()
        if state.sort == c.key then
            state.desc = not state.desc
        else
            state.sort = c.key
            state.desc = c.descending == true
        end
        List.SortChanged()
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L[c.label], 1, 1, 1)
        GameTooltip:AddLine(L["Click to sort"], 0.7, 0.7, 0.7)
        if COLUMN_TIPS[c.key] then GameTooltip:AddLine(L[COLUMN_TIPS[c.key]], 1, 0.82, 0, true) end
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    headers[c.key] = h
    return h
end

local function Layout()
    layout = {}
    local x = 0
    for _, c in ipairs(COLUMNS) do
        if IsOn(c) then
            layout[#layout + 1] = { key = c.key, x = x }
            x = x + c.w
        end
    end
    totalWidth = x
    local width = math.max(MIN_WIDTH, totalWidth + 52)
    local screen = UIParent:GetWidth()
    if screen and width > screen - 40 then width = screen - 40 end
    frame:SetWidth(width)
    content:SetWidth(totalWidth)
    for _, c in ipairs(COLUMNS) do
        local h = Header(c)
        local col
        for _, v in ipairs(layout) do
            if v.key == c.key then col = v end
        end
        if col then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", headerBar, "TOPLEFT", col.x, 0)
            h:SetWidth(c.w)
            h.text:ClearAllPoints()
            h.text:SetPoint("LEFT", 2, 0)
            h.text:SetPoint("RIGHT", -12, 0)
            h.arrow:ClearAllPoints()
            h.arrow:SetPoint("RIGHT", -2, 0)
            h:Show()
        else
            h:Hide()
        end
    end
    for _, row in ipairs(rows) do PlaceRow(row) end
end

---------------------------------------------------------------------------------------------
-- Rows

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.cells = {}
    row.icons = {}
    row.more = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.band = row:CreateTexture(nil, "BACKGROUND")
    row.band:SetAllPoints()
    row.band:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.05 or 0)
    PlaceRow(row)
    row:SetScript("OnEnter", function(self)
        if self.item then
            AQ.ShowQuestTooltip(self, { entry = self.item.entry, quests = { self.item.q }, top = self.item.q }, "ANCHOR_RIGHT")
            AddRewardLines(self.item)
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

local function UpdateHeaders()
    for _, c in ipairs(COLUMNS) do
        local h = headers[c.key]
        if h then
            local sorted = state.sort == c.key
            h.arrow:SetShown(sorted)
            if sorted then
                -- the arrow texture points up; flip it for descending
                if state.desc then h.arrow:SetTexCoord(0, 0.5625, 1, 0) else h.arrow:SetTexCoord(0, 0.5625, 0, 1) end
            end
            if sorted then h.text:SetTextColor(1, 1, 1) else h.text:SetTextColor(1, 0.82, 0) end
        end
    end
end

-- Sort what has been collected and draw it.
local function Render()
    Sort(items)
    local shown = math.min(#items, MAX_ROWS)
    for i = 1, shown do
        local item = items[i]
        local row = Row(i)
        row.item = item
        for _, col in ipairs(layout) do
            row.cells[col.key]:SetText(CellText(col.key, item))
        end
        local rewardCol
        for _, col in ipairs(layout) do
            if col.key == "rewards" then rewardCol = col end
        end
        ShowRewardIcons(row, item, rewardCol)
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
    UpdateHeaders()
    for _, b in ipairs(buttons) do b.Update() end
end

function List.Refresh()
    if not (frame and frame:IsShown()) then return end
    if not AQ.Data.ready then
        status:SetText(L["Quest database not loaded"])
        return
    end
    items = Collect()
    Render()
end

function List.SortChanged()
    local p = Prefs()
    p.sort, p.desc = state.sort, state.desc
    if frame and frame:IsShown() and AQ.Data.ready then Render() end
end

---------------------------------------------------------------------------------------------
-- Controls

local function MenuButton(x, width, text, entries)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, -82)
    b:SetScript("OnClick", function(self) AQ.OpenMenu(self, entries()) end)
    b.Update = function() b:SetText(text()) end
    b.Update()
    buttons[#buttons + 1] = b
    return b
end

local function Choices(list, key, after)
    return function()
        local entries = {}
        for _, item in ipairs(list) do
            entries[#entries + 1] = { text = L[item[2]], checked = function() return state[key] == item[1] end,
                onClick = function() state[key] = item[1] if after then after() end List.Refresh() end }
        end
        return entries
    end
end

local function SortEntries()
    local entries = {}
    for _, c in ipairs(COLUMNS) do
        entries[#entries + 1] = { text = L[c.label], checked = function() return state.sort == c.key end,
            onClick = function()
                if state.sort ~= c.key then state.sort, state.desc = c.key, c.descending == true end
                List.SortChanged()
            end }
    end
    return entries
end

local function ColumnEntries()
    local entries = {}
    for _, c in ipairs(COLUMNS) do
        if not c.always then
            entries[#entries + 1] = { text = L[c.label], keepOpen = true, checked = function() return IsOn(c) end,
                onClick = function()
                    Prefs().cols[c.key] = not IsOn(c)
                    Layout()
                    -- a hidden column cannot keep the list sorted by it unnoticed: keep the sort, the header is just gone
                    if frame:IsShown() and AQ.Data.ready then Render() end
                end }
        end
    end
    return entries
end

local function Create()
    frame = CreateFrame("Frame", "AllQuestList", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(MIN_WIDTH, 540)
    frame:SetPoint("CENTER", 180, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)                 -- clicking it brings it in front of other windows (the settings)
    frame:Hide()
    tinsert(UISpecialFrames, "AllQuestList")

    local p = Prefs()
    if p.sort and ColumnOf(p.sort) then state.sort, state.desc = p.sort, p.desc == true end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText(L["AllQuest - available quests"])

    -- a small gear in the title bar, beside the close button, opens the settings
    local gear = CreateFrame("Button", nil, frame)
    gear:SetSize(18, 18)
    gear:SetPoint("TOPRIGHT", -28, -4)
    gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetPushedTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    gear:SetScript("OnClick", function() AQ.ToggleOptions() end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Settings"], 1, 1, 1)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 16, -32)
    label:SetText(L["Search quests, givers or zones"])
    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(60, 22)
    clear:SetText(L["Clear"])
    clear:SetPoint("TOPRIGHT", -14, -46)
    search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetHeight(22)
    search:SetPoint("TOPLEFT", 22, -46)
    search:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(box)
        state.text = box:GetText() or ""
        List.Refresh()
    end)
    search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    clear:SetScript("OnClick", function() search:SetText("") search:ClearFocus() end)

    MenuButton(12, 118, function() return LabelOf(SCOPES, state.scope) end, Choices(SCOPES, "scope"))
    MenuButton(134, 130, function() return (L["Sort: %s"]):format(L[ColumnOf(state.sort).label]) end, SortEntries)
    local dir = MenuButton(268, 54, function() return state.desc and L["Desc"] or L["Asc"] end, function()
        return {}
    end)
    dir:SetScript("OnClick", function()
        state.desc = not state.desc
        List.SortChanged()
    end)
    dir:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(state.desc and L["Descending - click for ascending"] or L["Ascending - click for descending"], 1, 1, 1)
        GameTooltip:Show()
    end)
    dir:SetScript("OnLeave", function() GameTooltip:Hide() end)
    MenuButton(326, 124, function() return LabelOf(TYPE_FILTERS, state.filter) end, Choices(TYPE_FILTERS, "filter"))
    MenuButton(454, 94, function() return L["Columns"] end, ColumnEntries)

    headerBar = CreateFrame("Frame", nil, frame)
    headerBar:SetPoint("TOPLEFT", 10, -110)
    headerBar:SetPoint("TOPRIGHT", -30, -110)
    headerBar:SetHeight(18)
    local strip = headerBar:CreateTexture(nil, "BACKGROUND")
    strip:SetAllPoints()
    strip:SetColorTexture(0.2, 0.16, 0.05, 0.55)
    local underline = headerBar:CreateTexture(nil, "BORDER")
    underline:SetPoint("BOTTOMLEFT")
    underline:SetPoint("BOTTOMRIGHT")
    underline:SetHeight(1)
    underline:SetColorTexture(1, 0.82, 0, 0.6)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -130)
    scroll:SetPoint("BOTTOMRIGHT", -30, 34)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(420, 10)
    scroll:SetScrollChild(content)

    status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 16, 14)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -16, 14)
    hint:SetText(L["Click: waypoint  -  Shift-click: arrow  -  Right-click: more"])

    Layout()

    -- distances change as the player moves
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        if not ((state.sort == "distance" or IsOn(ColumnOf("distance"))) and AQ.Data.ready) then return end
        elapsed = elapsed + dt
        if elapsed > 2 then
            elapsed = 0
            Render()
        end
    end)
    frame:SetScript("OnShow", function() List.Refresh() end)
    frame:SetScript("OnHide", AQ.CloseMenu)
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
        frame:Raise()
    end
end
