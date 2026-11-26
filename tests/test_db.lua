local stub = require("stub")

T.test("a fresh install gets general defaults", function()
    local DUI = stub.Load()
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.borderPx, 8)
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.heavyBorder, true)
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.cornerPx, 6)
    T.eq(DUI:Get("general", "softness"), 0.15)
    T.eq(DUI:Get("general", "brightness"), 0.95)
end)

T.test("saved values survive and missing defaults are filled in", function()
    local DUI = stub.Load({ before = function() DaylightUIDB = { general = { softness = 0.5 } } end })
    T.eq(DUI:Get("general", "softness"), 0.5)
    T.eq(DUI:Get("general", "fontScale"), 1)
end)

T.test("modules enable at login with merged defaults", function()
    local DUI = stub.Load({ login = false })
    local seen
    DUI:RegisterModule("Demo", { defaults = { a = 1, nested = { b = 2 } }, OnEnable = function(_, db) seen = db end })
    T.isnil(seen, "not before login")
    stub.FireEvent("PLAYER_LOGIN")
    T.eq(seen.nested.b, 2)
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.Demo, seen, "lives in saved variables")
    T.truthy(DUI:GetModule("Demo").enabled)
end)

T.test("a module registered after login enables straight away", function()
    local DUI = stub.Load()
    local enabled = false
    DUI:RegisterModule("Late", { OnEnable = function() enabled = true end })
    T.truthy(enabled)
end)

T.test("duplicate module names are refused", function()
    local DUI = stub.Load()
    DUI:RegisterModule("X", {})
    T.errors(function() DUI:RegisterModule("X", {}) end)
end)

T.test("a failing OnEnable does not stop later modules", function()
    local DUI = stub.Load({ login = false })
    local second = false
    DUI:RegisterModule("Bad", { OnEnable = function() error("nope") end })
    DUI:RegisterModule("Good", { OnEnable = function() second = true end })
    stub.FireEvent("PLAYER_LOGIN")
    T.truthy(second)
    T.eq(#stub.errors, 1)
end)

T.test("dotted paths get and set nested values", function()
    local DUI = stub.Load()
    local t = {}
    DUI.DB.SetPath(t, "a.b.c", 5)
    T.eq(DUI.DB.GetPath(t, "a.b.c"), 5)
    T.isnil(DUI.DB.GetPath(t, "a.x.c"))
end)

T.test("Set on a module stores the value and calls OnSettingChanged", function()
    local DUI = stub.Load()
    local got
    DUI:RegisterModule("Demo", { defaults = { size = 1 }, OnSettingChanged = function(_, path, v) got = path .. "=" .. v end })
    T.truthy(DUI:Set("Demo", "size", 3))
    T.eq(DUI:Get("Demo", "size"), 3)
    T.eq(got, "size=3")
end)

T.test("a slider held down tells the module at a steady pace, ending on the last value", function()
    local DUI = stub.Load()
    local calls, last = 0, nil
    DUI:RegisterModule("Demo", { defaults = { size = 1 },
        OnSettingChanged = function(_, path, v) calls, last = calls + 1, v end })
    DUI.Options.sliderHeld = true
    for i = 1, 50 do DUI:Set("Demo", "size", i) end
    T.eq(DUI:Get("Demo", "size"), 50, "the value is stored at every step")
    T.eq(calls, 0, "the module isn't refreshed at every step")
    stub.RunTimers()
    T.eq(calls, 1, "once")
    T.eq(last, 50, "with the last value")
    DUI.Options.sliderHeld = false
    DUI:Set("Demo", "size", 7)
    T.eq(calls, 2, "released, it's at once again")
    T.eq(last, 7)
end)

T.test("a General slider held down repaints the style once, when it's let go", function()
    local DUI = stub.Load()
    local repaints = 0
    DUI.On("RepaintCore", function() repaints = repaints + 1 end)
    DUI.Options.sliderHeld = true
    for i = 1, 30 do DUI:Set("general", "borderPx", i % 5 + 1) end
    stub.RunTimers()
    T.eq(repaints, 0, "nothing while it's held")
    DUI.Options.sliderHeld = false
    DUI.FlushHeldStyle()
    stub.RunTimers()
    T.eq(repaints, 1, "one repaint for the whole drag")
    DUI:Set("general", "borderPx", 4)
    stub.RunTimers()
    T.eq(repaints, 2, "not held: next frame as before")
end)

T.test("Set in combat stores now and applies after combat", function()
    local DUI = stub.Load()
    local calls = 0
    DUI:RegisterModule("Demo", { defaults = { size = 1 }, OnSettingChanged = function() calls = calls + 1 end })
    stub.EnterCombat()
    DUI:Set("Demo", "size", 2)
    DUI:Set("Demo", "size", 3)
    T.eq(DUI:Get("Demo", "size"), 3)
    T.eq(calls, 0)
    stub.LeaveCombat()
    T.eq(calls, 1, "same key collapses to one call")
end)

T.test("Set on general notifies every enabled module of a style change", function()
    local DUI = stub.Load()
    local styled = 0
    DUI:RegisterModule("Demo", { OnStyleChanged = function() styled = styled + 1 end })
    DUI:Set("general", "softness", 0.3)
    stub.RunTimers()   -- the style repaints on the next frame
    T.eq(styled, 1)
end)

T.test("Get and Set on an unknown scope do nothing", function()
    local DUI = stub.Load()
    T.isnil(DUI:Get("Nope", "x"))
    T.falsy(DUI:Set("Nope", "x", 1))
end)

T.test("if the saved table is replaced, the next access re-initializes it", function()
    local DUI = stub.Load()
    local mod = DUI:RegisterModule("Demo", { defaults = { a = 1 } })
    DaylightUIDB = { general = { softness = 0.5 } }
    T.eq(DUI:Get("general", "softness"), 0.5)
    T.eq(DUI:Get("general", "fontScale"), 1)
    T.eq(mod.db, DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.Demo, "module db re-pointed")
    T.eq(mod.db.a, 1)
end)

T.test("logout strips values equal to their defaults", function()
    local DUI = stub.Load()
    DUI.Profiles.AddPreset("DPS/Tank")   -- installed: saved from now on
    DUI:RegisterModule("Demo", { defaults = { a = 1, nested = { b = 2 } } })
    DUI:Set("general", "softness", 0.5)
    stub.RunTimers()   -- the style repaints on the next frame
    DUI:Set("Demo", "a", 5)
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.softness, 0.5)
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.fontScale)
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.Demo.a, 5)
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.Demo.nested, "empty table removed")
end)

