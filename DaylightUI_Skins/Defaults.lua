-- Default settings for the window skins: which packs are on.

local _, ns = ...

ns.DEFAULTS = {
    packs = { npc = true, social = true, collections = true, system = true },
    windowAlphaOwn = false, -- off: follows the general window opacity
    windowAlpha = 0.85,
    ccAlert = true, -- the crowd control alert in Daylight UI style; off = the game's own (Packs/LossOfControl.lua)
    breathSlant = true, -- angled end on the breath bar; off = straight (Packs/Breath.lua)
    mapReveal = false, -- dim the world map's unexplored areas (MapReveal.lua)
    mapLogBeside = true, -- when maximized, open the quest list beside the map instead of shrinking it
    mapRevealDim = 0.6, -- brightness of the unexplored areas
    mapLevels = true, -- the hovered zone's level range after its name (MapLevels.lua)
    mapDungeons = true, -- world map pins (MapPins.lua): dungeon and raid entrances
    mapFlights = true,        -- your faction's flight masters
    mapTravel = true,         -- boats and zeppelins
    mapFlightsAll = false, -- the other faction's flight masters too
    mapPinScale = 1, -- pin size
    mapPinAlpha = 1, -- pin opacity
    addonSkins = {}, -- [switch key] = true (filled by Engine.AddonSwitch); false leaves that addon unskinned
    windowScales = {}, -- [game window name] = scale set with Ctrl + mouse wheel (WindowScale.lua)
    windowSpots = {}, -- [game window name] = dragged position (WindowMove.lua)
    rolls = {
        enabled = true,       -- Daylight UI's own roll window; off = the game's popups in Daylight UI style (Rolls/)
        list = "auto",        -- auto | always | hover | off: when a roll shows who picked what
        compact = true,       -- several rolls up: compact cards
        fightCompact = true,  -- in a fight: compact, lists only under the mouse
        linger = 5,           -- seconds a result stays up
        holdOnHover = true,
        maxShown = 4,
        grow = "up",          -- up | down from the Loot Rolls handle
        width = 300,
        spacing = 6,
        buttonSize = 30,
        buttonWords = true,
        icons = "daylight",   -- daylight | game
        sort = "best",        -- best | picked
        showPass = true,
        rollBars = true,
        ticks = true,
        twins = true,
        timerText = true,
        qualityLine = true,
        winShine = true,
    },
}
