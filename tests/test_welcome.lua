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
