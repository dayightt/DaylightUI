local stub = require("stub")

-- The swing timers: a bar per hand, filled over each swing the client
-- reports, dimmed out of reach, recolored while an attack is queued.

-- Shown "In combat" unless asked (the layout tests want every bar up);
-- visibility = "default" keeps the default (while swinging).
local function login(before, visibility)
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Daylight", isPlayer = true, class = "WARRIOR", health = 50, maxHealth = 50 }
        if before then before() end
    end })
    stub.RunTimers()
    if visibility ~= "default" then
        DaylightUI:Set("UnitFrames", "swing.visibility", visibility or "combat")
        stub.RunTimers()
    end
    return DUI, ns
end

local function rows(h)
    local out = {}
    for _, r in ipairs(h.rows) do out[r.def.key] = r end
    return out
end

T.test("swing: a bar for the main hand under the cast bar, as wide as it; the game's own hidden", function()
    local _, ns = login()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local h = ns.swing
    T.truthy(h, "built")
    local r = rows(h)
    T.truthy(r.main:IsShown(), "the main hand")
    T.falsy(r.off:IsShown(), "no off hand without an off-hand weapon")
    T.falsy(r.ranged:IsShown(), "no ranged without a ranged weapon")
    local player = ns.frames.player
    local p, rel, rp = h:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, player); T.eq(rp, "BOTTOMLEFT", "no cast: hung under the frame itself")
    T.eq(h:GetWidth(), player:GetWidth(), "as wide as it")
    local sl = DaylightUI.Style.GetSlant(r.main)
    T.eq(sl.side, "right", "its angled end carried on")
    T.eq(sl.ref.frame, player, "on the frame's own line")
    local shallow = sl.cut
    local _, _, _, lx0 = r.main.label:GetPoint(1)
    T.eq(lx0, ns.CastBar.PAD, "the label 3px in from the bar's edge")
    local _, _, _, tx = r.main.time:GetPoint(1)
    T.near(tx, -(ns.CastBar.PAD + sl.cut), 1e-6, "the time clear of its angled end")
    ns.playerCastbar:Show()                            -- a cast starts
    stub.RunOnUpdate(ns.playerCastbar.slide.driver, 1)  -- done sliding out
    local _, rel2 = h:GetPoint(1)
    T.eq(rel2, ns.playerCastbar, "hung under the cast bar while it shows")
    T.truthy(DaylightUI.Style.GetSlant(r.main).cut > shallow, "further down the same line")
    local _, _, _, lx = r.main.label:GetPoint(1)
    T.eq(lx, ns.CastBar.PAD, "still 3px in")
    ns.playerCastbar:Hide()
    local _, rel3 = h:GetPoint(1)
    T.eq(rel3, player, "back under the frame when the cast ends")
    T.falsy(SwingTimerMainHandFrame:IsShown(), "the game's own swing bar hidden")
    T.truthy(DaylightUI.Style.GetShell(r.main), "our border")
end)

T.test("swing: a cast slides out from under the frame, pushing the bars down; and back", function()
    local _, ns = login(nil, "always")
    local h, cb, CB = ns.swing, ns.playerCastbar, ns.CastBar
    local player = ns.frames.player
    local main = rows(h).main
    T.truthy(h:IsVisible())
    stub.RunOnUpdate(h.slide.driver, 1)                      -- slid out at login
    T.eq(cb:GetParent(), cb.clip, "in a clip under the frame")
    T.eq(h:GetParent(), h.clip, "the bars in their own clip")
    T.eq(h.clip:GetParent(), cb.clip, "inside the cast bar's")
    local shallow = DaylightUI.Style.GetSlant(main).cut
    cb:Show()                                          -- a cast starts
    local _, _, _, _, cy0 = cb:GetPoint(1)
    T.truthy(cy0 > 0, "starts tucked up behind the frame")
    local p, rel, rp = h:GetPoint(1)
    T.eq(rel, player); T.eq(rp, "TOPLEFT", "moving: measured from the frame's top")
    stub.RunOnUpdate(cb.slide.driver, CB.SLIDE / 2)
    local _, _, _, _, cy1 = cb:GetPoint(1)
    T.truthy(cy1 < cy0, "part way down")
    T.truthy(DaylightUI.Style.GetSlant(main).cut > shallow, "the bars pushed down, their angle on the line")
    T.truthy(cb:GetFrameLevel() < h:GetFrameLevel(), "the bars over it, so it comes out from under them")
    stub.RunOnUpdate(cb.slide.driver, 1)
    local _, rel2 = h:GetPoint(1)
    T.eq(rel2, cb, "settled: hung under the cast bar")
    local deep = DaylightUI.Style.GetSlant(main).cut
    -- The cast ends: it slides back under, the bars follow it up.
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    T.truthy(cb:IsShown(), "still there, sliding back")
    stub.RunOnUpdate(cb.slide.driver, CB.SLIDE / 2)
    T.truthy(DaylightUI.Style.GetSlant(main).cut < deep)
    stub.RunOnUpdate(cb.slide.driver, 1)
    T.falsy(cb:IsShown(), "hidden once under")
    local _, rel3, rp3 = h:GetPoint(1)
    T.eq(rel3, player); T.eq(rp3, "BOTTOMLEFT", "back under the frame")
    T.near(DaylightUI.Style.GetSlant(main).cut, shallow, 1e-6)
end)

