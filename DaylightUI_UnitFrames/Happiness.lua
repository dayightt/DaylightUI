-- A hunter pet's happiness. Three looks (pet.happinessLook): a square filled
-- with the mood's color ("square", the default, readable at any size), the
-- game's mood face ("icon"), or a stripe inside the frame ("frame") on the
-- left or right (pet.happinessSide). Red is unhappy, yellow content, green
-- happy (a happy pet does more damage and gains loyalty). The square keeps
-- the frame's own edge. The mood face sits on its own, with no box around it.
-- The stripe is separated from the bars like health is from power. On an
-- angled end the bars stay straight and the stripe fills out to the frame's
-- angle. The square and the face are placed like
-- the corner icons via happinessSpot/X/Y, sized by happinessSize. The tooltip
-- mirrors the game's own indicator: mood, damage, loyalty gain or loss, and
-- diet. Hunter pets only. The character window's pet page keeps the game's face.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Happiness = {}
ns.Happiness = Happiness

Happiness.ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }
-- The old pet-happiness sheet is three faces in its top band. A client that
-- hands that whole sheet back as one atlas shows a sliced face unless these
-- coordinates pick one.
Happiness.SHEET = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
Happiness.SHEET_COORD = {
    { 0.375, 0.5625, 0, 0.359375 },
    { 0.1875, 0.375, 0, 0.359375 },
    { 0, 0.1875, 0, 0.359375 },
}
Happiness.COLORS = {
    [1] = { 0.9, 0.25, 0.22 },     -- unhappy
    [2] = { 1.0, 0.82, 0.25 },     -- content
    [3] = { 0.35, 0.8, 0.35 },     -- happy
}
Happiness.STRIPE = 4             -- the in-frame stripe, about a power bar tall

local function widget(f)
    if f and f.happiness then return f.happiness end
    if ns.happiness and f and ns.happiness.pet == f then return ns.happiness end
end

function Happiness.Integrated(cfg)
    return type(cfg) == "table" and cfg.happiness == true and cfg.happinessLook == "frame"
end

-- The stripe, once the frame exists. Parent is the pet frame, so hiding the
-- square doesn't hide it. Clipped to the frame's angle.
local function ensureBand(h)
    if h.stripe then return end
    local pet = h.pet
    local band = CreateFrame("Frame", nil, pet)
    band:SetAllPoints(pet)
    if pet.overlay then band:SetFrameLevel(math.max(pet.health:GetFrameLevel() + 1, pet.overlay:GetFrameLevel() - 1)) end
    h.band = band
    h.stripe = band:CreateTexture(nil, "ARTWORK")
    h.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    h.gap = Style.Separator(band)
    if pet.spec and pet.spec.slant then
        Style.Clip(pet, h.stripe, "inner", "inner", "right")
        Style.Clip(pet, h.gap, "inner", "inner", "right")
    end
    band:Hide()
end

local function barTextures(f)
    local t = {}
    local function add(tex) if tex then t[#t + 1] = tex end end
    add(f.health and f.health:GetStatusBarTexture())
    add(f.health and Style.BarBack(f.health))
    if f.power then
        add(f.power:GetStatusBarTexture())
        add(Style.BarBack(f.power))
        add(f.separator)
    end
    if f.heals then
        add(f.heals:GetStatusBarTexture())
        if f.heals.wedge then add(f.heals.wedge:GetStatusBarTexture()) end
    end
    if f.absorbs then
        add(f.absorbs:GetStatusBarTexture())
        if f.absorbs.wedge then add(f.absorbs.wedge:GetStatusBarTexture()) end
    end
    if f.overshield then
        add(f.overshield:GetStatusBarTexture())
        add(f.overshield.glow)
    end
    return t
end

-- Lay the stripe out and tell the frame how far the bars stand off it.
-- On an angled end the bars stop at a straight edge, the separator stays
-- straight, and the stripe fills out to the frame's own angle. Its narrowest
-- point (the top of the cut) is the same width as the straight stripe.
-- Returns nil when the stripe is off.
function Happiness.Prepare(f, cfg)
    f.moodSide, f.moodPad = nil, nil
    local h = widget(f)
    if not h then return nil end
    ensureBand(h)
    local on = f.unitToken == "pet" and Happiness.Integrated(cfg)
    for _, tex in ipairs(barTextures(f)) do Style.ClipSpan(tex, "inner") end
    if not on then
        h.band:Hide()
        return nil
    end
    local side = cfg.happinessSide == "left" and "left" or "right"
    local slantOn = cfg.slant ~= false and f.spec.slant or nil
    local along = slantOn == side
    local T = Pixel.Px(f, Style.BorderPx(f))
    local w = Pixel.Px(f, Happiness.STRIPE)
    local gap = Pixel.Px(f, Style.SEPARATOR_PX)
    -- The cut is already on the frame (UF.Layout). The block has to cover it
    -- so the top of the angle still keeps a full stripe.
    local cut = along and (f.cut or 0) or 0
    local block = w + cut
    -- The gap is straight, inboard of the angle, so the frame's cut must not
    -- mask it. The stripe takes only the frame's own outer line.
    Style.ClipSpan(h.gap, "inner", false, "off")
    Style.ClipSpan(h.stripe, "inner", false, along and side or "off")
    h.stripe:ClearAllPoints()
    h.gap:ClearAllPoints()
    if side == "left" then
        h.stripe:SetPoint("TOPLEFT", f, "TOPLEFT", T, -T)
        h.stripe:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", T, T)
        h.stripe:SetWidth(block)
        h.gap:SetPoint("TOPLEFT", f, "TOPLEFT", T + block, -T)
        h.gap:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", T + block, T)
        h.gap:SetWidth(gap)
    else
        h.stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", -T, -T)
        h.stripe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T, T)
        h.stripe:SetWidth(block)
        h.gap:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(T + block), -T)
        h.gap:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(T + block), T)
        h.gap:SetWidth(gap)
    end
    -- The bars themselves move in by the whole block, so text on them is
    -- already clear of the stripe.
    return { side = side, along = along, w = w, gap = gap, cut = cut }
