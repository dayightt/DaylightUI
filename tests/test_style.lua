local stub = require("stub")

T.test("Soften desaturates toward the color's gray, then dims it", function()
    local DUI = stub.Load()
    local grey = 0.299
    T.rgb({ DUI.Style.Soften(1, 0, 0) },
        { (1 + (grey - 1) * 0.15) * 0.95, grey * 0.15 * 0.95, grey * 0.15 * 0.95 }, "defaults")
    DUI:Set("general", "brightness", 1)
    stub.RunTimers()   -- the style repaints on the next frame
    DUI:Set("general", "softness", 0)
    stub.RunTimers()   -- the style repaints on the next frame
    T.rgb({ DUI.Style.Soften(1, 0, 0) }, { 1, 0, 0 }, "no softening")
end)

T.test("softened colors are never brighter than the original", function()
    local DUI = stub.Load()
    for _, c in pairs(RAID_CLASS_COLORS) do
        local r, g, b = DUI.Style.Soften(c.r, c.g, c.b)
        T.truthy(r * 0.299 + g * 0.587 + b * 0.114 <= c.r * 0.299 + c.g * 0.587 + c.b * 0.114 + 1e-9)
    end
end)

T.test("class colors are softened Blizzard colors", function()
    local DUI = stub.Load()
    local r, g, b = DUI.Style.ClassColor("MAGE")
    local er, eg, eb = DUI.Style.Soften(0.25, 0.78, 0.92)
    T.near(r, er); T.near(g, eg); T.near(b, eb)
end)

T.test("secret, unknown or missing tokens fall back to neutral", function()
    local DUI = stub.Load()
    local neutral = { DUI.Style.Neutral() }
    T.rgb({ DUI.Style.ClassColor(stub.Secret("MAGE")) }, neutral, "secret class")
    T.rgb({ DUI.Style.ClassColor("NOPE") }, neutral, "unknown class")
    T.rgb({ DUI.Style.ClassColor(nil) }, neutral, "nil class")
    T.rgb({ DUI.Style.ReactionColor(stub.Secret(2)) }, neutral, "secret reaction")
end)

T.test("class text: an unknown class reads warm white, never the bars' gray", function()
    local DUI = stub.Load()
    local v = DUI.Style.INK.VALUE
    T.rgb({ DUI.Style.ClassTextColor(nil) }, v, "nil class")
    T.rgb({ DUI.Style.ClassTextColor(stub.Secret("MAGE")) }, v, "secret class")
    T.rgb({ DUI.Style.ClassTextColor("NOPE") }, v, "unknown class")
    T.rgb({ DUI.Style.ClassTextColor("MAGE") }, { DUI.Style.ClassColor("MAGE") }, "a known class: its color")
end)

T.test("reaction maps hostile / neutral / friendly", function()
    local DUI = stub.Load()
    local S = DUI.Style
    T.rgb({ S.ReactionColor(2) }, { S.Soften(unpack(S.REACTION.hostile)) }, "hostile")
    T.rgb({ S.ReactionColor(4) }, { S.Soften(unpack(S.REACTION.neutral)) }, "neutral")
    T.rgb({ S.ReactionColor(5) }, { S.Soften(unpack(S.REACTION.friendly)) }, "friendly")
end)

T.test("power color: own palette first, then PowerBarColor, else a soft blue", function()
    local DUI = stub.Load()
    local S = DUI.Style
    T.rgb({ S.PowerColor("MANA") }, { S.Soften(unpack(S.POWER.MANA)) }, "mana")
    T.rgb({ S.PowerColor("RAGE") }, { S.Soften(1, 0, 0) }, "rage")
    T.rgb({ S.PowerColor(stub.Secret("RAGE")) }, { S.Soften(unpack(S.POWER_FALLBACK)) }, "secret")
end)

T.test("Lighten moves toward white", function()
    local DUI = stub.Load()
    local r = DUI.Style.Lighten(0.2, 0.2, 0.2, 0.5)
    T.near(r, 0.6)
end)

T.test("Shell adds background, border, shadow, bevel, slant-fill and heavy band pieces once", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local s = DUI.Style.Shell(f)
    T.eq(#stub.Children(s), 35)
    T.eq(DUI.Style.Shell(f), s, "idempotent")
    T.eq(#stub.Children(s), 35)
    T.eq(DUI.Style.GetShell(f), s)
end)

T.test("Shell pieces are sized in physical pixels on 4K", function()
    local DUI = stub.Load({ before = function() stub.SetScreen(3840, 2160, 0.64) end })
    DUI:Set("general", "borderPx", 4)
    DUI:Set("general", "cornerPx", 2)
    stub.RunTimers()   -- the style repaints on the next frame
    local f = CreateFrame("Frame", nil, UIParent)
    local s = DUI.Style.Shell(f)
    local u = (768 / 2160) / 0.64
    T.near(s.border.TOPLEFT:GetWidth(), 2 * u, nil, "corner curve")
    local _, _, _, x, y = s.border.TOP:GetPoint(2)
    T.near(x, -2 * u); T.near(y, -4 * u, nil, "edge is border thick")
    T.near(s.shadow.TOPLEFT:GetWidth(), 8 * u)
    T.near(s.bevelTop:GetHeight(), u)
    T.eq(s.border.TOP:GetNumPoints(), 2)
end)

T.test("Shell border alpha follows the setting", function()
    local DUI = stub.Load()
    local s = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent))
    T.near(s.border.LEFT.__vertex[4], 1)
    DUI:Set("general", "borderAlpha", 0.5)
    stub.RunTimers()   -- the style repaints on the next frame
    T.near(s.border.LEFT.__vertex[4], 0.5)
end)

T.test("window background opacity follows the setting, other shells keep theirs", function()
    local DUI = stub.Load()
    local win = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent), { window = true })
    local plain = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent))
    T.near(win.bg.__color[4], 0.85)
    DUI:Set("general", "windowAlpha", 0.4)
    stub.RunTimers()   -- the style repaints on the next frame
    T.near(win.bg.__color[4], 0.4)
    T.near(plain.bg.__color[4], DUI.Style.BACKGROUND_ALPHA)
end)

T.test("a window can have its own opacity, and General's Apply brings every one back", function()
    local DUI = stub.Load()
    local Book = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent), { window = "Book" })
    local Other = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent), { window = "Inspect" })
    DUI:Set("general", "windowAlpha", 0.6)
    stub.RunTimers()
    T.near(Book.bg.__color[4], 0.6)

    DUI:Set("Book", "windowAlpha", 0.3)
    T.near(Book.bg.__color[4], 0.6)
    DUI:Set("Book", "windowAlphaOwn", true)
    T.near(Book.bg.__color[4], 0.3)
    DUI:Set("Book", "windowAlpha", 0.2)
    T.near(Book.bg.__color[4], 0.2)
    T.near(Other.bg.__color[4], 0.6)

    DUI:Set("general", "windowAlpha", 0.7)
    stub.RunTimers()
    T.near(Book.bg.__color[4], 0.2)
    T.near(Other.bg.__color[4], 0.7)

    DUI.Options.ApplyWindowAlpha()
    T.near(Book.bg.__color[4], 0.7)
    T.eq(DUI:Get("Book", "windowAlphaOwn"), false)
end)

