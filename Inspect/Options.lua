-- The inspect window's options, as data.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Inspect window", nil, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Inspect",
      desc = "Another player's gear and talents in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "DaylightUI style inspect window", reload = true,
              desc = "Inspecting a player opens DaylightUI's window, with their gear and talents. Turn it off to use the game's window." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            backRows[1], backRows[2],
            { type = "toggle", key = "lastNames.inspect", label = "First and last names",
              desc = "The window's title shows the player's last name after their first name.",
              get = function() return DUI:Get("general", "lastNames.inspect") == true end,
              set = function(v) DUI:Set("general", "lastNames.inspect", v) end },
        } },
    } },
} }
