-- Party pets. A small bar beside each party member with a pet out, in the pet
-- frame's look (angled end, thin power bar, name on the bar), painted in the
-- owner's class colors by default so it reads as theirs. Off by default
-- (partyPet.enabled).
--
-- Each pet is a secure unit button attached to its owner's party button, the
-- same way the game's templates do it: "useparent-unit" plus "unitsuffix" =
-- "pet". The header's sorting carries it along and a click targets the right
-- pet in combat (SecureButton_GetUnit maps party1pet to partypet1). The game's
-- unit watch shows it while the pet exists. Attributes and the unit watch are
-- protected, so it's only created out of combat, and a member who joins
-- mid-fight gets theirs afterwards. Your own button (hideSelf off) never shows
-- one: the watch would read "playerpet", which isn't a unit, and your pet has
-- its own frame anyway.

local _, ns = ...
local DUI = DaylightUI
local UF, Pixel = ns.UF, DUI.Pixel

local PP = {}
ns.PartyPets = PP

PP.SPEC = { unit = "partypet1", compact = true, power = true, slant = "right" }
PP.GAP = 4   -- gap between the owner and its pet
PP.SPOTS = { right = "Right of its owner", left = "Left of its owner", below = "Under its owner", above = "Over its owner" }
PP.SPOT_ORDER = { "right", "left", "below", "above" }
PP.COLORS = { owner = "Its owner's class", own = "Like your pet frame" }
PP.COLOR_ORDER = { "owner", "own" }

PP.pets = {}   -- every real pet button created

local function config()
    local d = ns.module and ns.module.db
    if not d then return nil end
    return d.partyPet, d.partyPetText
end

-- The pet's unit for an owner's: party3 -> partypet3, raid7 -> raidpet7, you -> pet.
function PP.UnitFor(owner)
    if type(owner) ~= "string" then return nil end
    if owner == "player" then return "pet" end
    local kind, n = owner:match("^(%a+)(%d+)$")
    if kind == "party" or kind == "raid" then return kind .. "pet" .. n end
    return nil
end

-- Where the pet sits per the settings: spot (PP.SPOTS), width, height, or nil
-- while pets are off. AuraGroups.Box reads it so an aura row on that side
-- starts past the pet, whether or not a pet is out, so rows don't jump.
function PP.Room()
    local cfg = config()
    if not (cfg and cfg.enabled == true) then return nil end
    return PP.SPOTS[cfg.spot] and cfg.spot or "right", cfg.width, cfg.height
end

-- Points the pet beside its owner b. Protected for a real pet, out of combat only.
local function place(p, b, cfg)
    local gap, x, y = PP.GAP, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    local spot = cfg.spot
    p:ClearAllPoints()
    if spot == "left" then
        -- Stay clear of the portrait ring hanging off the outer end.
        p:SetPoint("RIGHT", b, "LEFT", -gap - (b.ringReach or 0) + x, y)
    elseif spot == "below" then
        p:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -(b.cut or 0) + x, -gap - (b.foot or 0) + y)
    elseif spot == "above" then
        local tab = b.tab and b.tab:IsShown() and (b.tabHeight or 0) or 0
        p:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", -(b.cut or 0) + x, gap + tab + y)
    else
        p:SetPoint("LEFT", b, "RIGHT", gap + x, y)
    end
end

local function layout(p, b, cfg, text)
    p:SetSize(2 * Pixel.Snap(p, cfg.width / 2), 2 * Pixel.Snap(p, cfg.height / 2))
    place(p, b, cfg)
    UF.Layout(p, cfg, text, true)
end

