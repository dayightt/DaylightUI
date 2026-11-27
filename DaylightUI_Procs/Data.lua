-- What Proc Alerts knows: the twelve flare designs, the animations, and every
-- proc it watches, by class. Spell ids are lowest rank first; the highest rank
-- the player knows is the one read.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Data = {}
ns.Data = Data

-- Where a design sits around the character. "side" and "across" are one
-- painted left piece drawn twice, the right one mirrored; the rest are one
-- centered texture.
Data.DESIGNS = {
    wings   = { name = L["Wings"], spot = "side" },
    talons  = { name = L["Talons"], spot = "side" },
    pillars = { name = L["Pillars"], spot = "side" },
    shards  = { name = L["Shards"], spot = "side" },
    flames  = { name = L["Flames"], spot = "side" },
    bolt    = { name = L["Lightning"], spot = "side" },
    comet   = { name = L["Comets"], spot = "across" },
    crown   = { name = L["Crown"], spot = "above" },
    sigil   = { name = L["Sigil"], spot = "above" },
    sun     = { name = L["Sunrise"], spot = "sun" },
    ring    = { name = L["Rune ring"], spot = "feet" },
    wave    = { name = L["Shockwave"], spot = "feet" },
}
Data.DESIGN_ORDER = { "wings", "talons", "pillars", "shards", "flames", "bolt", "comet", "crown", "sigil", "sun", "ring", "wave" }

-- Each spot's piece, in UI units at scale 1 from the middle of the holder (the
-- character). `edge` = the inner edge's distance from the middle, `step` = how
-- far each extra lane moves out (or up).
Data.SPOTS = {
    side   = { w = 256, h = 256, edge = 64, step = 64, y = 10, mirrored = true, anchor = "side" },
    across = { w = 176, h = 176, edge = 36, step = 60, y = 96, mirrored = true, anchor = "bottom" },
    above  = { w = 160, h = 160, y = 104, step = 56, anchor = "bottom" },
    sun    = { w = 208, h = 208, y = 70, step = 120, anchor = "center" },
    feet   = { w = 304, h = 304, y = -118, grow = 1.34, anchor = "center" },
}

-- While a flare is up (Flares.KINDS has the numbers). Every one but Still
-- flickers like flame on top of its own motion. strike: the liveliest flame;
-- breathe: dims slowly; pulse: its core beats; impact: sends out a wave;
-- flash: a gleam runs from base to tip; still: the painting doesn't move.
Data.ANIMS = {
    strike  = { name = L["Strike"] },
    breathe = { name = L["Breathe"] },
    pulse   = { name = L["Pulse"] },
    impact  = { name = L["Impact"] },
    flash   = { name = L["Flash"] },
    still   = { name = L["Still"] },
}
Data.ANIM_ORDER = { "strike", "breathe", "pulse", "impact", "flash", "still" }

-- Spell ranks, lowest first.
local R = {
    shadowbolt = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 },
    soulfire   = { 6353, 17924 },
    immolate   = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 },
    searing    = { 5676, 17919, 17920, 17921, 17922, 17923 },
    conflag    = { 17962, 18930, 18931, 18932, 1293817 },
    overpower  = { 7384, 7887, 11584, 11585 },
    revenge    = { 6572, 6574, 7379, 11600, 11601, 25288 },
    shieldblock = { 2565 },
    execute    = { 5308, 20658, 20660, 20661, 20662 },
    victory    = { 34428, 402927 },
    frostbolt  = { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304 },
    fireball   = { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306 },
    missiles   = { 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345 },
    pyroblast  = { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809 },
    wrath      = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 },
    starfire   = { 2912, 8949, 8950, 8951, 9875, 9876, 25298 },
    touch      = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },
    claw       = { 1082, 3029, 5201, 9849, 9850 },
    shred      = { 5221, 6800, 8992, 9829, 9830 },
    maul       = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 },
    lightning  = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208 },
    chain      = { 421, 930, 2860, 10605 },
    holylight  = { 635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292 },
    flash      = { 19750, 19939, 19940, 19941, 19942, 19943 },
    hammer     = { 24275, 24274, 24239 },
    nova       = { 15237, 15430, 15431, 27799, 27800, 27801 },
    smite      = { 585, 591, 598, 984, 1004, 6060, 10933, 10934 },
    lesserheal = { 2050, 2052, 2053 },
    riposte    = { 14251 },
    ambush     = { 8676, 8724, 8725, 11267, 11268, 11269 },
    garrote    = { 703, 8631, 8632, 8633, 11289, 11290 },
    mongoose   = { 1495, 14269, 14270, 14271 },
    counter    = { 19306, 20909, 20910 },
}
Data.RANKS = R