T.test("logout: other logout handlers run before the strip and still read every setting", function()
    local DUI = stub.Load()
    DUI.Profiles.AddPreset("DPS/Tank")
    DUI:RegisterModule("Demo", { defaults = { keep = true } })
    local seen
    DUI.RegisterEvent("PLAYER_LOGOUT", function() seen = DUI:Get("Demo", "keep") end)   -- came after the core's
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(seen, true, "the default was still there")
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].modules.Demo.keep, "and stripped after")
end)

T.test("a Korean or Chinese client gets the local font on once; other clients never", function()
    local real = _G.GetLocale
    for _, loc in ipairs({ "koKR", "zhCN", "zhTW" }) do
        _G.GetLocale = function() return loc end
        local DUI = stub.Load()
        T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.localFont, true, loc)
        T.truthy(DUI.DB.UseLocalFont())
    end
    for _, loc in ipairs({ "enUS", "deDE", "ruRU" }) do
        _G.GetLocale = function() return loc end
        local DUI = stub.Load()
        T.falsy(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.localFont, loc)
    end
    _G.GetLocale = real
end)

T.test("turning the local font off stays off; it does nothing on other clients", function()
    local real = _G.GetLocale
    _G.GetLocale = function() return "koKR" end
    local DUI = stub.Load()
    DUI:Set("general", "localFont", false)
    DUI.DB.Init()
    T.falsy(DUI.DB.General().localFont)
    _G.GetLocale = function() return "enUS" end
    DUI.DB.General().localFont = true
    T.falsy(DUI.DB.UseLocalFont())
    _G.GetLocale = real
end)

