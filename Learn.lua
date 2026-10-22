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

local function Remember(unit, questId, title, level)
    local db = AQ.db
    if not (db and db.learnQuests and AQ.Data.ready) or not questId or questId <= 0 then return end
    local kind, giverId = ParseGuid(UnitGUID(unit))
    if not kind then return end
    if AQ.Data.IsKnownGiver(kind, giverId, questId) then return end

    local existing = AQ.shared.learned[questId]
    if existing and existing.k == kind and existing.id == giverId then return end

    local mapId = C_Map.GetBestMapForUnit("player")
    local pos = mapId and C_Map.GetPlayerMapPosition(mapId, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end

    AQ.shared.learned[questId] = {
        n = title, l = level or UnitLevel("player"), k = kind, id = giverId, name = UnitName(unit),
        m = mapId, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10, t = time(),
    }
    AQ.Data.InvalidateMap(mapId)
    AQ.Print(("learned a new quest: %s"):format(title or ("Quest " .. questId)))
    AQ.RequestRefresh()
end

local function ScanGossip()
    if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        Remember("npc", q.questID, q.title, q.questLevel)
    end
end

local function ScanDetail()
    local id = GetQuestID and GetQuestID()
    if not id or id == 0 then return end
    local level = C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(id)
    Remember("questnpc", id, GetTitleText and GetTitleText() or nil, level)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("QUEST_DETAIL")
frame:SetScript("OnEvent", function(_, event)
    local ok, err = pcall(event == "GOSSIP_SHOW" and ScanGossip or ScanDetail)
    if not ok then geterrorhandler()(err) end
end)

function Learn.Count()
    local n = 0
    for _ in pairs(AQ.shared.learned) do n = n + 1 end
    return n
end

function Learn.Forget()
    local maps = {}
    for _, l in pairs(AQ.shared.learned) do maps[l.m] = true end
    AQ.shared.learned = {}
    for m in pairs(maps) do AQ.Data.InvalidateMap(m) end
end

-- Suggested group sizes: the quest log knows them for the quests you hold; remember them for the markers.
function Learn.ScanGroupSizes()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return end
    local changed = false
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.suggestedGroup and info.suggestedGroup > 1
            and AQ.shared.groupSizes[info.questID] ~= info.suggestedGroup then
            AQ.shared.groupSizes[info.questID] = info.suggestedGroup
            changed = true
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
