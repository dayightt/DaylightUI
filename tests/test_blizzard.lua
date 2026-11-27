local stub = require("stub")

local function setup(before)
    local _, ns = stub.Load({ module = true, login = false, before = before })
    return ns
end

T.test("Hide silences, hides and re-parents a frame", function()
    local ns = setup()
    ns.Blizzard.Hide("PlayerFrame")
    T.falsy(PlayerFrame:IsShown())
    T.falsy(PlayerFrame:IsEventRegistered("UNIT_HEALTH"))
    T.eq(PlayerFrame:GetParent(), ns.Blizzard.hiddenParent)
end)

T.test("a protected frame is left alone in combat and hidden after", function()
    local ns = setup()
    stub.EnterCombat()
    ns.Blizzard.Hide("TargetFrame")
    T.truthy(TargetFrame:IsShown())
    stub.LeaveCombat()
    T.falsy(TargetFrame:IsShown())
    T.eq(TargetFrame:GetParent(), ns.Blizzard.hiddenParent)
end)

T.test("a frame the game re-parents is parked again after the event that did it (no hook on the frame)", function()
    local ns = setup()
    ns.Blizzard.Hide("FocusFrame")
    local before = rawget(FocusFrame, "SetParent")
    FocusFrame:SetParent(UIParent)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.eq(FocusFrame:GetParent(), ns.Blizzard.hiddenParent)
    T.eq(rawget(FocusFrame, "SetParent"), before, "nothing written onto the game's frame")
end)

T.test("re-parenting waits while Edit Mode is open", function()
    local ns = setup()
    local edit = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
    ns.Blizzard.Hide("PetFrame")
    PetFrame:SetParent(UIParent)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.eq(PetFrame:GetParent(), UIParent, "still waiting")
    edit:Hide()
    stub.RunTimers()
    T.eq(PetFrame:GetParent(), ns.Blizzard.hiddenParent)
end)

T.test("the cast bar is detached from its unit and hidden", function()
    local ns = setup()
    ns.Blizzard.HideCastBar("PlayerCastingBarFrame")
    T.truthy(PlayerCastingBarFrame.__setUnitCalled)
    T.isnil(PlayerCastingBarFrame.__castUnit)
    T.falsy(PlayerCastingBarFrame:IsShown())
    T.falsy(PlayerCastingBarFrame:IsEventRegistered("UNIT_SPELLCAST_START"))
end)

T.test("Apply hides only what DaylightUI replaces", function()
    local ns = setup()
    local db = DaylightUI.DB.MergeDefaults({ focus = { enabled = false } }, ns.DEFAULTS)
    ns.Blizzard.Apply(db)
    T.eq(PlayerFrame:GetParent(), ns.Blizzard.hiddenParent)
    T.eq(FocusFrame:GetParent(), UIParent)
    T.falsy(PlayerCastingBarFrame:IsShown())
end)

-- With "Lock to Player Frame" on in Edit Mode, the game's profession window
-- borrows a second player cast bar while you craft. Daylight UI's own player
-- cast bar already shows the craft, so that one must stay quiet too.
T.test("the profession window's borrowed cast bar stays hidden while crafting", function()
    local ns = setup()
    local db = DaylightUI.DB.MergeDefaults({}, ns.DEFAULTS)
    ns.Blizzard.Apply(db)
    local page = CreateFrame("Frame", nil, UIParent)
    OverlayPlayerCastingBarFrame:StartReplacingPlayerBarAt(page)
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.falsy(OverlayPlayerCastingBarFrame:IsShown() and OverlayPlayerCastingBarFrame:GetAlpha() > 0,
        "no second cast bar over the profession window")
    OverlayPlayerCastingBarFrame:EndReplacingPlayerBar()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the borrowed cast bar is left to the game when Daylight UI's player cast bar is off", function()
    local ns = setup()
    local db = DaylightUI.DB.MergeDefaults({ playerCastbar = { enabled = false } }, ns.DEFAULTS)
    ns.Blizzard.Apply(db)
    OverlayPlayerCastingBarFrame:StartReplacingPlayerBarAt(CreateFrame("Frame", nil, UIParent))
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
    T.truthy(OverlayPlayerCastingBarFrame:IsShown(), "the game's own craft bar still shows")
    OverlayPlayerCastingBarFrame:EndReplacingPlayerBar()
end)


