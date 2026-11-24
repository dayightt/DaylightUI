-- The tour. After the setup guide's reload, "Take a tour?" asks once. Yes
-- walks the player past Daylight UI's own features (damage meter, buff
-- groups, bag groups, moving frames, the options), lighting one part, dimming
-- the rest, and showing a small card with Back, Next and Skip tour. It shares
-- its engine with DaylightMogul's tours. Home's "Take the tour" runs it again.
--
-- Each area adds its own stop with DUI.Tour.Add(id, spec). spec fields:
--   order, title, text (each a string or function)
--   part(): the regions to light, one box around those shown (none: the card
--     sits in the middle)
--   available(), enter(), leave(next): optional (show a sample, open the
--     options); leave gets the stop coming next, nil when the tour ends
--   settle: seconds to let enter() finish
--   wait: true if the part only shows once the player opens it (a key away).
--     Until then the card sits in the middle, and the light glides over once
--     it's up.
--
--   follow: true, or a function saying when, if the part moves or changes
--     while its step shows (a window the player is working in): the light
--     glides after it.
--   done(): true once the player has done what the step asks; it moves on.
--   avoid(): regions the card mustn't cover, though they aren't lit.
--
-- Tour.Run(list, opts) runs any list of stops as a tour of its own (the
-- Cooldown Manager's first-time tour). opts: key, through (the mouse reaches
-- what's under the layer, for stops the player tries as they read), skipped
-- (the line shown on a skip), finished(how) with how = "done" or "skip".
--
-- The layer covers the screen and takes the mouse but never the keyboard
-- (except Escape, which skips), so game keys still work. A fight ends it at
-- once. No game calls and no protected frames: only Daylight UI's frames, plus samples
-- through test mode (DUI.SetTestSolo), which ends in a fight by itself.

local _, DUI = ...
local Style, W, Win, Motion = DUI.Style, DUI.Widgets, DUI.Win, DUI.Motion
local Parts = Win.Parts
local L = DUI.L

local Tour = {}
DUI.Tour = Tour

Tour.NAME = "DaylightUITour"
Tour.ASK_NAME = "DaylightUITourAsk"
Tour.W = 320 -- card width
Tour.EDGE = 14 -- the card's inner padding
Tour.ROW_GAP = 8 -- between the card's rows
Tour.BTN_H = 24
Tour.TITLE_H = 20 -- the card's one-line title
Tour.BTN_W = 64 -- minimum width of Back and Next
Tour.ASK_Y = -160 -- the question, down from the top of the screen
Tour.TOAST_Y = 120 -- the "skipped" line, up from the bottom of the screen
Tour.TOAST_H = 36
Tour.LIGHT_PAD = 6 -- padding between the part and its light
Tour.GAP = 14 -- from the light to the card
Tour.MARGIN = 8 -- the card stays this far inside the screen
Tour.DIM = 0.55 -- how dark the rest of the screen gets
Tour.SETTLE = 0.4 -- lets what a step opens finish opening before the light finds it
Tour.WATCH = 0.2 -- how often a waiting step looks for its part
Tour.TOAST_TIME = 3.2
Tour.TYPE_GAP = 0.09 -- between the letters the search stop types
Tour.ASK_DELAY = 2 -- after login (the setup guide's check goes first)

Tour.stops = {}

local S -- the running tour: { list, opts, i, rect, x, top, lit, box, waiting, shown }

local function pop(text) return Parts.Hex({ Style.Pop() }) .. text .. "|r" end
Tour.Pop = pop

function Tour.Add(id, def)
    def.id = id
    for i, d in ipairs(Tour.stops) do
        if d.id == id then Tour.stops[i] = def return end
    end
    Tour.stops[#Tour.stops + 1] = def
end

function Tour.Running(key)
    if key == nil then return S ~= nil end
    return S ~= nil and S.opts.key == key
end
function Tour.Step() return S and S.i or nil end
function Tour.StepId() return S and S.list[S.i].id or nil end
function Tour.Lit() return S and S.lit or nil end

-- This player's stops in order (module on and the feature enabled).
function Tour.List()
    local list = {}
    for _, d in ipairs(Tour.stops) do
        local ok, on = true, true
        if d.available then ok, on = pcall(d.available) end
        if ok and on then list[#list + 1] = d end
    end
    table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return list
end

-- Placement

-- A region's box in the layer's units (y up), or nil while it has none.
local function boxOf(region)
    if not (type(region) == "table" and region.IsVisible and region:IsVisible()) then return nil end
    local l, b, r, t = region:GetLeft(), region:GetBottom(), region:GetRight(), region:GetTop()
    if not (l and b and r and t) then return nil end
    local frame = region.GetEffectiveScale and region or region:GetParent()
    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return { l = l * k, b = b * k, r = r * k, t = t * k }
end

-- Top left of a w x h card for a light at rect (y up) on an sw x sh screen.
-- Tries right of it, then below, left, above, and finally centered on it for
-- big windows like the options.
function Tour.CardSpot(rect, w, h, sw, sh)
    local gap, edge = Tour.GAP, Tour.MARGIN
    local x, top
    if sw - rect.r > w + gap + edge then x, top = rect.r + gap, rect.t
    elseif rect.b > h + gap then x, top = rect.r - w, rect.b - gap
    elseif rect.l > w + gap + edge then x, top = rect.l - gap - w, rect.t
    elseif sh - rect.t > h + gap + edge then x, top = rect.l, rect.t + gap + h
    else x, top = (rect.l + rect.r - w) / 2, (rect.b + rect.t + h) / 2 end
    x = math.max(edge, math.min(sw - w - edge, x))
    top = math.max(h + edge, math.min(sh - edge, top))
    return x, top
end

local function place(rect, x, top)
    local f = Tour.frame
    Tour.spot:ClearAllPoints()
    Tour.spot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", rect.l, rect.b)
    Tour.spot:SetPoint("TOPRIGHT", f, "BOTTOMLEFT", rect.r, rect.t)
    Tour.card:ClearAllPoints()
    Tour.card:SetPoint("TOPLEFT", f, "BOTTOMLEFT", x, top)
end

local function mix(a, b, t) return a + (b - a) * t end

-- The light and card glide to their new spots. The first step just appears
-- there while the whole layer fades in.
local function moveTo(rect, x, top)
    local was = S.rect
    local fromX, fromTop = S.x, S.top
    S.rect, S.x, S.top = rect, x, top
    if not (was and Motion.On()) then return place(rect, x, top) end
    Motion.Tween(Tour, 0, 1, Motion.NORMAL, function(t)
        if not S then return end
        place({ l = mix(was.l, rect.l, t), b = mix(was.b, rect.b, t),
                r = mix(was.r, rect.r, t), t = mix(was.t, rect.t, t) },
            mix(fromX, x, t), mix(fromTop, top, t))
    end)
end

-- The card


local function fitCard()
    local c = Tour.card
    -- Let go of the last step's height first: text held to a height measures
    -- only the lines that fit, so a longer step would come out cut.
    c.text:SetHeight(0)
    local th = c.text:GetStringHeight() or 0
    c.text:SetHeight(math.max(1, th)) -- grows down from its top, whatever measures it
    local h = Tour.EDGE * 2 + Style.SIZE.small + Tour.TITLE_H + th + Tour.ROW_GAP * 3 + Tour.BTN_H
    c:SetHeight(h)
    return h
end

local function words(step, n)
    local c = Tour.card
    c.count:SetText(string.format(L["%d of %d"], S.i, n))
    c.title:SetText(type(step.title) == "function" and step.title() or step.title)
    c.text:SetText(type(step.text) == "function" and step.text() or step.text)
    c.next.text:SetText(S.i == n and (DONE or L["Done"]) or (NEXT or L["Next"]))
    c.next.FitWidth(Tour.BTN_W)
    c.back.SetOff(S.i == 1)
end

local function grow(box, more)
    if not box then return more end
    return { l = math.min(box.l, more.l), b = math.min(box.b, more.b),
             r = math.max(box.r, more.r), t = math.max(box.t, more.t) }
end

-- The step's parts on screen (part() may return several, like sample buff
-- buttons) as one box, plus the first of them. Nil while none shows.
local function partOf(step)
    if not step.part then return nil end
    local got = { pcall(step.part) }
    if not got[1] then return nil end
    local box, first
    for i = 2, table.maxn(got) do
        local b = boxOf(got[i])
        if b then
            first = first or got[i]
            box = grow(box, b)
        end
    end
    return first, box
end

-- The light's box grown by the regions a step's card keeps clear of.
local function avoidOf(step, box)
    if not step.avoid then return box end
    local got = { pcall(step.avoid) }
    if not got[1] then return box end
    for i = 2, table.maxn(got) do
        local b = boxOf(got[i])
        if b then box = grow(box, b) end
    end
    return box
end

local function paint()
    local step = S.list[S.i]
    local n = #S.list
    words(step, n)
    local h = fitCard()
    local bar = Tour.card.bar
    Motion.Tween(bar, bar:GetValue(), S.i / n, Motion.SLOW, function(v) bar:SetValue(v) end)
    local part, box = partOf(step)
    S.lit, S.box, S.shown = box and part or nil, box, S.i
    S.waiting = step.wait and not box
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    if not box then
        -- Nothing to light: card in the middle, light shrunk to a point under it.
        local x, top = (sw - Tour.W) / 2, (sh + h) / 2
        Tour.spot.edge:Hide()
        return moveTo({ l = sw / 2, b = sh / 2, r = sw / 2, t = sh / 2 }, x, top)
    end
    Tour.spot.edge:Show()
    local pad = Tour.LIGHT_PAD
    local rect = { l = box.l - pad, b = box.b - pad, r = box.r + pad, t = box.t + pad }
    local x, top = Tour.CardSpot(avoidOf(step, rect), Tour.W, h, sw, sh)
    moveTo(rect, x, top)
end

-- An error in a step's own code ends the tour so the screen is never left covered.
local function guarded(fn)
    if not DUI.SafeCall(fn) then Tour.Stop() end
end

local function leaveStep(nextStep)
    local step = S and S.list[S.i]
    if step and step.leave then DUI.SafeCall(step.leave, nextStep) end
end

-- The text fades out and the next step's fades in. A step that opens
-- something (enter) lets it land first so the light finds its real spot.
local function goTo(i)
    if not S or i < 1 or i > #S.list or i == S.i then return end
    leaveStep(S.list[i])
    S.i = i
    local step = S.list[i]
    if step.enter then guarded(step.enter) end
    if not S then return end
    local c = Tour.card
    local wait = step.enter and (step.settle or Tour.SETTLE) or Motion.FAST
    if not Motion.On() then
        if not step.enter then return guarded(paint) end
        wait = step.settle or Tour.SETTLE
    else
        Motion.AlphaTo(c.words, 0, Motion.FAST)
    end
    local token = {}
    Tour.fading = token
    C_Timer.After(wait, function()
        if Tour.fading ~= token or not S then return end
        guarded(paint)
        if S then Motion.AlphaTo(c.words, 1, Motion.FAST) end
    end)
end

-- Building

local function pane(f)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(0, 0, 0, Tour.DIM)
    Tour.panes = Tour.panes or {}
    Tour.panes[#Tour.panes + 1] = t
    return t
end

local function buildLight(f)
    local spot = CreateFrame("Frame", nil, f)
    Tour.spot = spot
    -- the four panes hang off the light, so they glide with it
    local top, bottom, left, right = pane(f), pane(f), pane(f), pane(f)
    top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    top:SetPoint("BOTTOM", spot, "TOP", 0, 0)
    bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("TOP", spot, "BOTTOM", 0, 0)
    left:SetPoint("LEFT", f, "LEFT", 0, 0)
    left:SetPoint("TOPRIGHT", spot, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", spot, "BOTTOMLEFT", 0, 0)
    right:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    right:SetPoint("TOPLEFT", spot, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMLEFT", spot, "BOTTOMRIGHT", 0, 0)
    -- same edge as the setup guide's spotlight (InstallerUI.lua UI.Spotlight)
    spot.edge = W.Round(spot, "OVERLAY", 0, true)
    spot.edge:SetAllPoints(spot)
    spot.pulse = spot:CreateAnimationGroup()
    spot.pulse:SetLooping("BOUNCE")
    local a = spot.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35)
    a:SetToAlpha(0.9)
    a:SetDuration(0.6)
end

-- The card's count, bar, title and text (shared with the question).
local function cardWords(c, parent)
    -- one short line at a fixed height, so the text below never shifts up
    c.title = Style.Text(parent, Style.SIZE.head, "LEFT")
    c.title:SetSize(Tour.W - 2 * Tour.EDGE, Tour.TITLE_H)
    c.title:SetWordWrap(false)
    Style.InkText(c.title, "VALUE")
    c.text = Style.Text(parent, Style.SIZE.body, "LEFT")
    c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -Tour.ROW_GAP)
    c.text:SetWidth(Tour.W - 2 * Tour.EDGE)
    c.text:SetWordWrap(true)
    c.text:SetJustifyV("TOP")
    Style.InkText(c.text, "TEXT")
end

local function buildCard(f)
    local c = CreateFrame("Frame", nil, f)
    Tour.card = c
    c:SetWidth(Tour.W)
    c:SetFrameLevel(f:GetFrameLevel() + 10)
    c:EnableMouse(true)
    Style.Shell(c, { window = true })
    c.close = W.Close(c, function() Tour.Skip() end)
    c.close:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -6)
    c.words = CreateFrame("Frame", nil, c) -- what fades between steps
    c.words:SetAllPoints(c)
    local row = CreateFrame("Frame", nil, c.words)
    row:SetPoint("TOPLEFT", c, "TOPLEFT", Tour.EDGE, -Tour.EDGE)
    row:SetPoint("TOPRIGHT", c, "TOPRIGHT", -(Tour.EDGE + 20), -Tour.EDGE)
    row:SetHeight(Style.SIZE.small)
    c.count = Style.Text(row, Style.SIZE.small, "LEFT")
    c.count:SetPoint("LEFT", row, "LEFT", 0, 0)
    Style.InkText(c.count, "LABEL")
    c.bar = W.Bar(row)
    c.bar:SetPoint("LEFT", c.count, "RIGHT", 10, 0)
    c.bar:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    cardWords(c, c.words)
    c.title:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -Tour.ROW_GAP)
    c.next = W.Button(c, NEXT or L["Next"], Tour.BTN_H)
    c.next:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -Tour.EDGE, Tour.EDGE)
    c.next:SetScript("OnClick", function() Tour.Next() end)
    Parts.Tone(c.next, "main")
    c.back = W.Button(c, BACK or L["Back"], Tour.BTN_H)
    c.back:SetPoint("RIGHT", c.next, "LEFT", -Tour.ROW_GAP, 0)
    c.back:SetScript("OnClick", function() Tour.Back() end)
    c.back.FitWidth(Tour.BTN_W)
    c.skip = W.Link(c)
    c.skip:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", Tour.EDGE, Tour.EDGE + 2)
    c.skip:SetScript("OnClick", function() Tour.Skip() end)
end

local function buildToast()
    local t = CreateFrame("Frame", nil, UIParent)
    Tour.toast = t
    t:SetFrameStrata("FULLSCREEN_DIALOG")
    t:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, Tour.TOAST_Y)
    t:SetAlpha(0)
    t:Hide()
    Style.Shell(t, { window = true })
    t.text = Style.Text(t, Style.SIZE.body, "CENTER")
    t.text:SetPoint("CENTER", t, "CENTER", 0, 0)
    Style.InkText(t.text, "TEXT")
