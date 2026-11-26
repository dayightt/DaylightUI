-- Keep in this slot (bag-by-bag view, Alt-right-click an item): Clean Up leaves
-- that slot alone. The game's sort can only skip whole bags, so when any slot is
-- kept, Clean Up runs this sort instead. It reads the bags, works out where
-- everything belongs and swaps items into place in rounds a short beat apart.
-- A kept item that wandered off goes back to its slot, and a kept slot whose
-- item is gone stays free for it. Items marked as junk by hand need it too: the
-- game's sort only knows gray junk, and this one puts both at the end. So does
-- Clean up toward the end (Keep.ToEnd). Otherwise Clean Up is the game's.
-- Saved per character since bags differ. Moves stay inside the plain bags or
-- inside one special bag (only its own item type fits), and bags the player
-- told the game to skip during cleanup are skipped here too.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Keep = {}
ns.Keep = Keep

Keep.DELAY = 0.2        -- seconds between rounds (moved items stay locked briefly)
Keep.TRIES = 80         -- max rounds before giving up

local running = false
local whenDone          -- called once the cleanup ends, however it ends

local function kept()
    local c = DUI.DB.Character()
    if type(c.keepSlots) ~= "table" then c.keepSlots = {} end
    return c.keepSlots
end

local function key(bag, slot) return bag .. ":" .. slot end

function Keep.At(bag, slot) return kept()[key(bag, slot)] end

function Keep.Any() return next(kept()) ~= nil end

-- Whether any bag item is marked as junk by hand (Clean Up then runs this sort).
function Keep.AnyMarkedJunk(window)
    if not window then return false end
    for _, s in ipairs(window.set.Slots()) do
        if s.section ~= "keyring" then
            local info = ns.Items.InfoAt(s.bag, s.button:GetID())
            if info and ns.Categories.IsMarkedJunk(info.itemID) then return true end
        end
    end
    return false
end

-- Only offered on the bag window's own slots in the bag-by-bag view. A slot
-- means nothing in the categories view (kept slots still hold there).
function Keep.Offered(btn, bag, slot)
    local f = ns.window
    return f ~= nil and f.Setting("view") == "grid" and f.set.Button(bag, slot) == btn
end

function Keep.Toggle(bag, slot, itemID)
    local k = key(bag, slot)
    local list = kept()
    if list[k] then list[k] = nil else list[k] = itemID end
    if ns.FillAll then ns.FillAll() end
end

-- The player's own "ignore this bag" for clean up, the same flag the game's bag
-- menu sets (saved by the game). The game's sort skips such a bag whole, so its
-- items stay where they are, gaps and all.
function Keep.Skipped(bag)
    local C = C_Container
    if bag == 0 then
        return type(C.GetBackpackAutosortDisabled) == "function" and C.GetBackpackAutosortDisabled() == true
    end
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.DisableAutoSort
    return flag ~= nil and type(C.GetBagSlotFlag) == "function" and C.GetBagSlotFlag(bag, flag) == true
end
local skipped = Keep.Skipped

function Keep.SetSkipped(bag, on)
    local C = C_Container
    on = on == true
    if bag == 0 then
        if type(C.SetBackpackAutosortDisabled) == "function" then DUI.SafeCall(C.SetBackpackAutosortDisabled, on) end
        return
    end
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.DisableAutoSort
    if flag ~= nil and type(C.SetBagSlotFlag) == "function" then DUI.SafeCall(C.SetBagSlotFlag, bag, flag, on) end
end

-- Clean up toward the end (Bags > Layout). Daylight UI keeps it as its own
-- setting: the game's direction flag (C_Container.GetSortBagsRightToLeft) didn't
-- hold what was written to it in game, so reading it back flipped the switch
-- off again. With it on, the bags' Clean Up is this file's sort, which packs
-- toward the end itself.
function Keep.ToEnd() return ns.Setting("sortToEnd") == true end

-- The game's own sorts (SortBags, SortBank) read that flag, so it's written
-- right before each one. The game names it the other way round: right to left
-- is its normal fill from the first slot, so toward the end is the flag off.
function Keep.TellGame()
    local C = C_Container
    if not C or type(C.SetSortBagsRightToLeft) ~= "function" then return end
    local want = not Keep.ToEnd()
    local get = C.GetSortBagsRightToLeft
    if type(get) == "function" and get() == want then return end
    DUI.SafeCall(C.SetSortBagsRightToLeft, want)
end

