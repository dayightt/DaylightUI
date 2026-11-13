-- A unit frame's aura groups: debuffs, crowd control and buffs, each in its own
-- client aura container placed by Spots. The client fixes a group's filter when
-- it's added and builds a batch of buttons at that point, so each "which"
-- choice is declared the first time it shows (Place, Auras.AddGroup), after the
-- group's settings are on its container, and then kept. Switching back only
-- changes counts. Settings live at <frame>.auras.<group>.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local AuraGroups = {}
ns.AuraGroups = AuraGroups

AuraGroups.DEFS = {
    { key = "debuffs", label = "Debuffs", kind = "gdebuff", choices = { "all", "dispel", "raid" },
      desc = "Harmful effects on them." },
    { key = "cc", label = "Crowd control", kind = "gcc", choices = { "cc" },
      desc = "Stuns, fears, roots and the like: one big icon in the middle by default." },
    { key = "buffs", label = "Buffs", kind = "tilebuff", choices = { "heals", "mine", "all" },
      desc = "Your heals over time and shields, everything you cast, or all of them. A class without heals or shields shows none." },
}
AuraGroups.BY_KEY = {}
for _, def in ipairs(AuraGroups.DEFS) do AuraGroups.BY_KEY[def.key] = def end

AuraGroups.CHOICE_LABELS = {
    debuffs = { all = "All debuffs", dispel = "Only ones I can dispel", raid = "Ones that matter in a fight" },
    buffs = { heals = "Heals and shields", mine = "Only mine", all = "All" },
}

-- Every setting of a group. Looks.lua resets all of them.
AuraGroups.FIELDS = { "show", "which", "spot", "grow", "size", "max", "rows", "spacing", "x", "y", "timers", "shortTimers", "swipe", "tooltips" }

-- Sample icons for stand-ins (options preview, /dui test), in the shape
-- Auras.DrawSample expects.
local I = "Interface\\Icons\\"
-- left: the fraction of time left, for the sweep.
AuraGroups.SAMPLES = {
    debuffs = {
        { icon = I .. "Spell_Shadow_ShadowWordPain", time = "14s", dispel = "Magic", left = 0.6 },
        { icon = I .. "Spell_Nature_CorrosiveBreath", time = "8s", dispel = "Poison", left = 0.35 },
        { icon = I .. "Spell_Shadow_CurseOfSargeras", time = "22s", dispel = "Curse", left = 0.8 },
        { icon = I .. "Ability_Gouge", time = "9s", count = 3, dispel = "Bleed", left = 0.5 },
    },
    cc = {
        { icon = I .. "Spell_Nature_Polymorph", time = "6s", dispel = "Magic", left = 0.4 },
    },
    buffs = {
        { icon = I .. "Spell_Nature_Rejuvenation", time = "12s", left = 0.7 },
        { icon = I .. "Spell_Nature_ResistNature", time = "28m", long = true, left = 0.95 },
        { icon = I .. "Spell_Holy_Renew", time = "9s", left = 0.3 },
        { icon = I .. "Spell_Holy_PowerWordShield", time = "25s", left = 0.55 },
    },
}

-- Where Place last put each container, for ShowSample.
local placed = setmetatable({}, { __mode = "k" })

-- How many sample icons sample tile i shows, like a real raid: most members
-- carry nothing, a few have a debuff, one is stunned.
AuraGroups.SAMPLE_COUNTS = {
    debuffs = { 1, 0, 2, 0, 0, 1, 0, 0 },
    cc = { 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 },
    buffs = { 1, 2, 3, 0 },
}

local function groupOf(def, choice)
    for _, g in ipairs(ns.Auras.KINDS[def.kind].groups) do
        if g.key == choice then return g end
    end
end

-- The client rejected this choice's filter, or it doesn't exist.
function AuraGroups.Refused(def, choice)
    local g = groupOf(def, choice)
    return g == nil or ns.Auras.REFUSED[g.filter] == true
end

-- Whether the choice can show here: not rejected, and not a spell list your
-- class lacks. The options still list it so one profile works for every character.
local function usable(def, choice)
    if AuraGroups.Refused(def, choice) then return false end
    local g = groupOf(def, choice)
    return g.ids == nil or g.ids() ~= nil
end
AuraGroups.Usable = usable

-- The choice to show when the picked one can't. Only a filter the client
-- refused falls back to another choice. "Heals and shields" on a class with no
-- heals or shields shows nothing: falling back to "Only mine" filled the row
-- with tracking and long buffs. A preview (sample) still shows the picked
-- choice, so the row can be seen and placed, like the heal indicators.
local function fallback(def, which, preview)
    if which and not AuraGroups.Refused(def, which) then return preview and which or nil end
    for _, c in ipairs(def.choices) do
        if usable(def, c) then return c end
    end
    return nil
