-- Made by tools/make_cdm_spells.py from talentsforever.com/data.json
-- CC BY 4.0: https://talentsforever.com, see
-- CdmSpells-LICENSE.txt. Spell ids and two flags only, no tooltip text.
-- Don't edit by hand: run the tool again.
--
-- Per class token: one family per spell, every rank's id (rank 1 first);
-- cd = a cooldown over the global cooldown, aura = it puts up a buff or a
-- debuff, passive = a passive whose buff has a spell id of its own.
-- GROUP: buffs other classes put on you (class = whose).

local _, ns = ...

local S = {
    WARRIOR = {
        { 6673, 5242, 6192, 11549, 11550, 11551, 25289, aura = true }, -- Battle Shout
        { 18499, cd = true, aura = true }, -- Berserker Rage
        { 2687, cd = true, aura = true }, -- Bloodrage
        { 23881, 23892, 23893, 23894, cd = true, aura = true }, -- Bloodthirst
        { 1161, cd = true, aura = true }, -- Challenging Shout
        { 100, 6178, 11578, cd = true, aura = true }, -- Charge
        { 12809, cd = true, aura = true }, -- Concussion Blow
        { 12328, cd = true, aura = true }, -- Death Wish
        { 1160, 6190, 11554, 11555, 11556, aura = true }, -- Demoralizing Shout
        { 676, cd = true, aura = true }, -- Disarm
        { 1715, 7372, 7373, aura = true }, -- Hamstring
        { 20252, 20616, 20617, cd = true, aura = true }, -- Intercept
        { 5246, cd = true, aura = true }, -- Intimidating Shout
        { 12975, cd = true, aura = true }, -- Last Stand
        { 694, 7400, 7402, 20559, 20560, cd = true, aura = true }, -- Mocking Blow
        { 12294, 21551, 21552, 21553, cd = true, aura = true }, -- Mortal Strike
        { 7384, 7887, 11584, 11585, cd = true }, -- Overpower
        { 12323, aura = true }, -- Piercing Howl
        { 6552, 6554, cd = true, aura = true }, -- Pummel
        { 1329555, cd = true, aura = true }, -- Reckless Swings
        { 1719, cd = true }, -- Recklessness
        { 772, 6546, 6547, 6548, 11572, 11573, 11574, aura = true }, -- Rend
        { 20230, cd = true, aura = true }, -- Retaliation
        { 6572, 6574, 7379, 11600, 11601, 25288, cd = true }, -- Revenge
        { 72, 1671, 1672, cd = true, aura = true }, -- Shield Bash
        { 2565, cd = true, aura = true }, -- Shield Block
        { 23922, 23923, 23924, 23925, cd = true }, -- Shield Slam
        { 871, cd = true, aura = true }, -- Shield Wall
        { 1240193, 1464, 8820, 11604, 11605, cd = true }, -- Slam
        { 1310222, cd = true }, -- Spearing Strike
        { 7386, 7405, 8380, 11596, 11597, aura = true }, -- Sunder Armor
        { 12292, cd = true }, -- Sweeping Strikes
        { 355, cd = true }, -- Taunt
        { 6343, 8198, 8204, 8205, 11580, 11581, cd = true, aura = true }, -- Thunder Clap
        { 402927, cd = true }, -- Victory Rush
        { 1680, cd = true }, -- Whirlwind
    },
    PALADIN = {
        { 1044, cd = true, aura = true }, -- Blessing of Freedom
        { 20217, aura = true }, -- Blessing of Kings
        { 19740, 19834, 19835, 19836, 19837, 19838, 25291, aura = true }, -- Blessing of Might
        { 1022, 5599, 10278, cd = true, aura = true }, -- Blessing of Protection
        { 6940, 20729, aura = true }, -- Blessing of Sacrifice
        { 19742, 19850, 19852, 19853, 19854, 25290, aura = true }, -- Blessing of Wisdom
        { 26573, 20116, 20922, 20923, 20924, cd = true, aura = true }, -- Consecration
        { 20216, cd = true }, -- Divine Favor
        { 19752, cd = true, aura = true }, -- Divine Intervention
        { 498, 5573, cd = true, aura = true }, -- Divine Protection
        { 642, 1020, cd = true, aura = true }, -- Divine Shield
        { 879, 5614, 5615, 10312, 10313, 10314, cd = true }, -- Exorcism
        { 25898, aura = true }, -- Greater Blessing of Kings
        { 25782, 25916, aura = true }, -- Greater Blessing of Might
        { 25894, 25918, aura = true }, -- Greater Blessing of Wisdom
        { 853, 5588, 5589, 10308, cd = true, aura = true }, -- Hammer of Justice
        { 24275, 24274, 24239, cd = true }, -- Hammer of Wrath
        { 20925, 20927, 20928, 1239570, cd = true, aura = true }, -- Holy Shield
        { 1311606, 20473, 20929, 20930, cd = true }, -- Holy Shock
        { 679, 678, 1866, 680, 2495, 5569, 10332, 10333, cd = true }, -- Holy Strike
        { 2812, 10318, cd = true, aura = true }, -- Holy Wrath
        { 20271, cd = true }, -- Judgement
        { 633, 2800, 10310, cd = true }, -- Lay on Hands
        { 1310911, 1311590, 1311595, cd = true, aura = true }, -- Light's Vigil
        { 1328548, aura = true }, -- Oath of Light
        { 20066, cd = true, aura = true }, -- Repentance
        { 25780, aura = true }, -- Righteous Fury
        { 20375, 20915, 20918, 20919, 20920, aura = true }, -- Seal of Command
        { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423, aura = true }, -- Seal of Fury
        { 20164, aura = true }, -- Seal of Justice
        { 20165, 20347, 20348, 20349, aura = true }, -- Seal of Light
        { 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293, aura = true }, -- Seal of Righteousness
        { 20166, 20356, 20357, aura = true }, -- Seal of Wisdom
        { 21082, 20162, 20305, 20306, 20307, 20308, aura = true }, -- Seal of the Crusader
        { 1310994, cd = true }, -- Swift Judgement
        { 1311015, cd = true, aura = true }, -- Templar's Bulwark
        { 2878, 5627, 10326, cd = true, aura = true }, -- Turn Undead
    },
    HUNTER = {
        { 19434, 20900, 20901, 20902, 20903, 20904, cd = true }, -- Aimed Shot
        { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287, cd = true }, -- Arcane Shot
        { 5118, aura = true }, -- Aspect of the Cheetah
        { 13159, aura = true }, -- Aspect of the Pack
        { 19574, cd = true, aura = true }, -- Bestial Wrath
        { 17253, 17255, 17256, 17257, 17258, 17259, 17260, 17261, cd = true }, -- Bite
        { 7371, 26177, 26178, 26179, 26201, 27685, cd = true, aura = true }, -- Charge
        { 5116, cd = true, aura = true }, -- Concussive Shot
        { 19306, 1242634, 20909, 20910, cd = true, aura = true }, -- Counterattack
        { 1742, 1753, 1754, 1755, 1756, 16697, cd = true }, -- Cower
        { 23099, 23109, 23110, cd = true, aura = true }, -- Dash
        { 24423, 24577, 24578, 24579, cd = true, aura = true }, -- Demoralizing Screech
        { 19263, cd = true, aura = true }, -- Deterrence
        { 781, 14272, 14273, cd = true }, -- Disengage
        { 1264758, 1264927, 1264929, 1264930, 1264933, cd = true, aura = true }, -- Dismember
        { 20736, 14274, 15629, 15630, 15631, 15632, cd = true }, -- Distracting Shot
        { 23145, 23147, 23148, cd = true, aura = true }, -- Dive
        { 1265899, 1265901, 1265902, 1265903, 1265904, aura = true }, -- Dust Cloud
        { 6197, aura = true }, -- Eagle Eye
        { 1221404, cd = true, aura = true }, -- Enchanted Flare
        { 13813, 14316, 14317, cd = true, aura = true }, -- Explosive Trap
        { 1002, aura = true }, -- Eyes of the Beast
        { 5384, cd = true, aura = true }, -- Feign Death
        { 1543, cd = true, aura = true }, -- Flare
        { 1499, 14310, 14311, cd = true, aura = true }, -- Freezing Trap
        { 13809, cd = true, aura = true }, -- Frost Trap
        { 24604, 24605, 24603, 24597, cd = true, aura = true }, -- Furious Howl
        { 2649, 14916, 14917, 14918, 14919, 14920, 14921, cd = true }, -- Growl
        { 1130, 14323, 14324, 14325, aura = true }, -- Hunter's Mark
        { 13795, 14302, 14303, 14304, 14305, cd = true, aura = true }, -- Immolation Trap
        { 19577, cd = true, aura = true }, -- Intimidation
        { 24118, 24119, 24120, 1299332, aura = true }, -- Lacerate
        { 136, 3111, 3661, 3662, 13542, 13543, 13544, aura = true }, -- Mend Pet
        { 1265054, 1265055, 1265056, 1265057, 1265058, cd = true, aura = true }, -- Mine!
        { 1495, 14269, 14270, 14271, cd = true }, -- Mongoose Bite
        { 2643, cd = true }, -- Multi-Shot
        { 1264735, 1264736, 1264739, 1264741, 1264742, cd = true, aura = true }, -- Pinch
        { 24450, 24452, 24453, cd = true }, -- Prowl
        { 3045, cd = true, aura = true }, -- Rapid Fire
        { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266, cd = true }, -- Raptor Strike
        { 1265065, 1265066, 1265067, 1265068, 1265069, cd = true, aura = true }, -- Savage Rend
        { 1513, 14326, 14327, cd = true, aura = true }, -- Scare Beast
        { 19503, cd = true, aura = true }, -- Scatter Shot
        { 24640, 24583, 24586, 24587, cd = true, aura = true }, -- Scorpid Poison
        { 3043, aura = true }, -- Scorpid Sting
        { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, aura = true }, -- Serpent Sting
        { 26064, cd = true, aura = true }, -- Shell Shield
        { 1310687, 1310785, 1310786, cd = true, aura = true }, -- Sniper Shot
        { 1264478, 1264479, 1264480, 1264481, 1264482, cd = true, aura = true }, -- Sonic Blast
        { 1317257, cd = true, aura = true }, -- Strider Kick
        { 1293241, 1293525, 1293526, 1293527, cd = true, aura = true }, -- Summon Hawk
        { 1264494, 1264497, 1264498, 1264501, 1264502, cd = true }, -- Swipe
        { 1515, aura = true }, -- Tame Beast
        { 1265038, 1265039, 1265040, 1265041, 1265042, cd = true, aura = true }, -- Tendon Rip
        { 26090, 26187, 26188, 1264455, cd = true }, -- Thunderstomp
        { 19801, cd = true }, -- Tranquilizing Shot
        { 1310612, cd = true, aura = true }, -- Trickster's Dance
        { 1299346, 1299348, 19506, 20905, 20906, aura = true }, -- Trueshot Aura
        { 3034, 14279, 14280, cd = true, aura = true }, -- Viper Sting
        { 1510, 14294, 14295, aura = true }, -- Volley
        { 1265843, 1265878, 1265880, 1265881, 1265883, cd = true, aura = true }, -- Web
        { 2974, 14267, 14268, aura = true }, -- Wing Clip
    },
    ROGUE = {
        { 13750, cd = true, aura = true }, -- Adrenaline Rush
        { 13877, cd = true, aura = true }, -- Blade Flurry
        { 2094, cd = true, aura = true }, -- Blind
        { 1833, aura = true }, -- Cheap Shot
        { 14177, cd = true }, -- Cold Blood
        { 3420, 3421, aura = true }, -- Crippling Poison
        { 2835, 2837, 11357, 11358, 25347, aura = true }, -- Deadly Poison
        { 1316709, 1325756, 1325757, 1325758, cd = true }, -- Death Mark
        { 1725, cd = true }, -- Distract
        { 5277, cd = true, aura = true }, -- Evasion
        { 8647, 8649, 8650, 11197, 11198, aura = true }, -- Expose Armor
        { 1966, 6768, 8637, 11303, 25302, cd = true }, -- Feint
        { 703, 8631, 8632, 8633, 11289, 11290, aura = true }, -- Garrote
        { 14278, cd = true, aura = true }, -- Ghostly Strike
        { 1776, 1777, 8629, 11285, 11286, cd = true, aura = true }, -- Gouge
        { 16511, aura = true }, -- Hemorrhage
        { 1766, 1767, 1768, 1769, cd = true, aura = true }, -- Kick
        { 408, 8643, cd = true, aura = true }, -- Kidney Shot
        { 5763, 8694, 11400, aura = true }, -- Mind-numbing Poison
        { 1328825, aura = true, passive = true }, -- Poised
        { 14183, cd = true }, -- Premeditation
        { 14185, cd = true }, -- Preparation
        { 14251, cd = true, aura = true }, -- Riposte
        { 1943, 8639, 8640, 11273, 11274, 11275, aura = true }, -- Rupture
        { 6770, 2070, 11297, aura = true }, -- Sap
        { 1329283, 1329549, cd = true }, -- Shank
        { 5171, 6774, aura = true }, -- Slice and Dice
        { 2983, 8696, 11305, cd = true, aura = true }, -- Sprint
        { 1784, 1785, 1786, 1787, cd = true }, -- Stealth
        { 1856, 1857, cd = true, aura = true }, -- Vanish
        { 13220, 13228, 13229, 13230, aura = true }, -- Wound Poison
    },
    PRIEST = {
        { 552, aura = true }, -- Abolish Disease
        { 1277331, 1277332, 1277333, 1277334, 1277335, cd = true, aura = true }, -- Chastise
        { 1277455, cd = true, aura = true }, -- Confounding Flash
        { 1277462, 1277634, 1277638, 1277639, 1277640, cd = true, aura = true }, -- Contingency Plan
        { 1277324, 1277325, 1277326, 1277327, 1277328, cd = true, aura = true }, -- Dark Sacrifice
        { 13908, 19236, 19238, 19240, 19241, 19242, 19243, cd = true }, -- Desperate Prayer
        { 2944, 19276, 19277, 19278, 19279, 19280, cd = true, aura = true }, -- Devouring Plague
        { 1277370, 1277371, 1277372, 1277374, 1277376, 1277377, 1277378, cd = true }, -- Divine Grace
        { 14752, 14818, 14819, 27841, aura = true }, -- Divine Spirit
        { 2651, cd = true, aura = true }, -- Elune's Grace
        { 586, 9578, 9579, 9592, 10941, 10942, cd = true, aura = true }, -- Fade
        { 6346, cd = true, aura = true }, -- Fear Ward
        { 13896, 19271, 19273, 19274, 19275, cd = true, aura = true }, -- Feedback
        { 9035, 19281, 19282, 19283, 19284, 19285, aura = true }, -- Hex of Weakness
        { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261, aura = true }, -- Holy Fire
        { 588, 7128, 602, 1006, 10951, 10952, aura = true }, -- Inner Fire
        { 14751, cd = true }, -- Inner Focus
        { 1706, aura = true }, -- Levitate
        { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947, cd = true }, -- Mind Blast
        { 15407, 17311, 17312, 17313, 17314, 18807, aura = true }, -- Mind Flay
        { 453, 8192, 10953, aura = true }, -- Mind Soothe
        { 2096, 10909, aura = true }, -- Mind Vision
        { 402174, 1240720, 1240721, 1316995, cd = true, aura = true }, -- Penance
        { 10060, cd = true, aura = true }, -- Power Infusion
        { 1243, 1244, 1245, 2791, 10937, 10938, aura = true }, -- Power Word: Fortitude
        { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901, cd = true, aura = true }, -- Power Word: Shield
        { 21562, 21564, aura = true }, -- Prayer of Fortitude
        { 401859, 1240826, 1240827, cd = true, aura = true }, -- Prayer of Mending
        { 27683, aura = true }, -- Prayer of Shadow Protection
        { 27681, aura = true }, -- Prayer of Spirit
        { 8122, 8124, 10888, 10890, cd = true, aura = true }, -- Psychic Scream
        { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315, aura = true }, -- Renew
        { 9484, 9485, 10955, aura = true }, -- Shackle Undead
        { 976, 10957, 10958, aura = true }, -- Shadow Protection
        { 1309595, 1309633, 1309635, 1309636, cd = true }, -- Shadow Word: Death
        { 589, 594, 970, 992, 2767, 10892, 10893, 10894, aura = true }, -- Shadow Word: Pain
        { 18137, 19308, 19309, 19310, 19311, 19312, aura = true }, -- Shadowguard
        { 15487, cd = true, aura = true }, -- Silence
        { 10797, 19296, 19299, 19302, 19303, 19304, 19305, cd = true, aura = true }, -- Starshards
        { 2652, 19261, 19262, 19264, 19265, 19266, aura = true }, -- Touch of Weakness
        { 15286, cd = true, aura = true }, -- Vampiric Embrace
    },
    SHAMAN = {
        { 556, cd = true }, -- Astral Recall
        { 421, 930, 2860, 10605, cd = true }, -- Chain Lightning
        { 8170, aura = true }, -- Disease Cleansing Totem
        { 8042, 8044, 8045, 8046, 10412, 10413, 10414, cd = true, aura = true }, -- Earth Shock
        { 2484, cd = true, aura = true }, -- Earthbind Totem
        { 6196, aura = true }, -- Far Sight
        { 408341, 408342, 408343, 408344, 408345, cd = true }, -- Fire Nova
        { 8184, 10537, 10538, aura = true }, -- Fire Resistance Totem
        { 8050, 8052, 8053, 10447, 10448, 29228, cd = true, aura = true }, -- Flame Shock
        { 8227, 8249, 10526, 16387, aura = true }, -- Flametongue Totem
        { 8181, 10478, 10479, aura = true }, -- Frost Resistance Totem
        { 8056, 8058, 10472, 10473, cd = true, aura = true }, -- Frost Shock
        { 8033, 8038, 10456, 16355, 16356, aura = true }, -- Frostbrand Weapon
        { 8835, 10627, 25359, aura = true }, -- Grace of Air Totem
        { 8177, cd = true, aura = true }, -- Grounding Totem
        { 5394, 6375, 6377, 10462, 10463, aura = true }, -- Healing Stream Totem
        { 16166, cd = true, aura = true }, -- Lightning Mastery
        { 324, 325, 905, 945, 8134, 10431, 10432, aura = true }, -- Lightning Shield
        { 8190, 10585, 10586, 10587, aura = true }, -- Magma Totem
        { 5675, 10495, 10496, 10497, aura = true }, -- Mana Spring Totem
        { 16190, 17354, 17359, 1325256, cd = true, aura = true }, -- Mana Tide Totem
        { 10595, 10600, 10601, aura = true }, -- Nature Resistance Totem
        { 16188, cd = true }, -- Nature's Swiftness
        { 8166, aura = true }, -- Poison Cleansing Totem
        { 425336, cd = true, aura = true }, -- Rage of the Farseer
        { 20608, cd = true }, -- Reincarnation
        { 408521, 1239242, 1239243, cd = true, aura = true }, -- Riptide
        { 3599, 6363, 6364, 6365, 10437, 10438, aura = true }, -- Searing Totem
        { 6495, aura = true }, -- Sentry Totem
        { 5730, 6390, 6391, 6392, 10427, 10428, cd = true, aura = true }, -- Stoneclaw Totem
        { 8071, 8154, 8155, 10406, 10407, 10408, aura = true }, -- Stoneskin Totem
        { 17364, cd = true, aura = true }, -- Stormstrike
        { 8075, 8160, 8161, 10442, 25361, aura = true }, -- Strength of Earth Totem
        { 437009, cd = true }, -- Totemic Call
        { 8143, aura = true }, -- Tremor Totem
        { 131, aura = true }, -- Water Breathing
        { 408510, aura = true }, -- Water Shield
        { 546, aura = true }, -- Water Walking
        { 8512, 10613, 10614, aura = true }, -- Windfury Totem
        { 15107, 15111, 15112, aura = true }, -- Windwall Totem
    },
    MAGE = {
        { 1008, 8455, 10169, 10170, aura = true }, -- Amplify Magic
        { 400574, 1239696, 1239697, 1239699, 1239700, aura = true }, -- Arcane Blast
        { 23028, aura = true }, -- Arcane Brilliance
        { 1459, 1460, 1461, 10156, 10157, aura = true }, -- Arcane Intellect
        { 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345, aura = true }, -- Arcane Missiles
        { 12042, cd = true }, -- Arcane Power
        { 1326079, 1326080, 1326081, 1326082, cd = true }, -- Arcane Wrath
        { 11113, 13018, 13019, 13020, 13021, cd = true, aura = true }, -- Blast Wave
        { 1953, cd = true }, -- Blink
        { 10, 6141, 8427, 10185, 10186, 10187, aura = true }, -- Blizzard
        { 12472, cd = true }, -- Cold Snap
        { 11129, cd = true }, -- Combustion
        { 120, 8492, 10159, 10160, cd = true, aura = true }, -- Cone of Cold
        { 2139, cd = true, aura = true }, -- Counterspell
        { 604, 8450, 8451, 10173, 10174, aura = true }, -- Dampen Magic
        { 12051, cd = true, aura = true }, -- Evocation
        { 2136, 2137, 2138, 8412, 8413, 10197, 10199, cd = true }, -- Fire Blast
        { 543, 8457, 8458, 10223, 10225, cd = true, aura = true }, -- Fire Ward
        { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306, aura = true }, -- Fireball
        { 2120, 2121, 8422, 8423, 10215, 10216, aura = true }, -- Flamestrike
        { 168, 7300, 7301, aura = true }, -- Frost Armor
        { 122, 865, 6131, 10230, cd = true, aura = true }, -- Frost Nova
        { 6143, 8461, 8462, 10177, 28609, cd = true, aura = true }, -- Frost Ward
        { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304, aura = true }, -- Frostbolt
        { 401502, 1237312, 1237313, aura = true }, -- Frostfire Bolt
        { 7302, 7320, 10219, 10220, aura = true }, -- Ice Armor
        { 11426, 13031, 13032, 13033, cd = true, aura = true }, -- Ice Barrier
        { 11958, cd = true, aura = true }, -- Ice Block
        { 1312002, 400640, 1240044, 1240045, 1240046, 1240047, cd = true }, -- Ice Lance
        { 6117, 22782, 22783, aura = true }, -- Mage Armor
        { 1463, 8494, 8495, 10191, 10192, 10193, aura = true }, -- Mana Shield
        { 28271, 28272, 118, 12824, 12825, 12826, aura = true }, -- Polymorph
        { 11419, cd = true }, -- Portal: Darnassus
        { 11416, cd = true }, -- Portal: Ironforge
        { 11417, cd = true }, -- Portal: Orgrimmar
        { 10059, cd = true }, -- Portal: Stormwind
        { 11420, cd = true }, -- Portal: Thunder Bluff
        { 11418, cd = true }, -- Portal: Undercity
        { 12043, cd = true }, -- Presence of Mind
        { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809, aura = true }, -- Pyroblast
        { 130, aura = true }, -- Slow Fall
    },
    WARLOCK = {
        { 18288, cd = true, aura = true }, -- Amplify Curse
        { 980, 1014, 6217, 11711, 11712, 11713, aura = true }, -- Bane of Agony
        { 603, cd = true }, -- Bane of Doom
        { 1225228, aura = true }, -- Bane of Havoc
        { 710, 18647, aura = true }, -- Banish
        { 1293817, 1293818, 17962, 18930, 18931, 18932, cd = true }, -- Conflagrate
        { 17767, 17850, 17851, 17852, 17853, 17854, aura = true }, -- Consume Shadows
        { 172, 6222, 6223, 7648, 11671, 11672, 25311, aura = true }, -- Corruption
        { 18223, aura = true }, -- Curse of Exhaustion
        { 704, 7658, 7659, 11717, aura = true }, -- Curse of Recklessness
        { 1714, 11719, aura = true }, -- Curse of Tongues
        { 702, 1108, 6205, 7646, 11707, 11708, aura = true }, -- Curse of Weakness
        { 440892, 1311676, 1311677, 1311680, aura = true }, -- Curse of the Elements
        { 6789, 17925, 17926, cd = true, aura = true }, -- Death Coil
        { 706, 1086, 11733, 11734, 11735, aura = true }, -- Demon Armor
        { 687, 696, aura = true }, -- Demon Skin
        { 18788, aura = true }, -- Demonic Sacrifice
        { 132, 2970, 11743, aura = true }, -- Detect Invisibility
        { 19505, 19731, 19734, 19736, cd = true }, -- Devour Magic
        { 689, 699, 709, 7651, 11699, 11700, aura = true }, -- Drain Life
        { 5138, 6226, 11703, 11704, aura = true }, -- Drain Mana
        { 1120, 8288, 8289, 11675, aura = true }, -- Drain Soul
        { 5782, 6213, 6215, aura = true }, -- Fear
        { 18708, cd = true }, -- Fel Domination
        { 2947, 8316, 8317, 11770, 11771, aura = true }, -- Fire Shield
        { 755, 3698, 3699, 3700, 11693, 11694, 11695, aura = true }, -- Health Funnel
        { 1949, 11683, 11684, aura = true }, -- Hellfire
        { 5484, 17928, cd = true, aura = true }, -- Howl of Terror
        { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309, aura = true }, -- Immolate
        { 1122, cd = true, aura = true }, -- Inferno
        { 7814, 7815, 7816, 11778, 11779, 11780, cd = true }, -- Lash of Pain
        { 7870, aura = true }, -- Lesser Invisibility
        { 4511, cd = true }, -- Phase Shift
        { 5740, 6219, 11677, 11678, aura = true }, -- Rain of Fire
        { 18540, cd = true }, -- Ritual of Doom
        { 7812, 19438, 19440, 19441, 19442, 19443, aura = true }, -- Sacrifice
        { 6358, aura = true }, -- Seduction
        { 6229, 11739, 11740, 28610, cd = true, aura = true }, -- Shadow Ward
        { 17877, 18867, 18868, 18869, 18870, 18871, cd = true }, -- Shadowburn
        { 18265, 18879, 18880, 18881, aura = true }, -- Siphon Life
        { 6360, 7813, 11784, 11785, cd = true }, -- Soothing Kiss
        { 6353, 17924, cd = true }, -- Soul Fire
        { 19244, 19647, cd = true, aura = true }, -- Spell Lock
        { 17735, 17750, 17751, 17752, cd = true }, -- Suffering
        { 19478, 19655, 19656, 19660, aura = true }, -- Tainted Blood
        { 3716, 7809, 7810, 7811, 11774, 11775, cd = true }, -- Torment
        { 5697, aura = true }, -- Unending Breath
        { 1316697, aura = true }, -- Wrack
    },
    DRUID = {
        { 2893, aura = true }, -- Abolish Poison
        { 22812, cd = true, aura = true }, -- Barkskin
        { 5211, 6798, 8983, cd = true, aura = true }, -- Bash
        { 5209, cd = true, aura = true }, -- Challenging Roar
        { 8998, 9000, 9892, cd = true }, -- Cower
        { 1850, 9821, cd = true, aura = true }, -- Dash
        { 99, 1735, 9490, 9747, 9898, aura = true }, -- Demoralizing Roar
        { 5229, cd = true, aura = true }, -- Enrage
        { 339, 1062, 5195, 5196, 9852, 9853, aura = true }, -- Entangling Roots
        { 770, 778, 9749, 9907, aura = true }, -- Faerie Fire
        { 1238122, cd = true, aura = true }, -- Feral Charge
        { 22842, cd = true, aura = true }, -- Frenzied Regeneration
        { 21849, 21850, aura = true }, -- Gift of the Wild
        { 6795, cd = true }, -- Growl
        { 2637, 18657, 18658, aura = true }, -- Hibernate
        { 16914, 17401, 17402, aura = true }, -- Hurricane
        { 29166, cd = true, aura = true }, -- Innervate
        { 5570, 24974, 24975, 24976, 24977, aura = true }, -- Insect Swarm
        { 1328617, 1328616, 414644, 1235826, 1235827, aura = true }, -- Lacerate
        { 1126, 5232, 6756, 5234, 8907, 9884, 9885, aura = true }, -- Mark of the Wild
        { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835, aura = true }, -- Moonfire
        { 16689, 16810, 16811, 16812, 16813, 17329, cd = true, aura = true }, -- Nature's Grasp
        { 17116, cd = true }, -- Nature's Swiftness
        { 1328829, aura = true, passive = true }, -- Poised
        { 9005, 9823, 9827, aura = true }, -- Pounce
        { 407995, 1238069, 1238070, cd = true }, -- Primal Bite
        { 5215, 6783, 9913, cd = true }, -- Prowl
        { 1822, 1823, 1824, 9904, aura = true }, -- Rake
        { 20484, 20739, 20742, 20747, 20748, cd = true }, -- Rebirth
        { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858, aura = true }, -- Regrowth
        { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299, aura = true }, -- Rejuvenation
        { 1079, 9492, 9493, 9752, 9894, 9896, aura = true }, -- Rip
        { 1322605, cd = true }, -- Shifting Power
        { 2908, 8955, 9901, aura = true }, -- Soothe Animal
        { 18562, cd = true }, -- Swiftmend
        { 467, 782, 1075, 8914, 9756, 9910, aura = true }, -- Thorns
        { 740, 8918, 9862, 9863, cd = true, aura = true }, -- Tranquility
        { 408120, 1238214, 1238215, cd = true, aura = true }, -- Wild Growth
    },
    GROUP = {
        { 1243, 1244, 1245, 2791, 10937, 10938, class = "PRIEST" }, -- Power Word: Fortitude
        { 21562, 21564, class = "PRIEST" }, -- Prayer of Fortitude
        { 14752, 14818, 14819, 27841, class = "PRIEST" }, -- Divine Spirit
        { 27681, class = "PRIEST" }, -- Prayer of Spirit
        { 976, 10957, 10958, class = "PRIEST" }, -- Shadow Protection
        { 27683, class = "PRIEST" }, -- Prayer of Shadow Protection
        { 10060, class = "PRIEST" }, -- Power Infusion
        { 6346, class = "PRIEST" }, -- Fear Ward
        { 1126, 5232, 6756, 5234, 8907, 9884, 9885, class = "DRUID" }, -- Mark of the Wild
        { 21849, 21850, class = "DRUID" }, -- Gift of the Wild
        { 467, 782, 1075, 8914, 9756, 9910, class = "DRUID" }, -- Thorns
        { 29166, class = "DRUID" }, -- Innervate
        { 1459, 1460, 1461, 10156, 10157, class = "MAGE" }, -- Arcane Intellect
        { 23028, class = "MAGE" }, -- Arcane Brilliance
        { 1008, 8455, 10169, 10170, class = "MAGE" }, -- Amplify Magic
        { 604, 8450, 8451, 10173, 10174, class = "MAGE" }, -- Dampen Magic
        { 19740, 19834, 19835, 19836, 19837, 19838, 25291, class = "PALADIN" }, -- Blessing of Might
        { 19742, 19850, 19852, 19853, 19854, 25290, class = "PALADIN" }, -- Blessing of Wisdom
        { 20217, class = "PALADIN" }, -- Blessing of Kings
        { 1022, 5599, 10278, class = "PALADIN" }, -- Blessing of Protection
        { 1044, class = "PALADIN" }, -- Blessing of Freedom
        { 25782, 25916, class = "PALADIN" }, -- Greater Blessing of Might
        { 25894, 25918, class = "PALADIN" }, -- Greater Blessing of Wisdom
        { 25898, class = "PALADIN" }, -- Greater Blessing of Kings
    },
}


