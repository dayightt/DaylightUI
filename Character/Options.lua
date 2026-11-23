-- The character window's options, as data.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

local lookRows = DUI.Options.LookRows("frameStyle", nil)

local MODES = { accent = "Accent color", class = "Class color", gradient = "Class gradient", custom = "One color" }
local HEAD_MODES = { group = "Each its own", accent = "Accent color", class = "Class color", gradient = "Class gradient",
                     custom = "One color" }
local LINE_MODES = { tab = "Like the tab underline", accent = "Accent color", class = "Class color", gradient = "Class gradient",
                     custom = "One color" }

local function mode(key, label, values, order, desc)
    return { type = "dropdown", key = "colors." .. key .. "Mode", label = label, values = values, order = order, desc = desc }
end
-- Color swatches only show while their menu is on "One color", or "Each its own"
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
            { type = "toggle", key = "enabled", label = "Daylight UI style character window",
              desc = "Pressing C opens Daylight UI's character window. Turn it off to use the game's own, in Daylight UI's look. Each window also has a button to switch to the other." },
            { type = "slider", key = "scale", label = "Character window scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is. Other windows still open beside it when they fit." },
            { type = "dropdown", key = "statsOpen", label = "Open stat groups", values = { auto = "By class and spec", all = "All" },
              order = { "auto", "all" },
              desc = "Which stat groups start open. By class and spec: Attributes and the one that matters for you. Groups you open or fold yourself are remembered for each character." },
        } },
        { label = "Borders and background", items = lookRows },
        { label = "Look", items = {
            { type = "toggle", key = "lastNames.character", label = "First and last names",
              desc = "Your last name after your first, at the top of the window.",
              get = function() return DUI:Get("general", "lastNames.character") == true end,
              set = function(v) DUI:Set("general", "lastNames.character", v) end,
              default = function() return true end },
            { type = "toggle", key = "names", label = "Item names beside icons",
              desc = "Each item's name and item level next to its icon. When off, only the icons show, with the item level in each corner and more room for the model." },
            { type = "toggle", key = "itemLevel", label = "Item level line",
              desc = "The dim line under each item's name. Repair warnings still show when it's off." },
            { type = "toggle", key = "levelInIcon", label = "Item level in the icon",
              desc = "The item level in the icon's corner instead of a line under the name, so long names have the room." },
            { type = "toggle", key = "missingEnchants", since = "2.2.4", label = "Missing enchants",
              desc = "A soft No enchant line under gear that could carry an enchant but has none. Enchants themselves show in your accent color." },
            { type = "slider", key = "repairAt", label = "Repair warning at", min = 0.05, max = 0.5, step = 0.05, unit = "%",
              desc = "A slot at or under this much durability gets an amber dot and says Repair soon." },
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
            color("head", "Custom header color", { key = "head", mode = "custom" }, "Every header in this color, when Header colors is One color."),
            mode("line", "Header lines", LINE_MODES, { "tab", "accent", "class", "gradient", "custom" },
                 "The thin line under each header. Like the tab underline: whatever Tab underline below is set to. Class gradient uses your class's colors from the Gradients page."),
            color("line", "Custom header line color", { key = "line", mode = "custom" }, "The lines under the headers in this color, when Header lines is One color."),
            { type = "toggle", key = "glow", label = "Glow behind your character",
              desc = "The soft light behind the model on the Character page. When off, only the window's background shows." },
            mode("glow", "Glow color", MODES, { "accent", "class", "gradient", "custom" },
                 "The soft light behind the model on the Character page."),
            color("glow", "Custom glow color", { key = "glow", mode = "custom" }, "The glow behind your character in this color, when Glow color is One color."),
            mode("tab", "Tab underline", MODES, { "accent", "gradient", "class", "custom" },
                 "The line under the open tab at the top (Character, Reputation, Skills...)."),
            color("tab", "Custom tab underline color", { key = "tab", mode = "custom" }, "The line under the open tab in this color, when Tab underline is One color."),
            { type = "toggle", key = "gradient", label = "Gradient bars",
              desc = "Reputation bars in their colors from the Gradients page, skill, PvP and currency bars in the accent's. When off, they're plain fills. Needs Gradients on (General > Gradients).",
              disabled = function() return DUI.Gradients.Flat() end },
            { type = "toggle", key = "zebra", label = "Striped rows",
              desc = "Every other row on a faint stripe, in the stats and the long lists, so lines are easier to follow." },
            { type = "toggle", key = "footColors", label = "Colored item level and durability",
              desc = "The item level at the bottom in your gear's quality color, durability green to yellow to red. When off, both are plain white." },
        } },
    } },
} }
