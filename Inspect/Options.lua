-- The inspect window's options, as data.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect

local lookRows = DUI.Options.LookRows("frameStyle", nil)

ns.OPTIONS = { pages = {
    { id = "window", label = "Inspect",
      desc = "Another player's gear and talents in one window, in Daylight UI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "Daylight UI style inspect window",
              desc = "Inspecting a player opens Daylight UI's window, with their gear and talents. Turn it off to use the game's own window, in Daylight UI's look. Each window also has a button to switch to the other." },
            { type = "slider", key = "scale", label = "Inspect window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            { type = "toggle", key = "missingEnchants", label = "Missing enchants",
              desc = "An amber No enchant line under their gear that could carry an enchant but has none." },
            { type = "toggle", key = "lastNames.inspect", label = "First and last names",
              desc = "The window's title shows the player's last name after their first name.",
              get = function() return DUI:Get("general", "lastNames.inspect") == true end,
              set = function(v) DUI:Set("general", "lastNames.inspect", v) end,
              default = function() return true end },
        } },
        { label = "Borders and background", items = lookRows },
    } },
} }
