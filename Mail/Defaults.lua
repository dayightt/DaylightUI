-- Default settings for the mailbox window.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail

ns.DEFAULTS = {
    -- Daylight UI's mailbox instead of the game's; switched from either window.
    enabled = true,
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
    ticks = false,            -- a tick on each letter, so Collect takes only the ticked ones
}
