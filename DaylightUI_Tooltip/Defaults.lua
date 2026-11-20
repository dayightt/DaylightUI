-- Default settings for the tooltips.

local _, ns = ...

-- Bar texture and fonts picked separately for this area (Media.RegisterArea):
-- the health bar, the tooltip text, and the titles and small text, which
-- follow the tooltip font until given their own.
ns.MEDIA_BARS = { "health" }
ns.MEDIA_FONTS = { "title", "small" }
ns.MEDIA = DaylightUI.Media.RegisterArea("tooltip", "Tooltip", ns.MEDIA_BARS, ns.MEDIA_FONTS)
for _, k in ipairs(ns.MEDIA_FONTS) do
    DaylightUI.Media.RegisterSlot(ns.MEDIA.fonts[k], "Tooltip", "media." .. k .. "Font", "font", ns.MEDIA.font)
end

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS, ns.MEDIA_FONTS),
    -- "simple": the game's tooltip in the Daylight UI look; "rich": Daylight UI's
    -- own cards drawn over it (Rich/).
    style = "simple",
    pill = "combat", -- a unit as one small line where the tooltip would be: "combat" (and under restrictions), "always", "never"
    pillKey = "shift", -- held, the full card in the pill's place: "shift", "ctrl", "alt", "none"
    portraits = true, -- a creature's face and a player's class icon at the top of their card
    -- Other addons' lines on the rich card (Rich/Foreign.lua): "own" (their
    -- own area at the bottom), "mixed" (in with the card's rows), "hidden".
    addonLines = "own",
    -- Which kinds of other addons' lines get a look of their own; off, they're
    -- repainted like any other line.
    addonAdapters = { questie = true, prices = true, score = true },
    anchor = "game", -- "game": at Daylight UI's unlock handle (near the game's spot); "cursor": follows the mouse
    cursorX = 12, -- offset of the cursor tooltip's bottom-left corner from the cursor
    cursorY = 12,
    scale = 1,
    textSize = 12,   -- every line
    titleSize = 14,  -- a name, an item's name, a spell's name
    smallSize = 11,  -- sub lines, the quote, small facts
    dpsSize = 14,    -- a weapon's damage per second on the Rich card
    -- Their border, shadow and background. By design tooltips are a little
    -- more solid than the windows, also on the global style.
    frameStyle = DaylightUI.Style.LookDefaults({ windowAlpha = 0.92 }),
    classColors = true,     -- players' names in their class color
    classBorder = true, -- class-colored border too
    borderGradient = false, -- border uses the unit's class (or reaction) gradient
    showTarget = true, -- a "Target:" line showing who the unit is targeting
    guildRank = true,       -- a player's rank after their guild
    buffs = false, -- a friendly player's buffs as icons (out of combat only; secret in combat)
    greenStats = true, -- shorten items' green "Equip:" lines ("+1% Hit")
    itemLevel = false,      -- an "Item Level" line on weapons and armor
    stackSize = false,      -- "Stacks to 20" on items that stack
    showIDs = false,        -- an "Item ID" / "Spell ID" line on items, spells and auras
    qualityBorder = true, -- item border in its quality color
    healthBar = true,
    barGradient = "frames", -- health bar color: "frames" (a gradient when unit frame health uses one), "gradient", "flat", "customGradient"
    barStops = DaylightUI.Style.DefaultStops(), -- ...the colors for "customGradient"
    barHeight = 5,
    hideInCombat = false, -- in combat, show unit tooltips only while Shift is held
    fadeOut = false, -- world object tooltips fade out like the game's (off: hide at once)
}

-- Titles and small text used to be the text size plus 2 and minus 1. A
-- profile that changed the text size before they had sizes of their own
-- keeps them where they were. Runs once per profile (tipUpgrade), on full or
-- sparse settings alike.
function ns.UpgradeSizes(p)
    if type(p) ~= "table" or type(p.modules) ~= "table" then return end
    local t = p.modules.Tooltip
    if type(t) ~= "table" or (tonumber(t.tipUpgrade) or 0) >= 1 then return end
    t.tipUpgrade = 1
    local text = tonumber(t.textSize)
    if not text or text == ns.DEFAULTS.textSize then return end
    if t.titleSize == nil or t.titleSize == ns.DEFAULTS.titleSize then t.titleSize = text + 2 end
    if t.smallSize == nil or t.smallSize == ns.DEFAULTS.smallSize then t.smallSize = text - 1 end
end
DaylightUI.DB.RegisterUpgrade(ns.UpgradeSizes)
