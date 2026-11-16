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
local dmfAt, dmfValue = 0, false
local function DarkmoonActive()
    if GetTime and GetTime() - dmfAt < 30 then return dmfValue end   -- called once per Faire quest: reuse the answer
    local r = false
    local n = RealmNow()
    local nowT = time({ year = n.year, month = n.month, day = n.day, hour = n.hour, min = n.min })
    for back = 0, 1 do
        local y, m = n.year, n.month - back
        if m < 1 then m = 12 y = y - 1 end
        for d = 3, 9 do
            if date("*t", time({ year = y, month = m, day = d, hour = 12 })).wday == 2 then   -- 2 = Monday
                local start = time({ year = y, month = m, day = d, hour = 4 })
                if nowT >= start and nowT < start + 7 * 86400 then r = true end
                break
            end
        end
    end
    dmfAt, dmfValue = GetTime and GetTime() or 0, r
    return r
end

-- How long a holiday runs, in days, from its bundled date window plus a few days of slack (21 when unknown).
function Events.RunDays(name)
    local w = AQ.DB.events and AQ.DB.events[name]
    if not w then return 21 end
    local sd, sm = (w.sd or ""):match("^(%d+)/(%d+)$")
    local ed, em = (w.ed or ""):match("^(%d+)/(%d+)$")
    if not sd then return 21 end
    local y = 2001   -- any non-leap year
    local a = time({ year = y, month = tonumber(sm), day = tonumber(sd), hour = 12 })
    local b = time({ year = y, month = tonumber(em), day = tonumber(ed), hour = 12 })
    if b < a then b = time({ year = y + 1, month = tonumber(em), day = tonumber(ed), hour = 12 }) end
    return math.max(7, math.floor((b - a) / 86400) + 1) + 3
end

-- Is realm "now" inside the holiday's window? Dates are "D/M"; a window may wrap the new year. A window of a single
-- day (the data gives one for Noblegarden, which really runs about a week) is widened to a week.
local function WithinDates(d)
    local sd, sm = (d.sd or ""):match("^(%d+)/(%d+)$")
    local ed, em = (d.ed or ""):match("^(%d+)/(%d+)$")
    if not (sd and ed) then return false end
    local n = RealmNow()
    local nowT = time({ year = n.year, month = n.month, day = n.day, hour = n.hour, min = n.min })
    for y = n.year - 1, n.year do
        local start = time({ year = y, month = tonumber(sm), day = tonumber(sd), hour = d.sh or 0, min = d.sm or 0 })
        local ey = (tonumber(em) < tonumber(sm) or (em == sm and tonumber(ed) < tonumber(sd))) and y + 1 or y
        local finish = time({ year = ey, month = tonumber(em), day = tonumber(ed), hour = d.eh or 23, min = d.em or 59 })
        if finish - start < 86400 then finish = start + 7 * 86400 end
        if nowT >= start and nowT <= finish then return true end
    end
    return false
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
