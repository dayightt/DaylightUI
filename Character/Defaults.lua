-- Default settings for the character window.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

ns.DEFAULTS = {
    enabled = true,       -- replaces the game's window; read at login, so changing it needs a reload
    names = true,         -- item names beside the icons. Off gives the model the room
    itemLevel = true,     -- the dim line under each name
    scale = 1,
    windowAlphaOwn = false,   -- off follows the General windowAlpha
    windowAlpha = 0.85,
    repairAt = 0.25,      -- a slot at or under this much durability says "Repair soon"
    gradient = true,      -- gradient bars, or plain fills when off
    statsOpen = "all",    -- "all", or "auto" for Attributes plus your class and spec's group
    zebra = false,        -- every other row on a faint stripe (stats, lists)
    glow = true,          -- the soft glow behind the model
    footColors = true,    -- footer item level in your gear's quality, durability from green to red
    colors = {
        headMode = "accent",      -- accent | group (per-group colors below) | class | gradient | custom
        head = { 1, 1, 1 },
        attributes = { 1, 0.82, 0.35 },
        attack = { 1, 0.48, 0.38 },
        ranged = { 0.55, 0.86, 0.42 },
        spell = { 0.72, 0.58, 1 },
        defense = { 0.45, 0.7, 1 },
        resistances = { 0.38, 0.85, 0.8 },
        lineMode = "tab",         -- tab (same as the tab underline) | accent | class | gradient | custom
        line = { 0.78, 0.78, 0.8 },
        glowMode = "accent",      -- accent | class | gradient | custom
        glow = { 0.45, 0.6, 1 },
        tabMode = "accent",       -- the open tab's underline: accent | gradient | class | custom
        tab = { 1, 1, 1 },
    },
}
