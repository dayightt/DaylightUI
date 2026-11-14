-- Hides the default frames DaylightUI replaces. Their events are silenced and
-- they get parked under a hidden frame once at load. Nothing is destroyed and
-- nothing is hooked. If the game re-parents one later, it gets parked again.

local _, ns = ...
local DUI = DaylightUI

local Blizzard = {}
ns.Blizzard = Blizzard

local hidden = CreateFrame("Frame")
hidden:Hide()
Blizzard.hiddenParent = hidden

local handled = {}
local parked = {}            -- frames parked by Blizzard.Hide, rechecked after events
local watching = false

local CHILD_KEYS = {
    "healthBar", "healthbar", "HealthBar", "manabar", "ManaBar", "castBar", "spellbar",
    "CastingBarFrame", "BuffFrame", "AurasFrame", "DebuffFrame", "totFrame", "PowerBarAlt", "powerBarAlt",
}
local ALT_POWER_BARS = { "AlternatePowerBar", "MonkStaggerBar", "EvokerEbonMightBar", "DemonHunterSoulFragmentsBar" }
local UNIT_FRAMES = { player = "PlayerFrame", target = "TargetFrame", focus = "FocusFrame", pet = "PetFrame" }
local SWING_FRAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

local function resolve(frame)
    if type(frame) == "string" then return _G[frame] end
    return frame
end

local function unregister(child)
    if type(child) == "table" and child.UnregisterAllEvents then child:UnregisterAllEvents() end
end

-- The controller's top bar opens the target menu through the game's own target
-- frame, and the game closes any menu whose owner isn't visible. So with the
-- controller UI on, that frame stays shown inside a see-through frame instead.
local veil = CreateFrame("Frame", nil, UIParent)
veil:SetAlpha(0)
veil:EnableMouse(false)
Blizzard.veil = veil

local function wantVeil(frame)
    return frame == _G.TargetFrame and DUI.Pad ~= nil and DUI.Pad.On()
end

local function quiet(frame)
    if frame:IsMouseEnabled() then frame:EnableMouse(false) end
    local tot = frame.totFrame
    if type(tot) == "table" and tot.EnableMouse and tot:IsMouseEnabled() then tot:EnableMouse(false) end
end

local function park(frame)
    local veiled = wantVeil(frame)
    local home = veiled and veil or hidden
    if frame:GetParent() == home and frame:IsShown() == veiled then
        -- Edit Mode can turn the mouse back on.
        if veiled and not InCombatLockdown() then quiet(frame) end
        return
    end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        C_Timer.After(0.25, function() park(frame) end)
        return
    end
    if frame:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() park(frame) end, "blizzard:park:" .. tostring(frame:GetName()))
        return
    end
    frame:SetParent(home)
    if veiled then
        quiet(frame)
        frame:Show()
    else
        frame:Hide()
    end
end

function Blizzard.Hide(frame)
    frame = resolve(frame)
    if not frame or handled[frame] then return end
    if frame:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() Blizzard.Hide(frame) end, "blizzard:hide:" .. tostring(frame:GetName()))
        return
    end
    handled[frame] = true
    frame:UnregisterAllEvents()
    frame:Hide()
    for _, key in ipairs(CHILD_KEYS) do unregister(frame[key]) end
    local container = frame.HealthBarsContainer
    if type(container) == "table" then unregister(container.healthBar) end
    park(frame)
    parked[#parked + 1] = frame
    Blizzard.WatchParked()
end

-- The game re-parents some frames (Edit Mode, vehicles, group changes), so
-- they get parked again after those events. Don't hook SetParent instead:
-- hooking a game frame's own method taints the game code that calls it.
Blizzard.REPARK_EVENTS = { "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE",
                           "UNIT_EXITED_VEHICLE", "PLAYER_REGEN_ENABLED" }

function Blizzard.Repark()
    for _, frame in ipairs(parked) do park(frame) end
end

function Blizzard.WatchParked()
    if watching then return end
    watching = true
    local function soon() C_Timer.After(0, Blizzard.Repark) end
    for _, e in ipairs(Blizzard.REPARK_EVENTS) do pcall(DUI.RegisterEvent, e, soon) end
    DUI.On("PadChanged", soon)
    local em = EditModeManagerFrame
    if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
end

function Blizzard.HideCastBar(frame)
    frame = resolve(frame)
    if not frame or handled[frame] then return end
    if frame:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() Blizzard.HideCastBar(frame) end, "blizzard:castbar:" .. tostring(frame:GetName()))
        return
    end
    handled[frame] = true
    if frame.SetUnit then pcall(frame.SetUnit, frame, nil) end
    frame:UnregisterAllEvents()
    frame:Hide()
    -- Hide once, with events off first so its own handlers have nothing to do.
    -- If the game shows it again it stays invisible through alpha, and is
    -- never hidden again from here.
    frame:SetAlpha(0)
    frame:HookScript("OnShow", function(self) self:SetAlpha(0) end)
end

function Blizzard.WarnConflicts()
    DUI.WarnIfLoaded("EllesmereUIUnitFrames", "EllesmereUI Unit Frames", DUI.L["frames"])
end

-- Turning a DaylightUI frame off later does not bring Blizzard's back until
-- the next reload.
function Blizzard.Apply(db)
    for unit, name in pairs(UNIT_FRAMES) do
        if db[unit].enabled then
            Blizzard.Hide(name)
            if unit == "player" then
                for _, bar in ipairs(ALT_POWER_BARS) do unregister(_G[bar]) end
            end
        end
    end
    if db.party.enabled then Blizzard.Hide("PartyFrame") end
    if db.raid.enabled then
        Blizzard.Hide("CompactRaidFrameContainer")
        Blizzard.Hide("CompactRaidFrameManager")
    end
    -- The game's arena frame shows enemy flag carriers. It's created on first
    -- use, so Arena.lua asks again when a carrier turns up.
    if db.arena.enabled then Blizzard.Hide("CompactArenaFrame") end
    if db.combo.enabled then Blizzard.HideCastBar("ComboFrame") end
    if db.playerCastbar.enabled then
        Blizzard.HideCastBar("PlayerCastingBarFrame")
        Blizzard.HideCastBar("PetCastingBarFrame")
    end
    -- The game's own swing timers (shown when its option is on).
    if db.swing.enabled and ns.swing then
        for _, name in ipairs(SWING_FRAMES) do Blizzard.HideCastBar(name) end
    end
    Blizzard.WarnConflicts()
end
