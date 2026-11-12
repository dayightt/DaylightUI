-- Extra parts a group button can carry besides the frame itself: the dispel
-- icon in a corner, the whole-frame dispel highlight (border, tint and a soft
-- glow around the frame) and buffs on the frame. Used by raid tiles and party
-- buttons. The client's aura containers fill them (Auras.DISPEL_FILTER, or
-- HARMFUL), so no aura is read and they work in combat.

local _, ns = ...
local DUI = DaylightUI
local UF, Style, Pixel = ns.UF, DUI.Style, DUI.Pixel

local GP = {}
ns.GroupParts = GP

-- A debuff you can dispel: one small icon in the tile's top-right corner,
-- edged in its dispel type's color. Filled by the client's aura container.
GP.DISPEL_FILTER = ns.Auras.DISPEL_FILTER

local function dispelLayout(size)
    return { layoutIndex = 1, elementWidth = size, elementHeight = size, elementSpacing = 0, lineSpacing = 0 }
end

-- With "only mine" off, the same icon takes any debuff that has a dispel type.
-- It's a second group, so the filter doesn't have to change.
GP.DISPEL_ALL_FILTER = "HARMFUL"

-- The glow uses the shell's soft shadow art (Media/shadow.png, a corner whose
-- solid core fills its inner half), cropped to the fading half and drawn in
-- ADD, so the dispel color lights the tile's edge and fades out GLOW_PX past
-- it. Crops are { left, right, top, bottom } with the outside always toward
-- the art's clear end. The edges use a single line of it.
GP.GLOW_ART = DUI.MEDIA .. "shadow.png"
GP.GLOW_PX = 6
GP.GLOW_KEYS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOP", "BOTTOM", "LEFT", "RIGHT" }
GP.GLOW_COORDS = {
    TOPLEFT = { 0, 0.5, 0, 0.5 }, TOPRIGHT = { 0.5, 0, 0, 0.5 },
    BOTTOMLEFT = { 0, 0.5, 0.5, 0 }, BOTTOMRIGHT = { 0.5, 0, 0.5, 0 },
    TOP = { 0.99, 1, 0, 0.5 }, BOTTOM = { 0.99, 1, 0.5, 0 },
    LEFT = { 0, 0.5, 0.99, 1 }, RIGHT = { 0.5, 0, 0.99, 1 },
}

-- The whole-tile highlight: a tint over the health bar and a border around the
-- tile, both colored by the debuff's dispel type. owner is the frame they
-- belong to: the aura button, so the client colors and shows them, or a sample
-- tile's own frame. The glow is made separately (GP.MakeGlow) because it sits
-- lower, under the portrait.
function GP.MakeHighlight(owner)
    local function tex(layer)
        local t = owner:CreateTexture(nil, layer)
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:Hide()
        return t
    end
    local hl = { tint = tex("BACKGROUND"), strips = {}, glow = {} }
    for i = 1, 4 do hl.strips[i] = tex("BORDER") end
    return hl
end

-- The glow's eight pieces on owner (a glow button or a sample's glow frame).
function GP.MakeGlow(owner)
    local glow = {}
    for _, key in ipairs(GP.GLOW_KEYS) do
        local t = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetTexture(GP.GLOW_ART)
        t:SetTexCoord(unpack(GP.GLOW_COORDS[key]))
        t:SetBlendMode("ADD")
        t:Hide()
        glow[key] = t
    end
    return glow
end

-- How far a tile's own pieces reach above its top and below its bottom:
-- Ribbon's name row and power line (UF.Layout's f.hitTop, f.foot), so the glow
-- and target outline wrap the whole ribbon.
function GP.Reach(b)
    if not b.ribbon then return 0, 0 end
    return b.hitTop or 0, b.foot or 0
end

