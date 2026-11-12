local stub = require("stub")

-- The target frame arriving from no target (Arrive.lua): the frame fades in, the
-- health and power fills grow from empty, the portrait pops in with a light running
-- round its ring, and the name tab slides up from behind.

local GLIDE = Enum.StatusBarInterpolation.ExponentialEaseOut

local function login()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.target = { name = "Defias Pillager", isPlayer = false, reaction = 2, level = 32,
                              health = 72, maxHealth = 100, power = 40, maxPower = 100 }
    end })
    return DUI, ns
end

-- The motion kit's tweens and the fade engine, dt seconds on.
local function step(DUI, dt)
    local d = DUI.Motion.Driver()
    if d and d:GetScript("OnUpdate") then stub.RunOnUpdate(d, dt) end
    DUI.Fade.Animate(dt)
end

local function settle(DUI)
    for _ = 1, 90 do step(DUI, 1 / 60) end
end

local function tabY(f)
    local _, _, _, _, y = f.tab:GetPoint(1)
    return y
end

-- The target goes from none to one: the unit watch shows the frame.
local function arrive(f)
    f:Hide()
    f:Show()
end

T.test("arriving from no target: fills grow, ring pops in, tab slides up", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    local restY = tabY(f)
    arrive(f)
    T.eq(stub.Plain(f.health:GetValue()), 72, "the real value, handed to the client to glide to")
    T.eq(f.health.__interp, GLIDE, "the client grows the fill from empty (a secret is fine)")
    T.eq(f.power.__interp, GLIDE, "the power fill too")
    T.truthy(f.portrait:GetScale() < 1, "the portrait starts small")
    T.truthy(tabY(f) < restY, "the tab starts lower, behind the body")
    T.truthy(f.tabClip.__clips, "and is cut off at the body's top edge while it slides")
    T.truthy(f.portrait.arriveLight:IsShown(), "a light runs round the ring")
    local now = DUI.Fade.State("UnitFrames.target")
    T.truthy(now < 0.5, "the frame fades in")
    settle(DUI)
    T.near(f.portrait:GetScale(), 1, 0.001, "the portrait lands at its size")
    T.near(tabY(f), restY, 0.001, "the tab lands where it rests")
    T.falsy(f.tabClip.__clips, "nothing clipped at rest")
    T.falsy(f.portrait.arriveLight:IsShown(), "the light is gone")
    T.eq(DUI.Fade.State("UnitFrames.target"), 1)
end)

T.test("a target swap snaps: no arrival while the frame stays shown", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    stub.units.target.health = 30
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(f.health.__interp, nil, "the new unit's health lands at once")
    T.near(f.portrait:GetScale() or 1, 1, 0.001)
    T.falsy(f.tabClip.__clips)
end)

T.test("the swap's own update during an arrival doesn't cut the fill's growth short", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    arrive(f)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(f.health.__interp, GLIDE, "still growing")
end)

T.test("arriving in a fight plays too, with the frame left alone", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    local pt = { f:GetPoint(1) }
    stub.EnterCombat()
    T.noerror(function() arrive(f) end)
    T.eq(f.health.__interp, GLIDE)
    settle(DUI)
    T.deq({ f:GetPoint(1) }, pt, "the protected frame itself never moves")
    stub.LeaveCombat()
end)

T.test("the target lost mid-arrival: everything back at rest", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    local restY = tabY(f)
    arrive(f)
    step(DUI, 0.03)
    f:Hide()
    T.near(f.portrait:GetScale(), 1, 0.001)
    T.near(tabY(f), restY, 0.001)
    T.falsy(f.tabClip.__clips)
    T.falsy(f.portrait.arriveLight:IsShown())
end)

T.test("motion off: it simply shows", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    DUI:Set("general", "motion", false)
    arrive(f)
    T.eq(f.health.__interp, nil)
    T.near(f.portrait:GetScale() or 1, 1, 0.001)
    T.eq(DUI.Fade.State("UnitFrames.target"), 1)
end)

T.test("test mode samples don't arrive", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    DUI.SetTestMode(true)
    arrive(f)
    T.near(f.portrait:GetScale() or 1, 1, 0.001)
end)

-- Leaving (Arrive.lua): the target is cleared and the game's unit watch only reports
-- it (asState). The frame stays up a moment with its clicks off, fades out with its
-- tab sliding back down behind the body, then hides.

local function clear()
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.UnitWatch()
end

