-- What the missing-buffs row looks for: the group buffs (who gives them, every
-- rank of the single and the group version), each class's own buff, weapon
-- oils, poisons and imbues, and a few consumables. Spell and item ids are the
-- classic ones; a buff is matched by the client's own name for its ids, so
-- another rank, another caster's copy or another language still counts.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local Data = {}
BL.ReminderData = Data

local I = "Interface\\Icons\\"

-- "Light" alone is also a color elsewhere, so the blessing has a key of its
-- own: a language can name the blessing without changing the color too.
local lightWord = L["Light (Blessing of Light)"]
if lightWord == "Light (Blessing of Light)" then lightWord = "Light" end

-- Who wants a buff that only some classes use.
Data.MANA_USERS = { DRUID = true, HUNTER = true, MAGE = true, PALADIN = true, PRIEST = true, SHAMAN = true, WARLOCK = true }
-- Battle Shout raises melee attack power only: a hunter shoots.
Data.MELEE = { DRUID = true, PALADIN = true, ROGUE = true, SHAMAN = true, WARRIOR = true }

-- Each group buff, as EllesmereUI's WoW Forever families have them: the class
-- that gives it, a short name, its icon, names (the spells whose names cover
-- every rank, the group version and other casters' copies), the single and
-- group versions lowest rank first, and who benefits. talent: a talent spell,
-- so another priest may not have it (never asked of others). seen: asked for
-- only when someone in the group already wears it (Shadow Protection is for
-- some fights). blessing: one per paladin, asked for by your class, never
-- given from the row. self: cast on yourself (a shout).
Data.FAMILIES = {
    { key = "fortitude", class = "PRIEST", short = L["Fortitude"], icon = I .. "Spell_Holy_WordFortitude",
      names = { 1243, 21562 }, single = { 1243, 1244, 1245, 2791, 10937, 10938 }, group = { 21562, 21564 } },
    { key = "wild", class = "DRUID", short = L["Mark of the Wild"], icon = I .. "Spell_Nature_Regeneration",
      names = { 1126, 21849 }, single = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, group = { 21849, 21850 } },
    { key = "intellect", class = "MAGE", short = L["Intellect"], icon = I .. "Spell_Holy_MagicalSentry", benefit = "mana",
      names = { 1459, 23028 }, single = { 1459, 1460, 1461, 10156, 10157 }, group = { 23028 } },
    { key = "spirit", class = "PRIEST", short = L["Spirit"], icon = I .. "Spell_Holy_DivineSpirit", benefit = "mana",
      talent = true, names = { 14752, 27681 }, single = { 14752, 14818, 14819, 27841 }, group = { 27681 } },
    { key = "shadow", class = "PRIEST", short = L["Shadow Protection"], icon = I .. "Spell_Shadow_AntiShadow", seen = true,
      names = { 976, 27683 }, single = { 976, 10957, 10958 }, group = { 27683 } },
    { key = "shout", class = "WARRIOR", short = L["Battle Shout"], icon = I .. "Ability_Warrior_BattleShout",
      benefit = "melee", self = true,
      names = { 6673 }, single = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, group = {} },
    { key = "might", class = "PALADIN", short = L["Might"], icon = I .. "Spell_Holy_FistOfJustice", blessing = true,
      names = { 19740, 25782 }, single = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, group = { 25782, 25916 } },
    { key = "wisdom", class = "PALADIN", short = L["Wisdom"], icon = I .. "Spell_Holy_SealOfWisdom", blessing = true,
      names = { 19742, 25894 }, single = { 19742, 19850, 19852, 19853, 19854, 25290 }, group = { 25894, 25918 } },
    { key = "kings", class = "PALADIN", short = L["Kings"], icon = I .. "Spell_Magic_MageArmor", blessing = true,
      names = { 20217, 25898 }, single = { 20217 }, group = { 25898 } },
    { key = "salvation", class = "PALADIN", short = L["Salvation"], icon = I .. "Spell_Holy_SealOfSalvation", blessing = true,
      names = { 1038, 25895 }, single = { 1038 }, group = { 25895 } },
    { key = "light", class = "PALADIN", short = lightWord, icon = I .. "Spell_Holy_PrayerOfHealing02", blessing = true,
      names = { 19977, 25890 }, single = { 19977, 19978, 19979 }, group = { 25890 } },
    { key = "sanctuary", class = "PALADIN", short = L["Sanctuary"], icon = I .. "Spell_Nature_LightningShield", blessing = true,
      names = { 20911, 25899 }, single = { 20911, 20912, 20913, 20914 }, group = { 25899 } },
}

-- Which blessings to ask for first, by your class; a tank skips Salvation
-- (it lowers threat). Classes not listed use mana and want Wisdom first.
Data.BLESSING_ORDER = {
    WARRIOR = { "might", "kings", "salvation", "light" },
    ROGUE = { "might", "kings", "salvation", "light" },
    HUNTER = { "might", "kings", "wisdom", "salvation" },
    default = { "wisdom", "kings", "salvation", "might" },
}

-- Your class's own buff. Each entry: its lines (only one can be up; any of
-- them counts), each line's ranks lowest first. own: only your own copy
-- counts (a paladin's aura or a hunter's aspect from someone else isn't yours).
Data.SELF = {
    HUNTER = { { key = "aspect", short = L["Aspect"], own = true, lines = {
        { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }, -- Hawk
        { 13163 },                                            -- Monkey
        { 5118 },                                             -- Cheetah
        { 13159 },                                            -- Pack
        { 20043, 20190 },                                     -- Wild
        { 13161, 1299445, 1299446, 1299447 },                 -- Beast
        { 34074, 415423 },                                    -- Viper
        { 469145 },
    } } },
    PALADIN = { { key = "aura", short = L["Aura"], own = true, lines = {
        { 465, 10290, 643, 10291, 1032, 10292, 10293 },       -- Devotion
        { 7294, 10298, 10299, 10300, 10301 },                 -- Retribution
        { 19746 },                                            -- Concentration
        { 19876, 19895, 19896 },                              -- Shadow Resistance
        { 19888, 19897, 19898 },                              -- Frost Resistance
        { 19891, 19899, 19900 },                              -- Fire Resistance
    } } },
    PRIEST = { { key = "innerfire", short = L["Inner Fire"], lines = { { 588, 7128, 602, 1006, 10951, 10952 } } } },
    SHAMAN = { { key = "shield", short = L["Lightning Shield"], lines = {
        { 324, 325, 905, 945, 8134, 10431, 10432 }, { 408510 } } } },
    WARLOCK = { { key = "demonarmor", short = L["Demon Armor"], lines = {
        { 687, 696, 706, 1086, 11733, 11734, 11735 } } } },
    MAGE = { { key = "armor", short = L["Armor"], lines = {
        { 168, 7300, 7301 },                                  -- Frost Armor
        { 7302, 7320, 10219, 10220 },                         -- Ice Armor
        { 6117, 22782, 22783 },                               -- Mage Armor
    } } },
}

-- Rogue poisons (items), best kind first, each best rank first.
Data.POISONS = {
    8928, 8927, 8926, 6950, 6949, 6947,   -- Instant
    20844, 8985, 8984, 2893, 2892,        -- Deadly
    10922, 10921, 10920, 10918,           -- Wound
    9186, 6951, 5237,                     -- Mind-numbing
    3776, 3775,                           -- Crippling
}

-- Shaman imbues (spells), each lowest rank first. Rockbiter is the fallback.
Data.IMBUES = {
    { key = "rockbiter", ids = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 } },
    { key = "windfury", ids = { 8232, 8235, 10486, 16362 } },
    { key = "flametongue", ids = { 8024, 8027, 8030, 16339, 16341, 16342 } },
    { key = "frostbrand", ids = { 8033, 8038, 10456, 16355, 16356 } },
}

