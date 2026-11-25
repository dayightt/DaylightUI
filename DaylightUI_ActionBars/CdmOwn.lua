-- Icons for spells the player knows but the game's Cooldown Manager doesn't display
-- (set to "Not Displayed"). The game builds no item frame for those, so a placed one
-- gets a Daylight UI frame with a cooldown swipe.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local L = DUI.L

local Own = {}
ns.CdmOwn = Own

local AURA = { TrackedBuff = true, TrackedBar = true }
local frames = {}   -- [id] = frame
local holds = {}    -- [id .. kind] = placeholder frame

-- { [id] = { kind = "icon"|"bar", aura = bool } } for every spell the game lists for
-- this spec that the character knows, shown or not. Read only.
-- Cached between layout passes (one per aura shown or hidden) and re-read via
-- Own.Forget after a spell, talent or spec change and after the game's own layout
-- pass, since its Cooldown Manager settings may have moved a spell. An empty answer
-- (game not ready at login) or one read in combat or under restrictions (ids may
-- come back secret) isn't cached.
local known
function Own.Forget() known = nil end
function Own.Known()
    if known then return known end
    local out = Own.Read()
    if next(out) and not InCombatLockdown() and not (DUI.Restricted and DUI.Restricted()) then known = out end
    return out
end
-- What a placed piece is: a spell the game lists (Known), else one from the custom
-- list (CdmCustom.Entry). nil = nothing to draw. known = a layout pass's Own.Known(),
-- since in combat it isn't cached and each call would read it again.
function Own.Entry(id, known)
    local k = (known or Own.Known())[id]
    if k == nil and ns.CdmCustom then k = ns.CdmCustom.Entry(id) end
    return k
end
for _, e in ipairs({ "SPELLS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
                     "PLAYER_TALENT_UPDATE", "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED" }) do
    DUI.RegisterEvent(e, Own.Forget)
end

function Own.Read()
    local out = {}
    local cats = ns.CdmData.Categories()
    if not cats then return out end
    local CV = _G.C_CooldownViewer
    for name, cat in pairs(cats) do
        local ids = CV.GetCooldownViewerCategorySet(cat, false)
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            -- In two categories the cooldown one wins (pairs order isn't fixed).
            local had = type(id) == "number" and not isSecret(id) and out[id]
            if had == nil or (had and had.aura and not AURA[name]) then
                out[id] = { kind = name == "TrackedBar" and "bar" or "icon", aura = AURA[name] or false, cat = name }
            end
        end
    end
    Own.AddProcBuffs(out, CV, cats)
    -- The game files some cooldowns as buffs (Charge, which tracks the stun). An
    -- icon spell with a real cooldown is treated as a cooldown.
    for id, k in pairs(out) do
        if k.aura and k.kind == "icon" and Own.HasCooldown(Own.SpellOf(id)) then k.aura = false end
    end
    return out
end

-- What a placed spell shows, and who draws it, follow from things that stay put
-- while you play: the game's data about the spell (does it have a real cooldown,
-- does it have a buff or debuff, does that buff hold a count), the row the game
-- files it in, and the player's own "What it shows" pick. No other option and
-- nothing picked up along the way may change either, or a spell could swap drawers
-- in the middle of a session.
--
-- Own.Track says what it shows. The player's pick wins. Left unset:
--   no buff or debuff                           nil, a plain cooldown
--   a buff row spell                            "both" with a real cooldown, else "buff"
--   a cooldown whose icon shows its buff        "both" (Rend, Death Wish, Bloodrage)
--   a cooldown whose icon never shows its buff  "cooldown" (Mortal Strike), or "both" when
--                                               the buff holds a count or there is no
--                                               real cooldown to show (Slice and Dice)
--
-- Own.GameDraws says who draws it. The game's own item does when it already shows
-- exactly that; Daylight UI's icons, buff buttons and bars draw the rest:
--   shows                the game's cooldown icon         the game's buff item
--   nothing to pick      the game's                       the game's
--   "cooldown"           the game's if the icon never     Daylight UI's
--                        shows the buff, else Daylight UI's
--   "buff"               Daylight UI's                    the game's
--   "both"               the game's if the icon shows     Daylight UI's
--                        the buff, else Daylight UI's
-- Always Daylight UI's: a totem, a buff that holds a count (the game's cooldown icon
-- can't show one), a buff the game's item can't see (CdmAuras.GameBlind), a spell
-- placed in the other shape than the game's item, and a spell the game has no item
-- for at all.
Own.TRACKS = { "both", "cooldown", "buff" }
local function valid(t) return t == "both" or t == "cooldown" or t == "buff" end

