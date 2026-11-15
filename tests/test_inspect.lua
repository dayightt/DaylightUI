local stub = require("stub")
local CW = require("charworld")

-- The inspect window.

T.test("inspect: Gear reads another unit's slots, the player's stay the player's", function()
    stub.Load({ before = CW.world({ items = { Head = CW.item("Lionheart Helm", { quality = 4, level = 65 }) } }) })
    local Gear = stub.character.Gear
    local seen = {}
    local link = _G.GetInventoryItemLink
    _G.GetInventoryItemLink = function(unit, id) seen[#seen + 1] = unit; return link(unit, id) end
    Gear.Read("Head", nil, "target")
    T.eq(seen[#seen], "target")
    Gear.Read("Head")
    T.eq(seen[#seen], "player")
end)

T.test("inspect: Slots.Make into a table of its own leaves the character window's alone", function()
    stub.Load({ before = CW.world({}) })
    local Slots = stub.character.Slots
    local before = Slots.frames.Head
    local mine = {}
    local h = Slots.Make(UIParent, "Head", "left", nil, mine)
    T.eq(mine.Head, h)
    T.eq(Slots.frames.Head, before)
end)

-- ---------------------------------------------------------------------
-- The window and the follower (Inspect/Window.lua)
-- ---------------------------------------------------------------------
local IW = require("inspectworld")

local function load(spec)
    stub.Load({ before = IW.world(spec) })
    return stub.inspect
end

-- A frame of the world: timers, the follower's look, the moves.
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

T.test("inspect: ours opens in the game's place, its title their name in their class color", function()
    local ns = load()
    IW.Inspect("target")
    frame(30)
    local f = ns.Window.frame
    T.truthy(DaylightUI.Win.IsOpen(f), "ours open")
    T.eq(InspectFrame:GetParent(), DaylightUI.Win.Followers.veil, "the game's frame is under the veil")
    T.truthy(InspectFrame:IsShown(), "the game's frame still counts as shown")
    T.eq(f.title:GetText(), "Garrick Stone")
    T.rgb({ f.title:GetTextColor() }, { DaylightUI.Style.ClassTextColor("WARRIOR") })
    T.truthy((f.sub:GetText() or ""):find("60"), "the sub line has their level")
end)

T.test("inspect: the game's frame hides (target changed): ours closes", function()
    local ns = load()
    IW.Inspect("target")
    frame(30)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    frame(30)
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame))
    T.isnil(ns.Window.unit, "the old player is forgotten")
    T.truthy(#IW.Calls("ClearInspectPlayer") > 0, "the game's OnHide still ran")
end)

T.test("inspect: our X closes the game's frame too", function()
    local ns = load()
    IW.Inspect("target")
    frame(30)
    ns.Window.frame.close:Click()
    frame(30)
    T.falsy(InspectFrame:IsShown())
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame))
end)

T.test("inspect: a second inspect while ours is open shows the new player", function()
    local ns = load()
    IW.Inspect("target")
    frame(30)
    stub.units.target = { name = "Mira", class = "PALADIN", level = 58, isPlayer = true, guid = "Player-3" }
    IW.Inspect("target")
    frame(30)
    T.truthy(DaylightUI.Win.IsOpen(ns.Window.frame))
    T.eq(ns.Window.frame.title:GetText(), "Mira")
end)

T.test("inspect: switched off, the game's frame is left alone", function()
    local ns = load({ enabled = false })
    IW.Inspect("target")
    frame(30)
    T.isnil(ns.Window.frame)
    T.truthy(InspectFrame:IsShown())
    T.eq(InspectFrame:GetParent(), UIParent, "never parked")
end)

T.test("inspect: opened in a fight before it was parked, the game's window stays the game's", function()
    local ns = load()
    stub.EnterCombat()
    IW.Inspect("target")
    frame(30)
    T.eq(InspectFrame:GetParent(), UIParent, "not parked in combat")
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame))
    stub.LeaveCombat()
end)

-- ---------------------------------------------------------------------
-- The gear page (Inspect/Gear.lua, Inspect/Model.lua)
-- ---------------------------------------------------------------------

local function warriorGear()
    return { target = {
        [1] = CW.item("Lionheart Helm", { quality = 4, level = 65, enchantId = 2583, enchant = "+10 Defense" }),
        [5] = CW.item("Breastplate of Might", { quality = 4, level = 66 }),
        [16] = CW.item("Ashkandi", { quality = 4, level = 77 }),
    } }
end