T.test("swing: a swing ending mid-cast slides back up cut off at the cast bar's bottom, never over it", function()
    local _, ns = login(function() stub.swing.speeds = { 2.6, 0, 0 } end, "default")
    local h, cb = ns.swing, ns.playerCastbar
    local main = rows(h).main
    stub.units.player.cast = { name = "X", notInterruptible = false, duration = stub.Duration(3) }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.RunOnUpdate(cb.slide.driver, 1)
    stub.FireEvent("PLAYER_SWING", 2.6, Enum.PlayerSwingType.MainHand)
    stub.RunOnUpdate(h.slide.driver, 1)
    local _, rel = h:GetPoint(1)
    T.eq(rel, cb, "settled under the cast bar")
    T.truthy(h.clip.__clips, "in a clip")
    local _, crel = h.clip:GetPoint(1)
    T.eq(crel, cb.clip, "settled: the clip is the cast bar's whole clip")
    -- The swing lands, the grace runs out: back up under the cast bar.
    stub.Advance(2.7)
    stub.RunOnUpdate(main, 2.7)
    stub.Advance(ns.Swing.GRACE)
    stub.RunOnUpdate(main, ns.Swing.GRACE)
    T.eq(h.slide.goal, 0, "sliding back up")
    stub.RunOnUpdate(h.slide.driver, ns.Swing.SLIDE / 2)
    local p, rel2, rp, _, y = h.clip:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel2, cb, "the clip's top is the cast bar's")
    T.eq(rp, "BOTTOMLEFT", "at its bottom edge")
    T.truthy(y > 0, "up by the borders' overlap")
    stub.RunOnUpdate(h.slide.driver, 1)
    T.falsy(h:IsShown(), "gone under")
    T.truthy(cb:IsShown(), "the cast goes on")
    -- The next swing: out again from under it, cut off the same way.
    stub.FireEvent("PLAYER_SWING", 2.6, Enum.PlayerSwingType.MainHand)
    stub.RunOnUpdate(h.slide.driver, ns.Swing.SLIDE / 2)
    local _, rel3 = h.clip:GetPoint(1)
    T.eq(rel3, cb, "sliding out: cut off at the cast bar too")
    stub.RunOnUpdate(h.slide.driver, 1)
    local _, rel4 = h.clip:GetPoint(1)
    T.eq(rel4, cb.clip, "settled again: the whole clip")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("swing: a cast straight after the last turns the bar round, no blink", function()
    local _, ns = login(nil, "always")
    local cb, CB = ns.playerCastbar, ns.CastBar
    local cast = { name = "X", notInterruptible = false, duration = stub.Duration(1) }
    stub.units.player.cast = cast
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.truthy(cb:IsShown())
    stub.RunOnUpdate(cb.slide.driver, 1)
    stub.units.player.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    stub.RunOnUpdate(cb.slide.driver, CB.SLIDE / 2)
    T.eq(cb.slide.goal, 0, "sliding back under")
    local _, _, _, _, y = cb:GetPoint(1)
    stub.units.player.cast = cast
    stub.FireEvent("UNIT_SPELLCAST_START", "player")   -- the next one
    T.eq(cb.slide.goal, 1, "out again")
    local _, _, _, _, y2 = cb:GetPoint(1)
    T.eq(y2, y, "from where it was")
    stub.RunOnUpdate(cb.slide.driver, 1)
    T.truthy(cb:IsShown())
    T.eq(cb.slide.p, 1)
end)

