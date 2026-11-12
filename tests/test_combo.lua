local stub = require("stub")

local function login(class, token)
    return stub.Load({ module = true, before = function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = class, powerToken = token or "ENERGY" }
    end })
end

T.test("only rogues and druids get combo points", function()
    local _, ns = login("MAGE", "MANA")
    T.isnil(ns.combo)
    _, ns = login("ROGUE")
    T.truthy(ns.combo)
    T.eq(#ns.combo.pips, 5)
end)

T.test("pips sit under the target, past its angled end, and fill with the count", function()
    local _, ns = login("ROGUE")
    local c = ns.combo
    local p, rel, rp = c:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, ns.frames.target); T.eq(rp, "BOTTOMLEFT")
    for i, pip in ipairs(c.pips) do
        local lo, hi = pip.bar.__min, pip.bar.__max
        T.eq(lo, i - 1); T.eq(hi, i)
    end
    stub.comboPoints = 3
    ns.Combo.Update(c)
    T.truthy(c:IsShown())
    T.eq(c.pips[1].bar.__value, 3)
    T.eq(c.pips[5].bar.__value, 3)
    stub.comboPoints = nil
end)

T.test("a secret count still reaches the pips", function()
    local _, ns = login("ROGUE")
    local s = stub.Secret(2)
    stub.comboPoints = s
    ns.Combo.Update(ns.combo)
    T.eq(ns.combo.pips[3].bar.__value, s)
    stub.comboPoints = nil
end)

T.test("druids only see pips in cat form", function()
    local _, ns = login("DRUID", "MANA")
    ns.Combo.Update(ns.combo)
    T.falsy(ns.combo:IsShown())
    stub.units.player.powerToken = "ENERGY"
    ns.Combo.Update(ns.combo)
    T.truthy(ns.combo:IsShown())
end)

T.test("turning combo points off hides them", function()
    local DUI, ns = login("ROGUE")
    DUI:Set("UnitFrames", "combo.enabled", false)
    T.falsy(ns.combo:IsShown())
end)

T.test("pips lean the same way as the target's angled end", function()
    local _, ns = login("ROGUE")
    for _, pip in ipairs(ns.combo.pips) do
        T.eq(DaylightUI.Style.GetSlant(pip).side, ns.frames.target.spec.slant)
    end
end)

T.test("angled ends off: the pips are whole, outline and background round both ends", function()
    local DUI, ns = login("ROGUE")
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "combo.slant", false)
    stub.RunTimers()
    for _, pip in ipairs(ns.combo.pips) do
        local s = S.GetShell(pip)
        T.isnil(S.GetSlant(pip).side, "no angled end")
        T.truthy(s.border.LEFT:IsShown() and s.border.RIGHT:IsShown(), "both side edges")
        T.eq(#(s.bg.__masks or {}), 0, "the background isn't masked")
    end
end)

T.test("the last pip is red, so a full row stands out; off, it matches the rest", function()
    local DUI, ns = login("ROGUE")
    local S = DaylightUI.Style
    local red = { S.Soften(ns.Combo.FULL_COLOR[1], ns.Combo.FULL_COLOR[2], ns.Combo.FULL_COLOR[3]) }
    local gold = { S.Soften(ns.Combo.COLOR[1], ns.Combo.COLOR[2], ns.Combo.COLOR[3]) }
    T.rgb(ns.combo.pips[5].bar.__barColor, red, "the fifth")
    local back = S.BarBack(ns.combo.pips[5].bar).__vertex
    T.near(back[1], gold[1] * S.BAR_BACK_DIM, 1e-6, "its empty part gold like the rest: red only when filled")
    T.rgb(ns.combo.pips[4].bar.__barColor, gold, "the rest")
    DUI:Set("UnitFrames", "combo.fullRed", false)
    stub.RunTimers()
    T.rgb(ns.combo.pips[5].bar.__barColor, gold, "off")
end)

T.test("a custom color shows on the pips", function()
    local DUI, ns = login("ROGUE")
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "combo.color", { 0.2, 0.6, 0.9 })
    stub.RunTimers()
    T.rgb(ns.combo.pips[1].bar.__barColor, { S.Soften(0.2, 0.6, 0.9) }, "pip 1")
