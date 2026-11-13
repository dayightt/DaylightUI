-- Opening the bag tops up partial stacks of the same item so slots aren't wasted
-- on two half stacks (combined stacks hide this: 15 and 5 Linen Cloth show as 20
-- but take two slots). One move at a time, a short beat apart, until nothing is
-- left to merge. Never in combat, with something on the cursor, or while trade,
-- mail or the auction house is open (a stack split to hand over has to stay
-- split). Bags only, not the keyring or the bank.

local _, ns = ...

local Stack = {}
ns.Stack = Stack

Stack.DELAY = 0.15      -- seconds between moves (the game locks both slots while one lands)
Stack.MAX_MOVES = 100   -- cap per opening

local running = false

local function maxStack(link)
    local ok, _, _, _, _, _, _, _, size = pcall(C_Item.GetItemInfo, link)
    return ok and type(size) == "number" and size or nil
end

local function infoAt(at) return ns.Items.InfoAt(at.bag, at.slot) end
local cursorBusy = ns.Items.CursorBusy

-- Blocked during combat, with the cursor busy, a trade window open, or the
-- setting off (force = Clean Up asked, ignores the setting).
local function blocked(force)
    if not force and ns.Setting("autoStack") == false then return true end
    if ns.Items.InCombat() then return true end
    if cursorBusy() then return true end
    return next(ns.Layout.apart) ~= nil
end

-- Next merge: { from = slot, to = slot }, the later partial stack onto the first
-- one of that item, or nil when every item is in full stacks. Slots are
-- { bag, slot }. Locked slots wait for the next beat, items in skip (link -> true)
-- are left alone. A slot Clean Up keeps (Keep.lua) only receives, it never
-- gives its item away.
function Stack.Next(window, skip)
    window = window or ns.window
    if not window then return nil end
    local first = {}
    for _, s in ipairs(window.set.Slots()) do
        if s.section ~= "keyring" then
            local here = { bag = s.bag, slot = s.button:GetID() }
            local info = infoAt(here)
            local link = info and info.hyperlink
            local size = link and not (skip and skip[link]) and maxStack(link)
            if size and size > 1 and not info.isLocked and (info.stackCount or 0) < size then
                local at = first[link]
                local keptHere = ns.Keep.At(here.bag, here.slot) ~= nil
                if not at then first[link] = here
                elseif not keptHere then return { from = here, to = at }
                elseif ns.Keep.At(at.bag, at.slot) == nil then return { from = at, to = here } end
            end
        end
    end
end

local after, forced     -- callbacks waiting for the run to end; whether it's Clean Up's run

local function finish()
    running, forced = false, false
    local fn = after
    after = nil
    if fn then fn() end
end

-- skip collects items the game wouldn't merge (nothing moved), left alone after.
local function step(moves, skip)
    if blocked(forced) or moves >= Stack.MAX_MOVES then return finish() end
    local m = Stack.Next(nil, skip)
    if not m then return finish() end
    local info = infoAt(m.from)
    local link, before = info.hyperlink, info.stackCount
    C_Container.PickupContainerItem(m.from.bag, m.from.slot)
    C_Container.PickupContainerItem(m.to.bag, m.to.slot)
    -- Whatever didn't fit goes back where it came from.
    if cursorBusy() and type(ClearCursor) == "function" then ClearCursor() end
    C_Timer.After(Stack.DELAY, function()
        local now = infoAt(m.from)
        if now and now.hyperlink == link and now.stackCount == before then skip[link] = true end
        step(moves + 1, skip)
    end)
end

-- Starts tidying (a run already going just continues). done is called when it
-- finishes, right away if there's nothing to do. force = Clean Up's run.
function Stack.Run(done, force)
    if running then
        if done then
            local before = after
            after = function()
                if before then before() end
                done()
            end
        end
        return
    end
    if blocked(force) or type(C_Container.PickupContainerItem) ~= "function" then
        if done then done() end
        return
    end
    running, forced, after = true, force == true, done
    step(0, {})
end

-- Splitting to hand over
--
-- A split on the cursor isn't a stack yet: trade, mail and the auction house
-- take from its source slot, so they'd take the whole stack. While one of them
-- is open, the split is put down in a free bag slot and picked up again, so the
-- cursor holds a real stack of just that many.

Stack.LAND_WAIT = 2     -- seconds to wait for the split to land before giving up
Stack.POLL = 0.05

-- First free slot in the regular bags (not the profession bag, which only takes
-- its own item type).
function Stack.FreeSlot(window)
    window = window or ns.window
    if not window then return nil end
    for _, s in ipairs(window.set.Slots()) do
        if s.section == "bags" then
            local at = { bag = s.bag, slot = s.button:GetID() }
            if not infoAt(at) then return at end
        end
    end
end

function Stack.AfterSplit()
    if next(ns.Layout.apart) == nil or not cursorBusy() then return end
    local at = Stack.FreeSlot()
    if not at then return end
    C_Container.PickupContainerItem(at.bag, at.slot)
    local waited = 0
    local function pickUp()
        if cursorBusy() then return end                 -- the player picked up something else
        local info = infoAt(at)
        if info and not info.isLocked then
            C_Container.PickupContainerItem(at.bag, at.slot)
            return
        end
        waited = waited + Stack.POLL
        if waited < Stack.LAND_WAIT then C_Timer.After(Stack.POLL, pickUp) end
    end
    C_Timer.After(Stack.POLL, pickUp)
end

-- The game's split box calls its owner's SplitStack on OK, and the game resets
-- that on every shift-click (ContainerFrame.lua OnModifiedClick), so wrapping it
-- on the button never sticks. Follow the OK instead, for these buttons only.
local mine = setmetatable({}, { __mode = "k" })
local hooked = false

function Stack.Hook(btn)
    mine[btn] = true
    if hooked or type(StackSplitOkayButton_OnClick) ~= "function" then return end
    hooked = true
    hooksecurefunc("StackSplitOkayButton_OnClick", function()
        local owner = StackSplitFrame and StackSplitFrame.owner
        if owner and mine[owner] then Stack.AfterSplit() end
    end)
end
