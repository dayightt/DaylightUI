local stub = require("stub")

-- The 2.0 welcome (Welcome.lua): once per account for a player who had
-- Daylight UI before, in the setup guide's window: what's new, then the
-- portrait and tooltip looks side by side (InstallerLooks.lua), written only
-- at Finish. The tour's pages carry the same two choices.

local function press(b) b:GetScript("OnClick")(b, "LeftButton") end
-- The X: the window fades out, then tells the welcome.
local function closeWindow()
    press(DaylightUIInstaller.close)
    local g = DaylightUIInstaller.__duiMotion and DaylightUIInstaller.__duiMotion.vanish
    local fn = g and g:GetScript("OnFinished")
    if fn then fn(g) end
end

-- A player updating from 1.9.6: the unit frames' upgrade kept the classic ring.
local function returning(uf)
    local DUI = stub.Load({ module = true, tooltip = true, before = function()
        local mods = { UnitFrames = { groupFrames = 20 } }
        for k, v in pairs(uf or {}) do mods.UnitFrames[k] = v end
        DaylightUIDB = { version = "1.9.6", notesSeen = "1.9.6", installerSeen = true, barFxAsked = true,
                         profileData = { ["DPS/Tank"] = { general = {}, positions = {}, modules = mods } } }
    end })
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    stub.Dismiss()
    return DUI
end

local function nextShown(DUI) return DUI.InstallerUI.Frame().next:IsShown() end
-- Past the last pick: the bar animations slide comes last and needs none.
local function toEnd(DUI)
    for _ = 1, 5 do
        if not DUI.Welcome.Running() then return end
        DUI.Welcome.Next()
    end
end

