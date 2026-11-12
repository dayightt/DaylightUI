-- Default settings for the inspect window.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect

ns.DEFAULTS = {
    enabled = true,   -- replaces the game's inspect window; needs a reload
    scale = 1,
    windowAlphaOwn = false,   -- off: follows the general window opacity
    windowAlpha = 0.85,
}

-- Window pages, registered by the page files (Gear, Talents) before Window.lua builds
-- them: { id, text, Build(page), Fill(page), w?, h?, pieces? }.
ns.PAGES = ns.PAGES or {}
