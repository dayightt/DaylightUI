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

-- The game's frames can answer IsMouseEnabled with a secret (seen on its group
-- buttons when a group forms), so the mouse is turned off without asking first.
local function quiet(frame)
    frame:EnableMouse(false)
    local tot = frame.totFrame
    if type(tot) == "table" and tot.EnableMouse then tot:EnableMouse(false) end
end

-- The controller's directional party targeting (party targeting turned off in
-- the game's controller settings, and always in a raid) walks the game's own
-- group frames: it hands CompactPartyFrame (inside PartyFrame) or
-- CompactRaidFrameContainer to the game's navigation, which only stops on
-- buttons it can see, and clicks the one the D-pad lands on. So with the
-- controller UI on, those two keep their events and stay visible inside the
-- see-through frame. They are only re-parented, never shown or hidden from
-- here: their OnShow refreshes the game's controller footer, and run from addon
-- code that would taint its bindings for the rest of the session. The raid
-- manager stays hidden but keeps its events, since it is what shows the party
-- list when a group forms. Decided once per session, at the first hide.
local GROUP_FRAMES = { PartyFrame = true, CompactRaidFrameContainer = true }
local KEEP_EVENTS = { CompactRaidFrameManager = true }
local kept = {}

local function padUI()
    if DUI.Pad and DUI.Pad.On() then return true end
    return DUI.DB ~= nil and DUI.DB.PadUI() == true
end

local function parkKept(frame)
    if frame:GetParent() == veil then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        C_Timer.After(0.25, function() parkKept(frame) end)
        return
    end
    if frame:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() parkKept(frame) end, "blizzard:kept:" .. tostring(frame:GetName()))
        return
    end
    frame:SetParent(veil)
    Blizzard.AimGroup()
end

local function park(frame)
    if kept[frame] then return parkKept(frame) end
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
    local name = frame:GetName()
    local pad = (GROUP_FRAMES[name] or KEEP_EVENTS[name]) and padUI()
    if pad and GROUP_FRAMES[name] then
        kept[frame] = true
        Blizzard.WatchGroup()
    else
        if not pad then
            frame:UnregisterAllEvents()
            for _, key in ipairs(CHILD_KEYS) do unregister(frame[key]) end
            local container = frame.HealthBarsContainer
            if type(container) == "table" then unregister(container.healthBar) end
        end
        frame:Hide()
    end
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
    for _, e in ipairs(Blizzard.REPARK_EVENTS) do DUI.RegisterEvent(e, soon) end
    DUI.On("PadChanged", soon)
    local em = EditModeManagerFrame
    if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
end

-- The game's unit buttons inside the kept group frames, found each time: the
-- raid container makes its buttons as members join.
local function gameButtons(frame, out)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsObjectType("Button") and type(child:GetAttribute("unit")) == "string" then
            out[#out + 1] = child
        end
        gameButtons(child, out)
    end
    return out
end

local function mouseOff(frame)
    frame:EnableMouse(false)
    for _, child in ipairs({ frame:GetChildren() }) do mouseOff(child) end
end

-- Daylight UI's shown tile for a unit, party or raid.
local function tileFor(unit)
    if not ns.Group then return nil end
    for _, b in ns.Group.Buttons() do
        if b:GetAttribute("unit") == unit and b:IsVisible() then return b end
    end
end

local aimed = setmetatable({}, { __mode = "k" }) -- game button -> the tile its cursor sits on, or false

-- The game's group buttons draw their target box and ready check icon with
-- ignoreParentAlpha (CompactUnitFrameTemplate), so the see-through frame didn't
-- hide them: targeting a member with the D-pad lit an empty box where the game's
-- frame would be. Daylight UI's own tile shows the target outline instead.
local function followVeil(piece)
    if type(piece) == "table" and piece.IsIgnoringParentAlpha and piece:IsIgnoringParentAlpha() then
        piece:SetIgnoreParentAlpha(false)
    end
end

local function seeThrough(b)
    followVeil(b.selectionHighlight)
    local ready = b.readyCheckIcon
    followVeil(ready)
    if type(ready) == "table" then followVeil(ready.Icon) end
end

-- With the game's hover mode for party targeting on, the D-pad only marks a
-- member, and the game draws a box of lines round its button, outside the
-- see-through frame. Its arrow already points at Daylight UI's tile, so the
-- box stays unseen.
local function hideHoverBox()
    local gt = _G.GroupTargeting
    local box = type(gt) == "table" and gt.TargetHighlight
    if type(box) == "table" and box.SetAlpha and box:GetAlpha() ~= 0 then box:SetAlpha(0) end
end

-- The see-through game frames take no clicks, and the game's cursor and its
-- D-pad order follow Daylight UI's tiles: each game button's cursor spot is put
-- on the tile showing the same member, through the game's own setter (the
-- spot is what its navigation measures from). A member Daylight UI doesn't show
-- is skipped. The game refuses these in a fight, so they wait for it to end.
function Blizzard.AimGroup()
    if not next(kept) then return end
    if InCombatLockdown() then
        DUI.AfterCombat(Blizzard.AimGroup, "blizzard:aimgroup")
        return
    end
    local setSpot, ignore, unignore = _G.SmartNavigation_SetCustomCursorAnchorPointForFrame,
        _G.SmartNavigation_MarkFrameIgnored, _G.SmartNavigation_ClearIgnoreStatus
    local canAim = type(setSpot) == "function" and type(ignore) == "function"
        and type(unignore) == "function" and type(CreateAnchor) == "function"
    for frame in pairs(kept) do
        mouseOff(frame)
        for _, b in ipairs(gameButtons(frame, {})) do
            seeThrough(b)
        end
        hideHoverBox()
        if canAim then
            for _, b in ipairs(gameButtons(frame, {})) do
                local tile = tileFor(b:GetAttribute("unit")) or false
                if aimed[b] ~= tile then
                    aimed[b] = tile
                    if tile then
                        setSpot(b, CreateAnchor("RIGHT", tile, "LEFT", 0, 0))
                        unignore(b)
                    else
                        setSpot(b, nil)
                        ignore(b)
                    end
                end
            end
        end
    end
