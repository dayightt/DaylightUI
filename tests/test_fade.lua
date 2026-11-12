local stub = require("stub")

-- A test area: its settings live in General under key, and its frames are given.
local function area(DUI, key, s, frames, extra)
    DUI.DB.General()[key] = s
    local def = { key = key, scope = "general", path = key, frames = function() return frames end }
    for k, v in pairs(extra or {}) do def[k] = v end
    DUI.Fade.Register(def)
end

local function frame(over)
    local f = CreateFrame("Frame", nil, UIParent)
    f:Show()
    f.__over = over
    function f:IsMouseOver() return self.__over == true end
    return f
end

-- secs of game time in frame-sized steps. A step over Fade.MAX_STEP counts as a
-- hitch and is cut short.
local function play(F, secs)
    local n = math.max(1, math.floor(secs * 60 + 0.5))
    for _ = 1, n do stub.RunOnUpdate(F.driver, secs / n) end
end

-- Back in the world after a loading screen: steady frames until the fade-in starts.
local function steady(F)
    stub.RunTimers()
    for _ = 1, 60 do stub.RunOnUpdate(F.settler, 1 / 60) end
    stub.RunTimers()
end

-- One check, then two seconds of frames.
local function settle(F)
    F.Step()
    for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
end

T.test("fade: out of combat fades after the delay, a fight or the mouse brings it back", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a, b = frame(), frame()
    area(DUI, "tf", { mode = "ooc", alpha = 0.3, mouseover = true, delay = 2 }, { a, b })
    settle(F)
    T.eq(a:GetAlpha(), 1, "inside the delay: still shown")
    stub.Advance(3)
    settle(F)
    T.eq(a:GetAlpha(), 0.3, "past the delay: faded")
    T.eq(b:GetAlpha(), 0.3, "the whole area together")
    a.__over = true
    settle(F)
    T.eq(b:GetAlpha(), 1, "the mouse over one wakes the area")
    a.__over = false
    stub.Advance(3)
    settle(F)
    T.eq(a:GetAlpha(), 0.3, "faded again after the delay")
    stub.EnterCombat()
    settle(F)
    T.eq(a:GetAlpha(), 1, "in a fight: full")
    stub.LeaveCombat()
    settle(F)
    T.eq(a:GetAlpha(), 1, "just out of it: the delay first")
    stub.Advance(3)
    settle(F)
    T.eq(a:GetAlpha(), 0.3)
end)

T.test("fade: always fades in a fight too; show on mouseover off ignores the mouse", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = false, delay = 1 }, { a })
    stub.EnterCombat()
    stub.Advance(2)
    settle(F)
    T.eq(a:GetAlpha(), 0, "always: faded even in combat")
    a.__over = true
    settle(F)
    T.eq(a:GetAlpha(), 0, "mouseover off: stays faded")
    stub.LeaveCombat()
end)

T.test("fade: never leaves it shown, and turned off it eases back once then lets go", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = true, delay = 0 }, { a })
    settle(F)
    T.eq(a:GetAlpha(), 0)
    DUI.DB.General().tf.mode = "never"
    stub.Advance(3)
    settle(F)
    T.eq(a:GetAlpha(), 1, "back to full")
    a:SetAlpha(0.7)
    settle(F)
    T.eq(a:GetAlpha(), 0.7, "then left alone")
end)

T.test("fade: 0.6 s out and 0.35 s in on a soft curve; turning mid-way doesn't jump", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = true, delay = 0 }, { a })
    F.Step()
    play(F, 0.3)
    T.near(a:GetAlpha(), 0.5, 0.01, "half the time: half way (smoothstep is symmetric)")
    play(F, 0.3)
    T.eq(a:GetAlpha(), 0, "0.6 s: there")
    a.__over = true
    F.Step()
    play(F, 0.35)
    T.eq(a:GetAlpha(), 1, "back in 0.35 s")
    a.__over = false
    F.Step()
    play(F, 0.15)
    local before = a:GetAlpha()
    a.__over = true
    F.Step()
    play(F, 0.01)
    T.truthy(math.abs(a:GetAlpha() - before) < 0.05, "turning round: no jump (" .. before .. " -> " .. a:GetAlpha() .. ")")
    T.truthy(a:GetAlpha() >= before, "and heading up")
end)

T.test("fade: wake shows it at full, cap dims it further", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    local awake, cap = false, nil
    area(DUI, "tf", { mode = "never" }, { a },
         { wake = function() return awake end, cap = function() return cap end })
    cap = 0
    settle(F)
    T.eq(a:GetAlpha(), 0, "a cap works with mode never")
    awake = true
    settle(F)
    T.eq(a:GetAlpha(), 1, "wake beats the cap")
end)

T.test("fade: an area's own over counts as the mouse: its setting obeyed, a hush past it", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    local over, asked = false, 0
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = false, delay = 0 }, { a },
         { over = function() asked = asked + 1; return over end })
    over = true
    settle(F)
    T.eq(a:GetAlpha(), 0, "show on mouseover off: stays faded")
    F.Hush("t", { "tf" })
    settle(F)
    T.eq(a:GetAlpha(), 1, "hushed: the mouse shows it")
    over = false
    for _ = 1, 3 do settle(F) end   -- a hush eases out slowly
    T.eq(a:GetAlpha(), 0, "off it: gone")
    F.Unhush("t", true)
    DUI.DB.General().tf.mode = "never"
    settle(F)
    asked = 0
    for _ = 1, 10 do settle(F) end
    T.eq(asked, 0, "never fades: not asked")
end)

T.test("fade: an area that never fades doesn't ask the mouse or its wake each tick", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame(true)
    local asked = 0
    local real = a.IsMouseOver
    function a:IsMouseOver() asked = asked + 1; return real(self) end
    area(DUI, "tf", { mode = "never", opacity = 0.8 }, { a },
         { wake = function() asked = asked + 1; return true end })
    for _ = 1, 10 do settle(F) end
    T.eq(asked, 0, "ten ticks: nothing asked")
    T.near(a:GetAlpha(), 0.8, 0.001, "shown at its opacity")
end)

T.test("fade: unlocked, test mode or the area's own options page show it at full", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = true, delay = 0 }, { a }, { page = "Test.page" })
    settle(F)
    T.eq(a:GetAlpha(), 0)
    DUI.Movers.unlocked = true
    settle(F)
    T.eq(a:GetAlpha(), 1, "unlocked")
    DUI.Movers.unlocked = false
    DUI.testMode = true
    settle(F)
    T.eq(a:GetAlpha(), 1, "test mode")
    DUI.testMode = false
    F.editMode = true
    settle(F)
    T.eq(a:GetAlpha(), 1, "Edit Mode")
    F.editMode = false
    local P = DUI.OptionsPanel
    local shown, current = P.IsShown, P.Current
    P.IsShown = function() return true end
    P.Current = function() return "Test.page" end
    settle(F)
    T.eq(a:GetAlpha(), 1, "its page open")
    local held = true
    local down = _G.IsMouseButtonDown
    _G.IsMouseButtonDown = function() return held end
    DUI:Set("general", "tf.alpha", 0.4)
    settle(F)
    T.eq(a:GetAlpha(), 0.4, "dragging the faded opacity shows the faded look")
    stub.Advance(5)
    settle(F)
    T.eq(a:GetAlpha(), 0.4, "for as long as the mouse holds it")
    held = false
    stub.FireEvent("GLOBAL_MOUSE_UP", "LeftButton")
    settle(F)
    T.eq(a:GetAlpha(), 1, "let go: back to full at once while the page is open")
    held = true
    DUI:Set("general", "tf.delay", 1)
    DUI:Set("general", "tf.mode", "combat")
    settle(F)
    T.eq(a:GetAlpha(), 1, "picking a mode or a delay doesn't flash it away")
    held = false
    DUI:Set("general", "tf.alpha", 0.2)
    settle(F)
    T.eq(a:GetAlpha(), 1, "a change without the mouse held (typed, reset) doesn't either")
    _G.IsMouseButtonDown = down
    P.IsShown, P.Current = shown, current
