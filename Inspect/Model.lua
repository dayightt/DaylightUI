-- The inspected player's model in the middle of the gear page: a PlayerModel set to the
-- unit, like the game's InspectModelFrame (Camelot InspectPaperDollFrame.xml:
-- PlayerModel + SetUnit). The character model's scene setup (SetUpCharacterSheetScene)
-- only works for the player. Behind it, the character window's soft glow in their class
-- color and a shadow at the feet. Drag to turn, easing out after release.

local _, DUI = ...
DUI.Inspect = DUI.Inspect or {}
local ns = DUI.Inspect

local Model = {}
ns.Model = Model

Model.TURN = 0.012      -- radians per pixel dragged
Model.SETTLE = 0.88     -- fraction of turn speed kept each frame after release
Model.STOP = 0.0005
Model.GLOW = DUI.MEDIA .. "char-glow.png"
Model.GLOW_ALPHA = 0.3
Model.GLOW_W, Model.GLOW_H = 1.0, 0.95
Model.GLOW_UP = 0.04
Model.SHADOW_ALPHA = 0.6
Model.SHADOW_W, Model.SHADOW_H = 0.5, 26
Model.FEET = 0.12

local function place()
    local h = Model.holder
    if not h then return end
    local w, ht = h:GetWidth() or 0, h:GetHeight() or 0
    h.glow:ClearAllPoints()
    h.glow:SetPoint("CENTER", h, "CENTER", 0, ht * Model.GLOW_UP)
    h.glow:SetSize(w * Model.GLOW_W, ht * Model.GLOW_H)
    h.shadow:ClearAllPoints()
    h.shadow:SetPoint("CENTER", h, "BOTTOM", 0, ht * Model.FEET)
    h.shadow:SetSize(w * Model.SHADOW_W, Model.SHADOW_H)
end

local function turn(m, elapsed)
    if m.dragX then
        local x = GetCursorPosition()
        local d = (x - m.dragX) * Model.TURN
        m.dragX = x
        m.speed = d / math.max(elapsed or 0, 0.001)
        m.facing = (m.facing or 0) + d
    elseif m.speed and math.abs(m.speed) > Model.STOP then
        m.speed = m.speed * Model.SETTLE
        m.facing = (m.facing or 0) + m.speed * (elapsed or 0)
    else
        m.speed = 0
        return
    end
    m:SetFacing(m.facing)
end

function Model.Build(parent)
    local h = CreateFrame("Frame", nil, parent)
    Model.holder = h
    h.glow = h:CreateTexture(nil, "BACKGROUND")
    h.glow:SetTexture(Model.GLOW)
    h.glow:SetAlpha(Model.GLOW_ALPHA)
    h.shadow = h:CreateTexture(nil, "BORDER")
    h.shadow:SetTexture(Model.GLOW)
    h.shadow:SetVertexColor(0, 0, 0, Model.SHADOW_ALPHA)
    h:SetScript("OnSizeChanged", place)
    local ok, m = pcall(CreateFrame, "PlayerModel", nil, h)
    if ok and type(m) == "table" then
        m:SetAllPoints(h)
        m:EnableMouse(true)
        m:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then self.dragX = GetCursorPosition() end
        end)
        m:SetScript("OnMouseUp", function(self) self.dragX = nil end)
        m:SetScript("OnHide", function(self) self.dragX, self.speed = nil, 0 end)
        m:SetScript("OnUpdate", turn)
        Model.model = m
    end
    place()
    return h
end

-- Glow in their class color (the player's own accent wouldn't help here).
function Model.Paint(unit)
    local h = Model.holder
    if not h then return end
    local _, token = UnitClass(unit)
    if type(token) == "string" and not (issecretvalue and issecretvalue(token)) then
        local r, g, b = DUI.Style.ClassColor(token)
        h.glow:SetVertexColor(r, g, b, 1)
    else
        h.glow:SetVertexColor(DUI.Style.Accent())
    end
end

-- New player: the client dresses the model, then it fades in.
function Model.SetUnit(unit)
    Model.Paint(unit)
    local m = Model.model
    if not (m and unit) then return end
    m.facing, m.speed, m.dragX = 0, 0, nil
    m:SetAlpha(0)
    pcall(m.SetUnit, m, unit)
    pcall(m.SetFacing, m, 0)
    DUI.Motion.Fade(m, 0, 1, DUI.Motion.NORMAL)
end

-- Same player, gear changed (late links, a swap): the client re-dresses it in place,
-- no fade since the model is already up.
function Model.Dress(unit)
    local m = Model.model
    if not (m and unit) then return end
    pcall(m.SetUnit, m, unit)
    pcall(m.SetFacing, m, m.facing or 0)
end

function Model.Clear()
    local m = Model.model
    if m and type(m.ClearModel) == "function" then pcall(m.ClearModel, m) end
end
