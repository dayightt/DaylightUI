local stub = require("stub")
local savedEditMode = _G.C_EditMode

-- The game's quest tracker, as far as placing it touches it.
-- The game adding a block. It goes in the section's usedBlocks, then the quest
-- update fires, which is when ours go over the tracker.
function addUsed(section, b)
    section.usedBlocks = section.usedBlocks or { tmpl = {} }
    table.insert(section.usedBlocks.tmpl, b)
    stub.FireEvent("QUEST_LOG_UPDATE")
    stub.RunTimers()
end

local function world()
    _G.C_EditMode = nil   -- test_bars (abworld) leaves a fake one behind; no saved layout here
    Enum.EditModeSystem = { ActionBar = 0, ObjectiveTracker = 12 }
    Enum.EditModeObjectiveTrackerSetting = { Height = 0, Opacity = 1, TextSize = 2 }
    _G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    local otf = CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
    otf:SetSize(260, 600)
    otf.NineSlice = CreateFrame("Frame", nil, otf)
    local function header(parent)
        local h = CreateFrame("Frame", nil, parent)
        h.Text = h:CreateFontString()
        h.Background = h:CreateTexture()
        function h:SetCollapsed() end
        h.MinimizeButton = CreateFrame("Button", nil, h)
        local tex = h.MinimizeButton:CreateTexture()
        function h.MinimizeButton:GetNormalTexture() return tex end
        return h
    end
    otf.Header = header(otf)
    for _, name in ipairs({ "QuestObjectiveTracker", "ScenarioObjectiveTracker" }) do
        local s = CreateFrame("Frame", name, otf)
        s.Header = header(s)
        function s:AddBlock(b) addUsed(self, b) end
        function s:Update() end
    end
end

local function login() return stub.Load({ infopanel = true, before = world }) end

local function newBlock(parent, questID)
    local b = CreateFrame("Frame", nil, parent)
    b.id = questID
    b.HeaderText = b:CreateFontString()
    local pb = CreateFrame("Button", nil, b)
    pb:SetSize(20, 20)
    pb.Display = CreateFrame("Frame", nil, pb)
    pb.Display.Icon = pb.Display:CreateTexture()
    local normal = pb:CreateTexture()
    function pb:GetNormalTexture() return normal end
    b.poiButton = pb
    local line = CreateFrame("Frame", nil, b)
    line.Text = line:CreateFontString()
    line.Dash = line:CreateFontString()
    return b, line
end

T.test("tracker: our layout puts the game's tracker under the panel by screen offsets, not on our frame", function()
    login()
    local Tr = stub.infopanel.Tracker
    Tr.anchor.x, Tr.anchor.y = 1200, 500
    local layout = { systems = { { system = 12, systemIndex = nil, settings = {} } } }
    T.falsy(Tr.Current(layout), "a layout without it needs rewriting")
    Tr.Fill(layout)
    local a = layout.systems[1].anchorInfo
    T.eq(a.relativeTo, "UIParent", "never tied to a frame of ours (it would taint the game's tracker)")
    T.eq(a.point, "TOPRIGHT"); T.eq(a.relativePoint, "TOPRIGHT")
    T.near(a.offsetX, 1200 - UIParent:GetWidth(), 0.1)
    T.near(a.offsetY, 500 - UIParent:GetHeight(), 0.1)
    T.truthy(Tr.Current(layout))
    Tr.anchor.y = 460
    T.falsy(Tr.Current(layout), "the panel grew: the spot needs rewriting")
    T.isnil(DaylightUI.EditMode.GetSetting(layout.systems[1], 1), "its background is the player's (Edit Mode)")
end)

T.test("tracker: the screen changing size places the anchor again, so the spot written stays right", function()
    login()
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    local bottom = 700
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return bottom end
    Tr.Apply(DaylightUI:Get("InfoPanel", "tracker"))
    stub.RunTimers()
    local _, y0 = Tr.Spot()
    -- 86 taller (a smaller UI scale): the panel hangs from the top, so its
    -- bottom rises too.
    stub.SetScreen(1920, 1080, 768 / (UIParent:GetHeight() + 86))
    bottom = 786
    stub.FireEvent("UI_SCALE_CHANGED")
    stub.RunTimers()
    local _, y1 = Tr.Spot()
    T.near(y1, y0, 0.1, "same distance from the screen's top as before")
end)

