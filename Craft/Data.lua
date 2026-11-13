-- Reads what the profession window shows from C_TradeSkillUI: the open profession,
-- the professions that have a crafting window (the tabs), and learned recipes by
-- category. Forever hides unlearned recipes (Camelot
-- Professions.GetDefaultShowUnlearned is false), so this does too. The trade skill's
-- own filters are left alone; chips and search filter in Lua, so the game's window
-- still shows what it always did when handed back.
--
-- The recipe calls only refuse secrets from tainted code ("AllowedWhenUntainted") and
-- none of their returns are marked secret, but numbers are still checked with
-- issecretvalue before comparing.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L

local Data = {}
ns.Data = Data

-- Enum.TradeskillRelativeDifficulty values (the enum may be missing).
Data.OPTIMAL, Data.MEDIUM, Data.EASY, Data.TRIVIAL = 0, 1, 2, 3

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function num(v) return type(v) == "number" and not secret(v) and v or nil end
local function str(v) return type(v) == "string" and not secret(v) and v or nil end

local function TS() return type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil end

-- Guarded call to C_TradeSkillUI[name]; undocumented calls may not exist.
local function call(name, ...)
    local ts = TS()
    local fn = ts and ts[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

-- The trade skill list is being re-read (a switch), so it's half old, half new.
-- TRADE_SKILL_LIST_UPDATE follows when done; ProfessionsMixin:OnEvent waits for it
-- the same way.
function Data.Changing() return call("IsDataSourceChanging") == true end

-- The open profession: { id, name, skill, max, bonus }, nil when none is open.
-- id and name come from the base skill line (what the tabs use). skill, max and bonus
-- are what the game's window shows (Professions.GetProfessionInfo: child line first,
-- else the base), for the player's own and for a linked profession alike.
function Data.Profession()
    local p = call("GetBaseProfessionInfo")
    if type(p) ~= "table" then return nil end
    local id = num(p.professionID)
    if not id or id == 0 then return nil end
    local c = call("GetChildProfessionInfo")
    local shown = (type(c) == "table" and (num(c.professionID) or 0) ~= 0) and c or p
    return { id = id, name = str(p.professionName) or "", skill = num(shown.skillLevel) or 0,
             max = num(shown.maxSkillLevel) or 0, bonus = num(shown.skillModifier) or 0 }
end

-- Viewing someone else's recipes: a link, or one guild member's (like
-- Professions.IsViewingExternalCraftingList, minus the whole-guild list, which only
-- the game's window handles). Returns the owner's name, or true if unknown; nil for
-- the player's own, an NPC's, and the guild list.
function Data.Viewing()
    if call("IsTradeSkillGuild") == true then return nil end
    local linked, owner = call("IsTradeSkillLinked")
    if linked == true then return str(owner) or true end
    if call("IsTradeSkillGuildMember") == true then return true end
    return nil
end

function Data.Icon(id) return (call("GetTradeSkillTexture", id)) end

-- Professions with a crafting window, in the game's tab order (GetProfessions: two
-- primaries, which can be unlearned, then secondaries). Same rule as Forever's own
-- tabs (Camelot ProfessionsMixin:RefreshRightTab): gathering professions like
-- Herbalism and Skinning fail CanTradeSkillShowCraftingUI.
function Data.Tabs()
    local out = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out end
    local list = { GetProfessions() }
    for i = 1, 7 do
        local idx = list[i]
        if idx then
            local name, icon, rank, maxRank, _, offset, skillLine = GetProfessionInfo(idx)
            local spellID
            if type(offset) == "number" and C_SpellBook and type(C_SpellBook.GetSpellBookItemInfo) == "function" then
                local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
                local item = C_SpellBook.GetSpellBookItemInfo(offset + 1, bank)
                spellID = type(item) == "table" and num(item.spellID) or nil
            end
            if spellID and call("CanTradeSkillShowCraftingUI", spellID) == true and num(skillLine) then
                out[#out + 1] = { skillLine = skillLine, name = str(name) or "", icon = icon, spellID = spellID,
                                  rank = num(rank) or 0, max = num(maxRank) or 0, primary = i <= 2 }
            end
        end
    end
    return out
end

