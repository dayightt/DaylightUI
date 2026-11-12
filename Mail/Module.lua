-- Registers the mailbox window and its gold ledger with the core. It lives in the core
-- addon; the window is switched by the "enabled" setting (read at login) and the ledger
-- runs either way.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail

-- When DaylightMogul's mailbox is in use (API 1.5+ and Mail.Owns() is true), the window
-- isn't built and the Skins leave the game's mail frames to Mogul. The ledger keeps
-- recording so there's no gap if Mogul is removed. Every call is guarded like
-- Craft/Module.lua. Checked in OnEnable, after Mogul has loaded.
function ns.MogulOwns()
    local mog = _G.DaylightMogul
    local api = type(mog) == "table" and mog.API
    local v = type(api) == "table" and api.version
    if type(v) ~= "table" or type(v[1]) ~= "number" or type(v[2]) ~= "number" then return false end
    if v[1] < 1 or (v[1] == 1 and v[2] < 5) then return false end
    local mail = api.Mail
    if type(mail) ~= "table" or type(mail.Owns) ~= "function" then return false end
    local ok, owns = pcall(mail.Owns)
    return ok and owns == true
end

DUI:RegisterModule("Mailbox", {
    label = "Mailbox",
    order = 130,
    section = "QoL", pageOrder = 134, windowCard = true,   -- a card on Extras > Windows
    ns = ns,
    parts = { "Ledger", "Inbox", "Send", "LedgerPage", "Window" },
    defaults = ns.DEFAULTS,
    options = ns.OPTIONS,
    OnEnable = function(mod)
        ns.module = mod
        ns.Ledger.Start()
        ns.Send.SaveOwnName()   -- so this character's alts can pick it as a recipient
        DUI.mailMogul = ns.MogulOwns()
        DUI.mailOwnWindow = mod.db.enabled == true and not DUI.mailMogul
        if DUI.mailOwnWindow then ns.Window.Build(mod) end
    end,
    OnSettingChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
    OnStyleChanged = function()
        if ns.Window then ns.Window.Apply() end
    end,
})
