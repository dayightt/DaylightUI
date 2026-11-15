-- Registers the bag with the DaylightUI core.

local _, ns = ...

DaylightUI:RegisterModule("Bags", {
    -- What each file defines. If a file goes missing after an update, the module
    -- turns itself off with one line in chat (tests/test_guards.lua checks this list).
    ns = ns,
    parts = { "Items", "Plugins", "Search", "Junk", "Repair", "Bags", "Layout", "Stack", "Keep", "Swap", "Window", "Move", "Disenchant", "Guard", "Prep",
               "Slots", "Bank", "Saved", "Viewer", "Currency", "MoneyRoll", "Categories", "OpenClose" },
    label = "Bags",
    order = 125,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod) ns.Build(mod) end,
    OnSettingChanged = function(mod) ns.Refresh(mod) end,
    OnStyleChanged = function(mod) ns.Refresh(mod) end,
})
