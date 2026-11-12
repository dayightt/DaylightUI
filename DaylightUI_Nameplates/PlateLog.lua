-- /dui platelog: a recorder for nameplates that stop drawing mid-session. Every
-- plate goes blank with no error and /reload fixes it; even the game's own plate
-- and a texture made directly on it stop drawing, while it still reports shown at
-- alpha 1. It can't be reproduced on demand, so it runs all session for every
-- player and is kept across /reload (DaylightUIDB.plateLog, the newest MAX rows).
--   /dui platelog mark   "the plates are gone now": snapshots every plate into
--                        the log and opens the newest rows in a box to copy
--                        into a bug report.
--   /dui platelog        on or off (on by default), how many rows are kept
--   /dui platelog clear  empties it
-- What it records:
--   every CVar change, screen/UI scale change, loading screen, zone, combat,
--   flight or loss of control, cinematic, NPC dialog (and Daylight UI's NPC
--   scene), AFK, mount, vehicle, death, blocked action;
--   every Daylight UI call that touches the game's plates (plate size, click
--   insets, scales, stacking, range, name-only, instance friends, Refresh, a
--   Sync that changed something, /dui platefix);
--   once a second, only when something differs: plate counts (game and Daylight
--   UI), plates added/removed that second, plate size and insets,
--   UIParent/WorldFrame, plates behind the camera, plates the game says aren't
--   visible, their scales, fps.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local PlateLog = {}
ns.PlateLog = PlateLog

PlateLog.MAX = 1500 -- rows kept (keeps the saved variables file small)
PlateLog.HEARTBEAT = 30 -- s: write a sample row even when nothing changed
PlateLog.REPORT_MAX = 3800 -- copy box text sized to fit one Discord message
local started = GetTime()

function PlateLog.DB()
    local root = _G.DaylightUIDB
    if type(root) ~= "table" then return nil end
    local d = root.plateLog
    if type(d) ~= "table" then
        d = { on = true }
        root.plateLog = d
    end
    if type(d.log) ~= "table" then d.log = {} end
    return d
end

local session
local function r2(v) return type(v) == "number" and math.floor(v * 100 + 0.5) / 100 or v end
local function secret(v) return issecretvalue and issecretvalue(v) end
local function plainv(v)
    if secret(v) then return "secret" end
    if type(v) == "number" then return r2(v) end
    return v
end

