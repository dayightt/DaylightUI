local stub = require("stub")

-- Ending motion on the combat frames: a cast that ends fades out FAST (a new one is
-- up at once), status icons of the same unit ease, and a level gained bumps the badge.

local function run(n)
    local d = DaylightUI.Motion.Driver()
    for _ = 1, n do if d then stub.RunOnUpdate(d, 1 / 60) end end
end

local function bar()
    local _, ns = stub.Load({ module = true, login = false })
    local h = ns.CastBar.Create("player")
    ns.CastBar.Layout(h, ns.DEFAULTS.playerCastbar)
    ns.CastBar.cfg.fill = "plain"
    return h, ns
end

local function cast(name)
    stub.units.player = { cast = { name = name or "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
end

T.test("cast bars: a cast that ends fades out FAST, then hides", function()
    local h = bar()
    cast()
    T.eq(h:GetAlpha(), 1)
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    T.truthy(h:IsShown(), "still going")
    run(3)
    T.truthy(h:GetAlpha() > 0 and h:GetAlpha() < 1, "partway")
    run(30)
    T.falsy(h:IsShown(), "gone")
end)

T.test("cast bars: the next cast mid-fade is up at once, at full", function()
    local h = bar()
    cast()
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    run(3)
    cast("Fireball")
    T.eq(h:GetAlpha(), 1, "at once: fight info never waits")
    run(30)
    T.truthy(h:IsShown()); T.eq(h:GetAlpha(), 1, "the old fade doesn't finish it off")
end)

T.test("cast bars: an interrupt after the stop brings the bar back for its hold", function()
    local h, ns = bar()
    cast()
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    run(2)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    run(30)
    T.truthy(h:IsShown(), "held")
    T.eq(h.text.__text, INTERRUPTED or "Interrupted")
    stub.RunTimers()
    run(30)
    T.falsy(h:IsShown(), "then fades away")
end)

T.test("status icons: resting eases in and out; a fresh read sets it at once", function()
    local _, ns = stub.Load({ module = true, login = false })
    local f = ns.UF.Create({ unit = "player", label = "Player", power = true })
    ns.UF.Layout(f, { width = 187, height = 43, powerHeight = 11, showName = true, portrait = "class" }, ns.DEFAULTS.playerText)
    if not f.status then return end
    f.showResting = true
    stub.units.player = { name = "Me", level = 10 }
    stub.resting = true
    ns.UF.UpdateStatus(f, nil, true)
    local rest = f.status.icons.rest
    T.truthy(rest:IsShown())
    run(3)
    T.truthy(rest:GetAlpha() > 0 and rest:GetAlpha() < 1, "easing in")
    run(30)
    T.eq(rest:GetAlpha(), 1)
    stub.resting = false
    ns.UF.UpdateStatus(f, nil, true)
    T.truthy(rest:IsShown(), "easing out")
    run(30)
    T.falsy(rest:IsShown())
    stub.resting = true
    ns.UF.UpdateStatus(f)
    T.truthy(rest:IsShown()); T.eq(rest:GetAlpha(), 1, "no animate: at once")
    stub.resting = nil
end)

T.test("level badge: a level gained bumps it; a fresh unit doesn't", function()
    local _, ns = stub.Load({ module = true, login = false })
    local f = ns.UF.Create({ unit = "player", label = "Player", power = true })
    ns.UF.Layout(f, { width = 187, height = 43, powerHeight = 11, showName = true, portrait = "class" }, ns.DEFAULTS.playerText)
    if not f.status then return end
    f.showLevel = true
    stub.units.player = { name = "Me", level = 10 }
    ns.UF.UpdateStatus(f)
    local t = f.status.levelText
    T.falsy(t.__duiBump and t.__duiBump:IsPlaying(), "first read: no bump")
    stub.units.player.level = 11
    ns.UF.UpdateStatus(f, nil, true)
    T.truthy(t.__duiBump and t.__duiBump:IsPlaying(), "level up: bumps")
    T.eq(t.__text, 11)
end)

-- The target's bar hung under its frame: the player's slide, mirrored (the target's
-- ring is on the right, its angle on the left). The buffs under the frame stay
-- where they are, past the room it slides out into.
T.test("target cast bar: under the frame it slides out mirrored, the buffs keep their room", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local h, f = ns.targetCastbarFree, ns.frames.target
    local room = ns.auras.buffDrop
    DUI:Set("UnitFrames", "targetCastbar.at", "slide")
    stub.RunTimers()
    T.truthy(h.column, "hung under the frame")
    T.eq(h:GetParent(), h.clip, "inside the clip it slides out of")
    T.truthy(DUI.Movers.Get("unitframes.targetCastbar").suspended, "no mover: it follows the frame")
    T.near(h:GetWidth(), f:GetWidth(), 1, "as wide as the frame")
    T.eq(DUI.Style.GetSlant(h).side, "left", "carries the target's angle, on its left")
    T.truthy(h.bar:GetReverseFill(), "fills from the ring, like the frame's own bars")
    T.truthy(ns.auras.buffDrop >= room + h:GetHeight(), "the buffs sit past the room it needs")
    local kept = ns.auras.buffDrop

    stub.units.target = { name = "Mob", cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) } }
    f:Show()
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(h:IsShown(), "up at once")
    T.truthy(h.slide.p < 1, "sliding out, not popped in")
    stub.RunOnUpdate(h.slide.driver, 1)
    T.eq(h.slide.p, 1, "all the way out")
    T.eq(ns.auras.buffDrop, kept, "the buffs didn't move")

    stub.units.target = { name = "Mob" }
    stub.FireEvent("UNIT_SPELLCAST_STOP", "target")
    T.truthy(h:IsShown(), "slides back under rather than vanishing")
    stub.RunOnUpdate(h.slide.driver, 1)
    T.falsy(h:IsShown(), "gone once back under")

    DUI:Set("UnitFrames", "targetCastbar.at", "free")
    stub.RunTimers()
    T.falsy(h.column, "on its own again")
    T.eq(h:GetParent(), UIParent, "out of the clip")
    T.falsy(h.bar:GetReverseFill(), "its own fill way")
end)

