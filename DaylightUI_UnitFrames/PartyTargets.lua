-- Party targets. A small frame beside each party member showing who they're
-- targeting, set up like the target of target (its own page, "partyTarget").
-- Off by default (partyTarget.enabled).
--
-- Each one is a secure unit button attached to its member's party button, the
-- way party pets are: "useparent-unit" plus "unitsuffix" = "target", so the
-- header's sorting carries it along and a click targets the right unit in
-- combat. The game's unit watch shows it while the member has a target.
-- Attributes and the unit watch are protected, so it's only created out of
-- combat, and a member who joins mid-fight gets theirs afterwards. A target's
-- target sends no unit events, so it's polled like the target of target.

local _, ns = ...
local DUI = DaylightUI
local UF, Pixel = ns.UF, DUI.Pixel

local PT = {}
ns.PartyTargets = PT

PT.SPEC = { unit = "party1target", compact = true, power = true, slant = "right", range = true, names = "partyTarget" }
PT.KEY = "partyTarget"
PT.FADE = "UnitFrames.partyTarget"
PT.GAP = 4      -- gap between the member (or their pet) and the target
PT.POLL = 0.1
PT.SPOTS = { right = "Right of the member", left = "Left of the member", below = "Under the member", above = "Over the member" }
PT.SPOT_ORDER = { "right", "left", "below", "above" }

PT.buttons = {}   -- every real target button created

local function db() return ns.module and ns.module.db end

local function config()
    local d = db()
    if not d then return nil end
    return d.partyTarget, d.partyTargetText, d
end

-- The target's unit for a member's: party3 -> party3target, you -> target.
function PT.UnitFor(owner)
    if type(owner) ~= "string" then return nil end
    if owner == "player" then return "target" end
    if owner:match("^party%d$") or owner:match("^raid%d+$") then return owner .. "target" end
    return nil
end

-- The party pet's room on the same side, so the target sits past it.
local function petRoom(spot)
    local pspot, pw, ph = ns.PartyPets.Room()
    if pspot ~= spot then return 0 end
    if spot == "right" or spot == "left" then return pw + ns.PartyPets.GAP end
    return ph + ns.PartyPets.GAP
end

-- Where the target sits per the settings: spot, width, height, or nil while
-- off. AuraGroups.Box reads it so an aura row on that side starts past it.
function PT.Room()
    local cfg = config()
    if not (cfg and cfg.enabled == true) then return nil end
    return PT.SPOTS[cfg.spot] and cfg.spot or "right", cfg.width, cfg.height
end

-- Points the target beside its member b. Protected for a real one, out of combat only.
local function place(p, b, cfg)
    local spot = PT.SPOTS[cfg.spot] and cfg.spot or "right"
    local gap, x, y = PT.GAP + petRoom(spot), tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
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

local function layout(p, b, cfg, text, d)
    p.iconStyle, p.classIcons = d.portraits.icons, d.portraits.classIcons
    p.rangeFade, p.rangeAlpha = d.range.enabled, UF.RangeAlpha(d.range, false)
    p.rangePick = UF.RangePick(d.range)
    p:SetSize(2 * Pixel.Snap(p, cfg.width / 2), 2 * Pixel.Snap(p, cfg.height / 2))
    place(p, b, cfg)
    UF.Layout(p, cfg, text, true)
end

-- Redraws a real target from its unit (a new unit, a new target, or a setting).
function PT.Refresh(p)
    if p.test then return end
    if type(p.unitToken) == "string" and UnitExists(p.unitToken) then UF.UpdateAll(p, true) end
end

-- The member's unit changed (the header re-sorted, someone joined), so the
-- target follows. Allowed in combat since it only touches our fields.
function PT.Retarget(b, unit)
    local p = b.ptarget
    if not p or p.preview then return end
    local u = PT.UnitFor(unit)
    if u == p.unitToken then return end
    p.unitToken = u
    UF.RegisterUnitEvents(p)
    PT.Refresh(p)
end

-- A real party button's target. Protected, so it waits for combat to end.
function PT.Make(b)
    if b.ptarget or b.preview then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() PT.Layout(b) end, "partytarget:" .. (b:GetName() or tostring(b)))
        return
    end
    local p = CreateFrame("Button", b:GetName() and b:GetName() .. "Target" or nil, b, UF.BUTTON_TEMPLATE)
    p:SetAttribute("useparent-unit", true)
    p:SetAttribute("unitsuffix", "target")
    p:SetAttribute("*type1", "target")
    p:SetAttribute("*type2", "togglemenu")
    p:RegisterForClicks("AnyUp")
    p.unitToken = PT.UnitFor(b.unitToken) or PT.SPEC.unit
    p.owner = b
    UF.Build(p, PT.SPEC)
    p:SetFrameLevel(b:GetFrameLevel() + 2)
    p:Hide()
    b.ptarget = p
    PT.buttons[#PT.buttons + 1] = p
    if type(ClickCastFrames) == "table" then ClickCastFrames[p] = true end
    ns.ClickCast.Dress(p)
    UF.Wire(p)
    UF.EnablePolling(p, PT.POLL)
    -- The member's unit attribute names the target's unit too.
    b:HookScript("OnAttributeChanged", function(btn, name, value)
        if name == "unit" then PT.Retarget(btn, value) end
    end)
end

-- A real party button's target from the settings. Created the first time
-- they're on, then sized, placed and watched. Off means no watch and hidden.
-- Called from every party button's layout (Group:LayoutButton).
function PT.Layout(b)
    local cfg, text, d = config()
    if not cfg or b.preview then return end
    if not b.ptarget then
        if cfg.enabled ~= true then return end
        PT.Make(b)
        if not b.ptarget then return end
    end
    if InCombatLockdown() then
        DUI.AfterCombat(function() PT.Layout(b) end, "partytarget:" .. (b:GetName() or tostring(b)))
        return
    end
    local p = b.ptarget
    layout(p, b, cfg, text, d)
    p:SetFrameStrata(ns.StrataOf(cfg))
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
    PT.Refresh(p)
end

-- Every target's fade (its own page's Fade card), range fade included.
function PT.RegisterFade()
    DUI.Fade.Register{ key = PT.FADE, scope = "UnitFrames", path = "partyTarget.fade",
        page = "UnitFrames.partyTarget", frames = function() return PT.buttons end, paint = UF.PaintFade, whole = true,
        float = false }
