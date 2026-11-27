-- Default settings for the spellbook and talents window.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

ns.DEFAULTS = {
    enabled = true,       -- Daylight UI's window instead of the game's; switched from either window
    scale = 1,
    frameStyle = DaylightUI.Style.LookDefaults(), -- borders, shadows and background, or General's (Style.LookOf)
    hideLowRanks = true,  -- the spellbook lists only each spell's top rank
    hidePassives = false, -- the spellbook leaves out passive spells (the game's book menu has it, off)
    masterSpot = false,   -- a weapon master's city and district in the training tooltip
    fightBook = true,     -- keep this window in combat (Fight.lua); false hands over to the game's book, which allows dragging spells
}
