-- Items: the price key of an item and what the game says about it.
-- Game/ is the one folder that calls the game's item, merchant, container
-- and Auction House functions; everything else asks through ns.Items,
-- ns.Merchant and (later) ns.Scan.

local _, ns = ...

ns.Game = ns.Game or {}
ns.Game.SLICE = 250      -- most replicate rows handled in one frame
ns.Game.SLICE_MS = 6     -- and at most this many milliseconds of them

-- A frame's reading stops at whichever comes first, SLICE rows or SLICE_MS.
-- Rows cost very different amounts (an item the game must load, a big house),
-- so a row count alone let one frame take 50 to 100 ms and the game stutter.
function ns.Game.Deadline()
    return debugprofilestop() + ns.Game.SLICE_MS
end
function ns.Game.Late(deadline)
    return debugprofilestop() >= deadline
end
ns.Game.ITEM_WAIT = 10   -- seconds to wait for the game to know an item (a full scan: of no item arriving)

-- Now, in seconds: the server's clock when the game has one (prices seen on
-- different PCs line up), else the computer's. Every price row is stamped with it.
function ns.Game.Now()
    if type(GetServerTime) == "function" then return GetServerTime() end
    return time()
end

local Items = {}
ns.Items = Items

local BIND_ON_PICKUP, BIND_QUEST = 1, 4   -- C_Item.GetItemInfo's bindType

-- "item:7429:enchant:g1:g2:g3:g4:suffix:...": the itemID (1st field) and
-- the suffix (7th), empty fields kept; one match, no table per call (the
-- tooltip asks on every fill).
local LINK_SUFFIX = "^item:([^:|]*):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*:([^:|]*)"
local LINK_ID = "^item:([^:|]*)"
local OWN_KEY = "^(%d+):(%-?%d+)$"   -- a price key of ours: "7429:-15"