end)

T.test("spacing moves the pips apart", function()
    local DUI, ns = login("ROGUE")
    local size = DUI:Get("UnitFrames", "combo.size")
    DUI:Set("UnitFrames", "combo.gap", 6)
    stub.RunTimers()
    local _, _, _, x = ns.combo.pips[2]:GetPoint(1)
    T.eq(x, size + 6)
end)

T.test("outline 0 and gradient on don't error; the last pip stays red", function()
    local DUI, ns = login("ROGUE")
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "combo.border", 0)
    DUI:Set("UnitFrames", "combo.colorMode", "gradient")
    stub.RunTimers()
    local red = { S.Soften(ns.Combo.FULL_COLOR[1], ns.Combo.FULL_COLOR[2], ns.Combo.FULL_COLOR[3]) }
    T.rgb(ns.combo.pips[5].bar.__barColor, red, "the fifth")
    DUI:Set("UnitFrames", "combo.slant", false)
    stub.RunTimers()
end)

T.test("above the target: over its name tab, and the debuffs rise past the pips", function()
    local DUI, ns = login("ROGUE")
    local t = ns.frames.target
    local _, _, _, _, debuffY = ns.auras.debuffs:GetPoint(1)
    DUI:Set("UnitFrames", "combo.side", "above")
    stub.RunTimers()
    local p, rel, rp, _, y = ns.combo:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, t); T.eq(rp, "TOPLEFT")
    T.truthy(y >= t.tab:GetHeight(), "clear of the name tab")
    T.eq(ns.auras.buffDrop, 0, "the buffs under it close up")
    local _, _, _, _, liftedY = ns.auras.debuffs:GetPoint(1)
    T.eq(liftedY, debuffY + ns.Combo.Lift(DUI:Get("UnitFrames", "combo")), "the debuffs above the pips")
end)

T.test("centered, outer end, and stretched across the frame", function()
    local DUI, ns = login("ROGUE")
    local t = ns.frames.target
    DUI:Set("UnitFrames", "combo.align", "center")
    stub.RunTimers()
    local p, _, rp, x = ns.combo:GetPoint(1)
    T.eq(p, "TOP"); T.eq(rp, "BOTTOM"); T.eq(x, 0)
    DUI:Set("UnitFrames", "combo.align", "outer")
    stub.RunTimers()
    p, _, rp = ns.combo:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rp, "BOTTOMRIGHT")
    DUI:Set("UnitFrames", "combo.stretch", true)
    stub.RunTimers()
    p = ns.combo:GetPoint(1)
    T.eq(p, "TOPLEFT", "stretched rows start at the inner end")
    T.truthy(ns.combo:GetWidth() > 5 * 14 + 4 * 3, "wider than the default row")
    T.truthy(ns.combo:GetWidth() <= t:GetWidth(), "within the frame")
end)

T.test("on the player, above: from its inner (right) end", function()
    local DUI, ns = login("ROGUE")
    DUI:Set("UnitFrames", "combo.anchor", "player")
    DUI:Set("UnitFrames", "combo.side", "above")
    stub.RunTimers()
    local p, rel, rp = ns.combo:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, ns.frames.player); T.eq(rp, "TOPRIGHT")
    T.eq(ns.auras.aboveLift, 0, "the target's debuffs stay put")
end)

T.test("colors: one color, color to full color, class color, a pair per point", function()
    local DUI, ns = login("ROGUE")
    local S, G = DaylightUI.Style, DaylightUI.Gradients
    local pips = ns.combo.pips
    DUI:Set("UnitFrames", "combo.color", { 0.2, 0.6, 0.9 })
    DUI:Set("UnitFrames", "combo.fullColor", { 1, 0, 0 })
    DUI:Set("UnitFrames", "combo.colorMode", "blend")
    stub.RunTimers()
    T.rgb(pips[1].bar.__barColor, { S.Soften(0.2, 0.6, 0.9) }, "the first: Color")
    T.rgb(pips[3].bar.__barColor, { S.Soften(0.6, 0.3, 0.45) }, "halfway")
    T.rgb(pips[5].bar.__barColor, { S.Soften(1, 0, 0) }, "the last: Full color")
    DUI:Set("UnitFrames", "combo.colorMode", "class")
    stub.RunTimers()
    T.rgb(pips[2].bar.__barColor, { S.ClassColor("ROGUE") }, "class color")
    DUI:Set("UnitFrames", "combo.colorMode", "points")
    stub.RunTimers()
    local k = S.BAR_BACK_DIM
    for i = 1, 5 do
        local r = G.Mid("COMBO_" .. i)
        T.near(S.BarBack(pips[i].bar).__vertex[1], r * k, 1e-6, "pip " .. i .. " its own pair")
    end
end)

