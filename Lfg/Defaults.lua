-- Default settings for the group finder window.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg

ns.DEFAULTS = {
    enabled = true,   -- replaces the game's group finder; needs a reload
    scale = 1,
    activitySort = "level",   -- List yourself: sort activities by suggested level ("level") or A to Z ("name")
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
}
