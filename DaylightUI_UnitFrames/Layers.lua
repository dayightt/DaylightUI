-- Layers: which part of a unit frame draws over which, where parts overlap.
-- Each part (the name tab, portrait, portrait icons, aura rows, and the pieces
-- that can stand on their own) has an Order, its frame level above its unit
-- frame, and, while it stands on its own, a Layer (strata, or "FRAME" to draw
-- with its frame). Saved as <unit>.parts.<key> = { order = n, layer = s }.
-- Nothing is set until a player changes it: an untouched part keeps the level
-- its own code gives it, and its Order shows that level.
-- Party, raid and arena tiles aren't covered.

local _, ns = ...
local DUI = DaylightUI

local Layers = {}
ns.Layers = Layers

Layers.MIN, Layers.MAX = 1, 60
Layers.STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                       FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function frameOf(unit) return unit == "personal" and ns.Personal.frame or (ns.frames and ns.frames[unit]) end

local function auraRows(set)
    if type(set) ~= "table" then return nil end
    local out = {}
    if set.debuffs then out[#out + 1] = set.debuffs end
    if set.buffs then out[#out + 1] = set.buffs end
    return out
end

local function db() return ns.module and ns.module.db end

-- Whether a piece stands on its own (on UIParent), so it can take a Layer.
local function powerFree(unit) local d = db(); return d and d[unit] and d[unit].powerAt == "free" end
local function castFree(unit)
    local d = db()
    return d and ns.CastBar.At(unit, d[unit .. "Castbar"]) ~= "power"
end

-- The parts each frame has. get(f) returns the part's frame or a list of them.
-- free(f) is true while it stands on its own; mover names its unlock handle.
local NAME = { key = "name", label = "Name tab", get = function(f) return f.tabClip end }
local PORTRAIT = { key = "portrait", label = "Portrait",
    get = function(f) return f.portraitFree and f.portraitHolder or f.portrait end,
    free = function(f) return f.portraitFree == true end,
    mover = function(f) return f.portraitHolder and f.portraitHolder.key end }
-- The icons ride 6 levels over the portrait (UF.HomePortrait) unless given an
-- order of their own.
local ICONS = { key = "icons", label = "Portrait icons and level", get = function(f) return f.status end,
    follows = "portrait", over = 6 }
local function auras(field)
    return { key = "auras", label = "Aura rows", get = function() return auraRows(ns[field]) end }
end
local function power(unit)
    return { key = "power", label = "Power bar", get = function(f) return f.freePower end,
             free = function() return powerFree(unit) end,
             mover = function() return ns.PowerBar.KeyFor(unit) end }
end
local function castbar(unit, field)
    return { key = "castbar", label = "Cast bar", get = function() return ns[field] end,
             free = function() return castFree(unit) end, ownLayer = true,
             mover = function() return "unitframes." .. unit .. "Castbar" end }
end

Layers.PARTS = {
    player = { NAME, PORTRAIT, ICONS, auras("playerAuras"), power("player"),
               { key = "druid", label = "Druid bars", get = function() return _G.DaylightUIDruidBars end,
                 free = function() return true end, mover = function() return ns.DruidBars.KEY end },
               castbar("player", "playerCastbar") },
    target = { NAME, PORTRAIT, ICONS, auras("auras"), power("target"),
               { key = "threat", label = "Threat %", get = function(f) return f.threatHolder end,
                 free = function(f) return f.threatTag ~= nil and f.threatTag:GetParent() == f.threatHolder end,
                 mover = function() return ns.UF.THREAT_KEY end },
               { key = "combo", label = "Combo points", get = function() return ns.combo and ns.combo.holder end,
                 free = function() local d = db(); return d and d.combo and d.combo.anchor == "free" end,
                 mover = function() return ns.Combo.KEY end },
               castbar("target", "targetCastbarFree") },
    focus = { NAME, PORTRAIT, ICONS, auras("focusAuras"), power("focus"), castbar("focus", "focusCastbarFree") },
    pet = { NAME, auras("petAuras") },
    personal = { { key = "auras", label = "Aura rows", get = function() return auraRows(ns.Personal.auras) end } },
}

local function list(v)
    if type(v) ~= "table" then return {} end
    if v.GetFrameLevel then return { v } end
    return v
end

function Layers.Find(unit, key)
    for _, part in ipairs(Layers.PARTS[unit] or {}) do
        if part.key == key then return part end
    end
end

-- The saved choice for a part, or nil.
function Layers.Saved(unit, key)
    local d = db()
    local p = d and d[unit] and d[unit].parts
    return type(p) == "table" and type(p[key]) == "table" and p[key] or nil
end

-- A part's Order as it draws now: its level above its unit frame.
function Layers.OrderOf(unit, key)
    local s = Layers.Saved(unit, key)
    if s and tonumber(s.order) then return tonumber(s.order) end
    local f, part = frameOf(unit), Layers.Find(unit, key)
    local first = part and f and list(part.get(f))[1]
    if not first then return Layers.MIN end
    local home = first.layerHome or first:GetFrameLevel()
    return math.max(Layers.MIN, math.min(Layers.MAX, home - f:GetFrameLevel()))
end

-- Sets one frame's level and keeps everything inside it at its offset (the
-- portrait's ring over its model, a tab's crest over the tab).
local function setLevel(frame, level)
    if frame.layerHome == nil then frame.layerHome = frame:GetFrameLevel() end
    ns.UF.NoteLevels(frame)
    frame:SetFrameLevel(math.max(0, level))
    ns.UF.Relevel(frame)
end

local function restore(frame)
    if frame.layerHome == nil then return end
    ns.UF.NoteLevels(frame)
    frame:SetFrameLevel(frame.layerHome)
    ns.UF.Relevel(frame)
    frame.layerHome = nil
end

-- Applies every saved Order and Layer. Runs at the end of each refresh, after
-- the frames' own code has placed their parts. Protected parents: out of combat.
function Layers.Apply()
    for unit, parts in pairs(Layers.PARTS) do
        local f = frameOf(unit)
        if f then
            for _, part in ipairs(parts) do
                local s = Layers.Saved(unit, part.key)
                local order = s and tonumber(s.order)
                local lead = not order and part.follows and Layers.Saved(unit, part.follows)
                local leadFrame = lead and tonumber(lead.order) and list(Layers.Find(unit, part.follows).get(f))[1]
                for _, frame in ipairs(list(part.get(f))) do
                    if order then
                        setLevel(frame, f:GetFrameLevel() + math.max(Layers.MIN, math.min(Layers.MAX, order)))
                    elseif leadFrame then
                        setLevel(frame, leadFrame:GetFrameLevel() + part.over)
                    else
                        restore(frame)
                    end
                    local layer = s and s.layer
                    if part.free and not part.ownLayer and part.free(f) and type(layer) == "string" and layer ~= "FRAME"
                        and ns.STRATA_LABELS[layer] then
                        frame:SetFrameStrata(layer)
                    end
                end
            end
        end
    end
end

-- Saves a part's Order and Layer and redraws. nil clears one.
function Layers.Set(unit, key, order, layer)
    local path = unit .. ".parts." .. key
    DUI:Set("UnitFrames", path .. ".order", order)
    if layer ~= false then DUI:Set("UnitFrames", path .. ".layer", layer) end
end

-- The frame level and strata rank a frame really draws at: its own, or the
-- highest frame inside it.
local function topOf(frame)
    local top = frame:GetFrameLevel()
    for _, c in ipairs({ frame:GetChildren() }) do
        if c:IsShown() then top = math.max(top, topOf(c)) end
    end
    return top
end
Layers.TopOf = topOf

-- Unlock's Bring forward / Send back for a part with a handle. others is a
-- list of overlapping frames. Returns the new Order and Layer, or nil and why.
function Layers.Step(unit, key, others, up)
    local f, part = frameOf(unit), Layers.Find(unit, key)
    local mine = part and f and list(part.get(f))[1]
    if not mine then return nil, "missing" end
    local rank = Layers.STRATA_RANK
    local myRank, myLow, myTop = rank[mine:GetFrameStrata()] or 3, mine:GetFrameLevel(), topOf(mine)
    -- The nearest frame above (or below) this one, by strata then level.
    local pick, pickRank, pickLevel
    for _, o in ipairs(others) do
        local r = rank[o:GetFrameStrata()] or 3
        local lo, hi = o:GetFrameLevel(), topOf(o)
        if up then
            local above = r > myRank or (r == myRank and hi >= myLow)
            if above and (not pick or r < pickRank or (r == pickRank and hi < pickLevel)) then
                pick, pickRank, pickLevel = o, r, hi
            end
        else
            local below = r < myRank or (r == myRank and lo <= myTop)
            if below and (not pick or r > pickRank or (r == pickRank and lo > pickLevel)) then
                pick, pickRank, pickLevel = o, r, lo
            end
        end
    end
    if not pick then return nil, up and "top" or "bottom" end
    local layer
    if pickRank ~= myRank then
        if not (part.free and part.free(f)) or part.ownLayer then return nil, "layer" end
        layer = pick:GetFrameStrata()
        if layer == f:GetFrameStrata() then layer = "FRAME" end
    end
    local want = up and (pickLevel + 1) or (pickLevel - 1 - (myTop - myLow))
    local order = want - f:GetFrameLevel()
    if order > Layers.MAX or order < Layers.MIN then return nil, "range" end
    return order, layer
end

-- The settings rows for one frame's page: an Order slider per part, and a
-- Layer pick for each part that can stand on its own.
function Layers.Rows(unit, off)
    local rows = {}
    for _, part in ipairs(Layers.PARTS[unit] or {}) do
        local key = part.key
        local f = frameOf(unit)
        rows[#rows + 1] = { type = "slider", key = unit .. ".parts." .. key .. ".order", label = part.label .. " order",
            min = Layers.MIN, max = Layers.MAX, step = 1,
            desc = "Where it draws among this frame's parts: a higher number draws on top. "
                .. (part.mover and "In unlock mode, click it for Bring forward and Send back." or "It has no handle in unlock mode, so it's set here."),
            get = function() return Layers.OrderOf(unit, key) end,
            set = function(v) Layers.Set(unit, key, v, false) end,
            default = function() return nil end,
            disabled = off }
        if part.free and not part.ownLayer then
            rows[#rows + 1] = { type = "dropdown", key = unit .. ".parts." .. key .. ".layer", label = part.label .. " layer",
                values = ns.CASTBAR_STRATA_LABELS, order = ns.CASTBAR_STRATA,
                desc = "The layer it draws in while it stands on its own. Same as frame keeps it with the frame.",
                get = function() local s = Layers.Saved(unit, key); return s and s.layer or "FRAME" end,
                set = function(v) DUI:Set("UnitFrames", unit .. ".parts." .. key .. ".layer", v ~= "FRAME" and v or nil) end,
                default = function() return "FRAME" end,
                disabled = function(get) return (off and off(get)) or not (f and part.free(f)) end }
        end
    end
    return rows
end

-- The unlock editor's hook for a part's handle.
function Layers.MoverHook(unit, key)
    return {
        step = function(others, up)
            local order, layer = Layers.Step(unit, key, others, up)
            if not order then return false, layer end
            Layers.Set(unit, key, order, layer or false)
            return true
        end,
    }
end

-- Gives every part with an unlock handle its Bring forward / Send back.
function Layers.Hook()
    for unit, parts in pairs(Layers.PARTS) do
        local f = frameOf(unit)
        for _, part in ipairs(parts) do
            local key = part.mover and f and part.mover(f)
            if key then DUI.Movers.SetLayerHook(key, Layers.MoverHook(unit, part.key)) end
        end
    end
end
