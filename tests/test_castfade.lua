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

-- The focus's bar can hang under its frame too, like the target's.
T.test("focus cast bar: under the frame it slides out, the buffs keep their room", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local h, f = ns.focusCastbarFree, ns.frames.focus
    T.truthy(f, "a focus frame")
    local room = select(2, ns.FocusAuraRoom(ns.module.db))
    DUI:Set("UnitFrames", "focusCastbar.enabled", true)
    DUI:Set("UnitFrames", "focusCastbar.at", "slide")
    stub.RunTimers()
    T.truthy(h.column, "hung under the frame")
    T.eq(h:GetParent(), h.clip, "inside the clip it slides out of")
    T.truthy(DUI.Movers.Get("unitframes.focusCastbar").suspended, "no mover: it follows the frame")
    T.near(h:GetWidth(), f:GetWidth(), 1, "as wide as the frame")
    T.truthy(select(2, ns.FocusAuraRoom(ns.module.db)) > room, "the buffs keep room for it")
    DUI:Set("UnitFrames", "focusCastbar.at", "free")
    stub.RunTimers()
    T.falsy(h.column, "on its own again")
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

-- The fade setting of a cast bar, its own (yours) or its frame's (the target's
-- bar on its own): a cast starting never snaps a faded bar back to full.

local function settleFade(secs)
    local F = DaylightUI.Fade
    for _ = 1, 30 do
        F.Step()
        if F.driver then stub.RunOnUpdate(F.driver, secs / 30) end
        stub.Advance(secs / 30)
    end
end

local function optionItem(pageId, key)
    for id, page in DaylightUI.Options.Pages() do
        if id == pageId then
            for _, g in ipairs(page.groups) do
                for _, it in ipairs(g.items or {}) do if it.key == key then return it, g end end
            end
        end
    end
end

T.test("cast bars: your cast bar has an Opacity & fade card on its page, never fading by default", function()
    local DUI = stub.Load({ module = true })
    stub.RunTimers()
    local it, g = optionItem("UnitFrames.player", "playerCastbar.fade.mode")
    T.truthy(it, "the Visible row")
    T.eq(g and g.label, DUI.Fade.CARD_LABEL)
    T.isnil(it and it.values.float, "no Only when something changes: it already shows only while you cast")
    T.eq(DUI:Get("UnitFrames", "playerCastbar.fade.mode"), "never", "untouched, nothing changes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: your cast bar fades by its own setting, and a cast keeps it faded", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    -- On its own, where a cast that ends fades out (hung, it slides back under the frame).
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    DUI:Set("UnitFrames", "playerCastbar.fade.mode", "always")
    DUI:Set("UnitFrames", "playerCastbar.fade.mouseover", false)
    DUI:Set("UnitFrames", "playerCastbar.fade.alpha", 0.3)
    DUI:Set("UnitFrames", "playerCastbar.fade.delay", 1)
    stub.RunTimers()
    settleFade(3)
    local h = ns.playerCastbar
    cast()
    T.near(h:GetAlpha(), 0.3, 0.001, "starts faded, not at full")
    settleFade(1)
    T.near(h:GetAlpha(), 0.3, 0.001, "and stays there")
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    run(30)
    T.falsy(h:IsShown(), "still fades out and hides when the cast ends")
    cast("Fireball")
    T.near(h:GetAlpha(), 0.3, 0.001, "the next cast faded too")
    -- Back to Always: full again.
    DUI:Set("UnitFrames", "playerCastbar.fade.mode", "never")
    stub.RunTimers()
    settleFade(2)
    T.eq(h:GetAlpha(), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: the target's bar on its own keeps the target frame's fade when a cast starts", function()
    local DUI, ns = stub.Load({ module = true })
    stub.units.target = { name = "Mob", health = 10, maxHealth = 10 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    DUI:Set("UnitFrames", "targetCastbar.at", "free")
    DUI:Set("UnitFrames", "target.fade.mode", "always")
    DUI:Set("UnitFrames", "target.fade.mouseover", false)
    DUI:Set("UnitFrames", "target.fade.alpha", 0.2)
    DUI:Set("UnitFrames", "target.fade.delay", 1)
    stub.RunTimers()
    settleFade(3)
    local h = ns.targetCastbarFree
    stub.units.target.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(h:IsShown())
    T.near(h:GetAlpha(), 0.2, 0.001, "faded with its frame, not snapped to full")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: hung under the player frame, your faded cast bar slides out faded", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    DUI:Set("UnitFrames", "playerCastbar.fade.mode", "always")
    DUI:Set("UnitFrames", "playerCastbar.fade.mouseover", false)
    DUI:Set("UnitFrames", "playerCastbar.fade.alpha", 0.4)
    DUI:Set("UnitFrames", "playerCastbar.fade.delay", 1)
    stub.RunTimers()
    settleFade(3)
    local h = ns.playerCastbar
    T.truthy(h.column, "hung")
    cast()
    T.near(h:GetAlpha(), 0.4, 0.001)
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    run(30)
    cast("Fireball")
    T.near(h:GetAlpha(), 0.4, 0.001, "the next one too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
