local stub = require("stub")

-- The unit frames' colors and text formats.

local function login() return stub.Load({ module = true }) end

-- The client's color curve, standing in: points kept, evaluated linearly.
local function fakeCurves()
    _G.C_CurveUtil = {
        CreateColorCurve = function()
            local c = { points = {} }
            function c:SetType() end
            function c:AddPoint(x, col) self.points[#self.points + 1] = { x, col } end
            return c
        end,
        CreateCurve = function()
            local c = { points = {} }
            function c:SetType() end
            function c:AddPoint(x, y) self.points[#self.points + 1] = { x, y } end
            return c
        end,
    }
    _G.Enum.LuaCurveType = { Linear = 0 }
    local real = _G.UnitHealthPercent
    _G.UnitHealthPercent = function(u, predicted, curve)
        if type(curve) == "table" and curve.points and type(curve.points[1][2]) == "table" then
            local p = (stub.units[u] and stub.units[u].pct or 0) / 100
            local col = p >= 0.75 and curve.points[3][2] or p >= 0.25 and curve.points[2][2] or curve.points[1][2]
            return { GetRGB = function() return col.r, col.g, col.b end }
        elseif type(curve) == "table" and curve.points then
            local p = (stub.units[u] and stub.units[u].pct or 0) / 100
            return p >= 1 and 0 or 1
        end
        return real(u, predicted, curve)
    end
end

T.test("colors: health by class (as before), one color, or dark with the missing part colored", function()
    local DUI, ns = login()
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "colors.health", "class")
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    local f = ns.frames.player
    ns.UF.UpdateAll(f, true)
    T.rgb(f.health.__barColor, { S.ClassColor("MAGE") }, "class")
    DUI:Set("UnitFrames", "colors.health", "custom")
    DUI:Set("UnitFrames", "colors.healthColor", { 1, 0, 1 })
    stub.RunTimers()
    T.rgb(f.health.__barColor, { S.Soften(1, 0, 1) }, "your own color")
    DUI:Set("UnitFrames", "colors.health", "dark")
    stub.RunTimers()
    T.rgb(f.health.__barColor, ns.UF.DARK_FILL, "a dark fill")
    local back = S.BarBack(f.health).__vertex
    T.rgb(back, { S.ClassColor("MAGE") }, "the missing part in the class color")
end)

T.test("colors: the gradient follows health through the client's curve", function()
    fakeCurves()
    local DUI, ns = login()
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "colors.health", "gradient")
    stub.RunTimers()
    local f = ns.frames.player
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 90, maxHealth = 100, pct = 90 }
    ns.UF.UpdateHealth(f, true)
    T.rgb(f.health.__barColor, { ns.UF.GradientAt(1) }, "green when full")
    stub.units.player.pct = 10
    ns.UF.UpdateHealth(f, true)
    T.rgb(f.health.__barColor, { ns.UF.GradientAt(0) }, "red when low")
    local r, g = ns.UF.GradientAt(0.5)
    T.truthy(r > 0.5 and g > 0.5, "yellow at half")
    _G.C_CurveUtil = nil
end)

T.test("colors: class gradient paints the unit's pair on the health fill", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "colors.health", "classGradient")
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    local f = ns.frames.player
    ns.UF.UpdateAll(f, true)
    local lo, hi = DUI.Gradients.Colors("MAGE")
    local grad = f.health:GetStatusBarTexture().__gradient
    T.truthy(grad, "gradient set")
    T.eq(grad[2], lo); T.eq(grad[3], hi)
    -- test mode: the sample's class
    f.test = { class = "WARRIOR", health = 80 }
    ns.UF.ShowSample(f)
    lo, hi = DUI.Gradients.Colors("WARRIOR")
    grad = f.health:GetStatusBarTexture().__gradient
    T.eq(grad[2], lo); T.eq(grad[3], hi)
    f.test = nil
end)

