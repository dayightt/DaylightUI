-- Shared controls, plus the options window's pages, cards and rows.
-- Rows are built from the registry's item data. Refresh() re-reads the
-- settings, Layout(query) places whatever the search leaves visible.

local _, DUI = ...
local Style, Options, Theme = DUI.Style, DUI.Options, DUI.OptionsTheme
local SIZE = DUI.Style.SIZE   -- the one text-size scale (Style.lua)
local L = DUI.L

local W = {}
DUI.Widgets = W

W.BODY = Theme.BodyFont()
W.TITLE = Style.FONT
W.ROW_HEIGHT = 28
W.BESIDE_GAP = 34   -- item.beside's controls from the row's own: the reset arrow sits between
W.PAD = 14
W.CONTROL_WIDTH = 150
W.CARD_GAP = 12
W.SLIDER_BOX = 60     -- a slider's value box: wide enough for "400 px" (an edit box scrolls a longer text to its end)
W.KNOB, W.KNOB_BIG = 12, 14   -- a slider's knob, and while hovered or dragged
W.LABEL_GAP = 36      -- between a row's label and its control (the reset arrow sits there)

W.COLORS = Theme.COLORS
local C = W.COLORS
local MEDIA = DUI.MEDIA

local function hex255(v) return math.max(0, math.min(255, math.floor((v or 1) * 255 + 0.5))) end
local function hex(c) return string.format("|cff%02x%02x%02x", hex255(c[1]), hex255(c[2]), hex255(c[3])) end

-- Eases an alpha change when animate is set and the region is visible,
-- otherwise sets it at once and cancels any running ease.
function W.EaseAlpha(region, to, animate)
    if animate and region:IsVisible() then
        DUI.Motion.AlphaTo(region, to, DUI.Motion.FAST)
        return
    end
    local key = region.__duiAlphaKey
    if key and key.goal == to and region:IsVisible() then return end   -- already easing there
    if key then DUI.Motion.Tween(key, 0, 0, 0); key.goal = nil end
    region:SetAlpha(to)
end

-- Shows or hides with a quick fade while the parent is visible.
function W.EaseShown(region, on, instant)
    local parent = region:GetParent()
    if not instant and parent and parent:IsVisible() then
        if on or region:IsShown() then DUI.Motion.AlphaTo(region, on and 1 or 0, DUI.Motion.FAST, true) end
        return
    end
    W.EaseAlpha(region, 1)
    region:SetShown(on)
end

-- Money as coin icons with the digits in INK.MONEY. opts.pad zero-pads
-- silver and copper once a higher coin shows ("1g 05s 09c"), opts.color =
-- false leaves the digits uncolored. Returns "" for secrets and non-numbers.
function W.Money(copper, opts)
    if issecretvalue and issecretvalue(copper) then return "" end
    if type(copper) ~= "number" then return "" end
    opts = opts or {}
    local amount = copper > 0 and math.floor(copper) or 0
    local on = opts.color ~= false
    local open, close = on and hex(Style.INK.MONEY) or "", on and "|r" or ""
    local g, s, c = math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100
    local vals = { { g, 10000 }, { s, 100 }, { c, 1 } }
    local parts = {}
    for i, v in ipairs(vals) do
        if v[1] > 0 or (i == 3 and #parts == 0) then
            local out = DUI.MoneyString(v[1] * v[2])
            local pad = opts.pad and i > 1 and (g > 0 or (i == 3 and s > 0))
            local n = out:gsub("^([%d,]+)", function(d)
                if pad then d = string.format("%02d", tonumber(d)) end
                return open .. d .. close
            end)
            parts[#parts + 1] = n
        end
    end
    return table.concat(parts, " ")
end

-- Building blocks

-- Text in the body or title font. It's tracked so a font change on the
-- Appearance page reaches text that already exists. If both fonts are the
-- same file, the text counts as body. Inside a window, a window font picked
-- on General > Appearance takes over.
local tracked = setmetatable({}, { __mode = "k" })

local function fileOf(t)
    local own = t[3] and DUI.Media.Pick(t[3])
    if own then return Style.FontFileOf(own) end
    return t[1] == "TITLE" and W.TITLE or W.BODY
end

function W.TrackFont(fs, font, size, parent)
    local slot = parent and Style.WindowSlotOf(parent) or nil
    if font == W.BODY then tracked[fs] = { "BODY", size, slot }
    elseif font == W.TITLE then tracked[fs] = { "TITLE", size, slot } end
    return tracked[fs] and fileOf(tracked[fs]) or font
end

DUI.On("RepaintCore", function()
    for fs, t in pairs(tracked) do fs:SetFont(fileOf(t), t[2], "") end
end)

function W.Font(parent, font, size, color, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(W.TrackFont(fs, font, size, parent), size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.7)
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function W.Tint(tex, c, alpha)
    tex:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

function W.TintAccent(tex, alpha)
    Style.PaintAccent(tex, alpha)
end

-- The options window's highlight is always the Daylight gradient, whatever
-- the player's accent. A plain W.Tint afterwards clears it.
function W.TintDaylight(tex, alpha)
    alpha = alpha or 1
    local a, b = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
    if tex.SetGradient and CreateColor then
        tex:SetVertexColor(1, 1, 1, alpha)
        tex:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], alpha), CreateColor(b[1], b[2], b[3], alpha))
    else
        local m = Style.GRADIENT_MID
        tex:SetVertexColor(m[1], m[2], m[3], alpha)
    end
end

-- Text can't take a gradient, so it gets the middle color.
function W.TextDaylight(fs)
    local m = Style.GRADIENT_MID
    fs:SetTextColor(m[1], m[2], m[3], 1)
end

-- Dark text on a light accent (rogue yellow, priest white), light otherwise.
W.ON_LIGHT = { 0.08, 0.08, 0.09 }
function W.OnAccent()
    local r, g, b = Style.Accent()
    if r * 0.299 + g * 0.587 + b * 0.114 > 0.55 then return W.ON_LIGHT end
    return C.text
end

function W.TextAccent(fs)
    local r, g, b = Style.Accent()
    fs:SetTextColor(r, g, b, 1)
end

function W.TextColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Rounded rectangle or outline that keeps its corners at any size
-- (nine-slice of a small round texture).
local SLICE = 10
function W.Round(parent, layer, sublevel, outline)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetTexture(MEDIA .. (outline and "ui-round-line.png" or "ui-round.png"))
    if t.SetTextureSliceMargins then
        t:SetTextureSliceMargins(SLICE, SLICE, SLICE, SLICE)
        if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
    return t
end

