-- Registers the buff and debuff bars with the DaylightUI core.

local _, BL = ...
local DUI = DaylightUI

-- "settings.debuff.iconSize" -> "iconSize", "debuff".
local function settingOf(path)
    local key = string.match(path, "^settings%.debuff%.(.+)$")
    if key then return key, "debuff" end
    return string.match(path, "^settings%.(.+)$"), nil
end

DUI:RegisterModule(BL.MODULE, {
    -- The module's parts, so a file missing after an update disables the
    -- module with one line in chat instead of erroring.
    ns = BL,
    parts = { "Categories", "Data", "Classify", "Auras", "Spells", "Layout", "Scan", "Preview", "Widgets",
               "Bar", "Feel", "DebuffBar", "Private", "Reminder", "EdgeEditor" },
    label = "Buffs & Debuffs",
    order = 130,
    defaults = BL.DEFAULTS,
    options = BL.OPTIONS,
    OnEnable = function(mod)
        DUI.WarnIfLoaded("BuffLedger", "BuffLedger", "buff bars")
        BL.UseModule(mod)
        BL.BuildBars()
        DUI.SafeCall(BL.Private.Build)
    end,
    OnSettingChanged = function(_, path)
        local key, scope = settingOf(path)
        if not key then return end
        -- The anchors follow the icon size: room for the time above the buffs'
        -- first row, and the debuffs' first row resting on the panel.
        if key == "iconSize" then BL.PlaceAnchor() end
        BL.Fire("SETTINGS_CHANGED", key, scope)
    end,
    OnStyleChanged = function()
        -- New font or border: restyle every button.
        BL.EachBar(function(bar) bar:Restyle(); bar:ApplyBackground() end)
    end,
})
