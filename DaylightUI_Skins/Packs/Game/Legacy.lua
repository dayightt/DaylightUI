-- The game's own Legacy window, in the Daylight UI look, for players who pick it over
-- Daylight UI's (Win.Swap). Never walked while Daylight UI's window covers it.

local _, ns = ...
local Engine = ns.Engine

local function covered()
    local W = DaylightUI.Legacy and DaylightUI.Legacy.Window
    return type(W) == "table" and type(W.Covers) == "function" and W.Covers() == true
end

-- Its pages build as they're first shown, so each is gone over then.
Engine.Window({ key = "legacy", pack = "collections", addon = "Blizzard_LegacySystem", frame = "LegacySystemFrame",
    watch = true, skip = covered })
