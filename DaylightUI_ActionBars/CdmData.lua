-- The player's Cooldown Manager layout. Every spell is a piece (an icon or a bar).
-- A piece either sits free on screen (the first piece of a chain) or hangs off one
-- side of another piece. A chain's first piece holds the chain's settings
-- (set.chains[rootID]), and each piece can override the look.
-- This file holds the saved layout, the one-time move from the old blocks, and the
-- math for where every piece goes. No frames, so it can be tested on plain tables.
-- Every function takes one talent set's layout (`set` = { v = 2, pieces = {},
-- chains = {} }). Positions are px from screen center in UIParent units, y up. A box
-- is { x = left, y = top, w, h }.

local _, ns = ...
local DUI = DaylightUI

local Data = {}
ns.CdmData = Data

Data.FORMAT = 2
Data.GAP = 4         -- px between a piece and the one it hangs off
Data.SIDES = { "right", "down", "left", "up" }
Data.ORIGIN = { 0, -120 }   -- default spot of the old layout frame

-- A chain's look. A piece's own look table overrides it key by key.
-- back is the bars' background: "dark", "solid" (backColor {r,g,b,a}) or "gradient"
-- (backGradient {lo,hi}). A spell's own background (CdmEffects backMode) wins.
Data.LOOK = { size = 36, width = 220, height = 18, color = "class", icon = true, text = 11, time = true, back = "dark" }
-- Bar defaults when nothing else is set (read by Cooldowns and CdmBars).
Data.BAR_LOOK = { color = "class", icon = true, text = 11, time = true }
-- A chain's toggles: which end stays put as pieces hide, only in combat, always show
-- (buffs that aren't up still show), close the gap of a hidden piece, and the gap
-- between pieces (a piece's own gap wins). Then when the chain shows: only in a
-- group, only with a target, not while mounted, and where (anywhere | instance =
-- dungeons, raids, battlegrounds, arenas | world).
Data.CHAIN = { grow = "start", combat = false, always = false, collapse = true, spacing = Data.GAP,
    group = false, target = false, mounted = false, where = "any" }

-- A piece's icon text keys (Data.TEXT_KEYS, or Data.BAR_TEXT_KEYS for bars), with
-- unset ones left out.
function Data.TextOf(set, id, keys)
    local t = {}
    for _, k in ipairs(keys or Data.TEXT_KEYS) do t[k] = Data.PieceLook(set, id, k) end
    return t
end

-- A block-like table's look value (Rows hands one per piece to the skins).
function Data.Look(block, key)
    local v = block[key]
    if v == nil then v = Data.BAR_LOOK[key] end
    return v
end

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local function copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = copy(x) end
    return c
end

Data.SETS = 2        -- layouts per character, one per talent set
Data.MOVE = 2        -- version of the one-time move from profiles; bump when it has more to do

-- Profile keys from before the layout was per character. The move removes them.
Data.OLD_KEYS = { "cdmLayout", "cdmLayoutOn", "cdmHideUnplaced",
    -- the old Buff bars page; bars now take their look from their block
    "cdmBars", "cdmDock", "cdmGrow", "cdmBarHeight", "cdmMatchWidth", "cdmWidth",
    "cdmGap", "cdmOffset", "cdmColor", "cdmIcon", "cdmText", "cdmTime" }

local function emptySet() return { v = Data.FORMAT, pieces = {}, chains = {} } end

-- A set with something in it, in either format (old blocks or pieces).
function Data.HasPieces(set)
    if type(set) ~= "table" then return false end
    if type(set.pieces) == "table" and next(set.pieces) ~= nil then return true end
    return type(set.blocks) == "table" and #set.blocks > 0
end

-- Runs once. Each profile's old layout (its sets with blocks) is kept account-wide
-- in cdmSaved[profile name] for "Copy from...", and the old keys are removed from
-- every profile. No character gets a layout from this; each starts empty.
function Data.MoveOld()
    local root = DUI.DB.Root()
    if (tonumber(root.cdmMoved) or 0) >= Data.MOVE then return end
    root.cdmMoved = Data.MOVE
    if type(root.cdmSaved) ~= "table" then root.cdmSaved = {} end
    local pd = type(root.profileData) == "table" and root.profileData or {}
    for name, p in pairs(pd) do
        local ab = type(p) == "table" and type(p.modules) == "table" and p.modules.ActionBars
        if type(ab) == "table" then
            local keep
            if type(ab.cdmLayout) == "table" then
                for g, set in pairs(ab.cdmLayout) do
                    if type(g) == "number" and Data.HasPieces(set) and set.rows == nil then
                        keep = keep or {}
                        keep[g] = copy(set)
                    end
                end
            end
            if keep and root.cdmSaved[name] == nil then root.cdmSaved[name] = keep end
            for _, k in ipairs(Data.OLD_KEYS) do ab[k] = nil end
        end
    end
end

-- This character's toggles and picks (DB.Character().cdm), created if missing.
-- Before login the name isn't known, so this returns an unsaved scratch table; the
-- layout is only built after login.
function Data.Store()
    Data.MoveOld()
    local c = DUI.DB.Character()
    if type(c.cdm) ~= "table" then c.cdm = {} end
    if type(c.cdm.use) ~= "table" then c.cdm.use = {} end
    Data.MoveToProfiles()
    Data.TakeSaved()
    Data.MendShared()
    return c.cdm
end

-- Where the old layout frame (mover "cdm.s<g>") sat. Old blocks were placed from
-- its center.
local function oldOrigin(g)
    local pos = DUI.DB and DUI.DB.Positions and DUI.DB.Positions()["cdm.s" .. tostring(g)]
    if DUI.Movers and DUI.Movers.Valid and DUI.Movers.Valid(pos) then return pos[1], pos[2] end
    return Data.ORIGIN[1], Data.ORIGIN[2]
end

-- Brings a saved layout up to the current format (old formats, renamed keys).
local function normalize(set, ox, oy)
    -- The rows format never shipped; a set still in it starts empty.
    if set.rows ~= nil then
        set.rows, set.buttons, set.blocks = nil, nil, nil
    end
    if set.v ~= Data.FORMAT then Data.Migrate(set, ox or Data.ORIGIN[1], oy or Data.ORIGIN[2]) end
    if type(set.pieces) ~= "table" then set.pieces = {} end
    if type(set.chains) ~= "table" then set.chains = {} end
    -- "Show missing buffs" used to be per chain; now it's per spell (missing).
    for root, c in pairs(set.chains) do
        if type(c) == "table" and c.always ~= nil then
            if c.always == true and set.pieces[root] then
                for _, q in ipairs(Data.Subtree(set, root)) do set.pieces[q].missing = true end
            end
            c.always = nil
        end
    end
    -- "Only when usable" was a When ready choice; now it's When not usable's Hide.
    if not set.usableMoved then
        set.usableMoved = true
        for _, p in pairs(set.pieces) do
            if type(p) == "table" and p.onReady == "usable" then
                p.onReady, p.onUnusable = nil, "hide"
            end
        end
    end
    -- The buff swipe's unset color used to be the game's yellow, now the accent.
    -- Drop a saved copy of that old default (the picker saves what it opened on).
    if not set.activeAccent then
        set.activeAccent = true
        for _, p in pairs(set.pieces) do
            local c = type(p) == "table" and p.activeColor
            if type(c) == "table" and c[1] == 1 and c[2] == 0.95 and c[3] == 0.57 and c[4] == 0.7 then
                p.activeColor = nil
            end
        end
    end
    return set
end

-- ---------------------------------------------------------------------
-- Profiles: named, account-wide layouts, each for one class. A class can have any
-- number, with one picked per talent set.
-- DB.Root().cdmProfiles[id] = { name, class, set }; a character's picks live in
-- DB.Character().cdm.use[g] = id.
-- ---------------------------------------------------------------------

local function myClass()
    local _, token = UnitClass("player")
    if type(token) == "string" and not (issecretvalue and issecretvalue(token)) then return token end
end
Data.MyClass = myClass

local function profiles()
    local root = DUI.DB.Root()
    if type(root.cdmProfiles) ~= "table" then root.cdmProfiles = {} end
    return root.cdmProfiles
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

function Data.Profile(id)
    local p = id ~= nil and profiles()[id]
    if type(p) == "table" and type(p.set) == "table" then return p end
end

-- A class's profiles (the player's class when nil), by name: { { id, name } }.
function Data.Profiles(class)
    class = class or myClass()
    local out = {}
    for id, p in pairs(profiles()) do
        if type(p) == "table" and type(p.set) == "table" and p.class == class then
            out[#out + 1] = { id = id, name = tostring(p.name or id) }
        end
    end
    table.sort(out, function(a, b)
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then return x < y end
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end

-- A name no other profile of the class uses: name, else "name 2", "name 3"...
function Data.FreeName(name, class, except)
    local taken = {}
    for id, p in pairs(profiles()) do
        if id ~= except and type(p) == "table" and p.class == class and type(p.name) == "string" then
            taken[p.name:lower()] = true
        end
    end
    local try, n = name, 1
    while taken[try:lower()] do n = n + 1; try = string.format("%s %d", name, n) end
    return try
end

-- Creates a profile for class (the player's when nil) with the given layout set
-- (kept as is) or an empty one. Returns its id.
function Data.NewProfile(name, class, set)
    class = class or myClass()
    local root = DUI.DB.Root()
    local list = profiles()
    local n = (tonumber(root.cdmNextProfile) or 0) + 1
    while list["p" .. n] ~= nil do n = n + 1 end
    root.cdmNextProfile = n
    local id = "p" .. n
    name = trim(name)
    if name == "" then name = DUI.L["Layout"] end
    list[id] = { name = Data.FreeName(name, class), class = class,
        set = type(set) == "table" and set or emptySet() }
    Data.Changed()
    return id
end

function Data.RenameProfile(id, name)
    local p = Data.Profile(id)
    name = trim(name)
    if not p or name == "" then return false end
    p.name = Data.FreeName(name, p.class, id)
    return true
end

-- Deletes it for every character. Talent sets that used it end up with none.
function Data.DeleteProfile(id)
    if not Data.Profile(id) then return false end
    profiles()[id] = nil
    Data.Changed()
    return true
end

-- A new profile of the same class with a deep copy of id's layout. Returns its id.
function Data.CopyProfile(id, name)
    local p = Data.Profile(id)
    if not p then return nil end
    return Data.NewProfile(name or p.name, p.class, copy(normalize(p.set)))
end

-- The profile talent set g uses, or nil (none picked, deleted, or another class).
function Data.Use(g)
    local c = DUI.DB.Character()
    local use = type(c) == "table" and type(c.cdm) == "table" and type(c.cdm.use) == "table" and c.cdm.use or nil
    local id = use and use[g]
    local p = Data.Profile(id)
    if p and p.class == myClass() then return id end
end

-- Talent set g uses profile id from now on (nil for none).
function Data.Assign(g, id)
    if type(g) ~= "number" or g < 1 or g > Data.SETS or g % 1 ~= 0 then return false end
    if id ~= nil and not Data.Profile(id) then return false end
    Data.Store().use[g] = id
    Data.Changed()
    return true
end

-- Talent set g's layout, from its profile. With none, an empty layout kept for this
-- session only (Data.Ensure saves it as a profile once it's edited).
local scratch = {}
function Data.Get(g)
    if type(g) ~= "number" or g < 1 or g > Data.SETS or g % 1 ~= 0 then return emptySet() end
    Data.Store()
    local p = Data.Profile(Data.Use(g))
    if p then return normalize(p.set) end
    scratch[g] = scratch[g] or emptySet()
    return normalize(scratch[g])
end

-- Talent set g's layout, saved. With no profile picked, a new one named after the
-- class is made from it and picked. The editor calls this before any change.
function Data.Ensure(g)
    local set = Data.Get(g)
    if Data.Use(g) or not myClass() then return set end
    local name = UnitClass("player")
    local id = Data.NewProfile(type(name) == "string" and name or nil, nil, set)
    scratch[g] = nil
    Data.Assign(g, id)
    return set
end

-- Once per character, its old per-character layouts (cdm.sets) become profiles of
-- its class, picked for the same talent sets. Other characters move too when their
-- class is known (saved by other parts of the UI); the rest move at their own login.
-- again = run once more this session (tests).
local function charName(key) return (tostring(key):match("^(.-)%-") or tostring(key)) end
local movedFor   -- once per session (Store runs on every layout pass)
function Data.MoveToProfiles(again)
    local root, me = DUI.DB.Root(), DUI.DB.CharKey()
    if not me or (movedFor == root and not again) then return end
    movedFor = root
    local chars = type(root.characters) == "table" and root.characters or {}
    for key, c in pairs(chars) do
        local cdm = type(c) == "table" and c.cdm
        local sets = type(cdm) == "table" and cdm.sets
        if type(sets) == "table" then
            local inv = type(c.inventory) == "table" and c.inventory or nil
            local class
            if key == me then class = myClass() else class = c.class or (inv and inv.class) end
            if type(class) == "string" then
                if type(cdm.use) ~= "table" then cdm.use = {} end
                local filled = {}
                for g = 1, Data.SETS do
                    if type(sets[g]) == "table" and Data.HasPieces(sets[g]) then filled[#filled + 1] = g end
                end
                for _, g in ipairs(filled) do
                    local ox, oy
                    if key == me then ox, oy = oldOrigin(g) end
                    local set = normalize(sets[g], ox, oy)
                    local name = #filled > 1 and string.format(DUI.L["%s, talent set %d"], charName(key), g) or charName(key)
                    if cdm.use[g] == nil then cdm.use[g] = Data.NewProfile(name, class, set) end
                end
                cdm.sets = nil
            end
        end
    end
end

-- Once per character, the layout it had before layouts were per character (1.6.0
-- and older, kept in cdmSaved by Data.MoveOld under its profile's name) becomes a
-- profile of its class. Those showed nothing since 1.6.1, and 1.6.4 removed the
-- "Copy from" that reached them. It's only picked by a character with no profile
-- picked at all; one with a pick finds it in the class's list. One profile per old
-- layout and class, shared by that class's characters. A deleted one is only made
-- again for a character that hasn't taken it yet. again = tests.
local takenFor
function Data.TakeSaved(again)
    local root, me = DUI.DB.Root(), DUI.DB.CharKey()
    if not me or (takenFor == root and not again) then return end
    local class = myClass()
    local saved = root.cdmSaved
    if not class or type(saved) ~= "table" or next(saved) == nil then return end
    takenFor = root
    local c = DUI.DB.Character()
    if type(c) ~= "table" then return end
    if type(c.cdm) ~= "table" then c.cdm = {} end
    local cdm = c.cdm
    if cdm.savedTaken then return end
    cdm.savedTaken = true
    if type(cdm.use) ~= "table" then cdm.use = {} end
    local picked = false
    for g = 1, Data.SETS do
        if Data.Use(g) then picked = true end
    end
    -- Which old layout: the one under this character's profile (per talent set
    -- with dual spec), else the only one there is.
    local only, count = nil, 0
    for name, sets in pairs(saved) do
        if type(sets) == "table" then only, count = name, count + 1 end
    end
    local function nameFor(g)
        local per = type(c.specProfiles) == "table" and c.specProfiles[g]
        for _, n in ipairs({ per, c.profile, DUI.DB.DEFAULT }) do
            if type(n) == "string" and type(saved[n]) == "table" then return n end
        end
        if count == 1 then return only end
    end
    if type(root.cdmFromSaved) ~= "table" then root.cdmFromSaved = {} end
    local made = root.cdmFromSaved
    for g = 1, Data.SETS do
        local name = nameFor(g)
        local sets = name and saved[name]
        local from = sets and (Data.HasPieces(sets[g]) and g or (Data.HasPieces(sets[3 - g]) and 3 - g))
        if from then
            local key = string.format("%s|%s|%d", name, class, from)
            local id = made[key]
            if not Data.Profile(id) or Data.Profile(id).class ~= class then
                local ox, oy = oldOrigin(from)
                local label = name
                if Data.HasPieces(sets[1]) and Data.HasPieces(sets[2]) then
                    label = string.format(DUI.L["%s, talent set %d"], name, from)
                end
                id = Data.NewProfile(label, class, normalize(copy(sets[from]), ox, oy))
                made[key] = id
            end
            if not picked then cdm.use[g] = id end
        end
    end
end

-- Until 1.6.5 two characters with the same first name shared one saved entry, so
-- 1.6.4 turned their shared layout into a profile of whichever logged in first, and
-- the other (another class) showed nothing. A pick of another class's profile
-- becomes a copy of it for this class, made once per layout and class and kept in
-- cdmClassCopies. `from` is the original, so two characters never copy back and
-- forth. Returns the copy's id.
local function classCopy(id, class)
    local p = Data.Profile(id)
    local origin = Data.Profile(p.from) and p.from or id
    local o = Data.Profile(origin)
    if o.class == class then return origin end
    local root = DUI.DB.Root()
    if type(root.cdmClassCopies) ~= "table" then root.cdmClassCopies = {} end
    local key = string.format("%s|%s", tostring(origin), class)
    local made = root.cdmClassCopies[key]
    if not (Data.Profile(made) and Data.Profile(made).class == class) then
        made = Data.NewProfile(o.name, class, normalize(copy(o.set)))
        Data.Profile(made).from = origin
        root.cdmClassCopies[key] = made
    end
    return made
end

function Data.MendShared()
    local class = myClass()
    if not class or not DUI.DB.CharKey() then return end
    local c = DUI.DB.Character()
    local cdm = type(c) == "table" and type(c.cdm) == "table" and c.cdm
    local use = cdm and type(cdm.use) == "table" and cdm.use
    if not use then return end
    for g = 1, Data.SETS do
        local p = Data.Profile(use[g])
        if p and p.class ~= class then
            -- An empty one isn't worth keeping; the search below fills it.
            use[g] = Data.HasPieces(p.set) and classCopy(use[g], class) or nil
            Data.Changed()
        end
    end
    -- Once. The shared layout became a profile named after the first name (or
    -- "<name>, talent set 2") of whichever character logged in first, in its class,
    -- and the other saw nothing (opening the editor then made and picked an empty
    -- layout). A talent set with nothing, or an empty layout, takes that profile,
    -- copied for another class if needed. Seen in a player's saved file: a
    -- paladin's layout filed as a hunter's.
    if cdm.sharedLooked then return end
    cdm.sharedLooked = true
    local first = tostring(DUI.DB.ShortKey() or ""):match("^(.-)%-")
    if not first or first == "" then return end
    for g = 1, Data.SETS do
        local mine = Data.Profile(Data.Use(g))
        if not (mine and Data.HasPieces(mine.set)) then
            local wanted = { [first] = true, [string.format(DUI.L["%s, talent set %d"], first, g)] = true }
            local found
            for id, q in pairs(profiles()) do
                if type(q) == "table" and type(q.set) == "table" and q.from == nil
                        and wanted[q.name] and Data.HasPieces(q.set) and (not found or tostring(id) < tostring(found)) then
                    found = id
                end
            end
            if found then
                use[g] = classCopy(found, class)
                Data.Changed()
            end
        end
    end
end

-- Which set is in use: the talent set's. This is the one place to change if sets
-- ever stop matching talent sets. The editor can temporarily show another set
-- (nil = follow talents).
local viewing
function Data.SetViewing(g) viewing = g end
function Data.CurrentIndex() return viewing or DUI.DB.SpecGroup() end

function Data.Current()
    return Data.Get(Data.CurrentIndex())
end

-- "on" (Use my layout) and "hideUnplaced": per character, on unless turned off.
function Data.Switch(key) return Data.Store()[key] ~= false end
function Data.SetSwitch(key, v) Data.Store()[key] = v and true or false end

-- ---------------------------------------------------------------------
-- The tree
-- ---------------------------------------------------------------------

-- Bumped whenever a layout is written, so the cached index below is rebuilt.
-- Everything that changes pieces calls Data.Changed.
Data.version = 0
function Data.Changed() Data.version = Data.version + 1 end

-- Children by parent and side, cached until the next Data.Changed since the layout
-- runs on every aura shown or hidden. Read only.
-- Piece keys are the game's cooldown ids (numbers) and custom spells ("s<spell id>",
-- CdmCustom). Lua won't sort a list that mixes them, so numbers go first and each
-- kind sorts on its own.
function Data.ByKey(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    return a < b
end

local indexCache = setmetatable({}, { __mode = "k" })   -- set.pieces -> index
function Data.Index(set)
    local c = indexCache[set.pieces]
    if c and c.version == Data.version then return c end
    c = { version = Data.version, kids = {}, roots = {} }
    for id, p in pairs(set.pieces) do
        local parent = p.parent
        if parent ~= nil and set.pieces[parent] and p.side then
            local k = c.kids[parent] or {}
            c.kids[parent] = k
            -- one child per side; a second one (a bad save) hangs off the first
            if k[p.side] == nil then k[p.side] = id end
        else
            c.roots[#c.roots + 1] = id
        end
    end
    table.sort(c.roots, Data.ByKey)
    indexCache[set.pieces] = c
    return c
end

function Data.Child(set, id, side)
    local k = Data.Index(set).kids[id]
    return k and k[side] or nil
end

-- The first piece of id's chain (itself when free). This runs about 25 times per
-- piece on every layout pass, which runs on every aura change, so a normal chain is
-- walked without allocating a table; that used to be most of the module's garbage.
-- Only a walk longer than any real chain (a loop in a bad save) keeps a list.
Data.ROOT_WALK = 64
function Data.Root(set, id)
    local pieces, p = set.pieces, id
    for _ = 1, Data.ROOT_WALK do
        local q = pieces[p]
        local parent = q and q.parent
        if parent == nil or not pieces[parent] then return p end
        p = parent
    end
    local seen
    seen, p = {}, id
    while set.pieces[p] and set.pieces[p].parent ~= nil and set.pieces[set.pieces[p].parent] and not seen[p] do
        seen[p] = true
        p = set.pieces[p].parent
    end
    return p
end

-- id and every piece hanging off it, id first.
function Data.Subtree(set, id)
    local out, seen = {}, {}
    local function walk(p)
        if seen[p] then return end
        seen[p] = true
        out[#out + 1] = p
        local k = Data.Index(set).kids[p]
        if k then for _, side in ipairs(Data.SIDES) do if k[side] then walk(k[side]) end end end
    end
    walk(id)
    return out
end

-- A chain's settings table (created if missing), found from any piece in it.
function Data.Chain(set, id)
    local root = Data.Root(set, id)
    local c = set.chains[root]
    if type(c) ~= "table" then c = {}; set.chains[root] = c end
    if type(c.look) ~= "table" then c.look = {} end
    return c
end

-- One chain toggle (Data.CHAIN), found from any piece in it.
function Data.ChainValue(set, id, key)
    local c, v = set.chains[Data.Root(set, id)], nil
    if type(c) == "table" then v = c[key] end
    if v == nil then v = Data.CHAIN[key] end
    return v
end

-- A piece's look: its own, else its chain's, else the default.
function Data.PieceLook(set, id, key)
    local p, v = set.pieces[id], nil
    if p and type(p.look) == "table" then v = p.look[key] end
    if v == nil then
        local c = set.chains[Data.Root(set, id)]
        if type(c) == "table" and type(c.look) == "table" then v = c.look[key] end
    end
    if v == nil then v = Data.LOOK[key] end
    return v
end

-- A piece's size on screen.
function Data.Dims(set, id)
    local p = set.pieces[id]
    if p and p.shape == "bar" then
        return Data.PieceLook(set, id, "width"), Data.PieceLook(set, id, "height")
    end
    local s = Data.PieceLook(set, id, "size")
    local own = p and tonumber(p.size)
    if own and own > 0 then s = max(16, floor(own + 0.5)) end
    return s, s
end

-- The piece as a block of one. This is what Rows' placement, the skins, our bars and
-- CdmEffects read (kind, size, width, look, toggles). Built fresh each call, so cache
-- it per pass.
function Data.PieceBlock(set, id)
    local p = set.pieces[id]
    local shape = p and p.shape == "bar" and "bar" or "icon"
    local w, h = Data.Dims(set, id)
    local look = function(k) return Data.PieceLook(set, id, k) end
    return { kind = shape, dir = "row", grow = "start", wrap = "down", perLine = 1, spacing = 0,
        size = h, width = w, x = 0, y = 0,
        color = look("color"), icon = look("icon"), text = look("text"), time = look("time"),
        back = look("back"), backColor = look("backColor"), backGradient = look("backGradient"),
        iconText = shape == "icon" and Data.TextOf(set, id) or nil,
        barText = shape == "bar" and Data.TextOf(set, id, Data.BAR_TEXT_KEYS) or nil,
        combat = Data.ChainValue(set, id, "combat") == true,
        group = Data.ChainValue(set, id, "group") == true,
        target = Data.ChainValue(set, id, "target") == true,
        mounted = Data.ChainValue(set, id, "mounted") == true,
        where = Data.ChainValue(set, id, "where"),
        -- Hide wins over Show (the card writes one or the other, older saves may
        -- have both). A missing glow needs something to glow around.
        always = p ~= nil and (p.missing == true or p.missingGlow == true) and p.hideMissing ~= true,
        collapse = Data.ChainValue(set, id, "collapse") ~= false }
end

-- Whether a piece's block is hidden right now by its chain's show rules.
-- now = { fight, group, target, mounted, instance } (plain values, from Rows.Now).
function Data.Away(block, now)
    if block.combat and not now.fight then return true end
    if block.group and not now.group then return true end
    if block.target and not now.target then return true end
    if block.mounted and now.mounted then return true end
    if block.where == "instance" and not now.instance then return true end
    if block.where == "world" and now.instance then return true end
    return false
end

-- Whether the game's own item of this shape ("icon" | "bar") can sit in a block (or
-- a piece's block of one, Data.PieceBlock).
function Data.Native(block, kind)
    return type(block) == "table" and block.kind == kind
end

-- ---------------------------------------------------------------------
-- Positioning
-- ---------------------------------------------------------------------

-- A w x h box on `side` of box b, aligned by align, gap px away.
function Data.ChildBox(b, side, w, h, align, gap)
    local x, y
    if side == "down" or side == "up" then
        y = side == "down" and b.y - b.h - gap or b.y + gap + h
        if align == "start" then x = b.x
        elseif align == "end" then x = b.x + b.w - w
        else x = b.x + (b.w - w) / 2 end
    else
        x = side == "right" and b.x + b.w + gap or b.x - gap - w
        if align == "start" then y = b.y
        elseif align == "end" then y = b.y - b.h + h
        else y = b.y - (b.h - h) / 2 end
    end
    return { x = x, y = y, w = w, h = h }
end

local AXIS = { right = "x", left = "x", down = "y", up = "y" }
-- Direction each side grows along its axis: right is +x, down is -y (y up).
local SIGN = { right = 1, left = -1, down = -1, up = 1 }

-- The side a root's chain runs to: its first child in SIDES order.
local function runSide(set, id)
    local k = Data.Index(set).kids[id]
    if not k then return nil end
    for _, side in ipairs(Data.SIDES) do if k[side] then return side end end
end

local function lay(set, shown, out)
    local index = Data.Index(set)
    local seen = {}
    -- empty: this box and everything before it back to the root is hidden, so the
    -- next piece starts right there with no gap. spacing is the chain's gap.
    -- slot (a hidden piece hung off another) = where it would sit: { box = its
    -- parent's, side, align, gap, empty }. A piece hung beside it (across its side)
    -- takes that place. Centering it on the hidden piece's flat box put it on top of
    -- the chain (Thunder Clap beside a hidden Charge, on bars).
    local function place(id, b, hidden, empty, spacing, slot)
        out[id] = b
        b.hidden = hidden or nil
        local k = index.kids[id]
        if not k then return end
        local taker   -- the first piece beside a hidden one, taking its place
        -- A hidden first piece with a neighbor on each side (left and right, or up
        -- and down): the first starts right at its spot and the one across keeps its
        -- gap, or the two would touch.
        local started = {}
        for _, side in ipairs(Data.SIDES) do
            local c = k[side]
            if c and not seen[c] then
                seen[c] = true
                local p = set.pieces[c]
                local w, h = Data.Dims(set, c)
                local off = shown ~= nil and not shown[c]
                local across = slot ~= nil and AXIS[side] ~= AXIS[slot.side]
                if across and not taker then
                    if off then if AXIS[slot.side] == "x" then w = 0 else h = 0 end end
                    taker = Data.ChildBox(slot.box, slot.side, w, h, slot.align, off and 0 or slot.gap)
                    place(c, taker, off, off and slot.empty, spacing, off and slot or nil)
                else
                    -- A second piece beside the hidden one hangs off the first.
                    local base = across and taker or b
                    -- A hidden piece takes no room along its side and no gap, so
                    -- the pieces after it close up.
                    if off then if AXIS[side] == "x" then w = 0 else h = 0 end end
                    local align = p.align or "center"
                    local empty = empty and not started[AXIS[side]]
                    started[AXIS[side]] = true
                    local gap = (off or empty) and 0 or tonumber(p.gap) or spacing
                    place(c, Data.ChildBox(base, side, w, h, align, gap), off, off and empty, spacing,
                        off and { box = base, side = side, align = align, empty = empty,
                                  gap = empty and 0 or tonumber(p.gap) or spacing } or nil)
                end
            end
        end
    end
    for _, id in ipairs(index.roots) do
        seen[id] = true
        local p = set.pieces[id]
        local w, h = Data.Dims(set, id)
        local off = shown ~= nil and not shown[id]
        if off then
            local side = runSide(set, id)
            if side and AXIS[side] == "x" then w = 0 elseif side then h = 0 else w, h = 0, 0 end
        end
        local spacing = tonumber(Data.ChainValue(set, id, "spacing")) or Data.GAP
        place(id, { x = tonumber(p.x) or 0, y = tonumber(p.y) or 0, w = w, h = h }, off, off, spacing)
    end
end

-- The straight run from a root along its run side: root, child, its child...
local function run(set, root, side)
    local list, p = { root }, root
    while true do
        local c = Data.Child(set, p, side)
        if not c then break end
        list[#list + 1] = c
        p = c
    end
    return list
end

local OPPOSITE = { right = "left", left = "right", down = "up", up = "down" }

-- The low and high edge of the boxes along an axis. skipHidden leaves out pieces
-- that are down, so a collapsed one can't pull the edge.
local function edges(boxes, list, axis, skipHidden)
    local lo, hi
    for _, id in ipairs(list) do
        local b = boxes[id]
        if not (skipHidden and b.hidden) then
            local a, z
            if axis == "x" then a, z = b.x, b.x + b.w else a, z = b.y - b.h, b.y end
            lo = lo and min(lo, a) or a
            hi = hi and max(hi, z) or z
        end
    end
    return lo, hi
end

-- Every piece's box, { [id] = { x, y, w, h, hidden } }. shown = { [id] = true } for
-- the pieces currently up (nil = all). A hidden piece collapses along its side. A
-- chain growing from its middle or end shifts so that point of its line (both
-- runs out of the first piece along its run side's axis) stays where it would be
-- with everything shown.
function Data.Layout(set, shown)
    local out = {}
    lay(set, shown, out)
    if shown == nil then return out end
    local full
    for _, root in ipairs(Data.Index(set).roots) do
        local grow = Data.ChainValue(set, root, "grow")
        local side = (grow == "center" or grow == "end") and runSide(set, root)
        if side then
            if not full then full = {}; lay(set, nil, full) end
            local list, axis = run(set, root, side), AXIS[side]
            local back = run(set, root, OPPOSITE[side])
            for i = 2, #back do list[#list + 1] = back[i] end
            local fullLo, fullHi = edges(full, list, axis)
            local lo, hi = edges(out, list, axis, true)
            -- Nothing up on the line itself: measure where it collapsed to.
            if not lo then lo, hi = edges(out, list, axis) end
            local shift = 0
            if lo and grow == "center" then
                shift = (fullLo + fullHi) / 2 - (lo + hi) / 2
            elseif lo then
                shift = SIGN[side] > 0 and fullHi - hi or fullLo - lo
            end
            if shift ~= 0 then
                for _, id in ipairs(Data.Subtree(set, root)) do
                    local b = out[id]
                    if axis == "x" then b.x = b.x + shift else b.y = b.y + shift end
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------
-- Editing the layout (the editor and tests)
-- ---------------------------------------------------------------------

-- A free piece with its top-left at x, y. A piece already in the layout keeps its
-- options and is only freed and moved.
function Data.AddPiece(set, id, shape, x, y)
    local p = set.pieces[id]
    if p then
        Data.Unhook(set, id, x, y)
        if shape then p.shape = shape end
        return p
    end
    Data.Changed()
    p = { shape = shape == "bar" and "bar" or "icon", x = floor((x or 0) + 0.5), y = floor((y or 0) + 0.5) }
    set.pieces[id] = p
    return p
end

-- A row of new pieces: the first at x, y, each next one on `side` of the previous
-- (default right for icons, down for bars).
function Data.AddChain(set, ids, shape, x, y, side, gap)
    side = side or (shape == "bar" and "down" or "right")
    local before
    for _, id in ipairs(ids) do
        if before then
            Data.AddPiece(set, id, shape, 0, 0)
            Data.Hook(set, id, before, side, "start")
            if gap then set.pieces[id].gap = gap end
        else
            Data.AddPiece(set, id, shape, x, y)
        end
        before = id
    end
    return ids[1]
end

-- Hangs id (and everything off it) on `side` of parent. A taken side means the end
-- of that run. Returns false when it would hang off itself.
function Data.Hook(set, id, parent, side, align)
    local p, host = set.pieces[id], set.pieces[parent]
    if not (p and host and AXIS[side]) then return false end
    for _, q in ipairs(Data.Subtree(set, id)) do
        if q == parent then return false end
    end
    local seen = {}
    while true do
        local c = Data.Child(set, parent, side)
        if not c or c == id or seen[c] then break end
        seen[c] = true
        parent = c
    end
    Data.Changed()
    p.parent, p.side, p.align = parent, side, align or "center"
    p.x, p.y = nil, nil
    set.chains[id] = nil
    return true
end

-- Moves id's chain so its first piece's top-left is at x, y (whole numbers). Used by
-- the editor's nudges and typed positions.
function Data.MoveChain(set, id, x, y)
    local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end
    if not (set.pieces[id] and finite(x) and finite(y)) then return false end
    local p = set.pieces[Data.Root(set, id)]
    Data.Changed()
    p.x, p.y = floor(x + 0.5), floor(y + 0.5)
    return true
end

-- Detaches id from its parent, free at x, y, keeping its chain's settings.
function Data.Unhook(set, id, x, y)
    local p = set.pieces[id]
    if not p then return end
    Data.Changed()
    if p.parent ~= nil then
        local from = set.chains[Data.Root(set, id)]
        p.parent, p.side, p.align, p.gap = nil, nil, nil, nil
        if type(from) == "table" then set.chains[id] = copy(from) end
    end
    if x then p.x = floor(x + 0.5) end
    if y then p.y = floor(y + 0.5) end
end

-- Swaps a and b. Where each sits (its spot, or its parent, side, alignment and gap)
-- is exchanged, children follow the swap, and a group's settings stay with the
-- group's first spot. Each spell keeps its own shape, look and options. Returns
-- false when either is missing.
local PLACE = { "parent", "side", "align", "gap", "x", "y" }
function Data.Swap(set, a, b)
    local pa, pb = set.pieces[a], set.pieces[b]
    if not (pa and pb) or a == b then return false end
    for _, k in ipairs(PLACE) do pa[k], pb[k] = pb[k], pa[k] end
    -- Whatever pointed at one now points at the other, a and b included: a piece
    -- that hung off its swap partner now has the partner hanging off it.
    for _, q in pairs(set.pieces) do
        if q.parent == a then q.parent = b elseif q.parent == b then q.parent = a end
    end
    set.chains[a], set.chains[b] = set.chains[b], set.chains[a]
    Data.Changed()
    return true
end

-- The piece before id in its group (its parent) and the one after (its child on the
-- run side; a group's first piece uses its first hooked side). Either is nil at an end.
function Data.Neighbors(set, id)
    local p = set.pieces[id]
    if not p then return nil, nil end
    local before = p.parent ~= nil and set.pieces[p.parent] and p.parent or nil
    local after = p.side and Data.Child(set, id, p.side) or nil
    if not after and not before then
        for _, side in ipairs(Data.SIDES) do
            after = Data.Child(set, id, side)
            if after then break end
        end
    end
    return before, after
end

-- Removes the whole chain id is in: every piece and its settings.
function Data.RemoveChain(set, id)
    if not set.pieces[id] then return false end
    local root = Data.Root(set, id)
    local gone = Data.Subtree(set, root)
    Data.Changed()
    for _, q in ipairs(gone) do set.pieces[q] = nil; set.chains[q] = nil end
    return true
end

-- Removes id. Its children go free where they are now (boxes from Data.Layout;
-- without them, at id's own spot).
function Data.RemovePiece(set, id, boxes)
    local p = set.pieces[id]
    if not p then return end
    boxes = boxes or Data.Layout(set)
    local k = Data.Index(set).kids[id]
    local chain = set.chains[Data.Root(set, id)]
    if k then
        for _, side in ipairs(Data.SIDES) do
            local c = k[side]
            if c then
                local b = boxes[c] or boxes[id] or { x = 0, y = 0 }
                local q = set.pieces[c]
                q.parent, q.side, q.align, q.gap = nil, nil, nil, nil
                q.x, q.y = floor(b.x + 0.5), floor(b.y + 0.5)
                if type(chain) == "table" then set.chains[c] = copy(chain) end
            end
        end
    end
    Data.Changed()
    set.pieces[id] = nil
    set.chains[id] = nil
end

-- ---------------------------------------------------------------------
-- Settings (the editor's card). Values are checked and clamped, and a value equal
-- to what it falls back to is removed.
-- ---------------------------------------------------------------------

-- Look keys: a { min, max } range, a list of values, or true for a toggle.
Data.LOOK_FIELDS = {
    size = { 16, 64 }, width = { 60, 400 }, height = { 10, 40 },
    color = { "class", "gradient", "spell" }, icon = true, text = { 8, 16 }, time = true,
    back = { "dark", "solid", "gradient" }, backColor = { color = true, alpha = true }, backGradient = { gradient = true },
    -- Icon text (unset follows the action bars' look, CD.TextLook).
    cdNumbers = true, cdSize = { 8, 24 }, countSize = { 8, 20 },
    countSpot = { "br", "tr", "tl", "center", "bottom" }, low = true, lowAt = { 1, 10 }, lowColor = { color = true },
    cdColor = { color = true }, countColor = { color = true },
    keyShown = true, keySize = { 8, 20 }, keySpot = { "tr", "tl", "br", "center", "bottom" },
    -- Bar text (unset is the group's text size, white; CD.BarText).
    nameSize = { 8, 20 }, nameColor = { color = true }, timeSize = { 8, 20 }, timeColor = { color = true },
}
Data.TEXT_KEYS = { "cdNumbers", "cdSize", "countSize", "countSpot", "low", "lowAt", "lowColor", "cdColor", "countColor", "keyShown", "keySize", "keySpot" }
Data.BAR_TEXT_KEYS = { "nameSize", "nameColor", "timeSize", "timeColor" }
Data.CHAIN_FIELDS = {
    grow = { "start", "center", "end" }, combat = true, always = true, collapse = true, spacing = { 0, 16 },
    group = true, target = true, mounted = true, where = { "any", "instance", "world" },
}
-- Spell options (defaults live in CdmEffects). icon / bar = that shape only.
Data.SPELL_FIELDS = {
    glow = { bool = true }, readyGlow = { bool = true }, usableGlow = { bool = true },
    noSwipe = { bool = true, icon = true }, noGcd = { bool = true, icon = true }, reverse = { bool = true, icon = true },
    activeGlow = { bool = true, icon = true }, noDurationSwipe = { bool = true, icon = true },
    activeColor = { color = true, alpha = true, icon = true },
    glowColor = { color = true }, readyGlowColor = { color = true }, usableGlowColor = { color = true },
    desat = { values = { "game", "grey", "color" }, icon = true },
    onCd = { values = { "show", "fade", "hide" } },
    onReady = { values = { "show", "fade", "hide" } },
    onUnusable = { values = { "show", "fade", "hide" } },
    onShort = { values = { "show", "fade", "hide" } },
    track = { values = { "both", "cooldown", "buff" } },
    cdAlpha = { min = 0, max = 1 },
    barMode = { values = { "block", "solid", "gradient" }, bar = true },
    fillBy = { values = { "shield", "time" }, bar = true }, shieldAmount = { bool = true },
    barColor = { color = true, bar = true },
    barGradient = { gradient = true, bar = true },
    backMode = { values = { "block", "solid", "gradient" }, bar = true },
    backGradient = { gradient = true, bar = true },
    backColor = { color = true, alpha = true, bar = true },
    showName = { bool = true, bar = true },
    nameAlign = { values = { "left", "center" }, bar = true },
    inactiveFlash = { bool = true, bar = true }, chargeLines = { bool = true, bar = true },
    missing = { bool = true }, missingGlow = { bool = true }, missingGlowColor = { color = true },
    upGlow = { bool = true }, upGlowColor = { color = true },
    clipGlow = { bool = true }, clipGlowColor = { color = true },
    hideActive = { bool = true }, hideMissing = { bool = true },
    readySound = { sound = true }, usableSound = { sound = true }, buffSound = { sound = true }, buffEndSound = { sound = true },
}

local function oneOf(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
end

-- v, or nil when it equals the value it falls back to (false stays false).
local function unless(v, base)
    if v == base then return nil end
    return v
end

local function isRGB(c)
    return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

-- Checks a value against a field. Returns the value to keep, or nil when it's bad.
local function check(spec, v)
    if spec == true then
        if type(v) == "boolean" then return v end
    elseif spec.gradient then
        if type(v) == "table" and isRGB(v.lo) and isRGB(v.hi) then
            return { lo = { v.lo[1], v.lo[2], v.lo[3] }, hi = { v.hi[1], v.hi[2], v.hi[3] } }
        end
    elseif spec.color then
        if not isRGB(v) then return nil end
        if not spec.alpha then return { v[1], v[2], v[3] } end
        local a = v[4]
        if a ~= nil and type(a) ~= "number" then return nil end
        return { v[1], v[2], v[3], max(0, min(1, a or 1)) }
    elseif type(spec[1]) == "number" then
        if type(v) == "number" and v == v then return max(spec[1], min(spec[2], floor(v + 0.5))) end
    elseif oneOf(spec, v) then
        return v
    end
end

-- Sets one look key, either for the whole chain (whole = true, which clears the
-- pieces' own values for that key) or for the piece (matching the chain's value
-- clears it). An icon's own size is the piece's size, as the skins read it.
function Data.SetLook(set, id, key, value, whole)
    local p, spec = set.pieces[id], Data.LOOK_FIELDS[key]
    if not (p and spec) then return false end
    value = check(spec, value)
    if value == nil then return false end
    Data.Changed()
    if whole then
        local c = Data.Chain(set, id)
        c.look[key] = unless(value, Data.LOOK[key])
        for _, q in ipairs(Data.Subtree(set, Data.Root(set, id))) do
            local qp = set.pieces[q]
            if type(qp.look) == "table" then qp.look[key] = nil end
            if key == "size" then qp.size = nil end
        end
        return true
    end
    local c, base = set.chains[Data.Root(set, id)], nil
    if type(c) == "table" and type(c.look) == "table" then base = c.look[key] end
    if base == nil then base = Data.LOOK[key] end
    -- A bar's name or time size equal to its group's text size goes back to unset.
    if base == nil and (key == "nameSize" or key == "timeSize") then base = Data.PieceLook(set, id, "text") end
    if key == "size" then
        p.size = unless(value, base)
        if type(p.look) == "table" then p.look.size = nil end
        return true
    end
    if type(p.look) ~= "table" then p.look = {} end
    p.look[key] = unless(value, base)
    if next(p.look) == nil then p.look = nil end
    return true
end

-- Sets one chain toggle (Data.CHAIN), from any piece in it. A new spacing applies to
-- every piece and clears their own gaps.
function Data.SetChainValue(set, id, key, value)
    local spec = Data.CHAIN_FIELDS[key]
    if not (set.pieces[id] and spec) then return false end
    value = check(spec, value)
    if value == nil then return false end
    Data.Changed()
    local c = Data.Chain(set, id)
    c[key] = unless(value, Data.CHAIN[key])
    if key == "spacing" then
        for _, q in ipairs(Data.Subtree(set, Data.Root(set, id))) do set.pieces[q].gap = nil end
    end
    return true
end

-- How a hooked piece sits on its side: align (start | center | end) or gap (0..16
-- px; equal to the chain's spacing clears it).
function Data.SetHookValue(set, id, key, value)
    local p = set.pieces[id]
    if not (p and p.parent ~= nil) then return false end
    if key == "align" then
        if not oneOf({ "start", "center", "end" }, value) then return false end
        p.align = value
    elseif key == "gap" then
        value = check({ 0, 16 }, value)
        if value == nil then return false end
        p.gap = unless(value, Data.ChainValue(set, id, "spacing"))
    else
        return false
    end
    Data.Changed()
    return true
end

-- Sets one spell option of a piece (Data.SPELL_FIELDS). Returns false when the
-- piece's shape doesn't take it or the value is bad.
function Data.SetSpellValue(set, id, key, value)
    local p, spec = set.pieces[id], Data.SPELL_FIELDS[key]
    local bar = p and p.shape == "bar"
    if not (p and spec) or (spec.icon and bar) or (spec.bar and not bar) then return false end
    if spec.bool then
        if type(value) ~= "boolean" then return false end
    elseif spec.gradient then
        if type(value) ~= "table" or not isRGB(value.lo) or not isRGB(value.hi) then return false end
        value = { lo = { value.lo[1], value.lo[2], value.lo[3] }, hi = { value.hi[1], value.hi[2], value.hi[3] } }
    elseif spec.color then
        if not isRGB(value) then return false end
        if spec.alpha then
            local a = value[4]
            if a ~= nil and type(a) ~= "number" then return false end
            value = { value[1], value[2], value[3], max(0, min(1, a or 1)) }
        else
            value = { value[1], value[2], value[3] }
        end
    elseif spec.values then
        if not oneOf(spec.values, value) then return false end
    elseif spec.sound then
        if not DUI.Sound.IsAlert(value) then return false end
    else
        if type(value) ~= "number" or value ~= value then return false end
        value = max(spec.min, min(spec.max, value))
    end
    if value == ns.CdmEffects.DEFAULTS[key] then value = nil end
    Data.Changed()
    p[key] = value
    return true
end

-- Shows a piece as an icon or a bar.
function Data.SetShape(set, id, shape)
    local p = set.pieces[id]
    if not p or (shape ~= "icon" and shape ~= "bar") then return false end
    if p.shape ~= shape then
        Data.Changed()
        p.shape = shape
    end
    return true
end

-- What a custom spell's piece (CdmCustom) shows: its cooldown or its buff/debuff.
-- The game's pieces (number keys) have no track.
Data.TRACKS = { "cooldown", "aura", "both" }
function Data.SetTrack(set, id, track)
    local p = set.pieces[id]
    if not (p and type(id) == "string" and oneOf(Data.TRACKS, track)) then return false end
    if p.track ~= track then
        Data.Changed()
        p.track = track
    end
    -- Buff missing's visibility only applies when showing the buff.
    if track == "cooldown" and (p.hideMissing or p.missing) then Data.Changed(); p.hideMissing, p.missing = nil, nil end
    return true
end

-- ---------------------------------------------------------------------
-- Old blocks (format 1), migrated once
-- ---------------------------------------------------------------------

-- An old block's shape, for blocks saved without some of these keys.
local OLD_ICON = { dir = "row", grow = "center", wrap = "down", size = 36, spacing = 4, perLine = 8 }
local OLD_BAR = { dir = "column", grow = "end", size = 18, width = 220, spacing = 2 }

local function old(block, key)
    local v = block[key]
    if v == nil then v = (block.kind == "bar" and OLD_BAR or OLD_ICON)[key] end
    return v
end

-- Offset from a w x h box's named point to its center (y up).
local function centreOffset(point, w, h)
    local dx, dy = 0, 0
    if point:find("LEFT") then dx = w / 2 elseif point:find("RIGHT") then dx = -w / 2 end
    if point:find("TOP") then dy = -h / 2 elseif point:find("BOTTOM") then dy = h / 2 end
    return dx, dy
end
Data.CentreOffset = centreOffset

-- The point of a block that stays put as it gains or loses items. The skins still
-- use it for a piece's block of one (TOPLEFT / TOP).
function Data.Anchor(block)
    local g = block.grow
    if block.kind == "bar" then
        return g == "start" and "TOP" or g == "end" and "BOTTOM" or "CENTER"
    end
    local v, h
    if block.dir == "column" then
        v = g == "start" and "TOP" or g == "end" and "BOTTOM" or ""
        h = block.wrap == "left" and "RIGHT" or "LEFT"
    else
        h = g == "start" and "LEFT" or g == "end" and "RIGHT" or ""
        v = block.wrap == "up" and "BOTTOM" or "TOP"
    end
    return v .. h
end

-- Each old block becomes a chain: its first spell where the block's first slot was
-- (the old layout frame sat at ox, oy), each next spell on the side the block grew
-- to, and a wrapped line's first spell beside the previous line's first. Spell
-- options stay on the piece. The old tables are kept in set.old as a way back.
function Data.Migrate(set, ox, oy)
    local blocks = type(set.blocks) == "table" and set.blocks or {}
    local buttons = type(set.buttons) == "table" and set.buttons or {}
    if next(blocks) ~= nil or next(buttons) ~= nil then
        set.old = { blocks = copy(blocks), buttons = copy(buttons) }
    end
    local pieces, chains = {}, {}
    set.pieces, set.chains = pieces, chains
    Data.Changed()
    for i, block in ipairs(blocks) do
        local list = {}
        for id, b in pairs(buttons) do
            if type(b) == "table" and b.block == i then list[#list + 1] = id end
        end
        table.sort(list, function(a, b)
            local oa, ob = tonumber(buttons[a].order) or 0, tonumber(buttons[b].order) or 0
            if oa ~= ob then return oa < ob end
            return a < b
        end)
        if #list > 0 then
            local bar = block.kind == "bar"
            local dir, grow = bar and "column" or old(block, "dir"), old(block, "grow")
            local size, gap = old(block, "size"), old(block, "spacing")
            local w = bar and old(block, "width") or size
            local per = bar and #list or max(1, old(block, "perLine") or 1)
            -- the direction spells go, and the direction a new line goes
            local along
            if dir == "column" then along = grow == "end" and "up" or "down"
            else along = grow == "end" and "left" or "right" end
            local across = dir == "column" and (old(block, "wrap") == "left" and "left" or "right")
                or (old(block, "wrap") == "up" and "up" or "down")
            -- the first slot's top-left on screen
            local count = #list
            local inLine = min(per, count)
            local step = size + gap
            local alongPx = (grow == "center") and -((inLine - 1) / 2) * step or 0
            local sx, sy
            if bar or dir == "column" then sx, sy = 0, -alongPx else sx, sy = alongPx, 0 end
            local a = Data.Anchor({ kind = block.kind, dir = dir, grow = grow, wrap = old(block, "wrap") })
            local cx, cy = centreOffset(a, w, size)
            local x = ox + (tonumber(block.x) or 0) + sx + cx - w / 2
            local y = oy + (tonumber(block.y) or 0) + sy + cy + size / 2
            local root = list[1]
            local lineFirst
            for n, id in ipairs(list) do
                local p = type(buttons[id]) == "table" and copy(buttons[id]) or {}
                p.block, p.order = nil, nil
                p.shape = bar and "bar" or "icon"
                pieces[id] = p
                if n == 1 then
                    p.x, p.y = floor(x + 0.5), floor(y + 0.5)
                    lineFirst = id
                elseif (n - 1) % per == 0 then
                    p.parent, p.side, p.align, p.gap = lineFirst, across, "start", gap
                    lineFirst = id
                else
                    p.parent, p.side, p.align, p.gap = list[n - 1], along, "center", gap
                end
            end
            local look = { size = not bar and size or nil, width = bar and w or nil, height = bar and size or nil,
                color = block.color, icon = block.icon, text = block.text, time = block.time }
            chains[root] = { look = look, grow = (grow == "center") and "center" or "start",
                combat = block.combat == true or nil, always = block.always == true or nil,
                collapse = block.collapse == false and false or nil }
        end
    end
    set.blocks, set.buttons = nil, nil
    set.v = Data.FORMAT
end
