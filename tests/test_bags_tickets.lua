local stub = require("stub")

-- Clean Up with kept slots (Keep.lua) plans every move itself, so it has to
-- read the game's clean up direction the way the game's own sort does.
-- C_Container.GetSortBagsRightToLeft is true by default on Forever, and the
-- game's sort then fills from the backpack's first slot; turned off it packs
-- toward the end of the last bag (EllesmereUI's "Sort to Bottom" turns it
-- off for that).

-- Two plain bags of 6, the first three slots kept, the rest scattered.
local function world(rightToLeft)
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
    C_Container.GetSortBagsRightToLeft = rightToLeft ~= nil and function() return rightToLeft end or nil
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

T.test("bags: kept-slot Clean Up with the game's normal direction fills right after the kept slots", function()
    stub.Load({ bags = true })
    local items = world(true)
    T.eq(name(items, 0, 1), "Hearthstone", "kept slots stay")
    T.eq(name(items, 0, 3), "Pick")
    T.eq(name(items, 0, 4), "Apple", "the rest starts in the first free slot")
    T.eq(name(items, 0, 5), "Banana")
    T.eq(name(items, 0, 6), "Cherry")
    T.isnil(items[1][6], "nothing left at the end of the last bag")
end)

T.test("bags: kept-slot Clean Up packs toward the end only with the game's direction turned off", function()
    stub.Load({ bags = true })
    local items = world(false)
    T.eq(name(items, 0, 1), "Hearthstone", "kept slots stay")
    T.eq(name(items, 1, 6), "Apple", "the first item in the very last slot")
    T.eq(name(items, 1, 5), "Banana")
    T.isnil(items[0][4], "the front left empty")
end)

T.test("bags: kept-slot Clean Up fills from the front when the game can't say its direction", function()
    stub.Load({ bags = true })
    local items = world(nil)
    T.eq(name(items, 0, 4), "Apple")
    T.isnil(items[1][6])
end)

T.test("bags: the Clean up toward the end switch is on when the game's right-to-left flag is off", function()
    stub.Load({ bags = true })
    local row
    for _, page in ipairs(stub.bags.OPTIONS.pages) do
        for _, group in ipairs(page.groups or {}) do
            for _, it in ipairs(group.items or {}) do
                if it.label == "Clean up toward the end" then row = it end
            end
        end
    end
    T.truthy(row, "the switch is on the Bags page")
    _G.C_Container = _G.C_Container or {}
    local flag = true
    local get, set = C_Container.GetSortBagsRightToLeft, C_Container.SetSortBagsRightToLeft
    C_Container.GetSortBagsRightToLeft = function() return flag end
    C_Container.SetSortBagsRightToLeft = function(v) flag = v end
    T.falsy(row.get(), "the game's default (right to left) is the normal fill, so the switch is off")
    row.set(true)
    T.eq(flag, false, "on turns the game's flag off")
    T.truthy(row.get())
    row.set(false)
    T.eq(flag, true, "off puts the game's normal fill back")
    C_Container.GetSortBagsRightToLeft, C_Container.SetSortBagsRightToLeft = get, set
end)
