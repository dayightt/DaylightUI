local stub = require("stub")

-- An ended cast bar fades out (Motion.FAST) before it hides, so run the tweens.
local function fadeOut()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 30 do if d then stub.RunOnUpdate(d, 1 / 60) end end
end

local function setup()
    local _, ns = stub.Load({ module = true, login = false })
    local h = ns.CastBar.Create("player")
    ns.CastBar.Layout(h, ns.DEFAULTS.playerCastbar)
    ns.CastBar.cfg.fill = "plain"   -- flat colors unless a test asks for the pairs
    return h, ns
end

T.test("a cast shows the bar with the client driving the fill", function()
    local h = setup()
    local d = stub.Duration(1.23)
    stub.units.player = { cast = { name = "Frostbolt", texture = 135846, notInterruptible = false, duration = d } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.truthy(h:IsShown())
    T.eq(h.bar.__timer[1].GetRemainingDuration(), 1.23, "the client's duration (a secret copy)")
    T.eq(h.bar.__timer[2], Enum.StatusBarInterpolation.Immediate)
    T.eq(h.bar.__timer[3], Enum.StatusBarTimerDirection.ElapsedTime)
    T.eq(h.text.__text, "Frostbolt")
    T.eq(h.icon.__texture, 135846)
end)

T.test("a channel drains", function()
    local h = setup()
    stub.units.player = { channel = { name = "Mind Flay", notInterruptible = false, duration = stub.Duration(2) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    T.eq(h.bar.__timer[3], Enum.StatusBarTimerDirection.RemainingTime)
end)

T.test("a mob's channel with no display name still shows its bar", function()
    local _, ns = setup()
    local t = ns.CastBar.Create("target")
    ns.CastBar.Layout(t, ns.DEFAULTS.targetCastbar)
    stub.units.target = { name = "Foe", reaction = 2, channel = { name = "Mind Flay", displayName = false, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    T.truthy(t:IsShown(), "the channel shows")
    T.eq(stub.Text(t.text), "Mind Flay", "named by the spell when the display name is missing")
end)

T.test("channel ticks: lines between a channel's ticks on your own bar only", function()
    local h, ns = setup()
    local CB = ns.CastBar
    local function shown(bar)
        local n = 0
        for _, t in ipairs(bar.tickLines or {}) do if t:IsShown() then n = n + 1 end end
        return n
    end
    h.bar:SetSize(200, 20)   -- the fake game doesn't size a bar from its anchors
    stub.units.player = { channel = { name = "Drain Life", spellID = 11700, duration = stub.Duration(5) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    T.eq(shown(h), 0, "off by default")
    CB.cfg.channelTicks = true
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    T.eq(shown(h), 4, "five ticks, four lines between them")
    stub.units.player = { cast = { name = "Shadow Bolt", duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.eq(shown(h), 0, "a plain cast has none")
    stub.units.player = { channel = { name = "Unknown", spellID = 999999, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    T.eq(shown(h), 0, "a channel not on the list has none")
    local t = CB.Create("target")
    CB.Layout(t, ns.DEFAULTS.targetCastbar)
    t.bar:SetSize(200, 20)
    stub.units.target = { name = "Foe", reaction = 2, channel = { name = "Mind Flay", spellID = 15407, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    T.eq(shown(t), 0, "only your own bar")
    CB.ShowSample(h, ns.Test.CASTS.player)
    T.eq(shown(h), 4, "the sample turns into a channel to show them")
    T.eq(h.text.__text, "Drain Life")
    CB.cfg.channelTicks = false
end)

-- A warlock wants Drain Life green and Drain Soul purple at a glance.
T.test("spell colors: your cast of a listed spell takes its color, any rank, others keep theirs", function()
    local h, ns = setup()
    local CB, Style = ns.CastBar, DaylightUI.Style
    stub.spells = { [689] = { name = "Drain Life" }, [11700] = { name = "Drain Life" }, [686] = { name = "Shadow Bolt" } }
    CB.cfg.spellColors = { { name = "drain life", color = { 0.2, 0.8, 0.3 } } }
    local function hi(bar)
        local g = bar:GetStatusBarTexture().__gradient
        return g and g[3]
    end
    local wr, wg, wb = Style.Soften(0.2, 0.8, 0.3)
    for _, id in ipairs({ 689, 11700 }) do
        stub.units.player = { channel = { name = "Drain Life", spellID = id, duration = stub.Duration(5) } }
        stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        local c = hi(h.bar)
        T.truthy(c, "a gradient from the picked color, rank " .. id)
        T.near(c.r, wr, 1e-6); T.near(c.g, wg, 1e-6); T.near(c.b, wb, 1e-6)
    end
    stub.units.player = { cast = { name = "Shadow Bolt", spellID = 686, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.isnil(hi(h.bar), "a spell not on the list keeps the cast color")
    T.near(h.bar:GetStatusBarTexture().__vertex[1], CB.cfg.cast[1], 1e-6)
    stub.units.player = { cast = { name = "Drain Life", spellID = 689, notInterruptible = true, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.isnil(hi(h.bar), "can't be interrupted still wins: it's a warning")
    local t = CB.Create("target")
    CB.Layout(t, ns.DEFAULTS.targetCastbar)
    stub.units.target = { name = "Foe", reaction = 2, channel = { name = "Drain Life", spellID = 689, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
    T.isnil(hi(t.bar), "only your own bar: another unit's spell can be secret")
    -- The preview shows the last spell picked, in its color.
    CB.ShowSample(h, ns.Test.CASTS.player)
    T.eq(h.text.__text, "drain life")
    T.truthy(hi(h.bar), "the sample in the picked color")
    CB.cfg.spellColors = {}
    CB.ShowSample(h, ns.Test.CASTS.player)
    T.eq(h.text.__text, "Holy Light", "no list: the usual sample")
    T.isnil(hi(h.bar))
    stub.spells = nil
end)

T.test("spell colors: added by id or name, each in its own color, recolored and taken off", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local CB = ns.CastBar
    stub.spells = { [689] = { name = "Drain Life" }, [1120] = { name = "Drain Soul" } }
    T.eq(CB.AddSpellColor("689"), "Drain Life", "by id, the game's name kept")
    local name, why = CB.AddSpellColor("424242")
    T.isnil(name); T.truthy(why, "an id with no spell says so")
    T.eq(CB.AddSpellColor("1120"), "Drain Soul")
    local list = DUI:Get("UnitFrames", "casts.spellColors")
    T.eq(#list, 2)
    T.truthy(list[1].color[1] ~= list[2].color[1] or list[1].color[3] ~= list[2].color[3], "each starts in its own color")
    CB.AddSpellColor("689")
    list = DUI:Get("UnitFrames", "casts.spellColors")
    T.eq(#list, 2, "no second line for the same spell")
    T.eq(list[2].name, "Drain Life", "it moves last, so the preview shows it")
    CB.SetSpellColor(2, { 0.1, 0.9, 0.2 })
    T.eq(DUI:Get("UnitFrames", "casts.spellColors")[2].color[2], 0.9)
    T.eq(CB.cfg.spellColors[2].color[2], 0.9, "the bars read the saved list")
    CB.RemoveSpellColor(1)
    list = DUI:Get("UnitFrames", "casts.spellColors")
    T.eq(#list, 1); T.eq(list[1].name, "Drain Life")
    CB.RemoveSpellColor(1)
    T.eq(#DUI:Get("UnitFrames", "casts.spellColors"), 0)
    stub.spells = nil
end)

T.test("a secret interruptible flag lays the locked color over the fill, the client picks", function()
    local h, ns = setup()
    local lc = ns.CastBar.cfg.locked
    stub.units.player = { cast = { name = "X", notInterruptible = stub.Secret(true), duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.falsy(h.bar:GetStatusBarTexture().__vertexFromBoolean, "the fill keeps its own color")
    local o = h.lockTex
    T.truthy(o and o:IsShown(), "the overlay shows")
    T.eq(o.__vertex[1], lc[1]); T.eq(o.__vertex[2], lc[2]); T.eq(o.__vertex[3], lc[3])
    T.truthy(o.__alphaFromBoolean, "its alpha from the secret flag")
    stub.units.player = { cast = { name = "X", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.falsy(o:IsShown(), "a plain flag needs no overlay")
end)

-- An enemy's uninterruptible cast in a fight was gray over the cast color's olive
-- empty part.
T.test("a secret interruptible flag picks the empty part's color too", function()
    local h, ns = setup()
    local Style = DaylightUI.Style
    local lc, k = ns.CastBar.cfg.locked, Style.BAR_BACK_DIM
    stub.units.player = { cast = { name = "X", notInterruptible = stub.Secret(true), duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local back = Style.BarBack(h.bar)
    local v = back.__vertexFromBoolean
    T.truthy(v, "the empty part's color from the secret flag")
    T.near(v[2].r, lc[1] * k, 1e-6); T.near(v[2].g, lc[2] * k, 1e-6); T.near(v[2].b, lc[3] * k, 1e-6)
    local w = back.__vertex
    T.near(v[3].r, w[1], 1e-6); T.near(v[3].g, w[2], 1e-6); T.near(v[3].b, w[3], 1e-6)
end)

T.test("a craft looks like any other cast, never the locked gray", function()
    local h, ns = setup()
    local lc, nc = ns.CastBar.cfg.locked, ns.CastBar.cfg.cast
    -- The client says a craft can't be interrupted.
    stub.units.player = { cast = { name = "Rough Bronze Cuirass", tradeSkill = true, notInterruptible = true,
                                   duration = stub.Duration(4.5) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local v = h.bar:GetStatusBarTexture().__vertex
    T.eq(v[1], nc[1]); T.eq(v[2], nc[2]); T.eq(v[3], nc[3])
    T.falsy(v[1] == lc[1] and v[2] == lc[2], "not the locked color")
end)

T.test("a cast that can't be interrupted uses the locked color, over class color", function()
    local h, ns = setup()
    local lc = ns.CastBar.cfg.locked
    ns.CastBar.cfg.classColor = true
    stub.units.player = { cast = { name = "X", notInterruptible = true, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local v = h.bar:GetStatusBarTexture().__vertex
    T.eq(v[1], lc[1]); T.eq(v[2], lc[2]); T.eq(v[3], lc[3])
    ns.CastBar.cfg.classColor = false
    stub.units.player = { cast = { name = "X", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.eq(h.bar:GetStatusBarTexture().__vertex[1], ns.CastBar.cfg.cast[1])
end)

T.test("a failed attempt while still casting keeps the bar up", function()
    local h = setup()
    stub.units.player = { cast = { name = "X", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.FireEvent("UNIT_SPELLCAST_FAILED", "player")
    T.truthy(h:IsShown())
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    fadeOut()   -- an ended cast fades out FAST first
    T.falsy(h:IsShown())
end)

T.test("remaining time is written on update", function()
    local h = setup()
    stub.units.player = { cast = { name = "X", notInterruptible = false, duration = stub.Duration(1.23) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.RunOnUpdate(h, 0.06)
    T.eq(h.time.__text, "1.2")
end)

T.test("a disabled cast bar never shows", function()
    local _, ns = stub.Load({ module = true, login = false })
    local h = ns.CastBar.Create("player")
    ns.CastBar.Layout(h, { enabled = false, width = 240, height = 18, showIcon = true })
    stub.units.player = { cast = { name = "X", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.falsy(h:IsShown())
end)

T.test("a bar placed into another bar covers it, opaque, with text that fits", function()
    local _, ns = stub.Load({ module = true, login = false })
    local target = CreateFrame("Frame", nil, UIParent)
    local power = CreateFrame("StatusBar", nil, target)
    local h = ns.CastBar.Create("target", target, power)
    ns.CastBar.Layout(h, ns.DEFAULTS.targetCastbar, ns.DEFAULTS.target)
    local p, rel = h:GetPoint(1)
    T.eq(p, "ALL"); T.eq(rel, power)
    T.truthy(h:GetFrameLevel() > power:GetFrameLevel(), "drawn over the power bar")
    T.eq(h.bg.__color[4], 1, "opaque backing")
    T.isnil(DaylightUI.Style.GetShell(h), "no border of its own")
    T.eq(h.text.__font[2], math.min(ns.DEFAULTS.targetCastbar.spell.size, ns.CastBar.FitText(ns.DEFAULTS.target.powerHeight)))
    local _, _, _, _, y = h.text:GetPoint(1)
    T.truthy(y > 0, "lifted to sit centered")
    T.isnil(h.icon)
end)

T.test("inside a frame the text takes its own size, nudge and color", function()
    local _, ns = stub.Load({ module = true, login = false })
    local target = CreateFrame("Frame", nil, UIParent)
    local h = ns.CastBar.Create("target", target, CreateFrame("StatusBar", nil, target))
    ns.CastBar.Layout(h, ns.DEFAULTS.targetCastbar, ns.DEFAULTS.target)
    local _, _, _, x0, y0 = h.text:GetPoint(1)
    local _, _, _, tx0 = h.time:GetPoint(1)
    local cfg = { enabled = true, insideTextSize = 15, insideTextX = 6, insideTextY = -9,
                  spell = { color = { 1, 0.5, 0 } }, time = { color = { 1, 0.5, 0 } } }
    ns.CastBar.Layout(h, cfg, ns.DEFAULTS.target)
    T.eq(h.text.__font[2], 15); T.eq(h.time.__font[2], 15)
    local _, _, _, x, y = h.text:GetPoint(1)
    local _, _, _, tx, ty = h.time:GetPoint(1)
    T.eq(x, x0 + 6); T.eq(y, y0 - 9); T.eq(tx, tx0 + 6); T.eq(ty, y0 - 9)
    T.eq(h.text.__textColor[2], 0.5); T.eq(h.time.__textColor[3], 0)
end)

T.test("inside a frame a text size the player picked is kept, the default fits the bar", function()
    local _, ns = stub.Load({ module = true, login = false })
    local target = CreateFrame("Frame", nil, UIParent)
    local h = ns.CastBar.Create("target", target, CreateFrame("StatusBar", nil, target))
    local fit = ns.CastBar.FitText(ns.DEFAULTS.target.powerHeight)
    ns.CastBar.Layout(h, { enabled = true, spell = { size = 20 }, time = { size = 12 } }, ns.DEFAULTS.target)
    T.eq(h.text.__font[2], 20, "the picked spell name size")
    T.eq(h.time.__font[2], math.min(12, fit), "the default time size still fits the power bar")
end)

T.test("an enemy's secret cast data goes straight to the client widgets", function()
    local _, ns = stub.Load({ module = true, login = false })
    local target = CreateFrame("Frame", nil, UIParent)
    local h = ns.CastBar.Create("target", target, CreateFrame("StatusBar", nil, target))
    ns.CastBar.Layout(h, ns.DEFAULTS.targetCastbar, ns.DEFAULTS.target)
    local name, flag = stub.Secret("Shadow Bolt"), stub.Secret(false)
    stub.units.target = { cast = { name = name, notInterruptible = flag, duration = stub.Duration(stub.Secret(1.5)) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(h:IsShown())
    T.eq(h.text.__text, name)
    stub.RunOnUpdate(h, 0.06)
    T.eq(h.time.__text.secretFormat, "%.1f")
end)

T.test("the time text updates at most every 0.05s", function()
    local h = setup()
    stub.units.player = { cast = { name = "X", notInterruptible = false, duration = stub.Duration(1.23) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.RunOnUpdate(h, 0.02)
    stub.RunOnUpdate(h, 0.02)
    T.isnil(h.time.__text)
    stub.RunOnUpdate(h, 0.02)
    T.eq(h.time.__text, "1.2")
end)

T.test("cast bars: an interrupt holds the bar a moment, red, then it goes", function()
    local h, ns = setup()
    stub.units.player = { cast = { name = "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
    T.truthy(h:IsShown(), "held")
    T.eq(h.text.__text, INTERRUPTED or "Interrupted")
    T.eq(h.bar:GetStatusBarTexture().__vertex[1], ns.CastBar.cfg.interrupted[1], "red")
    stub.RunTimers()
    fadeOut()   -- an ended cast fades out FAST first
    T.falsy(h:IsShown(), "then gone")
end)

T.test("cast bars: an earlier interrupt's timer doesn't cut a newer hold short", function()
    local h = setup()
    local holds, real = {}, C_Timer.After
    C_Timer.After = function(_, fn) holds[#holds + 1] = fn end
    local ok, err = pcall(function()
        for _ = 1, 2 do   -- kicked, a new cast at once, kicked again
            stub.units.player = { cast = { name = "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
            stub.FireEvent("UNIT_SPELLCAST_START", "player")
            stub.units.player = {}
            stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
            stub.FireEvent("UNIT_SPELLCAST_STOP", "player")
        end
    end)
    C_Timer.After = real
    if not ok then error(err, 0) end
    T.eq(#holds, 2)
    holds[1]()   -- the first hold's time is up
    T.truthy(h:IsShown(), "the second kick still holds")
    holds[2]()
    fadeOut()   -- an ended cast fades out FAST first
    T.falsy(h:IsShown(), "its own time up: gone")
end)

T.test("cast bars: channel color, no name, and left / total timer", function()
    local h, ns = setup()
    local cfg = {}
    for k, v in pairs(ns.DEFAULTS.casts) do cfg[k] = v end
    cfg.channel, cfg.fill = { 0, 0, 1 }, "plain"
    ns.CastBar.Configure(cfg)
    local spell, time = { show = false }, { format = "total" }
    local bar = {}
    for k, v in pairs(ns.DEFAULTS.playerCastbar) do bar[k] = v end
    bar.spell, bar.time = spell, time
    ns.CastBar.Layout(h, bar)
    local d = stub.Duration(1.2)
    d.GetTotalDuration = function() return 2.5 end
    stub.units.player = { channel = { name = "Mind Flay", duration = d } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    T.eq(h.text.__text, "", "no spell name")
    T.eq(h.bar:GetStatusBarTexture().__vertex[3], 1, "the channel color")
    stub.RunOnUpdate(h, 0.1)
    T.eq(h.time.__text, "1.2 / 2.5")
    time.show = false
    stub.RunOnUpdate(h, 0.1)
    T.eq(h.time.__text, "")
    ns.CastBar.Configure(ns.DEFAULTS.casts)
end)

T.test("cast bars: in the caster's class color when set", function()
    local h, ns = setup()
    local cfg = {}
    for k, v in pairs(ns.DEFAULTS.casts) do cfg[k] = v end
    cfg.classColor, cfg.fill = true, "plain"
    ns.CastBar.Configure(cfg)
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE",
                          cast = { name = "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local r, g, b = DaylightUI.Style.ClassColor("MAGE")
    local v = h.bar:GetStatusBarTexture().__vertexFromBoolean
    local col = v and v[3] or nil
    if col then
        T.near(col.r, r, 1e-6, "the mage's color")
    else
        T.near(h.bar:GetStatusBarTexture().__vertex[1], r, 1e-6, "the mage's color")
    end
    local back = DaylightUI.Style.BarBack(h.bar).__vertex
    T.near(back[1], r * DaylightUI.Style.BAR_BACK_DIM, 1e-6, "the empty part in the same color, dimmed")
    ns.CastBar.Configure(ns.DEFAULTS.casts)
end)

T.test("cast bars: a caster whose class the game hides (battlegrounds) still shows its class color", function()
    local h, ns = setup()
    local cfg = {}
    for k, v in pairs(ns.DEFAULTS.casts) do cfg[k] = v end
    cfg.classColor, cfg.fill = true, "pair"
    ns.CastBar.Configure(cfg)
    stub.units.player = { name = "Rival", isPlayer = true, class = "MAGE", classHidden = true,
                          cast = { name = "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local mage = h.classLayers and h.classLayers.MAGE
    T.truthy(mage and mage:IsShown(), "the class layers")
    T.eq(mage.__cell.__value, 8)
    T.eq(mage.__gradient[2], (DaylightUI.Gradients.Colors("MAGE")), "the mage pair")
    -- can't be interrupted: the locked color, with no layers over it
    stub.units.player.cast.notInterruptible = true
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.falsy(mage:IsShown())
    -- class color off: none
    stub.units.player.cast.notInterruptible = false
    ns.CastBar.Configure(ns.DEFAULTS.casts)
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.falsy(mage:IsShown())
end)

T.test("the target's cast bar can be its own bar, sized and moved on its own", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    T.falsy(ns.targetCastbarFree.enabled, "inside the frame by default")
    T.truthy(DUI.Movers.Get("unitframes.targetCastbar").suspended)
    DUI:Set("UnitFrames", "targetCastbar.at", "free")
    DUI:Set("UnitFrames", "targetCastbar.width", 300)
    DUI:Set("UnitFrames", "targetCastbar.height", 30)
    stub.RunTimers()
    local h = ns.targetCastbarFree
    T.truthy(h.enabled)
    T.falsy(ns.targetCastbar.enabled, "the one inside the frame steps aside")
    T.near(h:GetWidth(), 300, 1); T.near(h:GetHeight(), 30, 1)
    T.falsy(DUI.Movers.Get("unitframes.targetCastbar").suspended, "its own mover")
    stub.units.target = { name = "Mob", cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(h:IsShown(), "it shows the target's cast")
    T.falsy(ns.targetCastbar:IsShown())
end)

T.test("the target's cast bar has its own colors", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "targetCasts.cast", { 0, 0, 1 })
    DUI:Set("UnitFrames", "casts.cast", { 1, 0, 0 })
    DUI:Set("UnitFrames", "casts.fill", "plain")
    stub.RunTimers()
    stub.units.target = { name = "Mob", cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) } }
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE",
                          cast = { name = "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local function fill(h)
        local tex = h.bar:GetStatusBarTexture()
        local v = tex.__vertexFromBoolean
        if v then return v[3].r, v[3].b end
        return tex.__vertex[1], tex.__vertex[3]
    end
    local tr, tb = fill(ns.targetCastbar)
    T.eq(tb, 1, "the target's: blue"); T.eq(tr, 0)
    local pr, pb = fill(ns.playerCastbar)
    T.eq(pr, 1, "yours: red"); T.eq(pb, 0)
end)

T.test("the focus has a cast bar: in its frame, or its own", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    stub.units.focus = { name = "Mob", cast = { name = "Heal", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "focus")
    T.truthy(ns.focusCastbar:IsShown(), "inside the focus frame")
    DUI:Set("UnitFrames", "focusCastbar.at", "free")
    stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_START", "focus")
    T.truthy(ns.focusCastbarFree:IsShown(), "its own bar")
    T.falsy(DUI.Movers.Get("unitframes.focusCastbar").suspended)
end)

T.test("the player cast bar attached can have a straight end", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    DUI:Set("UnitFrames", "playerCastbar.slant", false)
    stub.RunTimers()
    T.isnil(DaylightUI.Style.GetSlant(ns.playerCastbar) and DaylightUI.Style.GetSlant(ns.playerCastbar).side, "straight")
end)

T.test("a cast bar of its own can angle its left end, its right end, or both", function()
    local DUI, ns = stub.Load({ module = true })
    local Style = DaylightUI.Style
    DUI:Set("UnitFrames", "targetCastbar.at", "below")
    DUI:Set("UnitFrames", "targetCastbar.slantLeft", true)
    DUI:Set("UnitFrames", "targetCastbar.showIcon", true)
    stub.RunTimers()
    local h = ns.targetCastbarFree
    local sl = Style.GetSlant(h)
    T.eq(sl.side, "left", "the left end alone, like the target frame")
    local _, _, _, x = h.icon:GetPoint(1)
    T.truthy(x >= sl.cut, "the icon starts past the angle")
    DUI:Set("UnitFrames", "targetCastbar.slant", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(h).side, "both")
    DUI:Set("UnitFrames", "focusCastbar.at", "free")
    DUI:Set("UnitFrames", "focusCastbar.slantLeft", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(ns.focusCastbarFree).side, "left", "the focus's too")
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    DUI:Set("UnitFrames", "playerCastbar.slantLeft", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(ns.playerCastbar).side, "both", "yours, with its right end on by default")
end)

-- A player's report: with the icon on, the cast's first stretch filled hidden
-- behind the icon, so a cast looked like it hadn't started.
T.test("with the spell icon on, the fill starts past the icon, never under it", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    DUI:Set("UnitFrames", "playerCastbar.showIcon", true)
    DUI:Set("UnitFrames", "targetCastbar.at", "below")
    DUI:Set("UnitFrames", "targetCastbar.slantLeft", true)
    stub.RunTimers()
    for _, h in ipairs({ ns.playerCastbar, ns.targetCastbarFree }) do
        T.truthy(h.icon:IsShown(), "the icon shows")
        local _, _, _, ix = h.icon:GetPoint(1)
        local _, _, _, bx = h.bar:GetPoint(1)
        T.truthy(bx >= ix + h.icon:GetWidth() - 0.01, "the fill starts at the icon's right edge")
    end
    DUI:Set("UnitFrames", "playerCastbar.showIcon", false)
    stub.RunTimers()
    local _, _, _, bx, by = ns.playerCastbar.bar:GetPoint(1)
    T.near(bx, -by, 0.01, "no icon: the fill runs the whole bar, inside the border")
end)

T.test("a cast bar of its own can flip each angled end on its own", function()
    local DUI, ns = stub.Load({ module = true })
    local Style = DaylightUI.Style
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    DUI:Set("UnitFrames", "playerCastbar.slantLeft", true)
    stub.RunTimers()
    local h = ns.playerCastbar
    T.isnil(Style.GetSlant(h).under, "leaning out by default")
    DUI:Set("UnitFrames", "playerCastbar.slantUnder", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(h).under, "right", "the right end alone: a slanted box")
    DUI:Set("UnitFrames", "playerCastbar.slantUnder", false)
    DUI:Set("UnitFrames", "playerCastbar.slantUnderLeft", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(h).under, "left", "the left end alone")
    DUI:Set("UnitFrames", "playerCastbar.slantUnder", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(h).under, "both", "both ends lean under")
    DUI:Set("UnitFrames", "playerCastbar.slantLeft", false)
    stub.RunTimers()
    T.eq(Style.GetSlant(h).under, "right", "a flip on an end that isn't angled does nothing")
    DUI:Set("UnitFrames", "targetCastbar.at", "below")
    DUI:Set("UnitFrames", "targetCastbar.slantLeft", true)
    DUI:Set("UnitFrames", "targetCastbar.slantUnderLeft", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(ns.targetCastbarFree).under, "left", "the target's too")
    DUI:Set("UnitFrames", "playerCastbar.at", "below")
    stub.RunTimers()
    T.isnil(Style.GetSlant(h).under, "hung under the frame it follows the frame's angle")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a cast bar of its own can switch on its own angle; off, the shared one", function()
    local DUI, ns = stub.Load({ module = true })
    local Style = DaylightUI.Style
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    stub.RunTimers()
    local h = ns.playerCastbar
    local shared = Style.GetSlant(h).cut
    T.truthy(shared > 0, "angled by default")
    DUI:Set("UnitFrames", "playerCastbar.lean", 0.6)
    stub.RunTimers()
    T.eq(Style.GetSlant(h).cut, shared, "an angle without its switch is ignored")
    DUI:Set("UnitFrames", "playerCastbar.ownAngle", true)
    stub.RunTimers()
    T.truthy(Style.GetSlant(h).cut > shared, "steeper with its own angle")
    DUI:Set("UnitFrames", "playerCastbar.lean", 0.02)
    stub.RunTimers()
    T.truthy(Style.GetSlant(h).cut < shared, "near 0 it's nearly square, not the shared angle")
    DUI:Set("UnitFrames", "playerCastbar.ownAngle", false)
    stub.RunTimers()
    T.eq(Style.GetSlant(h).cut, shared, "switched off, the shared angle again")
    DUI:Set("UnitFrames", "targetCastbar.at", "free")
    DUI:Set("UnitFrames", "targetCastbar.slant", true)
    stub.RunTimers()
    local tShared = Style.GetSlant(ns.targetCastbarFree).cut
    DUI:Set("UnitFrames", "targetCastbar.ownAngle", true)
    DUI:Set("UnitFrames", "targetCastbar.lean", 0.6)
    stub.RunTimers()
    T.truthy(Style.GetSlant(ns.targetCastbarFree).cut > tShared, "the target's too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a free power bar can set its own angle, and a cast bar hung under it follows", function()
    local DUI, ns = stub.Load({ module = true })
    local Style = DaylightUI.Style
    DUI:Set("UnitFrames", "player.powerAt", "free")
    DUI:Set("UnitFrames", "playerCastbar.from", "power")
    stub.RunTimers()
    local pb, h = ns.frames.player.freePower, ns.playerCastbar
    local shared, castShared = Style.GetSlant(pb).cut, Style.GetSlant(h).cut
    DUI:Set("UnitFrames", "player.powerOwnAngle", true)
    DUI:Set("UnitFrames", "player.powerLean", 0.6)
    stub.RunTimers()
    T.truthy(Style.GetSlant(pb).cut > shared, "the power bar's end is steeper")
    T.truthy(Style.GetSlant(h).cut > castShared, "the cast bar under it continues the steeper line")
    DUI:Set("UnitFrames", "player.powerOwnAngle", false)
    stub.RunTimers()
    T.eq(Style.GetSlant(pb).cut, shared, "switched off, the shared angle again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the player's cast bar between the frames fills the gap, both ends flipped", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local pf, tf, h = ns.frames.player, ns.frames.target, ns.playerCastbar
    DUI:Set("UnitFrames", "playerCastbar.at", "middle")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(ns.module.db.playerCastbar.at, "middle", "stays between the frames")
    T.truthy(h.middle)
    T.eq(DaylightUI.Style.GetSlant(h).under, "both", "wider at the bottom")
    local _, rel1 = h:GetPoint(1)
    local _, rel2 = h:GetPoint(2)
    T.eq(rel1, pf); T.eq(rel2, tf)
end)

T.test("upgrade step 22: a bar flipped with the old single switch flips both ends", function()
    local _, ns = stub.Load({ module = true })
    local uf = { playerCastbar = { slantUnder = true, slantUnderLeft = false },
                 focusCastbar = { slantUnder = false, slantUnderLeft = false },
                 player = { powerSlantUnder = true, powerSlantUnderLeft = false },
                 target = { powerSlantUnder = false, powerSlantUnderLeft = false } }
    ns.UPGRADE_STEPS[22](uf)
    T.eq(uf.playerCastbar.slantUnderLeft, true, "flipped before: both ends")
    T.eq(uf.focusCastbar.slantUnderLeft, false, "never flipped: untouched")
    T.eq(uf.player.powerSlantUnderLeft, true, "a power bar too")
    T.eq(uf.target.powerSlantUnderLeft, false)
    ns.UPGRADE_STEPS[22]({})
end)

T.test("upgrade step 21: a personal display angle set before the Own angle switch keeps it", function()
    local _, ns = stub.Load({ module = true })
    local own = { personal = { angle = 0.4, ownAngle = false, lean = 0.21 } }
    ns.UPGRADE_STEPS[21](own)
    T.eq(own.personal.ownAngle, true); T.eq(own.personal.lean, 0.4)
    T.eq(own.personal.angle, 0, "the older setting is spent")
    local shared = { personal = { angle = 0, ownAngle = false, lean = 0.21 } }
    ns.UPGRADE_STEPS[21](shared)
    T.eq(shared.personal.ownAngle, false, "0 meant the shared angle")
    T.eq(shared.personal.lean, 0.21, "its slider starts at the shared default")
    ns.UPGRADE_STEPS[21]({})
end)

T.test("upgrade step 20: a bar 1.9.1 moved off the spot between the frames goes back", function()
    local _, ns = stub.Load({ module = true })
    local moved = { playerCastbar = { at = "free", width = 120, slant = true, slantLeft = true, slantUnder = true } }
    ns.UPGRADE_STEPS[20](moved)
    T.eq(moved.playerCastbar.at, "middle")
    T.isnil(moved.playerCastbar.slantLeft); T.isnil(moved.playerCastbar.slantUnder)
    -- A free bar the player shaped another way stays free.
    local own = { playerCastbar = { at = "free", slantLeft = true } }
    ns.UPGRADE_STEPS[20](own)
    T.eq(own.playerCastbar.at, "free"); T.eq(own.playerCastbar.slantLeft, true)
    ns.UPGRADE_STEPS[20]({})
end)

T.test("cast bars: with the Gradients page's pairs, an interrupt gets its own pair", function()
    local h, ns = setup()
    ns.CastBar.cfg.fill = "pair"
    stub.units.player = { cast = { name = "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    local lo = DaylightUI.Gradients.Colors("CAST_INTERRUPTED")
    T.near(h.bar:GetStatusBarTexture().__gradient[2].r, lo.r, 1e-6, "the interrupted pair")
    ns.CastBar.cfg.fill = "plain"
end)

T.test("upgrade step 8: a cast bar's attach switch becomes where it sits", function()
    local _, ns = stub.Load({ module = true })
    local uf = { playerCastbar = { attach = false }, targetCastbar = { attach = true }, focusCastbar = { attach = false } }
    ns.UPGRADE_STEPS[8](uf)
    T.eq(uf.playerCastbar.at, "free"); T.isnil(uf.playerCastbar.attach)
    T.isnil(uf.targetCastbar.at, "attached = the default spot"); T.isnil(uf.targetCastbar.attach)
    T.eq(uf.focusCastbar.at, "free")
    ns.UPGRADE_STEPS[8]({})
end)

T.test("the target's cast bar can sit above or below its frame, centered, with a nudge", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local h, target = ns.targetCastbarFree, ns.frames.target
    T.eq(DUI:Get("UnitFrames", "targetCastbar.at"), "power", "inside the frame by default")
    DUI:Set("UnitFrames", "targetCastbar.at", "above")
    stub.RunTimers()
    T.truthy(h.enabled); T.falsy(ns.targetCastbar.enabled, "the one inside steps aside")
    T.truthy(DUI.Movers.Get("unitframes.targetCastbar").suspended, "no mover: it follows the frame")
    local p, rel, rp, x, y = h:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rp, "TOP")
    T.truthy(rel == target or rel == target.tab, "over the frame (or its name tab)")
    T.eq(x, 0); T.truthy(y > 0)
    T.truthy(ns.auras.aboveLift >= h:GetHeight(), "the debuffs above move out past it")
    DUI:Set("UnitFrames", "targetCastbar.at", "below")
    DUI:Set("UnitFrames", "targetCastbar.x", 10)
    DUI:Set("UnitFrames", "targetCastbar.y", 5)
    stub.RunTimers()
    local p2, rel2, rp2, x2, y2 = h:GetPoint(1)
    T.eq(p2, "TOP"); T.eq(rel2, target); T.eq(rp2, "BOTTOM")
    T.eq(x2, 10); T.eq(y2, -ns.CastBar.AT_GAP + 5, "nudged")
    T.truthy(ns.auras.buffDrop >= h:GetHeight(), "the buffs below move out past it")
    stub.units.target = { name = "Mob", cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(h:IsShown(), "it shows the target's cast")
end)

T.test("the player's cast bar can sit above its frame; the swing timers then stand alone", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local h, f = ns.playerCastbar, ns.frames.player
    T.eq(DUI:Get("UnitFrames", "playerCastbar.at"), "below", "hung under the frame by default")
    DUI:Set("UnitFrames", "playerCastbar.at", "above")
    stub.RunTimers()
    local p, rel, rp = h:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rp, "TOP")
    T.truthy(rel == f or rel == f.tab, "over the frame (or its name tab)")
    T.truthy(DUI.Movers.Get("unitframes.playerCastbar").suspended)
    T.falsy(h.cfgAttach, "not hanging under the frame")
    T.near(h:GetWidth(), DUI:Get("UnitFrames", "playerCastbar.width"), 1, "its own width")
end)

T.test("the cast bar 'Where' choice offers each bar its own spots", function()
    local DUI = stub.Load({ module = true })
    local items = {}
    -- Each bar's rows are on its frame's page, under the Cast bar tab.
    for _, id in ipairs({ "player", "target", "focus", "party" }) do
        for _, g in ipairs(DUI.Options.GetPage("UnitFrames." .. id).groups) do
            if g.tab == "Cast bar" then
                for _, item in ipairs(g.items) do if item.key then items[item.key] = item end end
            end
        end
    end
    local p, t = items["playerCastbar.at"], items["targetCastbar.at"]
    T.eq(p.type, "dropdown"); T.isnil(p.values.power, "the player's has no 'inside'")
    T.truthy(p.values.below and p.values.above and p.values.free)
    T.truthy(t.values.power and t.values.above and t.values.below and t.values.free)
    T.truthy(items["focusCastbar.at"].values.power)
    T.truthy(items["targetCastbar.x"] and items["targetCastbar.y"], "a nudge")
end)

-- The blade: an interrupted enemy cast is sliced (a line across, then the bar
-- splits in two and fades).
local function settleMotion()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 120 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

local function step(n)
    local d = DaylightUI.Motion.Driver()
    for _ = 1, n do stub.RunOnUpdate(d, 1 / 60) end
end

local ME = "Player-1-00000001"
local function kickWorld()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.guid = ME
    stub.units.target = { name = "Mob", guid = "Creature-0-1", reaction = 2,
                          cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    -- The fake game leaves a bar sized by anchors at 0 x 0, so give it the game's size.
    ns.targetCastbar:SetSize(200, 8)
    return DUI, ns, ns.targetCastbar
end

T.test("cast bars: your interrupt slices the bar in the accent, then it splits in two and goes", function()
    local DUI, ns, h = kickWorld()
    T.truthy(h:IsShown(), "the target casts")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
    local k = h.blade
    T.truthy(k and k:IsShown(), "the line runs across")
    T.eq(k:GetParent(), ns.frames.target, "on the frame, not the bar")
    local r, g, b = DUI.Style.Accent()
    T.rgb(k.line.__vertex, { r, g, b }, "your kick: the accent")
    T.falsy(k.halves[1]:IsShown(), "the bar holds while it cuts")
    step(12)
    T.truthy(k.halves[1]:IsShown() and k.halves[2]:IsShown(), "then it splits in two")
    T.eq(h:GetAlpha(), 0, "the halves stand in for the bar")
    stub.units.target.cast = nil
    stub.RunTimers()
    settleMotion()
    T.falsy(k:IsShown(), "then it's gone")
    T.eq(h:GetAlpha(), 1, "the bar's alpha back for the next cast")
    local masks = 0
    for _, half in ipairs(k.halves) do masks = masks + #(half.edge.__masks or {}) + #(half.fill.__masks or {}) end
    T.eq(masks, 0, "no masks")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: someone else's interrupt, or a secret one, cuts in warm white", function()
    local DUI, _, h = kickWorld()
    local W = DUI.Motion.BLADE_EDGE
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, "Player-1-00000002", nil)
    T.truthy(h.blade:IsShown())
    T.rgb(h.blade.line.__vertex, W, "someone else's: warm white")
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    -- Under restrictions the client hands the payload over as secrets.
    stub.SetRestriction("Encounter", true)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
    stub.SetRestriction("Encounter", false)
    T.truthy(h.blade:IsShown(), "it cuts either way")
    T.rgb(h.blade.line.__vertex, W, "a secret kicker: warm white")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: a new cast or a new target ends the blade at once; the player's bar has none", function()
    local _, ns, h = kickWorld()
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
    step(12)
    T.eq(h:GetAlpha(), 0)
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.falsy(h.blade:IsShown(), "a new cast")
    T.eq(h:GetAlpha(), 1, "and its bar is back")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
    T.truthy(h.blade:IsShown())
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(h.blade:IsShown(), "a new target")
    T.isnil(ns.playerCastbar.blade, "never on your own bar")
    T.truthy(ns.focusCastbar.blade and ns.targetCastbarFree.blade and ns.focusCastbarFree.blade, "every other bar")
end)

T.test("cast bars: every interrupt animation plays on the target's bar and gives it back", function()
    local DUI, ns, h = kickWorld()
    local k = h.blade
    for _, style in ipairs(DUI.Motion.KICKS) do
        ns.CastBar.cfg.kickStyle = style
        stub.units.target.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
        stub.FireEvent("UNIT_SPELLCAST_START", "target")
        stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
        T.eq(k.style, style, style .. " plays")
        step(20)
        T.eq(h:GetAlpha(), 0, style .. ": its pieces stand in for the bar")
        stub.units.target.cast = nil
        stub.RunTimers()
        settleMotion()
        T.falsy(k:IsShown(), style .. ": then gone")
        T.eq(h:GetAlpha(), 1, style .. ": the bar's alpha back")
    end
    ns.CastBar.cfg.kickStyle = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: 'Kicked by' names who interrupted beside the target's bar; a new target hides it", function()
    local DUI, ns, h = kickWorld()
    stub.units.party1 = { name = "Valeera", isPlayer = true, class = "ROGUE", guid = "Player-1-00000002" }
    local t = h.kickTag
    T.truthy(t and not t:IsShown(), "built with the bar, hidden")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, "Player-1-00000002", nil)
    T.truthy(t:IsShown())
    T.eq(stub.Text(t.name), "Valeera")
    T.rgb(t.name.__textColor, { DUI.Style.ClassTextColor("ROGUE") }, "in the class color")
    local _, rel = t:GetPoint(1)
    T.eq(rel, h, "beside the bar")
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(t:IsShown(), "a new target hides it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a frame above the tag faded by a secret (range) makes its
-- GetAlpha secret, and a second kick while the tag still showed tweened from it.
T.test("cast bars: a second kick under a secret-faded parent eases the tag without reading its alpha", function()
    local DUI, ns, h = kickWorld()
    local t = h.kickTag
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
    T.truthy(t:IsShown())
    t:GetParent():SetAlphaFromBoolean(stub.Secret(true), 1, 0.5)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
    settleMotion()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(t:IsShown(), "the tag still shows")
    T.eq(stub.Plain(t.__alpha), 1, "eased in all the way")
end)

T.test("cast bars: with motion off there's no blade, the bar's red hold says it", function()
    local DUI, _, h = kickWorld()
    DUI:Set("general", "motion", false)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "Cast-1", 133, ME, nil)
    T.falsy(h.blade:IsShown())
    T.truthy(h:IsShown(), "the interrupted bar holds")
    T.eq(h:GetAlpha(), 1)
end)

T.test("upgrade step 11: the three fill switches become one Fill style", function()
    local _, ns = stub.Load({ module = true })
    local uf = { casts = { pairGradient = false, gradient = true, fill = "pair" },
                 swing = { pairGradient = false, gradient = false, fill = "pair" } }
    ns.UPGRADE_STEPS[11](uf)
    T.eq(uf.casts.fill, "daylight"); T.isnil(uf.casts.gradient); T.isnil(uf.casts.pairGradient)
    T.eq(uf.swing.fill, "plain")
    uf = { casts = { gradient = true, fill = "pair" } }
    ns.UPGRADE_STEPS[11](uf)
    T.eq(uf.casts.fill, "pair", "the pair won over the Daylight gradient")
    ns.UPGRADE_STEPS[11]({})
end)

T.test("upgrade step 12: your health's Daylight switch becomes the player page's Health bar color", function()
    local _, ns = stub.Load({ module = true })
    local uf = { colors = { playerDaylight = true } }
    ns.UPGRADE_STEPS[12](uf)
    T.eq(uf.player.colorHealth, "daylight"); T.isnil(uf.colors.playerDaylight)
    uf = { colors = { playerDaylight = false }, player = { colorHealth = "class" } }
    ns.UPGRADE_STEPS[12](uf)
    T.eq(uf.player.colorHealth, "class")
end)

T.test("upgrade step 13: name length and cast text size each move to their frame or bar", function()
    local _, ns = stub.Load({ module = true })
    local uf = { colors = { nameLimit = true, nameLimitLen = 8 }, target = { nameLimitLen = 5 }, player = { nameLimitLen = 0 },
                 text = { cast = 14 }, playerCastbar = { textSize = 0 }, targetCastbar = { textSize = 16 }, swing = { textSize = 12 } }
    ns.UPGRADE_STEPS[13](uf)
    T.eq(uf.player.nameLimitLen, 8); T.eq(uf.target.nameLimitLen, 5, "its own limit stays"); T.eq(uf.raid.nameLimitLen, 8)
    T.isnil(uf.raid20, "a raid size with no setup of its own follows Raid 10's")
    T.isnil(uf.colors.nameLimit); T.isnil(uf.colors.nameLimitLen)
    T.eq(uf.playerCastbar.textSize, 14); T.eq(uf.targetCastbar.textSize, 16, "its own size stays")
    T.eq(uf.focusCastbar.textSize, 14); T.eq(uf.swing.textSize, 14); T.isnil(uf.text.cast)
    uf = { colors = { nameLimit = false, nameLimitLen = 8 }, playerCastbar = { textSize = 0 } }
    ns.UPGRADE_STEPS[13](uf)
    T.isnil(uf.player, "no limit before, none now")
    T.eq(uf.playerCastbar.textSize, 12, "the old 0 was 12")
end)

T.test("upgrade step 17: the shared spell name and timer, and each bar's text size and color, move to each bar's two texts", function()
    local _, ns = stub.Load({ module = true })
    local uf = { casts = { showName = false, timer = "total" }, playerCastbar = { textSize = 14 },
                 targetCastbar = { textColor = { 1, 0.5, 0 } } }
    ns.UPGRADE_STEPS[17](uf)
    T.eq(uf.playerCastbar.spell.size, 14); T.eq(uf.playerCastbar.time.size, 14); T.isnil(uf.playerCastbar.textSize)
    T.rgb(uf.targetCastbar.spell.color, { 1, 0.5, 0 }); T.rgb(uf.targetCastbar.time.color, { 1, 0.5, 0 })
    T.isnil(uf.targetCastbar.textColor)
    for _, key in ipairs({ "playerCastbar", "targetCastbar", "focusCastbar", "partyCastbar" }) do
        T.eq(uf[key].spell.show, false, key); T.eq(uf[key].time.format, "total", key)
    end
    T.isnil(uf.casts.showName); T.isnil(uf.casts.timer)
    uf = { casts = { timer = "none" } }
    ns.UPGRADE_STEPS[17](uf)
    T.eq(uf.focusCastbar.time.show, false)
    T.isnil(uf.focusCastbar.spell, "nothing else saved")
    uf = {}
    ns.UPGRADE_STEPS[17](uf)
    T.isnil(uf.playerCastbar, "an untouched profile gets nothing")
end)

T.test("each cast bar places, sizes and colors its spell name and time on its own", function()
    local _, ns = stub.Load({ module = true, login = false })
    local h = ns.CastBar.Create("player")
    local cfg = {}
    for k, v in pairs(ns.DEFAULTS.playerCastbar) do cfg[k] = v end
    cfg.at = "free"
    cfg.spell = { show = true, size = 15, pos = "center", x = 0, y = -2, color = { 1, 0.5, 0 } }
    cfg.time = { show = true, format = "left", size = 9, pos = "left", x = 0, y = 3, color = { 0, 1, 0 } }
    ns.CastBar.Layout(h, cfg)
    local _, _, _, x0 = h.text:GetPoint(1)
    cfg.spell.x = 4
    ns.CastBar.Layout(h, cfg)
    T.eq(h.text.__font[2], 15); T.eq(h.time.__font[2], 9)
    T.eq(h.text:GetJustifyH(), "CENTER", "centered across the bar")
    local _, _, _, x, y = h.text:GetPoint(1)
    T.eq(x, x0 + 4); T.eq(y, -2)
    local tp, _, _, _, ty = h.time:GetPoint(1)
    T.eq(tp, "LEFT"); T.eq(ty, 3)
    T.eq(h.text.__textColor[2], 0.5); T.eq(h.time.__textColor[2], 1)
    cfg.spell.show, cfg.time.format = false, "total"
    ns.CastBar.Layout(h, cfg)
    ns.CastBar.ShowSample(h, { text = "Fireball", value = 0.5 })
    T.eq(h.text.__text, "", "its own name switch")
    T.eq(h.time.__text, "1.2 / 2.5", "its own timer pick")
    cfg.time.show = false
    ns.CastBar.Layout(h, cfg)
    ns.CastBar.ShowSample(h, { text = "Fireball", value = 0.5 })
    T.eq(h.time.__text, "")
end)

T.test("above or below its frame the target's cast bar is as wide as the frame, unless switched off", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local h, target = ns.targetCastbarFree, ns.frames.target
    DUI:Set("UnitFrames", "targetCastbar.at", "below")
    stub.RunTimers()
    T.near(h:GetWidth() * h:GetEffectiveScale(), target:GetWidth() * target:GetEffectiveScale(), 1, "the frame's width")
    DUI:Set("UnitFrames", "target.width", 220)
    stub.RunTimers()
    T.near(h:GetWidth() * h:GetEffectiveScale(), target:GetWidth() * target:GetEffectiveScale(), 1, "follows a wider frame")
    DUI:Set("UnitFrames", "targetCastbar.fitFrame", false)
    DUI:Set("UnitFrames", "targetCastbar.width", 300)
    stub.RunTimers()
    T.near(h:GetWidth(), 300, 1, "its own width when switched off")
    -- A player who had set a width of their own keeps it.
    local uf = { targetCastbar = { width = 260 }, focusCastbar = {} }
    ns.UPGRADE_STEPS[14](uf)
    T.eq(uf.targetCastbar.fitFrame, false); T.eq(uf.focusCastbar.fitFrame, nil)
end)

-- A batch of crafts (50 bandages) gets one bar for the whole batch, counting, and
-- never sliding away between two crafts. GetRemainingRecasts is the crafts after the
-- one under way (the game's own ProfessionsCrafting uses total = it + 1).
T.test("a batch of crafts is one bar over the whole batch, with its count", function()
    local h = setup()
    local left = 2
    local keptTS = rawget(_G, "C_TradeSkillUI")
    _G.C_TradeSkillUI = { GetRemainingRecasts = function() return left end }
    local function craft(n)
        local now = GetTime()
        stub.units.player = { cast = { name = "Linen Bandage", tradeSkill = true, notInterruptible = true,
            from = now * 1000, to = (now + 3) * 1000, spellID = 3275, duration = stub.Duration(3) } }
        stub.FireEvent("UNIT_SPELLCAST_START", "player", "Cast-" .. n, 3275)
    end
    local function finish(n)
        stub.Advance(3)
        left = math.max(0, left - 1)
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. n, 3275)
        stub.units.player = {}
        stub.FireEvent("UNIT_SPELLCAST_STOP", "player", "Cast-" .. n, 3275)
    end
    craft(1)
    T.truthy(h:IsShown())
    T.near(h.bar.__timer[1]:GetTotalDuration(), 9, 0.01, "three crafts' time")
    T.eq(h.text.__text, "Linen Bandage 1/3")
    finish(1)
    T.truthy(h:IsShown(), "stays up between two crafts")
    stub.Advance(0.3)
    craft(2)
    T.eq(h.text.__text, "Linen Bandage 2/3")
    T.near(h.bar.__timer[1]:GetRemainingDuration(), 6.3, 0.01, "this one, then the last at the pace so far (gap included)")
    finish(2)
    craft(3)
    T.eq(h.text.__text, "Linen Bandage 3/3")
    finish(3)
    fadeOut()   -- an ended cast fades out FAST first
    T.falsy(h:IsShown(), "the last one done: it goes")
    -- One craft alone gets its own cast, as before.
    left = 0
    craft(4)
    T.eq(h.text.__text, "Linen Bandage")
    T.near(h.bar.__timer[1].GetRemainingDuration(), 3, 0.01)
    _G.C_TradeSkillUI = keptTS
end)

T.test("a batch of crafts ends at once when one is interrupted or none comes", function()
    local h = setup()
    local keptTS = rawget(_G, "C_TradeSkillUI")
    _G.C_TradeSkillUI = { GetRemainingRecasts = function() return 4 end }
    local now = GetTime()
    stub.units.player = { cast = { name = "Linen Bandage", tradeSkill = true, from = now * 1000,
        to = (now + 3) * 1000, spellID = 3275, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "Cast-1", 3275)
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player", "Cast-1", 3275)
    T.truthy(h.batch, "waiting for the next one")
    stub.RunTimers()
    T.eq(h.batch, nil, "none came")
    fadeOut()   -- an ended cast fades out FAST first
    T.falsy(h:IsShown())
    stub.units.player = { cast = { name = "Linen Bandage", tradeSkill = true, from = now * 1000,
        to = (now + 3) * 1000, spellID = 3275, duration = stub.Duration(3) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "Cast-2", 3275)
    T.truthy(h.batch)
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-2", 3275)
    T.eq(h.batch, nil, "moved: the rest won't come")
    _G.C_TradeSkillUI = keptTS
end)

-- The client's own duration object (C_DurationUtil), handed over secret in a boss
-- fight. Its getters answer with secrets the time text can still show (the fake's
-- object used to do math on its secret fields).
T.test("a target's cast in a boss fight: the client's secret duration still writes the time", function()
    local _, ns = stub.Load({ module = true, login = false })
    local target = CreateFrame("Frame", nil, UIParent)
    local h = ns.CastBar.Create("target", target, CreateFrame("StatusBar", nil, target))
    ns.CastBar.Layout(h, ns.DEFAULTS.targetCastbar, ns.DEFAULTS.target)
    local d = C_DurationUtil.CreateDuration()
    d:SetTimeFromStart(GetTime(), 2)
    stub.units.target = { name = "Mob", reaction = 2, cast = { name = "Shadow Bolt", texture = 1, notInterruptible = false, duration = d } }
    stub.SetRestriction("Encounter", true)
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    stub.RunOnUpdate(h, 0.1)
    stub.SetRestriction("Encounter", false)
    T.eq(stub.Text(h.time), "2.0", "the time shows")
    T.truthy(type(h.time.__text) == "table", "drawn from a secret")
end)

-- Inside the target frame the cast bar was a square strip past the frame's angled
-- end, and a cast you can't interrupt was flat.
T.test("the target's cast bar inside its frame is cut to the frame's angle, as its power bar", function()
    local _, ns = stub.Load({ module = true })
    local h, f = ns.targetCastbar, ns.frames.target
    local Style = DaylightUI.Style
    -- The frame's cut, as on the power bar's empty part (its fill also has its
    -- own moving edge).
    local n = #(Style.BarBack(f.power).__masks or {})
    T.truthy(n > 0, "the power bar is cut")
    T.eq(#(h.bar:GetStatusBarTexture().__masks or {}), n, "the fill")
    T.eq(#(Style.BarBack(h.bar).__masks or {}), n, "the empty part")
    T.eq(#(h.bg.__masks or {}), n, "the backing")
end)

T.test("a cast you can't interrupt runs its own gradient", function()
    local h, ns = setup()
    ns.CastBar.cfg.fill = "pair"
    local lo = DaylightUI.Gradients.Colors("CAST_LOCKED")
    stub.units.player = { cast = { name = "X", notInterruptible = true, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local g = h.bar:GetStatusBarTexture().__gradient
    T.truthy(g, "a gradient fill")
    T.near(g[2].r, lo.r, 1e-6)
    -- A secret flag: the overlay carries the same gradient.
    stub.units.player = { cast = { name = "X", notInterruptible = stub.Secret(true), duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local o = h.lockTex
    T.truthy(o.__gradient, "the overlay is a gradient")
    T.near(o.__gradient[2].r, lo.r, 1e-6)
end)

-- The cast bar and swing timer in the look of a power bar moved on their own, and
-- slid out of it.
T.test("the player's cast bar and swing timer take their own border, and can slide out of the power bar standing on its own", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local Style = DUI.Style
    local h = ns.playerCastbar
    local s = Style.GetShell(h)
    T.isnil(s.opts.borderPx, "General's by default")
    DUI:Set("UnitFrames", "playerCastbar.shell.own", true)
    DUI:Set("UnitFrames", "playerCastbar.shell.borderPx", 3)
    DUI:Set("UnitFrames", "playerCastbar.shell.cornerPx", 2)
    stub.RunTimers()
    T.eq(s.opts.borderPx, 3, "its own border")
    T.eq(s.opts.cornerPx, 2, "its own corners")
    DUI:Set("UnitFrames", "swing.shell.own", true)
    DUI:Set("UnitFrames", "swing.shell.borderPx", 2)
    stub.RunTimers()
    for _, row in ipairs(ns.swing.rows) do
        T.eq(Style.GetShell(row).opts.borderPx, 2, "every swing bar's own border")
    end
    -- Hung under the frame by default, or under the power bar on its own.
    T.eq(h.under, ns.frames.player)
    DUI:Set("UnitFrames", "player.powerAt", "free")
    DUI:Set("UnitFrames", "playerCastbar.from", "power")
    stub.RunTimers()
    local pb = ns.frames.player.freePower
    T.truthy(pb:IsShown(), "the power bar on its own")
    T.eq(h.under, pb, "slides out from under the power bar")
    T.eq(ns.swing.castbar.under, pb, "the swing timer hangs from it too")
    local clipPoint = { h.clip:GetPoint(1) }
    T.eq(clipPoint[2], pb, "its clip starts at the power bar's bottom")
    DUI:Set("UnitFrames", "player.powerSlantBoth", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(pb).side, "both", "the power bar angled at both ends")
    T.eq(Style.GetSlant(h).side, "both", "the cast bar under it follows both")
    for _, row in ipairs(ns.swing.rows) do
        if row:IsShown() then T.eq(Style.GetSlant(row).side, "both", "and the swing bars") end
    end
    DUI:Set("UnitFrames", "player.powerSlantBoth", false)
    stub.RunTimers()
    T.eq(Style.GetSlant(pb).side, "right")
    -- Flipped, the cast bar still hangs from it and leans back in from its
    -- bottom corner: a chevron.
    DUI:Set("UnitFrames", "player.powerSlantUnder", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(pb).under, "right", "the power bar's end leans under")
    T.eq(h.under, pb, "the cast bar still slides out from the power bar")
    local hs = Style.GetSlant(h)
    T.eq(hs.side, "right"); T.isnil(hs.under, "it leans the usual way")
    T.eq(hs.ref.drop.right, pb:GetHeight(), "its line starts at the power bar's bottom corner")
    DUI:Set("UnitFrames", "player.powerSlantBoth", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(pb).under, "right", "its other end keeps its own lean")
    DUI:Set("UnitFrames", "player.powerSlantUnderLeft", true)
    stub.RunTimers()
    T.eq(Style.GetSlant(pb).under, "both", "both ends lean under")
    DUI:Set("UnitFrames", "player.powerSlantUnder", false)
    stub.RunTimers()
    T.eq(Style.GetSlant(pb).under, "left", "the left end alone")
    T.eq(h.under, pb, "either end flipped, it stays under the power bar")
    hs = Style.GetSlant(h)
    T.eq(hs.ref.drop.left, pb:GetHeight()); T.isnil(hs.ref.drop.right)
    DUI:Set("UnitFrames", "player.powerSlantUnder", true)
    -- The spell cost shade leans the same way as the fill it sits on.
    local cost, fill = pb.set.cost, pb.set.power
    local function sameAngle(why)
        local s1, c1, u1 = Style.GetFillAngle(fill)
        local s2, c2, u2 = Style.GetFillAngle(cost)
        T.eq(s2, s1, why .. ": side"); T.eq(c2, c1, why .. ": cut"); T.eq(u2, u1, why .. ": leans under")
    end
    T.eq(select(3, Style.GetFillAngle(fill)), true, "the fill leans under")
    sameAngle("leaning under")
    DUI:Set("UnitFrames", "player.reverseFill", true)
    stub.RunTimers()
    T.truthy(Style.GetFillAngle(fill), "reversed, the fill takes the other end's angle")
    sameAngle("reversed")
    DUI:Set("UnitFrames", "player.reverseFill", false)
    DUI:Set("UnitFrames", "player.powerSlantUnder", false)
    DUI:Set("UnitFrames", "player.powerSlantBoth", false)
    stub.RunTimers()
    T.isnil(Style.GetSlant(pb).under)
    T.eq(h.under, pb, "unflipped: from the power bar as before")
    T.isnil(Style.GetSlant(h).ref.drop.right, "its line from the power bar's top again")
    DUI:Set("UnitFrames", "player.powerAt", "inside")
    stub.RunTimers()
    T.eq(h.under, ns.frames.player, "the power bar back inside: under the frame again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Your interrupt (Pummel) on cooldown until cd.d ends, or ready.
local function markWorld(cd)
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "WARRIOR"
    stub.knownSpells = { [6552] = true }
    _G.GetShapeshiftForm = function() return 3 end
    local saved = { C_Spell.GetSpellCooldown, C_Spell.GetSpellCooldownDuration }
    C_Spell.GetSpellCooldown = function()
        return { isActive = cd.on == true, isOnGCD = cd.gcd, isEnabled = true, startTime = 0, duration = 0 }
    end
    C_Spell.GetSpellCooldownDuration = function() return cd.d end
    stub.FireEvent("SPELLS_CHANGED")
    local function restore()
        C_Spell.GetSpellCooldown, C_Spell.GetSpellCooldownDuration = saved[1], saved[2]
        _G.GetShapeshiftForm = nil
        stub.knownSpells = {}
    end
    return DUI, ns, restore
end

local function span(from, to, secret)
    local d = C_DurationUtil.CreateDuration()
    if secret then d:SetTimeSpan(stub.Secret(from), stub.Secret(to)) else d:SetTimeSpan(from, to) end
    return d
end

T.test("cast bars: an enemy target's cast marks where your interrupt comes back, off as shipped", function()
    local cd = { on = true }
    local DUI, ns, restore = markWorld(cd)
    T.eq(DUI:Get("UnitFrames", "casts.kickMark"), false, "off as shipped")
    local h = ns.targetCastbar
    local m = h.kickMark
    T.truthy(m, "the target's bar has one")
    T.truthy(ns.focusCastbar.kickMark and ns.targetCastbarFree.kickMark and ns.focusCastbarFree.kickMark)
    T.isnil(ns.playerCastbar and ns.playerCastbar.kickMark, "never on your own bar")
    local now = GetTime()
    cd.d = span(now - 5, now + 1)
    stub.units.target = { name = "Mob", reaction = 2, cast = { name = "Fireball", texture = 1, duration = span(now, now + 3) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.falsy(m.clip:IsShown(), "switched off: nothing")
    DUI:Set("UnitFrames", "casts.kickMark", true)
    stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(m.clip:IsShown(), "on cooldown: the mark shows")
    T.eq(stub.Plain(m.probe:GetValue()), now + 1, "at the moment it's ready")
    local lo, hi = m.probe:GetMinMaxValues()
    T.eq(stub.Plain(lo), now); T.eq(stub.Plain(hi), now + 3, "over the cast's span")
    -- Ready: gone, back when it goes on cooldown again.
    cd.on = false
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    stub.RunTimers()
    T.falsy(m.clip:IsShown(), "ready: gone")
    cd.on = true
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    stub.RunTimers()
    T.truthy(m.clip:IsShown(), "used mid-cast: it comes back")
    -- A friendly caster: no mark.
    stub.units.target.reaction = 5
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.falsy(m.clip:IsShown(), "not an enemy")
    stub.units.target.reaction = 2
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(m.clip:IsShown())
    -- The cast ends: the mark goes with it.
    stub.units.target.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "target")
    stub.RunTimers()
    T.falsy(m.clip:IsShown(), "cast over: gone")
    restore()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: the interrupt mark shows on a target cast bar sliding out under its frame", function()
    local cd = { on = true }
    local DUI, ns, restore = markWorld(cd)
    DUI:Set("UnitFrames", "casts.kickMark", true)
    DUI:Set("UnitFrames", "targetCastbar.at", "slide")
    stub.RunTimers()
    local h = ns.targetCastbarFree
    T.truthy(h.enabled); T.falsy(ns.targetCastbar.enabled, "the one inside steps aside")
    stub.EnterCombat()
    local now = GetTime()
    cd.d = span(now - 5, now + 1, true)
    stub.units.target = { name = "Mob", reaction = 2, cast = { name = "Fireball", texture = 1, duration = span(now, now + 3, true) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    stub.RunTimers()
    T.truthy(h.duration, "the bar it shows runs on the cast's duration")
    T.truthy(h.kickMark.clip:IsShown(), "on cooldown: the mark shows on the bar that's up")
    T.falsy(ns.targetCastbar.kickMark.clip:IsShown(), "and not on the one stepped aside")
    T.eq(stub.Plain(h.kickMark.probe:GetValue()), now + 1)
    stub.units.target.cast = nil
    stub.LeaveCombat()
    restore()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cast bars: the interrupt mark in a boss fight, every time secret, goes in whole", function()
    local cd = { on = true }
    local DUI, ns, restore = markWorld(cd)
    DUI:Set("UnitFrames", "casts.kickMark", true)
    stub.RunTimers()
    stub.EnterCombat()
    stub.SetRestriction("Encounter", true)
    local now = GetTime()
    cd.d = span(now - 5, now + 1, true)
    stub.units.focus = { name = "Boss", reaction = 2, channel = { name = "Drain Life", texture = 1, duration = span(now, now + 3, true) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "focus")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local m = ns.focusCastbar.kickMark
    T.truthy(m.clip:IsShown(), "shown")
    T.eq(stub.Plain(m.probe:GetValue()), now + 1, "the secret end time went in whole")
    stub.units.focus.channel = nil
    stub.SetRestriction("Encounter", false)
    stub.LeaveCombat()
    restore()
end)

-- A texture holds at most three masks, so the same mask added twice wastes a
-- slot. The target's and focus's cast bars sit in their power bars and are cut
-- like them, once.
T.test("cast bars inside the target and focus frames hold each mask once", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "target.width", 250)
    DUI:Set("UnitFrames", "focus.width", 210)
    for _, h in ipairs({ ns.targetCastbar, ns.focusCastbar }) do
        for _, tex in ipairs({ h.bg, h.bar:GetStatusBarTexture(), DUI.Style.BarBack(h.bar) }) do
            local seen = {}
            for _, m in ipairs(tex.__masks or {}) do
                T.isnil(seen[m], h.kind .. ": a mask added twice")
                seen[m] = true
            end
        end
    end
end)

T.test("a custom gradient fill: your colors on yours, the other bars' own on theirs", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "casts.fill", "customGradient")
    DUI:Set("UnitFrames", "casts.customGradient.count", 2)
    DUI:Set("UnitFrames", "casts.customGradient.c1", { 1, 0, 0 })
    DUI:Set("UnitFrames", "targetCasts.customGradient.count", 2)
    DUI:Set("UnitFrames", "targetCasts.customGradient.c1", { 0, 0, 1 })
    stub.RunTimers()
    stub.units.target = { name = "Mob", cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) } }
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE",
                          cast = { name = "Frostbolt", notInterruptible = false, duration = stub.Duration(1) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    local function first(h) return DUI.Style.FillColors(h.bar:GetStatusBarTexture())[3] end
    T.eq(first(ns.playerCastbar), DUI.Gradients.Stops(DUI:Get("UnitFrames", "casts.customGradient"))[1][3], "yours starts red")
    T.truthy(first(ns.targetCastbar) > 0.5, "the target's starts blue")
    T.truthy(ns.playerCastbar.bar:GetStatusBarTexture().__gradient, "two colors: the fill's own gradient")

    -- An interrupt shows its own color, with no gradient left over it.
    DUI:Set("UnitFrames", "casts.customGradient.count", 3)
    stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    ns.CastBar.Interrupted(ns.playerCastbar)
    local c = DUI:Get("UnitFrames", "casts.interrupted")
    T.eq(DUI.Style.FillColors(ns.playerCastbar.bar:GetStatusBarTexture())[1], c[1], "the interrupted color")
    T.isnil(DUI.Style.FillStops(ns.playerCastbar.bar:GetStatusBarTexture()), "the gradient's colors gone")
end)

T.test("a cast bar inside a frame fades the power text while it shows, never a free one", function()
    local _, ns = stub.Load({ module = true, login = false })
    local f = CreateFrame("Frame", nil, UIParent)
    f.power = CreateFrame("StatusBar", nil, f)
    f.power:SetStatusBarTexture([[Interface\Buttons\WHITE8x8]])
    f.powerText = f:CreateFontString(nil, "OVERLAY")
    local h = ns.CastBar.Create("target", f, f.power)
    T.eq(f.powerText:GetAlpha(), 1)
    h:Show()
    T.eq(f.powerText:GetAlpha(), 0, "faded under the spell name")
    h:Hide()
    T.eq(f.powerText:GetAlpha(), 1, "back when the cast ends")
    local g = CreateFrame("Frame", nil, UIParent)
    g.powerText = g:CreateFontString(nil, "OVERLAY")
    local free = ns.CastBar.Create("target")
    free:Show()
    T.eq(g.powerText:GetAlpha(), 1)
end)

-- A player's report: the target's power text came back over a mount being
-- summoned, now and then. Every power change wrote the text's alpha back to 1
-- (or to the full-power fade) under the cast bar.
T.test("the target's power text stays hidden under its cast bar through power changes and target swaps", function()
    local DUI, ns = stub.Load({ module = true })
    DUI:Set("UnitFrames", "target.showPowerText", true)
    stub.RunTimers()
    local f = _G.DaylightUIFrame_target
    local h = ns.targetCastbar
    stub.units.target = { name = "Rider", reaction = 4, power = 2600, powerMax = 2600,
        cast = { name = "Black Skeletal Horse", duration = stub.Duration(1.5) } }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.UnitWatch()
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(h:IsVisible(), "the cast shows inside the frame")
    T.truthy(f.powerText:IsShown(), "the power text is on")
    T.eq(f.powerText:GetAlpha(), 0, "hidden under the spell name")
    stub.FireEvent("UNIT_POWER_FREQUENT", "target", "MANA")
    T.eq(f.powerText:GetAlpha(), 0, "a power change keeps it hidden")
    stub.FireEvent("UNIT_MAXPOWER", "target", "MANA")
    stub.FireEvent("UNIT_DISPLAYPOWER", "target")
    T.eq(f.powerText:GetAlpha(), 0, "so does a new max or power type")
    -- A swap to another caster: the bar stays up, the frame redraws.
    stub.units.target = { name = "Other", reaction = 4, power = 100, powerMax = 2600,
        cast = { name = "Frostbolt", duration = stub.Duration(2) } }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.UnitWatch()
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.eq(f.powerText:GetAlpha(), 0, "a target swap mid-cast keeps it hidden")
    DUI:Set("UnitFrames", "target.hideFullPower", true)
    stub.RunTimers()
    stub.FireEvent("UNIT_POWER_FREQUENT", "target", "MANA")
    T.eq(f.powerText:GetAlpha(), 0, "the full-power fade doesn't bring it back either")
    DUI:Set("UnitFrames", "target.hideFullPower", false)
    stub.RunTimers()
    -- The cast ends: the text comes back and power changes show it again.
    stub.units.target.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "target")
    fadeOut()
    T.falsy(h:IsShown(), "the bar is gone")
    T.eq(f.powerText:GetAlpha(), 1, "back when the cast ends")
    stub.FireEvent("UNIT_POWER_FREQUENT", "target", "MANA")
    T.eq(f.powerText:GetAlpha(), 1, "and stays back")
    -- The target goes away mid-cast.
    stub.units.target.cast = { name = "Frostbolt", duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.eq(f.powerText:GetAlpha(), 0)
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.UnitWatch()
    stub.RunTimers()
    stub.units.target = { name = "Third", reaction = 4, power = 50, powerMax = 100 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.UnitWatch()
    stub.RunTimers()
    T.falsy(h:IsShown())
    T.eq(f.powerText:GetAlpha(), 1, "a new target with no cast shows its power text")
end)

-- A player's report: with the player frame set to fade, a cast bar hung under it
-- went behind it. A frame that fades as one picture (Fade's whole mode, drawn to
-- its own buffer) draws over a bar hung on its layer one step above it, so while
-- a cast bar hangs under a frame that frame fades piece by piece instead.
T.test("a frame with your cast bar hung under it or on its own never fades as one picture, and does again with the bar off", function()
    local DUI, ns = stub.Load({ module = true })
    local f = ns.frames.player
    function f:SetFlattensRenderLayers(on) self.flat = on end
    function f:SetIsFrameBuffer(on) self.buffer = on end
    local F = DUI.Fade
    local function settle()
        stub.RunTimers()
        for _ = 1, 3 do
            F.Step()
            for _ = 1, 60 do stub.RunOnUpdate(F.driver, 1 / 60) end
            stub.RunTimers()
        end
    end
    DUI:Set("UnitFrames", "player.fade", { mode = "ooc", alpha = 0.3, delay = 0 })
    DUI:Set("UnitFrames", "playerCastbar.at", "below")
    settle()
    T.truthy(ns.playerCastbar.column, "the bar hangs under the frame")
    T.falsy(f.buffer, "faded with a bar hung under it: piece by piece")
    -- A player's report after 2.2.6: a cast bar moved off on its own still went
    -- behind. A frame drawn to its own buffer covered it wherever it stood, its
    -- layer picked higher or not, so any cast bar of yours keeps it off.
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    DUI:Set("UnitFrames", "playerCastbar.strata", "HIGH")
    settle()
    T.falsy(ns.playerCastbar.column, "the bar stands on its own")
    T.eq(ns.playerCastbar:GetFrameStrata(), "HIGH", "in the layer picked for it")
    T.falsy(f.buffer, "the bar on its own: the frame still fades piece by piece")
    DUI:Set("UnitFrames", "player.powerAt", "free")
    settle()
    local pb = f.freePower
    T.truthy(pb, "the power bar on its own")
    function pb:SetFlattensRenderLayers(on) self.flat = on end
    function pb:SetIsFrameBuffer(on) self.buffer = on end
    DUI:Set("UnitFrames", "player.fade", { mode = "ooc", alpha = 0.2, delay = 0 })
    settle()
    T.falsy(pb.buffer, "and so do the pieces that fade with it")
    DUI:Set("UnitFrames", "player.powerAt", "inside")
    DUI:Set("UnitFrames", "playerCastbar.at", "below")
    settle()
    T.falsy(f.buffer, "hung again: piece by piece")
    DUI:Set("UnitFrames", "playerCastbar.enabled", false)
    settle()
    T.eq(f.buffer, true, "no cast bar at all: one picture")
    T.eq(pb.buffer, true, "its power bar too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bar ends: under a flipped player end the hung cast bar and swing bars lean back in, while sliding", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local Style = DUI.Style
    DUI:Set("UnitFrames", "player.slantUnder", true)
    DUI:Set("UnitFrames", "swing.attach", true)
    stub.RunTimers()
    local f, h = ns.frames.player, ns.playerCastbar
    T.eq(h.under, f)
    T.eq(Style.GetSlant(f).under, "right", "the player's right end flipped")
    local fH = f:GetHeight()
    -- Mid-slide and settled, its line starts at the frame's bottom corner.
    stub.units.player = stub.units.player or { name = "Me", isPlayer = true, class = "MAGE" }
    stub.units.player.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    for i = 1, 3 do
        local d = DaylightUI.Motion.Driver()
        if d and d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end
        local sl = Style.GetSlant(h)
        T.eq(sl.side, "right", "step " .. i)
        T.isnil(sl.under, "step " .. i .. ": it leans the usual way, top corner out")
        T.eq(sl.ref.drop.right, fH, "step " .. i .. ": from the frame's bottom corner")
    end
    -- The fill's edge leans the usual way too.
    local edge, _, under = Style.GetFillAngle(h.bar)
    T.eq(edge, "right"); T.falsy(under)
    for _, row in ipairs(ns.swing.rows) do
        local sl = Style.GetSlant(row)
        if row:IsShown() and sl and sl.ref then
            T.eq(sl.ref.drop.right, fH, "the swing bars carry on the same line")
        end
    end
    -- Back to the usual end: its line from the frame's top again.
    DUI:Set("UnitFrames", "player.slantUnder", false)
    stub.RunTimers()
    T.isnil(Style.GetSlant(h).ref.drop.right)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bar ends: a cast bar's end menus write its switches, each end on its own", function()
    local DUI, ns = stub.Load({ module = true })
    stub.RunTimers()
    local O = DUI.Options
    -- Each frame's page carries its cast bar's card.
    local rows, pageOf = {}, {}
    for id in O.Pages() do
        local page = O.GetPage(id)
        for _, g in ipairs(page and page.groups or {}) do
            for _, it in ipairs(g.items or {}) do
                if it.ends then rows[it.label], pageOf[it.label] = it, page end
            end
        end
    end
    local function set(label, v) O.Set(pageOf[label], rows[label], v) end
    for _, who in ipairs({ "Your cast bar", "Target cast bar", "Focus cast bar", "Party cast bar" }) do
        T.truthy(rows[who .. " left end"] and rows[who .. " right end"], who .. ": both end menus")
    end
    T.falsy(rows["Your cast bar flip right end"], "no flip switches left")
    -- The target's bar above the frame: \--/ is the left end usual, the right end usual.
    DUI:Set("UnitFrames", "targetCastbar.at", "above")
    set("Target cast bar left end", "slash")
    set("Target cast bar right end", "backslash")
    stub.RunTimers()
    local sl = DUI.Style.GetSlant(ns.targetCastbarFree)
    T.eq(sl.side, "both"); T.eq(sl.under, "both", "/--\\")
end)
