local stub = require("stub")

local function setMotion(on)
    DaylightUI.DB.General().motion = on
end

T.test("motion: speeds, and the switch defaults on", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    T.eq(M.FAST, 0.12); T.eq(M.NORMAL, 0.2); T.eq(M.SLOW, 0.4)
    T.eq(M.On(), true)
    setMotion(false)
    T.eq(M.On(), false)
end)

T.test("motion: off, every helper jumps to its end state", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    setMotion(false)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetAlpha(0)
    M.Fade(f, 0, 0.5, 0.2)
    T.eq(f:GetAlpha(), 0.5, "fade end")
    f:SetAlpha(0)
    M.Appear(f, 6)
    T.eq(f:GetAlpha(), 1, "appear end")
    local tex = f:CreateTexture()
    tex:Show()
    M.Flash(tex)
    T.eq(tex:IsShown(), false, "flash hidden")
    local got, done
    M.Tween("k", 0, 10, 1, function(v) got = v end, function() done = true end)
    T.eq(got, 10); T.eq(done, true)
end)

T.test("motion: an error in a tween's step or end reaches the error handler (BugSack sees it)", function()
    local DUI = stub.Load()
    setMotion(false)
    local before = #stub.errors
    DUI.Motion.Tween("broken", 0, 1, 1, function() error("step went wrong") end, function() error("done went wrong") end)
    T.eq(#stub.errors, before + 2, "both reported")
    T.truthy(tostring(stub.errors[before + 1]):find("step went wrong", 1, true))
    stub.errors = {}
end)

T.test("motion: Fade reuses one group per region and sets its end alpha", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local made = 0
    local real = f.CreateAnimationGroup
    f.CreateAnimationGroup = function(self) made = made + 1 return real(self) end
    local g1 = DUI.Motion.Fade(f, 0, 1, 0.2)
    T.eq(f:GetAlpha(), 1, "kept at its end")
    local g2 = DUI.Motion.Fade(f, 1, 0, 0.2, 0.1)
    T.eq(f:GetAlpha(), 0)
    T.eq(made, 1, "one group, reused")
    T.eq(g1, g2)
    T.eq(g2:IsPlaying(), true, "playing again")
end)

T.test("motion: Appear leaves alpha 1 and replays cleanly", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    DUI.Motion.Appear(f, 6)
    DUI.Motion.Appear(f, 6)
    T.eq(f:GetAlpha(), 1)
    T.eq(f.__duiMotion.appearFade:IsPlaying(), true)
end)

T.test("motion: a tween runs to its target and calls done once", function()
    local DUI = stub.Load()
    local driverFrame
    local last, done = nil, 0
    DUI.Motion.Tween("gold", 0, 100, 0.2, function(v) last = v end, function() done = done + 1 end)
    T.eq(last, 0)
    -- the driver is the only frame with an OnUpdate made by the kit
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then driverFrame = fr end
    end
    T.eq(driverFrame ~= nil, true, "driver exists")
    stub.RunOnUpdate(driverFrame, 0.1)
    T.eq(last > 0 and last < 100, true, "midway")
    stub.RunOnUpdate(driverFrame, 0.2)
    T.eq(last, 100); T.eq(done, 1)
    T.eq(driverFrame.__scripts.OnUpdate, nil, "driver idles")
end)

T.test("motion: a new tween on a key replaces the old; zero length ends at once", function()
    local DUI = stub.Load()
    local a, b, adone = nil, nil, false
    DUI.Motion.Tween("k", 0, 10, 1, function(v) a = v end, function() adone = true end)
    DUI.Motion.Tween("k", 5, 6, 1, function(v) b = v end)
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, 2) end
    end
    T.eq(a, 0, "old never advanced"); T.eq(adone, false)
    T.eq(b, 6)
    local z
    DUI.Motion.Tween("z", 3, 3, 1, function(v) z = v end)
    T.eq(z, 3)
end)

T.test("motion: an erroring step doesn't kill the driver", function()
    local DUI = stub.Load()
    local ok
    DUI.Motion.Tween("bad", 0, 1, 0.1, function() error("boom") end)
    DUI.Motion.Tween("good", 0, 1, 0.1, function(v) ok = v end)
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, 1) end
    end
    T.eq(ok, 1)
