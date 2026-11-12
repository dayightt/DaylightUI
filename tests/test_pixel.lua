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