function W.Icon(parent, file, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(MEDIA .. file)
    t:SetSize(size, size)
    W.Tint(t, color or C.dim)
    return t
end

local function showTip(owner, title, desc)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    -- Same look as the tooltips. The options window always uses the Daylight sweep.
    local Tips = DUI.Tips
    Tips.Clear()
    Tips.Title(title or "")
    if desc then Tips.Text(desc) end
    Tips.Flush(GameTooltip, { sweep = "daylight" })
    GameTooltip:Show()
end

function W.Tooltip(owner, title, desc)
    if desc then showTip(owner, title, desc) end
end

-- Full text for a name too long for its box.
function W.NameTip(owner, name)
    showTip(owner, name)
end

function W.HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- Keeps the row highlighted while the mouse is over any part of it. A control
-- on a plain frame (the preview strip's Zoom) has no row.
function W.Hover(row, frame)
    if not (row.Enter and row.Leave) then return end
    frame:HookScript("OnEnter", row.Enter)
    frame:HookScript("OnLeave", row.Leave)
end

-- The standard text button: black outline, warm band, dark fill lit along
-- the top. Drawn with plain textures and no masks, so it stays cheap.
-- On hover the band traces in the accent from the top-left corner around to
-- the bottom-right, and draws back on leave. Pressed darkens the fill.
-- SetActive keeps the band fully lit, b.main gives a footer's main action a
-- brighter band, SetOff dims it and blocks clicks. Every click plays a sound.
W.BUTTON = {
    outline = Style.BORDER,
    band = { 0.10, 0.09, 0.063 },
    bandMain = { 0.2, 0.172, 0.118 },
    bandOff = { 0.07, 0.066, 0.055 },
    fillTop = { 0.11, 0.1, 0.086 },
    fillBottom = { 0.071, 0.071, 0.078 },
    lit = { 1, 0.94, 0.84, 0.08 },
    text = Style.INK.TEXT,
    gleam = { size = 10, alpha = 0.9, color = { 1, 0.95, 0.85 } },   -- the light on each tracing end
}
local BTN = W.BUTTON
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function vertical(tex, top, bottom)
    W.Tint(tex, { 1, 1, 1 })
    if tex.SetGradient and CreateColor then
        tex:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    else
        W.Tint(tex, top)
    end
end

-- Color at t (0 left, 1 right) along a gradient accent.
local function accentAt(lo, hi, t)
    if not lo then return { Style.Accent() } end
    return { lo[1] + (hi[1] - lo[1]) * t, lo[2] + (hi[2] - lo[2]) * t, lo[3] + (hi[3] - lo[3]) * t }
end

-- A horizontal piece from x0 to x1 (fractions of the width) in its slice of the accent.
local function across(tex, lo, hi, x0, x1)
    local a, z = accentAt(lo, hi, x0), accentAt(lo, hi, x1)
    if lo and tex.SetGradient and CreateColor then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(z[1], z[2], z[3], 1))
    else
        tex:SetVertexColor(a[1], a[2], a[3], 1)
    end
end

-- Lit buttons repaint when the accent changes.
local buttons = setmetatable({}, { __mode = "k" })
DUI.On("StyleChanged", function()
    for b in pairs(buttons) do
        if b.trace.p > 0 and b:IsVisible() then b.trace.Draw(b.trace.p) end
    end
end)

-- The hover trace, shared by our buttons and the game buttons the skins
-- dress. Four border strips inset px in and thick px wide grow from the
-- top-left corner, one along the top and down the right, one down the left
-- and along the bottom, meeting bottom-right. It's only textures and a tween,
-- no scripts, so it can sit on a game button driven from HookScript.
-- tr.To(on) eases on (NORMAL) or off (FAST), tr.Snap(p) jumps, tr.p is the
-- current progress. layer defaults to BORDER; use OVERLAY over a game
-- button's own border. quiet: no size hook on the frame (see W.ButtonLook);
-- the trace is then redrawn at the new size the next time it moves.
function W.Trace(frame, inset, thick, layer, quiet)
    local tr = { p = 0 }
    for _, key in ipairs({ "top", "right", "left", "bottom" }) do
        local t = frame:CreateTexture(nil, layer or "BORDER", nil, 6)
        t:SetTexture(WHITE)
        t:Hide()
        tr[key] = t
    end
    tr.top:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    tr.top:SetHeight(thick)
    tr.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    tr.right:SetWidth(thick)
    tr.left:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    tr.left:SetWidth(thick)
    tr.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    tr.bottom:SetHeight(thick)
    tr.gleams = {}
    local G = BTN.gleam
    for i = 1, 2 do
        local g = frame:CreateTexture(nil, layer or "BORDER", nil, 7)
        g:SetTexture(MEDIA .. "glow.png")
        g:SetBlendMode("ADD")
        g:SetSize(G.size, G.size)
        g:SetVertexColor(G.color[1], G.color[2], G.color[3], 1)
        g:Hide()
        tr.gleams[i] = g
    end
    local function size(t, w, h)
        local show = (w or h) > 0.01
        t:SetShown(show)
        if show then
            if w then t:SetWidth(w) else t:SetHeight(h) end
        end
    end
    -- p: 0 dark to 1 fully traced. gleam: show the lights on the running ends.
    function tr.Draw(p, gleam)
        tr.p = p
        local w, h = frame:GetWidth(), frame:GetHeight()
        if type(w) ~= "number" or type(h) ~= "number" then return end
        w, h = w - 2 * inset, h - 2 * inset
        if w <= 0 or h <= 0 then return end
        local d = p * (w + h)
        local topW, rightH = math.min(d, w), math.max(0, math.min(d - w, h))
        local leftH, bottomW = math.min(d, h), math.max(0, math.min(d - h, w))
        size(tr.top, topW)
        size(tr.right, nil, rightH)
        size(tr.left, nil, leftH)
        size(tr.bottom, bottomW)
        local lo, hi
        if CreateColor then lo, hi = Style.AccentPair() end
        across(tr.top, lo, hi, 0, topW / w)
        across(tr.bottom, lo, hi, 0, bottomW / w)
        local l, r = accentAt(lo, hi, 0), accentAt(lo, hi, 1)
        tr.left:SetVertexColor(l[1], l[2], l[3], 1)
        tr.right:SetVertexColor(r[1], r[2], r[3], 1)
        -- The end lights appear at once and go out when the two ends meet.
        local a = gleam and math.min(1, (1 - p) * 4) * G.alpha or 0
        for i, g in ipairs(tr.gleams) do
            g:SetShown(a > 0)
            if a > 0 then
                g:SetAlpha(a)
                g:ClearAllPoints()
                if i == 1 then
                    if d <= w then g:SetPoint("CENTER", frame, "TOPLEFT", inset + d, -inset - thick / 2)
                    else g:SetPoint("CENTER", frame, "TOPRIGHT", -inset - thick / 2, -inset - rightH) end
                else
                    if d <= h then g:SetPoint("CENTER", frame, "TOPLEFT", inset + thick / 2, -inset - d)
                    else g:SetPoint("CENTER", frame, "BOTTOMLEFT", inset + bottomW, inset + thick / 2) end
                end
            end
        end
    end
    function tr.To(on)
        local goal = on and 1 or 0
        if goal == tr.p then return end
        local M = DUI.Motion
        if M then
            M.Tween(tr, tr.p, goal, goal == 1 and M.NORMAL or M.FAST, function(p) tr.Draw(p, goal == 1) end)
        else
            tr.Draw(goal)
        end
    end
    function tr.Snap(p)
        if DUI.Motion then DUI.Motion.Tween(tr, tr.p, tr.p, 0) end
        tr.Draw(p)
    end
    -- Redraw at the new size.
    if frame.HookScript and not quiet then
        frame:HookScript("OnSizeChanged", function() if tr.p > 0 then tr.Draw(tr.p) end end)
    end
    return tr
end

function W.Button(parent, text, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(height or 24)
    return W.DressButton(b, text)
end

-- A button that opens a menu: W.Button with its label on the left and a
-- chevron on the right. b.SetLabel(text, min) sizes it to the text (at least
-- min, default W.MENU_BUTTON_MIN) and fades new text in. Caller sets OnClick.
W.MENU_BUTTON_MIN = 110
function W.MenuButton(parent, text, h)
    local b = W.Button(parent, "", h or 24)
    b.chevron = W.Icon(b, "ui-chevron.png", 10, Style.INK.LABEL)
    b.chevron:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.text:SetJustifyH("LEFT")
    function b.SetLabel(words, min)
        local was = b.text:GetText()
        b.text:SetText(words or "")
        local w = b.text:GetStringWidth()
        if type(w) ~= "number" then w = 60 end
        b:SetWidth(math.max(min or W.MENU_BUTTON_MIN, math.ceil(w) + 12 + 10 + 10 + 8))
        local M = DUI.Motion
        if M and was and was ~= "" and was ~= words and b:IsVisible() then M.Fade(b.text, 0, 1, M.FAST) end
    end
    b.SetLabel(text)
    return b
end

-- Just the button look: layers, trace and resting paint, stored on s. For our
-- buttons s is the button. For a game button (Kit.Button) it's a separate
-- table so nothing gets written onto the game's frame. text is an existing
-- font string to reuse, or nil to make one. No scripts: the caller drives
-- s.Hover, and sets s.down / s.off before calling s.Paint.
-- quiet: no show, hide or size hooks either. A game frame's Show, Hide and
-- resizing run those hooks inside the game's own code, which they taint, so
-- the caller then resets the look with s.Rest when the button goes away.
function W.ButtonLook(b, s, text, quiet)
    s = s or b
    local px = DUI.Pixel.Px
    local one, band = px(b, 1), px(b, 3)
    local T = band - one
    local function layer(sub, inset)
        local t = b:CreateTexture(nil, "BACKGROUND", nil, sub)
        t:SetTexture(WHITE)
        t:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
        return t
    end
    s.outline = layer(-8, 0)
    W.Tint(s.outline, BTN.outline)
    s.band = layer(-7, one)
    s.fill = layer(-6, band)
    s.lit = b:CreateTexture(nil, "BACKGROUND", nil, -5)
    s.lit:SetTexture(WHITE)
    s.lit:SetPoint("TOPLEFT", s.fill, "TOPLEFT", 0, 0)
    s.lit:SetPoint("TOPRIGHT", s.fill, "TOPRIGHT", 0, 0)
    s.lit:SetHeight(one)
    W.Tint(s.lit, BTN.lit)
    local tr = W.Trace(b, one, T, nil, quiet)
    s.trace = tr
    function s.Draw(p) tr.Draw(p) end
    -- Trace on (hovered or active) or back off.
    function s.Light(on) tr.To((on or s.active) and not s.off) end
    if text then
        s.text = text
    else
        s.text = W.Font(b, W.BODY, SIZE.body, BTN.text, "CENTER")
        s.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    function s.Paint()
        W.Tint(s.band, (s.off and BTN.bandOff) or (s.main and BTN.bandMain) or BTN.band)
        if s.down and not s.off then vertical(s.fill, BTN.fillBottom, BTN.fillTop)
        else vertical(s.fill, BTN.fillTop, BTN.fillBottom) end
        s.lit:SetShown(not s.down)
        if s.text then s.text:SetAlpha(s.off and 0.45 or 1) end
    end
    -- Mouse entered or left. Callers with their own OnEnter call this.
    function s.Hover(on)
        if not on then s.down = false; s.Paint() end
        s.Light(on)
    end
    -- Hidden mid-trace gets no OnLeave, so reset to rest (or fully lit if active,
    -- in case the accent changed meanwhile).
    function s.Rest()
        s.down = false
        tr.Snap((s.active and not s.off) and 1 or 0)
    end
    if not quiet then
        b:HookScript("OnHide", s.Rest)
        b:HookScript("OnShow", function() if tr.p > 0 then tr.Draw(tr.p) end end)
    end
    s.Paint()
    return s
end

-- The same look on a button from a game template whose OnClick belongs to the
-- game (the bank's Buy tab). Sets the mouse and size scripts, never OnClick.
function W.DressButton(b, text)
    buttons[b] = true
    W.ButtonLook(b)
    b.text:SetText(text or "")
    b:SetScript("OnEnter", function() b.Hover(true) end)
    b:SetScript("OnLeave", function() b.Hover(false) end)
    b:SetScript("OnMouseDown", function() b.down = true; b.Paint() end)
    b:SetScript("OnMouseUp", function() b.down = false; b.Paint() end)
    -- PostClick, because callers set OnClick and that would drop a hook. A
    -- template's own PostClick is kept.
    local function click() if DUI.Sound then DUI.Sound.Play("click") end end
    if b:GetScript("PostClick") then b:HookScript("PostClick", click) else b:SetScript("PostClick", click) end
    function b.SetActive(on)
        b.active = on
        b.Light(b:IsMouseOver() == true)
        W.TextColor(b.text, on and C.value or BTN.text)
    end
    -- Off: dimmed and ignores clicks.
    function b.SetOff(on)
        b.off = on and true or nil
        b:SetEnabled(not on)
        b.Paint()
        b.Light(not on and b:IsMouseOver() == true)
    end
    function b.FitWidth(min)
        local w = b.text:GetStringWidth()
        if type(w) ~= "number" then w = 60 end
        b:SetWidth(math.max(min or 90, w + 32))
    end
    return b
end

-- The standard text link: quiet text that turns the accent on hover while a
-- thin underline grows from the left. opts.own keeps the text's own colors
-- (a gradient name like the options window's Discord link), slightly dim at
-- rest. b.SetLabel(text) sizes it. Caller sets OnClick; the sound is built in.
W.LINK_DIM = 0.8   -- an own-colored link's alpha at rest
function W.Link(parent, size, opts)
    local own = opts and opts.own
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(20)
    b.text = W.Font(b, W.BODY, size or SIZE.small, C.faint)
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    if own then b.text:SetAlpha(W.LINK_DIM) end
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetTexture(WHITE)
    b.line:SetHeight(1)
    b.line:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -2)
    b.line:SetWidth(0.01)
    b.line:Hide()
    local at = 0
    -- p: 0 at rest, 1 hovered. Drives the underline length and either the text
    -- color or, with own colors, its alpha.
    local function draw(p)
        at = p
        b.line:SetShown(p > 0.01)
        b.line:SetWidth(math.max(0.01, (b:GetWidth() or 0) * p))
        Style.PaintAccent(b.line, 0.8)
        if own then
            b.text:SetAlpha(W.LINK_DIM + (1 - W.LINK_DIM) * p)
        else
            local r, g, bl = Style.Accent()
            local f = C.faint
            b.text:SetTextColor(f[1] + (r - f[1]) * p, f[2] + (g - f[2]) * p, f[3] + (bl - f[3]) * p, 1)
        end
    end
    local function hover(on)
        local M = DUI.Motion
        if M then M.Tween(b.line, at, on and 1 or 0, M.FAST, draw) else draw(on and 1 or 0) end
    end
    function b.SetLabel(text)
        b.text:SetText(text or "")
        local w = b.text:GetStringWidth()
        b:SetWidth(type(w) == "number" and w > 0 and w or 200)
    end
    b:SetScript("OnEnter", function() hover(true) end)
    b:SetScript("OnLeave", function() hover(false) end)
    b:SetScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
    return b
end

-- The standard close X: tan at rest, accent on hover, dimmer when pressed,
-- plays the click sound. size is the hit box (24), icon the drawn X (12).
-- The caller places it.
W.CLOSE, W.CLOSE_ICON = 24, 12
-- The hit box reaches REACH past the art on every side except the left, where
-- a header icon sits HEADER_ICON_GAP away. Players kept missing it when
-- closing loot windows.
W.CLOSE_REACH, W.CLOSE_REACH_LEFT = 6, 2
function W.CloseReach(b)
    local function reach() b:SetHitRectInsets(-W.CLOSE_REACH_LEFT, -W.CLOSE_REACH, -W.CLOSE_REACH, -W.CLOSE_REACH) end
    if b.IsProtected and b:IsProtected() and InCombatLockdown() then DUI.AfterCombat(reach, b) else reach() end
end

-- Removes a frame from the gamepad cursor's stops: the X (B already closes)
-- and scroll bars (the game treats anything with OnMouseDown as a stop and
-- parked the cursor on the bar). Goes through the game's own call because a
-- hand-written field would taint. Controller UI only, out of combat.
function W.PadSkip(f)
    if not (DUI.Pad and DUI.Pad.On()) or type(SmartNavigation_MarkFrameIgnored) ~= "function" then return end
    DUI.AfterCombat(function() SmartNavigation_MarkFrameIgnored(f) end, f)
end

-- Puts a wide stop's anchor near its left edge instead of its middle, so
-- pressing right from a list's left column goes to the next column rather
-- than up to a heading. The game's Settings lists do the same with a custom
-- cursor anchor.
function W.PadSpot(f)
    if not (DUI.Pad and DUI.Pad.On()) or type(SmartNavigation_SetCustomCursorAnchorPointForFrame) ~= "function" then return end
    local spot = f:CreateTexture(nil, "BACKGROUND")
    spot:SetSize(2, 2)
    spot:SetPoint("LEFT", f, "LEFT", 2, 0)
    DUI.AfterCombat(function()
        SmartNavigation_SetCustomCursorAnchorPointForFrame(f, CreateAnchor("RIGHT", spot, "CENTER", -4, 0))
    end, spot)
end

-- Gamepad support for an options row, matching the game's Settings rows: the
-- whole row is one stop and the control inside is skipped. Selected, it
-- highlights like a hover and shows its tooltip. A acts like a click, left
-- and right step a slider or dropdown (with repeat), Y resets. The game calls
-- OnSmartNavSelect/Deselect/Click through its secure wrapper. The marks are
-- set through the game's setters out of combat, and added later if the
-- controller UI is turned on after the row was built.
W.PAD_ROW = { toggle = true, slider = true, dropdown = true, color = true, button = true, gradient = true }
local padWaiting = setmetatable({}, { __mode = "k" })

local function padMarks(row)
    if type(SmartNavigation_MarkFrameFocusable) ~= "function" then
        padWaiting[row] = true
        return
    end
    padWaiting[row] = nil
    if not row.padSpot then
        row.padSpot = row:CreateTexture(nil, "BACKGROUND")
        row.padSpot:SetSize(2, 2)
        row.padSpot:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
    end
    DUI.AfterCombat(function()
        SmartNavigation_MarkFrameFocusable(row)
        for _, f in ipairs({ row.control, row.reset }) do SmartNavigation_MarkFrameIgnored(f) end
        if type(SmartNavigation_SetCustomCursorAnchorPointForFrame) == "function" and CreateAnchor then
            SmartNavigation_SetCustomCursorAnchorPointForFrame(row, CreateAnchor("RIGHT", row.padSpot, "CENTER", -4, 0))
        end
    end, row)
end

if DUI.On then
    DUI.On("PadChanged", function()
        for row in pairs(padWaiting) do padMarks(row) end
    end)
end

-- One step of a slider row, clamped to its range.
function W.PadSlide(row, dir)
    local item, page = row.item, row.page
    if row.disabled then return end
    local v = Options.Get(page, item)
    if type(v) ~= "number" then v = item.min end
    local to = W.SnapValue(item, math.max(item.min, math.min(item.max, v + dir * (item.step or 1))))
    if to ~= v then Options.Set(page, item, to) end
end

-- A row on a controller is one stop and the D-pad moves freely between rows.
-- A acts on it: flips a switch, opens a dropdown's list or a color, presses a
-- button, and picks up a slider. A picked slider takes left and right (held
-- repeats) until A or B puts it down, or the D-pad leaves.
function W.PadRow(row)
    local item, c = row.item, row.control
    if not (c and W.PAD_ROW[item.type]) then return end
    row.padRow = true
    local function stopEditing()
        if not row.padEditing then return end
        row.padEditing = nil
        DUI.Pad.FreeSides(row.padStep)
    end
    if item.type == "slider" then
        row.padStep = function(dir) W.PadSlide(row, dir) end
        row.padA = function()
            if row.padEditing then return stopEditing() end
            row.padEditing = true
            DUI.Pad.HoldSides(row.padStep, stopEditing)
        end
    elseif item.type == "gradient" then
        row.padA = function() c.lo:Click() end
        row.padX = function() c.hi:Click() end
    else
        row.padA = function() c:Click() end
    end
    function row.OnSmartNavSelect()
        row.padOn = true
        if DUI.OptionsPanel and DUI.OptionsPanel.PadAim then DUI.OptionsPanel.PadAim(row) end
        row.Enter()
    end
    function row.OnSmartNavDeselect()
        row.padOn = nil
        stopEditing()
        row.Leave()
    end
    function row.OnSmartNavClick()
        if row.padA and not row.disabled then row.padA() end
    end
    padMarks(row)
end

function W.Close(parent, onClick, size, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or W.CLOSE, size or W.CLOSE)
    W.CloseReach(b)
    W.PadSkip(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(MEDIA .. "ui-close.png")
    b.icon:SetSize(icon or W.CLOSE_ICON, icon or W.CLOSE_ICON)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    function b.Paint(over)
        if over then W.Tint(b.icon, { Style.Accent() }) else W.Tint(b.icon, Style.INK.LABEL) end
        b.icon:SetAlpha(b.down and 0.6 or 1)
    end
    b:SetScript("OnEnter", function() b.Paint(true) end)
    b:SetScript("OnLeave", function() b.down = false; b.Paint(false) end)
    b:SetScript("OnMouseDown", function() b.down = true; b.Paint(true) end)
    b:SetScript("OnMouseUp", function() b.down = false; b.Paint(b:IsMouseOver() == true) end)
    b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    b:SetScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
    b.Paint(false)
    return b
end

-- Puts the W.Close look on a game template's close button and keeps the
-- game's click. Hides the game's art and uses HookScript so the template's
-- scripts survive. Size and position stay the game's (it measures titles
-- against them). The X is kept in our own table, not as a field on the
-- button, which would show up as taint. Calling it again returns the same X.
local dressedClose = setmetatable({}, { __mode = "k" })
function W.DressClose(b)
    if dressedClose[b] then return dressedClose[b] end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local art = b[get] and b[get](b)
        if art then art:SetAlpha(0) end
    end
    for _, r in ipairs({ b:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    W.CloseReach(b)
    local x = b:CreateTexture(nil, "OVERLAY")
    dressedClose[b] = x
    x:SetTexture(MEDIA .. "ui-close.png")
    x:SetSize(W.CLOSE_ICON, W.CLOSE_ICON)
    x:SetPoint("CENTER", b, "CENTER", 0, 0)
    local down = false
    local function paint(over)
        if over then W.Tint(x, { Style.Accent() }) else W.Tint(x, Style.INK.LABEL) end
        x:SetAlpha(down and 0.6 or 1)
    end
    b:HookScript("OnEnter", function() paint(true) end)
    b:HookScript("OnLeave", function() down = false; paint(false) end)
    b:HookScript("OnMouseDown", function() down = true; paint(true) end)
    b:HookScript("OnMouseUp", function() down = false; paint(b:IsMouseOver() == true) end)
    b:HookScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
    paint(false)
    return x
end

-- Small round map button (the world map's quick menu, where the game's
-- filter button was): dark disc, warm rim, tan icon that turns the accent on
-- hover along with the rim, shrinks a bit when pressed. icon is a Media file.
-- The caller places it.
W.MAP_BUTTON, W.MAP_BUTTON_ICON = 26, 14
function W.MapButton(parent, icon, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(W.MAP_BUTTON, W.MAP_BUTTON)
    b.disc = W.Round(b, "BACKGROUND")
    b.disc:SetAllPoints(b)
    W.Tint(b.disc, Style.BACKGROUND, 0.9)
    b.rim = W.Round(b, "BORDER", 0, true)
    b.rim:SetAllPoints(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(MEDIA .. icon)
    b.icon:SetSize(W.MAP_BUTTON_ICON, W.MAP_BUTTON_ICON)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    function b.Paint(over)
        if over then
            W.Tint(b.icon, { Style.Accent() })
            W.Tint(b.rim, { Style.Accent() }, 0.9)
        else
            W.Tint(b.icon, Style.INK.LABEL)
            W.Tint(b.rim, Style.BORDER, 0.9)
        end
    end
    b:SetScript("OnEnter", function() b.Paint(true) end)
    b:SetScript("OnLeave", function() b.Paint(false) end)
    b:SetScript("OnMouseDown", function() DUI.Motion.Bump(b.icon, 0.88) end)
    b:SetScript("OnClick", function(self, button) if onClick then onClick(self, button) end end)
    b:SetScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
    b.Paint(false)
    return b
end

-- A bare icon used as a button (chat header: whispers, copy, lock, options).
-- Tan at rest, accent on hover, a small bump when pressed, click sound and
-- tooltip. icon is a Media file, tip is text or a function returning text,
-- size is the hit box (W.ICON_BUTTON, icon drawn at 14). b.SetIcon(file)
-- swaps the icon, e.g. the lock's open and closed states.
W.ICON_BUTTON, W.ICON_BUTTON_ICON = 20, 14
W.ICON_TIP_WAIT = 1   -- seconds the mouse rests on an icon before its name shows
function W.IconButton(parent, icon, tip, onClick, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or W.ICON_BUTTON, size or W.ICON_BUTTON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(W.ICON_BUTTON_ICON, W.ICON_BUTTON_ICON)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    function b.SetIcon(file) b.icon:SetTexture(MEDIA .. file) end
    b.SetIcon(icon)
    b.over = 0
    local function paint(p)
        b.over = p
        local lo, r, g, bl = Style.INK.LABEL, Style.Accent()
        b.icon:SetVertexColor(lo[1] + (r - lo[1]) * p, lo[2] + (g - lo[2]) * p, lo[3] + (bl - lo[3]) * p, 1)
    end
    function b.Paint(over)
        local M = DUI.Motion
        if M then M.Tween(b.icon, b.over, over and 1 or 0, M.FAST, paint) else paint(over and 1 or 0) end
    end
    -- Name shows only after a short rest (W.ICON_TIP_WAIT), so sweeping across
    -- the icons doesn't flash tooltips.
    local token = 0
    b:SetScript("OnEnter", function(self)
        b.Paint(true)
        token = token + 1
        local mine = token
        C_Timer.After(W.ICON_TIP_WAIT, function()
            if mine ~= token or not self:IsMouseOver() then return end
            local words = type(tip) == "function" and tip() or tip
            if words and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                DUI.Tips.Clear()
                DUI.Tips.Title(words)
                DUI.Tips.Flush()
                GameTooltip:Show()
            end
        end)
    end)
    b:SetScript("OnLeave", function(self)
        b.Paint(false)
        token = token + 1
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    b:SetScript("OnMouseDown", function() DUI.Motion.Bump(b.icon, 0.85) end)
    b:SetScript("OnClick", function(self, button) if onClick then onClick(self, button) end end)
    b:SetScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
    paint(0)
    return b
end

-- The standard text box for searches, names and numbers: rounded dark box,
-- outline easing to the accent (half on hover, full while focused).
-- opts: height (W.INPUT_H), size (13), justify ("LEFT"), hint (placeholder),
-- search (magnifier on the left, clear X on the right; Escape clears first,
-- then leaves), maxLetters, numeric, onChange(text, userInput).
-- Enter and Escape drop focus, and a caller may SetScript those. The box owns
-- OnTextChanged, focus and OnEnter/OnLeave: use HookScript for those, and
-- onChange for typing. The caller sizes and places it.
W.INPUT_H = 26
local inputs = setmetatable({}, { __mode = "k" })   -- box -> its look
DUI.On("StyleChanged", function()
    for e, s in pairs(inputs) do if s.glow > 0 and e:IsVisible() then s.Paint() end end
end)

-- Just the box look: background, outline and accent outline, stored on s.
-- For a game edit box (Kit.EditBox) s is a separate table so nothing is
-- written on the game's frame. pad widens the box past the frame on both
-- sides, for game boxes whose text starts at the edge. No scripts: the caller
-- calls s.Ease() on hover and focus changes and s.Rest() on hide.
function W.InputLook(e, s, pad)
    s = s or e
    pad = pad or 0
    inputs[e] = s
    local function place(t)
        t:SetPoint("TOPLEFT", e, "TOPLEFT", -pad, 0)
        t:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", pad, 0)
    end
    s.bg = W.Round(e, "BACKGROUND")
    place(s.bg)
    W.Tint(s.bg, C.control)
    s.edge = W.Round(e, "BORDER", 0, true)
    place(s.edge)
    W.Tint(s.edge, C.cardEdge)
    s.lit = W.Round(e, "BORDER", 1, true)
    place(s.lit)
    -- Outline: 0 at rest, half on hover, full when focused. Done through the
    -- tint's alpha, because in game a gradient ignores SetAlpha.
    s.glow = 0
    function s.Paint()
        Style.PaintAccent(s.lit, s.glow)
    end
    function s.Ease()
        local to = (e:HasFocus() and 1) or (e:IsMouseOver() and 0.5) or 0
        local M = DUI.Motion
        if M then
            M.Tween(s.lit, s.glow, to, M.FAST, function(v) s.glow = v; s.Paint() end)
        else
            s.glow = to
            s.Paint()
        end
    end
    function s.Rest()
        if DUI.Motion then DUI.Motion.Tween(s.lit, s.glow, 0, 0) end
        s.glow = 0
        s.Paint()
    end
    s.Paint()
    return s
end

function W.Input(parent, opts)
    opts = opts or {}
    local h, size = opts.height or W.INPUT_H, opts.size or SIZE.body
    local e = CreateFrame("EditBox", nil, parent)
    inputs[e] = true
    e:SetHeight(h)
    e:SetAutoFocus(false)
    e:SetFont(W.BODY, size, "")
    W.TrackFont(e, W.BODY, size)
    W.TextColor(e, C.text)
    e:SetJustifyH(opts.justify or "LEFT")
    if opts.maxLetters then e:SetMaxLetters(opts.maxLetters) end
    if opts.numeric then e:SetNumeric(true) end
    local left = opts.search and 26 or 10
    local right = opts.search and 22 or 10
    if opts.justify == "CENTER" then left, right = 4, 4 end
    e:SetTextInsets(left, right, 0, 0)
    W.InputLook(e)
    if opts.search then
        e.isSearch = true   -- the controller's left menu button finds it (Pad.FindParts)
        e.icon = W.Icon(e, "ui-search.png", 13, C.faint)
        e.icon:SetPoint("LEFT", e, "LEFT", 8, 0)
        local s = math.min(18, h - 6)
        e.clear = W.Close(e, function()
            e:SetText("")
            e:ClearFocus()
        end, s, 10)
        e.clear:SetPoint("RIGHT", e, "RIGHT", -4, 0)
        e.clear:Hide()
    end
    e.hint = W.Font(e, W.BODY, size, C.faint, opts.justify)
    if opts.justify == "CENTER" then e.hint:SetPoint("CENTER", e, "CENTER", 0, 0)
    else
        e.hint:SetPoint("LEFT", e, "LEFT", left, 0)
        e.hint:SetPoint("RIGHT", e, "RIGHT", -right, 0)   -- a narrow box cuts it short
    end
    e.hint:SetText(opts.hint or "")
    e:SetScript("OnEnter", e.Ease)
    e:SetScript("OnLeave", e.Ease)
    e:SetScript("OnEditFocusGained", e.Ease)
    e:SetScript("OnEditFocusLost", e.Ease)
    e:SetScript("OnHide", e.Rest)
    e:SetScript("OnTextChanged", function(self, user)
        local text = self:GetText() or ""
        self.hint:SetShown(text == "")
        if self.clear then self.clear:SetShown(text ~= "") end
        if opts.onChange then opts.onChange(text, user) end
    end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self)
        if opts.search and (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    return e
end

-- Multi-line text box: scrollable text to select and copy or paste into,
-- in W.Input's box with our scroll bar. The caller places the area (a
-- ScrollFrame); the edit box is area.edit.
-- opts: width (text width), step (px per wheel notch), onEscape(edit),
-- follow (stick to the newest line as text grows), hint (area.hint),
-- maxLetters. area.Lock(text, select) makes it read-only, restoring text
-- after any edit (selected if select). area.Lock(nil) unlocks it.
W.TEXTAREA_EDGE_MIN, W.TEXTAREA_EDGE_MAX = 60, 900   -- px a second, scrolling past an edge

-- Scrolls a W.TextArea just enough to bring the span from top to bottom
-- (px down from the text's top) into view.
function W.TextAreaShow(area, top, bottom)
    local at, view = area:GetVerticalScroll() or 0, area:GetHeight() or 0
    if view <= 0 then return end
    local to = at
    if top < at then to = top elseif bottom > at + view then to = bottom - view end
    to = math.max(0, math.min(area:GetVerticalScrollRange() or 0, to))
    if to ~= at then area:SetVerticalScroll(to); area.bar.Update() end
end

function W.TextArea(parent, opts)
    opts = opts or {}
    local area = CreateFrame("ScrollFrame", nil, parent)
    area:SetClipsChildren(true)
    area.bg = W.Round(area, "BACKGROUND")
    area.bg:SetPoint("TOPLEFT", area, "TOPLEFT", -6, 6)
    area.bg:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 6, -6)
    W.Tint(area.bg, C.control)
    local edit = CreateFrame("EditBox", nil, area)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(W.BODY, SIZE.body, "")
    W.TrackFont(edit, W.BODY, SIZE.body)
    W.TextColor(edit, C.text)
    edit:SetWidth(opts.width or 400)
    if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end
    -- Placeholder like W.Input's, hidden once there's text.
    local function changed(self)
        if area.hint then area.hint:SetShown((self:GetText() or "") == "") end
    end
    if opts.hint then
        area.hint = W.Font(area, W.BODY, SIZE.body, C.faint, "LEFT")
        area.hint:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
        area.hint:SetText(opts.hint)
        edit:SetScript("OnTextChanged", changed)
    end
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if opts.onEscape then opts.onEscape(self) end
    end)
    area:SetScrollChild(edit)
    area:EnableMouse(true)
    area:SetScript("OnMouseDown", function() edit:SetFocus() end)
    area.bar = W.Scroll(area, { step = opts.step, read = function()
        return area:GetVerticalScroll() or 0, area:GetVerticalScrollRange() or 0, area:GetHeight() or 0
    end })
    -- The game measures new text a frame after SetText, so the scroll range only
    -- grows then. Follow it down to the newest line when asked.
    area:SetScript("OnScrollRangeChanged", function(self, _, yRange)
        if opts.follow then self:SetVerticalScroll(yRange or 0) end
        self.bar.Update()
    end)
    -- Keep the cursor in view. y is its line's top below the text's top (0 or
    -- less), h its height.
    edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
        if type(y) ~= "number" or type(h) ~= "number" then return end
        W.TextAreaShow(area, -y, -y + h)
    end)
    -- Dragging a selection past the top or bottom edge keeps scrolling, faster
    -- the farther out the mouse is. Runs only while the button is held.
    local function edge(self, elapsed)
        if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil); return end
        local s = self:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        cy = cy / s
        local top, bottom = self:GetTop(), self:GetBottom()
        if not (top and bottom) then return end
        local d = cy > top and -(cy - top) or (cy < bottom and bottom - cy or 0)
        if d == 0 then return end
        local speed = math.min(W.TEXTAREA_EDGE_MAX, math.max(W.TEXTAREA_EDGE_MIN, math.abs(d) * 10))
        local v = (self:GetVerticalScroll() or 0) + (d < 0 and -1 or 1) * speed * elapsed
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange() or 0, v)))
        self.bar.Update()
    end
    edit:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then area:SetScript("OnUpdate", edge) end
    end)
    edit:HookScript("OnMouseUp", function() area:SetScript("OnUpdate", nil) end)
    function area.Lock(text, select)
        if text == nil then edit:SetScript("OnTextChanged", opts.hint and changed or nil); return end
        edit:SetScript("OnTextChanged", function(self, user)
            changed(self)
            if user then
                self:SetText(text)
                if select then self:HighlightText() end
            end
        end)
    end
    area.edit = edit
    return area
end

-- The standard text tab (spellbook pages, character, shop, bank, talent
-- sets): tan at rest, light on hover, accent when picked, with an underline
-- that grows from the middle. Clicking another tab plays the click sound.
-- opts: size (13), justify ("CENTER"), inset (room left of the line),
-- paintLine(tex) to color the line (default: the accent). The caller sizes,
-- places and sets OnClick. b.Pick(on) paints it, b.SetOff(on) dims it and
-- blocks clicks.
W.TAB_H = 24

-- Just the tab look: text colors and underline, stored on s. For a game tab
-- (Kit.Tab) s is a separate table so nothing is written on the game's frame.
-- text is the tab's font string. opts as W.Tab plus under, which puts the
-- line right under the text instead of at the tab's bottom. Only a resize
-- hook; the caller drives s.Paint(over) and s.Pick(on, animate). s.off dims it.
function W.TabLook(b, s, text, opts)
    s = s or b
    opts = opts or {}
    s.text = text
    local inset = opts.inset or 0
    s.line = b:CreateTexture(nil, "ARTWORK")
    s.line:SetTexture(WHITE)
    s.line:SetHeight(2)
    if opts.under then s.line:SetPoint("TOP", text, "BOTTOM", 0, -opts.under)
    else s.line:SetPoint("BOTTOM", b, "BOTTOM", inset / 2, 0) end
    s.line:Hide()
    local function full() return math.max(0.01, (b:GetWidth() or 0) - inset) end
    function s.Paint(over)
        if s.off then Style.InkText(s.text, "OFF")
        elseif s.picked then Style.InkText(s.text, "pop")
        else Style.InkText(s.text, over and "VALUE" or "LABEL") end
        s.line:SetShown(s.picked == true)
        if s.picked then (opts.paintLine or function(t) Style.PaintAccent(t, 1) end)(s.line) end
    end
    -- animate: grow the line in. Used for player clicks, not refills.
    function s.Pick(on, animate)
        local was = s.picked
        s.picked = on and true or nil
        s.Paint(b:IsMouseOver() == true)
        if not on then return end
        local M = DUI.Motion
        if animate and not was and M and M.On() then
            local w = full()
            M.Tween(s.line, 0, 1, M.FAST, function(p) s.line:SetWidth(math.max(0.01, w * p)) end)
        elseif not was then
            s.line:SetWidth(full())
        end
    end
    b:HookScript("OnSizeChanged", function() if s.picked then s.line:SetWidth(full()) end end)
    return s
end

function W.Tab(parent, text, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(W.TAB_H)
    b.text = Style.Text(b, opts.size or SIZE.body, opts.justify or "CENTER")
    if (opts.justify or "CENTER") == "CENTER" then b.text:SetPoint("CENTER", b, "CENTER", 0, 1)
    else b.text:SetPoint(opts.justify, b, opts.justify, opts.inset or 0, 1) end
    b.text:SetText(text or "")
    W.TabLook(b, b, b.text, opts)
    function b.SetOff(on)
        b.off = on and true or nil
        b:SetEnabled(not on)
        b.Paint(false)
    end
    -- Width fits the text plus padding. The line follows resizes.
    function b.FitWidth(pad, min)
        local w = b.text:GetStringWidth()
        if type(w) ~= "number" then w = 40 end
        b:SetWidth(math.max(min or 24, math.ceil(w) + (pad or 4) + (opts.inset or 0)))
    end
    b:SetScript("OnEnter", function() b.Paint(true) end)
    b:SetScript("OnLeave", function() b.Paint(false) end)
    b:SetScript("PreClick", function() b.fresh = not b.picked end)
    b:SetScript("PostClick", function() if b.fresh and DUI.Sound then DUI.Sound.Play("click") end end)
    b.Paint(false)
    return b
end

-- Column headers over a list (Parts.Table): small tan labels, white on hover,
-- the sorted column in the accent with a chevron (up ascending, down
-- descending), with a faint rule underneath. Color changes ease FAST.
-- cols: { { id, text, width (px) or fill = true, justify = "LEFT"|"RIGHT",
-- sort = true } }. Clicking a sortable column calls onSort(id, descending):
-- a new column starts ascending, the same one flips. head:SetSort(id,
-- descending) paints without calling back. head:Layout(width) places the
-- labels and returns { [id] = { x, w } }. Fill columns split the leftover
-- width and the last one takes the rounding. head.cells[id] is the button
-- (.text, .arrow).
W.COLUMN_H, W.COLUMN_GAP, W.SORT_ARROW = 22, 8, 10
local heads = setmetatable({}, { __mode = "k" })

function W.ColumnHead(parent, cols, onSort)
    local head = CreateFrame("Frame", nil, parent)
    head:SetHeight(W.COLUMN_H)
    head.cols, head.cells = cols or {}, {}
    head.rule = head:CreateTexture(nil, "ARTWORK")
    head.rule:SetTexture(WHITE)
    head.rule:SetVertexColor(1, 1, 1, 0.06)
    head.rule:SetHeight(1)
    head.rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
    head.rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)

    -- cell.over: 0 at rest, 1 hovered (LABEL to VALUE). cell.sorted: 0 to 1
    -- toward the accent, fading the chevron in with it.
    local function paint(cell)
        local p, s = cell.over or 0, cell.sorted or 0
        local a, z = Style.INK.LABEL, Style.INK.VALUE
        local r, g, b = a[1] + (z[1] - a[1]) * p, a[2] + (z[2] - a[2]) * p, a[3] + (z[3] - a[3]) * p
        local ar, ag, ab = Style.Accent()
        r, g, b = r + (ar - r) * s, g + (ag - g) * s, b + (ab - b) * s
        cell.text:SetTextColor(r, g, b, 1)
        cell.arrow:SetVertexColor(r, g, b, 1)
        cell.arrow:SetAlpha(s)
        cell.arrow:SetShown(s > 0.01)
        cell.arrow:SetRotation(cell.rot or (cell.desc and 0 or math.pi))   -- the art points down
    end
    local function ease(cell, field, to)
        local M = DUI.Motion
        local key = field == "over" and cell or cell.arrow
        local function step(v) cell[field] = v; paint(cell) end
        if M then M.Tween(key, cell[field] or 0, to, M.FAST, step) else step(to) end
    end
    function head.Paint()
        for _, cell in pairs(head.cells) do paint(cell) end
    end

    -- Chevron goes after the text in a LEFT column, before it in a RIGHT one.
    local function placeArrow(cell)
        local w = cell.text:GetStringWidth()
        if type(w) ~= "number" then w = 0 end
        w = math.min(w, cell.room or w)
        cell.arrow:ClearAllPoints()
        if cell.col.justify == "RIGHT" then cell.arrow:SetPoint("RIGHT", cell, "RIGHT", -(w + 4), 0)
        else cell.arrow:SetPoint("LEFT", cell, "LEFT", w + 4, 0) end
    end

    for _, col in ipairs(head.cols) do
        local cell = CreateFrame("Button", nil, head)
        cell.col = col
        cell:SetHeight(W.COLUMN_H)
        local j = col.justify or "LEFT"
        cell.text = Style.Text(cell, SIZE.small, j)
        cell.text:SetPoint(j, cell, j, 0, 0)
        cell.text:SetWordWrap(false)
        cell.text:SetText(col.text or "")
        cell.arrow = W.Icon(cell, "ui-chevron.png", W.SORT_ARROW, Style.INK.LABEL)
        cell.arrow:Hide()
        placeArrow(cell)
        cell:EnableMouse(col.sort == true)
        cell:SetScript("OnEnter", function(self) if col.sort then ease(self, "over", 1) end end)
        cell:SetScript("OnLeave", function(self) if col.sort then ease(self, "over", 0) end end)
        cell:SetScript("OnClick", function()
            if not col.sort then return end
            local desc = head.sortId == col.id and not head.descending
            head:SetSort(col.id, desc)
            if DUI.Sound then DUI.Sound.Play("click") end
            if onSort then onSort(col.id, desc) end
        end)
        head.cells[col.id] = cell
        paint(cell)
    end

    function head:SetSort(id, descending)
        self.sortId, self.descending = id, descending == true
        for cid, cell in pairs(self.cells) do
            local on = cid == id
            if on then
                local to = self.descending and 0 or math.pi
                local M = DUI.Motion
                -- Flipping the visible chevron rotates it. A new column just points.
                if cell.desc ~= self.descending and (cell.sorted or 0) > 0.01 and M and M.On() then
                    cell.rotKey = cell.rotKey or {}
                    M.Tween(cell.rotKey, cell.rot or (cell.desc and 0 or math.pi), to, M.FAST, function(v)
                        cell.rot = v
                        paint(cell)
                    end)
                else
                    if cell.rotKey and M then M.Tween(cell.rotKey, to, to, 0) end
                    cell.rot = to
                end
                cell.desc = self.descending
            end
            if (cell.sorted or 0) ~= (on and 1 or 0) then ease(cell, "sorted", on and 1 or 0)
            else paint(cell) end
        end
    end

    function head:Layout(width)
        width = type(width) == "number" and width or (self:GetWidth() or 0)
        local fixed, fills, lastFill = 0, 0, nil
        for i, col in ipairs(self.cols) do
            if col.fill then fills = fills + 1; lastFill = i else fixed = fixed + (col.width or 0) end
        end
        local gaps = W.COLUMN_GAP * math.max(0, #self.cols - 1)
        local room = math.max(0, width - fixed - gaps)
        local share = fills > 0 and math.floor(room / fills) or 0
        local at, x = {}, 0
        for i, col in ipairs(self.cols) do
            local w = col.width or 0
            if col.fill then w = (i == lastFill) and (room - share * (fills - 1)) or share end
            at[col.id] = { x = x, w = w }
            local cell = self.cells[col.id]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
            cell:SetWidth(math.max(1, w))
            cell.room = math.max(1, w - W.SORT_ARROW - 4)
            cell.text:SetWidth(cell.room)
            placeArrow(cell)
            x = x + w + W.COLUMN_GAP
        end
        self.at = at
        return at
    end

    heads[head] = true
    return head
end
if DUI.On then DUI.On("StyleChanged", function() for h in pairs(heads) do h.Paint() end end) end

-- Scroll bars and progress bars

-- Progress bar for our windows: round ends, faint track, any height (thin
-- ones use W.BAR_H). Still a StatusBar, so SetMinMaxValues, SetValue and
-- Style.SetBarValue's glide all work. The StatusBar's own fill is invisible
-- and the rounded bar.fill follows it. Paint bar.fill, never the StatusBar:
-- W.BarColor, W.BarPair, or Style.PaintAccent(bar.fill).
W.BAR_H = 4
W.BAR_TRACK = { 1, 1, 1, 0.07 }
-- Bar textures picked on General > Appearance: the fill texture is laid over
-- the rounded fill in MOD blend so the colors and gradient show through, and
-- the background texture sits in the track at W.BAR_TRACK_TEXTURED. Both are
-- clipped to the pill's round ends. With none picked it's the plain pill.
W.BAR_SLOT, W.BACK_SLOT = "windows.bar", "windows.back"
W.BAR_TRACK_TEXTURED = 0.25
local pills = setmetatable({}, { __mode = "k" })

local function capped(bar, over, layer, sub)
    local t = bar:CreateTexture(nil, layer, nil, sub)
    t:SetAllPoints(over)
    for _, side in ipairs({ "l", "r" }) do
        local m = bar:CreateMaskTexture()
        m:SetTexture(MEDIA .. "mask-cap-" .. side .. ".png", "CLAMP", "CLAMP")
        m:SetPoint(side == "l" and "LEFT" or "RIGHT", over, side == "l" and "LEFT" or "RIGHT", 0, 0)
        t:AddMaskTexture(m)
        t["cap" .. side] = m
    end
    t:Hide()
    return t
end

local function capSize(bar)
    local h = bar:GetHeight()
    if type(h) ~= "number" or h <= 0 then h = W.BAR_H end
    for _, t in ipairs({ bar.grain, bar.trackGrain }) do
        if t then t.capl:SetSize(h, h); t.capr:SetSize(h, h) end
    end
end

function W.PaintBarTexture(bar)
    local fg, bg = Style.SharedBar(W.BAR_SLOT), Style.SharedBack(W.BACK_SLOT)
    if fg and not bar.grain then
        bar.grain = capped(bar, bar:GetStatusBarTexture(), "ARTWORK", 1)
        bar.grain:SetBlendMode("MOD")
        capSize(bar)
    end
    if bg and not bar.trackGrain then
        bar.trackGrain = capped(bar, bar, "BACKGROUND", 1)
        capSize(bar)
    end
    if bar.grain then
        if fg then bar.grain:SetTexture(fg) end
        bar.grain:SetShown(fg ~= nil)
    end
    if bar.trackGrain then
        if bg then
            bar.trackGrain:SetTexture(bg)
            local c = W.BAR_TRACK
            bar.trackGrain:SetVertexColor(c[1], c[2], c[3], W.BAR_TRACK_TEXTURED)
        end
        bar.trackGrain:SetShown(bg ~= nil)
    end
    bar.track:SetShown(bg == nil)
end

function W.Bar(parent, h)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetAlpha(0)
    bar:SetHeight(h or W.BAR_H)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.track = W.Round(bar, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    W.Tint(bar.track, W.BAR_TRACK)
    bar.fill = W.Round(bar, "ARTWORK")
    bar.fill:SetAllPoints(bar:GetStatusBarTexture())
    pills[bar] = true
    W.PaintBarTexture(bar)
    bar:HookScript("OnSizeChanged", capSize)
    return bar
end

DUI.On("RepaintCore", function()
    for bar in pairs(pills) do W.PaintBarTexture(bar) end
end)

function W.BarColor(bar, r, g, b, a)
    bar.fill:SetVertexColor(r, g, b, a or 1)
end

-- lo, hi: color objects (Gradients.Colors). Set to white first, because a
-- plain color set after a gradient clears it.
function W.BarPair(bar, lo, hi, orientation)
    bar.fill:SetVertexColor(1, 1, 1, 1)
    if bar.fill.SetGradient and lo and hi then bar.fill:SetGradient(orientation or "HORIZONTAL", lo, hi) end
end

-- Bars always get a gradient. A single color is turned into a pair
-- (Gradients.PairFrom), as the unit frames do.
function W.BarFrom(bar, r, g, b, alpha)
    local lo, hi = DUI.Gradients.PairFrom({ r, g, b })
    DUI.Gradients.PaintPair(bar.fill, lo, hi, alpha)
end

-- The accent's own pair, or one made from a single-color accent.
function W.BarAccent(bar, alpha)
    if Style.AccentPair() then Style.PaintAccent(bar.fill, alpha) return end
    local r, g, b = Style.Accent()
    W.BarFrom(bar, r, g, b, alpha)
end

-- A row of day columns (the mailbox ledger). Each day is a rounded column
-- from a faint middle line, up in gold for a good day, down in soft red for
-- a bad one, an empty day a faint stub. Heights glide as the numbers change.
-- Hovering a column shows a tooltip filled by opts.tip(day).
--   local d = W.DayBars(parent, h, { tip = function(day) ... end })
--   d.Set({ { day = "YYYY-MM-DD", net = 12345 }, ... })   -- oldest first
W.DAY_GAP = 3
W.DAY_UP = Style.INK.MONEY
W.DAY_DOWN = Style.INK.DAMAGE
W.DAY_EMPTY = { 1, 1, 1, 0.12 }

function W.DayBars(parent, h, opts)
    opts = opts or {}
    local d = CreateFrame("Frame", nil, parent)
    d:SetHeight(h or 56)
    d.mid = d:CreateTexture(nil, "BACKGROUND")
    d.mid:SetTexture("Interface\\Buttons\\WHITE8X8")
    W.Tint(d.mid, W.BAR_TRACK)
    d.mid:SetHeight(1)
    d.cols = {}
    d.days = {}
    local function column(i)
        local c = d.cols[i]
        if c then return c end
        c = CreateFrame("Button", nil, d)
        c.fill = W.Round(c, "ARTWORK")
        c.shown = 0
        c:SetScript("OnEnter", function(self)
            if not (opts.tip and GameTooltip and DUI.Tips) then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            DUI.Tips.Clear()
            opts.tip(d.days[self.index])
            DUI.Tips.Flush(GameTooltip)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        d.cols[i] = c
        return c
    end
    local function paint(c, v)
        local pair = v >= 0 and W.DAY_UP or W.DAY_DOWN
        if v == 0 then c.fill:SetVertexColor(W.DAY_EMPTY[1], W.DAY_EMPTY[2], W.DAY_EMPTY[3], W.DAY_EMPTY[4]); return end
        local lo, hi = DUI.Gradients.PairFrom(pair)
        local a, b = DUI.Gradients.PaintRGBOf(lo, hi)
        c.fill:SetVertexColor(1, 1, 1, 1)
        if c.fill.SetGradient and CreateColor then
            -- bright end away from the middle line
            if v > 0 then c.fill:SetGradient("VERTICAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
            else c.fill:SetGradient("VERTICAL", CreateColor(b[1], b[2], b[3], 1), CreateColor(a[1], a[2], a[3], 1)) end
        else
            c.fill:SetVertexColor(b[1], b[2], b[3], 1)
        end
    end
    -- One column sized to its share of the room (px, signed from the middle line).
    local function place(c, px)
        c.shown = px
        local mid = d.midY
        local len = math.max(2, math.abs(px))
        c.fill:ClearAllPoints()
        if px >= 0 then
            c.fill:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, mid)
            c.fill:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, mid)
        else
            c.fill:SetPoint("TOPLEFT", c, "BOTTOMLEFT", 0, mid)
            c.fill:SetPoint("TOPRIGHT", c, "BOTTOMRIGHT", 0, mid)
        end
        c.fill:SetHeight(len)
    end
    function d.Set(days)
        d.days = days or {}
        local n = #d.days
        local w = d:GetWidth()
        if type(w) ~= "number" or w <= 0 then w = 260 end
        local height = d:GetHeight()
        local most, anyDown = 0, false
        for _, x in ipairs(d.days) do
            most = math.max(most, math.abs(x.net or 0))
            if (x.net or 0) < 0 then anyDown = true end
        end
        -- Leave room below the line only when some day went down.
        d.midY = anyDown and math.floor(height * 0.38) or 0
        d.mid:ClearAllPoints()
        d.mid:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 0, d.midY)
        d.mid:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, d.midY)
        local up, down = height - d.midY, d.midY
        local gap = n > 40 and 1 or W.DAY_GAP
        local cw = n > 0 and math.max(1, (w - gap * (n - 1)) / n) or 0
        for i, x in ipairs(d.days) do
            local c = column(i)
            c.index = i
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", d, "TOPLEFT", (i - 1) * (cw + gap), 0)
            c:SetSize(cw, height)
            local v = x.net or 0
            local goal = most > 0 and (v >= 0 and v / most * up or v / most * down) or 0
            paint(c, v)
            DUI.Motion.Tween(c, c.shown or 0, goal, DUI.Motion.NORMAL, function(px) place(c, px) end)
            c:Show()
        end
        for i = n + 1, #d.cols do d.cols[i]:Hide() end
    end
    return d
end

W.SCROLL = { width = 4, track = { 1, 1, 1, 0.04 }, thumb = { 1, 1, 1, 0.22 }, thumbHover = { 1, 1, 1, 0.38 },
             minThumb = 24, gap = 6, step = 48, linger = 1, poll = 0.15, rest = 0.7 }

-- A thin scroll pill beside a list. Shown at the rest alpha whenever the
-- list overflows, full while scrolling or hovered, back after linger seconds,
-- hidden when everything fits. Drag the thumb or click the track to jump.
-- The wheel glides to where the notches add up.
-- sf is a ScrollFrame, or any frame with opts.read/write.
-- opts: x (gap right of sf), step (px per notch), wheel = false (the caller
-- handles the wheel and calls bar.Wake() or bar.Wheel(delta)), read() ->
-- at, max, view (for lists that aren't ScrollFrames, any units), write(v),
-- onScroll(v), parent.
-- bar.Update() redraws now after a refill or jump; a slow poll catches the
-- rest. bar.Lock(on) blocks drag and wheel so only the owner scrolls it.
function W.Scroll(sf, opts)
    opts = opts or {}
    local S, M = W.SCROLL, DUI.Motion
    local bar = CreateFrame("Frame", nil, opts.parent or sf:GetParent())
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", opts.x or S.gap, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", opts.x or S.gap, 0)
    bar:SetWidth(S.width)
    bar:SetFrameLevel(sf:GetFrameLevel() + 5)
    W.PadSkip(bar)
    bar:SetHitRectInsets(-6, -6, 0, 0)   -- 4 px is hard to catch
    bar.track = W.Round(bar, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    W.Tint(bar.track, S.track)
    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetTexture(DUI.MEDIA .. "ui-pill.png")
    bar.thumb:SetWidth(S.width)
    W.Tint(bar.thumb, S.thumb)
    bar:SetAlpha(0)
    bar:EnableMouse(false)

    local function read()
        if opts.read then return opts.read() end
        local child = sf:GetScrollChild()
        local h, view = child and child:GetHeight(), sf:GetHeight()
        if type(h) ~= "number" or type(view) ~= "number" then return 0, 0, 0 end
        return sf:GetVerticalScroll() or 0, math.max(0, h - view), view
    end
    local function write(v)
        if opts.write then opts.write(v) else sf:SetVerticalScroll(v) end
        if opts.onScroll then opts.onScroll(v) end
    end

    -- shown: the alpha it's at or heading to (0 hidden, S.rest, 1 lit).
    local shown, lastMove, grab, goal = 0, -10, nil, nil
    local function show(to)
        if to == shown then return end
        local from = shown
        shown = to
        if M then M.Fade(bar, from, to, to > from and M.FAST or M.SLOW) else bar:SetAlpha(to) end
    end

    function bar.Update()
        local at, max, view = read()
        bar.max = max
        if max <= 0 or view <= 0 then
            if max <= 0 and at > 0 and not opts.read then write(0) end
            bar:EnableMouse(false)
            show(0)
            return
        end
        if at > max then at = max; write(max) end
        bar:EnableMouse(not bar.locked)
        local h = bar:GetHeight()
        if type(h) ~= "number" or h <= 0 then return end
        local thumbH = math.min(h, math.max(S.minThumb, h * view / (max + view)))
        bar.thumb:SetHeight(thumbH)
        bar.thumb:ClearAllPoints()
        bar.thumb:SetPoint("TOP", bar, "TOP", 0, -(at / max) * (h - thumbH))
    end

    function bar.Wake()
        lastMove = GetTime()
        bar.Update()
        if (bar.max or 0) > 0 then show(1) end
    end

    -- Jump straight there (drag, jump) or glide (wheel).
    function bar.To(v, glide)
        local _, max = read()
        v = math.max(0, math.min(max, v))
        if glide and M and M.On() then
            goal = v
            M.Tween(bar, (read()), v, M.FAST, function(p) write(p); bar.Update() end, function() goal = nil end)
        else
            bar.Stop()
            write(v)
        end
        bar.Wake()
    end

    -- A wheel notch counts from where a running glide is heading, so quick
    -- notches add up.
    function bar.Wheel(delta)
        bar.To((goal or (read())) - delta * (opts.step or S.step), true)
    end

    -- Locked lists scroll only from their owner. The spellbook does this in
    -- combat because its secure cast buttons move with the list.
    function bar.Lock(on)
        bar.locked = on and true or nil
        if on then grab = nil end
        bar.Update()
    end

    -- Stop any running glide; a refill or jump made elsewhere wins.
    function bar.Stop()
        goal = nil
        if M then M.Tween(bar, 0, 0, 0) end
    end

    -- The gamepad D-pad scrolls the list itself, bypassing the bar (SmartNavigation HandleScroll).
    if DUI.Pad and DUI.Pad.On() and not opts.read then
        sf:HookScript("OnVerticalScroll", function() if not goal then bar.Wake() end end)
    end

    if opts.wheel ~= false then
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(_, delta)
            -- Ctrl + wheel resizes the window it sits in (Win.WheelScale).
            if IsControlKeyDown and IsControlKeyDown() then
                local p = sf:GetParent()
                while p and not p.wheelScale do p = p:GetParent() end
                if p then p.wheelScale(delta); return end
            end
            if bar.locked then return end
            if opts.onWheel then opts.onWheel(delta) end
            bar.Wheel(delta)
        end)
    end

    local function dragTo()
        local _, max = read()
        local h, top, thumbH = bar:GetHeight(), bar:GetTop(), bar.thumb:GetHeight()
        if max <= 0 or type(top) ~= "number" or type(thumbH) ~= "number" or h <= thumbH then return end
        local _, cy = GetCursorPosition()
        cy = cy / bar:GetEffectiveScale()
        local off = math.min(h - thumbH, math.max(0, top - cy - grab))
        bar.To(off / (h - thumbH) * max)
    end
    local function stop()
        grab = nil
        W.Tint(bar.thumb, bar:IsMouseOver() and S.thumbHover or S.thumb)
    end
    bar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or bar.locked then return end
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local top, h = self.thumb:GetTop(), self.thumb:GetHeight()
        if type(top) == "number" and type(h) == "number" and cy <= top and cy >= top - h then
            grab = top - cy
        else
            grab = (h or 0) / 2   -- the track: the thumb's middle goes there
        end
        dragTo()
    end)
    bar:SetScript("OnMouseUp", stop)
    bar:SetScript("OnEnter", function() W.Tint(bar.thumb, S.thumbHover) end)
    bar:SetScript("OnLeave", function() if not grab then W.Tint(bar.thumb, S.thumb) end end)

    -- While visible: follow the drag every frame, otherwise check every poll
    -- seconds for hover, a new range or an outside jump.
    local wait = 0
    bar:SetScript("OnUpdate", function(_, dt)
        if grab then dragTo(); return end
        wait = wait - dt
        if wait > 0 then return end
        wait = S.poll
        bar.Update()
        local over = sf:IsMouseOver() == true or bar:IsMouseOver() == true
        if over then lastMove = GetTime() end
        if (bar.max or 0) <= 0 then show(0)
        else show((over or GetTime() - lastMove < S.linger) and 1 or S.rest) end
    end)
    bar:SetScript("OnHide", function()
        grab, shown = nil, 0
        bar.Stop()
        if M then M.Fade(bar, 0, 0, 0.01) else bar:SetAlpha(0) end
    end)
    return bar
end

-- List tools: move up/down, delete, striped lines

W.LIST_TOOL = 20        -- the boxes' height (the Combine/Hide pills')
local STRIPE = { 0, 0, 0, 0.22 }   -- darker than the card: the buttons stand out on it