-- Stones and oils (items), best first. kind: blade = only on an edged weapon,
-- blunt = only on a blunt one, nil = any weapon. Warlock stones go on the main
-- hand only (mainOnly).
Data.STONES = {
    { id = 23123 }, { id = 20749 }, { id = 20748 }, { id = 18262, kind = "blade" }, { id = 23122, kind = "blade" },
    { id = 12404, kind = "blade" }, { id = 12643, kind = "blunt" }, { id = 20750 }, { id = 20747 },
    { id = 7964, kind = "blade" }, { id = 7965, kind = "blunt" }, { id = 2871, kind = "blade" }, { id = 3241, kind = "blunt" },
    { id = 20746 }, { id = 2863, kind = "blade" }, { id = 3240, kind = "blunt" }, { id = 20745 }, { id = 20744 },
    { id = 2862, kind = "blade" }, { id = 3239, kind = "blunt" }, { id = 3824 }, { id = 3829 },
    { id = 287978, kind = "blade" }, { id = 287979 }, { id = 287980, kind = "blade" },
    { id = 13701, mainOnly = true }, { id = 13700, mainOnly = true }, { id = 13699, mainOnly = true }, { id = 1254, mainOnly = true },
    { id = 13603, mainOnly = true }, { id = 13602, mainOnly = true }, { id = 5522, mainOnly = true },
}

-- Weapon subclasses (Enum.ItemWeaponSubclass) by edge.
Data.BLADE = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [15] = true }
Data.BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }

-- Consumables, each behind its own switch (off by default).
-- Well Fed by name, plus the foods whose buff has another name.
Data.FOOD = { 19705, 18192, 18194, 22730, 25661, 18125, 18141 }
Data.CAMP = 1229741
Data.SLEEPING_BAG = { buff = 429959, item = 211527, stacks = 3 }
-- Scrolls per stat, best first. The buff is the scroll's own spell; a group
-- buff of the same stat (cover) replaces it, so then none is asked for.
Data.SCROLLS = {
    { key = "intellect", cover = "intellect", items = { 10308, 4419, 2290, 955 } },
    { key = "stamina", cover = "fortitude", items = { 10307, 4422, 1711, 1180 } },
    { key = "spirit", cover = "spirit", items = { 10306, 4424, 1712, 1181 } },
    { key = "strength", items = { 10310, 4426, 2289, 954 } },
    { key = "agility", items = { 10309, 4425, 1477, 3012 } },
    { key = "protection", items = { 10305, 4421, 1478, 3013 } },
}

-- What the test mode and the options' preview show: the mock-up's four tiles.
Data.SAMPLE = {
    { key = "intellect", kind = "give", have = 3, total = 5, short = L["Intellect"], icon = I .. "Spell_Holy_MagicalSentry" },
    { key = "fortitude", kind = "get", short = L["Fortitude"], icon = I .. "Spell_Holy_WordFortitude" },
    { key = "armor", kind = "self", short = L["Mage Armor"], icon = I .. "Spell_MageArmor" },
    { key = "weapon:main", kind = "weapon", short = L["Wizard Oil"], icon = I .. "INV_Potion_104", left = 240 },
}

local byKey = {}
for _, b in ipairs(Data.FAMILIES) do
    byKey[b.key] = b
    b.ids = {}
    for _, id in ipairs(b.single) do b.ids[#b.ids + 1] = id end
    for _, id in ipairs(b.group or {}) do b.ids[#b.ids + 1] = id end
end
Data.byKey = byKey
