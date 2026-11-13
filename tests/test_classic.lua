local stub = require("stub")

local function hex(s)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

local function copy(c) return { c[1], c[2], c[3] } end

-- Classic: the game's yellow words, steel frames, near-black blue backgrounds.
local YELLOW = { 1, 0.82, 0 }

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
    T.rgb(S.BORDER, hex("1c1c20"), "dark steel edge")
    T.rgb(S.BACKGROUND, hex("0a0a16"), "warm black")
    T.rgb(S.INK.LABEL, YELLOW, "yellow labels")
    T.rgb(S.INK.TITLE, YELLOW, "yellow titles")
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
    T.rgb({ v[1], v[2], v[3] }, hex("1c1c20"))
    local bg = s.bg.__color or s.bg.__vertex
    T.rgb({ bg[1], bg[2], bg[3] }, hex("0a0a16"), "background")
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
    T.rgb(DUI.Style.BORDER, hex("1c1c20"), "classic profile")
    DB.activeName = was
    DUI.RepaintStyle()
    stub.RunTimers()
    T.rgb(DUI.Style.BORDER, { 0.024, 0.024, 0.027 }, "back on the daylight profile")
end)

local GOLD_LO, GOLD_HI = hex("b8860b"), { 1, 0.82, 0 }
local GOLD_MID = { (GOLD_LO[1] + GOLD_HI[1]) / 2, (GOLD_LO[2] + GOLD_HI[2]) / 2, (GOLD_LO[3] + GOLD_HI[3]) / 2 }
local STEEL_LO, STEEL_HI = hex("5c5c64"), hex("b4b4bc")
local STEEL_MID = { (STEEL_LO[1] + STEEL_HI[1]) / 2, (STEEL_LO[2] + STEEL_HI[2]) / 2, (STEEL_LO[3] + STEEL_HI[3]) / 2 }

local function heavyShell(DUI)
    DUI:Set("general", "borderPx", 8)
    stub.RunTimers()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 60)
    return DUI.Style.Shell(f)
end

T.test("classic's band sweeps steel, even with the plain game bars on", function()
    local DUI = stub.Load()
    local s = heavyShell(DUI)
    look(DUI, "classic")
    local g = s.band.TOP.__gradient
    T.truthy(g, "the top band sweeps")
    T.rgb({ g[2].r, g[2].g, g[2].b }, STEEL_LO, "dark steel on the left")
    T.rgb({ g[3].r, g[3].g, g[3].b }, STEEL_HI, "bright steel on the right")
    T.falsy(s.border.TOP.__gradient, "the outline stays one color")
    look(DUI, "daylight")
    T.falsy(s.band.TOP.__gradient, "daylight's band is one color again")
end)

T.test("gold accent: on paints gold, off keeps the player's, the accent setting untouched", function()
    local DUI = stub.Load()
    local S = DUI.Style
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.2, 0.3 })
    DUI:Set("general", "lookGradients", true)
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
    T.rgb({ v[1], v[2], v[3] }, STEEL_MID, "flat steel")
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
    T.rgb({ s.border.TOP.__vertex[1], s.border.TOP.__vertex[2], s.border.TOP.__vertex[3] }, hex("1c1c20"), "dark outline")
    -- A flag the client resolves (aggro, dispel): its off colors are classic too.
    S.ShellColorsFromBoolean(s, true, { 1, 0, 0 }, { 1, 0, 0 })
    local off = s.border.TOP.__vertexFromBoolean[3]
    T.rgb({ off.r, off.g, off.b }, hex("1c1c20"), "off = the dark outline")
    look(DUI, "daylight")
    S.ShellColorsFromBoolean(s, true, { 1, 0, 0 }, { 1, 0, 0 })
    off = s.border.TOP.__vertexFromBoolean[3]
    T.rgb({ off.r, off.g, off.b }, { 0.024, 0.024, 0.027 }, "the cache follows the look")
end)

