local stub = require("stub")
local LW = require("cdmlayoutworld")
local H = require("helpers")
local loadWorld, realFacts, plainAuras = LW.loadWorld, LW.realFacts, LW.plainAuras
local data, empty, filled, box = LW.data, LW.empty, LW.filled, LW.box
local profileWorld, oldLayout, oldSet, oldBlock = LW.profileWorld, LW.oldLayout, LW.oldSet, LW.oldBlock
local inBlock, parked, boopy, nightzFile = LW.inBlock, LW.parked, LW.boopy, LW.nightzFile
local nightz, fakeViewer, fakeRegistry, rowsWorld = LW.nightz, LW.fakeViewer, LW.fakeRegistry, LW.rowsWorld
local layoutFrame, pieceFrame, changeSpecTo, eased = LW.layoutFrame, LW.pieceFrame, LW.changeSpecTo, LW.eased
local garbageMadeBy, visibleMenuRowOf = H.garbageMadeBy, H.visibleMenuRowOf

T.test("cdm data: a row of icons lays out left to right from its top-left", function()
    local D = data()
    local set = filled(D)
    local L = D.Layout(set)
    T.deq(box(L[11]), { 0, 0, 36, 36 })
    T.deq(box(L[12]), { 40, 0, 36, 36 })
    T.deq(box(L[13]), { 80, 0, 36, 36 })
    T.eq(set.pieces[12].parent, 11); T.eq(set.pieces[12].side, "right")
    T.eq(D.Root(set, 13), 11)
    T.deq(D.Subtree(set, 12), { 12, 13 })
end)

-- A pass asks every piece's root about 25 times, on every aura shown or hidden.
T.test("cdm data: finding a chain's first piece makes no garbage", function()
    local D = data()
    local set = empty()
    D.AddChain(set, { 11, 12, 13, 14, 15, 16 }, "icon", 0, 0)
    T.eq(D.Root(set, 16), 11)
    local grown = garbageMadeBy(function() D.Root(set, 16) end, 1000)
    T.truthy(grown < 1, "grew " .. grown .. " KB")
end)

T.test("cdm data: two spells in a group trade places, each keeping its own options", function()
    local D = data()
    local set = filled(D)                  -- 11 > 12 > 13, left to right
    set.chains[11] = { grow = "center" }
    set.pieces[12].look = { size = 40 }
    set.pieces[13].spell = { glow = true }
    T.eq(select(1, D.Neighbors(set, 12)), 11); T.eq(select(2, D.Neighbors(set, 12)), 13)
    T.isnil((D.Neighbors(set, 11)), "the first has none before it")
    T.eq(select(2, D.Neighbors(set, 11)), 12)
    T.isnil(select(2, D.Neighbors(set, 13)), "the last none after")
    -- 12 and 13 (parent and child) trade places.
    T.truthy(D.Swap(set, 12, 13))
    local L = D.Layout(set)
    T.eq(L[13].x, 40, "13 is second now"); T.eq(L[12].x, 80, "12 last")
    T.eq(set.pieces[13].parent, 11); T.eq(set.pieces[12].parent, 13)
    T.deq(set.pieces[12].look, { size = 40 }, "its own look went with it")
    T.deq(set.pieces[13].spell, { glow = true })
    -- The first spot trades too, and the group's settings stay at the front.
    T.truthy(D.Swap(set, 11, 13))
    L = D.Layout(set)
    T.deq({ L[13].x, L[13].y }, { 0, 0 }, "13 leads where the group was")
    T.eq(L[11].x, 40)
    T.eq(D.Root(set, 12), 13)
    T.deq(set.chains[13], { grow = "center" }, "the group's settings at the front")
    T.isnil(set.chains[11])
    T.falsy(D.Swap(set, 13, 99), "a missing one: nothing")
    T.falsy(D.Swap(set, 13, 13))
end)

T.test("cdm data: a loop in a bad save still answers", function()
    local D = data()
    local set = empty()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    set.pieces[11].parent, set.pieces[11].side = 13, "right"
    T.eq(D.Root(set, 12), 12, "a full circle stops where it started")
    D.AddPiece(set, 14, "icon", 0, 0)
    set.pieces[14].parent, set.pieces[14].side = 13, "down"
    T.eq(D.Root(set, 14), 13, "a tail stops where it meets the circle")
end)

T.test("cdm data: pieces hang off any side, lined up start, middle or end", function()
    local D = data()
    local set = empty()
    D.AddPiece(set, 1, "icon", 100, 50)
    D.AddPiece(set, 2, "bar", 0, 0)
    T.truthy(D.Hook(set, 2, 1, "right", "center"))
    D.AddPiece(set, 3, "bar", 0, 0)
    T.truthy(D.Hook(set, 3, 1, "down", "start"))
    D.AddPiece(set, 4, "icon", 0, 0)
    T.truthy(D.Hook(set, 4, 1, "up", "end"))
    D.AddPiece(set, 5, "icon", 0, 0)
    T.truthy(D.Hook(set, 5, 1, "left"))
    local L = D.Layout(set)
    T.deq(box(L[2]), { 140, 41, 220, 18 }, "a bar beside the icon, centered on it")
    T.deq(box(L[3]), { 100, 10, 220, 18 }, "below, left edges lined up")
    T.deq(box(L[4]), { 100, 90, 36, 36 }, "above")
    T.deq(box(L[5]), { 60, 50, 36, 36 }, "to the left")
end)

T.test("cdm data: hooking onto a taken side goes to the end of that run; never onto itself", function()
    local D = data()
    local set = filled(D)
    D.AddPiece(set, 14, "icon", 0, 0)
    T.truthy(D.Hook(set, 14, 11, "right"))
    T.eq(set.pieces[14].parent, 13, "after the last one")
    T.falsy(D.Hook(set, 11, 13, "down"), "11 can't hang off its own chain")
    T.falsy(D.Hook(set, 12, 99, "down"), "no such piece")
end)

T.test("cdm data: a hidden piece closes up, with one gap left", function()
    local D = data()
    local set = filled(D)
    local L = D.Layout(set, { [11] = true, [13] = true })
    T.eq(L[13].x, 40, "13 moved into 12's place")
    T.truthy(L[12].hidden)
    L = D.Layout(set, { [12] = true, [13] = true })
    T.eq(L[12].x, 0, "the first one hidden: the next starts at the chain's spot")
    T.eq(L[13].x, 40)
    L = D.Layout(set, { [13] = true })
    T.eq(L[13].x, 0)
end)

-- A druid's stack of bars growing up from above the target frame: with the bottom
-- bar down, the rest stayed where they were and left its room empty under them.
T.test("cdm data: a chain growing up or left closes up onto its first piece's far edge, bars and icons", function()
    local D = data()
    for _, shape in ipairs({ "bar", "icon" }) do
        local set = empty()
        D.AddPiece(set, 1, shape, 0, 0)
        D.AddPiece(set, 2, shape, 0, 0); D.Hook(set, 2, 1, "up", "start")
        D.AddPiece(set, 3, shape, 0, 0); D.Hook(set, 3, 2, "up", "start")
        local F = D.Layout(set)
        local L = D.Layout(set, { [2] = true, [3] = true })
        T.eq(L[2].y, F[1].y, shape .. ": the second piece drops into the first one's spot")
        T.eq(L[3].y, F[2].y, shape .. ": and the third into the second's")
        L = D.Layout(set, { [3] = true })
        T.eq(L[3].y, F[1].y, shape .. ": two down, the last one sits at the bottom")
        -- The same growing left.
        set = empty()
        D.AddPiece(set, 1, shape, 0, 0)
        D.AddPiece(set, 2, shape, 0, 0); D.Hook(set, 2, 1, "left", "start")
        F = D.Layout(set)
        L = D.Layout(set, { [2] = true })
        T.eq(L[2].x + L[2].w, F[1].x + F[1].w, shape .. ": growing left, it moves into the first one's spot")
    end
end)

-- Shield Block first in the group, one spell hooked on its left, three on its
-- right, Grow from Middle. With Shield Block down, its two neighbors touch with
-- no gap between them.
T.test("cdm data: a hidden first spell's two neighbors keep one gap between them, round the same middle", function()
    local D = data()
    local set = empty()
    D.AddPiece(set, 1, "icon", 0, 0)
    D.AddPiece(set, 2, "icon", 0, 0); D.Hook(set, 2, 1, "left")
    D.AddPiece(set, 3, "icon", 0, 0); D.Hook(set, 3, 1, "right")
    D.AddPiece(set, 4, "icon", 0, 0); D.Hook(set, 4, 3, "right")
    D.SetChainValue(set, 1, "grow", "center")
    local F = D.Layout(set)
    local w, gap = F[1].w, F[3].x - F[1].w
    local L = D.Layout(set, { [2] = true, [3] = true, [4] = true })
    T.eq(L[3].x - (L[2].x + L[2].w), gap, "one gap between the two neighbors")
    T.eq(L[4].x - (L[3].x + L[3].w), gap)
    T.eq((L[2].x + L[4].x + L[4].w) / 2, (F[2].x + F[4].x + F[4].w) / 2, "the group's middle stays put")
end)

-- A player's warrior: Rend bar, Battle Shout bar on it, Charge on that, Thunder
-- Clap beside Charge. With Charge and Battle Shout hidden, Thunder Clap sat
-- centered on a flat line, on top of the bars.
T.test("cdm data: a piece beside a hidden one takes its place, never over the chain", function()
    local D = data()
    local set = empty()
    D.AddPiece(set, 1, "bar", 0, 0)                 -- Rend bar: 0..-18
    D.AddPiece(set, 2, "bar", 0, 0); D.Hook(set, 2, 1, "up", "start")
    D.AddPiece(set, 3, "icon", 0, 0); D.Hook(set, 3, 2, "up", "start")
    D.AddPiece(set, 4, "icon", 0, 0); D.Hook(set, 4, 3, "right", "center")
    local L = D.Layout(set)
    T.deq(box(L[3]), { 0, 62, 36, 36 }, "all up: Charge above Battle Shout")
    T.deq(box(L[4]), { 40, 62, 36, 36 })
    L = D.Layout(set, { [1] = true, [2] = true, [4] = true })
    T.deq(box(L[4]), { 0, 62, 36, 36 }, "Charge hidden: Thunder Clap in its place")
    L = D.Layout(set, { [1] = true, [4] = true })
    T.deq(box(L[4]), { 0, 40, 36, 36 }, "Battle Shout hidden too: just above the Rend bar")
    -- Both sides of a hidden piece: the second hangs off the first, with no overlap.
    D.AddPiece(set, 5, "icon", 0, 0); D.Hook(set, 5, 3, "left", "center")
    L = D.Layout(set, { [1] = true, [2] = true, [4] = true, [5] = true })
    T.deq(box(L[4]), { 0, 62, 36, 36 })
    T.deq(box(L[5]), { -40, 62, 36, 36 })
    -- Thunder Clap hidden as well: what hangs off it takes Charge's place.
    D.AddPiece(set, 6, "icon", 0, 0); D.Hook(set, 6, 4, "right", "center")
    L = D.Layout(set, { [1] = true, [2] = true, [6] = true })
    T.deq(box(L[6]), { 0, 62, 36, 36 })
end)

T.test("cdm data: a chain growing from its middle or end stays centered or end-fixed", function()
    local D = data()
    local set = filled(D)
    D.Chain(set, 11).grow = "center"
    local L = D.Layout(set, { [11] = true, [12] = true })
    T.eq(L[11].x, 20, "two of three: shifted half a slot")
    T.eq(L[12].x, 60)
    D.Chain(set, 11).grow = "end"
    L = D.Layout(set, { [11] = true, [12] = true })
    T.eq(L[11].x, 40, "the far end stays")
    set.chains[11].grow = nil
    T.eq(D.Layout(set, { [11] = true, [12] = true })[11].x, 0, "start: the first piece stays")
end)

-- A group hung out both sides of its first piece slid right when only the left
-- side's spells were up: only the right-hand run was measured.
T.test("cdm data: a chain out both sides of its first piece stays centered", function()
    local D = data()
    local set = filled(D)
    D.AddPiece(set, 14, "icon", 0, 0)
    T.truthy(D.Hook(set, 14, 11, "left", "center"))
    D.Chain(set, 11).grow = "center"
    local full = D.Layout(set)
    T.eq(full[14].x, -40)
    local middle = (-40 + 116) / 2
    T.eq(D.Layout(set, { [14] = true })[14].x, middle - 18, "the left one alone sits in the middle")
    T.eq(D.Layout(set, { [13] = true })[13].x, middle - 18, "the right one alone too")
    local L = D.Layout(set, { [14] = true, [13] = true })
    T.eq((L[14].x + L[13].x + 36) / 2, middle, "both ends up: the pair's middle stays")
    D.Chain(set, 11).grow = "end"
    T.eq(D.Layout(set, { [14] = true })[14].x, 80, "end: the far end stays")
end)

-- A player's druid: two rows started from the right end (the first spell has the
-- second row under it and the first row on its left). With Grow from Middle only
-- the column through the first spell was centered, so changing form added and
-- dropped icons at one end and left the rows off the middle.
T.test("cdm data: every row of a group growing from its middle stays centered", function()
    local D = data()
    local set = empty()
    D.AddPiece(set, 1, "icon", 0, 0)
    D.AddPiece(set, 2, "icon", 0, 0); D.Hook(set, 2, 1, "left")
    D.AddPiece(set, 3, "icon", 0, 0); D.Hook(set, 3, 2, "left")
    D.AddPiece(set, 4, "icon", 0, 0); D.Hook(set, 4, 1, "down")
    D.AddPiece(set, 5, "icon", 0, 0); D.Hook(set, 5, 4, "left")
    D.AddPiece(set, 6, "icon", 0, 0); D.Hook(set, 6, 5, "left")
    D.SetChainValue(set, 1, "grow", "center")
    local F = D.Layout(set)
    local mid1 = (F[3].x + F[1].x + F[1].w) / 2
    local mid2 = (F[6].x + F[4].x + F[4].w) / 2
    local L = D.Layout(set, { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true })
    T.eq((L[3].x + L[1].x + L[1].w) / 2, mid1, "the top row keeps its middle")
    T.eq((L[6].x + L[4].x + L[4].w) / 2, mid2, "the full row under it stays where it was")
    T.eq(L[4].x, F[4].x)
    L = D.Layout(set, { [1] = true, [2] = true, [3] = true, [4] = true, [6] = true })
    T.eq((L[3].x + L[1].x + L[1].w) / 2, mid1, "the full top row stays")
    T.eq(L[1].x, F[1].x)
    T.eq((L[6].x + L[4].x + L[4].w) / 2, mid2, "the bottom row keeps its middle")
    -- end: each row keeps its far end
    D.SetChainValue(set, 1, "grow", "end")
    L = D.Layout(set, { [1] = true, [3] = true, [4] = true, [6] = true })
    T.eq(L[3].x, F[3].x, "the top row's far end stays")
    T.eq(L[6].x, F[6].x, "the bottom row's too")
end)

-- Two shown boxes that cover each other. Boxes that only touch don't.
local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y - a.h < b.y and b.y - b.h < a.y
end

local function noOverlap(L, shown, why)
    local ids = {}
    for id in pairs(shown) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids do
        for j = i + 1, #ids do
            T.falsy(overlaps(L[ids[i]], L[ids[j]]),
                why .. ": " .. ids[i] .. " and " .. ids[j] .. " on top of each other")
        end
    end
end

-- Four icons snapped into a 2x2: 1 top-left (first), 2 top-right, 3 bottom-left,
-- 4 bottom-right. hooks = { { id, parent, side } }.
local function grid(D, hooks, grow)
    local set = empty()
    D.AddPiece(set, 1, "icon", 0, 0)
    for _, h in ipairs(hooks) do
        D.AddPiece(set, h[1], "icon", 0, 0)
        T.truthy(D.Hook(set, h[1], h[2], h[3], "center"))
    end
    if grow then D.SetChainValue(set, 1, "grow", grow) end
    local F = D.Layout(set)
    T.deq({ F[1].x, F[1].y, F[2].x, F[2].y, F[3].x, F[3].y, F[4].x, F[4].y },
        { 0, 0, 40, 0, 0, -40, 40, -40 }, "a 2x2")
    return set, F
end

local ROWS = { { 2, 1, "right" }, { 3, 1, "down" }, { 4, 3, "right" } }

-- A player's 2x2 with Slide over: the first spell gave up its spot, and the second
-- row rose into the first, one spell on top of another.
T.test("cdm data: a 2x2's hidden first piece: its row-mate takes its spot, the second row stays", function()
    local D = data()
    local set, F = grid(D, ROWS)
    local shown = { [2] = true, [3] = true, [4] = true }
    local L = D.Layout(set, shown)
    noOverlap(L, shown, "start")
    T.deq({ L[2].x, L[2].y }, { 0, 0 }, "2 slid into 1's spot")
    T.deq(box(L[3]), box(F[3]), "3 kept its spot")
    T.deq(box(L[4]), box(F[4]), "4 kept its spot")
end)

T.test("cdm data: a 2x2's hidden first piece, growing from the middle or the end", function()
    local D = data()
    local set, F = grid(D, ROWS, "center")
    local shown = { [2] = true, [3] = true, [4] = true }
    local L = D.Layout(set, shown)
    noOverlap(L, shown, "center")
    T.deq({ L[2].x, L[2].y }, { 20, 0 }, "2 alone in the middle of the top row")
    T.deq(box(L[3]), box(F[3])); T.deq(box(L[4]), box(F[4]))
    D.SetChainValue(set, 1, "grow", "end")
    L = D.Layout(set, shown)
    noOverlap(L, shown, "end")
    T.deq(box(L[2]), box(F[2]), "the top row's far end stays")
    T.deq(box(L[3]), box(F[3])); T.deq(box(L[4]), box(F[4]))
end)

T.test("cdm data: a 2x2 built in columns: its hidden first piece's column-mate takes its spot", function()
    local D = data()
    local set, F = grid(D, { { 3, 1, "down" }, { 2, 1, "right" }, { 4, 2, "down" } })
    local shown = { [2] = true, [3] = true, [4] = true }
    local L = D.Layout(set, shown)
    noOverlap(L, shown, "columns")
    T.deq({ L[3].x, L[3].y }, { 0, 0 }, "3 slid up into 1's spot")
    T.deq(box(L[2]), box(F[2]), "the other column stays")
    T.deq(box(L[4]), box(F[4]))
end)

