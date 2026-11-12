-- The social window's options, as data.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Social window", nil, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Social",
      desc = "Your friends, recent allies, friend requests and the raid, in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "DaylightUI style social window", reload = true,
              desc = "Pressing O shows DaylightUI's window: who's online, people you played with, friend requests and your raid's groups. Turn it off to use the game's window." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            backRows[1], backRows[2],
        } },
    } },
} }
