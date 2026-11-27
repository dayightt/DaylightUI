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
    { key = "wild", class = "DRUID", short = L["Mark"], icon = I .. "Spell_Nature_Regeneration",
      names = { 1126, 21849 }, single = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, group = { 21849, 21850 } },
    { key = "intellect", class = "MAGE", short = L["Intellect"], icon = I .. "Spell_Holy_MagicalSentry", benefit = "mana",
      names = { 1459, 23028 }, single = { 1459, 1460, 1461, 10156, 10157 }, group = { 23028 },
      stronger = { [11396] = 25 } },
    { key = "spirit", class = "PRIEST", short = L["Spirit"], icon = I .. "Spell_Holy_DivineSpirit", benefit = "mana",
      talent = true, names = { 14752, 27681 }, single = { 14752, 14818, 14819, 27841 }, group = { 27681 } },
    { key = "shadow", class = "PRIEST", short = L["Shadow"], icon = I .. "Spell_Shadow_AntiShadow", seen = true,
      names = { 976, 27683 }, single = { 976, 10957, 10958 }, group = { 27683 } },
    { key = "shout", class = "WARRIOR", short = L["Shout"], icon = I .. "Ability_Warrior_BattleShout",
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

-- How much of its stat each raid buff rank gives (EllesmereUI's numbers for
-- WoW Forever): a stronger buff of the same stat counts as the raid buff when
-- it beats the best rank you know, and a scroll or elixir must beat it.
Data.AMOUNTS = {
    [1243] = 4, [1244] = 10, [1245] = 26, [2791] = 42, [10937] = 56, [10938] = 70, [13864] = 3, [23947] = 43,
    [23948] = 54, [21562] = 56, [21564] = 70, [450086] = 43,
    [1459] = 2, [1460] = 7, [1461] = 15, [10156] = 22, [10157] = 31, [23028] = 31, [11396] = 25,
    [14752] = 17, [14818] = 23, [14819] = 33, [16875] = 40, [27841] = 40, [27681] = 40,
}

-- Which blessings to ask for first, by your class; a tank skips Salvation
-- (it lowers threat). Classes not listed use mana and want Wisdom first.
Data.BLESSING_ORDER = {
    WARRIOR = { "might", "kings", "salvation", "light" },
    ROGUE = { "might", "kings", "salvation", "light" },
    HUNTER = { "might", "kings", "wisdom", "salvation" },
    default = { "wisdom", "kings", "salvation", "might" },
}

-- Each class's own buffs, EllesmereUI's lists for WoW Forever. Each line is a
-- buff of which only one can be up, its ranks lowest first; the last line is
-- the strongest (what a click casts when no line was seen yet). on: ticked by
-- default. own: only your own copy counts (another hunter's aspect isn't
-- yours). ownMemory: only yours is remembered, anyone's holds the reminder
-- back (a blessing). also: ranks per line that count too (Greater Blessings).
-- label: the icon's short name (else the spell name's first word); menu: the
-- name in the options' list.
Data.CLASS_BUFFS = {
    DRUID = {
        { key = "thorns", lines = { { 467, 782, 1075, 8914, 9756, 9910 } } },
    },
    HUNTER = {
        { key = "aspect", label = L["Aspect"], on = true, own = true, lines = {
            { 34074, 415423 }, { 469145 },
            { 13159 }, { 5118 }, { 13163 },
            { 13161, 1299445, 1299446, 1299447 },
            { 20043, 20190 },
            { 13165, 14318, 14319, 14320, 14321, 14322, 25296 },
        } },
        { key = "trueshot", on = true, lines = { { 1299346, 1299348, 19506, 20905, 20906 } } },
    },
    PALADIN = {
        { key = "blessing", label = L["Blessing"], menu = L["Blessings"], on = true, ownMemory = true, lines = {
            { 19742, 19850, 19852, 19853, 19854, 25290 },
            { 20217 },
            { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
        }, also = { { 25894, 25918 }, { 25898 }, { 25782, 25916 } } },
        { key = "paladinaura", label = L["Aura"], menu = L["Important auras"], on = true, own = true, lines = {
            { 19891, 19899, 19900 },
            { 19888, 19897, 19898 },
            { 19876, 19895, 19896 },
            { 19746 },
            { 7294, 10298, 10299, 10300, 10301 },
            { 465, 10290, 643, 10291, 1032, 10292, 10293 },
        } },
        { key = "rfury", lines = { { 25780 } } },
    },
    PRIEST = {
        { key = "innerfire", on = true, lines = { { 588, 7128, 602, 1006, 10951, 10952 } } },
        { key = "shadowform", lines = { { 15473 } } },
    },
    SHAMAN = {
        { key = "shield", label = L["Shield"], on = true, lines = {
            { 324, 325, 905, 945, 8134, 10431, 10432 },
            { 408510 },
        } },
    },
    WARLOCK = {
        { key = "demonarmor", label = L["Armor"], on = true, lines = { { 687, 696, 706, 1086, 11733, 11734, 11735 } } },
    },
}

-- A mage's armors (Mage Armors, off by default): Frost, Ice, Mage.
Data.MAGE_ARMORS = { { 168, 7300, 7301 }, { 7302, 7320, 10219, 10220 }, { 6117, 22782, 22783 } }

-- A hunter's trackings by creature kind (UnitCreatureType's id 1-7): Beasts,
-- Dragonkin, Demons, Elementals, Giants, Undead, Humanoids.
Data.TRACKING = { 1494, 19879, 19878, 19880, 19882, 19884, 19883 }

