-- The window skins' options page: one switch per pack.

local _, ns = ...

local lookRows = DaylightUI.Options.LookRows("frameStyle", nil)

-- One switch per addon that has a skin (Packs/Addons), shown only while that
-- addon is installed. The card is hidden when none are.
local addonItems = {}
for _, spec in ipairs(ns.Engine.ADDON_SWITCHES) do
    addonItems[#addonItems + 1] = { type = "toggle", key = "addonSkins." .. spec.key, label = spec.label, reload = true,
        desc = spec.desc, hidden = function() return not ns.Engine.Installed(spec) end }
end

-- Daylight UI's loot roll window (Rolls/). Every row but the switch rests while
-- the window is off.
local function rollsPage()
    local NEW = "2.0"
    local function off(get) return get("rolls.enabled") == false end
    local function row(t)
        t.since = t.since or NEW
        if t.key ~= "rolls.enabled" then t.disabled = t.disabled or off end
        return t
    end
    return { id = "rolls", label = "Loot rolls",
      desc = "Need, Greed and Pass in Daylight UI's own roll window: who picked what, every roll and the winner.",
      sample = function(parent) return ns.RollSample.New(parent) end,
      groups = {
        { label = "Loot rolls", tab = "Basics", items = {
            row({ type = "toggle", key = "rolls.enabled", since = "2.2", label = "Daylight UI loot rolls", reload = true,
              desc = "Loot rolls in Daylight UI's own roll window, with who picked what, every roll and who won. When off, the game's own roll popups show instead." }),
            row({ type = "toggle", key = "rolls.popups", since = "2.2.2", label = "Restyle the game's roll popups", reload = true,
              disabled = function(get) return get("rolls.enabled") ~= false end,
              desc = "With Daylight UI loot rolls off, the game's roll popups wear Daylight UI style, with how many players picked Need, Greed and Pass on each button. When off, they look the way the game draws them." }),
            row({ type = "dropdown", key = "rolls.list", label = "Group list",
              values = { auto = "With one roll", always = "Always", hover = "On mouseover", off = "Never" },
              order = { "auto", "always", "hover", "off" },
              desc = "When a roll shows who picked what and everyone's rolls. A roll stays small until you've picked, then its list opens. With one roll up the list shows on its own, and with several, on the one under your mouse or the one just won." }),
            row({ type = "toggle", key = "rolls.compact", label = "Compact rolls when several drop",
              desc = "With more than one roll up, each shows just the item, your buttons and a row of ticks for who has picked, so several rolls fit on screen at once. When off, every roll shows in full." }),
            row({ type = "toggle", key = "rolls.fightCompact", label = "Compact rolls in a fight",
              desc = "In a fight, rolls stay compact and their lists open only under your mouse, so they never cover more of the screen than they need." }),
            row({ type = "slider", key = "rolls.linger", label = "Result time", min = 0, max = 15, step = 1,
              desc = "How many seconds a roll stays up after someone wins it. At 0 it leaves as soon as the winner is known." }),
            row({ type = "toggle", key = "rolls.holdOnHover", label = "Keep results under the mouse",
              desc = "A finished roll stays up while your mouse is on it, and leaves once you move away." }),
        } },
        { label = "Layout", tab = "Layout", items = {
            row({ type = "slider", key = "rolls.maxShown", label = "Max shown", min = 1, max = 8, step = 1,
              desc = "How many rolls show at once. Rolls past this wait their turn, with a line saying how many are waiting." }),
            row({ type = "dropdown", key = "rolls.grow", label = "Grow direction", values = { up = "Up", down = "Down" },
              order = { "up", "down" },
              desc = "Which way new rolls stack from the Loot Rolls handle." }),
            row({ type = "slider", key = "rolls.width", label = "Width", min = 240, max = 420, step = 10, unit = "px",
              desc = "How wide each roll is." }),
            row({ type = "slider", key = "rolls.spacing", label = "Spacing", min = 0, max = 20, step = 1, unit = "px",
              desc = "The gap between rolls." }),
            { type = "text", label = "Move the rolls with the Loot Rolls handle in unlock mode (/dui unlock). The mouse wheel over the handle sets their size." },
        } },
        { label = "Roll buttons", items = {
            row({ type = "slider", key = "rolls.buttonSize", label = "Roll button size", min = 24, max = 40, step = 1, unit = "px",
              desc = "The height of the Need, Greed and Pass buttons, and the size of their icons." }),
            row({ type = "toggle", key = "rolls.buttonWords", label = "Roll button words",
              desc = "Need, Greed and Pass written beside their icons. When off, the buttons show only their icons. Hover one for its name." }),
            row({ type = "dropdown", key = "rolls.icons", label = "Roll button icons", values = { daylight = "Daylight UI", game = "The game's" },
              order = { "daylight", "game" },
              desc = "Daylight UI's die, coin and cross, each in its own color, or the game's own dice and coins." }),
        } },
        { label = "Group list", tab = "List", items = {
            row({ type = "dropdown", key = "rolls.sort", label = "List order", values = { best = "Best roll first", picked = "As they picked" },
              order = { "best", "picked" },
              desc = "Best roll first puts Need above Greed above Pass, highest roll on top, so the winner leads. As they picked keeps the order people chose in." }),
            row({ type = "toggle", key = "rolls.showPass", label = "Show players who passed",
              desc = "Players who passed stay in the list, dimmed. When off, they're left out." }),
            row({ type = "toggle", key = "rolls.rollBars", label = "Roll bars",
              desc = "A thin bar beside each roll, as long as the number, to compare rolls at a glance." }),
            row({ type = "toggle", key = "rolls.ticks", label = "Pick ticks",
              desc = "A row of small ticks on a compact roll, one per player: tall for a high roll, faint for Greed, flat for Pass." }),
            row({ type = "toggle", key = "lastNames.rolls", label = "First and last names",
              desc = "Players' full names in the roll list. When off, first names only.",
              get = function() return DaylightUI:Get("general", "lastNames.rolls") == true end,
              set = function(v) DaylightUI:Set("general", "lastNames.rolls", v) end,
              default = function() return false end }),
            row({ type = "toggle", key = "rolls.twins", label = "Mark duplicate drops",
              desc = "Two of the same item are tagged 1 of 2 and 2 of 2 and joined by a line. Once one is won, its winner is tagged \"has one\" on the other." }),
        } },
        { label = "Look", tab = "Look", items = {
            row({ type = "toggle", key = "rolls.timerText", label = "Seconds left",
              desc = "The seconds left to pick, beside the timer bar." }),
            row({ type = "toggle", key = "rolls.qualityLine", label = "Quality color line",
              desc = "A line in the item's quality color along the top of each roll." }),
            row({ type = "toggle", key = "rolls.winShine", label = "Shine on a win",
              desc = "A light sweeps across the roll when someone wins it, twice when it's you. Needs Motion effects (General > Appearance)." }),
        } },
      } }
