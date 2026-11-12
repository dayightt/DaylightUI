-- Loot sparkles: lootable quest objects keep their sparkle. The game only draws
-- it with the outline mode off, and a graphics preset turns the outline back
-- on, so the settings are set again a moment after any graphics change.

local _, ns = ...
local DUI = DaylightUI

local Sparkles = {}
ns.Sparkles = Sparkles
ns.features[#ns.features + 1] = Sparkles

-- The game settings, and the value each needs for the sparkle.
Sparkles.CVARS = {
    outlineModeShowLootEffectWhenDisabled = "1",
    graphicsOutlineMode = "0",
    OutlineEngineMode = "0",
    raidGraphicsOutlineMode = "0",
    RAIDOutlineEngineMode = "0",
}
-- What switching it off puts back when the client can't say its own default.
Sparkles.FALLBACK = { outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2",
    OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2" }
Sparkles.DELAY = 1   -- seconds after a graphics change: a preset sets many settings at once

local watched = {}
for name in pairs(Sparkles.CVARS) do watched[name:lower()] = true end

local mod, applied, pending

local function get(name)
    if type(GetCVar) ~= "function" then return nil end
    local ok, v = pcall(GetCVar, name)
    return ok and v ~= nil and tostring(v) or nil
end

local function set(name, v)
    if type(SetCVar) == "function" and get(name) ~= v then pcall(SetCVar, name, v) end
end

local function default(name)
    local fn = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if type(fn) == "function" then
        local ok, v = pcall(fn, name)
        if ok and v ~= nil then return tostring(v) end
    end
    return Sparkles.FALLBACK[name]
end

local function wanted() return mod and mod.db and mod.db.lootSparkles == true end

-- With `keep`, the player just turned it on, so their old values are saved
-- (ns.KeepCVar) and restored when it's turned off. Nothing saved means the game's default.
local function apply(on, keep)
    applied = on
    if keep then for name in pairs(Sparkles.CVARS) do ns.KeepCVar(name) end end
    DUI.AfterCombat(function()
        if wanted() ~= on then return end   -- switched again while waiting
        for name, v in pairs(Sparkles.CVARS) do
            set(name, on and v or (ns.GiveBackCVar(name) or default(name)))
        end
    end, "qol:sparkles")
end

-- A graphics change (the player's or a preset's): set ours again once it settles.
local function onCVar(_, name)
    if not wanted() or pending or type(name) ~= "string" or not watched[name:lower()] then return end
    pending = true
    C_Timer.After(Sparkles.DELAY, function()
        pending = false
        if wanted() then apply(true) end
    end)
end

-- Only acts when the setting changes (or on login while it is on), so a player
-- who never touches it keeps their own game settings.
function Sparkles.Enable(m)
    mod = m
    DUI.RegisterEvent("CVAR_UPDATE", onCVar)
    if wanted() then apply(true) else applied = false end
end

function Sparkles.Refresh(m)
    mod = m
    local on = wanted()
    if on ~= applied then apply(on, on) end
end
