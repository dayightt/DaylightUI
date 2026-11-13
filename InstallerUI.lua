-- The setup guide's window. A veil dims the game for the welcome and finish
-- pages, and the welcome gets the sunrise banner. Tour pages get a sidebar of
-- steps with a progress line, a header (step, title, what it changes) and a
-- footer ("Change it later", Back, Next). Pages scroll in the body and slide
-- in from the side they come from. Also here: the spotlight around real
-- frames, the secure Reload button, and hiding during combat. Page content
-- lives in InstallerSteps.lua and the flow in Installer.lua.

local _, DUI = ...
local Style, W = DUI.Style, DUI.Widgets
local SIZE = DUI.Style.SIZE -- the text size scale
local C = W.COLORS
local L = DUI.L
local T = DUI.Options.Text

local UI = {}
DUI.InstallerUI = UI

UI.WIDTH, UI.HEIGHT = 760, 520
UI.RAIL = 170 -- the step list's width
-- Matches the window kit's spacing (Windows/, loaded after this file): its
-- edge (Win.EDGE), title line (Win.TITLE_Y) and footer room (Npc.FOOT).
UI.PAD = 16
UI.TOP = 12 -- the title line, down from the window's top
UI.HEADER = 76 -- from the top down to the rule: the title (with its step) and what it changes
UI.FOOTER = 52
UI.BUTTON_H = 28 -- footer button height (as in Parts.Footer)
UI.BANNER_H = 150
UI.BANNER_CROP = { 0.31, 0.74 } -- the vertical band of the banner shown: the sun and the title, close up
UI.GLOW_ALPHA = 0.22
UI.VEIL_ALPHA = 0.45
UI.SLIDE = 24 -- how far a page slides in from
UI.PIN_GAP = 16 -- between a page's pinned part and its scrolling part
UI.RAIL_TOP, UI.STEP_H = 78, 30

local frame, veil, reload
local spots = {}
local quiet, combatHidden = false, false
local away, wanted = false, false -- whole UI hidden (see "stepping aside" below); whether the guide should be open
local handlers = {}

function UI.Frame() return frame end
function UI.Veil() return veil end
function UI.Spots() return spots end
function UI.ReloadButton() return reload end
function UI.IsShown() return frame ~= nil and frame:IsShown() end

-- The width a page is laid out to: the window's inside minus the sidebar.
function UI.ContentWidth(rail) return UI.WIDTH - 2 * UI.PAD - (rail and UI.RAIL or 0) end

-- An alpha fade on a frame or texture that holds its end value. Call Play on it.
local function fade(region, from, to, duration, delay)
    local g = region:CreateAnimationGroup()
    g:SetToFinalAlpha(true)
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    if delay then a:SetStartDelay(delay) end
    a:SetSmoothing("OUT")
    return g
end

-- Building

local function buildVeil()
    veil = CreateFrame("Frame", nil, UIParent)
    veil:SetAllPoints(UIParent)
    veil:SetFrameStrata("HIGH")
    veil:SetFrameLevel(1)
    veil:EnableMouse(true)
    veil.tex = veil:CreateTexture(nil, "BACKGROUND")
    veil.tex:SetAllPoints(veil)
    veil.tex:SetColorTexture(0, 0, 0, UI.VEIL_ALPHA)
    veil.fadeIn = fade(veil, 0, 1, DUI.Motion.NORMAL)
    veil.fadeOut = fade(veil, 1, 0, DUI.Motion.CLOSE)
    veil:Hide()
end

-- The player closing it (X, Escape). The window and its veil fade out
-- together, and its OnHide (the close) runs when the fade ends.
local function closeByPlayer()
    away = false -- a click or a key means the UI is clearly there
    if veil and veil:IsShown() and DUI.Motion.On() then veil.fadeOut:Play() end
    DUI.Motion.Vanish(frame)
end

