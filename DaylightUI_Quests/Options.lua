-- Quest tracker options, as data.

local _, ns = ...

local function isOn(key) return function(get) return get(key) == true end end
local function off(key) return function(get) return get(key) ~= true end end

local SIDES = { left = "Left", right = "Right" }
local CLICK_ACTIONS = { map = "Show on map", details = "Quest details", priority = "Make it your priority",
                        fold = "Fold it", untrack = "Stop tracking",
                        link = "Link in chat", none = "Nothing" }
local CLICK_ORDER = { "map", "details", "priority", "fold", "untrack", "link", "none" }
local function clickPick(key, label, desc)
    return { type = "dropdown", key = "clicks." .. key, label = label, values = CLICK_ACTIONS, order = CLICK_ORDER, desc = desc }
end
local FILTERS = { all = "All tracked quests", zone = "This zone only", log = "Every quest in your log" }
local SORTS = { recent = "Most recent progress", zone = "Zone order", level = "Level", near = "Nearest first", ready = "Ready first" }
local INSTANCE_MODES = { zone = "This zone only", fold = "Fold to the header", hide = "Hide", none = "Leave as it is" }
local OBJ_COLORS = { plain = "Plain", done = "Green when done", count = "Red to green by count" }
local JOURNAL_SORTS = { log = "Quest log order", level = "Level", ready = "Ready first", watched = "Tracked first" }
local TITLE_MODES = { difficulty = "By difficulty", one = "One color" }
local BAR_MODES = { accent = "Accent", class = "Class color", custom = "Custom" }
local MARKER_LOOKS = { beacon = "Beacon", pillar = "Light pillar", minimal = "Minimal" }
local FOCUS_MODES ={ accent = "Accent", daylight = "Daylight gradient", gradient = "Class gradient", class = "Class color", custom = "Custom" }

local function size(key, label, desc)
    return { type = "slider", key = "sizes." .. key, label = label, min = 8, max = 20, desc = desc }
end
local function color(key, label, desc)
    return { type = "color", key = "colors." .. key, label = label, desc = desc }
end

-- Paint mode menu (custom / accent / class color / class gradient) plus its custom color.
local PAINT_MODES = { custom = "Custom", accent = "Accent", class = "Class color", gradient = "Class gradient" }
local function paintMode(key, label)
    return { type = "dropdown", key = "colors." .. key .. "Mode", label = label, values = PAINT_MODES,
             order = { "custom", "accent", "class", "gradient" },
             desc = "One custom color, the accent, your class color, or your class's two colors as a gradient (from the Gradients page)." }
end
local function paintColor(key, label)
    return { type = "color", key = "colors." .. key, label = label,
             desc = "The color used while the menu above is set to Custom.",
             hidden = function(get) return get("colors." .. key .. "Mode") ~= "custom" end }
end

