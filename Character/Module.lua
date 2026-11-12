-- Registers the character window with the core. It ships inside the core
-- addon, so the "enabled" setting (read at login) is its on/off switch.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

DUI:RegisterModule("Character", {
    label = "Character",
    order = 124,
    section = "QoL", pageOrder = 110,   -- its options page sits under Extras
    ns = ns,
    parts = { "Colors", "Gear", "Stats", "StatText", "Window", "Follow", "Slots", "Model", "CharacterPage", "PetPage", "Menus", "List", "Reputation", "Skills", "PvP", "Statistics", "Currency" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        if ns.Window and mod.db.enabled ~= false then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function(_, path)
        if ns.window then ns.Window.Apply(path) end
    end,
    OnStyleChanged = function()
        if ns.window then ns.Window.Apply() end
    end,
})
