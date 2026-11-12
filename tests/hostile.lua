local stub = require("stub")
local BW = require("bookworld")
local CW = require("charworld")
local IW = require("inspectworld")
local PW = require("craftworld")
local LW = require("lfgworld")
local SW = require("socialworld")
local LGW = require("legacyworld")
local MW = require("mailworld")
local H = {}

-- The hostile sweep (run by tests/test_hostile_*.lua): every module on, a 40-player
-- battleground (enemy players, debuffs with dispel types), then every lever pulled
-- while the client is at its strictest: between fights in the match, in a fight,
-- and in a boss fight. Every event the addon's frames listen to, every frame's
-- OnUpdate, timers and tickers, and every setting on every options page set to
-- another value, then the fight and the match end so the queued work runs. Any
-- error (caught by SafeCall or not) and any touch of a locked aura button fails
-- it, listed by where it happened. These are the errors players used to hit first
-- in battlegrounds.

local ALL = { module = true, actionbars = true, buffs = true, bags = true, nameplates = true, tooltip = true,
              qol = true, chat = true, infopanel = true, skins = true, quests = true }

local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "SHAMAN", "WARLOCK", "PALADIN" }
local DISPELS = { "Magic", "Curse", "Disease", "Poison" }
local UNITS = { "player", "target", "targettarget", "focus", "pet", "party1", "raid1", "raid7", "nameplate1", "nameplate2" }

