-- Registers the quality-of-life helpers with the DaylightUI core.

local _, ns = ...

-- Each feature file adds itself here with an Enable() and a Refresh().
ns.features = ns.features or {}

local function each(method, mod)
    for _, feature in ipairs(ns.features) do
        if type(feature[method]) == "function" then feature[method](mod) end
    end
end

DaylightUI:RegisterModule("QoL", {
    -- What its files define, so a file missing after an update turns the
    -- module off with one line in chat instead of a pile of errors.
    ns = ns,
    parts = { "Delete", "Loot", "Trainer", "Quests", "Gossip", "Cinematics", "Tutorials", "AfkFacts", "Afk", "Camera", "Sparkles", "Glow", "Tracking", "Errors", "ErrorText", "Flight", "LootFeed", "LevelUp", "ZoneTitle", "RepBanner", "Campfire", "Fishing", "CursorRing" },
    label = "Quality of Life",
    order = 150,
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod) each("Enable", mod) end,
    OnSettingChanged = function(mod) each("Refresh", mod) end,
})
