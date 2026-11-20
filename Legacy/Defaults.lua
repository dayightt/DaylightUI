-- Default settings for the Legacy window.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy

ns.DEFAULTS = {
    enabled = true,   -- Daylight UI's window instead of the game's; switched from either window
    scale = 1,
    frameStyle = DaylightUI.Style.LookDefaults(), -- borders, shadows and background, or General's (Style.LookOf)
}
