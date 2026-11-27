-- The world the missing-buffs tests share (tests/test_buffs_reminder*.lua): a
-- group, the client's names for every buff the row looks for, the spells you
-- know, and the bag and gear reads.
local stub = require("stub")

local RW = {}

-- The English names the client gives each id (only the first id of a list
-- needs one; the rest share it).
RW.NAMES = {
    fortitude = { "Power Word: Fortitude", "Prayer of Fortitude" },
    wild = { "Mark of the Wild", "Gift of the Wild" },
    intellect = { "Arcane Intellect", "Arcane Brilliance" },
    spirit = { "Divine Spirit", "Prayer of Spirit" },
    shadow = { "Shadow Protection", "Prayer of Shadow Protection" },
    shout = { "Battle Shout" },
    might = { "Blessing of Might", "Greater Blessing of Might" },
    wisdom = { "Blessing of Wisdom", "Greater Blessing of Wisdom" },
    kings = { "Blessing of Kings", "Greater Blessing of Kings" },
    salvation = { "Blessing of Salvation", "Greater Blessing of Salvation" },
    light = { "Blessing of Light", "Greater Blessing of Light" },
    sanctuary = { "Blessing of Sanctuary", "Greater Blessing of Sanctuary" },
}
RW.CLASS_NAMES = {
    thorns = { "Thorns" },
    aspect = { "Aspect of the Viper", "Aspect of the Dragonhawk", "Aspect of the Pack", "Aspect of the Cheetah",
               "Aspect of the Monkey", "Aspect of the Beast", "Aspect of the Wild", "Aspect of the Hawk" },
    trueshot = { "Trueshot Aura" },
    blessing = { "Blessing of Wisdom", "Blessing of Kings", "Blessing of Might" },
    paladinaura = { "Fire Resistance Aura", "Frost Resistance Aura", "Shadow Resistance Aura", "Concentration Aura",
                    "Retribution Aura", "Devotion Aura" },
    rfury = { "Righteous Fury" },
    innerfire = { "Inner Fire" },
    shadowform = { "Shadowform" },
    shield = { "Lightning Shield", "Water Shield" },
    demonarmor = { "Demon Armor" },
}
RW.ARMOR_NAMES = { "Frost Armor", "Ice Armor", "Mage Armor" }
RW.TRACK_NAMES = { "Track Beasts", "Track Dragonkin", "Track Demons", "Track Elementals", "Track Giants",
                   "Track Undead", "Track Humanoids" }
RW.IMBUE_NAMES = { rockbiter = "Rockbiter Weapon", windfury = "Windfury Weapon",
                   flametongue = "Flametongue Weapon", frostbrand = "Frostbrand Weapon" }

function RW.Names(BL)
    local D = BL.ReminderData
    local function name(ids, n) for _, id in ipairs(ids) do stub.spells[id] = { name = n } end end
    for _, fam in ipairs(D.FAMILIES) do
        local n = RW.NAMES[fam.key]
        name(fam.single, n[1])
        if fam.group then name(fam.group, n[2] or n[1]) end
    end
    for _, list in pairs(D.CLASS_BUFFS) do
        for _, buff in ipairs(list) do
            for i, line in ipairs(buff.lines) do name(line, RW.CLASS_NAMES[buff.key][i] or buff.key) end
            for i, line in ipairs(buff.also or {}) do name(line, "Greater " .. RW.CLASS_NAMES[buff.key][i]) end
        end
    end
    for i, line in ipairs(D.MAGE_ARMORS) do name(line, RW.ARMOR_NAMES[i]) end
    for i, id in ipairs(D.TRACKING) do name({ id }, RW.TRACK_NAMES[i]) end
    for _, b in ipairs(D.WEAPON_BUFFS) do
        if b.spells then name(b.spells, RW.IMBUE_NAMES[b.key]) end
        if b.create then name(b.create, "Create " .. b.name) end
    end
    name({ D.WELL_FED }, "Well Fed")
    name({ D.CENSER.buff }, "Magical Awareness")
    name({ D.SLEEPING_BAG.sleeping }, "Sleeping")
    name({ D.CAMP }, "Camp Benefits")
    name({ D.SLEEPING_BAG.buff }, "Well Rested")
end

-- Logs in with these units in a party. opts.known = spell ids you know,
-- opts.bags = true installs the bag and gear reads, opts.before = more setup.
function RW.Login(units, opts)
    opts = opts or {}
    stub.Load({ buffs = true, before = function()
        _G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
        CreateFrame("Frame", "BuffFrame", UIParent)
        CreateFrame("Frame", "DebuffFrame", UIParent)
        for _, u in pairs(units) do if u.isPlayer == nil then u.isPlayer = true end end
        stub.units = units
        if opts.bags then stub.BagReads() end
        -- Your own aura of a spell id, as the client's: nothing while auras are
        -- secret, unless the game never hides it (RequiresNonSecretAura).
        local had = C_UnitAuras.GetPlayerAuraBySpellID
        C_UnitAuras.GetPlayerAuraBySpellID = function(spellID)
            if stub.AurasRestricted() and not stub.neverSecretAuras[spellID] then return nil end
            for _, a in ipairs(stub.auras.player and stub.auras.player.HELPFUL or {}) do
                if a.spellId == spellID then
                    local out = {}
                    for k, v in pairs(a) do out[k] = v end
                    return out
                end
            end
            return nil
        end
        stub.onReset = stub.onReset or {}
        stub.onReset[#stub.onReset + 1] = function() C_UnitAuras.GetPlayerAuraBySpellID = had end
        if opts.before then opts.before() end
    end })
    for id in pairs(stub.knownSpells) do stub.knownSpells[id] = nil end
    -- Auras one test made never secret don't carry into the next.
    stub.neverSecretAuras = {}
    for _, id in ipairs(opts.known or {}) do stub.knownSpells[id] = true end
    RW.Names(stub.buffs)
    -- A normal dungeon unless the test says where: raid buffs are left out of
    -- the open world by default.
    if opts.where ~= "world" then
        stub.SetInstance(opts.where or "party")
        stub.difficulty = opts.difficulty or 1
    end
    -- "I'm missing others' buffs" is off by default; most tests want both views.
    if opts.mine ~= false then DaylightUI:Set("Buffs", "settings.reminder.raid.mine", true) end
    stub.SetGroup(units.party1 ~= nil or units.raid1 ~= nil, false)
    stub.RunTimers()
    return stub.buffs
end

function RW.Keys(list)
    local out = {}
    for _, e in ipairs(list or {}) do out[#out + 1] = e.key end
    return out
end

function RW.Entry(list, key)
    for _, e in ipairs(list or {}) do if e.key == key then return e end end
    return nil
end

function RW.Settle()
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 5) end
end

return RW
