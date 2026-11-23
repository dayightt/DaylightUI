local stub = require("stub")
local LW = require("cdmlayoutworld")
local H = require("helpers")
local data, filled, oldLayout = LW.data, LW.filled, LW.oldLayout
local fakeViewer, fakeRegistry = LW.fakeViewer, LW.fakeRegistry
local rowsWorld, layoutFrame, pieceFrame, changeSpecTo = LW.rowsWorld, LW.layoutFrame, LW.pieceFrame, LW.changeSpecTo
local eased, settledPass, shownPieceIds = LW.eased, LW.settledPass, LW.shownPieceIds
local garbageMadeBy = H.garbageMadeBy
local countCalls = H.countCalls
local recordTooltips, visibleMenuRowOf, menuRowOf = H.recordTooltips, H.visibleMenuRowOf, H.menuRowOf
local countBlockedActions, indexOf = H.countBlockedActions, H.indexOf
local moveLead, lead, hangOff = LW.moveLead, LW.lead, LW.hangOff
local expectAnchor, recordReveals = H.expectAnchor, H.recordReveals
local pressEditorKey, stepEditor, dragGroup, selectAndSettle = LW.pressEditorKey, LW.stepEditor, LW.dragGroup, LW.selectAndSettle

-- Cooldown Manager groups attached to other frames (DaylightUI_ActionBars/CdmTether.lua).

local function expectNoErrorsLogged() T.eq(#stub.errors, 0, tostring(stub.errors[1])) end

-- Also fails on a logged error. Loading a world wipes the log, so world builders check it first.
local function test(name, run)
    T.test(name, function()
        run()
        expectNoErrorsLogged()
    end)
end

local function tetherFrame(g, root) return _G["DaylightUICdmTether" .. g .. "_" .. tostring(root)] end

-- UIParent units from the screen's center, worked out by hand: the fake client resolves no anchors.
local function screenTopLeft(frame)
    local point, relative, relativePoint, offsetX, offsetY = frame:GetPoint(1)
    assert(point == "TOPLEFT", "anchored by its top-left, got " .. tostring(point))
    if relative == layoutFrame(1) or relative == layoutFrame(2) then
        assert(relativePoint == "CENTER", "off the layout frame's center")
        return offsetX, offsetY
    end
    local name, baseX, baseY = relative.GetName and relative:GetName()
    if type(name) == "string" and name:find("^DaylightUICdmTether") then
        assert(relativePoint == "TOPLEFT", "off the tether frame's top-left")
        baseX, baseY = screenTopLeft(relative)
    else
        baseX, baseY = stub.actionbars.CdmTether.PointAt(relative, relativePoint)
    end
    return baseX + offsetX, baseY + offsetY
end

local function offsetFromLeadTop(frame, leadFrame)
    local x, y = screenTopLeft(frame)
    local leadX, leadY = stub.actionbars.CdmTether.PointAt(leadFrame, "TOP")
    return x - leadX, y - leadY
end

-- Between from and to within a pixel as the pass lands, strictly between partway, on to once settled.
local function expectGlidesOnScreen(AB, frame, from, to, context)
    local function expectBetween(moment, strictlyWhereApart)
        local spot = { screenTopLeft(frame) }
        for axis = 1, 2 do
            local low, high = math.min(from[axis], to[axis]), math.max(from[axis], to[axis])
            local between
            if strictlyWhereApart and high - low > 2 then
                between = spot[axis] > low + 1 and spot[axis] < high - 1
            else
                between = spot[axis] >= low - 1 and spot[axis] <= high + 1
            end
            T.truthy(between, string.format("%s, %s: axis %d at %.1f, not between %.1f and %.1f",
                context, moment, axis, spot[axis], from[axis], to[axis]))
        end
    end
    stub.RunTimers()
    expectBetween("as the pass lands")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), DaylightUI.Motion.NORMAL / 2)
    expectBetween("partway through the glide", true)
    settledPass(AB)
    local x, y = screenTopLeft(frame)
    T.near(x, to[1], 1, context .. ", settled: x")
    T.near(y, to[2], 1, context .. ", settled: y")
end

local function hasTetherField(chain)
    if type(chain) ~= "table" then return false end
    for _, key in ipairs({ "tether", "tetherAt", "tetherX", "tetherY" }) do
        if chain[key] ~= nil then return true end
    end
    return false
end

local ATTACHED_X, ATTACHED_Y = -150, 20
local SPOT_X, SPOT_Y = -200, 150
-- From the first icon's top-left to the middle of three 36 px icons, 4 apart.
local GROUP_MIDDLE_X, GROUP_MIDDLE_Y = 58, -18

local function attach(D, set, key, root)
    root = root or 11
    D.SetChainValue(set, root, "tether", key)
    D.SetChainValue(set, root, "tetherAt", "TOP")
    D.SetChainValue(set, root, "tetherX", ATTACHED_X)
    D.SetChainValue(set, root, "tetherY", ATTACHED_Y)
end

local function attachInEditor(world, key, root)
    T.truthy(world.Tether.Attach(world.set, root or 11, key), "attached to " .. tostring(key))
    world.Ed.Changed()
end

local function secondLead()
    local frame = lead("test.lead2", 400, 300, 100, 60)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 450, 330)
    return frame
end

-- A 1920 x 1080 screen; "test.lead" hangs by its TOP at the screen's center.
local function tetherWorld(options)
    expectNoErrorsLogged()
    options = options or {}
    local inEditor = options.editor or options.pick or options.twoLeads or options.editorLead
    local DUI, AB, ess, _, _, UF = rowsWorld(options.buffIcons, { module = options.unitFrames, buffs = options.buffs })
    UIParent.__w, UIParent.__h = 1920, 1080
    local world = { DUI = DUI, AB = AB, D = AB.CdmData, Tether = AB.CdmTether, Ed = AB.CdmEditor, ess = ess, UF = UF,
        Personal = UF and UF.Personal }
    if options.lead ~= false then
        world.lead = lead("test.lead", 860, 500, 200, 40)
        world.lead:ClearAllPoints()
        world.lead:SetPoint("TOP", UIParent, "BOTTOM", 0, 540)
    end
    if options.personal == "on" then DUI:Set("UnitFrames", "personal.enabled", true) end
    if options.personal == "off" then moveLead(world.Personal.frame, 860, 300, 200, 40) end
    world.set = world.D.Current()
    local spot = inEditor and { SPOT_X, SPOT_Y } or { 50, -20 }
    world.D.AddChain(world.set, options.ids or { 11, 12, 13 }, "icon", spot[1], spot[2], options.side)
    if options.attached then attach(world.D, world.set, options.attached) end
    if inEditor then T.truthy(world.Ed.Open(), "the editor opens") end
    if options.editorLead then attachInEditor(world, options.editorLead) end
    world.Tether.Stale()
    settledPass(AB)
    if options.pick then
        world.Ed.Select(11)
        AB.CdmCard.SetTab("chain")
        for _, row in ipairs(AB.CdmCard.ROWS.chain) do
            if row.item and row.item.key == "cdm.card.chain.tether" then world.row = row end
        end
    end
    if options.atOffset then
        DUI.Movers.GRID = 16
        moveLead(world.lead, 700, 300, 200, 40)
        attachInEditor(world, "test.lead")
        world.D.SetChainValue(world.set, 11, "tetherX", ATTACHED_X)
        world.D.SetChainValue(world.set, 11, "tetherY", ATTACHED_Y)
        world.Tether.Follow(world.set)
    end
    if options.twoLeads then
        world.secondLead = secondLead()
        attachInEditor(world, "test.lead")
        world.D.AddChain(world.set, { 21, 22 }, "icon", 300, -200)
        attachInEditor(world, "test.lead2", 21)
    end
    return world
end

local function savedSpot(set, id) return { set.pieces[id].x, set.pieces[id].y } end


local function followInstead(world, key)
    world.D.SetChainValue(world.set, 11, "tether", key)
    world.Tether.Stale()
end

local function isCdmRowsScript(handler)
    return debug.getinfo(handler, "S").short_src:find("CdmRows%.lua") ~= nil
end

local function expectNothingRunsEachFrame(context)
    for _, frame in ipairs(stub.frames) do
        local onUpdate = frame.__scripts and frame.__scripts.OnUpdate
        if onUpdate and isCdmRowsScript(onUpdate) then
            T.falsy(frame:IsShown(), context .. ": a Cooldown Manager row script runs each frame")
        end
    end
end

-- Off its layout frame where the lead's point plus the offset is.
local function expectPlaced(tether, leadFrame, at, x, y, context)
    local pointX, pointY = stub.actionbars.CdmTether.PointAt(leadFrame, at)
    expectAnchor(tether, { "TOPLEFT", tether:GetParent(), "CENTER", pointX + x, pointY + y }, context)
end

local function expectHung(tether, leadFrame, at, x, y, context)
    expectAnchor(tether, { "TOPLEFT", leadFrame, at, x, y }, context)
end

local function isHungOff(tether, leadFrame) return select(2, tether:GetPoint(1)) == leadFrame end

-- Hung off the lead at the offset, or placed off its layout frame where that puts it.
local function expectFollows(tether, leadFrame, at, x, y, context)
    if isHungOff(tether, leadFrame) then
        expectHung(tether, leadFrame, at, x, y, context .. ", hung off it")
    else
        expectPlaced(tether, leadFrame, at, x, y, context)
    end
end

local function anchorReaches(frame, target)
    for index = 1, frame:GetNumPoints() do
        local _, relative = frame:GetPoint(index)
        if relative == target or (relative and relative.GetNumPoints and anchorReaches(relative, target)) then
            return true
        end
    end
    return false
end

local function expectNothingAnchoredTo(target, frames, context)
    for _, frame in ipairs(frames) do
        T.falsy(anchorReaches(frame, target), context .. ": " .. tostring(frame:GetName()) .. " isn't anchored to it")
    end
end

-- As a plugin switched off mid-session leaves it. Giving it back fires no event.
local function loseMover(DUI, key)
    local realGet, realKeys, lost = DUI.Movers.Get, DUI.Movers.Keys, true
    DUI.Movers.Get = function(askedKey)
        if lost and askedKey == key then return nil end
        return realGet(askedKey)
    end
    DUI.Movers.Keys = function()
        local keys = {}
        for _, registered in ipairs(realKeys()) do
            if not (lost and registered == key) then keys[#keys + 1] = registered end
        end
        return keys
    end
    return function() lost = false end
end

-- Leads that can't be read safely; measurable: its rectangle still can be.
local HOSTILE_LEADS = {
    secret = { measurable = false, make = function(frame)
        frame.__secretAnchoring = true
        frame.__center = { stub.Secret(960), stub.Secret(520) }
    end },
    erroring = { measurable = false, make = function(frame)
        local function broken() error("a plugin's frame that broke") end
        frame.GetPoint, frame.GetCenter = broken, broken
    end },
    restricted = { measurable = true, make = function(frame) frame.IsAnchoringRestricted = function() return true end end },
}

local function pickFromList(world, key)
    world.row.frame.control:Click()
    local listed = menuRowOf(world.DUI.Widgets, key)
    T.truthy(listed, tostring(key) .. " is in the list")
    listed:Click()
end

local function measuredFromText(DUI, leadName)
    return DUI.L["Measured from %s, at its anchor point (%s). If that frame takes the group past a screen edge, the group stops at the edge and comes back when it can."]
        :format(leadName, DUI.Movers.AnchorLabels()["TOP"])
end

local function headingsOf(values, keys, titles)
    local headingOf, headings, heading = {}, {}, nil
    for _, key in ipairs(keys) do
        if titles[key] then
            heading = values[key]
            headings[#headings + 1] = heading
        else
            headingOf[key] = heading
        end
    end
    return headingOf, headings
end

-- Once any fade has run its course.
local function shownLeadRings(Ed)
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), DaylightUI.Motion.FAST)
    local ring = Ed.LeadRing()
    if ring and ring:IsShown() then return { ring } end
    return {}
end

-- Round a frame when it sits GROUP_PAD outside that frame's top-left.
local function ringRound(Ed, leadFrame)
    local left, top = stub.actionbars.CdmTether.PointAt(leadFrame, "TOPLEFT")
    for _, ring in ipairs(shownLeadRings(Ed)) do
        local _, _, _, x, y = ring:GetPoint(1)
        if left and x == left - Ed.GROUP_PAD and y == top + Ed.GROUP_PAD then return ring end
    end
    return nil
end

