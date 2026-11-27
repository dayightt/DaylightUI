-- Missing buffs, the Consumables section (Reminder.lua runs it), as
-- EllesmereUI's WoW Forever section works: Camp Benefits, the sleeping bag
-- (and its sleep timer while you rest in it), Well Fed (a click eats), the
-- Arcane Censer in dungeons, scrolls and elixirs per stat, and weapon stones
-- and oils (ReminderSelf.lua reads the weapons). Out of a fight and outside
-- PvP only.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local Items = {}
BL.ReminderItems = Items

local Data = BL.ReminderData

local function H() return BL.Reminder.H end
local function cfg() return BL.Reminder.Section("items") end

local function useMacro(id) return "/use [nocombat] item:" .. id end

-- Camp Benefits: by its id, shown while it isn't on you. Nothing to click.
local function camp(state, out)
    local h = H()
    if state.secret and not h.ranksReadable({ Data.CAMP }) then return end
    if h.playerAura(Data.CAMP) ~= false then return end
    out[#out + 1] = { key = "camp", kind = "item", section = "items", short = L["Camp"], tipSpell = Data.CAMP,
                      icon = h.spellIcon(Data.CAMP, "Interface\\Icons\\Spell_Fire_Fire") }
end

-- ---------------------------------------------------------------------
-- The sleeping bag
-- ---------------------------------------------------------------------

local function atMaxLevel()
    local h = H()
    if h.call(IsPlayerAtEffectiveMaxLevel) == true then return true end
    local level = h.call(UnitLevel, "player")
    local max = h.call(GetMaxLevelForPlayerExpansion) or h.call(GetMaxPlayerLevel)
    return type(level) == "number" and type(max) == "number" and level >= max
end

local function bagOwned()
    local h = H()
    return not atMaxLevel() and h.itemCount(Data.SLEEPING_BAG.item) > 0
end

-- The sleep timer: while you sleep in the bag (its own aura on you), a
-- countdown to three stacks of Well-Rested, a minute a stack, started again
-- when a stack lands. Kept across a /reload.
local sleep -- { startedAt, stacks, ends (false once full) }
function Items.ForgetSleep() sleep = nil end

local function bagStacks(state)
    local h = H()
    local bag = Data.SLEEPING_BAG
    if state.secret and not h.ranksReadable({ bag.buff }) then return nil end
    local aura = h.playerAura(bag.buff)
    if aura == nil then return nil end
    return aura and (tonumber(h.plain(aura.applications)) or 0) or 0, aura or nil
end