end

function Tour.OnKey(key)
    if key == "ESCAPE" and S then
        Tour.Skip()
        return true
    end
    return false
end

local function moved(a, b)
    if not (a and b) then return a ~= b end
    return math.abs(a.l - b.l) > 0.5 or math.abs(a.b - b.b) > 0.5
        or math.abs(a.r - b.r) > 0.5 or math.abs(a.t - b.t) > 0.5
end

-- A waiting step (the bags, a key away) keeps looking for its part; a
-- following one glides after it; a step the player has done moves on.
local watched = 0
local function watch(_, dt)
    if not S then return end
    local step = S.list[S.i]
    if not (S.waiting or step.follow or step.done) or S.shown ~= S.i then return end
    watched = watched + (dt or 0)
    if watched < Tour.WATCH then return end
    watched = 0
    if step.done then
        local ok, yes = pcall(step.done)
        if ok and yes then return Tour.Next() end
    end
    if S.waiting then
        if partOf(step) then guarded(paint) end
        return
    end
    local follow = step.follow
    if type(follow) == "function" then
        local ok, on = pcall(follow)
        follow = ok and on
    end
    if follow and moved(select(2, partOf(step)), S.box) then guarded(paint) end
end

function Tour.Build()
    if Tour.frame then return Tour.frame end
    local f = CreateFrame("Frame", Tour.NAME, UIParent)
    Tour.frame = f
    f:SetAllPoints(UIParent)
    -- above the options window (DIALOG), which a stop may light
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:Hide()
    buildLight(f)
    buildCard(f)
    buildToast()
    Win.Keys(f, Tour.OnKey)
    f:SetScript("OnUpdate", watch)
    return f
