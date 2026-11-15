-- Default settings for the social window.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social

ns.DEFAULTS = {
    enabled = true,   -- replaces the game's social window; needs a reload
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
    friendFactions = false,   -- a faction banner by each friend's character
    friendDim = false,        -- dim friends in another game or on another ruleset
    friendChips = false,      -- All / Same game / Online chips over the friends list
}