-- What follows the item's own name in a whole name ("of Defense"), nil when
-- nothing does or the game hasn't loaded the item.
local function wordsAfter(whole, id)
    local base = whole and Items.Name(id)
    if not base or #whole <= #base + 1 then return nil end
    if string.sub(whole, 1, #base + 1) == base .. " " then return string.sub(whole, #base + 2) end
    return nil
end

local function wordsIn(link, id)
    return wordsAfter(string.match(link, "|h%[(.-)%]|h"), id)
end

-- A suffixed item lists the bags and the lists showing it again a frame after
-- something new is learned about suffixes ("SuffixLearned", once a frame).
local telling = false
local function tell()
    if telling then return end
    telling = true
    C_Timer.After(0, function()
        telling = false
        ns.Fire("SuffixLearned")
    end)
end

-- Keeps a suffix's words for showing its name ("of the Defender"), once. Words
-- only ever name a suffix: they never decide which price an item gets.
local function learn(suffix, words)
    local all = ns.DB.Suffixes()
    if not words or all[suffix] then return end
    all[suffix] = words
    tell()
end

-- The bonus IDs of a link ("12751", or "12751:6654" for two), nil for none.
-- On Forever a random suffix is a bonus ID in the link, one per suffix, while
-- the Auction House has its own number for it (a fixed list, 14296-14473, not
-- a fixed distance from the bonus). The 13th field counts the IDs after it.
local BONUS = "^" .. string.rep("[^:]*:", 12) .. "(%d+):([^|]*)"
local bonusPatterns = {}   -- how many IDs -> a pattern taking that many
local function bonusOf(link)
    local body = string.match(link, "item:([^|]+)")
    local count, rest
    if body then count, rest = string.match(body, BONUS) end
    count = tonumber(count)
    if not count or count < 1 or count > 16 then return nil end
    local pattern = bonusPatterns[count]
    if not pattern then
        pattern = "^" .. string.rep("%d+:", count - 1) .. "%d+"
        bonusPatterns[count] = pattern
    end
    return string.match(rest, pattern)
end

-- Pairs a link's bonus with the AH's suffix number. Only called with a link and
-- a number the game gave for the very same item (an auction's row, an item in
-- the bags), never from a name or a sample: a wrong pair would show one
-- suffix's price on another. Saved for the account, so it's learned once.
local function pair(link, suffix)
    local bonus = type(link) == "string" and bonusOf(link)
    if not bonus or type(suffix) ~= "number" or suffix == 0 then return end
    local paired = ns.DB.Table("suffixBonus")
    if paired[bonus] == suffix then return end
    paired[bonus] = suffix
    tell()
end

local function plainNumber(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "number" and v or nil
end

-- The AH's random suffix numbers on Forever.
Items.SUFFIX_FIRST, Items.SUFFIX_LAST = 14296, 14473

-- Without this, a suffix was only paired once that very item showed up at the
-- AH or in the bags, so a green just dropped had no price. The game's tooltip
-- for an item key carries the suffix's bonus in its link, so every suffix can
-- be paired at once from any item that rolls them. Done once a session, the
-- first time a link's suffix isn't paired. If the game's answer for a pair
-- already known disagrees, nothing is learned: a wrong pair shows one
-- suffix's price on another.
local taught = false
local function teach(itemID)
    if taught then return end
    local get = C_TooltipInfo and C_TooltipInfo.GetItemKey
    if type(get) ~= "function" then return end
    taught = true
    local level = select(4, C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID))
    level = plainNumber(level) or 0
    local paired = ns.DB.Table("suffixBonus")
    local bonusFor = {}
    for bonus, suffix in pairs(paired) do bonusFor[suffix] = bonus end
    local found = {}
    for suffix = Items.SUFFIX_FIRST, Items.SUFFIX_LAST do
        local data = get(itemID, level, suffix)
        local link = type(data) == "table" and data.hyperlink
        local bonus = type(link) == "string" and not (issecretvalue and issecretvalue(link)) and bonusOf(link)
        if bonus then
            local known = paired[bonus]
            if known ~= nil and known ~= suffix then return end
            if bonusFor[suffix] ~= nil and bonusFor[suffix] ~= bonus then return end
            if found[bonus] then return end   -- two suffixes, one bonus: not a real answer
            found[bonus] = suffix
        end
    end
    local any = false
    for bonus, suffix in pairs(found) do
        if paired[bonus] == nil then
            paired[bonus] = suffix
            any = true
        end
    end
    if any then tell() end
end

-- The price key of an item link, item ID or price key, and its plain
-- itemID key: "2589", "2589" for plain items; "7429:-15", "7429" for a link
-- with a random suffix (classic "of the Monkey" gear: the link's 7th field
-- after "item:", itemID being the 1st). A key gives itself back
-- ("7429:-15" -> "7429:-15", "7429"). Nil for anything that is not an item.
-- A third value, true: the link has a suffix whose AH number isn't paired yet,
-- so it has no price of its own, and the plain key's (the cheapest of every
-- suffix) isn't its price either.
function Items.Key(linkOrID)
    local id, suffix, unplaced
    if type(linkOrID) == "number" then
        id = linkOrID
    elseif type(linkOrID) == "string" then
        local at = string.find(linkOrID, "item:", 1, true)
        if at then
            -- anchored at the first "item:", as the game's links have one
            local idText, suffixText = string.match(linkOrID, LINK_SUFFIX, at)
            if not idText then idText = string.match(linkOrID, LINK_ID, at) end
            id, suffix = tonumber(idText), tonumber(suffixText)
            if id and suffix and suffix ~= 0 then
                learn(suffix, wordsIn(linkOrID, id))
            elseif id then
                local bonus = bonusOf(linkOrID)
                suffix = bonus and ns.DB.Table("suffixBonus")[bonus]
                if bonus and not suffix and not taught then
                    teach(id)
                    suffix = ns.DB.Table("suffixBonus")[bonus]
                end
                if not suffix then
                    -- Words after the item's name are a suffix not paired yet.
                    -- A bonus on an item whose name the game hasn't loaded may
                    -- be one too, so it gets no price rather than a guess.
                    unplaced = wordsIn(linkOrID, id) ~= nil
                        or (bonus ~= nil and Items.Name(id) == nil)
                end
            end
        else
            local idText, suffixText = string.match(linkOrID, OWN_KEY)
            if idText then
                id, suffix = tonumber(idText), tonumber(suffixText)
            else
                id = tonumber(linkOrID)
            end
        end
    end
    if not id or id <= 0 or id ~= math.floor(id) then return nil end
    local base = string.format("%d", id)
    if suffix and suffix ~= 0 then
        return base .. ":" .. string.format("%d", suffix), base
    end
    return base, base, unplaced or nil
