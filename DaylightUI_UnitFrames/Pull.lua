-- The pull timer. A countdown someone in the group starts (the leader drawer's
-- 5/10/15, /countdown, a boss mod) shows as one big number in the middle of
-- the screen. Each second eases in slightly large, settles, and shrinks away
-- as the next arrives. The last three use the accent, and at zero "Pull"
-- lights up and fades. The game's own countdown bar and numbers go to alpha 0
-- while this runs, but its sounds and chat line stay. Other game timers, like
-- a battleground start, are left alone.
--
-- Under chat lockdown (possibly in instances) the countdown seconds are
-- secret and can't be timed, so the game's own display shows instead. A
-- countdown we started ourselves is already known (Leader.sent).

local _, ns = ...
local DUI = DaylightUI
local Style, Motion = DUI.Style, DUI.Motion
local L = DUI.L

local Pull = {}
ns.Pull = Pull

Pull.SIZE = 64               -- display art, not window text
Pull.LABEL_GAP = 4
Pull.POP = 1.25              -- each second starts this big
Pull.SHRINK = 0.85           -- and leaves this small
Pull.IN = Motion.FAST        -- how long a second takes to settle
Pull.OUT = 0.15              -- the end of a second it spends leaving
Pull.ACCENT_FROM = 3         -- the last seconds in the accent
Pull.OWN_WINDOW = 2          -- a countdown this soon after one we sent is ours
Pull.MAX = 3600              -- the game's maximum

local frame, host, num, label, driver
local endAt, shownN

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function ease(p)
    if p <= 0 then return 0 end
    if p >= 1 then return 1 end
    return 1 - (1 - p) ^ 3
end

-- The game's countdown

-- The game's timer frame running a player countdown (TimerTracker's
-- StartTimerBar), or nil.
local function gameTimer()
    local tt = _G.TimerTracker
    local kind = Enum.StartTimerType and Enum.StartTimerType.PlayerCountdown
    if type(tt) ~= "table" or type(tt.timerList) ~= "table" or kind == nil then return nil end
    for _, t in pairs(tt.timerList) do
        if t.type == kind and not t.isFree then return t end
    end
end

local veiled                 -- the game's timer frame set to alpha 0

local function unveil()
    if veiled then veiled:SetAlpha(1) end
    veiled = nil
end

local function veil()
    local t = gameTimer()
    if t == veiled then return end
    unveil()
    if t then
        t:SetAlpha(0)
        veiled = t
    end
end

-- Ours

local function paintNumber(n)
    shownN = n
    if n >= 60 then
        num:SetFormattedText("%d:%02d", math.floor(n / 60), n % 60)
    else
        num:SetText(n)
    end
    if n <= Pull.ACCENT_FROM then Style.InkText(num, "pop") else Style.InkText(num, "VALUE") end
end

local function stop()
    driver:SetScript("OnUpdate", nil)
    endAt, shownN = nil, nil
end

-- Fade out, then hide, and give the game's frame its alpha back.
local function leave(dur)
    stop()
    unveil()
    if not frame:IsShown() then return end
    Motion.Fade(frame, frame:GetAlpha(), 0, dur)
    C_Timer.After(Motion.On() and dur or 0, function()
        if not endAt then frame:Hide() end
    end)
end

-- Zero: "Pull" in the accent, slightly large, then slowly away.
local function pulled()
    stop()
    unveil()
    num:SetText(L["Pull"])
    Style.InkText(num, "pop")
    label:SetAlpha(0)
    host:SetScale(1)
    Motion.Bump(host, Pull.POP)
    frame:SetAlpha(1)
    C_Timer.After(1, function()
        if endAt then return end
        Motion.Fade(frame, 1, 0, Motion.SLOW)
        C_Timer.After(Motion.On() and Motion.SLOW or 0, function()
            if not endAt then frame:Hide() end
        end)
    end)
end

