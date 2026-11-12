-- The character window's options, as data.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

local backRows = DUI.Options.BackAlphaRows("windowAlpha", "Character window", nil, "1.6.2")

local MODES = { accent = "Accent", class = "Class color", gradient = "Class gradient", custom = "Custom" }
local HEAD_MODES = { group = "Each its own", accent = "Accent", class = "Class color", gradient = "Class gradient",
                     custom = "Custom" }
local LINE_MODES = { tab = "Like the tab underline", accent = "Accent", class = "Class color", gradient = "Class gradient",
                     custom = "Custom" }

local function mode(key, label, values, order, desc)
    return { type = "dropdown", key = "colors." .. key .. "Mode", label = label, values = values, order = order, desc = desc }
end
-- Color swatches only show while their menu is on "Custom", or "Each its own"
-- for the group colors.
local function color(key, label, when, desc)
    return { type = "color", key = "colors." .. key, label = label, desc = desc,
             hidden = function(get) return get("colors." .. when.key .. "Mode") ~= when.mode end }
end
local function groupColor(key, label)
    return color(key, label, { key = "head", mode = "group" },
                 "This group's header. The other pages use the six colors in turn.")
end

ns.OPTIONS = { pages = {
    { id = "window", label = "Character window",
      desc = "Your character window: gear, model, stats and the other pages. It opens with C, as always.",
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "DaylightUI style character window", reload = true,
              desc = "Pressing C opens DaylightUI's character window. Turn it off to use the game's." },
        } },
        { label = "Look", items = {
            { type = "toggle", key = "lastNames.character", label = "First and last names",
              desc = "Your last name after your first, at the top of the window.",
              get = function() return DUI:Get("general", "lastNames.character") == true end,
              set = function(v) DUI:Set("general", "lastNames.character", v) end },
            { type = "toggle", key = "names", label = "Item names beside icons",
              desc = "Each item's name and item level next to its icon. When off, only the icons show, with the item level in each corner and more room for the model." },
            { type = "toggle", key = "itemLevel", label = "Item level line",
              desc = "The dim line under each item's name. Repair warnings still show when it's off." },
            { type = "slider", key = "scale", label = "Window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is. Other windows still open beside it when they fit." },
            backRows[1], backRows[2],
        } },
        { label = "Gear", items = {
            { type = "slider", key = "repairAt", label = "Repair warning at", min = 0.05, max = 0.5, step = 0.05, unit = "%",
              desc = "A slot at or under this much durability gets an amber dot and says Repair soon." },
        } },
        { label = "Stats", items = {
            { type = "dropdown", key = "statsOpen", label = "Open stat groups", values = { auto = "By class and spec", all = "All" },
              order = { "auto", "all" },
              desc = "Which stat groups start open. By class and spec: Attributes and the one that matters for you. Groups you open or fold yourself are remembered for each character." },
        } },
        { label = "Bars", items = {
            { type = "toggle", key = "gradient", label = "Gradient bars",
              desc = "Reputation bars in their colors from the Gradients page, skill, PvP and currency bars in the accent's. When off, they're plain fills." },
        } },
        { label = "Colors", items = {
            mode("head", "Header colors", HEAD_MODES, { "accent", "group", "class", "gradient", "custom" },
                 "The stat group headers and the headers on the other pages. Each its own: a color per stat group, used in turn on the other pages."),
            groupColor("attributes", "Attributes"),
            groupColor("attack", "Attack"),
            groupColor("ranged", "Ranged"),
            groupColor("spell", "Spell"),
            groupColor("defense", "Defense"),
            groupColor("resistances", "Resistances"),
            color("head", "Header color", { key = "head", mode = "custom" }, "Every header in this one color."),
            mode("line", "Header lines", LINE_MODES, { "tab", "accent", "class", "gradient", "custom" },
                 "The thin line under each header. Like the tab underline: whatever Tab underline below is set to. Class gradient uses your class's colors from the Gradients page."),
            color("line", "Line color", { key = "line", mode = "custom" }, "The lines under the headers in this color."),
            { type = "toggle", key = "glow", label = "Glow behind your character",
              desc = "The soft light behind the model on the Character page. When off, only the window's background shows." },
            mode("glow", "Glow color", MODES, { "accent", "class", "gradient", "custom" },
                 "The soft light behind the model on the Character page."),
            color("glow", "Glow custom color", { key = "glow", mode = "custom" }, "The glow behind your character in this color."),
            mode("tab", "Tab underline", MODES, { "accent", "gradient", "class", "custom" },
                 "The line under the open tab at the top (Character, Reputation, Skills...)."),
            color("tab", "Underline color", { key = "tab", mode = "custom" }, "The line under the open tab in this color."),
            { type = "toggle", key = "zebra", label = "Striped rows",
              desc = "Every other row on a faint stripe, in the stats and the long lists, so lines are easier to follow." },
            { type = "toggle", key = "footColors", label = "Colored item level and durability",
              desc = "The item level at the bottom in your gear's quality color, durability green to yellow to red. When off, both are plain gray." },
        } },
    } },
} }
