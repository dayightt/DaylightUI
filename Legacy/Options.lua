-- The Legacy window's options, as data.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Legacy window", nil, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Legacy",
      desc = "Your Legacy Points, their rewards, the challenges that earn them and the Legacy trees, in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "DaylightUI style Legacy window", reload = true,
              desc = "The Legacy button shows DaylightUI's window: how far the next reward is, the challenges and the Legacy trees. Turn it off to use the game's window." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            backRows[1], backRows[2],
        } },
    } },
} }