end

local groupWatched = false
function Blizzard.WatchGroup()
    if groupWatched then return end
    groupWatched = true
    local pending = false
    local function soon()
        if pending then return end
        pending = true
        C_Timer.After(0, function()
            pending = false
            Blizzard.AimGroup()
        end)
    end
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_PET" }) do DUI.RegisterEvent(e, soon) end
end

function Blizzard.HideCastBar(frame)
    frame = resolve(frame)
    if not frame or handled[frame] then return end
    if frame:IsProtected() and InCombatLockdown() then
        DUI.AfterCombat(function() Blizzard.HideCastBar(frame) end, "blizzard:castbar:" .. tostring(frame:GetName()))
        return
    end
    handled[frame] = true
    if frame.SetUnit then DUI.SafeCall(frame.SetUnit, frame, nil) end
    frame:UnregisterAllEvents()
    frame:Hide()
    -- Hide once, with events off first so its own handlers have nothing to do.
    -- If the game shows it again it stays invisible through alpha, and is
    -- never hidden again from here.
    frame:SetAlpha(0)
    frame:HookScript("OnShow", function(self) self:SetAlpha(0) end)
end

-- Battleground flag carriers. On this client the game shows them with the old
-- arena frames (ArenaEnemyMatchFrame1-5 in ArenaEnemyFramesContainer, under the
-- minimap), not CompactArenaFrame. Each match frame and its pet frame show
-- themselves, and the container, on their own events, and a shown container
-- is taken back by the right-side frame manager. So their events go quiet too,
-- or the bars come back the moment a carrier is seen.
Blizzard.ARENA_MAX = 5

local function silence(frame)
    if type(frame) ~= "table" then return end
    unregister(frame)
    for _, key in ipairs(CHILD_KEYS) do unregister(frame[key]) end
end

function Blizzard.HideArena()
    Blizzard.Hide("CompactArenaFrame")
    if not _G.ArenaEnemyFramesContainer then return end
    silence(_G.ArenaEnemyMatchFramesContainer)
    silence(_G.ArenaEnemyPrepFramesContainer)
    for i = 1, Blizzard.ARENA_MAX do
        silence(_G["ArenaEnemyMatchFrame" .. i])
        silence(_G["ArenaEnemyMatchFrame" .. i .. "PetFrame"])
        silence(_G["ArenaEnemyPrepFrame" .. i])
    end
    Blizzard.Hide("ArenaEnemyFramesContainer")
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
    -- The game's frames for enemy flag carriers. CompactArenaFrame is created
    -- on first use, so Arena.lua asks again when a carrier turns up.
    if db.arena.enabled then Blizzard.HideArena() end
    if db.combo.enabled then Blizzard.HideCastBar("ComboFrame") end
    if db.playerCastbar.enabled then
        Blizzard.HideCastBar("PlayerCastingBarFrame")
        Blizzard.HideCastBar("PetCastingBarFrame")
        -- The profession window borrows this one in place of the player cast bar
        -- while you craft (when the game's cast bar is locked to the player frame),
        -- so it would be a second bar beside Daylight UI's own.
        Blizzard.HideCastBar("OverlayPlayerCastingBarFrame")
    end
    -- The game's own swing timers (shown when its option is on).
    if db.swing.enabled and ns.swing then
        for _, name in ipairs(SWING_FRAMES) do Blizzard.HideCastBar(name) end
    end
end