end)

T.test("fade: an area several pages show is at full with any of them open", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = true, delay = 0 }, { a }, { page = { "Test.one", "Test.two" } })
    local P = DUI.OptionsPanel
    local shown, current = P.IsShown, P.Current
    local page = "Test.other"
    P.IsShown = function() return true end
    P.Current = function() return page end
    settle(F)
    T.eq(a:GetAlpha(), 0, "another page: faded")
    page = "Test.two"
    settle(F)
    T.eq(a:GetAlpha(), 1, "its second page open")
    P.IsShown, P.Current = shown, current
end)

T.test("fade: paint is used instead of SetAlpha; Hold stops painting", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    local painted
    area(DUI, "tf", { mode = "always", alpha = 0.2, mouseover = true, delay = 0 }, { a },
         { paint = function(f, v) painted = v end })
    settle(F)
    T.eq(painted, 0.2, "paint got the alpha")
    T.eq(a:GetAlpha(), 1, "and SetAlpha wasn't called")
    local b = frame()
    area(DUI, "tf2", { mode = "always", alpha = 0, mouseover = true, delay = 0 }, { b })
    F.Hold("tf2", true)
    settle(F)
    T.eq(b:GetAlpha(), 1, "held: not painted")
    F.Hold("tf2", false)
    T.eq(b:GetAlpha(), 0, "released: painted where it is")
    local now, goal, faded = F.State("tf")
    T.eq(now, 0.2); T.eq(goal, 0.2); T.eq(faded, 0.2)
end)

T.test("fade: a secret mouse answer counts as not over", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    function a:IsMouseOver() return stub.Secret(true) end
    function a:GetLeft() return stub.Secret(0) end   -- secret edges too, as on a secure header in combat
    T.falsy(F.Over(a), "secret, and no plain edges: not over")
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = true, delay = 0 }, { a })
    settle(F)
    T.eq(a:GetAlpha(), 0, "fades, no error")
end)

T.test("fade: a frame that joins later is repainted to the faded alpha", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local list = { frame() }
    area(DUI, "tf", { mode = "always", alpha = 0.25, mouseover = true, delay = 0 }, list)
    settle(F)
    local late = frame()
    list[2] = late
    F.Step()
    T.eq(late:GetAlpha(), 0.25, "one tick later: faded like the rest")
end)

T.test("fade: an area shown at full doesn't ask for its frames each tick", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local asked = 0
    DUI.DB.General().tf = { mode = "never" }
    F.Register{ key = "tf", scope = "general", path = "tf",
                frames = function() asked = asked + 1; return { frame() } end }
    asked = 0
    for _ = 1, 10 do F.Step() end
    T.eq(asked, 0, "ten ticks: never asked")
end)

T.test("fade: a faded area at rest isn't painted every tick, only now and then", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    local painted = 0
    area(DUI, "tf", { mode = "always", alpha = 0.3, mouseover = true, delay = 0 }, { a },
         { paint = function(f, v) painted = painted + 1; f:SetAlpha(v) end })
    settle(F)
    T.eq(a:GetAlpha(), 0.3)
    painted = 0
    for _ = 1, 5 do F.Step() end
    T.eq(painted, 0, "resting: not painted again")
    a:SetAlpha(1)   -- someone else's
    stub.Advance(F.REPAINT)
    F.Step()
    T.eq(painted, 1, "after a while: painted once")
    T.eq(a:GetAlpha(), 0.3, "back where it belongs")
end)

T.test("fade: motion off snaps", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    DUI.DB.General().motion = false
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = true, delay = 0 }, { a })
    F.Step()
    T.eq(a:GetAlpha(), 0, "straight there")
end)

