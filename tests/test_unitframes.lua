local stub = require("stub")

local function make(spec, cfg)
    local _, ns = stub.Load({ module = true, login = false })
    local f = ns.UF.Create(spec)
    ns.UF.Layout(f, cfg, ns.DEFAULTS.playerText)
    return f, ns
end

local PLAYER = { unit = "player", label = "Player", power = true }

-- Loading Blizzard_AuraContainer from addon code set it up tainted. After that
-- every game call to a method some addon had hooked failed with "attempt to
-- call a nil value", thousands a minute. The game loads it itself.
T.test("the unit frames never load one of the game's own addons, even before the game has", function()
    local loads = {}
    stub.Load({ module = true, before = function()
        C_AddOns.LoadAddOn = function(name) loads[#loads + 1] = name end
    end })
    stub.RunTimers()
    T.truthy(DaylightUIFrame_target, "the frames were built")
    T.isnil(loads[1], "nothing loaded from our code")
end)

T.test("frames are secure unit buttons that target and open the menu", function()
    local f = make(PLAYER, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    T.eq(f:GetName(), "DaylightUIFrame_player")
    T.truthy(f:IsProtected())
    T.eq(f:GetAttribute("unit"), "player")
    T.eq(f:GetAttribute("*type1"), "target")
    T.eq(f:GetAttribute("*type2"), "togglemenu")
end)

T.test("layout sizes the frame and snaps the power bar to pixels", function()
    local f = make(PLAYER, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    T.near(f:GetWidth(), 2 * DaylightUI.Pixel.Snap(f, 220 / 2))
    T.near(f.power:GetHeight(), 8 * 768 / 1080)
    local p, rel = f.health:GetPoint(2)
    T.eq(p, "BOTTOMRIGHT")
    T.eq(rel, f.separator)
end)

T.test("the name sits centered along the bottom of the health bar", function()
    local f = make(PLAYER, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    local p, rel, rp = f.nameText:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, f.health); T.eq(rp, "BOTTOMLEFT")
    T.truthy(f.nameText:IsShown())
    T.truthy(f.percentText:IsShown())
end)

T.test("health, percent and name tolerate secret values", function()
    local f, ns = make({ unit = "target", label = "Target", power = true, tab = true, marker = true, classification = true },
        { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true, showMarker = true, showClassification = true })
    local hp = stub.Secret(50)
    stub.units.target = { name = stub.Secret("Boss"), isPlayer = false, reaction = stub.Secret(2),
        health = hp, maxHealth = stub.Secret(100), pct = stub.Secret(50), raidTarget = stub.Secret(3),
        classification = stub.Secret("elite") }
    ns.UF.UpdateAll(f)
    T.eq(f.health.__value, hp)
    T.eq(f.percentText.__text.secretFormat, "%.0f")
    T.eq(stub.lastCurve, "ScaleTo100")
    T.truthy(issecretvalue(f.nameText.__text), "secret name passed through untouched")
    T.truthy(f.marker:IsShown(), "a secret marker is still drawn")
    T.falsy(f.crest:IsShown())
end)

T.test("names show as written, always soft white", function()
    local f, ns = make(PLAYER, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    stub.units.player = { name = "Kaladin", class = "MAGE", isPlayer = true, health = 10, maxHealth = 20, pct = 50 }
    ns.UF.UpdateAll(f)
    T.eq(f.nameText.__text, "Kaladin")
    T.rgb(f.nameText.__textColor, ns.UF.NAME_COLOR, "name")
    T.eq(stub.Text(f.percentText), "50")
end)

T.test("unit colors: class, reaction, tapped, secret", function()
    local _, ns = stub.Load({ module = true, login = false })
    local S = DaylightUI.Style
    stub.units.a = { isPlayer = true, class = "MAGE" }
    stub.units.b = { isPlayer = false, reaction = 2 }
    stub.units.c = { isPlayer = false, reaction = 2, tapped = true }
    stub.units.d = { isPlayer = stub.Secret(true) }
    T.rgb({ ns.UF.UnitColor("a") }, { S.ClassColor("MAGE") }, "class")
    T.rgb({ ns.UF.UnitColor("b") }, { S.ReactionColor(2) }, "reaction")
    T.rgb({ ns.UF.UnitColor("c") }, { S.Neutral() }, "tapped")
    T.rgb({ ns.UF.UnitColor("d") }, { S.Neutral() }, "secret")
end)

T.test("custom reaction, tapped, state, dispel colors and range opacity", function()
    local _, ns = stub.Load({ module = true, login = false })
    local UF, S = ns.UF, DaylightUI.Style
    stub.units.b = { isPlayer = false, reaction = 2 }
    stub.units.c = { isPlayer = false, reaction = 2, tapped = true }
    UF.ConfigureColors({ hostile = { 0, 0, 1 }, tapped = { 1, 0, 0 }, dead = { 0.1, 0.2, 0.3 },
                         offline = { 0.3, 0.2, 0.1 }, dispelMagic = { 1, 1, 0 } })
    T.rgb({ UF.UnitColor("b") }, { S.Soften(0, 0, 1) }, "hostile")
    T.rgb({ UF.UnitColor("c") }, { 1, 0, 0 }, "tapped")
    T.rgb({ UF.StateColor("ghost") }, { 0.1, 0.2, 0.3 }, "ghost uses dead")
    T.rgb({ UF.StateColor("offline") }, { 0.3, 0.2, 0.1 }, "offline")
    T.eq(ns.Auras.DISPEL_COLORS.Magic[2], 1)
    T.eq(UF.RangeAlpha({ alpha = 0.4, groupOwn = true, alphaGroup = 0.7 }, true), 0.7)
    T.eq(UF.RangeAlpha({ alpha = 0.4, groupOwn = true, alphaGroup = 0.7 }, false), 0.4)
    T.eq(UF.RangeAlpha({ alpha = 0.4, groupOwn = false, alphaGroup = 0.7 }, true), 0.4)
end)

T.test("unit colors: a group member whose class is hidden gets it from their group token", function()
    local _, ns = stub.Load({ module = true, login = false })
    local S = DaylightUI.Style
    stub.units.party1 = { isPlayer = true, class = "DRUID" }
    stub.units.targettarget = { isPlayer = true, class = stub.Secret("DRUID") }
    stub.units.focus = { isPlayer = stub.Secret(true), class = stub.Secret("DRUID") }
    local real = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b)
        if (a == "targettarget" or a == "focus") and b == "party1" then return true end
        return real(a, b)
    end
    T.rgb({ ns.UF.UnitColor("targettarget") }, { S.ClassColor("DRUID") }, "class hidden")
    T.rgb({ ns.UF.UnitColor("focus") }, { S.ClassColor("DRUID") }, "player-ness hidden too")
    -- The match itself hidden: gray, as before.
    _G.UnitIsUnit = function() return stub.Secret(true) end
    T.rgb({ ns.UF.UnitColor("targettarget") }, { S.Neutral() }, "nothing to go on")
    _G.UnitIsUnit = real
end)

T.test("the name tab: a secret text width gets a fixed share, no error", function()
    local f, ns = make({ unit = "party2", label = "Party", power = true, tab = true },
        { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    T.truthy(f.tab, "has a name tab")
    local real = f.nameText.GetStringWidth
    f.nameText.GetStringWidth = function() return stub.Secret(50) end
    ns.UF.SizeTab(f, "Selena")
    T.eq(#stub.errors, 0)
    f.nameText.GetStringWidth = real
end)

T.test("power bar uses the soft power color", function()
    local f, ns = make(PLAYER, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    stub.units.player = { name = "X", isPlayer = true, class = "MAGE", powerToken = "RAGE", power = 5, maxPower = 10 }
    ns.UF.UpdatePower(f)
    T.eq(f.power.__value, 5)
    T.rgb(f.power.__barColor, { DaylightUI.Style.PowerColor("RAGE") }, "power")
end)

T.test("unit events update the frame; unknown events are skipped", function()
    local _, ns = stub.Load({ module = true, login = false })
    stub.unknownEvents.UNIT_CLASSIFICATION_CHANGED = true
    local f = ns.UF.Create(PLAYER)
    ns.UF.Layout(f, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true }, ns.DEFAULTS.playerText)
    ns.UF.Wire(f)
    stub.units.player = { name = "X", isPlayer = true, class = "MAGE", health = 7, maxHealth = 9, pct = 77 }
    stub.FireEvent("UNIT_HEALTH", "player")
    T.eq(stub.Plain(f.health.__value), 7)
    stub.FireEvent("UNIT_HEALTH", "target")
    T.eq(stub.Plain(f.health.__value), 7)
end)

T.test("UNIT_POWER_FREQUENT nudges the power bar along too, so it fills between ticks", function()
    local _, ns = stub.Load({ module = true, login = false })
    local f = ns.UF.Create(PLAYER)
    ns.UF.Layout(f, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true }, ns.DEFAULTS.playerText)
    ns.UF.Wire(f)
    stub.units.player = { name = "X", isPlayer = true, class = "ROGUE", powerToken = "ENERGY", power = 42, maxPower = 100 }
    stub.FireEvent("UNIT_POWER_FREQUENT", "player")
    T.eq(f.power.__value, 42)
    T.eq(f.power.__interp, Enum.StatusBarInterpolation.ExponentialEaseOut, "glides like any other power update")
    stub.FireEvent("UNIT_POWER_FREQUENT", "target")
    T.eq(f.power.__value, 42, "another unit's tick doesn't touch it")
end)

T.test("the power bar is polled every frame while shown, so it fills between ticks", function()
    local _, ns = stub.Load({ module = true, login = false })
    -- Built (not wired): a secure group header's raid tile drives its unit
    -- through attributes, not UF.Wire, so the poll has to start in UF.Build.
    local f = ns.UF.Create(PLAYER)
    ns.UF.Layout(f, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true }, ns.DEFAULTS.playerText)
    stub.units.player = { name = "X", isPlayer = true, class = "ROGUE", powerToken = "ENERGY", power = 10, maxPower = 100 }
    stub.RunOnUpdate(f, 0.06)
    T.eq(f.power.__value, 10)
    T.eq(f.power.__interp, Enum.StatusBarInterpolation.ExponentialEaseOut, "a jump still glides with Smooth bars on")
    stub.units.player.power = 11
    stub.RunOnUpdate(f, 0.06)
    T.eq(f.power.__value, 11, "moved on before the next UNIT_POWER_UPDATE tick")
    f:Hide()
    stub.units.player.power = 99
    stub.RunOnUpdate(f, 0.06)
    T.eq(f.power.__value, 11, "hidden: no point polling")
end)

T.test("polling updates a frame on its interval", function()
    local _, ns = stub.Load({ module = true, login = false })
    local f = ns.UF.Create({ unit = "targettarget", label = "ToT", compact = true })
    ns.UF.Layout(f, { width = 100, height = 20, showName = true }, ns.DEFAULTS.playerText)
    ns.UF.EnablePolling(f, 0.1)
    stub.units.targettarget = { name = "Friend", isPlayer = true, class = "PRIEST" }
    stub.RunOnUpdate(f, 0.05)
    T.isnil(f.nameText.__text)
    stub.RunOnUpdate(f, 0.06)
    T.eq(f.nameText.__text, "Friend")
end)

T.test("a new target name resizes the tab but doesn't re-place the aura rows", function()
    local _, ns = stub.Load({ module = true })
    local f = ns.frames.target
    stub.units.target = { name = "Szeth", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    ns.UF.UpdateIdentity(f)
    local n, orig = 0, ns.Auras.Place
    ns.Auras.Place = function(...) n = n + 1; return orig(...) end
    stub.units.target.name = "Taln"
    ns.UF.UpdateIdentity(f)
    stub.FireEvent("UNIT_FLAGS", "target")
    T.eq(n, 0, "the rows' room didn't change")
    f:SetWidth(f:GetWidth() + 20)
    ns.UF.SizeTab(f)
    ns.Auras.Place = orig
    T.eq(n, 1, "a wider frame does")
end)

-- The target of target sits beside the target, under its portrait ring:
-- every part of it draws under every part of the target (seen in game: its
-- bar drew over the ring while its shell drew under).
T.test("the target of target draws whole under the target and its portrait", function()
    local _, ns = stub.Load({ module = true })
    local function levels(f, out)
        out = out or {}
        if type(f.GetFrameLevel) == "function" then out[#out + 1] = f:GetFrameLevel() end
        if type(f.GetChildren) == "function" then
            for _, c in ipairs({ f:GetChildren() }) do levels(c, out) end
        end
        return out
    end
    local tgt, tot = levels(ns.frames.target), levels(ns.frames.targettarget)
    T.truthy(math.max(unpack(tot)) < math.min(unpack(tgt)),
        "tot top " .. math.max(unpack(tot)) .. " under target bottom " .. math.min(unpack(tgt)))
end)

T.test("the target of target's poll reads health every tick, the rest every few", function()
    local _, ns = stub.Load({ module = true, login = false })
    local UF = ns.UF
    local f = UF.Create({ unit = "targettarget", label = "ToT", compact = true })
    UF.Layout(f, { width = 100, height = 20, showName = true }, ns.DEFAULTS.playerText)
    UF.EnablePolling(f, 0.1)
    stub.units.targettarget = { name = "Friend", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    local calls = { UpdateAll = 0, UpdateHealth = 0 }
    local orig = {}
    for name in pairs(calls) do
        orig[name] = UF[name]
        UF[name] = function(...) calls[name] = calls[name] + 1; return orig[name](...) end
    end
    for _ = 1, 10 do stub.RunOnUpdate(f, 0.11) end
    for name, fn in pairs(orig) do UF[name] = fn end
    T.eq(calls.UpdateAll, 10 / UF.POLL_FULL, "the full pass, a safety net")
    T.truthy(calls.UpdateHealth >= 10, "health on every tick")
end)

T.test("bars glide on updates and snap when the unit changes", function()
    local f, ns = make(PLAYER, { width = 220, height = 48, powerHeight = 10, showName = true, showPercent = true })
    stub.units.player = { name = "X", isPlayer = true, class = "MAGE", health = 5, maxHealth = 10, pct = 50 }
    ns.UF.UpdateHealth(f)
    T.eq(f.health.__interp, Enum.StatusBarInterpolation.ExponentialEaseOut)
    ns.UF.UpdateAll(f, true)
    T.isnil(f.health.__interp)
    DaylightUI:Set("general", "smoothBars", false)
    ns.UF.UpdateHealth(f)
    T.isnil(f.health.__interp)
end)

T.test("health bars carry no hit or heal trail: just the fill, gliding", function()
    local f, ns = make(PLAYER, { width = 220, height = 48, powerHeight = 10, showName = true, showPercent = true })
    T.isnil(ns.DEFAULTS.healthTrail); T.isnil(ns.DEFAULTS.trail)
    stub.units.player = { name = "X", isPlayer = true, class = "MAGE", health = 5, maxHealth = 10, pct = 50 }
    ns.UF.UpdateHealth(f)
    T.eq(stub.Plain(f.health:GetValue()), 5)
    -- A trail would be a second bar; the bar style's clip frame is no bar.
    local bars = 0
    for _, child in ipairs({ f.health:GetChildren() }) do
        if child:GetObjectType() == "StatusBar" then bars = bars + 1 end
    end
    T.eq(bars, 0, "no trail bars on the health bar")
end)

local TARGET = { unit = "target", label = "Target", power = true, slant = "left", tab = true, marker = true, classification = true }
local TCFG = { width = 220, height = 50, powerHeight = 13, showName = true, showPercent = true, showMarker = true, showClassification = true, slant = true }

T.test("elite, boss and rare units get a gold or silver crest on the tab", function()
    local f, ns = make(TARGET, TCFG)
    for kind, col in pairs({ elite = "gold", worldboss = "gold", rareelite = "silver", rare = "silver" }) do
        stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = kind }
        ns.UF.UpdateIdentity(f)
        T.truthy(f.crest:IsShown(), kind)
        T.truthy(f.tabEdge:IsShown(), kind)
        T.rgb(f.crest.ring.__vertex, ns.UF.CREST_COLORS[col], kind)
    end
    local p, rel, rp = f.crest:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, f.tab); T.eq(rp, "TOPRIGHT")
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "normal" }
    ns.UF.UpdateIdentity(f)
    T.falsy(f.crest:IsShown())
    T.falsy(f.tabEdge:IsShown())
end)

T.test("the crest can be turned off and widens the tab when shown", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, classification = "normal" }
    ns.UF.UpdateIdentity(f)
    local plain = f.tab:GetWidth()
    stub.units.target.classification = "elite"
    ns.UF.UpdateIdentity(f)
    T.truthy(f.tab:GetWidth() > plain, "room for the crest")
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    cfg.showClassification = false
    ns.UF.Layout(f, cfg, ns.DEFAULTS.playerText)
    ns.UF.UpdateIdentity(f)
    T.falsy(f.crest:IsShown())
end)

T.test("long names can be cut to a set number of letters", function()
    local _, ns = stub.Load({ module = true, login = false })
    T.eq(ns.UF.LimitName("Archmage Arugal", 0), "Archmage Arugal", "0: in full (the default)")
    T.eq(ns.UF.LimitName("Archmage Arugal"), "Archmage Arugal")
    T.eq(ns.UF.LimitName("Archmage Arugal", 4), "Arch")
    T.eq(ns.UF.LimitName("Ann", 4), "Ann", "short names are left alone")
    local secret = stub.Secret("Archmage Arugal")
    T.eq(ns.UF.LimitName(secret, 4), secret, "a secret name can't be cut")
    T.eq(ns.UF.LimitName("아서스메네실", 4), "아서스메", "Korean names are cut by letters, not bytes")
end)

T.test("the name limit applies when a frame's identity is drawn", function()
    local f, ns = make(TARGET, TCFG)
    f.nameLimitLen = 3   -- the frame's own Max name length
    stub.units.target = { name = "Archmage Arugal", isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText.__text, "Arc")
end)

T.test("the raid marker sits in the tab before the name and widens it", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2 }
    ns.UF.UpdateAll(f, true)
    local plain = f.tab:GetWidth()
    stub.units.target.raidTarget = 8
    ns.UF.UpdateMarker(f)
    T.truthy(f.marker:IsShown())
    T.eq(f.marker:GetParent(), f.tab)
    T.eq(f.marker:GetTexture(), ns.UF.MARKER_SHEET, "our marker sheet")
    T.eq(stub.Plain(f.marker.__cell), 8, "the skull")
    T.truthy(f.tab:GetWidth() > plain, "room for the marker")
    local p, rel = f.marker:GetPoint(1)
    T.eq(p, "LEFT"); T.eq(rel, f.tab)
    stub.units.target.raidTarget = nil
    ns.UF.UpdateMarker(f)
    T.falsy(f.marker:IsShown())
    T.near(f.tab:GetWidth(), plain)
end)

T.test("a raid marker put on fades in; a unit swap snaps", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2 }
    ns.UF.UpdateAll(f, true)
    local d = DaylightUI.Motion.Driver and DaylightUI.Motion.Driver()
    local function run(n) d = DaylightUI.Motion.Driver(); for _ = 1, n do stub.RunOnUpdate(d, 1 / 60) end end
    stub.units.target.raidTarget = stub.Secret(8)
    ns.UF.UpdateMarker(f, true)
    T.truthy(f.marker:IsShown())
    T.eq(f.marker:GetAlpha(), 0, "from clear")
    run(3)
    T.truthy(f.marker:GetAlpha() > 0 and f.marker:GetAlpha() < 1, "fading in (FAST)")
    run(30)
    T.eq(f.marker:GetAlpha(), 1)
    stub.units.target.raidTarget = stub.Secret(nil)
    ns.UF.UpdateMarker(f, true)
    stub.units.target.raidTarget = stub.Secret(4)
    ns.UF.UpdateMarker(f)
    T.eq(f.marker:GetAlpha(), 1, "a swap (no arrive): at once")
end)

T.test("a secret marker index is still drawn", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2, raidTarget = stub.Secret(8) }
    ns.UF.UpdateAll(f, true)
    T.truthy(f.marker:IsShown())
    T.truthy(issecretvalue(f.marker.__cell), "the secret index goes straight to the sheet")
    stub.units.target.raidTarget = stub.Secret(nil)
    ns.UF.UpdateMarker(f)
    T.falsy(f.marker:IsShown(), "a secret 'no marker' shows nothing")
end)