T.test("welcome: a returning player gets it at login, and the portrait question stays away", function()
    local DUI = returning()
    stub.RunTimers()
    T.truthy(DUI.Welcome.Running(), "shown")
    T.truthy(DUI.InstallerUI.IsShown())
    T.eq(DUI.Welcome.Slide(), "news")
    T.isnil(stub.Asked(), "no second question on top of it")
    T.truthy(DUI.DB.Root().portraitLookAsked, "the welcome asks about portraits itself")
    local page = DUI.Welcome.Page()
    T.eq(#page.cards, #DUI.Welcome.NEWS)
    T.truthy(page.go.fill:GetNumMaskTextures() >= 2, "the button's fill is cut to both angled ends")
    -- Nothing flashes in whole first: each piece is hidden until its turn,
    -- then rises in.
    do
        DUI.Welcome.Go(1)
        for _, piece in ipairs({ page.greet, page.cards[1], page.cards[#page.cards], page.go }) do
            T.eq(piece:GetAlpha(), 0, "hidden until its turn")
        end
        local d = DUI.Win.Feel.Driver()
        for _ = 1, 60 do
            local tick = d and d:GetScript("OnUpdate")
            if tick then tick(d, 0.05) end
        end
        stub.RunTimers()
        T.eq(page.cards[#page.cards]:GetAlpha(), 1, "then risen in")
    end
    T.truthy(string.find(page.greet:GetText(), "Welcome to Daylight UI", 1, true))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: each look must be picked, both are drawn, and nothing is written before Finish", function()
    local DUI = returning()
    DUI.Welcome.Show()
    press(DUI.Welcome.Page().go)
    T.eq(DUI.Welcome.Slide(), "portraitLook")
    T.falsy(nextShown(DUI), "Next waits for a pick")
    DUI.Welcome.Next()
    T.eq(DUI.Welcome.Slide(), "portraitLook", "and can't be skipped")
    local picker = DUI.Welcome.Page().picker
    T.truthy(picker.box.frames.socket.socketOn, "one sample is set into its frame")
    T.falsy(picker.box.frames.classic.socketOn, "the other is the classic ring")
    press(picker.cards.socket)
    T.truthy(nextShown(DUI), "picked: Next")
    T.truthy(picker.cards.socket.selected)
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic", "not written yet")
    DUI.Welcome.Next()
    T.eq(DUI.Welcome.Slide(), "tooltipStyle")
    picker = DUI.Welcome.Page().picker
    -- The pair rises as one piece: nothing inside it (a card, a shrunk
    -- drawing, a name) slides on its own, so nothing lands out of step.
    picker.Play()
    local function glides(r) return r.__feelAt ~= nil end
    T.truthy(glides(picker), "the pair rises")
    for _, k in ipairs({ "rich", "simple" }) do
        T.falsy(glides(picker.cards[k]), k .. "'s card doesn't slide on its own")
        T.falsy(glides(picker.box.cards[k].wrap), k .. "'s drawing doesn't either")
        T.falsy(glides(picker.box.names[k]), k .. "'s name doesn't either")
    end
    local rich = picker.box.cards.rich.card
    T.truthy(DUI:GetModule("Tooltip").ns.RichPanel.Get(rich):IsShown(), "the rich card is drawn by the card's own code")
    T.truthy(#picker.box.cards.simple.card.lines > 4, "the simple one has the game's lines")
    press(picker.cards.rich)
    T.truthy(nextShown(DUI), "picked: Next")
    toEnd(DUI)
    T.falsy(DUI.Welcome.Running(), "done")
    for _, id in ipairs({ "player", "target", "focus", "party" }) do
        T.eq(DUI:Get("UnitFrames", id .. ".portraitLook"), "socket", id)
    end
    T.eq(DUI:Get("Tooltip", "style"), "rich")
    T.eq(DUI.DB.Root().welcome, DUI.Welcome.VERSION)
    T.falsy(DUI.Welcome.Due(), "once per account")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: the new portraits leave a frame with its portrait off alone; the old looks keep everything", function()
    local DUI = returning({ focus = { portrait = "none" } })
    DUI.Welcome.Show()
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.socket)
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.simple)
    toEnd(DUI)
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "socket")
    T.eq(DUI:Get("UnitFrames", "focus.portraitLook"), "classic", "no portrait there, so nothing changed")
    T.eq(DUI:Get("Tooltip", "style"), "simple")

    DUI = returning()
    DUI.Welcome.Show()
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.classic)
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.simple)
    toEnd(DUI)
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic")
    T.falsy(DUI.Welcome.Due())
end)

T.test("welcome: closing it early writes nothing and it comes back; /dui welcome opens it", function()
    local DUI = returning()
    DUI.Welcome.Show()
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.socket)
    closeWindow()
    T.falsy(DUI.Welcome.Running())
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic")
    T.truthy(DUI.Welcome.Due(), "asks again next time")
    SlashCmdList.DAYLIGHTUI("welcome")
    T.truthy(DUI.Welcome.Running())
    T.eq(DUI.Welcome.Slide(), "news", "from the start")
end)

T.test("welcome: never on a brand-new account, never in a fight", function()
    local DUI = stub.Load({ module = true, tooltip = true })
    stub.RunTimers()
    T.falsy(DUI.Welcome.Running())
    T.eq(DUI.DB.Root().welcome, DUI.Welcome.VERSION, "a first install never sees it")
    DUI = returning()
    stub.EnterCombat()
    DUI.Welcome.Show()
    T.falsy(DUI.InstallerUI.IsShown(), "not in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(DUI.Welcome.Running(), "once it ends")
end)

T.test("guide: the portrait and tooltip questions pick through the draft, with both looks drawn", function()
    local DUI = stub.Load({ module = true, tooltip = true })
    stub.RunTimers()
    local I, D = DUI.Installer, DUI.InstallerDraft
    if not I.flow then I.Show() end
    I.Start("tour")
    local q = I.QuestionById("portrait")
    T.truthy(q, "the portrait question")
    T.eq(I.Answer(q), "socket", "a new player starts on the new look")
    I.Go("q:portrait")
    T.truthy(I.pages.duel.span, "both looks drawn across the two columns")
    I.Pick(q, "classic")
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic")
    T.truthy(D.Picked("UnitFrames", "player.portraitLook"))
    q = I.QuestionById("tooltip")
    local was = I.Answer(q)
    local other = was == "rich" and "simple" or "rich"
    I.Pick(q, other)
    T.eq(DUI:Get("Tooltip", "style"), other)
    T.truthy(D.Picked("Tooltip", "style"))
    D.Revert()
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "socket", "closing the guide puts it back")
    T.eq(DUI:Get("Tooltip", "style"), was)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player updating from 1.9.6 with the nameplates on too.
local function returningWithPlates(plates)
    local DUI = stub.Load({ module = true, tooltip = true, nameplates = true, before = function()
        DaylightUIDB = { version = "1.9.6", notesSeen = "1.9.6", installerSeen = true, barFxAsked = true,
                         profileData = { ["DPS/Tank"] = { general = {}, positions = {},
                             modules = { UnitFrames = { groupFrames = 20 }, Nameplates = plates } } } }
    end })
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    stub.Dismiss()
    return DUI
end

local function throughToPlates(DUI)
    DUI.Welcome.Show()
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.classic)
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.simple)
    DUI.Welcome.Next()
    T.eq(DUI.Welcome.Slide(), "plateClassIcon", "a third pick: class icons on friendly plates")
    return DUI.Welcome.Page().picker