T.test("tracker: the anchor sits under the panel's bottom-right corner", function()
    login()
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 700 end
    Tr.Apply(DaylightUI:Get("InfoPanel", "tracker"))
    local point, rel, relPoint, x, y = Tr.anchor:GetPoint(1)
    T.eq(point, "TOPRIGHT"); T.eq(rel, UIParent); T.eq(relPoint, "BOTTOMLEFT")
    T.eq(x, 1900 - Tr.EDGE, "just in from the panel's right edge")
    T.eq(y, 700 - P.GAP, "right under the panel")
    -- Not in combat: whatever hangs from it mustn't move then.
    stub.EnterCombat()
    function P.panel:GetBottom() return 500 end
    Tr.Apply(DaylightUI:Get("InfoPanel", "tracker"))
    local _, _, _, _, y2 = Tr.anchor:GetPoint(1)
    T.eq(y2, y, "held until combat ends")
    stub.LeaveCombat()
    local _, _, _, _, y3 = Tr.anchor:GetPoint(1)
    T.truthy(y3 < y, "then moved")
end)

T.test("tracker: moved in unlock mode, it goes there (per profile) and the layout is saved on lock", function()
    login()
    local DUI = DaylightUI
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 700 end
    local e = DUI.Movers.Get(Tr.MOVER)
    T.truthy(e and e.proxy, "a handle in unlock mode; the game's tracker itself is never moved")
    local hx, hy = e.home()
    T.near(hx + Tr.stand:GetWidth() / 2 + UIParent:GetWidth() / 2, 1900, 0.1, "unmoved, the handle sits under the panel")
    T.near(hy + Tr.stand:GetHeight() / 2 + UIParent:GetHeight() / 2, 700 - P.GAP, 0.1)
    local saves = 0
    local EM = DUI.EditMode
    local exists, upToDate, save, active = EM.Exists, EM.UpToDate, EM.Save, EM.IsActive
    EM.Exists = function() return true end
    EM.UpToDate = function() return false end
    EM.Save = function() saves = saves + 1 end
    -- On a layout of the player's own, the spot is theirs to set in Edit Mode:
    -- saving would switch them onto Daylight UI's.
    EM.IsActive = function() return false end
    DUI.Movers.Unlock()
    e.onMoved(Tr.MOVER)
    DUI.Movers.Lock()
    T.eq(saves, 0, "not saved on a layout of their own")
    EM.IsActive = function() return true end
    DUI.Movers.Unlock()
    DUI.DB.Positions()[Tr.MOVER] = { -300, 100 }
    e.onMoved(Tr.MOVER)
    DUI.Movers.Lock()
    T.eq(saves, 1, "locking writes the layout and asks for a reload")
    local cx, cy = Tr.Corner()
    T.near(cx, UIParent:GetWidth() / 2 - 300 + Tr.stand:GetWidth() / 2, 0.1, "the handle's top-right corner")
    T.near(cy, UIParent:GetHeight() / 2 + 100 + Tr.stand:GetHeight() / 2, 0.1)
    local _, _, _, x = Tr.anchor:GetPoint(1)
    T.eq(x, cx - Tr.EDGE, "the anchor follows it, not the panel")
    local layout = { systems = { { system = 12, systemIndex = nil, settings = {} } } }
    Tr.Fill(layout)
    T.near(layout.systems[1].anchorInfo.offsetX, cx - Tr.EDGE - UIParent:GetWidth(), 0.1, "and so does the layout")
    -- Locked again with nothing moved: no second write.
    DUI.Movers.Unlock(); DUI.Movers.Lock()
    T.eq(saves, 1)
    -- Reset: back under the panel.
    DUI.Movers.Reset(Tr.MOVER)
    DUI.Movers.Unlock(); DUI.Movers.Lock()
    local _, _, _, x2 = Tr.anchor:GetPoint(1)
    T.eq(x2, 1900 - Tr.EDGE)
    T.eq(saves, 2)
    EM.Exists, EM.UpToDate, EM.Save, EM.IsActive = exists, upToDate, save, active
end)

