-- The fake game's professions for the profession window's tests: the trade skill
-- as Forever runs it (Blizzard_Professions and its Camelot/ overrides, plus what
-- was seen in game):
--   * Casting a profession's spell (or OpenTradeSkill) opens its trade skill:
--     TRADE_SKILL_SHOW, the ProfessionsFrame shows, then TRADE_SKILL_LIST_UPDATE.
--     Switching while it's open (a tab) fires the same and the frame stays shown
--     (no TRADE_SKILL_CLOSE). Who shows the frame on the first open isn't in the
--     game's Lua (the client loads Blizzard_Professions), so this is a guess,
--     done here as ShowUIPanel after TRADE_SKILL_SHOW.
--   * ProfessionsFrame is made on the first open (ADDON_LOADED
--     "Blizzard_Professions"). Its OnHide calls CloseTradeSkill, and
--     TRADE_SKILL_CLOSE hides it unless its BookPage shows
--     (ProfessionsMixin:OnHide, OnTradeSkillClosed).
--   * GetAllRecipeIDs lists every recipe, learned or not.
--
--   * The slot filter (Camelot Professions.InitSlotsFilter, the game's
--     Professions.SetInventorySlotFilter): a profession's slots
--     (GetAllFilterableInventorySlotsCount/Name, none for Cooking),
--     SetInventorySlotFilter(i, checked, only), ClearInventorySlotFilter.
--     GetFilteredRecipeIDs gives the learned ones in a shown slot (a recipe with
--     no slot goes in the last one, Created Items). A change lists again.
--
--   * Crafting: CraftRecipe(id, n) starts n casts of the recipe's spell, by its
--     id (UNIT_SPELLCAST_FAILED player <guid> 2538 in game). A test plays each
--     with PW.Cast() (START, then SUCCEEDED: materials used, the bags' event) or
--     PW.Cast(false) (FAILED, and the rest won't come).
--   * Cooldowns: a recipe with cooldown = seconds starts it when a cast of it
--     succeeds. C_TradeSkillUI.GetRecipeCooldown(id) then answers what the game's
--     ProfessionsRecipeSchematicForm reads: cooldown (seconds left, nil when
--     none), isDayCooldown, charges, maxCharges. PW.Cooldown(id, seconds) sets
--     one by hand, or clears it with nil.
--
-- PW.world(spec) is stub.Load's "before". A test then plays PW.Open(skillLine),
-- PW.Close(), PW.SetBag(itemID, n), and reads PW.Calls(kind).
local stub = require("stub")

local PW = {}

local function S() return PW.state end
local function record(kind, ...) table.insert(S().calls, { kind = kind, args = { ... } }) end
function PW.Calls(kind)
    local out = {}
    for _, c in ipairs(S().calls) do if c.kind == kind then out[#out + 1] = c.args end end
    return out
end

-- The button the player is pressing. In game, a craft started after the addon's
-- click hid its own button was blocked ("the game blocked UNKNOWN()" from inside
-- CraftRecipe), while started first the same call goes through. The client's real
-- rule isn't in its source, so this models what was seen.
function PW.Press(button) S().pressed = button; button:Click(); S().pressed = nil end
local function refused(what)
    local b = S().pressed
    if not b or b:IsVisible() then return false end
    stub.errors[#stub.errors + 1] = "ADDON_ACTION_BLOCKED: UNKNOWN() (" .. what .. ")"
    return true
end

-- The game's own code runs untainted (stub.inSecure).
local function asGame(fn, ...)
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(fn, ...)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 2) end
end

-- Sample professions: Tailoring (two categories, one recipe not learned),
-- Herbalism (no crafting window), Cooking (one recipe needing a fire).
function PW.Sample()
    return {
        { name = "Tailoring", skillLine = 197, icon = 136249, spellID = 3908, rank = 148, max = 225,
          slots = { "Head", "Chest", "Created Items" }, recipes = {
            { id = 101, name = "Azure Silk Hood", cat = 11, difficulty = 0, skillUps = 1, mats = { { 4305, 2 }, { 2321, 2 } }, out = 7048, quality = 2, slot = 1 },
            { id = 102, name = "Bolt of Silk Cloth", cat = 10, difficulty = 1, mats = { { 4306, 4 } }, out = 4305, quality = 1 },
            { id = 103, name = "Brown Linen Shirt", cat = 11, difficulty = 3, mats = { { 2996, 3 }, { 2320, 1 } }, out = 4344, quality = 1, slot = 2 },
            { id = 104, name = "Bolt of Linen Cloth", cat = 10, difficulty = 3, mats = { { 2589, 2 } }, out = 2996, quality = 1 },
            { id = 105, name = "Red Woolen Bag", cat = 11, difficulty = 2, learned = false, mats = { { 2997, 3 } }, out = 5763, quality = 1 },
        } },
        { name = "Herbalism", skillLine = 182, icon = 136246, spellID = 2366, rank = 120, max = 150, craftingUI = false, recipes = {},
          extra = { { spellID = 2383, name = "Find Herbs", icon = 133939 }, { spellID = 55428, name = "Lifeblood", passive = true } } },
        { name = "Cooking", skillLine = 185, icon = 133971, spellID = 2550, rank = 2, max = 75, recipes = {
            { id = 2538, name = "Charred Wolf Meat", cat = 20, difficulty = 0, mats = { { 2672, 1 } }, out = 2679, quality = 1,
              requires = { { name = "Cooking Fire", met = false } } },
        } },
    }
end

PW.CATEGORIES = { [10] = { name = "Materials", uiOrder = 5 }, [11] = { name = "Cloth Armor", uiOrder = 10 },
                  [20] = { name = "Everyday Meals", uiOrder = 10 } }
PW.ITEMS = { [4305] = "Bolt of Silk Cloth", [2321] = "Fine Thread", [4306] = "Silk Cloth", [2996] = "Bolt of Linen Cloth",
             [2320] = "Coarse Thread", [2589] = "Linen Cloth", [2997] = "Bolt of Woolen Cloth", [2672] = "Stringy Wolf Meat",
             [7048] = "Azure Silk Hood", [4344] = "Brown Linen Shirt", [5763] = "Red Woolen Bag", [2679] = "Charred Wolf Meat" }

local function prof(skillLine)
    for _, p in ipairs(S().profs) do if p.skillLine == skillLine then return p end end
    return nil
end

local function recipe(id)
    for _, p in ipairs(S().profs) do
        for _, r in ipairs(p.recipes) do if r.id == id then return r, p end end
    end
    return nil
end

local function craftable(r)
    local n
    for _, m in ipairs(r.mats) do
        local can = math.floor((S().bags[m[1]] or 0) / m[2])
        n = n and math.min(n, can) or can
    end
    return n or 0
end

local function frame()
    if _G.ProfessionsFrame then return _G.ProfessionsFrame end
    local f = CreateFrame("Frame", "ProfessionsFrame", UIParent)
    f:Hide()
    f.CraftingPage = CreateFrame("Frame", nil, f)
    f.BookPage = CreateFrame("Frame", nil, f)
    f.BookPage:Hide()
    f:SetScript("OnHide", function() C_TradeSkillUI.CloseTradeSkill() end)
    f:RegisterEvent("TRADE_SKILL_CLOSE")
    f:SetScript("OnEvent", function(self, event)
        if event == "TRADE_SKILL_CLOSE" and not self.BookPage:IsShown() then asGame(HideUIPanel, self) end
    end)
    record("LoadAddOn", "Blizzard_Professions")
    stub.FireEvent("ADDON_LOADED", "Blizzard_Professions")
    return f
end

function PW.Load() return frame() end

-- The profession opens (its spell cast, or a tab). See the top.
function PW.Open(skillLine)
    asGame(function()
        local f = frame()
        S().open = skillLine
        f.BookPage:Hide()
        f.CraftingPage:Show()
        stub.FireEvent("TRADE_SKILL_SHOW")
        ShowUIPanel(f)
        stub.FireEvent("TRADE_SKILL_LIST_UPDATE")
    end)
end

-- Someone's link: the game's frame shows first, before any of their data has come
-- in (the game's IsDataSourceChanging may or may not say so, since a list can also
-- just be empty). PW.LinkArrives brings it (TRADE_SKILL_LIST_UPDATE).
function PW.LinkOpens(changing)
    asGame(function()
        local f = frame()
        S().open, S().linked, S().changing = nil, false, changing == true
        f.BookPage:Hide()
        f.CraftingPage:Show()
        stub.FireEvent("TRADE_SKILL_SHOW")
        ShowUIPanel(f)
    end)
end

function PW.LinkArrives(skillLine, name)
    asGame(function()
        S().open, S().linked, S().linkedName, S().changing = skillLine, true, name, false
        stub.FireEvent("TRADE_SKILL_LIST_UPDATE")
    end)
end

-- The game's overview page (every profession) inside the same frame.
function PW.Overview()
    asGame(function()
        local f = frame()
        f.CraftingPage:Hide()
        f.BookPage:Show()
        ShowUIPanel(f)
    end)
end

function PW.Close() asGame(function() HideUIPanel(frame()) end) end

function PW.SetBag(itemID, n)
    S().bags[itemID] = n
    stub.FireEvent("BAG_UPDATE_DELAYED")
end

-- A skill point: the rank goes up and the list event comes.
-- Items an enchant can go on: { { guid, name, enchant = what's on it } }.
function PW.EnchantItems(list) S().enchantItems = list end

-- The game's rule (its REPLACE_TRADESKILL_ENCHANT dialog): an item with an enchant
-- on it asks before each cast, and nothing casts until it's answered.
local function askReplace(c)
    local item = c.target
    if not (item and item.enchant) then return end
    c.asking = true
    stub.FireEvent("REPLACE_TRADESKILL_ENCHANT", item.enchant, c.name)
end

-- One cast of the craft under way (see the top).
function PW.Cast(ok)
    local c = S().crafting
    if not c or c.asking then return end
    S().castInfo = { name = c.name, from = 1000, to = 2500 }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "Cast-" .. c.left, c.id)
    S().castInfo = nil
    if ok == false then
        S().crafting = nil
        stub.FireEvent("UNIT_SPELLCAST_FAILED", "player", "Cast-" .. c.left, c.id)
        return
    end
    for _, m in ipairs(c.mats) do S().bags[m[1]] = math.max(0, (S().bags[m[1]] or 0) - m[2]) end
    local r = recipe(c.id)
    if r and r.cooldown then S().cds[c.id] = r.cooldown end
    c.left = c.left - 1
    if c.target then c.target.enchant = c.name end
    if c.left <= 0 then S().crafting = nil end
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. (c.left + 1), c.id)
    stub.FireEvent("BAG_UPDATE_DELAYED")
    if c.left > 0 then askReplace(c) end
end

-- Sets a recipe's cooldown by hand in seconds left, or clears it with nil.
function PW.Cooldown(id, seconds) S().cds[id] = seconds end

function PW.SkillUp(skillLine)
    local p = prof(skillLine or S().open)
    p.rank = p.rank + 1
    stub.FireEvent("TRADE_SKILL_LIST_UPDATE")
end

local original = {}
local function keep(t, name)
    local key = tostring(t) .. name
    if original[key] == nil then original[key] = t[name] or false end
    return original[key] or nil
end

local function install()
    Enum.SpellBookSpellBank = Enum.SpellBookSpellBank or { Player = 0, Pet = 1 }
    _G.ShowUIPanel = function(f) record("ShowUIPanel", f:GetName()); f:Show() end
    -- The game's rule (UIParentPanelManager.lua) checks CheckProtectedFunctionsAllowed,
    -- so from addon code in combat it does nothing.
    _G.HideUIPanel = function(f)
        if stub.combat and (stub.inSecure or 0) == 0 then return end
        record("HideUIPanel", f:GetName()); f:Hide()
    end
    -- SetAttributeNoHandler on a UI panel is refused to addon code in a fight
    -- (ADDON_ACTION_BLOCKED ProfessionsFrame:SetAttributeNoHandler() in game).
    _G.SetUIPanelAttribute = function(f, key, value)
        if stub.combat and (stub.inSecure or 0) == 0 then
            stub.errors[#stub.errors + 1] = "ADDON_ACTION_BLOCKED: " .. tostring(f:GetName()) .. ":SetAttributeNoHandler()"
            return
        end
        record("SetUIPanelAttribute", key, value)
    end
    _G.GetProfessions = function()
        local out = {}
        for i = 1, #S().profs do out[i] = i end
        return unpack(out)
    end
    _G.GetProfessionInfo = function(i)
        local p = S().profs[i]
        if not p then return nil end
        return p.name, p.icon, p.rank, p.max, 1 + #(p.extra or {}), i * 10, p.skillLine
    end
    -- A profession's spells sit at i * 10 + 1 (its own), then its extra ones (Find
    -- Herbs, a passive the game's book shows but can't be dragged).
    Enum.SpellBookItemType = Enum.SpellBookItemType or { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }
    local spellInfo = keep(C_SpellBook, "GetSpellBookItemInfo")
    C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
        local p = S().profs[math.floor(slot / 10)]
        local k = slot % 10
        local s = p and (k == 1 and p or (p.extra or {})[k - 1])
        if s then return { spellID = s.spellID, name = s.name, iconID = s.icon, isPassive = s.passive == true,
                           itemType = Enum.SpellBookItemType.Spell } end
        if spellInfo then return spellInfo(slot, bank) end
        return nil
    end
    C_SpellBook.PickupSpellBookItem = function(slot, bank) record("PickupSpellBookItem", slot, bank) end
    C_Item.GetItemLocation = function(guid)
        for _, item in ipairs(S().enchantItems or {}) do
            if item.guid == guid then return item end
        end
    end
    C_Item.GetItemName = function(loc) return loc.name end
    C_Item.GetItemIcon = function(loc) return loc.icon or 134952 end
    C_Item.GetItemQuality = function(loc) return loc.quality or 2 end
    C_Item.ReplaceTradeskillEnchant = function()
        record("ReplaceTradeskillEnchant")
        if S().crafting then S().crafting.asking = nil end
    end
    _G.StaticPopup_Hide = function(which) record("StaticPopup_Hide", which) end
    for _, name in ipairs({ "GetItemCount", "GetItemNameByID", "GetItemIconByID", "GetItemQualityByID", "GetItemInfo" }) do
        local mine = keep(C_Item, name)
        C_Item[name] = function(id, ...)
            local known = PW.ITEMS[id]
            if not known then
                if type(id) == "string" then
                    for item, n in pairs(PW.ITEMS) do
                        if id:find(n, 1, true) then known, id = n, item; break end
                    end
                end
                if not known then return mine and mine(id, ...) or nil end
            end
            if name == "GetItemCount" then return S().bags[id] or 0 end
            if name == "GetItemNameByID" then return known end
            if name == "GetItemIconByID" then return 1000 + id end
            if name == "GetItemQualityByID" then
                for _, p in ipairs(S().profs) do for _, r in ipairs(p.recipes) do if r.out == id then return r.quality end end end
                return 1
            end
            return known, "|cffffffff|Hitem:" .. id .. "|h[" .. known .. "]|h|r"
        end
    end
    local casting = keep(_G, "UnitCastingInfo")
    _G.UnitCastingInfo = function(unit)
        local c = unit == "player" and S().castInfo
        if c then return c.name, c.name, 1, c.from, c.to, true, "Cast-1", false, 1 end
        return casting and casting(unit) or nil
    end
    local open = function() return S().open and prof(S().open) end
    _G.C_TradeSkillUI = {
        -- The game's link button (Blizzard_ProfessionsCrafting.lua) links your own
        -- open profession. With nothing open there's nothing to link.
        CanTradeSkillListLink = function() return S().open ~= nil and S().noLink ~= true end,
        GetTradeSkillListLink = function()
            local p = open()
            if not p or S().noListLink then return nil end
            return "|cffffd000|Htrade:Player-1:" .. p.skillLine .. "|h[" .. p.name .. "]|h|r"
        end,
        GetBaseProfessionInfo = function()
            local p = open()
            if not p then return { professionID = 0, professionName = "", skillLevel = 0, maxSkillLevel = 0, skillModifier = 0 } end
            return { professionID = p.skillLine, professionName = p.name, skillLevel = p.rank, maxSkillLevel = p.max,
                     skillModifier = 0, profession = 1, sourceCounter = 1 }
        end,
        -- Someone's link reads their skill here (the game's Professions.GetProfessionInfo
        -- checks the child first), and so does your own when the child line has its own
        -- number (`p.childRank`). The game's rank bar shows the child's whatever the base says.
        GetChildProfessionInfo = function()
            local p = open()
            local s = S().linkedSkill or (p and p.childRank)
            if p and s then
                return { professionID = p.skillLine, professionName = p.name, skillLevel = s, maxSkillLevel = p.max, skillModifier = 0 }
            end
            return { professionID = 0, professionName = "", skillLevel = 0, maxSkillLevel = 0 }
        end,
        GetAllFilterableInventorySlotsCount = function() return open() and open().slots and #open().slots or 0 end,
        GetFilterableInventorySlotName = function(i) return open() and open().slots and open().slots[i] end,
        SetInventorySlotFilter = function(i, checked, only)
            record("SetInventorySlotFilter", i, checked, only)
            local n = open() and open().slots and #open().slots or 0
            if only then for k = 1, n do S().hiddenSlots[k] = true end end
            S().hiddenSlots[i] = not checked or nil
            C_Timer.After(0, function() stub.FireEvent("TRADE_SKILL_LIST_UPDATE") end)
        end,
        ClearInventorySlotFilter = function()
            record("ClearInventorySlotFilter")
            S().hiddenSlots = {}
            C_Timer.After(0, function() stub.FireEvent("TRADE_SKILL_LIST_UPDATE") end)
        end,
        GetFilteredRecipeIDs = function()
            local out, p = {}, open()
            for _, r in ipairs(p and p.recipes or {}) do
                local slot = r.slot or (p.slots and #p.slots)
                if r.learned ~= false and not (slot and S().hiddenSlots[slot]) then out[#out + 1] = r.id end
            end
            return out
        end,
        GetAllRecipeIDs = function()
            local out = {}
            for _, r in ipairs(open() and open().recipes or {}) do out[#out + 1] = r.id end
            return out
        end,
        GetRecipeInfo = function(id)
            local r = recipe(id)
            if not r then return nil end
            return { recipeID = r.id, name = r.name, icon = 2000 + r.id, categoryID = r.cat, learned = r.learned ~= false,
                relativeDifficulty = r.difficulty, numSkillUps = r.skillUps or 1, canSkillUp = r.difficulty ~= 3,
                isEnchantingRecipe = r.enchant == true, isDummyRecipe = false,
                -- The made item's link. An enchant makes none.
                hyperlink = not r.enchant and ("|cffffffff|Hitem:" .. (9000 + r.id) .. "|h[" .. r.name .. "]|h|r") or nil }
        end,
        -- The recipe's own link, as Shift-click in the game's list gives.
        GetRecipeLink = function(id)
            local r = recipe(id)
            return r and ("|cffffd000|Henchant:" .. r.id .. "|h[" .. r.name .. "]|h|r") or nil
        end,
        GetRecipeSchematic = function(id)
            local r = recipe(id)
            local slots = {}
            for i, m in ipairs(r and r.mats or {}) do
                slots[i] = { reagents = { { itemID = m[1] } }, quantityRequired = m[2], required = true, hiddenInCraftingForm = false, slotIndex = i }
            end
            local y = r and r.yield or {}
            return { recipeID = id, name = r and r.name or "", outputItemID = r and r.out, reagentSlotSchematics = slots,
                     quantityMin = y[1] or 1, quantityMax = y[2] or y[1] or 1,
                     recipeType = r and r.enchant and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Enchant or nil }
        end,
        GetCraftableCount = function(id) local r = recipe(id); return r and craftable(r) or 0 end,
        GetRecipeCooldown = function(id)
            local left = S().cds[id]
            return left, false, 0, 0
        end,
        GetRecipeRequirements = function(id) local r = recipe(id); return r and r.requires or {} end,
        GetRecipeDescription = function(id) local r = recipe(id); return r and r.description or "" end,
        GetCategoryInfo = function(id)
            local c = PW.CATEGORIES[id]
            return c and { categoryID = id, name = c.name, uiOrder = c.uiOrder, type = "subheader" } or nil
        end,
        IsRecipeInSkillLine = function(id, skillLine) local _, p = recipe(id); return p ~= nil and p.skillLine == skillLine end,
        CanTradeSkillShowCraftingUI = function(spellID)
            for _, p in ipairs(S().profs) do if p.spellID == spellID then return p.craftingUI ~= false end end
            return false
        end,
        OpenTradeSkill = function(skillLine)
            if not stub.HardwareOnly("OpenTradeSkill") then return false end
            record("OpenTradeSkill", skillLine)
            if not prof(skillLine) then return false end
            C_Timer.After(0, function() PW.Open(skillLine) end)
            return true
        end,
        CloseTradeSkill = function()
            record("CloseTradeSkill")
            if S().open then
                S().open = nil
                stub.FireEvent("TRADE_SKILL_CLOSE")
            end
        end,
        CraftRecipe = function(id, n)
            record("CraftRecipe", id, n)
            if refused("CraftRecipe") then return end
            local r = recipe(id)
            if r then S().crafting = { id = id, name = r.name, mats = r.mats, left = n or 1 } end
        end,
        CraftEnchant = function(id, n, reagents, target)
            record("CraftEnchant", id, n, target)
            if refused("CraftEnchant") then return end
            local r = recipe(id)
            if not (r and target) then return end
            S().crafting = { id = id, name = r.name, mats = r.mats, left = n or 1, target = target }
            askReplace(S().crafting)
        end,
        GetEnchantItems = function()
            local out = {}
            for _, item in ipairs(S().enchantItems or {}) do out[#out + 1] = item.guid end
            return out
        end,
        -- The game's two answers (ProfessionsMixin:SetTitle): linked, then whose.
        IsTradeSkillLinked = function() return S().linked == true, S().linkedName end,
        IsTradeSkillGuild = function() return S().guild == true end,
        IsTradeSkillGuildMember = function() return S().guildMember == true end,
        GetTradeSkillTexture = function() local p = open(); return p and p.icon end,
        IsDataSourceChanging = function() return S().changing == true end,
        IsNPCCrafting = function() return false end,
    }
end

-- spec: profs (default PW.Sample(); a recipe may carry yield = { min, max } and enchant = true),
-- bags { [itemID] = n }, enabled (the module's switch, default true here since the tests are
-- about Daylight UI's window), noDB (true seeds no DaylightUIDB; Mogul's loader asks for it).
function PW.world(spec)
    spec = spec or {}
    return function()
        PW.state = { calls = {}, cds = {}, profs = spec.profs or PW.Sample(), linked = spec.linked, hiddenSlots = {},
            bags = spec.bags or { [4305] = 5, [2321] = 3, [4306] = 8, [2589] = 1, [2672] = 7 } }
        _G.ProfessionsFrame = nil
        install()
        if not spec.noDB then DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Professions = { enabled = spec.enabled ~= false } } } } } end
    end
end

return PW
