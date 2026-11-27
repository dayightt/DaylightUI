-- Missing buffs: what the row of icons above you shows (ReminderRow.lua draws
-- it). Three sections, as EllesmereUI's buff reminders have them on WoW
-- Forever: raid buffs (the ones you give, with how many lack them, and the
-- ones others give that you lack), your own buffs (ReminderSelf.lua) and
-- consumables (ReminderItems.lua). Each section says where it shows: the open
-- world, dungeons, raids, and for raid buffs in a fight. Nothing shows while
-- resting, dead, in a vehicle, flying on a mount or on a flight path.
--
-- Buffs are found by the client's own name for their ids, so any rank,
-- another caster's copy and any language count. Auras are secret in a fight
-- and under the client's restrictions (boss fights, keystones, PvP matches):
-- a buff is read then only when the client says every rank of it is plain,
-- and a buff that can't be read never shows as missing.

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

-- A section's settings ("raid", "self", "items"), never nil.
local EMPTY = {}
local function section(name)
    local c = cfg()
    local s = c and c[name]
    return type(s) == "table" and s or EMPTY
end
Reminder.Section = section

function Reminder.Enabled()
    local c = cfg()
    return c ~= nil and c.enabled == true
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
-- When it's a fight, when the row hides, where you are
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

-- Why nothing shows now, or nil: resting, dead, on a flight path, in a
-- vehicle, or flying on a mount. A flight form isn't a mount, as in
-- EllesmereUI's gate.
function Reminder.Away()
    if call(IsResting) == true then return "resting" end
    if call(UnitIsDeadOrGhost, "player") == true then return "dead" end
    if call(UnitOnTaxi, "player") == true then return "taxi" end
    if call(UnitInVehicle, "player") == true then return "vehicle" end
    if call(IsMounted) == true and call(IsFlying) == true then return "flying" end
    return nil
end

-- Where-to-show places, from the instance's type and difficulty (EllesmereUI's
-- buckets on WoW Forever). nil: a place none of the sections lists (a
-- battleground, an arena, a scenario), where everything shows.
local DUNGEON = { [1] = true, [2] = true, [8] = true, [23] = true, [24] = true, [205] = true }
local RAID = { [9] = true, [148] = true, [14] = true, [3] = true, [4] = true, [17] = true, [7] = true,
               [33] = true, [15] = true, [5] = true, [6] = true, [16] = true, [233] = true }
Reminder.DUNGEON_DIFFICULTY, Reminder.RAID_DIFFICULTY = DUNGEON, RAID

-- The instance's type and difficulty, once per look (never C_Map: the client
-- itself crashes inside GetBestMapForUnit in places).
local function instance()
    if type(GetInstanceInfo) ~= "function" then return "none", 0 end
    local ok, _, kind, diff = read(GetInstanceInfo)
    if not ok then return "none", 0 end
    kind, diff = plain(kind), plain(diff)
    return type(kind) == "string" and kind or "none", type(diff) == "number" and diff or 0
end

local function bucketOf(kind, diff)
    local G = C_Garrison
    if G and type(G.IsOnGarrisonMap) == "function" and call(G.IsOnGarrisonMap) == true then return "open_world" end
    if kind == "party" then return DUNGEON[diff] and "dungeon" or nil end
    if kind == "raid" then return RAID[diff] and "raid" or nil end
    if kind == "scenario" or kind == "arena" or kind == "pvp" then return nil end
    return "open_world"
end

function Reminder.Bucket()
    return bucketOf(instance())
end

-- A section's gate: left out in a fight when In combat is unticked, else
-- shown unless this place is set to false. A place none lists always shows.
function Reminder.Shows(where, fighting, state)
    if type(where) ~= "table" then where = EMPTY end
    if fighting and where.in_combat == false then return false end
    local bucket
    if state then bucket = state.bucket else bucket = Reminder.Bucket() end
    if not bucket then return true end
    return where[bucket] ~= false
end

-- ---------------------------------------------------------------------
-- Reading buffs
-- ---------------------------------------------------------------------

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

-- The lowest rank you know in a list (lowest first), or nil.
local function lowest(ids)
    if not ids then return nil end
    for i = 1, #ids do
        if known(ids[i]) then return ids[i] end
    end
    return nil
end

local function spellName(id)
    return id and C_Spell and call(C_Spell.GetSpellName, id) or nil
end

local function spellIcon(id, fallback)
    local tex = id and C_Spell and call(C_Spell.GetSpellTexture, id)
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

