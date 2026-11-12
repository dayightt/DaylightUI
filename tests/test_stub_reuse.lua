local stub = require("stub")   -- T (test helpers) is a global set by tests/run.lua

-- The seams that let another addon (DaylightMogul) copy this fake game.
T.test("reset clears every name in RESET_GLOBALS", function()
    stub.RESET_GLOBALS[#stub.RESET_GLOBALS + 1] = "MogulProbeGlobal"
    _G.MogulProbeGlobal = 1
    stub.Reset()
    T.isnil(rawget(_G, "MogulProbeGlobal"))
    table.remove(stub.RESET_GLOBALS)
end)
T.test("reset still clears our own globals by default", function()
    _G.DaylightUIDB, _G.DaylightUI, _G.SLASH_DAYLIGHTUI1 = {}, {}, "/dui"
    stub.Reset()
    T.isnil(rawget(_G, "DaylightUIDB"))
    T.isnil(rawget(_G, "DaylightUI"))
    T.isnil(rawget(_G, "SLASH_DAYLIGHTUI1"))
end)
T.test("LoadFiles is exported", function() T.eq(type(stub.LoadFiles), "function") end)
T.test("FinishFade settles the feelOwner's windows", function()
    stub.Reset()
    local settled
    stub.feelOwner = { Win = { Feel = { Settle = function(f) settled = f end } } }
    local f = CreateFrame("Frame")
    stub.FinishFade(f)
    stub.feelOwner = nil
    T.eq(settled, f)
end)