-- Primary professions (the ones that can be unlearned), with or without a crafting
-- window. Gathering ones have no tab but can still be dropped.
function Data.Primaries()
    local out = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out end
    local one, two = GetProfessions()
    for _, idx in ipairs({ one or false, two or false }) do
        if idx then
            local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if num(skillLine) then out[#out + 1] = { name = str(name) or "", skillLine = skillLine } end
        end
    end
    return out
end

-- Difficulty color: the game's orange, yellow and green; trivial is a warm dim
-- instead of the game's gray.
function Data.Color(difficulty)
    local INK = DUI.Style.INK
    local function game(c, fallback)
        if type(c) == "table" and type(c.GetRGB) == "function" then return { c:GetRGB() } end
        return fallback
    end
    if difficulty == Data.OPTIMAL then return game(_G.DIFFICULT_DIFFICULTY_COLOR, INK.BAD) end
    if difficulty == Data.MEDIUM then return game(_G.FAIR_DIFFICULTY_COLOR, INK.WARN) end
    if difficulty == Data.EASY then return game(_G.EASY_DIFFICULTY_COLOR, INK.GOOD) end
    return INK.OFF
end

-- Recipe name color in the list: its skill-up color, or with rarity on, the quality
-- of what it makes. Enchants make no item, so they stay white like on the recipe page,
-- and so do uncached items until their info arrives.
function Data.NameColor(recipe, rarity)
    if not rarity then return Data.Color(recipe.difficulty) end
    local q = Data.OutputQuality(recipe.id)
    if type(q) == "number" then return { DUI.Win.Parts.QualityColor(q) } end
    return DUI.Style.INK.TITLE
end

-- Difficulty label (the recipe's top line).
function Data.SkillWords(difficulty)
    if difficulty == Data.OPTIMAL then return L["Always a skill point"] end
    if difficulty == Data.MEDIUM then return L["Usually a skill point"] end
    if difficulty == Data.EASY then return L["Sometimes a skill point"] end
    return L["No skill points"]
end

-- Skill-up range: the levels a recipe turns yellow, green and gray at, from the game's
-- data in SkillUps.lua (the client itself only tells the color right now). nil when
-- the recipe isn't listed.
function Data.Range(id)
    local v = ns.SkillUps and ns.SkillUps[id]
    if type(v) ~= "number" then return nil end
    local yellow, gray = math.floor(v / 1000), v % 1000
    return { yellow = yellow, green = math.floor((yellow + gray) / 2), gray = gray }
end

-- The color a range gives at a skill level.
function Data.ColorAt(range, skill)
    if skill < range.yellow then return Data.OPTIMAL end
    if skill < range.green then return Data.MEDIUM end
    if skill < range.gray then return Data.EASY end
    return Data.TRIVIAL
end

-- The skill the colors are measured from: the profession's level plus any bonus
-- (a racial one), as the shown skill.
function Data.Skill(prof)
    if type(prof) ~= "table" then return nil end
    return (prof.skill or 0) + (prof.bonus or 0)
end

-- The range of a recipe, only while it agrees with the color the client gives it: a
-- range the game moved since the data was read would otherwise show wrong numbers.
function Data.RangeFor(recipe, skill)
    local range = type(recipe) == "table" and Data.Range(recipe.id)
    if not (range and type(skill) == "number") then return nil end
    if Data.ColorAt(range, skill) ~= recipe.difficulty then return nil end
    return range
end

-- Chance (0 to 1) that one craft gives a skill point: always on orange, never on
-- gray, and in between the classic rule, (gray - skill) / (gray - yellow), so 100%
-- at yellow falling to 50% at green. nil when it can't be told honestly.
function Data.Chance(recipe, skill)
    if type(recipe) ~= "table" then return nil end
    if recipe.difficulty == Data.OPTIMAL then return 1 end
    if recipe.difficulty == Data.TRIVIAL then return 0 end
    local range = Data.RangeFor(recipe, skill)
    if not range then return nil end
    if range.gray <= range.yellow then return skill < range.yellow and 1 or 0 end
    return math.max(0, math.min(1, (range.gray - skill) / (range.gray - range.yellow)))
end

-- "72%", or nil.
function Data.ChanceText(chance)
    if type(chance) ~= "number" then return nil end
    return string.format("%d%%", math.floor(chance * 100 + 0.5))
end

-- Materials. A recipe's schematic never changes, so it's read once per recipe.

Data.schematics = {}

local function schematic(id)
    local s = Data.schematics[id]
    if s == nil then
        s = call("GetRecipeSchematic", id, false)
        s = type(s) == "table" and s or false
        Data.schematics[id] = s
    end
    return s or nil
end

local function have(itemID)
    if C_Item and type(C_Item.GetItemCount) == "function" then return num(C_Item.GetItemCount(itemID)) or 0 end
    return 0
end

-- { { itemID, name, icon, quality, need, have } } in the game's slot order. Slots the
-- crafting form hides (optional reagents) are skipped.
function Data.Materials(id)
    local s = schematic(id)
    local out = {}
    if not (s and type(s.reagentSlotSchematics) == "table") then return out end
    for _, slot in ipairs(s.reagentSlotSchematics) do
        local first = type(slot.reagents) == "table" and slot.reagents[1]
        local itemID = type(first) == "table" and num(first.itemID)
        if itemID and slot.hiddenInCraftingForm ~= true and slot.required ~= false then
            local name = C_Item and C_Item.GetItemNameByID and str(C_Item.GetItemNameByID(itemID))
            out[#out + 1] = { itemID = itemID, name = name, need = num(slot.quantityRequired) or 1, have = have(itemID),
                icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil,
                quality = C_Item and C_Item.GetItemQualityByID and num(C_Item.GetItemQualityByID(itemID)) or nil }
        end
    end
    return out
end

-- Short materials text ("2 Linen Cloth, 1 Coarse Thread"). Uncached names are left
-- out until they load.
function Data.MaterialsLine(mats)
    local bits = {}
    for _, m in ipairs(mats) do
        if m.name then bits[#bits + 1] = string.format(L["%d %s"], m.need, m.name) end
    end
    return table.concat(bits, ", ")
end

-- Quality of the crafted item (its name color on the recipe page).
function Data.OutputQuality(id)
    local s = schematic(id)
    local item = s and num(s.outputItemID)
    if item and C_Item and type(C_Item.GetItemQualityByID) == "function" then return num(C_Item.GetItemQualityByID(item)) end
    return nil
end

-- Recipes

local function recipeIDs()
    local ids = call("GetAllRecipeIDs")
    if type(ids) ~= "table" then ids = call("GetFilteredRecipeIDs") end
    return type(ids) == "table" and ids or {}
end

local function category(id, cache)
    if cache[id] ~= nil then return cache[id] end
    local c = call("GetCategoryInfo", id)
    local out = false
    if type(c) == "table" then out = { id = id, name = str(c.name) or "", order = num(c.uiOrder) or 0 } end
    cache[id] = out
    return out
end

-- Chat link for a recipe, the same way the game's list does it. Enchants make no item,
-- so their recipe info has no hyperlink; use C_TradeSkillUI.GetRecipeLink, else the
-- crafted item's link.
function Data.RecipeLink(recipe)
    if type(recipe) ~= "table" then return nil end
    return str(call("GetRecipeLink", recipe.id)) or recipe.link
end

-- Everything the list needs: { prof, sections = { { id, name, order, recipes } }, byID }.
-- Sections in the game's category order, recipes in the game's list order.
function Data.Read()
    local data = { prof = Data.Profession(), sections = {}, byID = {} }
    if not data.prof then return data end
    local inLine = TS() and type(TS().IsRecipeInSkillLine) == "function"
    local cats, bySection = {}, {}
    for _, id in ipairs(recipeIDs()) do
        local r = num(id) and call("GetRecipeInfo", id)
        if type(r) == "table" and r.learned == true and r.isDummyRecipe ~= true
            and (not inLine or call("IsRecipeInSkillLine", id, data.prof.id) ~= false) then
            local mats = Data.Materials(id)
            local recipe = { id = id, name = str(r.name) or "", icon = r.icon, link = str(r.hyperlink),
                difficulty = num(r.relativeDifficulty) or Data.TRIVIAL, skillUps = num(r.numSkillUps) or 0,
                canSkillUp = r.canSkillUp ~= false, enchant = r.isEnchantingRecipe == true, verb = str(r.alternateVerb),
                count = num(call("GetCraftableCount", id)) or 0, mats = mats, sub = Data.MaterialsLine(mats) }
            local cat = num(r.categoryID) and category(r.categoryID, cats) or nil
            local key = cat and cat.id or 0
            local section = bySection[key]
            if not section then
                section = { id = key, name = cat and cat.name ~= "" and cat.name or (OTHER or L["Other"]), order = cat and cat.order or 1e6, recipes = {} }
                bySection[key] = section
                data.sections[#data.sections + 1] = section
            end
            section.recipes[#section.recipes + 1] = recipe
            data.byID[id] = recipe
        end
    end
    table.sort(data.sections, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return data
end

-- Slot filter (Blacksmithing, Tailoring...). Uses the game's own filter, so the slots
-- match the profession (Camelot Professions.InitSlotsFilter). One slot at a time, like
-- Professions.SetInventorySlotFilter; the list keeps what the game's filtered list holds.

-- Slots this profession can filter by: { { index, name } }, or {} for none.
function Data.Slots()
    local out = {}
    local n = num(call("GetAllFilterableInventorySlotsCount")) or 0
    for i = 1, n do
        local name = str(call("GetFilterableInventorySlotName", i))
        if name then out[#out + 1] = { index = i, name = name } end
    end
    return out
end

-- Keep only slot index (nil = all slots).
function Data.SetSlot(index)
    call("ClearInventorySlotFilter")
    if index then call("SetInventorySlotFilter", index, true, true) end
end

-- Recipe ids currently in the game's filtered list, as a set.
function Data.Filtered()
    local ids = call("GetFilteredRecipeIDs")
    local set = {}
    for _, id in ipairs(type(ids) == "table" and ids or {}) do set[id] = true end
    return set
end

-- Can it still give a skill point (the "Skill-ups" chip)?
function Data.SkillsUp(recipe)
    return recipe.canSkillUp and recipe.difficulty ~= Data.TRIVIAL
end
