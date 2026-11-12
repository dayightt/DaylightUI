local stub = require("stub")

-- Importing a layout from the game's own Cooldown Manager string (CdmImport). The
-- game's encoder is stubbed as in test_profiles, a store behind a token, so a
-- string here decodes to the table built here, laid out the way
-- Blizzard_CooldownViewer's serializer writes it.

local function fakeEncoding()
    local store, n = {}, 0
    _G.C_EncodingUtil = {
        DeserializeCBOR = function(s)
            local i = tonumber(string.match(s, "^cbor(%d+)$"))
            if not i or not store[i] then error("bad cbor") end
            return store[i]
        end,
        DecompressString = function(s, method)
            if string.sub(s, 1, 1) ~= "z" then error("bad deflate") end
            return string.sub(s, 2)
        end,
        DecodeBase64 = function(s) return string.sub(s, 2) end,
    }
    -- A table as the game would export it.
    return function(t) n = n + 1; store[n] = t; return "1|bzcbor" .. n end
end

-- The game's cooldowns: id -> default category (10-19 Essential, 20s Utility, 30s
-- buffs, 40s bars). 50 is hidden by default, 51 not known.
local function fakeViewer()
    local cats = { [0] = { 11, 12, 13 }, [1] = { 21, 22 }, [2] = { 31 }, [3] = { 41, 42 } }
    local byId = {}
    for cat, ids in pairs(cats) do for _, id in ipairs(ids) do byId[id] = { category = cat, flags = 0 } end end
    byId[50] = { category = 0, flags = 2 }   -- HideByDefault
    byId[51] = { category = 0, flags = 1, unknown = true }   -- HideAura, not learned
    table.insert(cats[0], 51)
    table.insert(cats[0], 50)
    _G.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function(cat) return cats[cat] or {} end,
        GetCooldownViewerCooldownInfo = function(id)
            local i = byId[id]
            return i and { cooldownID = id, category = i.category, flags = i.flags, isKnown = not i.unknown } or nil
        end,
    }
end

local function world()
    _G.DaylightUITestDUI = stub.Load({ actionbars = true })
    local encode = fakeEncoding()
    fakeViewer()
    stub.units.player = stub.units.player or { isPlayer = true, name = "Tester" }
    stub.units.player.class = "MAGE"
    local _, _, class = UnitClass("player")
    return stub.actionbars.CdmImport, stub.actionbars.CdmData, encode, class
end

