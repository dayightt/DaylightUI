local stub = require("stub")

-- Proc Alerts in the public API (1.16): the list, a proc's state, its events
-- and watcher, a test flare, and a plugin's own alert.

local OVERPOWER, REVENGE = 7384, 6572

local function load()
    stub.Load({ procs = true, before = function()
        stub.SpellReads()
        stub.SetUnits({ player = { name = "Me", class = "WARRIOR", isPlayer = true },
                        target = { name = "Mob", reaction = 2, health = 100, maxHealth = 100 } })
        stub.knownSpells[OVERPOWER] = true
        stub.knownSpells[REVENGE] = true
    end })
    DaylightUI.RegisterPlugin("ProcPlugin", { title = "Proc Plugin", needs = { 1, 16 } })
    return stub.procs, DaylightUI.API, DaylightUI.API.For("ProcPlugin")
end

local function step(dt)
    if dt then stub.Advance(dt) end
    stub.RunTimers()
    stub.RunTickers()
    stub.RunTimers()
end

local function usable(id, yes) stub.spellUsable[id] = { yes, false } end
local function cast(id) stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id) end

T.test("api procs: the version says 1.16 and the calls are there", function()
    local _, API, me = load()
    T.truthy(API.minor >= 16, "minor " .. tostring(API.minor))
    for _, name in ipairs({ "ProcAlerts", "ProcState", "TestProcAlert" }) do
        T.eq(type(API[name]), "function", "API." .. name)
    end
    for _, name in ipairs({ "WatchProc", "AddProcAlert", "ShowProcAlert", "HideProcAlert" }) do
        T.eq(type(me[name]), "function", "me." .. name)
    end
end)