end

-- A member picked a new target (you: PLAYER_TARGET_CHANGED).
local watch = CreateFrame("Frame")
watch:RegisterEvent("UNIT_TARGET")
watch:RegisterEvent("PLAYER_TARGET_CHANGED")
watch:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then unit = "player" end
    for _, p in ipairs(PT.buttons) do
        if p.owner and p.owner.unitToken == unit then PT.Refresh(p) end
    end
end)

-- Samples (test mode, the Party page preview, this page's own): a plain
-- frame on each sample member, for the members who have a target.

PT.SAMPLES = {
    { name = "Sadeas", reaction = 2, health = 72, healthValue = 1450, power = 60, powerValue = 900, powerToken = "MANA" },
    { name = "Sadeas", reaction = 2, health = 72, healthValue = 1450, power = 60, powerValue = 900, powerToken = "MANA" },
    { name = "Vivenna", reaction = 2, health = 35, healthValue = 380, power = 40, powerValue = 600, powerToken = "MANA" },
}

-- The sample for this page's own preview.
function PT.PageSample() return PT.SAMPLES[1] end

function PT.DressSample(b)
    local p = CreateFrame("Button", nil, b)
    p.unitToken, p.preview, p.owner = PT.SPEC.unit, true, b
    UF.Build(p, PT.SPEC)
    p:SetFrameLevel(b:GetFrameLevel() + 2)
    p:EnableMouse(false)
    p:Hide()
    b.ptarget = p
end

-- The sample target for a sample member: the page's member always has one,
-- test mode's first three (the tank and healer on one enemy, a damage dealer on another).
function PT.SampleFor(b, i)
    if type(b.test) ~= "table" then return nil end
    if b.fullSample then return PT.SAMPLES[1] end
    return i and PT.SAMPLES[i] or nil
end

function PT.ShowSample(b, i)
    local p = b.ptarget
    if not p then return end
    local cfg, text, d = config()
    local s = cfg and cfg.enabled == true and PT.SampleFor(b, i)
    if not s then
        PT.HideSample(b)
        return
    end
    layout(p, b, cfg, text, d)
    p.test = s
    p:Show()
    UF.ShowSample(p)
end

function PT.HideSample(b)
    local p = b.ptarget
    if not p then return end
    p.test = nil
    p:Hide()
end

-- Design mode's dots for a sample's target (member px, top left, y down):
-- where its middle sits at each spot with no nudge, matching `place`.
function PT.Dots(b)
    local p = b.ptarget
    local w, h, pw, ph = b:GetWidth(), b:GetHeight(), p:GetWidth(), p:GetHeight()
    local tab = b.tab and b.tab:IsShown() and (b.tabHeight or 0) or 0
    local x = w - (b.cut or 0) - pw / 2
    local function gap(spot) return PT.GAP + petRoom(spot) end
    return { { spot = "right", x = w + gap("right") + pw / 2, y = h / 2 },
             { spot = "left", x = -gap("left") - (b.ringReach or 0) - pw / 2, y = h / 2 },
             { spot = "below", x = x, y = h + gap("below") + (b.foot or 0) + ph / 2 },
             { spot = "above", x = x, y = -(gap("above") + tab + ph / 2) } }
end

-- How far a sample's target reaches past its member: up, down, left, right.
-- The Party page's preview makes room for it.
function PT.Reach(b)
    local p = b.ptarget
    if not (p and p:IsShown()) then return 0, 0, 0, 0 end
    local cfg = config()
    local w, h = p:GetWidth(), p:GetHeight()
    local spot = PT.SPOTS[cfg.spot] and cfg.spot or "right"
    local x, y, gap = tonumber(cfg.x) or 0, tonumber(cfg.y) or 0, PT.GAP + petRoom(spot)
    local bh = b:GetHeight()
    if spot == "left" then return 0, 0, w + gap + (b.ringReach or 0) - x, 0 end
    if spot == "below" then return 0, h + gap + (b.foot or 0) - y, 0, 0 end
    if spot == "above" then return h + gap + y, 0, 0, 0 end
    local over = math.max(0, (h - bh) / 2)
    return over + y, over - y, 0, w + gap + x
end
