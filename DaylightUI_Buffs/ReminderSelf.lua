-- Missing buffs, the Self Buffs section (Reminder.lua runs it), as
-- EllesmereUI's WoW Forever section works: your class's buffs (each ticked
-- one), the mage armors, and in a fight a hunter's target tracking. Out of a
-- fight and outside PvP only, except the tracking, which is in a fight only.
-- Absence only: a buff up counts however little time it has left.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local Self = {}
BL.ReminderSelf = Self

local Data = BL.ReminderData

local function H() return BL.Reminder.H end
local function cfg() return BL.Reminder.Section("self") end

-- The spell name's first word, as EllesmereUI labels its icons ("Inner").
local function shortLabel(name)
    if type(name) ~= "string" then return nil end
    return name:match("^(%S+)") or name
end
Self.ShortLabel = shortLabel

-- Your own copy of an aura: true, false (none or someone else's), nil when the
-- client won't say who cast it.
local function own(aura)
    local h = H()
    local from = h.plain(aura.isFromPlayerOrPlayerPet)
    if from == true then return true end
    local src = h.plain(aura.sourceUnit)
    if type(src) == "string" then return h.call(UnitIsUnit, src, "player") == true end
    if from == false then return false end
    return nil
end

-- Any rank in a list up on you: true, false, or nil when it can't tell.
local function ranksUp(ranks, mine)
    local h = H()
    local unknown = false
    for _, id in ipairs(ranks) do
        local aura = h.playerAura(id)
        if aura then
            if not mine then return true end
            local yours = own(aura)
            if yours then return true end
            if yours == nil then unknown = true end
        elseif aura == nil then
            unknown = true
        end
    end
    if unknown then return nil end
    return false
end

local function lineUp(lines, i, also, mine)
    local state = ranksUp(lines[i], mine)
    if state then return true end
    local extra = also and also[i]
    if extra then
        local more = ranksUp(extra, mine)
        if more then return true end
        if more == nil then state = nil end
    end
    return state
end

local function lineReadable(lines, i, also)
    local h = H()
    local extra = also and also[i]
    return h.ranksReadable(lines[i]) and not (extra and not h.ranksReadable(extra))
end

-- EllesmereUI's CollectLines: the line up (to remember), false while it's held
-- back with nothing to remember, or nil and the spell to cast (the highest
-- rank of the line last seen up, else of the strongest line known).
local function collectLines(state, lines, last, also, mine, anyCounts)
    local h = H()
    local first = lines[last] and last or nil
    local unknown = false
    if first then
        local up = lineUp(lines, first, also, mine)
        if up then return first end
        if up == nil then unknown = true end
    end
    local readable = not (state.secret and first and not lineReadable(lines, first, also))
    for i = 1, #lines do
        if i ~= first then
            local up = lineUp(lines, i, also, mine)
            if up then return i end
            if up == nil then unknown = true end
            if state.secret and not lineReadable(lines, i, also) then readable = false end
        end
    end
    -- Under the aura lock an unreadable rank would read absent: say nothing.
    if unknown or not readable then return false end
    if anyCounts then
        for i = 1, #lines do
            if lineUp(lines, i, also, false) then return false end
        end
    end
    local id = first and h.highest(lines[first])
    if not id then
        for i = #lines, 1, -1 do
            id = h.highest(lines[i])
            if id then break end
        end
    end
    if id then return nil, id end
    return false
end
Self.CollectLines = collectLines

local function spellEntry(out, key, id, label, extra)
    local h = H()
    local name = h.spellName(id)
    local e = {
        key = key, kind = "self", section = "self", spell = id, tipSpell = id,
        short = label or shortLabel(name) or tostring(id), icon = h.spellIcon(id),
        macro = name and ("/cast [nocombat,@player] " .. name) or nil,
    }
    for k, v in pairs(extra or {}) do e[k] = v end
    out[#out + 1] = e
    return e
end
Self.SpellEntry = spellEntry

-- A class buff is ticked: the player's pick, else its default.
function Self.ClassBuffOn(buff)
    local picks = cfg().picks
    local v = type(picks) == "table" and picks[buff.key]
    if v == nil then return buff.on == true end
    return v == true
end

local function classBuffs(state, out, mine)
    local h = H()
    local store = h.charStore()
    for _, buff in ipairs(Data.CLASS_BUFFS[mine] or {}) do
        if Self.ClassBuffOn(buff) then
            local last = store and store.last[buff.key]
            local up, id = collectLines(state, buff.lines, last, buff.also, buff.own or buff.ownMemory, buff.ownMemory)
            if id then
                local e = spellEntry(out, buff.key, id, buff.label)
                e.buff = buff
                if BL.ReminderPicker and BL.ReminderPicker.ClassBuff then BL.ReminderPicker.ClassBuff(e, buff) end
            end
            -- Only a buff with more than one line has a line to remember.
            if up and up ~= last and buff.lines[2] and store then store.last[buff.key] = up end
        end
    end
end

local function mageArmor(state, out)
    local h = H()
    local store = h.charStore()
    local last = store and store.mageArmor
    local up, id = collectLines(state, Data.MAGE_ARMORS, last)
    if id then spellEntry(out, "magearmor", id, L["Armor"]) end
    if up and up ~= last and store then store.mageArmor = up end
end

-- ---------------------------------------------------------------------
-- A hunter's target tracking (in a fight)
-- ---------------------------------------------------------------------

-- Which trackings you could switch on (by creature kind) and which kinds are
-- already matched or not known (a bit each): kept until the minimap's
-- trackers or your spells change.
local trackState
local function trackingState()
    if trackState then return trackState.needed, trackState.mask end
    local h = H()
    local needed, mask, uncertain = {}, 0, false
    local typeOf = {}
    for kind, id in ipairs(Data.TRACKING) do
        typeOf[id] = kind
        if not h.known(id) then mask = bit.bor(mask, 2 ^ (kind - 1)) end
    end
    local M = C_Minimap
    local n = M and h.call(M.GetNumTrackingTypes) or 0
    for i = 1, (type(n) == "number" and n or 0) do
        local ok, info = h.read(M.GetTrackingInfo, i)
        if ok and type(info) == "table" and not DUI.IsSecret(info) and info.type == "spell" then
            if DUI.IsSecret(info.spellID) then
                if DUI.IsSecret(info.active) or info.active then uncertain = true end
            else
                local kind = typeOf[info.spellID]
                if kind then
                    if DUI.IsSecret(info.active) then uncertain = true
                    elseif info.active then mask = bit.bor(mask, 2 ^ (kind - 1))
                    elseif h.known(info.spellID) then needed[kind] = info.spellID end
                end
            end
        end
    end
    trackState = { needed = needed, mask = uncertain and 127 or mask }
    return trackState.needed, trackState.mask
end
function Self.ForgetTracking() trackState = nil end

-- The tracking that matches a hostile target's kind. A kind the client keeps
-- secret still shows: the row's icon picks its column itself (secretType).
local function hunterTracking(out)
    local h = H()
    local function plainTrue(fn, ...)
        local ok, v = h.read(fn, ...)
        if not ok or DUI.IsSecret(v) then return nil end
        return v
    end
    if plainTrue(UnitExists, "target") ~= true then return end
    if plainTrue(UnitCanAttack, "player", "target") ~= true then return end
    if plainTrue(UnitIsDeadOrGhost, "target") ~= false then return end
    local ok, _, kind = h.read(UnitCreatureType, "target")
    if not ok then return end
    local secret = DUI.IsSecret(kind)
    if not secret and (type(kind) ~= "number" or kind < 1 or kind > 7) then return end
    local needed, mask = trackingState()
    local id
    if not secret then
        id = needed[kind]
        if not id then return end
    end
    out[#out + 1] = {
        key = "huntertracking", kind = "track", section = "self", spell = id, tipSpell = id,
        icon = id and h.spellIcon(id) or nil, short = nil, noGlow = true,
        secretType = secret and kind or nil, trackMask = secret and mask or 0,
    }
end

-- Find Treasure on, and any other spell tracker on (a class's), from one
-- pass over the minimap's trackers kept until they change.
local minimap
local function minimapState()
    if minimap then return minimap.treasure, minimap.class end
    local h = H()
    local treasure, class = false, false
    local M = C_Minimap
    local n = M and h.call(M.GetNumTrackingTypes) or 0
    for i = 1, (type(n) == "number" and n or 0) do
        local ok, info = h.read(M.GetTrackingInfo, i)
        info = ok and type(info) == "table" and BL.PlainTable(info) or nil
        if info and h.plain(info.active) == true and h.plain(info.type) == "spell" then
            if h.plain(info.spellID) == Data.FIND_TREASURE then treasure = true else class = true end
        end
    end
    minimap = { treasure = treasure, class = class }
    return treasure, class
end

-- Demonic Sacrifice: the click summons the chosen demon (Auto: the one out,
-- else the Imp), then sacrifices it.
local function sacrifice(state, out)
    local h = H()
    if not h.known(Data.DEMONIC_SACRIFICE) then return end
    local chosen = cfg().demon
    local wanted = {}
    for _, d in ipairs(Data.SACRIFICE_DEMONS) do
        if chosen == nil or chosen == "auto" or chosen == d.key then wanted[#wanted + 1] = d.buff end
    end
    if state.secret and not h.ranksReadable(wanted) then return end
    for _, id in ipairs(wanted) do
        local a = h.playerAura(id)
        if a == nil or a then return end
    end
    local family
    if h.call(UnitExists, "pet") == true and h.call(UnitIsDead, "pet") ~= true then
        local ok, _, id = h.read(UnitCreatureFamily, "pet")
        -- Which demon is out is unknown: nothing is offered (a summon would replace it).
        if not ok or DUI.IsSecret(id) then return end
        family = id
    end
    local target = Data.SACRIFICE_DEMONS[1]
    for _, d in ipairs(Data.SACRIFICE_DEMONS) do
        if (chosen == d.key) or ((chosen == nil or chosen == "auto") and d.family == family) then target = d break end
    end
    if family == target.family then
        spellEntry(out, "demonicsacrifice", Data.DEMONIC_SACRIFICE)
    elseif h.known(target.summon) then
        spellEntry(out, "demonicsacrifice", target.summon)
    end
end

-- Gathering: no tracker up and you know one; the click casts the first known.
-- A class's own tracker on hides it (Ignore if class tracking is on).
local function gather(state, out)
    local h = H()
    local list = Data.GATHER_TRACKING
    if state.secret and not h.ranksReadable(list) then return end
    for _, id in ipairs(list) do
        local a = h.playerAura(id)
        if a == nil or a then return end
    end
    local id
    for _, x in ipairs(list) do
        if h.known(x) then id = x break end
    end
    if not id then return end
    if cfg().gatherClassTrack ~= false then
        local _, class = minimapState()
        if class then return end
    end
    spellEntry(out, "gather", id)
end

local function treasure(out)
    local h = H()
    if not h.known(Data.FIND_TREASURE) then return end
    if minimapState() then return end
    spellEntry(out, "treasure", Data.FIND_TREASURE)
end

local function trackingWanted(mine)
    return mine == "HUNTER" and cfg().hunterTracking == true
end

-- ---------------------------------------------------------------------
-- Weapons: an imbue or poison (this section) and a stone or oil
-- (Consumables), read apart per hand
-- ---------------------------------------------------------------------

local HANDS = {
    { slot = 16, ws = "MainHand", imbue = "mhImbue", temp = "mhTemp", key = "weapon_mh" },
    { slot = 17, ws = "OffHand", imbue = "ohImbue", temp = "ohTemp", key = "weapon_oh" },
}

-- What's in a hand: BLADED, BLUNT or NEUTRAL; nil for no weapon, a shield or
-- off-hand item, a ranged weapon or a fishing pole.
local function category(slot)
    local h = H()
    local id = h.call(GetInventoryItemID, "player", slot)
    if type(id) ~= "number" or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, _, _, _, equipLoc, _, class, sub = h.read(C_Item.GetItemInfoInstant, id)
    if not ok then return nil end
    equipLoc, class, sub = h.plain(equipLoc), h.plain(class), h.plain(sub)
    local weapon = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    if class ~= weapon then return nil end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then return nil end
    if sub == Data.FISHING_POLE or Data.RANGED[sub] then return nil end
    if Data.BLADED[sub] then return "BLADED" end
    if Data.BLUNT[sub] then return "BLUNT" end
    return "NEUTRAL"
end

-- Seconds left on a hand's imbue and on its temporary enchant (nil for none);
-- false when the client won't say.
local function enchants(ws)
    local W = DUI.Weapons
    local slot = Enum and Enum.WeaponSlot and Enum.WeaponSlot[ws]
    if not (W and slot) then return false end
    local list, refused = W.Read(slot)
    if refused then return false end
    local T = Enum.ItemEnchantType or {}
    local imbue, temp
    for _, e in ipairs(list) do
        local left = (e.msLeft or 0) / 1000
        if left > 0 then
            if e.kind == (T.Imbue or 3) then imbue = left
            elseif e.kind == (T.Temporary or 2) then temp = left end
        end
    end
    return true, imbue, temp
end

-- What a buff offers now: its highest known spell, an item you carry (highest,
-- or lowest with Rank to use), else a warlock's Create spell.
local function available(buff, low)
    local h = H()
    if buff.spells then return h.highest(buff.spells) end
    local items = buff.items
    local first, last, step = #items, 1, -1
    if low then first, last, step = 1, #items, 1 end
    for i = first, last, step do
        if h.itemCount(items[i]) > 0 then return nil, items[i] end
    end
    if buff.create then return nil, nil, h.highest(buff.create) end
end

-- A hand's pick: "off" none, a named buff, or Auto (nil): the first in the
-- table that fits your class and weapon and that you have; a warlock's Create
-- spell only when no stone of any kind is at hand.
local function pick(choice, isImbue, class, wcat, low)
    if choice == "off" then return nil end
    local auto = choice == nil or choice == "auto"
    local creatable, createID
    for _, buff in ipairs(Data.WEAPON_BUFFS) do
        if (auto or choice == buff.key) and (buff.imbue == true) == isImbue
            and (not buff.class or buff.class == class) and (not buff.weapon or buff.weapon == wcat) then
            local spell, item, create = available(buff, low)
            if spell or item or not auto then return buff, spell or create, item end
            if create and not creatable then creatable, createID = buff, create end
        end
    end
    if creatable then return creatable, createID end
end

-- Missing, or less than the Show Below minutes left (the next look is armed
-- at the crossing).
local function needs(state, left, warn)
    if not left then return true end
    if warn and left < warn then return true end
    local at = state.now + left - (warn or 0)
    if not state.nextLook or at < state.nextLook then state.nextLook = at end
    return false
end

local function weaponEntry(out, hand, label, key, section, buff, spell, item, hideNoItem, left, state)
    local h = H()
    if buff.spells and not spell then return end
    if buff.items and not item and not spell and hideNoItem then return end
    local e = { key = key, kind = "weapon", section = section, short = label, hand = hand.slot }
    if spell then
        local name = h.spellName(spell)
        e.spell, e.tipSpell, e.icon = spell, spell, h.spellIcon(spell)
        e.macro = name and ("/cast [nocombat] " .. name) or nil
    else
        local shown = item or buff.items[#buff.items]
        e.icon, e.tipItem = h.itemIcon(shown), shown
        e.count = item and h.itemCount(item) or 0
        if item then
            e.item, e.itemName = item, h.itemName(item)
            e.macro = "/use [nocombat] item:" .. item .. "\n/use " .. hand.slot
        end
    end
    if left then e.expireAt = state.now + left end
    out[#out + 1] = e
end

-- wantImbue: this section's poisons and imbues; wantTemp: Consumables' stones
-- and oils.
function Self.Weapons(state, out, class, wantImbue, wantTemp)
    if not (wantImbue or wantTemp) then return end
    local c = cfg()
    local all = BL.Reminder.Config()
    local hands = type(all.hands) == "table" and all.hands[class] or nil
    local low, hideNoItem = c.lowRank == true, c.hideNoItem ~= false
    local below = tonumber(c.weaponBelow) or 1
    local warn = below > 0 and below * 60 or nil
    local mh, oh = L["Main"], L["Off"]
    if mh == oh then mh, oh = L["Main Hand"], L["Off Hand"] end
    for i, hand in ipairs(HANDS) do
        local wcat = category(hand.slot)
        local ok, imbueLeft, tempLeft
        if wcat then ok, imbueLeft, tempLeft = enchants(hand.ws) end
        if ok then
            local label = i == 1 and mh or oh
            if wantImbue then
                local buff, spell, item = pick(hands and hands[hand.imbue], true, class, wcat, low)
                if buff and needs(state, imbueLeft, warn) then
                    weaponEntry(out, hand, label, hand.key .. "_imbue", "self", buff, spell, item, hideNoItem, imbueLeft, state)
                end
            end
            if wantTemp then
                local buff, spell, item = pick(hands and hands[hand.temp], false, class, wcat, low)
                if buff and needs(state, tempLeft, warn) then
                    weaponEntry(out, hand, label, hand.key .. "_temp", "items", buff, spell, item, hideNoItem, tempLeft, state)
                end
            end
        end
    end
end

-- The class has an imbue of its own (rogue, shaman, warlock).
function Self.HasImbue(class)
    for _, b in ipairs(Data.WEAPON_BUFFS) do
        if b.imbue and b.class == class then return true end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Spells the player typed in, and groups of them
-- ---------------------------------------------------------------------

-- Every id that counts for a spell: itself, the raid buff family that lists
-- it (a custom Fortitude counts Prayer of Fortitude), and its class buff or
-- armor line. Other ranks of its name are found by name.
local rankCache = {}
local function ranksOf(id)
    local list = rankCache[id]
    if list then return list end
    list, rankCache[id] = { id }, nil
    local seen = { [id] = true }
    local function add(ids)
        for _, x in ipairs(ids or {}) do
            if not seen[x] then seen[x] = true; list[#list + 1] = x end
        end
    end
    local function has(ids) for _, x in ipairs(ids or {}) do if x == id then return true end end end
    for _, fam in ipairs(Data.FAMILIES) do if has(fam.ids) then add(fam.ids) end end
    for _, buffs in pairs(Data.CLASS_BUFFS) do
        for _, b in ipairs(buffs) do
            for i, line in ipairs(b.lines) do
                if has(line) or has(b.also and b.also[i]) then add(line); add(b.also and b.also[i]) end
            end
        end
    end
    for _, line in ipairs(Data.MAGE_ARMORS) do if has(line) then add(line) end end
    rankCache[id] = list
    return list
end
Self.RanksOf = ranksOf

-- Any rank of it up on you: true, false, or nil when the client won't say.
local function anyUp(ids)
    local h = H()
    local unknown, names = false, {}
    for _, id in ipairs(ids) do
        local a = h.playerAura(id)
        if a then return true end
        if a == nil then unknown = true end
        local n = h.spellName(id)
        if n then names[n] = true end
    end
    for n in pairs(names) do
        local a = h.auraByName("player", n)
        if a then return true end
        if a == nil then unknown = true end
    end
    if unknown then return nil end
    return false
end

-- The highest rank you know: one of the listed ids, else the one the client
-- gives for its name.
local function knownTop(ids)
    local h = H()
    local id = h.highest(ids)
    if id then return id end
    local name = h.spellName(ids[1])
    if name and C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = h.read(C_Spell.GetSpellInfo, name)
        info = ok and type(info) == "table" and BL.PlainTable(info) or nil
        if info and type(info.spellID) == "number" and h.known(info.spellID) then return info.spellID end
    end
    return nil
end

-- The ticked class buffs' ids and names: a custom spell or group made only of
-- them stands down while the class buff covers it.
local function covered(mine)
    local h = H()
    local ids, names = {}, {}
    for _, buff in ipairs(Data.CLASS_BUFFS[mine] or {}) do
        if Self.ClassBuffOn(buff) then
            for _, lines in ipairs({ buff.lines, buff.also or {} }) do
                for _, line in ipairs(lines) do
                    for _, id in ipairs(line) do
                        ids[id] = true
                        local n = h.spellName(id)
                        if n then names[n] = true end
                    end
                end
            end
        end
    end
    if mine == "MAGE" and cfg().mageArmor == true then
        for _, line in ipairs(Data.MAGE_ARMORS) do
            for _, id in ipairs(line) do
                ids[id] = true
                local n = h.spellName(id)
                if n then names[n] = true end
            end
        end
    end
    return ids, names
end

local function isCovered(id, ids, names)
    return ids[id] or names[H().spellName(id) or false] or false
end

local function castEntry(out, key, id, label, top)
    local h = H()
    local shown = top or id
    local name = h.spellName(shown)
    local e = {
        key = key, kind = "self", section = "self", spell = top, tipSpell = shown,
        short = label or shortLabel(name) or tostring(id), icon = h.spellIcon(shown),
        macro = top and name and ("/cast [nocombat,@player] " .. name) or nil,
    }
    out[#out + 1] = e
    return e
end

local function customs(state, out, mine)
    local h = H()
    local c = cfg()
    local custom = type(c.custom) == "table" and c.custom or {}
    local ids, classes = type(custom.ids) == "table" and custom.ids or {}, type(custom.classes) == "table" and custom.classes or {}
    if #ids == 0 then return end
    local cIds, cNames = covered(mine)
    for _, id in ipairs(ids) do
        local off = type(classes[id]) == "table" and classes[id][mine] == false
        if not off and not isCovered(id, cIds, cNames) and h.spellName(id) then
            local ranks = ranksOf(id)
            if not (state.secret and not h.ranksReadable(ranks)) and anyUp(ranks) == false then
                castEntry(out, "custom:" .. id, id, nil, knownTop(ranks))
            end
        end
    end
end

local function groups(state, out, mine)
    local h = H()
    local list = cfg().groups
    if type(list) ~= "table" then return end
    local cIds, cNames = covered(mine)
    for i, group in ipairs(list) do
        local members = type(group) == "table" and type(group.ids) == "table" and group.ids or {}
        local allCovered = #members > 0
        for _, id in ipairs(members) do
            if not isCovered(id, cIds, cNames) then allCovered = false break end
        end
        if not allCovered then
            local icon, up, readable = nil, false, true
            for _, id in ipairs(members) do
                if h.spellName(id) then
                    local ranks = ranksOf(id)
                    local top = knownTop(ranks)
                    if top and (not icon or (BL.Reminder.Config().picker == true and id == group.castSpellID)) then icon = top end
                    local on = anyUp(ranks)
                    if on then up = true break end
                    if on == nil or (state.secret and not h.ranksReadable(ranks)) then readable = false end
                end
            end
            if icon and readable and not up then
                local e = castEntry(out, "g" .. i, icon, type(group.name) == "string" and group.name or nil, icon)
                e.group = i
                if BL.ReminderPicker and BL.ReminderPicker.Group then BL.ReminderPicker.Group(e, group) end
            end
        end
    end
end

-- Writes a fresh copy of a setting's table back (saved settings never share
-- a table with the defaults).
local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
local function save(path, v) DUI:Set(BL.MODULE, "settings.reminder.self." .. path, v) end

-- A typed spell id, if the client knows it: true when added.
local function parseId(text)
    if type(text) == "number" then text = tostring(text) end
    if type(text) ~= "string" or not text:match("^%s*%d+%s*$") then return nil end
    local id = tonumber(text)
    if not H().spellName(id) then return nil end
    return id
end

function Self.AddCustom(text)
    local id = parseId(text)
    if not id then return false end
    local custom = copy(cfg().custom) or {}
    custom.ids = custom.ids or {}
    for _, x in ipairs(custom.ids) do if x == id then return false end end
    custom.ids[#custom.ids + 1] = id
    save("custom", custom)
    return true
end

function Self.RemoveCustom(id)
    local custom = copy(cfg().custom) or {}
    for i, x in ipairs(custom.ids or {}) do
        if x == id then
            table.remove(custom.ids, i)
            if custom.classes then custom.classes[id] = nil end
            save("custom", custom)
            return true
        end
    end
    return false
end

-- A custom spell shown for a class or not (all ticked to start).
function Self.SetCustomClass(id, class, on)
    local custom = copy(cfg().custom) or {}
    custom.classes = custom.classes or {}
    custom.classes[id] = custom.classes[id] or {}
    if on then custom.classes[id][class] = nil else custom.classes[id][class] = false end
    if not next(custom.classes[id]) then custom.classes[id] = nil end
    save("custom", custom)
end

function Self.NewGroup(name)
    if type(name) ~= "string" or name:match("^%s*$") then return false end
    local list = copy(cfg().groups) or {}
    list[#list + 1] = { name = name, ids = {} }
    save("groups", list)
    return #list
end

function Self.RenameGroup(i, name)
    local list = copy(cfg().groups) or {}
    if not list[i] or type(name) ~= "string" or name:match("^%s*$") then return false end
    list[i].name = name
    save("groups", list)
    return true
end

function Self.RemoveGroup(i)
    local list = copy(cfg().groups) or {}
    if not list[i] then return false end
    table.remove(list, i)
    save("groups", list)
    return true
end

function Self.AddToGroup(i, text)
    local id = parseId(text)
    local list = copy(cfg().groups) or {}
    if not id or not list[i] then return false end
    list[i].ids = list[i].ids or {}
    for _, x in ipairs(list[i].ids) do if x == id then return false end end
    list[i].ids[#list[i].ids + 1] = id
    save("groups", list)
    return true
end

-- Removing a member also drops its picked spell and pinned rank.
function Self.RemoveFromGroup(i, id)
    local list = copy(cfg().groups) or {}
    local g = list[i]
    if not g then return false end
    for k, x in ipairs(g.ids or {}) do
        if x == id then
            table.remove(g.ids, k)
            if g.castSpellID == id then g.castSpellID = nil end
            if g.castRanks then g.castRanks[id] = nil end
            save("groups", list)
            return true
        end
    end
    return false
end

-- ---------------------------------------------------------------------
-- The section
-- ---------------------------------------------------------------------

function Self.Collect(state, out, mine)
    if state.pvp then return end
    local c = cfg()
    if mine == "MAGE" then
        if c.mageArmor == true then mageArmor(state, out) end
    else
        classBuffs(state, out, mine)
    end
    if mine == "WARLOCK" and c.sacrifice == true then sacrifice(state, out) end
    if c.imbue == true and Self.HasImbue(mine) then Self.Weapons(state, out, mine, true, false) end
    if c.gather == true then gather(state, out) end
    if c.treasure == true then treasure(out) end
    customs(state, out, mine)
    groups(state, out, mine)
end

-- Weapons are watched while a weapon reminder is on.
function Self.WantsWeapons()
    local h = H()
    local items = BL.Reminder.Section("items")
    return (cfg().imbue == true and Self.HasImbue(h.myClass())) or items.oil == true
end

function Self.WantsBags() return Self.WantsWeapons() end

-- In a fight: only a hunter's target tracking.
function Self.Fight(state, out, mine)
    if trackingWanted(mine) then hunterTracking(out) end
end

-- The events the section needs now (Reminder.Watch).
function Self.Watch(want)
    local h = H()
    local tracking = trackingWanted(h.myClass())
    want("PLAYER_TARGET_CHANGED", tracking)
    want("UNIT_FLAGS", tracking, "target")
    want("UNIT_FACTION", tracking, "target")
    local c = cfg()
    want("MINIMAP_UPDATE_TRACKING", tracking or c.gather == true or c.treasure == true)
    want("UNIT_PET", h.myClass() == "WARLOCK" and c.sacrifice == true, "player")
end

BL.Reminder.handlers.self = function(event)
    if event == "MINIMAP_UPDATE_TRACKING" or event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        trackState, minimap = nil, nil
    end
end
