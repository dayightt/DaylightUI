-- Missing buffs: what a row of tiles above you shows (ReminderRow.lua draws
-- it). In a group: the raid buffs you give, with how many lack them (a click
-- casts yours), and the ones others give that you lack. Also your class's own
-- buff, weapon oils, poisons and imbues you carry, and the consumables the
-- player switched on. Hidden while resting, dead, traveling, and solo.
--
-- Buffs are found by the client's own name for their ids, so any rank,
-- another caster's copy and any language count. Auras are secret in a fight
-- and under the client's restrictions (boss fights, keystones, PvP matches):
-- in a fight nothing is read and the row holds as it was at the pull; under a
-- restriction out of combat a buff is read only when the client says its aura
-- isn't secret, and a buff that can't be read never shows as missing.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local Reminder = {}
BL.Reminder = Reminder

local Data = BL.ReminderData
Reminder.FAMILIES = Data.FAMILIES
Reminder.byKey = Data.byKey
Reminder.SETTLE = 3      -- seconds after a loading screen before looking
Reminder.hidden = {}     -- [key] = true: middle-clicked away until the next loading screen

local function cfg()
    local db = BL.DB
    local s = db and db.settings
    return type(s) == "table" and type(s.reminder) == "table" and s.reminder or nil
end
Reminder.Config = cfg

local function opt(key)
    local c = cfg()
    return c ~= nil and c[key] == true
end

function Reminder.Enabled() return opt("enabled") end

-- Seconds left under which a buff counts as running low.
function Reminder.LowSeconds()
    local c = cfg()
    local m = c and tonumber(c.lowMinutes)
    return (m and m >= 0 and m or 5) * 60
end

local function plain(v) return BL.Plain(v) end

-- A read the client may refuse on purpose (a secret or restricted answer):
-- the file's one bare pcall. Nothing here that acts goes through it.
local function read(fn, ...) return pcall(fn, ...) end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = read(fn, ...)
    if not ok then return nil end
    return plain(a), plain(b)
end

-- ---------------------------------------------------------------------
-- When it's a fight, when the row hides
-- ---------------------------------------------------------------------

-- A fight: the combat flag the fade sets first (PLAYER_REGEN_DISABLED comes
-- before the lockdown), the lockdown, or a boss encounter (its auras turn
-- secret before any lockdown).
function Reminder.Fighting()
    return (DUI.Fade and DUI.Fade.fighting) == true or InCombatLockdown() or Reminder.encounter == true
end

-- Auras can't be read freely right now: the client's restrictions.
function Reminder.AurasSecret()
    if DUI.Restricted() then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = read(C_Secrets.ShouldAurasBeSecret)
        if not ok or plain(secret) ~= false then return true end
    end
    return false
end

-- Resting, dead, on a flight path, in a vehicle, flying: nothing to do about buffs.
function Reminder.Away()
    if call(IsResting) == true then return true end
    if call(UnitIsDeadOrGhost, "player") == true then return true end
    if call(UnitOnTaxi, "player") == true then return true end
    if call(UnitInVehicle, "player") == true then return true end
    if call(IsFlying) == true then return true end
    return false
end

-- ---------------------------------------------------------------------
-- Reading buffs
-- ---------------------------------------------------------------------

-- The client's names for a list of spell ids, once each, cached per list.
local nameCache = setmetatable({}, { __mode = "k" })
local function namesOf(ids)
    local got = nameCache[ids]
    if got then return got end
    local out, seen = {}, {}
    for _, id in ipairs(ids) do
        local n = C_Spell and call(C_Spell.GetSpellName, id)
        if type(n) == "string" and n ~= "" and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    if #out == 0 then return out end -- not cached: the client may not know them yet
    nameCache[ids] = out
    return out
end
Reminder.NamesOf = namesOf

-- Under a restriction a buff is readable only when the client says every one
-- of its ids is plain. Asked once per refresh (state.readable).
local function readable(state, ids)
    if not state.secret then return true end
    local r = state.readable[ids]
    if r ~= nil then return r end
    r = true
    local ask = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if type(ask) ~= "function" then r = false end
    for _, id in ipairs(ids) do
        if not r then break end
        local ok, secret = read(ask, id)
        if not ok or plain(secret) ~= false then r = false end
    end
    state.readable[ids] = r
    return r
end

