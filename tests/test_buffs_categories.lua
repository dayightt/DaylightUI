local stub = require("stub")

-- The buff categories' logic (ported with the buff bars): loaded with the
-- core and logged in, as the client does.
local function loadBL(opts)
    stub.Load({ buffs = true, before = opts and opts.before })
    return stub.buffs
end

local DEFAULT_ORDER = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid",
    "weapon", "consumable", "world", "other" }

T.test("Seed populates the 13 defaults in shipped order, once", function()
    local BL = loadBL()
    T.deq(BL.Categories.Order(), DEFAULT_ORDER)
    T.eq(T.count(BL.DB.categories), 13)
    local priest = BL.Categories.Get("priest")
    T.eq(priest.name, "Priest")
    T.eq(priest.builtin, true)
    T.eq(priest.deletable, true)
    T.eq(priest.hidden, false)
    T.eq(priest.consolidate, false)
    T.near(priest.color[1], 1, 0.001)
    T.eq(BL.Categories.Get("other").deletable, false)
    T.eq(BL.Categories.Get("warrior").icon, "Interface\\Icons\\Ability_Warrior_Rampage")

    BL.Categories.Delete("mage")
    BL.Categories.Seed()
    T.isnil(BL.Categories.Get("mage"), "second Seed is a no-op")
end)

T.test("class colors come from RAID_CLASS_COLORS at seed time", function()
    local BL = loadBL()
    local mage = BL.Categories.Get("mage")
    T.near(mage.color[1], 0.25, 0.001)
    T.near(mage.color[2], 0.78, 0.001)
end)

