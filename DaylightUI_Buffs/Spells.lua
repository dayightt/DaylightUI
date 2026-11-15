-- Spells: the bridge between names and spell IDs. Categories are decided
-- by name (Classify.lua); the client's aura container filters by spell
-- ID. Whenever aura data is readable (out of combat) every buff's spell
-- ID is recorded against its name, so the container's per-category
-- filters can be rebuilt from ids alone - including in combat, when the
-- names can no longer be read.

local _, BL = ...
local DUI = DaylightUI

local Spells = {}
BL.Spells = Spells

-- Records id -> name for every readable aura entry and lets the
-- classifier learn caster classes on the way. Returns true when a new
-- id was seen.
function Spells.Learn(entries)
    local changed = false
    for _, e in ipairs(entries or {}) do
        if e.kind == "aura" then
            local id = BL.Plain(e.spellId)
            local name = BL.Plain(e.name)
            if type(id) == "number" and type(name) == "string" and name ~= "" then
                if BL.DB.spells[id] ~= name then
                    BL.DB.spells[id] = name
                    changed = true
                end
                BL.Classify.Resolve(e)
            end
        end
    end
    if changed then BL.Fire("SPELLS_CHANGED") end
    return changed
end

function Spells.Name(spellId)
    return BL.DB.spells[spellId]
end

-- One shared probe table for every query (Resolve only reads it).
local probe = { kind = "aura" }
function Spells.CategoryOf(spellId)
    local name = BL.DB.spells[spellId]
    if not name then return "other" end
    probe.name = name
    return BL.Classify.Resolve(probe)
end

-- { byCategory = { [categoryId] = { [spellId] = true } },
--   known = { [spellId] = true },          every id ever seen
--   categorized = { [spellId] = true } }   ids that belong to a category other than Other
-- Every existing category has a set, empty or not. The Other group is
-- "everything except categorized", so unknown and Other-assigned buffs
-- both land there. category: [spellId] = its category, for every known id.
-- Built once and kept until its inputs change: learned spells, overrides and
-- learned classes, categories (each change fires one of the events below). The
-- tables are shared, so never modify them.
local sets, setsDB
function Spells.Sets()
    if sets and setsDB == BL.DB then return sets end
    local byCategory, known, categorised, category = {}, {}, {}, {}
    for id in pairs(BL.DB.categories) do byCategory[id] = {} end
    for spellId in pairs(BL.DB.spells) do
        known[spellId] = true
        local cat = Spells.CategoryOf(spellId)
        category[spellId] = cat
        byCategory[cat] = byCategory[cat] or {}
        byCategory[cat][spellId] = true
        if cat ~= "other" then categorised[spellId] = true end
    end
    -- Plugins' categories (DaylightUI.API: me.AddBuffCategory) hold their spells by
    -- id, so the client sorts them in a fight too. A buff the player moved by
    -- hand stays where they put it.
    for _, pc in ipairs(BL.PluginCategories()) do
        local id = pc.category
        if id and BL.DB.categories[id] then
            byCategory[id] = byCategory[id] or {}
            for _, sid in ipairs(pc.spells) do
                local name = BL.DB.spells[sid]
                if not (name and BL.DB.overrides[name]) then
                    local was = category[sid]
                    if was and byCategory[was] then byCategory[was][sid] = nil end
                    byCategory[id][sid] = true
                    category[sid], known[sid], categorised[sid] = id, true, true
                end
            end
        end
    end
    sets = { byCategory = byCategory, known = known, categorised = categorised, category = category }
    setsDB = BL.DB
    return sets
end

local function dropSets() sets = nil end

-- Plugins' categories: each one's own category (made once in the player's
-- list, marked with the plugin's key, then theirs to move, recolor or hide)
-- and its spell ids. Kept by the API, never saved.
local NONE = {}
function BL.PluginCategories()
    local R = DUI.APIReport
    return type(R) == "table" and R.BuffCategories and R.BuffCategories() or NONE
end
function BL.TakePluginCategories()
    if not BL.DB then return end
    for _, pc in ipairs(BL.PluginCategories()) do
        local found
        for id, rec in pairs(BL.DB.categories) do
            if rec.plugin == pc.key then found = id end
        end
        if not found then
            found = BL.Categories.Create(pc.label, pc.color)
            BL.DB.categories[found].plugin = pc.key
        end
        pc.category = found
    end
    sets = nil
    BL.Fire("CATEGORIES_CHANGED")
end
BL.On("DB_READY", function() DUI.SafeCall(BL.TakePluginCategories) end)
DUI.On("BuffCategoriesChanged", function() DUI.SafeCall(BL.TakePluginCategories) end)
BL.On("SPELLS_CHANGED", dropSets)
BL.On("OVERRIDES_CHANGED", dropSets)
BL.On("CATEGORIES_CHANGED", dropSets)
BL.On("DB_READY", dropSets)