function Own.HasAura(id, k)
    if k and AURA[k.cat] then return true end
    return (ns.CdmAuras ~= nil and ns.CdmAuras.Follows(id)) or Own.QuietAura(id)
end

-- A totem piece's track (CdmCustom.TOTEMS and TOTEM_SLOTS), from the game's list or
-- Daylight UI's own (custom). nil leaves the piece to its plain path: the game's
-- icon, or for Daylight UI's own a cooldown or buff by CdmCustom.Track.
local function totemTrack(sid, p, custom)
    local pick = type(p) == "table" and p.track or nil
    if type(p) == "table" and p.hideMissing == true then pick = "buff" end
    -- No buff: the totem's time while it stands. A pick from before (Both, Buff
    -- only) reads as Totem.
    if ns.CdmCustom.TotemNoBuff(sid) then return pick ~= "cooldown" and "totem" or nil end
    -- A buff: the totem's time with the buff covering the icon while you have it,
    -- so the icon shows when you're out of range. Buff only and Cooldown stay as picked.
    if pick == "cooldown" or pick == "buff" or pick == "aura" then
        if custom then return nil end
        return pick == "aura" and "buff" or pick
    end
    return "both"
end

function Own.Track(id, p, known)
    local C = ns.CdmCustom
    local custom = C ~= nil and C.Is(id)
    -- An element piece: Totem and buff, whichever totem stands.
    if custom and C.Element(id) then return "both" end
    if C and not (custom and C.IsPet(id)) and C.Totem(Own.SpellOf(id)) then
        if not custom and not (known or Own.Known())[id] then return nil end
        return totemTrack(Own.SpellOf(id), p, custom)
    end
    if custom then
        -- A spell of the addon's own list shows one thing (CdmCustom.Track), or both.
        return C.Track(id) == "both" and "both" or nil
    end
    local k = (known or Own.Known())[id]
    if not k then return nil end
    -- No buff known yet: a plain cooldown, unless the player picked something else.
    -- The buff is watched by the spell's own id until a cast teaches the real one.
    if not Own.HasAura(id, k) then
        local t = Own.Picked(p)
        return t ~= "cooldown" and t or nil
    end
    local t = Own.Picked(p)
    if t then return t end
    -- The game's icon never shows a quiet aura, so left alone it stays a cooldown.
    -- The Buff up and Buff missing rows still work on it: the game's buff item of
    -- the same spell says whether the buff is up. With no real cooldown (Slice and
    -- Dice) there's nothing to stay as. A buff that holds a count (Shield Block,
    -- Holy Shield; Own.Stacks) shows it while up, since the count is why it's placed.
    local hasCooldown = Own.HasCooldown(Own.SpellOf(id))
    if hasCooldown and not AURA[k.cat] and Own.QuietAura(id) then
        return Own.Stacks(id) and "both" or "cooldown"
    end
    -- A cooldown-row spell with no cooldown of its own (Rend, Moonfire) stays up
    -- like the game's icon: its aura while up, else ready. Only spells from the buff
    -- rows show just while up.
    return (hasCooldown or not AURA[k.cat]) and "both" or "buff"
end

-- Whether the game's own item draws a placed spell that shows t (Own.Track's
-- answer), or Daylight UI draws it and the game's item stays out of sight. auraRow
-- = the item sits in one of the game's buff rows, else it's a cooldown icon.
function Own.GameDraws(id, t, auraRow)
    if t == nil then return true end
    local C, A = ns.CdmCustom, ns.CdmAuras
    -- A totem is timed by Daylight UI from its slot.
    if t == "totem" or (C ~= nil and C.Totem(Own.SpellOf(id)) ~= nil) then return false end
    if A ~= nil and A.GameBlind(id) then return false end
    -- A buff item shows the buff and hides while it's down, nothing else.
    if auraRow then return t == "buff" end
    if A ~= nil and A.Follows(id) then return t == "both" and not Own.Stacks(id) end
    return t == "cooldown"
end

-- Shows only its buff, never its cooldown.
function Own.BuffOnly(id, p, known)
    local C = ns.CdmCustom
    if C and C.Is(id) then return C.Track(id) == "aura" end
    return Own.Track(id, p, known) == "buff"
end

-- The player's own pick (not the rule's guess), or nil. Hide (Buff missing) implies
-- Buff only: shown just while the buff is up.
function Own.Picked(p)
    if type(p) == "table" and p.hideMissing == true then return "buff" end
    local t = type(p) == "table" and p.track
    if valid(t) then return t end
end

