-- Dropping a bag on a slot whose bag still has items in it. The game only swaps
-- empty bags, so the items are moved out first (rounds of moves a short beat
-- apart), then the new bag goes in and the old one lands where the new one was.
-- If the bags are full, half stacks get merged first (Stack.Run), a profession
-- bag or quiver takes what it can, and at a banker the bank takes the rest (a
-- chat line says how many). A chat line also says when there still isn't room.
-- Never in combat. The new bag must come from the bags themselves (not the bank
-- or another bag slot); anything else is left to the game.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Swap = {}
ns.Swap = Swap

Swap.DELAY = 0.2        -- seconds between rounds (moved items stay locked briefly)
Swap.TRIES = 15         -- max rounds before giving up
Swap.BAG_CLASSES = { [1] = true, [11] = true }   -- container, quiver

local running = false

local infoAt, cursorBusy, inCombat = ns.Items.InfoAt, ns.Items.CursorBusy, ns.Items.InCombat

-- The item on the cursor, if it's a bag.
local function heldBag()
    if type(GetCursorInfo) ~= "function" then return nil end
    local kind, id = GetCursorInfo()
    if kind ~= "item" or type(id) ~= "number" then return nil end
    local get = C_Item and C_Item.GetItemInfoInstant
    if type(get) ~= "function" then return nil end
    local ok, _, _, _, _, _, classID = pcall(get, id)
    return ok and Swap.BAG_CLASSES[classID] and id or nil
end

-- Where the held bag came from. Its slot stays locked while it's held.
local function heldFrom(itemID)
    for bag = 0, ns.Bags.NumBags() + ns.Bags.NumProfession() do
        for slot = 1, ns.Bags.Size(bag) do
            local info = infoAt(bag, slot)
            if info and info.isLocked and info.itemID == itemID then return { bag = bag, slot = slot } end
        end
    end
end

