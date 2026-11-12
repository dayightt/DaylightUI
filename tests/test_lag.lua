local stub = require("stub")

-- Measures how much addon Lua runs on frames where nothing happens. Every module
-- is on and idle after login, then 2 s at 60 fps, solo and in a fight with a target.
-- Fails when:
--   * a new frame runs an OnUpdate while idle. Hide it when it has nothing to do,
--     or add it to DRIVERS with the reason.
--   * the Lua work per idle frame grows past BUDGET (counted in Lua
--     instructions, so the same on every PC).
--   * a ticker runs faster than the fade's 0.1 s.
-- After a real speed-up, lower BUDGET to the printed number plus some room.

-- Files allowed an idle OnUpdate, how many, and why it can't be an event.
local DRIVERS = {
    ["Windows/Follow.lua"] = { 1, "the game's windows parked under ours get no OnShow/OnHide: one IsShown each a frame" },
    ["DaylightUI_UnitFrames/UnitFrames.lua"] = { 3, "player power polls every frame (settled: power is the poll); the shared power glide; a frame's throttled poll (target of target or focus target: no events for those units, only while shown)" },
    ["DaylightUI_UnitFrames/Units.lua"] = { 1, "range: throttled to UF.RANGE_INTERVAL, the game sends no range event" },
    ["DaylightUI_ActionBars/Buttons.lua"] = { 1, "range on the buttons, only with a target, each Buttons.RANGE_EVERY" },
    ["DaylightUI_ActionBars/Skin.lua"] = { 1, "button range and usable tint, throttled in Skin.Tick" },
    ["DaylightUI_Buffs/Bar.lua"] = { 2, "hover (throttled, the client's aura buttons take no OnEnter of ours); weapon enchant countdown (throttled)" },
    ["DaylightUI_Tooltip/Tooltip.lua"] = { 1, "keeps the tooltip on the cursor while it fades (once a frame, skipped when the game's own update ran)" },
    ["DaylightUI_Chat/Chat.lua"] = { 1, "chat's line fade steps, a full look each Chat.WATCH" },
    ["DaylightUI_InfoPanel/Panel.lua"] = { 1, "hover over the panel's parts, each Panel.HOVER_EVERY" },
    ["Options/Widgets.lua"] = { 1, "a shown list's scroll bar: a look each poll (hover, a new range)" },
}
-- Lua instructions per idle frame, about 20% over the last measure (solo 1550, fight 3101).
local BUDGET = { solo = 1900, fight = 3700 }
local FASTEST_TICKER = 0.1

local ALL = { module = true, actionbars = true, buffs = true, skins = true, bags = true, nameplates = true,
              tooltip = true, qol = true, chat = true, infopanel = true, quests = true }

-- Frames whose OnUpdate runs in game now: shown, all parents shown.
local function drivers()
    local out = {}
    local f = EnumerateFrames()
    while f do
        local fn = rawget(f, "__scripts") and f.__scripts.OnUpdate
        if fn and f:IsVisible() then
            local info = debug.getinfo(fn, "S")
            out[#out + 1] = { f = f, fn = fn, src = info.short_src:gsub("\\", "/"):gsub("^%./", ""), line = info.linedefined }
        end
        f = EnumerateFrames(f)
    end
    return out
end

-- Runs n frames; returns the Lua instructions per frame our drivers ran.
local function frames(n, dt, count)
    local list = drivers()
    local ran = 0
    if count then debug.sethook(function() ran = ran + 1 end, "", 10) end
    for _ = 1, n do
        stub.Advance(dt)
        for _, d in ipairs(list) do
            if d.f.__scripts.OnUpdate == d.fn then d.fn(d.f, dt) end
        end
    end
    if count then debug.sethook() end
    return ran * 10 / n
end

local function settle()
    -- The client's unit watch always runs. A frame whose unit doesn't exist
    -- (no focus, no target of target) is hidden and its poll stops.
    stub.UnitWatch()
    for _ = 1, 5 do stub.RunTimers(); stub.RunTickers() end
    frames(180, 1 / 60)   -- 3 s, long enough for every fade, glide and login move to end
    stub.RunTimers()
end

local function check(scene)
    local by, problems = {}, {}
    for _, d in ipairs(drivers()) do
        by[d.src] = by[d.src] or {}
        table.insert(by[d.src], d.line)
    end
    for src, lines in pairs(by) do
        local ok = DRIVERS[src]
        if not ok or #lines > ok[1] then
            table.sort(lines)
            problems[#problems + 1] = string.format("%s: %d idle OnUpdate (line %s), allowed %d",
                src, #lines, table.concat(lines, ", "), ok and ok[1] or 0)
        end
    end
    table.sort(problems)
    T.eq(#problems, 0, scene .. ": runs every frame while nothing happens (hide its frame when idle, or add it"
        .. " to DRIVERS with why):\n  " .. table.concat(problems, "\n  "))
    -- Interpreter only, since compiled code skips the count hook. Keeps the number stable.
    if jit then jit.off(); jit.flush() end
    local work = frames(120, 1 / 60, true)
    if jit then jit.on() end
    print(string.format("  (%s: %d Lua instructions per idle frame, budget %d)", scene, work, BUDGET[scene]))
    T.truthy(work <= BUDGET[scene], string.format("%s: %d Lua instructions per idle frame, budget %d: something"
        .. " new runs every frame (a lower number from a real speed-up: lower BUDGET)", scene, work, BUDGET[scene]))
end

T.test("idle, solo: no new per-frame work, within the budget", function()
    stub.Load(ALL)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    settle()
    check("solo")
end)

T.test("idle in a fight with a target: no new per-frame work, within the budget", function()
    stub.Load(ALL)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    settle()
    stub.SetUnits({ target = { name = "Defias Thug", health = 800, maxHealth = 1000, reaction = 2, level = 20 } })
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.EnterCombat()
    settle()
    check("fight")
end)

T.test("idle in a fight with meter windows out: no new per-frame work, within the budget", function()
    local DUI = stub.Load(ALL)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    DUI:Set("InfoPanel", "meter.enabled", true)
    local W = stub.infopanel.Windows
    W.Add("healing")
    W.Add("threat")
    W.Add("summary")
    settle()
    stub.SetGroup(true)
    stub.SetUnits({ target = { name = "Defias Thug", health = 800, maxHealth = 1000, reaction = 2, level = 20 } })
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.EnterCombat()
    settle()
    check("fight")
    stub.SetGroup(false)
end)

T.test("no ticker runs faster than the fade's 0.1 s", function()
    stub.Load(ALL)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    settle()
    local fast = {}
    for _, t in ipairs(stub.tickers) do
        if not t.cancelled and type(t.interval) == "number" and t.interval < FASTEST_TICKER then
            local info = debug.getinfo(t.fn, "S")
            fast[#fast + 1] = info.short_src .. ":" .. info.linedefined .. " every " .. t.interval .. " s"
        end
    end
    T.eq(#fast, 0, "tickers faster than " .. FASTEST_TICKER .. " s:\n  " .. table.concat(fast, "\n  "))
    T.truthy(#stub.tickers > 0, "no tickers at all: the check went hollow")
end)