-- A chevron-sized button. Unusable ones are faint and ignore clicks.
local function toolButton(parent, file, size, rotation, hover)
    local b = CreateFrame("Button", nil, parent)
    b.icon = W.Icon(b, file, size, C.text)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    if rotation then b.icon:SetRotation(rotation) end
    b:SetScript("OnEnter", function() if b.enabled ~= false then hover(b.icon) end end)
    b:SetScript("OnLeave", function() if b.enabled ~= false then W.Tint(b.icon, b.rest or C.text) end end)
    b:SetScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
    function b.SetUsable(on)
        b.enabled = on and true or false
        W.Tint(b.icon, on and (b.rest or C.text) or C.faint)
        b:SetAlpha(on and 1 or 0.45)
        b:EnableMouse(on and true or false)
    end
    return b
end

-- Up and down in one rounded box: box.up, box.down (each has .SetUsable(on)).
function W.MoveButtons(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(48, W.LIST_TOOL)
    box.bg = W.Round(box, "BACKGROUND")
    box.bg:SetAllPoints(box)
    W.Tint(box.bg, C.control)
    box.split = box:CreateTexture(nil, "BORDER")
    box.split:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.12)
    box.split:SetSize(1, W.LIST_TOOL - 8)
    box.split:SetPoint("CENTER", box, "CENTER", 0, 0)
    box.up = toolButton(box, "ui-chevron.png", 13, math.pi, W.TintDaylight)
    box.up:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    box.up:SetPoint("BOTTOMRIGHT", box, "BOTTOM", 0, 0)
    box.down = toolButton(box, "ui-chevron.png", 13, nil, W.TintDaylight)
    box.down:SetPoint("TOPLEFT", box, "TOP", 0, 0)
    box.down:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    return box
