-- Totems. The game's active-totem timers (TotemFrame) live under its own player
-- frame, which the unit frames hide, so they move to ours: just above its right end,
-- clear of the name tab, unless moved in unlock mode (TIMERS_KEY). They're styled
-- like the buff bar's icons (square element-colored edge, inner shade, time on the
-- top edge). The classic totem bar (MultiCastActionBarFrame) takes the stance bar's
-- spot by default, since a shaman has no stance bar. It sits in its own holder
-- (Totems.KIND, settings db.bars.totem) and gets the buttons' skin.

local _, ns = ...
local DUI = DaylightUI

local Totems = {}
ns.Totems = Totems

Totems.PLAYER = "DaylightUIFrame_player"
Totems.GAP = 11              -- space above the player frame, room for the time text
Totems.MULTICAST = { "MultiCastSummonSpellButton", "MultiCastRecallSpellButton" }
Totems.TIMERS_KEY = "actionbars.totemtimers"

-- The buff bar's numbers, copied so this works with Buffs disabled.
local BORDER_PX = 2
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TIME_COLOR = DUI.Style.INK.VALUE
-- A fixed size: the icon's measured width is unreliable while the game lays the
-- timers out, and sizing from it came out huge.
local TIME_SIZE = 11
-- Slot order in the game: fire, earth, water, air.
local ELEMENTS = { { 0.9, 0.35, 0.15 }, { 0.6, 0.45, 0.25 }, { 0.2, 0.55, 0.95 }, { 0.7, 0.85, 0.95 } }
local dressed = setmetatable({}, { __mode = "k" })

-- Only a shaman has the totem bar; for anyone else it's never touched.
function Totems.IsShaman()
    local _, class = UnitClass("player")
    return class == "SHAMAN"
end

-- Puts a frame at its spot now, and again the frame after the game's own layout may
-- have moved it (out of combat, since both frames are protected). No hook on its
-- SetPoint: Edit Mode calls that from protected code, and with a hook on the frame
-- the call failed ("attempt to call a nil value", on every layout update).
Totems.PLACE_EVENTS = { "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_ENTERING_WORLD", "UPDATE_MULTI_CAST_ACTIONBAR",
                        "PLAYER_TOTEM_UPDATE", "UPDATE_SHAPESHIFT_FORM", "PLAYER_TALENT_UPDATE" }
local places = {}

local function placeAll()
    for _, place in pairs(places) do DUI.SafeCall(place) end
end

-- Once on the next frame however many events came (no timer per event).
local placeQueued = false
local function placeLater()
    placeQueued = false
    DUI.AfterCombat(placeAll, "totems:place")
end
local function soon()
    if placeQueued then return end
    placeQueued = true
    C_Timer.After(0, placeLater)
end

local function pin(frame, place)
    places[frame] = place
    if not Totems.placeWired then
        Totems.placeWired = true
        for _, event in ipairs(Totems.PLACE_EVENTS) do pcall(DUI.RegisterEvent, event, soon) end
        -- Leaving Edit Mode puts them back at their Edit Mode spots.
        local em = _G.EditModeManagerFrame
        if type(em) == "table" and em.HookScript then em:HookScript("OnHide", soon) end
        -- The game restacks its bottom bars whenever one shows or hides (a pet, a
        -- form, a fight starting or ending), including the totem bar while it's at
        -- its Edit Mode default, and only through this callback
        -- (EditModeManager.lua UpdateBottomActionBarPositions). With no event for
        -- it, the bar sat at its Edit Mode spot, off its unlock handle, until a
        -- layout was written (Totems.FillLayout, held back while the controller UI
        -- is on or until the reload is taken).
        local R = _G.EventRegistry
        if type(R) == "table" and R.RegisterCallback then
            -- Put back immediately, not on the next frame: the game restacks on
            -- every form change (Ghost Wolf), and a frame late the bar visibly
            -- jumped away and back.
            local function now()
                if InCombatLockdown() then soon() else placeAll() end
            end
            pcall(R.RegisterCallback, R, "EditModeManager.UpdateBottomActionBarPositions", now, Totems)
        end
    end
    DUI.AfterCombat(function() DUI.SafeCall(place) end, "totems:pin:" .. tostring(frame:GetName()))
