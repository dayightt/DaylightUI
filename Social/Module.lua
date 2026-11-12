-- Registers the social window with the core. It lives in the core addon and is switched
-- by the "enabled" setting, read at login.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social

DUI:RegisterModule("Social", {
    label = "Social",
    order = 131,
    section = "QoL", pageOrder = 135, windowCard = true,   -- a card on Extras > Windows
    ns = ns,
    parts = { "Data", "Friends", "Allies", "Requests", "Raid", "Window" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        DUI.socialOwnWindow = mod.db.enabled == true
        if ns.Window and mod.db.enabled == true then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