T.test("inspect gear: their slots, item level and enchants", function()
    local ns = load({ gear = warriorGear(), itemLevel = { target = 63.4 } })
    IW.Inspect("target")
    frame(30)
    local page = ns.Window.frame.pages.gear
    T.eq(page.slots.Head.name:GetText(), "Lionheart Helm")
    T.truthy(string.find(page.slots.Head.line:GetText() or "", "65", 1, true), "their item's level")
    T.eq(page.slots.Head.enchant:GetText(), "+10 Defense")
    T.rgb({ page.slots.Head.enchant:GetTextColor() }, DaylightUI.Style.INK.GOOD)
    T.eq(page.slots.Shirt.name:GetText(), DaylightUI.Char.Gear.LABEL.Shirt)
    T.rgb({ page.slots.Shirt.name:GetTextColor() }, DaylightUI.Style.INK.OFF)
    T.truthy(string.find(page.level:GetText() or "", "63", 1, true), "average item level shown")
    T.rgb({ page.level:GetTextColor() }, { DaylightUI.Style.Pop() })
    T.falsy(page.note:IsShown(), "no waiting text with gear in")
end)

T.test("inspect gear: a missing enchant on an enchantable slot says so in the warn color", function()
    local ns = load({ gear = warriorGear() })
    IW.Inspect("target")
    frame(30)
    local slots = ns.Window.frame.pages.gear.slots
    T.truthy(slots.Chest.enchant:IsShown())
    T.rgb({ slots.Chest.enchant:GetTextColor() }, DaylightUI.Style.INK.WARN)
    T.falsy(slots.Shirt.enchant:IsShown(), "an empty slot asks for nothing")
end)