T.test("colors: the target's class gradient mirrors the player's, unless turned off", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "colors.health", "classGradient")
    stub.units.target = { name = "Them", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    local f = ns.frames.target
    local lo, hi = DUI.Gradients.Colors("MAGE")
    ns.UF.UpdateAll(f, true)
    local grad = f.health:GetStatusBarTexture().__gradient
    T.eq(grad[2], hi, "mirrored by default"); T.eq(grad[3], lo)
    stub.units.targettarget = { name = "Other", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    ns.UF.UpdateAll(ns.frames.targettarget, true)
    local tot = ns.frames.targettarget.health:GetStatusBarTexture().__gradient
    T.eq(tot[2], hi, "target of target too"); T.eq(tot[3], lo)
    DUI:Set("UnitFrames", "colors.mirrorGradient", false)
    ns.UF.UpdateAll(f, true)
    grad = f.health:GetStatusBarTexture().__gradient
    T.eq(grad[2], lo, "off: same way as the player"); T.eq(grad[3], hi)
    DUI:Set("UnitFrames", "colors.mirrorGradient", true)
    DUI:Set("general", "gradients.orientation", "VERTICAL")
    ns.UF.UpdateAll(f, true)
    lo, hi = DUI.Gradients.Colors("MAGE")
    grad = f.health:GetStatusBarTexture().__gradient
    T.eq(grad[2], lo, "a vertical gradient isn't mirrored"); T.eq(grad[3], hi)
end)

T.test("colors: an enemy whose class the game hides (battlegrounds) still shows its class", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "colors.health", "classGradient")
    stub.units.target = { name = "Rival", isPlayer = true, class = "MAGE", classHidden = true, reaction = 2,
        health = 50, maxHealth = 100, pct = 50 }
    local f = ns.frames.target
    ns.UF.UpdateAll(f, true)
    local mage, rogue = f.classLayers and f.classLayers.MAGE, f.classLayers and f.classLayers.ROGUE
    T.truthy(mage, "class layers built")
    T.truthy(mage:IsShown(), "shown")
    T.truthy(issecretvalue(mage.__cell), "the secret id goes straight to the sheet")
    T.eq(mage.__cell.__value, 8, "mage's cell")
    local lo, hi = DUI.Gradients.Colors("MAGE")
    T.eq(mage.__gradient[2], hi, "the mage pair, mirrored like the target's fill"); T.eq(mage.__gradient[3], lo)
    T.eq(rogue.__gradient[3], (DUI.Gradients.Colors("ROGUE")), "each layer its own class's pair")
    -- flat class colors
    DUI:Set("UnitFrames", "colors.health", "class")
    ns.UF.UpdateAll(f, true)
    T.rgb(mage.__vertex, { DUI.Style.ClassColor("MAGE") }, "flat class color")
    T.truthy(mage:IsShown())
    -- other modes, a dead unit, or a class the game shows: no layers
    DUI:Set("UnitFrames", "colors.health", "custom")
    ns.UF.UpdateAll(f, true)
    T.falsy(mage:IsShown(), "custom color: hidden")
    DUI:Set("UnitFrames", "colors.health", "classGradient")
    stub.units.target.classHidden = nil
    ns.UF.UpdateAll(f, true)
    T.falsy(mage:IsShown(), "a plain class paints the fill itself")
end)

T.test("colors: a hidden class (battlegrounds) colors the name and health text too", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "colors.name", "classGradient")
    DUI:Set("UnitFrames", "target.percentColor", "class")
    stub.units.target = { name = "Rival", isPlayer = true, class = "MAGE", classHidden = true, reaction = 2,
        health = 50, maxHealth = 100, pct = 50 }
    local f = ns.frames.target
    ns.UF.UpdateAll(f, true)
    local c = f.nameText.__textColor
    T.truthy(issecretvalue(c[1]), "the client's class color, as it gives it")
    T.eq(c[1].__value, RAID_CLASS_COLORS.MAGE.r)
    T.isnil(f.nameKey, "no letters in the fallback pair")
    T.eq(f.nameText.__text, "Rival")
    T.eq(f.percentText.__textColor[1].__value, RAID_CLASS_COLORS.MAGE.r, "health text")
    -- white stays white
    DUI:Set("UnitFrames", "colors.name", "white")
    ns.UF.UpdateAll(f, true)
    T.falsy(issecretvalue(f.nameText.__textColor[1]))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("colors: class gradient reads a hidden class from the unit's group token", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "colors.health", "classGradient")
    stub.units.party1 = { name = "Friend", isPlayer = true, class = "HUNTER", health = 50, maxHealth = 100, pct = 50 }
    stub.units.targettarget = { name = "Friend", isPlayer = true, class = "HUNTER", classHidden = true,
        health = 50, maxHealth = 100, pct = 50 }
    local realIsUnit = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b) return (a == "targettarget" and b == "party1") or a == b end
    local f = ns.frames.targettarget
    ns.UF.UpdateAll(f, true)
    _G.UnitIsUnit = realIsUnit
    local lo, hi = DUI.Gradients.Colors("HUNTER")
    local grad = f.health:GetStatusBarTexture().__gradient
    T.eq(grad[2], hi, "the hunter pair (mirrored)"); T.eq(grad[3], lo)
    T.falsy(f.classLayers and f.classLayers.HUNTER:IsShown(), "no layers: the class is known")
