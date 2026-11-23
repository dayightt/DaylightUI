-- Default settings for the inspect window.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect

ns.DEFAULTS = {
    enabled = true,   -- Daylight UI's window instead of the game's; switched from either window
    scale = 1,
    missingEnchants = false, -- an amber "No enchant" under their gear that could have one
    frameStyle = DaylightUI.Style.LookDefaults(), -- borders, shadows and background, or General's (Style.LookOf)
}

-- Window pages, registered by the page files (Gear, Talents) before Window.lua builds
-- them: { id, text, Build(page), Fill(page), w?, h?, pieces? }.
ns.PAGES = ns.PAGES or {}
