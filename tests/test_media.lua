local stub = require("stub")

-- A stand-in for the shared media library: a few textures and fonts.
local function fakeLSM()
    local lsm = { media = { statusbar = { Smooth = "Interface\\Smooth.tga", Flat = "Interface\\Flat.tga" },
                            font = { Roboto = "Interface\\Roboto.ttf" } } }
    function lsm:Fetch(kind, name) return self.media[kind] and self.media[kind][name] end
    function lsm:List(kind)
        local out = {}
        for name in pairs(self.media[kind] or {}) do out[#out + 1] = name end
        table.sort(out)
        return out
    end
    function lsm:Register(kind, name, file)
        self.media[kind] = self.media[kind] or {}
        if self.media[kind][name] then return false end
        self.media[kind][name] = file
        return true
    end
    function lsm.RegisterCallback(_, _, _, fn) lsm.callback = fn end
    _G.LibStub = function(name) return name == "LibSharedMedia-3.0" and lsm or nil end
    return lsm
end

T.test("media: one bar texture for every bar, ours by default, a shared one when picked", function()
    local lsm = fakeLSM()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local Style = DUI.Style
    T.eq(lsm.media.statusbar.DaylightUI, Style.BAR.fill, "ours in the shared list for other addons")
    local bar = Style.Bar(UIParent)
    local seam = Style.Bar(UIParent, "seamless")
    T.eq(bar:GetStatusBarTexture().__texture or bar.__barTexture, Style.BAR.fill)
    DUI:Set("general", "barTexture", "lsm:Smooth")
    stub.RunTimers()
    T.eq(Style.BarFile(), "Interface\\Smooth.tga")
    local function file(b) local t = b:GetStatusBarTexture(); return (t and t.__texture) or b.__barTexture end
    T.eq(file(bar), "Interface\\Smooth.tga", "an existing bar follows")
    T.eq(file(seam), "Interface\\Smooth.tga", "a heal prediction bar too")
    T.eq(file(Style.Bar(UIParent)), "Interface\\Smooth.tga", "and a new one starts in it")
    DUI:Set("general", "barTexture", "daylight")
    stub.RunTimers()
    T.eq(file(seam), Style.BAR.seamless, "back to ours: prediction keeps its seamless fill")
    _G.LibStub = nil
end)

T.test("media: the Daylight gradient keeps a picked bar texture, multiplied over the sweep", function()
    fakeLSM()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local Style = DUI.Style
    local holder = CreateFrame("Frame", nil, UIParent)
    local bar = Style.Bar(holder)
    local fill = bar:GetStatusBarTexture()
    Style.Clip(holder, fill, "inner")
    Style.Slant(holder, "right", 6)
    Style.AngleFill(bar, "right", 6)
    local function grain()
        for _, r in ipairs({ bar:GetRegions() }) do
            if r ~= fill and r.__blend == "MOD" then return r end
        end
    end
    Style.SetBarGradient(bar, true)
    T.eq(fill.__texture, Style.GRADIENT_FILE, "the sweep's image")
    T.isnil(grain(), "our own texture: the image alone")
    DUI:Set("general", "barTexture", "lsm:Smooth")
    stub.RunTimers()
    T.eq(fill.__texture, Style.GRADIENT_FILE, "still the sweep")
    local g = grain()
    T.truthy(g, "the picked texture laid over it")
    T.eq(g.__texture, "Interface\\Smooth.tga")
    T.truthy(g:IsShown())
    T.eq(#(g.__masks or {}), #(fill.__masks or {}), "the fill's angled edge and clip")
    DUI:Set("general", "barTexture", "lsm:Flat")
    stub.RunTimers()
    T.eq(g.__texture, "Interface\\Flat.tga", "follows a new pick")
    Style.SetBarGradient(bar, false)
    T.eq(fill.__texture, "Interface\\Flat.tga", "gradient off: the picked texture as the fill")
    T.falsy(g:IsShown(), "and nothing over it")
    Style.SetBarGradient(bar, true)
    T.truthy(g:IsShown())
    DUI:Set("general", "barTexture", "daylight")
    stub.RunTimers()
    T.falsy(g:IsShown(), "back to ours: the image alone")
    _G.LibStub = nil
end)

T.test("media: our six extra bar fills, listed after ours and worn like a shared pick", function()
    local lsm = fakeLSM()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local Style, Media, O = DUI.Style, DUI.Media, DUI.Options
    T.eq(#Media.BARS, 6)
    T.eq(lsm.media.statusbar["DaylightUI Silk"], DUI.MEDIA .. "bar-silk.tga", "in the shared list for other addons")
    local values, order = O.BarRow("windowBar", "Window bar", "the bars").choices()
    T.eq(order[2], "daylight", "after General's")
    T.eq(order[3], "silk", "ours next, in order")
    T.eq(values.grain, "Grain")
    T.isnil(values["lsm:DaylightUI Silk"], "not twice under its shared name")
    T.eq(values["lsm:Smooth"], "Smooth", "the shared ones after")
    local holder = CreateFrame("Frame", nil, UIParent)
    local bar = Style.Bar(holder)
    local fill = bar:GetStatusBarTexture()
    DUI:Set("general", "barTexture", "glass")
    stub.RunTimers()
    T.eq(fill.__texture, DUI.MEDIA .. "bar-glass.tga", "the fill wears it")
    Style.SetBarGradient(bar, true)
    local grain
    for _, r in ipairs({ bar:GetRegions() }) do
        if r ~= fill and r.__blend == "MOD" then grain = r end
    end
    T.eq(grain and grain.__texture, DUI.MEDIA .. "bar-glass.tga", "over the Daylight gradient too")
    T.eq(O.BarRow("windowBar", "Window bar", "the bars").shownAs("general"), "Glass", "by its own name")
    _G.LibStub = nil
    local plain = stub.Load()
    plain:Set("general", "barTexture", "tube")
    stub.RunTimers()
    T.eq(plain.Style.BarFile(), plain.MEDIA .. "bar-tube.tga", "no shared library needed")
end)

T.test("media: a shared pick that isn't there (yet) falls back to ours", function()
    _G.LibStub = nil
    local DUI = stub.Load()
    DUI:Set("general", "barTexture", "lsm:Gone")
    DUI:Set("general", "font", "lsm:Gone")
    stub.RunTimers()
    T.eq(DUI.Style.BarFile(), DUI.Style.BAR.fill)
    T.eq(DUI.Style.FONT, DUI.Style.FONTS.expressway.file)
end)

T.test("media: a long list refills only the rows that scroll in, so a font list never loads a screenful per notch", function()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local W = DUI.Widgets
    local owner = CreateFrame("Button", nil, UIParent)
    local values, keys = {}, {}
    for i = 1, 60 do keys[i] = "k" .. i; values[keys[i]] = "Font " .. i end
    local asked = 0
    W.OpenMenu(owner, keys, values, nil, function() end, nil,
        { preview = "font", fetch = function() asked = asked + 1; return "x.ttf" end })
    asked = 0
    W.ScrollMenu(1)
    T.eq(W.MenuRow(1).text:GetText(), "Font 2")
    T.eq(W.MenuRow(W.MENU_MAX_ROWS).text:GetText(), "Font 13")
    T.truthy(asked <= 1, "one row came in, " .. asked .. " rows were drawn again")
    W.ScrollMenu(-1)
    T.eq(W.MenuRow(1).text:GetText(), "Font 1", "back up")
    W.CloseMenu()
end)

T.test("media: every font list is alphabetical, ours and shared together", function()
    local lsm = fakeLSM()
    lsm.media.font["Zeta Shared"] = "Interface\z.ttf"
    lsm.media.font["bravo Shared"] = "Interface\b.ttf"
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local values, order = DUI.Options.DamageFontChoices()
    T.eq(order[1], "auto", "Automatic stays on top")
    for i = 3, #order do
        local a, b = values[order[i - 1]]:lower(), values[order[i]]:lower()
        T.truthy(a <= b, a .. " before " .. b)
    end
    _G.LibStub = nil
end)

T.test("media: shared fonts work as the font", function()
    fakeLSM()
    local DUI = stub.Load()
    DUI:Set("general", "font", "lsm:Roboto")
    stub.RunTimers()
    T.eq(DUI.Style.FONT, "Interface\\Roboto.ttf")
    _G.LibStub = nil
end)

T.test("media: a bar background for every bar, and an area's own picks over General's", function()
    fakeLSM()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local Style, Media = DUI.Style, DUI.Media
    Media.RegisterBar("test.health", "general", "windowBar", "windowBack")   -- any general keys will do for a slot
    local plain = Style.Bar(UIParent)
    local own = Style.Bar(UIParent, nil, "test.health")
    Style.SetBarSlot(own, "test.health")
    local function file(b) local t = b:GetStatusBarTexture(); return (t and t.__texture) or b.__barTexture end
    T.eq(Style.BarBack(plain).__texture, Style.BAR.back, "ours behind by default")
    DUI:Set("general", "barBack", "lsm:Flat")
    stub.RunTimers()
    T.eq(Style.BarBack(plain).__texture, "Interface\\Flat.tga", "a picked background on every bar")
    DUI:Set("general", "windowBar", "lsm:Smooth")
    stub.RunTimers()
    T.eq(file(own), "Interface\\Smooth.tga", "the area's own pick")
    T.eq(file(plain), Style.BAR.fill, "the rest keep General's")
    DUI:Set("general", "barTexture", "lsm:Flat")
    stub.RunTimers()
    T.eq(file(own), "Interface\\Smooth.tga", "an own pick stays over a General change")
    DUI:Set("general", "windowBack", "lsm:Smooth")
    stub.RunTimers()
    T.eq(Style.BarBack(own).__texture, "Interface\\Smooth.tga", "its own background")
    T.eq(Style.BarBack(plain).__texture, "Interface\\Flat.tga", "the rest keep General's background")
    T.truthy(Media.AnyOwn("bar"))
    Media.ApplyToAll("bar")
    stub.RunTimers()
    T.eq(DUI:Get("general", "windowBar"), Media.GENERAL, "Apply to all: back to General")
    T.eq(file(own), "Interface\\Flat.tga", "and it shows General's")
    T.falsy(Media.AnyOwn("bar"))
    Media.SLOTS["test.health"], Media.SLOTS["test.health.back"] = nil, nil
    _G.LibStub = nil
end)

T.test("media: window bars keep their round ends with a picked texture inside", function()
    fakeLSM()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local W = DUI.Widgets
    local bar = W.Bar(UIParent, 12)
    T.isnil(bar.grain, "ours: the plain pill, nothing over it")
    T.truthy(bar.track:IsShown())
    DUI:Set("general", "windowBar", "lsm:Smooth")
    DUI:Set("general", "windowBack", "lsm:Flat")
    stub.RunTimers()
    T.eq(bar.grain.__texture, "Interface\\Smooth.tga", "the fill wears the pick")
    T.eq(bar.grain.__blend, "MOD", "multiplied in: the fill keeps its colors")
    T.eq(#bar.grain.__masks, 2, "both round ends")
    T.eq(bar.trackGrain.__texture, "Interface\\Flat.tga", "the background pick in the track")
    T.falsy(bar.track:IsShown())
    T.eq(bar:GetHeight(), 12, "the same size")
    DUI:Set("general", "windowBar", "daylight")
    stub.RunTimers()
    T.falsy(bar.grain:IsShown(), "ours again: the plain pill")
    _G.LibStub = nil
end)

T.test("media: text in our windows follows the window font", function()
    fakeLSM()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local Style, W = DUI.Style, DUI.Widgets
    local win = DUI.Win.New({ w = 300, h = 200 })
    local inWin = Style.Text(win.host, 13)
    local button = W.Font(win.host, W.BODY, 13)
    local outside = Style.Text(UIParent, 13)
    T.eq(inWin:GetFont(), Style.FONT, "General's font while it follows General")
    T.eq(button:GetFont(), W.BODY)
    DUI:Set("general", "windowFont", "lsm:Roboto")
    stub.RunTimers()
    T.eq(inWin:GetFont(), "Interface\\Roboto.ttf", "the window's own font")
    T.eq(button:GetFont(), "Interface\\Roboto.ttf", "its buttons too")
    T.eq(outside:GetFont(), Style.FONT, "nothing outside the window")
    DUI.Media.ApplyToAll("font")
    stub.RunTimers()
    T.eq(inWin:GetFont(), Style.FONT, "Apply to all: General's again")
    _G.LibStub = nil
end)

T.test("media: each unit frame picks its own bar textures and fonts", function()
    fakeLSM()
    local DUI, ns = stub.Load({ module = true })
    stub.FireEvent("PLAYER_LOGIN")
    local Style = DUI.Style
    local f, t = ns.frames.player, ns.frames.target
    local function file(b) local x = b:GetStatusBarTexture(); return (x and x.__texture) or b.__barTexture end
    DUI:Set("UnitFrames", "player.media.health", "lsm:Smooth")
    DUI:Set("UnitFrames", "player.media.powerBack", "lsm:Flat")
    stub.RunTimers()
    T.eq(file(f.health), "Interface\\Smooth.tga", "the player's health wears its own pick")
    T.eq(file(t.health), Style.BAR.fill, "the target's keeps General's")
    T.eq(file(f.power), Style.BAR.fill, "power keeps General's")
    T.eq(Style.BarBack(f.power).__texture, "Interface\\Flat.tga", "power's own background")
    DUI:Set("UnitFrames", "target.media.nameFont", "bangers")
    stub.RunTimers()
    T.eq(t.nameText:GetFont(), Style.FONTS.bangers.file, "the target's name font")
    T.eq(f.nameText:GetFont(), Style.FONT, "the player's name stays General's")
    DUI:Set("UnitFrames", "playerCastbar.media.bar", "lsm:Flat")
    stub.RunTimers()
    T.eq(DUI.Style.BarFile("fill", "uf.cast.player"), "Interface\\Flat.tga", "the player cast bar's own")
    DUI.Media.ApplyToAll("font")
    DUI.Media.ApplyToAll("bar")
    DUI.Media.ApplyToAll("back")
    stub.RunTimers()
    T.eq(t.nameText:GetFont(), Style.FONT, "the reset: General's font")
    T.eq(file(f.health), Style.BAR.fill, "and General's texture")
    T.eq(DUI:Get("UnitFrames", "target.media.nameFont"), "general")
    _G.LibStub = nil
end)

T.test("media: every area registers its picks, and one reset clears them all", function()
    fakeLSM()
    local DUI = stub.Load({ nameplates = true, infopanel = true, chat = true })
    stub.FireEvent("PLAYER_LOGIN")
    local S = DUI.Media.SLOTS
    for _, id in ipairs({ "plates.health", "plates.health.back", "plates.font", "plates.font.name",
                          "panel.xp", "panel.meter", "panel.font.meter",
                          "chat.font" }) do
        T.truthy(S[id], id)
    end
    T.isnil(S["plates.font.name"].parent, "each text's font on its own")
    DUI:Set("Nameplates", "media.nameFont", "lsm:Roboto")
    DUI:Set("Nameplates", "media.health", "lsm:Smooth")
    DUI:Set("InfoPanel", "media.xp", "lsm:Flat")
    stub.RunTimers()
    T.eq(DUI.Style.FontFile("plates.font.name"), "Interface\\Roboto.ttf", "names take their own font")
    T.eq(DUI.Style.BarFile("fill", "plates.health"), "Interface\\Smooth.tga")
    T.eq(DUI.Style.BarFile("fill", "panel.xp"), "Interface\\Flat.tga")
    DUI.Media.ApplyToAll("bar")
    DUI.Media.ApplyToAll("font")
    stub.RunTimers()
    T.eq(DUI:Get("Nameplates", "media.health"), "general")
    T.eq(DUI:Get("InfoPanel", "media.xp"), "general")
    T.eq(DUI:Get("Nameplates", "media.nameFont"), "general")
    T.eq(DUI.Style.FontFile("plates.font.name"), DUI.Style.FONT)
    _G.LibStub = nil
end)

T.test("media: a pick on General shows what General is set to, not the word", function()
    fakeLSM()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local O = DUI.Options
    local font, bar = O.FontRow("windowFont", "Window font", "Text"), O.BarRow("windowBar", "Window bar", "the bars")
    T.eq(font.shownAs("general"), "Expressway", "the font's own name")
    T.eq(bar.shownAs("general"), "DaylightUI", "ours by name")
    T.isnil(font.shownAs("bangers"), "an own pick shows as itself")
    local values = font.choices()
    T.eq(values.general, "Expressway (General)", "in the list, marked as General's")
    DUI:Set("general", "barTexture", "lsm:Smooth")
    DUI:Set("general", "font", "fira")
    T.eq(bar.shownAs("general"), "Smooth", "follows a General change")
    T.eq(font.shownAs("general"), "Fira Sans")
    _G.LibStub = nil
end)

T.test("media: the dropdown lists ours first, then the shared ones, and scrolls when long", function()
    local lsm = fakeLSM()
    for i = 1, 30 do lsm.media.statusbar["Tex" .. string.format("%02d", i)] = "Interface\\t" .. i end
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local W = DUI.Widgets
    local owner = CreateFrame("Button", nil, UIParent)
    local values, keys = {}, {}
    for i = 1, 30 do keys[i] = "k" .. i; values[keys[i]] = "Choice " .. i end
    W.OpenMenu(owner, keys, values, "k1", function() end, nil, { preview = "bar", fetch = function() return "x.tga" end })
    T.eq(W.MenuRow(1).text.__text or W.MenuRow(1).text:GetText(), "Choice 1")
    T.falsy(W.MenuRow(W.MENU_MAX_ROWS + 1) and W.MenuRow(W.MENU_MAX_ROWS + 1):IsShown(), "only a screenful of rows")
    T.truthy(W.MenuRow(1).swatch:IsShown(), "a texture shows itself")
    W.ScrollMenu(5)
    T.eq(W.MenuRow(1).text:GetText(), "Choice 6", "the wheel scrolls")
    W.ScrollMenu(100)
    T.eq(W.MenuRow(W.MENU_MAX_ROWS).text:GetText(), "Choice 30", "down to the last, no further")
    W.CloseMenu()
    _G.LibStub = nil
end)

T.test("scroll bar: shows at rest whenever a list has more than fits, lit while it scrolls, away when it all fits", function()
    local DUI = stub.Load()
    stub.FireEvent("PLAYER_LOGIN")
    local W = DUI.Widgets
    local sf = CreateFrame("ScrollFrame", nil, UIParent)
    local most = 200
    local bar = W.Scroll(sf, { read = function() return 0, most, 100 end, write = function() end })
    bar:SetHeight(100)
    local tick = bar:GetScript("OnUpdate")
    tick(bar, 1)
    T.eq(bar:GetAlpha(), W.SCROLL.rest, "more below: the pill shows, so the list reads as one that scrolls")
    bar.Wake()
    T.eq(bar:GetAlpha(), 1, "scrolling: lit")
    most = 0
    tick(bar, 1)
    T.eq(bar:GetAlpha(), 0, "it all fits: no pill")
end)