-- A gradient accent colors letter by letter on white.
local function expectAccentText(DUI, fontString, plainText, context)
    local accentText, coloredByLetter = DUI.Style.AccentText(plainText)
    T.eq(fontString:GetText(), accentText, context .. ": its text")
    local color = coloredByLetter and { 1, 1, 1 } or { DUI.Style.Accent() }
    T.rgb({ fontString:GetTextColor() }, color, context .. ": its color")
end

test("cdm tether: a group saves only a valid lead, lead point and offset, nothing while it follows nothing, and its pieces read it", function()
    local D = data()
    local Tether = stub.actionbars.CdmTether
    local set = filled(D)
    T.deq({ D.ChainValue(set, 11, "tether"), D.ChainValue(set, 11, "tetherAt"), D.ChainValue(set, 11, "tetherX"),
        D.ChainValue(set, 11, "tetherY") }, { false, "CENTER", 0, 0 }, "a new group follows nothing, at no offset")
    T.falsy(hasTetherField(set.chains[11]), "nothing saved for a new group")
    local longestKey = string.rep("k", 128)
    T.truthy(D.SetChainValue(set, 11, "tether", longestKey), "a lead key of 128 characters is accepted")
    T.truthy(D.SetChainValue(set, 11, "tetherAt", "TOP"))
    local refusedValues = { tether = string.rep("k", 129), tetherAt = "MIDDLE", tetherX = 0 / 0 }
    for field, refused in pairs(refusedValues) do
        T.eq(D.SetChainValue(set, 11, field, refused), false, field .. " " .. tostring(refused) .. " is refused")
    end
    T.deq({ set.chains[11].tether, D.ChainValue(set, 11, "tetherAt"), D.ChainValue(set, 11, "tetherX") },
        { longestKey, "TOP", 0 }, "unchanged after the refusals")
    T.truthy(D.SetChainValue(set, 11, "tetherY", 5000))
    T.eq(D.ChainValue(set, 11, "tetherY"), 4096, "an offset is held within 4096")
    T.truthy(D.SetChainValue(set, 11, "tether", false))
    T.isnil(set.chains[11].tether, "false is the default, so nothing is saved")

    local hooked = filled(D)
    D.AddChain(hooked, { 21, 22 }, "icon", 0, -100)
    D.SetChainValue(hooked, 11, "tether", "unitframes.personal")
    D.SetChainValue(hooked, 11, "tetherAt", "TOP")
    D.SetChainValue(hooked, 11, "tetherX", -120)
    D.SetChainValue(hooked, 21, "tether", "test.lead")
    T.deq({ Tether.Of(hooked, 12) }, { "unitframes.personal", -120, 0, "TOP" }, "every piece reads its group's attachment")
    T.truthy(D.Hook(hooked, 21, 13, "right"))
    T.deq({ Tether.Of(hooked, 21) }, { "unitframes.personal", -120, 0, "TOP" }, "it follows the receiving group's lead")
    rawset(hooked.chains[11], "tether", 42)
    T.isnil((Tether.Of(hooked, 12)), "a malformed lead reads as none")

    D.SetChainValue(set, 11, "tether", "unitframes.personal")
    D.RemoveChain(set, 11)
    T.isnil(set.chains[11], "removing the group removes its attachment")
end)

test("cdm tether: a malformed saved attachment value reads as nothing or the default, and laying out with it raises no error", function()
    local savedAttachments = {
        { { tether = 42, tetherAt = "TOP", tetherX = 10, tetherY = -4 }, {} },
        { { tether = {} }, {} },
        { { tether = "" }, {} },
        { { tether = string.rep("k", 129) }, {} },
        { { tether = "a\0b" }, {} },
        { { tether = "test.lead", tetherAt = "MIDDLE", tetherX = 10, tetherY = -4 }, { "test.lead", 10, -4, "CENTER" } },
        { { tether = "test.lead", tetherX = "x", tetherY = 0 / 0 }, { "test.lead", 0, 0, "CENTER" } },
        { { tether = "test.lead", tetherX = math.huge, tetherY = -math.huge }, { "test.lead", 0, 0, "CENTER" } },
    }
    for index, case in ipairs(savedAttachments) do
        local world = tetherWorld()
        local chain = world.D.Chain(world.set, 11)
        for key, value in pairs(case[1]) do chain[key] = value end
        world.Tether.Stale()
        T.noerror(function() settledPass(world.AB) end, "saved group " .. index .. " lays out")
        T.deq({ world.Tether.Of(world.set, 11) }, case[2], "saved group " .. index .. " reads")
    end
end)

test("cdm tether: a lead hung off the layout would loop; any other lead, however it hangs or however hostile, is read without an error", function()
    local world = tetherWorld({ ids = { 11, 12 }, lead = false })
    local Tether = world.Tether
    local onPiece = lead("plugin.Test.onPiece")
    hangOff(onPiece, pieceFrame(1, 12))
    hangOff(lead("plugin.Test.onLead"), onPiece)
    local link = lead("test.deep")
    for _ = 1, 25 do
        local nextLink = CreateFrame("Frame", nil, UIParent)
        hangOff(link, nextLink)
        link = nextLink
    end
    hangOff(link, UIParent)
    local cycleStart, cycleEnd = lead("test.cycle"), CreateFrame("Frame", nil, UIParent)
    hangOff(cycleStart, cycleEnd)
    hangOff(cycleEnd, cycleStart)
    local brokenCount = lead("plugin.Test.brokenCount")
    hangOff(brokenCount, pieceFrame(1, 12))
    brokenCount.GetNumPoints = function() error("a plugin's frame that broke") end
    lead("test.twoPoints"):SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
    local expectations = {
        { "plugin.Test.onPiece", "loop" }, { "plugin.Test.onLead", "loop" },
        { "test.deep", "ready", "TOP" }, { "test.cycle", "ready", "TOP" },
        { "plugin.Test.brokenCount", "ready", "CENTER" },
        { "test.twoPoints", "ready", "CENTER" },
        { "plugin.Gone.frame", "missing" },
    }
    for name, hostile in pairs(HOSTILE_LEADS) do
        local key = "test.hostile." .. name
        local frame = lead(key, 860, 200, 200, 40)
        hangOff(frame, pieceFrame(1, 12))
        hostile.make(frame)
        expectations[#expectations + 1] = { key, "ready", "CENTER" }
        T.eq((Tether.PointAt(frame, "TOP")) ~= nil, hostile.measurable, key .. ": its point read only when it can be")
    end
    for _, expected in ipairs(expectations) do
        local key, state, hang = expected[1], expected[2], expected[3]
        T.eq(Tether.State(key), state, key)
        local frame, hangPoint = Tether.Lead(key)
        T.eq(hangPoint, hang, key .. " hangs by")
        T.eq(frame ~= nil, hang ~= nil, key .. " gives its frame only when it can be followed")
    end
end)

test("cdm tether: a lead's point is measured in UIParent units as Unlock Frames measures it, or not at all", function()
    local world = tetherWorld({ lead = false })
    local DUI, Tether = world.DUI, world.Tether
    local frame = lead("test.lead", 860, 200, 200, 40)
    frame:SetScale(0.5)
    local function expectSameAsUnlockFrames(context)
        local toUIParent = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local frameX, frameY = frame:GetCenter()
        local centerX = frameX * toUIParent - UIParent:GetWidth() / 2
        local centerY = frameY * toUIParent - UIParent:GetHeight() / 2
        local width, height = frame:GetWidth() * toUIParent, frame:GetHeight() * toUIParent
        for point in pairs(DUI.Movers.ANCHOR_SIGN) do
            local expectedX, expectedY = DUI.Movers.PointOf(point, centerX, centerY, width, height)
            local x, y = Tether.PointAt(frame, point)
            T.near(x, expectedX, 1e-6, context .. ", " .. point .. ": x")
            T.near(y, expectedY, 1e-6, context .. ", " .. point .. ": y")
        end
    end
    expectSameAsUnlockFrames("lead at half scale")
    stub.SetScreen(1920, 1080, 0.8)
    frame:SetScale(1.25)
    expectSameAsUnlockFrames("a smaller UI scale and a larger lead")
    T.isnil((Tether.PointAt(lead("test.unplaced"), "TOP")), "no point for a lead never placed")
end)

local function preUpdateWorld()
    expectNoErrorsLogged()
    local DUI = stub.Load({ actionbars = true, before = function()
        fakeRegistry()
        fakeViewer("EssentialCooldownViewer", { 11, 12, 13, 200265 })
        fakeViewer("BuffBarCooldownViewer", { 21, 22 })
        _G.GetRealmName = function() return "R" end
        stub.units.player = { name = "Tester", isPlayer = true, class = "WARRIOR" }
    end })
    stub.RunTimers()
    return DUI, stub.actionbars
end

local PRE_UPDATE_FILES = {
    oldLayouts = function()
        local DUI, AB = preUpdateWorld()
        oldLayout(DUI, AB.CdmData, 1, { v = 2, chains = { [11] = { grow = "center", spacing = 6 } }, pieces = {
            [11] = { shape = "icon", x = -150, y = -90 },
            [12] = { shape = "icon", parent = 11, side = "right", align = "center" },
            [21] = { shape = "bar", x = 120, y = -60 } } })
        oldLayout(DUI, AB.CdmData, 2, { v = 2, chains = {}, pieces = { [13] = { shape = "icon", x = 40, y = 200 } } })
        return DUI, AB
    end,
}

test("cdm tether: layouts saved before the update load following nothing, play as before and are never rewritten", function()
    for name, load in pairs(PRE_UPDATE_FILES) do
        local DUI, AB = load()
        local D, R, Tether = AB.CdmData, AB.CdmRows, AB.CdmTether
        D.Get(1); D.Get(2)
        local savedAfterLoad = DaylightUI.DB.Copy(DaylightUIDB.cdmProfiles)
        for g = 1, 2 do
            DUI.DB.SpecGroup = function() return g end
            R.Refresh(); stub.RunTimers()
            stub.EnterCombat(); stub.RunTimers()
            R.Update()
            stub.LeaveCombat(); stub.RunTimers()
        end
        local piecesShown = 0
        for g = 1, 2 do
            DUI.DB.SpecGroup = function() return g end
            R.Refresh(); stub.RunTimers()
            local set, layout = D.Get(g), layoutFrame(g)
            for root, chain in pairs(set.chains) do
                T.falsy(hasTetherField(chain), name .. ": group " .. tostring(root) .. " saves no attachment")
            end
            T.falsy(layout:IsClampedToScreen(), name .. ": the layout frame isn't clamped")
            local shown = shownPieceIds(set, g)
            local boxes = D.Layout(set, shown)
            for id in pairs(set.pieces) do
                local context = name .. ", piece " .. tostring(id)
                T.isnil((Tether.Of(set, id)), context .. " follows no frame")
                T.isnil(tetherFrame(g, id), context .. ": no tether frame")
            end
            for id in pairs(shown) do
                local frame, context = pieceFrame(g, id), name .. ", piece " .. tostring(id)
                T.deq({ frame:GetPoint(1) }, { "TOPLEFT", layout, "CENTER", boxes[id].x, boxes[id].y }, context)
                T.falsy(frame:IsClampedToScreen(), context .. " isn't clamped")
                piecesShown = piecesShown + 1
            end
        end
        T.truthy(piecesShown > 0, name .. ": some piece shows")
        T.deq(DaylightUIDB.cdmProfiles, savedAfterLoad, name .. ": play writes nothing")
        _G.GetRealmName = nil
    end
end)

local function flickerEachIcon(world)
    for index = 1, 3 do
        world.ess[index]:Hide()
        settledPass(world.AB)
        world.ess[index]:Show()
        settledPass(world.AB)
    end
end

-- Where camera zoom and mounting carry the Personal Display.
local LEAD_SPOTS = { { 860, 380 }, { 900, 620 }, { 1500, 1000 } }

-- As the player frame is: a secure frame can't be anchored to.
local function protectLead(world)
    world.lead.IsProtected = function() return true end
    settledPass(world.AB)
end

test("cdm tether: a group on an unprotected Daylight UI frame hangs straight off it at its point plus the offset, carried in or out of a fight with nothing running, writing nothing", function()
    local world = tetherWorld({ attached = "test.lead" })
    local set, leadFrame = world.set, world.lead
    local savedBefore = DaylightUI.DB.Copy(set)
    local tether = tetherFrame(1, 11)
    T.truthy(tether:IsClampedToScreen())
    expectHung(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, "attached")
    expectNothingRunsEachFrame("hung")
    local cleared, pointed = countCalls(tether, "ClearAllPoints"), countCalls(tether, "SetPoint")
    for index, spot in ipairs(LEAD_SPOTS) do
        local context = "spot " .. index
        moveLead(leadFrame, spot[1], spot[2], 200, 40)
        if index % 2 == 0 then stub.EnterCombat() else stub.LeaveCombat() end
        stub.RunTimers()
        T.deq({ offsetFromLeadTop(pieceFrame(1, 11), leadFrame) }, { ATTACHED_X, ATTACHED_Y }, context)
    end
    stub.LeaveCombat(); stub.RunTimers()
    flickerEachIcon(world)
    T.eq(cleared.calls + pointed.calls, 0, "the lead carries it: the tether is never moved by hand")
    T.deq(set, savedBefore, "play writes nothing")
end)

-- Each moves the lead as Unlock Frames does; the fake client moves no frame by its anchor.
local UNLOCK_FRAMES_MOVES = {
    { "moved in Unlock Frames", function(Movers) Movers.SetExact("test.lead", 200, -100) end },
    { "nudged", function(Movers) Movers.Nudge("test.lead", 1, 0) end },
    { "everything reset", function(Movers) Movers.ResetAll() end },
}

test("cdm tether: a group on a protected lead is placed beside it when Unlock Frames places it or a frame it hangs off, or on the next pass after a move no event tells, never anchored to it and writing nothing", function()
    local world = tetherWorld({ attached = "test.lead" })
    local AB, set, leadFrame, Movers = world.AB, world.set, world.lead, world.DUI.Movers
    protectLead(world)
    local savedBefore = DaylightUI.DB.Copy(set)
    local tether = tetherFrame(1, 11)
    expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, "attached")
    expectNothingRunsEachFrame("placed")
    for index, step in ipairs(UNLOCK_FRAMES_MOVES) do
        local spot = LEAD_SPOTS[index]
        moveLead(leadFrame, spot[1], spot[2], 200, 40)
        step[2](Movers)
        stub.RunTimers(); eased(DaylightUI)
        expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, step[1])
    end
    local base = lead("test.base", 400, 300, 200, 40)
    hangOff(leadFrame, base)
    settledPass(AB)
    moveLead(leadFrame, 500, 200, 200, 40)
    Movers.SetExact("test.base", -300, -200)
    stub.RunTimers(); eased(DaylightUI)
    expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, "the frame it hangs off placed")
    for _, inFight in ipairs({ false, true }) do
        local context = inFight and "in a fight" or "out of a fight"
        if inFight then stub.EnterCombat(); stub.RunTimers() end
        local before = { tether:GetPoint(1) }
        moveLead(leadFrame, inFight and 900 or 1300, 620, 200, 40)
        stub.RunTimers()
        T.deq({ tether:GetPoint(1) }, before, context .. ": moved with no event, left until the next pass")
        settledPass(AB)
        expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, context .. ": the next pass")
    end
    stub.LeaveCombat(); stub.RunTimers()
    expectNothingAnchoredTo(leadFrame, { tether, pieceFrame(1, 11), pieceFrame(1, 12), pieceFrame(1, 13) }, "the lead")
    T.deq(set, savedBefore, "play writes nothing")
    hangOff(lead("plugin.Test.onTether"), tether)
    world.Tether.Stale()
    T.eq(world.Tether.State("plugin.Test.onTether"), "loop", "a frame hung off a tether frame would loop")
