local H = require("hostile")

-- The hostile sweep in a party: you and four others in a keystone dungeon,
-- with every setting changed between pulls. Uses the Ribbon frame style since
-- the other sweeps run Daylight's, so both shapes get a fight.
T.test("hostile sweep: a keystone party in Ribbon, every setting changed between pulls, no errors", function()
    local found, pulled = H.Sweep("between", function(DUI) DUI:Set("UnitFrames", "look.style", "ribbon") end,
        { world = "party" })
    H.Check(found, pulled, true)
end)