-- A unit wearing any of names: true (and when it ends, 0 for never), false,
-- or nil when the client won't say.
local function wearing(unit, names, filter)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if type(get) ~= "function" or #names == 0 then return nil end
    for _, n in ipairs(names) do
        local ok, a = read(get, unit, n, filter or "HELPFUL")
        if not ok then return nil end
        if type(a) ~= "nil" then
            a = BL.PlainTable(a)
            if not a then return nil end
            local ends, long = plain(a.expirationTime), plain(a.duration)
            return true, type(ends) == "number" and ends or 0, plain(a.applications), type(long) == "number" and long or 0
        end
    end
    return false
end

-- true, false or nil, counting a buff that runs out within the low window as
-- missing. The end time of a low one comes second; a buff still fine arms the
-- next look at its crossing (state.nextLook).
local function present(state, unit, names, filter)
    local on, ends, stacks, long = wearing(unit, names, filter)
    if on ~= true then return on end
    if ends and ends > 0 then
        -- A short buff (a 2 minute shout) runs low in its last quarter, not
        -- for its whole life.
        local low = state.low
        if long and long > 0 then low = math.min(low, long / 4) end
        local left = ends - state.now
        if left <= low then return false, ends, stacks end
        local at = ends - low
        if not state.nextLook or at < state.nextLook then state.nextLook = at end
    end
    return true, nil, stacks
end

local function known(id)
    return C_SpellBook and call(C_SpellBook.IsSpellKnown, id) == true
end

-- The highest rank you know in a list (lowest first), or nil.
local function highest(ids)
    if not ids then return nil end
    for i = #ids, 1, -1 do
        if known(ids[i]) then return ids[i] end
    end
    return nil
end
Reminder.Highest = highest

-- Usable now, or only short of mana (a reagent missing says no).
local function usable(id)
    if not (C_Spell and type(C_Spell.IsSpellUsable) == "function") then return true end
    local can, noPower = call(C_Spell.IsSpellUsable, id)
    return can == true or noPower == true
end

local function spellName(id)
    return C_Spell and call(C_Spell.GetSpellName, id) or nil
end

local function spellIcon(id, fallback)
    local tex = C_Spell and call(C_Spell.GetSpellTexture, id)
    return tex or fallback
end

local function itemCount(id)
    return C_Item and call(C_Item.GetItemCount, id) or 0
end

local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then
        local tex = call(C_Item.GetItemIconByID, id)
        if tex then return tex end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, icon = read(C_Item.GetItemInfoInstant, id)
        if ok and plain(icon) then return plain(icon) end
    end
    return 134400
end

local function itemName(id)
    if C_Item and C_Item.GetItemNameByID then
        local n = call(C_Item.GetItemNameByID, id)
        if type(n) == "string" then return n end
    end
    return nil
end

-- ---------------------------------------------------------------------
-- The group: read the way EllesmereUI's Raid Buffs read on WoW Forever
-- ---------------------------------------------------------------------

-- A family's names: its first single and group ranks name every rank, the
-- group version and other casters' copies. Kept once every name has loaded.
local famNames = setmetatable({}, { __mode = "k" })
local function familyNames(fam)
    local list = famNames[fam]
    if list and list.done then return list end
    list = {}
    local n = 0
    for _, id in ipairs(fam.names) do
        local name = C_Spell and call(C_Spell.GetSpellName, id)
        if type(name) == "string" and name ~= "" then n = n + 1; list[n] = name end
    end
    list.done = (n == #fam.names) or nil
    famNames[fam] = list
    return list
end

-- The aura of a family on a unit, false while none is up, nil while the
-- client won't say (or a name hasn't loaded: the buff could be up under it).
function Reminder.FamilyAura(unit, fam)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if type(get) ~= "function" then return nil end
    local names = familyNames(fam)
    for _, n in ipairs(names) do
        local ok, aura = read(get, unit, n, "HELPFUL")
        if not ok or DUI.IsSecret(aura) then return nil end
        if aura then return aura end
    end
    if not names.done then return nil end
    return false
end

local function unitHas(unit, fam)
    local aura = Reminder.FamilyAura(unit, fam)
    if not aura then return aura end
    return true
end

-- Every rank plain right now (asked only under a restriction).
local function ranksReadable(list)
    local ask = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if type(ask) ~= "function" then return true end
    for _, id in ipairs(list or {}) do
        local ok, secret = read(ask, id)
        if not ok or DUI.IsSecret(secret) or secret ~= false then return false end
    end
    return true
end

local function famReadable(state, fam)
    if not state.secret then return true end
    local r = state.readable[fam]
    if r == nil then
        r = ranksReadable(fam.single) and ranksReadable(fam.group)
        state.readable[fam] = r
    end
    return r
