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

local GOLD_LO, GOLD_HI = hex("7a5c18"), hex("f3d27a")
local GOLD_MID = { (GOLD_LO[1] + GOLD_HI[1]) / 2, (GOLD_LO[2] + GOLD_HI[2]) / 2, (GOLD_LO[3] + GOLD_HI[3]) / 2 }

local function heavyShell(DUI)
    DUI:Set("general", "borderPx", 8)
    stub.RunTimers()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 60)
    return DUI.Style.Shell(f)
end

T.test("classic's band sweeps gold", function()
    local DUI = stub.Load()
    local s = heavyShell(DUI)
    look(DUI, "classic")
    local g = s.band.TOP.__gradient
    T.truthy(g, "the top band sweeps")
    T.rgb({ g[2].r, g[2].g, g[2].b }, GOLD_LO, "dark gold on the left")
    T.rgb({ g[3].r, g[3].g, g[3].b }, GOLD_HI, "bright gold on the right")
    T.falsy(s.border.TOP.__gradient, "the outline stays stone")
    look(DUI, "daylight")
    T.falsy(s.band.TOP.__gradient, "daylight's band is one color again")
end)

T.test("gold accent: on paints gold, off keeps the player's, the accent setting untouched", function()
    local DUI = stub.Load()
    local S = DUI.Style
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.2, 0.3 })
    look(DUI, "classic")
    T.truthy(S.GoldAccent())
    T.rgb({ S.Accent() }, GOLD_MID, "gold")
    T.eq(S.AccentSweep(), "gold")
    local lo, hi = S.AccentPair()
    T.rgb(lo, GOLD_LO); T.rgb(hi, GOLD_HI)
    T.rgb({ S.AccentAt(0) }, GOLD_LO, "a list starts dark gold")
    DUI:Set("general", "lookGold", false)
    stub.RunTimers()
    T.falsy(S.GoldAccent())
    T.rgb({ S.Accent() }, { 0.1, 0.2, 0.3 }, "the player's own")
    T.eq(DUI:Get("general", "accent"), "custom", "never written")
    DUI:Set("general", "lookGold", true)
    look(DUI, "daylight")
    T.rgb({ S.Accent() }, { 0.1, 0.2, 0.3 }, "daylight: the player's own")
end)

T.test("gradients off: one flat gold, no sweep", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local s = heavyShell(DUI)
    DUI:Set("general", "gradients.off", true)
    look(DUI, "classic")
    T.isnil(S.AccentSweep())
    T.rgb({ S.Accent() }, GOLD_MID)
    T.falsy(s.band.TOP.__gradient, "the band is one color")
    local v = s.band.TOP.__vertex
    T.rgb({ v[1], v[2], v[3] }, GOLD_MID, "flat gold")
end)

T.test("a highlight beats the gold band and falls back to classic", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local s = heavyShell(DUI)
    look(DUI, "classic")
    S.SetShellColors(s, { 1, 0, 0 }, { 1, 0, 0 })
    T.falsy(s.band.TOP.__gradient, "the highlight's own band")
    T.rgb({ s.band.TOP.__vertex[1], s.band.TOP.__vertex[2], s.band.TOP.__vertex[3] }, { 1, 0, 0 })
    S.SetShellColors(s, nil, nil, nil)
    T.truthy(s.band.TOP.__gradient, "gold again")
    T.rgb({ s.border.TOP.__vertex[1], s.border.TOP.__vertex[2], s.border.TOP.__vertex[3] }, hex("3d362e"), "stone outline")
    -- A flag the client resolves (aggro, dispel): its off colors are classic too.
    S.ShellColorsFromBoolean(s, true, { 1, 0, 0 }, { 1, 0, 0 })
    local off = s.border.TOP.__vertexFromBoolean[3]
    T.rgb({ off.r, off.g, off.b }, hex("3d362e"), "off = stone")
    look(DUI, "daylight")
    S.ShellColorsFromBoolean(s, true, { 1, 0, 0 }, { 1, 0, 0 })
    off = s.border.TOP.__vertexFromBoolean[3]
    T.rgb({ off.r, off.g, off.b }, { 0.024, 0.024, 0.027 }, "the cache follows the look")
end)

T.test("a window's title, sub line and portrait rim follow the look", function()
    local DUI = stub.Load()
    local f = DUI.Win.New({ w = 300, h = 200, portrait = true })
    look(DUI, "classic")
    T.rgb(f.title.__textColor, hex("ffd35a"), "gold title")
    T.rgb(f.sub.__textColor, DUI.Win.DIM, "sub line")
    T.rgb(f.portraitRim.__vertex, DUI.Style.BAND, "rim in the band")
    look(DUI, "daylight")
    T.rgb(f.title.__textColor, { 1, 1, 1 }, "white again")
end)

T.test("options text made by W.Font follows the look, unless recolored since", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local label = W.Font(UIParent, W.BODY, 13, DUI.Style.INK.LABEL)
    local own = W.Font(UIParent, W.BODY, 13, DUI.Style.INK.LABEL)
    own:SetTextColor(0.2, 0.9, 0.2)
    look(DUI, "classic")
    T.rgb(label.__textColor, hex("e2c27a"), "gold label")
    T.rgb(own.__textColor, { 0.2, 0.9, 0.2 }, "a color set since is left alone")
    look(DUI, "daylight")
    T.rgb(label.__textColor, { 0.76, 0.71, 0.62 }, "tan again")
end)

