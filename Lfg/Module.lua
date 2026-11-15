-- Registers the group finder window with the core. It lives in the core addon and is
-- switched by the "enabled" setting, read at login.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg

DUI:RegisterModule("GroupFinder", {
    label = "Group Finder",
    order = 129,
    section = "QoL", pageOrder = 133, windowCard = true,   -- a card on Extras > Windows
    ns = ns,
    parts = { "Data", "Rows", "Browse", "Listing", "Who", "Window" },
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
