-- The base window: shell, header (optional round portrait, title, sub line,
-- close button) and a page host. Pages are built once ahead of time and filled
-- on show. Opening, closing and page switches animate through Feel; when to
-- open or close is up to the caller.
--
--   local f = Win.New({ name = "DaylightUINpc", w = 400, h = 540, portrait = true })
--   Win.AddPage(f, "talk", { Build = fn(page), Fill = fn(page, ...) })
--   Win.ShowPage(f, "talk", ...)   -- fills it; lifts it in if the window is open
--   Win.Open(f) / Win.Close(f, done)

local _, DUI = ...
local Style = DUI.Style

local Win = DUI.Win
local Feel = Win.Feel

Win.HEADER = 56
Win.EDGE = 16
Win.PORTRAIT = 40
Win.TITLE_SIZE, Win.SUB_SIZE = DUI.Style.SIZE.title, DUI.Style.SIZE.small
Win.DIM = DUI.Style.INK.LABEL   -- labels and unselected tabs
Win.LINE = 2   -- accent line height along the top
Win.MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

Win.COMPACT = 36   -- compact header height, title row only (bags)
Win.CLOSE_X = -9
Win.TITLE_Y = -12

-- Compact headers center the close button on the title. Full headers put it
-- a bit lower, between the title and sub line.
function Win.CloseY(compact) return compact and -8 or -15 end

-- Accent line along the top, plus a faint rule under the header at `height`
-- px when given. Win.Repaint colors the top line.
function Win.Lines(f, height)
    f.topLine = f:CreateTexture(nil, "ARTWORK")
    f.topLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.topLine:SetHeight(Win.LINE)
    f.topLine:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -2)
    f.topLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -2)
    if not height then return end
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.rule:SetHeight(1)
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", Win.EDGE, -height)
    f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Win.EDGE, -height)
    f.rule:SetVertexColor(1, 1, 1, 0.06)
end

-- A one-shot flare around the portrait as a window opens. Uses the game's
-- spell alert flipbooks (ActionButtonSpellAlerts.xml): the burst, then the
-- spinning ring, desaturated and tinted with the accent, then fading out.
-- It plays once so it never reads as an alert. Alpha is stepped by
-- Motion.Tween, not an animation group. No flare with motion off.
Win.GLOW_START = "UI-HUD-ActionBar-Proc-Start-Flipbook"
Win.GLOW_LOOP = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
Win.GLOW_START_SIZE = 2.6   -- times the portrait size (the game uses 150 on a 45 button)
Win.GLOW_LOOP_SIZE = 1.4    -- times the portrait size, same ratio as the game
Win.GLOW_START_TIME = 0.7   -- same as the game
Win.GLOW_HOLD = 1.1         -- seconds the ring spins before fading

local function flipbook(g, tex, dur, looping)
    local ag = g:CreateAnimationGroup()
    if looping then ag:SetLooping("REPEAT") end
    local fb = ag:CreateAnimation("FlipBook")
    fb:SetTarget(tex)
    fb:SetDuration(dur)
    fb:SetFlipBookRows(6)
    fb:SetFlipBookColumns(5)
    fb:SetFlipBookFrames(30)
    fb:SetFlipBookFrameWidth(0)
    fb:SetFlipBookFrameHeight(0)
    return ag
end

local function glowTexture(g, p, atlas, size)
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetAtlas(atlas)
    t:SetDesaturated(true)   -- the art is gold; desaturate so the accent tint comes out true
    t:SetBlendMode("ADD")
    t:SetSize(Win.PORTRAIT * size, Win.PORTRAIT * size)
    t:SetPoint("CENTER", p, "CENTER", 0, 0)
    return t
end