end

-- Returns the mood (1 to 3), the damage percent and the loyalty rate, or nil
-- when there's no hunter pet.
function Happiness.Read()
    if not (C_PetInfo and C_PetInfo.GetPetHappiness) then return nil end
    local _, isHunterPet = HasPetUI()
    if not isHunterPet then return nil end
    local ok, mood, damage, loyalty = pcall(C_PetInfo.GetPetHappiness)
    if not ok or not Happiness.COLORS[mood] then return nil end
    return mood, damage, loyalty
end

local function addTipLines(mood, damage, loyalty)
    local Tips, c = DUI.Tips, Happiness.COLORS[mood]
    Tips.Clear()
    Tips.Title(_G["PET_HAPPINESS" .. mood] or string.format(DUI.L["Happiness %s"], tostring(mood)), c[1], c[2], c[3])
    if type(damage) == "number" and PET_DAMAGE_PERCENTAGE then
        Tips.Sub(string.format(PET_DAMAGE_PERCENTAGE, damage))
    end
    if type(loyalty) == "number" and loyalty < 0 and LOSING_LOYALTY then
        Tips.Text(LOSING_LOYALTY, Tips.BAD)
    elseif type(loyalty) == "number" and loyalty > 0 and GAINING_LOYALTY then
        Tips.Text(GAINING_LOYALTY, Tips.GOOD)
    end
    local okDiet, diet = pcall(C_PetInfo.GetPetFoodTypes)
    if okDiet and type(diet) == "table" and PET_DIET_TEMPLATE then
        local list = #diet > 0 and table.concat(diet, PET_FOOD_DELIMIT or ", ") or (NONE or DUI.L["None"])
        Tips.Sub(string.format(PET_DIET_TEMPLATE, list))
    end
    Tips.Flush(GameTooltip)
end

local function showTooltip(self)
    local mood, damage, loyalty = Happiness.Read()
    if not mood then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    addTipLines(mood, damage, loyalty)
    GameTooltip:Show()
end

function Happiness.Create(pet)
    local h = CreateFrame("Frame", nil, pet)
    h.pet = pet
    ensureBand(h)
    h.shell = Style.Shell(h)
    h.fill = h:CreateTexture(nil, "ARTWORK")
    h.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    h.face = h:CreateTexture(nil, "ARTWORK", nil, 1)
    h:EnableMouse(true)
    h:SetScript("OnEnter", showTooltip)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- UNIT_PET fires for every owner the client knows about, party members
    -- included, so only yours counts. UNIT_HAPPINESS stays unfiltered because
    -- the game's source doesn't show which unit token it uses on this client.
    pcall(h.RegisterEvent, h, "UNIT_HAPPINESS")
    pcall(h.RegisterUnitEvent, h, "UNIT_PET", "player")
    h:SetScript("OnEvent", function(self) Happiness.Update(self) end)
    return h
end