T.test("panel backgrounds that looked different from every window's keep their own look", function()
    local DUI = stub.Load({ before = function()
        DaylightUIDB = { version = 2, profileData = {
            Mine = { modules = { Chat = { panelAlpha = 0.5 }, InfoPanel = { meter = { bgAlpha = 0.3 } } } },
            Light = { general = { windowAlpha = 0.6 }, modules = {} } } }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(pd.Mine.backs1, true)
    DUI.DB.Fill(pd.Mine)
    DUI.DB.Fill(pd.Light)
    local chat = pd.Mine.modules.Chat
    T.eq(chat.frameStyle.global, false, "chat at 0.5: its own look")
    T.near(chat.frameStyle.windowAlpha, 0.5)
    T.isnil(chat.panelAlphaOwn, "the old switch is gone")
    T.isnil(chat.panelAlpha)
    T.truthy((pd.Mine.modules.InfoPanel.frameStyle or {}).global ~= false, "the info panel looked like the windows: global")
    T.isnil(pd.Mine.modules.InfoPanel.meter.bgAlpha, "the meter's own is gone")
    local box = pd.Light.modules.Quests.frameStyle
    T.eq(box.global, false, "windows at 0.6, the quest box at 0.85: keeps 0.85")
    T.near(box.windowAlpha, 0.85)
    T.eq(pd.Light.modules.Buffs.settings.debuff.frameStyle.global, false)
end)

T.test("old border and opacity settings move into each section's own look", function()
    local DUI = stub.Load()
    local p = { general = { borderPx = 4, shadowAlpha = 0.2 }, modules = {
        Bags = { windowAlphaOwn = true, windowAlpha = 0.4 },
        Book = { windowAlpha = 0.3 },   -- set, but never switched on
        Chat = { border = "flat", borderSize = 3 },
        InfoPanel = { panelBorder = false, map = { alphaOwn = true, alpha = 0.5 }, databar = { borderAlpha = 0.6 },
                      meters = { windows = { w3 = { kind = "meter", border = false } } } },
        Quests = { boxBorder = false },
        Tooltip = { borderPx = 0 },
        QoL = { lootFeedBorderColor = "quality", flightAlphaOwn = true, flightAlpha = 0.7 },
    } }
    DUI.DB.SectionLooks(p)
    local m = p.modules
    T.eq(m.Bags.frameStyle.global, false)
    T.near(m.Bags.frameStyle.windowAlpha, 0.4)
    T.eq(m.Bags.frameStyle.borderPx, 4, "the rest starts from the profile's own General")
    T.near(m.Bags.frameStyle.shadowAlpha, 0.2)
    T.isnil(m.Bags.windowAlphaOwn)
    T.isnil(m.Book.frameStyle, "a value that never showed changes nothing")
    T.isnil(m.Book.windowAlpha)
    T.eq(m.Chat.frameStyle.heavyBorder, false, "a flat chat border")
    T.eq(m.Chat.frameStyle.borderPx, 3)
    T.isnil(m.Chat.border)
    T.eq(m.InfoPanel.frameStyle.borderAlpha, 0, "no border = border opacity 0")
    T.isnil(m.InfoPanel.panelBorder)
    T.near(m.InfoPanel.map.frameStyle.windowAlpha, 0.5)
    T.eq(m.InfoPanel.map.frameStyle.borderAlpha, 0, "the map box took the panel's missing border, as before")
    T.near(m.InfoPanel.databar.frameStyle.borderAlpha, 0.6)
    T.isnil(m.InfoPanel.databar.frameStyle.heavyBorder, "the data bar's own design isn't copied from General")
    T.eq(m.InfoPanel.meters.windows.w3.frameStyle.borderAlpha, 0)
    T.eq(m.Quests.frameStyle.borderAlpha, 0)
    T.eq(m.Tooltip.frameStyle.borderAlpha, 0, "a 0 px tooltip border")
    T.eq(m.Tooltip.frameStyle.borderPx, 1)
    T.near(m.Tooltip.frameStyle.windowAlpha, 0.92)
    T.eq(m.QoL.lootFeedFrame.global, false, "a border color keeps the feed's own look")
    T.near(m.QoL.flightFrame.windowAlpha, 0.7)
    T.isnil(m.QoL.flightAlphaOwn)

    local before = DUI.DB.Copy(p)
    DUI.DB.SectionLooks(p)
    T.deq(p, before, "a second run changes nothing")
end)

T.test("a bar texture saved as the window color goes back to the window bar background", function()
    local DUI = stub.Load({ before = function()
        DaylightUIDB = { version = 2, profileData = { Mine = { general = { windowTint = "silk" }, modules = {} } } }
    end })
    T.eq(DUI:Get("general", "windowBack"), "silk", "the texture pick comes back")
    T.eq(DUI:Get("general", "windowTint"), "daylight", "the window color is the default again")
    local kept = { general = { windowTint = "class", windowBack = "glass" } }
    DUI.DB.WindowBackFix(kept)
    T.eq(kept.general.windowTint, "class", "a real color pick stays")
    T.eq(kept.general.windowBack, "glass")
end)

-- Rich is the tooltips' own default, so the options don't offer to "reset" a new profile to
-- Simple. Profiles from before Rich existed keep Simple, once.
T.test("tooltips default to Rich, existing profiles keep the look they had", function()
    local DUI = stub.Load({ tooltip = true, before = function()
        DaylightUIDB = { version = 2, profileData = {
            Old = { modules = { Tooltip = { textSize = 13 } } },
            NoTip = { modules = {} },
            Rich = { modules = { Tooltip = { style = "rich" } } } } }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(DUI:GetModule("Tooltip").defaults.style, "rich", "Rich is the default")
    T.eq(pd.Old.modules.Tooltip.style, "simple", "an existing profile keeps Simple")
    T.eq(pd.NoTip.modules.Tooltip.style, "simple", "even one that never loaded the tooltips")
    T.eq(pd.Rich.modules.Tooltip.style, "rich", "one already in Rich stays there")
    T.eq(pd.Old.tipStyle1, true)
    pd.Old.modules.Tooltip.style = nil
    DUI.DB.Init()
    T.isnil(pd.Old.modules.Tooltip.style, "only once")
end)

-- Proc Alerts came later: profiles from before start with them off (the welcome
-- offers them), once; new installs and new profiles have them on.
T.test("Proc Alerts start off in profiles from before them, on in new ones", function()
    local DUI = stub.Load({ procs = true, before = function()
        DaylightUIDB = { version = 2, profileData = {
            Old = { modules = { Tooltip = { textSize = 13 } } },
            On = { modules = { Procs = { enabled = true } } } } }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(pd.Old.modules.Procs.enabled, false, "an existing profile starts with them off")
    T.eq(pd.On.modules.Procs.enabled, true, "one switched on stays on")
    T.eq(pd.Old.procsOff1, true)
    pd.Old.modules.Procs.enabled = true
    DUI.DB.Init()
    T.eq(pd.Old.modules.Procs.enabled, true, "only once")
    DUI.Profiles.Create("Fresh")
    T.eq(pd.Fresh.procsOff1, true, "a new profile is marked")
end)

-- Nameplates sit lower by default now: profiles from before keep the old
-- height once, so no player's plates move; new installs and new profiles
-- start low.
T.test("nameplates keep their old height in old profiles, sit low in new ones", function()
    local DUI = stub.Load({ nameplates = true, before = function()
        DaylightUIDB = { version = 2, profileData = {
            Old = { modules = { Tooltip = { textSize = 13 } } },
            Moved = { modules = { Nameplates = { offsetY = 5 } } } } }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(pd.Old.modules.Nameplates.offsetY, 14, "an existing profile keeps the old height")
    T.eq(pd.Moved.modules.Nameplates.offsetY, 5, "a height picked by hand stays")
    pd.Old.modules.Nameplates.offsetY = nil
    DUI.DB.Init()
    T.isnil(pd.Old.modules.Nameplates.offsetY, "only once")
    DUI.Profiles.Create("Fresh")
    T.eq(pd.Fresh.plateLow1, true, "a new profile is marked")
    T.eq(DUI:Get("Nameplates", "offsetY") ~= nil, true)
end)

T.test("a fresh install starts with low nameplates", function()
    local DUI = stub.Load({ nameplates = true })
    local first = DaylightUIDB.profileData[DUI.DB.DEFAULT]
    T.eq(first.plateLow1, true)
    T.eq(DUI:Get("Nameplates", "offsetY"), -20)
    DUI.DB.Init()
    T.eq(DUI:Get("Nameplates", "offsetY"), -20, "still low on the next load")
end)

T.test("a fresh install starts with Proc Alerts on, and stays so on the next load", function()
    local DUI = stub.Load({ procs = true })
    local first = DaylightUIDB.profileData[DUI.DB.DEFAULT]
    T.eq(first.procsOff1, true)
    T.eq(DUI:Get("Procs", "enabled"), true)
    DUI.DB.Init()
    T.eq(DUI:Get("Procs", "enabled"), true, "not off on the next load")
    DUI.Profiles.Create("Blank", { general = {}, modules = {}, positions = {} })
    T.eq(DaylightUIDB.profileData.Blank.modules.Procs.enabled, true, "a shared profile starts on too")
end)

T.test("a fresh install and a new profile start in Rich tooltips with nothing saved", function()
    local DUI = stub.Load({ tooltip = true })
    local first = DaylightUIDB.profileData[DUI.DB.DEFAULT]
    T.eq(first.tipStyle1, true, "marked as already past the one-time step")
    T.eq(DUI:Get("Tooltip", "style"), "rich")
    DUI.DB.Init()
    T.eq(DUI:Get("Tooltip", "style"), "rich", "and not Simple on the next load either")
    DUI.Profiles.Create("Fresh")
    local p = DaylightUIDB.profileData.Fresh
    T.eq(p.tipStyle1, true, "a new profile is marked too")
    T.eq(p.modules.Tooltip.style, "rich")
end)

-- The short chat tags start from the player's language on a new profile; a profile that existed
-- before keeps the English letters, once.
T.test("existing profiles keep the English chat tag letters, new ones start in the player's language", function()
    local DUI = stub.Load({ before = function()
        DaylightUIDB = { version = 2, profileData = {
            Old = { modules = { Chat = { panelShown = false } } },
            NoChat = { modules = {} },
            Picked = { modules = { Chat = { tagLetters = "native" } } } } }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(pd.Old.modules.Chat.tagLetters, "english", "an existing profile keeps today's letters")
    T.eq(pd.NoChat.modules.Chat.tagLetters, "english", "even one that never loaded the chat")
    T.eq(pd.Picked.modules.Chat.tagLetters, "native", "a pick of theirs is left alone")
    T.eq(pd.Old.tagLetters1, true)
    pd.Old.modules.Chat.tagLetters = nil
    DUI.DB.Init()
    T.isnil(pd.Old.modules.Chat.tagLetters, "only once")
end)

T.test("a fresh install and a new profile are not set to English chat tags", function()
    local DUI = stub.Load()
    local pd = DaylightUIDB.profileData
    local first = pd[DUI.DB.DEFAULT]
    T.eq(first.tagLetters1, true, "marked as already past the one-time step")
    T.isnil(type(first.modules.Chat) == "table" and first.modules.Chat.tagLetters or nil, "no English forced")
    DUI.DB.Init()
    T.isnil(type(first.modules.Chat) == "table" and first.modules.Chat.tagLetters or nil, "and not on the next load either")
    DUI.Profiles.Create("Fresh")
    local p = DaylightUIDB.profileData.Fresh
    T.truthy(p, "a profile is made")
    T.eq(p.tagLetters1, true, "a new profile is marked too")
end)

T.test("bar ends: one switch for both ends is split so every end looks as it did", function()
    stub.Load({ before = function()
        DaylightUIDB = { version = 2, profileData = {
            Off = { modules = { InfoPanel = { databar = { angled = false } }, QoL = { lootFeedSlant = false, lootFeedSlantSide = "left" } } },
            Left = { modules = { QoL = { lootFeedSlantSide = "left" } } },
            Right = { modules = { QoL = { lootFeedSlantSide = "right" } } },
            Plain = { modules = { InfoPanel = { databar = { height = 30 } } } } } }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(pd.Off.modules.InfoPanel.databar.angledRight, false, "the data bar's right end straight as before")
    T.eq(pd.Off.modules.QoL.lootFeedLeft, false); T.eq(pd.Off.modules.QoL.lootFeedRight, false)
    T.isnil(pd.Off.modules.QoL.lootFeedSlant, "the old keys go")
    T.isnil(pd.Off.modules.QoL.lootFeedSlantSide)
    T.isnil(pd.Left.modules.QoL.lootFeedLeft, "angled on the left: the default")
    T.eq(pd.Left.modules.QoL.lootFeedRight, false)
    T.eq(pd.Right.modules.QoL.lootFeedLeft, false)
    T.isnil(pd.Right.modules.QoL.lootFeedRight)
    T.isnil(pd.Plain.modules.InfoPanel.databar.angledRight, "untouched: nothing written")
    T.eq(pd.Plain.barEnds1, true)
end)