function Win.MakeGlow(f, p)
    local g = CreateFrame("Frame", nil, f)
    g:SetAllPoints(f)
    g:SetFrameLevel(f:GetFrameLevel() + 8)
    g.start = glowTexture(g, p, Win.GLOW_START, Win.GLOW_START_SIZE)
    g.loop = glowTexture(g, p, Win.GLOW_LOOP, Win.GLOW_LOOP_SIZE)
    g.startAnim = flipbook(g, g.start, Win.GLOW_START_TIME, false)
    g.loopAnim = flipbook(g, g.loop, 1, true)
    g.startAnim:SetScript("OnFinished", function() g.start:SetAlpha(0) end)
    g.hold = {}
    g:SetAlpha(0)
    g:Hide()
    return g
end

local function paintGlow(t)
    local lo, hi = Style.AccentPair()
    if lo and CreateColor then
        t:SetVertexColor(1, 1, 1, 1)
        t:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
    else
        t:SetVertexColor(Style.Accent())
    end
end

local function stopGlow(g)
    g.startAnim:Stop()
    g.loopAnim:Stop()
    g:SetAlpha(0)
    g:Hide()
end

-- Plays the flare once, if there is a portrait and motion is on.
function Win.Glow(f)
    local g = f.portraitGlow
    if not g or not (DUI.Motion and DUI.Motion.On()) or not f.portrait:IsShown() then return end
    local Motion = DUI.Motion
    paintGlow(g.start)
    paintGlow(g.loop)
    g.startAnim:Stop()
    g.start:SetAlpha(1)
    g:Show()
    g.startAnim:Play()
    g.loopAnim:Play()
    Motion.Tween(g, 0, 1, Motion.FAST, function(a) g:SetAlpha(a) end)
    Motion.Tween(g.hold, 0, 1, Win.GLOW_HOLD, nil, function()
        Motion.Tween(g, 1, 0, Motion.SLOW, function(a) g:SetAlpha(a) end, function() stopGlow(g) end)
    end)
end

-- The shared window header, also used by the character window and bags.
-- spec.portrait adds a round portrait. spec.compact is just the title row
-- (Win.COMPACT tall, no sub line or rule). spec.onClose falls back to
-- f.onClose, then Win.Close.
-- Sets f.title, f.sub (not compact), f.close, f.portrait, f.topLine, f.rule.
function Win.Header(f, spec)
    spec = spec or {}
    local E = Win.EDGE
    local left = E
    if spec.portrait then
        local p = f:CreateTexture(nil, "ARTWORK")
        p:SetSize(Win.PORTRAIT, Win.PORTRAIT)
        p:SetPoint("TOPLEFT", f, "TOPLEFT", E, -8)
        local mask = f:CreateMaskTexture()
        mask:SetTexture(Win.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(p)
        p:AddMaskTexture(mask)
        local rim = f:CreateTexture(nil, "OVERLAY")
        rim:SetTexture(DUI.MEDIA .. "portrait-rim.png")
        rim:SetPoint("TOPLEFT", p, "TOPLEFT", -3, 3)
        rim:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 3, -3)
        -- The rim art is white. Tint it the shell's band color so it reads
        -- as part of the window.
        rim:SetVertexColor(Style.BAND[1], Style.BAND[2], Style.BAND[3], 1)
        f.portrait, f.portraitRim = p, rim
        f.portraitGlow = Win.MakeGlow(f, p)
        left = E + Win.PORTRAIT + 12
    end
    f.title = Style.Text(f, Win.TITLE_SIZE, "LEFT")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, Win.TITLE_Y)
    f.title:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.title:SetWordWrap(false)
    Style.InkText(f.title, "VALUE")
    if not spec.compact then
        f.sub = Style.Text(f, Win.SUB_SIZE, "LEFT")
        f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
        f.sub:SetPoint("RIGHT", f, "RIGHT", -40, 0)
        f.sub:SetWordWrap(false)
        f.sub:SetTextColor(Win.DIM[1], Win.DIM[2], Win.DIM[3])
    end
    f.close = DUI.Widgets.Close(f, function()
        if spec.onClose then spec.onClose(f)
        elseif f.onClose then f.onClose()
        else Win.Close(f) end
    end)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", Win.CLOSE_X, Win.CloseY(spec.compact))
    Win.Lines(f, not spec.compact and Win.HEADER or nil)
    Win.Repaint(f)
