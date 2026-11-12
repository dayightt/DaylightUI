-- Default settings for the Legacy window.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy

ns.DEFAULTS = {
    enabled = true,   -- replaces the game's Legacy window; needs a reload
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
}
