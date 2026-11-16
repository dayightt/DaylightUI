-- The social window's options, as data.

local _, DUI = ...
DUI.Social = DUI.Social or {}
local ns = DUI.Social

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Social window", nil, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Social",
      desc = "Your friends, recent allies, friend requests and the raid, in one window, in Daylight UI style.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "Daylight UI style social window",
              desc = "Pressing O shows Daylight UI's window: who's online, people you played with, friend requests and your raid's groups. Turn it off to use the game's own window, in Daylight UI's look. Each window also has a button to switch to the other." },
            { type = "slider", key = "scale", label = "Social window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is." },
            backRows[1], backRows[2],
        } },
        { label = "Friends", items = {
            { type = "toggle", key = "friendFactions", label = "Faction icons", since = "1.7.2",
              desc = "A small Alliance or Horde banner before each friend's character, and their faction in the tooltip." },
            { type = "toggle", key = "friendDim", label = "Dim friends you can't play with", since = "1.7.2",
              desc = "Friends in another game or on another ruleset show dimmed, like the ones who are offline." },
            { type = "toggle", key = "friendChips", label = "Friend filter buttons", since = "1.7.2",
              desc = "All, Same game and Online buttons over the friends list, to show only the friends you can play with or the ones who are on." },
        } },
    } },
} }