local function buildBanner()
    local b = CreateFrame("Frame", nil, frame)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    b:SetHeight(UI.BANNER_H)
    -- The Home page's banner and sunrise (Options.NewSunrise), cropped to a band
    -- with the sun and title close up.
    local crop = UI.BANNER_CROP
    local h = UI.BANNER_H - 16
    local sky = CreateFrame("Frame", nil, b)
    sky:SetAllPoints(b)
    b.sky = sky
    -- Dark sky across the whole banner (the sunrise's is only as wide as the
    -- logo), so the wash always lands on something.
    b.back = sky:CreateTexture(nil, "BACKGROUND")
    b.back:SetTexture(DUI.MEDIA .. "logo-sky.png")
    b.back:SetTexCoord(0, 1, crop[1], crop[2])
    b.back:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -8)
    b.back:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -12, 8)
    b.sunrise = DUI.Options.NewSunrise(sky, crop)
    b.sunrise:SetSize(h * 2 / (crop[2] - crop[1]), h)
    b.sunrise:SetPoint("TOP", b, "TOP", 0, -8)
    b.sunrise.sky:Hide() -- b.back is the only sky, so there's no seam at the logo's edges
    -- A wash of Daylight colors across the whole banner, additive (it would hide
    -- anything behind it otherwise), in its own frame above the sunrise so it
    -- covers the middle as well as the sides.
    local over = CreateFrame("Frame", nil, sky)
    over:SetAllPoints(b)
    over:SetFrameLevel(b.sunrise:GetFrameLevel() + 5)
    b.glow = over:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture(Style.GRADIENT_FILE)
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -8)
    b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -12, 8)
    b.glow:SetAlpha(UI.GLOW_ALPHA)
    frame.banner = b
end

local function buildRail()
    local r = CreateFrame("Frame", nil, frame)
    r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    r:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    r:SetWidth(UI.RAIL)
    r.bg = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.bg:SetAllPoints(r)
    r.bg:SetColorTexture(C.sidebar[1], C.sidebar[2], C.sidebar[3], 1)
    r.edge = r:CreateTexture(nil, "BORDER")
    r.edge:SetColorTexture(1, 1, 1, 0.05)
    r.edge:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.edge:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    r.edge:SetWidth(1)
    r.logo = r:CreateTexture(nil, "ARTWORK")
    r.logo:SetTexture(DUI.MEDIA .. "logo-wordmark.png")
    r.logo:SetSize(144, 36)
    r.logo:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -18)
    -- The progress line: a faint track from the first step to the last, filled in
    -- Daylight colors down to the current step.
    r.line = r:CreateTexture(nil, "ARTWORK")
    r.line:SetColorTexture(1, 1, 1, 0.08)
    r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.fill:SetColorTexture(1, 1, 1, 1)
    if r.fill.SetGradient and CreateColor then
        local a, b = Style.GRADIENT[1], Style.GRADIENT[2]
        -- A vertical gradient starts from its first color at the bottom.
        r.fill:SetGradient("VERTICAL", CreateColor(b[1], b[2], b[3], 1), CreateColor(a[1], a[2], a[3], 1))
    end
    r.items = {}
    frame.rail = r
end

local function buildHeader()
    local h = CreateFrame("Frame", nil, frame)
    h:SetHeight(UI.HEADER)
    -- The window kit's title, with the step after it like the options window's section.
    h.title = W.Font(h, W.TITLE, SIZE.title, C.text)
    h.title:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.step = W.Font(h, W.BODY, SIZE.small, C.faint)
    h.step:SetPoint("BOTTOMLEFT", h.title, "BOTTOMRIGHT", 10, 2)
    h.desc = W.Font(h, W.BODY, SIZE.body, C.dim)
    h.desc:SetWordWrap(true)
    h.desc:SetJustifyV("TOP")
    h.desc:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -6)
    h.desc:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 8)
    -- The window kit's faint rule under the header (Win.Lines).
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetColorTexture(1, 1, 1, 0.06)
    h.rule:SetHeight(1)
    h.rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 24, 0)
    frame.header = h
end

local function buildBody()
    local s = CreateFrame("ScrollFrame", nil, frame)
    s.bar = W.Scroll(s)
    frame.scroll = s
end

