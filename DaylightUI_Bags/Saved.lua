-- Saved inventories: each character's bags at logout, their bank whenever it's
-- seen, and the account bank (shared by all characters). The viewer
-- (Viewer.lua) shows them anywhere: your bank away from a banker, your other
-- characters' bags and banks.
--
-- Per character in DB.Character().inventory = { class, money, time, bags, bank,
-- bankTime }; the account bank once in DB.Root().accountBank = { tabs, money,
-- time }. A container is { section, size, family, items }, an item is
-- { link, count, icon, quality, bound }. Kept short because every character's
-- bank ends up in the saved file.
--
-- Shown through fake container ids starting at Saved.BASE. Items.InfoAt,
-- Items.FreeAt and Bags.Size read those from here, so layout, groups and search
-- work on a saved copy the same as on live bags.

local _, ns = ...
local DUI = DaylightUI

local Saved = {}
ns.Saved = Saved

Saved.BASE = 1000            -- first fake container id (real ones are far below)
Saved.view = {}              -- containers being shown, in order

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function bankType(name) return Enum and Enum.BankType and Enum.BankType[name] end

-- Reading the game's containers

-- One container as it is now (nil if it has no slots).
local function read(id, section)
    local size = ns.Bags.NumSlots(id)
    if type(size) ~= "number" or size <= 0 then return nil end
    local _, family = call(C_Container.GetContainerNumFreeSlots, id)
    local items = {}
    for slot = 1, size do
        local info = ns.Items.InfoAt(id, slot)
        if type(info) == "table" and info.iconFileID then
            items[slot] = { info.hyperlink, info.stackCount or 1, info.iconFileID, info.quality, info.isBound and true or nil }
        end
    end
    return { section = section, size = size, family = type(family) == "number" and family ~= 0 and family or nil, items = items }
end