end

-- Our look on the time. The game recolors and refonts it on its own, so this runs
-- again after it does.
local function styleTime(fs, size)
    local S = DUI.Style
    fs:SetFont(S.FontFile(ns.MEDIA.font), size, S.Outline())
    fs:SetShadowOffset(S.TEXT_SHADOW[1], S.TEXT_SHADOW[2])
    fs:SetShadowColor(0, 0, 0, S.TEXT_SHADOW[3])
    fs:SetTextColor(TIME_COLOR[1], TIME_COLOR[2], TIME_COLOR[3])
end

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Seconds left on a totem slot. nil when the game hides it (secret) or there's no
-- totem.
local function timeLeft(slot)
    if type(slot) ~= "number" or not GetTotemInfo then return nil end
    local _, _, start, duration = GetTotemInfo(slot)
    if isSecret(start) or isSecret(duration) then return nil end
    if type(start) ~= "number" or type(duration) ~= "number" or duration <= 0 then return nil end
    return start + duration - GetTime()
end

-- Our time text, formatted like the buff bar ("55s", not the game's "55 s") but
-- rounded like the game (SecondsToTimeAbbrev: minutes, hours and days up, seconds
-- down). In a fight the game's own text shows instead because the time goes secret,
-- and with the buff bar's rounding a totem read 3 m then 2m as combat came and went.
function Totems.Time(left)
    if type(left) ~= "number" or left < 1 then return "" end
    if left >= 86400 then return string.format("%dd", math.ceil(left / 86400)) end
    if left >= 3600 then return string.format("%dh", math.ceil(left / 3600)) end
    if left >= 60 then return string.format("%dm", math.ceil(left / 60)) end
    return string.format("%ds", math.floor(left))
end

-- If the game won't give us the time, its own text shows instead.
local function tick(btn, d, fs)
    local left = timeLeft(btn.slot or (btn.GetID and btn:GetID()))
    if left then
        d.time:SetText(Totems.Time(left))
        if fs then fs:SetAlpha(0) end
    else
        d.time:SetText("")
        if fs then fs:SetAlpha(1) end
    end
end

-- How much closer together the timers sit than the game's own spacing (their rim art
-- is hidden, so its gap looks too wide).
Totems.TIMER_TIGHTEN = 4

-- Each timer is made a little narrower (its icon stays centered) so the game's own
-- layout packs them closer. Never through the frame's `spacing` or our own call to
-- its Layout: a value of ours on the game's frame taints its layout and
-- PlayerFrame_AdjustAttachments after it (blocked actions in a fight). A button new
-- to the game's pool is only narrowed after the game laid it out at full width
-- (TotemFrameMixin:Update runs Layout at once), so it reports that, and SkinTimers
-- then shifts the timers after it by what it lost (Totems.CloseUp). Pooled buttons
-- keep their width, so the game's later layouts are already tight.
local function tightenTimer(btn, d)
    d.baseW = d.baseW or btn:GetWidth()
    local want = d.baseW - Totems.TIMER_TIGHTEN
    if want > 0 and btn:GetWidth() ~= want then
        local lost = btn:GetWidth() - want
        btn:SetWidth(want)
        return lost
    end
    return 0
end

