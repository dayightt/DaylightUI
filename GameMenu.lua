-- Adds a "DaylightUI" entry to the Escape menu that opens the options, and a
-- Cooldown Manager entry under it. Both go through the menu's own AddButton list,
-- so they match the other buttons even unskinned. The Skins module dresses the whole menu when it's on.
--
-- No protected calls: GameMenuFrame and its buttons aren't secure, and this
-- only reacts to the menu's OnShow without replacing the game's script. The
-- buttons hide the menu before opening anything, like the game's own do.

local _, DUI = ...
local L = DUI.L

-- The addon title's blue-to-orange gradient.
local LABEL = "|cff1e90ffD|r|cff4083f5a|r|cff6276e8y|r|cff8569d8l|r|cffa65dc3i|r"
    .. "|cffc556a3g|r|cffdc5881h|r|cffed685et|r|cfff8813cU|r|cffff9a1fI|r"

-- The Cooldown Manager button does what /cdm does: Daylight UI's layout editor
-- when its Cooldown Manager is on (the Action Bars module sets
-- DUI.OpenCooldownManager and returns true when it took the click), otherwise the
-- game's own settings window, opened the way the game's /cdm opens it.
local function openCooldowns()
    local open = DUI.OpenCooldownManager
    if type(open) == "function" and open() then return end
    local settings = _G.CooldownViewerSettings
    if type(settings) == "table" and type(settings.ShowUIPanel) == "function" then settings:ShowUIPanel(false) end
end

local function closeMenu()
    if type(HideUIPanel) == "function" then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
end

-- Grayed out with the game's own reason when the client says the Cooldown Manager
-- isn't available yet, as its Edit Mode does.
local function cooldownsAvailable()
    local C = _G.C_CooldownViewer
    if type(C) ~= "table" or type(C.IsCooldownViewerAvailable) ~= "function" then return true end
    local ok, why = C.IsCooldownViewerAvailable()
    if ok == false then return false, why end
    return true
end

local function hasCooldowns()
    return type(DUI.OpenCooldownManager) == "function" or type(_G.CooldownViewerSettings) == "table"
end

-- The menu builds its buttons from a list (InitButtons/AddButton) with gaps
-- between sections. Daylight UI's goes right above AddOns, taking the gap above it so
-- it heads that section, and the menu lays itself out to fit.
local function addToMenu(menu)
    local b = menu:AddButton(LABEL, function()
        closeMenu()
        DUI.OptionsPanel.Show()
    end)
    local cd
    if hasCooldowns() then
        local ok, why = cooldownsAvailable()
        cd = menu:AddButton(L["Cooldown Manager"], function()
            closeMenu()
            openCooldowns()
        end, not ok, why)
    end
    if type(b) ~= "table" or type(menu.buttonPool) ~= "table" then return end
    for other in menu.buttonPool:EnumerateActive() do
        if other ~= b and other ~= cd and other:GetText() == ADDONS and type(other.layoutIndex) == "number" then
            b.layoutIndex = other.layoutIndex - 0.5
            b.topPadding, other.topPadding = other.topPadding, nil
            if type(cd) == "table" then cd.layoutIndex, cd.topPadding = other.layoutIndex - 0.25, nil end
        end
    end
    if menu.MarkDirty then menu:MarkDirty() end
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    if type(GameMenuFrame) ~= "table" then return end
    if type(rawget(GameMenuFrame, "AddButton")) ~= "function" then return end
    -- The game rebuilds the list (InitButtons) only from the menu's OnShow and
    -- OnEvent, so re-add the button after each without hooking the menu's methods.
    local function after(menu) DUI.SafeCall(addToMenu, menu) end
    GameMenuFrame:HookScript("OnShow", after)
    GameMenuFrame:HookScript("OnEvent", after)
end)
