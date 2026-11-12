-- The window skins' options page: one switch per pack.

local _, ns = ...

local backRows = DaylightUI.Options.BackAlphaRows("windowAlpha", "Game window", nil, "1.6.2")

-- One switch per addon that has a skin (Packs/Addons), shown only while that
-- addon is installed. The card is hidden when none are.
local addonItems = {}
for _, spec in ipairs(ns.Engine.ADDON_SWITCHES) do
    addonItems[#addonItems + 1] = { type = "toggle", key = "addonSkins." .. spec.key, label = spec.label, reload = true,
        desc = spec.desc, hidden = function() return not ns.Engine.Installed(spec) end }
end

ns.OPTIONS = { pages = {
    { id = "skins", label = "Game window skins",
      desc = "The game's own windows in DaylightUI style: the info panel's background, DaylightUI borders, font, controls and scroll bars.",
      groups = {
        { label = "Packs", desc = "The game's windows Daylight UI didn't rebuild. Rebuilt windows have their own switches under Extras.", items = {
            { type = "toggle", key = "packs.npc", label = "Flight maps, stable and books", reload = true,
              desc = "Flight maps, books and letters, tabards and petitions, the stable. Also the game's own quest, gossip, vendor, trainer and bank windows while Daylight UI's are off." },
            { type = "toggle", key = "packs.social", label = "Guild, calendar and trading", reload = true,
              desc = "Guild and communities, the calendar, trading, the guild bank. Also the game's own friends, mail and group finder windows while Daylight UI's are off." },
            { type = "toggle", key = "packs.collections", label = "Collections and journals", reload = true,
              desc = "Collections, achievements, the dungeon journal, the dressing room." },
            { type = "toggle", key = "packs.system", label = "Menus, loot and items", reload = true,
              desc = "The game menu, addon list, macros, clock, loot, socketing, upgrading, the scrapper, the auction house, the professions book, the world map's frame, the breath bar, the crowd control alert, the box that splits a stack. Also the game's own character and inspect windows while Daylight UI's are off." },
        } },
        { label = "Windows", items = {
            backRows[1], backRows[2],
        } },
        { label = "Breath bar", items = {
            { type = "toggle", key = "breathSlant", label = "Breath bar angled end",
              desc = "Cuts the right end of the breath bar at an angle, on the fatigue and feign death bars too. When off, the end is straight.",
              disabled = function(get) return get("packs.system") == false end },
        } },
        { label = "Other addons", desc = "Other addons' windows in DaylightUI style. One switch per addon you have installed.",
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
              desc = "How see-through the world map's symbols are. Lower it to see more of the map under them." },
        } },
    } },
} }