local function ids(set, root)
    local out, id = {}, root
    while id do
        out[#out + 1] = id
        local D = stub.actionbars.CdmData
        id = D.Child(set, id, set.pieces[root].shape == "bar" and "down" or "right")
    end
    return out
end

local function rootOf(set, member)
    return stub.actionbars.CdmData.Root(set, member)
end

T.test("cdm import: a game string's four rows become chains in its order, moves and hidden ones kept", function()
    local I, D, encode, class = world()
    local tag = class * 10 + 1
    local text = encode({ 5, { [tag] = 7 }, { [tag] = { [7] = {
        { 13, 11, 12, 22, 21, 31, 42, 41, 50, 51 },
        { [1] = { 12 }, [3] = { 31 }, [-1] = { 13 } },   -- 12 to Utility, buff 31 to bars, 13 hidden
    } } }, { [7] = "Raid" } })
    local t = assert(I.Read(text))
    local pick = assert(I.Pick(t))
    T.eq(pick.name, "Raid")
    local rows = I.Rows(pick.layout)
    T.deq(rows[0], { 11 })                -- 13 hidden, 12 moved, 50 hidden by default, 51 not known
    T.deq(rows[1], { 12, 22, 21 })
    T.deq(rows[2], {})
    T.deq(rows[3], { 31, 42, 41 })
    local set = { v = 2, pieces = {}, chains = {} }
    I.Build(set, rows)
    T.deq(ids(set, rootOf(set, 11)), { 11 })
    T.deq(ids(set, rootOf(set, 12)), { 12, 22, 21 })
    T.deq(ids(set, rootOf(set, 31)), { 31, 42, 41 })
    T.eq(set.pieces[31].shape, "bar")
    T.eq(set.pieces[12].shape, "icon")
    T.eq(D.Chain(set, 12).grow, "center")
    T.eq(D.Chain(set, 12).look.size, 30, "no game viewer: Utility at 30")
    -- Utility under Essential, both centered on the screen
    local boxes = D.Layout(set)
    T.truthy(boxes[12].y < boxes[11].y)
    T.eq(boxes[11].x + boxes[11].w / 2, D.ORIGIN[1])
    T.truthy(boxes[31].x + boxes[31].w < boxes[11].x)   -- the bars to the left
end)

T.test("cdm import: spells the string didn't list go in their default row; unknown ids are left out", function()
    local I, D, encode, class = world()
    local tag = class * 10 + 1
    local t = assert(I.Read(encode({ 5, {}, { [tag] = { [3] = { { 12, 999, 11 } } } }, { [3] = "Mine" } })))
    local rows = I.Rows(assert(I.Pick(t)).layout)
    T.deq(rows[0], { 12, 11, 13 })
    T.deq(rows[1], { 21, 22 })
end)

-- The game's own rebuild (CheckBuildDisplayData in CooldownViewerSettingsDataProvider):
-- the string's order keeps only ids in this game's category sets, then every other
-- id of the sets is added in the sets' order. A move only changes the row, never
-- the place in line.
T.test("cdm import: the order is rebuilt like the game's: ids it doesn't list dropped, unlisted moves in default order", function()
    local I, D, encode, class = world()
    local CV = _G.C_CooldownViewer
    local get = CV.GetCooldownViewerCooldownInfo
    CV.GetCooldownViewerCooldownInfo = function(id)
        if id == 60 then return { cooldownID = 60, category = 0, flags = 0, isKnown = true } end
        return get(id)
    end
    local tag = class * 10 + 1
    local t = assert(I.Read(encode({ 5, {}, { [tag] = { [2] = {
        { 11, 60 },
        { [0] = { 22 } },   -- 22 moved to Essential, not in the order list
    } } }, { [2] = "Mine" } })))
    local rows = I.Rows(assert(I.Pick(t)).layout)
    T.deq(rows[0], { 11, 12, 13, 22 })
    T.deq(rows[1], { 21 })
end)

T.test("cdm import: this spec's active layout is picked over another of the class; another class is refused", function()
    local I, D, encode, class = world()
    _G.C_SpecializationInfo = { GetSpecialization = function() return 2 end }
    local mine1, mine2 = class * 10 + 1, class * 10 + 2
    local t = assert(I.Read(encode({ 5, { [mine2] = 9 }, {
        [mine1] = { [4] = { { 11 } } },
        [mine2] = { [8] = { { 12 } }, [9] = { { 13 } } },
    }, { [4] = "One", [8] = "Two", [9] = "Active" } })))
    T.eq(I.Pick(t).name, "Active")
    _G.GetClassInfo = function(id) return "Classname" .. id end
    local other = (class == 1 and 2 or 1)
    local t2 = assert(I.Read(encode({ 5, {}, { [other * 10 + 1] = { [1] = { { 11 } } } }, { [1] = "x" } })))
    local pick, why = I.Pick(t2)
    T.eq(pick, nil)
    T.truthy(string.find(why, "Classname" .. other, 1, true))
    _G.C_SpecializationInfo, _G.GetClassInfo = nil, nil
end)

T.test("cdm import: bad text says why, never errors", function()
    local I = world()
    for _, s in ipairs({ "", "hello", "2|abc", "1|bzcbor999", "1|xx" }) do
        local t, why = I.Read(s)
        T.eq(t, nil)
        T.eq(type(why), "string")
    end
end)

T.test("cdm import: the paste box makes a new profile named after the layout, picked for the talent set", function()
    local I, D, encode, class = world()
    local tag = class * 10 + 1
    local old = D.NewProfile("Mine")
    D.Assign(1, old)
    D.AddChain(D.Get(1), { 41 }, "icon", 0, 0)
    local spec
    _G.DaylightUITestDUI.Profiles.ShowPaste = function(s) spec = s end
    local refreshed = 0
    I.Open(1, function() refreshed = refreshed + 1 end)
    T.truthy(spec)
    local what, said = spec.read(encode({ 5, {}, { [tag] = { [1] = { { 11, 12 } } } }, { [1] = "Luxthos Prot" } }))
    T.truthy(what)
    T.truthy(string.find(said, "Luxthos Prot", 1, true))
    T.eq(spec.go(what), nil)
    T.eq(refreshed, 1)
    local id = D.Use(1)
    T.truthy(id ~= old, "a new profile")
    T.eq(D.Profile(id).name, "Luxthos Prot")
    T.eq(D.Get(1).pieces[41].shape, "bar")   -- 41 is a bar by default, so it goes in the bar column
    T.eq(D.Get(1).pieces[11].shape, "icon")
    T.truthy(D.Profile(old).set.pieces[41], "the old profile is kept as it was")
    T.eq(D.Profile(old).set.pieces[41].shape, "icon")
end)

T.test("cdm import: each row is drawn as the game draws it: spot, size, padding, per line, direction", function()
    local I, D = world()
    -- The fake game doesn't lay frames out, so viewers say where they are and carry
    -- the game's Edit Mode fields (UIParent's scale is 1).
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local function viewer(cx, cy, w, h, point, scale, fields)
        local v = { GetCenter = function() return (cx + W / 2) / scale, (cy + H / 2) / scale end,
                    GetWidth = function() return w / scale end, GetHeight = function() return h / scale end,
                    GetEffectiveScale = function() return scale end,
                    GetPoint = function() return point end }
        for k, x in pairs(fields) do v[k] = x end
        return v
    end
    -- Essential: 3 a line, icons at 80% (40 px), padding 6 (2 px apart), centered.
    _G.EssentialCooldownViewer = viewer(30, -200, 300, 100, "CENTER", 1,
        { iconLimit = 3, iconPadding = 6, iconScale = 0.8, isHorizontal = true, iconDirection = 1 })
    -- Utility: anchored by its left edge, growing left, viewer at 0.5 scale.
    _G.UtilityCooldownViewer = viewer(-300, 100, 60, 30, "LEFT", 0.5,
        { iconLimit = 8, iconPadding = 8, iconScale = 1, isHorizontal = true, iconDirection = 0 })
    -- Bars: a column down from its top (a column runs up when the direction is
    -- Right, CooldownViewerMixin:RefreshLayout).
    _G.BuffBarCooldownViewer = viewer(400, 0, 220, 100, "TOP", 1,
        { iconLimit = 10, iconPadding = 5, iconScale = 1, isHorizontal = false, iconDirection = 0 })
    local looks = I.ViewerLooks()
    T.near(looks[0].w, 40, 0.01); T.near(looks[0].gap, 2, 0.01); T.eq(looks[0].per, 3)
    T.near(looks[1].w, 15, 0.01, "the viewer's scale counts")
    T.truthy(looks[1].reverse)
    local set = I.Build({ v = 2, pieces = {}, chains = {} },
        { [0] = { 11, 12, 13, 14 }, [1] = { 21, 22 }, [2] = {}, [3] = { 41, 42 } }, looks)
    local b = D.Layout(set)
    -- Essential: 3, then a second line under the first, the grid centered on the
    -- game's middle (30, -200): 3*40+2*2 = 124 wide, 82 tall.
    T.near(b[11].x, 30 - 62, 0.6); T.near(b[11].y, -200 + 41, 0.6)
    T.near(b[12].x, b[11].x + 42, 0.6, "2 px apart")
    T.near(b[14].x, b[11].x, 0.6, "the 4th wraps under the 1st")
    T.near(b[14].y, b[11].y - 42, 0.6)
    T.eq(D.Chain(set, 11).look.size, 40)
    T.eq(D.Chain(set, 11).spacing, 2)
    T.eq(D.Chain(set, 11).grow, "center")
    -- Utility: its left edge stays where the game's is (-300 - 60 / 2), with the
    -- first icon at the right end and the next to its left.
    local uLeft = -300 - 30
    T.near(math.min(b[21].x, b[22].x), uLeft, 0.6)
    T.truthy(b[22].x < b[21].x, "grows left")
    T.eq(D.Chain(set, 21).look.size, 15)
    -- Bars: down from the game's top, at its middle.
    T.near(b[41].y, 50, 0.6); T.near(b[41].x + b[41].w / 2, 400, 0.6)
    T.truthy(b[42].y < b[41].y)
    T.eq(D.Chain(set, 41).look.width, 220)
    _G.EssentialCooldownViewer, _G.UtilityCooldownViewer, _G.BuffBarCooldownViewer = nil, nil, nil
end)