end)

T.test("colors: power gradient paints the power type's pair, mirrored on the target", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "colors.power", "gradient")
    stub.units.player = { name = "Me", isPlayer = true, class = "WARRIOR", powerToken = "RAGE", power = 5, maxPower = 10 }
    local f = ns.frames.player
    ns.UF.UpdateAll(f, true)
    local lo, hi = DUI.Gradients.Colors("RAGE")
    local grad = f.power:GetStatusBarTexture().__gradient
    T.truthy(grad, "gradient set")
    T.eq(grad[2], lo); T.eq(grad[3], hi)
    stub.units.target = { name = "Them", isPlayer = true, class = "ROGUE", powerToken = "ENERGY", power = 5, maxPower = 10 }
    ns.UF.UpdateAll(ns.frames.target, true)
    lo, hi = DUI.Gradients.Colors("ENERGY")
    grad = ns.frames.target.power:GetStatusBarTexture().__gradient
    T.eq(grad[2], hi, "target mirrored"); T.eq(grad[3], lo)
end)

T.test("colors: power in one color; names in the unit's color", function()
    local DUI, ns = login()
    local S = DaylightUI.Style
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", powerToken = "MANA", power = 5, maxPower = 10 }
    DUI:Set("UnitFrames", "colors.power", "custom")
    DUI:Set("UnitFrames", "colors.powerColor", { 0, 1, 0 })
    DUI:Set("UnitFrames", "colors.name", "class")
    stub.RunTimers()
    local f = ns.frames.player
    ns.UF.UpdateAll(f, true)
    T.rgb(f.power.__barColor, { S.Soften(0, 1, 0) }, "power")
    local r, g, b = S.ClassColor("MAGE")
    T.rgb(f.nameText.__textColor, { S.Lighten(r, g, b, 0.3) }, "name")
    DUI:Set("UnitFrames", "colors.backBrightness", 0.1)
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    local _, g2 = S.Soften(0, 1, 0)
    T.truthy(math.abs(S.BarBack(f.power).__vertex[2] - g2 * 0.1) < 1e-6, "the empty part dimmer")
end)

T.test("text: every health format, secret or not", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Mob", reaction = 2, health = 4100, maxHealth = 6600, pct = 62 }
    local function show(fmt)
        DUI:Set("UnitFrames", "target.healthText", fmt)
        stub.RunTimers()
        ns.UF.UpdateHealth(f, true)
        return stub.Text(f.percentText)
    end
    T.eq(show("percent"), "62")
    T.eq(show("value"), "4.1K")
    T.eq(show("valuemax"), "4.1K / 6.6K")
    T.eq(show("both"), "4.1K | 62%")
    T.eq(show("missing"), "-2.5K")
    T.eq(show("full"), "4,100", "the whole number, whatever the number style")
    stub.units.target.health = stub.Secret(4100)
    T.eq(show("full"), "4,100", "a secret health in full")
    show("valuemax")
    T.truthy(f.percentText:IsShown(), "a secret health still writes")
end)

T.test("text: the number style (General > Appearance) writes health and power, secret or not", function()
    local DUI, ns = login()
    local f, p = ns.frames.target, ns.frames.player
    stub.units.target = { name = "Mob", reaction = 2, health = 12345, maxHealth = 1234567, pct = 1 }
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", powerToken = "MANA", power = 1234, maxPower = 2900 }
    DUI:Set("UnitFrames", "target.healthText", "valuemax")
    DUI:Set("UnitFrames", "player.showPowerText", true)
    local function show(style)
        DUI:Set("general", "numbers", style)
        stub.RunTimers()
        ns.UF.UpdateHealth(f, true)
        ns.UF.UpdatePower(p, true)
        return stub.Text(f.percentText), stub.Text(p.powerText)
    end
    T.eq(DUI:Get("general", "numbers"), "short", "short by default")
    local h, pw = show("exact")
    T.eq(h, "12.3K / 1.23M", "more exact")
    T.eq(pw, "1.23K", "more exact power")
    h, pw = show("full")
    T.eq(h, "12,345 / 1,234,567", "full")
    T.eq(pw, "1,234", "full power")
    h = show("upto")
    T.eq(h, "12345 / 1.2M", "full up to 100K")
    stub.units.target.health = stub.Secret(12345)
    T.eq(show("full"), "12,345 / 1,234,567", "a secret health in full")
    T.eq(show("exact"), "12.3K / 1.23M", "a secret health, more exact")
end)

