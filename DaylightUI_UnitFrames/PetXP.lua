-- A hunter pet's experience bar (pet.xpBar, off by default), in one of two places
-- (pet.xpBarMode):
--   "frame": a strip inside the pet frame under its power bar, as thin as the power bar
--            (pet.xpBarHeight). The frame's layout makes room for it (UF.Layout), and the
--            numbers are in the frame's tooltip.
--   "free":  a bar of its own, movable like the other bars, with its length
--            (pet.xpBarWidth), thickness (pet.xpBarFreeHeight) and direction
--            (pet.xpBarOrientation), and the numbers on it.
-- Only a hunter's pet has XP, and only while it can still level. The free bar is gone with
-- no pet, a demon or a pet at the top level, except as a sample while it is unlocked to be
-- placed. The strip keeps its room (empty) so the frame doesn't change size at the top level.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local PetXP = {}
ns.PetXP = PetXP

PetXP.KEY = "unitframes.petxp"
PetXP.HOME = { "CENTER", nil, "CENTER", 0, -220 }
PetXP.SAMPLE = { value = 3200, max = 9100 }
PetXP.TURN = math.pi / 2

local isSecret = DUI.IsSecret
local function plain(v) return type(v) == "number" and not isSecret(v) end

-- The pet's XP and what it needs, or nil: no pet, not a hunter's, or nothing left to level.
function PetXP.Read()
    if type(HasPetUI) ~= "function" or type(GetPetExperience) ~= "function" then return nil end
    local has, hunter = HasPetUI()
    if not (has and hunter) then return nil end
    local cur, need = GetPetExperience()
    if plain(cur) and plain(need) and need > 0 then return cur, need end
end

local function percent(cur, need) return string.format("%s / %s  (%d%%)", BreakUpLargeNumbers(cur),
    BreakUpLargeNumbers(need), math.floor(cur / need * 100)) end

-- ---------------------------------------------------------------------
-- The strip inside the pet frame
-- ---------------------------------------------------------------------

-- Made with the pet frame (UF.Build): a bar like its power bar, and the line over it.
function PetXP.Build(f)
    f.xp = Style.Bar(f, nil, ns.UF.MEDIA.petxp.bar)
    f.xpSep = Style.Separator(f)
    f.xp:Hide()
    f.xpSep:Hide()
end

-- Whether this pet frame keeps a strip for the experience: the pet's settings, a hunter (their
-- pets are the ones that level; a sample stands in for one), and no backdrop art, which has its
-- own layout.
function PetXP.Wants(f, cfg)
    return f.xp ~= nil and cfg.xpBar == true and cfg.xpBarMode ~= "free" and not f.backdropOn
        and (f.test == true or ns.Happiness.HunterPet())
end

-- The strip's height in the frame's pixels, or 0 for none. Never so tall that it takes the room
-- the power bar and UF.MIN_HEALTH of health need; room is what is left for the strip.
function PetXP.Reserve(f, cfg, room)
    if not PetXP.Wants(f, cfg) then return 0 end
    local h = Pixel.Snap(f, tonumber(cfg.xpBarHeight) or 4)
    return math.max(Pixel.Px(f, 1), math.min(h, Pixel.Snap(f, math.max(0, room or h))))
end

-- The bar's colors as a list of { r, g, b } stops, dark to light: its own gradient, the accent's,
-- the class's, or blue (xp.color). One stop is a flat color.
local BLUE = { 0.2, 0.5, 0.95 }
function PetXP.Stops(xp)
    local G = DUI.Gradients
    local mode = type(xp) == "table" and xp.color or "accent"
    if mode == "custom" then
        local own = G.Stops(xp.customGradient)
        if own then return own end
    elseif mode == "class" then
        local key = G.KeyFor("player")
        if key and G.Has(key) then
            local lo, hi = G.PaintRGB(key)
            return { { Style.Soften(lo[1], lo[2], lo[3]) }, { Style.Soften(hi[1], hi[2], hi[3]) } }
        end
    elseif mode == "blue" then
        local lo, hi = G.PairFrom(BLUE)
        return { { Style.Soften(lo[1], lo[2], lo[3]) }, { Style.Soften(hi[1], hi[2], hi[3]) } }
    end
    -- The accent: every color of a custom one, its two ends, or the one color.
    local many = Style.AccentStops()
    if many then return many end
    local lo, hi = Style.AccentPair()
    if lo then return { lo, hi } end
    return { { Style.Accent() } }
end

