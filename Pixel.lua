-- Sizes in physical screen pixels, so borders stay crisp at any UI scale
-- (especially 4K at small scales). `perfect` is one physical pixel in UI
-- units at effective scale 1.

local _, DUI = ...

local Pixel = {}
DUI.Pixel = Pixel

local physicalHeight

function Pixel.Refresh()
    local _, h = GetPhysicalScreenSize()
    if h and h > 0 then
        physicalHeight = h
    elseif not physicalHeight then
        physicalHeight = 1080
    end
    Pixel.perfect = 768 / physicalHeight
end
Pixel.Refresh()

-- One physical pixel in frame's coordinate space.
function Pixel.Unit(frame)
    local es = (frame or UIParent):GetEffectiveScale()
    if not es or es <= 0 then es = 1 end
    return Pixel.perfect / es
end

function Pixel.Px(frame, n)
    return n * Pixel.Unit(frame)
end

-- Nearest whole physical pixel. The epsilon keeps values sitting exactly on a
-- boundary from flipping between reloads.
function Pixel.Snap(frame, v)
    local u = Pixel.Unit(frame)
    local px = v / u
    if px >= 0 then
        px = math.floor(px + 0.5 + 0.001)
    else
        px = -math.floor(-px + 0.5 + 0.001)
    end
    return px * u
end

DUI.On("RepaintCore", Pixel.Refresh)
DUI.RegisterEvent("UI_SCALE_CHANGED", function() DUI.NotifyStyleChanged() end)
DUI.RegisterEvent("DISPLAY_SIZE_CHANGED", function() DUI.NotifyStyleChanged() end)