T.test("every separate background opacity is one Apply reaches", function()
    local DUI = stub.Load({ buffs = true, skins = true, bags = true, qol = true, chat = true, infopanel = true, quests = true })
    T.truthy(#DUI.DB.ALL_BACKS >= 18, "panels and windows both listed")
    for _, b in ipairs(DUI.DB.ALL_BACKS) do
        local mod = DUI:GetModule(b[1])
        T.truthy(mod, b[1] .. " is a module")
        T.eq(DUI.DB.GetPath(mod.defaults, b[2] .. "Own"), false, b[1] .. " " .. b[2])
        T.eq(type(DUI.DB.GetPath(mod.defaults, b[2])), "number", b[1] .. " " .. b[2])
    end
end)

T.test("text is outlined with a soft drop shadow", function()
    local DUI = stub.Load()
    local fs = DUI.Style.Text(UIParent, 12)
    T.eq(fs.__font[3], "OUTLINE")
    T.eq(fs.__shadowOffset[1], 1); T.eq(fs.__shadowOffset[2], -1)
    T.near(fs.__shadowColor[4], 0.6)
end)

T.test("noBackground and noBevel hide those layers", function()
    local DUI = stub.Load()
    local s = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent), { noBackground = true, noBevel = true })
    T.falsy(s.bg:IsShown())
    T.falsy(s.bevelTop:IsShown())
end)

T.test("bars use the soft fill over a brushed backing", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local m = S.Bar(UIParent)
    T.eq(m.__barTexture, S.BAR.fill)
    local back
    for _, c in ipairs(stub.Children(m)) do if c.__texture == S.BAR.back then back = c end end
    T.truthy(back, "backing texture")
    S.SetBarColor(m, 0.8, 0.4, 0.2)
    T.rgb(m.__barColor, { 0.8, 0.4, 0.2 }, "fill")
    local k = S.BAR_BACK_DIM
    T.rgb(back.__vertex, { 0.8 * k, 0.4 * k, 0.2 * k }, "backing")
    T.near(back.__vertex[4], S.BAR_BACK_ALPHA)
end)

-- Every text of every closed window, once per slider step.
T.test("a repaint writes only the texts whose font came out different", function()
    local DUI = stub.Load()
    local fs = DUI.Style.Text(UIParent, 14)
    local writes, set = 0, fs.SetFont
    fs.SetFont = function(...) writes = writes + 1; return set(...) end
    DUI:Set("general", "accent", "daylight")
    stub.RunTimers()
    T.eq(writes, 0, "no font in that change")
    DUI:Set("general", "fontScale", 1.5)
    stub.RunTimers()
    T.eq(writes, 1, "text size")
    DUI:Set("general", "font", "fira")
    stub.RunTimers()
    T.eq(writes, 2, "the font")
    T.eq(fs.__font[1], DUI.Style.FONTS.fira.file)
    DUI:Set("general", "textOutline", "THICKOUTLINE")
    stub.RunTimers()
    T.eq(writes, 3, "the outline")
    local before = writes
    DUI:Set("general", "textShadow", false)
    stub.RunTimers()
    T.eq(writes, before + 1, "the shadow")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("Text uses the DaylightUI font and the font scale", function()
    local DUI = stub.Load()
    local fs = DUI.Style.Text(UIParent, 14)
    T.eq(fs.__font[1], DUI.MEDIA .. "fonts\\ExpresswayFree.ttf")
    T.eq(fs.__font[2], 14)
    DUI:Set("general", "fontScale", 1.5)
    stub.RunTimers()   -- the style repaints on the next frame
    T.eq(fs.__font[2], 21)
    -- Picking another font repaints text already on screen.
    DUI:Set("general", "font", "fira")
    stub.RunTimers()   -- the style repaints on the next frame
    T.eq(fs.__font[1], DUI.Style.FONTS.fira.file)
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    DUI:Set("general", "font", "game")
    stub.RunTimers()   -- the style repaints on the next frame
    T.eq(fs.__font[1], "Fonts\\FRIZQT__.TTF", "the client's own font")
    _G.STANDARD_TEXT_FONT = nil
end)

T.test("the local font replaces ours on a Korean client only", function()
    local real = _G.GetLocale
    _G.STANDARD_TEXT_FONT = "Fonts\2002.TTF"
    _G.GetLocale = function() return "koKR" end
    local DUI = stub.Load()
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "localFont", true)
    DUI.Style.PickFont()
    T.eq(DUI.Style.FONT, "Fonts\2002.TTF")
    DUI:Set("general", "localFont", false)
    DUI.Style.PickFont()
    T.eq(DUI.Style.FONT, DUI.Style.FONTS.fira.file)
    _G.GetLocale = function() return "enUS" end
    DUI:Set("general", "localFont", true)
    DUI.Style.PickFont()
    T.eq(DUI.Style.FONT, DUI.Style.FONTS.fira.file)
    _G.GetLocale = real
    _G.STANDARD_TEXT_FONT = nil
end)

-- A game font object: GetFont/SetFont like the client's Font.
local function fakeFont(face, size, flags)
    local f = { face = face, size = size, flags = flags }
    function f:GetFont() return self.face, self.size, self.flags end
    function f:SetFont(a, b, c) self.face, self.size, self.flags = a, b, c end
    return f
end

