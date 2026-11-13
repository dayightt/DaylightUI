-- Object glow: quest objects, chests and the fishing bobber light up as you get
-- near. Ore and herbs are told apart but never lit: switching the game's plate
-- on and off for every node walked past may be what stops all nameplates
-- drawing until a reload. The game picks one object as the soft interact target
-- ("softinteract") and gives it a nameplate. That plate is the only way to find
-- the object on screen, so the light is attached to it.
--
-- Dim out of reach, lit in reach, dim again when the game refuses it (skill too
-- low, locked). The OnUpdate only runs while a light is showing.
--
-- The CVars it changes are saved per account (ns.KeepCVar) and restored when
-- it's switched off and at logout, so characters without the module are
-- unaffected. The interact plate is only opened for objects we light, so NPCs
-- and corpses get no new plate or icon.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Motion = DUI.Motion

local Glow = {
    SOFT = "softinteract",
    RANGE = "15",           -- yards: the client drops the soft target past this, whatever is asked
    FISH_RANGE = "60",      -- while the line is in: the bobber lands further out
    PLATE_RANGE = 60,       -- the plate must reach as far as the soft target does
    BOBBER = 35591,         -- the bobber's object id, in its GUID
    EVERY = 0.2,            -- s between looks at a light's object
    WATCH = 0.25,           -- s between looks with no light up: an event alone misses a far object
    -- The picture, in px on the plate.
    -- The plate sits over the object and the game can't say how tall that is, or
    -- how far off: seen in game, a vein's foot is far below its plate up close and
    -- nearer it from afar. So objectGlowHeight is the drop in reach, FAR_DROP of it far off.
    FAR_DROP = 0.55,
    FLAT = 0.36,            -- a circle lying on the ground, seen from the usual camera
    POOL = 130,             -- the pool of light's width
    CORE = 54,              -- its bright middle's
    SHAFT_W = 30,
    SHAFT_H = 120,
    LEAN = 16,              -- the shaft leans this far right at its top: the angled look
    RISE = 96,              -- how far a mote climbs
    MOTES = 4,
    MOTE = 7,
    MOTE_LIFE = 3.2,
    RING_TIME = 0.8,        -- s the ring takes to run out
    RING_REACH = 1.15,      -- its width at the end, in POOL widths
    SPREAD = 0.35,          -- the pool is this much wider as it arrives and leaves
    LIFT = 0.45,            -- a one-color light's bright end
    FRAME_W = 170,          -- the angled frame on the ground (objectglow-frame.png, 2:1)
    FRAME_H = 85,
    FRAME_OUT = 0.45,       -- it grows this much as it runs out
    -- Its corners in halves of the art, x right and y up: as tools/make_object_glow.py draws them.
    FRAME_PATH = { { -0.62, 0.72 }, { 0.92, 0.72 }, { 0.62, -0.72 }, { -0.92, -0.72 } },
    SUN_W = 170,            -- the low sun behind the object (objectglow-sun.png, 2:1)
    SUN_H = 85,
    TRACK = 1.05,           -- the sweep's ring, in POOL widths
    DOTS = 12,              -- the light that runs round a frame or ring, head first
    DOT = 9,
    TAIL = 0.3,             -- its tail, as a share of the way round
    RUN_EVERY = 3,          -- s to go round once
    BREATH = 0.1,           -- the light breathes this much
    BREATH_EVERY = 3,       -- s
    -- How bright each piece is at full light.
    A_POOL = 0.4,
    A_CORE = 0.3,
    A_SHAFT = 0.4,
    A_SHADE = 0.2,          -- the dark under it: light alone washes out on snow and sand
    A_RING = 0.5,
    A_FRAME = 0.65,
    A_SUN = 0.6,
    A_TRACK = 0.6,
    A_MOTE = 0.5,
    A_DOT = 0.7,
    FAR = 0.45,             -- brightness out of reach
    LOCK_DIM = 0.5,         -- and when the game refuses it
    PREVIEW_STEP = 1.4,     -- s each state of each kind shows
    -- The looks. pool: its strength; motes: theirs, none without; run: what the light runs round.
    LOOKS = {
        daybreak = { pool = 1, shaft = true, motes = 1 },
        frame = { pool = 0.75, frame = true, run = "frame", motes = 0.7 },
        sunrise = { pool = 0.8, sun = true },
        sweep = { pool = 1.1, track = true, run = "ring", motes = 0.6, dots = 1.4 },
    },
    -- Light, soft and warm like the rest of the look. A thing with its own
    -- color keeps it: these say what the object is at a glance.
    KINDS = {
        quest = { 1.00, 0.84, 0.32 },
        chest = { 0.58, 0.78, 1.00 },
        bobber = { 1.00, 0.52, 0.42 },
        other = { 0.92, 0.90, 0.86 },
    },
    ORDER = { "quest", "chest", "bobber", "other" },
    -- Which setting each kind answers to.
    SWITCH = { quest = "objectGlowQuest",
        chest = "objectGlowChest", bobber = "objectGlowBobber", other = "objectGlowOther" },
    -- The cursor the game gives an object says what it is: part of the file's
    -- name, first match wins ("questinteract" is a quest before an interact).
    CURSOR_WORDS = {
        { "gather", "herb" }, { "mine", "ore" },
        { "quest", "quest" }, { "important", "quest" }, { "recurring", "quest" }, { "wrapper", "quest" },
        { "picklock", "chest" }, { "lootall", "chest" }, { "pickup", "chest" },
        { "mail", "service" }, { "speak", "service" }, { "buy", "service" }, { "trainer", "service" },
        { "taxi", "service" }, { "innkeeper", "service" }, { "repair", "service" }, { "stable", "service" },
        { "interact", "other" }, { "inspect", "other" },
    },
    -- The game's cursor files, which it may hand back as a file id.
    CURSOR_FILES = { "Mine", "GatherHerbs", "Quest", "QuestRepeatable", "QuestTurnIn", "QuestInteract",
        "CampaignQuest", "CampaignQuestTurnIn", "LegendaryQuest", "LegendaryQuestTurnIn", "Important",
        "ImportantTurnIn", "Recurring", "Recurringturnin", "Wrapper", "Wrapperturnin", "PickLock", "LootAll",
        "Pickup", "Interact", "GamepadInteract", "Inspect", "Mail", "Speak", "Buy", "Trainer", "Taxi",
        "Innkeeper", "Repair", "RepairNPC", "Stablemaster" },
    -- A chest has no cursor of its own: the game gives it a lever's. So its name
    -- says, or having looted one like it does (DB.Root().glowChests). A word may
    -- start or end a longer one (Schatztruhe). Russian's capitals don't fold.
    CHEST_WORDS = {
        enUS = { "chest", "coffer", "crate", "barrel", "strongbox", "lockbox", "trunk", "footlocker", "cache", "stash" },
        deDE = { "truhe", "kiste", "fass", "schatulle", "kasten" },
        frFR = { "coffre", "caisse", "tonneau", "malle" },
        esES = { "cofre", "caja", "barril", "arca", "baúl" },
        esMX = { "cofre", "caja", "barril", "arca", "baúl" },
        ruRU = { "сундук", "Сундук", "ящик", "Ящик", "бочка", "Бочка", "ларец", "Ларец" },
    },
}
Glow.Random = math.random   -- tests fix it
ns.Glow = Glow

