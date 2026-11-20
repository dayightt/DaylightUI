-- The profession window's options, as data.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

local lookRows = DUI.Options.LookRows("frameStyle", function() return DUI.craftMogul == true end)

ns.OPTIONS = { pages = {
    { id = "window", label = "Professions",
      desc = "Your profession's recipes in one window, in Daylight UI style.",
      groups = {
        { label = "Window", items = {
            { type = "text", label = "DaylightMogul's profession window is in use.",
              hidden = function() return not DaylightUI.craftMogul end },
            { type = "toggle", key = "enabled", label = "Daylight UI style profession window",
              disabled = function() return DaylightUI.craftMogul == true end,
              desc = "Opening a profession shows Daylight UI's window: your recipes on the left, the one you picked on the right. Turn it off to use the game's own window, in Daylight UI's look, for addons that build on it. Each window also has a button to switch to the other." },
            { type = "toggle", key = "rarityNames", since = "1.5.1", label = "Rarity colors",
              desc = "Recipe names take the rarity color of what they make. When off, they show how likely a skill-up is. The same switch sits beside the window's search.",
              disabled = function() return DaylightUI.craftMogul == true end },
            { type = "toggle", key = "skillUps", since = "1.7.2", label = "Skill-up chance",
              desc = "Each recipe shows its chance of giving a skill point, and the recipe you pick shows where it turns yellow, green and gray.",
              disabled = function() return DaylightUI.craftMogul == true end },
            { type = "toggle", key = "profit", since = "2.2", label = "Profit",
              desc = "The recipe you pick shows what its materials cost, what it sells for and the profit, from the prices the Auction House has shown you. The Profit chip over the list shows every recipe's, best first.",
              disabled = function() return DaylightUI.craftMogul == true or not DaylightUI.AuctionPrices end },
            { type = "slider", key = "scale", label = "Profession window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is.", disabled = function() return DaylightUI.craftMogul == true end },
        } },
        { label = "Borders and background", items = lookRows },
    } },
} }
