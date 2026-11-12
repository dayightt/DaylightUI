-- Buff motion. In its last seconds the buff timer shifts to the warm end of the
-- Daylight gradient and pulses, using a color curve the client evaluates on the
-- time left, so it works in combat when the buttons are locked. Buffs and
-- debuffs also slide in as they land and lift away as they leave.

local _, BL = ...
local DUI = DaylightUI
local Style, Motion = DUI.Style, DUI.Motion

local Feel = {}
BL.Feel = Feel

Feel.EXPIRING = 5 -- seconds left when the timer turns warm
Feel.BREATH = 0.5 -- one pulse: full, dim, full
Feel.DIM = 0.45

-- The curve, rebuilt only when the motion setting changes.
local curve, curveMotion
local function expiringCurve()
    local motion = Motion.On()
    if curve ~= nil and curveMotion == motion then return curve or nil end
    curveMotion, curve = motion, false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    if Enum.LuaCurveType and c.SetType then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    -- x = seconds left. From 0 to EXPIRING: orange with a point every half
    -- pulse, dim on the odd ones. Just above that, the timer's normal color.
    local o, t = Style.GRADIENT[2], BL.Widgets.TIME_COLOR
    local step = Feel.BREATH / 2
    local n = math.floor(Feel.EXPIRING / step + 0.5)
    for i = 0, n do
        local dim = motion and i % 2 == 1
        c:AddPoint(i * step, CreateColor(o[1], o[2], o[3], dim and Feel.DIM or 1))
    end
    c:AddPoint(Feel.EXPIRING + 0.01, CreateColor(t[1], t[2], t[3], 1))
    curve = c
    return c
end

-- Color options for the buff bar's time text, or nil if the setting is off or
-- the client has no curves.
function Feel.TimeColor()
    if BL.GetSetting("expiring") == false then return nil end
    local prop = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration
    if prop == nil then return nil end
    local c = expiringCurve()
    return c and { curve = c, property = prop } or nil
end

-- Buffs and debuffs slide in and out ------------------------------------
-- In: the client plays an animation group we give each button
-- (AddAuraShownAnimation) when it comes up for a new aura, so it works in combat
-- and on the right icon (the client keeps one button per aura,
-- Blizzard_AuraContainerGroups.lua). Out: the client hides a button instantly,
-- so a copy of ours (bar look, aura icon) lifts away from where it was. Out of
-- combat only, since that's the only time we know where an icon sat.

