-- The crowd control alert ("Stunned 3.2") as a light, boxless line over the
-- world: icon, name and time, with a thin line underneath that draws out from
-- the middle when the effect lands and drains back as it runs out.
--
-- The game's LossOfControlFrame still does all the real work invisibly: when to
-- show, what to say, its Edit Mode position, its fade and sound. All of that
-- compares values that go secret under the client's restrictions, which only
-- the game's code may do. Ours is a same-size child of it, so it shares its
-- position, scale, alpha and visibility, and only passes the game's text and
-- icon through untouched. The size is fixed because a secret text's width
-- can't be measured, so long names get cut off.
--
-- This is fight information: it shows the instant the game's does, with FAST
-- motion that starts immediately.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion

local Alert = {
    ICON = 36, -- icon size, px
    BAR = 3, -- underline height, px
    LINE_Y = 50, -- underline offset from the top, px
    GAP = 10, -- icon to name
    TIME = 56, -- fixed width for the time; a secret text can't be measured
    SLIDE = 8, -- slide-in distance for the text, px
    POP = 1.28, -- starting scale for the icon pop
    SAMPLE_FILL = 0.6,
    SAMPLE_TIME = "4.2",
    SAMPLE_ICON = 135860, -- LOSS_OF_CONTROL_STUNNED_ICON, the game's Edit Mode sample
    FULL = 2, -- DISPLAY_TYPE_FULL: timed, not a short alert
}
ns.CcAlert = Alert

local function shell(art)
    Style.Shell(art, { noBackground = true, noBevel = true, lean = true })
end

-- The pieces, shared by the alert, its ghost and the test mode sample.
local function parts(f)
    f:EnableMouse(false)
    f.art = CreateFrame("Frame", nil, f)
    shell(f.art)
    f.icon = f.art:CreateTexture(nil, "ARTWORK")
    Style.CropIcon(f.icon)
    f.words = CreateFrame("Frame", nil, f)
    f.words:SetAllPoints(f)
    -- No background behind the text, so it's always outlined.
    f.name = Style.Text(f.words, Style.SIZE.title, "LEFT")
    Style.DressText(f.name, Style.SIZE.title, { outline = "OUTLINE" })
    f.name:SetWordWrap(false)
    f.time = Style.Text(f.words, Style.SIZE.title, "RIGHT")
    Style.DressText(f.time, Style.SIZE.title, { outline = "OUTLINE" })
    f.bar = Style.Bar(f)
    f.bar:SetFillStyle(Enum.StatusBarFillStyle.Center)
    Style.BarBack(f.bar):SetAlpha(0)
end

-- Size and layout. Rerun when the style changes (border width).
function Alert.Layout(f)
    local width = f:GetWidth()
    local icon = Pixel.Snap(f, Alert.ICON)
    f.art:ClearAllPoints()
    f.art:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Pixel.Snap(f, Alert.LINE_Y - Alert.ICON - 6))
    f.art:SetSize(icon, icon)
    shell(f.art)
    local T = Pixel.Px(f.art, Style.BorderPx(f.art))
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f.art, "TOPLEFT", T, -T)
    f.icon:SetPoint("BOTTOMRIGHT", f.art, "BOTTOMRIGHT", -T, T)
    f.time:ClearAllPoints()
    f.time:SetPoint("RIGHT", f.art, "RIGHT", width - icon, 0)
    f.time:SetWidth(Alert.TIME)
    f.name:ClearAllPoints()
    f.name:SetPoint("LEFT", f.art, "RIGHT", Alert.GAP, 0)
    f.name:SetWidth(width - icon - 2 * Alert.GAP - Alert.TIME)
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOP", f, "TOP", 0, -Pixel.Snap(f, Alert.LINE_Y))
    f.bar:SetSize(width, Pixel.Snap(f, Alert.BAR))
end

function Alert.Paint(f)
    Style.PaintAccentBar(f.bar)
    Style.InkText(f.name, "VALUE")
    Style.InkText(f.time, "pop")
end

-- Passes the game's text and icon through every frame while shown. As a child
-- of the game's frame it hides with it, so nothing runs without an alert. Any
-- value may be secret, so they're passed along whole and never inspected.
function Alert.Sync(h)
    local g = Alert.game
    h.icon:SetTexture(g.Icon:GetTexture())
    h.name:SetText(g.AbilityName:GetText())
    local on = g.TimeLeft:IsShown()
    h.time:SetShown(on)
    if on then h.time:SetText(g.TimeLeft.NumberText:GetText()) end
end

