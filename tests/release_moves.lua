-- Changes since the last release that move a returning player's setup on
-- purpose, each with why. Changing a default moves everyone who never touched
-- it, so first try an upgrade step that keeps existing profiles on the old value
-- (tests/test_release_moves.lua then passes without an entry here).
-- values: "Module.path" (or "general.path") -> why.
-- frames: a movable frame's key ("unitframes.player") -> why.
-- plates: a case ("defaults", or "<piece>@<spot>"), "<case>|<piece>", or
-- "*|<piece>" for one piece in every case -> why.
-- Emptied at each release, when tests/release_snapshot.lua writes the new snapshot.
return {
    values = {},
    frames = {},
    plates = {},
}