-- Every way to snap a 2x2 with its first piece top-left, every grow, every set of
-- pieces down: no two shown pieces cover each other.
T.test("cdm data: a 2x2 with any pieces down never stacks one piece on another", function()
    local D = data()
    local shapes = {
        ROWS,
        { { 2, 1, "right" }, { 3, 1, "down" }, { 4, 2, "down" } },
        { { 2, 1, "right" }, { 4, 2, "down" }, { 3, 4, "left" } },
        { { 3, 1, "down" }, { 4, 3, "right" }, { 2, 4, "up" } },
    }
    for n, hooks in ipairs(shapes) do
        for _, grow in ipairs({ "start", "center", "end" }) do
            local set, F = grid(D, hooks, grow)
            for mask = 1, 14 do
                local shown, ids = {}, {}
                for id = 1, 4 do
                    if bit.band(mask, 2 ^ (id - 1)) ~= 0 then shown[id] = true; ids[#ids + 1] = id end
                end
                local L = D.Layout(set, shown)
                local why = "shape " .. n .. ", " .. grow .. ", up: " .. table.concat(ids, " ")
                noOverlap(L, shown, why)
            end
        end
    end
end)

-- The same 2x2 as bars, which are wide and flat, so a row closing along the wrong
-- axis shows up on them too.
T.test("cdm data: a 2x2 of bars with any pieces down never stacks one bar on another", function()
    local D = data()
    local set = empty()
    D.AddPiece(set, 1, "bar", 0, 0)
    for _, h in ipairs(ROWS) do
        D.AddPiece(set, h[1], "bar", 0, 0)
        T.truthy(D.Hook(set, h[1], h[2], h[3], "center"))
    end
    local F = D.Layout(set)
    T.truthy(F[2].x > F[1].x and F[3].y < F[1].y, "a 2x2 of bars")
    local L = D.Layout(set, { [2] = true, [3] = true, [4] = true })
    T.deq({ L[2].x, L[2].y }, { F[1].x, F[1].y }, "2 slid into 1's spot")
    T.deq(box(L[3]), box(F[3]), "the second row stays")
    T.deq(box(L[4]), box(F[4]))
    for mask = 1, 14 do
        local shown, ids = {}, {}
        for id = 1, 4 do
            if bit.band(mask, 2 ^ (id - 1)) ~= 0 then shown[id] = true; ids[#ids + 1] = id end
        end
        noOverlap(D.Layout(set, shown), shown, "bars, up: " .. table.concat(ids, " "))
    end
end)

T.test("cdm data: the chain look, a piece's own look, and own icon size", function()
    local D = data()
    local set = filled(D)
    D.Chain(set, 12).look.size = 30
    T.eq(D.PieceLook(set, 13, "size"), 30, "set through any piece: the chain's")
    set.pieces[13].look = { size = 50 }
    T.eq(D.PieceLook(set, 13, "size"), 50)
    T.eq(select(1, D.Dims(set, 12)), 30)
    set.pieces[12].size = 20
    T.eq(select(1, D.Dims(set, 12)), 20, "a spell's own size wins")
    local b = D.PieceBlock(set, 13)
    T.eq(b.kind, "icon"); T.eq(b.size, 50); T.eq(b.collapse, true); T.eq(b.combat, false)
    set.chains[11].combat = true
    T.eq(D.PieceBlock(set, 12).combat, true)
    T.truthy(D.Native(b, "icon")); T.falsy(D.Native(b, "bar"))
end)

T.test("cdm data: unhooking keeps the chain's settings; removing frees what hung off", function()
    local D = data()
    local set = filled(D)
    D.Chain(set, 11).look.size = 30
    D.Unhook(set, 12, 200, 10)
    T.isnil(set.pieces[12].parent)
    T.eq(set.pieces[12].x, 200)
    T.eq(set.chains[12].look.size, 30, "the freed chain kept its look")
    T.eq(D.Root(set, 13), 12)
    D.RemovePiece(set, 12)
    T.isnil(set.pieces[12])
    T.isnil(set.pieces[13].parent, "13 is free now")
    T.eq(set.pieces[13].x, 234, "where it was (30 px icons)")
    T.eq(set.chains[13].look.size, 30)
end)

T.test("cdm data: AddPiece on a placed spell keeps its options", function()
    local D = data()
    local set = filled(D)
    set.pieces[12].glow = false
    D.AddPiece(set, 12, "bar", 5, 6)
    T.eq(set.pieces[12].glow, false)
    T.eq(set.pieces[12].shape, "bar")
    T.isnil(set.pieces[12].parent)
end)

T.test("cdm data: the tree index is kept until the layout changes", function()
    local D = data()
    local set = filled(D)
    local a = D.Index(set)
    T.truthy(D.Index(set) == a, "kept")
    D.AddPiece(set, 20, "icon", 0, 0)
    T.truthy(D.Index(set) ~= a, "rebuilt after a change")
end)

T.test("cdm profiles: a copy is deep, of the same class, with a free name", function()
    local DUI, D = profileWorld()
    local id = D.NewProfile("Raid")
    D.AddChain(D.Profile(id).set, { 11, 12, 13 }, "icon", 0, 0)
    local copy = D.CopyProfile(id)
    T.truthy(copy ~= id)
    T.eq(D.Profile(copy).name, "Raid 2")
    T.eq(D.Profile(copy).class, "WARRIOR")
    T.eq(D.Profile(copy).set.pieces[12].parent, 11)
    D.Profile(id).set.pieces[12].side = "down"
    T.eq(D.Profile(copy).set.pieces[12].side, "right", "a copy, not shared")
end)

T.test("cdm profiles: a copy of an old-format layout moves it first", function()
    local DUI, D = profileWorld()
    local id = D.NewProfile("Old", nil, { blocks = { { kind = "icon", x = 0, y = 0, dir = "row", grow = "start", size = 36, spacing = 4, perLine = 8 } },
        buttons = { [11] = { block = 1, order = 1 }, [12] = { block = 1, order = 2 } } })
    local to = D.Profile(D.CopyProfile(id)).set
    T.eq(to.pieces[12].parent, 11)
    T.isnil(to.blocks)
end)

T.test("cdm data: Current follows the talent set", function()
    local DUI, D = profileWorld()
    local g = 1
    DUI.DB.SpecGroup = function() return g end
    D.Assign(1, D.NewProfile("One"))
    local one = D.Current()
    D.AddPiece(one, 11, "icon", 0, 0)
    g = 2
    local two = D.Current()
    T.truthy(one ~= two, "a table each")
    T.isnil(next(two.pieces), "set 2 has no profile: empty")
    T.truthy(D.Get(1).pieces[11], "set 1 kept its piece")
    g = 1
    T.truthy(D.Current() == one)
end)

T.test("cdm profiles: account-wide, shown to their class only, one picked per talent set", function()
    local DUI, D = profileWorld()
    T.eq(D.SETS, 2)
    local a, b = D.NewProfile("Tank"), D.NewProfile("Dps")
    D.Assign(1, a); D.Assign(2, b)
    D.AddPiece(D.Get(1), 11, "icon", 0, 0)
    T.truthy(DUI.DB.Root().cdmProfiles[a].set.pieces[11], "saved in the account's profiles")
    T.eq(DUI.DB.Character().cdm.use[1], a, "the character keeps only its picks")
    T.isnil(DUI:Get("ActionBars", "cdmLayout"), "not in the UI profile")
    local names = {}
    for _, p in ipairs(D.Profiles()) do names[#names + 1] = p.name end
    T.deq(names, { "Dps", "Tank" })
    T.truthy(D.Switch("on")); T.truthy(D.Switch("hideUnplaced"))
    D.SetSwitch("on", false)
    T.eq(DUI.DB.Character().cdm.on, false)
    -- Another Warrior sees them and picks its own. A Mage sees none.
    stub.units.player.name = "Other"
    T.isnil(D.Use(1), "another character picks its own")
    T.eq(#D.Profiles(), 2, "the class's profiles are there")
    D.Assign(1, a)
    T.truthy(D.Get(1).pieces[11], "the same profile, shared")
    T.truthy(D.Switch("on"), "with its own switches")
    stub.units.player.class = "MAGE"
    T.eq(#D.Profiles(), 0, "another class sees none")
    T.isnil(D.Use(1), "a pick of another class's profile counts as none")
    stub.units.player.name = "Tester"
    stub.units.player.class = "WARRIOR"
    T.eq(D.Use(1), a)
end)

T.test("cdm profiles: rename keeps names apart; delete leaves the talent sets that used it with none", function()
    local DUI, D = profileWorld()
    local a, b = D.NewProfile("Tank"), D.NewProfile("Dps")
    T.truthy(D.RenameProfile(b, "tank"))
    T.eq(D.Profile(b).name, "tank 2", "no two of a class share a name")
    T.falsy(D.RenameProfile(b, "  "))
    D.Assign(1, a); D.Assign(2, a)
    T.truthy(D.DeleteProfile(a))
    T.isnil(D.Use(1)); T.isnil(D.Use(2))
    T.isnil(next(D.Get(1).pieces), "nothing to show")
end)

T.test("cdm profiles: the editor saves an unpicked talent set's layout as a new profile", function()
    local DUI, D = profileWorld()
    T.isnil(D.Use(1))
    local set = D.Ensure(1)
    local id = D.Use(1)
    T.truthy(id, "made and picked")
    T.truthy(D.Profile(id).set == set, "the same table, so nothing placed is lost")
    T.truthy(D.Ensure(1) == set, "only once")
    T.eq(#D.Profiles(), 1)
end)

T.test("cdm data: a set outside 1..SETS is empty and not saved", function()
    local DUI, D = profileWorld()
    D.AddPiece(D.Get(3), 11, "icon", 0, 0)
    T.isnil(next(D.Get(3).pieces))
    T.isnil(next(D.Get(1.5).pieces))
    T.falsy(D.Assign(3, D.NewProfile("x")))
end)

T.test("cdm profiles: each character's old layouts become profiles of its class, picked as before", function()
    local DUI, D = profileWorld()
    local root = DUI.DB.Root()
    root.characters = root.characters or {}
    root.characters["Alt-Realm"] = { class = "PRIEST", cdm = { sets = { [2] = { v = 2, pieces = { [11] = { shape = "icon", x = 0, y = 0 } }, chains = {} } } } }
    root.characters["Unknown-Realm"] = { cdm = { sets = { [1] = { v = 2, pieces = { [11] = { shape = "icon", x = 0, y = 0 } }, chains = {} } } } }
    local set = oldLayout(DUI, D, 1, { v = 2, pieces = { [12] = { shape = "icon", x = 5, y = 6 } }, chains = {} })
    T.eq(set.pieces[12].x, 5)
    T.eq(D.Profile(D.Use(1)).name, "Tester")
    T.isnil(DUI.DB.Character().cdm.sets, "moved")
    local alt = root.characters["Alt-Realm"].cdm
    T.isnil(alt.sets)
    T.eq(D.Profile(alt.use[2]).class, "PRIEST")
    T.eq(D.Profile(alt.use[2]).name, "Alt")
    T.truthy(root.characters["Unknown-Realm"].cdm.sets, "class unknown: waits for its own login")
end)

T.test("cdm data: the old profile layouts move to saved copies, once", function()
    local DUI = loadWorld({ actionbars = true })
    local D = stub.actionbars.CdmData
    local root = DUI.DB.Root()
    root.cdmMoved, root.cdmSaved = nil, nil
    local function old(n)
        local s = oldSet({}, {})
        for i = 1, n do s.blocks[i] = oldBlock("icon") end
        return s
    end
    local ab = root.profileData[DUI.DB.DEFAULT].modules.ActionBars
    ab.cdmLayout = { [1] = old(2), [2] = old(0) }
    ab.cdmLayoutOn = false
    ab.cdmBars = false; ab.cdmColor = "spell"
    root.profileData.Healer = { modules = { ActionBars = { cdmLayout = { [1] = old(0) }, cdmHideUnplaced = false } } }
    D.MoveOld()
    T.eq(#root.cdmSaved[DUI.DB.DEFAULT][1].blocks, 2)
    T.isnil(root.cdmSaved[DUI.DB.DEFAULT][2], "an empty set isn't kept")
    T.isnil(root.cdmSaved.Healer, "nothing to keep")
    T.isnil(ab.cdmLayout); T.isnil(ab.cdmLayoutOn)
    T.isnil(ab.cdmBars); T.isnil(ab.cdmColor)
    T.isnil(root.profileData.Healer.modules.ActionBars.cdmHideUnplaced)
    T.isnil(next(D.Get(1).pieces), "the character starts empty")
    ab.cdmLayout = { [1] = old(5) }
    D.MoveOld()
    T.eq(#root.cdmSaved[DUI.DB.DEFAULT][1].blocks, 2, "runs once")
end)

T.test("cdm profiles: a parked old layout comes back, picked, for a character with none", function()
    local DUI, D = profileWorld()
    parked(DUI, DUI.DB.DEFAULT, 1)
    D.TakeSaved(true)
    local id = D.Use(1)
    T.truthy(id, "picked for talent set 1")
    T.eq(D.Profile(id).class, "WARRIOR")
    T.eq(D.Profile(id).name, DUI.DB.DEFAULT)
    T.truthy(D.Get(1).pieces[11]); T.truthy(D.Get(1).pieces[12])
    T.eq(D.Use(2), id, "the other talent set had none: the same layout")
    T.eq(DUI.DB.Root().cdmSaved[DUI.DB.DEFAULT][1].pieces, nil, "the parked copy is left as it was")
    -- Once per character, so a deleted one stays deleted.
    D.DeleteProfile(id)
    D.TakeSaved(true)
    T.isnil(D.Use(1)); T.eq(#D.Profiles(), 0)
end)

T.test("cdm profiles: a parked layout under another profile's name is found by the character's profile", function()
    local DUI, D = profileWorld()
    parked(DUI, "Raid", 1)
    parked(DUI, "Solo", 2)
    DUI.DB.Character().profile = "Solo"
    D.TakeSaved(true)
    T.eq(D.Profile(D.Use(1)).name, "Solo")
end)

T.test("cdm profiles: a character with a layout picked keeps it; the parked one joins the list", function()
    local DUI, D = profileWorld()
    local mine = D.NewProfile("Mine")
    D.Assign(1, mine)
    parked(DUI, DUI.DB.DEFAULT, 1)
    D.TakeSaved(true)
    T.eq(D.Use(1), mine)
    T.isnil(D.Use(2), "nothing picked for a talent set left empty on purpose")
    T.eq(#D.Profiles(), 2)
end)

T.test("cdm profiles: two characters that shared an entry each see the shared layout, in their own class", function()
    local set = { v = 2, pieces = { [11] = { shape = "icon", x = 0, y = 0 } }, chains = {} }
    local DUI, D = boopy("Dadoopy", "WARRIOR", { version = 2, profileData = { ["DPS/Tank"] = {} }, cdmMoved = 2, cdmNextProfile = 1,
        cdmProfiles = { p1 = { name = "Boopy", class = "WARRIOR", set = set } },
        characters = { ["Boopy-R"] = { profile = "DPS/Tank", install = "installed", cdm = { use = { [1] = "p1" } } } } })
    T.eq(D.Use(1), "p1", "the class that made it keeps it")
    local saved = DaylightUIDB
    DUI, D = boopy("Mcdoopy", "PRIEST", saved)
    D.Get(1)   -- the first layout pass, as in game
    local id = D.Use(1)
    T.truthy(id and id ~= "p1", "the other class gets its own copy")
    T.eq(D.Profile(id).class, "PRIEST")
    T.truthy(D.Get(1).pieces[11])
    saved = DaylightUIDB
    DUI, D = boopy("Dadoopy", "WARRIOR", saved)
    D.Get(1)
    T.eq(D.Use(1), "p1", "and logging back in copies nothing back")
    DUI, D = boopy("Mcdoopy", "PRIEST", DaylightUIDB)
    D.Get(1)
    T.eq(D.Use(1), id)
    T.eq(#D.Profiles("PRIEST"), 1); T.eq(#D.Profiles("WARRIOR"), 1)
    T.truthy(DaylightUIDB.characters["Boopy Mcdoopy-R"], "each keyed by first and last name")
    _G.GetRealmName = nil
end)

T.test("cdm profiles: the player whose paladin layout was filed as their hunter's gets it back on both", function()
    local DUI, D = nightz("Pali", "PALADIN", nightzFile())
    T.eq(D.Profile(D.Use(1)).class, "PALADIN")
    T.truthy(D.Get(1).pieces["s1311649"], "talent set 1: the layout")
    T.truthy(D.Get(2).pieces[200265], "talent set 2 had nothing: the same layout")
    T.eq(DaylightUIDB.cdmProfiles.p1.class, "HUNTER", "the hunter's stays")
    -- Emptied on purpose later, so it doesn't come back.
    D.Assign(1, D.NewProfile("Blank"))
    DUI, D = nightz("Pali", "PALADIN", DaylightUIDB)
    T.isnil(next(D.Get(1).pieces))
    _G.GetRealmName = nil
end)

T.test("cdm profiles: the hunter sharing that entry keeps the layout, not the paladin's empty one", function()
    local DUI, D = nightz("Pali", "PALADIN", nightzFile())
    DUI, D = nightz("Hunt", "HUNTER", DaylightUIDB)
    T.eq(D.Use(1), "p1")
    T.truthy(D.Get(1).pieces["s1311649"])
    T.eq(#D.Profiles("HUNTER"), 1, "no empty copy made for it")
    _G.GetRealmName = nil
end)

T.test("cdm profiles: as 1.6.5 found it, two empty paladin picks, both filled", function()
    local db = nightzFile()
    db.cdmNextProfile = 3
    db.cdmProfiles.p3 = { class = "PALADIN", name = "Paladin 2", set = { v = 2, chains = {}, pieces = {} } }
    db.characters["Nightz Pali-R"] = db.characters["Nightz-R"]
    db.characters["Nightz Pali-R"].cdm.use = { "p2", "p3" }
    db.characters["Nightz Pali-R"].fromShort = true
    db.characters["Nightz-R"] = nil
    local DUI, D = nightz("Pali", "PALADIN", db)
    T.truthy(D.Get(1).pieces["s1311649"]); T.truthy(D.Get(2).pieces["s1311649"])
    T.eq(D.Use(1), D.Use(2), "one copy")
    _G.GetRealmName = nil
end)

T.test("cdm profiles: a pick of another class's profile becomes a copy for this class, once", function()
    local DUI, D = profileWorld()
    local war = D.NewProfile("Shared")
    D.AddChain(D.Profile(war).set, { 11, 12 }, "icon", 0, 0)
    D.Assign(1, war); D.Assign(2, war)
    stub.units.player.class = "PRIEST"
    D.MendShared()
    local mine = D.Use(1)
    T.truthy(mine and mine ~= war)
    T.eq(D.Use(2), mine, "one copy for both talent sets")
    T.eq(D.Profile(mine).name, "Shared")
    T.truthy(D.Get(1).pieces[12])
    T.eq(D.Profile(war).class, "WARRIOR", "the original is left as it was")
end)

T.test("cdm profiles: characters of one class share the parked layout's profile; another class gets its own", function()
    local DUI, D = profileWorld()
    parked(DUI, DUI.DB.DEFAULT, 1)
    D.TakeSaved(true)
    local first = D.Use(1)
    DUI.DB.Character().cdm = { use = {} }   -- an alt of the same class, logging in
    D.TakeSaved(true)
    T.eq(D.Use(1), first)
    stub.units.player.class = "PRIEST"
    DUI.DB.Character().cdm = { use = {} }
    D.TakeSaved(true)
    local priest = D.Use(1)
    T.truthy(priest and priest ~= first)
    T.eq(D.Profile(priest).class, "PRIEST")
end)

-- A druid's layout as a player's file had it: Moonfire and Demoralizing Roar by
-- spell, Moonfire again as the game's cooldown 41, Mark of the Wild (a buff any
-- class can wear) and the trinket slot.
local function druidPieces()
    return {
        ["s8921"] = { shape = "bar", x = 0, y = 0 },
        ["s99"] = { shape = "bar", parent = "s8921", side = "down", align = "start" },
        [41] = { shape = "icon", x = 0, y = -80 },
        ["s1126"] = { shape = "icon", x = 60, y = -80 },
        [13] = { shape = "icon", x = 120, y = -80 },
    }
end
local function moonfireInfo()
    _G.C_CooldownViewer = _G.C_CooldownViewer or {}
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        if id == 41 then return { spellID = 9835 } end
    end
end

T.test("cdm profiles: a new warrior sharing a druid's first name gets none of the druid's spells", function()
    local db = { version = 2, profileData = { ["DPS/Tank"] = {} }, cdmMoved = 2, cdmNextProfile = 1,
        cdmProfiles = { p1 = { name = "Boopy", class = "DRUID", set = { v = 2, chains = {}, pieces = druidPieces() } } },
        characters = { ["Boopy Dadoopy-R"] = { profile = "DPS/Tank", install = "installed", class = "DRUID",
            cdm = { use = { "p1", "p1" } } } } }
    local DUI, D = boopy("Mcdoopy", "WARRIOR", db)
    moonfireInfo()
    local pieces = D.Get(1).pieces
    T.isnil(D.Use(1), "the druid's layout isn't copied")
    T.isnil(pieces["s8921"], "Moonfire is a druid's")
    T.isnil(pieces["s99"], "Demoralizing Roar is a druid's")
    T.isnil(pieces[41], "the game's Moonfire cooldown too")
    for _, p in pairs(DaylightUIDB.cdmProfiles) do
        if p.class == "WARRIOR" then
            T.isnil(p.set.pieces["s8921"], "no warrior profile holds Moonfire")
        end
    end
    T.eq(DaylightUIDB.cdmProfiles.p1.class, "DRUID", "the druid's own is left as it was")
    T.truthy(DaylightUIDB.cdmProfiles.p1.set.pieces["s8921"])
    _G.GetRealmName = nil
end)

T.test("cdm profiles: an old layout parked from a druid comes back to a warrior without the druid's spells", function()
    local DUI, D = profileWorld("WARRIOR")
    moonfireInfo()
    local root = DUI.DB.Root()
    root.cdmSaved = { [DUI.DB.DEFAULT] = { [1] = oldSet({ oldBlock("icon") }, inBlock(1, { "s8921", "s99", 11 })) } }
    D.TakeSaved(true)
    local pieces = D.Get(1).pieces
    T.isnil(pieces["s8921"]); T.isnil(pieces["s99"])
    T.isnil(D.Use(1), "it was the druid's layout: nothing to bring back")
end)

T.test("cdm profiles: a warrior's saved copy of a druid layout loses the druid's spells, keeps its own", function()
    local mine = druidPieces()
    mine["s6673"] = { shape = "bar", parent = "s99", side = "down", align = "start" }   -- Battle Shout, added later
    local db = { version = 2, profileData = { ["DPS/Tank"] = {} }, cdmMoved = 2, cdmNextProfile = 2,
        cdmClassCopies = { ["p1|WARRIOR"] = "p2" },
        cdmProfiles = {
            p1 = { name = "Boopy", class = "DRUID", set = { v = 2, chains = {}, pieces = druidPieces() } },
            p2 = { name = "Boopy", class = "WARRIOR", from = "p1", set = { v = 2, chains = {}, pieces = mine } },
        },
        characters = { ["Boopy Mcdoopy-R"] = { profile = "DPS/Tank", install = "installed",
            cdm = { use = { "p2", "p2" }, sharedLooked = true, savedTaken = true } } } }
    local DUI, D = boopy("Mcdoopy", "WARRIOR", db)
    moonfireInfo()
    local pieces = D.Get(1).pieces
    T.eq(D.Use(1), "p2")
    T.isnil(pieces["s8921"]); T.isnil(pieces["s99"]); T.isnil(pieces[41])
    T.truthy(pieces["s6673"], "the warrior's own Battle Shout stays")
    T.isnil(pieces["s6673"].parent, "and goes free where it was")
    T.truthy(pieces["s1126"], "a buff any class can wear stays")
    T.truthy(pieces[13], "the trinket slot stays")
    _G.GetRealmName = nil
end)

T.test("cdm data: a set still in the old rows format starts empty", function()
    local DUI, D = profileWorld()
    local set = oldLayout(DUI, D, 1, { rows = { { kind = "icon" } }, buttons = { [11] = { row = 1, order = 1 } }, blocks = { {} } })
    T.isnil(set.rows)
    T.isnil(next(set.pieces))
end)

T.test("cdm data: an old row block becomes a chain in the same spot, options kept", function()
    local DUI, D = profileWorld()
    local buttons = inBlock(1, { 11, 12, 13 })
    buttons[12].glow = false
    local set = oldLayout(DUI, D, 1, oldSet({ oldBlock("icon", { x = 10, y = 20, grow = "start", combat = true }) }, buttons))
    T.eq(set.v, 2)
    T.isnil(set.blocks); T.isnil(set.buttons)
    T.truthy(set.old and set.old.blocks[1], "the old tables kept")
    -- the old layout frame sat at 0, -120, and a start row's anchor is its top-left
    T.eq(set.pieces[11].x, 10); T.eq(set.pieces[11].y, -100)
    T.eq(set.pieces[12].parent, 11); T.eq(set.pieces[12].side, "right"); T.eq(set.pieces[12].gap, 4)
    T.eq(set.pieces[12].glow, false, "the spell's options came along")
    T.isnil(set.pieces[12].block)
    T.eq(set.chains[11].combat, true)
    T.eq(set.chains[11].look.size, 36)
end)

T.test("cdm data: the old layout's position is read from its mover", function()
    local DUI, D = profileWorld()
    DUI.DB.Positions()["cdm.s1"] = { 300, 200 }
    local set = oldLayout(DUI, D, 1, oldSet({ oldBlock("icon", { grow = "start" }) }, inBlock(1, { 11 })))
    T.eq(set.pieces[11].x, 300); T.eq(set.pieces[11].y, 200)
end)

T.test("cdm data: an old centered row keeps its middle; old grow-from-end runs the other way", function()
    local D = data()
    local set = oldSet({ oldBlock("icon", { x = 0, y = 0 }), oldBlock("icon", { grow = "end", x = 0, y = -100 }) },
        inBlock(1, { 11, 12, 13 }))
    for id, b in pairs(inBlock(2, { 21, 22 })) do set.buttons[id] = b end
    D.Migrate(set, 0, 0)
    -- three 36 px icons, 4 apart, centered on 0, so the first starts at -58
    T.eq(set.pieces[11].x, -58); T.eq(set.pieces[11].y, 0)
    T.eq(set.chains[11].grow, "center")
    local L = D.Layout(set, { [11] = true, [13] = true, [21] = true, [22] = true })
    T.eq(L[11].x, -38, "still centered with one hidden")
    T.eq(set.pieces[22].side, "left", "grow from end: each next one to the left")
    T.eq(set.pieces[21].x, -36, "its first slot ends at the old anchor")
end)

T.test("cdm data: old wrapped lines and bar columns", function()
    local D = data()
    local set = oldSet({ oldBlock("icon", { grow = "start", perLine = 2 }), oldBlock("bar", { x = 0, y = 0 }) },
        inBlock(1, { 11, 12, 13 }))
    for id, b in pairs(inBlock(2, { 21, 22 })) do set.buttons[id] = b end
    D.Migrate(set, 0, 0)
    T.eq(set.pieces[13].parent, 11, "a new line starts under the line before's first")
    T.eq(set.pieces[13].side, "down"); T.eq(set.pieces[13].align, "start")
    T.eq(set.pieces[21].shape, "bar")
    T.eq(set.pieces[22].side, "up", "an old bar block grew up from its bottom")
    T.eq(set.pieces[21].y, 18, "its first bar's bottom sat on the anchor")
    T.eq(set.chains[21].look.width, 220); T.eq(set.chains[21].look.height, 18)
    T.eq(set.chains[21].look.color, "class")
end)

-- The real layout

T.test("cdm rows: one layout frame per talent set at the screen's center, no movers", function()
    local DUI, AB = rowsWorld()
    T.isnil(DUI.Movers.Get("cdm.s1"), "placed by the editor, not unlock mode")
    local p, rel, rp = layoutFrame(1):GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.falsy(layoutFrame(1):IsShown(), "nothing placed: hidden")
end)

T.test("cdm rows: each piece's frame sits at its box, the item in it", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    D.AddChain(set, { 11, 13 }, "icon", 50, -20)
    R.Refresh(); stub.RunTimers()
    local layout = layoutFrame(1)
    T.truthy(layout:IsShown(), "layout shown")
    local f = pieceFrame(1, 11)
    T.truthy(f:IsShown())
    local p, rel, rp, x, y = f:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, layout); T.eq(rp, "CENTER"); T.eq(x, 50); T.eq(y, -20)
    T.eq(f:GetWidth(), 36)
    T.eq(select(4, pieceFrame(1, 13):GetPoint(1)), 90, "the next one 4 px on")
    p, rel = ess[1]:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, f)
    T.eq(ess[1]:GetWidth(), 36)
    T.eq(select(2, ess[3]:GetPoint(1)), pieceFrame(1, 13))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: the layout is a fade area, so the campfire's hush reaches it; the game's viewers keep their own opacity", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    D.AddPiece(D.Current(), 11, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    local viewer = _G.EssentialCooldownViewer
    _G.Enum = _G.Enum or {}
    Enum.EditModeCooldownViewerSetting = Enum.EditModeCooldownViewerSetting or { Opacity = 5 }
    function viewer:GetSettingValue(k) return k == Enum.EditModeCooldownViewerSetting.Opacity and 50 or nil end
    local F = DUI.Fade
    local list = R.FadeFrames()
    T.eq(list[1], layoutFrame(1)); T.eq(list[2], pieceFrame(1, 11))
    R.PaintFade(layoutFrame(1), 1)
    T.near(viewer:GetAlpha(), 0.5, 1e-6, "the viewer at its Edit Mode opacity")
    F.Hush("camp", { "ActionBars." })
    F.Step()
    for _ = 1, 60 * (F.HUSH_OUT + 1) do stub.RunOnUpdate(F.driver, 1 / 60) end
    T.eq(layoutFrame(1):GetAlpha(), 0, "hushed: the layout gone")
    T.eq(viewer:GetAlpha(), 0, "and the game's items with their viewer")
    T.eq(pieceFrame(1, 11):GetAlpha(), 1, "the piece itself untouched (it follows the layout)")
    F.Unhush("camp", true)
    T.eq(layoutFrame(1):GetAlpha(), 1)
    T.near(viewer:GetAlpha(), 0.5, 1e-6)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: unplaced items stay hidden while the layout is on", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    R.Refresh(); stub.RunTimers()
    T.eq(ess[2]:GetAlpha(), 0, "nothing placed yet: the game's items still hidden")
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1)
    T.eq(ess[2]:GetAlpha(), 0, "unplaced faded")
    D.SetSwitch("hideUnplaced", false)
    R.Refresh(); stub.RunTimers()
    T.eq(ess[2]:GetAlpha(), 0, "an old saved value can't bring them back")
    D.SetSwitch("on", false)
    R.Refresh(); stub.RunTimers()
    T.eq(ess[2]:GetAlpha(), 1, "layout off releases everything")
    T.falsy(R.Owns(ess[1]), "and forgets it")
    T.falsy(layoutFrame(1):IsShown())
end)

T.test("cdm rows: items without a cooldownID are left alone", function()
    local DUI, AB = rowsWorld()
    local _, util = fakeViewer("UtilityCooldownViewer", { false })
    util[1].cooldownID = nil
    local D, R = AB.CdmData, AB.CdmRows
    D.AddPiece(D.Current(), 11, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(util[1]:GetAlpha(), 1)
end)

T.test("cdm rows: a game bar placed as an icon isn't claimed: it hides and our aura icon shows it", function()
    local DUI, AB, ess, bars = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    D.AddChain(set, { 21, 11 }, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.falsy(R.Owns(bars[1]), "a bar placed as an icon: not claimed")
    T.eq(bars[1]:GetAlpha(), 0, "the game's bar out of sight")
    T.falsy(bars[1]:IsMouseEnabled())
    T.eq(R.DrawnBy(21), "aura icon")
    local h = AB.CdmAuras.Frame(21)
    T.truthy(h and h:IsShown(), "the client's aura display in our holder")
    T.eq(h:GetParent(), pieceFrame(1, 21))
    T.truthy(R.Owns(ess[1]))
    T.eq(R.DrawnBy(11), "game")
    -- Out of the layout, the game's bar stays out of sight with the rest.
    D.RemovePiece(set, 21)
    R.Refresh(); stub.RunTimers()
    T.eq(bars[1]:GetAlpha(), 0)
    T.falsy(h:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: switching talent set shows the other set's layout", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    DUI.DB.SpecGroup = function() return 1 end
    D.AddPiece(D.Get(1), 11, "icon", 0, 0)
    D.AddPiece(D.Get(2), 12, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.truthy(layoutFrame(1):IsShown()); T.falsy(layoutFrame(2):IsShown())
    changeSpecTo(DUI, 2); stub.RunTimers()
    T.falsy(layoutFrame(1):IsShown(), "set 1 hidden")
    T.truthy(layoutFrame(2):IsShown())
    T.truthy(R.Owns(ess[2])); T.falsy(R.Owns(ess[1]))
    T.eq(select(2, ess[2]:GetPoint(1)), pieceFrame(2, 12))
end)

T.test("cdm rows: a hidden item closes up its chain", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    ess[1]:Hide()
    R.Refresh(); stub.RunTimers()
    T.eq(select(4, pieceFrame(1, 12):GetPoint(1)), 0, "the next one moves up")
    T.eq(select(4, pieceFrame(1, 13):GetPoint(1)), 40)
    T.falsy(pieceFrame(1, 11):IsShown(), "its frame hides")
    D.Chain(set, 11).collapse = false
    D.Changed(); R.Refresh(); stub.RunTimers()
    local x = select(4, pieceFrame(1, 12):GetPoint(1))
    T.truthy(x >= 0 and x < 40, "a shown piece glides, it doesn't jump")
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.eq(select(4, pieceFrame(1, 12):GetPoint(1)), 40, "close the gap off: it keeps its gap")
end)

-- A pass runs under DUI.SafeCall. One that broke partway used to leave the last
-- pass's item list half-filled (it's the same table), so the show rules
-- (Rows.Away) later missed items they were meant to hide.
T.test("cdm rows: a pass that breaks partway keeps the last whole layout for the show rules", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local shown = ess[2].IsShown
    ess[2].IsShown = function() error("broke partway") end
    R.Refresh(); stub.RunTimers()
    ess[2].IsShown = shown
    T.truthy(#stub.errors > 0, "the pass broke")
    for k in pairs(stub.errors) do stub.errors[k] = nil end
    for i = 1, 3 do ess[i]:SetAlpha(1) end
    R.editing = true
    R.Away()
    R.editing = false
    for i = 1, 3 do T.eq(ess[i]:GetAlpha(), 0, "item " .. i .. " steps aside with the rest") end
end)

T.test("cdm rows: a removed piece's frame hides", function()
    local DUI, AB = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.truthy(pieceFrame(1, 12):IsShown())
    D.RemovePiece(set, 12)
    R.Refresh(); stub.RunTimers()
    T.falsy(pieceFrame(1, 12):IsShown())
end)

T.test("cdm rows: a bar placed as a bar gets its chain's size; others keep the game's", function()
    local DUI, AB, _, bars = rowsWorld()
    AB.Cooldowns.Scan()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    D.AddPiece(set, 21, "bar", 0, 0)
    bars[2]:SetSize(270, 30)
    R.Refresh(); stub.RunTimers()
    local b = bars[1]
    T.truthy(R.Owns(b)); T.eq(R.BlockOf(b).kind, "bar")
    T.eq(select(2, b:GetPoint(1)), pieceFrame(1, 21), "in its frame, not the viewer")
    T.eq(b:GetWidth(), 220, "the chain's width")
    T.eq(b:GetHeight(), 18, "the chain's bar height")
    T.eq(b.Icon:GetWidth(), 18, "a square icon")
    T.eq(select(2, b.Bar:GetPoint(1)), b.Icon, "the bar after the icon")
    T.isnil(R.BlockOf(bars[2]))
    T.eq(bars[2]:GetWidth(), 270, "a bar not placed keeps the game's size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: /dui cdm place puts every unplaced item of a kind in a new chain", function()
    local DUI, AB, ess = rowsWorld()
    DUI.RunCommand("cdm place icon"); stub.RunTimers()
    local set = AB.CdmData.Current()
    T.eq(set.pieces[11].shape, "icon")
    T.eq(set.pieces[12].parent, 11)
    T.eq(set.pieces[13].parent, 12)
    T.truthy(AB.CdmRows.Owns(ess[1]))
    T.truthy(stub.ChatContains("3 spells added"))
    DUI.RunCommand("cdm place bar"); stub.RunTimers()
    T.eq(set.pieces[21].shape, "bar")
    T.isnil(set.pieces[21].parent, "a chain of its own")
    T.truthy(set.pieces[21].y < set.pieces[11].y, "below the icons")
    DUI.RunCommand("cdm place nonsense")
    T.truthy(stub.ChatContains("cdm place <icon|bar>"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The layout page and look

-- Shim for tests written with blocks: "block" i is the i-th chain made here
-- (icons in a row, bars in a column, each at 0, -(i-1)*48).
local shim = setmetatable({}, { __mode = "k" })
local function addBlock(D, set, kind)
    local t = shim[set] or {}
    shim[set] = t
    t[#t + 1] = { kind = kind, ids = {} }
    return #t
end
local function place(D, set, id, i, pos)
    local t = shim[set]
    for _, b in ipairs(t) do
        for n = #b.ids, 1, -1 do if b.ids[n] == id then table.remove(b.ids, n) end end
    end
    local b = t[i]
    pos = math.max(1, math.min(pos or #b.ids + 1, #b.ids + 1))
    table.insert(b.ids, pos, id)
    for _, x in ipairs(b.ids) do D.AddPiece(set, x, b.kind, 0, -(i - 1) * 48) end
    for n = 2, #b.ids do D.Hook(set, b.ids[n], b.ids[n - 1], b.kind == "bar" and "down" or "right", "start") end
end
-- Block i's chain settings and look.
local function chainOf(set, i)
    return stub.actionbars.CdmData.Chain(set, shim[set][i].ids[1])
end
local function lookOf(set, i) return chainOf(set, i).look end
local function unplace(D, set, id)
    for _, b in ipairs(shim[set] or {}) do
        for n = #b.ids, 1, -1 do if b.ids[n] == id then table.remove(b.ids, n) end end
    end
    D.RemovePiece(set, id)
end
local function frameOf(id) return _G["DaylightUICdmPiece1_" .. id] end
-- The layout page and look, continued

-- The dev tools' /dui cdm probes (DaylightUI_Dev/CdmProbe.lua), loaded on top.
local function devCdm(DUI, words)
    local ns = {}
    assert(loadfile("DaylightUI_Dev/CdmProbe.lua"))("DaylightUI_Dev", ns)
    DUI.RunCommand("cdm " .. words)
    return ns.CdmProbe
end

-- The rows world as the old editor tests had it (no editor, so E is nil).
local function editorWorld(buffIcons)
    local DUI, AB, ess, bars, icons = rowsWorld(buffIcons)
    return DUI, AB, nil, AB.CdmData, ess, bars, icons
end
T.test("cdm look: a bar chain's look reaches its bars", function()
    local DUI, AB, E, D, _, bars = editorWorld()
    AB.Cooldowns.Scan()
    local CD = AB.Cooldowns
    local b = bars[1]
    function b:GetSpellID() return 11 end
    local set = D.Current()
    D.AddPiece(set, 21, "bar", 0, 0)
    local function redo() D.Changed(); AB.CdmRows.Refresh(); stub.RunTimers() end
    redo()
    T.eq(b.Bar.Name.__font[2], 11, "default text size")
    local clock = AB.BuffBars.Clock(b.cooldownID)
    T.truthy(clock and clock:IsShown() and clock:GetAlpha() == 1, "time on by default: our M:SS clock")
    T.falsy(b.Bar.Duration:IsShown(), "over the game's own time")
    D.Chain(set, 21).look.color = "spell"; redo()
    local want = CD.PALETTE[11 % #CD.PALETTE + 1]
    T.eq(b.Bar.__barColor[1], want[1], "per spell color")
    D.Chain(set, 21).look.text = 14; redo()
    T.eq(b.Bar.Name.__font[2], 14)
    D.Chain(set, 21).look.time = false; redo()
    T.eq(clock:GetAlpha(), 0, "time off")
    T.falsy(b.Bar.Duration:IsShown())
    set.pieces[21].look = { icon = false }; redo()
    T.eq(b.Icon:GetAlpha(), 0, "a piece's own look: icon hidden")
    T.eq(select(2, b.Bar:GetPoint(1)), b, "the bar the whole width with no icon")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm look: per-spell bar colors paint the real bar", function()
    local DUI, AB, E, D, _, bars = editorWorld()
    AB.Cooldowns.Scan()
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 21, "bar", 0, -50)
    local function redo() AB.CdmRows.Refresh(); stub.RunTimers() end
    redo()
    local item
    AB.CdmRows.EachItem(function(it, id) if id == 21 then item = it end end)
    T.truthy(item, "bar claimed")
    local p = set.pieces[21]
    p.barMode, p.barColor = "solid", { 0.9, 0.1, 0.2 }; redo()
    T.deq(item.Bar.__barColor, { 0.9, 0.1, 0.2, 1 }, "solid fill")
    p.backMode, p.backColor = "solid", { 0.3, 0.4, 0.5, 0.6 }; redo()
    T.deq(AB.Cooldowns.Parts(item).back.__vertex, { 0.3, 0.4, 0.5, 0.6 }, "background with its alpha")
    p.barMode = "gradient"; redo()
    T.deq(item.Bar.__barColor, { 1, 1, 1, 1 }, "gradient: white fill")
    T.truthy(item.Bar:GetStatusBarTexture().__gradient, "gradient set on the fill texture")
    p.backMode, p.backGradient = "gradient", { lo = { 1, 0, 0 }, hi = { 0, 0, 1 } }; redo()
    T.truthy(AB.Cooldowns.Parts(item).back.__gradient, "gradient set on the background")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)


T.test("cdm: plain /dui cdm opens the layout; the dev tools take their words", function()
    local DUI, AB = editorWorld()
    DUI.RunCommand("cdm"); stub.RunTimers()
    T.truthy(AB.CdmEditor.IsOpen(), "no dev tools: the editor")
    AB.CdmEditor.Close()
    if T.dev then
        DUI.OptionsPanel.Show("home"); stub.RunTimers()
        devCdm(DUI, "ids")
        T.truthy(stub.ChatContains("Cooldown Manager ids:"), "dev: the ids report")
        T.falsy(AB.CdmEditor.IsOpen(), "a dev word doesn't open the editor")
        T.truthy(type(DaylightUIDevDB) == "table" and DaylightUIDevDB.cdmIds, "kept for report.py")
        DUI.RunCommand("cdm"); stub.RunTimers()
        T.truthy(stub.ChatContains("No Cooldown Manager icons yet") or DaylightUIDevDB.cdm ~= nil, "dev: plain is the viewer report")
        DaylightUIDevDB = nil
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: unlock mode's bar has a Cooldown Manager button that opens the layout", function()
    local DUI, AB = editorWorld()
    T.truthy(DUI.Movers.Unlock(), "unlocked")
    local lock = DUI.Movers.LockButton()
    local b = DUI.Movers.BarButtons()[1]
    T.truthy(b and b:IsShown(), "the button shows on the bar")
    local _, rel = b:GetPoint(1)
    T.eq(rel, lock.areas, "after Areas")
    local _, foldRel = lock.fold:GetPoint(1)
    T.eq(foldRel, b, "Hide after it")
    b:Click(); stub.RunTimers()
    T.falsy(DUI.Movers.unlocked, "unlock mode ends")
    T.truthy(AB.CdmEditor.IsOpen(), "the editor opens")
    AB.CdmEditor.Close()

    -- With Daylight UI's Cooldown Manager off there is nothing to open.
    AB.Cooldowns.enabled = nil
    DUI.Movers.Unlock()
    T.falsy(b:IsShown(), "hidden while it's off")
    local _, rel2 = lock.fold:GetPoint(1)
    T.eq(rel2, lock.areas, "Hide closes up after Areas")
    DUI.Movers.Lock()
    AB.Cooldowns.enabled = true
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: the Escape menu's Cooldown Manager button opens the layout, or leaves it to the game while off", function()
    local DUI, AB = editorWorld()
    T.truthy(DUI.OpenCooldownManager(), "taken")
    T.truthy(AB.CdmEditor.IsOpen(), "the editor opens")
    AB.CdmEditor.Close()
    AB.Cooldowns.enabled = nil
    T.falsy(DUI.OpenCooldownManager(), "off: the game's settings open instead")
    T.falsy(AB.CdmEditor.IsOpen(), "the editor stays shut")
    T.falsy(stub.ChatContains("switch it on"), "nothing printed")
    AB.Cooldowns.enabled = true
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm own: the empty bar takes the spell's background color and follows changes", function()
    local DUI, AB, E, D = editorWorld()
    local set = D.Current()
    addBlock(D, set, "bar"); place(D, set, 21, 1, 1)
    local ph = AB.CdmOwn.Placeholder(21, UIParent, "bar")
    T.deq(ph.Back.__vertex, { 0, 0, 0, DUI.Style.BAR_BACK_ALPHA }, "black by default")
    set.pieces[21].backMode = "solid"; set.pieces[21].backColor = { 0.2, 0.3, 0.4, 0.5 }
    AB.CdmOwn.Placeholder(21, UIParent, "bar")
    T.deq(ph.Back.__vertex, { 0.2, 0.3, 0.4, 0.5 }, "tinted on the second call")
    set.pieces[21].backMode = "gradient"; set.pieces[21].backGradient = { lo = { 1, 0, 0 }, hi = { 0, 0, 1 } }
    AB.CdmOwn.Placeholder(21, UIParent, "bar")
    T.truthy(ph.Back.__gradient, "gradient background")
    set.pieces[21].backMode = nil
    AB.CdmOwn.Placeholder(21, UIParent, "bar")
    T.deq(ph.Back.__vertex, { 0, 0, 0, DUI.Style.BAR_BACK_ALPHA }, "back to black")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: letting an item go never runs the game's layout from our code", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1)
    R.Refresh(); stub.RunTimers()
    local v = _G.EssentialCooldownViewer
    local before = v.__laid or 0
    unplace(D, set, 11)
    R.Refresh(); stub.RunTimers()
    T.falsy(R.Owns(ess[1]), "let go")
    T.eq(v.__laid or 0, before, "tainted RefreshLayout empties the game's pool")
end)

-- No hooks on the game's RefreshLayout, OnAcquireItemFrame or the items'
-- SetPoint. Every time the game lays its items out again comes from an event, a
-- script or an EventRegistry callback, and the re-claim pass right after puts
-- them back.
T.test("cdm rows: the game laying its items out again puts them back in our blocks the frame after", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1)
    R.Refresh(); stub.RunTimers()
    local v, block = _G.EssentialCooldownViewer, frameOf(11)
    T.eq(select(2, ess[1]:GetPoint(1)), block, "claimed")
    local function back(why)
        T.eq(select(2, ess[1]:GetPoint(1)), v, why .. ": the game put it in its grid")
        stub.RunTimers()
        T.eq(select(2, ess[1]:GetPoint(1)), block, why .. ": back in our block the frame after")
        T.eq(ess[2]:GetAlpha(), 0, why .. ": unplaced still hidden")
    end
    -- An Edit Mode setting (its dialog fires no event) hides and shows the items.
    v:RefreshLayout(); back("Edit Mode setting")
    _G.EventRegistry:TriggerEvent("CooldownViewerSettings.OnDataChanged"); back("its settings")
    stub.FireEvent("UNIT_AURA", "target", { isFullUpdate = true }); back("a full aura update")
    v:RefreshLayout(); _G.EventRegistry:TriggerEvent("EditMode.Exit"); back("leaving Edit Mode")
    -- A plain aura change lays nothing out, so no pass runs for it.
    local passes = 0
    R.onUpdate = function() passes = passes + 1 end
    stub.FireEvent("UNIT_AURA", "player", { addedAuras = {} }); stub.RunTimers()
    T.eq(passes, 0, "an added aura is not a layout pass")
    R.onUpdate = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game lays its items out inside the event (a new target's full aura
-- update), so a timer would come after the frame is drawn and the icon would
-- flicker to the game's spot and back. This frame's own OnUpdate runs after the
-- events and before drawing.
T.test("cdm rows: a full aura update puts items back before the frame is drawn, one pass", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1)
    R.Refresh(); stub.RunTimers()
    local v, block = _G.EssentialCooldownViewer, frameOf(11)
    local passes = 0
    R.onUpdate = function() passes = passes + 1 end
    stub.FireEvent("UNIT_AURA", "target", { isFullUpdate = true })
    T.eq(select(2, ess[1]:GetPoint(1)), v, "the game put it in its grid")
    T.truthy(R.now:IsShown(), "a pass is waiting for this frame's OnUpdate")
    stub.RunOnUpdate(R.now, 0)
    T.eq(select(2, ess[1]:GetPoint(1)), block, "back in our block in the same frame")
    T.falsy(R.now:IsShown(), "nothing runs every frame once it's done")
    stub.RunTimers()
    T.eq(passes, 1, "the timer behind it has nothing left to do")
    R.onUpdate = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- In a fight isFullUpdate reads secret on every UNIT_AURA. A raid boss's target
-- sends several a second, so each one must not cost a whole layout pass.
T.test("cdm rows: in a fight a plain aura change runs no layout pass, a full one still puts items back", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1)
    R.Refresh(); stub.RunTimers()
    local block = frameOf(11)
    stub.EnterCombat(); stub.RunTimers()   -- a fight starting may lay out (combat-only chains)
    local passes = 0
    R.onUpdate = function() passes = passes + 1 end
    for _ = 1, 5 do stub.FireEvent("UNIT_AURA", "target", { isFullUpdate = false, addedAuras = {} }) end
    stub.RunTimers()
    T.eq(passes, 0, "secret flag, nothing laid out by the game: no pass")
    stub.FireEvent("UNIT_AURA", "target", { isFullUpdate = true }); stub.RunTimers()
    T.eq(select(2, ess[1]:GetPoint(1)), block, "the game's full update: back in our block")
    R.onUpdate = nil
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: a new item the game makes on a layout pass is skinned and claimed the frame after", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1)
    place(D, set, 14, 1, 2)
    R.Refresh(); stub.RunTimers()
    local v = _G.EssentialCooldownViewer
    -- A spell added in the game's settings: the pool hands out a fresh item.
    local late = CreateFrame("Frame", nil, v)
    late:SetSize(40, 40)
    late.cooldownID, late.layoutIndex = 14, 4
    late.Icon = late:CreateTexture()
    late.art = late:CreateTexture()
    ess[4] = late
    local stray = CreateFrame("Frame", nil, v)
    stray:SetSize(40, 40)
    stray.cooldownID, stray.layoutIndex = 15, 5
    stray.Icon = stray:CreateTexture()
    ess[5] = stray
    _G.EventRegistry:TriggerEvent("CooldownViewerSettings.OnDataChanged")
    stub.RunTimers()
    T.eq(late.art:GetAlpha(), 0, "skinned")
    T.truthy(R.Owns(late), "claimed into its block")
    T.eq(select(2, late:GetPoint(1)), frameOf(late.cooldownID))
    T.eq(stray:GetAlpha(), 0, "an unplaced new one hidden")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: an item moved by something we didn't see is put back by the look-around", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1)
    R.Refresh(); stub.RunTimers()
    local v = _G.EssentialCooldownViewer
    ess[1]:ClearAllPoints()
    ess[1]:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
    T.eq(R.Drifted(), true, "noticed")
    AB.Cooldowns.Tick(); stub.RunTimers()
    T.eq(select(2, ess[1]:GetPoint(1)), frameOf(11), "back in its frame")
    T.eq(R.Drifted(), false, "settled")
    -- A hidden claimed item (inactive) with no anchors isn't drift. Otherwise
    -- every look would refresh.
    ess[1]:Hide(); ess[1]:ClearAllPoints()
    T.eq(R.Drifted(), false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: a bar in a block keeps its icon when the game hides it (Name only), with no hook", function()
    local DUI, AB, _, bars = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    addBlock(D, set, "bar")
    place(D, set, 21, 1, 1)
    R.Refresh(); stub.RunTimers()
    local b = bars[1]
    T.truthy(b.Icon:IsShown(), "icon shown in the block")
    b:SetBarContent(3)
    T.falsy(b.Icon:IsShown(), "the game hid it")
    stub.RunTimers()
    T.truthy(b.Icon:IsShown(), "shown again the frame after")
    T.eq(b.Bar:GetNumPoints(), 2, "the bar laid out again: the game's LEFT point gone")
    T.eq(select(2, b.Bar:GetPoint(1)), b.Icon, "beside the icon")
    -- Outside a block, the game's choice stands.
    unplace(D, set, 21)
    R.Refresh(); stub.RunTimers()
    b:SetBarContent(3); stub.RunTimers()
    T.falsy(b.Icon:IsShown(), "a bar in no block stays the game's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Per-spell effects

-- Block 1 (icons): 11, 12. Block 2 (bars): 21. 13 and 22 unplaced. The game's
-- alert manager is faked, and each icon's swipe is recorded.
local function fxWorld()
    local ess, bars
    local DUI = loadWorld({ actionbars = true, before = function()
        _, ess = fakeViewer("EssentialCooldownViewer", { 11, 12, 13 })
        _, bars = fakeViewer("BuffBarCooldownViewer", { 21, 22 })
        -- The game's alert manager keeps the alert and fires the glow event.
        -- The addon reads HasAlert and nothing hooks it.
        local up = {}
        _G.ActionButtonSpellAlertManager = {
            ShowAlert = function(_, b)
                up[b] = true
                stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1); stub.RunTimers()
            end,
            HideAlert = function(_, b)
                up[b] = nil
                stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 1); stub.RunTimers()
            end,
            HasAlert = function(_, b) return up[b] == true end,
        }
    end })
    stub.RunTimers()
    for _, item in ipairs(ess) do
        item.Cooldown.SetDrawSwipe = function(self, on) self.__swipe = on end
    end
    local AB = stub.actionbars
    local D = AB.CdmData
    local set = D.Current()
    addBlock(D, set, "icon"); addBlock(D, set, "bar")
    place(D, set, 11, 1); place(D, set, 12, 1); place(D, set, 21, 2)
    AB.CdmRows.Refresh(); stub.RunTimers()
    return DUI, AB, set, ess, bars
end

-- A glow piece's color: the solid end of its fade, else its plain color.
local function glowRGB(t)
    local gr = t.__gradient
    if gr then
        local c = (gr[2].a or 0) > (gr[3].a or 0) and gr[2] or gr[3]
        return { c.r, c.g, c.b }
    end
    local v = t.__vertex
    return v and { v[1], v[2], v[3] } or {}
end

-- Tests write settings straight into the set, so they tell the layout it changed
-- as Data's setters do.
local function pass(AB) AB.CdmData.Changed(); AB.CdmRows.Refresh(); stub.RunTimers() end

T.test("cdm effects: a spell's own glow style runs lights round it in place of the ring, sized to it", function()
    local DUI, AB, set, ess = fxWorld()
    local Fx, M, D = AB.CdmEffects, _G.ActionButtonSpellAlertManager, AB.CdmData
    T.eq(D.SetSpellValue(set, 11, "glowStyle", "nope"), false, "only a known style")
    T.eq(D.SetSpellValue(set, 11, "glowStyle", "comet"), true)
    pass(AB)
    M:ShowAlert(ess[1])
    local g = Fx.GlowFrame(ess[1])
    T.truthy(Fx.GlowShown(ess[1]), "glows")
    T.truthy(g.glowDriver and g.glowDriver:IsShown(), "the lights run")
    T.eq(g.glowStyle, "comet")
    T.falsy(g.parts.mid.clip:IsShown(), "no ring under them")
    -- Sized by the icon, and following it when it grows.
    g.glowDriver.__scripts.OnUpdate(g.glowDriver, 0.1)
    local thick, size = g.glowThick, g.glowSize
    T.near(size, math.min(ess[1]:GetWidth(), ess[1]:GetHeight()) * Fx.GLOW_SCALE.size, 1e-6)
    ess[1]:SetSize(ess[1]:GetWidth() * 2, ess[1]:GetHeight() * 2)
    g.glowDriver.__scripts.OnUpdate(g.glowDriver, 0.1)
    T.truthy(g.glowThick > thick and g.glowSize > size, "grows with the icon")
    local _, rel = g.glowDots[1]:GetPoint(1)
    T.eq(rel, ess[1], "round the item")
    -- Another spell keeps the ring.
    M:ShowAlert(ess[2])
    T.truthy(Fx.GlowFrame(ess[2]).parts.mid.clip:IsShown(), "the other spell's ring")
    -- Back to the ring on this one: the lit glow changes on the next pass.
    D.SetSpellValue(set, 11, "glowStyle", "ring")
    pass(AB)
    M:ShowAlert(ess[1])
    T.truthy(g.parts.mid.clip:IsShown(), "the ring again")
    for _ = 1, 5 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.1) end
    T.falsy(g.glowDriver:IsShown(), "the lights stop")
    -- Motion off keeps the ring whatever is picked.
    DUI:Set("general", "motion", false)
    T.eq(Fx.GlowStyle({ glowStyle = "twinkle" }), "ring")
    M:HideAlert(ess[1]); M:HideAlert(ess[2])
end)

T.test("cdm effects: proc glow follows the game's alert on claimed items only", function()
    local DUI, AB, set, ess = fxWorld()
    local Fx, M = AB.CdmEffects, _G.ActionButtonSpellAlertManager
    M:ShowAlert(ess[1])
    T.truthy(Fx.GlowShown(ess[1]), "claimed: glows")
    M:ShowAlert(ess[3])
    T.falsy(Fx.GlowShown(ess[3]), "13 isn't in the layout")
    M:HideAlert(ess[1])
    T.falsy(Fx.GlowShown(ess[1]), "alert gone")
    set.pieces[11].glow = false
    pass(AB)
    M:ShowAlert(ess[1])
    T.falsy(Fx.GlowShown(ess[1]), "glow turned off for this spell")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: the game's alert manager is never hooked", function()
    local hidden
    loadWorld({ actionbars = true, before = function()
        hidden = function() end
        _G.ActionButtonSpellAlertManager = { ShowAlert = function() end, HideAlert = hidden }
    end })
    stub.RunTimers()
    T.eq(_G.ActionButtonSpellAlertManager.HideAlert, hidden, "HideAlert is still the game's own")
end)

T.test("cdm effects: the glow goes when the item is let go, and comes back", function()
    local DUI, AB, set, ess = fxWorld()
    local Fx, M = AB.CdmEffects, _G.ActionButtonSpellAlertManager
    M:ShowAlert(ess[1])
    stub.actionbars.CdmData.SetSwitch("on", false); pass(AB)
    T.falsy(Fx.GlowShown(ess[1]), "released")
    stub.actionbars.CdmData.SetSwitch("on", true); pass(AB)
    T.truthy(Fx.GlowShown(ess[1]), "claimed again while the alert is still up")
end)

T.test("cdm effects: own size changes only that icon; the chain closes around it", function()
    local DUI, AB, set, ess, bars = fxWorld()
    T.eq(ess[1]:GetWidth(), 36)
    set.pieces[11].size = 20
    set.pieces[21].size = 20
    pass(AB)
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.eq(ess[1]:GetWidth(), 20); T.eq(ess[1]:GetHeight(), 20)
    T.eq(ess[2]:GetWidth(), 36, "the others keep the block's size")
    local p, rel, rp = ess[1]:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, frameOf(11)); T.eq(rp, "CENTER")
    T.eq(frameOf(11):GetWidth(), 20)
    T.eq(select(4, frameOf(12):GetPoint(1)), 24, "the next one follows its edge")
    T.eq(bars[1]:GetHeight(), 18, "bars have no own size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: hide swipe keeps it off and puts it back on release", function()
    local DUI, AB, set, ess = fxWorld()
    set.pieces[11].noSwipe = true
    pass(AB)
    local cd = ess[1].Cooldown
    T.eq(cd.__swipe, false)
    cd:SetDrawSwipe(true)                       -- the game turns it back on
    T.eq(cd.__swipe, false, "forced back off")
    T.isnil(ess[2].Cooldown.__swipe, "others untouched")
    stub.actionbars.CdmData.SetSwitch("on", false)
    unplace(AB.CdmData, set, 11); pass(AB)
    T.eq(cd.__swipe, true, "restored")
    cd:SetDrawSwipe(false); cd:SetDrawSwipe(true)
    T.eq(cd.__swipe, true, "the hook stays out of the way once released")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Spell 100 + cooldownID behind each icon. cds / charges are what the game reports.
local function withCooldowns(ess)
    local cds, charges = {}, {}
    _G.C_Spell = _G.C_Spell or {}
    C_Spell.GetSpellCooldown = function(sid) return cds[sid] end
    C_Spell.GetSpellCharges = function(sid) return charges[sid] end
    for _, item in ipairs(ess) do item.cooldownInfo = { spellID = 100 + item.cooldownID } end
    return cds, charges
end

-- Cooldown events are handled once, the frame after a burst.
local function cdEvent() stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers() end

T.test("cdm text: numbers off and sized, count spot, low-time color; back on release", function()
    local DUI, AB, set, ess = fxWorld()
    withCooldowns(ess)
    local CD, D = AB.Cooldowns, AB.CdmData
    -- A color curve and a duration the client evaluates, with 2 s left.
    local made = {}
    _G.C_CurveUtil = { CreateColorCurve = function()
        local c = { points = {} }
        function c:SetType() end
        function c:AddPoint(x, col) self.points[#self.points + 1] = { x, col } end
        made[#made + 1] = c
        return c
    end }
    C_Spell.GetSpellCooldownDuration = function()
        return { EvaluateRemainingDuration = function(_, curve)
            local pick = curve.points[1][2]
            for _, p in ipairs(curve.points) do if p[1] <= 2 then pick = p[2] end end
            return { GetRGBA = function() return pick.r, pick.g, pick.b, pick.a end }
        end }
    end
    local item = ess[1]
    local cd = item.Cooldown
    local fs = item:CreateFontString()
    cd.GetCountdownFontString = function() return fs end
    cd.SetHideCountdownNumbers = function(self, v) self.__hide = v end
    item.ChargeCount = { Current = item:CreateFontString() }
    T.truthy(D.SetLook(set, 11, "cdNumbers", false))
    T.truthy(D.SetLook(set, 11, "countSpot", "tl"))
    T.truthy(D.SetLook(set, 11, "countSize", 15))
    T.falsy(D.SetLook(set, 11, "countSpot", "moon"), "a bad spot is refused")
    pass(AB)
    T.eq(cd.__hide, true, "numbers off")
    T.eq(select(1, item.ChargeCount.Current:GetPoint(1)), "TOPLEFT", "count at its spot")
    D.SetLook(set, 11, "cdNumbers", true)
    D.SetLook(set, 11, "cdSize", 20)
    D.SetLook(set, 11, "low", true)
    D.SetLook(set, 11, "lowAt", 3)
    D.SetLook(set, 11, "lowColor", { 0, 1, 0 })
    pass(AB)
    T.eq(cd.__hide, false, "numbers on")
    T.eq(select(2, fs:GetFont()), 20, "numbers size")
    T.rgb({ fs:GetTextColor() }, { 0, 1, 0 }, "2 s left: the low color")
    T.eq(select(2, item.ChargeCount.Current:GetFont()), 15)
    stub.actionbars.CdmData.SetSwitch("on", false)
    unplace(D, set, 11); pass(AB)
    T.isnil(CD.TextOf(item), "let go")
    T.eq(select(1, item.ChargeCount.Current:GetPoint(1)), "BOTTOMRIGHT", "count back at the corner")
    _G.C_CurveUtil = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm text: the low-time ticker sleeps with nothing counting and wakes on a cooldown", function()
    local DUI, AB, set, ess = fxWorld()
    withCooldowns(ess)
    local CD, D = AB.Cooldowns, AB.CdmData
    _G.C_CurveUtil = { CreateColorCurve = function()
        local c = { points = {} }
        function c:SetType() end
        function c:AddPoint(x, col) self.points[#self.points + 1] = { x, col } end
        return c
    end }
    local asked = 0
    C_Spell.GetSpellCooldownDuration = function()
        asked = asked + 1
        return { EvaluateRemainingDuration = function(_, curve)
            local pick = curve.points[1][2]
            return { GetRGBA = function() return pick.r, pick.g, pick.b, pick.a end }
        end }
    end
    local item = ess[1]
    local fs = item:CreateFontString()
    item.Cooldown.GetCountdownFontString = function() return fs end
    item.Cooldown:Hide()
    D.SetLook(set, 11, "low", true)
    D.SetLook(set, 11, "lowColor", { 0, 1, 0 })
    pass(AB)
    T.truthy(CD.LowTicking(), "on while the color is used")
    for _ = 1, CD.LOW_IDLE do stub.RunTickers() end
    T.falsy(CD.LowTicking(), "no cooldown counting: it stops")
    T.rgb({ fs:GetTextColor() }, AB.Skin.LookFor("cdm").cooldownTextColor, "left in the plain color")
    asked = 0
    stub.RunTickers()
    T.eq(asked, 0, "nothing asked while asleep")
    item.Cooldown:Show()
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    T.truthy(CD.LowTicking(), "a cooldown wakes it")
    T.rgb({ fs:GetTextColor() }, { 0, 1, 0 }, "painted at once")
    for _ = 1, CD.LOW_IDLE + 1 do stub.RunTickers() end
    T.truthy(CD.LowTicking(), "keeps going while it counts")
    _G.C_CurveUtil = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm text: an icon's numbers and stacks colors; unset = the action bars' colors", function()
    local DUI, AB, set, ess = fxWorld()
    withCooldowns(ess)
    local D, Card = AB.CdmData, AB.CdmCard
    local item = ess[1]
    local fs = item:CreateFontString()
    item.Cooldown.GetCountdownFontString = function() return fs end
    item.ChargeCount = { Current = item:CreateFontString() }
    T.truthy(D.SetLook(set, 11, "cdColor", { 0, 0, 1 }))
    T.truthy(D.SetLook(set, 11, "countColor", { 1, 0, 0 }))
    pass(AB)
    T.rgb({ fs:GetTextColor() }, { 0, 0, 1 }, "numbers color")
    T.rgb({ item.ChargeCount.Current:GetTextColor() }, { 1, 0, 0 }, "stacks color")
    set.pieces[11].look = nil
    pass(AB)
    T.rgb({ fs:GetTextColor() }, AB.Skin.LookFor("cdm").cooldownTextColor, "back to the action bars' color")
    T.rgb({ item.ChargeCount.Current:GetTextColor() }, AB.Skin.COUNT_COLOR)
    T.rgb(Card.Fallback("cdColor"), AB.Skin.LookFor("cdm").cooldownTextColor, "the card shows it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: hide global cooldown keeps the swipe off only on the GCD; reverse swipe", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local cd = ess[1].Cooldown
    cd.SetReverse = function(self, on) self.__reverse = on end
    set.pieces[11].noGcd = true
    set.pieces[11].reverse = true
    cds[111] = { isOnGCD = true, duration = 1.5 }
    pass(AB)
    T.eq(cd.__swipe, false, "the GCD: no swipe")
    T.eq(cd.__reverse, true, "reversed")
    cds[111] = { isOnGCD = false, duration = 8 }
    cd:SetDrawSwipe(true)                       -- the game's update, now with its own cooldown
    T.eq(cd.__swipe, true, "its own cooldown: swipe")
    cds[111] = { isOnGCD = stub.Secret(true), duration = stub.Secret(1.5) }
    cd:SetDrawSwipe(true)
    T.eq(cd.__swipe, true, "a secret answer shows the swipe")
    cds[111] = { isOnGCD = true, duration = 1.5 }
    cd:SetDrawSwipe(true)
    T.eq(cd.__swipe, false)
    set.pieces[11].noGcd, set.pieces[11].reverse = nil, nil
    pass(AB)
    T.eq(cd.__swipe, true, "off: swipe back")
    T.eq(cd.__reverse, false, "off: not reversed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: gray out follows the cooldown; Game default leaves the game's", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local icon = AB.Cooldowns.IconOf(ess[1])
    set.pieces[11].desat = "grey"
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.truthy(icon:IsDesaturated(), "on cooldown: gray")
    icon:SetDesaturated(false)                  -- the game sets its own
    T.truthy(icon:IsDesaturated(), "ours wins")
    cds[111] = { duration = 0, isOnGCD = false }
    cdEvent()
    T.falsy(icon:IsDesaturated(), "ready: colored")
    cds[111] = { duration = 1.5, isOnGCD = true }
    cdEvent()
    T.falsy(icon:IsDesaturated(), "the global cooldown doesn't count")
    set.pieces[11].desat = "color"
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.falsy(icon:IsDesaturated(), "stay colored")
    set.pieces[11].desat = nil
    pass(AB)
    icon:SetDesaturated(true)
    T.truthy(icon:IsDesaturated(), "Game default: the game's value stands")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: on cooldown fade or hide by alpha, back when ready or let go", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    set.pieces[11].onCd = "fade"; set.pieces[11].cdAlpha = 0.25
    set.pieces[12].onCd = "hide"
    cds[111] = { duration = 8, isOnGCD = false }
    cds[112] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0.25)
    T.eq(ess[2]:GetAlpha(), 0, "hidden by alpha")
    T.truthy(ess[2]:IsShown(), "never Hide()")
    cds[111] = { duration = 0 }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 1, "ready")
    stub.actionbars.CdmData.SetSwitch("on", false)
    unplace(AB.CdmData, set, 12); pass(AB)
    T.eq(ess[2]:GetAlpha(), 1, "let go: full again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player only wanted to see them while on cooldown.
T.test("cdm effects: Buff only rests old cooldown settings its card no longer shows", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    set.pieces[11].onCd = "hide"
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "a cooldown: hidden")
    AB.CdmOwn.BuffOnly = function() return true end
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 1, "Buff only: stays shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: while ready fade or hide by alpha, back on cooldown; the global cooldown counts as ready", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    set.pieces[11].onReady = "hide"
    set.pieces[12].onReady = "fade"; set.pieces[12].cdAlpha = 0.25
    cds[111] = { duration = 0 }
    cds[112] = { duration = 0 }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "ready: hidden")
    T.eq(ess[2]:GetAlpha(), 0.25, "ready: faded")
    T.truthy(ess[1]:IsShown(), "never Hide()")
    cds[111] = { duration = 1.5, isOnGCD = true }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 0, "the global cooldown doesn't bring it up")
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 1, "on cooldown: shown")
    set.pieces[11].onCd = "fade"; set.pieces[11].cdAlpha = 0.5
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0.5, "both set: on cooldown follows On cooldown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Searing Totem has no cooldown, so When ready Hide hid it for good. The game's
-- icon times the totem, so a totem that's down counts as its cooldown.
T.test("cdm effects: When ready Hide shows a totem only while it's down", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    -- 111 is a totem with no buff (CdmCustom.TOTEMS, fire slot); 112 a totem that
    -- isn't on that list, which keeps its own cooldown.
    stub.SetUnits({ player = { class = "SHAMAN" } })
    local class = "SHAMAN"
    local realSpells = AB.CdmSpells[class]
    AB.CdmSpells[class] = { { 111, aura = true }, { 112, aura = true } }
    AB.CdmCustom.TOTEMS[111] = 1
    AB.CdmCustom.Forget()
    -- The game's item data, and whether slot 1 holds a totem (GetTotemDuration
    -- returns nothing once it's gone).
    local totem
    ess[1].GetTotemData = function() return totem end
    ess[2].GetTotemData = function() return totem end
    set.pieces[12].onReady = "hide"
    cds[112] = { duration = 0 }
    local function stand(on) stub.totems[1] = on and { spell = 111, duration = {} } or nil end
    set.pieces[11].onReady = "hide"
    cds[111] = { duration = 0 }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "no totem: hidden")
    totem = { slot = 1, expirationTime = GetTime() + 60, duration = 60, modRate = 1 }; stand(true)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 1); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "totem down: shown, the game's icon timing it")
    T.eq(ess[2]:GetAlpha(), 0, "a totem not on the list: its own cooldown (ready), as before")
    -- Right-clicked away: the item keeps the emptied slot as its totem.
    totem = { slot = 1, spellID = 0, expirationTime = 0, duration = 0, modRate = 1 }; stand(false)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 1); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "destroyed: hidden though the item still holds the slot")
    -- Run out: no event, the next look finds the slot empty.
    totem = { slot = 1, expirationTime = GetTime() + 60, duration = 60, modRate = 1 }; stand(true)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 1); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "down again")
    stand(false)
    stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "ran out with no event: hidden at the next look")
    -- In a fight the item's totem data is a secret table: no error, keeps its state.
    totem = { slot = 1, expirationTime = GetTime() + 60, duration = 60, modRate = 1 }; stand(true)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 1); stub.RunTimers()
    totem = stub.Secret({ slot = 1 })
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 1); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "secret totem data: stays as it was")
    ess[1].GetTotemData, ess[2].GetTotemData = nil, nil
    AB.CdmCustom.TOTEMS[111] = nil
    AB.CdmSpells[class] = realSpells
    AB.CdmCustom.Forget()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- From a priest using Grow from Middle: cooldowns set to hide while ready kept
-- their spot, so the group never re-centered.
T.test("cdm effects: a cooldown hidden while ready slides out of its group, back on cooldown", function()
    local DUI, AB, set, ess = fxWorld()
    local D = AB.CdmData
    DUI.DB.General().motion = false
    local cds = withCooldowns(ess)
    T.truthy(D.SetChainValue(set, 11, "grow", "center"))
    local full = D.Layout(set)
    local w = full[11].w
    local gap = full[12].x - full[11].x - w
    set.pieces[11].onReady = "hide"
    cds[111] = { duration = 8, isOnGCD = false }
    cds[112] = { duration = 8, isOnGCD = false }
    pass(AB)
    local f2 = pieceFrame(1, 12)
    T.eq(f2.goalX, full[12].x, "on cooldown: in its spot")
    cds[111] = { duration = 0 }
    cdEvent(); stub.RunTimers()
    T.eq(f2.goalX, full[12].x - (w + gap) / 2, "ready and hidden: the rest closes up round the middle")
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent(); stub.RunTimers()
    T.eq(f2.goalX, full[12].x, "on cooldown again: back in its spot")
    -- With slide over off it keeps its spot and only its alpha goes.
    T.truthy(D.SetChainValue(set, 11, "collapse", false))
    cds[111] = { duration = 0 }
    cdEvent(); stub.RunTimers()
    T.eq(f2.goalX, full[12].x, "Slide over off")
    T.eq(ess[1]:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A druid with every form's spells in one group growing from its middle: the ones
-- left out of the form gave up nothing, so the rest sat off to one side.
T.test("cdm effects: a spell left out of the form slides out of its group, Show missing buffs or not", function()
    local DUI, AB, set, ess = fxWorld()
    local D = AB.CdmData
    DUI.DB.General().motion = false
    local cds = withCooldowns(ess)
    cds[111] = { duration = 0 }
    cds[112] = { duration = 0 }
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "DRUID"
    local form = 0
    local spells = { 5487, 768 }
    _G.GetNumShapeshiftForms = function() return #spells end
    _G.GetShapeshiftFormInfo = function(i) return 136000 + i, form == i, true, spells[i] end
    T.truthy(D.SetChainValue(set, 11, "grow", "center"))
    local full = D.Layout(set)
    local w = full[11].w
    local gap = full[12].x - full[11].x - w
    T.truthy(D.SetSpellValue(set, 11, "hideInCat", true))
    pass(AB)
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    local f2 = pieceFrame(1, 12)
    T.eq(f2.goalX, full[12].x, "caster form: in its spot")
    form = 2
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.eq(f2.goalX, full[12].x - (w + gap) / 2, "Cat Form: the rest closes up round the middle")
    T.truthy(D.SetChainValue(set, 11, "always", true))
    pass(AB); stub.RunTimers()
    T.eq(f2.goalX, full[12].x - (w + gap) / 2, "Show missing buffs keeps spots for missing buffs, not for a spell out of its form")
    form = 0
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.eq(f2.goalX, full[12].x, "back in caster form: back in its spot")
    -- The same as bars, stacked: the next one moves up into the spot.
    T.truthy(D.SetShape(set, 11, "bar")); T.truthy(D.SetShape(set, 12, "bar"))
    pass(AB); stub.RunTimers()
    local bars = D.Layout(set)
    local y2 = pieceFrame(1, 12).goalY
    form = 2
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.truthy(pieceFrame(1, 12).goalY ~= y2 or pieceFrame(1, 12).goalX ~= bars[12].x, "a bar out of its form gives its spot up too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- "Not usable: Hide" (which replaced the old "Show when usable") kept its spot,
-- leaving Grow from Middle off-center.
T.test("cdm effects: a cooldown hidden while not usable slides out of its group, back when castable", function()
    local DUI, AB, set, ess = fxWorld()
    local D = AB.CdmData
    DUI.DB.General().motion = false
    local cds = withCooldowns(ess)
    local can = { [111] = true, [112] = true }
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, false end
    T.truthy(D.SetChainValue(set, 11, "grow", "center"))
    local full = D.Layout(set)
    local w = full[11].w
    local gap = full[12].x - full[11].x - w
    set.pieces[11].onUnusable = "hide"
    cds[111] = { duration = 0 }
    cds[112] = { duration = 0 }
    pass(AB)
    local f2 = pieceFrame(1, 12)
    T.eq(f2.goalX, full[12].x, "castable: in its spot")
    can[111] = false
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "not castable: hidden")
    T.eq(f2.goalX, full[12].x - (w + gap) / 2, "not castable: the rest closes up round the middle")
    can[111] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(f2.goalX, full[12].x, "castable again: back in its spot")
    T.eq(ess[1]:GetAlpha(), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Set to hide while ready, every spell showed while wanding.
T.test("cdm effects: a wand shot's lockout counts as ready, a real cooldown under it doesn't", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    C_Spell.IsAutoRepeatSpell = function(id) return id == 5019 end
    _G.UnitRangedDamage = function() return 1.5 end
    set.pieces[11].onReady = "hide"
    set.pieces[12].onReady = "hide"
    cds[111] = { duration = 0 }
    stub.Advance(10)
    cds[112] = { startTime = GetTime() - 1, duration = 8, isOnGCD = false, isActive = true }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "ready: hidden")
    T.eq(ess[2]:GetAlpha(), 1, "on a real cooldown: shown")
    AB.Ping.Shot(5019)
    cds[111] = { startTime = GetTime(), duration = 1.5, isOnGCD = false, isActive = true }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 0, "the wand shot doesn't bring it up")
    T.eq(ess[2]:GetAlpha(), 1, "a cooldown from before the shot stays real")
    stub.Advance(0.5)
    cds[111] = { startTime = GetTime(), duration = 10, isOnGCD = false, isActive = true }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 1, "cast while wanding: a real cooldown shows")
    AB.Ping.lockUntil = 0
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: a Hide out of combat block stays away out of combat when a cooldown changes", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    set.pieces[11].onCd = "fade"; set.pieces[11].cdAlpha = 0.25
    chainOf(set, 1).combat = true
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "away out of combat")
    cds[111] = { duration = 0 }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 0, "ready out of combat: still away")
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 0, "on cooldown out of combat: still away")
    stub.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0.25, "in combat: the fade")
    cds[111] = { duration = 0 }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 1, "in combat, ready")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "away again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: charges count as on cooldown only at zero", function()
    local DUI, AB, set, ess = fxWorld()
    local cds, charges = withCooldowns(ess)
    set.pieces[11].onCd = "fade"
    cds[111] = { duration = 8, isOnGCD = false }
    charges[111] = { currentCharges = 1, maxCharges = 2 }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 1, "a charge left")
    charges[111] = { currentCharges = 0, maxCharges = 2 }
    stub.FireEvent("SPELL_UPDATE_CHARGES"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0.4)
end)

T.test("cdm effects: glow when ready", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.falsy(Fx.GlowShown(ess[1]), "on cooldown")
    cds[111] = { duration = 0 }
    cdEvent()
    T.truthy(Fx.GlowShown(ess[1]), "ready")
end)

T.test("cdm effects: glow when usable (Revenge after a block), off cooldown only, its own color", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local can = {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, false end
    local Fx = AB.CdmEffects
    cds[111] = { duration = 0 }
    pass(AB)
    can[111] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.falsy(Fx.GlowShown(ess[1]), "switch off: no glow")
    set.pieces[11].usableGlow = true
    set.pieces[11].usableGlowColor = { 0, 1, 0 }
    can[111] = false
    pass(AB)
    T.falsy(Fx.GlowShown(ess[1]), "not castable")
    can[111] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.truthy(Fx.GlowShown(ess[1]), "castable: glows")
    local green = 0
    T.deq(glowRGB(AB.CdmEffects.GlowFrame(ess[1]).tex), { 0, 1, 0 }, "the ring in the picked color")
    green = 1
    T.eq(green, 1)
    cds[111] = { duration = 5, isOnGCD = false }
    cdEvent()
    T.falsy(Fx.GlowShown(ess[1]), "on cooldown: off")
    cds[111] = { duration = 0 }
    cdEvent()
    T.truthy(Fx.GlowShown(ess[1]), "ready and castable again")
    C_Spell.IsSpellUsable = function() return stub.Secret(false), false end
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.truthy(Fx.GlowShown(ess[1]), "a secret answer keeps the last one")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Reactive spells like Riposte or Overpower should pop up when usable.
T.test("cdm effects: When not usable Hide hides it until castable (short of power counts), shown when the game won't say", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local can, noPower = {}, {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, noPower[sid] == true end
    set.pieces[11].onUnusable = "hide"
    cds[111] = { duration = 0 }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "ready but not castable (no parry yet): hidden")
    T.falsy(ess[1]:IsMouseEnabled(), "no tooltip over the gap")
    can[111] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "castable: shown at once")
    can[111], noPower[111] = false, true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "only short of rage: still shown")
    noPower[111] = false
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "gone again")
    cds[111] = { duration = 5, isOnGCD = false }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 1, "on cooldown: On cooldown's Show")
    cds[111] = { duration = 0 }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 0, "ready, not castable: hidden")
    C_Spell.IsSpellUsable = function() return stub.Secret(false), stub.Secret(false) end
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "a secret answer: shown, never missing when needed")
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "onUnusable", "fade"), "a value the setter takes")
    T.falsy(AB.CdmData.SetSpellValue(set, 11, "onReady", "usable"), "no longer a When ready pick")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A rogue's Kick shown only when off cooldown and with the energy for it.
T.test("cdm effects: When short of power Hide hides a ready spell until there's power for it", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local can, noPower = {}, {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, noPower[sid] == true end
    set.pieces[11].onShort = "hide"
    cds[111] = { duration = 0 }
    can[111], noPower[111] = false, true
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "ready, short of energy: hidden")
    can[111], noPower[111] = true, false
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "energy back: shown at once")
    can[111], noPower[111] = false, false
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "not usable for another reason: When not usable's Show")
    set.pieces[11].onShort = "fade"; set.pieces[11].cdAlpha = 0.25
    can[111], noPower[111] = false, true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers(); eased(DUI)
    T.eq(ess[1]:GetAlpha(), 0.25, "Fade: to Fade to")
    C_Spell.IsSpellUsable = function() return stub.Secret(false), stub.Secret(true) end
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers(); eased(DUI)
    T.eq(ess[1]:GetAlpha(), 1, "a secret answer: shown")
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "onShort", "hide"), "a value the setter takes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Cat spells only in Cat Form, bear spells only in Bear Form, and warrior stances
-- and rogue stealth the same way.
T.test("cdm effects: a spell left out of a form hides while you're in it, and comes back as you leave", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    cds[111] = { duration = 0 }
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "DRUID"
    local form = 0
    local spells = { 5487, 768 }   -- Bear, Cat
    _G.GetNumShapeshiftForms = function() return #spells end
    _G.GetShapeshiftFormInfo = function(i) return 136000 + i, form == i, true, spells[i] end
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "hideInCat", true), "a value the setter takes")
    T.falsy(AB.CdmData.SetSpellValue(set, 11, "hideInCat", "yes"))
    pass(AB)
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.eq(AB.CdmEffects.FormNow(), "Caster", "no form: caster")
    T.eq(ess[1]:GetAlpha(), 1, "shown out of Cat Form")
    form = 2
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.eq(AB.CdmEffects.FormNow(), "Cat")
    T.eq(ess[1]:GetAlpha(), 0, "in Cat Form: hidden at once")
    form = 1
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.eq(AB.CdmEffects.FormNow(), "Bear", "Bear Form (Dire Bear too: one key)")
    T.eq(ess[1]:GetAlpha(), 1, "back in Bear Form")
    -- A rogue: stealth comes through its own event.
    stub.units.player.class = "ROGUE"
    spells, form = {}, 0
    local stealthed = false
    _G.IsStealthed = function() return stealthed end
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "hideInUnstealthed", true))
    stub.FireEvent("UPDATE_STEALTH"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "out of Stealth: an opener hides")
    stealthed = true
    stub.FireEvent("UPDATE_STEALTH"); stub.RunTimers()
    T.eq(AB.CdmEffects.FormNow(), "Stealth")
    T.eq(ess[1]:GetAlpha(), 1, "in Stealth: shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A stance is no buff, so only this wash says which one you're in.
T.test("cdm effects: the warrior stance you're in is lit, and the light moves with the stance", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    cds[111] = { duration = 0 }
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "WARRIOR"
    local stance = 1
    local spells = { 2457, 71, 2458 }
    _G.GetNumShapeshiftForms = function() return #spells end
    _G.GetShapeshiftFormInfo = function(i) return 132349 + i, stance == i, true, spells[i] end
    ess[1].cooldownInfo.overrideSpellID = 71    -- Defensive Stance
    pass(AB)
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers(); eased(DUI)
    T.eq(AB.CdmEffects.FormNow(), "Battle")
    T.falsy(AB.CdmEffects.StanceShown(ess[1]), "in Battle Stance: Defensive isn't lit")
    stance = 2
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.truthy(AB.CdmEffects.StanceShown(ess[1]), "in Defensive Stance: lit at once")
    eased(DUI)
    stance = 3
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.falsy(AB.CdmEffects.StanceShown(ess[1]), "Berserker: Defensive goes dark")
    stance = 2
    set.pieces[11].activeGlow = false
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.falsy(AB.CdmEffects.StanceShown(ess[1]), "the buff-up color switched off: no wash either")
    T.falsy(AB.CdmEffects.StanceShown(ess[2]), "a spell that isn't a stance never lights")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- On Forever the game says Overpower isn't usable outside Battle Stance even
-- right after a dodge, so a warrior in Defensive or Berserker never saw it light
-- up to swap stances for it.
T.test("cdm effects: Overpower lights up after the target dodges, in any stance", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    cds[111], cds[7384] = { duration = 0 }, { duration = 0 }
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "WARRIOR"
    local stance, gameSays = 3, false
    local spells = { 2457, 71, 2458 }
    _G.GetNumShapeshiftForms = function() return #spells end
    _G.GetShapeshiftFormInfo = function(i) return 132349 + i, stance == i, true, spells[i] end
    C_Spell.IsSpellUsable = function() return gameSays, false end
    ess[1].cooldownInfo.overrideSpellID = 7384
    set.pieces[11].usableGlow = true
    set.pieces[12].usableGlow = true
    local Fx = AB.CdmEffects
    pass(AB)
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.eq(Fx.FormNow(), "Berserker")
    T.falsy(Fx.GlowShown(ess[1]), "no dodge yet")
    stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", stub.Secret(40), 1)
    stub.RunTimers()
    T.falsy(Fx.GlowShown(ess[1]), "a hit isn't a dodge")
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
    stub.RunTimers()
    T.truthy(Fx.GlowShown(ess[1]), "dodged in Berserker Stance: lit")
    T.falsy(Fx.GlowShown(ess[2]), "only Overpower")
    stub.Advance(4); stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.truthy(Fx.GlowShown(ess[1]), "still inside the 5 s")
    stub.Advance(1.1); stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.falsy(Fx.GlowShown(ess[1]), "the window ran out")
    -- A new target: the dodge was the old one's.
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1); stub.RunTimers()
    T.truthy(Fx.GlowShown(ess[1]))
    stub.FireEvent("PLAYER_TARGET_CHANGED"); stub.RunTimers()
    T.falsy(Fx.GlowShown(ess[1]), "another target: gone")
    -- Cast it: spent.
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1); stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 7384); stub.RunTimers()
    T.falsy(Fx.GlowShown(ess[1]), "used: gone")
    -- In Battle Stance the game knows whose dodge it was: its answer stands.
    stance = 1
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, 1); stub.RunTimers()
    T.falsy(Fx.GlowShown(ess[1]), "Battle Stance, the game says no: someone else's dodge")
    gameSays = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.truthy(Fx.GlowShown(ess[1]), "the game says yes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Arcane Shot with every Visibility on Show vanished with no target (not
-- usable, out of range), on and off cooldown.
T.test("cdm effects: every Visibility on Show keeps a spell shown when it isn't usable", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    C_Spell.IsSpellUsable = function() return false, false end
    set.pieces[11].onReady, set.pieces[11].onCd, set.pieces[11].onUnusable = "show", "show", "show"
    cds[111] = { duration = 0 }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 1, "ready, not usable: shown")
    cds[111] = { duration = 5, isOnGCD = false }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 1, "on cooldown, not usable: shown")
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    stub.FireEvent("PLAYER_TARGET_CHANGED"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "after target and usable events: shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Hooked spells went missing in play for a hunter, and players have no dev
-- tools, so /dui cdm report saves one line per placed spell.
T.test("cdm report: /dui cdm report saves each placed spell's state in the settings file", function()
    local DUI, AB, set, ess = fxWorld()
    DaylightUIDB.cdmWhy = nil
    DUI.RunCommand("cdm report")
    local lines = DaylightUIDB.cdmWhy
    T.truthy(type(lines) == "table" and lines[1]:find("set 1", 1, true), tostring(lines and lines[1]))
    local all = table.concat(lines, "\n")
    T.truthy(all:find("11: icon, track nil, slide true, keep false, drawn game", 1, true), all)
    T.truthy(all:find("auras readable true", 1, true), all)
    T.truthy(all:find("EssentialCooldownViewer shown true", 1, true), "each of the game's rows, to tell a hidden buff row: " .. all)
    T.truthy(all:find("buffs switched on 0", 1, true), all)
    T.truthy(all:find("12: icon on 11 right", 1, true), all)
    T.truthy(all:find("in its piece held", 1, true), all)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Overpower looked ready all the time, and "Only when usable" sitting under
-- "When ready" was confusing.
T.test("cdm effects: an icon you can't cast dims like the game's own, blue when only short of power", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local can, noPower = {}, {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, noPower[sid] == true end
    cds[111] = { duration = 0 }
    pass(AB)
    local r, g, b = ess[1].Icon:GetVertexColor()
    T.eq(r, 0.4); T.eq(g, 0.4); T.eq(b, 0.4, "ready but can't be cast: dim")
    T.eq(ess[1]:GetAlpha(), 1, "still there: Show is the default")
    noPower[111] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    r, g, b = ess[1].Icon:GetVertexColor()
    T.eq(r, 0.5); T.eq(b, 1, "only short of power: the game's blue")
    noPower[111], can[111] = false, true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    r, g, b = ess[1].Icon:GetVertexColor()
    T.eq(r, 1); T.eq(g, 1); T.eq(b, 1, "castable: full color")
    C_Spell.IsSpellUsable = function() return stub.Secret(false), stub.Secret(false) end
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.eq((ess[1].Icon:GetVertexColor()), 1, "a secret answer: never dimmed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: When not usable Fade uses Fade to, When ready's own Hide still wins when castable", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local can = false
    C_Spell.IsSpellUsable = function() return can, false end
    set.pieces[11].onUnusable = "fade"; set.pieces[11].cdAlpha = 0.25
    cds[111] = { duration = 0 }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0.25, "faded while it can't be cast")
    can = true
    set.pieces[11].onReady = "hide"
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "castable: When ready decides")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: a spell left not usable by a mount follows the mount going away", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local can = false
    C_Spell.IsSpellUsable = function() return can, false end
    set.pieces[11].onUnusable = "hide"
    cds[111] = { duration = 0 }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0, "mounted: hidden")
    can = true
    stub.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "off the mount: shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: a saved Only when usable moves to When not usable, once", function()
    local DUI, AB, set = fxWorld()
    set.pieces[11].onReady = "usable"
    set.usableMoved = nil
    local D = AB.CdmData
    local again = D.Current()
    T.isnil(again.pieces[11].onReady, "gone from When ready")
    T.eq(again.pieces[11].onUnusable, "hide", "the same thing, in its new row")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- What the sound alerts played: the keys handed to Sound.Alert, in order.
local function listenAlerts(DUI)
    local got = {}
    local alert = DUI.Sound.Alert
    DUI.Sound.Alert = function(key) got[#got + 1] = key; alert(key) end
    return got
end

T.test("cdm sounds: a spell's ready sound plays once off a real cooldown, never on the GCD", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "readySound", "kit:353402"))
    local got = listenAlerts(DUI)
    cds[111] = { duration = 0 }
    pass(AB)
    cds[111] = { isOnGCD = true, duration = 1.5 }
    cdEvent()
    cds[111] = { duration = 0 }
    cdEvent()
    T.eq(#got, 0, "the global cooldown is no cooldown")
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    T.eq(#got, 0, "not going on cooldown")
    cds[111] = { duration = 0 }
    cdEvent()
    T.deq(got, { "kit:353402" }, "ready")
    cdEvent()
    T.eq(#got, 1, "once")
    -- A wand shot is a cooldown that isn't a real one (Ping.Shot).
    stub.Advance(1)
    AB.Ping.lockUntil = GetTime() + 3
    cds[111] = { duration = 2, isOnGCD = false }
    cdEvent()
    cds[111] = { duration = 0 }
    cdEvent()
    T.eq(#got, 1, "a wand shot's lockout stays quiet")
    AB.Ping.lockUntil = 0
    -- The frame counts a buff's time on the game's icon, so its end isn't "ready".
    stub.Advance(1)
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    ess[1].Cooldown:GetScript("OnCooldownDone")(ess[1].Cooldown)
    T.eq(#got, 1, "still on cooldown: quiet")
    cdEvent()
    cds[111] = { duration = 0 }
    ess[1].Cooldown:GetScript("OnCooldownDone")(ess[1].Cooldown)
    T.eq(#got, 2, "and the real end sounds")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm sounds: under restrictions your own cast and the frame's end say ready", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    _G.GetSpellBaseCooldown = function() return 30000 end
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "readySound", "dui:quest"))
    local got = listenAlerts(DUI)
    cds[111] = { duration = 0 }
    pass(AB)
    cds[111] = { duration = stub.Secret(8), isOnGCD = stub.Secret(false) }
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 111); stub.RunTimers()
    local done = ess[1].Cooldown:GetScript("OnCooldownDone")
    stub.Advance(1.5)
    done(ess[1].Cooldown)
    T.eq(#got, 0, "the GCD's end")
    stub.Advance(30)
    done(ess[1].Cooldown)
    T.deq(got, { "dui:quest" }, "the cooldown's end")
    done(ess[1].Cooldown)
    T.eq(#got, 1, "once")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Wanding set off other spells' sounds. In a fight a cooldown only says that it
-- runs (isActive); its start and length are secret.
T.test("cdm sounds: wanding in a fight sets off no spell's sound and shows no hidden spell", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    C_Spell.IsAutoRepeatSpell = function(id) return id == 5019 end
    C_Spell.IsSpellUsable = function() return true, false end
    _G.UnitRangedDamage = function() return 1.5 end
    _G.GetSpellBaseCooldown = function(sid) return sid == 112 and 8000 or 0 end
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "usableSound", "kit:353423"))
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "readySound", "kit:353402"))
    T.truthy(AB.CdmData.SetSpellValue(set, 12, "readySound", "dui:quest"))
    set.pieces[11].onReady = "hide"
    local got = listenAlerts(DUI)
    local function hidden(d) return { startTime = stub.Secret(GetTime()), duration = stub.Secret(d), isOnGCD = false, isActive = true } end
    local function shot()
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-w", 5019)
        cds[111], cds[112] = hidden(1.5), hidden(1.5)
        cdEvent()
    end
    cds[111], cds[112] = { duration = 0 }, { duration = 0 }
    stub.Advance(10)
    pass(AB)
    for _ = 1, 3 do
        shot()
        T.eq(ess[1]:GetAlpha(), 0, "the shot doesn't bring a hidden spell up")
        stub.Advance(1.5)
        cds[111], cds[112] = { duration = 0, isActive = false }, { duration = 0, isActive = false }
        ess[1].Cooldown:GetScript("OnCooldownDone")(ess[1].Cooldown)
        ess[2].Cooldown:GetScript("OnCooldownDone")(ess[2].Cooldown)
        cdEvent()
    end
    T.eq(#got, 0, "three shots: quiet")
    -- A real cooldown cast between shots counts, and its end sounds while wanding.
    shot()
    stub.Advance(0.5)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 112)
    cds[112] = hidden(8)
    cdEvent()
    T.eq(ess[2]:GetAlpha(), 1, "shown on its cooldown")
    stub.Advance(1)
    shot()
    cds[112] = hidden(8)
    cdEvent()
    stub.Advance(7)
    shot()
    cds[112] = hidden(1.5)
    ess[2].Cooldown:GetScript("OnCooldownDone")(ess[2].Cooldown)
    cdEvent()
    T.deq(got, { "dui:quest" }, "its ready sound, once, and nothing else")
    AB.Ping.lockUntil, AB.Ping.shotAt = 0, nil
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm sounds: usable sounds as the condition comes true, not as rage comes back", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local can, noPower = {}, {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, noPower[sid] == true end
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "usableSound", "kit:353423"))
    local got = listenAlerts(DUI)
    cds[111] = { duration = 0 }
    pass(AB)
    local function usableEvent() stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers() end
    can[111] = true
    usableEvent()
    T.deq(got, { "kit:353423" }, "a dodge: Overpower is up")
    usableEvent()
    T.eq(#got, 1, "once")
    stub.Advance(1)
    can[111] = false; noPower[111] = true
    usableEvent()
    can[111] = true; noPower[111] = false
    usableEvent()
    T.eq(#got, 1, "rage coming back isn't a proc")
    can[111] = false
    usableEvent()
    C_Spell.IsSpellUsable = function() return stub.Secret(true), false end
    usableEvent()
    T.eq(#got, 1, "a secret answer changes nothing")
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, noPower[sid] == true end
    cds[111] = { duration = 8, isOnGCD = false }
    can[111] = true
    usableEvent()
    T.eq(#got, 1, "on cooldown: not usable yet")
    cds[111] = { duration = 0 }
    usableEvent()
    T.eq(#got, 2, "off cooldown with the proc still up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm sounds: a game buff item sounds as it shows, even collapsed out of the layout", function()
    local DUI, AB, set, ess, bars = fxWorld()
    T.truthy(AB.CdmData.SetSpellValue(set, 21, "buffSound", "dui:done"))
    local got = listenAlerts(DUI)
    bars[1]:SetIsActive(false)
    pass(AB)
    bars[1]:SetIsActive(true)
    pass(AB)
    T.deq(got, { "dui:done" })
    pass(AB)
    T.eq(#got, 1, "once while it stays up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm sounds: the list, its saved keys and how each kind plays", function()
    local DUI, AB, set = fxWorld()
    local Sound, D = DUI.Sound, AB.CdmData
    T.falsy(D.SetSpellValue(set, 11, "readySound", "nonsense"), "a bad key is refused")
    T.falsy(D.SetSpellValue(set, 11, "readySound", 316447), "so is a bare number")
    T.truthy(D.SetSpellValue(set, 11, "readySound", "kit:316447"))
    T.truthy(D.SetSpellValue(set, 11, "readySound", "none"))
    T.isnil(set.pieces[11].readySound, "none isn't saved")
    _G.CooldownViewerSoundData = { [4] = { { soundKitID = 353402, text = "Synth Bleep" } },
        [3] = { { soundKitID = 316447, text = "Chime Ascending" } } }
    _G.Enum.CooldownViewerSoundCategory = { Short = 4, Instruments = 3 }
    local values, order, titles = Sound.AlertChoices()
    T.eq(order[1], "none")
    T.eq(values["kit:316447"], "Chime Ascending", "the game's own list, read live")
    T.isnil(values["kit:353402"], "Short's kits don't exist on this client: they aren't offered")
    T.truthy(values["dui:quest"], "ours")
    T.eq(order[2], "head:punchy", "the sharp ones first")
    T.eq(values["file:568016"], "Proc", "the game's own proc sound, by its file: its kit is at 0.025 volume")
    T.truthy(titles["head:punchy"])
    T.truthy(titles["head:Instruments"], "headed by category")
    T.isnil(titles["head:Short"])
    for _, k in ipairs(order) do
        T.truthy(titles[k] or Sound.IsAlert(k), "every choice can be saved: " .. k)
    end
    -- Shared media: the library's own silent "None" isn't a second None, and
    -- with nothing else there's no Shared media heading at all.
    local shared = { "None" }
    _G.LibStub = function(name)
        return name == "LibSharedMedia-3.0" and { List = function(_, kind) return kind == "sound" and shared or {} end } or nil
    end
    values, order, titles = Sound.AlertChoices()
    T.isnil(values["lsm:None"])
    T.isnil(titles["head:shared"], "no heading over nothing")
    shared[2] = "Test Horn"
    values, order, titles = Sound.AlertChoices()
    T.eq(values["lsm:Test Horn"], "Test Horn", "another addon's sound is offered")
    T.truthy(titles["head:shared"])
    _G.LibStub = nil
    _G.CooldownViewerSoundData = nil
    -- The game's sound kits play the way the game plays them, with the same call
    -- and sub type (CooldownViewerAlert_PlaySoundAlert, TriggerAlertEvent in
    -- Blizzard_CooldownViewer). In game, PlaySound(kit, "Master") was silent for
    -- kit 353392.
    local kits, files = {}, {}
    _G.C_Sound = { PlaySoundWithOptions = function(p)
        kits[#kits + 1] = { p.soundKitID, p.uiSoundSubType }
        return true, 7
    end }
    _G.PlaySound = function() error("the game's own call comes first") end
    _G.PlaySoundFile = function(file, channel) files[#files + 1] = { file, channel }; return true, 8 end
    DUI.DB.General().sounds = false
    T.eq(Sound.Alert("kit:353402"), 7, "its handle, for the list to cut it off")
    T.eq(Sound.Alert("dui:quest"), 8)
    T.eq(Sound.Alert("file:568016"), 8)
    Sound.Alert("none")
    T.deq(kits, { { 353402, "Gameplay SFX" } }, "soft UI sounds off doesn't silence a fight's alert")
    T.deq(files, { { Sound.FILES.quest, "Master" }, { 568016, "Master" } })
    -- If the game says no, fall back on the plain call. An error is shown, never swallowed.
    local plain = {}
    _G.C_Sound.PlaySoundWithOptions = function() return false end
    _G.PlaySound = function(kit, channel) plain[#plain + 1] = { kit, channel }; return true, 9 end
    T.eq(Sound.Alert("kit:353402"), 9)
    T.deq(plain, { { 353402, "SFX" } })
    _G.C_Sound.PlaySoundWithOptions = function() error("refused") end
    Sound.Alert("kit:353402")
    T.eq(#stub.errors, 1, "shown, not swallowed")
    stub.errors[1] = nil
    _G.C_Sound = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: a light runs across on ready, an own icon dips going on cooldown", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    cds[111] = { duration = 0 }
    pass(AB)
    local swept = 0
    local sweep = Fx.Sweep
    Fx.Sweep = function(item) swept = swept + 1; sweep(item) end
    local dipped = 0
    local dip = Fx.Dip
    Fx.Dip = function(item) dipped = dipped + 1; dip(item) end
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(dipped, 1, "going on cooldown")
    T.eq(swept, 0)
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.05)
    T.truthy(ess[1]:GetWidth() < 36, "out of combat the game's item dips too")
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.eq(ess[1]:GetWidth(), 36, "back to its size")
    pass(AB)
    T.eq(dipped, 1, "no change, nothing again")
    local done = ess[1].Cooldown:GetScript("OnCooldownDone")
    done(ess[1].Cooldown)
    T.eq(swept, 1, "ready: the light runs")
    cds[111] = { duration = 0 }
    pass(AB)
    T.eq(swept, 1, "once, not again on the next read")
    -- in combat the game's item doesn't dip
    stub.EnterCombat()
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(dipped, 2)
    T.eq(ess[1]:GetWidth(), 36, "the game's item keeps its size in a fight")
    stub.LeaveCombat()
    Fx.Sweep, Fx.Dip = sweep, dip
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: the ready glow uses its own color", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    set.pieces[11].readyGlow = true
    set.pieces[11].readyGlowColor = { 0, 1, 0 }
    set.pieces[11].glowColor = { 1, 0, 0 }
    cds[111] = { duration = 0 }
    pass(AB)
    T.truthy(AB.CdmEffects.GlowShown(ess[1]), "ready")
    local green = 0
    T.deq(glowRGB(AB.CdmEffects.GlowFrame(ess[1]).tex), { 0, 1, 0 }, "the ring in the picked color")
    green = 1
    T.eq(green, 1)
end)

T.test("cdm data: a glow color goes back to the accent, other colors still need one", function()
    local DUI, AB, set = fxWorld()
    local D = AB.CdmData
    for _, key in ipairs({ "glowColor", "readyGlowColor", "usableGlowColor", "missingGlowColor",
                           "upGlowColor", "clipGlowColor" }) do
        T.truthy(D.SetSpellValue(set, 11, key, { 0, 1, 0 }), key .. " takes a color")
        T.deq(set.pieces[11][key], { 0, 1, 0 })
        T.truthy(D.SetSpellValue(set, 11, key, nil), key .. " takes nil")
        T.eq(set.pieces[11][key], nil, key .. " cleared")
    end
    T.eq(D.SetSpellValue(set, 11, "activeColor", nil), false, "not an accent color")
    T.eq(D.SetSpellValue(set, 11, "readyGlowColor", "red"), false, "still checks colors")
end)

T.test("cdm effects: a cleared glow color paints the accent and follows it", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local D = AB.CdmData
    set.pieces[11].readyGlow = true
    cds[111] = { duration = 0 }
    D.SetSpellValue(set, 11, "readyGlowColor", { 0, 1, 0 })
    pass(AB)
    T.deq(glowRGB(AB.CdmEffects.GlowFrame(ess[1]).tex), { 0, 1, 0 }, "picked")
    D.SetSpellValue(set, 11, "readyGlowColor", nil)
    pass(AB)
    local function accent() local r, g, b = DUI.Style.Accent(); return { r, g, b } end
    local got = glowRGB(AB.CdmEffects.GlowFrame(ess[1]).tex)
    for i = 1, 3 do T.near(got[i], accent()[i], 0.001, "the accent again") end
    DUI:Set("General", "accent", "class")
    pass(AB)
    got = glowRGB(AB.CdmEffects.GlowFrame(ess[1]).tex)
    for i = 1, 3 do T.near(got[i], accent()[i], 0.001, "follows a new accent") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: cooldown end and combat end update the state", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true; set.pieces[11].onCd = "fade"
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.falsy(Fx.GlowShown(ess[1]), "on cooldown")
    T.eq(ess[1]:GetAlpha(), 0.4)
    local done = ess[1].Cooldown:GetScript("OnCooldownDone")
    T.eq(type(done), "function", "done hook set")
    done(ess[1].Cooldown)
    T.truthy(Fx.GlowShown(ess[1]), "ready, no event needed")
    T.eq(ess[1]:GetAlpha(), 1)
    -- after combat the state is read again
    cds[111] = { duration = 8, isOnGCD = false }
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.falsy(Fx.GlowShown(ess[1]), "regen refreshes")
    -- a released item's done hook does nothing
    set.pieces[11].readyGlow = nil
    unplace(AB.CdmData, set, 11); pass(AB)
    local alpha = ess[1]:GetAlpha()
    done(ess[1].Cooldown)
    T.eq(ess[1]:GetAlpha(), alpha)
    T.falsy(Fx.GlowShown(ess[1]))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: hidden by cooldown turns the mouse off, back as the game had it when ready", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    set.pieces[12].onCd = "hide"
    cds[112] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(ess[2]:IsMouseMotionEnabled(), false, "no tooltip over the gap")
    pass(AB)
    T.eq(ess[2]:IsMouseMotionEnabled(), false, "next pass keeps it off")
    cds[112] = { duration = 0 }
    cdEvent()
    T.eq(ess[2]:IsMouseMotionEnabled(), true, "its tooltip back when shown")
    T.eq(ess[2]:IsMouseClickEnabled(), false, "and still click-through, as the game makes it")
    -- The game hides its row, so Daylight UI lets its items go: they keep the game's mouse.
    _G.EssentialCooldownViewer:Hide(); pass(AB)
    T.eq(ess[2]:IsMouseClickEnabled(), false, "let go: click-through")
    T.eq(ess[2]:IsMouseMotionEnabled(), true, "with its tooltip")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: active glow off hides the buff swipe, color recolors it", function()
    local DUI, AB, set, ess = fxWorld()
    local cd = ess[1].Cooldown
    -- Record over the method as it is (every icon's is already hooked).
    local hooked = cd.SetSwipeColor
    cd.SetSwipeColor = function(self, r, g, b, a) self.__tint = { r, g, b, a }; return hooked(self, r, g, b, a) end
    set.pieces[11].activeGlow = false
    ess[1].wasSetFromAura = true
    pass(AB)
    T.eq(cd.__tint[4], 0, "buff up: swipe see-through")
    cd:SetSwipeColor(1, 0.95, 0.57, 0.7)          -- the game paints it again
    T.eq(cd.__tint[4], 0, "kept see-through")
    ess[1].wasSetFromAura = false
    cd:SetSwipeColor(0, 0, 0, 0.7)                -- back to a cooldown
    T.eq(cd.__tint[4], stub.actionbars.Skin.SWIPE[4], "cooldown swipe untouched")
    set.pieces[11].activeGlow = nil
    set.pieces[11].activeColor = { 0, 1, 0, 0.5 }
    ess[1].wasSetFromAura = true
    pass(AB)
    T.eq(cd.__tint[2], 1); T.eq(cd.__tint[4], 0.5, "own color")
    set.pieces[11].activeColor = nil
    pass(AB)
    local r, g, b = DUI.Style.Accent()
    T.eq(cd.__tint[1], r); T.eq(cd.__tint[2], g); T.eq(cd.__tint[3], b, "unset: the accent")
    T.eq(cd.__tint[4], 0.7, "at the game's opacity")
    cd:SetSwipeColor(1, 0.95, 0.57, 0.7)          -- the game paints its yellow again
    T.eq(cd.__tint[3], b, "kept in the accent")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: a saved copy of the old yellow buff swipe goes once", function()
    local DUI, AB, set = fxWorld()
    set.pieces[11].activeColor = { 1, 0.95, 0.57, 0.7 }
    set.pieces[12].activeColor = { 0, 1, 0, 0.5 }
    set.activeAccent = nil
    local again = AB.CdmData.Current()
    T.isnil(again.pieces[11].activeColor, "old default dropped")
    T.eq(again.pieces[12].activeColor[2], 1, "a real pick stays")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: a failing SetDrawSwipe does not lock the hooks", function()
    local DUI, AB, set, ess = fxWorld()
    set.pieces[11].noSwipe = true
    local cd = ess[1].Cooldown
    cd.SetDrawSwipe = function() error("boom") end
    pass(AB)
    cd.SetDrawSwipe = function(self, on) self.__swipe = on end
    set.pieces[11].noSwipe = false
    pass(AB)
    T.eq(cd.__swipe, true, "swipe restored, guard was reset")
end)

T.test("cdm effects: a secret cooldown is skipped and keeps the last state", function()
    local DUI, AB, set, ess = fxWorld()
    local cds, charges = withCooldowns(ess)
    set.pieces[11].onCd = "fade"
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0.4)
    stub.combat = true
    cds[111] = { duration = stub.Secret(0), isOnGCD = stub.Secret(false) }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 0.4, "kept")
    charges[111] = { currentCharges = stub.Secret(1), maxCharges = 2 }
    stub.FireEvent("SPELL_UPDATE_CHARGES"); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0.4, "kept")
    ess[1].cooldownInfo = { spellID = stub.Secret(111) }
    cdEvent()
    T.eq(ess[1]:GetAlpha(), 0.4, "a secret spell id too")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: switching On cooldown back to show, or letting go, restores alpha", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    set.pieces[11].onCd = "fade"; set.pieces[11].cdAlpha = 0.25
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0.25)
    set.pieces[11].onCd = "show"
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 1, "show: back to full")
    set.pieces[11].onCd = "fade"
    pass(AB)
    T.eq(ess[1]:GetAlpha(), 0.25)
    set.pieces[11].onCd = "show"
    stub.actionbars.CdmData.SetSwitch("on", false)
    unplace(AB.CdmData, set, 11); pass(AB)
    T.eq(ess[1]:GetAlpha(), 1, "let go with the option already show")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's category lists (Essential 0, Utility 1, TrackedBuff 2,
-- TrackedBar 3): known ids, and all ids including unlearned ones.
local function withCategories(known, all)
    _G.Enum.CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
    _G.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function(cat, allow)
            if cat < 0 then error("bad argument #1 to '?' (Usage: local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category [, allowUnlearned]))", 2) end
            return (allow and all or known)[cat] or {}
        end,
    }
end
local function noCategories()
    _G.C_CooldownViewer, _G.Enum.CooldownViewerCategory = nil, nil
end

T.test("cdm own icons: a spell learned later shows on SPELLS_CHANGED, its icon once the game knows it", function()
    local DUI, AB, E, D = editorWorld()
    local known = { [0] = { 11, 12 } }
    withCategories(known, { [0] = { 11, 12, 14 } })
    local info = false
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return info and { spellID = 100 + id } or nil end
    C_Spell.GetSpellTexture = function() return 1234 end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 14, 1, 1)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.isnil(AB.CdmOwn.Frame(14), "not known yet")
    known[0] = { 11, 12, 14 }
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    local f = AB.CdmOwn.Frame(14)
    T.truthy(f and f:IsShown(), "shows once learned")
    T.isnil(f.cooldownInfo.spellID, "the game has no info yet")
    info = true
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.eq(f.cooldownInfo.spellID, 114, "asked again")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- In combat the spell list isn't kept (ids may be secret), so a layout pass
-- reads it once and hands it to every piece.
T.test("cdm own icons: a pass in combat reads the game's spell list once", function()
    local DUI, AB, E, D = editorWorld()
    withCategories({ [0] = { 11, 12, 14, 15 }, [2] = { 41 } }, { [0] = { 11, 12, 14, 15 }, [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellTexture = function() return 1234 end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 14, 1, 1); place(D, set, 15, 1, 2); place(D, set, 41, 1, 3)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local reads, get = 0, _G.C_CooldownViewer.GetCooldownViewerCategorySet
    _G.C_CooldownViewer.GetCooldownViewerCategorySet = function(cat, allow)
        if cat == 0 then reads = reads + 1 end
        return get(cat, allow)
    end
    stub.combat = true
    AB.CdmOwn.Forget()
    AB.CdmRows.Update()
    stub.combat = false
    T.truthy(AB.CdmOwn.Frame(14):IsShown(), "still drawn")
    T.eq(reads, 1, "one read of the list for the whole pass")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A pass runs on every aura change in a fight. A piece's block comes from its saved
-- settings alone, so making it again each pass was most of the pass's garbage.
T.test("cdm rows: passes reuse each piece's block until the layout changes", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    local b = R.BlockOf(ess[1])
    T.truthy(b, "the item sits in its piece's block")
    local made, real = 0, D.PieceBlock
    D.PieceBlock = function(...) made = made + 1; return real(...) end
    stub.combat = true
    for _ = 1, 5 do R.Update() end
    T.eq(made, 0, "no new blocks while nothing changed")
    T.truthy(R.BlockOf(ess[1]) == b, "the same block")
    D.SetLook(set, 11, "size", 44)
    R.Update()
    T.truthy(made > 0, "a layout change makes them again")
    T.eq(R.BlockOf(ess[1]).size, 44)
    stub.combat = false
    D.PieceBlock = real
    -- The text look worked out from a block is kept with it, until the bars' look changes.
    local CD, block = AB.Cooldowns, R.BlockOf(ess[1])
    T.truthy(CD.TextLook(block) == CD.TextLook(block), "kept")
    DUI:Set("ActionBars", "look.countSize", 17); stub.RunTimers()
    T.eq(CD.TextLook(block).countSize, 17, "the bars' new count size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's info call makes a new table each time; passes in a fight asked it
-- thousands of times a minute, so each id is read once until spells change.
T.test("cdm info: each cooldown id is read once until the game's spells change", function()
    local DUI, AB, E, D = editorWorld()
    withCategories({ [0] = { 11, 12, 14, 15 }, [2] = { 41 } }, { [0] = { 11, 12, 14, 15 }, [2] = { 41 } })
    local reads, spell = 0, 114
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        reads = reads + 1
        return { spellID = id == 14 and spell or 100 + id }
    end
    C_Spell.GetSpellTexture = function() return 1234 end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 14, 1, 1); place(D, set, 15, 1, 2); place(D, set, 41, 1, 3)
    AB.CdmRows.Refresh(); stub.RunTimers()
    reads = 0
    for _ = 1, 5 do AB.CdmRows.Update() end
    T.eq(reads, 0, "passes reuse what was read")
    T.eq(AB.CdmOwn.SpellOf(14), 114)
    spell = 214
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.eq(AB.CdmOwn.SpellOf(14), 214, "read again once spells change")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm own icons: a placed known spell gets our frame with a cooldown, auras don't, release hides it", function()
    local DUI, AB, E, D = editorWorld()
    withCategories({ [0] = { 11, 12, 14 }, [2] = { 41 } }, { [0] = { 11, 12, 14 }, [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local calls, set = 0, D.Current()
    C_Spell.GetSpellCooldownDuration = function() calls = calls + 1; return {} end
    C_Spell.GetSpellTexture = function() return 1234 end
    addBlock(D, set, "icon")
    place(D, set, 14, 1, 1)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local f = AB.CdmOwn.Frame(14)
    T.truthy(f and f:IsShown(), "own frame shown")
    T.eq(f:GetParent(), frameOf(14), "inside its piece frame")
    local swipes = 0
    f.Cooldown.SetCooldownFromDurationObject = function() swipes = swipes + 1 end
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers()
    T.truthy(swipes >= 1, "cooldown swipe set")
    T.truthy(calls >= 1)
    place(D, set, 41, 1, 2)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.isnil(AB.CdmOwn.Frame(41), "aura ids get no own frame")
    place(D, set, 13, 1, 3); place(D, set, 99, 1, 4)
    if T.dev then
        devCdm(DUI, "why")
        T.truthy(stub.ChatContains("our own icon, shown"), "why: the own icon")
        T.truthy(stub.ChatContains("not known"), "why: an unknown spell")
    end
    unplace(D, set, 13); unplace(D, set, 99)
    unplace(D, set, 14)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(f:IsShown(), "hidden once unplaced")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Aura spells the game doesn't display, with the game's aura container in a holder.
local function auraWorld(selfAura, buffIcons)
    local DUI, AB, E, D, ess, bars, icons = editorWorld(buffIcons)
    withCategories({ [2] = { 41, 42, 43 } }, { [2] = { 41, 42, 43 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = selfAura, linkedSpellIDs = id == 42 and { 900 } or nil }
    end
    C_Spell.GetSpellName = function(sid) return (sid == 141 or sid == 142 or sid == 900) and "Rend" or ("Spell" .. sid) end
    C_Spell.GetSpellTexture = function() return 1234 end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 41, 1, 1)
    return DUI, AB, E, D, set, ess, bars, icons
end

-- selfAura false doesn't mean "on the target": Battle Shout says false because
-- it reaches the party. The game looks on you, then your target, whatever it says
-- (scanUnits in CooldownViewerItemData.lua), and so does the addon.
T.test("cdm auras: a placed aura spell gets a holder watching you, then your target", function()
    local DUI, AB, E, D, set = auraWorld(false)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.truthy(h and h:IsShown(), "holder shown")
    T.eq(h:GetParent(), frameOf(41), "inside its piece frame")
    T.eq(#h.containers, 2)
    T.eq(h.containers[1].unit, "player", "you first (Battle Shout)")
    T.eq(h.containers[1].c.__groups.a.filter, "HELPFUL")
    local k = h.containers[2]
    T.eq(k.unit, "target"); T.eq(k.c.__unit, "target")
    local g = k.c.__groups.a
    T.eq(g.filter, "HARMFUL|PLAYER")
    T.deq(g.opts.candidateFilters.includeSpellIDs, { [141] = true, [142] = true, [900] = true }, "every rank")
    T.truthy(g.button.__cooldown, "cooldown bound")
    T.truthy(g.button.__icon, "icon bound")
    T.eq(g.button:GetWidth(), 36, "the button is sized, not 0x0")
    -- The border goes on a box with its own size and one anchor, with the icon
    -- inside it. A frame laid on the client's button by all its points was 0x0
    -- in game and drew no border.
    T.isnil(DUI.Style.GetShell(g.button), "no shell straight on the client's button")
    local parts = h.parts and h.parts[g.button]
    T.truthy(parts and parts.box and DUI.Style.GetShell(parts.box), "the shell is on our box")
    T.eq(parts.box:GetNumPoints(), 1, "one anchor")
    T.eq(parts.box:GetWidth(), 36, "its own size")
    T.truthy(parts.icon:GetWidth() < 36, "the icon sits inside the border")
    local n = k.c.__refreshes or 0
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(k.c.__refreshes, n + 1, "re-read on a new target")
    T.isnil(AB.CdmOwn.Frame(41), "no own frame")
    unplace(D, set, 41)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(h:IsShown(), "hidden once unplaced")
    place(D, set, 41, 1, 1)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmAuras.Frame(41), h, "same holder")
    T.eq(#h.containers, 2, "same containers")
    if T.dev then devCdm(DUI, "why") end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm sounds: a buff's end sound plays once as it drops, not for a new target, at login or when you die", function()
    local DUI, AB, E, D, set = auraWorld(false)
    plainAuras()
    local Fx = AB.CdmEffects
    T.truthy(D.SetSpellValue(set, 41, "buffEndSound", "kit:316447"))
    AB.CdmRows.Refresh(); stub.RunTimers()
    local got = listenAlerts(DUI)
    local h, p = AB.CdmAuras.Frame(41), set.pieces[41]
    T.truthy(h.wantsUp, "the holder asks whether it's up")
    Fx.BuffMoment(p, h, false)
    Fx.BuffMoment(p, h, true)
    T.eq(#got, 0, "just entered the world")
    stub.Advance(Fx.SETTLE + 1)
    Fx.BuffMoment(p, h, false)
    Fx.BuffMoment(p, h, true)
    T.deq(got, { "kit:316447" }, "heard as it ends")
    Fx.BuffMoment(p, h, true)
    T.eq(#got, 1, "once, not while it stays down")
    Fx.BuffMoment(p, h, false)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    Fx.BuffMoment(p, h, true)
    T.eq(#got, 1, "a new target's debuff leaving view didn't end")
    stub.Advance(1)
    Fx.BuffMoment(p, h, false)
    local dead = _G.UnitIsDeadOrGhost
    _G.UnitIsDeadOrGhost = function() return true end
    Fx.BuffMoment(p, h, true)
    _G.UnitIsDeadOrGhost = dead
    T.eq(#got, 1, "dying clears every buff: no sound")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The client writes the stacks into the count text as it takes it, so a text
-- with no font yet errored and the icon never showed its stacks.
T.test("cdm auras: the stack count has a font before the client takes it", function()
    local DUI, AB = auraWorld(false)
    local errs = {}
    local onError = DUI.SafeCall
    DUI.SafeCall = function(fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then errs[#errs + 1] = tostring(err) end
        return ok
    end
    stub.FontRule = true
    local ok, err = pcall(function() AB.CdmRows.Refresh(); stub.RunTimers() end)
    stub.FontRule, DUI.SafeCall = nil, onError
    T.truthy(ok, tostring(err))
    T.eq(#errs, 0, tostring(errs[1]))
    local h = AB.CdmAuras.Frame(41)
    local btn = h and h.containers[1].c.__groups.a.button
    T.truthy(btn and btn.__count, "the client draws the stacks")
end)

T.test("cdm auras: a self aura watches the player's buffs", function()
    local DUI, AB = auraWorld(true)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.eq(#h.containers, 1)
    T.eq(h.containers[1].unit, "player")
    T.eq(h.containers[1].c.__groups.a.filter, "HELPFUL")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm auras: an unknown aura kind gets both containers", function()
    local DUI, AB = auraWorld(nil)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(#AB.CdmAuras.Frame(41).containers, 2)
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm auras: no aura container in the client is survived and reported", function()
    local DUI, AB = auraWorld(false)
    stub.noAuraContainer = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.truthy(h.err, "error kept")
    if T.dev then T.truthy(devCdm(DUI, "why").AuraWhy(41):find("container failed", 1, true)) end
    stub.noAuraContainer = false
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Block options: "Hide out of combat" and "Show missing buffs".
T.test("cdm block options: a chain reads as off for only in combat and always show", function()
    local DUI, AB, E, D = editorWorld()
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    local b = D.PieceBlock(set, 11)
    T.eq(b.combat, false); T.eq(b.always, false); T.eq(b.collapse, true)
    D.Chain(set, 11).combat = true
    T.eq(D.PieceBlock(set, 11).combat, true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm block options: only in combat is alpha, out of combat, for every kind of item", function()
    local DUI, AB, E, D, set, ess = auraWorld(false)
    withCategories({ [0] = { 11, 14 }, [2] = { 41 } }, { [0] = { 11, 14 }, [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, selfAura = false } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    place(D, set, 11, 1, 2); place(D, set, 14, 1, 3)
    chainOf(set, 1).combat = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.eq(h:GetAlpha(), 0, "holder hidden out of combat")
    T.eq(ess[1]:GetAlpha(), 0, "game item hidden out of combat")
    stub.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED"); stub.RunTimers()
    T.eq(h:GetAlpha(), 1, "holder back in combat")
    T.eq(ess[1]:GetAlpha(), 1, "game item back in combat")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED"); stub.RunTimers()
    T.eq(h:GetAlpha(), 0); T.eq(ess[1]:GetAlpha(), 0)
    chainOf(set, 1).combat = false
    D.Changed(); AB.CdmRows.Refresh(); stub.RunTimers(); eased(DUI)
    T.eq(AB.CdmOwn.Frame(14):GetAlpha(), 1, "our own icon back when turned off")
    T.eq(h:GetAlpha(), 1, "off: shown out of combat")
    T.eq(ess[1]:GetAlpha(), 1)
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm block options: only with a target, hide while mounted, where: alpha, no layout pass", function()
    local DUI, AB, E, D, set, ess = auraWorld(false)
    withCategories({ [0] = { 11, 14 } }, { [0] = { 11, 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, selfAura = false } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    place(D, set, 11, 1, 2); place(D, set, 14, 1, 3)
    T.truthy(D.SetChainValue(set, 11, "target", true))
    T.falsy(D.SetChainValue(set, 11, "where", "moon"), "a bad place is refused")
    local hadTarget = stub.units.target
    stub.units.target = nil
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "no target: away")
    T.eq(AB.CdmOwn.Frame(14):GetAlpha(), 0, "our own icon too")
    stub.units.target = { name = "Boar", reaction = 2 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(ess[1]:GetAlpha(), 1, "a target: back at once")
    eased(DUI)
    T.eq(AB.CdmOwn.Frame(14):GetAlpha(), 1)
    D.SetChainValue(set, 11, "target", false)
    D.SetChainValue(set, 11, "mounted", true)
    stub.mounted = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "mounted: away")
    stub.mounted = false
    stub.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    T.eq(ess[1]:GetAlpha(), 1, "off the mount: back")
    D.SetChainValue(set, 11, "mounted", false)
    D.SetChainValue(set, 11, "where", "instance")
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "open world: away")
    stub.SetInstance("party")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.eq(ess[1]:GetAlpha(), 1, "in a dungeon: shown")
    stub.SetInstance(nil)
    stub.units.target = hadTarget
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm block options: always show - underlay on holders, placeholders for hidden game buffs", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31 })
    withCategories({ [2] = { 31, 41 } }, { [2] = { 31, 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, selfAura = false } end
    place(D, set, 31, 1, 2)
    icons[1]:SetIsActive(false)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.falsy(h.under:IsShown(), "no grayed icon without Show missing buffs")
    T.isnil(AB.CdmOwn.PlaceholderFrame(31, "icon"), "no placeholder by default")
    chainOf(set, 1).always = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(h.under:IsShown(), "underlay while always")
    local ph = AB.CdmOwn.PlaceholderFrame(31, "icon")
    T.truthy(ph and ph:IsShown(), "placeholder for the hidden buff")
    T.eq(ph:GetParent(), frameOf(31))
    -- Dressed like every other icon in the layout: the border with the icon inside.
    local parts = AB.Cooldowns.Parts(ph)
    T.truthy(parts and parts.shell, "the stand-in icon wears the layout's border")
    T.truthy(ph.Icon:IsDesaturated(), "still grayed")
    icons[1]:SetIsActive(true); stub.RunTimers()
    T.falsy(ph:IsShown(), "game item showing hides its placeholder")
    icons[1]:SetIsActive(false); AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(ph:IsShown(), "back when it hides")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's own aura item only looks on you for HELPFUL|PLAYER
-- (GetTargetAurasFilterString in CooldownViewerItemData.lua, since you're a
-- friend), so it never sees a debuff a spell puts on you, such as Arcane Blast's
-- stack (400573). The addon draws it from your debuffs; the game's item stays
-- out of sight and is never asked.
T.test("cdm rows: the game's buff icon of a spell whose debuff lands on you gives way to ours", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31 })
    stub.SetUnits({ player = { class = "MAGE" } })
    AB.CdmSpells.MAGE = { { 400574, 1239696, aura = true } }
    stub.knownSpells = { [400574] = true }
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 31 and 400574 or 100 + id, selfAura = true } end
    unplace(D, set, 41)
    place(D, set, 31, 1, 1)
    icons[1]:SetIsActive(false)   -- the game's item never finds the debuff
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(31), "aura icon", "drawn by ours")
    T.eq(icons[1]:GetAlpha(), 0, "the game's item out of sight")
    local h = AB.CdmAuras.Frame(31)
    T.truthy(h and h:IsShown(), "our holder shown")
    T.truthy(h.face, "ours draws it (the client's container showed nothing in game)")
    T.truthy(h.ids[400573], "up and down read by the stack's id")
    T.eq(h.face.alphaTo, 0, "down: out of sight")
    -- Hide (Buff missing): up and down are read from your debuffs, never from the
    -- game's hidden item.
    T.truthy(D.SetSpellValue(set, 31, "hideMissing", true))
    stub.auras.player = { HARMFUL = { { spellId = 400573, duration = 18, expirationTime = GetTime() + 18,
        applications = 3, sourceUnit = "player", isHarmful = true, isFromPlayerOrPlayerPet = true } } }
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmAuras.IsUp(h), true, "up: the debuff on you")
    T.eq(h.face.alphaTo, 1, "shown")
    T.eq(h.face.count:GetText(), "3", "its stacks")
    T.truthy(h.face.shownEnd, "its time")
    -- /dui cdm report says what draws it and what's on you.
    local line = table.concat(AB.CdmRows.Why(), "\n")
    T.truthy(line:find("drawn by ours", 1, true), "drawn by ours: " .. line)
    T.truthy(line:find("400573 on you", 1, true), "the stack on you: " .. line)
    -- Gone, so out of sight.
    stub.auras.player = {}
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
    T.eq(h.face.alphaTo, 0, "gone")
    -- In a fight auras can't be read. Your own casts start and stack it, and its
    -- length (18 s, read earlier) ends it.
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 400574); stub.RunTimers()
    T.eq(h.face.alphaTo, 1, "your cast: up")
    T.eq(h.face.count:GetText(), "", "one stack: no number")
    stub.Advance(2)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 400574); stub.RunTimers()
    T.eq(h.face.count:GetText(), "2", "the second cast: 2")
    for i = 1, 4 do stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-x" .. i, 400574) end
    stub.RunTimers()
    T.eq(h.face.count:GetText(), "4", "never past its 4 (the game's data)")
    stub.Advance(17.1); stub.RunTimers()
    T.eq(h.face.alphaTo, 0, "18 s after the first cast (and the game's moment more): gone")
    stub.combat = false
    -- Out of a fight its id finds nothing (it can't be tracked that way in game,
    -- so ArcAuras counts casts too). The casts count, an aura change doesn't take
    -- it down, and dying clears it.
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 400574); stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 400574); stub.RunTimers()
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(h.face.alphaTo, 1, "counted from your casts")
    T.eq(h.face.count:GetText(), "2")
    stub.FireEvent("PLAYER_DEAD"); stub.RunTimers()
    T.eq(h.face.alphaTo, 0, "dying clears it")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A mage pulling with Arcane Blast stacks still up from the last fight: that cast
-- was left to a read of the debuff, but the fight it started hid the debuff first,
-- so the count stayed one short for the whole chain (a player on 1.8.4: 2 on the
-- bar, 3 on the game's debuff). Counted once the fight hides it, icon and bar.
T.test("cdm self debuff: a pull's cast is counted when the fight hides the debuff first, icon and bar", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31 })
    stub.SetUnits({ player = { class = "MAGE" } })
    AB.CdmSpells.MAGE = { { 400574, 1239696, aura = true } }
    stub.knownSpells = { [400574] = true }
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 31 and 400574 or 100 + id, selfAura = true } end
    unplace(D, set, 41)
    place(D, set, 31, 1, 1)
    icons[1]:SetIsActive(false)
    local function stacks(n)
        stub.auras.player = { HARMFUL = { { spellId = 400573, duration = 18, expirationTime = GetTime() + 18,
            applications = n, sourceUnit = "player", isHarmful = true, isFromPlayerOrPlayerPet = true } } }
    end
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 31, "bar") end
        AB.CdmRows.Refresh(); stub.RunTimers()
        local h = AB.CdmAuras.Frame(31)
        if shape == "bar" then h = AB.CdmBars.AuraFrame(31) end
        T.truthy(h and h.face, shape .. ": drawn by ours")
        -- Two stacks up from the last fight, read by id.
        stacks(2)
        stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
        T.eq(h.selfStacks, 2, shape .. ": read")
        -- The pull: the cast goes off while auras can be read, the fight starts
        -- before the third stack is read.
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pull-" .. shape, 400574)
        stub.combat = true
        stacks(3)
        stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
        T.eq(h.selfStacks, 3, shape .. ": the pull's cast counted")
        stub.combat = false
        stub.auras.player = {}
        stub.FireEvent("PLAYER_DEAD"); stub.RunTimers()
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A shaman's Lightning Shield (Buff up Hide, Buff missing Show) never came back
-- when its charges ran out in a fight (a player on 1.8.4): the aura can't be read
-- there, and nothing but the cast says it's up. The game's own cooldown icon of it
-- holds the aura it shows and lets it go the moment the aura ends, fights too
-- (CooldownViewerItemData.lua ClearAuraInstanceInfo), so that says down.
T.test("cdm auras: a buff drawn by ours in place of the game's cooldown icon hears it end in a fight, icon and bar", function()
    local DUI, AB, E, D, ess = editorWorld()
    DUI.DB.General().motion = false
    withCategories({ [1] = { 11, 12 } }, { [1] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, hasAura = true, selfAura = true } end
    _G.GetSpellBaseCooldown = function() return 0 end   -- no cooldown of its own
    C_Spell.GetSpellTexture = function() return 1234 end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1)
    T.truthy(D.SetSpellValue(set, 11, "hideActive", true))
    T.truthy(D.SetSpellValue(set, 11, "missing", true))
    set.pieces[11].track = "buff"      -- Buff only, as the card's Show pins it
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 11, "bar") end
        stub.auras.player = { HELPFUL = { { spellId = 111, duration = 600, expirationTime = GetTime() + 600 } } }
        ess[1]:SetAura(true)
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(AB.CdmRows.DrawnBy(11), shape == "bar" and "aura bar" or "aura icon", shape .. ": drawn by ours")
        local h = shape == "bar" and AB.CdmBars.AuraFrame(11) or AB.CdmAuras.Frame(11)
        T.eq(h.up, true, shape .. ": up")
        stub.EnterCombat()
        stub.auras.player = { HELPFUL = {} }
        ess[1]:SetAura(false)            -- the game's icon let it go
        stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(h.up, false, shape .. ": the charges ran out in the fight: down")
        stub.LeaveCombat()
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game lists a rogue's Venom by its buff (1310703), which nobody learns: the
-- talent that procs it is 1329328. So the game calls it unknown even with the
-- talent, and the tray said "Not known right now" (a player on 1.8.4). Known
-- through the talent, it's drawn by ours, as an icon and as a bar.
T.test("cdm own: a buff a talent procs is known once you have the talent, icon and bar", function()
    local DUI, AB, E, D, set = auraWorld(false)
    stub.SetUnits({ player = { class = "ROGUE" } })
    withCategories({ [2] = {} }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 31 and 1310703 or 100 + id, selfAura = true } end
    stub.knownSpells = {}
    AB.CdmOwn.Forget()
    T.isnil(AB.CdmOwn.Known()[31], "no talent: not known")
    stub.knownSpells = { [1329328] = true }
    stub.FireEvent("PLAYER_TALENT_UPDATE")
    local k = AB.CdmOwn.Known()[31]
    T.truthy(k and k.aura, "the talent: known, a buff")
    unplace(D, set, 41)
    place(D, set, 31, 1, 1)
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 31, "bar") end
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(AB.CdmRows.DrawnBy(31), shape == "bar" and "aura bar" or "aura icon", shape .. ": drawn by ours")
        local h = shape == "bar" and AB.CdmBars.AuraFrame(31) or AB.CdmAuras.Frame(31)
        T.truthy(h and h.ids and h.ids[1310703], shape .. ": watching the buff")
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's buff icon of Bestial Wrath looks on you and your target only, so it
-- never lights up for the buff on your pet. Ours draws it, as an icon and as a bar.
T.test("cdm rows: the game's buff icon of a buff on your pet gives way to ours, icon and bar", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31 })
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "HUNTER" }, pet = { name = "Fang" } })
    AB.CdmSpells.HUNTER = { { 19574, cd = true, aura = true } }
    stub.knownSpells = { [19574] = true }
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 31 and 19574 or 100 + id, selfAura = true } end
    unplace(D, set, 41)
    place(D, set, 31, 1, 1)
    icons[1]:SetIsActive(false)   -- the game's item never finds it
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 31, "bar") end
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(AB.CdmRows.DrawnBy(31), shape == "bar" and "aura bar" or "aura icon", shape .. ": drawn by ours")
        T.eq(icons[1]:GetAlpha(), 0, shape .. ": the game's item out of sight")
        local h = shape == "bar" and AB.CdmBars.AuraFrame(31) or AB.CdmAuras.Frame(31)
        local pet = false
        for _, k in ipairs(h and h.containers or {}) do if k.unit == "pet" then pet = true end end
        T.truthy(pet, shape .. ": watched on your pet")
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's buff icon only finds buffs you cast (HELPFUL|PLAYER), so another
-- warrior's Battle Shout on you never lit it. Ours watches any caster's. A DoT
-- each caster keeps their own of (Rend) stays the game's: only yours counts there.
T.test("cdm rows: a group buff someone else put on you is drawn by ours, icon and bar", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31, 41 })
    plainAuras()
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "WARRIOR" } })
    AB.CdmSpells.WARRIOR = { { 6673, 5242, aura = true }, { 772, 6546, aura = true } }
    stub.knownSpells = { [6673] = true, [772] = true }
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31, 41 } }, { [2] = { 31, 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 31 and 6673 or id == 41 and 772 or 100 + id }
    end
    place(D, set, 31, 1, 1)
    icons[1]:SetIsActive(false)   -- the game's item never finds another warrior's shout
    stub.auras.player = { HELPFUL = { { spellId = 5242, duration = 120, expirationTime = GetTime() + 100,
        sourceUnit = "party1", isFromPlayerOrPlayerPet = false } } }
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 31, "bar") end
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(AB.CdmRows.DrawnBy(31), shape == "bar" and "aura bar" or "aura icon", shape .. ": drawn by ours")
        T.eq(icons[1]:GetAlpha(), 0, shape .. ": the game's item out of sight")
        local h = shape == "bar" and AB.CdmBars.AuraFrame(31) or AB.CdmAuras.Frame(31)
        T.truthy(h and AB.CdmAuras.IsUp(h), shape .. ": the other warrior's shout counts as up")
        T.eq(AB.CdmRows.DrawnBy(41), "game", shape .. ": Rend stays the game's")
    end
    stub.auras.player = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Summon Hawk's hawk is no aura the game's item could find. Ours draws it from
-- your casts, as an icon and as a bar.
T.test("cdm rows: Summon Hawk's hawk is drawn by ours from your casts, icon and bar", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31 })
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "HUNTER" } })
    AB.CdmSpells.HUNTER = { { 1293241, 1293525, cd = true, aura = true } }
    stub.knownSpells = { [1293241] = true }
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 31 and 1293241 or 100 + id, selfAura = true } end
    unplace(D, set, 41)
    place(D, set, 31, 1, 1)
    icons[1]:SetIsActive(false)
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 31, "bar") end
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(AB.CdmRows.DrawnBy(31), shape == "bar" and "aura bar" or "aura icon", shape .. ": drawn by ours")
        T.eq(icons[1]:GetAlpha(), 0, shape .. ": the game's item out of sight")
        local h = shape == "bar" and AB.CdmBars.AuraFrame(31) or AB.CdmAuras.Frame(31)
        T.truthy(h and h.face, shape .. ": our own face")
        T.eq(h.face.alphaTo, 0, shape .. ": no hawk yet")
        stub.combat = true
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "h" .. shape, 1293241); stub.RunTimers()
        T.eq(h.face.alphaTo, 1, shape .. ": a hawk")
        T.truthy(h.face.shownEnd, shape .. ": with its time")
        stub.Advance(18.1); stub.RunTimers()
        T.eq(h.face.alphaTo, 0, shape .. ": gone after 18 s")
        stub.combat = false
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The same stack as a bar: drawn by ours too, with its time running down the bar.
T.test("cdm rows: a spell whose debuff lands on you as a bar is drawn by ours", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31 })
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "MAGE" } })
    AB.CdmSpells.MAGE = { { 400574, 1239696, aura = true } }
    stub.knownSpells = { [400574] = true }
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 31 and 400574 or 100 + id, selfAura = true } end
    unplace(D, set, 41)
    place(D, set, 31, 1, 1)
    set.pieces[31].shape = "bar"
    icons[1]:SetIsActive(false)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(31), "aura bar", "drawn as a bar")
    local h = AB.CdmBars.AuraFrame(31)
    T.truthy(h and h:IsShown(), "our bar shown")
    T.truthy(h.face and h.face.parts, "ours draws the bar (no client container)")
    T.eq(#h.containers, 0, "no client container")
    T.eq(h.face.alphaTo, 0, "down: out of sight")
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 400574); stub.RunTimers()
    T.eq(h.face.alphaTo, 1, "your cast: up")
    T.truthy(h.face.parts.bar.__timer, "the bar runs down its time")
    T.truthy(h.face.shownEnd, "its time")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 400574); stub.RunTimers()
    T.eq(h.face.parts.count:GetText(), "2", "the second cast: 2")
    stub.Advance(18.3); stub.RunTimers()
    T.eq(h.face.alphaTo, 1, "a moment past 18 s it's still on you in game")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 400574); stub.RunTimers()
    T.eq(h.face.parts.count:GetText(), "3", "a cast then adds to the old stack, as in game")
    stub.Advance(AB.CdmAuras.SELF_LATE); stub.RunTimers()
    T.eq(h.face.alphaTo, 0, "gone after its 18 s")
    stub.combat = false
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm block options: always show keeps the gap of a hidden buff; collapse is ignored", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31, 32 })
    withCategories({ [2] = { 31, 32 } }, { [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, selfAura = false } end
    unplace(D, set, 41)
    place(D, set, 31, 1, 1); place(D, set, 32, 1, 2)
    icons[1]:SetIsActive(false)
    chainOf(set, 1).collapse = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.isnil(AB.CdmOwn.PlaceholderFrame(31, "icon"), "collapsed: no slot for the hidden one")
    chainOf(set, 1).always = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    local ph = AB.CdmOwn.PlaceholderFrame(31, "icon")
    T.truthy(ph and ph:IsShown(), "the hidden one holds a slot with always on")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm block options: always show gives a hidden game bar an empty bar of ours", function()
    local DUI, AB, E, D, ess, bars = editorWorld()
    withCategories({ [3] = { 21 } }, { [3] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellName = function(sid) return "Battle Shout" end
    local set = D.Current()
    addBlock(D, set, "bar"); place(D, set, 21, 1, 1)
    chainOf(set, 1).always = true
    bars[1]:SetIsActive(false)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local ph = AB.CdmOwn.PlaceholderFrame(21, "bar")
    T.truthy(ph and ph:IsShown(), "empty bar shown")
    T.eq(ph.Bar:GetValue(), 0)
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm block options: flash when inactive pulses the empty bar until the buff is back", function()
    local DUI, AB, E, D, ess, bars = editorWorld()
    withCategories({ [3] = { 21 } }, { [3] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local set = D.Current()
    addBlock(D, set, "bar"); place(D, set, 21, 1, 1)
    chainOf(set, 1).always = true
    bars[1]:SetIsActive(false)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local ph = AB.CdmOwn.PlaceholderFrame(21, "bar")
    T.falsy(AB.CdmEffects.Flashing(ph), "off by default")
    set.pieces[21].inactiveFlash = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(AB.CdmEffects.Flashing(ph), "flashing while down")
    stub.RunOnUpdate(AB.CdmEffects.flashDriver, 0.3)
    T.truthy(ph.Bar:GetAlpha() < 1, "pulsing")
    bars[1]:SetIsActive(true)                                -- the buff is back
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(AB.CdmEffects.Flashing(ph), "stopped")
    T.eq(ph.Bar:GetAlpha(), 1, "back to full")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm missing: the old chain switch moves onto each spell of the chain", function()
    local DUI, AB, E, D, ess, bars = editorWorld()
    withCategories({ [3] = { 21 } }, { [3] = { 21 } })
    local set = D.Current()
    addBlock(D, set, "bar"); place(D, set, 21, 1, 1)
    chainOf(set, 1).always = true
    set = D.Current()
    T.eq(set.pieces[21].missing, true)
    T.isnil(chainOf(set, 1).always)
    noCategories()
end)

T.test("cdm missing: Battle Shout only while it's down, glowing", function()
    local DUI, AB, E, D, ess, bars = editorWorld()
    withCategories({ [3] = { 21 } }, { [3] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local set = D.Current()
    addBlock(D, set, "bar"); place(D, set, 21, 1, 1)
    T.truthy(D.SetSpellValue(set, 21, "missing", true))
    T.truthy(D.SetSpellValue(set, 21, "hideActive", true))
    T.truthy(D.SetSpellValue(set, 21, "missingGlow", true))
    bars[1]:SetIsActive(true)                                -- up: hidden
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(bars[1]:GetAlpha(), 0, "hidden while active")
    T.falsy(AB.CdmEffects.GlowShown(bars[1]))
    bars[1]:SetIsActive(false)                                -- down: the stand-in, glowing
    AB.CdmRows.Refresh(); stub.RunTimers()
    local ph = AB.CdmOwn.PlaceholderFrame(21, "bar")
    T.truthy(ph and ph:IsShown(), "shown while missing")
    T.truthy(AB.CdmEffects.GlowShown(ph), "glows while missing")
    bars[1]:SetIsActive(true)                                -- cast again
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(ph), "glow gone")
    T.eq(bars[1]:GetAlpha(), 0)
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's own buff item, hidden while up, kept its spot, so a group growing
-- from its middle sat off-center. This applies to every track type.
T.test("cdm hide up: the game's buff item hidden while up gives its spot up, back when it drops", function()
    local DUI, AB, E, D, ess, bars = editorWorld()
    DUI.DB.General().motion = false
    withCategories({ [3] = { 21, 22 } }, { [3] = { 21, 22 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local set = D.Current()
    addBlock(D, set, "bar"); place(D, set, 21, 1, 1); place(D, set, 22, 1, 2)
    T.truthy(D.SetChainValue(set, 21, "grow", "center"))
    T.truthy(D.SetSpellValue(set, 21, "hideActive", true))
    local full = D.Layout(set)
    bars[1]:SetIsActive(true); bars[2]:SetIsActive(true)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local f2 = pieceFrame(D.CurrentIndex(), 22)
    T.eq(bars[1]:GetAlpha(), 0, "up: hidden")
    local alone = D.Layout(set, { [22] = true })
    T.eq(f2.goalY, alone[22].y, "up and hidden: the other one comes to the middle")
    T.truthy(f2.goalY ~= full[22].y, "a spot that moved")
    bars[1]:SetIsActive(false)                                -- dropped: the game hides it
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(f2.goalY, alone[22].y, "down: the game's own hide, closed up")
    bars[1]:SetIsActive(true)                                -- cast again
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(bars[1]:GetAlpha(), 0, "up again: hidden")
    T.eq(f2.goalY, alone[22].y, "still closed up, no flicker back")
    -- With slide over off it keeps its spot.
    T.truthy(D.SetChainValue(set, 21, "collapse", false))
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(f2.goalY, full[22].y, "Slide over off")
    -- With hide off it shows in its spot.
    T.truthy(D.SetChainValue(set, 21, "collapse", true))
    T.truthy(D.SetSpellValue(set, 21, "hideActive", false))
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(bars[1]:GetAlpha(), 1)
    T.eq(f2.goalY, full[22].y, "shown: in its spot")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Demon Skin, from a card saved before Visibility existed (Buff up: Hide, Keep
-- its spot off, Glow on), showed a glow around a hidden button.
T.test("cdm missing: a glow always has its icon under it; Hide takes both", function()
    local DUI, AB, E, D, set = auraWorld(false)
    plainAuras()
    DUI.DB.General().motion = false
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    T.truthy(D.SetSpellValue(set, 41, "missingGlow", true))
    stub.auras.player = { HELPFUL = {} }
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.eq(D.PieceBlock(set, 41).always, true, "the glow keeps it in the layout")
    T.truthy(h.under:IsShown(), "the grayed icon under the glow")
    T.eq(h.underBox:GetAlpha(), 1)
    T.truthy(AB.CdmEffects.GlowShown(h), "reminding")
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 0, "cast: hidden, as Buff up asks")
    T.falsy(AB.CdmEffects.GlowShown(h))
    -- Hide (Buff missing): nothing shows, so nothing glows.
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.truthy(D.SetSpellValue(set, 41, "hideMissing", true))
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(D.PieceBlock(set, 41).always, false)
    T.falsy(AB.CdmEffects.GlowShown(h), "no glow round nothing")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A druid's Omen of Clarity (Buff only, "Glow on proc" on) never glowed while
-- Clearcasting was up, because WoW Forever fires no proc alerts. Buff up's Glow
-- lights it while the buff is up.
T.test("cdm up glow: a buff glows while it's up, on the game's item and on our own icon", function()
    local DUI, AB, E, D, ess, bars = editorWorld()
    withCategories({ [3] = { 21 } }, { [3] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local set = D.Current()
    addBlock(D, set, "bar"); place(D, set, 21, 1, 1)
    T.truthy(D.SetSpellValue(set, 21, "upGlow", true))
    T.truthy(D.SetSpellValue(set, 21, "upGlowColor", { 1, 1, 1 }))
    bars[1]:SetIsActive(true)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(AB.CdmEffects.GlowShown(bars[1]), "glows while up")
    bars[1]:SetIsActive(false)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(bars[1]), "not while down")
    -- Hide (Buff up): nothing shows, so nothing glows.
    T.truthy(D.SetSpellValue(set, 21, "hideActive", true))
    bars[1]:SetIsActive(true)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(bars[1]), "no glow round nothing")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm up glow: our own aura icon glows while its buff is up", function()
    local DUI, AB, E, D, set = auraWorld(false)
    plainAuras()
    DUI.DB.General().motion = false
    T.truthy(D.SetSpellValue(set, 41, "upGlow", true))
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.truthy(h.wantsUp, "it watches its buff")
    T.truthy(AB.CdmEffects.GlowShown(h), "glows while up")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(h), "not while down")
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.truthy(AB.CdmEffects.GlowShown(h), "again as it lands")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Recast glow: a damage over time spell cast again early loses the ticks it had
-- left, so it glows once the next cast would land just as it runs out. Timed from
-- your own casts and the length in the game's data, so it works in a fight where
-- the aura can't be read, with or without an item of the game's for the debuff.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm recast glow: lights when the next cast would land as the debuff ends (" .. shape .. ")", function()
    local DUI, AB, E, D, set = auraWorld(false)
    DUI.DB.General().motion = false
    if shape == "bar" then set.pieces[41].shape = "bar" end
    T.truthy(D.SetSpellValue(set, 41, "clipGlow", true))
    AB.CdmSpells.FACTS[141] = { lasts = 18 }
    C_Spell.GetSpellInfo = function(sid) return { castTime = sid == 141 and 2000 or 0 } end
    stub.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = shape == "bar" and AB.CdmBars.AuraFrame(41) or AB.CdmAuras.Frame(41)
    T.truthy(h.wantsClip, "it times its debuff from your cast")
    T.falsy(h.wantsUp, "and asks nobody whether it's up")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 141)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(h), "18 s left: not yet")
    -- 2.5 s left, more than its 2 s cast.
    stub.Advance(15.5)
    stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(h), "a cast now would still clip it")
    stub.Advance(0.6)
    stub.RunTimers(); stub.RunTimers()
    T.truthy(AB.CdmEffects.GlowShown(h), "glows: a cast now lands as it ends")
    -- Casting it is the refresh: the glow goes out.
    local now = GetTime() * 1000
    stub.units.player = stub.units.player or {}
    stub.units.player.cast = { name = "Rend", spellID = 141, from = now, to = now + 2000 }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "cast2", 141)
    stub.RunTimers(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(h), "not while casting it")
    stub.units.player.cast = nil
    stub.combat = false
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- Hide (Buff up) on the pieces Daylight UI draws itself. The client's button is
-- never asked to hide. Its container goes see-through instead, so it can't show
-- in a fight however the aura is read.
T.test("cdm hide up: our aura holder never shows the buff, Keep its spot grays only while it's down", function()
    local DUI, AB, E, D, set = auraWorld(false)
    plainAuras()
    DUI.DB.General().motion = false
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    T.truthy(D.SetSpellValue(set, 41, "missing", true))
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.eq(AB.CdmRows.DrawnBy(41), "aura icon")
    T.eq(h.containers[1].c:GetAlpha(), 0, "the buff's button can't show")
    T.eq(h.underBox:GetAlpha(), 0, "up: no grayed icon")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 1, "down: the grayed icon")
    -- Hide off again: the buff shows.
    T.truthy(D.SetSpellValue(set, 41, "hideActive", false))
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(h.containers[1].c:GetAlpha(), 1, "back")
    T.eq(h.underBox:GetAlpha(), 1)
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A Paladin's Kings with Show keybind on: the key stayed on screen over the
-- hidden buff.
T.test("cdm hide up: the keybind hides with the buff and comes back when it drops", function()
    local DUI, AB, E, D, set = auraWorld(false)
    plainAuras()
    DUI.DB.General().motion = false
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    T.truthy(D.SetSpellValue(set, 41, "missing", true))
    -- Slide over off, so it keeps its spot while hidden. With it on, it gives up
    -- the spot and the key goes with it (the end of this test).
    T.truthy(D.SetChainValue(set, 41, "collapse", false))
    AB.CdmOwn.Look = function(id) if id == 41 then return "Kings", "t" end end
    C_Spell.GetSpellName = function(id) return (id == 41 or id == 1041) and "Kings" or nil end
    stub.slots[2] = { texture = "t", spellID = 1041 }
    stub.bindings["ACTIONBUTTON2"] = { "Q" }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()
    DUI:Set("ActionBars", "cdmKeybinds", true)
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    local l = AB.Cooldowns.KeyLabel(h)
    T.truthy(l and l:IsShown(), "the label is there")
    T.eq(l.text:GetAlpha(), 0, "up: no key over the hidden buff")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(l.text:GetAlpha(), 1, "down: the key with the grayed icon")
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(l.text:GetAlpha(), 0, "up again: gone")
    T.truthy(D.SetSpellValue(set, 41, "hideActive", false))
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(l.text:GetAlpha(), 1, "Hide off: the key shows with the buff")
    -- Slide over on: hidden while up, it gives up its spot, key and all.
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    T.truthy(D.SetChainValue(set, 41, "collapse", true))
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(l:IsShown(), "Slide over: no key where its spot was")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.truthy(l:IsShown() and l.text:GetAlpha() == 1, "down: back in its spot with its key")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Sap (hidden by default in the game's own Cooldown Manager) placed as a bar showed
-- nothing on a sapped mob. It's your debuff on the target, cast out of a fight.
T.test("cdm auras: Sap on your target shows, icon and bar", function()
    local rules = dofile("tests/aura_rules.lua")
    for _, shape in ipairs({ "icon", "bar" }) do
        local DUI, AB, E, D, set = auraWorld(false)
        plainAuras()
        DUI.DB.General().motion = false
        stub.units.player = stub.units.player or {}
        stub.units.player.class = "ROGUE"
        AB.CdmSpells.ROGUE = { { 6770, 2070, 11297, aura = true } }
        AB.CdmCustom.Forget()
        _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
            return { spellID = 6770, overrideSpellID = 11297, selfAura = false, hasAura = true }
        end
        set.pieces[41].shape = shape
        stub.knownSpells = { [6770] = true, [2070] = true, [11297] = true }
        stub.units.target = { name = "Giant Yeti", reaction = 2, guid = "Creature-1", health = 300, maxHealth = 300 }
        AB.CdmRows.Refresh(); stub.RunTimers()
        local h = (shape == "bar" and AB.CdmBars.AuraFrame or AB.CdmAuras.Frame)(41)
        T.truthy(h and h:IsShown(), shape .. ": drawn by ours")
        local k
        for _, c in ipairs(h.containers or {}) do if c.unit == "target" then k = c end end
        T.truthy(k, shape .. ": watches the target")
        local g = k.c.__groups.a
        local sapped = { spellId = 11297, harmful = true, mine = true, fromPlayer = true, duration = 45 }
        T.truthy(rules(g, { canAssist = false }, sapped), shape .. ": the client would show your Sap there")
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 11297)
        stub.auras.target = { HARMFUL = { { spellId = 11297, duration = 45, expirationTime = GetTime() + 45,
            isFromPlayerOrPlayerPet = true, isHarmful = true } } }
        AB.CdmAuras.AuraChanged(); stub.RunTimers()
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.truthy(h:IsShown() and h:GetAlpha() > 0, shape .. ": shown while the mob is sapped")
        T.eq(AB.CdmAuras.IsUp(h), true, shape .. ": read as up")
        stub.auras.target = nil
        noCategories()
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

T.test("cdm hide up: the game's hidden buff item says when it falls off in a fight, even early", function()
    local DUI, AB, E, D, ess, bars, icons = editorWorld({ 41 })
    DUI.DB.General().motion = false
    withCategories({ [2] = { 41 } }, { [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    _G.GetSpellBaseCooldown = function(sid) return sid == 141 and 15000 or 0 end
    local set = D.Current()
    addBlock(D, set, "icon"); place(D, set, 41, 1, 1)
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    icons[1]:SetIsActive(true)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown icon")
    local own = AB.CdmOwn.Frame(41)
    T.eq(own:GetAlpha(), 0, "up: hidden")
    stub.combat = true
    icons[1]:SetIsActive(false); stub.RunTimers()
    T.eq(own:GetAlpha(), 1, "cancelled in the fight: back")
    icons[1]:SetIsActive(true); stub.RunTimers()
    T.eq(own:GetAlpha(), 0, "up again, whoever cast it")
    stub.combat = false
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm hide up: Cooldown and buff hides our cooldown icon while the buff is up", function()
    local DUI, AB, E, D = editorWorld()
    plainAuras()
    DUI.DB.General().motion = false
    withCategories({ [2] = { 41 } }, { [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    _G.GetSpellBaseCooldown = function(sid) return sid == 141 and 15000 or 0 end
    local set = D.Current()
    addBlock(D, set, "icon"); place(D, set, 41, 1, 1)
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown icon")
    local own, h = AB.CdmOwn.Frame(41), AB.CdmAuras.Frame(41)
    T.eq(h.containers[1].c:GetAlpha(), 0, "the buff's button can't show")
    T.eq(own:GetAlpha(), 0, "up: the icon hidden")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(own:GetAlpha(), 1, "down: the cooldown icon")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Berserking set to Both, Fade on cooldown, Buff up Show: the buff starts the
-- cooldown, and the icon showed faded the whole time the buff was up.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm buff up: Cooldown and buff stays bright while its buff is up, fades on cooldown after (" .. shape .. ")", function()
    local DUI, AB, E, D = editorWorld()
    plainAuras()
    DUI.DB.General().motion = false
    withCategories({ [2] = { 41 } }, { [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    _G.GetSpellBaseCooldown = function(sid) return sid == 141 and 15000 or 0 end
    local cds = {}
    C_Spell.GetSpellCooldown = function(sid) return cds[sid] end
    local set = D.Current()
    addBlock(D, set, shape); place(D, set, 41, 1, 1)
    T.truthy(D.SetSpellValue(set, 41, "onCd", "fade"))
    T.truthy(D.SetSpellValue(set, 41, "cdAlpha", 0.4))
    cds[141] = { duration = 180, isOnGCD = false }
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown " .. shape)
    local own = shape == "icon" and AB.CdmOwn.Frame(41) or AB.CdmBars.AuraFrame(41)
    T.eq(own:GetAlpha(), 1, "buff up: shown, not faded")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(own:GetAlpha(), 0.4, "buff gone, still on cooldown: faded")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end
