local stub = require("stub")

-- Clean Up with kept slots (Keep.lua) plans every move itself, so it has to
-- follow the "Clean up toward the end" switch the way the game's sort is told
-- to. The switch is Daylight UI's own setting (sortToEnd): the game's
-- C_Container.GetSortBagsRightToLeft didn't hold what was written in game.

-- Two plain bags of 6, the first three slots kept, the rest scattered.
local function world(toEnd, gameFlag)
    local ns = stub.bags
    local items = { [0] = {}, [1] = {} }
    local function item(id, name) return { itemID = id, hyperlink = "|Hitem:" .. id .. "|h", itemName = name, stackCount = 1, quality = 1 } end
    items[0][1], items[0][2], items[0][3] = item(11, "Hearthstone"), item(12, "Mount"), item(13, "Pick")
    items[0][6] = item(20, "Apple")
    items[1][2] = item(21, "Banana")
    items[1][6] = item(22, "Cherry")
    local slots = {}
    for _, bag in ipairs({ 0, 1 }) do
        for slot = 1, 6 do
            slots[#slots + 1] = { bag = bag, section = "bags", button = { GetID = function() return slot end } }
        end
    end
    local window = { set = { Slots = function() return slots end } }
    local Items = ns.Items
    local infoAt, freeAt = Items.InfoAt, Items.FreeAt
    Items.InfoAt = function(bag, slot) return items[bag] and items[bag][slot] end
    Items.FreeAt = function() return 0, 0 end
    _G.C_Container = _G.C_Container or {}
    local get = C_Container.GetSortBagsRightToLeft
    C_Container.GetSortBagsRightToLeft = gameFlag ~= nil and function() return gameFlag end or nil
    DaylightUI:Set("Bags", "sortToEnd", toEnd == true)
    DaylightUI.DB.Character().keepSlots = { ["0:1"] = 11, ["0:2"] = 12, ["0:3"] = 13 }
    -- Rounds of moves, as Keep's own step makes them, until nothing is left to move.
    for _ = 1, 20 do
        local moves = ns.Keep.Moves(window)
        if #moves == 0 then break end
        for _, m in ipairs(moves) do
            local a, b = m.from, m.to
            items[a.bag][a.slot], items[b.bag][b.slot] = items[b.bag][b.slot], items[a.bag][a.slot]
        end
    end
    Items.InfoAt, Items.FreeAt = infoAt, freeAt
    C_Container.GetSortBagsRightToLeft = get
    DaylightUI.DB.Character().keepSlots = {}
    return items
end

local function name(items, bag, slot) return items[bag][slot] and items[bag][slot].itemName end

T.test("bags: kept-slot Clean Up with the switch off fills right after the kept slots", function()
    stub.Load({ bags = true })
    local items = world(false, true)
    T.eq(name(items, 0, 1), "Hearthstone", "kept slots stay")
    T.eq(name(items, 0, 3), "Pick")
    T.eq(name(items, 0, 4), "Apple", "the rest starts in the first free slot")
    T.eq(name(items, 0, 5), "Banana")
    T.eq(name(items, 0, 6), "Cherry")
    T.isnil(items[1][6], "nothing left at the end of the last bag")
end)

T.test("bags: kept-slot Clean Up packs toward the end with the switch on, whatever the game's flag says", function()
    stub.Load({ bags = true })
    local items = world(true, true)
    T.eq(name(items, 0, 1), "Hearthstone", "kept slots stay")
    T.eq(name(items, 1, 6), "Apple", "the first item in the very last slot")
    T.eq(name(items, 1, 5), "Banana")
    T.isnil(items[0][4], "the front left empty")
end)

T.test("bags: kept-slot Clean Up fills from the front with the switch off, whatever the game's flag says", function()
    stub.Load({ bags = true })
    local items = world(false, false)
    T.eq(name(items, 0, 4), "Apple")
    T.isnil(items[1][6])
end)

-- Ticket (2.4.0): "First click on the radio button, the settings above flash.
-- 2nd click the slider moves and CUTTE is enabled. 3rd click - Clean Up in bags:
-- it doesn't work. 4th I drag my bags window and release -> CUTTE slider turns
-- itself off." The switch read the game's C_Container.GetSortBagsRightToLeft back
-- as its state, and in game that flag didn't hold what was written. Worst case
-- here: the game keeps answering its default whatever is written.
local function cleanupRow()
    for _, group in ipairs(DaylightUI.Options.GetPage("Bags.bags").groups) do
        for _, it in ipairs(group.items or {}) do
            if it.label == "Clean up toward the end" then return it end
        end
    end
end

local function stubbornGame()
    _G.C_Container = _G.C_Container or {}
    local game = { writes = {} }
    C_Container.GetSortBagsRightToLeft = function() return true end
    C_Container.SetSortBagsRightToLeft = function(v) game.writes[#game.writes + 1] = v end
    return game
end

T.test("bags: Clean up toward the end turns on with one click, even when the game's flag doesn't hold", function()
    stub.Load({ bags = true })
    stubbornGame()
    -- Loading without the bag world's fake C_Container errors once; count only what follows.
    local errs = #stub.errors
    local O = DaylightUI.Options
    local page, item = O.GetPage("Bags.bags"), cleanupRow()
    T.truthy(item, "the switch is on the Bags page")
    local row = CreateFrame("Frame", nil, UIParent)
    DaylightUI.Widgets.toggle(row, page, item)
    T.falsy(O.Get(page, item), "off to start")
    row.control:GetScript("OnClick")(row.control)
    T.eq(O.Get(page, item), true, "on after the first click")
    row.control:GetScript("OnClick")(row.control)
    T.eq(O.Get(page, item), false, "a second click turns it off again")
    T.eq(#stub.errors, errs, tostring(stub.errors[errs + 1]))
end)

T.test("bags: Clean up toward the end stays on when the bag window is dragged and the page redraws", function()
    stub.Load({ bags = true })
    stubbornGame()
    -- Loading without the bag world's fake C_Container errors once; count only what follows.
    local errs = #stub.errors
    local O = DaylightUI.Options
    local page, item = O.GetPage("Bags.bags"), cleanupRow()
    T.truthy(O.Set(page, item, true))
    -- A drag's release saves the window's spot, which redraws an open options page.
    DaylightUI:Set("Bags", "position", { left = 100, top = 400 })
    stub.RunTimers()
    T.eq(O.Get(page, item), true, "still on after the page read it again")
    T.eq(#stub.errors, errs, tostring(stub.errors[errs + 1]))
end)

-- Other languages number a format's holes (%1$d) and spell plurals as
-- |4one:many; (seen on a French client). Reading a bag's size line built a
-- broken pattern from that, and every bag size read errored.
T.test("bags: a game format with numbered holes and plurals still reads back", function()
    local Items = stub.bags.Items
    local fr = Items.Pattern("%1$d |4emplacement:emplacements; %2$s")
    T.eq(tonumber(("16 emplacements Sac"):match(fr)), 16, "French bag size line")
    T.eq(tonumber(("1 emplacement Sac"):match(fr)), 1, "singular too")
    local en = Items.Pattern("%d Slot %s")
    T.eq(tonumber(("14 Slot Bag"):match(en)), 14, "English still reads")
    local skill = Items.Pattern("Requiert %2$s (%1$d)")
    T.eq(tonumber(("Requiert Cuisine (110)"):match(skill)), 110, "a numbered skill line")
    T.eq(("50% off (3)"):match(Items.Pattern("50%% off (%d)")), "3", "a literal percent stays literal")
end)

-- The class reagents (Fish Oil, Shiny Fish Scales, Rune of Teleportation,
-- Arcane Powder, candles...) are white Miscellaneous items with the subclass
-- Reagent (item class 15, subclass 1 in the Forever build's item tables); only
-- the Ankh is a class 5 Reagent. They went to Miscellaneous, and a shaman read
-- that as "not a reagent, so it gets sold".
local function facts(id, classID, subClassID, quality)
    return { itemID = id, link = "|Hitem:" .. id .. "|h", classID = classID, subClassID = subClassID,
             quality = quality, count = 1, recent = false }
end

T.test("bags: class reagents land in Reagents, never Junk or Miscellaneous", function()
    stub.Load({ bags = true })
    local Cat = stub.bags.Categories
    T.eq(Cat.Assign(facts(17058, 15, 1, 1), "bags"), "reagent", "Fish Oil")
    T.eq(Cat.Assign(facts(17057, 15, 1, 1), "bags"), "reagent", "Shiny Fish Scales")
    T.eq(Cat.Assign(facts(17031, 15, 1, 1), "bags"), "reagent", "Rune of Teleportation")
    T.eq(Cat.Assign(facts(17030, 5, 0, 1), "bags"), "reagent", "the Ankh stays a reagent")
    T.eq(Cat.Assign(facts(5000, 15, 4, 1), "bags"), "misc", "other Miscellaneous items stay there")
    T.eq(Cat.Assign(facts(5001, 15, 1, 0), "bags"), "junk", "a gray item is still junk")
    local f = facts(17058, 15, 1, 1)
    T.truthy(stub.bags.Search.KEYWORDS.reagent(f), "the search word reagent finds them too")
end)