T.test("whole row at full points: every pip's overlay spans the last point", function()
    local DUI, ns = login("ROGUE")
    local S = DaylightUI.Style
    local pips = ns.combo.pips
    T.falsy(pips[1].full:IsShown(), "off to start with")
    DUI:Set("UnitFrames", "combo.fullAll", true)
    stub.RunTimers()
    local red = { S.Soften(ns.Combo.FULL_COLOR[1], ns.Combo.FULL_COLOR[2], ns.Combo.FULL_COLOR[3]) }
    for _, pip in ipairs(pips) do
        T.truthy(pip.full:IsShown())
        T.eq(pip.full.__min, 4); T.eq(pip.full.__max, 5)
        T.rgb(pip.full.__barColor, red)
    end
    stub.comboPoints = 5
    ns.Combo.Update(ns.combo)
    T.eq(pips[1].full.__value, 5, "fills at five")
    stub.comboPoints = nil
    DUI:Set("UnitFrames", "combo.fullRed", false)
    stub.RunTimers()
    T.falsy(pips[1].full:IsShown(), "only with the full color on")
end)

T.test("empty pips: their brightness follows the setting", function()
    local DUI, ns = login("ROGUE")
    local S = DaylightUI.Style
    DUI:Set("UnitFrames", "combo.empty", 0.1)
    stub.RunTimers()
    local r = S.Soften(ns.Combo.COLOR[1], ns.Combo.COLOR[2], ns.Combo.COLOR[3])
    T.near(S.BarBack(ns.combo.pips[1].bar).__vertex[1], r * 0.1, 1e-6)
end)

T.test("upgrade: a profile with the old Gradient switch on keeps its gradient", function()
    local _, ns = login("ROGUE")
    local uf = { combo = { gradient = true } }
    ns.UPGRADE_STEPS[6](uf)
    T.eq(uf.combo.colorMode, "gradient"); T.isnil(uf.combo.gradient)
    uf = { combo = { gradient = false } }
    ns.UPGRADE_STEPS[6](uf)
    T.isnil(uf.combo.colorMode); T.isnil(uf.combo.gradient)
    ns.UPGRADE_STEPS[6]({})
end)

-- Pop and sweep: a point gained flashes its pip, and the fifth sweeps a light across
-- the row, but only on a plain count that went up on the same target.
local function settle()
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
end

local function count(ns, n)
    stub.comboPoints = n
    ns.Combo.Update(ns.combo)
end

-- How much brighter than its painted color a pip's fill is now.
local function lit(pip)
    local c, p = pip.bar.__barColor, pip.color
    return (c[1] + c[2] + c[3]) - (p[1] + p[2] + p[3])
end

T.test("pop: a point gained flashes that pip only, then it settles back", function()
    local _, ns = login("ROGUE")
    local pips = ns.combo.pips
    count(ns, 2); settle()
    count(ns, 3)
    T.truthy(lit(pips[3]) > 0.1, "pip 3 flashes")
    T.truthy(pips[3].burst:IsShown(), "a glow bursts round it")
    T.falsy(pips[2].burst:IsShown(), "not round pip 2")
    T.near(lit(pips[2]), 0, 1e-6, "pip 2 doesn't")
    T.near(lit(pips[4]), 0, 1e-6, "pip 4 doesn't")
    T.falsy(ns.combo.sweep:IsShown(), "no sweep under five")
    settle()
    T.near(lit(pips[3]), 0, 1e-6, "back to its color")
    T.falsy(pips[3].burst:IsShown(), "the glow gone")
    count(ns, 2)
    T.near(lit(pips[2]), 0, 1e-6, "a point spent: nothing")
    stub.comboPoints = nil
end)

