-- Which profession window opens: Daylight UI's or the game's own, for players who
-- prefer it or use addons that build on the game's window. It's the "enabled"
-- setting, switched from either window's header and kept for next time. The two
-- windows trade places at once (after a fight when in one), with no reload.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L

local Swap = {}
ns.Swap = Swap

Swap.ICON = "ui-swap.png"
Swap.H = 20   -- the button on the game's window, as tall as its close button

-- Daylight UI's window is the one to use (DaylightMogul's, when that's in use,
-- leaves this off).
function Swap.Ours() return ns.Setting("enabled") == true and not DUI.craftMogul end

-- Picked from a button. Already Daylight UI's, with the game's lent for a while (the
-- SkillUp link): just take it back.
function Swap.Use(ours)
    local W = ns.Window
    if ours and Swap.Ours() then
        if W and W.follow then W.TakeBack() end
        return
    end
    DUI:Set("Professions", "enabled", ours == true)
end

local function game() return ns.Window and ns.Window.Game() end

-- On the game's window: shown while it's the player's pick, or while Daylight UI's
-- has handed it over for a while (the SkillUp link), so there's always a way back.
function Swap.Paint()
    local b = Swap.button
    if not b then return end
    b:SetShown(not DUI.craftMogul and (not Swap.Ours() or (ns.Window and ns.Window.handed) == true))
end

local function tip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    DUI.Tips.Clear()
    DUI.Tips.Title(L["Daylight UI window"])
    DUI.Tips.Text(L["Use Daylight UI's profession window from now on. The button in its header brings this one back."])
    DUI.Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

-- Made once the game's window exists, as its child so it shows and moves with it.
function Swap.Button()
    local g = game()
    if Swap.button or not g or DUI.craftMogul then return end
    local b = DUI.Widgets.Button(g, L["Daylight UI window"], Swap.H)
    b:SetWidth(math.ceil(b.text and b.text:GetStringWidth() or 120) + 24)
    local close = type(g.CloseButton) == "table" and g.CloseButton
    if close then b:SetPoint("RIGHT", close, "LEFT", -6, 0)
    else b:SetPoint("TOPRIGHT", g, "TOPRIGHT", -32, -2) end
    b:SetFrameLevel(g:GetFrameLevel() + 510)   -- above the game's pages (level 100)
    b:SetScript("OnClick", function() Swap.Use(true) end)
    b:HookScript("OnEnter", tip)
    b:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    Swap.button = b
    g:HookScript("OnShow", Swap.Paint)
    Swap.Paint()
end

-- The setting changed (here, from the options, or a profile switch): when it now
-- says the other window, they trade places.
function Swap.Apply()
    if DUI.craftMogul then return end
    local ours = Swap.Ours()
    if ours == Swap.was then return Swap.Paint() end
    Swap.was = ours
    DUI.craftOwnWindow = ours
    local W = ns.Window
    if ours and W and not W.frame then W.Build(ns.module) end
    if ns.Key and ns.Key.ready then ns.Key.Apply() end
    if W and W.follow then
        if ours then W.TakeBack() else W.GiveAway() end
    end
    Swap.Paint()
    if not ours then DUI.Fire("CraftGameWindow") end
end

function Swap.Init()
    Swap.was = Swap.Ours()
    Swap.Button()
    DUI.RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_Professions" then DUI.AfterCombat(Swap.Button, "craft:swap") end
    end)
end