end)

test("cdm tether: a group on the party or raid frames is placed beside them when they're laid out again, the raid onto Raid 40's spot too", function()
    for _, key in ipairs({ "unitframes.party", "unitframes.raid" }) do
        local world = tetherWorld({ unitFrames = true, attached = key })
        local DUI, AB = world.DUI, world.AB
        local holder = DUI.Movers.Get(key).frame
        T.truthy(holder:IsProtected(), key .. ": its holder is protected")
        moveLead(holder, 400, 600, 200, 100)
        settledPass(AB)
        local tether = tetherFrame(1, 11)
        expectPlaced(tether, holder, "TOP", ATTACHED_X, ATTACHED_Y, key)
        if key == "unitframes.raid" then
            DUI:Set("UnitFrames", "raid40.ownSpot", true)
            settledPass(AB)
        end
        local laidOut = {}
        DUI.On("FrameLaidOut", function(laidOutKey) laidOut[laidOutKey] = true end)
        moveLead(holder, 600, 400, 300, 150)
        local refreshes = countCalls(AB.CdmRows, "Refresh")
        if key == "unitframes.raid" then
            world.UF.Raid.PlaceHolder(40)
        else
            local d = world.UF.module.db
            world.UF.Party.group:Layout(d.party, d.partyText, d.range)
        end
        T.truthy(refreshes.calls > 0, key .. ": laid out with nothing placed, a pass asked for")
        refreshes.restore()
        stub.RunTimers(); eased(DaylightUI)
        T.truthy(laidOut[key], key .. ": told it was laid out")
        expectPlaced(tether, holder, "TOP", ATTACHED_X, ATTACHED_Y, key .. ": laid out again")
    end
end)

test("cdm tether: a lead not there, gone or looping sits its group at its saved spot, attachment kept", function()
    local unfollowableLeads = {
        ["not there"] = function() end,
        ["gone mid-session"] = function(world)
            local leadFrame = lead("plugin.Late.frame", 860, 500, 200, 40)
            world.Tether.Stale(); settledPass(world.AB)
            expectFollows(tetherFrame(1, 11), leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, "following first")
            loseMover(world.DUI, "plugin.Late.frame")
        end,
        ["hung off another group"] = function(world)
            world.D.AddChain(world.set, { 21, 22 }, "icon", 0, -200)
            settledPass(world.AB)
            local loopingLead = lead("plugin.Late.frame")
            hangOff(loopingLead, pieceFrame(1, 21))
            local anchorings = {}
            local tether = tetherFrame(1, 11)
            local setPoint = tether.SetPoint
            tether.SetPoint = function(self, point, relative, ...)
                anchorings[#anchorings + 1] = relative
                return setPoint(self, point, relative, ...)
            end
            return function()
                for _, relative in ipairs(anchorings) do T.truthy(relative ~= loopingLead, "never anchored into the loop") end
            end
        end,
    }
    for name, makeUnfollowable in pairs(unfollowableLeads) do
        local world = tetherWorld({ lead = false, attached = "plugin.Late.frame" })
        local savedChain = DaylightUI.DB.Copy(world.set.chains[11])
        local checkAfter = makeUnfollowable(world)
        world.Tether.Stale()
        settledPass(world.AB)
        expectAnchor(tetherFrame(1, 11), { "TOPLEFT", layoutFrame(1), "CENTER", 50, -20 }, name)
        T.deq(world.set.chains[11], savedChain, name .. ": the attachment is kept")
        if checkAfter then checkAfter() end
    end
end)

local function passesAskedFor(AB, step)
    local refreshes = countCalls(AB.CdmRows, "Refresh")
    step()
    refreshes.restore()
    return refreshes.calls
end

test("cdm tether: a group placed from a plugin's or protected lead is never followed each frame, Unlock Frames open or closed, and opening or closing it asks for one pass only when such a group exists", function()
    local world = tetherWorld({ attached = "test.lead" })
    local AB, Movers = world.AB, world.DUI.Movers
    T.eq(passesAskedFor(AB, function() Movers.Unlock() end), 0, "only a hung group: opening asks for no pass")
    T.eq(passesAskedFor(AB, function() Movers.Lock() end), 0, "only a hung group: closing asks for no pass")
    stub.RunTimers()
    world.D.AddChain(world.set, { 21, 22 }, "icon", 0, -200)
    world.D.SetChainValue(world.set, 21, "tether", "plugin.Test.frame")
    local pluginLead = lead("plugin.Test.frame", 400, 300, 200, 40)
    world.Tether.Stale(); settledPass(AB)
    expectNothingRunsEachFrame("closed, a group hung and one placed")
    T.eq(passesAskedFor(AB, function() T.truthy(Movers.Unlock(), "Unlock Frames opens") end), 1, "opening asks for one pass")
    stub.RunTimers()
    expectNothingRunsEachFrame("open, a group placed from a lead")
    local placed = tetherFrame(1, 21)
    local before = { placed:GetPoint(1) }
    moveLead(pluginLead, 700, 500, 200, 40)
    stub.RunTimers()
    T.deq({ placed:GetPoint(1) }, before, "open: the lead moved with no event, the group stays put")
    protectLead(world)
    expectNothingRunsEachFrame("open, its other lead protected")
    T.eq(passesAskedFor(AB, function() Movers.Lock() end), 1, "closing asks for one pass")
    stub.RunTimers()
    expectNothingRunsEachFrame("closed")
end)

test("cdm tether: a group on our own unprotected lead with no position yet at the pass is hung off it all the same, and sits beside it once the lead has one, with no further pass and nothing running each frame", function()
    local world = tetherWorld({ attached = "test.lead" })
    local AB, leadFrame = world.AB, world.lead
    local tether = tetherFrame(1, 11)
    leadFrame.__center = nil
    world.Tether.Stale()
    settledPass(AB)
    expectHung(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, "no position yet: hung at its point plus the offset")
    expectNothingRunsEachFrame("no position yet")
    local refreshes = countCalls(AB.CdmRows, "Refresh")
    local cleared, pointed = countCalls(tether, "ClearAllPoints"), countCalls(tether, "SetPoint")
    moveLead(leadFrame, 900, 620, 200, 40)
    stub.RunTimers()
    T.deq({ offsetFromLeadTop(pieceFrame(1, 11), leadFrame) }, { ATTACHED_X, ATTACHED_Y }, "given a position: beside it")
    T.eq(refreshes.calls, 0, "given a position: no pass asked for")
    T.eq(cleared.calls + pointed.calls, 0, "given a position: the tether is never moved by hand")
    refreshes.restore()
    expectNothingRunsEachFrame("given a position")
end)

test("cdm tether: a group on our own lead whose tether reads protected is placed beside it, never hung, and placed again when Unlock Frames places the lead, with nothing running each frame", function()
    local world = tetherWorld({ attached = "test.lead" })
    local AB, leadFrame, Movers = world.AB, world.lead, world.DUI.Movers
    local tether = tetherFrame(1, 11)
    tether.IsProtected = function() return true end
    settledPass(AB)
    T.falsy(isHungOff(tether, leadFrame), "not hung")
    expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, "placed beside it")
    expectNothingRunsEachFrame("placed")
    for index, step in ipairs(UNLOCK_FRAMES_MOVES) do
        local spot = LEAD_SPOTS[index]
        moveLead(leadFrame, spot[1], spot[2], 200, 40)
        step[2](Movers)
        stub.RunTimers(); eased(DaylightUI)
        T.falsy(isHungOff(tether, leadFrame), step[1] .. ": not hung")
        expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, step[1])
        expectNothingRunsEachFrame(step[1])
    end
end)

test("cdm tether: the tether frame spans the pieces that show, holding them as they'd sit unattached, sized again only when they change", function()
    local world = tetherWorld({ ids = { 11, 12, 13, 21 }, attached = "test.lead" })
    local AB, set = world.AB, world.set
    local tether = tetherFrame(1, 11)
    moveLead(world.lead, 1700, 1040, 200, 40)
    settledPass(AB)
    for id, offsetX in pairs({ [11] = 0, [12] = 40, [13] = 80, [21] = 120 }) do
        expectAnchor(pieceFrame(1, id), { "TOPLEFT", tether, "TOPLEFT", offsetX, 0 }, "piece " .. id)
        T.eq(pieceFrame(1, id):GetParent(), layoutFrame(1), "piece " .. id .. " stays a child of the layout frame")
    end
    T.deq({ tether:GetSize() }, { 156, 36 }, "all shown")
    world.ess[2]:Hide()
    settledPass(AB)
    T.deq({ tether:GetSize() }, { 116, 36 }, "the middle one hidden")
    set.pieces[13].size = 48
    settledPass(AB)
    T.deq({ tether:GetSize() }, { 128, 48 }, "the last one bigger")
    local resized = countCalls(tether, "SetSize")
    settledPass(AB)
    stub.EnterCombat(); stub.RunTimers()
    settledPass(AB)
    T.eq(resized.calls, 0, "unchanged: not sized again")
    stub.LeaveCombat(); stub.RunTimers()
    world.ess[2]:Show()
    settledPass(AB)
    T.deq({ tether:GetSize() }, { 168, 48 }, "all shown again")
end)

