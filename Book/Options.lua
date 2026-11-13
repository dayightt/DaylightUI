-- The spellbook and talents window's options, as data.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Spellbook", nil, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Spellbook & talents",
      desc = "Your spellbook and talents in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "DaylightUI style spellbook window", reload = true,
              desc = "The spellbook and talent keys open DaylightUI's window. Turn it off to always use the game's window." },
            { type = "toggle", key = "fightBook", label = "Keep the spellbook in a fight", disabled = function(get) return get("enabled") == false end,
              desc = "In a fight the window stays: scroll it, switch tabs and click a spell to cast it. The search and section buttons wait until the fight ends. Turn it off to get the game's own book in a fight, where you can drag spells to your bars." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            backRows[1], backRows[2],
        } },
        { label = "Spellbook", items = {
            { type = "toggle", key = "hideLowRanks", invert = true, label = "Show lower spell ranks",
              desc = "The lower ranks of each spell sit under the highest, so you can cast an older rank for less mana. When off, the spellbook lists only the highest rank. The spellbook page has the same switch (Hide ranks)." },
            { type = "toggle", key = "masterSpot", label = "Where weapon masters stand", since = "1.7.2",
              desc = "On the Training page, a weapon skill's tooltip names each weapon master's city and district, not just their name." },
        } },
    } },
} }
