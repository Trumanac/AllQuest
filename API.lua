local AddOn, AQ = ...

-- A small public API so other addons (quest guides, arrow addons ...) can ask what AllQuest shows, without reading
-- its saved data. Everything here is read-only and follows the player's own filters and hidden lists.
--
--   AllQuestAPI.version                       number, raised when something changes in a way that could break callers
--   AllQuestAPI.IsReady()                     true once the quest database is loaded
--   AllQuestAPI.GetQuests(uiMapId)            list of quests available on a map (see Describe for the fields)
--   AllQuestAPI.GetNearest([limit], [maxYards])  the closest available quests to the player, nearest first
--   AllQuestAPI.IsHidden(questId)             true when the player hid the quest or its chain
--   AllQuestAPI:RegisterCallback("AllQuest_Refreshed", fn)   called after the markers were redrawn
local API = { version = 1 }
AQ.API = API
_G.AllQuestAPI = API

local callbackHandler = LibStub and LibStub("CallbackHandler-1.0", true)
if callbackHandler then API.callbacks = callbackHandler:New(API) end

-- { questId, name, level, trivial, locked, repeatable, groupSize, giverKind ("n" npc, "o" object, "i" item, "d" dungeon),
--   giverId, giverName, mapId, x, y (0-1 on that map), distance (yards, when known) }
local function Describe(pin, q)
    local entry = pin.entry
    return {
        questId = q.id, name = AQ.Data.QuestName(q.id), level = q.level, trivial = q.trivial and true or false,
        locked = q.locked and true or false, repeatable = q.rep and true or false, groupSize = q.grp,
        giverKind = entry.kind, giverId = entry.id, giverName = (AQ.Data.StarterInfo(entry)),
        mapId = entry.map, x = entry.x, y = entry.y,
    }
end

function API.IsReady()
    return AQ.Data and AQ.Data.ready and true or false
end

function API.GetQuests(uiMapId)
    local list = {}
    if not API.IsReady() or not uiMapId then return list end
    for _, pin in ipairs(AQ.PinsFor(uiMapId)) do
        for _, q in ipairs(pin.quests) do list[#list + 1] = Describe(pin, q) end
    end
    return list
end

function API.GetNearest(limit, maxYards)
    local list = {}
    if not API.IsReady() then return list end
    local home = AQ.PlayerZone()
    local continent = home and AQ.ContinentOf(home)
    if not continent then return list end
    for _, uiMapId in ipairs(AQ.Data.MapIds()) do
        if AQ.ContinentOf(uiMapId) == continent then
            for _, pin in ipairs(AQ.PinsFor(uiMapId)) do
                local distance = AQ.Minimap.Distance(pin.entry)
                if distance and (not maxYards or distance <= maxYards) then
                    for _, q in ipairs(pin.quests) do
                        local item = Describe(pin, q)
                        item.distance = distance
                        list[#list + 1] = item
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.questId < b.questId
    end)
    if limit then
        for i = #list, limit + 1, -1 do list[i] = nil end
    end
    return list
end

function API.IsHidden(questId)
    local ignored = AQ.shared and AQ.shared.ignored
    if not ignored then return false end
    return (ignored.quests[questId] or AQ.Data.IsChainHidden(questId)) and true or false
end