-- A totem timer button. The game's Icon frame holds the texture.
local function skinTotem(btn)
    local icon = btn.Icon
    local tex = type(icon) == "table" and (icon.Texture or icon.texture)
    if type(tex) ~= "table" or not tex.SetTexture then return end
    local d = dressed[btn]
    if not d then
        d = {}
        dressed[btn] = d
        -- All the game's art on the button and its child frames (round rims, the
        -- dark box behind the time), whatever it's called. Only the icon art stays.
        local function hideArt(frame)
            for _, reg in ipairs({ frame:GetRegions() }) do
                if reg ~= tex and reg.GetObjectType then
                    local kind = reg:GetObjectType()
                    if kind == "Texture" or kind == "MaskTexture" then reg:SetAlpha(0) end
                end
            end
            for _, child in ipairs({ frame:GetChildren() }) do hideArt(child) end
        end
        hideArt(btn)
        -- The game rounds the icon with a mask; buffs are square.
        local n = tex.GetNumMaskTextures and tex:GetNumMaskTextures()
        if type(n) == "number" then
            for i = n, 1, -1 do
                local m = tex:GetMaskTexture(i)
                if type(m) == "table" then tex:RemoveMaskTexture(m) end
            end
        end
        DUI.Style.CropIcon(tex)
        d.edge = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        d.edge:SetTexture(WHITE)
        local px = DUI.Pixel.Px(btn, BORDER_PX)
        d.edge:SetPoint("TOPLEFT", tex, "TOPLEFT", -px, px)
        d.edge:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", px, -px)
        -- Solid black under the art so the world never shows through it.
        d.back = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
        d.back:SetColorTexture(0, 0, 0, 1)
        d.back:SetAllPoints(tex)
        -- The icon is a child frame drawn over the button's own layers, so the
        -- shade and the time sit on a frame above it.
        d.top = CreateFrame("Frame", nil, btn)
        d.top:SetAllPoints(btn)
        d.top:SetFrameLevel(icon:GetFrameLevel() + 3)
        d.shade = d.top:CreateTexture(nil, "ARTWORK", nil, 2)
        d.shade:SetTexture(DUI.MEDIA .. "inner-shadow.png")
        d.shade:SetVertexColor(0, 0, 0, 1)
        d.shade:SetAllPoints(tex)
        d.time = d.top:CreateFontString(nil, "OVERLAY", nil, 7)
        d.time:SetJustifyH("CENTER")
        d.elapsed = 0
        d.top:SetScript("OnUpdate", function(_, dt)
            d.elapsed = d.elapsed + dt
            if d.elapsed < 0.1 then return end
            d.elapsed = 0
            tick(btn, d, d.fs)
        end)
    end
    styleTime(d.time, TIME_SIZE)
    d.time:ClearAllPoints()
    d.time:SetPoint("CENTER", tex, "TOP", 0, 0)
    -- Every update, since the game may re-anchor the time and slots reuse buttons.
    local fs = btn.Duration or btn.duration
    -- The game's own time, kept styled for when ours can't show.
    if type(fs) == "table" and fs.SetFont then
        d.fs = fs
        if fs:GetParent() ~= d.top then fs:SetParent(d.top) end
        styleTime(fs, TIME_SIZE)
        if not d.hooked then
            d.hooked = true
            local busy = false
            local function again(self)
                if busy then return end
                busy = true
                styleTime(self, TIME_SIZE)
                busy = false
            end
            hooksecurefunc(fs, "SetTextColor", again)
            hooksecurefunc(fs, "SetFontObject", again)
        end
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tex, "TOP", 0, 0)
        fs:SetDrawLayer("OVERLAY", 7)
    end
    tick(btn, d, d.fs)
    local lost = tightenTimer(btn, d)
    local slot = btn.slot or (btn.GetID and btn:GetID())
    local e = type(slot) == "number" and ELEMENTS[slot]
    local r, g, b
    if e then r, g, b = DUI.Style.Soften(e[1], e[2], e[3]) else r, g, b = DUI.Style.Neutral() end
    d.edge:SetVertexColor(r, g, b, 1)
    return lost
end