-- The client drives the bar from the effect's duration, no Lua per frame.
-- Short alerts (an interrupt lockout notice) have no bar.
function Alert.Bar(h)
    local index = Constants.LossOfControlConsts.LOSS_OF_CONTROL_ACTIVE_INDEX
    local data = C_LossOfControl.GetActiveLossOfControlData(index)
    local duration
    if type(data) == "table" and data.displayType == Alert.FULL then
        duration = C_LossOfControl.GetActiveLossOfControlDuration("player", index)
    end
    local has = type(duration) ~= "nil"
    if has then
        h.bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.RemainingTime)
    end
    h.bar:SetShown(has)
end

-- Landing animation: icon pops, text slides in, line draws out from the middle.
-- Replays when a new effect replaces one still showing.
function Alert.Land(h)
    Motion.Pop(h.art, Alert.POP, Motion.FAST)
    Motion.SlideIn(h.words, -Alert.SLIDE, 0, Motion.FAST)
    Motion.Tween(h.bar, 1, h:GetWidth(), Motion.FAST, function(w) h.bar:SetWidth(w) end)
end

local function shown()
    local h = Alert.frame
    h:RegisterUnitEvent("LOSS_OF_CONTROL_ADDED", "player")
    h:RegisterUnitEvent("LOSS_OF_CONTROL_UPDATE", "player")
    Alert.Sync(h)
    Alert.Bar(h)
    Alert.Land(h)
end

-- The game hides its frame instantly, so a ghost copy fades out in its place
-- (Motion.Ghost). Skipped when the game's own fade already removed it.
local function dressGhost(g)
    parts(g)
    Alert.Paint(g)
    g.time:Hide()
    g.bar:Hide()
    Alert.ghost = g
end

local function gone()
    local h, g = Alert.frame, Alert.game
    h:UnregisterAllEvents()
    Motion.Ghost(g, dressGhost)
    local ghost = Alert.ghost
    if ghost and ghost:IsShown() then
        Alert.Layout(ghost)
        ghost.icon:SetTexture(g.Icon:GetTexture())
        ghost.name:SetText(g.AbilityName:GetText())
    end
end

-- Test mode: the game's frame can't be shown from here (it hides itself when
-- nothing affects you), so a sample sits in its spot.
local function sample()
    local s = Alert.sample
    if s then return s end
    s = CreateFrame("Frame", nil, UIParent)
    s:SetPoint("CENTER", Alert.game, "CENTER", 0, 0)
    s:SetSize(Alert.game:GetSize())
    s:SetFrameStrata(Alert.game:GetFrameStrata())
    parts(s)
    s.icon:SetTexture(Alert.SAMPLE_ICON)
    s.name:SetText(LOSS_OF_CONTROL_DISPLAY_STUN)
    s.time:SetText(Alert.SAMPLE_TIME)
    s.bar:SetMinMaxValues(0, 1)
    s.bar:SetValue(Alert.SAMPLE_FILL)
    Alert.Layout(s)
    Alert.Paint(s)
    Alert.sample = s
    return s
end

local function syncTest()
    if not Alert.game then return end
    local on = DUI.testMode and DUI.TestPartShown("ccalert")
    if on then
        local s = sample()
        s:SetScale(Alert.game:GetScale())
        s:Show()
    elseif Alert.sample then
        Alert.sample:Hide()
    end
end

DUI.On("TestModeChanged", syncTest)
DUI.On("TestPartChanged", function(key) if key == "ccalert" then syncTest() end end)
DUI.RegisterTestPart("ccalert", "CC alert", 87, function() return Alert.game ~= nil end)

Engine.Register({ key = "lossofcontrol", pack = "system", apply = function()
    local g = _G.LossOfControlFrame
    if type(g) ~= "table" or type(g.TimeLeft) ~= "table" or Alert.game then return end
    Alert.game = g
    -- The game's pieces: all invisible, all still working.
    for _, piece in ipairs({ g.blackBg, g.RedLineTop, g.RedLineBottom, g.Icon, g.AbilityName, g.TimeLeft, g.Cooldown }) do
        piece:SetAlpha(0)
    end
    local h = CreateFrame("Frame", nil, g)
    h:SetPoint("CENTER", g, "CENTER", 0, 0)
    h:SetSize(g:GetSize())
    parts(h)
    Alert.frame = h
    Alert.Layout(h)
    Alert.Paint(h)
    h:SetScript("OnUpdate", Alert.Sync)
    h:SetScript("OnEvent", function(_, event)
        Alert.Sync(h)
        Alert.Bar(h)
        if event == "LOSS_OF_CONTROL_ADDED" then Alert.Land(h) end
    end)
    g:HookScript("OnShow", shown)
    g:HookScript("OnHide", gone)
    if g:IsShown() then shown() end
    DUI.On("StyleChanged", function()
        for _, f in pairs({ alert = h, ghost = Alert.ghost, sample = Alert.sample }) do
            Alert.Layout(f)
            Alert.Paint(f)
        end
    end)
end })