-- world "bg" is a 40-player raid against enemy players. "party" is you and four
-- others in a keystone dungeon against monsters (no raid units at all).
local function battleground(world)
    local party = world == "party"
    local units = { player = { name = "Me", lastName = "Daylight", class = "PRIEST", isPlayer = true, reaction = 5,
                               health = 80, maxHealth = 100, power = 50, maxPower = 100 } }
    local function ally(i)
        return { name = "Ally" .. i, class = CLASSES[i % #CLASSES + 1], isPlayer = true, reaction = 5,
                 health = 40 + i, maxHealth = 100, power = 10, maxPower = 100 }
    end
    if party then
        for i = 1, 4 do units["party" .. i] = ally(i) end
    else
        for i = 1, 40 do units["raid" .. i] = ally(i) end
        for i = 1, 4 do units["party" .. i] = units["raid" .. (i + 1)] end
    end
    local function enemy(i)
        return { name = "Foe" .. i, class = CLASSES[i % #CLASSES + 1], isPlayer = not party, reaction = 2, enemy = true,
                 health = 30, maxHealth = 100, power = 20, maxPower = 100,
                 cast = { name = "Fireball", texture = 1, duration = stub.Duration(1.5) } }
    end
    units.target, units.focus, units.targettarget = enemy(1), enemy(2), units.player
    units.pet = { name = "Wolf", class = "HUNTER", reaction = 5, health = 50, maxHealth = 50 }
    for i = 1, 5 do units["nameplate" .. i] = enemy(i + 2) end
    stub.SetUnits(units)
    stub.SetGroup(true, not party)
    for _, u in ipairs(UNITS) do
        local debuffs = {}
        for i, d in ipairs(DISPELS) do
            debuffs[i] = { name = d .. " hex", spellId = 100 + i, icon = 1, dispelName = d, auraInstanceID = 1000 + i,
                           duration = 10, expirationTime = 20, applications = 1 }
        end
        stub.SetAuras(u, "HARMFUL", debuffs)
        stub.SetAuras(u, "HELPFUL", { { name = "Fortitude", spellId = 1243, icon = 1, auraInstanceID = 2000,
                                        duration = 0, expirationTime = 0, applications = 1 } })
    end
end

-- Client functions other areas need that the fake game only fakes in their own
-- test files: bags (a 16-slot backpack with two items) and XP.
local function gameWorld()
    local items = { [1] = { iconFileID = 101, stackCount = 5, quality = 3, hyperlink = "|Hitem:1|h" },
                    [2] = { iconFileID = 102, stackCount = 1, quality = 0, hyperlink = "|Hitem:2|h" } }
    _G.IsShiftKeyDown = _G.IsShiftKeyDown or function() return false end   -- the tooltip asks every frame
    _G.Constants = _G.Constants or {}
    Constants.InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 }
    _G.C_Container = {
        GetContainerNumSlots = function(id) return id == 0 and 16 or 0 end,
        GetContainerItemInfo = function(bag, slot) return bag == 0 and items[slot] or nil end,
        GetContainerItemQuestInfo = function() return {} end,
        GetContainerNumFreeSlots = function(bag) return bag == 0 and 14 or 0, 0 end,
        HasContainerItem = function(bag, slot) return bag == 0 and items[slot] ~= nil end,
        SetItemSearch = function() end,
        SortBags = function() end,
        ContainerIDToInventoryID = function(id) return 30 + id end,
        GetContainerItemEquipmentSetInfo = function() return false, "" end,
    }
    _G.GetMoney = function() return 9592 end
    _G.UnitXP = function() return 300 end
    _G.UnitXPMax = function() return 1200 end
    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    CreateFrame("Frame", "MinimapCluster", UIParent)
    CreateFrame("Frame", "Minimap", MinimapCluster)
    CreateFrame("Frame", "BuffFrame", UIParent)
    CreateFrame("Frame", "DebuffFrame", UIParent)
    -- The spellbook and talents window, switched on (it's off by default while being
    -- built), and the inspect window's game (the book world, the character world,
    -- Blizzard_InspectUI). Its units are the battleground's, set after.
    local gear = { [1] = CW.item("Helm", { enchant = "+8 Stamina", enchantId = 1 }), [16] = CW.item("Blade") }
    LW.world({ level = false })()   -- the group finder (Lfg/), with the battleground's own level and group
    SW.world({})()   -- the social window (Social/): friends, allies, requests; the raid is the battleground's
    PW.world({})()   -- the professions (Craft/): its world first, the inspect's ShowUIPanel last
    IW.world({ gear = { target = gear, party1 = gear }, itemLevel = { target = 60, party1 = 58 } })()
    MW.world({ letters = { { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 },
        { sender = "Thaxton Ashby", subject = "Hello" } } })()   -- the mailbox (Mail/), with two letters waiting
    LGW.world({})()   -- the Legacy window (Legacy/), last, since its C_MajorFactions and C_Traits answer for it and pass the rest on
    DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true }, Inspect = { enabled = true },
        Professions = { enabled = true }, GroupFinder = { enabled = true }, Social = { enabled = true },
        Legacy = { enabled = true } } } } }
end

-- The spellbook and talents window: P and N, both pages filled, a search, the
-- game's book opened and closed, the addon's closed. In a fight P opens the game's
-- book (the hand-back), but an addon window already open stays.
local function pullBook(DUI)
    local B = DUI.Book and DUI.Book.Window
    if not (B and B.frame) then error("the book window wasn't built") end
    BW.Open(BW.SPELLBOOK)
    DUI.Win.Followers.Tick()
    B.Show("talents")
    B.Show("spells")
    if DUI.Book.Spells then DUI.Book.Spells.Search("a") ; DUI.Book.Spells.Search("") end
    BW.Toggle(BW.TALENTS)
    DUI.Win.Followers.Tick()
    BW.Escape()
    DUI.Win.Followers.Tick()
    B.Close()
    stub.RunTimers()
end

