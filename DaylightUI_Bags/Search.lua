-- Bag search. Terms are joined with & (all) and | (any); ; works as | too, so a
-- custom group can list several words ("ore; bar; stone"). Each term is a name,
-- a keyword or a comparison.
--
--   * a plain word that is a keyword finds those items plus names containing
--     it; any other word searches names (equipment set names too)
--   * "#word" is the keyword only (an unknown keyword matches nothing)
--   * "!term" is everything the term doesn't match
--   * item types come from class and subclass (GetItemInfoInstant, no loading
--     needed); quality and bound state come from the bag
--   * "q>rare", "q>=uncommon", "q<epic", "q=3" compare quality;
--     "ilvl>20", "ilvl<=10", "ilvl20-30" compare item level (gear only)
--   * "boe & !q<rare | potion": & binds tighter than |
--
-- Replaces the game's name search. Each slot's result goes to the button's own
-- SetMatchesSearch so the game's dimming shows.

local _, ns = ...
local L = DaylightUI.L

local Search = {}
ns.Search = Search

-- The game's item classes (also used for the bag's groups, Categories.lua),
-- plus the consumable subclasses that matter here.
Search.CLASS = { consumable = 0, container = 1, weapon = 2, armor = 4, reagent = 5, projectile = 6, tradegoods = 7,
                 recipe = 9, quiver = 11, quest = 12, key = 13, misc = 15 }
Search.FOOD = { [5] = true }                           -- Food & Drink
Search.POTION = { [1] = true, [2] = true, [3] = true }  -- potions, elixirs, flasks
Search.QUALITY = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

local C = Search.CLASS

-- Keywords: facts -> true when the item matches.
Search.KEYWORDS = {
    gear = function(f) return f.classID == C.weapon or f.classID == C.armor end,
    weapon = function(f) return f.classID == C.weapon end,
    armor = function(f) return f.classID == C.armor end,
    consumable = function(f) return f.classID == C.consumable end,
    food = function(f) return f.classID == C.consumable and Search.FOOD[f.subClassID] == true end,
    potion = function(f) return f.classID == C.consumable and Search.POTION[f.subClassID] == true end,
    reagent = function(f) return f.classID == C.reagent or f.classID == C.tradegoods or f.craftingReagent == true end,
    tradegoods = function(f) return f.classID == C.tradegoods end,
    recipe = function(f) return f.classID == C.recipe end,
    key = function(f) return f.classID == C.key end,
    container = function(f) return f.classID == C.container end,
    quest = function(f) return f.classID == C.quest or f.questItem == true end,
    junk = function(f) return f.quality == 0 end,
    -- BoE / BoU while not yet bound (bind type from GetItemInfo).
    boe = function(f) return f.bindType == 2 and f.bound ~= true end,
    bou = function(f) return f.bindType == 3 and f.bound ~= true end,
    soulbound = function(f) return f.bound == true end,
    set = function(f) return f.inSet == true end,
    locked = function(f) return f.locked == true end,
}
local K = Search.KEYWORDS
K.drink, K.armour, K.bag, K.trade, K.bound, K.sets = K.food, K.armor, K.container, K.tradegoods, K.soulbound, K.set
for name, q in pairs(Search.QUALITY) do
    K[name] = function(f) return f.quality == q end
end

-- Keyword list for the search box's tooltip.
Search.HELP = L["Kinds: gear, weapon, armor, consumable, food, drink, potion, reagent, tradegoods, recipe, key, container, quest, junk\n"
    .. "Binding: boe, bou, soulbound. In an equipment set: set, or the set's name. Locked: locked\n"
    .. "Quality: poor, common, uncommon, rare, epic, legendary, or q>rare, q>=uncommon, q<epic\n"
    .. "Item level: ilvl>20, ilvl<=10, ilvl20-30\n"
    .. "Join with & (all) or | (any), ! for not: boe & q>common, food | potion, gear & !set\n"
    .. "A word that isn't one of these finds names. Start with # for the keyword only."]
    .. "\n" .. L["; works like |, so one search can list several words: ore; bar; stone"]

local function trim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end

local function qualityOf(word)
    local n = tonumber(word)
    if n then return n end
    return Search.QUALITY[word]
end

local function compare(v, op, n)
    if type(v) ~= "number" then return false end
    if op == ">" then return v > n elseif op == ">=" then return v >= n
    elseif op == "<" then return v < n elseif op == "<=" then return v <= n end
    return v == n
end

local NEVER = function() return false end

-- Fields a comparison can read: q>rare, ilvl>=20.
Search.FIELDS = { q = "quality", quality = "quality", ilvl = "itemLevel", level = "itemLevel" }

