local stub = require("stub")

-- The buff categories' logic (ported with the buff bars): loaded with the
-- core and logged in, as the client does.
local function loadBL(opts)
    stub.Load({ buffs = true, before = opts and opts.before })
    return stub.buffs
end

local function group(key, count, extra)
    local g = { key = key, count = count, elementWidth = 30, elementHeight = 30, elementSpacing = 4, lineSpacing = 16, groupSpacing = 12 }
    for k, v in pairs(extra or {}) do g[k] = v end
    return g
end

local RIGHTWARD = { anchorPoint = "TOPLEFT", horizontal = 1, vertical = -1, maximumLineSize = 4 * 34 }
local LEFTWARD = { anchorPoint = "TOPRIGHT", horizontal = -1, vertical = -1, maximumLineSize = 4 * 34 }

T.test("Flow places elements along the line with element spacing", function()
    local BL = loadBL()
    local f = BL.Layout.Flow({ group("a", 3) }, RIGHTWARD)
    T.eq(#f.elements, 3)
    T.eq(f.elements[1].x, 0)
    T.eq(f.elements[2].x, 34)
    T.eq(f.elements[3].x, 68)
    T.eq(f.elements[1].y, 0)
    T.eq(f.width, 30 * 3 + 4 * 2)
    T.eq(f.height, 30)
    T.eq(f.lines, 1)
end)

T.test("groupSpacing separates groups on the same line and can itself wrap", function()
    local BL = loadBL()
    local f = BL.Layout.Flow({ group("a", 1), group("b", 1) }, RIGHTWARD)
    T.eq(f.elements[2].x, 34 + 12)
    T.eq(f.elements[2].key, "b")
    -- four icons fill the line exactly; the next group's spacing pushes it to line 2
    f = BL.Layout.Flow({ group("a", 4), group("b", 1) }, RIGHTWARD)
    T.eq(f.elements[5].x, 0)
    T.eq(f.elements[5].y, -(30 + 16))
    T.eq(f.lines, 2)
end)

T.test("a group longer than the line wraps element by element, like the client", function()
    local BL = loadBL()
    local f = BL.Layout.Flow({ group("a", 6) }, RIGHTWARD)
    T.eq(f.elements[4].x, 102)
    T.eq(f.elements[5].x, 0)
    T.eq(f.elements[5].y, -46)
    T.eq(f.elements[6].x, 34)
    T.eq(f.height, 46 + 30)
end)

T.test("a group that fits partly continues on the current line (no whole-group move)", function()
    local BL = loadBL()
    local f = BL.Layout.Flow({ group("a", 2), group("b", 3) }, RIGHTWARD)
    -- a1 a2 [gap] b1 fits (34+34+12+30 = 110 <= 136); b2 wraps
    T.eq(f.elements[3].x, 68 + 12)
    T.eq(f.elements[3].y, 0)
    T.eq(f.elements[4].x, 0)
    T.eq(f.elements[4].y, -46)
end)

T.test("forceNewLine starts a group on its own line", function()
    local BL = loadBL()
    local f = BL.Layout.Flow({ group("a", 1), group("b", 1, { forceNewLine = true }) }, RIGHTWARD)
    T.eq(f.elements[2].x, 0)
    T.eq(f.elements[2].y, -46)
end)

T.test("empty groups add nothing, not even spacing", function()
    local BL = loadBL()
    local f = BL.Layout.Flow({ group("a", 1), group("b", 0), group("c", 1) }, RIGHTWARD)
    T.eq(#f.elements, 2)
    T.eq(f.elements[2].x, 34 + 12)
    f = BL.Layout.Flow({}, RIGHTWARD)
    T.eq(#f.elements, 0)
    T.eq(f.width, 0)
    T.eq(f.lines, 0)
end)

T.test("leftward growth mirrors x; ElementRect and HitTest agree with it", function()
    local BL = loadBL()
    local f = BL.Layout.Flow({ group("a", 2) }, LEFTWARD)
    T.eq(f.elements[1].x, 0)
    T.eq(f.elements[2].x, -34)
    local l, b, r, t = BL.Layout.ElementRect(f.elements[2], "TOPRIGHT")
    T.eq(l, -64); T.eq(r, -34); T.eq(t, 0); T.eq(b, -30)
    T.eq(BL.Layout.HitTest(f, "TOPRIGHT", -40, -10).index, 2)
    T.eq(BL.Layout.HitTest(f, "TOPRIGHT", -10, -10).index, 1)
    T.isnil(BL.Layout.HitTest(f, "TOPRIGHT", -32, -10), "the gap between icons hits nothing")
    T.isnil(BL.Layout.HitTest(f, "TOPRIGHT", 5, -10))
    local g = BL.Layout.Flow({ group("a", 2) }, RIGHTWARD)
    T.eq(BL.Layout.HitTest(g, "TOPLEFT", 40, -10).index, 2)
    T.eq(BL.Layout.HitTest(g, "TOPLEFT", 40, -31), nil, "below the icon")
end)

T.test("ClusterEntries follows categoryOrder, skips hidden, sorts soonest first with permanents last", function()
    local BL = loadBL()
    local function e(name, exp, i) return { kind = "aura", name = name, expirationTime = exp, timed = exp ~= nil and exp > 0, index = i, auraInstanceID = i, sourceUnit = "player" } end
    local entries = { e("Well Fed", 500, 1), e("Arcane Intellect", 0, 2), e("Frost Armor", 900, 3), e("Mage Armor", 300, 4), e("Power Word: Fortitude", 800, 5) }
    local clusters = BL.Layout.ClusterEntries(entries, BL.DB.categories, BL.Categories.Order())
    T.eq(clusters[1].categoryId, "priest")
    T.eq(clusters[2].categoryId, "mage")
    T.eq(clusters[3].categoryId, "consumable")
    local names = {}
    for i, x in ipairs(clusters[2].entries) do names[i] = x.name end
    T.deq(names, { "Mage Armor", "Frost Armor", "Arcane Intellect" })
    BL.Categories.SetHidden("mage", true)
    T.eq(#BL.Layout.ClusterEntries(entries, BL.DB.categories, BL.Categories.Order()), 2)
end)

T.test("consolidation gate matrix", function()
    local BL = loadBL()
    local cat, off = { consolidate = true }, { consolidate = false }
    local none = { consolidateOnlyGroup = false, consolidateOnlyRaid = false }
    local grp = { consolidateOnlyGroup = true, consolidateOnlyRaid = false }
    local raid = { consolidateOnlyGroup = false, consolidateOnlyRaid = true }
    local solo, party, inRaid = { inGroup = false, inRaid = false }, { inGroup = true, inRaid = false }, { inGroup = true, inRaid = true }
    local allowed = BL.Layout.ConsolidateAllowed
    T.falsy(allowed(off, none, inRaid))
    T.truthy(allowed(cat, none, solo))
    T.falsy(allowed(cat, grp, solo))
    T.truthy(allowed(cat, grp, party))
    T.falsy(allowed(cat, raid, party))
    T.truthy(allowed(cat, raid, inRaid))
end)