-- The frame's corners in px and each side's length, so the running light keeps
-- the same speed on long and short sides.
do
    local P = { total = 0 }
    for i, c in ipairs(Glow.FRAME_PATH) do
        P[i] = { x = c[1] * Glow.FRAME_W / 2, y = c[2] * Glow.FRAME_H / 2 }
    end
    for i = 1, 4 do
        local p, q = P[i], P[i % 4 + 1]
        p.len = math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2)
        P.total = P.total + p.len
    end
    Glow.framePoints = P
end
ns.features[#ns.features + 1] = Glow

local GLOW_ART = DUI.MEDIA .. "glow.png"
local BEAM_ART = DUI.MEDIA .. "waypoint-beam.png"
local RING_ART = DUI.MEDIA .. "objectglow-ring.png"
local FRAME_ART = DUI.MEDIA .. "objectglow-frame.png"
local SUN_ART = DUI.MEDIA .. "objectglow-sun.png"
local UNABLE = "unable"

local mod, events, probe, applied, leaving
local fight = false         -- in a fight: PLAYER_REGEN_DISABLED comes before InCombatLockdown says so
local lineOut = false       -- your fishing line is in the water
local gateOpen              -- nil = not known yet
local plateUnits = {}       -- the plate tokens up now
local byFile = {}           -- cursor file id -> { kind, blocked }
local gathered = {}         -- object ids the game called ore or herb: never learned as chests
local known = {}            -- the object last classified
local previewRun = 0        -- each preview's id: a newer one stops the older one's timers
local previewing = false

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- A call's plain first return, or nil (no such call, an error, a secret).
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or secret(v) then return nil end
    return v
end

local function on(key) return mod ~= nil and mod.db ~= nil and mod.db[key] == true end
local function wanted() return on("objectGlow") end

-- ---------------------------------------------------------------------
-- The game settings
-- ---------------------------------------------------------------------

-- Every setting taken over, and the value it holds. The plate's own two are
-- set by Glow.Gate; the rest stay put while it's on.
Glow.CVARS = {
    SoftTargetInteract = "3",               -- always pick an object, mouse and keyboard too
    SoftTargetInteractArc = "2",            -- all around you
    SoftTargetInteractOnlyInRange = "0",    -- not only what's already in reach
    SoftTargetInteractRangeIsHard = "0",    -- or the bobber, further out, is passed over
    SoftTargetIconGameObject = "1",         -- without it the game makes no plate for an object
}
Glow.GATE_CVARS = { "SoftTargetNameplateInteract", "SoftTargetIconInteract" }
Glow.RANGE_CVAR = "SoftTargetInteractRange"
Glow.PLATE_CVAR = "nameplateGameObjectMaxDistance"

local function get(name)
    if type(GetCVar) ~= "function" then return nil end
    local ok, v = pcall(GetCVar, name)
    return ok and v ~= nil and tostring(v) or nil
end

-- Only settings this client has: the list changes between versions.
local function set(name, v)
    local now = get(name)
    if now ~= nil and now ~= v and type(SetCVar) == "function" then pcall(SetCVar, name, v) end
end

-- The controller UI sets these same settings itself, for the time it's on.
local function padMode()
    local E = DUI.EditMode
    return type(E) == "table" and plain(E.GamepadMode) == true
end
local function canWrite() return wanted() and not padMode() end

local function range() return lineOut and Glow.FISH_RANGE or Glow.RANGE end

-- Open: the game shows a plate for the soft target, which the light needs.
-- Shut: back to the player's own values. Forcing 0 instead made node plates
-- flash on and off. Can't be changed in combat.
function Glow.Gate(open)
    if not canWrite() or InCombatLockdown() then return end
    if open then set("SoftTargetIconGameObject", "1") end   -- the game puts it back to 0 after a loading screen
    if open == gateOpen then return end
    gateOpen = open
    set("SoftTargetNameplateInteract", open and "1" or (ns.KeptCVar("SoftTargetNameplateInteract") or "0"))
    set("SoftTargetIconInteract", ns.KeptCVar("SoftTargetIconInteract") or (open and "1" or "0"))
end

local function keepAll()
    for name in pairs(Glow.CVARS) do ns.KeepCVar(name) end
    for _, name in ipairs(Glow.GATE_CVARS) do ns.KeepCVar(name) end
    ns.KeepCVar(Glow.RANGE_CVAR)
    ns.KeepCVar(Glow.PLATE_CVAR)
end

local function giveAllBack()
    applied = false
    gateOpen = nil
    local function back(name)
        local v = ns.GiveBackCVar(name)
        if v ~= nil then set(name, v) end
    end
    for name in pairs(Glow.CVARS) do back(name) end
    for _, name in ipairs(Glow.GATE_CVARS) do back(name) end
    back(Glow.RANGE_CVAR)
    back(Glow.PLATE_CVAR)
end

function Glow.Apply()
    DUI.AfterCombat(function()
        if not canWrite() then return end
        keepAll()
        applied = true
        for name, v in pairs(Glow.CVARS) do set(name, v) end
        set(Glow.RANGE_CVAR, range())
        -- A player who shows plates further out keeps that.
        local theirs = tonumber(ns.KeptCVar(Glow.PLATE_CVAR)) or 0
        set(Glow.PLATE_CVAR, tostring(math.max(theirs, Glow.PLATE_RANGE)))
        gateOpen = nil
        Glow.Evaluate()
    end, "qol:glow")
end

-- ---------------------------------------------------------------------
-- What's that object?
-- ---------------------------------------------------------------------

-- A cursor file's name -> what it says, whether it's grayed.
function Glow.ReadCursorName(name)
    if type(name) ~= "string" then return nil, false end
    name = name:lower()
    local blocked = name:find(UNABLE, 1, true) ~= nil
    for _, w in ipairs(Glow.CURSOR_WORDS) do
        if name:find(w[1], 1, true) then return w[2], blocked end
    end
    return nil, blocked
end

local function learnCursorFiles()
    if type(GetFileIDFromPath) ~= "function" then return end
    for _, file in ipairs(Glow.CURSOR_FILES) do
        for _, prefix in ipairs({ "", "Unable" }) do
            local id = plain(GetFileIDFromPath, "Interface\\Cursor\\" .. prefix .. file)
            if id then byFile[id] = { (Glow.ReadCursorName(file)), prefix ~= "" } end
        end
    end
end

-- Whether the game has a cursor for it, what that says, and whether it's grayed.
function Glow.ReadCursor(unit)
    if not probe then
        probe = UIParent:CreateTexture(nil, "BACKGROUND")
        probe:Hide()
    end
    if plain(SetUnitCursorTexture, probe, unit, nil, true) ~= true then return false, nil, false end
    local tex = plain(probe.GetTexture, probe)
    local atlas = probe.GetAtlas and plain(probe.GetAtlas, probe)
    local file = byFile[tex]
    if file then return true, file[1], file[2] end
    local kind, blocked = Glow.ReadCursorName(tex)
    if not kind then
        local fromAtlas, grayed = Glow.ReadCursorName(atlas)
        kind, blocked = fromAtlas, blocked or grayed
    end
    return true, kind, blocked
end

-- The number all objects of a sort share, the sixth part of their GUID.
function Glow.ObjectID(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

local function chestsSeen()
    local root = DUI.DB.Root()
    if type(root.glowChests) ~= "table" then root.glowChests = {} end
    return root.glowChests
end

function Glow.IsChest(id, name)
    if id and chestsSeen()[id] then return true end
    if type(name) ~= "string" then return false end
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    local words = Glow.CHEST_WORDS[locale] or Glow.CHEST_WORDS.enUS
    for word in name:lower():gmatch("[^%s%p]+") do
        for _, chest in ipairs(words) do
            if word:sub(1, #chest) == chest or word:sub(-#chest) == chest then return true end
        end
    end
    return false
end

-- The game itself ties it to a quest you have.
function Glow.IsQuest(unit)
    local Q = C_QuestLog
    if Q and plain(Q.UnitIsRelatedToActiveQuest, unit) == true then return true end
    local lineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
    local data = lineType and C_TooltipInfo and plain(C_TooltipInfo.GetUnit, unit)
    if type(data) == "table" and type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            if line.type == lineType then return true end
        end
    end
    return false
end

-- The kind, from what the cursor says and everything else we can ask.
function Glow.Classify(unit, hasCursor, kind, guid)
    local service = kind == "service"
    if service then kind = "other" end
    local id = Glow.ObjectID(guid)
    if id == Glow.BOBBER then return "bobber", id end
    if kind == "ore" or kind == "herb" then return kind, id end
    if Glow.IsQuest(unit) then return "quest", id end
    if service then return "other", id end
    if (kind == nil or kind == "other") and Glow.IsChest(id, plain(UnitName, unit)) then return "chest", id end
    if kind then return kind, id end
    if hasCursor or plain(UnitIsInteractable, unit) == true then return "other", id end
    return nil, id
end

-- The soft target's kind and whether it's grayed now. A grayed cursor is read
-- every look; the kind once per object (a quest change forgets it).
function Glow.Read()
    local unit = Glow.SOFT
    local hasCursor, kind, blocked = Glow.ReadCursor(unit)
    local guid = plain(UnitGUID, unit)
    if guid and known.guid == guid then return known.kind, blocked, guid end
    local id
    kind, id = Glow.Classify(unit, hasCursor, kind, guid)
    if id and (kind == "ore" or kind == "herb") then gathered[id] = true end
    known.guid, known.kind = guid, kind
    return kind, blocked, guid
end

-- "ready" in reach, "far" out of it, "locked" in reach but refused for now.
function Glow.State(blocked)
    local near = plain(UnitIsInInteractRange, Glow.SOFT)
    if near == false then return "far" end
    if blocked then return near == true and "locked" or "far" end
    return "ready"
end

-- Looting something: remember what sort of thing it came from, which is how
-- crates and barrels (and any chest in a language we have no word for) count.
function Glow.LearnChests()
    if not wanted() or type(GetNumLootItems) ~= "function" or type(GetLootSourceInfo) ~= "function" then return end
    for slot = 1, plain(GetNumLootItems) or 0 do
        local id = Glow.ObjectID(plain(GetLootSourceInfo, slot))
        if id and id ~= Glow.BOBBER and not gathered[id] then chestsSeen()[id] = true end
    end
end

-- ---------------------------------------------------------------------
-- The picture
-- ---------------------------------------------------------------------

local function toward(v, goal, dt, dur)
    if dur <= 0 then return goal end
    local s = dt / dur
    if v < goal then return math.min(goal, v + s) end
    return math.max(goal, v - s)
end

local function layer(parent, file, draw, sub, blend)
    local t = parent:CreateTexture(nil, draw, nil, sub)
    t:SetTexture(file)
    t:SetBlendMode(blend or "ADD")
    -- Sizes animate below a pixel: no snapping to the grid.
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
    if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
    return t
end

local function lift(c, k)
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

local function blend(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- The light's two ends: the accent, read now (never cached), or the object's.
function Glow.ColorOf(kind)
    if not (mod and mod.db and mod.db.objectGlowColor == "object") then
        local Style = DUI.Style
        local lo, hi = Style.AccentPair()
        if lo then return lo, hi end
        local r, g, b = Style.Accent()
        local c = { r, g, b }
        return c, lift(c, Glow.LIFT)
    end
    local c = Glow.KINDS[kind] or Glow.KINDS.other
    return c, lift(c, Glow.LIFT)
end

function Glow.LookOf()
    local look = mod and mod.db and mod.db.objectGlowLook
    return Glow.LOOKS[look] and look or "sweep"
end

local function gradient(tex, orientation, lo, hi)
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orientation, CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
    else
        tex:SetVertexColor(lo[1], lo[2], lo[3], 1)
    end
end

-- Puts a picture in a look and its colors. Only the colors and shapes that
-- change every frame are touched in paint: the rest stands.
local function dress(a, look, lo, hi)
    local spec = Glow.LOOKS[look]
    a.look, a.spec, a.lo, a.hi = look, spec, lo, hi
    a.shade:SetVertexColor(0, 0, 0, 1)
    a.pool:SetVertexColor(lo[1], lo[2], lo[3], 1)
    local heart = lift(hi, 0.4)
    a.core:SetVertexColor(heart[1], heart[2], heart[3], 1)
    a.shaft:SetShown(spec.shaft == true)
    gradient(a.shaft, "VERTICAL", hi, lo)
    a.frame:SetShown(spec.frame == true)
    gradient(a.frame, "HORIZONTAL", lo, hi)
    a.sun:SetShown(spec.sun == true)
    gradient(a.sun, "HORIZONTAL", lo, hi)
    a.track:SetShown(spec.track == true)
    a.track:SetVertexColor(lo[1], lo[2], lo[3], 1)
    local reach = lift(lo, 0.4)
    a.ring:SetShown(spec.frame ~= true)
    a.ring:SetVertexColor(reach[1], reach[2], reach[3], 1)
    a.frameOut:SetShown(spec.frame == true)
    a.frameOut:SetVertexColor(reach[1], reach[2], reach[3], 1)
    for i, m in ipairs(a.motes) do
        local c = blend(lo, hi, i / Glow.MOTES)
        m.tex:SetVertexColor(c[1], c[2], c[3], 1)
        m.tex:SetShown(spec.motes ~= nil)
    end
    for i, d in ipairs(a.dots) do
        local c = i == 1 and lift(hi, 0.5) or blend(hi, lo, i / Glow.DOTS)
        d:SetVertexColor(c[1], c[2], c[3], 1)
        d:SetShown(spec.run ~= nil)
    end
end

-- A spot u of the way round (any number, it wraps), from the picture's middle.
local function spotOn(run, u)
    u = u % 1
    if run == "ring" then
        local angle = u * 2 * math.pi
        local r = Glow.POOL * Glow.TRACK / 2
        return math.cos(angle) * r, math.sin(angle) * r * Glow.FLAT
    end
    local P = Glow.framePoints
    local want = u * P.total
    for i = 1, 4 do
        local p, q = P[i], P[i % 4 + 1]
        if want <= p.len or i == 4 then
            local t = want / p.len
            return p.x + (q.x - p.x) * t, p.y + (q.y - p.y) * t
        end
        want = want - p.len
    end
end

local function paint(a)
    local spec = a.spec
    local arrive = 1 - (1 - a.arrive) * (1 - a.arrive)  -- eased out
    local level = arrive * (Glow.FAR + (1 - Glow.FAR) * a.lit) * (1 - Glow.LOCK_DIM * a.lock)
    local moving = Motion.On()
    if moving then
        level = level * (1 + Glow.BREATH * math.sin(a.t * 2 * math.pi / Glow.BREATH_EVERY))
    end
    level = math.min(level, 1)
    local wide = Glow.POOL * (1 + Glow.SPREAD * (1 - arrive))
    a.shade:SetSize(wide * 1.15, wide * 1.15 * Glow.FLAT)
    a.shade:SetAlpha(level * Glow.A_SHADE)
    a.pool:SetSize(wide, wide * Glow.FLAT)
    a.pool:SetAlpha(level * Glow.A_POOL * spec.pool)
    a.core:SetSize(Glow.CORE, Glow.CORE * Glow.FLAT)
    a.core:SetAlpha(level * Glow.A_CORE * spec.pool)
    if spec.shaft then
        a.shaft:SetHeight(Glow.SHAFT_H * (0.6 + 0.4 * a.lit) * arrive + 0.01)
        a.shaft:SetAlpha(level * Glow.A_SHAFT)
    end
    if spec.frame then a.frame:SetAlpha(level * Glow.A_FRAME) end
    if spec.sun then
        a.sun:SetHeight(Glow.SUN_H * (0.55 + 0.45 * a.lit) * arrive + 0.01)
        a.sun:SetAlpha(level * Glow.A_SUN)
    end
    if spec.track then
        local w = Glow.POOL * Glow.TRACK
        a.track:SetSize(w, w * Glow.FLAT)
        a.track:SetAlpha(level * Glow.A_TRACK)
    end
    -- The ring that runs out on coming into reach: the frame's own shape for the frame.
    local age = moving and a.ringAge
    local out = spec.frame and a.frameOut or a.ring
    if age then
        local p = age / Glow.RING_TIME
        local grow = 1 - (1 - p) * (1 - p)
        local fade = arrive * Glow.A_RING * (1 - p) * (1 - p)
        if spec.frame then
            local k = 1 + Glow.FRAME_OUT * grow
            out:SetSize(Glow.FRAME_W * k, Glow.FRAME_H * k)
        else
            local w = Glow.POOL * (0.3 + (Glow.RING_REACH - 0.3) * grow)
            out:SetSize(w, w * Glow.FLAT)
        end
        out:SetAlpha(fade)
    else
        out:SetAlpha(0)
    end
    if spec.motes then
        for _, m in ipairs(a.motes) do
            local p = moving and (a.t / Glow.MOTE_LIFE + m.phase) % 1 or 0
            local y = p * Glow.RISE
            m.tex:ClearAllPoints()
            m.tex:SetPoint("CENTER", a, "CENTER", m.x + Glow.LEAN * y / Glow.SHAFT_H, y)
            m.tex:SetAlpha(moving and level * a.lit * Glow.A_MOTE * spec.motes * math.sin(p * math.pi) or 0)
        end
    end
    if spec.run then
        local head = moving and a.t / Glow.RUN_EVERY or 0
        for i, d in ipairs(a.dots) do
            local p = (i - 1) / Glow.DOTS
            local x, y = spotOn(spec.run, head - p * Glow.TAIL)
            local size = Glow.DOT * (spec.dots or 1) * (i == 1 and 2.2 or 1 - 0.5 * p)
            d:SetSize(size, size)
            d:ClearAllPoints()
            d:SetPoint("CENTER", a, "CENTER", x, y)
            d:SetAlpha(math.min(1, level * Glow.A_DOT * (spec.dots or 1) * (1 - p) * (1 - p)))
        end
    end
end

-- How far under its plate a light sits: in reach it drops to the object's foot.
function Glow.Drop(near)
    local height = mod and mod.db and mod.db.objectGlowHeight or 110
    return height * (Glow.FAR_DROP + (1 - Glow.FAR_DROP) * near)
end

function Glow.Place(a)
    if not a.plate then return end
    local drop = Glow.Drop(math.max(a.lit, a.lock))
    if drop == a.drop then return end
    a.drop = drop
    a:ClearAllPoints()
    a:SetPoint("CENTER", a.plate, "CENTER", 0, -drop)
end

local function step(a, dt)
    dt = dt or 0
    a.t = a.t + dt
    local still = not Motion.On()
    a.arrive = toward(a.arrive, a.leaving and 0 or 1, dt, still and 0 or Motion.SLOW)
    if a.leaving and a.arrive <= 0 then
        a:Hide()
        return
    end
    a.lit = toward(a.lit, a.state == "ready" and 1 or 0, dt, still and 0 or Motion.NORMAL)
    a.lock = toward(a.lock, a.state == "locked" and 1 or 0, dt, still and 0 or Motion.NORMAL)
    if not a.leaving then Glow.Place(a) end
    if a.ringAge then
        a.ringAge = a.ringAge + dt
        if a.ringAge >= Glow.RING_TIME then a.ringAge = nil end
    end
    paint(a)
    if a.leaving then return end
    -- Where it is now, for the light left behind when the plate goes.
    local ok, x, y = pcall(a.GetCenter, a)
    local okScale, scale = pcall(a.GetEffectiveScale, a)
    if ok and okScale and type(x) == "number" and type(y) == "number" and type(scale) == "number"
        and not secret(x) and not secret(y) and not secret(scale) then
        local ratio = scale / UIParent:GetEffectiveScale()
        a.gx, a.gy = x * ratio, y * ratio
    else
        a.gx, a.gy = nil, nil
    end
    a.lookIn = (a.lookIn or Glow.EVERY) - dt
    if a.lookIn <= 0 then
        a.lookIn = Glow.EVERY
        if a.plate and not previewing then DUI.SafeCall(Glow.Evaluate) end
    end
end

function Glow.NewArt(parent)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(1, 1)
    a:Hide()
    a.t, a.arrive, a.lit, a.lock = 0, 0, 0, 0
    a.shade = layer(a, GLOW_ART, "BACKGROUND", 0, "BLEND")
    a.pool = layer(a, GLOW_ART, "BACKGROUND", 1)
    a.core = layer(a, GLOW_ART, "BACKGROUND", 2)
    a.track = layer(a, RING_ART, "BACKGROUND", 3)
    a.ring = layer(a, RING_ART, "BACKGROUND", 3)
    a.frame = layer(a, FRAME_ART, "BACKGROUND", 4)
    a.frameOut = layer(a, FRAME_ART, "BACKGROUND", 4)
    a.sun = layer(a, SUN_ART, "BACKGROUND", 4)
    a.shaft = layer(a, BEAM_ART, "BORDER", 0)
    for _, t in ipairs({ a.shade, a.pool, a.core, a.track, a.ring, a.frame, a.frameOut }) do
        t:SetPoint("CENTER", a, "CENTER", 0, 0)
    end
    a.frame:SetSize(Glow.FRAME_W, Glow.FRAME_H)
    a.sun:SetSize(Glow.SUN_W, Glow.SUN_H)
    a.sun:SetPoint("BOTTOM", a, "CENTER", 0, 0)
    a.shaft:SetSize(Glow.SHAFT_W, Glow.SHAFT_H)
    a.shaft:SetPoint("BOTTOM", a, "CENTER", 0, 0)
    if a.shaft.SetVertexOffset then
        pcall(a.shaft.SetVertexOffset, a.shaft, 1, Glow.LEAN, 0)
        pcall(a.shaft.SetVertexOffset, a.shaft, 3, Glow.LEAN, 0)
    end
    a.motes = {}
    for i = 1, Glow.MOTES do
        local tex = layer(a, GLOW_ART, "BORDER", 1)
        tex:SetSize(Glow.MOTE, Glow.MOTE)
        a.motes[i] = { tex = tex, phase = (i - 1) / Glow.MOTES,
            x = (Glow.Random() - 0.5) * Glow.SHAFT_W * 0.6 }
    end
    a.dots = {}
    for i = 1, Glow.DOTS do a.dots[i] = layer(a, GLOW_ART, "BORDER", 2) end
    dress(a, "frame", Glow.KINDS.other, Glow.KINDS.other)
    a:SetScript("OnUpdate", step)
    return a
end

-- The light goes, spreading where it stood: its plate may be gone already, so
-- a second picture on the screen plays that.
function Glow.Leave()
    local a = Glow.art
    if not a or not a.plate then return end
    local g = Glow.ghost
    if g and a.gx and Motion.On() and a.arrive > 0.3 then
        g:ClearAllPoints()
        g:SetPoint("CENTER", UIParent, "BOTTOMLEFT", a.gx, a.gy)
        dress(g, a.look, a.lo, a.hi)
        g.t, g.arrive, g.lit, g.lock, g.state = a.t, a.arrive, a.lit, a.lock, a.state
        g.ringAge, g.leaving = nil, true
        g:Show()
    end
    a:Hide()
    a:ClearAllPoints()
    a:SetParent(UIParent)
    if a.hushed then a.hushed:SetAlpha(1); a.hushed = nil end
    a.plate, a.kind, a.guid, a.state, a.gx, a.gy = nil, nil, nil, nil, nil, nil
end

-- The game's own interact icon on a plate.
function Glow.GameIcon(plate)
    local uf = type(plate) == "table" and plate.UnitFrame
    local icon = type(uf) == "table" and uf.SoftTargetFrame
    return type(icon) == "table" and icon.SetAlpha and icon or nil
end

-- On plate, under what the plate shows, or moved to a new state in place.
function Glow.Show(plate, kind, state, guid)
    local a = Glow.art
    if not a then return end
    if a.plate ~= plate or a.kind ~= kind or a.guid ~= guid then
        Glow.Leave()
        a:SetParent(plate)
        local level = plain(plate.GetFrameLevel, plate)
        if level then a:SetFrameLevel(math.max(level - 1, 0)) end
        a.drop = nil
        if a.SetIgnoreParentAlpha then a:SetIgnoreParentAlpha(true) end
        a.plate, a.kind, a.guid = plate, kind, guid
        -- The light marks the bobber already; the game's icon on top of it was
        -- a second marker.
        if kind == "bobber" and not InCombatLockdown() then
            a.hushed = Glow.GameIcon(plate)
            if a.hushed then a.hushed:SetAlpha(0) end
        end
        dress(a, Glow.LookOf(), Glow.ColorOf(kind))
        a.t, a.arrive, a.leaving = 0, 0, false
        a.lit = state == "ready" and 1 or 0
        a.lock = state == "locked" and 1 or 0
        a.ringAge = state == "ready" and 0 or nil
        a.state = state
        Glow.Place(a)
        a:Show()
        return
    end
    if a.state ~= state then
        if state == "ready" then a.ringAge = 0 end
        a.state = state
    end
end

-- A setting or the accent changed: the light up now takes it at once.
function Glow.Redress()
    local a = Glow.art
    if a and a.plate then
        dress(a, Glow.LookOf(), Glow.ColorOf(a.kind))
        Glow.Place(a)
    end
end

-- ---------------------------------------------------------------------
-- What to light
-- ---------------------------------------------------------------------

local function allowed()
    if not wanted() then return false end
    if fight and not on("objectGlowFight") then return false end
    if not on("objectGlowInstance") then
        local inside = plain(IsInInstance)
        if inside == true then return false end
    end
    return true
end

-- The plate of the soft target; the token alone usually finds it, and if it
-- doesn't, the object among the plates up now.
local function plateOf()
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    local plate = plain(get, Glow.SOFT)
    if plate then return plate end
    for unit in pairs(plateUnits) do
        if plain(UnitIsGameObject, unit) == true or plain(UnitIsUnit, unit, Glow.SOFT) == true then
            plate = plain(get, unit)
            if plate then return plate end
        end
    end
    return nil
end

-- One look at the soft target. Comes from the game's events, and every
-- Glow.EVERY s from the light itself while one shows.
function Glow.Evaluate()
    if leaving or previewing then return end
    if not allowed() or plain(UnitIsGameObject, Glow.SOFT) ~= true then
        Glow.Leave()
        Glow.Gate(false)
        return
    end
    local kind, blocked, guid = Glow.Read()
    if not kind or not on(Glow.SWITCH[kind]) then
        Glow.Leave()
        Glow.Gate(false)
        return
    end
    Glow.Gate(true)
    local plate = plateOf()
    if not plate then   -- just asked for: the next look finds it (Glow.Watch)
        Glow.Leave()
        return
    end
    Glow.Show(plate, kind, Glow.State(blocked), guid)
end

-- The game may not have a far object's plate ready when its events fire, and
-- nothing says when it will. With events alone the light only showed once you
-- stood on the object, so this polls. A light that's already up polls itself (step).
function Glow.Watch()
    local a = Glow.art
    if a and a.plate then return end
    if wanted() and not fight then DUI.SafeCall(Glow.Evaluate) end
end

-- Your line in the water: the bobber lands further out than the soft target
-- looks, so it's asked to look further until the line comes in.
local function fishing(line)
    lineOut = line
    if not canWrite() or not applied or InCombatLockdown() then return end
    set(Glow.RANGE_CVAR, range())
end

local function onEvent(_, event, unit, _, spell)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local Fish = ns.Fishing
        if unit == "player" and on("objectGlowBobber") and Fish and Fish.Spell and spell == Fish.Spell() then
            fishing(true)
        end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if unit == "player" and lineOut then fishing(false) end
    end
end

local function wire()
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", onEvent)
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    local function look() DUI.SafeCall(Glow.Evaluate) end
    DUI.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", look)
    DUI.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
        if type(unit) == "string" and not secret(unit) then plateUnits[unit] = true end
        look()
    end)
    DUI.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        if type(unit) == "string" and not secret(unit) then plateUnits[unit] = nil end
        look()
    end)
    DUI.RegisterEvent("QUEST_LOG_UPDATE", function()
        known.guid = nil
        look()
    end)
    DUI.RegisterEvent("LOOT_READY", function() DUI.SafeCall(Glow.LearnChests) end)
    DUI.RegisterEvent("LOOT_OPENED", function() DUI.SafeCall(Glow.LearnChests) end)
    -- Settings can't change in a fight: set for it as it starts.
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        fight = true
        previewing = false
        Glow.Gate(on("objectGlowFight"))
        look()
    end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        fight = false
        look()
    end)
    DUI.On("StyleChanged", Glow.Redress)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if wanted() then Glow.Apply() end
    end)
    DUI.RegisterEvent("PLAYER_LOGOUT", function()
        leaving = true
        if applied then giveAllBack() end
    end)
