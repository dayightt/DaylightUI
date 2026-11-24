-- Registers the character window with the core. It ships inside the core
-- addon, so the "enabled" setting is its switch: Daylight UI's window or the
-- game's own, picked from the options or a button on either window.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

-- The two windows trade places (out of combat): the game's comes back as itself,
-- or goes out of sight again with this one open on its page.
local function swap(ours)
    if not ours then return ns.Follow.Release() end
    if not ns.window then ns.Window.Build(ns.module) end
    ns.Follow.Reclaim()
end

DUI:RegisterModule("Character", {
    label = "Character",
    order = 124,
    section = "QoL", pageOrder = 110,   -- its options page sits under Extras
    ns = ns,
    parts = { "Colors", "Gear", "Stats", "StatText", "Window", "Follow", "Slots", "Model", "CharacterPage", "PetPage", "Menus", "Sets", "List", "Reputation", "Skills", "PvP", "Statistics", "Currency" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        ns.Follow.given = mod.db.enabled == false
        ns.swap = DUI.Win.Swap({
            scope = "Character",
            game = ns.Follow.Game,
            apply = swap,
        })
        if not ns.Follow.given then ns.Window.Build(mod) end
        -- Shown as itself (picked, or lent for a currency transfer), the game's
        -- window gets its slots over the model.
        local g = ns.Follow.Game()
        if g and g.HookScript then g:HookScript("OnShow", ns.Slots.Lift) end
    end,
    OnSettingChanged = function(_, path)
        ns.swap.Apply()
        if ns.window then ns.Window.Apply(path) end
    end,
    OnStyleChanged = function()
        if ns.window then ns.Window.Apply() end
    end,
})