-- FACTS BEGIN (tools/make_cdm_facts.py, from the game's data; don't edit by hand)
S.FACTS = {
    [0] = {},
    [10] = { on = "self", lasts = 8 },
    [17] = { cd = 4, on = "friend", lasts = 30 },
    [71] = { on = "self" },
    [72] = { cd = 12, noaura = true },
    [78] = { noaura = true },
    [99] = { on = "enemy", lasts = 30 },
    [100] = { cd = 15, on = "enemy", lasts = 1, auras = { 7922 } },
    [116] = { on = "enemy", lasts = 5 },
    [118] = { on = "enemy", lasts = 20 },
    [120] = { cd = 10, on = "enemy", lasts = 6 },
    [122] = { cd = 25, on = "enemy", lasts = 8 },
    [130] = { on = "self", lasts = 30 },
    [131] = { on = "friend", lasts = 600 },
    [132] = { on = "friend", lasts = 600 },
    [133] = { on = "enemy", lasts = 4 },
    [136] = { on = "pet", lasts = 5 },
    [139] = { on = "friend", lasts = 15 },
    [143] = { on = "enemy", lasts = 6 },
    [145] = { on = "enemy", lasts = 6 },
    [168] = { on = "self", lasts = 1800 },
    [172] = { on = "enemy", lasts = 12 },
    [205] = { on = "enemy", lasts = 6 },
    [284] = { noaura = true },
    [285] = { noaura = true },
    [324] = { on = "self", lasts = 600, charges = 3 },
    [325] = { on = "self", lasts = 600, charges = 3 },
    [339] = { on = "enemy", lasts = 12 },
    [348] = { on = "enemy", lasts = 15 },
    [355] = { cd = 8, on = "enemy", lasts = 3 },
    [408] = { cd = 20, on = "enemy" },
    [421] = { cd = 6, noaura = true },
    [453] = { on = "enemy", lasts = 15 },
    [465] = { on = "self" },
    [467] = { on = "friend", lasts = 600 },
    [498] = { cd = 300, on = "self", lasts = 6 },
    [543] = { cd = 30, on = "self", lasts = 30 },
    [546] = { on = "friend", lasts = 600 },
    [552] = { on = "friend", lasts = 20 },
    [556] = { cd = 900 },
    [586] = { cd = 30, on = "self", lasts = 10 },
    [588] = { on = "self", lasts = 600, charges = 20 },
    [589] = { on = "enemy", lasts = 18 },
    [592] = { cd = 4, on = "friend", lasts = 30 },
    [594] = { on = "enemy", lasts = 18 },
    [600] = { cd = 4, on = "friend", lasts = 30 },
    [602] = { on = "self", lasts = 600, charges = 20 },
    [603] = { cd = 60, on = "enemy", lasts = 60 },
    [604] = { on = "friend", lasts = 600 },
    [633] = { cd = 1200 },
    [642] = { cd = 300, on = "self", lasts = 10 },
    [643] = { on = "self" },
    [676] = { cd = 60, on = "enemy", lasts = 10 },
    [678] = { cd = 10 },
    [679] = { cd = 10 },
    [680] = { cd = 10 },
    [687] = { on = "self", lasts = 1800 },
    [689] = { on = "enemy", lasts = 5 },
    [693] = { on = "friend", lasts = 1800, auras = { 20707, 20762, 20763, 20764, 20765 } },
    [694] = { cd = 120, on = "enemy", lasts = 6 },
    [696] = { on = "self", lasts = 1800 },
    [699] = { on = "enemy", lasts = 5 },
    [702] = { on = "enemy", lasts = 120 },
    [703] = { on = "enemy", lasts = 18 },
    [704] = { on = "enemy", lasts = 120 },
    [706] = { on = "self", lasts = 1800 },
    [707] = { on = "enemy", lasts = 15 },
    [709] = { on = "enemy", lasts = 5 },
    [710] = { on = "enemy", lasts = 20 },
    [740] = { cd = 300, on = "self", lasts = 10 },
    [755] = { on = "pet", lasts = 10 },
    [768] = { on = "self" },
    [770] = { on = "enemy", lasts = 40 },
    [772] = { on = "enemy", lasts = 9 },
    [774] = { on = "friend", lasts = 12 },
    [778] = { on = "enemy", lasts = 40 },
    [781] = { cd = 5 },
    [782] = { on = "friend", lasts = 600 },
    [783] = { on = "self" },
    [837] = { on = "enemy", lasts = 6 },
    [845] = { noaura = true },
    [853] = { cd = 60, on = "enemy", lasts = 3 },
    [865] = { cd = 25, on = "enemy", lasts = 8 },
    [871] = { cd = 900, on = "self", lasts = 12 },
    [879] = { cd = 15, noaura = true },
    [905] = { on = "self", lasts = 600, charges = 3 },
    [930] = { cd = 6, noaura = true },
    [945] = { on = "self", lasts = 600, charges = 3 },
    [970] = { on = "enemy", lasts = 18 },
    [976] = { on = "friend", lasts = 600 },
    [980] = { on = "enemy", lasts = 24 },
    [992] = { on = "enemy", lasts = 18 },
    [1002] = { on = "pet", lasts = 120 },
    [1006] = { on = "self", lasts = 600, charges = 20 },
    [1008] = { on = "friend", lasts = 600 },
    [1014] = { on = "enemy", lasts = 24 },
    [1020] = { cd = 300, on = "self", lasts = 12 },
    [1022] = { cd = 300, on = "friend", lasts = 6 },
    [1032] = { on = "self" },
    [1038] = {},
    [1044] = { cd = 20, on = "friend", lasts = 10 },
    [1058] = { on = "friend", lasts = 12 },
    [1062] = { on = "enemy", lasts = 15 },
    [1066] = { on = "self" },
    [1075] = { on = "friend", lasts = 600 },
    [1079] = { on = "enemy", lasts = 12 },
    [1086] = { on = "self", lasts = 1800 },
    [1094] = { on = "enemy", lasts = 15 },
    [1098] = { on = "enemy", lasts = 300 },
    [1108] = { on = "enemy", lasts = 120 },
    [1120] = { on = "enemy", lasts = 15, charges = 1 },
    [1122] = { cd = 3600 },
    [1126] = { on = "friend", lasts = 3600 },
    [1130] = { on = "any", lasts = 120 },
    [1160] = { on = "enemy", lasts = 45 },
    [1161] = { cd = 600, on = "enemy", lasts = 6 },
    [1243] = { on = "friend", lasts = 3600 },
    [1244] = { on = "friend", lasts = 3600 },
    [1245] = { on = "friend", lasts = 3600 },
    [1430] = { on = "friend", lasts = 12 },
    [1459] = { on = "friend", lasts = 3600 },
    [1460] = { on = "friend", lasts = 3600 },
    [1461] = { on = "friend", lasts = 3600 },
    [1463] = { on = "self", lasts = 60 },
    [1464] = { cd = 15, noaura = true },
    [1495] = { cd = 5, noaura = true },
    [1499] = { cd = 30, on = "enemy", lasts = 10, auras = { 3355, 14308, 14309, 1324500, 1324501, 1324502 } },
    [1510] = { on = "self", lasts = 6 },
    [1513] = { cd = 30, on = "enemy", lasts = 10 },
    [1515] = { on = "enemy", lasts = 20 },
    [1543] = { cd = 15 },
    [1608] = { noaura = true },
    [1671] = { cd = 12, noaura = true },
    [1672] = { cd = 12, noaura = true },
    [1680] = { cd = 10, noaura = true },
    [1706] = { on = "self", lasts = 120 },
    [1714] = { on = "enemy", lasts = 30 },
    [1715] = { on = "enemy", lasts = 15 },
    [1719] = { cd = 1800, on = "self", lasts = 15 },
    [1725] = { cd = 30, on = "enemy", lasts = 10 },
    [1735] = { on = "enemy", lasts = 30 },
    [1742] = { cd = 5 },
    [1753] = { cd = 5 },
    [1754] = { cd = 5 },
    [1755] = { cd = 5 },
    [1756] = { cd = 5 },
    [1766] = { cd = 10, noaura = true },
    [1767] = { cd = 10, noaura = true },
    [1768] = { cd = 10, noaura = true },
    [1769] = { cd = 10, noaura = true },
    [1776] = { cd = 10, on = "enemy", lasts = 4 },
    [1777] = { cd = 10, on = "enemy", lasts = 4 },
    [1784] = { cd = 10, on = "self" },
    [1785] = { cd = 10, on = "self" },
    [1786] = { cd = 10, on = "self" },
    [1787] = { cd = 10, on = "self" },
    [1822] = { on = "enemy", lasts = 9 },
    [1823] = { on = "enemy", lasts = 9 },
    [1824] = { on = "enemy", lasts = 9 },
    [1833] = { on = "enemy", lasts = 4 },
    [1850] = { cd = 300, on = "self", lasts = 15 },
    [1856] = { cd = 300, on = "self", lasts = 10, auras = { 11327, 11329, 18461 } },
    [1857] = { cd = 300, on = "self", lasts = 10, auras = { 11327, 11329, 18461 } },
    [1866] = { cd = 10 },
    [1943] = { on = "enemy", lasts = 6 },
    [1949] = { on = "self", lasts = 15 },
    [1953] = { cd = 15, on = "self", lasts = 1 },
    [1966] = { cd = 10 },
    [1978] = { on = "enemy", lasts = 15 },
    [2070] = { on = "enemy", lasts = 35 },
    [2090] = { on = "friend", lasts = 12 },
    [2091] = { on = "friend", lasts = 12 },
    [2094] = { cd = 300, on = "enemy", lasts = 10 },
    [2096] = { on = "any", lasts = 60 },
    [2120] = { on = "self", lasts = 8 },
    [2121] = { on = "self", lasts = 8 },
    [2136] = { cd = 8, noaura = true },
    [2137] = { cd = 8, noaura = true },
    [2138] = { cd = 8, noaura = true },
    [2139] = { cd = 30, noaura = true },
    [2457] = { on = "self" },
    [2458] = { on = "self" },
    [2484] = { cd = 15, on = "self", auras = { 6474 } },
    [2495] = { cd = 10 },
    [2565] = { cd = 5, on = "self", lasts = 7, charges = 2 },
    [2637] = { on = "enemy", lasts = 20 },
    [2643] = { cd = 6, noaura = true },
    [2645] = { on = "self" },
    [2649] = { cd = 5 },
    [2651] = { cd = 300, on = "self", lasts = 15, charges = 3 },
    [2652] = { on = "self", lasts = 600 },
    [2687] = { cd = 60, on = "self", lasts = 10, auras = { 29131 } },
    [2767] = { on = "enemy", lasts = 18 },
    [2791] = { on = "friend", lasts = 3600 },
    [2800] = { cd = 1200 },
    [2812] = { cd = 60, noaura = true },
    [2835] = {},
    [2837] = {},
    [2860] = { cd = 6, noaura = true },
    [2878] = { cd = 30, on = "enemy", lasts = 10 },
    [2893] = { on = "friend", lasts = 8 },
    [2908] = { on = "enemy", lasts = 15 },
    [2941] = { on = "enemy", lasts = 15 },
    [2943] = { on = "enemy", lasts = 120 },
    [2944] = { cd = 24, on = "enemy", lasts = 24 },
    [2947] = { on = "friend", lasts = 180 },
    [2970] = { on = "friend", lasts = 600 },
    [2973] = { cd = 6, noaura = true },
    [2974] = { on = "enemy", lasts = 10 },
    [2983] = { cd = 300, on = "self", lasts = 15 },
    [3034] = { cd = 15, on = "enemy", lasts = 8 },
    [3043] = { on = "enemy", lasts = 20 },
    [3044] = { cd = 6, noaura = true },
    [3045] = { cd = 300, on = "self", lasts = 15 },
    [3111] = { on = "pet", lasts = 5 },
    [3140] = { on = "enemy", lasts = 8 },
    [3355] = { on = "enemy", lasts = 10 },
    [3420] = {},
    [3421] = {},
    [3599] = {},
    [3627] = { on = "friend", lasts = 12 },
    [3661] = { on = "pet", lasts = 5 },
    [3662] = { on = "pet", lasts = 5 },
    [3698] = { on = "pet", lasts = 10 },
    [3699] = { on = "pet", lasts = 10 },
    [3700] = { on = "pet", lasts = 10 },
    [3716] = { cd = 5 },
    [3747] = { cd = 4, on = "friend", lasts = 30 },
    [4511] = { cd = 10, on = "self" },
    [5116] = { cd = 12, on = "enemy", lasts = 4 },
    [5118] = { on = "self" },
    [5138] = { on = "enemy", lasts = 5 },
    [5143] = { on = "self", lasts = 3 },
    [5144] = { on = "self", lasts = 4 },
    [5145] = { on = "self", lasts = 5 },
    [5171] = { on = "self", lasts = 6 },
    [5195] = { on = "enemy", lasts = 18 },
    [5196] = { on = "enemy", lasts = 21 },
    [5209] = { cd = 600, on = "enemy", lasts = 6 },
    [5211] = { cd = 60, on = "enemy", lasts = 2 },
    [5215] = { cd = 10, on = "self" },
    [5229] = { cd = 60, on = "self", lasts = 10 },
    [5232] = { on = "friend", lasts = 3600 },
    [5234] = { on = "friend", lasts = 3600 },
    [5242] = { on = "self", lasts = 180 },
    [5246] = { cd = 180, on = "enemy", lasts = 8 },
    [5277] = { cd = 300, on = "self", lasts = 15 },
    [5287] = { on = "friend", lasts = 3600, auras = { 1126, 5232, 5234, 6756, 8907, 9884, 9885, 21849, 21850 } },
    [5308] = { on = "self", lasts = 1, auras = { 26651 } },
    [5384] = { cd = 30, on = "self", lasts = 360 },
    [5394] = {},
    [5484] = { cd = 40, on = "enemy", lasts = 10 },
    [5487] = { on = "self" },
    [5569] = { cd = 10 },
    [5570] = { on = "enemy", lasts = 12 },
    [5573] = { cd = 300, on = "self", lasts = 8 },
    [5588] = { cd = 60, on = "enemy", lasts = 4 },
    [5589] = { cd = 60, on = "enemy", lasts = 5 },
    [5599] = { cd = 300, on = "friend", lasts = 8 },
    [5614] = { cd = 15, noaura = true },
    [5615] = { cd = 15, noaura = true },
    [5627] = { cd = 30, on = "enemy", lasts = 15 },
    [5675] = {},
    [5677] = { on = "self" },
    [5678] = { on = "self", auras = { 5677, 10491, 10493, 10494 } },
    [5697] = { on = "friend", lasts = 600 },
    [5720] = { noaura = true },
    [5723] = { noaura = true },
    [5730] = { cd = 30 },
    [5740] = { on = "self", lasts = 8 },
    [5763] = {},
    [5782] = { on = "enemy", lasts = 10 },
    [6065] = { cd = 4, on = "friend", lasts = 30 },
    [6066] = { cd = 4, on = "friend", lasts = 30 },
    [6074] = { on = "friend", lasts = 15 },
    [6075] = { on = "friend", lasts = 15 },
    [6076] = { on = "friend", lasts = 15 },
    [6077] = { on = "friend", lasts = 15 },
    [6078] = { on = "friend", lasts = 15 },
    [6117] = { on = "self", lasts = 1800 },
    [6131] = { cd = 25, on = "enemy", lasts = 8 },
    [6136] = { on = "enemy", lasts = 5 },
    [6141] = { on = "self", lasts = 8 },
    [6143] = { cd = 30, on = "self", lasts = 30 },
    [6150] = { on = "self", lasts = 12 },
    [6178] = { cd = 15, on = "enemy", lasts = 1, auras = { 7922 } },
    [6190] = { on = "enemy", lasts = 45 },
    [6192] = { on = "self", lasts = 180 },
    [6196] = { on = "self", lasts = 60 },
    [6197] = { on = "self", lasts = 60 },
    [6205] = { on = "enemy", lasts = 120 },
    [6213] = { on = "enemy", lasts = 15 },
    [6215] = { on = "enemy", lasts = 20 },
    [6217] = { on = "enemy", lasts = 24 },
    [6219] = { on = "self", lasts = 8 },
    [6222] = { on = "enemy", lasts = 15 },
    [6223] = { on = "enemy", lasts = 18 },
    [6226] = { on = "enemy", lasts = 5 },
    [6229] = { cd = 30, on = "self", lasts = 30 },
    [6262] = { noaura = true },
    [6263] = { noaura = true },
    [6343] = { cd = 6, on = "enemy", lasts = 10 },
    [6346] = { cd = 180, on = "friend", lasts = 180, charges = 1 },
    [6353] = { cd = 60, noaura = true },
    [6358] = { on = "enemy", lasts = 15 },
    [6360] = { cd = 4 },
    [6363] = {},
    [6364] = {},
    [6365] = {},
    [6375] = {},
    [6377] = {},
    [6390] = { cd = 30 },
    [6391] = { cd = 30 },
    [6392] = { cd = 30 },
    [6474] = { on = "self" },
    [6495] = { on = "self", lasts = 300 },
    [6546] = { on = "enemy", lasts = 12 },
    [6547] = { on = "enemy", lasts = 15 },
    [6548] = { on = "enemy", lasts = 18 },
    [6552] = { cd = 10, noaura = true },
    [6554] = { cd = 10, noaura = true },
    [6572] = { cd = 5, noaura = true },
    [6574] = { cd = 5, noaura = true },
    [6673] = { on = "self", lasts = 180 },
    [6756] = { on = "friend", lasts = 3600 },
    [6768] = { cd = 10 },
    [6770] = { on = "enemy", lasts = 25 },
    [6774] = { on = "self", lasts = 6 },
    [6783] = { cd = 10, on = "self" },
    [6788] = { on = "any", lasts = 15 },
    [6789] = { cd = 120, on = "enemy", lasts = 3 },
    [6795] = { cd = 8, on = "enemy", lasts = 3 },
    [6798] = { cd = 60, on = "enemy", lasts = 3 },
    [6807] = { noaura = true },
    [6808] = { noaura = true },
    [6809] = { noaura = true },
    [6940] = { on = "friend", lasts = 30 },
    [7128] = { on = "self", lasts = 600, charges = 20 },
    [7294] = { on = "self" },
    [7300] = { on = "self", lasts = 1800 },
    [7301] = { on = "self", lasts = 1800 },
    [7302] = { on = "self", lasts = 1800 },
    [7320] = { on = "self", lasts = 1800 },
    [7322] = { on = "enemy", lasts = 7 },
    [7369] = { noaura = true },
    [7371] = { cd = 25, on = "self", lasts = 4, charges = 1 },
    [7372] = { on = "enemy", lasts = 15 },
    [7373] = { on = "enemy", lasts = 15 },
    [7379] = { cd = 5, noaura = true },
    [7384] = { cd = 5, noaura = true },
    [7386] = { on = "enemy", lasts = 30, stacks = 5 },
    [7400] = { cd = 120, on = "enemy", lasts = 6 },
    [7402] = { cd = 120, on = "enemy", lasts = 6 },
    [7405] = { on = "enemy", lasts = 30, stacks = 5 },
    [7646] = { on = "enemy", lasts = 120 },
    [7648] = { on = "enemy", lasts = 18 },
    [7651] = { on = "enemy", lasts = 5 },
    [7658] = { on = "enemy", lasts = 120 },
    [7659] = { on = "enemy", lasts = 120 },
    [7744] = { cd = 120, on = "self", lasts = 0.1 },
    [7809] = { cd = 5 },
    [7810] = { cd = 5 },
    [7811] = { cd = 5 },
    [7812] = { on = "pet", lasts = 30 },
    [7813] = { cd = 4 },
    [7814] = { cd = 12, noaura = true },
    [7815] = { cd = 12, noaura = true },
    [7816] = { cd = 12, noaura = true },
    [7870] = { on = "self", lasts = 300 },
    [7887] = { cd = 5, noaura = true },
    [8033] = {},
    [8038] = {},
    [8042] = { cd = 6, noaura = true },
    [8044] = { cd = 6, noaura = true },
    [8045] = { cd = 6, noaura = true },
    [8046] = { cd = 6, noaura = true },
    [8050] = { cd = 6, on = "enemy", lasts = 12 },
    [8052] = { cd = 6, on = "enemy", lasts = 12 },
    [8053] = { cd = 6, on = "enemy", lasts = 12 },
    [8056] = { cd = 6, on = "enemy", lasts = 8 },
    [8058] = { cd = 6, on = "enemy", lasts = 8 },
    [8071] = {},
    [8075] = { on = "self", auras = { 8076, 8162, 8163, 10441, 25362 } },
    [8076] = { on = "self" },
    [8092] = { cd = 8, noaura = true },
    [8102] = { cd = 8, noaura = true },
    [8103] = { cd = 8, noaura = true },
    [8104] = { cd = 8, noaura = true },
    [8105] = { cd = 8, noaura = true },
    [8106] = { cd = 8, noaura = true },
    [8122] = { cd = 30, on = "enemy", lasts = 8 },
    [8124] = { cd = 30, on = "enemy", lasts = 8 },
    [8134] = { on = "self", lasts = 600, charges = 3 },
    [8143] = { on = "self", auras = { 8145 } },
    [8145] = { on = "self" },
    [8154] = {},
    [8155] = {},
    [8160] = { on = "self", auras = { 8076, 8162, 8163, 10441, 25362 } },
    [8161] = { on = "self", auras = { 8076, 8162, 8163, 10441, 25362 } },
    [8162] = { on = "self" },
    [8163] = { on = "self" },
    [8166] = { on = "self", auras = { 8167 } },
    [8167] = { on = "self" },
    [8170] = { on = "self", auras = { 8172 } },
    [8172] = { on = "self" },
    [8177] = { cd = 15, on = "self", charges = 1, auras = { 8178, 8179 } },
    [8178] = { on = "self", charges = 1 },
    [8179] = { on = "self" },
    [8181] = { on = "self", auras = { 8182, 10476, 10477 } },
    [8182] = { on = "self" },
    [8184] = { on = "self", auras = { 8185, 10534, 10535 } },
    [8185] = { on = "self" },
    [8190] = {},
    [8192] = { on = "enemy", lasts = 15 },
    [8198] = { cd = 6, on = "enemy", lasts = 14 },
    [8204] = { cd = 6, on = "enemy", lasts = 18 },
    [8205] = { cd = 6, on = "enemy", lasts = 22 },
    [8227] = { on = "self", auras = { 8230, 8250, 10521, 15036 } },
    [8230] = { on = "self" },
    [8249] = { on = "self", auras = { 8230, 8250, 10521, 15036 } },
    [8250] = { on = "self" },
    [8288] = { on = "enemy", lasts = 15, charges = 1 },
    [8289] = { on = "enemy", lasts = 15, charges = 1 },
    [8316] = { on = "friend", lasts = 180 },
    [8317] = { on = "friend", lasts = 180 },
    [8380] = { on = "enemy", lasts = 30, stacks = 5 },
    [8400] = { on = "enemy", lasts = 8 },
    [8401] = { on = "enemy", lasts = 8 },
    [8402] = { on = "enemy", lasts = 8 },
    [8406] = { on = "enemy", lasts = 7 },
    [8407] = { on = "enemy", lasts = 8 },
    [8408] = { on = "enemy", lasts = 8 },
    [8412] = { cd = 8, noaura = true },
    [8413] = { cd = 8, noaura = true },
    [8416] = { on = "self", lasts = 5 },
    [8417] = { on = "self", lasts = 5 },
    [8422] = { on = "self", lasts = 8 },
    [8423] = { on = "self", lasts = 8 },
    [8427] = { on = "self", lasts = 8 },
    [8450] = { on = "friend", lasts = 600 },
    [8451] = { on = "friend", lasts = 600 },
    [8455] = { on = "friend", lasts = 600 },
    [8457] = { cd = 30, on = "self", lasts = 30 },
    [8458] = { cd = 30, on = "self", lasts = 30 },
    [8461] = { cd = 30, on = "self", lasts = 30 },
    [8462] = { cd = 30, on = "self", lasts = 30 },
    [8492] = { cd = 10, on = "enemy", lasts = 6 },
    [8494] = { on = "self", lasts = 60 },
    [8495] = { on = "self", lasts = 60 },
    [8512] = { on = "self", auras = { 8515, 10609, 10612 } },
    [8515] = { on = "self" },
    [8629] = { cd = 10, on = "enemy", lasts = 4 },
    [8631] = { on = "enemy", lasts = 18 },
    [8632] = { on = "enemy", lasts = 18 },
    [8633] = { on = "enemy", lasts = 18 },
    [8637] = { cd = 10 },
    [8639] = { on = "enemy", lasts = 6 },
    [8640] = { on = "enemy", lasts = 6 },
    [8643] = { cd = 20, on = "enemy", lasts = 1 },
    [8647] = { on = "enemy", lasts = 30 },
    [8649] = { on = "enemy", lasts = 30 },
    [8650] = { on = "enemy", lasts = 30 },
    [8694] = {},
    [8696] = { cd = 300, on = "self", lasts = 15 },
    [8820] = { cd = 15, noaura = true },
    [8835] = { on = "self", auras = { 8836, 10626, 25360 } },
    [8836] = { on = "self" },
    [8907] = { on = "friend", lasts = 3600 },
    [8910] = { on = "friend", lasts = 12 },
    [8914] = { on = "friend", lasts = 600 },
    [8918] = { cd = 300, on = "self", lasts = 10 },
    [8921] = { on = "enemy", lasts = 9 },
    [8924] = { on = "enemy", lasts = 12 },
    [8925] = { on = "enemy", lasts = 12 },
    [8926] = { on = "enemy", lasts = 12 },
    [8927] = { on = "enemy", lasts = 12 },
    [8928] = { on = "enemy", lasts = 12 },
    [8929] = { on = "enemy", lasts = 12 },
    [8936] = { on = "friend", lasts = 21 },
    [8938] = { on = "friend", lasts = 21 },
    [8939] = { on = "friend", lasts = 21 },
    [8940] = { on = "friend", lasts = 21 },
    [8941] = { on = "friend", lasts = 21 },
    [8955] = { on = "enemy", lasts = 15 },
    [8972] = { noaura = true },
    [8983] = { cd = 60, on = "enemy", lasts = 4 },
    [8998] = { cd = 10 },
    [9000] = { cd = 10 },
    [9005] = { on = "enemy", lasts = 2 },
    [9035] = { on = "enemy", lasts = 120 },
    [9484] = { on = "enemy", lasts = 30 },
    [9485] = { on = "enemy", lasts = 40 },
    [9490] = { on = "enemy", lasts = 30 },
    [9492] = { on = "enemy", lasts = 12 },
    [9493] = { on = "enemy", lasts = 12 },
    [9578] = { cd = 30, on = "self", lasts = 10 },
    [9579] = { cd = 30, on = "self", lasts = 10 },
    [9592] = { cd = 30, on = "self", lasts = 10 },
    [9634] = { on = "self" },
    [9745] = { noaura = true },
    [9747] = { on = "enemy", lasts = 30 },
    [9749] = { on = "enemy", lasts = 40 },
    [9750] = { on = "friend", lasts = 21 },
    [9752] = { on = "enemy", lasts = 12 },
    [9756] = { on = "friend", lasts = 600 },
    [9821] = { cd = 300, on = "self", lasts = 15 },
    [9823] = { on = "enemy", lasts = 2 },
    [9827] = { on = "enemy", lasts = 2 },
    [9833] = { on = "enemy", lasts = 12 },
    [9834] = { on = "enemy", lasts = 12 },
    [9835] = { on = "enemy", lasts = 12 },
    [9839] = { on = "friend", lasts = 12 },
    [9840] = { on = "friend", lasts = 12 },
    [9841] = { on = "friend", lasts = 12 },
    [9852] = { on = "enemy", lasts = 24 },
    [9853] = { on = "enemy", lasts = 27 },
    [9856] = { on = "friend", lasts = 21 },
    [9857] = { on = "friend", lasts = 21 },
    [9858] = { on = "friend", lasts = 21 },
    [9862] = { cd = 300, on = "self", lasts = 10 },
    [9863] = { cd = 300, on = "self", lasts = 10 },
    [9880] = { noaura = true },
    [9881] = { noaura = true },
    [9884] = { on = "friend", lasts = 3600 },
    [9885] = { on = "friend", lasts = 3600 },
    [9892] = { cd = 10 },
    [9894] = { on = "enemy", lasts = 12 },
    [9896] = { on = "enemy", lasts = 12 },
    [9898] = { on = "enemy", lasts = 30 },
    [9901] = { on = "enemy", lasts = 15 },
    [9904] = { on = "enemy", lasts = 9 },
    [9907] = { on = "enemy", lasts = 40 },
    [9910] = { on = "friend", lasts = 600 },
    [9913] = { cd = 10, on = "self" },
    [10059] = { cd = 60 },
    [10060] = { cd = 180, on = "friend", lasts = 15 },
    [10148] = { on = "enemy", lasts = 8 },
    [10149] = { on = "enemy", lasts = 8 },
    [10150] = { on = "enemy", lasts = 8 },
    [10151] = { on = "enemy", lasts = 8 },
    [10156] = { on = "friend", lasts = 3600 },
    [10157] = { on = "friend", lasts = 3600 },
    [10159] = { cd = 10, on = "enemy", lasts = 6 },
    [10160] = { cd = 10, on = "enemy", lasts = 6 },
    [10161] = { cd = 10, on = "enemy", lasts = 6 },
    [10169] = { on = "friend", lasts = 600 },
    [10170] = { on = "friend", lasts = 600 },
    [10173] = { on = "friend", lasts = 600 },
    [10174] = { on = "friend", lasts = 600 },
    [10177] = { cd = 30, on = "self", lasts = 30 },
    [10179] = { on = "enemy", lasts = 9 },
    [10180] = { on = "enemy", lasts = 9 },
    [10181] = { on = "enemy", lasts = 9 },
    [10185] = { on = "self", lasts = 8 },
    [10186] = { on = "self", lasts = 8 },
    [10187] = { on = "self", lasts = 8 },
    [10191] = { on = "self", lasts = 60 },
    [10192] = { on = "self", lasts = 60 },
    [10193] = { on = "self", lasts = 60 },
    [10197] = { cd = 8, noaura = true },
    [10199] = { cd = 8, noaura = true },
    [10211] = { on = "self", lasts = 5 },
    [10212] = { on = "self", lasts = 5 },
    [10215] = { on = "self", lasts = 8 },
    [10216] = { on = "self", lasts = 8 },
    [10219] = { on = "self", lasts = 1800 },
    [10220] = { on = "self", lasts = 1800 },
    [10223] = { cd = 30, on = "self", lasts = 30 },
    [10225] = { cd = 30, on = "self", lasts = 30 },
    [10230] = { cd = 25, on = "enemy", lasts = 8 },
    [10278] = { cd = 300, on = "friend", lasts = 10 },
    [10290] = { on = "self" },
    [10291] = { on = "self" },
    [10292] = { on = "self" },
    [10293] = { on = "self" },
    [10298] = { on = "self" },
    [10299] = { on = "self" },
    [10300] = { on = "self" },
    [10301] = { on = "self" },
    [10308] = { cd = 60, on = "enemy", lasts = 6 },
    [10310] = { cd = 1200 },
    [10312] = { cd = 15, noaura = true },
    [10313] = { cd = 15, noaura = true },
    [10314] = { cd = 15, noaura = true },
    [10318] = { cd = 60, noaura = true },
    [10326] = { cd = 30, on = "enemy", lasts = 20 },
    [10332] = { cd = 10 },
    [10333] = { cd = 10 },
    [10406] = {},
    [10407] = {},
    [10408] = {},
    [10412] = { cd = 6, noaura = true },
    [10413] = { cd = 6, noaura = true },
    [10414] = { cd = 6, noaura = true },
    [10427] = { cd = 30 },
    [10428] = { cd = 30 },
    [10431] = { on = "self", lasts = 600, charges = 3 },
    [10432] = { on = "self", lasts = 600, charges = 3 },
    [10437] = {},
    [10438] = {},
    [10441] = { on = "self" },
    [10442] = { on = "self", auras = { 8076, 8162, 8163, 10441, 25362 } },
    [10447] = { cd = 6, on = "enemy", lasts = 12 },
    [10448] = { cd = 6, on = "enemy", lasts = 12 },
    [10456] = {},
    [10462] = {},
    [10463] = {},
    [10472] = { cd = 6, on = "enemy", lasts = 8 },
    [10473] = { cd = 6, on = "enemy", lasts = 8 },
    [10476] = { on = "self" },
    [10477] = { on = "self" },
    [10478] = { on = "self", auras = { 8182, 10476, 10477 } },
    [10479] = { on = "self", auras = { 8182, 10476, 10477 } },
    [10491] = { on = "self" },
    [10493] = { on = "self" },
    [10494] = { on = "self" },
    [10495] = { on = "self", auras = { 5677, 10491, 10493, 10494 } },
    [10496] = { on = "self", auras = { 5677, 10491, 10493, 10494 } },
    [10497] = { on = "self", auras = { 5677, 10491, 10493, 10494 } },
    [10521] = { on = "self" },
    [10526] = { on = "self", auras = { 8230, 8250, 10521, 15036 } },
    [10534] = { on = "self" },
    [10535] = { on = "self" },
    [10537] = { on = "self", auras = { 8185, 10534, 10535 } },
    [10538] = { on = "self", auras = { 8185, 10534, 10535 } },
    [10585] = {},
    [10586] = {},
    [10587] = {},
    [10595] = {},
    [10600] = {},
    [10601] = {},
    [10605] = { cd = 6, noaura = true },
    [10609] = { on = "self" },
    [10612] = { on = "self" },
    [10613] = { on = "self", auras = { 8515, 10609, 10612 } },
    [10614] = { on = "self", auras = { 8515, 10609, 10612 } },
    [10626] = { on = "self" },
    [10627] = { on = "self", auras = { 8836, 10626, 25360 } },
    [10797] = { cd = 30, on = "enemy", lasts = 6 },
    [10888] = { cd = 30, on = "enemy", lasts = 8 },
    [10890] = { cd = 30, on = "enemy", lasts = 8 },
    [10892] = { on = "enemy", lasts = 18 },
    [10893] = { on = "enemy", lasts = 18 },
    [10894] = { on = "enemy", lasts = 18 },
    [10898] = { cd = 4, on = "friend", lasts = 30 },
    [10899] = { cd = 4, on = "friend", lasts = 30 },
    [10900] = { cd = 4, on = "friend", lasts = 30 },
    [10901] = { cd = 4, on = "friend", lasts = 30 },
    [10909] = { on = "any", lasts = 60 },
    [10927] = { on = "friend", lasts = 15 },
    [10928] = { on = "friend", lasts = 15 },
    [10929] = { on = "friend", lasts = 15 },
    [10937] = { on = "friend", lasts = 3600 },
    [10938] = { on = "friend", lasts = 3600 },
    [10941] = { cd = 30, on = "self", lasts = 10 },
    [10942] = { cd = 30, on = "self", lasts = 10 },
    [10945] = { cd = 8, noaura = true },
    [10946] = { cd = 8, noaura = true },
    [10947] = { cd = 8, noaura = true },
    [10951] = { on = "self", lasts = 600, charges = 20 },
    [10952] = { on = "self", lasts = 600, charges = 20 },
    [10953] = { on = "enemy", lasts = 15 },
    [10955] = { on = "enemy", lasts = 50 },
    [10957] = { on = "friend", lasts = 600 },
    [10958] = { on = "friend", lasts = 600 },
    [11071] = { on = "self" },
    [11095] = { on = "enemy" },
    [11103] = { on = "self" },
    [11113] = { cd = 45, on = "enemy", lasts = 6 },
    [11119] = { on = "self" },
    [11129] = { cd = 180, on = "self", charges = 3 },
    [11180] = { on = "self", charges = 1 },
    [11185] = { on = "self" },
    [11197] = { on = "enemy", lasts = 30 },
    [11198] = { on = "enemy", lasts = 30 },
    [11213] = { on = "self" },
    [11255] = { on = "self" },
    [11273] = { on = "enemy", lasts = 6 },
    [11274] = { on = "enemy", lasts = 6 },
    [11275] = { on = "enemy", lasts = 6 },
    [11285] = { cd = 10, on = "enemy", lasts = 4 },
    [11286] = { cd = 10, on = "enemy", lasts = 4 },
    [11289] = { on = "enemy", lasts = 18 },
    [11290] = { on = "enemy", lasts = 18 },
    [11297] = { on = "enemy", lasts = 45 },
    [11303] = { cd = 10 },
    [11305] = { cd = 300, on = "self", lasts = 15 },
    [11327] = { on = "self", lasts = 10 },
    [11329] = { on = "self", lasts = 10 },
    [11357] = {},
    [11358] = {},
    [11366] = { on = "enemy", lasts = 12 },
    [11400] = {},
    [11416] = { cd = 60 },
    [11417] = { cd = 60 },
    [11418] = { cd = 60 },
    [11419] = { cd = 60 },
    [11420] = { cd = 60 },
    [11426] = { cd = 30, on = "self", lasts = 60 },
    [11549] = { on = "self", lasts = 180 },
    [11550] = { on = "self", lasts = 180 },
    [11551] = { on = "self", lasts = 180 },
    [11554] = { on = "enemy", lasts = 45 },
    [11555] = { on = "enemy", lasts = 45 },
    [11556] = { on = "enemy", lasts = 45 },
    [11564] = { noaura = true },
    [11565] = { noaura = true },
    [11566] = { noaura = true },
    [11567] = { noaura = true },
    [11572] = { on = "enemy", lasts = 21 },
    [11573] = { on = "enemy", lasts = 21 },
    [11574] = { on = "enemy", lasts = 21 },
    [11578] = { cd = 15, on = "enemy", lasts = 1, auras = { 7922 } },
    [11580] = { cd = 6, on = "enemy", lasts = 26 },
    [11581] = { cd = 6, on = "enemy", lasts = 30 },
    [11584] = { cd = 5, noaura = true },
    [11585] = { cd = 5, noaura = true },
    [11596] = { on = "enemy", lasts = 30, stacks = 5 },
    [11597] = { on = "enemy", lasts = 30, stacks = 5 },
    [11600] = { cd = 5, noaura = true },
    [11601] = { cd = 5, noaura = true },
    [11604] = { cd = 15, noaura = true },
    [11605] = { cd = 15, noaura = true },
    [11608] = { noaura = true },
    [11609] = { noaura = true },
    [11665] = { on = "enemy", lasts = 15 },
    [11667] = { on = "enemy", lasts = 15 },
    [11668] = { on = "enemy", lasts = 15 },
    [11671] = { on = "enemy", lasts = 18 },
    [11672] = { on = "enemy", lasts = 18 },
    [11675] = { on = "enemy", lasts = 15, charges = 1 },
    [11677] = { on = "self", lasts = 8 },
    [11678] = { on = "self", lasts = 8 },
    [11683] = { on = "self", lasts = 15 },
    [11684] = { on = "self", lasts = 15 },
    [11693] = { on = "pet", lasts = 10 },
    [11694] = { on = "pet", lasts = 10 },
    [11695] = { on = "pet", lasts = 10 },
    [11699] = { on = "enemy", lasts = 5 },
    [11700] = { on = "enemy", lasts = 5 },
    [11703] = { on = "enemy", lasts = 5 },
    [11704] = { on = "enemy", lasts = 5 },
    [11707] = { on = "enemy", lasts = 120 },
    [11708] = { on = "enemy", lasts = 120 },
    [11711] = { on = "enemy", lasts = 24 },
    [11712] = { on = "enemy", lasts = 24 },
    [11713] = { on = "enemy", lasts = 24 },
    [11717] = { on = "enemy", lasts = 120 },
    [11719] = { on = "enemy", lasts = 30 },
    [11732] = { noaura = true },
    [11733] = { on = "self", lasts = 1800 },
    [11734] = { on = "self", lasts = 1800 },
    [11735] = { on = "self", lasts = 1800 },
    [11739] = { cd = 30, on = "self", lasts = 30 },
    [11740] = { cd = 30, on = "self", lasts = 30 },
    [11743] = { on = "friend", lasts = 600 },
    [11770] = { on = "friend", lasts = 180 },
    [11771] = { on = "friend", lasts = 180 },
    [11774] = { cd = 5 },
    [11775] = { cd = 5 },
    [11778] = { cd = 12, noaura = true },
    [11779] = { cd = 12, noaura = true },
    [11780] = { cd = 12, noaura = true },
    [11784] = { cd = 4 },
    [11785] = { cd = 4 },
    [11958] = { cd = 300, on = "self", lasts = 10 },
    [12042] = { cd = 180, on = "self", lasts = 15 },
    [12043] = { cd = 180, on = "self", charges = 1 },
    [12051] = { cd = 480, on = "self", lasts = 8 },
    [12289] = { on = "enemy" },
    [12292] = { cd = 30, on = "self", lasts = 20, charges = 5 },
    [12294] = { cd = 6, on = "enemy", lasts = 10 },
    [12311] = { on = "self" },
    [12317] = { on = "self" },
    [12319] = { on = "self" },
    [12323] = { on = "enemy", lasts = 6 },
    [12328] = { cd = 180, on = "self", lasts = 30 },
    [12355] = { on = "enemy", lasts = 2 },
    [12472] = { cd = 600 },
    [12484] = { on = "enemy", lasts = 1.5 },
    [12494] = { on = "enemy", lasts = 5 },
    [12505] = { on = "enemy", lasts = 12 },
    [12522] = { on = "enemy", lasts = 12 },
    [12523] = { on = "enemy", lasts = 12 },
    [12524] = { on = "enemy", lasts = 12 },
    [12525] = { on = "enemy", lasts = 12 },
    [12526] = { on = "enemy", lasts = 12 },
    [12536] = { on = "self", lasts = 15, charges = 1 },
    [12579] = { on = "enemy", lasts = 15, stacks = 5 },
    [12809] = { cd = 45, on = "enemy", lasts = 5 },
    [12824] = { on = "enemy", lasts = 30 },
    [12825] = { on = "enemy", lasts = 40 },
    [12826] = { on = "enemy", lasts = 50 },
    [12834] = { on = "self" },
    [12880] = { on = "self", lasts = 12 },
    [12966] = { on = "self", lasts = 15, charges = 3 },
    [12975] = { cd = 180, on = "self", lasts = 20, auras = { 12976 } },
    [12976] = { on = "self", lasts = 20 },
    [13018] = { cd = 45, on = "enemy", lasts = 6 },
    [13019] = { cd = 45, on = "enemy", lasts = 6 },
    [13020] = { cd = 45, on = "enemy", lasts = 6 },
    [13021] = { cd = 45, on = "enemy", lasts = 6 },
    [13031] = { cd = 30, on = "self", lasts = 60 },
    [13032] = { cd = 30, on = "self", lasts = 60 },
    [13033] = { cd = 30, on = "self", lasts = 60 },
    [13159] = { on = "self" },
    [13161] = { on = "self" },
    [13163] = { on = "self" },
    [13165] = { on = "self" },
    [13220] = {},
    [13228] = {},
    [13229] = {},
    [13230] = {},
    [13542] = { on = "pet", lasts = 5 },
    [13543] = { on = "pet", lasts = 5 },
    [13544] = { on = "pet", lasts = 5 },
    [13549] = { on = "enemy", lasts = 15 },
    [13550] = { on = "enemy", lasts = 15 },
    [13551] = { on = "enemy", lasts = 15 },
    [13552] = { on = "enemy", lasts = 15 },
    [13553] = { on = "enemy", lasts = 15 },
    [13554] = { on = "enemy", lasts = 15 },
    [13555] = { on = "enemy", lasts = 15 },
    [13750] = { cd = 300, on = "self", lasts = 15 },
    [13795] = { cd = 30 },
    [13797] = { on = "enemy", lasts = 15 },
    [13809] = { cd = 30, on = "any", lasts = 30, auras = { 13810 } },
    [13810] = { on = "any", lasts = 30 },
    [13813] = { cd = 30 },
    [13877] = { cd = 120, on = "self", lasts = 15 },
    [13896] = { cd = 180, on = "self", lasts = 15 },
    [13908] = { cd = 600, noaura = true },
    [14143] = { on = "self", lasts = 20, charges = 1 },
    [14144] = { on = "self" },
    [14177] = { cd = 180, on = "self", charges = 1 },
    [14183] = { cd = 120, on = "self", lasts = 20 },
    [14185] = { cd = 600 },
    [14251] = { cd = 6, on = "enemy", lasts = 6 },
    [14260] = { cd = 6, noaura = true },
    [14261] = { cd = 6, noaura = true },
    [14262] = { cd = 6, noaura = true },
    [14263] = { cd = 6, noaura = true },
    [14264] = { cd = 6, noaura = true },
    [14265] = { cd = 6, noaura = true },
    [14266] = { cd = 6, noaura = true },
    [14267] = { on = "enemy", lasts = 10 },
    [14268] = { on = "enemy", lasts = 10 },
    [14269] = { cd = 5, noaura = true },
    [14270] = { cd = 5, noaura = true },
    [14271] = { cd = 5, noaura = true },
    [14272] = { cd = 5 },
    [14273] = { cd = 5 },
    [14274] = { cd = 8 },
    [14278] = { cd = 20, on = "self", lasts = 7 },
    [14279] = { cd = 15, on = "enemy", lasts = 8 },
    [14280] = { cd = 15, on = "enemy", lasts = 8 },
    [14281] = { cd = 6, noaura = true },
    [14282] = { cd = 6, noaura = true },
    [14283] = { cd = 6, noaura = true },
    [14284] = { cd = 6, noaura = true },
    [14285] = { cd = 6, noaura = true },
    [14286] = { cd = 6, noaura = true },
    [14287] = { cd = 6, noaura = true },
    [14294] = { on = "self", lasts = 6 },
    [14295] = { on = "self", lasts = 6 },
    [14298] = { on = "enemy", lasts = 15 },
    [14299] = { on = "enemy", lasts = 15 },
    [14300] = { on = "enemy", lasts = 15 },
    [14301] = { on = "enemy", lasts = 15 },
    [14302] = { cd = 30 },
    [14303] = { cd = 30 },
    [14304] = { cd = 30 },
    [14305] = { cd = 30 },
    [14308] = { on = "enemy", lasts = 15 },
    [14309] = { on = "enemy", lasts = 20 },
    [14310] = { cd = 30 },
    [14311] = { cd = 30 },
    [14316] = { cd = 30 },
    [14317] = { cd = 30 },
    [14318] = { on = "self" },
    [14319] = { on = "self" },
    [14320] = { on = "self" },
    [14321] = { on = "self" },
    [14322] = { on = "self" },
    [14323] = { on = "any", lasts = 120 },
    [14324] = { on = "any", lasts = 120 },
    [14325] = { on = "any", lasts = 120 },
    [14326] = { cd = 30, on = "enemy", lasts = 15 },
    [14327] = { cd = 30, on = "enemy", lasts = 20 },
    [14531] = { on = "self" },
    [14751] = { cd = 180, on = "self", charges = 1 },
    [14752] = { on = "friend", lasts = 3600 },
    [14818] = { on = "friend", lasts = 3600 },
    [14819] = { on = "friend", lasts = 3600 },
    [14892] = { on = "self" },
    [14893] = { on = "friend", lasts = 15 },
    [14909] = { on = "self" },
    [14914] = { on = "enemy", lasts = 10 },
    [14916] = { cd = 5 },
    [14917] = { cd = 5 },
    [14918] = { cd = 5 },
    [14919] = { cd = 5 },
    [14920] = { cd = 5 },
    [14921] = { cd = 5 },
    [15036] = { on = "self" },
    [15107] = { on = "self", auras = { 15108, 15109, 15110 } },
    [15108] = { on = "self" },
    [15109] = { on = "self" },
    [15110] = { on = "self" },
    [15111] = { on = "self", auras = { 15108, 15109, 15110 } },
    [15112] = { on = "self", auras = { 15108, 15109, 15110 } },
    [15257] = { on = "self" },
    [15258] = { on = "enemy", lasts = 15, stacks = 5 },
    [15261] = { on = "enemy", lasts = 10 },
    [15262] = { on = "enemy", lasts = 10 },
    [15263] = { on = "enemy", lasts = 10 },
    [15264] = { on = "enemy", lasts = 10 },
    [15265] = { on = "enemy", lasts = 10 },
    [15266] = { on = "enemy", lasts = 10 },
    [15267] = { on = "enemy", lasts = 10 },
    [15269] = { on = "enemy", lasts = 3 },
    [15270] = { on = "self" },
    [15271] = { on = "self", lasts = 15 },
    [15286] = { cd = 30, on = "enemy", lasts = 30 },
    [15326] = { on = "self" },
    [15407] = { on = "enemy", lasts = 3 },
    [15473] = { on = "self" },
    [15487] = { cd = 45, on = "enemy", lasts = 5 },
    [15629] = { cd = 8 },
    [15630] = { cd = 8 },
    [15631] = { cd = 8 },
    [15632] = { cd = 8 },
    [16164] = { on = "self" },
    [16166] = { cd = 180, on = "self", lasts = 15, charges = 1 },
    [16176] = { on = "self" },
    [16177] = { on = "friend", lasts = 15 },
    [16188] = { cd = 180, on = "self", charges = 1 },
    [16190] = { cd = 300, on = "self", auras = { 16191, 17355, 17360, 1325257 } },
    [16191] = { on = "self" },
    [16246] = { on = "self", lasts = 15, charges = 1 },
    [16256] = { on = "self" },
    [16355] = {},
    [16356] = {},
    [16387] = { on = "self", auras = { 8230, 8250, 10521, 15036 } },
    [16487] = { on = "self" },
    [16488] = { on = "self", lasts = 6 },
    [16511] = { on = "enemy", lasts = 15 },
    [16689] = { cd = 60, on = "self", lasts = 45, charges = 1 },
    [16697] = { cd = 5 },
    [16810] = { cd = 60, on = "self", lasts = 45, charges = 1 },
    [16811] = { cd = 60, on = "self", lasts = 45, charges = 1 },
    [16812] = { cd = 60, on = "self", lasts = 45, charges = 1 },
    [16813] = { cd = 60, on = "self", lasts = 45, charges = 1 },
    [16850] = { on = "self" },
    [16864] = { on = "self" },
    [16870] = { on = "self", lasts = 15, charges = 1 },
    [16880] = { on = "self" },
    [16886] = { on = "self", lasts = 3 },
    [16914] = { on = "self", lasts = 10 },
    [16922] = { on = "enemy", lasts = 3 },
    [17007] = { on = "self" },
    [17116] = { cd = 180, on = "self", charges = 1 },
    [17253] = { cd = 10, noaura = true },
    [17255] = { cd = 10, noaura = true },
    [17256] = { cd = 10, noaura = true },
    [17257] = { cd = 10, noaura = true },
    [17258] = { cd = 10, noaura = true },
    [17259] = { cd = 10, noaura = true },
    [17260] = { cd = 10, noaura = true },
    [17261] = { cd = 10, noaura = true },
    [17311] = { on = "enemy", lasts = 3 },
    [17312] = { on = "enemy", lasts = 3 },
    [17313] = { on = "enemy", lasts = 3 },
    [17314] = { on = "enemy", lasts = 3 },
    [17329] = { cd = 60, on = "self", lasts = 45, charges = 1 },
    [17354] = { cd = 300, on = "self", auras = { 16191, 17355, 17360, 1325257 } },
    [17355] = { on = "self" },
    [17359] = { cd = 300, on = "self", auras = { 16191, 17355, 17360, 1325257 } },
    [17360] = { on = "self" },
    [17364] = { cd = 6, on = "enemy", lasts = 12, charges = 1 },
    [17401] = { on = "self", lasts = 10 },
    [17402] = { on = "self", lasts = 10 },
    [17735] = { cd = 120 },
    [17750] = { cd = 120 },
    [17751] = { cd = 120 },
    [17752] = { cd = 120 },
    [17767] = { on = "self", lasts = 10 },
    [17793] = { on = "self" },
    [17794] = { on = "enemy", lasts = 12 },
    [17850] = { on = "self", lasts = 10 },
    [17851] = { on = "self", lasts = 10 },
    [17852] = { on = "self", lasts = 10 },
    [17853] = { on = "self", lasts = 10 },
    [17854] = { on = "self", lasts = 10 },
    [17877] = { cd = 15, on = "enemy", lasts = 8 },
    [17924] = { cd = 60, noaura = true },
    [17925] = { cd = 120, on = "enemy", lasts = 3 },
    [17926] = { cd = 120, on = "enemy", lasts = 3 },
    [17928] = { cd = 40, on = "enemy", lasts = 15 },
    [17941] = { on = "self", lasts = 10 },
    [17962] = { cd = 10, noaura = true },
    [18094] = { on = "self" },
    [18118] = { on = "enemy", lasts = 5 },
    [18119] = { on = "self" },
    [18137] = { on = "self", lasts = 600, charges = 3 },
    [18223] = { on = "enemy", lasts = 12 },
    [18265] = { on = "enemy", lasts = 30 },
    [18288] = { cd = 180, on = "self", lasts = 30, charges = 1 },
    [18425] = { on = "enemy", lasts = 2 },
    [18499] = { cd = 30, on = "self", lasts = 10 },
    [18540] = { cd = 3600 },
    [18562] = { cd = 15, noaura = true },
    [18647] = { on = "enemy", lasts = 30 },
    [18657] = { on = "enemy", lasts = 30 },
    [18658] = { on = "enemy", lasts = 40 },
    [18708] = { cd = 300, on = "self", lasts = 15, charges = 1 },
    [18788] = { on = "self", lasts = 7200, auras = { 18789, 18790, 18791, 18792 } },
    [18789] = { on = "self", lasts = 7200 },
    [18790] = { on = "self", lasts = 7200 },
    [18791] = { on = "self", lasts = 7200 },
    [18792] = { on = "self", lasts = 7200 },
    [18807] = { on = "enemy", lasts = 3 },
    [18809] = { on = "enemy", lasts = 12 },
    [18867] = { cd = 15, on = "enemy", lasts = 8 },
    [18868] = { cd = 15, on = "enemy", lasts = 8 },
    [18869] = { cd = 15, on = "enemy", lasts = 8 },
    [18870] = { cd = 15, on = "enemy", lasts = 8 },
    [18871] = { cd = 15, on = "enemy", lasts = 8 },
    [18879] = { on = "enemy", lasts = 30 },
    [18880] = { on = "enemy", lasts = 30 },
    [18881] = { on = "enemy", lasts = 30 },
    [18930] = { cd = 10, noaura = true },
    [18931] = { cd = 10, noaura = true },
    [18932] = { cd = 10, noaura = true },
    [19028] = { on = "self", auras = { 25228 } },
    [19184] = { on = "enemy" },
    [19185] = { on = "enemy", lasts = 5 },
    [19236] = { cd = 600, noaura = true },
    [19238] = { cd = 600, noaura = true },
    [19240] = { cd = 600, noaura = true },
    [19241] = { cd = 600, noaura = true },
    [19242] = { cd = 600, noaura = true },
    [19243] = { cd = 600, noaura = true },
    [19244] = { cd = 30, on = "enemy", lasts = 3, auras = { 24259 } },
    [19249] = { on = "enemy", lasts = 120 },
    [19251] = { on = "enemy", lasts = 120 },
    [19252] = { on = "enemy", lasts = 120 },
    [19253] = { on = "enemy", lasts = 120 },
    [19254] = { on = "enemy", lasts = 120 },
    [19261] = { on = "self", lasts = 600 },
    [19262] = { on = "self", lasts = 600 },
    [19263] = { cd = 300, on = "self", lasts = 10 },
    [19264] = { on = "self", lasts = 600 },
    [19265] = { on = "self", lasts = 600 },
    [19266] = { on = "self", lasts = 600 },
    [19271] = { cd = 180, on = "self", lasts = 15 },
    [19273] = { cd = 180, on = "self", lasts = 15 },
    [19274] = { cd = 180, on = "self", lasts = 15 },
    [19275] = { cd = 180, on = "self", lasts = 15 },
    [19276] = { cd = 24, on = "enemy", lasts = 24 },
    [19277] = { cd = 24, on = "enemy", lasts = 24 },
    [19278] = { cd = 24, on = "enemy", lasts = 24 },
    [19279] = { cd = 24, on = "enemy", lasts = 24 },
    [19280] = { cd = 24, on = "enemy", lasts = 24 },
    [19281] = { on = "enemy", lasts = 120 },
    [19282] = { on = "enemy", lasts = 120 },
    [19283] = { on = "enemy", lasts = 120 },
    [19284] = { on = "enemy", lasts = 120 },
    [19285] = { on = "enemy", lasts = 120 },
    [19296] = { cd = 30, on = "enemy", lasts = 6 },
    [19299] = { cd = 30, on = "enemy", lasts = 6 },
    [19302] = { cd = 30, on = "enemy", lasts = 6 },
    [19303] = { cd = 30, on = "enemy", lasts = 6 },
    [19304] = { cd = 30, on = "enemy", lasts = 6 },
    [19305] = { cd = 30, on = "enemy", lasts = 6 },
    [19306] = { cd = 5, on = "enemy", lasts = 5 },
    [19308] = { on = "self", lasts = 600, charges = 3 },
    [19309] = { on = "self", lasts = 600, charges = 3 },
    [19310] = { on = "self", lasts = 600, charges = 3 },
    [19311] = { on = "self", lasts = 600, charges = 3 },
    [19312] = { on = "self", lasts = 600, charges = 3 },
    [19407] = { on = "self" },
    [19434] = { cd = 6, noaura = true },
    [19438] = { on = "pet", lasts = 30 },
    [19440] = { on = "pet", lasts = 30 },
    [19441] = { on = "pet", lasts = 30 },
    [19442] = { on = "pet", lasts = 30 },
    [19443] = { on = "pet", lasts = 30 },
    [19478] = { on = "self", lasts = 60 },
    [19503] = { cd = 30, on = "enemy", lasts = 4 },
    [19505] = { cd = 8, noaura = true },
    [19506] = { on = "self", lasts = 1800 },
    [19552] = { on = "self" },
    [19574] = { cd = 120, on = "pet", lasts = 18 },
    [19577] = { cd = 60, on = "pet", lasts = 15, charges = 1 },
    [19621] = { on = "self" },
    [19647] = { cd = 30, on = "enemy", lasts = 3, auras = { 24259 } },
    [19655] = { on = "self", lasts = 60 },
    [19656] = { on = "self", lasts = 60 },
    [19660] = { on = "self", lasts = 60 },
    [19675] = { on = "enemy", lasts = 4 },
    [19731] = { cd = 8, noaura = true },
    [19734] = { cd = 8, noaura = true },
    [19736] = { cd = 8, noaura = true },
    [19740] = { on = "friend", lasts = 3600 },
    [19742] = { on = "friend", lasts = 3600 },
    [19746] = { on = "self" },
    [19752] = { cd = 3600, on = "friend", lasts = 180, auras = { 19753 } },
    [19801] = { cd = 20, noaura = true },
    [19834] = { on = "friend", lasts = 3600 },
    [19835] = { on = "friend", lasts = 3600 },
    [19836] = { on = "friend", lasts = 3600 },
    [19837] = { on = "friend", lasts = 3600 },
    [19838] = { on = "friend", lasts = 3600 },
    [19850] = { on = "friend", lasts = 3600 },
    [19852] = { on = "friend", lasts = 3600 },
    [19853] = { on = "friend", lasts = 3600 },
    [19854] = { on = "friend", lasts = 3600 },
    [19876] = { on = "self" },
    [19888] = { on = "self" },
    [19891] = { on = "self" },
    [19895] = { on = "self" },
    [19896] = { on = "self" },
    [19897] = { on = "self" },
    [19898] = { on = "self" },
    [19899] = { on = "self" },
    [19900] = { on = "self" },
    [19977] = {},
    [19978] = {},
    [19979] = {},
    [20043] = { on = "self" },
    [20049] = { on = "self" },
    [20050] = { on = "self", lasts = 30, stacks = 5 },
    [20066] = { cd = 60, on = "enemy", lasts = 6 },
    [20116] = { cd = 8, on = "self", lasts = 8 },
    [20127] = { on = "self" },
    [20128] = { on = "self", lasts = 10, charges = 5 },
    [20154] = { on = "self", lasts = 30 },
    [20162] = { on = "self", lasts = 30 },
    [20163] = { on = "self", lasts = 30 },
    [20164] = { on = "self", lasts = 30 },
    [20165] = { on = "self", lasts = 30 },
    [20166] = { on = "self", lasts = 30 },
    [20177] = { on = "self" },
    [20184] = { on = "enemy", lasts = 10 },
    [20185] = { on = "enemy", lasts = 40 },
    [20186] = { on = "enemy", lasts = 40 },
    [20188] = { on = "enemy", lasts = 40 },
    [20190] = { on = "self" },
    [20216] = { cd = 120, on = "self", charges = 1 },
    [20217] = { on = "friend", lasts = 3600 },
    [20230] = { cd = 900, on = "self", lasts = 15, charges = 30 },
    [20252] = { cd = 30, on = "enemy", lasts = 3, auras = { 20253 } },
    [20271] = { cd = 10 },
    [20287] = { on = "self", lasts = 30 },
    [20288] = { on = "self", lasts = 30 },
    [20289] = { on = "self", lasts = 30 },
    [20290] = { on = "self", lasts = 30 },
    [20291] = { on = "self", lasts = 30 },
    [20292] = { on = "self", lasts = 30 },
    [20293] = { on = "self", lasts = 30 },
    [20300] = { on = "enemy", lasts = 40 },
    [20301] = { on = "enemy", lasts = 40 },
    [20302] = { on = "enemy", lasts = 40 },
    [20303] = { on = "enemy", lasts = 40 },
    [20305] = { on = "self", lasts = 30 },
    [20306] = { on = "self", lasts = 30 },
    [20307] = { on = "self", lasts = 30 },
    [20308] = { on = "self", lasts = 30 },
    [20344] = { on = "enemy", lasts = 40 },
    [20345] = { on = "enemy", lasts = 40 },
    [20346] = { on = "enemy", lasts = 40 },
    [20347] = { on = "self", lasts = 30 },
    [20348] = { on = "self", lasts = 30 },
    [20349] = { on = "self", lasts = 30 },
    [20354] = { on = "enemy", lasts = 40 },
    [20355] = { on = "enemy", lasts = 40 },
    [20356] = { on = "self", lasts = 30 },
    [20357] = { on = "self", lasts = 30 },
    [20375] = { on = "self", lasts = 30 },
    [20419] = { on = "self", lasts = 30 },
    [20421] = { on = "self", lasts = 30 },
    [20422] = { on = "self", lasts = 30 },
    [20423] = { on = "self", lasts = 30 },
    [20473] = { cd = 10 },
    [20484] = { cd = 1800 },
    [20511] = { on = "enemy", lasts = 8 },
    [20549] = { cd = 90, on = "enemy", lasts = 2 },
    [20554] = { cd = 180, on = "self", lasts = 15 },
    [20559] = { cd = 120, on = "enemy", lasts = 6 },
    [20560] = { cd = 120, on = "enemy", lasts = 6 },
    [20569] = { noaura = true },
    [20572] = { cd = 120, on = "self", lasts = 15 },
    [20577] = { cd = 120 },
    [20580] = { cd = 10, on = "self" },
    [20589] = { cd = 120, on = "self", lasts = 3 },
    [20594] = { cd = 180, on = "self", lasts = 8 },
    [20600] = { cd = 180, on = "self", lasts = 20 },
    [20608] = { cd = 3600, on = "self" },
    [20616] = { cd = 30, on = "enemy", lasts = 3, auras = { 20614 } },
    [20617] = { cd = 30, on = "enemy", lasts = 3, auras = { 20615 } },
    [20658] = { on = "self", lasts = 1, auras = { 26651 } },
    [20660] = { on = "self", lasts = 1, auras = { 26651 } },
    [20661] = { on = "self", lasts = 1, auras = { 26651 } },
    [20662] = { on = "self", lasts = 1, auras = { 26651 } },
    [20707] = { on = "friend", lasts = 1800 },
    [20711] = { on = "self" },
    [20729] = { on = "friend", lasts = 30 },
    [20736] = { cd = 8 },
    [20739] = { cd = 1800 },
    [20742] = { cd = 1800 },
    [20747] = { cd = 1800 },
    [20748] = { cd = 1800 },
    [20762] = { on = "friend", lasts = 1800 },
    [20763] = { on = "friend", lasts = 1800 },
    [20764] = { on = "friend", lasts = 1800 },
    [20765] = { on = "friend", lasts = 1800 },
    [20900] = { cd = 6, noaura = true },
    [20901] = { cd = 6, noaura = true },
    [20902] = { cd = 6, noaura = true },
    [20903] = { cd = 6, noaura = true },
    [20904] = { cd = 6, noaura = true },
    [20905] = { on = "self", lasts = 1800 },
    [20906] = { on = "self", lasts = 1800 },
    [20909] = { cd = 5, on = "enemy", lasts = 5 },
    [20910] = { cd = 5, on = "enemy", lasts = 5 },
    [20915] = { on = "self", lasts = 30 },
    [20918] = { on = "self", lasts = 30 },
    [20919] = { on = "self", lasts = 30 },
    [20920] = { on = "self", lasts = 30 },
    [20922] = { cd = 8, on = "self", lasts = 8 },
    [20923] = { cd = 8, on = "self", lasts = 8 },
    [20924] = { cd = 8, on = "self", lasts = 8 },
    [20925] = { cd = 10, on = "self", lasts = 10, charges = 4 },
    [20927] = { cd = 10, on = "self", lasts = 10, charges = 4 },
    [20928] = { cd = 10, on = "self", lasts = 10, charges = 4 },
    [20929] = { cd = 10 },
    [20930] = { cd = 10 },
    [21082] = { on = "self", lasts = 30 },
    [21084] = { on = "self", lasts = 30 },
    [21183] = { on = "enemy", lasts = 40 },
    [21551] = { cd = 6, on = "enemy", lasts = 10 },
    [21552] = { cd = 6, on = "enemy", lasts = 10 },
    [21553] = { cd = 6, on = "enemy", lasts = 10 },
    [21562] = { on = "self", lasts = 3600 },
    [21564] = { on = "self", lasts = 3600 },
    [21849] = { on = "self", lasts = 3600 },
    [21850] = { on = "self", lasts = 3600 },
    [22782] = { on = "self", lasts = 1800 },
    [22783] = { on = "self", lasts = 1800 },
    [22812] = { cd = 60, on = "self", lasts = 15 },
    [22842] = { cd = 180, on = "self", lasts = 10 },
    [22845] = { on = "self", lasts = 10, auras = { 22842 } },
    [22959] = { on = "enemy", lasts = 30, stacks = 5 },
    [23028] = { on = "self", lasts = 3600 },
    [23099] = { cd = 30, on = "self", lasts = 15 },
    [23109] = { cd = 30, on = "self", lasts = 15 },
    [23110] = { cd = 30, on = "self", lasts = 15 },
    [23145] = { cd = 30, on = "self", lasts = 15 },
    [23147] = { cd = 30, on = "self", lasts = 15 },
    [23148] = { cd = 30, on = "self", lasts = 15 },
    [23694] = { on = "enemy", lasts = 5 },
    [23881] = { cd = 6, on = "self", lasts = 10 },
    [23892] = { cd = 6, on = "self", lasts = 10 },
    [23893] = { cd = 6, on = "self", lasts = 10 },
    [23894] = { cd = 6, on = "self", lasts = 10 },
    [23922] = { cd = 6, noaura = true },
    [23923] = { cd = 6, noaura = true },
    [23924] = { cd = 6, noaura = true },
    [23925] = { cd = 6, noaura = true },
    [24118] = { on = "enemy", lasts = 21 },
    [24119] = { on = "enemy", lasts = 21 },
    [24120] = { on = "enemy", lasts = 21 },
    [24239] = { cd = 6, noaura = true },
    [24274] = { cd = 6, noaura = true },
    [24275] = { cd = 6, noaura = true },
    [24423] = { cd = 10, on = "enemy", lasts = 30 },
    [24450] = { cd = 10, on = "self", charges = 1 },
    [24452] = { cd = 10, on = "self", charges = 1 },
    [24453] = { cd = 10, on = "self", charges = 1 },
    [24577] = { cd = 10, on = "enemy", lasts = 30 },
    [24578] = { cd = 10, on = "enemy", lasts = 30 },
    [24579] = { cd = 10, on = "enemy", lasts = 30 },
    [24583] = { cd = 4, on = "enemy", lasts = 10, stacks = 5 },
    [24586] = { cd = 4, on = "enemy", lasts = 10, stacks = 5 },
    [24587] = { cd = 4, on = "enemy", lasts = 10, stacks = 5 },
    [24597] = { cd = 30, on = "self", lasts = 60 },
    [24603] = { cd = 30, on = "self", lasts = 60 },
    [24604] = { cd = 30, on = "self", lasts = 60 },
    [24605] = { cd = 30, on = "self", lasts = 60 },
    [24640] = { cd = 4, on = "enemy", lasts = 10, stacks = 5 },
    [24858] = { on = "self" },
    [24907] = { on = "self" },
    [24932] = { on = "self" },
    [24974] = { on = "enemy", lasts = 12 },
    [24975] = { on = "enemy", lasts = 12 },
    [24976] = { on = "enemy", lasts = 12 },
    [24977] = { on = "enemy", lasts = 12 },
    [25228] = { on = "self" },
    [25286] = { noaura = true },
    [25288] = { cd = 5, noaura = true },
    [25289] = { on = "self", lasts = 180 },
    [25290] = { on = "friend", lasts = 3600 },
    [25291] = { on = "friend", lasts = 3600 },
    [25295] = { on = "enemy", lasts = 15 },
    [25299] = { on = "friend", lasts = 12 },
    [25302] = { cd = 10 },
    [25304] = { on = "enemy", lasts = 9 },
    [25306] = { on = "enemy", lasts = 8 },
    [25309] = { on = "enemy", lasts = 15 },
    [25311] = { on = "enemy", lasts = 18 },
    [25315] = { on = "friend", lasts = 15 },
    [25345] = { on = "self", lasts = 5 },
    [25347] = {},
    [25359] = { on = "self", auras = { 8836, 10626, 25360 } },
    [25360] = { on = "self" },
    [25361] = { on = "self", auras = { 8076, 8162, 8163, 10441, 25362 } },
    [25362] = { on = "self" },
    [25780] = { on = "self", lasts = 1800 },
    [25782] = { on = "any", lasts = 3600 },
    [25890] = {},
    [25894] = { on = "any", lasts = 3600 },
    [25895] = {},
    [25898] = { on = "any", lasts = 3600 },
    [25916] = { on = "any", lasts = 3600 },
    [25918] = { on = "any", lasts = 3600 },
    [26064] = { cd = 180, on = "self", lasts = 12 },
    [26090] = { cd = 60, noaura = true },
    [26177] = { cd = 25, on = "self", lasts = 4, charges = 1 },
    [26178] = { cd = 25, on = "self", lasts = 4, charges = 1 },
    [26179] = { cd = 25, on = "self", lasts = 4, charges = 1 },
    [26187] = { cd = 60, noaura = true },
    [26188] = { cd = 60, noaura = true },
    [26201] = { cd = 25, on = "self", lasts = 4, charges = 1 },
    [26573] = { cd = 8, on = "self", lasts = 8 },
    [27681] = { on = "self", lasts = 3600 },
    [27683] = { on = "self", lasts = 1200 },
    [27685] = { cd = 25, on = "self", lasts = 4, charges = 1 },
    [27811] = { on = "self" },
    [27813] = { on = "self", lasts = 6 },
    [27827] = { on = "self", lasts = 15 },
    [27828] = { on = "self", lasts = 6 },
    [27841] = { on = "friend", lasts = 3600 },
    [28271] = { on = "enemy", lasts = 50 },
    [28272] = { on = "enemy", lasts = 50 },
    [28609] = { cd = 30, on = "self", lasts = 30 },
    [28610] = { cd = 30, on = "self", lasts = 30 },
    [28682] = { on = "self", stacks = 10 },
    [29131] = { on = "self", lasts = 10 },
    [29166] = { cd = 360, on = "friend", lasts = 20 },
    [29228] = { cd = 6, on = "enemy", lasts = 12 },
    [30160] = { on = "self" },
    [30165] = { on = "self", lasts = 10 },
    [52127] = {},
    [400573] = { on = "self", lasts = 18, stacks = 4 },
    [400574] = { on = "self", lasts = 18, stacks = 4, auras = { 400573 } },
    [400588] = { on = "self" },
    [400589] = { on = "self", lasts = 15 },
    [400624] = { on = "self" },
    [400625] = { on = "self", lasts = 20, stacks = 3, charges = 1 },
    [400640] = { cd = 8 },
    [400647] = { on = "self" },
    [400670] = { on = "self", lasts = 15, stacks = 2 },
    [401502] = { on = "enemy", lasts = 9 },
    [401859] = { cd = 10, on = "friend", lasts = 30, stacks = 5, auras = { 401877, 1240848, 1240849 } },
    [401877] = { on = "friend", lasts = 30, stacks = 5 },
    [402174] = { cd = 12 },
    [402927] = { cd = 30 },
    [402975] = { on = "self", lasts = 20 },
    [407995] = { cd = 6, noaura = true },
    [408120] = { cd = 6, on = "any", lasts = 7 },
    [408248] = { on = "self" },
    [408255] = { on = "self", lasts = 15, stacks = 4, charges = 1 },
    [408341] = { cd = 10 },
    [408342] = { cd = 10 },
    [408343] = { cd = 10 },
    [408344] = { cd = 10 },
    [408345] = { cd = 10 },
    [408423] = { noaura = true },
    [408424] = { noaura = true },
    [408426] = { noaura = true },
    [408427] = { noaura = true },
    [408428] = { noaura = true },
    [408490] = { cd = 10 },
    [408510] = { on = "self", lasts = 600, charges = 3 },
    [408521] = { cd = 12, on = "friend", lasts = 15 },
    [410156] = { on = "enemy", lasts = 12, charges = 1, auras = { 17364 } },
    [412538] = { on = "enemy", lasts = 4 },
    [412609] = { on = "enemy", lasts = 12 },
    [414644] = { on = "enemy", lasts = 15, stacks = 5 },
    [414647] = { on = "enemy", lasts = 15, stacks = 5, auras = { 414644, 1235826, 1235827 } },
    [414923] = { on = "enemy", lasts = 3 },
    [415405] = { on = "self" },
    [415407] = { on = "self", lasts = 20, charges = 1 },
    [417141] = { cd = 180, on = "self", lasts = 15 },
    [425336] = { cd = 180, on = "self", lasts = 25 },
    [426065] = { on = "self" },
    [426311] = { on = "self", lasts = 20 },
    [431622] = { on = "self" },
    [431624] = { on = "friend", lasts = 12 },
    [437009] = { cd = 30 },
    [437032] = { on = "self" },
    [437063] = { on = "self", lasts = 15, charges = 1 },
    [440667] = { on = "enemy", lasts = 30 },
    [440668] = { on = "self", lasts = 30 },
    [440870] = { on = "self" },
    [440892] = { on = "enemy", lasts = 300 },
    [1221404] = { cd = 30, on = "any", lasts = 30 },
    [1222988] = { on = "self" },
    [1223031] = { on = "self" },
    [1223987] = { on = "self" },
    [1225228] = { on = "enemy", lasts = 300 },
    [1235826] = { on = "enemy", lasts = 15, stacks = 5 },
    [1235827] = { on = "enemy", lasts = 15, stacks = 5 },
    [1237312] = { on = "enemy", lasts = 9 },
    [1237313] = { on = "enemy", lasts = 9 },
    [1238069] = { cd = 6, noaura = true },
    [1238070] = { cd = 6, noaura = true },
    [1238073] = { cd = 6, noaura = true },
    [1238122] = { cd = 15, on = "enemy", lasts = 4, auras = { 19675, 414923 } },
    [1238214] = { cd = 6, on = "any", lasts = 7 },
    [1238215] = { cd = 6, on = "any", lasts = 7 },
    [1238289] = { on = "enemy", lasts = 5 },
    [1238299] = { cd = 10 },
    [1238300] = { cd = 10 },
    [1238640] = { on = "self" },
    [1239242] = { cd = 12, on = "friend", lasts = 15 },
    [1239243] = { cd = 12, on = "friend", lasts = 15 },
    [1239570] = { cd = 10, on = "self", lasts = 10, charges = 4 },
    [1239696] = { noaura = true },
    [1239697] = { noaura = true },
    [1239699] = { noaura = true },
    [1239700] = { noaura = true },
    [1240044] = { cd = 8 },
    [1240045] = { cd = 8 },
    [1240046] = { cd = 8 },
    [1240047] = { cd = 8 },
    [1240193] = { cd = 15, noaura = true },
    [1240720] = { cd = 12 },
    [1240721] = { cd = 12 },
    [1240826] = { cd = 10, on = "friend", lasts = 30, stacks = 5, auras = { 401877, 1240848, 1240849 } },
    [1240827] = { cd = 10, on = "friend", lasts = 30, stacks = 5, auras = { 401877, 1240848, 1240849 } },
    [1240848] = { on = "friend", lasts = 30, stacks = 5 },
    [1240849] = { on = "friend", lasts = 30, stacks = 5 },
    [1242512] = { on = "self", lasts = 15 },
    [1242634] = { cd = 5, on = "enemy", lasts = 5 },
    [1242853] = { on = "self", lasts = 10 },
    [1259416] = { cd = 90, on = "self", lasts = 10 },
    [1259686] = { cd = 120, on = "self", lasts = 30, auras = { 1259688, 1270893 } },
    [1259688] = { on = "self", lasts = 30 },
    [1259691] = { on = "self", lasts = 3600 },
    [1259705] = { cd = 120, on = "self", lasts = 3600, auras = { 1259691, 1270842 } },
    [1259718] = { cd = 180 },
    [1259799] = { cd = 180, on = "self", lasts = 15 },
    [1259812] = { cd = 120, on = "self", lasts = 8 },
    [1259813] = { cd = 120, on = "self", lasts = 8 },
    [1259817] = { cd = 120, on = "self", lasts = 8 },
    [1259821] = { cd = 120, on = "self", lasts = 8 },
    [1259823] = { cd = 120, on = "self", lasts = 8 },
    [1259918] = { on = "self" },
    [1260270] = { cd = 180, on = "self", lasts = 6 },
    [1264455] = { cd = 60, noaura = true },
    [1264478] = { cd = 60, on = "enemy", lasts = 20 },
    [1264479] = { cd = 60, on = "enemy", lasts = 20 },
    [1264480] = { cd = 60, on = "enemy", lasts = 20 },
    [1264481] = { cd = 60, on = "enemy", lasts = 20 },
    [1264482] = { cd = 60, on = "enemy", lasts = 20 },
    [1264494] = { cd = 5, noaura = true },
    [1264497] = { cd = 5, noaura = true },
    [1264498] = { cd = 5, noaura = true },
    [1264501] = { cd = 5, noaura = true },
    [1264502] = { cd = 5, noaura = true },
    [1264735] = { cd = 30, on = "enemy", lasts = 9 },
    [1264736] = { cd = 30, on = "enemy", lasts = 9 },
    [1264739] = { cd = 30, on = "enemy", lasts = 9 },
    [1264741] = { cd = 30, on = "enemy", lasts = 9 },
    [1264742] = { cd = 30, on = "enemy", lasts = 9 },
    [1264758] = { cd = 15, on = "enemy", lasts = 6 },
    [1264927] = { cd = 15, on = "enemy", lasts = 6 },
    [1264929] = { cd = 15, on = "enemy", lasts = 6 },
    [1264930] = { cd = 15, on = "enemy", lasts = 6 },
    [1264933] = { cd = 15, on = "enemy", lasts = 6 },
    [1265038] = { cd = 30, on = "enemy", lasts = 9 },
    [1265039] = { cd = 30, on = "enemy", lasts = 9 },
    [1265040] = { cd = 30, on = "enemy", lasts = 9 },
    [1265041] = { cd = 30, on = "enemy", lasts = 9 },
    [1265042] = { cd = 30, on = "enemy", lasts = 9 },
    [1265054] = { cd = 90, on = "enemy", lasts = 3 },
    [1265055] = { cd = 90, on = "enemy", lasts = 3 },
    [1265056] = { cd = 90, on = "enemy", lasts = 3 },
    [1265057] = { cd = 90, on = "enemy", lasts = 3 },
    [1265058] = { cd = 90, on = "enemy", lasts = 3 },
    [1265065] = { cd = 60, on = "enemy", lasts = 18 },
    [1265066] = { cd = 60, on = "enemy", lasts = 18 },
    [1265067] = { cd = 60, on = "enemy", lasts = 18 },
    [1265068] = { cd = 60, on = "enemy", lasts = 18 },
    [1265069] = { cd = 60, on = "enemy", lasts = 18 },
    [1265843] = { cd = 40, on = "enemy", lasts = 4 },
    [1265878] = { cd = 40, on = "enemy", lasts = 4 },
    [1265880] = { cd = 40, on = "enemy", lasts = 4 },
    [1265881] = { cd = 40, on = "enemy", lasts = 4 },
    [1265883] = { cd = 40, on = "enemy", lasts = 4 },
    [1265899] = { on = "enemy", lasts = 30 },
    [1265901] = { on = "enemy", lasts = 30 },
    [1265902] = { on = "enemy", lasts = 30 },
    [1265903] = { on = "enemy", lasts = 30 },
    [1265904] = { on = "enemy", lasts = 30 },
    [1270842] = { on = "self", lasts = 15 },
    [1270893] = { on = "self", lasts = 3600 },
    [1277324] = { cd = 600, on = "self", lasts = 15 },
    [1277325] = { cd = 600, on = "self", lasts = 15 },
    [1277326] = { cd = 600, on = "self", lasts = 15 },
    [1277327] = { cd = 600, on = "self", lasts = 15 },
    [1277328] = { cd = 600, on = "self", lasts = 15 },
    [1277331] = { cd = 120, on = "enemy", lasts = 2 },
    [1277332] = { cd = 120, on = "enemy", lasts = 2 },
    [1277333] = { cd = 120, on = "enemy", lasts = 2 },
    [1277334] = { cd = 120, on = "enemy", lasts = 2 },
    [1277335] = { cd = 120, on = "enemy", lasts = 2 },
    [1277370] = { cd = 600 },
    [1277371] = { cd = 600 },
    [1277372] = { cd = 600 },
    [1277374] = { cd = 600 },
    [1277376] = { cd = 600 },
    [1277377] = { cd = 600 },
    [1277378] = { cd = 600 },
    [1277455] = { cd = 120, on = "enemy", lasts = 3 },
    [1277462] = { cd = 600, on = "friend", lasts = 30 },
    [1277634] = { cd = 600, on = "friend", lasts = 30 },
    [1277638] = { cd = 600, on = "friend", lasts = 30 },
    [1277639] = { cd = 600, on = "friend", lasts = 30 },
    [1277640] = { cd = 600, on = "friend", lasts = 30 },
    [1280345] = { on = "self", lasts = 8, auras = { 20116, 20922, 20923, 20924, 26573 } },
    [1280346] = { on = "self", lasts = 8, auras = { 20116, 20922, 20923, 20924, 26573 } },
    [1280347] = { on = "self", lasts = 8, auras = { 20116, 20922, 20923, 20924, 26573 } },
    [1280348] = { on = "self", lasts = 8, auras = { 20116, 20922, 20923, 20924, 26573 } },
    [1280349] = { on = "self", lasts = 8, auras = { 20116, 20922, 20923, 20924, 26573 } },
    [1284536] = { on = "self", lasts = 10, charges = 1 },
    [1289681] = { on = "self", lasts = 5, charges = 1 },
    [1289682] = { on = "self" },
    [1293241] = { cd = 6 },
    [1293525] = { cd = 6 },
    [1293526] = { cd = 6 },
    [1293527] = { cd = 6 },
    [1293816] = { on = "self", lasts = 20 },
    [1293817] = { cd = 10, noaura = true },
    [1293818] = { cd = 10, noaura = true },
    [1299026] = { cd = 180, on = "self", lasts = 8 },
    [1299332] = { on = "enemy", lasts = 21 },
    [1299346] = { on = "self", lasts = 1800 },
    [1299348] = { on = "self", lasts = 1800 },
    [1299445] = { on = "self" },
    [1299446] = { on = "self" },
    [1299447] = { on = "self" },
    [1299448] = { on = "self", lasts = 12 },
    [1309595] = { cd = 18 },
    [1309633] = { cd = 18 },
    [1309635] = { cd = 18 },
    [1309636] = { cd = 18 },
    [1310222] = { cd = 20 },
    [1310532] = { on = "self" },
    [1310533] = { on = "self" },
    [1310536] = { on = "enemy", lasts = 21 },
    [1310612] = { cd = 180, on = "self", lasts = 12 },
    [1310687] = { cd = 15, on = "self", lasts = 10, charges = 3 },
    [1310703] = { on = "self", lasts = 6 },
    [1310726] = { on = "self", lasts = 10, charges = 1 },
    [1310735] = { on = "self" },
    [1310785] = { cd = 15, on = "self", lasts = 10, charges = 3 },
    [1310786] = { cd = 15, on = "self", lasts = 10, charges = 3 },
    [1310897] = { cd = 180, on = "self", lasts = 6 },
    [1310909] = { on = "friend", lasts = 30, charges = 1 },
    [1310910] = { on = "enemy", lasts = 30, charges = 1 },
    [1310911] = { cd = 6 },
    [1310994] = { cd = 60 },
    [1311015] = { cd = 300, on = "self", lasts = 8 },
    [1311590] = { cd = 6 },
    [1311593] = { on = "friend", lasts = 30, charges = 1 },
    [1311594] = { on = "enemy", lasts = 30, charges = 1 },
    [1311595] = { cd = 6 },
    [1311597] = { on = "friend", lasts = 30, charges = 1 },
    [1311599] = { on = "enemy", lasts = 30, charges = 1 },
    [1311606] = { cd = 10 },
    [1311649] = { on = "self", lasts = 30 },
    [1311656] = { on = "self", lasts = 30 },
    [1311676] = { on = "enemy", lasts = 300 },
    [1311677] = { on = "enemy", lasts = 300 },
    [1311680] = { on = "enemy", lasts = 300 },
    [1311701] = { on = "self", lasts = 15, stacks = 3 },
    [1311703] = { on = "self", lasts = 15, stacks = 3 },
    [1311704] = { on = "self", lasts = 15, stacks = 3 },
    [1311705] = { on = "self", lasts = 15, stacks = 3 },
    [1312002] = { cd = 8 },
    [1316697] = { on = "enemy", lasts = 6 },
    [1316709] = { cd = 10, on = "enemy", lasts = 6 },
    [1316995] = { cd = 12 },
    [1317257] = { cd = 8, on = "self", lasts = 3 },
    [1318827] = { cd = 120 },
    [1319289] = { on = "self", auras = { 768, 783, 1066, 5487, 9634, 24858 } },
    [1319507] = { on = "self", auras = { 71, 2457, 2458 } },
    [1319652] = { on = "enemy", lasts = 120, auras = { 702, 704, 1108, 1714, 6205, 7646, 7658, 7659, 11707, 11708, 11717, 11719, 18223, 440892, 1311676, 1311677, 1311680 } },
    [1320379] = { on = "self", lasts = 50 },
    [1322605] = { cd = 8, noaura = true },
    [1323522] = { on = "self", lasts = 30, auras = { 20162, 20163, 20164, 20165, 20166, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 20305, 20306, 20307, 20308, 20347, 20348, 20349, 20356, 20357, 20375, 20419, 20421, 20422, 20423, 20915, 20918, 20919, 20920, 21082, 21084, 1311649, 1311656 } },
    [1324056] = { on = "self", auras = { 5118, 13159, 13161, 13163, 13165, 14318, 14319, 14320, 14321, 14322, 20043, 20190, 1299445, 1299446, 1299447 } },
    [1324187] = { on = "self", lasts = 40 },
    [1324188] = { on = "self", lasts = 30 },
    [1324189] = { on = "self", lasts = 20 },
    [1324401] = { on = "self", lasts = 4 },
    [1324415] = { on = "self", lasts = 30 },
    [1324420] = { on = "self", lasts = 40 },
    [1324422] = { on = "self", lasts = 50 },
    [1324427] = { on = "self", lasts = 5 },
    [1324448] = { on = "self", lasts = 10 },
    [1324451] = { on = "self", lasts = 15 },
    [1324453] = { on = "self", lasts = 20 },
    [1324459] = { on = "self", lasts = 3 },
    [1324462] = { on = "self", lasts = 20 },
    [1324463] = { on = "self", lasts = 30 },
    [1324468] = { on = "self", lasts = 300 },
    [1324473] = { on = "self", lasts = 300 },
    [1324474] = { on = "self" },
    [1324475] = { on = "self", lasts = 1 },
    [1324477] = { on = "self", lasts = 10 },
    [1324481] = { cd = 10, on = "self", lasts = 4 },
    [1324482] = { on = "self", lasts = 25 },
    [1324483] = { on = "self", lasts = 35 },
    [1324484] = { on = "self", lasts = 45 },
    [1324485] = { on = "self", lasts = 2 },
    [1324487] = { on = "self", lasts = 2 },
    [1324488] = { on = "self", lasts = 3 },
    [1324490] = { on = "self", lasts = 4 },
    [1324494] = { on = "self", lasts = 3 },
    [1324499] = { on = "self", lasts = 4 },
    [1324500] = { cd = 30, on = "self", lasts = 10 },
    [1324501] = { cd = 30, on = "self", lasts = 15 },
    [1324502] = { cd = 30, on = "self", lasts = 20 },
    [1324506] = { cd = 30, on = "self", lasts = 10 },
    [1324507] = { cd = 30, on = "self", lasts = 15 },
    [1324510] = { cd = 30, on = "self", lasts = 20 },
    [1324511] = { on = "self", lasts = 3 },
    [1324513] = { on = "self", lasts = 3 },
    [1324515] = { on = "self", lasts = 4 },
    [1324516] = { on = "self", lasts = 5 },
    [1324517] = { on = "self", lasts = 6 },
    [1324538] = { on = "self", lasts = 6 },
    [1324543] = { on = "self", lasts = 10 },
    [1324545] = { on = "self", lasts = 15 },
    [1324546] = { on = "self", lasts = 20 },
    [1324551] = { on = "self", lasts = 3 },
    [1324556] = { on = "self", lasts = 5 },
    [1324558] = { on = "self", lasts = 10 },
    [1325256] = { cd = 300, on = "self", auras = { 16191, 17355, 17360, 1325257 } },
    [1325257] = { on = "self" },
    [1325756] = { cd = 10, on = "enemy", lasts = 6 },
    [1325757] = { cd = 10, on = "enemy", lasts = 6 },
    [1325758] = { cd = 10, on = "enemy", lasts = 6 },
    [1326053] = { on = "enemy", lasts = 9 },
    [1326054] = { on = "enemy", lasts = 9 },
    [1326055] = { on = "enemy", lasts = 9 },
    [1326057] = { cd = 120 },
    [1326079] = { cd = 6 },
    [1326080] = { cd = 6 },
    [1326081] = { cd = 6 },
    [1326082] = { cd = 6 },
    [1326084] = { on = "self", stacks = 4, charges = 1 },
    [1328198] = { on = "self", lasts = 15, stacks = 3 },
    [1328206] = { on = "self", lasts = 15, stacks = 3 },
    [1328548] = { on = "friend", lasts = 300 },
    [1328616] = { on = "enemy", lasts = 15, stacks = 5 },
    [1328617] = { on = "enemy", lasts = 15, stacks = 5 },
    [1328825] = { on = "self" },
    [1328829] = { on = "self" },
    [1329283] = { cd = 10, noaura = true },
    [1329326] = { on = "self", lasts = 7, charges = 1 },
    [1329549] = { cd = 10, noaura = true },
    [1329553] = { on = "self", lasts = 2 },
    [1329555] = { cd = 15, on = "self", lasts = 8, charges = 4 },
}
-- FACTS END

ns.CdmSpells = S
