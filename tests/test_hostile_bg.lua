local H = require("hostile")

-- The hostile sweep (tests/hostile.lua) with every setting changed in a
-- battleground between fights: where the 0.8.1 dispel tint error hit a player.
T.test("hostile sweep: every setting changed in a battleground between fights, no errors", function()
    local found, pulled = H.Sweep("between")
    H.Check(found, pulled, true)
end)
