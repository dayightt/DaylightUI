-- Data: the starting categories for the buffs everyone sees. The aura API gives
-- a buff's name but not where it came from, and this table fills that gap.
-- Each seed is the buff's spell id (a few ids when ranks or versions are
-- translated differently), then its English name. The client turns ids into
-- names in its own language, so a German or Chinese client sorts the same buffs
-- as an English one. The English name is a reminder, and the fallback match when
-- the client doesn't know the id (or there is none; those few only work on
-- English clients). Ranked spells share one name, so one id covers every rank.
-- Ids come from classic era spell data (TBC for names era lacks). Read at
-- runtime and never saved, so a newer version applies at once while the
-- player's own reassignments still win (see Classify.lua).

local _, BL = ...

local Data = {}
BL.Data = Data

BL.SEED_SPELLS = {
    warrior = {
        { "Battle Shout", 5242 }, { "Commanding Shout", 22440 }, { "Bloodrage", 2687 }, { "Berserker Rage", 18499 },
        { "Last Stand", 12975 }, { "Shield Wall", 871 }, { "Shield Block", 2565 }, { "Enrage", 1640, 3019, 23537 },
        { "Recklessness", 1719 }, { "Sweeping Strikes", 12292 }, { "Death Wish", 12328 }, { "Flurry", 12319 },
        { "Defensive Stance", 71 }, { "Battle Stance", 2457 }, { "Berserker Stance", 2458 }, { "Retaliation", 20230 },
        { "Bloodthirst", 23880 }, { "Spell Reflection", 9941, 23920 }, { "Rampage", 8285, 25744 },
    },
    paladin = {
        { "Blessing of Might", 19740 }, { "Greater Blessing of Might", 25782, 25915 },
        { "Blessing of Wisdom", 19742 }, { "Greater Blessing of Wisdom", 25894, 25919 },
        { "Blessing of Kings", 20217 }, { "Greater Blessing of Kings", 25898 }, { "Blessing of Salvation", 1038 },
        { "Greater Blessing of Salvation", 25895 }, { "Blessing of Sanctuary", 20911 },
        { "Greater Blessing of Sanctuary", 25899, 25951 }, { "Blessing of Light", 19977 },
        { "Greater Blessing of Light", 25890, 25948 }, { "Blessing of Protection", 1022 },
        { "Blessing of Freedom", 1044 }, { "Blessing of Sacrifice", 6940 }, { "Devotion Aura", 465 },
        { "Retribution Aura", 7294 }, { "Concentration Aura", 19746 }, { "Sanctity Aura", 20218 },
        { "Shadow Resistance Aura", 19876 }, { "Frost Resistance Aura", 19888 }, { "Fire Resistance Aura", 19891 },
        { "Righteous Fury", 20450 }, { "Divine Shield", 642 }, { "Divine Protection", 498 },
        { "Divine Favor", 20216 }, { "Holy Shield", 9800 }, { "Seal of Righteousness", 864 },
        { "Seal of Command", 20375 }, { "Seal of the Crusader", 20162 }, { "Seal of Wisdom", 1105 },
        { "Seal of Light", 20165 }, { "Seal of Justice", 20164 }, { "Vengeance", 8602 },
        { "Lay on Hands", 633, 2804 }, { "Holy Light", 635, 656 },
    },
    hunter = {
        { "Aspect of the Hawk", 6385 }, { "Aspect of the Monkey", 13163 }, { "Aspect of the Cheetah", 5118 },
        { "Aspect of the Pack", 13159 }, { "Aspect of the Beast", 13161 }, { "Aspect of the Wild", 20043 },
        { "Aspect of the Falcon", 469145 }, { "Trueshot Aura", 1563 }, { "Rapid Fire", 3045 },
        { "Feign Death", 5384 }, { "Bestial Wrath", 19574 }, { "Deterrence", 19263 }, { "Quick Shots", 6150 },
        { "Eyes of the Beast", 1002 }, { "Eagle Eye", 6197 }, { "Track Beasts", 1494 }, { "Track Humanoids", 5225 },
        { "Track Undead", 19884 }, { "Track Hidden", 19885 }, { "Track Elementals", 19880 },
        { "Track Demons", 19878 }, { "Track Giants", 19882 }, { "Track Dragonkin", 19879 },
        { "Frenzy", 19451, 23128 }, { "Ferocious Inspiration", 34455 },
    },
    rogue = {
        { "Stealth", 1784 }, { "Sprint", 2983 }, { "Evasion", 4086 }, { "Blade Flurry", 13877 },
        { "Adrenaline Rush", 13750, 28752 }, { "Slice and Dice", 5171 }, { "Cold Blood", 14177 }, { "Vanish", 1856 },
        { "Remorseless", 14143 }, { "Ghostly Strike", 14278 }, { "Preparation", 14185 },
        { "Cloak of Shadows", 462873 },
    },
    priest = {
        { "Power Word: Fortitude", 1243 }, { "Prayer of Fortitude", 21562 }, { "Divine Spirit", 6386 },
        { "Prayer of Spirit", 27681 }, { "Shadow Protection", 976 }, { "Prayer of Shadow Protection", 27683 },
        { "Power Word: Shield", 17, 17139 }, { "Fear Ward", 6346 }, { "Inner Fire", 588 }, { "Renew", 139, 25058 },
        { "Power Infusion", 10060 }, { "Inner Focus", 14751 }, { "Shadowform", 15473 },
        { "Spirit of Redemption", 20711 }, { "Touch of Weakness", 2652 }, { "Feedback", 6347 },
        { "Elune's Grace", 2651 }, { "Abolish Disease", 552 }, { "Levitate", 1706, 27986 }, { "Fade", 586 },
        { "Prayer of Healing", 596 }, { "Blessed Recovery", 27811 }, { "Inspiration", 14892 }, { "Champion's Grace" },
        { "Lightwell Renew", 7001 },
    },
    shaman = {
        { "Lightning Shield", 324, 23551 }, { "Water Shield", 408510 }, { "Earth Shield", 379 },
        { "Bloodlust", 1328, 23951 }, { "Heroism", 23682 }, { "Strength of Earth", 8076, 25362 },
        { "Grace of Air", 8836, 25360 }, { "Windfury Totem", 8512 }, { "Mana Spring", 5677, 24853 },
        { "Healing Stream", 5672 }, { "Tranquil Air", 25909 }, { "Stoneskin", 8072 }, { "Nature Resistance", 848 },
        { "Fire Resistance", 541, 2868 }, { "Frost Resistance", 4077 }, { "Water Walking", 546 },
        { "Water Breathing", 131 }, { "Ghost Wolf", 519 }, { "Elemental Mastery", 16166 },
        { "Nature's Swiftness", 16188 }, { "Ancestral Fortitude", 16177 }, { "Healing Way", 29202 },
        { "Clearcasting", 12536 }, { "Elemental Focus", 16164 }, { "Totem of Wrath", 30706 },
        { "Wrath of Air Totem", 2895 }, { "Mana Tide", 16191 },
    },
    mage = {
        { "Arcane Intellect", 1459, 364161 }, { "Arcane Brilliance", 23028 }, { "Mage Armor", 6117 },
        { "Ice Armor", 506 }, { "Frost Armor", 168 }, { "Dampen Magic", 604 }, { "Amplify Magic", 1008 },
        { "Ice Barrier", 2890 }, { "Mana Shield", 1463 }, { "Ice Block", 11958 }, { "Evocation", 12051 },
        { "Arcane Power", 12042 }, { "Presence of Mind", 12043 }, { "Combustion", 11129 }, { "Slow Fall", 130 },
        { "Blink", 517 }, { "Fire Ward", 543 }, { "Frost Ward", 3723 }, { "Blazing Speed", 31641 },
        { "Molten Armor", 428741 }, { "Icy Veins", 425121 }, { "Invisibility", 885, 23452 },
    },
    warlock = {
        { "Demon Skin", 687 }, { "Demon Armor", 706 }, { "Fel Armor", 403619 }, { "Soulstone Resurrection", 20707 },
        { "Unending Breath", 5697 }, { "Detect Invisibility", 2970 }, { "Detect Lesser Invisibility", 132 },
        { "Detect Greater Invisibility", 11743 }, { "Blood Pact", 6307 }, { "Paranoia", 19480 },
        { "Shadow Ward", 535 }, { "Fire Shield", 134 }, { "Sacrifice", 1050, 22651 }, { "Soul Link", 19028 },
        { "Demonic Sacrifice", 18788 }, { "Burning Wish", 18789 }, { "Touch of Shadow", 18791 },
        { "Fel Stamina", 18748 }, { "Fel Energy", 18792 }, { "Amplify Curse", 18288 }, { "Shadow Trance", 17941 },
        { "Nightfall", 18094, 23653 }, { "Backlash", 34935 }, { "Fel Domination", 18708 },
        { "Master Demonologist", 23759 }, { "Demonic Frenzy", 23257 }, { "Eye of Kilrogg", 126 },
    },
    druid = {
        { "Mark of the Wild", 1126 }, { "Gift of the Wild", 21849 }, { "Thorns", 467, 25640 },
        { "Rejuvenation", 774, 28724 }, { "Regrowth", 3734, 8936 }, { "Barkskin", 20655 },
        { "Omen of Clarity", 16864 }, { "Nature's Grace", 16880 }, { "Innervate", 29166 },
        { "Bear Form", 5487, 18309 }, { "Dire Bear Form", 9634 }, { "Cat Form", 499 }, { "Aquatic Form", 1066 },
        { "Travel Form", 783 }, { "Moonkin Form", 24858 }, { "Tree of Life", 439733 }, { "Prowl", 5215, 24450 },
        { "Dash", 1151, 23099 }, { "Tiger's Fury", 5217 }, { "Frenzied Regeneration", 22842 },
        { "Leader of the Pack", 17007 }, { "Moonkin Aura", 24907 }, { "Lifebloom", 408124 }, { "Tranquility", 740 },
        { "Natural Perfection", 33881 }, { "Swiftmend", 18562 }, { "Abolish Poison", 2893 },
    },
    weapon = {
        { "Rockbiter Weapon", 8017 }, { "Flametongue Weapon", 8024 }, { "Frostbrand Weapon", 8033 },
        { "Windfury Weapon", 8232 }, { "Instant Poison", 8679 }, { "Deadly Poison", 2818 },
        { "Crippling Poison", 3408 }, { "Mind-numbing Poison", 5760, 25810 }, { "Wound Poison", 13218 },
        { "Sharpened" }, { "Weighted" }, { "Blessed Wizard Oil", 28898 },
    },
    consumable = {
        { "Well Fed", 19705, 25694 }, { "Rumsey Rum Black Label", 25804 }, { "Rumsey Rum", 20875 },
        { "Rumsey Rum Light", 25037 }, { "Rumsey Rum Dark", 25722 }, { "Winterfall Firewater", 17038 },
        { "Ground Scorpok Assay" }, { "R.O.I.D.S." }, { "Gordok's Ogre Compound" }, { "Lung Juice Cocktail" },
        { "Cerebral Cortex Compound" }, { "Infallible Mind", 10690 }, { "Gizzard Gum" }, { "Crystal Ward", 15233 },
        { "Crystal Spire", 15279 }, { "Crystal Force", 15231 }, { "Crystal Yield", 15235 },
        { "Blessed Sunfruit", 18124 }, { "Blessed Sunfruit Juice", 18140 }, { "Blackened Basilisk", 33286 },
        { "Increased Stamina", 18191, 25661 }, { "Increased Intellect", 22730 }, { "Increased Agility", 18192 },
        { "Increased Strength" }, { "Increased Spirit", 18193 }, { "Mana Regeneration", 18194 },
        { "Health Regeneration", 18222 }, { "Food", 433, 25660 }, { "Drink", 430, 24355, 29007 },
        { "Regeneration", 820, 24361 }, { "Greater Fire Protection Potion", 17574 },
        { "Greater Frost Protection Potion", 17575 }, { "Greater Nature Protection Potion", 17576 },
        { "Greater Shadow Protection Potion", 17578 }, { "Greater Arcane Protection Potion", 17577 },
        { "Fire Protection", 7230, 29432 }, { "Frost Protection", 7236 }, { "Nature Protection", 7250 },
        { "Shadow Protection Potion", 7256 }, { "Arcane Protection", 17549 }, { "Holy Protection", 973 },
        { "Mighty Rage", 17528 }, { "Rage of Ages", 10667 }, { "Strike of the Scorpok", 10669 },
        { "Spirit of Boar", 10668 }, { "Sharpened Claws", 16942 }, { "Mongoose" }, { "Fortitude" }, { "Armor", 3220 },
        { "Intellect", 3167 }, { "Agility", 3159 }, { "Strength", 3163 }, { "Stamina", 8099 }, { "Spirit", 8112 },
        { "Protection", 42206 }, { "Swiftness", 11 }, { "Free Action", 6615 }, { "Invulnerability", 3169 },
        { "Limited Invulnerability" }, { "Restoration", 11359 }, { "Nature's Beauty" },
        { "Elixir of the Mongoose", 17538 }, { "Elixir of Fortitude", 3178 }, { "Elixir of Giants", 11472 },
        { "Elixir of Superior Defense", 17554 }, { "Elixir of Greater Firepower", 26277 },
        { "Elixir of Frost Power", 21923 }, { "Elixir of Shadow Power", 11476 },
        { "Elixir of Greater Intellect", 11465 }, { "Elixir of Sages" }, { "Elixir of Brute Force", 17537 },
        { "Elixir of Demonslaying", 11406 }, { "Elixir of Poison Resistance", 3174 }, { "Elixir of Waterbreathing" },
        { "Elixir of Water Walking" }, { "Flask of the Titans", 17626 }, { "Flask of Supreme Power", 17637 },
        { "Flask of Distilled Wisdom", 17636 }, { "Flask of Chromatic Resistance", 17638 },
        { "Flask of Petrification", 17634 }, { "Juju Power", 16323 }, { "Juju Might", 16329 },
        { "Juju Chill", 16325 }, { "Juju Ember", 16326 }, { "Juju Flurry", 16322 }, { "Juju Escape", 16321 },
        { "Juju Guile", 16327 }, { "Scroll of Agility" }, { "Scroll of Intellect" }, { "Scroll of Protection" },
        { "Scroll of Spirit" }, { "Scroll of Stamina" }, { "Scroll of Strength" }, { "Dreamless Sleep", 15822 },
        { "Greater Dreamless Sleep", 24360 }, { "Swiftness Potion", 2335 }, { "Mageblood Potion", 24365 },
        { "Nightfin Soup", 18243 }, { "Grilled Squid", 18240 }, { "Runn Tum Tuber Surprise", 22761 },
        { "Smoked Desert Dumplings", 24801, 24802 }, { "Tender Wolf Steak", 22480 }, { "Sagefish Delight", 25954 },
        { "Dirge's Kickin' Chimaerok Chops", 25659 }, { "Spirit of Zanza", 24382 }, { "Swiftness of Zanza", 24383 },
        { "Sheen of Zanza", 24417 }, { "Bogling Root" }, { "Noggenfogger Elixir", 16589 },
        { "Savory Deviate Delight", 8238 }, { "Rage Potion", 6617 }, { "Great Rage Potion", 6618 },
        { "Mighty Rage Potion", 17527 }, { "Restorative Potion", 11452 }, { "Living Action Potion", 24367 },
        { "Free Action Potion", 6624 }, { "Shadow Oil", 3449 }, { "Frost Oil", 3454 }, { "Stonescale Oil", 17551 },
        { "Nature Resistance Potion" }, { "Dense Dynamite", 23063, 23070 }, { "Goblin Rocket Fuel", 11456 },
        { "Ultra-Flash Shadow Reflector", 23082 }, { "Gnomish Death Ray", 12759 }, { "Goblin Sapper Charge", 12760 },
        { "Power Word: Strength" }, { "Kreeg's Stout Beatdown", 22790 }, { "Gordok Green Grog", 22789 },
        { "Fizzy Faire Drink" }, { "Darkmoon Special Reserve" }, { "Dragonbreath Chili", 15851, 15906 },
        { "Bright Campfire", 7359 }, { "Troll's Blood" }, { "Lesser Stoneshield" }, { "Greater Stoneshield", 17540 },
        { "Stoneshield", 4941 }, { "Ironshield", 28515 },
    },
    world = {
        { "Rallying Cry of the Dragonslayer", 22888 }, { "Warchief's Blessing", 16609 },
        { "Spirit of Zandalar", 24425 }, { "Songflower Serenade", 15366 }, { "Mol'dar's Moxie", 22818 },
        { "Fengus' Ferocity", 22817 }, { "Slip'kik's Savvy", 22820 }, { "Boon of Blackfathom", 430947 },
        { "Spark of Inspiration", 438536 }, { "Fervor of the Temple Explorer", 446695 }, { "Resist Fire", 1185 },
        { "Blessing of Blackfathom", 8733 }, { "Darkmoon Faire Fortune", 23765 }, { "Traces of Silithyst", 29534 },
        { "Chronoboon Displacer" }, { "Spirit of the Alpha", 408696 }, { "Bloodmoon Blessing" },
        { "Hakkar's Blessing" },
    },
}

