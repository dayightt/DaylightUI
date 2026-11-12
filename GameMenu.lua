-- Adds a "DaylightUI" entry to the Escape menu that opens the options. It is
-- added through the menu's own AddButton list, so it matches the other buttons
-- even unskinned. The Skins module dresses the whole menu when it's on.
--
-- No protected calls: GameMenuFrame and its buttons aren't secure, and this
-- only reacts to the menu's OnShow without replacing the game's script. The
-- button hides the menu before opening the options, like the game's own do.

local _, DUI = ...

-- The addon title's blue-to-orange gradient.
local LABEL = "|cff1e90ffD|r|cff4083f5a|r|cff6276e8y|r|cff8569d8l|r|cffa65dc3i|r"
    .. "|cffc556a3g|r|cffdc5881h|r|cffed685et|r|cfff8813cU|r|cffff9a1fI|r"

-- The menu builds its buttons from a list (InitButtons/AddButton) with gaps
-- between sections. Ours goes right above AddOns, taking the gap above it so
-- it heads that section, and the menu lays itself out to fit.
local function addToMenu(menu)
    local b = menu:AddButton(LABEL, function()
        if type(HideUIPanel) == "function" then HideUIPanel(GameMenuFrame) else GameMenuFrame:Hide() end
        DUI.OptionsPanel.Show()
    end)
    if type(b) ~= "table" or type(menu.buttonPool) ~= "table" then return end
    for other in menu.buttonPool:EnumerateActive() do
        if other ~= b and other:GetText() == ADDONS and type(other.layoutIndex) == "number" then
            b.layoutIndex = other.layoutIndex - 0.5
            b.topPadding, other.topPadding = other.topPadding, nil
        end
    end
    if menu.MarkDirty then menu:MarkDirty() end
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    if type(GameMenuFrame) ~= "table" then return end
    if type(rawget(GameMenuFrame, "AddButton")) ~= "function" then return end
    -- The game rebuilds the list (InitButtons) only from the menu's OnShow and
    -- OnEvent, so re-add ours after each without hooking the menu's methods.
    local function after(menu) DUI.SafeCall(addToMenu, menu) end
    GameMenuFrame:HookScript("OnShow", after)
    GameMenuFrame:HookScript("OnEvent", after)
end)
