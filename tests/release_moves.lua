-- Changes since the last release that move a returning player's setup on
-- purpose, each with why. Changing a default moves everyone who never touched
-- it, so first try an upgrade step that keeps existing profiles on the old value
-- (tests/test_release_moves.lua then passes without an entry here).
-- values: "Module.path" (or "general.path") -> why.
-- frames: a movable frame's key ("unitframes.player") -> why.
-- plates: a case ("defaults", or "<piece>@<spot>"), "<case>|<piece>", or
-- "*|<piece>" for one piece in every case -> why.
-- Emptied at each release, when tests/release_snapshot.lua writes the new snapshot.
local BACK = "back where it sat before 1.8.0: the big defensive icon added then pushed it out"
local ROWS = "aura rows back as they were before 1.8.0 for players who had them (upgrade step 19)"
return {
    values = {
        ["UnitFrames.targetAuras.buffSpot"] = ROWS,
        ["UnitFrames.targetAuras.buffGrow"] = ROWS,
        ["UnitFrames.targetAuras.buffRows"] = ROWS,
        ["UnitFrames.targetAuras.debuffRows"] = ROWS,
        ["UnitFrames.playerAuras.debuffGrow"] = ROWS,
        ["UnitFrames.personal.auras.debuffGrow"] = ROWS,
        ["UnitFrames.personal.auras.buffGrow"] = ROWS,
    },
    frames = {},
    plates = {
        ["*|execIcon"] = BACK,
        ["level@outright"] = BACK,
        ["name@outright"] = BACK,
        ["percent@outright"] = BACK,
        ["threatPct@outright"] = BACK,
        ["defensives@outtopleft"] = "the threat % stays by the bar, the big defensive goes past it",
    },
}