end

-- The group (container group key) that shows for def, or nil when off.
-- preview: for a stand-in set (options preview, test mode).
function AuraGroups.ActiveKey(def, all, preview)
    local g = type(all) == "table" and all[def.key] or nil
    if type(g) ~= "table" or g.show ~= true then return nil end
    local which = g.which
    if def.key == "debuffs" and (which == nil or which == "all") then
        local cc = all.cc
        if type(cc) == "table" and cc.show == true and not AuraGroups.Refused(AuraGroups.BY_KEY.cc, "cc")
           and not AuraGroups.Refused(def, "notcc") then
            which = "notcc"
        end
    end
    if which and usable(def, which) then return which end
    return fallback(def, which, preview)
end

-- One container per group on frame, for unit (group buttons point theirs at
-- the unit later, GP.PointAuras). No groups yet, Place adds them.
function AuraGroups.Create(frame, unit)
    local set = { unit = unit }
    for _, def in ipairs(AuraGroups.DEFS) do
        local c = ns.Auras.NewContainer(frame, def.kind, "right", unit, false, nil, true)
        if not c then return nil end
        c:SetFrameLevel(frame:GetFrameLevel() + 8)
        set[def.key] = c
    end
    return set
end

-- Stand-ins for samples (options preview, /dui test). Placed by Place like a
-- real set but never filled by the client.
function AuraGroups.PlainSet(frame)
    local set = { plain = true }
    for _, def in ipairs(AuraGroups.DEFS) do
        local c = ns.Auras.Plain(frame)
        c.dluiKind = def.kind
        set[def.key] = c
    end
    return set
end

function AuraGroups.SetUnit(set, unit)
    if not set or type(unit) ~= "string" then return end
    set.unit = unit
    for _, c in AuraGroups.Containers(set) do
        pcall(c.SetUnit, c, unit)
        pcall(c.UpdateAllAuras, c)
    end
    ns.Indicators.SetUnit(set, unit)
end

-- Extra groups (Add piece): auras.x1..x4 (Defaults.lua), each debuffs or buffs
-- with its own filter. Their containers are created the first time a slot is
-- turned on (out of combat), one per kind, and kept for reuse. A slot turned
-- off or switched to the other kind just gets counts of 0.

-- The group def and filter a slot's settings g show, or nil when off.
function AuraGroups.ExtraActive(g, preview)
    if type(g) ~= "table" or g.show ~= true then return nil end
    local def = AuraGroups.BY_KEY[g.what == "buffs" and "buffs" or "debuffs"]
    local which = def.key == "buffs" and g.buffWhich or g.debuffWhich
    if which == nil or not usable(def, which) then which = fallback(def, which, preview) end
    if not which then return nil end
    return def, which
end