-- The spell has a real cooldown (longer than the global cooldown), by the game's
-- base cooldown call, else by its own spell data, which also counts a cooldown
-- shared by a group of spells (the shocks, Charge, Kick). Never by watching a
-- cooldown run: a wand shot puts every spell on one, and a spell would then be
-- drawn one way before its first cast and another way after.
function Own.HasCooldown(sid)
    if not sid then return false end
    local get = _G.GetSpellBaseCooldown or (C_Spell and C_Spell.GetSpellBaseCooldown)
    if type(get) == "function" then
        local ok, ms = pcall(get, sid)
        if ok and type(ms) == "number" and not isSecret(ms) and ms > 1500 then return true end
    end
    local fact = ns.CdmCustom and ns.CdmCustom.Fact(sid)
    return fact ~= nil and fact.cd ~= nil
end

local function infoOf(id) return ns.CdmData.Info(id) end

local function plainNumber(v)
    if type(v) == "number" and not isSecret(v) then return v end
end

-- Buffs a talent procs. The game's Cooldown Manager lists the buff's own spell,
-- which nobody learns, so it calls the buff unknown and never shows it even with the
-- talent taken (a rogue's Venom). By the buff's spell id, the talents that proc it
-- (the game's data: the talent's effect triggers the buff).
Own.PROC_TALENTS = {
    [1310703] = { 1329328 },   -- Venom
    [1284536] = { 14909 },     -- Holy Purpose, from Searing Light
}

local function spellKnown(sid)
    local known = type(C_SpellBook) == "table" and C_SpellBook.IsSpellKnown
    if type(known) ~= "function" then return false end
    local ok, yes = pcall(known, sid)
    return ok and yes == true
end

-- Adds to out the game's buff ids it left out as unknown whose talent you have.
function Own.AddProcBuffs(out, CV, cats)
    for name, cat in pairs(cats) do
        if AURA[name] then
            local ids = CV.GetCooldownViewerCategorySet(cat, true)
            if type(ids) == "table" then
                for _, id in ipairs(ids) do
                    if type(id) == "number" and not isSecret(id) and out[id] == nil then
                        local info = infoOf(id)
                        local talents = info and Own.PROC_TALENTS[plainNumber(info.spellID) or 0]
                        if talents then
                            for _, t in ipairs(talents) do
                                if spellKnown(t) then
                                    out[id] = { kind = name == "TrackedBar" and "bar" or "icon", aura = true, cat = name }
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Own.SpellOf(id)
    local C = ns.CdmCustom
    if C and C.Is(id) then return C.SpellOf(id) end
    local info = infoOf(id)
    return info and plainNumber(info.spellID)
end

-- A cooldown with a buff or debuff the game's icon doesn't show. Either the game
-- says it has an aura but flags it HideAura (Mortal Strike), or it says none, links
-- none, and Daylight UI's spell list (CdmSpells) knows one (Charge's stun). It can
-- still be picked on the card. own = by the row's own spell alone (CdmAuras.Follows).
-- Racials the game files with no aura though they give a buff. Eureka! (Gnome) has
-- one rank per power type, and its buff carries the same spell id.
Own.RACIAL_AURAS = {
    [1259812] = true, [1259813] = true, [1259817] = true, [1259821] = true, [1259823] = true, -- Eureka!
}

function Own.QuietAura(id, own)
    local C = ns.CdmCustom
    if C and C.Is(id) then return false end
    if ns.CdmAuras and ns.CdmAuras.Follows(id, own) then return false end
    local info = infoOf(id)
    if info and not isSecret(info.hasAura) and info.hasAura == true then return true end
    local sid = info and plainNumber(info.spellID)
    if sid ~= nil and Own.RACIAL_AURAS[sid] then return true end
    return sid ~= nil and C ~= nil and C.KeyOfAuraSpell(sid) ~= nil
end

-- Buffs and debuffs seen from your own casts, per character:
-- DB.Character().cdmAuraIDs[cast spell id] = { [aura spell id] = true }. The game's
-- data has no aura id for some spells (a totem's buff comes from the totem, a
-- trinket's from its use), so a placed spell's cast where auras can be read looks
-- for it, by id and by name. These ids widen what a buff button watches
-- (CdmAuras.SpellIDs) and tell a totem's icon its buff is known. They also decide
-- whether a placed buff stays hidden in the game's row for the aura holder to draw
-- (CdmSwitch.Placed).
local function auraBook()
    local c = DUI.DB and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.cdmAuraIDs) ~= "table" then c.cdmAuraIDs = {} end
    return c.cdmAuraIDs
end

-- { [aura spell id] = true } learned for this cast spell id, or nil.
function Own.AuraOf(sid)
    local t = sid ~= nil and auraBook()[sid]
    return type(t) == "table" and next(t) ~= nil and t or nil
end

