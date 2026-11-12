-- Registers the profession window with the core. It lives in the core addon and is
-- switched by the "enabled" setting, read at login.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

-- When DaylightMogul's profession window is in use (API 1.3+ and Craft.Owns() is
-- true), this one isn't built at all, including the Professions key, and the Skins
-- leave the game's frame to Mogul. Every call is guarded like Mail/LedgerPage.lua, so
-- a missing, older or broken Mogul changes nothing. Checked in OnEnable, after Mogul
-- has loaded.
function ns.MogulOwns()
    local mog = _G.DaylightMogul
    local api = type(mog) == "table" and mog.API
    local v = type(api) == "table" and api.version
    if type(v) ~= "table" or type(v[1]) ~= "number" or type(v[2]) ~= "number" then return false end
    if v[1] < 1 or (v[1] == 1 and v[2] < 3) then return false end
    local craft = api.Craft
    if type(craft) ~= "table" or type(craft.Owns) ~= "function" then return false end
    local ok, owns = pcall(craft.Owns)
    return ok and owns == true
end

DUI:RegisterModule("Professions", {
    label = "Professions",
    order = 128,
    section = "QoL", pageOrder = 132, windowCard = true,   -- a card on Extras > Windows
    ns = ns,
    parts = { "Data", "Share", "Spells", "List", "Recipe", "Make", "View", "Key", "Window" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        DUI.craftMogul = ns.MogulOwns()
        DUI.craftOwnWindow = mod.db.enabled == true and not DUI.craftMogul
        if ns.Window and DUI.craftOwnWindow then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