end

-- Connected, alive, a player.
local function unitOk(u)
    return call(UnitExists, u) == true and call(UnitIsConnected, u) ~= false
        and call(UnitIsDeadOrGhost, u) ~= true and call(UnitIsPlayer, u) == true
end

-- In range when the client says so plainly, else in sight (UnitInRange is
-- secret on this client); a secret answer counts as near.
local function inRange(u)
    if u == "player" or call(UnitIsUnit, u, "player") == true then return true end
    if type(UnitInRange) == "function" then
        local ok, near, checked = read(UnitInRange, u)
        if ok and not DUI.IsSecret(near) and not DUI.IsSecret(checked) and checked then return near == true end
    end
    if type(UnitIsVisible) ~= "function" then return true end
    local ok, vis = read(UnitIsVisible, u)
    if not ok or DUI.IsSecret(vis) then return true end
    return vis == true
end

-- Whether a unit wants the buff: mana buffs for mana users, Battle Shout for
-- melee (a healing hybrid doesn't swing).
local HEAL_HYBRID = { PALADIN = true, DRUID = true, SHAMAN = true }
local function benefits(u, fam)
    if not fam.benefit then return true end
    local _, class = UnitClass(u)
    class = plain(class)
    if type(class) ~= "string" then return false end
    if fam.benefit == "mana" then return Data.MANA_USERS[class] == true end
    if not Data.MELEE[class] then return false end
    local role = UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned(u))
    return not (role == "HEALER" and HEAL_HYBRID[class])
end

