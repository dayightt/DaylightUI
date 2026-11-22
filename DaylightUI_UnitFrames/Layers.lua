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
-- A frame's orders run 1 to its number of parts.
-- Frame levels between two orders: more than any part's own art spans (a
-- portrait with its ring, icons and skull reaches about 9), so parts on
-- different orders never interleave.
Layers.STEP = 12
Layers.STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                       FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function frameOf(unit) return unit == "personal" and ns.Personal.frame or (ns.frames and ns.frames[unit]) end

local function db() return ns.module and ns.module.db end

-- Whether a piece stands on its own (on UIParent), so it can take a Layer.
local function powerFree(unit) local d = db(); return d and d[unit] and d[unit].powerAt == "free" end
local function castFree(unit)
    local d = db()
    return d and ns.CastBar.At(unit, d[unit .. "Castbar"]) ~= "power"
end

-- A frame's aura rows: an options preview's stand-ins, else the live set.
local LIVE_AURAS = { target = "auras", player = "playerAuras", focus = "focusAuras", pet = "petAuras" }
local function auraRow(unit, kind)
    return function(f)
        local set = f.sampleAuras
        if not set then set = unit == "personal" and ns.Personal.auras or ns[LIVE_AURAS[unit]] end
        local row = set and set[kind]
        if not row then return nil end
        -- Sample icons (the options preview, test mode) draw on a holder beside the row.
        local holder = ns.Auras.HolderFor(row)
        if holder then return { row, holder } end
        return row
    end
end

-- The parts each frame has, as in Design mode. get(f) returns a frame, a list
-- of frames, or (region = true) a texture or text, which moves into a small
-- frame of its own once it's given an order. free(f): it stands on its own;
-- mover(f): its unlock handle. f is the live frame or an options preview.
local function part(key, label, get, extra)
    local p = { key = key, label = label, get = get }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

-- glue(f): frames drawn as part of a part without being inside it. They move
-- with it and keep their gap to it. The frame's border goes round its health bar.
local HEALTH = part("health", "Health bar", function(f) return f.health end,
    { glue = function(f) return { DUI.Style.GetShell(f) } end })
local function power(unit)
    return part("power", "Power bar", function(f) return f.freePower and powerFree(unit) and f.freePower or f.power end,
        { free = function(f) return f.freePower ~= nil and powerFree(unit) end,
          mover = function() return ns.PowerBar.KeyFor(unit) end })
end
-- On the frame, the portrait's socket ring (2.0 look), its icon set and the
-- raid-target skull are frames beside it; standing on its own they're inside it.
local PORTRAIT = part("portrait", "Portrait", function(f) return f.portraitFree and f.portraitHolder or f.portrait end,
    { glue = function(f)
          if f.portraitFree then return {} end
          return { f.socket, f.status, f.dotSkull }
      end,
      free = function(f) return f.portraitFree == true end,
      mover = function(f) return f.portraitHolder and f.portraitHolder.key end })
local function inTab(f) return f.tab ~= nil and f.tab:IsShown() and f.tabClip ~= nil end
local NAME = part("name", "Name", function(f) if inTab(f) then return f.tabClip end return f.nameText end,
    { regionIf = function(f) return not inTab(f) end })
local HEALTH_TEXT = part("healthText", "Health text", function(f) return f.percentText end, { region = true })
local POWER_TEXT = part("powerText", "Power text", function(f) return f.powerText end, { region = true })
local MARKER = part("marker", "Raid marker", function(f) return f.marker end, { region = true })
local CREST = part("crest", "Elite crest", function(f) return f.crest end)
-- The portrait's icons ride 6 levels over it (UF.HomePortrait), each moving to
-- a frame of its own once given an order.
local function statusIcon(key, label, name, more)
    return part(key, label, function(f)
        local st = f.status
        if not (st and st.icons[name]) then return nil end
        if more then return { st.icons[name], st.levelText, st.skull } end
        return st.icons[name]
    end, { region = true })
end
local LEVEL = statusIcon("level", "Level", "level", true)
local LEADER = statusIcon("leader", "Leader crown", "leader")
local PVP = statusIcon("pvp", "PvP flag", "pvp")
local REST = statusIcon("rest", "Resting", "rest")
local function debuffs(unit) return part("debuffs", "Debuffs", auraRow(unit, "debuffs")) end
local function buffs(unit) return part("buffs", "Buffs", auraRow(unit, "buffs")) end
local function castbar(unit, field)
    return part("castbar", "Cast bar", function(f) if not f.layerPreview then return ns[field] end end,
        { free = function() return castFree(unit) end, ownLayer = true,
          mover = function() return "unitframes." .. unit .. "Castbar" end })
