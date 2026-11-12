-- Default settings for the window skins: which packs are on.

local _, ns = ...

ns.DEFAULTS = {
    packs = { npc = true, social = true, collections = true, system = true },
    windowAlphaOwn = false, -- off: follows the general window opacity
    windowAlpha = 0.85,
    breathSlant = true, -- angled end on the breath bar; off = straight (Packs/Breath.lua)
    mapReveal = false, -- dim the world map's unexplored areas (MapReveal.lua)
    mapLogBeside = true, -- when maximized, open the quest list beside the map instead of shrinking it
    mapRevealDim = 0.6, -- brightness of the unexplored areas
    mapDungeons = true, -- world map pins (MapPins.lua): dungeon and raid entrances
    mapFlights = true,        -- your faction's flight masters
    mapTravel = true,         -- boats and zeppelins
    mapFlightsAll = false, -- the other faction's flight masters too
    mapPinScale = 1, -- pin size
    mapPinAlpha = 1, -- pin opacity
    addonSkins = {}, -- [switch key] = true (filled by Engine.AddonSwitch); false leaves that addon unskinned
    windowScales = {}, -- [game window name] = scale set with Ctrl + mouse wheel (WindowScale.lua)
    windowSpots = {}, -- [game window name] = dragged position (WindowMove.lua)
}