T.test("fade: the options rows read the same everywhere and dim while Never", function()
    local DUI = stub.Load()
    local items = DUI.Fade.Items("player.fade.")
    T.eq(#items, 7)
    T.eq(items[1].key, "player.fade.opacity"); T.eq(items[1].label, "Opacity")
    T.eq(items[1].min, 0); T.eq(items[1].max, 1); T.eq(items[1].unit, "%")
    T.eq(items[2].key, "player.fade.mode"); T.eq(items[2].label, "Visible")
    T.deq(items[2].order, { "never", "ooc", "combat", "always", "float" }, "Float is one of its picks")
    T.eq(items[2].values.float, "Only when something changes")
    T.eq(items[3].key, "player.fade.alpha"); T.eq(items[3].label, "Faded opacity")
    T.eq(items[4].key, "player.fade.mouseover"); T.eq(items[4].label, "Show on mouseover")
    T.eq(items[5].key, "player.fade.target"); T.eq(items[5].label, "Show with a target")
    T.eq(items[6].key, "player.fade.targetEnemy"); T.eq(items[6].label, "Only enemies")
    T.eq(items[7].key, "player.fade.delay"); T.eq(items[7].label, "Delay")
    local vals = { ["player.fade.mode"] = "never" }
    local get = function(k) return vals[k] end
    T.truthy(items[3].disabled(get), "Always: dimmed")
    T.falsy(items[1].disabled(get), "Opacity works with Always too")
    vals["player.fade.mode"] = "ooc"
    T.falsy(items[3].disabled(get), "Fade out of combat: live")
    vals["player.fade.mode"] = "float"
    T.falsy(items[3].disabled(get), "Only when something changes: Faded opacity live")
    T.falsy(items[7].disabled(get), "and Delay")
    T.truthy(items[6].disabled(get), "Only enemies: dimmed while Show with a target is off")
    vals["player.fade.target"] = true
    T.falsy(items[6].disabled(get), "and live once it's on")
    local fixed = DUI.Fade.Items("target.fade.", nil, nil, nil, { noFloat = true })
    T.isnil(fixed[2].values.float, "no float pick where it can't float")
    T.deq(fixed[2].order, { "never", "ooc", "combat", "always" })
    local off = DUI.Fade.Items("x.fade.", { { type = "toggle", key = "x.idle", label = "Idle" } },
                               function() return true end)
    T.eq(#off, 8, "extra rows go last")
    T.truthy(off[1].disabled(get), "the page's own disabled applies to every row")
    local card = DUI.Fade.Card("player.fade.")
    T.eq(card.label, "Opacity & fade"); T.eq(#card.items, 7)
    local d = DUI.Fade.Defaults({ mode = "always", delay = 3 })
    T.eq(d.mode, "always"); T.eq(d.delay, 3); T.eq(d.alpha, 0); T.eq(d.mouseover, true); T.eq(d.opacity, 1)
    T.eq(d.target, false, "Show with a target: off unless picked")
    T.eq(d.targetEnemy, false, "any target counts unless picked")
    T.isnil(d.float, "no Float switch any more")
    T.truthy(DUI.Fade.Defaults() ~= DUI.Fade.Defaults(), "a fresh table each time")
end)

T.test("fade upgrade: a saved Float switch becomes the Visible pick Only when something changes", function()
    local DUI = stub.Load()
    local Up = DUI.FadeUpgrade
    local p = { general = { fadeEngine = 7 }, modules = {
        UnitFrames = { player = { fade = { mode = "combat", float = true } }, pet = { fade = { mode = "ooc", float = false } } },
        ActionBars = { bars = { main = { fade = { float = true } } }, bagBarFade = { float = true } },
        Buffs = { settings = { debuff = { fade = { float = true, alpha = 0.2 } } } },
        Chat = { floating = true, sounds = { float = true } } } }
    Up.Run(p)
    local m = p.modules
    T.eq(m.UnitFrames.player.fade.mode, "float"); T.isnil(m.UnitFrames.player.fade.float)
    T.eq(m.UnitFrames.pet.fade.mode, "ooc", "Float off: its pick stays"); T.isnil(m.UnitFrames.pet.fade.float)
    T.eq(m.ActionBars.bars.main.fade.mode, "float")
    T.eq(m.ActionBars.bagBarFade.mode, "float", "a ...Fade table too")
    T.eq(m.Buffs.settings.debuff.fade.mode, "float"); T.eq(m.Buffs.settings.debuff.fade.alpha, 0.2)
    T.eq(m.Chat.sounds.float, true, "only fade tables")
    T.eq(p.general.fadeEngine, 8)
end)

T.test("fade upgrade: steps run once per profile and FromOOC moves the old keys", function()
    local DUI = stub.Load()
    local Up = DUI.FadeUpgrade
    local t = { fadeOOC = true, oocAlpha = 0.4 }
    Up.FromOOC(t, 0.1)
    T.eq(t.fade.mode, "ooc"); T.eq(t.fade.alpha, 0.4, "its own opacity wins")
    T.isnil(t.fadeOOC); T.isnil(t.oocAlpha)
    local u = { fadeOOC = true }
    Up.FromOOC(u, 0.1)
    T.eq(u.fade.alpha, 0.1, "else General's")
    local v = { oocAlpha = 0.3 }
    Up.FromOOC(v, nil)
    T.isnil(v.fade.mode, "an opacity alone keeps the mode at its default")
    T.eq(v.fade.alpha, 0.3)
    local runs = 0
    local saved = Up.STEPS
    Up.STEPS = { function() runs = runs + 1 end }
    local p = { general = {}, modules = {} }
    Up.Run(p); Up.Run(p)
    T.eq(runs, 1, "once per profile")
    T.eq(p.general.fadeEngine, 1)
    Up.STEPS = saved
end)

T.test("fade: login fade-in starts everything at 0 and glides to where it belongs", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    T.truthy(F.intro, "on by default")
    local a, b = frame(), frame()
    area(DUI, "shown", { mode = "never" }, { a })
    area(DUI, "faded", { mode = "always", alpha = 0.2, mouseover = true, delay = 3 }, { b })
    T.eq(a:GetAlpha(), 0, "starts invisible")
    T.eq(b:GetAlpha(), 0)
    F.Step()
    T.eq(a:GetAlpha(), 0, "held at 0 until the world is in")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    F.Step()
    play(F, 0.5)
    T.eq(a:GetAlpha(), 0, "still 0 while the loading screen is up")
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    steady(F)
    play(F, F.INTRO / 2)
    T.truthy(a:GetAlpha() > 0.3 and a:GetAlpha() < 0.7, "half way at half the fade-in (" .. a:GetAlpha() .. ")")
    play(F, F.INTRO / 2)
    T.eq(a:GetAlpha(), 1, "shown areas end shown")
    T.eq(b:GetAlpha(), 1, "set to fade: up for the login reveal first")
    stub.Advance(F.REVEAL_SPREAD + 2 * F.REVEAL_TIME)
    F.Step()
    play(F, F.OUT)
    T.eq(b:GetAlpha(), 0.2, "then faded, no wait for the delay")
    local c = frame()
    area(DUI, "late", { mode = "never" }, { c })
    T.eq(c:GetAlpha(), 1, "an area that comes later just shows")
end)

T.test("fade: the fade-in can be turned off; motion off skips it too", function()
    local DUI = stub.Load({ intro = true })
    DUI.DB.General().fadeIn = false
    local F = DUI.Fade
    local a = frame()
    area(DUI, "x", { mode = "always", alpha = 0.3, mouseover = true, delay = 3 }, { a })
    T.eq(a:GetAlpha(), 0.3, "off: starts where it belongs")
    T.falsy(F.intro)
end)

T.test("fade upgrade: General's old opacity is gone once every module has read it", function()
    local DUI = stub.Load()
    local p = { general = { oocAlpha = 0.4 }, modules = { InfoPanel = { fadeOOC = true } } }
    DUI.FadeUpgrade.Run(p)
    T.isnil(p.general.oocAlpha)
    T.eq(p.modules.InfoPanel.fade.alpha, 0.4, "read before it went")
    T.eq(p.general.fadeEngine, #DUI.FadeUpgrade.STEPS)
end)

T.test("fade upgrade: copying an old profile keeps its chat idle switch (upgraded before defaults fill it)", function()
    local DUI = stub.Load({ chat = true })
    DaylightUIDB.profileData.Old = { general = {}, modules = { Chat = { fade = false, fadeAfter = 20 } }, positions = {} }
    T.eq(DUI.Profiles.Create("New", nil, "Old"), "New")
    local c = DaylightUIDB.profileData.New.modules.Chat
    T.eq(c.hides, "fights", "the copy: idle fade still off (Chat hides in fights only)")
    T.eq(c.idleAfter, 20)
    T.eq(DaylightUIDB.profileData.Old.modules.Chat.hides, "fights", "and the source too")
end)

T.test("fade: the fade-in starts anyway if the loading screen never says it's gone", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local a = frame()
    area(DUI, "shown", { mode = "never" }, { a })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.Advance(F.INTRO_FALLBACK - 1)
    F.Step()
    play(F, F.INTRO - 0.3)
    T.eq(a:GetAlpha(), 0, "not yet")
    stub.Advance(2)
    F.Step()
    play(F, F.INTRO)
    T.eq(a:GetAlpha(), 1, "the fallback started it")
end)

T.test("fade: and if the world never comes in, a late safety starts it", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local a = frame()
    area(DUI, "shown", { mode = "never" }, { a })
    stub.Advance(F.INTRO_SAFETY + 1)
    F.Step()
    play(F, F.INTRO)
    T.eq(a:GetAlpha(), 1)
end)

T.test("fade: after the loading screen the fade-in waits out the stutter: hitches hold it back, steady frames start it, the cap starts it anyway", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local a = frame()
    area(DUI, "shown", { mode = "never" }, { a })
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    stub.RunTimers()
    T.truthy(F.settler:IsShown(), "watching the frames")
    T.truthy(F.intro, "not started at the loading screen")
    for _ = 1, 6 do
        for _ = 1, 15 do stub.RunOnUpdate(F.settler, 1 / 60) end   -- a quarter second smooth
        stub.RunOnUpdate(F.settler, 0.1)                           -- then a hitch
    end
    T.truthy(F.intro, "hitches every quarter second: still waiting")
    for _ = 1, 30 do stub.RunOnUpdate(F.settler, 1 / 60) end
    T.falsy(F.intro, "half a second steady: started")
    T.falsy(F.settler:IsShown(), "the watcher stops (tests/test_lag)")

    DUI = stub.Load({ intro = true })
    F = DUI.Fade
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    stub.RunTimers()
    local t = 0
    while F.intro and t < 10 do stub.RunOnUpdate(F.settler, 0.1); t = t + 0.1 end
    T.truthy(t <= F.STEADY_CAP, "never steady: the cap starts it (" .. t .. " s)")
    T.falsy(F.settler:IsShown())
end)

T.test("fade: one long frame (the game catching up after a loading screen) does not finish a fade at once", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local a = frame()
    area(DUI, "shown", { mode = "never" }, { a })
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    steady(F)
    stub.RunOnUpdate(F.driver, 2)
    T.truthy(a:GetAlpha() < 0.2, "barely started (" .. a:GetAlpha() .. ")")
    play(F, 0.5)
    T.truthy(a:GetAlpha() > 0.2 and a:GetAlpha() < 0.9, "then glides (" .. a:GetAlpha() .. ")")
    play(F, 1)
    T.eq(a:GetAlpha(), 1)
end)

T.test("fade: show with a target brings it back while targeting, the delay runs once it's cleared", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a, b = frame(), frame()
    area(DUI, "tt", { mode = "ooc", alpha = 0.2, mouseover = false, target = true, delay = 2 }, { a })
    area(DUI, "tn", { mode = "ooc", alpha = 0.2, mouseover = false, delay = 2 }, { b })
    stub.units.target = { name = "Boar" }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    play(F, 0.5)
    stub.Advance(3); settle(F)
    T.eq(a:GetAlpha(), 1, "a target: stays shown")
    T.eq(b:GetAlpha(), 0.2, "switch off: fades as before")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    settle(F)
    T.eq(a:GetAlpha(), 1, "cleared: the delay runs first")
    stub.Advance(3); settle(F)
    T.eq(a:GetAlpha(), 0.2, "then it fades")
    stub.units.target = { name = "Wolf" }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    play(F, 1)
    T.eq(a:GetAlpha(), 1, "a new target: back at once")
end)

T.test("fade: show with a target, only enemies: a quest giver keeps it faded, a boar brings it back", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    local a, fl = frame(), frame()
    area(DUI, "te", { mode = "ooc", alpha = 0.2, mouseover = false, target = true, targetEnemy = true, delay = 2 }, { a })
    area(DUI, "tf", { mode = "float", alpha = 0, mouseover = false, target = true, targetEnemy = true, delay = 2 }, { fl })
    stub.Advance(3); settle(F)
    stub.units.target = { name = "Quest Giver" }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.Advance(3); settle(F)
    T.eq(a:GetAlpha(), 0.2, "a friendly target: stays faded")
    T.eq(fl:GetAlpha(), 0, "Float too")
    stub.units.target = { name = "Boar", hostile = true }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    play(F, 1)
    T.eq(a:GetAlpha(), 1, "something you can attack: back")
    T.eq(fl:GetAlpha(), 1, "Float too")
    _G.UnitCanAttack = nil
end)

T.test("fade: Float: gone out of a fight, back in one, under the mouse, with a target, or for a moment after a change", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a, t, n = frame(), frame(), frame()
    -- Floating: its other rows still count.
    area(DUI, "fa", { mode = "float", alpha = 0.2, mouseover = false, delay = 2 }, { a })
    area(DUI, "ft", { mode = "float", alpha = 0, target = true, delay = 2 }, { t })
    area(DUI, "fn", { mode = "never", delay = 2 }, { n })
    stub.Advance(3); settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "floats to its own faded opacity")
    T.eq(t:GetAlpha(), 0)
    T.eq(n:GetAlpha(), 1, "Float off: its own Never")
    -- A change brings it back, then it goes away its delay after the last one.
    F.Wake("fa"); F.Wake("fn")
    settle(F)
    T.eq(a:GetAlpha(), 1, "a change brings it back")
    T.eq(t:GetAlpha(), 0, "only that area")
    stub.Advance(1.5); settle(F)
    T.eq(a:GetAlpha(), 1, "inside its delay")
    stub.Advance(1); settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "then it floats away")
    -- The mouse only where Show on mouseover is on.
    a.__over, t.__over = true, true
    settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "Show on mouseover off: stays away")
    T.eq(t:GetAlpha(), 1, "on: back under the mouse")
    a.__over, t.__over = false, false
    stub.Advance(3); settle(F)
    -- A target, where Show with a target is on.
    stub.units.target = { name = "Boar" }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    settle(F)
    T.eq(t:GetAlpha(), 1, "a target: back")
    T.near(a:GetAlpha(), 0.2, 1e-6, "the others stay away")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.Advance(3); settle(F)
    -- A fight brings it back at once, and after it the delay runs first.
    stub.EnterCombat()
    play(F, F.IN)
    T.eq(a:GetAlpha(), 1, "a fight: back")
    stub.LeaveCombat()
    settle(F)
    T.eq(a:GetAlpha(), 1, "just out of it: the delay first")
    stub.Advance(3); settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "then away")
    -- Float off: its own Never, and a change wakes nothing.
    DUI:Set("general", "fa.mode", "never")
    settle(F)
    T.eq(a:GetAlpha(), 1, "Float off: its own Never again")
    area(DUI, "fx", { mode = "always", alpha = 0, mouseover = false, delay = 0 }, { n })
    stub.Advance(1); settle(F)
    F.Wake("fx")
    settle(F)
    T.eq(n:GetAlpha(), 0, "Float off: a change wakes nothing")
end)