-- Spell ids of every placed piece, as { [cast spell id] = true }.
local function placedSpells()
    local set = ns.CdmData and ns.CdmData.Current()
    local out = {}
    local C = ns.CdmCustom
    for id in pairs(set and set.pieces or {}) do
        if C and C.Is(id) then
            if not C.IsPet(id) then
                for s in pairs(C.Ranks(id)) do out[s] = true end
            end
        else
            local s = Own.SpellOf(id)
            if s then out[s] = true end
        end
    end
    return out
end

-- Your aura from this cast: on you, then your own on the target. By id first,
-- then by the spell's name.
local LOOKS = { { unit = "player", filter = "HELPFUL" }, { unit = "target", filter = "HARMFUL|PLAYER" } }
local function auraFrom(sid)
    local U = C_UnitAuras
    if type(U) ~= "table" then return nil end
    local name
    local okN, n = pcall(C_Spell.GetSpellName, sid)
    if okN and type(n) == "string" and not isSecret(n) then name = n end
    -- A totem's buff is often named without the word Totem (Strength of Earth
    -- Totem puts up Strength of Earth), so that name is tried too.
    local bare
    local C = ns.CdmCustom
    if name and C and C.Totem(sid) then
        bare = name:gsub("%s*Totem%s*", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if bare == name or bare == "" then bare = nil end
    end
    for _, look in ipairs(LOOKS) do
        local a
        if type(U.GetUnitAuraBySpellID) == "function" then
            local ok, got = pcall(U.GetUnitAuraBySpellID, look.unit, sid)
            -- On the target, only your own debuff.
            if ok and type(got) == "table" and (look.unit == "player"
                or got.isFromPlayerOrPlayerPet == true or got.sourceUnit == "player") then
                a = got
            end
        end
        for _, nm in ipairs({ name, bare }) do
            if not a and type(U.GetAuraDataBySpellName) == "function" then
                local ok, got = pcall(U.GetAuraDataBySpellName, look.unit, nm, look.filter)
                if ok and type(got) == "table" then a = got end
            end
        end
        local found = a and plainNumber(a.spellId)
        if found then return found end
    end
end

-- After a cast of a placed spell, out of a fight: remember the aura it put up.
Own.AURA_LOOK_DELAY = 0.3
function Own.LearnAura(sid)
    if not (ns.Cooldowns and ns.Cooldowns.enabled) then return end
    local A = ns.CdmAuras
    if not (A and A.Readable and A.Readable()) then return end
    if not placedSpells()[sid] then return end
    local found = auraFrom(sid)
    if not found then return end
    local book = auraBook()
    if type(book[sid]) == "table" and book[sid][found] then return end
    book[sid] = type(book[sid]) == "table" and book[sid] or {}
    book[sid][found] = true
    A.Rebuild()
    if ns.CdmRows then ns.CdmRows.Refresh() end
end

-- Totems dropped in a fight before their buff was learned: [cast spell id] = true.
-- Auras can't be read there, so each is looked up once the fight ends, if it
-- still stands (Own.LearnAfterCombat).
local totemsToLearn = {}

local casts = CreateFrame("Frame")
casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
casts:SetScript("OnEvent", function(_, _, _, _, sid)
    if type(sid) ~= "number" or isSecret(sid) then return end
    if InCombatLockdown() then
        local C = ns.CdmCustom
        if C and C.Totem(sid) and not C.TotemBuffKnown(sid) then totemsToLearn[sid] = true end
        return
    end
    -- The aura lands a moment after the cast event.
    C_Timer.After(Own.AURA_LOOK_DELAY, function() DUI.SafeCall(Own.LearnAura, sid) end)
end)

-- After a fight: each totem dropped in it with its buff unknown, still standing,
-- has its buff looked up now. One gone or already learned is dropped from the list.
function Own.LearnAfterCombat()
    local C = ns.CdmCustom
    if not C then return end
    for sid in pairs(totemsToLearn) do
        if C.TotemBuffKnown(sid) or not C.TotemUp(sid) then
            totemsToLearn[sid] = nil
        else
            Own.LearnAura(sid)
            if C.TotemBuffKnown(sid) then totemsToLearn[sid] = nil end
        end
    end
end
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() DUI.SafeCall(Own.LearnAfterCombat) end)

-- A spell whose buff holds a count, by the game's spell data: charges that get used
-- up (Shield Block, Holy Shield) or stacks that build (Prayer of Mending). The
-- game's cooldown icon shows the buff but never its count (its cooldown items only
-- draw spell charges, see CooldownViewer.lua), so Daylight UI draws these, with the
-- client's aura button counting.
function Own.Stacks(id)
    local fact = ns.CdmCustom and ns.CdmCustom.Fact(Own.SpellOf(id))
    if not fact then return false end
    return (fact.charges or 0) > 1 or (fact.stacks or 0) > 1
