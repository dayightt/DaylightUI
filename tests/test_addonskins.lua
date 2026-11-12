local stub = require("stub")

-- Skins for other people's addons (DaylightUI_Skins/Packs/Addons): the framework's
-- promises. A skin waits for its addon, a broken one is reported once and left
-- alone, and its switch only shows while the addon is installed.

local function login(before)
    stub.Load({ skins = true, before = function()
        _G.DaylightUIDB = { modules = { NPC = { enabled = false }, Professions = { enabled = false }, Social = { enabled = false } } }
        if before then before() end
    end })
    stub.RunTimers()
    return stub.skins
end

-- A fake addon: its window made as it loads.
local function loadFake(name)
    stub.installedAddOns[name] = true
    stub.loadedAddOns[name] = true
    local f = CreateFrame("Frame", name .. "Window", UIParent)
    f:SetSize(300, 200)
    f.Bg = f:CreateTexture()
    stub.FireEvent("ADDON_LOADED", name)
    stub.RunTimers()
    return f
end

T.test("addon skins: a skin waits for its addon, then dresses its window", function()
    local SK = login()
    local applied = 0
    DaylightUI.Skins.Register({ key = "fakeOne", addon = "FakeOne", switch = "fakeOne", apply = function(Kit)
        applied = applied + 1
        Kit.Window(_G.FakeOneWindow)
    end })
    stub.RunTimers()
    T.eq(applied, 0, "not before its addon loads")
    local f = loadFake("FakeOne")
    T.eq(applied, 1, "once, as it loads")
    T.truthy(SK.Kit.ShellOf(f), "in our look")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("addon skins: a broken skin is named once in chat and stops, no error", function()
    login()
    local tries = 0
    local def = { key = "fakeTwo", addon = "FakeTwo", label = "Fake Two", apply = function()
        tries = tries + 1
        error("its frames changed")
    end }
    stub.addonMeta.FakeTwo = { Version = "2.0" }
    DaylightUI.Skins.Register(def)
    loadFake("FakeTwo")
    T.eq(#stub.errors, 0, "no error box over another addon's change")
    T.truthy(stub.ChatContains("Fake Two 2.0"), "named once, with its version")
    T.truthy(def.broken, "stopped")
    stub.FireEvent("ADDON_LOADED", "Anything")
    stub.RunTimers()
    T.eq(tries, 1, "never tried again")
    -- A hook it set later goes the same way, quietly.
    local hook = stub.skins.Engine.Safe(def, function() error("nope") end)
    hook()
    T.eq(#stub.errors, 0)
end)

T.test("addon skins: a hook's error stops that skin, said once", function()
    login()
    local def = { key = "fakeHook", addon = "FakeHook", label = "Fake Hook", apply = function() end }
    DaylightUI.Skins.Register(def)
    loadFake("FakeHook")
    local hook = stub.skins.Engine.Safe(def, function() error("a widget changed") end)
    local before = #stub.chat
    hook(); hook()
    T.eq(#stub.errors, 0)
    T.eq(#stub.chat - before, 1, "one line")
    T.truthy(def.broken)
end)

T.test("addon skins: its switch off leaves the addon as it is", function()
    local applied = false
    login(function()
        DaylightUIDB.modules.Skins = { addonSkins = { fakeThree = false } }
    end)
    DaylightUI.Skins.Register({ key = "fakeThree", addon = "FakeThree", switch = "fakeThree", apply = function() applied = true end })
    loadFake("FakeThree")
    T.falsy(applied)
end)

T.test("addon skins: the Other addons switches show only for installed addons", function()
    local SK = login(function() stub.installedAddOns.Questie = true end)
    local Options = DaylightUI.Options
    local page
    local found = {}
    for _, p in Options.Pages() do
        for _, g in ipairs(p.groups or {}) do
            for _, item in ipairs(g.items or {}) do
                if type(item.key) == "string" and item.key:find("^addonSkins%.") then found[item.key] = item; page = p end
            end
        end
    end
    T.truthy(page, "the skins page")
    local questie, rxp = found["addonSkins.questie"], found["addonSkins.rxp"]
    T.truthy(questie and rxp, "a switch per addon skin")
    T.falsy(Options.IsHidden(page, questie), "Questie installed: shown")
    T.truthy(Options.IsHidden(page, rxp), "RestedXP not installed: hidden")
    T.truthy(SK.Engine.Installed({ addon = "Questie" }))
    T.falsy(stub.ChatContains("Options ("), "each switch has a default: no complaint at login")
end)

-- ---------------------------------------------------------------------
-- Ace3 (AceGUI-3.0.lua, minor 41). A widget's constructor ends with
-- AceGUI:RegisterAsWidget(widget) / RegisterAsContainer, with its type set.
-- ---------------------------------------------------------------------

local function fakeAceGUI()
    local lib = {}
    function lib:RegisterAsWidget(w) w.frame.obj = w; return w end
    function lib:RegisterAsContainer(w) w.frame.obj = w; return w end
    local libs = { ["AceGUI-3.0"] = lib }
    _G.LibStub = setmetatable({}, { __call = function(_, name) return libs[name] end })
    return lib
end

local function backdrop(f)
    for _, k in ipairs({ "TopLeftCorner", "TopEdge", "Center" }) do f[k] = f:CreateTexture() end
end

-- Constructors as AceGUI's widgets build them (only what the skin reads).
local ACE = {}
function ACE.Frame(lib)
    local frame = CreateFrame("Frame", nil, UIParent)
    backdrop(frame)
    local close = CreateFrame("Button", nil, frame)
    close.Left, close.Middle, close.Right = close:CreateTexture(), close:CreateTexture(), close:CreateTexture()
    local statusbg = CreateFrame("Button", nil, frame)
    backdrop(statusbg)
    local w = { type = "Frame", frame = frame, content = CreateFrame("Frame", nil, frame),
        titletext = frame:CreateFontString(), statustext = statusbg:CreateFontString(), close = close }
    return lib:RegisterAsContainer(w)
end
function ACE.CheckBox(lib)
    local frame = CreateFrame("Button", nil, UIParent)
    local w = { type = "CheckBox", frame = frame, checkbg = frame:CreateTexture(), highlight = frame:CreateTexture(),
        text = frame:CreateFontString() }
    w.check = frame:CreateTexture()
    w.checkbg:SetSize(24, 24)
    function w:SetValue(v) self.checked = v end
    function w:SetDisabled(d) self.disabled = d end
    function w:SetType() end
    function w:SetTriState() end
    return lib:RegisterAsWidget(w)
end
function ACE.TabGroup(lib)
    local frame = CreateFrame("Frame", nil, UIParent)
    local border = CreateFrame("Frame", nil, frame)
    backdrop(border)
    local w = { type = "TabGroup", frame = frame, border = border, tabs = {}, content = CreateFrame("Frame", nil, border) }
    function w:BuildTabs()
        for i = #self.tabs + 1, 2 do
            local tab = CreateFrame("Button", nil, border)
            tab.Left, tab.Middle, tab.Right = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
            tab.Text = tab:CreateFontString()
            tab.selected = (i == 1)
            self.tabs[i] = tab
        end
    end
    return lib:RegisterAsContainer(w)
end

T.test("ace3: a widget made after the start is dressed at once, by its type", function()
    local lib
    local SK = login(function() lib = fakeAceGUI() end)
    local Kit = SK.Kit
    local frame = ACE.Frame(lib)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(Kit.ShellOf(frame.frame), "the window in our look")
    T.eq(frame.frame.Center:GetAlpha(), 0, "its backdrop gone")
    T.eq(frame.titletext.__font[1], DaylightUI.Style.FONT, "our font on its title")
    T.truthy(Kit.ButtonOf(frame.close), "its Close is our button")
    T.truthy(Kit.ShellOf(frame.statustext:GetParent()), "its status line a box of ours")
    -- An addon's own button laid on it later (Questie's "My Journey").
    frame.frame:Hide()
    local later = CreateFrame("Button", nil, frame.frame)
    later.Left, later.Middle, later.Right = later:CreateTexture(), later:CreateTexture(), later:CreateTexture()
    T.falsy(Kit.ButtonOf(later))
    frame.frame:Show()
    T.truthy(Kit.ButtonOf(later), "a button added later is ours once the window opens")

    local cb = ACE.CheckBox(lib)
    local sw = SK.Ace3.switchOf[cb]
    T.truthy(sw, "a checkbox is our switch")
    T.eq(cb.checkbg:GetAlpha(), 0, "its box gone")
    T.falsy(sw.on)
    cb:SetValue(true)
    T.truthy(sw.on, "follows AceGUI's SetValue")
    cb:SetDisabled(true)
    T.truthy(sw.off, "dimmed while off")

    local tg = ACE.TabGroup(lib)
    tg:BuildTabs()
    T.truthy(Kit.TabOf(tg.tabs[1]) and Kit.TabOf(tg.tabs[2]), "tabs made later are our tabs")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.LibStub = nil
end)

T.test("ace3: a library that comes with an addon loaded later is hooked then; a newer copy hooked again", function()
    login()
    T.falsy(_G.LibStub and _G.LibStub("AceGUI-3.0", true))
    local lib = fakeAceGUI()
    stub.FireEvent("ADDON_LOADED", "Questie")
    local f = ACE.Frame(lib)
    T.truthy(stub.skins.Kit.ShellOf(f.frame), "dressed")
    -- A newer copy replaces the library's functions in place (LibStub).
    function lib:RegisterAsContainer(w) w.frame.obj = w; return w end
    stub.FireEvent("ADDON_LOADED", "RXPGuides")
    local g = ACE.Frame(lib)
    T.truthy(stub.skins.Kit.ShellOf(g.frame), "still dressed")
    _G.LibStub = nil
end)

T.test("ace3: a widget that breaks the skin is named once, the rest left as they are", function()
    local lib
    login(function() lib = fakeAceGUI() end)
    local w = { type = "CheckBox", frame = CreateFrame("Button", nil, UIParent) }   -- AceGUI changed
    w.checkbg = setmetatable({}, { __index = function() error("changed") end })
    lib:RegisterAsWidget(w)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(stub.ChatContains("Ace3"), "named once")
    local f = ACE.Frame(lib)
    T.falsy(stub.skins.Kit.ShellOf(f.frame), "stopped: later ones left alone")
    _G.LibStub = nil
end)

-- A SharedMedia picker (prototypes.lua in AceGUI-3.0-SharedMediaWidgets). Its
-- arrow opens a pooled list frame that gets its dialog backdrop again each time
-- it's returned, filled with pooled lines.
local function fakeMediaPicker(lib, kindName)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame.label, frame.text = frame:CreateFontString(), frame:CreateFontString()
    frame.DLeft, frame.DMiddle, frame.DRight = frame:CreateTexture(), frame:CreateTexture(), frame:CreateTexture()
    frame.dropButton = CreateFrame("Button", nil, frame)
    local w = { type = kindName, frame = frame }
    local list = CreateFrame("Frame", nil, UIParent)
    backdrop(list)
    list.slider = CreateFrame("Slider", nil, list)
    list.contentRepo = {}
    local line = CreateFrame("Button", nil, list)
    line.text = line:CreateFontString()
    frame.dropButton:SetScript("OnClick", function()
        if w.dropdown then
            list.Center:SetAlpha(1)          -- ReturnDropDownFrame sets the backdrop again
            w.dropdown = nil
        else
            list.contentRepo[1] = line
            w.dropdown = list
        end
    end)
    lib:RegisterAsWidget(w)
    return w, list, line
end

T.test("ace3: a SharedMedia picker's open list is ours, each time it opens", function()
    local lib
    local SK = login(function() lib = fakeAceGUI() end)
    local Kit = SK.Kit
    local w, list, line = fakeMediaPicker(lib, "LSM30_Statusbar")
    T.eq(w.frame.DMiddle:GetAlpha(), 0, "the box's art gone")
    w.frame.dropButton:Click()
    T.truthy(Kit.ShellOf(list), "the list in our look")
    T.eq(list.Center:GetAlpha(), 0, "its dialog backdrop gone")
    T.truthy(SK.Ace3.lines[line], "its lines dressed")
    w.frame.dropButton:Click()                      -- closed, so the pool gives it its backdrop back
    w.frame.dropButton:Click()
    T.eq(list.Center:GetAlpha(), 0, "gone again on the next opening")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.LibStub = nil
end)

T.test("ace3: a font picker keeps each font as its own; a border picker shows the hovered border", function()
    local lib
    login(function() lib = fakeAceGUI() end)
    local font = fakeMediaPicker(lib, "LSM30_Font")
    T.falsy(font.frame.text.__font and font.frame.text.__font[1] == DaylightUI.Style.FONT, "the font picker's text keeps its font")
    local border, list, line = fakeMediaPicker(lib, "LSM30_Border")
    line:SetScript("OnEnter", function() end)       -- its own, which sets the hovered border's backdrop
    line.dropdown = list
    border.frame.dropButton:Click()
    T.eq(list.Center:GetAlpha(), 0)
    line:GetScript("OnEnter")(line)
    T.eq(list.Center:GetAlpha(), 1, "the hovered border shows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.LibStub = nil
end)

T.test("ace3: switched off, nothing is dressed", function()
    local lib
    login(function()
        lib = fakeAceGUI()
        DaylightUIDB.modules.Skins = { addonSkins = { ace3 = false } }
    end)
    local f = ACE.Frame(lib)
    T.falsy(stub.skins.Kit.ShellOf(f.frame))
    _G.LibStub = nil
end)

-- ---------------------------------------------------------------------
-- Questie's tracker steps aside for Daylight UI's
-- ---------------------------------------------------------------------

T.test("questie: its tracker off while ours draws, back when ours is gone", function()
    login(function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { db = { profile = { trackerEnabled = true, enableMapIcons = true, enableMiniMapIcons = true } } }
    end)
    local Engine = stub.skins.Engine
    local profile = Questie.db.profile
    DaylightUI.questsOwnTracker = true
    T.truthy(DaylightUI.QuestieAside.Run())
    T.eq(profile.trackerEnabled, false, "its tracker never builds")
    T.truthy(DaylightUI.DB.Root().questieOff.trackerEnabled, "we note we did it")
    T.eq(profile.enableMapIcons, true, "our map marks aren't drawing (Quests not loaded): its icons stay")
    DaylightUI.questsOwnTracker = nil
    DaylightUI.QuestieAside.Run()
    T.eq(profile.trackerEnabled, true, "ours gone: Questie's is back")
    T.falsy(DaylightUI.DB.Root().questieOff, "nothing left noted")
    -- Switched off by the player themself, not by the addon, so it's left off.
    profile.trackerEnabled = false
    DaylightUI.QuestieAside.Run()
    T.eq(profile.trackerEnabled, false)
    _G.Questie = nil
end)

T.test("questie: its tracker steps aside with the Skins module off too (the core does it)", function()
    stub.Load({ before = function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { db = { profile = { trackerEnabled = true, enableMapIcons = true, enableMiniMapIcons = true } } }
    end })
    T.falsy(DaylightUI:GetModule("Skins"), "no Skins module")
    DaylightUI.questsOwnTracker = true
    DaylightUI.Fire("QuestMapsChanged")      -- Quests' OnEnable fires it
    T.eq(Questie.db.profile.trackerEnabled, false, "one tracker, ours")
    DaylightUI.questsOwnTracker = nil
    _G.Questie = nil
end)

T.test("questie: its map icons and NPC tooltips we switched off once come back, the player's own stay off", function()
    login(function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { db = { profile = { trackerEnabled = true, enableMapIcons = false, enableMiniMapIcons = false,
                                          showQuestsInNpcTooltip = false, mapCoordinatesEnabled = false } } }
        _G.DaylightUIDB = { questieOff = { enableMapIcons = true, showQuestsInNpcTooltip = true } }
    end)
    DaylightUI.QuestieAside.Run()
    local p = Questie.db.profile
    T.eq(p.enableMapIcons, true, "ours are gone: its world map icons back")
    T.eq(p.showQuestsInNpcTooltip, true, "and its NPC tooltips")
    T.eq(p.enableMiniMapIcons, false, "one we never switched off stays as the player has it")
    T.eq(p.mapCoordinatesEnabled, false)
    _G.Questie = nil
end)

T.test("questie: its objective icons in our art while its skin is on, the player's own back when off", function()
    local reset = 0
    login(function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { db = { profile = { ICON_SLAY = "their.blp", questObjectiveColors = false } },
                       SetIcons = function() reset = reset + 1 end }
    end)
    local p = Questie.db.profile
    DaylightUI.QuestieAside.Run()
    T.eq(p.ICON_SLAY, "Interface\\AddOns\\DaylightUI\\Media\\objective-kill.png", "our sword")
    T.eq(p.ICON_LOOT, "Interface\\AddOns\\DaylightUI\\Media\\objective-loot.png")
    T.eq(p.questObjectiveColors, true, "each quest its own color")
    T.truthy(reset > 0, "Questie reads its icon list again")
    local was = reset
    DaylightUI.QuestieAside.Run()
    T.eq(reset, was, "nothing changed: not again")
    DaylightUI:Set("Skins", "addonSkins.questie", false)
    DaylightUI.QuestieAside.Run()
    T.eq(p.ICON_SLAY, "their.blp", "the player's own pick back")
    T.isnil(p.ICON_LOOT, "one they never set: unset again")
    T.eq(p.questObjectiveColors, false)
    T.isnil(DaylightUI.DB.Root().questieIcons, "nothing kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.Questie = nil
end)

-- ---------------------------------------------------------------------
-- RestedXP (GuideWindow.lua): RXPFrame and its parts
-- ---------------------------------------------------------------------

local function fakeRXP()
    local f = CreateFrame("Frame", "RXPFrame", UIParent)
    f.BottomFrame = CreateFrame("Frame", "RXPFrame_bottomFrame", f)
    backdrop(f.BottomFrame)
    local name = CreateFrame("Frame", "RXPFrameGuideName", f)
    backdrop(name)
    name.bg = name:CreateTexture()
    name.icon = name:CreateTexture()
    f.Footer = CreateFrame("Frame", nil, f)
    backdrop(f.Footer)
    f.CurrentStepFrame = CreateFrame("Frame", nil, f)
    f.CurrentStepFrame.framePool = {}
    function f.CurrentStepFrame.UpdateText() end
    f.ScrollChild = CreateFrame("Frame", "RXPFrame_bottomFrame_steps", f.BottomFrame)
    f.ScrollChild.framePool = {}
    function f.BottomFrame.UpdateFrame() end
    function f:UpdateVisuals() end
    return f
end

local function step(f)
    local s = CreateFrame("Frame", nil, f.CurrentStepFrame)
    backdrop(s)
    s.number = CreateFrame("Frame", nil, s)
    backdrop(s.number)
    local el = CreateFrame("Frame", nil, s)
    el.button = CreateFrame("CheckButton", nil, el)
    el.button:SetSize(12, 12)
    s.elements = { el }
    f.CurrentStepFrame.framePool[#f.CurrentStepFrame.framePool + 1] = s
    return s
end

T.test("rxp: the guide window in our look, step boxes as they come up", function()
    local f
    login(function()
        stub.installedAddOns.RXPGuides, stub.loadedAddOns.RXPGuides = true, true
        f = fakeRXP()
    end)
    local Kit = stub.skins.Kit
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(f.BottomFrame.Center:GetAlpha(), 0, "its backdrop gone")
    T.truthy(Kit.ShellOf(f.BottomFrame), "ours")
    T.eq(RXPFrameGuideName.bg:GetAlpha(), 0, "its banner gone")
    T.eq(RXPFrameGuideName.icon:GetAlpha(), 1, "its logo kept")
    local s = step(f)
    f.CurrentStepFrame.UpdateText()
    T.truthy(Kit.ShellOf(s), "a new step box dressed")
    T.truthy(Kit.SwitchOf(s.elements[1].button), "its check mark is our switch")
    local row = CreateFrame("Frame", "RXPFrame_bottomFrame_steps_frame_1", f.ScrollChild)
    backdrop(row)
    f.ScrollChild.framePool[1] = row
    f.BottomFrame.UpdateFrame()
    T.eq(row.Center:GetAlpha(), 0)
    T.truthy(Kit.ShellOf(row), "list rows are our rows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- RestedXP refreshes its list one step at a time, many times a second (its ticker,
-- "/istep" in RXPGuides.lua, and a C_Timer per step), and its top text every cycle.
-- With both addons running the game used 50-65% CPU while each refresh dressed
-- every row and box again.
T.test("rxp: its refreshes dress only what's new, not every row each time", function()
    local f
    login(function()
        stub.installedAddOns.RXPGuides, stub.loadedAddOns.RXPGuides = true, true
        f = fakeRXP()
    end)
    local Kit = stub.skins.Kit
    for i = 1, 100 do
        local row = CreateFrame("Frame", "RXPFrame_bottomFrame_steps_frame_" .. i, f.ScrollChild)
        backdrop(row)
        f.ScrollChild.framePool[i] = row
    end
    local s = step(f)
    f.BottomFrame.UpdateFrame()
    f.CurrentStepFrame.UpdateText()
    T.truthy(Kit.ShellOf(f.ScrollChild.framePool[100]), "every row dressed")
    T.truthy(Kit.ShellOf(s), "the step box dressed")
    local wasRow, wasShell = Kit.Row, Kit.Shell
    local rowCalls, shellCalls = 0, 0
    Kit.Row = function(...) rowCalls = rowCalls + 1; return wasRow(...) end
    Kit.Shell = function(...) shellCalls = shellCalls + 1; return wasShell(...) end
    for n = 1, 50 do
        f.BottomFrame.UpdateFrame(nil, n)
        f.CurrentStepFrame.UpdateText()
    end
    T.eq(rowCalls, 0, "rows already ours: not dressed again")
    T.eq(shellCalls, 0, "step boxes already ours: not laid out again")
    local row = CreateFrame("Frame", "RXPFrame_bottomFrame_steps_frame_101", f.ScrollChild)
    backdrop(row)
    f.ScrollChild.framePool[101] = row
    f.BottomFrame.UpdateFrame(nil, 101)
    T.eq(rowCalls, 1, "a new row: dressed once")
    T.eq(row.Center:GetAlpha(), 0, "its backdrop gone")
    local el = CreateFrame("Frame", nil, s)
    el.button = CreateFrame("CheckButton", nil, el)
    el.button:SetSize(12, 12)
    s.elements[2] = el
    f.CurrentStepFrame.UpdateText()
    T.truthy(Kit.SwitchOf(el.button), "a new line in a box: its check mark ours")
    Kit.Row, Kit.Shell = wasRow, wasShell
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- RestedXP's V2 window (UI/V2/Core.lua): AceGUI widgets of its own, with art drawn
-- by RXP.ui.v2:ApplyFrameBackdrop / AddFrameShadow.
local function fakeRXPv2()
    local ui, v2 = {}, { state = { player = {} } }
    function ui:ApplyFrameBackdrop(frame)
        if not frame.rxpBackground then
            frame.rxpBackground = CreateFrame("Frame", nil, frame)
            frame.rxpBorder = CreateFrame("Frame", nil, frame)
        end
        frame.rxpBackground:Show()
    end
    function ui:AddFrameShadow(frame) frame.rxpShadow = frame.rxpShadow or CreateFrame("Frame", nil, frame) end
    local function window()
        local frame = CreateFrame("Frame", nil, UIParent)
        local w = { frame = frame, upperFrame = CreateFrame("Frame", nil, frame), guideStepsFrame = CreateFrame("Frame", nil, frame) }
        w.guideNameFrame = CreateFrame("Frame", nil, w.upperFrame)
        w.title, w.subtitle = w.guideNameFrame:CreateFontString(), w.guideNameFrame:CreateFontString()
        w.footerText, w.footerBackground, w.banner = frame:CreateFontString(), frame:CreateTexture(), frame:CreateTexture()
        w.closebutton = CreateFrame("Button", nil, w.upperFrame)
        w.settingsButton, w.guideSelectButton = CreateFrame("Button", nil, w.guideNameFrame), CreateFrame("Button", nil, w.guideNameFrame)
        w.sizer = CreateFrame("Button", nil, w.guideStepsFrame)
        w.guideSteps = { items = {} }
        function w.guideSteps:SetRows() end
        function w:UpdateSubTheme()
            for _, p in ipairs({ self.upperFrame, self.guideStepsFrame, self.guideNameFrame }) do ui:ApplyFrameBackdrop(p) end
            ui:AddFrameShadow(self.upperFrame)
            self.title:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        end
        w:UpdateSubTheme()
        return w
    end
    function v2:GetGuideWindow()
        if self.state.guideWindow then return self.state.guideWindow end
        self.state.guideWindow = window()
        return self.state.guideWindow
    end
    local function item()
        local frame = CreateFrame("Frame", nil, UIParent)
        local it = { frame = frame, card = CreateFrame("Frame", nil, frame), elementRows = {}, activeElementRows = 1 }
        it.title = CreateFrame("Frame", nil, it.card)
        it.titletext = it.title:CreateFontString()
        local row = CreateFrame("Frame", nil, it.card)
        row.button = CreateFrame("CheckButton", nil, row)
        row.button.rxpHoverFrame = CreateFrame("Frame", nil, row.button)
        row.text = row:CreateFontString()
        it.elementRows[1] = row
        function it:SetElements() end
        function it:UpdateSubTheme() end
        function it:SetTitle() end
        ui:ApplyFrameBackdrop(it.card)
        ui:ApplyFrameBackdrop(it.title)
        ui:ApplyFrameBackdrop(row.button)
        ui:ApplyFrameBackdrop(row.button.rxpHoverFrame)
        return it
    end
    function v2:UpdatePlayerActiveStepItem(it) it:SetElements() end
    _G.RXP = { ui = { v2 = ui }, v2 = v2 }
    return v2, item
end

T.test("rxp v2: its window and step boxes in our look, its art gone, our font kept", function()
    local v2, item
    login(function()
        stub.installedAddOns.RXPGuides, stub.loadedAddOns.RXPGuides = true, true
        fakeRXP()
        v2, item = fakeRXPv2()
    end)
    local Kit = stub.skins.Kit
    local w = v2:GetGuideWindow()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(Kit.ShellOf(w.frame), "one window of ours round it")
    T.eq(w.upperFrame.rxpBackground:GetAlpha(), 0, "its header art gone")
    T.eq(w.upperFrame.rxpShadow:GetAlpha(), 0, "its shadow gone")
    T.falsy(Kit.ShellOf(w.upperFrame), "its inner panes plain")
    T.eq(w.banner:GetAlpha(), 0, "its banner gone")
    local ours = DaylightUI.Style.FontFile(DaylightUI.Style.WINDOW_SLOT)
    T.eq(w.title.__font[1], ours, "our font")
    w:UpdateSubTheme()                              -- its theme sets its own again
    T.eq(w.title.__font[1], ours, "ours again after its theme")
    T.eq(w.upperFrame.rxpBackground:GetAlpha(), 0)

    local it = item()
    v2:UpdatePlayerActiveStepItem(it)
    stub.RunTimers()
    T.truthy(Kit.ShellOf(it.card), "a step box is a window of ours")
    T.truthy(Kit.ShellOf(it.title), "its Step tab ours")
    local row = it.elementRows[1]
    T.truthy(Kit.ShellOf(row.button), "its line's box ours")
    T.falsy(Kit.ShellOf(row.button.rxpHoverFrame), "its skip hover has no box of its own")
    T.eq(row.button.rxpBackground:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.RXP = nil
end)

T.test("rxp v2: a window made before the skin started is dressed as it starts", function()
    local w
    login(function()
        stub.installedAddOns.RXPGuides, stub.loadedAddOns.RXPGuides = true, true
        fakeRXP()
        local v2 = fakeRXPv2()
        w = v2:GetGuideWindow()
    end)
    stub.RunTimers()
    T.truthy(stub.skins.Kit.ShellOf(w.frame))
    T.eq(w.guideStepsFrame.rxpBackground:GetAlpha(), 0, "its art gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.RXP = nil
end)

T.test("questie: its map coordinates and NPC tooltip quests step aside for ours", function()
    login(function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { db = { profile = { trackerEnabled = true, enableMapIcons = true, enableMiniMapIcons = true,
                                         mapCoordinatesEnabled = true, showQuestsInNpcTooltip = true } } }
    end)
    local Engine = stub.skins.Engine
    local keys = {}
    for _, a in ipairs(DaylightUI.QuestieAside.LIST) do keys[a.key] = a end
    T.truthy(keys.mapCoordinatesEnabled, "coordinates in the list")
    T.truthy(keys.showQuestsInNpcTooltip, "NPC tooltip quests in the list")
    local was1, was2 = keys.mapCoordinatesEnabled.ours, keys.showQuestsInNpcTooltip.ours
    keys.mapCoordinatesEnabled.ours = function() return true end
    keys.showQuestsInNpcTooltip.ours = function() return true end
    DaylightUI.QuestieAside.Run()
    T.eq(Questie.db.profile.mapCoordinatesEnabled, false)
    T.eq(Questie.db.profile.showQuestsInNpcTooltip, false)
    keys.mapCoordinatesEnabled.ours, keys.showQuestsInNpcTooltip.ours = was1, was2
    _G.Questie = nil
end)

-- ---------------------------------------------------------------------
-- ForeverDungeonJournal (Core/Journal.lua): its own BackdropTemplate window
-- ---------------------------------------------------------------------

local function fakeFDJ()
    stub.installedAddOns.ForeverDungeonJournal, stub.loadedAddOns.ForeverDungeonJournal = true, true
    local f = CreateFrame("Frame", "ForeverDungeonJournalFrame", UIParent)
    f.SetBackdrop = function() end
    backdrop(f)
    f.mainTitle = f:CreateFontString()
    f.contentPanel = CreateFrame("Frame", nil, f)
    f.contentPanel.SetBackdrop = f.SetBackdrop
    backdrop(f.contentPanel)
    f.contentParchment = f.contentPanel:CreateTexture()
    f.dungeonBackgroundArt = f.contentPanel:CreateTexture()
    -- A frame whose dressing fails (its frames change between versions) is skipped on its own.
    local odd = CreateFrame("Frame", nil, f)
    odd.SetBackdrop = f.SetBackdrop
    odd.Center = setmetatable({}, { __index = function() error("changed") end })
    local boss = CreateFrame("Button", nil, f.contentPanel)
    boss.SetBackdrop = f.SetBackdrop
    backdrop(boss)
    boss:SetSize(315, 55)
    boss.portrait = boss:CreateTexture()
    boss.name = boss:CreateFontString()
    boss.name:SetTextColor(0.27, 0.18, 0.08)          -- its dark ink for parchment
    function boss:GetBackdropColor() return 0.5, 0.4, 0.2, 1 end
    f.boss = boss
    local tab = CreateFrame("Button", nil, f.contentPanel)
    tab.Left, tab.Middle, tab.Right = tab:CreateTexture(), tab:CreateTexture(), tab:CreateTexture()
    tab.Text = tab:CreateFontString()
    tab:SetSize(90, 22)
    f.bossesTab = tab
    local api = { THEMES = { ["Hall of Thanes"] = { rowSelected = { 0.5, 0.4, 0.2, 1 } } } }
    function api.RefreshHomeCards() end
    function api.ToggleSettingsPanel()
        if _G.ForeverDungeonJournalSettings then return end
        local s = CreateFrame("Frame", "ForeverDungeonJournalSettings", UIParent)
        s.SetBackdrop = f.SetBackdrop
        backdrop(s)
    end
    _G.ForeverDungeonJournal_NS = api
    return f, api
end

T.test("fdj: the journal in our look, its tints gone, its art kept", function()
    local f, api
    login(function() f, api = fakeFDJ() end)
    stub.RunTimers()
    local Kit = stub.skins.Kit
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(Kit.ShellOf(f), "a window of ours")
    T.eq(f.contentPanel.Center:GetAlpha(), 0, "its tinted panel gone")
    T.truthy(Kit.Erased(f.contentParchment), "its parchment erased")
    T.eq(f.dungeonBackgroundArt:GetAlpha(), 1, "the dungeon's picture kept")
    T.truthy(Kit.ShellOf(f.boss), "a boss row is our row")
    T.eq(f.boss.portrait:GetAlpha(), 1, "its portrait kept")
    T.truthy(Kit.TabOf(f.bossesTab), "its Bosses button is our tab")
    T.falsy(Kit.ButtonOf(f.bossesTab), "not a button as well")
    local r = f.boss.name:GetTextColor()
    T.truthy(r > 0.5, "its dark ink made light")
    T.eq(f.mainTitle.__font[1], DaylightUI.Style.FontFile(DaylightUI.Style.WINDOW_SLOT), "our font")
    -- A click makes it repaint its text its own way (locals, nothing to hook).
    f:Show()
    local boss = f.boss
    boss.index = 2
    function api.GetSelectedDungeon() return "Hall of Thanes", 2 end
    boss:HookScript("OnClick", function() boss.name:SetTextColor(0.1, 0.06, 0.02); boss.name:SetFont("Fonts/FRIZQT__.TTF", 14, "") end)
    boss:Click()
    stub.RunTimers()
    T.truthy(select(1, boss.name:GetTextColor()) > 0.5, "our ink again after its repaint")
    T.eq(boss.name.__font[1], DaylightUI.Style.FontFile(DaylightUI.Style.WINDOW_SLOT), "our font again")
    T.truthy(stub.skins.FDJ and true, "picked read from the journal")
    api.ToggleSettingsPanel()
    stub.RunTimers()
    T.truthy(Kit.ShellOf(ForeverDungeonJournalSettings), "its settings window, made later, ours too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.ForeverDungeonJournal_NS = nil
end)

-- Its quest page repaints with no click, on an item's data arriving or a quest log
-- update (its event handler -> RefreshQuestDetail, which ends in
-- FDJ.ApplyQuestDetailScroll in Core/Journal.lua).
T.test("fdj: the quest page stays ours when it repaints by itself", function()
    local f, api
    login(function()
        f, api = fakeFDJ()
        f.questTextInset = CreateFrame("Frame", nil, f)
        f.questDetailContent = CreateFrame("Frame", nil, f.questTextInset)
        f.selectedQuestName = f.questTextInset:CreateFontString()
        f.questDetailText = f.questDetailContent:CreateFontString()
        f.questRewardHeader = f.questDetailContent:CreateFontString()
        function api.ApplyQuestDetailScroll() end
    end)
    stub.RunTimers()
    f:Show()
    f.selectedQuestName:SetTextColor(1, 0.78, 0.16)
    f.questDetailText:SetTextColor(0.1, 0.065, 0.025)
    f.questRewardHeader:SetText("|cffffd36bChoose one reward|r")
    -- Made the first time a quest needs it, in the game's black font.
    f.questAlsoReceiveHeader = f.questDetailContent:CreateFontString()
    f.questAlsoReceiveHeader:SetTextColor(0, 0, 0)
    api.ApplyQuestDetailScroll("quest:1", 100)
    -- No timers run, so in the same frame its dark ink is never drawn.
    local INK = DaylightUI.Style.INK
    T.truthy(select(1, f.questDetailText:GetTextColor()) > 0.5, "its dark ink made light, the same frame")
    T.eq(select(3, f.selectedQuestName:GetTextColor()), INK.VALUE[3], "the quest's name is a title")
    T.eq(select(1, f.questAlsoReceiveHeader:GetTextColor()), INK.LABEL[1], "a heading it makes later is ours too")
    T.eq(f.questRewardHeader:GetText(), "Choose one reward", "its gold code gone from a heading")
    -- A finished objective's muted brown is too dark for Daylight UI's panels.
    f.questDetailText:SetText("|cff6e5c405/7 Bats slain|r")
    api.ApplyQuestDetailScroll("quest:1", 100)
    T.eq(f.questDetailText:GetText(), DaylightUI.Win.Parts.Hex(INK.OFF) .. "5/7 Bats slain|r", "its muted brown our dim ink")
    -- The loot page repaints when an item's data arrives, with no click.
    f.boss.name:SetTextColor(0.1, 0.06, 0.02)
    stub.FireEvent("GET_ITEM_INFO_RECEIVED", 123)
    stub.RunTimers()
    T.truthy(select(1, f.boss.name:GetTextColor()) > 0.5, "the rest gone over after an item arrives")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.ForeverDungeonJournal_NS = nil
end)

-- ---------------------------------------------------------------------
-- NeedRoll (UI/Theme.lua, UI/MainFrame.lua): its Native look, made on first open
-- from the game's templates and its own makers
-- ---------------------------------------------------------------------

-- A font object like the client's (GetFont/SetFont, a color of its own).
local function fakeFont(face, size, r, g, b)
    local o = { face = face, size = size, flags = "", color = { r, g, b } }
    function o:GetFont() return self.face, self.size, self.flags end
    function o:SetFont(a, s, fl) self.face, self.size, self.flags = a, s, fl end
    function o:SetTextColor(cr, cg, cb) self.color = { cr, cg, cb } end
    function o:GetTextColor() return self.color[1], self.color[2], self.color[3] end
    return o
end

local function fakeNeedRoll()
    stub.installedAddOns.NeedRoll, stub.loadedAddOns.NeedRoll = true, true
    _G.NeedRollFontNativeBody = fakeFont("Fonts/FRIZQT__.TTF", 12, 1, 1, 1)
    _G.NeedRollFontNativeHeading = fakeFont("Fonts/FRIZQT__.TTF", 16, 1, 0.82, 0)
    _G.NeedRollFontNativeSection = fakeFont("Fonts/FRIZQT__.TTF", 14, 1, 0.82, 0)
    local nr = {}
    -- Its window, made the first time it opens (UI:Build).
    function _G.NeedRoll_OnCompartmentClick()
        if _G.NeedRollNativeFrame then _G.NeedRollNativeFrame:Show(); return end
        local f = CreateFrame("Frame", "NeedRollNativeFrame", UIParent)
        f:SetSize(900, 600)
        f.TitleContainer = CreateFrame("Frame", nil, f)
        f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
        -- AddNativeTitle: its icon and name in a holder over the emptied title.
        local holder = CreateFrame("Frame", nil, f.TitleContainer)
        holder:CreateTexture()
        holder.name = holder:CreateFontString()
        holder.name:SetText("NeedRoll")
        nr.holder = holder
        -- Theme:CreatePanel (native): the game's inset over its parchment.
        local pane = CreateFrame("Frame", nil, f)
        pane:SetSize(300, 500)
        pane.NineSlice = CreateFrame("Frame", nil, pane)
        pane.parchment = pane:CreateTexture()
        pane.parchment:SetAtlas("collections-background-tile")
        nr.pane = pane
        -- Theme:Row: hover, selected and bar textures, SetSelected.
        local row = CreateFrame("Button", nil, pane)
        row:SetSize(280, 24)
        row.hover, row.selected, row.bar = row:CreateTexture(), row:CreateTexture(), row:CreateTexture()
        row.icon = row:CreateTexture()
        row.name = row:CreateFontString()
        row.name:SetTextColor(0.627, 0.627, 0.627)       -- its muted gray
        function row:SetSelected(on) self.isSelected = on; self.selected:SetShown(on) end
        nr.row = row
        -- Theme:Pill: fill, edge, label, Paint, SetLabel, SetTone.
        local pill = CreateFrame("Button", nil, pane)
        pill:SetSize(80, 20)
        pill.fill, pill.edge = pill:CreateTexture(), pill:CreateTexture()
        pill.text = pill:CreateFontString()
        function pill:Paint() self.text:SetTextColor(1, 0.82, 0) end
        function pill:SetLabel(t) self.text:SetText(t) end
        function pill:SetTone(c) self.tone = c; self:Paint() end
        pill:SetScript("OnEnter", function(self) self:Paint() end)
        nr.pill = pill
        -- Theme:ScrollBar: a track fill, a thumb frame with one line, Update.
        local bar = CreateFrame("Frame", nil, pane)
        bar:SetSize(2, 400)
        bar.track = bar:CreateTexture()
        bar.thumb = CreateFrame("Frame", nil, bar)
        bar.thumb.line = bar.thumb:CreateTexture()
        function bar:Update() end
        nr.bar = bar
        -- Theme:Dialog's box: Theme:Rounded's bg and border.
        local box = CreateFrame("Frame", nil, f)
        box.bg, box.border = box:CreateTexture(), box:CreateTexture()
        nr.box = box
        -- CreateList: a list pane, its label's rule, and a canvas its section card
        -- draws on (Theme:SectionCard, a local of its own), redrawn on every Refresh.
        local list = CreateFrame("Frame", nil, f)
        list.rule = list:CreateTexture(nil, "BORDER")
        list.label = list:CreateFontString()
        list.canvas = CreateFrame("Frame", nil, list)
        list.canvas:SetSize(280, 400)
        list.canvas:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        -- Where things sit, since the fake game lays nothing out: the canvas at
        -- 0, 400, the card 6 in and 40 down, 268 x 120.
        function list.canvas:GetLeft() return 0 end
        function list.canvas:GetTop() return 400 end
        local edge = list.canvas:CreateTexture(nil, "BORDER")
        local fill = list.canvas:CreateTexture(nil, "BACKGROUND")
        for _, t in ipairs({ edge, fill }) do
            function t:GetLeft() return 6 end
            function t:GetTop() return 360 end
            function t:GetRight() return 274 end
            function t:GetBottom() return 240 end
        end
        function list:Refresh()
            for _, t in ipairs({ edge, fill }) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", 6, -40)
                t:SetSize(268, 120)
                t:SetVertexColor(1, 0.82, 0, 0.55)
                t:Show()
            end
        end
        list:Refresh()
        nr.list, nr.listCard = list, edge
        -- A header row: Theme:Row with its thin shut card, plus a card of its own
        -- (OverviewRow: row.card = Theme:SectionCard(pane)).
        local header = CreateFrame("Button", nil, list)
        header:SetSize(260, 30)
        header.hover, header.selected, header.bar = header:CreateTexture(), header:CreateTexture(), header:CreateTexture()
        function header:SetSelected() end
        header.shutFill, header.shutEdge = header:CreateTexture(), header:CreateTexture()
        header.title = header:CreateFontString()
        header.shut = true
        function header:PaintShut() self.title:SetTextColor(1, 0.82, 0) end
        local card = { all = { list:CreateTexture(nil, "BORDER") } }
        function card.Draw() card.all[1]:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4); card.all[1]:SetSize(250, 30); card.all[1]:Show() end
        function card.Hide() card.all[1]:Hide() end
        card.all[1]:Hide()
        header.card = card
        nr.header = header
        -- Theme:Divider: a 1px frame of two gold fades.
        local divider = CreateFrame("Frame", nil, pane)
        divider:SetHeight(1)
        divider:CreateTexture(nil, "ARTWORK")
        divider:CreateTexture(nil, "ARTWORK")
        row.divider = divider
        nr.divider = divider
        -- Theme:ChipUnderline: three parts and Set(color, alpha, thick).
        local chip = CreateFrame("Button", nil, pane)
        chip.text = chip:CreateFontString()
        local lines = { chip:CreateTexture(), chip:CreateTexture(), chip:CreateTexture() }
        function lines:Set(color, alpha) for i = 1, 3 do self[i]:SetVertexColor(color[1], color[2], color[3], alpha) end end
        function lines:Hide() for i = 1, 3 do self[i]:Hide() end end
        chip.lines = lines
        nr.chip = chip
        -- Theme:LabelToggle: word buttons with an underline frame, SetActive.
        local toggle = CreateFrame("Frame", nil, pane)
        toggle.buttons = {}
        for _, word in ipairs({ "Overview", "Details" }) do
            local b = CreateFrame("Button", nil, toggle)
            b.text = b:CreateFontString()
            b.underline = CreateFrame("Frame", nil, b)
            for _ = 1, 3 do b.underline:CreateTexture(nil, "ARTWORK") end
            toggle.buttons[word] = b
        end
        function toggle:SetActive(active)
            for name, b in pairs(self.buttons) do
                b.active = name == active
                b.text:SetTextColor(b.active and 1 or 0.5, b.active and 0.82 or 0.5, b.active and 0 or 0.5)
            end
        end
        toggle:SetActive("Overview")
        nr.toggle = toggle
        -- Theme:CardBackdrop: a holder with a fill and, over the box, its gold outline.
        local recipe = CreateFrame("Frame", nil, pane)
        local holder = CreateFrame("Frame", nil, recipe)
        holder.fill = holder:CreateTexture(nil, "BACKGROUND")
        local outline = CreateFrame("Frame", nil, holder)
        outline.edge = outline:CreateTexture(nil, "BORDER")
        function recipe:FitCard() end
        nr.recipe, nr.recipeEdge = recipe, outline.edge
        f:Show()
    end
    return nr
end

T.test("needroll: its window, made on first open, in our look", function()
    local nr
    login(function() nr = fakeNeedRoll() end)
    local Kit = stub.skins.Kit
    local Style = DaylightUI.Style
    T.isnil(_G.NeedRollNativeFrame, "no window until it's opened")
    -- Its fonts are Daylight UI's from the start: the face, and the ink by what each is for.
    T.eq(NeedRollFontNativeBody.face, Style.FontFile(Style.WINDOW_SLOT), "our font on its body text")
    T.eq(NeedRollFontNativeBody.size, 12, "its size kept")
    T.rgb({ NeedRollFontNativeHeading:GetTextColor() }, Style.INK.LABEL, "headings tan")
    T.rgb({ NeedRollFontNativeBody:GetTextColor() }, Style.INK.TEXT, "body soft white")
    NeedRoll_OnCompartmentClick()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local f = NeedRollNativeFrame
    T.truthy(Kit.ShellOf(f), "a window of ours")
    T.eq(f.TitleContainer.TitleText:GetText(), "NeedRoll", "its name in our title")
    T.eq(nr.holder:GetAlpha(), 0, "its centered title out of sight")
    T.truthy(Kit.Erased(nr.pane.parchment) or nr.pane.parchment:GetAlpha() == 0, "its parchment gone")
    T.truthy(Kit.RowOf(nr.row).line, "a list row is a line of ours")
    T.falsy(Kit.ShellOf(nr.row), "no box on it")
    T.truthy(Kit.Erased(nr.row.hover), "its own hover light gone")
    T.eq(nr.row.icon:GetAlpha(), 1, "its icon kept")
    T.rgb({ nr.row.name:GetTextColor() }, Style.INK.LABEL, "its gray our tan")
    T.truthy(stub.skins.NeedRoll.Pill(nr.pill), "a pill is our button")
    nr.pill:GetScript("OnEnter")(nr.pill)
    T.rgb({ nr.pill.text:GetTextColor() }, DaylightUI.Widgets.BUTTON.text, "its gold label ours after its own paint")
    T.truthy(Kit.Erased(nr.bar.thumb.line), "its thin thumb gone")
    T.truthy(stub.skins.NeedRoll.Thumb(nr.bar), "our pill thumb")
    T.truthy(Kit.ShellOf(nr.box), "a dialog in our shell")
    T.truthy(Kit.Erased(nr.box.bg), "its rounded fill gone")
    -- A click: what it fills is gone over again.
    nr.row:SetSelected(true)
    nr.row.name:SetTextColor(0.627, 0.627, 0.627)
    nr.row:Click()
    stub.RunTimers()
    T.rgb({ nr.row.name:GetTextColor() }, Style.INK.LABEL, "its gray our tan again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.NeedRoll_OnCompartmentClick, _G.NeedRollNativeFrame = nil, nil
    _G.NeedRollFontNativeBody, _G.NeedRollFontNativeHeading, _G.NeedRollFontNativeSection = nil, nil, nil
end)

-- Its minimap button and map links open the window on a click. GLOBAL_MOUSE_UP
-- looks for it, but only while it can still be dressed.
T.test("needroll: a click looks for its window only while it can still be dressed", function()
    local function clicks(NR)
        local look, ran = NR.Look, 0
        NR.Look = function(...) ran = ran + 1; return look(...) end
        for _ = 1, 3 do stub.FireEvent("GLOBAL_MOUSE_UP", "LeftButton") end
        stub.RunTimers()
        NR.Look = look
        return ran
    end
    login(function()
        DaylightUIDB.modules.Skins = { addonSkins = { needroll = false } }
        fakeNeedRoll()
    end)
    T.eq(clicks(stub.skins.NeedRoll), 0, "its switch off: no look on a click")
    login(function()
        fakeNeedRoll()
        _G.NeedRollDB = { skin = "modern" }
    end)
    T.eq(clicks(stub.skins.NeedRoll), 0, "its Modern look (not ours to dress): no look either")
    _G.NeedRollDB = nil
    T.truthy(clicks(stub.skins.NeedRoll) > 0, "its Native look, not made yet: a click looks")
    NeedRoll_OnCompartmentClick()
    stub.RunTimers()
    T.truthy(stub.skins.NeedRoll.reg.done, "dressed")
    T.eq(clicks(stub.skins.NeedRoll), 0, "dressed: clicks are left alone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.NeedRoll_OnCompartmentClick, _G.NeedRollNativeFrame = nil, nil
    _G.NeedRollFontNativeBody, _G.NeedRollFontNativeHeading, _G.NeedRollFontNativeSection = nil, nil, nil
end)

T.test("needroll: a hook that breaks stops the whole skin: no half re-dress after", function()
    login(function() fakeNeedRoll() end)
    NeedRoll_OnCompartmentClick()
    stub.RunTimers()
    local NR, Engine = stub.skins.NeedRoll, stub.skins.Engine
    Engine.Safe(NR.def, function() error("its widget changed") end)()
    local each, ran = NR.Each, 0
    NR.Each = function(...) ran = ran + 1; return each(...) end
    NR.def.again()
    stub.RunTimers()
    NR.Each = each
    T.eq(ran, 0, "its window isn't gone over again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.NeedRoll_OnCompartmentClick, _G.NeedRollNativeFrame = nil, nil
    _G.NeedRollFontNativeBody, _G.NeedRollFontNativeHeading, _G.NeedRollFontNativeSection = nil, nil, nil
end)

T.test("needroll: its gold cards, rules and underlines in our look, after each of its redraws", function()
    local nr
    login(function() nr = fakeNeedRoll() end)
    NeedRoll_OnCompartmentClick()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local Kit, NR = stub.skins.Kit, stub.skins.NeedRoll
    -- The open section's card: theirs erased, Daylight UI's over the same spot.
    T.truthy(Kit.Erased(nr.listCard), "its gold card erased")
    local ours = NR.CardOf(nr.list.canvas)
    T.truthy(ours and ours.fill, "our card instead")
    T.falsy(Kit.ShellOf(ours), "a soft fill, no outline")
    T.eq(ours:GetWidth(), 268, "as wide as its card")
    nr.list:Refresh()                                  -- it redraws it on each scroll step
    T.truthy(Kit.Erased(nr.listCard), "still erased after its redraw")
    nr.listCard:Hide()
    nr.list:Refresh()
    -- A row's own card, drawn and hidden through its table.
    nr.header.card.Draw()
    local rowCard = NR.CardOf(nr.header.card)
    T.truthy(rowCard and Kit.Erased(nr.header.card.all[1]), "a row's card ours too")
    T.truthy(Kit.Erased(nr.header.shutFill) and Kit.Erased(nr.header.shutEdge), "the shut card gone")
    local band = NR.rows[nr.header].band
    T.truthy(band and band:IsShown(), "a shut header on our faint band")
    nr.header.shut = false
    nr.header:PaintShut()
    T.falsy(band:IsShown(), "the open one has its section's card instead")
    T.rgb({ nr.header.title:GetTextColor() }, { DaylightUI.Style.Accent() }, "the open section's name in the accent, after its own paint")
    -- Lines in the faint rule, underlines in the accent.
    local rule = { nr.list.rule:GetVertexColor() }
    T.near(rule[4], NR.RULE[4], 0.01, "the label's rule faint")
    T.truthy(NR.ruled[nr.divider], "the divider ours")
    nr.chip.lines:Set({ 1, 0.82, 0 }, 1, 1.5)
    local r, g, b = DaylightUI.Style.Accent()
    T.rgb({ nr.chip.lines[2]:GetVertexColor() }, { r, g, b }, "a chip's underline in the accent after its own Set")
    T.rgb({ nr.toggle.buttons.Overview.text:GetTextColor() }, { r, g, b }, "the picked word in the accent")
    T.truthy(Kit.Erased(nr.recipeEdge), "a recipe box's gold outline gone")
    T.falsy(Kit.ShellOf(nr.recipe), "its dark fill is the box")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.NeedRoll_OnCompartmentClick, _G.NeedRollNativeFrame = nil, nil
    _G.NeedRollFontNativeBody, _G.NeedRollFontNativeHeading, _G.NeedRollFontNativeSection = nil, nil, nil
end)

-- ---------------------------------------------------------------------
-- Deadly Boss Mods (DBM-StatusBarTimers/DBT.lua, v12.1.18): the global DBT, each
-- bar a "DBT_Bar_<n>" frame holding a StatusBar "<frame>Bar" and its
-- Name/Timer/Icon1/Icon2/Background/Variance by name. Every look change goes
-- through the bars' shared prototype's ApplyStyle, which sets its own font and
-- texture again.
-- ---------------------------------------------------------------------

local DBM_TEXTURE = "Interface/AddOns/DBM-StatusBarTimers/textures/default.blp"

local function fakeDBT()
    stub.installedAddOns["DBM-StatusBarTimers"], stub.loadedAddOns["DBM-StatusBarTimers"] = true, true
    local DBT = { Options = { FontSize = 10, Texture = DBM_TEXTURE, Font = "Fonts/FRIZQT__.TTF", Height = 20 }, bars = {} }
    local ids, n = {}, 0
    local proto = {}
    local mt = { __index = proto }
    function proto:ApplyStyle()
        local name = self.frame:GetName()
        local bar = _G[name .. "Bar"]
        bar:SetSize(195, DBT.Options.Height)
        bar:SetStatusBarTexture(DBT.Options.Texture)
        bar:GetStatusBarTexture():SetTexture(DBT.Options.Texture)   -- in the client the fill takes that file
        _G[name .. "BarName"]:SetFont(DBT.Options.Font, DBT.Options.FontSize, "")
        _G[name .. "BarTimer"]:SetFont(DBT.Options.Font, DBT.Options.FontSize, "")
    end
    function DBT:CreateBar(timer, id, icon, huge, small, color, isDummy, colorType, inlineIcon, keep, fade, countdown,
                           countdownMax, isCooldown, secretText, isSecret)
        if not timer then return end
        n = n + 1
        local frame = CreateFrame("Frame", "DBT_Bar_" .. n, UIParent)
        local bar = CreateFrame("StatusBar", "DBT_Bar_" .. n .. "Bar", frame)
        bar:SetPoint("CENTER", frame, "CENTER")
        local function piece(key, make) _G["DBT_Bar_" .. n .. "Bar" .. key] = make end
        piece("Background", bar:CreateTexture())
        piece("Variance", bar:CreateTexture())
        piece("Icon1", bar:CreateTexture())
        piece("Icon2", bar:CreateTexture())
        piece("Name", bar:CreateFontString())
        piece("Timer", bar:CreateFontString())
        local obj = setmetatable({ frame = frame, id = id }, mt)
        frame.obj = obj
        ids[id] = obj
        self.bars[obj] = true
        _G["DBT_Bar_" .. n .. "BarName"]:SetText(isSecret and secretText or id)
        _G["DBT_Bar_" .. n .. "BarIcon1"]:SetTexture(icon)
        obj:ApplyStyle()
        return obj
    end
    function DBT:GetBar(id) return ids[id] end
    function DBT:GetBarIterator() return pairs(self.bars) end
    function DBT:ApplyStyle() for obj in self:GetBarIterator() do obj:ApplyStyle() end end
    _G.DBT = DBT
    return DBT
end

local function dbmFont(obj, key) return _G[obj.frame:GetName() .. "Bar" .. key].__font end

T.test("dbm: its timer bars in the player's font, bar texture and border; its size and spots stay", function()
    local DBT
    login(function() DBT = fakeDBT() end)
    stub.RunTimers()
    local DUI, Style = DaylightUI, DaylightUI.Style
    local SK = stub.skins
    local first = DBT:CreateBar(30, "Big Slam", 136116)
    local second = DBT:CreateBar(12, "Fire Wave", 136116)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    for _, obj in ipairs({ first, second }) do
        local bar = _G[obj.frame:GetName() .. "Bar"]
        T.eq(dbmFont(obj, "Name")[1], Style.FontFile(), "the Appearance font")
        T.eq(dbmFont(obj, "Name")[3], Style.Outline(), "its outline")
        T.eq(dbmFont(obj, "Timer")[1], Style.FontFile(), "its time too")
        T.eq(dbmFont(obj, "Name")[2], 10 * DUI:Get("general", "fontScale"), "DBM's own size, with the font scale")
        T.eq(bar:GetStatusBarTexture():GetTexture(), Style.BarFile(), "the bar texture picked in the options")
        T.truthy(SK.DBMSkin.holders[obj.frame], "our border behind it")
        T.truthy(Style.GetShell(SK.DBMSkin.holders[obj.frame]), "in our shell")
        T.eq(bar:GetHeight(), 20, "its height stays DBM's")
    end
    -- Its own repaint (an option changed in DBM) sets its font again, and Daylight UI's comes back.
    DBT.Options.FontSize = 14
    DBT:ApplyStyle()
    T.eq(dbmFont(first, "Name")[1], Style.FontFile(), "ours again after its repaint")
    T.eq(dbmFont(first, "Name")[2], 14 * DUI:Get("general", "fontScale"), "at its new size")
    T.eq(_G[first.frame:GetName() .. "Bar"]:GetStatusBarTexture():GetTexture(), Style.BarFile(), "our texture again")
    -- The player picks another font and the bars follow.
    DUI:Set("general", "font", "fira")
    stub.RunTimers()
    T.eq(dbmFont(second, "Name")[1], Style.FONTS.fira.file, "a font change reaches its bars")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.DBT = nil
end)

T.test("dbm: a bar made in a boss fight with a secret name is dressed without touching its name", function()
    local DBT
    login(function() DBT = fakeDBT() end)
    stub.RunTimers()
    stub.EnterCombat()
    stub.SetRestriction("Encounter", true)
    local obj = DBT:CreateBar(20, "timer123", 136116, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        stub.Secret("Annihilate"), true)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(stub.secretArgErrors, 0, "no secret handed to a call that refuses one")
    T.eq(dbmFont(obj, "Name")[1], DaylightUI.Style.FontFile(), "our font on it")
    stub.SetRestriction("Encounter", false)
    stub.LeaveCombat()
    _G.DBT = nil
end)

T.test("dbm: its switch off leaves its bars as DBM draws them", function()
    local DBT
    login(function()
        DaylightUIDB.modules.Skins = { addonSkins = { dbm = false } }
        DBT = fakeDBT()
    end)
    stub.RunTimers()
    local obj = DBT:CreateBar(30, "Big Slam", 136116)
    T.eq(dbmFont(obj, "Name")[1], "Fonts/FRIZQT__.TTF", "DBM's font")
    T.eq(_G[obj.frame:GetName() .. "Bar"]:GetStatusBarTexture():GetTexture(), DBM_TEXTURE, "DBM's texture")
    T.falsy(stub.skins.DBMSkin.holders[obj.frame], "no border of ours")
    _G.DBT = nil
end)

-- ---------------------------------------------------------------------
-- BigWigs and LittleWigs (BigWigs_Plugins v427.8): pooled LibCandyBar bars, every
-- look change going through the current bar style (tests/bigwigsworld.lua)
-- ---------------------------------------------------------------------

local function bigwigs()
    local BWW = require("bigwigsworld")
    local W
    login(function() W = BWW.Install(stub) end)
    stub.RunTimers()
    BWW.LoadPlugins(stub)
    stub.RunTimers()
    return BWW, W, stub.skins.BigWigsSkin
end

local function bigwigsDone()
    _G.BigWigs, _G.BigWigsAPI = nil, nil
    stub.loadedAddOns.BigWigs, stub.loadedAddOns.BigWigs_Plugins = nil, nil
end

T.test("bigwigs: its timer bars in the player's font, bar texture and border; its size stays", function()
    local BWW, W, BW = bigwigs()
    local Style = DaylightUI.Style
    local bar = BWW.Start(W, "Big Slam", 136116)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(bar.candyBarLabel.__font[1], Style.FontFile(), "the Appearance font")
    T.eq(bar.candyBarDuration.__font[1], Style.FontFile(), "its time too")
    T.eq(bar.candyBarLabel.__font[3], Style.Outline(), "its outline")
    T.eq(bar.candyBarLabel.__font[2], 10 * DaylightUI:Get("general", "fontScale"), "BigWigs' size, with the font scale")
    T.eq(bar.candyBarBar:GetStatusBarTexture():GetTexture(), Style.BarFile(), "the picked bar texture")
    T.truthy(BW.holders[bar], "our border")
    T.truthy(Style.GetShell(BW.holders[bar]), "in our shell")
    T.eq(bar.height, 16, "its height stays BigWigs'")
    T.truthy(BW.holders[bar]:GetFrameLevel() < bar:GetFrameLevel(), "under the bar, or it would cover the icon")
    -- A setting changed in BigWigs puts its font back, then Daylight UI's again.
    W.db.profile.fontSize = 12
    BWW.Update(W)
    T.eq(bar.candyBarLabel.__font[1], Style.FontFile(), "ours again after its repaint")
    T.eq(bar.candyBarLabel.__font[2], 12 * DaylightUI:Get("general", "fontScale"), "at its new size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bigwigsDone()
end)

T.test("bigwigs: an emphasized bar takes BigWigs' big size before it's marked emphasized", function()
    local BWW, W = bigwigs()
    local bar = BWW.Start(W, "Big Slam", 136116)
    BWW.Emphasize(W, bar)
    T.eq(bar.candyBarLabel.__font[2], 13 * DaylightUI:Get("general", "fontScale"), "the emphasized size")
    BWW.Update(W)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bigwigsDone()
end)

T.test("bigwigs: the right end angled, square when the icon sits there", function()
    local BWW, W = bigwigs()
    local Style = DaylightUI.Style
    local bar = BWW.Start(W, "Big Slam", 136116)
    T.eq((Style.GetFillAngle(bar.candyBarBar)), "right", "angled on the bar's free end")
    bar:Set("LCBiconPosition", "RIGHT")
    W.Style().BarStopped(bar)
    W.Style().ApplyStyle(bar)
    T.falsy(Style.GetFillAngle(bar.candyBarBar), "an icon on that end: square")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bigwigsDone()
end)

T.test("bigwigs: a stopped bar leaves nothing of ours on it for the pool or another style", function()
    local BWW, W, BW = bigwigs()
    local Style = DaylightUI.Style
    local bar = BWW.Start(W, "Big Slam", 136116)
    BWW.Stop(W, bar)
    T.falsy(BW.holders[bar]:IsShown(), "our border gone")
    T.falsy(Style.GetFillAngle(bar.candyBarBar), "the fill square again")
    local again = BWW.Start(W, "Fire Wave", 136116)
    T.eq(again, bar, "the pool hands the same bar back")
    T.truthy(BW.holders[bar]:IsShown(), "dressed again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bigwigsDone()
end)

T.test("bigwigs: a style picked in BigWigs stays that style's", function()
    local BWW, W, BW = bigwigs()
    local bar = BWW.Start(W, "Big Slam", 136116)
    BWW.PickStyle(W, "Other")
    T.falsy(BW.holders[bar]:IsShown(), "ours off the running bar")
    local fresh = BWW.Start(W, "Fire Wave", 136116)
    T.falsy(BW.holders[fresh], "a new bar never dressed")
    T.eq(fresh.candyBarLabel.__font[1], BWW.FONT, "BigWigs' font")
    T.eq(W.db.profile.barStyle, "Other", "its setting untouched")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bigwigsDone()
end)

T.test("bigwigs: nothing goes into BigWigs' settings", function()
    local BWW, W = bigwigs()
    BWW.Start(W, "Big Slam", 136116)
    T.eq(W.db.profile.barStyle, "Default", "its style setting stays")
    T.eq(W.db.profile.fontSize, 10, "its font size")
    bigwigsDone()
end)

T.test("bigwigs: a bar made in a boss fight with a secret name and icon is dressed without touching them", function()
    local BWW, W, BW = bigwigs()
    stub.EnterCombat()
    stub.SetRestriction("Encounter", true)
    local bar = BWW.Start(W, stub.Secret("Annihilate"), stub.Secret(136116))
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(stub.secretArgErrors, 0, "no secret handed to a call that refuses one")
    T.truthy(BW.holders[bar], "our border on it")
    T.eq(bar.candyBarLabel.__font[1], DaylightUI.Style.FontFile(), "our font on it")
    stub.SetRestriction("Encounter", false)
    stub.LeaveCombat()
    bigwigsDone()
end)

T.test("bigwigs: the skin waits for BigWigs' plugins, which load on demand", function()
    local BWW = require("bigwigsworld")
    local W
    login(function() W = BWW.Install(stub) end)
    stub.RunTimers()
    T.falsy(rawget(stub.skins.BigWigsSkin, "broken"), "nothing to do yet")
    local before = BWW.Start(W, "Pull", 136116)
    T.falsy(stub.skins.BigWigsSkin.holders[before], "no plugins, no hook yet")
    BWW.LoadPlugins(stub)
    stub.RunTimers()
    T.truthy(BWW.Start(W, "Big Slam", 136116), "a bar")
    local bar = BWW.Start(W, "Fire Wave", 136116)
    T.truthy(stub.skins.BigWigsSkin.holders[bar], "dressed once they're in")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bigwigsDone()
end)

T.test("bigwigs: its switch off leaves its bars as BigWigs draws them", function()
    local BWW = require("bigwigsworld")
    local W
    login(function()
        DaylightUIDB.modules.Skins = { addonSkins = { bigwigs = false } }
        W = BWW.Install(stub)
    end)
    stub.RunTimers()
    BWW.LoadPlugins(stub)
    stub.RunTimers()
    local bar = BWW.Start(W, "Big Slam", 136116)
    T.eq(bar.candyBarLabel.__font[1], BWW.FONT, "BigWigs' font")
    T.eq(bar.candyBarBar:GetStatusBarTexture():GetTexture(), BWW.TEXTURE, "BigWigs' texture")
    T.falsy(stub.skins.BigWigsSkin.holders[bar], "no border of ours")
    bigwigsDone()
end)

T.test("bigwigs: a skin that breaks is named once and leaves the bars as they are", function()
    local BWW, W, BW = bigwigs()
    local Dress = BW.Dress
    local bar = BWW.Start(W, "Big Slam", 136116)
    bar.candyBarIconFrame.SetWidth = function() error("changed in a new version") end
    W.Style().ApplyStyle(bar)
    T.eq(#stub.errors, 0, "no error reaches the player")
    T.eq(BW.Dress, Dress, "the skin's still there")
    local fresh = BWW.Start(W, "Fire Wave", 136116)
    T.falsy(BW.holders[fresh], "and stops")
    bigwigsDone()
end)

-- ---------------------------------------------------------------------
-- Attune (Attune.lua, 16001-34): its window, with each chain drawn like the talent
-- trees (tests/attuneworld.lua)
-- ---------------------------------------------------------------------

T.test("attune: its window ours, each step a talent tile, its lines the talents' arrows", function()
    local AW = require("attuneworld")
    login(function() AW.Install() end)
    stub.RunTimers()
    local DUI, Style = DaylightUI, DaylightUI.Style
    local SK, TL, A = stub.skins, DaylightUI.Book.Talents, DaylightUI.Book.Arrows
    _G.Attune_Frame()
    _G.Attune_Select("KARA")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(SK.Kit.ShellOf(_G.AttuneBronzeChrome), "its bronze border: our window")
    local function ring(id) return SK.Attune.tiles[_G["Attune_Node_" .. id]].ring:GetVertexColor() end
    T.eq(_G.Attune_Node_1.Center:GetAlpha(), 0, "its backdrop out of sight")
    T.eq((ring("1")), TL.FULL[1], "a done step: the gold ring")
    T.eq((ring("3")), (Style.Accent()), "the next step: the accent")
    T.eq((ring("4")), TL.LOCKED[1], "a locked step: dark")
    T.truthy(_G.Attune_Icon_4:GetNormalTexture():IsDesaturated(), "its icon grayed while locked")
    T.eq(_G.Attune_Title_1.__font[1], Style.FontFile(Style.WINDOW_SLOT), "our font on its words")
    T.falsy(_G.Attune_Type_1:GetText():find("ffd100", 1, true), "its yellow gone from the type line")
    T.falsy(_G.Attune_Type_1:GetText():find("808080", 1, true), "its gray too")
    local line = _G.Attune_Line3_2_1
    T.eq(line.__color[1], TL.FULL[1], "a line out of a done step: gold")
    T.eq(line:GetThickness(), A.WIDTH, "the arrows' width")
    T.eq(_G.Attune_Line3_4_3.__color[1], A.OFF[1], "a line not lit yet: the arrows' dark")
    T.truthy(SK.Attune.tiles[_G.Attune_Node_2].head:IsShown(), "a chevron where a line comes in")
    T.falsy(SK.Attune.tiles[_G.Attune_Node_1].head:IsShown(), "none on the first step")
    -- The next step done: drawn again, its ring flashes like a talent filling.
    AW.states["3"] = "done"
    _G.Attune_Select("KARA")
    T.eq((ring("3")), TL.FULL[1], "gold once done")
    T.truthy(SK.Attune.tiles[_G.Attune_Node_3].flash:IsShown(), "the flash of a ring closing")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    AW.Remove()
end)

T.test("attune: once its skin broke, a style change leaves its steps alone", function()
    local AW = require("attuneworld")
    login(function() AW.Install() end)
    stub.RunTimers()
    local SK = stub.skins
    _G.Attune_Frame()
    _G.Attune_Select("KARA")
    T.truthy(next(SK.Attune.tiles), "its steps dressed")
    SK.Engine.Broke(SK.Attune.def, "a newer Attune")
    local dressed = 0
    local real = SK.Attune.Dress
    SK.Attune.Dress = function(...) dressed = dressed + 1; return real(...) end
    DaylightUI.Fire("StyleChanged")
    SK.Attune.Dress = real
    T.eq(dressed, 0, "the broken skin stops whole")
    AW.Remove()
end)

-- OPie (UI/RingView.lua, 8.10.2). Other looks come in through
-- OPie.UI:RegisterIndicatorConstructor, which makes one button and checks every
-- method its rings call, and that the flag methods take a secret false.
local OPIE_METHODS = { "SetPoint", "SetScale", "GetScale", "SetShown", "SetParent", "SetIcon", "SetIconTexCoord",
    "SetIconAtlas", "SetIconVertexColor", "SetDominantColor", "SetOverlayIcon", "SetOverlayIconVertexColor",
    "SetUsable", "SetCount", "SetBinding", "SetCooldown", "SetShortLabel",
    "SetCooldownDuration", "SetEquipState", "SetHighlighted", "SetActive", "SetOuterGlow", "SetQualityOverlay" }
-- Runs the motion kit's tweens to their end (the ring's tint glides).
local function settleMotion()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end
local function fakeOPie()
    stub.installedAddOns.OPie, stub.loadedAddOns.OPie = true, true
    local O = { looks = {} }
    O.UI = { RegisterIndicatorConstructor = function(_, key, info)
        local b = info.CreateIndicator(nil, UIParent, 48)
        for _, m in ipairs(OPIE_METHODS) do
            if type(b[m]) ~= "function" then return false, "missing " .. m end
        end
        if info.supportsCooldownNumbers and type(b.SetCooldownTextShown) ~= "function" then
            return false, "missing SetCooldownTextShown"
        end
        for _, m in ipairs({ "SetActive", "SetHighlighted", "SetOuterGlow" }) do
            if not pcall(b[m], b, stub.Secret(false)) then return false, m .. " refused a secret" end
        end
        O.looks[key] = info
        return true
    end }
    _G.OPie = O
    return O
end

T.test("opie: with the action bars off, its ring buttons wear their default look", function()
    local O
    login(function() O = fakeOPie() end)
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local info = O.looks.daylight
    T.truthy(info, "registered with OPie")
    T.eq(info.apiLevel, 5, "the level that takes secrets")
    T.falsy(DaylightUI.ActionButtonLook, "no action bars here")
    local b = info.CreateIndicator(nil, UIParent, 48)
    local d = b.dui
    T.truthy(DaylightUI.Style.BorderPx(b) > 0, "a border round it")
    b:SetIcon(136116, 1)
    b:SetUsable(false, false, false, false, true)
    settleMotion()
    T.eq(d.icon:GetAlpha(), 0.4, "out of range: faded, as the action bars")
    b:SetUsable(true, true)
    settleMotion()
    T.eq(d.icon:GetAlpha(), 1, "usable again")
    b:SetHighlighted(true)
    T.eq(d.wash:GetAlpha(), 0.12, "the slice you'd pick: the mouseover wash")
    b:SetHighlighted(false)
    T.eq(d.wash:GetAlpha(), 0, "and back")
    b:SetOuterGlow(stub.Secret(true))
    b:SetActive(stub.Secret(true))
    b:SetCount(stub.Secret(3))
    b:SetCount(nil)
    T.eq(d.count:GetText(), "", "no count")
    local dur, got = stub.Duration(5), nil
    function d.cd:SetCooldownFromDurationObject(x) got = x end
    b:SetCooldownDuration(dur, false)
    T.eq(got, dur, "a fight's cooldown: the client's duration")
    b:SetEquipState(false, true)
    T.truthy(d.mark:IsShown(), "worn: marked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.OPie = nil
end)

T.test("opie: its ring buttons follow the player's action bar look, live", function()
    local O
    stub.Load({ skins = true, actionbars = true, before = function()
        _G.DaylightUIDB = { modules = { NPC = { enabled = false }, Professions = { enabled = false }, Social = { enabled = false } } }
        O = fakeOPie()
    end })
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local DUI = DaylightUI
    T.truthy(DUI.ActionButtonLook, "the action bars share their look")
    local b = O.looks.daylight.CreateIndicator(nil, UIParent, 48)
    local d = b.dui
    b:Show()
    b:SetIcon(136116, 1)
    b:SetBinding("SHIFT-4")
    T.eq(d.L, DUI.ActionButtonLook.Look(), "every bar's look")
    -- The player changes the action bars' look and the ring follows.
    DUI:Set("ActionBars", "look.range", "color")
    DUI:Set("ActionBars", "look.border", 5)
    DUI:Set("ActionBars", "look.keybindSize", 14)
    DUI:Set("ActionBars", "look.shortKeys", true)
    stub.RunTimers()
    T.eq(d.L.range, "color", "the new look read")
    b:SetUsable(false, false, false, false, true)
    settleMotion()
    T.eq(d.icon:GetAlpha(), 1, "range by color: not faded")
    local rc = d.L.rangeColor
    T.eq((d.icon:GetVertexColor()), rc[1], "out of range in the look's range color")
    T.eq(DUI.Style.BorderPx(b), 5, "the look's border")
    T.eq(d.key.__font[2], 14 * DUI:Get("general", "fontScale"), "the look's keybind size")
    T.falsy(d.key:GetText():find("SHIFT", 1, true), "short keybinds")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.OPie = nil
end)

local function opieWithBars()
    local O
    stub.Load({ skins = true, actionbars = true, before = function()
        _G.DaylightUIDB = { modules = { NPC = { enabled = false }, Professions = { enabled = false }, Social = { enabled = false } } }
        O = fakeOPie()
    end })
    stub.RunTimers()
    local b = O.looks.daylight.CreateIndicator(nil, UIParent, 48)
    b:Show()
    b:SetIcon(136116, 1)
    return b, b.dui
end

-- OPie's usable is false on any cooldown too, the global one included (usable and
-- inRange and cdUsable in ActionBook Handlers.lua). Its third argument
-- (onCooldown) says so out of a fight. In a fight its cooldowns come as duration
-- objects and onCooldown stays false.
T.test("opie: only a really unusable spell is grayed, never one on a cooldown", function()
    local b, d = opieWithBars()
    -- The global cooldown out of a fight: OPie says not usable, on cooldown.
    b:SetUsable(false, false, true, false, false)
    b:SetCooldown(1.2, 1.5, false)
    settleMotion()
    T.eq((d.icon:GetVertexColor()), 1, "the global cooldown: no unusable gray")
    -- In a fight: not usable, onCooldown false, the cooldown a duration object.
    b:SetUsable(false, false, false, false, false)
    b:SetCooldownDuration(stub.Duration(1.5), false)
    settleMotion()
    T.eq((d.icon:GetVertexColor()), 1, "in a fight: no unusable gray on every global cooldown")
    -- Really unusable out of a fight: the action bars' gray.
    b:SetUsable(false, false, false, false, false)
    b:SetCooldown(0, 0, false)
    settleMotion()
    T.truthy((d.icon:GetVertexColor()) < 1, "an unusable spell: grayed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.OPie = nil
end)

T.test("opie: a fight's cooldown leaves no gray or fade from before it, and its sweep clears", function()
    local b, d = opieWithBars()
    DaylightUI:Set("ActionBars", "look.cdGray", true)
    DaylightUI:Set("ActionBars", "look.cdAlpha", 0.5)
    stub.RunTimers()
    -- A real cooldown before the pull: grayed and faded.
    b:SetUsable(false, false, true, false, false)
    b:SetCooldown(20, 30, false)
    settleMotion()
    T.eq(d.icon:GetAlpha(), 0.5, "a real cooldown: the look's opacity")
    T.eq(d.icon:GetDesaturation(), 1, "and its gray")
    -- The pull: OPie only hands duration objects now, whose length can't be read.
    b:SetCooldownDuration(stub.Duration(18), false)
    settleMotion()
    T.eq(d.icon:GetAlpha(), 1, "in a fight: no fade left from before it")
    T.eq(d.icon:GetDesaturation(), 0, "nor gray")
    -- Nothing on cooldown any more: the duration sweep goes.
    local cleared = 0
    function d.cd:Clear() cleared = cleared + 1 end
    b:SetCooldown(0, 0, false)
    T.eq(cleared, 1, "the fight's sweep cleared")
    b:SetCooldown(0, 0, false)
    T.eq(cleared, 1, "once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.OPie = nil
end)

T.test("opie: its switch off leaves OPie's own buttons", function()
    local O
    login(function()
        DaylightUIDB.modules.Skins = { addonSkins = { opie = false } }
        O = fakeOPie()
    end)
    stub.RunTimers()
    T.falsy(O.looks.daylight, "nothing registered")
    _G.OPie = nil
end)

-- ---------------------------------------------------------------------
-- PrettyTooltip (v1.3.8): its panels over the hidden tooltip (tests/prettyworld.lua),
-- found by their shape and drawn over on every render
-- ---------------------------------------------------------------------

local function pretty(before)
    local PW = require("prettyworld")
    local posts = {}
    login(function()
        PW.Install(stub)
        Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2, UnitAura = 7 }
        _G.TooltipDataProcessor = { AllTypes = "ALL", AddTooltipPostCall = function(kind, fn)
            posts[kind] = posts[kind] or {}
            table.insert(posts[kind], fn)
        end }
        if before then before() end
    end)
    stub.RunTimers()
    local function fill(tip, kind)
        for _, fn in ipairs(posts.ALL or {}) do fn(tip, { type = kind }) end
        stub.RunTimers()
    end
    return PW, fill, stub.skins.PrettySkin
end

local function prettyDone()
    require("prettyworld").Uninstall(stub)
    _G.TooltipDataProcessor = nil
end

T.test("prettytooltip: its panel wears our shell, its own frame art out of sight, its words and icon kept", function()
    local PW, fill, PS = pretty()
    local tip = CreateFrame("GameTooltip", "PrettyTestTip", UIParent)
    local panel = PW.NewPanel()
    PW.Render(panel, { 0.6, 0.2, 0.9 })
    fill(tip, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local s = PS.Shell(panel)
    T.truthy(s, "found by its shape, with no name or global")
    local function gone()
        for _, key in ipairs({ "halo", "background", "glow", "header" }) do
            T.falsy(panel[key]:IsShown(), key .. " out of sight")
        end
        for i = 1, 4 do
            T.falsy(panel.edges[i]:IsShown(), "edge out of sight")
            T.falsy(panel.shades[i]:IsShown(), "shade out of sight")
        end
    end
    gone()
    PW.Render(panel, { 0.6, 0.2, 0.9 })
    gone()          -- in game its gold band and edges came back over the shell
    T.truthy(panel.icon:IsShown(), "its icon stays")
    T.eq(s:GetFrameLevel(), panel:GetFrameLevel() - 1, "under its words")
    prettyDone()
end)

T.test("prettytooltip: a panel made after the first fill is found too", function()
    local PW, fill, PS = pretty()
    local tip = CreateFrame("GameTooltip", "PrettyTestTipLate", UIParent)
    fill(tip, 7777)       -- a kind it doesn't draw, so no panel yet
    local panel = PW.NewPanel()
    PW.Render(panel, { 1, 1, 1 })
    fill(tip, 0)
    T.truthy(PS.Shell(panel), "dressed at the first kind it draws")
    prettyDone()
end)

T.test("prettytooltip: the border follows its accent on every render; a plain one keeps the normal border", function()
    local PW, fill, PS = pretty()
    local tip = CreateFrame("GameTooltip", "PrettyTestTip2", UIParent)
    local panel = PW.NewPanel()
    PW.Render(panel, { 0.6, 0.2, 0.9 })
    fill(tip, 0)
    local s = PS.Shell(panel)
    T.near(s.opts.borderColor[1], 0.6, 0.001, "its quality color")
    PW.Render(panel, { 0.2, 0.8, 0.3 })
    T.near(s.opts.borderColor[2], 0.8, 0.001, "a new item, painted with no help")
    PW.Render(panel, { 1, 1, 1 })
    T.isnil(s.opts.borderColor, "white or gray: our normal border")
    PW.Render(panel, { 1, 0.4, 0.1 }, { 0.3, 0.8, 1 })
    T.truthy(s.opts.borderPair, "a dual school sweeps its two ends")
    T.near(s.opts.borderPair[2][3], 1, 0.001, "its right end")
    PW.Render(panel, { 1, 0.4, 0.1 })
    T.isnil(s.opts.borderPair, "one color again: no sweep")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    prettyDone()
end)

T.test("prettytooltip: pieces it makes later are dressed as they come: the game's border, the X, the Equipped tab", function()
    local PW, fill, PS = pretty()
    local tip = CreateFrame("GameTooltip", "PrettyTestTip3", UIParent)
    local panel = PW.NewPanel()
    PW.Render(panel, { 1, 1, 1 })
    fill(tip, 0)
    PW.Render(panel, { 1, 1, 1 }, nil, { native = true, close = true, tag = true })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(panel.nativeBorder:IsShown(), "the game's border out of sight")
    T.falsy(panel.close.lines[1]:IsShown(), "its hand-drawn X gives way to ours")
    T.falsy(panel.equipped.border:IsShown(), "the tab's art out of sight")
    T.truthy(PS.Shell(panel.equipped), "the tab wears a shell")
    prettyDone()
end)

T.test("prettytooltip: a panel fades in, is there at once in a fight, and a redraw never fades it again", function()
    local PW, fill, PS = pretty()
    local tip = CreateFrame("GameTooltip", "PrettyTestTip4", UIParent)
    local panel = PW.NewPanel()
    PW.Render(panel, { 1, 1, 1 })
    fill(tip, 0)
    panel:Hide()
    stub.Advance(1)
    panel:Show()
    T.eq(panel:GetAlpha(), 0, "starts from nothing")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1)
    T.eq(panel:GetAlpha(), 1, "and arrives")
    PW.Render(panel, { 1, 1, 1 })
    T.eq(panel:GetAlpha(), 1, "a redraw of a shown panel doesn't fade")
    panel:Hide()
    panel:Show()
    T.eq(panel:GetAlpha(), 1, "hidden and shown in one frame (a refill) never left the screen")
    panel:Hide()
    stub.Advance(1)
    stub.combat = true
    panel:Show()
    T.eq(panel:GetAlpha(), 1, "fight info never waits")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    prettyDone()
end)

T.test("prettytooltip: its switch off leaves its panels its own", function()
    local PW, fill, PS = pretty(function()
        DaylightUIDB.modules.Skins = { addonSkins = { prettytooltip = false } }
    end)
    local tip = CreateFrame("GameTooltip", "PrettyTestTip5", UIParent)
    local panel = PW.NewPanel()
    PW.Render(panel, { 1, 1, 1 })
    fill(tip, 0)
    T.isnil(PS.Shell(panel), "not dressed")
    T.truthy(panel.halo:IsShown(), "its art stays")
    prettyDone()
end)

T.test("prettytooltip: a panel changed by an update is named once and left, with no error", function()
    local PW, fill, PS = pretty()
    local tip = CreateFrame("GameTooltip", "PrettyTestTip6", UIParent)
    local panel = PW.NewPanel()
    PW.Render(panel, { 1, 1, 1 })
    fill(tip, 0)
    panel.edges[3] = nil     -- renamed in an update
    panel:SetHeight(130)
    panel:SetHeight(140)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    prettyDone()
end)

-- ---------------------------------------------------------------------
-- Bagnon (12.1.9, BagBrother core/api/skinning.lua and Bagnon src/frame.lua). A skin
-- is { id, template, load, layout, font, fontH }, registered with
-- Bagnon.Skins:Register. Each window's look comes from its profile's `skin`, read
-- through Bagnon's defaults (metatables).
-- ---------------------------------------------------------------------

local function fakeBagnon()
    stub.installedAddOns.Bagnon, stub.loadedAddOns.Bagnon = true, true
    local frameDefaults = { skin = "Bagnon" }
    frameDefaults.__index = frameDefaults
    local defaults = {}
    for _, id in ipairs({ "inventory", "bank" }) do
        local d = setmetatable({}, frameDefaults)
        d.__index = d
        defaults[id] = d
    end
    local B = { Settings = { ProfileDefaults = defaults }, Skins = { Registry = {} } }
    function B.Skins:Register(skin) self.Registry[skin.id] = skin end
    B.Skins:Register({ id = "Bagnon", template = "NineSliceCodeTemplate" })
    -- Its item class: the border colored by what the item is.
    local Item = {}
    function Item:UpdateBorder()
        if self.color then
            self.IconBorder:SetVertexColor(self.color[1], self.color[2], self.color[3])
            self.IconBorder:Show()
        else
            self.IconBorder:Hide()
        end
    end
    B.Item = Item
    -- A window as Frame:New makes it. own holds the player's own (raw) values.
    function B.Window(id, own)
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(400, 300)
        f.id = id
        f.profile = setmetatable(own or {}, defaults[id])
        f.CloseButton = CreateFrame("Button", nil, f)
        f.SearchBar = CreateFrame("EditBox", nil, f)
        f.Title = CreateFrame("Button", nil, f)
        local sort = CreateFrame("CheckButton", nil, f)
        sort.Icon = sort:CreateTexture()
        f.MenuButtons = { sort }
        return f
    end
    -- Frame:UpdateVisuals: the profile's skin (else the default) on a frame of its
    -- own, then the title's fonts, then the layout.
    function B.Visuals(f)
        local skin = B.Skins.Registry[f.profile.skin] or B.Skins.Registry.Bagnon
        skin.frames = skin.frames or {}
        local bg = skin.frames[f] or CreateFrame("Frame", nil, f, skin.template)
        skin.frames[f], bg.skin, f.skin = bg, skin, bg
        bg:SetAllPoints(f)
        if skin.load then skin.load(bg) end
        B.titleFont = skin.font
        if skin.layout then skin.layout(bg) end
    end
    function B.NewItem(f, color)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(37, 37)
        b.icon = b:CreateTexture()
        b.IconBorder = b:CreateTexture()
        b.IconGlow = b:CreateTexture()
        b.frame, b.color = f, color
        b.UpdateBorder = function(self) return B.Item.UpdateBorder(self) end
        b:UpdateBorder()
        return b
    end
    _G.Bagnon = B
    return B
end

local function bagnonDone()
    _G.Bagnon = nil
    stub.loadedAddOns.Bagnon, stub.installedAddOns.Bagnon = nil, nil
end

T.test("bagnon: its windows wear the Daylight UI look, picked in its own skin list", function()
    local B
    login(function() B = fakeBagnon() end)
    stub.RunTimers()
    local Kit = stub.skins.Kit
    local ours = B.Skins.Registry.DaylightUI
    T.truthy(ours, "ours in Bagnon's skin list")
    T.eq(ours.title, "Daylight UI", "named for its list")
    local f = B.Window("inventory")
    T.eq(f.profile.skin, "DaylightUI", "ours for a window whose look was never picked")
    B.Visuals(f)
    T.truthy(Kit.ShellOf(f.skin), "our shell behind it")
    T.truthy(Kit.InputOf(f.SearchBar), "its search box in our text box look")
    T.truthy(Kit.ShellOf(f.MenuButtons[1]), "its top buttons ours")
    T.truthy(B.titleFont and B.titleFont == _G.DaylightUIBagnonTitle, "our title font")
    local epic = B.NewItem(f, { 0.64, 0.21, 0.93 })
    local empty = B.NewItem(f, nil)
    local s = Kit.ShellOf(epic)
    T.truthy(s, "an item slot outlined")
    T.eq(s.opts.borderColor[1], 0.64, "in the color Bagnon gave it")
    T.eq(Kit.ShellOf(empty).opts.borderColor, Kit.EMPTY_ITEM_BORDER, "an empty one dim")
    T.eq(epic.IconBorder:GetAlpha(), 0, "its own border out of sight")
    -- Bagnon recolors it (a quest picked up), and the skin follows.
    epic.color = { 1, 0.82, 0.2 }
    epic:UpdateBorder()
    T.eq(Kit.ShellOf(epic).opts.borderColor[1], 1, "the new color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bagnonDone()
end)

T.test("bagnon: a look the player picked in Bagnon stays theirs", function()
    local B
    login(function() B = fakeBagnon() end)
    stub.RunTimers()
    local f = B.Window("bank", { skin = "Bagnon" })
    T.eq(f.profile.skin, "Bagnon", "their pick kept")
    B.Visuals(f)
    T.falsy(stub.skins.Kit.ShellOf(f.skin), "no shell of ours")
    local item = B.NewItem(f, { 0, 0.44, 0.87 })
    T.falsy(stub.skins.Kit.ShellOf(item), "its slots left as Bagnon draws them")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    bagnonDone()
end)

T.test("bagnon: its switch off leaves Bagnon's own list and default", function()
    local B
    login(function()
        DaylightUIDB.modules.Skins = { addonSkins = { bagnon = false } }
        B = fakeBagnon()
    end)
    stub.RunTimers()
    T.falsy(B.Skins.Registry.DaylightUI, "nothing added to its list")
    T.eq(B.Window("inventory").profile.skin, "Bagnon", "its own default")
    bagnonDone()
end)

-- ---------------------------------------------------------------------
-- Baganator (834, API/Main.lua and Skins/*.lua). Every piece it makes goes through
-- Baganator.Skins.AddFrame to the current skin, then to each listener.
-- GetCurrentSkin says which look is picked.
-- ---------------------------------------------------------------------

local function fakeBaganator(look)
    stub.installedAddOns.Baganator, stub.loadedAddOns.Baganator = true, true
    local all, listeners = {}, {}
    local G = { look = look or "blizzard" }
    G.API = { Skins = {
        GetCurrentSkin = function() return G.look end,
        GetAllFrames = function() return all end,
        RegisterListener = function(fn) listeners[#listeners + 1] = fn end,
    } }
    G.Skins = { AddFrame = function(kind, region, tags)
        local d = { regionType = kind, region = region, tags = tags }
        all[#all + 1] = d
        for _, fn in ipairs(listeners) do fn(d) end
    end }
    -- A window (ButtonFrameTemplate) with a slot and a search box.
    function G.Window()
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(400, 300)
        f.Bg = f:CreateTexture()
        f.CloseButton = CreateFrame("Button", nil, f)
        G.Skins.AddFrame("ButtonFrame", f, { "backpack" })
        local search = CreateFrame("EditBox", nil, f)
        G.Skins.AddFrame("SearchBox", search)
        local item = CreateFrame("Button", nil, f)
        item:SetSize(37, 37)
        item.icon = item:CreateTexture()
        item.IconBorder = item:CreateTexture()
        item.SlotBackground = item:CreateTexture()
        G.Skins.AddFrame("ItemButton", item)
        return f, search, item
    end
    _G.Baganator = G
    return G
end

local function baganatorDone()
    _G.Baganator = nil
    stub.loadedAddOns.Baganator, stub.installedAddOns.Baganator = nil, nil
end

T.test("baganator: its windows, slots and search box wear the Daylight UI look", function()
    local G, early
    login(function()
        G = fakeBaganator()
        early = G.Window()   -- made before the skin started
    end)
    stub.RunTimers()
    local Kit = stub.skins.Kit
    T.truthy(Kit.ShellOf(early), "a window made before ours came, dressed as it starts")
    local f, search, item = G.Window()
    T.truthy(Kit.ShellOf(f), "a window in our shell")
    T.truthy(Kit.InputOf(search), "its search box ours")
    T.truthy(Kit.ShellOf(item), "a slot outlined")
    T.eq(item.SlotBackground:GetAlpha(), 0, "its slot art gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    baganatorDone()
end)

T.test("baganator: a look the player picked in Baganator stays theirs", function()
    local G
    login(function() G = fakeBaganator("dark") end)
    stub.RunTimers()
    local f, _, item = G.Window()
    local Kit = stub.skins.Kit
    T.falsy(Kit.ShellOf(f), "its window left to its Dark look")
    T.falsy(Kit.ShellOf(item), "its slots too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    baganatorDone()
end)

T.test("baganator: its switch off leaves it as it draws itself", function()
    local G
    login(function()
        DaylightUIDB.modules.Skins = { addonSkins = { baganator = false } }
        G = fakeBaganator()
    end)
    stub.RunTimers()
    local f = G.Window()
    T.falsy(stub.skins.Kit.ShellOf(f), "no shell of ours")
    baganatorDone()
end)