T.test("swing: an interrupt after the cast's stop still holds the bar under the frame", function()
    local _, ns = login(nil, "always")
    local cb, CB = ns.playerCastbar, ns.CastBar
    stub.units.player.cast = { name = "X", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.RunOnUpdate(cb.slide.driver, 1)
    stub.units.player.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")      -- the stop first: sliding back
    T.eq(cb.slide.goal, 0)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    T.eq(cb.slide.goal, 1, "out again for the hold")
    stub.RunOnUpdate(cb.slide.driver, 1)
    T.truthy(cb:IsShown(), "held")
    T.eq(cb.text.__text, INTERRUPTED or "Interrupted")
    stub.RunTimers()
    T.eq(cb.slide.goal, 0, "then it slides back under")
    stub.RunOnUpdate(cb.slide.driver, 1)
    T.falsy(cb:IsShown())
end)

T.test("swing: test mode straight after a cast keeps the sample cast bar up", function()
    local _, ns = login(nil, "always")
    local cb = ns.playerCastbar
    stub.units.player.cast = { name = "X", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.RunOnUpdate(cb.slide.driver, 1)
    stub.units.player.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    T.eq(cb.slide.goal, 0)
    ns.CastBar.ShowSample(cb, ns.Test.CASTS.player)
    stub.RunOnUpdate(cb.slide.driver, 1)
    T.truthy(cb:IsShown(), "the sample stays")
    T.eq(cb.slide.p, 1)
end)

T.test("swing: hung under the frame, the bars slide out from under it and back", function()
    local _, ns = login()
    local h = ns.swing
    T.falsy(h:IsShown())
    stub.units.player.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.truthy(h:IsShown())
    T.eq(h.slide.p, 0, "starts tucked under")
    local _, rel, rp = h:GetPoint(1)
    T.eq(rel, ns.frames.player); T.eq(rp, "TOPLEFT")
    stub.RunOnUpdate(h.slide.driver, ns.Swing.SLIDE / 2)
    T.truthy(h.slide.p > 0 and h.slide.p < 1)
    stub.RunOnUpdate(h.slide.driver, 1)
    local _, rel2, rp2 = h:GetPoint(1)
    T.eq(rp2, "BOTTOMLEFT", "settled under the frame")
    stub.units.player.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.truthy(h:IsShown(), "sliding back")
    stub.units.player.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(h.slide.goal, 1, "back in combat: turns round")
    stub.RunOnUpdate(h.slide.driver, 1)
    T.truthy(h:IsShown())
end)

T.test("swing: shown in combat or while a swing runs; filled over the swing, empty when it lands", function()
    local _, ns = login()
    local h = ns.swing
    local main = rows(h).main
    T.falsy(h:IsShown(), "hidden out of combat")
    stub.FireEvent("PLAYER_SWING", 2.0, Enum.PlayerSwingType.MainHand)
    T.truthy(h:IsShown(), "shown while a swing runs")
    T.eq(main.time.__text, "2.0")
    stub.Advance(0.5)
    stub.RunOnUpdate(main, 0.5)
    T.near(main.bar:GetValue(), 0.25, 1e-6, "a quarter through")
    T.eq(main.time.__text, "1.5")
    stub.Advance(1.6)
    stub.RunOnUpdate(main, 1.6)
    T.eq(main.bar:GetValue(), 0, "landed: empty")
    T.truthy(h:IsShown(), "for a moment, in case the next swing's reported just after")
    stub.Advance(ns.Swing.GRACE)
    stub.RunOnUpdate(main, ns.Swing.GRACE)
    T.truthy(h:IsShown(), "sliding back under the frame")
    stub.RunOnUpdate(h.slide.driver, 1)
    T.falsy(h:IsShown(), "hidden again out of combat")
    stub.units.player.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.truthy(h:IsShown(), "shown in combat")
end)

T.test("swing: an off hand and a ranged weapon each get a bar, stacked", function()
    local _, ns = login(function() stub.swing.speeds = { 2.6, 1.8, 3.0 } end)
    local h = ns.swing
    local r = rows(h)
    T.truthy(r.off:IsShown()); T.truthy(r.ranged:IsShown())
    local _, _, _, _, y1 = r.main:GetPoint(1)
    local _, _, _, _, y2 = r.off:GetPoint(1)
    T.truthy(y2 < y1, "the off hand under the main hand")
    stub.FireEvent("PLAYER_SWING", 1.8, Enum.PlayerSwingType.OffHand)
    T.truthy(r.off.start, "the off hand's swing runs on its own bar")
    T.falsy(r.main.start)
    DaylightUI:Set("UnitFrames", "swing.ranged", false)
    stub.RunTimers()
    T.falsy(r.ranged:IsShown(), "ranged turned off")
end)

T.test("swing: out of the target's reach a bar dims and its time turns red", function()
    local _, ns = login()
    local main = rows(ns.swing).main
    T.truthy(stub.swing.checks[Enum.PlayerSwingType.MainHand], "the client asked about reach")
    local function run(n)
        local d = DaylightUI.Motion.Driver()
        for _ = 1, n do if d then stub.RunOnUpdate(d, 1 / 60) end end
    end
    stub.FireEvent("PLAYER_SWING_RANGE_UPDATE", Enum.PlayerSwingType.MainHand, false, true)
    T.eq(main.time.__textColor[1], ns.Swing.OUT_OF_RANGE_TEXT[1], "red time, at once")
    if main:IsShown() then
        run(3)
        T.truthy(main:GetAlpha() < 1 and main:GetAlpha() > ns.Swing.OUT_OF_RANGE_ALPHA, "dimming (FAST)")
    end
    run(30)
    T.eq(main:GetAlpha(), ns.Swing.OUT_OF_RANGE_ALPHA, "dimmed")
    stub.FireEvent("PLAYER_SWING_RANGE_UPDATE", Enum.PlayerSwingType.MainHand, false, false)
    run(30)
    T.eq(main:GetAlpha(), 1, "no check made: not out of reach")
    stub.swing.inRange[Enum.PlayerSwingType.MainHand] = false
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    run(30)
    T.eq(main:GetAlpha(), ns.Swing.OUT_OF_RANGE_ALPHA, "asked again on a new target")
end)

T.test("swing: a queued Heroic Strike recolors the melee bars and names itself", function()
    local _, ns = login()
    DaylightUI:Set("UnitFrames", "swing.fill", "plain")
    stub.RunTimers()
    local main = rows(ns.swing).main
    stub.swing.current["Heroic Strike"] = true
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    T.eq(main.label.__text, "Heroic Strike")
    T.near(main.bar.__barColor[1], ns.Swing.QUEUED[1], 1e-6, "the queued color")
    stub.swing.current["Heroic Strike"] = nil
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    T.eq(main.label.__text, main.def.label, "back when it's gone")
end)

T.test("swing: detached, its own width and mover; test mode shows sample swings", function()
    local DUI, ns = login()
    local h = ns.swing
    DaylightUI:Set("UnitFrames", "swing.attach", false)
    DaylightUI:Set("UnitFrames", "swing.width", 300)
    stub.RunTimers()
    T.near(h:GetWidth(), 300, 0.5, "its own width (pixel-snapped)")
    local _, rel = h:GetPoint(1)
    T.eq(rel, UIParent, "on its own mover")
    T.truthy(DUI.SetTestMode(true))
    T.truthy(h:IsShown(), "shown in test mode")
    T.near(rows(h).main.bar:GetValue(), ns.Swing.SAMPLE.main[1], 1e-6)
    DUI.SetTestMode(false)
    T.eq(h.slide.goal, 0, "slides back into its own box")
    stub.RunOnUpdate(h.slide.driver, 1)
    T.falsy(h:IsShown())
end)

T.test("swing: detached as a group, the bars slide out of their own box, cut at its edge only while they move", function()
    local _, ns = login(nil, "default")
    local h = ns.swing
    DaylightUI:Set("UnitFrames", "swing.attach", false)
    stub.RunTimers()
    T.truthy(h.together)
    T.falsy(h:IsShown(), "nothing swinging yet")
    stub.FireEvent("PLAYER_SWING", 2.6, Enum.PlayerSwingType.MainHand)
    T.truthy(h:IsShown())
    T.eq(h:GetParent(), h.boxClip, "in its box's clip")
    T.eq(h.slide.p, 0, "starts tucked in its box")
    T.truthy(h.boxClip.cut, "cut at the box's edge while sliding")
    stub.RunOnUpdate(h.slide.driver, ns.Swing.SLIDE / 2)
    local _, _, _, _, y = h.inner:GetPoint(1)
    T.truthy(y > 0 and y < h:GetHeight(), "halfway out: " .. tostring(y))
    stub.RunOnUpdate(h.slide.driver, 1)
    local _, _, _, _, y2 = h.inner:GetPoint(1)
    T.eq(y2, 0, "out")
    T.falsy(h.boxClip.cut, "whole, shadow and all, at rest")
end)

T.test("swing: detaching the cast bar leaves the swing bars hung under the player frame", function()
    local _, ns = login()
    local h = ns.swing
    DaylightUI:Set("UnitFrames", "playerCastbar.at", "free")
    stub.RunTimers()
    T.truthy(h.attached, "still hung")
    T.truthy(h.column, "in the frame's column")
    local _, rel = h:GetPoint(1)
    T.eq(rel, ns.frames.player, "under the frame itself")
    T.truthy(DaylightUI.Movers.Get("unitframes.swing").suspended, "no handle of its own")
    ns.playerCastbar:Show()                            -- a cast on the free bar
    local _, rel2 = h:GetPoint(1)
    T.eq(rel2, ns.frames.player, "the free cast bar doesn't take it along")
end)

T.test("swing: a bar detached on its own has its own piece, size and handle, and rises in as it fades in", function()
    local _, ns = login(function() stub.swing.speeds = { 2.6, 1.8, 3.0 } end, "default")
    local h = ns.swing
    local r = rows(h)
    DaylightUI:Set("UnitFrames", "swing.bars.off.detach", true)
    DaylightUI:Set("UnitFrames", "swing.bars.off.width", 260)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(r.off.alone)
    T.eq(r.off:GetParent(), r.off.pod, "in its own piece")
    T.near(r.off.pod:GetWidth(), 260, 0.5, "its own width")
    T.falsy(DaylightUI.Movers.Get("unitframes.swingOff").suspended, "its own handle")
    T.truthy(DaylightUI.Movers.Get("unitframes.swingMain").suspended, "the main hand stays in the group")
    T.truthy(h.attached, "the group stays hung under the frame")
    T.falsy(r.off.pod:IsShown(), "nothing swinging yet")
    stub.FireEvent("PLAYER_SWING", 1.8, Enum.PlayerSwingType.OffHand)
    T.truthy(r.off.pod:IsShown(), "comes in at once")
    T.falsy(h:IsShown(), "the group has no swing of its own")
    stub.RunOnUpdate(r.off.pop.driver, DaylightUI.Motion.NORMAL / 2)
    local a = r.off.pod:GetAlpha()
    T.truthy(a > 0 and a < 1, "fading in: " .. a)
    local _, _, _, _, y = r.off:GetPoint(1)
    T.truthy(y < 0 and y > -ns.Swing.RISE, "rising into place: " .. y)
    stub.RunOnUpdate(r.off.pop.driver, 1)
    local _, _, _, _, y2 = r.off:GetPoint(1)
    T.eq(y2, 0); T.eq(r.off.pod:GetAlpha(), 1)
    -- The swing lands: the bar fades away.
    stub.Advance(2)
    stub.RunOnUpdate(r.off, 2)
    stub.Advance(1)
    stub.RunOnUpdate(r.off, 1)
    T.eq(r.off.pop.goal, 0, "fading out")
    stub.RunOnUpdate(r.off.pop.driver, 1)
    T.falsy(r.off.pod:IsShown(), "gone")
    -- Back in the group.
    DaylightUI:Set("UnitFrames", "swing.bars.off.detach", false)
    stub.RunTimers()
    T.eq(r.off:GetParent(), h, "home")
    T.truthy(DaylightUI.Movers.Get("unitframes.swingOff").suspended)
end)

T.test("swing: the main hand bar can be switched off", function()
    local _, ns = login(function() stub.swing.speeds = { 2.6, 0, 3.0 } end)
    local r = rows(ns.swing)
    T.truthy(r.main:IsShown())
    DaylightUI:Set("UnitFrames", "swing.mainHand", false)
    stub.RunTimers()
    T.falsy(r.main:IsShown(), "main hand off")
    T.truthy(r.ranged:IsShown(), "the ranged bar stays")
end)

T.test("swing: a client without the swing API gets no bars and no errors", function()
    local _, ns = login(function() _G.C_SwingTimer = nil end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(ns.swing)
end)

T.test("swing: by default a bar shows only while its swing runs, and the stack closes up between swings", function()
    local _, ns = login(function() stub.swing.speeds = { 2.6, 0, 3.0 } end, "default")
    local h = ns.swing
    local r = rows(h)
    T.eq(DaylightUI:Get("UnitFrames", "swing.visibility"), "swinging")
    T.falsy(h:IsShown(), "nothing before a swing")
    stub.units.player.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.falsy(h:IsShown(), "nor just for being in combat")
    stub.FireEvent("PLAYER_SWING", 3.0, Enum.PlayerSwingType.Ranged)
    T.truthy(h:IsShown(), "a shot: shown")
    T.truthy(r.ranged:IsShown()); T.falsy(r.main:IsShown(), "only the bar that's swinging")
    local _, _, _, _, y = r.ranged:GetPoint(1)
    T.eq(y, 0, "at the top of the stack")
    stub.Advance(3.1)
    stub.RunOnUpdate(r.ranged, 3.1)
    T.truthy(r.ranged:IsShown(), "landed: kept a moment, not blinked off")
    stub.FireEvent("PLAYER_SWING", 3.0, Enum.PlayerSwingType.Ranged)
    T.truthy(r.ranged.start, "the next shot in the grace: straight on")
    stub.Advance(3.1)
    stub.RunOnUpdate(r.ranged, 3.1)
    stub.Advance(ns.Swing.RANGED_GRACE)
    stub.RunOnUpdate(r.ranged, ns.Swing.RANGED_GRACE)
    T.truthy(r.ranged:IsShown(), "kept up while it slides back under the frame")
    stub.RunOnUpdate(h.slide.driver, 1)
    T.falsy(r.ranged:IsShown(), "gone once the (ranged) grace passes with no new shot")
    T.falsy(h:IsShown())
end)

T.test("swing timer: every hand in your class color when set", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "swing.classColor", true)
    stub.RunTimers()
    local _, token = UnitClass("player")
    local r = DaylightUI.Style.ClassColor(token)
    T.near(ns.Swing.COLORS.main[1], r, 1e-6)
    T.eq(ns.Swing.COLORS.off, ns.Swing.COLORS.main)
    DUI:Set("UnitFrames", "swing.classColor", false)
    stub.RunTimers()
    T.eq(ns.Swing.COLORS.main, DUI:Get("UnitFrames", "swing.colors.main"), "back to the set colors")
end)

T.test("swing timer: a ranged shot whose length comes secret still runs, on the ranged speed", function()
    local DUI, ns = login(nil, "swinging")
    local h = ns.swing
    stub.swing.speeds = { 2.6, 0, 3.0 }
    DUI:Set("UnitFrames", "swing.ranged", true)
    stub.RunTimers()
    local T_ = Enum.PlayerSwingType
    stub.FireEvent("PLAYER_SWING", stub.Secret(3.0), T_.Ranged)
    local row = h.byType[T_.Ranged]
    T.truthy(row.start, "running")
    T.eq(row.dur, 3.0, "the ranged speed")
end)

T.test("swing timer: the ranged bar shows even when the client hides the ranged speed", function()
    local DUI, ns = login(nil, "swinging")
    DUI:Set("UnitFrames", "swing.ranged", true)
    stub.RunTimers()
    stub.swing.speeds = { 2.6, 0, stub.Secret(3.0) }
    stub.FireEvent("PLAYER_SWING", 2.9, Enum.PlayerSwingType.Ranged)
    T.truthy(ns.swing.byType[Enum.PlayerSwingType.Ranged].start, "the shot shows")
end)

-- What's in your hands, as the client says it: slot -> { link, classID }.
local function gear(slots)
    local link, instant = _G.GetInventoryItemLink, C_Item and C_Item.GetItemInfoInstant
    _G.GetInventoryItemLink = function(_, slot) return slots[slot] and slots[slot][1] end
    _G.C_Item = _G.C_Item or {}
    C_Item.GetItemInfoInstant = function(l)
        for _, s in pairs(slots) do
            if s[1] == l then return 1, "", "", "", 0, s[2], 0 end
        end
    end
    return function() _G.GetInventoryItemLink = link; C_Item.GetItemInfoInstant = instant end
end

T.test("swing timer: in a fight the hidden speeds don't invent a ranged bar for an empty slot or a relic", function()
    for _, slots in ipairs({ {}, { [18] = { "idol", 4 } } }) do
        local undo = gear(slots)
        local _, ns = login(nil, "combat")
        local r = rows(ns.swing)
        stub.swing.speeds = { stub.Secret(2.6), nil, stub.Secret(0) }     -- what combat reads
        stub.FireEvent("PLAYER_REGEN_DISABLED")
        stub.FireEvent("UNIT_ATTACK_SPEED", "player")
        stub.RunTimers()
        T.truthy(r.main:IsShown(), "the main hand")
        T.falsy(r.ranged:IsShown(), "nothing to shoot with")
        undo()
    end
end)

T.test("swing timer: a real bow keeps its bar in a fight, and it goes when the bow comes off", function()
    local slots = { [18] = { "bow", 2 } }
    local undo = gear(slots)
    local _, ns = login(nil, "combat")
    local r = rows(ns.swing)
    stub.swing.speeds = { stub.Secret(2.6), nil, stub.Secret(3.0) }
    stub.FireEvent("UNIT_ATTACK_SPEED", "player")
    stub.RunTimers()
    T.truthy(r.ranged:IsShown(), "the bow's bar")
    slots[18] = nil
    stub.FireEvent("WEAPON_SLOT_CHANGED")
    stub.RunTimers()
    T.falsy(r.ranged:IsShown(), "gone with the bow")
    undo()
end)

T.test("swing timer: with the Gradients page's pairs, a queued attack gets its own pair", function()
    local DUI, ns = login()
    DaylightUI:Set("UnitFrames", "swing.fill", "pair")
    stub.RunTimers()
    local main = rows(ns.swing).main
    local function lo() return main.bar:GetStatusBarTexture().__gradient[2].r end
    T.near(lo(), (DUI.Gradients.Colors("SWING_MAIN")).r, 1e-6, "the main hand's pair")
    for _, spell in ipairs({ "Heroic Strike", "Cleave" }) do
        stub.swing.current[spell] = true
        stub.FireEvent("ACTIONBAR_UPDATE_STATE")
        T.near(lo(), (DUI.Gradients.Colors("SWING_QUEUED")).r, 1e-6, spell .. ": the queued pair")
        stub.swing.current[spell] = nil
        stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    end
    T.near(lo(), (DUI.Gradients.Colors("SWING_MAIN")).r, 1e-6, "back when it's gone")
end)

T.test("swing timer options: one color shows the swatches, two-color the pairs (the Gradients page's own)", function()
    local DUI = login()
    DaylightUI:Set("UnitFrames", "swing.fill", "plain")
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.swing")
    local byLabel = {}
    for _, group in ipairs(page.groups) do
        for _, item in ipairs(group.items) do byLabel[item.type .. ":" .. item.label] = item end
    end
    local swatch, pair = byLabel["color:Main hand color"], byLabel["gradient:Main hand gradient"]
    T.truthy(swatch); T.truthy(pair)
    T.falsy(O.IsHidden(page, swatch))
    T.truthy(O.IsHidden(page, pair))
    DaylightUI:Set("UnitFrames", "swing.fill", "pair")
    T.truthy(O.IsHidden(page, swatch))
    T.falsy(O.IsHidden(page, pair))
    pair.set({ lo = { 0.1, 0.2, 0.3 }, hi = { 0.4, 0.5, 0.6 } })
    T.near((DUI.Gradients.RGB("SWING_MAIN"))[1], 0.1, 1e-6, "the same pair as the Gradients page")
    local errors = O.ValidatePage(page)
    T.eq(#errors, 0, errors[1])
end)

local function detach(extra)
    DaylightUI:Set("UnitFrames", "swing.attach", false)
    for k, v in pairs(extra or {}) do DaylightUI:Set("UnitFrames", "swing." .. k, v) end
    stub.RunTimers()
end

T.test("swing: detached, fill right to left; attached ignores it", function()
    local _, ns = login()
    local r = rows(ns.swing)
    detach({ reverseFill = true })
    T.eq(r.main.bar.__reverse, true)
    DaylightUI:Set("UnitFrames", "swing.attach", true)
    stub.RunTimers()
    T.eq(r.main.bar.__reverse, false)
end)

T.test("swing: its own text size; attached, no taller than a row fits", function()
    local _, ns = login()
    local r = rows(ns.swing)
    detach({ textSize = 15 })
    T.eq(select(2, r.main.label:GetFont()), 15)
    DaylightUI:Set("UnitFrames", "swing.textSize", 8)
    DaylightUI:Set("UnitFrames", "swing.attach", true)
    stub.RunTimers()
    T.eq(select(2, r.main.label:GetFont()), 8, "attached: the same size while it fits")
    DaylightUI:Set("UnitFrames", "swing.textSize", 24)
    stub.RunTimers()
    T.truthy(select(2, r.main.label:GetFont()) < 24, "attached: capped by the row")
end)

T.test("swing: the border goes around the bar, never into it (any screen)", function()
    local DUI, ns = login()
    local h, r = ns.swing, rows(ns.swing)
    local Pixel = DUI.Pixel
    local border = Pixel.Px(h, DUI.DB.General().borderPx)
    T.near(h.rowHeight - 2 * border, DUI:Get("UnitFrames", "swing.height"), Pixel.Unit(h) * 2, "the bar keeps its own height")
    -- A smaller screen makes the 8 px border twice as thick in UI units: the
    -- bar keeps its height and its text keeps its size.
    local before = h.rowHeight
    DUI.DB.General().borderPx = 16
    ns.Swing.Layout(h, h.cfg, h.castbar)
    T.truthy(h.rowHeight > before, "a thicker border makes the row taller")
    T.eq(select(2, r.main.label:GetFont()), 12, "the text keeps its size")
end)

T.test("swing: a height set before the border went around the bar keeps its look on 4K", function()
    local _, ns = login()
    local up = ns.UPGRADE_STEPS[15]
    local uf = { swing = { height = 30 } }
    up(uf)
    T.eq(uf.swing.height, 22, "loses what the border took")
    uf.swing.height = 22
    up(uf)
    T.eq(uf.swing.height, 14, "the old default lands on the new one")
    uf.swing.height = 14
    up(uf)
    T.eq(uf.swing.height, 14, "a new profile's default is left alone")
    uf.swing.height = 10
    up(uf)
    T.eq(uf.swing.height, 10, "a small one stays: only taller now, never thinner")
end)

T.test("swing: detached spacing and stacking upward", function()
    local _, ns = login(function() stub.swing.speeds = { 2.6, 1.8, 0 } end)
    local h, r = ns.swing, rows(ns.swing)
    detach({ spacing = 4 })
    local _, _, _, _, y = r.off:GetPoint(1)
    local gap = -y - h.rowHeight
    T.truthy(gap > 0, "a gap between the bars")
    T.near(h:GetHeight(), 2 * h.rowHeight + gap, 1e-6)
    detach({ growUp = true })
    T.eq(r.main:GetPoint(1), "BOTTOMLEFT")
end)

T.test("swing: detached, the box keeps its size between swings; attached shrinks", function()
    local _, ns = login(function() stub.swing.speeds = { 2.6, 1.8, 0 } end, "default")
    local h, r = ns.swing, rows(ns.swing)
    detach()
    local full = h:GetHeight()
    T.truthy(full > h.rowHeight, "two bars' worth with none swinging")
    stub.FireEvent("PLAYER_SWING", 2.6, Enum.PlayerSwingType.MainHand)
    T.eq(h:GetHeight(), full, "one swinging")
    DaylightUI:Set("UnitFrames", "swing.attach", true)
    stub.RunTimers()
    T.truthy(h:GetHeight() < full, "attached: only the shown bar")
end)

T.test("swing: detached weapon icon and angled end", function()
    local _, ns = login()
    local r = rows(ns.swing)
    detach({ showIcon = true, slant = true })
    T.truthy(r.main.icon:IsShown())
    T.eq(r.main.icon.__texture, "tex:16")
    T.truthy(r.main.endCut > 0)
    detach({ slant = false })
    T.eq(r.main.endCut, 0)
    DaylightUI:Set("UnitFrames", "swing.attach", true)
    stub.RunTimers()
    T.falsy(r.main.icon:IsShown())
end)

-- Hunters: Auto Shot's wind-up line and "Stop moving"; the range readout.
local function hunter(extra)
    return login(function()
        stub.units.player.class = "HUNTER"
        stub.swing.speeds = { 2.6, 0, 3.0 }
        if extra then extra() end
    end, "default")
end

T.test("swing: the stop-moving line and the range readout are off by default", function()
    local DUI, ns = hunter()
    T.eq(DUI:Get("UnitFrames", "swing.stopCue"), false)
    T.eq(DUI:Get("UnitFrames", "swing.rangeText"), false)
    local r = rows(ns.swing).ranged
    stub.FireEvent("PLAYER_SWING", 3.0, Enum.PlayerSwingType.Ranged)
    T.falsy(r.windLine.on, "no line")
    T.eq(r.label:GetText(), r.def.label, "the bar's own name")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    stub.Advance(3.1)
    stub.RunOnUpdate(r, 3.1)
    T.falsy(r.held, "nothing held back")
    T.eq(r.label:GetText(), r.def.label)
end)

T.test("swing: a hunter's Auto Shot line; moving in the wind-up says Stop moving and holds the bar full", function()
    local DUI, ns = hunter()
    DUI:Set("UnitFrames", "swing.stopCue", true)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local h, r = ns.swing, rows(ns.swing).ranged
    stub.FireEvent("PLAYER_SWING", 3.0, Enum.PlayerSwingType.Ranged)
    T.truthy(r.windLine.on, "the line shows")
    local block = ns.Swing.Windup(3.0)
    T.near(r.block, block, 1e-6)
    T.truthy(block > 0.5 and block < 1, "the wind-up and a ping: " .. block)
    local _, _, _, x = r.windLine:GetPoint(1)
    local w = h:GetWidth() - 2 * DaylightUI.Pixel.Px(r, DaylightUI.DB.General().borderPx)
    T.near(x, w * (1 - block / 3.0), 1, "where the wind-up starts")
    -- Standing still: nothing to say.
    stub.Advance(3.0 - block + 0.05)
    stub.RunOnUpdate(r, 0.05)
    T.eq(r.label:GetText(), r.def.label, "standing: the bar's name")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    stub.RunOnUpdate(r, 0.01)
    T.eq(r.label:GetText(), "Stop moving", "moving in the wind-up")
    stub.Advance(1)
    stub.RunOnUpdate(r, 1)
    T.truthy(r.held, "past the end, moving: held")
    T.eq(r.bar:GetValue(), 1, "full")
    T.truthy(r:IsShown(), "still up")
    stub.Advance(2)
    stub.RunOnUpdate(r, 2)
    T.truthy(r:IsShown(), "held as long as you move")
    stub.FireEvent("PLAYER_STOPPED_MOVING")
    stub.RunOnUpdate(r, 0.01)
    T.falsy(r.held)
    T.eq(r.label:GetText(), r.def.label, "standing again")
    stub.FireEvent("PLAYER_SWING", 3.0, Enum.PlayerSwingType.Ranged)
    T.truthy(r.start, "the shot: the next reload runs")
    T.eq(r.bar:GetValue(), 0)
    T.truthy(r.windLine.on, "the line stays, no blink")
end)

T.test("swing: no Auto Shot line for a class without Auto Shot", function()
    local DUI, ns = login(function() stub.swing.speeds = { 2.6, 0, 3.0 } end, "default")
    DUI:Set("UnitFrames", "swing.stopCue", true)
    stub.RunTimers()
    local r = rows(ns.swing).ranged
    stub.FireEvent("PLAYER_SWING", 3.0, Enum.PlayerSwingType.Ranged)
    T.falsy(r.windLine.on)
    T.falsy(r.block)
end)

T.test("swing: the range readout names how far the target is", function()
    local inRange = {}
    local DUI, ns = hunter(function()
        stub.units.target = { name = "Boar", hostile = true, health = 10, maxHealth = 10 }
        _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
        _G.C_Item.IsItemInRange = function(id) return inRange[id] end
    end)
    DUI:Set("UnitFrames", "swing.rangeText", true)
    stub.RunTimers()
    local r = rows(ns.swing).ranged
    local T_ = Enum.PlayerSwingType
    stub.FireEvent("PLAYER_SWING", 3.0, T_.Ranged)
    local function poll() stub.RunOnUpdate(r.ranger, 1) end
    stub.swing.inRange[T_.MainHand] = true
    poll()
    T.eq(r.label:GetText(), "Melee")
    stub.swing.inRange[T_.MainHand], stub.swing.inRange[T_.Ranged] = false, false
    inRange[17626] = true
    poll()
    T.eq(r.label:GetText(), "Dead zone", "too close to shoot")
    stub.swing.inRange[T_.Ranged] = true
    inRange[17626], inRange[7734] = false, true
    poll()
    T.eq(r.label:GetText(), "30 yd")
    inRange[7734] = false
    poll()
    T.eq(r.label:GetText(), "Max range", "only Auto Shot reaches")
    stub.swing.inRange[T_.Ranged] = false
    poll()
    T.eq(r.label:GetText(), "Out of range")
    -- The game won't say (secret): back to the bar's name, no error.
    stub.swing.inRange[T_.MainHand] = stub.Secret(true)
    stub.swing.inRange[T_.Ranged] = stub.Secret(true)
    for k in pairs(inRange) do inRange[k] = stub.Secret(true) end
    poll()
    T.eq(r.label:GetText(), r.def.label)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.units.target = nil
    poll()
    T.eq(r.label:GetText(), r.def.label, "no target: the bar's name")
    _G.UnitCanAttack, _G.C_Item.IsItemInRange = nil, nil
end)

T.test("swing: test mode shows the line and a sample range when they're on", function()
    local DUI, ns = hunter()
    DUI:Set("UnitFrames", "swing.stopCue", true)
    DUI:Set("UnitFrames", "swing.rangeText", true)
    stub.RunTimers()
    local h, r = ns.swing, rows(ns.swing).ranged
    ns.Swing.ShowSample(h)
    T.truthy(r.windLine.on)
    T.eq(r.label:GetText(), "30 yd")
    ns.Swing.HideSample(h)
    T.eq(r.label:GetText(), r.def.label)
end)

T.test("swing: a bar detached on its own hides its name and time when switched off", function()
    local _, ns = login()
    local r = rows(ns.swing)
    DaylightUI:Set("UnitFrames", "swing.bars.main.detach", true)
    stub.RunTimers()
    stub.FireEvent("PLAYER_SWING", 2.6, Enum.PlayerSwingType.MainHand)
    T.truthy(r.main.label:IsShown(), "name on by default")
    DaylightUI:Set("UnitFrames", "swing.bars.main.showName", false)
    DaylightUI:Set("UnitFrames", "swing.bars.main.showTime", false)
    stub.RunTimers()
    stub.RunOnUpdate(r.main, 0.5)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(r.main.label:IsShown(), "no name")
    T.falsy(r.main.time:IsShown(), "no time")
end)

T.test("swing: attached, a bar's own name and time switches hide its text; the group's switch still turns all off", function()
    local _, ns = login()
    local r = rows(ns.swing)
    stub.FireEvent("PLAYER_SWING", 2.6, Enum.PlayerSwingType.MainHand)
    T.falsy(r.main.alone, "attached")
    T.truthy(r.main.label:IsShown()); T.truthy(r.main.time:IsShown())
    DaylightUI:Set("UnitFrames", "swing.bars.main.showName", false)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(r.main.label:IsShown(), "no name")
    T.truthy(r.main.time:IsShown(), "time stays")
    DaylightUI:Set("UnitFrames", "swing.bars.main.showTime", false)
    stub.RunTimers()
    T.falsy(r.main.time:IsShown(), "no time")
    DaylightUI:Set("UnitFrames", "swing.bars.main.showName", true)
    DaylightUI:Set("UnitFrames", "swing.bars.main.showTime", true)
    DaylightUI:Set("UnitFrames", "swing.showText", false)
    stub.RunTimers()
    T.falsy(r.main.label:IsShown(), "group switch off: no name")
    T.falsy(r.main.time:IsShown(), "group switch off: no time")
end)

T.test("cast bar between the frames: a trapezoid wider at the bottom, the swing bars fanning out under it, each wider", function()
    local _, ns = login()
    DaylightUI:Set("UnitFrames", "playerCastbar.at", "middle")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local cb, h = ns.playerCastbar, ns.swing
    local Style = DaylightUI.Style
    local p1, rel1, rp1 = cb:GetPoint(1)
    T.eq(p1, "TOPLEFT"); T.eq(rel1, ns.frames.player); T.eq(rp1, "TOPRIGHT", "starts at your frame's end")
    local p2, rel2, rp2 = cb:GetPoint(2)
    T.eq(p2, "TOPRIGHT"); T.eq(rel2, ns.frames.target); T.eq(rp2, "TOPLEFT", "ends at the target frame's")
    local sl = Style.GetSlant(cb)
    T.eq(sl.side, "both", "both ends angled"); T.eq(sl.under, "both", "both leaning under: wider at the bottom")
    T.truthy(cb.middle, "between the frames")
    T.truthy(h.fan, "the swing bars fan out under it")
    T.falsy(h.attached, "not hung under the player frame")
    T.eq(h:GetParent(), h.fanClip, "in the clip they fold out of")
    ns.Swing.ShowSample(h)
    stub.RunTimers()
    local r = rows(h)
    T.truthy(r.main:IsShown() and r.off:IsShown() and r.ranged:IsShown(), "every bar in test mode")
    local rs = Style.GetSlant(r.main)
    T.eq(rs.side, "both"); T.eq(rs.under, "both", "each bar carries the angle down")
    T.truthy(r.off:GetWidth() > r.main:GetWidth() and r.ranged:GetWidth() > r.off:GetWidth(), "each a little wider")
    local _, _, rp = r.main:GetPoint(1)
    T.eq(rp, "TOP", "centered under it")
    -- No cast up: the first bar sits in the cast bar's own spot.
    T.eq(h.room.p, 0, "no cast: raised into the cast bar's spot")
    local _, _, _, _, yIdle = h:GetPoint(1)
    local wIdle = r.main:GetWidth()
    -- A cast starts: they scoot down under it, FAST.
    ns.CastBar.ShowSample(cb, { value = 0.5, text = "Fireball" })
    T.eq(h.room.goal, 1, "a cast up: heading under it")
    stub.RunOnUpdate(h.room.driver, 1)
    T.eq(h.room.p, 1)
    local _, _, _, _, yCast = h:GetPoint(1)
    T.truthy(yCast < yIdle, "lower with a cast up")
    T.truthy(r.main:GetWidth() > wIdle, "wider further down, the angle kept")
    -- The cast ends: back up into its spot.
    ns.CastBar.Stop(cb, true)
    T.eq(h.room.goal, 0, "cast over: rising back")
    stub.RunOnUpdate(h.room.driver, 1)
    local _, _, _, _, yBack = h:GetPoint(1)
    T.eq(yBack, yIdle, "back in the cast bar's spot")
    -- Back under the frame: hung again.
    DaylightUI:Set("UnitFrames", "playerCastbar.at", "below")
    stub.RunTimers()
    T.falsy(h.fan, "no fan")
    T.truthy(h.attached, "hung under the player frame again")
    T.falsy(cb.middle)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