-- The profession window: a profession opened, a slot, a search, a craft and its
-- casts, a tab, K's overview, the game's frame hidden, the addon's closed. In a
-- fight the game's own window is used (the hand-back) and the addon's may not open.
local function pullCraft(DUI)
    local C = DUI.Craft and DUI.Craft.Window
    if not (C and C.frame) then error("the profession window wasn't built") end
    PW.Open(197)
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    if DUI.Win.IsOpen(C.frame) then
        DUI.Craft.List.PickSlot(2)
        DUI.Craft.List.PickSlot(nil)
        DUI.Craft.List.Search("silk")
        DUI.Craft.List.Search("")
        DUI.Craft.Make.Create()
        PW.Cast()
        DUI.Craft.Make.CreateAll()
        PW.Cast(false)
        stub.Key(C.Switch, 185)   -- a tab, as the player's click
        stub.RunTimers()
        DUI.Win.Followers.Tick()
    end
    PW.Close()
    DUI.Win.Followers.Tick()
    PW.Overview()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    C.Close()
    stub.RunTimers()
end

-- The group finder window: the game's key, a search, a group opened, a listing made
-- from the game's note box and taken down, the who list, the game's frame hidden,
-- the addon's closed. The addon's window is used in fights too.
local function pullLfg(DUI)
    local G = DUI.Lfg and DUI.Lfg.Window
    if not (G and G.frame) then error("the group finder window wasn't built") end
    LW.Toggle(1)
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    if DUI.Win.IsOpen(G.frame) then
        stub.Key(G.ShowTab, "find", true)
        stub.RunTimers()
        local first = DUI.Lfg.Browse.results and DUI.Lfg.Browse.results[1]
        if first then DUI.Lfg.Browse.Toggle(first.id) end
        stub.Key(G.ShowTab, "list", true)
        DUI.Lfg.Listing.Toggle(798)
        LW.Type("sweep")
        stub.Key(DUI.Lfg.Listing.Post)
        stub.RunTimers()
        DUI.Win.Followers.Tick()
        stub.Key(G.ShowTab, "who", true)
        stub.RunTimers()
        DUI.Lfg.Listing.Unlist()
        stub.RunTimers()
    end
    LW.Close()
    DUI.Win.Followers.Tick()
    G.Close()
    stub.RunTimers()
end