-- The group's tokens: you and party1-4, or raid1-40.
local function tokens()
    local out = {}
    if IsInRaid() then
        for i = 1, 40 do out[#out + 1] = "raid" .. i end
    else
        out[1] = "player"
        for i = 1, 4 do out[#out + 1] = "party" .. i end
    end
    return out
end

local function isMe(u) return u == "player" or call(UnitIsUnit, u, "player") == true end

-- The classes of the others here, in range: { [CLASS] = how many }.
local function groupClasses()
    local set = {}
    for _, u in ipairs(tokens()) do
        if not isMe(u) and unitOk(u) and inRange(u) then
            local _, class = UnitClass(u)
            class = plain(class)
            if type(class) == "string" then set[class] = (set[class] or 0) + 1 end
        end
    end
    return set
end

-- In-range members who want it and have it, against all of them, the first
-- one lacking it and every one lacking it. A member who can't be read counts
-- on neither side.
local function coverage(fam)
    local have, total, first, lacking = 0, 0, nil, {}
    for _, u in ipairs(tokens()) do
        if unitOk(u) and inRange(u) and benefits(u, fam) then
            local has = unitHas(u, fam)
            if has ~= nil then
                total = total + 1
                if has then
                    have = have + 1
                else
                    first = first or u
                    lacking[#lacking + 1] = u
                end
            end
        end
    end
    return have, total, first, lacking
end

-- You can give it: your class and a rank known.
local function iCast(fam, mine)
    return not fam.blessing and fam.class == mine and (highest(fam.single) or highest(fam.group)) ~= nil
end
Reminder.ICast = iCast

-- The click's cast: the group version on you while you know it and could
-- cast it now (its reagent in the bags; mana aside), else the highest rank on
-- the one lacking it (you, for a shout).
local function pickCast(fam, first)
    local g = highest(fam.group)
    if g and C_Spell and type(C_Spell.IsSpellUsable) == "function" then
        local ok, can, noMana = read(C_Spell.IsSpellUsable, g)
        if ok and not DUI.IsSecret(can) and not DUI.IsSecret(noMana) and (can or noMana) then return g, "player" end
    end
    return highest(fam.single), (not fam.self and first) or "player"
end

-- Someone other than you wears it.
local function worn(fam)
    for _, u in ipairs(tokens()) do
        if not isMe(u) and unitOk(u) and unitHas(u, fam) == true then return true end
    end
    return false
end

local function getEntry(fam)
    return { key = fam.key, kind = "get", family = fam, short = fam.short, icon = spellIcon(fam.names[1], fam.icon) }
end

-- Raid buffs only ask whether a buff is there (no running low): a 2 minute
-- shout would otherwise always read as running out.
local function groupEntries(state, out, mine, grouped)
    local c = cfg()
    local giveOn, getOn = c.give ~= false, c.get ~= false
    local classes = grouped and groupClasses() or {}
    state.giving = false
    for _, fam in ipairs(Data.FAMILIES) do
        if not fam.blessing then
            local mineToGive = iCast(fam, mine)
            if mineToGive then state.giving = true end
            if mineToGive then
                if giveOn and famReadable(state, fam) and (not fam.seen or worn(fam)) then
                    local missing, have, total, first, lacking
                    if grouped then
                        have, total, first, lacking = coverage(fam)
                        missing = total > 0 and have < total
                    else
                        missing = unitHas("player", fam) == false
                    end
                    if missing then
                        local spell, unit = pickCast(fam, first)
                        if spell then
                            out[#out + 1] = { key = fam.key, kind = "give", family = fam, have = have, total = total,
                                              unit = unit, spell = spell, lacking = lacking,
                                              short = fam.short, icon = spellIcon(fam.names[1], fam.icon) }
                        end
                    end
                end
            elseif getOn and grouped and not fam.talent and (classes[fam.class] or 0) > 0
                    and benefits("player", fam) and famReadable(state, fam) and (not fam.seen or worn(fam)) then
                if unitHas("player", fam) == false then out[#out + 1] = getEntry(fam) end
            end
        end
    end
    -- Blessings: one per paladin here, the ones that suit you first.
    local paladins = classes.PALADIN or 0
    if not getOn or paladins == 0 then return end
    local on, had, count = {}, 0, 0
    for _, fam in ipairs(Data.FAMILIES) do
        if fam.blessing then
            count = count + 1
            local has = nil
            if famReadable(state, fam) then has = unitHas("player", fam) end
            on[fam.key] = has
            if has ~= false then had = had + 1 end
        end
    end
    local need = math.min(paladins, count) - had
    local tank = UnitGroupRolesAssigned and plain(UnitGroupRolesAssigned("player")) == "TANK"
    for _, key in ipairs(Data.BLESSING_ORDER[mine] or Data.BLESSING_ORDER.default) do
        if need <= 0 then break end
        if on[key] == false and not (tank and key == "salvation") then
            out[#out + 1] = getEntry(Data.byKey[key])
            need = need - 1
        end
    end
end

-- ---------------------------------------------------------------------
-- Your own buff, weapons, consumables
-- ---------------------------------------------------------------------

local function charStore()
    local DB = DUI.DB
    local ch = DB and DB.Character and DB.Character()
    if type(ch) ~= "table" then return nil end
    ch.buffReminder = type(ch.buffReminder) == "table" and ch.buffReminder or {}
    local s = ch.buffReminder
    s.last = type(s.last) == "table" and s.last or {}
    return s
end
Reminder.CharStore = charStore

-- Your own aura of a spell, as EllesmereUI reads it: true, false (absent or
-- another caster's), or nil when a secret answer can't tell.
local function ownAuraState(id)
    local ok, aura = read(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok or DUI.IsSecret(aura) then return nil end
    if aura == nil then return false end
    local fromPlayer = aura.isFromPlayerOrPlayerPet
    if not DUI.IsSecret(fromPlayer) and fromPlayer == false then return false end
    local src = aura.sourceUnit
    if src == nil or DUI.IsSecret(src) then return nil end
    return UnitIsUnit(src, "player") == true, aura
end

-- Any rank of a line up on you: true (and the aura), false, or nil when an
-- own-only read can't tell.
local function lineState(line, own)
    local unknown
    for _, id in ipairs(line) do
        if own then
            local state, aura = ownAuraState(id)
            if state then return true, aura end
            if state == nil then unknown = true end
        else
            local ok, aura = read(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and aura ~= nil then return true, aura end
        end
    end
    if unknown then return nil end
    return false
end

-- A buff up on you still counts as missing in its last stretch: the low
-- window, or a quarter of its length for a short buff. Fields that read
-- secret count as fine.
local function runningLow(state, aura)
    if type(aura) ~= "table" or DUI.IsSecret(aura) then return nil end
    local ends, long = aura.expirationTime, aura.duration
    if DUI.IsSecret(ends) or DUI.IsSecret(long) or type(ends) ~= "number" or ends <= 0 then return nil end
    local low = state.low
    if type(long) == "number" and long > 0 then low = math.min(low, long / 4) end
    if ends - state.now <= low then return ends end
    local at = ends - low
    if not state.nextLook or at < state.nextLook then state.nextLook = at end
    return nil
end

-- One reminder while no line is up (the mage armors, a class buff). The icon
-- and the click follow the line last seen up, else the first line known.
local function selfEntries(state, out, mine)
    for _, buff in ipairs(Data.SELF[mine] or {}) do
        local knownLines = {}
        for i, line in ipairs(buff.lines) do
            if highest(line) then knownLines[#knownLines + 1] = i end
        end
        local readableAll = true
        if state.secret then
            for _, line in ipairs(buff.lines) do
                if not ranksReadable(line) then readableAll = false break end
            end
        end
        if #knownLines > 0 and readableAll then
            local up, unknown, lowEnds, lowLine = nil, false, nil, nil
            for i, line in ipairs(buff.lines) do
                local on, aura = lineState(line, buff.own)
                if on == true then
                    local ends = runningLow(state, aura)
                    if ends then lowEnds, lowLine = ends, i else up = i end
                    break
                end
                if on == nil then unknown = true end
            end
            local store = charStore()
            if up then
                if store then store.last[buff.key] = up end
            elseif not unknown then
                local pick = lowLine or (store and store.last[buff.key])
                if not (pick and buff.lines[pick] and highest(buff.lines[pick])) then pick = knownLines[1] end
                local spell = highest(buff.lines[pick])
                local name = spellName(spell)
                out[#out + 1] = {
                    key = buff.key, kind = "self", spell = spell, expireAt = lowEnds,
                    short = name or buff.short, icon = spellIcon(spell),
                    macro = name and ("/cast [nocombat,@player] " .. name) or nil,
                }
            end
        end
    end
end

-- The weapon in an inventory slot: its id and weapon subclass, nil when none.
local function weaponIn(slot)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local id = call(GetInventoryItemID, "player", slot)
    if type(id) ~= "number" then return nil end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, class, sub = read(C_Item.GetItemInfoInstant, id)
        if ok then
            class, sub = plain(class), plain(sub)
            if class ~= nil and class ~= 2 then return nil end -- a shield or an off-hand item
            return id, sub
        end
    end
    return id, nil
end

local function stoneFits(stone, sub, main)
    if stone.mainOnly and not main then return false end
    if stone.kind == "blade" then return sub == nil or Data.BLADE[sub] == true end
    if stone.kind == "blunt" then return sub == nil or Data.BLUNT[sub] == true end
    return true
end

-- What to put on a hand: { item } or { spell }, nil when nothing's at hand.
local function weaponPick(mine, sub, main)
    if mine == "ROGUE" then
        for _, id in ipairs(Data.POISONS) do
            if itemCount(id) > 0 then return { item = id } end
        end
    elseif mine == "SHAMAN" then
        local store = charStore()
        local last = store and store.last.imbue
        local pick
        for _, imbue in ipairs(Data.IMBUES) do
            local id = highest(imbue.ids)
            if id and (imbue.key == last or not pick) then pick = id end
            if id and imbue.key == last then break end
        end
        if pick then return { spell = pick } end
    end
    for _, stone in ipairs(Data.STONES) do
        if stoneFits(stone, sub, main) and itemCount(stone.id) > 0 then return { item = stone.id } end
    end
    return nil
end

local enchantLong = {} -- [enchantID] = the most seconds seen left on it

local HANDS = {
    { key = "weapon:main", inv = 16, slot = "MainHand", main = true },
    { key = "weapon:off", inv = 17, slot = "OffHand" },
}

local function weaponEntries(state, out, mine)
    local W = DUI.Weapons
    if not W then return end
    for _, hand in ipairs(HANDS) do
        local id, sub = weaponIn(hand.inv)
        local slotEnum = Enum and Enum.WeaponSlot and Enum.WeaponSlot[hand.slot]
        if id and slotEnum then
            local list, refused = W.Read(slotEnum)
            if not refused then
                local left, long
                for _, e in ipairs(list) do
                    local s = (e.msLeft or 0) / 1000
                    -- The client gives no enchant's full length: the most seen
                    -- stands in (a 5 minute imbue mustn't run low its whole life).
                    if e.enchantID then
                        local seen = enchantLong[e.enchantID]
                        if not seen or s > seen then enchantLong[e.enchantID] = s; seen = s end
                        if not left or s > left then long = seen end
                    end
                    if not left or s > left then left = s end
                end
                local low = state.low
                if long and long > 0 then low = math.min(low, long / 4) end
                local missing, ends = false, nil
                if not left then
                    missing = true
                elseif left > 0 and left <= low then
                    missing, ends = true, state.now + left
                elseif left > 0 then
                    local at = state.now + left - low
                    if not state.nextLook or at < state.nextLook then state.nextLook = at end
                end
                local pick = missing and weaponPick(mine, sub, hand.main) or nil
                if pick then
                    local e = { key = hand.key, kind = "weapon", expireAt = ends, hand = hand.inv }
                    if pick.item then
                        e.item = pick.item
                        e.short = itemName(pick.item) or (hand.main and L["Main hand"] or L["Off hand"])
                        e.icon = itemIcon(pick.item)
                        e.macro = "/use [nocombat] item:" .. pick.item .. "\n/use " .. hand.inv
                    else
                        local name = spellName(pick.spell)
                        e.spell = pick.spell
                        e.short = name or (hand.main and L["Main hand"] or L["Off hand"])
                        e.icon = spellIcon(pick.spell)
                        e.macro = name and ("/cast [nocombat] " .. name) or nil
                    end
                    out[#out + 1] = e
                end
            end
        end
    end
end

local function useMacro(item) return "/use [nocombat] item:" .. item end

-- Plugins' own missing buffs (API 1.17): an icon while none of the spells is
-- on you and the plugin's when() says yes; a click casts the highest one you
-- know (none known: shown, not clickable).
local function pluginEntries(state, out)
    local R = DUI.APIReport
    local list = R and R.BuffReminders and R.BuffReminders()
    for _, p in ipairs(list or {}) do
        local wanted = true
        if p.when then
            local ok, yes = DUI.SafeReturn(p.when)
            wanted = ok and yes == true
        end
        if wanted and (not state.secret or ranksReadable(p.spells)) and lineState(p.spells, false) == false then
            local spell = highest(p.spells)
            local name = spell and spellName(spell)
            out[#out + 1] = {
                key = p.key, kind = "plugin", spell = spell, short = p.label,
                icon = p.icon or spellIcon(p.spells[1]),
                macro = name and ("/cast [nocombat] " .. name) or nil,
            }
        end
    end
end

local function itemEntries(state, out, have)
    local c = cfg()
    if c.food and readable(state, Data.FOOD) then
        local on, ends = present(state, "player", namesOf(Data.FOOD))
        if on == false then
            out[#out + 1] = { key = "food", kind = "item", short = L["Well Fed"], expireAt = ends,
                              icon = spellIcon(Data.FOOD[1], "Interface\\Icons\\INV_Misc_Food_14") }
        end
    end
    if c.camp then
        local ids = { Data.CAMP }
        Data.CAMP_IDS = Data.CAMP_IDS or ids
        if readable(state, Data.CAMP_IDS) then
            local on, ends = present(state, "player", namesOf(Data.CAMP_IDS))
            if on == false then
                out[#out + 1] = { key = "camp", kind = "item", short = spellName(Data.CAMP) or L["Camp"], expireAt = ends,
                                  icon = spellIcon(Data.CAMP, "Interface\\Icons\\Spell_Fire_Fire") }
            end
        end
    end
    if c.sleepingBag then
        local bag = Data.SLEEPING_BAG
        local level, max = call(UnitLevel, "player"), call(GetMaxPlayerLevel)
        Data.BAG_IDS = Data.BAG_IDS or { bag.buff }
        if type(level) == "number" and type(max) == "number" and level < max and itemCount(bag.item) > 0
                and readable(state, Data.BAG_IDS) then
            local on, _, stacks = present(state, "player", namesOf(Data.BAG_IDS))
            if on == false or (on == true and (tonumber(stacks) or 0) < bag.stacks) then
                out[#out + 1] = { key = "sleepingBag", kind = "item", item = bag.item, macro = useMacro(bag.item),
                                  short = itemName(bag.item) or spellName(bag.buff) or L["Sleeping Bag"],
                                  icon = itemIcon(bag.item) }
            end
        end
    end
    if c.scrolls then
        for _, scroll in ipairs(Data.SCROLLS) do
            if not (scroll.cover and have[scroll.cover]) then
                local carried
                for _, id in ipairs(scroll.items) do
                    if itemCount(id) > 0 then carried = id break end
                end
                local buffName, buffId
                if carried and C_Item then buffName, buffId = call(C_Item.GetItemSpell, carried) end
                if type(buffName) == "string" and (type(buffId) ~= "number" or readable(state, { buffId })) then
                    local on, ends = present(state, "player", { buffName })
                    if on == false then
                        out[#out + 1] = { key = "scroll:" .. scroll.key, kind = "item", item = carried,
                                          macro = useMacro(carried), expireAt = ends,
                                          short = itemName(carried) or buffName, icon = itemIcon(carried) }
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Collect
-- ---------------------------------------------------------------------

-- Everything missing now, in the row's order, or nil when it can't tell (a
-- fight: the row then holds). Entries: { key, kind = "give"|"get"|"self"|
-- "weapon"|"item", family, have, total, unit, spell, item, macro, expireAt,
-- icon, short }. Also sets Reminder.nextLook (when a buff starts running
-- low) and Reminder.giving (you give a raid buff, so the group is watched).
function Reminder.Collect()
    if Reminder.Fighting() then return nil end
    local out = {}
    Reminder.nextLook, Reminder.giving = nil, false
    local c = cfg()
    if not c or c.enabled ~= true then return out end
    if Reminder.Away() then return out end
    local grouped = IsInGroup() == true
    if not grouped and c.solo ~= true then return out end
    local state = { secret = Reminder.AurasSecret(), readable = {}, now = GetTime(), low = Reminder.LowSeconds() }
    local _, mine = UnitClass("player")
    mine = plain(mine)
    groupEntries(state, out, mine, grouped)
    Reminder.giving = grouped and state.giving == true
    if c.self ~= false then selfEntries(state, out, mine) end
    if c.weapons ~= false then weaponEntries(state, out, mine) end
    -- Group buffs on you (for scrolls that a group buff replaces).
    local have = {}
    if c.scrolls then
        for _, fam in ipairs(Data.FAMILIES) do
            if famReadable(state, fam) and unitHas("player", fam) ~= false then have[fam.key] = true end
        end
    end
    itemEntries(state, out, have)
    pluginEntries(state, out)
    Reminder.nextLook = state.nextLook
    -- Middle-clicked away until the next loading screen.
    for i = #out, 1, -1 do
        if Reminder.hidden[out[i].key] then table.remove(out, i) end
    end
    return out
end

-- ---------------------------------------------------------------------
-- Refreshing
-- ---------------------------------------------------------------------

local Row -- BL.ReminderRow, read when first needed (it loads first)
local function row() Row = Row or BL.ReminderRow return Row end

local lookTimer
local function armLook()
    if lookTimer then lookTimer:Cancel(); lookTimer = nil end
    local at = Reminder.nextLook
    if not at then return end
    local wait = math.max(0.1, at - GetTime())
    lookTimer = C_Timer.NewTimer(wait, function() lookTimer = nil; Reminder.RefreshSoon() end)
end

function Reminder.Refresh()
    local R = row()
    if not R or Reminder.sample then return end
    if not Reminder.Enabled() then
        R.Set({})
        Reminder.Watch()
        return
    end
    local list = Reminder.Collect()
    if list == nil then return end -- a fight: hold the row as it is
    R.Set(list)
    armLook()
    Reminder.Watch()
end

-- Once next frame, however many came in: a raid's roster and a pre-pull
-- rebuff come in bursts, and each look reads every member.
Reminder.RefreshSoon = DUI.Soon(function() DUI.SafeCall(Reminder.Refresh) end)

-- The sample: test mode (until it ends) or the options' preview.
function Reminder.ShowSample(on)
    local R = row()
    if not R then return end
    if on == false then
        Reminder.sample = nil
        R.Set({})
        Reminder.RefreshSoon()
        return
    end
    Reminder.sample = true
    R.Set(Data.SAMPLE, true)
end

-- ---------------------------------------------------------------------
-- Events: only while the row is switched on
-- ---------------------------------------------------------------------

local events = CreateFrame("Frame")
Reminder.events = events
-- The group's auras, two units a frame, only while you give a raid buff in a group.
local watchers = {}
Reminder.watchers = watchers

local ALWAYS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_UPDATE_RESTING", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "SPELLS_CHANGED",
    "ADDON_RESTRICTION_STATE_CHANGED", "WEAPON_ENCHANT_CHANGED", "PLAYER_LEVEL_UP" }
local PLAYER_UNIT = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_SUCCEEDED" }

local registered = false
local function registerAll(on)
    if on == registered then return end
    registered = on
    if not on then
        events:UnregisterAllEvents()
        return
    end
    for _, e in ipairs(ALWAYS) do events:RegisterEvent(e) end
    for _, e in ipairs(PLAYER_UNIT) do events:RegisterUnitEvent(e, "player") end
end

local function watchGroup(units)
    local n = 0
    for i = 1, #units, 2 do
        n = n + 1
        local f = watchers[n]
        if not f then
            f = CreateFrame("Frame")
            f:SetScript("OnEvent", function()
                if not Reminder.Fighting() then Reminder.RefreshSoon() end
            end)
            watchers[n] = f
        end
        local a, b = units[i], units[i + 1]
        if f.a ~= a or f.b ~= b then
            f:UnregisterAllEvents()
            if b then f:RegisterUnitEvent("UNIT_AURA", a, b) else f:RegisterUnitEvent("UNIT_AURA", a) end
            f.a, f.b = a, b
        end
    end
    for i = n + 1, #watchers do
        local f = watchers[i]
        if f.a then f:UnregisterAllEvents(); f.a, f.b = nil, nil end
    end
end

-- Registers what the row needs now, and nothing when it's off.
function Reminder.Watch()
    local on = Reminder.Enabled()
    registerAll(on)
    local c = cfg()
    local bags = on and c and (c.weapons ~= false or c.scrolls or c.sleepingBag) or false
    if bags ~= (events.bags == true) then
        events.bags = bags or nil
        if bags then events:RegisterEvent("BAG_UPDATE_DELAYED") else events:UnregisterEvent("BAG_UPDATE_DELAYED") end
    end
    local units = {}
    if on and Reminder.giving and IsInGroup() then
        if IsInRaid() then
            for i = 1, 40 do
                local u = "raid" .. i
                if UnitExists(u) and not UnitIsUnit(u, "player") then units[#units + 1] = u end
            end
        else
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) then units[#units + 1] = u end
            end
        end
    end
    watchGroup(units)
end

-- Counted by the tests: the events the row holds now.
function Reminder.Registered()
    local n = 0
    for _ in pairs(events.__events or {}) do n = n + 1 end
    for _, f in ipairs(watchers) do if f.a then n = n + 1 end end
    return n
end

local function startFight()
    local R = row()
    if R and not Reminder.sample then R.Fight(true) end
end

local function endFight()
    Reminder.encounter = nil
    local R = row()
    if R then R.Fight(false) end
    Reminder.RefreshSoon()
end

local function imbueCast(spellID)
    spellID = plain(spellID)
    if type(spellID) ~= "number" then return end
    for _, imbue in ipairs(Data.IMBUES) do
        for _, id in ipairs(imbue.ids) do
            if id == spellID then
                local s = charStore()
                if s then s.last.imbue = imbue.key end
                return
            end
        end
    end
end

events:SetScript("OnEvent", function(_, event, a, b, c)
    if event == "PLAYER_REGEN_DISABLED" then
        startFight()
    elseif event == "ENCOUNTER_START" then
        Reminder.encounter = true
        startFight()
    elseif event == "PLAYER_REGEN_ENABLED" then
        endFight()
    elseif event == "ENCOUNTER_END" then
        Reminder.encounter = nil
        if not InCombatLockdown() then endFight() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A loading screen: middle-clicked tiles come back, and the group and
        -- auras settle before looking.
        wipe(Reminder.hidden)
        Reminder.encounter = nil
        Reminder.RefreshSoon()
        C_Timer.After(Reminder.SETTLE, Reminder.RefreshSoon)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        imbueCast(c)
        Reminder.RefreshSoon()
    elseif not Reminder.Fighting() then
        Reminder.RefreshSoon()
    end
end)

DUI.On("BuffRemindersChanged", function() Reminder.RefreshSoon() end)

BL.OnPlayer("UNIT_AURA", function()
    if registered and not Reminder.Fighting() then Reminder.RefreshSoon() end
end)

-- Test mode ---------------------------------------------------------------

local function syncTest()
    if not row() or not row().holder then return end
    if DUI.testMode and DUI.TestPartShown("buffreminder") and Reminder.Enabled() then
        Reminder.ShowSample(true)
    elseif Reminder.sample then
        Reminder.ShowSample(false)
    end
end
DUI.On("TestModeChanged", syncTest)
DUI.On("TestPartChanged", function(key) if key == "buffreminder" then syncTest() end end)
DUI.RegisterTestPart("buffreminder", "Buff reminder", 85, function()
    return row() ~= nil and row().holder ~= nil and Reminder.Enabled()
end)

BL.On("DB_READY", function()
    local R = row()
    if R then R.Build() end
    Reminder.sample = nil
    Reminder.Watch()
    Reminder.RefreshSoon()
end)
BL.On("SETTINGS_CHANGED", function(key)
    if type(key) ~= "string" or not key:find("^reminder%.") then return end
    local R = row()
    if R and R.Relayout then R.Relayout() end
    Reminder.Watch()
    if Reminder.sample then
        if not Reminder.Enabled() then Reminder.ShowSample(false) else R.Set(Data.SAMPLE, true) end
        return
    end
    Reminder.RefreshSoon()
end)