end

-- A small rounded box with an X that turns red on hover.
function W.DeleteButton(parent)
    local b = toolButton(parent, "ui-close.png", 10, nil, function(icon) W.Tint(icon, C.warn) end)
    b:SetSize(W.LIST_TOOL + 4, W.LIST_TOOL)
    b.rest = C.dim
    W.Tint(b.icon, C.dim)
    b.bg = W.Round(b, "BACKGROUND")
    b.bg:SetAllPoints(b)
    W.Tint(b.bg, C.control)
    return b
end

-- Alternating faint band on list lines (on = this line gets one).
function W.Stripe(line, on)
    if not line.stripe then
        line.stripe = W.Round(line, "BACKGROUND", -1)
        line.stripe:SetPoint("TOPLEFT", line, "TOPLEFT", -8, 0)
        line.stripe:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", 8, 0)
        W.Tint(line.stripe, STRIPE)
    end
    line.stripe:SetShown(on and true or false)
end

-- Two-click confirm: the first click turns the button into "Click again" for
-- a few seconds. For actions that can't be undone.
W.CONFIRM = 3   -- seconds an armed "Click again" waits
W.CONFIRM_GAP = 0.25   -- seconds after arming before a click counts: swallows a double-click without losing a real second click

-- Calling it again on the same button (a list row reused for another item,
-- like on the profiles page) just swaps the label and action and disarms it.
-- The button is only wired once.
-- asking: label to show while armed, for buttons the player didn't click
-- first, where a bare "Click again" wouldn't make sense.
-- quick: a double-click goes through (skips W.CONFIRM_GAP). Only for things
-- that are cheap to redo, like clearing a list. Never for spending gold or
-- irreversible resets.
function W.Confirm(b, label, func, asking, quick)
    local ask = b.asks
    if ask then
        ask.label, ask.func, ask.asking, ask.quick = label, func, asking, quick
        ask.token = ask.token + 1
        b.armed = false
        b.Paint()
        return
    end
    ask = { label = label, func = func, asking = asking, quick = quick, token = 0 }
    b.asks = ask
    b.armed = false
    -- Back to the plain button, so the next page's reset asks again.
    function b.Disarm()
        ask.token = ask.token + 1
        if not b.armed then return end
        b.armed = false
        b.Paint()
    end
    local base = b.Paint
    function b.Paint()
        if base then base() end
        if b.armed then
            b.text:SetText(ask.asking or L["Click again"])
            W.TextColor(b.text, DUI.Style.INK.WARN)   -- "Click again" in INK.WARN (C.warn is BAD)
        else
            local words = ask.label
            b.text:SetText(type(words) == "function" and words() or words)
            W.TextColor(b.text, b.active and C.value or BTN.text)
        end
        if b.fit then b.FitWidth(b.fit) end
    end
    b:SetScript("OnClick", function()
        if b.disabled then return end
        if not b.armed then
            b.armed = true
            b.armedAt = GetTime()
            ask.token = ask.token + 1
            local mine = ask.token
            b.Paint()
            C_Timer.After(W.CONFIRM, function()
                if ask.token == mine then
                    b.armed = false
                    b.Paint()
                end
            end)
            return
        end
        if not ask.quick and GetTime() - (b.armedAt or 0) < W.CONFIRM_GAP then return end   -- the double-click's second half
        b.armed = false
        ask.token = ask.token + 1
        b.Paint()
        -- func returned true: it plays its own sound (abandoning a quest).
        if ask.func() ~= true and DUI.Sound then DUI.Sound.Play("gone") end
    end)
    b:HookScript("OnHide", b.Disarm)
    b.Paint()
