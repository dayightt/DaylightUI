-- Heal indicators on party and raid tiles. A small square per watched spell of
-- yours (Renew, Power Word: Shield, Weakened Soul...), in the spell's color
-- from HealSpells.lua or a custom one, each at its own Spots spot, with the
-- remaining time drawn as the client's swipe. The client's aura container
-- finds the aura by spell id (every rank) and only shows the square while it's
-- up. No aura is read, so it works in combat and battlegrounds.
--
-- look = "square" (the spell's color) or "icon" (the aura's own icon, filled
-- by the client and edged in the spell's color).
-- Settings: <party|raid>.indicators = { show, size, swipe, look, i1..i6 = {
-- show, spell ("auto" = your class's pick for that square, else a rank 1 id),
-- spot, x, y, paint (spell|custom), custom } }.
--
-- Each square is its own container since it has its own spot. It's created
-- the first time it's on (out of combat) and kept. Each spell it has watched
-- gets its own group, because a group's filter is fixed when added and the
-- client builds 10 buttons for it then, so a spell change only changes counts.
-- A buff kept up for minutes (HealSpells `long`, e.g. Oath of Light) also
-- counts down its last minute in the warning color. The client writes the
-- time through a formatter that stays blank until then, so it's correct in
-- combat.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel, Gradients = DUI.Style, DUI.Pixel, DUI.Gradients

local Ind = {}
ns.Indicators = Ind

Ind.SLOTS = { "i1", "i2", "i3", "i4", "i5", "i6" }
-- Shade the elapsed time on the square, like the aura icons (Auras.StyleSwipe).
Ind.SWIPE_ALPHA = 0.6
-- How many squares sample tile i shows (the full sample shows all of them).
Ind.SAMPLE_COUNTS = { 2, 0, 1, 3, 0, 1, 0, 2 }
-- The fraction of time left each sample square shows.
Ind.SAMPLE_LEFT = { 0.7, 0.4, 0.85, 0.55, 0.3, 0.95 }
-- A sample square's icon with no spell picked.
Ind.SAMPLE_ICON = "Interface/Icons/INV_Misc_QuestionMark"
-- The seconds a long buff's sample square counts down from.
Ind.SAMPLE_TIME = 42

local squares = setmetatable({}, { __mode = "k" })   -- container -> { [btn] = { fill, cd } }

-- The time left, centered on the square, for a long buff's last minute.
local function timeText(f)
    local fs = Style.Text(f, Style.SIZE.tiny, "CENTER")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    Style.InkText(fs, "WARN")
    return fs
end

-- Square i's color under its settings g, as r, g, b.
function Ind.ColorFor(i, g)
    if type(g) == "table" and g.paint == "custom" and type(g.custom) == "table" then
        return g.custom[1], g.custom[2], g.custom[3]
    end
    return ns.HealSpells.ColorOf(ns.HealSpells.SpellFor(i, type(g) == "table" and g.spell or nil))
end

local function paint(tex, r, g, b)
    local lo, hi = Gradients.PairFrom({ r, g, b })
    Gradients.PaintPair(tex, lo, hi)
end

-- The square's pieces inside f (a client button or a stand-in): a dark edge,
-- the colored fill, and a cooldown for the swipe.
local function build(f)
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(f)
    local k = Style.BACKGROUND
    edge:SetColorTexture(k[1], k[2], k[3], 0.9)
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    local icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
    Style.CropIcon(icon)
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetDrawEdge(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    cd:SetHideCountdownNumbers(true)
    cd:EnableMouse(false)
    return { edge = edge, fill = fill, icon = icon, cd = cd }
end

local function dress(f, p, st)
    f:SetSize(st.size, st.size)
    local T = Pixel.Px(f, 1)
    p.fill:ClearAllPoints()
    p.fill:SetPoint("TOPLEFT", f, "TOPLEFT", T, -T)
    p.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T, T)
    paint(p.fill, st.r, st.g, st.b)
    p.icon:ClearAllPoints()
    p.icon:SetAllPoints(p.fill)
    -- The icon look: the aura's icon, edged in the spell's color.
    local iconLook = st.look == "icon"
    p.fill:SetShown(not iconLook)
    p.icon:SetShown(iconLook)
    if iconLook then
        p.edge:SetColorTexture(st.r, st.g, st.b, 1)
    else
        local k = Style.BACKGROUND
        p.edge:SetColorTexture(k[1], k[2], k[3], 0.9)
    end
    p.cd:SetAllPoints(p.fill)
    p.cd:SetDrawSwipe(st.swipe)
    if st.swipe then
        p.cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        p.cd:SetSwipeColor(0, 0, 0, Ind.SWIPE_ALPHA)
        p.cd:SetReverse(true)
    end
end

-- Styles the client's button for a square. It's locked afterwards whenever
-- auras are secret, so later changes go through restyle.
local function initButton(c, btn, id)
    ns.Auras.TileMouse(btn, false)   -- clicks and hover go to the tile
    local p = build(btn)
    btn:SetIcon(p.icon)
    btn:SetDurationCooldown(p.cd)
    if id and ns.HealSpells.IsLong(id) then
        p.time = timeText(btn)
        Style.SetAuraTime(btn, p.time, nil, Style.DurationFormatter(ns.HealSpells.LONG_WARN))
    end
    dress(btn, p, c.dluiInd)
    squares[c] = squares[c] or setmetatable({}, { __mode = "k" })
    squares[c][btn] = p
end

local function layoutOf(size)
    return { layoutIndex = 1, elementWidth = size, elementHeight = size, elementSpacing = 0, lineSpacing = 0 }
end

-- Size, color or swipe changed. Restyle every button made so far, once the
-- client allows it (DUI.AfterRestrictions).
local function restyle(c)
    DUI.AfterRestrictions(function()
        local st = c.dluiInd
        for id in pairs(c.dluiIndGroups) do
            pcall(c.SetAuraGroupLayout, c, "s" .. id, layoutOf(st.size))
            if c.dluiIndOthers[id] then pcall(c.SetAuraGroupLayout, c, "s" .. id .. "o", layoutOf(st.size)) end
        end
        for btn, p in pairs(squares[c] or {}) do pcall(dress, btn, p, st) end
    end, "indicators:" .. tostring(c))
end

local function addOne(c, key, filter, candidates, id)
    return pcall(c.AddAuraGroup, c, key, filter, {
        candidateFilters = candidates,
        maxFrameCount = 0,
        layout = layoutOf(c.dluiInd.size),
        initializeFrame = function(btn) initButton(c, btn, id) end,
    })
end

local function addGroup(c, id)
    if c.dluiIndGroups[id] then return true end
    local ok = addOne(c, "s" .. id, ns.HealSpells.FilterOf(id), ns.HealSpells.CandidatesOf(id), id)
    if ok then
        c.dluiIndGroups[id] = true
        local others = ns.HealSpells.OthersOf(id)
        if others then c.dluiIndOthers[id] = addOne(c, "s" .. id .. "o", others.filter, others.candidates) end
    end
    return ok
end

local function newSquare(set, frame)
    if set.plain then
        local f = CreateFrame("Frame", nil, frame)
        f:EnableMouse(false)
        f:SetFrameLevel(frame:GetFrameLevel() + 9)   -- above the aura rows, like the real ones
        f.plain = true
        f.parts = build(f)
        f:Hide()
        return f
    end
    if InCombatLockdown() then return nil end   -- its parent may be protected
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    c:EnableMouse(false)
    c:SetFrameLevel(frame:GetFrameLevel() + 9)
    pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT")
    local unit = type(frame.unitToken) == "string" and frame.unitToken or set.unit
    if type(unit) == "string" then pcall(c.SetUnit, c, unit) end
    c.dluiInd, c.dluiIndGroups, c.dluiIndOthers = { size = 8, r = 1, g = 1, b = 1, swipe = true, look = "square" }, {}, {}
    return c
end

-- The square's counts: the shown spell on, every other one off. All off while
-- the unit is out of sight, since the game can't tell whose auras they are.
local function counts(c)
    for id in pairs(c.dluiIndGroups) do
        local n = (id == c.dluiIndOn and not c.dluiUnseen) and 1 or 0
        pcall(c.SetAuraGroupMaxFrameCount, c, "s" .. id, n)
        if c.dluiIndOthers[id] then pcall(c.SetAuraGroupMaxFrameCount, c, "s" .. id .. "o", n) end
    end
end

-- Places set's squares on frame from the frame's indicator settings cfg.
-- The parent is protected (a group button), so squares are only made out of combat.
function Ind.Place(set, frame, cfg, box)
    if not set then return end
    cfg = type(cfg) == "table" and cfg or {}
    set.ind = set.ind or {}
    local size = math.max(2, math.floor(tonumber(cfg.size) or 8))
    local swipe = cfg.swipe ~= false
    local look = cfg.look == "icon" and "icon" or "square"
    for i, key in ipairs(Ind.SLOTS) do
        local g = type(cfg[key]) == "table" and cfg[key] or {}
        local on = cfg.show == true and g.show == true
        local id = on and ns.HealSpells.SpellFor(i, g.spell) or nil
        local c = set.ind[i]
        -- A stand-in shows whenever its square is on, spell or not, so a class
        -- without a pick still sees it, and can place and size it.
        if (id or (on and set.plain)) and not c then
            c = newSquare(set, frame)
            set.ind[i] = c
        end
        if c then
            c.dluiLong = id and ns.HealSpells.IsLong(id) or nil
            local L = ns.Spots.Layout(g.spot, "right", box, { x = g.x, y = g.y, line = size })
            c:ClearAllPoints()
            c:SetPoint(L.point, frame, L.relPoint, L.x, L.y)
            c:SetSize(size, size)
            local r, gg, b = Ind.ColorFor(i, g)
            if c.plain then
                c.on = on or nil
                -- A sample's icon is the spell's own, since there's no aura to fill it.
                local tex = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                c.parts.icon:SetTexture(tex or Ind.SAMPLE_ICON)
                dress(c, c.parts, { size = size, r = r, g = gg, b = b, swipe = swipe, look = look })
            else
                local st = c.dluiInd
                local changed = st.size ~= size or st.r ~= r or st.g ~= gg or st.b ~= b or st.swipe ~= swipe
                    or st.look ~= look
                st.size, st.r, st.g, st.b, st.swipe, st.look = size, r, gg, b, swipe, look
                if id then addGroup(c, id) end
                c.dluiIndOn = id
                counts(c)
                if changed then restyle(c) end
                pcall(c.UpdateAllAuras, c)
            end
        end
    end
end

-- Both walk every real square of set (set.ind), skipping stand-ins.
function Ind.SetUnit(set, unit)
    if type(unit) ~= "string" or not (set and set.ind) then return end
    for _, c in pairs(set.ind) do
        if not c.plain then
            pcall(c.SetUnit, c, unit)
            pcall(c.UpdateAllAuras, c)
        end
    end
end

-- seen: the unit is within sight range. Called by GroupParts' range ticker for
-- every tile 5 times a second, so no closures or tables per call.
function Ind.SetSeen(set, seen)
    if not (set and set.ind) then return end
    local unseen = not seen
    for _, c in pairs(set.ind) do
        if not c.plain and c.dluiUnseen ~= unseen then
            c.dluiUnseen = unseen
            counts(c)
        end
    end
end

-- Stand-ins for the options preview and /dui test, placed like real squares.
-- Every square that's on shows, in a calm stand-in color when it has no spell
-- (HealSpells.ColorOf). Sample tile i shows Ind.SAMPLE_COUNTS[i] of them, the
-- full sample shows all.
function Ind.ShowSample(set, frame, cfg, box, i)
    if not set then return end
    Ind.Place(set, frame, cfg, box)
    local n = i and Ind.SAMPLE_COUNTS[(i - 1) % #Ind.SAMPLE_COUNTS + 1] or #Ind.SLOTS
    local shown = 0
    for k = 1, #Ind.SLOTS do
        local c = set.ind[k]
        if c and c.plain then
            local on = c.on ~= nil and shown < n
            if on then
                shown = shown + 1
                -- The sweep frozen at its fraction left, like the aura samples.
                local cd, span = c.parts.cd, ns.Auras.SAMPLE_SWIPE_SPAN
                if type(cfg) == "table" and cfg.swipe ~= false then
                    cd:SetCooldown(GetTime() - (1 - Ind.SAMPLE_LEFT[k]) * span, span)
                    cd:Show()
                else
                    cd:Hide()
                end
                -- A long buff's countdown, as it looks in its last minute.
                if c.dluiLong and not c.parts.time then c.parts.time = timeText(c) end
                if c.parts.time then
                    c.parts.time:SetText(string.format(Style.DURATION_STEPS[2].format, Ind.SAMPLE_TIME))
                    c.parts.time:SetShown(c.dluiLong == true)
                end
            end
            c:SetShown(on)
        end
    end
end

function Ind.HideSample(set)
    for _, c in pairs(set and set.ind or {}) do
        if c.plain then c:Hide() end
    end
end
