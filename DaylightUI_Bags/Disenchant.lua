-- Disenchant button in the bag's tool row, for characters who know Disenchant.
-- Click it to get the targeting hand, then click an item, same as casting from
-- the spellbook.
--
-- Casting needs a secure button, and a secure button inside the bag would keep
-- the bag from closing in combat. So the tool row shows a plain button for the
-- look, hover and tooltip, and while the mouse is over it the window kit's cast
-- button (Win.Caster: on UIParent, one strata above the bag, out of combat only)
-- sits on top. Craft/Make.lua's Stop button works the same way. At the bag's own
-- strata the plain icon kept the mouse.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local DE = {}
ns.Disenchant = DE

DE.SPELL = 13262
DE.ICON = "ui-disenchant.png"
DE.NAME = "DaylightUIBagDisenchant"

function DE.Known()
    if type(IsPlayerSpell) == "function" then
        local ok, yes = pcall(IsPlayerSpell, DE.SPELL)
        if ok then return yes == true end
    end
    local book = C_SpellBook and C_SpellBook.IsSpellKnown
    if type(book) == "function" then
        local ok, yes = pcall(book, DE.SPELL)
        return ok and yes == true
    end
    return false
end

-- The spell's localized name, for the tooltip.
function DE.Title()
    local get = C_Spell and C_Spell.GetSpellName
    local name = type(get) == "function" and get(DE.SPELL)
    return type(name) == "string" and name or L["Disenchant"]
end

-- The tool row's visible button, or nil.
local function visual()
    local f = ns.window
    return f and f.disenchantButton
end

-- The cast button has the mouse; forward hover, tooltip and sound to the visible one.
local function hand(script)
    return function(row)
        local fn = row:GetScript(script)
        if fn then fn(row) end
    end
end

function DE.Over()
    local b = visual()
    if b and DE.caster then DE.caster.Over(b, { type1 = "spell", spell = DE.SPELL }) end
end

-- Shown only to characters who know the spell. The search box stretches to
-- whichever tool is last.
function DE.Sync()
    local f, b = ns.window, visual()
    if not b then return end
    local known = DE.Known()
    b:SetShown(known)
    if not known and DE.caster then DE.caster.Hide() end
    ns.Window.LayoutTools(f)
end

function DE.Register(f)
    DE.caster = DUI.Win.Caster({ name = DE.NAME,
        above = function() return ns.window end,
        enter = hand("OnEnter"), leave = hand("OnLeave"), post = hand("PostClick") })
    if f.disenchantButton then f.disenchantButton:HookScript("OnEnter", DE.Over) end
    f:HookScript("OnHide", function() DE.caster.Hide() end)
    DUI.RegisterEvent("SPELLS_CHANGED", DE.Sync)
    DE.Sync()
end
