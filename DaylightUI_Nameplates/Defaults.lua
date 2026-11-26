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
    offsetY = -20, -- offset up (+) or down (-) from the center of the game's plate (older profiles keep 14, DB.KeepPlateHeight)
    range = 60, -- max plate distance in yards (the game's maximum)
    targetScale = true, -- size your target's plate and the others separately (below)
    target = { width = 1, height = 1, scale = 1.15, nameSize = 0 }, -- nameSize: target name (0 = Name size); the rest scale target Width and bar height, plus extra zoom
    others = { width = 1, height = 1, scale = 1 }, -- every other plate while you have a target (off by default: resizing every plate on a target switch cost frames in crowds)
    hoverLight = 0.15, -- hover highlight strength (0 = none; Plate.HOVER)
    targetStyle = "outline", -- target plate highlight: outline, glow or none
    targetAccent = true, -- outline or glow in the accent color; off uses the colors below
    targetLight = "none", -- an animated light on the target outline: "none" or a W.GLOW_STYLES key (W.GlowAround)
    targetOutline = { 0.72, 0.7, 0.66 }, -- outline color (Daylight gray)
    targetGlow = { 0.72, 0.7, 0.66 }, -- glow color
    targetArrows = "none", -- arrows at your target's plate: "none", "sides", "top" (Plate.TARGET_ARROWS)
    targetArrowPaint = "accent", -- "accent" or "custom" (targetArrowColor)
    targetArrowColor = { 0.85, 0.22, 0.20 },
    targetArrowSize = 16,
    groupFocus = false, -- in a group, a double arrow over the enemy most of you are targeting (Manager.CountFocus)
    dimOthers = false, -- fade other plates while you have a target (casting ones stay full)
    dimAlpha = 0.5, -- ...to this opacity
    rangeFade = false, -- fade enemy plates your class's attacks can't reach (Range.SPELLS)
    rangeAlpha = 0.5, -- ...to this opacity
    backAlpha = 0.8, -- opacity of the empty part of health and power bars (Style.BAR_BACK_ALPHA = default); lower also thins the plate's dark backing (Plate.Clear)
    width = 170,
    height = 16,
    castHeight = 14,
    showName = true, -- names on enemy plates
    nameSize = 13,
    shortNames = false, -- long names shortened to initials but the last word ("S. C. Commander"), friendly plates too
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
    threatSolo = false, -- solo too: mobs attacking you in the aggro color, the rest normal
    threatBar = true, -- ...on the health bar fill (the original look)
    threatBorder = false, -- ...on the bar border
    threatGlow = false, -- ...as a glow around the bar
    threatPulse = true, -- threat marks pulse, faster when the mob is about to switch
    threatSize = false, -- each plate's size by its threat state (tanks: small while held, big once lost)
    threatSizeAggro = 0.85, -- ...attacking you
    threatSizeWarn = 1.15, -- ...about to switch
    threatSizeLost = 1.25, -- ...on someone else
    threatPct = false, -- your threat % on the mob beside its bar (in a group or with a pet)
    threatPctColor = "threat", -- "threat" (orange or red when it needs you, else white), "white", "accent", "custom"
    threatPctCustom = { INK.WARN[1], INK.WARN[2], INK.WARN[3] }, -- ...color for "custom"
    threatPctSize = 0, -- 0 = scale with bar height
    mobTarget = false, -- the name of whoever each enemy is attacking, by its plate
    mobTargetColor = "class", -- "class" (players in their class color, others white), "white", "accent", "custom"
    mobTargetCustom = { INK.VALUE[1], INK.VALUE[2], INK.VALUE[3] }, -- ...color for "custom"
    mobTargetSize = 0, -- 0 = a share of the name's size, like the guild line
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
    executeIconPos = "outright", executeIconX = 0, executeIconY = 0,
    percentPos = "right", percentX = 0, percentY = 0,
    levelPos = "left", levelX = 0, levelY = 0,
    threatPctPos = "outtopleft", threatPctX = 0, threatPctY = 0,
    mobTargetPos = "below", mobTargetX = 0, mobTargetY = 0,
    debuffSpot = "above", debuffGrow = "center", debuffX = 0, debuffY = 0,
    ccSpot = "outright", ccX = 0, ccY = 0,
    defensiveSpot = "outright", defensiveX = 0, defensiveY = 0,
    buffSpot = "above", buffGrow = "left", buffX = 0, buffY = 0,
    predictHeals = true,    -- incoming heals, on the health bar
    predictAbsorbs = true,  -- shields, on the health bar
    dotTint = true, -- your DoTs' remaining damage, shaded on the health bar
    dotSkull = true, -- ...plus a skull past the bar end when they'll kill it
    dotsDoesItDie = true, -- with the Does It Die addon installed, its numbers drive the shade and skull (target frame too)
    execute = "off", -- execute range on enemy bars: "auto" (classes with an execute), "on", "off"
    executePct = 0.2, -- ...up to this fraction of health
    executeStyle = "band", -- ...style: "band" (lights up in range), "line" (marker only), "bar" (whole fill lights), "pulse" (band, pulsing), "icon" (your finisher's icon by the bar)
    executeAccent = true, -- ...in the accent color; off uses executeColor
    executeColor = { 0.9, 0.36, 0.26 },
    executeTexture = "flat", -- ...fill: "flat", "bar" (media.execute), "fade" (faint at the low end, full at the line), "stripes", "neon"
    executeStrength = 0.45, -- ...brightness once the enemy is in range
    executeLineSize = 2, -- ...edge line thickness in px (0 = none)
    executeRest = true, -- ...faint band before the enemy is in range
    executeRestStrength = 0.1, -- ...its brightness (1 = as bright as the lit band can be)
    executeGlow = false, -- ...a soft glow round the health bar once in range
    executeSpark = false, -- ...a bright spark on the line once in range
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
    powerGradient = DaylightUI.Style.DefaultStops(), -- ...colors for "customGradient"
    powerText = false, -- power as text on the power bar
    powerFormat = "percent", -- ...written as one of Health.POWER_FORMATS
    powerTextSize = 0, -- ...0 = follows the power bar's height
    minions = true, -- enemy pets and totems as a round badge (turns on the game's switch for their plates)
    minionStyle = "badge", -- ...round "badge", or slim "bar" with the portrait beside it
    minionSize = 30, -- ...badge size
    cc = true, -- crowd control as a larger icon beside the bar
    ccSize = 36,
    defensives = true, -- an enemy's big defensive (Divine Shield, Ice Block...) as a larger icon past it
    defensiveSize = 30,
    buffs = true, -- enemy buffs you can purge or steal
    buffSize = 18,
    maxBuffs = 3,
    castIcon = false, -- spell icon left of the cast bar
    castIconPos = "outleft", -- ...or "outright"
    castX = 0, castY = 0, -- cast bar offset from its spot under the health bar
    castTarget = false, -- who an enemy's cast is aimed at, in their class color, on its cast bar
    castKickMark = false, -- a thin mark on enemy casts where your interrupt comes off cooldown (DUI.Interrupt)
    kickStyle = "blade", -- interrupted cast animation, one of Motion.KICKS
    kickedBy = true, -- briefly show "Kicked by <name>" beside an interrupted cast
    kickedByPos = "right", -- ...right of the cast bar, or "below" it
    -- Friendly plate settings, same meaning as the keys above (see Plate.Cfg).
    -- With enabled off, friendly plates show just the name.
    friendly = {
        enabled = false, height = 4, width = 170,
        barWhen = "always", -- "always", "combat" (only in your fights), "hurt" (in a fight or below full health)
        hideInInstance = false, -- turn off the game's friendly plates in dungeons, raids and battlegrounds (Manager.ApplyInstanceFriends)
        totems = true, -- friendly totems as a round badge in their element's color instead of their name
        totemSize = 0, -- their badge's size, 0 = the enemy badges' (minionSize)
        totemIcon = "portrait", -- "portrait" (the totem itself), "spell" (its spell's icon) or "element"
        totemShape = "round", -- "round" or "square"
        totemBorder = true, -- the ring or edge in the element's color
        percent = false, healthFormat = "percent", percentSign = true, healthSize = 0,
        level = false,
        levelColor = "class", -- "class" (class and reaction, as the name), "white", "accent", "custom"; never by difficulty
        levelCustom = { INK.VALUE[1], INK.VALUE[2], INK.VALUE[3] }, -- ...color for "custom"
        power = false, -- power bar under friendly health bars (who: shared powerShow)
        showName = true, -- names on friendly plates (name-only plates keep theirs)
        nameSize = 13, nameColor = "class", guild = true, role = true,
        -- Name color "custom": a color per kind of friendly name.
        namePlayer = { 0.45, 0.7, 1.0 },    -- a friendly player
        nameNpc = { 0.45, 0.88, 0.45 },     -- a friendly NPC
        nameOther = { 1.0, 0.72, 0.3 }, -- opposite-faction player who isn't flagged, so friendly
        partyName = false, -- one color for your party and raid's names (partyCustom)
        partyCustom = { 0.667, 0.667, 1.0 }, -- the game's party chat blue (names, and the marks below)
        partyMark = "none", -- mark beside party and raid names, which keep their color: "none", "before", "around" (Plate.ShowGroupMark)
        classIcon = "none", -- a player's class icon by the name: "none", "before", "after", "above" (Plate.ShowClassIcon)
        classIconScale = 1.3, -- the icon's size as a share of the name's
        guildColor = "class", guildCustom = { INK.GOOD[1], INK.GOOD[2], INK.GOOD[3] }, guildSize = 0,
        roleColor = "tan", roleCustom = { INK.MONEY[1], INK.MONEY[2], INK.MONEY[3] }, roleSize = 0,
        namePos = "above", nameX = 0, nameY = 0, -- the spot needs the health bar; name-only stays centered, nudged by X and Y
        percentPos = "right", percentX = 0, percentY = 0,
        levelPos = "left", levelX = 0, levelY = 0,
        healthColor = "classGradient", healthCustom = { 0.3, 0.7, 0.35 }, healthGradient = DaylightUI.Style.DefaultStops(),
        myBuffs = false, -- your own buffs and HoTs above the name
        myBuffSize = 18,
        maxMyBuffs = 4,
        myBuffSpot = "above", myBuffGrow = "center", myBuffX = 0, myBuffY = 0,
    },
    healthColor = "classGradient", -- class (players) and reaction, "classGradient", "gradient" by health, "custom" or "customGradient"
    healthCustom = { 0.75, 0.3, 0.28 },
    healthGradient = DaylightUI.Style.DefaultStops(), -- the colors for "customGradient"
    -- Special mobs get their own bar color over Health bar color (threat and tapped
    -- still win). Off by default.
    bossBar = false, bossColor = { 0.95, 0.66, 0.2 }, -- boss (UnitIsBossMob, or a world boss)
    rareBar = false, rareColor = { 0.62, 0.74, 0.95 }, -- rare or rare elite
    questBar = false, questColor = { 0.95, 0.85, 0.3 }, -- a mob your quests still need
    casterBar = false, casterColor = { 0.42, 0.45, 0.95 }, -- mana-using mob
    healthFormat = "percent",
    percentSign = true, -- "62%" rather than "62" when the health text is a percent
    healthSize = 0, -- 0 = scale with bar height
    -- Enemy names: "reaction", "class" (class and reaction), "classGradient", or
    -- "white". Enemy players in class color read like friends, so reaction is the
    -- default. Friendly plates keep "class".
    nameColor = "reaction",
    factionIcon = true, -- opposite faction crest by a player's name, any plate (Plate.ShowFaction)
    pvpIcon = false, -- the same crest by the name of anyone flagged for PvP, NPCs too (Plate.PvPFaction)
    threatFill = "plain", -- "plain" (the three colors below) or "pair" (Gradients' THREAT_ON/WARN/LOST)
    threatAggro = { 0.92, 0.2, 0.18 }, -- attacking you
    threatWarn = { 1.0, 0.55, 0.12 }, -- about to switch targets
    threatLost = { 0.98, 0.84, 0.26 }, -- on someone else: lost, or never had it
    castColor = { 0.78, 0.62, 0.30 },
    castFill = "pair", -- "plain" (castColor), "daylight" (logo gradient), "pair" (Gradients page), "customGradient"
    castGradient = DaylightUI.Style.DefaultStops(), -- the colors for "customGradient"
    slant = true, -- angled bar end
    clickPad = 4, -- extra click area around the name and bar
    stacking = "stack", -- "stack" (plates spread apart), "overlap", or "game" (the game's setting)
    stackFriendly = false, -- stack friendly plates too
}
-- Threat % font: "general" uses the health text's (Plate.MEDIA).
ns.DEFAULTS.media.threatPctFont = "general"
-- Level font, same rule.
ns.DEFAULTS.media.levelFont = "general"
-- The mob's target's font: "general" uses the name's.
ns.DEFAULTS.media.mobTargetFont = "general"
-- The execute range's "Bar texture": "general" uses the one on General > Appearance.
ns.DEFAULTS.media.execute = "general"
-- Bar animation (the core's BarFx.lua) on every plate's health, power and
-- cast bars, friendly plates too. Off: forty moving bars in a fight is busy.
ns.DEFAULTS.barFx = { health = DaylightUI.BarFx.Defaults(), power = DaylightUI.BarFx.Defaults(),
                      cast = DaylightUI.BarFx.Defaults() }
