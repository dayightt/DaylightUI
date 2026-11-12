local stub = require("stub")

-- DaylightUI.API 1.3: Paint, a plugin's look laid on Daylight UI's frames after each
-- of Daylight UI's own paints (API.lua's painter registry), with the pieces it
-- claims left to it. A made-up kind stands in for the real ones.

local function setup()
    stub.Load({ login = false })
    local DUI = DaylightUI
    local R = DUI.APIReport
    local partsAsked, repainted = 0, {}
    R.Parts("testkind", function(f)
        partsAsked = partsAsked + 1
        return { fill = f.fill, name = f.label }
    end)
    R.Repainter("testkind", function(f) repainted[#repainted + 1] = f end)
    local function frame(unit, isPreview)
        local f = CreateFrame("Frame", nil, UIParent)
        f.fill = f:CreateTexture()
        f.label = f:CreateFontString()
        R.Made("testkind", f, unit, isPreview)
        return f
    end
    return DUI, R, frame, function() return partsAsked end, repainted
end

local function chatWith(word)
    local n = 0
    for _, m in ipairs(stub.chat) do if string.find(m, word, 1, true) then n = n + 1 end end
    return n
end

T.test("api paint: runs on frames that exist, then after each paint", function()
    local DUI, R, frame = setup()
    local f1, f2 = frame("a", false), frame("b", false)
    local calls = {}
    local h = DUI.API.For("Neon").Paint("testkind", function(f, parts, info)
        calls[#calls + 1] = { f, parts, info }
    end)
    T.truthy(h, "a handle")
    T.eq(#calls, 2, "both frames painted at once")
    T.eq(calls[1][2].fill ~= nil, true, "with their parts")
    R.Painted("testkind", f1, { a = 1 })
    T.eq(#calls, 3)
    T.eq(calls[3][1], f1)
    T.eq(calls[3][3].a, 1, "the info handed on")
    T.eq(DUI.API.Parts(f2).name, f2.label)
    T.isnil(DUI.API.Parts(CreateFrame("Frame")), "not a frame of an opened kind")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api paint: a painter added before the frames paints each as it comes, previews too", function()
    local DUI, R, frame = setup()
    local seen = {}
    DUI.API.For("Neon").Paint("testkind", function(f) seen[#seen + 1] = f end)
    T.eq(#seen, 0)
    local f = frame("a", false)
    R.Painted("testkind", f)
    T.eq(#seen, 2, "once as it was made, once after the paint")
    local p = frame(nil, true)
    T.eq(#seen, 3)
    T.eq(seen[3], p, "a preview is painted too")
end)

T.test("api paint: claiming a piece, a second claim refused with one line, handed on when the first stops", function()
    local DUI, R, frame = setup()
    local f = frame("a", false)
    local first = DUI.API.For("Neon").Paint("testkind", function() end, { owns = { "fill" } })
    T.eq(R.Owned("testkind", "fill"), true)
    T.eq(R.Owned("testkind", "name"), false)
    local second = DUI.API.For("Glow").Paint("testkind", function() end, { owns = { "fill" } })
    T.truthy(second, "still painting")
    T.eq(chatWith("Glow"), 1, "one line naming the second")
    T.eq(chatWith("Neon") >= 1, true, "and the first")
    DUI.API.Off(first)
    T.eq(R.Owned("testkind", "fill"), true, "the second now holds it")
    DUI.API.Off(second)
    T.eq(R.Owned("testkind", "fill"), false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api paint: stopping gives the frames back to Daylight UI at once", function()
    local DUI, R, frame, _, repainted = setup()
    local f1, f2 = frame("a", false), frame("b", false)
    local n = 0
    local h = DUI.API.For("Neon").Paint("testkind", function() n = n + 1 end, { owns = { "fill" } })
    T.eq(#repainted, 2, "claiming takes Daylight UI's look off each frame first")
    DUI.API.Off(h)
    T.eq(R.Owned("testkind", "fill"), false)
    T.eq(#repainted, 4, "each frame repainted on the way out")
    local was = n
    R.Painted("testkind", f1)
    T.eq(n, was, "no longer called")
    DUI.API.Off(h)   -- twice, and nothing happens
    T.eq(#repainted, 4)
end)

T.test("api paint: an error names the plugin and the others still paint", function()
    local DUI, R, frame = setup()
    local f = frame("a", false)
    DUI.API.For("Broken").Paint("testkind", function() error("neon bug") end)
    local ok = 0
    DUI.API.For("Fine").Paint("testkind", function() ok = ok + 1 end)
    R.Painted("testkind", f)
    T.eq(ok, 2, "once at start, once now")
    T.truthy(#stub.errors >= 1)
    T.truthy(string.find(tostring(stub.errors[1]), "Broken", 1, true), tostring(stub.errors[1]))
end)

T.test("api paint: with no painter, a paint costs nothing", function()
    local DUI, R, frame, asked = setup()
    local f = frame("a", false)
    R.Painted("testkind", f)
    R.Painted("testkind", f)
    T.eq(asked(), 0, "the parts were never gathered")
end)

T.test("api paint: bad arguments are refused", function()
    local DUI = setup()
    local me = DUI.API.For("Neon")
    T.isnil(me.Paint("testkind", nil))
    T.isnil(me.Paint(nil, function() end))
    T.truthy(me.Paint("nokind", function() end), "a kind not loaded yet is kept (its module may load later)")
end)

-- Edge cases.
T.test("api paint: a painter asked for before its kind's module loaded still paints", function()
    stub.Load({ login = false })
    local R = DaylightUI.APIReport
    local seen = 0
    local h = DaylightUI.API.For("Early").Paint("latekind", function() seen = seen + 1 end)
    T.truthy(h, "kept, not refused")
    local f = CreateFrame("Frame")
    R.Made("latekind", f, "x", false)
    R.Parts("latekind", function() return {} end)
    T.eq(seen, 1, "painted once its parts are known")
    R.Painted("latekind", f)
    T.eq(seen, 2)
end)

T.test("api paint: a painter stopping itself mid-paint never breaks the others", function()
    local DUI, R, frame = setup()
    local f = frame("a", false)
    local first, after = nil, 0
    first = DUI.API.For("Once").Paint("testkind", function() if first then DUI.API.Off(first) end end)
    DUI.API.For("Next").Paint("testkind", function() after = after + 1 end)
    local was = after
    R.Painted("testkind", f)
    T.truthy(after >= was + 1, "the next one still ran")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    was = after
    R.Painted("testkind", f)
    T.eq(after, was + 1, "and keeps running, once a paint")
end)
