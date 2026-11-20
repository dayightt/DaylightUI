-- The Legacy window's options, as data.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy

local lookRows = DUI.Options.LookRows("frameStyle", nil)

ns.OPTIONS = { pages = {
    { id = "window", label = "Legacy",
      desc = "Your Legacy Points, their rewards, the challenges that earn them and the Legacy trees, in one window, in Daylight UI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "Daylight UI style Legacy window",
              desc = "The Legacy button shows Daylight UI's window: how far the next reward is, the challenges and the Legacy trees. Turn it off to use the game's own window, in Daylight UI's look. Each window also has a button to switch to the other." },
            { type = "slider", key = "scale", label = "Legacy window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
        } },
        { label = "Borders and background", items = lookRows },
    } },
} }