T.test("Create appends before Other and bumps nextCustomId", function()
    local BL = loadBL()
    local fired = 0
    BL.On("CATEGORIES_CHANGED", function() fired = fired + 1 end)
    local id = BL.Categories.Create("Trinkets", { 0.1, 0.2, 0.3 })
    T.eq(id, "custom-1")
    T.eq(BL.DB.nextCustomId, 2)
    local order = BL.Categories.Order()
    T.eq(order[#order], "other")
    T.eq(order[#order - 1], "custom-1")
    local rec = BL.Categories.Get(id)
    T.eq(rec.name, "Trinkets")
    T.eq(rec.builtin, false)
    T.eq(rec.deletable, true)
    T.deq(rec.color, { 0.1, 0.2, 0.3 })
    T.eq(fired, 1)
    T.eq(BL.Categories.Create("Second"), "custom-2")
end)

T.test("Rename/SetColor/SetHidden/SetConsolidate write the record and fire once each", function()
    local BL = loadBL()
    local fired = 0
    BL.On("CATEGORIES_CHANGED", function() fired = fired + 1 end)
    BL.Categories.Rename("priest", "Holy folks")
    BL.Categories.SetColor("priest", { 0.5, 0.5, 0.5 })
    BL.Categories.SetHidden("priest", true)
    BL.Categories.SetConsolidate("priest", true)
    local p = BL.Categories.Get("priest")
    T.eq(p.name, "Holy folks")
    T.deq(p.color, { 0.5, 0.5, 0.5 })
    T.eq(p.hidden, true)
    T.eq(p.consolidate, true)
    T.eq(fired, 4)
    T.falsy(BL.Categories.Rename("nope", "x"))
end)

T.test("Move shifts within the order, clamps, and never moves Other", function()
    local BL = loadBL()
    T.truthy(BL.Categories.Move("paladin", -1))
    T.eq(BL.Categories.Order()[1], "paladin")
    T.eq(BL.Categories.Order()[2], "warrior")
    T.falsy(BL.Categories.Move("paladin", -1), "already first")
    T.falsy(BL.Categories.Move("other", -1))
    T.falsy(BL.Categories.Move("other", 1))
    T.falsy(BL.Categories.Move("world", 1), "cannot move below Other")
    T.truthy(BL.Categories.Move("world", -1))
    local o = BL.Categories.Order()
    T.eq(o[#o], "other")
    T.eq(o[#o - 1], "consumable")
    T.eq(o[#o - 2], "world")
end)

T.test("Delete refuses Other and unknowns, removes the record, redirects overrides and learned", function()
    local BL = loadBL()
    BL.DB.overrides["Arcane Intellect"] = "mage"
    BL.DB.overrides["Food"] = "consumable"
    BL.DB.learned["Frost Armor"] = "mage"
    T.falsy(BL.Categories.Delete("other"))
    T.falsy(BL.Categories.Delete("nope"))
    T.truthy(BL.Categories.Delete("mage"))
    T.isnil(BL.Categories.Get("mage"))
    T.falsy(tContains(BL.Categories.Order(), "mage"))
    T.eq(BL.DB.overrides["Arcane Intellect"], "other")
    T.eq(BL.DB.overrides["Food"], "consumable")
    T.eq(BL.DB.learned["Frost Armor"], "other")
    T.eq(BL.Categories.Resolve("mage"), "other")
    T.eq(BL.Categories.Resolve("priest"), "priest")
    T.falsy(BL.Categories.Exists("mage"))
end)

T.test("ResetToDefault restores missing built-ins in shipped order and keeps customs after them", function()
    local BL = loadBL()
    BL.Categories.Delete("hunter")
    BL.Categories.Delete("rogue")
    BL.Categories.Rename("priest", "Renamed")
    local c1 = BL.Categories.Create("Custom A")
    local c2 = BL.Categories.Create("Custom B")
    BL.Categories.Move(c2, -1) -- B before A
    BL.Categories.Move("druid", -1)
    BL.DB.overrides["Aspect of the Hawk"] = "other"
    BL.DB.history[1] = { buffName = "x", from = "a", to = "b", time = 1 }

    BL.Categories.ResetToDefault()

    local expected = {}
    for _, id in ipairs(DEFAULT_ORDER) do expected[#expected + 1] = id end
    table.insert(expected, #expected, c2) -- customs sit before Other
    table.insert(expected, #expected, c1)
    T.deq(BL.Categories.Order(), expected)
    T.eq(BL.Categories.Get("hunter").name, "Hunter")
    T.eq(BL.Categories.Get("priest").name, "Renamed", "existing built-ins untouched")
    T.eq(BL.DB.overrides["Aspect of the Hawk"], "other", "overrides untouched")
    T.eq(#BL.DB.history, 1)
end)

T.test("FindByName is case-insensitive", function()
    local BL = loadBL()
    T.eq(BL.Categories.FindByName("PRIEST"), "priest")
    T.eq(BL.Categories.FindByName("consumable"), "consumable")
    T.isnil(BL.Categories.FindByName("nothing"))
    T.isnil(BL.Categories.FindByName(nil))
end)

T.test("SetConsolidateAll flips every category and AllConsolidated reports it", function()
    local BL = loadBL()
    local fired = 0
    BL.On("CATEGORIES_CHANGED", function() fired = fired + 1 end)
    T.falsy(BL.Categories.AllConsolidated())
    T.falsy(BL.Categories.AnyConsolidated(), "none combine by default: the group / raid switches dim")
    BL.Categories.SetConsolidateAll(true)
    T.truthy(BL.Categories.AllConsolidated())
    T.truthy(BL.Categories.AnyConsolidated())
    T.eq(BL.Categories.Get("other").consolidate, true)
    T.eq(fired, 1, "one event for the whole switch")
    BL.Categories.SetConsolidate("mage", false)
    T.falsy(BL.Categories.AllConsolidated())
    T.truthy(BL.Categories.AnyConsolidated(), "some still do")
    BL.Categories.SetConsolidateAll(false)
    T.eq(BL.Categories.Get("priest").consolidate, false)
end)

T.test("SetColor quiet fires only the color event; the plain call fires CATEGORIES_CHANGED", function()
    local BL = loadBL()
    local full, color = 0, 0
    BL.On("CATEGORIES_CHANGED", function() full = full + 1 end)
    BL.On("CATEGORY_COLOR_CHANGED", function(id) color = color + 1; T.eq(id, "mage") end)
    BL.Categories.SetColor("mage", { 0.1, 0.2, 0.3 }, true)
    T.eq(full, 0); T.eq(color, 1)
    BL.Categories.SetColor("mage", { 0.1, 0.2, 0.3 })
    T.eq(full, 1); T.eq(color, 1)
end)

local function nearRGB(a, b, msg)
    for i = 1, 3 do T.near(a[i], b[i], 1e-6, msg) end
end

T.test("categories start solid, with a pair in shades of their color", function()
    local BL = loadBL()
    local priest = BL.Categories.Get("priest")
    T.eq(priest.style, "solid")
    T.falsy(BL.Categories.IsGradient("priest"))
    nearRGB(priest.gradient.hi, priest.color, "priest hi is its color")
    nearRGB(priest.gradient.lo, { priest.color[1] * 0.55, priest.color[2] * 0.55, priest.color[3] * 0.55 })
    T.eq(BL.Categories.Get("other").style, "solid")
end)

T.test("a new category is solid, its pair made from its color", function()
    local BL = loadBL()
    local id = BL.Categories.Create("Trinkets", { 0.6, 0.4, 0.2 })
    local rec = BL.Categories.Get(id)
    T.eq(rec.style, "solid")
    nearRGB(rec.gradient.lo, { 0.6 * 0.55, 0.4 * 0.55, 0.2 * 0.55 })
    nearRGB(rec.gradient.hi, { 0.6, 0.4, 0.2 })
end)

T.test("Upgrade: records saved before borders could be gradients go solid once, pairs from their color", function()
    local BL = loadBL()
    local id = BL.Categories.Create("Old custom", { 0.2, 0.4, 0.8 })
    BL.Categories.SetColor("mage", { 0.1, 0.9, 0.1 })
    for _, k in ipairs({ "priest", "mage", id }) do
        local rec = BL.Categories.Get(k)
        rec.style, rec.gradient = nil, nil     -- as saved before this feature
    end
    BL.DB.solidBorders = nil                   -- and before the one-time pass
    BL.Categories.Upgrade()
    local priest = BL.Categories.Get("priest")
    T.eq(priest.style, "solid")
    nearRGB(priest.gradient.hi, priest.color, "unchanged built-in: shades of its color")
    nearRGB(BL.Categories.Get("mage").gradient.hi, { 0.1, 0.9, 0.1 }, "recolored built-in: from its color")
    nearRGB(BL.Categories.Get(id).gradient.lo, { 0.2 * 0.55, 0.4 * 0.55, 0.8 * 0.55 }, "custom: from its color")
    BL.Categories.SetStyle("warlock", "gradient")
    local before = BL.Categories.Get("priest").gradient
    BL.Categories.Upgrade()
    T.eq(BL.Categories.Get("priest").gradient, before, "once only")
    T.eq(BL.Categories.Get("warlock").style, "gradient", "a style chosen later is left alone")
end)

T.test("SetStyle and SetGradient validate, copy and fire", function()
    local BL = loadBL()
    local heard = {}
    BL.On("CATEGORY_COLOR_CHANGED", function(id) heard[#heard + 1] = "color:" .. tostring(id) end)
    BL.On("CATEGORIES_CHANGED", function() heard[#heard + 1] = "all" end)
    T.falsy(BL.Categories.SetStyle("priest", "sparkly"), "bad style refused")
    T.truthy(BL.Categories.SetStyle("priest", "solid"))
    T.falsy(BL.Categories.IsGradient("priest"))
    T.eq(heard[#heard], "color:priest")
    local lo, hi = { 0.1, 0.2, 0.3 }, { 0.4, 0.5, 0.6 }
    T.truthy(BL.Categories.SetGradient("priest", lo, hi, true))
    T.eq(heard[#heard], "color:priest", "quiet: a repaint")
    lo[1] = 9
    local plo, phi = BL.Categories.Pair("priest")
    T.near(plo[1], 0.1, 1e-9, "stored a copy"); T.near(phi[3], 0.6, 1e-9)
    BL.Categories.SetGradient("priest", lo, hi)
    T.eq(heard[#heard], "all", "not quiet: the full change")
    T.falsy(BL.Categories.SetGradient("nope", lo, hi))
    T.isnil(BL.Categories.Pair("nope"))
end)

T.test("a shipped category shows in the player's language; the saved name stays English", function()
    stub.Load({ buffs = true, locale = function(L)
        L["Warrior"] = "Krieger"
        L["Other"] = "Sonstiges"
    end })
    local BL = stub.buffs
    T.eq(BL.Categories.Get("warrior").name, "Warrior", "saved as shipped")
    T.eq(BL.Categories.Label("warrior"), "Krieger")
    T.eq(BL.Categories.Label("other"), "Sonstiges")
    T.eq(BL.Categories.FindByName("krieger"), "warrior", "/dui buffs toggle takes the shown name")
    T.eq(BL.Categories.FindByName("Warrior"), "warrior", "and the English one")
    BL.Categories.Rename("warrior", "Tanks")
    T.eq(BL.Categories.Label("warrior"), "Tanks", "a renamed one shows as the player wrote it")
    local id = BL.Categories.Create("Mine")
    T.eq(BL.Categories.Label(id), "Mine")
end)

T.test("text color: a gray category's name reads warm; the timer is a warm value", function()
    local BL = loadBL()
    local INK = DaylightUI.Style.INK
    T.deq({ BL.Categories.TextColor("other") }, INK.LABEL, "Other: warm label, not its gray edge")
    T.deq({ BL.Categories.TextColor("mage") }, { BL.Widgets.CategoryColor("mage") }, "a colored category keeps its color")
    T.deq(BL.Widgets.TIME_COLOR, INK.VALUE)
end)

T.test("a plugin's buff category is made once and holds its spells by id, a hand move still wins", function()
    local BL = loadBL()
    local me = DaylightUI.API.For("Watcher")
    T.eq(me.AddBuffCategory("food", { label = "Well Fed", spells = { 1001, 1002 }, color = { 0.9, 0.6, 0.2 } }), true)
    local id
    for k, rec in pairs(BL.DB.categories) do if rec.plugin == "Watcher:food" then id = k end end
    T.truthy(id, "made in the player's list")
    T.eq(BL.Categories.Get(id).name, "Well Fed")
    local order = BL.Categories.Order()
    T.eq(order[#order], "other", "before Other")
    local sets = BL.Spells.Sets()
    T.truthy(sets.byCategory[id][1001] and sets.byCategory[id][1002], "its spells by id")
    T.truthy(sets.categorised[1001], "out of Other")
    -- Again (another login, or new spells): the same category, the new list.
    me.AddBuffCategory("food", { label = "Well Fed", spells = { 1003 } })
    local n = 0
    for _, rec in pairs(BL.DB.categories) do if rec.plugin == "Watcher:food" then n = n + 1 end end
    T.eq(n, 1, "made once")
    sets = BL.Spells.Sets()
    T.truthy(sets.byCategory[id][1003]); T.isnil(sets.byCategory[id][1001])
    -- A buff the player moved by hand stays where they put it.
    BL.DB.spells[1003] = "Feast"
    BL.DB.overrides.Feast = "world"
    BL.Fire("OVERRIDES_CHANGED")
    sets = BL.Spells.Sets()
    T.isnil(sets.byCategory[id][1003], "the player's move wins")
    T.eq(me.AddBuffCategory("bad", { label = "x" }), false)
    local bar
    for f, scope in DaylightUI.API.Frames("buffbar") do if scope == "buff" then bar = f end end
    T.truthy(bar, "the buff bar's holder is a frame plugins can attach to")
end)
