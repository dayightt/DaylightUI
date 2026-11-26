-- Default settings for the action bars module.

local _, ns = ...

-- Areas with their own bar texture and font (Media.RegisterArea): the Cooldown
-- Manager's bars, and one font for all button text.
ns.MEDIA_BARS = { "cdm" }
ns.MEDIA = DaylightUI.Media.RegisterArea("bars", "ActionBars", ns.MEDIA_BARS)

-- A bar's shape (applied live by Bars.LayoutBar) and its fade (live, via the fade
-- engine).
--   size     button size in percent (the game's 45 px at 100)
--   height   button height in percent of its width (100 = square; action bars only)
--   pad      space between buttons
--   rows     rows (columns when vertical)
--   icons    number of buttons
--   vertical runs down instead of across
--   visible  "always", "combat", "nocombat" or "hidden" (bar 2 and the grids)
--   fade     the fade engine's options (Fade.lua)
local function bar(t)
    t.size = t.size or 70
    t.pad = t.pad or 2
    t.rows = t.rows or 1
    t.vertical = t.vertical or false
    t.fade = t.fade or DaylightUI.Fade.Defaults({ target = true })   -- wake with a target, you're about to press something
    return t
end

-- Bars 2-8 page per stance, form, held modifier or target (Paging.STATES; 0 = no change).
local function paged(t)
    t.paging = { shift = 0, ctrl = 0, alt = 0, help = 0, harm = 0, prowl = 0, cat = 0, bear = 0, stealth = 0,
                 battle = 0, defensive = 0, berserker = 0, shadowform = 0 }
    t.height = 100
    return bar(t)
end

-- Bar 1's page while a modifier is held or by your target (forms already page it).
local function held(t)
    t.paging = { shift = 0, ctrl = 0, alt = 0, help = 0, harm = 0 }
    t.autoPage = true   -- forms, stances and picked pages swap its buttons (Paging.PageRule)
    t.prowlBar = false  -- a prowling druid's bar 1 stays on the Cat Form page unless this is on
    t.height = 100
    return t
end

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS),
    hideEmpty = true,
    -- The game's bag bar and micro menu: "hidden" or "shown". When shown each can
    -- fade (bagBarFade, microMenuFade). microMenuCorner: if never moved, it starts
    -- in the bottom-right corner instead of the game's spot (used by the presets,
    -- Profiles.PRESETS).
    bagBar = "hidden", microMenu = "hidden", microMenuCorner = false,
    bagBarFade = DaylightUI.Fade.Defaults({ delay = 3 }),
    microMenuFade = DaylightUI.Fade.Defaults({ delay = 3 }),
    padBarsFade = DaylightUI.Fade.Defaults({ delay = 3 }), -- the game's controller crossbar
    -- The totem timers above the player frame (Totems.lua): shown, and how they fade.
    totemTimers = true,
    totemTimersFade = DaylightUI.Fade.Defaults(),
    totemTimersSize = 100,          -- % of the game's size
    totemTimersGap = 2,             -- space between two timers' borders
    totemTimersShowTime = true,
    totemTimersTimePos = "top",     -- top | middle | bottom, as on the buff bar
    totemTimersTimeSize = 11,
    totemTimersSwipe = true,        -- the dark sweep as time runs out
    totemTimersElements = true,     -- each edge in its element's color
    -- The Cooldown Manager layout's fade (CdmRows.FadeFrames). Shown by default; the
    -- campfire's hush reaches it like the bars.
    cdmFade = DaylightUI.Fade.Defaults(),
    -- Bar animation (the core's BarFx.lua) on the Cooldown Manager's bars.
    cdmBarFx = DaylightUI.BarFx.Defaults(),
    skinMenus = true,       -- bag bar and micro menu in the buttons' look (Menus.lua)
    -- The micro menu's icons in that look: "accent" (one sweep along the row),
    -- "class", "custom" (microIconCustom) or "each" (every icon its own color,
    -- microColors by icon name), and the dark tiles behind them.
    microIconColor = "accent",
    microIconCustom = { 1, 1, 1 },
    microColors = {
        character = { 0.60, 0.80, 1.00 }, professions = { 0.90, 0.68, 0.42 },
        talents = { 0.55, 0.88, 0.55 }, spellbook = { 0.72, 0.62, 0.98 },
        achievements = { 0.98, 0.82, 0.35 }, legacy = { 0.92, 0.60, 0.90 },
        quests = { 0.98, 0.88, 0.40 }, housing = { 0.78, 0.86, 0.55 },
        guild = { 0.45, 0.88, 0.62 }, finder = { 0.45, 0.82, 0.95 },
        collections = { 0.98, 0.62, 0.70 }, journal = { 0.92, 0.55, 0.45 },
        help = { 0.50, 0.88, 0.82 }, shop = { 0.98, 0.70, 0.45 }, menu = { 0.90, 0.88, 0.82 },
    },
    microBackgrounds = true,
    microIconSize = 18,     -- px
    microGap = 3,           -- px from the button's edge to its tile
    microHoverGrow = true,  -- the icon swells a little under the mouse
    microOpenMark = "border",   -- an open window's button: "border", "line" or "both"
    microRestAlpha = 1,     -- icon opacity away from the mouse
    cooldowns = true,       -- Cooldown Manager icons in the same look
    cdmKeybinds = false,    -- keybind on every icon (a piece's keyShown overrides it)
    readyPing = true,       -- a button coming off a real cooldown (not the GCD) pops and flashes
    rankUp = true,          -- a newly learned rank replaces the previous one on your bars (RankUp.lua)
    bars = {
        main = held(bar({ icons = 12, visible = "always" })),
        bar2 = paged({ icons = 12, visible = "always" }),
        left = paged({ icons = 12, rows = 2, visible = "always", fade = DaylightUI.Fade.Defaults({ mode = "always", delay = 3, target = true }) }),
        right = paged({ icons = 12, rows = 2, visible = "always", fade = DaylightUI.Fade.Defaults({ mode = "always", delay = 3, target = true }) }),
        -- Bars 5-8 start hidden. Older profiles keep the ones in use
        -- (DB.KeepBars5to8, Bars.HideEmptyOld).
        bar5 = paged({ icons = 12, visible = "hidden" }),
        bar6 = paged({ icons = 12, visible = "hidden" }),
        bar7 = paged({ icons = 12, visible = "hidden" }),
        bar8 = paged({ icons = 12, visible = "hidden" }),
        stance = bar({ size = 60, icons = 10, visible = "always" }),
        pet = bar({ size = 60, icons = 10, visible = "always" }),
        possess = bar({ size = 60, visible = "always" }),
        totem = bar({ size = 60, visible = "always" }),
    },
    -- The buttons' look, applied live.
    look = {
        border = 3,                          -- edge width in screen pixels
        keybind = true, keybindSize = 12,
        countSize = 11,
        macroNames = true,
        pressed = { 0, 0, 0 }, pressedAlpha = 0.3,
        dip = true,                          -- a pressed icon sinks in
        highlight = { 1, 1, 1 }, highlightAlpha = 0.12,
        checked = "accent", checkedColor = { 0.72, 0.70, 0.66 }, checkedAlpha = 0.3,
        -- An active spell's lit border and glow (Skin.PaintActive).
        checkedBorder = false, checkedGlow = false,
        checkedBorderMode = "accent", checkedBorderColor = { 1, 1, 1 },
        proc = "accent", procColor = { 1.0, 0.82, 0.25 },
        range = "fade", rangeColor = { 0.9, 0.25, 0.22 },
        cooldownAlpha = 0.7,
        keybindPos = "topright", countPos = "bottomright",
        macroSize = 9,
        cooldownNumbers = true, cooldownSize = 14,
        shortKeys = true,
        tooltips = "always",                 -- "nocombat" or "never"
        shape = "square",                    -- or a Skin.SHAPES name (make_shapes.py)
        borderStyle = "daylight",            -- "daylight" (the band), "flat" (an outline) or "none"
        corners = "round",                   -- "round" (Appearance's corners) or "square"
        shadow = true,
        zoom = 0,                            -- extra icon crop as a share of the icon (0-0.4)
        borderColor = "shell",               -- "shell", "accent", "class" or "custom"
        borderCustom = { 0.72, 0.70, 0.66 },
        swipeColor = { 0, 0, 0 },            -- cooldown shade (cooldownAlpha is its opacity)
        edge = "off",                        -- cooldown edge line: "off", "accent", "class", "custom"
        edgeColor = { 1, 1, 1 },
        keybindColor = { 0.86, 0.82, 0.74 }, -- warm, a touch brighter than INK.LABEL (Skin.HOTKEY)
        countColor = { 1, 1, 1 },
        macroColor = { 1, 1, 1 },
        cooldownTextColor = { 1, 1, 1 },
        -- Text offsets in px from their default spot.
        keybindX = 0, keybindY = 0, countX = 0, countY = 0,
        macroX = 0, macroY = 0, cooldownX = 0, cooldownY = 0,
        -- Each spell's cost on its button (Skin.UpdateCost): off until switched on.
        costs = false, costSize = 12, costPos = "bottomleft",
        costColor = "power",                 -- the power's own color, or "custom"
        costCustom = { 0.55, 0.7, 1 },
        costX = 0, costY = 0,
        -- A panel behind the whole bar (Bars.PaintBack).
        -- The border lit while hovered / pressed, in the accent, your class color
        -- or a custom color (hoverBorderColor / pressBorderColor).
        hoverBorder = false, hoverBorderMode = "accent", hoverBorderColor = { 1, 1, 1 },
        pressBorder = false, pressBorderMode = "accent", pressBorderColor = { 1, 1, 1 },
        -- On a real cooldown (not the global one): gray, and this opacity.
        cdGray = false, cdAlpha = 1,
        back = false, backColor = { 0.06, 0.055, 0.05, 0.6 }, backBorder = true, backPad = 4,
    },
    -- Per-bar look overrides on top of `look` (Skin.LookFor). Only what was changed
    -- for that bar, keyed by bar (Bars.DEFS keys) or "cdm" (the Cooldown Manager).
    barLooks = {},
}

-- The settings in use: the module's once enabled, else the table the bars read
-- while the files load (Bars.lua sets ns.db).
function ns.Settings()
    return (ns.module and ns.module.db) or ns.db
end

-- Settings from before these options: the hide toggles. The grids' old shared fade
-- toggle is handled by the fade upgrade (FadeUpgrade.lua).
function ns.Migrate(db)
    db.skin = nil       -- the "button style off" choice was removed
    if db.hideBags == false then db.bagBar = "shown" end
    if db.hideMicro == false then db.microMenu = "shown" end
    db.hideBags, db.hideMicro = nil, nil
end

-- Upgrades for saved action bar settings, one profile at a time. Runs on the active
-- profile before the bars first read it (Bars.lua), and from the core on a new
-- profile copied from another (DB.RunUpgrades). Each step runs once per profile
-- (barsUpgrade holds the last one done) and works on full or sparse tables alike.
-- A step gets the profile's action bar settings and its positions.
ns.BARS_UPGRADE = {
    -- 1: the totem bar's size and spacing join the other bars' settings.
    function(ab)
        local old = ab.totemBar
        if type(old) ~= "table" then return end
        if type(ab.bars) ~= "table" then ab.bars = {} end
        if type(ab.bars.totem) ~= "table" then ab.bars.totem = {} end
        if type(old.size) == "number" then ab.bars.totem.size = old.size end
        if type(old.pad) == "number" then ab.bars.totem.pad = old.pad end
    end,
    -- 2: the old totem bar settings are removed (step 1 carried them over).
    function(ab) ab.totemBar = nil end,
}

-- p = a profile's data { modules = {...}, ... }.
function ns.UpgradeBars(p)
    if type(p) ~= "table" then return end
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.positions) ~= "table" then p.positions = {} end
    local ab = p.modules.ActionBars
    if type(ab) ~= "table" then
        ab = {}
        p.modules.ActionBars = ab
    end
    for i = (tonumber(ab.barsUpgrade) or 0) + 1, #ns.BARS_UPGRADE do
        ns.BARS_UPGRADE[i](ab, p.positions)
        ab.barsUpgrade = i
    end
end

DaylightUI.DB.RegisterUpgrade(ns.UpgradeBars)
