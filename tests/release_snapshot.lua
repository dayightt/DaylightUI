-- Records what a player of this release has (their saved data after a session,
-- every setting's value, where each nameplate piece sits) in
-- tests/release_data.lua, for tests/test_release_moves.lua. Run it from the
-- repo root on the release's own code, as part of every release:
--   luajit tests/release_snapshot.lua <version>
package.path = "tests/?.lua;" .. package.path
T = T or {}
local Check = require("release_check")

local version = arg[1] or "?"
local saved = Check.Saved()
local DUI = Check.Load(saved)
Check.Write("tests/release_data.lua", {
    version = version,
    saved = saved,
    values = Check.Values(DUI),
    frames = Check.Frames(DUI),
    plates = Check.Plates(DUI),
})
print("tests/release_data.lua written for " .. version)
