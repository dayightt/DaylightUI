-- Locked items (Alt-right-click, see Categories.lua) can't be sold or
-- disenchanted by accident. While a vendor is open or Disenchant is on the
-- cursor, a locked item's slot ignores clicks and drags. The game's click
-- handler is left alone, replacing it would taint every item use. The slot
-- just stops registering for clicks. The mouse still reaches it, so the tooltip
-- shows and Alt-right-click still opens the unlock menu (OnMouseUp in Items.Dress).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Guard = {}
ns.Guard = Guard

Guard.vendor = false
Guard.disenchanting = false

function Guard.Active() return Guard.vendor or Guard.disenchanting end

-- Updates one slot. Only called when its state changes.
function Guard.Apply(btn, info)
    local holder = btn:GetParent()
    if ns.Saved.Is(holder:GetID()) then return end      -- saved copies (viewer) can't be sold anyway
    local want = Guard.Active() and info ~= nil and ns.Categories.IsLocked(info.itemID)
    if want == (btn.dluiGuarded == true) then return end
    btn.dluiGuarded = want or nil
    if want then
        btn:RegisterForClicks()
        btn:RegisterForDrag()
    else
        -- Same as ContainerFrameItemButtonMixin:OnLoad.
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")
    end
end

function Guard.Sync()
    for _, f in ipairs({ ns.window or false, ns.Bank and ns.Bank.window or false }) do
        if f and f.set then
            for _, s in ipairs(f.set.Slots()) do
                Guard.Apply(s.button, ns.Items.InfoAt(s.bag, s.button:GetID()))
            end
        end
    end
end

-- Click on a guarded slot: open the menu, or explain why nothing happened.
function Guard.Refused(btn, button)
    if button == "RightButton" and IsAltKeyDown and IsAltKeyDown() then return ns.Categories.Menu(btn) end
    local info = ns.Items.InfoAt(btn:GetParent():GetID(), btn:GetID())
    if info then DUI.Print(string.format(L["%s is locked. Alt-right-click it to unlock it."], info.hyperlink or "")) end
end

local function disenchanting()
    local is = C_Spell and C_Spell.IsCurrentSpell
    if type(is) ~= "function" then return false end
    local ok, on = pcall(is, ns.Disenchant.SPELL)
    return ok and on == true
end

local function set(key, on)
    if Guard[key] == on then return end
    Guard[key] = on
    Guard.Sync()
end

function Guard.Register()
    DUI.RegisterEvent("MERCHANT_SHOW", function() set("vendor", true) end)
    DUI.RegisterEvent("MERCHANT_CLOSED", function() set("vendor", false) end)
    -- Fires on every cast. Only touch the slots when the answer changes.
    DUI.RegisterEvent("CURRENT_SPELL_CAST_CHANGED", function() set("disenchanting", disenchanting()) end)
end
