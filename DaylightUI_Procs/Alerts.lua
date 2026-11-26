-- Each proc's own settings. They live in one table, `alerts[procKey][field]`,
-- holding only what differs from that proc's default, so a default changed in
-- a later version reaches everyone who never touched it.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Alerts = {}
ns.Alerts = Alerts

-- The default "Two colors of my own" are the Daylight sweep's two ends.
local DAY_LO, DAY_HI = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]

-- What one proc can change, and its default (a function reads the proc's own).
Alerts.FIELDS = {
    enabled = function(p) return not p.off end,
    design = function(p) return p.design end,
    anim = function(p) return p.anim end,
    speed = 1,
    embers = true,
    colorMode = "accent",
    colorTop = function() return { DAY_HI[1], DAY_HI[2], DAY_HI[3] } end,
    colorBottom = function() return { DAY_LO[1], DAY_LO[2], DAY_LO[3] } end,
    size = 1,
    alpha = 1,
    x = 0,
    y = 0,
    sound = function(p) return p.sound or "file:568016" end,
    combatOnly = function(p) if p.combatOnly == false then return false end return true end,
    drain = false,
    fromStacks = function(p) return p.fromStacks or p.stacks or 1 end,
}

-- The fields "Copy this look to my other alerts" copies. Not the design, so
-- every alert still looks different.
Alerts.LOOK = { "anim", "speed", "embers", "colorMode", "colorTop", "colorBottom", "size", "alpha", "sound" }

local function saved()
    local t = DUI:Get("Procs", "alerts")
    if type(t) == "table" then return t end
end

function Alerts.Default(key, field)
    local p = ns.Data.BY[key]
    local d = Alerts.FIELDS[field]
    if type(d) == "function" then return p and d(p) end
    return d
end

function Alerts.Get(key, field)
    local t = saved()
    local mine = t and t[key]
    if type(mine) == "table" and mine[field] ~= nil then return mine[field] end
    return Alerts.Default(key, field)
end

local function same(a, b)
    if type(a) == "table" and type(b) == "table" then
        for i = 1, 3 do
            if math.abs((a[i] or 0) - (b[i] or 0)) > 1e-4 then return false end
        end
        return true
    end
    return a == b
end

-- A copy of the saved table, so DUI:Set sees a new value and fires.
local function copy()
    local out = {}
    for k, v in pairs(saved() or {}) do
        if type(v) == "table" then
            local inner = {}
            for f, x in pairs(v) do inner[f] = x end
            out[k] = inner
        end
    end
    return out
end

local function write(t)
    for k, v in pairs(t) do
        if next(v) == nil then t[k] = nil end
    end
    DUI:Set("Procs", "alerts", t)
end

function Alerts.Set(key, field, value)
    local t = copy()
    local mine = t[key] or {}
    if same(value, Alerts.Default(key, field)) then value = nil end
    if type(value) == "table" then value = { value[1], value[2], value[3] } end
    mine[field] = value
    t[key] = mine
    write(t)
end

function Alerts.Reset(key)
    local t = copy()
    t[key] = nil
    write(t)
end

-- Copies one alert's look onto the player's other alerts (not their designs).
function Alerts.CopyToClass(key)
    local t = copy()
    for _, p in ipairs(ns.Data.Mine()) do
        if p.key ~= key then
            local mine = t[p.key] or {}
            for _, field in ipairs(Alerts.LOOK) do
                local v = Alerts.Get(key, field)
                if same(v, Alerts.Default(p.key, field)) then v = nil end
                if type(v) == "table" then v = { v[1], v[2], v[3] } end
                mine[field] = v
            end
            t[p.key] = mine
        end
    end
    write(t)
end

local function lift(c, k)
    return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

-- A proc's two colors, bottom (lo) and top (hi), each { r, g, b }, read now.
function Alerts.Colors(key)
    local mode = Alerts.Get(key, "colorMode")
    if mode == "custom" then
        local lo, hi = Alerts.Get(key, "colorBottom"), Alerts.Get(key, "colorTop")
        if type(lo) == "table" and type(hi) == "table" then return lo, hi end
    elseif mode == "class" then
        local token = ns.Data.Class()
        local G = DUI.Gradients
        if token and G and G.RGB and not G.Flat() then
            local lo, hi = G.RGB(token)
            if lo and hi then
                return { lo[1] + (hi[1] - lo[1]) * Style.CLASS_LIFT, lo[2] + (hi[2] - lo[2]) * Style.CLASS_LIFT,
                         lo[3] + (hi[3] - lo[3]) * Style.CLASS_LIFT }, hi
            end
        end
        local c = { Style.ClassColor(token) }
        return c, lift(c, 0.35)
    end
    local lo, hi = Style.AccentPair()
    if lo and hi then return lo, hi end
    local c = { Style.Accent() }
    return c, c
end
