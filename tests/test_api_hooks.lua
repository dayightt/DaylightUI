local stub = require("stub")

-- DaylightUI.API 1.3: named hooks on Daylight UI's own functions (me.Hook /
-- me.Wrap / me.Unhook). Errors are named, a broken wrap falls back to Daylight UI's
-- function, and only Daylight UI's tables can be hooked.

local function load()
    stub.Load({ module = true, login = false })
    local DUI = DaylightUI
    local UF = DUI:GetModule("UnitFrames").ns.UF
    local calls = {}
    UF.TestTarget = function(a, b) calls[#calls + 1] = a; return a + b end
    return DUI, UF, calls
end

local function chatWith(word)
    local n = 0
    for _, m in ipairs(stub.chat) do if string.find(m, word, 1, true) then n = n + 1 end end
    return n
end

T.test("api hooks: after runs after Daylight UI's function with the same arguments", function()
    local DUI, UF, calls = load()
    local got
    local h = DUI.API.For("Neon").Hook(UF, "TestTarget", function(a, b) got = { #calls, a, b } end)
    T.truthy(h)
    T.eq(UF.TestTarget(2, 3), 5, "Daylight UI's answer kept")
    T.eq(got[1], 1, "after Daylight UI's ran")
    T.eq(got[2], 2); T.eq(got[3], 3)
end)

T.test("api hooks: a wrap can skip Daylight UI's function and answer itself", function()
    local DUI, UF, calls = load()
    DUI.API.For("Neon").Wrap(UF, "TestTarget", function(orig, a, b) return 99 end)
    T.eq(UF.TestTarget(1, 1), 99)
    T.eq(#calls, 0, "skipped")
end)

T.test("api hooks: two plugins on one function, one lets go, the other keeps working in order", function()
    local DUI, UF = load()
    local order = {}
    local a = DUI.API.For("A").Hook(UF, "TestTarget", function() order[#order + 1] = "A" end)
    DUI.API.For("B").Hook(UF, "TestTarget", function() order[#order + 1] = "B" end)
    UF.TestTarget(1, 1)
    T.eq(table.concat(order, ","), "A,B")
    DUI.API.For("A").Unhook(a)
    UF.TestTarget(1, 1)
    T.eq(table.concat(order, ","), "A,B,B")
end)

T.test("api hooks: a wrap that errors falls back to Daylight UI's function, its error named", function()
    local DUI, UF, calls = load()
    DUI.API.For("Broken").Wrap(UF, "TestTarget", function() error("wrap bug") end)
    T.eq(UF.TestTarget(2, 2), 4, "Daylight UI's answer")
    T.eq(#calls, 1)
    T.truthy(string.find(tostring(stub.errors[1]), "Broken", 1, true), tostring(stub.errors[1]))
end)

T.test("api hooks: an after that errors is named and the answer still comes back", function()
    local DUI, UF = load()
    DUI.API.For("Broken").Hook(UF, "TestTarget", function() error("after bug") end)
    T.eq(UF.TestTarget(1, 2), 3)
    T.truthy(string.find(tostring(stub.errors[1]), "Broken", 1, true))
end)

T.test("api hooks: refused on a frame, the game's tables and _G, with one line each", function()
    local DUI = load()
    local me = DUI.API.For("Neon")
    T.eq(me.Hook(UIParent, "Show", function() end), false, "a frame")
    T.eq(me.Hook(C_Timer, "After", function() end), false, "a game table")
    T.eq(me.Hook(_G, "print", function() end), false, "_G")
    T.eq(chatWith("Neon"), 3)
    T.eq(me.Hook(DUI.Style, "NoSuchFunction", function() end), false, "not a function")
end)

T.test("api hooks: letting go of every hook puts Daylight UI's function back", function()
    local DUI, UF = load()
    local orig = UF.TestTarget
    local me = DUI.API.For("Neon")
    local h1 = me.Hook(UF, "TestTarget", function() end)
    local h2 = me.Wrap(UF, "TestTarget", function(o, ...) return o(...) end)
    T.truthy(UF.TestTarget ~= orig)
    me.Unhook(h1); me.Unhook(h2)
    T.eq(UF.TestTarget, orig)
end)

T.test("api hooks: callers that go through the table hear a hook made later", function()
    local DUI, UF = load()
    local function caller() return UF.TestTarget(1, 1) end
    local heard = false
    DUI.API.For("Neon").Hook(UF, "TestTarget", function() heard = true end)
    caller()
    T.eq(heard, true)
end)

T.test("api hooks: core tables are Daylight UI's too", function()
    local DUI = load()
    local n = 0
    DUI.API.For("Neon").Hook(DUI.Style, "Accent", function() n = n + 1 end)
    DUI.Style.Accent()
    T.eq(n, 1)
end)

T.test("api hooks: Daylight UI's own error inside a wrap stays Daylight UI's", function()
    local DUI, UF = load()
    UF.TestTarget = function() error("daylight bug") end
    DUI.API.For("Innocent").Wrap(UF, "TestTarget", function(orig, ...) return orig(...) end)
    local ok, err = pcall(UF.TestTarget, 1, 1)
    T.eq(ok, false, "the error goes on to the caller")
    T.truthy(string.find(tostring(err), "daylight bug", 1, true), tostring(err))
    for _, e in ipairs(stub.errors) do T.falsy(string.find(tostring(e), "Innocent", 1, true), "not blamed: " .. tostring(e)) end
end)

T.test("api hooks: an after that unhooks itself mid-call leaves the others running", function()
    local DUI, UF = load()
    local me = DUI.API.For("Self")
    local h
    h = me.Hook(UF, "TestTarget", function() me.Unhook(h) end)
    local n = 0
    DUI.API.For("Other").Hook(UF, "TestTarget", function() n = n + 1 end)
    UF.TestTarget(1, 1)
    UF.TestTarget(1, 1)
    T.eq(n, 2)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api hooks: Daylight UI's error reporting can't be hooked", function()
    local DUI = load()
    T.eq(DUI.API.For("Neon").Hook(DUI, "SafeCallAs", function() end), false)
    T.eq(DUI.API.For("Neon").Hook(DUI, "SafeCall", function() end), false)
end)
