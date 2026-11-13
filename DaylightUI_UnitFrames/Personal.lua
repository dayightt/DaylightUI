-- Your own health, power and combo points just under your character, like
-- Legion's personal resource display. That one was a nameplate on you. This
-- client has no player nameplate and no way to ask where your character is on
-- screen (the game's own display became a fixed Edit Mode frame), so the spot
-- is derived from the camera. The camera aims at your character, so your feet
-- sit straight below the screen's middle, at a drop that shrinks as you zoom
-- out. The drop grows with your model's height (race, form, mount) and the
-- over-the-shoulder camera shifts it sideways. Each new spot is eased to.
--
-- Nothing runs while the camera is still. A zoom (the game's global zoom
-- functions are hooked), mounting, a form change or a resize wakes the follow,
-- which stops once the camera settles. Not clickable and not protected, so it
-- moves, shows and fades in combat like any other addon frame.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion

local PR = {}
ns.Personal = PR

PR.KEY = "unitframes.personal"
PR.FADE = "UnitFrames.personal"

-- Camera constants. These are estimates tuned in game, since the client says
-- nothing about where the character is or how big it is.
PR.VIEW = 1.5        -- 2 tan(half the view's height) at cameraFov 90 (90 across a 4:3 screen)
PR.FEET = 2.3        -- yards from the camera's aim point down to just under a human's feet (measured off a screenshot)
PR.MIN_ZOOM = 1.5    -- closer (first person) counts as this
PR.EDGE = 0.1        -- never closer to the screen's bottom than this share of its height
PR.SHOULDER = 0.9    -- how much of the over-the-shoulder shift to follow (more overshoots)
PR.NO_CAMERA = 0.16  -- without a camera reading: this share of the screen height below the middle
PR.EASE = Motion.FAST   -- the glide toward a new spot (time constant)
PR.SETTLE = 10       -- frames the zoom must hold still before the follow stops

-- Model height relative to a human's (raceFile), shapeshift form id, mounted.
PR.RACE = { Human = 1, Dwarf = 0.8, NightElf = 1.15, Gnome = 0.55, Orc = 1.05, Scourge = 0.95, Tauren = 1.3,
            Troll = 1.15, BloodElf = 1, Draenei = 1.15 }
PR.FORM = { [1] = 0.7, [3] = 0.85, [4] = 0.6, [5] = 1.05, [8] = 1.05, [16] = 0.75, [31] = 1.2 }
PR.MOUNTED = 1.55

PR.DOCK_GAP = 4      -- gap between the pieces stacked under the bars
PR.TEXT_MIN = 8      -- a number sized to fit its bar never goes smaller than this
PR.TEXT_PAD = 4      -- a number's gap from the bar's end

PR.POWER_POLL = 0.05   -- your power fills between the game's events, so poll while it moves
PR.POWER_REST = 1      -- s of unchanged power before the poll rests until the next power event

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function db() return ns.module and ns.module.db and ns.module.db.personal end

-- One body like the player frame: health over power in a single shell, a thin
-- line between them, one angled end across both. Either bar can be turned off
-- and the other then fills the shell alone.
local function makeBody(parent, media)
    local s = CreateFrame("Frame", nil, parent)
    s:EnableMouse(false)
    -- What the player frame's heal and shield bars read off a frame.
    s.spec, s.unitToken = { unit = "personal", slant = "right" }, "player"
    Style.Shell(s)
    Style.Slant(s, nil, 0)
    s.health = Style.Bar(s, nil, media.bars.health)
    s.power = Style.Bar(s, nil, media.bars.power)
    s.separator = Style.Separator(s)
    for _, tex in ipairs({ s.health:GetStatusBarTexture(), Style.BarBack(s.health), s.power:GetStatusBarTexture(),
                           Style.BarBack(s.power), s.separator }) do
        Style.Clip(s, tex, "inner")
    end
    -- The numbers, over the bars and the cost shade.
    local over = CreateFrame("Frame", nil, s)
    over:SetAllPoints(s)
    over:EnableMouse(false)
    over:SetFrameLevel(s.health:GetFrameLevel() + 3)
    s.healthText = Style.Text(over, 11, "CENTER", media.fonts.health)
    s.powerText = Style.Text(over, 10, "CENTER", media.fonts.power)
    s.healthText:Hide()
    s.powerText:Hide()
    return s
end

-- How far its angled end leans: its own angle, else the shared Slant angle.
function PR.Angle()
    local cfg = db()
    local a = cfg and tonumber(cfg.angle)
    if a and a > 0 then return a end
    return ns.UF.SLANT
end

-- Lays body s out w wide: health h tall (0 for none), then power p tall (0 for
-- none), angled on side. Returns its height and the cut.
local function layBody(s, w, h, p, side)
    local T = Pixel.Px(s, Style.BorderPx(s))
    local hh, ph = h > 0 and Pixel.Snap(s, h) or 0, p > 0 and Pixel.Snap(s, p) or 0
    local both = hh > 0 and ph > 0
    local line = both and Pixel.Px(s, Style.SEPARATOR_PX) or 0
    local H = hh + line + ph + 2 * T
    s:SetSize(2 * Pixel.Snap(s, w / 2), H)
    local cut = side and Pixel.Snap(s, H * PR.Angle()) or 0
    Style.Slant(s, side, cut)
    local health, power = s.health, s.power
    health:SetShown(hh > 0)
    s.healthCut = cut * hh / H
    if hh > 0 then
        health:ClearAllPoints()
        health:SetPoint("TOPLEFT", s, "TOPLEFT", T, -T)
        health:SetPoint("TOPRIGHT", s, "TOPRIGHT", -T, -T)
        health:SetHeight(hh)
        Style.AngleFill(health, side, s.healthCut)
    end
    power:SetShown(ph > 0)
    s.separator:SetShown(both)
    if ph > 0 then
        power:ClearAllPoints()
        power:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", T, T)
        power:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -T, T)
        power:SetHeight(ph)
        Style.AngleFill(power, side, cut * ph / H)
    end
    if both then
        s.separator:ClearAllPoints()
        s.separator:SetPoint("BOTTOMLEFT", power, "TOPLEFT", 0, 0)
        s.separator:SetPoint("BOTTOMRIGHT", power, "TOPRIGHT", 0, 0)
        s.separator:SetHeight(line)
    end
    Style.LayoutShell(Style.GetShell(s))
    return H, cut
end

-- One number on its bar: at the angled end (clear of the cut), the middle or
-- the square end. Never read back, since a text showing a secret has secret anchoring.
local function placeNumber(fs, bar, pos, endPad, y)
    fs:ClearAllPoints()
    if pos == "inner" then
        ns.UF.PlaceText(fs, "RIGHT", bar, "RIGHT", -endPad, y)
        fs:SetJustifyH("RIGHT")
    elseif pos == "outer" then
        ns.UF.PlaceText(fs, "LEFT", bar, "LEFT", PR.TEXT_PAD, y)
        fs:SetJustifyH("LEFT")
    else
        ns.UF.PlaceText(fs, "CENTER", bar, "CENTER", 0, y)
        fs:SetJustifyH("CENTER")
    end
end

local function numberSize(size, barHeight)
    size = tonumber(size) or 0
    if size > 0 then return size end
    return math.max(PR.TEXT_MIN, math.floor(barHeight * 0.85 + 0.5))
end

function PR.LayoutNumbers(cfg, cut, H, showHealth)
    local s = PR.frame.body
    local function lay(fs, bar, on, pos, size, y)
        fs:SetShown(on)
        if not on then return end
        local hh = bar:GetHeight()
        Style.SetTextSize(fs, numberSize(size, hh))
        Style.InkText(fs, "VALUE")
        placeNumber(fs, bar, pos, cut * hh / H + PR.TEXT_PAD, y)
    end
    lay(s.healthText, s.health, showHealth and cfg.showPercent == true, cfg.healthTextPos, cfg.healthTextSize, 0)
    lay(s.powerText, s.power, cfg.showPower ~= false and cfg.showPowerText == true, cfg.powerTextPos,
        cfg.powerTextSize, Pixel.Px(s, 1))
end

-- Whether your cast bar ("castbar") or swing bars ("swing") stand under the
-- display. The real bars move here, nothing is drawn twice.
function PR.Docks(kind)
    local cfg = db()
    return cfg ~= nil and cfg.enabled == true and cfg[kind] == true
end

function PR.Create()
    local media = ns.UF.MEDIA.personal
    local h = CreateFrame("Frame", "DaylightUIPersonal", UIParent)
    h:EnableMouse(false)
    h:SetFrameStrata("LOW")
    h.body = makeBody(h, media)
    h.healthBar, h.powerBar = h.body.health, h.body.power
    h.healthText, h.powerText = h.body.healthText, h.body.powerText
    -- What the health painting reads off a frame (UF.PaintHealth).
    h.paint = { health = h.healthBar, unitToken = "player" }
    h:Hide()
    PR.frame = h

    -- Its events are only on while the display is (PR.Listen, from Layout).
    h:SetScript("OnEvent", function(_, event)
        if h.test then return end
        if event == "PLAYER_TARGET_CHANGED" then
            -- Combo points belong to the target here (Combo.lua).
            if h.combo then ns.Combo.Update(h.combo, true) end
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            PR.UpdateHealth()
        elseif event == "UNIT_POWER_FREQUENT" then
            PR.WakePower()
        elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
            PR.UpdatePower()
        elseif event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
            ns.UF.UpdatePrediction(h.body)
        else
            PR.UpdateShown()
        end
    end)

    -- The power poll only runs while the value moves, since your power fills
    -- smoothly between events (same as UF.PollPower).
    local poll = CreateFrame("Frame", nil, h)
    poll:Hide()
    poll:SetScript("OnUpdate", function(self, dt)
        self.wait = (self.wait or 0) - dt
        if self.wait > 0 then return end
        self.wait = PR.POWER_POLL
        PR.PollPower()
    end)
    h.poll = poll

    -- The follow runs while the camera moves (PR.Step).
    local follow = CreateFrame("Frame")
    follow:Hide()
    follow:SetScript("OnUpdate", function(_, dt) PR.Step(dt) end)
    PR.follow = follow
    PR.HookCamera()

    local list = { h }
    DUI.Movers.Register(h, PR.KEY, "Personal Display", { "TOP", nil, "CENTER", 0, -110 })
    -- The engine's own alpha, never read back from the frame. Fully faded, the
    -- power poll rests. Coming back, it starts again right away.
    DUI.Fade.Register{ key = PR.FADE, scope = "UnitFrames", path = "personal.fade",
        page = "UnitFrames.personal", frames = function() return list end, whole = true,
        paint = function(f, a)
            f:SetAlpha(a)
            local gone = a <= 0
            if PR.faded and not gone then PR.faded = false; PR.WakePower()
            else PR.faded = gone end
        end }
    return h
end

-- The display's events are only on while it is, so off costs nothing. The
-- health ones only while it has a health bar.
local EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_TARGET_CHANGED" }
local UNIT_EVENTS = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED" }
function PR.Listen(on, health)
    local h = PR.frame
    health = on and health
    if health ~= h.listeningHealth then
        h.listeningHealth = health
        for _, e in ipairs(HEALTH_EVENTS) do
            if health then h:RegisterUnitEvent(e, "player") else h:UnregisterEvent(e) end
        end
    end
    if on == h.listening then return end
    h.listening = on
    for _, e in ipairs(UNIT_EVENTS) do
        if on then h:RegisterUnitEvent(e, "player") else h:UnregisterEvent(e) end
    end
    for _, e in ipairs(EVENTS) do
        if on then h:RegisterEvent(e) else h:UnregisterEvent(e) end
    end
end

-- Where your feet are

-- The camera's distance in yards, or nil when there's no reading on this client.
function PR.Zoom()
    if type(GetCameraZoom) ~= "function" then return nil end
    local z = GetCameraZoom()
    if type(z) ~= "number" or isSecret(z) then return nil end
    return z
end

local function cvarNumber(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(get) ~= "function" then return nil end
    local v = get(name)
    if isSecret(v) then return nil end
    return tonumber(v)
end

-- 2 tan(half the view's height), from the camera's field of view.
function PR.View()
    local fov = cvarNumber("cameraFov")
    if not fov or fov <= 0 then return PR.VIEW end
    return PR.VIEW * math.tan(math.rad(fov) / 2)
end

-- How tall your model is relative to a human's. The race can be secret under
-- the client's restrictions (UnitRace is "SecretWhenUnitIdentityRestricted"),
-- so the last plain value is kept.
function PR.Size()
    local _, race = UnitRace("player")
    if type(race) == "string" and not isSecret(race) then PR.race = race end
    local k = PR.race and PR.RACE[PR.race] or 1
    local mounted = IsMounted()
    if not isSecret(mounted) and mounted then return k * PR.MOUNTED end
    local form = type(GetShapeshiftFormID) == "function" and GetShapeshiftFormID() or nil
    if type(form) ~= "number" or isSecret(form) then return k end
    return k * (PR.FORM[form] or 1)
end

-- The spot for the display's top, as offsets from the screen's middle in
-- UIParent units, for a camera zoom (nil when none was read).
function PR.Spot(zoom, cfg)
    local H = UIParent:GetHeight()
    local nx, ny = tonumber(cfg.x) or 0, tonumber(cfg.y) or 0
    if not zoom then return nx, ny - H * PR.NO_CAMERA end
    local perYard = H / (math.max(zoom, PR.MIN_ZOOM) * PR.View())
    local drop = math.min(PR.FEET * PR.Size() * perYard, H * (0.5 - PR.EDGE))
    -- Over the shoulder the camera slides right, so you sit left of the middle.
    local side = -(cvarNumber("test_cameraOverShoulder") or 0) * PR.SHOULDER * perYard
    return side + nx, ny - drop
end

local function place(x, y)
    local h = PR.frame
    local s = h:GetScale()
    if not s or s <= 0 then s = 1 end
    h:ClearAllPoints()
    h:SetPoint("TOP", UIParent, "CENTER", x / s, y / s)
end

-- One frame of the follow: read the camera, ease toward its spot, and rest once
-- the camera has held still and the display has arrived.
function PR.Step(dt)
    local cfg = db()
    if not cfg or not PR.following then
        PR.follow:Hide()
        return
    end
    local zoom = PR.Zoom()
    if zoom == PR.lastZoom then
        PR.still = (PR.still or 0) + 1
    else
        PR.still, PR.lastZoom = 0, zoom
    end
    local tx, ty = PR.Spot(zoom, cfg)
    if not PR.x or not Motion.On() then
        PR.x, PR.y = tx, ty
    else
        local k = 1 - math.exp(-(dt or 0) / PR.EASE)
        PR.x, PR.y = PR.x + (tx - PR.x) * k, PR.y + (ty - PR.y) * k
    end
    local close = math.abs(tx - PR.x) < 0.5 and math.abs(ty - PR.y) < 0.5
    if close and PR.still >= PR.SETTLE then
        PR.x, PR.y = tx, ty
        PR.follow:Hide()
    end
    place(PR.x, PR.y)
end

-- Something moved the camera or changed your size, so follow until it settles.
function PR.Wake()
    if not PR.following then return end
    PR.still = 0
    PR.follow:Show()
end

-- The game's zoom functions (mouse wheel and zoom keys go through them). These
-- are global functions, never a game object's method.
local CAMERA_CALLS = { "CameraZoomIn", "CameraZoomOut", "MoveViewInStart", "MoveViewOutStart", "SetView", "ResetView" }
function PR.HookCamera()
    if PR.hooked then return end
    PR.hooked = true
    for _, name in ipairs(CAMERA_CALLS) do
        if type(_G[name]) == "function" then hooksecurefunc(name, PR.Wake) end
    end
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_MOUNT_DISPLAY_CHANGED", "UPDATE_SHAPESHIFT_FORM",
                             "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CVAR_UPDATE" }) do
        DUI.RegisterEvent(event, PR.Wake)
    end
end

-- Bars

function PR.UpdateHealth(instant)
    local h = PR.frame
    if not h or h.test or not h.healthBar:IsShown() then return end
    local bar = h.healthBar
    local max = UnitHealthMax("player")
    Style.SetBarRange(bar, 0, max)
    Style.SetBarValue(bar, UnitHealth("player"), instant)
    if h.body.heals then ns.UF.UpdatePrediction(h.body, max) end
    -- The "gradient" health color follows the health, same as UF.UpdateHealth.
    ns.UF.ApplyGradient(h.paint)
    if h.healthText:IsShown() then
        local cfg = db()
        ns.UF.WriteHealth(h.healthText, cfg.healthText, "player", cfg.percentSign, cfg.hideFullHealth)
    end
end

-- Its own bar colors, or the player frame's while set to "player". Called from
-- Layout, which every setting change goes through after the player frame's
-- own layout.
function PR.ReadColors(cfg)
    local f, own = PR.frame.paint, ns.frames and ns.frames.player or {}
    if cfg.colorHealth == "player" then f.healthMode, f.healthCustom = own.healthMode, own.healthCustom
    else f.healthMode, f.healthCustom = cfg.colorHealth, cfg.colorHealthCustom end
    if cfg.colorPower == "player" then f.powerMode, f.powerCustom = own.powerMode, own.powerCustom
    else f.powerMode, f.powerCustom = cfg.colorPower, cfg.colorPowerCustom end
end

function PR.PaintHealth()
    local f = PR.frame.paint
    f.state = ns.UF.UnitState("player")
    local r, g, b = ns.UF.UnitColor("player")
    if f.state then r, g, b = ns.UF.StateColor(f.state) end
    ns.UF.PaintHealth(f, r, g, b)
end

function PR.UpdatePower(instant)
    local h = PR.frame
    if not h or h.test or not h.powerBar:IsShown() then return end
    local bar = h.powerBar
    bar:SetMinMaxValues(0, UnitPowerMax("player"))
    local _, token = UnitPowerType("player")
    ns.UF.PaintPower(bar, token, "player", h.paint)
    PR.polled = nil
    PR.FeedPower(instant)
    PR.WakePower()
end

-- Sets the value on the bar. Returns true when it moved (a secret one counts as moved).
function PR.FeedPower(instant)
    local v = UnitPower("player")
    if not isSecret(v) and v == PR.polled and not instant then return false end
    PR.polled = not isSecret(v) and v or nil
    local h = PR.frame
    Style.SetBarValue(h.powerBar, v, instant)
    if h.powerText:IsShown() then
        local cfg = db()
        ns.UF.WritePower(h.powerText, cfg.powerFormat, "player", cfg.hideFullPower, cfg.powerPercentSign)
    end
    return true
end

function PR.PollPower()
    local h = PR.frame
    if PR.faded or not h:IsShown() or not h.powerBar:IsShown() then
        h.poll:Hide()
        return
    end
    local now = GetTime()
    if PR.FeedPower() then PR.powerMoved = now end
    if now - (PR.powerMoved or 0) > PR.POWER_REST then h.poll:Hide() end
end

function PR.WakePower()
    local h = PR.frame
    if not h or h.test or PR.faded or not h:IsShown() or not h.powerBar:IsShown() then return end
    PR.powerMoved = GetTime()
    h.poll:Show()
end

-- Layout and showing

-- Shown while on and alive (a ghost has no bars to watch). The fade handles
-- the rest (in combat, with a target).
function PR.UpdateShown()
    local h, cfg = PR.frame, db()
    if not h or not cfg then return end
    local state = not h.test and ns.UF.UnitState("player") or nil
    local show = cfg.enabled == true and state ~= "dead" and state ~= "ghost"
    if show and not h:IsShown() then
        h:Show()
        PR.UpdateAll()
    elseif not show then
        h:Hide()
    end
end

function PR.UpdateAll()
    if not PR.frame or PR.frame.test then return end
    PR.PaintHealth()
    PR.UpdateHealth(true)
    PR.UpdatePower(true)
    if PR.frame.combo then ns.Combo.Update(PR.frame.combo, true) end
end

function PR.Layout(cfg)
    local h = PR.frame
    if not h or not cfg then return end
    h:SetScale(DUI.Movers.Scale(PR.KEY))
    PR.ReadColors(cfg)
    ns.UF.ApplyShell(h.body, cfg)
    local side = cfg.slant ~= false and "right" or nil
    local w = tonumber(cfg.width) or 150
    local p = cfg.showPower ~= false and (tonumber(cfg.powerHeight) or 5) or 0
    -- Never both off, since a display with no bars would be an empty shell.
    local showHealth = cfg.showHealth ~= false or p <= 0
    local H, cut = layBody(h.body, w, showHealth and (tonumber(cfg.height) or 10) or 0, p, side)
    h.body:ClearAllPoints()
    h.body:SetPoint("TOP", h, "TOP", 0, 0)
    h:SetSize(h.body:GetWidth(), H)
    h.cut, h.foot, h.cutSide = cut, 0, "right"
    PR.LayoutNumbers(cfg, cut, H, showHealth)
    -- The spell cost shade, the player frame's own (set on the Player page),
    -- created the first time the display is on.
    local body = h.body
    -- Incoming heals and shields, using the player frame's bars and colors,
    -- created the first time the display has a health bar.
    body.predictHeals = showHealth and cfg.predictHeals ~= false
    body.predictAbsorbs = showHealth and cfg.predictAbsorbs ~= false
    if cfg.enabled and showHealth and not body.heals then ns.UF.CreatePrediction(body) end
    if body.heals then ns.UF.LayoutPrediction(body, side) end
    if cfg.enabled and not body.cost then ns.UF.CreateCost(body, { slant = true }) end
    if body.cost then
        ns.UF.LayoutCost(body, side, cut * body.power:GetHeight() / H, ns.module.db.player)
        if not cfg.enabled or p <= 0 then
            body.costPreview = false
            body.cost:Hide()
        end
    end
    -- Its own combo row, created the first time the display is on (nil except
    -- for rogues and druids), so it costs nothing while off.
    if cfg.enabled and not h.comboMade then
        h.comboMade = true
        h.combo = ns.Combo.Create(h)
    end
    if h.combo then
        local cc = {}
        for k, v in pairs(ns.module.db.combo) do cc[k] = v end
        cc.enabled = cfg.combo ~= false
        cc.anchor, cc.side, cc.align = "target", "below", "inner"
        cc.stretch = cfg.comboStretch ~= false
        cc.size = tonumber(cfg.comboSize) or cc.size
        cc.height = tonumber(cfg.comboHeight) or 0
        cc.x, cc.y = tonumber(cfg.comboX) or 0, tonumber(cfg.comboY) or 0
        cc.slant = cfg.slant ~= false
        ns.Combo.Layout(h.combo, cc)
        -- Docked bars stack past the row, wherever it was nudged up or down.
        h.comboReach = cc.enabled and math.max(0, PR.DOCK_GAP + ns.Combo.Height(cc) - cc.y) or 0
    end
    PR.Listen(cfg.enabled == true, showHealth)
    PR.following = cfg.enabled == true and cfg.follow ~= "fixed"
    DUI.Movers.Suspend(PR.KEY, PR.following)
    if PR.following then
        PR.x = nil
        PR.Step(0)
        PR.Wake()
    else
        PR.follow:Hide()
    end
    PR.UpdateShown()
    if h.test then PR.ShowSample()
    elseif h:IsShown() then PR.UpdateAll() end
end

-- Stacks what's docked under the bars and the combo row, swing bars first so
-- they never move when a cast starts and stay readable at a glance. Their own
-- layouts size them first (Units.lua), and the swing bars ask again when their
-- number changes (ST.Place).
function PR.Dock()
    local h = PR.frame
    if not h then return end
    local y = h:GetHeight() + (h.comboReach or 0)
    for _, piece in ipairs({ { "swing", ns.swing }, { "castbar", ns.playerCastbar } }) do
        local kind, f = piece[1], piece[2]
        if f and PR.Docks(kind) then
            f:ClearAllPoints()
            f:SetPoint("TOP", h, "TOP", 0, -(y + PR.DOCK_GAP))
            y = y + PR.DOCK_GAP + f:GetHeight()
        end
    end
    if PR.auras then PR.auras.buffDrop = y - h:GetHeight() end
end

-- Your buffs and debuffs on the display. Their containers are created the
-- first time a row is turned on, so players who leave them off pay nothing
-- (same as ns.PlacePlayerAuras). A row under the bars clears what's docked there.
function PR.PlaceAuras()
    local h, cfg = PR.frame, db()
    local a = cfg and cfg.auras
    if not (h and a) then return end
    if not PR.auras and cfg.enabled and (a.debuffs or a.buffs) then
        PR.auras = ns.Auras.Create(h, "right", "player", a)
    end
    if not PR.auras then return end
    PR.Dock()
    ns.Auras.Apply(PR.auras, a)
    ns.Auras.Place(PR.auras, h, cfg)
end

-- Test mode and the options page: sample values on the live display

PR.SAMPLE = { health = 72, healthValue = 3600, power = 58, powerValue = 1856, combo = 3, heals = 10, absorbs = 8 }

function PR.ShowSample()
    local h, cfg = PR.frame, db()
    if not h or not cfg or not cfg.enabled then return end
    h.test = true
    h:Show()
    PR.PaintHealth()
    local s = PR.SAMPLE
    Style.SetBarRange(h.healthBar, 0, 100)
    Style.SetBarValue(h.healthBar, s.health, true)
    local body = h.body
    if body.heals then
        ns.UF.SetPrediction(body, 100, body.predictHeals and s.heals or 0, body.predictAbsorbs and s.absorbs or 0)
        body.overshield:SetAlpha(0)
    end
    local bar = h.powerBar
    local _, token = UnitPowerType("player")
    ns.UF.PaintPower(bar, token, "player", h.paint)
    bar:SetMinMaxValues(0, 100)
    Style.SetBarValue(bar, s.power, true)
    ns.UF.WriteSampleHealth(h.healthText, cfg.healthText, s.health, s.healthValue, cfg.percentSign, cfg.hideFullHealth)
    ns.UF.WriteSamplePower(h.powerText, cfg.powerFormat, s.power, s.powerValue, cfg.powerPercentSign, nil, token)
    if h.combo then ns.Combo.ShowSample(h.combo, s.combo) end
    if PR.auras then ns.Auras.ShowSample(PR.auras, h, cfg.auras, ns.Test.AURAS) end
end

function PR.HideSample()
    local h = PR.frame
    if not h or not h.test then return end
    h.test = nil
    if h.combo then ns.Combo.HideSample(h.combo) end
    if PR.auras then ns.Auras.HideSample(PR.auras) end
    h:Hide()
    PR.UpdateShown()
end

DUI.RegisterTestPart("personal", "Personal display", 45, function()
    local cfg = db()
    return cfg ~= nil and cfg.enabled == true
end)