end

T.test("welcome: class icons on friendly nameplates, both drawn, picked like the others", function()
    local DUI = returningWithPlates()
    local picker = throughToPlates(DUI)
    local crowd = picker.box.frames
    T.truthy(crowd.above.people[1].icon:IsShown(), "one crowd has the icons")
    local _, over, at = crowd.above.people[1].icon:GetPoint(1)
    T.eq(over, crowd.above.people[1].name, "each over its name")
    T.eq(at, "TOP", "above it")
    T.falsy(crowd.none.people[1].icon:IsShown(), "the other is names only")
    T.falsy(nextShown(DUI), "Next waits for a pick")
    press(picker.cards.above)
    T.truthy(nextShown(DUI), "picked: Next")
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "none", "not written yet")
    toEnd(DUI)
    T.falsy(DUI.Welcome.Running())
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "above", "Class icons puts them above the name")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: an icon already placed keeps its spot; Names only turns it off", function()
    local DUI = returningWithPlates({ friendly = { classIcon = "before" } })
    local picker = throughToPlates(DUI)
    press(picker.cards.above)
    toEnd(DUI)
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "before", "kept before the name")
    DUI = returningWithPlates({ friendly = { classIcon = "after" } })
    picker = throughToPlates(DUI)
    press(picker.cards.none)
    toEnd(DUI)
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "none")
end)

T.test("guide: the class icons question picks through the draft", function()
    local DUI = stub.Load({ module = true, nameplates = true })
    stub.RunTimers()
    local I, D = DUI.Installer, DUI.InstallerDraft
    if not I.flow then I.Show() end
    I.Start("tour")
    local q = I.QuestionById("plateIcons")
    T.truthy(q, "the class icons question")
    T.eq(I.Answer(q), "none", "off to start")
    I.Pick(q, "above")
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "above")
    T.truthy(D.Picked("Nameplates", "friendly.classIcon"))
    D.Revert()
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "none", "closing the guide puts it back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Proc Alerts came after the 2.0 welcome. An account that saw it (welcome = 2)
-- updates with its profile from before: Proc Alerts start off there, and the
-- welcome comes back with only their slide.
local function sawWelcome(opts)
    opts = opts or {}
    local DUI = stub.Load({ module = true, tooltip = true, procs = opts.procs ~= false, before = function()
        stub.SetUnits({ player = { name = "Me", class = opts.class or "WARRIOR", isPlayer = true } })
        DaylightUIDB = { version = "2.2.7", notesSeen = "2.2.7", installerSeen = true, barFxAsked = true,
                         portraitLookAsked = true, welcome = opts.welcome or 2,
                         profileData = { ["DPS/Tank"] = { general = {}, positions = {},
                             modules = { UnitFrames = { groupFrames = 20 }, Procs = opts.procsSaved } } } }
    end })
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    stub.Dismiss()
    return DUI
end