-- The fake's timers keep no time: hold the later ones (the re-reads) until
-- the test lets them run.
local function holdLater()
    local held, after = {}, C_Timer.After
    C_Timer.After = function(s, fn) if s > 0 then held[#held + 1] = fn else after(s, fn) end end
    return function() C_Timer.After = after; for _, fn in ipairs(held) do fn() end end
end

T.test("inspect gear: late links fill in", function()
    local ns = load({ gear = warriorGear(), late = true })
    local release = holdLater()
    IW.Inspect("target")
    frame(30)
    local page = ns.Window.frame.pages.gear
    T.eq(page.slots.Head.name:GetText(), DaylightUI.Char.Gear.LABEL.Head, "empty at first")
    T.truthy(page.note:IsShown(), "a soft wait while the gear loads")
    IW.Arrive("target")
    frame(1)
    T.eq(page.slots.Head.name:GetText(), "Lionheart Helm")
    T.eq(page.slots.Head.enchant:GetText(), "+10 Defense")
    T.falsy(page.note:IsShown())
    release()
end)

T.test("inspect gear: links that come with no event still fill in", function()
    local ns = load({ gear = warriorGear(), late = true })
    local release = holdLater()
    IW.Inspect("target")
    frame(30)
    IW.Arrive("target", true)
    frame(1)
    local slots = ns.Window.frame.pages.gear.slots
    T.eq(slots.Head.name:GetText(), DaylightUI.Char.Gear.LABEL.Head, "nothing told us yet")
    release()
    frame(1)
    T.eq(slots.Head.name:GetText(), "Lionheart Helm", "the re-read found it")
end)

T.test("inspect gear: a re-read left from an old inspect is dropped", function()
    local ns = load({ gear = warriorGear() })
    local release = holdLater()
    IW.Inspect("target")
    frame(30)
    local wave = ns.Window.wave
    IW.Inspect("target")
    frame(30)
    T.truthy(ns.Window.wave > wave, "a new inspect starts new re-reads")
    release()
end)

-- The model: SetUnit (dressed, faded in) once per player shown, Dress
-- (dressed again, no fade) when their gear changes while open.
local function countModel(ns)
    local n = { set = 0, dress = 0 }
    local set, dress = ns.Model.SetUnit, ns.Model.Dress
    ns.Model.SetUnit = function(...) n.set = n.set + 1; return set(...) end
    ns.Model.Dress = function(...) n.dress = n.dress + 1; if dress then return dress(...) end end
    return n
end

T.test("inspect model: the same player inspected again is dressed again", function()
    local ns = load({ gear = warriorGear() })
    local n = countModel(ns)
    IW.Inspect("target")
    frame(30)
    T.eq(n.set, 1)
    IW.Hide()
    frame(30)
    IW.Inspect("target")
    frame(30)
    T.eq(n.set, 2, "a new open shows them fresh, not the old model")
end)

T.test("inspect model: late links dress the model again, without its fade", function()
    local ns = load({ gear = warriorGear(), late = true })
    local release = holdLater()
    local n = countModel(ns)
    IW.Inspect("target")
    frame(30)
    T.eq(n.set, 1)
    IW.Arrive("target")
    frame(1)
    T.eq(n.set, 1, "no second fade-in")
    T.eq(n.dress, 1, "their gear on the model")
    release()
    frame(1)
    T.eq(n.dress, 1, "a re-read with nothing new leaves it")
end)

T.test("inspect model: an unreadable guid still sets the model once per open", function()
    local guid = stub.Secret("Player-2")
    local ns = load({ gear = warriorGear(), units = {
        player = { name = "Me", class = "MAGE", level = 60, isPlayer = true, guid = "Player-1" },
        target = { name = "Garrick", lastName = "Stone", class = "WARRIOR", level = 60, isPlayer = true, guid = guid },
    } })
    local release = holdLater()
    local n = countModel(ns)
    IW.Inspect("target")
    frame(30)
    stub.FireEvent("UNIT_INVENTORY_CHANGED", "target")
    release()
    frame(1)
    T.eq(n.set, 1, "no blink on every re-read")
end)

-- Two players behind secret guids (a PvP match, a restricted map), both on
-- "target": a new inspect is a new player, dressed and faded in afresh.
T.test("inspect model: a second player with an unreadable guid is shown fresh", function()
    local ns = load({ gear = warriorGear(), units = {
        player = { name = "Me", class = "MAGE", level = 60, isPlayer = true, guid = "Player-1" },
        target = { name = "Garrick", lastName = "Stone", class = "WARRIOR", level = 60, isPlayer = true, guid = stub.Secret("Player-2") },
    } })
    local n = countModel(ns)
    IW.Inspect("target")
    frame(30)
    T.eq(n.set, 1)
    stub.units.target = { name = "Mira", class = "PALADIN", level = 58, isPlayer = true, guid = stub.Secret("Player-3") }
    IW.Inspect("target")
    frame(30)
    T.eq(n.set, 2, "the new player's model")
end)

T.test("inspect gear: a second player leaves none of the first one's gear", function()
    local ns = load({ gear = warriorGear() })
    IW.Inspect("target")
    frame(30)
    stub.units.target = { name = "Mira", class = "PALADIN", level = 58, isPlayer = true, guid = "Player-3" }
    IW.state.gear.target = { [5] = CW.item("Robe", { quality = 2, level = 40 }) }
    IW.Inspect("target")
    frame(30)
    local slots = ns.Window.frame.pages.gear.slots
    T.eq(slots.Head.name:GetText(), DaylightUI.Char.Gear.LABEL.Head)
    T.falsy(slots.Head.enchant:IsShown())
    T.eq(slots.Chest.name:GetText(), "Robe")
end)

T.test("inspect gear: the character window keeps its own slots", function()
    local ns = load({ gear = warriorGear() })
    IW.Inspect("target")
    frame(30)
    T.truthy(DaylightUI.Char.Slots.frames.Head ~= ns.Window.frame.pages.gear.slots.Head)
end)

T.test("inspect gear: hovering a slot shows their item's tooltip", function()
    local ns = load({ gear = warriorGear() })
    IW.Inspect("target")
    frame(30)
    local seen
    GameTooltip.SetInventoryItem = function(_, unit, id) seen = { unit, id } end
    ns.GearPage.Tip(ns.Window.frame.pages.gear.slots.Head)
    T.deq(seen, { "target", 1 })
end)

-- ---------------------------------------------------------------------
-- The talents page (Inspect/Talents.lua)
-- ---------------------------------------------------------------------
local BW = require("bookworld")

local function warriorTree()
    local nodes = BW.WarriorNodes()
    for _, n in ipairs(nodes) do
        if n.name == "Deep Wounds" then n.rank = 3 end
        if n.name == "Mortal Strike" then n.rank = 1 end
    end
    return { nodes = nodes }
end

local function talents(ns) return ns.Window.frame.pages.talents end

local function shownTiles(page)
    local shown = 0
    for _, box in ipairs(page.trees) do
        if box:IsShown() then for _, b in ipairs(box.tiles) do if b:IsShown() then shown = shown + 1 end end end
    end
    return shown
end

T.test("inspect talents: a tab beside the gear, their trees read-only, points per tree", function()
    local ns = load({ tree = warriorTree() })
    IW.Inspect("target")
    frame(30)
    local f = ns.Window.frame
    T.truthy(f.defs.talents, "the page is there")
    T.eq(f.current, "gear", "gear first")
    ns.Window.Show("talents")
    frame(30)
    local page = talents(ns)
    T.eq(f.current, "talents")
    T.eq(#page.trees, 3)
    T.truthy(page.trees[1].readOnly)
    T.eq(page.trees[1].token, "WARRIOR")
    T.eq(page.trees[3].index, 3)
    T.truthy(string.find(page.split:GetText(), "Arms", 1, true))
    T.eq(shownTiles(page), #BW.WarriorNodes())
    T.falsy(page.note:IsShown())
end)

T.test("inspect talents: clicks buy nothing", function()
    local ns = load({ tree = warriorTree(), book = { tree = { left = 10 } } })
    IW.Inspect("target")
    frame(30)
    ns.Window.Show("talents")
    frame(30)
    for _, box in ipairs(talents(ns).trees) do
        for _, b in ipairs(box.tiles) do
            if b.node then
                DaylightUI.Book.Talents.Click(b, "LeftButton")
                DaylightUI.Book.Talents.Click(b, "RightButton")
            end
        end
    end
    frame(5)
    T.eq(#BW.Calls("PurchaseRank"), 0)
    T.eq(#BW.Calls("RefundRank"), 0)
end)

T.test("inspect talents: a second inspect (another class, fewer talents) leaves no old tiles", function()
    local ns = load({ tree = warriorTree() })
    IW.Inspect("target")
    frame(30)
    ns.Window.Show("talents")
    frame(30)
    T.eq(shownTiles(talents(ns)), #BW.WarriorNodes())
    BW.trees[IW.CONFIG] = BW.NewTree({ nodes = { BW.WarriorNodes()[1] } })
    stub.units.target = { name = "Mira", class = "SHAMAN", level = 40, isPlayer = true, guid = "Player-3" }
    IW.Inspect("target")
    frame(30)
    local page = talents(ns)
    T.eq(shownTiles(page), 1)
    T.eq(page.trees[1].token, "SHAMAN")
    T.falsy(page.trees[2]:IsShown(), "the trees it lacks are gone")
end)

T.test("inspect talents: a re-read with nothing new draws nothing again", function()
    local ns = load({ tree = warriorTree() })
    IW.Inspect("target")
    frame(30)
    ns.Window.Show("talents")
    frame(30)
    local Talents = DaylightUI.Book.Talents
    local fill, n = Talents.FillTree, 0
    Talents.FillTree = function(...) n = n + 1; return fill(...) end
    ns.Window.Refill()
    T.eq(n, 0, "same player, same ranks")
    BW.trees[IW.CONFIG].nodes[1].rank = 1
    ns.Window.Refill()
    Talents.FillTree = fill
    T.truthy(n > 0, "a rank changed: drawn again")
end)

T.test("inspect talents: no tree to read says so calmly", function()
    local ns = load({ tree = warriorTree() })
    BW.trees[IW.CONFIG] = nil
    IW.Inspect("target")
    frame(30)
    ns.Window.Show("talents")
    frame(30)
    local page = talents(ns)
    T.truthy(page.note:IsShown())
    T.eq(page.note:GetText(), "No talents yet.")
    T.rgb({ page.note:GetTextColor() }, DaylightUI.Style.INK.LABEL)
    T.eq(shownTiles(page), 0)
    T.eq(#stub.errors, 0)
end)

T.test("inspect talents: opened in a fight, drawn with nothing protected touched", function()
    local ns = load({ tree = warriorTree() })
    IW.Inspect("target")
    frame(30)
    stub.EnterCombat()
    ns.Window.Show("talents")
    frame(30)
    T.eq(shownTiles(talents(ns)), #BW.WarriorNodes())
    T.eq(#stub.errors, 0)
    stub.LeaveCombat()
end)

T.test("inspect: not dragged, ours sits where the game's window was (its top-left)", function()
    local ns = load()
    IW.Inspect("target")
    frame(30)
    local p, rel, rp, x, y = ns.Window.frame:GetPoint(1)
    T.eq(p, "TOPLEFT")
    T.eq(rel, InspectFrame)
    T.eq(rp, "TOPLEFT")
    T.eq(x, 0)
    T.eq(y, 0)
end)

T.test("inspect on a controller: Y on a gear slot puts it in the dressing room, as the game's", function()
    local ns = load({ gear = warriorGear() })
    IW.Inspect("target")
    frame(30)
    local f = ns.Window.frame
    local head = f.pages.gear.slots.Head
    local y = f.padKeys[1]
    T.eq(y.key, "Y")
    T.truthy(y.when(head), "a slot with an item")
    T.falsy(y.when(nil), "nothing picked: nothing to show")
end)