T.test("target cast bar: slides out from under combo points sitting below the frame", function()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", powerToken = "ENERGY" }
    end })
    stub.RunTimers()
    DUI:Set("UnitFrames", "targetCastbar.at", "slide")
    DUI:Set("UnitFrames", "combo.enabled", false)
    stub.RunTimers()
    local bare = ns.targetCastbarFree.column.lift
    DUI:Set("UnitFrames", "combo.enabled", true)
    DUI:Set("UnitFrames", "combo.anchor", "target")
    DUI:Set("UnitFrames", "combo.side", "below")
    stub.RunTimers()
    local _, _, pips = ns.TargetAuraRoom(ns.module.db)
    T.truthy(pips > 0, "pips under the frame")
    T.near(ns.targetCastbarFree.column.lift, bare - pips, 0.5, "hangs below them")
end)

-- A druid's pips only show in cat form. Out of it nothing sits under the frame, so
-- the bar hangs right under it, not past an empty gap. In game it slid out of thin
-- air, lower than the player's.
T.test("target cast bar: past the pips only while they show", function()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Leafy", isPlayer = true, class = "DRUID", powerToken = "MANA" }
    end })
    stub.RunTimers()
    local h = ns.targetCastbarFree
    DUI:Set("UnitFrames", "combo.enabled", false)
    DUI:Set("UnitFrames", "targetCastbar.at", "slide")
    stub.RunTimers()
    local bare = h.column.lift
    DUI:Set("UnitFrames", "combo.enabled", true)
    DUI:Set("UnitFrames", "combo.anchor", "target")
    DUI:Set("UnitFrames", "combo.side", "below")
    stub.RunTimers()
    local _, _, pips = ns.TargetAuraRoom(ns.module.db)
    T.truthy(pips > 0, "room kept for the pips")
    T.falsy(ns.combo:IsShown(), "no pips out of cat form")
    T.near(h.column.lift, bare, 0.5, "hangs right under the frame")
    T.near(select(5, h.clip:GetPoint(1)), bare, 0.5, "and slides out from there")

    -- Cat form with the bar up: it glides down past them.
    stub.units.target = { name = "Mob", cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) } }
    ns.frames.target:Show()
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    stub.RunOnUpdate(h.slide.driver, 1)
    stub.units.player.powerToken = "ENERGY"
    stub.FireEvent("UNIT_DISPLAYPOWER", "player")
    T.truthy(ns.combo:IsShown(), "pips up")
    T.near(h.column.lift, bare, 0.5, "not a jump")
    stub.RunOnUpdate(h.pips.driver, 1)
    T.near(h.column.lift, bare - pips, 0.5, "past the pips")
    T.near(select(5, h.clip:GetPoint(1)), bare - pips, 0.5, "the clip with it")

    -- Back out with no bar up: straight back, nothing to see.
    stub.units.target = { name = "Mob" }
    stub.FireEvent("UNIT_SPELLCAST_STOP", "target")
    stub.RunOnUpdate(h.slide.driver, 1)
    stub.units.player.powerToken = "MANA"
    stub.FireEvent("UNIT_DISPLAYPOWER", "player")
    T.near(h.column.lift, bare, 0.5, "back under the frame")

    -- At its own size under the frame: the same.
    DUI:Set("UnitFrames", "targetCastbar.at", "below")
    stub.RunTimers()
    local y = select(5, h:GetPoint(1))
    stub.units.player.powerToken = "ENERGY"
    stub.FireEvent("UNIT_DISPLAYPOWER", "player")
    T.near(select(5, h:GetPoint(1)), y - pips, 0.5, "below the frame: past the pips only while they show")
end)

-- The game's own bar shows UnitCastingInfo's second value, displayName (the
-- CastingBarFrame in Blizzard_UIPanels_Game). The first, name, can be a raw
-- untranslated one: a zhCN player saw "Open" and "No Text" looting a quest item.
T.test("cast bars: show the spell's display name, not its raw name", function()
    local h = bar()
    local casting, channel = _G.UnitCastingInfo, _G.UnitChannelInfo
    _G.UnitCastingInfo = function() return "Open", "打开", 1, 0, 0, false, 1, false, 1 end
    stub.units.player = { cast = { name = "Open", duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.eq(h.text.__text, "打开")
    _G.UnitCastingInfo = function() end
    _G.UnitChannelInfo = function() return "Open", "打开", 1, 0, 0, false, false, 1 end
    stub.units.player = { channel = { name = "Open", duration = stub.Duration(1) } }
    h.text:SetText("")
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    _G.UnitCastingInfo, _G.UnitChannelInfo = casting, channel
    T.eq(h.text.__text, "打开")
end)