-- Search words in the player's language. A translation gives the same words in
-- the same order, one word each; "a/b" lets either spelling work (poción/pocion).
-- The English list is written twice so the translation key stays a plain string.
do
    local english, i = {}, 0
    for w in string.gmatch("gear weapon armor consumable food drink potion reagent tradegoods recipe key container bag quest junk soulbound set locked poor common uncommon rare epic legendary quality level", "%S+") do english[#english + 1] = w end
    for spellings in string.gmatch(L["gear weapon armor consumable food drink potion reagent tradegoods recipe key container bag quest junk soulbound set locked poor common uncommon rare epic legendary quality level"], "%S+") do
        i = i + 1
        local en = english[i]
        if not en then break end
        for w in string.gmatch(string.lower(spellings), "[^/]+") do
            if w ~= en then
                if K[en] and not K[w] then K[w] = K[en] end
                if Search.QUALITY[en] and not Search.QUALITY[w] then Search.QUALITY[w] = Search.QUALITY[en] end
                if Search.FIELDS[en] and not Search.FIELDS[w] then Search.FIELDS[w] = Search.FIELDS[en] end
            end
        end
    end
end

-- Turns one term (lowercase, trimmed, non-empty) into a test on item facts.
local function term(text)
    -- ilvl20-30: inclusive range.
    local field, lo, hi = string.match(text, "^(%a+)%s*(%d+)%s*%-%s*(%d+)$")
    if field and Search.FIELDS[field] == "itemLevel" then
        lo, hi = tonumber(lo), tonumber(hi)
        return function(f)
            local v = f.itemLevel
            return type(v) == "number" and v >= lo and v <= hi
        end
    end
    local op, word
    field, op, word = string.match(text, "^(%a+)%s*([<>=]=?)%s*(%w+)$")
    local key = field and Search.FIELDS[field]
    if key then
        local n = (key == "quality") and qualityOf(word) or tonumber(word)
        if not n then return NEVER end
        return function(f) return compare(f[key], op, n) end
    end
    local keywordOnly = string.sub(text, 1, 1) == "#"
    if keywordOnly then text = string.sub(text, 2) end
    local keyword = K[text]
    if keywordOnly then return keyword or NEVER end
    return function(f)
        if keyword and keyword(f) then return true end
        if type(f.name) == "string" and string.find(string.lower(f.name), text, 1, true) then return true end
        return type(f.setNames) == "string" and string.find(string.lower(f.setNames), text, 1, true) ~= nil
    end
end

-- "!term" negates; "!!" cancels out.
local function negated(text)
    local no = false
    while string.sub(text, 1, 1) == "!" do
        no = not no
        text = trim(string.sub(text, 2))
    end
    if text == "" then return nil end
    local test = term(text)
    if not no then return test end
    return function(f) return not test(f) end
end

local function split(text, sep)
    local out = {}
    for part in string.gmatch(text .. sep, "(.-)%" .. sep) do out[#out + 1] = trim(part) end
    return out
end

-- The whole search as a test on item facts (nil = no search). & binds tighter
-- than |, so "a & b | c" is (a and b) or c. Empty pieces ("a &", a lone "!")
-- are dropped while typing.
function Search.Parse(text)
    local whole = string.lower(trim(text))
    if whole == "" then return nil end
    whole = string.gsub(whole, ";", "|")
    local any = {}
    for _, part in ipairs(split(whole, "|")) do
        local all = {}
        for _, piece in ipairs(split(part, "&")) do
            local test = piece ~= "" and negated(piece)
            if test then all[#all + 1] = test end
        end
        if #all == 1 then any[#any + 1] = all[1]
        elseif #all > 1 then
            any[#any + 1] = function(f)
                for i = 1, #all do if not all[i](f) then return false end end
                return true
            end
        end
    end
    if #any == 0 then return nil end
    if #any == 1 then return any[1] end
    return function(f)
        for i = 1, #any do if any[i](f) then return true end end
        return false
    end
end

-- Baganator's searches (Syndicator's language) turned into this one, for its
-- category import. Its operators are the same (& | !, ~ also means not, same
-- order), "#word" is a keyword, and a bare number or range is an item level.
-- Each English keyword maps to one here, or to false when there's nothing like
-- it: those terms are left out and named back to the player.
Search.SYNDICATOR = {
    gear = "gear", equipment = "gear", weapon = "weapon", armor = "armor", armour = "armor",
    consumable = "consumable", food = "food", drink = "drink", potion = "potion",
    reagent = "reagent", ["crafting reagent"] = "reagent", ["trade goods"] = "tradegoods", tradegoods = "tradegoods",
    tradeskill = "tradegoods", recipe = "recipe", key = "key", keyring = "key", container = "container", bag = "container",
    quest = "quest", ["quest item"] = "quest", junk = "junk", trash = "junk",
    boe = "boe", bou = "bou", soulbound = "soulbound", bound = "soulbound", set = "set", ["equipment set"] = "set",
    poor = "poor", common = "common", uncommon = "uncommon", rare = "rare", epic = "epic", legendary = "legendary",
    boa = false, warbound = false, artifact = false, heirloom = false, toy = false, pet = false, ["battle pet"] = false,
    mount = false, socket = false, cosmetic = false, reputation = false, manuscript = false, use = false, open = false,
    ["tradeable loot"] = false, gem = false, ["item enhancement"] = false, miscellaneous = false, profession = false,
    classic = false, vanilla = false, bc = false, tbc = false, ["burning crusade"] = false, wrath = false, wotlk = false,
    cata = false, cataclysm = false, mop = false, pandaria = false, wod = false, draenor = false, legion = false,
    bfa = false, shadowlands = false, dragonflight = false, ["war within"] = false, ["the war within"] = false,
}

-- One Syndicator term (lowercase, trimmed) as one of ours, or nil.
local function fromSyndicatorTerm(text)
    local no = ""
    while true do
        local first = string.sub(text, 1, 1)
        if first ~= "!" and first ~= "~" then break end
        no = no == "" and "!" or ""
        text = trim(string.sub(text, 2))
    end
    if text == "" then return nil end
    if string.match(text, "^%d+$") then return no .. "ilvl=" .. text end
    local op, n = string.match(text, "^([<>]=?)%s*(%d+)$")
    if op then return no .. "ilvl" .. op .. n end
    local lo, hi = string.match(text, "^(%d+)%s*%-%s*(%d+)$")
    if lo then return no .. "ilvl" .. lo .. "-" .. hi end
    local keywordOnly = string.sub(text, 1, 1) == "#"
    local word = keywordOnly and trim(string.sub(text, 2)) or text
    local mapped = Search.SYNDICATOR[word]
    if mapped then return no .. (keywordOnly and "#" or "") .. mapped end
    if mapped == false then return nil end
    -- A keyword in the player's own language works as it is.
    if keywordOnly then return K[word] and (no .. "#" .. word) or nil end
    return no .. word
end

-- The whole search, plus the terms left out. nil search = nothing left of it.
function Search.FromSyndicator(text)
    local whole = string.lower(trim(text))
    local dropped = {}
    if whole == "" then return nil, dropped end
    -- Brackets around the whole search change nothing; anywhere else they would.
    local inner = string.match(whole, "^%((.*)%)$")
    if inner and not string.find(inner, "[()]") then whole = trim(inner) end
    if string.find(whole, "[();]") then
        dropped[1] = whole
        return nil, dropped
    end
    local any = {}
    for _, part in ipairs(split(whole, "|")) do
        local all = {}
        for _, piece in ipairs(split(part, "&")) do
            if piece ~= "" then
                local ours = fromSyndicatorTerm(piece)
                if ours then all[#all + 1] = ours else dropped[#dropped + 1] = piece end
            end
        end
        if #all > 0 then any[#any + 1] = table.concat(all, " & ") end
    end
    if #any == 0 then return nil, dropped end
    return table.concat(any, " | "), dropped
end

-- Facts about the item in a slot, for matching. Cat.Facts adds to the same
-- table for groups, so item info is read once for both. quest is the slot's
-- quest info if the caller already has it.
function Search.Facts(bag, slot, info, quest)
    local f = { quality = info.quality, name = info.itemName, bound = info.isBound == true, link = info.hyperlink }
    f.locked = ns.Categories ~= nil and ns.Categories.IsLocked(info.itemID)
    local id = info.itemID or info.hyperlink
    if id and C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, id)
        if ok then f.classID, f.subClassID = classID, subClassID end
    end
    if not f.name and info.hyperlink then f.name = string.match(info.hyperlink, "%[(.-)%]") end
    if C_Item and C_Item.GetItemInfo and (info.hyperlink or info.itemID) then
        local ok, name, _, _, _, _, _, _, maxStack, _, _, _, _, _, bindType, _, _, reagent = pcall(C_Item.GetItemInfo, info.hyperlink or info.itemID)
        if ok then
            f.name = f.name or name
            f.craftingReagent = reagent == true
            if type(maxStack) == "number" then f.maxStack = maxStack end
            if type(bindType) == "number" then f.bindType = bindType end
        end
    end
    if f.classID == C.weapon or f.classID == C.armor then f.itemLevel = DaylightUI.ItemLevel(info.hyperlink or info.itemID) end
    if C_Container.GetContainerItemEquipmentSetInfo then
        local ok, yes, names = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
        f.inSet = ok and yes == true
        if f.inSet and type(names) == "string" then f.setNames = names end
    end
    if type(quest) ~= "table" then
        local qok, q = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
        quest = qok and q or nil
    end
    if type(quest) == "table" then f.questItem = quest.isQuestItem == true or quest.questID ~= nil end
    return f
end

-- Whether a slot's item stands out under a window's search (match from
-- Search.Parse, nil = no search). Everything matches with no search, and empty
-- slots never dim since they're only an outline.
function Search.Matches(bag, slot, info, match, quest)
    if not match or not info then return true end
    return match(Search.Facts(bag, slot, info, quest)) == true
end