T.test("game text: the font goes on the game's font objects and comes back off", function()
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.GameFontNormal = fakeFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    _G.LaterFont = fakeFont("Fonts\\ARIALN.TTF", 10, "")
    local names = { "GameFontNormal", "NotAFont" }
    _G.GetFonts = function() return names end
    local DUI = stub.Load()
    local fira = DUI.Style.FONTS.fira.file
    DUI:Set("general", "font", "fira")
    stub.RunTimers()
    T.eq(GameFontNormal.face, "Fonts\\FRIZQT__.TTF", "off by default")

    DUI:Set("general", "gameText", true)
    stub.RunTimers()
    T.eq(GameFontNormal.face, fira, "face swapped")
    T.eq(GameFontNormal.size, 12, "size kept")
    T.eq(GameFontNormal.flags, "OUTLINE", "outline kept")
    T.eq(STANDARD_TEXT_FONT, fira)
    T.eq(DAMAGE_TEXT_FONT, fira, "combat numbers")
    T.eq(DUI.GameFonts.ClientFont(), "Fonts\\FRIZQT__.TTF", "the client's own is remembered")

    names[#names + 1] = "LaterFont"   -- a game window loads its own fonts
    stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI"); stub.RunTimers()   -- walked the frame after
    T.eq(LaterFont.face, fira, "late font objects too")

    DUI:Set("general", "font", "game")   -- the game's own font: nothing to put on
    stub.RunTimers()
    T.eq(DUI.Style.FONT, "Fonts\\FRIZQT__.TTF", "Game font is still the client's")
    T.eq(GameFontNormal.face, "Fonts\\FRIZQT__.TTF", "put back")
    T.eq(LaterFont.face, "Fonts\\ARIALN.TTF", "each to its own")
    T.eq(STANDARD_TEXT_FONT, "Fonts\\FRIZQT__.TTF")

    DUI:Set("general", "font", "fira")
    stub.RunTimers()
    DUI:Set("general", "gameText", false)
    stub.RunTimers()
    T.eq(GameFontNormal.face, "Fonts\\FRIZQT__.TTF", "off puts it back")
    T.eq(DAMAGE_TEXT_FONT, fira, "damage numbers on Automatic keep the Appearance font")
    DUI:Set("general", "damage.font", "game")
    stub.RunTimers()
    T.eq(DAMAGE_TEXT_FONT, "Fonts\\FRIZQT__.TTF", "their own Game font pick puts the client's back")
    _G.STANDARD_TEXT_FONT, _G.DAMAGE_TEXT_FONT, _G.GetFonts = nil, nil, nil
    _G.GameFontNormal, _G.LaterFont = nil, nil
end)

-- The scrolling combat text over the player: the client makes CombatTextFont at
-- 120 with "FILTER, FIXEDHEIGHT" and shrinks each line with SetTextHeight. Any
-- other face keeping those flags spaced every letter out ("B l o c k") in game;
-- the same face with no flags read normally.
T.test("game text: combat text drops the client's fixed-height flags and gets them back", function()
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.CombatTextFont = fakeFont("Fonts\\FRIZQT__.TTF", 120, "FILTER, FIXEDHEIGHT")
    _G.GameFontNormal = fakeFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    _G.GetFonts = function() return { "CombatTextFont", "GameFontNormal" } end
    local DUI = stub.Load()
    local fira = DUI.Style.FONTS.fira.file
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    stub.RunTimers()
    T.eq(CombatTextFont.face, fira)
    T.eq(CombatTextFont.size, 120, "size kept")
    T.eq(CombatTextFont.flags, "", "no fixed height on our face")
    T.eq(GameFontNormal.flags, "OUTLINE", "other flags untouched")

    stub.RunTimers()
    DUI:Set("general", "font", "barlow")   -- a second swap must not lose the client's flags
    stub.RunTimers()
    DUI:Set("general", "gameText", false)
    stub.RunTimers()
    T.eq(CombatTextFont.face, DUI.Style.FONTS.barlow.file, "Automatic keeps the Appearance font")
    DUI:Set("general", "damage.sctFont", "game")
    stub.RunTimers()
    T.eq(CombatTextFont.face, "Fonts\\FRIZQT__.TTF", "the Game font pick puts it back")
    T.eq(CombatTextFont.flags, "FILTER, FIXEDHEIGHT", "with the client's flags")
    _G.STANDARD_TEXT_FONT, _G.GetFonts, _G.CombatTextFont, _G.GameFontNormal = nil, nil, nil, nil
end)

T.test("game text: a font object already wearing ours isn't set again when a window loads", function()
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.GameFontNormal = fakeFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    _G.CombatTextFont = fakeFont("Fonts\\FRIZQT__.TTF", 120, "FILTER, FIXEDHEIGHT")
    _G.GetFonts = function() return { "GameFontNormal", "CombatTextFont" } end
    local DUI = stub.Load()
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    stub.RunTimers()
    local fira = DUI.Style.FONTS.fira.file
    T.eq(GameFontNormal.face, fira)
    local sets = 0
    for _, f in ipairs({ GameFontNormal, CombatTextFont }) do
        local real = f.SetFont
        f.SetFont = function(...) sets = sets + 1 return real(...) end
    end
    stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI"); stub.RunTimers()
    T.eq(sets, 0, "nothing set again")
    GameFontNormal.face = "Fonts\\ARIALN.TTF"   -- someone put another face on it
    stub.FireEvent("ADDON_LOADED", "Blizzard_Calendar"); stub.RunTimers()
    T.eq(sets, 1, "that one is put right")
    T.eq(GameFontNormal.face, fira)
    T.eq(GameFontNormal.flags, "OUTLINE")
    _G.STANDARD_TEXT_FONT, _G.GetFonts, _G.GameFontNormal, _G.CombatTextFont = nil, nil, nil, nil
end)

T.test("game text: the local font on a Korean client keeps the game's text alone", function()
    local real = _G.GetLocale
    _G.GetLocale = function() return "koKR" end
    _G.GameFontNormal = fakeFont("Fonts\\2002.TTF", 12, "")
    _G.GetFonts = function() return { "GameFontNormal" } end
    local DUI = stub.Load()
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "localFont", true)
    DUI:Set("general", "gameText", true)
    stub.RunTimers()
    T.eq(GameFontNormal.face, "Fonts\\2002.TTF")
    _G.GetLocale, _G.GetFonts, _G.GameFontNormal = real, nil, nil
end)

T.test("corner caps round the contents only when the curve is wider than the border", function()
    local DUI = stub.Load()
    DUI:Set("general", "borderPx", 4)
    DUI:Set("general", "cornerPx", 2)
    stub.RunTimers()   -- the style repaints on the next frame
    local f = CreateFrame("Frame", nil, UIParent)
    local s = DUI.Style.Shell(f)
    T.falsy(s.fillet.TOPLEFT:IsShown(), "2px curve on a 4px border needs no caps")
    DUI:Set("general", "cornerPx", 8)
    stub.RunTimers()   -- the style repaints on the next frame
    local u = 768 / 1080
    T.truthy(s.fillet.TOPLEFT:IsShown())
    T.near(s.fillet.TOPLEFT:GetWidth(), 4 * u)
    T.near(s.border.TOPLEFT:GetWidth(), 8 * u)
    local _, _, _, x, y = s.fillet.TOPLEFT:GetPoint(1)
    T.near(x, 4 * u); T.near(y, -4 * u)
end)

T.test("a zero corner curve hides the corner pieces instead of sizing them 0", function()
    local DUI = stub.Load()
    local s = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent))
    DUI:Set("general", "cornerPx", 0)
    stub.RunTimers()   -- the style repaints on the next frame
    for _, key in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        T.falsy(s.border[key]:IsShown(), key)
        T.falsy(s.fillet[key]:IsShown(), key)
    end
    DUI:Set("general", "cornerPx", 2)
    stub.RunTimers()   -- the style repaints on the next frame
    T.truthy(s.border.TOPLEFT:IsShown())
end)

T.test("the corner curve is capped at half the frame's smaller side", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 10)
    local s = DUI.Style.Shell(f)
    s:SetSize(100, 10)
    DUI:Set("general", "cornerPx", 24)
    stub.RunTimers()   -- the style repaints on the next frame
    T.near(s.border.TOPLEFT:GetWidth(), 5)
end)

T.test("a shell whose size reads back secret skips the cap instead of comparing", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 10)
    local s = DUI.Style.Shell(f)
    s:SetSize(100, 10)
    -- Sized from an aura container, the client hands back secret numbers:
    -- still numbers, but comparing one is an error. Flag these two as such.
    local real = _G.issecretvalue
    _G.issecretvalue = function(v) return v == 100 or v == 10 or real(v) end
    local ok, err = pcall(function()
        DUI:Set("general", "cornerPx", 24)
        stub.RunTimers()   -- the style repaints on the next frame
    end)
    _G.issecretvalue = real
    T.truthy(ok, tostring(err))
    T.truthy(s.border.TOPLEFT:GetWidth() > 5, "not capped from a size it can't read")
end)

T.test("with rounded corners the shadow wraps the curve instead of the square", function()
    local DUI = stub.Load()
    local s = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent))
    local u = 768 / 1080
    DUI:Set("general", "cornerPx", 12)
    stub.RunTimers()   -- the style repaints on the next frame
    -- curve 12, shadow 4: the piece whose core is nearest 12/16
    T.truthy(s.shadow.TOPLEFT.__texture:find("shadow%-round%-[78]%.png$"), "core matches the curve")
    DUI:Set("general", "shadowPx", 8)
    stub.RunTimers()
    T.truthy(s.shadow.TOPLEFT.__texture:find("shadow%-round%-6%.png$"), "a wider shadow: a smaller core")
    DUI:Set("general", "shadowPx", 4)
    stub.RunTimers()
    T.near(s.shadow.TOPLEFT:GetWidth(), 16 * u, nil, "curve + shadow")
    local _, _, _, x = s.shadow.TOP:GetPoint(1)
    T.near(x, 12 * u, nil, "top shadow starts where the curve ends")
    DUI:Set("general", "cornerPx", 2)
    stub.RunTimers()   -- the style repaints on the next frame
    T.eq(s.shadow.TOPLEFT.__texture, DUI.MEDIA .. "shadow.png")
