-- Registers the NPC window with the core. It lives in the core addon and is
-- switched by the "enabled" setting, read at login.

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc

-- When DaylightMogul handles the vendor (API 1.6+ and Vendor.Owns() is true), the
-- shop page isn't built and the merchant frame is left to Mogul. Gossip, quests
-- and the trainer still use this window. Checked in OnEnable, after Mogul has loaded.
function ns.MogulVendor()
    local mog = _G.DaylightMogul
    local api = type(mog) == "table" and mog.API
    local v = type(api) == "table" and api.version
    if type(v) ~= "table" or type(v[1]) ~= "number" or type(v[2]) ~= "number" then return false end
    if v[1] < 1 or (v[1] == 1 and v[2] < 6) then return false end
    local vendor = api.Vendor
    if type(vendor) ~= "table" or type(vendor.Owns) ~= "function" then return false end
    local ok, owns = pcall(vendor.Owns)
    return ok and owns == true
end

DUI:RegisterModule("NPC", {
    label = "NPC window",
    order = 125,
    section = "QoL", pageOrder = 120,   -- options page goes under Extras
    ns = ns,
    parts = { "Data", "Shop", "Train", "Window", "Scene", "Popups" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        DUI.vendorMogul = ns.MogulVendor()
        DUI.npcOwnWindow = mod.db.enabled ~= false
        if ns.Window and mod.db.enabled ~= false then ns.Window.Build(mod) end
        if ns.Popups then ns.Popups.Enable() end
    end,
    OnSettingChanged = function()
        if ns.Window then ns.Window.Apply() end
        if ns.Popups then ns.Popups.Update() end
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