end

-- A layout saved before a spell's options stopped deciding who draws it. The old
-- rules drew some unset spells differently: Hide (Buff up) or a buff glow turned a
-- cooldown whose icon never shows its buff into Cooldown and buff; Hide, a buff
-- sound or Glow to recast moved a game cooldown icon to Daylight UI's own; and a
-- spell once seen on a cooldown counted as having one. Each such piece gets what
-- it showed written down as its pick, so nothing on screen changes.
--
-- A layout is shared by every character of its class, and the first one to log in
-- may not know every spell in it (a lower alt, other talents). A piece it can't
-- read waits in set.tracksLeft for a character that knows the spell. Pieces placed
-- later are never read the old way.
local function picked(p) return Own.Picked(p) ~= nil or p.track ~= nil end
local function sounds(v) return v ~= nil and v ~= "none" end

-- Cooldowns the old rules had seen run, per spell, by any character of this class.
local function seenCooldowns()
    local DB = DUI.DB
    local out = {}
    if not DB then return out end
    local mine = DB.Character()
    local root = DB.Root()
    local _, class = UnitClass("player")
    local function add(c)
        if type(c) ~= "table" or type(c.cdmCooldowns) ~= "table" then return end
        for sid, yes in pairs(c.cdmCooldowns) do
            if yes == true then out[sid] = true end
        end
    end
    add(mine)
    for _, c in pairs(type(root.characters) == "table" and root.characters or {}) do
        local theirs = type(c) == "table" and (c.class or (type(c.inventory) == "table" and c.inventory.class))
        if c ~= mine and type(class) == "string" and theirs == class then add(c) end
    end
    return out
end

