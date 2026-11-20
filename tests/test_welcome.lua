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
    T.eq(DUI.InstallerUI.Frame().next.text:GetText(), "Finish")
    DUI.Welcome.Next()
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
    DUI.Welcome.Next()
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "socket")
    T.eq(DUI:Get("UnitFrames", "focus.portraitLook"), "classic", "no portrait there, so nothing changed")
    T.eq(DUI:Get("Tooltip", "style"), "simple")

    DUI = returning()
    DUI.Welcome.Show()
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.classic)
    DUI.Welcome.Next()
    press(DUI.Welcome.Page().picker.cards.simple)
    DUI.Welcome.Next()
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

T.test("tour: the portrait and tooltip looks pick through the draft, with both drawn", function()
    local DUI = stub.Load({ module = true, tooltip = true })
    local D, Steps = DUI.InstallerDraft, DUI.InstallerSteps
    D.Begin()
    local frames = Steps.Build("frames", UIParent, 500)
    local picker = frames.pickers.portraitLook
    T.truthy(picker, "the Frames page has the portrait look")
    picker.Refresh()
    T.truthy(picker.cards.socket.selected, "a new player starts on the new look")
    press(picker.cards.classic)
    T.eq(DUI:Get("UnitFrames", "player.portraitLook"), "classic")
    T.truthy(D.Picked("UnitFrames", "player.portraitLook"))
    local everyday = Steps.Build("everyday", UIParent, 500)
    picker = everyday.pickers.tooltipStyle
    T.truthy(picker, "the Everyday page has the tooltip look")
    picker.Refresh()
    local was = DUI:Get("Tooltip", "style")
    T.truthy(picker.cards[was].selected, "the setup's own look is picked")
    local other = was == "rich" and "simple" or "rich"
    press(picker.cards[other])
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
    T.eq(DUI.InstallerUI.Frame().next.text:GetText(), "Finish")
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "none", "not written yet")
    DUI.Welcome.Next()
    T.falsy(DUI.Welcome.Running())
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "above", "Class icons puts them above the name")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("welcome: an icon already placed keeps its spot; Names only turns it off", function()
    local DUI = returningWithPlates({ friendly = { classIcon = "before" } })
    local picker = throughToPlates(DUI)
    press(picker.cards.above)
    DUI.Welcome.Next()
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "before", "kept before the name")
    DUI = returningWithPlates({ friendly = { classIcon = "after" } })
    picker = throughToPlates(DUI)
    press(picker.cards.none)
    DUI.Welcome.Next()
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "none")
end)

T.test("tour: the Nameplates page has the class icons, picked through the draft", function()
    local DUI = stub.Load({ module = true, nameplates = true })
    local D = DUI.InstallerDraft
    D.Begin()
    local plates = DUI.InstallerSteps.Build("plates", UIParent, 500)
    local picker = plates.pickers.plateClassIcon
    T.truthy(picker, "the Nameplates page has the class icons")
    picker.Refresh()
    T.truthy(picker.cards.none.selected, "off to start")
    press(picker.cards.above)
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "above")
    T.truthy(D.Picked("Nameplates", "friendly.classIcon"))
    D.Revert()
    T.eq(DUI:Get("Nameplates", "friendly.classIcon"), "none", "closing the guide puts it back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
