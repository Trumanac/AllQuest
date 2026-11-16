local AddOn, AQ = ...

-- Other addons. Questie draws its own "!" markers for quests you can pick up, which would sit on top of
-- AllQuest's. While "Hide Questie's available-quest markers" is on (default), AllQuest switches those off in
-- Questie's settings and puts them back when the option is turned off. (If AllQuest is removed while the option is
-- still on, Questie's own options page, Icons tab, has to switch them back on.) Everything else Questie does
-- (objectives, turn-ins, tracker) is left alone.
local Compat = {}
AQ.Compat = Compat

local function QuestieProfile()
    local Q = _G.Questie
    local db = Q and Q.db
    local p = db and db.profile
    if not p or p.enableAvailable == nil then return end
    local key = (db.GetCurrentProfile and db:GetCurrentProfile()) or "default"
    return Q, p, key
end

function Compat.QuestieLoaded()
    return QuestieProfile() ~= nil
end

function Compat.Apply()
    local Q, p, key = QuestieProfile()
    if not p or not AQ.shared then return end
    AQ.shared.questieSaved = AQ.shared.questieSaved or {}
    local saved = AQ.shared.questieSaved
    local want = AQ.db and AQ.db.enabled and AQ.db.hideQuestieAvailable
    local function Redraw(show)
        -- Questie keeps its modules private; QuestieLoader is the way in (QuestieQuest is a global only in debug mode)
        local loader = _G.QuestieLoader
        local qq = _G.QuestieQuest or (loader and loader.ImportModule and loader:ImportModule("QuestieQuest"))
        if qq and qq.ToggleAvailableQuests then pcall(qq.ToggleAvailableQuests, show) end
    end
    if want then
        if not saved[key] then saved[key] = { a = p.enableAvailable, i = p.enableAvailableItems, s = p.showAvailableQuests } end
        if p.enableAvailable or p.enableAvailableItems or p.showAvailableQuests then
            -- showAvailableQuests is the master switch (also covers repeatable, event, dungeon, raid and PvP quests)
            p.enableAvailable, p.enableAvailableItems, p.showAvailableQuests = false, false, false
            Redraw(false)
        end
    elseif saved[key] then
        local s = saved[key]
        saved[key] = nil
        p.enableAvailable, p.enableAvailableItems = s.a, s.i
        if s.s ~= nil then p.showAvailableQuests = s.s end
        Redraw(s.a ~= false)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    -- Questie sets itself up a little after login
    pcall(Compat.Apply)            -- before Questie draws its first markers, when it is already loaded
    C_Timer.After(8, Compat.Apply)
    C_Timer.After(25, Compat.Apply)
end)