T.test("welcome: after the 2.0 welcome, an update brings Proc Alerts first, with them off until picked", function()
    local DUI = sawWelcome()
    T.eq(DUI:Get("Procs", "enabled"), false, "a profile from before starts with Proc Alerts off")
    T.truthy(DUI.Welcome.Due(), "the welcome is due again")
    stub.RunTimers()
    T.truthy(DUI.Welcome.Running(), "shown at login")
    T.eq(#DUI.Welcome.Slides(2), 2, "Proc Alerts, then the bar animations")
    T.eq(DUI.Welcome.Slide(), "procAlerts", "no news, no looks picked before")
    T.isnil(stub.Asked(), "no second question on top of it")
    local picker = DUI.Welcome.Page().picker
    local box = picker.box
    T.eq(box.stages.on.portrait.__portraitUnit, "player", "your portrait in the On card")
    T.eq(box.stages.off.portrait.__portraitUnit, "player", "and in the Off card")
    local flare = box.stages.on.flare
    T.truthy(flare and flare.key, "a flare in the On card")
    T.eq(DUI:GetModule("Procs").ns.Data.BY[flare.key].class, "WARRIOR", "one of your class's procs")
    T.truthy(flare.parts[1].tex:GetTexture() ~= nil, "drawn")
    T.isnil(box.stages.off.flare, "none in the Off card")
    T.falsy(DUI.InstallerUI.Frame().back:IsShown(), "no Back on the only slide")
    T.falsy(nextShown(DUI), "Next waits for a pick")
    T.truthy(picker.cards.on.tag and picker.cards.on.tag:IsShown(), "On wears the New tag")
    press(picker.cards.on)
    T.truthy(nextShown(DUI), "picked: Next")
    T.eq(DUI:Get("Procs", "enabled"), false, "not written yet")
    toEnd(DUI)
    T.falsy(DUI.Welcome.Running(), "done")
    T.eq(DUI:Get("Procs", "enabled"), true, "On turns them on")
    T.eq(DUI.DB.Root().welcome, DUI.Welcome.VERSION)
    T.falsy(DUI.Welcome.Due(), "once per account")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: Off keeps Proc Alerts off; closing it early writes nothing and asks again", function()
    local DUI = sawWelcome()
    DUI.Welcome.Show(2)
    press(DUI.Welcome.Page().picker.cards.on)
    closeWindow()
    T.eq(DUI:Get("Procs", "enabled"), false, "nothing written")
    T.truthy(DUI.Welcome.Due(), "asks again next time")
    DUI.Welcome.Show(2)
    press(DUI.Welcome.Page().picker.cards.off)
    toEnd(DUI)
    T.eq(DUI:Get("Procs", "enabled"), false, "Off keeps them off")
    T.falsy(DUI.Welcome.Due())
    -- /dui welcome shows everything again, news first, the bar animations last.
    SlashCmdList.DAYLIGHTUI("welcome")
    T.eq(DUI.Welcome.Slide(), "news")
    local list = DUI.Welcome.Slides()
    T.eq(list[#list - 1], "procAlerts")
    T.eq(list[#list], "barFx")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: an update from before 2.0 gets the news, every look, then Proc Alerts", function()
    local DUI = sawWelcome({ welcome = 0 })
    stub.RunTimers()
    T.eq(DUI.Welcome.Slide(), "news")
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.classic)
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.simple)
    DUI.Welcome.Next()
    T.eq(DUI.Welcome.Slide(), "procAlerts")
    T.truthy(DUI.InstallerUI.Frame().back:IsShown(), "Back to the looks")
    press(DUI.Welcome.Page().picker.cards.on)
    toEnd(DUI)
    T.falsy(DUI.Welcome.Running())
    T.eq(DUI:Get("Procs", "enabled"), true)
    T.eq(DUI:Get("Tooltip", "style"), "simple")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: with Proc Alerts switched off in the AddOns list, only the bar animations come after the 2.0 welcome", function()
    local DUI = sawWelcome({ procs = false })
    stub.RunTimers()
    T.eq(DUI.Welcome.Slide(), "barFx", "no Proc Alerts slide")
    T.eq(#DUI.Welcome.Slides(2), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: a profile that already had Proc Alerts switched on keeps them on", function()
    local DUI = sawWelcome({ procsSaved = { enabled = true } })
    T.eq(DUI:Get("Procs", "enabled"), true)
    stub.RunTimers()
    local picker = DUI.Welcome.Page().picker
    T.falsy(picker.cards.off.selected, "nothing picked for them")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("guide: Make it mine asks about Proc Alerts, both drawn, picked through the draft", function()
    local DUI = stub.Load({ module = true, procs = true, before = function()
        stub.SetUnits({ player = { name = "Me", class = "MAGE", isPlayer = true } })
    end })
    stub.RunTimers()
    local I, D = DUI.Installer, DUI.InstallerDraft
    if not I.flow then I.Show() end
    I.Start("tour")
    local q = I.QuestionById("procs")
    T.truthy(q, "the Proc Alerts question")
    T.eq(q.part, "Proc Alerts", "on a page of its own")
    T.eq(I.Answer(q), "on", "a new player starts with them on")
    I.Go("q:procs")
    local box = I.pages.duel.span
    T.truthy(box, "both looks drawn across the two columns")
    T.truthy(box.stages.on.flare.parts[1].tex:GetTexture() ~= nil, "a flare lit in the On look")
    T.eq(DUI:GetModule("Procs").ns.Data.BY[box.stages.on.flare.key].class, "MAGE", "one of your class's")
    I.Pick(q, "off")
    T.eq(DUI:Get("Procs", "enabled"), false)
    T.truthy(D.Picked("Procs", "enabled"))
    D.Revert()
    T.eq(DUI:Get("Procs", "enabled"), true, "closing the guide puts it back")
    I.Start("quick", "DPS/Tank")
    T.isnil(I.QuestionById("procs"), "Quick setup leaves it on without asking")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("guide: no Proc Alerts question while the module is switched off", function()
    local DUI = stub.Load({ module = true })
    stub.RunTimers()
    local I = DUI.Installer
    if not I.flow then I.Show() end
    I.Start("tour")
    T.isnil(I.QuestionById("procs"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("chrome: a plaque is as wide as its words and their padding, and spaced capitals skip other alphabets", function()
    local DUI = returning()
    local Chrome = DUI.InstallerChrome
    local p = Chrome.Plaque(UIParent)
    p.Set(Chrome.Spaced("First light"))
    T.eq(p:GetHeight(), 34)
    T.eq(p:GetWidth(), math.ceil(p.text:GetStringWidth()) + 2 * 44)
    T.eq(Chrome.Spaced("ab c"), "A B   C")
    T.eq(Chrome.Spaced("привет"), DUI.Style.Upper("привет"), "left alone outside the Latin alphabet")
    local t = Chrome.Title(UIParent)
    t.Set("Good evening")
    T.eq(t.ruleL:GetWidth(), 200)
    T.eq(DUI.InstallerUI.SHOW_W, 900); T.eq(DUI.InstallerUI.SHOW_H, 625)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The bar animations that came after the last welcome (Welcome.BAR_STYLES):
-- an account that saw it (welcome = 3) gets one slide showing each of them
-- moving on a sample health bar, and where to pick one. Nothing to pick there.
local function sawProcs(opts)
    opts = opts or {}
    local DUI = stub.Load({ module = opts.frames ~= false, tooltip = true, procs = true, before = function()
        stub.SetUnits({ player = { name = "Me", class = "PRIEST", isPlayer = true } })
        DaylightUIDB = { version = "2.3.0", notesSeen = "2.3.0", installerSeen = true, barFxAsked = true,
                         portraitLookAsked = true, welcome = opts.welcome or 3,
                         profileData = { ["DPS/Tank"] = { general = {}, positions = {},
                             modules = { UnitFrames = { groupFrames = 20 }, Procs = { enabled = true } } } } }
    end })
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    stub.Dismiss()
    return DUI
end

T.test("welcome: an update shows each new bar animation moving in your accent, and where to pick one", function()
    local DUI = sawProcs()
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.8, 0.4 })
    local before = DUI:Get("UnitFrames", "player.barFx.health.style")
    T.truthy(DUI.Welcome.Due(), "due after the update")
    stub.RunTimers()
    T.truthy(DUI.Welcome.Running(), "shown at login")
    T.eq(DUI.Welcome.Slide(), "barFx", "only the new slide")
    local page = DUI.Welcome.Page()
    local shown = DUI.Welcome.BarStyles()
    T.truthy(#shown >= 4, "Daybreak and the three pixel styles at least")
    T.eq(#page.cards, #shown, "a card for each one")
    for i, key in ipairs(shown) do
        local c = page.cards[i]
        T.eq(DUI.BarFx.StyleOf(c.sample.bars[1].bar), key, "each card's bar wears its own animation: " .. key)
        T.truthy(c.title:GetText() ~= nil and c.title:GetText() ~= "", "named")
        T.truthy(c.text:GetText() ~= nil and c.text:GetText() ~= "", "and a line about it")
        T.falsy(c:IsMouseEnabled(), "nothing to click")
        local lo = DUI.Style.FillColors(c.sample.bars[1].bar:GetStatusBarTexture())
        T.truthy(lo and math.abs(lo[1] - 0.2) < 0.01 and math.abs(lo[2] - 0.8) < 0.01, "filled with your accent: " .. key)
    end
    local frame = DUI.InstallerUI.Frame()
    T.truthy(frame.later:IsShown(), "a link to where they're picked")
    T.truthy(string.find(frame.later.text:GetText() or "", "Bars tab", 1, true), frame.later.text:GetText())
    press(frame.later)
    local Panel = DUI.OptionsPanel
    T.truthy(Panel.IsShown and Panel.IsShown() or DaylightUIOptions and DaylightUIOptions:IsShown(), "the link opens the options")
    T.eq(frame.next.text:GetText(), "Finish", "no pick needed")
    DUI.Welcome.Next()
    T.falsy(DUI.Welcome.Running(), "done")
    T.eq(DUI:Get("UnitFrames", "player.barFx.health.style"), before, "nothing written")
    T.eq(DUI.DB.Root().welcome, DUI.Welcome.VERSION)
    T.falsy(DUI.Welcome.Due(), "once per account")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: the bar animations come after Proc Alerts for an account that missed both", function()
    local DUI = sawProcs({ welcome = 2 })
    stub.RunTimers()
    T.eq(DUI.Welcome.Slide(), "procAlerts")
    press(DUI.Welcome.Page().picker.cards.on)
    T.eq(DUI.InstallerUI.Frame().next.text:GetText(), NEXT or "Next")
    DUI.Welcome.Next()
    T.eq(DUI.Welcome.Slide(), "barFx")
    T.truthy(DUI.InstallerUI.Frame().back:IsShown(), "Back to Proc Alerts")
    DUI.Welcome.Next()
    T.falsy(DUI.Welcome.Running())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: with the unit frames switched off, no bar animations slide", function()
    local DUI = sawProcs({ frames = false })
    stub.RunTimers()
    T.falsy(DUI.Welcome.Running(), "nothing to show")
    T.eq(DUI.DB.Root().welcome, DUI.Welcome.VERSION, "and nothing left due")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: closing the bar animations early brings them back; /dui whatsnew opens them", function()
    local DUI = sawProcs()
    stub.RunTimers()
    closeWindow()
    T.truthy(DUI.Welcome.Due(), "asks again next login")
    SlashCmdList.DAYLIGHTUI("whatsnew")
    T.eq(DUI.Welcome.Slide(), "barFx", "the command opens just the newest slide")
    DUI.Welcome.Next()
    T.falsy(DUI.Welcome.Due())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("guide: the spell costs question starts off and picks through the draft", function()
    local DUI = stub.Load({ module = true, actionbars = true })
    stub.RunTimers()
    local I, D = DUI.Installer, DUI.InstallerDraft
    if not I.flow then I.Show() end
    I.Start("tour")
    local q = I.QuestionById("barCosts")
    T.truthy(q, "the spell costs question")
    T.eq(q.look, "spellCosts")
    T.eq(I.Answer(q), "off", "off by default")
    -- Its drawing: both looks, the costs only on the first.
    local box = DUI.InstallerLooks.KINDS.spellCosts.box(UIParent)
    box.Refresh(460)
    T.truthy(box.frames.on and box.frames.off, "a strip of buttons for each look")
    T.truthy(#box.frames.on.costs > 0, "costs drawn on the first")
    T.eq(#box.frames.off.costs, 0, "none on the second")
    I.Pick(q, "on")
    T.eq(DUI:Get("ActionBars", "look.costs"), true)
    T.truthy(D.Picked("ActionBars", "look.costs"))
    D.Revert()
    T.eq(DUI:Get("ActionBars", "look.costs"), false, "closing the guide puts it back")
    T.falsy(tContains(DUI.Welcome.CHOICES, "spellCosts"), "no welcome slide: it stays off for everyone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