-- The game just laid the timers out using a button's old width (it was new to its
-- pool). Each timer after it in the game's order (layoutIndex) moves left by what the
-- ones before it lost, and the frame narrows by the total, matching where the game's
-- next layout would place them. Only points and size are touched (plain widget calls
-- that only the game's own next Layout reads, and overwrites); never `spacing` or
-- its Layout.
function Totems.CloseUp(tf, lost)
    local list = {}
    for btn in pairs(lost) do list[#list + 1] = btn end
    for _, child in ipairs({ tf:GetChildren() }) do
        if not lost[child] and type(child.layoutIndex) == "number" and child:IsShown() then list[#list + 1] = child end
    end
    table.sort(list, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)
    local shift = 0
    for _, btn in ipairs(list) do
        if shift > 0 and btn:GetNumPoints() == 1 then
            local p, rel, rp, x, y = btn:GetPoint(1)
            if type(x) == "number" and not isSecret(x) and not isSecret(y) then
                btn:ClearAllPoints()
                btn:SetPoint(p, rel, rp, x - shift, y)
            end
        end
        shift = shift + (lost[btn] or 0)
    end
    if shift > 0 and not (InCombatLockdown() and tf:IsProtected()) then tf:SetWidth(tf:GetWidth() - shift) end
end

function Totems.SkinTimers()
    local tf = TotemFrame
    if not tf then return end
    local lost
    for _, child in ipairs({ tf:GetChildren() }) do
        local n = skinTotem(child)
        if n and n > 0 and child:IsShown() then
            lost = lost or {}
            lost[child] = n
        end
    end
    if lost then Totems.CloseUp(tf, lost) end
end

-- The timers' toggle (setting totemTimers). Off, they wait in the same hidden frame
-- the bag bar uses, so the game showing them shows nothing.
function Totems.TimersOn()
    local db = ns.Settings()
    return not (type(db) == "table" and db.totemTimers == false)
end

-- The timers' spot: a saved spot from unlock mode, else above our player frame (only
-- the default needs it).
local function placeTimers(tf, player)
    if not Totems.TimersOn() then
        tf:SetParent(ns.Hide.parent)
        return
    end
    tf:SetParent(UIParent)
    tf:ClearAllPoints()
    local saved = DUI.DB.Positions()[Totems.TIMERS_KEY]
    if saved then
        local r = tf:GetEffectiveScale() / UIParent:GetEffectiveScale()
        tf:SetPoint("CENTER", UIParent, "CENTER", saved[1] / r, saved[2] / r)
    elseif player then
        tf:SetPoint("BOTTOMRIGHT", player, "TOPRIGHT", 0, Totems.GAP)
    end
end

-- Spreads the totem bar's buttons out from the first (which keeps whatever spot the
-- game gives it on the bar) by the spacing, across or down. shape = the bar's
-- settings (the caller scales the bar).
function Totems.LayoutBar(mc, shape)
    local pad = shape.pad or 2
    local prev
    for i = 1, 12 do
        local b = _G["MultiCastActionButton" .. i]
        if type(b) == "table" and b.SetPoint then
            if prev then
                b:ClearAllPoints()
                if shape.vertical then
                    b:SetPoint("TOP", prev, "BOTTOM", 0, -pad)
                else
                    b:SetPoint("LEFT", prev, "RIGHT", pad, 0)
                end
            end
            prev = b
            -- The slot button under it (with its own backdrop art) follows, or it
            -- peeks out where the spacing differs from the game's.
            local slot = _G["MultiCastSlotButton" .. i]
            if type(slot) == "table" and slot.SetPoint then
                slot:ClearAllPoints()
                slot:SetPoint("CENTER", b, "CENTER", 0, 0)
            end
        end
    end
end

-- The totem bar in our Edit Mode layout. At the game's default spot it counts as one
-- of the game's bottom bars (EditModeUtil.GetBottomActionBars), and the game
-- restacks those whenever one shows or hides, such as when a fight starts or ends.
-- That took the totem bar out of our holder to its own spot until our pin put it
-- back after the fight. Off its default, the game leaves it alone. The spot written
-- is the holder's own default (like the Extra Abilities button's, Bars.FillExtra),
-- so wherever the game puts its bar back (that restack, or its own updates
-- re-hanging the summon button, first slot and pages, MultiCastActionBarFrame.lua)
-- it lands where ours is. The game's own default sits over the middle of the action
-- bars; 1.6.8 and earlier wrote that one, so it counts as outdated (OLD_SPOT) and
-- is rewritten once.
Totems.OLD_SPOT = { point = "RIGHT", relativePoint = "BOTTOM", offsetX = -28, offsetY = 128 }

