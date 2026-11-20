-- The scan band: under the window's header, on every tab, while a full scan
-- runs. It opens (the pages glide down to make room), says the stage in words
-- with a live count, a bar fills, and a soft light keeps running along it so it
-- never looks stuck. The finish: one bright sweep and flash, a sound, the
-- priced number counting up, then it glides away. A scan that stops or can't
-- start says why here, in one line.

local _, ns = ...
local DUI = DaylightUI
local L = ns.L
local Win = DUI.Win
local Style = DUI.Style
local W = DUI.Widgets
local Parts = Win.Parts
local Motion = DUI.Motion

local Band = {}
ns.ScanBand = Band

Band.H = 44             -- the room the pages give up
Band.EDGE = 16
Band.BAR_H = 8
Band.TICK = 0.1         -- seconds between looks at the scan
Band.LIGHT_W = 90
Band.LIGHT_DUR = 1.5    -- one run of the resting light (a loop, not a transition)
Band.LIGHT_ALPHA = 0.35
Band.FLASH_ALPHA = 0.55
Band.HOLD_DONE = 5      -- seconds each last line stays
Band.HOLD_STOP = 8
Band.HOLD_REFUSED = 4

local state      -- nil (closed), "scanning", "done", "stopped", "refused"
local ticker
local holding    -- the token of the running hold
local room = 0   -- how far the pages are down now (px)

local function pop(text) return Parts.Hex({ Style.Pop() }) .. text .. "|r" end
local function popNumber(n) return pop(ns.Thousands(n)) end
local function main() return ns.Window end

local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

-- The pages glide down by `to` px.
local function makeRoom(to, animate)
    local f = main().frame
    local function put(v)
        room = v
        f.host:ClearAllPoints()
        f.host:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Win.HEADER - 1 - v)
        f.host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    end
    if animate then
        Motion.Tween(Band, room, to, Motion.NORMAL, put)
    else
        Motion.Tween(Band, 0, 0, 0)
        put(to)
    end
end

local function show(on, animate)
    local b = Band.frame
    if animate then
        Motion.AlphaTo(b, on and 1 or 0, Motion.FAST, true)
    else
        Motion.AlphaTo(b, on and 1 or 0, 0, true)
        b:SetShown(on)
        if on then b:SetAlpha(1) end
    end
    makeRoom(on and Band.H or 0, animate)
end

local function say(left, right, role)
    local b = Band.frame
    b.say:SetText(left)
    b.count:SetText(right or "")
    Style.InkText(b.say, role)
    Style.InkText(b.count, "LABEL")
end

-- One look at the running scan.
local function follow()
    local stage, done, total, left, share = ns.Scan.Now()
    if not stage then return stopTicker() end
    if stage == "asking" then
        say(L["Asking the Auction House..."], L["Keep it open, about a minute"], "LABEL")
    elseif stage == "loading" then
        say(string.format(L["Loading new items from the game, %s to go"], popNumber(left)),
            string.format(L["%s of %s"], popNumber(done), ns.Thousands(total)), "LABEL")
    elseif stage == "reading" then
        say(L["Reading the Auction House..."], string.format(L["%s of %s"], popNumber(done), ns.Thousands(total)), "TEXT")
    else
        say(L["Saving prices"], pop(math.floor(share * 100 + 0.5) .. "%"), "LABEL")
    end
    Style.SetBarValue(Band.frame.bar, share)
end

-- The resting light: along the fill, or the whole track while it's empty.
local function runLight()
    if state ~= "scanning" then return end
    local b = Band.frame
    local over = b.bar:GetValue() > 0.02 and b.bar:GetStatusBarTexture() or b.bar
    Motion.Sweep(b.light, over, { width = Band.LIGHT_W, dur = Band.LIGHT_DUR, alpha = Band.LIGHT_ALPHA,
        key = b.light, done = runLight })
end

local function stopLight()
    local b = Band.frame
    Motion.Tween(b.light, 1, 1, 0)
    b.light:Hide()
end