T.test("long names cap the tab and are cut short to fit it", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Archmage Arugal The Very Long Named", isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.near(f.tab:GetWidth(), DaylightUI.Pixel.Snap(f, f:GetWidth() * ns.UF.TAB_MAX))
    T.truthy(f.nameText:GetWidth() < f.tab:GetWidth(), "name fits inside the tab")
    stub.units.target.name = "Wolf"
    ns.UF.UpdateIdentity(f)
    T.truthy(f.tab:GetWidth() < f:GetWidth() * 0.4, "short names shrink the tab again")
end)

T.test("a name tab fits the name even when the frame's own text answers a secret width", function()
    local f, ns = make(TARGET, TCFG)
    -- After a secret name, the client can answer a secret width for the
    -- frame's text though the name now shown is plain.
    f.nameText.GetStringWidth = function() return stub.Secret(28) end
    stub.units.target = { name = "Echo", isPlayer = true, reaction = 5 }
    ns.UF.UpdateIdentity(f)
    T.truthy(f.tab:GetWidth() < f:GetWidth() * 0.4, "the tab fits Echo, not half the frame")
end)

T.test("the fills' moving edges share the frame's angle", function()
    local f = make(TARGET, TCFG)
    local S = DaylightUI.Style
    local hm, pm = S.GetFillMask(f.health), S.GetFillMask(f.power)
    T.truthy(hm and hm.added); T.truthy(pm and pm.added)
    local p, rel = hm:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, f.health:GetStatusBarTexture())
    -- Same slope: cut per unit of height matches the frame's.
    local slope = f.cut / f:GetHeight()
    T.near(pm:GetWidth() / 4 / f.power:GetHeight(), slope)
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    cfg.slant = false
    local ns = select(2, stub.Load({ module = true, login = false }))
    local g = ns.UF.Create(TARGET)
    ns.UF.Layout(g, cfg, ns.DEFAULTS.playerText)
    T.falsy(S.GetFillMask(g.health) and S.GetFillMask(g.health).added)
end)

T.test("dead, ghost and offline units say so and turn gray", function()
    local f, ns = make(TARGET, TCFG)
    local S = DaylightUI.Style
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, health = 0, maxHealth = 50, pct = 0, dead = true }
    ns.UF.UpdateAll(f, true)
    T.eq(f.percentText.__text, "DEAD")
    T.rgb(f.health.__barColor, { S.Neutral() }, "grey")
    stub.units.target = { name = "Ally", isPlayer = true, class = "MAGE", health = 1, maxHealth = 50, pct = 2, ghost = true }
    ns.UF.UpdateAll(f, true)
    T.eq(f.percentText.__text, "GHOST")
    stub.units.target = { name = "Ally", isPlayer = true, class = "MAGE", health = 30, maxHealth = 50, pct = 60, offline = true }
    ns.UF.UpdateAll(f, true)
    T.eq(f.percentText.__text, "OFFLINE")
    stub.units.target.offline = false
    ns.UF.UpdateHealth(f)
    T.isnil(f.state)
    T.rgb(f.health.__barColor, { S.ClassColor("MAGE") }, "color comes back")
    T.eq(stub.Text(f.percentText), "60")
end)

T.test("NPCs never read as offline, and secret states are left alone", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, health = 20, maxHealth = 50, pct = 40, offline = true }
    ns.UF.UpdateAll(f, true)
    T.isnil(f.state)
    local real = _G.UnitIsDead
    _G.UnitIsDead = function() return stub.Secret(true) end
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, health = 0, maxHealth = 50, pct = 0 }
    ns.UF.UpdateAll(f, true)
    _G.UnitIsDead = real
    T.isnil(f.state)
end)

T.test("incoming heals and absorbs hang off the health fill, heals first", function()
    local f, ns = make(TARGET, TCFG)
    local inc, abs = stub.Secret(900), stub.Secret(400)
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = 20, maxHealth = 50, pct = 40,
                          incoming = inc, absorbs = abs }
    ns.UF.UpdateAll(f, true)
    T.eq(f.heals.__value, inc, "secret amounts go straight in")
    T.eq(f.heals.wedge.__value, inc)
    T.eq(f.absorbs.__value, abs)
    T.eq(f.heals.__max, 50)
    local p, rel, rp = f.heals:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, f.health:GetStatusBarTexture()); T.eq(rp, "TOPLEFT")
    _, rel = f.absorbs:GetPoint(1)
    T.eq(rel, f.heals:GetStatusBarTexture(), "absorbs start where heals end")
    T.eq(f.heals.wedge.__min, 0); T.eq(f.heals.wedge.__max, 1, "any amount fills the wedge")
    T.truthy(f.heals.wedge:IsShown())
    T.near(f.heals.wedge:GetWidth(), f.healthCut)
end)

T.test("heal and shield bars follow the health bar's size (laid out before it had one)", function()
    local f = make(TARGET, TCFG)
    f.health:SetWidth(0)
    f.health:GetScript("OnSizeChanged")(f.health, 0, 10)
    T.eq(f.heals:GetWidth(), 0)
    f.health:SetSize(120, 10)
    f.health:GetScript("OnSizeChanged")(f.health, 120, 10)
    T.eq(f.heals:GetWidth(), 120, "heals as long as the health bar")
    T.eq(f.absorbs:GetWidth(), 120, "shields too")
end)

T.test("prediction can be turned off per frame, and nothing comes through as nil", function()
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    cfg.predictHeals, cfg.predictAbsorbs = false, false
    local f, ns = make(TARGET, cfg)
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = 20, maxHealth = 50, pct = 40,
                          incoming = 900, absorbs = 400 }
    ns.UF.UpdateAll(f, true)
    T.falsy(f.heals:IsShown())
    T.eq(f.heals.__value, 0)
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = 20, maxHealth = 50, pct = 40 }
    f.predictHeals = true
    ns.UF.UpdatePrediction(f)
    T.eq(f.heals.__value, 0, "no heals incoming: an empty bar")
end)

T.test("the wedge's mask sits on its back side, so only the triangle shows", function()
    local f = make(TARGET, TCFG)
    local m = f.heals.wedge.mask
    local p, rel, rp = m:GetPoint(1)
    T.eq(p, "TOPRIGHT", "a bar growing left: the mask hangs off the wedge's right")
    T.eq(rel, f.heals.wedge); T.eq(rp, "TOPRIGHT")
    T.eq(m.__texture, DaylightUI.MEDIA .. "mask-trail-l.png")
    local g = make({ unit = "player", label = "Player", power = true, slant = "right", tab = true },
        { width = 220, height = 50, powerHeight = 13, showName = true, showPercent = true, slant = true })
    p = g.heals.wedge.mask:GetPoint(1)
    T.eq(p, "TOPLEFT", "growing right: off its left")
end)

-- The bar ends a frame's shell is cut with: { left = "straight"|"slash"|"backslash", right = ... }.
local function shapeOf(f)
    local S = DaylightUI.Style
    local sl = S.GetSlant(f)
    local out = {}
    for _, e in ipairs({ "left", "right" }) do
        local on = sl and sl.cut > 0 and (sl.side == e or sl.side == "both")
        local flip = sl and (sl.under == e or sl.under == "both")
        out[e] = S.EndGlyph(e, on, flip)
    end
    return out
end

T.test("bar ends: all four shapes on the player frame, each end on its own", function()
    local SPEC = { unit = "player", label = "Player", power = true, slant = "right", tab = true }
    local base = { width = 220, height = 50, powerHeight = 13, showName = true, showPercent = true, portrait = "none" }
    -- The player's inner end is its right. { inner angled, inner flipped, outer angled, outer flipped }
    local cases = {
        { "/--/", { true, false, true, true }, "slash", "slash" },
        { "\\--/", { true, false, true, false }, "backslash", "slash" },
        { "/--\\", { true, true, true, true }, "slash", "backslash" },
        { "\\--\\", { true, true, true, false }, "backslash", "backslash" },
    }
    for _, c in ipairs(cases) do
        local cfg = {}
        for k, v in pairs(base) do cfg[k] = v end
        cfg.slant, cfg.slantUnder, cfg.slantOuter, cfg.slantUnderOuter = c[2][1], c[2][2], c[2][3], c[2][4]
        local f = make(SPEC, cfg)
        local shape = shapeOf(f)
        T.eq(shape.left, c[3], c[1] .. ": left end")
        T.eq(shape.right, c[4], c[1] .. ": right end")
        -- The health fill runs toward the right end and takes its shape.
        local edge, cut, under = DaylightUI.Style.GetFillAngle(f.health)
        T.eq(edge, "right", c[1])
        T.truthy(cut > 0, c[1])
        T.eq(under == true, c[4] == "backslash", c[1] .. ": the fill's edge leans like the right end")
        T.eq(f.outerCut > 0, true, c[1] .. ": the outer end is cut")
    end
end)

T.test("bar ends: a portrait on the frame keeps the outer end straight", function()
    local f = make({ unit = "player", label = "Player", power = true, slant = "right", tab = true, portrait = true },
        { width = 220, height = 50, powerHeight = 13, showName = true, slant = true, slantOuter = true,
          portrait = "class", portraitScale = 1 })
    T.eq(shapeOf(f).left, "straight", "the ring covers it")
    T.eq(f.outerCut, 0)
end)

T.test("bar ends: a reversed fill takes the outer end's shape", function()
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    -- The target: inner end left, outer end right flipped (\), filling from the inner end.
    cfg.slantOuter, cfg.slantUnderOuter, cfg.reverseFill = true, true, true
    local f = make(TARGET, cfg)
    local edge, cut, under = DaylightUI.Style.GetFillAngle(f.health)
    T.eq(edge, "right", "reversed, it runs toward the outer end")
    T.truthy(cut > 0)
    T.eq(under, true)
    cfg.slantOuter = false
    f = make(TARGET, cfg)
    T.isnil((DaylightUI.Style.GetFillAngle(f.health)), "a straight outer end: a square edge")
end)

T.test("bar ends: on a flipped end, heals, shields, overheal and overshield lean with it, in a fight", function()
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    -- The target's inner end (left) flipped, the outer end angled too: /--/.
    cfg.slantUnder, cfg.slantOuter, cfg.slantUnderOuter = true, true, false
    cfg.dotTint = true
    local spec = {}
    for k, v in pairs(TARGET) do spec[k] = v end
    spec.dots = true
    local f, ns = make(spec, cfg)
    stub.EnterCombat()
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = stub.Secret(20), maxHealth = stub.Secret(50),
                          pct = stub.Secret(40), incoming = stub.Secret(900), absorbs = stub.Secret(400) }
    ns.UF.UpdateAll(f, true)
    local S = DaylightUI.Style
    local edge, cut, under = S.GetFillAngle(f.health)
    T.eq(edge, "left"); T.eq(under, true)
    for _, s in ipairs({ f.heals, f.absorbs }) do
        local e2, c2, u2 = S.GetFillAngle(s)
        T.eq(e2, edge); T.near(c2, cut); T.eq(u2, true, "the segment's edge is flipped too")
        -- The wedge fills the triangle the flipped edge leaves: the left end's
        -- trail turned round, which is the right end's cut image.
        T.eq(s.wedge.mask.__texture, DaylightUI.MEDIA .. "mask-slant-r.png")
        T.truthy(s.wedge:IsShown())
        for _, tex in ipairs({ s:GetStatusBarTexture(), s.wedge:GetStatusBarTexture() }) do
            T.truthy(#(tex.__masks or {}) <= 3)
        end
    end
    -- The overheal past the frame's end is cut by that end: the left end leans under.
    local clipped = false
    for _, m in ipairs(f.heals:GetStatusBarTexture().__masks or {}) do
        if m.__texture == DaylightUI.MEDIA .. "mask-trail-r.png" then clipped = true end
    end
    T.truthy(clipped, "overheal is cut along the flipped end")
    -- The overshield and its line stay inside both ends.
    T.eq(#(f.overshield:GetStatusBarTexture().__masks or {}), 2)
    -- Class layers and the DoT veil fit in three masks with both ends angled.
    T.truthy(#(f.dotVeil.bar:GetStatusBarTexture().__masks or {}) <= 3)
end)

T.test("bar ends: on a flipped end the cost shade and druid mana lean with the power fill", function()
    local f = make({ unit = "player", label = "Player", power = true, slant = "right", tab = true },
        { width = 220, height = 50, powerHeight = 13, showName = true, slant = true, slantUnder = true,
          slantOuter = true, costPreview = true })
    local S = DaylightUI.Style
    local e, c, u = S.GetFillAngle(f.power)
    T.eq(e, "right"); T.eq(u, true)
    local e2, _, u2 = S.GetFillAngle(f.cost)
    T.eq(e2, e); T.eq(u2, true)
    local e3, c3, u3 = S.GetFillAngle(f.altMana)
    T.eq(e3, e); T.eq(u3, true); T.truthy(c3 > 0 and c3 < c)
    T.truthy(#(f.cost:GetStatusBarTexture().__masks or {}) <= 3)
end)

T.test("power text shows on the power bar when turned on", function()
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    cfg.showPowerText = true
    local f, ns = make(TARGET, cfg)
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, power = 1234, maxPower = 2000, powerToken = "MANA" }
    ns.UF.UpdateAll(f, true)
    T.truthy(f.powerText:IsShown())
    T.eq(f.powerText.__text, "1.2K", "shortened like the health value")
    local p, rel = f.powerText:GetPoint(1)
    T.eq(p, "LEFT", "the target's inner end"); T.eq(rel, f.power)
    local g = make(TARGET, TCFG)
    T.falsy(g.powerText:IsShown(), "off by default")
end)

T.test("druids in a form get a thin mana strip; everyone else doesn't", function()
    local spec = { unit = "player", label = "Player", power = true, slant = "right", tab = true }
    local cfg = { width = 220, height = 50, powerHeight = 13, showName = true, showPercent = true, slant = true, druidMana = true }
    local f, ns = make(spec, cfg)
    stub.units.player = { name = "Bear", isPlayer = true, class = "DRUID", powerToken = "RAGE", power = 20, maxPower = 100,
                          mana = 700, maxMana = 1000 }
    ns.UF.UpdatePower(f, true)
    T.truthy(f.altMana:IsShown())
    T.eq(f.altMana.__value, 700); T.eq(f.altMana.__max, 1000)
    T.truthy(f.altMana:GetHeight() < f.power:GetHeight())
    stub.units.player.powerToken = "MANA"
    ns.UF.UpdatePower(f, true)
    T.falsy(f.altMana:IsShown(), "caster form: the bar is mana already")
    stub.units.player = { name = "War", isPlayer = true, class = "WARRIOR", powerToken = "RAGE", power = 20, maxPower = 100 }
    ns.UF.UpdatePower(f, true)
    T.falsy(f.altMana:IsShown(), "not a druid")
end)

-- Spell cost preview: a player on mana (type 0) casting spell 123.
local function costFrame(cfg)
    local spec = { unit = "player", label = "Player", power = true, slant = "right", tab = true }
    cfg = cfg or {}
    local f, ns = make(spec, { width = 220, height = 50, powerHeight = 13, showName = true, showPercent = true,
                               costPreview = cfg.costPreview, slant = true })
    stub.units.player = { name = "Mage", isPlayer = true, class = "MAGE", powerToken = "MANA", powerType = 0,
                          power = 900, maxPower = 1000 }
    stub.spellCosts = { [123] = { { type = 0, name = "MANA", cost = 50 } } }
    return f, ns
end

T.test("a cast shades the power it will use, and stops when the cast ends", function()
    local f = costFrame({ costPreview = true })
    T.falsy(f.cost:IsShown())
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.truthy(f.cost:IsShown())
    T.eq(f.cost.__value, 50); T.eq(f.cost.__max, 1000)
    for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }) do
        stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
        T.truthy(f.cost:IsShown())
        stub.FireEvent(e, "player", "guid", 123)
        T.falsy(f.cost:IsShown(), e)
    end
    stub.spellCosts = nil
end)

