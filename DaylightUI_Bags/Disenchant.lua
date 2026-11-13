-- Spell buttons in the bag's tool row: Disenchant, and Comprehend Scroll for
-- characters who know it. Click one to get the targeting hand, then click an
-- item, same as casting from the spellbook.
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

-- One tool: spec { spell, icon (fallback), name (the secure button's), key
-- (the tool row button's field on the window), title (fallback name) }.
local function Tool(spec)
    local T = { SPELL = spec.spell, ICON = spec.icon, NAME = spec.name, KEY = spec.key }

    function T.Known()
        if type(IsPlayerSpell) == "function" then
            local ok, yes = pcall(IsPlayerSpell, T.SPELL)
            if ok then return yes == true end
        end
        local book = C_SpellBook and C_SpellBook.IsSpellKnown
        if type(book) == "function" then
            local ok, yes = pcall(book, T.SPELL)
            return ok and yes == true
        end
        return false
    end

    -- The spell's localized name, for the tooltip.
    function T.Title()
        local get = C_Spell and C_Spell.GetSpellName
        local name = type(get) == "function" and get(T.SPELL)
        return type(name) == "string" and name or spec.title
    end

    -- The spell's own icon, so the button looks like it does on the bars.
    function T.Icon()
        local get = C_Spell and C_Spell.GetSpellTexture
        if type(get) == "function" then
            local ok, tex = pcall(get, T.SPELL)
            if ok and (type(tex) == "number" or type(tex) == "string") then return tex end
        end
        return T.ICON
    end

    -- The tool row's visible button, or nil.
    local function visual()
        local f = ns.window
        return f and f[T.KEY]
    end

    -- The cast button has the mouse; forward hover, tooltip and sound to the visible one.
    local function hand(script)
        return function(row)
            local fn = row:GetScript(script)
            if fn then fn(row) end
        end
    end

    function T.Over()
        local b = visual()
        if b and T.caster then T.caster.Over(b, { type1 = "spell", spell = T.SPELL }) end
    end

    -- Shown only to characters who know the spell. The search box stretches to
    -- whichever tool is last.
    function T.Sync()
        local f, b = ns.window, visual()
        if not b then return end
        local known = T.Known()
        if known and b.icon then b.icon:SetTexture(T.Icon()) end
        b:SetShown(known)
        if not known and T.caster then T.caster.Hide() end
        ns.Window.LayoutTools(f)
    end

    function T.Register(f)
        T.caster = DUI.Win.Caster({ name = T.NAME,
            above = function() return ns.window end,
            enter = hand("OnEnter"), leave = hand("OnLeave"), post = hand("PostClick") })
        if f[T.KEY] then f[T.KEY]:HookScript("OnEnter", T.Over) end
        f:HookScript("OnHide", function() T.caster.Hide() end)
        DUI.RegisterEvent("SPELLS_CHANGED", T.Sync)
        T.Sync()
    end

    return T
end

ns.Disenchant = Tool({ spell = 13262, icon = "Interface\\Icons\\INV_Enchant_Disenchant",
    name = "DaylightUIBagDisenchant", key = "disenchantButton", title = L["Disenchant"] })

-- A WoW: Forever spell, learned from a trainer, cast on a scroll in the bags.
ns.Comprehend = Tool({ spell = 1296017, icon = "Interface\\Icons\\INV_Scroll_03",
    name = "DaylightUIBagComprehend", key = "comprehendButton", title = L["Comprehend Scroll"] })
