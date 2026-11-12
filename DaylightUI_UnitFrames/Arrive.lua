-- The target frame's arrival animation. Plays only when going from no target
-- to a target, never on a swap (the frame stays shown and the new health lands
-- at once), and works in combat. The frame fades in, health and power grow from
-- empty (the client glides them, so secret values are fine), the portrait pops
-- in with a light running once around its ring, and the name tab slides up
-- from behind the body, clipped at the body's top edge (f.tabClip). The frame
-- itself is protected and never moves, only the pieces inside it. With motion
-- off it just shows. A style change (Daylight, Ribbon) uses the same arrival so
-- the new shape doesn't jump in (Units.lua, ns.Refresh).

local _, ns = ...
local DUI = DaylightUI
local Motion = DUI.Motion
local Style = DUI.Style

local Arrive = {}
ns.Arrive = Arrive

Arrive.POP_FROM = 0.6    -- the portrait starts at this scale
Arrive.OVERSHOOT = 0.1   -- and swells this much past 1 on the way
Arrive.LIGHT = 0.4       -- the light's trail at its brightest
local LIGHT_D = 1000     -- a long cooldown, reset each step to show a fraction

-- The light that runs around the ring: a cooldown swipe of the ring's band in
-- white for the trail, plus a glow at its head. Created on first use.
local function light(p)
    if p.arriveLight then return p.arriveLight end
    local UF = ns.UF
    local cd = CreateFrame("Cooldown", nil, p.top)
    cd:SetPoint("CENTER", p, "CENTER", 0, 0)
    cd:SetFrameLevel(p.top:GetFrameLevel() + 3)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(UF.RING_FILL_REVERSE)
    cd:Hide()
    local top = CreateFrame("Frame", nil, cd)
    top:SetAllPoints(p)
    top:SetFrameLevel(cd:GetFrameLevel() + 1)
    local head = top:CreateTexture(nil, "OVERLAY")
    head:SetTexture(DUI.MEDIA .. "glow.png")
    head:SetBlendMode("ADD")
    cd.head = head
    p.arriveLight = cd
    return cd
end

-- v is how far around the light has run (0-1, from the top, the same way the
-- aggro fill runs). nil hides it.
local function drawLight(f, v)
    local p = f.portrait
    local cd = p.arriveLight
    if not cd then return end
    if not v or v >= 1 then
        cd:Hide()
        return
    end
    local fade = 1 - v * v
    cd:SetSwipeColor(1, 1, 1, Arrive.LIGHT * fade)
    cd:SetCooldown(GetTime() - math.min(v, 0.999) * LIGHT_D, LIGHT_D)
    cd:Show()
    local turn = v * 2 * math.pi
    local r = p.radius or 0
    cd.head:ClearAllPoints()
    cd.head:SetPoint("CENTER", p, "CENTER", math.sin(turn) * r, math.cos(turn) * r)
    cd.head:SetAlpha(fade)
end

-- The tab's corner icons (leader, rest, PvP) hang off the tab, so they come
-- in with it instead of over the body.
local TAB_ICONS = { "leader", "rest", "pvp" }
local function tabIcons(f, a)
    local icons = f.status and f.status.icons
    if not icons then return end
    for _, k in ipairs(TAB_ICONS) do
        if icons[k] then icons[k]:SetAlpha(a) end
    end
end

local function keys(f)
    local k = f.arriveKeys
    if not k then
        k = { pop = {}, tab = {}, leave = {} }
        f.arriveKeys = k
    end
    return k
end

local function popStep(f, e)
    ns.UF.PlacePortrait(f, Arrive.POP_FROM + (1 - Arrive.POP_FROM) * e + Arrive.OVERSHOOT * math.sin(math.pi * e))
    drawLight(f, e)
end

local function tabStep(f, e)
    ns.UF.PlaceTab(f, (1 - e) * ns.UF.TabDrop(f))
    tabIcons(f, e)
end

local function tabDone(f)
    f.tabClip:SetClipsChildren(false)
end

