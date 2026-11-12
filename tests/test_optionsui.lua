-- The options window: its look, the rail and page list, the cards' columns
-- and chips, and search results. test_options.lua covers the registry.
local stub = require("stub")

local ALL = { module = true, actionbars = true, buffs = true, bags = true, nameplates = true, tooltip = true,
              qol = true, chat = true, infopanel = true, skins = true, quests = true }

local function rowFor(pf, key)
    for _, card in ipairs(pf.cards) do
        for _, row in ipairs(card.rows) do
            if row.item.key == key then return row end
        end
    end
end

local function withLocale(locale, fn)
    local before = _G.GetLocale
    _G.GetLocale = function() return locale end
    local ok, err = pcall(fn)
    _G.GetLocale = before
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------
-- Look
-- ---------------------------------------------------------------------

T.test("every section has a color, an icon and a short name; an unknown one gets a fallback", function()
    local DUI = stub.Load(ALL)
    local Theme = DUI.OptionsTheme
    for _, s in ipairs(DUI.Options.Sections()) do
        T.truthy(Theme.SECTIONS[s.id], "a look for " .. s.id)
        local look = Theme.Section(s.id)
        T.eq(#look.color, 3, s.id .. " color")
        T.truthy(type(look.icon) == "string" and look.icon ~= "", s.id .. " icon")
        T.truthy(#look.short <= 9, s.id .. " short name fits the rail")
    end
    DUI.Options.RegisterSection("BuffLedger", "Buff Ledger", 135)
    local look = Theme.Section("BuffLedger")
    T.eq(look.icon, Theme.FALLBACK_ICON)
    T.eq(look.short, "Buff Ledger")
    T.eq(#look.color, 3)
    T.rgb(Theme.GradientAt(0), Theme.SWEEP[1], "the sweep starts blue")
    T.rgb(Theme.GradientAt(1), Theme.SWEEP[#Theme.SWEEP], "and ends orange")
end)

T.test("the body font follows the Appearance font on Latin-alphabet clients, Arial Narrow on the others", function()
    for _, locale in ipairs({ "enUS", "deDE" }) do
        withLocale(locale, function()
            local DUI = stub.Load()
            DUI:Set("general", "font", "fira")
            DUI.Style.PickFont()
            T.eq(DUI.Widgets.BODY, DUI.Style.FONTS.fira.file, locale .. " follows the chosen font")
            T.eq(DUI.Widgets.TITLE, DUI.Style.FONTS.fira.file)
            DUI:Set("general", "font", "poppins")
            DUI.Style.PickFont()
            T.eq(DUI.Widgets.BODY, DUI.Style.FONTS.poppins.file, locale .. " follows a change")
        end)
    end
    withLocale("ruRU", function()
        local DUI = stub.Load()
        DUI:Set("general", "font", "fira")
        DUI.Style.PickFont()
        T.eq(DUI.Widgets.BODY, "Fonts\\ARIALN.TTF", "a font that may lack Cyrillic is not used for the body")
    end)
    -- Korean and Chinese clients use the game's own font (their "Use my
    -- language's font" is on from the start).
    withLocale("koKR", function()
        _G.STANDARD_TEXT_FONT = "Fonts\\2002.TTF"
        local DUI = stub.Load()
        DUI:Set("general", "localFont", true)
        DUI.Style.PickFont()
        T.eq(DUI.Widgets.BODY, "Fonts\\2002.TTF")
        _G.STANDARD_TEXT_FONT = nil
    end)
end)

T.test("a font chosen in Appearance reaches the open options window at once", function()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("UnitFrames.player")
    local pf = DUI.OptionsPanel.PageFrame()
    local row = rowFor(pf, "player.width")
    local slider = row.control.box
    DUI:Set("general", "font", "fira")
    stub.RunTimers()
    local fira = DUI.Style.FONTS.fira.file
    T.eq(row.label.__font[1], fira, "a row's label")
    T.eq(pf.cards[1].title.__font[1], fira, "a card's title")
    T.eq(slider.__font[1], fira, "a slider's number box")
    T.eq(row.label.__font[2], 13, "the size is kept")
end)

T.test("a switch that's on fills with the player's accent (as every control); off, the plain track", function()
    local DUI = stub.Load({ module = true })
    DUI.Style.Accent = function() return 1, 0.96, 0.41 end      -- a rogue's yellow accent
    DUI.Style.AccentPair = function() return { 1, 0.9, 0.3 }, { 1, 0.96, 0.41 } end
    DUI.OptionsPanel.Show("UnitFrames.player")
    local row = rowFor(DUI.OptionsPanel.PageFrame(), "player.enabled")
    local track = row.control.track
    track.__gradient = nil
    row.control.Refresh()
    T.truthy(row.control.on, "the player frame is on")
    T.truthy(track.__gradient, "on: the gradient")
    local a = track.__gradient[2]
    T.near(a.r, 1, 1e-6, "the accent's own pair")
    DUI.Options.Set(row.page, row.item, false)
    row.control.Refresh()
    T.rgb(track.__vertex, DUI.Widgets.COLORS.track, "off: the plain track")
end)

T.test("a switch at rest slides nothing on a refresh; only a flip slides the knob (Motion), then stops", function()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("UnitFrames.player")
    local row = rowFor(DUI.OptionsPanel.PageFrame(), "player.enabled")
    local b = row.control
    local function run() for _ = 1, 60 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.05) end end
    if DUI.Motion.Driver() then run() end
    local at = b.pos
    b.Refresh()
    T.eq(b.pos, at, "unchanged: nothing to slide")
    T.isnil(b:GetScript("OnUpdate"), "no OnUpdate of its own")
    DUI.Options.Set(row.page, row.item, false)
    b.Refresh()
    local from = b.pos
    b.Refresh()
    T.eq(b.goal ~= from, true, "flipped: the knob has somewhere to go")
    run()
    T.eq(b.pos, b.goal, "and gets there")
    T.truthy(b.pos ~= at, "the other end")
end)

T.test("a button is a small shell: the mouse traces the band in the accent, a press pushes in, off takes no clicks", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    DUI.Style.Accent = function() return 1, 0.96, 0.41 end
    DUI.Style.AccentPair = function() return nil end
    local b = W.Button(UIParent, "Go", 24)
    b:SetWidth(100)
    local function settle() for _ = 1, 40 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.02) end end
    T.rgb(b.band.__vertex, W.BUTTON.band, "warm band at rest")
    T.falsy(b.trace.top:IsShown(), "no trace at rest")
    b:GetScript("OnEnter")(b)
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.03)
    T.truthy(b.trace.top:IsShown() and b.trace.left:IsShown(), "two lights leave the top-left corner")
    T.truthy(b.trace.gleams[1]:IsShown(), "with a light on each end")
    T.truthy(b.trace.top:GetWidth() < 90, "partway")
    settle()
    T.eq(b.trace.p, 1, "traced all round")
    T.near(b.trace.top:GetWidth(), 98, 1, "the top full")
    T.truthy(b.trace.right:IsShown() and b.trace.bottom:IsShown(), "and the far sides")
    T.rgb(b.trace.right.__vertex, { 1, 0.96, 0.41 }, "in the player's accent")
    T.falsy(b.trace.gleams[1]:IsShown(), "the lights go once the ends meet")
    b:GetScript("OnMouseDown")(b)
    T.falsy(b.lit:IsShown(), "pressed: the lit line goes")
    b:GetScript("OnMouseUp")(b)
    T.truthy(b.lit:IsShown(), "let go: lit again")
    b:GetScript("OnLeave")(b)
    settle()
    T.eq(b.trace.p, 0, "leaving draws it back")
    T.falsy(b.trace.top:IsShown(), "dark again")
    b.SetActive(true)
    settle()
    T.eq(b.trace.p, 1, "switched on: lit all round")
    T.rgb(b.text.__textColor, W.COLORS.value, "white text")
    b.SetActive(false)
    settle()
    T.rgb(b.text.__textColor, W.BUTTON.text, "warm text")
    b.SetOff(true)
    T.falsy(b:IsEnabled(), "off: no clicks")
    T.rgb(b.band.__vertex, W.BUTTON.bandOff, "off: a dim band")
    b:GetScript("OnEnter")(b)
    settle()
    T.eq(b.trace.p, 0, "off: the mouse lights nothing")
    b.SetOff(false)
    T.truthy(b:IsEnabled(), "on again")
end)

T.test("the close X: warm at rest, the accent under the mouse, dim while pressed, calls back", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    DUI.Style.Accent = function() return 1, 0.96, 0.41 end
    local hit = 0
    local x = W.Close(UIParent, function() hit = hit + 1 end)
    T.rgb(x.icon.__vertex, DUI.Style.INK.LABEL, "warm tan at rest")
    x:GetScript("OnEnter")(x)
    T.rgb(x.icon.__vertex, { 1, 0.96, 0.41 }, "accent on hover")
    x:GetScript("OnMouseDown")(x)
    T.near(x.icon:GetAlpha(), 0.6, 0.01, "dimmer while pressed")
    x:GetScript("OnMouseUp")(x)
    x:GetScript("OnClick")(x)
    T.eq(hit, 1, "calls back")
    local r = x.__hitRect
    T.truthy(r and r[2] <= -W.CLOSE_REACH and r[3] <= -W.CLOSE_REACH and r[4] <= -W.CLOSE_REACH,
        "takes clicks past what it draws, easy to hit again and again")
    local game = CreateFrame("Button", nil, UIParent)
    W.DressClose(game)
    T.truthy(game.__hitRect and game.__hitRect[2] < 0, "the game's X dressed as ours reaches as far")
end)

T.test("a tab: tan at rest, light on hover, picked in the accent with its line, off takes no clicks", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    DUI.Style.Accent = function() return 1, 0.96, 0.41 end
    DUI.Style.AccentPair = function() return nil end
    local t = W.Tab(UIParent, "Spells")
    t:SetWidth(60)
    T.rgb(t.text.__textColor, DUI.Style.INK.LABEL, "tan at rest")
    T.falsy(t.line:IsShown(), "no line")
    t:GetScript("OnEnter")(t)
    T.rgb(t.text.__textColor, DUI.Style.INK.VALUE, "light on hover")
    t.Pick(true)
    T.truthy(t.line:IsShown(), "picked: the line")
    T.rgb(t.line.__vertex, { 1, 0.96, 0.41 }, "in the accent")
    t.SetOff(true)
    T.falsy(t:IsEnabled(), "off: no clicks")
end)

T.test("a changed setting shows the reset arrow and no dot; resetting hides it", function()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("UnitFrames.player")
    local row = rowFor(DUI.OptionsPanel.PageFrame(), "player.width")
    T.falsy(row.reset:IsShown(), "default: no reset")
    DUI.Options.Set(row.page, row.item, row.item.min)
    T.truthy(row.reset:IsShown(), "changed: the reset arrow")
    T.falsy(row.dot, "no changed dot")
    row.reset:GetScript("OnClick")(row.reset)
    T.falsy(row.reset:IsShown(), "reset: no arrow")
end)

T.test("rows are 28 px and grow for a label that wraps", function()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("UnitFrames.player")
    local row = rowFor(DUI.OptionsPanel.PageFrame(), "player.width")
    T.eq(row:GetHeight(), 28)
    row.label.GetStringHeight = function() return 30 end    -- two lines
    row.Measure()
    T.eq(row:GetHeight(), 42)
end)

T.test("a card's title is INK.LABEL (docs/controls.md), with an outline and the lit top line", function()
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show("UnitFrames.player")
    local card = DUI.OptionsPanel.PageFrame().cards[1]
    T.rgb(card.title.__textColor, DUI.Style.INK.LABEL, "card heading")
    T.rgb(card.edge.__vertex, DUI.Widgets.COLORS.cardEdge, "outline")
    T.rgb(card.lit.__color, DUI.Widgets.COLORS.cardLit, "lit top line")
end)

T.test("a General change refreshes the open window once (the style repaint), a module change at once", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("appearance")
    stub.RunTimers()
    local n, orig = 0, P.Refresh
    P.Refresh = function(...) n = n + 1; return orig(...) end
    DUI:Set("general", "motion", false)
    T.eq(n, 0, "waits for the repaint the frame after")
    stub.RunTimers()
    T.eq(n, 1, "once, not twice")
    n = 0
    DUI:Set("UnitFrames", "player.width", 250)
    T.eq(n, 1, "a module's setting: at once")
    n = 0
    stub.EnterCombat()
    DUI:Set("general", "motion", true)
    T.eq(n, 1, "in a fight the repaint waits, so the window doesn't")
    stub.LeaveCombat()
    P.Refresh = orig
end)

-- ---------------------------------------------------------------------
-- The rail, the page list, the header and the window's size
-- ---------------------------------------------------------------------

T.test("the rail: a button per section, its icon in its color; the one on show marked", function()
    local DUI = stub.Load({ module = true })
    local P, Theme = DUI.OptionsPanel, DUI.OptionsTheme
    P.Show("UnitFrames.player")
    local uf, core = P.NavButton("UnitFrames"), P.NavButton("core")
    T.truthy(uf:IsShown() and core:IsShown())
    T.eq(uf.icon.__texture, Theme.IconFile("frames"))
    T.rgb(uf.icon.__vertex, Theme.SECTIONS.UnitFrames.color, "tinted its color")
    T.eq(uf.text:GetText(), "Frames", "the short name under it")
    T.truthy(uf.on and uf.bar:IsShown() and uf.wash:IsShown(), "on show: bar and wash")
    T.falsy(core.on or core.wash:IsShown(), "the others not")
    T.eq(core.icon.__alpha, DUI.OptionsNav.ICON_ALPHA.off, "the others' icons dimmed")
    local _, _, _, _, y1 = core:GetPoint(1)
    local _, _, _, _, y2 = uf:GetPoint(1)
    T.truthy(y2 < y1, "in section order, top to bottom")
    core:GetScript("OnEnter")(core)
    T.eq(core.icon.__alpha, 1, "hovered: full")
    core:GetScript("OnLeave")(core)
end)

T.test("the page list: every page of the section, the one on show marked; sections open where they were left", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    local last
    for _, page in ipairs(DUI.Options.Sections()[2].pages) do
        local b = P.PageButton(page.id)
        T.truthy(b and b:IsShown(), page.id .. " listed")
        local _, _, _, _, y = b:GetPoint(1)
        if last then T.truthy(y < last, page.id .. " under the one before") end
        last = y
    end
    T.truthy(P.PageButton("UnitFrames.player").on, "the page on show marked")
    T.truthy(P.PageButton("UnitFrames.player").bar:IsShown())
    T.falsy(P.PageButton("home"), "another section's pages aren't listed")
    T.eq(P.Nav().listTitle:GetText(), "Unit Frames", "the section's name over its pages")
    local target = P.PageButton("UnitFrames.target")
    target:GetScript("OnClick")(target)
    T.eq(P.Current(), "UnitFrames.target")
    P.NavButton("core"):GetScript("OnClick")(P.NavButton("core"))
    T.eq(P.Current(), "home", "a section opens on its first page")
    T.falsy(P.PageButton("UnitFrames.player"):IsShown(), "the other section's pages put away")
    P.NavButton("UnitFrames"):GetScript("OnClick")(P.NavButton("UnitFrames"))
    T.eq(P.Current(), "UnitFrames.target", "and comes back to the page it was left on")
end)

T.test("searching counts matches on the rail and the page list; sections and pages without any dim", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    P.Search("height")
    T.truthy(tonumber(P.NavButton("UnitFrames").count:GetText()) > 0, "counted on the rail")
    T.truthy(tonumber(P.PageButton(P.Current()).count:GetText()) > 0, "and on the page")
    P.Search("debuffs from others")
    T.truthy(P.NavButton("core").empty, "General has none")
    T.eq(P.NavButton("core").icon.__alpha, DUI.OptionsNav.ICON_ALPHA.empty)
    T.truthy(P.PageButton("UnitFrames.player").empty, "nor has the Player page")
    P.Search("")
    T.eq(P.NavButton("UnitFrames").count:GetText(), "", "no counts once cleared")
    T.falsy(P.NavButton("core").empty)
end)

T.test("the header: the page's title, its section in its color, its description", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.raid")
    local h = P.Header()
    T.eq(h.title:GetText(), "Raid 10")
    T.eq(h.section:GetText(), "Unit Frames")
    T.rgb(h.section.__textColor, DUI.OptionsTheme.SECTIONS.UnitFrames.color)
    T.eq(h.desc:GetText(), DUI.Options.GetPage("UnitFrames.raid").desc)
    P.Show("patchnotes")
    T.eq(h.section:GetText(), "", "no section name when it's the page's own")
end)

T.test("the window opens at 1000 x 680, resizes within limits, and keeps its size for the account", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    local f = P.Frame()
    T.eq(f:GetWidth(), 1000)
    T.eq(f:GetHeight(), 680)
    T.eq(P.PageFrame():GetWidth(), P.ContentWidth(), "the page as wide as its area")
    P.Resize(500, 300)
    T.eq(f:GetWidth(), 860, "no narrower than the least")
    T.eq(f:GetHeight(), 560)
    P.Resize(5000, 5000)
    T.eq(f:GetWidth(), math.floor(UIParent:GetWidth() + 0.5), "no bigger than the screen")
    P.Resize(1240, 720)
    T.eq(f:GetWidth(), 1240)
    T.eq(P.PageFrame():GetWidth(), P.ContentWidth(), "the page follows")
    T.eq(P.CONTENT_WIDTH, P.ContentWidth())
    T.deq(DUI.DB.Root().optionsWindow, { w = 1240, h = 720 }, "kept")

    DUI = stub.Load({ module = true, before = function() end })
    DUI.DB.Root().optionsWindow = { w = 1100, h = 700 }
    DUI.OptionsPanel.Show("home")
    T.eq(DUI.OptionsPanel.Frame():GetWidth(), 1100, "opened at the size kept")
end)

T.test("Ctrl + the wheel scales the options window, over its lists too", function()
    local DUI = stub.Load({ module = true, before = function() end })
    local P = DUI.OptionsPanel
    P.Show("home")
    local f = P.Frame()
    T.eq(f:GetScale(), 1)
    f:GetScript("OnMouseWheel")(f, 1)
    T.eq(f:GetScale(), 1, "no Ctrl: nothing")
    _G.IsControlKeyDown = function() return true end
    f:GetScript("OnMouseWheel")(f, 1)
    T.near(f:GetScale(), 1.05, 1e-6, "a step up")
    local sf = P.PageFrame():GetParent()
    sf:GetScript("OnMouseWheel")(sf, -1)
    sf:GetScript("OnMouseWheel")(sf, -1)
    T.near(f:GetScale(), 0.95, 1e-6, "the page's scroll hands it up")
    for _ = 1, 20 do f:GetScript("OnMouseWheel")(f, 1) end
    T.near(f:GetScale(), P.SCALE_MAX, 1e-6, "kept within its range")
    _G.IsControlKeyDown = nil
    T.near(DUI.DB.Root().optionsWindow.scale, P.SCALE_MAX, 1e-6, "kept")
    P.Resize(1000, 600)
    T.near(DUI.DB.Root().optionsWindow.scale, P.SCALE_MAX, 1e-6, "a resize keeps it")
    T.truthy(f:GetWidth() * P.SCALE_MAX <= UIParent:GetWidth() + 1, "still fits the screen")
end)

-- ---------------------------------------------------------------------
-- Cards in columns, chips and focus
-- ---------------------------------------------------------------------

T.test("a page gets as many 330 px columns as fit, one to three", function()
    local W = stub.Load().Widgets
    T.eq(W.Columns(500), 1)
    T.eq(W.Columns(728), 2)
    T.eq(W.Columns(1200), 3)
    T.eq(W.Columns(2400), 3, "never more than three")
end)

T.test("cards go into the shortest column, in page order", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.target")
    local pf = P.PageFrame()
    T.eq(DUI.Widgets.Columns(pf:GetWidth()), 2)
    local bottoms = { 0, 0 }
    for _, card in ipairs(pf.cards) do
        if card:IsShown() then
            T.falsy(card.wide, card.group.label)
            local other = card.column == 1 and 2 or 1
            T.eq(card.offsetY, bottoms[card.column], card.group.label .. " right under its column's last card")
            T.truthy(bottoms[card.column] <= bottoms[other], card.group.label .. " in the shorter column")
            T.eq(card.offsetX, card.column == 1 and 0 or card:GetWidth() + DUI.Widgets.CARD_GAP)
            bottoms[card.column] = card.offsetY + card:GetHeight() + DUI.Widgets.CARD_GAP
        end
    end
    T.near(pf:GetHeight(), math.max(bottoms[1], bottoms[2]), 1e-6, "the page as tall as its taller column")
end)

T.test("a card with a module's own content or a color pair spans every column", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("gradients")
    local pf = P.PageFrame()
    local wide = 0
    for _, card in ipairs(pf.cards) do
        if card:IsShown() and card.wide then
            wide = wide + 1
            T.eq(card:GetWidth(), pf:GetWidth(), card.group.label .. " full width")
            T.eq(card.offsetX, 0)
        end
    end
    T.truthy(wide > 0, "the color pairs' cards are wide")
    T.truthy(DUI.Widgets.IsWide({ wide = true, items = {} }), "a group can ask")
end)

T.test("a color pair hidden right now leaves its card narrow; showing it widens the card", function()
    local DUI = stub.Load({ infopanel = true })
    local P = DUI.OptionsPanel
    P.Show("InfoPanel.panel")
    local pf = P.PageFrame()
    local look
    for _, card in ipairs(pf.cards) do
        if card.group.label == "Experience bar look" then look = card end
    end
    T.truthy(look, "Experience bar look card")
    T.falsy(look.wide, "custom color hidden: a narrow card")
    T.truthy(look:GetWidth() < pf:GetWidth(), "it sits in a column")
    DUI:Set("InfoPanel", "xp.color", "custom")
    pf.Layout()
    T.truthy(look.wide, "custom color shown: a wide card")
    T.eq(look:GetWidth(), pf:GetWidth())
end)

T.test("a narrow card alone before a wide one takes the whole width, no empty column", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("gradients")
    local pf = P.PageFrame()
    T.truthy(DUI.Widgets.Columns(pf:GetWidth()) > 1, "the page has columns")
    local first = pf.cards[1]
    T.falsy(first.wide, "Gradient settings is a narrow card")
    T.truthy(first:IsShown())
    T.eq(first:GetWidth(), pf:GetWidth(), "it fills the row")
    T.eq(first.offsetX, 0)
end)

T.test("a narrow page is one column; a wide window three", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.colors")
    local pf = P.PageFrame()
    pf:SetWidth(500)
    pf.Layout("")
    local y = 0
    for _, card in ipairs(pf.cards) do
        if card:IsShown() then
            T.eq(card:GetWidth(), 500)
            T.eq(card.offsetY, y, "stacked")
            y = y + card:GetHeight() + DUI.Widgets.CARD_GAP
        end
    end
    P.Resize(1365, 700)
    T.eq(DUI.Widgets.Columns(pf:GetWidth()), 3, "content " .. pf:GetWidth())
    local cols = {}
    for _, card in ipairs(pf.cards) do
        if card:IsShown() and card.column then cols[card.column] = true end
    end
    T.truthy(cols[3], "a third column in use")
end)

T.test("chips: All and one per titled card; picking one shows it alone, again shows all", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.colors")
    local pf, chips = P.PageFrame(), P.Chips()
    T.truthy(chips:IsShown())
    -- A chip per card with rows to show.
    local shown = 0
    for _, card in ipairs(pf.cards) do if (card.count or 0) > 0 then shown = shown + 1 end end
    T.eq(chips.count, shown, "a chip per card")
    T.eq(chips.buttons[1].text:GetText(), "All")
    T.truthy(chips.buttons[1].on, "All lit at first")
    local second = chips.buttons[3]
    T.eq(second.card, pf.cards[2])
    second:Click()
    T.eq(pf.focus, pf.cards[2])
    T.truthy(second.on and not chips.buttons[1].on, "its chip lit")
    T.truthy(second.bg.__gradient or second.bg.__vertex, "filled in the accent")
    for i, card in ipairs(pf.cards) do T.eq(card:IsShown(), i == 2, card.group.label) end
    T.eq(pf.cards[2]:GetWidth(), pf:GetWidth(), "alone at full width")
    T.eq(pf.cards[2].offsetY, 0)
    second:Click()
    T.isnil(pf.focus, "again: all")
    T.truthy(pf.cards[1]:IsShown())
    chips.buttons[3]:Click()
    chips.buttons[1]:Click()
    T.isnil(pf.focus, "All: all")
    chips.buttons[3]:Click()
    P.Show("UnitFrames.player")
    P.Show("UnitFrames.colors")
    T.isnil(pf.focus, "a page opens on All")
end)

T.test("no chip for a card with nothing to show right now", function()
    local DUI = stub.Load()
    local O = DUI.Options
    O.RegisterSection("Test", "Test", 500)
    O.RegisterPage({ id = "test.page", section = "Test", label = "Test", scope = "Test",
        defaults = { a = true, b = true, c = true }, groups = {
            { label = "One", items = { { type = "toggle", key = "a", label = "A" } } },
            { label = "Two", items = { { type = "toggle", key = "b", label = "B" } } },
            { label = "Hidden", items = { { type = "toggle", key = "c", label = "C", hidden = function() return true end } } },
        } })
    DUI.OptionsPanel.Show("test.page")
    local chips = DUI.OptionsPanel.Chips()
    T.eq(chips.count, 2, "One and Two")
    for _, b in ipairs(chips.buttons) do
        if b:IsShown() then T.truthy(b.text:GetText() ~= "Hidden") end
    end
end)

-- Tabs: a long page's cards split into tabs, Basics first.
local function tabPage(DUI)
    local O = DUI.Options
    O.RegisterSection("Test", "Test", 500)
    O.RegisterPage({ id = "test.tabs", section = "Test", label = "Tabs", scope = "Test",
        defaults = { a = true, b = true, c = true, d = true }, groups = {
            { label = "Size", tab = "Basics", items = { { type = "toggle", key = "a", label = "A", desc = "A." } } },
            { label = "Health", items = { { type = "toggle", key = "b", label = "B", desc = "B." } } },
            { label = "Words", tab = "Text", items = { { type = "toggle", key = "c", label = "C", desc = "C." } } },
            { label = "Icons", tab = "Extras", items = { { type = "toggle", key = "d", label = "D", desc = "D." } } },
        } })
end

T.test("tabs: a page with tabs shows them instead of chips, its first tab's cards only", function()
    local DUI = stub.Load()
    tabPage(DUI)
    local P = DUI.OptionsPanel
    P.Show("test.tabs")
    local pf, tabs = P.PageFrame(), P.Tabs()
    T.truthy(tabs:IsShown(), "the tab row")
    T.falsy(P.Chips():IsShown(), "no chips with tabs")
    T.eq(#pf.tabs, 3)
    T.eq(tabs.buttons[1].text:GetText(), "Basics")
    T.truthy(tabs.buttons[1].picked, "Basics picked first")
    T.eq(pf.tab, "Basics")
    T.eq(pf.cards[2].tab, "Basics", "a card without a tab sits on the one before it")
    T.truthy(pf.cards[1]:IsShown() and pf.cards[2]:IsShown())
    T.falsy(pf.cards[3]:IsShown() or pf.cards[4]:IsShown(), "other tabs' cards hidden")
    tabs.buttons[2]:Click()
    T.eq(pf.tab, "Text")
    T.truthy(tabs.buttons[2].picked and not tabs.buttons[1].picked)
    T.truthy(pf.cards[3]:IsShown())
    T.falsy(pf.cards[1]:IsShown())
    T.eq(pf.cards[3].offsetY, 0, "at the top")
end)

T.test("tabs: a jump, a search result and reopening the page pick the right tab", function()
    local DUI = stub.Load()
    tabPage(DUI)
    local P = DUI.OptionsPanel
    P.Show("test.tabs")
    local pf = P.PageFrame()
    local lit = P.JumpTo({ "d" })
    T.eq(pf.tab, "Extras", "the jump went to the row's tab")
    T.eq(#lit, 1, "its row lit")
    P.Show("UnitFrames.player")
    P.Show("test.tabs")
    T.eq(pf.tab, "Basics", "a page opens on its first tab")
    P.Search("words")
    T.falsy(P.Tabs():IsShown(), "no tabs while searching")
    P.OpenResult("test.tabs", { "c" })
    T.eq(pf.tab, "Text", "a result opens on its tab")
    T.truthy(P.Tabs():IsShown())
end)

-- Lock after Unlock put the window back through Panel.Show, which opens a
-- page on its first tab: the scroll spot of tab 3 landed on tab 1.
T.test("tabs: locking again puts the window back on the tab and scroll spot you left", function()
    local DUI = stub.Load()
    tabPage(DUI)
    local P = DUI.OptionsPanel
    P.Show("test.tabs")
    P.SetTab("Extras")
    local scroll = P.PageFrame():GetParent()
    scroll:SetVerticalScroll(42)
    DUI.Movers.Unlock()
    DUI.Movers.Lock()
    T.eq(P.Current(), "test.tabs")
    T.eq(P.PageFrame().tab, "Extras", "the tab it was left on")
    T.eq(scroll:GetVerticalScroll(), 42)
end)

-- The one Reset page button stayed armed across a page switch: the next
-- page reset in one click.
T.test("Reset page armed on one page is plain again on the next", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    DUI:Set("UnitFrames", "player.width", 300)
    P.Refresh()
    local b = P.ResetButton()
    b:Click()
    T.truthy(b.armed)
    P.Show("UnitFrames.target")
    T.falsy(b.armed, "a page switch disarms it")
    T.eq(b.text:GetText(), "Reset page")
    b:Click()
    T.truthy(b.armed, "one click arms it again, resets nothing")
    b:Hide()
    T.falsy(b.armed, "hidden: disarmed")
end)

T.test("tabs: the frame pages open on Basics, the rest in Bars, Text, Auras and Extras", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.party")
    local pf = P.PageFrame()
    T.deq(pf.tabs, { "Basics", "Bars", "Text", "Auras", "Extras" })
    T.eq(pf.tab, "Basics")
    T.eq(pf.Find("party.width").tab, "Basics", "size in Basics")
    T.eq(pf.Find("party.direction").tab, "Basics", "layout in Basics")
    T.eq(pf.Find("party.fade.mode").tab, "Basics", "visibility in Basics")
    T.eq(pf.Find("party.media.health").tab, "Bars", "bar texture out of Basics")
    T.eq(pf.Find("party.showPercent").tab, "Text")
    T.eq(pf.Find("party.indicators.show").tab, "Auras")
    local rows = 0
    for _, card in ipairs(pf.cards) do
        if card:IsShown() then rows = rows + (card.count or 0) end
    end
    T.truthy(rows <= 30, "Basics is short: " .. rows .. " rows")
    for _, id in ipairs({ "player", "target", "focus", "pet", "targettarget", "raid" }) do
        P.Show("UnitFrames." .. id)
        T.eq(P.PageFrame().tabs[1], "Basics", id)
        T.truthy(P.Tabs():IsShown(), id .. " tab row")
    end
end)

T.test("tabs: Raid 20 following Raid 10 shows only its Raid size card", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.raid20")
    local pf = P.PageFrame()
    local shown = {}
    for _, card in ipairs(pf.cards) do if card:IsShown() then shown[#shown + 1] = card.group.label end end
    T.deq(shown, { "Raid size" })
    T.falsy(P.Tabs():IsShown(), "no tabs with one card")
    for _, hit in ipairs(DUI.Options.Search("tiles per line")) do
        T.eq(hit.page.id, "UnitFrames.raid", "search skips the following sizes' copies")
    end
    DUI.Options.GetPage("UnitFrames.raid20").groups[1].items[1].set(false)
    P.Refresh()
    T.truthy(P.Tabs():IsShown(), "its own setup: all its tabs")
end)

-- Picker cards: one card editing one of several alike things ("Settings for").
local function pickPage(DUI)
    local O = DUI.Options
    O.RegisterSection("Test", "Test", 500)
    local saved = {}
    DUI.pickSaved = saved
    local function rows(n)
        return { { type = "slider", key = "s" .. n .. ".size", label = "Square size", min = 1, max = 9, desc = "Size.",
                   get = function() return saved[n] or 2 end, set = function(v) saved[n] = v end,
                   default = function() return 2 end },
                 { type = "toggle", key = "s" .. n .. ".on", label = "Square glow", desc = "Glow." } }
    end
    local defaults = {}
    for n = 1, 3 do defaults["s" .. n] = { size = 2, on = false } end
    local card = O.PickCard({ label = "Squares", desc = "The squares.", pickDesc = "Which square the rows below set.",
        choices = { { id = "1", label = "Square 1", items = rows(1) }, { id = "2", label = "Square 2", items = rows(2) },
                    { id = "3", label = "Square 3", items = rows(3) } },
        copy = { label = "Copy from", desc = "Another square.", button = "Copy the square", buttonDesc = "Copies it.",
                 fn = function(from, to) saved[tonumber(to)] = saved[tonumber(from)] end } })
    O.RegisterPage({ id = "test.pick", section = "Test", label = "Pick", scope = "Test", defaults = defaults,
        groups = { card } })
    return card
end

T.test("picker card: a Settings for row, only the picked thing's rows show", function()
    local DUI = stub.Load()
    pickPage(DUI)
    DUI.Options.Validate({}, {})
    local errors = DUI.Options.ValidatePage(DUI.Options.GetPage("test.pick"))
    T.eq(#errors, 0, table.concat(errors, "; "))
    local P = DUI.OptionsPanel
    P.Show("test.pick")
    local pf = P.PageFrame()
    local card, row1 = pf.Find("s1.size")
    local _, row2 = pf.Find("s2.size")
    T.truthy(row1:IsShown(), "square 1 first")
    T.falsy(row2:IsShown())
    local picker = card.rows[1]
    T.eq(picker.item.label, "Settings for")
    picker.item.set("2")
    P.Refresh()
    T.truthy(row2:IsShown())
    T.falsy(row1:IsShown())
    -- A jump to square 3's row picks square 3.
    local lit = P.JumpTo({ "s3.on" })
    T.eq(#lit, 1)
    T.eq(picker.item.get(), "3")
end)

T.test("picker card: search finds the picked one's rows; Reset page and Copy reach every one", function()
    local DUI = stub.Load()
    pickPage(DUI)
    local O = DUI.Options
    T.eq(#O.Search("square glow"), 1, "one row, not three")
    local saved = DUI.pickSaved
    saved[3] = 7
    local page = O.GetPage("test.pick")
    local card = page.groups[1]
    card.items[1].set("1")
    local from = card.items[2]
    T.eq(from.label, "Copy from")
    from.set("3")
    card.items[3].func()
    T.eq(saved[1], 7, "copied onto the picked one")
    O.ResetPage(page)
    T.eq(saved[3], 2, "Reset page: a hidden one too")
    T.eq(saved[1], 2)
end)

T.test("picker card: picking a Copy from source wakes the Copy button", function()
    local DUI = stub.Load()
    local spec = pickPage(DUI)
    local O, P = DUI.Options, DUI.OptionsPanel
    P.Show("test.pick")
    local card = P.PageFrame().Find("s1.size")
    local button
    for _, row in ipairs(card.rows) do
        if row.item and row.item.label == "Copy the square" then button = row end
    end
    T.truthy(button, "the Copy row")
    T.truthy(button.disabled, "off until a source is picked")
    O.Set(O.GetPage("test.pick"), spec.items[2], "3")
    T.falsy(button.disabled, "on once one is")
end)

T.test("no chips for a page with fewer than two titled cards, or while searching", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("patchnotes")
    T.falsy(P.Chips():IsShown(), "patch notes: one bare card")
    P.Show("UnitFrames.target")
    T.falsy(P.Chips():IsShown(), "a page with tabs")
    P.Show("UnitFrames.colors")
    T.truthy(P.Chips():IsShown())
    P.Search("width")
    T.falsy(P.Chips():IsShown(), "searching")
    P.Search("")
    T.truthy(P.Chips():IsShown())
end)

T.test("a click on a frame's part opens its tab and lights its rows", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.target")
    local pf = P.PageFrame()
    local card = pf.Find("target.showName")
    local text = pf.Find("targetText.name")
    T.eq(card, text, "the name's settings share a card")
    local lit = P.JumpTo({ "target.showName", "targetText.name" })
    T.eq(pf.tab, "Text", "its tab")
    T.isnil(pf.focus, "a tabbed page shows the whole tab")
    T.truthy(card:IsShown())
    T.eq(#lit, 2, "both rows lit")
    P.JumpTo({ "target.width", "target.showName" })
    T.eq(pf.tab, "Basics", "the first setting's tab")
end)

T.test("a click on a part of a page without tabs shows its card alone when its settings sit in one card", function()
    local DUI = stub.Load()
    local O = DUI.Options
    O.RegisterSection("Test", "Test", 500)
    O.RegisterPage({ id = "test.focus", section = "Test", label = "Focus", scope = "Test",
        defaults = { a = true, b = true, c = true }, groups = {
            { label = "One", items = { { type = "toggle", key = "a", label = "A", desc = "A." },
                                       { type = "toggle", key = "b", label = "B", desc = "B." } } },
            { label = "Two", items = { { type = "toggle", key = "c", label = "C", desc = "C." } } },
        } })
    local P = DUI.OptionsPanel
    P.Show("test.focus")
    local pf = P.PageFrame()
    local lit = P.JumpTo({ "a", "b" })
    T.eq(pf.focus, pf.cards[1], "that card alone")
    T.eq(#lit, 2, "both rows lit")
    P.JumpTo({ "a", "c" })
    T.isnil(pf.focus, "two cards: all of them")
end)

-- ---------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------

T.test("starting a search closes an open dropdown list", function()
    local DUI = stub.Load({ module = true })
    local P, W = DUI.OptionsPanel, DUI.Widgets
    P.Show("UnitFrames.player")
    local dropdown
    for _, card in ipairs(P.PageFrame().cards) do
        for _, row in ipairs(card.rows) do
            if row.item.type == "dropdown" and not dropdown then dropdown = row.control end
        end
    end
    dropdown:Click()
    T.eq(W.menuOwner, dropdown, "open")
    P.Search("width")
    T.isnil(W.menuOwner, "closed")
end)

local function resultBlock(P, pageId)
    for _, b in ipairs(P.Results().blocks) do
        if b:IsShown() and b.heading.pageId == pageId then return b end
    end
end

T.test("two letters or more: every matching setting, live, in a card per page and card", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    P.Search("w")
    T.falsy(P.Results():IsShown(), "one letter: still the page")
    P.Search("width")
    local res = P.Results()
    T.truthy(res:IsShown(), "the results")
    T.falsy(P.PageFrame():IsShown(), "in the page's place")
    T.falsy(P.Strip():IsShown(), "no sample")
    T.falsy(P.Chips():IsShown(), "no chips")
    T.eq(P.Header().title:GetText(), "Search")
    local hits = DUI.Options.Search("width")
    T.eq(P.Header().desc:GetText(), #hits .. " settings match.")
    T.eq(#res.shown, #hits, "a row for each")
    local b = resultBlock(P, "UnitFrames.player")
    T.eq(b.heading.text:GetText(), "Unit Frames › Player")
    T.rgb(b.heading.text.__textColor, DUI.OptionsTheme.SECTIONS.UnitFrames.color)
    T.truthy(res.Row("player.width"), "the player's width among them")
    T.truthy(res.Row("raid.width"), "and the raid's")
end)

T.test("a setting shared by two pages (the Quick actions) gets a row in each card: no empty card", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    for _, query in ipairs({ "reset", "frames" }) do
        P.Search(query)
        local res = P.Results()
        local n = 0
        for _, b in ipairs(res.blocks) do
            if b:IsShown() then
                local rows = 0
                for _, row in ipairs(res.shown) do
                    if row:GetParent() == b and row:IsShown() then rows = rows + 1 end
                end
                T.truthy(rows > 0, query .. ": " .. b.heading.text:GetText() .. " " .. b.heading.card:GetText() .. " has rows")
                n = n + rows
            end
        end
        T.eq(n, #res.shown, query .. ": every result row sits in a card")
    end
end)

T.test("the counts on the page list match the results (hidden settings left out of both)", function()
    local DUI = stub.Load(ALL)
    local O = DUI.Options
    for _, query in ipairs({ "font", "reset", "frames", "show", "width" }) do
        local perPage = {}
        for _, hit in ipairs(O.Search(query)) do
            perPage[hit.page] = (perPage[hit.page] or 0) + 1
        end
        for _, page in O.Pages() do
            T.eq(O.CountMatches(page, query), perPage[page] or 0, query .. " on " .. page.id)
        end
    end
end)

T.test("a change made in the results is made at once", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    P.Search("width")
    local row = P.Results().Row("player.width")
    local box = row.control.box
    box:SetText("200")
    box:GetScript("OnEnterPressed")(box)
    T.eq(DUI.Options.Get(row.page, row.item), 200)
    T.truthy(P.Results().Row("player.width").reset:IsShown(), "shown changed")
end)

T.test("a setting changed elsewhere while the results show is shown changed there", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    P.Search("width")
    local row = P.Results().Row("player.width")
    T.falsy(row.reset:IsShown(), "default at first")
    DUI:Set("UnitFrames", "player.width", row.item.min)
    row = P.Results().Row("player.width")
    T.truthy(row.reset:IsShown(), "re-read after the change")
    T.eq(row.control.box:GetText(), DUI.Widgets.FormatValue(row.item, row.item.min))
end)

T.test("a result's heading opens its page there and lights the settings", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    P.Nav().searchBox:SetText("width")
    local b = resultBlock(P, "UnitFrames.raid")
    b.heading:Click()
    T.eq(P.Current(), "UnitFrames.raid")
    T.falsy(P.Results():IsShown(), "the search over")
    T.eq(P.Nav().searchBox:GetText(), "", "and its box empty")
    local _, row = P.PageFrame().Find("raid.width")
    T.truthy(row.flash and row.flash:IsShown(), "lit up")
end)

T.test("at most 60 results; a line says how many more", function()
    local DUI = stub.Load(ALL)
    local P = DUI.OptionsPanel
    P.Show("home")
    local hits = DUI.Options.Search("show")
    T.truthy(#hits > DUI.OptionsResults.MAX, #hits .. " matches")
    P.Search("show")
    T.eq(#P.Results().shown, DUI.OptionsResults.MAX)
    T.truthy(P.Results().more:IsShown())
    T.eq(P.Results().more:GetText(), "And " .. (#hits - 60) .. " more: keep typing to narrow it down.")
end)

T.test("results from the section you're on come first, your page first of all", function()
    local DUI = stub.Load(ALL)
    local P = DUI.OptionsPanel
    local hits = DUI.Options.Search("fade")
    -- A section whose matches come late in window order.
    local here = hits[#hits].page
    P.Show(here.id)
    P.Search("fade")
    local shown = P.Results().shown
    T.eq(shown[1].page.id, here.id, "your page first")
    local left = false
    for _, row in ipairs(shown) do
        if row.page.section ~= here.section then left = true
        else T.falsy(left, "no result of this section after another's") end
    end
    T.truthy(left, "the other sections still follow")
end)

T.test("nothing matching says so", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    P.Search("zzzz")
    T.truthy(P.EmptyText():IsShown())
    T.eq(P.EmptyText():GetText(), "No settings match \"zzzz\".")
    T.eq(P.Header().desc:GetText(), "0 settings match.")
    P.Search("")
    T.falsy(P.EmptyText():IsShown())
end)

T.test("clearing the search goes back to the page, scrolled where it was", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.target")
    local scroll = P.PageFrame():GetParent()
    scroll:SetVerticalScroll(40)
    P.Search("width")
    T.eq(scroll:GetVerticalScroll(), 0, "results from the top")
    P.Search("")
    T.eq(P.Current(), "UnitFrames.target")
    T.truthy(P.PageFrame():IsShown())
    T.eq(scroll:GetScrollChild(), P.PageFrame())
    T.eq(scroll:GetVerticalScroll(), 40, "where it was")
    T.eq(P.Header().title:GetText(), "Target")
    T.truthy(P.Strip():IsShown(), "its sample back")
end)

T.test("clicking a page while searching ends the search and opens it", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.player")
    P.Nav().searchBox:SetText("width")
    local raid = P.PageButton("UnitFrames.raid")
    raid:Click()
    T.eq(P.Current(), "UnitFrames.raid")
    T.falsy(P.Results():IsShown())
    T.eq(P.Nav().searchBox:GetText(), "")
end)

T.test("dragging the corner pins the window's top-left, so the corner follows the mouse", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    local f = P.Frame()
    f.GetLeft = function() return 300 end
    f.GetTop = function() return 900 end
    local grip = f.grip   -- the window kit's (Win.Grip)
    T.truthy(grip, "the grip")
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    local point, rel, relPoint, x, y = f:GetPoint(1)
    T.eq(point, "TOPLEFT")
    T.eq(rel, UIParent)
    T.eq(relPoint, "BOTTOMLEFT")
    T.eq(x, 300)
    T.eq(y, 900)
end)

T.test("dragging the corner grows the window by the mouse's move, never past the screen", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    local f = P.Frame()
    f:SetSize(1000, 680)
    f.GetLeft = function() return 300 end
    f.GetTop = function() return 900 end
    local grip = f.grip   -- the window kit's (Win.Grip)
    local cx, cy = 1300, 220
    local old = GetCursorPosition
    GetCursorPosition = function() return cx, cy end
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    cx, cy = 1350, 200
    grip:GetScript("OnUpdate")(grip, 0.01)
    T.eq(f:GetWidth(), 1050, "50 px right")
    T.eq(f:GetHeight(), 700, "20 px down")
    cx, cy = 99999, -99999
    grip:GetScript("OnUpdate")(grip, 0.01)
    T.truthy(f:GetWidth() <= UIParent:GetWidth() - 300, "stops at the screen's right edge")
    T.truthy(f:GetHeight() <= 900, "stops at the screen's bottom")
    grip:GetScript("OnMouseUp")(grip, "LeftButton")
    T.falsy(grip:GetScript("OnUpdate"), "let go: no more sizing")
    GetCursorPosition = old
end)

-- The window closing mid-drag (Escape) kept no size: the next open came
-- back at the old one.
T.test("closing the window mid-drag keeps the size it was dragged to", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show("home")
    local f = P.Frame()
    f:SetSize(1000, 680)
    f.GetLeft = function() return 300 end
    f.GetTop = function() return 900 end
    local grip = f.grip
    stub.cursorPos = { 1300, 220 }
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    stub.cursorPos = { 1340, 220 }
    grip:GetScript("OnUpdate")(grip, 0.01)
    f:Hide()
    T.falsy(grip:GetScript("OnUpdate"), "no more sizing")
    T.eq(DUI.DB.Root().optionsWindow.w, 1040, "kept for the account")
end)

T.test("a dropdown list grows to fit its longest choice, so none is cut off", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local owner = CreateFrame("Button", nil, UIParent)
    owner:SetSize(150, 26)
    local long = "Horizontal (light at the left, dark at the right)"
    W.OpenMenu(owner, { "a", "b" }, { a = "Short", b = long }, "a", function() end)
    local row = W.MenuRow(2)
    T.truthy(row:GetParent():GetWidth() >= #long * 7 + 42, "the list as wide as the long choice")
    W.CloseMenu()
    W.OpenMenu(owner, { "a" }, { a = "Short" }, "a", function() end)
    T.eq(W.MenuRow(1):GetParent():GetWidth(), 150, "never narrower than the dropdown")
    W.CloseMenu()
end)

-- A new frame starts shown: built shown, the first open is no change, so
-- its OnShow (the fade in) never ran after a reload.
T.test("the very first open after a reload fades in, like every later one", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show()
    local g = P.Frame().__duiMotion and P.Frame().__duiMotion.appearFade
    T.truthy(g and g:IsPlaying(), "the fade in plays on the first open")
end)

-- Closing fades the window out first (Motion.Vanish); the fade's end (its
-- OnFinished) stands in for the time passing.
T.test("the window fades out on close; Escape goes through the motion kit; a toggle mid-fade opens it again", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    P.Show()
    local f = P.Frame()
    local function fadeDone()
        local g = f.__duiMotion and f.__duiMotion.vanish
        local fn = g and g:GetScript("OnFinished")
        if fn then fn(g) end
    end
    for _, n in ipairs(UISpecialFrames) do T.truthy(n ~= "DaylightUIOptions", "Escape is the stand-in's, not the window's") end
    P.Toggle()
    T.truthy(f:IsShown(), "still on screen while it fades")
    T.falsy(P.IsShown(), "but counts as closed")
    P.Toggle()
    T.truthy(P.IsShown(), "a toggle mid-fade opens it again")
    T.eq(f:GetAlpha(), 1)
    -- Escape: the game hides the stand-in; the window fades, then hides.
    for _, n in ipairs(UISpecialFrames) do
        local fr = _G[n]
        if fr and fr:IsShown() then fr:Hide() end
    end
    T.truthy(f:IsShown())
    T.falsy(P.IsShown())
    fadeDone()
    T.falsy(f:IsShown(), "gone once the fade ends")
end)

-- Switching pages: the new one slides in from the side of the list it's on.
T.test("a page switched to slides in from where it sits in the list", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    -- Two pages of one section, in list order.
    local pages
    for _, s in ipairs(DUI.Options.Sections()) do
        if #s.pages >= 2 then pages = s.pages; break end
    end
    local a, b = pages[1].id, pages[2].id
    local function slide(id)
        local m = P.PageFrame(id).__duiMotion
        return m and m.slideIn
    end
    P.Show(a)
    T.falsy(slide(a) and slide(a):IsPlaying(), "opening the window: its own fade, no slide")
    P.Show(b)
    T.truthy(slide(b):IsPlaying(), "slides in")
    T.eq(slide(b).dy, -P.SLIDE, "further down the list: up from below")
    P.Show(a)
    T.eq(slide(a).dy, P.SLIDE, "further up: down from above")
    slide(a):Stop()
    P.Show(a)
    T.falsy(slide(a):IsPlaying(), "the same page again: no slide")
end)

-- With the page: its header text and its sample fade in (the old ones go at
-- once); the search results slide in when a search starts, not per letter.
T.test("a page switch fades the header and sample in; the first search slides the results in", function()
    local DUI = stub.Load({ module = true })
    local P = DUI.OptionsPanel
    local function fading(r) local m = r.__duiMotion; return m and m.fade and m.fade:IsPlaying() == true end
    local function stop(r) if r.__duiMotion and r.__duiMotion.fade then r.__duiMotion.fade:Stop() end end
    P.Show("home")
    local h = P.Header()
    local texts = { h.title, h.section, h.desc }
    for _, fs in ipairs(texts) do T.falsy(fading(fs), "opening the window: its own fade") end
    P.Show("UnitFrames.player")
    for _, fs in ipairs(texts) do
        T.truthy(fading(fs), "the header text fades in with the page")
        T.eq(fs:GetAlpha(), 1, "and rests at full")
        stop(fs)
    end
    local strip = P.Strip()
    T.truthy(strip:IsShown(), "the frame page has a sample")
    T.truthy(fading(strip), "the sample fades in too")
    T.eq(strip:GetAlpha(), 1)
    stop(strip)
    -- Search: the results come in once, as the search starts.
    local res = P.Results()
    local function sliding() local m = res.__duiMotion; return m and m.slideIn and m.slideIn:IsPlaying() == true end
    P.Search("w")
    T.falsy(sliding(), "one letter: no results yet")
    P.Search("wi")
    T.truthy(sliding(), "the results slide in")
    T.eq(res.__duiMotion.slideIn.dy, -P.SLIDE, "up from below, like a page")
    res.__duiMotion.slideIn:Stop()
    P.Search("wid")
    T.falsy(sliding(), "another letter doesn't replay it")
    P.Search("")
    -- Motion off: everything at full at once, nothing playing.
    DUI:Set("general", "motion", false)
    P.Show("home")
    for _, fs in ipairs(texts) do stop(fs) end
    stop(strip)
    P.Show("UnitFrames.player")
    for _, fs in ipairs(texts) do
        T.falsy(fading(fs), "motion off: no fade")
        T.eq(fs:GetAlpha(), 1)
    end
    T.falsy(fading(strip))
    T.eq(strip:GetAlpha(), 1)
    P.Search("wi")
    T.falsy(sliding(), "motion off: no slide")
    T.eq(res:GetAlpha(), 1)
end)

-- Design mode drops used to land in "random" places. A dot is only a marker,
-- and each spot anchors the piece its own way (a row's pinned end, its grow
-- side), so an offset worked out from the dot jumped by that gap. The piece
-- must land where it was let go, whichever dot is nearest.
T.test("a Design mode drop leaves the piece where it was let go, on any spot", function()
    local DUI, UF = stub.Load({ module = true })
    local cfg = { spot = "a", x = 0, y = 0 }
    -- Owner px from its top left, y down; the screen is the same px, y up.
    local owner = CreateFrame("Frame", nil, UIParent)
    owner.GetLeft = function() return 0 end
    owner.GetTop = function() return 200 end
    owner.GetEffectiveScale = function() return 1 end
    local dots = { { spot = "a", x = 50, y = 50 }, { spot = "b", x = 150, y = 50 } }
    -- Each spot puts the piece's middle somewhere else than its dot.
    local OFF = { a = { 40, 0 }, b = { -25, 15 } }
    local piece = CreateFrame("Frame", nil, owner)
    local mid
    local function lay()
        local d = cfg.spot == "a" and dots[1] or dots[2]
        mid = { d.x + OFF[cfg.spot][1] + cfg.x, d.y + OFF[cfg.spot][2] - cfg.y }
    end
    piece.GetEffectiveScale = function() return 1 end
    piece.GetRect = function() return mid[1] - 10, 200 - mid[2] - 5, 20, 10 end
    piece.GetCenter = function() return mid[1], 200 - mid[2] end
    piece.SetPoint = function(_, _, _, _, x, y) mid = { x, 200 - y } end   -- the drag carries it
    piece.ClearAllPoints = function() end
    local sample = { frame = CreateFrame("Frame", nil, UIParent) }
    function sample.Refresh() lay(); return 100 end
    function sample.Parts()
        return { { label = "Debuffs", keys = {}, region = piece,
                   move = { spotKey = "spot", xKey = "x", yKey = "y", owner = owner, dots = dots,
                            drop = function(x, y) return UF.Spots.Drop(dots, x, y) end } } }
    end
    local strip = DUI.SampleStrip.New(UIParent, function() end, function(changes)
        for _, c in ipairs(changes) do cfg[c[1]] = c[2] end
    end)
    strip.SetPage({ id = "fake", sample = function() return sample end })
    strip.SetDesign(true)
    strip.Redraw(600, 300)
    local b = strip.Hotspots()[1]
    local cx, cy = 0, 0
    local old = GetCursorPosition
    GetCursorPosition = function() return cx, cy end
    local function drag(fromX, fromY, toX, toY)
        cx, cy = fromX, 200 - fromY
        b:GetScript("OnMouseDown")(b, "LeftButton")
        cx, cy = toX, 200 - toY
        strip:GetScript("OnUpdate")(strip, 0.01)
        b:GetScript("OnMouseUp")(b, "LeftButton")
        b = strip.Hotspots()[1]
    end
    -- Grabbed off its middle, carried right next to dot b (a new spot).
    lay()
    local gx, gy = mid[1] + 6, mid[2] - 3          -- the grab, from the middle: (6, -3)
    drag(gx, gy, 140, 80)
    T.eq(cfg.spot, "b")
    T.near(mid[1], 134, 0.5, "x where let go")
    T.near(mid[2], 83, 0.5, "y where let go")
    -- Again from there, a little up: it moves by just that, no creep.
    drag(140, 80, 140, 70)
    T.near(mid[1], 134, 0.5); T.near(mid[2], 73, 0.5)
    -- Dropped within the magnet of dot a, the piece used to jump to spot a's own
    -- anchor, 40 px off the dot. It must sit on the dot.
    lay()
    drag(mid[1], mid[2], 52, 49)
    T.eq(cfg.spot, "a")
    T.near(mid[1], 50, 0.5, "snapped: middle on the dot (x)")
    T.near(mid[2], 50, 0.5, "snapped: middle on the dot (y)")
    -- Just past the magnet it stays where it was let go, so small moves by
    -- dragging still work.
    lay()
    drag(mid[1], mid[2], 54, 50)
    T.near(mid[1], 54, 0.5, "free: x where let go")
    T.near(mid[2], 50, 0.5, "free: y where let go")
    GetCursorPosition = old
end)

-- W.Scroll, the shared scroll bar.
local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

local function scrollWorld(childH)
    local DUI = stub.Load({})
    local W = DUI.Widgets
    local host = CreateFrame("Frame", nil, UIParent)
    local sf = CreateFrame("ScrollFrame", nil, host)
    sf:SetHeight(100)
    local child = CreateFrame("Frame", nil, sf)
    child:SetHeight(childH)
    sf:SetScrollChild(child)
    local bar = W.Scroll(sf)
    bar:SetHeight(100)
    return W, sf, bar, child
end

T.test("scroll bar: softly shown at rest, the wheel glides and lights it, it dims after a while", function()
    local W, sf, bar = scrollWorld(400)
    stub.RunOnUpdate(bar, 1)
    T.eq(bar:GetAlpha(), W.SCROLL.rest, "at rest: shown softly (more below)")
    sf:GetScript("OnMouseWheel")(sf, -1)
    T.eq(bar:GetAlpha(), 1, "woke")
    T.truthy(sf:GetVerticalScroll() < W.SCROLL.step, "still gliding")
    settle()
    T.eq(sf:GetVerticalScroll(), W.SCROLL.step, "glided one notch")
    -- Two notches before the glide lands add up.
    sf:GetScript("OnMouseWheel")(sf, -1)
    sf:GetScript("OnMouseWheel")(sf, -1)
    settle()
    T.eq(sf:GetVerticalScroll(), 3 * W.SCROLL.step)
    -- The thumb: a quarter of the bar (100 of 400 shown), its spot by the scroll.
    T.near(bar.thumb:GetHeight(), 25, 0.01)
    stub.Advance(W.SCROLL.linger + 0.1)
    stub.RunOnUpdate(bar, 1)
    T.eq(bar:GetAlpha(), W.SCROLL.rest, "back to rest once the list sat still")
end)

T.test("scroll bar: never past the end, hover shows it, a short list has none", function()
    local W, sf, bar, child = scrollWorld(150)
    for _ = 1, 5 do sf:GetScript("OnMouseWheel")(sf, -1) end
    settle()
    T.eq(sf:GetVerticalScroll(), 50, "stops at the end")
    stub.Advance(5)
    sf.IsMouseOver = function() return true end
    stub.RunOnUpdate(bar, 1)
    T.eq(bar:GetAlpha(), 1, "the mouse over the list shows it")
    child:SetHeight(80)
    stub.RunOnUpdate(bar, 1)
    T.eq(sf:GetVerticalScroll(), 0, "back to the top")
    T.eq(bar:GetAlpha(), 0, "nothing to scroll: no bar")
    T.falsy(bar:IsMouseEnabled())
end)

T.test("scroll bar: a refill mid-glide wins, motion off steps", function()
    local W, sf, bar = scrollWorld(400)
    sf:GetScript("OnMouseWheel")(sf, -2)
    bar.Stop()
    sf:SetVerticalScroll(0)
    settle()
    T.eq(sf:GetVerticalScroll(), 0, "the glide stopped")
    DaylightUI.DB.General().motion = false
    sf:GetScript("OnMouseWheel")(sf, -1)
    T.eq(sf:GetVerticalScroll(), W.SCROLL.step, "at once")
end)

T.test("menu: several ticks, headings, and staying open for switches", function()
    local DUI = stub.Load({})
    local W = DUI.Widgets
    local on = { a = true, b = false }
    local picked = {}
    local owner = CreateFrame("Button", nil, UIParent)
    owner:SetSize(20, 20)
    W.OpenMenu(owner, { "head", "a", "b" }, { head = "Things", a = "Apple", b = "Pear" }, nil,
        function(k) picked[#picked + 1] = k; on[k] = not on[k] end, nil,
        { checked = function(k) return on[k] == true end, titles = { head = true }, keepOpen = true })
    T.falsy(W.MenuRow(1).check:IsShown(), "a heading has no tick")
    T.truthy(W.MenuRow(2).check:IsShown(), "Apple on")
    T.falsy(W.MenuRow(3).check:IsShown(), "Pear off")
    W.MenuRow(1):Click()
    T.eq(#picked, 0, "a heading does nothing")
    W.MenuRow(3):Click()
    T.eq(picked[1], "b")
    T.truthy(W.menuOwner, "still open")
    T.truthy(W.MenuRow(3).check:IsShown(), "its tick follows")
    W.CloseMenu()
end)

T.test("map button: round, the accent under the mouse, clicks", function()
    local DUI = stub.Load({})
    local W = DUI.Widgets
    local n = 0
    local b = W.MapButton(UIParent, "ui-search.png", function() n = n + 1 end)
    T.eq(b:GetWidth(), W.MAP_BUTTON)
    b:GetScript("OnEnter")(b)
    local r = DUI.Style.Accent()
    T.eq(b.icon.__vertex[1], r, "the accent under the mouse")
    b:GetScript("OnClick")(b, "LeftButton")
    T.eq(n, 1)
end)

-- The game's AddOns settings page holds one button of ours: our own
-- W.Button (no game template dressed after), opening the window.
T.test("the game's AddOns settings: our own button opens the options", function()
    local cat
    local DUI = stub.Load({ module = true, before = function()
        _G.Settings = {
            RegisterCanvasLayoutCategory = function(f, name) return { frame = f, name = name } end,
            RegisterAddOnCategory = function(c) cat = c end,
        }
    end })
    _G.Settings = nil
    T.truthy(cat, "registered")
    T.eq(cat.name, "DaylightUI")
    local b = ({ cat.frame:GetChildren() })[1]
    T.truthy(b and b.SetActive, "a W.Button")
    T.falsy(b.__template, "no game template under it")
    T.eq(b.text:GetText(), "Open DaylightUI options")
    b:Click()
    T.truthy(DUI.OptionsPanel.IsShown())
end)
