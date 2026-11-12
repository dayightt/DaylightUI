-- Default settings for the nameplates. Sizes are in the plate's own units.

local _, ns = ...

local INK = DaylightUI.Style.INK

-- Nameplates have their own bar texture and font settings (Media.RegisterArea,
-- Plate.MEDIA): the plate font, plus name, health and cast text that follow it.
ns.MEDIA_BARS = { "health", "cast", "combo", "power" }
ns.MEDIA_FONTS = { "name", "health", "cast" }

-- Spots around the health bar (DaylightUI.Spots). Aura rows and crowd control can
-- only use these, since their icons are taller than the bar. The name and marks
-- can use any spot, including on the bar.
ns.OUTSIDE_SPOTS = { "above", "below", "outleft", "outright", "outtopleft", "outtopright", "outbottomleft", "outbottomright" }

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS, ns.MEDIA_FONTS),
    scale = 1,              -- on top of the UI's scale; the game's plate scale is ignored
    offsetY = 14, -- offset up (+) or down (-) from the center of the game's plate
    range = 60, -- max plate distance in yards (the game's maximum)
    targetScale = true, -- size your target's plate and the others separately (below)
    target = { width = 1, height = 1, scale = 1.15, nameSize = 0 }, -- nameSize: target name (0 = Name size); the rest scale target Width and bar height, plus extra zoom
    others = { width = 1, height = 1, scale = 1 }, -- every other plate while you have a target (off by default: resizing every plate on a target switch cost frames in crowds)
    hoverLight = 0.15, -- hover highlight strength (0 = none; Plate.HOVER)
    targetStyle = "outline", -- target plate highlight: outline, glow or none
    targetAccent = true, -- outline or glow in the accent color; off uses the colors below
    targetOutline = { 0.72, 0.7, 0.66 }, -- outline color (Daylight gray)
    targetGlow = { 0.72, 0.7, 0.66 }, -- glow color
    targetArrows = "none", -- arrows at your target's plate: "none", "sides", "top" (Plate.TARGET_ARROWS)
    targetArrowPaint = "accent", -- "accent" or "custom" (targetArrowColor)
    targetArrowColor = { 0.85, 0.22, 0.20 },
    targetArrowSize = 16,
    dimOthers = false, -- fade other plates while you have a target (casting ones stay full)
    dimAlpha = 0.5, -- ...to this opacity
    backAlpha = 0.8, -- opacity of the empty part of health and power bars (Style.BAR_BACK_ALPHA = default); lower also thins the plate's dark backing (Plate.Clear)
    width = 170,
    height = 16,
    castHeight = 14,
    nameSize = 13,
    percent = true, -- health percent on the bar
    level = true, -- unit level at the bar's other end
    levelColor = "difficulty", -- "difficulty" (the game's gray, green, yellow, orange, red), "white", "accent", "custom"
    levelCustom = { INK.VALUE[1], INK.VALUE[2], INK.VALUE[3] }, -- ...color for "custom"
    levelSize = 0, -- 0 = scale with bar height
    eliteDragon = true, -- dragon on the bar end for elites, rares and bosses
    guild = true, -- player's guild under their name
    role = true, -- NPC title (Skinner, Flight Master...) under its name
    -- Their look. Color: "class" (guild) or "tan" (title), "white" or "custom".
    -- Size 0 scales with nameSize. Friendly plates have their own.
    guildColor = "class", guildCustom = { INK.GOOD[1], INK.GOOD[2], INK.GOOD[3] }, guildSize = 0,
    roleColor = "tan", roleCustom = { INK.MONEY[1], INK.MONEY[2], INK.MONEY[3] }, roleSize = 0,
    threat = false, -- threat colors in a group or with a pet; off until a player (a tank) turns them on
    threatBar = true, -- ...on the health bar fill (the original look)
    threatBorder = false, -- ...on the bar border
    threatGlow = false, -- ...as a glow around the bar
    threatPulse = true, -- threat marks pulse, faster when the mob is about to switch
    threatPct = false, -- your threat % on the mob beside its bar (in a group or with a pet)
    threatPctColor = "threat", -- "threat" (orange or red when it needs you, else white), "white", "accent", "custom"
    threatPctCustom = { INK.WARN[1], INK.WARN[2], INK.WARN[3] }, -- ...color for "custom"
    threatPctSize = 0, -- 0 = scale with bar height
    quest = true, -- marker on quest targets
    questCount = true, -- ...with the objective count (4/10) beside it
    questIcon = false, -- ...as an objective icon (sword, bag, cog, eye) in the quest color (needs the Quests module)
    markerSize = 16, -- raid marker (skull, star...) left of the bar
    -- Placement (Plate.PlaceSpots): a spot around the health bar (DaylightUI.Spots),
    -- a nudge, and for rows a grow direction. Pieces sharing a spot stack outward
    -- from the bar.
    namePos = "above", nameX = 0, nameY = 0,
    questPos = "outleft", questX = 0, questY = 0,
    markerPos = "outleft", markerX = 0, markerY = 0,
    dotSkullPos = "outright", dotSkullX = 0, dotSkullY = 0,
    percentPos = "right", percentX = 0, percentY = 0,
    levelPos = "left", levelX = 0, levelY = 0,
    threatPctPos = "outtopleft", threatPctX = 0, threatPctY = 0,
    debuffSpot = "above", debuffGrow = "center", debuffX = 0, debuffY = 0,
    ccSpot = "outright", ccX = 0, ccY = 0,
    buffSpot = "above", buffGrow = "left", buffX = 0, buffY = 0,
    predictHeals = true,    -- incoming heals, on the health bar
    predictAbsorbs = true,  -- shields, on the health bar
    dotTint = true, -- your DoTs' remaining damage, shaded on the health bar
    dotSkull = true, -- ...plus a skull past the bar end when they'll kill it
    execute = "off", -- execute range on enemy bars: "auto" (classes with an execute), "on", "off"
    executePct = 0.2, -- ...up to this fraction of health
    executeStyle = "band", -- ...style: "band" (lights up in range), "line" (marker only), "bar" (whole fill lights), "pulse" (band, pulsing)
    executeAccent = true, -- ...in the accent color; off uses executeColor
    executeColor = { 0.9, 0.36, 0.26 },
    executeTexture = "flat", -- ...fill: "flat", "bar" (shared bar texture), "fade" (faint at the low end, full at the line)
    executeStrength = 0.45, -- ...brightness once the enemy is in range
    executeLineSize = 2, -- ...edge line thickness in px (0 = none)
    executeRest = true, -- ...faint band before the enemy is in range
    debuffs = true,         -- your debuffs above the bar
    debuffSize = 24,
    maxDebuffs = 6,
    comboPoints = true, -- combo points under your target's plate (rogues, cat druids)
    comboPosition = "below", -- ...under the health bar, or "above" it (the name moves up)
    comboHeight = 5,        -- ...pip height
    comboWidth = 1, -- ...fraction of bar width the row spans (centered)
    comboGap = 3, -- ...gap between pips
    comboBorder = 2,        -- ...outline
    comboSlant = false, -- ...pips angled like the bar end
    power = false, -- mana, rage or energy as a thin bar under the health bar (off by default)
    powerShow = "players", -- ...for "players" (players and mana users), "all" (anyone with power), or "target" only
    powerHeight = 5, -- ...height (same as the combo pips)
    powerGap = 2, -- ...gap under the health bar
    powerColor = "type", -- ...color: "type" (the power type's pair from the Gradients page) or "custom"
    powerCustom = { 0.3, 0.52, 0.95 }, -- ...color for "custom"
    minions = true, -- enemy pets and totems as a round badge (turns on the game's switch for their plates)
    minionStyle = "badge", -- ...round "badge", or slim "bar" with the portrait beside it
    minionSize = 30, -- ...badge size
    cc = true, -- crowd control as a larger icon beside the bar
    ccSize = 36,
    buffs = true, -- enemy buffs you can purge or steal
    buffSize = 18,
    maxBuffs = 3,
    castIcon = false, -- spell icon left of the cast bar
    castIconPos = "outleft", -- ...or "outright"
    castX = 0, castY = 0, -- cast bar offset from its spot under the health bar
    kickStyle = "blade", -- interrupted cast animation, one of Motion.KICKS
    kickedBy = true, -- briefly show "Kicked by <name>" beside an interrupted cast
    kickedByPos = "right", -- ...right of the cast bar, or "below" it
    -- Friendly plate settings, same meaning as the keys above (see Plate.Cfg).
    -- With enabled off, friendly plates show just the name.
    friendly = {
        enabled = false, height = 4, width = 170,
        hideInInstance = false, -- turn off the game's friendly plates in dungeons, raids and battlegrounds (Manager.ApplyInstanceFriends)
        percent = false, healthFormat = "percent", healthSize = 0,
        level = false,
        power = false, -- power bar under friendly health bars (who: shared powerShow)
        nameSize = 13, nameColor = "class", guild = true, role = true,
        -- Name color "custom": a color per kind of friendly name.
        namePlayer = { 0.45, 0.7, 1.0 },    -- a friendly player
        nameNpc = { 0.45, 0.88, 0.45 },     -- a friendly NPC
        nameOther = { 1.0, 0.72, 0.3 }, -- opposite-faction player who isn't flagged, so friendly
        partyName = false, -- one color for your party and raid's names (partyCustom)
        partyCustom = { 0.667, 0.667, 1.0 }, -- the game's party chat blue (names, and the marks below)
        partyMark = "none", -- mark beside party and raid names, which keep their color: "none", "before", "around" (Plate.ShowGroupMark)
        guildColor = "class", guildCustom = { INK.GOOD[1], INK.GOOD[2], INK.GOOD[3] }, guildSize = 0,
        roleColor = "tan", roleCustom = { INK.MONEY[1], INK.MONEY[2], INK.MONEY[3] }, roleSize = 0,
        namePos = "above", nameX = 0, nameY = 0, -- with the health bar on; name-only stays centered
        percentPos = "right", percentX = 0, percentY = 0,
        levelPos = "left", levelX = 0, levelY = 0,
        healthColor = "classGradient", healthCustom = { 0.3, 0.7, 0.35 },
        myBuffs = false, -- your own buffs and HoTs above the name
        myBuffSize = 18,
        maxMyBuffs = 4,
        myBuffSpot = "above", myBuffGrow = "center", myBuffX = 0, myBuffY = 0,
    },
    healthColor = "classGradient", -- class (players) and reaction, "classGradient", "gradient" by health, or "custom"
    healthCustom = { 0.75, 0.3, 0.28 },
    -- Special mobs get their own bar color over Health bar color (threat and tapped
    -- still win). Off by default.
    bossBar = false, bossColor = { 0.95, 0.66, 0.2 }, -- boss (UnitIsBossMob, or a world boss)
    rareBar = false, rareColor = { 0.62, 0.74, 0.95 }, -- rare or rare elite
    questBar = false, questColor = { 0.95, 0.85, 0.3 }, -- a mob your quests still need
    casterBar = false, casterColor = { 0.42, 0.45, 0.95 }, -- mana-using mob
    healthFormat = "percent",
    healthSize = 0, -- 0 = scale with bar height
    -- Enemy names: "reaction", "class" (class and reaction), "classGradient", or
    -- "white". Enemy players in class color read like friends, so reaction is the
    -- default. Friendly plates keep "class".
    nameColor = "reaction",
    factionIcon = true, -- opposite faction crest by a player's name, any plate (Plate.ShowFaction)
    threatFill = "plain", -- "plain" (the three colors below) or "pair" (Gradients' THREAT_ON/WARN/LOST)
    threatAggro = { 0.92, 0.2, 0.18 }, -- attacking you
    threatWarn = { 1.0, 0.55, 0.12 }, -- about to switch targets
    threatLost = { 0.98, 0.84, 0.26 }, -- on someone else: lost, or never had it
    castColor = { 0.78, 0.62, 0.30 },
    castFill = "pair", -- "plain" (castColor), "daylight" (logo gradient), "pair" (Gradients page)
    slant = true, -- angled bar end
    clickPad = 4, -- extra click area around the name and bar
    stacking = "game", -- "stack" (plates spread apart), "overlap", or "game" (the game's setting)
    stackFriendly = false, -- stack friendly plates too
}
-- Threat % font: "general" uses the health text's (Plate.MEDIA).
ns.DEFAULTS.media.threatPctFont = "general"
-- Level font, same rule.
ns.DEFAULTS.media.levelFont = "general"
