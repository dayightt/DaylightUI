-- The tooltips' options page.

local _, ns = ...

ns.OPTIONS = { pages = {
    { id = "tooltip", label = "Tooltips",
      desc = "The game's tooltips in the DaylightUI look.",
      -- With PrettyTooltip on this module is off (Module.lua), so none of this would apply.
      hidden = function() return DaylightUI.PrettyAside.Draws() end,
      groups = {
        { label = "Placement", items = {
            { type = "dropdown", key = "anchor", label = "Position",
              values = { game = "Default spot", cursor = "At the cursor" }, order = { "game", "cursor" },
              desc = "Default spot: where the game puts it, or where you dragged it in unlock mode. "
                  .. "Tooltips for bags, bars and other frames that place their own still sit beside what you hover." },
            { type = "slider", key = "cursorX", label = "Tooltip left / right of the cursor", min = -100, max = 100, step = 1, unit = "px",
              desc = "How far right of the cursor the tooltip's corner sits (below zero: to the left).",
              hidden = function(get) return get("anchor") ~= "cursor" end },
            { type = "slider", key = "cursorY", label = "Tooltip up / down from the cursor", min = -100, max = 100, step = 1, unit = "px",
              desc = "How far above the cursor the tooltip's corner sits (below zero: lower down).",
              hidden = function(get) return get("anchor") ~= "cursor" end },
        } },
        { label = "Size", items = {
            { type = "slider", key = "scale", label = "Scale", min = 0.6, max = 1.6, step = 0.05, unit = "x",
              desc = "Makes tooltips bigger or smaller, text and all, on top of the Scale on the General page." },
            { type = "slider", key = "textSize", label = "Text size", min = 9, max = 18, step = 1,
              desc = "The tooltip text; titles are a little larger." },
            DaylightUI.Options.FontRow("media.font", "Tooltip font", "Every line in the tooltips"),
        } },
        { label = "Look", items = {
            { type = "slider", key = "bgAlpha", label = "Background opacity", min = 0.3, max = 1, step = 0.05, unit = "%",
              desc = "How solid the dark background is." },
            { type = "toggle", key = "classColors", label = "Class-colored names",
              desc = "A player's name in their class color; other units in their reaction's color." },
            { type = "toggle", key = "classBorder", label = "Class-colored border",
              desc = "The border in the same color as the name." },
            { type = "toggle", key = "borderGradient", label = "Gradient border",
              desc = "That border in the unit's class (or reaction) gradient from the Gradients page, running left to right.",
              disabled = function(get) return get("classBorder") == false end },
            { type = "toggle", key = "qualityBorder", label = "Item quality border",
              desc = "Items that are uncommon or better get a border in their quality color." },
            { type = "toggle", key = "healthBar", label = "Health bar",
              desc = "A slim bar under the tooltip of a player or creature." },
            { type = "slider", key = "barHeight", label = "Health bar height", min = 2, max = 12, step = 1, unit = "px",
              desc = "How tall the health bar under the tooltip is.",
              disabled = function(get) return get("healthBar") ~= true end },
            DaylightUI.Options.BarRow("media.health", "Health bar", "the health bar under a unit's tooltip", function(get) return get("healthBar") ~= true end),
            DaylightUI.Options.BackRow("media.health", "Health bar", "the health bar under a unit's tooltip", function(get) return get("healthBar") ~= true end),
            { type = "dropdown", key = "barGradient", label = "Health bar color",
              values = { frames = "Same as unit frames", gradient = "Class gradient", flat = "Class and reaction" },
              order = { "frames", "gradient", "flat" },
              desc = "Same as unit frames: a class gradient when your unit frames' health bars use one. "
                  .. "Class gradient uses the pairs from the Gradients page.",
              disabled = function(get) return get("healthBar") ~= true end },
        } },
        { label = "Extra lines", items = {
            { type = "toggle", key = "showTarget", label = "Show who they're targeting",
              desc = "Who a player or creature is targeting, in their color (\">> You <<\" when it's you)." },
            { type = "toggle", key = "guildRank", label = "Guild rank", desc = "After a player's guild name." },
            { type = "toggle", key = "buffs", label = "Their buffs",
              desc = "A friendly player's buffs as a row of small icons, so you can see what they're missing before you rebuff. Not in combat: the game hides other players' buffs then." },
            { type = "toggle", key = "greenStats", label = "Short, colored item stats",
              desc = "An item's green Equip lines in a few words (\"Improves your chance to hit by 1%\" reads \"+1% Hit\"), and every stat in a color of its own: each school, hit, crit, spell power, healing, the base stats. Procs and use effects stay as they are." },
            { type = "toggle", key = "itemLevel", label = "Item level",
              desc = "An Item Level line on weapon and armor tooltips, in soft gold." },
            { type = "toggle", key = "stackSize", label = "Stack size",
              desc = "How many of an item fit in one bag slot (\"Stacks to 20\"), on items that stack." },
            { type = "toggle", key = "showIDs", label = "Spell and item IDs",
              desc = "A small gray line at the bottom of spell and item tooltips with its ID: handy for macros, other addons and bug reports. Buff and debuff icons use the game's own tooltip, which can't show it." },
            { type = "toggle", key = "lastNames.tooltip", label = "First and last names",
              desc = "Players' last names after their first, on tooltips. Where the game hides names (in combat, in places) only the first name shows.",
              get = function() return DaylightUI:Get("general", "lastNames.tooltip") == true end,
              set = function(v) DaylightUI:Set("general", "lastNames.tooltip", v) end },
            -- Lives in the Quests module (GiverTips.lua), which draws it even with this module off.
            { type = "toggle", key = "mapQuests.tooltip", scope = "Quests", label = "Quests in NPC tooltips",
              desc = "Point at a quest giver to see the quests you can pick up from them and the ones ready to hand in, each with its level in its difficulty color. Needs Questie.",
              hidden = function() return not DaylightUI:GetModule("Quests") end,
              -- The list comes from Questie (GiverTips' GT.On), so nothing shows without it.
              disabled = function()
                  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
                  return not (type(loaded) == "function" and loaded("Questie") == true)
              end,
              get = function() return DaylightUI:Get("Quests", "mapQuests.tooltip") ~= false end,
              set = function(v) DaylightUI:Set("Quests", "mapQuests.tooltip", v) end,
              default = function() return true end },
        } },
        { label = "Hiding", items = {
            { type = "toggle", key = "fadeOut", label = "Fade out",
              desc = "A tooltip for something in the world (a creature, a player, a mailbox) fades away slowly after the mouse leaves it, as the game does. When off, it's gone at once." },
        } },
        { label = "In combat", items = {
            { type = "toggle", key = "hideInCombat", invert = true, label = "Show unit tooltips in combat",
              desc = "Players' and creatures' tooltips show while you're fighting. When off, they stay hidden in a fight; hold Shift to see one." },
        } },
    } },
} }
