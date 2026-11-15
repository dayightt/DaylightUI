-- Keep in this slot (bag-by-bag view, Alt-right-click an item): Clean Up leaves
-- that slot alone. The game's sort can only skip whole bags, so when any slot is
-- kept, Clean Up runs this sort instead. It reads the bags, works out where
-- everything belongs and swaps items into place in rounds a short beat apart.
-- A kept item that wandered off goes back to its slot, and a kept slot whose
-- item is gone stays free for it. With no kept slots, Clean Up is the game's.
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

-- The player's own "ignore this bag" from the game's bag menu.
local function skipped(bag)
    local C = C_Container
    if bag == 0 then
        return type(C.GetBackpackAutosortDisabled) == "function" and C.GetBackpackAutosortDisabled() == true
    end
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.DisableAutoSort
    return flag ~= nil and type(C.GetBagSlotFlag) == "function" and C.GetBagSlotFlag(bag, flag) == true
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
    return { mark = mark(info), class = class or 99, sub = sub or 0, quality = info.quality or 0,
             name = info.itemName or info.hyperlink or "", count = info.stackCount or 1 }
end

-- Same item types together, best quality first, then by name; bigger stacks first.
local function before(a, b)
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
