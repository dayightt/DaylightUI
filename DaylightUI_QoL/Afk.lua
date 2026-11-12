-- AFK screen: when you go AFK the world dims, the UI fades out and your character
-- stands beside a card with your details, time away, a rotating fun fact
-- (AfkFacts.lua) and the clock. Moving, a key or a click brings the UI back.
--
-- Never shown in combat or under the client's restrictions, and entering combat
-- (PLAYER_REGEN_DISABLED, just before lockdown) restores everything at once.
-- The UI is hidden only through UIParent's alpha, which is allowed in combat and
-- touches nothing protected. This screen is a UIParent child that ignores its alpha.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Afk = {}
ns.Afk = Afk
ns.features[#ns.features + 1] = Afk

Afk.STRATA = "FULLSCREEN_DIALOG"
Afk.DIM_TOP, Afk.DIM_BOTTOM = 0.35, 0.75     -- the world's dimming, top to bottom
Afk.PANEL_W = 340
Afk.PAD = 18
Afk.CUT = 26                                 -- the card's angled right end
Afk.SLIDE = 16                               -- px the card glides in from
Afk.SWAY, Afk.SWAY_PERIOD = 0.28, 24         -- the model turns this far each way, once in this many seconds
Afk.TURN = 0.3                               -- and leans this far toward the card (guess; tune in game)
Afk.MODEL_WAIT = 2                           -- seconds to wait for the model before showing it anyway
Afk.GLOW = DUI.MEDIA .. "char-glow.png"
Afk.GLOW_ALPHA = 0.22
Afk.HINT = L["Move or press any key to come back"]

-- Asked when a fight, a queue or a cinematic needs the player: the screen
-- steps aside (the AFK flag stays).
Afk.LEAVE_EVENTS = {
    "PLAYER_REGEN_DISABLED", "LFG_PROPOSAL_SHOW", "READY_CHECK", "PARTY_INVITE_REQUEST",
    "DUEL_REQUESTED", "RESURRECT_REQUEST", "CONFIRM_SUMMON", "UPDATE_BATTLEFIELD_STATUS",
    "CINEMATIC_START", "PLAY_MOVIE", "LOADING_SCREEN_ENABLED",
}

local mod, screen, events
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion
local Facts = ns.AfkFacts

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function plain(v) return v ~= nil and not secret(v) end

local function wanted() return mod and mod.db and mod.db.afkScreen ~= false end

-- Away now: a plain true from the client (it's secret in chat lockdown).
function Afk.IsAway()
    local v = call(UnitIsAFK, "player")
    return plain(v) and v == true
end

-- Whether the screen may come up at all right now.
function Afk.CanShow()
    if InCombatLockdown() or DUI.Restricted() then return false end
    if UnitAffectingCombat and UnitAffectingCombat("player") == true then return false end
    return UIParent:IsShown() == true
end

-- ---------------------------------------------------------------------
-- What the card says
-- ---------------------------------------------------------------------

-- 4:07 under an hour, 1:04:07 after.
function Afk.Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

-- 3d 4h 12m: the biggest two parts.
function Afk.Played(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local d, h, m = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
    if d > 0 then return string.format(L["%dd %dh"], d, h) end
    if h > 0 then return string.format(L["%dh %dm"], h, m) end
    return string.format(L["%dm"], m)
end

-- The time of day, the way the minimap clock shows it (its 24-hour and
-- server-time choices when the info panel is on; else local, 24-hour).
function Afk.TimeOfDay()
    local twentyFour, server = true, false
    local cfg = DUI:Get("InfoPanel", "map.clock")
    if type(cfg) == "table" then
        twentyFour, server = cfg.twentyFour ~= false, cfg.useServer == true
    end
    local h, m
    if server and type(GetGameTime) == "function" then h, m = GetGameTime()
    else h, m = tonumber(date("%H")), tonumber(date("%M")) end
    if type(h) ~= "number" or type(m) ~= "number" then return "" end
    if twentyFour then return string.format("%02d:%02d", h, m) end
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d %s", h12, m, h >= 12 and (TIMEMANAGER_PM or "PM") or (TIMEMANAGER_AM or "AM"))
end

local function atCap()
    local capped = call(IsPlayerAtEffectiveMaxLevel)
    if capped ~= nil then return capped == true end
    local max = call(GetMaxPlayerLevel)
    local level = UnitLevel("player")
    return type(max) == "number" and type(level) == "number" and level >= max
end

-- Played time, only if the game already reported it this session (asking for
-- it prints to chat). Counted forward from when it arrived.
function Afk.OnTimePlayed(_, total, thisLevel)
    if type(total) ~= "number" or secret(total) then return end
    Afk.played = { total = total, at = GetTime() }
    local lvl = UnitLevel("player")
    if type(thisLevel) == "number" and not secret(thisLevel) and plain(lvl) then
        Afk.played.level, Afk.played.levelAt = thisLevel, lvl
    end
end

-- The card's lines: { name, nameColor, sub, guild, rows = { { label, value } } }.
function Afk.Read()
    local info = {}
    info.name = DUI.UnitName("player", "character") or ""
    local className, token = UnitClass("player")
    info.nameColor = { Style.ClassTextColor(token) }
    local level, race = UnitLevel("player"), call(UnitRace, "player")
    local sub = {}
    if plain(level) and level > 0 then sub[#sub + 1] = string.format(L["Level %d"], level) end
    if plain(race) then sub[#sub + 1] = race end
    -- The class in its color; the rest is the line's warm tan.
    if plain(className) then
        local c = info.nameColor
        sub[#sub + 1] = (c[1] and DUI.Win.Parts.Hex(c) or "") .. className .. (c[1] and "|r" or "")
    end
    info.sub = table.concat(sub, " ")
    local guild = call(GetGuildInfo, "player")
    info.guild = plain(guild) and guild ~= "" and ("<" .. guild .. ">") or nil
    local rows = {}
    local zone, area = call(GetRealZoneText) or call(GetZoneText), call(GetSubZoneText)
    if plain(zone) and zone ~= "" then
        if plain(area) and area ~= "" and area ~= zone then zone = area .. ", " .. zone end
        rows[#rows + 1] = { L["Zone"], zone }
    end
    if not atCap() then
        local cur, max = call(UnitXP, "player"), call(UnitXPMax, "player")
        if type(cur) == "number" and type(max) == "number" and not secret(cur) and not secret(max) and max > 0 then
            rows[#rows + 1] = { L["Experience"], string.format("%d%%", math.floor(cur / max * 100)) }
            local rested = call(GetXPExhaustion)
            if type(rested) == "number" and not secret(rested) and rested > 0 then
                rows[#rows + 1] = { L["Rested"], string.format(L["%d%% of a level"], math.floor(rested / max * 100 + 0.5)) }
            end
        end
    end
    local played = Afk.played
    if played then rows[#rows + 1] = { L["Played"], Afk.Played(played.total + GetTime() - played.at) } end
    info.rows = rows
    return info
end

-- ---------------------------------------------------------------------
-- The screen
-- ---------------------------------------------------------------------

local function row(i)
    local r = screen.rows[i]
    if r then return r end
    r = { label = Style.Text(screen.panel, Style.SIZE.small, "LEFT"), value = Style.Text(screen.panel, Style.SIZE.body, "RIGHT") }
    Style.InkText(r.label, "LABEL")
    Style.InkText(r.value, "VALUE")
    r.value:SetWordWrap(false)
    screen.rows[i] = r
    return r
end

local function textHeight(fs, fallback)
    local ok, h = pcall(fs.GetStringHeight, fs)
    if ok and type(h) == "number" and not secret(h) and h > 0 then return h end
    return fallback
end

-- Fills the card and stacks it, top down.
function Afk.Fill()
    local p = screen.panel
    local info = Afk.Read()
    local left, right = Afk.PAD, Afk.PAD + Afk.CUT
    local width = Afk.PANEL_W - left - right
    local y = Afk.PAD
    local function place(fs, size, gap)
        y = y + (gap or 0)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", p, "TOPLEFT", left, -y)
        fs:SetWidth(width)
        fs:Show()
        y = y + textHeight(fs, size)
    end
    Style.PaintAccentText(p.away, L["AWAY"])
    place(p.away, 12)
    p.awayTime:ClearAllPoints()
    p.awayTime:SetPoint("TOPRIGHT", p, "TOPRIGHT", -right, -Afk.PAD)
    p.name:SetText(info.name)
    p.name:SetTextColor(info.nameColor[1] or 1, info.nameColor[2] or 1, info.nameColor[3] or 1)
    place(p.name, 24, 8)
    p.sub:SetText(info.sub)
    place(p.sub, 13, 2)
    if info.guild then
        p.guild:SetText(info.guild)
        place(p.guild, 13, 2)
    else
        p.guild:Hide()
    end
    y = y + 12
    p.line:ClearAllPoints()
    p.line:SetPoint("TOPLEFT", p, "TOPLEFT", left, -y)
    p.line:SetSize(width, Pixel.Px(p, 1))
    Style.PaintAccent(p.line, 0.7)
    y = y + 10
    for i, r in ipairs(info.rows) do
        local fs = row(i)
        fs.label:SetText(r[1])
        fs.value:SetText(r[2])
        y = y + (i > 1 and 6 or 0)
        fs.label:ClearAllPoints()
        fs.label:SetPoint("TOPLEFT", p, "TOPLEFT", left, -y)
        fs.value:ClearAllPoints()
        fs.value:SetPoint("TOPRIGHT", p, "TOPRIGHT", -right, -y)
        fs.value:SetWidth(width - 90)
        fs.label:Show()
        fs.value:Show()
        y = y + math.max(textHeight(fs.label, 12), textHeight(fs.value, 13))
    end
    for i = #info.rows + 1, #screen.rows do
        screen.rows[i].label:Hide()
        screen.rows[i].value:Hide()
    end
    -- The fun fact: room for a heading and two lines, kept whatever it says
    -- so the card never jumps as facts turn over.
    local f = p.fact
    Facts.Reset()
    f.key = nil
    Motion.Tween("qol:afkfact", 1, 1, 0, function(a) f:SetAlpha(a) end)   -- a fade cut short last time
    Style.PaintAccentText(f.head, L["Quests"])
    f.line:SetText("X")
    f.lineH = textHeight(f.line, 13)
    local room = textHeight(f.head, 11) + 3 + f.lineH * 2 + 2
    if Afk.ShowFact() then
        y = y + 16
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", p, "TOPLEFT", left, -y)
        f:SetSize(width, room)
        f:Show()
        y = y + room
    else
        f:Hide()
    end
    place(p.clock, 34, f:IsShown() and 8 or 16)
    p:SetHeight(math.floor(y + Afk.PAD + 0.5))
    Style.Slant(p, "right", Pixel.Snap(p, Afk.CUT))
    Afk.Tick(true)
end

-- Writes the next fact into the card. false when none fits.
function Afk.ShowFact()
    local f = screen.panel.fact
    local key, head, line = Facts.Next()
    if not key then return false end
    f.key = key
    Style.PaintAccentText(f.head, string.upper(head))
    f.line:SetText(line)
    f.since = 0
    return true
end

-- Every Facts.EVERY seconds: a soft fade over to the next fact.
function Afk.TurnFact()
    local f = screen.panel.fact
    if not (f.key and f:IsShown()) then return end
    f.since = (f.since or 0) + 1
    if f.since < Facts.EVERY then return end
    f.since = 0
    Motion.Tween("qol:afkfact", 1, 0, Motion.NORMAL, function(a) f:SetAlpha(a) end, function()
        Afk.ShowFact()
        Motion.Tween("qol:afkfact", 0, 1, Motion.SLOW, function(a) f:SetAlpha(a) end)
    end)
end

-- The away time and the clock, written only when they change.
function Afk.Tick(force)
    local p = screen and screen.panel
    if not p then return end
    local away = Afk.Clock(GetTime() - (Afk.since or GetTime()))
    if force or away ~= p.awayTime.shown then
        p.awayTime.shown = away
        p.awayTime:SetText(away)
    end
    local now = Afk.TimeOfDay()
    if force or now ~= p.clock.shown then
        p.clock.shown = now
        p.clock:SetText(now)
    end
end

local function actor()
    return screen and DUI.PlayerActor(screen.scene) or nil
end

-- Sizes everything to the screen (UI scale can change while it's down).
function Afk.Layout()
    local H = UIParent:GetHeight() or 768
    local m = screen.model
    m:ClearAllPoints()
    m:SetSize(H * 0.42, H * 0.72)
    m:SetPoint("CENTER", screen, "CENTER", -H * 0.18, -H * 0.04)
    m.glow:ClearAllPoints()
    m.glow:SetPoint("CENTER", m, "CENTER", 0, H * 0.03)
    m.glow:SetSize(H * 0.42, H * 0.68)
    m.shadow:ClearAllPoints()
    m.shadow:SetPoint("CENTER", m, "BOTTOM", 0, H * 0.72 * 0.12)
    m.shadow:SetSize(H * 0.42 * 0.5, 26)
    Afk.panelX = H * 0.02
    Afk.PlacePanel(Afk.p or 1)
end

function Afk.PlacePanel(p)
    local panel = screen.panel
    panel:ClearAllPoints()
    panel:SetPoint("LEFT", screen, "CENTER", (Afk.panelX or 0) + (1 - p) * Afk.SLIDE, 0)
end

local function build()
    screen = CreateFrame("Frame", "DaylightUIAfkScreen", UIParent)
    screen:SetAllPoints(UIParent)
    screen:SetFrameStrata(Afk.STRATA)
    screen:SetIgnoreParentAlpha(true)   -- stays while UIParent fades away
    screen:EnableMouse(true)
    screen:EnableKeyboard(true)
    screen:Hide()
    screen.rows = {}

    local dim = screen:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(screen)
    dim:SetColorTexture(0, 0, 0, 1)
    if dim.SetGradient and CreateColor then
        dim:SetGradient("VERTICAL", CreateColor(0, 0, 0, Afk.DIM_BOTTOM), CreateColor(0, 0, 0, Afk.DIM_TOP))
    else
        dim:SetVertexColor(0, 0, 0, (Afk.DIM_TOP + Afk.DIM_BOTTOM) / 2)
    end
    screen.dim = dim

    -- The character, hidden until the game has loaded it.
    local m = CreateFrame("Frame", nil, screen)
    m.glow = m:CreateTexture(nil, "BACKGROUND")
    m.glow:SetTexture(Afk.GLOW)
    m.shadow = m:CreateTexture(nil, "BORDER")
    m.shadow:SetTexture(Afk.GLOW)
    m.shadow:SetVertexColor(0, 0, 0, 0.6)
    screen.model = m
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, m, "ModelSceneMixinTemplate")
    if ok and type(scene) == "table" then
        scene:SetAllPoints(m)
        scene:EnableMouse(false)
        screen.scene = scene
    end

    -- The card.
    local p = CreateFrame("Frame", nil, screen)
    p:SetWidth(Afk.PANEL_W)
    p:SetFrameLevel(m:GetFrameLevel() + 5)
    Style.Shell(p)
    Style.Slant(p, nil, 0)
    p.away = Style.Text(p, Style.SIZE.small, "LEFT")
    p.away:SetText(L["AWAY"])
    p.awayTime = Style.Text(p, Style.SIZE.small, "RIGHT")
    Style.InkText(p.awayTime, "TEXT")
    p.name = Style.Text(p, 24, "LEFT")
    p.name:SetWordWrap(false)
    p.sub = Style.Text(p, Style.SIZE.body, "LEFT")
    Style.InkText(p.sub, "LABEL")
    p.guild = Style.Text(p, Style.SIZE.body, "LEFT")
    Style.InkText(p.guild, "GOOD")
    p.line = p:CreateTexture(nil, "ARTWORK")
    p.line:SetColorTexture(1, 1, 1, 1)
    local f = CreateFrame("Frame", nil, p)
    f.head = Style.Text(f, Style.SIZE.small, "LEFT")
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.line = Style.Text(f, Style.SIZE.body, "LEFT")
    f.line:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 0, -3)
    f.line:SetPoint("TOPRIGHT", f.head, "BOTTOMRIGHT", 0, -3)
    f.line:SetJustifyV("TOP")
    f.line:SetWordWrap(true)
    if f.line.SetMaxLines then f.line:SetMaxLines(2) end
    Style.InkText(f.line, "TEXT")
    p.fact = f
    p.clock = Style.Text(p, 34, "LEFT")
    Style.InkText(p.clock, "VALUE")
    screen.panel = p

    screen.hint = Style.Text(screen, Style.SIZE.small, "CENTER")
    screen.hint:SetPoint("BOTTOM", screen, "BOTTOM", 0, 48)
    Style.InkText(screen.hint, "LABEL")
    screen.hint:SetText(Afk.HINT)

    screen:SetScript("OnKeyDown", function(self, key)
        -- The key goes on to the game (W walks, and that ends AFK), except
        -- Escape: it only closes this screen, not open the game menu too.
        -- A screenshot keeps the screen up.
        if not InCombatLockdown() and self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        end
        if key ~= "PRINTSCREEN" then Afk.Leave() end
    end)
    screen:SetScript("OnMouseDown", function() Afk.Leave() end)
    screen:SetScript("OnUpdate", function(_, elapsed) Afk.OnUpdate(elapsed or 0) end)
end

-- Every frame while up: the model's wait and sway, the clock once a second.
function Afk.OnUpdate(elapsed)
    if InCombatLockdown() then return Afk.Leave(true) end
    Afk.t = (Afk.t or 0) + elapsed
    Afk.tick = (Afk.tick or 0) + elapsed
    if Afk.tick >= 1 then
        Afk.tick = 0
        Afk.Tick()
        Afk.TurnFact()
    end
    local scene = screen.scene
    if not scene then return end
    local a = actor()
    if Afk.waiting then
        Afk.waited = Afk.waited + elapsed
        if (a and a.IsLoaded and a:IsLoaded()) or Afk.waited >= Afk.MODEL_WAIT then
            Afk.waiting = false
            Afk.yaw = a and a.GetYaw and a:GetYaw() or 0
            Afk.shownAt = Afk.t
        end
        return
    end
    if Afk.shownAt then
        -- The model fades in by hand (an alpha animation left the character
        -- window's model at 0).
        local e = math.min(1, (Afk.t - Afk.shownAt) / Motion.SLOW)
        scene:SetAlpha(Motion.On() and e or 1)
        if e >= 1 then Afk.shownAt = nil end
    end
    if a and a.SetYaw and Motion.On() then
        a:SetYaw((Afk.yaw or 0) + Afk.TURN + Afk.SWAY * math.sin(Afk.t * 2 * math.pi / Afk.SWAY_PERIOD))
    end
end

-- p: 0 = the UI as normal, 1 = the AFK screen fully up.
local function apply(p)
    Afk.p = p
    screen:SetAlpha(p)
    UIParent:SetAlpha(1 - p)
    -- The minimap's dots ignore the alpha: the map hides once the UI is gone.
    DUI.Fade.MapAway("afk", p >= 1)
    Afk.PlacePanel(p)
end

-- Brings the screen up. preview: shown without the AFK flag (/dui afk).
function Afk.Show(preview)
    if not Afk.CanShow() then return false end
    if not screen then build() end
    Afk.preview = preview == true
    Afk.since = GetTime()
    Afk.t, Afk.tick = 0, 0
    Afk.Layout()
    Afk.Fill()
    Style.PaintAccent(screen.model.glow, Afk.GLOW_ALPHA, "VERTICAL")
    local scene = screen.scene
    if scene and type(ModelSceneUtil) == "table" and type(ModelSceneUtil.SetUpCharacterSheetScene) == "function" then
        scene:SetAlpha(0)
        pcall(ModelSceneUtil.SetUpCharacterSheetScene, scene)
        Afk.waiting, Afk.waited = true, 0
    else
        Afk.waiting = false
    end
    local from = screen:IsShown() and Afk.p or 0
    screen:Show()
    Afk.up = true
    Motion.Tween("qol:afk", from, 1, Motion.SLOW, apply)
    return true
end

-- Puts the UI back: a glide, or at once (a fight starting).
function Afk.Leave(now)
    if not (screen and Afk.up) then return end
    Afk.up, Afk.preview = false, false
    local done = function()
        if Afk.up then return end
        screen:Hide()
        UIParent:SetAlpha(1)
    end
    if now or InCombatLockdown() then
        Motion.Tween("qol:afk", Afk.p or 0, 0, 0, apply, done)
    else
        Motion.Tween("qol:afk", Afk.p or 1, 0, Motion.NORMAL, apply, done)
    end
end

function Afk.Shown() return Afk.up == true end

-- PLAYER_FLAGS_CHANGED fires for any flag (PvP, DND...): the screen comes
-- up only as you go away, and goes as you come back.
local wasAway = false
function Afk.OnFlags(_, unit)
    if unit ~= nil and unit ~= "player" then return end
    local away = Afk.IsAway()
    if away and not wasAway then
        wasAway = true
        if wanted() then Afk.Show(false) end
    elseif not away and wasAway then
        wasAway = false
        if not Afk.preview then Afk.Leave() end
    end
end

function Afk.OnLeaveEvent(event, ...)
    if not Afk.up then return end
    if event == "UPDATE_BATTLEFIELD_STATUS" then
        -- Only a battleground that's ready to enter needs you.
        local index = ...
        local status = type(index) == "number" and call(GetBattlefieldStatus, index)
        if status ~= "confirm" then return end
    end
    Afk.Leave(event == "PLAYER_REGEN_DISABLED" or event == "LOADING_SCREEN_ENABLED")
end

function Afk.Preview()
    if Afk.up then return Afk.Leave() end
    if not Afk.Show(true) then DUI.Print(L["The AFK screen can't show in combat, a boss fight, a keystone or a PvP match."]) end
end

function Afk.Enable(m)
    mod = m
    if events then return end
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_FLAGS_CHANGED" then return Afk.OnFlags(event, ...) end
        if event == "TIME_PLAYED_MSG" then return Afk.OnTimePlayed(event, ...) end
        if event == "ADDON_RESTRICTION_STATE_CHANGED" then
            if Afk.up and DUI.Restricted() then Afk.Leave(true) end
            return
        end
        Afk.OnLeaveEvent(event, ...)
    end)
    local function listen(e) pcall(events.RegisterEvent, events, e) end
    listen("PLAYER_FLAGS_CHANGED")
    listen("TIME_PLAYED_MSG")
    listen("ADDON_RESTRICTION_STATE_CHANGED")
    for _, e in ipairs(Afk.LEAVE_EVENTS) do listen(e) end
    wasAway = Afk.IsAway()
    Facts.Begin()
    DUI.RegisterCommand("afk", Afk.Preview, L["/dui afk - preview the AFK screen (any key closes it)"])
end

function Afk.Refresh(m)
    mod = m
    if not wanted() and Afk.up and not Afk.preview then Afk.Leave() end
end