local function totemEntry(layout)
    local sys = Enum.EditModeSystem and Enum.EditModeSystem.TotemActionBar
    return sys ~= nil and DUI.EditMode.FindSystem(layout, sys, nil) or nil
end

local function atOldSpot(entry)
    local a, o = entry.anchorInfo, Totems.OLD_SPOT
    return type(a) == "table" and a.point == o.point and a.relativePoint == o.relativePoint
        and a.offsetX == o.offsetX and a.offsetY == o.offsetY
end

local function wantsWrite(entry)
    return entry ~= nil and (entry.isInDefaultPosition or atOldSpot(entry))
end

function Totems.FillLayout(layout)
    local entry = totemEntry(layout)
    if not wantsWrite(entry) then return end
    local d = ns.Shape.Defaults().totem
    -- Edit Mode's offsets are in the bar's own scale (ours, from the bar's size).
    local mc = _G.MultiCastActionBarFrame
    local r = 1
    if type(mc) == "table" and mc.GetEffectiveScale then
        r = mc:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if not (r > 0) then r = 1 end
    end
    DUI.EditMode.Anchor(entry, d.point, d.rel or d.point, d.x / r, d.y / r)
end

-- False while the saved layout still has it at the game's default spot. Only a
-- shaman has the bar, so nobody else is asked to reload for it.
function Totems.LayoutCurrent(layout)
    if not Totems.IsShaman() then return true end
    return not wantsWrite(totemEntry(layout))
end

function Totems.Apply()
    local tf = TotemFrame
    local player = _G[Totems.PLAYER]
    if tf then
        if not Totems.timersMoverRegistered then
            Totems.timersMoverRegistered = true
            DUI.Movers.Register(tf, Totems.TIMERS_KEY, "Totem Timers", nil, { proxy = true,
                minW = 150, minH = 40, active = Totems.TimersOn,
                onMoved = function()
                    DUI.AfterCombat(function() placeTimers(tf, _G[Totems.PLAYER]) end, "totems:timers")
                end })
        end
        -- The game's managed-frame system pulls the timers back under its (hidden)
        -- player frame every time they show, so they vanished with each new totem.
        -- This flag tells it to leave them alone (a plain field, not a hook). It's
        -- still a value of ours the game reads as a timer shows, and it's the only
        -- one left; in a fight nothing else keeps them out of its hidden player frame.
        tf.ignoreFramePositionManager = true
        pin(tf, function() placeTimers(tf, _G[Totems.PLAYER]) end)
        if not Totems.showHooked then
            Totems.showHooked = true
            tf:HookScript("OnShow", soon)
        end
        Totems.SkinTimers()
        if not Totems.hooked then
            Totems.hooked = true
            -- The game creates timer buttons as totems go down, in the frame's
            -- Update, which runs from its own OnEvent, the pet frame showing or
            -- hiding, and the player frame's art swap (TotemFrame.lua, PetFrame.lua,
            -- PlayerFrame.lua). Follow those, never with a hook on the frame's
            -- methods.
            local function again() Totems.SkinTimers() end
            tf:HookScript("OnEvent", again)
            local pet = _G.PetFrame
            if type(pet) == "table" and pet.HookScript then
                pet:HookScript("OnShow", again)
                pet:HookScript("OnHide", again)
            end
            if type(PlayerFrame_ToPlayerArt) == "function" then hooksecurefunc("PlayerFrame_ToPlayerArt", again) end
        end
    end
    local mc = Totems.IsShaman() and MultiCastActionBarFrame
    if mc then
        for i = 1, 12 do
            local b = _G["MultiCastActionButton" .. i]
            if b then ns.Skin.SetBar(b, "totem"); ns.Skin.Apply(b) end
        end
        for _, name in ipairs(Totems.MULTICAST) do
            if _G[name] then ns.Skin.SetBar(_G[name], "totem"); ns.Skin.Apply(_G[name]) end
        end
    end