T.test("pop: reaching five sweeps a light across the row", function()
    local _, ns = login("ROGUE")
    local c = ns.combo
    count(ns, 4); settle()
    count(ns, 5)
    T.truthy(c.sweep:IsShown(), "the light runs")
    T.eq(c.sweep:GetBlendMode(), "ADD")
    T.truthy(lit(c.pips[5]) > 0.1, "and the fifth flashes")
    settle()
    T.falsy(c.sweep:IsShown(), "gone at the end")
    stub.comboPoints = nil
end)

T.test("pop: a new target, a secret count, test mode or motion off animate nothing", function()
    local DUI, ns = login("ROGUE")
    local c = ns.combo
    count(ns, 0); settle()
    stub.comboPoints = 5
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(c.sweep:IsShown(), "a swap to a target at five: no sweep")
    T.near(lit(c.pips[5]), 0, 1e-6, "nor a flash")
    count(ns, 2)
    T.near(lit(c.pips[2]), 0, 1e-6, "down: nothing")
    T.noerror(function() count(ns, stub.Secret(3)) end)
    T.near(lit(c.pips[3]), 0, 1e-6, "secret: nothing")
    count(ns, 4)
    T.near(lit(c.pips[4]), 0, 1e-6, "the first plain count after a secret one only seeds")
    ns.Combo.ShowSample(c, 2)
    count(ns, 3)
    ns.Combo.HideSample(c)
    T.near(lit(c.pips[3]), 0, 1e-6, "test mode ending only seeds")
    DUI.DB.General().motion = false
    count(ns, 2); count(ns, 5)
    T.near(lit(c.pips[5]), 0, 1e-6, "motion off: no flash")
    T.falsy(c.sweep:IsShown(), "motion off: no sweep")
    stub.comboPoints = nil
end)

T.test("pop: the flash returns to a gradient pip's pair", function()
    local DUI, ns = login("ROGUE")
    DUI:Set("UnitFrames", "combo.colorMode", "gradient")
    stub.RunTimers()
    local pip = ns.combo.pips[2]
    local before = pip.bar:GetStatusBarTexture().__gradient
    count(ns, 1); settle()
    count(ns, 2)
    local mid = pip.bar:GetStatusBarTexture().__gradient
    T.truthy(mid[2].b > before[2].b, "brighter while it flashes")
    settle()
    local after = pip.bar:GetStatusBarTexture().__gradient
    T.near(after[2].r, before[2].r, 1e-6); T.near(after[3].b, before[3].b, 1e-6)
    stub.comboPoints = nil
end)

T.test("one power event, and only a combo point change redraws the row", function()
    local _, ns = login("ROGUE")
    local c = ns.combo
    T.falsy(c:IsEventRegistered("UNIT_POWER_UPDATE"), "UNIT_POWER_FREQUENT only, like the game's own combo bar")
    T.truthy(c:IsEventRegistered("UNIT_POWER_FREQUENT"))
    local n, real = 0, ns.Combo.Update
    ns.Combo.Update = function(...) n = n + 1; return real(...) end
    for _ = 1, 10 do stub.FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY") end
    T.eq(n, 0, "energy ticks leave the pips alone")
    T.truthy(c:IsEventRegistered("COMBO_TARGET_CHANGED"), "points moved to a new target, like the game's bar")
    -- A finisher: the points go with the energy event (seen in game).
    stub.comboPoints = 5
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY")
    T.eq(n, 1, "the count changed on an energy event: redrawn")
    for _ = 1, 5 do stub.FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY") end
    T.eq(n, 1, "then the ticks leave it alone again")
    stub.comboPoints = 0
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY")
    T.eq(n, 2, "spent: redrawn")
    n = 0
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    T.eq(n, 1)
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", stub.Secret("COMBO_POINTS"))
    T.eq(n, 2, "a secret power type still updates")
    stub.FireEvent("UNIT_DISPLAYPOWER", "player")
    T.eq(n, 3, "a form change still updates")
    ns.Combo.Update = real
end)
