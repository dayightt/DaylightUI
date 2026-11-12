-- What DaylightMogul, the companion auction house addon, reads from DaylightUI.
-- Only its Bridge/ folder calls in, and it calls exactly these. Changing one
-- makes Mogul quietly stop following the style, so this file fails first.
-- Mogul's own suite uses a stand-in; this pins the real thing.
local stub = require("stub")
local MW = require("mailworld")

T.test("mogul contract: the global is DaylightUI's namespace", function()
    local DUI = stub.Load()
    T.truthy(_G.DaylightUI == DUI, "_G.DaylightUI")
end)

T.test("mogul contract: DB.General() is the active general table, live", function()
    stub.Load()
    local general = DaylightUI.DB.General()
    T.eq(type(general), "table", "DB.General()")
    T.truthy(DaylightUI:Set("general", "font", "lato"), "Set general")
    T.eq(DaylightUI.DB.General().font, "lato", "a change shows in the table it hands out")
    T.truthy(DaylightUI.DB.General() == general, "the same table, not a copy")
end)

T.test("mogul contract: On(\"StyleChanged\") fires after a style change", function()
    stub.Load()
    local fired = 0
    DaylightUI.On("StyleChanged", function() fired = fired + 1 end)
    DaylightUI:Set("general", "scale", 1.1)
    T.eq(fired, 0, "not before the next frame")
    stub.RunTimers()
    T.eq(fired, 1, "StyleChanged")
end)

T.test("mogul contract: On(\"Login\") fires at login, after the profile is picked", function()
    stub.Load({ login = false })
    local general
    DaylightUI.On("Login", function() general = DaylightUI.DB.General() end)
    stub.FireEvent("PLAYER_LOGIN")
    T.eq(type(general), "table", "Login fired, and DB.General() answers inside it")
end)

T.test("mogul contract: GameFonts.ClientFont() returns a font path", function()
    stub.Load()
    T.eq(type(DaylightUI.GameFonts), "table", "GameFonts")
    T.eq(type(DaylightUI.GameFonts.ClientFont), "function", "GameFonts.ClientFont")
    T.eq(type(DaylightUI.GameFonts.ClientFont()), "string", "a string")
end)

-- Mogul imports the mailbox ledger once, keyed by Name-Realm like its own.
-- It reads days of flat kinds, items by name, the latest entries and item IDs.
T.test("mogul contract: DB.Character(key).ledger is the mailbox ledger, in the shape Mogul imports", function()
    local world = MW.world({ money = 100000, letters = {} })
    stub.Load({ before = function() world(); _G.GetRealmName = function() return "Forever" end end })
    local key = DaylightUI.DB.CharKey()
    T.eq(key, UnitName("player") .. "-Forever", "the key is Name-Realm")
    T.eq(type(DaylightUI.DB.Character), "function", "DB.Character")
    MW.OpenAH()
    MW.BuyCommodity({ name = "Heavy Leather", itemID = 4234, count = 20, unit = 1000 })
    for _ = 1, 30 do MW.Settle(); stub.RunTimers() end
    MW.CloseAH()
    local d = DaylightUI.DB.Character(key).ledger
    T.eq(type(d), "table", "ledger")
    T.eq(type(d.since), "number", "since")
    local day = d.days[date("%Y-%m-%d")]
    T.eq(type(day), "table", "days[YYYY-MM-DD]")
    T.eq(day.buys, -20000, "a day's kinds, flat and signed")
    T.deq(d.items["Heavy Leather"], { bought = 20000, boughtN = 20, sold = 0, soldN = 0 }, "items by name")
    local e = d.recent[1]
    T.eq(e.kind, "buys"); T.eq(e.amount, -20000); T.eq(e.item, "Heavy Leather"); T.eq(e.count, 20)
    T.eq(type(e.t), "number", "an entry's time")
    T.eq(type(d.ids), "table", "ids: name = itemID")
    _G.GetRealmName = nil
end)

-- The other direction: Mogul's profession API (1.3). The Craft module checks at
-- OnEnable, after Mogul has loaded. With API version 1.3 or later and
-- API.Craft.Owns() true, Mogul's profession window is in use, so DaylightUI
-- builds none and leaves the Professions key and the game's frame to Mogul.
T.test("mogul contract: API 1.3 Craft.Owns() true at login steps our profession window aside", function()
    local PW = require("craftworld")
    stub.Load({ before = function()
        PW.world({})()
        _G.DaylightMogul = { API = { version = { 1, 3 }, Craft = { Owns = function() return true end } } }
    end })
    T.eq(DaylightUI.craftMogul, true, "Mogul's window")
    T.isnil(stub.craft.Window.frame, "ours not built")
    _G.DaylightMogul = { API = { version = { 2, 0 }, Craft = { Owns = function() return true end } } }
    T.eq(stub.craft.MogulOwns(), true, "a later major still counts")
    _G.DaylightMogul = nil
    T.eq(stub.craft.MogulOwns(), false, "gone: ours")
end)