test("cdm tether: an attached group's far piece hiding leaves the rest put on screen, or glides them as unattached when it closes up round its middle", function()
    local extentChanges = {
        ["growing left"] = { side = "left", firstPieceTo = { ATTACHED_X, ATTACHED_Y } },
        ["closing up round its middle"] = { grow = "center", firstPieceTo = { ATTACHED_X + 20, ATTACHED_Y } },
    }
    for name, change in pairs(extentChanges) do
        local world = tetherWorld({ side = change.side, attached = "test.lead" })
        if change.grow then world.D.SetChainValue(world.set, 11, "grow", change.grow) end
        settledPass(world.AB)
        local secondPieceX = ATTACHED_X + (change.side == "left" and -40 or 40)
        T.deq({ offsetFromLeadTop(pieceFrame(1, 12), world.lead) }, { secondPieceX, ATTACHED_Y }, name .. ": all shown")
        world.ess[3]:Hide()
        world.AB.CdmRows.Refresh()
        expectGlidesOnScreen(world.AB, pieceFrame(1, 11), { ATTACHED_X, ATTACHED_Y }, change.firstPieceTo, name)
    end
end)

test("cdm tether: a group with nothing showing or no longer attached hides its tether frame and its pieces snap back", function()
    local world = tetherWorld({ attached = "test.lead" })
    local AB, D, set = world.AB, world.D, world.set
    local tether, layout = tetherFrame(1, 11), layoutFrame(1)
    for index = 1, 3 do world.ess[index]:Hide() end
    settledPass(AB)
    T.falsy(pieceFrame(1, 11):IsShown(), "nothing of the group shows")
    T.falsy(tether:IsShown(), "nothing shows: its tether frame hides")
    for index = 1, 3 do world.ess[index]:Show() end
    settledPass(AB)
    D.SetChainValue(set, 11, "tether", false)
    AB.CdmRows.Refresh(); stub.RunTimers()
    expectAnchor(pieceFrame(1, 11), { "TOPLEFT", layout, "CENTER", 50, -20 }, "first piece, off the layout at once")
    attach(D, set, "test.lead")
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(tether:IsShown(), "attached again")
    expectAnchor(pieceFrame(1, 13), { "TOPLEFT", tether, "TOPLEFT", 80, 0 }, "last piece, into its tether frame at once")
end)

local LEAD_CHANGES = {
    ["a setting changing"] = function(DUI) DUI.Fire("SettingChanged", "general", "scale") end,
    ["an Unlock Frames frame placed"] = function(DUI) DUI.Fire("MoverApplied", "test.other") end,
    ["a fight ending"] = function() stub.FireEvent("PLAYER_REGEN_ENABLED") end,
}

test("cdm tether: a kept lead answer is worked out again after a setting changes, a frame is placed or a fight ends", function()
    for name, fireLeadChange in pairs(LEAD_CHANGES) do
        local DUI, AB = rowsWorld()
        local Tether = AB.CdmTether
        local optionalShown = false
        DUI.Movers.Register(CreateFrame("Frame", nil, UIParent), "test.optional", "Optional", { "CENTER", nil, "CENTER", 0, 0 },
            { active = function() return optionalShown end })
        T.eq(Tether.State("test.optional"), "off", name .. ": before")
        optionalShown = true
        T.eq(Tether.State("test.optional"), "off", name .. ": kept until something happens")
        fireLeadChange(DUI, AB)
        T.eq(Tether.State("test.optional"), "ready", name .. ": worked out again")
        T.eq(#stub.errors, 0, name .. ": " .. tostring(stub.errors[1]))
    end
end)

test("cdm tether: placing a frame, even one not there yet, asks for a pass; any frame placed does while a group is placed from a lead", function()
    local world = tetherWorld({ lead = false, attached = "test.later" })
    local DUI = world.DUI
    local refreshes = countCalls(world.AB.CdmRows, "Refresh")
    local function expectAsks(fire, context, asks)
        local before = refreshes.calls
        fire()
        T.eq(refreshes.calls, before + (asks or 1), context)
    end
    local laterLead
    expectAsks(function() laterLead = lead("test.later", 400, 300, 100, 60) end, "the followed lead turning up")
    settledPass(world.AB)
    expectAsks(function() DUI.Fire("MoverApplied", "test.later") end, "hung off it: no pass", 0)
    laterLead.IsProtected = function() return true end
    settledPass(world.AB)
    expectAsks(function() DUI.Fire("MoverApplied", "test.later") end, "the followed lead placed")
    expectAsks(function() DUI.Fire("MoverApplied", "test.other") end, "another frame placed, which it may hang off")
end)

test("cdm tether: a setting elsewhere runs no layout pass unless it switches a followed frame on or off, which its name then shows", function()
    local world = tetherWorld({ unitFrames = true, personal = "on", attached = "unitframes.personal" })
    local DUI, AB = world.DUI, world.AB
    moveLead(world.Personal.frame, 860, 300, 200, 40)
    settledPass(AB)
    local passes = countCalls(AB.CdmRows, "Update")
    DUI:Set("UnitFrames", "party.width", DUI:Get("UnitFrames", "party.width") + 20)
    DUI:Set("Chat", "fontSize", 14)
    stub.RunTimers()
    T.eq(passes.calls, 0, "another frame's settings, every frame placed again: no pass")
    T.eq(world.Tether.Name("unitframes.personal"), world.Tether.Label("unitframes.personal"), "the followed frame on")
    DUI:Set("UnitFrames", "personal.enabled", false)
    stub.RunTimers()
    T.eq(passes.calls, 1, "the followed frame switched off: one pass")
    T.eq(world.Tether.Name("unitframes.personal"), DUI.L["%s (off)"]:format(world.Tether.Label("unitframes.personal")),
        "named as off")
    passes.restore()
end)

test("cdm tether: a group follows a switched-off Personal Display, and keeps its saved point when it's switched on", function()
    local world = tetherWorld({ unitFrames = true, personal = "off", attached = "unitframes.personal" })
    local tether = tetherFrame(1, 11)
    local display = world.Personal.frame
    expectFollows(tether, display, "TOP", ATTACHED_X, ATTACHED_Y, "following the switched-off display, not its saved spot")
    world.DUI:Set("UnitFrames", "personal.enabled", true)
    settledPass(world.AB)
    expectFollows(tether, display, "TOP", ATTACHED_X, ATTACHED_Y, "the saved point is kept")
end)

test("cdm tether: a group at its saved spot goes onto its lead at once when it turns up", function()
    tetherWorld({ lead = false, attached = "plugin.Late.frame" })
    local tether = tetherFrame(1, 11)
    expectAnchor(tether, { "TOPLEFT", layoutFrame(1), "CENTER", 50, -20 }, "waiting at its saved spot")
    local lateLead = lead("plugin.Late.frame", 860, 500, 200, 40)
    stub.RunTimers()
    expectFollows(tether, lateLead, "TOP", ATTACHED_X, ATTACHED_Y, "on its lead")
end)

test("cdm tether: a group hangs off the Personal Display once it's built after the group's first pass, or after the fight it was reloaded in", function()
    for _, reloadedInFight in ipairs({ false, true }) do
        local context = reloadedInFight and "reloaded in a fight" or "built late"
        local world = tetherWorld({ lead = false, attached = "unitframes.personal" })
        local DUI, tether = world.DUI, tetherFrame(1, 11)
        DUI.DB.Active().modules.UnitFrames = { personal = { enabled = true, follow = "feet" } }
        if reloadedInFight then stub.EnterCombat(); stub.RunTimers() end
        -- The unit frames addon loads after the action bars'.
        local UF = {}
        stub.LoadFiles(stub.MODULE_DIR, stub.MODULE_FILES, "DaylightUI_UnitFrames", UF)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_UnitFrames")
        if reloadedInFight then
            settledPass(world.AB)
            expectAnchor(tether, { "TOPLEFT", layoutFrame(1), "CENTER", 50, -20 }, "at its saved spot in the fight")
            stub.LeaveCombat()
        end
        stub.RunTimers(); eased(DaylightUI)
        moveLead(UF.Personal.frame, 860, 300, 200, 40)
        settledPass(world.AB)
        expectHung(tether, UF.Personal.frame, "TOP", ATTACHED_X, ATTACHED_Y, context)
    end
end)

local PLUGIN_LEADS = { plain = { measurable = true, make = function() end } }
for name, hostile in pairs(HOSTILE_LEADS) do PLUGIN_LEADS[name] = hostile end

test("cdm tether: a plugin's frame, plain or hostile, is never hung off; its group is placed from its position on a pass and when it's placed in Unlock Frames", function()
    for name, pluginLead in pairs(PLUGIN_LEADS) do
        local world = tetherWorld({ lead = false, attached = "plugin.Test.frame" })
        local leadFrame = lead("plugin.Test.frame", 860, 500, 200, 40)
        pluginLead.make(leadFrame)
        world.Tether.Stale(); settledPass(world.AB)
        local tether = tetherFrame(1, 11)
        expectNothingAnchoredTo(leadFrame, { tether }, name)
        if pluginLead.measurable then
            expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, name)
            moveLead(leadFrame, 400, 300, 200, 40)
            settledPass(world.AB)
            expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, name .. ": moved, then a pass")
            moveLead(leadFrame, 1200, 700, 200, 40)
            world.DUI.Fire("MoverApplied", "plugin.Test.frame")
            stub.RunTimers()
            expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, name .. ": moved, then placed in Unlock Frames")
        end
    end
end)

test("cdm tether: a hung lead that turns protected has its group placed from its position on the next pass; in a fight, once it ends", function()
    for _, inFight in ipairs({ false, true }) do
        local context = inFight and "in a fight" or "out of a fight"
        local world = tetherWorld({ attached = "test.lead" })
        local tether, leadFrame = tetherFrame(1, 11), world.lead
        expectHung(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, context .. ": hung first")
        if inFight then stub.EnterCombat(); stub.RunTimers() end
        leadFrame.IsProtected = function() return true end
        settledPass(world.AB)
        if inFight then
            expectHung(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, context .. ": left hung in the fight")
            stub.LeaveCombat(); stub.RunTimers(); eased(DaylightUI)
        end
        expectPlaced(tether, leadFrame, "TOP", ATTACHED_X, ATTACHED_Y, context .. ": placed")
    end
end)

test("cdm tether: a tether frame protected in a fight keeps its anchor and is laid out once the fight ends", function()
    local world = tetherWorld({ attached = "test.lead" })
    local AB, tether = world.AB, tetherFrame(1, 11)
    local blockedActions = countBlockedActions()
    local otherLead = lead("test.other", 400, 300, 200, 40)
    stub.EnterCombat(); stub.RunTimers()
    world.D.SetChainValue(world.set, 11, "tether", "test.other")
    tether.IsProtected = function() return true end
    local cleared, pointed = countCalls(tether, "ClearAllPoints"), countCalls(tether, "SetPoint")
    local resized, hidden = countCalls(tether, "SetSize"), countCalls(tether, "Hide")
    for _ = 1, 3 do settledPass(AB) end
    expectFollows(tether, world.lead, "TOP", ATTACHED_X, ATTACHED_Y, "held in the fight")
    T.eq(cleared.calls + pointed.calls + resized.calls + hidden.calls, 0, "nothing done to the held frame")
    stub.LeaveCombat()
    stub.RunTimers(); eased(DaylightUI)
    expectFollows(tether, otherLead, "TOP", ATTACHED_X, ATTACHED_Y, "after the fight")
    T.eq(blockedActions(), 0, "no blocked action")
end)

test("cdm tether: emptying the layout or switching it off hides its tether frames; protected in a fight, once it ends", function()
    local endings = {
        ["the layout emptied"] = { endAttachment = function(world) world.D.RemoveChain(world.set, 11) end, inFight = false },
        ["the layout off"] = { endAttachment = function(world) world.D.SetSwitch("on", false) end, inFight = true },
    }
    for name, ending in pairs(endings) do
        local context = name .. (ending.inFight and ", protected in a fight" or "")
        local world = tetherWorld({ attached = "test.lead" })
        local tether = tetherFrame(1, 11)
        if ending.inFight then
            tether.IsProtected = function() return true end
            stub.EnterCombat(); stub.RunTimers()
        end
        ending.endAttachment(world)
        settledPass(world.AB)
        if ending.inFight then
            T.truthy(tether:IsShown(), context .. ": left shown in the fight")
            stub.LeaveCombat(); stub.RunTimers(); eased(DaylightUI)
        end
        T.falsy(tether:IsShown(), context .. ": its tether frame hidden")
    end
end)

