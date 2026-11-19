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

-- Puts the saved scale on UIParent. It is set even when it looks the same,
-- since the client may have just put its own on; the areas are told only when
-- it really changed. tell: run the areas' UI_SCALE_CHANGED handlers, which the
-- client doesn't fire for a scale set from code.
local telling = false
local function applyScale(tell)
    local s = Pixel.UIScale()
    if not s then return end
    local changed = math.abs((UIParent:GetScale() or 1) - s) >= 0.0001
    UIParent:SetScale(s)
    if not changed then return end
    if tell then
        telling = true
        DUI.RunEvent("UI_SCALE_CHANGED")
        telling = false
    end
    DUI.NotifyStyleChanged()
end

-- UIParent can't be resized in a fight, a reload in one included.
local function applySoon(tell)
    DUI.AfterCombat(function() applyScale(tell) end, "uiscale")
end

function Pixel.SetUIScale(v)
    if type(v) ~= "number" or v ~= v then return end
    DUI.DB.Root().uiScale = clampScale(v)
    applySoon(true)
end

-- Reads the screen size again; repaints only when a pixel's size changed.
local function rereadScreen()
    local before = Pixel.perfect
    Pixel.Refresh()
    if Pixel.perfect ~= before then DUI.NotifyStyleChanged() end
end

DUI.On("RepaintCore", Pixel.Refresh)

-- Set as early as the saved value exists, then again at login.
local loggedIn = false
DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == ADDON_NAME then applySoon(false) end
end)
-- The client puts its own scale on during login, after ADDON_LOADED, so the
-- login is where the saved one goes back for good. Before it, the client's
-- own changes are left to this.
DUI.RegisterEvent("PLAYER_LOGIN", function()
    loggedIn = true
    applySoon(true)
end)
-- Loading screens don't set the scale (the client tells through
-- UI_SCALE_CHANGED when it changes one); the first one keeps the scale the
-- game had, so nothing changes size when this starts.
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local root = DUI.DB.Root()
    if root.uiScale == nil then
        root.uiScale = clampScale(UIParent:GetScale() or 1)
        root.uiScaleGame = root.uiScale
    end
    rereadScreen()
end)
-- Handlers of this event registered after this one (every area's) run at the
-- right scale when it is put back at once. In a fight it waits, and the areas
-- are told again once it is back.
DUI.RegisterEvent("UI_SCALE_CHANGED", function()
    Pixel.Refresh()
    if loggedIn and not telling then
        if InCombatLockdown() then applySoon(true) else applyScale(false) end
    end
    DUI.NotifyStyleChanged()
end)
DUI.RegisterEvent("DISPLAY_SIZE_CHANGED", function()
    Pixel.Refresh()
    DUI.NotifyStyleChanged()
end)