T.test("fade: Float shows a change a moment even with a delay of 0; an area that can't float never does", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a, b = frame(), frame()
    area(DUI, "fz", { mode = "float", delay = 0 }, { a })
    area(DUI, "fy", { mode = "float", delay = 0 }, { b }, { float = false })
    stub.Advance(1); settle(F)
    T.eq(a:GetAlpha(), 0)
    T.eq(b:GetAlpha(), 1, "float = false: its Float setting does nothing")
    F.Wake("fz")
    settle(F)
    T.eq(a:GetAlpha(), 1, "back for a moment")
    stub.Advance(F.WAKE + 0.1); settle(F)
    T.eq(a:GetAlpha(), 0, "away once it's over")
    T.eq(F.Floats("fz"), true); T.eq(F.Floats("fy"), false); T.eq(F.Floats("nope"), false)
end)

T.test("fade: Float everything is on only while every area that can float does; it sets them all", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    area(DUI, "f1", { mode = "never" }, { frame() })
    area(DUI, "f2", { mode = "ooc" }, { frame() })
    area(DUI, "f3", { mode = "never" }, { frame() }, { float = false })
    T.eq(F.AllFloat(), false)
    F.SetAllFloat(true)
    T.eq(DUI.DB.General().f1.mode, "float"); T.eq(DUI.DB.General().f2.mode, "float")
    T.eq(DUI.DB.General().f3.mode, "never", "an area that can't float is left alone")
    T.eq(F.AllFloat(), true, "every one on: on")
    DUI:Set("general", "f2.mode", "combat")
    T.eq(F.AllFloat(), false, "one off: off")
    T.eq(DUI.DB.General().f1.mode, "float", "the others keep floating")
    F.SetAllFloat(false)
    T.eq(DUI.DB.General().f1.mode, "never", "off: back to the default pick")
    T.eq(DUI.DB.General().f2.mode, "combat", "one that wasn't floating keeps its pick")
end)

T.test("fade: a bad float is refused", function()
    local DUI = stub.Load()
    local ok = pcall(DUI.Fade.Register, { key = "bad", scope = "general", path = "bad",
                                          frames = function() return {} end, float = "maybe" })
    T.eq(ok, false)
end)

T.test("fade: in combat fades only while fighting", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tc", { mode = "combat", alpha = 0.3, mouseover = false, delay = 0 }, { a })
    settle(F)
    T.eq(a:GetAlpha(), 1, "out of combat: shown")
    stub.EnterCombat()
    settle(F)
    T.eq(a:GetAlpha(), 0.3, "fighting: faded")
    stub.LeaveCombat()
    settle(F)
    T.eq(a:GetAlpha(), 1, "after: shown again")
end)