-- A hunter's Aimed Shot: Auto Shot lands (its own SUCCEEDED) and a key pressed
-- mid-cast fails ("another action is in progress") while the cast runs on.
-- Only the end of this cast may take its shade away.
T.test("the cost shade stays for the whole cast while other casts end around it", function()
    local f = costFrame({ costPreview = true })
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "aimed", 123)
    T.truthy(f.cost:IsShown())
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "auto", 75)
    T.truthy(f.cost:IsShown(), "Auto Shot landing mid-cast")
    stub.FireEvent("UNIT_SPELLCAST_FAILED", "player", "other", 1978)
    T.truthy(f.cost:IsShown(), "another spell refused mid-cast")
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    T.truthy(f.cost:IsShown(), "an action bar refresh")
    T.eq(f.cost.__value, 50)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "aimed", 123)
    T.falsy(f.cost:IsShown(), "the cast itself ending")
    stub.spellCosts = nil
end)

T.test("the cost preview ignores other power types and missing data", function()
    local f = costFrame({ costPreview = true })
    stub.spellCosts = { [123] = { { type = 1, name = "RAGE", cost = 20 } } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.falsy(f.cost:IsShown(), "other power type")
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 999)
    T.falsy(f.cost:IsShown(), "no cost")
    stub.spellCosts = { [123] = { { type = 0, name = "MANA", cost = 50 } } }
    local keep = C_Spell.GetSpellPowerCost
    C_Spell.GetSpellPowerCost = nil
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.falsy(f.cost:IsShown(), "API missing")
    C_Spell.GetSpellPowerCost = keep
    stub.spellCosts = nil
end)

T.test("a secret cost goes straight to the bar; the option can turn it off", function()
    local f = costFrame({ costPreview = true })
    local s = stub.Secret(50)
    stub.spellCosts = { [123] = { { type = 0, name = "MANA", cost = s } } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.truthy(f.cost:IsShown())
    T.truthy(f.cost.__value == s, "passed through untouched")
    local g = costFrame({ costPreview = false })
    stub.spellCosts = { [123] = { { type = 0, name = "MANA", cost = 50 } } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.falsy(g.cost:IsShown(), "off")
    stub.spellCosts = nil
end)

-- A warrior on rage (type 1) with Heroic Strike (78) costing 15.
local function rageFrame()
    local f, ns = costFrame({ costPreview = true })
    stub.units.player = { name = "War", isPlayer = true, class = "WARRIOR", powerToken = "RAGE", powerType = 1,
                          power = 60, maxPower = 100 }
    stub.spellCosts = { [78] = { { type = 1, name = "RAGE", cost = 15 } },
                        [123] = { { type = 1, name = "RAGE", cost = 10 } } }
    return f, ns
end

T.test("a queued Heroic Strike shades its rage until the swing lands or it is canceled", function()
    local f = rageFrame()
    stub.swing.current["Heroic Strike"] = true
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    T.truthy(f.cost:IsShown())
    T.eq(f.cost.__value, 15); T.eq(f.cost.__max, 100)
    stub.swing.current["Heroic Strike"] = nil
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 78)
    T.falsy(f.cost:IsShown(), "swing landed")
    stub.swing.current["Heroic Strike"] = true
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    stub.swing.current["Heroic Strike"] = nil
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    T.falsy(f.cost:IsShown(), "cancelled")
    stub.spellCosts = nil
end)

T.test("a cast wins over a queued attack, then the queued one comes back", function()
    local f = rageFrame()
    stub.swing.current["Heroic Strike"] = true
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    T.eq(f.cost.__value, 10, "the cast")
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player", "guid", 123)
    T.eq(f.cost.__value, 15, "back to Heroic Strike")
    stub.swing.current["Heroic Strike"] = nil
    stub.spellCosts = nil
end)

T.test("a secret queued answer shows nothing", function()
    local f = rageFrame()
    local keep = C_Spell.IsCurrentSpell
    C_Spell.IsCurrentSpell = function() return stub.Secret(true) end
    stub.FireEvent("ACTIONBAR_UPDATE_STATE")
    T.falsy(f.cost:IsShown())
    C_Spell.IsCurrentSpell = keep
    stub.spellCosts = nil
end)

T.test("only the player frame has a cost preview", function()
    local f = make(TARGET, TCFG)
    T.falsy(f.cost)
end)

T.test("a disconnect shows OFFLINE straight away", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = 30, maxHealth = 50, pct = 60 }
    ns.UF.UpdateAll(f, true)
    ns.UF.Wire(f)
    stub.units.target.offline = true
    stub.FireEvent("UNIT_CONNECTION", "target")
    T.eq(f.percentText.__text, "OFFLINE")
end)

T.test("the raid marker sits inside the tab, past its angled cut", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, raidTarget = 8 }
    ns.UF.UpdateAll(f, true)
    local p, rel, rp, x = f.marker:GetPoint(1)
    T.eq(p, "LEFT"); T.eq(rel, f.tab); T.eq(rp, "LEFT")
    T.truthy(x > 0, "inward from the target's inner (left) end")
    local g = make({ unit = "focus", label = "Focus", power = true, slant = "right", tab = true, marker = true },
        { width = 180, height = 40, powerHeight = 8, showName = true, showPercent = true, showMarker = true, slant = true })
    stub.units.focus = { name = "Pal", isPlayer = true, class = "MAGE", raidTarget = 4 }
    ns.UF.UpdateAll(g, true)
    p, rel, rp, x = g.marker:GetPoint(1)
    T.eq(p, "RIGHT"); T.truthy(x < 0, "inward from the focus's inner (right) end")
end)

T.test("an overshield: the shield past the missing health runs back over the health, lit, shown by the client's secret flag", function()
    local f, ns = make(TARGET, TCFG)
    local fits, over, total = stub.Secret(30), stub.Secret(true), stub.Secret(45)
    _G.Enum.UnitDamageAbsorbClampMode = { MissingHealth = 1 }
    local mode
    _G.CreateUnitHealPredictionCalculator = function()
        return { SetDamageAbsorbClampMode = function(_, m) mode = m end,
                 GetDamageAbsorbs = function() return fits, over end }
    end
    _G.UnitGetDetailedHealPrediction = function() end
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = 20, maxHealth = 50, pct = 40,
                          incoming = 0, absorbs = total }
    ns.UF.UpdatePrediction(f)
    T.eq(mode, 1, "clamped to the health missing")
    T.eq(f.absorbs.__value, fits, "the part that fits hangs off the health")
    local o = f.overshield
    T.eq(o.__value, total, "the whole shield over the health, from the frame's end")
    T.eq(o.__alphaFromBoolean[1], over, "shown by the client's flag, never read")
    T.eq(o.__reverse, false, "the target grows left, so its overshield fills from the left end")
    _G.CreateUnitHealPredictionCalculator, _G.UnitGetDetailedHealPrediction = nil, nil
    f.healCalc = nil
    ns.UF.UpdatePrediction(f)
    T.eq(f.absorbs.__value, total, "no calculator: the whole shield, as before")
    T.eq(o:GetAlpha(), 0, "and no overshield")
end)

-- A player report: a Healing Stream Totem on focus (5 health, full) drew a
-- heal bar a whole frame long past its end, over the next frame. The game
-- caps heal overflow (MAX_INCOMING_HEAL_OVERFLOW) and its calculator does it
-- for secret amounts. An overheal still shows, a quarter bar at most.
T.test("an overheal shows past the health's end, capped by the client at a quarter of the bar", function()
    local f, ns = make(TARGET, TCFG)
    local raw, fits = stub.Secret(900), stub.Secret(30)
    _G.Enum.UnitDamageAbsorbClampMode = { MissingHealth = 1 }
    _G.Enum.UnitIncomingHealClampMode = { MissingHealth = 0, MaximumHealth = 1 }
    local mode, overflow
    _G.CreateUnitHealPredictionCalculator = function()
        return { SetDamageAbsorbClampMode = function() end,
                 SetIncomingHealClampMode = function(_, m) mode = m end,
                 SetIncomingHealOverflowPercent = function(_, v) overflow = v end,
                 GetIncomingHeals = function() return fits end,
                 GetDamageAbsorbs = function() return 0, false end }
    end
    _G.UnitGetDetailedHealPrediction = function() end
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", health = 20, maxHealth = 50, pct = 40,
                          incoming = raw, absorbs = 0 }
    ns.UF.UpdatePrediction(f)
    T.eq(mode, 0, "clamped to the health missing")
    T.eq(overflow, ns.UF.HEAL_OVERFLOW, "an overheal up to the cap")
    T.eq(ns.UF.HEAL_OVERFLOW, 1.25)
    T.eq(f.heals.__value, fits, "the capped heal, never the whole one")
    T.eq(f.heals.wedge.__value, fits)
    -- Overheal switched off: the same calculator stops at the health missing,
    -- and back on it runs past again.
    local saved = ns.UF.colors
    ns.UF.colors = { overheal = false }
    ns.UF.StylePrediction(f)
    ns.UF.UpdatePrediction(f)
    T.eq(overflow, 1, "overheal off: no heal past the health's end")
    ns.UF.colors = saved
    ns.UF.StylePrediction(f)
    ns.UF.UpdatePrediction(f)
    T.eq(overflow, ns.UF.HEAL_OVERFLOW, "back on")
    -- Shields switched off on this frame: heals still come clamped.
    f.predictAbsorbs = false
    f.heals:SetValue(0)
    ns.UF.UpdatePrediction(f)
    T.eq(f.heals.__value, fits)
    f.predictAbsorbs = true
    _G.CreateUnitHealPredictionCalculator, _G.UnitGetDetailedHealPrediction = nil, nil
    f.healCalc = nil
    ns.UF.UpdatePrediction(f)
    T.eq(f.heals.__value, raw, "no calculator: the heal as the game gives it, as before")
end)

T.test("filling upward, the overshield's line is turned to lie along the top, not squashed sideways", function()
    local up = {}
    for k, v in pairs(TCFG) do up[k] = v end
    up.fillVertical, up.slant = true, false
    local f, ns = make({ unit = "focus", label = "Focus", power = true }, up)
    local g = f.overshield.glow
    T.eq(f.health:GetOrientation(), "VERTICAL")
    T.eq(table.concat({ g:GetTexCoord() }, ","), "0,0,1,0,0,1,1,1", "the game's upright art turned on its side")
    ns.UF.Layout(f, TCFG, ns.DEFAULTS.playerText)
    T.eq(table.concat({ g:GetTexCoord() }, ","), "0,0,0,1,1,0,1,1", "back upright filling sideways")
end)

T.test("a shield looks the same whether or not it fits: both in the overshield's stripes", function()
    local f, ns = make(TARGET, TCFG)
    local O = ns.UF.OVERSHIELD
    T.eq(f.absorbs:GetStatusBarTexture().__texture, O.stripes, "the shield in the health missing")
    T.eq(f.absorbs.wedge:GetStatusBarTexture().__texture, O.stripes, "its angled end too")
    T.eq(f.overshield:GetStatusBarTexture().__texture, O.stripes, "and the part past it")
    T.eq(f.absorbs.__color and f.absorbs.__color[4] or ns.UF.PREDICTION.absorbs.alpha, O.alpha, "equally strong")
    DaylightUI:Set("general", "barTexture", "lsm:Other")
    stub.RunTimers()
    T.eq(f.absorbs:GetStatusBarTexture().__texture, O.stripes, "the Bar texture setting leaves shields striped")
end)

T.test("the Colors page's heal and shield colors and shield texture reach every bar", function()
    local f, ns = make(TARGET, TCFG)
    local UF = ns.UF
    local defaults = ns.DEFAULTS and ns.DEFAULTS.colors
    if defaults then
        T.eq(defaults.absorbStyle, "stripes", "stripes by default")
        T.eq(type(defaults.healColor), "table"); T.eq(type(defaults.absorbColor), "table")
    end
    UF.ConfigureColors({ healColor = { 1, 0, 0 }, absorbColor = { 0, 0, 1 }, absorbStyle = "plain" })
    UF.LayoutPrediction(f, nil)
    T.eq(f.heals.__barColor[1], 1, "heal color")
    T.eq(f.heals.wedge.__barColor[1], 1, "its wedge too")
    T.eq(f.absorbs.__barColor[3], 1, "shield color")
    T.eq(f.overshield.__barColor[3], 1, "the overshield follows it")
    T.eq(f.absorbs:GetStatusBarTexture().__texture, "Interface\\Buttons\\WHITE8x8", "plain shield")
    T.eq(f.absorbs.wedge:GetStatusBarTexture().__texture, "Interface\\Buttons\\WHITE8x8", "its wedge too")
    T.eq(f.overshield:GetStatusBarTexture().__texture, "Interface\\Buttons\\WHITE8x8", "and the overshield")
    UF.ConfigureColors({ absorbStyle = "lsm:NotRegistered" })
    UF.LayoutPrediction(f, nil)
    T.eq(f.absorbs:GetStatusBarTexture().__texture, UF.OVERSHIELD.stripes, "an unregistered shared bar falls back to stripes")
    T.eq(f.heals.__barColor[1], UF.PREDICTION.heals.color[1], "no saved color: the default")
    UF.ConfigureColors(nil)
end)