local function buildFooter()
    local f = CreateFrame("Frame", nil, frame)
    f:SetHeight(UI.FOOTER)
    -- Laid out like the kit's footer (Parts.Footer): buttons 12 px up from the
    -- bottom, a faint line 10 px above them.
    f.line = f:CreateTexture(nil, "BORDER")
    f.line:SetColorTexture(1, 1, 1, 0.06)
    f.line:SetHeight(1)
    f.line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", UI.PAD, 12 + UI.BUTTON_H + 10)
    f.line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -UI.PAD, 12 + UI.BUTTON_H + 10)
    local row = 12 + UI.BUTTON_H / 2 -- the buttons' center, up from the bottom
    -- "Change it later" opens the options window on that page, over the guide.
    local later = W.Link(f)
    later:SetPoint("LEFT", f, "BOTTOMLEFT", UI.PAD, row)
    later:SetScript("OnClick", function()
        if frame.laterPage and DUI.OptionsPanel then DUI.OptionsPanel.Show(frame.laterPage) end
    end)
    frame.later = later
    frame.next = W.Button(f, NEXT or L["Next"], UI.BUTTON_H)
    frame.next:SetWidth(110)
    frame.next:SetPoint("RIGHT", f, "BOTTOMRIGHT", -UI.PAD, row)
    frame.next.SetActive(true)
    frame.next:SetScript("OnClick", function() if handlers.next then handlers.next() end end)
    frame.back = W.Button(f, BACK or L["Back"], UI.BUTTON_H)
    frame.back:SetWidth(90)
    frame.back:SetPoint("RIGHT", frame.next, "LEFT", -8, 0)
    frame.back:SetScript("OnClick", function() if handlers.back then handlers.back() end end)
    frame.footer = f
end

local function buildClose()
    local b = W.Close(frame, closeByPlayer)
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", DUI.Win.CLOSE_X, DUI.Win.CloseY()) -- where every window has its X
    b:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.close = b
end

-- Dragged by its top edge.
local function buildDrag()
    local d = CreateFrame("Frame", nil, frame)
    d:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    d:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -48, 0)
    d:SetHeight(40)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", function() frame:StartMoving() end)
    d:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.drag = d
end

local function build()
    frame = CreateFrame("Frame", "DaylightUIInstaller", UIParent)
    frame:SetSize(UI.WIDTH, UI.HEIGHT)
    -- Below DIALOG, so the options window, popups and menus open over it.
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(10)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Style.Shell(frame)
    frame.fill = W.Round(frame, "BACKGROUND", 1)
    frame.fill:SetAllPoints(frame)
    W.Tint(frame.fill, C.window)
    buildVeil()
    buildBanner()
    buildRail()
    buildHeader()
    buildBody()
    buildFooter()
    buildClose()
    buildDrag()
    -- Escape closes it, but it isn't registered as one of the game's special
    -- frames. The game closes all of those itself (CloseAllWindows on entering the
    -- world, when a new character is prompted), and that isn't the player
    -- closing the guide. Other keys pass through to the game.
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local esc = key == "ESCAPE"
        self:SetPropagateKeyboardInput(not esc)
        if esc then closeByPlayer() end
    end)
    frame:Hide()
    frame:SetScript("OnHide", function()
        veil:Hide()
        UI.Spotlight(nil)
        UI.HideReload()
        -- Still shown, only the UI around it was hidden.
        if frame:IsShown() then away = true end
        if quiet or away then return end
        wanted = false
        if handlers.close then handlers.close() end
    end)
    -- Fades in on open and fades out only when the player closes it (above),
    -- never when the guide hides itself. Escape is handled in OnKeyDown.
    DUI.Motion.Window(frame, nil, true)
    -- Shown again mid-fade: bring the veil back too.
    hooksecurefunc(frame, "Show", function()
        if veil and veil.fadeOut:IsPlaying() then
            veil.fadeOut:Stop()
            veil:SetAlpha(1)
        end
    end)
end

function UI.Body()
    if not frame then build() end
    return frame.scroll
end

-- Showing pages

-- Shows the window. h holds callbacks: close() when the player closes it (X or
-- Escape, not when the guide hides itself), next(), back(), again() after combat.
function UI.Open(h)
    if not frame then build() end
    handlers = h or {}
    combatHidden = false
    wanted = true
    frame:Show()
end

-- Hides the window without counting as the player closing it.
function UI.QuietHide()
    if not frame then return end
    wanted = false
    quiet = true
    frame:Hide()
    quiet = false
end

function UI.SetVeil(on)
    if not veil then return end
    if on and frame:IsShown() then
        if not veil:IsShown() then
            veil.fadeOut:Stop()
            veil:Show()
            veil.fadeIn:Play()
        end
    else
        veil:Hide()
    end
end