T.test("text: missing health shows nothing at full", function()
    fakeCurves()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Mob", reaction = 2, health = 6600, maxHealth = 6600, pct = 100 }
    DUI:Set("UnitFrames", "target.healthText", "missing")
    stub.RunTimers()
    ns.UF.UpdateHealth(f, true)
    T.eq(stub.Plain(f.percentText:GetAlpha()), 0, "hidden at full")
    stub.units.target.pct, stub.units.target.health = 50, 3300
    ns.UF.UpdateHealth(f, true)
    T.eq(stub.Plain(f.percentText:GetAlpha()), 1, "shown when hurt")
    _G.C_CurveUtil = nil
end)

T.test("text: power formats", function()
    local DUI, ns = login()
    local f = ns.frames.player
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", powerToken = "MANA", power = 2300, maxPower = 2900 }
    DUI:Set("UnitFrames", "player.showPowerText", true)
    DUI:Set("UnitFrames", "player.powerFormat", "valuemax")
    stub.RunTimers()
    ns.UF.UpdatePower(f, true)
    T.eq(f.powerText.__text, "2.3K / 2.9K")
end)

T.test("text: power text hides at full, when asked", function()
    fakeCurves()
    local saved = _G.UnitPowerPercent
    _G.UnitPowerPercent = function(u, _, _, curve)
        local x = stub.units[u]
        local p = x and x.power / x.maxPower or 0
        if type(curve) == "table" and curve.points then return p >= 1 and 0 or 1 end
        return p * 100
    end
    local DUI, ns = login()
    local f = ns.frames.player
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", powerToken = "MANA", power = 2900, maxPower = 2900 }
    DUI:Set("UnitFrames", "player.showPowerText", true)
    stub.RunTimers()
    ns.UF.UpdatePower(f, true)
    T.eq(f.powerText:GetAlpha(), 1, "off by default: shown at full")
    DUI:Set("UnitFrames", "player.hideFullPower", true)
    stub.RunTimers()
    ns.UF.UpdatePower(f, true)
    T.eq(f.powerText:GetAlpha(), 0, "hidden at full")
    stub.units.player.power = 1200
    ns.UF.UpdatePower(f, true)
    T.eq(f.powerText:GetAlpha(), 1, "shown once spent")
    T.eq(f.powerText.__text, "1.2K")
    _G.UnitPowerPercent, _G.C_CurveUtil = saved, nil
end)

T.test("text: each frame has its own sizes; the old shared ones carry over", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "targetText.name", 15)
    stub.RunTimers()
    T.eq(ns.frames.target.nameText.__font[2], 15, "the target's")
    T.falsy(ns.frames.player.nameText.__font[2] == 15, "not the player's")
    DUI, ns = stub.Load({ module = true, before = function()
        DaylightUIDB = { modules = { UnitFrames = { text = { name = 16, percent = 9, cast = 13 } } } }
    end })
    T.eq(DUI:Get("UnitFrames", "playerText.name"), 16)
    T.eq(DUI:Get("UnitFrames", "focusText.name"), 16)
    T.eq(DUI:Get("UnitFrames", "petText.name"), 9, "the small frames' names were at the health size")
    T.eq(DUI:Get("UnitFrames", "playerCastbar.spell.size"), 13, "the cast bars keep theirs, each its own")
    T.eq(DUI:Get("UnitFrames", "playerCastbar.time.size"), 13)
    T.eq(DUI:Get("UnitFrames", "swing.textSize"), 13)
    T.isnil(DUI:Get("UnitFrames", "text.name"))
end)

T.test("text: power and percent together", function()
    local DUI, ns = login()
    local f = ns.frames.player
    _G.UnitPowerPercent = function() return 80 end
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", powerToken = "MANA", power = 2300, maxPower = 2900 }
    DUI:Set("UnitFrames", "player.showPowerText", true)
    DUI:Set("UnitFrames", "player.powerFormat", "both")
    stub.RunTimers()
    ns.UF.UpdatePower(f, true)
    T.eq(f.powerText.__text, "2.3K | 80%")
    _G.UnitPowerPercent = nil
end)

T.test("text: % after a percent, when asked", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Mob", reaction = 2, health = 4100, maxHealth = 6600, pct = 62 }
    DUI:Set("UnitFrames", "target.healthText", "percent")
    stub.RunTimers()
    ns.UF.UpdateHealth(f, true)
    T.eq(stub.Text(f.percentText), "62", "off by default")
    DUI:Set("UnitFrames", "target.percentSign", true)
    stub.RunTimers()
    ns.UF.UpdateHealth(f, true)
    T.eq(stub.Text(f.percentText), "62%")
end)