T.test("the overshield's own options: off, from the other end, its own color and texture", function()
    local f, ns = make(TARGET, TCFG)
    local UF = ns.UF
    local defaults = ns.DEFAULTS.colors
    T.eq(defaults.overshield, true, "on by default")
    T.eq(defaults.overshieldReverse, false, "from the frame's end by default")
    T.eq(defaults.overshieldPaint, "shield", "the shield's color by default")
    T.eq(defaults.overshieldStyle, "shield", "the shield's texture by default")
    local o = f.overshield
    UF.ConfigureColors({ absorbColor = { 0, 0, 1 }, absorbStyle = "plain" })
    UF.LayoutPrediction(f, nil)
    T.eq(o.__reverse, false, "the target grows left: from the left end")
    T.eq((o.glow:GetPoint(1)), "TOP", "its line on the fill's growing edge")
    T.eq(select(3, o.glow:GetPoint(1)), "TOPRIGHT")
    T.eq(o:GetStatusBarTexture().__texture, "Interface\\Buttons\\WHITE8x8", "follows the shield's texture")
    UF.ConfigureColors({ absorbColor = { 0, 0, 1 }, overshieldReverse = true, overshieldPaint = "custom",
                         overshieldColor = { 1, 0.5, 0 }, overshieldStyle = "stripes", absorbStyle = "plain" })
    UF.LayoutPrediction(f, nil)
    T.eq(o.__reverse, true, "turned round: from the health's other end")
    T.eq(select(3, o.glow:GetPoint(1)), "TOPLEFT", "its line on the new growing edge")
    T.eq(o.__barColor[1], 1, "its own color"); T.eq(o.__barColor[2], 0.5)
    T.eq(f.absorbs.__barColor[3], 1, "the shield keeps its own")
    T.eq(o:GetStatusBarTexture().__texture, UF.OVERSHIELD.stripes, "its own texture")
    T.eq(f.absorbs:GetStatusBarTexture().__texture, "Interface\\Buttons\\WHITE8x8", "the shield keeps its own")
    UF.ConfigureColors({ overshield = false })
    UF.LayoutPrediction(f, nil)
    T.falsy(o:IsShown(), "off: no overshield")
    T.truthy(f.absorbs:IsShown(), "the shield that fits still shows")
    UF.ConfigureColors(nil)
end)

T.test("the power text lines up under the big health number", function()
    local f, ns = make(PLAYER, { width = 187, height = 43, powerHeight = 11, showName = true, showPercent = true,
                                 bigNumber = true, showPowerText = true, slant = true })
    local _, _, _, bx = f.percentText:GetPoint(1)
    local _, _, _, px = f.powerText:GetPoint(1)
    T.near(px, bx, 0.01, "the same inset from the inner end")
end)

T.test("power text position and size options", function()
    local function build(pos, psize)
        local cfg = {}
        for k, v in pairs(TCFG) do cfg[k] = v end
        cfg.showPowerText = true; cfg.powerTextPos = pos
        local f, ns = make(TARGET, cfg)
        ns.UF.LayoutPowerExtras(f, cfg, { name = 12, percent = 11, power = psize }, cfg.slant, 0)
        return f
    end
    local f = build("inner", 0)
    T.eq((f.powerText:GetPoint(1)), "LEFT", "inner = the target's left end")
    f = build("center", 0)
    T.eq((f.powerText:GetPoint(1)), "CENTER")
    f = build("outer", 0)
    T.eq((f.powerText:GetPoint(1)), "RIGHT", "outer = the far end")
    f = build("inner", 0)
    local auto = f.powerText.__font[2]
    T.eq(auto, math.min(11, math.floor(TCFG.powerHeight * 0.85 + 0.5)), "0 = fit the bar")
    f = build("inner", 14)
    T.eq(f.powerText.__font[2], 14, "14 = 14")
end)

T.test("PvP, leader and resting icons scale with their size settings", function()
    local cfg = { width = 187, height = 43, powerHeight = 11, showName = true, portrait = "class" }
    local f, ns = make(PLAYER, cfg)
    if not f.status or not f.portrait:IsShown() then return end
    local base = f.status.icons.pvp:GetWidth()
    local c2 = {}
    for k, v in pairs(cfg) do c2[k] = v end
    c2.pvpSize, c2.leaderSize, c2.restSize = 2, 0.5, 1
    ns.UF.Layout(f, c2, ns.DEFAULTS.playerText)
    T.near(f.status.icons.pvp:GetWidth(), base * 2)
    T.near(f.status.icons.leader:GetWidth(), ns.UF.STATUS.leader.size * f.portrait:GetWidth() / 2 * 0.5)
    T.near(f.status.icons.rest:GetWidth(), ns.UF.STATUS.rest.size * f.portrait:GetWidth() / 2)
end)

T.test("another unit's power gain glides over a tick; drops and target swaps snap", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Mob", powerToken = "ENERGY", power = 20, maxPower = 100 }
    ns.UF.UpdateAll(f, true)
    T.eq(f.power:GetValue(), 20)
    stub.units.target.power = 40
    ns.UF.PollPower(f, ns.UF.POWER_POLL)
    T.eq(f.power:GetValue(), 20)
    ns.UF.PollPower(f, ns.UF.POWER_GLIDE / 2)
    T.near(f.power:GetValue(), 30)
    ns.UF.PollPower(f, ns.UF.POWER_GLIDE)
    T.eq(f.power:GetValue(), 40)
    stub.units.target.power = 10
    ns.UF.PollPower(f, ns.UF.POWER_POLL_OTHERS)
    T.eq(f.power:GetValue(), 10)
    stub.units.target.power = 90
    ns.UF.UpdateAll(f, true)
    T.eq(f.power:GetValue(), 90)
end)

T.test("anyone else's power is polled slowly (events carry it); a hidden power bar isn't polled", function()
    local f, ns = make(TARGET, TCFG)
    stub.units.target = { name = "Mob", powerToken = "ENERGY", power = 20, maxPower = 100 }
    ns.UF.UpdateAll(f, true)
    local reads, real = 0, _G.UnitPower
    _G.UnitPower = function(...) reads = reads + 1; return real(...) end
    for _ = 1, 10 do ns.UF.PollPower(f, 0.05) end   -- half a second of frames
    T.eq(reads, 2, "every 0.25 s, not every 0.05")
    f.power:Hide()
    reads = 0
    for _ = 1, 10 do ns.UF.PollPower(f, 0.05) end
    T.eq(reads, 0, "Power bar off: nothing read")
    _G.UnitPower = real
end)

T.test("power events skip a hidden power bar; it catches up when it comes back", function()
    local cfg = { width = 187, height = 43, powerHeight = 11, showPower = false }
    local f, ns = make(TARGET, cfg)
    ns.UF.Wire(f)
    stub.units.target = { name = "Mob", powerToken = "ENERGY", power = 20, maxPower = 100 }
    local reads, real = 0, _G.UnitPowerMax
    _G.UnitPowerMax = function(...) reads = reads + 1; return real(...) end
    for _ = 1, 10 do stub.FireEvent("UNIT_POWER_FREQUENT", "target") end
    T.eq(reads, 0, "Power bar off: no power read per event")
    _G.UnitPowerMax = real
    stub.units.target.power = 70
    cfg.showPower = true
    ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText)
    T.truthy(f.power:IsShown())
    T.eq(f.power.__value, 70, "back on: the current power, at once")
end)

T.test("your own power still goes straight to the bar", function()
    local f, ns = make(PLAYER, { width = 220, height = 36, powerHeight = 6 })
    stub.units.player = { name = "X", isPlayer = true, class = "ROGUE", powerToken = "ENERGY", power = 20, maxPower = 100 }
    ns.UF.UpdateAll(f, true)
    stub.units.player.power = 40
    ns.UF.PollPower(f, ns.UF.POWER_POLL)
    T.eq(f.power:GetValue(), 40)
end)

T.test("a free target cast bar gets fill direction and text size", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    DUI:Set("UnitFrames", "targetCastbar.at", "free")
    DUI:Set("UnitFrames", "targetCastbar.reverseFill", true)
    DUI:Set("UnitFrames", "targetCastbar.spell.size", 15)
    stub.RunTimers()
    local h = ns.targetCastbarFree
    T.eq(h.bar.__reverse, true, "filled right to left")
    T.eq(select(2, h.text:GetFont()), 15, "its spell name size")
end)

T.test("the player's power bar can stand on its own, with its own size and end, and come back", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local f = ns.frames.player
    local inside, bar = f.power, DaylightUIPowerBar_player
    T.truthy(bar, "built with the frame")
    T.falsy(bar:IsShown(), "inside by default")
    stub.units.player = { name = "War", isPlayer = true, class = "WARRIOR", powerToken = "RAGE", power = 30, maxPower = 100 }
    DUI:Set("UnitFrames", "player.powerAt", "free")
    DUI:Set("UnitFrames", "player.powerWidth", 240)
    DUI:Set("UnitFrames", "player.powerSlant", false)
    stub.RunTimers()
    T.truthy(bar:IsShown(), "on its own")
    T.eq(f.power, bar.set.power, "updates go to the free bar")
    T.falsy(inside:IsShown(), "the frame's own bar is gone")
    T.falsy(f.separator:IsShown())
    T.near(bar:GetWidth(), 240, 1)
    T.eq(bar.set.power.__value, 30, "filled at once")
    local hp, rel = f.health:GetPoint(2)
    T.eq(hp, "BOTTOMRIGHT"); T.eq(rel, f, "the frame is all health")
    stub.units.player.power = 55
    ns.UF.PollPower(f, ns.UF.POWER_POLL)
    T.eq(bar.set.power:GetValue(), 55, "polled like before")
    DUI:Set("UnitFrames", "player.powerAt", "inside")
    stub.RunTimers()
    T.falsy(bar:IsShown(), "back inside")
    T.eq(f.power, inside)
    T.truthy(inside:IsShown())
end)

T.test("the target's and focus's power bars can stand on their own, each with its own handle", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    for _, unit in ipairs({ "target", "focus" }) do
        local f = ns.frames[unit]
        local inside, bar = f.power, _G["DaylightUIPowerBar_" .. unit]
        T.truthy(bar, unit .. ": built with the frame")
        local key = ns.PowerBar.KeyFor(unit)
        T.truthy(key ~= ns.PowerBar.KEY, "its own mover, not the player's")
        T.eq(DUI.Movers.Get(key).frame, bar)
        T.truthy(DUI.Movers.Get(key).suspended, "no handle while inside")
        stub.units[unit] = { name = "Mob", reaction = 2, health = 50, maxHealth = 100, powerToken = "MANA", power = 30, maxPower = 100 }
        stub.FireEvent(unit == "target" and "PLAYER_TARGET_CHANGED" or "PLAYER_FOCUS_CHANGED")
        DUI:Set("UnitFrames", unit .. ".powerAt", "free")
        DUI:Set("UnitFrames", unit .. ".powerWidth", 220)
        stub.RunTimers()
        T.truthy(bar:IsShown(), unit .. ": on its own")
        T.falsy(DUI.Movers.Get(key).suspended)
        T.eq(f.power, bar.set.power, "updates go to the free bar")
        T.falsy(inside:IsShown(), "the frame's own bar is gone")
        T.near(bar:GetWidth(), 220, 1)
        T.eq(bar.set.power.__value, 30, "filled at once")
        local list = f.pieces
        T.eq(list[#list] == bar or list[2] == bar, true, "it fades with the frame")
        f:Hide()
        T.falsy(bar:IsShown(), "gone with the frame when there's no " .. unit)
        f:Show()
        T.truthy(bar:IsShown(), "back with it")
        DUI:Set("UnitFrames", unit .. ".powerAt", "inside")
        stub.RunTimers()
        T.falsy(bar:IsShown(), "back inside")
        T.eq(f.power, inside)
    end
end)

T.test("with the power bar on its own, the hung cast bar and swing bars still line up under the frame", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local f, h = ns.frames.player, ns.playerCastbar
    local function shape()
        local c = h.column
        local p, rel, rp, x, y = h:GetPoint(1)
        return { p, rel, rp, x, y, c and c.fH, f.cut, h:GetWidth(), f:GetHeight() }
    end
    local before = shape()
    T.truthy(h.column, "hung under the frame")
    DUI:Set("UnitFrames", "player.powerAt", "free")
    stub.RunTimers()
    local after = shape()
    for i = 1, 9 do T.eq(after[i], before[i], "same spot, width and angle (" .. i .. ")") end
    local border = -select(5, f.health:GetPoint(1))
    local H = f:GetHeight()
    T.near(f.healthCut, f.cut * (H - 2 * border) / H, 0.01, "the health fill's edge is the frame's line, all the way down")
end)

T.test("health text moves by its X/Y offset, and only once per layout", function()
    local cfg = { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true }
    local f, ns = make(PLAYER, cfg)
    local p0, rel0, rp0, x0, y0 = f.percentText:GetPoint(1)
    cfg.healthTextX, cfg.healthTextY = 6, -2
    ns.UF.Layout(f, cfg, ns.DEFAULTS.playerText)
    ns.UF.Layout(f, cfg, ns.DEFAULTS.playerText)
    local p, rel, rp, x, y = f.percentText:GetPoint(1)
    T.eq(f.percentText:GetNumPoints(), 1, "still one anchor")
    T.eq(p, p0); T.eq(rel, rel0); T.eq(rp, rp0)
    T.eq(x, x0 + 6, "moved right, not twice")
    T.eq(y, y0 - 2, "moved down")
end)

T.test("small health text sits at the inner end, clear of the angle", function()
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    cfg.bigNumber = false
    local f = make(TARGET, cfg)
    local p, rel, rp, x = f.percentText:GetPoint(1)
    T.eq(p, "LEFT", "target's inner end is its left"); T.eq(rel, f.health); T.eq(rp, "LEFT")
    T.eq(x >= f.cut + 4, true, "clear of the angled end")
    local pf = make(PLAYER, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    T.eq((pf.percentText:GetPoint(1)), "RIGHT", "player's inner end is its right")
end)

T.test("health text position puts it in the middle or at the outer end, nudges on top", function()
    local cfg = { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true, bigNumber = false }
    local f, ns = make(PLAYER, cfg)
    cfg.healthTextPos, cfg.healthTextX = "center", -7
    ns.UF.Layout(f, cfg, ns.DEFAULTS.playerText)
    local p, rel, rp, x = f.percentText:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, f.health); T.eq(rp, "CENTER")
    T.eq(x, -7, "the nudge moves it from the middle")
    T.eq(f.percentText:GetJustifyH(), "CENTER")
    cfg.healthTextPos, cfg.healthTextX = "outer", 0
    ns.UF.Layout(f, cfg, ns.DEFAULTS.playerText)
    p, rel, rp, x = f.percentText:GetPoint(1)
    T.eq(p, "LEFT", "player's outer end is its left"); T.eq(rp, "LEFT")
    T.eq(x, 4, "no angle to clear at the outer end")
    -- The large number goes where the position says too.
    cfg.bigNumber, cfg.healthTextPos = true, "center"
    ns.UF.Layout(f, cfg, ns.DEFAULTS.playerText)
    p, _, rp, x = f.percentText:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rp, "CENTER"); T.eq(x, 0)
end)

T.test("a tall tile's health text stays in the middle of its bottom for older profiles", function()
    local _, ns = stub.Load({ module = true, login = false })
    local uf = { groupFrames = 23, party = { height = 40, bigNumber = false }, raid = { height = 50 },
                 raid20 = { height = 20 }, raid40 = { height = 50, healthTextPos = "outer" } }
    ns.UpgradeGroupFrames({ modules = { UnitFrames = uf } })
    T.eq(uf.party.healthTextPos, "center")
    T.eq(uf.raid.healthTextPos, "center")
    T.isnil(uf.raid20.healthTextPos, "a short tile keeps the inner end")
    T.eq(uf.raid40.healthTextPos, "outer", "a pick stays")
    local fresh = { party = { height = 40, bigNumber = false } }
    ns.UpgradeGroupFrames({ modules = { UnitFrames = fresh } })
    T.isnil(fresh.party.healthTextPos, "a new profile starts at the inner end")
end)

T.test("power text moves by its X/Y offset", function()
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    cfg.showPowerText = true
    local f, ns = make(TARGET, cfg)
    local p0, rel0, _, x0, y0 = f.powerText:GetPoint(1)
    cfg.powerTextX, cfg.powerTextY = -5, 3
    ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText)
    local p, rel, _, x, y = f.powerText:GetPoint(1)
    T.eq(f.powerText:GetNumPoints(), 1)
    T.eq(p, p0); T.eq(rel, rel0)
    T.eq(x, x0 - 5); T.eq(y, y0 + 3)
end)

