local AddOn, AQ = ...

-- Holiday quests: a quest tied to a holiday is shown only while that holiday is on.
-- The game's own calendar is the main source (its holiday titles for today). When the calendar cannot be
-- read, the bundled date windows (AQ.DB.events) are used instead.
local Events = {}
AQ.Events = Events

local today = {}            -- lowercase holiday titles on the calendar today
local calendarUsable = false

local function Normalize(text)
    return (tostring(text):lower():gsub("[%'%’`]", ""))
end

-- Read today's calendar entries. Returns true when the calendar answered.
function Events.Refresh()
    local set, any = {}, false
    local ok = pcall(function()
        local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
        if not (now and C_Calendar and C_Calendar.GetNumDayEvents) then return end
        -- the calendar counts months from the one it is showing, which is not today's if the player browsed away
        local offset = 0
        local viewed = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(0)
        if viewed and viewed.month and viewed.year then
            offset = (now.year - viewed.year) * 12 + (now.month - viewed.month)
        end
        local count = C_Calendar.GetNumDayEvents(offset, now.monthDay) or 0
        for i = 1, count do
            if C_Calendar.GetHolidayInfo then
                local info = C_Calendar.GetHolidayInfo(offset, now.monthDay, i)
                if info and info.name then set[Normalize(info.name)] = true any = true end
            end
            if C_Calendar.GetDayEvent then
                local event = C_Calendar.GetDayEvent(offset, now.monthDay, i)
                if event and event.title then
                    set[Normalize(event.title)] = true
                    -- player and guild events do not prove the holiday list has loaded
                    if event.calendarType == "HOLIDAY" then any = true end
                end
            end
        end
    end)
    today = set
    -- holiday titles are matched against bundled English names, so on other languages the calendar cannot decide
    local english = (GetLocale and GetLocale() or "enUS"):find("^en") ~= nil
    calendarUsable = ok and any and english   -- an empty answer may just mean the calendar has not loaded yet: then the date windows decide
    return calendarUsable
end

-- The calendar's "now" in realm time (the holiday schedules are realm time), as year/month/day/hour/min.
local function RealmNow()
    local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if t and t.year and t.monthDay then
        return { year = t.year, month = t.month, day = t.monthDay, hour = t.hour or 0, min = t.minute or 0 }
    end
    local d = date("*t")
    return { year = d.year, month = d.month, day = d.day, hour = d.hour, min = d.min }
end

-- Darkmoon Faire, WoW Forever: opens on a Monday at 4:00 realm time and stays 7 days. The Monday is the first
-- one on or after the 3rd of the month (matches the announced 2026-11-09, 12-07, 2027-01-04, 02-08, 03-08, 04-05,
-- 05-03, 06-07). Used when the calendar does not list the Faire.
local DARKMOON = "Darkmoon Faire"
local function DarkmoonActive()
    local n = RealmNow()
    local nowT = time({ year = n.year, month = n.month, day = n.day, hour = n.hour, min = n.min })
    for back = 0, 1 do
        local y, m = n.year, n.month - back
        if m < 1 then m = 12 y = y - 1 end
        for d = 3, 9 do
            if date("*t", time({ year = y, month = m, day = d, hour = 12 })).wday == 2 then   -- 2 = Monday
                local start = time({ year = y, month = m, day = d, hour = 4 })
                if nowT >= start and nowT < start + 7 * 86400 then return true end
                break
            end
        end
    end
    return false
end

-- Port of the usual "is today inside start..end" test; dates are "D/M", ranges may wrap the new year.
local function WithinDates(d)
    local sd, sm = (d.sd or ""):match("^(%d+)/(%d+)$")
    local ed, em = (d.ed or ""):match("^(%d+)/(%d+)$")
    if not (sd and ed) then return false end
    local t = RealmNow()
    local current = t.month * 1000000 + t.day * 10000 + t.hour * 100 + t.min
    local start = tonumber(sm) * 1000000 + tonumber(sd) * 10000 + (d.sh or 0) * 100 + (d.sm or 0)
    local finish = tonumber(em) * 1000000 + tonumber(ed) * 10000 + (d.eh or 23) * 100 + (d.em or 59)
    if start <= finish then return current >= start and current <= finish end
    return current >= start or current <= finish
end

function Events.IsActive(name)
    local wanted = Normalize(name)
    if wanted == "" then return false end
    for title in pairs(today) do
        if title:find(wanted, 1, true) then return true end
    end
    if name == DARKMOON then return DarkmoonActive() end
    if calendarUsable then return false end
    local window = AQ.DB.events and AQ.DB.events[name]
    return window ~= nil and WithinDates(window)
end

-- Names of the holidays that are on now (for /aq events).
function Events.ActiveList()
    local list = {}
    for name in pairs(AQ.DB.events or {}) do
        if Events.IsActive(name) then list[#list + 1] = name end
    end
    if not (AQ.DB.events and AQ.DB.events[DARKMOON]) and Events.IsActive(DARKMOON) then list[#list + 1] = DARKMOON end
    table.sort(list)
    return list
end

function Events.Request()
    pcall(function()
        if C_Calendar and C_Calendar.OpenCalendar then C_Calendar.OpenCalendar() end
    end)
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "CALENDAR_UPDATE_EVENT_LIST")
frame:SetScript("OnEvent", function()
    Events.Refresh()
    AQ.RequestRefresh()
end)

-- Ask for the calendar after login, then re-read it every few minutes (the date rolls over at midnight).
function Events.Start()
    Events.Request()
    C_Timer.After(5, function() Events.Refresh() AQ.RequestRefresh() end)
    C_Timer.NewTicker(600, function() Events.Refresh() AQ.RequestRefresh() end)
end
