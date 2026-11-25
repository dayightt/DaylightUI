-- Registers Proc Alerts with the DaylightUI core.

local _, ns = ...
local DUI = DaylightUI

DUI:RegisterModule("Procs", {
    ns = ns,
    parts = { "Data", "Alerts", "Flares", "Engine", "Game", "Sample", "Options" },
    label = "Proc Alerts",
    order = 135,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.Flares.Build(mod)
        ns.Engine.Start(mod)
        ns.Game.Setup()
    end,
    -- A setting change is acted on at once (Engine.lua listens to SettingChanged):
    -- only Daylight UI's own unprotected frames move, so it needn't wait out a fight.
    OnStyleChanged = function() ns.Flares.Repaint() end,
})
