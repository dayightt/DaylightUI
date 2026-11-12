-- Registers the spellbook and talents window with the core. It ships inside
-- the core addon, so it is switched by the "enabled" setting, read at login.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

DUI:RegisterModule("Book", {
    label = "Spellbook",
    order = 126,
    section = "QoL", pageOrder = 130, windowCard = true,   -- shows as a card on Extras > Windows
    ns = ns,
    parts = { "TalentData", "Arrows", "Spend", "Talents", "LoadoutString", "Builds", "SpellData", "Cast", "Spells", "Training", "Fight", "Window" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        DUI.bookOwnWindow = mod.db.enabled == true
        if ns.Window and mod.db.enabled == true then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