-- The page fades in, sliding from the side it comes from (dir 1 from the
-- right going forward, -1 from the left going back).
function UI.Slide(page, dir)
    local g = page.slideIn
    if not g then
        g = page:CreateAnimationGroup()
        g.hide = g:CreateAnimation("Alpha")
        g.hide:SetFromAlpha(0)
        g.hide:SetToAlpha(0)
        g.hide:SetDuration(0)
        g.hide:SetOrder(1)
        g.jump = g:CreateAnimation("Translation")
        g.jump:SetDuration(0)
        g.jump:SetOrder(1)
        g.move = g:CreateAnimation("Translation")
        g.move:SetDuration(DUI.Motion.NORMAL)
        g.move:SetOrder(2)
        g.move:SetSmoothing("OUT")
        g.alpha = g:CreateAnimation("Alpha")
        g.alpha:SetFromAlpha(0)
        g.alpha:SetToAlpha(1)
        g.alpha:SetDuration(DUI.Motion.NORMAL)
        g.alpha:SetOrder(2)
        page.slideIn = g
    end
    g:Stop()
    g.jump:SetOffset(UI.SLIDE * dir, 0)
    g.move:SetOffset(-UI.SLIDE * dir, 0)
    g:Play()
end

-- The welcome's sunrise: the Home page banner's animation plays and the
-- Daylight wash fades up under it.
function UI.Sunrise()
    local b = frame.banner
    b.sunrise.Play()
    -- Stepped by hand, never an alpha animation group (that flickered in game).
    local M = DUI.Motion
    b.glow:SetAlpha(0)
    M.Tween(b.glow, 0, UI.GLOW_ALPHA, M.SLOW, function(a) b.glow:SetAlpha(a) end)
end

-- A new page's header text fades in with it like the options window's.
-- Unchanged text stays put.
local function say(fs, text)
    if fs:GetText() == text then return end
    fs:SetText(text)
    if frame:IsVisible() then DUI.Motion.Fade(fs, 0, 1, DUI.Motion.NORMAL) end
end

-- A footer button coming back fades in quickly; one leaving goes at once so
-- it can't be clicked on its way out.
local function button(b, on)
    local fresh = on and not b:IsShown() and frame:IsVisible()
    b:SetShown(on)
    if fresh then DUI.Motion.Fade(b, 0, 1, DUI.Motion.FAST) end
end

-- Puts a page in the window. opts: full (the welcome: banner, no sidebar,
-- header or footer), rail, veil, step and total ("Step 2 of 6"), title, desc,
-- later (an options page for "Change it later"), back (show Back), next
-- (Next's text, nil hides it), dir (1 forward, -1 back).
function UI.SetPage(page, opts)
    if not frame then build() end
    local rail = opts.rail == true and not opts.full
    frame.rail:SetShown(rail)
    frame.banner:SetShown(opts.full == true)
    frame.header:SetShown(not opts.full)
    frame.footer:SetShown(not opts.full)
    local left = (rail and UI.RAIL or 0) + UI.PAD
    frame.header:ClearAllPoints()
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -UI.TOP)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD - 24, -UI.TOP)
    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", rail and UI.RAIL or 0, 0)
    frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    -- A page may pin a part above the rest (the Frames page's samples). It sits
    -- under the header and stays put while the rest of the page scrolls below it.
    local pin = not opts.full and page.pinned or nil
    if frame.pinned and frame.pinned ~= pin then frame.pinned:Hide() end
    frame.pinned = pin
    local top = UI.TOP + UI.HEADER + 12 -- under the rule, the kit's spacing (Parts.Stack's top)
    if pin then
        pin:SetParent(frame)
        pin:ClearAllPoints()
        pin:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
        pin:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.PAD, -top)
        pin:Show()
        top = top + pin:GetHeight() + UI.PIN_GAP
    end
    frame.scroll:ClearAllPoints()
    if opts.full then
        frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.PAD, -UI.BANNER_H)
        frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAD, UI.PAD)
    else
        frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
        frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -UI.PAD, UI.FOOTER)
    end
    local h = frame.header
    say(h.step, opts.step and string.format(L["Step %d of %d"], opts.step, opts.total) or "")
    say(h.title, T(opts.title or ""))
    say(h.desc, T(opts.desc or ""))
    frame.laterPage = opts.later
    local where = opts.later and DUI.InstallerPages.Where(opts.later)
    frame.later.SetLabel(where and string.format(L["Change it later: /dui > %s"], where) or "")
    frame.later:SetShown(where ~= nil)
    button(frame.back, opts.back == true)
    button(frame.next, opts.next ~= nil)
    if opts.next then frame.next.text:SetText(opts.next) end
    if frame.current and frame.current ~= page then frame.current:Hide() end
    frame.current = page
    frame.scroll:SetScrollChild(page)
    frame.scroll.bar.Stop()
    frame.scroll:SetVerticalScroll(0)
    page:Show()
    UI.Slide(page, opts.dir or 1)
    if pin then UI.Slide(pin, opts.dir or 1) end
    if opts.full then UI.Sunrise() end
    UI.SetVeil(opts.veil == true)
