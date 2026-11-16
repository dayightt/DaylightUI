-- Registers the social window with the core. It lives in the core addon and is switched
-- by the "enabled" setting, from the options or either window (Social.swap).

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social

DUI:RegisterModule("Social", {
    label = "Social",
    order = 131,
    section = "QoL", pageOrder = 135, windowCard = true,   -- a card on Extras > Windows
    ns = ns,
    parts = { "Data", "Detail", "Friends", "Allies", "Requests", "Raid", "Window" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        ns.Window.SwapInit()
        if ns.Window.Ours() then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function()
        if ns.Window.swap then ns.Window.swap.Apply() end
        ns.Window.Apply()
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