-- The bags a clean up can skip, in order: the backpack, then each equipped bag.
function Keep.CleanupBags()
    local out = { 0 }
    local Bags = ns.Bags
    for bag = 1, Bags.NumBags() + Bags.NumProfession() do
        if Bags.NumSlots(bag) > 0 then out[#out + 1] = bag end
    end
    return out
end

function Keep.BagName(bag)
    if bag == 0 then return BAG_NAME_BACKPACK or L["Backpack"] end
    local get = C_Container and C_Container.GetBagName
    local name = type(get) == "function" and get(bag)
    if type(name) == "string" and name ~= "" then return name end
    return string.format(L["Bag %d"], bag)
end

-- "Skips Backpack, Large Knapsack.", or nil when every bag is sorted. Said
-- under the Clean Up button, since a skipped bag keeps its gaps.
function Keep.SkippedText()
    local names = {}
    for _, bag in ipairs(Keep.CleanupBags()) do
        if skipped(bag) then names[#names + 1] = Keep.BagName(bag) end
    end
    if #names == 0 then return nil end
    return string.format(L["Skips %s."], table.concat(names, ", "))
end

-- Sell Junk leaving a bag alone, the same flag the game's bag menu sets (read
-- by Junk.BagSkipped).
function Keep.SetSellSkipped(bag, on)
    local C = C_Container
    on = on == true
    if bag == 0 then
        if type(C.SetBackpackSellJunkDisabled) == "function" then DUI.SafeCall(C.SetBackpackSellJunkDisabled, on) end
        return
    end
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.ExcludeJunkSell
    if flag ~= nil and type(C.SetBagSlotFlag) == "function" then DUI.SafeCall(C.SetBagSlotFlag, bag, flag, on) end
end

-- What a bag holds: the game's sort puts these kinds in it first. The game's own
-- list and order (ContainerFrameUtil_EnumerateBagGearFilters), each with its word.
Keep.HOLDS = { "ClassEquipment", "ClassConsumables", "ClassProfessionGoods", "ClassJunk", "ClassQuestItems", "ClassReagents" }
Keep.HOLDS_WORD = { ClassEquipment = "BAG_FILTER_EQUIPMENT", ClassConsumables = "BAG_FILTER_CONSUMABLES",
    ClassProfessionGoods = "BAG_FILTER_PROFESSION_GOODS", ClassJunk = "BAG_FILTER_JUNK",
    ClassQuestItems = "BAG_FILTER_QUEST_ITEMS", ClassReagents = "BAG_FILTER_REAGENTS" }
Keep.HOLDS_FALLBACK = { ClassEquipment = L["Equipment"], ClassConsumables = L["Consumables"],
    ClassProfessionGoods = L["Trade Goods"], ClassJunk = L["Junk"], ClassQuestItems = L["Quest Items"],
    ClassReagents = L["Reagents"] }

function Keep.HoldsWord(name) return _G[Keep.HOLDS_WORD[name]] or Keep.HOLDS_FALLBACK[name] end

-- Only an equipped plain bag holds what the player picks: not the backpack, nor
-- a profession bag (the game's ContainerFrame_CanContainerUseFilterMenu).
function Keep.CanHold(bag)
    local Bags = ns.Bags
    if type(bag) ~= "number" or bag < 1 or bag > Bags.NumBags() or Bags.NumSlots(bag) <= 0 then return false end
    local inv = C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag)
    if inv and type(IsInventoryItemProfessionBag) == "function" and IsInventoryItemProfessionBag("player", inv) then
        return false
    end
    return true
end

function Keep.Holds(bag, name)
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags[name]
    local get = C_Container.GetBagSlotFlag
    return flag ~= nil and type(get) == "function" and get(bag, flag) == true
end

function Keep.SetHolds(bag, name, on)
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags[name]
    local set = C_Container.SetBagSlotFlag
    if flag ~= nil and type(set) == "function" then DUI.SafeCall(set, bag, flag, on == true) end
end

-- "Equipment, Junk", or nil when the bag holds anything.
function Keep.HoldsText(bag)
    if not Keep.CanHold(bag) then return nil end
    local words = {}
    for _, name in ipairs(Keep.HOLDS) do
        if Keep.Holds(bag, name) then words[#words + 1] = Keep.HoldsWord(name) end
    end
    if #words == 0 then return nil end
    return table.concat(words, LIST_DELIMITER or ", ")
end

-- The game's bag windows hold these switches, and they stay parked, so these
-- menus are the only way to see or change them. The Clean Up button's lists
-- every bag, backpack first: ticked when Clean Up, then Sell junk, leaves it alone.
function Keep.CleanupMenu(owner)
    local keys, values, titles = { "head" }, { head = L["Clean Up skips"] }, { head = true, sellhead = true }
    local bags = Keep.CleanupBags()
    for _, bag in ipairs(bags) do
        keys[#keys + 1] = "bag" .. bag
        values["bag" .. bag] = Keep.BagName(bag)
    end
    keys[#keys + 1] = "sellhead"
    values.sellhead = L["Sell junk skips"]
    for _, bag in ipairs(bags) do
        keys[#keys + 1] = "sell" .. bag
        values["sell" .. bag] = Keep.BagName(bag)
    end
    local function read(k)
        local kind, n = string.match(k, "^(%a+)(%d+)$")
        return kind, tonumber(n)
    end
    DUI.Widgets.OpenMenu(owner, keys, values, nil, function(k)
        local kind, bag = read(k)
        if kind == "bag" then Keep.SetSkipped(bag, not skipped(bag))
        elseif kind == "sell" then Keep.SetSellSkipped(bag, not ns.Junk.BagSkipped(bag)) end
    end, nil, { titles = titles, keepOpen = true, checked = function(k)
        local kind, bag = read(k)
        if kind == "bag" then return skipped(bag) end
        if kind == "sell" then return ns.Junk.BagSkipped(bag) end
        return false
    end })
end

-- One bag's menu (a right-click on it in the strip), as the game's per-bag menu:
-- what it holds (a plain bag only), then whether Clean Up and Sell junk skip it.
function Keep.BagMenu(owner, bag)
    if ns.Bags.NumSlots(bag) <= 0 then return end
    local name = Keep.BagName(bag)
    local keys, values, titles = {}, {}, { holds = true, skips = true }
    if Keep.CanHold(bag) then
        keys[1], values.holds = "holds", string.format(L["%s holds"], name)
        for _, hold in ipairs(Keep.HOLDS) do
            keys[#keys + 1] = hold
            values[hold] = Keep.HoldsWord(hold)
        end
    end
    keys[#keys + 1] = "skips"
    values.skips = string.format(L["%s is skipped by"], name)
    keys[#keys + 1], values.clean = "clean", BAG_FILTER_CLEANUP or L["Clean Up"]
    keys[#keys + 1], values.sell = "sell", L["Sell junk"]
    DUI.Widgets.OpenMenu(owner, keys, values, nil, function(k)
        if k == "clean" then Keep.SetSkipped(bag, not skipped(bag))
        elseif k == "sell" then Keep.SetSellSkipped(bag, not ns.Junk.BagSkipped(bag))
        elseif Keep.HOLDS_WORD[k] then Keep.SetHolds(bag, k, not Keep.Holds(bag, k)) end
    end, nil, { titles = titles, keepOpen = true, checked = function(k)
        if k == "clean" then return skipped(bag) end
        if k == "sell" then return ns.Junk.BagSkipped(bag) end
        if Keep.HOLDS_WORD[k] then return Keep.Holds(bag, k) end
        return false
    end })
end

-- Sort identity for a slot. Same link and count never move.
local function mark(info) return info and (info.hyperlink or tostring(info.itemID)) .. "#" .. (info.stackCount or 1) end

local function facts(info)
    local get = C_Item and C_Item.GetItemInfoInstant
    local class, sub
    if type(get) == "function" then
        local ok, _, _, _, _, _, c, s = pcall(get, info.hyperlink or info.itemID)
        if ok then class, sub = c, s end
    end
    local junk = info.quality == 0 or ns.Categories.IsMarkedJunk(info.itemID)
    return { mark = mark(info), junk = junk, class = class or 99, sub = sub or 0, quality = info.quality or 0,
             name = info.itemName or info.hyperlink or "", count = info.stackCount or 1 }
end

-- Junk last, as the game's sort does. Then same item types together, best
-- quality first, then by name; bigger stacks first.
local function before(a, b)
    if a.junk ~= b.junk then return b.junk end
    if a.class ~= b.class then return a.class < b.class end
    if a.sub ~= b.sub then return a.sub < b.sub end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.name ~= b.name then return a.name < b.name end
    if a.count ~= b.count then return a.count > b.count end
    return a.mark < b.mark
end

-- Slots that sort together: { plain = { slot, ... }, [bag] = { ... } }.
local function groups(window)
    local out, skip = {}, {}
    for _, s in ipairs(window.set.Slots()) do
        if s.section ~= "keyring" then
            if skip[s.bag] == nil then skip[s.bag] = skipped(s.bag) end
            if not skip[s.bag] then
                local _, family = ns.Items.FreeAt(s.bag)
                local g = (s.section == "bags" and (family or 0) == 0) and "plain" or s.bag
                out[g] = out[g] or {}
                table.insert(out[g], { bag = s.bag, slot = s.button:GetID() })
            end
        end
    end
    return out
end

-- Target layout for one group: slot key -> mark (nil = empty).
local function plan(list)
    local goal, loose, targets, spare = {}, {}, {}, {}
    local infos = {}
    for _, at in ipairs(list) do infos[at] = ns.Items.InfoAt(at.bag, at.slot) end
    local want = {}         -- slots waiting for their kept item
    for _, at in ipairs(list) do
        local info, id = infos[at], Keep.At(at.bag, at.slot)
        if id and info and info.itemID == id then
            goal[key(at.bag, at.slot)] = mark(info)
        else
            if info then loose[#loose + 1] = facts(info) end
            if id then want[#want + 1] = { at = at, id = id }; spare[#spare + 1] = at
            else targets[#targets + 1] = at end
        end
    end
    -- A kept item found elsewhere goes back home.
    for i = #want, 1, -1 do
        local w = want[i]
        for _, at in ipairs(list) do
            local info = infos[at]
            if info and info.itemID == w.id and not goal[key(at.bag, at.slot)] then
                local m = mark(info)
                local found
                for n, e in ipairs(loose) do
                    if e.mark == m then found = n; break end
                end
                if found then
                    table.remove(loose, found)
                    goal[key(w.at.bag, w.at.slot)] = m
                    for n, s in ipairs(spare) do
                        if s == w.at then table.remove(spare, n); break end
                    end
                    break
                end
            end
        end
    end
    table.sort(loose, before)
    -- Clean up toward the end: fill from the last open slot back.
    if Keep.ToEnd() then
        for i = 1, math.floor(#targets / 2) do
            targets[i], targets[#targets + 1 - i] = targets[#targets + 1 - i], targets[i]
        end
    end
    -- More items than open slots: the still-empty kept slots take the rest.
    for _, at in ipairs(spare) do
        if #targets < #loose then targets[#targets + 1] = at end
    end
    for i, e in ipairs(loose) do
        local at = targets[i]
        if at then goal[key(at.bag, at.slot)] = e.mark end
    end
    return goal
end

-- This round's moves (no slot touched twice), and whether a still-locked slot
-- means another round is needed.
function Keep.Moves(window)
    local moves, busy = {}, false
    for _, list in pairs(groups(window)) do
        local goal = plan(list)
        local now, locked, used = {}, {}, {}
        for _, at in ipairs(list) do
            local k = key(at.bag, at.slot)
            local info = ns.Items.InfoAt(at.bag, at.slot)
            now[k] = mark(info)
            locked[k] = info ~= nil and info.isLocked == true
        end
        for _, to in ipairs(list) do
            local t = key(to.bag, to.slot)
            local wanted = goal[t]
            if wanted and now[t] ~= wanted and not used[t] then
                if locked[t] then busy = true
                else
                    local from
                    for _, at in ipairs(list) do
                        local k = key(at.bag, at.slot)
                        if k ~= t and now[k] == wanted and goal[k] ~= wanted and not used[k] then
                            if locked[k] then busy = true else from = at; break end
                        end
                    end
                    if from then
                        used[t], used[key(from.bag, from.slot)] = true, true
                        moves[#moves + 1] = { from = from, to = to }
                    end
                end
            end
        end
    end
    return moves, busy
end

local function finish(msg)
    running = false
    if msg then DUI.Print(msg) end
    local fn = whenDone
    whenDone = nil
    if fn then fn() end
end

local function step(tries)
    local window = ns.window
    if not window then return finish() end
    if ns.Items.InCombat() then return finish(L["Clean up stopped: you're in combat."]) end
    if ns.Items.CursorBusy() then return finish(L["Clean up stopped: something is on the cursor."]) end
    local moves, busy = Keep.Moves(window)
    if #moves == 0 and not busy then return finish() end
    if tries >= Keep.TRIES then return finish(L["Clean up gave up: some items wouldn't move."]) end
    for _, m in ipairs(moves) do
        C_Container.PickupContainerItem(m.from.bag, m.from.slot)
        C_Container.PickupContainerItem(m.to.bag, m.to.slot)
        if ns.Items.CursorBusy() and type(ClearCursor) == "function" then ClearCursor() end
    end
    C_Timer.After(Keep.DELAY, function() step(tries + 1) end)
end

-- Clean Up with kept slots: top up stacks first, like the game's sort, then
-- run the rounds of moves. done is called when it ends, or at once when it
-- can't start or one is already going (that run calls its own).
function Keep.Sort(done)
    if running or ns.Items.InCombat() or ns.Items.CursorBusy() or type(C_Container.PickupContainerItem) ~= "function" then
        if done then done() end
        return
    end
    running, whenDone = true, done
    ns.Stack.Run(function() step(0) end, true)
end
