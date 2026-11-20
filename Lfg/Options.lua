-- The group finder window's options, as data.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg

local lookRows = DUI.Options.LookRows("frameStyle", nil)

ns.OPTIONS = { pages = {
    { id = "window", label = "Group Finder",
      desc = "Finding a group, listing yourself and the who list, in one window, in Daylight UI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "Daylight UI style group finder window",
              desc = "Opening the group finder shows Daylight UI's window: groups to join, listing yourself, and who's about. Turn it off to use the game's own window, in Daylight UI's look. Each window also has a button to switch to the other." },
            { type = "slider", key = "scale", label = "Group finder scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            { type = "dropdown", key = "activitySort", label = "Sort activities by", since = "1.6.4",
              values = { level = "Level", name = "Name" }, order = { "level", "name" },
              desc = "How dungeons, quests and zones are listed when you list yourself: lowest level first, or A to Z. The Sort button on that page changes it too." },
        } },
        { label = "Borders and background", items = lookRows },
    } },
} }
