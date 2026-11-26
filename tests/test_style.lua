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

T.test("window background color: windows and panels follow it, other shells keep theirs", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local win = S.Shell(CreateFrame("Frame", nil, UIParent), { window = true })
    local panel = S.Shell(CreateFrame("Frame", nil, UIParent), { bgAlpha = 0.5, panel = true })
    local plain = S.Shell(CreateFrame("Frame", nil, UIParent))
    T.near(win.bg.__color[1], S.BACKGROUND[1])

    DUI:Set("general", "windowTintColor", { 0.2, 0.1, 0.05 })
    DUI:Set("general", "windowTint", "custom")
    stub.RunTimers()
    T.near(win.bg.__color[1], 0.2)
    T.near(panel.bg.__color[3], 0.05)
    T.near(panel.bg.__color[4], 0.5)   -- the panel keeps its own opacity
    T.near(plain.bg.__color[1], S.BACKGROUND[1])

    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE" }
    DUI:Set("general", "windowTint", "class")
    stub.RunTimers()
    local r, g, b = S.RawClassColor(select(2, UnitClass("player")))
    T.truthy(r, "the fake player has a class")
    local k = S.CLASS_BACK_MIX
    T.near(win.bg.__color[1], S.BACKGROUND[1] + (r * 0.5 - S.BACKGROUND[1]) * k)
    T.near(plain.bg.__color[2], S.BACKGROUND[2])

    DUI:Set("general", "windowTint", "daylight")
    stub.RunTimers()
    T.near(win.bg.__color[1], S.BACKGROUND[1])
end)

T.test("a window can have its own look, starting from General's, and General's Apply brings every one back", function()
    local DUI = stub.Load()
    local Book = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent), { window = "Book" })
    local Other = DUI.Style.Shell(CreateFrame("Frame", nil, UIParent), { window = "Inspect" })
    DUI:Set("general", "windowAlpha", 0.6)
    DUI:Set("general", "borderPx", 4)
    stub.RunTimers()
    T.near(Book.bg.__color[4], 0.6)

    DUI:Set("Book", "frameStyle.windowAlpha", 0.3)
    T.near(Book.bg.__color[4], 0.6, nil, "its own values wait for the switch")
    DUI:Set("Book", "frameStyle.windowAlpha", 0.85)
    DUI:Set("Book", "frameStyle.global", false)
    T.near(DUI:Get("Book", "frameStyle.windowAlpha"), 0.6, nil, "it starts from what General shows")
    T.eq(DUI:Get("Book", "frameStyle.borderPx"), 4)
    T.near(Book.bg.__color[4], 0.6, nil, "so nothing jumps")

    DUI:Set("Book", "frameStyle.windowAlpha", 0.2)
    T.near(Book.bg.__color[4], 0.2)
    T.near(Other.bg.__color[4], 0.6)
    DUI:Set("Book", "frameStyle.borderAlpha", 0.5)
    T.near(Book.border.LEFT.__vertex[4], 0.5, nil, "its border too, at once")
    T.near(Other.border.LEFT.__vertex[4], 1)

    DUI:Set("general", "windowAlpha", 0.7)
    stub.RunTimers()
    T.near(Book.bg.__color[4], 0.2)
    T.near(Other.bg.__color[4], 0.7)

    DUI.Options.ApplyGlobalStyle()
    T.near(Book.bg.__color[4], 0.7)
    T.near(Book.border.LEFT.__vertex[4], 1)
    T.eq(DUI:Get("Book", "frameStyle.global"), true)
end)

T.test("a value already set on a section stays when its global style goes off", function()
    local DUI = stub.Load()
    DUI:Set("general", "borderPx", 4)
    DUI:Set("Book", "frameStyle.shadowPx", 9)
    DUI:Set("Book", "frameStyle.global", false)
    T.eq(DUI:Get("Book", "frameStyle.shadowPx"), 9)
    T.eq(DUI:Get("Book", "frameStyle.borderPx"), 4)
end)

