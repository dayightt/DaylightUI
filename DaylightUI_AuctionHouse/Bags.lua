-- Bags: what the character carries, per price key (the Groups page's "20 in
-- your bags", the post preview's counts, adding items from your bags).
--
--   ns.Bags.Counts() -> { [key] = count }   read again only after the bags changed
--   ns.Bags.Count(key) -> count (0 when none)
--   ns.Bags.Keys() -> { key... }            the keys carried, in bag order, once each
--   ns.Bags.Link(key) -> the link of one carried
--   ns.Bags.Slot(key) -> bag, slot   where one stack of it sits that can be sold (not bound),
--                                   the biggest; nil when none
--   ns.Bags.Free(key) -> count       how many of it can be sold (bound stacks left out)
--   ns.Bags.KeyAt(bag, slot) -> the price key of what sits there now, read live (nil: nothing)
--   ns.Bags.Stacks(key) -> { { bag, slot, n } }   its stacks that can be traded (not bound),
--                                   biggest first (Mail/Plan.lua mails whole stacks)
--   ns.Bags.CountIn(ids) -> counts, n   { [key] = count } in those containers (a bank's
--                                   tabs: Game/Bank.lua), n = how many of them have slots
--   ns.Bags.Last() -> bag              the last bag read (0 .. Last(): Game/Move.lua reads the same)
--
-- The backpack, the equipped bags (0 .. NUM_BAG_SLOTS) and the reagent bag
-- where the game names one (Enum.BagIndex.ReagentBag: 5 on Forever). The bags are read
-- on the first ask after BAG_UPDATE_DELAYED (the game's "the bags settled"),
-- never on the event itself: nothing runs while nobody is looking.

local _, ns = ...

local Bags = {}
ns.Bags = Bags

local dirty = true
local counts, keys, links, slots = {}, {}, {}, {}

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The last bag to read: the reagent bag comes right after the equipped ones.
local function lastBag()
    local last = NUM_BAG_SLOTS or 4
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if type(reagent) == "number" and reagent > last then last = reagent end
    return last
end
Bags.Last = lastBag

-- One container's stacks, each as each(key, qty, link, slot, row). Returns
-- false when it has no slots (not there, or not sent yet).
local function eachIn(bag, each)
    local n = plain(C_Container.GetContainerNumSlots(bag))
    if type(n) ~= "number" or n <= 0 then return false end
    for slot = 1, n do
        local row = C_Container.GetContainerItemInfo(bag, slot)
        if type(row) == "table" then
            local link, id = plain(row.hyperlink), plain(row.itemID)
            local key = ns.Items.BagKey(bag, slot, link, id)
            local qty = plain(row.stackCount)
            if key and type(qty) == "number" then each(key, qty, link, slot, row) end
        end
    end
    return true
end

local function read()
    dirty = false
    counts, keys, links, slots = {}, {}, {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    for bag = 0, lastBag() do
        eachIn(bag, function(key, qty, link, slot, row)
            if not counts[key] then keys[#keys + 1] = key end
            counts[key] = (counts[key] or 0) + qty
            links[key] = links[key] or link
            local list = slots[key] or {}
            slots[key] = list
            list[#list + 1] = { bag = bag, slot = slot, n = qty, bound = plain(row.isBound) == true }
        end)
    end
end

function Bags.CountIn(ids)
    local out, n = {}, 0
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return out, 0 end
    for _, bag in ipairs(ids) do
        if eachIn(bag, function(key, qty) out[key] = (out[key] or 0) + qty end) then n = n + 1 end
    end
    return out, n
end

function Bags.Counts()
    if dirty then read() end
    return counts
end

function Bags.Count(key)
    return Bags.Counts()[key] or 0
end

function Bags.Keys()
    Bags.Counts()
    return keys
end

function Bags.Link(key)
    Bags.Counts()
    return links[key]
end

function Bags.Slot(key)
    Bags.Counts()
    local best
    for _, s in ipairs(slots[key] or {}) do
        if not s.bound and (not best or s.n > best.n) then best = s end
    end
    if best then return best.bag, best.slot end
end

function Bags.KeyAt(bag, slot)
    local row = C_Container.GetContainerItemInfo(bag, slot)
    if type(row) ~= "table" then return nil end
    local link, id = plain(row.hyperlink), plain(row.itemID)
    return ns.Items.BagKey(bag, slot, link, id)
end

function Bags.Stacks(key)
    Bags.Counts()
    local out = {}
    for _, s in ipairs(slots[key] or {}) do
        if not s.bound then out[#out + 1] = { bag = s.bag, slot = s.slot, n = s.n } end
    end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return out
end

function Bags.Free(key)
    Bags.Counts()
    local n = 0
    for _, s in ipairs(slots[key] or {}) do if not s.bound then n = n + s.n end end
    return n
end

ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
    dirty = true
    ns.Fire("BagsChanged")
end)

-- A suffix just learned can change the key of what's carried.
ns.On("SuffixLearned", function()
    dirty = true
    ns.Fire("BagsChanged")
end)