end)

T.test("a shadow of 0 is hidden, not drawn at the texture's own size", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 40)
    local s = DUI.Style.Shell(f, { borderPx = 0, cornerPx = 0, shadowPx = 0 })
    DUI.Style.LayoutShell(s)
    for key, tex in pairs(s.shadow) do T.falsy(tex:IsShown(), key) end
    s.opts.shadowPx = 4
    DUI.Style.LayoutShell(s)
    T.truthy(s.shadow.BOTTOM:IsShown(), "back when the shadow has a size")
end)

T.test("the heavy border lays a band a pixel inside the outline", function()
    local DUI = stub.Load()
    DUI:Set("general", "borderPx", 9)
    stub.RunTimers()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 40)
    local s = DUI.Style.Shell(f)
    local u = 768 / 1080
    T.truthy(s.band.TOP:IsShown())
    T.truthy(s.lit:IsShown())
    local _, _, _, x, y = s.band.TOP:GetPoint(1)
    T.near(y, -u, nil, "one pixel in")
    local _, _, _, _, y2 = s.band.TOP:GetPoint(2)
    T.near(y2, -8 * u, nil, "stops a pixel short of the 9px border's inside")
    T.rgb({ s.band.TOP.__vertex[1], s.band.TOP.__vertex[2], s.band.TOP.__vertex[3] }, DUI.Style.BAND, "band")
    DUI:Set("general", "heavyBorder", false)
    stub.RunTimers()   -- the style repaints on the next frame
    T.falsy(s.band.TOP:IsShown())
    T.falsy(s.lit:IsShown())
    DUI:Set("general", "heavyBorder", true)
    stub.RunTimers()   -- the style repaints on the next frame
    DUI:Set("general", "borderPx", 2)
    stub.RunTimers()   -- the style repaints on the next frame
    T.falsy(s.band.TOP:IsShown(), "too thin for a band")
end)

T.test("an angled end carries the band and its inner line on their own lines", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 50)
    local s = DUI.Style.Shell(f)
    DUI.Style.Slant(f, "right", 10)
    T.truthy(s.bandSlant.right:IsShown())
    T.truthy(s.lineSlant.right:IsShown())
    T.falsy(s.bandSlant.left:IsShown())
    local function maskX(tex)
        local m = tex.__masks[#tex.__masks]
        local _, _, _, x = m:GetPoint(1)
        return x
    end
    local band, line, inner = maskX(s.bandSlant.right), maskX(s.lineSlant.right), maskX(s.bg)
    T.truthy(band < 0 and line < band and inner < line, "outline, band, line, contents, from the edge in")
end)

T.test("an angled end masks only what can reach it; a narrow frame keeps every mask", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 20)
    local s = DUI.Style.Shell(f)
    local function masks(tex) return #(tex.__masks or {}) end
    local corner, bandCorner = masks(s.border.TOPLEFT), masks(s.band.BOTTOMLEFT)
    DUI.Style.Slant(f, "right", 12)
    T.eq(masks(s.border.LEFT), 0, "the left edge is far from the cut")
    T.eq(masks(s.border.TOPLEFT), corner, "its corner keeps only its rounding")
    T.eq(masks(s.band.BOTTOMLEFT), bandCorner)
    T.eq(masks(s.fillet.TOPLEFT), 0)
    T.eq(masks(s.border.TOP), 1, "the top runs into the cut")
    T.falsy(s.border.RIGHT:IsShown(), "the right edge lies under the cut's own strips")
    T.falsy(s.band.RIGHT:IsShown())
    T.eq(masks(s.lit), 0, "the lit line stops short of the cut")
    local _, _, _, x = s.lit:GetPoint(2)
    T.truthy(x < -1, "a little in from the edge")
    DUI.Style.Slant(f, "left", 12)
    T.truthy(s.border.RIGHT:IsShown(), "back when the angle moves to the other end")
    T.falsy(s.border.LEFT:IsShown())
    T.eq(masks(s.border.RIGHT), 0)
    -- A combo pip: the cut's mask spans most of it, so nothing is skipped.
    f:SetSize(20, 6)
    DUI.Style.Slant(f, "right", 3)
    T.eq(masks(s.border.LEFT), 1, "a narrow frame keeps the mask")
end)

T.test("a shell can take a thinner border than the general one", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local s = DUI.Style.Shell(f, { borderPx = function(g) return math.floor(g / 2) end })
    T.eq(DUI.Style.BorderPx(f), 4)
    local _, _, _, _, y = s.border.TOP:GetPoint(2)
    T.near(y, -4 * 768 / 1080)
end)