T.test("a separator and a followed texture keep the look's color", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local line = S.Separator(UIParent)
    local rim = UIParent:CreateTexture()
    S.Follow(rim, S.BAND)
    look(DUI, "classic")
    T.rgb(line.__color, hex("3d362e"), "separator in stone")
    T.near(line.__color[4], 0.9)
    T.rgb(rim.__vertex, S.LOOKS.classic.BAND, "rim in the gold band")
    look(DUI, "daylight")
    T.rgb(line.__color, { 0.024, 0.024, 0.027 })
end)

T.test("a button turns red and gold, and back", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local b = W.Button(UIParent, "Go")
    look(DUI, "classic")
    local g = b.fill.__gradient
    T.truthy(g, "the fill runs top to bottom")
    T.rgb({ g[3].r, g[3].g, g[3].b }, hex("9a1a12"), "red at the top")
    T.rgb({ g[2].r, g[2].g, g[2].b }, hex("560c07"), "darker red below")
    T.rgb(b.band.__vertex, DUI.Style.LOOKS.classic.BAND, "gold band")
    T.rgb(b.text.__textColor, hex("ffd35a"), "gold words")
    T.rgb(DUI.Style.INK.TEXT, { 0.949, 0.933, 0.902 }, "sentences elsewhere stay soft white")
    look(DUI, "daylight")
    T.rgb(b.band.__vertex, { 0.10, 0.09, 0.063 }, "today's band")
    T.rgb(b.text.__textColor, { 0.949, 0.933, 0.902 }, "today's words")
end)

local FRIZ = "Fonts" .. string.char(92) .. "FRIZQT__.TTF"

T.test("classic titles use the game's font, body text keeps the player's", function()
    local DUI = stub.Load()
    local S, W = DUI.Style, DUI.Widgets
    local f = DUI.Win.New({ w = 300, h = 200 })
    local head = W.Title(UIParent, 15, S.INK.LABEL)
    local body = S.Text(UIParent, 13)
    look(DUI, "classic")
    T.eq(S.TitleFont(), FRIZ)
    T.eq((f.title:GetFont()), FRIZ, "window title")
    T.eq((head:GetFont()), FRIZ, "card heading")
    T.eq((body:GetFont()), S.FONT, "body text")
    look(DUI, "daylight")
    T.isnil(S.TitleFont())
    T.eq((f.title:GetFont()), S.FONT, "the player's font again")
    T.eq((head:GetFont()), W.TITLE)
end)

T.test("a non-Latin client keeps its own font on classic titles", function()
    local DUI = stub.Load()
    local real = DUI.DB.UseLocalFont
    DUI.DB.UseLocalFont = function() return true end
    look(DUI, "classic")
    T.isnil(DUI.Style.TitleFont(), "the game's Latin font lacks the letters")
    DUI.DB.UseLocalFont = real
end)

local function angledFrame(DUI, side)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(220, 40)
    DUI.Style.Shell(f)
    DUI.Style.Slant(f, side, 12)
    DUI.Style.Rivets(f, true)
    return f
end

local function shownRivets(DUI, f)
    local n = 0
    for _, t in pairs(DUI.Style.RivetsOf(f) or {}) do if t:IsShown() then n = n + 1 end end
    return n
end

T.test("rivets sit on an angled frame's cuts under Classic only", function()
    local DUI = stub.Load()
    local f = angledFrame(DUI, "right")
    T.eq(shownRivets(DUI, f), 0, "none under Daylight")
    look(DUI, "classic")
    T.eq(shownRivets(DUI, f), 1, "one on the one cut")
    local r = DUI.Style.RivetsOf(f).right
    local _, rel, to, x, y = r:GetPoint(1)
    T.truthy(rel == f and to == "RIGHT", "placed on the frame's right end, so it follows a resize")
    T.truthy(x < 0 and x > -12, "inside the cut")
    T.near(y, 0, 0.01, "halfway down")
    T.rgb(r.__vertex, GOLD_HI, "bright gold")
    look(DUI, "daylight")
    T.eq(shownRivets(DUI, f), 0, "gone again")
end)

T.test("a frame with both ends cut gets a rivet on each, a straight frame none", function()
    local DUI = stub.Load()
    local f = angledFrame(DUI, "both")
    local plain = CreateFrame("Frame", nil, UIParent)
    plain:SetSize(200, 40)
    DUI.Style.Shell(plain)
    DUI.Style.Rivets(plain, true)
    look(DUI, "classic")
    T.eq(shownRivets(DUI, f), 2)
    T.eq(shownRivets(DUI, plain), 0, "no cut, no rivet")
end)

T.test("the header rule turns gold with a diamond under Classic", function()
    local DUI = stub.Load()
    local f = DUI.Win.New({ w = 300, h = 200 })
    T.falsy(f.ruleGem and f.ruleGem:IsShown(), "no diamond under Daylight")
    look(DUI, "classic")
    T.truthy(f.ruleGem and f.ruleGem:IsShown(), "a diamond in the middle")
    T.truthy(f.ruleLeft:IsShown() and f.ruleLeft.__gradient, "gold fading out to the left")
    T.truthy(f.ruleRight:IsShown() and f.ruleRight.__gradient, "and to the right")
    T.falsy(f.rule:IsShown(), "the faint rule steps aside")
    look(DUI, "daylight")
    T.falsy(f.ruleGem:IsShown())
    T.falsy(f.ruleLeft:IsShown())
    T.truthy(f.rule:IsShown(), "today's faint rule")
end)
