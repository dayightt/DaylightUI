-- Ctrl + mouse wheel over a game window scales it, like BlizzMove. Covers every
-- window in UIPanelWindows, picked up as addons load. Saved per profile by name
-- (windowScales); /dui reset clears them. Out of combat only, since some of
-- these windows hold secure buttons.
--
-- Apart from MapMove, this is the only place that writes to the game's windows:
-- EnableMouseWheel, a HookScript and SetScale. Nothing of theirs is called or
-- replaced. Reapplied after the game lays out its panels, since
-- UpdateUIPanelPositions may shrink a big one to fit the screen.

local _, ns = ...
local DUI = DaylightUI

local Scale = {}
ns.WindowScale = Scale

Scale.STEP, Scale.MIN, Scale.MAX = 0.05, 0.5, 1.5
-- The world map has its own corner grip.
Scale.SKIP = { WorldMapFrame = true }

local cfg
local hooked = {}   -- [name] = frame

local function scales()
    if not cfg then return nil end
    if type(cfg.windowScales) ~= "table" then cfg.windowScales = {} end
    return cfg.windowScales
end

-- A window's saved scale, or nil if never changed.
function Scale.Of(name)
    local t = scales()
    local v = t and t[name]
    if type(v) ~= "number" or v ~= v then return nil end
    return math.max(Scale.MIN, math.min(Scale.MAX, v))
end

-- Applies the saved scale. Windows never scaled are left alone.
function Scale.Apply(name)
    local f, s = hooked[name], Scale.Of(name)
    if not (f and s) or InCombatLockdown() then return end
    if math.abs((f:GetScale() or 1) - s) > 0.001 then f:SetScale(s) end
end

function Scale.ApplyAll()
    for name in pairs(hooked) do Scale.Apply(name) end
end

-- One Ctrl + wheel notch: a step bigger or smaller, saved.
function Scale.Wheel(name, delta)
    local f = hooked[name]
    if not (f and cfg) or InCombatLockdown() then return end
    local v = (Scale.Of(name) or f:GetScale() or 1) + (delta > 0 and Scale.STEP or -Scale.STEP)
    v = math.floor(math.max(Scale.MIN, math.min(Scale.MAX, v)) / Scale.STEP + 0.5) * Scale.STEP
    scales()[name] = v
    Scale.Apply(name)
end

local function hook(name, f)
    if hooked[name] or Scale.SKIP[name] then return end
    if type(f) ~= "table" or type(f.EnableMouseWheel) ~= "function" or type(f.HookScript) ~= "function" then return end
    hooked[name] = f
    f:EnableMouseWheel(true)
    f:HookScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then Scale.Wheel(name, delta) end
    end)
    f:HookScript("OnShow", function() Scale.Apply(name) end)
    Scale.Apply(name)
end

-- Every listed window that exists so far (more appear as addons load).
function Scale.Scan()
    if InCombatLockdown() then
        DUI.AfterCombat(Scale.Scan, "skins:windowScale")
        return
    end
    local list = _G.UIPanelWindows
    if type(list) ~= "table" then return end
    for name in pairs(list) do
        if type(name) == "string" then hook(name, _G[name]) end
    end
end

local started = false
function Scale.Start(c)
    cfg = c
    if not started then
        started = true
        DUI.RegisterEvent("ADDON_LOADED", function() C_Timer.After(0, Scale.Scan) end)
        if type(_G.UpdateUIPanelPositions) == "function" then
            hooksecurefunc("UpdateUIPanelPositions", Scale.ApplyAll)
        end
        DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Scale.Reset
    end
    Scale.Scan()
    Scale.ApplyAll()
end

-- /dui reset: every window back to the game's scale.
function Scale.Reset()
    local t = scales()
    if not t then return end
    for name in pairs(t) do
        t[name] = nil
        local f = hooked[name]
        if f and not InCombatLockdown() then f:SetScale(1) end
    end
    -- The loot window uses the master scale, so reapply that instead of 1.
    DUI.Movers.ApplyAll()
end