-- Every container of set as (def, c): the groups' first, then the extras'.
function AuraGroups.Containers(set)
    local list = {}
    if set then
        for _, def in ipairs(AuraGroups.DEFS) do
            if set[def.key] then list[#list + 1] = { def, set[def.key] } end
        end
        for _, key in ipairs(ns.AURA_SLOTS) do
            local slot = set.extra and set.extra[key]
            if slot then
                for _, def in ipairs(AuraGroups.DEFS) do
                    if slot[def.key] then list[#list + 1] = { def, slot[def.key] } end
                end
            end
        end
    end
    local i = 0
    return function()
        i = i + 1
        local e = list[i]
        if e then return e[1], e[2] end
    end
end

-- The slot's container for def, created now if possible: stand-ins any time,
-- client containers only out of combat since the parent may be protected.
local function extraContainer(set, frame, key, def)
    set.extra = set.extra or {}
    local slot = set.extra[key] or {}
    set.extra[key] = slot
    if slot[def.key] then return slot[def.key] end
    local c
    if set.plain then
        c = ns.Auras.Plain(frame)
        c.dluiKind = def.kind
    elseif not InCombatLockdown() then
        c = ns.Auras.NewContainer(frame, def.kind, "right", set.unit, false, nil, true)
        if c then
            c:SetFrameLevel(frame:GetFrameLevel() + 8)
            local unit = type(frame.unitToken) == "string" and frame.unitToken or set.unit
            if type(unit) == "string" then pcall(c.SetUnit, c, unit) end
        end
    end
    slot[def.key] = c
    return c
end

-- The room on frame for Spots.Layout. cfg is the frame's settings (power bar,
-- dispel icon). Matches the old tile buffs: T in from the sides, T + 1 from top
-- and bottom, the power bar strip kept clear, and a top row stopping short of
-- the dispel icon. A frame with a portrait ring (party bars) keeps clear of it
-- at the outer end, and one with a name tab keeps rows over the frame above
-- the tab, starting where the tab starts.
function AuraGroups.Box(frame, cfg)
    cfg = cfg or {}
    local T = Pixel.Px(frame, Style.BorderPx(frame))
    local cut = frame.cut or 0
    local side = frame.spec and frame.spec.slant
    local tab = frame.tab
    local tabOn = tab ~= nil and tab:IsShown() == true
    local ringIn, reach = frame.ringInset or 0, frame.ringReach or 0
    -- A tab moved off the outer end (UF.ReadTab) makes rows start at the ring.
    local tabOuter = tabOn and (frame.tabAt or "outer") == "outer"
    local aboveIn = tabOuter and (frame.tabInset or ns.UF.TAB_INSET) or ringIn
    -- A tab lifted off the frame (tab.y) is kept clear of too.
    local tabLift = tabOn and math.max(0, frame.tabY or 0) or 0
    -- The ring sits at the outer end, which is the left unless the angled end is there.
    local outerL = side ~= "left"
    -- Icons sit in the corners on frames that always put them there (raid
    -- tiles), or on party buttons in corner mode.
    local cornered = not (frame.spec and frame.spec.cornerIcons) or frame.cornerMode == true
    local box = {
        w = frame:GetWidth(), h = frame:GetHeight(), padX = T, padY = T + 1,
        cutL = side == "left" and cut or 0, cutR = side == "right" and cut or 0,
        topInset = 0,
        -- Ribbon's power is a line under the frame (f.foot), not inside it.
        bottomInset = (ns.UF.ShowsPower(cfg) and not frame.ribbon) and (cfg.powerHeight or 0) + 1 or 0,
        topReserve = cfg.showDispel and (cfg.dispelSize or 0) + 2 or 0,
        above = tabOn and (frame.tabHeight or 0) + tabLift or 0, below = frame.foot or 0,
        outL = outerL and reach or 0, outR = outerL and 0 or reach,
        aboveInL = outerL and aboveIn or 0, aboveInR = outerL and 0 or aboveIn,
        belowInL = outerL and ringIn or 0, belowInR = outerL and 0 or ringIn,
        -- A party button with a home only keeps clear what was moved off it.
        corners = AuraGroups.Corners(cfg, not cornered),
    }
    -- Party pets (PartyPets.lua): a row on the pet's side starts past it.
    local spot, pw, ph = nil, 0, 0
    if frame.spec and frame.spec.pets then spot, pw, ph = ns.PartyPets.Room() end
    if spot == "right" then box.outR = box.outR + pw + ns.PartyPets.GAP
    elseif spot == "left" then box.outL = box.outL + pw + ns.PartyPets.GAP
    elseif spot == "below" then box.below = box.below + ph + ns.PartyPets.GAP
    elseif spot == "above" then box.above = box.above + ph + ns.PartyPets.GAP end
    return box
end

-- The frame's own icons that sit at a spot when shown (role, marker, leader,
-- dispel), as { [spot] = size + 1 }, so a row there starts past them. Reserved
-- whether or not the icon is showing, so rows don't jump.
-- homed: the frame has a name tab or portrait, so only a role, marker or crown
-- moved to a spot counts. Otherwise an icon at home sits at its corner.
local CORNER_ICONS = { { "showRole", "rolePos", "roleSize" }, { "showMarker", "markerPos", "markerSize" },
                       { "showLeader", "leaderPos", "leaderPx" }, { "showDispel", "dispelPos", "dispelSize" } }
AuraGroups.CORNER_ICONS = CORNER_ICONS
function AuraGroups.Corners(cfg, homed)
    local out = {}
    for _, k in ipairs(CORNER_ICONS) do
        local spot, size = cfg[k[2]], tonumber(cfg[k[3]])
        if spot == ns.UF.ICON_HOME then spot = not homed and ns.UF.HOME_CORNER[k[2]] or nil
        elseif homed and k[1] == "showDispel" then spot = nil end
        if cfg[k[1]] == true and type(spot) == "string" and size then
            out[spot] = math.max(out[spot] or 0, size + 1)
        end
    end
    return out
end