end)

-- Seen in game: "invalid key to 'next'" in the driver, when a finished tween
-- started new ones (the zone title's fade in after its fade out) mid-walk.
T.test("motion: a done that starts new tweens doesn't break the driver's walk", function()
    local DUI = stub.Load()
    local ends, chained = 0, 0
    for i = 1, 3 do
        DUI.Motion.Tween("first" .. i, 0, 1, 0.1, nil, function()
            ends = ends + 1
            for j = 1, 40 do
                DUI.Motion.Tween("next" .. i .. ":" .. j, 0, 1, 0.1, nil, function() chained = chained + 1 end)
            end
        end)
    end
    local d = DUI.Motion.Driver()
    T.noerror(function() stub.RunOnUpdate(d, 1) end)
    T.eq(ends, 3)
    T.eq(chained, 0, "new ones start next frame")
    stub.RunOnUpdate(d, 1)
    T.eq(chained, 120)
end)

-- Vanish: a fade out, then Hide (the fade's OnFinished stands in for time).
local function finish(f)
    local g = f.__duiMotion and f.__duiMotion.vanish
    local fn = g and g:GetScript("OnFinished")
    if fn then fn(g) end
end

-- What the client's Escape does: hide every shown special frame.
local function escape()
    local hid = false
    for _, n in ipairs(UISpecialFrames) do
        local fr = _G[n]
        if fr and fr:IsShown() then fr:Hide(); hid = true end
    end
    return hid
end

local function window(DUI, rise)
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    DUI.Motion.Window(f, rise)
    return f
end

T.test("motion: Vanish fades, then hides at full alpha", function()
    local DUI = stub.Load()
    local f = window(DUI, 6)
    f:Show()
    DUI.Motion.Vanish(f)
    T.eq(f:IsShown(), true, "still shown while fading")
    T.eq(DUI.Motion.Shown(f), false, "counts as closed")
    T.eq(f.__duiMotion.vanish:IsPlaying(), true)
    finish(f)
    T.eq(f:IsShown(), false, "hidden after the fade")
    T.eq(f:GetAlpha(), 1, "alpha back for the next open")
end)

T.test("motion: reopening mid-fade cancels it at full alpha", function()
    local DUI = stub.Load()
    local f = window(DUI)
    f:Show()
    DUI.Motion.Vanish(f)
    f:Show()
    T.eq(f.__duiMotion.vanish:IsPlaying(), false, "fade stopped")
    T.eq(f:GetAlpha(), 1)
    T.eq(DUI.Motion.Shown(f), true)
    finish(f)   -- a late finish must not hide it
    T.eq(f:IsShown(), true)
    -- SetShown(true) cancels too (the bags follow the game that way).
    DUI.Motion.Vanish(f)
    f:SetShown(true)
    T.eq(DUI.Motion.Shown(f), true)
    T.eq(escape(), true, "Escape works again after the reopen")
    T.eq(f.__duiMotion.vanish:IsPlaying(), true)
end)

T.test("motion: Vanish with motion off hides at once", function()
    local DUI = stub.Load()
    setMotion(false)
    local f = window(DUI, 6)
    f:Show()
    DUI.Motion.Vanish(f)
    T.eq(f:IsShown(), false)
    f:Show()
    T.eq(escape(), true)
    T.eq(f:IsShown(), false, "Escape hides at once too")
end)

T.test("motion: Escape fades the window through its stand-in", function()
    local DUI = stub.Load()
    local f = window(DUI, 6)
    T.eq(escape(), false, "closed window: Escape not taken")
    f:Show()
    T.eq(escape(), true, "Escape taken")
    T.eq(f:IsShown(), true, "fading, not gone")
    T.eq(f.__duiMotion.vanish:IsPlaying(), true)
    T.eq(escape(), false, "a second Escape is free for the game menu")
    finish(f)
    T.eq(f:IsShown(), false)
    -- A close button's fade frees Escape as well.
    f:Show()
    DUI.Motion.Vanish(f)
    T.eq(escape(), false)
end)

T.test("motion: a plain Hide mid-fade leaves a clean window", function()
    local DUI = stub.Load()
    local f = window(DUI)
    f:Show()
    DUI.Motion.Vanish(f)
    f:Hide()
    T.eq(f.__duiMotion.vanish:IsPlaying(), false)
    f:Show()
    T.eq(DUI.Motion.Shown(f), true)
    T.eq(f:GetAlpha(), 1)
end)

-- Every OnUpdate the kit made, dt seconds on.
local function tickAll(dt)
    for _, fr in ipairs(stub.frames or {}) do
        if fr.__scripts and fr.__scripts.OnUpdate then stub.RunOnUpdate(fr, dt) end
    end
end

T.test("motion: FadeIn steps a game window's alpha up to what it was, out of combat only", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetAlpha(0.5)
    stub.combat = true
    M.FadeIn(f)
    T.eq(M.FadingIn(f), false, "nothing in combat")
    T.eq(f:GetAlpha(), 0.5)
    stub.combat = false
    M.FadeIn(f)
    T.eq(M.FadingIn(f), true)
    T.eq(f:GetAlpha(), 0, "starts clear")
    tickAll(0.1)
    T.truthy(f:GetAlpha() > 0 and f:GetAlpha() < 0.5, "midway")
    tickAll(1)
    T.eq(f:GetAlpha(), 0.5, "ends at its own alpha")
    T.eq(M.FadingIn(f), false)
end)

-- An alpha animation on a game window loses what the window does to its
-- own parts while it plays (the world map's picture stayed hidden, the game
-- menu's button art came back), so FadeIn never makes one.
T.test("motion: FadeIn plays no animation on the game's window", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local made = 0
    local real = f.CreateAnimationGroup
    f.CreateAnimationGroup = function(...) made = made + 1; return real(...) end
    DUI.Motion.FadeIn(f)
    tickAll(1)
    T.eq(made, 0)
end)

T.test("motion: FadeIn gives way when something else sets the window's alpha", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local f = CreateFrame("Frame", nil, UIParent)
    M.FadeIn(f)
    tickAll(0.05)
    f:SetAlpha(0.8)                 -- the game's own fade (the map, moving)
    tickAll(0.05)
    T.eq(f:GetAlpha(), 0.8, "theirs wins")
    T.eq(M.FadingIn(f), false)
    tickAll(1)
    T.eq(f:GetAlpha(), 0.8, "and stays")
end)

T.test("motion: FadeIn started just before a fight snaps to its alpha as the fight starts", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetAlpha(0.7)
    M.FadeIn(f)
    tickAll(0.05)
    T.truthy(f:GetAlpha() < 0.7, "fading")
    stub.combat = true
    local sets, real = 0, f.SetAlpha
    tickAll(0.05)
    T.eq(f:GetAlpha(), 0.7, "at its own alpha at once")
    T.eq(M.FadingIn(f), false, "and stopped")
    f.SetAlpha = function(...) sets = sets + 1; return real(...) end
    tickAll(1)
    T.eq(sets, 0, "no more steps in the fight")
    stub.combat = false
end)

T.test("motion: FadeIn closed or reopened mid-fade keeps the window's own alpha", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetAlpha(0.6)
    M.FadeIn(f)
    tickAll(0.05)
    f:Hide()
    T.eq(f:GetAlpha(), 0.6, "closed: its alpha back")
    T.eq(M.FadingIn(f), false)
    tickAll(1)
    T.eq(f:GetAlpha(), 0.6, "the old fade stays stopped")
    f:Show()
    M.FadeIn(f)
    tickAll(0.05)
    M.FadeIn(f)                     -- again before it ended
    tickAll(1)
    T.eq(f:GetAlpha(), 0.6, "reopened: still its own")
end)

T.test("motion: Bump scales without touching alpha; off does nothing", function()
    local DUI = stub.Load()
    local tex = CreateFrame("Frame", nil, UIParent):CreateTexture()
    tex:SetAlpha(0.7)
    DUI.Motion.Bump(tex, 1.15, DUI.Motion.FAST)
    T.eq(tex.__duiBump:IsPlaying(), true)
    T.eq(tex:GetAlpha(), 0.7)
    local other = CreateFrame("Frame", nil, UIParent):CreateTexture()
    setMotion(false)
    DUI.Motion.Bump(other)
    T.isnil(other.__duiBump)
end)

-- Ghost: a game window that just closed, as our own fading copy where it was.
local function gameWindow()
    local f = CreateFrame("Frame", "TestGameWindow", UIParent)
    f.GetRect = function() return 100, 200, 300, 400 end
    f:SetScale(0.5)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(7)
    return f
end

T.test("motion: Ghost copies a closed window's spot, scaled, and fades it out", function()
    local DUI = stub.Load()
    local f = gameWindow()
    f:Show()
    f:Hide()
    local dressed = 0
    local g
    local real = CreateFrame
    _G.CreateFrame = function(...) local fr = real(...); g = g or fr; return fr end
    DUI.Motion.Ghost(f, function() dressed = dressed + 1 end)
    _G.CreateFrame = real
    T.truthy(g, "a ghost")
    T.eq(dressed, 1, "dressed once")
    T.truthy(g:IsShown())
    T.eq(g:GetWidth(), 150, "the window's size at its scale")
    T.eq(g:GetHeight(), 200)
    local p, rel, rp, x, y = g:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, UIParent); T.eq(x, 50); T.eq(y, 100)
    T.eq(g:GetFrameStrata(), "HIGH")
    T.eq(g:GetFrameLevel(), 7)
    T.truthy(g.fade:IsPlaying())
    g.fade:GetScript("OnFinished")(g.fade)
    T.falsy(g:IsShown(), "gone after the fade")
    -- Closed again: the same ghost, not a new one or a second dressing.
    f:Show()
    f:Hide()
    DUI.Motion.Ghost(f, function() dressed = dressed + 1 end)
    T.eq(dressed, 1)
    T.truthy(g:IsShown())
    -- Opened again mid-fade: the ghost goes at once.
    f:Show()
    T.falsy(g:IsShown())
    T.falsy(g.fade:IsPlaying())
end)

T.test("motion: no Ghost for a window still shown (UI hidden around it), with motion off, or with no spot", function()
    local DUI = stub.Load()
    local made = 0
    local real = CreateFrame
    local f = gameWindow()
    _G.CreateFrame = function(...) made = made + 1; return real(...) end
    f:Show()
    DUI.Motion.Ghost(f)
    T.eq(made, 0, "still shown")
    f:Hide()
    setMotion(false)
    DUI.Motion.Ghost(f)
    T.eq(made, 0, "motion off")
    setMotion(true)
    f.GetRect = function() return nil end
    DUI.Motion.Ghost(f)
    T.eq(made, 0, "no spot")
    _G.CreateFrame = real
end)

-- The loot window fades itself out, then hides at alpha 0: a ghost would put
-- it back at full for a moment (a flash as it goes).
T.test("motion: no Ghost for a window that already faded itself out", function()
    local DUI = stub.Load()
    local made = 0
    local real = CreateFrame
    local f = gameWindow()
    f:Show()
    f:SetAlpha(0)
    f:Hide()
    _G.CreateFrame = function(...) made = made + 1; return real(...) end
    DUI.Motion.Ghost(f)
    _G.CreateFrame = real
    T.eq(made, 0, "already faded")
end)

T.test("motion: a Ghost's border (the frame dress returns) fades faster than its background", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    T.truthy(M.GHOST_EDGE < M.CLOSE, "the border goes first")
    local f = gameWindow()
    f:Show()
    f:Hide()
    local edge, tex
    M.Ghost(f, function(g)
        edge = CreateFrame("Frame", nil, g)
        tex = edge:CreateTexture()
        return edge
    end)
    T.truthy(edge.__duiMotion and edge.__duiMotion.ghostEdge:IsPlaying(), "the border frame fades on its own")
    T.falsy(tex.__duiMotion, "never a texture's own fade (it lost the texture's tint in game)")
    edge:SetAlpha(0)   -- where its fade leaves it
    -- Closed again: the border starts from full, not where it was left.
    f:Show()
    f:Hide()
    M.Ghost(f)
    T.eq(edge:GetAlpha(), 1)
    T.truthy(edge.__duiMotion.ghostEdge:IsPlaying())
end)

-- Slider: a 0..1 slide with its own driver frame, shown only while it moves.
T.test("motion: a slider eases to its goal, then calls done once", function()
    local DUI = stub.Load()
    local seen, done = {}, 0
    local sl = DUI.Motion.Slider(function(s) seen[#seen + 1] = s.p end,
        { p = 0, dur = 0.2, done = function() done = done + 1 end })
    T.eq(sl.p, 0); T.eq(sl.goal, 0)
    T.falsy(sl.driver:IsShown(), "idle until it moves")
    sl:To(1)
    T.truthy(sl.driver:IsShown())
    T.truthy(sl:Moving())
    stub.RunOnUpdate(sl.driver, 0.1)
    T.near(sl.p, 0.5, 1e-6, "eased in and out: half way at half time")
    stub.RunOnUpdate(sl.driver, 1)
    T.eq(sl.p, 1); T.falsy(sl:Moving())
    T.falsy(sl.driver:IsShown(), "stops once there")
    T.eq(done, 1)
    T.eq(seen[#seen], 1, "placed at the end")
    sl:To(1)
    T.falsy(sl.driver:IsShown(), "already there: nothing to do")
    T.eq(done, 1)
end)

T.test("motion: a slider turns round from where it is", function()
    local DUI = stub.Load()
    local sl = DUI.Motion.Slider(nil, { p = 1, dur = 0.2 })
    sl:To(0)
    stub.RunOnUpdate(sl.driver, 0.1)
    local mid = sl.p
    sl:To(1)
    T.eq(sl.p, mid, "no jump on turning round")
    stub.RunOnUpdate(sl.driver, 0.05)
    T.truthy(sl.p > mid and sl.p < 1)
    sl:To(1)
    T.truthy(sl:Moving(), "heading there already: carries on")
    stub.RunOnUpdate(sl.driver, 1)
    T.eq(sl.p, 1)
end)

T.test("motion: a slider jumps with motion off, and on Jump", function()
    local DUI = stub.Load()
    local done = 0
    local sl = DUI.Motion.Slider(nil, { dur = 0.2, done = function() done = done + 1 end })
    T.eq(sl.p, 1, "out by default")
    sl:To(0)
    sl:Jump(1)
    T.eq(sl.p, 1); T.eq(sl.goal, 1); T.falsy(sl:Moving())
    T.falsy(sl.driver:IsShown())
    T.eq(done, 0, "a jump isn't an arrival")
    setMotion(false)
    sl:To(0)
    T.eq(sl.p, 0, "motion off: straight there")
    T.falsy(sl.driver:IsShown())
    T.eq(done, 1)
end)

T.test("motion: SlideIn fades a frame in from an offset, replaying cleanly", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    DUI.Motion.SlideIn(f, 0, -12)
    local g = f.__duiMotion.slideIn
    T.truthy(g:IsPlaying())
    T.eq(g.dx, 0); T.eq(g.dy, -12)
    DUI.Motion.SlideIn(f, 0, 12)
    T.eq(f.__duiMotion.slideIn, g, "the same group, reused")
    T.eq(g.dy, 12, "the new direction")
    g:Stop()
    setMotion(false)
    DUI.Motion.SlideIn(f, 0, 12)
    T.falsy(g:IsPlaying(), "motion off: no slide")
end)

T.test("motion: Sweep runs a light left to right, fading at the ends, then hides it", function()
    local DUI = stub.Load()
    local over = CreateFrame("Frame", nil, UIParent)
    over:SetSize(100, 10)
    local tex = over:CreateTexture()
    tex:Hide()
    local done = 0
    DUI.Motion.Sweep(tex, over, { width = 20, dur = 0.5, done = function() done = done + 1 end })
    T.truthy(tex:IsShown(), "shown at the start")
    local d = DUI.Motion.Driver()
    stub.RunOnUpdate(d, 0.1)
    local _, _, _, x1 = tex:GetPoint(1)
    stub.RunOnUpdate(d, 0.1)
    local _, _, _, x2 = tex:GetPoint(1)
    T.truthy(x2 > x1, "it moves right")
    stub.RunOnUpdate(d, 0.4)
    T.falsy(tex:IsShown(), "hidden at the end")
    T.eq(done, 1)
    setMotion(false)
    DUI.Motion.Sweep(tex, over)
    T.falsy(tex:IsShown(), "motion off: nothing")
end)

T.test("motion: a row hover eases to the light's own faint alpha, never solid", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local f = CreateFrame("Frame", nil, UIParent)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetVertexColor(1, 1, 1, Parts.HI[4])
    t:Hide()
    Parts.Light(t, true)
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.truthy(t:IsShown(), "lit")
    T.eq(t:GetAlpha(), Parts.HI[4], "eases to 0.06, not 1")
    Parts.Light(t, false)
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.falsy(t:IsShown(), "out")
    Parts.Light(t, true, true)
    T.eq(t:GetAlpha(), Parts.HI[4], "instant too")
end)

T.test("motion: AlphaTo steps from where it is, shows on the way up, hides at the end on the way out", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    M.AlphaTo(f, 1, M.FAST, true)
    T.eq(f:IsShown(), true, "shown at once")
    T.eq(f:GetAlpha(), 0, "from clear")
    tickAll(0.05)
    T.truthy(f:GetAlpha() > 0 and f:GetAlpha() < 1, "midway")
    tickAll(1)
    T.eq(f:GetAlpha(), 1)
    M.AlphaTo(f, 0, M.FAST, true)
    T.eq(f:IsShown(), true, "still shown while it goes")
    tickAll(1)
    T.eq(f:IsShown(), false, "hidden once gone")
    T.eq(f:GetAlpha(), 0)
    -- Back up mid-fade: from where it is, never hidden.
    M.AlphaTo(f, 1, M.FAST, true)
    tickAll(1)
    M.AlphaTo(f, 0, M.FAST, true)
    tickAll(0.03)
    M.AlphaTo(f, 1, M.FAST, true)
    tickAll(1)
    T.eq(f:IsShown(), true); T.eq(f:GetAlpha(), 1)
    setMotion(false)
    M.AlphaTo(f, 0.35)
    T.eq(f:GetAlpha(), 0.35, "motion off: there at once")
end)

T.test("motion: AlphaTo with no time snaps at once, even while a fade to the same goal runs", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local f = CreateFrame("Frame", nil, UIParent)
    f:Show()
    f:SetAlpha(1)
    M.AlphaTo(f, 0, M.FAST, true)
    tickAll(0.03)
    T.truthy(f:GetAlpha() > 0, "fading out")
    -- A recycled plate's cast bar: gone this frame, not after the fade.
    M.AlphaTo(f, 0, 0, true)
    T.eq(f:GetAlpha(), 0, "snapped")
    T.eq(f:IsShown(), false, "hidden at once")
    tickAll(1)
    T.eq(f:IsShown(), false, "the old fade doesn't come back")
    -- And up: a snap to 1 while a fade to 1 runs.
    M.AlphaTo(f, 1, M.FAST)
    tickAll(0.03)
    M.AlphaTo(f, 1, 0)
    T.eq(f:GetAlpha(), 1, "snapped up")
end)

T.test("motion: CountTo counts from the last shown number, the first one shown at once", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local f = CreateFrame("Frame", nil, UIParent)
    local fs = f:CreateFontString()
    local fmt = function(n) return n and ("ilvl " .. n) or "" end
    T.eq(M.CountTo(fs, 50, fmt), false, "first: no count")
    T.eq(fs:GetText(), "ilvl 50")
    T.eq(M.CountTo(fs, 60, fmt), true)
    tickAll(0.1)
    local mid = tonumber(fs:GetText():match("%d+"))
    T.truthy(mid > 50 and mid < 60, "counting, whole numbers")
    tickAll(1)
    T.eq(fs:GetText(), "ilvl 60")
    T.eq(M.CountTo(fs, nil, fmt), false)
    T.eq(fs:GetText(), "", "no number: its text at once")
    T.eq(M.CountTo(fs, 70, fmt), false, "after no number: shown at once")
    M.CountTo(fs, 52.4, fmt)
    tickAll(1)
    T.eq(fs:GetText(), "ilvl 52.4", "ends on the exact value")
end)
