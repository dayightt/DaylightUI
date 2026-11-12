-- Migrates a profile's old fade settings (fadeOOC and oocAlpha, the bars'
-- mouseover and fade, chat's fade switch) into the fade engine's tables.
-- One numbered step per module, each run once per profile (general.fadeEngine
-- holds the last one done). Runs on the active profile at login before any
-- module merges its defaults, which would wipe chat's old "fade" switch, and
-- on a new profile copied from another (DB.RunUpgrades). Profiles only save
-- what differs from the defaults, so a missing key means the old default.

local _, DUI = ...

local Up = {}
DUI.FadeUpgrade = Up

local function num(v) return type(v) == "number" and v or nil end

-- t.fadeOOC / t.oocAlpha become t.fade. g is General's old opacity.
function Up.FromOOC(t, g)
    if type(t) ~= "table" then return end
    if t.fadeOOC == true or num(t.oocAlpha) then
        if type(t.fade) ~= "table" then t.fade = {} end
        if t.fadeOOC == true then
            t.fade.mode = "ooc"
            t.fade.alpha = num(t.oocAlpha) or g
        else
            t.fade.alpha = t.oocAlpha
        end
    end
    t.fadeOOC, t.oocAlpha = nil, nil
end

-- fn(p, g): p is a profile's data, g is General's old oocAlpha (or nil).
Up.STEPS = {}

-- 1: info panel and quest tracker.
Up.STEPS[1] = function(p, g)
    local ip = p.modules.InfoPanel
    if type(ip) ~= "table" then return end
    Up.FromOOC(ip, g)
    Up.FromOOC(ip.tracker, g)
end

-- 2: buff and debuff bars.
Up.STEPS[2] = function(p, g)
    local b = p.modules.Buffs
    if type(b) ~= "table" or type(b.settings) ~= "table" then return end
    Up.FromOOC(b.settings, g)
    Up.FromOOC(b.settings.debuff, g)
end

-- 3: chat. Its old "fade" switch was the idle fade.
Up.STEPS[3] = function(p, g)
    local c = p.modules.Chat
    if type(c) ~= "table" then return end
    if type(c.fade) == "boolean" then c.idleFade = c.fade; c.fade = nil end
    if num(c.fadeAfter) then c.idleAfter = c.fadeAfter end
    c.fadeAfter = nil
    if c.mouseoverOnly == true then
        c.fade = { mode = "always", alpha = 0, delay = 0 }
        c.fadeOOC, c.oocAlpha = nil, nil
    else
        Up.FromOOC(c, g)
    end
    c.mouseoverOnly = nil
end

-- 4: unit frames, party and raid (plus the old healer tiles, which the unit
-- frames' own upgrade turns into party and raid settings later).
local UF_FRAMES = { "player", "target", "targettarget", "focus", "pet", "party", "raid", "healer", "healerParty" }
Up.STEPS[4] = function(p, g)
    local uf = p.modules.UnitFrames
    if type(uf) ~= "table" then return end
    for _, k in ipairs(UF_FRAMES) do Up.FromOOC(uf[k], g) end
end

-- 5: action bars. A side grid with no saved mouseover had the old default
-- (on) unless the grids' old shared switch (fade.enabled) was off. One saved
-- as off must stay off under the new default.
local SIDE = { left = true, right = true }
Up.STEPS[5] = function(p, g)
    local ab = p.modules.ActionBars
    if type(ab) ~= "table" then return end
    local old = type(ab.fade) == "table" and ab.fade or {}
    local oldAlpha, oldDelay = num(old.alpha), num(old.delay) or 3
    local ooc = type(ab.ooc) == "table" and ab.ooc or {}
    local oocAlpha = type(ab.oocAlpha) == "table" and ab.oocAlpha or {}
    if type(ab.bars) ~= "table" then ab.bars = {} end
    local keys = {}
    for k in pairs(ab.bars) do keys[k] = true end
    for k in pairs(ooc) do keys[k] = true end
    for k in pairs(oocAlpha) do keys[k] = true end
    for k in pairs(SIDE) do keys[k] = true end
    for k in pairs(keys) do
        if type(ab.bars[k]) ~= "table" then ab.bars[k] = {} end
        local b = ab.bars[k]
        local mouse = b.mouseover
        if mouse == nil then mouse = SIDE[k] == true and old.enabled ~= false end
        if mouse then
            b.fade = { mode = "always", alpha = oldAlpha, delay = oldDelay }
        elseif ooc[k] == true then
            b.fade = { mode = "ooc", alpha = num(oocAlpha[k]) or g }
        elseif SIDE[k] then
            b.fade = { mode = "never" }
        elseif num(oocAlpha[k]) then
            b.fade = { alpha = oocAlpha[k] }
        end
        b.mouseover = nil
    end
    for _, k in ipairs({ "bagBar", "microMenu" }) do
        if ab[k] == "mouseover" then
            ab[k] = "shown"
            ab[k .. "Fade"] = { mode = "always", alpha = oldAlpha, delay = oldDelay }
        end
    end
    ab.fade, ab.ooc, ab.oocAlpha = nil, nil, nil
end

-- 6: General's shared opacity is gone (every step above has read it).
Up.STEPS[6] = function(p) p.general.oocAlpha = nil end

-- 7: chat's four ways to hide (fade mode, idle fade, Floating chat, Float
-- during fights) became a single "Chat hides" pick, and the fade card keeps
-- only its opacity. Old defaults: idle fade and fights on. A profile that
-- already has a pick was created after this step (the standard setup floats
-- the chat) and keeps it.
Up.STEPS[7] = function(p)
    local c = p.modules.Chat
    if type(c) ~= "table" then return end
    local fade = type(c.fade) == "table" and c.fade or nil
    local mode = fade and fade.mode or "never"
    if c.hides ~= nil then
        -- created after this step, nothing old to move
    elseif c.floating == true then
        c.hides = "always"
    elseif c.idleFade ~= false or mode == "ooc" or mode == "always" then
        c.hides = "fightsIdle"
    elseif c.combatFloat ~= false or mode == "combat" then
        c.hides = "fights"
    else
        c.hides = "never"
    end
    if fade then fade.mode, fade.alpha, fade.mouseover, fade.target, fade.delay = nil, nil, nil, nil, nil end
    c.floating, c.idleFade, c.combatFloat = nil, nil, nil
end

-- 8: an area's own Float switch (float = true) became mode "float" of its
-- Visible row. Every area's settings live in a table named fade or ...Fade.
local function floatToMode(t, depth)
    if depth > 6 then return end
    for k, v in pairs(t) do
        if type(v) == "table" then
            if type(k) == "string" and string.find(k, "[Ff]ade$") and type(v.float) == "boolean" then
                if v.float == true then v.mode = "float" end
                v.float = nil
            end
            floatToMode(v, depth + 1)
        end
    end
end
Up.STEPS[8] = function(p)
    floatToMode(p.general, 0)
    floatToMode(p.modules, 0)
end

function Up.Run(p)
    if type(p) ~= "table" then return end
    if type(p.general) ~= "table" then p.general = {} end
    if type(p.modules) ~= "table" then p.modules = {} end
    local g = num(p.general.oocAlpha)
    for i = (tonumber(p.general.fadeEngine) or 0) + 1, #Up.STEPS do
        Up.STEPS[i](p, g)
        p.general.fadeEngine = i
    end
end

DUI.DB.RegisterUpgrade(Up.Run)
