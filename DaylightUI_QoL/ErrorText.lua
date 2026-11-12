-- Restyled error text in the middle of the screen: errors in soft red, other
-- lines soft white, easing in and out. A repeated line glows briefly and holds
-- longer instead of stacking. (No size pulse: animated text scaling jumps.)
-- Anchored to UIErrorsFrame so its Edit Mode / unlock handle still moves it.
--
-- No hook. Every LE_GAME_ERR_* type is claimed as a fallback through
-- DUI.ClaimMessageType, so quieted errors (Errors.lua) and quest progress keep
-- their own handling. The rest is drawn here with the sound the game would have
-- played. Lines added another way (SYSMSG, other addons) stay the game's.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local ErrorText = {
    OWNER = "errortext",
    W = 512,
    ROW_H = 22,
    ROWS = 3,
    HOLD = 2,     -- seconds a line stays (the game's displayDuration)
    RISE = 4,     -- px a new line rises in
    GLOW = 0.6,   -- how far toward white the same line again lights up
    GAP = 0.4,    -- the same line's sound at most this often
    DEFAULT_Y = -122,   -- the game's frame spot (UIErrorsFrame.xml), when it isn't there
    TEST_PART = "errortext",
}
ns.ErrorText = ErrorText
ns.features[#ns.features + 1] = ErrorText

local mod, holder, listening, claimed, sampling
local rows = {}
ErrorText.rows = rows

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.errorText == true end

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- Every message type the client has, read once from its LE_GAME_ERR_* names.
local types
local function allTypes()
    if types then return types end
    types = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "number" and string.sub(k, 1, 12) == "LE_GAME_ERR_" then
            types[#types + 1] = v
        end
    end
    return types
end

-- The row's color, `v` of the way from its ink to white.
local function tint(r, v)
    r.glow = v
    local c, w = r.ink, Style.INK.VALUE
    r.text:SetTextColor(c[1] + (w[1] - c[1]) * v, c[2] + (w[2] - c[2]) * v, c[3] + (w[3] - c[3]) * v, 1)
end

-- Up from wherever it is now and back, so pressing again and again never
-- jumps. The row itself is the tween's key.
local function lightUp(r)
    Motion.Tween(r, r.glow, ErrorText.GLOW, Motion.FAST, r.tint, function()
        Motion.Tween(r, ErrorText.GLOW, 0, Motion.NORMAL, r.tint)
    end)
end

local function newRow(i)
    local r = CreateFrame("Frame", nil, holder)
    r:SetSize(ErrorText.W, ErrorText.ROW_H)
    r:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * ErrorText.ROW_H)
    r:EnableMouse(false)
    r:Hide()
    r.text = Style.Text(r, Style.SIZE.head, "CENTER")
    r.text:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.text:SetWordWrap(false)
    r.id = 0
    r.glow = 0
    r.tint = function(v) tint(r, v) end
    return r
end

local function build()
    if holder then return holder end
    holder = CreateFrame("Frame", "DaylightUIErrorText", UIParent)
    DUI.Movers.FollowScale(holder)
    holder:SetSize(ErrorText.W, ErrorText.ROW_H * ErrorText.ROWS)
    holder:SetFrameStrata("DIALOG")
    holder:EnableMouse(false)
    local game = _G.UIErrorsFrame
    if type(game) == "table" and type(game.GetObjectType) == "function" then
        holder:SetPoint("TOP", game, "TOP", 0, 0)
    else
        holder:SetPoint("TOP", UIParent, "TOP", 0, ErrorText.DEFAULT_Y)
    end
    for i = 1, ErrorText.ROWS do rows[i] = newRow(i) end
    return holder
end

-- Which row a line goes in: the one already showing it, else a free one
-- (the top first), else the oldest. A secret line is never compared.
local function rowFor(key)
    local free, oldest
    for _, r in ipairs(rows) do
        if r:IsShown() and not r.leaving and key ~= nil and r.key == key then return r end
        if not free and (not r:IsShown() or r.leaving) then free = r end
        if r:IsShown() and (not oldest or r.since < oldest.since) then oldest = r end
    end
    return free or oldest
end

local function leave(r)
    r.leaveAt = nil
    if not r:IsShown() then return end
    r.leaving = true
    r.id = r.id + 1
    local id = r.id
    Motion.Fade(r, r:GetAlpha(), 0, Motion.SLOW)
    C_Timer.After(Motion.SLOW, function()
        if r.id ~= id then return end
        r.leaving = nil
        r:Hide()
    end)
end

-- Each row keeps the time it leaves (`leaveAt`); one timer looks at them
-- all and waits for the soonest, so a line repeated many times makes no
-- new timers.
local checking = false
local function checkLeaving()
    checking = false
    local now, soonest = GetTime(), nil
    for _, r in ipairs(rows) do
        if r.leaveAt then
            if r.leaveAt <= now then
                r.leaveAt = nil
                leave(r)
            elseif not soonest or r.leaveAt < soonest then
                soonest = r.leaveAt
            end
        end
    end
    if soonest then
        checking = true
        C_Timer.After(soonest - now, checkLeaving)
    end
end

local function hold(r)
    r.id = r.id + 1
    r.leaveAt = not r.held and GetTime() + ErrorText.HOLD or nil
    if r.leaveAt and not checking then
        checking = true
        C_Timer.After(ErrorText.HOLD, checkLeaving)
    end
end

-- Shows one line. kind is "error" or "info", text may be secret. With `held`
-- it stays until released (the sample). Returns whether it repeated the last
-- line, so no new sound plays within GAP.
function ErrorText.Show(kind, text, held)
    build()
    local key = not secret(text) and text or nil
    local r = rowFor(key)
    local fresh = not r:IsShown() or r.leaving
    local again = not fresh and key ~= nil and r.key == key
    r.key, r.held, r.leaving = key, held, nil
    r.since = GetTime()
    r.text:SetText(text)
    r.ink = Style.INK[kind == "error" and "BAD" or "TEXT"]
    if again then
        lightUp(r)
    else
        Motion.Tween(r, 0, 0, 0)   -- a line taking over a row starts unlit
        tint(r, 0)
    end
    if fresh then
        Motion.Fade(r, 1, 1, 0)   -- stops a fade-out still playing
        r:Show()
        Motion.Appear(r, ErrorText.RISE)
    end
    hold(r)
    local quiet = again and r.soundAt and r.since - r.soundAt < ErrorText.GAP
    if not quiet then r.soundAt = r.since end
    return r, quiet
end

-- Every line goes (switched off, or the sample ends).
function ErrorText.Clear()
    for _, r in ipairs(rows) do
        r.held = nil
        leave(r)
    end
end

local function onMessage(kind)
    return function(_, messageType, message)
        if secret(messageType) or type(messageType) ~= "number" then return end
        if not enabled() or DUI.GameMessagesSuppressed() then return end
        if DUI.MessageTypeOwner(messageType) ~= ErrorText.OWNER then return end
        if not secret(message) and type(message) ~= "string" then return end
        local quiet
        DUI.SafeCall(function() quiet = select(2, ErrorText.Show(kind, message)) end)
        if not quiet then DUI.PlayGameMessageSound(messageType) end
    end
end

-- A red line of ours (DUI.ShowError): drawn here while this is on.
local function ours(text)
    if not enabled() or (not secret(text) and type(text) ~= "string") then return false end
    DUI.SafeCall(ErrorText.Show, "error", text)
    return true
end

-- The sample, in the game's own words: shown while test mode or unlock mode wants it.
local function sampleWanted()
    if not enabled() then return false end
    if DUI.testMode and DUI.TestPartShown(ErrorText.TEST_PART) then return true end
    return DUI.Movers ~= nil and DUI.Movers.unlocked == true
end

function ErrorText.UpdateSample()
    if sampleWanted() then
        if sampling then return end
        sampling = true
        ErrorText.Show("error", _G.SPELL_FAILED_INTERRUPTED or L["Interrupted"], true)
        ErrorText.Show("error", _G.ERR_INV_FULL or L["Inventory is full."], true)
    elseif sampling then
        sampling = nil
        ErrorText.Clear()
    end
end

local function apply()
    local claim = enabled()
    if claim == (claimed == true) then return end
    claimed = claim
    for _, id in ipairs(allTypes()) do
        if claim then DUI.ClaimMessageType(id, ErrorText.OWNER, true) else DUI.ReleaseMessageType(id, ErrorText.OWNER) end
    end
end

function ErrorText.Enable(m)
    mod = m
    if not listening then
        listening = true
        -- Always listening (the shared event frame has no unregister); nothing
        -- is ours while this is off, so nothing shows then.
        DUI.RegisterEvent("UI_ERROR_MESSAGE", onMessage("error"))
        DUI.RegisterEvent("UI_INFO_MESSAGE", onMessage("info"))
        DUI.errorText = ours
        DUI.RegisterTestPart(ErrorText.TEST_PART, "Error text", 97, enabled)
        DUI.On("TestModeChanged", ErrorText.UpdateSample)
        DUI.On("TestPartChanged", function(key) if key == ErrorText.TEST_PART then ErrorText.UpdateSample() end end)
        DUI.On("UnlockChanged", ErrorText.UpdateSample)
    end
    apply()
end

function ErrorText.Refresh(m)
    mod = m
    apply()
    if not enabled() then
        sampling = nil
        ErrorText.Clear()
    else
        ErrorText.UpdateSample()
    end
end