end

-- The price key of an item key table (C_AuctionHouse's ItemKey: itemID,
-- itemLevel, itemSuffix, battlePetSpeciesID) and its plain itemID key; a
-- non-zero itemSuffix gives "id:suffix" (Forever's are positive: "4567:14303",
-- seen in play). Nil for anything else.
function Items.KeyOf(itemKey)
    if type(itemKey) ~= "table" or type(itemKey.itemID) ~= "number" then return nil end
    local key, base = Items.Key(itemKey.itemID)
    if not key then return nil end
    local suffix = itemKey.itemSuffix
    if type(suffix) == "number" and suffix ~= 0 and suffix == math.floor(suffix) then
        return base .. ":" .. string.format("%d", suffix), base
    end
    return key, base
end

-- Learns from an AH row's item key. With the row's own link (the same
-- auction): the link's bonus is paired with the key's suffix number, and the
-- words are kept for its name. Without one, only a name to show, from the name
-- the game gives the key (the same name its own browse list shows); a name
-- never decides a price. Nothing to learn for a plain key.
local seenLinks = {}   -- this session: a suffixed price key -> a real link of it
function Items.LearnKey(itemKey, link)
    if type(itemKey) ~= "table" then return end
    local id, suffix = itemKey.itemID, plainNumber(itemKey.itemSuffix)
    if type(id) ~= "number" or not suffix or suffix == 0 then return end
    if type(link) == "string" then
        seenLinks[id .. ":" .. string.format("%d", suffix)] = link
        pair(link, suffix)
        learn(suffix, wordsIn(link, id))
    end
    if ns.DB.Suffixes()[suffix] or not (C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo) then return end
    local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
    if type(info) == "table" and type(info.itemName) == "string"
        and not (issecretvalue and issecretvalue(info.itemName)) then
        learn(suffix, wordsAfter(info.itemName, id))
    end
end

-- The price key of what sits in a bag slot. A suffix not paired yet asks the
-- game for the AH's key of that very item (what its own sell frame does; it
-- may answer only at the AH) and pairs it, so what you carry and what's up for
-- sale are one item.
function Items.BagKey(bag, slot, link, id)
    local isLink = type(link) == "string"
    local key, base, unplaced = Items.Key(isLink and link or id)
    if not unplaced or not isLink then return key end
    if not (C_AuctionHouse and C_AuctionHouse.GetItemKeyFromItem and ItemLocation) then return key end
    local itemKey = C_AuctionHouse.GetItemKeyFromItem(ItemLocation:CreateFromBagAndSlot(bag, slot))
    local suffix = type(itemKey) == "table" and plainNumber(itemKey.itemSuffix)
    if not suffix or suffix == 0 then return key end
    pair(link, suffix)
    learn(suffix, wordsIn(link, Items.ID(key)))
    return base .. ":" .. string.format("%d", suffix)
end

-- The price key of an auction's own row (a search, your auctions, your bids):
-- the game's item key, which carries the AH's suffix number, pairs the row's
-- link with it; a plain one goes by the link, else the itemID.
function Items.RowKey(itemKey, link)
    local key, base = Items.KeyOf(itemKey)
    if key and key ~= base then
        Items.LearnKey(itemKey, link)
        return key, base
    end
    if type(link) == "string" then return Items.Key(link) end
    if key then return key, base end
    return Items.Key(type(itemKey) == "table" and itemKey.itemID or nil)
end

-- The itemID of a key ("7429:-15" -> 7429).
function Items.ID(key)
    return tonumber(string.match(tostring(key), "^%d+"))
end

local function info(itemID)
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    return C_Item.GetItemInfo(itemID)
end

