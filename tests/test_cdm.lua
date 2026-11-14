local stub = require("stub")

local function data()
    stub.Load({ actionbars = true })
    return stub.actionbars.CdmData
end

local function empty() return { v = 2, pieces = {}, chains = {} } end

-- A set with one row of icons 11, 12, 13 at 0, 0 (36 px, gap 4).
local function filled(D)
    local set = empty()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    return set
end

local function box(b) return { b.x, b.y, b.w, b.h } end

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
    jit.off()   -- the game has no JIT, and its own bookkeeping isn't the addon's to count
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do D.Root(set, 16) end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    jit.on()
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

-- A logged-in Warrior (profiles are per class).
local function profileWorld(class)
    local DUI = stub.Load({ actionbars = true })
    stub.units.player = stub.units.player or { isPlayer = true, name = "Tester" }
    stub.units.player.class = class or "WARRIOR"
    return DUI, stub.actionbars.CdmData
end

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

-- An old per-character layout (before profiles), moved as at login.
local function oldLayout(DUI, D, g, set)
    local cdm = D.Store()
    cdm.sets = cdm.sets or {}
    cdm.sets[g] = set
    D.MoveToProfiles(true)
    return D.Get(g)
end

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

-- An old-format set (format 1): blocks, and buttons with block + order.
local function oldSet(blocks, buttons) return { blocks = blocks, buttons = buttons } end
local function oldBlock(kind, over)
    local b = kind == "bar"
        and { kind = "bar", dir = "column", x = 0, y = 0, grow = "end", wrap = "right", size = 18, width = 220,
              spacing = 2, collapse = true, combat = false, always = false, color = "class", icon = true, text = 11, time = true }
        or { kind = "icon", dir = "row", x = 0, y = 0, grow = "center", wrap = "down", size = 36, spacing = 4,
              perLine = 8, collapse = true, combat = false, always = false }
    for k, v in pairs(over or {}) do b[k] = v end
    return b
end
local function inBlock(i, ids)
    local t = {}
    for n, id in ipairs(ids) do t[id] = { block = i, order = n } end
    return t
end

T.test("cdm data: the old profile layouts move to saved copies, once", function()
    local DUI = stub.Load({ actionbars = true })
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

-- A layout from 1.6.0 or older, parked in cdmSaved under profile name.
local function parked(DUI, name, g)
    local root = DUI.DB.Root()
    root.cdmSaved = root.cdmSaved or {}
    root.cdmSaved[name] = root.cdmSaved[name] or {}
    root.cdmSaved[name][g or 1] = oldSet({ oldBlock("icon") }, inBlock(1, { 11, 12 }))
end

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

-- From a player's report: two characters with the same first name shared one
-- entry in 1.6.3, and after 1.6.4 the second one's CDM was empty.
local function boopy(last, class, db)
    local DUI = stub.Load({ actionbars = true, before = function()
        _G.GetRealmName = function() return "R" end
        stub.units.player = { name = "Boopy", lastName = last, isPlayer = true, class = class }
        DaylightUIDB = db or DaylightUIDB
    end })
    return DUI, stub.actionbars.CdmData
end

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

-- A player's saved file, cut down: one entry "Nightz-Realm" shared by a paladin
-- (Nightz Pali) and a hunter. The hunter logged in first on 1.6.4, so the
-- paladin's layout became p1, a HUNTER profile "Nightz". The paladin, seeing
-- nothing, opened the editor and got p2, empty, picked.
local function nightzFile()
    return { version = 2, profileData = { Nightz = {} }, cdmMoved = 2, cdmNextProfile = 2, cdmSaved = {},
        cdmProfiles = {
            p1 = { class = "HUNTER", name = "Nightz", set = { v = 2, chains = {}, pieces = {
                ["s1311649"] = { shape = "icon", x = 1, y = -176 },
                [200265] = { shape = "icon", parent = "s1311649", side = "left", align = "center" } } } },
            p2 = { class = "PALADIN", name = "Paladin", set = { v = 2, chains = {}, pieces = {} } },
        },
        characters = { ["Nightz-R"] = { class = "PALADIN", mailName = "Nightz Pali", profile = "Nightz",
            install = "installed", cdm = { use = { "p2" } } } } }
end
local function nightz(last, class, db)
    local DUI = stub.Load({ actionbars = true, before = function()
        _G.GetRealmName = function() return "R" end
        stub.units.player = { name = "Nightz", lastName = last, isPlayer = true, class = class }
        DaylightUIDB = db
    end })
    local D = stub.actionbars.CdmData
    D.Get(1)   -- the first layout pass, as in game
    return DUI, D
end

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

-- A viewer of the game's shape: items with a cooldownID (nil = unused pool item).
local function fakeViewer(name, ids)
    local v = CreateFrame("Frame", name, UIParent)
    local items = {}
    for i, id in ipairs(ids) do
        local item = CreateFrame("Frame", nil, v)
        item:SetSize(40, 40)
        item.cooldownID = id
        item.layoutIndex = i
        item.Icon = item:CreateTexture()
        item.Cooldown = CreateFrame("Cooldown", nil, item)
        if name == "BuffBarCooldownViewer" then
            item.Icon = CreateFrame("Frame", nil, item)
            item.Icon.Icon = item.Icon:CreateTexture()
            item.Bar = CreateFrame("StatusBar", nil, item)
            item.Bar.Name = item.Bar:CreateFontString()
            item.Bar.Duration = item.Bar:CreateFontString()
        end
        items[i] = item
    end
    v.itemFramePool = { EnumerateActive = function()
        local i = 0
        return function() i = i + 1; return items[i] end
    end }
    -- The game's RefreshLayout (CooldownViewer.lua): every item is released
    -- (hidden, anchors cleared), acquired again and shown, then put back in the
    -- viewer's own grid. Only the game's code runs it: on its settings changing
    -- (EventRegistry "CooldownViewerSettings.OnDataChanged"), a full aura update,
    -- Edit Mode, or the viewer showing.
    function v:RefreshLayout()
        self.__laid = (self.__laid or 0) + 1
        for _, item in ipairs(items) do item:Hide(); item:ClearAllPoints() end
        for i, item in ipairs(items) do
            if item.cooldownID then
                item:Show()
                item:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * 40, 0)
            end
        end
    end
    -- A bar's content (Edit Mode "Icon and name" 1, "Name only" 3). The game
    -- hides or shows the icon frame and adds a LEFT point to the bar.
    if name == "BuffBarCooldownViewer" then
        for _, item in ipairs(items) do
            function item:SetBarContent(c)
                if c == 3 then self.Icon:Hide() else self.Icon:Show() end
                self.Bar:SetPoint("LEFT", self.Icon, c == 3 and "LEFT" or "RIGHT", c == 3 and 0 or 2, 0)
            end
        end
    end
    if _G.EventRegistry then
        _G.EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", v.RefreshLayout, v)
    end
    v:RegisterUnitEvent("UNIT_AURA", "player", "target")
    v:SetScript("OnEvent", function(self, event, _, info)
        if event == "UNIT_AURA" and (not info or info.isFullUpdate) then self:RefreshLayout() end
    end)
    return v, items
end