end

-- Slider values

function W.FormatValue(item, v)
    if item.unit == "%" then return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    if item.unit == "px" then return string.format("%d px", math.floor(v + 0.5)) end
    if item.unit == "x" then return string.format("%.2fx", v) end
    if (item.step or 1) < 1 then return string.format("%.2f", v) end
    return tostring(math.floor(v + 0.5))
end

-- Parses what was typed into a slider's box. On a percent slider "35",
-- "35%" and "35 %" all mean 0.35.
function W.ParseValue(item, text)
    local n = tonumber((string.gsub(text or "", "[^%d%.%-]", "")))
    if not n then return nil end
    if item.unit == "%" then n = n / 100 end
    return n
end

function W.SnapValue(item, v)
    local step = item.step or 1
    v = math.floor((v - item.min) / step + 0.5) * step + item.min
    v = math.max(item.min, math.min(item.max, v))
    return tonumber(string.format("%.4f", v))
end

-- Controls. Each sets row.control, a frame with Refresh().

local SWITCH_W, SWITCH_H, KNOB = 30, 16, 12

-- The standard on/off switch: a pill with a sliding knob that fills with the
-- accent when on. b.SetOn(on) paints it. Caller sets OnClick; the toggle
-- sound is built in.
local switches = setmetatable({}, { __mode = "k" })
DUI.On("StyleChanged", function()
    for b, sw in pairs(switches) do if sw.on and b:IsVisible() then sw.SetOn(true) end end
end)

-- Just the switch look: pill and knob, stored on s. For a game checkbox
-- (Kit.Check) s is a separate table so nothing is written on the game's
-- frame. width is the pill's (SWITCH_W), the rest scales with it, centered
-- on b. No scripts: the caller calls s.SetOn(on), which slides the knob
-- (the first call just places it). s.off dims it.
W.SWITCH_W = SWITCH_W
function W.SwitchLook(b, s, width)
    s = s or b
    switches[b] = s
    local w = width or SWITCH_W
    local k = w / SWITCH_W
    local knob, margin = KNOB * k, 2 * k
    s.track = b:CreateTexture(nil, "ARTWORK")
    s.track:SetTexture(MEDIA .. "ui-pill.png")
    s.track:SetSize(w, SWITCH_H * k)
    s.track:SetPoint("CENTER", b, "CENTER", 0, 0)
    s.knob = b:CreateTexture(nil, "OVERLAY")
    s.knob:SetTexture(MEDIA .. "ui-knob.png")
    s.knob:SetSize(knob, knob)
    local OFF, ON = margin, w - knob - margin
    local function place(x)
        s.pos = x
        s.knob:ClearAllPoints()
        s.knob:SetPoint("LEFT", s.track, "LEFT", x, 0)
    end
    function s.SetOn(on)
        s.on = on
        if s.off then
            W.Tint(s.track, C.track)
            W.Tint(s.knob, C.faint)
        elseif on then
            Style.PaintAccent(s.track, 1)
            s.knob:SetVertexColor(1, 1, 1, 1)
        else
            W.Tint(s.track, C.track)
            W.Tint(s.knob, C.dim)
        end
        s.track:SetAlpha(s.off and 0.45 or 1)
        local goal = on and ON or OFF
        local M = DUI.Motion
        if not s.pos or not M then
            place(goal)
        elseif goal ~= s.goal then
            M.Tween(s.knob, s.pos, goal, M.FAST, place)
        end
        s.goal = goal
    end
    return s
end

function W.Switch(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SWITCH_W, SWITCH_H)
    W.SwitchLook(b)
    b:SetScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("toggle") end end)
    return b
end

function W.toggle(row, page, item)
    local b = W.Switch(row)
    function b.Refresh() b.SetOn(Options.Get(page, item) == true) end
    b:SetScript("OnClick", function()
        if row.disabled then return end
        Options.Set(page, item, Options.Get(page, item) ~= true)
    end)
    -- Clicking anywhere on the row flips it too.
    row:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and not row.disabled then b:Click() end
    end)
    row.control = b
end

-- Just the slider look: thin pill track, the filled part in the Daylight
-- sweep, a round knob that grows a little on hover or drag. Works on our
-- sliders and other addons' (the Skins' Ace3 sliders): state lives on s and
-- only the thumb art and hooked scripts touch the slider. s.Fill(frac) sets
-- the fill to 0-1 of the track.
function W.SliderLook(sl, s)
    s = s or {}
    s.track = sl:CreateTexture(nil, "BACKGROUND")
    s.track:SetTexture(MEDIA .. "ui-pill.png")
    s.track:SetPoint("LEFT", sl, "LEFT", 0, 0)
    s.track:SetPoint("RIGHT", sl, "RIGHT", 0, 0)
    s.track:SetHeight(4)
    W.Tint(s.track, C.track)
    s.fill = sl:CreateTexture(nil, "BORDER")
    s.fill:SetTexture(MEDIA .. "ui-pill.png")
    s.fill:SetPoint("LEFT", s.track, "LEFT", 0, 0)
    s.fill:SetHeight(4)
    W.TintDaylight(s.fill)
    sl:SetThumbTexture(MEDIA .. "ui-knob.png")
    local thumb = sl:GetThumbTexture()
    -- Knob grows on hover and shrinks back FAST.
    local knobSize
    local function knob(big)
        if type(thumb) ~= "table" then return end
        local goal = big and W.KNOB_BIG or W.KNOB
        local M = DUI.Motion
        if not knobSize or not M or not sl:IsVisible() then
            if M then M.Tween(thumb, 0, 0, 0) end
            knobSize = goal
            thumb:SetSize(goal, goal)
            return
        end
        M.Tween(thumb, knobSize, goal, M.FAST, function(v) knobSize = v; thumb:SetSize(v, v) end)
    end
    if type(thumb) == "table" then thumb:SetVertexColor(1, 1, 1, 1) end
    knob(false)
    sl:HookScript("OnEnter", function() knob(true) end)
    sl:HookScript("OnLeave", function() knob(s.held) end)
    sl:HookScript("OnMouseDown", function() s.held = true; knob(true) end)
    sl:HookScript("OnMouseUp", function() s.held = false; knob(sl:IsMouseOver()) end)
    sl:HookScript("OnHide", function() s.held = false end)
    function s.Fill(frac)
        local w = sl:GetWidth()
        if type(w) ~= "number" then w = 0 end
        if type(frac) ~= "number" or frac ~= frac then frac = 0 end
        s.fill:SetWidth(math.max(0.01, math.min(1, math.max(0, frac)) * w))
    end
    return s
end

-- A slider on any frame: thin accent track, knob that grows on hover, and a
-- value box you can type into ("35%" on a percent slider is 0.35).
-- spec: min, max, step?, unit? ("%", "px", "x"), width?, get(), set(v),
-- preview(v)? (return true if a drag step was previewed; set is then called
-- once on release), disabled()?. f.Refresh() shows get()'s value, sliding
-- there FAST if it changed from elsewhere.
function W.Slider(parent, spec)
    local item = spec
    local function get() return spec.get() end
    local function off() return spec.disabled ~= nil and spec.disabled() == true end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(spec.width or W.CONTROL_WIDTH, 22)

    local box = W.Input(f, { height = 22, justify = "CENTER", maxLetters = 10 })
    box:SetWidth(W.SLIDER_BOX)
    box:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    W.TextColor(box, C.value)

    local s = CreateFrame("Slider", nil, f)
    s:SetPoint("LEFT", f, "LEFT", 0, 0)
    s:SetPoint("RIGHT", box, "LEFT", -10, 0)
    s:SetHeight(18)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(item.min, item.max)
    s:SetValueStep(item.step or 1)
    s:SetObeyStepOnDrag(true)
    s:SetHitRectInsets(-4, -4, -6, -6)
    local look = W.SliderLook(s, {})
    s.track, s.fill = look.track, look.fill
    -- On a page with a preview, drag steps only redraw the preview
    -- (spec.preview). The value is saved once, on release.
    local quiet
    local function save()
        local v = quiet
        quiet = nil
        if v ~= nil then spec.set(v) end
    end
    s:HookScript("OnMouseUp", save)
    s:HookScript("OnHide", save)

    local updating = false
    local function paintFill(v)
        look.Fill((v - item.min) / (item.max - item.min))
    end
    -- A value changed from elsewhere while visible (typed in the box, Reset, a
    -- preset) slides the knob and fill FAST. A drag stays under the mouse, and
    -- the first fill is set at once.
    local function show(v)
        updating = true
        s:SetValue(v)
        updating = false
        paintFill(v)
    end
    -- While sliding, the number in the box rolls along with the knob.
    local function slide(v)
        show(v)
        if not box:HasFocus() then box:SetText(W.FormatValue(item, W.SnapValue(item, v))) end
    end
    local shownV
    function f.Refresh()
        local v = get() or item.min
        local from = shownV
        shownV = v
        local M = DUI.Motion
        if type(from) == "number" and from ~= v and not look.held and f:IsVisible()
            and s:GetValue() ~= v then
            M.Tween(f, from, v, M.FAST, slide, function()
                if not box:HasFocus() then box:SetText(W.FormatValue(item, v)) end
            end)
            return
        end
        M.Tween(f, 0, 0, 0)
        show(v)
        if not box:HasFocus() then box:SetText(W.FormatValue(item, v)) end
    end
    s:SetScript("OnSizeChanged", function() paintFill(get() or item.min) end)
    s:SetScript("OnValueChanged", function(_, v)
        if updating then return end
        if off() then
            f.Refresh()
            return
        end
        v = W.SnapValue(item, v)
        DUI.Motion.Tween(f, 0, 0, 0)   -- the hand wins over a slide under way
        shownV = v
        paintFill(v)
        box:SetText(W.FormatValue(item, v))
        if get() == v then return end
        if look.held and spec.preview and spec.preview(v) then
            quiet = v
        else
            spec.set(v)
        end
    end)
    box:HookScript("OnEditFocusGained", function(self)
        if off() then
            self:ClearFocus()
            return
        end
        self:HighlightText()
    end)
    box:SetScript("OnEnterPressed", function(self)
        local v = W.ParseValue(item, self:GetText())
        self:ClearFocus()
        if v and not off() then spec.set(W.SnapValue(item, v)) end
        f.Refresh()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        f.Refresh()
    end)
    box:HookScript("OnEditFocusLost", function() f.Refresh() end)
    f.slider, f.box = s, box
    return f
end

-- An options row's slider: W.Slider bound to the page's setting.
function W.slider(row, page, item)
    local f = W.Slider(row, { min = item.min, max = item.max, step = item.step, unit = item.unit,
        get = function() return Options.Get(page, item) end,
        set = function(v) Options.Set(page, item, v) end,
        preview = function(v) return Options.Preview(page, item, v) end,
        disabled = function() return row.disabled == true end })
    row.control = f
    W.Hover(row, f.slider)
    W.Hover(row, f.box)
end

-- The shared dropdown list: one popup for every dropdown, over a full-screen
-- catcher that closes it on any click outside.
local catcher, menu

local function buildMenu()
    catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() W.CloseMenu() end)
    catcher:Hide()
    menu = CreateFrame("Frame", nil, catcher)
    DUI.Pad.Popup(menu, function() W.CloseMenu() end)
    menu:SetFrameLevel(catcher:GetFrameLevel() + 5)
    menu:EnableMouse(true)
    -- Same frame look as the rest of the UI.
    Style.Shell(menu)
    menu.rows = {}
    -- Rows ride on menu.strip, so a glide moves one frame and only rows coming
    -- into view get filled (drawRows).
    menu.view = CreateFrame("ScrollFrame", nil, menu)
    menu.view:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -4)
    menu.view:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -4)
    menu.strip = CreateFrame("Frame", nil, menu.view)
    menu.view:SetScrollChild(menu.strip)
    -- Off-screen string for measuring choices.
    menu.measure = W.Font(menu, W.BODY, SIZE.body, C.text)
    menu.measure:Hide()
end

local MENU_ROW = 26
W.MENU_MAX_ROWS = 12    -- a longer list scrolls with the mouse wheel
W.MENU_WHEEL = 2        -- rows one notch of the wheel moves
W.MENU_DROP = 6         -- px a menu drops out of its owner as it opens

-- State while open: the choices and the scroll offset (choices above the
-- top row).
local open = {}
local drawMenu

-- Row scripts are set once and each fill only updates r.key and r.title, so
-- a wheel notch creates no new closures.
-- Row look shared by the menu and W.Complete: a 26 px button with a soft
-- hover wash (r.hl) and body text (r.text).
local function baseRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(MENU_ROW)
    r.hl = W.Round(r, "BACKGROUND")
    r.hl:SetPoint("TOPLEFT", r, "TOPLEFT", 4, 0)
    r.hl:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -4, 0)
    W.Tint(r.hl, { 1, 1, 1, 0.06 })
    r.hl:Hide()
    r.text = W.Font(r, W.BODY, SIZE.body, C.text)
    return r
end

local function makeRow(i)
    local r = baseRow(menu.strip)
    -- Texture choices show the texture as a strip behind the name.
    r.swatch = r:CreateTexture(nil, "BORDER")
    r.swatch:SetPoint("TOPLEFT", r, "TOPLEFT", 6, -3)
    r.swatch:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -28, 3)
    r.swatch:Hide()
    r.text:SetPoint("LEFT", r, "LEFT", 12, 0)
    r.text:SetPoint("RIGHT", r, "RIGHT", -30, 0)
    r.check = W.Icon(r, "ui-check.png", 14)
    r.check:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    -- A submenu row gets W.MenuButton's chevron, pointing right.
    r.more = W.Icon(r, "ui-chevron.png", 10, Style.INK.LABEL)
    r.more:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    r.more:SetRotation(math.pi / 2)
    r.more:Hide()
    -- On a controller only the visible rows exist (drawRows), so landing on
    -- the last or first visible row scrolls the next choice in and the next
    -- step lands on it (W.PadMenuRow).
    r.OnSmartNavSelect = function(self) W.PadMenuRow(self) end
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        if self.title then return end
        local opts, keys = open.opts or {}, open.keys
        -- Right-click goes to opts.onRightClick (its own menu).
        if button == "RightButton" then
            if not opts.onRightClick then return end
            DUI.Sound.Play("click")
            W.CloseMenu()
            opts.onRightClick(self.key)
            return
        end
        DUI.Sound.Play("click")
        -- opts.confirm[key]: the first click turns the row into "Click again"
        -- for W.CONFIRM seconds, like W.Confirm.
        if opts.confirm and opts.confirm[self.key] and open.armed == self.key
            and GetTime() - (open.armedAt or 0) < W.CONFIRM_GAP then
            return   -- the double-click's second half (W.CONFIRM_GAP)
        end
        if opts.confirm and opts.confirm[self.key] and open.armed ~= self.key then
            open.armed, open.armedAt = self.key, GetTime()
            local token = (open.armedToken or 0) + 1
            open.armedToken = token
            drawMenu()
            C_Timer.After(W.CONFIRM, function()
                if open.armedToken == token and open.keys == keys then
                    open.armed = nil
                    drawMenu()
                end
            end)
            return
        end
        if opts.confirm and opts.confirm[self.key] then DUI.Sound.Play("gone") end
        -- A menu of switches stays open and redraws its ticks.
        if opts.keepOpen then
            open.onPick(self.key)
            if open.keys == keys then drawMenu() end
            return
        end
        W.CloseMenu()
        open.onPick(self.key)
    end)
    -- Live preview of each choice on hover.
    r:SetScript("OnEnter", function(self)
        if not self.title then self.hl:Show() end
        if self.more:IsShown() then W.TintAccent(self.more) end
        local opts = open.opts
        if opts and opts.onHover then opts.onHover(self.key) end
    end)
    r:SetScript("OnLeave", function()
        r.hl:Hide()
        W.Tint(r.more, Style.INK.LABEL)
    end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) menu.bar.Wheel(delta) end)
    menu.rows[i] = r
    return r