T.test("an angled end's layers are strips that stop short of the contents", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 50)
    local s = DUI.Style.Shell(f)
    DUI.Style.Slant(f, "right", 10)
    local function masks(tex) return tex.__masks or {} end
    T.eq(#masks(s.slantFill.right), 2, "outline: inside the edge, outside the band")
    T.eq(#masks(s.bandSlant.right), 2)
    T.eq(#masks(s.lineSlant.right), 2)
    local stop = masks(s.lineSlant.right)[1]
    T.eq(stop.__texture, DaylightUI.MEDIA .. "mask-trail-r.png")
    T.eq(stop.__wrap, "CLAMPTOBLACKADDITIVE", "nothing past the mask")
    DUI:Set("general", "heavyBorder", false)
    stub.RunTimers()   -- the style repaints on the next frame
    T.eq(#masks(s.slantFill.right), 2, "plain border: the outline stops at the contents")
    DUI.Style.Slant(f, nil, 0)
    T.eq(#masks(s.slantFill.right), 0, "no angle, no masks")
end)

T.test("a cut of 0 is a straight end, not an angled one with nothing to cut", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 50)
    local s = DUI.Style.Shell(f)
    DUI.Style.Slant(f, "right", 10)
    T.falsy(s.border.RIGHT:IsShown(), "angled: the cut takes that end's edge")
    DUI.Style.Slant(f, "right", 0)
    T.isnil(DUI.Style.GetSlant(f).side)
    T.truthy(s.border.RIGHT:IsShown(), "its edge back")
    T.eq(#(s.bg.__masks or {}), 0, "no mask left on the background")
end)

T.test("an end leaning under: its bottom corner sticks out, so both cuts run parallel", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 50)
    local s = DUI.Style.Shell(f)
    local M = DaylightUI.MEDIA
    local function texOf(tex, i) return (tex.__masks or {})[i] and tex.__masks[i].__texture end
    DUI.Style.Slant(f, "both", 10, nil, "left")
    T.eq(DUI.Style.GetSlant(f).under, "left")
    -- The left end's line runs from the cut's width in at the top to the
    -- corner at the bottom: the right end's mask turned half round.
    local bgMasks = {}
    for _, m in ipairs(s.bg.__masks) do bgMasks[m.__texture] = true end
    T.truthy(bgMasks[M .. "mask-trail-r.png"], "left end: the right cut turned round")
    T.truthy(bgMasks[M .. "mask-slant-r.png"], "right end: as ever")
    T.falsy(bgMasks[M .. "mask-slant-l.png"], "not the mirrored cut")
    T.eq(texOf(s.lineSlant.left, 1), M .. "mask-slant-r.png", "its stop keeps the other side of the same line")
    -- Shadows: along the top it starts past the cut, along the bottom at the corner.
    local T1 = DUI.Pixel.Px(f, DUI.Style.BorderPx(f))
    local _, _, _, topX = s.shadow.TOP:GetPoint(1)
    local _, _, _, botX = s.shadow.BOTTOM:GetPoint(1)
    T.near(topX, 10 + T1, nil, "top shadow starts where the cut meets the top")
    T.near(botX, T1, nil, "bottom shadow runs out to the corner")
    T.truthy(s.shadow.BOTTOMLEFT:IsShown(), "the bottom corner is the one that sticks out")
    local _, _, _, cx = s.shadow.TOPLEFT:GetPoint(1)
    T.truthy(cx > 10, "the top corner's shadow sits in where the cut meets the top")
    local _, _, _, litX = s.lit:GetPoint(1)
    T.truthy(litX > 9, "the lit line starts in past the cut")
    -- Back to a plain slant: the mirrored mask again.
    DUI.Style.Slant(f, "both", 10)
    bgMasks = {}
    for _, m in ipairs(s.bg.__masks) do bgMasks[m.__texture] = true end
    T.truthy(bgMasks[M .. "mask-slant-l.png"])
    T.near(select(4, s.shadow.TOP:GetPoint(1)), T1, nil, "top shadow at the corner again")
end)

T.test("the accent: Daylight purple, or the player's class color", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local r, g, b = S.Accent()
    T.eq(r, S.ACCENT[1]); T.eq(b, S.ACCENT[3])
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE" }
    DUI:Set("general", "accent", "class")
    stub.RunTimers()   -- the style repaints on the next frame
    r, g, b = S.Accent()
    T.eq(r, RAID_CLASS_COLORS.MAGE.r); T.eq(g, RAID_CLASS_COLORS.MAGE.g); T.eq(b, RAID_CLASS_COLORS.MAGE.b)
end)

T.test("rounded corners show only a ring of border, so a frame with just a background has no dark blobs", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 60)
    local s = DUI.Style.Shell(f)
    s:SetSize(200, 60)
    local function holed(tex)
        for _, m in ipairs(tex.__masks or {}) do
            if type(m.__texture) == "string" and string.find(m.__texture, "mask-hole", 1, true) then return m end
        end
    end
    DUI:Set("general", "cornerPx", 2)
    stub.RunTimers()   -- the style repaints on the next frame
    T.falsy(holed(s.border.TOPLEFT), "nearly square: the piece is all border")
    DUI:Set("general", "cornerPx", 17)
    stub.RunTimers()   -- the style repaints on the next frame
    local m = holed(s.border.TOPLEFT)
    T.truthy(m, "rounded: the inside is cleared")
    T.eq(m:GetPoint(1), "BOTTOMRIGHT", "around the curve's center")
    T.truthy(holed(s.band.TOPLEFT), "the band too")
    DUI:Set("general", "cornerPx", 2)
    stub.RunTimers()   -- the style repaints on the next frame
    T.falsy(holed(s.border.TOPLEFT), "and whole again")
end)

T.test("an angled end is a sharp corner; only the square end is rounded", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 40)
    local s = DUI.Style.Shell(f)
    s:SetSize(200, 40)
    DUI:Set("general", "cornerPx", 17)
    stub.RunTimers()   -- the style repaints on the next frame
    DUI.Style.Slant(f, "right", 12)
    T.falsy(s.border.TOPRIGHT:IsShown(), "no round corner under the cut")
    T.falsy(s.fillet.TOPRIGHT:IsShown())
    T.truthy(s.border.TOPLEFT:IsShown(), "the square end stays round")
    local _, _, _, x = s.border.TOP:GetPoint(2)
    T.eq(x, 0, "the top edge runs out to the cut")
end)

T.test("aura times read 13m and 7s, not 13 m: the client formats them with our rules", function()
    local DUI = stub.Load()
    local f = DUI.Style.DurationFormatter()
    T.truthy(f, "a formatter")
    T.eq(f.steps[1].format, "", "nothing under a second (a no-end aura reports 0)")
    T.eq(f.steps[2].format, "%ds")
    T.eq(f.steps[3].format, "%dm"); T.eq(f.steps[3].components[1].div, 60)
    T.eq(f.steps[4].format, "%dh")
    local btn = CreateFrame("Button", nil, UIParent)
    function btn:SetDurationText(fs, opts) self.fs, self.opts = fs, opts end
    local fs = btn:CreateFontString()
    DUI.Style.SetAuraTime(btn, fs)
    T.eq(btn.opts.textFormatter, f)
    -- Without the formatter the client's own text stays.
    local util = _G.C_StringUtil
    _G.C_StringUtil = nil
    DUI = stub.Load()
    btn.opts = nil
    DUI.Style.SetAuraTime(btn, fs)
    _G.C_StringUtil = util
    T.isnil(btn.opts)
end)

T.test("style: bar times read 9, 42, then 2:58, rounded up on the whole value so 59.6 never reads 0:60", function()
    local DUI = stub.Load()
    local f = DUI.Style.ClockFormatter()
    T.truthy(f, "a formatter")
    T.eq(f.steps[1].format, "", "nothing at 0 (an aura with no end)")
    local sec = f.steps[2]
    T.eq(sec.format, "%d", "under a minute: just the seconds, no 0: and no leading 0")
    T.eq(sec.rounding, Enum.NumericRuleFormatRounding.Up); T.eq(sec.step, 1)
    T.isnil(sec.components)
    local mss = f.steps[3]
    T.eq(mss.threshold, 59.0001, "59.5 rounds up to 60: it goes to 1:00, never \"60\"")
    T.eq(mss.format, "%d:%02d")
    T.eq(mss.rounding, Enum.NumericRuleFormatRounding.Up); T.eq(mss.step, 1)
    T.eq(mss.components[1].div, 60); T.eq(mss.components[2].mod, 60)
    T.isnil(mss.components[1].step, "the parts only divide")
    T.eq(f.steps[4].format, "%dh"); T.eq(f.steps[4].components[1].div, 3600)
    local btn = CreateFrame("Button", nil, UIParent)
    function btn:SetDurationText(fs, opts) self.fs, self.opts = fs, opts end
    DUI.Style.SetAuraTime(btn, btn:CreateFontString(), nil, f)
    T.eq(btn.opts.textFormatter, f, "handed to an aura button")
end)

T.test("style: aura time takes a color curve, and falls back when the client refuses it", function()
    local DUI = stub.Load()
    local btn, fs = {}, {}
    function btn:SetDurationText(f, opts) self.fs, self.opts = f, opts end
    local tc = { curve = {}, property = 0 }
    T.eq(DUI.Style.SetAuraTime(btn, fs, tc), true)
    T.eq(btn.opts.textColor, tc)
    function btn:SetDurationText(f, opts)
        if opts and opts.textColor then error("refused") end
        self.fs, self.opts = f, opts
    end
    T.falsy(DUI.Style.SetAuraTime(btn, fs, tc), "refused: plain timer")
    T.isnil(btn.opts and btn.opts.textColor)
end)

T.test("a style change repaints once a frame, the shells on screen now and hidden ones when shown", function()
    local DUI = stub.Load()
    local shown = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent))
    local closedWindow = CreateFrame("Frame", nil, UIParent)
    closedWindow:Hide()
    local hidden = DUI.Style.Shell(CreateFrame("Frame", nil, closedWindow))
    local laid = 0
    local layout = DUI.Style.LayoutShell
    DUI.Style.LayoutShell = function(s) if s == shown then laid = laid + 1 end return layout(s) end
    for a = 0.5, 0.9, 0.1 do DUI:Set("general", "borderAlpha", a) end   -- a slider dragged
    T.eq(laid, 0, "not on every step")
    stub.RunTimers()
    T.eq(laid, 1, "once, the frame after")
    DUI.Style.LayoutShell = layout
    T.truthy(hidden.dirty, "the hidden one waits")
    T.near(hidden.border.LEFT.__vertex[4], 1, 1e-6, "still the old look")
    closedWindow:Show()
    hidden:GetScript("OnShow")(hidden)
    T.near(hidden.border.LEFT.__vertex[4], 0.9, 1e-6, "the new look when shown")