-- Placed at its spot around (or on) the pet frame, happinessSize across.
function Happiness.Layout(h, cfg)
    if not h then return end
    h.enabled = cfg.happiness == true
    h.tint = cfg.happinessBar == true
    local look = cfg.happinessLook
    h.look = (look == "icon" or look == "frame") and look or "square"
    if h.look == "frame" then
        h:Hide()
        Happiness.Update(h)
        return
    end
    if h.band then h.band:Hide() end
    local pet = h.pet
    local s = math.max(8, tonumber(cfg.happinessSize) or 16)
    h:SetSize(s, s)
    ns.UF.PlaceSpot(h, pet, pet, cfg.happinessSpot or "outleft", 1, 1, tonumber(cfg.happinessX) or 0, tonumber(cfg.happinessY) or 0)
    local T = Pixel.Px(h, DUI.DB.General().borderPx)
    h.fill:ClearAllPoints()
    h.fill:SetPoint("TOPLEFT", h, "TOPLEFT", T, -T)
    h.fill:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    h.face:ClearAllPoints()
    -- The square is inset for its border. A face has no border, so it fills
    -- the whole size.
    if h.look == "square" then h.face:SetAllPoints(h.fill) else h.face:SetAllPoints(h) end
    Happiness.Update(h)
end

-- Test mode: a content pet, whatever the class.
function Happiness.ShowSample(h)
    if not h then return end
    h.test = true
    Happiness.Draw(h, h.enabled and 2 or nil)
    if h.tint then Happiness.Repaint(h) end
end

-- Repaint the pet frame's bar, from its sample in test mode or the real pet.
function Happiness.Repaint(h)
    local UF, pet = ns.UF, h.pet
    if not UF then return end
    if pet.test and UF.ShowSample then UF.ShowSample(pet)
    elseif UF.UpdateIdentity then UF.UpdateIdentity(pet) end
end

function Happiness.HideSample(h)
    if not h or not h.test then return end
    h.test = nil
    Happiness.Update(h)
end

-- One mood from the game's face. The atlas region is one face on a current
-- client. The classic sheet is three faces across its top, so a region that
-- wide is cropped to the one mood or the face shows up sliced.
local function moodFace(face, mood)
    local atlas = Happiness.ATLAS[mood]
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local file = type(info) == "table" and info.file
    local l, r = type(info) == "table" and info.leftTexCoord, type(info) == "table" and info.rightTexCoord
    local t, b = type(info) == "table" and info.topTexCoord, type(info) == "table" and info.bottomTexCoord
    local named = type(file) == "string" or type(file) == "number"
    if named and type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number" then
        local w, h = r - l, b - t
        local sheet = type(file) == "string" and file:find("PetHappiness", 1, true) and w > 0.5
        if sheet or (h > 0 and w > h * 1.4) then
            l, r, t, b = unpack(Happiness.SHEET_COORD[mood])
            file = Happiness.SHEET
        end
        face:SetTexture(file)
        face:SetTexCoord(l, r, t, b)
    else
        face:SetTexCoord(0, 1, 0, 1)
        face:SetAtlas(atlas)
    end
end

-- On the pet frame's own tooltip while the stripe is showing.
function Happiness.AddTip(f)
    local h = widget(f)
    if not h or h.look ~= "frame" or not h.enabled or not h.band or not h.band:IsShown() then return end
    local mood, damage, loyalty = h.test and 2, nil, nil
    if not h.test then mood, damage, loyalty = Happiness.Read() end
    if not mood then return end
    addTipLines(mood, damage, loyalty)
end

function Happiness.Draw(h, mood)
    if h.look == "frame" then
        h:Hide()
        local on = mood ~= nil and h.stripe ~= nil
        if h.band then h.band:SetShown(on) end
        if on then
            local r, g, b = Style.Soften(unpack(Happiness.COLORS[mood]))
            h.stripe:SetVertexColor(r, g, b)
        end
        return
    end
    if h.band then h.band:Hide() end
    h:SetShown(mood ~= nil)
    if not mood then return end
    local r, g, b = Style.Soften(unpack(Happiness.COLORS[mood]))
    local square = h.look == "square"
    h.fill:SetVertexColor(r, g, b)
    h.fill:SetShown(square)
    h.face:SetShown(not square)
    -- The square keeps the frame's edge. A face has none: no border, no fill
    -- behind it.
    if h.shell then
        Style.SetShellColors(h.shell, nil)
        h.shell:SetShown(square)
    end
    if square then return end
    moodFace(h.face, mood)
end

-- The pet's health bar color while "color the bar" is on and there's a mood
-- to show (a content pet in test mode). Nil otherwise.
function Happiness.BarColor(h, f)
    if not h or f ~= h.pet or f.state or not h.tint then return nil end
    local mood = h.test and 2 or Happiness.Read()
    local c = mood and Happiness.COLORS[mood]
    if not c then return nil end
    return Style.Soften(c[1], c[2], c[3])
end

function Happiness.Update(h)
    if not h then return end
    if not h.test then
        Happiness.Draw(h, h.enabled and Happiness.Read() or nil)
    end
    -- Repaint the bar when it's tinted, and once more when the tint goes off.
    if h.tint or h.tinted then Happiness.Repaint(h) end
    h.tinted = h.tint
end
