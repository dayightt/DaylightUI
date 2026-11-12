-- Default settings for the quest tracker. Sizes are in UI units. Colors are
-- { r, g, b } and already softened (shown as-is).

local _, ns = ...
local INK = DaylightUI.Style.INK
-- copies a text color (Style.INK), since a saved color is written into its own table
local function ink(c) return { c[1], c[2], c[3] } end

-- Area-specific bar textures and font (Media.RegisterArea): the progress bars and
-- one font for the tracker text.
ns.MEDIA_BARS = { "progress" }
ns.MEDIA = DaylightUI.Media.RegisterArea("quests", "Quests", ns.MEDIA_BARS)

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS),
    width = 226,              -- used when matchMap is off or there's no minimap
    matchMap = true,          -- same width as the info panel's minimap
    maxHeight = 560,          -- the list scrolls past this
    zoneNames = true,
    compact = false,
    itemSide = "left",        -- item button column: left or right of the list
    box = false,
    boxAlphaOwn = false,    -- off: use the general window opacity
    boxAlpha = 0.85,
    boxBorder = true,
    capsTitles = false,
    questLevels = false,      -- "[15] Title" in the tracker
    questTags = true,         -- small tag after an elite, dungeon, raid or PvP quest's title
    questParty = true,        -- party members on a quest, at the end of its line
    hideDone = false,
    filter = "all",           -- all (tracked) | zone | log (every quest in the log, without adding watches)
    sort = "recent",          -- recent (a quest that progresses moves to the top with its zone) | zone | level | near | ready
    foldReady = false,        -- a ready quest shows only its title (never for timed ones)
    instances = "zone",       -- in a dungeon or raid: zone (this zone only) | fold | hide | none (applied on the loading screen)
    objColors = "plain",      -- objective text: plain | done (green once done) | count (red to green)
    hoverDim = true,          -- dim the other quests while one is hovered
    rowTips = true,           -- show a hovered quest's tooltip beside the tracker
    growUp = false,           -- list grows upward from the handle (for a tracker placed low)
    emptyHeader = false,      -- show the Quests header with nothing tracked
    sound = true,             -- when a quest is ready to turn in
    tracker = true,           -- with Questie on: this tracker (off = Questie's tracker; Choice.lua)
    -- What each click on a quest does (Clicks.ACTIONS). Right-click is always the menu.
    clicks = { click = "map", shift = "untrack", ctrl = "priority", alt = "none" },
    journal = true,           -- replace the world map's quest log with the journal (Journal.lua)
    journalTipBeside = true,  -- journal row tooltip beside the panel like the game's (off = at the mouse)
    journalHoverIcons = true, -- hovering a quest name or Questie icon grows its icons and fades the others
    journalSort = "log",      -- per-zone order: log | level | ready | watched
    journalHereFirst = true,  -- the current zone at the top of the list
    journalTextSize = 13,     -- a row's title size; level and progress 1 smaller, zone names 2 bigger
    journalRowHeight = 24,
    journalLevels = true,     -- level in front of each quest
    journalProgress = true,   -- 0/6 or Ready on the right of each row
    journalDots = true,       -- dot on tracked quests
    journalZoneCaps = true,   -- zone names in capitals
    journalOpacity = 0.94,    -- panel background opacity
    progress = true,          -- redraw the game's yellow quest progress lines ("slain: 5/8") (Progress.lua)
    progressScale = 1,        -- scale of the whole popup
    progressHold = 1.8,       -- seconds a popup line stays before fading (Progress.HOLD)
    nav = {
        marker = false,       -- replace the game's in-world marker (Nav.lua); off by default
        style = "beacon",     -- beacon | pillar | minimal
        scale = 1,
        distance = true,      -- yards under the marker
        fightFade = true,     -- softer in combat (marker and arrow)
        arrow = false,        -- TomTom-style arrow to the nearest objective still needed (Arrow.lua, needs QuestieDB)
        arrowScale = 1,
        arrowColorMode = "accent",   -- accent | class | custom
        arrowColor = { 0.72, 0.70, 0.66 },
        arrowGlow = true,            -- soft glow behind the arrow
        arrowGlowAlpha = 0.35,
        arrowDistance = true,        -- yards under the arrow
        trail = true,         -- breadcrumbs on the ground from the player to the marker
    },
    -- An NPC's quests in its tooltip, from Questie's list (GiverTips.lua, needs Questie)
    mapQuests = { tooltip = true },
    sizes = { header = 12, title = 12, objective = 11, zone = 10 },
    colors = {
        headerMode = "custom",      -- custom | accent | class | gradient
        header = { 1, 1, 1 },
        headerLineMode = "accent",
        headerLine = { 0.78, 0.78, 0.8 },
        zoneMode = "custom",
        zone = ink(INK.LABEL),
        titleMode = "difficulty",   -- difficulty | one
        title = { 1, 0.82, 0 },
        objective = ink(INK.TEXT),
        count = ink(INK.VALUE),
        done = { 0.52, 0.76, 0.52 },       -- Style.INK.GOOD, softer
        tick = { 0.44, 0.75, 0.45 },
        ready = { 1, 0.82, 0.2 },
        elite = { 1, 0.82, 0.2 },          -- quest tag colors (Look.NewTag), by kind
        dungeon = { 0.62, 0.77, 1 },
        raid = { 0.76, 0.62, 1 },
        pvp = { 0.95, 0.47, 0.44 },
        failed = { 0.89, 0.33, 0.30 },
        timer = { 0.91, 0.69, 0.29 },
        timerUrgent = { 0.89, 0.33, 0.30 },
        focusMode = "accent",       -- priority quest icon: accent | daylight | gradient | class | custom
        focus = { 0.64, 0.37, 0.78 },
        barMode = "accent",         -- accent | class | custom
        bar = { 0.72, 0.70, 0.66 },
    },
    fade = DaylightUI.Fade.Defaults(),
}

-- recentFirst (on/off) was replaced by sort; off meant the game's zone order.
function ns.UpgradeSort(p)
    if type(p) ~= "table" or type(p.modules) ~= "table" then return end
    local q = p.modules.Quests
    if type(q) ~= "table" or q.recentFirst == nil then return end
    if q.recentFirst == false and q.sort == nil then q.sort = "zone" end
    q.recentFirst = nil
end
DaylightUI.DB.RegisterUpgrade(ns.UpgradeSort)