-- The one icon that shows while resting: the sleep timer.
function Items.SleepTimer(state, out)
    local h = H()
    local c = cfg()
    local bag = Data.SLEEPING_BAG
    if c.bag ~= true or c.bagTimer == false or state.pvp or not bagOwned() then sleep = nil return end
    if state.secret and not h.ranksReadable({ bag.sleeping }) then return end
    if not h.playerAura(bag.sleeping) then sleep = nil return end
    local stacks = bagStacks(state)
    if not stacks then return end
    local now = state.now
    if not sleep then
        sleep = { startedAt = now, stacks = stacks }
    elseif stacks ~= sleep.stacks then
        sleep.startedAt, sleep.stacks = now, stacks
        sleep.ends = stacks >= bag.stacks and false or nil
    end
    local e = { key = "sleepingbag", kind = "item", section = "items", short = L["Sleeping"], tipSpell = bag.buff,
                icon = h.spellIcon(bag.buff), badge = string.format("%d/%d", math.min(stacks, bag.stacks), bag.stacks) }
    if sleep.ends ~= false then
        local ends = sleep.startedAt + math.max(1, bag.stacks - stacks) * 60
        sleep.ends = ends
        if ends > now then
            e.expireAt = ends
            if not state.nextLook or ends < state.nextLook then state.nextLook = ends end
        end
    end
    out[#out + 1] = e
end

local function sleepingBag(state, out)
    local h = H()
    local c = cfg()
    local bag = Data.SLEEPING_BAG
    if not bagOwned() then return end
    local stacks, aura = bagStacks(state)
    if not stacks then return end
    local ends = aura and h.below(state, aura, c.bagBelow)
    if stacks < bag.stacks or ends then
        out[#out + 1] = { key = "sleepingbag", kind = "item", section = "items", short = L["Sleeping"],
                          item = bag.item, tipItem = bag.item, macro = useMacro(bag.item), expireAt = ends,
                          icon = h.itemIcon(bag.item), count = h.itemCount(bag.item) }
    end
end

-- ---------------------------------------------------------------------
-- Well Fed
-- ---------------------------------------------------------------------

local NUM_BAGS = 4
local foods -- [itemID] = count, kept until the bags change

local function isFood(id, name)
    local h = H()
    local ok, _, _, _, _, _, class = h.read(C_Item.GetItemInfoInstant, id)
    if not ok or h.plain(class) ~= (Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0) then return false end
    return h.call(C_Item.GetItemSpell, id) == name
end

local function scanFood()
    local h = H()
    local found = {}
    local name = h.spellName(Data.FOOD_SPELL)
    local C = C_Container
    if not name or type(C) ~= "table" then return found end
    for bag = 0, NUM_BAGS do
        for slot = 1, (h.call(C.GetContainerNumSlots, bag) or 0) do
            local id = h.call(C.GetContainerItemID, bag, slot)
            if type(id) == "number" and isFood(id, name) then
                local ok, info = h.read(C.GetContainerItemInfo, bag, slot)
                info = ok and type(info) == "table" and BL.PlainTable(info) or nil
                found[id] = (found[id] or 0) + (info and tonumber(info.stackCount) or 1)
            end
        end
    end
    return found
end

local function foodNow()
    if not foods then foods = scanFood() end
    return foods
end
Items.Foods = foodNow

-- A bag change: a food whose count dropped is the one just eaten.
local function bagsChanged()
    if not foods then return end
    local now = scanFood()
    for id, n in pairs(foods) do
        if (now[id] or 0) < n then
            local store = H().charStore()
            if store then store.food = id end
            break
        end
    end
    foods = now
end

-- The food a click eats: the picked one, else the one last eaten, else the
-- highest-level one usable (ties: item level, then id).
function Items.PickFood(list, picked)
    local h = H()
    if picked and list[picked] then return picked end
    local store = h.charStore()
    local last = store and store.food
    if last and list[last] then return last end
    local level = h.call(UnitLevel, "player") or 0
    local best, bestMin, bestIlvl
    for id in pairs(list) do
        local ok, _, _, _, ilvl, minLevel = h.read(C_Item.GetItemInfo, id)
        minLevel, ilvl = ok and tonumber(h.plain(minLevel)) or 0, ok and tonumber(h.plain(ilvl)) or 0
        if minLevel <= level and (not best or minLevel > bestMin
            or (minLevel == bestMin and (ilvl > bestIlvl or (ilvl == bestIlvl and id > best)))) then
            best, bestMin, bestIlvl = id, minLevel, ilvl
        end
    end
    return best
end

local function wellFed(state, out)
    local h = H()
    local c = cfg()
    local name = h.spellName(Data.WELL_FED) or L["Well Fed"]
    if state.secret and not h.ranksReadable({ Data.WELL_FED }) then return end
    local aura = h.auraByName("player", name)
    if aura == nil then return end
    local latest, unknown = nil, false
    if aura then
        latest = h.endsAt(aura)
    else
        for _, id in ipairs(Data.FOOD_BUFFS) do
            local a = h.playerAura(id)
            if a == nil then unknown = true
            elseif a then
                aura = a
                local ends = h.endsAt(a)
                if ends and (not latest or ends > latest) then latest = ends end
            end
        end
    end
    if unknown and not aura then return end
    local ends
    if aura then
        if not latest then return end
        ends = h.below(state, { expirationTime = latest }, c.wellFedBelow)
        if not ends then return end
    end
    local e = { key = "wellfed", kind = "item", section = "items", short = name, expireAt = ends,
                icon = h.spellIcon(Data.WELL_FED), tipSpell = Data.WELL_FED }
    local list = foodNow()
    local picker = BL.Reminder.Config().picker == true
    local id = Items.PickFood(list, picker and c.wellFedItem or nil)
    if id then
        e.item, e.tipItem, e.tipSpell = id, id, nil
        e.icon, e.count, e.macro = h.itemIcon(id), list[id], useMacro(id)
        if picker and next(list) then e.foods = list end
    end
    out[#out + 1] = e
end

-- ---------------------------------------------------------------------
-- The Arcane Censer (dungeons only)
-- ---------------------------------------------------------------------

local function censer(state, out)
    local h = H()
    if state.kind ~= "party" then return end
    local item
    for _, id in ipairs(Data.CENSER.items) do
        if h.itemCount(id) > 0 then item = id break end
    end
    if not item then return end
    if state.secret and not h.ranksReadable({ Data.CENSER.buff }) then return end
    if h.playerAura(Data.CENSER.buff) ~= false then return end
    out[#out + 1] = { key = "censer", kind = "item", section = "items", short = L["Censer"], item = item,
                      tipItem = item, macro = useMacro(item), icon = h.itemIcon(item), count = h.itemCount(item) }
end

-- ---------------------------------------------------------------------
-- Scrolls and elixirs
-- ---------------------------------------------------------------------

-- A stat locked for a class: a mage knowing Arcane Intellect never needs an
-- Intellect scroll, a priest knowing Fortitude or Divine Spirit the same.
function Items.Locked(key, class)
    for _, s in ipairs(Data.STATS) do
        if s.key == key then
            if not s.class or s.class ~= class then return false end
            local fam = Data.byKey[s.family]
            return H().highest(fam and fam.single) ~= nil
        end
    end
    return false
end

-- The camp's Incense Candle Intellect and whether it holds a First Aid Kit,
-- read from the Camp Benefits tooltip's lines.
local function campBonuses()
    local h = H()
    local aura = h.playerAura(Data.CAMP)
    if not aura then return 0, false end
    local id = h.plain(aura.auraInstanceID)
    local get = C_TooltipInfo and C_TooltipInfo.GetUnitAuraByAuraInstanceID
    if type(id) ~= "number" or type(get) ~= "function" then return 0, false end
    local candle, kit = h.spellName(Data.CAMP_CANDLE), h.spellName(Data.CAMP_KIT)
    local ok, tip = h.read(get, "player", id)
    tip = ok and type(tip) == "table" and BL.PlainTable(tip) or nil
    local lines = tip and BL.PlainTable(tip.lines)
    if not lines then return 0, false end
    local amount, hasKit = 0, false
    for _, line in ipairs(lines) do
        line = BL.PlainTable(line)
        local text = line and h.plain(line.leftText)
        if type(text) == "string" then
            for row in text:gmatch("[^\r\n]+") do
                local a, b
                if candle then a, b = row:find(candle, 1, true) end
                if a and row:sub(1, a - 1):match("^%s*$") then amount = tonumber(row:match("(%d+)%D*$", b + 1)) or amount end
                if kit and not hasKit then
                    a = row:find(kit, 1, true)
                    hasKit = a ~= nil and row:sub(1, a - 1):match("^%s*$") ~= nil
                end
            end
        end
    end
    return amount, hasKit
end

local function owned(items)
    for _, it in ipairs(items) do
        if H().itemCount(it[1]) > 0 then return true end
    end
    return false
end

-- The bonus an item must beat (nil: nothing needed), and when the active one
-- runs out within Show Below.
local function toBeat(state, stat, items, family, warn, stronger, candle)
    local h = H()
    local amount = 0
    if family then
        local fam = Data.byKey[family]
        if not BL.Reminder.FamReadable(state, fam) then return nil end
        local aura = BL.Reminder.FamilyAura("player", fam)
        if aura == nil then return nil end
        if aura then
            if not stronger then return nil end
            local id = h.plain(aura.spellId)
            amount = Data.AMOUNTS[id]
            if not amount then return nil end
        end
    end
    if stat.key == "intellect" then amount = math.max(amount, candle or 0) end
    if (amount > 0 and not stronger) or amount >= items[1][2] then return nil end
    if state.secret then
        local ids = {}
        for _, it in ipairs(items) do ids[#ids + 1] = it[3] end
        if not h.ranksReadable(ids) then return nil end
    end
    local active, latest = 0, nil
    for _, it in ipairs(items) do
        local a = h.playerAura(it[3])
        if a == nil then return nil end
        if a then
            if active == 0 then active = it[2] end
            local ends = h.endsAt(a)
            if ends and (not latest or ends > latest) then latest = ends end
        end
    end
    if active == 0 then return amount end
    if warn and latest then
        local ends = h.below(state, { expirationTime = latest }, warn)
        if ends then return amount, ends end
    end
    if stronger and active < items[1][2] then return math.max(amount, active) end
    return nil
end

-- The item to use: strongest first (weakest with Rank to use), beating the
-- bonus, carried, and not above your level. choices gets every eligible one.
local function pickItem(items, bonus, low, choices)
    local h = H()
    local level = h.call(UnitLevel, "player") or 0
    local first, last, step = 1, #items, 1
    if low then first, last, step = #items, 1, -1 end
    local found
    for i = first, last, step do
        local id, gives = items[i][1], items[i][2]
        if gives > bonus and h.itemCount(id) > 0 then
            local ok, _, _, _, _, need = h.read(C_Item.GetItemInfo, id)
            need = ok and tonumber(h.plain(need)) or nil
            if need and level >= need then
                if not choices then return id end
                choices[id] = h.itemCount(id)
                found = found or id
            end
        end
    end
    return found
end

local function statEntry(out, stat, id, ends, key, choices)
    local h = H()
    local e = { key = key, kind = "item", section = "items", short = stat.label, item = id, tipItem = id,
                macro = "/use [@player,nocombat] item:" .. id, icon = h.itemIcon(id), expireAt = ends,
                count = h.itemCount(id), statKey = stat.key, choices = choices }
    if C_Item and C_Item.GetItemCooldown then
        local start, dur = h.call(C_Item.GetItemCooldown, id)
        if type(start) == "number" and type(dur) == "number" and dur > 1.5 then e.cooldown = { start, dur } end
    end
    out[#out + 1] = e
end

local function scrolls(state, out, mine)
    local c = cfg()
    local picks = type(c.stats) == "table" and c.stats[mine]
    if type(picks) ~= "table" then return end
    local separate, stronger, low = c.separate == true, c.stronger == true, c.statLowRank == true
    local warn = tonumber(c.statBelow) or 0
    local picker = BL.Reminder.Config().picker == true
    local pinned = type(c.statPick) == "table" and c.statPick[mine]
    local candle, kit
    local one
    local shared = picker and not separate and {} or nil
    for _, stat in ipairs(Data.STATS) do
        if picks[stat.key] == true and not Items.Locked(stat.key, mine) then
            local own, ownHealth = owned(stat.items), stat.health and owned(stat.health.items)
            if own or ownHealth then
                if candle == nil then candle, kit = campBonuses() end
                local choices = shared or (picker and {} or nil)
                local id, ends
                if own and not (stat.key == "stamina" and kit) then
                    local bonus
                    bonus, ends = toBeat(state, stat, stat.items, stat.family, warn, stronger, candle)
                    if bonus then id = pickItem(stat.items, bonus, low, choices) end
                end
                -- Stamina: a health elixir when no scroll fits (they stack).
                if not id and ownHealth then
                    local bonus, hEnds = toBeat(state, stat.health, stat.health.items, nil, warn, stronger)
                    if bonus then id, ends = pickItem(stat.health.items, bonus, low, choices), hEnds end
                end
                local pin = separate and type(pinned) == "table" and pinned["stat:" .. stat.key] or (not separate and pinned)
                if id and choices and type(pin) == "number" and choices[pin] then id = pin end
                if id then
                    if separate then
                        statEntry(out, stat, id, ends, "stat:" .. stat.key, choices)
                    elseif not one then
                        one = { stat = stat, id = id, ends = ends }
                        if not shared then break end
                    end
                end
            end
        end
    end
    if one then
        local id = one.id
        if shared and type(pinned) == "number" and shared[pinned] then id = pinned end
        statEntry(out, one.stat, id, one.ends, "scrollsAndElixirs", shared)
    end
end

-- ---------------------------------------------------------------------
-- The section
-- ---------------------------------------------------------------------

function Items.Collect(state, out, mine)
    if state.pvp then return end
    local c = cfg()
    if c.camp == true then camp(state, out) end
    if c.bag == true then sleepingBag(state, out) end
    if c.wellFed == true then wellFed(state, out) end
    if c.censer == true then censer(state, out) end
    scrolls(state, out, mine)
    if c.oil == true and BL.ReminderSelf then BL.ReminderSelf.Weapons(state, out, mine, false, true) end
end

local function anyStat()
    local c = cfg()
    local picks = type(c.stats) == "table" and c.stats[H().myClass()]
    if type(picks) ~= "table" then return false end
    for _, on in pairs(picks) do if on == true then return true end end
    return false
end

function Items.WantsBags()
    local c = cfg()
    return c.bag == true or c.wellFed == true or c.censer == true or c.oil == true or anyStat()
end

function Items.Watch(want)
    local c = cfg()
    want("BAG_UPDATE_COOLDOWN", anyStat())
    want("PLAYER_LOGOUT", c.bag == true and c.bagTimer ~= false)
end

-- Kept across a /reload, never across a login: where the sleep timer was.
BL.Reminder.handlers.items = function(event, isLogin, isReload)
    if event == "BAG_UPDATE_DELAYED" then
        bagsChanged()
    elseif event == "PLAYER_LOGOUT" then
        local store = H().charStore()
        if store then store.sleep = sleep and sleep.ends and { ends = sleep.ends, stacks = sleep.stacks } or nil end
    elseif event == "PLAYER_ENTERING_WORLD" then
        foods = nil
        local store = H().charStore()
        local saved = store and store.sleep
        if store then store.sleep = nil end
        if isReload == true and type(saved) == "table" and type(saved.ends) == "number" and saved.ends > GetTime() then
            local stacks = tonumber(saved.stacks) or 0
            sleep = { startedAt = saved.ends - math.max(1, Data.SLEEPING_BAG.stacks - stacks) * 60, stacks = stacks }
        elseif isLogin == true then
            sleep = nil
        end
    end
end
