-- Spell buttons in the bag's tool row: Disenchant, Comprehend Scroll, Pick
-- Lock and Feed Pet, each for characters who know it. Click one to get the targeting hand, then click an
-- item, same as casting from the spellbook.
--
-- Casting needs a secure button, and a secure button inside the bag would keep
-- the bag from closing in combat. So the tool row shows a plain button for the
-- look, hover and tooltip, and while the mouse is over it the window kit's cast
-- button (Win.Caster: on UIParent, one strata above the bag, out of combat only)
-- sits on top. Craft/Make.lua's Stop button works the same way. At the bag's own
-- strata the plain icon kept the mouse.
--
-- Disenchant can also stay on: Shift-click its button and every item clicked
-- after that is disenchanted, until the button is clicked again, the bag
-- closes or a fight starts. A second cast button follows the pointer over the
-- items that can take it. It casts the spell and names the slot through the
-- secure template's target-bag and target-slot, so each click is still the
-- player's own. Shift-click needs nothing secure: an unmodified "type1" does
-- nothing on a modified click, the same way the spellbook's cast rows leave
-- Shift-click to link the spell.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

-- One tool: spec { spell, icon (a flat Media icon, like the rest of the row), name (the secure button's), key
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

    -- While the spell stays on, the button itself casts nothing: its plain
    -- click turns it off (T.Clicked from the tool row's own click).
    function T.Over()
        local b = visual()
        if not (b and T.caster) then return end
        if T.on then T.caster.Over(b, nil) else T.caster.Over(b, { type1 = "spell", spell = T.SPELL }) end
    end

    -- Shown only to characters who know the spell. The search box stretches to
    -- whichever tool is last.
    function T.Sync()
        local f, b = ns.window, visual()
        if not b then return end
        local known = T.Known()
        b:SetShown(known)
        if not known then
            if T.caster then T.caster.Hide() end
            T.SetOn(false)
        end
        ns.Window.LayoutTools(f)
    end

    -- Staying on (spec.keep = whether a slot's item can take the spell).

    T.on = false

    -- Whether the item in this bag slot can take the spell right now.
    function T.Takes(bag, slot, info)
        if not spec.keep or type(info) ~= "table" or info.isLocked then return false end
        return spec.keep(info) and not ns.Categories.Guarded(bag, slot, info)
    end

    -- The cast button lies over this slot.
    function T.Covers(slotButton)
        local b = T.slotCaster and T.slotCaster.button
        return b ~= nil and b:IsShown() and b.row == slotButton
    end

    -- The pointer came onto a slot of the bag window (Items.Dress): with the
    -- spell staying on and an item that takes it, the cast button goes over it.
    function T.SlotOver(slotButton)
        if not T.on or not T.slotCaster or T.Covers(slotButton) then return end
        local holder = slotButton:GetParent()
        local bag, slot = holder and holder:GetID(), slotButton:GetID()
        if type(bag) ~= "number" or type(slot) ~= "number"
            or not T.Takes(bag, slot, ns.Items.InfoAt(bag, slot)) then
            return T.SlotOff()
        end
        local b = T.slotCaster.Over(slotButton, { type1 = "spell", spell = T.SPELL })
        if not b then return end
        -- After the cast, the secure template hands the spell this slot's item.
        b:SetAttribute("target-bag", bag)
        b:SetAttribute("target-slot", slot)
    end

    function T.SlotOff(slotButton)
        local c = T.slotCaster
        if not (c and c.button and c.button.row) then return end
        if slotButton and c.button.row ~= slotButton then return end
        c.Hide()
    end

    -- The slot under the cast button changed (its item went, or locked while
    -- the spell takes it): off it, and the slot gets the pointer back.
    local function recheck()
        local b = T.slotCaster and T.slotCaster.button
        local slotButton = b and b.row
        if not slotButton then return end
        local holder = slotButton:GetParent()
        local bag, slot = holder and holder:GetID(), slotButton:GetID()
        if not T.Takes(bag, slot, ns.Items.InfoAt(bag, slot)) then T.SlotOff() end
    end

    local function glow(b, on)
        local W = DUI.Widgets
        if not b.keepGlow then
            if not on then return end
            b.keepGlow = CreateFrame("Frame", nil, b)
            b.keepGlow:SetAllPoints(b)
            b.keepGlow:SetFrameLevel(b:GetFrameLevel() + 2)
        end
        local style = W.ButtonGlowStyle()
        W.GlowAround(b.keepGlow, on and style ~= "none", { style = style, frame = b, inset = 0,
            thick = DUI.Pixel.Px(b, 2), parent = b.keepGlow, layer = "OVERLAY" })
    end

    -- Turn staying on on or off. It only starts out of a fight, with the bag
    -- open and the spell known.
    function T.SetOn(on)
        on = on == true
        if on and (InCombatLockdown() or not T.Known() or not (ns.window and ns.window:IsShown())) then return end
        if T.on == on then return end
        T.on = on
        local b = visual()
        if b then
            if b.hover then b.hover(b:IsMouseOver()) end
            glow(b, on)
        end
        if not on then T.SlotOff() end
        if b and (on or b:IsMouseOver()) then T.Over() end
        ns.Guard.Sync()
        ns.Window.MatchAll(ns.window)
    end

    -- A click on the tool row button: Shift-click turns staying on on, any
    -- click while it's on turns it off. A plain click while off has cast the
    -- spell once already (the cast button over it).
    function T.Clicked()
        if T.on then T.SetOn(false)
        elseif IsShiftKeyDown() then T.SetOn(true) end
    end

    local function keepRegister(f)
        local b = f[T.KEY]
        if b then
            -- Held in the accent while on, not only under the mouse.
            local paint = b.hover
            if paint then b.hover = function(over) paint(over or T.on) end end
        end
        T.slotCaster = DUI.Win.Caster({ name = T.NAME .. "Item",
            above = function() return ns.window end,
            enter = function(slotButton)
                local fn = slotButton:GetScript("OnEnter")
                if fn then DUI.SafeCall(fn, slotButton) end
            end,
            leave = function(slotButton)
                if slotButton:IsMouseOver() then return end
                local fn = slotButton:GetScript("OnLeave")
                if fn then DUI.SafeCall(fn, slotButton) end
            end,
            -- A modified click casts nothing; it still links or tries on the item.
            post = function(slotButton)
                if not (IsModifierKeyDown and IsModifierKeyDown() and HandleModifiedItemClick) then return end
                local holder = slotButton:GetParent()
                local info = ns.Items.InfoAt(holder:GetID(), slotButton:GetID())
                if info and info.hyperlink then DUI.SafeCall(HandleModifiedItemClick, info.hyperlink) end
            end })
        f:HookScript("OnHide", function() T.SetOn(false) end)
        -- Before the lockdown, while the cast buttons can still hide.
        DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() T.SetOn(false) end)
        DUI.RegisterEvent("ITEM_LOCK_CHANGED", recheck)
        DUI.RegisterEvent("BAG_UPDATE_DELAYED", recheck)
    end

    function T.Register(f)
        local post = hand("PostClick")
        T.caster = DUI.Win.Caster({ name = T.NAME,
            above = function() return ns.window end,
            enter = hand("OnEnter"), leave = hand("OnLeave"),
            post = function(row, button)
                post(row, button)
                if spec.keep then T.Clicked() end
            end })
        if f[T.KEY] then f[T.KEY]:HookScript("OnEnter", T.Over) end
        f:HookScript("OnHide", function() T.caster.Hide() end)
        if spec.keep then keepRegister(f) end
        DUI.RegisterEvent("SPELLS_CHANGED", T.Sync)
        T.Sync()
    end

    return T
end

-- Uncommon to epic weapons and armor (Enum.ItemClass Weapon 2, Armor 4).
local function disenchantable(info)
    local q = info.quality
    if type(q) ~= "number" or q < 2 or q > 4 then return false end
    local id = info.itemID or info.hyperlink
    local get = C_Item and C_Item.GetItemInfoInstant
    if id == nil or type(get) ~= "function" then return false end
    local classID = select(6, get(id))
    local E = Enum and Enum.ItemClass
    return classID == (E and E.Weapon or 2) or classID == (E and E.Armor or 4)
end

ns.Disenchant = Tool({ spell = 13262, icon = "ui-disenchant.png", keep = disenchantable,
    name = "DaylightUIBagDisenchant", key = "disenchantButton", title = L["Disenchant"] })

-- A WoW: Forever spell, learned from a trainer, cast on a scroll in the bags.
ns.Comprehend = Tool({ spell = 1296017, icon = "ui-micro-quests.png",
    name = "DaylightUIBagComprehend", key = "comprehendButton", title = L["Comprehend Scroll"] })

-- A rogue's Pick Lock, cast on a lockbox in the bags.
ns.PickLock = Tool({ spell = 1804, icon = "ui-lock.png",
    name = "DaylightUIBagPickLock", key = "pickLockButton", title = L["Pick Lock"] })

-- A hunter's Feed Pet, cast on food in the bags.
ns.FeedPet = Tool({ spell = 6991, icon = "ui-feed.png",
    name = "DaylightUIBagFeedPet", key = "feedPetButton", title = L["Feed Pet"] })
