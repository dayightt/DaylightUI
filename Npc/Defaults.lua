-- Default settings for the NPC window.

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc

ns.DEFAULTS = {
    enabled = true,      -- replaces the gossip and quest frames; needs a reload
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
    look = "window",     -- "window" or "immersive" (a card on the side, rest of the UI faded)
    typeText = false,    -- immersive: the NPC's words appear letter by letter
    zoom = true,         -- immersive: camera moves over the shoulder toward the NPC
    fadeUI = true,       -- immersive: fade the rest of the UI during the talk
    vendor = true,       -- vendor page in this window; needs a reload
    trainer = true,      -- trainer page in this window; needs a reload
    keys = true,         -- 1-9 pick a line, Enter/Space continue, Escape goes back
    acceptKey = "space", -- "space", "enter" or "both" (Enter alone would also open chat)
    popupKeys = true,    -- Enter accepts the game's yes/no popups out of combat, Space too on innkeeper ones
}