local function retarget()
    stub.units.target = { name = "Kobold Miner", isPlayer = false, reaction = 2, level = 30,
                          health = 50, maxHealth = 100, power = 0, maxPower = 0 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.UnitWatch()
end

T.test("stub: a unit watch as state sets state-unitexists, only when it changes", function()
    stub.Reset()
    local f = CreateFrame("Button", nil, UIParent, "SecureUnitButtonTemplate")
    f:SetAttribute("unit", "target")
    local seen = {}
    f:SetScript("OnAttributeChanged", function(_, k, v) if k == "state-unitexists" then seen[#seen + 1] = v end end)
    RegisterUnitWatch(f, true)
    stub.UnitWatch()
    T.deq(seen, { false }, "checked once at once, then no news")
    T.truthy(f:IsShown(), "the frame is left alone")
end)

T.test("clearing the target: the frame lingers with clicks off, fades out, tab sliding down, then hides", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.UnitWatch()
    settle(DUI)
    local restY = tabY(f)
    T.truthy(f.__mouse ~= false, "clickable with a target")
    clear()
    T.truthy(f:IsShown(), "still up for its fade")
    T.eq(f.__mouse, false, "clicks pass through it at once")
    T.eq(f.nameText:GetText(), "Defias Pillager", "it keeps its last look while it goes")
    step(DUI, 0.05)
    T.truthy(DUI.Fade.State("UnitFrames.target") < 1, "fading out")
    T.truthy(tabY(f) < restY, "the tab slides back down")
    settle(DUI)
    T.falsy(f:IsShown(), "hidden once faded")
    T.near(tabY(f), restY, 0.001, "the tab back at rest")
    T.falsy(f.tabClip.__clips)
end)

T.test("a new target while it fades: it comes straight back and arrives", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.UnitWatch()
    settle(DUI)
    clear()
    step(DUI, 0.05)
    retarget()
    T.truthy(f:IsShown())
    T.truthy(f.__mouse ~= false, "clickable again")
    T.eq(f.nameText:GetText(), "Kobold Miner")
    T.eq(f.health.__interp, GLIDE, "it arrives: the fill grows")
    settle(DUI)
    T.truthy(f:IsShown(), "no leftover hide")
    T.eq(DUI.Fade.State("UnitFrames.target"), 1)
end)

T.test("cleared in a fight: faded and click-through, hidden once the fight ends", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.secure = true
    stub.UnitWatch()
    settle(DUI)
    stub.EnterCombat()
    T.noerror(function() clear() end)
    T.noerror(function() settle(DUI) end)
    T.eq(f.__mouse, false)
    T.eq(DUI.Fade.State("UnitFrames.target"), 0, "gone from sight")
    T.truthy(f:IsShown(), "a protected frame can't hide in combat")
    T.noerror(function() retarget() end)
    T.truthy(f.__mouse ~= false, "a new target in the fight takes clicks at once")
    settle(DUI)
    T.eq(DUI.Fade.State("UnitFrames.target"), 1, "and comes back")
    T.noerror(function() clear() end)
    settle(DUI)
    stub.LeaveCombat()
    T.falsy(f:IsShown(), "hidden after the fight")
    stub.secure = false
end)

T.test("motion off: clearing hides at once", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.UnitWatch()
    settle(DUI)
    DUI:Set("general", "motion", false)
    clear()
    T.falsy(f:IsShown())
end)

-- The unit frames' moments (Moments.lua): lights for a fight starting and ending,
-- and the last breath of a target dying before your eyes.

local function light(f, kind)
    local h = f.moments and f.moments[kind]
    return h and h.light
end

T.test("the login reveal: each shown frame arrives, fills growing from empty once it's half in; a fight first: the real values", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    f.health.__interp = nil
    DUI.Fire("LoginReveal")
    T.eq(stub.Plain(f.health:GetValue()), 0, "empty from the start, while the frame fades in")
    T.isnil(f.health.__interp, "not growing yet")
    stub.RunTimers()
    T.eq(f.health.__interp, GLIDE, "the fill grows from empty, the client gliding")
    T.eq(stub.Plain(f.health:GetValue()), 72, "to the real value")
    T.truthy(f.portrait:GetScale() < 1, "the portrait pops in")
    T.eq(DUI.Fade.State("UnitFrames.target"), 1, "its fade left to the reveal")
    settle(DUI)
    T.near(f.portrait:GetScale(), 1, 0.001, "and lands")

    DUI, ns = login()
    settle(DUI)
    ns.frames.target.health.__interp = nil
    DUI.Fire("LoginReveal")
    stub.EnterCombat()
    stub.RunTimers()
    T.isnil(ns.frames.target.health.__interp, "a fight started: no growing")
    T.eq(stub.Plain(ns.frames.target.health:GetValue()), 72, "the real value at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a fight starting runs a light along each frame's top edge; ending, a warm one", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.RunTimers()
    T.truthy(light(ns.frames.player, "edge") and light(ns.frames.player, "edge"):IsShown(), "on you at once")
    T.truthy(light(f, "edge") and light(f, "edge"):IsShown(), "and on the target, a beat later")
    local r, g, b = DUI.Style.Accent()
    T.near(select(1, light(f, "edge"):GetVertexColor()), r, 0.001, "in the accent")
    settle(DUI)
    T.falsy(light(f, "edge"):IsShown(), "gone once it has run")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.RunTimers()
    local gold = DUI.Style.INK.MONEY
    T.truthy(light(f, "edge"):IsShown(), "the fight ending: a light again")
    T.near(select(1, light(f, "edge"):GetVertexColor()), gold[1], 0.001, "warm, going out")
    settle(DUI)
    T.falsy(light(f, "edge"):IsShown())
end)

T.test("dying ends the fight with no warm light; motion off: no lights", function()
    local DUI, ns = login()
    settle(DUI)
    stub.units.player = stub.units.player or { name = "Me", isPlayer = true }
    stub.units.player.dead = true
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.RunTimers()
    T.falsy(light(ns.frames.target, "edge") and light(ns.frames.target, "edge"):IsShown())
    stub.units.player.dead = false
    DUI:Set("general", "motion", false)
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.RunTimers()
    T.falsy(light(ns.frames.target, "edge") and light(ns.frames.target, "edge"):IsShown())
end)

T.test("the target dying: a breath rises off the frame and DEAD fades in", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    stub.units.target.health = 0
    stub.units.target.dead = true
    stub.FireEvent("UNIT_HEALTH", "target")
    T.eq(f.percentText:GetText(), DUI.L["DEAD"])
    local t = light(f, "body")
    T.truthy(t and t:IsShown(), "the breath")
    local _, _, _, _, y0 = t:GetPoint(1)
    step(DUI, 0.4)
    local _, _, _, _, y1 = t:GetPoint(1)
    T.truthy(y1 > y0, "it rises")
    settle(DUI)
    T.falsy(t:IsShown(), "and is gone")
end)

-- Hide at full health reads its alpha off a curve. The fake game has none, so this
-- one answers with the unit's `pct` (0 = at full, hidden).
local function withCurve(fn)
    _G.C_CurveUtil = { CreateCurve = function()
        local c = {}
        function c:SetType() end
        function c:AddPoint() end
        return c
    end }
    local ok, err = pcall(fn)
    _G.C_CurveUtil = nil
    if not ok then error(err, 0) end
end

T.test("a kill, then a new target at full health at once: its hidden health text stays hidden", function() withCurve(function()
    local DUI, ns = login()
    local f = ns.frames.target
    DUI:Set("UnitFrames", "target.hideFullHealth", true)
    settle(DUI)
    stub.units.target.health = 0
    stub.units.target.dead = true
    stub.FireEvent("UNIT_HEALTH", "target")
    step(DUI, 0.1)
    stub.units.target = { name = "Defias Thug", isPlayer = false, reaction = 2, level = 30,
                          health = 100, maxHealth = 100, pct = 0, power = 0, maxPower = 100 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(stub.Plain(f.percentText:GetAlpha()), 0, "hidden at full health")
    settle(DUI)
    T.eq(stub.Plain(f.percentText:GetAlpha()), 0, "the dead one's fade doesn't bring it back")
    T.falsy(light(f, "body"):IsShown(), "the breath went with the old target")
end) end)

T.test("motion off: a target killed from full health shows DEAD", function() withCurve(function()
    local DUI, ns = login()
    local f = ns.frames.target
    DUI:Set("UnitFrames", "target.hideFullHealth", true)
    DUI:Set("general", "motion", false)
    stub.units.target.health = 100
    stub.units.target.pct = 0
    stub.FireEvent("UNIT_HEALTH", "target")
    settle(DUI)
    T.eq(stub.Plain(f.percentText:GetAlpha()), 0, "hidden at full health")
    stub.units.target.health = 0
    stub.units.target.dead = true
    stub.FireEvent("UNIT_HEALTH", "target")
    T.eq(f.percentText:GetText(), DUI.L["DEAD"])
    T.eq(stub.Plain(f.percentText:GetAlpha()), 1, "DEAD shows")
end) end)

T.test("a swap to a corpse has no breath", function()
    local DUI, ns = login()
    local f = ns.frames.target
    settle(DUI)
    stub.units.target = { name = "Corpse", isPlayer = false, reaction = 2, level = 30, dead = true,
                          health = 0, maxHealth = 100, power = 0, maxPower = 100 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(f.percentText:GetText(), DUI.L["DEAD"])
    local t = light(f, "body")
    T.falsy(t and t:IsShown())
end)