end

-- New header text on the visible page (after Finish has run). The text fades
-- in and the page stays put. back = false hides Back.
function UI.Retitle(title, desc, back)
    if not frame then return end
    say(frame.header.title, T(title or ""))
    say(frame.header.desc, T(desc or ""))
    button(frame.back, back == true)
end

-- The sidebar

local function railItem(i)
    local rail = frame.rail
    local b = rail.items[i]
    if b then return b end
    b = CreateFrame("Button", nil, rail)
    b:SetHeight(UI.STEP_H)
    b:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -(UI.RAIL_TOP + (i - 1) * UI.STEP_H))
    b:SetPoint("RIGHT", rail, "RIGHT", 0, 0)
    b.tick = W.Icon(b, "ui-check.png", 12, C.dim)
    b.tick:SetPoint("LEFT", b, "LEFT", 30, 0)
    b.tick:Hide()
    b.text = W.Font(b, W.BODY, SIZE.body, C.faint)
    b.text:SetPoint("LEFT", b, "LEFT", 46, 0)
    -- A tick pops in when its step is done.
    b.pop = b.tick:CreateAnimationGroup()
    local s = b.pop:CreateAnimation("Scale")
    s:SetScaleFrom(0.6, 0.6)
    s:SetScaleTo(1, 1)
    s:SetDuration(DUI.Motion.NORMAL)
    s:SetSmoothing("OUT")
    rail.items[i] = b
    return b
end

