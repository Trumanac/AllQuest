local AddOn, AQ = ...

-- Optionally hides Blizzard's objective tracker (the quest list on the right of the screen).
-- Hide() it, re-hide whenever Blizzard shows it again,
-- and wait for combat to end when the frame is protected.
local Tracker = {}
AQ.Tracker = Tracker

local hooked = false
local waiter = CreateFrame("Frame")

local function Wanted()
    return AQ.db and AQ.db.hideTracker
end

function Tracker.Apply()
    local frame = ObjectiveTrackerFrame
    if not frame then return end
    local wanted = Wanted()

    if InCombatLockdown() and (not wanted or frame:IsProtected()) then
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")   -- retry with the latest setting after combat
        return
    end
    waiter:UnregisterEvent("PLAYER_REGEN_ENABLED")

    if wanted then
        if not hooked then
            frame:HookScript("OnShow", function()
                if Wanted() then Tracker.Apply() end
            end)
            hooked = true
        end
        frame:Hide()
    elseif Tracker.hidden then
        -- let Blizzard decide again whether it should be visible
        if frame.Update then frame:Update() else frame:Show() end
    end
    Tracker.hidden = wanted and true or false
end

waiter:SetScript("OnEvent", function() Tracker.Apply() end)
