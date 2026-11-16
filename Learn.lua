local AddOn, AQ = ...

-- Self-extending database. When a quest giver offers a quest the bundled data does not know (a quest added
-- by a later patch, or one that was left out), AllQuest remembers the giver and the quest in the saved learned table
-- and shows it from then on. The giver's position is the player's position while talking to it.
local Learn = {}
AQ.Learn = Learn

-- GUID -> "n" (creature) / "o" (object) and the id.
local function ParseGuid(guid)
    if type(guid) ~= "string" then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if not id then return end
    if kind == "Creature" or kind == "Vehicle" then return "n", id end
    if kind == "GameObject" then return "o", id end
end

local function Remember(unit, questId, title, level, repeatable)
    local db = AQ.db
    if not (db and db.learnQuests and AQ.Data.ready) or not questId or questId <= 0 then return end
    local kind, giverId = ParseGuid(UnitGUID(unit))
    if not kind then return end
    if AQ.Data.IsKnownGiver(kind, giverId, questId) then return end

    local existing = AQ.shared.learned[questId]
    if existing then
        -- keep the first giver seen (a second one would make the marker jump between them); note it was seen again
        existing.t = time()
        if repeatable and not existing.r then existing.r = true AQ.Data.InvalidateMap(existing.m) end
        return
    end

    local mapId = C_Map.GetBestMapForUnit("player")
    local pos = mapId and C_Map.GetPlayerMapPosition(mapId, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end

    AQ.shared.learned[questId] = {
        n = title, l = level or UnitLevel("player"), k = kind, id = giverId, name = UnitName(unit),
        f = UnitFactionGroup("player"), r = repeatable and true or nil,
        h = (AQ.Events and #AQ.Events.ActiveList() > 0) or nil,    -- learned while a holiday was on: may be a holiday quest
        m = mapId, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10, t = time(),
    }
    AQ.Data.InvalidateMap(mapId)
    AQ.RequestRefresh()
    return title or ((AQ.L["Quest %d"]):format(questId))
end

-- One chat line for everything learned from one window (a giver can offer several quests at once).
local function Announce(titles)
    if #titles == 0 then return end
    local L = AQ.L
    if #titles == 1 then
        AQ.Print(L["learned a new quest"] .. ": " .. titles[1])
    else
        AQ.Print((L["learned %d new quests"]):format(#titles) .. ": " .. table.concat(titles, ", ", 1, math.min(#titles, 4))
            .. (#titles > 4 and ", ..." or ""))
    end
end

local function ScanGossip()
    if not (AQ.db and AQ.db.learnQuests) then return end
    if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
    local titles = {}
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        titles[#titles + 1] = Remember("npc", q.questID, q.title, q.questLevel, q.repeatable or (q.frequency and q.frequency > 0))
    end
    Announce(titles)
end

local function ScanDetail()
    local id = GetQuestID and GetQuestID()
    if not id or id == 0 then return end
    local level = C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
    local title = Remember("questnpc", id, GetTitleText and GetTitleText() or nil, level, QuestIsDaily and (QuestIsDaily() or (QuestIsWeekly and QuestIsWeekly())) or nil)
    if title then Announce({ title }) end
end

-- Rewards: the quest dialog shows experience, money and items, so remember them for the quest list's columns.
-- The item links can be missing for a moment while the game loads the items, so try again once.
local function ItemIds(kind, count)
    local ids = {}
    for i = 1, count do
        local link = GetQuestItemLink and GetQuestItemLink(kind, i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if not id then return nil end
        ids[#ids + 1] = id
    end
    return ids
end

local function ScanRewards(questId, retry)
    if not (questId and questId > 0 and GetRewardXP) then return end
    local items = ItemIds("reward", GetNumQuestRewards and GetNumQuestRewards() or 0)
    local choices = ItemIds("choice", GetNumQuestChoices and GetNumQuestChoices() or 0)
    if not (items and choices) then
        -- only while the same quest is still on screen: the dialog is what the reward calls read
        if not retry then
            C_Timer.After(1, function()
                if GetQuestID and GetQuestID() == questId then pcall(ScanRewards, questId, true) end
            end)
        end
        return
    end
    local record = { GetRewardXP() or 0, GetRewardMoney and GetRewardMoney() or 0, #items > 0 and items or nil, #choices > 0 and choices or nil }
    local old = AQ.shared.rewards[questId]
    -- the dialog shows the XP for THIS character (reduced for grey quests, none at max level): keep the highest
    -- amount ever seen, together with the money that went with it
    if old and (old[1] or 0) > record[1] then record[1], record[2] = old[1], old[2] end
    if old and old[1] == record[1] and old[2] == record[2] and #(old[3] or {}) == #items and #(old[4] or {}) == #choices then return end
    AQ.shared.rewards[questId] = record
    if AQ.QuestList and AQ.QuestList.Refresh then AQ.QuestList.Refresh() end
end

local function ScanQuestDialog()
    ScanRewards(GetQuestID and GetQuestID())
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_COMPLETE")
frame:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(function()
        if event == "GOSSIP_SHOW" then
            ScanGossip()
        elseif event == "QUEST_DETAIL" then
            ScanDetail()
            ScanQuestDialog()
        else
            ScanQuestDialog()
        end
    end)
    if not ok then geterrorhandler()(err) end
end)

function Learn.Count()
    local n = 0
    for _ in pairs(AQ.shared.learned) do n = n + 1 end
    return n
end

function Learn.Forget()
    local maps = {}
    for _, l in pairs(AQ.shared.learned) do
        if l.m then maps[l.m] = true end
    end
    AQ.shared.learned = {}
    for m in pairs(maps) do AQ.Data.InvalidateMap(m) end
end

-- Suggested group sizes: the quest log knows them for the quests you hold; remember them for the markers.
function Learn.ScanGroupSizes()
    local changed = false
    local function Note(questId, size)
        if questId and size and size > 1 and AQ.shared.groupSizes[questId] ~= size then
            AQ.shared.groupSizes[questId] = size
            changed = true
        end
    end
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader then Note(info.questID, info.suggestedGroup) end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local _, _, suggestedGroup, isHeader, _, _, _, questId = GetQuestLogTitle(i)
            if not isHeader then Note(questId, suggestedGroup) end
        end
    end
    if changed then AQ.RequestRefresh() end
end

local sizes = CreateFrame("Frame")
sizes:RegisterEvent("QUEST_ACCEPTED")
sizes:RegisterEvent("PLAYER_LOGIN")
sizes:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(5, function() pcall(Learn.ScanGroupSizes) end)
    else
        C_Timer.After(1, function() pcall(Learn.ScanGroupSizes) end)
    end
end)
