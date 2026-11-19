-- Default settings for the tooltips.

local _, ns = ...

-- Bar texture and font picked separately for this area (Media.RegisterArea): health bar and tooltip text.
ns.MEDIA_BARS = { "health" }
ns.MEDIA = DaylightUI.Media.RegisterArea("tooltip", "Tooltip", ns.MEDIA_BARS)

ns.DEFAULTS = {
    media = DaylightUI.Media.AreaDefaults(ns.MEDIA_BARS),
    -- "simple": the game's tooltip in the Daylight UI look; "rich": Daylight UI's
    -- own cards drawn over it (Rich/).
    style = "simple",
    richAlpha = 0.95, -- the rich card's background opacity
    pill = "combat", -- a unit as one small line where the tooltip would be: "combat" (and under restrictions), "always", "never"
    pillKey = "shift", -- held, the full card in the pill's place: "shift", "ctrl", "alt", "none"
    anchor = "game", -- "game": at Daylight UI's unlock handle (near the game's spot); "cursor": follows the mouse
    cursorX = 12, -- offset of the cursor tooltip's bottom-left corner from the cursor
    cursorY = 12,
    scale = 1,
    textSize = 12,
    bgAlpha = 0.92,
    -- On by default, unlike the windows: tooltips stay a little more solid
    -- than the shared window opacity, as they always were.
    bgAlphaOwn = true,
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
    barGradient = "frames", -- health bar color: "frames" (class gradient when unit frame health uses one), "gradient", "flat"
    barHeight = 5,
    hideInCombat = false, -- in combat, show unit tooltips only while Shift is held
    fadeOut = false, -- world object tooltips fade out like the game's (off: hide at once)
}