T.test("tracker: the anchor always has a place, and waits for the panel's", function()
    login()
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    T.eq(Tr.anchor:GetNumPoints(), 1, "a starting spot before the panel is laid out")
    local _, rel = Tr.anchor:GetPoint(1)
    T.eq(rel, UIParent)
    -- The panel has no edges yet: nothing moves, and it tries again.
    Tr.Apply(DaylightUI:Get("InfoPanel", "tracker"))
    local _, _, _, x0 = Tr.anchor:GetPoint(1)
    T.eq(x0, Tr.START[1], "still the starting spot")
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 700 end
    stub.RunTimers()
    local _, _, rp, x = Tr.anchor:GetPoint(1)
    T.eq(rp, "BOTTOMLEFT"); T.eq(x, 1900 - Tr.EDGE, "placed once the panel has its place")
end)

T.test("tracker: once the game's tracker sits under the panel, moving the panel leaves it (no reload asked)", function()
    local DUI = login()
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    local EM = DUI.EditMode
    local exists, upToDate, autoSave = EM.Exists, EM.UpToDate, EM.AutoSave
    local current, asked = false, 0
    EM.Exists = function() return true end
    EM.UpToDate = function() return current end
    EM.AutoSave = function() asked = asked + 1 end
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 700 end
    -- The layout lags behind: it follows the panel, as before.
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    T.falsy(DUI.DB.Positions()[Tr.MOVER], "not its own spot until the layout has it")
    local _, _, _, x0, y0 = Tr.anchor:GetPoint(1)
    T.eq(x0, 1900 - Tr.EDGE)
    -- The layout has it (after the reload): that spot becomes its own.
    current = true
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    T.truthy(DUI.DB.Positions()[Tr.MOVER], "pinned")
    asked = 0
    function P.panel:GetRight() return 1500 end
    function P.panel:GetBottom() return 400 end
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    local _, _, _, x1, y1 = Tr.anchor:GetPoint(1)
    T.near(x1, x0, 0.1, "stays where it was"); T.near(y1, y0, 0.1)
    T.eq(asked, 0, "no reload popup")
    -- Reset in unlock mode: under the panel again.
    DUI.Movers.Reset(Tr.MOVER)
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    local _, _, _, x2 = Tr.anchor:GetPoint(1)
    T.eq(x2, 1500 - Tr.EDGE)
    EM.Exists, EM.UpToDate, EM.AutoSave = exists, upToDate, autoSave
end)

-- From a player report: moved a little lower under the panel, it snapped back
-- at the next login. Only the default spot follows the strip, never a hand-moved one.
T.test("tracker: a spot moved by hand just under the panel stays put", function()
    local DUI = login()
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return 700 end
    local hx, hy = Tr.Home()
    -- Dragged one grid step lower in unlock mode (as a drop saves it).
    DUI.DB.Positions()[Tr.MOVER] = { hx, hy - DUI.Movers.GRID }
    local spot = DUI.DB.Copy(DUI.DB.Positions()[Tr.MOVER])
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    T.deq(DUI.DB.Positions()[Tr.MOVER], spot, "kept")
    -- The spot pinned for it under the panel still follows the strip.
    DUI.DB.Positions()[Tr.MOVER] = nil
    local EM = DUI.EditMode
    local exists, upToDate = EM.Exists, EM.UpToDate
    EM.Exists = function() return true end
    EM.UpToDate = function() return true end
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    local pinned = DUI.DB.Positions()[Tr.MOVER]
    T.truthy(pinned, "pinned")
    function P.panel:GetBottom() return 700 - stub.infopanel.DataTexts.Room({ data = { enabled = true, textSize = 11 } }) end
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    T.truthy(DUI.DB.Positions()[Tr.MOVER][2] < pinned[2], "followed the strip down")
    EM.Exists, EM.UpToDate = exists, upToDate
end)