-- Families too varied to list one by one (English names only). Tried in
-- order after the seeds; the first match wins.
BL.SEED_PATTERNS = {
    { "^Elixir of", "consumable" },
    { "^Flask of", "consumable" },
    { "^Greater .+ Protection Potion$", "consumable" },
    { "^Juju ", "consumable" },
    { "^Scroll of", "consumable" },
    { "^Well Fed", "consumable" },
    { "^Rumsey Rum", "consumable" },
    { " Potion$", "consumable" },
    { "Fortune$", "world" },
    { "^Sayge's", "world" },
    { "Sharpened$", "weapon" },
    { "Sharpening Stone$", "weapon" },
    { "Weightstone$", "weapon" },
    { " Oil$", "weapon" },
    { " Poison$", "weapon" },
}

-- name -> category, in the client's language and in English, built on first
-- use (spell names don't change in a session). A name that two seeds share in
-- this language (zhCN Stealth and Prowl) is in neither; it goes to `shared`
-- with every category it could be, and Classify picks.
local names, shared

local function spellName(id)
    local get = C_Spell and C_Spell.GetSpellName
    if not get then return nil end
    local ok, n = pcall(get, id)
    if ok and type(n) == "string" and n ~= "" then return n end
    return nil
end

local function add(n, cat)
    if not n then return end
    local set = shared[n]
    if set then set[cat] = true; return end
    local had = names[n]
    if had == nil then
        names[n] = cat
    elseif had ~= cat then
        names[n] = nil
        shared[n] = { [had] = true, [cat] = true }
    end
end

local function build()
    names, shared = {}, {}
    for cat, list in pairs(BL.SEED_SPELLS) do
        for _, seed in ipairs(list) do
            add(seed[1], cat)
            for i = 2, #seed do add(spellName(seed[i]), cat) end
        end
    end
end

-- Drops the built names (tests change the seeds).
function Data.Forget() names, shared = nil, nil end

function Data.Lookup(name)
    if type(name) ~= "string" then return nil end
    if not names then build() end
    local hit = names[name]
    if hit then return hit end
    if shared[name] then return nil end
    for i = 1, #BL.SEED_PATTERNS do
        local entry = BL.SEED_PATTERNS[i]
        if string.find(name, entry[1]) then return entry[2] end
    end
    return nil
end

-- The categories a name shared by several seeds could be ({ [id] = true }), or nil.
function Data.Shared(name)
    if type(name) ~= "string" then return nil end
    if not names then build() end
    return shared[name]
end

-- One name per seed, in the client's language when it knows the id.
function Data.Names()
    local out = {}
    for _, list in pairs(BL.SEED_SPELLS) do
        for _, seed in ipairs(list) do
            out[#out + 1] = (seed[2] and spellName(seed[2])) or seed[1]
        end
    end
    return out
end
