-- The pieces of /dui platecheck and /dui platefix that don't need the
-- Nameplates module: the game's plates as they read, the player's screen and
-- UI scale, which parts of Daylight UI are on, and the text cut safe for the
-- copy box. The Nameplates module builds its check and report on these.
-- Plates have gone invisible with that module switched off too, so with it off
-- these commands are registered here, with the steps that don't need it.
-- Chat output stays in English: it's read by whoever works on the bug.

local _, DUI = ...
local L = DUI.L

local R = {}
DUI.PlateReport = R

DUI.RegisterCommand("flatoff", function()
    local mod = DUI:GetModule("Nameplates")
    if not (mod and mod.enabled) then return DUI.Print(L["flatoff: Nameplates is off"]) end
    if InCombatLockdown() then return DUI.Print(L["flatoff: try again out of combat"]) end
    if mod.ns.Manager.ToggleFlattening() then
        DUI.Print(L["flatoff: plates no longer flatten their layers (until /reload)"])
    else
        DUI.Print(L["flatoff: plates flatten their layers again"])
    end
end, function() return L["/dui flatoff - switch nameplate layer flattening off and on"] end)

local function plain(v)
    if DUI.IsSecret(v) then return nil end
    return v
end

function R.CVar(name)
    if type(GetCVar) ~= "function" then return nil end
    local ok, v = pcall(GetCVar, name)
    return ok and type(v) == "string" and v or nil
end