-- The game's event hub (CallbackRegistry). Callbacks are kept per event and
-- called as fn(owner, ...).
local function fakeRegistry()
    local cbs = {}
    _G.EventRegistry = {
        RegisterCallback = function(_, e, fn, owner)
            cbs[e] = cbs[e] or {}
            cbs[e][#cbs[e] + 1] = { fn, owner }
        end,
        UnregisterCallback = function() end,
        TriggerEvent = function(_, e, ...)
            for _, c in ipairs(cbs[e] or {}) do c[1](c[2], ...) end
        end,
    }
end

-- Essential: ids 11, 12, 13; BuffBar: 21, 22.
-- buffIcons: ids for a Tracked Buffs icon viewer too (5th in the items).
local function rowsWorld(buffIcons)
    local ess, bars, icons
    local DUI = stub.Load({ actionbars = true, before = function()
        fakeRegistry()
        _, ess = fakeViewer("EssentialCooldownViewer", { 11, 12, 13 })
        _, bars = fakeViewer("BuffBarCooldownViewer", { 21, 22 })
        if buffIcons then _, icons = fakeViewer("BuffIconCooldownViewer", buffIcons) end
    end })
    stub.RunTimers()
    return DUI, stub.actionbars, ess, bars, icons
end

local function layoutFrame(g) return _G["DaylightUICdmLayout" .. g] end
local function pieceFrame(g, id) return _G["DaylightUICdmPiece" .. g .. "_" .. id] end

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

T.test("cdm rows: unplaced items fade with the layout and the setting on", function()
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
    T.eq(ess[2]:GetAlpha(), 1, "setting off")
    D.SetSwitch("hideUnplaced", true)
    R.Refresh(); stub.RunTimers()
    T.eq(ess[2]:GetAlpha(), 0)
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
    -- Out of the layout (and unplaced items shown), the game's bar is back.
    D.SetSwitch("hideUnplaced", false)
    D.RemovePiece(set, 21)
    R.Refresh(); stub.RunTimers()
    T.eq(bars[1]:GetAlpha(), 1)
    T.falsy(h:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: switching talent set shows the other set's layout", function()
    local DUI, AB, ess = rowsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    local g = 1
    DUI.DB.SpecGroup = function() return g end
    D.AddPiece(D.Get(1), 11, "icon", 0, 0)
    D.AddPiece(D.Get(2), 12, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.truthy(layoutFrame(1):IsShown()); T.falsy(layoutFrame(2):IsShown())
    g = 2
    stub.FireEvent("ACTIVE_TALENT_GROUP_CHANGED"); stub.RunTimers()
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
    R.Refresh(); stub.RunTimers()
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
    local DUI = stub.Load({ actionbars = true, before = function()
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

local function pass(AB) AB.CdmRows.Refresh(); stub.RunTimers() end

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
    stub.Load({ actionbars = true, before = function()
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
    stub.actionbars.CdmData.SetSwitch("hideUnplaced", false)
    unplace(AB.CdmData, set, 11); pass(AB)
    T.falsy(Fx.GlowShown(ess[1]), "released")
    place(AB.CdmData, set, 11, 1); pass(AB)
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
    stub.actionbars.CdmData.SetSwitch("hideUnplaced", false)
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
    stub.actionbars.CdmData.SetSwitch("hideUnplaced", false)
    unplace(D, set, 11); pass(AB)
    T.isnil(CD.TextOf(item), "let go")
    T.eq(select(1, item.ChargeCount.Current:GetPoint(1)), "BOTTOMRIGHT", "count back at the corner")
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
    stub.actionbars.CdmData.SetSwitch("hideUnplaced", false)
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

-- The addon's own icons and bars ease their alpha (CdmEffects setAlpha), so let it land.
local function eased(DUI)
    local d = DUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
end

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
    bars[1]:Hide()
    pass(AB)
    bars[1]:Show()
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

T.test("cdm effects: hidden by cooldown turns the mouse off, back when ready", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local mouse = {}
    ess[2].EnableMouse = function(self, on) mouse[self] = on end
    set.pieces[12].onCd = "hide"
    cds[112] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(mouse[ess[2]], false, "no tooltip over the gap")
    pass(AB)
    T.eq(mouse[ess[2]], false, "next pass keeps it off")
    cds[112] = { duration = 0 }
    cdEvent()
    T.eq(mouse[ess[2]], true, "back on when shown")
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
    stub.actionbars.CdmData.SetSwitch("hideUnplaced", false)
    unplace(AB.CdmData, set, 11); pass(AB)
    T.eq(ess[1]:GetAlpha(), 1, "let go with the option already show")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's category lists (Essential 0, Utility 1, TrackedBuff 2,
-- TrackedBar 3): known ids, and all ids including unlearned ones.
local function withCategories(known, all)
    _G.Enum.CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenSpell = -1, HiddenAura = -2 }
    _G.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function(cat, allow) return (allow and all or known)[cat] or {} end,
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

T.test("cdm sounds: a buff's sound plays as the client's button comes up, once with the rows' word", function()
    local DUI, AB, E, D, set = auraWorld(false)
    local Fx = AB.CdmEffects
    T.truthy(D.SetSpellValue(set, 41, "buffSound", "kit:316447"))
    AB.CdmRows.Refresh(); stub.RunTimers()
    local got = listenAlerts(DUI)
    local h = AB.CdmAuras.Frame(41)
    local btn = h.containers[1].c.__groups.a.button
    local onPlay = btn.__shownAnims[1]:GetScript("OnPlay")
    T.truthy(onPlay, "the slide tells us")
    onPlay()
    T.eq(#got, 0, "just entered the world: buffs already up aren't news")
    stub.Advance(Fx.SETTLE + 1)
    stub.combat = true
    onPlay()
    T.deq(got, { "kit:316447" }, "a proc mid-fight")
    Fx.BuffMoment(set.pieces[41], h, true)
    Fx.BuffMoment(set.pieces[41], h, false)
    T.eq(#got, 1, "the same moment heard by two paths")
    stub.Advance(1)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    onPlay()
    T.eq(#got, 1, "a new target's debuff button isn't a proc")
    stub.Advance(1)
    Fx.SetAway(h, true)
    onPlay()
    T.eq(#got, 1, "a chain that's away stays quiet")
    Fx.SetAway(h, false)
    onPlay()
    T.eq(#got, 2)
    stub.combat = false
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    AB.CdmRows.Refresh(); stub.RunTimers(); eased(DUI)
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
    icons[1]:Hide()
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
    icons[1]:Show(); stub.RunTimers()
    T.falsy(ph:IsShown(), "game item showing hides its placeholder")
    icons[1]:Hide(); AB.CdmRows.Refresh(); stub.RunTimers()
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
    icons[1]:Hide()   -- the game's item never finds the debuff
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
    stub.Advance(17); stub.RunTimers()
    T.eq(h.face.alphaTo, 0, "18 s after the first cast: gone")
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
    icons[1]:Hide()
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
    stub.Advance(18.1); stub.RunTimers()
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
    icons[1]:Hide()
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
    bars[1]:Hide()
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
    bars[1]:Hide()
    AB.CdmRows.Refresh(); stub.RunTimers()
    local ph = AB.CdmOwn.PlaceholderFrame(21, "bar")
    T.falsy(AB.CdmEffects.Flashing(ph), "off by default")
    set.pieces[21].inactiveFlash = true
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(AB.CdmEffects.Flashing(ph), "flashing while down")
    stub.RunOnUpdate(AB.CdmEffects.flashDriver, 0.3)
    T.truthy(ph.Bar:GetAlpha() < 1, "pulsing")
    bars[1]:Show()                                -- the buff is back
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
    bars[1]:Show()                                -- up: hidden
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(bars[1]:GetAlpha(), 0, "hidden while active")
    T.falsy(AB.CdmEffects.GlowShown(bars[1]))
    bars[1]:Hide()                                -- down: the stand-in, glowing
    AB.CdmRows.Refresh(); stub.RunTimers()
    local ph = AB.CdmOwn.PlaceholderFrame(21, "bar")
    T.truthy(ph and ph:IsShown(), "shown while missing")
    T.truthy(AB.CdmEffects.GlowShown(ph), "glows while missing")
    bars[1]:Show()                                -- cast again
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
    bars[1]:Show(); bars[2]:Show()
    AB.CdmRows.Refresh(); stub.RunTimers()
    local f2 = pieceFrame(D.CurrentIndex(), 22)
    T.eq(bars[1]:GetAlpha(), 0, "up: hidden")
    local alone = D.Layout(set, { [22] = true })
    T.eq(f2.goalY, alone[22].y, "up and hidden: the other one comes to the middle")
    T.truthy(f2.goalY ~= full[22].y, "a spot that moved")
    bars[1]:Hide()                                -- dropped: the game hides it
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(f2.goalY, alone[22].y, "down: the game's own hide, closed up")
    bars[1]:Show()                                -- cast again
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
    bars[1]:Show()
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(AB.CdmEffects.GlowShown(bars[1]), "glows while up")
    bars[1]:Hide()
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(bars[1]), "not while down")
    -- Hide (Buff up): nothing shows, so nothing glows.
    T.truthy(D.SetSpellValue(set, 21, "hideActive", true))
    bars[1]:Show()
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.falsy(AB.CdmEffects.GlowShown(bars[1]), "no glow round nothing")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm up glow: our own aura icon glows while its buff is up", function()
    local DUI, AB, E, D, set = auraWorld(false)
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

-- Hide (Buff up) on the pieces Daylight UI draws itself. The client's button is
-- never asked to hide. Its container goes see-through instead, so it can't show
-- in a fight however the aura is read.
T.test("cdm hide up: our aura holder never shows the buff, Keep its spot grays only while it's down", function()
    local DUI, AB, E, D, set = auraWorld(false)
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

T.test("cdm hide up: in a fight your cast says it's up, its length when it runs out", function()
    local DUI, AB, E, D, set = auraWorld(false)
    DUI.DB.General().motion = false
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    T.truthy(D.SetSpellValue(set, 41, "missing", true))
    T.truthy(D.SetSpellValue(set, 41, "missingGlow", true))
    stub.auras.player = { HELPFUL = { { spellId = 141, duration = 120, expirationTime = GetTime() + 120 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 1, "down before the fight")
    T.truthy(AB.CdmEffects.GlowShown(h), "reminding")
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 141); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 0, "cast in the fight: gone")
    T.falsy(AB.CdmEffects.GlowShown(h), "no reminder")
    stub.FireEvent("UNIT_AURA", "player", {}); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 0, "a blind aura look doesn't bring it back")
    stub.Advance(121); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 1, "ran out in the fight")
    T.truthy(AB.CdmEffects.GlowShown(h), "reminding again")
    stub.combat = false
    noCategories()
    T.eq(stub.lockErrors, 0, "no locked button touched")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm hide up: a harmful spell cast in a fight is gone with the target", function()
    local DUI, AB, E, D, set = auraWorld(false)
    DUI.DB.General().motion = false
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    T.truthy(D.SetSpellValue(set, 41, "missing", true))
    C_Spell.IsSpellHarmful = function() return true end
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 141); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 0)
    stub.FireEvent("PLAYER_TARGET_CHANGED"); stub.RunTimers()
    T.eq(h.underBox:GetAlpha(), 1, "the new target hasn't got it")
    stub.combat = false
    C_Spell.IsSpellHarmful = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    icons[1]:Show()
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown icon")
    local own = AB.CdmOwn.Frame(41)
    T.eq(own:GetAlpha(), 0, "up: hidden")
    stub.combat = true
    icons[1]:Hide(); stub.RunTimers()
    T.eq(own:GetAlpha(), 1, "cancelled in the fight: back")
    icons[1]:Show(); stub.RunTimers()
    T.eq(own:GetAlpha(), 0, "up again, whoever cast it")
    stub.combat = false
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm hide up: Cooldown and buff hides our cooldown icon while the buff is up", function()
    local DUI, AB, E, D = editorWorld()
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

-- Hidden while its buff was up, the addon's cooldown icon kept its spot in a
-- group growing from its middle.
T.test("cdm hide up: Cooldown and buff hidden while up gives its spot up, back when it drops", function()
    local DUI, AB, E, D = editorWorld()
    DUI.DB.General().motion = false
    withCategories({ [2] = { 41, 42 } }, { [2] = { 41, 42 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    _G.GetSpellBaseCooldown = function(sid) return (sid == 141 or sid == 142) and 15000 or 0 end
    local set = D.Current()
    addBlock(D, set, "icon"); place(D, set, 41, 1, 1); place(D, set, 42, 1, 2)
    T.truthy(D.SetChainValue(set, 41, "grow", "center"))
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    local full = D.Layout(set)
    local alone = D.Layout(set, { [42] = true })
    stub.auras.player = { HELPFUL = {} }
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown icon")
    local f2 = pieceFrame(D.CurrentIndex(), 42)
    T.truthy(f2 and f2:IsShown(), "the other spell is placed")
    T.eq(f2.goalX, full[42].x, "down: both in their spots")
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(AB.CdmOwn.Frame(41):GetAlpha(), 0, "up: hidden")
    T.eq(f2.goalX, alone[42].x, "up and hidden: the other one comes to the middle")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(AB.CdmOwn.Frame(41):GetAlpha(), 1, "down: back")
    T.eq(f2.goalX, full[42].x, "down: back in its spot")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm hide up: a custom spell's aura bar hides while up", function()
    local DUI, AB, E, D, set = auraWorld(false)
    DUI.DB.General().motion = false
    local p = set.pieces[41]
    p.shape = "bar"
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura bar")
    local h = AB.CdmBars.AuraFrame(41)
    T.eq(h.containers[1].c:GetAlpha(), 0, "the buff's bar can't show")
    T.eq(h:GetAlpha(), 0, "up: the whole bar hidden")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm hide up: the game's cooldown icon that shows its aura moves to ours, which can hide it", function()
    local DUI, AB, set, ess = fxWorld()
    DUI.DB.General().motion = false
    withCategories({ [0] = { 11 } }, { [0] = { 11 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    AB.CdmOwn.Forget()
    pass(AB)
    T.eq(AB.CdmRows.DrawnBy(11), "game", "left unset: the game's icon")
    T.truthy(AB.CdmData.SetSpellValue(set, 11, "hideActive", true))
    pass(AB)
    T.eq(AB.CdmRows.DrawnBy(11), "aura and cooldown icon")
    T.eq(ess[1]:GetAlpha(), 0, "the game's out of sight")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm own icons: a spell the game files as a buff but with a real cooldown gets our cooldown icon, its buff over it", function()
    local DUI, AB, E, D = editorWorld()
    withCategories({ [2] = { 41, 42 } }, { [2] = { 41, 42 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    _G.GetSpellBaseCooldown = function(sid) return sid == 141 and 15000 or 0 end
    local set = D.Current()
    addBlock(D, set, "icon"); place(D, set, 41, 1, 1); place(D, set, 42, 1, 2)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local own = AB.CdmOwn.Frame(41)
    T.truthy(own and own:IsShown(), "Charge-like: own cooldown icon")
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown icon")
    local h = AB.CdmAuras.Frame(41)
    T.truthy(h and h:IsShown(), "the buff's holder")
    T.eq(h:GetParent(), own, "over our icon")
    T.truthy(h:GetFrameLevel() > own.Cooldown:GetFrameLevel(), "above its cooldown swipe")
    T.falsy(h.under:IsShown(), "no dim underlay: the cooldown icon shows while the buff is down")
    -- Track: Cooldown shows the icon alone.
    D.SetSpellValue(set, 41, "track", "cooldown")
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "own icon")
    T.falsy(h:IsShown(), "the holder put away")
    T.isnil(AB.CdmOwn.Frame(42), "Rend-like: still an aura")
    T.truthy(AB.CdmAuras.Frame(42), "aura holder")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: ready glow goes off when the game hides the cooldown, follows isActive when it doesn't", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true
    cds[111] = { duration = 0, isOnGCD = false }
    pass(AB)
    T.truthy(Fx.GlowShown(ess[1]), "ready: glow")
    stub.combat = true
    cds[111] = { duration = stub.Secret(6), isOnGCD = stub.Secret(false), isActive = stub.Secret(true) }
    cdEvent()
    T.falsy(Fx.GlowShown(ess[1]), "unknown: no stale glow")
    cds[111] = { duration = stub.Secret(6), isOnGCD = false, isActive = true }
    cdEvent()
    T.falsy(Fx.GlowShown(ess[1]), "on cooldown by isActive")
    cds[111] = { duration = stub.Secret(0), isOnGCD = false, isActive = false }
    cdEvent()
    T.truthy(Fx.GlowShown(ess[1]), "ready by isActive")
    if T.dev then
        devCdm(DUI, "cdprobe")
        T.truthy(stub.ChatContains("111: duration secret"), "cdprobe: the held spell")
    end
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Redundant work (the sweep).

T.test("cdm effects: a cast's burst of cooldown and charge events refreshes each held item once", function()
    local DUI, AB, set, ess = fxWorld()
    withCooldowns(ess)
    local Fx, Own = AB.CdmEffects, AB.CdmOwn
    local refreshed, own = 0, 0
    local realR, realO = Fx.Refresh, Own.UpdateAll
    Fx.Refresh = function(...) refreshed = refreshed + 1; return realR(...) end
    Own.UpdateAll = function(...) own = own + 1; return realO(...) end
    cdEvent()
    local per = refreshed
    T.truthy(per > 0, "held items refreshed")
    refreshed, own = 0, 0
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.FireEvent("SPELL_UPDATE_CHARGES")
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.FireEvent("SPELL_UPDATE_CHARGES")
    stub.RunTimers()
    Fx.Refresh, Own.UpdateAll = realR, realO
    T.eq(refreshed, per, "four events: one pass")
    T.eq(own, 1, "our own icons once too")
end)

T.test("cdm effects: an unchanged glow or gray isn't painted again on every cooldown event", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true
    set.pieces[12].desat = "grey"
    cds[111] = { duration = 0, isOnGCD = false }
    cds[112] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.truthy(Fx.GlowShown(ess[1]), "ready: glow")
    local icon = AB.Cooldowns.IconOf(ess[2])
    T.truthy(icon:IsDesaturated(), "on cooldown: gray")
    local paints, greys = 0, 0
    local realP = DUI.Style.AccentPair
    DUI.Style.AccentPair = function(...) paints = paints + 1; return realP(...) end
    local realD = icon.SetDesaturated
    icon.SetDesaturated = function(...) greys = greys + 1; return realD(...) end
    for _ = 1, 5 do cdEvent() end
    T.eq(paints, 0, "the lit glow isn't painted again")
    T.eq(greys, 0, "the gray isn't written again")
    DUI.Fire("StyleChanged")                    -- the accent may have changed
    cdEvent()
    T.truthy(paints > 0, "a style change paints the glow again")
    icon.SetDesaturated = realD
    icon:SetDesaturated(false)                  -- the game sets its own
    T.truthy(icon:IsDesaturated(), "ours still goes back on after the game's")
    cds[112] = { duration = 0, isOnGCD = false }
    cdEvent()
    T.falsy(icon:IsDesaturated(), "ready: colored")
    DUI.Style.AccentPair = realP
end)

-- Earlier versions drew four flat 2 px lines, which read as a border rather than
-- a glow, then hand-made lights that read as a blob. Now it's the game's own proc
-- glow, recolored, easing in and out.
T.test("cdm effects: the glow is the game's proc ring, turning, recolored, easing in and out", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true
    cds[111] = { duration = 0 }
    pass(AB)
    local g = Fx.GlowFrame(ess[1])
    T.truthy(g and g:IsShown(), "lit")
    T.eq(g.tex.__atlas or g.tex:GetAtlas(), Fx.GLOW_ATLAS, "the game's proc loop art")
    T.truthy(g.tex:IsDesaturated(), "grayed, so our color tints it true")
    T.truthy(g.anim:IsPlaying(), "turning")
    T.eq(g:GetParent(), ess[1], "a frame of ours on the item, not the game's alert")
    T.eq(g:GetAlpha(), 0, "eases in from nothing")
    local drv = Fx.glowDriver
    stub.RunOnUpdate(drv, 0.05)
    local mid = g:GetAlpha()
    T.truthy(mid > 0 and mid < 1, "partway in")
    stub.RunOnUpdate(drv, 0.2)
    T.near(g:GetAlpha(), 1, 0.001, "fully in, FAST")
    T.isnil(drv.__scripts.OnUpdate, "nothing runs of ours once it's in: the ring turns by itself")
    -- Off: eases out, then hides and stops.
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    T.falsy(Fx.GlowShown(ess[1]))
    T.truthy(g:IsShown(), "still fading")
    stub.RunOnUpdate(drv, 0.1)
    T.truthy(g:GetAlpha() > 0 and g:GetAlpha() < 1, "partway out")
    stub.RunOnUpdate(drv, 0.3)
    T.falsy(g:IsShown(), "gone")
    T.falsy(g.anim:IsPlaying(), "stopped")
    T.isnil(drv.__scripts.OnUpdate, "the driver stops with nothing lit")
    -- Motion off: the fade snaps, but the ring still turns (a stopped flipbook shows its whole sheet).
    DUI.DB.General().motion = false
    cds[111] = { duration = 0 }
    cdEvent()
    stub.RunOnUpdate(drv, 0.01)
    T.eq(g:GetAlpha(), 1, "at once")
    T.truthy(g.anim:IsPlaying())
    DUI.DB.General().motion = nil
end)

-- The ring is square art: stretched over a long bar its corners smeared into a
-- blob across the whole bar (seen in game on a seal bar).
T.test("cdm effects: a bar's glow keeps square ends and stretches only the ring's straight middle", function()
    local DUI, AB = fxWorld()
    local Fx = AB.CdmEffects
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(200, 20)
    Fx.SetGlow(bar, true, { 1, 0, 1 })
    local g = Fx.GlowFrame(bar)
    local P = g.parts
    local gh = 20 + 2 * 20 * Fx.GLOW_PAD
    T.truthy(g.wide, "split for a wide item")
    T.truthy(P.left.clip:IsShown() and P.right.clip:IsShown(), "both ends drawn")
    T.near(P.left.holder:GetWidth(), gh, 0.01, "the left end is the whole ring, square")
    T.near(P.left.holder:GetHeight(), gh, 0.01)
    T.near(P.left.clip:GetWidth(), gh / 2, 0.01, "cut in half")
    T.near(P.right.holder:GetWidth(), gh, 0.01, "the right end too")
    T.near(P.mid.holder:GetWidth(), (200 + 2 * 20 * Fx.GLOW_PAD - gh) / Fx.GLOW_MID, 0.01,
        "the middle shows only the ring's straight edge")
    for _, key in ipairs({ "left", "mid", "right" }) do
        T.truthy(P[key].clip:DoesClipChildren(), key .. " is clipped")
        T.deq({ P[key].tex:GetVertexColor() }, { 1, 0, 1, 1 }, key .. " in the picked color")
    end
    -- A square icon keeps the one whole ring.
    local icon = CreateFrame("Frame", nil, UIParent)
    icon:SetSize(36, 36)
    Fx.SetGlow(icon, true)
    local gi = Fx.GlowFrame(icon)
    T.falsy(gi.wide)
    T.falsy(gi.parts.left.clip:IsShown(), "no ends on an icon")
    T.eq(select(2, gi.parts.mid.holder:GetPoint(1)), gi, "the whole ring over it")
end)

T.test("cdm layout: an aura shown or hidden re-places without reading the known spells or rebuilding the tree", function()
    local DUI, AB, E, D, ess = editorWorld()
    withCategories({ [0] = { 11, 12, 14 } }, { [0] = { 11, 12, 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return {} end
    C_Spell.GetSpellTexture = function() return 1234 end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1); place(D, set, 14, 1, 2)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(AB.CdmOwn.Frame(14) and AB.CdmOwn.Frame(14):IsShown(), "our own icon for 14")
    local reads = 0
    local CV = _G.C_CooldownViewer
    local realC = CV.GetCooldownViewerCategorySet
    CV.GetCooldownViewerCategorySet = function(...) reads = reads + 1; return realC(...) end
    local index = D.Index(set)
    for _ = 1, 5 do
        ess[1]:Hide(); stub.RunTimers()
        ess[1]:Show(); stub.RunTimers()
    end
    T.eq(reads, 0, "known spells kept")
    T.truthy(D.Index(set) == index, "the tree kept")
    T.truthy(AB.CdmOwn.Frame(14):IsShown(), "still placed")
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.truthy(reads > 0, "a spell learned: read again")
    place(D, set, 12, 1, 3); AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(D.Index(set) ~= index, "the layout written: the tree again")
    T.eq(ess[2]:GetParent() and select(2, ess[2]:GetPoint(1)), frameOf(12), "the new one placed")
    CV.GetCooldownViewerCategorySet = realC
end)

-- Any spell in a bar block (CdmBars) gets the addon's own bars for what the game
-- only draws as icons. Essential 11, 12; Tracked Buffs 31 (yours), 32; Tracked Bars 21.
local function barsWorld()
    local ess, icons, bars
    local DUI = stub.Load({ actionbars = true, before = function()
        fakeRegistry()
        _, ess = fakeViewer("EssentialCooldownViewer", { 11, 12 })
        _, icons = fakeViewer("BuffIconCooldownViewer", { 31, 32 })
        _, bars = fakeViewer("BuffBarCooldownViewer", { 21 })
    end })
    stub.RunTimers()
    _G.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = id == 31 or nil }
    end }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C_Spell.GetSpellTexture = function() return 1234 end
    local w = { cds = {}, durs = {}, charges = {}, chargeDurs = {} }
    C_Spell.GetSpellCooldown = function(sid) return w.cds[sid] end
    C_Spell.GetSpellCharges = function(sid) return w.charges[sid] end
    C_Spell.GetSpellCooldownDuration = function(sid, ignoreGCD) w.ignoreGCD = ignoreGCD; return w.durs[sid] end
    C_Spell.GetSpellChargeDuration = function(sid) return w.chargeDurs[sid] end
    local AB = stub.actionbars
    local set = AB.CdmData.Current()
    addBlock(AB.CdmData, set, "bar")
    return DUI, AB, set, w, ess, icons, bars
end

-- A warrior's Charge placed as an icon never showed. The game files it under
-- Tracked Buffs (it tracks the stun) and hides its buff icon until a stun lands,
-- while the editor offers it as a cooldown.
T.test("cdm rows: a cooldown the game files as a buff is ours, not the game's hidden buff icon", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [2] = { 31, 32 } }, { [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = function(sid) return sid == 131 and 15000 or 0 end
    icons[1]:Hide()                               -- no stun up, so the game hides it
    D.AddPiece(set, 31, "icon", 0, 0)
    D.AddPiece(set, 32, "icon", 0, -48)
    R.Refresh(); stub.RunTimers()
    local own = AB.CdmOwn.Frame(31)
    T.truthy(own and own:IsShown(), "our cooldown icon")
    T.eq(own:GetParent(), frameOf(31), "in its piece")
    T.truthy(frameOf(31):IsShown(), "its piece takes its spot")
    T.eq(icons[1]:GetAlpha(), 0, "the game's buff icon out of sight")
    icons[1]:Show()                               -- a stun lands, and it's still the addon's
    R.Refresh(); stub.RunTimers()
    T.eq(icons[1]:GetAlpha(), 0, "the game's buff icon stays out of sight")
    T.truthy(own:IsShown())
    T.isnil(AB.CdmOwn.Frame(32), "a real buff (no cooldown) stays the game's")
    T.eq(icons[2]:GetAlpha(), 1)
    -- As a bar it's a cooldown bar, not an aura bar that hides with the stun.
    icons[1]:Hide()
    D.SetShape(set, 31, "bar")
    R.Refresh(); stub.RunTimers()
    T.truthy(frameOf(31):IsShown(), "the bar piece shows with the stun down")
    T.eq(R.DrawnBy(31), "aura and cooldown bar", "the stun's bar over the cooldown")
    D.SetSpellValue(set, 31, "track", "cooldown")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "cooldown bar", "Track: Cooldown")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Power Word: Shield as a bar never drained by the shield left. The game files it
-- under Tracked Bars, and the game's own bar (kept there) only knows its time.
T.test("cdm rows: a shield the game shows as a bar is our aura bar while it fills by the shield", function()
    local DUI, AB, set, w, ess, icons, bars = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [3] = { 21 } }, { [3] = { 21 } })
    -- Power Word: Shield, rank 1 (CdmSpells' families mark it as a shield).
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 21 and 17 or 100 + id } end
    D.AddPiece(set, 21, "bar", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(21), "aura bar", "ours, filled by the shield")
    T.eq(bars[1]:GetAlpha(), 0, "the game's bar out of sight")
    local h = AB.CdmBars.AuraFrame(21)
    T.truthy(h.isShield and h.shield:IsShown(), "our shield bar")
    -- The empty part in the fill's own color, dimmed, read as one color. It's dark now.
    local parts = h.parts[h.containers[1].c.__groups.a.button]
    local r, g, b = parts.backTex:GetVertexColor()
    local c = DUI.Style.BACKGROUND
    T.eq(r, c[1]); T.eq(g, c[2]); T.eq(b, c[3])
    -- By time: the game's own bar does that.
    D.SetSpellValue(set, 21, "fillBy", "time")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(21), "game")
    T.eq(bars[1]:GetAlpha(), 1)
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- UNIT_SPELLCAST_SUCCEEDED's unit is secret for anyone else's cast under
-- restrictions (SecretWhenUnitSpellCastRestricted), so a handler hearing every
-- unit's casts compares a secret (`unit ~= "player"`) on each one in a raid. The
-- fake game's secrets can't fail a compare with a string, so this checks who
-- listens: only the player's own casts.
T.test("nothing of ours hears everyone's casts: your own only (the shield bars, the profession window)", function()
    barsWorld()
    local broad = {}
    for _, f in ipairs(stub.frames) do
        local fn = f.__events and f.__events.UNIT_SPELLCAST_SUCCEEDED and not f.__unitEvents.UNIT_SPELLCAST_SUCCEEDED
            and f.__scripts.OnEvent
        local src = fn and debug.getinfo(fn, "S").source or ""
        if fn and not string.find(src, "^@%.?/?tests[/\\]") and not string.find(src, "blizzard", 1, true) then
            broad[#broad + 1] = src
        end
    end
    T.eq(#broad, 0, "every unit's casts heard by " .. tostring(broad[1]))
end)

-- A priest's Power Word: Shield is a cooldown in the game's data (its Essential
-- id, with its aura). As a bar it's the shield's bar over its cooldown, and it
-- still fills by the shield left.
T.test("cdm rows: Hide (Buff missing) shows a shield's bar only while there is a shield", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 11 and 17 or 100 + id, selfAura = true, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 17 and 4000 or 0 end
    D.AddPiece(set, 11, "bar", 0, 0)
    T.truthy(D.SetSpellValue(set, 11, "missing", true))
    T.truthy(D.SetSpellValue(set, 11, "hideMissing", true))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura bar")
    T.eq(D.PieceBlock(set, 11).always, false, "Keep its spot gives way")
    local h = AB.CdmBars.AuraFrame(11)
    local s = h.shield
    T.eq(h.under:GetAlpha(), 0, "no empty bar while it's down")
    T.eq(s:GetParent(), h.shieldClip, "the shield bar in the gate's clip")
    T.eq(h.shieldGate:GetValue(), 0, "closed with no shield")
    -- Off: the empty bar keeps its spot again.
    D.SetSpellValue(set, 11, "hideMissing", false)
    R.Refresh(); stub.RunTimers()
    T.eq(s:GetParent(), h, "back out of the clip")
    T.eq(h.under:GetAlpha(), 1, "kept in its spot")
    D.SetSpellValue(set, 11, "hideMissing", true)
    R.Refresh(); stub.RunTimers()
    stub.units.player = stub.units.player or {}
    stub.units.player.absorbs = stub.Secret(250)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 592)
    T.eq(rawget(h.shieldGate:GetValue(), "__value"), 250, "open while the shield is up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A warrior's Flurry (the game's Tracked Buffs, no cooldown) placed as a bar,
-- Buff only, Buff missing: Hide, glow on proc, never showed while Flurry was up.
T.test("cdm rows: a game buff icon placed as a bar with Hide (Buff missing) shows while the buff is up", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [2] = { 31, 32 } }, { [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, linkedSpellIDs = { 200 + id } }
    end
    D.AddPiece(set, 32, "bar", 0, 0)
    T.truthy(D.SetSpellValue(set, 32, "hideMissing", true))
    T.truthy(D.SetSpellValue(set, 32, "glow", true))
    stub.auras.player = { HELPFUL = { { spellId = 232 } } }
    icons[2]:Show()
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(32), "aura bar")
    T.truthy(frameOf(32):IsShown(), "its piece shows while up")
    local h = AB.CdmBars.AuraFrame(32)
    T.truthy(h and h:IsVisible(), "our bar is visible")
    local btn = h.containers[1].c.__groups.a.button
    T.truthy(btn and btn:IsVisible(), "the buff's bar is visible")
    T.eq(btn:GetEffectiveAlpha(), 1, "and not see-through")
    -- Down out of a fight (the piece slides over), then it procs mid-fight.
    stub.auras.player = { HELPFUL = {} }
    icons[2]:Hide()
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    stub.EnterCombat(); stub.RunTimers()
    stub.auras.player = { HELPFUL = { { spellId = 232 } } }
    icons[2]:Show()
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = false, addedAuras = {} }); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    T.truthy(frameOf(32):IsShown(), "its piece shows when it procs in a fight")
    btn = h.containers[1].c.__groups.a.button
    T.truthy(btn and btn:IsVisible(), "the buff's bar is visible in the fight")
    T.eq(btn:GetEffectiveAlpha(), 1, "and not see-through in the fight")
    stub.LeaveCombat(); stub.RunTimers()
    -- The game's Tracked Buffs window hidden (Edit Mode Visibility: Hidden, or In
    -- combat while out of one) stops hearing UNIT_AURA (its OnHide in
    -- CooldownViewer.lua), so its item stays hidden with the buff up. Daylight UI
    -- draws the spell from what it reads itself.
    icons[2]:Hide()
    icons[2]:GetParent():Hide(); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(32), "aura bar", "ours, not the hidden window's item")
    T.truthy(frameOf(32):IsShown(), "its piece shows with the game's window hidden")
    btn = h.containers[1].c.__groups.a.button
    T.truthy(btn and btn:IsVisible(), "the buff's bar is visible with the game's window hidden")
    -- A spell the game would hold in its own hidden window is drawn by the addon too.
    D.AddPiece(set, 31, "icon", 0, -48)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "aura icon", "drawn by Daylight UI, not the hidden window")
    T.eq(icons[1]:GetAlpha(), 1, "the hidden window's item let go")
    -- With the window back, its items report again.
    icons[2]:GetParent():Show(); icons[2]:Show(); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "game", "the game's own icon again")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A shaman's Flurry buff ID is only in the game's overrideTooltipSpellID (no
-- linkedSpellIDs). The game's own item matches it there
-- (GetAssociatedAuraSpellPriority in CooldownViewerItemData), so the addon must too.
T.test("cdm rows: a game buff whose aura is only its overrideTooltipSpellID shows while up", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [2] = { 31, 32 } }, { [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, overrideTooltipSpellID = 200 + id, linkedSpellIDs = {} }
    end
    D.AddPiece(set, 32, "bar", 0, 0)
    T.truthy(D.SetSpellValue(set, 32, "hideMissing", true))
    icons[2]:GetParent():Hide(); stub.RunTimers()
    stub.auras.player = { HELPFUL = { { spellId = 232 } } }
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(32), "aura bar")
    T.truthy(frameOf(32):IsShown(), "its piece shows while the buff is up")
    T.truthy(AB.CdmAuras.SpellIDs(32)[232], "the tooltip spell is one of its auras")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: a shield the game files as a cooldown fills by the shield left over its cooldown", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 11 and 17 or 100 + id, selfAura = true, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 17 and 4000 or 0 end
    D.AddPiece(set, 11, "bar", 0, 0)
    R.Refresh(); stub.RunTimers()
    -- With no shield up the bar used to be the cooldown, full (ready) and white.
    -- A shield's bar has no cooldown under it: empty, in its spot.
    T.eq(R.DrawnBy(11), "aura bar")
    local h = AB.CdmBars.AuraFrame(11)
    local s = h.shield
    T.truthy(h.isShield and s:IsShown(), "our shield bar")
    T.falsy(h.cooldownUnder, "no cooldown under it")
    T.eq(h.Bar:GetValue(), 0, "empty with no shield")
    T.eq(h.under:GetAlpha(), 1, "kept in its spot")
    T.truthy(frameOf(11):IsShown())
    local k = h.containers[1].c
    local btn = k.__groups.a.button
    local parts = h.parts[btn]
    T.eq(parts.bar:GetStatusBarTexture():GetAlpha(), 0, "the client's time fill gives way")
    T.truthy(s:GetFrameLevel() > k:GetFrameLevel(), "ours over the client's bar")
    T.eq(parts.bar:GetAlpha(), 0, "the client's whole time bar gives way")
    T.eq(s:GetAlpha(), 1, "ours is there, empty, with no shield")
    -- You cast it with no word from the client's button. The amount right after
    -- is the full value, and the hits after drain it.
    stub.units.player = stub.units.player or {}
    stub.units.player.absorbs = stub.Secret(250)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 592)
    local _, full = s:GetMinMaxValues()
    T.eq(rawget(full, "__value"), 250, "full at the cast")
    T.eq(rawget(s.gate:GetValue(), "__value"), 250, "the amount's gate open")
    stub.Advance(1)
    stub.units.player.absorbs = stub.Secret(100)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(s:GetValue(), "__value"), 100, "drained without the button")
    _, full = s:GetMinMaxValues()
    T.eq(rawget(full, "__value"), 250, "the full stays")
    stub.Advance(1)
    -- It lands, then soaks: the bar drains and its full value is kept.
    btn:Hide()
    stub.units.player = stub.units.player or {}
    stub.units.player.absorbs = stub.Secret(300)
    btn:Show()
    T.eq(s:GetAlpha(), 1, "shown while the shield is up")
    local _, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 300)
    stub.Advance(1)
    stub.units.player.absorbs = stub.Secret(120)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(s:GetValue(), "__value"), 120, "drained")
    -- It used to flash on a target change. With an enemy target it's still yours,
    -- and the client's button is left alone.
    local n = k.__refreshes or 0
    stub.units.target = { friend = false }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(k.__refreshes or 0, n, "no rebuild for an enemy target")
    -- The client rebuilding its button (gone and straight back) keeps the full value.
    stub.Advance(1)
    btn:Hide(); btn:Show()
    stub.units.player.absorbs = stub.Secret(90)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    _, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 300, "a blink isn't a new shield")
    T.eq(rawget(s:GetValue(), "__value"), 90)
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A prot warrior's Shield Block only showed while its buff was up. The game files
-- it as a buff. When the addon can't tell it has a cooldown (no base cooldown
-- answer), the player picks Track on the card.
T.test("cdm rows: Track picks what a buff spell shows (buff only, cooldown, both)", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [2] = { 31 }, [0] = { 33 } }, { [2] = { 31 }, [0] = { 33 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = nil                 -- no answer, so it can't tell
    icons[1]:Hide()                               -- the buff is down, so the game hides it
    D.AddPiece(set, 31, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "unset and unknown: buff only")
    T.isnil(Own.Track(33, nil), "a cooldown-family spell has no Track")
    T.falsy(frameOf(31):IsShown(), "buff only: gone while the buff is down")
    T.falsy(D.SetSpellValue(set, 31, "track", "sometimes"), "a bad value is refused")
    T.truthy(D.SetSpellValue(set, 31, "track", "both"))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "aura and cooldown icon")
    T.truthy(frameOf(31):IsShown(), "both: in its spot with the buff down")
    T.eq(icons[1]:GetAlpha(), 0, "the game's buff icon out of sight")
    icons[1]:Show()                               -- the buff lands, and it's still the addon's
    R.Refresh(); stub.RunTimers()
    T.eq(icons[1]:GetAlpha(), 0)
    T.eq(R.DrawnBy(31), "aura and cooldown icon")
    D.SetSpellValue(set, 31, "track", "buff")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "game", "buff only: the game's icon again")
    T.eq(icons[1]:GetAlpha(), 1)
    T.falsy(AB.CdmOwn.Frame(31):IsShown(), "our icon put away")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game doesn't always say a spell has a cooldown (Forever's API docs lack
-- GetSpellBaseCooldown). The first press outside restrictions teaches it, per
-- character, and the rule turns the spell into Cooldown and buff.
T.test("cdm facts: a buff spell's cooldown is learned from its first real cooldown (not the GCD, not a secret)", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = nil
    icons[1]:Hide()
    D.AddPiece(set, 31, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "not known yet: buff only")
    w.cds[131] = { duration = 1.5, isOnGCD = true }
    cdEvent()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "the GCD teaches nothing")
    w.cds[131] = { duration = stub.Secret(5), isOnGCD = false }
    cdEvent()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "a secret cooldown is never read")
    w.cds[131] = { duration = 5, isOnGCD = false }
    cdEvent()
    T.eq(DUI.DB.Character().cdmCooldowns[131], true, "remembered for this character")
    T.eq(Own.Track(31, set.pieces[31]), "both", "now: Cooldown and buff")
    T.eq(R.DrawnBy(31), "aura and cooldown icon")
    T.truthy(frameOf(31):IsShown(), "in its spot with the buff down")
    D.SetSpellValue(set, 31, "track", "buff")
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "the player's pick still wins")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's own Cooldown Manager switched off (Options, CVar cooldownViewerEnabled)
-- or a viewer set to Hidden: the game hides its viewers and every item in them
-- (the addon only anchors them). The addon's icons draw those spells then, and
-- hand them back to the game's items when it shows again.
T.test("cdm rows: a hidden game viewer hands its spells to our own icons", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = nil
    D.AddPiece(set, 11, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "game")
    EssentialCooldownViewer:Hide()
    stub.RunTimers()
    T.eq(R.DrawnBy(11), "own icon", "the game's viewer hidden: ours draws it")
    T.truthy(Own.Frame(11) and Own.Frame(11):IsVisible(), "and it shows")
    T.falsy(R.Owns(ess[1]), "the hidden item let go")
    EssentialCooldownViewer:Show()
    stub.RunTimers()
    T.eq(R.DrawnBy(11), "game", "shown again: the game's item")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Rend and Thunder Clap: the game files them as cooldowns, and its Essential icon
-- already shows the aura, then the cooldown. Left unset, that stays the game's when
-- the spell has a real cooldown. With none (Moonfire and Rend, where Moonfire sat
-- as a cooldown icon in game) it's the addon's aura icon, shown only while up. A
-- pick of Cooldown or Buff only is the addon's to draw.
T.test("cdm facts: a cooldown-family spell with an aura takes Cooldown or Buff only picks; one without has no Track", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, hasAura = id == 11, selfAura = false }
    end
    _G.GetSpellBaseCooldown = nil
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 12, "icon", 0, -48)
    R.Refresh(); stub.RunTimers()
    -- Unset, it stays the game's icon, shown all the time as the game shows it
    -- (Rend), with its debuff while up.
    T.eq(R.DrawnBy(11), "game", "unset, no cooldown: still the game's icon")
    T.eq(ess[1]:GetAlpha(), 1, "shown, as in the game")
    T.eq(Own.Track(11, set.pieces[11]), "both", "its aura while up, else ready")
    set.pieces[11].track = "buff"
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura icon", "Buff only picked: shown only while up")
    set.pieces[11].track = nil
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "game", "unset with a real cooldown: the game's icon (aura, then cooldown)")
    T.eq(ess[1]:GetAlpha(), 1)
    _G.GetSpellBaseCooldown = nil
    T.isnil(Own.Track(12, set.pieces[12]), "no aura: nothing to pick")
    D.SetSpellValue(set, 11, "track", "cooldown")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "own icon", "Cooldown: ours")
    T.eq(ess[1]:GetAlpha(), 0, "the game's icon out of sight")
    D.SetSpellValue(set, 11, "track", "buff")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura icon", "Buff only: the aura's holder")
    D.SetSpellValue(set, 11, "track", "both")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "game", "Both: the game's icon already does it")
    T.eq(ess[1]:GetAlpha(), 1)
    D.SetSpellValue(set, 12, "track", "cooldown")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(12), "game", "a pick on a spell with no aura changes nothing")
    D.SetShape(set, 11, "bar")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura and cooldown bar", "Both by hand as a bar: the cooldown under the aura")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: our own icons and cooldown bars follow On cooldown, While ready and the glows", function()
    local DUI, AB, set, w = barsWorld()
    local D, R, Fx = AB.CdmData, AB.CdmRows, AB.CdmEffects
    withCategories({ [0] = { 14 } }, { [0] = { 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    D.AddPiece(set, 14, "icon", 0, 0)             -- the game draws no item for it, so it's the addon's icon
    D.AddPiece(set, 11, "bar", 0, -48)            -- an Essential icon as a bar is the addon's cooldown bar
    set.pieces[14].onReady = "hide"
    set.pieces[11].onReady = "hide"
    set.pieces[11].readyGlow = true
    w.cds[114] = { duration = 0 }
    w.cds[111] = { duration = 0 }
    R.Refresh(); stub.RunTimers()
    local own, bar = AB.CdmOwn.Frame(14), AB.CdmBars.CooldownFrame(11)
    T.truthy(own and own:IsShown() and bar and bar:IsShown())
    T.eq(own:GetAlpha(), 0, "own icon ready: hidden")
    T.eq(bar:GetAlpha(), 0, "own bar ready: hidden")
    T.truthy(Fx.GlowShown(bar), "the ready glow reaches our bar")
    local mouse = own:IsMouseEnabled()
    w.cds[114] = { duration = 8, isOnGCD = false, isActive = true }
    w.cds[111] = { duration = 8, isOnGCD = false, isActive = true }
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers(); eased(DUI)
    T.eq(own:GetAlpha(), 1, "own icon on cooldown: shown")
    T.eq(bar:GetAlpha(), 1, "own bar on cooldown: shown")
    T.eq(own:IsMouseEnabled(), mouse, "the mouse is left as it was on our own frames")
    R.Refresh(); stub.RunTimers()
    T.eq(own:GetAlpha(), 1, "a layout pass keeps it")
    w.cds[114] = { duration = 0 }
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers(); eased(DUI)
    T.eq(own:GetAlpha(), 0, "ready again: hidden")
    D.RemovePiece(set, 14); R.Refresh(); stub.RunTimers()
    T.falsy(own:IsShown(), "let go")
    T.isnil(Fx.ButtonOf(own), "and its effects cleared")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: our own icon eases in and out of Only when usable (FAST)", function()
    local DUI, AB, set, w = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [0] = { 14 } }, { [0] = { 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local can = {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, false end
    D.AddPiece(set, 14, "icon", 0, 0)
    set.pieces[14].onUnusable = "hide"
    w.cds[114] = { duration = 0 }
    R.Refresh(); stub.RunTimers()
    local own = AB.CdmOwn.Frame(14)
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.eq(own:GetAlpha(), 0, "not castable: gone")
    can[114] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST / 2)
    local a = own:GetAlpha()
    T.truthy(a > 0 and a < 1, "on its way in: " .. tostring(a))
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST)
    T.eq(own:GetAlpha(), 1, "in")
    set.pieces[14].onUnusable = nil
    can[114] = false
    R.Refresh(); stub.RunTimers()
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST / 2)
    local r = own.Icon:GetVertexColor()
    T.truthy(r > 0.4 and r < 1, "the dim eases in: " .. tostring(r))
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST)
    T.eq((own.Icon:GetVertexColor()), 0.4, "dim")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: an Essential cooldown in a bar block is our bar, filled by the client", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    -- Its time uses the client's countdown numbers, as M:SS.
    local make = CreateFrame
    CreateFrame = function(kind, ...)
        local fr = make(kind, ...)
        if kind == "Cooldown" then function fr:SetCountdownFormatter(x) self.__formatter = x end end
        return fr
    end
    place(D, set, 11, 1)
    pass(AB)
    CreateFrame = make
    T.truthy(AB.CdmBars.CooldownFrame(11).Timer.__formatter == DUI.Style.ClockFormatter(), "countdown as M:SS")
    T.falsy(R.Owns(ess[1]), "the game's icon isn't claimed")
    T.eq(ess[1]:GetAlpha(), 0, "and out of sight")
    T.eq(R.DrawnBy(11), "cooldown bar")
    local f = AB.CdmBars.CooldownFrame(11)
    T.truthy(f and f:IsShown())
    T.eq(f:GetParent(), frameOf(11))
    T.truthy(R.Owns(f)); T.eq(R.BlockOf(f).kind, "bar")
    T.eq(f:GetWidth(), 220); T.eq(f:GetHeight(), 18, "the block's bar size")
    T.eq(f.Icon:GetWidth(), 18, "a square icon")
    T.truthy(AB.Cooldowns.Parts(f) and AB.Cooldowns.Parts(f).slot, "dressed like the game's bars")
    T.eq(f.Bar.Name:GetText(), "Spell111")
    T.eq(f.Bar:GetValue(), 1, "ready: full")
    -- On cooldown the client fills it from the duration object, ignoring the GCD.
    local d = stub.Duration(stub.Secret(30))
    w.cds[111] = { isActive = true }
    w.durs[111] = d
    cdEvent()
    T.truthy(f.Bar.__timer and f.Bar.__timer[1] == d, "the cooldown's duration object")
    T.eq(f.Bar.__timer[3], Enum.StatusBarTimerDirection.ElapsedTime, "fills up as it comes back")
    T.eq(w.ignoreGCD, true)
    -- The global cooldown alone: full, no timer.
    f.Bar.__timer = nil
    w.cds[111] = { isActive = true, isOnGCD = true }
    cdEvent()
    T.isnil(f.Bar.__timer); T.eq(f.Bar:GetValue(), 1)
    -- Charges (charge lines on): the bar holds the charges (a secret count drawn
    -- by the client), and the recharging piece sits one charge wide off its edge.
    local cd2 = stub.Duration(stub.Secret(8))
    f.Bar.__timer = nil
    f.Bar:SetWidth(180)                         -- its laid-out width, since the fake game doesn't solve anchors
    w.charges[111] = { maxCharges = 3, currentCharges = stub.Secret(1), isActive = true }
    w.chargeDurs[111] = cd2
    cdEvent()
    T.isnil(f.Bar.__timer, "the bar itself holds the charges")
    T.eq(select(2, f.Bar:GetMinMaxValues()), 3)
    T.truthy(f.next and f.next:IsShown() and f.next.__timer and f.next.__timer[1] == cd2, "the recharge piece")
    T.near(f.next:GetWidth(), 60, 0.01, "one charge wide")
    T.eq(select(2, f.next:GetPoint(1)), f.Bar:GetStatusBarTexture(), "off the fill's edge")
    T.truthy(f.lines[1]:IsShown() and f.lines[2]:IsShown(), "two lines for three charges")
    -- Charge lines off: the next charge's recharge spans the whole bar, as before.
    set.pieces[11].chargeLines = false
    pass(AB); cdEvent()
    T.truthy(f.Bar.__timer and f.Bar.__timer[1] == cd2, "the recharge")
    T.falsy(f.next:IsShown()); T.falsy(f.lines[1]:IsShown())
    -- Out of the block, the addon's bar hides and the game's icon comes back.
    D.SetSwitch("hideUnplaced", false)
    unplace(D, set, 11)
    pass(AB)
    T.falsy(f:IsShown())
    T.eq(ess[1]:GetAlpha(), 1)
    T.isnil(R.DrawnBy(11))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: a tracked buff in a bar block is the client's aura bar over an empty bar of ours", function()
    local DUI, AB, set, w, _, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    place(D, set, 31, 1)
    pass(AB)
    T.eq(icons[1]:GetAlpha(), 0, "the game's icon out of sight")
    T.eq(R.DrawnBy(31), "aura bar")
    local h = AB.CdmBars.AuraFrame(31)
    T.truthy(h and h:IsShown())
    T.eq(h:GetParent(), frameOf(31))
    T.eq(h.Bar:GetValue(), 0, "our bar is the empty one")
    T.eq(h.Bar.Name:GetText(), "Spell131")
    T.eq(#h.containers, 1)
    local k = h.containers[1]
    T.eq(k.unit, "player"); T.eq(k.c.__groups.a.filter, "HELPFUL")
    T.truthy(k.c.__groups.a.opts.candidateFilters.includeSpellIDs[131])
    local btn = k.c.__groups.a.button
    T.truthy(btn.__bar, "a bar the client fills")
    T.eq(btn.__barOpts.direction, Enum.StatusBarTimerDirection.RemainingTime, "emptying as the aura runs out")
    T.truthy(btn.__time and btn.__icon and btn.__count, "time, icon and stacks the client draws")
    T.eq(btn.__timeOpts.textFormatter, DUI.Style.ClockFormatter(), "the time as M:SS")
    T.eq(btn:GetWidth(), 220); T.eq(btn:GetHeight(), 18, "the button is the bar's size")
    -- A wider block in a PvP match: the button waits until the match ends.
    stub.SetRestriction("PvPMatch", true)
    lookOf(set, 1).width = 300
    pass(AB)
    T.eq(h:GetWidth(), 300, "our holder at once")
    T.eq(btn:GetWidth(), 220, "the client's button not touched")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.eq(btn:GetWidth(), 300, "after the match")
    -- The aura down (the game hid its icon) gets no slot in a collapsing block.
    -- "Show missing buffs" keeps the empty bar, pulsing when asked.
    icons[1]:Hide(); stub.RunTimers()
    T.falsy(h:IsShown(), "collapsed")
    chainOf(set, 1).always = true
    set.pieces[31].inactiveFlash = true
    pass(AB)
    T.truthy(h:IsShown(), "always show")
    T.truthy(AB.CdmEffects.Flashing(h), "pulses while down")
    icons[1]:Show(); stub.RunTimers()
    T.falsy(AB.CdmEffects.Flashing(h), "up again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: the aura bar takes the block's look and the spell's own color", function()
    local DUI, AB, set = barsWorld()
    local D = AB.CdmData
    place(D, set, 32, 1)
    set.pieces[32].barMode = "solid"
    set.pieces[32].barColor = { 1, 0, 0 }
    pass(AB)
    local h = AB.CdmBars.AuraFrame(32)
    T.eq(#h.containers, 2, "not said whose: both")
    local btn = h.containers[1].c.__groups.a.button
    local parts = h.parts[btn]
    T.deq(parts.bar.__barColor, { 1, 0, 0, 1 }, "the spell's fill color on the client's bar")
    T.eq(parts.icon:GetAlpha(), 1)
    lookOf(set, 1).icon = false
    pass(AB)
    T.eq(parts.icon:GetAlpha(), 0, "icon off")
    T.truthy(select(4, parts.bar:GetPoint(1)) < 18, "the bar starts at the left")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm text: a bar's own name and time size and color, over its group's text size", function()
    local DUI, AB, set = barsWorld()
    local D, Card, INK = AB.CdmData, AB.CdmCard, DUI.Style.INK
    place(D, set, 31, 1)
    pass(AB)
    local h = AB.CdmBars.AuraFrame(31)
    local parts = h.parts[h.containers[1].c.__groups.a.button]
    T.eq(select(2, parts.time:GetFont()), 11, "unset: the group's text size")
    T.rgb({ h.Bar.Name:GetTextColor() }, INK.VALUE, "and white")
    T.eq(Card.Fallback("nameSize", set, 31), 11, "the card shows the group's")
    T.truthy(D.SetLook(set, 31, "nameSize", 15))
    T.truthy(D.SetLook(set, 31, "nameColor", { 0, 1, 0 }))
    T.truthy(D.SetLook(set, 31, "timeSize", 9))
    T.truthy(D.SetLook(set, 31, "timeColor", { 1, 0, 1 }))
    T.falsy(D.SetLook(set, 31, "timeSize", "big"), "a size is a number")
    pass(AB)
    T.eq(select(2, h.Bar.Name:GetFont()), 15, "name size")
    T.rgb({ h.Bar.Name:GetTextColor() }, { 0, 1, 0 }, "name color")
    T.eq(select(2, parts.time:GetFont()), 9, "time size on the client's time")
    T.rgb({ parts.time:GetTextColor() }, { 1, 0, 1 }, "time color")
    T.eq(select(2, parts.name:GetFont()), 15, "the button's own name too")
    T.truthy(D.SetLook(set, 31, "timeSize", 11))
    T.isnil(set.pieces[31].look.timeSize, "the group's size again: unset")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: spells the game doesn't display become our bars in a bar block", function()
    local DUI, AB, set = barsWorld()
    withCategories({ [0] = { 14 }, [2] = { 41 } }, { [0] = { 14 }, [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, selfAura = false } end
    local D, R = AB.CdmData, AB.CdmRows
    place(D, set, 14, 1); place(D, set, 41, 1)
    pass(AB)
    T.eq(R.DrawnBy(14), "cooldown bar"); T.eq(R.DrawnBy(41), "aura bar")
    T.truthy(AB.CdmBars.CooldownFrame(14):IsShown())
    local h = AB.CdmBars.AuraFrame(41)
    T.truthy(h:IsShown())
    T.eq(h.containers[2].unit, "target"); T.eq(h.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
    -- A new target: the bar's container follows it, as the icons' do.
    local n = h.containers[2].c.__refreshes or 0
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(h.containers[2].c.__refreshes, n + 1)
    T.isnil(AB.CdmOwn.PlaceholderFrame(14, "bar"), "a real bar, not the empty stand-in")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Rend (its Essential cooldown id) placed as a bar sat full forever. The game's
-- Essential icon shows the spell's aura while it's up
-- (CheckCacheCooldownValuesFromAura, unless the HideAura flag is set) and the
-- cooldown otherwise. The addon's bar does the same.
T.test("cdm bars: a cooldown with an aura in a bar block follows the aura, its cooldown under it", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    -- 11: Rend (a debuff on the target, no cooldown). 12: Thunder Clap (a debuff
    -- and a real cooldown).
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 112 and 6000 or 0 end
    place(D, set, 11, 1); place(D, set, 12, 1)
    pass(AB)
    T.eq(R.DrawnBy(11), "aura bar", "Rend: the debuff's bar")
    local h = AB.CdmBars.AuraFrame(11)
    T.truthy(h and h:IsShown())
    T.eq(#h.containers, 2, "you (never matches a debuff), then the target")
    T.eq(h.containers[2].unit, "target"); T.eq(h.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
    T.truthy(h.containers[2].c.__groups.a.opts.candidateFilters.includeSpellIDs[111])
    T.eq(h.Bar:GetValue(), 0, "empty while the debuff is down")
    T.isnil(AB.CdmBars.CooldownFrame(11), "no cooldown bar")
    T.eq(ess[1]:GetAlpha(), 0, "the game's icon out of sight")
    -- Thunder Clap: the debuff while it's up, with the cooldown under it.
    T.eq(R.DrawnBy(12), "aura and cooldown bar")
    local t = AB.CdmBars.AuraFrame(12)
    T.truthy(t and t:IsShown() and t.Timer, "a cooldown under the aura")
    T.eq(t.Bar:GetValue(), 1, "ready: full")
    T.falsy(t.Icon.Icon:IsDesaturated(), "the icon in color: it's a cooldown too")
    local d = stub.Duration(stub.Secret(6))
    w.cds[112] = { isActive = true }
    w.durs[112] = d
    cdEvent()
    T.truthy(t.Bar.__timer and t.Bar.__timer[1] == d, "the cooldown fills our bar")
    local k = t.containers[2].c
    T.truthy(k:GetFrameLevel() > t.Timer:GetFrameLevel(), "the client's aura bar over the cooldown")
    local btn = k.__groups.a.button
    local back = t.parts[btn].back
    T.truthy(back and back:GetAlpha() == 1, "and it hides the cooldown under it while the aura is up")
    -- On a priest's Power Word: Shield, the empty part over the cooldown was the
    -- bar texture in pure white, with a white fill on it.
    local bt = t.parts[btn].backTex
    local r, g, b = bt:GetVertexColor()
    local c = DUI.Style.BACKGROUND
    T.eq(bt:GetAlpha(), 1)
    T.eq(r, c[1]); T.eq(g, c[2]); T.eq(b, c[3])
    -- When the game is told not to show the aura (HideAura), it's a cooldown bar.
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true, flags = id == 12 and 1 or 0 }
    end
    pass(AB)
    T.eq(R.DrawnBy(12), "cooldown bar")
    T.falsy(t:IsShown(), "the aura bar gone")
    T.eq(R.DrawnBy(11), "aura bar")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Shield Block and Holy Shield hold charges, but the game's Essential icon shows
-- their buff with no count. Its cooldown items only draw spell charges, never an
-- aura's applications (CooldownViewer.lua). The addon draws them: its own
-- cooldown icon with the client's aura button over it, which draws the stacks.
T.test("cdm: Shield Block and Holy Shield in the cooldown row show their charges (ours, not the game's icon)", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    stub.SetUnits({ player = { class = "WARRIOR" } })
    set = D.Current()
    AB.CdmSpells.WARRIOR = { { 2565, cd = true, aura = true }, { 20925, 20927, 20928, cd = true, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [1] = { 11, 12 } }, { [1] = { 11, 12 } })
    -- 11: a cooldown with a buff and no charges (stays the game's icon).
    -- 12: Shield Block, as the game files it: a Utility cooldown with no aura of
    -- its own, its buff only in the addon's spell list (a quiet aura, Cooldown
    -- only when left unset).
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 12 and 2565 or 100 + id, selfAura = true, hasAura = id ~= 12 }
    end
    _G.GetSpellBaseCooldown = function() return 5000 end
    AB.CdmOwn.Forget()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 12, "icon", 48, 0)
    pass(AB)
    T.eq(R.DrawnBy(11), "game", "no charges: the game's icon as before")
    T.eq(AB.CdmOwn.Track(12, set.pieces[12]), "both", "its buff while up, then the cooldown")
    T.eq(R.DrawnBy(12), "aura and cooldown icon", "Shield Block: ours")
    T.eq(ess[2]:GetAlpha(), 0, "the game's icon out of sight")
    local h = AB.CdmAuras.Frame(12)
    local btn = h and h.containers[1].c.__groups.a.button
    T.truthy(btn and btn.__count, "the client draws the charges left")
    -- On cast it moved oddly: the buff dropped in over the same spell's icon.
    -- Over the addon's icon it only fades in.
    T.eq(btn.cdmSlideKey, "fade", "no drop over the cooldown icon")
    -- Then it went down 2px and back up: going on cooldown the icon dips (shrinks
    -- and springs back) and the buff's button, its size locked, rode along. The
    -- buff now sits on the icon's spot instead.
    local own = AB.CdmOwn.Frame(12)
    local _, rel = h:GetPoint(1)
    T.eq(rel, own:GetParent(), "on the spot, not the dipping icon")
    T.eq(h:GetWidth(), own:GetWidth(), "the icon's size at rest")
    -- Holy Shield, any rank.
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 12 and 20928 or 100 + id, selfAura = true, hasAura = id ~= 12 }
    end
    AB.CdmOwn.Forget()
    pass(AB)
    T.eq(R.DrawnBy(12), "aura and cooldown icon", "Holy Shield: ours")
    -- Picked Cooldown only: no buff, so the game's way is fine either way.
    set.pieces[12].track = "cooldown"
    pass(AB)
    T.eq(R.DrawnBy(12), "own icon", "Cooldown only: no buff to count")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game files Slice and Dice as a cooldown with no aura, and it has no real
-- cooldown, so its icon showed nothing at all.
T.test("cdm: a filed cooldown with no real cooldown and a buff the game hides is its buff (Slice and Dice)", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    stub.SetUnits({ player = { class = "ROGUE" } })
    set = D.Current()
    AB.CdmSpells.ROGUE = { { 111, 1110, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 11 } }, { [0] = { 11 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = true, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    Own.Forget()
    D.AddPiece(set, 11, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(11, set.pieces[11]), "both", "its buff while up, else ready")
    T.eq(R.DrawnBy(11), "aura and cooldown icon", "ours: the game's icon never shows this buff")
    for _, r in ipairs(Card.ROWS.show) do
        if r.item and r.item.key == "cdm.card.track" then
            T.truthy(r.show(set, 11, set.pieces[11]), "What it shows is on its card")
        end
    end
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Eureka! (a Gnome racial) gives a buff the game doesn't flag, so its card had no
-- What it shows choice.
T.test("cdm card: Eureka! can pick its buff", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    withCategories({ [0] = { 21 } }, { [0] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
        return { spellID = 1259812, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 120000 end
    Own.Forget()
    D.AddPiece(set, 21, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    local shown
    for _, r in ipairs(Card.ROWS.show) do
        if r.item and r.item.key == "cdm.card.track" then shown = r.show(set, 21, set.pieces[21]) end
    end
    T.truthy(shown, "What it shows is on its card")
    T.truthy(D.SetSpellValue(set, 21, "track", "buff"))
    T.eq(Own.Track(21, set.pieces[21]), "buff")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Bloodrage (filed by the game as a cooldown with no aura to show) had no
-- What it shows, Buff up or Buff missing rows, while Rend had them.
T.test("cdm card: a cooldown whose buff the game doesn't show has the buff rows (Bloodrage)", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    stub.SetUnits({ player = { class = "WARRIOR" } })
    set = D.Current()     -- the class is part of whose settings these are
    AB.CdmSpells.WARRIOR = { { 111, 1110, cd = true, aura = true }, { 112, cd = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = true, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 60000 end
    Own.Forget()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 12, "icon", 48, 0)
    R.Refresh(); stub.RunTimers()
    local function row(key)
        for _, r in ipairs(Card.ROWS.show) do if r.item and r.item.key == key then return r end end
    end
    local function shows(id, key) return row(key).show(set, id, set.pieces[id]) end
    for _, key in ipairs({ "cdm.card.track", "cdm.card.buffUp", "cdm.card.missingGlow" }) do
        T.truthy(shows(11, key), key .. ": a cooldown with a buff")
    end
    T.truthy(shows(12, "cdm.card.track"), "a cooldown with no buff known can still pick")
    for _, key in ipairs({ "cdm.card.buffUp", "cdm.card.missingGlow" }) do
        T.falsy(shows(12, key), key .. ": a cooldown with none, left as a cooldown")
    end
    T.eq(Own.Track(11, set.pieces[11]), "cooldown", "left alone, what it always showed")
    T.isnil(Own.Track(12, set.pieces[12]), "left alone, a plain cooldown")
    T.eq(R.DrawnBy(11), "game", "left alone, the game's icon")
    -- Picked: its buff over its cooldown, watched for every rank.
    T.truthy(D.SetSpellValue(set, 11, "track", "both"))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura and cooldown icon")
    local ids = {}
    for k, v in pairs(AB.CdmAuras.Frame(11).containers[1].c.__groups.a.opts.candidateFilters.includeSpellIDs) do
        ids[v == true and k or v] = true
    end
    T.truthy(ids[111] and ids[1110], "every rank in the list")
    -- Only the buff.
    D.SetSpellValue(set, 11, "track", "buff")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura icon")
    -- Unset again, a Buff row alone brings the buff in.
    set.pieces[11].track = nil
    T.truthy(D.SetSpellValue(set, 11, "hideActive", true))
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(11, set.pieces[11]), "both")
    T.eq(R.DrawnBy(11), "aura and cooldown icon", "Hide (Buff up) needs the buff watched")
    D.SetSpellValue(set, 11, "hideActive", false)
    T.truthy(D.SetSpellValue(set, 11, "missingGlow", true))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura and cooldown icon", "Glow (Buff missing) too")
    -- The game's own flag counts as well: it has an aura, flagged not to show it.
    D.SetSpellValue(set, 11, "missingGlow", false)
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 300 + id, selfAura = true, hasAura = id == 12, flags = 1 }
    end
    Own.Forget()
    T.truthy(shows(12, "cdm.card.track"), "hasAura with the HideAura flag")
    T.isnil(Own.Track(11, set.pieces[11]), "no aura by either word")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The spell ids a holder's first container watches.
local function watched(AB, id, shape)
    local h = shape == "bar" and AB.CdmBars.AuraFrame(id) or AB.CdmAuras.Frame(id)
    local out = {}
    local c = h and h.containers[1]
    for k, v in pairs(c and c.c.__groups.a.opts.candidateFilters.includeSpellIDs or {}) do
        out[v == true and k or v] = true
    end
    return out
end

-- Every spell can pick Cooldown, Buff only or Both, even one with no buff anyone
-- listed: its buff is watched by its own id until a cast teaches the real one.
T.test("cdm track: a cooldown with no buff known can still be set to its buff or both, icon and bar", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 60000 end
    Own.Forget()
    D.AddPiece(set, 12, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(12), "game", "left alone, the game's cooldown icon")
    T.isnil(Own.Track(12, set.pieces[12]))
    T.truthy(D.SetSpellValue(set, 12, "track", "cooldown"))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(12), "game", "Cooldown is what it was: still the game's")
    for _, shape in ipairs({ "icon", "bar" }) do
        D.SetShape(set, 12, shape)
        T.truthy(D.SetSpellValue(set, 12, "track", "buff"))
        R.Refresh(); stub.RunTimers()
        T.eq(R.DrawnBy(12), shape == "bar" and "aura bar" or "aura icon", shape .. ": Buff only")
        T.truthy(watched(AB, 12, shape)[112], shape .. ": watched by its own id")
        T.truthy(D.SetSpellValue(set, 12, "track", "both"))
        R.Refresh(); stub.RunTimers()
        T.eq(R.DrawnBy(12), shape == "bar" and "aura and cooldown bar" or "aura and cooldown icon", shape .. ": Both")
    end
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Nothing lists every spell's buff, and a buff's id can differ from its spell's.
-- A cast where auras can be read finds it by id, else by the spell's name, and
-- keeps it per character.
T.test("cdm track: a placed spell's buff is learned from a cast, by name when its id differs", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 60000 end
    Own.Forget()
    D.AddPiece(set, 12, "bar", 0, 0)
    R.Refresh(); stub.RunTimers()
    stub.SetUnits({ player = {}, target = { exists = true } })
    -- Your debuff on the target, under another id but the spell's name.
    stub.SetAuras("target", "HARMFUL", { { name = "Spell112", spellId = 9112, sourceUnit = "player", isFromPlayerOrPlayerPet = true } })
    -- Not placed: nothing learned.
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-0", 111); stub.RunTimers()
    T.isnil(Own.AuraOf(111), "a spell not placed")
    -- In a fight auras can't be read: nothing learned.
    stub.SetRestriction("PvPMatch", true)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 112); stub.RunTimers()
    T.isnil(Own.AuraOf(112), "auras secret: nothing read")
    stub.SetRestriction("PvPMatch", false)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 112); stub.RunTimers()
    T.truthy(Own.AuraOf(112) and Own.AuraOf(112)[9112], "found by name")
    T.truthy(DUI.DB.Character().cdmAuraIDs[112][9112], "kept for this character")
    T.truthy(Own.QuietAura(12), "now a cooldown with a buff the game's icon doesn't show")
    T.eq(Own.Track(12, set.pieces[12]), "cooldown", "left alone it stays a cooldown, like Bloodrage")
    for _, shape in ipairs({ "bar", "icon" }) do
        D.SetShape(set, 12, shape)
        T.truthy(D.SetSpellValue(set, 12, "track", "both"))
        R.Refresh(); stub.RunTimers()
        T.eq(R.DrawnBy(12), shape == "bar" and "aura and cooldown bar" or "aura and cooldown icon", shape .. ": Both")
        local ids = watched(AB, 12, shape)
        T.truthy(ids[9112] and ids[112], shape .. ": the learned id watched as well as its own")
    end
    -- Someone else's debuff of that name teaches nothing.
    D.AddPiece(set, 11, "icon", 0, -48)
    stub.SetAuras("target", "HARMFUL", { { name = "Spell111", spellId = 9111, sourceUnit = "party1", isFromPlayerOrPlayerPet = false } })
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 111); stub.RunTimers()
    T.isnil(Own.AuraOf(111), "not yours")
    -- A buff on you under the cast's own id.
    stub.SetAuras("player", "HELPFUL", { { name = "Spell111", spellId = 111 } })
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 111); stub.RunTimers()
    T.truthy(Own.AuraOf(111) and Own.AuraOf(111)[111], "found by id")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Rend as a bar with Background color "Solid color" black: the empty bar stayed light gray.
T.test("cdm bars: an aura bar's empty part takes the background color (the spell's or its group's)", function()
    local DUI, AB, set = barsWorld()
    local D, CD = AB.CdmData, AB.Cooldowns
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    place(D, set, 11, 1)
    D.SetSpellValue(set, 11, "backMode", "solid")
    D.SetSpellValue(set, 11, "backColor", { 0.1, 0.2, 0.3, 0.9 })
    pass(AB)
    local h = AB.CdmBars.AuraFrame(11)
    T.eq(h.Bar:GetValue(), 0, "empty: the background is what shows")
    local p = CD.Parts(h)
    T.truthy(p and p.back, "the bar's backdrop")
    T.rgb({ p.back:GetVertexColor() }, { 0.1, 0.2, 0.3 }, "the spell's own")
    T.near(select(4, p.back:GetVertexColor()), 0.9)
    -- "Same as its group" uses the group's color (Look tab, Whole group).
    D.SetSpellValue(set, 11, "backMode", "block")
    D.SetLook(set, 11, "back", "solid", true)
    D.SetLook(set, 11, "backColor", { 0.5, 0, 0, 1 }, true)
    pass(AB)
    T.rgb({ p.back:GetVertexColor() }, { 0.5, 0, 0 }, "the group's")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The on-screen editor (CdmEditor)

-- The rows world with the editor open on talent set 1.
local function edWorld()
    local DUI, AB, ess, bars = rowsWorld()
    withCategories({ [0] = { 11, 12, 13 }, [3] = { 21, 22 } }, { [0] = { 11, 12, 13, 14 }, [3] = { 21, 22 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local names = {}
    _G.C_Spell.GetSpellName = function(sid) return names[sid] or ("Spell " .. sid) end
    -- The addon's own spell list starts empty; tests that need it fill it (customTray).
    for k in pairs(AB.CdmSpells) do AB.CdmSpells[k] = {} end
    AB.CdmCustom.Forget()
    local Ed = AB.CdmEditor
    T.truthy(Ed.Open(), "opens out of combat")
    return DUI, AB, Ed, AB.CdmData, ess, bars
end

T.test("cdm card: Move back and Move forward trade places with the spell beside it", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card = D.Current(), AB.CdmCard
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    Ed.Changed()
    local function row(key)
        for _, r in ipairs(Card.ROWS.chain) do if r.item and r.item.key == key then return r end end
    end
    local back, fwd = row("cdm.card.back"), row("cdm.card.forward")
    Ed.Select(11)
    Card.SetTab("chain")
    T.truthy(back.show(set, 11, set.pieces[11]), "both always there, side by side")
    T.truthy(back.item.disabled(), "the first can't go back: grayed")
    T.falsy(fwd.item.disabled())
    local b = back.frame
    T.truthy(b:IsShown() and fwd.frame:IsShown(), "on the Group tab")
    T.falsy(b:IsEnabled(), "grayed button")
    T.eq(select(5, fwd.frame:GetPoint(1)), select(5, b:GetPoint(1)), "one line")
    fwd.item.func()
    T.eq(D.Root(set, 13), 12, "11 moved forward: 12 leads")
    T.eq(set.pieces[11].parent, 12)
    T.eq(Ed.Selected(), 11, "still picked, to keep moving it")
    fwd.item.func()
    T.eq(set.pieces[11].parent, 13, "last now")
    T.truthy(fwd.item.disabled(), "nothing after it")
    back.item.func()
    T.eq(set.pieces[11].parent, 12, "back one")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: Form or stance lists the class's own forms, each a switch on by default", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card = D.Current(), AB.CdmCard
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "DRUID"
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Select(11)
    local rows = {}
    for _, r in ipairs(Card.ROWS.show) do if r.item then rows[r.item.key] = r end end
    local p = set.pieces[11]
    local cat, battle = rows["cdm.card.hideInCat"], rows["cdm.card.hideInBattle"]
    T.truthy(cat and cat.show(set, 11, p), "a druid: Cat Form")
    T.falsy(battle.show(set, 11, p), "no warrior stances for a druid")
    T.eq(cat.item.get(), true, "on by default: shown in it")
    cat.item.set(false)
    T.eq(set.pieces[11].hideInCat, true, "off: left out of Cat Form")
    cat.item.set(true)
    T.isnil(set.pieces[11].hideInCat, "back on: nothing saved")
    stub.units.player.class = "PRIEST"
    T.falsy(cat.show(set, 11, p), "a class with no forms: no rows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: each moment has its sound row, and its list opens with headings and plays a pick", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card, W = D.Current(), AB.CdmCard, DUI.Widgets
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Select(11)
    local rows = {}
    for _, r in ipairs(Card.ROWS.show) do
        if r.item then rows[r.item.key] = r end
    end
    local p = set.pieces[11]
    T.truthy(rows["cdm.card.readySound"].show(set, 11, p), "a cooldown: When ready has a sound")
    T.truthy(rows["cdm.card.usableSound"].show(set, 11, p), "Usable or proc too")
    T.falsy(rows["cdm.card.buffSound"].show(set, 11, p), "no buff, no buff sound")
    local item = rows["cdm.card.readySound"].item
    T.eq(item.get(), "none", "silent until picked")
    local row = CreateFrame("Frame", nil, UIParent)
    W.dropdown(row, { id = "cdm.card", scope = "ActionBars" }, item)
    row.control:Click()
    T.eq(W.menuOwner, row.control, "the list opens")
    W.CloseMenu()
    local heard = {}
    local alert = DUI.Sound.Alert
    DUI.Sound.Alert = function(key) heard[#heard + 1] = key; alert(key) end
    item.set("dui:quest")
    item.onPick("dui:quest")
    stub.RunTimers(1)
    T.eq(p.readySound, "dui:quest", "saved on the piece")
    T.eq(item.get(), "dui:quest")
    T.deq(heard, { "dui:quest" }, "heard once as it's picked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: the sound list plays a row the mouse rests on, and the pick, through its real rows", function()
    local DUI, AB, Ed, D = edWorld()
    local set, W = D.Current(), DUI.Widgets
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Select(11)
    DUI.Sound.ALERT_PUNCHY = {}   -- the addon's own sounds in the rows W.MenuRow shows, without scrolling
    local item
    for _, r in ipairs(AB.CdmCard.ROWS.show) do
        if r.item and r.item.key == "cdm.card.readySound" then item = r.item end
    end
    local row = CreateFrame("Frame", nil, UIParent)
    W.dropdown(row, { id = "cdm.card", scope = "ActionBars" }, item)
    local played, stopped = {}, {}
    _G.PlaySoundFile = function(file) played[#played + 1] = file; return true, #played end
    _G.StopSound = function(h) stopped[#stopped + 1] = h end
    local function rowOf(key)
        for i = 1, W.MENU_MAX_ROWS do
            local r = W.MenuRow(i)
            if r and r.key == key then return r end
        end
    end
    local function hover(key) rowOf(key):GetScript("OnEnter")(rowOf(key)) end
    local FILES = DUI.Sound.FILES
    row.control:Click()
    hover("none"); stub.RunTimers()
    hover("head:own"); stub.RunTimers()
    T.eq(#played, 0, "None and a heading have nothing to hear")
    hover("dui:quest")
    hover("dui:done")
    hover("dui:apply")
    stub.RunTimers()
    T.deq(played, { FILES.apply }, "a sweeping mouse: only where it rests")
    hover("dui:done"); stub.RunTimers()
    T.deq(played, { FILES.apply, FILES.done })
    T.deq(stopped, { 1 }, "the last one is cut off")
    T.isnil(set.pieces[11].readySound, "hovering saves nothing")
    rowOf("dui:quest"):Click()
    stub.RunTimers()
    T.eq(set.pieces[11].readySound, "dui:quest", "a real click saves it")
    T.eq(played[#played], FILES.quest, "and plays it")
    _G.StopSound = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: open hides the live layout behind previews; Done brings it back", function()
    local DUI, AB, Ed, D, ess = edWorld()
    D.AddChain(D.Current(), { 11, 12 }, "icon", 0, 0)
    Ed.Changed(); stub.RunTimers()
    T.truthy(_G.DaylightUICdmEditor:IsShown())
    T.eq(ess[1]:GetAlpha(), 0, "the game's item steps aside")
    T.truthy(AB.CdmRows.editing)
    Ed.Close(); stub.RunTimers()
    T.falsy(_G.DaylightUICdmEditor:IsShown())
    T.eq(ess[1]:GetAlpha(), 1, "back")
    stub.EnterCombat()
    T.falsy(Ed.Open(), "not in combat")
    stub.LeaveCombat()
    Ed.Open()
    stub.EnterCombat()
    T.falsy(Ed.IsOpen(), "a fight closes it")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm switched off: the game's Cooldown Manager and its /cdm are left alone", function()
    local gameOpened = false
    stub.Load({ actionbars = true, login = false, before = function()
        fakeRegistry()
        fakeViewer("EssentialCooldownViewer", { 11, 12 })
        _G.SLASH_COOLDOWNVIEWER1 = "/cdm"
        _G.SlashCmdList.COOLDOWNVIEWER = function() gameOpened = true end
    end })
    local mods = DaylightUIDB.profileData[DaylightUI.DB.DEFAULT].modules
    mods.ActionBars = mods.ActionBars or {}
    mods.ActionBars.cooldowns = false
    stub.FireEvent("PLAYER_LOGIN")
    local AB = stub.actionbars
    T.falsy(AB.Cooldowns.enabled, "never started")
    SlashCmdList.COOLDOWNVIEWER("")
    T.truthy(gameOpened, "/cdm is still the game's")
    T.falsy(AB.CdmEditor.Open(), "the editor stays shut")
    T.truthy(stub.ChatContains("switch it on"), "and says why")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a bar preview follows its Show name and Name position", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddPiece(set, 21, "bar", 0, 0)
    Ed.Changed(); stub.RunTimers()
    local f
    for _, c in ipairs(stub.Children(Ed.Overlay())) do if c.id == 21 then f = c end end
    T.truthy(f, "the preview piece")
    T.eq(select(1, f.name:GetPoint(1)), "LEFT", "left by default")
    T.eq(f.name:GetAlpha(), 1)
    T.truthy(D.SetSpellValue(set, 21, "nameAlign", "center"))
    Ed.Changed(); stub.RunTimers()
    T.eq(select(1, f.name:GetPoint(1)), "CENTER", "centred")
    T.eq(f.name:GetJustifyH(), "CENTER")
    T.truthy(D.SetSpellValue(set, 21, "nameAlign", "left"))
    T.truthy(D.SetSpellValue(set, 21, "showName", false))
    Ed.Changed(); stub.RunTimers()
    T.eq(select(1, f.name:GetPoint(1)), "LEFT", "back on the left")
    T.eq(f.name:GetAlpha(), 0, "hidden")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the tray lists every spell once, placed ones marked, other talents on a switch", function()
    local DUI, AB, Ed, D = edWorld()
    D.AddPiece(D.Current(), 12, "icon", 0, 0)
    local ids, placed = {}, {}
    for _, e in ipairs(Ed.Spells()) do ids[#ids + 1] = e.id; placed[e.id] = e.placed end
    T.deq(ids, { 11, 12, 13, 21, 22 })
    T.truthy(placed[12]); T.falsy(placed[11])
    Ed.SetShowUnlearned(true)
    local last = Ed.Spells()[6]
    T.eq(last.id, 14); T.truthy(last.unlearned)
    Ed.SetQuery("spell 113")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's cooldown list also holds items with no spell (CooldownViewerItemData.lua):
-- an equipment slot (trinkets) or a spell category (potions, healthstones).
T.test("cdm editor: a trinket slot or potion cooldown shows its item's or the game's name and icon", function()
    local DUI, AB, Ed, D = edWorld()
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        if id == 12 then return { equipSlot = 13, linkedSpellIDs = {} } end
        if id == 13 then return { spellCategoryID = 30, linkedSpellIDs = {} } end
        return { spellID = 100 + id }
    end
    local oldID, oldItem = _G.GetInventoryItemID, _G.C_Item
    _G.GetInventoryItemID = function(_, slot) return slot == 13 and 5000 or nil end
    _G.C_Item = setmetatable({ GetItemNameByID = function(item) return item == 5000 and "Lucky Charm" or nil end },
        { __index = oldItem })
    T.eq(Ed.SpellName(12), "Lucky Charm")
    T.eq(Ed.SpellTexture(12), "tex:13", "the equipped item's icon")
    T.truthy(Ed.SpellName(13), "a potion has a name")
    T.eq(Ed.SpellTexture(13), "Interface/ICONS/INV_POTION_54", "the game's potion icon")
    local names = {}
    for _, e in ipairs(Ed.Spells()) do names[e.id] = e.name end
    T.eq(names[12], "Lucky Charm"); T.truthy(names[13] ~= "", "listed with a name")
    -- Empty trinket slots used to show as "?" on every character.
    _G.GetInventoryItemID = function() return nil end
    local listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.falsy(listed[12], "an empty trinket slot isn't in the tray")
    T.truthy(listed[13], "a potion has no slot: still listed")
    D.AddPiece(D.Current(), 12, "icon", 0, 0)
    listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.truthy(listed[12], "a placed one stays, so it can be removed")
    _G.GetInventoryItemID, _G.C_Item = oldID, oldItem
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Three "Unknown spell" cooldowns with "?" icons showed in the tray. The game names
-- an entry by its tooltip override, then its override, then its base spell
-- (GetSpellID in CooldownViewerItemData.lua). One with no name and no icon is nothing to pick.
T.test("cdm editor: a cooldown named by its override spell; one with no name or icon isn't in the tray", function()
    local DUI, AB, Ed, D = edWorld()
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        if id == 11 then return { spellID = 999, overrideSpellID = 111, linkedSpellIDs = {} } end
        if id == 12 then return { spellID = 998, linkedSpellIDs = {} } end
        if id == 13 then return { spellID = 997, overrideTooltipSpellID = 113, overrideSpellID = 996, linkedSpellIDs = {} } end
        return { spellID = 100 + id }
    end
    local old = _G.C_Spell
    local gone = { [999] = true, [998] = true, [997] = true, [996] = true }
    _G.C_Spell = setmetatable({
        GetSpellName = function(sid) if not gone[sid] then return old.GetSpellName(sid) end end,
        GetSpellTexture = function(sid) if not gone[sid] then return old.GetSpellTexture(sid) end end,
    }, { __index = old })
    T.eq(Ed.SpellName(11), old.GetSpellName(111), "the override spell's name")
    T.eq(Ed.SpellTexture(11), old.GetSpellTexture(111), "and its icon")
    T.eq(Ed.SpellName(13), old.GetSpellName(113), "the tooltip override first, as the game")
    local listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.truthy(listed[11]); T.truthy(listed[13])
    T.falsy(listed[12], "no name, no icon: not in the tray")
    D.AddPiece(D.Current(), 12, "icon", 0, 0)
    listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.truthy(listed[12], "a placed one stays, so it can be removed")
    _G.C_Spell = old
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: click a tray spell, pick a shape: it lands free and picked; a placed one is picked", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Choose(21)
    T.eq(Ed.Pending().kind, "bar", "the game's shape known")
    Ed.Pick("icon")
    local p = D.Current().pieces[21]
    T.eq(p.shape, "icon"); T.truthy(p.x and p.y)
    T.eq(Ed.Selected(), 21)
    T.isnil(Ed.Pending())
    Ed.Choose(11); Ed.Pick("bar")
    local b11, b21 = D.Layout(D.Current())[11], D.Layout(D.Current())[21]
    T.truthy(b11.x >= b21.x + b21.w or b11.y - b11.h >= b21.y or b21.y - b21.h >= b11.y, "a free spot, not on top")
    Ed.Choose(21)
    T.isnil(Ed.Pending(), "placed: no chooser")
    T.eq(Ed.Selected(), 21)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: + on a side, then a spell: it hangs off that side", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Choose(11); Ed.Pick("icon")
    Ed.SetAttach(11, "down")
    T.deq(Ed.Attach(), { id = 11, side = "down" })
    Ed.Choose(21); Ed.Pick("bar")
    local p = D.Current().pieces[21]
    T.eq(p.parent, 11); T.eq(p.side, "down"); T.eq(p.align, "start")
    T.isnil(Ed.Attach())
    Ed.SetAttach(11, "right"); Ed.Choose(12); Ed.Pick("icon")
    T.eq(D.Current().pieces[12].align, "center", "beside, same shape: centered")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: drag moves a chain, drops near a side to hook, drags off to unhook", function()
    local DUI, AB, Ed, D = edWorld()
    DUI:Set("general", "gridSnap", false)    -- the grid has its own test
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    D.AddPiece(set, 13, "icon", 300, 0)
    Ed.Changed()
    -- A press that doesn't move is a click.
    Ed.StartDrag(11, 10, -10); Ed.DragTo(11, -11); Ed.Drop()
    T.eq(Ed.Selected(), 11); T.eq(set.pieces[11].x, 0)
    -- The chain moves with its first piece.
    Ed.StartDrag(11, 10, -10); Ed.DragTo(110, -60); Ed.Drop()
    T.eq(set.pieces[11].x, 100); T.eq(set.pieces[11].y, -50)
    T.eq(D.Layout(set)[12].x, 140, "12 came along")
    -- 13 dropped right beside 12 stays free: only a + makes a group.
    Ed.StartDrag(13, 300, 0); Ed.DragTo(184, -50); Ed.Drop()
    T.isnil(set.pieces[13].parent, "never joined by a drag")
    -- 12 dragged: the whole group moves, still a group, 12 picked.
    local before = set.pieces[11].y
    Ed.StartDrag(12, 150, -60); Ed.DragTo(150, -360); Ed.Drop()
    T.eq(set.pieces[12].parent, 11, "never split by a drag")
    T.eq(set.pieces[11].y, before - 300)
    T.eq(Ed.Selected(), 12)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a tray spell dragged up asks its shape and lands centered where it was dropped", function()
    local DUI, AB, Ed, D = edWorld()
    DUI:Set("general", "gridSnap", false)    -- the grid has its own test
    Ed.StartTrayDrag(11, 0, -400); Ed.DragTo(50, 100); Ed.Drop(false)
    T.eq(Ed.Pending().id, 11)
    Ed.Pick("icon")
    local p = D.Current().pieces[11]
    T.eq(p.x, 32); T.eq(p.y, 118)
    Ed.StartTrayDrag(12, 0, -400); Ed.DragTo(0, -300); Ed.Drop(true)
    T.isnil(Ed.Pending(), "dropped back on the tray: called off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A piece dropped under the tray could never be picked again, because the tray
-- sat over it and didn't move.
T.test("cdm editor: the tray drags out of the way, stays on screen, keeps its spot; a moving piece sees through it", function()
    local DUI, AB, Ed, D = edWorld()
    local tray = Ed.Tray()
    local function at() local _, _, _, x, y = tray:GetPoint(1); return { x, y } end
    T.deq(at(), { 0, Ed.TRAY_EDGE }, "first at the bottom")
    Ed.StartTrayMove(0, -520); Ed.MoveTray(100, -100); Ed.EndTrayMove()
    T.deq(at(), { 100, Ed.TRAY_EDGE + 420 })
    Ed.MoveTray(900, 900)
    T.deq(at(), { 100, Ed.TRAY_EDGE + 420 }, "let go: a move does nothing")
    -- Kept whole on the screen.
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    Ed.StartTrayMove(0, 0); Ed.MoveTray(5000, 5000); Ed.EndTrayMove()
    T.deq(at(), { (sw - tray:GetWidth()) / 2, sh - tray:GetHeight() })
    Ed.StartTrayMove(0, 0); Ed.MoveTray(-9000, -9000); Ed.EndTrayMove()
    T.deq(at(), { -(sw - tray:GetWidth()) / 2, 0 })
    -- Remembered for the next open.
    Ed.StartTrayMove(0, 0); Ed.MoveTray(-200, 300); Ed.EndTrayMove()
    local keep = at()
    Ed.Close(); Ed.Open()
    T.deq(at(), keep)
    T.deq(DUI.DB.Root().cdmTray, { x = keep[1], y = keep[2] })
    -- A piece on the move: the tray, title and banner turn see-through.
    D.AddPiece(D.Current(), 11, "icon", 0, 0)
    Ed.Changed()
    Ed.StartDrag(11, 10, -10); Ed.DragTo(60, -400)
    T.eq(tray:GetAlpha(), Ed.FADED)
    Ed.Drop()
    T.eq(tray:GetAlpha(), 1)
    -- A tray spell carried up keeps the tray solid (dropping back calls it off).
    Ed.StartTrayDrag(12, 0, -400); Ed.DragTo(0, -300)
    T.eq(tray:GetAlpha(), 1)
    Ed.Drop(true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: Delete removes the picked piece, Escape steps back then closes", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Choose(11); Ed.Pick("icon")
    local key = _G.DaylightUICdmEditor:GetScript("OnKeyDown")
    key(_G.DaylightUICdmEditor, "DELETE")
    T.isnil(D.Current().pieces[11]); T.isnil(Ed.Selected())
    Ed.Choose(12)
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.isnil(Ed.Pending()); T.truthy(Ed.IsOpen(), "first the chooser")
    Ed.Choose(12); Ed.Pick("icon"); Ed.SetAttach(12, "up")
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.isnil(Ed.Attach()); T.truthy(Ed.IsOpen(), "then the waiting +")
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.isnil(Ed.Selected()); T.truthy(Ed.IsOpen(), "then the picked piece (its card)")
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.falsy(Ed.IsOpen(), "then Done")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: the card's setters check, clamp, and drop a value that's the same as what it falls back to", function()
    local D = data()
    local set = filled(D)
    D.AddPiece(set, 21, "bar", 0, -100)
    -- an icon's own size is the piece's size, and setting the chain's size removes it
    T.truthy(D.SetLook(set, 12, "size", 100))
    T.eq(set.pieces[12].size, 64, "clamped")
    T.eq(D.Layout(set)[12].w, 64)
    T.truthy(D.SetLook(set, 12, "size", 36))
    T.isnil(set.pieces[12].size, "same as the chain: gone")
    -- for the whole chain, every piece's own value of that key goes
    D.SetLook(set, 13, "size", 20)
    T.truthy(D.SetLook(set, 11, "size", 30, true))
    T.eq(set.chains[11].look.size, 30); T.isnil(set.pieces[13].size)
    T.eq(D.Layout(set)[13].w, 30)
    -- a switch off stays off
    T.truthy(D.SetLook(set, 21, "time", false))
    T.eq(set.pieces[21].look.time, false)
    T.falsy(D.SetLook(set, 21, "time", "yes"), "not a switch value")
    T.falsy(D.SetLook(set, 21, "nope", 1))
    -- spacing: every piece's own gaps go
    set.pieces[12].gap = 9
    T.truthy(D.SetChainValue(set, 11, "spacing", 10))
    T.isnil(set.pieces[12].gap)
    T.eq(D.Layout(set)[12].x, 40, "30 + 10")
    T.truthy(D.SetChainValue(set, 12, "spacing", 4))
    T.isnil(set.chains[11].spacing, "the default: gone")
    T.falsy(D.SetChainValue(set, 11, "grow", "sideways"))
    -- a hooked piece's line-up and gap (a free one has none)
    T.truthy(D.SetHookValue(set, 12, "gap", 12))
    T.eq(set.pieces[12].gap, 12)
    T.truthy(D.SetHookValue(set, 12, "align", "end"))
    T.falsy(D.SetHookValue(set, 11, "gap", 2), "not hooked")
    -- spell options: the piece's shape decides, and defaults are dropped
    T.falsy(D.SetSpellValue(set, 11, "showName", false), "bars only")
    T.truthy(D.SetSpellValue(set, 21, "showName", false))
    T.eq(set.pieces[21].showName, false)
    T.truthy(D.SetSpellValue(set, 11, "onCd", "fade"))
    T.truthy(D.SetSpellValue(set, 11, "cdAlpha", 5))
    T.eq(set.pieces[11].cdAlpha, 1)
    T.truthy(D.SetSpellValue(set, 11, "onCd", "show"))
    T.isnil(set.pieces[11].onCd)
    T.truthy(D.SetShape(set, 11, "bar"))
    T.eq(set.pieces[11].shape, "bar")
    T.falsy(D.SetShape(set, 11, "round"))
end)

T.test("cdm editor: a picked piece gets the card beside its chain; its rows write the piece", function()
    local DUI, AB, Ed, D = edWorld()
    local Card = AB.CdmCard
    Ed.Choose(11); Ed.Pick("icon")
    T.truthy(Card.Shown(), "picked on add: the card is up")
    -- every tab draws for an icon and a bar
    for _, shape in ipairs({ "icon", "bar" }) do
        D.SetShape(D.Current(), 11, shape); Ed.Changed()
        for _, t in ipairs(Card.TABS) do Card.SetTab(t) end
    end
    Card.SetTab("look")
    -- the rows' items read and write the picked piece
    local function item(t, key)
        for _, r in ipairs(Card.ROWS[t]) do if r.item and r.item.key == key then return r.item end end
    end
    item("look", "cdm.card.width").set(300)
    T.eq(D.Current().pieces[11].look.width, 300)
    T.eq(item("look", "cdm.card.width").get(), 300)
    item("chain", "cdm.card.chain.combat").set(true)
    T.eq(D.Current().chains[11].combat, true)
    item("show", "cdm.card.readyGlow").set(true)
    T.eq(D.Current().pieces[11].readyGlow, true)
    -- a drag puts it away, a click on nothing too
    Ed.StartDrag(11, 0, 0); Ed.DragTo(50, 0)
    T.falsy(Card.Shown(), "away while dragging")
    Ed.Drop()
    T.truthy(Card.Shown(), "back after the drop")
    Ed.Select(nil)
    T.falsy(Card.Shown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the grid shows while it's open, a free drop lands on it, a magnet snap wins", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 13, "icon", 300, -5)
    Ed.Changed()
    T.truthy(DUI.DB.General().gridSnap, "on by default")
    T.truthy(DUI.Movers.Grid():IsShown(), "the unlock grid, behind the pieces")
    -- dropped free: its corner on the nearest grid line
    Ed.StartDrag(11, 10, -10); Ed.DragTo(110, -60); Ed.Drop()
    T.eq(set.pieces[11].x, 96); T.eq(set.pieces[11].y, -48)
    -- the magnet lined its top up with 13's, so that axis stays and the other snaps to the grid
    Ed.StartDrag(11, 110, -60); Ed.DragTo(214, -20); Ed.Drop()
    T.eq(set.pieces[11].y, -5, "13's top, off the grid")
    T.eq(set.pieces[11].x, 208)
    -- a tray drop lands on the grid too
    Ed.StartTrayDrag(12, 0, -400); Ed.DragTo(50, 100); Ed.Drop(false); Ed.Pick("icon")
    T.eq(set.pieces[12].x, 32); T.eq(set.pieces[12].y, 112)
    -- the pill's switches are unlock mode's
    local snap, mag = Ed.SnapButtons()
    T.truthy(snap.active); T.truthy(mag.active)
    snap:Click()
    T.falsy(DUI.DB.General().gridSnap)
    T.falsy(snap.active)
    T.falsy(DUI.Movers.Grid():IsShown(), "off: no grid")
    Ed.StartDrag(11, 0, 0); Ed.DragTo(-101, 3); Ed.Drop()
    T.eq(set.pieces[11].x, 107, "grid off: where it was let go")
    mag:Click()
    T.falsy(DUI.DB.General().magnet)
    snap:Click()
    T.truthy(DUI.Movers.Grid():IsShown())
    Ed.Close()
    T.falsy(DUI.Movers.Grid():IsShown(), "gone with the editor")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the top bar holds every button once the talent set's label is in", function()
    local DUI, AB, Ed, D = edWorld()
    local pill = Ed.Pill()
    local snap, mag = Ed.SnapButtons()
    -- edges 14, title, 14, then the buttons 8 apart
    local wide, n = 14 + 14 + 14, 0
    for _, r in ipairs({ pill:GetRegions() }) do
        if r.GetText and r:GetText() == "Cooldown layout" then wide = wide + r:GetStringWidth() end
    end
    for _, b in ipairs({ pill:GetChildren() }) do
        if b:IsShown() and b:GetObjectType() == "Button" then wide = wide + b:GetWidth(); n = n + 1 end
    end
    wide = wide + (n - 1) * 8
    T.eq(n, 7, "talent set, import, reset, live preview, two snaps, done")
    T.truthy(pill:GetWidth() >= wide, "bar " .. pill:GetWidth() .. " vs what it holds " .. wide)
    T.truthy(snap:GetWidth() > 0 and mag:GetWidth() > 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: arrow keys nudge the picked chain (Shift: a grid step); the card's Position row too", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    Ed.Changed()
    local o = _G.DaylightUICdmEditor
    local key = o:GetScript("OnKeyDown")
    key(o, "RIGHT")
    T.eq(set.pieces[11].x, 0, "nothing picked: the key isn't ours")
    Ed.Select(12)
    key(o, "RIGHT"); key(o, "UP")
    T.eq(set.pieces[11].x, 1, "the hooked piece moves its whole chain")
    T.eq(set.pieces[11].y, 1)
    key(o, "LEFT"); key(o, "DOWN")
    T.eq(set.pieces[11].x, 0); T.eq(set.pieces[11].y, 0)
    _G.IsShiftKeyDown = function() return true end
    key(o, "RIGHT")
    _G.IsShiftKeyDown = nil
    T.eq(set.pieces[11].x, 16, "Shift: one grid step")
    T.eq(set.pieces[12].parent, 11, "still hooked")
    -- the card's Chain tab: nudges and X/Y
    local Card = AB.CdmCard
    Card.SetTab("chain")
    local pos = Card.Position()
    T.truthy(pos:IsShown())
    pos.right:Click(); pos.up:Click()
    T.eq(set.pieces[11].x, 17); T.eq(set.pieces[11].y, 1)
    -- X and Y are the whole group's middle, as unlock mode's are a frame's.
    -- Two 36 px icons 4 apart are 76 wide and 36 high.
    T.eq(pos.x:GetText(), "55"); T.eq(pos.y:GetText(), "-17")
    pos.x:SetText("0"); pos.y:SetText("0")
    pos.x:GetScript("OnEnterPressed")(pos.x)
    T.eq(set.pieces[11].x, -38, "0 = centered on the screen"); T.eq(set.pieces[11].y, 18)
    T.eq(pos.x:GetText(), "0"); T.eq(pos.y:GetText(), "0")
    pos.x:SetText("abc")
    pos.x:GetScript("OnEnterPressed")(pos.x)
    T.eq(set.pieces[11].x, -38, "not a number: unchanged")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a piece dragged past a group follows the cursor, no hopping line to line", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    D.AddPiece(set, 14, "icon", -60, 60)
    Ed.Changed()
    local fx, fy = -60, 60
    Ed.StartDrag(14, 0, 0)
    local worst, off, last = 0, 0, nil
    for x = 0, 240 do               -- along the top of the group
        Ed.DragTo(x, 0)
        local px = set.pieces[14].x
        if last then worst = math.max(worst, math.abs(px - last)) end
        if px ~= fx + x then off = off + 1 end
        last = px
    end
    Ed.Drop()
    T.truthy(worst <= 4, "biggest jump for 1 px of mouse: " .. worst)
    T.truthy(off <= 120, "steps pulled off the cursor, of 240: " .. off)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a waiting + puts the card away and grows the tray, then both come back", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11 }, "icon", 0, 0)
    Ed.Changed()
    local Card = AB.CdmCard
    local function settle()
        local d = DUI.Motion.Driver()
        local tick = d and d:GetScript("OnUpdate")
        if tick then tick(d, 1) end
    end
    Ed.Select(11)
    T.truthy(Card.Shown(), "picked: the card")
    local w0, h0 = Ed.Tray():GetWidth(), Ed.Tray():GetHeight()
    Ed.SetAttach(11, "right"); settle()
    T.falsy(Card.Shown(), "the + waits: the card is away")
    local grown = Ed.CELL_BIG - Ed.CELL
    T.eq(Ed.Tray():GetWidth(), w0 + Ed.TRAY_COLS * grown)
    T.truthy(Ed.Tray():GetHeight() > h0, "taller too")
    T.deq({ Ed.TrayCell(1):GetSize() }, { Ed.CELL_BIG, Ed.CELL_BIG }, "bigger spells to hit")
    -- Esc: back as it was, the same piece picked.
    Ed.SetAttach(nil); settle()
    T.truthy(Card.Shown(), "called off: the card again")
    T.eq(Card.Frame():GetAlpha(), 1)
    T.eq(Ed.Tray():GetWidth(), w0); T.eq(Ed.Tray():GetHeight(), h0)
    -- A spell picked: it joins, the tray settles, the card is the new one's.
    Ed.SetAttach(11, "right"); settle()
    Ed.Choose(12); Ed.Pick("icon"); settle()
    T.eq(set.pieces[12].parent, 11)
    T.eq(Ed.Selected(), 12)
    T.truthy(Card.Shown()); T.eq(Card.Frame():GetAlpha(), 1)
    T.eq(Ed.Tray():GetWidth(), w0)
    -- Closed mid-wait: it opens at its normal size.
    Ed.SetAttach(12, "right"); settle()
    Ed.Close(); Ed.Open()
    T.eq(Ed.Tray():GetWidth(), w0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: X and Y of three in a row are the exact middle of the center one", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", -100, 50)
    Ed.Changed()
    Ed.Select(13)
    local b = D.Layout(set)[12]
    local x, y = Ed.Spot()
    T.eq(x, b.x + b.w / 2); T.eq(y, b.y - b.h / 2)
    Ed.MoveTo(0, 0)
    b = D.Layout(set)[12]
    T.eq(b.x + b.w / 2, 0, "0 puts the center spell on the screen's middle")
    T.eq(b.y - b.h / 2, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a waiting + asks right on the tray, where you're about to look", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Changed()
    local o = _G.DaylightUICdmEditor
    local banner = Ed.Banner()
    local function settle()
        local d = DUI.Motion.Driver()
        local tick = d and d:GetScript("OnUpdate")
        if tick then tick(d, 1) end
    end
    Ed.Select(11)
    Ed.SetAttach(11, "left"); settle()
    T.truthy(banner:IsShown())
    local p1, to, p2 = banner:GetPoint(1)
    T.eq(to, Ed.Tray(), "on the tray, not up by the title")
    T.eq(p1, "BOTTOM"); T.eq(p2, "TOP")
    T.eq(banner:GetAlpha(), 1)
    T.truthy(string.find(banner.text:GetText(), "|cff%x%x%x%x%x%xSpell %d+|r"), "the spell's name stands out")
    -- The tray dragged while it asks: the question goes along.
    Ed.StartTrayMove(0, 0); Ed.MoveTray(50, 60); Ed.EndTrayMove()
    T.eq(select(2, banner:GetPoint(1)), Ed.Tray())
    T.eq(select(2, banner.text:GetFont()), DUI.Style.SIZE.body)
    -- A tray dragged to the top of the screen: it asks under it.
    DUI.DB.Root().cdmTray = { x = 0, y = 9999 }
    Ed.Draw(); settle()
    p1, to, p2 = banner:GetPoint(1)
    T.eq(p1, "TOP"); T.eq(p2, "BOTTOM")
    DUI.DB.Root().cdmTray = nil
    -- Answered: it fades away, and the normal hints are back up top.
    Ed.SetAttach(nil); settle()
    T.falsy(banner:IsShown(), "a picked piece needs no words")
    Ed.Select(nil); settle()
    T.truthy(banner:IsShown())
    T.eq(banner:GetAlpha(), 1)
    p1, to = banner:GetPoint(1)
    T.eq(p1, "TOP"); T.truthy(to ~= Ed.Tray(), "under the title")
    T.eq(select(2, banner.text:GetFont()), DUI.Style.SIZE.small)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a + is the only way into a group, and it takes spells already placed", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    D.AddPiece(set, 13, "icon", 300, 0)
    Ed.Changed()
    -- Dropped from the tray right beside a piece: free too.
    Ed.StartTrayDrag(14, 0, -400); Ed.DragTo(100, -18); Ed.Drop(false); Ed.Pick("icon")
    T.isnil(set.pieces[14].parent, "a tray drop never joins")
    -- A placed spell picked in the tray goes to the waiting +.
    Ed.SetAttach(12, "right")
    Ed.Choose(13)
    T.eq(set.pieces[13].parent, 12); T.eq(set.pieces[13].side, "right")
    T.eq(Ed.Selected(), 13); T.isnil(Ed.Attach())
    -- So does a piece clicked on the screen.
    Ed.SetAttach(11, "down")
    Ed.StartDrag(14, 5, 5); Ed.Drop()
    T.eq(set.pieces[14].parent, 11); T.eq(set.pieces[14].side, "down")
    -- It can't go onto itself or what hangs off it: then it's only picked.
    Ed.SetAttach(13, "right")
    Ed.StartDrag(11, 5, 5); Ed.Drop()
    T.isnil(set.pieces[11].parent, "stays first")
    T.eq(Ed.Selected(), 11); T.isnil(Ed.Attach())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: MoveChain puts a chain's first piece at a spot, whole numbers only", function()
    local D = data()
    local set = filled(D)
    T.truthy(D.MoveChain(set, 12, 10.4, -20.6))
    T.eq(set.pieces[11].x, 10); T.eq(set.pieces[11].y, -21)
    T.isnil(set.pieces[12].x, "a hooked piece keeps no spot")
    T.falsy(D.MoveChain(set, 11, 0 / 0, 0))
    T.falsy(D.MoveChain(set, 11, "1", 0))
    T.falsy(D.MoveChain(set, 99, 0, 0))
end)

T.test("cdm card: the Look tab's Whole group colors every bar's background; a spell's own wins", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "bar", 0, 0)
    Ed.Select(11)
    local Card = AB.CdmCard
    local function item(t, key)
        for _, r in ipairs(Card.ROWS[t]) do if r.item and r.item.key == key then return r.item, r end end
    end
    local mode, row = item("look", "cdm.card.chain.back")
    T.truthy(mode, "a group background row on the Look tab")
    T.eq(mode.get(), "dark")
    local colour, crow = item("look", "cdm.card.chain.backColor")
    T.falsy(crow.show(set, 11, set.pieces[11]), "no color row until Solid")
    mode.set("solid")
    T.truthy(crow.show(set, 11, set.pieces[11]))
    T.eq(#colour.get(), 4, "shows a color before one is set")
    colour.set({ 1, 0, 0, 0.5 })
    T.eq(set.chains[11].look.back, "solid")
    T.eq(set.chains[11].look.backColor[1], 1)
    -- both bars take it through "Same as its group"
    local CD = AB.Cooldowns
    for _, id in ipairs({ 11, 12 }) do
        local m, c = CD.BackOf(set.pieces[id], D.PieceBlock(set, id))
        T.eq(m, "solid"); T.eq(c[4], 0.5)
    end
    -- a spell's own background wins over the group's
    T.truthy(D.SetSpellValue(set, 12, "backMode", "gradient"))
    T.eq((CD.BackOf(set.pieces[12], D.PieceBlock(set, 12))), "gradient")
    -- back to dark: the bars' dim fill color again
    mode.set("dark")
    T.isnil(set.chains[11].look.back, "the default isn't kept")
    T.isnil((CD.BackOf(set.pieces[11], D.PieceBlock(set, 11))))
    T.falsy(D.SetLook(set, 11, "back", "plaid", true))
    T.falsy(D.SetLook(set, 11, "backColor", { "red" }, true))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Slice and Dice (Buff only) with Glow when usable and Glow on proc never glowed.
-- Buff only has nothing to be usable off, and WoW Forever fires no proc alerts,
-- so those rows can't do anything.
T.test("cdm card: Usable rows only for a cooldown, and no proc glow row (Forever has no procs)", function()
    local DUI, AB, Ed, D = edWorld()
    withCategories({ [0] = { 11 }, [2] = { 12 } }, { [0] = { 11 }, [2] = { 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, hasAura = id == 11 }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    AB.CdmOwn.Forget()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local function row(key)
        for _, r in ipairs(AB.CdmCard.ROWS.show) do if r.item and r.item.key == key then return r end end
    end
    T.isnil(row("cdm.card.glow"), "no proc glow row")
    T.isnil(row("cdm.card.glowColor"), "no proc glow color row")
    set.pieces[12].usableGlow = true
    for _, key in ipairs({ "cdm.card.usableGlow", "cdm.card.usableGlowColor", "cdm.card.usableSound" }) do
        local r = row(key)
        Ed.Select(12)
        T.falsy(r.show(set, 12, set.pieces[12]), key .. ": Buff only has nothing to be usable off")
        set.pieces[11].usableGlow = true
        Ed.Select(11)
        T.truthy(r.show(set, 11, set.pieces[11]), key .. ": a cooldown does")
    end
    for _, r in ipairs(AB.CdmCard.ROWS.show) do
        if r.head == DUI.L["Usable"] then
            T.falsy(r.show(set, 12, set.pieces[12]), "the heading goes with its rows")
            T.truthy(r.show(set, 11, set.pieces[11]))
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Hide and Keep its spot were two switches for one choice, which was confusing.
T.test("cdm card: Buff up and Buff missing each have one Visibility; Buff missing's is Buff only's", function()
    local DUI, AB, Ed, D = edWorld()
    withCategories({ [0] = { 11 }, [2] = { 12 } }, { [0] = { 11 }, [2] = { 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, hasAura = id == 11 }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    AB.CdmOwn.Forget()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local function item(key)
        for _, r in ipairs(AB.CdmCard.ROWS.show) do if r.item and r.item.key == key then return r.item, r end end
    end
    local up, upRow = item("cdm.card.buffUp")
    local down, downRow = item("cdm.card.buffDown")
    local track = item("cdm.card.track")
    local _, glow = item("cdm.card.missingGlow")
    T.isnil(item("cdm.card.hideActive")); T.isnil(item("cdm.card.hideMissing")); T.isnil(item("cdm.card.missing"))
    local function on(r, id) return r.show(set, id, set.pieces[id]) end
    local q = set.pieces[12]
    -- A buff is gone while it's down unless asked otherwise, as before.
    Ed.Select(12)
    T.eq(up.get(), "show"); T.eq(down.get(), "hide")
    T.truthy(on(downRow, 12)); T.falsy(on(glow, 12), "nothing shows, so nothing to glow")
    for _, key in ipairs({ "cdm.card.readyGlow", "cdm.card.onCd", "cdm.card.desat" }) do
        local _, r = item(key)
        T.falsy(on(r, 12), key .. ": Buff only has no cooldown to act on")
        T.truthy(on(r, 11), key .. ": Cooldown and buff does")
    end
    down.set("show")
    T.eq(down.get(), "show")
    T.eq(q.missing, true); T.falsy(q.hideMissing)
    T.eq(D.PieceBlock(set, 12).always, true, "the grayed icon")
    T.eq(AB.CdmOwn.Track(12, q), "buff"); T.truthy(on(glow, 12))
    down.set("hide")
    T.eq(q.hideMissing, true); T.falsy(q.missing)
    T.eq(D.PieceBlock(set, 12).always, false)
    up.set("hide")
    T.eq(q.hideActive, true); T.eq(up.get(), "hide")
    up.set("show")
    T.falsy(q.hideActive)
    -- A saved Keep its spot and Hide together: Hide won, and still does.
    q.missing, q.hideMissing = true, true
    T.eq(down.get(), "hide")
    -- A glow saved with no Keep its spot: it shows, so the card says so.
    q.missing, q.hideMissing, q.missingGlow = nil, nil, true
    T.eq(down.get(), "show"); T.truthy(on(glow, 12))
    q.hideMissing = true
    T.eq(down.get(), "hide"); T.falsy(on(glow, 12))
    q.missingGlow = nil
    q.missing, q.hideMissing = nil, nil
    -- Cooldown and buff: its cooldown shows while the buff is down, so there's nothing to pick.
    local c = set.pieces[11]
    Ed.Select(11)
    T.eq(AB.CdmOwn.Track(11, c), "both")
    T.falsy(on(downRow, 11)); T.truthy(on(upRow, 11)); T.truthy(on(glow, 11))
    -- Buff only can, and Show holds Buff only by itself.
    track.set("buff")
    T.truthy(on(downRow, 11))
    down.set("hide")
    c.track = nil
    T.eq(AB.CdmOwn.Track(11, c), "buff", "Hide alone holds it")
    down.set("show")
    T.eq(AB.CdmOwn.Track(11, c), "buff", "Show pins it")
    track.set("both")
    T.falsy(c.missing); T.falsy(c.hideMissing)
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: When ready on the Show tab for cooldowns only, with Fade to when it fades", function()
    local DUI, AB, Ed, D = edWorld()
    withCategories({ [0] = { 11 }, [2] = { 12 } }, { [0] = { 11 }, [2] = { 12 } })
    AB.CdmOwn.Forget()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local Card = AB.CdmCard
    local function item(key)
        for _, r in ipairs(Card.ROWS.show) do if r.item and r.item.key == key then return r.item, r end end
    end
    local ready, row = item("cdm.card.onReady")
    local _, fadeRow = item("cdm.card.cdAlpha")
    T.truthy(row.show(set, 11, set.pieces[11]), "a cooldown: shown")
    T.falsy(row.show(set, 12, set.pieces[12]), "a buff: not shown (it's always ready)")
    Ed.Select(11)
    T.eq(ready.get(), "show")
    T.falsy(fadeRow.show(set, 11, set.pieces[11]))
    ready.set("fade")
    T.eq(set.pieces[11].onReady, "fade")
    T.truthy(fadeRow.show(set, 11, set.pieces[11]), "Fade to for a fading ready spell")
    ready.set("show")
    T.isnil(set.pieces[11].onReady, "the default isn't kept")
    T.falsy(D.SetSpellValue(set, 11, "onReady", "blink"))
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: stays put while its own sliders change the chain (bar width)", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11 }, "bar", -700, 0)   -- room on its right for the card, with the bar at 400 too
    Ed.Select(11)
    local Card = AB.CdmCard
    T.truthy(Card.Shown())
    local function pos() local _, _, _, x, y = Card.Frame():GetPoint(1); return x, y end
    local function settle()
        stub.RunOnUpdate(Card.Frame(), 0.1)
        local d = DUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 1) end
    end
    settle()
    local x0 = pos()
    local width
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == "cdm.card.chain.width" then width = r.item end end
    width.set(150); settle()
    T.eq((pos()), x0, "narrower: stays")
    width.set(225); settle()
    T.eq((pos()), x0, "a little wider, the + buttons still clear: stays")
    -- grown under the card, it moves clear, but not while the mouse holds one of its sliders
    local old = _G.IsMouseButtonDown
    local held = true
    _G.IsMouseButtonDown = function() return held end
    Card.Frame().IsMouseOver = function() return true end
    width.set(400); settle()
    T.eq((pos()), x0, "held: still")
    held = false; settle(); settle()
    T.truthy(pos() > x0, "let go: clear of the bar")
    _G.IsMouseButtonDown = old
    -- the chain itself moving takes the card along
    local x1 = pos()
    set.pieces[11].x = -750; Ed.Changed(); settle()
    T.truthy(pos() < x1, "follows the chain")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: an icon's Size slider stays grabbable: its row never hides on a redraw, and held, the card never moves", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", -700, 0)
    Ed.Select(11)
    local Card = AB.CdmCard
    local function pos() local _, _, _, x, y = Card.Frame():GetPoint(1); return x, y end
    local function settle()
        stub.RunOnUpdate(Card.Frame(), 0.1)
        local d = DUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 1) end
    end
    local size, row
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == "cdm.card.size" then size, row = r.item, r end end
    T.truthy(size, "the icon's Size row")
    -- Every step redraws the card, and the slider's row must never hide: in game a
    -- slider hidden mid-drag lets go of the mouse.
    local hid = 0
    row.frame:HookScript("OnHide", function() hid = hid + 1 end)
    size.set(50); settle()
    T.eq(hid, 0, "the Size row stays shown through a redraw")
    T.truthy(row.frame:IsShown())
    for _, grow in ipairs({ "start", "center", "end" }) do
        D.SetChainValue(set, 11, "grow", grow); Ed.Changed(); settle()
        local x0, y0 = pos()
        local old = _G.IsMouseButtonDown
        local held = true
        _G.IsMouseButtonDown = function() return held end
        Card.Frame().IsMouseOver = function() return true end
        for v = 40, 120, 8 do
            size.set(v); settle()
            local x, y = pos()
            T.eq(x, x0, grow .. ": held at " .. v .. ": stays under the mouse")
            T.eq(y, y0, grow .. ": held at " .. v .. ": not up or down either")
        end
        held = false; settle(); settle()
        _G.IsMouseButtonDown = old
        Card.Frame().IsMouseOver = nil
        size.set(40); settle(); settle()
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: its X only closes it; Remove from layout at the bottom takes the spell out", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    Ed.Select(12)
    local Card = AB.CdmCard
    local f = Card.Frame()
    T.truthy(Card.Shown())
    f.close:Click()
    T.falsy(Card.Shown(), "closed")
    T.isnil(Ed.Selected())
    T.truthy(set.pieces[12], "the spell stays")
    Ed.Select(12)
    T.truthy(f.remove:IsShown())
    f.remove:Click()
    T.isnil(set.pieces[12], "removed")
    T.truthy(set.pieces[11], "the rest stays")
    T.falsy(Card.Shown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the top bar's Reset empties the layout after Click again; Import opens the paste box", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local reset = Ed.PillButton("reset")
    reset:Click()
    T.truthy(D.Current().pieces[11], "the first click only asks")
    stub.Advance(1)
    reset:Click()
    T.isnil(next(D.Current().pieces), "empty")
    local opened
    DUI.Profiles.ShowPaste = function(spec) opened = spec end
    Ed.PillButton("import"):Click()
    T.truthy(opened and opened.read, "the paste box")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the picked spell's group gets an outline round all of it; a lone spell none", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    D.AddChain(set, { 21 }, "icon", 0, -100)
    Ed.Select(12)
    local g = Ed.GroupOutline()
    T.truthy(g:IsShown(), "shown round the group")
    local pad = Ed.GROUP_PAD
    T.near(g:GetWidth(), 3 * 36 + 2 * 4 + 2 * pad, 0.6, "all three spells inside")
    T.near(g:GetHeight(), 36 + 2 * pad, 0.6)
    local d = DUI.Motion.Driver()
    Ed.Select(21)
    if d then stub.RunOnUpdate(d, 1) end
    T.falsy(g:IsShown(), "a lone spell: no group outline")
    -- The colors flow round a lit outline only while the editor is open.
    T.truthy(Ed.Flowing(), "turning while a spell is picked")
    Ed.Close()
    T.falsy(Ed.Flowing(), "the editor shut: nothing runs")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: the Group tab removes the whole group, after Click again", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    D.AddChain(set, { 21 }, "icon", 0, -100)
    Ed.Select(12)
    local Card = AB.CdmCard
    local f = Card.Frame()
    T.truthy(f.remove:IsShown()); T.falsy(f.removeGroup:IsShown())
    Card.SetTab("chain")
    T.falsy(f.remove:IsShown(), "the spell's button gives way")
    T.truthy(f.removeGroup:IsShown())
    f.removeGroup:Click()
    T.truthy(set.pieces[11], "the first click only asks")
    T.eq(f.removeGroup.text:GetText(), DUI.L["Click again"])
    stub.Advance(1)
    f.removeGroup:Click()
    T.isnil(set.pieces[11]); T.isnil(set.pieces[12]); T.isnil(set.pieces[13])
    T.isnil(set.chains[11])
    T.truthy(set.pieces[21], "other groups stay")
    T.isnil(Ed.Selected())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: a taller tab (Group) moves it up so it stays on screen", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    local sh = UIParent:GetHeight() / 2
    D.AddChain(set, { 11 }, "bar", -300, -sh + 60)
    Ed.Select(11)
    local Card = AB.CdmCard
    Card.SetTab("show")
    Card.SetTab("chain")
    local d = DUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
    local f = Card.Frame()
    local _, _, _, _, y = f:GetPoint(1)
    T.truthy(y - f:GetHeight() >= -sh + 8, "its bottom on screen")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm options: each talent set picks a profile; New, Copy, Rename and Delete act on the one in use", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Close()
    stub.units.player = stub.units.player or { isPlayer = true, name = "Tester" }
    stub.units.player.class = "WARRIOR"
    local items = {}
    for _, g in ipairs(DUI.Options.GetPage("cdm.layout").groups) do
        for _, it in ipairs(g.items) do items[it.key or it.label] = it end
    end
    local get = function(k) return DUI:Get("ActionBars", k) end
    T.falsy(items["Edit layout"].disabled(get), "on by default")
    -- The name box answers at once here.
    local answer
    DUI.Widgets.Prompt = function(_, _, onAccept) onAccept(answer) end
    for _, k in ipairs({ "cdm.copy", "cdm.rename", "cdm.delete" }) do
        T.truthy(items[k].disabled(get), k .. ": no profile yet")
    end
    answer = "Tank"
    items["cdm.new"].func()
    local tank = D.Use(DUI.DB.SpecGroup())
    T.eq(D.Profile(tank).name, "Tank")
    D.AddChain(D.Get(1), { 11, 12 }, "icon", 10, 20)
    answer = "Tank copy"
    items["cdm.copy"].func()
    local copy = D.Use(1)
    T.truthy(copy ~= tank, "the copy is in use now")
    T.eq(D.Get(1).pieces[12].parent, 11)
    local values, order = items["cdm.use2"].choices()
    T.eq(values.none, DUI.L["None"])
    T.eq(#order, 3, "None and both profiles")
    items["cdm.use2"].set(tank)
    T.eq(D.Use(2), tank)
    T.eq(items["cdm.use2"].get(), tank)
    answer = "Prot"
    items["cdm.rename"].func()
    T.eq(D.Profile(copy).name, "Prot")
    items["cdm.delete"].func()
    T.isnil(D.Profile(copy))
    T.eq(items["cdm.use1"].get(), "none")
    T.eq(D.Use(2), tank, "the other set keeps its own")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The addon's own spell list (CdmSpells, made by tools/make_cdm_spells.py)

T.test("cdm spells: every class has families of ids, no id twice in a class, group buffs name their class", function()
    stub.Load({ actionbars = true })
    local S = stub.actionbars.CdmSpells
    T.truthy(type(S) == "table", "the list loads")
    for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local list = S[token]
        T.truthy(type(list) == "table" and #list > 10, token .. " has spells")
        local seen = {}
        for _, f in ipairs(list) do
            T.truthy(#f >= 1, token .. ": a family has ids")
            T.truthy(f.cd or f.aura, token .. ": every family has a cooldown or a duration")
            for _, id in ipairs(f) do
                T.truthy(type(id) == "number" and id > 0, token .. ": a spell id")
                T.isnil(seen[id], token .. ": id " .. tostring(id) .. " in one family only")
                seen[id] = true
            end
        end
    end
    T.truthy(#S.GROUP >= 8, "group buffs")
    for _, f in ipairs(S.GROUP) do T.truthy(type(f.class) == "string" and #f >= 1, "a group buff names its class") end
    local shout
    for _, f in ipairs(S.WARRIOR) do if f[1] == 6673 then shout = f end end
    T.truthy(shout and shout.aura, "Battle Shout puts up a buff")
    T.eq(#shout, 7, "every rank of it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: our own spell keys sit beside the game's ids: layout, order, track, copy", function()
    local _, D = profileWorld()
    local set = empty()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, "s6673", "bar", 0, -48)
    D.AddPiece(set, "s2687", "icon", 100, 0)
    T.truthy(D.Hook(set, "s2687", 11, "right"))
    local L = D.Layout(set)
    T.deq(box(L["s2687"]), { 40, 0, 36, 36 }, "hung off a game id")
    T.deq(box(L["s6673"]), { 0, -48, 220, 18 })
    T.deq(D.Index(set).roots, { 11, "s6673" }, "numbers first, then ours")
    local keys = { "s9", 30, "s10", 4 }
    table.sort(keys, D.ByKey)
    T.deq(keys, { 4, 30, "s10", "s9" })
    T.truthy(D.SetTrack(set, "s2687", "aura"))
    T.eq(set.pieces["s2687"].track, "aura")
    T.falsy(D.SetTrack(set, 11, "aura"), "a game id has no track")
    T.truthy(D.SetTrack(set, "s2687", "both"))
    T.falsy(D.SetTrack(set, "s2687", "buff"), "a bad value")
    D.SetTrack(set, "s2687", "aura")
    T.falsy(D.SetTrack(set, "s1", "aura"), "not placed")
    local to = D.Profile(D.CopyProfile(D.NewProfile("Mine", nil, set))).set
    T.eq(to.pieces["s2687"].track, "aura", "copied with the rest")
    T.eq(to.pieces["s2687"].parent, 11)
end)

-- A warrior with Battle Shout (two of three ranks), Bloodrage (cooldown and
-- buff) and Sweeping Strikes (not learned), and Fortitude from a priest.
local function customWorld(class)
    stub.Load({ actionbars = true })
    stub.SetUnits({ player = { class = class or "WARRIOR" } })
    local AB = stub.actionbars
    AB.CdmSpells.WARRIOR = {
        { 6673, 5242, 6192, aura = true },
        { 2687, cd = true, aura = true },
        { 12292, cd = true },
    }
    AB.CdmSpells.GROUP = { { 1243, 1244, class = "PRIEST" } }
    stub.knownSpells = { [6673] = true, [5242] = true, [2687] = true }
    AB.CdmCustom.Forget()
    return AB, AB.CdmCustom, AB.CdmData
end

-- Arcane Blast's casts only do damage. Its stack is another spell (400573), a
-- debuff on the mage, watched on you among buffs and debuffs, never on the target.
T.test("cdm custom: a spell whose debuff lands on you is watched among your debuffs, by the debuff's id", function()
    local AB, C = customWorld("MAGE")
    AB.CdmSpells.MAGE = { { 400574, 1239696, aura = true }, { 116, 205, aura = true } }
    stub.knownSpells = { [400574] = true, [116] = true }
    C.Forget()
    T.deq(C.Ranks("s400574"), { [400574] = true, [1239696] = true, [400573] = true }, "the ranks and the stack's own id")
    T.truthy(C.SelfDebuff("s400574")); T.truthy(C.SelfOnly("s400574"))
    T.falsy(C.SelfDebuff("s116"), "Frostbolt's is on the target")
    T.eq(C.SpellOf("s400574"), 400574, "the stack's id is never the spell shown")
    T.eq(C.KeyOfAuraSpell(400573), nil, "nor a rank of it")
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s400574")
    -- The client's container showed nothing for it in game, so the addon draws it.
    T.eq(#h.containers, 0, "no client container")
    T.truthy(h.face, "our own icon")
    T.truthy(h.ids[400573], "read by the stack's id")
    -- Its text isn't loaded and never read, yet it's still 18 s and 4 stacks from the game's data.
    C_Spell.GetSpellDescription = function() return nil end
    AB.CdmAuras.Track(h)
    for i = 1, 6 do stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c" .. i, 1239696) end
    stub.RunTimers()
    T.eq(h.selfStacks, 4, "4 at most")
    T.truthy(h.endsAt and math.abs(h.endsAt - GetTime() - 18) < 0.01, "18 s from the first cast")
    stub.Advance(18.1); stub.RunTimers()
    T.eq(h.up, false, "then gone")
    local f = CreateFrame("Frame", nil, UIParent)
    f.size = 30
    AB.CdmAuras.Setup(f, "s116")
    T.eq(f.containers[2].unit, "target"); T.eq(f.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
end)

-- Weakened Soul (6788), added by its ID: a debuff your own shield puts on you or
-- on the friend you shielded. Watched among your debuffs too.
T.test("cdm custom: a spell added by its ID is watched among your own debuffs too", function()
    local AB, C = customWorld("PRIEST")
    C.Forget()
    T.truthy(C.IsAdded("s6788"))
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s6788")
    local seen = {}
    for _, k in ipairs(h.containers) do seen[k.unit .. " " .. k.c.__groups.a.filter] = true end
    T.truthy(seen["player HELPFUL"], "your buffs")
    T.truthy(seen["player HARMFUL|PLAYER"], "your debuffs: a self-shield's Weakened Soul")
    T.truthy(seen["target HARMFUL|PLAYER"], "your target's, from you")
end)

-- The spot opened while Weakened Soul was up but stayed empty. The client's
-- containers refuse to pick a debuff on you (or any friend) by spell id unless
-- the spell is never secret (AuraContainerUtil.CanApplyIdentityCandidateFilters,
-- tests/aura_rules.lua), so the debuff group goes by what's left: yours, and no
-- longer than it lasts.
T.test("cdm custom: a debuff on you really shows in its container (never picked by spell id)", function()
    local shows = require("aura_rules")
    local AB, C = customWorld("PRIEST")
    C.Forget()
    local you = { canAssist = true, groupMember = true }
    local function debuffGroup(h)
        for _, k in ipairs(h.containers) do
            local g = k.c.__groups.a
            if k.unit == "player" and g.filter:find("HARMFUL") then return g end
        end
    end
    C_Spell.GetSpellDescription = function(sid)
        if sid == 6788 then return "Cannot be shielded again for 15 sec." end
    end
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s6788")
    local g = debuffGroup(h)
    T.truthy(g, "a debuff group on you")
    T.truthy(shows(g, you, { spellId = 6788, harmful = true, mine = true, duration = 15 }),
        "your Weakened Soul shows")
    T.falsy(shows(g, you, { spellId = 115, harmful = true, mine = false, duration = 15 }),
        "a mob's debuff on you doesn't")
    T.falsy(shows(g, you, { spellId = 2096, harmful = true, mine = true, duration = 60 }),
        "a longer one of yours (Recently Bandaged) doesn't")
    -- A spell the client calls never secret may still go by its id.
    stub.neverSecretAuras = { [6788] = true }
    local n = CreateFrame("Frame", nil, UIParent)
    n.size = 30
    AB.CdmAuras.Setup(n, "s6788")
    local ng = debuffGroup(n)
    T.truthy(shows(ng, you, { spellId = 6788, harmful = true, mine = true, duration = 15, neverSecret = true }))
    T.falsy(shows(ng, you, { spellId = 2096, harmful = true, mine = true, duration = 15, neverSecret = true }),
        "by its id: nothing else")
    stub.neverSecretAuras = {}
end)

T.test("cdm custom: our keys, the highest known rank, every rank, the track", function()
    local AB, C, D = customWorld()
    T.truthy(C.Is("s6673")); T.falsy(C.Is(6673)); T.falsy(C.Is("6673")); T.falsy(C.Is("s"))
    T.eq(C.SpellOf("s6673"), 5242, "the highest rank you know")
    T.deq(C.Ranks("s6673"), { [6673] = true, [5242] = true, [6192] = true }, "every rank, known or not")
    T.isnil(C.Entry("s12292"), "not learned: nothing to draw")
    T.eq(C.SpellOf("s12292"), 12292, "rank 1 for its look")
    T.truthy(C.Entry("s1243") and C.Entry("s1243").aura, "a group buff counts as known, a buff")
    T.truthy(C.SelfOnly("s1243")); T.falsy(C.SelfOnly("s6673"))
    T.falsy(C.Entry("s2687").aura, "a spell with both: its cooldown first")
    T.truthy(C.CanTrack("s2687")); T.truthy(C.CanTrack("s6673"), "a buff of yours can pick too")
    T.falsy(C.CanTrack("s1243"), "a group buff: no cooldown of yours")
    local set = D.Current()
    D.AddPiece(set, "s2687", "icon", 0, 0)
    T.truthy(D.SetTrack(set, "s2687", "aura"))
    T.truthy(C.Entry("s2687").aura, "the piece's pick")
    D.AddPiece(set, "s6673", "icon", 40, 0)
    T.eq(C.Track("s6673"), "aura", "left alone, a buff")
    D.SetTrack(set, "s6673", "cooldown")
    T.eq(C.Track("s6673"), "cooldown", "the player's pick")
    D.SetTrack(set, "s6673", "aura")
    T.truthy(C.IsAdded("s1953"), "not in the list: a spell added by its ID")
    T.isnil(C.Entry("s1953"), "another class's spell (Blink), not known: nothing to draw")
    -- Mana Spring (5677) added by its ID read as a cooldown. It's on no class's
    -- list, so it's someone else's buff on you.
    T.truthy(C.IsAdded("s5677"))
    T.truthy(C.Entry("s5677") and C.Entry("s5677").aura, "someone else's buff: drawn, a buff")
    T.eq(C.Track("s5677"), "aura")
    T.falsy(C.CanTrack("s5677"), "no cooldown of yours to pick")
    D.AddPiece(set, "s5677", "icon", 80, 0)
    D.SetTrack(set, "s5677", "cooldown")
    T.eq(C.Track("s5677"), "aura", "a cooldown pick it can't do is ignored")
    T.eq(AB.CdmOwn.Track("s5677") ~= nil and "x" or AB.CdmOwn.BuffOnly("s5677", set.pieces["s5677"]) and "buff", "buff", "the card's Buff options")
    D.RemovePiece(set, "s5677")
    T.isnil(C.Entry(11), "a game id")
    local tray = {}
    for _, e in ipairs(C.Tray()) do tray[#tray + 1] = e.id end
    T.deq(tray, { "s6673", "s2687", "s1243" }, "learned ones, then group buffs")
    T.eq(C.Unlearned()[1].id, "s12292")
    stub.knownSpells[6192] = true
    stub.FireEvent("SPELLS_CHANGED")
    T.eq(C.SpellOf("s6673"), 6192, "a new rank learned")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: another class gets its own list; no class read yet is survived", function()
    local AB, C = customWorld("PRIEST")
    T.falsy(C.Family("s6673").ids[2], "a warrior spell isn't a priest's family (one spell, as if added by ID)")
    T.truthy(C.Family("s1243"), "the group buffs are everyone's")
    stub.SetUnits({})
    C.Forget()
    T.falsy(C.Family("s6673").ids[2])
    T.truthy(C.Entry("s1243"), "group buffs still work")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a paladin's Seal shows any seal, on you only, a buff", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = {
        { 20375, 20915, aura = true },          -- Command
        { 20154, 20287, aura = true },          -- Righteousness
        { 21082, 20162, aura = true },          -- Crusader
        { 19740, 19834, aura = true },          -- Blessing of Might: not a seal
    }
    stub.knownSpells = { [21082] = true, [20154] = true, [20287] = true }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C.Forget()
    T.truthy(C.Is("seal"))
    T.deq(C.Ranks("seal"), { [20375] = true, [20915] = true, [20154] = true, [21084] = true, [20287] = true,
        [21082] = true, [20162] = true }, "every rank of every seal, nothing else")
    T.eq(C.SpellOf("seal"), 20287, "Righteousness' rank is its stand-in look")
    T.truthy(C.SelfOnly("seal"), "seals are on you")
    T.falsy(C.CanTrack("seal")); T.eq(C.Track("seal"), "aura")
    T.truthy(C.Entry("seal") and C.Entry("seal").aura)
    T.eq((C.Look("seal")), "Seal", "one word: which seal is up can't be read in a fight")
    T.eq(select(2, C.Look("seal")), "Interface/Icons/Spell_Holy_SealOfVengeance", "an icon of its own, not one seal's")
    T.eq(C.Tray()[1].id, "seal", "first in the tray")
    T.truthy(C.Family("s20154"), "each seal stays on its own too")
    T.eq((C.Look("s20154")), "Spell20287")
    stub.knownSpells = {}
    C.Forget()
    T.isnil(C.Entry("seal"), "no seal known: nothing to draw")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("seal"), "only paladins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a paladin's Aura shows any aura, on you only, a buff, so a missing one can glow", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = { { 20154, 20287, aura = true } }
    stub.knownSpells = { [465] = true, [10290] = true, [20154] = true }
    C.Forget()
    T.truthy(C.Is("aura"))
    local r = C.Ranks("aura")
    T.truthy(r[465] and r[10293] and r[7294] and r[19746] and r[19891] and r[20218], "every rank of every aura")
    T.falsy(r[20154], "not a seal")
    T.truthy(C.SelfOnly("aura")); T.eq(C.Track("aura"), "aura")
    T.truthy(C.Entry("aura") and C.Entry("aura").aura)
    T.eq((C.Look("aura")), "Aura")
    T.eq(select(2, C.Look("aura")), "Interface/Icons/Spell_Holy_AuraMastery", "an icon of its own, not one aura's")
    local tray = {}
    for i, e in ipairs(C.Tray()) do tray[e.id] = i end
    T.eq(tray.seal, 1); T.eq(tray.aura, 2, "beside the Seal")
    stub.knownSpells = {}
    C.Forget()
    T.isnil(C.Entry("aura"), "no aura known: nothing to draw")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("aura"), "only paladins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a paladin's Blessing shows any of their long blessings on you, whoever cast it", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = {
        { 19740, 19834, aura = true },          -- Blessing of Might
        { 20217, aura = true },                 -- Blessing of Kings
        { 25782, 25916, aura = true },          -- Greater Blessing of Might
        { 1022, 5599, cd = true, aura = true }, -- Blessing of Protection: not a long one
        { 20154, 20287, aura = true },          -- Seal of Righteousness
    }
    stub.knownSpells = { [19740] = true, [20154] = true }
    C.Forget()
    T.truthy(C.Is("blessing"))
    T.deq(C.Ranks("blessing"), { [19740] = true, [19834] = true, [20217] = true, [25782] = true, [25916] = true },
        "every long blessing, nothing else")
    T.truthy(C.SelfOnly("blessing"), "on you, whoever cast it")
    T.eq(C.Track("blessing"), "aura"); T.falsy(C.CanTrack("blessing"))
    T.truthy(C.Entry("blessing") and C.Entry("blessing").aura)
    T.eq((C.Look("blessing")), "Blessing")
    local tex = C_Spell.GetSpellTexture
    C_Spell.GetSpellTexture = function(id) if id == 19740 then return 135906 end end
    T.eq(select(2, C.Look("blessing")), 135906, "Blessing of Might's own icon")
    C_Spell.GetSpellTexture = tex
    local tray = {}
    for i, e in ipairs(C.Tray()) do tray[e.id] = i end
    T.eq(tray.seal, 1); T.eq(tray.blessing, 2, "after the Seal (no aura known here)")
    T.eq(C.KeyOfSpell(19834), "s19740", "a blessing's own piece wins a lookup by id")
    T.eq(C.KeyOfSpell(20287), "s20154", "a seal's too")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("blessing"), "only paladins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a hunter's or warlock's Pet piece, known with the spell that calls one, watching no aura", function()
    local AB, C = customWorld("HUNTER")
    AB.CdmSpells.HUNTER = {}
    stub.knownSpells = { [883] = true }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C.Forget()
    T.truthy(C.Is("pet")); T.truthy(C.IsPet("pet"))
    T.truthy(C.Entry("pet") and C.Entry("pet").aura, "a buff-like piece")
    T.eq(C.SpellOf("pet"), 883, "Call Pet")
    T.eq((C.Look("pet")), "Pet")
    T.deq(C.Ranks("pet"), {}, "no aura to look for")
    T.eq(C.Tray()[1].id, "pet")
    stub.knownSpells = {}
    C.Forget()
    T.isnil(C.Entry("pet"), "no pet yet: nothing to draw")
    local AW, CW = customWorld("WARLOCK")
    AW.CdmSpells.WARLOCK = {}
    stub.knownSpells = { [688] = true }
    CW.Forget()
    T.eq(CW.SpellOf("pet"), 688, "Summon Imp")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("pet"), "only hunters and warlocks")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A paladin's Seal of Righteousness is 21084, a rank the generated list
-- (talentsforever.com) lacks. It read "not known" and the Seal piece never showed.
T.test("cdm custom: Seal of Righteousness known as 21084 counts, for itself and the Seal", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = {
        { 20154, 20287, 20288, aura = true },   -- Righteousness, as the data has it
        { 20375, aura = true },                 -- Command
    }
    stub.knownSpells = { [21084] = true }
    C.Forget()
    T.eq(C.SpellOf("s20154"), 21084, "the rank you know")
    T.truthy(C.Ranks("s20154")[21084], "its buff is watched too")
    T.truthy(C.Entry("s20154"), "known: drawn")
    T.truthy(C.Entry("seal"), "the Seal shows")
    T.truthy(C.Ranks("seal")[21084])
    stub.knownSpells = { [21084] = true, [20287] = true }
    C.Forget()
    T.eq(C.SpellOf("s20154"), 20287, "a higher rank still wins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The rows world with the addon's own spell list for a warrior.
local function customRows()
    local DUI, AB = rowsWorld()
    stub.SetUnits({ player = { class = "WARRIOR" } })
    AB.CdmSpells.WARRIOR = { { 6673, 5242, 6192, aura = true }, { 2687, cd = true, aura = true } }
    AB.CdmSpells.GROUP = { { 1243, 1244, class = "PRIEST" } }
    stub.knownSpells = { [6673] = true, [5242] = true, [2687] = true }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C_Spell.GetSpellTexture = function(sid) return 5000 + sid end
    AB.CdmCustom.Forget()
    return DUI, AB, AB.CdmData, AB.CdmData.Current()
end
local function refresh(AB) AB.CdmRows.Refresh(); stub.RunTimers() end

T.test("cdm custom: the Pet piece shows while your pet is out and glows when it isn't, as an icon and as a bar", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "HUNTER" } })
    AB.CdmSpells.HUNTER = {}
    stub.knownSpells = { [883] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "pet", "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, "pet", "missingGlow", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        T.truthy(D.SetShape(set, "pet", shape) or shape == "icon")
        stub.SetUnits({ player = { class = "HUNTER" } })
        AB.CdmAuras.PetChanged()
        refresh(AB)
        local h = shape == "bar" and AB.CdmBars.AuraFrame("pet") or AB.CdmAuras.Frame("pet")
        T.truthy(h and h:IsShown(), shape .. ": drawn")
        T.eq(#(h.containers or {}), 0, shape .. ": no aura container")
        T.truthy(h.face, shape .. ": drawn by the addon")
        T.eq(h.up, false, shape .. ": no pet")
        T.eq(h.face:GetAlpha(), 0)
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": glows while missing")
        stub.SetUnits({ player = { class = "HUNTER" }, pet = {} })
        stub.FireEvent("UNIT_PET", "player"); stub.RunTimers()
        T.eq(h.up, true, shape .. ": pet out")
        T.eq(h.face:GetAlpha(), 1)
        T.falsy(AB.CdmEffects.GlowShown(h), shape .. ": no glow")
        stub.SetUnits({ player = { class = "HUNTER" }, pet = { dead = true } })
        stub.FireEvent("UNIT_HEALTH", "pet"); stub.RunTimers()
        T.eq(h.up, false, shape .. ": a dead pet is no pet")
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": glows again")
        -- In a fight too: whether a pet is out is never secret.
        stub.SetUnits({ player = { class = "HUNTER" }, pet = {} })
        stub.EnterCombat()
        stub.FireEvent("UNIT_PET", "player"); stub.RunTimers()
        T.eq(h.up, true, shape .. ": called in a fight")
        stub.LeaveCombat()
    end
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a spell of ours as an icon is our cooldown icon, timed by the rank you know", function()
    local DUI, AB, D, set = customRows()
    local asked
    C_Spell.GetSpellCooldownDuration = function(sid) asked = sid; return {} end
    D.AddPiece(set, "s2687", "icon", 0, 0)
    refresh(AB)
    local f = AB.CdmOwn.Frame("s2687")
    T.truthy(f and f:IsShown(), "our icon")
    T.eq(f:GetParent(), pieceFrame(1, "s2687"), "in its piece")
    T.eq(f.cooldownInfo.spellID, 2687, "the effects read it")
    T.eq(asked, 2687, "timed by the client")
    T.eq(AB.CdmRows.DrawnBy("s2687"), "own icon")
    if T.dev then devCdm(DUI, "why") end
    -- Unlearned (a talent swap): nothing drawn and nothing breaks, back when learned.
    stub.knownSpells = {}
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.falsy(f:IsShown(), "not known: hidden")
    stub.knownSpells = { [2687] = true }
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.truthy(f:IsShown(), "learned again")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a buff of ours watches every rank on you, then your target; a group buff only you", function()
    local DUI, AB, D, set = customRows()
    D.AddPiece(set, "s6673", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("s6673")
    T.truthy(h and h:IsShown(), "the game's aura display in a holder of ours")
    T.eq(#h.containers, 2)
    T.eq(h.containers[1].unit, "player"); T.eq(h.containers[1].c.__groups.a.filter, "HELPFUL")
    T.eq(h.containers[2].unit, "target"); T.eq(h.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
    T.deq(h.containers[1].c.__groups.a.opts.candidateFilters.includeSpellIDs,
        { [6673] = true, [5242] = true, [6192] = true }, "every rank")
    T.truthy(pieceFrame(1, "s6673"):IsShown(), "keeps its spot while the buff is down")
    T.eq(AB.CdmRows.DrawnBy("s6673"), "aura icon")
    D.SetShape(set, "s6673", "bar")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("s6673"), "aura bar")
    T.truthy(AB.CdmBars.AuraFrame("s6673"):IsShown())
    D.AddPiece(set, "s1243", "icon", 0, -48)
    refresh(AB)
    T.eq(#AB.CdmAuras.Frame("s1243").containers, 1, "a group buff: on you only")
    -- Bloodrage switched to its buff.
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.SetTrack(set, "s2687", "aura")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("s2687"), "aura icon")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A priest's Renew and Inner Fire with Grow from Middle: buffs Daylight UI draws
-- itself kept their spot when they dropped, so the group never closed up or
-- re-centered.
T.test("cdm custom: a buff of ours that's down slides out of its group; one we can't tell keeps its spot", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    D.AddPiece(set, "s6673", "icon", 0, 0)
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.Hook(set, "s2687", "s6673", "right")
    T.truthy(D.SetChainValue(set, "s6673", "grow", "center"))
    local full = D.Layout(set)
    local w = full["s6673"].w
    local gap = full["s2687"].x - w
    stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
    refresh(AB)
    local h = AB.CdmAuras.Frame("s6673")
    local f, f2 = pieceFrame(1, "s6673"), pieceFrame(1, "s2687")
    T.eq(f2.goalX, full["s2687"].x, "both up: each in its spot")
    -- The buff drops and the other one moves to the group's middle.
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, (w + gap) / 2, "down: the rest closes up round the middle")
    T.truthy(f:IsShown() and h:IsShown(), "still listening for the buff")
    -- In a fight it can land without your cast (a proc, or someone else's). The
    -- client's button coming up is the only sign of it.
    stub.combat = true
    AB.CdmAuras.Shown(h); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "its button came up: back in its spot")
    T.eq(f.goalX, 0)
    stub.combat = false
    -- Keep its spot never slides.
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, (w + gap) / 2, "the fight over: read down again")
    T.truthy(D.SetSpellValue(set, "s6673", "missing", true))
    refresh(AB)
    T.eq(f2.goalX, full["s2687"].x, "Keep its spot")
    T.truthy(D.SetSpellValue(set, "s6673", "missing", false))
    -- Slide over off: every spell keeps its place.
    T.truthy(D.SetChainValue(set, "s6673", "collapse", false))
    refresh(AB)
    T.eq(f2.goalX, full["s2687"].x, "Slide over off")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A mage's Missile Barrage hung above Arcane Blast: while its buff was down it
-- waited, still listening, right on top of Arcane Blast, so a proc in a fight came
-- up there and the two icons sat on each other. Hung left, the same.
T.test("cdm custom: a buff that slid out waits beside its spot, never on top of the piece it hangs from", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    D.AddPiece(set, "s6673", "icon", 0, 0)
    for _, case in ipairs({ { "up", "icon" }, { "left", "icon" }, { "down", "icon" }, { "right", "icon" },
        { "up", "bar" }, { "left", "bar" } }) do
        local side, shape = case[1], case[2]
        set.pieces["s2687"] = nil
        D.AddPiece(set, "s2687", shape, 0, -96)
        T.truthy(D.Hook(set, "s2687", "s6673", side))
        D.SetTrack(set, "s2687", "aura")
        stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
        refresh(AB)
        T.eq(AB.CdmRows.DrawnBy("s2687"), "aura " .. shape)
        side = side .. " " .. shape
        local parent, f = pieceFrame(1, "s6673"), pieceFrame(1, "s2687")
        T.truthy(f:IsShown(), side .. ": still listening while down")
        local pw, ph = parent:GetSize()
        local w, h = f:GetSize()
        local px, py, x, y = parent.goalX, parent.goalY, f.goalX, f.goalY
        local apart = x >= px + pw or x + w <= px or y - h >= py or y <= py - ph
        T.truthy(apart, side .. ": waits clear of the piece it hangs from ("
            .. x .. "," .. y .. " vs " .. px .. "," .. py .. ")")
    end
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A druid's Mark of the Wild and Thorns with Grow from Middle, Buff up Hide and
-- Buff missing Show (a reminder of what's missing): the one that was up hid but
-- kept its spot, so the missing one sat off to the side instead of in the middle.
T.test("cdm custom: a buff hidden while up (Buff up Hide) gives its spot up, even with Buff missing Show", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    D.AddPiece(set, "s6673", "icon", 0, 0)
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.Hook(set, "s2687", "s6673", "right")
    T.truthy(D.SetChainValue(set, "s6673", "grow", "center"))
    for _, id in ipairs({ "s6673", "s2687" }) do
        T.truthy(D.SetSpellValue(set, id, "missing", true))
        T.truthy(D.SetSpellValue(set, id, "hideActive", true))
    end
    local full = D.Layout(set)
    local w = full["s6673"].w
    local gap = full["s2687"].x - w
    stub.auras.player = { HELPFUL = {} }
    refresh(AB)
    local f2 = pieceFrame(1, "s2687")
    T.eq(f2.goalX, full["s2687"].x, "both missing: each shows in its spot")
    -- The first lands, hidden while up, so its spot goes and the missing one centers.
    stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, (w + gap) / 2, "up and hidden: the missing one comes to the middle")
    -- It drops again: back in its spot, both showing.
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "missing again: back in its spot")
    -- Slide over off: every spell keeps its place.
    stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
    T.truthy(D.SetChainValue(set, "s6673", "collapse", false))
    refresh(AB)
    T.eq(f2.goalX, full["s2687"].x, "Slide over off")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A warrior's Shield Block in a dungeon: after a reload inside, auras can't be
-- read even out of a fight, so Daylight UI never learned the buff was down and it
-- kept its spot until cast.
T.test("cdm custom: in a dungeon a buff of ours is told up and down by its button, after a reload too", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    stub.SetRestriction("Map", true)
    D.AddPiece(set, "s6673", "icon", 0, 0)
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.Hook(set, "s2687", "s6673", "right")
    local full = D.Layout(set)
    stub.auras.player = { HELPFUL = {} }
    refresh(AB)
    local h = AB.CdmAuras.Frame("s6673")
    local f2 = pieceFrame(1, "s2687")
    T.eq(f2.goalX, full["s2687"].x, "just built: can't tell yet, keeps its spot")
    -- No button came up for it, so the buff isn't there. The holder asks for a pass
    -- once that's had time; the fake game runs a timer at once whatever its delay,
    -- so it's asked here.
    stub.Advance(1)
    refresh(AB)
    T.eq(f2.goalX, 0, "no button came up: down, the next one slides over")
    local btn = h.containers[1].c.__groups.a.button
    stub.AuraVisible(btn, true); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "cast: its button came up")
    stub.AuraVisible(btn, false); stub.RunTimers()
    T.eq(f2.goalX, 0, "ran out: its button went away")
    -- In a fight (where it also held its spot): cast, then it runs out and the
    -- client stops the button's shown animations.
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 6673); stub.RunTimers()
    stub.AuraVisible(btn, true); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "cast in the fight: back in its spot")
    stub.AuraVisible(btn, false); stub.RunTimers()
    T.eq(f2.goalX, 0, "ran out in the fight: the next one slides over")
    T.truthy(table.concat(h.heard, " "):find("stop", 1, true), "the report says what was heard")
    -- Its countdown ending says so too, with no animation heard.
    local anims = btn.__shownAnims
    btn.__shownAnims = {}
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 6673); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "cast again: back")
    local done = h.parts[btn].cd:GetScript("OnCooldownDone")
    T.truthy(done, "the countdown is heard")
    done(); stub.RunTimers()
    T.eq(f2.goalX, 0, "its time ran out: slides over")
    T.truthy(table.concat(h.heard, " "):find("time out", 1, true))
    btn.__shownAnims = anims
    stub.AuraVisible(btn, false)
    -- The holder hiding with its chain isn't the buff going.
    stub.AuraVisible(btn, true); stub.RunTimers()
    h:Hide()
    T.eq(h.up, true, "a hidden holder: still up")
    h:Show()
    stub.combat = false
    stub.SetRestriction("Map", false)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Shield Block in a dungeon fight: the client's button gave no sign at all, so
-- after the cast it read as up for good and held an empty spot. Your cast is
-- plain, and its length is the one the buff had the last time it could be read,
-- else the spell's text.
T.test("cdm custom: in a dungeon fight a buff of ours runs out by the clock from your cast", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    D.AddPiece(set, "s6673", "icon", 0, 0)
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.Hook(set, "s2687", "s6673", "right")
    local full = D.Layout(set)
    -- Seen once where auras can be read, its length is kept for this character.
    stub.auras.player = { HELPFUL = { { spellId = 6673, duration = 5, expirationTime = GetTime() + 5 } } }
    refresh(AB)
    T.eq(DUI.DB.Character().cdmAuraLasts["s6673"], 5, "its length kept")
    stub.auras.player = { HELPFUL = {} }
    stub.Advance(6); AB.CdmAuras.AuraChanged(); stub.RunTimers()
    -- A reload inside a dungeon: a new holder with nothing read.
    AB.CdmAuras.Frame("s6673").auraLasts = nil
    stub.SetRestriction("Map", true)
    stub.combat = true
    local f2 = pieceFrame(1, "s2687")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 6673); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "cast: its spot")
    stub.Advance(6); stub.RunTimers()
    T.eq(f2.goalX, 0, "five seconds on: run out, the next one slides over")
    -- Never seen readable, so the spell's own text gives the length.
    DUI.DB.Character().cdmAuraLasts = nil
    AB.CdmAuras.Frame("s6673").auraLasts = nil
    local desc = C_Spell.GetSpellDescription
    C_Spell.GetSpellDescription = function() return "Increases your chance to block by 75% for 5 sec." end
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 6673); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "cast again")
    stub.Advance(6); stub.RunTimers()
    T.eq(f2.goalX, 0, "its text said five seconds")
    C_Spell.GetSpellDescription = desc
    -- A buff your blocks use up (Shield Block, Holy Shield) ends at the last block
    -- instead of breaking when the charges run out.
    local stacks = AB.CdmOwn.Stacks
    AB.CdmOwn.Stacks = function(id) return id == "s6673" end
    stub.combat = false
    stub.SetRestriction("Map", false)
    stub.auras.player = { HELPFUL = { { spellId = 6673, applications = 2, duration = 5, expirationTime = GetTime() + 5 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(DUI.DB.Character().cdmAuraCharges["s6673"], 2, "its charges kept (Improved Shield Block)")
    stub.auras.player = { HELPFUL = {} }
    stub.Advance(6); AB.CdmAuras.AuraChanged(); stub.RunTimers()
    stub.SetRestriction("Map", true)
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 6673); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "cast")
    stub.FireEvent("UNIT_COMBAT", "player", "WOUND", "BLOCK_REDUCED", 120, 1); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "one block: a charge left")
    stub.FireEvent("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 300, 1); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "a hit that wasn't blocked takes none")
    stub.FireEvent("UNIT_COMBAT", "player", "BLOCK", "", 0, 1); stub.RunTimers()
    T.eq(f2.goalX, 0, "the second block: used up, the next one slides over")
    -- It used to fold down early, after one block. When never seen readable, its
    -- text says how many (WoW Forever's Shield Block blocks 2 attacks), never a
    -- guessed 1.
    DUI.DB.Character().cdmAuraCharges = nil
    C_Spell.GetSpellDescription = function() return "Increases chance to block by 75% for 7 sec, but will only block 2 attacks." end
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 6673); stub.RunTimers()
    stub.FireEvent("UNIT_COMBAT", "player", "BLOCK", "", 0, 1); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "one block: its text said two")
    stub.FireEvent("UNIT_COMBAT", "player", "BLOCK", "", 0, 1); stub.RunTimers()
    T.eq(f2.goalX, 0, "the second: used up")
    -- No count anywhere: blocks aren't counted and the clock ends it.
    C_Spell.GetSpellDescription = function() return "Increases chance to block." end
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 6673); stub.RunTimers()
    stub.FireEvent("UNIT_COMBAT", "player", "BLOCK", "", 0, 1); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "no count known: a block doesn't end it")
    stub.Advance(8); stub.RunTimers()
    T.eq(f2.goalX, 0, "its time does")
    C_Spell.GetSpellDescription = desc
    AB.CdmOwn.Stacks = stacks
    stub.combat = false
    stub.SetRestriction("Map", false)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: the Seal placed as an icon and a bar watches every seal on you, named Seal", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 20375, 20915, aura = true }, { 20154, 20287, aura = true } }
    stub.knownSpells = { [20154] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "seal", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("seal")
    T.truthy(h and h:IsShown())
    T.eq(#h.containers, 1, "on you only")
    T.deq(h.containers[1].c.__groups.a.opts.candidateFilters.includeSpellIDs,
        { [20375] = true, [20915] = true, [20154] = true, [21084] = true, [20287] = true })
    T.eq(AB.CdmRows.DrawnBy("seal"), "aura icon")
    -- The empty slot ("Show missing buffs") used to wear Righteousness' icon.
    T.eq(h.under:GetTexture(), "Interface/Icons/Spell_Holy_SealOfVengeance", "the empty slot wears the Seal's own icon")
    D.SetShape(set, "seal", "bar")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("seal"), "aura bar")
    T.eq(AB.CdmBars.AuraFrame("seal").Bar.Name:GetText(), "Seal")
    T.eq(AB.CdmBars.AuraFrame("seal").Icon.Icon:GetTexture(), "Interface/Icons/Spell_Holy_SealOfVengeance")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: the Blessing wears Blessing of Might's own icon as an icon and a bar, a known file when the client has none", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 19740, 19834, aura = true }, { 20217, aura = true } }
    stub.knownSpells = { [19740] = true }
    AB.CdmCustom.Forget()
    local tex = C_Spell.GetSpellTexture
    local icon = 135906   -- what the client hands back for rank 1, read when drawn
    C_Spell.GetSpellTexture = function(id) if id == 19740 then return icon end end
    D.AddPiece(set, "blessing", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("blessing")
    T.truthy(h and h:IsShown())
    T.eq(AB.CdmRows.DrawnBy("blessing"), "aura icon")
    T.eq(h.under:GetTexture(), icon, "the empty slot wears the spell's own icon")
    D.SetShape(set, "blessing", "bar")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("blessing"), "aura bar")
    T.eq(AB.CdmBars.AuraFrame("blessing").Bar.Name:GetText(), "Blessing")
    T.eq(AB.CdmBars.AuraFrame("blessing").Icon.Icon:GetTexture(), icon)
    -- The client doesn't know the spell yet: a file it ships.
    C_Spell.GetSpellTexture = function() return nil end
    T.eq(select(2, AB.CdmCustom.Look("blessing")), "Interface/Icons/Spell_Holy_FistOfJustice")
    C_Spell.GetSpellTexture = tex
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The Seal as an icon with "Glow when not active" on, no seal up, and no glow:
-- the aura holders never said whether the buff was down.
T.test("cdm custom: Glow when not active lights our aura icon and bar while the buff is down", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 20375, 20915, aura = true }, { 20154, 20287, aura = true } }
    stub.knownSpells = { [20154] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "seal", "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, "seal", "missing", true))
    T.truthy(D.SetSpellValue(set, "seal", "missingGlow", true))
    stub.SetAuras("player", "HELPFUL", {})
    refresh(AB)
    local Fx, h = AB.CdmEffects, AB.CdmAuras.Frame("seal")
    T.truthy(Fx.GlowShown(h), "no seal: glows")
    -- With white picked, the glow stayed the accent color.
    T.truthy(D.SetSpellValue(set, "seal", "missingGlowColor", { 1, 1, 1 }))
    refresh(AB)
    local gf = Fx.GlowFrame(h)
    T.deq(glowRGB(gf.tex), { 1, 1, 1 }, "in the picked white")
    T.isnil(gf.tex.__gradient, "no accent gradient left on it")
    stub.SetAuras("player", "HELPFUL", { { spellId = 20375, name = "Seal of Command" } })
    stub.FireEvent("UNIT_AURA", "player", {}); stub.RunTimers()
    T.falsy(Fx.GlowShown(h), "a seal up: no glow")
    local btn = h.buttons and h.buttons[1]
    T.truthy(btn and btn.cdmSlide, "its button slides in as the aura lands")
    T.eq(btn.cdmSlideOn, true)
    T.eq(btn.cdmSlideKey, "slide", "a buff-only icon still drops in")
    -- In a fight the lookups come back empty, so the last answer holds.
    stub.EnterCombat()
    stub.FireEvent("UNIT_AURA", "player", {}); refresh(AB)
    T.falsy(Fx.GlowShown(h), "not a false alarm mid-fight")
    stub.LeaveCombat()
    stub.SetAuras("player", "HELPFUL", {})
    stub.FireEvent("PLAYER_REGEN_ENABLED"); stub.RunTimers()
    T.truthy(Fx.GlowShown(h), "fell off: glows once readable")
    -- The same as a bar.
    D.SetShape(set, "seal", "bar")
    refresh(AB)
    T.truthy(Fx.GlowShown(AB.CdmBars.AuraFrame("seal")), "the bar glows too")
    -- Off: no glow.
    D.SetSpellValue(set, "seal", "missingGlow", false)
    refresh(AB)
    T.falsy(Fx.GlowShown(AB.CdmBars.AuraFrame("seal")))
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seal of Fury as a bar with "Show missing buffs" off still showed its empty bar
-- while the seal was down. Addon code can't tell in a fight whether the buff is
-- up, so the client's own button carries the bar's whole look (background,
-- borders, name), and the addon's bar under it only shows with "Show missing
-- buffs" on.
T.test("cdm custom: Show missing buffs off draws nothing of ours while the buff is down", function()
    local DUI, AB, D, set = customRows()
    D.AddPiece(set, "s6673", "bar", 0, 0)
    D.AddPiece(set, "s1243", "icon", 0, -48)
    D.SetSpellValue(set, "s6673", "missing", false)
    D.SetSpellValue(set, "s1243", "missing", false)
    refresh(AB)
    local h = AB.CdmBars.AuraFrame("s6673")
    T.truthy(h:IsShown(), "it keeps its spot")
    T.eq(h.under:GetAlpha(), 0, "no empty bar")
    T.eq(h.over:GetAlpha(), 0, "no name over nothing")
    local btn = h.containers[1].c.__groups.a.button
    local parts = h.parts[btn]
    T.eq(parts.slot:GetAlpha(), 1, "the client's button wears the bar's border")
    T.eq(parts.iconBox:GetAlpha(), 1, "and the icon's")
    T.eq(parts.backTex:GetAlpha(), 1, "and its background")
    T.eq(parts.name:GetAlpha(), 1); T.eq(parts.name:GetText(), "Spell5242", "and its name")
    T.truthy(h.containers[1].c:GetFrameLevel() > h.Bar:GetFrameLevel(), "the client's bar over our empty one")
    local icon = AB.CdmAuras.Frame("s1243")
    T.truthy(icon:IsShown(), "the icon keeps its spot")
    T.falsy(icon.under:IsShown(), "no grayed icon")
    -- On: the empty bar and grayed icon while down, with the button's own extras off.
    D.SetSpellValue(set, "s6673", "missing", true)
    D.SetSpellValue(set, "s1243", "missing", true)
    refresh(AB)
    T.eq(h.under:GetAlpha(), 1); T.eq(h.over:GetAlpha(), 1)
    T.eq(parts.slot:GetAlpha(), 0); T.eq(parts.iconBox:GetAlpha(), 0)
    T.eq(parts.name:GetAlpha(), 0); T.eq(parts.backTex:GetAlpha(), 0)
    T.truthy(icon.under:IsShown(), "the grayed icon")
    -- Switched off in a boss fight: both wait until it's over, together.
    stub.SetRestriction("Encounter", true)
    D.SetSpellValue(set, "s6673", "missing", false)
    refresh(AB)
    T.eq(h.under:GetAlpha(), 1, "not yet: the button can't change now")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.SetRestriction("Encounter", false)
    stub.RunTimers()
    T.eq(h.under:GetAlpha(), 0); T.eq(parts.slot:GetAlpha(), 1)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a shield's icon shows the shield left in place of its time", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PRIEST", absorbs = 0 } })
    AB.CdmSpells.PRIEST = { { 17, 592, aura = true } }
    stub.knownSpells = { [592] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "s17", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("s17")
    T.truthy(h and h.amount and h.amount:IsShown(), "the amount, on by default")
    T.eq(rawget(h.amount:GetValue(), "__value"), 0, "no shield: its gate closed")
    local btn = h.containers[1].c.__groups.a.button
    local cd = h.parts[btn].cd
    T.truthy(h.amountOn)
    -- It lands, then soaks, in a fight: drawn but never read.
    stub.EnterCombat()
    stub.units.player.absorbs = stub.Secret(480)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(h.amount.text:GetText(), "__value"), "480")
    T.eq(rawget(h.amount:GetValue(), "__value"), 480, "its gate open")
    stub.units.player.absorbs = stub.Secret(200)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(h.amount.text:GetText(), "__value"), "200")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.LeaveCombat()
    -- Off shows the time again; on, it gives way (the client's cooldown, after restrictions).
    function cd:SetHideCountdownNumbers(v) self.__hideNumbers = v end
    D.SetSpellValue(set, "s17", "shieldAmount", false)
    refresh(AB)
    T.falsy(h.amount:IsShown(), "no amount")
    T.eq(cd.__hideNumbers, false, "the time is back")
    D.SetSpellValue(set, "s17", "shieldAmount", true)
    refresh(AB)
    T.truthy(h.amount:IsShown())
    T.eq(cd.__hideNumbers, true, "the time gives way")
    -- Hide duration swipe turns the client's swipe off and keeps its time.
    function cd:SetDrawSwipe(v) self.__swipe = v end
    T.truthy(D.SetSpellValue(set, "s17", "noDurationSwipe", true))
    refresh(AB)
    T.eq(cd.__swipe, false, "no swipe")
    D.SetSpellValue(set, "s17", "noDurationSwipe", false)
    refresh(AB)
    T.eq(cd.__swipe, true, "the swipe back")
    -- Reverse swipe reaches the client's swipe too (after restrictions).
    function cd:SetReverse(v) self.__reverse = v end
    T.truthy(D.SetSpellValue(set, "s17", "reverse", true))
    refresh(AB)
    T.eq(cd.__reverse, true, "reversed")
    D.SetSpellValue(set, "s17", "reverse", false)
    refresh(AB)
    T.eq(cd.__reverse, false, "not reversed")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a shield's bar fills by the shield left, its full when it lands", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PRIEST", absorbs = 0 } })
    AB.CdmSpells.PRIEST = { { 17, 592, aura = true }, { 139, aura = true } }
    stub.knownSpells = { [592] = true, [139] = true }
    AB.CdmCustom.Forget()
    T.truthy(AB.CdmBars.IsShield("s17"), "Power Word: Shield, any rank")
    T.falsy(AB.CdmBars.IsShield("s139"), "Renew isn't one")
    D.AddPiece(set, "s17", "bar", 0, 0)
    refresh(AB)
    local h = AB.CdmBars.AuraFrame("s17")
    local s = h.shield
    T.truthy(s and s:IsShown(), "our shield bar")
    local btn = h.containers[1].c.__groups.a.button
    local parts = h.parts[btn]
    T.eq(parts.bar:GetStatusBarTexture():GetAlpha(), 0, "the client's time fill gives way")
    T.eq(parts.time:GetAlpha(), 0, "and its time")
    -- It lands: the amount is its full value, and the hits after drain it.
    btn:Hide()
    stub.units.player.absorbs = stub.Secret(480)
    stub.EnterCombat()
    btn:Show()
    local lo, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 480, "full at the amount it landed with")
    T.eq(rawget(s.text:GetText(), "__value"), "480")
    stub.Advance(1)
    stub.units.player.absorbs = stub.Secret(200)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    lo, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 480, "the full stays")
    T.eq(rawget(s:GetValue(), "__value"), 200, "drained")
    T.eq(rawget(s.text:GetText(), "__value"), "200")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.LeaveCombat()
    -- A friendly target: its shield (from any caster), full from what it has now.
    T.eq(#h.containers, 1, "one container, its unit following the target")
    T.eq(h.containers[1].unit, "player")
    T.eq(h.containers[1].c.__groups.a.filter, "HELPFUL")
    stub.units.target = { friend = true, absorbs = stub.Secret(900) }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(h.containers[1].unit, "target")
    T.eq(h.containers[1].c.__unit, "target")
    lo, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 900, "the target's shield is the full")
    T.eq(rawget(s.text:GetText(), "__value"), "900")
    -- An enemy target: back to yours.
    stub.units.target = { friend = false, absorbs = stub.Secret(50) }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(h.containers[1].c.__unit, "player")
    T.eq(rawget(s.text:GetText(), "__value"), "200")
    T.eq(s.text:GetAlpha(), 1, "the amount shows")
    -- Show shield amount off: the bar alone.
    D.SetSpellValue(set, "s17", "shieldAmount", false)
    refresh(AB)
    T.eq(s.text:GetAlpha(), 0, "no amount")
    T.truthy(s:IsShown(), "the bar stays")
    D.SetSpellValue(set, "s17", "shieldAmount", true)
    refresh(AB)
    T.eq(s.text:GetAlpha(), 1)
    -- By time instead: the client's bar again.
    D.SetSpellValue(set, "s17", "fillBy", "time")
    refresh(AB)
    T.falsy(s:IsShown(), "no shield bar")
    T.eq(parts.bar:GetStatusBarTexture():GetAlpha(), 1)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a buff of ours placed in a fight gets its containers once the fight ends", function()
    local DUI, AB, D, set = customRows()
    stub.EnterCombat()
    D.AddPiece(set, "s6673", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("s6673")
    T.eq(#h.containers, 0, "none made in combat")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(#h.containers, 2, "made once it ends")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a boss fight with our pieces up raises no errors", function()
    local DUI, AB, D, set = customRows()
    C_Spell.GetSpellCooldownDuration = function() return {} end
    D.AddPiece(set, "s2687", "icon", 0, 0)
    D.AddPiece(set, "s6673", "bar", 0, -48)
    D.AddPiece(set, "s1243", "icon", 0, -96)
    refresh(AB)
    stub.SetRestriction("Encounter", true)
    stub.EnterCombat()
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    stub.FireEvent("UNIT_AURA", "player")
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    refresh(AB)
    T.truthy(AB.CdmOwn.Frame("s2687"):IsShown())
    stub.LeaveCombat()
    stub.SetRestriction("Encounter", false)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- edWorld's game spells are 11-14 (spell ids 111-114) and bars 21-22.
local function customTray(AB, families, known)
    stub.SetUnits({ player = { class = "WARRIOR" } })
    AB.CdmSpells.WARRIOR = families
    AB.CdmSpells.GROUP = { { 1243, class = "PRIEST" } }
    stub.knownSpells = known
    AB.CdmCustom.Forget()
end
local function trayIds(Ed)
    local ids = {}
    for _, e in ipairs(Ed.Spells()) do ids[#ids + 1] = e.id end
    return ids
end

-- The Seal (on you only, like a group buff) was hidden behind the Group buffs switch.
T.test("cdm editor: a paladin's Seal is in the tray with Group buffs off", function()
    local DUI, AB, Ed, D = edWorld()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 20154, 20287, aura = true } }
    AB.CdmSpells.GROUP = { { 1243, class = "PRIEST" } }
    stub.knownSpells = { [21084] = true }
    AB.CdmCustom.Forget()
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "seal", "s20154" }, "the Seal first of ours, no group buff")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the tray adds our class spells and group buffs, once each, after the game's", function()
    local DUI, AB, Ed, D = edWorld()
    -- 111 is the game's spell 11 (same name), so it's listed once, as the game's.
    customTray(AB, { { 111, aura = true }, { 2687, cd = true }, { 12292, cd = true } },
        { [111] = true, [2687] = true })
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "s2687" }, "group buffs off by default")
    Ed.SetShowGroup(true)
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "s2687", "s1243" })
    Ed.SetShowUnlearned(true)
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "s2687", "s1243", 14, "s12292" })
    Ed.SetShowUnlearned(false)
    Ed.SetShowGroup(false)
    -- A group buff already placed stays listed (as known) with the switch off.
    D.AddPiece(D.Current(), "s1243", "icon", 300, 0)
    local e
    for _, x in ipairs(Ed.Spells()) do if x.id == "s1243" then e = x end end
    T.truthy(e and e.placed and not e.unlearned, "placed: still listed, not as unknown")
    D.RemovePiece(D.Current(), "s1243")
    Ed.Choose("s2687")
    T.eq(Ed.Pending().kind, "icon")
    Ed.Pick("bar")
    T.eq(D.Current().pieces["s2687"].shape, "bar")
    T.eq(Ed.Selected(), "s2687")
    -- A layout copied from another class: a key this class has no spell for.
    AB.CdmSpells.MAGE = { { 1953, cd = true } }   -- Blink
    AB.CdmCustom.Forget()
    D.AddPiece(D.Current(), "s1953", "icon", 200, 0)
    local last = Ed.Spells()[#Ed.Spells()]
    T.eq(last.id, "s1953"); T.truthy(last.unlearned, "listed as not known")
    Ed.Changed(); stub.RunTimers()
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: a spell of ours with a cooldown and a buff picks which one it shows", function()
    local DUI, AB, Ed, D = edWorld()
    customTray(AB, { { 2687, cd = true, aura = true }, { 6673, aura = true } }, { [2687] = true, [6673] = true })
    Ed.Choose("s2687"); Ed.Pick("icon"); stub.RunTimers()
    local row
    for _, r in ipairs(AB.CdmCard.ROWS.show) do
        if r.item and r.item.key == "cdm.card.ownTrack" then row = r end
    end
    T.truthy(row, "a Track row on the Show tab")
    local set = D.Current()
    T.truthy(row.show(set, "s2687", set.pieces["s2687"]), "shown for a spell with both")
    T.eq(row.item.get(), "cooldown")
    row.item.set("aura"); stub.RunTimers()
    T.eq(set.pieces["s2687"].track, "aura")
    T.eq(AB.CdmRows.DrawnBy("s2687"), "aura icon", "the live layout follows")
    Ed.Choose("s6673"); Ed.Pick("icon")
    T.truthy(row.show(set, "s6673", set.pieces["s6673"]), "a buff can pick too")
    row.item.set("both"); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy("s6673"), "aura and cooldown icon", "Both: its buff over its cooldown")
    D.AddPiece(set, 11, "icon", 0, -100)
    T.falsy(row.show(set, 11, set.pieces[11]), "the game's spells have their own pick")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: every look setting is on Look (the spell's, then the whole group's); Group is placement and behavior", function()
    local DUI, AB, Ed, D = edWorld()
    local Card = AB.CdmCard
    local function keys(t)
        local out = {}
        for _, r in ipairs(Card.ROWS[t]) do if r.item then out[r.item.key] = true end end
        return out
    end
    local look, group = keys("look"), keys("chain")
    for _, k in ipairs({ "size", "width", "height", "color", "back", "backColor", "backGradient", "icon", "text", "time" }) do
        T.truthy(look["cdm.card.chain." .. k], "Look has the group's " .. k)
        T.isnil(group["cdm.card.chain." .. k], "Group doesn't have " .. k)
    end
    for _, k in ipairs({ "cdm.card.chain.spacing", "cdm.card.chain.grow", "cdm.card.chain.combat",
                         "cdm.card.chain.collapse", "cdm.card.alignAcross", "cdm.card.alignDown", "cdm.card.gap", "cdm.card.unhook" }) do
        T.truthy(group[k], "Group has " .. k)
        T.isnil(look[k], "Look doesn't have " .. k)
    end
    -- One spell alone: the group's sizes would only repeat its own.
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    local size
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == "cdm.card.chain.size" then size = r end end
    T.falsy(size.show(set, 11, set.pieces[11]), "alone: no group icon size")
    D.AddPiece(set, 12, "icon", 40, 0)
    T.truthy(D.Hook(set, 12, 11, "right"))
    T.truthy(size.show(set, 11, set.pieces[11]), "two: the group's icon size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: an icon shows the key that casts it, once asked, and follows the binding", function()
    local DUI, AB, ess = rowsWorld()
    local D, R, CD = AB.CdmData, AB.CdmRows, AB.Cooldowns
    local set = D.Current()
    D.AddChain(set, { 11, 13 }, "icon", 0, 0)
    stub.slots[2] = { texture = "t", spellID = 1011 }
    -- The bar holds another rank: the same name still finds the key.
    AB.CdmOwn.Look = function(id) if id == 11 then return "Slam", "t" end end
    C_Spell.GetSpellName = function(id) return id == 1011 and "Slam" or nil end
    stub.bindings["ACTIONBUTTON2"] = { "Q" }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    local l = CD.KeyLabel(ess[1])
    T.falsy(l and l:IsShown(), "off by default")

    DUI:Set("ActionBars", "cdmKeybinds", true)
    R.Refresh(); stub.RunTimers()
    l = CD.KeyLabel(ess[1])
    T.truthy(l and l:IsShown(), "on: the label shows")
    T.eq(l.text:GetText(), "Q")
    T.falsy(CD.KeyLabel(ess[3]) and CD.KeyLabel(ess[3]):IsShown(), "a spell on no bar shows none")

    stub.bindings["ACTIONBUTTON2"] = { "E" }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()
    T.eq(l.text:GetText(), "E", "a new binding shows without a layout pass")

    D.SetLook(set, 11, "keyShown", false)
    D.Changed(); R.Refresh(); stub.RunTimers()
    T.falsy(l:IsShown(), "the spell's own switch beats the page's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's /cdm stayed empty except for the grid. A bar piece's preview set
-- text on its key label, which has no font until an icon styles it, so the client
-- refused and the draw stopped before the banner and the tray.
T.test("cdm editor: a bar in the layout draws, with the tray and no key label", function()
    local DUI, AB, Ed, D = edWorld()
    stub.FontRule = true
    local ok, err = pcall(function()
        D.AddPiece(Ed.Set(), 21, "bar", 0, 0)
        Ed.Changed()
    end)
    stub.FontRule = nil
    T.truthy(ok, tostring(err))
    T.truthy(Ed.Tray():GetHeight() > 0, "the tray got its size")

    D.AddPiece(Ed.Set(), 11, "icon", 100, 0)
    DUI:Set("ActionBars", "cdmKeybinds", true)
    AB.CdmOwn.Look = function() return "Slam", "t" end
    stub.slots[2] = { texture = "t", spellID = 1011 }
    _G.C_Spell.GetSpellName = function() return "Slam" end
    stub.bindings["ACTIONBUTTON2"] = { "Q" }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()
    Ed.Changed()
    D.SetShape(Ed.Set(), 11, "bar")
    Ed.Changed()
    local kids = Ed.PreviewOf(11)
    T.falsy(kids.key:IsShown(), "an icon turned bar drops its key")
    Ed.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Add by ID (the tray's button, like EllesmereUI's Custom Spell ID / Item ID): a
-- spell the tray has is that one, any other spell is "s<id>", and an item with a
-- use is "i<id>", timed by the item's own cooldown. The fake game has no items,
-- so this test lends C_Item and C_Container the calls and takes them back.
-- The menu used to show two blank rows.
T.test("cdm editor: the tray's hint sits clear of the Add by ID button", function()
    local DUI, AB, Ed = edWorld()
    local hint, byID = Ed.TrayHint(), Ed.PillButton("byID")
    T.eq(stub.Text(hint), DUI.L["Click or drag a spell."])
    local found
    for i = 1, hint:GetNumPoints() do
        local p, rel, rp, x = hint:GetPoint(i)
        if p == "LEFT" then found = (rel == byID and rp == "RIGHT" and x > 0) end
    end
    T.truthy(found, "its left edge starts past the button, so a wide font wraps it instead of covering it")
end)

T.test("cdm editor: the Add by ID menu names its two rows", function()
    local DUI, AB, Ed = edWorld()
    local W = DUI.Widgets
    local owner = CreateFrame("Button", nil, UIParent)
    owner:SetSize(80, 20)
    Ed.OpenAddMenu(owner)
    T.eq(W.MenuRow(1).text:GetText(), DUI.L["Spell ID"])
    T.eq(W.MenuRow(2).text:GetText(), DUI.L["Item ID"])
    W.CloseMenu()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: add a spell or an item by its ID; an item times its own cooldown", function()
    local DUI, AB, Ed, D = edWorld()
    customTray(AB, { { 6673, 5242, 6192, aura = true } }, { [6673] = true, [9999] = true })
    local C = AB.CdmCustom
    local ITEMS = {
        [5512] = { spell = 6262, name = "Healthstone", icon = "hs", cached = true, count = 1, used = true },
        [7001] = { spell = 7002, name = "Trinket", icon = "tr", cached = true, count = 1 },
        [2589] = { name = "Linen Cloth", icon = "cloth", cached = true },
        [9000] = { spell = 9001, name = "Slow Item", icon = "slow", cached = false },
    }
    local cd = { start = 0, dur = 0 }
    local saved = { spell = C_Item.GetItemSpell, inst = C_Item.GetItemInfoInstant, name = C_Item.GetItemNameByID,
        cached = C_Item.IsItemDataCachedByID, load = C_Item.RequestLoadItemDataByID, usable = C_Item.IsUsableItem,
        consumable = C_Item.IsConsumableItem, stack = C_Item.GetItemMaxStackSizeByID, count = C_Item.GetItemCount,
        container = _G.C_Container }
    C_Item.GetItemSpell = function(id) local it = ITEMS[id]; if it and it.cached and it.spell then return "Use", it.spell end end
    C_Item.GetItemInfoInstant = function(id) local it = ITEMS[id]; if it then return id, "", "", "", it.icon end end
    C_Item.GetItemNameByID = function(id) local it = ITEMS[id]; return it and it.cached and it.name or nil end
    C_Item.IsItemDataCachedByID = function(id) return ITEMS[id] ~= nil and ITEMS[id].cached == true end
    local asked = {}
    C_Item.RequestLoadItemDataByID = function(id) asked[id] = true end
    C_Item.IsUsableItem = function(id) local it = ITEMS[id]; return (it and (it.count or 0) > 0) or false, false end
    C_Item.IsConsumableItem = function(id) return ITEMS[id] ~= nil and ITEMS[id].used == true end
    C_Item.GetItemMaxStackSizeByID = function(id) return ITEMS[id] and (ITEMS[id].used and 20 or 1) end
    C_Item.GetItemCount = function(id) return ITEMS[id] and ITEMS[id].count or 0 end
    _G.C_Container = { GetItemCooldown = function() return cd.start, cd.dur, 1 end }
    local ok, err = pcall(function()
        -- The keys.
        T.truthy(C.Is("i5512")); T.eq(C.ItemOf("i5512"), 5512); T.isnil(C.ItemOf("s5512")); T.isnil(C.ItemOf(11))
        -- Spells: wrong ones say why, and one the tray lists is that one.
        T.deq({ Ed.KeyForID("spell", "abc") }, { nil, "number" })
        _G.C_Spell.GetSpellName = function(sid)
            if sid == 777 then return nil end
            if sid == 6673 or sid == 5242 or sid == 6192 then return "Battle Shout" end
            return "Spell " .. sid
        end
        T.deq({ Ed.KeyForID("spell", "777") }, { nil, "spell" })
        T.eq(Ed.KeyForID("spell", "6192"), "s6673", "a rank of the list's family: that family")
        T.eq(Ed.KeyForID("spell", " 111 "), 11, "the game's piece (same name) wins")
        T.eq(Ed.KeyForID("spell", "9999"), "s9999", "anything else: a spell of its own")
        T.truthy(C.IsAdded("s9999")); T.falsy(C.IsAdded("s6673"))
        T.truthy(C.CanTrack("s9999"), "cooldown or buff: the card's What it shows picks")
        T.eq(C.Track("s9999"), "aura", "no real cooldown: its buff")
        T.truthy(C.Entry("s9999"), "known: drawn")
        AB.CdmSpells.MAGE = { { 1953, cd = true } }   -- Blink
        C.Forget()
        T.isnil(C.Entry("s1953"), "another class's spell, not known: nothing to draw")
        T.truthy(C.Entry("s8888"), "on no class's list: someone else's buff on you, drawn")
        T.eq(C.Track("s8888"), "aura")
        -- Items.
        T.deq({ Ed.KeyForID("item", "1") }, { nil, "item" })
        T.deq({ Ed.KeyForID("item", "2589") }, { nil, "use" }, "nothing to use, nothing to time")
        T.deq({ Ed.KeyForID("item", "9000") }, { nil, "wait" }, "not loaded yet")
        T.truthy(asked[9000], "asked to load")
        T.eq(Ed.KeyForID("item", "5512"), "i5512")
        T.deq({ C.Look("i5512") }, { "Healthstone", "hs" })
        T.eq(C.SpellOf("i5512"), 6262, "its use spell, for its buff")
        T.truthy(C.Entry("i5512"), "an item is always drawn")
        T.eq(C.Track("i5512"), "cooldown")
        -- Its cooldown is plain, with the global cooldown left out.
        T.falsy((C.ItemCooldown("i5512")), "ready")
        cd.start, cd.dur = GetTime(), 1
        T.falsy((C.ItemCooldown("i5512")), "a global cooldown isn't one")
        cd.start, cd.dur = GetTime() - 10, 120
        local on, d = C.ItemCooldown("i5512")
        T.truthy(on); T.truthy(d, "a duration object for the swipe and bar")
        -- Placed: the icon wears the item's cooldown, and the effects read it too.
        Ed.Choose("i5512"); Ed.Pick("icon")
        T.truthy(D.Current().pieces["i5512"], "placed")
        local e
        for _, x in ipairs(Ed.Spells()) do if x.id == "i5512" then e = x end end
        T.truthy(e and e.placed and not e.unlearned, "in the tray while placed")
        Ed.Close()
        AB.CdmRows.Refresh(); stub.RunTimers()
        local f = AB.CdmOwn.Frame("i5512")
        T.truthy(f and f:IsShown(), "our icon draws it")
        T.truthy(AB.CdmEffects.OnCooldown(f), "the effects see the item's cooldown")
        T.eq(f.ChargeCount.Current:GetText(), "1", "how many you carry")
        ITEMS[5512].count = 3
        stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
        T.eq(f.ChargeCount.Current:GetText(), "3", "follows the bags")
        ITEMS[5512].count = 0
        stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
        T.eq(f.ChargeCount.Current:GetText(), "0", "out: 0, as the game's buttons say")
        T.isnil(C.ItemCount("i7001"), "a trinket that isn't used up: no count")
        T.isnil(C.ItemCount("s9999"), "a spell: no count")
        T.deq({ C.ItemUsable("i5512") }, { false, false }, "none left: not usable (grays)")
    end)
    C_Item.GetItemSpell, C_Item.GetItemInfoInstant, C_Item.GetItemNameByID = saved.spell, saved.inst, saved.name
    C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID, C_Item.IsUsableItem = saved.cached, saved.load, saved.usable
    C_Item.IsConsumableItem, C_Item.GetItemMaxStackSizeByID, C_Item.GetItemCount = saved.consumable, saved.stack, saved.count
    _G.C_Container = saved.container
    stub.knownSpells = {}
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
