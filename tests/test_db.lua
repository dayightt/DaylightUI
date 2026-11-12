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

T.test("panel backgrounds follow every window's opacity; one that looked different keeps its own, once", function()
    local DUI = stub.Load({ before = function()
        DaylightUIDB = { version = 2, profileData = {
            Mine = { modules = { Chat = { panelAlpha = 0.5 }, InfoPanel = { meter = { bgAlpha = 0.3 } } } },
            Light = { general = { windowAlpha = 0.6 }, modules = {} } } }
    end })
    local pd = DaylightUIDB.profileData
    T.eq(pd.Mine.modules.Chat.panelAlphaOwn, true, "chat at 0.5: keeps its own")
    T.isnil(pd.Mine.modules.InfoPanel.panelAlphaOwn, "the info panel looked like the windows: follows them")
    T.isnil(pd.Mine.modules.InfoPanel.meter.bgAlpha, "the meter's own is gone")
    T.eq(pd.Light.modules.Quests.boxAlphaOwn, true, "windows at 0.6, the quest box at 0.85: keeps 0.85")
    T.eq(pd.Light.modules.Buffs.settings.debuff.backgroundAlphaOwn, true)
    T.eq(pd.Mine.backs1, true)
    pd.Mine.modules.Chat.panelAlphaOwn = nil
    DUI.DB.Init()
    T.isnil(pd.Mine.modules.Chat.panelAlphaOwn, "only once")
    T.eq(DUI.Style.BackAlpha(false, 0.4), DUI:Get("general", "windowAlpha"), "off: every window's")
    T.eq(DUI.Style.BackAlpha(true, 0.4), 0.4, "on: its own")
end)