end

-- Running

-- Hands the screen back at once while the dim fades out behind it.
local function finish(how)
    leaveStep()
    local f = Tour.frame
    local opts = S.opts
    S = nil
    Tour.fading = nil
    f:EnableMouse(false)
    Win.KeysOn(f, false)
    Tour.spot.pulse:Stop()
    Motion.AlphaTo(f, 0, Motion.NORMAL, true)
    if how and opts.finished then DUI.SafeCall(opts.finished, how) end
end

local function toast(text)
    if not Tour.toast then Tour.Build() end
    local t = Tour.toast
    t.text:SetText(text)
    t:SetSize((t.text:GetStringWidth() or 0) + 2 * Tour.EDGE, Tour.TOAST_H)
    t:Show()
    Motion.AlphaTo(t, 1, Motion.SLOW)
    local token = {}
    Tour.toastAt = token
    C_Timer.After(Tour.TOAST_TIME, function()
        if Tour.toastAt == token then Motion.AlphaTo(t, 0, Motion.SLOW, true) end
    end)
end

local function guideUp() return DUI.InstallerUI and DUI.InstallerUI.IsShown() end

-- Runs a list of stops from its first. False when it can't start now.
function Tour.Run(list, opts)
    if S or InCombatLockdown() or #list == 0 then return false end
    opts = opts or {}
    local f = Tour.Build()
    S = { list = list, opts = opts, i = 1 }
    Tour.card.skip.SetLabel(L["Skip tour"])
    f:EnableMouse(not opts.through)
    f:SetAlpha(0)
    f:Show()
    W.TintAccent(Tour.spot.edge)
    W.BarAccent(Tour.card.bar)
    Tour.card.bar:SetValue(0)
    Tour.card.words:SetAlpha(1)
    if Motion.On() then Tour.spot.pulse:Play() end
    Win.KeysOn(f, true)
    local step = list[1]
    if step.enter then guarded(step.enter) end
    if not S then return false end
    local token = {}
    Tour.fading = token
    C_Timer.After(step.enter and (step.settle or Tour.SETTLE) or 0, function()
        if Tour.fading ~= token or not S then return end
        guarded(paint)
        if S then Motion.AlphaTo(f, 1, Motion.NORMAL) end
    end)
    return true