local function contents(bag)
    local out = {}
    for slot = 1, ns.Bags.Size(bag) do
        if infoAt(bag, slot) then out[#out + 1] = slot end
    end
    return out
end

-- An item's family bits (what a special bag must share to take it). 0 when
-- unknown, then only a plain bag takes it.
local function itemFamily(itemID)
    local get = C_Item and C_Item.GetItemFamily
    if type(get) ~= "function" or type(itemID) ~= "number" then return 0 end
    local ok, fam = pcall(get, itemID)
    return ok and type(fam) == "number" and fam or 0
end

local function fits(spot, fam)
    return spot.family == 0 or bit.band(spot.family, fam) ~= 0
end

-- Containers that can take items: bags other than skip, then the character
-- bank tabs while at a banker. Each is { id, family, bank }.
local function containers(skip)
    local out = {}
    local plainBags = ns.Bags.NumBags()
    local function add(id, bank)
        local ok, _, family = pcall(C_Container.GetContainerNumFreeSlots, id)
        family = ok and family or 0
        -- The profession bag slot only takes its own item type, even when it reports
        -- no family. Never treat it as a plain bag.
        local special = not bank and id > plainBags
        if id ~= skip and ok and not (special and family == 0) then
            out[#out + 1] = { id = id, family = family, bank = bank }
        end
    end
    for bag = 0, plainBags + ns.Bags.NumProfession() do add(bag) end
    local Bank = ns.Bank
    local character = Enum and Enum.BankType and Enum.BankType.Character
    if Bank and Bank.open and character and Bank.bankType == character then
        for _, c in ipairs(Bank.List()) do add(c.id, true) end
    end
    return out
end

-- Empty slots in those containers, minus ones in used ("bag:slot" -> true,
-- moves still landing). Special bags first since they only take their own
-- item type, then plain bags, then the bank.
local function freeSlots(skip, used)
    local special, plain, bank = {}, {}, {}
    for _, c in ipairs(containers(skip)) do
        local into = c.bank and bank or (c.family ~= 0 and special or plain)
        for slot = 1, ns.Bags.Size(c.id) do
            if not infoAt(c.id, slot) and not (used and used[c.id .. ":" .. slot]) then
                into[#into + 1] = { bag = c.id, slot = slot, family = c.family, bank = c.bank }
            end
        end
    end
    for _, s in ipairs(plain) do special[#special + 1] = s end
    for _, s in ipairs(bank) do special[#special + 1] = s end
    return special
end

-- Where each item in bag goes: { [slot] = spot }, plus how many have nowhere to
-- go. The new bag (newID) only goes into a plain bag.
local function plan(bag, used, newID)
    local free, taken, out, short = freeSlots(bag, used), {}, {}, 0
    for _, slot in ipairs(contents(bag)) do
        local info = infoAt(bag, slot)
        local fam = info and info.itemID ~= newID and itemFamily(info.itemID) or 0
        local to
        for i, spot in ipairs(free) do
            if not taken[i] and fits(spot, fam) then taken[i], to = true, spot; break end
        end
        if to then out[slot] = to else short = short + 1 end
    end
    return out, short
end

local function finish(msg)
    running = false
    if msg then DUI.Print(msg) end
end

local function sayShort(short)
    finish(short == 1 and L["Not enough room to empty that bag: free 1 more slot first."]
        or string.format(L["Not enough room to empty that bag: free %d more slots first."], short))
end

local function step(t)
    if inCombat() then return finish(L["Bag swap stopped: you're in combat."]) end
    if cursorBusy() then return finish(L["Bag swap stopped: something is on the cursor."]) end
    local left = contents(t.bag)
    if #left == 0 then
        local info = infoAt(t.new.bag, t.new.slot)
        if not (info and info.itemID == t.id) then return finish(L["Bag swap stopped: the new bag moved."]) end
        if not info.isLocked then
            C_Container.PickupContainerItem(t.new.bag, t.new.slot)
            PutItemInBag(t.inv)
            if t.banked == 1 then return finish(L["Bag swapped: 1 item went to your bank."]) end
            if t.banked > 1 then return finish(string.format(L["Bag swapped: %d items went to your bank."], t.banked)) end
            return finish()
        end
    else
        local spots = plan(t.bag, t.used, t.id)
        for _, slot in ipairs(left) do
            local info = infoAt(t.bag, slot)
            local to = spots[slot]
            if info and not info.isLocked and to then
                t.used[to.bag .. ":" .. to.slot] = true
                C_Container.PickupContainerItem(t.bag, slot)
                C_Container.PickupContainerItem(to.bag, to.slot)
                if cursorBusy() and type(ClearCursor) == "function" then ClearCursor() end
                if to.bank then t.banked = t.banked + 1 end
                -- The new bag was inside the one being emptied: follow it.
                if t.new.bag == t.bag and t.new.slot == slot then t.new = to end
            end
        end
    end
    t.tries = t.tries + 1
    if t.tries > Swap.TRIES then return finish(L["Bag swap gave up: the items wouldn't move."]) end
    C_Timer.After(Swap.DELAY, function() step(t) end)
end

-- A bag on the cursor was dropped on bag `bag` (inventory slot inv). Returns
-- true if handled here (swapping, or reporting no room); false leaves the drop
-- to the game.
function Swap.Try(bag, inv)
    if running or inCombat() or not inv then return false end
    if type(C_Container.PickupContainerItem) ~= "function" or type(PutItemInBag) ~= "function" then return false end
    local id = heldBag()
    if not id then return false end
    if #contents(bag) == 0 then return false end      -- empty, the game swaps it itself
    local from = heldFrom(id)
    if not from then return false end
    local t = { bag = bag, inv = inv, id = id, new = from, tries = 0, used = {}, banked = 0 }
    local _, short = plan(bag, nil, id)
    if short > 0 and not ns.Stack.Next() then
        sayShort(short)
        return true
    end
    if type(ClearCursor) == "function" then ClearCursor() end
    running = true
    if short == 0 then
        step(t)
        return true
    end
    -- Not enough room yet. Merging half stacks may free some (the new bag goes back
    -- to its slot meanwhile; bags never stack, so it stays put).
    ns.Stack.Run(function()
        local info = infoAt(from.bag, from.slot)
        if not (info and info.itemID == id) then return finish(L["Bag swap stopped: the new bag moved."]) end
        local _, still = plan(bag, nil, id)
        if still > 0 then return sayShort(still) end
        step(t)
    end, true)
    return true
end
