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
            any = true
            if C_Calendar.GetHolidayInfo then
                local info = C_Calendar.GetHolidayInfo(offset, now.monthDay, i)
                if info and info.name then set[Normalize(info.name)] = true end
            end
            if C_Calendar.GetDayEvent then
                local event = C_Calendar.GetDayEvent(offset, now.monthDay, i)
                if event and event.title then set[Normalize(event.title)] = true end
            end
        end
    end)
    today = set
    calendarUsable = ok and any
    return calendarUsable
end

-- Port of the usual "is today inside start..end" test; dates are "D/M", ranges may wrap the new year.
local function WithinDates(d)
    local sd, sm = (d.sd or ""):match("^(%d+)/(%d+)$")
    local ed, em = (d.ed or ""):match("^(%d+)/(%d+)$")
    if not (sd and ed) then return false end
    local t = date("*t")
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
    table.sort(list)
    return list
end

function Events.Request()
    pcall(function()
        if C_Calendar and C_Calendar.OpenCalendar then C_Calendar.OpenCalendar() end
        if C_Calendar and C_Calendar.SetMonth then C_Calendar.SetMonth(0) end
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