-- False for bind-on-pickup and quest items; true when the game has not told
-- us (an item we can't read yet is assumed fine).
function Items.CanAuction(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = info(itemID)
    if type(bindType) ~= "number" then return true end
    return bindType ~= BIND_ON_PICKUP and bindType ~= BIND_QUEST
end

-- True for a bind-on-pickup item (it can never be sold), false otherwise;
-- false too while the game hasn't told us (unknown counts as sellable, as
-- CanAuction).
function Items.Soulbound(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = info(itemID)
    return bindType == BIND_ON_PICKUP
end

-- What a vendor pays for one, in copper; nil when it can't be sold or the
-- game doesn't know the item yet.
function Items.VendorSell(itemID)
    local _, _, _, _, _, _, _, _, _, _, sellPrice = info(itemID)
    if type(sellPrice) == "number" and sellPrice > 0 then return sellPrice end
    return nil
end

-- What disenchanting reads, no table made (a tooltip asks every fill):
-- quality, item level, classID; nil while the game hasn't loaded the item.
function Items.Gear(itemID)
    if type(itemID) ~= "number" then return nil end
    local name, _, quality, itemLevel, _, _, _, _, _, _, _, classID = info(itemID)
    if type(name) ~= "string" or name == "" then return nil end
    return quality, itemLevel, classID
end

-- What a list of items shows: { name, quality, icon, level (to use),
-- classID, subClassID }, or nil while the game hasn't loaded the item; then
-- it is asked for once (ITEM_DATA_LOAD_RESULT comes when it is in), unless
-- quiet (a walk over thousands of items must not ask for them all).
local asked = {}
function Items.Info(itemID, quiet)
    if type(itemID) ~= "number" then return nil end
    local name, _, quality, _, level, _, _, _, _, icon, _, classID, subClassID = info(itemID)
    if type(name) ~= "string" or name == "" then
        if not quiet and not asked[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
            asked[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    return { name = name, quality = quality, icon = icon, level = level, classID = classID, subClassID = subClassID }
end

-- What a search row shows, no table made (a big browse asks per row): name,
-- quality, item level, icon, vendorSell (nil when it can't be sold); nothing
-- while the game hasn't loaded the item. Never asks for it (Items.Request).
function Items.Row(itemID)
    local name, _, quality, level, req, _, _, _, _, icon, sell = info(itemID)
    if type(name) ~= "string" or name == "" then return nil end
    -- req: the level needed to use it, nil when anyone can (the game says 0 or 1)
    return name, quality, level, icon, (type(sell) == "number" and sell > 0) and sell or nil,
        (type(req) == "number" and req > 1) and req or nil
end

-- The item's name, nil while the game hasn't loaded it (never asks).
function Items.Name(itemID)
    if type(itemID) ~= "number" then return nil end
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemID)
        if type(n) == "string" and n ~= "" then return n end
    end
    local n = info(itemID)
    if type(n) == "string" and n ~= "" then return n end
    if not C_Item and GetItemInfo then
        n = GetItemInfo(itemID)
        if type(n) == "string" and n ~= "" then return n end
    end
    return nil
end

-- Asks the game to load an item (ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED follow).
function Items.Request(itemID)
    if type(itemID) == "number" and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Whether this character can use the item (the browse filter UsableOnly's
-- question: C_PlayerInfo.CanUseItem), nil when the game can't say.
function Items.Usable(itemID)
    if type(itemID) ~= "number" or not (C_PlayerInfo and C_PlayerInfo.CanUseItem) then return nil end
    local v = C_PlayerInfo.CanUseItem(itemID)
    if (issecretvalue and issecretvalue(v)) or type(v) ~= "boolean" then return nil end
    return v
end

-- False when this character can't use the item: too low a level for it, or
-- the game says no (class, armor, weapon skill). Nil while the game can't say.
function Items.CanUse(itemID)
    if type(itemID) ~= "number" then return nil end
    local _, _, _, _, need = info(itemID)
    local have = UnitLevel and UnitLevel("player")
    if type(need) == "number" and type(have) == "number" and need > have then return false end
    return Items.Usable(itemID)
end

-- The name a player knows a price key by: "Barbaric Battle Axe of the Bear".
-- base: the item's name when the caller has it. A suffix not seen yet says
-- so: two rows of one plain name can't be told apart. Nil while the game
-- hasn't loaded the item.
function Items.KeyName(key, base)
    local idText, suffixText = string.match(tostring(key), OWN_KEY)
    if not idText then return base or Items.Name(Items.ID(key)) end
    local id = tonumber(idText)
    base = base or Items.Name(id)
    if not base then return nil end
    local words = ns.DB.Suffixes()[tonumber(suffixText)]
    if words then return base .. " " .. words end
    return string.format(ns.L["%s (unknown suffix)"], base)
end

-- A suffixed key's real link (a carried one's, else one seen on the AH this
-- session), nil when there's none or for a plain key. Never built from the key:
-- on Forever the AH's suffix number isn't the link's, so that's the plain item.
function Items.RealLinkOf(key)
    if not string.match(tostring(key), OWN_KEY) then return nil end
    return ns.Bags.Link(key) or seenLinks[key]
end

-- What shows a suffixed key's own tooltip (its real link, else one built from
-- the key), nil for a plain key.
function Items.LinkOf(key)
    local idText, suffixText = string.match(tostring(key), OWN_KEY)
    if not idText then return nil end
    return Items.RealLinkOf(key) or ("item:" .. idText .. ":0:0:0:0:0:" .. suffixText)
end

-- Fills an item tooltip for a row: a suffixed key shows its own item (name and
-- stats); by the itemID only it would be the plain item, which has neither.
-- No real link: by the AH's item key, as the game's own AH fills a browse row.
function Items.SetTip(tip, key, itemID)
    local link = key and Items.RealLinkOf(key)
    if link and tip.SetHyperlink then tip:SetHyperlink(link) return end
    local idText, suffixText = string.match(tostring(key), OWN_KEY)
    if idText and tip.SetItemKey then
        local id, suffix = tonumber(idText), tonumber(suffixText)
        local _, _, _, itemLevel = info(id)
        local itemKey = { itemID = id, itemLevel = plainNumber(itemLevel) or 0, itemSuffix = suffix, battlePetSpeciesID = 0 }
        -- the game's own AH first asks for a real link of the key (its stats);
        -- SetItemKey alone is the group's "may vary" tooltip, no stats
        if C_AuctionHouse and C_AuctionHouse.GetItemKeySampleLink and tip.SetHyperlink then
            local sample = C_AuctionHouse.GetItemKeySampleLink(itemKey)
            -- Shown, never kept or paired: a sample may not be the key's own item.
            if type(sample) == "string" and not (issecretvalue and issecretvalue(sample)) and sample ~= "" then
                tip:SetHyperlink(sample)
                return
            end
        end
        local reqLevel
        if C_AuctionHouse and C_AuctionHouse.GetItemKeyRequiredLevel then
            reqLevel = plainNumber(C_AuctionHouse.GetItemKeyRequiredLevel(itemKey))
        end
        tip:SetItemKey(id, itemKey.itemLevel, suffix, reqLevel)
        return
    end
    link = key and Items.LinkOf(key)
    if link and tip.SetHyperlink then tip:SetHyperlink(link)
    elseif itemID and tip.SetItemByID then tip:SetItemByID(itemID) end
end

-- An item's whole link, what Shift and Ctrl on a row hand the game (chat needs
-- the real thing): from a link, a price key or an itemID. Nil while the game
-- hasn't loaded the item.
function Items.Hyperlink(item)
    if item == nil then return nil end
    if string.find(tostring(item), "|H", 1, true) then return item end
    local ask = Items.LinkOf(item) or Items.ID(item)
    if type(ask) == "string" and string.find(ask, "|H", 1, true) then return ask end
    if ask == nil then return nil end
    local _, link = info(ask)
    return type(link) == "string" and link or nil
end

-- The link of a table's item row (Parts.Table's link).
function Items.RowLink(d)
    if d.kind ~= "line" then return nil end
    return Items.Hyperlink(d.key or d.itemID or d.out)
