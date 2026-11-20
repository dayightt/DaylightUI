-- The pieces every Auction House file uses: Daylight UI's error reporting and
-- events, this module's own callbacks, and its saved prices.

local _, ns = ...
local DUI = DaylightUI

ns.SafeCall = DUI.SafeCall
ns.RegisterEvent = DUI.RegisterEvent
ns.AfterCombat = DUI.AfterCombat
ns.Thousands = DUI.Thousands
ns.L = DUI.L

function ns.Print(text)
    DUI.Print(text)
end

-- Callbacks between this module's files, kept apart from the core's so a name
-- like "PricesChanged" never reaches another module.
local callbacks = {}

function ns.On(name, fn)
    local list = callbacks[name]
    if not list then list = {}; callbacks[name] = list end
    list[#list + 1] = fn
end

function ns.Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do DUI.SafeCall(list[i], ...) end
end

-- The prices live in their own saved table, account-wide: every character on
-- one ruleset shops on the same Auction House.
--   DaylightUIAuctionDB = { rulesets = { [key] = { items, full, asked, offered, n, last } },
--                           suffixes = { [number] = "of the Bear" },
--                           vendor = { [itemID] = copper } }
local DB = {}
ns.DB = DB

-- Never written by a newer copy of the addon, so nothing here is read-only.
DB.readOnly = false

local function root()
    if type(DaylightUIAuctionDB) ~= "table" then DaylightUIAuctionDB = {} end
    return DaylightUIAuctionDB
end

function DB.Prices()
    return root()
end

function DB.RulesetData(rkey)
    local r = root()
    if type(r.rulesets) ~= "table" then r.rulesets = {} end
    local data = r.rulesets[rkey]
    if type(data) ~= "table" then
        data = {}
        r.rulesets[rkey] = data
    end
    return data
end

-- A saved table by name, made on first use (Sell's pins, hides and amounts).
function DB.Table(field)
    local r = root()
    if type(r[field]) ~= "table" then r[field] = {} end
    return r[field]
end

-- What vendors sell items for, by itemID (copper per unit, Vendor.lua).
function DB.Vendor()
    local r = root()
    if type(r.vendor) ~= "table" then r.vendor = {} end
    return r.vendor
end

-- Random-suffix words by the Auction House's suffix number. Forever's links
-- don't carry that number, so its words are the way back to it.
function DB.Suffixes()
    local r = root()
    if type(r.suffixes) ~= "table" then r.suffixes = {} end
    return r.suffixes
end

-- DaylightMogul is the full trading suite and owns the Auction House when it's
-- loaded: then this addon shows no window, no tooltip line and no options page,
-- so two addons never fight over the game's frame. Read at login, once every
-- addon has loaded.
function ns.MogulOwns()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local loaded = C_AddOns.IsAddOnLoaded("DaylightMogul")
        if loaded then return true end
    end
    return type(_G.DaylightMogul) == "table"
end

-- How long ago, in a few words: "12 min", "2 h", "3 days".
function ns.Ago(seconds)
    local L = ns.L
    if type(seconds) ~= "number" or seconds < 60 then return L["1 min"] end
    if seconds < 3600 then return string.format(L["%d min"], math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format(L["%d h"], math.floor(seconds / 3600)) end
    local days = math.floor(seconds / 86400)
    if days == 1 then return L["1 day"] end
    return string.format(L["%d days"], days)
end
