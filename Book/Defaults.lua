-- Default settings for the spellbook and talents window.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

ns.DEFAULTS = {
    enabled = true,       -- read at login, so changing it needs a reload
    scale = 1,
    windowAlphaOwn = false,   -- false: use the shared General windowAlpha
    windowAlpha = 0.85,
    hideLowRanks = true,  -- the spellbook lists only each spell's top rank
    masterSpot = false,   -- a weapon master's city and district in the training tooltip
    fightBook = true,     -- keep this window in combat (Fight.lua); false hands over to the game's book, which allows dragging spells
}