-- Mogul's mailbox API (1.5). With version 1.5 or later and API.Mail.Owns()
-- true, Mogul's mailbox is in use and DaylightUI builds none. The ledger still
-- records, so there's no gap if Mogul is removed later.
T.test("mogul contract: API 1.5 Mail.Owns() true at login steps our mailbox aside", function()
    local MW = require("mailworld")
    stub.Load({ before = function()
        MW.world({})()
        _G.DaylightMogul = { API = { version = { 1, 5 }, Mail = { Owns = function() return true end } } }
    end })
    T.eq(DaylightUI.mailMogul, true, "Mogul's mailbox")
    T.falsy(DaylightUI.mailOwnWindow, "ours not in use")
    T.isnil(stub.mail.Window.frame, "ours not built")
    _G.DaylightMogul = { API = { version = { 1, 4 }, Mail = { Owns = function() return true end } } }
    T.eq(stub.mail.MogulOwns(), false, "1.4 has no mailbox")
    _G.DaylightMogul = { API = { version = { 1, 5 }, Mail = { Owns = function() error("broken") end } } }
    T.eq(stub.mail.MogulOwns(), false, "a broken Mogul: ours")
    _G.DaylightMogul = nil
    T.eq(stub.mail.MogulOwns(), false, "gone: ours")
end)

-- Mogul's vendor API (1.6). With version 1.6 or later and API.Vendor.Owns()
-- true, Mogul's vendor window is in use. The NPC window then skips the
-- MerchantFrame and the shop page (gossip, quests and the trainer stay), and
-- Skins leaves the merchant frame alone.
T.test("mogul contract: API 1.6 Vendor.Owns() true at login steps our vendor page aside", function()
    local NW = require("npcworld")
    stub.Load({ before = function()
        NW.world({})()
        _G.DaylightMogul = { API = { version = { 1, 6 }, Vendor = { Owns = function() return true end } } }
    end })
    T.eq(DaylightUI.vendorMogul, true, "Mogul's vendor")
    T.falsy(DaylightUI.npcOwnVendor, "ours not in use")
    T.eq(DaylightUI.npcOwnWindow, true, "the talk window still ours")
    local N = stub.npc.Window
    T.isnil(N.frame.pages.shop, "no shop page built")
    NW.Merchant()
    for _ = 1, 3 do stub.RunTimers(); DaylightUI.Win.Followers.Tick() end
    T.falsy(N.frame:IsShown(), "a vendor never opens ours")
    _G.DaylightMogul = { API = { version = { 1, 5 }, Vendor = { Owns = function() return true end } } }
    T.eq(stub.npc.MogulVendor(), false, "1.5 has no vendor")
    _G.DaylightMogul = { API = { version = { 1, 6 }, Vendor = { Owns = function() error("broken") end } } }
    T.eq(stub.npc.MogulVendor(), false, "a broken Mogul: ours")
    _G.DaylightMogul = nil
    T.eq(stub.npc.MogulVendor(), false, "gone: ours")
end)

-- Mogul's warehouse panel docks beside the bank window. BankWindow() returns
-- the frame or nil, and never errors.
T.test("mogul contract: BankWindow() is the bank window while Bags is on, nil when off", function()
    stub.Load()
    T.eq(type(DaylightUI.BankWindow), "function", "BankWindow")
    T.isnil(DaylightUI.BankWindow(), "no Bags module: nil")
    local frame = CreateFrame("Frame", nil, UIParent)
    local ns = { Bank = {} }
    local mod = DaylightUI:RegisterModule("Bags", { ns = ns, label = "Bags", parts = {} })
    T.isnil(DaylightUI.BankWindow(), "registered, not enabled: nil")
    mod.enabled = true
    T.isnil(DaylightUI.BankWindow(), "enabled, bank window not built yet: nil")
    ns.Bank.window = frame
    T.truthy(DaylightUI.BankWindow() == frame, "the frame once built")
    mod.enabled = false
    T.isnil(DaylightUI.BankWindow(), "Bags switched off: nil")
    mod.enabled = true
    mod.ns = nil
    T.noerror(DaylightUI.BankWindow, "an odd module never errors")
    T.isnil(DaylightUI.BankWindow())
end)

T.test("mogul contract: VERSION is a string (Mogul's Bridge/Version.lua compares it)", function()
    stub.Load()
    T.eq(type(DaylightUI.VERSION), "string", "DaylightUI.VERSION")
end)