end

ns.OPTIONS = { pages = {
    { id = "skins", label = "Game window skins",
      desc = "The game's own windows in Daylight UI style: Daylight UI borders, window background, font, controls and scroll bars.",
      groups = {
        { label = "Restyled game windows", desc = "The game's windows Daylight UI didn't rebuild. Rebuilt windows have their own switches under Extras.", items = {
            { type = "toggle", key = "packs.npc", label = "Flight maps, stable and books", reload = true,
              desc = "Flight maps, books and letters, tabards and petitions, the stable, and the game's own talk, vendor and trainer windows when you pick them over Daylight UI's." },
            { type = "toggle", key = "packs.social", label = "Guild, calendar and trading", reload = true,
              desc = "Guild and communities, the calendar, trading, the guild bank, the game's mailbox, friends window and group finder." },
            { type = "toggle", key = "packs.collections", label = "Collections and journals", reload = true,
              desc = "Collections, achievements, the dungeon journal, the game's Legacy window, the dressing room." },
            { type = "toggle", key = "packs.system", label = "Menus, loot and items", reload = true,
              desc = "The game menu, addon list, macros, clock, loot, socketing, upgrading, the scrapper, the auction house, the professions book, the game's character, spellbook, profession and inspect windows, the world map's frame, the breath bar, the box that splits a stack." },
        } },
        { label = "Windows", items = {
        } },
        { label = "Borders and background", items = lookRows },
        { label = "Alerts and timers", items = {
            DaylightUI.Options.EndRows({ name = "Breath bar", note = "The fatigue and feign death bars too.",
                disabled = function(get) return get("packs.system") == false end,
                left = { on = "breathSlantLeft", flip = "breathUnderLeft" }, right = { on = "breathSlant", flip = "breathUnder" } })[1],
            DaylightUI.Options.EndRows({ name = "Breath bar", note = "The fatigue and feign death bars too.",
                disabled = function(get) return get("packs.system") == false end,
                left = { on = "breathSlantLeft", flip = "breathUnderLeft" }, right = { on = "breathSlant", flip = "breathUnder" } })[2],
            { type = "toggle", key = "ccAlert", label = "Crowd control alert", reload = true,
              desc = "The alert in the middle of the screen when you're stunned, feared or silenced, as a light line in Daylight UI style. When off, the game's own alert shows instead.",
              disabled = function(get) return get("packs.system") == false end },
        } },
        { label = "Other addons", desc = "Other addons' windows in Daylight UI style. One switch per addon you have installed.",
          items = addonItems },
        { label = "World map", items = {
            { type = "toggle", key = "mapLogBeside", label = "Quest list beside the map",
              desc = "With the map maximized, the quest list opens beside it, as it does on the small map, instead of taking its room from the map. On a narrow screen the map gives up only what doesn't fit.",
              disabled = function(get) return get("packs.system") == false end },
            { type = "toggle", key = "mapReveal", label = "Show unexplored areas",
              desc = "Parts of the world map you haven't explored yet show too, dimmed so you can still tell where you haven't been." },
            { type = "slider", key = "mapRevealDim", label = "Unexplored area brightness", min = 0.2, max = 1, step = 0.05, unit = "%",
              desc = "How bright the unexplored areas are. At 100% they look like the parts you've explored.",
              disabled = function(get) return get("mapReveal") ~= true end },
            { type = "toggle", key = "mapLevels", label = "Zone levels",
              desc = "Hover a zone on the world map to see its level range after its name, colored by how hard it is for you: green is easy, yellow is right for you, red is too high." },
            { type = "toggle", key = "mapDungeons", label = "Dungeon and raid entrances",
              desc = "A symbol on the world map at each dungeon and raid entrance. Hover it for the name." },
            { type = "toggle", key = "mapFlights", label = "Flight masters",
              desc = "A bird on the world map at each flight master you can use: blue for Alliance, red for Horde, gold for both." },
            { type = "toggle", key = "mapTravel", label = "Boats and zeppelins",
              desc = "A symbol on the world map at each boat dock and zeppelin tower. Hover it to see where it goes." },
            { type = "toggle", key = "mapFlightsAll", label = "Other faction's flight masters",
              desc = "Show the other faction's flight masters on the world map as well, in their own color. Handy for knowing where the enemy flies from.",
              disabled = function(get) return get("mapFlights") == false end },
            { type = "slider", key = "mapPinScale", label = "Map symbol scale", min = 0.5, max = 2, step = 0.05, unit = "x",
              desc = "The size of the entrance, flight master, boat and zeppelin symbols on the world map. They keep this size as you zoom." },
            { type = "slider", key = "mapPinAlpha", label = "Map symbol opacity", min = 0.2, max = 1, step = 0.05, unit = "%",
              desc = "How solid the world map's symbols are. Lower it to see more of the map under them." },
        } },
    } },
    rollsPage(),
} }