end

-- Runs the whole tour from its first stop. False when it can't start now.
function Tour.Start()
    if S then return false end
    if InCombatLockdown() then
        DUI.Print(L["The tour waits until the fight is over."])
        return false
    end
    if guideUp() then
        DUI.Print(L["Finish the setup guide first."])
        return false
    end
    local list = Tour.List()
    if #list == 0 then return false end
    Tour.HideAsk()
    -- The options would cover what the first stops light, so one stop reopens them.
    local P = DUI.OptionsPanel
    if P and P.IsShown and P.IsShown() then P.Toggle() end
    return Tour.Run(list, {
        key = "tour",
        skipped = string.format(L["Tour skipped. %s on the options' Home page shows it again."], pop(L["Take the tour"])),
        finished = function() DUI.DB.Root().tourDone = true end,
    })
end

function Tour.Next()
    if not S then return end
    if S.i < #S.list then return goTo(S.i + 1) end
    finish("done")
end

function Tour.Back()
    if S then goTo(S.i - 1) end
end

-- Skip tour prints one line saying where to find it again.
function Tour.Skip()
    if not S then return end
    local text = S.opts.skipped
    finish("skip")
    if text then toast(text) end
end

-- A fight started, so put everything back at once.
function Tour.Stop()
    if S then finish() end