-- A player's error: moving the health text slider while a raid tile showed
-- secret health ("arithmetic on a secret number value", OffsetText). A text
-- showing a secret has secret anchoring, so GetPoint's offsets are secret.
T.test("health and power text nudges work while the texts show secret values", function()
    local cfg = {}
    for k, v in pairs(TCFG) do cfg[k] = v end
    cfg.showPowerText, cfg.bigNumber = true, false
    local f, ns = make(TARGET, cfg)
    stub.units.target = { name = "Boss", isPlayer = false, reaction = 2, health = stub.Secret(50),
        maxHealth = stub.Secret(100), pct = stub.Secret(50), power = stub.Secret(30), maxPower = stub.Secret(100) }
    ns.UF.UpdateAll(f)
    f.powerText:SetText(stub.Secret("30"))
    cfg.healthTextX, cfg.healthTextY, cfg.powerTextX, cfg.powerTextY = 6, -2, -5, 3
    T.noerror(function() ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText) end)
    T.eq(f.percentText:GetNumPoints(), 1)
    T.eq(f.percentText.__points[1][4], f.cut + 4 + 6, "health text nudged right")
    T.eq(f.percentText.__points[1][5], -2, "and down")
    T.eq(f.powerText:GetNumPoints(), 1)
    T.eq(f.powerText.__points[1][5], DaylightUI.Pixel.Px(f, 1) + 3, "power text nudged up")
end)

T.test("PlaceText takes a missing nudge as none", function()
    local f, ns = make(PLAYER, { width = 220, height = 36, powerHeight = 6, showName = true, showPercent = true })
    f.percentText:ClearAllPoints()
    ns.UF.PlaceText(f.percentText, "LEFT", f.health, "LEFT", 4, 2, nil, nil)
    local p, rel, rp, x, y = f.percentText:GetPoint(1)
    T.eq(p, "LEFT"); T.eq(rel, f.health); T.eq(rp, "LEFT")
    T.eq(x, 4); T.eq(y, 2)
end)

T.test("a frame's Max name length cuts its name", function()
    local f, ns = make(TARGET, { width = 220, height = 50, powerHeight = 13, showName = true, slant = true, nameLimitLen = 5 })
    stub.units.target = { name = "Archmage Arugal", isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText.__text, "Archm")
end)

T.test("name and health text colors can be set per frame", function()
    local cfg = { width = 220, height = 50, powerHeight = 13, showName = true, showPercent = true, slant = true,
        nameColor = "custom", nameCustom = { 0.1, 0.2, 0.3 }, percentColor = "custom", percentCustom = { 0.4, 0.5, 0.6 } }
    local f, ns = make(TARGET, cfg)
    stub.units.target = { name = "Grell", isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.near(f.nameText.__textColor[1], 0.1); T.near(f.percentText.__textColor[3], 0.6)
    cfg.nameColor, cfg.percentColor = "global", "white"
    ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText)
    ns.UF.UpdateIdentity(f)
    T.near(f.percentText.__textColor[1], 1)
    T.near(f.nameText.__textColor[1], ns.UF.NAME_COLOR[1])
end)

local function plainText(t) return (t:gsub("|cff%x%x%x%x%x%x", ""):gsub("|r", "")) end

T.test("names can be drawn in the class gradient, per frame or globally", function()
    local cfg = { width = 220, height = 50, powerHeight = 13, showName = true, slant = true, nameColor = "classGradient" }
    local f, ns = make(TARGET, cfg)
    local G = DaylightUI.Gradients
    stub.units.target = { name = "Grell", isPlayer = true, class = "WARRIOR" }
    ns.UF.UpdateIdentity(f)
    local t = f.nameText.__text
    T.truthy(t:find("|cff%x%x%x%x%x%x%S|r"), "letters colored")
    T.eq(plainText(t), "Grell", "same words")
    T.eq(t, G.Text("WARRIOR", "Grell"), "the warrior pair")
    T.rgb(f.nameText.__textColor, { G.Mid("WARRIOR") }, "drawn on the pair's middle")
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText.__text, G.Text("HOSTILE", "Wolf"), "an NPC gets its reaction's pair")
    cfg.nameColor = "global"
    ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText)
    ns.UF.colors = { name = "classGradient" }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText.__text, G.Text("HOSTILE", "Wolf"), "the Colors page can pick it too")
    ns.UF.colors = { name = "white" }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText.__text, "Wolf", "plain again")
end)

T.test("a class gradient name: cut first, plain when dead, solid when secret", function()
    local f, ns = make(TARGET, { width = 220, height = 50, powerHeight = 13, showName = true, slant = true,
        nameColor = "classGradient", nameLimitLen = 3 })
    local G = DaylightUI.Gradients
    stub.units.target = { name = "Archmage", isPlayer = true, class = "MAGE", health = 50, maxHealth = 50, pct = 100 }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText.__text, G.Text("MAGE", "Arc"), "the gradient spans the letters shown")
    stub.units.target = { name = "Ally", isPlayer = true, class = "MAGE", health = 0, maxHealth = 50, pct = 0, dead = true }
    ns.UF.UpdateAll(f, true)
    T.eq(f.nameText.__text, "All", "a dead unit's name is plain")
    local r, g, b = ns.UF.StateColor("dead")
    T.rgb(f.nameText.__textColor, { DaylightUI.Style.Lighten(r, g, b, 0.3) }, "in the state color")
    local secret = stub.Secret("Boss")
    stub.units.target = { name = secret, isPlayer = true, class = "MAGE", health = 50, maxHealth = 50, pct = 100 }
    ns.UF.UpdateAll(f, true)
    T.eq(f.nameText.__text, secret, "a secret name is passed through")
    T.rgb(f.nameText.__textColor, { G.Mid("MAGE") }, "in the pair's middle")
end)

T.test("test mode samples show the class gradient name", function()
    local f, ns = make(TARGET, { width = 220, height = 50, powerHeight = 13, showName = true, slant = true,
        nameColor = "classGradient" })
    f.test = { name = "Sample", class = "PRIEST", health = 80 }
    ns.UF.ShowSample(f)
    T.eq(f.nameText.__text, DaylightUI.Gradients.Text("PRIEST", "Sample"))
    f.test = { name = "Foe", reaction = 4, health = 80 }
    ns.UF.ShowSample(f)
    T.eq(f.nameText.__text, DaylightUI.Gradients.Text("NEUTRAL", "Foe"))
end)

T.test("test mode samples write power in its format", function()
    local f, ns = make(TARGET, { width = 220, height = 50, powerHeight = 13, showName = true, slant = true,
        showPower = true, showPowerText = true, powerFormat = "percent", powerPercentSign = true })
    f.test = { name = "Sample", class = "PRIEST", health = 80, power = 65, powerToken = "MANA" }
    ns.UF.ShowSample(f)
    T.eq(f.powerText.__text, "65%")
    f.powerFormat = "both"
    ns.UF.ShowSample(f)
    T.eq(f.powerText.__text, "65 | 65%")
    f.powerFormat, f.powerPercentSign = "percent", false
    ns.UF.ShowSample(f)
    T.eq(f.powerText.__text, "65")
    -- Mana samples carry a value; rage, energy and focus run 0 to 100.
    f.test.powerValue = 2080
    f.powerFormat = "full"
    ns.UF.ShowSample(f)
    T.eq(f.powerText.__text, "2,080")
    f.powerFormat = "valuemax"
    ns.UF.ShowSample(f)
    T.eq(f.powerText.__text, "2.1K / 3.2K")
    f.test.powerToken = "RAGE"
    ns.UF.ShowSample(f)
    T.eq(f.powerText.__text, "65 / 100", "rage ignores the mana value")
end)

T.test("power can be written in full, with separators", function()
    local f, ns = make(TARGET, { width = 220, height = 50, powerHeight = 13, showName = true, slant = true,
        showPower = true, showPowerText = true, powerFormat = "full" })
    stub.units.target = { name = "Mob", reaction = 2, powerToken = "MANA", power = 21000, maxPower = 30000 }
    ns.UF.UpdatePower(f, true)
    T.eq(f.powerText.__text, "21,000")
end)

T.test("tab height, portrait size and marker size are options", function()
    local cfg = { width = 220, height = 50, powerHeight = 13, showName = true, slant = true, portrait = "class",
        tabHeight = 22, portraitScale = 0.5, markerSize = 20 }
    local f, ns = make({ unit = "target", label = "Target", power = true, slant = "left", tab = true, marker = true, portrait = true }, cfg)
    T.near(f.tab:GetHeight(), 22, 0.6)
    T.eq(f.markerSize, 20)
    local small = f.portrait:GetWidth()
    cfg.portraitScale, cfg.markerSize = 1, ns.UF.MARKER_SIZE
    ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText)
    T.truthy(f.portrait:GetWidth() > small)
    T.eq(f.markerSize, nil, "the default size keeps the usual marker")
end)

T.test("the portrait ring's end of the frame has no corner caps over the ring", function()
    -- A thin border with round corners: the caps (Style.Shell's s.over,
    -- above the ring) drew black wedges into the ring.
    local cfg = { width = 187, height = 43, powerHeight = 11, showName = true, slant = true, portrait = "class",
        shell = { own = true, borderPx = 2, cornerPx = 10, shadowPx = 4 } }
    local f, ns = make({ unit = "target", label = "Target", power = true, slant = "left", tab = true, portrait = true }, cfg)
    local s = DaylightUI.Style.GetShell(f)
    T.truthy(f.portrait:IsShown())
    T.falsy(s.fillet.TOPRIGHT:IsShown(), "the ring's end: under the ring")
    T.falsy(s.fillet.BOTTOMRIGHT:IsShown())
    T.truthy(s.fillet.TOPLEFT:IsShown() or s.angled.left, "the other end keeps its own")
    cfg.portraitScale = 0.6
    ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText)
    T.truthy(s.fillet.TOPRIGHT:IsShown(), "a ring too small to reach the corner leaves it rounded")
    cfg.portrait = "none"
    ns.UF.Layout(f, cfg, ns.DEFAULTS.targetText)
    T.truthy(s.fillet.TOPRIGHT:IsShown())
end)

T.test("target of target and pet can show health text", function()
    local f = make({ unit = "targettarget", label = "ToT", compact = true, slant = "left" },
        { width = 94, height = 22, showName = true, showPercent = true, healthText = "percent", slant = true })
    T.truthy(f.percentText:IsShown())
    local _, ns = stub.Load({ module = true, login = false })
    T.eq(ns.DEFAULTS.targettarget.showPercent, false)
    T.eq(ns.DEFAULTS.pet.showPercent, false)
end)