end

-- The game's name for an item's kind ("Two-Handed Axes"), else its class's.
function Items.TypeName(classID, subClassID)
    if type(classID) == "number" and type(subClassID) == "number" then
        local fn = (C_Item and C_Item.GetItemSubClassInfo) or _G.GetItemSubClassInfo
        if type(fn) == "function" then
            local name = fn(classID, subClassID)
            if type(name) == "string" and name ~= "" then return name end
        end
    end
    return Items.ClassName(classID)
end

-- The game's name for an item class ("Trade Goods"), nil when it has none.
function Items.ClassName(classID)
    if type(classID) ~= "number" then return nil end
    local fn = (C_Item and C_Item.GetItemClassInfo) or _G.GetItemClassInfo
    if type(fn) ~= "function" then return nil end
    local name = fn(classID)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- The itemID the client knows by an item's name (only items in its cache:
-- C_Item.GetItemInfoInstant takes a name too), nil when it doesn't. A
-- letter that names only an item finds its key this way (ns.Book.KeyOfName).
-- The game finds an item by its name only once it has loaded that item this
-- session, so names a full scan read are kept too, by client language.
function Items.Names()
    local all = ns.DB.Table("itemNames")
    local lang = GetLocale and GetLocale() or "enUS"
    if type(all[lang]) ~= "table" then all[lang] = {} end
    return all[lang]
