local stub = require("stub")

-- DaylightUI.API 1.3: plugins add settings to Daylight UI's modules (me.AddDefaults),
-- saved with Daylight UI's and kept while the plugin is off.

T.test("api defaults: added before the module turns on, read like any setting", function()
    stub.Load({ module = true, login = false })
    local DUI = DaylightUI
    T.eq(DUI.API.For("Neon").AddDefaults("UnitFrames", { neonGlow = 0.5, neon = { color = { 1, 0, 1 } } }), true)
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "neonGlow"), 0.5)
    T.eq(DUI:Get("UnitFrames", "neon.color")[2], 0)
    T.eq(DUI.DB.PluginKeys().UnitFrames.neonGlow, "Neon", "its owner kept")
end)

T.test("api defaults: added after the module is on, merged at once", function()
    stub.Load({ module = true })
    local DUI = DaylightUI
    T.eq(DUI.API.For("Neon").AddDefaults("UnitFrames", { neonGlow = 0.25 }), true)
    T.eq(DUI:Get("UnitFrames", "neonGlow"), 0.25)
end)

T.test("api defaults: a key Daylight UI already has is refused, nothing changed", function()
    stub.Load({ module = true })
    local DUI = DaylightUI
    local before = DUI:Get("UnitFrames", "player.width")
    T.eq(DUI.API.For("Neon").AddDefaults("UnitFrames", { player = { width = 999 } }), false)
    T.eq(DUI:Get("UnitFrames", "player.width"), before)
    local n = 0
    for _, m in ipairs(stub.chat) do if string.find(m, "Neon", 1, true) then n = n + 1 end end
    T.eq(n, 1, "one line")
end)

T.test("api defaults: a plugin's saved setting outlives the plugin being off", function()
    stub.Load({ module = true })
    local DUI = DaylightUI
    DUI.API.For("Neon").AddDefaults("UnitFrames", { neonGlow = 0.5 })
    DUI:Set("UnitFrames", "neonGlow", 0.9)
    DUI.DB.Active().unsaved = nil   -- a profile the setup guide finished (the stand-in is never saved)
    DUI.DB.OnLogout()
    local saved = DaylightUIDB
    -- Next session without the plugin.
    stub.Load({ module = true, before = function() _G.DaylightUIDB = saved end })
    local p = DaylightUI.DB.Active()
    T.eq(p.modules.UnitFrames.neonGlow, 0.9, "still saved")
    DaylightUI.DB.OnLogout()
    T.eq(DaylightUIDB.profileData[DaylightUI.DB.ActiveName()].modules.UnitFrames.neonGlow, 0.9, "and kept at logout")
end)

T.test("api defaults: bad asks are refused", function()
    stub.Load({ module = true })
    local me = DaylightUI.API.For("Neon")
    T.eq(me.AddDefaults(nil, {}), false)
    T.eq(me.AddDefaults("UnitFrames", nil), false)
end)
