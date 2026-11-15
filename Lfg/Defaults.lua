-- Default settings for the group finder window.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg

ns.DEFAULTS = {
    enabled = true,   -- Daylight UI's window instead of the game's; switched from either window
    scale = 1,
    activitySort = "level",   -- List yourself: sort activities by suggested level ("level") or A to Z ("name")
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
}
