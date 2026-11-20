-- Default settings for the mailbox window.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail

ns.DEFAULTS = {
    -- Daylight UI's mailbox instead of the game's; switched from either window.
    enabled = true,
    scale = 1,
    frameStyle = DaylightUI.Style.LookDefaults(), -- borders, shadows and background, or General's (Style.LookOf)
    ticks = false,            -- a tick on each letter, so Collect takes only the ticked ones
}