end

-- The game moves the bar itself along with its bottom bars whenever one shows or
-- hides (a form like Ghost Wolf, a fight starting or ending) while it's at its Edit
-- Mode default (EditModeManager.lua UpdateBottomActionBarPositions), and in a fight
-- nothing may put it back. So its buttons hang on a stand-in frame with the bar's
-- size and scale, sitting where the bar sits in the holder. Each child the game
-- anchored to the bar is anchored the same way to the stand-in, so the game moving
-- the bar moves nothing visible. The game re-anchors them to the bar on its own
-- updates (MultiCastActionBarFrame.lua, the summon button's), which come with
-- UPDATE_MULTI_CAST_ACTIONBAR, one of PLACE_EVENTS, so this runs again after.
function Totems.Hold(mc, holder)
    local st = Totems.stand
    if not st then
        st = CreateFrame("Frame", nil, holder)
        Totems.stand = st
    end
    st:SetScale(mc:GetScale())
    st:SetSize(mc:GetWidth(), mc:GetHeight())
    st:ClearAllPoints()
    st:SetPoint("CENTER", holder, "CENTER", 0, 0)
    for _, child in ipairs({ mc:GetChildren() }) do
        local n = child:GetNumPoints()
        local pts = {}
        local moved = false
        for i = 1, n do
            local p, rel, rp, x, y = child:GetPoint(i)
            if rel == mc then rel, moved = st, true end
            pts[i] = { p, rel, rp, x, y }
        end
        if moved then
            child:ClearAllPoints()
            for _, q in ipairs(pts) do child:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
        end
    end
end

-- The totem kind: the game's totem bar itself goes in our holder, centered and
-- scaled, and LayoutBar spaces and orients its buttons. Whether it shows stays the
-- game's call (only with totems known). It has no buttons of its own for Bars.lua;
-- the skin is applied by Totems.Apply.
Totems.KIND = {
    Setup = function(def, holder)
        local mc = _G.MultiCastActionBarFrame
        if type(mc) ~= "table" or not Totems.IsShaman() then return {} end
        mc:SetParent(holder)
        -- The game fills its slots on these, so the unlock handle and the bar's
        -- panel (only for a bar in use) follow.
        for _, event in ipairs({ "UPDATE_MULTI_CAST_ACTIONBAR", "PLAYER_ENTERING_WORLD" }) do
            pcall(DUI.RegisterEvent, event, function()
                C_Timer.After(0, function()
                    DUI.Movers.Recheck(ns.Bars.MoverKey(def))
                    ns.Bars.PaintBacksSoon()
                end)
            end)
        end
        pin(mc, function()
            mc:ClearAllPoints()
            mc:SetPoint("CENTER", holder, "CENTER", 0, 0)
            Totems.Hold(mc, holder)
        end)
        return {}
    end,
    Count = function() return 1 end,
    Base = function() return ns.Shape.SMALL_BUTTON end,
    Layout = function(_, holder, cfg)
        local mc = _G.MultiCastActionBarFrame
        if type(mc) ~= "table" or not Totems.IsShaman() then
            holder:SetSize(1, 1)
            return
        end
        local s = cfg.size / 100
        mc:SetScale(s)
        Totems.LayoutBar(mc, cfg)
        if not InCombatLockdown() then Totems.Hold(mc, holder) end
        local w, h = mc:GetWidth() * s, mc:GetHeight() * s
        if cfg.vertical then w, h = h, w end
        holder:SetSize(math.max(w, 1), math.max(h, 1))
    end,
    -- A handle only while the game shows the bar: a shaman with totems on it (the
    -- game's HasMultiCastActionBar; with none it only shows in Edit Mode).
    -- Rechecked as the game fills it (Totems.WatchInUse).
    InUse = function()
        return Totems.IsShaman() and type(HasMultiCastActionBar) == "function" and HasMultiCastActionBar() == true
    end,
    Rule = function() return "[petbattle][vehicleui][overridebar] hide; " end,
    Caps = { show = "totem" },
}
