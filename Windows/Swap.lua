-- Lets the player pick, from either window, between a Daylight UI window and the
-- game's own one it stands in for: for players who prefer the game's, or use
-- addons that build on it. The pick is the module's "enabled" setting, kept for
-- next time, and the two windows trade places at once (after a fight when in one).
--
--   local swap = Win.Swap({
--       scope = "Professions",                 -- settings scope; its "enabled" is the pick
--       game = function() return ProfessionsFrame end,  -- the game's window the link rides on
--       addon = "Blizzard_Professions",        -- optional: the load-on-demand addon that makes it
--       blocked = function() return false end, -- optional: true leaves the game's window to someone else
--       lent = function() return false end,    -- optional: the game's is shown for a while anyway
--       apply = function(ours) end,            -- the pick changed: trade places (out of combat)
--       take = function() end,                 -- optional: back from a lent game window
--   })
--   swap.Icon(f)    -- the header's swap icon, made before the window's tabs
--   swap.Apply()    -- from the module's OnSettingChanged
--   swap.Ours()     -- the Daylight UI window is the pick

local _, DUI = ...
local Win = DUI.Win
local L = DUI.L

Win.SWAP_ICON = "ui-swap.png"
Win.SWAP_GAP = 10   -- between the link on the game's window and its X

local function tipLink(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    DUI.Tips.Clear()
    DUI.Tips.Title(L["Daylight UI window"])
    DUI.Tips.Text(L["Use Daylight UI's window from now on. The button in its header brings this one back."])
    DUI.Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function hideTip(self)
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

function Win.Swap(spec)
    local s = { spec = spec }

    local function blocked() return spec.blocked ~= nil and spec.blocked() == true end
    local function game()
        local g = spec.game and spec.game()
        return type(g) == "table" and g or nil
    end

    function s.Ours() return DUI:Get(spec.scope, "enabled") == true and not blocked() end

    -- Already the Daylight UI window, with the game's lent for a while: just take it back.
    function s.Use(ours)
        if ours and s.Ours() then
            if spec.take then DUI.SafeCall(spec.take) end
            return
        end
        DUI:Set(spec.scope, "enabled", ours == true)
    end

    -- The link on the game's window shows while that window is the pick, or while
    -- the Daylight UI one has lent it out, so there's always a way back.
    function s.Paint()
        local b = s.link
        if not b then return end
        b:SetShown(not blocked() and (not s.Ours() or (spec.lent ~= nil and spec.lent() == true)))
    end

    -- Quiet words beside the game's X, as its child so it shows and moves with it.
    function s.Link()
        local g = game()
        if s.link or not g or blocked() then return end
        if g.IsForbidden and g:IsForbidden() then return end
        local b = DUI.Widgets.Link(g, DUI.Style.SIZE.small)
        b.SetLabel(L["Daylight UI window"])
        local close = type(g.CloseButton) == "table" and g.CloseButton
        if close then b:SetPoint("RIGHT", close, "LEFT", -Win.SWAP_GAP, 0)
        else b:SetPoint("TOPRIGHT", g, "TOPRIGHT", -32, -4) end
        b:SetFrameLevel(g:GetFrameLevel() + 510)   -- above the game's pages
        b:SetScript("OnClick", function() s.Use(true) end)
        b:HookScript("OnEnter", tipLink)
        b:HookScript("OnLeave", hideTip)
        s.link = b
        g:HookScript("OnShow", s.Paint)
        s.Paint()
    end

    -- The header's swap icon, left of the X (or of an icon already there).
    function s.Icon(f)
        local b = Win.HeaderIcon(f, Win.SWAP_ICON, L["Use the game's own window"], function() s.Use(false) end)
        f.swap = b
        return b
    end

    -- The setting changed (a button, the options, a profile switch): when it now
    -- says the other window, they trade places.
    function s.Apply()
        if blocked() then return end
        local ours = s.Ours()
        if ours == s.was then return s.Paint() end
        s.was = ours
        if InCombatLockdown() then
            s.was = not ours
            return DUI.AfterCombat(s.Apply, "swap:" .. spec.scope)
        end
        if spec.apply then DUI.SafeCall(spec.apply, ours) end
        s.Paint()
        if not ours then DUI.Fire("GameWindowPicked", spec.scope) end
    end

    s.was = s.Ours()
    s.Link()
    DUI.RegisterEvent("ADDON_LOADED", function(_, name)
        if spec.addon == nil or name == spec.addon then DUI.AfterCombat(s.Link, "swap:link:" .. spec.scope) end
    end)
    return s
end