end)

T.test("recoloring a shell to the color it has is free", function()
    local DUI = stub.Load()
    local s = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent))
    DUI.Style.SetShellColors(s, { 1, 0, 0 }, nil)
    local laid = 0
    local layout = DUI.Style.LayoutShell
    DUI.Style.LayoutShell = function(x) laid = laid + 1 return layout(x) end
    DUI.Style.SetShellColors(s, { 1, 0, 0 }, nil)
    DUI.Style.LayoutShell = layout
    T.eq(laid, 0, "the same color in a new table isn't a change")
end)

T.test("recoloring a shell paints its colors without laying it out", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 30)
    local s = DUI.Style.Shell(f)
    local laid = 0
    local layout = DUI.Style.LayoutShell
    DUI.Style.LayoutShell = function(x) laid = laid + 1 return layout(x) end
    DUI.Style.SetShellColors(s, { 1, 0, 0 }, { 0, 1, 0 })
    T.eq(laid, 0, "no layout for a color")
    T.near(s.border.TOPLEFT.__vertex[1], 1, 1e-6, "outline corner red")
    T.near(s.border.LEFT.__vertex[2], 0, 1e-6, "outline edge red")
    T.near(s.fillet.TOPLEFT.__vertex[1], 1, 1e-6, "fillet red")
    T.near(s.band.TOP.__vertex[2], 1, 1e-6, "band green")
    DUI.Style.SetShellColors(s, nil, nil)
    local nb = DUI.Style.BORDER
    T.near(s.border.TOP.__vertex[1], nb[1], 1e-6, "back to normal")
    T.eq(laid, 0)
    DUI.Style.LayoutShell = layout
end)

T.test("a secret threat flag reuses its color objects while the colors stay", function()
    local DUI = stub.Load()
    local s = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent))
    local made = 0
    local real = _G.CreateColor
    _G.CreateColor = function(...) made = made + 1 return real(...) end
    local red, band = { 1, 0, 0 }, { 0.5, 0, 0 }
    DUI.Style.ShellColorsFromBoolean(s, stub.Secret(true), red, band)
    local first = made
    DUI.Style.ShellColorsFromBoolean(s, stub.Secret(false), { 1, 0, 0 }, { 0.5, 0, 0 })
    T.eq(made, first, "same colors: none made")
    DUI.Style.ShellColorsFromBoolean(s, stub.Secret(true), { 0, 0, 1 }, band)
    T.truthy(made > first, "a new color: made again")
    _G.CreateColor = real
end)

T.test("a shell on a frame the client restricts (no scripts allowed) still repaints, at once", function()
    local DUI = stub.Load()
    local closed = CreateFrame("Frame", nil, UIParent)
    closed:Hide()
    local host = CreateFrame("Frame", nil, closed)
    local realCreate = _G.CreateFrame
    _G.CreateFrame = function(...)
        local f = realCreate(...)
        f.SetScript = function() error("Cannot assign script handler for 'onshow' (blocked by secret aspects)") end
        return f
    end
    local ok, s = pcall(DUI.Style.Shell, host)
    _G.CreateFrame = realCreate
    T.truthy(ok, tostring(s))
    T.truthy(s.alwaysLayout, "marked to lay out at once")
    DUI:Set("general", "borderAlpha", 0.5)
    stub.RunTimers()
    T.near(s.border.LEFT.__vertex[4], 0.5, 1e-6, "repainted though hidden")
end)

T.test("the accent can be Daylight's, the class's, or a color of your own", function()
    local DUI = stub.Load()
    local r = DUI.Style.Accent()
    T.near(r, DUI.Style.ACCENT[1], 1e-6, "Daylight's by default")
    DUI:Set("general", "accentColor", { 0.1, 0.8, 0.3 })
    DUI:Set("general", "accent", "custom")
    stub.RunTimers()
    local cr, cg, cb = DUI.Style.Accent()
    T.near(cr, 0.1, 1e-6); T.near(cg, 0.8, 1e-6); T.near(cb, 0.3, 1e-6, "your own")
    T.truthy(DUI.Style.ACCENTS.custom, "a choice in the list")
end)

T.test("style: the text outline and shadow are settings", function()
    local DUI = stub.Load()
    local fs = DUI.Style.Text(UIParent, 12)
    T.eq(fs.__font[3], "OUTLINE", "thin by default")
    DUI:Set("general", "textOutline", "THICKOUTLINE")
    DUI:Set("general", "textShadow", false)
    stub.RunTimers()
    T.eq(fs.__font[3], "THICKOUTLINE")
    T.eq(fs.__shadowColor and fs.__shadowColor[4] or 0, 0, "no shadow")
end)

T.test("style: DressText puts our font on someone else's text and keeps it up with the settings", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local fs = UIParent:CreateFontString()
    S.DressText(fs, 10)
    local eb = CreateFrame("EditBox", nil, UIParent)
    S.DressText(eb, 12, { outline = "" })
    local locked = UIParent:CreateFontString()
    S.DressText(locked, 9, { untracked = true })
    T.eq(fs.__font[1], S.FONT); T.eq(fs.__font[2], 10); T.eq(fs.__font[3], "OUTLINE")
    T.eq(eb.__font[3], "", "an edit box gets no outline")
    DUI:Set("general", "fontScale", 1.5)
    DUI:Set("general", "textShadow", false)
    DUI:Set("general", "textOutline", "THICKOUTLINE")
    stub.RunTimers()
    T.eq(fs.__font[2], 15, "Text size followed"); T.eq(fs.__font[3], "THICKOUTLINE")
    T.eq(fs.__shadowColor[4], 0, "Shadow followed")
    T.eq(eb.__font[2], 18); T.eq(eb.__font[3], "", "still none")
    T.eq(locked.__font[2], 9, "an untracked one is left alone")
    S.DressText(fs)
    T.eq(fs.__font[2], 15, "no size: the one it had")
end)

T.test("the Daylight gradient accent: shapes sweep blue to orange, text takes the middle purple", function()
    local DUI = stub.Load()
    DUI:Set("general", "accent", "gradient")
    local r, g, b = DUI.Style.Accent()
    T.near(r, 0.635, 0.001); T.near(g, 0.369, 0.001); T.near(b, 0.780, 0.001)
    local tex = UIParent:CreateTexture()
    DUI.Style.PaintAccent(tex)
    T.truthy(tex.__gradient, "a gradient across the shape")
    T.eq(tex.__gradient[1], "HORIZONTAL")
end)

T.test("a side overlapped by a stacked neighbor casts no shadow", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 20)
    local s = DUI.Style.Shell(f)
    DUI.Style.Seams(f, false, true)
    T.falsy(s.shadow.BOTTOM:IsShown()); T.falsy(s.shadow.BOTTOMRIGHT:IsShown())
    T.truthy(s.shadow.TOP:IsShown(), "the open side keeps its shadow")
    DUI.Style.Seams(f, false, false)
    T.truthy(s.shadow.BOTTOM:IsShown())
end)

