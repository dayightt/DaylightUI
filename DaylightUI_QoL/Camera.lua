-- Max camera distance, as a share of the game's normal one (100%). The
-- slider's top end is the highest value the client accepts. Finding it means
-- asking for far too much and reading back what the client kept, so that is
-- only done when the options page opens, never at login: a player who never
-- opens it keeps their game setting untouched.

local _, ns = ...
local DUI = DaylightUI

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
    if type(SetCVar) == "function" then DUI.SafeCall(SetCVar, Camera.CVAR, tostring(v)) end
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

-- Asked once a session, when the options page opens, and never in a fight.
function Camera.Ask()
    if Camera.top or (type(InCombatLockdown) == "function" and InCombatLockdown()) then return end
    Camera.top = Camera.FindTop()
end

function Camera.Top() return Camera.top or Camera.TOP end

-- The slider's top. Asked here too, while the options window is open: search
-- results draw the slider without its page ever opening.
function Camera.SliderTop()
    local panel = DUI.OptionsPanel
    if not Camera.top and panel and panel.IsShown and panel.IsShown() then Camera.Ask() end
    return Camera.Top()
end

-- Before the client was asked there is no known top: the client clamps the
-- value itself, so a saved distance past 200% isn't cut short.
local function zoom()
    local v = mod and mod.db and tonumber(mod.db.cameraZoom) or 1
    v = math.max(ns.CAMERA_SLIDER and ns.CAMERA_SLIDER.min or 0.5, v)
    return Camera.top and math.min(Camera.top, v) or v
end

local function apply(z)
    applied = z
    DUI.AfterCombat(function() set(z * Camera.Base()) end, "qol:camera")
end

-- Only acts when the setting changes (or on login while it isn't 100%), so a
-- player who never touches it keeps their own game setting.
function Camera.Enable(m)
    mod = m
    local z = zoom()
    if z ~= 1 then apply(z) else applied = 1 end
end

function Camera.Refresh(m)
    mod = m
    local z = zoom()
    if z ~= applied then apply(z) end
end
