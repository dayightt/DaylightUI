-- The fake character world for the character window tests: the game's window and
-- its pages (ToggleCharacter like the game's, minus the panel code), its slot
-- buttons, the inventory, the stats, the model, titles and equipment sets.
-- CW.world(spec) returns stub.Load's "before". Tests change CW.state and call the
-- game's functions. The other pages' game data (installReputation and friends)
-- sits above CW.world.
local stub = require("stub")

local CW = {}

CW.SLOT_IDS = { Ammo = 0, Head = 1, Neck = 2, Shoulder = 3, Shirt = 4, Chest = 5, Waist = 6, Legs = 7, Feet = 8,
    Wrist = 9, Hands = 10, Finger0 = 11, Finger1 = 12, Trinket0 = 13, Trinket1 = 14, Back = 15, MainHand = 16,
    SecondaryHand = 17, Ranged = 18, Tabard = 19 }
CW.PAGE_FRAMES = { "PaperDollFrame", "ReputationFrame", "SkillsFrame", "PVPRankFrame", "TokenFrame", "StatisticsFrame" }
CW.EQUIP = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger0", "Finger1", "Trinket0", "Trinket1" }
CW.WEAPONS = { "MainHand", "SecondaryHand", "Ranged" }

-- An item as the tests describe it. Fields: quality, level (false: not cached
-- yet), cur and max (durability), subType ("Arrow"), count.
-- An item's id is its own (fields.itemID) or one made from its name.
function CW.ItemId(x)
    if x.itemID then return x.itemID end
    local n = 0
    for i = 1, #x.name do n = (n * 31 + x.name:byte(i)) % 90000 end
    return 10000 + n
end

function CW.item(name, fields)
    local it = { name = name, quality = 3, level = 60 }
    for k, v in pairs(fields or {}) do it[k] = v end
    return it
end

-- A level 60 warrior's numbers. A test changes CW.state.stats.
function CW.defaultStats()
    return {
        stat = { { 120, 130, 10, 0 }, { 80, 80, 0, 0 }, { 150, 140, 0, -10 }, { 30, 30, 0, 0 }, { 40, 40, 0, 0 } },
        damage = { 120, 180 }, speed = { 2.6 }, ap = { 900, 50, 0 },
        ranged = { 2.9, 60, 90 }, rap = { 300, 0, 0 },
        hit = 3, hitRating = 1.5, crit = 20.04, rcrit = 8.5, expertise = 5,
        spell = 0, heal = 0, scrit = 1.2, shit = 0, regen = { 0, 0 },
        armor = { 3000, 3200, 3200, 200 }, defense = { 300, 12 }, dodge = 6.5, parry = 7.2, block = 4.1,
        shield = true, res = { [2] = 10, [3] = 20, [4] = 0, [5] = 5, [6] = 0 },   -- a number, or { base, effective }
        avg = 64.6,
        -- dual: two weapons (damage[3..4], speed[2], ohExpertise); haste and
        -- penetration as the client's calls return them (PaperDollFrame_SetHaste).
        dual = false, rangedWeapon = true, mhaste = 0, rhaste = { 0, 0 }, shaste = 0, armorPen = 0, spellPen = 0,
    }
end

local function S() return CW.state end
local function record(kind, value) table.insert(S().calls, { kind = kind, value = value }) end
CW.record = record

-- Every value one kind of call was made with, in order.
function CW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.value end end
    return out
end

-- In combat (CW.state.secret) the stats come back secret, as in game.
local function secret(v)
    if S().secret and type(v) == "number" then return stub.Secret(v) end
    return v
end
local function many(...)
    local n = select("#", ...)
    local out = { ... }
    for i = 1, n do out[i] = secret(out[i]) end
    return unpack(out, 1, n)
end

local function withId(b, id)
    b.__cwId = id
    b.GetID = function(self) return self.__cwId end   -- the stub's frames may not keep SetID
    b:EnableMouse(true)                                -- as the game's slot buttons are
    return b
end

local function buildFrames(spec)
    local cf = CreateFrame("Frame", "CharacterFrame", UIParent)
    cf:Hide()
    cf.activeSubframe = "PaperDollFrame"
    for _, name in ipairs(CW.PAGE_FRAMES) do
        if not (spec.missing and spec.missing[name]) then
            local p = CreateFrame("Frame", name, cf)
            p:Hide()
            if spec.hiddenPages and spec.hiddenPages[name] then p.hidden = true end
        end
    end
    _G.PaperDollFrame:Show()
    function cf:ShowSubFrame(name)
        self.activeSubframe = name
        for _, n in ipairs(CW.PAGE_FRAMES) do
            if _G[n] then _G[n]:SetShown(n == name) end
        end
    end
    -- The game's (Camelot/CharacterFrame.lua), with Show/Hide for the panel calls.
    _G.ToggleCharacter = function(tab, onlyShow)
        record("ToggleCharacter", { tab, onlyShow })
        local sub = _G[tab]
        if type(sub) ~= "table" or sub.hidden then return end
        if cf:IsShown() then
            if sub:IsShown() then
                if not onlyShow then cf:Hide() end
            else
                cf:ShowSubFrame(tab)
            end
        else
            cf:ShowSubFrame(tab)
            cf:Show()
        end
    end
    _G.SetUIPanelAttribute = function(f, key, value)
        if f == cf then S().panel[key] = value end
    end
    -- The slot buttons, in the game's two lists, inside the frame that holds them.
    local items = CreateFrame("Frame", "PaperDollItemsFrame", _G.PaperDollFrame)
    items:SetPoint("TOPLEFT", _G.PaperDollFrame, "TOPLEFT", 0, 0)
    items:SetSize(300, 400)
    items.flyoutSettings = { parent = _G.PaperDollFrame }
    items.EquipmentSlots, items.WeaponSlots = {}, {}
    for i, key in ipairs(CW.EQUIP) do
        local b = withId(CreateFrame("Button", "Character" .. key .. "Slot", items), CW.SLOT_IDS[key])
        b:SetPoint("TOPLEFT", items, "TOPLEFT", 0, -i * 10)
        items.EquipmentSlots[#items.EquipmentSlots + 1] = b
    end
    for i, key in ipairs(CW.WEAPONS) do
        local b = withId(CreateFrame("Button", "Character" .. key .. "Slot", items), CW.SLOT_IDS[key])
        b:SetPoint("BOTTOMLEFT", items, "BOTTOMLEFT", i * 10, 0)
        items.WeaponSlots[#items.WeaponSlots + 1] = b
    end
    -- The ammo button is in neither list: the game hangs it off the ranged one.
    local ammo = withId(CreateFrame("Button", "CharacterAmmoSlot", items), CW.SLOT_IDS.Ammo)
    ammo:SetPoint("LEFT", _G.CharacterRangedSlot, "RIGHT", 4, 0)
    local fly = CreateFrame("Frame", "EquipmentFlyoutFrame", UIParent)
    fly:Hide()
    _G.EquipmentFlyout_UpdateItems = function() record("flyout", true) end
    _G.PaperDollItemSlotButton_OnEnter = function(b) record("slotEnter", b:GetName()) end
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    tip.AddLine = function(_, text) record("tipLine", text) end
    tip.SetText = function(_, text) record("tipText", text) end
end

local function installInventory()
    _G.GetInventorySlotInfo = function(name)
        local key = string.gsub(name, "Slot$", "")
        local id = CW.SLOT_IDS[key]
        if not id then error("no slot " .. name) end
        return id, "empty:" .. key
    end
    local function it(id) return S().items[id] end
    -- The ammo slot (0) gives no link in this client, only the item's id. In game
    -- GetInventoryItemLink("player", 0) is nil while GetInventoryItemID gives 2512, count 313.
    _G.GetInventoryItemLink = function(_, id)
        local x = it(id)
        if id == CW.SLOT_IDS.Ammo then return nil end
        return x and ("|cffa335ee|Hitem:" .. CW.ItemId(x) .. ":" .. (x.enchantId or 0) .. "|h[" .. x.name .. "]|h|r") or nil
    end
    -- The game's tooltip data: an enchanted item's permanent enchant line
    -- (TooltipDataLineType ItemEnchantmentPermanent = 15), worded through the
    -- game's GlobalStrings ENCHANTED_TOOLTIP_LINE ("Enchanted: %s").
    _G.ENCHANTED_TOOLTIP_LINE = _G.ENCHANTED_TOOLTIP_LINE or "Enchanted: %s"
    _G.C_TooltipInfo = _G.C_TooltipInfo or {}
    C_TooltipInfo.GetInventoryItem = function(_, id)
        local x = it(id)
        if not x then return nil end
        CW.tipReads = (CW.tipReads or 0) + 1
        local lines = { { type = 0, leftText = x.name } }
        if x.enchant then
            lines[2] = { type = 15, leftText = string.format(ENCHANTED_TOOLTIP_LINE, x.enchant) }
        end
        return { lines = lines }
    end
    -- An empty ammo slot isn't nil in this client (in game it showed a gray box
    -- with "1"): it gives a count of 1 and something for its id. The game's own
    -- window goes by the icon (PaperDollItemSlotButton_Update: hasItem = texture ~= nil),
    -- so that's the rule. The id 0 is a stand-in.
    _G.GetInventoryItemID = function(_, id)
        local x = it(id)
        if not x and id == CW.SLOT_IDS.Ammo then return 0 end
        return x and CW.ItemId(x) or nil
    end
    _G.GetInventoryItemQuality = function(_, id) local x = it(id); return x and x.quality end
    _G.GetInventoryItemTexture = function(_, id) local x = it(id); return x and ("icon:" .. x.name) or nil end
    _G.GetInventoryItemDurability = function(id) local x = it(id); if x and x.max then return x.cur, x.max end end
    _G.GetInventoryItemCount = function(_, id)
        local x = it(id)
        if not x and id == CW.SLOT_IDS.Ammo then return 1 end
        return x and (x.count or 1) or 0
    end
    _G.UnitUsesAmmo = function() return S().usesAmmo == true end
    _G.GetAverageItemLevel = function() return S().stats.avg + 1, S().stats.avg, 0 end
    local function find(link)
        for _, x in pairs(S().items) do
            if string.find(link, "[" .. x.name .. "]", 1, true) then return x end
        end
    end
    C_Item.GetDetailedItemLevelInfo = function(link)
        local x = find(link)
        if x and x.level then return x.level end
    end
    C_Item.GetItemInfo = function(link)
        local x
        if type(link) == "number" then
            for _, it in pairs(S().items) do if CW.ItemId(it) == link then x = it end end
            if x then link = "|cffa335ee|Hitem:" .. link .. "|h[" .. x.name .. "]|h|r" end
        else x = find(link) end
        if x then return x.name, link, x.quality, x.level, 1, "Armor", x.subType end
    end
    _G.ITEM_QUALITY_COLORS = { [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
        [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 },
        [5] = { r = 1, g = 0.5, b = 0 } }
    _G.C_PaperDollInfo = { CursorCanGoInSlot = function(id) return S().cursorFits ~= nil and S().cursorFits[id] == true end }
    _G.CursorHasItem = function() return S().cursorFits ~= nil end
    -- A spell aimed at an item (the game's ItemButtonUtil.GetItemContext):
    -- S().aim = { kind = "enchant"|"condition", fits = { [slot id] = true } }.
    local function aimed(kind) return S().aim ~= nil and S().aim.kind == kind end
    local function fits(loc) return S().aim ~= nil and S().aim.fits[loc.equipmentSlotIndex] == true end
    _G.ItemLocation = { CreateFromEquipmentSlot = function(_, id) return { equipmentSlotIndex = id } end }
    _G.C_Spell = _G.C_Spell or {}
    C_Spell.TargetSpellIsEnchanting = function() return aimed("enchant") end
    C_Spell.TargetSpellChecksItemCondition = function() return aimed("condition") end
    C_Item.DoesItemExist = function(loc) return it(loc.equipmentSlotIndex) ~= nil end
    C_Item.DoesItemMatchTargetEnchantingSpell = function(loc) return aimed("enchant") and fits(loc) end
    C_Item.DoesItemMatchSpellItemCondition = function(loc) return aimed("condition") and fits(loc) end
end

local function installStats()
    -- Yours, or your pet's for "pet" (CW.petStats, same shape).
    local function st(u) return u == "pet" and S().petStats or S().stats end
    _G.UnitStat = function(u, i) local s = st(u).stat[i]; return many(s[1], s[2], s[3], s[4]) end
    _G.UnitDamage = function(u) local d = st(u).damage; return many(d[1], d[2], d[3] or d[1], d[4] or d[2]) end
    _G.UnitAttackSpeed = function(u) return many(st(u).speed[1], st(u).speed[2]) end
    _G.UnitAttackPower = function(u) return many(st(u).ap[1], st(u).ap[2], st(u).ap[3]) end
    _G.UnitRangedDamage = function() return many(st().ranged[1], st().ranged[2], st().ranged[3]) end
    _G.UnitRangedAttackPower = function() return many(st().rap[1], st().rap[2], st().rap[3]) end
    _G.CR_HIT_MELEE, _G.CR_HIT_RANGED, _G.CR_HIT_SPELL = 6, 7, 8
    _G.GetHitModifier = function() return secret(st().hit) end
    _G.GetOffhandHitModifier = function() return secret(st().ohit or st().hit) end
    _G.GetRangedHitModifier = function() return secret(st().rhit or 0) end
    _G.GetSpellHitModifier = function() return secret(st().spellHit or 0) end
    _G.GetCombatRatingBonus = function(cr) return secret(cr == 8 and st().shit or cr == 7 and st().rhitRating or st().hitRating) end
    _G.GetCritChance = function() return secret(st().crit) end
    _G.GetRangedCritChance = function() return secret(st().rcrit) end
    _G.GetExpertise = function() return many(st().expertise, st().ohExpertise or st().expertise, 0) end
    _G.IsDualWielding = function() return st().dual == true end
    _G.IsRangedWeapon = function() return st().rangedWeapon == true end
    _G.GetMeleeHaste = function() return secret(st().mhaste) end
    _G.GetRangedHaste = function() return many(st().rhaste[1], st().rhaste[2]) end
    _G.GetArmorPenetration = function() return secret(st().armorPen) end
    _G.GetSpellPenetration = function() return secret(st().spellPen) end
    _G.MANA, _G.RAGE, _G.ENERGY = "Mana", "Rage", "Energy"   -- the game's power words
    _G.GetSpellBonusDamage = function() return secret(st().spell) end
    _G.GetSpellBonusHealing = function() return secret(st().heal) end
    _G.GetSpellCritChance = function() return secret(st().scrit) end
    _G.GetManaRegen = function() return many(st().regen[1], st().regen[2]) end
    -- base, effective, real, bonus (UnitDocumentation; no Classic negBuff 5th value).
    _G.UnitArmor = function(u) local a = st(u).armor; return many(a[1], a[2], a[3], a[4]) end
    _G.UnitDefenseSkill = function() return many(st().defense[1], st().defense[2]) end
    _G.GetDodgeChance = function() return secret(st().dodge) end
    _G.GetParryChance = function() return secret(st().parry) end
    _G.GetBlockChance = function() return secret(st().block) end
    -- In game IsEquippedItemType("Shields") said no with a shield on. The game's own
    -- call is C_PaperDollInfo.OffhandHasShield.
    _G.IsEquippedItemType = function() return false end
    C_PaperDollInfo.OffhandHasShield = function() return st().shield == true end
    -- Plain in combat, as read in game.
    -- base, real, effective, bonus (UnitDocumentation), not Classic's base, total, plus, minus.
    _G.UnitResistance = function(u, i)
        local v = st(u).res[i] or 0
        local base, eff = v, v
        if type(v) == "table" then base, eff = v[1], v[2] end
        return base, eff, eff, eff - base
    end
    -- The pet's own calls (PlayerScriptDocumentation, UnitDocumentation).
    _G.GetPetSpellBonusDamage = function() return secret(st("pet").spell) end
    _G.GetPetHitChanceModifier = function() return secret(st("pet").hit) end
    _G.GetPetSpellHitChanceModifier = function() return secret(st("pet").shit) end
    _G.GetPetMeleeHaste = function() return secret(st("pet").haste) end
    _G.UnitSpellHaste = function(u) return secret(u == "player" and st().shaste or 0) end
    _G.GetPetCritChance = function() return many(st("pet").crit or 0, st("pet").scrit or 0) end
    _G.GetPetDodgeChance = function() return secret(st("pet").dodge or 0) end
    _G.GetUnitSpeed = function(u)
        local r = st(u).run or 7
        return many(0, r, st(u).fly or r, st(u).swim or r)
    end
    _G.IsSwimming = function(u) return st(u).swimming == true end
    _G.IsFlying = function(u) return st(u).flying == true end
    _G.IsFalling = function() return false end
    _G.BASE_MOVEMENT_SPEED = 7
    _G.GetSpecialization = function() return S().role and 1 or nil end
    _G.GetSpecializationRole = function() return S().role end
end

local function installModelAndMenus()
    _G.ModelSceneUtil = { SetUpCharacterSheetScene = function(scene)
        local a = { yaw = 0, dressed = {} }
        function a:IsLoaded() return S().modelLoaded ~= false end
        function a:DressPlayerSlot(slot) self.dressed[#self.dressed + 1] = slot end
        function a:SetYaw(y) self.yaw = y end
        function a:GetYaw() return self.yaw end
        S().actor = a
        record("setUpScene", true)
        scene.GetPlayerActor = function() return a end
    end }
    local titles = S().titles
    _G.GetNumTitles = function() return #titles end
    _G.IsTitleKnown = function(i) return titles[i] ~= nil and titles[i].known == true end
    _G.GetTitleName = function(i) return titles[i] and titles[i].name end
    _G.GetCurrentTitle = function() return S().title or 0 end
    _G.SetCurrentTitle = function(i) S().title = i; record("SetCurrentTitle", i) end
    local sets = S().sets
    _G.C_EquipmentSet = {
        GetEquipmentSetIDs = function()
            local ids = {}
            for i, s in ipairs(sets) do ids[i] = s.id end
            return ids
        end,
        GetEquipmentSetInfo = function(id)
            for _, s in ipairs(sets) do
                if s.id == id then return s.name, s.icon or 1, s.id, s.worn == true, 10, 0, 0, s.lost or 0, 0 end
            end
        end,
        GetNumEquipmentSets = function() return #sets end,
        CreateEquipmentSet = function(name, icon) record("CreateEquipmentSet", { name, icon }) end,
        GetEquipmentSetID = function(name)
            for _, s in ipairs(sets) do if s.name == name then return s.id end end
        end,
        SaveEquipmentSet = function(id, icon) record("SaveEquipmentSet", { id, icon }) end,
        ModifyEquipmentSet = function(id, name, icon) record("ModifyEquipmentSet", { id, name, icon }) end,
        DeleteEquipmentSet = function(id) record("DeleteEquipmentSet", id) end,
    }
    _G.EquipmentManager_EquipSet = function(id) record("EquipSet", id) end
    _G.UnitRace = function() return "Human", "Human" end
    _G.GetRealmName = function() return "Forever" end
    _G.PlaySound = function(id) record("PlaySound", id) end
    _G.SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2, IG_CHARACTER_INFO_TAB = 3 }
end

CW.STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- A faction as C_Reputation.GetFactionDataByIndex gives it. Fields: isHeader,
-- isChild, isCollapsed, atWarWith, canToggleAtWar, canSetInactive, isWatched,
-- inactive, description.
function CW.faction(name, reaction, value, min, max, fields)
    local f = { name = name, reaction = reaction, currentStanding = value, currentReactionThreshold = min,
                nextReactionThreshold = max, factionID = #name * 7 }
    for k, v in pairs(fields or {}) do f[k] = v end
    return f
end

local function installReputation(spec)
    local list = spec.factions or {}
    _G.C_Reputation = {
        GetNumFactions = function() return #list end,
        GetFactionDataByIndex = function(i)
            local f = list[i]
            if not f then return nil end
            local d = {}
            for k, v in pairs(f) do d[k] = v end
            d.factionIndex = i
            return d
        end,
        ExpandFactionHeader = function(i) record("ExpandFaction", i); list[i].isCollapsed = false end,
        CollapseFactionHeader = function(i) record("CollapseFaction", i); list[i].isCollapsed = true end,
        ToggleFactionAtWar = function(i) record("AtWar", i) end,
        SetFactionActive = function(i, on) record("SetFactionActive", { i, on }) end,
        IsFactionActive = function(i) return list[i] ~= nil and list[i].inactive ~= true end,
        SetWatchedFactionByIndex = function(i) record("Watch", i) end,
    }
    _G.GetText = function(key) return CW.STANDINGS[tonumber(string.match(key, "(%d+)$")) or 0] end
    _G.UnitSex = function() return 2 end
end

-- A skill line. Fields: isHeader, isChild, skillID (a header's category),
-- skillLineCategoryID, rank, maxRank, modifier, isCollapsed. isChild isn't in the
-- SkillLineAttributes docs, but the game's own Forever skills window reads it
-- (Camelot/SkillsFrame.lua, for indent and the sub-header template).
function CW.skill(name, fields)
    local s = { name = name, rank = 0, maxRank = 0, modifier = 0 }
    for k, v in pairs(fields or {}) do s[k] = v end
    return s
end

local function installSkills(spec)
    local list = spec.skills or {}
    _G.C_SkillInfo = {
        GetNumSkillLines = function() return #list end,
        GetSkillLineInfo = function(i)
            local s = list[i]
            if not s then return nil end
            local d = {}
            for k, v in pairs(s) do d[k] = v end
            return d
        end,
        ExpandSkillHeader = function(i) record("ExpandSkill", i); list[i].isCollapsed = false end,
        CollapseSkillHeader = function(i) record("CollapseSkill", i); list[i].isCollapsed = true end,
    }
end

CW.PVP_RANKS = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major", "Knight" }

-- spec.pvp: renownLevel, renownReputationEarned, renownLevelThreshold,
-- currentWeekProgressiveMaxLevel, previousWeekProgressiveMaxLevel, maxLevel,
-- seasonEnds (seconds), season. Rank N costs N x 1000 in all.
local function installPvP(spec)
    local p = spec.pvp
    _G.C_MajorFactions = {
        GetMajorFactionProgressionInfo = function(id)
            if id ~= 2800 or not p then return nil end
            local d = {}
            for k, v in pairs(p) do d[k] = v end
            return d
        end,
        GetTotalReputationForRenownLevel = function(_, level) return (level or 0) * 1000 end,
    }
    _G.C_SeasonInfo = { GetTimeUntilCurrentPVPSeasonEnd = function() return p and p.seasonEnds or 0 end }
    _G.GetCurrentArenaSeason = function() return p and p.season or 0 end
    _G.GetPVPRankText = function(rank) return CW.PVP_RANKS[rank] or ("Rank " .. rank) end
end

-- spec.statistics = { categories = { { id, title, parent } }, stats = { [category id] = { { id, name, quantity } } } }
local function installStatistics(spec)
    local s = spec.statistics or { categories = {}, stats = {} }
    _G.GetStatisticsCategoryList = function()
        local ids = {}
        for i, c in ipairs(s.categories) do ids[i] = c.id end
        return ids
    end
    _G.GetCategoryInfo = function(id)
        for _, c in ipairs(s.categories) do if c.id == id then return c.title, c.parent or -1 end end
    end
    _G.GetCategoryNumAchievements = function(id) return #(s.stats[id] or {}) end
    _G.GetStatistic = function(cat, i)
        local st = (s.stats[cat] or {})[i]
        if st then return st.quantity, st.skip == true, st.id end
    end
    _G.GetAchievementInfo = function(id)
        for _, list in pairs(s.stats) do
            for _, st in ipairs(list) do if st.id == id then return id, st.name end end
        end
    end
end

-- spec.currency: a list of C_CurrencyInfo.GetCurrencyListInfo tables.
local function installCurrency(spec)
    local list = spec.currency or {}
    _G.C_CurrencyInfo = {
        GetCurrencyListSize = function() return #list end,
        GetCurrencyListInfo = function(i)
            local c = list[i]
            if not c then return nil end
            local d = {}
            for k, v in pairs(c) do d[k] = v end
            return d
        end,
        ExpandCurrencyList = function(i, on) record("ExpandCurrency", { i, on }) end,
        SetCurrencyBackpack = function(i, on) record("Backpack", { i, on }) end,
        GetCurrencyDescription = function(id) return "What currency " .. tostring(id) .. " is for." end,
    }
end

-- A level 60 wolf's numbers. A test changes CW.state.petStats.
function CW.defaultPetStats()
    return {
        damage = { 80, 110 }, ap = { 400, 30, 0 }, armor = { 2000, 2100, 2100, 100 },
        res = { [2] = 5, [3] = 0, [4] = 0, [5] = 0, [6] = 0 }, spell = 0, hit = 2, shit = 0, haste = 0, run = 7 * 1.1,
    }
end

-- spec.pet: name, level, family, hunter (a hunter's pet: mood, loyalty and XP),
-- loyalty, xp, xpNeed, mood (1-3), damage, rate. nil means no pet out.
-- CW.SetPet(pet) summons another mid-test, or dismisses it with nil.
function CW.SetPet(pet)
    S().pet = pet
    stub.units.pet = pet and { name = pet.name or "Fang", level = pet.level or 60, maxHealth = pet.maxHealth or 3200,
        maxPower = pet.maxPower or 100, maxMana = pet.maxMana or 0, powerToken = pet.powerToken or "FOCUS" } or nil
end

local function installPet()
    local function pet() return S().pet end
    _G.HasPetUI = function()
        local p = pet()
        if not p then return false, false end
        return true, p.hunter == true
    end
    _G.UnitCreatureFamily = function(u) local p = pet(); if u == "pet" and p then return p.family or "Wolf", p.familyId or 1 end end
    _G.GetPetExperience = function() local p = pet(); return p and p.xp or 0, p and p.xpNeed or 0 end
    _G.C_PetInfo = {
        GetPetHappiness = function() local p = pet(); return p and p.mood or 3, p and p.damage or 125, p and p.rate or 1 end,
        GetPetLoyalty = function() local p = pet(); return p and p.loyalty or "" end,
        GetPetUIModelSceneID = function() return 718 end,
        GetPetFoodTypes = function() return { "Meat", "Fish" } end,
    }
    _G.PET_HAPPINESS1, _G.PET_HAPPINESS2, _G.PET_HAPPINESS3 = "Unhappy", "Content", "Happy"
    _G.PET_DAMAGE_PERCENTAGE = "Pet is doing %d%% damage"
    _G.CAMERA_TRANSITION_TYPE_IMMEDIATE, _G.CAMERA_MODIFICATION_TYPE_DISCARD = 1, 1
end

-- The game's pet scene on the pet model's ModelScene (the stub's scene only has
-- the widget's own methods, not the template's mixin).
function CW.PetScene(scene)
    function scene.TransitionToModelSceneID(_, id) record("petScene", id) end
    function scene.ReleaseAllActors() record("releaseActors", true) end
    function scene.GetActorByTag(_, tag)
        local a = { yaw = 0, tag = tag }
        function a:IsLoaded() return S().petLoaded ~= false end
        function a:SetModelByUnitCreatureDisplayID(u) record("petModel", u) end
        function a:SetYaw(y) self.yaw = y end
        function a:GetYaw() return self.yaw end
        S().petActor = a
        return a
    end
end

-- spec: items = { Head = CW.item(...) }, usesAmmo, class, role, titles =
-- { { name, known } }, title, sets = { { id, name, worn, lost } },
-- missing / hiddenPages = { [frame name] = true }, plus the other pages' fields
-- (see their install functions).
function CW.world(spec)
    spec = spec or {}
    return function()
        CW.state = {
            calls = {}, panel = {}, items = {}, stats = CW.defaultStats(), usesAmmo = spec.usesAmmo,
            titles = spec.titles or {}, sets = spec.sets or {}, title = spec.title, role = spec.role,
            secret = false, spec = spec, petStats = CW.defaultPetStats(),
        }
        for key, item in pairs(spec.items or {}) do CW.state.items[CW.SLOT_IDS[key]] = item end
        local token = ({ WARRIOR = "RAGE", ROGUE = "ENERGY" })[spec.class or "WARRIOR"] or "MANA"
        stub.SetUnits({ player = { name = "Daylight", class = spec.class or "WARRIOR", level = 60, isPlayer = true,
            maxHealth = 4200, maxPower = token == "MANA" and 3000 or 100, maxMana = token == "MANA" and 3000 or 0, powerToken = token } })
        if spec.pet then CW.SetPet(spec.pet) end
        buildFrames(spec)
        installInventory()
        installStats()
        installModelAndMenus()
        installReputation(spec)
        installSkills(spec)
        installPvP(spec)
        installStatistics(spec)
        installCurrency(spec)
        installPet()
    end
end

return CW