test("cdm tether: a group attached to the protected player frame plays through a fight with no blocked action", function()
    local world = tetherWorld({ unitFrames = true, attached = "unitframes.player" })
    local playerFrame = world.DUI.Movers.Get("unitframes.player").frame
    T.truthy(playerFrame:IsProtected(), "the player frame is a secure frame")
    moveLead(playerFrame, 400, 300, 200, 60)
    settledPass(world.AB)
    expectFollows(tetherFrame(1, 11), playerFrame, "TOP", ATTACHED_X, ATTACHED_Y, "attached")
    stub.secure = true
    stub.EnterCombat(); stub.RunTimers()
    flickerEachIcon(world)
    local ours = { tetherFrame(1, 11), pieceFrame(1, 11), pieceFrame(1, 12), pieceFrame(1, 13) }
    for _, frame in ipairs(ours) do
        T.falsy(frame:IsProtected(), tostring(frame:GetName()) .. " isn't protected")
    end
    expectNothingAnchoredTo(playerFrame, ours, "the player frame")
    stub.LeaveCombat(); stub.RunTimers(); eased(DaylightUI)
end)

test("cdm tether: a hidden lead still carries its group, shown by the group's own rules", function()
    local world = tetherWorld({ attached = "test.lead" })
    world.lead:Hide()
    moveLead(world.lead, 900, 620, 200, 40)
    settledPass(world.AB)
    T.truthy(pieceFrame(1, 11):IsShown(), "the group shows")
    T.eq(pieceFrame(1, 11):GetAlpha(), 1, "at its own alpha")
    T.eq(layoutFrame(1):GetAlpha(), 1, "the layout at its own alpha")
    expectFollows(tetherFrame(1, 11), world.lead, "TOP", ATTACHED_X, ATTACHED_Y, "carried by the hidden lead")
end)

local UNCHANGED_PASSES = 200

-- Attached: one group follows, one waits for a missing lead, one is held by the fight.
local function garbageOfUnchangedPasses(attached)
    local world = tetherWorld({ buffIcons = { 31, 32 } })
    local AB, D, set = world.AB, world.D, world.set
    D.AddChain(set, { 21, 22 }, "icon", 0, -200)
    D.AddChain(set, { 31, 32 }, "icon", 0, -300)
    if attached then
        attach(D, set, "test.lead")
        D.SetChainValue(set, 21, "tether", "plugin.Gone.frame")
        D.SetChainValue(set, 31, "tether", "test.lead")
    end
    settledPass(AB)
    if attached then
        -- The fake IsProtected makes garbage walking the frame tree; the game's makes none.
        tetherFrame(1, 11).IsProtected = function() return false end
        tetherFrame(1, 21).IsProtected = function() return false end
        tetherFrame(1, 31).IsProtected = function() return true end
        world.lead.IsProtected = function() return false end
    end
    stub.EnterCombat(); stub.RunTimers()
    settledPass(AB)
    local grown = garbageMadeBy(AB.CdmRows.Update, UNCHANGED_PASSES)
    stub.LeaveCombat()
    return grown
end

test("cdm tether: an unchanged layout pass makes no more garbage with groups attached", function()
    local unattachedGrowth = garbageOfUnchangedPasses(false)
    local attachedGrowth = garbageOfUnchangedPasses(true)
    T.truthy(attachedGrowth - unattachedGrowth < 1, string.format("%d passes: %.2f KB attached, %.2f KB unattached",
        UNCHANGED_PASSES, attachedGrowth, unattachedGrowth))
end)

test("cdm tether: a burst of frames placed or settings changed reads the layout at most once and runs one pass; a pass reads it as often however many groups follow", function()
    local world = tetherWorld({ unitFrames = true, attached = "unitframes.player" })
    local DUI, AB = world.DUI, world.AB
    local layoutReads = countCalls(AB.CdmData, "Current")
    local passes = countCalls(AB.CdmRows, "Update")
    DUI.Movers.ApplyAll()
    T.truthy(layoutReads.calls <= 1, "every frame placed: the layout read " .. layoutReads.calls .. " times")
    stub.RunTimers(); eased(DaylightUI)
    T.eq(passes.calls, 1, "one layout pass for the whole burst")
    local burst = tetherWorld({ attached = "test.lead" })
    local reads = countCalls(burst.D, "Current")
    for _ = 1, 50 do burst.DUI.Fire("SettingChanged", "UnitFrames", "personal.scale") end
    T.truthy(reads.calls <= 1, "50 setting changes read the layout " .. reads.calls .. " times")

    local single = tetherWorld({ ids = { 11 } })
    local D, set = single.D, single.set
    local roots = { 11, 12, 13, 21, 22 }
    for index = 2, #roots do D.AddPiece(set, roots[index], "icon", index * 50, 0) end
    local function currentReadsInOnePass()
        local reads = countCalls(D, "Current")
        single.AB.CdmRows.Update()
        reads.restore()
        return reads.calls
    end
    D.SetChainValue(set, 11, "tether", "test.lead")
    settledPass(single.AB)
    local withOne = currentReadsInOnePass()
    for _, id in ipairs(roots) do D.SetChainValue(set, id, "tether", "test.lead") end
    settledPass(single.AB)
    T.eq(currentReadsInOnePass(), withOne, "a pass reads the layout as often with every group attached")
    T.truthy(tetherFrame(1, 22) and tetherFrame(1, 22):IsShown(), "every group attached")
end)

test("cdm tether: attaching, switching and detaching keep a group where it is on screen, unsnapped, measured from the lead's hang point", function()
    local world = tetherWorld({ editor = true })
    local DUI, AB, D, Tether, set = world.DUI, world.AB, world.D, world.Tether, world.set
    DUI.DB.General().gridSnap = true
    DUI.Movers.GRID = 16
    local version = D.version
    for _, refused in ipairs({ { 99, "test.lead" }, { 11, 42 }, { 11, nil }, { 11, Tether.NONE } }) do
        T.eq(Tether.Attach(set, refused[1], refused[2]), false, "attaching " .. refused[1] .. " to " .. tostring(refused[2]))
    end
    T.eq(D.version, version, "nothing written for a piece not in the layout, a key that isn't one, or no change")
    local secondLeadFrame = secondLead()
    for _, step in ipairs({ { "test.lead", world.lead, "TOP" }, { "test.lead2", secondLeadFrame, "CENTER" } }) do
        local key, frame, hang = step[1], step[2], step[3]
        local before = { screenTopLeft(pieceFrame(1, 11)) }
        attachInEditor(world, key)
        local pointX, pointY = Tether.PointAt(frame, hang)
        T.deq({ Tether.Of(set, 11) }, { key, SPOT_X - pointX, SPOT_Y - pointY, hang }, key .. ": measured from its hang point")
        T.deq(savedSpot(set, 11), { SPOT_X, SPOT_Y }, key .. ": the saved spot isn't moved or snapped to the grid")
        expectGlidesOnScreen(AB, pieceFrame(1, 11), before, before, key)
        version = D.version
        T.eq(Tether.Attach(set, 13, key), false, key .. ": picked again from another piece of the group")
        T.eq(D.version, version, key .. ": nothing written")
    end
    local before = { screenTopLeft(pieceFrame(1, 11)) }
    attachInEditor(world, Tether.NONE)
    T.falsy(hasTetherField(set.chains[11]), "nothing saved for the attachment")
    expectGlidesOnScreen(AB, pieceFrame(1, 11), before, before, "detached")
    moveLead(secondLeadFrame, 400, 200, 100, 60)
    DUI.Fire("MoverApplied", "test.lead2"); stub.RunTimers(); eased(DaylightUI)
    expectAnchor(pieceFrame(1, 11), { "TOPLEFT", layoutFrame(1), "CENTER", SPOT_X, SPOT_Y }, "the old lead moved, the group stays")
end)

test("cdm tether: the frame list starts with where you put it, then each area's frames under Unlock Frames' headings in its order, leaving out frames it can't follow", function()
    local world = tetherWorld({ unitFrames = true, buffs = true, lead = false })
    local DUI, Tether = world.DUI, world.Tether
    local L = DUI.L
    lead("plugin.Boxes.box")
    DUI.Movers.Register(CreateFrame("Frame", nil, UIParent), "game.test", "Game Frame", nil, { proxy = true })
    DUI.Movers.Register(pieceFrame(1, 12), "plugin.Test.piece", "Piece", { "CENTER", nil, "CENTER", 0, 0 })
    DUI.Movers.Register(CreateFrame("Frame", nil, UIParent), "cdm.test", "Cooldown Group", { "CENTER", nil, "CENTER", 0, 0 })
    local values, keys, titles = Tether.Choices()
    T.eq(keys[1], Tether.NONE, "where you put it first")
    T.eq(values[Tether.NONE], L["Where you put it"])
    local headingOf, headings = headingsOf(values, keys, titles)
    T.deq(headings,
        { L["Cast Bars"], L["Group Frames"], L["Unit Frames"], L["Action Bars"], L["Buffs"], L["Combat Text"], L["Other"] },
        "one heading per area with frames, in Unlock Frames' order; raid, party and arena frames share theirs")
    local areaHeading = {}
    for _, area in ipairs(DUI.Movers.AREAS) do
        if area.label and not areaHeading[area.id] then areaHeading[area.id] = L[area.label] end
    end
    for key, heading in pairs(headingOf) do
        if key ~= Tether.NONE then T.eq(heading, areaHeading[DUI.Movers.AreaOf(key)], key .. " under its area's heading") end
    end
    T.eq(headingOf["plugin.Boxes.box"], L["Other"], "a plugin's frame under Other")
    T.isnil(values["game.test"], "a frame the game places is left out")
    T.isnil(values["plugin.Test.piece"], "a layout frame is left out")
    T.isnil(values["cdm.test"], "a Cooldown Manager key is left out")
    local function inOrder(listed, first, second, third)
        return indexOf(listed, first) < indexOf(listed, second) and indexOf(listed, second) < indexOf(listed, third)
    end
    T.truthy(inOrder(keys, "buffs.buff", "buffs.debuff", "buffs.reminder"), "Buffs, Debuffs, Missing Buffs in English")
    rawset(L, "Buffs", "Zz"); rawset(L, "Debuffs", "Yy"); rawset(L, "Missing Buffs", "Xx")
    _, keys = Tether.Choices()
    rawset(L, "Buffs", nil); rawset(L, "Debuffs", nil); rawset(L, "Missing Buffs", nil)
    T.truthy(inOrder(keys, "buffs.reminder", "buffs.debuff", "buffs.buff"),
        "a language that names them the other way round sorts them the other way round")
end)

test("cdm tether: a switched-off frame or a saved frame not here is listed in its area and named so; a ready one or one that would loop by its plain name", function()
    local world = tetherWorld({ unitFrames = true, lead = false })
    local DUI, Tether = world.DUI, world.Tether
    local L = DUI.L
    hangOff(lead("plugin.Test.onGroup"), pieceFrame(1, 11))
    Tether.Stale()
    T.eq(Tether.State("plugin.Test.onGroup"), "loop")
    local values, keys = Tether.Choices()
    local switchedOffName = L["%s (off)"]:format(L["Personal Display"])
    T.truthy(indexOf(keys, "unitframes.personal"), "a switched-off frame is still listed, so it can be picked")
    T.eq(values["unitframes.personal"], switchedOffName)
    local plainNames = { ["unitframes.player"] = L["Player"], [Tether.NONE] = L["Where you put it"],
        ["plugin.Test.onGroup"] = "plugin.Test.onGroup" }
    for key, name in pairs(plainNames) do
        T.eq(values[key], name, key .. " listed by its plain name")
    end
    local titles
    values, keys, titles = Tether.Choices("buffs.buff")
    local notHereName = L["%s (not here)"]:format("buffs.buff")
    T.eq(Tether.State("buffs.buff"), "missing")
    T.eq(headingsOf(values, keys, titles)["buffs.buff"], L["Buffs"], "under its own area's heading")
    T.eq(values["buffs.buff"], notHereName, "by its saved key")
    lead("plugin.Boxes.box")
    values, keys, titles = Tether.Choices("plugin.Alpha.gone")
    T.eq(headingsOf(values, keys, titles)["plugin.Alpha.gone"], L["Other"], "a plugin's frame under Other")
    T.truthy(indexOf(keys, "plugin.Alpha.gone") < indexOf(keys, "plugin.Boxes.box"), "at its alphabetical place")
    T.isnil(values["buffs.buff"], "only the group's own saved frame is listed when it isn't here")
end)