-- Demonic Sacrifice (WoW Forever pairs each demon with its own buff): the
-- talent, and each demon's summon spell, buff and creature family id.
Data.DEMONIC_SACRIFICE = 18788
Data.SACRIFICE_DEMONS = {
    { key = "imp", summon = 688, buff = 18789, family = 23 },
    { key = "voidwalker", summon = 697, buff = 18792, family = 16 },
    { key = "succubus", summon = 712, buff = 18791, family = 17 },
    { key = "felhunter", summon = 691, buff = 18790, family = 15 },
}

-- Gathering trackers in cast order (Find Herbs, Find Minerals: self buffs on
-- WoW Forever), and a dwarf's Find Treasure (no aura, read from the minimap).
Data.GATHER_TRACKING = { 2383, 2580 }
Data.FIND_TREASURE = 2481

-- Weapon buffs, EllesmereUI's table in its Auto order. imbue: a poison, an
-- imbue or a warlock's stone (Self Buffs), else a stone or oil (Consumables).
-- items lowest rank first; spells a shaman's ranks; create: a warlock's spell
-- that makes the stone. weapon: only on a BLADED or BLUNT weapon. name: what
-- the options list it as (a shaman's by the client's name of its spell).
Data.WEAPON_BUFFS = {
    { key = "instant", name = L["Instant Poison"], imbue = true, class = "ROGUE", items = { 6947, 6949, 6950, 8926, 8927, 8928 } },
    { key = "deadly", name = L["Deadly Poison"], imbue = true, class = "ROGUE", items = { 2892, 2893, 8984, 8985, 20844 } },
    { key = "crippling", name = L["Crippling Poison"], imbue = true, class = "ROGUE", items = { 3775, 3776 } },
    { key = "mindnumbing", name = L["Mind-numbing Poison"], imbue = true, class = "ROGUE", items = { 5237, 6951, 9186 } },
    { key = "wound", name = L["Wound Poison"], imbue = true, class = "ROGUE", items = { 10918, 10920, 10921, 10922 } },
    { key = "windfury", imbue = true, class = "SHAMAN", spells = { 8232, 8235, 10486, 16362 } },
    { key = "flametongue", imbue = true, class = "SHAMAN", spells = { 8024, 8027, 8030, 16339, 16341, 16342 } },
    { key = "frostbrand", imbue = true, class = "SHAMAN", spells = { 8033, 8038, 10456, 16355, 16356 } },
    { key = "rockbiter", imbue = true, class = "SHAMAN", spells = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 } },
    { key = "firestone", name = L["Firestone"], imbue = true, class = "WARLOCK", items = { 1254, 13699, 13700, 13701 }, create = { 6366, 17951, 17952, 17953 } },
    { key = "spellstone", name = L["Spellstone"], imbue = true, class = "WARLOCK", items = { 5522, 13602, 13603 }, create = { 2362, 17727, 17728 } },
    { key = "sharpening", name = L["Sharpening Stone"], weapon = "BLADED", items = { 2862, 287978, 2863, 2871, 7964, 12404 } },
    { key = "weightstone", name = L["Weightstone"], weapon = "BLUNT", items = { 3239, 3240, 3241, 7965, 12643 } },
    { key = "elemental", name = L["Elemental Sharpening Stone"], items = { 18262, 287980 } },
    { key = "wizardoil", name = L["Wizard Oil"], items = { 20744, 20746, 287979, 20750, 20749 } },
    { key = "manaoil", name = L["Mana Oil"], items = { 20745, 20747, 20748 } },
    { key = "shadowoil", name = L["Shadow Oil"], items = { 3824 } },
    { key = "frostoil", name = L["Frost Oil"], items = { 3829 } },
    { key = "blessedoil", name = L["Blessed Wizard Oil"], items = { 23123 } },
    { key = "consecrated", name = L["Consecrated Sharpening Stone"], items = { 23122 } },
}

-- Weapon subclasses (Enum.ItemWeaponSubclass) by kind: edged, blunt, ranged;
-- a fishing pole takes nothing.
Data.BLADED = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [9] = true, [15] = true }
Data.BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }
Data.RANGED = { [2] = true, [3] = true, [18] = true, [19] = true }
Data.FISHING_POLE = 20