end

-- ---------------------------------------------------------------------
-- Preview
-- ---------------------------------------------------------------------

-- In the middle of the screen, far then in reach: each kind in turn when they
-- have their own colors.
function Glow.Preview()
    if InCombatLockdown() or not Glow.art then return end
    Glow.Leave()
    previewRun = previewRun + 1
    previewing = true
    local run = previewRun
    local stand = Glow.stand
    if not stand then
        stand = CreateFrame("Frame", nil, UIParent)
        stand:SetSize(1, 1)
        stand:SetPoint("CENTER", UIParent, "CENTER", 0, Glow.Drop(1))
        Glow.stand = stand
    end
    -- In the accent every kind is the same light: once is enough.
    local order = mod and mod.db and mod.db.objectGlowColor == "object" and Glow.ORDER or { "quest" }
    local function beat(i)
        if run ~= previewRun or not previewing then return end
        local kind = order[math.ceil(i / 2)]
        if not kind then
            Glow.Leave()
            previewing = false
            return
        end
        Glow.Show(stand, kind, i % 2 == 1 and "far" or "ready", "preview" .. kind)
        C_Timer.After(Glow.PREVIEW_STEP, function() beat(i + 1) end)
    end
    beat(1)
end

-- ---------------------------------------------------------------------
-- Feature
-- ---------------------------------------------------------------------

function Glow.Enable(m)
    mod = m
    fight = InCombatLockdown() == true
    learnCursorFiles()
    if not Glow.art then
        Glow.art = Glow.NewArt(UIParent)
        Glow.ghost = Glow.NewArt(UIParent)
        Glow.ghost:SetFrameStrata("BACKGROUND")
    end
    if not events then
        wire()
        C_Timer.NewTicker(Glow.WATCH, Glow.Watch)
    end
    DUI.RegisterCommand("glow", Glow.Preview, L["/dui glow - preview the object glow"])
    if wanted() then Glow.Apply() else applied = false end
end

function Glow.Refresh(m)
    mod = m
    if wanted() then
        Glow.Apply()
        Glow.Redress()
    else
        Glow.Leave()
        if applied then DUI.AfterCombat(function()
            if not wanted() and applied then giveAllBack() end
        end, "qol:glow") end
    end
end