end

-- Header tabs, between the title and the close button.
--   Win.Tabs(f, { { id = "spells", text = SPELLBOOK }, ... }, function(id) ... end)
-- Win.PickTab(f, id) selects a tab without calling onPick.
Win.TAB_GAP, Win.TAB_SIZE = 14, DUI.Style.SIZE.body

function Win.PickTab(f, id)
    if not f.tabs then return end
    local was = f.tab
    f.tab = id
    for _, b in ipairs(f.tabs) do b.Pick(b.id == id, was ~= nil) end
end

-- A small icon button left of the close button, e.g. an options gear. Call
-- before Win.Tabs so the tabs and title make room for it.
Win.HEADER_ICON_GAP = 6
function Win.HeaderIcon(f, icon, tip, onClick)
    local b = DUI.Widgets.IconButton(f, icon, tip, onClick)
    b:SetPoint("RIGHT", f.close, "LEFT", -Win.HEADER_ICON_GAP, 0)
    f.headerRight = b
    f.headerRoom = b:GetWidth() + Win.HEADER_ICON_GAP
    local room = 40 + f.headerRoom
    f.title:SetPoint("RIGHT", f, "RIGHT", -room, 0)
    if f.sub then f.sub:SetPoint("RIGHT", f, "RIGHT", -room, 0) end
    return b
end

function Win.Tabs(f, tabs, onPick)
    f.tabs, f.onTab = {}, onPick
    local right = f.headerRight or f.close
    for i = #tabs, 1, -1 do
        local t = tabs[i]
        local b = DUI.Widgets.Tab(f, t.text, { size = Win.TAB_SIZE })
        b.id = t.id
        b.FitWidth()
        b:SetPoint("RIGHT", right, "LEFT", -Win.TAB_GAP, 0)
        b:SetScript("OnClick", function()
            if f.tab == b.id then return end
            Win.PickTab(f, b.id)
            if f.onTab then f.onTab(b.id) end
        end)
        table.insert(f.tabs, 1, b)
        right = b
    end
    -- Keep the title and sub line clear of the tabs.
    local room = 40 + (f.headerRoom or 0)
    for _, b in ipairs(f.tabs) do room = room + b:GetWidth() + Win.TAB_GAP end
    f.title:SetPoint("RIGHT", f, "RIGHT", -room, 0)
    if f.sub then f.sub:SetPoint("RIGHT", f, "RIGHT", -room, 0) end
    for _, b in ipairs(f.tabs) do b.Pick(f.tab == b.id) end
end

-- Repaints colors the core restyle doesn't cover. Call on style changes.
function Win.Repaint(f)
    if f.topLine then Style.PaintAccent(f.topLine, 0.7) end
    if f.tabs then for _, b in ipairs(f.tabs) do b.Paint(false) end end
    if f.grip then f.grip.Paint() end
end

function Win.New(spec)
    local f = CreateFrame("Frame", spec.name, UIParent)
    f.spec = spec
    f:SetFrameStrata(spec.strata or "MEDIUM")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetSize(spec.w or 400, spec.h or 540)
    f:Hide()
    Style.Shell(f, { window = spec.back or true })   -- spec.back: module whose opacity setting applies (Style.WindowBack)
    Win.Header(f, spec)
    DUI.Pad.Follow(f, function() f.close:Click() end)
    f.host = CreateFrame("Frame", nil, f)
    f.host:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -Win.HEADER - 1)
    f.host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.pages, f.defs = {}, {}
    f.room = true   -- other windows slide aside for it (Win.Room)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    return f
end

-- The window's top-center point in UIParent units, as saved by Win.Drag.
function Win.TopOf(f)
    local l, t, w = f:GetLeft(), f:GetTop(), f:GetWidth()
    if type(l) ~= "number" or type(t) ~= "number" or type(w) ~= "number" then return nil end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (l + w / 2) * k, t * k