-- What an unset piece showed under the old rules, when today's would draw it
-- differently; else nil.
local function oldTrack(id, p, k, known, seenCd, set)
    local C, A = ns.CdmCustom, ns.CdmAuras
    local sid = Own.SpellOf(id)
    local learnedCd = sid ~= nil and seenCd[sid] == true and not Own.HasCooldown(sid)
    if C and C.Is(id) then
        -- A spell added by ID showed its cooldown once one was seen.
        if learnedCd and C.IsAdded(id) and not C.ItemOf(id) and C.Track(id, set) == "aura" and C.CanTrack(id) then
            return "cooldown"
        end
        return nil
    end
    -- Those layouts were read by the row's own spell alone: a buff under a linked
    -- spell (Bloodrage's) didn't count as shown by the game's icon.
    local follows = A ~= nil and A.Follows(id, true)
    local linked = A ~= nil and not follows and A.Follows(id)
    local quiet = Own.QuietAura(id, true) or (not follows and Own.AuraOf(sid) ~= nil)
    if not (AURA[k.cat] or follows or quiet) then return nil end
    local hadCd = learnedCd or Own.HasCooldown(sid)
    local old
    if hadCd and not AURA[k.cat] and quiet then
        old = (Own.Stacks(id) or p.hideActive == true or p.missingGlow == true or p.upGlow == true)
            and "both" or "cooldown"
    else
        old = (hadCd or not AURA[k.cat]) and "both" or "buff"
    end
    -- These options moved a game cooldown icon to Daylight UI's own.
    local moved = p.hideActive == true or sounds(p.buffSound) or sounds(p.buffEndSound) or p.clipGlow == true
    local now = Own.Track(id, p, known)
    if linked and old == "cooldown" and now == "both" then
        -- Left as it was, the game's icon then and now. As a bar, or moved to
        -- Daylight UI's icon by an option, it showed the cooldown alone.
        if p.shape == "bar" or moved then return old end
        return nil
    end
    if old ~= now and not (old == "cooldown" and now == nil) then return old end
    -- Rend as a bar: a cooldown under the debuff's bar when the spell had a
    -- cooldown seen or an option moved it, which only Both keeps.
    if p.shape == "bar" and follows and old == "both" and not AURA[k.cat]
        and not Own.HasCooldown(sid) and (moved or learnedCd) then
        return "both"
    end
end

function Own.KeepOldTracks(set)
    if type(set) ~= "table" or type(set.pieces) ~= "table" then return end
    local left = set.tracksLeft
    if set.tracksKept and not (type(left) == "table" and next(left) ~= nil) then return end
    -- The spell list is whole only out of a fight, once the game has it.
    if InCombatLockdown() or (DUI.Restricted and DUI.Restricted()) then return end
    local known = Own.Known()
    if next(known) == nil then return end
    local first = not set.tracksKept
    set.tracksKept = true
    local seenCd = seenCooldowns()
    local C = ns.CdmCustom
    local changed = false
    local function look(id, p)
        if type(p) ~= "table" or picked(p) then return true end
        local custom = C ~= nil and C.Is(id)
        if not custom and not known[id] then return false end
        local t = oldTrack(id, p, known[id], known, seenCd, set)
        if t then p.track, changed = t, true end
        return true
    end
    if first then
        for id, p in pairs(set.pieces) do
            if not look(id, p) then
                if type(set.tracksLeft) ~= "table" then set.tracksLeft = {} end
                set.tracksLeft[id] = true
            end
        end
    else
        for id in pairs(left) do
            local p = set.pieces[id]
            if p == nil or look(id, p) then left[id] = nil end
        end
        if next(left) == nil then set.tracksLeft = nil end
    end
    if changed and ns.CdmData then ns.CdmData.Changed() end
end

-- A gear slot cooldown (trinkets) with nothing equipped there. The game lists one on
-- every character; the tray leaves it out.
function Own.EmptySlot(id)
    local info = infoOf(id)
    local slot = info and plainNumber(info.equipSlot)
    if not slot or type(GetInventoryItemID) ~= "function" then return false end
    return GetInventoryItemID("player", slot) == nil
end

-- Cooldowns with no spell, as the game draws them (CooldownViewerItemData.lua,
-- spellCategoryMetadataLookup): potions and healthstones by spell category.
local CATEGORY = {
    [4] = { icon = "Interface/ICONS/INV_POTION_114", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_COMBAT_TITLE", fallback = L["Combat potion"] },
    [30] = { icon = "Interface/ICONS/INV_POTION_54", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTH_TITLE", fallback = L["Healing potion"] },
    [1711] = { icon = "Interface/ICONS/Warlock_ Healthstone", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_HEALTHSTONE_TITLE", fallback = L["Healthstone"] },
    [2566] = { icon = "Interface/ICONS/Warlock_ Bloodstone", title = "COOLDOWN_VIEWER_TOOLTIP_POTION_DEMONIC_HEALTHSTONE_TITLE", fallback = L["Demonic Healthstone"] },
}

local SPELL_KEYS = { "overrideTooltipSpellID", "overrideSpellID", "spellID" }

-- A cooldown's name and icon (either may be nil): its spell, else the item in its
-- equipment slot (trinkets), else its spell category's (potions).
function Own.Look(id)
    local C = ns.CdmCustom
    if C and C.Is(id) then return C.Look(id) end
    local info = infoOf(id)
    if not info then return nil, nil end
    -- Same order as the game (CooldownViewerItemData.lua GetSpellID): tooltip
    -- override, override, then base spell; the first this client has.
    local first
    for _, key in ipairs(SPELL_KEYS) do
        local sid = plainNumber(info[key])
        if sid then
            first = first or sid
            local okN, name = pcall(C_Spell.GetSpellName, sid)
            local okT, tex = pcall(C_Spell.GetSpellTexture, sid)
            name = okN and type(name) == "string" and name or nil
            tex = okT and type(tex) ~= "nil" and tex or nil
            if name or tex then return name, tex end
        end
    end
    if first then return nil, nil end
    local slot = plainNumber(info.equipSlot)
    if slot then
        local tex = type(GetInventoryItemTexture) == "function" and GetInventoryItemTexture("player", slot) or nil
        local item = type(GetInventoryItemID) == "function" and GetInventoryItemID("player", slot)
        local get = item and type(C_Item) == "table" and C_Item.GetItemNameByID
        local ok, name = false, nil
        if type(get) == "function" then ok, name = pcall(get, item) end
        return ok and type(name) == "string" and name or nil, tex
    end
    local cat = CATEGORY[plainNumber(info.spellCategoryID) or 0]
    if cat then
        local title = _G[cat.title]
        return type(title) == "string" and title or cat.fallback, cat.icon
    end
    return nil, nil
end

function Own.Frame(id) return frames[id] end

Own.TOTEM_DIM = 0.3          -- icon alpha while a totem stands and you lack its buff
Own.TOTEM_TIME_LEVEL = 20    -- the totem's time over the buff's button (CdmAuras.Over: +10)

-- An element piece's icon and spell follow its slot (CdmCustom.SlotNow): the totem
-- or cooldown totem there, else the element's icon. Returns the phase and the
-- totem's duration. f.slotSpell and f.slotPhase say what's drawn (CdmEffects).
function Own.FollowSlot(f, icon)
    local C = ns.CdmCustom
    local sid, phase, d = C.SlotNow(f.cooldownID)
    f.cooldownInfo.spellID = sid or C.SpellOf(f.cooldownID)
    f.slotSpell, f.slotPhase = sid, phase
    local tex = sid and C_Spell.GetSpellTexture(sid)
    if type(tex) == "nil" then tex = C.Element(f.cooldownID).icon end
    icon:SetTexture(tex)
    return phase, d
end

function Own.Update(f)
    local C = ns.CdmCustom
    local element = f.totem and C ~= nil and C.Element(f.cooldownID) ~= nil
    local phase, slotDur
    if element then phase, slotDur = Own.FollowSlot(f, f.Icon) end
    local sid = f.cooldownInfo and f.cooldownInfo.spellID
    if not sid or type(f.Cooldown) ~= "table" then return end
    local ok, dur
    -- Totem and buff lifts the time over the buff's button; anything else has it
    -- back at its own level, at full opacity.
    f.cdLevel = f.cdLevel or (f.Cooldown:GetFrameLevel() - f:GetFrameLevel())
    local buffed = f.totem == true and f.totemBuff == true
    f.Cooldown:SetFrameLevel(f:GetFrameLevel() + (buffed and Own.TOTEM_TIME_LEVEL or f.cdLevel))
    if not buffed then f.Icon:SetAlpha(1) end
    if phase == "cooldown" then            -- an element's cooldown totem, gone: its cooldown
        ok, dur = pcall(C_Spell.GetSpellCooldownDuration, sid)
    elseif f.totem and C then              -- a totem: its time while it stands
        ok = true
        if element then dur = slotDur else dur = C.TotemUp(sid) end
        -- Totem and buff: dimmed while the totem stands, under the buff's button,
        -- which covers it in full color while you have the buff. The time stays on top.
        -- An element dims only for a standing totem whose buff is known.
        local dims = f.totemBuff and (not element or C.TotemBuffKnown(sid))
        f.Icon:SetAlpha(dims and type(dur) ~= "nil" and Own.TOTEM_DIM or 1)
    elseif C and C.ItemOf(f.cooldownID) then   -- an item added by ID: the item's cooldown and count
        local _, d = C.ItemCooldown(f.cooldownID)
        ok, dur = true, d
        local n = C.ItemCount(f.cooldownID)
        f.ChargeCount.Current:SetText(n and tostring(n) or "")
    else
        ok, dur = pcall(C_Spell.GetSpellCooldownDuration, sid)
    end
    if ok and type(dur) ~= "nil" then
        pcall(f.Cooldown.SetCooldownFromDurationObject, f.Cooldown, dur, true)
    else
        f.Cooldown:Clear()
    end
end

function Own.UpdateAll()
    for _, f in pairs(frames) do
        if f:IsShown() then Own.Update(f) end
    end
    -- Daylight UI's cooldown bars (CdmBars) follow the same events.
    if ns.CdmBars then ns.CdmBars.UpdateAll() end
end

function Own.Acquire(id, parent)
    local f = frames[id]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f.Icon = f:CreateTexture(nil, "ARTWORK")
        f.Icon:SetAllPoints()
        f.Icon:SetTexture(134400)
        f.Cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.Cooldown:SetAllPoints()
        -- A count (for an item added by ID) in the game items' spot and shape, so
        -- the skin's count styling reaches it. It sits over the swipe rather than
        -- on the Cooldown, which hides when cleared.
        local over = CreateFrame("Frame", nil, f)
        over:SetAllPoints(f)
        over:SetFrameLevel(f.Cooldown:GetFrameLevel() + 2)
        local count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        f.ChargeCount = { Current = count }
        f.cooldownID = id
        f.cooldownInfo = {}
        if ns.Cooldowns and ns.Cooldowns.SkinItem then DUI.SafeCall(ns.Cooldowns.SkinItem, f) end
        frames[id] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    -- The game may not have the spell's info yet at login, so keep asking until it
    -- does. With no spell (a trinket slot, a potion) use the item's icon.
    if not f.cooldownInfo.spellID then
        f.cooldownInfo.spellID = Own.SpellOf(id)
        local _, tex = Own.Look(id)
        if type(tex) ~= "nil" then f.Icon:SetTexture(tex) end
    end
    -- Coming back from "Hide out of combat" (Rows set it to 0). The effects set
    -- their own alpha after this.
    f:SetAlpha(1)
    f:Show()
    Own.Update(f)
    return f
end

function Own.ReleaseExcept(used, usedHolds)
    for id, f in pairs(frames) do
        if not used[id] and f:IsShown() then
            if ns.CdmEffects then ns.CdmEffects.Clear(f) end
            f:Hide()
        end
    end
    for key, f in pairs(holds) do
        if not (usedHolds and usedHolds[key]) and f:IsShown() then
            if f.Bar and ns.CdmEffects then ns.CdmEffects.Flash(f, f.Bar, false) end
            f:Hide()
        end
    end
end

-- "Show missing buffs": a stand-in for a buff or bar the game is hiding right now. An
-- icon is the spell's texture grayed; a bar is an empty skinned bar with the name.
function Own.Placeholder(id, parent, kind, bright)
    local key = id .. kind
    local f = holds[key]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f.Icon = f:CreateTexture(nil, "ARTWORK")
        f.Icon:SetAllPoints()
        f.Icon:SetDesaturated(true)
        f.Icon:SetAlpha(0.5)
        if kind == "bar" then
            f.Bar = CreateFrame("StatusBar", nil, f)
            f.Bar:SetAllPoints()
            f.Bar:SetMinMaxValues(0, 1)
            f.Bar:SetValue(0)
            DUI.Style.TrackBar(f.Bar, nil, ns.MEDIA.bars.cdm)
            -- Daylight UI's own dark empty bar. The game bars' skin leaves its backdrop
            -- untinted here, and it came out white.
            local back = f.Bar:CreateTexture(nil, "BACKGROUND", nil, -8)
            back:SetAllPoints()
            DUI.Style.TrackBack(back, ns.MEDIA.bars.cdm)
            back:SetVertexColor(0, 0, 0, DUI.Style.BAR_BACK_ALPHA)
            f.Back = back
            DUI.SafeCall(DUI.Style.Shell, f, { borderPx = ns.Cooldowns and ns.Cooldowns.BarBorder or 1,
                heavyMinPx = ns.Cooldowns and ns.Cooldowns.BAR_HEAVY_MIN })
            f.Text = f.Bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f.Text:SetPoint("LEFT", f.Bar, "LEFT", 4, 0)
            f.Text:SetTextColor(DUI.Style.INK.OFF[1], DUI.Style.INK.OFF[2], DUI.Style.INK.OFF[3])
        end
        if kind == "bar" then
            f.Icon:SetAlpha(0)
        elseif ns.Cooldowns and ns.Cooldowns.SkinItem then
            -- An icon wears the layout's look like Daylight UI's cooldown icons: border,
            -- crop, shade and shape, with the grayed icon inside the border.
            DUI.SafeCall(ns.Cooldowns.SkinItem, f)
        end
        f.placeholder = true
        holds[key] = f
    elseif f:GetParent() ~= parent then
        f:SetParent(parent)
    end
    if not f.set then
        local name, tex = Own.Look(id)
        if type(tex) ~= "nil" then
            f.Icon:SetTexture(tex)
            if kind == "bar" and name then f.Text:SetText(name) end
            f.set = true
        end
    end
    if kind ~= "bar" and (f.bright or false) ~= (bright == true) then
        -- With Hide (Buff up) too, the stand-in is only a reminder, in full color.
        f.bright = bright == true
        f.Icon:SetDesaturated(not f.bright)
        local from, to = f.bright and 0.5 or 1, f.bright and 1 or 0.5
        DUI.Motion.Tween(f.Icon, from, to, DUI.Motion.FAST, function(v) f.Icon:SetAlpha(v) end)
    end
    if kind == "bar" then
        -- The spell's own bar colors, read each time so a change shows.
        local set = ns.CdmData.Current()
        local b = set and set.pieces and set.pieces[id]
        local Fx, S = ns.CdmEffects, DUI.Style
        local mode = Fx.Get(b, "barMode")
        local c = Fx.Get(b, "barColor")
        local pair = Fx.Get(b, "barGradient")
        if mode == "solid" and type(c) == "table" then
            f.Bar:SetStatusBarColor(c[1], c[2], c[3], 1)
        elseif mode == "gradient" and type(pair) == "table" and DUI.Gradients then
            f.Bar:SetStatusBarColor(DUI.Gradients.MidOf(pair.lo, pair.hi))
        else
            f.Bar:SetStatusBarColor(1, 1, 1, 1)
        end
        local back, v
        if ns.Cooldowns then
            back, v = ns.Cooldowns.BackOf(b, b and ns.CdmData.PieceBlock(set, id))
            ns.Cooldowns.OwnBack(S.GetShell(f), back ~= nil)
            ns.Cooldowns.PlaceName(f.Text, f.Bar, Fx.Get(b, "showName") ~= false, Fx.Get(b, "nameAlign") == "center")
        end
        if back then
            ns.Cooldowns.PaintBack(f.Back, back, v)
        else
            f.Back:SetVertexColor(0, 0, 0, S.BAR_BACK_ALPHA)
        end
        Fx.Flash(f, f.Bar, Fx.Get(b, "inactiveFlash") == true)
    end
    f:Show()
    return f
end

function Own.PlaceholderFrame(id, kind) return holds[id .. kind] end

-- Cooldown and charge events: CdmEffects' single pass on the next frame (Fx.Soon)
-- updates Daylight UI's icons too.