-- Every rank plain right now (asked only under a restriction or in a fight).
local function ranksReadable(list)
    local ask = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if type(ask) ~= "function" then return true end
    for _, id in ipairs(list or {}) do
        local ok, secret = read(ask, id)
        if not ok or DUI.IsSecret(secret) or secret ~= false then return false end
    end
    return true
end

-- Your own aura of a spell id: the aura, false when none, nil when the client
-- won't say.
local function playerAura(id)
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if type(get) ~= "function" then return nil end
    local ok, aura = read(get, id)
    if not ok or DUI.IsSecret(aura) then return nil end
    if aura == nil then return false end
    return BL.PlainTable(aura) or nil
end

-- A buff on you by its name: the aura, false, or nil when the client won't say.
local function auraByName(unit, name)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    if type(get) ~= "function" or type(name) ~= "string" then return nil end
    local ok, aura = read(get, unit, name, "HELPFUL")
    if not ok or DUI.IsSecret(aura) then return nil end
    if aura == nil then return false end
    return BL.PlainTable(aura) or nil
end

-- When a buff up on you runs out, or nil for never (or can't tell).
local function endsAt(aura)
    if type(aura) ~= "table" then return nil end
    local ends = plain(aura.expirationTime)
    if type(ends) ~= "number" or ends <= 0 then return nil end
    return ends
end

-- A buff up with `minutes` of Show Below: missing again once less than that
-- is left (its end comes back), else the next look is armed at the crossing.
local function below(state, aura, minutes)
    minutes = tonumber(minutes) or 0
    if minutes <= 0 then return nil end
    local ends = endsAt(aura)
    if not ends then return nil end
    local low = minutes * 60
    if ends - state.now <= low then return ends end
    local at = ends - low
    if not state.nextLook or at < state.nextLook then state.nextLook = at end
    return nil
end

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

local function myClass()
    local _, class = UnitClass("player")
    class = plain(class)
    return type(class) == "string" and class or nil
end

-- The helpers the sections share (ReminderSelf.lua, ReminderItems.lua).
Reminder.H = {
    read = read, call = call, plain = plain, known = known, highest = highest, lowest = lowest,
    spellName = spellName, spellIcon = spellIcon, itemCount = itemCount, itemIcon = itemIcon, itemName = itemName,
    ranksReadable = ranksReadable, playerAura = playerAura, auraByName = auraByName, endsAt = endsAt,
    below = below, charStore = charStore, myClass = myClass, section = section,
}
Reminder.Highest = highest

-- ---------------------------------------------------------------------
-- Raid buffs: read the way EllesmereUI's Raid Buffs read on WoW Forever
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

-- Arcane Intellect also counts as up under a stronger buff of its stat (an
-- Elixir of Greater Intellect) that beats the best rank you know.
local function strongerUp(unit, fam)
    if not fam.stronger then return false end
    local best = 0
    local mine = highest(fam.single)
    if mine then best = Data.AMOUNTS[mine] or 0 end
    for id, amount in pairs(fam.stronger) do
        if amount > best then
            local name = spellName(id)
            if name and auraByName(unit, name) then return true end
        end
    end
    return false
end

local function unitHas(unit, fam)
    local aura = Reminder.FamilyAura(unit, fam)
    if aura == nil then return nil end
    if aura then return true end
    if strongerUp(unit, fam) then return true end
    return false
end
Reminder.UnitHas = unitHas

local function famReadable(state, fam)
    if not state.secret then return true end
    local r = state.readable[fam]
    if r == nil then
        r = ranksReadable(fam.single) and ranksReadable(fam.group)
        state.readable[fam] = r
    end
    return r
end
Reminder.FamReadable = famReadable

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

-- A buff switched on: the five with a switch each, Shadow Protection and the
-- blessings behind their own.
local function familyOn(r, fam)
    if fam.blessing then return r.blessings ~= false end
    if fam.key == "shadow" then return r.shadow ~= false end
    local on = type(r.on) == "table" and r.on or EMPTY
    return on[fam.key] ~= false
end
Reminder.FamilyOn = familyOn

local function getEntry(fam)
    return { key = fam.key, kind = "get", section = "raid", family = fam, short = fam.short,
             icon = spellIcon(fam.names[1], fam.icon), tipSpell = fam.names[1] }
end

-- Raid buffs only ask whether a buff is there (no running low): a 2 minute
-- shout would otherwise always read as running out.
local function raidEntries(state, out, mine, grouped)
    local r = section("raid")
    local others, getOn = r.others ~= false, r.mine == true
    local classes = grouped and groupClasses() or {}
    state.giving = false
    local gave = 0
    for _, fam in ipairs(Data.FAMILIES) do
        if not fam.blessing and familyOn(r, fam) then
            local mineToGive = iCast(fam, mine)
            if mineToGive then state.giving = true end
            if mineToGive then
                if famReadable(state, fam) and (not fam.seen or worn(fam)) then
                    local missing, have, total, first, lacking
                    if grouped and others then
                        have, total, first, lacking = coverage(fam)
                        missing = total > 0 and have < total
                    else
                        missing = unitHas("player", fam) == false
                    end
                    if missing then
                        local spell, unit = pickCast(fam, first)
                        if spell then
                            gave = gave + 1
                            out[#out + 1] = { key = fam.key, kind = "give", section = "raid", family = fam,
                                              have = grouped and others and have or nil,
                                              total = grouped and others and total or nil,
                                              unit = unit, spell = spell, lacking = lacking, extra = gave > 1 or nil,
                                              short = fam.short, icon = spellIcon(fam.names[1], fam.icon), tipSpell = spell }
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
    if not getOn or r.blessings == false or paladins == 0 then return end
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
        if wanted and (not state.secret or ranksReadable(p.spells)) then
            local up, unknown = false, false
            for _, id in ipairs(p.spells) do
                local a = playerAura(id)
                if a then up = true break end
                if a == nil then unknown = true end
            end
            if not up and not unknown then
                local spell = highest(p.spells)
                local name = spell and spellName(spell)
                out[#out + 1] = {
                    key = p.key, kind = "plugin", section = "self", spell = spell, short = p.label,
                    icon = p.icon or spellIcon(p.spells[1]), tipSpell = spell or p.spells[1],
                    macro = name and ("/cast [nocombat] " .. name) or nil,
                }
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Collect
-- ---------------------------------------------------------------------

-- One look's shared answers.
local function newState(fighting)
    local kind, diff = instance()
    return { secret = Reminder.AurasSecret(), readable = {}, now = GetTime(), fighting = fighting,
             kind = kind, bucket = bucketOf(kind, diff), pvp = kind == "pvp" or kind == "arena" }
end
Reminder.NewState = newState

-- Everything missing now, in the row's order (raid buffs, your own buffs,
-- consumables). Entries: { key, section = "raid"|"self"|"items", kind =
-- "give"|"get"|"self"|"weapon"|"item"|"plugin"|"track", family, have, total,
-- unit, spell, item, macro, expireAt, icon, short, count }. Also sets
-- Reminder.nextLook (the next Show Below crossing), Reminder.giving (you give
-- a raid buff, so the group is watched) and, in a fight, Reminder.unread (the
-- raid buffs the client won't let be read: their icons hold as they were).
--
-- In a fight only raid buffs are read, as EllesmereUI does, and only the one
-- you give whose button was bound before the pull: a secure button can't be
-- given a new spell in a fight.
function Reminder.Collect()
    local out = {}
    Reminder.nextLook, Reminder.giving, Reminder.unread = nil, false, {}
    local c = cfg()
    if not c or c.enabled ~= true then return out end
    local away = Reminder.Away()
    local fighting = Reminder.Fighting()
    if away then
        -- Resting in the sleeping bag: its timer is the one icon left.
        local I = BL.ReminderItems
        if away == "resting" and not fighting and I and I.SleepTimer then
            local state = newState(false)
            if Reminder.Shows(section("items").where, false, state) then I.SleepTimer(state, out) end
            Reminder.nextLook = state.nextLook
        end
        return out
    end
    local state = newState(fighting)
    if fighting then state.secret = true end
    local mine = myClass()
    local grouped = IsInGroup() == true
    if Reminder.Shows(section("raid").where, fighting, state) then
        raidEntries(state, out, mine, grouped)
        Reminder.giving = grouped and state.giving == true
        for _, fam in ipairs(Data.FAMILIES) do
            if state.readable[fam] == false then Reminder.unread[fam.key] = true end
        end
    end
    if fighting then
        local R = BL.ReminderRow
        local bound = R and R.BoundKey and R.BoundKey()
        for i = #out, 1, -1 do
            local e = out[i]
            if e.kind == "give" then
                if (bound and e.key ~= bound) or (not bound and e.extra) then table.remove(out, i)
                else e.extra = nil end
            end
        end
        local S = BL.ReminderSelf
        if S and S.Fight and Reminder.Shows(section("self").where, false, state) then S.Fight(state, out, mine) end
    else
        if Reminder.Shows(section("self").where, false, state) then
            local S = BL.ReminderSelf
            if S then S.Collect(state, out, mine) end
            pluginEntries(state, out)
        end
        if Reminder.Shows(section("items").where, false, state) then
            local I = BL.ReminderItems
            if I then I.Collect(state, out, mine) end
        end
    end
    Reminder.nextLook = state.nextLook
    -- Middle-clicked away until the next loading screen.
    for i = #out, 1, -1 do
        if Reminder.hidden[out[i].key] then table.remove(out, i) end
    end
    return out
end

-- ---------------------------------------------------------------------
-- Sounds: one per section, as a reminder newly appears
-- ---------------------------------------------------------------------

local heard -- the keys of the last look; nil until the first look after login

function Reminder.ResetSounds() heard = nil end

local function sounds(list)
    local now = {}
    for _, e in ipairs(list) do
        if e.kind ~= "track" then
            now[e.key] = true
            if heard and not heard[e.key] then
                local key = section(e.section or "self").sound
                if type(key) == "string" and key ~= "none" and DUI.Sound and DUI.Sound.Alert then
                    DUI.Sound.Alert(key)
                end
            end
        end
    end
    heard = now
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
    -- In a fight a raid buff the client won't let be read keeps its icon.
    if Reminder.Fighting() then
        local have = {}
        for _, e in ipairs(list) do have[e.key] = true end
        for _, t in ipairs(R.active) do
            local e = t.entry
            if e and not t.leaving and (e.kind == "give" or e.kind == "get") and not e.extra
                and Reminder.unread[e.key] and not have[e.key] then
                list[#list + 1] = e
            end
        end
    end
    sounds(list)
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
    "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }
local PLAYER_UNIT = { "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }

local registered = false
local function registerAll(on)
    if on == registered then return end
    registered = on
    if not on then
        events:UnregisterAllEvents()
        events.wants = nil
        return
    end
    for _, e in ipairs(ALWAYS) do events:RegisterEvent(e) end
    for _, e in ipairs(PLAYER_UNIT) do events:RegisterUnitEvent(e, "player") end
end

-- An event only while a reminder that needs it can show.
local function want(event, on, unit)
    events.wants = events.wants or {}
    on = on and true or false
    if (events.wants[event] == true) == on then return end
    events.wants[event] = on or nil
    if not on then events:UnregisterEvent(event)
    elseif unit then events:RegisterUnitEvent(event, unit)
    else events:RegisterEvent(event) end
end
Reminder.Want = want

local function watchGroup(units)
    local n = 0
    for i = 1, #units, 2 do
        n = n + 1
        local f = watchers[n]
        if not f then
            f = CreateFrame("Frame")
            f:SetScript("OnEvent", function() Reminder.RefreshSoon() end)
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
    if on then
        local S, I = BL.ReminderSelf, BL.ReminderItems
        local bags = (S and S.WantsBags and S.WantsBags()) or (I and I.WantsBags and I.WantsBags())
        want("BAG_UPDATE_DELAYED", bags)
        local weapons = S and S.WantsWeapons and S.WantsWeapons()
        want("WEAPON_ENCHANT_CHANGED", weapons)
        want("UNIT_INVENTORY_CHANGED", weapons, "player")
        if S and S.Watch then S.Watch(want) end
        if I and I.Watch then I.Watch(want) end
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

-- Other parts hear of events they asked for (Reminder.Want) through this.
Reminder.handlers = {}

events:SetScript("OnEvent", function(_, event, ...)
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
        for _, fn in pairs(Reminder.handlers) do DUI.SafeCall(fn, event, ...) end
        Reminder.RefreshSoon()
        C_Timer.After(Reminder.SETTLE, Reminder.RefreshSoon)
        return
    end
    for _, fn in pairs(Reminder.handlers) do DUI.SafeCall(fn, event, ...) end
    Reminder.RefreshSoon()
end)

DUI.On("BuffRemindersChanged", function() Reminder.RefreshSoon() end)

BL.OnPlayer("UNIT_AURA", function()
    if registered then Reminder.RefreshSoon() end
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
    Reminder.ResetSounds()
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