end

function Items.LearnName(name, id, names)
    if type(name) ~= "string" or name == "" or type(id) ~= "number" then return end
    if issecretvalue and (issecretvalue(name) or issecretvalue(id)) then return end
    (names or Items.Names())[name:lower()] = id
end

function Items.IDByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(name)
    if not (issecretvalue and issecretvalue(id)) and type(id) == "number" then return id end
    return Items.Names()[name:lower()]
end

-- ---------------------------------------------------------------------
-- The stack under an item tooltip
-- ---------------------------------------------------------------------

local function number(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "number" and v or nil
end

-- What the game filled the tooltip from: { getterName =, getterArgs = }.
-- The tooltip keeps it while it fills (processingInfo) or afterwards (info,
-- GetPrimaryTooltipInfo).
local function infoOf(tip)
    if type(tip) ~= "table" then return nil end
    local i = tip.processingInfo
    if type(i) ~= "table" then i = tip.info end
    if type(i) ~= "table" and type(tip.GetPrimaryTooltipInfo) == "function" then
        i = tip:GetPrimaryTooltipInfo()
    end
    return type(i) == "table" and i or nil
end

local function bagCount(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local row = C_Container.GetContainerItemInfo(bag, slot)
        local n = type(row) == "table" and number(row.stackCount)
        if n then return n end
    end
    if ItemLocation and C_Item and C_Item.GetStackCount then
        return number(C_Item.GetStackCount(ItemLocation:CreateFromBagAndSlot(bag, slot)))
    end
end

local function merchantCount(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local row = C_MerchantFrame.GetItemInfo(i)
        return type(row) == "table" and number(row.stackCount) or nil
    end
    if GetMerchantItemInfo then
        return number((select(4, GetMerchantItemInfo(i))))
    end
end

local COUNTERS = {
    GetBagItem = function(a) return bagCount(number(a[1]), number(a[2])) end,
    GetMerchantItem = function(a) return merchantCount(number(a[1])) end,
    GetBuybackItem = function(a)
        if GetBuybackItemInfo then return number((select(4, GetBuybackItemInfo(number(a[1]))))) end
    end,
    GetInventoryItem = function(a)
        local unit = a[1]
        if type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) then return nil end
        if GetInventoryItemCount then return number(GetInventoryItemCount(unit, number(a[2]))) end
    end,
}

-- How many the tooltip's item stands for (a bag stack, a merchant's pack,
-- an equipped count), 1 when the game doesn't say.
function Items.StackCount(tip)
    local info = infoOf(tip)
    local name, args = info and info.getterName, info and info.getterArgs
    local counter = type(name) == "string" and COUNTERS[name]
    local n
    if counter and type(args) == "table" then
        n = counter(args)
    end
    if type(n) ~= "number" or n < 1 then return 1 end
    return math.floor(n)
end
