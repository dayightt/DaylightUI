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