end
local function extraTexts(out, after)
    for i in ipairs(ns.TEXT_SLOTS or {}) do
        out[#out + 1] = part("text" .. i, "Extra text " .. i, function(f) return f.extraTexts and f.extraTexts[i] end,
            { region = true, slot = ns.TEXT_SLOTS[i] })
    end
    for _, p in ipairs(after or {}) do out[#out + 1] = p end
    return out
end

local function swing()
    -- The swing timer and its bars standing on their own; its own page picks its layer.
    return part("swing", "Swing timer", function(f)
        if f.layerPreview or not ns.swing then return nil end
        local out = { ns.swing }
        for _, pod in pairs(ns.swing.pods or {}) do out[#out + 1] = pod end
        return out
    end, { ownLayer = true, free = function() return true end, mover = function() return "unitframes.swing" end })
end
local function druid()
    return part("druid", "Druid bars", function(f) if not f.layerPreview then return _G.DaylightUIDruidBars end end,
        { free = function() return true end, mover = function() return ns.DruidBars.KEY end })
end
local THREAT = part("threat", "Threat %", function(f) return f.threatHolder end,
    { free = function(f) return f.threatTag ~= nil and f.threatTag:GetParent() == f.threatHolder end,
      mover = function() return ns.UF.THREAT_KEY end })
local COMBO = part("combo", "Combo points", function(f) if not f.layerPreview then return ns.combo and ns.combo.holder end end,
    { free = function() local d = db(); return d and d.combo and d.combo.anchor == "free" end,
      mover = function() return ns.Combo.KEY end })

-- Each frame's parts, bottom to top as Daylight UI draws them on a fresh
-- install. A part's place in its list is its default order.
Layers.PARTS = {
    player = extraTexts({ druid(), castbar("player", "playerCastbar"), swing(), HEALTH, power("player"),
        debuffs("player"), buffs("player"), NAME, HEALTH_TEXT, POWER_TEXT }, { PORTRAIT, LEVEL, LEADER, PVP, REST }),
    target = extraTexts({ castbar("target", "targetCastbarFree"), HEALTH, power("target"), debuffs("target"),
        buffs("target"), NAME, HEALTH_TEXT, POWER_TEXT }, { PORTRAIT, MARKER, CREST, LEVEL, LEADER, PVP, THREAT, COMBO }),
    focus = extraTexts({ castbar("focus", "focusCastbarFree"), HEALTH, power("focus"), debuffs("focus"), buffs("focus"),
        NAME, HEALTH_TEXT, POWER_TEXT }, { PORTRAIT, MARKER, LEVEL, LEADER, PVP }),
    pet = extraTexts({ HEALTH, power("pet"), debuffs("pet"), buffs("pet"), HEALTH_TEXT, POWER_TEXT },
        { NAME, part("happiness", "Pet happiness", function(f) return f.happiness end) }),
    personal = { debuffs("personal"), buffs("personal") },
}

local function list(v)
    if type(v) ~= "table" then return {} end
    if v.GetObjectType then return { v } end
    local out = {}
    for _, x in pairs(v) do if type(x) == "table" and x.GetObjectType then out[#out + 1] = x end end
    return out
end

local function isRegion(part, f)
    if part.regionIf then return part.regionIf(f) end
    return part.region == true
end

-- A texture or text given an order draws from a small frame of its own (one per
-- part) filling the frame its own code put it in. That code may move it to
-- another parent later; the next pass moves it back in.
local function carrierFor(f, part, regions)
    f.layerCarriers = f.layerCarriers or {}
    local c = f.layerCarriers[part.key]
    local home = regions[1]:GetParent()
    if c and home == c then home = c.home end
    if not c then
        c = CreateFrame("Frame", nil, home)
        f.layerCarriers[part.key] = c
    end
    if c.home ~= home then
        c:SetParent(home)
        c:ClearAllPoints()
        c:SetAllPoints(home)
        c.home = home
    end
    c:Show()
    for _, r in ipairs(regions) do
        if r:GetParent() ~= c then r:SetParent(c) end
    end
    return c
end

local function dropCarrier(f, part, regions)
    local c = f.layerCarriers and f.layerCarriers[part.key]
    if not c then return end
    for _, r in ipairs(regions) do
        if r:GetParent() == c then r:SetParent(c.home) end
    end
    c:Hide()
end

function Layers.MaxFor(unit) return math.max(Layers.MIN, #(Layers.PARTS[unit] or {})) end

function Layers.Find(unit, key)
    for _, part in ipairs(Layers.PARTS[unit] or {}) do
        if part.key == key then return part end
    end
end

-- Whether no part of a frame has a saved order or layer.
function Layers.Untouched(unit)
    local d = db()
    local p = d and d[unit] and d[unit].parts
    if type(p) ~= "table" then return true end
    for _, v in pairs(p) do
        if type(v) == "table" and (v.order ~= nil or v.layer ~= nil) then return false end
    end
    return true
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
    local f = frameOf(unit)
    if not f then return Layers.MIN end
    return Layers.DefaultOrders(f, unit)[key] or Layers.MIN
end

-- Sets one frame's level and keeps everything inside it at its offset (the
-- portrait's ring over its model, a tab's crest over the tab).
-- The game's aura containers carry their own buttons and order each button's
-- frames themselves (its border among them), so only the container is moved.
local function gameOwned(frame) return frame.GetObjectType and frame:GetObjectType() == "AuraContainer" end

local function setLevel(frame, level)
    if frame.layerHome == nil then frame.layerHome = frame:GetFrameLevel() end
    local inner = not gameOwned(frame)
    if inner then ns.UF.NoteLevels(frame) end
    frame:SetFrameLevel(math.max(0, level))
    frame.layerOwn = true
    if inner then ns.UF.Relevel(frame) end
end

local function restore(frame)
    if frame.layerHome == nil then return end
    local inner = not gameOwned(frame)
    if inner then ns.UF.NoteLevels(frame) end
    frame:SetFrameLevel(frame.layerHome)
    frame.layerOwn = nil
    if inner then ns.UF.Relevel(frame) end
    frame.layerHome = nil
end

-- The highest and lowest frame levels a frame draws at: its own and every
-- frame inside it, shown or not. The game's aura containers aren't looked
-- into (their buttons answer with secret values): a button sits one over its
-- container, with its border one under the button.
local function topOf(frame)
    local top = frame:GetFrameLevel()
    if gameOwned(frame) then return top + 2 end
    -- A frame inside it that Layers placed is a part of its own.
    for _, c in ipairs({ frame:GetChildren() }) do
        if not c.layerOwn then top = math.max(top, topOf(c)) end
    end
    return top
end
local function lowOf(frame)
    local low = frame:GetFrameLevel()
    if gameOwned(frame) then return low end
    for _, c in ipairs({ frame:GetChildren() }) do
        if not c.layerOwn then low = math.min(low, lowOf(c)) end
    end
    return low
end
Layers.TopOf, Layers.LowOf = topOf, lowOf

-- Applies a frame's saved Orders and Layers: a live frame, or an options
-- preview (f.layerPreview) of the same unit. Runs after the frame's own code has
-- placed its parts. Protected parents: out of combat.
-- A part moves as one: its frames, everything inside them and its glue. Parts
-- given an order are stacked from the lowest order up, each wholly over the
-- one before, so two parts never interleave; equal orders go in list order.
-- Where a part draws before any order is set: its frame's own level, or a
-- text's or icon's frame's.
local function homeLevel(x)
    if not x.GetFrameLevel then
        local c = x:GetParent()
        x = (c and c.home and c.layerOwn and c.home) or c
    end
    return x.layerHome or x:GetFrameLevel()
end

-- An unset part's order: its place in its frame's list.
function Layers.DefaultOrders(_, unit)
    local out = {}
    for i, part in ipairs(Layers.PARTS[unit] or {}) do out[part.key] = i end
    return out
end

local function partFrames(f, part, order)
    local found = list(part.get(f))
    if #found == 0 then return {} end
    if isRegion(part, f) then
        if order then return { carrierFor(f, part, found) } end
        dropCarrier(f, part, found)
        return {}
    end
    return found
end

local function glueOf(f, part)
    local out = {}
    for _, g in pairs(part.glue and part.glue(f) or {}) do
        if type(g) == "table" and g.GetFrameLevel then out[#out + 1] = g end
    end
    return out
end

function Layers.ApplyTo(f, unit)
    local parts = Layers.PARTS[unit]
    if not (f and parts) then return end
    local touched = not Layers.Untouched(unit)
    local base = f:GetFrameLevel()
    local defaults = touched and Layers.DefaultOrders(f, unit) or {}
    local placed = {}
    for i, part in ipairs(parts) do
        local s = Layers.Saved(unit, part.key)
        local order = touched and ((s and tonumber(s.order)) or defaults[part.key]) or nil
        local frames = partFrames(f, part, order)
        local glue = glueOf(f, part)
        if #frames > 0 and order then
            placed[#placed + 1] = { part = part, i = i, frames = frames, glue = glue,
                                    order = math.max(Layers.MIN, math.min(Layers.MaxFor(unit), order)) }
        else
            for _, frame in ipairs(frames) do restore(frame) end
            for _, g in ipairs(glue) do restore(g) end
        end
        for _, frame in ipairs(frames) do
            local layer = s and s.layer
            if not f.layerPreview and part.free and not part.ownLayer and part.free(f) and type(layer) == "string"
                and layer ~= "FRAME" and ns.STRATA_LABELS[layer] then
                frame:SetFrameStrata(layer)
            end
        end
    end
    table.sort(placed, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.i < b.i
    end)
    local prevTop
    for _, e in ipairs(placed) do
        local main = e.frames[1]
        local home = main.layerHome or main:GetFrameLevel()
        -- Each glued frame's gap to the part, as its own code placed them.
        for _, g in ipairs(e.glue) do
            if g.layerGap == nil then g.layerGap = (g.layerHome or g:GetFrameLevel()) - home end
        end
        -- How far below the part's own level its lowest piece reaches.
        local reach = 0
        for _, frame in ipairs(e.frames) do reach = math.min(reach, lowOf(frame) - frame:GetFrameLevel()) end
        for _, g in ipairs(e.glue) do reach = math.min(reach, g.layerGap + lowOf(g) - g:GetFrameLevel()) end
        local level = base + e.order * Layers.STEP - reach
        -- Two parts on one order: the later one goes wholly over the first.
        if prevTop then level = math.max(level, prevTop + 1 - reach) end
        local top = level
        for _, frame in ipairs(e.frames) do
            setLevel(frame, level)
            top = math.max(top, topOf(frame))
        end
        for _, g in ipairs(e.glue) do
            setLevel(g, level + g.layerGap)
            top = math.max(top, topOf(g))
        end
        prevTop = top
    end
end

function Layers.Apply()
    for unit in pairs(Layers.PARTS) do Layers.ApplyTo(frameOf(unit), unit) end
end

-- Saves a part's Order and Layer and redraws. nil clears one.
function Layers.Set(unit, key, order, layer)
    local path = unit .. ".parts." .. key
    DUI:Set("UnitFrames", path .. ".order", order)
    if layer ~= false then DUI:Set("UnitFrames", path .. ".layer", layer) end
end


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
    -- Another part of the same frame: one order over (or under) its order.
    for _, other in ipairs(Layers.PARTS[unit] or {}) do
        if other.key ~= key then
            for _, x in ipairs(list(other.get(f))) do
                local fr = x.GetFrameLevel and x or x:GetParent()
                if fr == pick then
                    local order = Layers.OrderOf(unit, other.key) + (up and 1 or -1)
                    if order > Layers.MaxFor(unit) or order < Layers.MIN then return nil, "range" end
                    return order, layer
                end
            end
        end
    end
    -- The order that puts all of it just over (or under) that frame.
    local base, step, span = f:GetFrameLevel(), Layers.STEP, myTop - myLow
    local order
    if up then
        order = math.floor((pickLevel - base) / step) + 1
    else
        order = math.floor((pickLevel - 1 - span - base) / step)
    end
    if order > Layers.MaxFor(unit) or order < Layers.MIN then return nil, "range" end
    return order, layer
end

-- Puts every part of a frame (or one part) back on its own code's level and layer.
function Layers.Reset(unit, key)
    DUI:Set("UnitFrames", unit .. ".parts" .. (key and ("." .. key) or ""), nil)
end

-- The settings rows for one frame's page: a reset, an Order slider per part,
-- and a Layer pick for each part that can stand on its own.
function Layers.Rows(unit, off)
    local rows = {
        { type = "button", label = "Reset layers", func = function() Layers.Reset(unit) end,
          desc = "Puts every part of this frame back where it drew before you changed its order or layer.",
          disabled = function(get) return (off and off(get)) or Layers.Untouched(unit) end },
    }
    for _, part in ipairs(Layers.PARTS[unit] or {}) do
        local key = part.key
        local f = frameOf(unit)
        -- An extra text's rows only show while that text is added (Add piece).
        local unused = part.slot and function(get) return get(unit .. ".texts." .. part.slot .. ".show") ~= true end
        rows[#rows + 1] = { type = "slider", key = unit .. ".parts." .. key .. ".order", label = part.label .. " order",
            min = Layers.MIN, max = Layers.MaxFor(unit), step = 1,
            desc = "Where it draws among this frame's parts: a higher number draws on top. "
                .. (part.mover and "In unlock mode, click it for Bring forward and Send back." or "It has no handle in unlock mode, so it's set here."),
            get = function() return Layers.OrderOf(unit, key) end,

            -- The default order saves as nil, so a reset leaves the part untouched.
            set = function(v)
                Layers.Set(unit, key, v ~= Layers.DefaultOrders(f, unit)[key] and v or nil, false)
            end,
            default = function() return Layers.DefaultOrders(f, unit)[key] end,
            disabled = off, hidden = unused }
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
        reset = function() Layers.Reset(unit, key) end,
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