-- Consumables (EllesmereUI's WoW Forever ids).
Data.CAMP = 1229741
Data.SLEEPING_BAG = { buff = 429959, sleeping = 1331671, item = 211527, stacks = 3 }
Data.CENSER = { items = { 275730, 281371 }, buff = 1297774 }   -- Arcane Censer, Elemental Attractor
Data.WELL_FED = 19705
-- Food buffs not named Well Fed, read by id (their names are shared with
-- other buffs): Grilled Squid, Nightfin Soup, Runn Tum Tuber Surprise,
-- Dirge's Chops, Blessed Sunfruit and its juice.
Data.FOOD_BUFFS = { 18192, 18194, 22730, 25661, 18125, 18141 }
Data.FOOD_SPELL = 1248377      -- every food's use spell carries this name
Data.CAMP_CANDLE = 1229705     -- a camp's Incense Candle (Intellect)
Data.CAMP_KIT = 1307244        -- a camp's First Aid Kit (Stamina's stand-in)

-- Scrolls and elixirs per stat, strongest first: { item, bonus, the buff it
-- gives }. An item giving two stats is under both. family: the raid buff of
-- the same stat (its rank's amount is the bonus to beat). class: the class
-- whose own buff locks the stat once known. Stamina's health items stack with
-- it and are checked on their own.
Data.STATS = {
    { key = "intellect", label = L["Intellect"], icon = 1459, family = "intellect", class = "MAGE", items = {
        { 9179, 25, 11396 }, { 250328, 25, 1250918 }, { 13447, 18, 17535 }, { 10308, 16, 12176 }, { 4419, 12, 8098 },
        { 250354, 10, 1250989 }, { 2290, 8, 8097 }, { 250353, 6, 1250988 }, { 955, 4, 8096 }, { 3383, 3, 3166 } } },
    { key = "strength", label = L["Strength"], icon = 8118, items = {
        { 250351, 25, 1250986 }, { 9206, 25, 11405 }, { 250350, 18, 1250985 }, { 10310, 17, 12179 }, { 4426, 13, 8120 },
        { 250349, 10, 1250984 }, { 2289, 9, 8119 }, { 3391, 8, 3164 }, { 6662, 8, 8212 }, { 954, 5, 8118 }, { 2454, 4, 2367 } } },
    { key = "agility", label = L["Agility"], icon = 8115, items = {
        { 13452, 25, 17538 }, { 250328, 25, 1250918 }, { 9187, 25, 11334 }, { 250350, 18, 1250985 }, { 10309, 17, 12174 },
        { 8949, 15, 11328 }, { 4425, 13, 8117 }, { 1477, 9, 8116 }, { 3390, 8, 3160 }, { 3012, 5, 8115 }, { 2457, 4, 2374 } } },
    { key = "stamina", label = L["Stamina"], icon = 8099, family = "fortitude", class = "PRIEST", items = {
        { 10307, 16, 12178 }, { 4422, 12, 8101 }, { 1711, 8, 8100 }, { 1180, 4, 8099 } },
      health = { items = { { 250335, 400, 1250931 }, { 250334, 200, 1250928 }, { 3825, 120, 3593 }, { 2458, 27, 2378 } } } },
    { key = "spirit", label = L["Spirit"], icon = 8112, family = "spirit", class = "PRIEST", items = {
        { 250348, 25, 1250981 }, { 250338, 25, 1250941 }, { 13447, 18, 17535 }, { 250347, 18, 1250979 }, { 10306, 15, 12177 },
        { 4424, 11, 8114 }, { 250346, 10, 1250978 }, { 1712, 7, 8113 }, { 250345, 6, 1250976 }, { 1181, 3, 8112 },
        { 250344, 3, 1250974 } } },
    { key = "protection", label = L["Protection"], icon = 8091, items = {
        { 250329, 500, 1250920 }, { 13445, 450, 11348 }, { 8951, 250, 11349 }, { 10305, 240, 12175 }, { 4421, 180, 8095 },
        { 3389, 150, 3220 }, { 1478, 120, 8094 }, { 3013, 60, 8091 }, { 5997, 50, 673 } } },
}

-- What the test mode and the options' preview show: the mock-up's four tiles.
Data.SAMPLE = {
    { key = "intellect", kind = "give", have = 3, total = 5, short = L["Intellect"], icon = I .. "Spell_Holy_MagicalSentry" },
    { key = "fortitude", kind = "get", short = L["Fortitude"], icon = I .. "Spell_Holy_WordFortitude" },
    { key = "armor", kind = "self", short = L["Armor"], icon = I .. "Spell_MageArmor" },
    { key = "weapon:main", kind = "weapon", short = L["Main"], icon = I .. "INV_Potion_104", left = 240 },
}

local byKey = {}
for _, b in ipairs(Data.FAMILIES) do
    byKey[b.key] = b
    b.ids = {}
    for _, id in ipairs(b.single) do b.ids[#b.ids + 1] = id end
    for _, id in ipairs(b.group or {}) do b.ids[#b.ids + 1] = id end
end
Data.byKey = byKey