-- One container placed from its group's settings g. on is the filter shown,
-- or nil for none (counts of 0).
local function placeOne(c, def, g, on, frame, box)
    local gap = tonumber(g.spacing) or 2
    local s = ns.Auras.SetOwnSize(c, tonumber(g.size) or 14, gap)
    local max = on and math.max(0, math.floor(tonumber(g.max) or 0)) or 0
    local rows = math.max(1, math.floor(tonumber(g.rows) or 1))
    local per = math.max(1, math.ceil(math.max(max, 1) / rows))
    local L = ns.Spots.Layout(g.spot, g.grow, box,
        { x = g.x, y = g.y, line = per * (s[1] + gap) - gap })
    -- Under the frame, the numbers on each icon's top edge need room.
    local spot = type(g.spot) == "string" and g.spot or ""
    if g.timers == true and (spot == "below" or spot:find("^outbottom")) then
        L.y = L.y - ns.Auras.TIME_SIZE[def.kind] * 0.6
    end
    local real = not ns.Auras.IsPlain(c)
    -- Settings first, since a group added now builds its buttons from them.
    ns.Auras.SetTimers(c, g.timers == true)
    ns.Auras.SetShortTimers(c, g.shortTimers == true)
    ns.Auras.SetSwipe(c, g.swipe == true)
    ns.Auras.SetTips(c, g.tooltips == true)
    if real and on then ns.Auras.AddGroup(c, on) end
    if def.kind == "tilebuff" then
        ns.Auras.SetBuffCounts(c, { showBuffs = on ~= nil, buffFilter = on }, max)
    elseif real then
        for _, kg in ipairs(ns.Auras.KINDS[def.kind].groups) do
            if c.dluiGroups[kg.key] then
                pcall(c.SetAuraGroupMaxFrameCount, c, kg.key, kg.key == on and max or 0)
            end
        end
    end
    ns.Auras.SetFlow(c, L.flowAnchor, L.hDir, L.vDir, L.line)
    c:ClearAllPoints()
    c:SetPoint(L.point, frame, L.relPoint, L.x, L.y)
    c:SetSize(math.max(1, L.line), s[2])
    if real then pcall(c.UpdateAllAuras, c) end
    placed[c] = { L = L, on = on, max = max, per = per, s = s, gap = gap, timers = g.timers == true,
                  shortTimers = g.shortTimers == true, swipe = g.swipe == true, def = def }
end

-- The parent is protected (a group button), so out of combat only. Extra group
-- containers are created here too.
function AuraGroups.Place(set, frame, all, box)
    if not set then return end
    for _, def in ipairs(AuraGroups.DEFS) do
        local c = set[def.key]
        if c then
            local g = type(all) == "table" and type(all[def.key]) == "table" and all[def.key] or {}
            placeOne(c, def, g, AuraGroups.ActiveKey(def, all, set.plain), frame, box)
        end
    end
    for _, key in ipairs(ns.AURA_SLOTS) do
        local g = type(all) == "table" and type(all[key]) == "table" and all[key] or nil
        local active, which = AuraGroups.ExtraActive(g, set.plain)
        if active then extraContainer(set, frame, key, active) end
        local slot = set.extra and set.extra[key]
        for _, def in ipairs(AuraGroups.DEFS) do
            local c = slot and slot[def.key]
            if c then placeOne(c, def, g or {}, def == active and which or nil, frame, box) end
        end
    end
end

-- A stand-in set (PlainSet) placed like a real one and filled with sample
-- icons: each shown group's max (capped by its list), or for sample tile i,
-- the count SAMPLE_COUNTS gives.
function AuraGroups.ShowSample(set, frame, all, box, i)
    if not set then return end
    AuraGroups.Place(set, frame, all, box)
    for def, c in AuraGroups.Containers(set) do
        local p = placed[c]
        if p then
            local list = AuraGroups.SAMPLES[def.key]
            if p.on == "heals" then   -- no long buffs (Mark) among heals and shields
                local short = {}
                for _, s in ipairs(list) do if not s.long then short[#short + 1] = s end end
                list = short
            end
            local n = p.on and math.min(p.max, #list) or 0
            local counts = i and AuraGroups.SAMPLE_COUNTS[def.key]
            if counts then n = math.min(n, counts[(i - 1) % #counts + 1]) end
            local fits = math.max(1, math.floor((p.L.line + p.gap) / (p.s[1] + p.gap)))
            ns.Auras.DrawSample(c, list, n, def.kind, { anchor = p.L.flowAnchor, hDir = p.L.hDir,
                                                         vDir = p.L.vDir, perRow = math.min(p.per, fits),
                                                         timers = p.timers, shortTimers = p.shortTimers,
                                                         swipe = p.swipe })
        end
    end
end

function AuraGroups.HideSample(set)
    if not set then return end
    for _, c in AuraGroups.Containers(set) do
        for _, btn in ipairs(c.pool or {}) do btn:Hide() end
        c:Hide()
    end
end

-- Fills Auras.REFUSED once so the options know before any frame exists.
do
    local probe = CreateFrame("Frame")
    probe:Hide()
    for _, def in ipairs(AuraGroups.DEFS) do
        if def.kind ~= "tilebuff" then ns.Auras.NewContainer(probe, def.kind, "right", "player", false) end
    end
end