T.test("every section's look is one General's Apply reaches, and starts on the global style", function()
    local DUI = stub.Load({ buffs = true, skins = true, bags = true, qol = true, chat = true, infopanel = true, quests = true, tooltip = true, procs = true, auctionhouse = true })
    T.truthy(#DUI.DB.LOOKS >= 24, "panels and windows both listed")
    for _, b in ipairs(DUI.DB.LOOKS) do
        local mod = DUI:GetModule(b[1])
        T.truthy(mod, b[1] .. " is a module")
        local d = DUI.DB.GetPath(mod.defaults, b[2])
        T.eq(type(d), "table", b[1] .. " " .. b[2])
        T.eq(d.global, true, b[1] .. " " .. b[2])
        for _, k in ipairs(DUI.Style.LOOK_KEYS) do T.truthy(d[k] ~= nil, b[1] .. " " .. b[2] .. "." .. k) end
    end
end)

T.test("on the global style a section keeps what's its own by design and takes the rest from General", function()
    local DUI = stub.Load({ tooltip = true, infopanel = true })
    local S = DUI.Style
    DUI:Set("general", "borderPx", 5)
    DUI:Set("general", "windowAlpha", 0.5)
    local tip = S.LookOf("Tooltip")
    T.near(tip.windowAlpha, 0.92, nil, "tooltips stay a little more solid")
    T.eq(tip.borderPx, 5)
    local bar = S.LookOf({ "InfoPanel", "databar.frameStyle" })
    T.eq(bar.borderAlpha, 0, "the data bar has no border")
    T.near(bar.windowAlpha, 0.5)
    T.eq(S.LookOf("Bags"), DUI.DB.General(), "a section with nothing of its own is General itself")

    DUI:Set("general", "borderPx", 6)
    DUI:Set("Tooltip", "frameStyle.global", false)
    T.near(DUI:Get("Tooltip", "frameStyle.windowAlpha"), 0.92, nil, "its design isn't overwritten by General's on the way off")
    T.eq(DUI:Get("Tooltip", "frameStyle.borderPx"), 6)
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
    _G.STANDARD_TEXT_FONT = "Fonts\\2002.TTF"
    _G.GetLocale = function() return "koKR" end
    local DUI = stub.Load()
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "localFont", true)
    DUI.Style.PickFont()
    T.eq(DUI.Style.FONT, "Fonts\\2002.TTF")
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

-- A /reload: the same saved settings loaded again. setup() puts the game's
-- fonts back as the client makes them on a fresh load.
local function relog(setup, opts)
    local sv = DaylightUIDB
    opts = opts or {}
    opts.before = function() setup(); DaylightUIDB = sv end
    local DUI = stub.Load(opts)
    stub.RunTimers()
    return DUI
end

-- The game's text takes the font once, at login, as EllesmereUI's "Apply to
-- All Game Text" does: the game's fonts never change under its frames while
-- they draw, so a change waits for a /reload.
T.test("game text: the font goes on the game's font objects at login, once", function()
    local names
    local function setup()
        _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        _G.NAMEPLATE_FONT = "Fonts\\FRIZQT__.TTF"
        _G.GameFontNormal = fakeFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        _G.LaterFont = fakeFont("Fonts\\ARIALN.TTF", 10, "")
        names = { "GameFontNormal", "NotAFont" }
        _G.GetFonts = function() return names end
    end
    setup()
    local DUI = stub.Load()
    local fira = DUI.Style.FONTS.fira.file
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    stub.RunTimers()
    T.eq(GameFontNormal.face, "Fonts\\FRIZQT__.TTF", "switched on mid-session: waits for a reload")
    T.eq(STANDARD_TEXT_FONT, "Fonts\\FRIZQT__.TTF")

    DUI = relog(setup)
    T.eq(GameFontNormal.face, fira, "after the reload: face swapped")
    T.eq(GameFontNormal.size, 12, "size kept")
    T.eq(GameFontNormal.flags, "OUTLINE", "outline kept")
    T.eq(STANDARD_TEXT_FONT, fira)
    T.eq(NAMEPLATE_FONT, "Fonts\\FRIZQT__.TTF", "the nameplate global stays the game's")
    T.eq(DUI.GameFonts.ClientFont(), "Fonts\\FRIZQT__.TTF", "the client's own is remembered")

    local sets = 0
    local real = GameFontNormal.SetFont
    GameFontNormal.SetFont = function(...) sets = sets + 1 return real(...) end
    names[#names + 1] = "LaterFont"   -- a game window loads its own fonts
    stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI"); stub.RunTimers()
    T.eq(LaterFont.face, "Fonts\\ARIALN.TTF", "fonts that load later keep the game's until a reload")
    DUI:Set("general", "font", "barlow")   -- a repaint of everything
    stub.RunTimers()
    T.eq(sets, 0, "never set again in the session")
    T.eq(GameFontNormal.face, fira)

    DUI:Set("general", "gameText", false)
    stub.RunTimers()
    T.eq(GameFontNormal.face, fira, "switched off: stays until the reload")
    relog(setup)
    T.eq(GameFontNormal.face, "Fonts\\FRIZQT__.TTF", "after it the game's own")
    T.eq(STANDARD_TEXT_FONT, "Fonts\\FRIZQT__.TTF")
    _G.STANDARD_TEXT_FONT, _G.NAMEPLATE_FONT, _G.DAMAGE_TEXT_FONT, _G.GetFonts = nil, nil, nil, nil
    _G.GameFontNormal, _G.LaterFont = nil, nil
end)

T.test("game text: the switch asks for a reload", function()
    local DUI = stub.Load()
    local item
    for _, g in ipairs(DUI.Options.GetPage("appearance").groups) do
        for _, it in ipairs(g.items) do if it.key == "gameText" then item = it end end
    end
    T.truthy(item, "the row is there")
    T.truthy(item.reload, "a change asks for a /reload")
end)

-- The game's nameplate and speech bubble fonts are families (one font per
-- alphabet, Blizzard_Fonts_Shared GameFonts.xml), made with "slug" rendering
-- for text drawn in the world. Each member keeps its own flags, an alphabet the
-- picked font can't draw keeps the game's face, the way EllesmereUI's game text
-- pass does it.
T.test("game text: a font family changes member by member and keeps its flags", function()
    local members, fam
    local function setup()
        _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        members = {
            roman = fakeFont("Fonts\\FRIZQT__.TTF", 9, "SLUG"),
            russian = fakeFont("Fonts\\FRIZQT___CYR.TTF", 9, "SLUG"),
            korean = fakeFont("Fonts\\2002.TTF", 9, "SLUG"),
        }
        fam = fakeFont("Fonts\\FRIZQT__.TTF", 9, "SLUG")
        function fam:GetFontObjectForAlphabet(a) return members[a] end
        _G.SystemFont_NamePlate = fam
        _G.GetFonts = function() return { "SystemFont_NamePlate" } end
    end
    setup()
    local DUI = stub.Load()
    local quick = DUI.Style.FONTS.quicksand.file
    DUI:Set("general", "font", "quicksand")
    DUI:Set("general", "gameText", true)
    relog(setup)
    T.eq(members.roman.face, quick, "Latin letters in the picked font")
    T.eq(members.roman.flags, "SLUG", "the member's own flags kept")
    T.eq(members.roman.size, 9)
    T.eq(members.russian.face, "Fonts\\FRIZQT___CYR.TTF", "no Russian letters in it: the game's face stays")
    T.eq(members.korean.face, "Fonts\\2002.TTF", "other alphabets keep theirs")
    T.eq(fam.face, quick, "the family's own font too")

    DUI = relog(setup)
    DUI:Set("general", "font", "fira")   -- has Russian letters
    relog(setup)
    T.eq(members.russian.face, DUI.Style.FONTS.fira.file, "a font with Russian letters draws them")
    T.eq(members.russian.flags, "SLUG")
    _G.STANDARD_TEXT_FONT, _G.GetFonts, _G.SystemFont_NamePlate = nil, nil, nil
end)

-- A game font family as Blizzard_Fonts_Shared builds one: a member per alphabet,
-- and the family's own font, which GetFont reads and copies take.
local function fakeFamily(faces, size, flags)
    local members = {}
    for alphabet, face in pairs(faces) do members[alphabet] = fakeFont(face, size, flags) end
    local fam = fakeFont(faces.roman, size, flags)
    function fam:GetFontObjectForAlphabet(a) return members[a] end
    return fam, members
end

local GAME_FACES = { roman = "Fonts\\FRIZQT__.TTF", russian = "Fonts\\FRIZQT___CYR.TTF", korean = "Fonts\\2002.TTF" }

-- CombatTextFont inherits SystemFont_World and CombatTextFontOutline inherits
-- SystemFont_World_ThickOutline (Blizzard_Fonts_Shared GameFontStyles.xml), so
-- the combat text over the player draws through those families' members. The
-- game text pass leaves CombatTextFont and SystemFont_World whole, as
-- EllesmereUI's does: the combat text has its own font pick.
T.test("game text: the world text family and the combat text font stay the game's", function()
    local world, worldMembers, combat
    local function setup()
        _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        _G.UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
        world, worldMembers = fakeFamily(GAME_FACES, 24, "FILTER, FIXEDHEIGHT")
        combat = fakeFont("Fonts\\FRIZQT__.TTF", 120, "FILTER, FIXEDHEIGHT")
        _G.SystemFont_World, _G.CombatTextFont = world, combat
        _G.SystemFont_Fixed = fakeFont("Fonts\\FRIZQT__.TTF", 20, "FIXEDHEIGHT")
        _G.GetFonts = function() return { "SystemFont_World", "CombatTextFont", "SystemFont_Fixed" } end
    end
    setup()
    local DUI = stub.Load()
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    DUI:Set("general", "damage.sctFont", "game")
    relog(setup)
    local fira = DUI.Style.FONTS.fira.file
    T.eq(worldMembers.roman.face, "Fonts\\FRIZQT__.TTF", "the world family's members keep the game's face")
    T.eq(worldMembers.roman.flags, "FILTER, FIXEDHEIGHT")
    T.eq(world.face, "Fonts\\FRIZQT__.TTF", "and the family's own font")
    T.eq(combat.face, "Fonts\\FRIZQT__.TTF", "the combat text follows its own pick, not the game text")
    T.eq(SystemFont_Fixed.face, fira, "other fonts take the face")
    T.eq(SystemFont_Fixed.flags, "FIXEDHEIGHT", "and keep their own flags")
    T.eq(UNIT_NAME_FONT, "Fonts\\FRIZQT__.TTF", "the names over heads keep the game's font")
    T.eq(STANDARD_TEXT_FONT, fira)
    _G.STANDARD_TEXT_FONT, _G.UNIT_NAME_FONT, _G.GetFonts = nil, nil, nil
    _G.SystemFont_World, _G.CombatTextFont, _G.SystemFont_Fixed = nil, nil, nil
end)

-- On a Russian client every Russian text draws with a family's own font, so it
-- takes a face only when that face has Russian letters.
T.test("game text: on a Russian client a family keeps its own font for a face without Russian", function()
    local real = _G.GetLocale
    _G.GetLocale = function() return "ruRU" end
    local fam, members
    local function setup()
        _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT___CYR.TTF"
        fam, members = fakeFamily({ roman = "Fonts\\FRIZQT___CYR.TTF", russian = "Fonts\\FRIZQT___CYR.TTF" }, 12, "")
        _G.GameFontNormal = fam
        _G.GetFonts = function() return { "GameFontNormal" } end
    end
    -- A shared-media font with no Russian letters (Daylight UI's own picks swap
    -- in a stand-in that has them on this client).
    local lsm = { font = { Roboto = "Interface\\Roboto.ttf" } }
    function lsm:Fetch(kind, name) return self[kind] and self[kind][name] end
    function lsm:List(kind) local out = {} for n in pairs(self[kind] or {}) do out[#out + 1] = n end return out end
    function lsm:Register() return true end
    function lsm.RegisterCallback() end
    _G.LibStub = function(name) return name == "LibSharedMedia-3.0" and lsm or nil end
    setup()
    local DUI = stub.Load()
    DUI:Set("general", "font", "lsm:Roboto")
    DUI:Set("general", "gameText", true)
    relog(setup)
    T.eq(members.roman.face, "Interface\\Roboto.ttf", "Latin letters take it")
    T.eq(members.russian.face, "Fonts\\FRIZQT___CYR.TTF", "Russian letters keep the game's")
    T.eq(fam.face, "Fonts\\FRIZQT___CYR.TTF", "the family's own font keeps Russian letters")
    _G.GetLocale, _G.LibStub = real, nil
    _G.STANDARD_TEXT_FONT, _G.GetFonts, _G.GameFontNormal = nil, nil, nil
end)

-- The hotkey text draws the range dot (U+25CF), which most bundled fonts can't
-- draw. NumberFontNormalSmallGray draws through the members it shares with
-- NumberFontNormalSmall, so it's moved onto a family of the same faces first
-- and keeps the dot, while NumberFontNormalSmall takes the face.
T.test("game text: the hotkey font keeps its faces for the range dot", function()
    _G.CreateFontFamily = function(_, list)
        local faces = {}
        for _, m in ipairs(list) do faces[m.alphabet] = m.file end
        local fam, members = fakeFamily(faces, list[1].height, list[1].flags)
        for _, m in ipairs(list) do members[m.alphabet].size, members[m.alphabet].flags = m.height, m.flags end
        return fam
    end
    local small, smallMembers, gray
    local function setup()
        _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
        small, smallMembers = fakeFamily(GAME_FACES, 12, "OUTLINE")
        gray = fakeFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        function gray:GetFontObjectForAlphabet(a) return (self.fontObject or small):GetFontObjectForAlphabet(a) end
        function gray:SetFontObject(f) self.fontObject = f end
        function gray:GetTextColor() return 0.5, 0.5, 0.5, 1 end
        function gray:SetTextColor(r, g, b) self.color = { r, g, b } end
        _G.NumberFontNormalSmall, _G.NumberFontNormalSmallGray = small, gray
        _G.GetFonts = function() return { "NumberFontNormalSmall", "NumberFontNormalSmallGray" } end
    end
    setup()
    local DUI = stub.Load()
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    relog(setup)
    local fira = DUI.Style.FONTS.fira.file
    T.eq(smallMembers.roman.face, fira, "the shared font takes the face")
    T.truthy(gray.fontObject and gray.fontObject ~= small, "the hotkey font moved onto a family of its own")
    T.eq(gray:GetFontObjectForAlphabet("roman"):GetFont(), "Fonts\\FRIZQT__.TTF", "with the game's face")
    T.eq(select(3, gray:GetFontObjectForAlphabet("roman"):GetFont()), "OUTLINE", "and its flags")
    T.deq(gray.color, { 0.5, 0.5, 0.5 }, "its color kept")
    _G.STANDARD_TEXT_FONT, _G.GetFonts, _G.CreateFontFamily = nil, nil, nil
    _G.NumberFontNormalSmall, _G.NumberFontNormalSmallGray = nil, nil
end)

-- The tooltip fonts are set from a setting, so they change in the session: on a
-- family member by member, and only what differs (a SetFont redraws every text).
T.test("game fonts: SetObjectFont sets a family member by member, once", function()
    local DUI = stub.Load()
    local fam, members = fakeFamily(GAME_FACES, 12, "OUTLINE")
    local fira = DUI.Style.FONTS.fira.file
    local sets = 0
    local real = members.roman.SetFont
    members.roman.SetFont = function(...) sets = sets + 1 return real(...) end
    DUI.GameFonts.SetObjectFont(fam, fira, 14, "")
    T.eq(members.roman.face, fira)
    T.eq(members.roman.size, 14)
    T.eq(members.russian.face, DUI.Style.HasCyrillic(fira) and fira or "Fonts\\FRIZQT___CYR.TTF")
    T.eq(members.korean.face, "Fonts\\2002.TTF", "Korean keeps the game's face")
    T.eq(members.korean.size, 14, "at the new size")
    DUI.GameFonts.SetObjectFont(fam, fira, 14, "")
    T.eq(sets, 1, "nothing set again when nothing changed")
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

T.test("a big rounding on a thick border keeps the inner curve off thin bars", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local s = DUI.Style.Shell(f, { borderPx = 8, cornerPx = 24 })
    s:SetSize(186, 42)   -- the fake game doesn't size a frame from its anchors
    DUI.Style.LayoutShell(s)
    local u = 768 / 1080
    local T8 = DUI.Pixel.Px(s, 8)
    local F = (42 - 2 * T8) / 4
    T.near(s.fillet.TOPLEFT:GetWidth(), F, 1e-6, "the inner curve is a quarter of the inside")
    T.near(s.border.TOPLEFT:GetWidth(), T8 + F, 1e-6, "the outline curves round the same center, so it stays as thick at the corner")
    -- The ring's hole is centered on the inner curve's center.
    local _, _, _, x, y = s.holes[s.border.TOPLEFT]:GetPoint(1)
    T.near(x, T8 + (42 - 2 * T8) / 4); T.near(y, -(T8 + (42 - 2 * T8) / 4))
    -- A tall frame keeps the full curve.
    s:SetSize(300, 300)
    DUI.Style.LayoutShell(s)
    T.near(s.fillet.TOPLEFT:GetWidth(), 24 * u - T8, 1e-6)
    T.near(s.border.TOPLEFT:GetWidth(), 24 * u, 1e-6, "and its full outline rounding")
end)

T.test("a combo pip's thin border stays even round its corners", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local s = DUI.Style.Shell(f, { borderPx = 2, noBevel = true })
    s:SetSize(20, 8)   -- a pip of the personal display's combo row
    DUI.Style.LayoutShell(s)
    local T2 = DUI.Pixel.Px(s, 2)
    local F = (8 - 2 * T2) / 4
    T.near(s.border.TOPLEFT:GetWidth(), T2 + F, 1e-6, "outer curve on the inner curve's center")
    local _, _, _, x = s.holes[s.border.TOPLEFT]:GetPoint(1)
    T.near(x, T2 + F)
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

T.test("a piece clipped before the first slant still leaves the shell's ends angled", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 40)
    local s = DUI.Style.Shell(f)
    local piece = f:CreateTexture()
    piece:SetAllPoints()
    DUI.Style.Clip(f, piece, "inner")
    DUI.Style.Slant(f, "both", 10)
    T.truthy(#(s.bg.__masks or {}) > 0, "the shell's background is cut")
    T.truthy(#(piece.__masks or {}) > 0, "and the piece too")
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

T.test("a border size missing from the settings falls back to its default", function()
    -- Seen in game: another addon left General's borderPx empty, and the
    -- flight timer's layout errored doing math on it.
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    DUI.Style.Shell(f)
    local half = CreateFrame("Frame", nil, UIParent)
    DUI.Style.Shell(half, { borderPx = function(g) return math.floor(g / 2) end })
    DUI.DB.General().borderPx = nil
    T.eq(DUI.Style.BorderPx(f), DUI.DB.GENERAL_DEFAULTS.borderPx, "plain shell")
    T.eq(DUI.Style.BorderPx(half), math.floor(DUI.DB.GENERAL_DEFAULTS.borderPx / 2), "a shell's own size from it")
    T.truthy(DUI.Pixel.Px(f, DUI.Style.BorderPx(f)) > 0, "the math works")
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

T.test("bar ends: each end's shape from its own two switches, and its glyph", function()
    local DUI = stub.Load()
    local S = DUI.Style
    -- Each of the four shapes, both ends angled.
    local side, under = S.EndsOf(true, false, true, false)
    T.eq(side, "both"); T.eq(under, nil, "\\--/ : both ends top out")
    side, under = S.EndsOf(true, true, true, false)
    T.eq(under, "left", "/--/ : the left end flipped alone")
    side, under = S.EndsOf(true, false, true, true)
    T.eq(under, "right", "\\--\\ : the right end flipped alone")
    side, under = S.EndsOf(true, true, true, true)
    T.eq(under, "both", "/--\\")
    -- A straight end never counts as flipped.
    side, under = S.EndsOf(false, true, true, false)
    T.eq(side, "right"); T.eq(under, nil)
    side, under = S.EndsOf(false, false, false, true)
    T.eq(side, nil); T.eq(under, nil)
    -- Glyphs are what the player sees: / on the right is the usual angle.
    T.eq(S.EndGlyph("right", true, false), "slash")
    T.eq(S.EndGlyph("right", true, true), "backslash")
    T.eq(S.EndGlyph("left", true, false), "backslash")
    T.eq(S.EndGlyph("left", true, true), "slash")
    T.eq(S.EndGlyph("left", false, true), "straight")
    for _, e in ipairs({ "left", "right" }) do
        for _, g in ipairs({ "straight", "slash", "backslash" }) do
            local on, flip = S.EndFromGlyph(e, g)
            T.eq(S.EndGlyph(e, on, flip), g, e .. " " .. g .. " round trip")
        end
    end
end)

T.test("bar ends: a hung bar's dropped end starts its line at the frame's bottom corner", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 40)
    DUI.Style.Shell(f)
    DUI.Style.Slant(f, "both", 8, nil, "right")
    local h = CreateFrame("Frame", nil, UIParent)
    h:SetSize(200, 20)
    h:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0)
    local s = DUI.Style.Shell(h)
    -- The line over the frame and the bar together is 60 tall, cut 12 (same slope as 8 over 40).
    DUI.Style.Slant(h, "both", 12, { frame = f, height = 60, drop = { right = 40 } })
    local function mask(tex, file)
        for _, m in ipairs(tex.__masks or {}) do
            -- A joined bar wears the crisp version of each image.
            local t = m.__texture or ""
            if t == DaylightUI.MEDIA .. file or t == DaylightUI.MEDIA .. file:gsub("%.png$", "-sharp.png") then return m end
        end
    end
    -- The right end, under a flipped one: its line runs from 40 down (the frame's
    -- bottom corner) over the 20 left, so its cut is 4 and it leans top out.
    local right = mask(s.bg, "mask-slant-r.png")
    T.truthy(right, "the right end is cut the usual way round: a chevron")
    local p, rel, rp, x, y = right:GetPoint(1)
    T.eq(rel, f); T.eq(p, "TOPRIGHT"); T.eq(rp, "TOPRIGHT")
    T.eq(y, -40, "starts at the frame's bottom")
    T.eq(right:GetWidth(), 16, "4x a cut of 4")
    T.eq(right:GetHeight(), 20)
    -- The left end continues the frame's line from its top, as before.
    local left = mask(s.bg, "mask-slant-l.png")
    p, rel, rp, x, y = left:GetPoint(1)
    T.eq(rel, f); T.eq(y, 0)
    T.eq(left:GetWidth(), 48); T.eq(left:GetHeight(), 60)
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

T.test("a texture clipped twice on one frame wears each end's mask once, so both ends fit", function()
    -- A party frame's inner cast bar: its background follows the power fill
    -- (Style.ClipLike) and is clipped to the frame again. Angling the second
    -- end wore the first end's mask twice plus the second's: four masks.
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 40)
    DUI.Style.Shell(f)
    local bar = CreateFrame("StatusBar", nil, f)
    local fill = bar:CreateTexture()
    local bg = bar:CreateTexture()
    DUI.Style.Clip(f, fill, "inner")
    DUI.Style.ClipLike(bg, fill)
    DUI.Style.Clip(f, bg, "inner")
    DUI.Style.Slant(f, "right", 10)
    T.eq(bg:GetNumMaskTextures(), 1, "one end, one mask")
    DUI.Style.Slant(f, "both", 10)
    T.eq(bg:GetNumMaskTextures(), 2, "each end's mask once")
    T.truthy(bg:GetMaskTexture(1) ~= bg:GetMaskTexture(2), "two different masks")
    DUI.Style.Slant(f, "left", 10)
    T.eq(bg:GetNumMaskTextures(), 1, "back to one end")
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

T.test("style: SetTextSize leaves a text alone when its size is the same, and still follows a change", function()
    local DUI = stub.Load()
    local S = DUI.Style
    local fs = S.Text(UIParent, 12)
    -- A nameplate lays out its texts again on every add; the font only changes when its look does.
    local writes = 0
    local setFont, setObj = fs.SetFont, fs.SetFontObject
    fs.SetFont = function(...) writes = writes + 1; return setFont(...) end
    fs.SetFontObject = function(...) writes = writes + 1; return setObj(...) end
    S.SetTextSize(fs, 12)
    S.SetTextSize(fs, 12)
    T.eq(writes, 0, "same size: no font written")
    S.SetTextSize(fs, 15)
    T.truthy(writes > 0, "a new size is written")
    T.eq(fs.__font[2], 15)
    DUI:Set("general", "fontScale", 2)
    stub.RunTimers()
    T.eq(fs.__font[2], 30, "Text size still follows")
    writes = 0
    S.SetTextSize(fs, 15)
    T.eq(writes, 0, "after a repaint, same size: nothing")
    DUI:Set("general", "textOutline", "THICKOUTLINE")
    S.SetTextSize(fs, 15)
    T.eq(fs.__font[3], "THICKOUTLINE", "a changed outline is put on even before the repaint runs")
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

T.test("the custom gradient accent runs through every color picked", function()
    local DUI = stub.Load()
    local S = DUI.Style
    DUI:Set("general", "accent", "customGradient")
    DUI:Set("general", "accentGradient.count", 3)
    DUI:Set("general", "accentGradient.c1", { 1, 0, 0 })
    DUI:Set("general", "accentGradient.c2", { 0, 1, 0 })
    DUI:Set("general", "accentGradient.c3", { 0, 0, 1 })
    stub.RunTimers()
    T.truthy(S.ACCENTS.customGradient, "a choice in the list")
    T.eq(S.AccentSweep(), "custom")
    local a, b = S.AccentPair()
    T.rgb(a, { 1, 0, 0 }, "a shape starts at the first color")
    T.rgb(b, { 0, 0, 1 }, "and ends at the last one")
    T.rgb({ S.AccentAt(0.5) }, { 0, 1, 0 }, "a list's middle row takes the middle color")
    T.rgb({ S.Accent() }, { 0, 1, 0 }, "text takes the middle")
    T.rgb({ S.SplashAt(1) }, { 0, 0, 1 }, "the level-up light follows it")
    local text, coloured = S.AccentText("abc")
    T.truthy(coloured); T.truthy(text:find("|cff00ff00b", 1, true), "the middle letter in the middle color")
    DUI:Set("general", "accentGradient.count", 2)
    stub.RunTimers()
    local _, hi = S.AccentPair()
    T.rgb(hi, { 0, 1, 0 }, "fewer colors end sooner")
    DUI:Set("general", "gradients.off", true)
    stub.RunTimers()
    T.isnil(S.AccentSweep(), "gradients off: one color")
    T.eq(type(S.Accent()), "number")
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
    T.eq(DUI.Widgets.BUTTON.text, INK.TEXT, "a button's words")
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

-- The client's font families (CreateFontFamily, Blizzard_Fonts_Shared's
-- FontFamily): one font object per alphabet, read with GetFontObjectForAlphabet;
-- the family's own GetFont is its first member's.
local function fontFamilies()
    local made = {}
    _G.CreateFontFamily = function(name, members)
        local fam = CreateFont(name)
        local byAlphabet = {}
        for _, m in ipairs(members) do
            local obj = CreateFont(nil)
            obj:SetFont(m.file, m.height, m.flags)
            byAlphabet[m.alphabet] = obj
        end
        fam:SetFont(members[1].file, members[1].height, members[1].flags)
        rawset(fam, "GetFontObjectForAlphabet", function(_, a) return byAlphabet[a] end)
        made[#made + 1] = fam
        return fam
    end
    return made
end

-- A text as the client keeps it: a plain SetFont fixes its face for good, and a
-- font object set on it after that no longer changes it.
local function clientText()
    local fs = UIParent:CreateFontString()
    rawset(fs, "SetFont", function(self, file, size, flags) self.__font = { file, size, flags } end)
    rawset(fs, "SetFontObject", function(self, obj) self.__fontObject = obj end)
    rawset(fs, "GetFontObject", function(self) return self.__fontObject end)
    rawset(fs, "GetFont", function(self)
        if self.__font then return self.__font[1], self.__font[2], self.__font[3] end
        local obj = self.__fontObject
        if obj then return obj:GetFont() end
    end)
    return fs
end

T.test("fonts: a name in Russian, Korean or Chinese draws with the game's font for those letters", function()
    local DUI = stub.Load()
    fontFamilies()
    local Style = DUI.Style
    local quick = Style.FONTS.quicksand.file
    local fam = Style.FontFamily(quick, 12, "OUTLINE", 0.5)
    T.eq(fam:GetFontObjectForAlphabet("roman"):GetFont(), quick, "Latin letters in the picked font")
    T.eq(fam:GetFontObjectForAlphabet("russian"):GetFont(), "Fonts\\FRIZQT___CYR.TTF", "no Russian letters in it")
    T.eq(fam:GetFontObjectForAlphabet("korean"):GetFont(), "Fonts\\2002.ttf")
    local express = Style.FONTS.expressway.file
    T.eq(Style.FontFamily(express, 12, "OUTLINE", 0.5):GetFontObjectForAlphabet("russian"):GetFont(), express,
        "a font with Russian letters draws them itself")
    T.eq(Style.FontFamily(quick, 12.05, "OUTLINE", 0.5), fam, "one family per font and size, not one per text")
    _G.CreateFontFamily = nil
end)

T.test("fonts: text styled by Daylight UI wears the family and keeps its color and side", function()
    local DUI = stub.Load()
    fontFamilies()
    local fs = clientText()
    fs:SetJustifyH("RIGHT")
    fs:SetTextColor(0.2, 0.4, 0.6, 1)
    DUI.Style.DressText(fs, 13)
    local fam = fs:GetFontObject()
    T.truthy(fam and fam.GetFontObjectForAlphabet, "a family, so other alphabets draw")
    T.eq(fs:GetFont(), DUI.Style.FONT)
    T.eq(fs:GetJustifyH(), "RIGHT")
    T.eq(select(3, fs:GetTextColor()), 0.6)
    local copy = clientText()
    DUI.Style.CopyFace(copy, fs)
    T.eq(copy:GetFontObject(), fam, "a nameplate's class-colored name copies the family, not just the file")
    _G.CreateFontFamily = nil
end)

T.test("fonts: a text that already got a plain font elsewhere still gets the picked font and size", function()
    local DUI = stub.Load()
    fontFamilies()
    local fs = clientText()
    fs:SetFont("Fonts\\ARIALN.TTF", 9, "")
    DUI.Style.SetFace(fs, DUI.Style.FONT, 14, "OUTLINE", 0.5)
    local file, size = fs:GetFont()
    T.eq(file, DUI.Style.FONT)
    T.eq(size, 14)
    _G.CreateFontFamily = nil
end)

-- A family is a named font object, so the game lists it with its own (GetFonts).
-- "Use this font for the game's text" walked it on every addon that loaded (at
-- login, opening the auction house) and put the Appearance font on it: the chat's
-- own font, picked for its Russian letters, was gone again.
T.test("game text: Daylight UI's own font families keep their font", function()
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.GameFontNormal = fakeFont("Fonts\\FRIZQT__.TTF", 12, "")
    local names = { "GameFontNormal" }
    _G.GetFonts = function() return names end
    local DUI = stub.Load()
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    local sv = DaylightUIDB
    DUI = stub.Load({ login = false, before = function() DaylightUIDB = sv end })
    fontFamilies()
    local Style = DUI.Style
    local comfortaa = Style.FONTS.comfortaa.file
    local fam = Style.FontFamily(comfortaa, 12, "", 0.9)
    names[#names + 1] = fam:GetName()
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    T.eq(GameFontNormal.face, Style.FONTS.fira.file, "the game's text takes the font")
    T.eq(fam:GetFont(), comfortaa, "the chat's family keeps its own")
    _G.STANDARD_TEXT_FONT, _G.DAMAGE_TEXT_FONT, _G.GetFonts, _G.GameFontNormal = nil, nil, nil, nil
    _G.CreateFontFamily = nil
end)

local function withLocale(locale, fn)
    local before = _G.GetLocale
    _G.GetLocale = function() return locale end
    local ok, err = pcall(fn)
    _G.GetLocale = before
    _G.CreateFontFamily = nil
    if not ok then error(err, 0) end
end

T.test("fonts: on a Russian client a font with no Russian letters hands over to one that has them", function()
    withLocale("ruRU", function()
        local DUI = stub.Load()
        local Style = DUI.Style
        DUI:Set("general", "font", "barlow")
        Style.PickFont()
        T.eq(Style.FONT, Style.FONTS.expressway.file, "Barlow has no Russian letters, Expressway does")
        T.eq(Style.Text(UIParent, 13):GetFont(), Style.FONTS.expressway.file, "every text follows")
        DUI:Set("general", "font", "fira")
        Style.PickFont()
        T.eq(Style.FONT, Style.FONTS.fira.file, "a font that has them stays")
        DUI:Set("general", "font", "cinzel")
        Style.PickFont()
        T.eq(Style.FONT, DUI.GameFonts.ClientFont(), "an Azeroth font hands over to the game's own")
        DUI:Set("general", "damage.font", "lato")
        T.eq(DUI.GameFonts.DamageWanted(), Style.FONTS.fira.file, "a page's own pick too")
        local values = DUI.Options.DamageFontChoices()
        T.truthy(string.find(values.barlow, "Expressway", 1, true), "the picker says which font it shows as")
        T.eq(values.fira, "Fira Sans")
    end)
    local DUI = stub.Load()
    DUI:Set("general", "font", "barlow")
    DUI.Style.PickFont()
    T.eq(DUI.Style.FONT, DUI.Style.FONTS.barlow.file, "other clients keep it")
    T.eq(DUI.Options.DamageFontChoices().barlow, "Barlow Condensed")
end)

T.test("fonts: every font says whether it has Russian letters, and which one stands in when not", function()
    local Style = stub.Load().Style
    for key, f in pairs(Style.FONTS) do
        if f.cyrillic ~= true then
            local by = Style.FONTS[f.cyrillic]
            T.truthy(by and by.cyrillic == true, key .. " names a stand-in that has them")
        end
    end
    T.truthy(Style.CYRILLIC["expresswayfree.ttf"])
    T.truthy(Style.CYRILLIC["arialn.ttf"])
    T.falsy(Style.CYRILLIC["lato-regular.ttf"])
end)

T.test("fonts: on a Korean client with Daylight UI's own font picked, Korean letters still draw", function()
    withLocale("koKR", function()
        local DUI = stub.Load()
        fontFamilies()
        local express = DUI.Style.FONTS.expressway.file
        T.eq(DUI.Style.FontFamily(express, 12, "", 0):GetFontObjectForAlphabet("korean"):GetFont(), DUI.Style.ALPHABET_FONTS.korean,
            "Expressway has no Korean letters")
        local client = DUI.GameFonts.ClientFont()
        T.eq(DUI.Style.FontFamily(client, 12, "", 0):GetFontObjectForAlphabet("korean"):GetFont(), client,
            "the game's own font draws them itself")
    end)
end)

T.test("style: capitals raise accented and Russian letters too", function()
    local DUI = stub.Load()
    local Up = DUI.Style.Upper
    T.eq(Up("Unterstützer"), "UNTERSTÜTZER")
    T.eq(Up("Cette session à"), "CETTE SESSION À")
    T.eq(Up("Esta sesión"), "ESTA SESIÓN")
    T.eq(Up("Этот сеанс ёж"), "ЭТОТ СЕАНС ЁЖ")
    T.eq(Up("利润 이익"), "利润 이익", "letters with no capitals stay as they are")
    T.eq(Up(nil), nil)
end)
