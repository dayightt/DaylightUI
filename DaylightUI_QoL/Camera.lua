-- Max camera distance, as a share of the game's normal one (100%). The
-- slider's top end is the highest value the client accepts, found at login by
-- asking for far too much and reading back what it kept.

local _, ns = ...

local Camera = {}
ns.Camera = Camera
ns.features[#ns.features + 1] = Camera

Camera.CVAR = "cameraDistanceMaxZoomFactor"
Camera.BASE = 2         -- the game's normal max when the client can't say
Camera.TOP = 2          -- the slider's top (200%) before the client is asked
Camera.ASK = 50         -- far beyond any client's limit

local mod, applied

local function get()
    if type(GetCVar) ~= "function" then return nil end
    local ok, v = pcall(GetCVar, Camera.CVAR)
    return ok and tonumber(v) or nil
end

local function set(v)
    if type(SetCVar) == "function" then pcall(SetCVar, Camera.CVAR, tostring(v)) end
end

-- The game's normal max distance: what 100% means.
function Camera.Base()
    local fn = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if type(fn) ~= "function" then return Camera.BASE end
    local ok, v = pcall(fn, Camera.CVAR)
    v = ok and tonumber(v)
    return (v and v > 0) and v or Camera.BASE
end

-- The client clamps the value it stores, so the read-back is its limit, as a
-- share of the base (rounded down to 5%). The player's own value goes straight back.
function Camera.FindTop()
    local before = get()
    if not before then return Camera.TOP end
    set(Camera.ASK)
    local kept = get()
    set(before)
    if not kept or kept >= Camera.ASK then return Camera.TOP end
    local top = math.floor(kept / Camera.Base() * 20 + 1e-6) / 20
    return top > 1 and top or Camera.TOP
end

function Camera.Top() return Camera.top or Camera.TOP end

local function zoom()
    local v = mod and mod.db and tonumber(mod.db.cameraZoom) or 1
    return math.max(ns.CAMERA_SLIDER and ns.CAMERA_SLIDER.min or 0.5, math.min(Camera.Top(), v))
end

local function apply(z)
    applied = z
    set(z * Camera.Base())
end

-- Only acts when the setting changes (or on login while it isn't 100%), so a
-- player who never touches it keeps their own game setting.
function Camera.Enable(m)
    mod = m
    Camera.top = Camera.FindTop()
    if ns.CAMERA_SLIDER then ns.CAMERA_SLIDER.max = Camera.top end   -- before the window is first built
    local z = zoom()
    if z ~= 1 then apply(z) else applied = 1 end
end

function Camera.Refresh(m)
    mod = m
    local z = zoom()
    if z ~= applied then apply(z) end
end
