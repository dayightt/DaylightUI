-- Default settings for the bag.

local _, ns = ...

ns.DEFAULTS = {
    enabled = true,         -- replace the default bags (needs a reload)
    columns = 10,           -- slots per row
    iconSize = 35,          -- px
    spacing = 2,            -- px between slots
    scale = 1,
    windowAlphaOwn = false,   -- off: use the general window opacity
    windowAlpha = 0.85,
    reagentMerged = false,  -- profession bag slots mixed in, instead of their own section
    emptySlots = "all",     -- "all": every empty slot; "grouped": one free tile per section
    greyPoor = true,        -- poor items grayed
    redUnusable = true,     -- tint items you can't use red
    showSlots = false,      -- bag slot strip above the window
    -- Item overlays, each in a fixed corner: bind type top left, equipment set
    -- top right, junk coin in its own spot.
    showBind = true,        -- "BoE" / "BoU" until bound
    showSet = false,        -- mark items that are in an equipment set
    showLevel = false,      -- item level on gear, bottom left
    showJunk = false,       -- the game's gold coin on gray items
    markCheapJunk = true,   -- a dot on the gray stack worth least (Junk.MarkCheapest)
    -- Categories view (Categories.lua)
    sellJunk = true,        -- sell the Junk group when a vendor opens
    autoRepair = true,      -- repair all when a repair vendor opens
    repairGuild = false,    -- use guild funds first when the guild allows it
    view = "categories",    -- "categories", "grid" or "list"
    listSort = "shelf",     -- the list's column to sort by inside each group ("shelf" = the Shelf's order)
    listDesc = false,
    recentMinutes = 15,     -- minutes a new item stays in Recent
    autoStack = true,       -- merge partial stacks when the bag opens (Stack.lua)
    combineStacks = true,   -- show stacks of one item as one (split again while trading, mailing, at the AH)
    stackShards = true,     -- show Soul Shards as one pile with a count (Layout.PILES)
    shardsKeep = 0,         -- warlocks: offer to delete Soul Shards past this many (0 = never)
    shardsKeepRaid = 0,     -- the same while in a raid
    showKeyring = false,    -- keyring slots, if the game has a keyring (Bags.HasKeyring)
    emptyGroups = false,    -- always show empty custom groups (otherwise only while Shift is held with an item on the cursor)
    -- groupOrder, groupNames, customGroups, removedGroups, collapsed, pins and locks are saved as the player sets them
    showCurrency = true,    -- tracked currencies in the footer next to the money
    moneyRoll = true,       -- tween the footer gold to its new amount
    -- Bank (Bank.lua): its own columns and bag slot row. Everything else follows
    -- the bags (ns.BANK_SHARED) unless ownLook gives it its own copy.
    bank = { columns = 14, ownLook = false, iconSize = 35, spacing = 2, scale = 1, view = "categories", emptySlots = "all",
             greyPoor = true, redUnusable = true, showBind = true, showSet = false, showLevel = false, showJunk = false, showSlots = false },
    -- Viewer (Viewer.lua: the bank from anywhere, other characters' bags). When off,
    -- nothing new is saved. Own columns and position; the rest follows the bags
    -- unless ownLook. redUnusable, showSet and showJunk are left out on purpose: with
    -- ownLook they read nil (off), and a saved copy is never judged usable.
    viewer = { enabled = true, columns = 14, ownLook = false, iconSize = 35, spacing = 2, scale = 1, view = "categories",
               emptySlots = "all", greyPoor = true, showBind = true, showLevel = false },
    -- position = { left, top } in UI units; nil means the default spot
}

-- Bank settings that follow the bags unless bank.ownLook is on.
ns.BANK_SHARED = { iconSize = true, spacing = true, scale = true, view = true, emptySlots = true,
                   greyPoor = true, redUnusable = true, showBind = true, showSet = true, showLevel = true, showJunk = true }

-- The bank used to keep a full copy of every bag setting. A profile whose bank
-- matches its bags now just follows them; one that differs gets ownLook so
-- nothing changes. Runs once per profile (bankLook1).
-- p is a profile's data { modules = {...} }, saved values over the defaults.
function ns.UpgradeBank(p)
    if type(p) ~= "table" or type(p.modules) ~= "table" then return end
    local bags = p.modules.Bags
    if type(bags) ~= "table" or bags.bankLook1 then return end
    bags.bankLook1 = true
    local bank, D = bags.bank, ns.DEFAULTS
    if type(bank) ~= "table" then return end
    for k in pairs(ns.BANK_SHARED) do
        local mine = bank[k]
        if mine == nil then mine = D.bank[k] end
        local theirs = bags[k]
        if theirs == nil then theirs = D[k] end
        if mine ~= theirs then bank.ownLook = true; return end
    end
end
DaylightUI.DB.RegisterUpgrade(ns.UpgradeBank)