T.test("a window's title, sub line and portrait rim follow the look", function()
    local DUI = stub.Load()
    local f = DUI.Win.New({ w = 300, h = 200, portrait = true })
    look(DUI, "classic")
    T.rgb(f.title.__textColor, YELLOW, "gold title")
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
    T.rgb(label.__textColor, YELLOW, "gold label")
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
    T.rgb(line.__color, hex("1c1c20"), "separator in stone")
    T.near(line.__color[4], 0.9)
    T.rgb(rim.__vertex, S.LOOKS.classic.BAND, "rim in the steel band")
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
    T.rgb(b.band.__vertex, hex("6b5520"), "a darker gold band, so the gold hover trace shows")
    T.rgb(b.text.__textColor, YELLOW, "yellow words")
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
    T.rgb(r.__vertex, STEEL_HI, "bright steel")
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

T.test("a window opening under Classic plays one gold glint; Daylight, motion off and combat play none", function()
    local DUI = stub.Load()
    local M = DUI.Motion
    local real, swept, f = M.Sweep, 0, nil
    M.Sweep = function(tex, over, opts)
        if over == f then
            swept = swept + 1
            T.rgb(opts.color, STEEL_HI, "silver light")
        end
        return real(tex, over, opts)
    end
    f = DUI.Win.New({ w = 300, h = 200 })
    DUI.Win.Feel.Open(f)
    T.eq(swept, 0, "daylight: none")
    DUI.Win.Feel.Close(f); stub.RunTimers()
    look(DUI, "classic")
    f:Hide()
    DUI.Win.Feel.Open(f)
    T.eq(swept, 1, "classic: one")
    f:Hide()
    stub.EnterCombat()
    DUI.Win.Feel.Open(f)
    T.eq(swept, 1, "none in a fight")
    stub.LeaveCombat()
    T.eq(swept, 1, "none after the fight")
    f:Hide()
    DUI:Set("general", "motion", false)
    T.eq(swept, 1, "none from the setting")
    stub.RunTimers()
    T.eq(swept, 1, "none from the repaint")
    DUI.Win.Feel.Open(f)
    T.eq(swept, 1, "none with motion off")
    M.Sweep = real
end)

local function rogueLogin()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", health = 5, maxHealth = 10 }
    end })
    _G.C_Texture = _G.C_Texture or {}
    C_Texture.GetAtlasInfo = function(name)
        if name == "classicon-rogue" then
            return { file = 12345, leftTexCoord = 0.1, rightTexCoord = 0.2, topTexCoord = 0.3, bottomTexCoord = 0.4 }
        end
    end
    return DUI, ns
end

T.test("the Daylight UI icon style shows the game's class icons under Classic", function()
    local DUI, ns = rogueLogin()
    local UF = ns.UF
    T.truthy(type(UF.ClassIcon("ROGUE", "daylight")) == "string", "ours under Daylight")
    look(DUI, "classic")
    T.eq(UF.ClassIcon("ROGUE", "daylight"), 12345, "the game's under Classic")
    T.eq(UF.ClassIcon("ROGUE", "game"), 12345)
    T.eq(UF.ClassIcon("ROGUE", "daylight", { ROGUE = "daylight" }), 12345, "a per-class daylight pick too")
    T.eq(DUI:Get("UnitFrames", "portraits.icons"), "daylight", "nothing written")
end)

T.test("a shown portrait swaps to the game's icon on the look change", function()
    local DUI, ns = rogueLogin()
    local f = ns.frames.player
    ns.UF.UpdateAll(f, true)
    T.eq(f.portrait.icon.__texture, DUI.MEDIA .. "class\\rogue.tga")
    look(DUI, "classic")
    T.eq(f.portrait.icon.__texture, 12345, "the game's icon")
    look(DUI, "daylight")
    T.eq(f.portrait.icon.__texture, DUI.MEDIA .. "class\\rogue.tga", "ours again")
end)