-- It used to wait 3-4 s into a fight, dim at once, and snap back the moment the
-- fight ended.
T.test("fade: in combat starts dimming as the fight starts, slowly, and comes back calmly", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tc", { mode = "combat", alpha = 0.3, mouseover = true, delay = 4.5 }, { a })
    settle(F)
    stub.EnterCombat()
    F.Step()
    play(F, 0.15)
    T.truthy(a:GetAlpha() < 0.9, "moving from the first moment (eased out), not a slow start then a rush")
    play(F, F.IN - 0.15)
    T.truthy(a:GetAlpha() < 0.95, "dimming already, no wait for the delay")
    T.truthy(a:GetAlpha() > 0.5, "but slowly")
    play(F, F.FIGHT_OUT)
    T.near(a:GetAlpha(), 0.3, 1e-6, "dimmed")
    -- The mouse mid-fight brings it back, and the delay counts once it leaves.
    a.__over = true
    settle(F)
    T.near(a:GetAlpha(), 1, 1e-6, "under the mouse: shown")
    a.__over = false
    stub.Advance(1)
    settle(F)
    T.near(a:GetAlpha(), 1, 1e-6, "inside the delay after the mouse left")
    stub.Advance(4)
    settle(F)
    T.near(a:GetAlpha(), 0.3, 1e-6, "dimmed again after the delay")
    -- It used to come back the moment the fight ended. Now the delay runs first,
    -- then it eases back calmly.
    stub.LeaveCombat()
    settle(F)
    T.near(a:GetAlpha(), 0.3, 1e-6, "still dimmed just after the fight")
    stub.Advance(3)
    settle(F)
    T.near(a:GetAlpha(), 0.3, 1e-6, "inside the delay")
    stub.Advance(1.6)
    F.Step()
    play(F, F.IN)
    T.truthy(a:GetAlpha() < 0.9, "no snap back once the delay is up")
    play(F, F.FIGHT_IN)
    T.near(a:GetAlpha(), 1, 1e-6, "back after the delay")
    -- Shown under the mouse as the fight ends, it stays shown with no dip.
    stub.EnterCombat()
    settle(F)
    play(F, F.FIGHT_OUT)
    a.__over = true
    settle(F)
    stub.LeaveCombat()
    a.__over = false
    settle(F)
    T.near(a:GetAlpha(), 1, 1e-6, "shown at the fight's end: stays shown")
end)

T.test("fade: opacity holds an area there with Never, and fading goes from it and back to it", function()
    for _, o in ipairs({ 0.5, 0.25, 0.8, 1 }) do
        local DUI = stub.Load()
        local F = DUI.Fade
        local a = frame()
        area(DUI, "tf", { mode = "never", alpha = 0, mouseover = true, delay = 2, opacity = o }, { a })
        settle(F)
        T.near(a:GetAlpha(), o, 1e-6, "Never: sits at its opacity " .. o)
        DUI.DB.General().tf.mode = "ooc"
        stub.Advance(3)
        settle(F)
        T.near(a:GetAlpha(), 0, 1e-6, "faded all the way from " .. o)
        a.__over = true
        settle(F)
        T.near(a:GetAlpha(), o, 1e-6, "the mouse brings it back to " .. o .. ", not full")
        a.__over = false
        stub.EnterCombat()
        settle(F)
        T.near(a:GetAlpha(), o, 1e-6, "a fight brings it back to " .. o)
        stub.LeaveCombat()
    end
end)

T.test("fade: the faded alpha never goes above opacity; a bad opacity falls back", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0.7, mouseover = true, delay = 0, opacity = 0.4 }, { a })
    settle(F)
    T.near(a:GetAlpha(), 0.4, 1e-6, "faded 70% over opacity 40%: stays at 40%")
    DUI.DB.General().tf.alpha = 0.2
    settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6)
    local _, _, faded, opacity = F.State("tf")
    T.near(faded, 0.2, 1e-6); T.near(opacity, 0.4, 1e-6)
    DUI.DB.General().tf.opacity = -1
    T.eq(F.Opacity("general", "tf"), 0, "never below 0")
    DUI.DB.General().tf.opacity = "x"
    T.eq(F.Opacity("general", "tf"), 1, "not a number: full")
    T.eq(F.Opacity("general", "nothing"), 1, "no settings: full")
end)

T.test("fade: opacity 0 stays gone, under the mouse and in a fight too", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "never", alpha = 0.5, mouseover = true, delay = 0, opacity = 0 }, { a })
    settle(F)
    T.eq(a:GetAlpha(), 0, "at rest")
    a.__over = true
    settle(F)
    T.eq(a:GetAlpha(), 0, "under the mouse")
    a.__over = false
    stub.EnterCombat()
    settle(F)
    T.eq(a:GetAlpha(), 0, "in a fight")
    stub.LeaveCombat()
end)

T.test("fade: unlocked or with its page open an area shows at its opacity; changing it doesn't peek", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = true, delay = 0, opacity = 0.6 }, { a }, { page = "Test.page" })
    settle(F)
    T.eq(a:GetAlpha(), 0)
    DUI.Movers.unlocked = true
    settle(F)
    T.near(a:GetAlpha(), 0.6, 1e-6, "unlocked")
    DUI.Movers.unlocked = false
    local P = DUI.OptionsPanel
    local shown, current = P.IsShown, P.Current
    P.IsShown = function() return true end
    P.Current = function() return "Test.page" end
    settle(F)
    T.near(a:GetAlpha(), 0.6, 1e-6, "its page open")
    DUI:Set("general", "tf.opacity", 0.3)
    settle(F)
    T.near(a:GetAlpha(), 0.3, 1e-6, "the new opacity at once, not the faded look")
    P.IsShown, P.Current = shown, current
end)

T.test("fade: 'Fade only in the open world' shows everything in dungeons, raids, battlegrounds and arenas, live", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    T.eq(DUI.DB.General().fadeOpenWorldOnly, false, "off out of the box")
    local a, c = frame(), frame()
    area(DUI, "tf", { mode = "ooc", alpha = 0.2, mouseover = true, delay = 2, opacity = 0.9 }, { a })
    -- An area faded by its own cap (chat's idle fade), at "never".
    area(DUI, "tc", { mode = "never" }, { c }, { cap = function() return 0 end })
    stub.Advance(3)
    settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "faded in the open world")
    T.eq(c:GetAlpha(), 0, "capped")
    -- Off: a dungeon changes nothing.
    stub.SetInstance("party")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "switch off: still faded in a dungeon")
    -- On, inside: shown at its opacity at once, with no peek at the faded look.
    DUI:Set("general", "fadeOpenWorldOnly", true)
    settle(F)
    T.near(a:GetAlpha(), 0.9, 1e-6, "switch on in a dungeon: shown at its opacity")
    T.eq(c:GetAlpha(), 1, "a capped area too")
    stub.Advance(10)
    settle(F)
    T.near(a:GetAlpha(), 0.9, 1e-6, "and it stays shown")
    -- Back outside: the delay first, then it fades again.
    stub.SetInstance(nil)
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    settle(F)
    T.near(a:GetAlpha(), 0.9, 1e-6, "just out: the delay first")
    stub.Advance(3)
    settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "faded again in the open world")
    -- Every kind of instance counts, but a scenario doesn't.
    for _, kind in ipairs({ "raid", "pvp", "arena" }) do
        stub.SetInstance(kind)
        stub.FireEvent("PLAYER_ENTERING_WORLD")
        settle(F)
        T.near(a:GetAlpha(), 0.9, 1e-6, kind)
        stub.SetInstance(nil)
        stub.FireEvent("PLAYER_ENTERING_WORLD")
        stub.Advance(3)
        settle(F)
        T.near(a:GetAlpha(), 0.2, 1e-6, kind .. ", left")
    end
    stub.SetInstance("scenario")
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "a scenario is the open world")
    -- Turned off while inside: fading again as set.
    stub.SetInstance("raid")
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    settle(F)
    T.near(a:GetAlpha(), 0.9, 1e-6)
    DUI:Set("general", "fadeOpenWorldOnly", false)
    stub.Advance(3)
    settle(F)
    T.near(a:GetAlpha(), 0.2, 1e-6, "switched off inside: fades as set")
end)

