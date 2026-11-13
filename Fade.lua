-- One fade engine for the whole UI. Every area that fades (a unit frame, a
-- bar, the buffs, the chat, the info panel, the tracker) registers here once,
-- and from then on only the engine sets its alpha. The same choices apply
-- everywhere (when to fade, to what opacity, back on mouseover, after what
-- delay), plus its own opacity while shown and one motion. Alpha only:
-- nothing is shown, hidden or moved, so protected frames are fine in combat.
--
-- Two parts: a ticker decides where each area should be, and a per-frame
-- driver eases it there, running only while something is moving. Each area's
-- alpha is tracked here in Lua and never read back with GetAlpha, so a secret
-- value or someone else's SetAlpha can't confuse it.
--
-- General's "Fades only in the open world" (fadeOpenWorldOnly) shows every
-- area in dungeons, raids, battlegrounds and arenas, updating on zone change.
--
-- Float (an area's Visible pick "Only when something changes", mode "float"):
-- hidden out of combat, shown in combat, and shown briefly after a change it
-- reports (Fade.Wake: a buff gained or lost, a health change, quest
-- progress). General > Fade's "Float everything" picks it for every area at
-- once.

local _, DUI = ...

local Fade = {}
DUI.Fade = Fade

Fade.TICK = 0.1 -- how often goals are checked
Fade.OUT = 0.6 -- seconds to fade all the way out
Fade.IN = 0.35 -- and to come all the way back
Fade.MIN_SHARE = 0.25 -- a short hop still takes this share of the full time
Fade.MAX_STEP = 0.1 -- a longer frame is a hitch (the first after a loading screen) and counts as this
Fade.INTRO = 1.3 -- the login and /reload fade-in
Fade.INTRO_WAIT = 0.3 -- wait after the loading screen goes, so it's seen
Fade.STEADY_DT = 1 / 25 -- a frame longer than this means the world is still streaming in
Fade.STEADY = 0.4 -- the fade-in waits for this many seconds of steady frames in a row
Fade.STEADY_CAP = 3 -- and starts anyway this long after the loading screen
Fade.INTRO_FALLBACK = 8 -- after PLAYER_ENTERING_WORLD it starts anyway
Fade.INTRO_SAFETY = 20 -- and after PLAYER_LOGIN, if the world never arrives
Fade.DEFAULT = { mode = "never", alpha = 0, mouseover = true, target = false, targetEnemy = false, delay = 4.5, opacity = 1 }
Fade.REPAINT = 1 -- a faded area at rest is repainted this often (in case of someone else's SetAlpha)

Fade.HUSH_OUT = 2.5 -- a hush eases its areas out this slowly (settling in by the fire)
Fade.WAKE = 1 -- Float: a change shows its area at least this long (even with a delay of 0)
Fade.FIGHT_OUT = 1.5 -- "In combat": dims this slowly as a fight starts (all the way down)
Fade.FIGHT_IN = 0.8 -- and comes back this calmly once it ends

local entries = {} -- key -> area
local hushes = {} -- name -> key prefixes (Fade.Hush)
local order = {} -- keys in registration order (stable ticks)
local ticker
local loginPhase = true -- until the fade-in starts, areas start at their goal
local loginAt, worldAt -- when PLAYER_LOGIN / PLAYER_ENTERING_WORLD fired
local tick = 0 -- check counter; an area's frames are read at most once per check

Fade.fighting = false
Fade.editMode = false
Fade.inInstance = false -- in a dungeon, raid, battleground or arena (from the zone events)
Fade.INSTANCE_KINDS = { party = true, raid = true, pvp = true, arena = true }
Fade.intro = true -- areas registering now start at 0 (if the fade-in is on)

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Is the mouse over f? Secure frames (the buffs header) can return a secret
-- boolean from IsMouseOver. Then measure the cursor ourselves, and if even
-- the edges are secret, treat it as not over.
function Fade.Over(f)
    local ok, over = pcall(f.IsMouseOver, f)
    if ok and not isSecret(over) then return over == true end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    for _, v in ipairs({ l, r, t, b }) do
        if type(v) ~= "number" or isSecret(v) then return false end
    end
    local x, y = GetCursorPosition()
    local s = f:GetEffectiveScale()
    if type(x) ~= "number" or type(s) ~= "number" or isSecret(s) then return false end
    x, y = x / s, y / s
    return x >= l and x <= r and y >= b and y <= t
end

local function motionOn() return not (DUI.Motion and not DUI.Motion.On()) end

-- The fade-in runs when General asks for it and motion is on.
local function introWanted()
    local g = DUI.DB and DUI.DB.General and DUI.DB.General()
    return g ~= nil and g.fadeIn == true and motionOn()
end

local function readOpacity(s)
    local o = type(s) == "table" and s.opacity
    if type(o) ~= "number" then return Fade.DEFAULT.opacity end
    return math.max(0, math.min(1, o))
end

-- Float (mode = "float"): hidden out of combat, shown in combat and briefly
-- after a change it reports (Fade.Wake). Faded opacity, mouseover, target and
-- delay stay the area's own. An area registered with float = false has no
-- such option (target, focus, chat come and go their own way).
local function floats(e, s)
    return e.float ~= false and type(s) == "table" and s.mode == "float"
end

-- An area's choices, validated: a bad or missing value falls back. opacity is
-- where it sits while shown, and the faded alpha never goes above it. Float
-- stands in for the mode as out of combat.
function Fade.Read(e)
    local s = DUI:Get(e.scope, e.path)
    local d = Fade.DEFAULT
    local mode, alpha, mouseover, delay, opacity, target
    if type(s) ~= "table" then
        mode, alpha, mouseover, delay, opacity, target = d.mode, d.alpha, d.mouseover, d.delay, d.opacity, d.target
    else
        mode = (s.mode == "ooc" or s.mode == "always" or s.mode == "combat") and s.mode or "never"
        opacity = readOpacity(s)
        alpha = type(s.alpha) == "number" and math.max(0, math.min(opacity, s.alpha)) or math.min(opacity, d.alpha)
        delay = type(s.delay) == "number" and math.max(0, s.delay) or d.delay
        mouseover = s.mouseover ~= false
        -- Show with a target: true, or "enemy" when only an attackable target counts.
        target = s.target == true and (s.targetEnemy == true and "enemy" or true)
    end
    if floats(e, s) then mode = "ooc" end
    return mode, alpha, mouseover, delay, opacity, target
end

-- Do you have a target? With enemy, only one you can attack (a quest giver or
-- vendor doesn't count). A secret answer counts as no.
function Fade.HasTarget(enemy)
    local ok, yes = pcall(UnitExists, "target")
    if not (ok and not isSecret(yes) and yes == true) then return false end
    if not enemy then return true end
    if type(UnitCanAttack) ~= "function" then return false end
    local okA, can = pcall(UnitCanAttack, "player", "target")
    return okA and not isSecret(can) and can == true
end

-- The opacity of the area whose settings live at scope/path.
function Fade.Opacity(scope, path)
    return readOpacity(DUI:Get(scope, path))
end

-- Inside an instance with "Fades only in the open world" on, every area shows
-- as if its fade were Never (fights there need everything).
function Fade.Aside()
    if not Fade.inInstance then return false end
    local g = DUI.DB and DUI.DB.General and DUI.DB.General()
    return g ~= nil and g.fadeOpenWorldOnly == true
end

-- Where the player is, checked at login and after each zone change.
function Fade.CheckInstance()
    local inside = false
    if type(IsInInstance) == "function" then
        local ok, yes, kind = pcall(IsInInstance)
        if ok and not isSecret(yes) and not isSecret(kind) then
            inside = yes == true and Fade.INSTANCE_KINDS[kind] == true
        end
    end
    local changed = inside ~= Fade.inInstance
    Fade.inInstance = inside
    return changed
end

local function forced(e)
    if DUI.Movers and DUI.Movers.unlocked == true then return true end
    if Fade.editMode or DUI.testMode == true then return true end
    local P = DUI.OptionsPanel
    if P == nil or not P.IsShown() then return false end
    local current = P.Current()
    if current == Fade.HUB_PAGE then return Fade.HubShows(e) end
    if e.page == nil then return false end
    -- A single page id, or a list (an area shown on several pages).
    if type(e.page) == "table" then
        for _, id in ipairs(e.page) do
            if id == current then return true end
        end
        return false
    end
    return current == e.page
end

-- An area's frames, read at most once per check and only when needed (mouse,
-- movement, or resting faded). An area shown at full reads nothing.
local function readFrames(e)
    local ok, list = pcall(e.frames)
    e.list = ok and type(list) == "table" and list or {}
    e.listAt = tick
end

local function listOf(e)
    if e.listAt ~= tick then readFrames(e) end
    return e.list
end

local function overAny(list)
    for _, f in ipairs(list) do
        local shown = f:IsShown()
        if (isSecret(shown) or shown) and Fade.Over(f) then return true end
    end
    return false
end

-- Is the mouse on the area? An area whose frames can't answer (the client's
-- aura containers, a list hanging below its holder) provides its own `over`.
local function mouseOn(e)
    return (e.over and e.over() == true) or overAny(listOf(e))
end

-- Is the area in a hush (its key starts with one of the hush's prefixes)?
local function hushed(e)
    if next(hushes) == nil then return false end
    for _, prefixes in pairs(hushes) do
        for _, p in ipairs(prefixes) do
            if e.key:sub(1, #p) == p then return true end
        end
    end
    return false
end

-- Where an area should be now. Also stamps when it was last wanted.
function Fade.Goal(e, now)
    -- Leaving (Fade.Leave): invisible no matter what else asks.
    if e.gone then return 0 end
    local mode, alpha, mouseover, delay, opacity, target = Fade.Read(e)
    -- Stepped aside: shown, and back in the world the delay runs first.
    if Fade.Aside() then e.lastNear = now; return opacity end
    if e.peeking then
        if Fade.Held() then return mode == "never" and opacity or alpha end
        e.peeking = nil
    end
    if forced(e) then e.lastNear = now; return opacity end
    -- Hushed (sitting by a campfire): hidden out of combat, back on mouseover.
    -- The second return asks for the slow ease out.
    if hushed(e) and not (Fade.fighting or InCombatLockdown()) then
        if (e.wake and e.wake() == true) or mouseOn(e) then
            e.lastNear = now
            return opacity
        end
        return 0, Fade.HUSH_OUT
    end
    -- Never fades (the default) and nothing caps it: shown, without checking the
    -- mouse or wake (this runs for every area ten times a second).
    if mode == "never" and not e.cap then return opacity end
    if (e.wake and e.wake() == true) or (mouseover and mouseOn(e))
       or (target and Fade.HasTarget(target == "enemy")) then
        e.lastNear = now
        e.peace = nil
        e.fought = nil
        return opacity
    end
    local goal, pace = opacity, nil
    local fighting = Fade.fighting or InCombatLockdown()
    if mode == "combat" and not fighting and e.fought and now - (Fade.peaceAt or 0) < delay then
        -- "In combat", a fight just ended: stay dimmed until the delay is up.
        goal, pace = alpha, Fade.FIGHT_OUT
    elseif mode == "combat" and not fighting then
        -- "In combat", between fights: shown, easing back calmly after one.
        e.lastNear = now
        e.peace = true
        e.fought = nil
        pace = Fade.FIGHT_IN
    elseif mode == "combat" and e.peace then
        -- A fight just started: dim at once, slowly. The delay is for the mouse
        -- leaving or a target cleared mid-fight.
        goal, pace = alpha, Fade.FIGHT_OUT
        e.fought = true
    elseif mode == "ooc" and fighting then
        e.lastNear = now
    elseif mode ~= "never" and now - e.lastNear >= delay then
        goal = alpha
        if mode == "combat" then e.fought = true end
    end
    if e.cap then
        local c = e.cap()
        if type(c) == "number" and c < goal then goal = c end
    end
    return goal, pace
end

-- Fading as one picture. The client fades a frame by fading each piece, so the
-- world and the pieces underneath show through every layer (a bar inside a
-- portrait ring). A frame drawn to its own buffer fades as a whole. Per the
-- game's rule (Frame:SetIsFrameBuffer) its layers must be flattened first or
-- it may draw nothing. Requested per reason (why) and on while anyone wants
-- it. It only changes out of combat (bars and tiles are protected), so an
-- area that can fade keeps it on even at full, ready for a fight.
local wholeDue = {}

local function setWhole(f, on)
    local flat, buffer = f.SetFlattensRenderLayers, f.SetIsFrameBuffer
    if type(flat) ~= "function" or type(buffer) ~= "function" then return end
    local ok
    if on then ok = pcall(flat, f, true) and pcall(buffer, f, true)
    else ok = pcall(buffer, f, false) and pcall(flat, f, false) end
    if ok then f.fadeWhole = on end
end

local function wholeNow()
    for f in pairs(wholeDue) do
        wholeDue[f] = nil
        local on = next(f.fadeWhy) ~= nil
        if (f.fadeWhole == true) ~= on then setWhole(f, on) end
    end
end

function Fade.Whole(f, why, on)
    local whys = f.fadeWhy
    if not whys then
        if not on then return end
        whys = {}
        f.fadeWhy = whys
    end
    if whys[why] == (on or nil) then return end
    whys[why] = on or nil
    wholeDue[f] = true
    DUI.AfterCombat(wholeNow, "fade:whole")
end

-- Paints every frame of the area and records which ones were painted.
local function paint(e)
    if e.held then return end
    local seen = e.seen or {}
    e.seen = seen
    local n = 0
    local whole = e.whole and (e.now < 1 or Fade.Read(e) ~= "never")
    for _, f in ipairs(e.list) do
        if e.whole then Fade.Whole(f, "fade", whole) end
        if e.paint then e.paint(f, e.now) else f:SetAlpha(e.now) end
        n = n + 1
        seen[n] = f
    end
    for i = n + 1, #seen do seen[i] = nil end
    e.paintedAt = GetTime()
end

-- A frame joined (or left) since the last paint: a raid member, a window.
local function newcomers(e)
    local list, seen = e.list, e.seen
    if not seen then return true end
    local n = 0
    for i, f in ipairs(list) do
        if seen[i] ~= f then return true end
        n = i
    end
    return seen[n + 1] ~= nil
end

-- Starts an ease from where it is to goal (dur given, or based on distance).
local function ease(t) return t * t * (3 - 2 * t) end
-- Ease-out: moves from the first frame and settles softly. Used for the long
-- paced fades (a fight's, a hush's), where smoothstep read as a wait then a rush.
local function easeOut(t) return math.sin(t * math.pi / 2) end

local function aim(e, goal, dur, curve)
    if e.to == goal and not dur then return end
    e.from, e.to, e.t = e.now, goal, 0
    local full = goal > e.now and Fade.IN or Fade.OUT
    e.dur = dur or full * math.max(Fade.MIN_SHARE, math.abs(goal - e.now))
    e.curve = curve or ease
end

-- Advances every moving area by one frame. Returns false once all have arrived.
function Fade.Animate(dt)
    dt = math.min(dt, Fade.MAX_STEP)
    local moving = false
    for _, key in ipairs(order) do
        local e = entries[key]
        if e.now ~= e.to then
            e.t = e.t + dt
            -- t below 0 means still waiting for the login ripple to reach it.
            local p = e.dur > 0 and math.max(0, math.min(1, e.t / e.dur)) or 1
            e.now = p >= 1 and e.to or e.from + (e.to - e.from) * (e.curve or ease)(p)
            paint(e)
            if e.now ~= e.to then moving = true end
        end
    end
    return moving
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
    if not Fade.Animate(dt) then self:Hide() end
end)
Fade.driver = driver

-- Updates every area's goal and starts the driver if any has to move.
function Fade.Step()
    local now = GetTime()
    -- The fade-in waits for the loading screen. These start it if that never
    -- reports being gone.
    if loginPhase and ((worldAt and now - worldAt >= Fade.INTRO_FALLBACK)
                       or (loginAt and now - loginAt >= Fade.INTRO_SAFETY)) then
        Fade.StartIntro()
    end
    tick = tick + 1
    local moving, snap = false, not motionOn()
    for _, key in ipairs(order) do
        local e = entries[key]
        local jumped = false
        if not (Fade.intro and loginPhase and e.introStart) then
            local goal, pace = Fade.Goal(e, now)
            if snap then
                jumped = e.now ~= goal or e.to ~= goal
                e.now, e.from, e.to = goal, goal, goal
            elseif pace and e.to ~= goal then
                aim(e, goal, pace * math.max(Fade.MIN_SHARE, math.abs(goal - e.now)), easeOut)
            else
                aim(e, goal)
            end
        end
        if e.now ~= e.to then
            moving = true
            listOf(e)
        elseif jumped then
            listOf(e)
            paint(e)
        elseif e.now ~= 1 then
            -- Resting below full: repainted for a frame that joined, and every so often in
            -- case of someone else's SetAlpha (per-tick repaints cost about 40 range
            -- checks per tick on a faded raid).
            listOf(e)
            if newcomers(e) or now - (e.paintedAt or 0) >= Fade.REPAINT then paint(e) end
        end
    end
    if moving then driver:Show() end
end

-- def: { key, scope, path, frames, page? (an id or a list), cap?, wake?, over? (mouse on it, when frames can't say), paint?, float? (false: no "Only when something changes" option), whole? (true: fades as one picture, Fade.Whole; only for Daylight UI frames with overlapping pieces) }
function Fade.Register(def)
    assert(type(def.key) == "string" and type(def.frames) == "function", "Fade.Register: key and frames")
    assert(def.float == nil or def.float == false, "Fade.Register: float")
    if Fade.intro and loginPhase and not introWanted() then Fade.intro = false end
    if loginPhase then Fade.CheckInstance() end -- before the zone events, so it starts where it belongs
    local old = entries[def.key]
    local e = { key = def.key, scope = def.scope, path = def.path, frames = def.frames, page = def.page,
                cap = def.cap, wake = def.wake, over = def.over, paint = def.paint, float = def.float, whole = def.whole }
    readFrames(e)
    local now = GetTime()
    if old then
        e.now, e.from, e.to, e.t, e.dur = old.now, old.from, old.to, old.t, old.dur
        e.lastNear, e.held, e.introStart = old.lastNear, old.held, old.introStart
    else
        order[#order + 1] = def.key
        e.t, e.dur = 0, 0
        e.lastNear = now
        if loginPhase and Fade.intro then
            e.now, e.from, e.to, e.introStart = 0, 0, 0, true
        elseif loginPhase then
            -- Login without the fade-in: start where it belongs (bars set to fade start
            -- faded instead of shown for the delay first).
            local _, _, _, delay = Fade.Read(e)
            e.lastNear = now - delay - 1
            local goal = Fade.Goal(e, now)
            e.now, e.from, e.to = goal, goal, goal
        else
            e.now, e.from, e.to = 1, 1, 1
        end
    end
    entries[def.key] = e
    if e.now ~= 1 then paint(e) end
    if not ticker then ticker = C_Timer.NewTicker(Fade.TICK, Fade.Step) end
end

-- An area that just appeared (the target frame, after having no target):
-- from invisible to where it belongs over dur. Nothing with motion off, during
-- the login fade-in, or while held.
function Fade.Arrive(key, dur)
    local e = entries[key]
    if not e or e.held or loginPhase or not motionOn() then return end
    listOf(e)
    e.now = 0
    aim(e, Fade.Goal(e, GetTime()), dur)
    paint(e)
    driver:Show()
end

-- An area that's leaving (the target frame, its unit gone): to invisible over
-- dur, and kept there until Fade.Back. Instant with motion off.
function Fade.Leave(key, dur)
    local e = entries[key]
    if not e then return end
    e.gone = true
    if e.held or loginPhase then return end
    listOf(e)
    if motionOn() then
        aim(e, 0, dur)
        driver:Show()
    else
        e.now, e.from, e.to = 0, 0, 0
        paint(e)
    end
end

-- It's back (or hidden for good), so its goal is its own again. Eased there
-- now rather than at the next check.
function Fade.Back(key)
    local e = entries[key]
    if not (e and e.gone) then return end
    e.gone = nil
    if e.held or loginPhase then return end
    listOf(e)
    local goal = Fade.Goal(e, GetTime())
    if motionOn() then
        aim(e, goal)
        driver:Show()
    else
        e.now, e.from, e.to = goal, goal, goal
        paint(e)
    end
end

-- Float: something the area shows changed (a buff gained or lost, your health).
-- It comes back and floats away its delay after the last change (at least
-- Fade.WAKE). Just a timestamp, since health can fire many times a second; the
-- next check eases it in.
function Fade.Wake(key)
    local e = entries[key]
    if e == nil then return end
    local s = DUI:Get(e.scope, e.path)
    if not floats(e, s) then return end
    local delay = type(s.delay) == "number" and math.max(0, s.delay) or Fade.DEFAULT.delay
    e.lastNear = math.max(e.lastNear or 0, GetTime() + math.max(0, Fade.WAKE - delay))
end

-- Does the area float (Visible: Only when something changes)? A module skips
-- its watching when none of its areas do.
function Fade.Floats(key)
    local e = entries[key]
    return e ~= nil and floats(e, DUI:Get(e.scope, e.path))
end

-- Float everything (General > Fade): on while every area that can float does.
-- Turning it on picks float for all of them; off puts each floating one back
-- to its default.
local function floatable(e) return e.float ~= false and type(e.path) == "string" end

function Fade.AllFloat()
    local any = false
    for _, key in ipairs(order) do
        local e = entries[key]
        if floatable(e) then
            any = true
            if DUI:Get(e.scope, e.path .. ".mode") ~= "float" then return false end
        end
    end
    return any
end

local function defaultMode(e)
    local defaults
    if e.scope == "general" then defaults = DUI.DB.GENERAL_DEFAULTS
    else
        local mod = DUI:GetModule(e.scope)
        defaults = mod and mod.defaults
    end
    local m = type(defaults) == "table" and DUI.DB.GetPath(defaults, e.path .. ".mode")
    if type(m) ~= "string" or m == "float" then return Fade.DEFAULT.mode end
    return m
end

function Fade.SetAllFloat(on)
    for _, key in ipairs(order) do
        local e = entries[key]
        if floatable(e) then
            if on then DUI:Set(e.scope, e.path .. ".mode", "float")
            elseif DUI:Get(e.scope, e.path .. ".mode") == "float" then DUI:Set(e.scope, e.path .. ".mode", defaultMode(e)) end
        end
    end
end

-- A module takes over the alpha for a while (the buffs Edit Mode preview).
function Fade.Hold(key, on)
    local e = entries[key]
    if not e then return end
    e.held = on and true or nil
    -- Repaint with its frames re-read, since the area's list may have changed
    -- meanwhile (the chat's style switched).
    if not on then readFrames(e); paint(e) end
end

-- A feature quiets some areas for a while (the campfire hides bars and unit
-- frames while you sit). Every area whose key starts with one of prefixes
-- slowly eases to 0 out of combat. The mouse, a fight, unlock, test mode and
-- the area's options page still show it.
function Fade.Hush(name, prefixes)
    hushes[name] = prefixes
end

-- Lifts a hush: the areas come back at normal speed, or at once with snap.
function Fade.Unhush(name, snap)
    if hushes[name] == nil then return end
    hushes[name] = nil
    if not snap then return end
    local now = GetTime()
    for _, key in ipairs(order) do
        local e = entries[key]
        local goal = Fade.Goal(e, now)
        if e.now ~= goal or e.to ~= goal then
            e.now, e.from, e.to = goal, goal, goal
            listOf(e)
            paint(e)
        end
    end
end

function Fade.Hushed() return next(hushes) ~= nil end

-- The game draws the minimap's dots (your arrow, quest marks, tracking,
-- party) at full strength regardless of its parents' alpha. So whoever fades
-- the map all the way out sets the map's own alpha to 0 meanwhile: the info
-- panel's fade (the login fade-in too), the AFK screen and the NPC scene
-- (UIParent's alpha). Never hide it: hidden and shown again, the game's map
-- came back blank (at every login and after each NPC talk in town). Its own
-- alpha is restored to what it was once nobody holds it.
local mapAway, mapAlphaBefore = {}, nil
function Fade.MapAway(name, on)
    on = on == true
    if (mapAway[name] == true) == on then return end
    local map = _G.Minimap
    if type(map) ~= "table" then return end
    local before = next(mapAway) ~= nil
    mapAway[name] = on or nil
    local now = next(mapAway) ~= nil
    if now and not before then
        local a = map:GetAlpha()
        mapAlphaBefore = type(a) == "number" and a or 1
        map:SetAlpha(0)
    elseif before and not now then
        map:SetAlpha(mapAlphaBefore or 1)
        mapAlphaBefore = nil
    end
end

-- Returns now, goal, fadedAlpha, opacity (nil for an unknown key).
function Fade.State(key)
    local e = entries[key]
    if not e then return nil end
    local _, alpha, _, _, opacity = Fade.Read(e)
    return e.now, e.to, alpha, opacity
end

local function plain(v) return type(v) == "number" and not isSecret(v) end

-- A frame's box in UIParent units, or nil if any part of it is unknown.
local function boxOf(f)
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    local es, us = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (plain(l) and plain(b) and plain(w) and plain(h) and plain(es) and plain(us)) or us <= 0 then return nil end
    local k = es / us
    return { l = l * k, b = b * k, w = w * k, h = h * k }
end

-- The ripple (with the reveal): the UI comes in from the middle of the screen,
-- where you stand, outward. An area starts its fade-in, and an outline its
-- trace, later the farther it sits from the middle, up to REVEAL_SPREAD at a
-- corner. Anything joining the reveal (the "LoginReveal" callback) times its
-- part by it. Nil when the frame isn't laid out.
function Fade.RippleDelay(f)
    local ok, box = pcall(boxOf, f)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not (ok and box and plain(w) and plain(h)) or w <= 0 or h <= 0 then return nil end
    local dx, dy = box.l + box.w / 2 - w / 2, box.b + box.h / 2 - h / 2
    local far = math.sqrt(dx * dx + dy * dy) / math.sqrt(w * w + h * h) * 2
    return Fade.REVEAL_SPREAD * math.min(1, far)
end

-- An area's delay: its nearest shown frame's (at once if none is laid out).
local function areaDelay(e)
    local best
    for _, f in ipairs(e.list or {}) do
        local ok, shown = pcall(f.IsShown, f)
        local d = ok and shown == true and Fade.RippleDelay(f)
        if d and (not best or d < best) then best = d end
    end
    return best or 0
end

-- Login: everything that came in at 0 glides to where it belongs.
function Fade.StartIntro()
    if not loginPhase then return end
    loginPhase = false
    if not Fade.intro then return end
    Fade.intro = false
    local now = GetTime()
    -- With the reveal coming, an area set to fade shows for it first, then fades
    -- as usual. Without it, it starts faded.
    local ripple = Fade.RevealComing()
    local hold = ripple and Fade.REVEAL_SPREAD + 2 * Fade.REVEAL_TIME or nil
    for _, key in ipairs(order) do
        local e = entries[key]
        readFrames(e)
        local _, _, _, delay = Fade.Read(e)
        e.lastNear = hold and now + hold - delay or now - delay - 1
        e.introStart = nil
        aim(e, Fade.Goal(e, now), Fade.INTRO)
        if ripple then e.t = -areaDelay(e) end
    end
    driver:Show()
    Fade.Reveal()
end

-- For tests and anything that wants it finished: jump to the end.
function Fade.SkipIntro()
    Fade.StartIntro()
    for _, key in ipairs(order) do
        local e = entries[key]
        e.now, e.from, e.t = e.to, e.to, e.dur
        paint(e)
    end
    driver:Hide()
end

-- The login reveal. As the fade-in starts on a real login, the UI ripples out
-- from the middle of the screen (Fade.RippleDelay). The main frames' outlines
-- draw themselves in the accent as it reaches them (like the buttons' hover
-- trace, W.Trace), the fade-in brings their fill up underneath, each traced
-- edge settles into its own border, and then a warm light sweeps across them
-- left to right. Modules join through the "LoginReveal" callback (action
-- buttons light up in a wave, unit frames arrive, quests slide in), and a
-- welcome line shows. Runs on login and /reload, not on zone changes or in
-- combat (fight info comes first). The traces are our own frames on UIParent
-- laid over the shells, never anchored to them, so no protected frame is
-- touched and everything works from the first moment.

Fade.REVEAL_MAX = 14 -- max outlines (the biggest frames)
Fade.REVEAL_SPREAD = 0.65 -- the ripple: a frame in a screen corner starts this long after one in the middle
Fade.REVEAL_TIME = 0.52 -- each trace, then its settle, at the login's own pace like INTRO (SLOW + 30%)
Fade.REVEAL_MIN_W = 40 -- smaller shells (buttons, icons) don't trace
Fade.REVEAL_MIN_H = 14
Fade.REVEAL_SKIP = 0.05 -- nor a frame whose area stays faded below this

Fade.SWEEP = { spread = 0.4, band = 0.4, alpha = 0.45 } -- the light after the traces: left to right across the screen within spread seconds
Fade.WELCOME = { size = 26, y = 150, rise = 12, hold = 2.4 } -- the welcome line: display art, above the middle

local revealDue = false -- the UI just loaded, so the first world entry reveals
local overlays = {} -- reused, one per outline
Fade.revealOverlays = overlays

local function inside(a, p)
    return a.l >= p.l - 1 and a.b >= p.b - 1 and a.l + a.w <= p.l + p.w + 1 and a.b + a.h <= p.b + p.h + 1
end

-- How transparent a frame will be once the intro is done: its own alpha and
-- its parents', with an area's goal in place of the frame that area owns
-- (its alpha is still coming up). Shown at alpha 0 (the Cooldown Manager's
-- empty buff slots) or secret means 0, nothing to trace.
local function alphaOf(f, goals)
    local a = 1
    for _ = 1, 10 do
        if type(f) ~= "table" or f == UIParent then return a end
        if goals[f] then return a * goals[f] end
        local okA, own = pcall(f.GetAlpha, f)
        if not (okA and plain(own)) then return 0 end
        a = a * own
        local ok, parent = pcall(f.GetParent, f)
        f = ok and parent or nil
    end
    return a
end

-- Frames traced even though they draw no border of their own (chat with its
-- background off, the quest list without its box). Each source returns the
-- frame to outline (nil for none right now) and how far outside it (pad, in
-- UIParent units). Its outline just fades since there's nothing to settle into.
local extras = {}
function Fade.RevealAlso(source) extras[#extras + 1] = source end

-- The visible outlined shells worth tracing: biggest first, none inside
-- another picked one, at most REVEAL_MAX, then nearest the middle first
-- (box.delay is when its trace starts, from the ripple).
function Fade.RevealPicks()
    local goals = {}
    for _, key in ipairs(order) do
        local e = entries[key]
        for _, f in ipairs(e.list or {}) do goals[f] = math.max(goals[f] or 0, e.to or 1) end
    end
    local found = {}
    for s in DUI.Style.Shells() do
        local frame = s:GetParent()
        local o = s.opts or {}
        local ok, shown = pcall(s.IsVisible, s)
        if ok and shown == true and frame and not o.window and not o.noBorder and o.borderPx ~= 0
           and alphaOf(frame, goals) >= Fade.REVEAL_SKIP then
            local box = boxOf(frame)
            if box and box.w >= Fade.REVEAL_MIN_W and box.h >= Fade.REVEAL_MIN_H then
                box.frame = frame
                found[#found + 1] = box
            end
        end
    end
    for _, source in ipairs(extras) do
        local ok, frame, pad = pcall(source)
        local okV, shown = false, nil
        if ok and type(frame) == "table" then okV, shown = pcall(frame.IsVisible, frame) end
        if okV and shown == true and alphaOf(frame, goals) >= Fade.REVEAL_SKIP then
            local okB, box = pcall(boxOf, frame)
            if okB and box and box.w >= Fade.REVEAL_MIN_W and box.h >= Fade.REVEAL_MIN_H then
                pad = plain(pad) and pad or 0
                box.l, box.b, box.w, box.h = box.l - pad, box.b - pad, box.w + 2 * pad, box.h + 2 * pad
                box.frame = frame
                found[#found + 1] = box
            end
        end
    end
    table.sort(found, function(a, b) return a.w * a.h > b.w * b.h end)
    local picks = {}
    for _, box in ipairs(found) do
        local nested = false
        for _, p in ipairs(picks) do
            if inside(box, p) then nested = true; break end
        end
        if not nested then picks[#picks + 1] = box end
        if #picks >= Fade.REVEAL_MAX then break end
    end
    for _, box in ipairs(picks) do box.delay = Fade.RippleDelay(box.frame) or 0 end
    table.sort(picks, function(a, b)
        if a.delay ~= b.delay then return a.delay < b.delay end
        return a.l < b.l
    end)
    return picks
end

local function overlay(i)
    local ov = overlays[i]
    if not ov then
        ov = CreateFrame("Frame", nil, UIParent)
        ov:EnableMouse(false)
        ov:Hide()
        overlays[i] = ov
    end
    return ov
end

-- Traces one outline in, then lets it settle into the border underneath.
local function traceOne(ov, box)
    local M, W = DUI.Motion, DUI.Widgets
    ov:ClearAllPoints()
    ov:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", box.l, box.b)
    ov:SetSize(box.w, box.h)
    local okS, strata = pcall(box.frame.GetFrameStrata, box.frame)
    local okL, level = pcall(box.frame.GetFrameLevel, box.frame)
    ov:SetFrameStrata(okS and type(strata) == "string" and strata or "MEDIUM")
    ov:SetFrameLevel(math.min(10000, (okL and plain(level) and level or 0) + 20))
    local px = DUI.Style.BorderPx(box.frame)
    local thick = DUI.Pixel.Px(ov, (plain(px) and px > 0) and px or 1)
    if ov.thick ~= thick then
        if ov.trace then
            for _, k in ipairs({ "top", "right", "left", "bottom" }) do ov.trace[k]:Hide() end
            for _, g in ipairs(ov.trace.gleams) do g:Hide() end
        end
        ov.trace, ov.thick = W.Trace(ov, 0, thick, "OVERLAY"), thick
    end
    local tr = ov.trace
    ov:SetAlpha(1)
    ov:Show()
    tr.Draw(0)
    M.Tween(tr, 0, 1, Fade.REVEAL_TIME, function(p) tr.Draw(p, true) end,
        function() M.AlphaTo(ov, 0, Fade.REVEAL_TIME, true) end)
end

-- Once the traces are in, a soft warm light runs across each traced frame
-- (Parts.SHINE, the glow the unit frames' fight light uses), left to right
-- across the screen. It's on its own frame so the outline settling under it
-- only fades that.
local function sweepOne(ov, box)
    local h = ov.shine
    if not h then
        h = CreateFrame("Frame", nil, UIParent)
        h:EnableMouse(false)
        h.light = h:CreateTexture(nil, "OVERLAY")
        h.light:SetTexture(DUI.MEDIA .. "glow.png")
        h.light:SetBlendMode("ADD")
        h.light:Hide()
        ov.shine = h
    end
    h:ClearAllPoints()
    h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", box.l, box.b)
    h:SetSize(box.w, box.h)
    h:SetFrameStrata(ov:GetFrameStrata())
    h:SetFrameLevel(ov:GetFrameLevel())
    h:Show()
    local S, M = Fade.SWEEP, DUI.Motion
    local Parts = DUI.Win and DUI.Win.Parts
    h.light:SetHeight(box.h * 1.2)
    M.Sweep(h.light, h, { width = box.w * S.band, dur = M.SLOW + M.NORMAL, alpha = S.alpha,
        color = Parts and Parts.SHINE, inset = box.w * S.band * 0.25 })
end

-- The welcome line (on login and /reload, but not while the setup guide opens
-- for a new character): "Welcome back, <you>" with your name in the accent,
-- rising in above the middle, then drifting up and away like the level-up
-- showpiece. Takes no clicks.
local welcome
function Fade.Welcome()
    local W = Fade.WELCOME
    local M, Style = DUI.Motion, DUI.Style
    if not welcome then
        welcome = CreateFrame("Frame", nil, UIParent)
        welcome:EnableMouse(false)
        welcome:SetFrameStrata("HIGH")
        welcome:SetSize(600, W.size * 2)
        welcome.text = Style.Text(welcome, W.size, "CENTER")
        welcome.text:SetPoint("CENTER")
        Fade.welcome = welcome
    end
    local name = DUI.UnitName("player", "player")
    if type(name) ~= "string" or isSecret(name) then return end
    local coloured, on = Style.AccentText(name)
    if not on then
        local Parts = DUI.Win and DUI.Win.Parts
        coloured = Parts and Parts.Hex({ Style.Accent() }) .. name .. "|r" or name
    end
    welcome.text:SetText(DUI.L["Welcome back, %s"]:format(coloured))
    Style.InkText(welcome.text, "TEXT")
    local function at(p, a)
        welcome:ClearAllPoints()
        welcome:SetPoint("CENTER", UIParent, "CENTER", 0, W.y + p)
        welcome:SetAlpha(a)
    end
    at(-W.rise, 0)
    welcome:Show()
    M.Tween("fade:welcome", 0, 1, M.SLOW, function(p) at(-W.rise * (1 - p), p) end, function()
        C_Timer.After(W.hold, function()
            M.Tween("fade:welcome", 0, 1, M.SLOW, function(p) at(W.rise * p, 1 - p) end,
                function() welcome:Hide() end)
        end)
    end)
end

-- Will the reveal play now? Once the UI has loaded (login or /reload), with
-- motion on and no fight going.
function Fade.RevealComing()
    return revealDue and motionOn() and not InCombatLockdown() and (DUI.Widgets and DUI.Widgets.Trace) ~= nil
end

-- Runs fn in secs seconds unless a fight has started by then (fight info first).
local function later(secs, fn)
    if secs <= 0 then fn() return end
    C_Timer.After(secs, function() if not InCombatLockdown() then fn() end end)
end

function Fade.Reveal()
    local coming = Fade.RevealComing()
    revealDue = false
    if not coming then return end
    local picks = Fade.RevealPicks()
    local last = 0
    for i, box in ipairs(picks) do
        last = math.max(last, box.delay)
        later(box.delay, function() traceOne(overlay(i), box) end)
    end
    local w = UIParent:GetWidth()
    local across = plain(w) and w > 0 and w or nil
    for i, box in ipairs(picks) do
        local x = across and math.max(0, math.min(1, (box.l + box.w / 2) / across)) or 0
        later(last + Fade.REVEAL_TIME + Fade.SWEEP.spread * x, function() sweepOne(overlay(i), box) end)
    end
    local guide = DUI.Installer and DUI.Installer.State
    if not (guide and guide() == nil) then Fade.Welcome() end
    DUI.Fire("LoginReveal")
end

DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() Fade.fighting = true; Fade.Step() end)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() Fade.fighting = false; Fade.peaceAt = GetTime(); Fade.Step() end)
-- "Show with a target": back as soon as you pick one; the delay runs once it's gone.
DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function() Fade.Step() end)
-- The fade-in starts once the loading screen is gone and the game has stopped
-- stuttering (before that it plays out unseen, behind the loading screen or
-- in choppy frames while the world streams in). Any hitch restarts the count
-- of steady frames, and STEADY_CAP starts it anyway.
local settler = CreateFrame("Frame")
settler.steady, settler.waited = 0, 0
settler:Hide()
settler:SetScript("OnUpdate", function(self, dt)
    self.waited = self.waited + dt
    self.steady = dt > Fade.STEADY_DT and 0 or self.steady + dt
    if not loginPhase or self.steady >= Fade.STEADY or self.waited >= Fade.STEADY_CAP - Fade.INTRO_WAIT then
        self:Hide()
        Fade.StartIntro()
    end
end)
Fade.settler = settler

DUI.RegisterEvent("LOADING_SCREEN_DISABLED", function()
    C_Timer.After(Fade.INTRO_WAIT, function()
        if not loginPhase then return end
        settler.steady, settler.waited = 0, 0
        settler:Show()
    end)
end)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if not worldAt then revealDue = true end
    worldAt = worldAt or GetTime()
    if Fade.CheckInstance() then Fade.Step() end
end)
DUI.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() if Fade.CheckInstance() then Fade.Step() end end)
DUI.RegisterEvent("PLAYER_LOGIN", function() loginAt = GetTime(); Fade.CheckInstance() end)

if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter",
          function() Fade.editMode = true; Fade.Step() end, Fade)
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit",
          function() Fade.editMode = false; Fade.Step() end, Fade)
end

-- Dragging the faded opacity slider shows the faded look, even where the area
-- is held at full (its options page is open), and releases it the moment the
-- mouse does. Only that slider: flashing the area away when picking a mode or
-- delay read as broken.
function Fade.Held()
    return type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") == true
end

DUI.RegisterEvent("GLOBAL_MOUSE_UP", function()
    local any = false
    for _, key in ipairs(order) do
        local e = entries[key]
        if e.peeking then e.peeking, any = nil, true end
    end
    if any then Fade.Step() end
end)

DUI.On("SettingChanged", function(scope, path)
    if type(path) ~= "string" then return end
    -- "Fades only in the open world": no preview, it applies at once.
    if scope == "general" and path == "fadeOpenWorldOnly" then Fade.Step(); return end
    local any = false
    for _, key in ipairs(order) do
        local e = entries[key]
        if e.scope == scope and type(e.path) == "string"
           and (path == e.path or path:sub(1, #e.path + 1) == e.path .. ".") then
            if path == e.path .. ".alpha" and Fade.Held() then
                e.peeking = true
                any = true
            end
        end
    end
    if any then Fade.Step() end
end)

-- Settings and the options rows every area shares

-- A fresh default table for a module's Defaults.lua.
function Fade.Defaults(overrides)
    local t = { mode = Fade.DEFAULT.mode, alpha = Fade.DEFAULT.alpha,
                mouseover = Fade.DEFAULT.mouseover, target = Fade.DEFAULT.target, targetEnemy = Fade.DEFAULT.targetEnemy, delay = Fade.DEFAULT.delay, opacity = Fade.DEFAULT.opacity }
    for k, v in pairs(overrides or {}) do t[k] = v end
    return t
end

-- The single "Visible" option.
Fade.MODES = { never = "Always", ooc = "Fade out of combat", combat = "Fade in combat", always = "Fade until mouseover",
               float = "Only when something changes" }
Fade.MODE_ORDER = { "never", "ooc", "combat", "always", "float" }
Fade.MODE_DESC = "Fade out of combat: fades a while after a fight and comes back in one. Fade in combat: fades a while into a fight and comes back after. Fade until mouseover: stays faded until your mouse is over it. Only when something changes: gone out of a fight, back in one, and back for a moment when it changes (a buff gained or lost, your health, quest progress, XP)."
Fade.FIELDS = { "opacity", "mode", "alpha", "mouseover", "target", "targetEnemy", "delay" } -- the rows every area has, in order
Fade.CARD_LABEL = "Opacity & fade"

-- The Fade rows for the area whose settings live under prefix ("player.fade.").
-- extra: rows to append. disabled(get): the page's own reason to dim them all
-- (the tracker turned off). name: what the Fade page calls the area (else its
-- card's title, or its page's when the card is the plain one).
-- opts.noFloat: no "Only when something changes" (the area registers
-- float = false). Every row carries fadeArea so the Fade page can find them
-- (Fade.HubGroups).
function Fade.Items(prefix, extra, disabled, name, opts)
    local noFloat = opts ~= nil and opts.noFloat == true
    local function pageOff(get) return disabled ~= nil and disabled(get) == true end
    local function fades(get)
        local m = get(prefix .. "mode")
        return m == "ooc" or m == "combat" or m == "always" or (m == "float" and not noFloat)
    end
    local function off(get) return pageOff(get) or not fades(get) end
    local values, order = {}, {}
    for _, m in ipairs(Fade.MODE_ORDER) do
        if not (noFloat and m == "float") then values[m] = Fade.MODES[m]; order[#order + 1] = m end
    end
    local items = {
        { type = "slider", key = prefix .. "opacity", label = "Opacity", min = 0, max = 1, step = 0.05, unit = "%",
          desc = "How see-through it is while shown, whatever the fade does. At 0 it never shows, even under the mouse or in a fight.", disabled = pageOff },
        { type = "dropdown", key = prefix .. "mode", label = "Visible", values = values, order = order,
          fallback = "never", desc = Fade.MODE_DESC, disabled = pageOff },
        { type = "slider", key = prefix .. "alpha", label = "Faded opacity", min = 0, max = 0.9, step = 0.05, unit = "%",
          desc = "How far it fades. At 0 it disappears fully. Never more than Opacity.", disabled = off },
        { type = "toggle", key = prefix .. "mouseover", label = "Show on mouseover",
          desc = "Comes back while your mouse is over it.", disabled = off },
        { type = "toggle", key = prefix .. "target", label = "Show with a target",
          desc = "Comes back while you have something targeted, and fades again after the delay once you clear it.", disabled = off },
        { type = "toggle", key = prefix .. "targetEnemy", label = "Only enemies",
          desc = "Show with a target only for something you can attack: talking to a quest giver or a vendor leaves it faded.",
          disabled = function(get) return off(get) or get(prefix .. "target") ~= true end },
        { type = "slider", key = prefix .. "delay", label = "Delay", min = 0, max = 30, step = 0.5,
          desc = "Seconds before it fades: after a fight ends, once a fight starts, after your mouse leaves it, after you clear your target, or after a change it shows.", disabled = off },
    }
    local area = { prefix = prefix, name = name, base = {}, extras = {} }
    for i, field in ipairs(Fade.FIELDS) do
        items[i].fadeArea = area
        area.base[field] = items[i]
    end
    for _, item in ipairs(extra or {}) do
        if disabled and not item.disabled then item.disabled = pageOff end
        item.fadeArea = area
        area.extras[#area.extras + 1] = item
        items[#items + 1] = item
    end
    return items
end

function Fade.Card(prefix, extra, disabled, name, opts)
    return { label = Fade.CARD_LABEL, desc = "How see-through it is, when it fades and how far. Unlocked, in test mode or with this page open, it shows at its opacity.",
             items = Fade.Items(prefix, extra, disabled, name, opts) }
end

-- The Fade page (General > Fade): every area's rows in one place, a card per
-- module with a picker for its areas. Its rows are copies that read and write
-- the area's own settings, so a change shows on both pages.

Fade.HUB_PAGE = "fade"
local hubCards = {} -- module cards, each { areas, chosen = the player's pick, Pick() }
local hubSeen, hubAt = {}, nil -- the picked areas' "scope:path", worked out once per check

local function refreshPanel()
    local P = DUI.OptionsPanel
    if P and P.IsShown() then P.Refresh() end
end

-- The area each card has picked shows at its opacity while the Fade page is
-- open, as it does with its own page open.
function Fade.HubShows(e)
    if hubAt ~= tick then
        hubAt = tick
        wipe(hubSeen)
        for _, card in ipairs(hubCards) do
            local a = card.Pick()
            hubSeen[a.scope .. ":" .. a.prefix] = true
        end
    end
    return type(e.path) == "string" and hubSeen[tostring(e.scope) .. ":" .. e.path .. "."] == true
end

-- Its own page disables it: raid frames off, the bag bar hidden, the game's
-- tracker while ours runs.
local function areaOff(a)
    local off = a.base.opacity.disabled
    return off ~= nil and off(a.get) == true
end

-- A copy of src (an area's row) reading and writing area()'s settings at the
-- same spot. area is a function so the base rows follow the pick.
local function sharedRow(src, area)
    local item = {}
    for k, v in pairs(src) do item[k] = v end
    item.key, item.fadeArea = nil, nil
    item.noSearch = true -- search finds the area's own row
    if src.field == "mode" then
        item.values, item.order = nil, nil
        item.choices = function() local own = area().base.mode return own.values, own.order end
    end
    local function keyOf() local a = area() return a, a.base[src.field] and a.base[src.field].key or src.key end
    if src.key then
        item.get = function() local a, key = keyOf() return DUI:Get(a.scope, key) end
        item.set = function(v) local a, key = keyOf() DUI:Set(a.scope, key, v) end
        item.default = function() local a, key = keyOf() return DUI.DB.GetPath(a.defaults, key) end
    end
    item.disabled = function()
        local a = area()
        local own = src.field and a.base[src.field] or src
        return own.disabled ~= nil and own.disabled(a.get) == true
    end
    -- The picked area's own rule (the chat hides its base rows except Opacity).
    item.hidden = function()
        local a = area()
        local own = src.field and a.base[src.field] or src
        -- A row in a picker card (a bar on Bar Layout) uses its own rule, not the pick's.
        local hide = own.inPick and own.baseHidden or (not own.inPick and own.hidden) or nil
        return hide ~= nil and hide(a.get) == true
    end
    return item
end

-- Every area the loaded modules' pages show (Fade.Items' rows), one card per
-- module in window order. Called once the modules' pages exist (Login).
function Fade.HubGroups()
    local groups, seen = {}, {}
    for i = #hubCards, 1, -1 do hubCards[i] = nil end
    local Options = DUI.Options
    for _, section in ipairs(Options.Sections()) do
        local card = { areas = {} }
        for _, page in ipairs(section.pages) do
            for _, group in ipairs(page.scope ~= "general" and page.groups or {}) do
                for _, item in ipairs(group.items) do
                    local a = item.fadeArea
                    if a and not seen[a] then
                        seen[a] = true
                        a.scope, a.page, a.defaults = page.scope, page, page.defaults or {}
                        a.get = function(key) return DUI:Get(a.scope, key) end
                        a.label = a.name or (group.label ~= Fade.CARD_LABEL and group.label) or page.label
                        a.id = a.scope .. ":" .. a.prefix
                        card.areas[#card.areas + 1] = a
                    end
                end
            end
        end
        if #card.areas > 0 then
            -- Until the player picks, the first area in use.
            local function pick()
                if card.chosen then return card.chosen end
                for _, a in ipairs(card.areas) do
                    if not areaOff(a) then return a end
                end
                return card.areas[1]
            end
            card.Pick = pick
            -- Areas that are off are left out, except the current pick.
            local function choices()
                local values, order, current = {}, {}, pick()
                for _, a in ipairs(card.areas) do
                    if a == current or not areaOff(a) then
                        values[a.id] = a.label; order[#order + 1] = a.id
                    end
                end
                return values, order
            end
            local items = {
                { type = "dropdown", label = "Settings for", noSearch = true,
                  desc = "Which part's fade the rows below set.",
                  choices = choices,
                  get = function() return pick().id end,
                  set = function(id)
                      for _, a in ipairs(card.areas) do if a.id == id then card.chosen = a end end
                      hubAt = nil
                      Fade.Step()
                      refreshPanel()
                  end,
                  hidden = function() return #card.areas < 2 end },
            }
            for _, field in ipairs(Fade.FIELDS) do
                local src = {}
                for k, v in pairs(card.areas[1].base[field]) do src[k] = v end
                src.field = field
                items[#items + 1] = sharedRow(src, pick)
            end
            -- Extras (Only at full health, the chat's idle fade) only show while their area is picked.
            for _, a in ipairs(card.areas) do
                for _, src in ipairs(a.extras) do
                    local row = sharedRow(src, function() return a end)
                    local own = row.hidden
                    row.hidden = function() return pick() ~= a or (own ~= nil and own() == true) end
                    items[#items + 1] = row
                end
            end
            hubCards[#hubCards + 1] = card
            groups[#groups + 1] = { label = section.label, items = items }
        end
    end
    return groups
end

-- Reset page on the Fade page resets every area's fade, not just the picked ones.
function Fade.ResetAll()
    local Options = DUI.Options
    for _, card in ipairs(hubCards) do
        for _, a in ipairs(card.areas) do
            for _, field in ipairs(Fade.FIELDS) do Options.ResetItem(a.page, a.base[field]) end
            for _, item in ipairs(a.extras) do Options.ResetItem(a.page, item) end
        end
    end
end