T.test("target of target: a power bar of its own, off by default; off it isn't polled", function()
    local DUI, ns = stub.Load({ module = true })
    local f = ns.frames.targettarget
    T.truthy(f.power, "it has one")
    T.eq(DUI:Get("UnitFrames", "targettarget.showPower"), false, "off by default")
    T.falsy(f.power:IsShown())
    local function watched()
        for _, g in ipairs(ns.UF.watchedPower) do if g == f then return true end end
        return false
    end
    T.falsy(watched(), "off: not polled")
    DUI:Set("UnitFrames", "targettarget.showPower", true)
    stub.RunTimers()
    T.truthy(f.power:IsShown(), "on: shown")
    T.truthy(watched(), "and polled")
    DUI:Set("UnitFrames", "targettarget.showPower", false)
    stub.RunTimers()
    T.falsy(watched(), "off again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("focus target: its own small frame beside the focus, set up like the target of target, following the focus's target", function()
    local DUI, ns = stub.Load({ module = true })
    local f = ns.frames.focustarget
    T.truthy(f, "made")
    T.eq(f.unitToken, "focustarget")
    local _, rel = f:GetPoint(1)
    T.eq(DUI:Get("UnitFrames", "focustarget.enabled"), true, "on, as the game's own")
    T.eq(DUI:Get("UnitFrames", "focustarget.width"), DUI:Get("UnitFrames", "targettarget.width"), "the target of target's size")
    T.eq(DUI:Get("UnitFrames", "focustarget.showPower"), false)
    stub.SetUnits({ player = { name = "Me", class = "PRIEST", isPlayer = true, health = 10, maxHealth = 10 },
        focus = { name = "Tank", class = "WARRIOR", isPlayer = true, health = 10, maxHealth = 10 },
        focustarget = { name = "Ogre", reaction = 2, health = 50, maxHealth = 100 } })
    stub.FireEvent("UNIT_TARGET", "focus")
    T.eq(f.nameText.__text, "Ogre", "who your focus is looking at")
    local found
    for _, page in ipairs(ns.OPTIONS.pages) do if page.id == "focustarget" then found = page end end
    T.truthy(found, "its own options page")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("unit frames: fade through the engine and multiply with the range fade", function()
    local DUI, ns = stub.Load({ module = true })
    stub.SetUnits({ player = { name = "Me", class = "WARRIOR", isPlayer = true, health = 10, maxHealth = 10 } })
    local f = ns.frames.player
    T.eq(DUI:Get("UnitFrames", "player.fade.mode"), "never", "off by default")
    DUI:Set("UnitFrames", "player.fade.mode", "ooc")
    DUI:Set("UnitFrames", "player.fade.delay", 0)
    stub.Advance(3)
    DUI.Fade.Step()
    for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    T.eq(f:GetAlpha(), 0, "out of combat: faded")
    T.eq(f.fadeNow, 0, "painted through UF.PaintFade")
    stub.EnterCombat()
    for _ = 1, 30 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    T.eq(f:GetAlpha(), 1, "a fight brings it back")
    stub.LeaveCombat()
end)

T.test("unit frames: frames that only show with your target have no Show with a target", function()
    local DUI, ns = stub.Load({ module = true })
    local function fadeRow(pageId, field)
        for _, page in ipairs(ns.OPTIONS.pages) do
            if page.id == pageId then
                for _, g in ipairs(page.groups) do
                    for _, item in ipairs(g.items or {}) do
                        if item.key == pageId .. ".fade." .. field then return item end
                    end
                end
            end
        end
    end
    local get = function(k) return DUI:Get("UnitFrames", k) end
    for _, id in ipairs({ "target", "targettarget" }) do
        for _, field in ipairs({ "target", "targetEnemy" }) do
            local row = fadeRow(id, field)
            T.truthy(row, id .. " still has the row for the Fade page's lookups")
            T.truthy(row and row.hidden and row.hidden(get), id .. ": " .. field .. " hidden")
        end
        T.falsy(fadeRow(id, "mouseover").hidden, id .. ": the other rows stay")
    end
    for _, id in ipairs({ "player", "focus", "pet" }) do
        local row = fadeRow(id, "target")
        T.truthy(row and not (row.hidden and row.hidden(get)), id .. ": Show with a target stays")
    end
    -- The Fade page's copies follow the area's own rule.
    local hub = DUI.Fade.HubGroups()
    for _, card in ipairs(hub) do
        for _, item in ipairs(card.items) do
            if item.label == "Settings for" and item.choices then
                local values = item.choices()
                for id in pairs(values) do
                    if id == "UnitFrames:target.fade." then
                        item.set(id)
                        for _, row in ipairs(card.items) do
                            if row.label == "Show with a target" or row.label == "Only enemies" then
                                T.truthy(row.hidden(), "Fade page: " .. row.label .. " hidden for the target frame")
                            end
                        end
                    end
                end
            end
        end
    end
end)

T.test("upgrade 25: Show with a target on the target frame becomes Always", function()
    local _, ns = stub.Load({ module = true })
    local p = { modules = { UnitFrames = { groupFrames = 24,
        target = { fade = { mode = "ooc", target = true } },
        targettarget = { fade = { mode = "always", target = true, targetEnemy = true } },
        focus = { fade = { mode = "ooc", target = true } } } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(p)
    local uf = p.modules.UnitFrames
    T.eq(uf.target.fade.mode, "never", "it was always shown at its opacity: now it says so")
    T.isnil(uf.target.fade.target)
    T.eq(uf.targettarget.fade.mode, "never", "only enemies: kept shown, so an enemy never fades")
    T.isnil(uf.targettarget.fade.target); T.isnil(uf.targettarget.fade.targetEnemy)
    T.eq(uf.focus.fade.mode, "ooc", "the focus frame's means your target: left alone")
    T.eq(uf.focus.fade.target, true)
    local q = { modules = { UnitFrames = { groupFrames = 24, target = { fade = { mode = "ooc" } } } }, positions = {}, general = {} }
    ns.UpgradeGroupFrames(q)
    T.eq(q.modules.UnitFrames.target.fade.mode, "ooc", "without it, the fade is untouched")
end)

T.test("unit frames: player and pet can fade only at full health", function()
    local DUI, ns = stub.Load({ module = true })
    -- As in the client: health is secret even out of combat, so the game
    -- reads it through a curve (UnitHealthPercent) and hands back a secret.
    local function hp(v) return rawget(v, "__value") end
    local units = { player = { name = "Me", class = "WARRIOR", isPlayer = true, health = stub.Secret(10), maxHealth = 10 },
                    pet = { name = "Wolf", health = stub.Secret(10), maxHealth = 10 } }
    stub.SetUnits(units)
    local saved = { curves = _G.C_CurveUtil, pct = _G.UnitHealthPercent }
    _G.C_CurveUtil = { CreateCurve = function()
        local c = { pts = {} }
        function c:AddPoint(x, y) self.pts[#self.pts + 1] = { x, y } end
        function c:Eval(x)
            for i = 2, #self.pts do
                local a, b = self.pts[i - 1], self.pts[i]
                if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
            end
            return self.pts[#self.pts][2]
        end
        return c
    end }
    _G.UnitHealthPercent = function(u, _, curve)
        local x = units[u]
        return stub.Secret(curve:Eval(hp(x.health) / x.maxHealth))
    end
    local function alpha(f)
        local a = f:GetAlpha()
        if type(a) == "table" then return hp(a) end
        return a
    end
    local function setHealth(u, v)
        units[u].health = stub.Secret(v)
        stub.FireEvent("UNIT_HEALTH", u)
    end
    local function run() for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end end
    local function settle(secs)
        stub.Advance(secs or 3)
        DUI.Fade.Step()
        run()
    end
    local ok, err = pcall(function()
        T.eq(DUI:Get("UnitFrames", "player.fade.fullHealth"), false, "off by default")
        T.eq(DUI:Get("UnitFrames", "pet.fade.fullHealth"), false, "pet: off by default")
        for _, u in ipairs({ "player", "pet" }) do
            DUI:Set("UnitFrames", u .. ".fade.mode", "always")
            DUI:Set("UnitFrames", u .. ".fade.delay", 2)
            DUI:Set("UnitFrames", u .. ".fade.fullHealth", true)
        end
        local f, pet = ns.frames.player, ns.frames.pet
        settle()
        T.eq(alpha(f), 0, "full health (secret): faded")
        setHealth("player", 6)
        settle(0)
        T.eq(alpha(f), 1, "a hit brings it back")
        settle()
        T.eq(alpha(f), 1, "hurt and steady: stays shown past the delay")
        T.eq(alpha(pet), 0, "the pet goes by its own health")
        setHealth("pet", 3)
        settle()
        T.eq(alpha(pet), 1, "pet hurt: shown")
        setHealth("player", 10)
        settle(0)
        settle(1)
        T.eq(alpha(f), 1, "healed to full: waits for the delay")
        settle()
        T.eq(alpha(f), 0, "then fades")
        DUI:Set("UnitFrames", "player.fade.opacity", 0.5)
        setHealth("player", 6)
        settle()
        T.near(alpha(f), 0.5, 1e-6, "hurt with opacity 50%: back to 50%, not full")
        setHealth("player", 10)
        settle(0)
        settle()
        T.eq(alpha(f), 0, "full again: fades from there")
        DUI:Set("UnitFrames", "player.fade.opacity", 1)
        DUI:Set("UnitFrames", "player.fade.fullHealth", false)
        setHealth("player", 6)
        settle()
        T.eq(alpha(f), 0, "switched off: fades whatever the health")
    end)
    _G.C_CurveUtil, _G.UnitHealthPercent = saved.curves, saved.pct
    if not ok then error(err, 0) end
end)

T.test("unit frames: the player frame can fade only at full mana", function()
    local DUI, ns = stub.Load({ module = true })
    -- Mana is plain out of a fight and secret in one (and under restrictions),
    -- where the game reads it through a curve (UnitPowerPercent).
    local function plain(v) if type(v) == "table" then return rawget(v, "__value") end return v end
    local me = { name = "Me", class = "MAGE", isPlayer = true, health = stub.Secret(10), maxHealth = 10,
                 powerType = 0, powerToken = "MANA", mana = 100, maxMana = 100, power = 100, maxPower = 100 }
    stub.SetUnits({ player = me })
    local saved = { curves = _G.C_CurveUtil, pct = _G.UnitPowerPercent, hpct = _G.UnitHealthPercent, kinds = Enum.PowerType }
    Enum.PowerType = Enum.PowerType or { Mana = 0, Rage = 1 }   -- as in the client
    _G.C_CurveUtil = { CreateCurve = function()
        local c = { pts = {} }
        function c:AddPoint(x, y) self.pts[#self.pts + 1] = { x, y } end
        function c:Eval(x)
            for i = 2, #self.pts do
                local a, b = self.pts[i - 1], self.pts[i]
                if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
            end
            return self.pts[#self.pts][2]
        end
        return c
    end }
    _G.UnitPowerPercent = function(u, kind, _, curve)
        local x = stub.units[u]
        if kind == 0 then return curve:Eval(x.mana / x.maxMana) end
        return curve:Eval(x.power / x.maxPower)
    end
    _G.UnitHealthPercent = function(u, _, curve)
        local x = stub.units[u]
        return stub.Secret(curve:Eval(plain(x.health) / x.maxHealth))
    end
    stub.WrapSecrets()
    local function alpha(f) return plain(f:GetAlpha()) end
    local function setMana(v, kind)
        me.mana, me.power = v, v
        stub.FireEvent("UNIT_POWER_UPDATE", "player", kind or "MANA")
    end
    local function run() for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end end
    local function settle(secs)
        stub.Advance(secs or 3)
        DUI.Fade.Step()
        run()
    end
    local ok, err = pcall(function()
        T.eq(DUI:Get("UnitFrames", "player.fade.fullMana"), false, "off by default")
        DUI:Set("UnitFrames", "player.fade.mode", "always")
        DUI:Set("UnitFrames", "player.fade.delay", 2)
        DUI:Set("UnitFrames", "player.fade.fullMana", true)
        local f = ns.frames.player
        settle()
        T.eq(alpha(f), 0, "full mana: faded")
        setMana(40)
        settle(0)
        T.eq(alpha(f), 1, "a spell's cost brings it back")
        settle()
        T.eq(alpha(f), 1, "short on mana and steady: stays shown past the delay")
        setMana(100)
        settle(0)
        settle(1)
        T.eq(alpha(f), 1, "refilled: waits for the delay")
        settle()
        T.eq(alpha(f), 0, "then fades")

        -- A free power bar is part of the frame: it waits for the mana too.
        DUI:Set("UnitFrames", "player.powerAt", "free")
        settle()
        local bar = f.pieces[2]
        setMana(40)
        settle()
        T.eq(alpha(bar), 1, "its own power bar stays with it")
        setMana(100)
        settle()
        T.eq(alpha(bar), 0, "and fades with it")
        DUI:Set("UnitFrames", "player.powerAt", "inside")

        -- In a fight mana is secret: the game's curve decides, nothing compared.
        stub.EnterCombat()
        setMana(40)
        settle()
        T.eq(ns.manaShort.player, nil, "in a fight mana reads secret: never compared")
        T.eq(alpha(f), 1, "in a fight, short on mana (secret): shown")
        setMana(100)
        settle()
        T.eq(alpha(f), 0, "in a fight, full mana (secret): faded")
        -- With full health on too (some players' mana reads secret out of a
        -- fight as well): health takes the curve, mana waits by its changes.
        DUI:Set("UnitFrames", "player.fade.fullHealth", true)
        setMana(40)
        settle(0)
        T.eq(alpha(f), 1, "both waits on, secret mana: a spell's cost brings it back")
        settle(ns.MANA_QUIET - 2)
        T.eq(alpha(f), 1, "still changing within the quiet time: stays shown")
        setMana(100)
        settle(ns.MANA_QUIET + 3)
        T.eq(alpha(f), 0, "both waits on, secret mana gone quiet and full health: faded")
        me.health = stub.Secret(5)
        stub.FireEvent("UNIT_HEALTH", "player")
        settle()
        T.eq(alpha(f), 1, "both waits on, hurt: shown by the health curve")
        me.health = stub.Secret(10)
        stub.FireEvent("UNIT_HEALTH", "player")
        stub.LeaveCombat()
        settle()
        T.eq(alpha(f), 0, "out of the fight, full health and mana: faded")
        DUI:Set("UnitFrames", "player.fade.fullHealth", false)

        -- No mana on the bar (a warrior, a druid in a form): nothing to wait for.
        me.powerType, me.powerToken, me.maxPower = 1, "RAGE", 100
        stub.FireEvent("UNIT_DISPLAYPOWER", "player")
        setMana(40, "RAGE")
        settle()
        T.eq(alpha(f), 0, "rage on the bar: fades as usual")
        me.powerType, me.powerToken = 0, "MANA"

        DUI:Set("UnitFrames", "player.fade.fullMana", false)
        setMana(40)
        settle()
        T.eq(alpha(f), 0, "switched off: fades whatever the mana")
    end)
    _G.C_CurveUtil, _G.UnitPowerPercent, _G.UnitHealthPercent = saved.curves, saved.pct, saved.hpct
    Enum.PowerType = saved.kinds
    if not ok then error(err, 0) end
end)

T.test("role icons: each role is its own quarter of our roles sheet", function()
    local _, ns = make(TARGET, TCFG)
    T.eq(ns.UF.ROLE_ICON_TEXTURE, DaylightUI.MEDIA .. "roles.png")
    T.eq(table.concat(ns.UF.ROLE_COORDS.TANK, ","), "0,0.5,0,0.5")
    T.eq(table.concat(ns.UF.ROLE_COORDS.HEALER, ","), "0.5,1,0,0.5")
    T.eq(table.concat(ns.UF.ROLE_COORDS.DAMAGER, ","), "0,0.5,0.5,1")
end)

T.test("power: one event per change, not two (UNIT_POWER_UPDATE is a slower copy of UNIT_POWER_FREQUENT)", function()
    stub.Load({ module = true })
    local f = DaylightUIFrame_player
    T.truthy(f:IsEventRegistered("UNIT_POWER_FREQUENT"))
    T.falsy(f:IsEventRegistered("UNIT_POWER_UPDATE"))
end)

T.test("unit frames: a frame's own border, corners and shadow; off follows General", function()
    local DUI, ns = stub.Load({ module = true })
    local S = DaylightUI.Style
    local f = ns.frames.target
    local s = S.GetShell(f)
    T.isnil(s.opts.borderPx, "General's by default")
    DUI:Set("UnitFrames", "target.shell.own", true)
    DUI:Set("UnitFrames", "target.shell.borderPx", 2)
    DUI:Set("UnitFrames", "target.shell.cornerPx", 0)
    DUI:Set("UnitFrames", "target.shell.shadowPx", 9)
    stub.RunTimers()
    T.eq(s.opts.borderPx, 2); T.eq(s.opts.cornerPx, 0); T.eq(s.opts.shadowPx, 9)
    T.eq(S.BorderPx(f), 2, "the bars sit inside the new border")
    T.isnil(S.GetShell(ns.frames.player).opts.borderPx, "only that frame")
    T.eq(S.GetShell(f.tab).opts.borderPx, ns.UF.TAB_BORDER(2), "its name tab half of it")
    DUI:Set("UnitFrames", "target.shell.own", false)
    stub.RunTimers()
    T.isnil(s.opts.borderPx, "back to General's")
end)

T.test("unit frames: the name tab's own border, corners and shadow, worn by the threat tag too", function()
    local DUI, ns = stub.Load({ module = true })
    local S = DaylightUI.Style
    local f = ns.frames.target
    local ts = S.GetShell(f.tab)
    T.isnil(ts.opts.shadowPx, "General's shadow by default")
    DUI:Set("UnitFrames", "target.tab.own", true)
    DUI:Set("UnitFrames", "target.tab.borderPx", 1)
    DUI:Set("UnitFrames", "target.tab.cornerPx", 12)
    DUI:Set("UnitFrames", "target.tab.shadowPx", 0)
    stub.RunTimers()
    T.eq(ts.opts.borderPx, 1); T.eq(ts.opts.cornerPx, 12); T.eq(ts.opts.shadowPx, 0)
    local tag = S.GetShell(f.threatTag)
    T.eq(tag.opts.cornerPx, 12, "the threat tag matches the name tab")
    T.isnil(S.GetShell(f).opts.cornerPx, "the frame keeps General's")
    T.isnil(S.GetShell(ns.frames.player.tab).opts.shadowPx, "only that frame's tab")
    DUI:Set("UnitFrames", "target.tab.own", false)
    stub.RunTimers()
    T.isnil(ts.opts.shadowPx, "back to the frame's")
    T.eq(ts.opts.borderPx, ns.UF.TAB_BORDER, "half the frame's border again")
end)

T.test("unit frames: the name tab's color: dark, your class, the accent or a picked one", function()
    local DUI, ns = stub.Load({ module = true })
    local S = DaylightUI.Style
    local ts = S.GetShell(ns.frames.target.tab)
    T.isnil(ts.opts.bgColor, "dark like the frame by default")
    T.eq(ts.bg.__color[1], S.BACKGROUND[1])
    DUI:Set("UnitFrames", "target.tab.color", "custom")
    DUI:Set("UnitFrames", "target.tab.colorCustom", { 0.9, 0.2, 0.5 })
    stub.RunTimers()
    T.eq(ts.bg.__color[1], 0.9, "the picked color, as it is")
    T.eq(ts.bg.__color[3], 0.5)
    DUI:Set("UnitFrames", "target.tab.color", "accent")
    stub.RunTimers()
    local r = S.Accent()
    T.near(ts.bg.__color[1], r * ns.UF.TAB_TINT, 1e-6, "the accent, darkened for the name")
    DUI:Set("UnitFrames", "target.tab.color", "class")
    stub.RunTimers()
    T.truthy(ts.opts.bgColor ~= nil, "your class color")
    T.isnil(S.GetShell(ns.frames.player.tab).opts.bgColor, "only that frame's tab")
    DUI:Set("UnitFrames", "target.tab.color", "dark")
    stub.RunTimers()
    T.isnil(ts.opts.bgColor, "dark again")
    T.eq(ts.bg.__color[1], S.BACKGROUND[1])
end)

T.test("unit frames: the name tab sits outer, middle or inner, nudged, and slides up from its lifted spot", function()
    local DUI, ns = stub.Load({ module = true })
    local f = ns.frames.target   -- angled on the left: its outer end is the right
    local function at() local p, rel, rp, x, y = f.tab:GetPoint(1) return p, rel, rp, x, y end
    local p, rel, rp = at()
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, f); T.eq(rp, "TOPRIGHT")
    DUI:Set("UnitFrames", "target.tab.at", "middle")
    DUI:Set("UnitFrames", "target.tab.x", 7)
    DUI:Set("UnitFrames", "target.tab.y", 5)
    stub.RunTimers()
    local x, y
    p, rel, rp, x, y = at()
    T.eq(p, "BOTTOM"); T.eq(rp, "TOP"); T.eq(x, 7)
    T.truthy(y > 3, "lifted: " .. y)
    T.eq(ns.UF.TabDrop(f), f.tabHeight + 1 + 5, "slides from behind the body")
    local box = ns.AuraGroups.Box(f, {})
    T.eq(box.above, f.tabHeight + 5, "rows over the frame clear the lifted tab")
    DUI:Set("UnitFrames", "target.tab.at", "inner")
    DUI:Set("UnitFrames", "target.tab.x", 0)
    stub.RunTimers()
    p, rel, rp, x = at()
    T.eq(p, "BOTTOMLEFT"); T.eq(rp, "TOPLEFT")
    T.eq(x, f.cut, "clear of the angled end")
    p, rel = f.threatTag:GetPoint(1)
    T.eq(rel, f.tab, "the threat tag steps outward of it")
end)

T.test("unit frames: the name tab fits the name, the whole top or a fixed width; the name to one side", function()
    local DUI, ns = stub.Load({ module = true })
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.tab.width", "fixed")
    DUI:Set("UnitFrames", "player.tab.widthPx", 120)
    stub.RunTimers()
    T.near(f.tab:GetWidth(), 120, 1)
    DUI:Set("UnitFrames", "player.tab.width", "full")
    DUI:Set("UnitFrames", "player.tab.at", "middle")
    stub.RunTimers()
    T.near(f.tab:GetWidth(), f:GetWidth() - f.tabInset - f.cut, 1)
    T.eq(f.tabAt, "outer", "a full-width tab starts at the outer end")
    DUI:Set("UnitFrames", "player.tab.align", "left")
    stub.RunTimers()
    local p, rel = f.nameText:GetPoint(1)
    T.eq(p, "LEFT"); T.eq(rel, f.tab)
    T.eq(f.nameText:GetJustifyH(), "LEFT")
end)

T.test("unit frames: the name tab's angled end follows the frame, or its own pick", function()
    local DUI, ns = stub.Load({ module = true })
    local S = DaylightUI.Style
    local f = ns.frames.player
    T.truthy(S.GetSlant(f.tab).side, "angled like the frame")
    DUI:Set("UnitFrames", "player.tab.slant", "off")
    stub.RunTimers()
    T.falsy(S.GetSlant(f.tab).side, "straight")
    DUI:Set("UnitFrames", "player.tab.slant", "on")
    DUI:Set("UnitFrames", "player.slant", false)
    stub.RunTimers()
    T.truthy(S.GetSlant(f.tab).side, "angled though the frame is straight")
end)

T.test("unit frames: raid tiles each get their own shell options (aggro colors never leak)", function()
    local _, ns = stub.Load({ module = true })
    local S = DaylightUI.Style
    local a = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton1", ns.Raid.header)
    a:SetAttribute("unit", "raid1")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, a:GetName())
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton2", ns.Raid.header)
    b:SetAttribute("unit", "raid2")
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    stub.RunTimers()
    T.truthy(S.GetShell(a).opts ~= S.GetShell(b).opts, "one table each")
    T.eq(S.GetShell(a).opts.borderPx, ns.UF.TAB_BORDER, "the tiles' half border, as before")
end)

T.test("unit frames: the pet's name goes outside its frame at a spot; its page offers the spots", function()
    local DUI, ns = stub.Load({ module = true })
    stub.units.pet = { name = "Grezzik", reaction = 5, level = 10, health = 80, maxHealth = 100 }
    local f = ns.frames.pet
    DUI:Set("UnitFrames", "pet.namePos", "above")
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    local p, rel, rp, _, y = f.nameText:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, f.health); T.eq(rp, "TOP")
    T.truthy(y > 0, "above the frame, not on its bar")
    local found
    for _, g in ipairs(DUI.Options.GetPage("UnitFrames.pet").groups) do
        for _, it in ipairs(g.items) do if it.key == "pet.namePos" then found = it end end
    end
    T.truthy(found, "a Name position row on the Pet page")
end)

T.test("unit frames: the pet's name stays on its bar by default; Name on the bar off puts it in a tab above, like the others", function()
    local DUI, ns = stub.Load({ module = true })
    stub.units.pet = { name = "Grezzik", reaction = 5, level = 10, health = 80, maxHealth = 100 }
    local f = ns.frames.pet
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    T.falsy(f.tab:IsShown(), "no tab by default")
    T.eq(f.nameText:GetParent(), f.overlay, "the name on the bar, as it always was")
    local _, rel = f.nameText:GetPoint(1)
    T.eq(rel, f.health, "across the bar")
    DUI:Set("UnitFrames", "pet.nameOnBar", false)
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    T.truthy(f.tab:IsShown(), "the tab shows")
    T.eq(f.nameText:GetParent(), f.tab, "the name in it")
    T.eq(f.nameText:GetText(), "Grezzik")
    local p, rel2, rp = f.tab:GetPoint(1)
    T.eq(rel2, f, "on the frame")
    T.truthy(p:find("^BOTTOM") and rp:find("^TOP"), "sitting on its top edge")
    T.eq(f.tab:GetHeight(), 14, "the pet's own tab height")
    T.truthy(f.tab:GetWidth() <= f:GetWidth(), "no wider than the frame")
    local card
    for _, g in ipairs(DUI.Options.GetPage("UnitFrames.pet").groups) do
        if g.label == "Name tab" then card = g end
    end
    T.truthy(card, "the Name tab card on the Pet page")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Every frame's name settings are on a Name tab of their own, apart from its health and power
-- texts, and the name tab's card sits with them.
T.test("unit frames: each frame has a Name tab with its name rows, and Text keeps the rest", function()
    local DUI = stub.Load({ module = true })
    local NAME = { showName = true, nameColor = true, nameLimitLen = true, namePos = true, nameX = true, nameY = true }
    local TEXTY = { showPercent = true, healthText = true, showPowerText = true }
    local function field(it) return type(it.key) == "string" and string.match(it.key, "%.([^%.]+)$") end
    for _, id in ipairs({ "player", "target", "focus", "party", "arena", "targettarget", "focustarget", "partyTarget", "pet", "raid" }) do
        local page = DUI.Options.GetPage("UnitFrames." .. id)
        T.truthy(page, id .. " has its page")
        local nameCard, textCard, tabCard
        for _, g in ipairs(page.groups) do
            if g.label == "Name" then nameCard = g elseif g.label == "Text" then textCard = g elseif g.label == "Name tab" then tabCard = g end
        end
        T.truthy(nameCard, id .. ": a Name card")
        T.eq(nameCard.tab, "Name", id .. ": on the Name tab")
        if tabCard then T.eq(tabCard.tab, "Name", id .. ": the name tab's card sits with it") end
        local found = {}
        for _, it in ipairs(nameCard.items) do found[field(it) or ""] = true end
        T.truthy(found.showName and found.nameColor and found.nameLimitLen, id .. ": the name's rows are there")
        if textCard then
            T.eq(textCard.tab, "Text")
            for _, it in ipairs(textCard.items) do
                T.falsy(NAME[field(it) or ""], id .. ": " .. tostring(it.key) .. " left the Text card")
            end
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Each cast bar's settings are on its frame's page, under a Cast bar tab, and the Cast Bars page
-- keeps what every bar shares.
T.test("unit frames: a Cast bar tab on the player, target, focus and party pages", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    local BAR = { player = "playerCastbar", target = "targetCastbar", focus = "focusCastbar", party = "partyCastbar" }
    for id, bar in pairs(BAR) do
        local page = O.GetPage("UnitFrames." .. id)
        local keys, tabs = {}, {}
        for _, g in ipairs(page.groups) do
            if g.tab == "Cast bar" then
                tabs[#tabs + 1] = g.label
                for _, it in ipairs(g.items) do if it.key then keys[it.key] = true end end
            end
        end
        T.truthy(#tabs >= 2, id .. ": its cast bar and its text")
        T.truthy(keys[bar .. ".enabled"] and keys[bar .. ".at"] and keys[bar .. ".height"], id .. ": the bar's own rows")
        T.truthy(keys[bar .. ".spell.size"] and keys[bar .. ".time.size"], id .. ": and its text sizes")
    end
    -- The test shows the casts while one of these pages is open.
    for id in pairs(BAR) do
        if id == "player" then goto skip end
        local shows = false
        for _, part in ipairs(O.GetPage("UnitFrames." .. id).preview or {}) do shows = shows or part == "castbars" end
        T.truthy(shows, id .. ": the test shows its cast bar")
        ::skip::
    end
    -- The player's cast bar border says whose it is, apart from the frame's own.
    local labels = {}
    for _, g in ipairs(O.GetPage("UnitFrames.player").groups) do labels[g.label] = (labels[g.label] or 0) + 1 end
    T.eq(labels["Border and shadow"], 1, "the frame's border card, once")
    T.eq(labels["Cast bar border and shadow"], 1, "the cast bar's own")
    -- The Cast Bars page has only what is shared: no bar's own rows.
    for _, g in ipairs(O.GetPage("UnitFrames.castbars").groups) do
        for _, it in ipairs(g.items) do
            T.falsy(type(it.key) == "string" and string.match(it.key, "^%a+Castbar%.at$"), "no bar's position row on the shared page")
        end
    end
    -- Design mode's Options button for a cast bar lands on that setting of its frame's page.
    local page, key = DUI.Movers.OptionsOf("unitframes.targetCastbar")
    T.eq(page, "UnitFrames.target")
    T.eq(key, "targetCastbar.at")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("unit frames: the target's name on the bar goes to any spot, nudged; in its tab it stays", function()
    local DUI, ns = stub.Load({ module = true })
    stub.units.target = { name = "Bandit", reaction = 2, level = 12, health = 50, maxHealth = 100, marker = 8 }
    local f = ns.frames.target
    DUI:Set("UnitFrames", "target.nameOnBar", true)
    DUI:Set("UnitFrames", "target.namePos", "topleft")
    DUI:Set("UnitFrames", "target.nameX", 5)
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    local p, rel, rp, x = f.nameText:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, f.health); T.eq(rp, "TOPLEFT")
    T.truthy(x >= 5, "nudged")
    local mp, mrel = f.marker:GetPoint(1)
    T.eq(mp, "RIGHT"); T.eq(mrel, f.nameText, "the marker rides before the name")
    -- Beside the portrait: the old spot, with the nudge.
    DUI:Set("UnitFrames", "target.namePos", "bar")
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    local _, rel2, _, x2 = f.nameText:GetPoint(1)
    T.eq(rel2, f.health)
    T.isnil(f.tileName, "not named like a tile")
    T.truthy(x2 ~= 0)
end)

T.test("unit frames: Design mode drags the name tab along the top, the name itself on the bar", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.target")
    P.SetDesign(true)
    local function namePart()
        for _, h in ipairs(P.Strip().Hotspots()) do if h.part.label == "Name" then return h.part end end
    end
    T.truthy(namePart(), "the name tab is a part")
    T.eq(namePart().move.spotKey, "target.tab.at", "in its tab the tab moves")
    T.eq(#namePart().move.dots, 3, "outer, middle, inner")
    DUI:Set("UnitFrames", "target.nameOnBar", true)
    stub.RunTimers()
    P.Refresh()
    T.truthy(namePart().move, "on the bar it does")
    T.eq(namePart().move.spotKey, "target.namePos")
end)

-- A raid fight sends UNIT_POWER_FREQUENT for every tile hundreds of times a
-- second: only the value moves; the color and max wait for their own events.
T.test("a power tick moves the value only; the color and max come with their own events", function()
    local f, ns = make(TARGET, TCFG)
    ns.UF.Wire(f)
    stub.units.target = { name = "Mob", powerToken = "ENERGY", power = 20, maxPower = 100 }
    ns.UF.UpdateAll(f, true)
    local paints, maxes = 0, 0
    local paint, setMax = ns.UF.PaintPower, f.power.SetMinMaxValues
    ns.UF.PaintPower = function(...) paints = paints + 1; return paint(...) end
    f.power.SetMinMaxValues = function(...) maxes = maxes + 1; return setMax(...) end
    stub.units.target.power = 10
    for _ = 1, 5 do stub.FireEvent("UNIT_POWER_FREQUENT", "target") end
    T.eq(paints, 0, "no repaint per tick")
    T.eq(maxes, 0, "no max per tick")
    T.eq(f.power:GetValue(), 10, "a drop still lands at once")
    stub.units.target.powerToken, stub.units.target.maxPower = "RAGE", 120
    stub.FireEvent("UNIT_DISPLAYPOWER", "target")
    T.eq(paints, 1, "a new power type repaints")
    T.truthy(maxes >= 1, "and sets the max")
    ns.UF.PaintPower, f.power.SetMinMaxValues = paint, nil
end)

T.test("only your own frame runs a power script every frame; everyone else's share one driver", function()
    local f, ns = make(TARGET, TCFG)
    local p = ns.UF.Create(PLAYER)
    T.truthy(p.__scripts.OnUpdate, "yours polls every frame")
    T.isnil(f.__scripts.OnUpdate, "the target has no script of its own")
    local found = false
    for _, w in ipairs(ns.UF.watchedPower) do if w == f then found = true end end
    T.truthy(found, "watched by the shared driver")
    -- A gain glides through the driver and stops when it lands.
    stub.units.target = { name = "Mob", powerToken = "ENERGY", power = 20, maxPower = 100 }
    ns.UF.UpdateAll(f, true)
    stub.units.target.power = 40
    ns.UF.PollOnce(f)
    T.truthy(ns.UF.glidingPower[f], "gliding")
    local driver
    for _, fr in ipairs(stub.frames) do
        if fr.__scripts and fr.__scripts.OnUpdate and debug.getinfo(fr.__scripts.OnUpdate, "S").source:find("UnitFrames.lua", 1, true)
            and fr ~= p then driver = fr end
    end
    T.truthy(driver, "one shared driver")
    stub.RunOnUpdate(driver, ns.UF.POWER_GLIDE / 2)
    T.near(f.power:GetValue(), 30)
    stub.RunOnUpdate(driver, ns.UF.POWER_GLIDE)
    stub.RunOnUpdate(driver, 0.01)
    T.eq(f.power:GetValue(), 40)
    -- Hidden mid-glide: it lands at once and leaves the list.
    stub.units.target.power = 80
    ns.UF.PollOnce(f)
    T.truthy(ns.UF.glidingPower[f], "gliding again")
    f:Hide()
    stub.RunOnUpdate(driver, 0.01)
    T.eq(f.power:GetValue(), 80, "landed while hidden")
    T.isnil(ns.UF.glidingPower[f], "a hidden frame stops gliding")
    T.isnil(ns.UF.glidingPower[f], "done gliding: off the list")
end)

T.test("floating mode: a health change wakes its frame or group; power wakes nothing", function()
    local _, ns = stub.Load({ module = true, login = false })
    local woke = {}
    local wake = DaylightUI.Fade.Wake
    DaylightUI.Fade.Wake = function(key) woke[#woke + 1] = key end
    local f = ns.UF.Create(PLAYER)
    ns.UF.Layout(f, { width = 220, height = 36, powerHeight = 6 }, ns.DEFAULTS.playerText)
    ns.UF.Wire(f)
    stub.units.player = { name = "X", isPlayer = true, class = "MAGE", health = 7, maxHealth = 9, power = 5, maxPower = 10 }
    stub.FireEvent("UNIT_HEALTH", "player")
    stub.FireEvent("UNIT_POWER_FREQUENT", "player")
    T.eq(table.concat(woke, " "), "UnitFrames.player", "your health, not the mana/energy ticks or rage draining")
    woke = {}
    local g = ns.UF.Create(PLAYER)
    g.group = { key = "party" }
    ns.UF.Wire(g)
    stub.FireEvent("UNIT_POWER_FREQUENT", "player")
    T.eq(#woke, 0, "power wakes no frame")
    woke = {}
    stub.FireEvent("UNIT_HEALTH", "player")
    T.eq(table.concat(woke, " "), "UnitFrames.player UnitFrames.party", "health: the group too")
    DaylightUI.Fade.Wake = wake
end)

-- Each frame's own Power bar switch (player, target, focus, party, pet,
-- raid): off, that frame is all health; the others keep theirs.
T.test("a frame's Power bar switch off: all health there, the others keep theirs", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local UF = ns.UF
    for _, unit in ipairs({ "player", "target", "focus" }) do
        T.eq(DUI:Get("UnitFrames", unit .. ".showPower"), true, unit .. ": on by default")
        DUI:Set("UnitFrames", unit .. ".showPower", false)
        stub.RunTimers()
        local f = ns.frames[unit]
        T.falsy(f.power:IsShown(), unit .. ": no power bar")
        T.falsy(f.separator:IsShown(), unit .. ": no line over it")
        T.falsy(UF.ShowsPower(DUI:Get("UnitFrames", unit)), unit)
    end
    local p, rel = ns.frames.player.health:GetPoint(2)
    T.eq(rel, ns.frames.player, "the health bar takes the frame down to its bottom")
    T.eq(p, "BOTTOMRIGHT")
    T.truthy(ns.frames.pet.power:IsShown(), "the pet keeps its own")
    T.truthy(UF.ShowsPower(DUI:Get("UnitFrames", "party")))
    T.truthy(UF.ShowsPower(DUI:Get("UnitFrames", "raid")))
    DUI:Set("UnitFrames", "player.showPower", true)
    stub.RunTimers()
    T.truthy(ns.frames.player.power:IsShown(), "back on")
    T.falsy(ns.frames.target.power:IsShown(), "the target's own switch still counts")
end)

T.test("power bar off: a cast asked to sit inside the frame sits below it, never lost", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local CB = ns.CastBar
    local tc, fc = DUI:Get("UnitFrames", "targetCastbar"), DUI:Get("UnitFrames", "focusCastbar")
    T.eq(CB.At("target", tc), "power")
    T.eq(CB.At("focus", fc), "power")
    DUI:Set("UnitFrames", "target.showPower", false)
    DUI:Set("UnitFrames", "focus.showPower", false)
    stub.RunTimers()
    T.eq(CB.At("target", tc), "below")
    T.eq(CB.At("focus", fc), "below")
    T.falsy(ns.targetCastbar.enabled, "the one inside the frame stands down")
    T.truthy(ns.targetCastbarFree.enabled, "the bar of its own takes over")
    T.truthy(ns.focusCastbarFree.enabled)
    T.eq(DUI:Get("UnitFrames", "targetCastbar.at"), tc.at, "the pick stays")
    DUI:Set("UnitFrames", "target.showPower", true)
    stub.RunTimers()
    T.eq(CB.At("target", tc), "power", "back inside when the bar is back")
end)

T.test("power bar on its own: a cast asked to sit inside the frame sits below it", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local CB = ns.CastBar
    local tc, fc = DUI:Get("UnitFrames", "targetCastbar"), DUI:Get("UnitFrames", "focusCastbar")
    DUI:Set("UnitFrames", "target.powerAt", "free")
    DUI:Set("UnitFrames", "focus.powerAt", "free")
    stub.RunTimers()
    T.eq(CB.At("target", tc), "below")
    T.eq(CB.At("focus", fc), "below")
    T.falsy(ns.targetCastbar.enabled, "nothing left inside the frame to cover")
    T.truthy(ns.targetCastbarFree.enabled, "the bar of its own takes over")
    T.truthy(ns.focusCastbarFree.enabled)
    DUI:Set("UnitFrames", "target.powerAt", "inside")
    stub.RunTimers()
    T.eq(CB.At("target", tc), "power", "back inside when the power bar is")
end)

T.test("power bar off: what rides on the bar goes with it", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local f = ns.frames.player
    stub.units.player = { name = "X", isPlayer = true, class = "DRUID", powerToken = "ENERGY", power = 20, maxPower = 100 }
    DUI:Set("UnitFrames", "player.showPowerText", true)
    stub.RunTimers()
    ns.UF.UpdatePower(f, true)
    T.truthy(f.altMana:IsShown(), "a form shows the druid's mana strip")
    T.truthy(f.powerText:IsShown())
    T.truthy(f.costPreview)
    DUI:Set("UnitFrames", "player.showPower", false)
    stub.RunTimers()
    ns.UF.UpdatePower(f, true)
    T.falsy(f.altMana:IsShown(), "no mana strip floating over the health")
    T.falsy(f.powerText:IsShown(), "no power number where the bar was")
    T.falsy(f.costPreview, "no cost shade")
    T.falsy(f.cost:IsShown())
    DUI:Set("UnitFrames", "player.showPower", true)
    stub.RunTimers()
    ns.UF.UpdatePower(f, true)
    T.truthy(f.altMana:IsShown())
    T.truthy(f.powerText:IsShown())
    T.truthy(f.costPreview)
end)

T.test("power bar off: a power bar on its own goes too, and its unlock handle with it", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    DUI:Set("UnitFrames", "player.powerAt", "free")
    stub.RunTimers()
    local h, key = ns.frames.player.freePower, ns.PowerBar.KEY
    T.truthy(h:IsShown())
    T.falsy(DUI.Movers.Get(key).suspended)
    DUI:Set("UnitFrames", "player.showPower", false)
    stub.RunTimers()
    T.falsy(h:IsShown())
    T.truthy(DUI.Movers.Get(key).suspended, "no handle for a bar that isn't there")
    DUI:Set("UnitFrames", "player.showPower", true)
    stub.RunTimers()
    T.truthy(h:IsShown())
    T.falsy(DUI.Movers.Get(key).suspended)
end)

-- The cost shade's fill has its own angled lead and back edges. Clipped at both
-- ends too it would need four masks, and a texture takes three.
T.test("a power bar on its own angled at both ends keeps its cost shade to three masks", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    DUI:Set("UnitFrames", "player.powerAt", "free")
    stub.RunTimers()
    local pb = ns.frames.player.freePower
    -- The fake game doesn't size a bar from its anchors; the angle needs a height.
    pb.set.power:SetHeight(11)
    for _, flip in ipairs({ false, true, false }) do
        DUI:Set("UnitFrames", "player.powerSlantUnder", flip)
        DUI:Set("UnitFrames", "player.powerSlantBoth", true)
        stub.RunTimers()
        T.eq(DUI.Style.GetSlant(pb).side, "both")
        DUI:Set("UnitFrames", "player.powerSlantBoth", false)
        stub.RunTimers()
        DUI:Set("UnitFrames", "player.powerSlantBoth", true)
        stub.RunTimers()
    end
    T.truthy(DUI.Style.GetFillAngle(pb.set.cost), "the shade's edge is angled")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("power bar off: the Ribbon line goes and nothing keeps room for it", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    ns.SetStyle("look.style", "ribbon")
    stub.RunTimers()
    local f = ns.frames.player
    T.truthy(f.line:IsShown())
    T.truthy(f.foot > 0)
    DUI:Set("UnitFrames", "player.showPower", false)
    DUI:Set("UnitFrames", "party.showPower", false)
    stub.RunTimers()
    T.falsy(f.line:IsShown())
    T.eq(f.foot, 0)
    local _, down = ns.UF.StyleReach(DUI:Get("UnitFrames", "party"), f)
    T.eq(down, 0, "the party's holder takes no line in")
end)

T.test("every frame page has its own Power bar switch, and its power rows dim with it", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local O = DUI.Options
    local function row(pageId, label)
        for _, g in ipairs(O.GetPage(pageId).groups) do
            for _, it in ipairs(g.items) do
                if it.label == label then return it end
            end
        end
    end
    local get = function(key) return DUI:Get("UnitFrames", key) end
    for _, page in ipairs({ "player", "target", "focus", "party", "pet", "raid" }) do
        local r = row("UnitFrames." .. page, "Power bar")
        T.truthy(r, page .. ": a Power bar switch")
        T.eq(r.key, page .. ".showPower", page)
    end
    for _, label in ipairs({ "Power bar height", "Power text", "Druid mana in forms" }) do
        T.falsy(row("UnitFrames.player", label).disabled(get), label)
    end
    T.falsy(row("UnitFrames.player", "Spell cost preview").disabled(get))
    DUI:Set("UnitFrames", "player.showPower", false)
    for _, label in ipairs({ "Power bar height", "Power text", "Druid mana in forms" }) do
        T.truthy(row("UnitFrames.player", label).disabled(get), label)
    end
    T.falsy(row("UnitFrames.target", "Power bar height").disabled(get), "the target's own rows stay")
    T.truthy(row("UnitFrames.player", "Spell cost preview").disabled(get))
    DUI:Set("UnitFrames", "personal.enabled", true)
    T.falsy(row("UnitFrames.player", "Spell cost preview").disabled(get), "it still shades the personal display's bar")
end)

T.test("upgrade: the old every-frame power switch off turns each frame's own off", function()
    local _, ns = stub.Load({ module = true })
    local uf = { look = { showPower = false }, pet = { width = 90 } }
    ns.UPGRADE_STEPS[16](uf)
    for _, key in ipairs({ "player", "target", "focus", "pet", "party", "partyPet", "raid", "raid20", "raid40" }) do
        T.eq(uf[key].showPower, false, key)
    end
    T.eq(uf.pet.width, 90, "the rest of a frame's settings stay")
    T.eq(uf.look.showPower, nil, "the old switch is gone")
    local on = { look = { showPower = true } }
    ns.UPGRADE_STEPS[16](on)
    T.eq(on.player, nil, "on: nothing written")
    T.eq(on.look.showPower, nil)
end)

-- A player's hunter pet at 1080p: the default 8 px border is 8 UI units at
-- the pixel-perfect scale, and a 20-high frame with a 4-high power bar kept
-- nothing for the health (only the power bar showed).
T.test("unitframes: a thick border never eats a small frame's health bar", function()
    local _, ns = stub.Load({ module = true, login = false })
    stub.SetScreen(1920, 1080, 768 / 1080)
    local f = ns.UF.Create({ unit = "pet", label = "Pet", compact = true, power = true, slant = "right" })
    local cfg = { width = 94, height = 20, powerHeight = 4, showPower = true, showName = true }
    ns.UF.Layout(f, cfg, ns.DEFAULTS.petText)
    local Pixel, Style = DaylightUI.Pixel, DaylightUI.Style
    local T_ = Pixel.Px(f, Style.BorderPx(f))
    T.near(T_, 8, 0.01, "8 px = 8 units here")
    local health = f:GetHeight() - 2 * T_ - f.power:GetHeight() - Pixel.Px(f, Style.SEPARATOR_PX)
    T.truthy(health >= ns.UF.MIN_HEALTH - 0.01, "room left for the health: " .. health)
    -- With room to spare the frame keeps its own height.
    cfg.height = 40
    ns.UF.Layout(f, cfg, ns.DEFAULTS.petText)
    T.near(f:GetHeight(), 2 * Pixel.Snap(f, 20), 0.01, "its own 40")
end)

T.test("missing health opacity: the empty part of health and power, and the frame's dark inside, thin together", function()
    stub.AlphaRule = true    -- a texture's one alpha, as in game
    local ok, err = pcall(function()
        local DUI, ns = stub.Load({ module = true })
        stub.RunTimers()
        local Style = DUI.Style
        stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50, power = 50, maxPower = 100 }
        for _, u in ipairs({ "player" }) do ns.UF.UpdateAll(ns.frames[u], true) end
        local f = ns.frames.player
        local back = Style.BarBack(f.health)
        local s = Style.GetShell(f)
        T.near(back:GetAlpha(), Style.BAR_BACK_ALPHA, 0.001, "as ever by default")
        T.isnil(s.opts.bgAlpha, "the frame's own background as ever")
        for _, key in ipairs({ "player", "target", "party", "raid" }) do
            local g = ns.frames[key]
            if type(g) == "table" and g.GetObjectType and Style.GetShell(g) then T.isnil(Style.GetShell(g).opts.bgAlpha, key .. " untouched by default") end
        end
        DUI:Set("UnitFrames", "colors.backAlpha", 0)
        stub.RunTimers()
        T.near(back:GetAlpha(), 0, 0.001, "see-through")
        if f.power then T.near(Style.BarBack(f.power):GetAlpha(), 0, 0.001, "the power bar's too") end
        T.eq(s.opts.bgAlpha, 0, "the frame's dark inside goes with it")
        T.near(s.bg.__color[4], 0, 0.001, "painted at once")
        DUI:Set("UnitFrames", "colors.backAlpha", 0.4)
        stub.RunTimers()
        T.near(back:GetAlpha(), 0.4, 0.001, "the opacity picked")
        T.eq(s.opts.bgAlpha, 0.4)
        DUI:Set("UnitFrames", "colors.backAlpha", 0.8)
        stub.RunTimers()
        T.isnil(s.opts.bgAlpha, "back to the usual")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end)
    stub.AlphaRule = nil
    if not ok then error(err, 0) end
end)

T.test("a frame's own bar background: color and opacity per frame, health and power apart", function()
    stub.AlphaRule = true    -- a texture's one alpha, as in game
    local ok, err = pcall(function()
        local DUI, ns = stub.Load({ module = true })
        stub.RunTimers()
        local Style = DUI.Style
        stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50, power = 50, maxPower = 100 }
        stub.units.target = { name = "Them", isPlayer = true, class = "ROGUE", health = 50, maxHealth = 100, pct = 50 }
        for _, u in ipairs({ "player", "target" }) do ns.UF.UpdateAll(ns.frames[u], true) end
        local f, t = ns.frames.player, ns.frames.target
        local back, tback = Style.BarBack(f.health), Style.BarBack(t.health)
        DUI:Set("UnitFrames", "player.backHealth", "custom")
        DUI:Set("UnitFrames", "player.backHealthColor", { 0.2, 0.1, 0.3 })
        DUI:Set("UnitFrames", "player.backHealthAlpha", 1)
        stub.RunTimers()
        local c = back.__vertex
        T.near(c[1], 0.2, 0.001, "its own color")
        T.near(c[3], 0.3, 0.001)
        T.near(c[4], 1, 0.001, "painted solid")
        T.near(back:GetAlpha(), 1, 0.001, "its own opacity, fully solid")
        T.near(tback:GetAlpha(), Style.BAR_BACK_ALPHA, 0.001, "the target keeps the shared look")
        T.near(tback.__vertex[4], Style.BAR_BACK_ALPHA, 0.001)
        if f.power then
            local p = Style.BarBack(f.power)
            T.near(p.__vertex[4], Style.BAR_BACK_ALPHA, 0.001, "power still follows the Colors page")
            DUI:Set("UnitFrames", "player.backPower", "dim")
            DUI:Set("UnitFrames", "player.backPowerAlpha", 0.3)
            stub.RunTimers()
            T.near(p:GetAlpha(), 0.3, 0.001, "power's own opacity")
            T.near(back:GetAlpha(), 1, 0.001, "health keeps its own")
            T.eq(Style.GetShell(f).opts.bgAlpha, 0.3, "the dark inside thins under the lowest")
        end
        -- Dark health mode: an own look wins over the full unit color.
        DUI:Set("UnitFrames", "player.colorHealth", "dark")
        stub.RunTimers()
        T.near(back.__vertex[1], 0.2, 0.001, "dark mode keeps the frame's own color")
        DUI:Set("UnitFrames", "player.backHealth", "global")
        DUI:Set("UnitFrames", "player.backPower", "global")
        stub.RunTimers()
        T.near(back:GetAlpha(), Style.BAR_BACK_ALPHA, 0.001, "shared again")
        T.near(back.__vertex[4], Style.BAR_BACK_ALPHA, 0.001)
        T.isnil(Style.GetShell(f).opts.bgAlpha)
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end)
    stub.AlphaRule = nil
    if not ok then error(err, 0) end
end)

-- In a restricted instance names read secret and can't be cut by letters: the
-- target of target showed "Sandfury Shadowhunter" whole with a limit of 8. The
-- name's text gets the width of that many letters instead.
T.test("a secret name keeps to the Max name length by width", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "targettarget.namePos", "above")
    DUI:Set("UnitFrames", "targettarget.nameLimitLen", 8)
    local f = ns.frames.targettarget
    stub.units.targettarget = { name = "Sandfury Shadowhunter", isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText.__text, "Sandfury", "a plain name is cut by letters")
    T.eq(f.nameText:GetWidth(), 0, "and needs no width")
    stub.units.targettarget = { name = stub.Secret("Sandfury Shadowhunter"), isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.truthy(issecretvalue(f.nameText.__text), "a secret name goes in whole")
    local w = f.nameText:GetWidth()
    T.truthy(w > 8 * 7 - 1 and w < 8 * 7 + 6, "as wide as 8 letters, the client cuts the rest: " .. tostring(w))
    stub.units.targettarget = { name = "Ann", isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText:GetWidth(), 0, "a plain name again: no width")
    DUI:Set("UnitFrames", "targettarget.nameLimitLen", 0)
    stub.units.targettarget = { name = stub.Secret("Sandfury Shadowhunter"), isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(f)
    T.eq(f.nameText:GetWidth(), 0, "no limit: whole")
    -- A frame with a name tab: the tab keeps to the limit too.
    DUI:Set("UnitFrames", "target.nameLimitLen", 4)
    local t = ns.frames.target
    stub.units.target = { name = stub.Secret("Sandfury Shadowhunter"), isPlayer = false, reaction = 2 }
    ns.UF.UpdateIdentity(t)
    T.truthy(t.tab:GetWidth() < t:GetWidth() * 0.5, "narrower than a secret name's usual half")
    T.truthy(t.nameText:GetWidth() < 4 * 7 + 6, "the name as wide as 4 letters")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's ask: the power bar as tall as the health, side by side with the
-- portrait between them. The power slider stopped at 20 while health went to 80.
T.test("the power bar height goes as high as the frame's height, and lays out that tall", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local O = DUI.Options
    local function row(pageId, label)
        for _, g in ipairs(O.GetPage(pageId).groups) do
            for _, it in ipairs(g.items) do
                if it.label == label then return it end
            end
        end
    end
    for _, page in ipairs({ "player", "target", "focus", "party" }) do
        local h, p = row("UnitFrames." .. page, "Height"), row("UnitFrames." .. page, "Power bar height")
        T.truthy(h and p, page)
        T.eq(p.max, h.max, page .. ": power goes as high as health")
    end
    T.eq(ns.DEFAULTS.player.powerHeight, 11, "the default stays")
    DUI:Set("UnitFrames", "player.powerAt", "free")
    DUI:Set("UnitFrames", "player.powerHeight", 43)
    stub.RunTimers()
    local bar = DaylightUIPowerBar_player
    T.truthy(bar and bar:IsShown(), "the free power bar shows")
    T.truthy(bar:GetHeight() >= DaylightUI.Pixel.Snap(bar, 43) - 0.01, "as tall as asked")
end)

T.test("a tile that can't grow keeps some health under a power bar taller than it", function()
    local _, ns = stub.Load({ module = true, login = false })
    local f = ns.UF.Create(PLAYER)
    f:SetSize(100, 30)
    ns.UF.Layout(f, { width = 100, height = 30, powerHeight = 60, showName = true, showPercent = true }, ns.DEFAULTS.playerText, true)
    local px = DaylightUI.Pixel.Px(f, DaylightUI.Style.BorderPx(f))
    T.truthy(f:GetHeight() - 2 * px - f.power:GetHeight() >= ns.UF.MIN_HEALTH, "health still shows")
    T.truthy(f.power:GetHeight() < 30, "the power bar stops inside the tile")
end)