-- From a player report: with the Quests module off, changing the minimap's size
-- or the data texts' font asked for a reload each time. The panel growing a
-- little is nobody's request to move the tracker, so it follows without a
-- write or a question while playing, and the layout is written on the way out.
T.test("tracker: the panel growing moves the spot without a reload question; the layout is written at logout", function()
    local layouts = {}
    local DUI = stub.Load({ infopanel = true, before = function()
        world()
        Enum.EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 }
        local function tracker() return { system = 12, settings = {}, anchorInfo = { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", offsetX = -100, offsetY = -300 } } end
        _G.EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function()
            return { { layoutIndex = 1, layoutType = 0, layoutName = "Modern", systems = { tracker() } } }
        end }
        layouts.list = { { layoutType = 1, layoutName = "DaylightUI - DPS/Tank", systems = { tracker() } } }
        layouts.active = 2
        _G.C_EditMode = {
            GetLayouts = function() return { layouts = DaylightUI.DB.Copy(layouts.list), activeLayout = layouts.active } end,
            SaveLayouts = function(info)
                layouts.list = {}
                for _, l in ipairs(info.layouts) do if l.layoutType ~= 0 then layouts.list[#layouts.list + 1] = l end end
                layouts.saves = (layouts.saves or 0) + 1
            end,
            SetActiveLayout = function(i) layouts.active = i end,
        }
        _G.EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
        EditModeManagerFrame.accountSettings = {}
        EditModeManagerFrame:Hide()
        DaylightUIDB = { installerSeen = 1e9 }
    end })
    local P, Tr = stub.infopanel.Panel, stub.infopanel.Tracker
    -- The layout already has the tracker under the panel, as after the reload
    -- that put it there.
    local a = layouts.list[1].systems[1].anchorInfo
    a.offsetX = 1900 - Tr.EDGE - UIParent:GetWidth()
    a.offsetY = 700 - P.GAP - UIParent:GetHeight()
    local bottom = 700
    function P.panel:GetRight() return 1900 end
    function P.panel:GetBottom() return bottom end
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    stub.RunTimers()
    T.isnil(stub.Asked(), "in place: nothing to ask")
    T.isnil(layouts.saves, "and nothing written")
    T.truthy(DUI.DB.Positions()[Tr.MOVER], "its spot is its own from here")
    local _, _, _, _, y0 = Tr.anchor:GetPoint(1)
    -- A bigger data text font: the strip under the map grows a few pixels.
    bottom = 696
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    stub.RunTimers()
    local _, _, _, _, y1 = Tr.anchor:GetPoint(1)
    T.near(y1, y0 - 4, 0.1, "the spot follows the strip")
    T.isnil(stub.Asked(), "no reload question for a change nobody asked the tracker for")
    T.isnil(layouts.saves, "no layout write while playing")
    bottom = 692
    Tr.Apply(DUI:Get("InfoPanel", "tracker"))
    stub.RunTimers()
    T.isnil(stub.Asked(), "nor for the next one")
    -- Leaving (a logout or a reload): the layout gets the spot, so it's in place next time.
    stub.FireEvent("PLAYER_LOGOUT")
    T.eq(layouts.saves, 1, "written once on the way out")
    T.near(layouts.list[1].systems[1].anchorInfo.offsetY, 692 - P.GAP - UIParent:GetHeight(), 0.1)
    T.isnil(stub.Asked(), "and still no question")
    _G.C_EditMode, _G.EditModeManagerFrame, _G.EditModePresetLayoutManager = nil, nil, nil
end)

T.test("tracker: the game's tracker keeps its own look (only placed and faded)", function()
    login()
    T.eq(ObjectiveTrackerFrame.Header:GetAlpha(), 1, "All Objectives left alone")
    T.eq(ObjectiveTrackerFrame.NineSlice:GetAlpha(), 1)
    local qh = QuestObjectiveTracker.Header
    T.isnil(qh.Background.__masks, "the game's header art left alone")
    T.isnil(qh.Text.__font, "the game's font")
    local b = newBlock(QuestObjectiveTracker, 1)
    QuestObjectiveTracker:AddBlock(b)
    T.isnil(b.HeaderText.__font)
    T.isnil(b.poiButton:GetNormalTexture().__masks, "its markers left alone")
    T.isnil(_G.DaylightUITrackerBox, "no box of ours behind it")
end)

-- Last: puts back what world() cleared, for the files that run after this one.
T.test("tracker: leaves the fake Edit Mode as it found it", function()
    _G.C_EditMode = savedEditMode
end)

T.test("tracker: stands down when our own quest tracker draws the quests", function()
    -- The XP bar reads these as the info panel loads (test_infopanel's world sets them).
    local function before() world(); _G.UnitXP = function() return 0 end; _G.UnitXPMax = function() return 100 end end
    stub.Load({ infopanel = true, before = before, login = false })
    DaylightUI.questsOwnTracker = true
    stub.FireEvent("PLAYER_LOGIN")
    DaylightUI.Fade.SkipIntro()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Tr = stub.infopanel.Tracker
    T.eq(Tr.Replaced(), true)
    T.isnil(DaylightUI.Movers.Get("infopanel.tracker"), "no handle of its own")
    T.truthy(_G.DaylightUITrackerAnchor, "the anchor our tracker hangs from is still there")
end)
