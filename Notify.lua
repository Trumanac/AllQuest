local AddOn, AQ = ...

-- Tells the player when a level-up or a turned-in quest has made new quests available.
-- It keeps the set of quests that were available the last time anything was checked ("base"); a check after a
-- level-up or a turn-in compares the new set with it. Any other change (settings, holidays ...) only moves the
-- base along, so those never count as "new".
local Notify = {}
AQ.Notify = Notify

local base          -- quest id -> true

-- Every quest available now in every zone: set (id -> true) and the details of the first spot found.
local function Available()
    local set, info = {}, {}
    if not AQ.Data.ready then return set, info end
    for _, map in ipairs(AQ.Data.MapIds()) do
        for _, pin in ipairs(AQ.PinsFor(map)) do
            for _, q in ipairs(pin.quests) do
                if not set[q.id] then
                    set[q.id] = true
                    info[q.id] = { level = q.level, map = map }
                end
            end
        end
    end
    return set, info
end

function Notify.Baseline()
    if AQ.Data.ready then base = (Available()) end
end

local MAX_LISTED = 4

function Notify.Check()
    if not AQ.Data.ready then return end
    local now, info = Available()
    local old = base
    base = now
    if not old or not AQ.db.notifyNewQuests then return end

    local fresh = {}
    for id in pairs(now) do
        if not old[id] then fresh[#fresh + 1] = id end
    end
    if #fresh == 0 then return end
    table.sort(fresh, function(a, b)
        if info[a].level ~= info[b].level then return info[a].level < info[b].level end
        return a < b
    end)

    local L = AQ.L
    local text
    if #fresh <= MAX_LISTED then
        -- a few: name them
        local parts = {}
        for _, id in ipairs(fresh) do
            local zone = C_Map.GetMapInfo(info[id].map)
            parts[#parts + 1] = ("[%d] %s%s"):format(info[id].level, AQ.Data.QuestName(id), zone and zone.name and (" (" .. zone.name .. ")") or "")
        end
        text = (#fresh == 1 and L["1 new quest available"] or (L["%d new quests available"]):format(#fresh)) .. ": " .. table.concat(parts, ", ")
    else
        -- many (a level-up opens a lot across the world): say where most of them are
        local perZone, order = {}, {}
        for _, id in ipairs(fresh) do
            local map = info[id].map
            if not perZone[map] then perZone[map] = 0 order[#order + 1] = map end
            perZone[map] = perZone[map] + 1
        end
        table.sort(order, function(a, b)
            if perZone[a] ~= perZone[b] then return perZone[a] > perZone[b] end
            return a < b
        end)
        local parts = {}
        for i = 1, math.min(#order, 3) do
            local zone = C_Map.GetMapInfo(order[i])
            parts[#parts + 1] = ("%s (%d)"):format(zone and zone.name or "?", perZone[order[i]])
        end
        text = (L["%d new quests available"]):format(#fresh) .. ", " .. L["mostly in"] .. ": " .. table.concat(parts, ", ")
    end
    AQ.Print(text .. "  -  " .. L["/aq list shows them all"])
end
