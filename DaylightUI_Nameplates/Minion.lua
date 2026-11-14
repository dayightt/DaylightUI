-- Enemy pets and totems (the game's "minions"), and friendly totems, as a round badge instead of a bar:
-- the unit's portrait in a ring colored by the totem's element. With minionStyle
-- "bar", a slim bar in that color with the portrait beside it and the name above.
-- In battlegrounds the game hides a minion's name and type, so there every minion
-- gets the badge with a game-drawn portrait and an enemy-colored ring.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Minion = {}
ns.Minion = Minion

-- The game's own CVar for enemy pet and totem plates.
Minion.CVAR = "nameplateShowEnemyMinions"
Minion.RING = DUI.MEDIA .. "portrait-band.png"
Minion.RING_INNER = 0.772 -- ring art opening, as a fraction of its outer edge (UF.RING_INNER)
Minion.GLOW = DUI.MEDIA .. "crest-glow.png"
Minion.DISC = DUI.MEDIA .. "crest-disc.png"
Minion.HOVER = 0.2 -- mouseover brighten
Minion.BAR_W = 0.5 -- slim bar width, as a fraction of a plate's
Minion.BAR_H = 0.75 -- ...and its height

Minion.COLORS = {
    fire = { 0.9, 0.42, 0.3 },
    earth = { 0.84, 0.64, 0.32 },
    water = { 0.36, 0.62, 0.88 },
    air = { 0.8, 0.85, 0.92 },
}
-- Each totem's first rank. Plates are matched by this name in the client's
-- language, since every rank's name starts with it.
Minion.TOTEMS = {
    fire = { 3599, 1535, 8190, 8227, 8181 },
    earth = { 8071, 2484, 5730, 8075, 8143 },
    water = { 5394, 5675, 8166, 8170, 8184, 16190 },
    air = { 8177, 10595, 8512, 8835, 15107, 25908, 6495 },
}

local plain = ns.Plate.Plain -- a call's plain first return, or nil (Plate.lua loads first)

local names
local function totemNames()
    if names then return names end
    names = {}
    local get = C_Spell and C_Spell.GetSpellName
    for element, ids in pairs(Minion.TOTEMS) do
        for _, id in ipairs(ids) do
            local n = plain(get, id)
            if type(n) == "string" and n ~= "" then names[#names + 1] = { n, element } end
        end
    end
    return names
end

-- A totem's element from its name, or nil (not a totem, or a hidden name).
function Minion.Element(unit)
    local name = plain(UnitName, unit)
    if type(name) ~= "string" then return nil end
    for _, t in ipairs(totemNames()) do
        if name:sub(1, #t[1]) == t[1] then return t[2] end
    end
    return nil
end

-- Whether a plate is an enemy minion while the switch is on: "badge", "bar"
-- (slim bar) or false. A friendly totem is a badge too (friendly.totems): a row
-- of long totem names over a group is mostly noise. Friendly pets keep their name.
function Minion.Is(p, c)
    if p.object or not p.unit then return false end
    if p.friendly then
        local f = ns.cfg.friendly
        if type(f) == "table" and f.totems == false then return false end
        if plain(UnitIsMinion, p.unit) ~= true or not Minion.Element(p.unit) then return false end
        return "badge"
    end
    if c.minions == false then return false end
    if plain(UnitIsMinion, p.unit) ~= true then return false end
    return c.minionStyle == "bar" and "bar" or "badge"
end

-- Built with the plate (never on a game plate in combat), hidden until used.
function Minion.Create(p)
    local b = CreateFrame("Frame", nil, p)
    b:Hide()
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.glow:SetTexture(Minion.GLOW)
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    b.glow:SetAlpha(0)
    b.shadow = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    b.shadow:SetTexture(Minion.GLOW)
    b.shadow:SetVertexColor(0, 0, 0, 0.8)
    b.shadow:SetPoint("CENTER", 0, -1)
    b.disc = b:CreateTexture(nil, "BACKGROUND")
    b.disc:SetTexture(Minion.DISC)
    b.disc:SetVertexColor(0.02, 0.02, 0.02, 1)
    b.disc:SetPoint("CENTER")
    -- The game's portraits are already round, so no mask.
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.hover = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.hover:SetTexture(Minion.DISC)
    b.hover:SetBlendMode("ADD")
    b.hover:SetVertexColor(1, 1, 1, Minion.HOVER)
    b.hover:SetPoint("CENTER")
    b.hover:Hide()
    b.ring = b:CreateTexture(nil, "OVERLAY")
    b.ring:SetTexture(Minion.RING)
    b.ring:SetPoint("CENTER")
    p.badge = b
    -- Slim bar's portrait, just left of the bar.
    b.mini = p:CreateTexture(nil, "ARTWORK")
    b.mini:Hide()
end

-- kind: "badge", "bar" or false. h: bar height.
function Minion.Layout(p, c, kind, h)
    local b = p.badge
    b.mini:SetShown(kind == "bar")
    if kind == "bar" then
        local s = math.floor(h * 1.6 + 0.5)
        b.mini:SetSize(s, s)
        b.mini:ClearAllPoints()
        b.mini:SetPoint("RIGHT", p.hp, "LEFT", -2, 0)
    end
    local on = kind == "badge"
    b:SetShown(on)
    if not on then return end
    local s = c.minionSize or 30
    b:ClearAllPoints()
    b:SetPoint("CENTER", p.hp, "CENTER", 0, 0)
    b:SetSize(s, s)
    local inner = s * Minion.RING_INNER
    b.ring:SetSize(s, s)
    b.glow:SetSize(s * 2, s * 2)
    b.shadow:SetSize(s * 1.3, s * 1.3)
    b.disc:SetSize(inner + 2, inner + 2)
    b.icon:SetSize(inner, inner)
    b.hover:SetSize(inner, inner)
end

-- Portrait and ring color. For the slim bar its portrait; the bar color comes from
-- Minion.PaintBar in the plate's own color pass.
function Minion.Update(p)
    local b, u = p.badge, p.unit
    if not u then return end
    if p.minionBar then pcall(SetPortraitTexture, b.mini, u) end
    if not p.minion then return end
    pcall(SetPortraitTexture, b.icon, u)
    local element = Minion.Element(u)
    local col = element and Minion.COLORS[element]
    local r, g, bl
    if col then r, g, bl = col[1], col[2], col[3]
    else r, g, bl = Style.ReactionColor(plain(UnitReaction, u, "player")) end
    b.ring:SetVertexColor(r, g, bl, 1)
end

-- A slim totem bar in its element color, as a gradient. Pets (or hidden names)
-- keep the plate's own color.
function Minion.PaintBar(p)
    local element = p.minionBar and Minion.Element(p.unit)
    local col = element and Minion.COLORS[element]
    if not col then return end
    Style.SetBarColor(p.health, col[1], col[2], col[3])
    if DUI.Gradients then DUI.Gradients.PaintFrom(p.health, col) end
end

-- Your target's badge glows in the accent, fading in and out.
function Minion.Target(p, on)
    local b = p.badge
    if not p.minion then b.glow:SetAlpha(0); return end
    if b.lit == on then return end
    b.lit = on
    local r, g, bl = Style.Accent()
    b.glow:SetVertexColor(r, g, bl, 1)
    local from = b.glow:GetAlpha()
    DUI.Motion.Tween(b, from, on and 0.9 or 0, DUI.Motion.FAST, function(v) b.glow:SetAlpha(v) end)
end

function Minion.Hover(p, on, k)
    -- The badge's highlight keeps its share of the plate's (a disc needs more).
    if k then p.badge.hover:SetAlpha(k * Minion.HOVER / ns.Plate.HOVER) end
    p.badge.hover:SetShown(p.minion and on or false)
end

function Minion.Clear(p)
    local b = p.badge
    -- Undo what Minion.Layout showed. The plate's next minion must be laid out again
    -- (Plate.Layout skips a plate laid out the same way).
    if (p.minion or p.minionBar) and p.laid then p.laid.minion = nil end
    p.minion, p.minionBar, b.lit = nil, nil, nil
    b.mini:Hide()
    b.glow:SetAlpha(0)
    b.hover:Hide()
    b:Hide()
end

-- The game only shows enemy pet and totem plates with its CVar on, and refuses
-- to change it in combat.
function Minion.Apply()
    DUI.AfterCombat(function()
        if SetCVar then pcall(SetCVar, Minion.CVAR, ns.cfg.minions == false and "0" or "1") end
    end, "nameplates:minions")
end
