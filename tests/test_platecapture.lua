local stub = require("stub")

-- The core watcher is tested independently of Manager's structural predicate;
-- test_plate_capture_state exercises that predicate against real module frames.
local function setup(opts)
    opts = opts or {}
    local timers, plates, states, lookups = {}, {}, {}, 0
    stub.Load({ before = function()
        if opts.saved then _G.DaylightUIDB = opts.saved end
        C_Timer.After = function(delay, fn) timers[#timers + 1] = { due = GetTime() + delay, fn = fn } end
        _G.C_NamePlate = { GetNamePlateForUnit = function(unit) lookups = lookups + 1; return plates[unit] end }
    end })
    local DUI = DaylightUI
    local s = { DUI = DUI, P = DUI.PlateCapture, timers = timers, plates = plates, states = states,
        prompts = {}, copies = {}, tickers = {}, mutationCalls = 0 }
    s.lookups = function() return lookups end
    s.store = function() return DUI.DB.Root().plateCapture end
    s.records = function() return s.store().records end
    function s.advance(seconds)
        stub.Advance(seconds)
        for round = 1, 100 do
            local pending, ran = {}, false
            for i = #timers, 1, -1 do
                if timers[i].due <= GetTime() then table.insert(pending, 1, table.remove(timers, i)); ran = true end
            end
            for _, timer in ipairs(pending) do timer.fn() end
            if not ran then return end
            assert(round < 100, "test timer storm")
        end
    end
    s.advance(6)
    DUI.VERSION = "1.9.3"
    _G.GetBuildInfo = function() return "game version", "12345", "private date" end
    _G.GetCVar = function(key)
        if key == "nameplateShowAll" or key == "nameplateShowEnemies"
            or key == "nameplateShowFriendlyPlayers" or key == "nameplateShowFriendlyNpcs" then return "1" end
        return "PRIVATE_CVAR"
    end
    DUI.Profiles.ShowText = function(title, hint, text) s.copies[#s.copies + 1] = { title = title, hint = hint, text = text } end
    DUI.Widgets.Ask = function(spec) s.prompts[#s.prompts + 1] = spec end
    DUI.Widgets.Asking = function() return s.otherPrompt end
    local ticker = C_Timer.NewTicker
    C_Timer.NewTicker = function(interval, fn)
        local t = ticker(interval, fn)
        s.tickers[#s.tickers + 1] = t
        return t
    end
    if not opts.moduleOff then
        s.manager = { CaptureState = function(unit) return states[unit] end }
        DUI:RegisterModule("Nameplates", { ns = { Manager = s.manager }, defaults = {} })
    end
    function s.add(i, reason)
        local unit = "nameplate" .. i
        local np = CreateFrame("Frame", nil, UIParent)
        np:SetFrameStrata("WORLD")
        local own = CreateFrame("Frame", nil, np)
        plates[unit] = np
        states[unit] = { identity = own, owned = true, expected = true, reason = reason,
            nativeShown = true, nativeVisible = true, nativeAlpha = 1, nativeScale = 1,
            oursShown = reason ~= "owned_hidden", oursVisible = reason ~= "owned_invisible",
            oursAlpha = reason == "owned_alpha_zero" and 0 or 1, oursScale = 1,
            width = 120, height = 20, attached = reason ~= "owned_detached", barShown = true,
            nameShown = true, badgeShown = false, minion = false, nameOnly = false }
        for _, method in ipairs({ "SetParent", "ClearAllPoints", "SetPoint", "SetAlpha", "SetScale", "Hide", "Show", "HookScript", "SetScript" }) do
            np[method] = function() s.mutationCalls = s.mutationCalls + 1; error("PRIVATE_NATIVE_MUTATION") end
        end
        stub.FireEvent("NAME_PLATE_UNIT_ADDED", unit)
        return np, own, states[unit]
    end
    function s.tick(n) for _ = 1, n or 1 do s.advance(1); s.P.Tick() end end
    function s.remove(i)
        local unit = "nameplate" .. i
        plates[unit], states[unit] = nil, nil
        stub.FireEvent("NAME_PLATE_UNIT_REMOVED", unit)
    end
    function s.command(text) DUI.RunCommand(text) end
    function s.text(index) return s.P.Format(s.records()[index or 1]) end
    return s
end

T.test("platecapture: default watch is on but no native plates means no sampling ticker", function()
    local s = setup()
    T.truthy(s.store().watch)
    T.eq(#s.tickers, 0)
    T.eq(#s.records(), 0)
    s.add(1)
    T.eq(#s.tickers, 1)
    T.eq(s.tickers[1].interval, 1)
    s.remove(1)
    T.truthy(s.tickers[1].cancelled)
    T.eq(s.mutationCalls, 0)
end)

T.test("platecapture: three stable structural samples freeze before one prompt and never repair", function()
    local s = setup()
    local _, _, state = s.add(1, "owned_hidden")
    s.tick(2); T.eq(#s.records(), 0)
    s.DUI.Widgets.Ask = function(spec)
        T.eq(#s.records(), 1, "persist before opening any UI")
        state.oursShown, state.reason = true, nil
        s.prompts[#s.prompts + 1] = spec
    end
    s.tick()
    T.eq(#s.prompts, 1)
    T.eq(s.records()[1].kind, "structural")
    T.eq(s.records()[1].current.plates[1].ours.oursShown, false, "frozen value survives later changes")
    T.eq(s.records()[1].clientBuild, 12345)
    T.truthy(s.text():find("Frame flags do not prove pixels rendered", 1, true))
    s.prompts[1].onYes()
    T.eq(s.copies[1].text, s.text())
    state.reason = "owned_alpha_zero"; s.tick(10)
    T.eq(#s.prompts, 1); T.eq(#s.records(), 1, "at most one automatic capture per session")
    T.eq(s.mutationCalls, 0)
end)

T.test("platecapture: transient, unknown and missing ownership reset the streak", function()
    local s = setup()
    local _, _, state = s.add(1, "owned_hidden")
    s.tick(2); state.reason = nil; s.tick()
    state.reason = "owned_hidden"; s.tick(2)
    state.expected = nil; s.tick()
    state.expected = true; s.tick(2)
    state.identity, state.owned = nil, false; s.tick()
    T.eq(#s.records(), 0)
    state.identity, state.owned = CreateFrame("Frame", nil, UIParent), true
    s.tick(2); T.eq(#s.records(), 0)
    s.tick(); T.eq(#s.records(), 1)
end)

T.test("platecapture: native and owned rebinds and token removal require three fresh samples", function()
    local s = setup()
    local _, _, state = s.add(1, "owned_hidden")
    s.tick(2)
    state.identity = CreateFrame("Frame", nil, UIParent)
    s.tick(2); T.eq(#s.records(), 0)
    s.plates.nameplate1 = CreateFrame("Frame", nil, UIParent)
    s.tick(2); T.eq(#s.records(), 0)
    s.remove(1); s.add(1, "owned_hidden")
    s.tick(2); T.eq(#s.records(), 0)
    s.tick(); T.eq(#s.records(), 1)
end)

T.test("platecapture: combat manual snapshot is unknown, reads no native frames, then opens frozen copy", function()
    local s = setup()
    s.add(1, "owned_hidden"); s.tick(2)
    stub.EnterCombat()
    local calls = 0
    C_NamePlate.GetNamePlateForUnit = function() calls = calls + 1; error("PRIVATE_ERROR") end
    s.tick(3)
    s.command("platecapture")
    T.eq(calls, 0)
    T.eq(s.records()[1].current.gate, "restricted")
    T.isnil(s.records()[1].current.native)
    T.eq(#s.prompts, 0); T.eq(#s.copies, 0)
    stub.LeaveCombat()
    T.eq(#s.copies, 1)
    T.truthy(s.copies[1].text:find("native=?", 1, true))
    T.falsy(s.copies[1].text:find("PRIVATE_ERROR", 1, true))
end)

T.test("platecapture: quiet gates suppress automatic observations and reset prior streaks", function()
    for _, kind in ipairs({ "fade", "loading", "cinematic", "movie", "platefps", "platefix", "probe", "restriction" }) do
        local s = setup()
        s.add(1, "owned_hidden"); s.tick(2)
        if kind == "fade" then UIParent:SetAlpha(0.5)
        elseif kind == "loading" then stub.FireEvent("PLAYER_ENTERING_WORLD")
        elseif kind == "cinematic" then stub.FireEvent("CINEMATIC_START")
        elseif kind == "movie" then stub.FireEvent("PLAY_MOVIE")
        elseif kind == "platefps" then s.manager.testHidden = true
        elseif kind == "platefix" then s.manager.fixStep = 1
        elseif kind == "probe" then s.DUI.PlateRenderProbe.Active = function() return true end
        else stub.SetRestriction("Encounter", true) end
        s.tick(3); T.eq(#s.records(), 0, kind)
        UIParent:SetAlpha(1)
        s.manager.testHidden, s.manager.fixStep = nil, nil
        s.DUI.PlateRenderProbe.Active = function() return false end
        stub.FireEvent("CINEMATIC_STOP"); stub.FireEvent("STOP_MOVIE")
        stub.SetRestriction("Encounter", false); s.advance(6)
        s.tick(2); T.eq(#s.records(), 0, kind .. " reset")
        s.tick(); T.eq(#s.records(), 1, kind .. " recovers")
    end
end)

T.test("platecapture: pixel-only healthy flags and module-off scenes require manual capture", function()
    local s = setup()
    s.add(1); s.tick(8)
    T.eq(#s.records(), 0, "no automatic claim about invisible pixels")
    s.command("platecapture"); T.eq(#s.records(), 1)
    s = setup({ moduleOff = true })
    s.add(1, "owned_hidden"); s.tick(8)
    T.eq(#s.records(), 0)
    s.command("platecapture")
    T.eq(s.records()[1].current.nameplatesOn, false)
    T.eq(s.records()[1].current.native, 1)
    T.isnil(s.records()[1].current.owned)
    s.remove(1); s.command("platecapture")
    T.eq(s.records()[1].current.native, 0)
end)

T.test("platecapture: triggering slot beyond six is included in bounded detail", function()
    local s = setup()
    for i = 1, 8 do s.add(i, i == 8 and "owned_hidden" or nil) end
    s.tick(3)
    T.eq(#s.records()[1].current.plates, 6)
    T.eq(s.records()[1].current.plates[1].slot, 8)
    T.eq(s.records()[1].current.plates[1].reason, "owned_hidden")
    T.truthy(s.records()[1].current.detailsTruncated)
end)

T.test("platecapture: transient native API refusal retains watcher but resets streak", function()
    local s = setup()
    s.add(1, "owned_hidden"); s.tick(2)
    local getter = C_NamePlate.GetNamePlateForUnit
    C_NamePlate.GetNamePlateForUnit = function() error("PRIVATE_FAILURE") end
    s.tick()
    T.falsy(s.tickers[1].cancelled)
    C_NamePlate.GetNamePlateForUnit = getter
    s.tick(2); T.eq(#s.records(), 0)
    s.tick(); T.eq(#s.records(), 1)
end)

T.test("platecapture: allowlisted recording excludes arbitrary API content and raw errors", function()
    local s = setup()
    local np, _, state = s.add(1)
    state.name, state.guid, state.reason = "PRIVATE_NAME", "PRIVATE_GUID", "PRIVATE_REASON"
    np.GetName = function() error("must not request name") end
    np.GetRect = function() error("must not request coordinates") end
    np.GetAlpha = function() error("PRIVATE_ERROR") end
    s.DUI.Fade.BufferAudit = function() return { tracked = 2, enabled = 1, noFrameBuffers = false, hardware = "PRIVATE_GPU" } end
    stub.FireEvent("CVAR_UPDATE", "PRIVATE_CVAR_KEY", "PRIVATE_CVAR_VALUE")
    stub.FireEvent("ADDON_ACTION_BLOCKED", "PRIVATE_ADDON", "PRIVATE_FUNCTION")
    stub.FireEvent("CURSOR_CHANGED", "PRIVATE_CURSOR")
    stub.FireEvent("MODIFIER_STATE_CHANGED", "PRIVATE_KEY", "PRIVATE_VALUE")
    s.command("platecapture")
    local text = s.text()
    T.falsy(text:find("PRIVATE", 1, true), text)
    T.truthy(text:find("action_blocked", 1, true))
    T.truthy(text:find("cursor_changed", 1, true))
    T.truthy(text:find("modifier_changed", 1, true))
    T.truthy(s.records()[1].current.incomplete)
    T.eq(s.records()[1].current.buffer.tracked, 2)
    T.isnil(s.records()[1].current.plates[1].ours.identity)
    T.falsy(table.concat(stub.chat, "\n"):find("plate capture v1", 1, true), "report is never dumped into chat")
end)

T.test("platecapture: unknown native, owned and bubble values stay unknown rather than zero or prefix count", function()
    local s = setup()
    s.add(1)
    s.manager.CaptureState = function() return "PRIVATE_BAD_ADAPTER" end
    local b1, b2 = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    b1.IsVisible = function() return stub.Secret(true) end
    stub.bubbles = { b1, b2 }
    s.command("platecapture")
    T.isnil(s.records()[1].current.owned)
    T.eq(s.records()[1].current.bubbles, 2)
    T.isnil(s.records()[1].current.bubblesVisible)
    C_NamePlate.GetNamePlateForUnit = function() return "PRIVATE_NOT_A_FRAME" end
    s.command("platecapture")
    T.isnil(s.records()[1].current.native)
    T.falsy(s.text():find("PRIVATE", 1, true))
    stub.bubbles = { stub.Secret(b1) }
    T.noerror(function() s.command("platecapture") end)
    T.isnil(s.records()[1].current.bubbles)
end)

T.test("platecapture: bounded history and three records retain accessible immutable reports", function()
    local s = setup()
    s.add(1)
    for _ = 1, 75 do stub.FireEvent("CURSOR_CHANGED"); s.tick() end
    for i = 1, 5 do s.command("platecapture"); s.advance(1) end
    T.eq(#s.records(), 3)
    T.eq(#s.records()[1].history, 60)
    T.eq(#s.records()[1].events, 24)
    T.truthy(#s.text() <= 12000)
    T.truthy(s.records()[1].history[1].buffers ~= nil)
    local frozen = s.text(3)
    s.states.nameplate1.oursAlpha = 0
    s.command("platereport 3")
    T.eq(s.copies[#s.copies].text, frozen, "saved report is not recaptured")
end)

T.test("platecapture: persistent opt-out survives reload and emits one saved-report reminder", function()
    local s = setup()
    s.command("platecapture"); s.command("platewatch off")
    local saved = s.DUI.DB.Copy(s.DUI.DB.Root())
    s = setup({ saved = saved })
    T.eq(s.store().watch, false)
    T.eq(#s.records(), 1)
    local chat = table.concat(stub.chat, "\n")
    T.truthy(chat:find("saved local nameplate report", 1, true))
    local before = #stub.chat
    s.DUI.Fire("Login")
    T.eq(#stub.chat, before, "no repeated reminder or popup")
    s.add(1, "owned_hidden"); s.tick(5)
    T.eq(#s.tickers, 0); T.eq(#s.prompts, 0)
    s.command("platereport")
    T.eq(#s.copies, 1)
end)

T.test("platecapture: malformed persisted data is bounded and sanitized before export", function()
    local records = {}
    for i = 1, 20 do records[i] = { schema = 1, version = "PRIVATE_VERSION", kind = "PRIVATE_KIND",
        current = { native = 0 / 0, uiAlpha = math.huge, name = "PRIVATE_NAME", gate = "PRIVATE_GATE" },
        extra = "PRIVATE_DATA", events = { { elapsed = 1, what = "PRIVATE_EVENT" } } } end
    records[1].current = nil
    local s = setup({ saved = { plateCapture = { watch = false, records = records, text = "PRIVATE_TEXT" } } })
    T.eq(#s.records(), 3)
    for i = 1, 3 do
        T.noerror(function() s.command("platereport " .. i) end)
        T.falsy(s.text(i):find("PRIVATE", 1, true))
    end
    T.isnil(s.store().text)
    T.eq(s.records()[1].version, "unknown")
end)

T.test("platecapture: clear invalidates deferred copies and already-issued prompt callbacks", function()
    local s = setup()
    stub.EnterCombat(); s.command("platecapture"); s.command("platereport clear"); stub.LeaveCombat()
    s.advance(10)
    T.eq(#s.copies, 0); T.eq(#s.records(), 0)
    s.add(1, "owned_hidden"); s.tick(3)
    local prompt = s.prompts[1]
    T.truthy(prompt)
    s.command("platereport clear"); prompt.onYes(); s.advance(5)
    T.eq(#s.copies, 0); T.eq(#s.records(), 0)
end)

T.test("platecapture: watch off cancels pending automatic notice but keeps the saved report", function()
    local s = setup()
    s.otherPrompt = { key = "unrelated" }
    s.add(1, "owned_hidden"); s.tick(3)
    T.eq(#s.records(), 1); T.eq(#s.prompts, 0)
    s.command("platewatch off"); s.otherPrompt = nil; s.advance(5)
    T.eq(#s.prompts, 0); T.eq(#s.records(), 1)
    s.command("platereport"); T.eq(#s.copies, 1)
end)

T.test("platecapture: pending manual copy resumes after UI restore without plate events or watch", function()
    local s = setup()
    s.command("platewatch off")
    UIParent:Hide(); s.command("platecapture")
    T.eq(#s.copies, 0)
    UIParent:Show(); s.advance(3)
    T.eq(#s.copies, 1)
    T.eq(#s.tickers, 0, "UI retry is not a native sampling ticker")
    T.truthy(s.copies[1].text:find("gate=ui_hidden", 1, true), "copy remains frozen at capture")
end)

T.test("platecapture: binding is named and invokes the same manual command", function()
    local s = setup()
    T.eq(BINDING_NAME_DAYLIGHTUI_PLATECAPTURE, "Capture missing nameplates")
    local f = assert(io.open("Bindings.xml", "r")); local xml = f:read("*a"); f:close()
    T.truthy(xml:find('name="DAYLIGHTUI_PLATECAPTURE"', 1, true))
    T.truthy(xml:find('RunCommand("platecapture")', 1, true))
    s.command("platecapture")
    T.eq(#s.records(), 1); T.eq(#s.copies, 1)
end)

T.test("platecapture: persistent opt-out prevents even the startup native scan", function()
    local s = setup({ saved = { plateCapture = { watch = false, records = {} } } })
    T.eq(s.lookups(), 0)
    s.add(1, "owned_hidden"); s.tick(4)
    T.eq(s.lookups(), 0); T.eq(#s.tickers, 0)
    s.command("platecapture")
    T.truthy(s.lookups() > 0, "explicit manual capture still works")
end)

T.test("platecapture: modifier and blocked-drag evidence uses fixed labels even in combat", function()
    local s = setup()
    stub.EnterCombat()
    for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CURSOR_CHANGED", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID" }) do
        stub.FireEvent(event, "PRIVATE_PAYLOAD", "PRIVATE_FUNCTION")
    end
    stub.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    stub.FireEvent("MODIFIER_STATE_CHANGED", "RSHIFT", 0)
    stub.FireEvent("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    stub.FireEvent("MODIFIER_STATE_CHANGED", "RALT", 0)
    stub.FireEvent("MODIFIER_STATE_CHANGED", stub.Secret("LSHIFT"), stub.Secret(1))
    s.command("platecapture")
    local text = s.text()
    for _, label in ipairs({ "action_blocked", "action_forbidden", "cursor_changed", "actionbar_grid_shown", "actionbar_grid_hidden", "shift_down", "shift_up", "ctrl_down", "alt_up" }) do
        T.truthy(text:find(label, 1, true), label)
    end
    T.falsy(text:find("PRIVATE", 1, true))
    T.eq(s.records()[1].current.gate, "restricted")
    T.eq(#s.prompts, 0)
end)