test("cdm tether: X and Y are measured from a lead there to follow, switched off or not, else from the screen's middle, naming a lead not here", function()
    local world = tetherWorld({ unitFrames = true, personal = "off", lead = false })
    local DUI, Tether, set = world.DUI, world.Tether, world.set
    local L = DUI.L
    local fromMiddle = L["Measured from the middle of the screen."]
    local fromLead = measuredFromText(DUI, L["Personal Display"])
    local notHere = L["%s isn't here, so this is measured from the middle of the screen. The group follows it again once it's back."]
    local function expectMeasuredFrom(leadKey, text, context)
        T.eq(Tether.MeasuredFromLead(set, 11), leadKey, context)
        T.eq(Tether.MeasuredFrom(set, 12), text, context)
    end
    expectMeasuredFrom(nil, fromMiddle, "following nothing")
    attach(world.D, set, "unitframes.personal")
    expectMeasuredFrom("unitframes.personal", fromLead, "switched off: no off mark on the name")
    DUI:Set("UnitFrames", "personal.enabled", true)
    Tether.Stale()
    expectMeasuredFrom("unitframes.personal", fromLead, "ready")
    followInstead(world, "plugin.Alpha.gone")
    expectMeasuredFrom(nil, notHere:format("plugin.Alpha.gone"), "not here, by its saved key")
    hangOff(lead("plugin.Test.onGroup"), pieceFrame(1, 11))
    followInstead(world, "plugin.Test.onGroup")
    expectMeasuredFrom(nil, fromMiddle, "a lead that would loop")
end)

