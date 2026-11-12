-- Registers the info panel with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("InfoPanel", {
    -- Every part the files define. If one is missing after an update, the
    -- module turns itself off with a single line in chat.
    ns = ns,
    parts = { "Panel", "XP", "RepBar", "XPGain", "Rows", "MeterHeader", "Meter", "ThreatView", "ThreatMeter", "DeathLog", "Breakdown", "BreakdownWindow", "Summary", "Windows", "MeterFrame", "Report", "Minimap", "Drawer", "DataTexts", "DataBar", "Broker", "Tracker", "MeterOptions" },
    label = "Info Panel",
    order = 120,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod) ns.Build(mod) end,
    OnSettingChanged = function(mod) ns.Refresh(mod) end,
    OnStyleChanged = function(mod) ns.Refresh(mod) end,
})
