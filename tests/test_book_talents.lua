local stub = require("stub")
local BW = require("bookworld")

-- The talents page (Book/TalentData.lua, Talents.lua, Arrows.lua): the game's tree
-- (bookworld's, from a Warrior read in game) drawn as three trees side by side.

local function load(spec)
    spec = spec or {}
    stub.Load({ before = function()
        BW.world(spec)()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
    end })
    return stub.book
end

local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end

local function openTalents(ns)
    BW.Open(BW.TALENTS)
    frame(30)
    return ns.Window.frame.pages.talents
end

local function tileOf(page, name)
    for _, box in ipairs(page.trees) do
        for _, b in ipairs(box.tiles) do
            if b:IsShown() and b.node and b.node.name == name then return b, box end
        end
    end
end

T.test("book talents: the game's tree reads as three trees in the game's order", function()
    local ns = load()
    local d = ns.TalentData.Read()
    T.eq(d.configID, BW.CONFIG)
    T.eq(#d.trees, 3)
    T.eq(d.trees[1].name, "Arms")
    T.eq(d.trees[2].name, "Fury")
    T.eq(d.trees[3].name, "Protection")
    T.eq(d.trees[2].spent, 2, "Cruelty 2/5")
    T.eq(d.spent, 2)
    T.eq(d.left, 0)
end)

T.test("book talents: grid places from positions (rows shared, columns per tree)", function()
    local ns = load()
    local d = ns.TalentData.Read()
    local function at(id) local n = d.byID[id]; return n.col, n.row end
    T.deq({ at(105938) }, { 1, 0 }, "Booming Voice")
    T.deq({ at(105933) }, { 0, 3 }, "Dual Wield Specialization: Fury's column 0")
    T.deq({ at(105932) }, { 3, 3 }, "Improved Execute")
    T.deq({ at(105949) }, { 0, 3 }, "Spearing Strike: Arms has no tile above row 3, rows still line up")
    T.deq({ at(105941) }, { 1, 6 }, "Mortal Strike")
    T.deq({ at(105962) }, { 0, 1 }, "Improved Bloodrage")
    for _, t in ipairs(d.trees) do
        T.eq(t.cols, 4)
        T.eq(t.rows, 7)
    end
end)

-- Forever keeps retired talents in its trees, parked far off the board (the game's
-- TraitNode table, build 1.60.1.70334): Hunter's old Lightning Reflexes at
-- x = 102800 and Improved Serpent Sting at y = 39300, and Priest's old Holy
-- Specialization at 9280, 21300 (x inside a tree's reach, y not). The game never
-- shows them. Put back on the grid, they sat on top of other tiles or widened a
-- tree, shrinking every tile.
T.test("book talents: a retired talent parked off the board isn't drawn, the grid keeps its size", function()
    local nodes = BW.WarriorNodes()
    nodes[#nodes + 1] = { id = 900001, spell = 990001, name = "Old Cruelty", group = BW.FURY, x = 9280, y = 21300, max = 5 }
    nodes[#nodes + 1] = { id = 900002, spell = 990002, name = "Old Enrage", group = BW.FURY, x = 102800, y = 5740, max = 5 }
    nodes[#nodes + 1] = { id = 900003, spell = 990003, name = "Old Flurry", group = BW.FURY, x = 6820, y = 39300, max = 5 }
    local ns = load({ tree = { nodes = nodes } })
    local d = ns.TalentData.Read()
    T.isnil(d.byID[900001], "Priest's old Holy Specialization")
    T.isnil(d.byID[900002], "Hunter's old Lightning Reflexes")
    T.isnil(d.byID[900003], "Hunter's old Improved Serpent Sting")
    T.eq(#d.trees[2].nodes, 12, "Fury keeps its own twelve")
    for _, t in ipairs(d.trees) do
        T.eq(t.cols, 4)
        T.eq(t.rows, 7)
    end
    local page = openTalents(ns)
    T.isnil(tileOf(page, "Old Cruelty"))
    local b = tileOf(page, "Cruelty")
    T.truthy(b:GetWidth() > 20, "tiles keep their size")
end)

T.test("book talents: N draws every tile in its place, with its rank", function()
    local ns = load()
    local page = openTalents(ns)
    T.eq(#page.trees, 3)
    local b, box = tileOf(page, "Cruelty")
    T.truthy(b)
    T.eq(box.tree.name, "Fury")
    T.eq(b.rank:GetText(), "2/5")
    T.eq(b.badge:IsShown(), true)
    local _, _, _, x, y = b:GetPoint(1)
    local pitch = select(4, tileOf(page, "Unbridled Wrath"):GetPoint(1))
    T.eq(x, pitch, "Cruelty and Unbridled Wrath share column 2")
    T.eq(y, 0)
    T.eq(box.pts:GetText(), "2")
    T.eq(page.foot.left:GetText(), "0")
    T.truthy(page.foot.split:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find("Fury 2", 1, true))
end)

T.test("book talents: tile states: full gold, part accent, available, locked gray", function()
    local ns = load({ tree = { left = 3 } })
    BW.Node(105928).rank = 0
    local page = openTalents(ns)
    local T2 = ns.Talents
    T.eq(T2.StateOf(tileOf(page, "Cruelty").node), "part")
    T.eq(T2.StateOf(tileOf(page, "Booming Voice").node), "avail")
    T.eq(T2.StateOf(tileOf(page, "Mortal Strike").node), "locked")
    T.eq(tileOf(page, "Mortal Strike").icon.__desaturated, true)
    T.eq(tileOf(page, "Mortal Strike").badge:IsShown(), false, "no rank on a locked talent")
    BW.Node(105939).rank = 5
    stub.FireEvent("TRAIT_NODE_CHANGED", 105939)
    frame(2)
    T.eq(T2.StateOf(tileOf(page, "Cruelty").node), "max")
    T.eq(tileOf(page, "Cruelty").rank:GetText(), "5/5", "a talent event redraws the shown page")
end)

T.test("book talents: arrows join the right tiles, lit once the first is full", function()
    local ns = load()
    local page = openTalents(ns)
    local _, arms = tileOf(page, "Sweeping Strikes")
    local found
    for _, a in ipairs(arms.links) do
        if a.from.name == "Sweeping Strikes" then found = a end
    end
    T.truthy(found)
    T.eq(found.to.name, "Mortal Strike")
    T.eq(found.state, "off")
    T.eq(found.head:IsShown(), true)
    T.eq(found.segs[2]:IsShown(), false, "straight down: one piece")
    local _, fury = tileOf(page, "Death Wish")
    T.eq(#fury.links, 1)
    T.eq(fury.links[1].to.name, "Flurry")
    BW.Node(105927).rank = 1
    stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", BW.TREE)
    frame(2)
    T.truthy(tileOf(page, "Death Wish").sweeping, "its ring closes first")
    T.falsy(fury.links[1].running, "the light waits for the ring")
    frame(15)
    T.truthy(fury.links[1].running, "then the light runs down it")
    frame(30)
    T.eq(fury.links[1].state, "lit")
    T.falsy(fury.links[1].running)
end)

T.test("book talents: a bent arrow goes across, then down", function()
    local nodes = BW.WarriorNodes()
    for _, n in ipairs(nodes) do if n.id == 105963 then n.edges = { 105962 } end end   -- made up: a bent one
    for _, n in ipairs(nodes) do if n.id == 105962 then n.y = 5730 end end
    local ns = load({ tree = { nodes = nodes } })
    local page = openTalents(ns)
    local _, prot = tileOf(page, "Concussion Blow")
    local bent
    for _, a in ipairs(prot.links) do if a.to.name == "Improved Bloodrage" then bent = a end end
    T.truthy(bent)
    T.eq(bent.segs[1]:IsShown(), true)
    T.eq(bent.segs[2]:IsShown(), true)
end)

T.test("book talents: a fresh character: nothing spent reads 0 everywhere", function()
    local nodes = BW.WarriorNodes()
    for _, n in ipairs(nodes) do n.rank = nil end
    local ns = load({ tree = { nodes = nodes, left = 0 } })
    local page = openTalents(ns)
    for _, box in ipairs(page.trees) do T.eq(box.pts:GetText(), "0") end
    T.eq(page.foot.left:GetText(), "0")
    T.eq(page.foot.label:GetText(), "points left")
end)

T.test("book talents: search lights matches and dims the rest", function()
    local ns = load()
    local page = openTalents(ns)
    page.search:SetText("strike")
    T.eq(tileOf(page, "Mortal Strike").hit, true)
    T.eq(tileOf(page, "Spearing Strike").hit, true)
    T.eq(tileOf(page, "Cruelty"):GetAlpha(), ns.Talents.DIM)
    T.eq(tileOf(page, "Mortal Strike"):GetAlpha(), 1)
    page.search:SetText("")
    T.eq(tileOf(page, "Cruelty"):GetAlpha(), 1)
    T.isnil(tileOf(page, "Mortal Strike").hit)
end)

-- A tooltip that keeps its lines, since the fake game has none of its own.
local function fakeTip()
    local tip = CreateFrame("Frame", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner, self.__lines = o, {} end
    function tip:IsOwned(o) return self.__owner == o end
    function tip:AddLine(t, r, g, b) self.__lines[#self.__lines + 1] = { text = t, r = r, g = g, b = b } end
    function tip:AddDoubleLine(l, rt, r, g, b, rr, rg, rb)
        self.__lines[#self.__lines + 1] = { text = l, r = r, g = g, b = b, right = rt, rr = rr, rg = rg, rb = rb }
    end
    return tip
end

local function hover(b)
    b:GetScript("OnEnter")(b)
    return GameTooltip.__lines
end

local function H(c) return DaylightUI.Win.Parts.Hex(c) end

-- A line holding text, with its color codes (text with codes) or without.
local function find(lines, text)
    for _, l in ipairs(lines) do
        local raw = tostring(l.text)
        local plain = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if raw:find(text, 1, true) or plain:find(text, 1, true) then return l end
    end
end

T.test("book talents: the tooltip has this rank and the next, and what's missing in red", function()
    local ns = load({ before = fakeTip })
    local page = openTalents(ns)
    local lines = hover(tileOf(page, "Cruelty"))
    T.truthy(find(lines, "Cruelty, rank 2."))
    T.truthy(find(lines, "Cruelty, rank 3."), "the next rank's text")
    local pop = H({ DaylightUI.Style.Pop() })
    T.truthy(find(lines, "Rank " .. pop .. "2|r/5"), "the rank count pops")
    T.truthy(find(lines, "Lowers threat by " .. pop .. "10|r%"), "the description's numbers colored like a spell's")
    lines = hover(tileOf(page, "Mortal Strike"))
    local bad = H(DaylightUI.Tips.BAD)
    local wait = find(lines, "Spend " .. bad .. "30|r more")
    T.truthy(wait, "the game's tier text, the points still missing in red")
    T.eq(wait.r, DaylightUI.Tips.TEXT[1], "the rest of the line white, not all red")
    local tr, tg, tb = ns.Talents.TreeColor(1, select(2, UnitClass("player")))
    T.truthy(wait.text:find(H({ tr, tg, tb }) .. "Arms", 1, true), "the tree in its own color")
    T.truthy(find(lines, "in " .. H(DaylightUI.Style.INK.VALUE) .. "Sweeping Strikes"), "the arrow into it")
    T.truthy(find(lines, "Mortal Strike, rank 1."), "an unlearned talent shows its first rank")
end)

-- The game's own talent tooltip shows an ability's whole spell lines
-- (C_TooltipInfo.GetTraitEntry): cost, range, cast time, cooldown, and what it
-- needs. These used to be left out.
T.test("book talents: an ability's tooltip has its cost, range, cast time, cooldown and need, in our colors", function()
    local ns = load({ before = function() fakeTip(); _G.RAGE = "Rage" end })   -- the game's power word
    local page = openTalents(ns)
    local lines = hover(tileOf(page, "Mortal Strike"))
    _G.RAGE = nil
    local INK = DaylightUI.Style.INK
    local cost = find(lines, "30 Rage")
    T.truthy(cost, "the cost")
    T.eq(cost.right, "Melee Range", "the range beside it")
    local pr, pg, pb = DaylightUI.Style.PowerColor("RAGE")
    T.eq(cost.r, pr, "the cost in rage's color")
    local cd = find(lines, "Instant")
    T.truthy(cd, "the cast time")
    T.truthy(cd.right and cd.right:find("cooldown", 1, true), "the cooldown beside it")
    T.eq(cd.r, INK.LABEL[1], "a short line is a label")
    T.eq(cd.rr, INK.LABEL[1])
    local need = find(lines, "Requires Melee Weapon")
    T.truthy(need, "what it needs")
    T.eq(need.r, INK.BAD[1], "a need not met stays red, ours")
    local desc = find(lines, "Mortal Strike, rank 1.")
    T.truthy(desc, "the description")
    T.eq(desc.r, INK.TEXT[1], "the description soft white, not the game's yellow")
    local n = 0
    for _, l in ipairs(lines) do if find({ l }, "Mortal Strike, rank 1.") then n = n + 1 end end
    T.eq(n, 1, "the description once")
    -- a passive talent: only its description, as before
    lines = hover(tileOf(page, "Cruelty"))
    T.falsy(find(lines, "cooldown"))
    T.truthy(find(lines, "Cruelty, rank 2."))
end)

T.test("book talents: a talent whose spell isn't loaded yet gets its text when it lands", function()
    local ns = load({ before = fakeTip })
    local page = openTalents(ns)
    local tile = tileOf(page, "Cruelty")
    BW.uncached[tile.node.spellID] = true
    local lines = hover(tile)
    T.falsy(find(lines, "Cruelty, rank 2."))
    T.eq(BW.Calls("RequestLoadSpellData")[1][1], tile.node.spellID, "asked the client for it")
    BW.uncached[tile.node.spellID] = nil
    stub.FireEvent("SPELL_DATA_LOAD_RESULT", tile.node.spellID, true)
    T.truthy(find(GameTooltip.__lines, "Cruelty, rank 2."), "drawn again with the text")
end)

T.test("book talents: a click redraws the open tooltip with the new rank", function()
    local ns = load({ before = fakeTip, tree = { left = 3 } })
    local page = openTalents(ns)
    local b = tileOf(page, "Booming Voice")
    T.truthy(find(hover(b), "Rank " .. H(DaylightUI.Style.INK.OFF) .. "0|r/5"))
    b:Click("LeftButton")
    frame(2)
    T.truthy(GameTooltip:IsOwned(b), "still the hovered tile's")
    T.truthy(find(GameTooltip.__lines, "Rank " .. H(ns.Talents.STAGED) .. "1|r/5"), "the new rank, without leaving and coming back")
end)

T.test("book talents: no tree from the game: a calm note, no error", function()
    local ns = load({ before = function() C_Traits = nil end })
    local page = openTalents(ns)
    T.eq(page.note:IsShown(), true)
    T.eq(page.search:IsShown(), false)
end)

T.test("book talents: a hidden node isn't drawn", function()
    local nodes = BW.WarriorNodes()
    for _, n in ipairs(nodes) do if n.id == 105926 then n.hidden = true end end
    local ns = load({ tree = { nodes = nodes } })
    local page = openTalents(ns)
    T.isnil(tileOf(page, "Improved Intercept"))
end)

T.test("book talents: talent events while the page is hidden read nothing", function()
    local ns = load()
    local reads = 0
    local read = ns.TalentData.Read
    ns.TalentData.Read = function(...) reads = reads + 1; return read(...) end
    stub.FireEvent("TRAIT_CONFIG_UPDATED", BW.CONFIG)
    frame(2)
    T.eq(reads, 0)
    ns.TalentData.Read = read
end)

T.test("book talents: each tile wears its talent's icon, the game's way (GetSpellTexture's second answer)", function()
    local ns = load()
    local page = openTalents(ns)
    local b = tileOf(page, "Cruelty")
    T.eq(b.icon:GetTexture(), 130000 + 105939 % 1000)
end)

T.test("book talents: the tier line counts what's still missing, as the game gives it", function()
    local ns = load({ before = fakeTip })
    local page = openTalents(ns)
    -- Fury has 2 (Cruelty): Unbridled Wrath (row 1) needs 5, so 3 more.
    local lines = hover(tileOf(page, "Unbridled Wrath"))
    T.truthy(find(lines, "Spend 3 more"), "not 5, not 1")
    -- Piercing Howl (row 2): 10, so 8 more.
    lines = hover(tileOf(page, "Piercing Howl"))
    T.truthy(find(lines, "Spend 8 more"))
end)

T.test("book talents: the tree's word stays plural (Enhancement Talents), even for one point", function()
    local nodes = BW.WarriorNodes()
    for _, n in ipairs(nodes) do if n.id == 105939 then n.rank = 4 end end   -- Fury 4, so row 1 needs 1 more
    local ns = load({ before = fakeTip, tree = { nodes = nodes } })
    local page = openTalents(ns)
    local l = find(hover(tileOf(page, "Unbridled Wrath")), "Spend 1 more")
    T.truthy(l)
    T.truthy(find({ l }, "in Fury Talents"), l.text)
    T.truthy(find({ l }, "1 more |4point:points;"), "the points word is still the client's to pick")
end)

-- Text color: each tree has its own warm tint, points left pop in the accent, and
-- none left reads as off.
T.test("book talents: tree colors differ and aren't gray; points left pop only when there are some", function()
    local ns = load({ tree = { left = 3 } })
    local seen = {}
    for i = 1, 3 do
        local r, g, b = ns.Talents.TreeColor(i, "WARRIOR")
        T.truthy(math.max(r, g, b) - math.min(r, g, b) > 0.04, "tree " .. i .. " not gray")
        local k = string.format("%.2f %.2f %.2f", r, g, b)
        T.falsy(seen[k], "tree " .. i .. " its own color"); seen[k] = true
    end
    local page = openTalents(ns)
    T.rgb({ page.foot.left:GetTextColor() }, { DaylightUI.Style.Pop() }, "points left pop")
    BW.tree.left = 0
    ns.Talents.Fill(page)
    T.rgb({ page.foot.left:GetTextColor() }, DaylightUI.Style.INK.OFF, "none left: off")
end)

-- ---------------------------------------------------------------------
-- Builds and the loadout string (Book/Builds.lua, LoadoutString.lua)
-- ---------------------------------------------------------------------

local function ranksOf(...)
    local out = {}
    for i = 1, select("#", ...), 2 do out[select(i, ...)] = select(i + 1, ...) end
    return out
end

local CRUELTY, BOOMING, UNBRIDLED, IMPALE = 105939, 105938, 105937, 105947

T.test("book builds: save keeps the set's points, staged too, per character and set; a name is replaced", function()
    local ns = load({ tree = { left = 5 } })
    openTalents(ns)
    local d = ns.TalentData.Read(); ns.Spend.Buy(d.byID[BOOMING], d)
    local b = ns.Builds.Save("Fury")
    T.deq(b.ranks, ranksOf(CRUELTY, 2, BOOMING, 1))
    local saved = DaylightUI.DB.Character().talentBuilds[1]
    T.eq(#saved, 1)
    T.eq(saved[1].name, "Fury")
    local d = ns.TalentData.Read(); ns.Spend.Buy(d.byID[BOOMING], d)
    ns.Builds.Save(" Fury ")
    T.eq(#saved, 1, "the same name replaces")
    T.eq(saved[1].ranks[BOOMING], 2)
    T.isnil(ns.Builds.Save(""), "no name, no build")
end)

T.test("book builds: loading stages rank by rank through the game, top row first, nothing applied", function()
    local ns = load({ tree = { left = 10 } })
    openTalents(ns)
    local staged, why = ns.Builds.Load({ name = "x", ranks = ranksOf(CRUELTY, 2, UNBRIDLED, 3, BOOMING, 5) })
    T.eq(staged, 8)
    T.isnil(why)
    local calls = BW.Calls("PurchaseRank")
    T.eq(#calls, 8)
    for i = 1, 5 do T.eq(calls[i][2], BOOMING, "row 1 first") end
    for i = 6, 8 do T.eq(calls[i][2], UNBRIDLED) end
    T.eq(#BW.Calls("CommitConfig"), 0, "only staged: Apply learns them")
    T.eq(BW.Node(BOOMING).staged, 5)
end)

-- After each staged rank only the build's own talents and the points are asked
-- again (the game's answers), never the whole tree.
T.test("book builds: loading reads the whole tree once, then only the build's talents", function()
    local ns = load({ tree = { left = 10 } })
    openTalents(ns)
    local reads, get = 0, C_Traits.GetTreeNodes
    C_Traits.GetTreeNodes = function(...) reads = reads + 1; return get(...) end
    local staged = ns.Builds.Load({ name = "x", ranks = ranksOf(CRUELTY, 2, UNBRIDLED, 3, BOOMING, 5) })
    C_Traits.GetTreeNodes = get
    T.eq(staged, 8)
    T.eq(reads, 1, "one whole read")
end)

T.test("book builds: points you don't have yet are left for later", function()
    local ns = load({ tree = { left = 3 } })
    openTalents(ns)
    local staged, why = ns.Builds.Load({ name = "x", ranks = ranksOf(CRUELTY, 2, BOOMING, 5) })
    T.eq(staged, 3)
    T.truthy(why and why:find("left for later", 1, true), why)
end)

T.test("book builds: a build without a talent you learned is refused (a trainer resets them)", function()
    local ns = load({ tree = { left = 10 } })
    openTalents(ns)
    local staged, why = ns.Builds.Load({ name = "x", ranks = ranksOf(BOOMING, 5) })
    T.eq(staged, 0)
    T.truthy(why and why:find("trainer", 1, true))
    T.eq(#BW.Calls("PurchaseRank"), 0)
end)

T.test("book builds: loading drops what was staged first, and a set not in use is refused", function()
    local ns = load({ tree = { left = 10 }, dual = true })
    openTalents(ns)
    local d = ns.TalentData.Read(); ns.Spend.Buy(d.byID[BOOMING], d)
    ns.Builds.Load({ name = "x", ranks = ranksOf(CRUELTY, 2, IMPALE, 0, UNBRIDLED, 0) })
    T.eq(#BW.Calls("RollbackConfig"), 1)
    T.eq(BW.Node(BOOMING).staged, 0)
    ns.Talents.ShowSet(2)
    local staged, why = ns.Builds.Load({ name = "x", ranks = {} })
    T.eq(staged, 0)
    T.truthy(why and why:find("Activate", 1, true))
end)

T.test("book builds: a copied talent string pastes back to the same points", function()
    local ns = load({ tree = { left = 10 } })
    openTalents(ns)
    ns.Builds.Load({ name = "x", ranks = ranksOf(CRUELTY, 2, BOOMING, 5, UNBRIDLED, 2) })
    local text = ns.Builds.Copy()
    T.truthy(type(text) == "string" and #text > 20)
    ns.Spend.Undo()
    T.eq(BW.Node(BOOMING).staged, 0)
    local staged = ns.Builds.Paste(text)
    T.eq(staged, 7)
    T.eq(BW.Node(BOOMING).rank, 5)
    T.eq(BW.Node(UNBRIDLED).rank, 2)
    -- the game's own string wins when the client makes one
    C_Traits.GenerateImportString = function() return "GAME" end
    T.eq(ns.Builds.Copy(), "GAME")
end)

-- The game's writer (ExportUtil.ConvertToBase64 in Blizzard_SharedXMLBase), copied
-- as is so the addon's reader is checked against it.
local function gameBase64(entries)
    local chars = { [0] = "A" }
    for n = 1, 25 do table.insert(chars, string.char(65 + n)) end
    for n = 0, 25 do table.insert(chars, string.char(97 + n)) end
    for n = 0, 9 do table.insert(chars, tostring(n)) end
    table.insert(chars, "+"); table.insert(chars, "/")
    local out, cur, reserved = "", 0, 0
    for _, e in ipairs(entries) do
        local value, need = e[2], e[1]
        while need > 0 do
            local space = 6 - reserved
            local rem = value % bit.lshift(1, space)
            value = bit.rshift(value, space)
            cur = cur + bit.lshift(rem, reserved)
            if space > need then
                reserved = (reserved + need) % 6
                need = 0
            else
                out = out .. chars[cur]
                cur, reserved, need = 0, 0, need - space
            end
        end
    end
    if reserved > 0 then out = out .. chars[cur] end
    return out
end

T.test("book builds: a string written the game's way reads right; bad strings say why", function()
    local ns = load({ tree = { left = 10 } })
    openTalents(ns)
    local e = { { 8, 1 }, { 16, 0 } }
    for _ = 1, 16 do e[#e + 1] = { 8, 0 } end
    for _, id in ipairs(C_Traits.GetTreeNodes(BW.TREE)) do
        if id == BOOMING then          -- selected, bought, partly: 3 ranks
            for _, v in ipairs({ { 1, 1 }, { 1, 1 }, { 1, 1 }, { 6, 3 }, { 1, 0 } }) do e[#e + 1] = v end
        elseif id == CRUELTY then      -- selected, bought, full (5)
            for _, v in ipairs({ { 1, 1 }, { 1, 1 }, { 1, 0 }, { 1, 0 } }) do e[#e + 1] = v end
        else
            e[#e + 1] = { 1, 0 }
        end
    end
    local got = ns.LoadoutString.Decode(gameBase64(e), BW.CONFIG)
    T.deq(got.ranks, ranksOf(BOOMING, 3, CRUELTY, 5))
    local _, why = ns.LoadoutString.Decode("not a string!", BW.CONFIG)
    T.truthy(why)
    C_Traits.GetLoadoutSerializationVersion = function() return 2 end
    local none, old = ns.LoadoutString.Decode(gameBase64(e), BW.CONFIG)
    T.isnil(none)
    T.truthy(old)
end)

T.test("book builds: the Builds button saves through its box and loads from its menu", function()
    local ns = load({ tree = { left = 10 } })
    local page = openTalents(ns)
    T.truthy(page.builds:IsShown())
    ns.Builds.Load({ name = "x", ranks = ranksOf(CRUELTY, 2, BOOMING, 2) })
    page.builds:Click()
    T.truthy(DaylightUI.Widgets.menuOwner == page.builds)
    ns.Builds.OpenBox("save")
    page.buildBox.edit:SetText("Lvl 20")
    ns.Builds.Confirm()
    T.falsy(DaylightUI.Motion.Shown(page.buildBox), "closing: it fades out")
    T.eq(ns.Builds.List()[1].name, "Lvl 20")
    ns.Spend.Undo()
    page.builds:Click()
    DaylightUI.Widgets.MenuRow(1):Click()
    T.eq(BW.Node(BOOMING).staged, 2)
    T.truthy(page.buildSay:IsShown())
end)

-- French: "Appliquer changements" ran into Undo in a fixed 228 px strip.
T.test("book talents: a long Apply label in another language never runs into Undo or the split", function()
    local ns = load()
    TALENT_FRAME_APPLY_BUTTON_TEXT = "Appliquer changements"
    local page = openTalents(ns)
    ns.Talents.Buttons(page)
    local apply, undo = page.actions.buttons[1], page.actions.buttons[2]
    T.truthy(apply:IsShown() and undo:IsShown())
    local strip = page.actions.frame:GetWidth()
    T.truthy(strip >= apply:GetWidth() + undo:GetWidth() + 8, "the strip holds both buttons side by side")
    T.truthy(apply:GetWidth() > 150, "Apply as wide as its words")
    -- What's left of the footer for the text: the split stops short of the strip.
    local foot = page.foot
    local used = foot.left:GetStringWidth() + 6 + foot.label:GetStringWidth() + 14 + foot.split:GetStringWidth()
    T.truthy(used <= foot:GetWidth() + 8 - strip - 16, "the split per tree stops before the buttons")
    TALENT_FRAME_APPLY_BUTTON_TEXT = nil
end)

-- Not so cramped horizontally: columns sit further apart than rows (Talents.WIDE),
-- and tiles keep their size.
T.test("book talents: columns are a little further apart than rows", function()
    local ns = load()
    local page = openTalents(ns)
    local function at(name) local _, _, _, x, y = tileOf(page, name):GetPoint(1); return x, y end
    local bx = at("Booming Voice")              -- Fury column 1, row 0
    local cx, cy = at("Cruelty")                -- column 2, row 0
    local _, uy = at("Unbridled Wrath")         -- column 2, row 1
    local across, down = cx - bx, cy - uy
    T.truthy(across > down, "across " .. across .. " vs down " .. down)
    T.truthy(tileOf(page, "Cruelty"):GetWidth() >= 36, "tiles keep their size")
end)

T.test("book talents: a read-only box draws a tree and its clicks buy nothing", function()
    local ns = load()
    local T2 = ns.Talents
    local data = ns.TalentData.Read()
    local box = T2.MakeTree(UIParent)
    box.readOnly, box.token = true, "WARRIOR"
    local pitch, size, px = T2.Fit(data, 220, 400)
    T2.FillTree(box, data.trees[2], pitch, size, data, px)
    T.eq(box.data, data)
    local b
    for _, t in ipairs(box.tiles) do if t.node and t.node.name == "Booming Voice" then b = t end end
    T.truthy(b, "Fury's first talent drawn")
    T.eq(b.box, box)
    T2.Click(b, "LeftButton")
    T2.Click(b, "RightButton")
    T.eq(#BW.Calls("PurchaseRank"), 0)
    T.eq(#BW.Calls("RefundRank"), 0)
    b:GetScript("OnEnter")(b)
    T.noerror(function() T2.Tip(b) end)
end)