end

function Win.PlaceTop(f, x, y)
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "BOTTOMLEFT", x / k, y / k)
end

-- True when the window can't move or resize right now: it's combat and the
-- window is protected, or a secure layer sits on it (f.held, used by the
-- spellbook in Book/Fight.lua).
function Win.Held(f)
    if not InCombatLockdown() then return false end
    return f:IsProtected() == true or (f.held ~= nil and f.held() == true)
end

-- The window's own scale times the global scale setting.
function Win.Scale(own)
    return (tonumber(own) or 1) * DUI.Movers.Scale()
end

-- Ctrl + mouse wheel scales the window in slider-sized steps, clamped to
-- lo-hi. Out of combat only, since protected windows can't scale then.
-- Scroll lists inside forward Ctrl + wheel to f.wheelScale (see W.Scroll).
Win.WHEEL_STEP = 0.05
function Win.WheelScale(f, get, set, lo, hi)
    f:EnableMouseWheel(true)
    function f.wheelScale(delta)
        if InCombatLockdown() then return end
        local v = (tonumber(get()) or 1) + (delta > 0 and Win.WHEEL_STEP or -Win.WHEEL_STEP)
        v = math.floor(math.max(lo or 0.7, math.min(hi or 1.3, v)) / Win.WHEEL_STEP + 0.5) * Win.WHEEL_STEP
        set(v)
    end
    f:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then f.wheelScale(delta) end
    end)
end

-- A bottom-right resize grip. Resizing gives pages more room; text size is
-- left to scale. The top-left corner stays fixed while dragging, and the
-- position and size are saved when the drag ends. Right-click resets.
-- opts:
--   min = { w, h } or fn(pageId) -> { w, h }
--   size(pageId) -> saved w, h or nil (Win.ShowPage opens at it)
--   set(w, h, pageId), save(x, y), reset()
--   place(f) re-anchors windows that live in the game's panel layout
--     instead of saving a position
--   resized(w, h, live) is called each frame with live = true (only stretch
--     rows, Stack:Stretch), then once at the end to refill
-- Protected windows only resize out of combat. Win.Resizable wires this to a
-- module's saved sizes.
Win.GRIP = 12
function Win.Grip(f, opts)
    local grip = CreateFrame("Button", nil, f)
    f.grip = grip
    f.userSize = opts.size
    grip:SetSize(Win.GRIP, Win.GRIP)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip.icon = grip:CreateTexture(nil, "ARTWORK")
    grip.icon:SetTexture(DUI.MEDIA .. "ui-grip.png")
    grip.icon:SetAllPoints(grip)
    grip.lit = grip:CreateTexture(nil, "OVERLAY")
    grip.lit:SetTexture(DUI.MEDIA .. "ui-grip.png")
    grip.lit:SetAllPoints(grip)
    local glow = 0
    -- Fade through the accent's alpha, since a gradient texture ignores SetAlpha.
    local function light(on)
        DUI.Motion.Tween(grip.lit, glow, on and 1 or 0, DUI.Motion.FAST, function(a) glow = a; Style.PaintAccent(grip.lit, a) end)
    end
    function grip.Paint()
        local c = Style.INK.LABEL
        grip.icon:SetVertexColor(c[1], c[2], c[3], 0.6)
        Style.PaintAccent(grip.lit, glow)
    end
    grip.Paint()
    local function cursor()
        local x, y = GetCursorPosition()
        local s = f:GetEffectiveScale()
        if type(s) ~= "number" or s <= 0 then s = 1 end
        return (tonumber(x) or 0) / s, (tonumber(y) or 0) / s
    end
    local function laidOut(w, h, live)
        f.goalW = w   -- read by Stack:Width
        if opts.resized then opts.resized(w, h, live) end
    end
    local function step()
        local g = grip.grab
        if not g then return end
        local cx, cy = cursor()
        local w = math.floor(math.max(g.minW, math.min(g.maxW, g.w + cx - g.x)) + 0.5)
        local h = math.floor(math.max(g.minH, math.min(g.maxH, g.h + g.y - cy)) + 0.5)
        if w == g.lastW and h == g.lastH then return end
        g.lastW, g.lastH = w, h
        f:SetSize(w, h)
        laidOut(w, h, true)
    end
    local function stop()
        local g = grip.grab
        if not g then return end
        step()
        grip.grab = nil
        grip:SetScript("OnUpdate", nil)
        if not grip:IsMouseOver() then light(false) end
        local w, h = f:GetWidth(), f:GetHeight()
        if opts.place then
            opts.place(f)
        else
            local x, y = Win.TopOf(f)
            if x then
                Win.PlaceTop(f, x, y)   -- back to a single anchor so Feel can glide it
                if opts.save then opts.save(x, y) end
            end
        end
        if opts.set then opts.set(w, h, f.current) end
        laidOut(w, h)
        if Win.Room then Win.Room.Changed(f) end
    end
    DUI.Widgets.PadSkip(grip)   -- mouse only, not a gamepad stop
    grip:SetScript("OnEnter", function() light(true) end)
    grip:SetScript("OnLeave", function() if not grip.grab then light(false) end end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or Win.Held(f) then return end
        Feel.Settle(f)   -- finish any glide first, it moves the same anchor
        local left, top = f:GetLeft(), f:GetTop()
        if type(left) ~= "number" or type(top) ~= "number" then return end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        local x, y = cursor()
        local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
        local min = opts.min or {}
        if type(min) == "function" then min = min(f.current) or {} end
        grip.grab = { x = x, y = y, w = f:GetWidth(), h = f:GetHeight(),
            minW = min[1] or 300, minH = min[2] or 300,
            maxW = math.max(min[1] or 300, (tonumber(UIParent:GetWidth()) or 1920) * k - left),
            maxH = math.max(min[2] or 300, top) }
        grip:SetScript("OnUpdate", step)
    end)
    -- Right-click resets to the default size.
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not grip.grab then
            if opts.reset and not Win.Held(f) then opts.reset() end
            return
        end
        stop()
    end)
    f:HookScript("OnHide", stop)
    return grip
