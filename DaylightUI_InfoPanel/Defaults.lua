-- Default settings for the info panel. Sizes are in UI units.

local _, ns = ...

-- The XP bar and the meters can pick their own bar texture and font.
ns.MEDIA_BARS = { "xp", "meter" }
ns.MEDIA_FONTS = { "xp", "meter" }
ns.MEDIA = DaylightUI.Media.RegisterArea("panel", "InfoPanel", ns.MEDIA_BARS, ns.MEDIA_FONTS)

local INK = DaylightUI.Style.INK
-- Copy the color, since a saved color is written into its own table.
local function ink(c) return { c[1], c[2], c[3] } end

-- The experience bar's own gradient starts as its old amber pair, then the
-- usual custom gradient colors past the second.
ns.XP_STOPS = DaylightUI.Style.DefaultStops()
ns.XP_STOPS.count, ns.XP_STOPS.c1, ns.XP_STOPS.c2 = 2, { 0.55, 0.38, 0.12 }, { 0.98, 0.78, 0.35 }

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS, ns.MEDIA_FONTS),
    xpGain = true,          -- flash the gained XP, show "+N", sweep on level up
    xp = { enabled = true, gameBar = false, showText = false, showPercent = false, textSize = 9, gradient = true, classColor = true, height = 11, detached = false, width = 207,
          matchBars = true,     -- when detached, match the main action bar's width
          color = "accent",     -- accent | class | blue | custom (customGradient); classColor = false is the old blue
          customGradient = ns.XP_STOPS,
          ticks = false,        -- 20 segments per level
          banked = true,        -- show XP from completed quests ahead of the fill
          bankedColor = ink(INK.GOOD), restedColor = { 0.58, 0.32, 0.88 },
          tipSide = "auto",     -- auto | left | right | above | below
          orientation = "horizontal",   -- horizontal | vertical (only when detached)
          ownFade = false,      -- false: fades with the panel; true: uses the fade below
          shell = { own = false, borderPx = 4, cornerPx = 6, shadowPx = 4 },   -- its own border (Panel.Look)
          barFx = DaylightUI.BarFx.Defaults(),   -- bar animation (the core's BarFx.lua)
          fade = DaylightUI.Fade.Defaults() },
    -- Standalone reputation bar for the watched faction. Uses the XP bar's
    -- texture and font.
    rep = { enabled = false, width = 207, height = 11, showName = true, showText = false, showPercent = true,
            textSize = 9, gradient = true, tipSide = "auto", orientation = "horizontal",
            shell = { own = false, borderPx = 4, cornerPx = 6, shadowPx = 4 },
            barFx = DaylightUI.BarFx.Defaults() },
    meter = { enabled = true, width = 207, rowHeight = 22, mode = "damage", session = "current",
              inGroup = false, inCombat = false, inInstance = false, onJoin = "nothing", onInstance = "ask",
              detached = false, height = 196,
              barColor = "class", gradient = true, barCustom = { 0.72, 0.70, 0.66 }, barGradient = DaylightUI.Style.DefaultStops(), textSize = 11,
              -- nameColorBy: "custom" paints names in nameColor, "class" in
              -- each player's class color. classText colors names and numbers
              -- by class, overriding both.
              nameColor = { 1, 1, 1 }, nameColorBy = "custom",
              -- trackAlpha is the opacity of each bar's empty part (0 = fill only).
              -- look: the detached window's border, shadow and background.
              classText = false, trackAlpha = 1, frameStyle = DaylightUI.Style.LookDefaults(),
              -- Row contents. icons is spec | class | none. showMe keeps your
              -- own row in view.
              rank = false, icons = "class", showTotal = true, showRate = true, showShare = true, showMe = true,
              rowGap = 1, angled = true,   -- angled: the fill's leading edge cut at an angle
              -- angledLeft: the bars' left end cut too; flipLeft/flipRight: that end leans the other way.
              angledLeft = false, flipLeft = false, flipRight = false,
              -- header is "always" or "hover" (only on mouseover).
              header = "always", headerTotal = false,
              numbers = "short",   -- short (12.3K) | full (12,345), used everywhere amounts show
              -- false: every damage meter fades with the panel; true: they all
              -- use the fade below, the one inside the panel too.
              ownFade = false, fade = DaylightUI.Fade.Defaults() },
    -- The Meters options page uses keys like win.<key> that point at the
    -- selected window. This lookup supplies a default of the right type for
    -- any of those keys.
    win = setmetatable({}, { __index = function(_, k)
        local W, D = ns.Windows, ns.DEFAULTS
        for _, t in ipairs({ D.meter, D.threat, W and W.TEMPLATE.meter, W and W.TEMPLATE.threat, W and W.TEMPLATE.summary }) do
            if type(t) == "table" and t[k] ~= nil then return t[k] end
        end
    end }),
    -- Saved position of the breakdown window.
    breakdownWin = {},
    -- Last channel and line count used to report the meter.
    report = { channel = "party", lines = 5 },
    -- Extra meter windows by id. Missing keys fall back to the window kind's
    -- template. The old meter2 setting is upgraded into one of these.
    -- sameFight: picking an earlier fight in one window applies to all
    -- windows on Current. backToCurrent: a pull switches back to the live fight.
    meters = { order = {}, next = 1, sameFight = true, backToCurrent = true,
               windows = setmetatable({}, { __index = function(_, id)
                   return ns.Windows and ns.Windows.TemplateFor(id)
               end }) },
    -- Threat meter, which slides out next to the damage meter.
    -- auto: "group" opens it in combat in a group or with a pet, "tank" only
    -- when you tank, "off" only from its tab.
    -- at: "left" hangs on the meter's outer side, "below" runs along its
    -- bottom (belowRows tall), "free" is a movable window.
    -- barColor: class | threat (colored by how close each row is) | custom.
    -- header: mob name and your percent on top ("always" | "off").
    threat = { enabled = true, auto = "group", at = "left", belowRows = 3, width = 170, rowHeight = 16, rows = 6, textSize = 10,
               barColor = "class", gradient = true, barCustom = { 0.72, 0.70, 0.66 }, barGradient = DaylightUI.Style.DefaultStops(), nameColor = { 1, 1, 1 }, nameColorBy = "custom",
               pullLine = true, pullColor = ink(INK.BAD), frameStyle = DaylightUI.Style.LookDefaults(), trackAlpha = 0.35, header = "always", angled = true,
               fade = DaylightUI.Fade.Defaults() },
    -- meterSide: which side of the map the meters slide out on. "auto" picks
    -- the side facing the middle of the screen.
    -- look: the minimap box's border, shadow and background, separate from
    -- the panel's.
    -- drawerOrder: the addon drawer's buttons in the order the player dragged them.
    -- shape: "square" or "round" (a rotating map is always round).
    -- noBox: a round map stands on its own, without the square box round it.
    map = { enabled = true, size = 226, shape = "square", noBox = false, buttons = true, drawer = true, drawerOrder = {}, meterSide = "auto",
             frameStyle = DaylightUI.Style.LookDefaults(),
             clock = { enabled = true, twentyFour = true, seconds = false, useServer = false, textSize = 11, color = ink(INK.VALUE) },
             fps = { enabled = false, textSize = 11, color = ink(INK.VALUE) },      -- next to the clock
             coords = { enabled = true, textSize = 11, color = ink(INK.VALUE) },    -- top of the map
             -- Zone name. colorBy "pvp" uses the zone's PvP color, "custom" uses `color`.
             location = { enabled = true, textSize = 11, colorBy = "pvp", color = ink(INK.VALUE) } },
    -- Data text strip under the minimap, with 3 to 5 slots. labels shows the
    -- small words ("Bags", "Guild") before the numbers.
    data = { enabled = true, count = 4, textSize = 10, labels = true,
             slot1 = "gold", slot2 = "durability", slot3 = "bags", slot4 = "system", slot5 = "social",
             volumeChannel = "master",    -- set from the volume text's right-click menu
             critKind = "auto",           -- auto (by class), attack, ranged or spell
             apKind = "auto",             -- auto (ranged for hunters), attack or ranged
             goldChars = "all",           -- gold tooltip lists "all" characters or only your "faction"
             soulBag = false,             -- the Soul Shards text shows the soul bag's size too
             numberColor = "accent", numberCustom = ink(INK.VALUE),   -- accent, white, class or custom
             ownFade = false,             -- false: fades with the panel; true: uses the fade below
             fade = DaylightUI.Fade.Defaults() },
    -- Data bar along the bottom of the screen. Up to four texts on each side
    -- of the center one; "none" leaves a slot empty.
    databar = { enabled = false, widthPct = 60, height = 24, textSize = 12, icons = true, labels = false, line = true,
                -- No border by default: on a strip this thin the top accent line is enough.
                frameStyle = DaylightUI.Style.LookDefaults({ borderAlpha = 0, heavyBorder = false }), angled = true,
                -- Each end on its own: angled is the left end, angledRight the right one
                -- (a core step split the old one switch, DB.SplitBarEnds); flipLeft and
                -- flipRight lean that end the other way, its bottom corner out.
                angledRight = true, flipLeft = false, flipRight = false,
                left1 = "location", left2 = "coords", left3 = "xp", left4 = "durability",
                center = "time", numberColor = "accent", numberCustom = ink(INK.VALUE),
                right1 = "bags", right2 = "social", right3 = "gold", right4 = "system",
                fade = DaylightUI.Fade.Defaults() },
    tracker = { enabled = true, fade = DaylightUI.Fade.Defaults() },
    -- The XP bar's box and, without a minimap, the meter's: border, shadow
    -- and background.
    frameStyle = DaylightUI.Style.LookDefaults(),
    fade = DaylightUI.Fade.Defaults(),   -- also covers a detached meter and the XP bar without its own fade
}

-- The experience bar's custom gradient was a pair (customLo, customHi) before
-- it took up to five colors. A profile's own pair moves into its first two.
function ns.UpgradeXPStops(p)
    if type(p) ~= "table" or p.xpStops1 or type(p.modules) ~= "table" then return end
    p.xpStops1 = true
    local xp = type(p.modules.InfoPanel) == "table" and p.modules.InfoPanel.xp
    if type(xp) ~= "table" then return end
    local lo, hi = xp.customLo, xp.customHi
    xp.customLo, xp.customHi = nil, nil
    if type(lo) ~= "table" and type(hi) ~= "table" then return end
    local stops = type(xp.customGradient) == "table" and xp.customGradient or {}
    if type(lo) == "table" then stops.c1 = { lo[1], lo[2], lo[3] } end
    if type(hi) == "table" then stops.c2 = { hi[1], hi[2], hi[3] } end
    xp.customGradient = stops
end
DaylightUI.DB.RegisterUpgrade(ns.UpgradeXPStops)