end

-- The question, after the setup guide

local function buildAsk()
    local a = CreateFrame("Frame", Tour.ASK_NAME, UIParent)
    Tour.ask = a
    a:SetFrameStrata("DIALOG")
    a:SetWidth(Tour.W)
    a:SetPoint("TOP", UIParent, "TOP", 0, Tour.ASK_Y)
    a:EnableMouse(true)
    a:Hide()
    Style.Shell(a, { window = true })
    a.close = W.Close(a, function() Tour.Answer(false) end)
    a.close:SetPoint("TOPRIGHT", a, "TOPRIGHT", -6, -6)
    cardWords(a, a)
    a.title:SetPoint("TOPLEFT", a, "TOPLEFT", Tour.EDGE, -Tour.EDGE)
    a.title:SetText(L["Take a tour?"])
    a.text:SetText(L["A minute to see what Daylight UI does that the game doesn't: the damage meter, buff and bag groups, moving frames and where every setting lives."])
    a.yes = W.Button(a, L["Show me around"], Tour.BTN_H)
    a.yes:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", -Tour.EDGE, Tour.EDGE)
    a.yes:SetScript("OnClick", function() Tour.Answer(true) end)
    a.yes.FitWidth(Tour.BTN_W)
    Parts.Tone(a.yes, "main")
    a.no = W.Button(a, L["Not now"], Tour.BTN_H)
    a.no:SetPoint("RIGHT", a.yes, "LEFT", -Tour.ROW_GAP, 0)
    a.no:SetScript("OnClick", function() Tour.Answer(false) end)
    a.no.FitWidth(Tour.BTN_W)
    local th = a.text:GetStringHeight() or 0
    a.text:SetHeight(math.max(1, th))
    a:SetHeight(Tour.EDGE * 2 + Tour.TITLE_H + th
        + Tour.ROW_GAP * 3 + Tour.BTN_H)
    return a