-- How far an end's outer line sits past the tile's side at the top and bottom
-- of the reach (negative is inward). 0, 0 for a straight end. Continues the
-- tile's angle over Ribbon's row and line, like the target outline.
local function endLean(sl, end_, H, up, down)
    if not sl or not (sl.side == end_ or sl.side == "both") then return 0, 0 end
    local cut = sl.cut or 0
    if cut <= 0 or type(H) ~= "number" or H <= 0 then return 0, 0 end
    local slope = cut / H
    if sl.under == end_ then return -cut - slope * up, slope * down end
    return slope * up, -cut - slope * down
end

-- Lays the glow's pieces around tile b, reaching G past its edges (and past
-- Ribbon's row and line). An angled end's light is one strip leaning along the
-- cut with its far corners sheared (like the target outline's angled end), its
-- corners at the cut's two ends.
local function placeGlow(glow, b, G)
    local up, down = GP.Reach(b)
    local sl, H = Style.GetSlant(b), b:GetHeight()
    local lt, lb = endLean(sl, "left", H, up, down)
    local rt, rb = endLean(sl, "right", H, up, down)
    for _, t in pairs(glow) do t:ClearAllPoints() end
    for _, key in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do glow[key]:SetSize(G, G) end
    glow.TOPLEFT:SetPoint("BOTTOMRIGHT", b, "TOPLEFT", -lt, up)
    glow.BOTTOMLEFT:SetPoint("TOPRIGHT", b, "BOTTOMLEFT", -lb, -down)
    glow.TOPRIGHT:SetPoint("BOTTOMLEFT", b, "TOPRIGHT", rt, up)
    glow.BOTTOMRIGHT:SetPoint("TOPLEFT", b, "BOTTOMRIGHT", rb, -down)
    glow.TOP:SetPoint("BOTTOMLEFT", b, "TOPLEFT", -lt, up)
    glow.TOP:SetPoint("TOPRIGHT", b, "TOPRIGHT", rt, G + up)
    glow.BOTTOM:SetPoint("TOPLEFT", b, "BOTTOMLEFT", -lb, -down)
    glow.BOTTOM:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", rb, -G - down)
    -- The sides: a strip G across (wider by the slope when leaning), from the
    -- end's inner corner outward. The corner that sticks out is sheared to it.
    -- Vertices: 1 upper left, 2 lower left, 3 upper right, 4 lower right.
    local Hr = (type(H) == "number" and H or 0) + up + down
    for _, e in ipairs({ { glow.LEFT, "LEFT", lt, lb, -1 }, { glow.RIGHT, "RIGHT", rt, rb, 1 } }) do
        local t, P, top, bottom, sign = e[1], e[2], e[3], e[4], e[5]
        local lean = top - bottom
        local w = Hr > 0 and G * math.sqrt(Hr * Hr + lean * lean) / Hr or G
        local inner = math.min(top, bottom)
        local O = P == "LEFT" and "RIGHT" or "LEFT"
        t:SetPoint("TOP" .. O, b, "TOP" .. P, sign * inner, up)
        t:SetPoint("BOTTOM" .. O, b, "BOTTOM" .. P, sign * inner, -down)
        t:SetWidth(w)
        for i = 1, 4 do pcall(t.SetVertexOffset, t, i, 0, 0) end
        local pair = lean > 0 and { 1, 3 } or { 2, 4 }
        for _, i in ipairs(pair) do pcall(t.SetVertexOffset, t, i, sign * math.abs(lean), 0) end
    end
end

-- Lays the glow around tile b and shows it if cfg asks for it.
function GP.StyleGlow(glow, b, cfg)
    placeGlow(glow, b, Pixel.Px(b, GP.GLOW_PX))
    local on = cfg.dispelGlow == true
    for _, t in pairs(glow) do t:SetShown(on) end
end

-- Anchors the highlight to tile b and shows the parts cfg asks for.
function GP.StyleHighlight(hl, b, cfg)
    local mode = cfg.dispelHighlight
    local tintOn = mode == "tint" or mode == "both"
    local borderOn = mode == "border" or mode == "both"
    -- Hidden when off, since the client only shows what it was told to color.
    hl.tint:SetAlpha(cfg.dispelAlpha or 0.3)
    hl.tint:SetShown(tintOn)
    local T = Pixel.Px(b, Style.BorderPx(b))
    local s = hl.strips
    -- On an angled tile the edges stop where the cut starts, and the angled end
    -- has no straight edge since a strip can't follow the slant.
    local cut = b.cut or 0
    local cr = (b.spec and b.spec.slant == "right") and cut or 0
    for _, t in ipairs(s) do t:ClearAllPoints() end
    s[1]:SetPoint("TOPLEFT", b, "TOPLEFT"); s[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT", -cr, 0); s[1]:SetHeight(T)
    s[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); s[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -cr, 0); s[2]:SetHeight(T)
    s[3]:SetPoint("TOPLEFT", b, "TOPLEFT"); s[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); s[3]:SetWidth(T)
    s[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); s[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); s[4]:SetWidth(T)
    for i, t in ipairs(s) do t:SetShown(borderOn and not (i == 4 and cr > 0)) end
    if next(hl.glow) then GP.StyleGlow(hl.glow, b, cfg) end
    hl.tint:ClearAllPoints()
    hl.tint:SetPoint("TOPLEFT", b.health or b, "TOPLEFT")
    hl.tint:SetPoint("BOTTOMRIGHT", b.health or b, "BOTTOMRIGHT", -cr, 0)
end

function GP.InitDispel(btn, b, withoutType)
    ns.Auras.TileMouse(btn, false)
    local edge = btn:CreateTexture(nil, "BACKGROUND")
    edge:SetTexture("Interface\\Buttons\\WHITE8x8")
    edge:SetAllPoints(btn)
    local w = ns.Auras.DEBUFF_BORDER
    edge:SetVertexColor(w[1], w[2], w[3], 1)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    btn:SetIcon(icon)
    btn.dispelEdge, btn.dispelIcon = edge, icon
    btn.highlight = GP.MakeHighlight(btn)
    btn.withoutType = withoutType
    b.dispelBtns[#b.dispelBtns + 1] = btn
    -- Size and style now. The button locks once this returns, and a tile made
    -- in a battleground stays locked all match (IsForbidden won't help, it
    -- isn't locked yet at this point). Its group is added by LayoutDispel after
    -- b.dispelCfg is set.
    local cfg = b.dispelCfg
    if not cfg and b.group then cfg = b.group:Config() end
    if cfg then
        local size = tonumber(cfg.dispelSize) or 10
        btn:SetSize(size, size)
        pcall(GP.StyleDispelParts, btn, b, cfg)
    end
end

-- Tells the client what to color: the corner icon's edge if asked for, and the
-- border. Parts that are off stay hidden and unregistered.
function GP.StyleDispelButton(btn, b, cfg)
    -- A forbidden button is left alone. LayoutDispel already waits out the
    -- restrictions that lock them.
    if btn.IsForbidden then
        local ok, no = pcall(btn.IsForbidden, btn)
        if not ok or no ~= false then return end
    end
    pcall(btn.glow and GP.StyleGlowParts or GP.StyleDispelParts, btn, b, cfg)
end

function GP.StyleDispelParts(btn, b, cfg)
    local hl = btn.highlight
    GP.StyleHighlight(hl, b, cfg)
    hl.tint:Hide()  -- the tint has its own container (CreateTint)
    if btn.ClearDispelTypeTextures then btn:ClearDispelTypeTextures() end
    local reg, wt = ns.Auras.RegisterDispelEdge, btn.withoutType
    btn.dispelEdge:SetShown(cfg.showDispel == true)
    btn.dispelIcon:SetAlpha(cfg.showDispel and 1 or 0)
    if cfg.showDispel then reg(btn, btn.dispelEdge, wt) end
    -- From the settings, never IsShown: a registered strip's IsShown is secret.
    local mode = cfg.dispelHighlight
    if mode == "border" or mode == "both" then
        for _, t in ipairs(hl.strips) do reg(btn, t, wt) end
    end
end

-- One glow button (its group is added by LayoutDispel while the glow is on):
-- the glow's pieces around the tile, colored by the client.
function GP.InitGlow(btn, b, withoutType)
    ns.Auras.TileMouse(btn, false)
    btn:SetSize(8, 8)
    btn.glow = GP.MakeGlow(btn)
    btn.withoutType = withoutType
    b.glowBtns[#b.glowBtns + 1] = btn
    -- Style it now, like InitDispel, since the button locks when this returns.
    local cfg = b.dispelCfg
    if not cfg and b.group then cfg = b.group:Config() end
    if cfg then pcall(GP.StyleGlowParts, btn, b, cfg) end
end

function GP.StyleGlowParts(btn, b, cfg)
    GP.StyleGlow(btn.glow, b, cfg)
    if btn.ClearDispelTypeTextures then btn:ClearDispelTypeTextures() end
    if cfg.dispelGlow ~= true then return end
    for key, t in pairs(btn.glow) do
        local c = GP.GLOW_COORDS[key]
        ns.Auras.RegisterDispelEdge(btn, t, btn.withoutType, GP.GLOW_ART,
            { left = c[1], right = c[2], top = c[3], bottom = c[4] })
    end
end

-- Adds a group to one of the tile's own containers the first time it's needed.
-- The client builds its buttons at that point, from b.dispelCfg. Returns true
-- when the group exists.
local function addGroup(c, key, filter, size, init)
    if c.dluiGroups[key] then return true end
    local ok = pcall(function()
        c:AddAuraGroup(key, filter, {
            sortMethod = AuraContainerSortMethod.ExpirationOnly,
            sortDirection = AuraContainerSortDirection.Normal,
            maxFrameCount = 0, layout = dispelLayout(size), initializeFrame = init,
        })
    end)
    if ok then c.dluiGroups[key] = true end
    return ok
end

-- The corner icon's container. Its groups (only mine, or any with a type) are
-- added by LayoutDispel when needed.
function GP.CreateDispel(b)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not ok or not c then return end
    c:EnableMouse(false)
    c:SetFrameLevel(b:GetFrameLevel() + 8)
    c.dluiGroups = {}
    b.dispelBtns = {}
    b.dispel = c
end

GP.DISPEL_GROUPS = { dispel = { GP.DISPEL_FILTER, true }, dispelAll = { GP.DISPEL_ALL_FILTER, false } }
GP.TINT_GROUPS = { tint = { GP.DISPEL_FILTER, true }, tintAll = { GP.DISPEL_ALL_FILTER, false } }

-- The tint: a second container whose single button is a tile-sized wash over
-- the health bar. The client ignores opacity on the texture it colors, so the
-- strength comes from the container's own alpha.
function GP.CreateTint(b)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not ok or not c then return end
    c:EnableMouse(false)
    c:SetFrameLevel((b.health or b):GetFrameLevel() + 1)
    c:SetAlpha(0.3)
    -- The wash covers the health bar up to an angled end's cut
    -- (GP.LayoutDispel re-points it on every layout).
    b.tintArea = CreateFrame("Frame", nil, b)
    b.tintArea:SetAllPoints(b.health or b)
    c.dluiGroups = {}
    b.tint = c
end

-- The glow: a third container just above the tile (the target outline's level)
-- so the portrait and name tab lie over it. On the corner icon's container it
-- lit up over the portrait.
GP.GLOW_GROUPS = { glow = { GP.DISPEL_FILTER, true }, glowAll = { GP.DISPEL_ALL_FILTER, false } }
function GP.CreateGlow(b)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not ok or not c then return end
    c:EnableMouse(false)
    c:SetFrameLevel(b:GetFrameLevel() + 1)
    c.dluiGroups = {}
    b.glowBtns = {}
    b.glowBox = c
end

-- One tint button (its group is added by LayoutDispel while the tint is on).
function GP.InitTint(btn, b, withoutType)
    ns.Auras.TileMouse(btn, false)
    btn:SetSize(8, 8)
    local t = btn:CreateTexture(nil, "BACKGROUND")
    t:SetTexture("Interface\\Buttons\\WHITE8x8")
    -- Fills the area frame. Once the client colors the texture it becomes
    -- forbidden to addon code, so layouts move the area instead.
    t:SetAllPoints(b.tintArea)
    ns.Auras.RegisterDispelEdge(btn, t, withoutType)
end

-- Sizes the corner icon and points the container at the tile's unit.
function GP.LayoutDispel(b, cfg)
    local c = b.dispel
    if not c then return end
    local size = cfg.dispelSize
    local T = Pixel.Px(b, Style.BorderPx(b))
    local spot = cfg.dispelPos or "topright"
    UF.PlaceSpot(c, b, b, spot, T + UF.CornerPad(b, spot) - 1, T, cfg.dispelX, cfg.dispelY)
    c:SetSize(size, size)
    -- Before the counts below, since a count can build a button styled from this.
    b.dispelCfg = cfg
    -- A group must exist for the highlight too, even with the icon off. Only
    -- the one in use is added, and its buttons are built then from cfg.
    local on = (cfg.showDispel or (cfg.dispelHighlight or "none") ~= "none") and 1 or 0
    local mine = cfg.dispelOnlyMine ~= false
    for key, n in pairs({ dispel = mine and on or 0, dispelAll = mine and 0 or on }) do
        local g = GP.DISPEL_GROUPS[key]
        if n > 0 then
            addGroup(c, key, g[1], size, function(btn) GP.InitDispel(btn, b, g[2]) end)
        end
        if c.dluiGroups[key] then
            pcall(c.SetAuraGroupLayout, c, key, dispelLayout(size))
            pcall(c.SetAuraGroupMaxFrameCount, c, key, n)
        end
    end
    local t = b.tint
    if t then
        local mode = cfg.dispelHighlight
        local tintOn = (mode == "tint" or mode == "both") and 1 or 0
        t:SetPoint("TOPLEFT", b, "TOPLEFT")
        t:SetSize(8, 8)
        t:SetAlpha(cfg.dispelAlpha or 0.3)
        for key, n in pairs({ tint = mine and tintOn or 0, tintAll = mine and 0 or tintOn }) do
            local g = GP.TINT_GROUPS[key]
            if n > 0 then
                addGroup(t, key, g[1], 8, function(btn) GP.InitTint(btn, b, g[2]) end)
            end
            if t.dluiGroups[key] then
                pcall(t.SetAuraGroupLayout, t, key, dispelLayout(8))
                pcall(t.SetAuraGroupMaxFrameCount, t, key, n)
            end
        end
    end
    local gb = b.glowBox
    if gb then
        local glowOn = cfg.dispelGlow == true and 1 or 0
        gb:SetPoint("TOPLEFT", b, "TOPLEFT")
        gb:SetSize(8, 8)
        for key, n in pairs({ glow = mine and glowOn or 0, glowAll = mine and 0 or glowOn }) do
            local g = GP.GLOW_GROUPS[key]
            if n > 0 then
                addGroup(gb, key, g[1], 8, function(btn) GP.InitGlow(btn, b, g[2]) end)
            end
            if gb.dluiGroups[key] then
                pcall(gb.SetAuraGroupLayout, gb, key, dispelLayout(8))
                pcall(gb.SetAuraGroupMaxFrameCount, gb, key, n)
            end
        end
    end
    -- The tint stops where an angled end's cut starts.
    local cr = (b.spec and b.spec.slant == "right") and (b.cut or 0) or 0
    local area = b.tintArea
    if area then
        area:ClearAllPoints()
        area:SetPoint("TOPLEFT", b.health or b, "TOPLEFT")
        area:SetPoint("BOTTOMRIGHT", b.health or b, "BOTTOMRIGHT", -cr, 0)
    end
    -- The client locks its aura buttons while auras are secret (combat, a PvP
    -- match, a boss). They get the new look once that lifts.
    DUI.AfterRestrictions(function()
        for _, btn in ipairs(b.dispelBtns) do GP.StyleDispelButton(btn, b, b.dispelCfg) end
        for _, btn in ipairs(b.glowBtns or {}) do GP.StyleDispelButton(btn, b, b.dispelCfg) end
    end, "dispel:" .. tostring(b))
end

local function pointAt(c, unit)
    if not c then return end
    pcall(c.SetUnit, c, unit)
    pcall(c.UpdateAllAuras, c)
end

-- Points every aura container on the button at its unit and refreshes.
function GP.PointAuras(b)
    if type(b.unitToken) ~= "string" then return end
    pointAt(b.dispel, b.unitToken)
    pointAt(b.tint, b.unitToken)
    pointAt(b.glowBox, b.unitToken)
    ns.AuraGroups.SetUnit(b.auraSet, b.unitToken)
end

-- From the range ticker: "only mine" buffs hide while the unit is out of sight
-- range. A secret answer leaves them as they are.
function GP.UpdateBuffsSeen(b)
    if type(b.unitToken) ~= "string" then return end
    local ok, seen = pcall(UnitIsVisible, b.unitToken)
    if not ok or (issecretvalue and issecretvalue(seen)) then return end
    seen = seen == true
    ns.Auras.SetBuffsSeen(b.auraSet and b.auraSet.buffs, seen)
    ns.Indicators.SetSeen(b.auraSet, seen)
end

-- Your target's tile: a thin ring just outside its border so it never covers
-- health, threat red or a dispel border, in the accent or a custom color
-- (targetMark, targetMarkColor, targetMarkCustom). The ring is a border-only
-- shell, so it gets the tile's rounded corners and angled end. It sits under
-- the portrait and the aura rows.
GP.MARK_PX = 2
function GP.MakeTargetMark(b)
    local f = CreateFrame("Frame", nil, b)
    f:SetFrameLevel(b:GetFrameLevel() + 1)
    f:EnableMouse(false)
    f.ring = Style.Shell(f, { borderPx = GP.MARK_PX, flat = true, noBackground = true, noBevel = true,
        shadowAlpha = 0, noCutFill = true })
    -- Its corner caps would fill around the tile's corners from above
    -- everything, covering the portrait.
    if f.ring then f.ring.over:Hide() end
    -- The angled end: one strip a border thick, its far end sheared along the
    -- cut (like the shell's own shadows lean).
    f.cutEdge = {}
    for _, side in ipairs({ "left", "right" }) do
        local t = (f.ring or f):CreateTexture(nil, "BORDER", nil, 0)
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:Hide()
        f.cutEdge[side] = t
    end
    f:SetAlpha(0)
    f:Hide()
    b.targetMark = f
    return f
end

-- Places the ring around tile b, continuing its angle, and paints it from cfg.
function GP.LayoutTargetMark(b, cfg)
    local f = b.targetMark
    if not f then return end
    b.markOn = cfg.targetMark ~= false
    local T = Pixel.Px(b, GP.MARK_PX)
    -- Same angle as the tile: its cut over a frame 2T taller, and around
    -- Ribbon's row and line too (GP.Reach). Being taller above, the angled end
    -- moves out by as much as the slope runs over the row, so the line passes
    -- the tile's corner the same way it would without it.
    local up, down = GP.Reach(b)
    local sl = Style.GetSlant(b)
    local side, cut, under = sl and sl.side, sl and sl.cut or 0, sl and sl.under
    local H = b:GetHeight()
    local angled = side and cut > 0 and type(H) == "number" and H > 0
    local slope = angled and cut / H or 0
    local outL = (side == "left" or side == "both") and slope * up or 0
    local outR = (side == "right" or side == "both") and slope * up or 0
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", b, "TOPLEFT", -T - outL, T + up)
    f:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", T + outR, -T - down)
    local ringH = angled and H + 2 * T + up + down or 0
    local cutR = angled and slope * ringH or 0
    if angled then
        Style.Slant(f, side, cutR, nil, under)
    elseif Style.GetSlant(f) then
        Style.Slant(f, nil, 0)
    elseif f.ring then
        Style.LayoutShell(f.ring)
    end
    local s = f.ring
    if not s then return end
    local c = cfg.targetMarkCustom
    local custom = cfg.targetMarkColor == "custom" and type(c) == "table"
    if custom then
        Style.SetShellColors(s, { c[1], c[2], c[3] }, nil, nil)
    else
        -- A gradient accent sweeps along it.
        Style.LightShell(s)
    end
    GP.LayoutCutEdges(f, angled and side, cutR, under, T, custom and c, angled and ringH)
    if not b.markOn then
        b.markWas, b.markA = nil, nil
        f:SetAlpha(0)
        f:Hide()
    end
end

-- The ring's angled end(s): a strip T thick (wider by the slope) at the end's
-- outer corner, its other end sheared in by the cut. Painted like the shell's
-- side there: the custom color, the gradient accent's end on that side, or the
-- accent. H is the ring's height (the tile's plus two borders).
function GP.LayoutCutEdges(f, side, cut, under, T, custom, H)
    local lo, hi = Style.AccentPair()
    local a = DUI:Get("general", "borderAlpha") or 1
    for _, end_ in ipairs({ "left", "right" }) do
        local t = f.cutEdge[end_]
        local on = (side == end_ or side == "both") and type(H) == "number" and H > 0
        if on then
            local w = T * math.sqrt(H * H + cut * cut) / H
            local P = end_:upper()
            local sign = end_ == "right" and -1 or 1
            t:ClearAllPoints()
            t:SetPoint("TOP" .. P, f, "TOP" .. P, 0, 0)
            t:SetPoint("BOTTOM" .. P, f, "BOTTOM" .. P, 0, 0)
            t:SetWidth(w)
            -- 1 upper left, 2 lower left, 3 upper right, 4 lower right. The
            -- corner sticking out is the top one, or the bottom one at an end
            -- leaning under.
            local inTop = under == end_
            for i = 1, 4 do pcall(t.SetVertexOffset, t, i, 0, 0) end
            local pair = inTop and { 1, 3 } or { 2, 4 }
            for _, i in ipairs(pair) do pcall(t.SetVertexOffset, t, i, sign * cut, 0) end
            if custom then
                t:SetVertexColor(custom[1], custom[2], custom[3], a)
            elseif lo then
                local e = end_ == "left" and lo or hi
                t:SetVertexColor(e[1], e[2], e[3], a)
            else
                local r, g, bl = Style.Accent()
                t:SetVertexColor(r, g, bl, a)
            end
        end
        t:SetShown(on == true)
    end
end

-- Shows the outline while the tile's unit is your target. In a battleground
-- the answer can be secret, and the client then sets the alpha from it.
function GP.UpdateTargetMark(b)
    local f = b.targetMark
    if not f or not b.markOn then return end
    local unit = b.unitToken
    local ok, is = false, nil
    if type(unit) == "string" then ok, is = pcall(UnitIsUnit, unit, "target") end
    if ok and issecretvalue and issecretvalue(is) then
        b.markWas, b.markA = nil, nil
        DUI.Motion.Tween("tmark:" .. tostring(b), 0, 0, 0)   -- stops a plain fade
        f:Show()
        f:SetAlphaFromBoolean(is, 1, 0)
        return
    end
    local want = ok and is == true
    if want == b.markWas then return end
    b.markWas = want
    f:Show()
    -- Start from wherever a running fade left it (a quick target hop).
    DUI.Motion.Tween("tmark:" .. tostring(b), b.markA or 0, want and 1 or 0, DUI.Motion.FAST, function(a)
        b.markA = a
        f:SetAlpha(a)
    end)
end

-- Every group tile, on a target change.
function GP.UpdateTargetMarks()
    for _, b in ns.Group.Buttons() do GP.UpdateTargetMark(b) end
end
