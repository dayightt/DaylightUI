-- Party cast bars, driven by CastBar.lua's engine (settings partyCastbar.*).
-- Placement modes: "power" puts the bar over the power bar (default), "slide"
-- hangs it under the frame and slides it out during a cast, "free" gives it
-- its own spot beside the frame, nudged by x/y.
--
-- Each party button gets both bars, like the target. They live inside the
-- button so they inherit its scale and fade, including range fade. The header
-- re-sorts buttons in combat, so the bars' events follow the unit through
-- CB.SetUnit, which is allowed in combat. Sample buttons get bars with no unit.

local _, ns = ...
local DUI = DaylightUI
local CB = ns.CastBar

local PC = {}
ns.PartyCasts = PC

PC.GAP = 4   -- gap between a detached bar and its frame
PC.SPOTS = { right = "Right of the frame", left = "Left of the frame", below = "Under the frame", above = "Over the frame" }
PC.SPOT_ORDER = { "right", "left", "below", "above" }

local function db() return ns.module and ns.module.db end

local function unitOf(b)
    if b.preview then return nil end
    local u = b.unitToken
    return type(u) == "string" and u or nil
end

-- The two bars on a party button, real or sample. Nothing protected here.
function PC.Make(b)
    if b.casts or not b.power then return b.casts end
    local u = unitOf(b)
    local inside = CB.Create(u, b, b.power, { kind = "party" })
    for _, tex in ipairs({ inside.bg, inside.bar:GetStatusBarTexture(), DUI.Style.BarBack(inside.bar) }) do
        DUI.Style.Clip(b, tex, "inner")
    end
    local own = CB.Create(u, nil, nil, { kind = "party", parent = b })
    own.near = b
    own.under, own.hangAt = b, "slide"
    b.casts = { inside = inside, own = own }
    if not b.preview then
        b:HookScript("OnAttributeChanged", function(btn, name, value)
            if name == "unit" then PC.Retarget(btn, value) end
        end)
    end
    return b.casts
end

-- The member changed, so both bars follow. Allowed in combat.
function PC.Retarget(b, unit)
    local c = b.casts
    if not c then return end
    unit = type(unit) == "string" and unit or nil
    CB.SetUnit(c.inside, unit)
    CB.SetUnit(c.own, unit)
end

-- A detached bar beside its frame, on its side, nudged by x/y.
local function place(h, b, cfg)
    local gap, x, y = PC.GAP, tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    h:ClearAllPoints()
    if cfg.spot == "left" then
        -- Stay clear of the portrait ring hanging off the outer end.
        h:SetPoint("RIGHT", b, "LEFT", -gap - (b.ringReach or 0) + x, y)
    elseif cfg.spot == "below" then
        h:SetPoint("TOP", b, "BOTTOM", x, -gap - (b.foot or 0) + y)
    elseif cfg.spot == "above" then
        local tab = b.tab and b.tab:IsShown() and (b.tabHeight or 0) or 0
        h:SetPoint("BOTTOM", b, "TOP", x, gap + tab + y)
    else
        h:SetPoint("LEFT", b, "RIGHT", gap + x, y)
    end
end

-- Lays out both bars from the settings. Called from every party button's
-- layout (Group:LayoutButton) and each sample's.
function PC.Layout(b)
    local d = db()
    if not (d and d.partyCastbar) then return end
    local cfg = d.partyCastbar
    if not b.casts then
        if cfg.enabled ~= true then return end
        if not PC.Make(b) then return end
    end
    local c = b.casts
    local at = CB.At("party", cfg)
    local on = cfg.enabled == true
    CB.Layout(c.inside, { enabled = on and at == "power", textSize = cfg.textSize, insideTextSize = cfg.insideTextSize,
                          textColor = cfg.textColor }, d.party)
    CB.Layout(c.own, { enabled = on and at ~= "power", at = at, width = cfg.width, height = cfg.height,
                       showIcon = cfg.showIcon, slant = at == "slide" or cfg.slant, textSize = cfg.textSize,
                       reverseFill = cfg.reverseFill, textColor = cfg.textColor })
    if at == "free" then place(c.own, b, cfg) end
end

-- The bar a cast shows on right now.
function PC.Shown(b)
    local d, c = db(), b.casts
    if not (d and c) then return nil end
    return CB.At("party", d.partyCastbar) == "power" and c.inside or c.own
end

-- Samples: the sample healer casts while test mode shows cast bars.
PC.SAMPLE = { text = DUI.L["Flash Heal"], value = 0.55, icon = "Interface\\Icons\\Spell_Holy_FlashHeal" }

function PC.ShowSample(b, casting)
    local d = db()
    if not (d and d.partyCastbar and d.partyCastbar.enabled == true) then return PC.HideSample(b) end
    PC.Layout(b)
    local c = b.casts
    if not c then return end
    if not (casting and DUI.TestPartShown("castbars")) then return PC.HideSample(b) end
    local shown = PC.Shown(b)
    CB.HideSample(shown == c.inside and c.own or c.inside)
    CB.ShowSample(shown, PC.SAMPLE)
end

function PC.HideSample(b)
    local c = b.casts
    if not c then return end
    CB.HideSample(c.inside)
    CB.HideSample(c.own)
end
