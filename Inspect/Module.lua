-- Registers the inspect window with the core. It lives in the core addon and is switched
-- by the "enabled" setting, read at login.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect

DUI:RegisterModule("Inspect", {
    label = "Inspect",
    order = 127,
    section = "QoL", pageOrder = 131, windowCard = true,   -- a card on Extras > Windows
    ns = ns,
    parts = { "Model", "GearPage", "TalentsPage", "Window" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        if ns.Window and mod.db.enabled == true then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