-- The fill grows to goal px tall, easing out over 0.3 s.
local function easeFill(goal)
    local rail = frame.rail
    rail.fillGoal = goal
    if not rail.fillNow then
        rail.fillNow = goal
        rail.fill:SetSize(2, goal)
        return
    end
    rail.easeT, rail.easeFrom = 0, rail.fillNow
    rail:SetScript("OnUpdate", function(self, dt)
        self.easeT = math.min(1, self.easeT + dt / 0.3)
        local t = 1 - (1 - self.easeT) ^ 3
        self.fillNow = self.easeFrom + (self.fillGoal - self.easeFrom) * t
        self.fill:SetSize(2, math.max(1, self.fillNow))
        if self.easeT >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

-- steps: { { id, label } } in order. current: index being shown. visited: ids
-- the player may jump back to. onPick(id) jumps.
function UI.SetRail(steps, current, visited, onPick)
    if not frame then build() end
    local rail = frame.rail
    for i, s in ipairs(steps) do
        local b = railItem(i)
        b.text:SetText(T(s.label))
        local done, now = i < current, i == current
        W.TextColor(b.text, now and C.text or (done and C.dim or C.faint))
        local had = b.tick:IsShown()
        b.tick:SetShown(done)
        if done then
            W.TintAccent(b.tick)
            if not had then b.pop:Play() end
        end
        b:SetScript("OnClick", function()
            if not now and visited[s.id] then onPick(s.id) end
        end)
        b:Show()
    end
    for i = #steps + 1, #rail.items do rail.items[i]:Hide() end
    local top = UI.RAIL_TOP + UI.STEP_H / 2
    rail.line:ClearAllPoints()
    rail.line:SetPoint("TOPLEFT", rail, "TOPLEFT", 21, -top)
    rail.line:SetSize(2, math.max(1, (#steps - 1) * UI.STEP_H))
    rail.fill:ClearAllPoints()
    rail.fill:SetPoint("TOPLEFT", rail.line, "TOPLEFT", 0, 0)
    easeFill(math.max(1, (current - 1) * UI.STEP_H))
end

-- Spotlight, Reload, combat

-- A soft pulsing accent outline around each named frame that exists and is
-- shown. Ours hangs from theirs, never the other way around.
function UI.Spotlight(names)
    for _, s in ipairs(spots) do s:Hide() end
    if not names then return end
    local n = 0
    for _, name in ipairs(names) do
        local target = _G[name]
        if type(target) == "table" and target.IsShown and target:IsShown() then
            n = n + 1
            local s = spots[n]
            if not s then
                s = CreateFrame("Frame", nil, UIParent)
                s:SetFrameStrata("HIGH")
                s.edge = W.Round(s, "OVERLAY", 0, true)
                s.edge:SetAllPoints(s)
                s.pulse = s:CreateAnimationGroup()
                s.pulse:SetLooping("BOUNCE")
                local a = s.pulse:CreateAnimation("Alpha")
                a:SetFromAlpha(0.35)
                a:SetToAlpha(0.9)
                a:SetDuration(0.6)
                spots[n] = s
            end
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", target, "TOPLEFT", -6, 6)
            s:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 6, -6)
            W.TintAccent(s.edge)
            s:Show()
            s.pulse:Play()
        end
    end
end

-- The Finish page's Reload: a secure button running /reload. Addon code can't
-- call ReloadUI on this client, but a click on a secure macro button can.
-- Created out of combat and parented to UIParent (the window must stay free
-- to hide in combat), laid over `over` while shown. Returns false when it
-- can't be shown now, and the guide uses the popup instead.
function UI.ShowReload(over)
    if InCombatLockdown() then return false end
    -- A timer from the Finish checklist can fire after the window closed.
    if not (frame and frame:IsShown()) then return false end
    if not reload then
        local ok, b = pcall(CreateFrame, "Button", "DaylightUIInstallerReload", UIParent, "SecureActionButtonTemplate")
        if not ok or type(b) ~= "table" then return false end
        reload = b
        reload:SetAttribute("type", "macro")
        reload:SetAttribute("macrotext", "/reload")
        reload:RegisterForClicks("AnyUp", "AnyDown")
        reload:SetFrameStrata("HIGH")
        reload.bg = W.Round(reload, "BACKGROUND")
        reload.bg:SetAllPoints(reload)
        reload.text = W.Font(reload, W.TITLE, SIZE.head, C.text, "CENTER")
        reload.text:SetPoint("CENTER", reload, "CENTER", 0, 0)
        reload.text:SetText(L["Reload"])
    end
    W.TintAccent(reload.bg)
    W.TextColor(reload.text, W.OnAccent())
    reload:ClearAllPoints()
    reload:SetAllPoints(over)
    reload:SetFrameLevel((frame and frame:GetFrameLevel() or 10) + 30)
    reload:Show()
    return true
end

-- force: also hide as combat starts (PLAYER_REGEN_DISABLED fires just before
-- lockdown, the last moment a secure frame can still hide). When hidden it
-- lets go of the page it was laid over, since a secure frame left anchored to
-- ours ties the two together.
function UI.HideReload(force)
    if not reload then return end
    if force or not InCombatLockdown() then reload:Hide() end
    DUI.AfterCombat(function()
        if not reload:IsShown() then reload:ClearAllPoints() end
    end, "installer reload points")
end

DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    UI.HideReload(true)
    if frame and frame:IsShown() then
        combatHidden = true
        UI.QuietHide()
    end
end)

DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if not (combatHidden and frame) then return end
    combatHidden = false
    wanted = true
    frame:Show()
    if handlers.again then handlers.again() end
end)

-- When the whole UI is hidden (a new character's intro cinematic, Alt+Z) the
-- guide hides with it, which isn't the player closing it. It comes back with
-- the UI on the same page.
UIParent:HookScript("OnShow", function()
    away = false
    if not (wanted and frame) then return end
    if InCombatLockdown() then combatHidden = true; return end
    frame:Show()
    if handlers.again then handlers.again() end
end)

-- An old release accidentally shipped a debug log of what hid the guide at
-- login, saved in DaylightUIDB.guideDebug. Clear what it left behind.
DUI.RegisterEvent("PLAYER_LOGIN", function()
    if type(DaylightUIDB) == "table" then DaylightUIDB.guideDebug = nil end
end)