T.test("side shadows run on through a seam, shadowing the shared line once", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 20)
    local s = DUI.Style.Shell(f)
    DUI.Style.Seams(f, true, true)
    local B = DUI.Pixel.Px(s, DUI.DB.General().borderPx)
    for _, k in ipairs({ "LEFT", "RIGHT" }) do
        local p1, p2 = s.shadow[k].__points[1], s.shadow[k].__points[2]
        T.eq(p1[5], -B, k .. " starts below the shared border line")
        T.eq(p2[5], 0, k .. " runs to the bottom edge")
    end
end)

T.test("an angled side casts a shadow leaning with the cut", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 20)
    local s = DUI.Style.Shell(f)
    DUI.Style.Slant(f, "right", 10)
    local r = s.shadow.RIGHT
    T.truthy(r:IsShown())
    local B = DUI.Pixel.Px(s, DUI.DB.General().borderPx)
    T.eq(r.__points[1][4], -10 * (20 - B) / 20, "on the line where the strip ends, above the corner")
    local c = s.shadow.BOTTOMRIGHT
    T.truthy(c:IsShown(), "a square corner where the cut meets the bottom")
    T.eq(c.__points[1][4], -(10 + B))
    T.truthy(r.__vertexOffsets[1][1] > 0 and r.__vertexOffsets[3][1] > 0, "top sheared out")
    T.eq(r.__vertexOffsets[1][1], r.__vertexOffsets[3][1])
    DUI.Style.Slant(f, nil, 0)
    T.eq(r.__vertexOffsets[1][1], 0, "square again")
end)

T.test("corner caps hang off the shell, so they fade and hide with it", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    local s = DUI.Style.Shell(f)
    T.eq(s.over:GetParent(), s)
end)

T.test("bars: range and value go straight to the bar, nothing laid over it", function()
    local DUI = stub.Load()
    local bar = DUI.Style.Bar(UIParent)
    DUI.Style.SetBarRange(bar, 0, 10)
    DUI.Style.SetBarValue(bar, 4)
    T.eq(bar.__max, 10); T.eq(bar:GetValue(), 4)
    T.eq(select("#", bar:GetChildren()), 0, "no trail bars")
end)

-- The class gradient accent: the player's class pair, its dark end lifted.
local function classGradientLogin(class)
    local DUI = stub.Load()
    stub.units.player = { name = "Me", isPlayer = true, class = class or "MAGE" }
    DUI:Set("general", "accent", "classGradient")
    stub.RunTimers()
    local lo, hi = DUI.Gradients.RGB(class or "MAGE")
    local k = DUI.Style.CLASS_LIFT
    local dark = { lo[1] + (hi[1] - lo[1]) * k, lo[2] + (hi[2] - lo[2]) * k, lo[3] + (hi[3] - lo[3]) * k }
    return DUI, DUI.Style, dark, hi
end

T.test("the class gradient accent: a choice of its own, shapes run the class pair, text its middle", function()
    local DUI, S, lo, hi = classGradientLogin("MAGE")
    T.truthy(S.ACCENTS.classGradient, "a choice in the list")
    T.eq(S.AccentSweep(), "class")
    T.truthy(S.GradientAccent())
    local a, b = S.AccentPair()
    T.rgb(a, lo, "the dark end, lifted"); T.rgb(b, hi, "the light end")
    T.rgb({ S.Accent() }, { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }, "text takes the middle")
    local tex = UIParent:CreateTexture()
    S.PaintAccent(tex)
    T.eq(tex.__gradient[1], "HORIZONTAL")
    T.near(tex.__gradient[2].r, lo[1], 1e-6); T.near(tex.__gradient[3].r, hi[1], 1e-6)
    S.PaintAccent(tex, 1, "VERTICAL")
    T.eq(tex.__gradient[1], "VERTICAL", "a shape can run it upward")
    T.rgb({ S.AccentAt(0) }, lo, "a list's first row the dark end")
    T.rgb({ S.AccentAt(1) }, hi, "its last the light end")
end)

T.test("the class gradient accent follows your edits to the class's pair", function()
    local DUI, S = classGradientLogin("MAGE")
    DUI.Gradients.SetPair("MAGE", { 0, 0, 0 }, { 1, 0, 0 })
    stub.RunTimers()
    local a, b = S.AccentPair()
    T.rgb(b, { 1, 0, 0 }, "the new light end")
    T.near(a[1], S.CLASS_LIFT, 1e-6, "the new dark end, lifted")
end)

T.test("the class gradient accent: no class known yet, one color", function()
    local DUI = stub.Load()
    stub.units.player = nil
    DUI:Set("general", "accent", "classGradient")
    stub.RunTimers()
    T.isnil(DUI.Style.AccentSweep())
    T.falsy(DUI.Style.GradientAccent())
    local r = DUI.Style.Accent()
    T.eq(type(r), "number")
    local text, coloured = DUI.Style.AccentText("Elwynn")
    T.eq(text, "Elwynn"); T.falsy(coloured)
end)

T.test("accent text: letter by letter along a gradient accent, plain otherwise", function()
    local DUI, S, lo, hi = classGradientLogin("MAGE")
    local text, coloured = S.AccentText("Ab")
    T.truthy(coloured)
    T.eq(text, string.format("|cff%02x%02x%02xA|cff%02x%02x%02xb|r",
        math.floor(lo[1] * 255 + 0.5), math.floor(lo[2] * 255 + 0.5), math.floor(lo[3] * 255 + 0.5),
        math.floor(hi[1] * 255 + 0.5), math.floor(hi[2] * 255 + 0.5), math.floor(hi[3] * 255 + 0.5)))
    local fs = UIParent:CreateFontString()
    S.PaintAccentText(fs, "Zone")
    T.rgb(fs.__textColor, { 1, 1, 1 }, "drawn on white")
    DUI:Set("general", "accent", "gradient")
    T.eq(select(1, S.AccentText("Zone")), DUI.GradientText("Zone"), "the Daylight one is the logo's sweep")
    DUI:Set("general", "accent", "daylight")
    S.PaintAccentText(fs, "Zone")
    T.eq(fs.__text, "Zone", "one color: the text as it was")
    T.rgb(fs.__textColor, S.ACCENT, "in the accent")
    local secret = stub.Secret("Name")
    DUI:Set("general", "accent", "classGradient")
    T.eq(S.AccentText(secret), secret, "a secret comes back as it was")
end)

T.test("gradient window borders sweep along the class gradient accent too", function()
    local DUI, S, lo, hi = classGradientLogin("PRIEST")
    DUI:Set("general", "gradientBorder", true)
    DUI:Set("general", "heavyBorder", false)
    stub.RunTimers()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 50)
    local s = S.Shell(f)
    local top = s.border.TOP.__gradient
    T.truthy(top, "the top edge sweeps")
    T.near(top[2].r, lo[1], 1e-6); T.near(top[3].r, hi[1], 1e-6)
end)

T.test("a shell lit in the accent sweeps its outline along a gradient accent, one color otherwise", function()
    local DUI, S, lo, hi = classGradientLogin("MAGE")
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(100, 50)
    local s = S.Shell(f)
    S.LightShell(s, 0.5)
    T.truthy(s.opts.borderPair, "a pair on the outline")
    T.rgb(s.opts.borderPair[1], lo); T.rgb(s.opts.borderPair[2], hi)
    local mid = { S.Accent() }
    T.rgb(s.opts.bandColor, { mid[1] * 0.5, mid[2] * 0.5, mid[3] * 0.5 }, "the band dimmed")
    local pair = s.opts.borderPair
    S.LightShell(s, 0.5)
    T.eq(s.opts.borderPair, pair, "lit again: the same pair, nothing repainted")
    DUI:Set("general", "accent", "daylight")
    S.LightShell(s)
    T.isnil(s.opts.borderPair, "one color")
    T.rgb(s.opts.borderColor, S.ACCENT)
end)

