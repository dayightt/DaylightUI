-- Registers the Legacy window with the core. It lives in the core addon and is switched
-- by the "enabled" setting, read at login.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy

DUI:RegisterModule("Legacy", {
    label = "Legacy",
    order = 132,
    section = "QoL", pageOrder = 136, windowCard = true,   -- a card on Extras > Windows
    ns = ns,
    parts = { "Data", "Progress", "Challenges", "Trees", "Window" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        DUI.legacyOwnWindow = mod.db.enabled == true
        if ns.Window and mod.db.enabled == true then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