local function readList(list)
    local out = {}
    for _, b in ipairs(list) do
        local c = read(b.id, b.section)
        if c then out[#out + 1] = c end
    end
    return out
end

-- A bank's tabs. nil if they can't be read now or haven't all arrived yet:
-- right after BANKFRAME_OPENED the tabs and their slots come in one by one
-- (Bank.Reread). saved is the previous copy. Bought tabs never go away, so a
-- read with fewer tabs is still arriving and never replaces it.
local function readBank(kind, saved)
    local t = bankType(kind)
    if t == nil or call(C_Bank and C_Bank.CanViewBank, t) ~= true then return nil end
    local tabs = call(C_Bank.FetchPurchasedBankTabData, t)
    local list = {}
    for _, tab in ipairs(type(tabs) == "table" and tabs or {}) do
        if type(tab.ID) == "number" then list[#list + 1] = { id = tab.ID, section = "bank" } end
    end
    local out = readList(list)
    if #out == 0 or #out < #list then return nil end         -- a tab still reports 0 slots
    if type(saved) == "table" and #out < #saved then return nil end
    return out
end

-- Saving

local function mine()
    local c = DUI.DB.Character()
    if type(c.inventory) ~= "table" then c.inventory = {} end
    local inv = c.inventory
    local _, class = UnitClass("player")
    if type(class) == "string" then inv.class = class end
    return inv
end

-- This character's bank has been seen with slots at some point.
function Saved.HasBank()
    local inv = DUI.DB.CharKey() and DUI.DB.Character().inventory
    return type(inv) == "table" and type(inv.bank) == "table" and #inv.bank > 0
end

-- Bags and gold are saved during play. By PLAYER_LOGOUT the game has already
-- emptied both (every character got saved with no bags and 0 gold), so a read
-- with no bags at all never replaces a saved copy.
function Saved.SaveBags()
    if not DUI.DB.CharKey() then return end
    local bags = readList(ns.Bags.List())
    if #bags == 0 then return end
    local inv = mine()
    inv.bags, inv.time = bags, time()
    inv.money = GetMoney and GetMoney() or inv.money
end

-- Saves a while after the last bag change (loot and vendor sales come in
-- bursts), same as Prep: each change restarts the wait. Waits for combat to
-- end, since reading every slot makes a table per item.
local bagsWait = 0
Saved.BAGS_SETTLE = 2
function Saved.SaveBagsSoon()
    bagsWait = bagsWait + 1
    local mine = bagsWait
    C_Timer.After(Saved.BAGS_SETTLE, function()
        if bagsWait ~= mine then return end
        DUI.AfterCombat(function()
            if ns.Viewer.On() then Saved.SaveBags() end
        end, "bags:save")
    end)
end

-- Saves whichever banks are visible now (only while one is open).
function Saved.SaveBank()
    if not DUI.DB.CharKey() then return end
    local inv = mine()
    local now = time()
    local bank = readBank("Character", inv.bank)
    if bank then inv.bank, inv.bankTime = bank, now end
    local account = readBank("Account", Saved.Account() and Saved.Account().tabs)
    if account then
        DUI.DB.Root().accountBank = { tabs = account, time = now,
            money = call(C_Bank.FetchDepositedMoney, bankType("Account")) }
    end
    if bank or account then DUI.Fire("BagsSaved") end
end

-- Once on the next frame, however many times it's asked (a deposit is a burst).
local armed = false
function Saved.SaveBankSoon()
    if armed then return end
    armed = true
    C_Timer.After(0, function()
        armed = false
        if ns.Bank and ns.Bank.open and ns.Viewer.On() then Saved.SaveBank() end
    end)
end

function Saved.Start()
    -- Nothing new is saved while the viewer is off (Viewer.On).
    DUI.RegisterEvent("PLAYER_LOGOUT", function()
        if not ns.Viewer.On() then return end
        Saved.SaveBags()
        if ns.Bank and ns.Bank.open then Saved.SaveBank() end
    end)
    -- Items moving in or out of the bags, or the bank while it's open.
    DUI.RegisterEvent("BAG_UPDATE_DELAYED", function()
        if not ns.Viewer.On() then return end
        Saved.SaveBagsSoon()
        if ns.Bank and ns.Bank.open then Saved.SaveBankSoon() end
    end)
    DUI.RegisterEvent("PLAYER_MONEY", function()
        if ns.Viewer.On() then Saved.SaveBagsSoon() end
    end)
    -- Once at login or reload, when the bags are available.
    if ns.Viewer.On() then Saved.SaveBagsSoon() end
end

-- Who's saved

-- Every character with something saved: { key, name, realm, class, inv }, this
-- realm first, then by name. Includes the current character.
function Saved.Characters()
    local own = DUI.DB.CharKey()
    local realm = own and own:match("%-(.*)$")
    local out = {}
    local chars = DUI.DB.Root().characters
    local function add(key, inv, class)
        local name, r = key:match("^(.-)%-(.*)$")
        out[#out + 1] = { key = key, name = name or key, realm = r or "", class = class, inv = inv, own = key == own }
    end
    for key, c in pairs(type(chars) == "table" and chars or {}) do
        local inv = type(c) == "table" and c.inventory
        if key ~= own and type(inv) == "table" and (inv.bags or inv.bank) then add(key, inv, inv.class) end
    end
    -- Always include the current character (to switch back to), saved or not.
    -- On a first session nothing is saved until a banker visit or logout.
    if own then
        local _, class = UnitClass("player")
        add(own, Saved.Of(own), type(class) == "string" and class or nil)
    end
    table.sort(out, function(a, b)
        local ah, bh = a.realm == realm, b.realm == realm
        if ah ~= bh then return ah end
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
    return out
end

-- A character's saved inventory, or nil.
function Saved.Of(key)
    local chars = DUI.DB.Root().characters
    local c = type(chars) == "table" and chars[key]
    return type(c) == "table" and type(c.inventory) == "table" and c.inventory or nil
end

function Saved.Account()
    local a = DUI.DB.Root().accountBank
    return type(a) == "table" and type(a.tabs) == "table" and a or nil
end

-- Showing one (fake ids read the same way as the game's containers)

function Saved.Is(id) return type(id) == "number" and id >= Saved.BASE end

-- The containers to show (a saved list, or nil for none).
function Saved.Show(list)
    Saved.view = type(list) == "table" and list or {}
end

-- The shown list in the shape a slot set expects.
function Saved.List()
    local out = {}
    for i, c in ipairs(Saved.view) do out[#out + 1] = { id = Saved.BASE + i, section = c.section or "bags" } end
    return out
end

local function container(id) return Saved.view[id - Saved.BASE] end

function Saved.Size(id)
    local c = container(id)
    return c and type(c.size) == "number" and c.size or 0
end

-- Free slots and bag family, like GetContainerNumFreeSlots.
function Saved.Free(id)
    local c = container(id)
    if not c then return 0, 0 end
    local used = 0
    for _ in pairs(c.items or {}) do used = used + 1 end
    return math.max(0, (c.size or 0) - used), c.family or 0
end

-- A saved item as a ContainerItemInfo table (built once per item).
local infos = setmetatable({}, { __mode = "k" })
function Saved.Info(id, slot)
    local c = container(id)
    local rec = c and c.items and c.items[slot]
    if type(rec) ~= "table" then return nil end
    local info = infos[rec]
    if not info then
        local link = rec[1]
        info = { hyperlink = link, stackCount = rec[2] or 1, iconFileID = rec[3], quality = rec[4], isBound = rec[5] == true,
                 itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil }
        infos[rec] = info
    end
    return info
end