T.test("a protected cast bar is left alone in combat and hidden after", function()
    local ns = setup()
    PlayerCastingBarFrame.__protected = true
    stub.EnterCombat()
    ns.Blizzard.HideCastBar("PlayerCastingBarFrame")
    T.truthy(PlayerCastingBarFrame:IsShown())
    T.falsy(PlayerCastingBarFrame.__setUnitCalled)
    stub.LeaveCombat()
    T.falsy(PlayerCastingBarFrame:IsShown())
    T.truthy(PlayerCastingBarFrame.__setUnitCalled)
end)

T.test("hiding the same frame twice is harmless", function()
    local ns = setup()
    ns.Blizzard.Hide("PlayerFrame")
    ns.Blizzard.Hide("PlayerFrame")
    PlayerFrame:SetParent(UIParent)
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(PlayerFrame:GetParent(), ns.Blizzard.hiddenParent)
end)

-- The controller's top bar opens the target menu through the game's own
-- TargetFrame_OpenMenu(TargetFrame), and the game's menu closes itself the frame
-- its owner isn't visible (Blizzard_Menu Menu.lua). So on a controller the game's
-- target frame has to stay visible, just see-through and click-through.
T.test("on a controller the game's target frame stays visible but unseen, so its menu opens", function()
    local ns = setup()
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    TargetFrame.__protected = true
    ns.Blizzard.Hide("TargetFrame")
    T.truthy(TargetFrame:IsVisible(), "the menu's owner is visible")
    T.eq(TargetFrame:GetEffectiveAlpha(), 0, "but not seen")
    T.falsy(TargetFrame:IsMouseEnabled(), "and takes no clicks")
    T.falsy(TargetFrame:IsEventRegistered("UNIT_HEALTH"))
    -- Back to the mouse: parked out of sight as before.
    _G.InputUtil, _G.GamepadMode = nil, nil
    DaylightUI.Fire("PadChanged")
    stub.RunTimers()
    T.falsy(TargetFrame:IsVisible())
    T.eq(TargetFrame:GetParent(), ns.Blizzard.hiddenParent)
    -- And again, in a fight: waits for it to end.
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
    stub.EnterCombat()
    DaylightUI.Fire("PadChanged")
    stub.RunTimers()
    T.falsy(TargetFrame:IsVisible(), "nothing protected moves in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(TargetFrame:IsVisible())
    _G.InputUtil, _G.GamepadMode = nil, nil
end)

T.test("with the mouse, the game's target frame is parked out of sight", function()
    local ns = setup()
    ns.Blizzard.Hide("TargetFrame")
    T.falsy(TargetFrame:IsVisible())
    T.eq(TargetFrame:GetParent(), ns.Blizzard.hiddenParent)
end)

-- The controller's directional party targeting (party targeting off in the
-- game's controller settings, and always in a raid) walks the game's own group
-- frames: RaidTargetingFreeSelection hands CompactPartyFrame (a child of
-- PartyFrame) or CompactRaidFrameContainer to SmartNavigation, which only stops
-- on visible buttons (IsButtonValid: IsVisible and IsRectValid), and the D-pad
-- Click()s the one it lands on. CompactPartyFrame is shown by the raid
-- manager's GROUP_ROSTER_UPDATE (CompactRaidFrameManager_UpdateContainerVisibility).
local function padOn()
    _G.InputUtil = { IsGamepadUIEnabled = function() return true end }
    _G.GamepadMode = { FrameControlsManager = { FrameShown = function() end, FrameHidden = function() end } }
end

local function padOff() _G.InputUtil, _G.GamepadMode = nil, nil end

-- The game's group frames as the client has them in a party: the party list
-- shown inside PartyFrame (its OnShow refreshes the game's controller footer),
-- the raid container hidden, both listening to the roster.
local function gameGroupFrames()
    local party = CreateFrame("Frame", "PartyFrame", UIParent)
    party:RegisterEvent("GROUP_ROSTER_UPDATE")
    local list = CreateFrame("Frame", "CompactPartyFrame", party)
    list.shows = 0
    list:SetScript("OnShow", function(self) self.shows = self.shows + 1 end)
    list.memberUnitFrames = {}
    for i, unit in ipairs({ "player", "party1", "party2" }) do
        local b = CreateFrame("Button", "CompactPartyFrameMember" .. i, list)
        b:SetAttribute("unit", unit)
        b:EnableMouse(true)
        list.memberUnitFrames[i] = b
    end
    local manager = CreateFrame("Frame", "CompactRaidFrameManager", UIParent)
    manager:RegisterEvent("GROUP_ROSTER_UPDATE")
    local container = CreateFrame("Frame", "CompactRaidFrameContainer", UIParent)
    container:RegisterEvent("GROUP_ROSTER_UPDATE")
    container:Hide()
    return party, list, manager, container
end

T.test("on a controller the game's party list stays visible but unseen, so the D-pad can walk it", function()
    local ns = setup()
    padOn()
    local party, list, manager, container = gameGroupFrames()
    ns.Blizzard.Apply(DaylightUI.DB.MergeDefaults({}, ns.DEFAULTS))
    stub.RunTimers()
    local member = list.memberUnitFrames[2]
    T.truthy(member:IsVisible(), "the game's navigation only stops on what it can see")
    T.eq(member:GetEffectiveAlpha(), 0, "but it isn't seen")
    T.falsy(member:IsMouseEnabled(), "and takes no clicks")
    T.eq(list.shows, 0, "never shown from Daylight UI's code: its OnShow is the game's controller footer")
    T.truthy(party:IsEventRegistered("GROUP_ROSTER_UPDATE"), "it keeps up with the roster")
    T.truthy(manager:IsEventRegistered("GROUP_ROSTER_UPDATE"), "the raid manager still shows the party list when a group forms")
    T.falsy(manager:IsVisible(), "while staying out of sight")
    T.truthy(container:IsEventRegistered("GROUP_ROSTER_UPDATE"), "the raid's list too")
    T.eq(container:GetParent(), ns.Blizzard.veil, "and it is seen-through when the game shows it in a raid")
    container:Show()
    T.eq(container:GetEffectiveAlpha(), 0)
    padOff()
end)

-- Seen in game: on joining a group or zoning, the game's own group buttons
-- answered IsMouseEnabled with a secret, and testing it stopped the update with
-- "boolean test on a secret boolean value". The fake game can't trap that test,
-- so this checks the question is never asked of the game's frames at all.
T.test("on a controller the game's group buttons go mouse-off without being asked whether they take the mouse", function()
    local ns = setup()
    padOn()
    local party, list = gameGroupFrames()
    local asked = 0
    local function counted(f)
        f.IsMouseEnabled = function() asked = asked + 1; return stub.Secret(true) end
    end
    counted(party); counted(list)
    for _, b in ipairs(list.memberUnitFrames) do counted(b) end
    ns.Blizzard.Apply(DaylightUI.DB.MergeDefaults({}, ns.DEFAULTS))
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.eq(asked, 0, "the game's answer can be secret: never read")
    for _, b in ipairs(list.memberUnitFrames) do T.eq(b.__mouse, false, "the member takes no clicks") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    padOff()
end)

T.test("on a controller the cursor sits on Daylight UI's tile of the same member, and skips members it doesn't show", function()
    local _, ns = stub.Load({ module = true })
    padOn()
    local anchors, ignored = {}, {}
    _G.CreateAnchor = function(point, rel, relPoint, x, y) return { point = point, rel = rel, relPoint = relPoint } end
    _G.SmartNavigation_SetCustomCursorAnchorPointForFrame = function(f, a)
        if stub.combat then error("refused in a fight") end
        anchors[f] = a
    end
    _G.SmartNavigation_MarkFrameIgnored = function(f) ignored[f] = true end
    _G.SmartNavigation_ClearIgnoreStatus = function(f) ignored[f] = nil end
    local _, list = gameGroupFrames()
    ns.Blizzard.Apply(DaylightUI.DB.MergeDefaults({}, ns.DEFAULTS))
    local h = ns.Party.header
    local tiles = {}
    for i, unit in ipairs({ "party2", "party1" }) do
        local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton" .. i, h)
        b:SetAttribute("unit", unit)
        h.initialConfigFunction(h, b:GetName())
        tiles[unit] = b
    end
    h:Show()
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    local m = list.memberUnitFrames
    T.truthy(anchors[m[2]], "party1 has a cursor spot")
    T.eq(anchors[m[2]] and anchors[m[2]].rel, tiles.party1, "on Daylight UI's party1 tile")
    T.eq(anchors[m[3]] and anchors[m[3]].rel, tiles.party2)
    T.truthy(ignored[m[1]], "you aren't in Daylight UI's party list by default, so the D-pad skips you")
    -- The roster changes in a fight: the spots wait for it to end (the game refuses them).
    stub.EnterCombat()
    tiles.party1:SetAttribute("unit", "party2")
    tiles.party2:SetAttribute("unit", "party1")
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(anchors[m[2]] and anchors[m[2]].rel, tiles.party2, "moved after the fight")
    _G.CreateAnchor, _G.SmartNavigation_SetCustomCursorAnchorPointForFrame = nil, nil
    _G.SmartNavigation_MarkFrameIgnored, _G.SmartNavigation_ClearIgnoreStatus = nil, nil
    padOff()
end)

-- Two pieces of the game's CompactUnitFrameTemplate ignore their parents' alpha
-- in its XML (CompactUnitFrame.xml): the target box (selectionHighlight, atlas
-- RaidFrame-TargetFrame, shown while the member is your target) and the ready
-- check icon. Inside the see-through frame they still showed at the game's spot:
-- the D-pad targets a member, and an empty box lit up where the game's party
-- frame would be (a player's report on a controller).
local function gamePieces(b)
    local box = b:CreateTexture(nil, "OVERLAY")
    box:SetIgnoreParentAlpha(true)
    box:Hide()
    b.selectionHighlight = box
    local ready = CreateFrame("Frame", nil, b)
    ready:SetIgnoreParentAlpha(true)
    ready.Icon = ready:CreateTexture()
    ready.Icon:SetIgnoreParentAlpha(true)
    b.readyCheckIcon = ready
    return box, ready
end

T.test("on a controller the game's target box and ready check icon stay unseen, party and raid", function()
    local _, ns = stub.Load({ module = true })
    padOn()
    local _, list, _, container = gameGroupFrames()
    local box, ready = gamePieces(list.memberUnitFrames[2])
    -- The game's hover mode box (GroupTargeting.lua), drawn round the game's button.
    local hoverBox = CreateFrame("Frame", nil, UIParent)
    _G.GroupTargeting = { TargetHighlight = hoverBox }
    ns.Blizzard.Apply(DaylightUI.DB.MergeDefaults({}, ns.DEFAULTS))
    stub.RunTimers()
    box:Show() -- the D-pad targets party1
    T.truthy(box:IsVisible())
    T.eq(box:GetEffectiveAlpha(), 0, "the game's target box isn't seen where the game's frame sits")
    T.eq(ready:GetEffectiveAlpha(), 0, "nor its ready check icon")
    T.eq(ready.Icon:GetEffectiveAlpha(), 0)
    T.eq(hoverBox:GetEffectiveAlpha(), 0, "nor the hover mode's box of lines")
    -- A raid member joins in a fight: the raid container makes the button then.
    container:Show()
    stub.EnterCombat()
    local raidButton = CreateFrame("Button", "CompactRaidFrame1", container)
    raidButton:SetAttribute("unit", "raid2")
    local raidBox = gamePieces(raidButton)
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    stub.LeaveCombat()
    stub.RunTimers()
    raidBox:Show()
    T.eq(raidBox:GetEffectiveAlpha(), 0, "a raid member's box after the fight too")
    _G.GroupTargeting = nil
    padOff()
end)

T.test("with the mouse, the game's group frames are parked and silenced as before", function()
    local ns = setup()
    local party, list, manager = gameGroupFrames()
    ns.Blizzard.Apply(DaylightUI.DB.MergeDefaults({}, ns.DEFAULTS))
    T.falsy(list.memberUnitFrames[2]:IsVisible())
    T.falsy(party:IsEventRegistered("GROUP_ROSTER_UPDATE"))
    T.falsy(manager:IsEventRegistered("GROUP_ROSTER_UPDATE"))
end)