-- Colors a bar of the experience: shaded along its stops with the gradient on, else flat at the light end.
function PetXP.Paint(bar, xp, vertical)
    local stops = PetXP.Stops(xp)
    if type(xp) == "table" and xp.gradient ~= false and #stops > 1 and not DUI.Gradients.Flat() then
        Style.PaintBarStops(bar, stops, nil, vertical and "VERTICAL" or "HORIZONTAL")
    else
        local c = stops[#stops]
        Style.SetBarColor(bar, c[1], c[2], c[3])
    end
end

-- Fills the strip. f.xpH is its height from the last layout.
function PetXP.PaintInside(f, cfg)
    if not f or not f.xp then return end
    if cfg then f.xpCfg = cfg end
    local on = (f.xpH or 0) > 0
    f.xp:SetShown(on)
    f.xpSep:SetShown(on)
    if not on then return end
    local cur, need = PetXP.Read()
    if f.test and not cur then cur, need = PetXP.SAMPLE.value, PetXP.SAMPLE.max end
    f.xp:SetMinMaxValues(0, need or 1)
    Style.SetBarValue(f.xp, cur or 0)
    PetXP.Paint(f.xp, f.xpCfg and f.xpCfg.xp, false)
end

-- On the pet frame's tooltip, under the unit's: the experience, while the strip is showing.
-- A part of its own: its title opens it after a rule, as the happiness one does, and the numbers
-- are a line of the same size as the rest. after: the happiness part was added before it.
function PetXP.AddTip(f, after)
    if f.unitToken ~= "pet" or (f.xpH or 0) <= 0 then return end
    local cur, need = PetXP.Read()
    if not cur then return end
    local Tips = DUI.Tips
    Tips.Clear()
    if after then Tips.Gap() end
    Tips.Title(DUI.L["Experience"], Style.Accent())
    Tips.Sub(percent(cur, need))
    Tips.Flush(GameTooltip)
end

-- ---------------------------------------------------------------------
-- The bar on its own
-- ---------------------------------------------------------------------

function PetXP.Create(pet)
    local f = CreateFrame("Frame", "DaylightUIPetExperienceBar", UIParent)
    f:SetFrameStrata("LOW")
    Style.Shell(f)
    f:Hide()
    f.pet = pet
    f.bar = Style.Bar(f)
    f.text = Style.Text(f.bar, 9, "CENTER", ns.UF.MEDIA.petxp.font)
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local cur, need = PetXP.Read()
        if not cur then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local Tips = DUI.Tips
        Tips.Clear()
        -- Whose experience it is: the pet's name over the line.
        local name = UnitName("pet")
        Tips.Title(type(name) == "string" and not isSecret(name) and name or DUI.L["Experience"])
        Tips.Line(DUI.L["Experience"], percent(cur, need))
        Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    DUI.Movers.Register(f, PetXP.KEY, "Pet Experience Bar", PetXP.HOME)
    DUI.Movers.Suspend(PetXP.KEY, true)
    local function refresh() PetXP.Update(f) end
    DUI.On("UnlockChanged", refresh)
    DUI.RegisterEvent("UNIT_PET_EXPERIENCE", refresh)
    DUI.RegisterEvent("UNIT_PET", refresh)
    DUI.RegisterEvent("UNIT_LEVEL", refresh)
    return f
end

-- The pet's settings, once the frame has been laid out (it knows then if it kept a strip).
function PetXP.Layout(f, cfg)
    if not f then return end
    f.cfg = cfg
    local free = cfg.xpBarMode == "free"
    local vertical = free and cfg.xpBarOrientation == "vertical"
    f.free, f.vertical = free, vertical
    local h = math.max(2, tonumber(cfg.xpBarFreeHeight) or 12)
    local w = math.max(20, tonumber(cfg.xpBarWidth) or 160)
    f:SetSize(vertical and h or w, vertical and w or h)
    DUI.Movers.Suspend(PetXP.KEY, not (free and cfg.xpBar == true))
    -- Its own border, corners and shadow (pet.xp.shell), else General's.
    ns.UF.WriteShell(Style.GetShell(f), ns.UF.OwnShell(cfg.xp))
    local T = Pixel.Px(f, Style.BorderPx(f))
    Style.LayoutShell(Style.GetShell(f))
    f.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    f.bar:SetRotatesTexture(vertical == true)
    f.text:SetRotation(vertical and PetXP.TURN or 0)
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", T, -T)
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T, T)
    Style.SetTextSize(f.text, tonumber(cfg.xp and cfg.xp.textSize) or 10)
    if free then DUI.Movers.ApplyAll() end
    PetXP.Update(f)
end

function PetXP.Update(f)
    PetXP.PaintInside(f.pet, f.cfg)
    local cfg = f.cfg
    if not cfg then return end
    local cur, need
    if cfg.xpBar == true and f.free then
        cur, need = PetXP.Read()
        -- Still there while unlocked, so it can be put in place.
        if not cur and DUI.Movers.unlocked then cur, need = PetXP.SAMPLE.value, PetXP.SAMPLE.max end
    end
    f:SetShown(cur ~= nil)
    if not cur then return end
    f.bar:SetMinMaxValues(0, need)
    Style.SetBarValue(f.bar, cur)
    PetXP.Paint(f.bar, cfg.xp, f.vertical)
    local text = string.format("%s / %s", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(need))
    if cfg.xp and cfg.xp.showPercent == true then text = text .. string.format("   %d%%", math.floor(cur / need * 100)) end
    f.text:SetText(text)
    f.text:Show()
end
