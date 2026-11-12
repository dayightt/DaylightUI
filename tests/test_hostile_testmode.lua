local H = require("hostile")

-- The hostile sweep (tests/hostile.lua) with test mode on. The sample frames
-- show while every setting changes in a battleground between fights, and the
-- first fight ends test mode, as in game.
T.test("hostile sweep: test mode on, every setting changed in a battleground, no errors", function()
    local found, pulled = H.Sweep("between", nil, { testMode = true })
    H.Check(found, pulled, true)
end)
