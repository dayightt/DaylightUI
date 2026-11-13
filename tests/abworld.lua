-- The fake game world shared by the action bar and installer tests: the
-- game's bars and buttons, and just enough of Edit Mode to save layouts.
-- world() builds it (use it as stub.Load's "before") and returns the table
-- standing for the game's saved layouts, which C_EditMode reads and writes.
local stub = require("stub")

local M = {}
local saved

function M.world()
    Enum.EditModeSystem = { ActionBar = 0, VehicleLeaveButton = 9 }
    Enum.EditModeActionBarSystemIndices = { MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4 }
    Enum.EditModeActionBarSetting = { Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4, VisibleSetting = 5, HideBarArt = 6, HideBarScrolling = 7 }
    Enum.ActionBarVisibleSetting = { Always = 0 }
    Enum.ActionBarOrientation = { Horizontal = 0 }
    Enum.EditModeLayoutType = { Preset = 0, Account = 1 }
    Enum.EditModePresetLayouts = { Modern = 0, Classic = 1 }
    _G.CopyTable = function(t)
        local c = {}
        for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
        return c
    end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.GetTime = function() return stub.now or 0 end
    -- Like the client, nothing at all (not nil) when the cursor is empty.
    _G.GetCursorInfo = function() if stub.cursor then return stub.cursor end end
    C_Timer.NewTicker = function(_, fn) return { Cancel = function() end, fn = fn } end
    -- Slots 2 and 3 have actions; the rest are empty.
    stub.noMana = {}
    _G.HasAction = function(slot) return slot == 2 or slot == 3 end
    _G.IsUsableAction = function(slot) return not stub.noMana[slot], stub.noMana[slot] == true end
    -- The game's proc alert: a frame of its own on the button, plus the glow
    -- events. The addon reads the alert and nothing hooks the manager.
    _G.ActionButtonSpellAlertManager = {
        ShowAlert = function(_, b)
            b.SpellActivationAlert = rawget(b, "SpellActivationAlert") or CreateFrame("Frame", nil, b)
            b.SpellActivationAlert:Show()
            stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1)
            stub.RunTimers()
        end,
        HideAlert = function(_, b)
            if rawget(b, "SpellActivationAlert") then b.SpellActivationAlert:Hide() end
            stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 1)
            stub.RunTimers()
        end,
    }
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which) stub.popup = which end
    local function preset(i)
        local systems = {}
        for idx = 1, 4 do systems[idx] = { system = 0, systemIndex = idx, settings = {}, anchorInfo = {} } end
        return { layoutIndex = i, layoutType = 0, layoutName = "p" .. i, systems = systems }
    end
    -- As in the game (EditModePresetLayoutsManager.lua): the presets are built
    -- once at load, and GetCopyOfPresetLayouts deep-copies them on every call.
    local PLM = { presetLayoutInfo = { preset(0), preset(1) } }
    PLM.GetCopyOfPresetLayouts = function() return CopyTable(PLM.presetLayoutInfo) end
    _G.EditModePresetLayoutManager = PLM
    -- A reload carries the game's layouts over (M.carry), else none yet.
    saved = M.carry or { layouts = {}, activeLayout = 1 }
    M.carry = nil
    _G.C_EditMode = {
        GetLayouts = function() return { layouts = CopyTable(saved.layouts), activeLayout = saved.activeLayout } end,
        -- The game always passes its presets first (UpdateLayoutInfo in
        -- EditModeManager.lua builds the list that way, and activeLayout counts them).
        SaveLayouts = function(info)
            for i = 1, #EditModePresetLayoutManager.GetCopyOfPresetLayouts() do
                local l = info.layouts[i]
                if not (type(l) == "table" and l.layoutType == 0) then error("bad argument: presets must come first") end
            end
            saved.layouts = {}
            for _, l in ipairs(info.layouts) do if l.layoutType ~= 0 then saved.layouts[#saved.layouts + 1] = l end end
            saved.info = info
        end,
        SetActiveLayout = function(i) saved.activeLayout = i end,
        OnLayoutAdded = function(i, activate) saved.added = i; if activate then saved.activeLayout = i end end,
    }
    -- The small bars, and the totem timers under the game's player frame.
    for _, spec in ipairs({ { "StanceBar", "StanceButton", 10 }, { "PetActionBar", "PetActionButton", 10 } }) do
        local bar = CreateFrame("Frame", spec[1], UIParent)
        for i = 1, spec[3] do
            local b = CreateFrame("Button", spec[2] .. i, bar)
            b:SetSize(30, 30)
            b.icon = b:CreateTexture()
            b:SetID(i)
            for _, k in ipairs({ "Normal", "Highlight", "Pushed", "Checked" }) do
                local tex = b:CreateTexture()
                b["Get" .. k .. "Texture"] = function() return tex end
            end
            function b:SetButtonState() end
        end
    end
    _G.GetPetActionInfo = function(i) if i == 1 then return "Attack" end end
    local tf = CreateFrame("Frame", "TotemFrame", PlayerFrame)
    tf.spacing = -6     -- TotemFrame.xml's KeyValue (a HorizontalLayoutFrame)
    function tf:Layout() self.dirty = false end
    local totem = CreateFrame("Button", nil, tf)
    totem:SetSize(37, 37)
    totem.Icon = CreateFrame("Frame", nil, totem)
    totem.Icon.Texture = totem.Icon:CreateTexture()
    totem.Border = totem:CreateTexture()
    totem.Duration = totem:CreateFontString()
    totem.slot = 1
    function tf:Update() end
    -- TotemFrameMixin:OnEvent: every event updates the timers.
    tf:SetScript("OnEvent", function(self) self:Update() end)
    -- The game's managed-frame system: as it shows, it goes back under the game's
    -- player frame (ManagedFrameMixin:OnShow -> AddManagedFrame).
    tf:SetScript("OnShow", function(self)
        if self.ignoreFramePositionManager then return end
        self:ClearAllPoints()
        self:SetParent(PlayerFrame)
    end)
    -- The classic totem bar: the game puts it wherever it likes and moves it back
    -- after its layout events, and Totems.lua puts it back after them.
    local mc = CreateFrame("Frame", "MultiCastActionBarFrame", UIParent)
    mc:SetSize(200, 40)
    mc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- The game's count of totem slots with spells (MultiCastActionBarFrame_Update).
    -- At 0 the bar stays hidden outside Edit Mode. HasMultiCastActionBar works as
    -- in MultiCastActionBarFrame.lua.
    mc.numActiveSlots = 0
    function _G.HasMultiCastActionBar()
        return MultiCastActionBarFrame.numActiveSlots and MultiCastActionBarFrame.numActiveSlots > 0
    end
    -- The summon button, anchored to the bar as the game's XML has it.
    local summon = CreateFrame("Button", "MultiCastSummonSpellButton", mc)
    summon:SetSize(30, 30)
    summon:SetPoint("BOTTOMLEFT", mc, "BOTTOMLEFT", 3, 3)
    for i = 1, 4 do
        local b = CreateFrame("Button", "MultiCastActionButton" .. i, mc)
        b:SetSize(30, 30)
        b.icon = b:CreateTexture()
        for _, k in ipairs({ "Normal", "Highlight", "Pushed", "Checked" }) do
            local tex = b:CreateTexture()
            b["Get" .. k .. "Texture"] = function() return tex end
        end
        function b:SetButtonState() end
    end
    -- EventRegistry: callbacks by event, in the order registered.
    local cbs = {}
    _G.EventRegistry = {
        RegisterCallback = function(_, e, fn, owner)
            cbs[e] = cbs[e] or {}
            cbs[e][#cbs[e] + 1] = { fn, owner }
        end,
        UnregisterCallback = function(_, e, owner)
            for i = #(cbs[e] or {}), 1, -1 do if cbs[e][i][2] == owner then table.remove(cbs[e], i) end end
        end,
        TriggerEvent = function(_, e, ...)
            for _, c in ipairs(cbs[e] or {}) do c[1](c[2], ...) end
        end,
    }
    -- The game stacks its bottom bars again whenever one shows or hides (a pet, a
    -- form, a fight's start or end). Each bar still at its Edit Mode default goes
    -- back on the stack, with no event of its own (UpdateBottomActionBarPositions
    -- in EditModeManager.lua, registered in the manager's OnLoad). The totem bar is
    -- one of Camelot's bottom bars. mc.isInDefaultPosition comes from its
    -- systemInfo and is true for the game's presets.
    mc.isInDefaultPosition = true
    EventRegistry:RegisterCallback("EditModeManager.UpdateBottomActionBarPositions", function()
        if mc:IsShown() and mc.isInDefaultPosition then
            mc:ClearAllPoints()
            mc:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", -115, 100)
        end
    end, "EditModeManagerFrame")
    CreateFrame("Frame", "BagsBar", UIParent)
    CreateFrame("Frame", "MicroMenuContainer", UIParent)
    -- The game's pass over its micro buttons (MainMenuBarMicroButtons.lua).
    _G.UpdateMicroButtons = function() end
    _G.EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame")
    EditModeManagerFrame.accountSettings = {}
    EditModeManagerFrame:Hide()
    -- Where the game would put each button: the x of its left edge and the y of
    -- its bottom. Bars 1 and 2 stacked with the grids on either side, filled from
    -- the bottom row (the upside-down case).
    local MULTI_PAGE = { MultiBarBottomLeft = 6, MultiBarBottomRight = 5, MultiBarRight = 3, MultiBarLeft = 4,
                         MultiBar5 = 13, MultiBar6 = 14 }
    local origin = { MainActionBar = { 600, 26 }, MultiBarBottomLeft = { 600, 73 },
                     MultiBarBottomRight = { 200, 26 }, MultiBarRight = { 1300, 26 },
                     MultiBarLeft = { 1400, 26 }, MultiBar5 = { 100, 120 }, MultiBar6 = { 100, 170 } }
    -- MultiBar7 (bar 8) is left out on purpose: a client without it must not error.
    for _, spec in ipairs({ { "MainActionBar", "ActionButton" }, { "MultiBarBottomLeft", "MultiBarBottomLeftButton" },
                            { "MultiBarBottomRight", "MultiBarBottomRightButton" }, { "MultiBarRight", "MultiBarRightButton" },
                            { "MultiBarLeft", "MultiBarLeftButton" }, { "MultiBar5", "MultiBar5Button" },
                            { "MultiBar6", "MultiBar6Button" } }) do
        local bar = CreateFrame("Frame", spec[1], UIParent)
        bar.EndCaps = CreateFrame("Frame", nil, bar)
        -- Bars 2-8's fixed page, as the game's MultiActionBars.xml sets it (an
        -- Attribute its Lua never writes again). Their buttons read it when a key
        -- presses them (CalculateAction, useparent-actionpage).
        if MULTI_PAGE[spec[1]] then bar:SetAttribute("actionpage", MULTI_PAGE[spec[1]]) end
        -- Edit Mode's icon size slider: 50% to 200% in steps of 5. Only bar 1 has
        -- it set up so far; the others borrow it.
        if spec[1] == "MainActionBar" then
            bar.settingDisplayInfoMap = { [3] = { ConvertValue = function(_, v) return (v - 50) / 5 end } }
        end
        bar:SetSize(300, 90)
        function bar:IsMouseOver() return self.__mouse == true end
        for i = 1, 12 do
            local b = CreateFrame("Button", spec[2] .. i, bar)
            b:SetSize(45, 45)
            -- The game's key press code (ActionButtonDown) ends with this mixin call.
            function b:UpdateState() end
            local o, grid = origin[spec[1]], spec[1] == "MultiBarBottomRight" or spec[1] == "MultiBarRight"
            local col, row = (i - 1) % (grid and 6 or 12), grid and math.floor((i - 1) / 6) or 0
            local x, y = o[1] + col * 47, o[2] + row * 47
            function b:GetLeft() return x end
            function b:GetRight() return x + 45 end
            function b:GetBottom() return y end
            function b:GetTop() return y + 45 end
            local tex = {}
            for _, k in ipairs({ "Normal", "Highlight", "Pushed", "Checked" }) do
                tex[k] = b:CreateTexture()
                b["Get" .. k .. "Texture"] = function() return tex[k] end
            end
            b.icon = b:CreateTexture()
            b.action = i
            function b:SetButtonState(s) self.__state = s end
            function b:GetButtonState() return self.__state or "NORMAL" end
            b.SlotArt = b:CreateTexture()
            b.HotKey = b:CreateFontString()
        end
    end
    return saved
end

-- A saved layout by name, and its index as the game counts it (the two presets
-- come first).
function M.layoutNamed(name)
    for i, l in ipairs(C_EditMode.GetLayouts().layouts) do
        if l.layoutName == name then return l, i + 2 end
    end
end

local function textures(b)
    for _, k in ipairs({ "Normal", "Highlight", "Pushed", "Checked" }) do
        local tex = b:CreateTexture()
        b["Get" .. k .. "Texture"] = function() return tex end
    end
end

local GAME_BARS = { { "MainActionBar", "ActionButton" }, { "MultiBarBottomLeft", "MultiBarBottomLeftButton" },
                    { "MultiBarBottomRight", "MultiBarBottomRightButton" }, { "MultiBarRight", "MultiBarRightButton" },
                    { "MultiBarLeft", "MultiBarLeftButton" }, { "MultiBar5", "MultiBar5Button" }, { "MultiBar6", "MultiBar6Button" } }

-- The game as the addon's own bars meet it: world() plus secure mode, the button
-- template, the game's two event frames, the possess bar, the leave-vehicle button
-- and Quick Keybind, with the game's bars and buttons protected.
-- opts.switch: the account switch, true (the default), false, or "unset" (nothing
-- saved). opts.ab: action bar settings to start from. opts.positions: saved spots.
function M.newWorld(opts)
    opts = opts or {}
    local saved = M.world()
    M.lastSaved = saved
    stub.secure = true
    stub.bindings = opts.bindings or {}
    -- The player's class (only a shaman has the totem bar).
    if opts.class then stub.units.player = { name = "Tester", class = opts.class } end
    _G.DaylightUIDB = { modules = { ActionBars = opts.ab or {} }, positions = opts.positions or {} }
    if opts.switch ~= "unset" then DaylightUIDB.newActionBars = opts.switch ~= false end
    ActionBarButtonEventsFrame.frames = { "game1", "game2", "game3" }
    stub.forms = opts.forms or 0
    stub.form = opts.form
    -- opts.formSpells: each form's spell id in the stance bar's order (a druid's
    -- Bear 5487, Aquatic 1066, Cat 768...), else made-up ids.
    stub.formSpells = opts.formSpells
    if stub.formSpells then stub.forms = #stub.formSpells end
    -- The game's: texture, isActive, isCastable, spellID.
    _G.GetShapeshiftFormInfo = function(i)
        if i <= stub.forms then
            return 136000 + i, stub.form == i, true, stub.formSpells and stub.formSpells[i] or 2457 + i
        end
    end
    -- opts.totemSlots: how many totem slots the game's totem bar has filled.
    MultiCastActionBarFrame.numActiveSlots = opts.totemSlots or 0
    -- The simple slot functions of world() are replaced by the slot-aware ones.
    stub.ActionSlots(opts.slots)
    MainActionBar:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    for _, spec in ipairs(GAME_BARS) do
        _G[spec[1]].__protected = true
        for i = 1, 12 do _G[spec[2] .. i].__protected = true end
    end
    for i = 1, 10 do
        _G["StanceButton" .. i].__protected = true
        _G["PetActionButton" .. i].__protected = true
    end
    local possess = CreateFrame("Frame", "PossessActionBar", UIParent)
    for i = 1, 2 do
        local b = CreateFrame("Button", "PossessButton" .. i, possess)
        b:SetSize(30, 30)
        b.icon = b:CreateTexture()
        b:SetID(i)
        b.__protected = true
        textures(b)
    end
    -- The leave-vehicle button: a child of bar 1, shown by the game. Show and Hide
    -- count their calls so a test can tell the addon never made one.
    local leave = CreateFrame("Button", "MainMenuBarVehicleLeaveButton", MainActionBar)
    leave:SetPoint("LEFT", MainActionBar, "RIGHT", 0, 0)
    textures(leave)
    -- Its wooden art comes with its template. A click on a flight swaps its
    -- highlight for the game's check glow and locks it (OnClicked in
    -- VehicleLeaveButton.lua).
    leave:GetNormalTexture():SetTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up")
    leave:GetHighlightTexture():SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    leave:SetScript("OnClick", function(self)
        self:GetHighlightTexture().__color = nil
        self:GetHighlightTexture():SetTexture("Interface\\Buttons\\CheckButtonHilight")
    end)
    -- The game shows it itself (VEHICLE_UPDATE, UPDATE_BONUS_ACTIONBAR, a flight),
    -- and its OnShow puts it at its Edit Mode spot
    -- (EditModeVehicleLeaveButtonSystem_OnShow -> UpdateActionBarLayout).
    -- A test shows it the game's way with leave:__gameShow().
    leave.__gameShow = leave.Show
    leave:SetScript("OnShow", function(self)
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 300, 20)
    end)
    function leave:Show() self.__shows = (self.__shows or 0) + 1; self.__shown = true end
    function leave:Hide() self.__hides = (self.__hides or 0) + 1; self.__shown = false end
    -- It's one of the game's bottom bars (Camelot EditModeUtil.GetBottomActionBars).
    -- When any of them shows or hides, the game stacks every shown one still at its
    -- default spot again (UpdateBottomActionBarPositions), with no event. A test
    -- runs that with leave:__gameStack().
    leave.systemInfo = { isInDefaultPosition = true }
    function leave:__gameStack()
        if not (self:IsShown() and self.systemInfo.isInDefaultPosition) then return end
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", -200, 120)
    end
    local quick = CreateFrame("Frame", "QuickKeybindFrame", UIParent)
    quick:Hide()
    -- The game's ActionBarController (ActionBarController.lua): a page or bonus bar
    -- change (a stance or form swap, in a fight too) runs StanceBar:Update, whose
    -- UpdateShownButtons reads each stance button's "statehidden", and then shows or
    -- hides bars 2-8 (MultiActionBar_Update). An attribute an addon wrote leaves the
    -- rest of that pass tainted, so in a fight the bars' ShowBase is blocked.
    local controller = CreateFrame("Frame", "ActionBarController", UIParent)
    controller:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    controller:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    controller:SetScript("OnEvent", function()
        local tainted = false
        for i = 1, 10 do
            local b = _G["StanceButton" .. i]
            if type(b) == "table" and not issecurevariable(b.__attrs, "statehidden") then tainted = true end
        end
        if tainted and stub.combat then
            stub.errors[#stub.errors + 1] = "ADDON_ACTION_BLOCKED: MultiBarBottomLeft:ShowBase()"
        end
    end)
    return saved
end

return M
