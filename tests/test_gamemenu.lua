local stub = require("stub")

T.test("no GameMenuFrame yet: nothing errors", function()
    T.noerror(function() stub.Load() end)
end)

T.test("a menu with its own button list: ours joins it, right above AddOns", function()
    local DUI = stub.Load({ login = false })
    _G.ADDONS = "AddOns"
    local menu = CreateFrame("Frame", "GameMenuFrame", UIParent)
    local active, dirty = {}, false
    menu.buttonPool = { EnumerateActive = function() local i = 0 return function() i = i + 1 return active[i] end end }
    function menu:AddButton(text, fn)
        local b = CreateFrame("Button", nil, self)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        b.layoutIndex = #active + 1
        active[#active + 1] = b
        return b
    end
    function menu:MarkDirty() dirty = true end
    function menu:InitButtons()
        active = {}
        self:AddButton("Options"); self:AddButton("AddOns"); self:AddButton("Macros")
        active[2].topPadding = 20
    end
    -- The game's scripts (GameMenuFrame.lua): OnShow and OnEvent build the list.
    menu:Hide()
    menu:SetScript("OnShow", function(self) self:InitButtons() end)
    menu:SetScript("OnEvent", function(self) self:InitButtons() end)
    local init = menu.InitButtons
    stub.FireEvent("PLAYER_LOGIN")
    T.eq(menu.InitButtons, init, "no hook on the menu's InitButtons")
    menu:Show()
    T.eq(#active, 4, "ours added once")
    local ours = active[4]
    T.truthy(ours:GetText():find("|cff1e90ffD|r", 1, true), "in the title's gradient")
    T.eq(ours.layoutIndex, 1.5, "between Options and AddOns")
    T.eq(ours.topPadding, 20, "it takes the section's gap")
    T.isnil(active[2].topPadding, "AddOns doesn't keep it")
    T.truthy(dirty, "the menu lays itself out again")
    T.falsy(_G.DaylightUIGameMenuButton, "no free-standing button")
    menu:GetScript("OnEvent")(menu, "STORE_STATUS_CHANGED")   -- the game builds it again while open
    T.eq(#active, 4, "ours back in, once")
    active[4]:Click()
    T.falsy(menu:IsShown(), "a click closes the menu")
    T.truthy(DUI.OptionsPanel.IsShown(), "and opens our options")
end)

-- The menu as the game builds it (MainMenuFrameTemplates.lua AddButton): a
-- disabled button keeps its motion scripts and shows why on hover.
local function gameMenu()
    _G.ADDONS = "AddOns"
    local menu = CreateFrame("Frame", "GameMenuFrame", UIParent)
    local active = {}
    menu.buttonPool = { EnumerateActive = function() local i = 0 return function() i = i + 1 return active[i] end end }
    function menu:AddButton(text, fn, isDisabled, disabledText)
        local b = CreateFrame("Button", nil, self)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        b:SetEnabled(not isDisabled)
        b.disabledText = isDisabled and disabledText or nil
        b.layoutIndex = #active + 1
        active[#active + 1] = b
        return b
    end
    function menu:MarkDirty() end
    function menu:InitButtons()
        active = {}
        self:AddButton("Options"); self:AddButton("AddOns"); self:AddButton("Macros")
        active[2].topPadding = 20
    end
    menu:Hide()
    menu:SetScript("OnShow", function(self) self:InitButtons() end)
    menu:SetScript("OnEvent", function(self) self:InitButtons() end)
    return menu, function() return active end
end

local function plain(text) return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function cdmButton(active)
    for _, b in ipairs(active()) do
        if plain(b:GetText()) == "DUI Cooldown Manager" then return b end
    end
end

-- The game's settings window (CooldownViewerSettings.lua): ShowUIPanel opens it.
local function fakeSettings()
    local s = CreateFrame("Frame", "CooldownViewerSettings", UIParent)
    s:Hide()
    function s:ShowUIPanel() self:Show() end
    return s
end

T.test("a Cooldown Manager button sits under Daylight UI's and opens the game's settings when nothing of ours takes it", function()
    local DUI = stub.Load({ login = false })
    local menu, active = gameMenu()
    local settings = fakeSettings()
    stub.FireEvent("PLAYER_LOGIN")
    menu:Show()
    local b = cdmButton(active)
    T.truthy(b, "the button is there, named DUI Cooldown Manager")
    T.truthy(b:GetText():find("|cff1e90ffD|r", 1, true), "it starts in the title's blue")
    T.truthy(b:GetText():find("|cffff9a1fr|r", 1, true), "and ends in its orange")
    T.eq(#active(), 5, "both of ours added once")
    T.eq(b.layoutIndex, 1.75, "right under Daylight UI's, above AddOns")
    T.isnil(b.topPadding, "no gap of its own")
    T.truthy(b:IsEnabled(), "usable")
    menu:GetScript("OnEvent")(menu, "STORE_STATUS_CHANGED")
    T.eq(#active(), 5, "rebuilt once")
    cdmButton(active):Click()
    T.falsy(menu:IsShown(), "a click closes the menu")
    T.truthy(settings:IsShown(), "and opens the game's Cooldown Manager settings")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the Cooldown Manager button opens Daylight UI's layout when it takes it", function()
    local DUI = stub.Load({ login = false })
    local menu, active = gameMenu()
    local settings = fakeSettings()
    local opened = 0
    DUI.OpenCooldownManager = function() opened = opened + 1; return true end
    stub.FireEvent("PLAYER_LOGIN")
    menu:Show()
    cdmButton(active):Click()
    T.eq(opened, 1, "Daylight UI's opener ran")
    T.falsy(settings:IsShown(), "the game's window stays shut")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("the Cooldown Manager button is grayed out with the game's reason when it isn't available", function()
    local DUI = stub.Load({ login = false })
    local menu, active = gameMenu()
    fakeSettings()
    _G.C_CooldownViewer = _G.C_CooldownViewer or {}
    local old = _G.C_CooldownViewer.IsCooldownViewerAvailable
    _G.C_CooldownViewer.IsCooldownViewerAvailable = function() return false, "Not yet" end
    stub.FireEvent("PLAYER_LOGIN")
    menu:Show()
    local b = cdmButton(active)
    T.falsy(b:IsEnabled(), "grayed out")
    T.eq(b.disabledText, "Not yet", "with the game's reason")
    _G.C_CooldownViewer.IsCooldownViewerAvailable = old
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("no Cooldown Manager at all: no button", function()
    stub.Load({ login = false })
    local menu, active = gameMenu()
    _G.CooldownViewerSettings = nil
    stub.FireEvent("PLAYER_LOGIN")
    menu:Show()
    T.isnil(cdmButton(active), "nothing to open")
    T.eq(#active(), 4, "Daylight UI's alone")
end)
