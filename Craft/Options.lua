-- The profession window's options, as data.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Profession window", function() return DUI.craftMogul == true end, "1.6.2")

ns.OPTIONS = { pages = {
    { id = "window", label = "Professions",
      desc = "Your profession's recipes in one window, in DaylightUI style.",
      groups = {
        { label = "Window", items = {
            { type = "text", label = "DaylightMogul's profession window is in use.",
              hidden = function() return not DaylightUI.craftMogul end },
            { type = "toggle", key = "enabled", label = "DaylightUI style profession window", reload = true,
              disabled = function() return DaylightUI.craftMogul == true end,
              desc = "Opening a profession shows DaylightUI's window: your recipes on the left, the one you picked on the right. In a fight the game's own window opens. Turn it off to use the game's window." },
            { type = "toggle", key = "rarityNames", since = "1.5.1", label = "Rarity colors",
              desc = "Recipe names take the rarity color of what they make. Off, they show how likely a skill-up is. The same switch sits beside the window's search.",
              disabled = function() return DaylightUI.craftMogul == true end },
            { type = "toggle", key = "skillUps", since = "1.7.2", label = "Skill-up chance",
              desc = "Each recipe shows its chance of giving a skill point, and the recipe you pick shows where it turns yellow, green and gray.",
              disabled = function() return DaylightUI.craftMogul == true end },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is.", disabled = function() return DaylightUI.craftMogul == true end },
            backRows[1], backRows[2],
        } },
    } },
} }
