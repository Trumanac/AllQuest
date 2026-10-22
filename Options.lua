local AddOn, AQ = ...

-- Settings. The same controls exist in two places: the game's own options window (Options > AddOns > AllQuest)
-- and a small standalone window (/allquest, the minimap button, the world map button). Only one is ever open:
-- while the game's options window is up, every way of opening the settings goes to its AllQuest page instead.
-- The page has presets and a few basics on top, and an "Advanced" part that can be folded away.
local standalone, panel, category
local builders = {}      -- one per place the controls were built, so each can be refreshed

local L = AQ.L
local ROW_CHECK, ROW_STEP, GAP = 24, 26, 8

---------------------------------------------------------------------------------------------
-- Row builders (a builder keeps the parent frame and the running vertical position)

-- A dropdown frame (also used by the quest list). text() is the closed box's text, setup(root) fills the menu;
-- clients without the modern dropdown get a button that calls step() instead. dd.Update() refreshes the text.
function AQ.NewDropdown(parent, width, text, setup, step)
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetupMenu(function(_, root) setup(root) end)
    else
        dd = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        dd:SetHeight(24)
        dd.OverrideText = dd.SetText
        dd:SetScript("OnClick", step)
    end
    dd:SetWidth(width)
    dd.Update = function() dd:OverrideText(text()) end
    dd.Update()
    return dd
end

