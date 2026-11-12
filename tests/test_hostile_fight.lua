local H = require("hostile")

-- The hostile sweep with every setting changed during a
-- battleground fight: the changes wait for the fight to end, then all run.
T.test("hostile sweep: every setting changed in a battleground fight, no errors", function()
    local found, pulled = H.Sweep("fight")
    H.Check(found, pulled, true)
end)

-- The sweep can fail: a planted secret comparison is caught.
T.test("hostile sweep can fail: a planted secret comparison is caught", function()
    local found = H.Sweep(nil, function(DUI)
        DUI.RegisterEvent("UNIT_HEALTH", function(_, unit)
            if UnitHealth(unit) > 0 then return end   -- compares a secret in combat
        end)
    end)
    local caught = false
    for _, p in ipairs(found) do if string.find(p, "test_hostile_fight.lua", 1, true) then caught = true end end
    T.truthy(caught, "the planted error wasn't found: " .. table.concat(found, " | "))
end)