-- The social window: O, every tab (the raid is the battleground's 40), a friend
-- picked and invited, one coming online, a request and its Accept, an ally pinned,
-- the game's frame hidden, the addon's closed. Used in fights too.
local function pullSocial(DUI)
    local G = DUI.Social and DUI.Social.Window
    if not (G and G.frame) then error("the social window wasn't built") end
    SW.Toggle()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    if DUI.Win.IsOpen(G.frame) then
        local F = DUI.Social.Friends
        local first = F.rows and F.rows[1]
        if first then stub.Key(first.Click, first) end
        stub.Key(function() local b = F.page.foot.buttons[1]; if b then b:Click() end end)
        SW.Login(6)
        stub.RunTimers()
        stub.Key(G.ShowTab, "allies", true)
        stub.RunTimers()
        local a = DUI.Social.Allies.list and DUI.Social.Allies.list[1]
        if a then DUI.Social.Data.Pin(a, true) end
        stub.Key(G.ShowTab, "requests", true)
        SW.Invite("Sweep#1")
        stub.RunTimers()
        local inv = DUI.Social.Data.Invites()[1]
        if inv then DUI.Social.Data.Accept(inv.id) end
        stub.Key(G.ShowTab, "raid", true)
        stub.RunTimers()
        DUI.Social.Raid.Sync()
        stub.Key(G.ShowTab, "friends", true)
        stub.RunTimers()
    end
    SW.Close()
    DUI.Win.Followers.Tick()
    G.Close()
    stub.RunTimers()
end

-- The inspect window: a player (the enemy target in a battleground, a party
-- member in the keystone), both pages, a target change, a second inspect, the
-- game's frame hidden, the addon's closed.
local function pullInspect(DUI)
    local I = DUI.Inspect and DUI.Inspect.Window
    if not (I and I.frame) then error("the inspect window wasn't built") end
    local unit = UnitIsPlayer("target") and "target" or "party1"
    IW.Inspect(unit)
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    if not DUI.Win.IsOpen(I.frame) then error("the inspect window didn't open on " .. unit) end
    I.Show("talents")
    I.Show("gear")
    IW.Arrive(unit)
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    DUI.Win.Followers.Tick()
    IW.Inspect(unit)
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    I.Show("talents")
    IW.Hide()
    DUI.Win.Followers.Tick()
    I.Close()
    stub.RunTimers()
end

-- Pages the sweep leaves alone, each with its reason.
local SKIP_PAGES = {
    profiles = "switching profiles always ends in a reload (Profiles.AskReload)",
}

-- Locked-part touches that are fine, each with its reason (like guards_allow.lua).
local ALLOWED_LOCKED = {
}

-- Raid tiles (or party buttons) the secure headers would make.
local function groupButtons(ns, world)
    local party = world == "party"
    local header = party and ns.Party.header or ns.Raid.header
    for i = 1, party and 4 or 5 do
        local b = CreateFrame("Button", (party and "DaylightUIPartyHeaderUnitButtonSweep" or "DaylightUIRaidHeaderUnitButtonSweep") .. i, header)
        b:SetAttribute("unit", (party and "party" or "raid") .. i)
        header.initialConfigFunction(header, b:GetName())
    end
end

-- What went wrong, once per place: "<where>: <message>".
local problems, order = {}, {}
-- How much it pulled, so it can't quietly go hollow.
local pulled = { events = 0, settings = 0, updates = 0 }
local function note(what, err)
    local key = what .. ": " .. string.match(tostring(err), "^[^\n]*")
    if not problems[key] then problems[key] = true; order[#order + 1] = key end
end
local function try(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then note(what, err) end
end
local function collect()
    for _, e in ipairs(stub.errors) do note("reported", e) end
    stub.errors = {}
    for site, n in pairs(stub.lockSites) do
        if not ALLOWED_LOCKED[string.match(site, "^(%S+)")] then note("locked part", site .. " (" .. n .. "x)") end
    end
    stub.lockSites, stub.lockErrors = {}, 0
end

-- Events the sweep doesn't fire, each with its reason.
local SKIP_EVENTS = {
    PLAYER_LOGOUT = "the session ends: saved settings are stripped to what differs from the defaults (DB.OnLogout)",
    PLAYER_LEAVING_WORLD = "a loading screen or logout follows",
}

-- Payloads that look like the client's, by event.
local function payloads(event)
    if SKIP_EVENTS[event] then return {} end
    if string.find(event, "^UNIT_") then
        local out = {}
        for _, u in ipairs(UNITS) do out[#out + 1] = { u } end
        return out
    end
    if string.find(event, "^CHAT_MSG_") then return { { "hello there", "Ally1", "", "", "Ally1", "", 0, 0, "", 0, 1, "Player-1-00000001" } } end
    if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then return { { "nameplate1" }, { "nameplate2" } } end
    if event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "ADDON_LOADED" or event == "PLAYER_LOGIN"
        or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then return {} end
    return { {} }
end

local function everyEvent()
    local seen, list = {}, {}
    for _, f in ipairs(stub.frames) do
        for e in pairs(f.__events or {}) do
            if not seen[e] then seen[e] = true; list[#list + 1] = e end
        end
    end
    table.sort(list)
    for _, e in ipairs(list) do
        for _, args in ipairs(payloads(e)) do
            pulled.events = pulled.events + 1
            try("event " .. e, stub.FireEvent, e, unpack(args))
        end
    end
end

local function everyUpdate()
    local n = #stub.frames
    for i = 1, n do
        local f = stub.frames[i]
        if f and f.__scripts and f.__scripts.OnUpdate then
            pulled.updates = pulled.updates + 1
            try("OnUpdate " .. tostring(f.__name), stub.RunOnUpdate, f, 0.2)
        end
    end
    try("tickers", stub.RunTickers)
    try("timers", stub.RunTimers)
end

-- Another value for an options item, or nil to leave it.
local function another(Options, page, item)
    local v = Options.Get(page, item)
    local t = item.type
    if t == "toggle" then return not v end
    if t == "slider" then
        if type(item.min) ~= "number" or type(item.max) ~= "number" then return nil end
        return (v == item.max) and item.min or item.max
    end
    if t == "dropdown" then
        local values = item.values
        if type(values) == "function" then values = values() end
        local keys = item.order
        if type(keys) == "function" then keys = keys() end
        if type(keys) ~= "table" and type(values) == "table" then
            keys = {}
            for k in pairs(values) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        end
        for _, k in ipairs(keys or {}) do if k ~= v then return k end end
        return nil
    end
    if t == "color" then return { 0.3, 0.6, 0.9, 1 } end
    if t == "gradient" then return { lo = { 0.2, 0.3, 0.4 }, hi = { 0.8, 0.7, 0.6 } } end
    return nil
end

local function everySetting(DUI)
    local Options = DUI.Options
    for id, page in Options.Pages() do
        for _, group in ipairs(not SKIP_PAGES[id] and page.groups or {}) do
            for _, item in ipairs(group.items or {}) do
                if (item.key or item.set) and not item.reload then
                    local ok, value = pcall(another, Options, page, item)
                    if ok and value ~= nil then
                        pulled.settings = pulled.settings + 1
                        try("setting " .. id .. " " .. tostring(item.key or item.label), Options.Set, page, item, value)
                    end
                end
            end
        end
    end
end

-- The mailbox window: a mailbox clicked, Collect all, a letter opened and taken,
-- the Send and Ledger tabs, then walked away from (the client's CloseMail fired, so
-- the next mailbox clicks). Used in fights too.
local function pullMail(DUI)
    local M = DUI.Mail
    if not (M and M.Window) then error("the mailbox window wasn't loaded") end
    MW.Open()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    if M.Window.frame and DUI.Win.IsOpen(M.Window.frame) then
        stub.Key(M.Inbox.Collect)
        MW.Settle()
        stub.RunTimers()
        if MW.Inbox()[1] then
            stub.Key(M.Inbox.Pick, 1)
            stub.Key(M.Inbox.Take)
            MW.Settle()
        end
        stub.Key(M.Window.ShowTab, "send")
        stub.RunTimers()
        stub.Key(M.Window.ShowTab, "ledger")
        stub.RunTimers()
        stub.Key(M.Window.ShowTab, "inbox")
    end
    MW.Leave()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    if MW.IsOpen() then error("walking away left the mailbox open (CloseMail never said)") end
    MW.Arrive({ sender = "Sweep Mailer", subject = "Again", money = 300 })
    MW.Deliver()
end

-- The Legacy window: the Legacy button, every tab, a challenge opened and searched,
-- a point staged in a tree and applied, a tracked challenge's click, the game's
-- frame hidden, the addon's closed. Used in fights too.
local function pullLegacy(DUI)
    local G = DUI.Legacy and DUI.Legacy.Window
    if not (G and G.frame) then error("the Legacy window wasn't built") end
    LGW.Toggle()
    stub.RunTimers()
    DUI.Win.Followers.Tick()
    if DUI.Win.IsOpen(G.frame) then
        DUI.Legacy.Progress.Wheel(-1)
        LGW.Earn(5)
        stub.RunTimers()
        stub.Key(G.ShowTab, "challenges")
        stub.RunTimers()
        local C = DUI.Legacy.Challenges
        C.Pick(20)
        local first = C.list and C.list[1]
        if first then C.Open(first.id) end
        C.Filter("todo")
        C.Filter("all")
        stub.Key(G.ShowTab, "trees")
        stub.RunTimers()
        local T = DUI.Legacy.Trees
        for _, b in ipairs(T.page.box.tiles) do
            if b:IsShown() and b.node and b.node.canBuy then stub.Key(b.Click, b, "LeftButton") break end
        end
        stub.RunTimers()
        T.Spend.Apply()
        T.Pick(2)
        LGW.Show(1102)
        stub.RunTimers()
        stub.Key(G.ShowTab, "progress")
        stub.RunTimers()
    end
    LGW.Close()
    DUI.Win.Followers.Tick()
    G.Close()
    stub.RunTimers()
end

local function phase(DUI, p, withSettings)
    p.enter()
    try("book window", pullBook, DUI)
    try("inspect window", pullInspect, DUI)
    try("profession window", pullCraft, DUI)
    try("group finder window", pullLfg, DUI)
    try("social window", pullSocial, DUI)
    try("Legacy window", pullLegacy, DUI)
    try("mailbox window", pullMail, DUI)
    everyEvent()
    everyUpdate()
    if withSettings then everySetting(DUI) end
    try("book window, again", pullBook, DUI)
    try("inspect window, again", pullInspect, DUI)
    try("profession window, again", pullCraft, DUI)
    try("group finder window, again", pullLfg, DUI)
    try("social window, again", pullSocial, DUI)
    try("Legacy window, again", pullLegacy, DUI)
    try("mailbox window, again", pullMail, DUI)
    everyEvent()
    everyUpdate()
    p.leave()
    everyUpdate()
    collect()
end

-- In order: the match (a battleground, or a keystone for the party world) between
-- fights, a fight in it, a boss fight, then the match ends. The settings pass
-- (about 1000 changes, the slow part) runs in one of them per test file, so the
-- files can run side by side under --par.
local function phases(match)
    return {
        -- A match also locks chat down (CHAT_MSG_* payloads go secret).
        { name = "between", enter = function() stub.SetRestriction(match, true); stub.SetRestriction("Chat", true) end,
          leave = function() end },
        { name = "fight", enter = function() stub.EnterCombat() end, leave = function() stub.LeaveCombat() end },
        { name = "boss", enter = function() stub.SetRestriction("Encounter", true); stub.EnterCombat() end,
          leave = function() stub.LeaveCombat(); stub.SetRestriction("Encounter", false) end },
        { name = "after", enter = function() end,
          leave = function() stub.SetRestriction(match, false); stub.SetRestriction("Chat", false) end },
    }
end

-- settingsIn: the phase ("between", "fight") whose settings pass runs, or nil.
-- plant(DUI): runs after login (a control's planted error).
-- how: { world = "bg" (default) | "party", testMode = true (test mode on from the
-- start; the first fight ends it, as in game) }.
-- Returns the problems found, and how much was pulled.
function H.Sweep(settingsIn, plant, how)
    how = how or {}
    problems, order = {}, {}
    pulled = { events = 0, settings = 0, updates = 0 }
    local opts = {}
    for k, v in pairs(ALL) do opts[k] = v end
    opts.before = gameWorld
    local DUI, ns = stub.Load(opts)
    battleground(how.world)
    try("group buttons", groupButtons, ns, how.world)
    if plant then plant(DUI) end
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    if how.testMode then
        try("test mode", function() T.truthy(DUI.SetTestMode(true), "test mode didn't start") end)
        stub.RunTimers()
    end
    collect()
    for _, p in ipairs(phases(how.world == "party" and "ChallengeMode" or "PvPMatch")) do
        phase(DUI, p, p.name == settingsIn)
    end
    return order, pulled
end
-- For local tools that play in the same world.
H.GameWorld, H.Battleground = gameWorld, battleground

-- No problems, and it really pulled the levers, so it can't quietly go hollow.
function H.Check(found, p, withSettings)
    T.eq(#found, 0, "\n  " .. table.concat(found, "\n  "))
    print(string.format("  (sweep: %d events, %d settings, %d frame updates)", p.events, p.settings, p.updates))
    T.truthy(p.events > 400 and p.updates > 20 and (not withSettings or p.settings > 400),
        "the sweep went hollow: " .. p.events .. " events, " .. p.settings .. " settings, " .. p.updates .. " updates")
end

return H
