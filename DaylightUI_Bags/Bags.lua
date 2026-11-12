-- Which bags exist, and per bag a holder frame (its ID is the bag ID, which is
-- how the game's item buttons know their bag) with a pool of buttons, as many
-- shown as the bag has slots. Bags.NewSet does the same for another window's
-- containers (the bank).
--
-- Buttons are only created out of combat and never thrown away. A bag that
-- shrinks hides its extras, one that grows gets more (after combat if needed).

local _, ns = ...
local DUI = DaylightUI

local Bags = {}
ns.Bags = Bags

local function inv()
    return Constants and Constants.InventoryConstants or {}
end

function Bags.NumBags() return inv().NumBagSlots or NUM_BAG_SLOTS or 4 end
function Bags.NumProfession() return inv().NumReagentBagSlots or 0 end

-- Keyring shown in the bag: the game has one and showKeyring is on (the strip's
-- key button in Slots.lua, or the Bags page).
function Bags.HasKeyring()
    if ns.Setting and ns.Setting("showKeyring") ~= true then return false end
    return Bags.GameKeyring()
end

-- The game has a keyring for this character (its own keyring button shows).
function Bags.GameKeyring()
    if KEYRING_CONTAINER == nil then return false end
    local fn = C_ActionBar and C_ActionBar.ShouldShowKeyring
    if type(fn) ~= "function" then return false end
    local ok, show = pcall(fn)
    if not (ok and show) then return false end
    local cok, cvar = pcall(GetCVarBool, "showKeyring")
    return not cok or cvar ~= false
end

-- Bags in order, each with its section: "bags" (backpack and bags 1-4),
-- "profession" or "keyring".
function Bags.List()
    local out = {}
    for id = 0, Bags.NumBags() do out[#out + 1] = { id = id, section = "bags" } end
    local n = Bags.NumBags()
    for id = n + 1, n + Bags.NumProfession() do out[#out + 1] = { id = id, section = "profession" } end
    if Bags.HasKeyring() then out[#out + 1] = { id = KEYRING_CONTAINER, section = "keyring" } end
    return out
end

-- Usable slot count for a container. The keyring holds more slots than a
-- character has unlocked; the game shows only GetKeyRingSize() of them
-- (ContainerFrame_GetContainerNumSlots) and puts a padlock on any slot past
-- that (UpdateExtended).
function Bags.NumSlots(id)
    if id == KEYRING_CONTAINER and type(GetKeyRingSize) == "function" then
        local ok, n = pcall(GetKeyRingSize)
        if ok and type(n) == "number" then return n end
    end
    local ok, n = pcall(C_Container.GetContainerNumSlots, id)
    if ok and type(n) == "number" then return n end
    return 0
end

function Bags.Size(id)
    if ns.Saved.Is(id) then return ns.Saved.Size(id) end
    local n = Bags.NumSlots(id)
    if n > 0 then return n end
    return 0
end

-- A slot set: one window's containers (list() returns them in order, each
-- { id, section }), a holder frame per container (ID = container, which is how
-- the game's buttons know their bag) and a pool of buttons. The bag is one set
-- (Bags itself), the bank another (Bank.lua).
-- make(holder, slot) supplies a custom button instead of the game's bag button
-- (the viewer's display-only slots, Viewer.lua). Those aren't protected, so
-- that set can sync in combat too.
function Bags.NewSet(list, make)
    local set = { holders = {}, buttons = {}, sizes = {}, List = list }
    -- Cached Slots() list, only rebuilt in Sync (cooldown bursts asked for it
    -- over and over).
    local slots

    local function holderFor(id, parent)
        local h = set.holders[id]
        if not h then
            h = CreateFrame("Frame", nil, parent)
            h:SetID(id)
            h:SetAllPoints(parent)
            h.dluiWindow = parent.dluiWindow
            set.holders[id] = h
            set.buttons[id] = {}
        end
        return h
    end

    -- Makes sure every container has its holder and enough buttons, shows each
    -- one's real slots and hides the rest (and containers no longer listed).
    -- Out of combat only. Returns true if the slots changed.
    function set.Sync(parent)
        if not make and InCombatLockdown and InCombatLockdown() then return false end
        slots = nil
        local changed, listed = false, {}
        for _, b in ipairs(set.List()) do
            local id = b.id
            listed[id] = true
            local h = holderFor(id, parent)
            local size = Bags.Size(id)
            if set.sizes[id] ~= size then
                set.sizes[id] = size
                changed = true
            end
            local list = set.buttons[id]
            for slot = #list + 1, size do
                local btn = make and make(h, slot) or CreateFrame("ItemButton", nil, h, ns.Items.TEMPLATE)
                btn:SetID(slot)
                ns.Items.Dress(btn)
                list[slot] = btn
            end
            -- Only hide here. The layout shows what it places (a stack merged into
            -- another stays hidden while the window holds still).
            for slot, btn in ipairs(list) do if slot > size then btn:Hide() end end
        end
        for id, list in pairs(set.buttons) do
            -- No longer listed: hide once (otherwise the closed bank would do this on
            -- every bag update).
            if not listed[id] and (set.sizes[id] or 0) > 0 then
                changed = true
                set.sizes[id] = 0
                for _, btn in ipairs(list) do btn:Hide() end
            end
        end
        return changed
    end

    -- Every shown button in order, each { button, bag, section }. Same table until
    -- the next Sync, so read it but never modify it.
    function set.Slots()
        if slots then return slots end
        local out = {}
        for _, b in ipairs(set.List()) do
            local list = set.buttons[b.id]
            if list then
                for slot = 1, set.sizes[b.id] or 0 do
                    if list[slot] then out[#out + 1] = { button = list[slot], bag = b.id, section = b.section } end
                end
            end
        end
        slots = out
        return out
    end

    -- A container's button for a slot, if shown.
    function set.Button(bag, slot)
        local list = set.buttons[bag]
        if not list or slot > (set.sizes[bag] or 0) then return nil end
        return list[slot]
    end

    -- Free and total slots (the keyring doesn't count). plain = only ordinary bags
    -- in the "bags" section (no profession bag, no herb or soul bag in a bag slot).
    -- That's what the InfoPanel data text counts (DT.ReadBags), so the footer
    -- matches it.
    function set.Free(plain)
        local free, total = 0, 0
        for _, b in ipairs(set.List()) do
            if b.section ~= "keyring" and (not plain or b.section == "bags") then
                local n, family = ns.Items.FreeAt(b.id)
                if not plain or not (type(family) == "number" and family ~= 0) then
                    total = total + (set.sizes[b.id] or Bags.Size(b.id))
                    if type(n) == "number" then free = free + n end
                end
            end
        end
        return free, total
    end

    -- Free slots in bags that only hold their own item type (profession bag, herb
    -- bag, quiver...): { { kind, free } } per kind (Items.BagKind), in bag order.
    -- The footer shows each one after the plain bags' count.
    function set.FreeSpecial()
        local out, at = {}, {}
        for _, b in ipairs(set.List()) do
            if b.section ~= "keyring" then
                local n, family = ns.Items.FreeAt(b.id)
                local special = b.section == "profession" or (type(family) == "number" and family ~= 0)
                if special and (b.section == "bags" or b.section == "profession") then
                    local kind = ns.Items.BagKind(b.id)
                    local e = at[kind]
                    if not e then e = { kind = kind, free = 0 }; at[kind] = e; out[#out + 1] = e end
                    if type(n) == "number" then e.free = e.free + n end
                end
            end
        end
        return out
    end

    return set
end

-- The bag's own set lives directly on Bags (Bags.holders, Bags.Slots(), ...).
for k, v in pairs(Bags.NewSet(Bags.List)) do Bags[k] = v end