function PlateLog.Note(what, extra)
    local d = PlateLog.DB()
    if not (d and d.on) then return end
    local row = {
        s = session, t = math.floor((GetTime() - started) * 10 + 0.5) / 10,
        at = date("%H:%M:%S"), what = what,
    }
    if extra then for k, v in pairs(extra) do row[k] = v end end
    local log = d.log
    log[#log + 1] = row
    local over = #log - PlateLog.MAX
    if over > 0 then
        for i = 1, #log - over do log[i] = log[i + over] end
        for i = #log, #log - over + 1, -1 do log[i] = nil end
    end
end
local note = PlateLog.Note

local function cvar(name)
    local fn = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(fn) ~= "function" then return "?" end
    local ok, v = pcall(fn, name)
    return ok and plainv(v) or "?"
end

local function ask(f, method, ...)
    if type(f) ~= "table" or type(f[method]) ~= "function" then return nil end
    local ok, v = pcall(f[method], f, ...)
    if not ok then return "refused" end
    return plainv(v)
end

local function behindCamera(unit)
    local M = C_NamePlateManager
    if type(unit) ~= "string" or not (M and M.IsNamePlateUnitBehindCamera) then return nil end
    local ok, b = pcall(M.IsNamePlateUnitBehindCamera, unit)
    return ok and plainv(b) or nil
end

local function gamePlates()
    local get = C_NamePlate and C_NamePlate.GetNamePlates
    if not get then return nil end
    local ok, list = pcall(get, issecure and issecure() or false)
    return ok and type(list) == "table" and list or nil
end

-- ---------------------------------------------------------------------
-- Once a second: plate state, written only when it differs
-- ---------------------------------------------------------------------

local added, removed = 0, 0
local lastSig, lastWrite = nil, 0

function PlateLog.Sample()
    local game, invisible, behind, lowAlpha = 0, 0, 0, 0
    local minScale, maxScale
    for _, np in pairs(gamePlates() or {}) do
        game = game + 1
        if ask(np, "IsVisible") ~= true then invisible = invisible + 1 end
        local a = ask(np, "GetEffectiveAlpha")
        if type(a) == "number" and a < 0.99 then lowAlpha = lowAlpha + 1 end
        local sc = ask(np, "GetEffectiveScale")
        if type(sc) == "number" then
            minScale = math.min(minScale or sc, sc)
            maxScale = math.max(maxScale or sc, sc)
        end
        local unit = type(np.GetUnit) == "function" and ask(np, "GetUnit") or nil
        if behindCamera(unit) == true then behind = behind + 1 end
    end
    local M = ns.Manager
    local ours, spare, oursHidden = 0, 0, 0
    if M then
        for _, p in pairs(M.byUnit) do
            ours = ours + 1
            if ask(p, "IsVisible") ~= true and not p.corpse then oursHidden = oursHidden + 1 end
        end
        spare = M.Spares and M.Spares() or 0
    end
    local w, h
    if C_NamePlate and C_NamePlate.GetNamePlateSize then
        local okS, a, b = pcall(C_NamePlate.GetNamePlateSize)
        if okS then w, h = plainv(a), plainv(b) end
    end
    local inset
    local PM, T = C_NamePlateManager, Enum and Enum.NamePlateType
    if PM and PM.GetNamePlateHitTestInsets and T then
        local okI, l = pcall(PM.GetNamePlateHitTestInsets, T.Enemy)
        inset = okI and plainv(l) or "refused"
    end
    local row = {
        game = game, ours = ours, spare = spare, invisible = invisible, oursHidden = oursHidden,
        behind = behind, lowAlpha = lowAlpha, minScale = minScale, maxScale = maxScale,
        size = tostring(w) .. "x" .. tostring(h), inset = inset,
        ui = string.format("%s/%s/%s", tostring(ask(UIParent, "IsShown")), tostring(ask(UIParent, "GetAlpha")),
            tostring(ask(UIParent, "GetEffectiveScale"))),
        world = string.format("%s/%s/%s", tostring(ask(WorldFrame, "IsShown")), tostring(ask(WorldFrame, "GetAlpha")),
            tostring(ask(WorldFrame, "GetEffectiveScale"))),
    }
    local sig = table.concat({ row.game, row.ours, row.invisible, row.oursHidden, row.behind, row.lowAlpha,
        tostring(row.minScale), tostring(row.maxScale), row.size, tostring(row.inset), row.ui, row.world }, "|")
    local now = GetTime()
    if sig ~= lastSig or added > 0 or removed > 0 or now - lastWrite >= PlateLog.HEARTBEAT then
        row.added, row.removed = added, removed
        row.fps = math.floor((GetFramerate and GetFramerate() or 0) + 0.5)
        note(sig == lastSig and "tick" or "state", row)
        lastSig, lastWrite = sig, now
    end
    added, removed = 0, 0
end

-- ---------------------------------------------------------------------
-- Game events that could change how plates are drawn
-- ---------------------------------------------------------------------

PlateLog.EVENTS = {
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "CINEMATIC_START", "CINEMATIC_STOP", "PLAY_MOVIE",
    "STOP_MOVIE", "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_DETAIL", "QUEST_FINISHED", "MERCHANT_SHOW",
    "MERCHANT_CLOSED", "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_FLAGS_CHANGED", "ADDON_ACTION_BLOCKED",
    "ADDON_ACTION_FORBIDDEN", "CVAR_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "FORBIDDEN_NAME_PLATE_UNIT_ADDED", "FORBIDDEN_NAME_PLATE_UNIT_REMOVED", "NAME_PLATE_CREATED",
    "FORBIDDEN_NAME_PLATE_CREATED",
}
local PLAYER_ONLY = { UNIT_ENTERED_VEHICLE = true, UNIT_EXITED_VEHICLE = true, PLAYER_FLAGS_CHANGED = true }

local function onEvent(_, event, a, b)
    if event == "NAME_PLATE_UNIT_ADDED" or event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then
        added = added + 1
        if event == "FORBIDDEN_NAME_PLATE_UNIT_ADDED" then note(event, { unit = a }) end
        return
    elseif event == "NAME_PLATE_UNIT_REMOVED" or event == "FORBIDDEN_NAME_PLATE_UNIT_REMOVED" then
        removed = removed + 1
        return
    end
    if PLAYER_ONLY[event] and a ~= "player" then return end
    local extra
    if event == "CVAR_UPDATE" then
        extra = { cvar = a, value = cvar(a) }
    elseif event == "PLAYER_FLAGS_CHANGED" then
        extra = { afk = UnitIsAFK and plainv(UnitIsAFK("player")) or nil }
    elseif event == "PLAYER_ENTERING_WORLD" then
        extra = { login = a, reload = b }
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        extra = { addon = a, fn = b }
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then
        extra = { zone = GetRealZoneText and plainv(GetRealZoneText()) or nil }
    end
    note(event, extra)
    if event == "LOADING_SCREEN_DISABLED" or event == "DISPLAY_SIZE_CHANGED" then PlateLog.Sample() end
end

-- ---------------------------------------------------------------------
-- Every call Daylight UI makes on the game's plates
-- ---------------------------------------------------------------------

PlateLog.CALLS = { "ApplySize", "ApplyScales", "ApplyStacking", "ApplyClickable", "ApplyNameOnly", "ApplyRange",
    "ApplyInstanceFriends", "Refresh", "Unseen", "Fix" }

local inSync, syncAdded, syncRemoved = false, 0, 0
local function wrapManager(M)
    if M.plateLogWrapped then return end
    M.plateLogWrapped = true
    for _, name in ipairs(PlateLog.CALLS) do
        local fn = M[name]
        if type(fn) == "function" then
            M[name] = function(...)
                note("ours:" .. name)
                return fn(...)
            end
        end
    end
    local Added, Removed, Sync = M.Added, M.Removed, M.Sync
    if type(Added) == "function" then
        M.Added = function(unit, ...)
            if inSync then syncAdded = syncAdded + 1 end
            return Added(unit, ...)
        end
    end
    if type(Removed) == "function" then
        M.Removed = function(unit, ...)
            if inSync then syncRemoved = syncRemoved + 1 end
            return Removed(unit, ...)
        end
    end
    if type(Sync) == "function" then
        M.Sync = function(...)
            inSync, syncAdded, syncRemoved = true, 0, 0
            local ok, err = pcall(Sync, ...)
            inSync = false
            if syncAdded > 0 or syncRemoved > 0 then
                note("ours:Sync", { added = syncAdded, removed = syncRemoved })
            end
            if not ok then error(err, 0) end
        end
    end
end

-- Daylight UI's NPC scene (over-the-shoulder camera, UI faded) starting and ending.
local function wrapScene()
    local Scene = DUI.Npc and DUI.Npc.Scene
    if type(Scene) ~= "table" or Scene.plateLogWrapped then return end
    Scene.plateLogWrapped = true
    for _, name in ipairs({ "Entered", "Left" }) do
        local fn = Scene[name]
        if type(fn) == "function" then
            Scene[name] = function(...)
                note("ours:Scene." .. name)
                return fn(...)
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- The mark: everything about every plate at the moment they're gone
-- ---------------------------------------------------------------------

local function plateLines()
    local out = {}
    local list = gamePlates()
    if not list then return { "no GetNamePlates" } end
    local byPlate = {}
    if ns.Manager then
        for unit, p in pairs(ns.Manager.byUnit) do
            if p.nameplate then byPlate[p.nameplate] = { unit = unit, p = p } end
        end
    end
    for i, np in pairs(list) do
        local unit = type(np.GetUnit) == "function" and ask(np, "GetUnit") or "?"
        local parent = ask(np, "GetParent")
        local line = string.format("%s %s shown=%s vis=%s a=%s ea=%s scale=%s lvl=%s strata=%s rect=%s parent=%s",
            tostring(i), tostring(unit), tostring(ask(np, "IsShown")), tostring(ask(np, "IsVisible")),
            tostring(ask(np, "GetAlpha")), tostring(ask(np, "GetEffectiveAlpha")), tostring(ask(np, "GetEffectiveScale")),
            tostring(ask(np, "GetFrameLevel")), tostring(ask(np, "GetFrameStrata")), tostring(ask(np, "IsRectValid")),
            tostring(type(parent) == "table" and ask(parent, "GetName") or parent))
        local uf = np.UnitFrame
        if type(uf) == "table" then
            line = line .. string.format(" uf: a=%s shown=%s parent=np:%s", tostring(ask(uf, "GetAlpha")),
                tostring(ask(uf, "IsShown")), tostring(ask(uf, "GetParent") == np))
        else
            line = line .. " uf: none"
        end
        line = line .. " behind=" .. tostring(behindCamera(unit))
        local mine = byPlate[np]
        if mine then
            local p = mine.p
            line = line .. string.format(" OURS %s: shown=%s vis=%s a=%s scale=%s lvl=%s corpse=%s stackParentIsNp=%s",
                mine.unit, tostring(ask(p, "IsShown")), tostring(ask(p, "IsVisible")), tostring(ask(p, "GetAlpha")),
                tostring(ask(p, "GetEffectiveScale")), tostring(ask(p, "GetFrameLevel")), tostring(p.corpse),
                tostring(p.stack ~= nil and ask(p.stack, "GetParent") == np))
        else
            line = line .. " no plate of ours"
        end
        out[#out + 1] = line
    end
    return out
end

PlateLog.MARK_CVARS = { "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriendlyPlayers",
    "nameplateShowFriendlyNpcs", "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateMinScale",
    "nameplateMaxScale", "nameplateSelectedScale", "nameplateGlobalScale", "nameplateMinAlpha", "nameplateMaxAlpha",
    "nameplateOccludedAlphaMult", "nameplateStackingTypes", "nameplateMaxDistance", "nameplateSize",
    "nameplateStyle", "nameplateSimplifiedTypes", "nameplateGameObjectMaxDistance", "nameplateShowEnemyMinions",
    "test_cameraOverShoulder", "test_cameraTargetFocusInteractEnable", "CameraKeepCharacterCentered", "uiScale",
    "useUiScale", "gxMaximize", "gxWindow", "renderscale" }

function PlateLog.Mark(why)
    PlateLog.Sample()
    local M = ns.Manager
    local check = M and M.CheckLines and select(2, pcall(M.CheckLines, 40)) or nil
    local cvars = {}
    for _, name in ipairs(PlateLog.MARK_CVARS) do cvars[#cvars + 1] = name .. "=" .. tostring(cvar(name)) end
    note("MARK", {
        why = why, plates = plateLines(), check = type(check) == "table" and check or nil, cvars = cvars,
        zone = GetRealZoneText and plainv(GetRealZoneText()) or nil,
        sub = GetSubZoneText and plainv(GetSubZoneText()) or nil,
        combat = InCombatLockdown and InCombatLockdown() or nil, mounted = IsMounted and plainv(IsMounted()) or nil,
        taxi = UnitOnTaxi and plainv(UnitOnTaxi("player")) or nil, minutes = math.floor((GetTime() - started) / 6) / 10,
    })
end

-- One row as one line of text for the copy box; tables (a mark's plates) are left out.
local function rowLine(row)
    local keys = {}
    for k, v in pairs(row) do
        if k ~= "s" and k ~= "t" and k ~= "at" and k ~= "what" and type(v) ~= "table" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = { string.format("%s s%s %s", tostring(row.at), tostring(row.s), tostring(row.what)) }
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(row[k]) end
    return table.concat(parts, " ")
end

-- What a player sends after a mark: the plates now (Manager.CheckLines), where
-- they are, then as many of the newest log rows as fit, newest first.
function PlateLog.Report()
    local M = ns.Manager
    local out = { string.format("Daylight UI %s platelog", tostring(DUI.VERSION)) }
    if M and M.ReportWorld then for _, line in ipairs(M.ReportWorld()) do out[#out + 1] = line end end
    if M and M.CheckLines then
        local ok, lines = pcall(M.CheckLines, M.REPORT_PLATES or 2)
        if ok and type(lines) == "table" then for _, line in ipairs(lines) do out[#out + 1] = line end end
    end
    out[#out + 1] = "Log, newest first:"
    local used = #table.concat(out, "\n")
    local d = PlateLog.DB()
    local log = d and d.log or {}
    for i = #log, 1, -1 do
        local line = rowLine(log[i])
        if used + #line + 1 > PlateLog.REPORT_MAX then break end
        out[#out + 1] = line
        used = used + #line + 1
    end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------

local ticker
function PlateLog.Start()
    local d = PlateLog.DB()
    if not d then return end
    d.sessions = (d.sessions or 0) + 1
    session = d.sessions
    note("login", { version = DUI.VERSION, on = d.on })
    if ns.Manager then wrapManager(ns.Manager) end
    wrapScene()
    if not ticker then ticker = C_Timer.NewTicker(1, PlateLog.Sample) end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- After the modules are built (they start at PLAYER_LOGIN; this runs after).
        self:UnregisterEvent("PLAYER_LOGIN")
        for _, e in ipairs(PlateLog.EVENTS) do pcall(self.RegisterEvent, self, e) end
        C_Timer.After(0, PlateLog.Start)
        return
    end
    onEvent(self, event, ...)
end)
frame:RegisterEvent("PLAYER_LOGIN")

DUI.RegisterCommand("platelog", function(arg)
    local d = PlateLog.DB()
    if not d then return end
    arg = (arg or ""):lower():match("^%s*(%S*)") or ""
    if arg == "mark" then
        PlateLog.Mark("marked")
        DUI.Profiles.ShowText(L["Nameplate report"], L["Ctrl+C to copy, then paste it in a bug report on the Daylight UI Discord. "
            .. "After that, /reload."], string.sub(PlateLog.Report(), 1, PlateLog.REPORT_MAX))
        DUI.Print(L["Copy the text in the box and send it to the Daylight UI team, then /reload."])
    elseif arg == "clear" then
        d.log = {}
        DUI.Print(L["platelog: cleared."])
    else
        d.on = not d.on
        DUI.Print(string.format(L["platelog: %s, %d rows kept."], d.on and L["on"] or L["off"], #d.log))
    end
end, L["/dui platelog - run while nameplates are invisible: copy what it shows into a bug report"])