end

-- Win.Grip backed by a module's per-profile db.sizes. Each page keeps its own
-- size unless opts.shared. Sizes never go below the page's base size
-- (opts.base(id) -> w, h) in width, or below minH (default 3/4 of base) in height.
-- opts: db(), base(id), shared, minH, save, place, resized(w, h, live),
-- follow() -> the Win.Follow def whose panel width needs rewriting.
-- Returns R with R.Size(id), R.Saved(id) (nil if unsaved) and R.Reset().
function Win.Resizable(f, opts)
    local R = {}
    local function key(id) return opts.shared and "all" or (id or "all") end
    local function base(id) return opts.base(id) end
    local function minH(id)
        local _, h = base(id)
        return opts.minH or math.floor(h * 0.75)
    end
    function R.Saved(id)
        local db = opts.db()
        local s = db and type(db.sizes) == "table" and db.sizes[key(id)]
        if type(s) ~= "table" or type(s[1]) ~= "number" or type(s[2]) ~= "number" then return nil end
        local bw = base(id)
        return math.max(bw, s[1]), math.max(minH(id), s[2])
    end
    function R.Size(id)
        local w, h = R.Saved(id)
        if w then return w, h end
        return base(id)
    end
    local function written()
        local fo = opts.follow and opts.follow()
        if fo then Win.Followers.WriteWidth(fo) end
    end
    function R.Reset()
        local db = opts.db()
        if not (db and db.sizes) then return false end
        db.sizes = nil
        local w, h = base(f.current)
        f.goalW = w
        if Feel.IsOpen(f) then Feel.Size(f, w, h) else f:SetSize(w, h) end
        if opts.resized then opts.resized(w, h) end
        written()
        return true
    end
    Win.Grip(f, {
        min = function(id) return { (base(id)), minH(id) } end,
        size = R.Saved,
        set = function(w, h, id)
            local db = opts.db()
            if not db then return end
            if type(db.sizes) ~= "table" then db.sizes = {} end
            db.sizes[key(id)] = { math.floor(w + 0.5), math.floor(h + 0.5) }
            written()
        end,
        save = opts.save, place = opts.place, resized = opts.resized, reset = function() R.Reset() end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = function() R.Reset() end   -- /dui reset
    return R
end

-- Drag the window by its header. opts.save(x, y) gets the top-center point
-- (Win.TopOf) when the drag ends; opts.reset() runs on a header right-click.
function Win.Drag(f, opts)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    local function onHeader()
        local top, s = f:GetTop(), f:GetEffectiveScale()
        local _, y = GetCursorPosition()
        if type(top) ~= "number" or type(y) ~= "number" or not s or s <= 0 then return false end
        return y / s >= top - Win.HEADER
    end
    local function stop()
        if not f.dragging then return end
        f.dragging = nil
        f:StopMovingOrSizing()
        f:SetUserPlaced(false)   -- we save the position, not the game's layout cache
        local x, y = Win.TopOf(f)
        if not x then return end
        Win.PlaceTop(f, x, y)   -- back to a single anchor so Feel can glide it
        if opts.save then opts.save(x, y) end
        if Win.Room then Win.Room.Changed(f) end   -- the new spot is home now
    end
    f:SetScript("OnDragStart", function()
        if not onHeader() or Win.Held(f) then return end
        Feel.Settle(f)   -- finish any glide first, it moves the same anchor
        f.dragging = true
        f:StartMoving()
    end)
    f:SetScript("OnDragStop", stop)
    f:HookScript("OnHide", stop)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and opts.reset and onHeader() then opts.reset() end
    end)
end

-- A dragged window's saved position, stored per profile as db.spot = { x, y }
-- (top-center, pixel snapped). db() returns the module's db or nil before it
-- loads; place(f) puts the window back at its default spot.
--   S.Get()      saved { x, y } or nil
--   S.Save(x, y) for Win.Drag's save
--   S.Reset()    true if a spot was cleared. Protected windows move back
--                after combat.
function Win.Spot(f, db, place)
    local S = {}
    function S.Get()
        local d = db()
        local s = d and d.spot
        if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then return s end
        return nil
    end
    function S.Save(x, y)
        local d = db()
        if d then d.spot = { DUI.Pixel.Snap(UIParent, x), DUI.Pixel.Snap(UIParent, y) } end
    end
    local function back() if Feel.IsOpen(f) then place(f) end end
    function S.Reset()
        local d = db()
        if not (d and d.spot) then return false end
        d.spot = nil
        if Win.Held(f) then
            DUI.AfterCombat(back, "winSpot:" .. tostring(f))
        else
            back()
        end
        return true
    end
    return S
end

-- Win.Close, plus hiding a tooltip owned by anything in the window. A row
-- hidden under the mouse never gets OnLeave, so its tooltip would stay up.
function Win.Shut(f, done)
    local tip = GameTooltip
    local owner = tip and tip:IsShown() and tip:GetOwner()
    while owner do
        if owner == f then tip:Hide(); break end
        owner = owner:GetParent()
    end
    Win.Close(f, done)
end

function Win.SetTitle(f, title, color, sub)
    -- A player's name can be secret in combat, so no truth test here.
    if type(title) == "nil" then title = "" end
    f.title:SetText(title)
    if color then f.title:SetTextColor(color[1], color[2], color[3]) else Style.InkText(f.title, "VALUE") end
    if f.sub then f.sub:SetText(sub or "") end
end

-- Show a unit's portrait. If the unit doesn't exist (a quest from a board or
-- an item), show `fallback` art like the game's quest window does.
function Win.SetPortrait(f, unit, fallback)
    if not f.portrait then return end
    f.portrait:SetTexCoord(0, 1, 0, 1)
    local ok
    if unit and type(UnitExists) == "function" and not UnitExists(unit) then unit = nil end
    if unit then
        ok = type(SetPortraitTexture) == "function" and pcall(SetPortraitTexture, f.portrait, unit)
    elseif fallback then
        f.portrait:SetTexture(fallback)
        ok = true
    end
    f.portrait:SetShown(ok and true or false)
    f.portraitRim:SetShown(ok and true or false)
end

-- Cropped so the icon's baked-in border doesn't show inside the round mask.
function Win.SetIcon(f, icon)
    if not f.portrait then return end
    f.portrait:SetTexture(icon)
    Style.CropIcon(f.portrait)
end

-- def.Build(page) runs once, def.Fill(page, ...) on every show.
-- Optional: def.pieces(page) for a custom lift-in order, def.w / def.h.
function Win.AddPage(f, id, def) f.defs[id] = def end

-- Call ahead of time so opening never waits on a build.
function Win.Build(f, id)
    local page, def = f.pages[id], f.defs[id]
    if page or not def then return page end
    page = CreateFrame("Frame", nil, f.host)
    page:SetAllPoints(f.host)
    page.win = f
    page:Hide()
    f.pages[id] = page
    def.Build(page)
    return page
end

local function piecesOf(def, page)
    if def.pieces then return def.pieces(page) end
    return Feel.Pieces(page)
end

-- Fill and show a page. On an open window the page lifts in right away;
-- otherwise Win.Open lifts it in after the header.
function Win.ShowPage(f, id, ...)
    local def = f.defs[id]
    if not def then return end
    local page = Win.Build(f, id)
    local old = f.current and f.pages[f.current]
    if old and old ~= page then old:Hide() end
    f.current = id
    if DUI.Motion then DUI.Motion.Tween(page, 1, 1, 0, function(a) page:SetAlpha(a) end) end   -- cancels any Win.Dim tween
    page:SetAlpha(1)
    page:Show()
    local w, h = def.w or f.spec.w or 400, def.h or f.spec.h or 540
    if f.userSize then   -- size saved from Win.Grip
        local uw, uh = f.userSize(id)
        if uw then w, h = uw, uh end
    end
    f.goalW, f.goalH = w, h   -- so Fill lays out for the final size, not the current one
    if def.Fill then def.Fill(page, ...) end
    if Feel.IsOpen(f) then
        Feel.Size(f, w, h)
        Feel.Stagger(piecesOf(def, page), 0)
        if Win.Room then Win.Room.Changed(f) end
    else
        f:SetSize(w, h)
    end
    DUI.Pad.Scrolls(f)   -- point the gamepad's right stick at this page's list
end

-- How much the page's width will change once the window finishes resizing.
function Win.GoalGrowth(page)
    local f = page and page.win
    if not (f and f.goalW) then return 0 end
    local now = f:GetWidth()
    if type(now) ~= "number" then return 0 end
    return f.goalW - now
end

function Win.Open(f)
    if Feel.IsOpen(f) then return end
    if DUI.Sound then DUI.Sound.Play("open") end
    Feel.Open(f)
    Win.Glow(f)
    local page = f.current and f.pages[f.current]
    if page then Feel.Stagger(piecesOf(f.defs[f.current], page), Feel.HEAD) end
end

function Win.Close(f, done)
    if not Feel.IsOpen(f) then if done then done() end return end
    if DUI.Sound then DUI.Sound.Play("close") end
    Feel.Close(f, done)
end

function Win.IsOpen(f) return Feel.IsOpen(f) end

-- Dim the current page while waiting for the next one.
function Win.Dim(f, on)
    local page = f.current and f.pages[f.current]
    if not page then return end
    local M = DUI.Motion
    local to = on and 0.35 or 1
    if M and M.On() then
        M.Tween(page, page:GetAlpha(), to, M.FAST, function(a) page:SetAlpha(a) end)
    else
        page:SetAlpha(to)
    end
end