-- Quest box background opacity: the general window opacity or its own.
local backRows = DaylightUI.Options.BackAlphaRows("boxAlpha", "Quest box", function(get) return get("box") ~= true end)
backRows[2].desc = backRows[2].desc or "How see-through the box behind the quest list is. Lower lets more of the world show through."
ns.OPTIONS = { pages = {
    { id = "tracker", label = "Tracker",
      desc = "Your watched quests, under the info panel. Move it in unlock mode.",
      groups = {
        { label = "Layout", items = {
            { type = "toggle", key = "matchMap", label = "Match the minimap's width",
              desc = "As wide as the minimap above it, so their edges line up. When off, it uses the width below." },
            { type = "slider", key = "width", label = "Width", min = 160, max = 400, unit = "px",
              desc = "How wide the list is.", disabled = isOn("matchMap") },
            { type = "slider", key = "maxHeight", label = "Height limit", min = 200, max = 1200, step = 10, unit = "px",
              desc = "Past this the list scrolls with the mouse wheel." },
            { type = "toggle", key = "growUp", label = "Grow upward",
              desc = "The list grows up from its handle instead of down. For a tracker placed low on the screen." },
            { type = "toggle", key = "zoneNames", label = "Zone names",
              desc = "A small zone name over each group of quests, the zone you're in first." },
            { type = "toggle", key = "compact", label = "Compact spacing",
              desc = "Less room between quests. Fits more on a small screen." },
            { type = "dropdown", key = "itemSide", label = "Item buttons", values = SIDES, order = { "left", "right" },
              desc = "Which side of the list the quest item buttons sit on." },
            { type = "toggle", key = "box", label = "Background",
              desc = "The panel's framed box behind the list, as tall as what's shown." },
            backRows[1], backRows[2],
            { type = "toggle", key = "boxBorder", label = "Border",
              desc = "A border and shadow around the background.", disabled = off("box") },
        } },
        { label = "Text", items = {
            DaylightUI.Options.FontRow("media.font", "Quest tracker font", "Every text in the quest tracker"),
            size("header", "Section header size", "Quests, Achievements."),
            size("title", "Quest title size", "Each quest's title in the tracker."),
            size("objective", "Objective size", "Objectives, counts, hand-in lines and timers."),
            size("zone", "Zone name size", "The small zone names over each group of quests."),
            { type = "toggle", key = "capsTitles", label = "Titles in capitals",
              desc = "Quest titles in capitals, like the DaylightUI unit frame names. Objectives stay as they are." },
            { type = "toggle", key = "questLevels", label = "Quest levels",
              desc = "Each quest's level in front of its title, like [15]." },
            { type = "toggle", key = "questTags", label = "Quest tags",
              desc = "A small tag after an elite, dungeon, raid or PvP quest's title, here and in the quest log on the map." },
            { type = "toggle", key = "questParty", label = "Party members on a quest",
              desc = "A small icon and count at the end of a quest's line when others in your party have it too, here and in the quest log on the map." },
            { type = "toggle", key = "hideDone", invert = true, label = "Show done objectives",
              desc = "A done objective stays, dimmed with a tick. When off, it disappears once it's done." },
        } },
        { label = "Behavior", items = {
            { type = "toggle", key = "tracker", label = "Use DaylightUI's quest tracker",
              desc = "Questie is on: when off, Questie's own tracker shows instead. Daylight UI's journal, marker and arrow stay either way.",
              hidden = function() return not (ns.Bridge and ns.Bridge.Loaded()) end },
            { type = "dropdown", key = "filter", label = "Quests to show", values = FILTERS, order = { "all", "zone", "log" },
              desc = "Every tracked quest, only the zone you're in, or every quest in your log without tracking them. The controls over the list switch the first two." },
            { type = "dropdown", key = "sort", label = "Quest order", values = SORTS, order = { "recent", "zone", "level", "near", "ready" },
              desc = "Within each zone. Most recent progress moves a quest and its zone to the top when a kill, item or objective counts. Nearest first looks again every few seconds as you move, never in a fight or a dungeon. Nothing moves in a fight." },
            { type = "toggle", key = "foldReady", label = "Fold ready quests",
              desc = "A quest ready to hand in shows its title alone. A timed quest never folds." },
            { type = "dropdown", key = "instances", label = "Tracker in dungeons and raids", values = INSTANCE_MODES, order = { "zone", "fold", "hide", "none" },
              desc = "What the tracker does when you enter a dungeon, raid or battleground. It comes back as you leave. This zone only keeps the quests for where you are; All over the list shows the rest until you leave." },
            { type = "toggle", key = "hoverDim", label = "Dim other quests on hover",
              desc = "The quest under the mouse stays bright, the others ease dimmer." },
            { type = "toggle", key = "rowTips", label = "Show quest tooltips",
              desc = "A quest under the mouse shows its objectives and clicks beside the tracker. When off, nothing shows and clicks work the same." },
            { type = "toggle", key = "emptyHeader", label = "Show the header with no quests",
              desc = "The Quests header stays when nothing is tracked, so you can see where the tracker is." },
            clickPick("click", "Click on a quest", "What a click on a quest in the tracker does. Clicking its icon always makes it your priority, and right-click opens its menu."),
            clickPick("shift", "Shift-click on a quest", "With chat open, Shift-click links the quest first."),
            clickPick("ctrl", "Ctrl-click on a quest", "Your priority quest is the one the marker and arrow lead to."),
            clickPick("alt", "Alt-click on a quest", "What Alt-click on a quest in the tracker does."),
            { type = "toggle", label = "Track new quests automatically",
              desc = "The game's own setting: a quest you accept goes straight into the tracker.",
              get = function() return type(GetCVarBool) == "function" and GetCVarBool("autoQuestWatch") == true end,
              set = function(v) if type(SetCVar) == "function" then SetCVar("autoQuestWatch", v and "1" or "0") end end,
              default = function() return true end },
        } },
        { label = "Quest progress pop-up", items = {
            { type = "toggle", key = "progress", label = "Quest progress pop-up",
              desc = "A kill or item for a quest shows for a moment at the top of the screen, small, with a progress bar. Turn it off to see the game's yellow line instead. Move it in unlock mode." },
            { type = "slider", key = "progressScale", label = "Pop-up scale", min = 0.5, max = 2, step = 0.05, unit = "x",
              desc = "The whole pop-up, text and bar together.",
              disabled = off("progress") },
            { type = "slider", key = "progressHold", label = "Stays for (seconds)", min = 1, max = 8, step = 0.1,
              desc = "How long a line stays on screen before it fades away.",
              disabled = off("progress") },
            DaylightUI.Options.BarRow("media.progress", "Progress bar", "the progress bars in the tracker and the pop-up"),
            DaylightUI.Options.BackRow("media.progress", "Progress bar", "the progress bars in the tracker and the pop-up"),
        } },
        DaylightUI.Fade.Card("fade.", nil, nil, "Quest tracker"),
      } },
    { id = "navigation", label = "Navigation",
      desc = "The marker in the world that leads you to your quest.",
      groups = {
        { label = "Quest marker", items = {
            { type = "toggle", key = "nav.marker", label = "DaylightUI style quest marker",
              desc = "The marker over the spot of the quest you picked (click its icon in the tracker) in DaylightUI style, with the distance. It fades away once you're in the quest's area on the map. Turn it off to see the game's own marker." },
            { type = "dropdown", key = "nav.style", label = "Marker look", values = MARKER_LOOKS,
              order = { "beacon", "pillar", "minimal" }, disabled = off("nav.marker"),
              desc = "Beacon: a diamond with a soft light. Light pillar: a beam standing on the spot, easy to see from far away. Minimal: a small arrow and the distance." },
            { type = "slider", key = "nav.scale", label = "Marker scale", min = 0.5, max = 2, step = 0.05, unit = "x",
              desc = "How big the quest marker is in the world, distance text included.",
              disabled = off("nav.marker") },
            { type = "toggle", key = "nav.distance", label = "Distance under the marker",
              desc = "How many yards away it is.", disabled = off("nav.marker") },
            { type = "toggle", key = "nav.trail", label = "Breadcrumbs on the ground",
              desc = "A trail of small diamonds from your feet to the marker, drifting toward it. Like the marker, it fades away once you're in the quest's area on the map.",
              disabled = off("nav.marker") },
            { type = "toggle", key = "nav.fightFade", label = "Softer in a fight",
              desc = "The marker and the arrow fade back while you're in combat, so they're never in the way." },
        } },
        { label = "Quest arrow", items = {
            { type = "toggle", key = "nav.arrow", label = "Arrow to the nearest objective",
              desc = "An arrow on your screen that points to the nearest mob or object you still need for the quest you picked, then to the quest giver once it's ready, with the yards under it. Nothing goes on the map. Needs the QuestieDB addon." },
            { type = "slider", key = "nav.arrowScale", label = "Arrow scale", min = 0.5, max = 2, step = 0.05, unit = "x",
              desc = "How big the arrow is on your screen, yards text included.",
              disabled = off("nav.arrow") },
            { type = "dropdown", key = "nav.arrowColorMode", label = "Arrow color", values = BAR_MODES,
              order = { "accent", "class", "custom" }, disabled = off("nav.arrow"),
              desc = "Accent follows the accent you picked on the General page, gradient and all." },
            { type = "color", key = "nav.arrowColor", label = "Custom arrow color",
              desc = "The arrow's color while Arrow color is set to Custom.",
              hidden = function(get) return get("nav.arrowColorMode") ~= "custom" end, disabled = off("nav.arrow") },
            { type = "toggle", key = "nav.arrowGlow", label = "Arrow glow",
              desc = "A soft light behind the arrow, in its color.", disabled = off("nav.arrow") },
            { type = "slider", key = "nav.arrowGlowAlpha", label = "Arrow glow strength", min = 0.1, max = 1, step = 0.05, unit = "%",
              desc = "How bright the light behind the arrow is.",
              disabled = function(get) return get("nav.arrow") ~= true or get("nav.arrowGlow") ~= true end },
            { type = "toggle", key = "nav.arrowDistance", label = "Yards under the arrow",
              desc = "How far away the spot is.", disabled = off("nav.arrow") },
            { type = "text", label = function()
                if ns.Spots and ns.Spots.Ready() then
                    return DaylightUI.L["QuestieDB found: the arrow is ready."]
                end
                return DaylightUI.L["QuestieDB isn't installed: the arrow needs it to know where each mob and quest giver is."]
              end },
        } },
      } },
    { id = "map", label = "Map",
      desc = "The quest log on the world map.",
      groups = {
        { label = "Quest log", items = {
            { type = "toggle", key = "journal", label = "DaylightUI style quest log on the map",
              desc = "The world map's quest list and quest pages in DaylightUI style, with Track, Share and Abandon on each quest. Turn it off to use the game's own." },
            { type = "toggle", key = "journalTipBeside", label = "Quest tooltips beside the log",
              desc = "Hovering a quest in the quest log shows its tooltip beside the log, as the game's own log does. Off shows it at the mouse.",
              disabled = off("journal") },
            { type = "toggle", key = "journalHoverIcons", label = "Spotlight a quest's map icons on hover",
              desc = "Hovering a Questie icon on the map or minimap, or a quest in the quest log, makes that quest's icons a little bigger and fades the other quests' icons." },
        } },
        { label = "Quest list", items = {
            { type = "dropdown", key = "journalSort", label = "Quest log sort order", values = JOURNAL_SORTS,
              order = { "log", "level", "ready", "watched" }, disabled = off("journal"),
              desc = "The order of the quests inside each zone in the quest log on the map." },
            { type = "toggle", key = "journalHereFirst", label = "Current zone first in the quest log",
              desc = "Puts the zone you're in at the top of the quest log. When off, zones stay in the game's order.",
              disabled = off("journal") },
            { type = "slider", key = "journalTextSize", label = "Quest log text size", min = 10, max = 18,
              desc = "Size of the quest names in the quest log on the map. Zone names, levels and progress follow it.",
              disabled = off("journal") },
            { type = "slider", key = "journalRowHeight", label = "Quest log row height", min = 18, max = 36, unit = "px",
              desc = "How tall each quest's row is in the quest log. Larger text keeps enough room however low this is set.",
              disabled = off("journal") },
            { type = "slider", key = "journalOpacity", label = "Quest log opacity", min = 0.5, max = 1, step = 0.01, unit = "%",
              desc = "How solid the quest log's background is. Lower lets the world show through behind the list.",
              disabled = off("journal") },
            { type = "toggle", key = "journalLevels", label = "Show quest levels in the quest log",
              desc = "The level in front of each quest name.", disabled = off("journal") },
            { type = "toggle", key = "journalProgress", label = "Show progress in the quest log",
              desc = "Counts like 0/6, and Ready, at the end of each quest's row.", disabled = off("journal") },
            { type = "toggle", key = "journalDots", label = "Mark tracked quests in the quest log",
              desc = "A small dot in front of each quest you're tracking.", disabled = off("journal") },
            { type = "toggle", key = "journalZoneCaps", label = "Zone names in capitals in the quest log",
              desc = "Writes zone names in capital letters. When off, they're written as the game writes them.",
              disabled = off("journal") },
        } },
      } },
    { id = "colors", label = "Colors",
      desc = "Every color in the quest tracker.",
      groups = {
        { label = "Headers", items = {
            paintMode("header", "Section header color"),
            paintColor("header", "Custom section header color"),
            paintMode("headerLine", "Header line color"),
            paintColor("headerLine", "Custom header line color"),
            paintMode("zone", "Zone name color"),
            paintColor("zone", "Custom zone name color"),
        } },
        { label = "Quests", items = {
            { type = "dropdown", key = "colors.titleMode", label = "Quest title color", values = TITLE_MODES,
              order = { "difficulty", "one" }, desc = "By the quest's difficulty for your level, or one color for all. The quest log on the map uses the same colors." },
            { type = "color", key = "colors.title", label = "Custom quest title color",
              desc = "Every quest title's color while Quest title color is set to One color.",
              hidden = function(get) return get("colors.titleMode") ~= "one" end },
            { type = "dropdown", key = "objColors", label = "Objective progress color",
              values = { plain = "The colors below", done = "Green once done", count = "Red to green as it fills" },
              order = { "plain", "done", "count" },
              desc = "How objective lines show their progress: in the colors below, green once done, or shading from red to green as the count fills." },
            color("objective", "Objective color", "Each objective line under a quest."),
            color("count", "Count color", "The numbers in objectives, like 3/8."),
            color("done", "Done objective color", "An objective you've finished."),
            color("tick", "Done tick color", "The tick next to a finished objective."),
            color("ready", "Ready to hand in", "The '?', the title and the hand-in line."),
            color("elite", "Elite tag color", "The tag after an elite quest's title."),
            color("dungeon", "Dungeon tag color", "The tag after a dungeon quest's title."),
            color("raid", "Raid tag color", "The tag after a raid quest's title."),
            color("pvp", "PvP tag color", "The tag after a PvP quest's title."),
            color("failed", "Failed quest color", "A quest you've failed, like a timed one that ran out."),
            color("timer", "Timer color", "The time left on a timed quest."),
            color("timerUrgent", "Timer color, last minute", "The time left on a timed quest once it's under a minute."),
            { type = "dropdown", key = "colors.focusMode", label = "Priority quest color", values = FOCUS_MODES,
              order = { "accent", "daylight", "gradient", "class", "custom" },
              desc = "The icon of the quest the minimap arrow points to (click a quest's icon to pick it), and the light behind an icon under the mouse." },
            { type = "color", key = "colors.focus", label = "Custom priority quest color",
              desc = "The priority quest's color while Priority quest color is set to Custom.",
              hidden = function(get) return get("colors.focusMode") ~= "custom" end },
        } },
        { label = "Progress bars", items = {
            { type = "dropdown", key = "colors.barMode", label = "Progress bar color", values = BAR_MODES,
              order = { "accent", "class", "custom" },
              desc = "Accent follows Appearance, including the Daylight gradient." },
            { type = "color", key = "colors.bar", label = "Custom progress bar color",
              desc = "The progress bars' color while Progress bar color is set to Custom.",
              hidden = function(get) return get("colors.barMode") ~= "custom" end },
        } },
      } },
} }