-- fadeKey: the frame's fade area (a party button uses the party's).
-- fromHere: interrupted mid-leave, so the fade eases up from where it was.
function Arrive.Start(f, fadeKey, fromHere)
    if f.test or not Motion.On() then return end
    local u = f.unitToken
    if type(u) ~= "string" or not UnitExists(u) then return end
    -- Until then the fill keeps growing, whatever updates come in.
    f.arriving = GetTime() + Motion.SLOW
    if not fromHere then DUI.Fade.Arrive(fadeKey or ("UnitFrames." .. u), Motion.NORMAL) end
    -- Fills start from empty and the client glides them to the real values.
    f.health:SetValue(0)
    Style.GlideBar(f.health, UnitHealth(u))
    if f.power and f.power:IsShown() then
        f.power:SetValue(0)
        Style.GlideBar(f.power, UnitPower(u))
    end
    local k = keys(f)
    local p = f.portrait
    if p and p:IsShown() and f.portraitEdge then
        local cd = light(p)
        cd:SetSwipeTexture(p.fillFile or ns.UF.RING_FILE)
        cd:SetSize(p.ring:GetWidth(), p.ring:GetHeight())
        cd.head:SetSize(0.4 * p:GetWidth(), 0.4 * p:GetWidth())
        Motion.Tween(k.pop, 0, 1, Motion.SLOW, function(e) popStep(f, e) end)
    end
    if f.tab and f.tab:IsShown() then
        f.tabClip:SetClipsChildren(true)
        Motion.Tween(k.tab, 0, 1, Motion.SLOW, function(e) tabStep(f, e) end, function() tabDone(f) end)
    end
end

-- The unit left, or something else wants it over: settle at rest right away.
function Arrive.Finish(f)
    local k = f.arriveKeys
    if not k then return end
    if f.portraitEdge then Motion.Tween(k.pop, 1, 1, 0, function(e) popStep(f, e) end) end
    if f.tab then
        Motion.Tween(k.tab, 1, 1, 0, function(e) tabStep(f, e) end)
        tabDone(f)
    end
    f.arriving = nil
end

-- Leaving: when the target clears, the frame goes out the way it came. The
-- game's unit watch would hide it instantly, so it only reports the change
-- (RegisterUnitWatch asState, "state-unitexists"). A restricted snippet turns
-- the frame's clicks off right then, in combat too, and back on with a new
-- unit, showing it if it was hidden. The frame keeps its last look
-- (UF.UpdateAll draws nothing without a unit), fades out with its tab sliding
-- back behind the body, then hides. In combat the hide waits until combat
-- ends; the frame stays faded and click-through until then.
Arrive.SNIPPET = [[
    if name == "state-unitexists" then
        if value then
            self:EnableMouse(true)
            self:Show()
        else
            self:EnableMouse(false)
        end
    end
]]

local function fadeKey(f) return "UnitFrames." .. f.unitToken end

local function hideNow(f)
    if not f.gone then return end
    f.gone = nil
    DUI.Fade.Back(fadeKey(f))
    f:Hide()
end

local function hide(f)
    DUI.AfterCombat(function() hideNow(f) end, "arrive.hide." .. f.unitToken)
end

function Arrive.Leave(f)
    if f.gone or f.test or not f:IsShown() then return end
    f.gone = true
    Arrive.Finish(f)
    DUI.Fade.Leave(fadeKey(f), Motion.NORMAL)
    local k = keys(f)
    if not Motion.On() then
        hide(f)
        return
    end
    local tab = f.tab and f.tab:IsShown()
    if tab then f.tabClip:SetClipsChildren(true) end
    Motion.Tween(k.leave, 0, 1, Motion.NORMAL, function(e)
        if tab then tabStep(f, 1 - e) end
    end, function()
        if tab then tabStep(f, 1); tabDone(f) end
        hide(f)
    end)
end

-- A unit came back while it was leaving. It returns right away and arrives,
-- easing up from where its fade had reached.
function Arrive.Back(f)
    if not f.gone then return end
    f.gone = nil
    local k = keys(f)
    Motion.Tween(k.leave, 0, 0, 0, function() end)
    DUI.Fade.Back(fadeKey(f))
    ns.UF.UpdateAll(f, true)
    Arrive.Start(f, nil, true)
end

-- Test mode or the frame being turned off takes over, so stop everything.
function Arrive.Stop(f)
    if not f.gone then return end
    f.gone = nil
    Motion.Tween(keys(f).leave, 0, 0, 0, function() end)
    Arrive.Finish(f)
    DUI.Fade.Back(fadeKey(f))
end

-- From UF.Wire, out of combat: install the snippet, then our own handler.
function Arrive.Wire(f)
    local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    SecureHandlerWrapScript(f, "OnAttributeChanged", header, Arrive.SNIPPET)
    f:HookScript("OnAttributeChanged", function(self, name, value)
        if name ~= "state-unitexists" then return end
        if value then Arrive.Back(self) elseif value == false then Arrive.Leave(self) end
    end)
end

-- Shows and hides the frame by its unit (ns.SetEnabled, out of combat). The
-- attribute is cleared first so the watch's first check always reports.
function Arrive.Watch(f)
    -- No unit now: hide as is, never fade out something that wasn't seen.
    local u = f.unitToken
    if not (UnitExists(u) or UnitIsVisible(u)) then f:Hide() end
    f:SetAttribute("state-unitexists", nil)
    RegisterUnitWatch(f, true)
end
