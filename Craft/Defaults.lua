-- Default settings for the profession window.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

ns.DEFAULTS = {
    enabled = true,   -- Daylight UI's window instead of the game's; switched from either window
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
    rarityNames = false,   -- color recipe names by item quality instead of skill-up color
    skillUps = false,      -- each recipe's skill-up chance, and its range on the recipe page
    profit = true,         -- what a recipe costs and sells for, from the Auction House's prices
}
