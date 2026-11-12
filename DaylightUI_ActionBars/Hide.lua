-- The game's bag bar and micro menu, hidden or shown (and when shown, optionally
-- faded by the fade engine). Hidden ones are parked under a hidden frame rather than
-- destroyed, so their keybinds (bags, spellbook, map...) keep working, and they go
-- back where they were when shown again. Shown, each gets an unlock-mode handle
-- (Hide.Movers). If never moved it stays where Edit Mode put it, unless its
-- <key>Corner setting (used by the presets' micro menu) starts it in the bottom-right.

local _, ns = ...
local DUI = DaylightUI

local Hide = {}
ns.Hide = Hide

-- Setting -> the game's frames.
Hide.FRAMES = {
    bagBar = { "BagsBar" },
    microMenu = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" },
}

local hidden = CreateFrame("Frame")
hidden:Hide()
Hide.parent = hidden

local home = setmetatable({}, { __mode = "k" })     -- frame -> its parent before it was parked

-- Edit Mode is moving things, so retry once it's closed.
local function later(fn)
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        C_Timer.After(0.25, fn)
        return true
    end
end

local function park(frame)
    if frame:GetParent() == hidden then return end
    if later(function() park(frame) end) then return end
    home[frame] = frame:GetParent()
    frame:SetParent(hidden)
end

local function unpark(frame)
    if frame:GetParent() ~= hidden then return end
    if later(function() unpark(frame) end) then return end
    frame:SetParent(home[frame] or UIParent)
    frame:SetAlpha(1)
end

function Hide.Apply(cfg)
    for key, names in pairs(Hide.FRAMES) do
        local mode = cfg[key] or "hidden"
        for _, name in ipairs(names) do
            local f = _G[name]
            if f then
                if mode == "hidden" then park(f) else unpark(f) end
            end
        end
    end
    Hide.PlaceAll(cfg)
end

-- The frame the fade engine manages for "bagBar" or "microMenu", or nil while it's
-- hidden.
function Hide.FadeFrame(cfg, key)
    if cfg[key] ~= "shown" then return nil end
    return Hide.Frame(key)
end

-- The game's frame for one of them, shown or not.
function Hide.Frame(key)
    for _, name in ipairs(Hide.FRAMES[key]) do
        if _G[name] then return _G[name] end
    end
end

-- ---------------------------------------------------------------------
-- Unlock mode. Each is a following proxy mover, like the totem bar: the handle saves
-- the spot, and the frame is put back there the frame after the game may have placed
-- it (entering the world, Edit Mode layouts, leaving Edit Mode). No hook on its
-- SetPoint (see Totems.lua). A frame that was never moved is never touched. On reset
-- it goes back to the spot the game last gave it this session (if already moved at
-- login, Edit Mode's spot after a /reload).
-- ---------------------------------------------------------------------

Hide.MOVERS = { bagBar = "Bag Bar", microMenu = "Micro Menu" }
Hide.MOVER_ORDER = { "microMenu", "bagBar" }
-- A spec change makes the game apply its layout again too (EditModeManager.lua),
-- without the layouts event. The corner is computed from the screen, so a new screen
-- size moves it too.
Hide.PLACE_EVENTS = { "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED",
                      "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }
Hide.EDGE = 12      -- distance from the screen's edges in the corner, same as the info panel

function Hide.MoverKey(key) return "actionbars." .. key end

local gameSpot = {}     -- key -> { x, y }: where the game had it before we moved it

local function offset(f)
    local cx, cy = f:GetCenter()
    if type(cx) ~= "number" then return nil end
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * r - UIParent:GetWidth() / 2, cy * r - UIParent:GetHeight() / 2
end

-- Where one set to start in the corner goes, as a center offset computed from its
-- real size for any screen and above a data bar. nil if not known yet.
function Hide.Corner(cfg, key)
    if cfg[key .. "Corner"] ~= true then return nil end
    local f = Hide.Frame(key)
    if type(f) ~= "table" then return nil end
    local w, h = f:GetWidth(), f:GetHeight()
    if w <= 1 or h <= 1 then return nil end     -- not laid out yet
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return { UIParent:GetWidth() / 2 - Hide.EDGE - w * r / 2,
             DUI.Movers.Above(Hide.EDGE) + h * r / 2 - UIParent:GetHeight() / 2 }
end

-- Moves one of them to its saved spot, only while shown (parked, its scale isn't
-- UIParent's, so the numbers would be off).
function Hide.Place(cfg, key)
    local f = Hide.FadeFrame(cfg, key)
    if not f or f:GetParent() == hidden then return end
    local saved = DUI.DB.Positions()[Hide.MoverKey(key)] or Hide.Corner(cfg, key)
    if not saved then
        -- Never moved, so it's where the game put it: remember that for a reset.
        local x, y = offset(f)
        if x then gameSpot[key] = { x, y } end
        return
    end
    if f.IsProtected and f:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() Hide.Place(cfg, key) end, "hide:place:" .. key)
        return
    end
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = saved[1] / r, saved[2] / r
    -- Already there, nothing to do (this runs again after each micro button pass).
    local p, rel, rp, px, py = f:GetPoint(1)
    if f:GetNumPoints() == 1 and p == "CENTER" and rel == UIParent and rp == "CENTER" and px == x and py == y then return end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function Hide.PlaceAll(cfg)
    for _, key in ipairs(Hide.MOVER_ORDER) do DUI.SafeCall(Hide.Place, cfg, key) end
end

local queued = false
local function soon()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        if ns.db then Hide.PlaceAll(ns.db) end
    end)
end

function Hide.Movers(cfg)
    for _, key in ipairs(Hide.MOVER_ORDER) do
        local f, mk = Hide.Frame(key), Hide.MoverKey(key)
        if type(f) == "table" and f.SetPoint and not DUI.Movers.Get(mk) then
            DUI.Movers.Register(f, mk, Hide.MOVERS[key], nil, { proxy = true, follow = true,
                minW = 60, minH = 30,
                active = function() return (ns.db or cfg)[key] == "shown" end,
                home = function()
                    local s = Hide.Corner(ns.db or cfg, key) or gameSpot[key]
                    if s then return s[1], s[2] end
                end,
                onMoved = function() DUI.SafeCall(Hide.Place, ns.db or cfg, key) end })
        end
    end
    if Hide.wired then return end
    Hide.wired = true
    for _, event in ipairs(Hide.PLACE_EVENTS) do pcall(DUI.RegisterEvent, event, soon) end
    -- The game puts the micro menu back at its Edit Mode spot when its override
    -- bar goes away (after a death, a vehicle), then runs its pass over the micro
    -- buttons. After that pass it goes back to its spot.
    if type(_G.UpdateMicroButtons) == "function" then hooksecurefunc("UpdateMicroButtons", soon) end
    -- Leaving Edit Mode puts them back at their Edit Mode spots.
    local em = _G.EditModeManagerFrame
    if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
    -- A data bar came or went, so a piece in the corner eases up or down with it.
    DUI.On("BottomRoomChanged", function()
        local db = ns.db
        if not db then return end
        for _, key in ipairs(Hide.MOVER_ORDER) do
            local f = Hide.FadeFrame(db, key)
            if f and not InCombatLockdown() and Hide.Corner(db, key)
               and not DUI.DB.Positions()[Hide.MoverKey(key)] then
                local _, was = offset(f)
                Hide.Place(db, key)
                local _, now = offset(f)
                if was and now and was ~= now then
                    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    DUI.Motion.Glide(f, 0, (was - now) / r, DUI.Motion.SLOW)
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------
-- Size. Edit Mode stores it (a Size slider saved as its step; ranges in the game's
-- EditModeSettingDisplayInfo.lua) and sets the frame's scale from it when it applies
-- the layout: Bags on BagsBar, the micro menu on MicroMenu (not its container). Our
-- slider reads the active layout, writes it there (DUI.EditMode.WriteSetting) and
-- scales the frame right away.
-- ---------------------------------------------------------------------

Hide.SIZE = {
    bagBar = { system = "Bags", setting = "EditModeBagsSetting", frame = "BagsBar", min = 75, max = 200, step = 5 },
    microMenu = { system = "MicroMenu", setting = "EditModeMicroMenuSetting", frame = "MicroMenu", min = 70, max = 200, step = 5 },
}

local function sizeKeys(key)
    local s = Hide.SIZE[key]
    local sys, set = Enum.EditModeSystem, Enum[s.setting]
    return s, sys and sys[s.system], set and set.Size
end

-- The size as a scale (1 = 100%): the active layout's, else the frame's.
function Hide.GetSize(key)
    local s, system, setting = sizeKeys(key)
    local stored = system ~= nil and setting ~= nil and DUI.EditMode.ActiveSetting(system, nil, setting)
    if type(stored) == "number" then return (stored * s.step + s.min) / 100 end
    local f = _G[s.frame]
    return type(f) == "table" and f.GetScale and f:GetScale() or 1
end

function Hide.SetSize(key, scale)
    local s, system, setting = sizeKeys(key)
    local pct = math.max(s.min, math.min(s.max, math.floor(scale * 100 / s.step + 0.5) * s.step))
    local f = _G[s.frame]
    if type(f) == "table" and f.SetScale then
        if f.IsProtected and f:IsProtected() and InCombatLockdown() then
            DUI.AfterCombat(function() Hide.SetSize(key, scale) end, "hide:size:" .. key)
            return
        end
        f:SetScale(pct / 100)
        if ns.db then DUI.SafeCall(Hide.Place, ns.db, key) end
    end
    if system ~= nil and setting ~= nil then
        DUI.EditMode.WriteSetting(system, nil, setting, (pct - s.min) / s.step)
    end
    DUI.Fire("SettingChanged", "ActionBars", key .. "Size", pct / 100)
end