end

function Tour.AskShown() return Tour.ask ~= nil and Motion.Shown(Tour.ask) end

function Tour.HideAsk()
    if Tour.AskShown() then Motion.AlphaTo(Tour.ask, 0, Motion.FAST, true) end
end

-- Asks if the setup guide just finished on this character (DB flag tourOffer,
-- set at Finish) and this account hasn't seen the tour yet.
function Tour.Offer()
    local char = DUI.DB.Character()
    if not char.tourOffer then return end
    if DUI.DB.Root().tourDone then char.tourOffer = nil return end
    if S or guideUp() or Tour.AskShown() then return end
    if InCombatLockdown() then return DUI.AfterCombat(Tour.Offer, "tour") end
    local a = Tour.ask or buildAsk()
    a:SetAlpha(0)
    a:Show()
    Motion.AlphaTo(a, 1, Motion.NORMAL)
end

function Tour.Answer(yes)
    DUI.DB.Character().tourOffer = nil
    Tour.HideAsk()
    if yes then
        Tour.Start()
    else
        DUI.DB.Root().tourDone = true
        toast(string.format(L["%s on the options' Home page runs it any time."], pop(L["Take the tour"])))
    end
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(Tour.ASK_DELAY, Tour.Offer)
end)
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    Tour.Stop()
    if Tour.AskShown() then
        -- ask again after the fight
        Tour.ask:Hide()
        DUI.AfterCombat(Tour.Offer, "tour")
    end