local function NewBuilder(parent, startY)
    local B = { parent = parent, y = startY, updates = {} }

    function B:Header(text)
        self.y = self.y - GAP
        local fs = self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 16, self.y)
        fs:SetText(L[text])
        self.y = self.y - 20
    end

    function B:Check(label, get, set, tooltip)
        local cb = CreateFrame("CheckButton", nil, self.parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 14, self.y + 4)
        cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
        cb.label:SetText(L[label])
        cb:SetScript("OnClick", function(btn)
            set(btn:GetChecked() and true or false)
            AQ.SettingsChanged()
        end)
        if tooltip then
            cb:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine(L[tooltip], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        self.updates[#self.updates + 1] = function() cb:SetChecked(get()) end
        self.y = self.y - ROW_CHECK
    end

    function B:Stepper(label, get, set, step, min, max, format, disabledWhen)
        local text = self.parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 20, self.y - 5)
        text:SetText(L[label])
        local minus = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        minus:SetSize(24, 22)
        minus:SetText("-")
        minus:SetPoint("TOPLEFT", 210, self.y)
        local value = self.parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
        value:SetWidth(44)
        local plus = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        plus:SetSize(24, 22)
        plus:SetText("+")
        plus:SetPoint("LEFT", value, "RIGHT", 0, 0)
        local function Bump(delta)
            local v = math.floor((get() + delta * step) / step + 0.5) * step   -- no float drift
            set(math.max(min, math.min(max, v)))
            AQ.SettingsChanged()
        end
        minus:SetScript("OnClick", function() Bump(-1) end)
        plus:SetScript("OnClick", function() Bump(1) end)
        self.updates[#self.updates + 1] = function()
            value:SetText(format:format(get()))
            local off = disabledWhen and disabledWhen()
            minus:SetEnabled(not off)
            plus:SetEnabled(not off)
            local c = off and 0.5 or 1
            text:SetTextColor(c, c, c)
        end
        self.y = self.y - ROW_STEP
    end

    function B:Button(label, onClick, width)
        local b = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        b:SetSize(width or 170, 22)
        b:SetText(L[label])
        b:SetPoint("TOPLEFT", 20, self.y)
        b:SetScript("OnClick", function() onClick() AQ.SettingsChanged() end)
        self.y = self.y - ROW_STEP
    end

    -- A dropdown. text() is the closed box's text, setup(root) fills the menu; clients without the modern
    -- dropdown get a button that calls step() instead. Returns the frame.
    function B:Dropdown(x, width, text, setup, step)
        local dd = AQ.NewDropdown(self.parent, width, text, setup, step)
        dd:SetPoint("TOPLEFT", x, self.y)
        self.updates[#self.updates + 1] = dd.Update
        return dd
    end

    -- A row of buttons: { { label, onClick, width }, ... }; each is only shown while its optional visible() is true.
    function B:Buttons(list, x)
        local left = x or 20
        local made = {}
        for _, spec in ipairs(list) do
            local b = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
            b:SetSize(spec[3] or 90, 24)
            b:SetText(L[spec[1]])
            b:SetPoint("TOPLEFT", left, self.y)
            left = left + (spec[3] or 90) + 4
            b:SetScript("OnClick", spec[2])
            if spec.visible then
                self.updates[#self.updates + 1] = function() b:SetShown(spec.visible()) end
            end
            made[#made + 1] = b
        end
        self.y = self.y - 30
        return made
    end

    -- The preset row: a dropdown with the built-in presets and the ones the player saved, a Save button
    -- (asks for a name) and, while a saved preset is in use, a Delete button.
    function B:Presets()
        local function Names()
            local names = {}
            for _, preset in ipairs(AQ.presetList) do names[#names + 1] = preset.name end
            for _, name in ipairs(AQ.UserPresetNames()) do names[#names + 1] = name end
            return names
        end
        local dd = self:Dropdown(18, 190,
            function()
                local _, _, name = AQ.CurrentPreset()
                return name and L[name] or L["Custom (not saved)"]
            end,
            function(root)
                local kind, key = AQ.CurrentPreset()
                for _, preset in ipairs(AQ.presetList) do
                    root:CreateRadio(L[preset.name], function() return kind == "builtin" and key == preset.key end,
                        function() AQ.ApplyPreset(preset.key) end)
                end
                local saved = AQ.UserPresetNames()
                if #saved > 0 then
                    root:CreateDivider()
                    root:CreateTitle(L["Saved"])
                    for _, name in ipairs(saved) do
                        root:CreateRadio(name, function() return kind == "user" and key == name end,
                            function() AQ.ApplyPreset(name) end)
                    end
                end
            end,
            function()
                local names = Names()
                local _, _, current = AQ.CurrentPreset()
                local nextIndex = 1
                for i, name in ipairs(names) do
                    if name == current then nextIndex = i % #names + 1 end
                end
                AQ.ApplyPreset(names[nextIndex])
            end)
        local save = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        save:SetSize(62, 24)
        save:SetText(L["Save..."])
        save:SetPoint("LEFT", dd, "RIGHT", 6, 0)
        save:SetScript("OnClick", function() StaticPopup_Show("ALLQUEST_SAVE_PRESET") end)
        local delete = CreateFrame("Button", nil, self.parent, "UIPanelButtonTemplate")
        delete:SetSize(62, 24)
        delete:SetText(L["Delete"])
        delete:SetPoint("LEFT", save, "RIGHT", 4, 0)
        delete:SetScript("OnClick", function()
            local kind, name = AQ.CurrentPreset()
            if kind == "user" then AQ.DeletePreset(name) end
        end)
        self.updates[#self.updates + 1] = function()
            local kind = AQ.CurrentPreset()
            delete:SetShown(kind == "user")
        end
        self.y = self.y - 30
    end

    -- Small text that follows the settings: `get` returns the string.
    function B:Dynamic(get, height)
        local fs = self.parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 18, self.y - 2)
        fs:SetWidth(300)
        fs:SetJustifyH("LEFT")
        self.updates[#self.updates + 1] = function() fs:SetText(get()) end
        self.y = self.y - (height or 30)
    end

    function B:Refresh()
        for _, update in ipairs(self.updates) do update() end
    end

    return B
end

-- Asks for a name to save the current settings under.
StaticPopupDialogs["ALLQUEST_SAVE_PRESET"] = {
    text = L["Name for this AllQuest preset:"],
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 24,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local box = self.EditBox or self.editBox
        box:SetText("")
        box:SetFocus()
    end,
    OnAccept = function(self)
        AQ.SavePreset((self.EditBox or self.editBox):GetText())
    end,
    EditBoxOnEnterPressed = function(box)
        local popup = box:GetParent()
        AQ.SavePreset(box:GetText())
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

-- Pop-ups that ask for text.
local function BoxOf(popup) return popup.EditBox or popup.editBox end

StaticPopupDialogs["ALLQUEST_NEW_PROFILE"] = {
    text = L["Name for the new AllQuest profile (it starts as a copy of your current settings and is used by this character):"],
    button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 24, timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self) local box = BoxOf(self) box:SetText("") box:SetFocus() end,
    OnAccept = function(self) AQ.ProfileCreate(BoxOf(self):GetText()) end,
    EditBoxOnEnterPressed = function(box) local popup = box:GetParent() AQ.ProfileCreate(box:GetText()) popup:Hide() end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

StaticPopupDialogs["ALLQUEST_EXPORT"] = {
    text = L["Your AllQuest settings. Copy this text (Ctrl+C):"],
    button1 = CLOSE, hasEditBox = true, editBoxWidth = 320, timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self)
        local box = BoxOf(self)
        box:SetText(AQ.ExportString())
        box:SetFocus()
        box:HighlightText()
    end,
    EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

local function DoImport(text)
    local ok, result = AQ.ImportString(text)
    if ok then AQ.Print(("imported %d settings."):format(result)) else AQ.Print("import failed: " .. result) end
end

StaticPopupDialogs["ALLQUEST_IMPORT"] = {
    text = L["Paste an AllQuest settings string (Ctrl+V):"],
    button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, editBoxWidth = 320, timeout = 0, whileDead = true, hideOnEscape = true,
    OnShow = function(self) local box = BoxOf(self) box:SetText("") box:SetFocus() end,
    OnAccept = function(self) DoImport(BoxOf(self):GetText()) end,
    EditBoxOnEnterPressed = function(box) local popup = box:GetParent() DoImport(box:GetText()) popup:Hide() end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
}

StaticPopupDialogs["ALLQUEST_RESET"] = {
    text = L["Reset every AllQuest setting of this profile to the defaults? Hidden quests, saved presets and other profiles are kept."],
    button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() AQ.ResetSettings() end,
}

-- All the settings rows. `resize(height)` tells the host how tall everything is now.
local function Fill(B, resize)
    local db = function() return AQ.db end
    local function Key(tbl, key) return function() return tbl()[key] end, function(v) tbl()[key] = v end end
    local function Check(builder, label, key, tip) local g, s = Key(db, key) builder:Check(label, g, s, tip) end
    local function Stepper(builder, label, key, ...) local g, s = Key(db, key) builder:Stepper(label, g, s, ...) end
    -- A checkbox for a setting that is stored the other way round ("hide ..."): ticked means shown.
    local function CheckNot(builder, label, key, tip)
        builder:Check(label, function() return not AQ.db[key] end, function(v) AQ.db[key] = not v end, tip)
    end

    B:Header("Preset")
    B:Presets()
    B:Dynamic(function()
        local kind, _, name = AQ.CurrentPreset()
        if kind then return L["Using the preset"] .. ": " .. L[name] end
        return L["You changed some settings. Save... keeps them under a name you choose."]
    end, 30)

    -- Every box reads the same way: ticked = the thing is shown / switched on.
    B:Header("Basics")
    Check(B, "Show quest markers", "enabled", "Master switch for the world map and minimap markers.")
    Check(B, "Show markers on the minimap", "minimapPins")
    Check(B, "Use colour-blind friendly colours", "colorblind",
        "Swaps the red / green / orange scale for purple, orange, yellow and blue. See also 'Show difficulty as a number' under Advanced.")
    B:Check("Show minimap button", function() return not AQ.shared.minimap.hide end,
        function(v) AQ.shared.minimap.hide = not v; AQ.Minimap.ApplyButton() end)

    B:Button("Open the quest list", function() AQ.QuestList.Toggle() end, 170)

    -- the fold-away part
    local toggle = CreateFrame("Button", nil, B.parent, "UIPanelButtonTemplate")
    toggle:SetSize(200, 22)
    toggle:SetPoint("TOPLEFT", 20, B.y - 10)
    local baseY = B.y - 10 - ROW_STEP
    local adv = CreateFrame("Frame", nil, B.parent)
    adv:SetPoint("TOPLEFT", 0, baseY)
    adv:SetWidth(340)
    local A = NewBuilder(adv, 0)

    A:Header("Which quests to show")
    Check(A, "Show only quests in my current zone", "currentZoneOnly",
        "Only the zone you are standing in gets markers, on the world map and the minimap. Off: nearby zones and the zone you are viewing show too.")
    Check(A, "Show quests of every level", "showAll", "Ignore the 'levels above me' limit.")
    Stepper(A, "Levels above me to show", "levelsAbove", 1, 0, 60, "%d", function() return AQ.db.showAll end)
    A:Dynamic(function() return L["Same scale as the game: up to +2 yellow, +3/+4 orange, +5 and up red."] end, 22)
    CheckNot(A, "Show low level (grey) quests", "hideLowLevel",
        "Quests that are trivial for you. Off: they are hidden.")
    Check(A, "Show repeatable quests", "showRepeatable")
    Check(A, "Show holiday quests (while the holiday is on)", "showEventQuests",
        "Quests tied to a holiday appear only while that holiday is running, according to the game calendar.")
    Check(A, "Show dungeon quests (at the entrance)", "showDungeonQuests",
        "Quests given inside a dungeon get a marker at the dungeon's entrance, tagged D.")
    Check(A, "Show dropped-item quests", "showDropQuests",
        "Quests started by an item get markers where the item drops, tagged i. The tooltip says what drops it.")
    CheckNot(A, "Show quests needing a skill I lack", "checkSkills",
        "Quests that need a profession or a higher skill level than you have. Off: they are hidden.")
    CheckNot(A, "Show quests needing reputation I lack", "checkReputation",
        "Quests that need a faction standing you have not reached (or that you have passed). Off: they are hidden.")
    Check(A, "Learn quests as I find them", "learnQuests",
        "When a quest giver offers a quest AllQuest does not know yet, it remembers it and shows it from then on.")

    A:Header("Marker look")
    Check(A, "Show difficulty colours", "colorByLevel",
        "Tint each marker by how hard its quest is for you. Off: every marker is gold (grey when trivial or not yet available).")
    Check(A, "Show difficulty as a number (+3, -2)", "difficultyText",
        "Writes how many levels the quest is above (+) or below (-) you under the marker and in the quest panel. Handy with colour-blind colours, or instead of colours.")
    Check(A, "Show quest type tag (G D R P i ...)", "showTypeTags",
        "C class, D dungeon, E world event, G group, H heroic, i dropped item, L legendary, P PvP, R raid, S escort, T profession.")
    Check(A, "Show quest level under marker", "showLevelText")
    Stepper(A, "World map marker size", "iconScale", 0.1, 0.5, 2.0, "%.1f")
    A:Dynamic(function() return AQ.LegendText() end, 34)

    A:Header("Display")
    local STYLES = { { "exclaim", "Exclamation" }, { "diamond", "Diamond" }, { "round", "Round" } }
    local function StyleName()
        for _, s in ipairs(STYLES) do
            if s[1] == AQ.db.markerStyle then return L[s[2]] end
        end
        return L["Exclamation"]
    end
    local shape = A.parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    shape:SetPoint("TOPLEFT", 20, A.y - 5)
    shape:SetText(L["Marker shape"])
    A:Dropdown(150, 150, StyleName, function(root)
        for _, s in ipairs(STYLES) do
            root:CreateRadio(L[s[2]], function() return AQ.db.markerStyle == s[1] end,
                function() AQ.db.markerStyle = s[1] AQ.SettingsChanged() end)
        end
    end, function()
        for i, s in ipairs(STYLES) do
            if s[1] == AQ.db.markerStyle then
                AQ.db.markerStyle = STYLES[i % #STYLES + 1][1]
                break
            end
        end
        AQ.SettingsChanged()
    end)
    A.y = A.y - 30
    Check(A, "Dark outline around markers", "markerOutline",
        "Draws a thin dark outline behind every marker so it stands out on bright or busy maps.")
    Stepper(A, "Marker opacity", "markerAlpha", 0.1, 0.3, 1.0, "%.1f")
    Stepper(A, "Text size on markers", "labelSize", 1, 8, 16, "%d")
    Stepper(A, "Quest panel size", "tooltipScale", 0.1, 0.7, 1.6, "%.1f")

    A:Header("Quest panel (on hover)")
    Check(A, "Show the panel on world map markers", "showTooltips",
        "Hovering a world map marker shows what it offers. Off: the markers ignore the mouse completely.")
    Check(A, "Show full details in the panel", "tooltipDetails",
        "On: type, requirements, what drops an item and more. Off: just the giver and each quest's level and name.")
    Check(A, "Show the quest chain (before / next) in the panel", "showChainInfo",
        "One extra line naming the quest that comes before and the quest it unlocks. Only in the detailed panel.")
    Check(A, "Show the panel on minimap markers", "minimapTooltips",
        "Hovering a minimap marker shows the same quest panel. Off: minimap markers do not catch the mouse at all.")

    A:Header("Quest types")
    for _, t in ipairs(AQ.FilterTypes) do
        local key = t[1]
        A:Check("Show " .. t[2] .. " quests", function() return not AQ.db.hiddenTypes[key] end,
            function(v) AQ.db.hiddenTypes[key] = (not v) or nil end,
            "Switch off a kind of quest to hide every quest of that type. The same choices are in the filter button on the world map.")
    end
    Check(A, "Show the quest-type filter button on the world map", "showFilterButton",
        "A small button next to the AllQuest button on the world map. It opens a menu to switch kinds of quests on and off. Orange while something is filtered out.")

    A:Header("World map")
    Check(A, "Show the whole continent when zoomed in (OpenMap)", "wholeContinent",
        "With OpenMap's seamless map, markers for the whole continent are loaded while you are zoomed in, so nothing pops in as you move around. Zoomed out, only your own zone shows. Off: only the zone you are viewing and your own.")

    Check(A, "Show the quest list button on the world map", "showListButton",
        "A small book button next to the AllQuest button that opens the quest list. The list also opens with /aq list or a middle-click on the minimap button.")
    Check(A, "Hide far markers while zooming if the frame rate drops (OpenMap)", "zoomSafeguard",
        "Only acts when the frame rate is low while you zoom or pan the seamless map: markers outside your own zone are hidden until the view settles.")

    A:Header("Minimap")
    Stepper(A, "Minimap marker size", "minimapScale", 0.1, 0.5, 2.5, "%.1f")
    A:Check("Allow moving the minimap button", function() return not AQ.shared.minimap.lock end,
        function(v) AQ.shared.minimap.lock = not v; AQ.Minimap.ApplyButton() end,
        "On: drag the button around the minimap edge. Off: it stays where it is.")
    A:Stepper("Button angle (degrees)", function() return AQ.shared.minimap.minimapPos or 215 end,
        function(v) AQ.shared.minimap.minimapPos = v % 360; AQ.Minimap.ApplyButton() end, 15, -1000, 1000, "%d")
    A:Button("Reset button position", AQ.Minimap.ResetButton)

    A:Header("Notices")
    Check(A, "Tell me when new quests become available", "notifyNewQuests",
        "A chat message after a level-up or a turned-in quest opens up new quests, naming the first few.")

    A:Header("Hidden quests and givers")
    A:Dynamic(function()
        local n = #AQ.IgnoredList()
        return n == 0 and L["Nothing hidden. Right-click a marker to hide a quest or a giver."]
            or (L["%d hidden. Pick one to bring it back."]):format(n)
    end, 24)
    local restore = A:Dropdown(18, 190, function() return L["Restore..."] end, function(root)
        local list = AQ.IgnoredList()
        if #list == 0 then
            root:CreateTitle(L["Nothing hidden"])
            return
        end
        for _, item in ipairs(list) do
            local kindName = ({ quest = "Quest", giver = "Giver", zone = "Zone", chain = "Chain" })[item.kind]
            root:CreateButton(L[kindName] .. ": " .. item.name,
                function() AQ.Unignore(item.kind, item.key) end)
        end
    end, function() end)
    local restoreAll = CreateFrame("Button", nil, A.parent, "UIPanelButtonTemplate")
    restoreAll:SetSize(110, 24)
    restoreAll:SetText(L["Restore all"])
    restoreAll:SetPoint("LEFT", restore, "RIGHT", 6, 0)
    restoreAll:SetScript("OnClick", AQ.RestoreAllIgnored)
    A.y = A.y - 30
    A:Button("Hide the zone I'm in", function()
        local zone = AQ.PlayerZone()
        local info = zone and C_Map.GetMapInfo(zone)
        if info and info.name then AQ.IgnoreZone(zone, info.name) end
    end, 170)

    A:Header("Profile and sharing")
    A:Dynamic(function()
        return (L["This character uses the profile: %s"]):format(AQ.ProfileName())
    end, 18)
    local profile = A:Dropdown(18, 190, function() return AQ.ProfileName() end, function(root)
        for _, name in ipairs(AQ.ProfileNames()) do
            root:CreateRadio(name, function() return AQ.ProfileName() == name end, function() AQ.ProfileUse(name) end)
        end
        root:CreateDivider()
        root:CreateButton(L["New profile..."], function() StaticPopup_Show("ALLQUEST_NEW_PROFILE") end)
    end, function() StaticPopup_Show("ALLQUEST_NEW_PROFILE") end)
    local deleteProfile = CreateFrame("Button", nil, A.parent, "UIPanelButtonTemplate")
    deleteProfile:SetSize(110, 24)
    deleteProfile:SetText(L["Delete profile"])
    deleteProfile:SetPoint("LEFT", profile, "RIGHT", 6, 0)
    deleteProfile:SetScript("OnClick", function() AQ.ProfileDelete(AQ.ProfileName()) end)
    A.updates[#A.updates + 1] = function() deleteProfile:SetShown(AQ.ProfileName() ~= "Default") end
    A.y = A.y - 30
    A:Buttons({
        { "New profile...", function() StaticPopup_Show("ALLQUEST_NEW_PROFILE") end, 120 },
        { "Export settings...", function() StaticPopup_Show("ALLQUEST_EXPORT") end, 140 },
        { "Import settings...", function() StaticPopup_Show("ALLQUEST_IMPORT") end, 140 },
    }, 18)
    A:Dynamic(function()
        local m = AQ.DB.meta
        return (L["Quest data: %s, %d quests, %d giver spots."]):format(m.date or "?", AQ.Data.questCount or 0, AQ.Data.entryCount or 0)
    end, 18)

    A:Header("Interface")
    CheckNot(A, "Show Blizzard's objective tracker", "hideTracker",
        "The quest list on the right side of the screen. Off: AllQuest hides it.")

    A:Button("Reset all settings", function() StaticPopup_Show("ALLQUEST_RESET") end)

    local advHeight = -A.y + 10
    adv:SetHeight(advHeight)
    toggle:SetScript("OnClick", function()
        AQ.shared.advancedOpen = not AQ.shared.advancedOpen
        AQ.RefreshOptions()
    end)
    B.updates[#B.updates + 1] = function()
        local open = AQ.shared.advancedOpen
        toggle:SetText(open and L["Advanced settings  [-]"] or L["Advanced settings  [+]"])
        adv:SetShown(open)
        resize(-baseY + 10 + (open and advHeight or 0))
    end
    -- the advanced rows refresh with the rest
    B.updates[#B.updates + 1] = function() A:Refresh() end
end

---------------------------------------------------------------------------------------------
-- The two places

-- A scrolling area inside `host` holding all the settings.
local function BuildScrolling(host, left, top, right, bottom)
    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", left, top)
    scroll:SetPoint("BOTTOMRIGHT", right, bottom)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(340)
    child:SetHeight(400)
    scroll:SetScrollChild(child)
    local B = NewBuilder(child, -6)
    Fill(B, function(height) child:SetHeight(height) end)
    builders[#builders + 1] = B
end

local function CreateStandalone()
    standalone = CreateFrame("Frame", "AllQuestOptions", UIParent, "BasicFrameTemplateWithInset")
    standalone:SetSize(380, 560)
    standalone:SetPoint("CENTER")
    standalone:SetMovable(true)
    standalone:EnableMouse(true)
    standalone:RegisterForDrag("LeftButton")
    standalone:SetScript("OnDragStart", standalone.StartMoving)
    standalone:SetScript("OnDragStop", standalone.StopMovingOrSizing)
    standalone:SetClampedToScreen(true)
    standalone:SetFrameStrata("DIALOG")
    standalone:Hide()
    tinsert(UISpecialFrames, "AllQuestOptions")

    local title = standalone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -5)
    title:SetText("AllQuest")

    BuildScrolling(standalone, 8, -28, -28, 8)
end

local function CreatePanel()
    panel = CreateFrame("Frame")
    panel.name = "AllQuest"
    panel.OnCommit, panel.OnDefault, panel.OnRefresh = function() end, function() end, function() end

    BuildScrolling(panel, 4, -4, -26, 4)

    -- the game's page and the standalone window are never both up
    panel:SetScript("OnShow", function()
        if standalone then standalone:Hide() end
        AQ.RefreshOptions()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "AllQuest")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function AQ.RefreshOptions()
    for _, B in ipairs(builders) do B:Refresh() end
end

local function GameOptionsOpen()
    return SettingsPanel and SettingsPanel:IsShown()
end

-- Show the AllQuest page inside the game's options window.
function AQ.OpenGameOptions()
    if standalone then standalone:Hide() end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

-- The minimap button, the map button and /allquest all come here.
function AQ.ToggleOptions()
    if GameOptionsOpen() then
        if not (panel and panel:IsShown()) then AQ.OpenGameOptions() end
        return
    end
    if not standalone then CreateStandalone() end
    if standalone:IsShown() then
        standalone:Hide()
    else
        AQ.RefreshOptions()
        standalone:Show()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    CreatePanel()
    AQ.RefreshOptions()
end)