end

-- Rows to build: a screenful plus one for the half-visible row during a glide.
local function rowCount()
    local most = (open.opts and open.opts.rows) or W.MENU_MAX_ROWS
    local shown = math.min(#open.keys, most)
    return shown, #open.keys > shown and shown + 1 or shown
end

-- Choice n stays on the same row while visible, so a row keeps its font as
-- it slides and a notch only loads fonts for rows coming in.
local function rowOf(n, count) return menu.rows[(n - 1) % count + 1] end

local function fillRow(r, n)
    local keys, values, opts = open.keys, open.values, open.opts or {}
    local k = keys[n]
    r.index = n
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", menu.strip, "TOPLEFT", 0, -((n - 1) * MENU_ROW))
    r:SetPoint("TOPRIGHT", menu.strip, "TOPRIGHT", 0, -((n - 1) * MENU_ROW))
    r.text:SetText(values[k])
    -- Previews: a font in its own face, a texture as a strip.
    local file = opts.fetch and opts.fetch(k)
    r.text:SetFont((opts.preview == "font" and file) or W.BODY, SIZE.body, "")
    if opts.preview == "bar" and file then
        r.swatch:SetTexture(file)
        r.swatch:SetVertexColor(0.45, 0.45, 0.5, 1)
        r.swatch:Show()
    else
        r.swatch:Hide()
    end
    -- opts.titles[k]: a heading row (small, upper case, in the accent, like a
    -- list section). opts.checked(k): a tick per row (a menu of switches),
    -- otherwise only the current choice gets one.
    local title = opts.titles and opts.titles[k]
    -- opts.hints[k]: a quiet info line in the label color, not a choice.
    local hint = opts.hints and opts.hints[k]
    r.key, r.title = k, title or hint
    local picked
    if opts.checked then picked = not title and opts.checked(k) == true else picked = k == open.current end
    r.check:SetShown(picked and true or false)
    -- opts.more[k]: the row opens a submenu (chevron, no "...").
    r.more:SetShown((not picked and opts.more and opts.more[k]) and true or false)
    W.Tint(r.more, Style.INK.LABEL)
    -- The player's accent, read now, not the fixed Daylight sweep.
    if picked then Style.PaintAccent(r.check) end
    if title then
        r.text:SetFont(W.BODY, SIZE.small, "")
        r.text:SetText(string.upper(values[k] or ""))
        W.TextAccent(r.text)
    elseif hint then
        r.text:SetFont(W.BODY, SIZE.small, "")
        W.TextColor(r.text, Style.INK.LABEL)
    elseif open.armed == k then
        r.text:SetText(L["Click again"])
        W.TextColor(r.text, Style.INK.WARN)   -- "Click again" in INK.WARN
    -- Menus of switches mark "on" with the tick alone. Coloring every on row
    -- in the accent turned the whole list one color.
    elseif picked and not opts.checked then W.TextAccent(r.text) else W.TextColor(r.text, C.text) end
    r:Show()
end

-- Fills the visible rows that just came into view, or every row when all.
-- A font the game hasn't loaded yet draws blank until its text is set again
-- (the font menu opened empty until scrolled away and back), so font
-- preview rows get set once more a moment later.
local refill
local function drawRows(all)
    local _, count = rowCount()
    local top = open.offset + 1
    local last = math.min(#open.keys, top + count - 1)
    local filled
    for n = top, last do
        local r = rowOf(n, count)
        if all or r.index ~= n then fillRow(r, n); filled = true end
    end
    if filled and not refill and open.opts and open.opts.preview == "font" then
        local keys = open.keys
        refill = true
        C_Timer.After(0.05, function()
            refill = nil
            if open.keys ~= keys then return end
            for _, r in ipairs(menu.rows) do
                if r.index and r:IsShown() and not r.title and open.armed ~= r.key then
                    r.text:SetText("")
                    r.text:SetText(open.values[r.key])
                end
            end
        end)
    end
end

function drawMenu()
    local shown, count = rowCount()
    for i = #menu.rows + 1, count do makeRow(i) end
    for i, r in ipairs(menu.rows) do
        r.index = nil
        if i > count then r:Hide() end
    end
    drawRows(true)
    for i = 1, count do
        if not menu.rows[i].index then menu.rows[i]:Hide() end
    end
    menu.view:SetHeight(shown * MENU_ROW)
    menu.strip:SetHeight(#open.keys * MENU_ROW)
    menu:SetHeight(shown * MENU_ROW + 8)
end

-- Gamepad on a row at the edge of the visible list: scroll one more choice
-- in so the D-pad can keep going.
function W.PadMenuRow(r)
    if not (open.keys and r.index) then return end
    local shown = rowCount()
    if r.index >= open.offset + shown and r.index < #open.keys then
        W.ScrollMenu(r.index - (open.offset + shown) + 1)
    elseif r.index <= open.offset + 1 and open.offset > 0 then
        W.ScrollMenu(-1)
    end
end

-- Scrolls an open list by rows, jumping straight there. The wheel glides via menu.bar.
function W.ScrollMenu(by)
    if not open.keys then return end
    menu.bar.To((open.offset + by) * MENU_ROW)
end

-- width (optional): list width, for owners narrower than the longest choice.
-- opts (optional):
--   preview = "font" | "bar", fetch = function(key) -> file: show each
--     choice as itself.
--   atCursor = true: a right-click menu opened at the mouse.
--   checked = function(key) -> on: a tick per row (menu of switches).
--   titles = { [key] = true }: headings. keepOpen = true: clicks toggle and
--     the menu stays. rows: visible rows before it scrolls.
--   hints = { [key] = true }: info lines, not choices.
--   onRightClick = function(key): a row's right-click.
--   confirm = { [key] = true }: ask "Click again" first, for deletes.
--   more = { [key] = true }: the row opens a submenu.
local cursorSpot
function W.OpenMenu(owner, keys, values, current, onPick, width, opts)
    if not menu then
        buildMenu()
        menu.bar = W.Scroll(menu.view, { parent = menu, x = -7, step = W.MENU_WHEEL * MENU_ROW,
            onScroll = function(v)
                open.offset = math.floor(v / MENU_ROW + 0.001)
                drawRows()
            end })
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(_, delta) menu.bar.Wheel(delta) end)
    end
    -- On a controller the mouse isn't where the player looks: open at the owner.
    local padded = owner ~= nil and DUI.Pad and DUI.Pad.On()
    if opts and opts.atCursor and not padded then
        cursorSpot = cursorSpot or CreateFrame("Frame", nil, UIParent)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale() or 1
        cursorSpot:SetSize(1, 1)
        cursorSpot:ClearAllPoints()
        cursorSpot:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (tonumber(x) or 0) / s, (tonumber(y) or 0) / s)
        owner = cursorSpot
    end
    open.keys, open.values, open.current, open.onPick, open.opts = keys, values, current, onPick, opts
    open.armed = nil
    -- Open with the current choice in view.
    open.offset = 0
    local inView = rowCount()
    for i, k in ipairs(keys) do
        if k == current then
            open.offset = math.max(0, math.min(#keys - inView, i - math.floor(inView / 2)))
        end
    end
    -- Wide enough for the longest choice, up to half the screen.
    local fit = 0
    for _, k in ipairs(keys) do
        menu.measure:SetText(values[k])
        local sw = menu.measure:GetStringWidth()
        if type(sw) == "number" and sw > fit then fit = sw end
    end
    local screenW = tonumber(UIParent:GetWidth()) or 1920
    fit = math.min(math.ceil(fit) + 42, math.floor(screenW / 2))   -- the text's 12 + 30 insets
    local w = math.max(owner:GetWidth(), width or 0, fit)
    menu:SetWidth(w)
    menu.strip:SetWidth(w)
    menu.bar.Stop()
    drawMenu()
    menu.view:SetVerticalScroll(open.offset * MENU_ROW)
    menu:ClearAllPoints()
    -- Below the owner, or above it if the list would run off the bottom of the
    -- screen (the damage meter sits low). Left-aligned with the owner, or
    -- right-aligned if a wide list would run off the side.
    local below = owner:GetBottom()
    local ownerScale, menuScale = owner:GetEffectiveScale(), menu:GetEffectiveScale()
    local up = type(below) == "number" and type(ownerScale) == "number" and ownerScale > 0
        and type(menuScale) == "number" and menuScale > 0
        and below * ownerScale - 4 * ownerScale < menu:GetHeight() * menuScale
    local side = "LEFT"
    local left = owner:GetLeft()
    if type(left) == "number" and type(ownerScale) == "number" and type(menuScale) == "number"
        and menuScale > 0 and left * ownerScale + w * menuScale > screenW * (UIParent:GetEffectiveScale() or 1) then
        side = "RIGHT"
    end
    if up then
        menu:SetPoint("BOTTOM" .. side, owner, "TOP" .. side, 0, 4)
    else
        menu:SetPoint("TOP" .. side, owner, "BOTTOM" .. side, 0, -4)
    end
    -- Opened fresh, it slides out of the owner while fading in. Redrawn while
    -- already open (a menu of switches), it stays put.
    local fresh = not catcher:IsShown() or W.menuOwner ~= owner
    catcher:Show()
    if fresh then DUI.Motion.SlideIn(menu, 0, up and -W.MENU_DROP or W.MENU_DROP, DUI.Motion.FAST) end
    W.menuOwner = owner
end

-- The i-th visible row, top first.
function W.MenuRow(i)
    if not menu or not open.keys then return nil end
    local shown, count = rowCount()
    if i > shown then return nil end
    return rowOf(open.offset + i, count)
end

function W.CloseMenu()
    if catcher then catcher:Hide() end
    W.menuOwner = nil
end

-- Autocomplete list under a W.Input, in the menu's look. Never takes the
-- box's focus and has no catcher, so clicks elsewhere still work.
-- suggest(text, cursor) -> nil | { { insert, from, to, label, note } }.
-- insert replaces text:sub(from, to) (1-based, inclusive). label is drawn
-- with the typed part in the accent, note small on the right.
-- Up/Down move, Tab or Enter fill, Esc closes. Enter with nothing open runs
-- the box's own handler, so set any OnEnterPressed/OnEscapePressed script
-- BEFORE calling this. After a fill it asks again, so a search string can
-- continue to its next part. c:Close(), c:IsOpen().
W.COMPLETE_MAX = 8
function W.Complete(input, suggest)
    local c = CreateFrame("Frame", nil, UIParent)
    c:SetFrameStrata("FULLSCREEN_DIALOG")
    Style.Shell(c)
    c:Hide()
    c.rows, c.list, c.pick = {}, {}, 1
    local isOpen, filling, closing = false, false, 0

    local function cursorOf(text)
        local n = input.GetCursorPosition and input:GetCursorPosition()
        return type(n) == "number" and n or #text
    end

    local function paint()
        for i, r in ipairs(c.rows) do
            r.hl:SetShown(isOpen and i == c.pick and i <= #c.list)
        end
    end

    local function fill(i)
        local s = c.list[i or c.pick]
        if not s then return end
        local text = input:GetText() or ""
        local to = s.to or s.from
        local out = text:sub(1, s.from - 1) .. s.insert .. text:sub(to + 1)
        -- Stay open through the refill. Refresh redraws or closes it, so the list
        -- doesn't flicker while typing.
        filling = true
        input:SetText(out)
        filling = false
        if input.SetCursorPosition then input:SetCursorPosition(s.from - 1 + #s.insert) end
        c:Refresh(out)
    end

    local function row(i)
        local r = baseRow(c)
        r.text:SetPoint("LEFT", r, "LEFT", 12, 0)
        r.note = W.Font(r, W.BODY, SIZE.small, Style.INK.LABEL, "RIGHT")
        r.note:SetPoint("RIGHT", r, "RIGHT", -10, 0)
        r.text:SetPoint("RIGHT", r.note, "LEFT", -8, 0)
        r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -(4 + (i - 1) * MENU_ROW))
        r:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -(4 + (i - 1) * MENU_ROW))
        -- On mouse down, not up: otherwise the box loses focus on the same press.
        r:RegisterForClicks("LeftButtonDown")
        r:SetScript("OnClick", function()
            DUI.Sound.Play("click")
            fill(i)
            if input.SetFocus then input:SetFocus() end
        end)
        r:SetScript("OnEnter", function() c.pick = i; paint() end)
        c.rows[i] = r
        return r
    end

    local function show(list, text)
        c.list, c.pick = list, 1
        for i = 1, math.min(#list, W.COMPLETE_MAX) do
            local s, r = list[i], c.rows[i] or row(i)
            local label = s.label or s.insert or ""
            local typed = text:sub(s.from, s.to or s.from)
            if typed ~= "" and label:sub(1, #typed):lower() == typed:lower() then
                local ar, ag, ab = Style.Accent()
                r.text:SetText(hex({ ar, ag, ab }) .. label:sub(1, #typed) .. "|r" .. label:sub(#typed + 1))
            else
                r.text:SetText(label)
            end
            W.TextColor(r.text, C.text)
            r.note:SetText(s.note or "")
            r:Show()
        end
        for i = math.min(#list, W.COMPLETE_MAX) + 1, #c.rows do c.rows[i]:Hide() end
        c.list = { unpack(list, 1, W.COMPLETE_MAX) }
        c:SetHeight(#c.list * MENU_ROW + 8)
        -- The list lives on UIParent, but the box may be in a scaled window.
        local w = tonumber(input:GetWidth()) or 0
        local is, cs = tonumber(input:GetEffectiveScale()), tonumber(c:GetEffectiveScale())
        if is and cs and is > 0 and cs > 0 then w = w * is / cs end
        c:SetWidth(math.max(w, 120))
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -2)
        local was, shown = isOpen, c:IsShown()
        isOpen = true
        c:Show()
        paint()
        if not was then
            -- Still fading out: snap back to full instead of fading in from 0.
            local M = DUI.Motion
            if M then M.Fade(c, shown and 1 or 0, 1, M.FAST) else c:SetAlpha(1) end
        end
    end

    function c:IsOpen() return isOpen end

    function c:Close()
        if not isOpen then return end
        isOpen = false
        paint()
        local M = DUI.Motion
        if M and M.On() then
            M.Fade(c, 1, 0, M.FAST)
            closing = closing + 1
            local token = closing
            C_Timer.After(M.FAST, function() if not isOpen and closing == token then c:Hide() end end)
        else
            c:Hide()
        end
    end

    function c:Refresh(text, user)
        text = text or input:GetText() or ""
        local list = text ~= "" and suggest(text, cursorOf(text)) or nil
        if list and #list > 0 then show(list, text) else c:Close() end
    end

    input:HookScript("OnTextChanged", function(self, user)
        if user then c:Refresh(self:GetText() or "") elseif not filling then c:Close() end
    end)
    input:HookScript("OnArrowPressed", function(_, key)
        if not isOpen then return end
        if key == "DOWN" then c.pick = math.min(#c.list, c.pick + 1)
        elseif key == "UP" then c.pick = math.max(1, c.pick - 1) end
        paint()
    end)
    input:HookScript("OnTabPressed", function() if isOpen then fill() end end)
    input:HookScript("OnEditFocusLost", function()
        C_Timer.After(0.1, function() if isOpen and not input:HasFocus() then c:Close() end end)
    end)
    input:HookScript("OnHide", function() c:Close() end)
    local enter, escape = input:GetScript("OnEnterPressed"), input:GetScript("OnEscapePressed")
    input:SetScript("OnEnterPressed", function(self, ...)
        if isOpen then fill() elseif enter then enter(self, ...) end
    end)
    input:SetScript("OnEscapePressed", function(self, ...)
        if isOpen then c:Close() elseif escape then escape(self, ...) end
    end)
    return c
end

function W.dropdown(row, page, item)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(W.CONTROL_WIDTH, 26)
    b.bg = W.Round(b, "BACKGROUND")
    b.bg:SetAllPoints(b)
    W.Tint(b.bg, C.control)
    -- Keep the box outline: a hovered row's wash matches the box color, so
    -- without it the box disappears under the mouse.
    b.edge = W.Round(b, "BORDER", 0, true)
    b.edge:SetAllPoints(b)
    W.Tint(b.edge, C.cardEdge)
    b.text = W.Font(b, W.BODY, SIZE.body, C.text)
    b.text:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -30, 0)
    b.text:SetWordWrap(false)   -- a narrow box cuts its choice short, never stacks it
    b.arrow = W.Icon(b, "ui-chevron.png", 14, C.dim)
    b.arrow:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    -- Choices are fixed (values, order) or fetched each time with choices(),
    -- since shared media arrives as other addons load.
    local function choices()
        if item.choices then return item.choices() end
        return item.values, item.order or W.SortedKeys(item.values)
    end
    function b.Refresh()
        local values = choices()
        local v = Options.Get(page, item)
        -- A shared media pick whose addon is gone shows its saved name.
        -- shownAs(v) overrides the box text for a value (a General media pick shows
        -- what General is set to, see Registry's MediaPick).
        local name = (item.shownAs and item.shownAs(v)) or values[v] or (DUI.Media and DUI.Media.SharedName(v))
        b.text:SetText(Options.Text(name or (item.fallback and values[item.fallback]) or ""))
    end
    b:SetScript("OnEnter", function()
        W.Tint(b.bg, C.controlHover)
        -- Tooltip with the full name when it's too long for the box.
        local cut = b.text:IsTruncated() == true
        if not cut then
            local full = b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth()
            if type(full) ~= "number" then full = b.text:GetStringWidth() end
            local room = b.text:GetWidth()
            cut = type(full) == "number" and type(room) == "number" and room > 0 and full > room + 0.5
        end
        if cut and W.menuOwner ~= b then
            W.NameTip(b, b.text:GetText())
        end
    end)
    b:SetScript("OnLeave", function()
        W.Tint(b.bg, C.control)
        W.HideTooltip()
    end)
    b:SetScript("OnClick", function()
        W.HideTooltip()
        if row.disabled then return end
        if W.menuOwner == b then
            W.CloseMenu()
            return
        end
        -- choices() may return a third value: headings (W.OpenMenu's titles).
        local values, keys, titles = choices()
        local shown = {}
        for k, text in pairs(values) do shown[k] = Options.Text(text) end
        W.OpenMenu(b, keys, shown, Options.Get(page, item), function(k)
            Options.Set(page, item, k)
            -- Extra action for this choice (the accent's "Custom color" opens the
            -- color picker).
            if item.onPick then item.onPick(k) end
            -- Rows outside the panel (the setup guide) aren't redrawn by it.
            if row.Refresh then row.Refresh() end
        end, nil, (item.preview or item.hover or titles) and { preview = item.preview, fetch = item.fetch, onHover = item.hover, titles = titles } or nil)
    end)
    row.control = b
end

-- A choice list's keys sorted by their display text, for lists with no
-- order of their own.
function W.SortedKeys(values)
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(values[a]) < tostring(values[b]) end)
    return keys
end

-- A "Custom" choice: opens the color picker on the current custom color
-- (or white) and saves each change through set({ r, g, b }).
function W.PickCustom(start, set)
    W.OpenColorPicker(start or { 1, 1, 1 }, set)
end

-- While the picker's wheel or opacity bar is held, the latest color waits
-- here and is saved on release, like the slider. Saving a General color
-- repaints the whole UI and the wheel fires every frame of a drag, which
-- caused big frame drops. Only runs while a color is waiting.
W.colorWait = CreateFrame("Frame")
W.COLOR_REST = 0.25
local colorHooked
local colorPending
local function colorRelease()
    if type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") then return end
    W.colorWait:SetScript("OnUpdate", nil)
    local p = colorPending
    colorPending = nil
    if p then p.save(p.color) end
end

-- Opens the game's color picker. onChange({ r, g, b }) fires on change (once,
-- on release, for a drag; onPreview(c) shows each step if given). Cancel
-- restores the starting color.
function W.OpenColorPicker(start, onChange, hasAlpha, onPreview)
    local cp = ColorPickerFrame
    if not cp then return end
    colorPending = nil
    local startA = start[4] or 1
    local previous = { start[1], start[2], start[3] }
    if hasAlpha then previous[4] = startA end
    local function current()
        local r, g, b = cp:GetColorRGB()
        if not hasAlpha then return { r, g, b } end
        local a = startA
        if cp.GetColorAlpha then a = cp:GetColorAlpha() end
        return { r, g, b, a }
    end
    local function moved()
        local c = current()
        if type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") then
            colorPending = { color = c, save = onChange }
            if onPreview then onPreview(c) end
            W.colorWait:SetScript("OnUpdate", colorRelease)
            return
        end
        -- On a controller the sticks move the color every frame they're held. Show
        -- it as it goes and save once they rest W.COLOR_REST seconds or the
        -- picker closes.
        if DUI.Pad and DUI.Pad.On() then
            local p = { color = c, save = onChange }
            colorPending = p
            if onPreview then onPreview(c) end
            C_Timer.After(W.COLOR_REST, function()
                if colorPending ~= p then return end
                colorPending = nil
                p.save(p.color)
            end)
            return
        end
        colorPending = nil
        onChange(c)
    end
    if not colorHooked and cp.HookScript then
        colorHooked = true   -- a local: nothing written on the game's frame
        cp:HookScript("OnHide", function()
            local p = colorPending
            colorPending = nil
            if p then p.save(p.color) end
        end)
    end
    local info = {
        r = start[1], g = start[2], b = start[3], hasOpacity = hasAlpha and true or false,
        opacity = startA,
        swatchFunc = moved,
        opacityFunc = hasAlpha and moved or nil,
        cancelFunc = function() colorPending = nil; onChange(previous) end,
    }
    if cp.SetupColorPickerAndShow then
        cp:SetupColorPickerAndShow(info)
    else
        cp.func, cp.cancelFunc = info.swatchFunc, info.cancelFunc
        cp:SetColorRGB(info.r, info.g, info.b)
        cp:Show()
    end
end

-- A rounded color swatch that opens the picker on click. get() returns
-- { r, g, b }, set(rgb) saves. hasAlpha (optional) adds an opacity slider
-- and a 4th number to set().
local function swatch(parent, row, get, set, hasAlpha)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(44, 24)
    b.edge = W.Round(b, "BACKGROUND")
    b.edge:SetAllPoints(b)
    W.Tint(b.edge, C.control)
    b.fill = W.Round(b, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
    b.fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    local function paint(c)
        if type(c) == "table" then b.fill:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 1) end
    end
    function b.Refresh() paint(get()) end
    b:SetScript("OnEnter", function() W.Tint(b.edge, C.controlHover) end)
    b:SetScript("OnLeave", function() W.Tint(b.edge, C.control) end)
    b:SetScript("OnClick", function()
        if row.disabled then return end
        local c = get() or { 1, 1, 1 }
        W.OpenColorPicker(c, function(col)
            if hasAlpha then set({ col[1], col[2], col[3], col[4] }) else set({ col[1], col[2], col[3] }) end
        end, hasAlpha, paint)
    end)
    return b
end

-- For editors outside the options pages (the buff border popup).
W.Swatch = swatch

function W.color(row, page, item)
    row.control = swatch(row, row, function() return Options.Get(page, item) end,
        function(c) Options.Set(page, item, c) end, item.alpha)
end

-- A pair of colors: a bar preview as painted, then swatches for the dark and
-- light ends. get() returns { lo, hi }, set(pair) saves, preview() (optional)
-- gives the ends as they'll paint. Also used outside the options pages, where
-- row is just the containing frame.
function W.GradientPair(parent, row, get, set, preview)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(90 + 8 + 44 + 6 + 44, 24)
    local function pair() return get() or {} end
    local function setEnd(which, c)
        local v = pair()
        local out = { lo = v.lo, hi = v.hi }
        out[which] = c
        set(out)
    end
    f.hi = swatch(f, row, function() return pair().hi end, function(c) setEnd("hi", c) end)
    f.hi:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.lo = swatch(f, row, function() return pair().lo end, function(c) setEnd("lo", c) end)
    f.lo:SetPoint("RIGHT", f.hi, "LEFT", -6, 0)
    if row.Enter then
        W.Hover(row, f.lo)
        W.Hover(row, f.hi)
    end
    f.preview = W.Round(f, "ARTWORK")
    f.preview:SetSize(90, 14)
    f.preview:SetPoint("RIGHT", f.lo, "LEFT", -8, 0)
    function f.Refresh()
        f.lo.Refresh()
        f.hi.Refresh()
        local v = pair()
        if type(v.lo) ~= "table" or type(v.hi) ~= "table" then return end
        local a, b = v.lo, v.hi
        if preview then a, b = preview() end
        f.preview:SetVertexColor(1, 1, 1, 1)
        if CreateColor and f.preview.SetGradient then
            f.preview:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
        end
    end
    return f
end

function W.gradient(row, page, item)
    row.control = W.GradientPair(row, row, function() return Options.Get(page, item) end,
        function(v) Options.Set(page, item, v) end, item.preview)
end

function W.button(row, page, item)
    local b = W.Button(row, "", 24)
    b.fit = 96
    local function label()
        if type(item.text) == "function" then return Options.Text(item.text()) end
        return Options.Text(item.text or item.label)
    end
    if item.confirm then
        W.Confirm(b, label, item.func)
    else
        local base = b.Paint
        function b.Paint()
            base()
            b.text:SetText(label())
            b.FitWidth(b.fit)
        end
        b:SetScript("OnClick", function()
            if not row.disabled then item.func() end
        end)
        b.Paint()
    end
    function b.Refresh()
        b.disabled = row.disabled
        b.Paint()
    end
    row.control = b
    -- Page-specific extras on the button (the Click-casting page lays a secure
    -- button over it on hover).
    if item.built then item.built(b, row) end
end

-- A full-width paragraph with no control.
function W.text(row, page, item)
    local fs = row.label
    fs:SetFont(W.BODY, SIZE.body, "")
    W.TrackFont(fs, W.BODY, SIZE.body)
    W.TextColor(fs, C.dim)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8)
    fs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -8)
    fs:SetWordWrap(true)
    fs:SetMaxLines(0)   -- a paragraph shows whole: W.Row's two-line cap cut it off
    fs:SetJustifyV("TOP")
    function row.Measure()
        -- Set the text again: text set while the row was hidden measures as one
        -- cut-off line until it's laid out on screen.
        fs:SetText(Options.Label(item))
        local h = fs:GetStringHeight()
        if type(h) ~= "number" or h <= 0 then h = 14 end
        row:SetHeight(h + 16)
    end
    function row.Update() fs:SetText(Options.Label(item)) end
end

-- A module's own content spanning the card (a list, an editor). The item
-- draws into the row: build(row, width) once, update(row) on every refresh,
-- height(row) for its size.
function W.custom(row, page, item)
    row.label:SetText("")
    row.line:SetAlpha(0)
    item.build(row)
    function row.Measure()
        local h = item.height and item.height(row) or W.ROW_HEIGHT
        row:SetHeight(math.max(1, h))
    end
    function row.Update()
        if item.update then item.update(row) end
    end
end

-- Compact rows for narrow side panels (the setup guide's cards). The label
-- sits above a slider or dropdown, or left of a toggle or color, all within
-- width px. Takes the same items as W.Row. opts.inline puts every control
-- right of its label on one line, sliders and dropdowns opts.control px
-- wide, rows opts.height tall (the cooldown layout editor's card).

W.COMPACT_INLINE, W.COMPACT_STACKED = 26, 40
W.COMPACT_CONTROL = 118
local INLINE = { toggle = true, color = true }
local SIZED = { slider = true, dropdown = true }

function W.CompactRow(parent, page, item, width, opts)
    local all = opts ~= nil and opts.inline == true
    local inline = all or INLINE[item.type] == true
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(width)
    row:EnableMouse(true)
    row.page, row.item = page, item
    row.label = W.Font(row, W.BODY, inline and SIZE.body or SIZE.small, inline and C.text or C.dim)
    row.label:SetText(Options.Label(item))
    row.label:SetWordWrap(false)
    -- The builders hook these onto their parts.
    function row.Enter() W.Tooltip(row, Options.Label(item), Options.Text(item.desc)) end
    function row.Leave() if not row:IsMouseOver() then W.HideTooltip() end end
    row:SetScript("OnEnter", row.Enter)
    row:SetScript("OnLeave", row.Leave)

    W[item.type](row, page, item)
    local c = row.control
    c:ClearAllPoints()
    if inline then
        row.height = all and opts.height or W.COMPACT_INLINE
        if all and SIZED[item.type] then c:SetWidth(opts.control or W.COMPACT_CONTROL) end
        c:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label:SetPoint("RIGHT", c, "LEFT", -8, 0)
    else
        row.height = W.COMPACT_STACKED
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        c:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        c:SetWidth(width)
    end
    row:SetHeight(row.height)

    function row.Refresh()
        local disabled = Options.IsDisabled(page, item)
        row.disabled = disabled
        row:SetAlpha(disabled and 0.35 or 1)
        if c.Refresh then c.Refresh() end
    end
    W.PadRow(row)   -- one D-pad stop, as an options row
    return row
end

-- Rows, cards and pages

-- Lights rows up in the gradient, holds, then fades them out. Shows where a
-- click on a frame's live sample lands. A new flash ends the previous one.
W.FLASH_TIME = 2        -- in all, the hold included
W.FLASH_HOLD = 0.5      -- at full before the fade starts
W.FLASH_ALPHA = 0.25
local flashing, flashDriver = {}, nil

local function endFlash()
    for _, row in ipairs(flashing) do row.flash:Hide() end
    flashing = {}
    if flashDriver then flashDriver:SetScript("OnUpdate", nil) end
end

function W.Flash(rows)
    endFlash()
    if #rows == 0 then return end
    flashDriver = flashDriver or CreateFrame("Frame", nil, UIParent)
    for _, row in ipairs(rows) do
        if not row.flash then
            row.flash = W.Round(row, "BACKGROUND", 2)
            row.flash:SetAllPoints(row)
        end
        W.TintDaylight(row.flash, W.FLASH_ALPHA)
        row.flash:Show()
        flashing[#flashing + 1] = row
    end
    local left = W.FLASH_TIME
    flashDriver:SetScript("OnUpdate", function(_, dt)
        left = left - dt
        if left <= 0 then return endFlash() end
        local p = math.min(1, left / (W.FLASH_TIME - W.FLASH_HOLD))
        local a = p * p * (3 - 2 * p)   -- eases in and out of the fade
        -- Through the tint's alpha: in game a gradient ignores SetAlpha.
        for _, row in ipairs(flashing) do W.TintDaylight(row.flash, W.FLASH_ALPHA * a) end
    end)
end

function W.FlashDriver() return flashDriver end

function W.Row(card, page, group, item)
    local row = CreateFrame("Frame", nil, card)
    row:SetHeight(W.ROW_HEIGHT)
    row:EnableMouse(true)
    row.page, row.group, row.item = page, group, item

    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hl:SetAllPoints(row)
    row.hl:SetColorTexture(1, 1, 1, 0.03)
    row.hl:Hide()
    row.line = row:CreateTexture(nil, "BORDER")
    row.line:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    row.line:SetHeight(1)
    row.line:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, 0)
    row.line:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, 0)
    row.label = W.Font(row, W.BODY, SIZE.body, C.text)
    row.label:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
    row.label:SetText(Options.Label(item))
    -- Long labels wrap to a second line and the row grows to fit.
    row.label:SetWordWrap(true)
    row.label:SetMaxLines(2)
    function row.Measure()
        local h = row.label:GetStringHeight()
        if type(h) ~= "number" then h = 0 end
        row:SetHeight(math.max(W.ROW_HEIGHT, math.ceil(h) + 12))
    end

    function row.Enter()
        if item.type == "text" or item.type == "custom" then return end
        row.hl:Show()
        W.Tooltip(row, Options.Label(item), Options.Text(item.desc))
    end
    function row.Leave()
        if row.padOn or row:IsMouseOver() then return end
        row.hl:Hide()
        W.HideTooltip()
    end
    row:SetScript("OnEnter", row.Enter)
    row:SetScript("OnLeave", row.Leave)

    W[item.type](row, page, item)

    -- Recently added rows get a "new" tag next to the label (Options.IsNew).
    if type(item.since) == "string" then
        row.newTag = W.Font(row, W.TITLE, SIZE.tiny, C.text)
        row.newTag:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        row.newTag:SetText(L["NEW"])
        W.TextDaylight(row.newTag)
        local update = row.Update
        function row.Update()
            if update then update() end
            row.newTag:SetShown(Options.IsNew(item))
        end
        row.newTag:SetShown(Options.IsNew(item))
    end

    if row.control then
        row.control:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
        row.label:SetPoint("RIGHT", row.control, "LEFT", -W.LABEL_GAP, 0)
        W.Hover(row, row.control)
    end
    -- item.beside(row) -> frame: extra controls left of the row's own, clear of
    -- the reset arrow (one row per thing instead of a picker). Its Refresh()
    -- runs with the row's.
    if item.beside and row.control then
        row.extras = item.beside(row)
        row.extras:SetPoint("RIGHT", row.control, "LEFT", -W.BESIDE_GAP, 0)
        row.label:SetPoint("RIGHT", row.extras, "LEFT", -W.LABEL_GAP, 0)
    end
    if Options.VALUE[item.type] then
        -- Changed from default: show the reset arrow beside the control.
        local r = CreateFrame("Button", nil, row)
        r:SetSize(16, 16)
        r:SetPoint("RIGHT", row.control, "LEFT", -10, 0)
        r.icon = W.Icon(r, "ui-reset.png", 14, C.faint)
        r.icon:SetPoint("CENTER", r, "CENTER", 0, 0)
        r:SetScript("OnEnter", function()
            W.TintDaylight(r.icon)
            W.Tooltip(r, RESET or L["Reset"], L["Put this back to its default."])
        end)
        r:SetScript("OnLeave", function()
            W.Tint(r.icon, C.faint)
            W.HideTooltip()
            row.Leave()
        end)
        -- On click the arrow spins back half a turn as it fades out.
        r:SetScript("OnClick", function()
            local M = DUI.Motion
            M.Tween(r.icon, 0, math.pi, M.FAST, function(a) r.icon:SetRotation(a) end,
                function() r.icon:SetRotation(0) end)
            Options.ResetItem(page, item)
        end)
        row.reset = r
    end

    function row.Refresh()
        local disabled = Options.IsDisabled(page, item)
        -- A parent switch flipped while visible: the row dims or wakes FAST. The
        -- first fill and hidden rows are set at once.
        local first = not row.filled
        row.filled = true
        W.EaseAlpha(row, disabled and 0.35 or 1, not first and row.disabled ~= disabled)
        row.disabled = disabled
        if row.Update then row.Update() end
        local changed = not disabled and row.reset ~= nil and not Options.IsDefault(page, item)
        if row.reset then W.EaseShown(row.reset, changed, first) end
        if row.control and row.control.Refresh then row.control.Refresh() end
        if row.extras then row.extras.Refresh() end
    end
    W.PadRow(row)
    return row
end

-- A card: rounded panel with a lit top line, a title in its section's
-- color, and its rows.
function W.Card(parent, page, group)
    local card = CreateFrame("Frame", nil, parent)
    card.page, card.group = page, group
    card.bg = W.Round(card, "BACKGROUND")
    card.bg:SetAllPoints(card)
    W.Tint(card.bg, C.card)
    card.edge = W.Round(card, "BORDER", 0, true)
    card.edge:SetAllPoints(card)
    W.Tint(card.edge, C.cardEdge)
    card.lit = card:CreateTexture(nil, "BORDER", nil, 1)
    card.lit:SetHeight(1)
    card.lit:SetPoint("TOPLEFT", card, "TOPLEFT", 8, 0)
    card.lit:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, 0)
    card.lit:SetColorTexture(C.cardLit[1], C.cardLit[2], C.cardLit[3], 1)
    card.title = W.Font(card, W.TITLE, SIZE.head, C.dim) -- card heading: INK.LABEL
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", W.PAD, -12)
    card.title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -W.PAD, -12)
    card.title:SetText(Options.Text(group.label))
    -- A bare card (group.bare) is just its rows: no background or title.
    if group.bare then
        card.bg:Hide()
        card.edge:Hide()
        card.lit:Hide()
        card.title:Hide()
    end
    if group.desc then
        card.desc = W.Font(card, W.BODY, SIZE.small, C.dim)
        -- Width is set in top(), not with a second anchor. Anchored widths aren't
        -- resolved until the next frame, so text measured at the old width (two
        -- lines reserved for three, rows overlapping the last line).
        card.desc:SetPoint("TOPLEFT", card, "TOPLEFT", W.PAD, -32)
        card.desc:SetWordWrap(true)
        card.desc:SetJustifyV("TOP")
        card.desc:SetText(Options.Text(group.desc))
    end
    -- Rows start under the title and the description. The description wraps,
    -- so it's measured once the card has its width.
    local function top()
        if group.bare then return 0 end
        -- No title (Home's greeting): rows start near the top.
        if not card.desc and (group.label or "") == "" then return 6 end
        if not card.desc then return 34 end
        local w = card:GetWidth()
        if type(w) == "number" and w > 2 * W.PAD then card.desc:SetWidth(w - 2 * W.PAD) end
        card.desc:SetText(Options.Text(group.desc))
        local h = card.desc:GetStringHeight()
        if type(h) ~= "number" or h <= 0 then h = 14 end
        return 32 + math.ceil(h) + 8
    end
    card.rows = {}
    for _, item in ipairs(group.items) do card.rows[#card.rows + 1] = W.Row(card, page, group, item) end

    -- Places the rows left by the search and hidden(); returns how many.
    function card.Layout(query)
        card.top = top()
        local y, count = card.top, 0
        for _, row in ipairs(card.rows) do
            local show = not Options.IsHidden(page, row.item) and Options.Matches(group, row.item, query)
            row:SetShown(show)
            if show then
                row.offsetY = y   -- down from the card's top (Panel.JumpTo)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -y)
                if row.Measure then row.Measure() end
                row.line:SetShown(count > 0)
                y = y + row:GetHeight()
                count = count + 1
            end
        end
        card:SetHeight(y + (group.bare and 0 or 6))
        card.count = count   -- W.Chips skips cards with nothing to show
        return count
    end
    function card.Refresh()
        for _, row in ipairs(card.rows) do row.Refresh() end
    end
    return card
end

-- Pages: cards in columns

W.COLUMN_MIN = 330    -- the least width a column of cards gets
W.COLUMNS_MAX = 3

-- Number of card columns for a page this wide.
function W.Columns(width)
    local n = math.floor((width + W.CARD_GAP) / (W.COLUMN_MIN + W.CARD_GAP))
    return math.max(1, math.min(W.COLUMNS_MAX, n))
end

-- A card spans every column when it shows a module's own content or a color
-- pair, or when its group sets wide = true. With a page given, currently
-- hidden rows don't count, so a Custom color pair that only shows once
-- Custom is picked leaves its card in a column.
function W.IsWide(group, page)
    if group.wide then return true end
    for _, item in ipairs(group.items) do
        if (item.type == "custom" or item.type == "gradient")
            and not (page and Options.IsHidden(page, item)) then return true end
    end
    return false
end

function W.Page(parent, page, width)
    local p = CreateFrame("Frame", nil, parent)
    p:SetWidth(width)
    p.page = page
    p.cards = {}
    -- Tabs on long pages: a card's tab is its group's, else the previous card's.
    -- p.tabs lists them in order, nil on pages without tabs. Cards before the
    -- first named one go on the first tab.
    local tab, first
    for _, group in ipairs(page.groups) do
        local card = W.Card(p, page, group)
        if group.tab then tab = group.tab; first = first or tab end
        card.tab = tab
        p.cards[#p.cards + 1] = card
    end
    if first then
        p.tabs = {}
        local seen = {}
        for _, card in ipairs(p.cards) do
            card.tab = card.tab or first
            if not seen[card.tab] then seen[card.tab] = true; p.tabs[#p.tabs + 1] = card.tab end
        end
        p.tab = p.tabs[1]
    end
    -- The visible tab, on pages with tabs.
    function p.SetTab(name) if p.tabs then p.tab = name end end
    -- A single card at full width (chip picked), or nil for all.
    function p.SetFocus(card) p.focus = card end
    -- Only these cards ({ [card] = true }, Design mode's selection), or nil.
    function p.SetFilter(set) p.filter = set end

    -- Whether a card has a visible row right now, before layout.
    local function shows(card, query)
        for _, row in ipairs(card.rows) do
            if not Options.IsHidden(page, row.item) and Options.Matches(card.group, row.item, query) then
                return true
            end
        end
        return false
    end

    -- Places cards in page order, each into the shortest column so far. A wide
    -- card spans all columns and the columns restart level below it. A run of
    -- narrow cards shorter than the column count (one card before a wide one)
    -- shares the full width so no column is left empty. Cards are anchored
    -- before their rows are laid out so wrapped text knows its width.
    -- Returns the number of visible rows.
    function p.Layout(query)
        local width = p:GetWidth()
        if type(width) ~= "number" or width <= 0 then width = W.COLUMN_MIN end
        local max = W.Columns(width)
        local n, colW = max, 0
        local heights = {}
        for i = 1, max do heights[i] = 0 end
        local function bottom()
            local m = 0
            for i = 1, max do m = math.max(m, heights[i]) end
            return m
        end
        local placed = {}
        for _, card in ipairs(p.cards) do
            card.wide = W.IsWide(card.group, page)
            -- Design mode's filter shows its cards on any tab.
            local onTab = p.tab == nil or p.filter ~= nil or card.tab == p.tab
            placed[#placed + 1] = onTab and (p.focus == nil or card == p.focus) and (p.filter == nil or p.filter[card] == true)
                and shows(card, query) and card or false
        end
        local total, inRun = 0, false
        for index, card in ipairs(p.cards) do
            card:ClearAllPoints()
            if placed[index] then
                local full = card.wide or p.focus ~= nil or max == 1
                if full then
                    inRun = false
                elseif not inRun then
                    -- Start of a run of narrow cards: count up to the next wide one.
                    local count = 0
                    for j = index, #p.cards do
                        local other = placed[j]
                        if other then
                            if other.wide then break end
                            count = count + 1
                        end
                    end
                    n = math.max(1, math.min(max, count))
                    colW = math.floor((width - (n - 1) * W.CARD_GAP) / n)
                    inRun = true
                end
                local x, y, col = 0, bottom(), nil
                if not full then
                    col = 1
                    for i = 2, n do
                        if heights[i] < heights[col] then col = i end
                    end
                    x, y = (col - 1) * (colW + W.CARD_GAP), heights[col]
                end
                card:SetWidth(full and width or colW)
                card:SetPoint("TOPLEFT", p, "TOPLEFT", x, -y)
                card.offsetX, card.offsetY, card.column = x, y, col   -- (Panel.JumpTo)
                local rows = card.Layout(query)
                card:SetShown(rows > 0)
                if rows > 0 then
                    total = total + rows
                    local below = y + card:GetHeight() + W.CARD_GAP
                    if full then
                        for i = 1, max do heights[i] = below end
                    else
                        heights[col] = below
                    end
                end
            else
                if p.focus == nil or card == p.focus then card.Layout(query) end   -- keeps card.count
                card:Hide()
            end
        end
        p:SetHeight(math.max(1, bottom()))
        return total
    end
    function p.Refresh()
        for _, card in ipairs(p.cards) do card.Refresh() end
    end
    -- The card and row holding a setting, visible or not (nil if not on this page).
    function p.Find(key)
        for _, card in ipairs(p.cards) do
            for _, row in ipairs(card.rows) do
                if row.item.key == key then return card, row end
                for _, also in ipairs(row.item.alsoKeys or {}) do
                    if also == key then return card, row end
                end
            end
        end
    end
    return p
end

-- Chips: a page's cards by name, "All" first, the visible one lit

W.CHIP_HEIGHT, W.CHIP_GAP, W.CHIP_PAD = 24, 6, 11

-- The standard chip (page cards here, spellbook sections): a small rounded
-- pill whose outline eases to the accent on hover and fills with it when
-- picked (b.SetOn). Click sound built in. Caller sets OnClick, b.FitWidth
-- sizes it.
local chips = setmetatable({}, { __mode = "k" })
DUI.On("StyleChanged", function()
    for b in pairs(chips) do if b:IsVisible() then b.Paint() end end
end)

function W.Chip(parent, text)
    local b = CreateFrame("Button", nil, parent)
    chips[b] = true
    b:SetHeight(W.CHIP_HEIGHT)
    b.base = W.Round(b, "BACKGROUND")
    b.base:SetAllPoints(b)
    W.Tint(b.base, C.card)
    b.bg = W.Round(b, "BACKGROUND", 1)   -- the accent fill, eased in by SetOn
    b.bg:SetAllPoints(b)
    b.edge = W.Round(b, "BORDER", 0, true)
    b.edge:SetAllPoints(b)
    W.Tint(b.edge, C.cardEdge)
    b.lit = W.Round(b, "BORDER", 1, true)
    b.lit:SetAllPoints(b)
    b.text = W.Font(b, W.BODY, SIZE.small, C.dim, "CENTER")
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.text:SetText(text or "")
    b.glow = 0
    b.fill = 0   -- 0 off .. 1 on: the accent fill over the card color
    b.fillKey = {}
    -- Fades go through the tint's alpha, never SetAlpha: in game a texture's
    -- SetAlpha replaces its tint alpha, and an off chip stayed filled.
    function b.Paint()
        local f = b.fill
        W.Tint(b.base, C.card)
        Style.PaintAccent(b.lit, b.glow * (1 - f))
        Style.PaintAccent(b.bg, 0.9 * f)
        W.Tint(b.edge, C.cardEdge, (C.cardEdge[4] or 1) * (1 - f))
        if f > 0.5 then
            W.TextColor(b.text, W.OnAccent())
        else
            W.TextColor(b.text, b.glow > 0.5 and C.text or C.dim)
        end
    end
    local function ease(to)
        local M = DUI.Motion
        if M then
            M.Tween(b.lit, b.glow, to, M.FAST, function(v) b.glow = v; b.Paint() end)
        else
            b.glow = to
            b.Paint()
        end
    end
    -- Picked or unpicked while visible: the fill floods in or drains FAST.
    function b.SetOn(on)
        b.on = on and true or nil
        local goal = b.on and 1 or 0
        local M = DUI.Motion
        if b:IsVisible() and M then
            M.Tween(b.fillKey, b.fill, goal, M.FAST, function(v) b.fill = v; b.Paint() end)
        else
            if M then M.Tween(b.fillKey, 0, 0, 0) end
            b.fill = goal
            b.Paint()
        end
    end
    function b.FitWidth()
        local tw = b.text:GetStringWidth()
        if type(tw) ~= "number" or tw <= 0 then tw = 7 * #(b.text:GetText() or "") end
        b:SetWidth(math.floor(tw + 2 * W.CHIP_PAD + 0.5))
    end
    b:SetScript("OnEnter", function() ease(1) end)
    b:SetScript("OnLeave", function() ease(0) end)
    b:SetScript("OnHide", function()
        b.glow = 0
        if DUI.Motion then DUI.Motion.Tween(b.fillKey, 0, 0, 0) end
        b.fill = b.on and 1 or 0
        b.Paint()
    end)
    b:SetScript("PostClick", function() if DUI.Sound then DUI.Sound.Play("click") end end)
    b.Paint()
    return b
end

-- Chips on parent. chips.Set(cards, focus) makes "All" plus one chip per
-- titled card and lights the focused one (nil means All). chips.count is how
-- many cards got one. chips.Layout(width) wraps them onto more lines and
-- returns the height. Clicking calls onPick(card), or onPick(nil) for All.
function W.Chips(parent, onPick)
    local chips = CreateFrame("Frame", nil, parent)
    chips.buttons = {}
    chips.count = 0
    local list = {}
    function chips.Set(cards, focus)
        list = { false }
        for _, card in ipairs(cards) do
            if not card.group.bare and (card.group.label or "") ~= "" and card.count ~= 0 then
                list[#list + 1] = card
            end
        end
        for i, entry in ipairs(list) do
            local b = chips.buttons[i]
            if not b then
                b = W.Chip(chips)
                b:SetScript("OnClick", function(self) onPick(self.card) end)   -- once: it reads self.card
                chips.buttons[i] = b
            end
            b.card = entry or nil
            b.text:SetText(entry and Options.Text(entry.group.label) or ALL or L["All"])
            b.SetOn(b.card == focus)
            b:Show()
        end
        for i = #list + 1, #chips.buttons do chips.buttons[i]:Hide() end
        chips.count = #list - 1
    end
    function chips.Layout(width)
        local x, y = 0, 0
        for i = 1, #list do
            local b = chips.buttons[i]
            b.FitWidth()
            local w = b:GetWidth()
            if x > 0 and x + w > width then x, y = 0, y + W.CHIP_HEIGHT + W.CHIP_GAP end
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", chips, "TOPLEFT", x, -y)
            x = x + w + W.CHIP_GAP
        end
        local h = y + W.CHIP_HEIGHT
        chips:SetSize(width, h)
        return h
    end
    return chips
end

-- Role badge for the group finder using the game's round role art: filled
-- when the role is taken, a faint ring when it's open. b.Set(role, open)
-- takes TANK, HEALER or DAMAGER and hides for anything else.
-- W.RoleText(role, size) is the same art inline in text (tooltips).
W.ROLE = 16
W.ROLE_ART = { TANK = "groupfinder-icon-role-large-tank", HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps" }
W.ROLE_OPEN = 0.3   -- an open spot's art: see-through and without color

function W.Role(parent, size)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(size or W.ROLE, size or W.ROLE)
    b.art = b:CreateTexture(nil, "ARTWORK")
    b.art:SetAllPoints(b)
    function b.Set(role, open)
        local atlas = W.ROLE_ART[role]
        b:SetShown(atlas ~= nil)
        if not atlas then return end
        b.art:SetAtlas(atlas)
        b.art:SetDesaturated(open == true)
        b.art:SetAlpha(open and W.ROLE_OPEN or 1)
    end
    return b
end

function W.RoleText(role, size)
    local atlas = W.ROLE_ART[role]
    if not atlas or type(CreateAtlasMarkup) ~= "function" then return "" end
    return CreateAtlasMarkup(atlas, size or 14, size or 14)
end

-- A one-line text prompt (a name, a rename, a search) using the game's
-- confirm dialog, which the Skins restyle. onAccept gets the trimmed text,
-- never empty unless opts.empty. It runs after the dialog closes: the game
-- hides a dialog after its OnAccept, so a second W.Prompt opened from inside
-- it would reuse that dialog and close on the same click (StaticPopup_OnClick).
-- opts.now runs it inside the click instead, for game calls that refuse to
-- run from a timer (friend invites, broadcasts).
function W.Prompt(text, initial, onAccept, opts)
    local which = "DAYLIGHTUI_PROMPT"
    if not StaticPopupDialogs[which] then
        local function accept(box, d)
            local value = box and strtrim(box:GetText() or "") or ""
            if (value ~= "" or (d and d.empty)) and d and d.onAccept then
                if d.now then d.onAccept(value) else C_Timer.After(0, function() d.onAccept(value) end) end
            end
        end
        StaticPopupDialogs[which] = {
            text = "%s", button1 = ACCEPT or L["Accept"], button2 = CANCEL or L["Cancel"],
            hasEditBox = true, editBoxWidth = 260, timeout = 0, whileDead = true, hideOnEscape = true,
            preferredIndex = 3,
            OnShow = function(self, d)
                local box = self.editBox or self.EditBox
                if box then
                    box:SetText(d and d.initial or "")
                    box:HighlightText()
                    box:SetFocus()
                end
            end,
            OnAccept = function(self, d) accept(self.editBox or self.EditBox, d) end,
            EditBoxOnEnterPressed = function(box)
                local parent = box:GetParent()
                accept(box, parent.data)
                parent:Hide()
            end,
            EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        }
    end
    StaticPopup_Show(which, text, nil, { initial = initial, onAccept = onAccept, empty = opts and opts.empty, now = opts and opts.now })
end