Feel.SLIDE = 6 -- px an icon drops in from and lifts out by
Feel.GHOSTS = 8 -- max leaving copies at once; extras are skipped
Feel.SETTLE = 2 -- seconds after entering the world with no copies (a reload isn't news)
Feel.ghosts = {}
local settleUntil = 0

local function plain(v) return not (issecretvalue and issecretvalue(v)) and v or nil end

local function wanted() return BL.GetSetting("newGlow") ~= false and Motion.On() end

-- A button's slide-in, created once in initializeFrame and handed to the client,
-- then tuned by Feel.TuneSlide. It drops from SLIDE px above while fading in.
-- Translation and alpha only: a Scale animation draws masked pieces as hard
-- boxes.
function Feel.MakeSlide(btn)
    if type(btn.AddAuraShownAnimation) ~= "function" then return end
    local ag = btn:CreateAnimationGroup()
    local s = {}
    s.up = ag:CreateAnimation("Translation") -- jump up, invisible...
    s.up:SetOrder(1); s.up:SetDuration(0)
    s.hide = ag:CreateAnimation("Alpha")
    s.hide:SetOrder(1); s.hide:SetDuration(0)
    s.down = ag:CreateAnimation("Translation") -- ...then glide down into place
    s.down:SetOrder(2); s.down:SetSmoothing("OUT")
    s.show = ag:CreateAnimation("Alpha")
    s.show:SetOrder(2); s.show:SetSmoothing("OUT"); s.show:SetToAlpha(1)
    btn.slide = s
    Feel.TuneSlide(btn)
    btn:AddAuraShownAnimation(ag)
end

-- Tuned to zero while the setting or motion is off (the client keeps the group,
-- only its numbers change). The button is locked whenever auras are secret, so
-- this runs from StyleButton, after restrictions.
function Feel.TuneSlide(btn)
    local s = btn.slide
    if not s then return end
    local on = wanted()
    local d = on and Feel.SLIDE or 0
    s.up:SetOffset(0, d)
    s.down:SetOffset(0, -d)
    s.down:SetDuration(on and Motion.NORMAL or 0)
    s.show:SetDuration(on and Motion.NORMAL or 0)
    s.hide:SetFromAlpha(on and 0 or 1); s.hide:SetToAlpha(on and 0 or 1)
    s.show:SetFromAlpha(on and 0 or 1)
    btn.slideOn = on
end

local function quiet()
    return InCombatLockdown() or DUI.Restricted() or not wanted()
end

-- What each bar shows, read the frame after an aura change, so a leaving aura's
-- spot can be found. { [bar] = { flow, members, consolidated } }
Feel.snaps = {}

-- A bar's members: buffs by category, debuffs as one group in the client's order.
local function membersOf(bar)
    if not bar:IsDebuff() then return bar:AllMembers() end
    local entries, restricted = BL.Auras.Collect("HARMFUL")
    if restricted then return nil end
    return { debuffs = BL.Layout.SortLikeClient(entries) }
end

function Feel.Snap(bar)
    Feel.snaps[bar] = nil
    if quiet() or not (bar and bar.frame and bar.holder) then return end
    local members = membersOf(bar)
    if not members then return end
    local flow = bar:Flow(bar:IsDebuff() and #members.debuffs or members)
    local consolidated = {}
    for k, v in pairs(bar.consolidated or {}) do consolidated[k] = v end
    Feel.snaps[bar] = { flow = flow, members = members, consolidated = consolidated }
end

-- The element showing an aura: its group, at its place among the group's members
-- (sorted like the client's). A combined group has one icon, which stays while
-- others remain in it (nil).
function Feel.Find(flow, members, consolidated, id)
    if id == nil then return nil end
    for key, list in pairs(members) do
        for i, m in ipairs(list) do
            if m.auraInstanceID == id then
                if consolidated[key] and #list > 1 then return nil end
                local index = consolidated[key] and 1 or i
                for _, e in ipairs(flow.elements) do
                    if e.key == key and e.index == index then return e, m end
                end
                return nil -- its category is hidden
            end
        end
    end
end

local function ghost()
    for _, g in ipairs(Feel.ghosts) do
        if not g:IsShown() then return g end
    end
    if #Feel.ghosts >= Feel.GHOSTS then return nil end
    local g = BL.Widgets.CreateIconButton(UIParent)
    g:EnableMouse(false)
    g:Hide()
    Feel.ghosts[#Feel.ghosts + 1] = g
    return g
end

-- A copy of the leaving icon lifts away and fades from where it was. It hangs on
-- the holder but uses the bar's faded alpha.
function Feel.Leave(bar, e, m, alpha)
    local g = ghost()
    if not g then return end
    g:SetParent(bar.holder)
    g:SetFrameStrata("HIGH")
    g:SetScale(bar:Scale())
    g:SetIconSize(bar:Size(), bar:BorderPx())
    if bar:IsDebuff() then
        local c = BL.DispelColor(m.dispelName or "None") or BL.DISPEL_COLORS.None
        g:SetEdgeColor(c[1], c[2], c[3])
    else
        g:SetEdgeCategory(e.key)
    end
    g.Icon:SetTexture(m.icon)
    g:SetTimeLeft(nil)
    g:SetCount(m.applications)
    -- In the copy's own scaled units. The container starts after the weapon
    -- strip (as in BarMixin:ElementAt).
    local corner = bar:Corner()
    local l, _, _, t = BL.Layout.ElementRect(e, corner)
    local x = (corner == "TOPRIGHT" and -1 or 1) * (bar.weaponWidth or 0) + l
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", bar.holder, corner, x, t)
    g:SetAlpha(alpha)
    g:Show()
    Motion.Tween(g, 0, 1, Motion.CLOSE, function(p)
        g:SetAlpha(alpha * (1 - p))
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", bar.holder, corner, x, t + Feel.SLIDE * p)
    end, function() g:Hide() end)
end

local function snapAll()
    BL.EachBar(function(bar) DUI.SafeCall(Feel.Snap, bar) end)
end
-- Once, next frame, however many auras changed this frame.
local snapQueued = false
local function snapNext()
    if snapQueued then return end
    snapQueued = true
    C_Timer.After(0, function()
        snapQueued = false
        snapAll()
    end)
end

-- UNIT_AURA for the player: each removed aura found in the last snapshot of its
-- bar leaves a copy lifting away, then a fresh snapshot is taken next frame
-- (the client has sorted by then). Only out of combat and with no restriction,
-- when aura data is plain.
function Feel.OnAura(unit, info)
    if BL.Plain(unit) ~= "player" then return end
    if quiet() then
        -- runs on every UNIT_AURA in a fight, so no new table each time
        if next(Feel.snaps) then wipe(Feel.snaps) end
        return
    end
    if type(info) ~= "table" then return end
    local full = not issecretvalue(info.isFullUpdate) and info.isFullUpdate
    local removed = not full and type(info.removedAuraInstanceIDs) == "table" and info.removedAuraInstanceIDs or nil
    if removed and GetTime() >= settleUntil and not BL.Preview.Active() then
        for bar, snap in pairs(Feel.snaps) do
            local alpha = DUI.Fade.State(bar:FadeKey()) or 1
            if bar.holder and bar.holder:IsVisible() and alpha >= 0.05 then
                for _, id in ipairs(removed) do
                    local e, m = Feel.Find(snap.flow, snap.members, snap.consolidated, plain(id))
                    if e then Feel.Leave(bar, e, m, alpha) end
                end
            end
        end
    end
    if full or removed or type(info.addedAuras) == "table" then
        snapNext()
    end
end

-- A fresh snapshot once auras are plain again, and after a setting moves icons.
local function snapSoon()
    C_Timer.After(0, function() DUI.AfterRestrictions(snapAll, "buffs:feel:snap") end)
end

DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    settleUntil = GetTime() + Feel.SETTLE
    snapSoon()
end)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", snapSoon)
BL.OnPlayer("UNIT_AURA", function(_, unit, info) Feel.OnAura(unit, info) end)
BL.On("SETTINGS_CHANGED", snapSoon)
