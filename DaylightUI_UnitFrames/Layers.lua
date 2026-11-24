-- Layers: which part of a unit frame draws over which, where parts overlap.
-- Each frame ranks its parts (the name tab, portrait, portrait icons, aura
-- rows, and the pieces that can stand on their own) in one list, top first:
-- a part draws over every part below it. A part standing on its own can also
-- take a Layer (strata, or "FRAME" to draw with its frame).
-- Saved as <unit>.parts = { order = { key, ... }, <key> = { layer = s } }.
-- Nothing is set until a player changes it: untouched parts keep the levels
-- their own code gives them, and the list shows them in the order they draw.
-- Party, raid and arena tiles aren't covered.

local _, ns = ...
local DUI = DaylightUI

local Layers = {}
ns.Layers = Layers

-- Frame levels between two places in the list: more than any part's own art
-- spans (a portrait with its ring, icons and skull reaches about 9).
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

-- A pet frame's happiness square: the preview's own, or the live pet's (ns.happiness).
local function happinessOf(f)
    if f.happiness then return f.happiness end
    local h = ns.happiness
    if h and h.pet == f then return h end
end

-- glue(f): frames drawn as part of a part without being inside it. They move
-- with it and keep their gap to it. The frame's border goes round its health
-- bar, and the incoming heal, absorb and overshield bars and a pet's happiness
-- stripe draw over it.
local HEALTH = part("health", "Health bar", function(f) return f.health end,
    { glue = function(f)
        local heals, absorbs, mood = f.heals, f.absorbs, happinessOf(f)
        return { DUI.Style.GetShell(f), heals, heals and heals.wedge, absorbs, absorbs and absorbs.wedge,
                 f.overshield, mood and mood.band }
    end })
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
-- install. It settles parts that draw at the same level, and places a part
-- that isn't built yet.
Layers.PARTS = {
    player = extraTexts({ druid(), castbar("player", "playerCastbar"), swing(), HEALTH, power("player"),
        debuffs("player"), buffs("player"), NAME, HEALTH_TEXT, POWER_TEXT }, { PORTRAIT, LEVEL, LEADER, PVP, REST }),
    target = extraTexts({ castbar("target", "targetCastbarFree"), HEALTH, power("target"), debuffs("target"),
        buffs("target"), NAME, HEALTH_TEXT, POWER_TEXT }, { PORTRAIT, MARKER, CREST, LEVEL, LEADER, PVP, THREAT, COMBO }),
    focus = extraTexts({ castbar("focus", "focusCastbarFree"), HEALTH, power("focus"), debuffs("focus"), buffs("focus"),
        NAME, HEALTH_TEXT, POWER_TEXT }, { PORTRAIT, MARKER, LEVEL, LEADER, PVP }),
    pet = extraTexts({ HEALTH, power("pet"), debuffs("pet"), buffs("pet"), HEALTH_TEXT, POWER_TEXT },
        { NAME, part("happiness", "Pet happiness", happinessOf) }),
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

function Layers.Find(unit, key)
    for _, part in ipairs(Layers.PARTS[unit] or {}) do
        if part.key == key then return part end
    end
end

local function saved(unit)
    local d = db()
    local p = d and d[unit] and d[unit].parts
    return type(p) == "table" and p or nil
end

-- Whether no part of a frame has a saved place or layer.
function Layers.Untouched(unit)
    local p = saved(unit)
    if not p then return true end
    if type(p.order) == "table" and #p.order > 0 then return false end
    for key, v in pairs(p) do
        if key ~= "order" and type(v) == "table" and v.layer ~= nil then return false end
    end
    return true
end

-- A part's saved choices ({ layer = s }), or nil.
function Layers.Saved(unit, key)
    local p = saved(unit)
    return p and key ~= "order" and type(p[key]) == "table" and p[key] or nil
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

-- Puts the parts missing from a bottom-to-top list just over their nearest
-- part below in ref (another bottom-to-top list), keeping ref's order.
local function fillFrom(keys, ref)
    local out, has = {}, {}
    for _, key in ipairs(keys) do
        if not has[key] then out[#out + 1], has[key] = key, true end
    end
    local below = 0
    for _, key in ipairs(ref) do
        if has[key] then
            for j, k in ipairs(out) do if k == key then below = j end end
        else
            below = below + 1
            table.insert(out, below, key)
            has[key] = true
        end
    end
    return out
end

local function reversed(t)
    local out = {}
    for i = #t, 1, -1 do out[#out + 1] = t[i] end
    return out
end

local DRAW = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

-- A frame's parts bottom to top as they draw now: by level, then a text's or
-- icon's draw layer, then the parts list. A frame ranks under the texts and
-- icons at its own level. A part f doesn't have goes where the parts list
-- puts it. Read only while no part is placed.
function Layers.DefaultStack(f, unit)
    local found, all = {}, {}
    for i, part in ipairs(Layers.PARTS[unit] or {}) do
        all[i] = part.key
        local x = f and list(part.get(f))[1]
        if x then
            local region = isRegion(part, f)
            local layer, sub
            if region then layer, sub = x:GetDrawLayer() end
            found[#found + 1] = { key = part.key, i = i, level = (region and x:GetParent() or x):GetFrameLevel(),
                                  draw = region and (DRAW[layer] or 3) or 0, sub = sub or 0 }
        end
    end
    table.sort(found, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.draw ~= b.draw then return a.draw < b.draw end
        if a.sub ~= b.sub then return a.sub < b.sub end
        return a.i < b.i
    end)
    local keys = {}
    for i, e in ipairs(found) do keys[i] = e.key end
    return fillFrom(keys, all)
end

-- Each live frame's default list, noted by ApplyTo before it places a part.
local homes = {}
local function defaultOf(unit)
    if Layers.Untouched(unit) or not homes[unit] then return Layers.DefaultStack(frameOf(unit), unit) end
    return homes[unit]
end

-- The frame's list as the player sees it, top first: the saved one (with any
-- part it lacks put back where it draws by default), or the default.
function Layers.Stack(unit)
    local default = defaultOf(unit)
    local p = saved(unit)
    if not (p and type(p.order) == "table" and #p.order > 0) then return reversed(default) end
    local keys = {}
    for _, key in ipairs(p.order) do
        if Layers.Find(unit, key) then keys[#keys + 1] = key end
    end
    return reversed(fillFrom(reversed(keys), default))
end

-- A part's place counted from the bottom (1 draws under the rest).
function Layers.OrderOf(unit, key)
    local stack = Layers.Stack(unit)
    for i, k in ipairs(stack) do
        if k == key then return #stack - i + 1 end
    end
end

-- Saves a frame's list (top first) and, unless layer is false, one part's
-- Layer (nil clears it), in one write. A list that matches the default saves
-- as nil, so the frame can be untouched again.
function Layers.Save(unit, stack, key, layer)
    local p = {}
    for k, v in pairs(saved(unit) or {}) do
        if k ~= "order" and type(v) == "table" and v.layer ~= nil then p[k] = { layer = v.layer } end
    end
    local default = reversed(defaultOf(unit))
    local same = #stack == #default
    for i, k in ipairs(default) do
        if stack[i] ~= k then same = false end
    end
    if not same then p.order = stack end
    if key and layer ~= false then
        p[key] = layer ~= nil and { layer = layer } or nil
    end
    DUI:Set("UnitFrames", unit .. ".parts", next(p) and p or nil)
end

-- Extra texts take part only while added (Add piece).
function Layers.InUse(unit, part)
    if not part.slot then return true end
    return DUI:Get("UnitFrames", unit .. ".texts." .. part.slot .. ".show") == true
end

-- The list the options page shows, top first: the parts in use.
function Layers.Shown(unit)
    local out = {}
    for _, key in ipairs(Layers.Stack(unit)) do
        if Layers.InUse(unit, Layers.Find(unit, key)) then out[#out + 1] = key end
    end
    return out
end

-- The list with one part moved past the next part in use above (up) or below
-- it, or nil when it's already at that end.
function Layers.Moved(unit, key, up)
    local stack = Layers.Stack(unit)
    local at
    for i, k in ipairs(stack) do if k == key then at = i end end
    if not at then return nil end
    local j = at
    repeat
        j = j + (up and -1 or 1)
        if j < 1 or j > #stack then return nil end
    until Layers.InUse(unit, Layers.Find(unit, stack[j]))
    table.remove(stack, at)
    table.insert(stack, j, key)
    return stack
end

function Layers.Move(unit, key, up)
    local stack = Layers.Moved(unit, key, up)
    if stack then Layers.Save(unit, stack, nil, false) end
    return stack ~= nil
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

-- Applies a frame's saved list and Layers: a live frame, or an options preview
-- (f.layerPreview) of the same unit. Runs after the frame's own code has
-- placed its parts. Protected parents: out of combat.
-- A part moves as one: its frames, everything inside them and its glue. Each
-- part goes wholly over the one below it in the list, so two parts never
-- interleave, even one whose art spans more than a step.
function Layers.ApplyTo(f, unit)
    local parts = Layers.PARTS[unit]
    if not (f and parts) then return end
    local touched = not Layers.Untouched(unit)
    -- The default list, read before the first pass that places anything.
    if f == frameOf(unit) then
        if not touched then homes[unit] = nil
        elseif not homes[unit] then homes[unit] = Layers.DefaultStack(f, unit) end
    end
    local rank = {}
    if touched then
        local stack = Layers.Stack(unit)
        for i, key in ipairs(stack) do rank[key] = #stack - i + 1 end
    end
    local base = f:GetFrameLevel()
    local placed = {}
    for _, part in ipairs(parts) do
        local s = Layers.Saved(unit, part.key)
        local order = rank[part.key]
        local frames = partFrames(f, part, order)
        local glue = glueOf(f, part)
        if #frames > 0 and order then
            placed[#placed + 1] = { frames = frames, glue = glue, order = order }
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
    table.sort(placed, function(a, b) return a.order < b.order end)
    -- Every home level is noted before any part moves: moving one relevels the
    -- frames inside it, a part among them.
    for _, e in ipairs(placed) do
        for _, x in ipairs(e.frames) do if x.layerHome == nil then x.layerHome = x:GetFrameLevel() end end
        for _, x in ipairs(e.glue) do if x.layerHome == nil then x.layerHome = x:GetFrameLevel() end end
    end
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
    -- An open unlock editor grays Bring forward and Send back from the new levels.
    DUI.Movers.RefreshEditor()
end

-- Unlock's Bring forward / Send back for a part with a handle. others is a
-- list of overlapping frames. Returns the new list (top first) and Layer, or
-- nil and why.
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
    local stack = Layers.Stack(unit)
    local n, at = #stack, nil
    for i, k in ipairs(stack) do if k == key then at = i end end
    local myOrder = n - at + 1
    table.remove(stack, at)
    -- Another part of the same frame: just over (or under) it in the list.
    for _, other in ipairs(Layers.PARTS[unit] or {}) do
        if other.key ~= key then
            for _, x in ipairs(list(other.get(f))) do
                local fr = x.GetFrameLevel and x or x:GetParent()
                if fr == pick then
                    for i, k in ipairs(stack) do
                        if k == other.key then
                            table.insert(stack, up and i or i + 1, key)
                            return stack, layer
                        end
                    end
                end
            end
        end
    end
    -- The place that puts all of it just over (or under) that frame.
    local base, step, span = f:GetFrameLevel(), Layers.STEP, myTop - myLow
    local order
    if up then
        order = math.floor((pickLevel - base) / step) + 1
    else
        order = math.floor((pickLevel - 1 - span - base) / step)
    end
    local still = not layer and ((up and order <= myOrder) or (not up and order >= myOrder))
    if order > n or order < 1 or still then return nil, "range" end
    table.insert(stack, n - order + 1, key)
    return stack, layer
end

-- Puts every part of a frame back where it drew before any change, or one
-- part back in its default place on its own code's layer.
function Layers.Reset(unit, key)
    if not key then
        DUI:Set("UnitFrames", unit .. ".parts", nil)
        return
    end
    local keys = {}
    for _, k in ipairs(Layers.Stack(unit)) do if k ~= key then keys[#keys + 1] = k end end
    Layers.Save(unit, reversed(fillFrom(reversed(keys), defaultOf(unit))), key, nil)
end

-- One line of the draw-order list: the part's name and its up and down buttons.
local LINE = 28
local function buildLine(parent, unit)
    local W, Style, L = DUI.Widgets, DUI.Style, DUI.L
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(LINE)
    line.move = W.MoveButtons(line)
    line.move:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.name = Style.Text(line, Style.SIZE.body, "LEFT")
    line.name:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.name:SetPoint("RIGHT", line.move, "LEFT", -8, 0)
    Style.InkText(line.name, "TEXT")
    local tips = { { line.move.up, true, L["Move up"], L["Draws it over the part above."] },
                   { line.move.down, false, L["Move down"], L["Draws it under the part below."] } }
    for _, t in ipairs(tips) do
        local b, up, title, desc = t[1], t[2], t[3], t[4]
        b:SetScript("OnClick", function() if line.key then Layers.Move(unit, line.key, up) end end)
        b:HookScript("OnEnter", function(self) W.Tooltip(self, title, desc) end)
        b:HookScript("OnLeave", W.HideTooltip)
    end
    return line
end

-- The draw-order list: a line per part in use, top first.
local function orderList(unit, off)
    return {
        type = "custom", label = "Draw order", disabled = off,
        build = function(row)
            row.lines = {}
            row.list = CreateFrame("Frame", nil, row)
            row.list:SetPoint("TOPLEFT", row, "TOPLEFT", DUI.Widgets.PAD, -4)
            row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -DUI.Widgets.PAD, -4)
        end,
        update = function(row)
            local shown = Layers.Shown(unit)
            for i, key in ipairs(shown) do
                local line = row.lines[i]
                if not line then
                    line = buildLine(row.list, unit)
                    row.lines[i] = line
                end
                line.key = key
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(i - 1) * LINE)
                line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(i - 1) * LINE)
                line.name:SetText(DUI.Options.Text(Layers.Find(unit, key).label))
                line.move.up.SetUsable(not row.disabled and i > 1)
                line.move.down.SetUsable(not row.disabled and i < #shown)
                DUI.Widgets.Stripe(line, i % 2 == 0)
                line:Show()
            end
            for i = #shown + 1, #row.lines do row.lines[i]:Hide() end
            row.count = #shown
            row.list:SetHeight(math.max(1, #shown * LINE))
        end,
        height = function(row) return (row.count or #Layers.Shown(unit)) * LINE + 8 end,
    }
end

-- The settings rows for one frame's page: a reset, the draw-order list, and a
-- Layer pick for each part that can stand on its own.
function Layers.Rows(unit, off)
    local rows = {
        { type = "button", label = "Reset layers", text = "Reset", confirm = true, func = function() Layers.Reset(unit) end,
          desc = "Puts every part of this frame back where it drew before you changed its place or layer.",
          disabled = function(get) return (off and off(get)) or Layers.Untouched(unit) end },
        orderList(unit, off),
    }
    for _, part in ipairs(Layers.PARTS[unit] or {}) do
        local key = part.key
        local f = frameOf(unit)
        if part.free and not part.ownLayer then
            rows[#rows + 1] = { type = "dropdown", key = unit .. ".parts." .. key .. ".layer", label = string.format(DUI.L["%s layer"], DUI.L[part.label]),
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

-- The unlock editor's hook for a part's handle: can(others, up) says whether a
-- step would go, and why not; step(others, up) takes it.
function Layers.MoverHook(unit, key)
    return {
        can = function(others, up)
            local stack, why = Layers.Step(unit, key, others, up)
            return stack ~= nil, why
        end,
        step = function(others, up)
            local stack, layer = Layers.Step(unit, key, others, up)
            if not stack then return false, layer end
            Layers.Save(unit, stack, key, layer or false)
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
