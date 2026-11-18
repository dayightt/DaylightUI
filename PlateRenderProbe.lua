-- Opt-in comparison for issue 80. One unskinned solid square changes ONLY
-- parent branch, then strata. No native setter or hook is called. Like the
-- other plate diagnostics, readback labels stay English for investigators.
-- This deliberately bypasses Style/Motion: those are part of what it tests.
local _, DUI = ...
local L = DUI.L
local P = {}
DUI.PlateRenderProbe = P

local SIZE, LEVEL, SECONDS = 18, 100, 90
local frame, texture, ready, run, ticker, pending
local serial, refusals, errors = 0, 0, 0
local cleanupKey = {}
local strataNames = { WORLD = true, BACKGROUND = true, LOW = true, MEDIUM = true,
    HIGH = true, DIALOG = true, FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

local function say(text) DUI.Print(L["platerender: %s"]:format(text)) end
local function call(object, method, ...)
    local args = { ... }
    local count = select("#", ...)
    local ok, supported, value = pcall(function()
        if type(object[method]) ~= "function" then return false end
        return true, object[method](object, unpack(args, 1, count))
    end)
    if not ok then errors = errors + 1; return false end
    if not supported then refusals = refusals + 1; return false end
    return true, value
end

local function read(object, method)
    local ok, value = call(object, method)
    if not ok then return false end
    if DUI.IsSecret(value) then refusals = refusals + 1; return false end
    return true, value
end

local function number(value)
    return not DUI.IsSecret(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

-- A forbidden ancestor can make even an owned child's methods unavailable.
-- Read only; a refusal never licenses a trial mutation of a native frame.
local function accessible(object)
    for _ = 1, 64 do
        if not object then return true end
        local ok, forbidden = read(object, "IsForbidden")
        if not ok then return false end
        if forbidden ~= false then refusals = refusals + 1; return false end
        ok, object = read(object, "GetParent")
        if not ok then return false end
    end
    refusals = refusals + 1
    return false
end

local function plateFor(unit)
    if not C_NamePlate or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        refusals = refusals + 1
        return false
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok then errors = errors + 1; return false end
    if DUI.IsSecret(plate) then refusals = refusals + 1; return false end
    return true, plate
end

local function inView(unit, plate)
    local shownOK, shown = read(plate, "IsShown")
    local visibleOK, visible = read(plate, "IsVisible")
    local manager = C_NamePlateManager
    if not manager or type(manager.IsNamePlateUnitBehindCamera) ~= "function" then
        refusals = refusals + 1; return false
    end
    local ok, behind = pcall(manager.IsNamePlateUnitBehindCamera, unit)
    if not ok then errors = errors + 1; return false end
    if DUI.IsSecret(behind) or type(behind) ~= "boolean" then refusals = refusals + 1; return false end
    if not shownOK or not visibleOK then return false end
    return true, shown == true and visible == true and behind == false
end

local function cleanup()
    if not frame then pending = nil; return true end
    if DUI.Restricted() then return false end
    if not accessible(frame) or not accessible(UIParent) then return false end
    -- Independent attempts: an anchor refusal must not skip returning our own
    -- frame to UIParent. Never mutate the native plate or its UnitFrame.
    local hidden = call(frame, "Hide")
    local cleared = call(frame, "ClearAllPoints")
    local moved = call(frame, "SetParent", UIParent)
    local ok, parent = read(frame, "GetParent")
    local shownOK, shown = read(frame, "IsShown")
    local pointsOK, points = read(frame, "GetNumPoints")
    if hidden and cleared and moved and ok and parent == UIParent
        and shownOK and shown == false and pointsOK and points == 0 then
        pending = nil
        return true
    end
    refusals = refusals + 1
    pending = true
    return false
end

local function stop(reason)
    run = nil
    serial = serial + 1
    if ticker then call(ticker, "Cancel"); ticker = nil end
    pending = frame ~= nil or nil
    if DUI.Restricted() then
        DUI.AfterRestrictions(function()
            if pending and cleanup() then say(L["Cleanup complete; the probe is off."]) end
        end, cleanupKey)
    else
        cleanup()
    end
    say(reason .. " " .. (pending and L["Cleanup pending; retry /dui platerender off after restrictions lift. Reload if access never returns."]
        or L["Probe off."]) .. string.format(" refusals=%d errors=%d", refusals, errors))
end

local function valid()
    if not run then return false end
    if DUI.Restricted() then stop(L["Comparison invalidated by combat or restrictions."]); return false end
    local ok, plate = plateFor(run.unit)
    if not ok or plate ~= run.plate then
        stop(L["Comparison invalidated: the selected plate association changed."])
        return false
    end
    if not accessible(run.plate) or not accessible(frame) then
        stop(L["Comparison invalidated: frame access was refused."])
        return false
    end
    local readable, visible = inView(run.unit, run.plate)
    if not readable or not visible then
        stop(L["Comparison invalidated: the native frame no longer reads visible and in front of the camera."])
        return false
    end
    return true
end

local function state()
    if not frame then return "parent=none strata=? level=? effectiveAlpha=? effectiveScale=?" end
    local ok, parent = read(frame, "GetParent")
    local parentText = ok and ((parent == UIParent and "UIParent")
        or (run and parent == run.plate and "selected-native-plate") or "other") or "?"
    local function numeric(method)
        local got, value = read(frame, method)
        return got and number(value) and string.format("%.3f", value) or "?"
    end
    local function flag(object, method)
        if not object then return "?" end
        local got, value = read(object, method)
        return got and type(value) == "boolean" and tostring(value) or "?"
    end
    local got, strata = read(frame, "GetFrameStrata")
    local strataText = got and type(strata) == "string" and strataNames[strata] and strata or "?"
    return string.format("parent=%s strata=%s level=%s effectiveAlpha=%s effectiveScale=%s shown=%s visible=%s nativeShown=%s nativeVisible=%s",
        parentText, strataText, numeric("GetFrameLevel"), numeric("GetEffectiveAlpha"), numeric("GetEffectiveScale"),
        flag(frame, "IsShown"), flag(frame, "IsVisible"), flag(run and run.plate, "IsShown"), flag(run and run.plate, "IsVisible"))
end

-- Observers must not diagnose the hierarchy changes made by this active probe.
function P.Active() return run ~= nil or pending == true end

function P.Status()
    local label = run and ("phase " .. run.phase .. "/3") or (pending and "off, cleanup pending" or "off")
    -- Gather values before the counts, since a refused read increments them.
    local actual = state()
    say(label .. ": " .. actual .. string.format(" refusals=%d errors=%d", refusals, errors))
end

local function build()
    if ready then return true end
    if not frame then
        local ok, value = pcall(CreateFrame, "Frame", "DaylightUIPlateRenderProbe", UIParent)
        if not ok or not value then errors = errors + 1; return false end
        frame = value -- created safely away from a native plate
    end
    if not call(frame, "Hide") then return false end
    if not texture then
        local created, value = call(frame, "CreateTexture", nil, "OVERLAY")
        if not created or not value then return false end
        texture = value
    end
    ready = call(texture, "SetAllPoints", frame) and call(texture, "SetColorTexture", 1, 0, 1, 1)
    return ready
end

local function anchorMatches(plate)
    local ok, point, relative, relativePoint, x, y = pcall(function() return frame:GetPoint(1) end)
    if not ok then errors = errors + 1; return false end
    for _, value in ipairs({ point, relative, relativePoint, x, y }) do
        if DUI.IsSecret(value) then refusals = refusals + 1; return false end
    end
    return point == "CENTER" and relative == plate and relativePoint == "CENTER"
        and number(x) and x == 0 and number(y) and y == 0
end

local function applyPhase()
    if not valid() then return end
    local parent = run.phase == 1 and run.plate or UIParent
    local strata = run.phase == 3 and "TOOLTIP" or "MEDIUM"
    if not accessible(parent) then stop(L["Comparison refused: parent access unavailable."]); return end
    -- Ignore inheritance so native distance alpha/scale cannot change the
    -- control square. Anchor to the SAME native plate in all three phases.
    local ok
    if run.phase == 1 then
        ok = call(frame, "Hide") and call(frame, "ClearAllPoints")
            and call(frame, "SetParent", parent)
            and call(frame, "SetIgnoreParentAlpha", true) and call(frame, "SetIgnoreParentScale", true)
            and call(frame, "SetSize", SIZE, SIZE) and call(frame, "SetScale", run.scale)
            and call(frame, "SetAlpha", 1) and call(frame, "SetFrameStrata", strata)
            and call(frame, "SetFrameLevel", LEVEL)
            and call(frame, "SetPoint", "CENTER", run.plate, "CENTER", 0, 0)
            and call(frame, "Show")
    elseif run.phase == 2 then
        ok = call(frame, "SetParent", parent)
        if ok then
            local got, level = read(frame, "GetFrameLevel")
            ok = got and number(level)
            -- Some clients reset level on reparenting. Restore just that
            -- comparison invariant; don't reanchor, resize, hide, or show.
            if ok and level ~= LEVEL then ok = call(frame, "SetFrameLevel", LEVEL) end
        end
    else
        ok = call(frame, "SetFrameStrata", strata)
    end
    if not ok then stop(L["Comparison refused: a required frame operation failed or is unsupported."]); return end
    -- A successful setter is not proof the engine accepted the requested
    -- invariants, and neither setters nor getters prove pixels were drawn.
    for _, check in ipairs({ { "GetParent", parent }, { "GetFrameStrata", strata },
        { "GetFrameLevel", LEVEL }, { "GetEffectiveAlpha", 1 }, { "GetEffectiveScale", run.scale },
        { "GetWidth", SIZE }, { "GetHeight", SIZE }, { "GetNumPoints", 1 },
        { "IsShown", true }, { "IsVisible", true } }) do
        local got, actual = read(frame, check[1])
        local expected = check[2]
        local same = got and (type(expected) == "number" and number(actual)
            and math.abs(actual - expected) < 0.00001 or type(expected) ~= "number" and actual == expected)
        if not same then
            refusals = refusals + 1
            stop(L["Comparison invalidated: a requested frame invariant was not readable or did not match."])
            return
        end
    end
    if not anchorMatches(run.plate) then
        refusals = refusals + 1
        stop(L["Comparison invalidated: the common anchor is unreadable or did not match."])
        return
    end
    P.Status()
    say(L["Record whether the magenta square is visibly present (yes/no). Keep the camera and character still."] .. " "
        .. (run.phase < 3 and L["Run /dui platerender for the next phase."] or L["Run /dui platerender off to finish."])
        .. " " .. L["This command does not detect rendered pixels."])
end

function P.Command(rest)
    rest = (rest or ""):lower()
    if rest == "off" then stop(L["Stopped."]); return end
    if rest == "status" then
        if run and not valid() then return end
        P.Status()
        return
    end
    if rest ~= "" then say(L["Use /dui platerender, /dui platerender status, or /dui platerender off."]); return end
    if DUI.Restricted() then
        refusals = refusals + 1
        if run then stop(L["Comparison invalidated by combat or restrictions."])
        else say(L["Refused: leave combat and all addon restrictions before starting."]) end
        return
    end
    if pending and not cleanup() then say(L["Refused: previous cleanup is still pending; use /dui platerender off."]); return end
    if run then
        if not valid() then return end
        if run.phase == 3 then stop(L["Comparison finished."]); return end
        run.phase = run.phase + 1
        applyPhase()
        return
    end
    refusals, errors = 0, 0
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" or type(C_Timer.After) ~= "function" then
        refusals = refusals + 1; stop(L["Refused: required timer APIs are unavailable."]); return
    end
    local targetOK, target = plateFor("target")
    if not targetOK then stop(L["Refused: the nameplate lookup is unavailable."]); return end
    local chosen, unit
    for i = 1, 40 do
        local token = "nameplate" .. i
        local ok, plate = plateFor(token)
        if not ok then stop(L["Refused: the nameplate lookup is unavailable."]); return end
        if plate then
            if not accessible(plate) then stop(L["Refused: frame ancestry is unavailable."]); return end
            local readable, visible = inView(token, plate)
            if not readable then stop(L["Refused: native visibility or camera APIs are unavailable."]); return end
            if visible and (not chosen or plate == target) then chosen, unit = plate, token end
            if chosen and chosen == target then break end
        end
    end
    if not chosen then say(L["Refused: no active native plate reads visible and in front of the camera."]); return end
    if not accessible(chosen) or not accessible(UIParent) then stop(L["Refused: frame ancestry is unavailable."]); return end
    local got, scale = read(UIParent, "GetEffectiveScale")
    if not got or not number(scale) or scale <= 0 then stop(L["Refused: UI scale is unreadable."]); return end
    if not build() then stop(L["Refused: the plain probe could not be built."]); return end
    serial = serial + 1
    local token = serial
    run = { plate = chosen, unit = unit, phase = 1, scale = scale }
    say(L["Selected %s. Target the intended unit before starting; first calibrate with a visibly working plate. This active test changes the frame hierarchy and may disturb the failure. It does not identify a cause. Timeout: %d seconds."]:format(unit, SECONDS))
    applyPhase()
    if not run then return end
    local ok, value = pcall(C_Timer.NewTicker, 0.2, function() if run and serial == token then valid() end end)
    if not ok or not value then errors = errors + 1; stop(L["Refused: the association watcher could not start."]); return end
    ticker = value
    ok = pcall(C_Timer.After, SECONDS, function()
        if run and serial == token then stop(L["Timed out after %d seconds."]:format(SECONDS)) end
    end)
    if not ok then errors = errors + 1; stop(L["Refused: the cleanup timer could not start."]) end
end

DUI.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    if run and (DUI.IsSecret(unit) or unit == run.unit) then stop(L["Comparison invalidated: the selected plate was removed."]) end
end)
local function restrictionsChanged()
    if run and DUI.Restricted() then stop(L["Comparison invalidated by combat or restrictions."])
    elseif pending and not DUI.Restricted() then cleanup() end
end
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", restrictionsChanged)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", restrictionsChanged)
DUI.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", restrictionsChanged)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if run then stop(L["Comparison invalidated by a world transition."]) else restrictionsChanged() end
end)
DUI.RegisterCommand("platerender", P.Command)
