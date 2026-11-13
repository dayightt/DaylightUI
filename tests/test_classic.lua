local stub = require("stub")

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

local function copy(c) return { c[1], c[2], c[3] } end

local function look(DUI, which)
    DUI:Set("general", "look", which)
    stub.RunTimers()   -- the style repaints on the next frame
end

T.test("classic swaps the palette in place and daylight puts today's numbers back", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local border, label, text = S.BORDER, S.INK.LABEL, S.INK.TEXT
    local was = { border = copy(border), band = copy(S.BAND), back = copy(S.BACKGROUND), label = copy(label) }
    look(DUI, "classic")
    T.truthy(S.BORDER == border and S.INK.LABEL == label, "the same tables, so every alias follows")
    T.rgb(S.BORDER, hex("3d362e"), "stone border")
    T.rgb(S.BACKGROUND, hex("0f0d0b"), "warm black")
    T.rgb(S.INK.LABEL, hex("e2c27a"), "gold labels")
    T.rgb(S.INK.TITLE, hex("ffd35a"), "gold titles")
    T.rgb(text, { 0.949, 0.933, 0.902 }, "sentences stay soft white")
    look(DUI, "daylight")
    T.rgb(S.BORDER, was.border, "border back")
    T.rgb(S.BAND, was.band, "band back")
    T.rgb(S.BACKGROUND, was.back, "background back")
    T.rgb(S.INK.LABEL, was.label, "labels back")
    T.rgb(S.INK.TITLE, { 1, 1, 1 }, "titles back")
end)

T.test("a table registered with Style.Looked follows the look", function()
    local DUI = stub.Load()
    local t = { c = { 1, 1, 1 }, n = 1 }
    local c = t.c
    DUI.Style.Looked(t, { daylight = { c = { 1, 1, 1 }, n = 1 }, classic = { c = { 0, 0.5, 0 }, n = 2 } })
    look(DUI, "classic")
    T.truthy(t.c == c, "colors copied in place")
    T.rgb(t.c, { 0, 0.5, 0 })
    T.eq(t.n, 2)
    look(DUI, "daylight")
    T.rgb(t.c, { 1, 1, 1 })
    T.eq(t.n, 1)
end)

T.test("a shell repaints to the classic border", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 40)
    local s = DUI.Style.Shell(f)
    look(DUI, "classic")
    local v = s.border.LEFT.__vertex
    T.rgb({ v[1], v[2], v[3] }, hex("3d362e"))
    local bg = s.bg.__color or s.bg.__vertex
    T.rgb({ bg[1], bg[2], bg[3] }, hex("0f0d0b"), "background")
end)

T.test("an unknown saved look reads daylight", function()
    local DUI = stub.Load()
    look(DUI, "nope")
    T.eq(DUI.Style.Look(), "daylight")
    T.rgb(DUI.Style.INK.TITLE, { 1, 1, 1 })
end)

T.test("switching to a profile on another look carries it", function()
    local DUI = stub.Load()
    local DB = DUI.DB
    local root = DB.Root()
    local was = DB.ActiveName()
    root.profileData.Gilded = DB.Fill({ general = { look = "classic" } })
    DB.activeName = "Gilded"
    DUI.RepaintStyle()
    stub.RunTimers()
    T.rgb(DUI.Style.BORDER, hex("3d362e"), "classic profile")
    DB.activeName = was
    DUI.RepaintStyle()
    stub.RunTimers()
    T.rgb(DUI.Style.BORDER, { 0.024, 0.024, 0.027 }, "back on the daylight profile")
end)