T.test("api procs: the list holds this class's procs with who draws them", function()
    local _, API = load()
    local list = API.ProcAlerts()
    T.truthy(type(list) == "table" and #list > 0)
    local by = {}
    for _, p in ipairs(list) do by[p.key] = p end
    T.truthy(by.overpower, "a warrior's own")
    T.isnil(by.clearcasting, "never another class's")
    T.eq(by.overpower.spellID, OVERPOWER)
    T.eq(by.overpower.design, "talons")
    T.eq(by.overpower.enabled, true)
    T.eq(by.overpower.drawnBy, "daylight")
    T.eq(type(by.overpower.name), "string")
    T.eq(by.edward.drawnBy, "game", "a buff the client shows")
    T.eq(by.edward.enabled, false, "off until ticked")
    list[1].key = "changed"
    T.truthy(API.ProcAlerts()[1].key ~= "changed", "a fresh table each call")
end)

T.test("api procs: shown, renewed and hidden reach listeners and the watcher in a fight", function()
    local _, API, me = load()
    local log, states = {}, {}
    me.On("ProcShown", function(key, stacks) log[#log + 1] = "shown:" .. key end)
    me.On("ProcHidden", function(key) log[#log + 1] = "hidden:" .. key end)
    local h = me.WatchProc("overpower", {
        shown = function(key) log[#log + 1] = "w-shown:" .. key end,
        hidden = function(key) log[#log + 1] = "w-hidden:" .. key end,
        changed = function(state) states[#states + 1] = state or false end,
    })
    T.truthy(h, "a handle")
    T.eq(#states, 1, "changed runs once at once")
    T.eq(states[1], false, "nothing up yet: nil")
    -- Revenge comes up at the same moment: the watcher hears only Overpower.
    stub.EnterCombat()
    usable(OVERPOWER, true)
    usable(REVENGE, true)
    stub.FireEvent("SPELL_UPDATE_USABLE")
    step()
    T.truthy(API.ProcState("overpower"), "up")
    local s = API.ProcState("overpower")
    T.eq(s.key, "overpower")
    T.truthy(type(s.left) == "number" and s.left > 0 and s.left <= 5, "time left " .. tostring(s.left))
    T.eq(s.dur, 5)
    T.eq(s.test, false)
    local shown = 0
    for _, e in ipairs(log) do if e == "shown:overpower" or e == "shown:revenge" then shown = shown + 1 end end
    T.eq(shown, 2, "both procs heard")
    local wshown = 0
    for _, e in ipairs(log) do if e == "w-shown:overpower" then wshown = wshown + 1 end
        T.truthy(e ~= "w-shown:revenge", "the watcher hears only its own") end
    T.eq(wshown, 1)
    T.truthy(states[#states] and states[#states].key == "overpower", "changed gets the state")
    -- A repaint while up (the accent changed) is no new proc.
    local before = #log
    DaylightUI:Set("Procs", "alpha", 0.8)
    stub.procs.Alerts.Set("overpower", "design", "wings")
    step()
    T.eq(#log, before, "no shown or hidden on a setting change")
    cast(OVERPOWER)
    step()
    T.isnil(API.ProcState("overpower"), "gone once cast")
    local hid = false
    for _, e in ipairs(log) do if e == "w-hidden:overpower" then hid = true end end
    T.truthy(hid, "the watcher heard it go")
    T.eq(states[#states], false, "changed with nil when gone")
    API.Off(h)
    local n = #log
    usable(OVERPOWER, true)
    step(6)
    local after = 0
    for i = n + 1, #log do if log[i]:find("^w%-") then after = after + 1 end end
    T.eq(after, 0, "Off stops the watcher")
end)

T.test("api procs: a test flare is no proc to listeners", function()
    local ns, API, me = load()
    local heard = 0
    me.On("ProcShown", function() heard = heard + 1 end)
    me.On("ProcHidden", function() heard = heard + 1 end)
    T.eq(API.TestProcAlert("overpower", 2), true)
    T.truthy(ns.Flares.Shown("overpower"))
    T.eq(API.ProcState("overpower").test, true)
    step(2.1)
    T.falsy(ns.Flares.Shown("overpower"), "gone after its seconds")
    T.eq(heard, 0)
    T.eq(API.TestProcAlert("nope"), false, "an unknown key")
end)

T.test("api procs: a plugin lights an alert of its own, kept off Daylight UI's list", function()
    local ns, API, me = load()
    T.eq(me.AddProcAlert("bloodlust", { name = "Bloodlust", design = "sun", anim = "pulse", dur = 40 }), true)
    T.eq(me.AddProcAlert("bloodlust", { name = "Bloodlust", design = "sun", anim = "pulse" }), true, "again: a new look")
    T.eq(me.AddProcAlert("bad", { design = "nope" }), false, "an unknown design")
    T.eq(me.AddProcAlert("bad2", { anim = "spin" }), false, "an unknown animation")
    T.eq(me.AddProcAlert("strikes", { name = "Strikes", anim = "strike" }), true, "Strike is an animation too")
    T.eq(me.AddProcAlert("plain", { name = "Plain" }), true)
    T.eq(ns.Alerts.Get("ProcPlugin:plain", "anim"), "pulse", "no animation given: still Pulse")
    local heard
    me.On("ProcShown", function(key) heard = key end)
    stub.EnterCombat()
    T.eq(me.ShowProcAlert("bloodlust", { left = 30, dur = 40, stacks = 1 }), true)
    T.eq(heard, "ProcPlugin:bloodlust", "heard under the plugin's name")
    local s = API.ProcState("ProcPlugin:bloodlust")
    T.truthy(s and s.dur == 40)
    T.eq(me.ShowProcAlert("nope"), false, "never added")
    for _, p in ipairs(API.ProcAlerts()) do T.truthy(p.key ~= "ProcPlugin:bloodlust", "not on the class list") end
    -- The engine's refresh leaves it alone.
    stub.FireEvent("SPELL_UPDATE_USABLE")
    step(1)
    T.truthy(ns.Flares.Shown("ProcPlugin:bloodlust"), "the engine never hides a plugin's")
    T.eq(me.HideProcAlert("bloodlust"), true)
    step(1)
    T.falsy(ns.Flares.Shown("ProcPlugin:bloodlust"))
    -- Proc Alerts switched off: nothing shows.
    DaylightUI:Set("Procs", "enabled", false)
    step()
    T.eq(me.ShowProcAlert("bloodlust"), false)
end)

T.test("api procs: every call is quiet with the module off", function()
    stub.Load({})
    local API = DaylightUI.API
    DaylightUI.RegisterPlugin("ProcPlugin", { title = "Proc Plugin", needs = { 1, 1 } })
    local me = API.For("ProcPlugin")
    T.isnil(API.ProcAlerts())
    T.isnil(API.ProcState("overpower"))
    T.eq(API.TestProcAlert("overpower"), false)
    T.eq(me.AddProcAlert("x", {}), false)
    T.eq(me.ShowProcAlert("x"), false)
    T.isnil(me.WatchProc("overpower", { shown = function() end }))
end)