T.test("a frame's bars can fill from the other end", function()
    local DUI, ns = login()
    local f = ns.frames.target
    T.eq(f.health.__reverse, true, "the target mirrors the player")
    DUI:Set("UnitFrames", "target.reverseFill", true)
    stub.RunTimers()
    T.eq(f.health.__reverse, false, "turned round")
    T.eq(f.power.__reverse, false)
end)

T.test("your health in the Daylight gradient: the player's bar only", function()
    local _, ns = stub.Load({ module = true, login = false })
    ns.UF.ConfigureColors({ health = "class", backBrightness = 0.4 })
    local f = ns.UF.Create({ unit = "player", name = "DaylightUIFrame_gradtest" })
    f.healthMode = "daylight"   -- the player page's Health bar color
    ns.UF.PaintHealth(f, 1, 0, 0)
    local function file(bar) return tostring(bar:GetStatusBarTexture().__texture or bar.__barTexture) end
    T.truthy(file(f.health):find("gradient%-daylight"), "the gradient on your bar")
    local t = ns.UF.Create({ unit = "target", name = "DaylightUIFrame_gradtest2" })
    ns.UF.PaintHealth(t, 1, 0, 0)
    T.falsy(file(t.health):find("gradient%-daylight"), "not on others")
    f.healthMode = "global"
    ns.UF.PaintHealth(f, 1, 0, 0)
    T.falsy(file(f.health):find("gradient%-daylight"), "switched off: our fill again")
end)

T.test("your health in the accent: follows it live, gradient or one color, your bar only", function()
    local DUI, ns = login()
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "colors.health", "class")
    DUI:Set("UnitFrames", "colors.backBrightness", 0.5)
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    stub.units.target = { name = "Bob", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    DUI:Set("UnitFrames", "player.colorHealth", "accent")
    DUI:Set("general", "accent", "classGradient")
    stub.RunTimers()
    local me, them = ns.frames.player, ns.frames.target
    ns.UF.UpdateAll(me, true)
    ns.UF.UpdateAll(them, true)
    local lo, hi = S.AccentPair()
    local g = me.health:GetStatusBarTexture().__gradient
    T.truthy(g, "the class pair across your fill")
    T.near(g[2].r, lo[1], 1e-6); T.near(g[3].r, hi[1], 1e-6)
    local back = S.BarBack(me.health)
    local ar = S.Accent()
    T.near(back:GetVertexColor(), ar * 0.5, 1e-6, "the empty part at the Colors page's brightness")
    T.rgb(them.health.__barColor, { S.ClassColor("MAGE") }, "the target keeps the Colors page's")

    DUI:Set("general", "accent", "gradient")
    stub.RunTimers()
    T.eq(me.health:GetStatusBarTexture().__texture, S.GRADIENT_FILE, "a new accent reaches the bar: Daylight's sweep")

    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    stub.RunTimers()
    T.truthy(me.health:GetStatusBarTexture().__texture ~= S.GRADIENT_FILE, "the sweep comes off")
    T.rgb(me.health.__barColor, { S.Accent() }, "a one-color accent: that color")

    me.state = "dead"
    ns.UF.PaintHealth(me, 0.4, 0.4, 0.4)
    T.rgb(me.health.__barColor, { 0.4, 0.4, 0.4 }, "dead: the plain color, like every mode")
    me.state = nil
end)

T.test("colors: a frame's own health and power colors win over the Colors page's, only on that frame", function()
    local DUI, ns = login()
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "colors.health", "class")
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    stub.units.target = { name = "Bob", isPlayer = true, class = "MAGE", health = 50, maxHealth = 100, pct = 50 }
    DUI:Set("UnitFrames", "player.colorHealth", "custom")
    DUI:Set("UnitFrames", "player.colorHealthCustom", { 1, 0, 1 })
    DUI:Set("UnitFrames", "player.colorPower", "custom")
    DUI:Set("UnitFrames", "player.colorPowerCustom", { 0, 1, 1 })
    stub.RunTimers()
    local me, them = ns.frames.player, ns.frames.target
    ns.UF.UpdateAll(me, true)
    ns.UF.UpdateAll(them, true)
    T.rgb(me.health.__barColor, { S.Soften(1, 0, 1) }, "the player's own color")
    T.rgb(me.power.__barColor, { S.Soften(0, 1, 1) }, "the player's own power color")
    T.rgb(them.health.__barColor, { S.ClassColor("MAGE") }, "the target keeps the Colors page's")
    DUI:Set("UnitFrames", "player.colorHealth", "global")
    stub.RunTimers()
    ns.UF.UpdateAll(me, true)
    T.rgb(me.health.__barColor, { S.ClassColor("MAGE") }, "back to the Colors page's")
end)
