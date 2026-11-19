local stub = require("stub")

local function at(w, h, scale)
    return stub.Load({ before = function() stub.SetScreen(w, h, scale) end })
end

T.test("one pixel at 1080p, UI scale 1", function()
    local DUI = at(1920, 1080, 1)
    T.near(DUI.Pixel.Unit(UIParent), 768 / 1080)
end)

T.test("one pixel on 4K at UI scale 0.64", function()
    local DUI = at(3840, 2160, 0.64)
    T.near(DUI.Pixel.Unit(UIParent), (768 / 2160) / 0.64)
    T.near(DUI.Pixel.Px(UIParent, 4), 4 * (768 / 2160) / 0.64)
end)

T.test("a frame's own scale is included", function()
    local DUI = at(3840, 2160, 0.64)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetScale(1.5)
    T.near(DUI.Pixel.Unit(f), (768 / 2160) / (0.64 * 1.5))
end)

T.test("Snap rounds to whole physical pixels", function()
    local DUI = at(3840, 2160, 0.64)
    local u = DUI.Pixel.Unit(UIParent)
    T.near(DUI.Pixel.Snap(UIParent, 10), 18 * u)
    T.near(DUI.Pixel.Snap(UIParent, 10.3), 19 * u)
    T.near(DUI.Pixel.Snap(UIParent, -10.3), -19 * u)
end)

T.test("a zero screen height keeps the last good value", function()
    local DUI = at(3840, 2160, 1)
    local before = DUI.Pixel.perfect
    stub.physH = 0
    DUI.Pixel.Refresh()
    T.near(DUI.Pixel.perfect, before)
end)

T.test("with no good height ever, assume 1080", function()
    local DUI = stub.Load({ before = function() stub.physH = 0 end })
    T.near(DUI.Pixel.perfect, 768 / 1080)
end)

T.test("a UI scale change triggers a core repaint", function()
    local DUI = at(1920, 1080, 1)
    local repainted = false
    DUI.On("StyleChanged", function() repainted = true end)
    stub.SetScreen(3840, 2160, 0.64)
    stub.FireEvent("UI_SCALE_CHANGED")
    stub.RunTimers()   -- the style repaints on the next frame
    T.truthy(repainted)
    T.near(DUI.Pixel.perfect, 768 / 2160)
end)

-- Daylight UI keeps the UI scale itself. Spots are saved from the screen's
-- center in UI units, so if the client changed the scale on its own the screen
-- would get taller or shorter in those units and bars near the bottom would
-- slide toward or off the edge.

T.test("the UI scale the game had is kept from the first loading screen on", function()
    local DUI = at(2560, 1440, 0.8)
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    T.near(DUI.DB.Root().uiScale, 0.8)
end)

T.test("the client changing the scale on its own is undone", function()
    local DUI = at(2560, 1440, 0.8)
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    stub.SetScreen(2560, 1440, 1)
    stub.FireEvent("UI_SCALE_CHANGED")
    T.near(UIParent:GetScale(), 0.8)
    T.near(UIParent:GetHeight(), 768 / 0.8)
end)

T.test("a new resolution keeps the screen just as tall in UI units", function()
    local DUI = at(2560, 1440, 0.8)
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    stub.SetScreen(1920, 1080, 0.71)
    stub.FireEvent("DISPLAY_SIZE_CHANGED")
    stub.FireEvent("UI_SCALE_CHANGED")
    T.near(UIParent:GetHeight(), 768 / 0.8)
end)

T.test("in a fight the scale waits until the fight ends", function()
    local DUI = at(2560, 1440, 0.8)
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    stub.EnterCombat()
    stub.SetScreen(2560, 1440, 1)
    stub.FireEvent("UI_SCALE_CHANGED")
    T.near(UIParent:GetScale(), 1)
    stub.LeaveCombat()
    T.near(UIParent:GetScale(), 0.8)
end)

T.test("a saved scale is used again at the next login", function()
    local DUI = stub.Load({ before = function()
        stub.SetScreen(2560, 1440, 1)
        _G.DaylightUIDB = { uiScale = 0.7 }
    end })
    T.near(UIParent:GetScale(), 0.7)
end)

T.test("picking a scale sizes the screen and tells every area", function()
    local DUI = at(2560, 1440, 0.8)
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    local told = false
    DUI.RegisterEvent("UI_SCALE_CHANGED", function() told = true end)
    DUI.Pixel.SetUIScale(0.7)
    T.near(DUI.DB.Root().uiScale, 0.7)
    T.near(UIParent:GetHeight(), 768 / 0.7)
    T.truthy(told)
end)

T.test("a picked scale stays between 40% and 115%", function()
    local DUI = at(2560, 1440, 0.8)
    DUI.Pixel.SetUIScale(0.1)
    T.near(UIParent:GetScale(), 0.4)
    DUI.Pixel.SetUIScale(3)
    T.near(UIParent:GetScale(), 1.15)
end)

T.test("a bar near the bottom stays the same distance from it", function()
    local DUI = at(2560, 1440, 0.8)
    stub.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    local bottomBefore = -UIParent:GetHeight() / 2
    stub.SetScreen(2560, 1440, 1)
    stub.FireEvent("UI_SCALE_CHANGED")
    stub.RunTimers()
    T.near(-UIParent:GetHeight() / 2, bottomBefore)
end)

-- Counts UIParent:SetScale calls from here on.
local function countSets()
    local n, set = { 0 }, UIParent.SetScale
    UIParent.SetScale = function(self, s) n[1] = n[1] + 1; return set(self, s) end
    return n
end

local function returning(scale, opts)
    opts = opts or {}
    return stub.Load({ login = opts.login, before = function()
        stub.SetScreen(2560, 1440, 1)
        _G.DaylightUIDB = { uiScale = scale, uiScaleGame = 1 }
        if opts.combat then stub.combat = true end
    end })
end

T.test("a loading screen leaves the scale alone", function()
    returning(0.7)
    UIParent:SetScale(0.9)   -- another addon, which fires no event
    local sets = countSets()
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    stub.RunTimers()
    T.eq(sets[1], 0)
    T.near(UIParent:GetScale(), 0.9)
end)

T.test("a loading screen reads the screen size again", function()
    local DUI = returning(0.7)
    stub.physW, stub.physH = 3840, 2160
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.near(DUI.Pixel.perfect, 768 / 2160)
end)

T.test("the client's scale during the login waits for the login to be put back", function()
    returning(0.7, { login = false })
    T.near(UIParent:GetScale(), 0.7)
    stub.SetScreen(2560, 1440, 1)
    stub.FireEvent("UI_SCALE_CHANGED")
    T.near(UIParent:GetScale(), 1)
    stub.FireEvent("PLAYER_LOGIN")
    T.near(UIParent:GetScale(), 0.7)
end)

T.test("a new screen size is read at once, in a fight too", function()
    local DUI = returning(0.7)
    stub.EnterCombat()
    stub.physW, stub.physH = 3840, 2160
    stub.FireEvent("DISPLAY_SIZE_CHANGED")
    T.near(DUI.Pixel.perfect, 768 / 2160)
    stub.LeaveCombat()
end)

T.test("a reload in a fight sets the scale once the fight ends", function()
    returning(0.7, { combat = true })
    T.near(UIParent:GetScale(), 1)
    stub.LeaveCombat()
    T.near(UIParent:GetScale(), 0.7)
end)

T.test("the client putting a scale on is always answered with the saved one", function()
    returning(0.7)
    local sets = countSets()
    stub.FireEvent("UI_SCALE_CHANGED")
    T.eq(sets[1], 1)
    T.near(UIParent:GetScale(), 0.7)
end)
