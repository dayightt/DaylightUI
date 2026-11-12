-- Default settings for the info panel. Sizes are in UI units.

local _, ns = ...

-- The XP bar and the meters can pick their own bar texture and font.
ns.MEDIA_BARS = { "xp", "meter" }
ns.MEDIA_FONTS = { "xp", "meter" }
ns.MEDIA = DaylightUI.Media.RegisterArea("panel", "InfoPanel", ns.MEDIA_BARS, ns.MEDIA_FONTS)

local INK = DaylightUI.Style.INK
-- Copy the color, since a saved color is written into its own table.
local function ink(c) return { c[1], c[2], c[3] } end

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS, ns.MEDIA_FONTS),
    xpGain = true,          -- flash the gained XP, show "+N", sweep on level up
    xp = { enabled = true, showText = false, showPercent = false, textSize = 9, gradient = true, classColor = true, height = 11, detached = false, width = 207,
          matchBars = true,     -- when detached, match the main action bar's width
          color = "accent",     -- accent | class | blue | custom (customLo/customHi); classColor = false is the old blue
          customLo = { 0.55, 0.38, 0.12 }, customHi = { 0.98, 0.78, 0.35 },
          ticks = false,        -- 20 segments per level
          banked = true,        -- show XP from completed quests ahead of the fill
          tipSide = "auto",     -- auto | left | right | above | below
          ownFade = false,      -- false: fades with the panel; true: uses the fade below
          fade = DaylightUI.Fade.Defaults() },
    -- Standalone reputation bar for the watched faction. Uses the XP bar's
    -- texture and font.
    rep = { enabled = false, width = 207, height = 11, showName = true, showText = false, showPercent = true,
            textSize = 9, gradient = true, tipSide = "auto" },
    meter = { enabled = true, width = 207, rowHeight = 22, mode = "damage", session = "current",
              inGroup = false, inCombat = false, inInstance = false, onJoin = "nothing", onInstance = "ask",
              detached = false, height = 196, border = true,   -- border of the detached window
              barColor = "class", gradient = true, barCustom = { 0.72, 0.70, 0.66 }, textSize = 11,
              nameColor = { 1, 1, 1 },
              -- classText colors names and numbers by class, overriding nameColor.
              -- trackAlpha is the opacity of each bar's empty part (0 = fill only).
              -- alphaOwn / alpha give the detached window its own background opacity.
              classText = false, trackAlpha = 1, alphaOwn = false, alpha = 0.85,
              -- Row contents. icons is spec | class | none. showMe keeps your
              -- own row in view.
              rank = true, icons = "spec", showTotal = true, showRate = true, showShare = true, showMe = true,
              rowGap = 1,
              -- header is "always" or "hover" (only on mouseover).
              header = "always", headerTotal = false,
              numbers = "short" },   -- short (12.3K) | full (12,345), used everywhere amounts show
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
               barColor = "class", gradient = true, barCustom = { 0.72, 0.70, 0.66 }, nameColor = { 1, 1, 1 },
               pullLine = true, pullColor = ink(INK.BAD), border = true, trackAlpha = 0.35, header = "always",
               fade = DaylightUI.Fade.Defaults() },
    -- meterSide: which side of the map the meters slide out on. "auto" picks
    -- the side facing the middle of the screen.
    -- alphaOwn / alpha / border: the minimap box's own look, separate from
    -- panelAlpha and panelBorder.
    -- drawerOrder: the addon drawer's buttons in the order the player dragged them.
    map = { enabled = true, size = 226, buttons = true, drawer = true, drawerOrder = {}, meterSide = "auto",
             alphaOwn = false, alpha = 0.85, border = true,
             clock = { enabled = true, twentyFour = true, useServer = false, textSize = 11, color = ink(INK.VALUE) },
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
             goldChars = "all" },         -- gold tooltip lists "all" characters or only your "faction"
    -- Data bar along the bottom of the screen. Up to four texts on each side
    -- of the center one; "none" leaves a slot empty.
    databar = { enabled = false, widthPct = 60, height = 24, textSize = 12, icons = true, labels = false, line = true,
                alphaOwn = false, alpha = 0.85, borderAlpha = 0, angled = true,
                left1 = "location", left2 = "coords", left3 = "xp", left4 = "durability",
                center = "time",
                right1 = "bags", right2 = "social", right3 = "gold", right4 = "system",
                fade = DaylightUI.Fade.Defaults() },
    tracker = { enabled = true, fade = DaylightUI.Fade.Defaults() },
    -- Background opacity of the panel and meter windows. Uses the general
    -- window opacity unless panelAlphaOwn is set.
    panelAlphaOwn = false,
    panelAlpha = 0.85,
    panelBorder = true,
    fade = DaylightUI.Fade.Defaults(),   -- also covers a detached meter and the XP bar without its own fade
}

-- The minimap box used to share the panel's background and border. Copy a
-- profile's custom panel look onto the new map settings once.
function ns.UpgradeMapBox(p)
    if type(p) ~= "table" or p.mapBox1 or type(p.modules) ~= "table" then return end
    p.mapBox1 = true
    local ip = p.modules.InfoPanel
    if type(ip) ~= "table" then return end
    local map = type(ip.map) == "table" and ip.map or {}
    for from, to in pairs({ panelAlphaOwn = "alphaOwn", panelAlpha = "alpha", panelBorder = "border" }) do
        if ip[from] ~= nil and map[to] == nil then map[to] = ip[from] end
    end
    if next(map) ~= nil then ip.map = map end
end
DaylightUI.DB.RegisterUpgrade(ns.UpgradeMapBox)
