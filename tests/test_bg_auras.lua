local stub = require("stub")

-- Aura buttons in a battleground. The client builds a batch of buttons the moment
-- a group is added (AddAuraGroup) and runs the addon's initializeFrame on each.
-- Under a PvP match that is the only moment they can be styled, so every setting
-- must be on the container before its groups.

local PVP = 3   -- Enum.AddOnRestrictionType.PvPMatch

local function login(before) return stub.Load({ module = true, before = before }) end

-- A /reload: settings saved by a first session, loaded again with before().
local function reload(set, before)
    local DUI = login()
    set(DUI)
    stub.RunTimers()
    local sv = DaylightUIDB
    sv.profileData[DUI.DB.ActiveName()].unsaved = nil
    stub.FireEvent("PLAYER_LOGOUT")
    return login(function() DaylightUIDB = sv; if before then before() end end)
end

local function raidTile(ns, i)
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton" .. i, ns.Raid.header)
    b:SetAttribute("unit", "raid" .. i)
    stub.units["raid" .. i] = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    stub.RunTimers()
    return b
end

local function declared(c)
    local n = 0
    for _ in pairs(c.__groups) do n = n + 1 end
    return n
end

T.test("joining a BG: a raid tile's buttons are built with its timers, swipe and size", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    DUI:Set("UnitFrames", "raid.auras.buffs.which", "all")
    DUI:Set("UnitFrames", "raid.auras.buffs.size", 20)
    DUI:Set("UnitFrames", "raid.auras.buffs.swipe", true)
    DUI:Set("UnitFrames", "raid.auras.buffs.timers", false)
    stub.RunTimers()
    stub.SetRestriction("PvPMatch", true)
    local b = raidTile(ns, 3)
    local g = b.auraSet.buffs.__groups.all
    T.truthy(g and g.button, "the buffs group is there")
    local btn = g.buttons[stub.AURA_BATCH]
    T.eq(btn:GetWidth(), 20, "its size")
    local parts = btn.__cooldown
    T.eq(parts.__drawSwipe, true, "the swipe")
    T.eq(btn.__timeOpts and btn.__timeOpts.textFormatter, DUI.Style.DurationFormatter(0), "timers off: writes nothing")
end)

T.test("a /reload in a BG: the target's and player's rows are built at their size", function()
    local DUI, ns = reload(function(D)
        D:Set("UnitFrames", "targetAuras.buffSize", 31)
        D:Set("UnitFrames", "targetAuras.debuffSize", 33)
        D:Set("UnitFrames", "playerAuras.buffs", true)
        D:Set("UnitFrames", "playerAuras.buffSize", 29)
    end, function() stub.restrictions[PVP] = true end)
    T.eq(ns.auras.buffs.__groups.buffs.buttons[stub.AURA_BATCH]:GetWidth(), 31, "target buffs")
    T.eq(ns.auras.debuffs.__groups.mine.button:GetWidth(), 33, "target debuffs")
    T.eq(ns.playerAuras.buffs.__groups.buffs.button:GetWidth(), 29, "player buffs")
    T.truthy(DUI.Restricted(), "the match is known from login on")
end)

T.test("a /reload in a BG: the restrictions are read before the modules build", function()
    local DUI = login(function() stub.restrictions[PVP] = true end)
    T.truthy(DUI.Restricted(), "no PLAYER_ENTERING_WORLD yet, the match is still known")
    local ran = false
    DUI.AfterRestrictions(function() ran = true end, "test:bg")
    T.falsy(ran, "held until the match ends")
end)

T.test("timers switched off later: the buttons get a formatter that writes nothing", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.auras.buffs.which", "mine")
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    DUI:Set("UnitFrames", "raid.auras.buffs.timers", true)
    stub.RunTimers()
    local b = raidTile(ns, 4)
    local btn = b.auraSet.buffs.__groups.mine.button
    T.eq(btn.__timeOpts.textFormatter, ns.Auras.TimeFormatter(false), "timers on")
    DUI:Set("UnitFrames", "raid.auras.buffs.timers", false)
    stub.RunTimers()
    T.eq(btn.__timeOpts.textFormatter, DUI.Style.DurationFormatter(0), "bound to an empty formatter")
end)

T.test("in a BG: the dispel corner icon is sized and edged when it is built", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "raid.dispelSize", 16)
    stub.RunTimers()
    stub.SetRestriction("PvPMatch", true)
    local b = raidTile(ns, 5)
    local btn = b.dispel.__groups.dispel.buttons[stub.AURA_BATCH]
    T.eq(btn:GetWidth(), 16, "its size")
    local edged = false
    for _, d in ipairs(btn.__dispels or {}) do if d.tex == btn.dispelEdge then edged = true end end
    T.truthy(edged, "its edge handed to the client")
end)

T.test("only the groups in use are declared; a choice is added the first time it is picked", function()
    local DUI, ns = login()
    local b = raidTile(ns, 6)
    local set = b.auraSet
    T.eq(declared(set.debuffs), 1, "debuffs: the one filter in use")
    T.eq(declared(set.buffs), 0, "buffs off: none")
    T.eq(declared(b.tint), 0, "no dispel highlight: no tint")
    T.eq(declared(b.dispel), 1, "the dispel icon: only mine")
    DUI:Set("UnitFrames", "raid.auras.buffs.which", "mine")
    DUI:Set("UnitFrames", "raid.auras.buffs.show", true)
    stub.RunTimers()
    T.truthy(set.buffs.__groups.mine, "switched on: added")
    T.truthy(set.buffs.__groups.mine.max > 0)
    DUI:Set("UnitFrames", "raid.auras.buffs.which", "all")
    stub.RunTimers()
    T.eq(set.buffs.__groups.mine.max, 0, "the old one kept, at 0")
    T.truthy(set.buffs.__groups.all.max > 0)
end)

T.test("the target's debuffs skip the all-in-one group when the split worked", function()
    local _, ns = login()
    T.isnil(ns.auras.debuffs.__groups.others)
    T.truthy(ns.Auras.Splits(ns.auras.debuffs))
end)

T.test("an unchanged icon size re-lays nothing", function()
    local _, ns = login()
    local c = ns.auras.buffs
    ns.Auras.SetOwnSize(c, 22, 3)
    local layout = c.__groups.buffs.layout
    ns.Auras.SetOwnSize(c, 22, 3)
    T.eq(c.__groups.buffs.layout, layout, "same size: the same layout table")
    ns.Auras.SetOwnSize(c, 24, 3)
    T.eq(c.__groups.buffs.layout.elementWidth, 24)
end)