T.test("switching looks with the unit frames off errors nothing", function()
    local DUI = stub.Load()
    look(DUI, "classic")
    look(DUI, "daylight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

local function itemFor(DUI, key)
    local page = DUI.Options.GetPage("appearance")
    for _, group in ipairs(page.groups) do
        for _, item in ipairs(group.items or {}) do
            if item.key == key then return item, group end
        end
    end
end

T.test("General > Appearance has a Look card with a Gold accent switch shown under Classic", function()
    local DUI = stub.Load()
    local look_, group = itemFor(DUI, "look")
    T.truthy(look_ and look_.type == "dropdown", "the Look dropdown")
    T.eq(group.label, "Look")
    T.eq(look_.values.daylight, "Daylight UI"); T.eq(look_.values.classic, "Classic")
    local gold = itemFor(DUI, "lookGold")
    T.truthy(gold and gold.type == "toggle", "the Gold accent switch")
    local get = function(k) return k == "look" and "daylight" or nil end
    T.eq(gold.hidden(get), true, "hidden under Daylight")
    get = function(k) return k == "look" and "classic" or nil end
    T.falsy(gold.hidden(get), "shown under Classic")
end)

T.test("the setup guide's Look step offers both looks first", function()
    local DUI = stub.Load()
    local step
    for _, s in ipairs(DUI.InstallerPages.TOUR) do if s.id == "look" then step = s end end
    T.truthy(step, "the Look step")
    local first = step.groups[1]
    T.truthy(first.cards and first.cards.key == "look" and first.cards.scope == "general")
end)

T.test("registering per-look values while files load never touches the saved settings", function()
    local DUI = stub.Load()
    local DB = DUI.DB
    local was, sv, init = DB.loggedIn, DB.sv, DB.Init
    local touched = false
    DB.loggedIn, DB.sv = nil, nil
    DB.Init = function() touched = true end
    DUI.Style.Looked({ c = { 1, 1, 1 } }, { daylight = { c = { 1, 1, 1 } }, classic = { c = { 0, 0, 0 } } })
    DB.loggedIn, DB.sv, DB.Init = was, sv, init
    T.falsy(touched, "the saved data is set up later, by the game's load event")
end)

T.test("a title set later still paints in the look's title color", function()
    local DUI = stub.Load()
    local f = DUI.Win.New({ w = 300, h = 200 })
    look(DUI, "classic")
    DUI.Win.SetTitle(f, "Spellbook")
    T.rgb(f.title.__textColor, YELLOW)
end)

T.test("the options window's page title takes the look's title color", function()
    local DUI = stub.Load()
    DUI.OptionsPanel.Show("appearance")
    look(DUI, "classic")
    local t
    local function walk(f)
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetText and r:GetText() == "Appearance" and select(2, r:GetFont()) == DUI.Style.SIZE.title then t = r end
        end
        for _, c in ipairs({ f:GetChildren() }) do walk(c) end
    end
    walk(_G.DaylightUIOptions)
    T.truthy(t, "the header title")
    T.rgb(t.__textColor, YELLOW)
end)

T.test("classic titles use the client's own game font, so a Russian client keeps its letters", function()
    local DUI = stub.Load()
    local was = STANDARD_TEXT_FONT
    local cyr = "Fonts" .. string.char(92) .. "FRIZQT___CYR.TTF"
    _G.STANDARD_TEXT_FONT = cyr
    look(DUI, "classic")
    T.eq(DUI.Style.TitleFont(), cyr)
    _G.STANDARD_TEXT_FONT = was
end)

T.test("a title given its own color keeps it through a repaint", function()
    local DUI = stub.Load()
    local f = DUI.Win.New({ w = 300, h = 200 })
    DUI.Win.SetTitle(f, "Stabby", { 1, 0.96, 0.41 })
    look(DUI, "classic")
    T.rgb(f.title.__textColor, { 1, 0.96, 0.41 }, "the class color stays")
    DUI.Win.SetTitle(f, "Spellbook")
    DUI:Set("general", "softness", 0.2)
    stub.RunTimers()
    T.rgb(f.title.__textColor, YELLOW, "a plain title follows the look")
end)

T.test("pieces painted once at build follow the look: crest disc, cast bar back, skinned game window back", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local tex = UIParent:CreateTexture()
    S.Follow(tex, S.BACKGROUND, 0.85, true)
    look(DUI, "classic")
    T.rgb(tex.__color, hex("0a0a16"))
    T.near(tex.__color[4], 0.85, nil, "its own alpha kept")
end)


T.test("classic numbers are white and section headings yellow, like the game's stat panel", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local n, h = UIParent:CreateFontString(), UIParent:CreateFontString()
    look(DUI, "classic")
    S.InkText(n, "pop")
    S.InkText(h, "heading")
    T.rgb(n.__textColor, { 1, 1, 1 }, "a number")
    T.rgb(h.__textColor, YELLOW, "a heading")
    look(DUI, "daylight")
    S.InkText(n, "pop")
    S.InkText(h, "heading")
    T.rgb(n.__textColor, { S.Accent() }, "daylight: numbers pop in the accent")
    T.rgb(h.__textColor, { S.Accent() }, "and headings too")
end)

T.test("classic bars are the game's plain colors until Gradient bars is on", function()
    local DUI = stub.Load()
    local S, G = DUI.Style, DUI.Gradients
    look(DUI, "classic")
    T.truthy(G.Flat(), "every pair plain")
    T.falsy(G.Off(), "the player's own master switch untouched")
    T.rgb({ S.FlatSweep() }, S.LOOKS.classic.FLAT_BAR, "a Daylight-sweep bar in the game's bar color")
    DUI:Set("general", "lookGradients", true)
    stub.RunTimers()
    T.falsy(G.Flat(), "gradients back")
    look(DUI, "daylight")
    DUI:Set("general", "lookGradients", false)
    stub.RunTimers()
    T.falsy(G.Flat(), "daylight never flattens by itself")
end)

T.test("classic unit frames: green health, power by its type", function()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10,
                              powerType = 1, powerToken = "RAGE", power = 40, maxPower = 100 }
    end })
    local f = ns.frames.player
    look(DUI, "classic")
    ns.UF.UpdateAll(f, true)
    T.falsy(f.health.__gradient, "no sweep")
    T.rgb(f.health.__barColor, DUI.Style.LOOKS.classic.HEALTH, "the game's green")
    DUI:Set("UnitFrames", "colors.power", "gradient")
    stub.RunTimers()
    ns.UF.PaintPower(f.power, "RAGE", "player", f)
    T.rgb(f.power.__barColor, { DUI.Style.PowerColor("RAGE") }, "rage in its own color, not a gradient")
    DUI:Set("general", "lookGradients", true)
    stub.RunTimers()
    ns.UF.UpdateAll(f, true)
    local r, g = f.health.__barColor[1], f.health.__barColor[2]
    T.falsy(math.abs(r - DUI.Style.LOOKS.classic.HEALTH[1]) < 0.01 and math.abs(g - DUI.Style.LOOKS.classic.HEALTH[2]) < 0.01,
        "Gradient bars on: the player's own bar colors again")
end)

T.test("the Gradient bars switch shows only under Classic", function()
    local DUI = stub.Load()
    local item = itemFor(DUI, "lookGradients")
    T.truthy(item and item.type == "toggle")
    T.eq(item.hidden(function(k) return k == "look" and "daylight" or nil end), true)
    T.falsy(item.hidden(function(k) return k == "look" and "classic" or nil end))
end)