local function hold(seconds)
    local token = {}
    holding = token
    C_Timer.After(seconds, function()
        if holding ~= token then return end
        holding, state = nil, nil
        show(false, main().IsOpen())
    end)
end

local function start(animate)
    holding = nil
    state = "scanning"
    Style.SetBarValue(Band.frame.bar, 0, true)
    stopTicker()
    ticker = C_Timer.NewTicker(Band.TICK, follow)
    follow()
    show(true, animate)
    runLight()
end

-- Back to closed, at once (the window isn't up).
local function reset()
    holding, state = nil, nil
    stopTicker()
    stopLight()
    show(false, false)
end

local function ended(ok, text, _, info)
    local b = Band.frame
    if not b then return end
    stopTicker()
    if not main().IsOpen() then return reset() end
    stopLight()
    state = ok and "done" or "stopped"
    if not ok then
        say(text, nil, "WARN")
        Style.SetBarValue(b.bar, 0)
        return hold(Band.HOLD_STOP)
    end
    info = info or { priced = 0, skipped = 0, fresh = 0 }
    Style.SetBarValue(b.bar, 1)
    local fresh = info.fresh > 0 and string.format(L["%s new to you"], popNumber(info.fresh)) or nil
    say(ns.Scan.DoneText(0, info.skipped, popNumber), fresh, "GOOD")
    Motion.Tween(b.say, 0, info.priced, Motion.SLOW, function(v)
        b.say:SetText(ns.Scan.DoneText(math.floor(v + 0.5), info.skipped, popNumber))
    end)
    Motion.Sweep(b.light, b.bar, { width = Band.LIGHT_W, dur = Motion.SLOW, alpha = 1, key = b.light })
    Motion.Flash(b.flash, Motion.SLOW)
    DUI.Sound.Play("done")
    local known = ns.Store.Count(ns.Ruleset.Key())
    main().CountKnown(known - info.fresh, known)
    hold(Band.HOLD_DONE)
end

function Band.Refuse(why)
    if not Band.frame or state == "scanning" then return end
    state = "refused"
    Style.SetBarValue(Band.frame.bar, 0, true)
    say(why, nil, "WARN")
    show(true, main().IsOpen())
    hold(Band.HOLD_REFUSED)
end

-- The window is about to open: the band as things are now.
function Band.Sync()
    if not Band.frame then return end
    if ns.Scan.Running() then return start(false) end
    if state then reset() end
end

function Band.State() return state end

function Band.Build(f)
    local b = CreateFrame("Frame", nil, f)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Win.HEADER - 1)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -Win.HEADER - 1)
    b:SetHeight(Band.H)
    b.say = Style.Text(b, Style.SIZE.small, "LEFT")
    b.say:SetPoint("TOPLEFT", b, "TOPLEFT", Band.EDGE, -8)
    b.count = Style.Text(b, Style.SIZE.small, "RIGHT")
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", -Band.EDGE, -8)
    b.say:SetPoint("RIGHT", b.count, "LEFT", -16, 0)
    b.bar = W.Bar(b, Band.BAR_H)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", Band.EDGE, 6)
    b.bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -Band.EDGE, 6)
    W.BarAccent(b.bar)
    b.light = b.bar:CreateTexture(nil, "OVERLAY")
    b.light:SetTexture(Parts.WHITE)
    b.light:SetBlendMode("ADD")
    b.light:SetHeight(Band.BAR_H)
    b.light:Hide()
    b.flash = W.Round(b.bar, "OVERLAY")
    b.flash:SetAllPoints(b.bar)
    b.flash:SetBlendMode("ADD")
    b.flash:SetVertexColor(1, 1, 1, Band.FLASH_ALPHA)
    b.flash:Hide()
    b:Hide()
    Band.frame = b
end

function Band.Restyle()
    if Band.frame then W.BarAccent(Band.frame.bar) end
end

ns.On("ScanStarted", function()
    if Band.frame and main().IsOpen() then start(true) end
end)
ns.On("ScanEnded", ended)