-- The owner's class colors for the pet's bar and name (UF.UpdateIdentity,
-- Colors.lua's gradient key), or nil for the normal friendly colors.
local function ownerClass(p, cfg)
    if not (cfg and cfg.color == "owner") then return nil end
    local owner = p.owner and p.owner.unitToken
    if type(owner) ~= "string" then return nil end
    return UF.ClassOf(owner)
end

-- Redraws a real pet from its unit (new unit, new pet, or a setting).
function PP.Refresh(p)
    p.ownerClass = ownerClass(p, config())
    if type(p.unitToken) == "string" and UnitExists(p.unitToken) then UF.UpdateAll(p, true) end
end

-- The owner's unit changed (the header re-sorted, someone joined), so the pet
-- follows. Allowed in combat since it only touches our fields and unit events.
function PP.Retarget(b, unit)
    local p = b.pet
    if not p or p.preview then return end
    local u = PP.UnitFor(unit)
    -- Update first: a pet made before the header set its owner's unit already
    -- holds the fallback "partypet1". Repeats are skipped there.
    if u == p.unitToken then return DUI.APIReport.Unit("partypet", p, u, false) end
    p.unitToken = u
    UF.RegisterUnitEvents(p)
    PP.Refresh(p)
    DUI.APIReport.Unit("partypet", p, u, false)
end

-- A real party button's pet. Protected, so it waits for combat to end.
function PP.Make(b)
    if b.pet or b.preview then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() PP.Layout(b) end, "partypet:" .. (b:GetName() or tostring(b)))
        return
    end
    local p = CreateFrame("Button", b:GetName() and b:GetName() .. "Pet" or nil, b, UF.BUTTON_TEMPLATE)
    p:SetAttribute("useparent-unit", true)
    p:SetAttribute("unitsuffix", "pet")
    p:SetAttribute("*type1", "target")
    p:SetAttribute("*type2", "togglemenu")
    p:RegisterForClicks("AnyUp")
    p.unitToken = PP.UnitFor(b.unitToken) or PP.SPEC.unit
    p.owner = b
    UF.Build(p, PP.SPEC)
    p:SetFrameLevel(b:GetFrameLevel() + 2)
    p:Hide()
    b.pet = p
    PP.pets[#PP.pets + 1] = p
    if type(ClickCastFrames) == "table" then ClickCastFrames[p] = true end
    ns.ClickCast.Dress(p)
    UF.Wire(p)
    DUI.APIReport.Made("partypet", p, PP.UnitFor(b.unitToken), false)
    -- The owner's unit attribute names the pet's unit too. Read the value
    -- directly, since the group's own hook may not have stored it yet.
    b:HookScript("OnAttributeChanged", function(btn, name, value)
        if name == "unit" then PP.Retarget(btn, value) end
    end)
end

-- A real party button's pet from the settings. Created the first time pets
-- are on, then sized, placed and watched. Off means no watch and hidden.
-- Called from every party button's layout (Group:LayoutButton).
function PP.Layout(b)
    local cfg, text = config()
    if not cfg or b.preview then return end
    if not b.pet then
        if cfg.enabled ~= true then return end
        PP.Make(b)
        if not b.pet then return end
    end
    if InCombatLockdown() then
        DUI.AfterCombat(function() PP.Layout(b) end, "partypet:" .. (b:GetName() or tostring(b)))
        return
    end
    local p = b.pet
    layout(p, b, cfg, text)
    if cfg.enabled == true then
        if not p.watched then
            RegisterUnitWatch(p)
            p.watched = true
        end
    elseif p.watched then
        UnregisterUnitWatch(p)
        p.watched = false
        p:Hide()
    end
    PP.Refresh(p)
    local Report = DUI.APIReport
    if Report.Wants("FrameStyled") then Report.Styled("partypet", p, false) end
end

-- A pet was summoned, dismissed or swapped. The event comes for its owner.
local watch = CreateFrame("Frame")
watch:RegisterEvent("UNIT_PET")
watch:SetScript("OnEvent", function(_, _, unit)
    for _, p in ipairs(PP.pets) do
        if p.owner and p.owner.unitToken == unit then PP.Refresh(p) end
    end
end)

-- Samples (test mode, the Party page preview): a plain pet on each sample
-- button, shown for members whose class keeps one out.

PP.SAMPLES = {
    WARLOCK = { name = "Grimlix", health = 64, healthValue = 420, power = 80, powerToken = "MANA" },
    HUNTER = { name = "Sable", health = 88, healthValue = 1100, power = 55, powerToken = "FOCUS" },
}

function PP.DressSample(b)
    local p = CreateFrame("Button", nil, b)
    p.unitToken, p.preview, p.owner = PP.SPEC.unit, true, b
    UF.Build(p, PP.SPEC)
    p:SetFrameLevel(b:GetFrameLevel() + 2)
    p:EnableMouse(false)
    p:Hide()
    b.pet = p
end

-- The sample pet for a sample owner. The Party page's member always has one.
-- In test mode only classes that keep a pet out get one, and never you.
function PP.SampleFor(b, cfg)
    local s = b.test
    if type(s) ~= "table" or s.you then return nil end
    local pet = PP.SAMPLES[s.class] or (b.fullSample and PP.SAMPLES.HUNTER)
    if not pet then return nil end
    local out = {}
    for k, v in pairs(pet) do out[k] = v end
    if cfg.color == "owner" and s.class then out.class = s.class else out.reaction = 5 end
    return out
end

function PP.ShowSample(b)
    local p = b.pet
    if not p then return end
    local cfg, text = config()
    local s = cfg and cfg.enabled == true and PP.SampleFor(b, cfg)
    if not s then
        PP.HideSample(b)
        return
    end
    layout(p, b, cfg, text)
    p.test = s
    p:Show()
    UF.ShowSample(p)
end

function PP.HideSample(b)
    local p = b.pet
    if not p then return end
    p.test = nil
    p:Hide()
end

-- Design mode's dots for a sample's pet (owner px, top left, y down): where
-- its middle sits at each spot with no nudge, matching `place`.
function PP.Dots(b)
    local p, gap = b.pet, PP.GAP
    local w, h, pw, ph = b:GetWidth(), b:GetHeight(), p:GetWidth(), p:GetHeight()
    local tab = b.tab and b.tab:IsShown() and (b.tabHeight or 0) or 0
    local x = w - (b.cut or 0) - pw / 2
    return { { spot = "right", x = w + gap + pw / 2, y = h / 2 },
             { spot = "left", x = -gap - (b.ringReach or 0) - pw / 2, y = h / 2 },
             { spot = "below", x = x, y = h + gap + (b.foot or 0) + ph / 2 },
             { spot = "above", x = x, y = -(gap + tab + ph / 2) } }
end

-- How far a sample's pet reaches past its owner: up, down, left, right.
-- The Party page's preview makes room for it.
function PP.Reach(b)
    local p = b.pet
    if not (p and p:IsShown()) then return 0, 0, 0, 0 end
    local cfg = config()
    local w, h = p:GetWidth(), p:GetHeight()
    local x, y, gap = tonumber(cfg.x) or 0, tonumber(cfg.y) or 0, PP.GAP
    local bh = b:GetHeight()
    local spot = cfg.spot
    if spot == "left" then return 0, 0, w + gap + (b.ringReach or 0) - x, 0 end
    if spot == "below" then return 0, h + gap + (b.foot or 0) - y, 0, 0 end
    if spot == "above" then return h + gap + y, 0, 0, 0 end
    local over = math.max(0, (h - bh) / 2)
    return over + y, over - y, 0, w + gap + x
end
