-- Registers the tooltips with the DaylightUI core.

local _, ns = ...

-- With PrettyTooltip drawing tooltips this module stands down, except for the
-- health bar its panels borrow (Tip.BarOnly).
local function off() return DaylightUI.PrettyAside.Draws() end

DaylightUI:RegisterModule("Tooltip", {
    -- The module's parts, so a file missing after an update disables the
    -- module with one line in chat instead of erroring.
    ns = ns,
    parts = { "Tooltip" },
    label = "Tooltips",
    order = 140,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        if off() then ns.Tooltip.BarOnly(mod) else ns.Tooltip.Build(mod) end
    end,
    OnSettingChanged = function(mod) if not off() then ns.Tooltip.Refresh(mod) end end,
    OnStyleChanged = function(mod) if not off() then ns.Tooltip.Refresh(mod) end end,
})