-- Text an edit box shows as it is: control bytes become "?", a "|" is doubled
-- (else the box reads it as a color or link code), broken UTF-8 becomes "?", and
-- a cut at max bytes never splits a character. Any of these left the copy box empty.
function R.Printable(text, max)
    local out, len, i = {}, 0, 1
    while i <= #text do
        local b = text:byte(i)
        local n = b < 0x80 and 1 or (b >= 0xF0 and b < 0xF5) and 4 or (b >= 0xE0 and b < 0xF0) and 3
            or (b >= 0xC2 and b < 0xE0) and 2 or 0
        local piece
        if n == 1 then
            piece = (b == 124 and "||") or (((b < 32 and b ~= 10) or b == 127) and "?") or string.char(b)
        elseif n > 1 then
            piece = text:sub(i, i + n - 1)
            for k = 2, n do
                local c = piece:byte(k)
                if not c or c < 0x80 or c > 0xBF then piece = nil break end
            end
        end
        if not piece then piece, n = "?", 1 end
        if max and len + #piece > max then break end
        out[#out + 1] = piece
        len = len + #piece
        i = i + n
    end
    return table.concat(out)
end

-- text cut to max bytes, never inside a character.
function R.Cut(text, max)
    if #text <= max then return text end
    local i = max + 1
    while i > 1 and text:byte(i) and text:byte(i) >= 0x80 and text:byte(i) < 0xC0 do i = i - 1 end
    return text:sub(1, i - 1)
end

-- One answer from a frame, guarded: "?" if it errors, "secret" if it's secret.
function R.Asked(f, method)
    local ok, v = pcall(function() return f[method](f) end)
    if not ok then return "?" end
    if DUI.IsSecret(v) then return "secret" end
    if type(v) == "number" then return string.format("%.2f", v) end
    return tostring(v)
end

function R.Where(f)
    local ok, l, b, w, h = pcall(function() return f:GetRect() end)
    if not ok then return "can't measure" end -- the game refuses; says nothing about the plate
    if type(l) == "nil" then return "no rect" end
    if DUI.IsSecret(l) or DUI.IsSecret(b) or DUI.IsSecret(w) or DUI.IsSecret(h) then return "secret" end
    return string.format("%.0f,%.0f %.0fx%.0f", l, b, w, h)
end

function R.State(f)
    local asked = R.Asked
    return string.format("shown=%s visible=%s alpha=%s effective=%s strata=%s scale=%s rectValid=%s box=%s",
        asked(f, "IsShown"), asked(f, "IsVisible"), asked(f, "GetAlpha"), asked(f, "GetEffectiveAlpha"),
        asked(f, "GetFrameStrata"), asked(f, "GetEffectiveScale"), asked(f, "IsRectValid"), R.Where(f))
end

-- A game plate's opening lines: the unit and the plate frame itself, and the
-- frame above it. wrong = the plate reads hidden or see-through.
function R.PlateHead(unit, np)
    -- nil for no answer or a secret one; a plain false stays false.
    local function ask(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if not ok then return nil end
        return plain(v)
    end
    local attack = ask(UnitCanAttack, "player", unit)
    local kind = attack == true and "enemy" or attack == false and "friendly" or "unknown"
    -- The one look Lua gets at where the game thinks the unit is on screen: a
    -- unit in front of the player that reads as behind the camera is misplaced.
    local M = C_NamePlateManager
    local behind = type(M) == "table" and ask(M.IsNamePlateUnitBehindCamera, unit)
    local head = string.format("%s: %s, player=%s, minion=%s, target=%s, behindCamera=%s", unit, kind,
        tostring(ask(UnitIsPlayer, unit)), tostring(ask(UnitIsMinion, unit)), tostring(ask(UnitIsUnit, unit, "target")),
        tostring(behind))
    local lines = { head, "  game plate " .. R.State(np) }
    local wrong = R.Asked(np, "IsVisible") ~= "true" or R.Asked(np, "GetAlpha") == "0.00"
        or R.Asked(np, "GetEffectiveAlpha") == "0.00"
    local okUp, up = pcall(function() return np:GetParent() end)
    if okUp and type(up) == "table" then
        lines[#lines + 1] = "  above it " .. R.Asked(up, "GetName") .. " " .. R.State(up)
    end
    return lines, wrong
end

-- The game's plate settings in a line, and whether its settings copy is tainted.
R.GAME_CVARS = { "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateOccludedAlphaMult", "nameplateGlobalScale",
    "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale", "nameplateMaxDistance" }
R.STACK_CVAR = "nameplateStackingTypes"

function R.GameLines()
    local words = {}
    for _, name in ipairs(R.GAME_CVARS) do
        local ok, v = pcall(C_CVar.GetCVar, name)
        words[#words + 1] = name:gsub("^nameplate", "") .. "=" .. tostring(ok and v)
    end
    -- The stacking setting is a bitfield whose raw value isn't text (the copy box
    -- showed nothing at all with it in), so it's read bit by bit.
    local E = Enum and Enum.NamePlateStackType
    local getBit = C_CVar and C_CVar.GetCVarBitfield
    if E and type(getBit) == "function" then
        local function bit(i)
            local ok, v = pcall(getBit, R.STACK_CVAR, i)
            return tostring(ok and plain(v))
        end
        words[#words + 1] = "Stacking enemy=" .. bit(E.Enemy) .. " friendly=" .. bit(E.Friendly)
    end
    local out = { "Game: " .. table.concat(words, " ") }
    local Bug = DUI.BugReport
    if type(Bug) == "table" and type(Bug.PlateCache) == "function" then
        local tainted = Bug.PlateCache()
        out[#out + 1] = #tainted > 0 and ("Plate settings tainted: " .. table.concat(tainted, ", "))
            or "Plate settings: clean"
    end
    return out
end

-- How the game is shown: screen, window mode, graphics card, frame caps, and the
-- UI scale three ways (the game's setting, whether it's used, and what UIParent
-- really has, which Daylight UI keeps at its own saved value), with how often
-- the scale and the screen changed this session.
R.changes = { scale = 0, display = 0 }
DUI.RegisterEvent("UI_SCALE_CHANGED", function() R.changes.scale = R.changes.scale + 1 end)
DUI.RegisterEvent("DISPLAY_SIZE_CHANGED", function() R.changes.display = R.changes.display + 1 end)

-- What happened in the game and in Daylight UI before a platefix, oldest
-- first: fights, loading screens, zones, game settings changed, the screen
-- and UI scale, cinematics, lost control, vehicles, the client's restrictions,
-- the AFK screen, the UI faded out and back, frames drawn to their own buffer,
-- NPC windows and quests taken or handed in, and plates coming and going. Players can't say what they did before the
-- plates went, so the report carries it. Only events feed it, nothing runs each
-- frame, and the same thing twice in a row counts up instead of taking a line.
R.LOG_SIZE = 24
R.LOG_BUCKET = 60 -- seconds of plates coming and going counted on one line
R.log = {}

local function clock() return type(GetTime) == "function" and GetTime() or 0 end

local function keep(entry)
    local log = R.log
    log[#log + 1] = entry
    if #log > R.LOG_SIZE then table.remove(log, 1) end
end

-- Frames drawn to their own buffer change after combat with no event of their
-- own, so the count is read each time something else is noted.
local buffersWas
local function buffers()
    local F = DUI.Fade
    local n = F and F.WholeCount and F.WholeCount()
    if type(n) == "number" and n ~= buffersWas then
        buffersWas = n
        keep({ at = clock(), what = "buffers drawn " .. n, times = 1 })
    end
end

function R.Note(what)
    buffers()
    local last = R.log[#R.log]
    if last and last.what == what then
        last.times, last.at = last.times + 1, clock()
        return
    end
    keep({ at = clock(), what = what, times = 1 })
end

function R.LogSize() return #R.log end

local platesNow
local function plateMoved(added)
    buffers()
    local now = clock()
    if not platesNow or now - platesNow.at >= R.LOG_BUCKET or R.log[#R.log] ~= platesNow then
        platesNow = { at = now, added = 0, removed = 0, times = 1 }
        keep(platesNow)
    end
    if added then platesNow.added = platesNow.added + 1 else platesNow.removed = platesNow.removed + 1 end
end
DUI.RegisterEvent("NAME_PLATE_UNIT_ADDED", function() plateMoved(true) end)
DUI.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function() plateMoved(false) end)

local NOTES = {
    PLAYER_REGEN_DISABLED = "fight", PLAYER_REGEN_ENABLED = "fight over",
    LOADING_SCREEN_ENABLED = "loading screen", PLAYER_ENTERING_WORLD = "entered the world",
    UI_SCALE_CHANGED = "UI scale changed", DISPLAY_SIZE_CHANGED = "screen size changed",
    CINEMATIC_START = "cinematic", CINEMATIC_STOP = "cinematic over", PLAY_MOVIE = "movie", STOP_MOVIE = "movie over",
    PLAYER_CONTROL_LOST = "lost control", PLAYER_CONTROL_GAINED = "control back",
}
for event, what in pairs(NOTES) do DUI.RegisterEvent(event, function() R.Note(what) end) end
DUI.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    R.Note("zone " .. tostring(type(GetRealZoneText) == "function" and plain(GetRealZoneText()) or "?"))
end)
-- Some changes come in runs and share one line, so they don't push everything
-- else out of the log: settings another addon eases a step at a time (voice-over
-- addons lower the sound while an NPC talks, nine lines a time), and one visit
-- to an NPC (its windows, the quests taken or handed in, closing it). Anything
-- else noted in between starts a new line.
R.FOLD_GAP = { settings = 10, npc = 120 } -- most seconds between two changes on one line
R.FOLD_NAMES = 6 -- settings named on one line, then "+N more"
R.FOLD_PARTS = 12 -- steps of one NPC visit on one line, then "..."

local function folding(kind)
    buffers()
    local last, now = R.log[#R.log], clock()
    if last and last.fold == kind and now - last.at < R.FOLD_GAP[kind] then
        last.at = now
        return last
    end
    local e = { at = now, fold = kind, times = 1, parts = {}, values = {}, changes = 0 }
    keep(e)
    return e
end

DUI.RegisterEvent("CVAR_UPDATE", function(_, name, value)
    local e = folding("settings")
    name, value = tostring(plain(name)), tostring(plain(value))
    if e.values[name] == nil then e.parts[#e.parts + 1] = name end
    e.values[name] = value
    e.changes = e.changes + 1
end)

local function npcStep(text, isNpc)
    local e = folding("npc")
    e.npc = e.npc or isNpc
    if e.parts[#e.parts] == text then return end
    if #e.parts >= R.FOLD_PARTS then e.cut = true; return end
    e.parts[#e.parts + 1] = text
end

-- The game's own name for the kind of window (Gossip, QuestGiver, Trainer...).
local function interaction(kind)
    kind = plain(kind)
    local names = type(Enum) == "table" and Enum.PlayerInteractionType
    if type(names) == "table" then
        for name, v in pairs(names) do
            if v == kind then return name end
        end
    end
    return "window " .. tostring(kind)
end

local function questName(id)
    id = plain(id)
    local title = type(id) == "number" and C_QuestLog and C_QuestLog.GetTitleForQuestID
        and C_QuestLog.GetTitleForQuestID(id)
    title = plain(title)
    if type(title) == "string" and title ~= "" then return R.Printable(title, 40) end
    return tostring(id)
end

DUI.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind) npcStep(interaction(kind), true) end)
DUI.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function() npcStep("closed", true) end)
DUI.RegisterEvent("QUEST_ACCEPTED", function(_, id) npcStep("took quest " .. questName(id)) end)
DUI.RegisterEvent("QUEST_TURNED_IN", function(_, id) npcStep("handed in quest " .. questName(id)) end)
DUI.RegisterEvent("UNIT_ENTERED_VEHICLE", function(_, unit) if unit == "player" then R.Note("vehicle") end end)
DUI.RegisterEvent("UNIT_EXITED_VEHICLE", function(_, unit) if unit == "player" then R.Note("vehicle over") end end)
DUI.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, kind, state)
    R.Note(string.format("restriction %s=%s", tostring(plain(kind)), tostring(plain(state))))
end)
DUI.On("AfkScreenShown", function() R.Note("AFK screen") end)
DUI.On("AfkScreenHidden", function() R.Note("AFK screen over") end)
-- The AFK screen and the NPC scene fade the whole UI a step each frame: only
-- the ends are noted.
local uiOut = false
DUI.On("UIAlpha", function(a)
    if type(a) ~= "number" then return end
    if a <= 0.01 and not uiOut then uiOut = true; R.Note("UI faded out")
    elseif a >= 0.99 and uiOut then uiOut = false; R.Note("UI back"); R.Restore("UI faded back") end
end)

-- The client draws nameplates and speech bubbles under one switch of its own,
-- apart from UIParent. Alt+Z (SetUIVisibility) turns it off along with the UI,
-- and the game turns it back on wherever it shows UIParent again. If something
-- shows the UI without it, plates and bubbles stay gone while the rest is back,
-- and Lua can't read the switch. So every call is noted with who made it.
R.inWorld, R.inWorldBy = nil, nil -- the last value anyone set; nil while nobody has
-- The last few changes, kept apart from the log: a burst of setting changes
-- would push them out of it.
R.SWITCH_KEEP = 4
R.switches = {}

local function ago(at, now)
    local s = math.max(0, math.floor(now - at + 0.5))
    return string.format("-%d:%02d", math.floor(s / 60), s % 60)
end

-- The first addon on the stack that isn't this file: the game's own code shows
-- as its Blizzard_ folder. No addon at all is a key binding or the client.
function R.Caller()
    if type(debugstack) ~= "function" then return "?" end
    local ok, stack = pcall(debugstack, 2, 12, 0)
    if not ok or type(stack) ~= "string" or DUI.IsSecret(stack) then return "?" end
    for line in stack:gmatch("[^\n]+") do
        if not line:find("PlateReport.lua", 1, true) then
            local name = line:match("AddOns[/\\]([^/\\]+)[/\\]")
            if name then return name end
        end
    end
    return "a key or the client"
end

local function watchSwitch(fn, label)
    if type(_G[fn]) ~= "function" then return end
    hooksecurefunc(fn, function(v)
        local on
        if not DUI.IsSecret(v) then on = v == true end
        local by = R.cycling and "/dui platefix" or R.restoring or R.Caller()
        R.inWorld, R.inWorldBy = on, by
        if R.restoring then return end
        local list = R.switches
        list[#list + 1] = { at = clock(), on = on, by = by }
        if #list > R.SWITCH_KEEP then table.remove(list, 1) end
        R.Note(string.format("%s %s by %s", label, on == nil and "?" or on and "on" or "off", by))
    end)
end
watchSwitch("SetUIVisibility", "whole UI and plates")
watchSwitch("SetInWorldUIVisibility", "plates and bubbles")
UIParent:HookScript("OnHide", function() R.Note("UI hidden") end)
UIParent:HookScript("OnShow", function() R.Note("UI shown"); R.Restore("UI shown") end)

-- Loading screens, landing from a flight, cinematics and fades of the whole UI
-- are where the switch has been left off while the UI came back. Turning it on
-- again there is safe to repeat: the game's Commentator code does it every
-- frame. Never while the UI is hidden, so the player's own Alt+Z stays off.
-- These calls aren't kept among the switch changes, or they'd push out the
-- ones that tell who turned it off.
function R.Restore(after)
    if not UIParent:IsShown() or InCombatLockdown() then return end
    R.restoring = "Daylight UI after " .. after
    if type(SetUIVisibility) == "function" then DUI.SafeCall(SetUIVisibility, true) end
    if type(SetInWorldUIVisibility) == "function" then DUI.SafeCall(SetInWorldUIVisibility, true) end
    R.restoring = nil
end
local RESTORE_AFTER = {
    LOADING_SCREEN_DISABLED = "a loading screen", PLAYER_CONTROL_GAINED = "control came back",
    CINEMATIC_STOP = "a cinematic", STOP_MOVIE = "a movie",
}
for event, what in pairs(RESTORE_AFTER) do DUI.RegisterEvent(event, function() R.Restore(what) end) end

-- Players say the plates go around travel: a loading screen, a flight, a
-- hearthstone, a character change. The log only reaches back a minute or so,
-- so the last of each is kept apart from it, with how long ago it was. A
-- flight shows as control lost for a minute or more.
R.travel = { loads = 0 }
local function zoneNow()
    local z = type(GetRealZoneText) == "function" and plain(GetRealZoneText()) or nil
    return R.Cut(tostring(z), 40)
end
DUI.RegisterEvent("LOADING_SCREEN_DISABLED", function()
    local t = R.travel
    t.loads, t.loadAt, t.loadZone = t.loads + 1, clock(), zoneNow()
end)
DUI.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    R.travel.zoneAt, R.travel.zone = clock(), zoneNow()
end)
DUI.RegisterEvent("PLAYER_CONTROL_LOST", function() R.travel.lostAt = clock() end)
DUI.RegisterEvent("PLAYER_CONTROL_GAINED", function()
    local t = R.travel
    if t.lostAt then t.backAt, t.lostFor, t.lostAt = clock(), clock() - t.lostAt, nil end
end)

function R.Travel()
    local t, now = R.travel, clock()
    local load = t.loadAt and string.format("last %s into %s", ago(t.loadAt, now), tostring(t.loadZone)) or "none yet"
    local zone = t.zoneAt and string.format("%s into %s", ago(t.zoneAt, now), tostring(t.zone)) or "none yet"
    local control = t.lostAt and string.format("lost now, for %.0f s", now - t.lostAt)
        or t.backAt and string.format("last back %s after %.0f s", ago(t.backAt, now), t.lostFor)
        or "never lost"
    return string.format("Travel: loading screens %d (%s); zone change %s; control %s", t.loads, load, zone, control)
end

-- Speech bubbles go with the plates, so the report counts them too (only
-- anyone talking nearby gives one), with the game's bubble settings.
function R.WorldUI()
    local set = R.inWorld == nil and "never set this session"
        or string.format("last set %s by %s", R.inWorld and "on" or "off", tostring(R.inWorldBy))
    if #R.switches > 0 then
        local now, said = clock(), {}
        for _, s in ipairs(R.switches) do
            said[#said + 1] = string.format("%s by %s %s", s.on == nil and "?" or s.on and "on" or "off", s.by,
                ago(s.at, now))
        end
        set = set .. " (switch changes: " .. table.concat(said, ", ") .. ")"
    end
    local bubbles, shown = "?", 0
    local B = C_ChatBubbles
    if type(B) == "table" and type(B.GetAllChatBubbles) == "function" then
        local ok, list = pcall(B.GetAllChatBubbles, false)
        if ok and type(list) == "table" then
            bubbles = 0
            for _, b in pairs(list) do
                bubbles = bubbles + 1
                if R.Asked(b, "IsVisible") == "true" then shown = shown + 1 end
            end
        end
    end
    return string.format("World UI: plates and bubbles switch %s, UI shown %s; speech bubbles %s (%d visible), "
        .. "chatBubbles=%s chatBubblesParty=%s", set, R.Asked(UIParent, "IsShown"), tostring(bubbles), shown,
        tostring(R.CVar("chatBubbles")), tostring(R.CVar("chatBubblesParty")))
end

local function inWorld(on)
    R.cycling = true
    local ok, err = pcall(SetInWorldUIVisibility, on)
    R.cycling = nil
    return ok, err
end

-- A platefix step: the switch off, then back on a moment later. Plates have
-- been seen there and "visible" with the switch never touched, yet not drawn,
-- so setting it on while it's already on may change nothing in the client.
function R.InWorldBack()
    local why
    if type(SetInWorldUIVisibility) == "function" then
        local ok, err = inWorld(false)
        if ok then
            local done = R.FixHold()
            C_Timer.After(R.FIX_GAP, function()
                local back, err2 = inWorld(true)
                if not back then
                    R.Note("plates and bubbles refused back on: " .. R.Printable(tostring(err2), R.MARK_WHY))
                end
                -- The whole UI's switch too, every time: with both, a player
                -- gets the plates back here without a /reload.
                if type(SetUIVisibility) == "function" and UIParent:IsShown() then
                    R.cycling = true
                    DUI.SafeCall(SetUIVisibility, true)
                    R.cycling = nil
                end
                -- The game hands its plates back out a moment after the switch
                -- comes on, so the step's "after" count waits for that.
                C_Timer.After(R.FIX_SETTLE, done)
            end)
            return "the game's switch for nameplates and speech bubbles turned off and back on, then the UI's"
                .. " switch on (wait a second)"
        end
        why = err
        if inWorld(true) then return "the game's switch for nameplates and speech bubbles turned on" end
    end
    if type(SetUIVisibility) == "function" and UIParent:IsShown() then
        local ok, err = pcall(SetUIVisibility, true)
        if ok then return "the game's UI switch turned on, nameplates and speech bubbles with it" end
        why = why or err
    end
    return "the game refused to turn nameplates and speech bubbles on (" .. R.Printable(tostring(why), R.MARK_WHY) .. ")"
end

-- Platefix steps on WorldFrame itself, the frame plates and speech bubbles
-- hang on. Caught live on two PCs: a plain square made on WorldFrame didn't
-- draw while one on UIParent did, and every Lua read of WorldFrame matched a
-- healthy session. So the client stopped drawing that whole layer, and the
-- step that wakes it says what it lost. Each one changes a single thing for
-- R.FIX_GAP seconds, then puts back what was there. Putting back waits for the
-- end of a fight if one starts in between, as WorldFrame may be protected.
local function worldStep(change, undo, said)
    local wf = WorldFrame
    if type(wf) ~= "table" then return "this client has no WorldFrame, nothing changed" end
    local ok, was = DUI.SafeReturn(change, wf)
    if not ok then return "the game refused it, nothing changed" end
    local done = R.FixHold()
    C_Timer.After(R.FIX_GAP, function()
        local function back()
            DUI.SafeCall(undo, wf, was)
            C_Timer.After(R.FIX_SETTLE, done)
        end
        if InCombatLockdown() then
            DUI.AfterCombat(back, "platefixWorld")
            done()
        else
            back()
        end
    end)
    return said
end

-- Each change returns what it found, for the undo to put back.
R.WORLD_STEPS = {
    function()
        return worldStep(function(wf)
            local a = wf:GetAlpha()
            wf:SetAlpha(0.99)
            return a
        end, function(wf, a) wf:SetAlpha(a) end,
            "the layer nameplates and speech bubbles are drawn on faded a hair and back (wait a second)")
    end,
    function()
        return worldStep(function(wf)
            local level = wf:GetFrameLevel()
            wf:SetFrameLevel(level + 1)
            return level
        end, function(wf, level) wf:SetFrameLevel(level) end,
            "the layer nameplates and speech bubbles are drawn on moved up a level and back (wait a second)")
    end,
    function()
        return worldStep(function(wf)
            local clips = wf:DoesClipChildren()
            wf:SetClipsChildren(not clips)
            return clips
        end, function(wf, clips) wf:SetClipsChildren(clips) end,
            "the layer nameplates and speech bubbles are drawn on: its edge cut switched and back (wait a second)")
    end,
    function()
        return worldStep(function(wf)
            wf:Hide()
            return true
        end, function(wf) wf:Show() end,
            "the layer nameplates and speech bubbles are drawn on hidden for half a second and shown again "
            .. "(the world may blink; wait a second)")
    end,
}

-- One folded line in words, and how many times to count it.
local function foldedLine(e)
    if e.fold == "npc" then
        return (e.npc and "NPC " or "") .. table.concat(e.parts, ", ") .. (e.cut and ", ..." or ""), 1
    end
    local shown = {}
    for i = 1, math.min(#e.parts, R.FOLD_NAMES) do
        shown[i] = e.parts[i] .. "=" .. e.values[e.parts[i]]
    end
    if #e.parts == 1 then return "setting " .. shown[1], e.changes end
    local more = #e.parts > R.FOLD_NAMES and string.format(" +%d more", #e.parts - R.FOLD_NAMES) or ""
    return string.format("settings %s%s (%d changes)", table.concat(shown, " "), more, e.changes), 1
end

-- The log as report lines, each with how long before `at` (now when left out).
function R.LogLines(at)
    buffers()
    at = at or clock()
    local out = {}
    for _, e in ipairs(R.log) do
        if e.at <= at then
            local what, times = e.what, e.times
            if e.fold then
                what, times = foldedLine(e)
            elseif not what then
                what = string.format("plates +%d -%d", e.added, e.removed)
            end
            out[#out + 1] = string.format("  %s %s%s", ago(e.at, at), what,
                times > 1 and string.format(" (x%d)", times) or "")
        end
    end
    if #out == 0 then out[1] = "  nothing yet" end
    return out
end

function R.Screen()
    local words = {}
    local function add(label, v)
        if v ~= nil then words[#words + 1] = label .. "=" .. tostring(v) end
    end
    if type(GetPhysicalScreenSize) == "function" then
        local ok, w, h = pcall(GetPhysicalScreenSize)
        if ok and type(w) == "number" and type(h) == "number" then words[#words + 1] = string.format("%dx%d", w, h) end
    end
    if type(GetMonitorCount) == "function" then
        local ok, n = pcall(GetMonitorCount)
        if ok then add("monitors", n) end
    end
    add("maximized", R.CVar("gxMaximize"))
    add("windowed", R.CVar("gxWindow"))
    add("api", R.CVar("gxapi"))
    add("maxFPS", R.CVar("maxFPS"))
    add("background", R.CVar("maxFPSBk"))
    local V = C_VideoOptions
    if type(V) == "table" and type(V.GetGxAdapterInfo) == "function" then
        local ok, list = pcall(V.GetGxAdapterInfo)
        if ok and type(list) == "table" then
            local names = {}
            for _, a in ipairs(list) do
                if type(a) == "table" and type(a.name) == "string" then names[#names + 1] = a.name end
            end
            if #names > 0 then words[#words + 1] = "GPU " .. table.concat(names, " / ") end
        end
    end
    local ok, ui = pcall(UIParent.GetScale, UIParent)
    local scale = string.format("uiScale=%s useUiScale=%s UIParent=%s", tostring(R.CVar("uiScale")),
        tostring(R.CVar("useUiScale")), ok and type(ui) == "number" and string.format("%.2f", ui) or "?")
    return {
        "Screen: " .. table.concat(words, " "),
        string.format("Scale: %s, scale changes %d, display changes %d", scale, R.changes.scale, R.changes.display),
    }
end

-- Which Daylight UI modules are on, and the state right now of the things only
-- Daylight UI does outside its own plates: frames drawn to their own buffer,
-- UIParent's alpha (the AFK screen and NPC scene fade it), the AFK screen and
-- speech bubble settings, game windows held open out of sight (Win.Follow's aside
-- holder), and a quest waypoint being tracked.
function R.Daylight()
    local on, off = {}, {}
    local list = DUI.InstallerPages and DUI.InstallerPages.MODULES or {}
    for _, m in ipairs(list) do
        local into = DUI:GetModule(m.name) and on or off
        into[#into + 1] = m.name
    end
    local function setting(module, key)
        if not DUI:GetModule(module) then return module .. " off" end
        local ok, v = pcall(DUI.Get, DUI, module, key)
        return ok and (v and "on" or "off") or "?"
    end
    local Fade = DUI.Fade
    local buffers = Fade and Fade.WholeCount and Fade.WholeCount() or "?"
    local held = 0
    local F = DUI.Win and DUI.Win.Followers
    local function count(holder)
        local n = 0
        if holder then
            for _, c in ipairs({ holder:GetChildren() }) do
                if c.IsShown and c:IsShown() then n = n + 1 end
            end
        end
        return n
    end
    if F then held = count(F.aside) end
    local waypoint = "?"
    local S = C_SuperTrack
    if type(S) == "table" and type(S.IsSuperTrackingUserWaypoint) == "function" then
        local okW, w = pcall(S.IsSuperTrackingUserWaypoint)
        waypoint = okW and tostring(plain(w)) or "?"
    end
    return {
        string.format("Daylight UI modules on: %s; off: %s", #on > 0 and table.concat(on, " ") or "none",
            #off > 0 and table.concat(off, " ") or "none"),
        string.format("Daylight UI now: buffers drawn %s, UIParent alpha %s, AFK screen %s, bubble skin %s, "
            .. "game windows held open %d, quest waypoint tracked %s", tostring(buffers), R.Asked(UIParent, "GetAlpha"),
            setting("QoL", "afkScreen"), setting("Chat", "bubbles"), held, waypoint),
    }
end

-- Where the player is, how the game is shown, what of Daylight UI is on, and
-- the other addons loaded. startedAt: GetTime() when the plates started.
R.REPORT_ADDONS = 40
R.ZONE_MAX = 80 -- bytes of the zone name kept, so the report's room goes to the plates
R.REPORT_CVARS = {
    "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs",
    "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale",
    "nameplateSize", "nameplateStyle", "nameplateSimplifiedTypes", "nameplateMotionSpeed", "nameplateShowEnemyMinions",
    -- How far plates push each other apart and how near the screen edge they may
    -- sit. Other nameplate addons write these, and they stay after one is removed.
    "nameplateOverlapH", "nameplateOverlapV", "nameplateOtherTopInset", "nameplateOtherBottomInset",
    "nameplateLargeTopInset", "nameplateLargeBottomInset",
}

function R.World(startedAt)
    local out = {}
    startedAt = startedAt or R.loggedInAt
    local up = startedAt and type(GetTime) == "function" and (GetTime() - startedAt) / 60
    local zone = type(GetRealZoneText) == "function" and plain(GetRealZoneText()) or nil
    local kind
    if type(GetInstanceInfo) == "function" then
        local ok, _, instanceType = pcall(GetInstanceInfo)
        kind = ok and instanceType or nil
    end
    out[#out + 1] = string.format("%s min since login or /reload, zone %s (%s), restricted=%s",
        up and string.format("%.0f", up) or "?", R.Cut(tostring(zone), R.ZONE_MAX), tostring(kind),
        tostring(DUI.Restricted() == true))
    out[#out + 1] = R.Travel()
    local words = {}
    for _, name in ipairs(R.REPORT_CVARS) do
        local v = R.CVar(name)
        if v then words[#words + 1] = name:gsub("^nameplate", "") .. "=" .. v end
    end
    out[#out + 1] = "More: " .. table.concat(words, " ")
    for _, line in ipairs(R.Screen()) do out[#out + 1] = line end
    for _, line in ipairs(R.Daylight()) do out[#out + 1] = line end
    out[#out + 1] = R.WorldUI()
    local A = C_AddOns
    if A and A.GetNumAddOns and A.GetAddOnInfo and A.IsAddOnLoaded then
        local names, more = {}, 0
        for i = 1, A.GetNumAddOns() do
            local ok, name = pcall(A.GetAddOnInfo, i)
            if ok and type(name) == "string" and not name:find("^DaylightUI") and A.IsAddOnLoaded(name) then
                if #names < R.REPORT_ADDONS then names[#names + 1] = name else more = more + 1 end
            end
        end
        out[#out + 1] = "Other addons: " .. (#names > 0 and table.concat(names, ", ") or "none")
            .. (more > 0 and string.format(" +%d more", more) or "")
    end
    return out
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    R.loggedInAt = type(GetTime) == "function" and GetTime() or nil
    -- The Nameplates module registers its own, fuller commands when it's on.
    if not DUI.HasCommand("platecheck") then R.RegisterFallback() end
end)

-- With the Nameplates module off: the game's plates as they read, and two
-- steps that need nothing of it.
R.CHECK_DETAIL = 6
R.REPORT_MAX = 3800
R.ADDONS_ROOM = 400
R.LOG_FLOOR = 600 -- about ten log lines, the minute or so before step 1
R.FIX_GAP = 0.5
R.FIX_SETTLE = 1
R.FIX_SHOW_CVARS = { "nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs" }

-- Every kind of plate switched off in the game's settings (its "Show enemy
-- nameplates" key flips the enemy one): there is nothing for platefix to bring
-- back, and players sent reports of exactly that.
function R.AllSwitchedOff()
    for _, name in ipairs(R.FIX_SHOW_CVARS) do
        if R.CVar(name) ~= "0" then return false end
    end
    return true
end
R.SWITCHED_OFF = "Every kind of nameplate is switched off in the game's settings (enemies, friendly players, "
    .. "friendly NPCs)."
R.SWITCHED_OFF_SAID = "platefix: " .. R.SWITCHED_OFF .. " Turn them on in the game's Nameplates options, "
    .. "or press the game's key for enemy nameplates."
R.PLATE_CVARS = { "nameplateMaxDistance", "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowEnemyMinions",
    "nameplateMinScale", "nameplateMaxScale", "nameplateSelectedScale" }
R.OFF = "Nameplates module off"

function R.CheckLines(detail)
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return { "No nameplate API." } end
    local secure = issecure and issecure() or false
    local plates = {}
    for i = 1, 40 do
        local unit = "nameplate" .. i
        local ok, np = pcall(get, unit, secure)
        if ok and type(np) == "table" then plates[#plates + 1] = { unit, np } end
    end
    local out = { string.format("Daylight UI %s. %s. Game plates %d", tostring(DUI.VERSION), R.OFF, #plates) }
    for _, line in ipairs(R.GameLines()) do out[#out + 1] = line end
    local left = detail or R.CHECK_DETAIL
    for _, p in ipairs(plates) do
        if left <= 0 then break end
        left = left - 1
        local okF, forbidden = pcall(function() return p[2]:IsForbidden() end)
        if okF and forbidden == true then
            out[#out + 1] = p[1] .. ": the game keeps this plate from addons (forbidden)"
        else
            for _, line in ipairs((R.PlateHead(p[1], p[2]))) do out[#out + 1] = line end
        end
    end
    if R.AllSwitchedOff() then out[#out + 1] = R.SWITCHED_OFF end
    return out
end

-- Where the game has put each of its plates. Lua can't read a plate's place,
-- and a plate that has gone invisible still reads as shown, so this draws it:
-- a numbered dot pinned to each plate, on a layer of the screen itself. The
-- dots draw even when nothing on the plate does, and a screenshot then shows
-- whether the plates are where their units are, somewhere else, or off the
-- screen. Dots only, because the client refuses a line that ends on a
-- nameplate. Gone again after MARK_SECONDS, except during a /dui platefix
-- run, which holds them to its end.
R.MARK_SECONDS = 20
R.MARK_AFTER = 60 -- seconds they stay once a platefix run is over
R.MARK_SIZE = 10
R.MARK_WHY = 160 -- letters kept of what the game said when it refused a marker
R.marks = {}

local function newMark(layer)
    local m = {}
    m.dot = layer:CreateTexture(nil, "OVERLAY")
    m.dot:SetSize(R.MARK_SIZE, R.MARK_SIZE)
    m.text = DUI.Style.Text(layer, DUI.Style.SIZE.small, "CENTER")
    m.text:SetPoint("BOTTOM", m.dot, "TOP", 0, 2)
    return m
end

local function showMark(m, on)
    m.dot:SetShown(on)
    m.text:SetShown(on)
end

function R.Unmark()
    R.marksOn = false
    if R.markLayer then DUI.Motion.AlphaTo(R.markLayer, 0, DUI.Motion.NORMAL, true) end
end

-- Pins one mark to a game plate. Returns whether the game took it, and what
-- it said if it didn't.
local function pin(m, np)
    return pcall(function()
        m.dot:ClearAllPoints()
        m.dot:SetPoint("CENTER", np, "CENTER", 0, 0)
    end)
end

-- Returns how many plates were marked, how many the game refused a dot on,
-- and what it said the first time. keep: how many
-- seconds they stay (MARK_SECONDS when left out), or true to leave them until
-- R.Release.
function R.Mark(keep)
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return 0 end
    local layer = R.markLayer
    if not layer then
        layer = CreateFrame("Frame", nil, UIParent)
        layer:SetAllPoints(UIParent)
        layer:SetFrameStrata("TOOLTIP")
        layer:Hide()
        R.markLayer = layer
    end
    local secure = issecure and issecure() or false
    local r, g, b = DUI.Style.Accent()
    local n, refused, why = 0, 0, nil
    for i = 1, 40 do
        local ok, np = pcall(get, "nameplate" .. i, secure)
        local okF, closed = pcall(function() return np:IsForbidden() end)
        if ok and type(np) == "table" and okF and closed ~= true then
            local m = R.marks[n + 1] or newMark(layer)
            R.marks[n + 1] = m
            local dotOn, said = pin(m, np)
            if not dotOn then
                refused = refused + 1
                why = why or R.Printable(tostring(said), R.MARK_WHY)
            end
            if dotOn then
                n = n + 1
                m.dot:SetColorTexture(r, g, b, 1)
                m.text:SetText(tostring(i))
                DUI.Style.InkText(m.text, "pop")
            end
            showMark(m, dotOn)
        end
    end
    for i = n + 1, #R.marks do showMark(R.marks[i], false) end
    R.markRun = (R.markRun or 0) + 1
    if n == 0 and keep ~= true then return 0, refused, why end
    R.marksOn = true
    local run = R.markRun
    DUI.Motion.AlphaTo(layer, 1, DUI.Motion.NORMAL)
    if keep ~= true then
        C_Timer.After(keep or R.MARK_SECONDS, function()
            if R.markRun == run then R.Unmark() end
        end)
    end
    return n, refused, why
end

-- Held through a /dui platefix run: the steps rebuild the game's plates, so
-- the dots are pinned again whenever a plate comes or goes.
function R.Hold()
    R.markHeld = true
    return R.Mark(true)
end

function R.Release(seconds)
    R.markHeld = nil
    return R.Mark(seconds)
end

local function remark()
    if not R.markHeld or R.markQueued then return end
    R.markQueued = true
    C_Timer.After(0, function()
        R.markQueued = nil
        if R.markHeld then R.Mark(true) end
    end)
end
DUI.RegisterEvent("NAME_PLATE_UNIT_ADDED", remark)
DUI.RegisterEvent("NAME_PLATE_UNIT_REMOVED", remark)

-- The first step of a platefix run puts the dots up, and its end asks for the
-- screenshot while they're still there. In English like the rest of platefix,
-- since players send these lines in.
function R.HoldSaid()
    return "platefix: each numbered dot is where the game has a nameplate. They stay on until you're done."
end

-- What to add when the game refused a dot: without it, a plate with no dot
-- reads the same as a plate that isn't there.
function R.RefusedSaid(refused, why)
    if (refused or 0) == 0 then return "" end
    return string.format(" The game refused the marker on %d nameplate%s: %s", refused, refused == 1 and "" or "s",
        tostring(why))
end

function R.ReleaseSaid(n, refused, why)
    if n == 0 then
        return "platefix: please take a screenshot now and send it with the report." .. R.RefusedSaid(refused, why)
    end
    return string.format("platefix: please take a screenshot now, with the numbered dots on screen, and send it with "
        .. "the report. The dots stay for %d seconds.", R.MARK_AFTER) .. R.RefusedSaid(refused, why)
end

function R.FixBegin()
    R.FixClear()
    R.Hold()
    DUI.Print(R.HoldSaid())
end

-- A step that finishes later (a timer, plates built over a few frames) holds
-- platefix until it's done, so the next step or a "yes" can't land in the
-- middle of it. FixHold returns the call that lets go. A hold that is never let
-- go (an error on the way) stops counting after FIX_BUSY_MAX seconds.
R.FIX_BUSY_MAX = 5
R.FIX_WAIT = "platefix: the last step is still finishing. Wait a second, then /dui platefix again."
local held, heldSince, heldRound, settled = 0, 0, 0, nil

function R.FixClear() held, heldRound, settled = 0, heldRound + 1, nil end

function R.FixHold()
    if held > 0 and clock() - heldSince >= R.FIX_BUSY_MAX then R.FixClear() end
    held, heldSince = held + 1, clock()
    local round, gone = heldRound, false
    return function()
        if gone or round ~= heldRound then return end
        gone, held = true, math.max(0, held - 1)
        if held == 0 and settled then
            local fn = settled
            settled = nil
            DUI.SafeCall(fn)
        end
    end
end

function R.FixBusy() return held > 0 and clock() - heldSince < R.FIX_BUSY_MAX end

-- What a step can be seen to change: the three show switches, the game's
-- plates and, with the module on, how many of them carry a Daylight UI plate.
-- Counts say a plate is there, not that it was drawn.
function R.Snapshot(ours)
    local s = {}
    for i, name in ipairs(R.FIX_SHOW_CVARS) do
        local v = R.CVar(name)
        s[i] = (v == "0" or v == "1") and v or "?"
    end
    s.game = "?"
    local list = C_NamePlate and C_NamePlate.GetNamePlates
    if type(list) == "function" then
        local ok, plates = pcall(list)
        if ok and type(plates) == "table" and not DUI.IsSecret(plates) then
            local n = 0
            for _ in pairs(plates) do n = n + 1 end
            s.game = n
        end
    end
    s.ours = ours and ours() or nil
    return s
end

local function snapText(s)
    if not s then return "?" end
    return string.format("E%s FP%s FN%s G%s", s[1], s[2], s[3], tostring(s.game))
        .. (s.ours and " O" .. tostring(s.ours) or "")
end

-- Runs step n of a round: notes the snapshot before it, what it did, and the
-- snapshot once it has finished (now, or when its last hold lets go).
function R.RunStep(run, n, step, ours)
    run.trace = run.trace or {}
    local row = { before = R.Snapshot(ours) }
    run.trace[n] = row
    local ok, did = pcall(step)
    if not ok then did = "failed (" .. tostring(did) .. ")" end
    run.did[n] = did
    local function after() row.after = R.Snapshot(ours) end
    if R.FixBusy() then settled = after else after() end
    return did
end

function R.FixYes(run, ours)
    if run then run.atYes = R.Snapshot(ours) end
end

-- One line per step: the counts before and after it, then what it did. The
-- "wait" hints are for the player in chat and are left out of the report.
function R.TraceLines(run)
    if not run then return {} end
    local trace, did = run.trace or {}, run.did or {}
    local out = {}
    if #trace > 0 then
        out[1] = "Each step, before => after (E FP FN show switches, G game plates, O with Daylight UI's), what it did:"
    end
    for n = 1, math.max(#trace, #did) do
        local said = did[n] and tostring(did[n]):gsub(" %(wait[^)]*%)$", "") or "?"
        local row = trace[n]
        if row then
            local was, now = snapText(row.before), snapText(row.after)
            out[#out + 1] = string.format("  %d: %s => %s, %s", n, was, now == was and "same" or now, said)
        else
            out[#out + 1] = string.format("  %d. %s", n, said)
        end
    end
    if run.atYes then out[#out + 1] = "  At yes: " .. snapText(run.atYes) end
    return out
end

function R.FixEnd()
    DUI.Print(R.ReleaseSaid(R.Release(R.MARK_AFTER)))
end

function R.MarkSaid(n, refused, why)
    if n == 0 then
        if (refused or 0) > 0 then return "platecheck: no marker on screen." .. R.RefusedSaid(refused, why) end
        return "platecheck: no game nameplates to mark right now."
    end
    return string.format("platecheck: %d marker%s on screen for %d seconds. Each numbered dot is where the game has "
        .. "that nameplate. Take a screenshot now and send it with these lines.", n, n == 1 and "" or "s",
        R.MARK_SECONDS) .. R.RefusedSaid(refused, why)
end

local function gameDefault(name)
    local fn = C_CVar and C_CVar.GetCVarDefault
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    return ok and type(v) == "string" and v or nil
end

-- The show switches a platefix step turned off, owed back until they read on again.
-- The game saves these settings, so a fight starting in the gap (it refuses them in
-- combat) or a logout in it would otherwise leave the player's plates off for good.
local owed = {}
local function payBack()
    for name in pairs(owed) do
        if R.CVar(name) ~= "0" then
            owed[name] = nil -- on again, by this or by the player
        else
            DUI.SafeCall(SetCVar, name, "1")
            if R.CVar(name) == "1" then owed[name] = nil end
        end
    end
    if next(owed) and InCombatLockdown() then DUI.AfterCombat(payBack, "platefix:switches") end
end
DUI.RegisterEvent("PLAYER_LOGOUT", payBack)

-- Switches the game's plates off for gap seconds so it builds them again, then on.
function R.CycleShowSwitches(gap, after)
    for _, name in ipairs(R.FIX_SHOW_CVARS) do
        if R.CVar(name) == "1" then
            owed[name] = true
            DUI.SafeCall(SetCVar, name, "0")
        end
    end
    C_Timer.After(gap, function()
        payBack()
        after()
    end)
end

R.FIX = {
    -- 1. The game's show switches off and on, so it builds its plates again.
    function()
        R.CycleShowSwitches(R.FIX_GAP, R.FixHold())
        return "the game's plates switched off and on (" .. R.OFF .. ")"
    end,
    -- 2. The plate settings Daylight UI can change, back to the game's defaults.
    function()
        local done = 0
        for _, name in ipairs(R.PLATE_CVARS) do
            local v = gameDefault(name)
            if v and DUI.SafeCall(SetCVar, name, v) then done = done + 1 end
        end
        return string.format("%d plate settings back to the game's defaults", done)
    end,
    -- 3. The game's own switch for nameplates and speech bubbles back on.
    function() return R.InWorldBack() end,
}
-- 4 on: the layer plates are drawn on.
for _, step in ipairs(R.WORLD_STEPS) do R.FIX[#R.FIX + 1] = step end

-- Keep the plate as it was when the player saw the problem, then the outcome of
-- every step. A busy event log or a long addon list can fill the copy box.
function R.BuildFixReport(title, run, world)
    -- The setup and Daylight UI state lines go before the log, and the addon
    -- list goes last: a busy log or a long list used to push the state lines
    -- past the end, and they were cut from nearly every report.
    local addons
    for _, line in ipairs(world) do
        if line:find("^Other addons:") then addons = line end
    end
    local function headText(short)
        local out = { title }
        for _, line in ipairs(R.TraceLines(run)) do out[#out + 1] = line end
        out[#out + 1] = "Before step 1:"
        local left = 0
        for _, line in ipairs(run.before) do
            if short and line:find("^  ") then left = left + 1 else out[#out + 1] = line end
        end
        if left > 0 then out[#out + 1] = string.format("  (%d lines of plate detail left out for room)", left) end
        for _, line in ipairs(world) do
            if line ~= addons then out[#out + 1] = line end
        end
        out[#out + 1] = "What happened before step 1 (most recent first, minutes:seconds before it):"
        return R.Printable(table.concat(out, "\n"))
    end
    local log = run.log or {}
    local omitted = "\n[Further report lines omitted]"
    local logWants = 0
    for _, line in ipairs(log) do logWants = logWants + #line + 1 end
    local floor = math.min(logWants, R.LOG_FLOOR)
    -- The last moments before step 1 are what a report can't do without.
    -- Short of room, a plate's detail lines go first (they read the same on a
    -- healthy plate as on a missing one), unless one of them looks wrong.
    local head = headText(false)
    local wrong = false
    for _, line in ipairs(run.before) do
        if line:find("^LOOKS WRONG") then wrong = true end
    end
    if not wrong and #head + floor + #omitted > R.REPORT_MAX then head = headText(true) end
    if #head > R.REPORT_MAX then
        local prefix = head:sub(1, R.REPORT_MAX - #omitted + 1)
        return prefix:match("^(.*)\n") .. omitted
    end
    -- The log keeps room for a short addon list, then takes what it needs,
    -- but never less than its floor while the box has room for it.
    local room = R.REPORT_MAX - #omitted - (addons and R.ADDONS_ROOM or 0)
    room = math.min(math.max(room, #head + floor), R.REPORT_MAX - #omitted)
    local lines, size, cut = {}, #head, false
    for i = #log, 1, -1 do
        local line = "\n" .. R.Printable(log[i])
        if size + #line > room then cut = true break end
        lines[#lines + 1] = line
        size = size + #line
    end
    local text = head .. table.concat(lines)
    if addons then
        local line = "\n\n" .. R.Printable(addons)
        local left = R.REPORT_MAX - #text - #omitted
        if #line > left then
            line, cut = left > 0 and line:sub(1, left):match("^(.*),") or "", true
        end
        text = text .. line
    end
    return cut and text .. omitted or text
end

local fixStep, fixRun

function R.FixReport(step)
    local run = fixRun or { did = {}, before = {} }
    local title = string.format("Daylight UI %s platefix (%s): %s", tostring(DUI.VERSION), R.OFF,
        step and string.format("step %d brought them back", step) or "no step brought them back")
    return R.BuildFixReport(title, run, run.world or R.World())
end

local function fixDone(step)
    local text = R.FixReport(step)
    fixStep, fixRun = nil, nil
    DUI.Profiles.ShowText(L["Nameplate report"], L["Ctrl+C to copy, then paste it in a bug report on the Daylight UI Discord. "
        .. "After that, /reload."], text)
    for line in string.gmatch(text, "[^\n]+") do DUI.Print(line) end
    R.FixEnd()
end

function R.Fix()
    if R.FixBusy() then return R.FIX_WAIT end
    if InCombatLockdown() then return "platefix: leave combat first, then /dui platefix again." end
    local n = (fixStep or 0) + 1
    if n == 1 and R.AllSwitchedOff() then return R.SWITCHED_OFF_SAID end
    if n > #R.FIX then
        fixDone(nil)
        return "platefix: that was every step and none brought them back. Copy the text in the box and send it to the "
            .. "Daylight UI team, then /reload."
    end
    if n == 1 then
        fixRun = { did = {}, before = R.CheckLines(1), world = R.World(), log = R.LogLines() }
        R.FixBegin()
    end
    fixStep = n
    local did = R.RunStep(fixRun, n, R.FIX[n])
    return string.format("platefix %d/%d: %s. Are the nameplates back? Yes: /dui platefix yes. "
        .. "No: /dui platefix again for the next step.", n, #R.FIX, did)
end

function R.RegisterFallback()
    DUI.RegisterCommand("platecheck", function()
        for _, line in ipairs(R.CheckLines()) do DUI.Print(line) end
        for _, line in ipairs(R.Daylight()) do DUI.Print(line) end
        DUI.Print(R.MarkSaid(R.Mark()))
    end, function() return L["/dui platecheck - run while a nameplate is missing, and send us what it prints"] end)
    DUI.RegisterCommand("platefix", function(rest)
        if string.lower(rest or "") ~= "yes" then return DUI.Print(R.Fix()) end
        if not fixStep then return DUI.Print(L["Run /dui platefix first, while the nameplates are invisible."]) end
        if R.FixBusy() then return DUI.Print(R.FIX_WAIT) end
        R.FixYes(fixRun)
        fixDone(fixStep)
        DUI.Print(L["Copy the text in the box and send it to the Daylight UI team, then /reload."])
    end, function() return L["/dui platefix - run while nameplates are invisible, one step each time, and say which step brought them back"] end)
end