-- Shadow Bolt and Searing Pain also renew Decimation's usual ratio.
local decimRenew = {}
for _, id in ipairs(R.shadowbolt) do decimRenew[#decimRenew + 1] = id end
for _, id in ipairs(R.searing) do decimRenew[#decimRenew + 1] = id end

-- Every proc. mode: how it's seen (Engine.lua). spell: the proc's own spell (its
-- name is shown). cast: the spell it boosts. dur: its usual length in seconds.
-- cd + holdCd: hidden for that long after a cast. noPower = false: short of
-- power doesn't count. combatOnly: the default of "Only in combat". off: not
-- shown until ticked. sound "none": the default sound (buffs only the game sees).
-- gameAlertOff: the game alerts for it too, and it has a signal of its own, so
-- the game's art (which would double the flare) is turned off while it's watched.
Data.PROCS = {
    -- Warlock
    { key = "trance", class = "WARLOCK", spell = 17941, mode = "trance", design = "wings", anim = "pulse", dur = 10,
      cast = R.shadowbolt, overlayIds = { 17941 }, gameAlertOff = true },
    { key = "decimation", class = "WARLOCK", spell = 440870, mode = "faster", design = "flames", anim = "pulse", dur = 10,
      cast = R.soulfire, refs = { R.shadowbolt, R.immolate }, renew = decimRenew },
    { key = "conflagrate", class = "WARLOCK", spell = 1293817, mode = "usable", design = "sigil", anim = "pulse", dur = 5,
      cast = R.conflag, noPower = false, onTarget = true, cd = 10, holdCd = true, noTimer = true, combatOnly = true, off = true },
    -- Warrior
    { key = "overpower", class = "WARRIOR", spell = 7384, mode = "usable", design = "talons", anim = "impact", dur = 5,
      cast = R.overpower, cd = 5, holdCd = true, combatOnly = true },
    { key = "revenge", class = "WARRIOR", spell = 6572, mode = "usable", design = "crown", anim = "impact", dur = 5,
      cast = R.revenge, cd = 5, combatOnly = true },
    { key = "shieldblock", class = "WARRIOR", spell = 2565, mode = "usable", design = "ring", anim = "pulse", dur = 5,
      cast = R.shieldblock, noPower = false, cd = 5, holdCd = true, noTimer = true, combatOnly = true, sound = "none" },
    { key = "execute", class = "WARRIOR", spell = 5308, mode = "usable", design = "comet", anim = "pulse", dur = 5,
      cast = R.execute, noPower = false, onTarget = true, hideOnCast = false, noTimer = true },
    { key = "victoryrush", class = "WARRIOR", spell = 402927, mode = "usable", design = "sun", anim = "pulse", dur = 20,
      cast = R.victory, cd = 30, holdCd = true, combatOnly = false },
    -- Mage
    { key = "clearcasting", class = "MAGE", spell = 12536, mode = "free", design = "sun", anim = "pulse", dur = 15,
      watch = { R.frostbolt, R.fireball } },
    { key = "missilebarrage", class = "MAGE", spell = 400588, mode = "free", design = "comet", anim = "pulse", dur = 15,
      watch = { R.missiles }, unless = "clearcasting" },
    { key = "hotstreak", class = "MAGE", spell = 400624, mode = "faster", design = "flames", anim = "pulse", dur = 20,
      cast = R.pyroblast, refs = { R.fireball }, threshold = 0.46, stacks = 3, stackAt = { 0.88, 0.66 } },
    -- Fingers of Frost changes nothing an addon can read, and the game's alert
    -- event alone missed it for players: the client shows it from its buff (Forever
    -- has two), and the alert only plays its sound.
    { key = "fingers", class = "MAGE", spell = 400670, mode = "aura", design = "shards", anim = "pulse", dur = 15,
      buffIds = { 400670, 400669 }, overlayIds = { 400670, 400669, 400647, 44544 }, noTimer = true },
    { key = "arcaneblast", class = "MAGE", spell = 400574, mode = "casts", design = "sigil", anim = "pulse", dur = 18,
      cast = { 400574 }, stacks = 4, fromStacks = 1 },
    -- Druid
    { key = "omen", class = "DRUID", spell = 16864, mode = "free", design = "sun", anim = "pulse", dur = 15,
      watch = { R.wrath, R.touch, R.claw, R.shred, R.maul } },
    { key = "eclipse", class = "DRUID", spell = 409813, mode = "faster", design = "crown", anim = "pulse", dur = 15,
      cast = R.starfire, refs = { R.wrath }, selfCheck = true, fullCut = 1.75, renew = R.wrath, stacks = 4, perCharge = 0.5 },
    { key = "naturesgrace", class = "DRUID", spell = 16880, mode = "aura", design = "pillars", anim = "breathe", dur = 3,
      buffIds = { 16886 }, sound = "none" },
    -- Shaman
    { key = "maelstrom", class = "SHAMAN", spell = 408498, mode = "instant", design = "bolt", anim = "pulse", dur = 30,
      cast = R.lightning, stacks = 5, perStack = 0.2 },
    { key = "elemfocus", class = "SHAMAN", spell = 16164, mode = "free", design = "sigil", anim = "pulse", dur = 15,
      watch = { R.lightning, R.chain }, skipInstant = true },
    { key = "stormstrike", class = "SHAMAN", spell = 1223031, mode = "reset", design = "wave", anim = "impact", dur = 4,
      cast = { 17364 }, cd = 8, combatOnly = true },
    -- Paladin
    { key = "infusion", class = "PALADIN", spell = 426065, mode = "faster", design = "sun", anim = "pulse", dur = 15,
      cast = R.holylight, refs = { R.flash }, selfCheck = true },
    { key = "hammer", class = "PALADIN", spell = 24275, mode = "usable", design = "comet", anim = "pulse", dur = 5,
      cast = R.hammer, noPower = false, onTarget = true, cd = 6, holdCd = true, noTimer = true },
    { key = "redoubt", class = "PALADIN", spell = 20127, mode = "aura", design = "ring", anim = "breathe", dur = 10,
      buffIds = { 20128, 20131, 20132, 20133, 20134 }, sound = "none" },
    { key = "vengeance", class = "PALADIN", spell = 20049, mode = "aura", design = "flames", anim = "breathe", dur = 30,
      buffIds = { 20050, 20052, 20053, 20054, 20055 }, stacks = 5, sound = "none" },
    { key = "reckoning", class = "PALADIN", spell = 20177, mode = "aura", design = "talons", anim = "breathe", dur = 15,
      buffIds = { 20178 }, stacks = 4, noTimer = true, sound = "none" },
    { key = "sealecho", class = "PALADIN", spell = 1310735, mode = "aura", design = "wings", anim = "breathe", dur = 15,
      buffIds = { 1311704, 1311703, 1311701, 1311705, 1328198, 1328206 }, stacks = 3, sound = "none" },
    -- Priest
    { key = "searinglight", class = "PRIEST", label = L["Searing Light"], mode = "free", design = "sun", anim = "pulse", dur = 15,
      watch = { R.nova }, others = { R.smite, R.lesserheal } },
    { key = "martyrdom", class = "PRIEST", spell = 14531, mode = "aura", design = "pillars", anim = "breathe", dur = 6,
      buffIds = { 27828, 14743 }, sound = "none" },
    -- Rogue
    { key = "riposte", class = "ROGUE", spell = 14251, mode = "usable", design = "talons", anim = "impact", dur = 5,
      cast = R.riposte, cd = 6, holdCd = true, combatOnly = true },
    { key = "ghostly", class = "ROGUE", spell = 14278, mode = "usable", design = "wings", anim = "flash", dur = 7,
      cast = R.ambush, also = R.garrote, notStealthed = true, openCast = { 14278 } },
    { key = "remorseless", class = "ROGUE", spell = 14144, mode = "aura", design = "sigil", anim = "flash", dur = 20,
      buffIds = { 14143, 14149 }, combatOnly = false, sound = "none" },
    -- Hunter
    { key = "mongoose", class = "HUNTER", spell = 1495, mode = "usable", design = "talons", anim = "impact", dur = 5,
      cast = R.mongoose, cd = 5, holdCd = true, combatOnly = true },
    { key = "counterattack", class = "HUNTER", spell = 19306, mode = "usable", design = "wings", anim = "impact", dur = 5,
      cast = R.counter, cd = 5, holdCd = true, combatOnly = true },
    { key = "rapidkilling", class = "HUNTER", spell = 415405, mode = "aura", design = "comet", anim = "flash", dur = 20,
      buffIds = { 415407, 415817 }, combatOnly = false, sound = "none" },
    { key = "quickshots", class = "HUNTER", spell = 6150, mode = "aura", design = "bolt", anim = "breathe", dur = 12,
      buffIds = { 6150 }, sound = "none" },
    { key = "quickstrikes", class = "HUNTER", spell = 469144, mode = "aura", design = "shards", anim = "breathe", dur = 12,
      buffIds = { 469144 }, sound = "none" },
    -- Weapons and enchants, any class
    { key = "edward", class = "GEAR", item = 2243, spell = 18803, mode = "aura", design = "pillars", anim = "flash", dur = 4,
      buffIds = { 18803 }, off = true, sound = "none" },
    { key = "revelation", class = "GEAR", spell = 1248805, mode = "aura", design = "shards", anim = "flash", dur = 15,
      buffIds = {}, buffNames = { "Revelation" }, off = true, sound = "none" },
    { key = "insight", class = "GEAR", spell = 1248757, mode = "aura", design = "wave", anim = "breathe", dur = 10,
      buffIds = {}, buffNames = { "Insight" }, off = true, sound = "none" },
}

Data.BY = {}
for _, p in ipairs(Data.PROCS) do Data.BY[p.key] = p end

-- An alert another addon adds through DaylightUI.API: it's looked up like any
-- proc (its look, its name), but never joins PROCS, so the engine, the aura
-- container and the options page leave it to the addon that shows it.
function Data.AddPlugin(p) Data.BY[p.key] = p end

Data.MODES = { trance = true, faster = true, usable = true, free = true, overlay = true, casts = true,
               aura = true, instant = true, reset = true }

-- The proc's name as the game says it: its spell's (or item's) name, read
-- when asked so it's in the player's language.
function Data.Name(p)
    if type(p) == "string" then p = Data.BY[p] end
    if not p then return "" end
    if p.label then return p.label end
    local name
    if p.item and C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(p.item) end
    if not name and p.spell and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(p.spell) end
    if type(name) ~= "string" or name == "" then return p.key end
    return name
end

-- The player's class token, or nil before it's known.
function Data.Class()
    local _, token = UnitClass("player")
    if type(token) == "string" then return token end
end

-- Whether this character has what a gear proc comes from: the item worn or
-- in the bags. An enchant with no buff Daylight UI can watch for counts as
-- missing, since its alert could never show.
function Data.Have(p)
    if p.class ~= "GEAR" then return true end
    if #(p.buffIds or {}) == 0 then return false end
    if not p.item then return true end
    local I = C_Item
    if not I then return false end
    if I.IsEquippedItem and I.IsEquippedItem(p.item) == true then return true end
    local n = I.GetItemCount and I.GetItemCount(p.item)
    return type(n) == "number" and n > 0
end

-- The procs Proc Alerts may watch for this character: its class's, then the gear ones.
function Data.Mine()
    local class, out = Data.Class(), {}
    for _, p in ipairs(Data.PROCS) do
        if p.class == class then out[#out + 1] = p end
    end
    for _, p in ipairs(Data.PROCS) do
        if p.class == "GEAR" then out[#out + 1] = p end
    end
    return out
end
