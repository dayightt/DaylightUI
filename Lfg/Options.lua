-- The group finder window's options, as data.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Group finder", nil, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Group Finder",
      desc = "Finding a group, listing yourself and the who list, in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "DaylightUI style group finder", reload = true,
              desc = "Opening the group finder shows DaylightUI's window: groups to join, listing yourself, and who's about. In a fight the game's own window opens. Turn it off to use the game's window." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            { type = "dropdown", key = "activitySort", label = "Sort activities by", since = "1.6.4",
              values = { level = "Level", name = "Name" }, order = { "level", "name" },
              desc = "How dungeons, quests and zones are listed when you list yourself: lowest level first, or A to Z. The Sort button on that page changes it too." },
            backRows[1], backRows[2],
        } },
    } },
} }
