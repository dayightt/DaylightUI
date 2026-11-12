-- Default settings for the mailbox window.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail

ns.DEFAULTS = {
    -- Replaces the game's mailbox window; needs a reload.
    enabled = true,
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
}