end)
DUI.RegisterCommand("tour", function() Tour.Start() end, function() return L["/dui tour - a short tour of what Daylight UI adds"] end)

-- The core's stops (modules add theirs in their own files)

Tour.Add("unlock", {
    order = 80,
    title = function() return L["Move anything"] end,
    text = function()
        return string.format(L["Every piece of Daylight UI moves. %s shows a handle on each: drag it, scroll to resize, right-click to put it back. %s shows every frame with sample units, to style them without a group."],
            pop("/dui unlock"), pop("/dui test"))
    end,
    enter = function() DUI.Movers.Unlock() end,
    leave = function() DUI.Movers.Lock() end,
    settle = Motion.NORMAL + 0.1,
    part = function() return DUI.Movers.LockButton() end,
})

-- The tour opened the options, so it closes them (Done, Skip, a fight) like
-- their X does, unless the next stop shows them too.
local function closeOptions(nextStep)
    if nextStep and nextStep.usesOptions then return end
    local P = DUI.OptionsPanel
    if P.IsShown() then P.Toggle() end
end

Tour.Add("options", {
    order = 90,
    title = function() return L["Every setting"] end,
    text = function()
        return string.format(L["Press Escape and pick Daylight UI in the game menu, or type %s. %s over any Daylight UI window sizes it. %s on Home runs this tour again."],
            pop("/dui"), pop(L["Ctrl + mouse wheel"]), pop(L["Take the tour"]))
    end,
    usesOptions = true,
    enter = function() DUI.OptionsPanel.Show("home") end,
    leave = closeOptions,
    part = function() return DUI.OptionsPanel.Frame() end,
})

-- The search box types a word by itself, a letter at a time, so the player
-- sees the matching settings show up as live rows.
local function typeDemo(word)
    local box = DUI.OptionsPanel.SearchBox()
    if not box then return end
    local token = {}
    Tour.typing = token
    box:SetText("")
    if not Motion.On() then return box:SetText(word) end
    local n = 0
    local function letter()
        if Tour.typing ~= token or Tour.StepId() ~= "search" then return end
        n = n + 1
        box:SetText(string.sub(word, 1, n))
        if n < #word then C_Timer.After(Tour.TYPE_GAP, letter) end
    end
    C_Timer.After(Tour.SETTLE, letter)
end

Tour.Add("search", {
    order = 95,
    title = function() return L["Find any setting"] end,
    text = function()
        return string.format(L["Type a word in %s and every setting that matches shows up here, ready to change on the spot. No digging through pages."],
            pop(L["Search settings"]))
    end,
    usesOptions = true,
    enter = function()
        DUI.OptionsPanel.Show("home")
        typeDemo(L["Health"])
    end,
    leave = function(nextStep)
        Tour.typing = nil
        local box = DUI.OptionsPanel.SearchBox()
        if box then box:SetText("") end
        closeOptions(nextStep)
    end,
    part = function() return DUI.OptionsPanel.SearchBox() end,
})