T.test("fade: the open-world switch at login inside a dungeon, and in a battleground fight (alpha only)", function()
    local DUI = stub.Load({ before = function() stub.SetInstance("party") end })
    local F = DUI.Fade
    local a = frame()
    DUI.DB.General().fadeOpenWorldOnly = true
    area(DUI, "tf", { mode = "always", alpha = 0, mouseover = false, delay = 0 }, { a })
    settle(F)
    T.eq(a:GetAlpha(), 1, "logged in inside a dungeon: shown")
    stub.SetInstance(nil)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    settle(F)
    T.eq(a:GetAlpha(), 0, "outside: faded")
    stub.EnterCombat()
    stub.SetInstance("pvp")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    settle(F)
    T.eq(a:GetAlpha(), 1, "shown in a battleground fight")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- The Fade page (General > Fade): every area's rows, sharing their settings
-- ---------------------------------------------------------------------

local ALL = { module = true, actionbars = true, buffs = true, chat = true, infopanel = true, quests = true,
              before = function()
                  _G.UnitXP = function() return 300 end
                  _G.UnitXPMax = function() return 1200 end
              end }

local function hubCard(DUI, label)
    for _, g in ipairs(DUI.Options.GetPage("fade").groups) do
        if g.label == label then return g end
    end
end

-- The card's row with this label (the copies have no key).
local function hubRow(card, label)
    for _, item in ipairs(card.items) do
        if item.label == label then return item end
    end
end

local function pick(DUI, card, label)
    local picker = card.items[1]
    for id, text in pairs((picker.choices())) do
        if text == label then DUI.Options.Set(DUI.Options.GetPage("fade"), picker, id) return end
    end
    error("no area " .. label)
end

T.test("fade page: a card per module, each listing its areas by name", function()
    local DUI = stub.Load(ALL)
    local page = DUI.Options.GetPage("fade")
    T.eq(page.groups[1].label, "Everywhere")
    local names = {}
    for _, g in ipairs(page.groups) do names[#names + 1] = g.label end
    for _, want in ipairs({ "Unit Frames", "Action Bars", "Buffs & Debuffs", "Chat", "Info Panel", "Quest Tracker" }) do
        T.truthy(hubCard(DUI, want), "a card for " .. want .. " (have " .. table.concat(names, ", ") .. ")")
    end
    local function listed(card, name)
        for _, text in pairs((card.items[1].choices())) do if text == name then return true end end
    end
    DUI:Set("ActionBars", "bagBar", "shown"); DUI:Set("ActionBars", "microMenu", "shown")
    local uf, ab, ip = hubCard(DUI, "Unit Frames"), hubCard(DUI, "Action Bars"), hubCard(DUI, "Info Panel")
    for _, n in ipairs({ "Player", "Target", "Pet", "Focus", "Party", "Raid" }) do T.truthy(listed(uf, n), n) end
    for _, n in ipairs({ "Action Bar 1", "Bag bar", "Micro menu", "Totem Timers" }) do T.truthy(listed(ab, n), n) end
    for _, n in ipairs({ "Info panel", "Threat meter" }) do T.truthy(listed(ip, n), n) end
    T.truthy(listed(hubCard(DUI, "Buffs & Debuffs"), "Debuffs"))
    T.truthy(DUI.Options.IsHidden(page, hubCard(DUI, "Chat").items[1]), "one area: no picker")
    DUI.questsOwnTracker = true   -- the fake game has no tracker of its own to switch off
    T.falsy(listed(ip, "Quest tracker"), "the game's tracker is left out while ours runs")
    T.eq(ab.items[1].get(), "ActionBars:bagBarFade.", "the first area in use, until the player picks")
    DUI:Set("ActionBars", "bagBar", "hidden"); DUI:Set("ActionBars", "microMenu", "hidden")
    T.falsy(listed(ab, "Bag bar"), "a hidden bag bar is left out")
    T.eq(ab.items[1].get(), "ActionBars:bars.main.fade.", "so Action Bar 1 comes first")
    for _, g in ipairs(page.groups) do T.eq(#DUI.Options.Validate(g.items, page.defaults), 0, g.label .. " rows are valid") end
end)

T.test("fade page: a change on either page is the same setting", function()
    local DUI = stub.Load(ALL)
    local page, O = DUI.Options.GetPage("fade"), DUI.Options
    local uf = hubCard(DUI, "Unit Frames")
    pick(DUI, uf, "Target")
    O.Set(page, hubRow(uf, "Visible"), "ooc")
    T.eq(DUI:Get("UnitFrames", "target.fade.mode"), "ooc", "the Fade page writes the frame's own setting")
    T.eq(DUI:Get("UnitFrames", "player.fade.mode"), "never", "only the picked one")
    DUI:Set("UnitFrames", "target.fade.alpha", 0.3)
    T.near(O.Get(page, hubRow(uf, "Faded opacity")), 0.3, 1e-6, "and reads it back")
    T.falsy(O.IsDefault(page, hubRow(uf, "Faded opacity")), "with the reset arrow")
    O.ResetItem(page, hubRow(uf, "Faded opacity"))
    T.eq(DUI:Get("UnitFrames", "target.fade.alpha"), 0, "reset to the frame's default")
    local chat = hubCard(DUI, "Chat")
    O.Set(page, hubRow(chat, "Chat hides"), "always")
    T.eq(DUI:Get("Chat", "hides"), "always", "the chat's own extra rows come along")
    T.truthy(O.IsHidden(page, hubRow(chat, "Visible")), "its Visible pick hidden: Chat hides does it")
    T.falsy(O.IsHidden(page, hubRow(chat, "Opacity")), "Opacity stays")
    T.falsy(O.IsHidden(page, hubRow(uf, "Visible")), "other areas keep theirs")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("fade page: rows follow the pick, dim like their own page, and only the picked area's extras show", function()
    local DUI = stub.Load(ALL)
    local page, O = DUI.Options.GetPage("fade"), DUI.Options
    local uf = hubCard(DUI, "Unit Frames")
    local full = {}
    for _, item in ipairs(uf.items) do if item.label == "Only at full health" then full[#full + 1] = item end end
    T.eq(#full, 2, "the player's and the pet's")
    pick(DUI, uf, "Player")
    T.falsy(O.IsHidden(page, full[1])); T.truthy(O.IsHidden(page, full[2]))
    pick(DUI, uf, "Target")
    T.truthy(O.IsHidden(page, full[1])); T.truthy(O.IsHidden(page, full[2]))
    pick(DUI, uf, "Raid")
    DUI:Set("UnitFrames", "raid.enabled", false)
    T.truthy(O.IsDisabled(page, hubRow(uf, "Opacity")), "raid frames off: dimmed, as on the Raid page")
    DUI:Set("UnitFrames", "raid.enabled", true)
    T.falsy(O.IsDisabled(page, hubRow(uf, "Opacity")))
    T.truthy(O.IsDisabled(page, hubRow(uf, "Delay")), "Never: the fade rows dim")
end)

T.test("fade page: search finds each row once, on its own page", function()
    local DUI = stub.Load(ALL)
    for _, hit in ipairs(DUI.Options.Search("faded opacity")) do
        T.truthy(hit.page.id ~= "fade", "no copies in the results")
    end
    T.truthy(#DUI.Options.Search("fade in on login") == 1, "the page's own switches still found")
end)

T.test("fade page: Reset page puts every area's fade back", function()
    local DUI = stub.Load(ALL)
    DUI:Set("UnitFrames", "player.fade.mode", "always")
    DUI:Set("ActionBars", "bagBarFade.delay", 9)
    T.eq(DUI:Get("ActionBars", "bagBarFade.delay"), 9)
    DUI:Set("Chat", "fade.opacity", 0.5)
    DUI:Set("general", "fadeIn", false)
    DUI.Options.ResetPage(DUI.Options.GetPage("fade"))
    T.eq(DUI:Get("UnitFrames", "player.fade.mode"), "never")
    T.eq(DUI:Get("ActionBars", "bagBarFade.delay"), DUI:GetModule("ActionBars").defaults.bagBarFade.delay)
    T.eq(DUI:Get("Chat", "fade.opacity"), 1)
    T.eq(DUI:Get("general", "fadeIn"), true)
end)

T.test("fade page: the picked areas show at their opacity while it's open, and the window draws it", function()
    local DUI = stub.Load(ALL)
    local F, P = DUI.Fade, DUI.OptionsPanel
    DUI:Set("UnitFrames", "player.fade.mode", "always")
    DUI:Set("UnitFrames", "target.fade.mode", "always")
    stub.Advance(10); settle(F); stub.Advance(10); settle(F)
    T.eq(select(2, F.State("UnitFrames.player")), 0, "faded with the window shut")
    P.Show("fade")
    settle(F)
    T.eq(select(2, F.State("UnitFrames.player")), 1, "the picked one shows")
    T.eq(select(2, F.State("UnitFrames.target")), 0, "the others keep fading")
    local uf = hubCard(DUI, "Unit Frames")
    pick(DUI, uf, "Target")
    settle(F)
    T.eq(select(2, F.State("UnitFrames.target")), 1, "a new pick shows")
    T.truthy(#P.PageFrame().cards >= 7, "every card drawn")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("fade hush: the hushed areas ease to 0 slowly, the others stay; the mouse, a fight and unlock show them", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a, b = frame(), frame()
    area(DUI, "hushA", { mode = "never", opacity = 0.8 }, { a })
    area(DUI, "other", { mode = "never" }, { b })
    settle(F)
    F.Hush("camp", { "hush" })
    F.Step()
    play(F, F.OUT)
    T.truthy(a:GetAlpha() > 0.05, "slower than a normal fade out: still on its way")
    play(F, F.HUSH_OUT)
    T.eq(a:GetAlpha(), 0, "hushed: gone")
    T.eq(b:GetAlpha(), 1, "an area outside the hush stays")
    a.__over = true
    settle(F)
    T.near(a:GetAlpha(), 0.8, 1e-6, "under the mouse: back at its opacity")
    a.__over = false
    F.Step()
    play(F, F.HUSH_OUT)
    T.eq(a:GetAlpha(), 0, "the mouse gone: hushed again")
    stub.EnterCombat()
    settle(F)
    T.near(a:GetAlpha(), 0.8, 1e-6, "a fight wins over the hush")
    stub.LeaveCombat()
    DUI.Movers.unlocked = true
    settle(F)
    T.near(a:GetAlpha(), 0.8, 1e-6, "unlocked wins too")
    DUI.Movers.unlocked = false
    F.Step()
    play(F, F.HUSH_OUT)
    T.eq(a:GetAlpha(), 0)
    F.Unhush("camp")
    settle(F)
    T.near(a:GetAlpha(), 0.8, 1e-6, "unhushed: back at the normal speed")
    T.falsy(F.Hushed(), "no hush left")
end)

T.test("fade hush: an area that fades on its own keeps its rules once unhushed; a snap is instant", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local a = frame()
    area(DUI, "hushB", { mode = "ooc", alpha = 0.3, mouseover = true, delay = 0 }, { a })
    stub.Advance(1)
    settle(F)
    T.eq(a:GetAlpha(), 0.3)
    F.Hush("camp", { "hush" })
    T.truthy(F.Hushed(), "a hush is on")
    F.Step()
    play(F, F.HUSH_OUT)
    T.eq(a:GetAlpha(), 0, "below its own faded alpha while hushed")
    F.Unhush("camp", true)
    T.eq(a:GetAlpha(), 0.3, "a snap: at its own goal at once")
    F.Unhush("nobody")   -- an unknown name is harmless
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A shown, outlined frame at a spot (the fake game has no layout).
local function placed(DUI, l, b, w, h)
    local f = frame()
    f:SetSize(w, h)
    function f:GetLeft() return l end
    function f:GetBottom() return b end
    DUI.Style.Shell(f)
    return f
end

local function login(initial, F)
    stub.FireEvent("PLAYER_ENTERING_WORLD", initial, not initial)
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    steady(F)
end

local function traced(F)
    local n = 0
    for _, ov in ipairs(F.revealOverlays) do if ov:IsShown() then n = n + 1 end end
    return n
end

T.test("fade: a real login traces the frames' outlines one after another, then they settle and nothing keeps running", function()
    local DUI = stub.Load({ intro = true })
    local F, M = DUI.Fade, DUI.Motion
    local big = placed(DUI, 100, 100, 300, 60)
    local small = placed(DUI, 500, 100, 200, 40)
    placed(DUI, 120, 110, 100, 20)          -- inside big, so its outline is big's
    placed(DUI, 700, 100, 30, 30)           -- a button, too small to trace
    local hidden = placed(DUI, 800, 100, 200, 40)
    area(DUI, "gone", { mode = "always", alpha = 0, mouseover = true, delay = 3 }, { hidden },
         { cap = function() return 0 end })   -- kept away (a set fade still comes up for the reveal)
    area(DUI, "here", { mode = "never" }, { big, small })
    login(true, DUI.Fade)
    local picks = F.RevealPicks()
    T.eq(#picks, 2, "the two outer, big enough, not faded away")
    T.eq(picks[1].frame, small, "nearest the middle of the screen first")
    T.truthy(picks[1].delay < picks[2].delay, "and the farther one later (the ripple)")
    T.eq(traced(F), 2, "both traced (the stagger's timers ran)")
    local ov = F.revealOverlays[1]
    T.eq(ov:GetParent(), UIParent, "ours, on UIParent: no anchor to the frame")
    T.falsy(ov:IsMouseEnabled(), "clicks go through")
    local d = M.Driver()
    -- 4 s, since the setup guide opens on a new character and plays its sunrise (~2.7 s) too.
    for _ = 1, 240 do stub.RunOnUpdate(d, 1 / 60) end
    T.eq(traced(F), 0, "settled: the traces are gone")
    T.isnil(d.__scripts.OnUpdate, "no driver left running")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("fade: the reveal skips a shown frame kept see-through (the Cooldown Manager's buff slots with no buff up)", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local seen = placed(DUI, 100, 100, 300, 60)
    local slot = placed(DUI, 500, 100, 200, 40)
    slot:SetAlpha(0)                         -- the game keeps an idle slot shown at alpha 0
    local holder = frame()
    local inner = placed(DUI, 800, 100, 200, 40)
    inner:SetParent(holder)
    holder:SetAlpha(0)                       -- or its parent
    login(true, F)
    local picks = F.RevealPicks()
    T.eq(#picks, 1, "only the frame you can see")
    T.eq(picks[1].frame, seen, "the seen one")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("fade: a /reload reveals too, a zone change doesn't; none in a fight or with motion off", function()
    local DUI = stub.Load({ intro = true })
    placed(DUI, 100, 100, 300, 60)
    login(false, DUI.Fade)
    T.eq(traced(DUI.Fade), 1, "/reload: traced like a login")
    for _ = 1, 240 do stub.RunOnUpdate(DUI.Motion.Driver(), 1 / 60) end
    T.eq(traced(DUI.Fade), 0, "settled")
    login(false, DUI.Fade)
    T.eq(traced(DUI.Fade), 0, "a zone change: nothing")

    DUI = stub.Load({ intro = true })
    placed(DUI, 100, 100, 300, 60)
    stub.combat = true
    login(true, DUI.Fade)
    stub.combat = false
    T.eq(traced(DUI.Fade), 0, "a fight: fight info first")

    DUI = stub.Load({ intro = true })
    DUI.DB.General().motion = false
    placed(DUI, 100, 100, 300, 60)
    login(true, DUI.Fade)
    T.eq(traced(DUI.Fade), 0, "motion off")
end)

T.test("fade: the login ripples out from the middle: a far area starts its fade-in later", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local near = placed(DUI, w / 2 - 100, h / 2 - 20, 200, 40)
    local far = placed(DUI, 0, 0, 200, 40)
    area(DUI, "near", { mode = "never" }, { near })
    area(DUI, "far", { mode = "never" }, { far })
    T.truthy(F.RippleDelay(near) < 0.05, "the middle: at once")
    T.truthy(F.RippleDelay(far) > F.REVEAL_SPREAD / 2, "a corner: late")
    T.isnil(F.RippleDelay(frame()), "a frame not laid out: no delay to give")
    login(true, F)
    play(F, F.INTRO / 3)
    T.truthy(near:GetAlpha() > far:GetAlpha(), "the middle comes in first (" .. near:GetAlpha() .. " > " .. far:GetAlpha() .. ")")
    play(F, F.INTRO + F.REVEAL_SPREAD)
    T.eq(near:GetAlpha(), 1)
    T.eq(far:GetAlpha(), 1, "both end shown")

    DUI = stub.Load({ intro = true })
    F = DUI.Fade
    stub.combat = true
    far = placed(DUI, 0, 0, 200, 40)
    near = placed(DUI, w / 2 - 100, h / 2 - 20, 200, 40)
    area(DUI, "near", { mode = "never" }, { near })
    area(DUI, "far", { mode = "never" }, { far })
    login(true, F)
    play(F, F.INTRO / 3)
    stub.combat = false
    T.eq(near:GetAlpha(), far:GetAlpha(), "a fight: no ripple, everything at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("fade: after the traces a warm light sweeps across each traced frame, then nothing keeps running", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    placed(DUI, 100, 100, 300, 60)
    placed(DUI, 900, 100, 200, 40)
    login(true, F)
    local lit = 0
    for i = 1, 2 do
        local sh = F.revealOverlays[i].shine
        if sh and sh.light:IsShown() then lit = lit + 1 end
        T.eq(sh and sh:GetParent(), UIParent, "ours, on UIParent")
        T.falsy(sh:IsMouseEnabled(), "clicks go through")
    end
    T.eq(lit, 2, "a light on each")
    for _ = 1, 240 do stub.RunOnUpdate(DUI.Motion.Driver(), 1 / 60) end
    T.falsy(F.revealOverlays[1].shine.light:IsShown(), "gone once across")
    T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, "no driver left running")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("fade: the reveal calls the modules in (LoginReveal) on a login and a /reload, not a zone change or in a fight", function()
    local DUI = stub.Load({ intro = true })
    local n = 0
    DUI.On("LoginReveal", function() n = n + 1 end)
    login(false, DUI.Fade)
    T.eq(n, 1, "/reload")
    login(false, DUI.Fade)
    T.eq(n, 1, "a zone change: no")

    DUI = stub.Load({ intro = true })
    n = 0
    DUI.On("LoginReveal", function() n = n + 1 end)
    stub.combat = true
    login(true, DUI.Fade)
    stub.combat = false
    T.eq(n, 0, "a fight: no")
end)

T.test("fade: a frame with no border of its own is outlined when a module asks (the chat with its background off)", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local bare = frame()
    bare:SetSize(300, 120)
    function bare:GetLeft() return 20 end
    function bare:GetBottom() return 20 end
    local wanted = true
    F.RevealAlso(function() if wanted then return bare, 6 end end)
    F.RevealAlso(function() error("a broken source") end)
    login(true, F)
    local picks = F.RevealPicks()
    T.eq(#picks, 1, "traced, no shell needed")
    T.eq(picks[1].frame, bare)
    T.eq(picks[1].l, 14, "padded out")
    T.eq(picks[1].w, 312)
    T.eq(traced(F), 1)
    wanted = false
    T.eq(#F.RevealPicks(), 0, "the source says none: none")
end)

T.test("fade: a login and a /reload say welcome with your name, then it drifts away; not before the setup guide", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    DUI.DB.Character().install = "done"
    login(true, F)
    local wl = F.welcome
    T.truthy(wl and wl:IsShown(), "shown")
    T.truthy(wl.text:GetText():find(DUI.UnitName("player", "player"), 1, true), "with your name: " .. tostring(wl.text:GetText()))
    T.falsy(wl:IsMouseEnabled(), "clicks go through")
    local d = DUI.Motion.Driver()
    for _ = 1, 60 do stub.RunOnUpdate(d, 1 / 60) end
    T.eq(wl:GetAlpha(), 1, "in")
    stub.RunTimers()
    for _ = 1, 60 do stub.RunOnUpdate(d, 1 / 60) end
    T.falsy(wl:IsShown(), "then gone")

    DUI = stub.Load({ intro = true })
    DUI.DB.Character().install = "done"
    login(false, DUI.Fade)
    T.truthy(DUI.Fade.welcome and DUI.Fade.welcome:IsShown(), "/reload: welcome too")

    DUI = stub.Load({ intro = true })
    DUI.DB.Character().install = nil
    login(true, DUI.Fade)
    T.falsy(DUI.Fade.welcome and DUI.Fade.welcome:IsShown(), "a new character: the setup guide's sunrise instead")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("fade: an area set to fade comes up for the login reveal, then fades its usual way", function()
    local DUI = stub.Load({ intro = true })
    local F = DUI.Fade
    local f = placed(DUI, 100, 100, 300, 60)
    area(DUI, "faded", { mode = "always", alpha = 0.2, mouseover = true, delay = 3 }, { f })
    login(true, F)
    T.eq(#F.RevealPicks(), 1, "traced like a shown frame")
    play(F, F.INTRO + F.REVEAL_SPREAD)
    T.eq(f:GetAlpha(), 1, "shown while its outline traces")
    stub.Advance(F.REVEAL_SPREAD + 2 * F.REVEAL_TIME)
    F.Step()
    play(F, F.OUT)
    T.eq(f:GetAlpha(), 0.2, "then down to its faded look, no wait for the delay")

    DUI = stub.Load({ intro = true })
    F = DUI.Fade
    DUI.DB.General().motion = false
    f = placed(DUI, 100, 100, 300, 60)
    area(DUI, "faded", { mode = "always", alpha = 0.2, mouseover = true, delay = 3 }, { f })
    login(true, F)
    F.Step()
    T.eq(f:GetAlpha(), 0.2, "no reveal: starts faded")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A frame under the game's rule (Frame:SetIsFrameBuffer on warcraft.wiki.gg): the
-- buffer needs flattened layers or the frame can come out invisible.
local function counted(f)
    f.calls = {}
    function f:SetFlattensRenderLayers(on) self.flat = on; self.calls[#self.calls + 1] = "flat" end
    function f:SetIsFrameBuffer(on)
        if on then assert(self.flat, "a frame buffer without flattened layers draws nothing") end
        if not on then assert(self.flat, "flat comes off after the buffer") end
        self.buffer = on
        self.calls[#self.calls + 1] = "buffer"
    end
    return f
end

T.test("fade: a whole area fades as one picture while it can fade, never its layers one by one", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local f = counted(frame(false))
    area(DUI, "w1", { mode = "ooc", alpha = 0.4, delay = 0, mouseover = true }, { f }, { whole = true })
    settle(F)
    T.eq(f.buffer, true, "faded: one picture")
    T.eq(f.flat, true, "with its layers flattened")
    -- A fight brings it back and it stays ready, since it can't change in a fight.
    local g = counted(frame(false))
    area(DUI, "w2", { mode = "never" }, { g }, { whole = true })
    settle(F)
    T.falsy(g.buffer, "an area that never fades costs nothing")
    local h = counted(frame(false))
    area(DUI, "w3", { mode = "ooc", alpha = 0.4, delay = 0 }, { h })
    settle(F)
    T.falsy(h.buffer, "only areas that ask")
end)

T.test("fade: a frame's buffer only changes out of combat, and waits for the fight's end", function()
    local DUI = stub.Load()
    local F = DUI.Fade
    local f = counted(frame(false))
    stub.EnterCombat()
    F.Whole(f, "range", true)
    T.falsy(f.buffer, "not in a fight")
    stub.LeaveCombat()
    T.eq(f.buffer, true, "after it")
    F.Whole(f, "range", false)
    T.eq(f.buffer, false, "off again")
    T.eq(f.flat, false, "flat off last")
end)
