-- The list of meter windows and where each one's settings live. "main" (the
-- panel's damage meter, meter.*) and "threat" (threat.*) always exist and can
-- only be switched off. Up to Windows.MAX more are player-made from a preset,
-- with settings in meters.windows.<id>. Order is meters.order.
--
-- A window's settings are merged from its kind's template (Windows.TEMPLATE) at
-- creation and login, and stripped back to the differences at logout, so a
-- template change reaches every window that wasn't edited.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Windows = {}
ns.Windows = Windows

Windows.MAX = 10              -- windows of the player's own, the two built in aside
Windows.KINDS = { meter = true, threat = true, summary = true }

-- Each kind's settings, as a new window starts.
Windows.TEMPLATE = {
    meter = { enabled = true, name = "", mode = "damage", session = "current",
              inGroup = false, inCombat = false, inInstance = false,
              width = 207, height = 196, border = true, rowHeight = 22, textSize = 11,
              barColor = "class", gradient = true, barCustom = { 0.72, 0.70, 0.66 }, nameColor = { 1, 1, 1 },
              classText = false, trackAlpha = 1, alphaOwn = false, alpha = 0.85,
              rank = false, icons = "spec", showTotal = true, showRate = true, showShare = true, showMe = true,
              rowGap = 1, header = "always", headerTotal = false, angled = true },
    -- auto: group (in a fight when someone else can hold the mob) | tank
    -- (only as the tank); unit: target | focus | smart (your target, else
    -- your target's target). The rest as the threat meter's own.
    threat = { enabled = true, name = "", auto = "group", unit = "target", header = "always",
               rows = 6, rowHeight = 16, textSize = 10, width = 170, border = true, alphaOwn = false, alpha = 0.85,
               barColor = "class", gradient = true, barCustom = { 0.72, 0.70, 0.66 }, nameColor = { 1, 1, 1 },
               trackAlpha = 0.35, angled = true, pullLine = true, pullColor = { DUI.Style.INK.BAD[1], DUI.Style.INK.BAD[2], DUI.Style.INK.BAD[3] } },
    -- columns: which numbers it shows; sort / sortDesc: by which.
    summary = { enabled = true, name = "", session = "current", inGroup = false, inCombat = false, inInstance = false,
                columns = { damage = true, dps = true, healing = true, hps = true, interrupts = true, dispels = true, deaths = true },
                sort = "damage", sortDesc = true, width = 420, height = 196, rowHeight = 20, textSize = 13, border = true, alphaOwn = false, alpha = 0.85 },
}

-- What "New window" offers, in its order: a kind, and what it starts as.
-- label/name: English, drawn through L.
Windows.PRESETS = {
    { key = "damage", kind = "meter", label = "Damage", icon = "damage", set = { mode = "damage" } },
    { key = "healing", kind = "meter", label = "Healing", icon = "healing", set = { mode = "healing" } },
    { key = "taken", kind = "meter", label = "Damage taken", icon = "taken", set = { mode = "taken" } },
    { key = "deaths", kind = "meter", label = "Deaths", icon = "deaths", set = { mode = "deaths" } },
    { key = "interrupts", kind = "meter", label = "Interrupts", icon = "interrupts", set = { mode = "interrupts" } },
    { key = "enemy", kind = "meter", label = "Enemy damage taken", icon = "enemy", set = { mode = "enemy" } },
    { key = "threat", kind = "threat", label = "Threat", icon = "threat", set = {} },
    { key = "summary", kind = "summary", label = "Fight summary", icon = "summary", set = {} },
}
Windows.PRESET = {}
for _, p in ipairs(Windows.PRESETS) do Windows.PRESET[p.key] = p end

local BUILTIN = {
    main = { kind = "meter", path = "meter" },
    threat = { kind = "threat", path = "threat" },
}
Windows.BUILTIN_ORDER = { "main", "threat" }

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

local function db() return ns.module and ns.module.db end

-- The saved list (made when missing: an old profile).
local function meters(d)
    d = d or db()
    if not d then return nil end
    if type(d.meters) ~= "table" then d.meters = {} end
    local m = d.meters
    if type(m.windows) ~= "table" then m.windows = {} end
    if type(m.order) ~= "table" then m.order = {} end
    return m
end

-- Where a window's settings live, inside the module's.
function Windows.Path(id)
    local b = BUILTIN[id]
    if b then return b.path end
    return "meters.windows." .. tostring(id)
end

-- Defaults for any key under meters.windows.<id>, from its kind's template.
-- Options.Default and DB.GetPath read through this. pairs() doesn't see it, so
-- merging and stripping stay with Windows.Fill / Windows.Strip.
function Windows.TemplateFor(id)
    local m = meters()
    local w = m and m.windows[id]
    local kind = type(w) == "table" and Windows.KINDS[w.kind] and w.kind or "meter"
    return Windows.TEMPLATE[kind]
end

-- Each of the player's windows with every setting its template has.
function Windows.Fill(d)
    local m = meters(d)
    if not m then return end
    for id, w in pairs(m.windows) do
        if type(w) ~= "table" or not Windows.KINDS[w.kind] then
            m.windows[id] = nil
        else
            -- A value of the wrong kind (a damaged import, an old build) goes
            -- back to the template's: the layout reads sizes as numbers.
            for k, v in pairs(Windows.TEMPLATE[w.kind]) do
                if w[k] ~= nil and type(w[k]) ~= type(v) then w[k] = nil end
            end
            DUI.DB.MergeDefaults(w, Windows.TEMPLATE[w.kind])
        end
    end
    -- The order lists each window once, and only those there are.
    local seen, order = {}, {}
    for _, id in ipairs(m.order) do
        if m.windows[id] and not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    for id in pairs(m.windows) do
        if not seen[id] then order[#order + 1] = id end
    end
    m.order = order
end

-- Back to what differs from the template (logout), every profile's.
function Windows.Strip(m)
    if type(m) ~= "table" or type(m.windows) ~= "table" then return end
    for _, w in pairs(m.windows) do
        if type(w) == "table" and Windows.KINDS[w.kind] then
            local kind = w.kind
            DUI.DB.StripDefaults(w, Windows.TEMPLATE[kind])
            w.kind = kind
        end
    end
end
function Windows.StripAll()
    local sv = _G.DaylightUIDB
    if type(sv) ~= "table" or type(sv.profileData) ~= "table" then return end
    for _, p in pairs(sv.profileData) do
        local ip = type(p) == "table" and type(p.modules) == "table" and p.modules.InfoPanel
        if type(ip) == "table" then Windows.Strip(ip.meters) end
    end
end
-- Last, as the DB's own: every other logout handler still reads full settings.
DUI.RegisterEvent("PLAYER_LOGOUT", Windows.StripAll, true)

-- Every window, built-in ones first, then the player's in their order:
-- { id, kind, cfg (its live settings), builtin, path }.
function Windows.List(d)
    d = d or db()
    local out = {}
    if not d then return out end
    for _, id in ipairs(Windows.BUILTIN_ORDER) do
        local b = BUILTIN[id]
        out[#out + 1] = { id = id, kind = b.kind, cfg = d[b.path], builtin = true, path = b.path }
    end
    local m = meters(d)
    for _, id in ipairs(m.order) do
        local w = m.windows[id]
        if type(w) == "table" then
            out[#out + 1] = { id = id, kind = w.kind, cfg = w, builtin = false, path = Windows.Path(id) }
        end
    end
    return out
end

-- The player's windows only.
function Windows.Own(d)
    local out = {}
    for _, e in ipairs(Windows.List(d)) do
        if not e.builtin then out[#out + 1] = e end
    end
    return out
end

function Windows.Get(d, id)
    for _, e in ipairs(Windows.List(d)) do
        if e.id == id then return e end
    end
end

-- A window's name: its own, else its preset's, else its mode's.
function Windows.Name(e)
    if type(e) ~= "table" then return "" end
    local n = e.cfg and e.cfg.name
    if type(n) == "string" and n ~= "" then return n end
    if e.id == "main" then return L["Damage meter"] end
    if e.id == "threat" or e.kind == "threat" then return L["Threat meter"] end
    if e.kind == "summary" then return L["Fight summary"] end
    local p = e.cfg and Windows.PRESET[e.cfg.preset]
    if p then return L[p.label] end
    return L["Meter"]
end

local function changed() DUI.Fire("MeterWindowsChanged") end

-- A new window from a preset (Windows.PRESETS' key): its id, or nil when
-- there are Windows.MAX already. Shown at once.
function Windows.Add(presetKey)
    local p = Windows.PRESET[presetKey]
    local m = meters()
    if not (p and m) then return nil end
    if #m.order >= Windows.MAX then return nil end
    local n = math.max(1, tonumber(m.next) or 1)
    local id = "w" .. n
    while m.windows[id] do
        n = n + 1
        id = "w" .. n
    end
    m.next = n + 1
    local w = copy(Windows.TEMPLATE[p.kind])
    for k, v in pairs(p.set) do w[k] = copy(v) end
    w.kind, w.preset = p.kind, p.key
    m.windows[id] = w
    m.order[#m.order + 1] = id
    DUI:Set("InfoPanel", "meters.order", m.order)
    changed()
    return id
end

-- The two built in can't be removed (false).
function Windows.Remove(id)
    if BUILTIN[id] then return false end
    local m = meters()
    if not (m and m.windows[id]) then return false end
    m.windows[id] = nil
    for i = #m.order, 1, -1 do
        if m.order[i] == id then table.remove(m.order, i) end
    end
    -- Its spot and its own size go too (ids are never used again).
    local key = "infopanel.meter." .. id
    DUI.DB.Positions()[key] = nil
    local scales = DUI.DB.General().frameScales
    if type(scales) == "table" then scales[key] = nil end
    DUI:Set("InfoPanel", "meters.order", m.order)
    changed()
    return true
end

function Windows.Rename(id, name)
    local e = Windows.Get(nil, id)
    if not e then return false end
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    DUI:Set("InfoPanel", e.path .. ".name", name)
    local mover = DUI.Movers.Get("infopanel.meter." .. id)
    if mover then mover.label = Windows.Name(Windows.Get(nil, id)) end
    changed()
    return true
end

-- One step up (delta -1) or down (1) the player's list.
function Windows.Move(id, delta)
    local m = meters()
    if not m then return false end
    for i, x in ipairs(m.order) do
        if x == id then
            local j = i + delta
            if j < 1 or j > #m.order then return false end
            m.order[i], m.order[j] = m.order[j], m.order[i]
            DUI:Set("InfoPanel", "meters.order", m.order)
            changed()
            return true
        end
    end
    return false
end

-- The General page's "Apply" resets every window background to the General
-- value. Options.ApplyWindowAlpha only knows fixed settings, so player-made
-- windows are handled here.
DUI.On("WindowAlphaApplied", function()
    for _, e in ipairs(Windows.Own()) do
        if e.cfg.alphaOwn == true then DUI:Set("InfoPanel", e.path .. ".alphaOwn", false) end
    end
end)

-- ---------------------------------------------------------------------
-- Migration: the old second meter (meter2.*) becomes window "w2" if it was
-- ever switched on or changed, keeping its settings and the visibility rules
-- it used to inherit from the first meter.
-- ---------------------------------------------------------------------

function Windows.Upgrade(p)
    if type(p) ~= "table" or p.meters1 or type(p.modules) ~= "table" then return end
    p.meters1 = true
    local ip = p.modules.InfoPanel
    if type(ip) ~= "table" then return end
    local old = ip.meter2
    ip.meter2 = nil
    if type(old) ~= "table" or next(old) == nil then return end
    local w = {}
    for k, v in pairs(old) do w[k] = copy(v) end
    if w.enabled == nil then w.enabled = false end   -- the old default
    if w.mode == nil then w.mode = "healing" end     -- the old default
    local first = type(ip.meter) == "table" and ip.meter or {}
    if first.inGroup == true then w.inGroup = true end
    if first.inCombat == true then w.inCombat = true end
    w.kind, w.preset = "meter", Windows.PRESET[w.mode] and w.mode or "damage"
    if type(ip.meters) ~= "table" then ip.meters = {} end
    local m = ip.meters
    if type(m.windows) ~= "table" then m.windows = {} end
    if type(m.order) ~= "table" then m.order = {} end
    -- "w2" (it was the second meter), unless that's already a window of the
    -- player's (a profile that went back to an older build and came back).
    local n = 2
    while m.windows["w" .. n] do n = n + 1 end
    local id = "w" .. n
    m.windows[id] = w
    table.insert(m.order, 1, id)
    m.next = math.max(tonumber(m.next) or 1, n + 1)
    -- Its spot and its own size in unlock mode go with it.
    local key = "infopanel.meter." .. id
    if type(p.positions) == "table" and p.positions["infopanel.meter2"] ~= nil then
        p.positions[key], p.positions["infopanel.meter2"] = p.positions["infopanel.meter2"], nil
    end
    local scales = type(p.general) == "table" and p.general.frameScales
    if type(scales) == "table" and scales["infopanel.meter2"] ~= nil then
        scales[key], scales["infopanel.meter2"] = scales["infopanel.meter2"], nil
    end
end
DUI.DB.RegisterUpgrade(Windows.Upgrade)
