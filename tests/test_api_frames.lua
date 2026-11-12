local stub = require("stub")

-- The unit frames, party, raid and party pets tell the API (API.lua) when they're
-- made, change unit, go away and get restyled.

local function recorder(API, event)
    local calls = {}
    API.On(event, function(...) calls[#calls + 1] = { ... } end)
    return calls
end

-- A party/raid button as the group's secure header would make it.
local function tile(ns, group, i, unit)
    local h = group.header
    local b = CreateFrame("Button", "DaylightUI" .. (group == ns.Raid and "Raid" or "Party") .. "HeaderUnitButton" .. i, h)
    b:SetAttribute("unit", unit)
    stub.units[unit] = stub.units[unit] or { name = "Kaladin", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    h.initialConfigFunction(h, b:GetName())
    return b
end

T.test("api frames: our single frames are found and announced", function()
    local DUI, ns = stub.Load({ module = true, login = false })
    local made = recorder(DUI.API, "FrameMade")
    stub.FireEvent("PLAYER_LOGIN")
    local seen = {}
    for _, c in ipairs(made) do if c[1] == "unit" then seen[c[3]] = c[2]; T.eq(c[4], false) end end
    T.eq(seen.player, ns.frames.player)
    T.eq(seen.target, ns.frames.target)
    T.eq(DUI.API.GetUnitFrame("target"), DaylightUIFrame_target)
    T.eq(DUI.API.GetUnitFrame("player"), DaylightUIFrame_player)
end)

T.test("api frames: a new target says FrameUnitChanged on the target frame", function()
    local DUI, ns = stub.Load({ module = true })
    local all = recorder(DUI.API, "FrameUnitChanged")
    local changed = setmetatable({}, { __index = table })
    local function mine()
        changed = {}
        for _, c in ipairs(all) do if c[2] == ns.frames.target then changed[#changed + 1] = c end end
    end
    stub.units.target = { name = "Defias Pillager", isPlayer = false, reaction = 2, level = 32,
                          health = 72, maxHealth = 100, power = 40, maxPower = 100 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    mine()
    T.eq(#changed, 1)
    T.eq(changed[1][1], "unit")
    T.eq(changed[1][2], ns.frames.target)
    T.eq(changed[1][3], "target")
    stub.units.target.name = "Other"
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    mine()
    T.eq(#changed, 2, "another target, another occupant")
end)

T.test("api frames: party tiles come and go with the group", function()
    local DUI, ns = stub.Load({ module = true, login = false })
    local made = recorder(DUI.API, "FrameMade")
    local removed = recorder(DUI.API, "FrameRemoved")
    stub.FireEvent("PLAYER_LOGIN")
    stub.SetGroup(true, false)
    local b = tile(ns, ns.Party, 1, "party1")
    local got
    for _, c in ipairs(made) do if c[2] == b then got = c end end
    T.truthy(got, "FrameMade for the tile")
    T.eq(got[1], "party")
    T.eq(got[3], "party1")
    T.eq(DUI.API.GetUnitFrame("party1"), b)
    stub.SetGroup(false, false)
    b:SetAttribute("unit", nil)
    -- Party tiles only: the members' cast bars ("castbar") let their units go too.
    local tiles = {}
    for _, c in ipairs(removed) do if c[1] == "party" then tiles[#tiles + 1] = c end end
    T.eq(#tiles, 1)
    T.eq(tiles[1][2], b)
    T.eq(tiles[1][3], "party1")
    T.isnil(DUI.API.GetUnitFrame("party1"))
    local changed = recorder(DUI.API, "FrameUnitChanged")
    b:SetAttribute("unit", "party2")
    local tileChanges = 0
    for _, c in ipairs(changed) do if c[1] == "party" then tileChanges = tileChanges + 1 end end
    T.eq(tileChanges, 1, "back with another member: only a unit change")
    T.eq(DUI.API.GetUnitFrame("party2"), b)
end)

T.test("api frames: in a raid the player's tile wins over the player frame", function()
    local DUI, ns = stub.Load({ module = true })
    stub.SetGroup(true, true, 10)
    stub.units.player = stub.units.player or { name = "Me", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    stub.units.raid3 = stub.units.player
    local b = tile(ns, ns.Raid, 1, "raid3")
    T.eq(DUI.API.GetUnitFrame("raid3"), b)
    T.eq(DUI.API.GetUnitFrame("player"), b, "the raid tile showing you")
    stub.SetRestriction("PvPMatch", true)
    local ok, res = pcall(DUI.API.GetUnitFrame, "player")
    T.truthy(ok, "no error under restrictions: " .. tostring(res))
    T.truthy(res == b or res == ns.frames.player, "a frame either way")
    stub.SetRestriction("PvPMatch", false)
end)

T.test("api frames: a style change says FrameStyled on every frame", function()
    local DUI, ns = stub.Load({ module = true })
    local styled = recorder(DUI.API, "FrameStyled")
    DUI.NotifyStyleChanged()
    stub.RunTimers()
    local seen = {}
    for _, c in ipairs(styled) do if c[1] == "unit" then seen[c[2]] = true end end
    for _, spec in ipairs(ns.SPECS) do T.truthy(seen[ns.frames[spec.unit]], spec.unit .. " restyled") end
end)

T.test("api frames: test mode and the options sample are previews", function()
    local DUI, ns = stub.Load({ module = true })
    local made = recorder(DUI.API, "FrameMade")
    local removed = recorder(DUI.API, "FrameRemoved")
    DUI.SetTestMode(true)
    stub.RunTimers()
    local previews = {}
    for _, c in ipairs(made) do
        if c[1] == "party" and c[4] == true then previews[c[2]] = true end
    end
    T.truthy(next(previews), "party tiles announced as previews")
    for f in pairs(previews) do
        T.isnil(DUI.API.GetUnitFrame(f.unitToken), "a preview is never looked up")
    end
    DUI.SetTestMode(false)
    stub.RunTimers()
    DUI.SetTestMode(true)
    stub.RunTimers()
    DUI.SetTestMode(false)
    stub.RunTimers()
    local times = {}
    for _, c in ipairs(made) do if c[4] == true then times[c[2]] = (times[c[2]] or 0) + 1 end end
    for f in pairs(previews) do T.eq(times[f], 1, "one FrameMade per preview frame") end
    local gone = 0
    for _, c in ipairs(removed) do if previews[c[2]] and c[4] == true then gone = gone + 1 end end
    T.truthy(gone > 0, "FrameRemoved for the previews")
    -- The options page's sample.
    local n0 = #made
    local s = ns.PageSample.New("party", CreateFrame("Frame"))
    s.Refresh(400, 300)
    T.truthy(#made > n0, "the sample's tile is announced")
    T.eq(made[#made][4], true)
    local s1 = ns.PageSample.New("target", CreateFrame("Frame"))
    T.eq(made[#made][1], "unit")
    T.eq(made[#made][4], true)
    T.eq(DUI.API.GetUnitFrame("target"), ns.frames.target, "the sample is not the real frame")
end)

T.test("api frames: party pets are announced and follow their owner", function()
    local DUI, ns = stub.Load({ module = true, login = false })
    local made = recorder(DUI.API, "FrameMade")
    stub.FireEvent("PLAYER_LOGIN")
    DUI:Set("UnitFrames", "partyPet.enabled", true)
    stub.SetGroup(true, false)
    local b = tile(ns, ns.Party, 1, "party1")
    stub.RunTimers()
    local pet
    for _, c in ipairs(made) do if c[1] == "partypet" then pet = c end end
    T.truthy(pet, "FrameMade partypet")
    T.eq(pet[4], false)
    local changed = recorder(DUI.API, "FrameUnitChanged")
    b:SetAttribute("unit", "party2")
    local found, owner = false, false
    for _, c in ipairs(changed) do
        if c[1] == "partypet" and c[3] == "partypet2" then found = true end
        if c[1] == "party" and c[2] == b and c[3] == "party2" then owner = true end
    end
    T.truthy(owner, "the tile changed unit")
    T.truthy(found, "the pet follows to partypet2")
end)

T.test("api frames: a tile is told it changed unit once it's redrawn", function()
    local DUI, ns = stub.Load({ module = true })
    stub.SetGroup(true, false)
    local b = tile(ns, ns.Party, 1, "party1")
    stub.units.party2 = { name = "Shallan", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    local who
    DUI.API.On("FrameUnitChanged", function(_, f) if f == b then who = b.rosterWho end end)
    b:SetAttribute("unit", "party2")
    T.truthy(who ~= nil, "told")
    T.eq(who, b.rosterWho, "the new member was already drawn")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The real header's order: it dresses a button (initialConfigFunction) and only
-- then sets its unit, and the tile and its pet are made at that moment
-- (Group:Dress). The first pet still gets "partypet1".
T.test("api frames: the first party pet gets its unit when the header sets it after dressing", function()
    local DUI, ns = stub.Load({ module = true, login = false })
    local made = recorder(DUI.API, "FrameMade")
    local styled = recorder(DUI.API, "FrameStyled")
    stub.FireEvent("PLAYER_LOGIN")
    DUI:Set("UnitFrames", "partyPet.enabled", true)
    stub.SetGroup(true, false)
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "HUNTER", health = 5, maxHealth = 10 }
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton1", h)
    h.initialConfigFunction(h, b:GetName())
    b:SetAttribute("unit", "party1")
    stub.RunTimers()
    T.truthy(b.pet, "the pet is made when the tile first gets a member")
    T.eq(DUI.API.GetUnitFrame("partypet1"), b.pet, "found by its unit")
    local got
    for _, c in ipairs(made) do if c[1] == "partypet" and c[2] == b.pet then got = c[3] end end
    T.eq(got, "partypet1", "made with its unit: the tile is dressed once it has a member")
    local n = 0
    for _, c in ipairs(styled) do if c[1] == "partypet" and c[2] == b.pet then n = n + 1 end end
    DUI:Set("UnitFrames", "partyPet.width", 90)
    stub.RunTimers()
    local m = 0
    for _, c in ipairs(styled) do if c[1] == "partypet" and c[2] == b.pet then m = m + 1 end end
    T.truthy(m > n, "a pet re-laid out says FrameStyled")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api frames: UnitFrames switched off, nothing found", function()
    local DUI = stub.Load()
    T.isnil(DUI.API.GetUnitFrame("player"))
    T.isnil(DUI.API.GetUnitFrame("party1"))
end)

-- ---------------------------------------------------------------------
-- Nameplates
-- ---------------------------------------------------------------------

local plateFrames
local function plateWorld(count)
    plateFrames = {}
    local function newPlate(i)
        local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
        np.UnitFrame = CreateFrame("Button", nil, np)
        np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
        np.UnitFrame.WidgetContainer = CreateFrame("Frame", nil, np.UnitFrame)
        np.UnitFrame.name = np.UnitFrame:CreateFontString(nil, "OVERLAY")
        function np:CanChangeHitTestPoints() return true end
        function np:SetAllHitTestPoints() end
        function np:SetHitTestPoints() end
        function np:ClearAllHitTestPoints() end
        function np:SetStackingBoundsFrame() end
        return np
    end
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        local i = tonumber(string.match(unit, "%d+"))
        if not i or not stub.units[unit] then return nil end
        plateFrames[i] = plateFrames[i] or newPlate(i)
        return plateFrames[i]
    end }
    _G.issecure = function() return false end
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    _G.UnitReaction = function(u) local x = stub.units[u]; return x and x.reaction end
    _G.IsInInstance = function() return false end
    _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
    Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
    _G.C_TooltipInfo = { GetUnit = function() return nil end }
    stub.units = { player = { name = "Me", class = "PRIEST", isPlayer = true } }
end

local function plateLoad(count)
    stub.Load({ nameplates = true, before = function() plateWorld(count) end })
    stub.RunTimers()
    -- Units appear after login, so the listeners below hear every plate.
    for i = 1, count or 2 do
        stub.units["nameplate" .. i] = { name = "Whelp" .. i, hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 }
    end
    return DaylightUI, stub.nameplates
end

T.test("api plates: a plate is announced and found by its unit", function()
    local DUI, ns = plateLoad()
    local made = recorder(DUI.API, "FrameMade")
    local changed = recorder(DUI.API, "FrameUnitChanged")
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local p = ns.Manager.byUnit.nameplate1
    T.truthy(p)
    T.eq(#made, 1)
    T.eq(made[1][1], "nameplate")
    T.eq(made[1][2], p)
    T.eq(made[1][4], false)
    T.eq(#changed, 1)
    T.eq(changed[1][1], "nameplate")
    T.eq(changed[1][2], p)
    T.eq(changed[1][3], "nameplate1")
    T.eq(DUI.API.GetNameplate("nameplate1"), p)
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.isnil(DUI.API.GetNameplate("nameplate1"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: a reused plate says goodbye to its old unit first", function()
    local DUI, ns = plateLoad()
    local log = {}
    for _, ev in ipairs({ "FrameMade", "FrameUnitChanged", "FrameRemoved" }) do
        DUI.API.On(ev, function(kind, f, unit) log[#log + 1] = ev .. ":" .. tostring(unit) end)
    end
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local p = ns.Manager.byUnit.nameplate1
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
    T.eq(ns.Manager.byUnit.nameplate2, p, "the same pooled plate")
    T.eq(table.concat(log, ","), "FrameMade:nil,FrameUnitChanged:nameplate1,FrameRemoved:nameplate1,FrameUnitChanged:nameplate2")
    T.eq(DUI.API.GetNameplate("nameplate2"), p)
    T.isnil(DUI.API.GetNameplate("nameplate1"))
end)

T.test("api plates: a plate is told once it is sized", function()
    local DUI, ns = plateLoad()
    local sized = {}
    local size = ns.Manager.SizeOne
    ns.Manager.SizeOne = function(p) sized[p] = true; return size(p) end
    local ready
    DUI.API.On("FrameUnitChanged", function(_, f) ready = sized[f] == true end)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    ns.Manager.SizeOne = size
    T.eq(ready, true, "sized before FrameUnitChanged")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: a plate that could not be put up is never reported", function()
    local DUI, ns = plateLoad()
    local made = recorder(DUI.API, "FrameMade")
    local np = C_NamePlate.GetNamePlateForUnit("nameplate1")
    function np:IsForbidden() return true end
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    T.eq(#made, 0)
    T.isnil(DUI.API.GetNameplate("nameplate1"))
end)

T.test("api plates: a restyle tells every plate on show", function()
    local DUI, ns = plateLoad()
    local styled = recorder(DUI.API, "FrameStyled")
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
    ns.Manager.Refresh()
    T.eq(#styled, 2)
    T.eq(styled[1][1], "nameplate")
    T.eq(styled[1][4], false)
end)

T.test("api plates: the options page's sample plates are previews", function()
    local DUI = plateLoad()
    local made = recorder(DUI.API, "FrameMade")
    local removed = recorder(DUI.API, "FrameRemoved")
    local P = DUI.OptionsPanel
    P.Show("Nameplates.plates")
    local s = P.Strip().Sample()
    T.eq(#made, 1)
    T.eq(made[1][1], "nameplate")
    T.eq(made[1][2], s.p)
    T.isnil(made[1][3])
    T.eq(made[1][4], true)
    P.Show("Nameplates.cast")
    T.truthy(#removed >= 1, "leaving the page takes its sample down")
    T.eq(removed[1][2], s.p)
    T.eq(removed[1][4], true)
    for frame in DUI.API.Frames("nameplate") do T.truthy(false, "a preview was listed") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: no listener, a plate costs nothing extra", function()
    local DUI, ns = plateLoad(40)
    local calls = 0
    local safe = DUI.SafeCallAs
    DUI.SafeCallAs = function(...) calls = calls + 1; return safe(...) end
    for i = 1, 40 do stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
    T.eq(DUI.API.GetNameplate("nameplate40"), ns.Manager.byUnit.nameplate40, "found even with nobody listening")
    for i = 1, 40 do stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
    DUI.SafeCallAs = safe
    T.eq(calls, 0, "no handler was called")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api plates: a sample shown again is not made again", function()
    local DUI = plateLoad()
    local made = recorder(DUI.API, "FrameMade")
    local changed = recorder(DUI.API, "FrameUnitChanged")
    local removed = recorder(DUI.API, "FrameRemoved")
    local P = DUI.OptionsPanel
    P.Show("Nameplates.plates")
    local s = P.Strip().Sample()
    P.Show("Nameplates.cast")
    P.Show("Nameplates.plates")
    local n = 0
    for _, c in ipairs(made) do if c[2] == s.p then n = n + 1 end end
    T.eq(n, 1, "exactly one FrameMade for the sample plate")
    T.truthy(#removed >= 1, "it was taken down when hidden")
    local again = false
    for _, c in ipairs(changed) do
        if c[2] == s.p and c[4] == true then
            again = true
            T.isnil(c[3], "the same unit as when it was made: none (a sample isn't your target)")
        end
    end
    T.truthy(again, "shown again is a unit change")
    P.Show("Nameplates.cast")
    local n2 = #removed
    T.isnil(removed[n2][3], "taken down with the unit it had")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Action buttons
-- ---------------------------------------------------------------------

T.test("api buttons: our action buttons are found by bar and slot", function()
    local ABW = require("abworld")
    local DUI, ns
    stub.Load({ actionbars = true, before = function() ABW.world() end })
    DUI, ns = DaylightUI, stub.actionbars
    local API = DUI.API
    T.eq(API.GetActionButton(1, 1), DaylightUIBar1Button1)
    T.eq(API.GetActionButton(1, 12), DaylightUIBar1Button12)
    T.eq(API.GetActionButton(2, 3), DaylightUIBar2Button3)
    T.isnil(API.GetActionButton(99, 1))
    -- By the addon's bar key too, the same button as its number, for every bar.
    T.eq(API.GetActionButton("main", 1), DaylightUIBar1Button1)
    T.eq(API.GetActionButton("bar2", 3), DaylightUIBar2Button3)
    for _, def in ipairs(ns.Bars.DEFS) do
        if def.kind == "action" then
            T.eq(API.GetActionButton(def.key, 1), API.GetActionButton(def.num, 1), def.key)
            T.truthy(API.GetActionButton(def.key, 1), def.key .. " found")
        end
    end
    T.isnil(API.GetActionButton("nope", 1))
    local n = 0
    for frame, unit in API.Frames("actionbutton") do
        n = n + 1
        T.eq(type(unit), "string")
    end
    T.eq(n, #ns.Buttons.All())
    -- a restyle says FrameStyled on every button
    local styled = recorder(API, "FrameStyled")
    ns.Bars.Refresh(ns.mod or DUI:GetModule("ActionBars"))
    stub.RunTimers()
    T.truthy(#styled >= n)
    T.eq(styled[1][1], "actionbutton")
    -- a plugin that loads later is told about the buttons already made
    local late = recorder(API, "FrameMade")
    local got
    for _, c in ipairs(late) do if c[2] == DaylightUIBar1Button1 then got = c end end
    T.eq(got[1], "actionbutton"); T.eq(got[3], "1:1"); T.eq(got[4], false)
end)