T.test("a bar in the accent: Daylight's image, the class pair across the fill, or one color", function()
    local DUI, S, lo, hi = classGradientLogin("MAGE")
    local bar = S.Bar(UIParent)
    T.truthy(S.PaintAccentBar(bar))
    local g = bar:GetStatusBarTexture().__gradient
    T.truthy(g, "the class pair across the fill")
    T.near(g[2].r, lo[1], 1e-6); T.near(g[3].r, hi[1], 1e-6)
    DUI:Set("general", "accent", "gradient")
    T.truthy(S.PaintAccentBar(bar))
    T.eq(bar:GetStatusBarTexture().__texture, S.GRADIENT_FILE, "the Daylight sweep's image")
    DUI:Set("general", "accent", "daylight")
    T.falsy(S.PaintAccentBar(bar))
    T.truthy(bar:GetStatusBarTexture().__texture ~= S.GRADIENT_FILE, "our own fill again")
end)

T.test("ink: roles exist, none is a neutral gray, Tips shares them", function()
    local DUI = stub.Load()
    local INK = DUI.Style.INK
    T.truthy(type(INK) == "table", "Style.INK")
    for _, k in ipairs({ "TITLE", "VALUE", "TEXT", "LABEL", "OFF", "GOOD", "WARN", "BAD", "DAMAGE", "MONEY" }) do
        local c = INK[k]
        T.truthy(type(c) == "table" and #c == 3, k)
        local hi, lo = math.max(c[1], c[2], c[3]), math.min(c[1], c[2], c[3])
        T.truthy(lo >= 0.99 or hi - lo > 0.04, k .. " is white or not a neutral gray")
    end
    -- brightest to dimmest: white, soft white, tan, dim
    T.truthy(INK.VALUE[1] >= INK.TEXT[1] and INK.TEXT[2] > INK.LABEL[2] and INK.LABEL[2] > INK.OFF[2], "the ladder")
    T.eq(DUI.Tips.TITLE, INK.TITLE); T.eq(DUI.Tips.VALUE, INK.VALUE); T.eq(DUI.Tips.TEXT, INK.TEXT)
    T.eq(DUI.Tips.LABEL, INK.LABEL); T.eq(DUI.Tips.MONEY, INK.MONEY)
end)

T.test("ink: the options window's text colors are the same ones", function()
    local DUI = stub.Load()
    local INK, C = DUI.Style.INK, DUI.OptionsTheme.COLORS
    T.eq(C.text, INK.TEXT); T.eq(C.value, INK.VALUE); T.eq(C.dim, INK.LABEL)
    T.eq(C.faint, INK.OFF); T.eq(C.warn, INK.BAD)
    -- A button's words follow the look (gold under Classic), soft white here.
    T.rgb(DUI.Widgets.BUTTON.text, INK.TEXT, "a button's words")
end)

T.test("ink: InkText paints a role, pop follows the accent", function()
    local DUI = stub.Load()
    local fs = UIParent:CreateFontString()
    DUI.Style.InkText(fs, "LABEL")
    T.rgb({ fs:GetTextColor() }, DUI.Style.INK.LABEL, "label")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    DUI:Set("general", "accent", "custom")
    stub.RunTimers()
    DUI.Style.InkText(fs, "pop")
    T.rgb({ fs:GetTextColor() }, { 0.2, 0.6, 0.9 }, "pop")
    T.rgb({ DUI.Style.Pop() }, { 0.2, 0.6, 0.9 }, "Pop()")
end)

T.test("class colors take a class-color addon's table first, else the game's", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local r = S.RawClassColor("MAGE")
    T.eq(r, RAID_CLASS_COLORS.MAGE.r, "the game's")
    _G.CUSTOM_CLASS_COLORS = { MAGE = { r = 0.1, g = 0.2, b = 0.3 } }
    local ok, err = pcall(function()
        local cr, cg, cb = S.RawClassColor("MAGE")
        T.rgb({ cr, cg, cb }, { 0.1, 0.2, 0.3 }, "the addon's")
        T.eq(S.RawClassColor("HUNTER"), RAID_CLASS_COLORS.HUNTER.r, "a class the addon left out")
        T.isnil(S.RawClassColor("NOPE"), "unknown")
        T.isnil(S.RawClassColor(nil), "nil")
        T.isnil(S.RawClassColor(stub.Secret("MAGE")), "secret")
    end)
    _G.CUSTOM_CLASS_COLORS = nil
    assert(ok, err)
end)

-- A shown party frame's aura rows hold 20 buttons the client builds up front,
-- so what each one's shell makes is most of the cost of someone joining.
T.test("a lean shell makes only what a thin border draws, and draws it the same", function()
    local DUI = stub.Load()
    local Style = DUI.Style
    local function shell(opts)
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(24, 24)
        return Style.Shell(f, opts)
    end
    local full = shell({ noBackground = true, noBevel = true, borderPx = 2 })
    local lean = shell({ noBackground = true, noBevel = true, borderPx = 2, lean = true })
    local function regions(s)
        local n = #{ s:GetRegions() }
        for _, c in ipairs({ s:GetChildren() }) do n = n + #{ c:GetRegions() } end
        return n
    end
    T.truthy(regions(lean) <= 24, "lean: " .. regions(lean) .. " pieces, full: " .. regions(full))
    for _, set in ipairs({ "border", "shadow", "fillet" }) do
        for key, a in pairs(full[set]) do
            local b = lean[set][key]
            T.truthy(b, set .. " " .. key .. " is there")
            T.eq(b:IsShown(), a:IsShown(), set .. " " .. key .. " shown")
            T.deq({ b:GetVertexColor() }, { a:GetVertexColor() }, set .. " " .. key .. " color")
            T.eq(b:GetWidth(), a:GetWidth(), set .. " " .. key .. " width")
            T.eq(b:GetHeight(), a:GetHeight(), set .. " " .. key .. " height")
            local p1, _, r1, x1, y1 = a:GetPoint(1)
            local p2, _, r2, x2, y2 = b:GetPoint(1)
            T.deq({ p2, r2, x2, y2 }, { p1, r1, x1, y1 }, set .. " " .. key .. " spot")
        end
    end
    -- No border (a debuff: its dispel edge is the border): the shadow alone.
    local bare = shell({ noBackground = true, noBevel = true, borderPx = 2, noBorder = true, lean = true })
    T.eq(regions(bare), 8, "the shadow's corners and edges")
    T.isnil(next(bare.border), "no outline made")
    T.isnil(bare.over, "no corner caps")
    Style.LayoutShell(bare)
    Style.PaintShellColors(bare)
    Style.LayoutShell(lean)
end)

-- Without CLAMP the game blends a texture's edge with its far edge: the
-- corner art's straight sides, where it meets the rest of the border, went
-- half see-through and showed as stray dots and bars on anything round.
T.test("the corner art never blends across its edges", function()
    local DUI = _G.DaylightUI
    local Style = DUI.Style
    local s = Style.Shell(CreateFrame("Frame", nil, UIParent), { borderPx = 8 })
    for _, key in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        T.eq(s.border[key].__wrap, "CLAMP", "outline " .. key)
        T.eq(s.band[key].__wrap, "CLAMP", "band " .. key)
        T.eq(s.fillet[key].__wrap, "CLAMP", "cap " .. key)
    end
    local ring = UIParent:CreateTexture()
    Style.RingCorner(ring, "TOPLEFT", 4, "x")
    T.eq(ring.__wrap, "CLAMP", "a ring's corner")
end)