-- One frame of a second: in (large to settled), held, out (smaller, fading).
local function tick()
    local left = endAt - GetTime()
    if left <= 0 then return pulled() end
    local n = math.ceil(left)
    if n ~= shownN then paintNumber(n) end
    -- The game sometimes creates its timer frame (or reuses one) a moment
    -- after the event, so keep it veiled.
    veil()
    if not Motion.On() then
        host:SetScale(1)
        host:SetAlpha(1)
        return
    end
    local into = n - left            -- 0 as the second starts, 1 as it ends
    local scale, alpha = 1, 1
    if into < Pull.IN then
        local e = ease(into / Pull.IN)
        scale, alpha = Pull.POP - (Pull.POP - 1) * e, e
    elseif into > 1 - Pull.OUT then
        local e = ease((into - (1 - Pull.OUT)) / Pull.OUT)
        scale, alpha = 1 - (1 - Pull.SHRINK) * e, 1 - e
    end
    host:SetScale(scale)
    host:SetAlpha(alpha)
end

function Pull.Start(seconds)
    if not frame or not Pull.on then return end
    if type(seconds) ~= "number" or seconds <= 0 then return leave(Motion.FAST) end
    endAt = GetTime() + math.min(seconds, Pull.MAX)
    shownN = nil
    label:SetText(string.upper(L["Pull"]))
    Style.InkText(label, "LABEL")
    label:SetAlpha(1)
    frame:Show()
    Motion.Fade(frame, frame:GetAlpha(), 1, Motion.FAST)
    tick()
    driver:SetScript("OnUpdate", tick)
end

function Pull.Running() return endAt ~= nil end

-- START_PLAYER_COUNTDOWN (initiatedBy, timeRemaining, totalTime, ...).
-- Plain seconds run this timer. Secret ones only do when we just sent the
-- countdown ourselves, otherwise the game's display shows.
function Pull.OnCountdown(_, seconds)
    if not Pull.on then return end
    if isSecret(seconds) or type(seconds) ~= "number" then
        local sent = ns.Leader and ns.Leader.sent
        if sent and GetTime() - sent.at <= Pull.OWN_WINDOW then
            seconds = sent.seconds
        else
            return leave(Motion.FAST)
        end
    end
    Pull.Start(seconds)
end

local function build()
    frame = CreateFrame("Frame", "DaylightUIPullTimer", UIParent)
    frame:SetSize(Pull.SIZE * 3, Pull.SIZE * 1.6)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    host = CreateFrame("Frame", nil, frame)
    host:SetSize(Pull.SIZE * 3, Pull.SIZE)
    host:SetPoint("CENTER", frame, "CENTER", 0, Pull.SIZE * 0.15)
    num = Style.Text(host, Pull.SIZE, "CENTER")
    num:SetPoint("CENTER", host, "CENTER", 0, 0)
    label = Style.Text(frame, Style.SIZE.small, "CENTER")
    label:SetPoint("TOP", host, "BOTTOM", 0, -Pull.LABEL_GAP)
    driver = CreateFrame("Frame", nil, frame)
    DUI.Movers.Register(frame, "unitframes.pull", "Pull Timer", { "CENTER", nil, "CENTER", 0, 180 })
    Pull.frame, Pull.num = frame, num
end

function Pull.Apply(db)
    Pull.on = db and db.pull and db.pull.enabled == true
    if not frame then build() end
    if not Pull.on and endAt then leave(0) end
end

DUI.RegisterEvent("START_PLAYER_COUNTDOWN", function(_, ...) Pull.OnCountdown(...) end)
DUI.RegisterEvent("CANCEL_PLAYER_COUNTDOWN", function()
    if endAt then leave(Motion.FAST) end
end)
-- Another game timer (a battleground start) may reuse the veiled frame, so
-- give it its alpha back first.
DUI.RegisterEvent("START_TIMER", function() if not endAt then unveil() end end)
DUI.On("StyleChanged", function()
    if shownN then paintNumber(shownN) end
    if label then Style.InkText(label, "LABEL") end
end)
