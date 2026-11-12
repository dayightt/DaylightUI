-- A hunter pet's happiness beside the pet frame. Either a square filled with
-- the mood's color (happinessLook "square", the default, readable at any size)
-- or the game's mood face from PetHappiness.lua edged in that color. Red is
-- unhappy, yellow content, green happy (a happy pet does more damage and gains
-- loyalty). Placed like the corner icons via happinessSpot/X/Y, sized by
-- happinessSize. The tooltip mirrors the game's own indicator: mood, damage,
-- loyalty gain or loss, and diet. Hunter pets only.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Happiness = {}
ns.Happiness = Happiness

Happiness.ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }
Happiness.COLORS = {
    [1] = { 0.9, 0.25, 0.22 },     -- unhappy
    [2] = { 1.0, 0.82, 0.25 },     -- content
    [3] = { 0.35, 0.8, 0.35 },     -- happy
}

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

local function showTooltip(self)
    local mood, damage, loyalty = Happiness.Read()
    if not mood then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
    GameTooltip:Show()
end

function Happiness.Create(pet)
    local h = CreateFrame("Frame", nil, pet)
    h.pet = pet
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
    h.look = cfg.happinessLook == "icon" and "icon" or "square"
    local pet = h.pet
    local s = math.max(8, tonumber(cfg.happinessSize) or 16)
    h:SetSize(s, s)
    ns.UF.PlaceSpot(h, pet, pet, cfg.happinessSpot or "outleft", 1, 1, tonumber(cfg.happinessX) or 0, tonumber(cfg.happinessY) or 0)
    local T = Pixel.Px(h, DUI.DB.General().borderPx)
    h.fill:ClearAllPoints()
    h.fill:SetPoint("TOPLEFT", h, "TOPLEFT", T, -T)
    h.fill:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    h.face:ClearAllPoints()
    h.face:SetAllPoints(h.fill)
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

function Happiness.Draw(h, mood)
    h:SetShown(mood ~= nil)
    if not mood then return end
    local r, g, b = Style.Soften(unpack(Happiness.COLORS[mood]))
    local face = h.look ~= "square"
    h.fill:SetVertexColor(r, g, b)
    h.fill:SetShown(not face)
    h.face:SetShown(face)
    -- The face gets an edge in the mood's color. The square keeps the frame's.
    if h.shell then Style.SetShellColors(h.shell, face and { r, g, b } or nil) end
    if face then h.face:SetAtlas(Happiness.ATLAS[mood]) end
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
