-- Sizes in physical screen pixels, so borders stay crisp at any UI scale
-- (especially 4K at small scales). `perfect` is one physical pixel in UI
-- units at effective scale 1.

local ADDON_NAME, DUI = ...

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

-- The UI scale. Spots are saved from the screen's center in UI units, and the
-- screen is 768 / scale units tall. If the client changes the scale on its own
-- (a new resolution, another monitor, its settings reset), every frame away
-- from the center slides toward or off the edges. So the scale is saved
-- account-wide and put back whenever the client changes it. The first one
-- saved is the one the game had, so nothing changes size when this starts.

Pixel.SCALE_MIN, Pixel.SCALE_MAX = 0.4, 1.15

local function clampScale(v)
    return math.max(Pixel.SCALE_MIN, math.min(Pixel.SCALE_MAX, v))
end

function Pixel.UIScale()
    local v = DUI.DB.Root().uiScale
    if type(v) == "number" and v == v then return clampScale(v) end
end

-- The scale the game had when Daylight UI first took it over.
function Pixel.GameScale()
    local v = DUI.DB.Root().uiScaleGame
    if type(v) == "number" and v == v then return clampScale(v) end
end

-- Puts the saved scale on UIParent. tell: run the areas' UI_SCALE_CHANGED
-- handlers, which the client doesn't fire for a scale set from code.
local function applyScale(tell)
    local s = Pixel.UIScale()
    if not s or math.abs((UIParent:GetScale() or 1) - s) < 0.0001 then return end
    UIParent:SetScale(s)
    if tell then DUI.RunEvent("UI_SCALE_CHANGED") end
    DUI.NotifyStyleChanged()
end

function Pixel.SetUIScale(v)
    if type(v) ~= "number" or v ~= v then return end
    DUI.DB.Root().uiScale = clampScale(v)
    DUI.AfterCombat(function() applyScale(true) end, "uiscale")
end

DUI.On("RepaintCore", Pixel.Refresh)

DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == ADDON_NAME then applyScale(false) end
end)
-- The client puts its own scale on during login, after ADDON_LOADED.
DUI.RegisterEvent("PLAYER_LOGIN", function()
    DUI.AfterCombat(function() applyScale(true) end, "uiscale")
end)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local root = DUI.DB.Root()
    if root.uiScale == nil then
        root.uiScale = clampScale(UIParent:GetScale() or 1)
        root.uiScaleGame = root.uiScale
    end
    DUI.AfterCombat(function() applyScale(true) end, "uiscale")
end)
-- Handlers of this event registered after this one (every area's) run at the
-- right scale when it is put back at once. In a fight it waits, and the areas
-- are told again once it is back.
DUI.RegisterEvent("UI_SCALE_CHANGED", function()
    if InCombatLockdown() then
        DUI.AfterCombat(function() applyScale(true) end, "uiscale")
    else
        applyScale(false)
    end
    DUI.NotifyStyleChanged()
end)
DUI.RegisterEvent("DISPLAY_SIZE_CHANGED", function() DUI.NotifyStyleChanged() end)