test("cdm card: Attach to is the Group tab's first row, a full column wide under its heading; picking a frame that can't be measured or would loop leaves the group following nothing; a saved one not here shows by its key", function()
    local world = tetherWorld({ pick = true })
    local DUI, D, Tether, set, row = world.DUI, world.D, world.Tether, world.set, world.row
    local Card = world.AB.CdmCard
    local rows = Card.ROWS.chain
    T.truthy(rows[1].head, "the heading first")
    T.truthy(rows[2] == row, "then Attach to")
    T.eq(rows[3].box, "position", "then the position box")
    T.eq(rows[4].item.key, "cdm.card.chain.spacing", "then the rows as before")
    T.truthy(row.stacked and row.frame:IsShown(), "on the Group tab, its label above its box")
    T.eq(row.frame.control:GetWidth(), Card.COL, "its box a column wide")
    local headingY = select(5, rows[1].frame:GetPoint(1))
    local rowY = select(5, row.frame:GetPoint(1))
    T.eq(rowY, headingY - Card.HEAD_H - 4, "right under the heading")
    T.eq(select(5, rows[3].frame:GetPoint(1)), rowY - row.height - 2, "the position box right under it")
    local reveals = recordReveals(DUI)
    lead("test.unplaced")
    lead("test.flat", 860, 500, 0, 0)
    hangOff(lead("plugin.Test.onGroup", 860, 500, 200, 40), pieceFrame(1, 11))
    Tether.Stale()
    local refusals = { ["test.unplaced"] = "a frame with no place on screen", ["test.flat"] = "a frame of no size",
        ["plugin.Test.onGroup"] = "a frame that would loop" }
    for key, context in pairs(refusals) do
        local version = D.version
        local groupBefore = DaylightUI.DB.Copy(set.chains[11])
        row.item.set(key)
        T.deq(set.chains[11], groupBefore, context .. ": the group's settings unchanged")
        T.eq(D.version, version, context .. ": nothing written")
        row.frame.Refresh()
        T.eq(row.frame.control.text:GetText(), DUI.L["Where you put it"], context .. ": the box unchanged")
    end
    T.eq(#reveals, 0, "a refused pick reveals nothing")
    T.eq(#shownLeadRings(world.Ed), 0, "and rings nothing")
    D.SetChainValue(set, 11, "tether", "plugin.Gone.frame")
    world.Ed.Changed(); settledPass(world.AB)
    local notHere = DUI.L["%s (not here)"]:format("plugin.Gone.frame")
    local box = row.frame.control
    T.eq(row.item.get(), "plugin.Gone.frame")
    T.eq(box.text:GetText(), notHere, "its saved key, not where you put it")
    box:Click()
    local listed = visibleMenuRowOf(DUI.Widgets, "plugin.Gone.frame")
    T.truthy(listed, "in view as the list opens")
    T.truthy(listed.check:IsShown(), "ticked as the current choice")
    T.eq(listed.text:GetText(), notHere)
end)

test("cdm card: picking a switched-off frame that has a place on screen attaches the group where it is, its X and Y its middle from the lead's point", function()
    local world = tetherWorld({ unitFrames = true, personal = "off", pick = true })
    local D, set = world.D, world.set
    local before = { screenTopLeft(pieceFrame(1, 11)) }
    world.row.item.set("unitframes.personal")
    T.eq(D.ChainValue(set, 11, "tether"), "unitframes.personal", "attached")
    expectGlidesOnScreen(world.AB, pieceFrame(1, 11), before, before, "attached to the switched-off display")
    local offsetX, offsetY = D.ChainValue(set, 11, "tetherX"), D.ChainValue(set, 11, "tetherY")
    T.deq({ world.Ed.Spot() }, { offsetX + GROUP_MIDDLE_X, offsetY + GROUP_MIDDLE_Y }, "the group's middle from the lead's point")
end)

test("cdm tether: following puts an attached group's editor spot at the lead's point plus its offset; rebasing an unmoved group writes nothing", function()
    local world = tetherWorld({ attached = "test.lead" })
    local D, Tether, set, leadFrame = world.D, world.Tether, world.set, world.lead
    D.AddChain(set, { 21, 22 }, "icon", 0, -200)
    D.SetChainValue(set, 21, "tether", "test.lead")
    moveLead(leadFrame, 860.4, 500.3, 200, 40)
    T.truthy(Tether.Follow(set, 21), "a group moved")
    T.deq(savedSpot(set, 11), { ATTACHED_X, ATTACHED_Y }, "at the lead's point plus the offset, in whole pixels")
    T.deq(savedSpot(set, 21), { 0, -200 }, "the dragged group is left to the drag")
    T.falsy(Tether.Follow(set, 21), "nothing moved since")
    T.truthy(Tether.Follow(set), "with nothing dragged")
    T.deq(savedSpot(set, 21), { 0, -20 }, "at the lead's center, in whole pixels")
    Tether.Rebase(set)
    local version = D.version
    Tether.Rebase(set)
    T.eq(D.version, version, "nothing moved: nothing written")
    moveLead(leadFrame, 860.4, 460.3, 200, 80)
    T.falsy(Tether.Follow(set, 21), "a lead growing around its hang point leaves the group's spot")
    Tether.Rebase(set)
    T.eq(D.ChainValue(set, 11, "tetherX"), ATTACHED_X, "and its offset")
    T.eq(D.version, version, "nothing written")
end)

test("cdm tether: opening the editor after the lead's anchor changed measures the group from the new point, keeping its spot", function()
    local world = tetherWorld({ editorLead = "test.lead" })
    local Tether, set, leadFrame = world.Tether, world.set, world.lead
    world.Ed.Close(); settledPass(world.AB)
    local onScreen = { screenTopLeft(pieceFrame(1, 11)) }
    leadFrame:ClearAllPoints()
    leadFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 500)
    T.truthy(world.Ed.Open())
    local bottomX, bottomY = Tether.PointAt(leadFrame, "BOTTOM")
    T.deq({ Tether.Of(set, 11) }, { "test.lead", SPOT_X - bottomX, SPOT_Y - bottomY, "BOTTOM" }, "the lead's new hang point")
    T.deq(savedSpot(set, 11), { SPOT_X, SPOT_Y }, "the spot stays")
    expectGlidesOnScreen(world.AB, pieceFrame(1, 11), onScreen, onScreen, "opening the editor")
end)

test("cdm tether: another talent set picked or a spec change while editing puts its attached groups where their leads carry them at once; with the editor closed, nowhere, each set following its own attachments", function()
    local function pickInEditor(world) world.Ed.SetGroup(2) end
    local function changeSpec(world) changeSpecTo(world.DUI, 2) end
    local switches = {
        { name = "picking it in the editor", switchToSecondSet = pickInEditor },
        { name = "a spec change", switchToSecondSet = changeSpec },
        { name = "a spec change with the editor closed", switchToSecondSet = changeSpec, editorClosed = true },
    }
    for _, switch in ipairs(switches) do
        local name, switchToSecondSet, editorClosed = switch.name, switch.switchToSecondSet, switch.editorClosed
        local world = tetherWorld({ editor = true })
        local D, Ed, set = world.D, world.Ed, world.set
        world.DUI.DB.SpecGroup = function() return 1 end
        attachInEditor(world, "test.lead")
        Ed.SetGroup(2)
        local secondSet = D.Get(2)
        D.AddChain(secondSet, { 11, 12, 13 }, "icon", 50, -20)
        attach(D, secondSet, "test.lead")
        D.AddChain(secondSet, { 21, 22 }, "icon", 0, -200)
        D.SetChainValue(secondSet, 21, "tether", "test.missing")
        Ed.SetGroup(1)
        if editorClosed then Ed.Close(); settledPass(world.AB) end
        moveLead(world.lead, 890, 480, 200, 40)
        switchToSecondSet(world)
        if editorClosed then
            T.deq(savedSpot(secondSet, 11), { 50, -20 }, name .. ": set 2's spot unchanged")
            T.deq(savedSpot(set, 11), { SPOT_X, SPOT_Y }, name .. ": set 1's spot unchanged")
            stub.RunTimers(); eased(DaylightUI)
            T.falsy(tetherFrame(1, 11):IsVisible(), name .. ": set 1's tether frame out of sight")
            expectFollows(tetherFrame(2, 11), world.lead, "TOP", ATTACHED_X, ATTACHED_Y,
                name .. ": set 2 follows its own attachment")
            changeSpecTo(world.DUI, 1); stub.RunTimers(); eased(DaylightUI)
            T.truthy(tetherFrame(1, 11):IsVisible(), name .. ": set 1's tether frame back")
            expectFollows(tetherFrame(1, 11), world.lead, "TOP", SPOT_X, SPOT_Y, name .. ": set 1 again")
        else
            T.eq(Ed.Set(), secondSet, name .. ": the editor shows the second set")
            T.deq(savedSpot(secondSet, 11), { 30 + ATTACHED_X, -20 + ATTACHED_Y },
                name .. ": at the lead's point plus the saved offset, before the editor steps")
            T.deq(savedSpot(secondSet, 21), { 0, -200 }, name .. ": a group whose lead isn't here keeps its spot")
            Ed.SetGroup(1)
            if name == "picking it in the editor" then
                T.deq(savedSpot(set, 11), { SPOT_X + 30, SPOT_Y - 20 }, "the set in use followed the lead as well")
            end
            Ed.SetGroup(2); Ed.SetGroup(1)
            local version = D.version
            Ed.SetGroup(2)
            T.eq(D.version, version, name .. ": switching again with unmoved leads writes nothing")
        end
    end
end)

test("cdm tether: the open editor follows a moving lead; stepping it, the lead still or moving, writes nothing and makes no garbage", function()
    local world = tetherWorld({ editor = true })
    local D, Ed = world.D, world.Ed
    local function stepTenTimes() for _ = 1, 10 do stepEditor(Ed) end end
    stepTenTimes()
    local unattachedGarbage = garbageMadeBy(stepTenTimes, 100)
    attachInEditor(world, "test.lead")
    settledPass(world.AB)
    local version = D.version
    stepTenTimes()
    T.eq(D.version, version, "ten steps: nothing written")
    local attachedGarbage = garbageMadeBy(stepTenTimes, 100)
    T.truthy(attachedGarbage - unattachedGarbage < 1,
        string.format("1000 steps: %.2f KB attached, %.2f KB unattached", attachedGarbage, unattachedGarbage))
    moveLead(world.lead, 860, 400, 200, 40)
    stepEditor(Ed)
    T.deq(savedSpot(world.set, 11), { SPOT_X, SPOT_Y - 100 }, "the spot followed")
    T.eq(D.version, version, "nothing written")
end)

test("cdm tether: edits that leave a group put don't move its offset or spot, its lead's point on a half pixel", function()
    local world = tetherWorld({ editor = true })
    local D, Ed, set = world.D, world.Ed, world.set
    world.lead:ClearAllPoints()
    world.lead:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    moveLead(world.lead, 860.5, 500.5, 200, 40)
    attachInEditor(world, "test.lead")
    stepEditor(Ed)
    local function attachment()
        local _, offsetX, offsetY, at = world.Tether.Of(set, 11)
        return { offsetX, offsetY, at, set.pieces[11].x, set.pieces[11].y }
    end
    local before = attachment()
    T.eq(before[3], "CENTER", "measured from the lead's center")
    for spacing = 1, 4 do
        D.SetChainValue(set, 11, "spacing", spacing)
        Ed.Changed()
        stepEditor(Ed)
        T.deq(attachment(), before, "spacing " .. spacing .. ": offset and spot kept")
    end
end)

test("cdm tether: unhooking, removing or swapping pieces of an attached group keeps the attachment with the group's first spot and every piece put on screen", function()
    local world = tetherWorld({ editorLead = "test.lead" })
    local AB, D, Ed, set = world.AB, world.D, world.Ed, world.set
    local spotOf = {}
    for _, id in ipairs({ 11, 12, 13 }) do spotOf[id] = { screenTopLeft(pieceFrame(1, id)) } end
    local lastBox = D.Layout(set)[13]
    D.Unhook(set, 13, lastBox.x, lastBox.y)
    Ed.Changed()
    T.eq(D.ChainValue(set, 13, "tether"), "test.lead", "the unhooked piece keeps the attachment")
    expectGlidesOnScreen(AB, pieceFrame(1, 13), spotOf[13], spotOf[13], "unhooked")
    expectGlidesOnScreen(AB, pieceFrame(1, 11), spotOf[11], spotOf[11], "the group it left")
    T.eq(D.ChainValue(set, 11, "tether"), "test.lead", "the group it left stays attached")
    Ed.Remove(11)
    T.eq(D.ChainValue(set, 12, "tether"), "test.lead", "the freed piece keeps the attachment")
    expectGlidesOnScreen(AB, pieceFrame(1, 12), spotOf[12], spotOf[12], "first piece removed")
    expectGlidesOnScreen(AB, pieceFrame(1, 13), spotOf[13], spotOf[13], "the other group")

    world = tetherWorld({ editorLead = "test.lead" })
    AB, D, Ed, set = world.AB, world.D, world.Ed, world.set
    local firstSpotBefore = { screenTopLeft(pieceFrame(1, 11)) }
    T.truthy(D.Swap(set, 11, 12))
    Ed.Changed()
    T.eq(D.ChainValue(set, 12, "tether"), "test.lead", "the attachment stays with the first spot")
    expectGlidesOnScreen(AB, pieceFrame(1, 12), firstSpotBefore, firstSpotBefore, "swapped in the group")
end)

test("cdm tether: the saved spot stays where the editor last showed the group, for versions that don't know attachments", function()
    local world = tetherWorld({ editorLead = "test.lead" })
    local D, Ed, set = world.D, world.Ed, world.set
    moveLead(world.lead, 860.4, 420.3, 200, 40)
    stepEditor(Ed)
    set.pieces[11].x = set.pieces[11].x + 1
    Ed.Changed()
    stepEditor(Ed)
    local pointX, pointY = world.Tether.PointAt(world.lead, "TOP")
    local lastShown = { math.floor(pointX + D.ChainValue(set, 11, "tetherX") + 0.5),
        math.floor(pointY + D.ChainValue(set, 11, "tetherY") + 0.5) }
    Ed.Close(); settledPass(world.AB)
    T.deq(savedSpot(set, 11), lastShown, "the saved spot is the last one shown")
    local onScreen = { screenTopLeft(pieceFrame(1, 11)) }
    T.near(onScreen[1], lastShown[1], 1); T.near(onScreen[2], lastShown[2], 1)
end)

-- The lead's TOP once moved to 700, 300, 200 x 40.
local MOVED_LEAD_TOP_X, MOVED_LEAD_TOP_Y = -160, -200

test("cdm tether: arrows, Shift-arrows and typed X/Y move an attached group's offset by exactly what's entered, the boxes' tooltip naming the lead", function()
    local world = tetherWorld({ pick = true, atOffset = true })
    local AB, D, Ed, set = world.AB, world.D, world.Ed, world.set
    local position = AB.CdmCard.Position()
    local function expectOffset(x, y, context)
        T.deq({ world.Tether.Of(set, 11) }, { "test.lead", x, y, "TOP" }, context .. ": still attached, at the offset")
        T.deq(savedSpot(set, 11), { MOVED_LEAD_TOP_X + x, MOVED_LEAD_TOP_Y + y }, context .. ": the spot follows the lead")
        T.deq({ Ed.Spot() }, { x + GROUP_MIDDLE_X, y + GROUP_MIDDLE_Y },
            context .. ": X and Y are the group's middle from the lead's point")
    end
    expectOffset(-150, 20, "before")
    local tooltips = recordTooltips(world.DUI.Widgets)
    stub.MouseEnter(position.y); stub.MouseLeave(position.y)
    T.eq(tooltips.shown[#tooltips.shown][3], measuredFromText(world.DUI, "test.lead"), "the tooltip measures from the lead")
    tooltips.restore()
    Ed.Nudge(1, 0)
    expectOffset(-149, 20, "a nudge of one is one, not two")
    stub.shift = true; pressEditorKey("UP"); stub.shift = nil
    expectOffset(-149, 36, "Shift-arrow: one grid step")
    T.eq(position.x:GetText(), "-91", "the X box shows the group's middle from the lead's point")
    T.eq(position.y:GetText(), "18", "the Y box shows the group's middle from the lead's point")
    settledPass(AB)
    local shownBefore = { screenTopLeft(pieceFrame(1, 11)) }
    position.x:SetText("0")
    position.x:GetScript("OnEnterPressed")(position.x)
    expectOffset(0 - GROUP_MIDDLE_X, 36, "X typed as 0: the middle on the lead's point")
    local typedSpot = { MOVED_LEAD_TOP_X - GROUP_MIDDLE_X, MOVED_LEAD_TOP_Y + 36 }
    expectGlidesOnScreen(AB, pieceFrame(1, 11), shownBefore, typedSpot, "X typed")
    position.y:SetText("abc")
    position.y:GetScript("OnEnterPressed")(position.y)
    T.eq(position.y:GetText(), "18", "not a number: the field shows the offset again")
    expectOffset(0 - GROUP_MIDDLE_X, 36, "not a number: unchanged")
    local version = D.version
    T.truthy(Ed.MoveTo(Ed.Spot()), "typing X and Y as they already are is accepted")
    T.eq(D.version, version, "and writes nothing")
end)

test("cdm tether: a dragged attached group stays attached where it's dropped, its offset from the lead's point at the drop, gliding there", function()
    for _, leadMoves in ipairs({ false, true }) do
        local context = leadMoves and "the lead moving during the drag" or "a still lead"
        local world = tetherWorld({ editorLead = "test.lead" })
        local DUI, D, Ed, set = world.DUI, world.D, world.Ed, world.set
        DUI.DB.General().gridSnap = false
        DUI.DB.General().magnet = false
        local shownBefore = { screenTopLeft(pieceFrame(1, 11)) }
        local dropped = { SPOT_X + 40, SPOT_Y }
        dragGroup(Ed, 40, function()
            if not leadMoves then return end
            moveLead(world.lead, 860, 450, 200, 40)
            stepEditor(Ed)
            T.deq(savedSpot(set, 11), dropped, context .. ": the lead moving doesn't move the group being dragged")
        end)
        T.falsy(Ed.Dragging(), context .. ": dropped")
        local leadTopX, leadTopY = world.Tether.PointAt(world.lead, "TOP")
        T.deq({ world.Tether.Of(set, 11) }, { "test.lead", dropped[1] - leadTopX, dropped[2] - leadTopY, "TOP" },
            context .. ": still attached, its offset from the lead's point at the drop")
        if leadMoves then
            settledPass(world.AB)
            T.deq({ screenTopLeft(pieceFrame(1, 11)) }, dropped, context .. ": shown where it was dropped")
        else
            expectGlidesOnScreen(world.AB, pieceFrame(1, 11), shownBefore, dropped, context)
        end
        stepEditor(Ed)
        T.deq(savedSpot(set, 11), dropped, context .. ": the editor keeps it where it was dropped")
    end
end)

test("cdm tether: in a fight nothing attaches, follows or rebases a group", function()
    local world = tetherWorld({ editor = true })
    local D, Ed, set = world.D, world.Ed, world.set
    attachInEditor(world, "test.lead")
    stepEditor(Ed)
    local spot, version = savedSpot(set, 11), D.version
    stub.EnterCombat()
    pressEditorKey("RIGHT")
    moveLead(world.lead, 860, 400, 200, 40)
    world.DUI.Fire("MoverApplied", "test.lead")
    stub.RunTimers()
    T.deq(savedSpot(set, 11), spot, "nothing followed in the fight")
    T.eq(D.version, version, "nothing attached or rebased in the fight")
    stub.LeaveCombat()
end)

test("cdm card: picking a frame from Attach to attaches only that group at once, ringing and revealing it; the current one again does nothing; where you put it detaches and ends both", function()
    local world = tetherWorld({ pick = true })
    local DUI, AB, D, Ed, set, row = world.DUI, world.AB, world.D, world.Ed, world.set, world.row
    D.AddChain(set, { 21, 22 }, "icon", 300, -200)
    Ed.Changed(); settledPass(AB)
    local reveals = recordReveals(DUI)
    local version = D.version
    pickFromList(world, "test.lead")
    T.eq(D.ChainValue(set, 11, "tether"), "test.lead", "attached by the pick itself")
    T.truthy(D.version > version, "the layout written")
    T.eq(row.frame.control.text:GetText(), "test.lead", "the box shows the frame")
    T.deq(reveals, { { "test.lead", true } }, "revealed once")
    T.truthy(ringRound(Ed, world.lead), "ringed")
    settledPass(AB)
    T.falsy(tetherFrame(1, 21) and tetherFrame(1, 21):IsShown(), "the other group has no tether frame")
    version = D.version
    pickFromList(world, "test.lead")
    T.eq(D.version, version, "the current choice again: nothing written")
    T.eq(#reveals, 1, "picking the same frame again reveals nothing more")
    pickFromList(world, world.Tether.NONE)
    eased(DaylightUI)
    T.eq(row.frame.control.text:GetText(), DUI.L["Where you put it"])
    T.deq(reveals, { { "test.lead", true }, { "test.lead", false } }, "where you put it: switched off")
    T.eq(#shownLeadRings(Ed), 0, "where you put it: no ring")
end)

test("cdm editor: picking an attached group rings and reveals its frame alone, painted still in the accent, under the previews, with its name tag; picking another moves the ring there; nothing picked, none", function()
    local world = tetherWorld({ twoLeads = true })
    local DUI, Ed, Tether = world.DUI, world.Ed, world.Tether
    local function expectPaintedFrom(ring, color, context)
        local startColor = ring:GetRegions().__gradient and ring:GetRegions().__gradient[2]
        T.truthy(startColor, context .. ": its line painted")
        T.rgb({ startColor.r, startColor.g, startColor.b }, color, context .. ": painted from the start of its colors")
    end
    local reveals = recordReveals(DUI)
    selectAndSettle(Ed, 11)
    local first = ringRound(Ed, world.lead)
    T.truthy(first, "a ring round the followed frame")
    expectPaintedFrom(first, DUI.Style.AccentPair() or { DUI.Style.Accent() }, "the accent")
    T.truthy(Ed.Flowing(), "the picked group's outlines turn")
    Ed.PreviewOf(11).lit(false)
    Ed.GroupOutline().lit(false)
    T.falsy(Ed.Flowing(), "with only the still ring lit, nothing turns")
    Ed.PreviewOf(11).lit(true)
    T.truthy(Ed.Flowing(), "an outline lit without still turns as before")
    T.eq(#shownLeadRings(Ed), 1, "exactly one ring")
    local pad, overlay = Ed.GROUP_PAD, first:GetParent()
    local left, top = Tether.PointAt(world.lead, "TOPLEFT")
    local right, bottom = Tether.PointAt(world.lead, "BOTTOMRIGHT")
    expectAnchor(first, { "TOPLEFT", overlay, "CENTER", left - pad, top + pad }, "its top-left")
    expectAnchor(first, { "BOTTOMRIGHT", overlay, "CENTER", right + pad, bottom - pad }, "its bottom-right", 2)
    moveLead(world.lead, 700, 300, 200, 40)
    stepEditor(Ed)
    T.truthy(ringRound(Ed, world.lead), "the ring follows its frame the next frame")
    expectNothingAnchoredTo(world.lead, { first }, "the ring")
    moveLead(world.lead, 860, 500, 200, 40)
    stepEditor(Ed)
    T.truthy(first:GetFrameLevel() < Ed.PreviewOf(11):GetFrameLevel(), "under the previews")
    T.falsy(first:IsMouseEnabled(), "the mouse goes through it")
    expectAccentText(DUI, first.tag, Tether.Name("test.lead"), "a ready frame's tag")
    Ed.Draw()
    Ed.Nudge(1, 0)
    stepEditor(Ed)
    T.deq(reveals, { { "test.lead", true } }, "revealed once, though redrawn and edited")
    Ed.Select(21)
    T.truthy(ringRound(Ed, world.secondLead), "another picked: the ring round the second frame")
    T.eq(#shownLeadRings(Ed), 1, "still exactly one ring")
    Ed.Select(nil)
    T.eq(#shownLeadRings(Ed), 0, "nothing picked: no ring")
    T.deq(reveals, {
        { "test.lead", true },
        { "test.lead", false }, { "test.lead2", true },
        { "test.lead2", false },
    }, "each pick switches the last frame off before revealing its own; nothing picked switches it off")
end)

test("cdm editor: the followed frame's ring fades out when nothing is picked, and comes back if a pick follows mid-fade", function()
    local world = tetherWorld({ twoLeads = true })
    local Ed, Motion = world.Ed, DaylightUI.Motion
    selectAndSettle(Ed, 11)
    local ring = Ed.LeadRing()
    T.eq(#shownLeadRings(Ed), 1, "picked: ringed")
    Ed.Select(nil)
    stub.RunOnUpdate(Motion.Driver(), Motion.FAST / 2)
    T.truthy(ring:IsShown(), "nothing picked: still shown, fading")
    T.truthy(ring:GetAlpha() > 0 and ring:GetAlpha() < 1, "partway out: alpha " .. ring:GetAlpha())
    stub.RunOnUpdate(Motion.Driver(), Motion.FAST)
    T.falsy(ring:IsShown(), "faded out: hidden")
    T.eq(ring:GetAlpha(), 0, "faded out: alpha 0")
    selectAndSettle(Ed, 11)
    Ed.Select(nil)
    stub.RunOnUpdate(Motion.Driver(), Motion.FAST / 2)
    Ed.Select(11)
    stub.RunOnUpdate(Motion.Driver(), Motion.FAST)
    T.truthy(ring:IsShown(), "picked mid-fade: shown")
    T.eq(ring:GetAlpha(), 1, "picked mid-fade: back to full")
end)

test("cdm editor: a followed frame of no size, or that would loop, gets no ring and isn't revealed", function()
    local world = tetherWorld({ twoLeads = true })
    local DUI, Ed, Tether = world.DUI, world.Ed, world.Tether
    local reveals = recordReveals(DUI)
    moveLead(world.lead, 860, 500, 0, 0)
    Ed.Select(11)
    T.eq(#shownLeadRings(Ed), 0, "no size")
    Ed.Select(nil)
    hangOff(lead("plugin.Test.onGroup", 860, 500, 200, 40), pieceFrame(1, 11))
    followInstead(world, "plugin.Test.onGroup")
    Ed.Select(11)
    T.eq(Tether.State("plugin.Test.onGroup"), "loop")
    T.eq(#shownLeadRings(Ed), 0, "would loop")
    T.deq(reveals, {}, "nothing revealed")
end)

test("cdm editor: a switched-off Personal Display with a place on screen is ringed by its plain name but stays hidden; its reveal ends when nothing is picked, the editor closes or a fight closes it", function()
    local world = tetherWorld({ unitFrames = true, personal = "off", attached = "unitframes.personal", editor = true })
    local DUI, Ed, Tether, Personal = world.DUI, world.Ed, world.Tether, world.Personal
    local reveals = recordReveals(DUI)
    local function hiddenWithNoSample() return not Personal.frame:IsShown() and Personal.frame.test == nil end
    local function expectRevealed(context)
        T.truthy(hiddenWithNoSample(), context .. ": switched off, so hidden")
    end
    Ed.Select(11)
    local ring = ringRound(Ed, Personal.frame)
    T.eq(Tether.Label("unitframes.personal"), DUI.L["Personal Display"])
    expectAccentText(DUI, ring.tag, Tether.Label("unitframes.personal"), "its plain name")
    expectRevealed("picked")
    Ed.Select(nil)
    T.truthy(hiddenWithNoSample(), "nothing picked: hidden")
    Ed.Select(11)
    Ed.Close()
    T.eq(#shownLeadRings(Ed), 0, "closed: no ring left")
    T.truthy(hiddenWithNoSample(), "closed: hidden")
    T.truthy(Ed.Open(), "opens again")
    Ed.Select(11)
    expectRevealed("the first pick after reopening")
    local close, revealsAtClose, ringsAtClose, hiddenAtClose = Ed.Close, nil, nil, nil
    Ed.Close = function(...)
        close(...)
        revealsAtClose, ringsAtClose, hiddenAtClose = #reveals, #shownLeadRings(Ed), hiddenWithNoSample()
    end
    stub.EnterCombat()
    Ed.Close = close
    T.falsy(Ed.IsOpen(), "the fight closed it")
    local onAndOff = { "unitframes.personal", true }
    T.deq(reveals, { onAndOff, { "unitframes.personal", false }, onAndOff, { "unitframes.personal", false },
        onAndOff, { "unitframes.personal", false } }, "every reveal switched off: unpicked, closed, and by the fight")
    T.eq(revealsAtClose, 6, "switched off by the time the fight's close returned")
    T.eq(ringsAtClose, 0, "no ring left by then")
    T.truthy(hiddenAtClose, "hidden by then")
    stub.LeaveCombat()
end)

test("cdm editor: the reveal and ring end when the followed frame goes, the group is removed, another talent set is opened or the layout reset", function()
    local world = tetherWorld({ twoLeads = true })
    local DUI, Ed, Tether = world.DUI, world.Ed, world.Tether
    local reveals = recordReveals(DUI)
    local function expectNoRing(context)
        eased(DaylightUI)
        T.eq(#shownLeadRings(Ed), 0, context .. ": no ring")
    end
    selectAndSettle(Ed, 11)
    local giveBack = loseMover(DUI, "test.lead")
    Tether.Stale()
    Ed.Draw()
    expectNoRing("the followed frame gone")
    giveBack()
    Tether.Stale()
    selectAndSettle(Ed, 21)
    Ed.RemoveChain(21)
    expectNoRing("the picked group removed")
    selectAndSettle(Ed, 11)
    Ed.SetGroup(2)
    expectNoRing("another talent set opened")
    Ed.SetGroup(1)
    selectAndSettle(Ed, 11)
    settledPass(world.AB)
    T.truthy(tetherFrame(1, 11):IsVisible(), "attached: its tether frame shows")
    Ed.Reset()
    expectNoRing("the layout reset")
    settledPass(world.AB)
    T.isnil(next(Ed.Set().chains), "the reset removes every attachment with the layout")
    T.falsy(tetherFrame(1, 11):IsVisible(), "the reset leaves no tether frame showing")
    T.deq(reveals, {
        { "test.lead", true }, { "test.lead", false },
        { "test.lead2", true }, { "test.lead2", false },
        { "test.lead", true }, { "test.lead", false },
        { "test.lead", true }, { "test.lead", false },
    }, "each frame switched off as its ring went")
end)

test("cdm editor: alone, picking a group that follows the party shows the party's preview, ringed, kept through /dui test on and off; closing ends it before it returns", function()
    local world = tetherWorld({ unitFrames = true, attached = "unitframes.party" })
    local DUI, Ed, Party = world.DUI, world.Ed, world.UF.Party
    local partyFrame = DUI.Movers.Get("unitframes.party").frame
    moveLead(partyFrame, 20, 500, 200, 300)
    T.truthy(Ed.Open(), "the editor opens")
    selectAndSettle(Ed, 11)
    stepEditor(Ed)
    local revealedSamples = stub.ShownCount(Party.preview)
    T.truthy(Party.group:Previewing() and revealedSamples > 0, "the party previews its samples")
    T.truthy(ringRound(Ed, partyFrame), "the party ringed")
    expectNothingAnchoredTo(partyFrame, { Ed.LeadRing(), tetherFrame(1, 11), pieceFrame(1, 11) }, "the party header")
    DUI.RunCommand("test")
    stub.RunTimers()
    T.truthy(DUI.testMode, "/dui test: test mode on")
    DUI.RunCommand("test")
    stub.RunTimers()
    T.truthy(Ed.IsOpen(), "the editor still open")
    T.truthy(Party.group:Previewing(), "the party still previews")
    T.eq(stub.ShownCount(Party.preview), revealedSamples, "the party's samples still shown")
    Ed.Close()
    T.falsy(Party.group:Previewing(), "no longer previewing once the editor closed")
    T.eq(stub.ShownCount(Party.preview), 0, "no samples left once the editor closed")
end)

test("cdm tether: a group whose lead has no rectangle yet or is missing is measured from the screen's middle, its arrows and X/Y moving its saved spot and keeping the attachment, until the lead is back", function()
    local troubles = {
        ["no rectangle yet"] = function(world)
            local center = world.lead.__center
            world.lead.__center = nil
            T.eq(world.Tether.MeasuredFrom(world.set, 11), world.DUI.L["Measured from the middle of the screen."],
                "no rectangle yet: the tooltip")
            return function() world.lead.__center = center end
        end,
        missing = function(world)
            local giveBack = loseMover(world.DUI, "test.lead")
            world.Tether.Stale()
            return function() giveBack(); world.Tether.Stale() end
        end,
    }
    for name, makeTrouble in pairs(troubles) do
        local world = tetherWorld({ pick = true, atOffset = true })
        local Ed, Tether, set = world.Ed, world.Tether, world.set
        eased(DaylightUI)
        local position = world.AB.CdmCard.Position()
        local giveBack = makeTrouble(world)
        local function middleFromScreenCenter() return { set.pieces[11].x + GROUP_MIDDLE_X, set.pieces[11].y + GROUP_MIDDLE_Y } end
        local middle = middleFromScreenCenter()
        T.deq({ Ed.Spot() }, middle, name .. ": X and Y are the group's middle from the screen's center")
        stepEditor(Ed); eased(DaylightUI)
        T.deq({ position.x:GetText(), position.y:GetText() }, { tostring(middle[1]), tostring(middle[2]) },
            name .. ": the open editor shows the boxes afresh")
        T.eq(#shownLeadRings(Ed), 0, name .. ": and drops the ring")
        local spot = savedSpot(set, 11)
        Ed.Nudge(1, 0)
        stub.shift = true; pressEditorKey("UP"); stub.shift = nil
        T.deq(savedSpot(set, 11), { spot[1] + 1, spot[2] + 16 }, name .. ": the saved spot moved by the nudges")
        middle = middleFromScreenCenter()
        T.truthy(Ed.MoveTo(middle[1] + 10, middle[2]), name .. ": X typed 10 further")
        T.deq(savedSpot(set, 11), { spot[1] + 11, spot[2] + 16 }, name .. ": the saved spot moved by 10")
        T.deq({ Tether.Of(set, 11) }, { "test.lead", ATTACHED_X, ATTACHED_Y, "TOP" }, name .. ": still attached, its offset kept")
        giveBack()
        T.deq({ Ed.Spot() }, { ATTACHED_X + GROUP_MIDDLE_X, ATTACHED_Y + GROUP_MIDDLE_Y }, name .. ": back, the group's middle from the lead's point")
        stepEditor(Ed); eased(DaylightUI)
        T.deq({ position.x:GetText(), position.y:GetText() },
            { tostring(ATTACHED_X + GROUP_MIDDLE_X), tostring(ATTACHED_Y + GROUP_MIDDLE_Y) },
            name .. ": back, the boxes from the lead's point")
        T.eq(#shownLeadRings(Ed), 1, name .. ": back, the ring")
    end
end)
