-- Default settings for the profession window.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

ns.DEFAULTS = {
    enabled = true,   -- replaces the game's crafting window; needs a reload
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
    rarityNames = false,   -- color recipe names by item quality instead of skill-up color
}
