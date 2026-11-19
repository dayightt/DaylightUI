-- A tooltip fades out instead of vanishing. The game hides its tooltips itself
-- (an owner's OnLeave calls Hide) and Daylight UI can't hold one open, so a
-- ghost does it: a copy of what was on the screen (the box in its border
-- color, every line, the health bar, a compare tooltip's tab) in the same spot,
-- fading out over NORMAL. With the rich look the card itself is lent to the
-- ghost and handed back when the fade ends or the tooltip shows again.
-- Never in combat, never with General's Motion off, and never when anything
-- on it is secret (its spots can't be read then): it just goes, as before.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret

local Ghost = {}
ns.TipGhost = Ghost

Ghost.MIN_ALPHA = 0.05 -- fainter than this, there's nothing to fade
Ghost.MAX_TEXTURES = 10 -- the game's embedded icons, <name>Texture1..10

local ghosts = setmetatable({}, { __mode = "k" }) -- tooltip -> its ghost
local notes = setmetatable({}, { __mode = "k" })  -- tooltip -> { l, b, w, h, t }: where it was last drawn
local shownAt = setmetatable({}, { __mode = "k" })
local lent = setmetatable({}, { __mode = "k" })   -- rich card -> the tooltip it belongs to

local function num(v) return type(v) == "number" and not isSecret(v) end

-- Called every frame before drawing (Tip.OnUpdate): the game clears a
-- tooltip's padding in its own OnHide, before ours runs, and the rich card's
-- size is that padding. So the ghost goes where the tooltip was last drawn.
function Ghost.Note(tip)
    local l, b, w, h = tip:GetRect()
    if not (num(l) and num(b) and num(w) and num(h)) then
        notes[tip] = nil
        return
    end
    local n = notes[tip]
    if not n then
        n = {}
        notes[tip] = n
    end
    n[1], n[2], n[3], n[4], n.t = l, b, w, h, GetTime()
end

local function boxOpts()
    return { borderPx = ns.Tooltip.BORDER, flat = true, noBevel = true, bgAlpha = ns.Tooltip.BackAlpha() }
end

local function make(tip)
    local g = CreateFrame("Frame", nil, UIParent)
    g:EnableMouse(false)
    g:Hide()
    g.tip = tip
    -- The box and the tab sit under the words, as the tooltip's own shell does.
    g.box = CreateFrame("Frame", nil, g)
    g.box:SetAllPoints(g)
    g.shell = Style.Shell(g.box, boxOpts())
    g.words = CreateFrame("Frame", nil, g)
    g.words:SetAllPoints(g)
    g.texts, g.icons = {}, {}
    ghosts[tip] = g
    return g
end

-- The ghost's copy of a box (the tooltip's shell or its tab's): same look,
-- same colors, at the same moment.
local function paintShell(gs, src)
    local o, so = gs.opts, src.opts
    if o.bgAlpha ~= so.bgAlpha then
        o.bgAlpha = so.bgAlpha
        Style.LayoutShell(gs)
    end
    Style.SetShellColors(gs, so.borderColor, nil, so.borderPair)
end

local function text(g, i)
    local fs = g.texts[i]
    if not fs then
        fs = g.words:CreateFontString(nil, "ARTWORK")
        g.texts[i] = fs
    end
    return fs
end

-- One of the tooltip's texts, copied where it is, relative to the tooltip's
-- top left. False when it can't be (its spot is secret).
local function copyText(g, n, src, l0, t0)
    if not (type(src) == "table" and src:IsShown()) then return n end
    local words = src:GetText()
    -- A line the game filled with a secret (under restrictions) can't be
    -- compared, and its spot can't be read either: no ghost then.
    if isSecret(words) then return false end
    if type(words) == "nil" or words == "" then return n end
    local l, t, w, h = src:GetLeft(), src:GetTop(), src:GetWidth(), src:GetHeight()
    if not (num(l) and num(t) and num(w) and num(h)) then return false end
    n = n + 1
    local fs = text(g, n)
    fs:SetFontObject(src:GetFontObject() or GameTooltipText)
    local justify = src:GetJustifyH() or "LEFT"
    fs:SetJustifyH(justify)
    fs:SetJustifyV(src:GetJustifyV() or "TOP")
    fs:SetWordWrap(src:CanWordWrap() ~= false)
    fs:SetTextColor(src:GetTextColor())
    -- A hair wider than the line, so the same words never wrap one more time.
    fs:SetSize(w + 1, h)
    fs:ClearAllPoints()
    if justify == "RIGHT" then
        fs:SetPoint("TOPRIGHT", g, "TOPLEFT", l - l0 + w, t - t0)
    else
        fs:SetPoint("TOPLEFT", g, "TOPLEFT", l - l0, t - t0)
    end
    fs:SetText(words)
    fs:SetAlpha(src:GetAlpha() or 1)
    fs:Show()
    return n
end

local function copyIcon(g, n, src, l0, t0)
    if not (type(src) == "table" and src:IsShown()) then return n end
    local file = src:GetTexture()
    if isSecret(file) then return false end
    if type(file) == "nil" then return n end
    local l, t, w, h = src:GetLeft(), src:GetTop(), src:GetWidth(), src:GetHeight()
    if not (num(l) and num(t) and num(w) and num(h)) then return false end
    n = n + 1
    local tex = g.icons[n]
    if not tex then
        tex = g.words:CreateTexture(nil, "ARTWORK")
        g.icons[n] = tex
    end
    tex:SetTexture(file)
    tex:SetTexCoord(src:GetTexCoord())
    tex:SetVertexColor(src:GetVertexColor())
    tex:SetSize(w, h)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", g, "TOPLEFT", l - l0, t - t0)
    tex:Show()
    return n
end

-- The health bar under GameTooltip: a bar of the ghost's own, the same fill
-- and color, the value passed whole (it's secret for every unit).
local function copyBar(g, tip)
    local bar = tip == GameTooltip and GameTooltipStatusBar
    local cfg = ns.Tooltip.Config()
    local want = type(bar) == "table" and bar:IsShown() and cfg and cfg.healthBar and not ns.Tooltip.barHidden
    if not want then
        if g.bar then g.bar:Hide() end
        return
    end
    local gb = g.bar
    if not gb then
        gb = CreateFrame("StatusBar", nil, g.words)
        Style.TrackBar(gb, nil, ns.MEDIA.bars.health)
        local back = gb:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(gb)
        Style.TrackBack(back, ns.MEDIA.bars.health)
        back:SetVertexColor(0, 0, 0, 0.6)
        gb.edge = gb:CreateTexture(nil, "BACKGROUND", nil, -8)
        gb.edge:SetColorTexture(0, 0, 0, 1)
        g.bar = gb
    end
    local px = DUI.Pixel.Px(bar, 1)
    gb:ClearAllPoints()
    gb:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -ns.Tooltip.BAR_GAP)
    gb:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", 0, -ns.Tooltip.BAR_GAP)
    gb:SetHeight(cfg.barHeight)
    gb.edge:ClearAllPoints()
    gb.edge:SetPoint("TOPLEFT", gb, "TOPLEFT", -px, px)
    gb.edge:SetPoint("BOTTOMRIGHT", gb, "BOTTOMRIGHT", px, -px)
    gb:SetMinMaxValues(bar:GetMinMaxValues())
    gb:SetValue(bar:GetValue())
    ns.Tooltip.PaintLike(gb, bar)
    gb:Show()
end

-- A compare tooltip's tab: its box and its word.
local function copyTab(g, tip, n, l0, t0)
    local hs = ns.Tooltip.HeaderShell(tip)
    local h = tip.CompareHeader
    if not (hs and hs:IsShown() and type(h) == "table" and h:IsShown()) then
        if g.tab then g.tab:Hide() end
        return n
    end
    local l, t, w, hh = hs:GetLeft(), hs:GetTop(), hs:GetWidth(), hs:GetHeight()
    if not (num(l) and num(t) and num(w) and num(hh)) then return false end
    if not g.tab then
        g.tab = CreateFrame("Frame", nil, g)
        g.tab.shell = Style.Shell(g.tab, boxOpts())
    end
    g.tab:ClearAllPoints()
    g.tab:SetPoint("TOPLEFT", g, "TOPLEFT", l - l0, t - t0)
    g.tab:SetSize(w, hh)
    paintShell(g.tab.shell, hs)
    g.tab:Show()
    return copyText(g, n, h.Label, l0, t0)
end

local function clear(g)
    for _, fs in ipairs(g.texts) do fs:Hide() end
    for _, tex in ipairs(g.icons) do tex:Hide() end
    if g.bar then g.bar:Hide() end
    if g.tab then g.tab:Hide() end
end

-- The tooltip's own look copied into the ghost. False when something on it
-- can't be read (secret), and then there's no ghost.
local function copyLook(g, tip)
    local l0, t0 = tip:GetLeft(), tip:GetTop()
    if not (num(l0) and num(t0)) then return false end
    local n = 0
    local count = tip.NumLines and tip:NumLines()
    if not num(count) then return false end
    for i = 1, count do
        for _, side in ipairs({ "Left", "Right" }) do
            n = copyText(g, n, ns.Tooltip.Line(tip, i, side), l0, t0)
            if not n then return false end
        end
    end
    n = copyTab(g, tip, n, l0, t0)
    if not n then return false end
    for i = n + 1, #g.texts do g.texts[i]:Hide() end
    local name = tip:GetName()
    local k = 0
    for i = 1, Ghost.MAX_TEXTURES do
        local icon = name and _G[name .. "Texture" .. i]
        if type(icon) ~= "table" then break end
        k = copyIcon(g, k, icon, l0, t0)
        if not k then return false end
    end
    for i = k + 1, #g.icons do g.icons[i]:Hide() end
    local s = ns.Tooltip.Shell(tip)
    g.box:SetShown(s ~= nil and s:IsShown())
    if s then paintShell(g.shell, s) end
    copyBar(g, tip)
    return true
end

-- The rich card goes to the ghost as it is: nothing on it has to be copied.
local function lend(g, p)
    lent[p] = g.tip
    g.card = p
    p:SetParent(g)
    p:ClearAllPoints()
    p:SetAllPoints(g)
    ns.RichPanel.Level(p)
    p:Show()
end

-- Back to its tooltip, hidden if the tooltip let it go meanwhile.
local function giveBack(g)
    local p = g.card
    if not p then return end
    g.card = nil
    local released = lent[p] == false
    lent[p] = nil
    p:SetParent(g.tip)
    p:ClearAllPoints()
    p:SetAllPoints(g.tip)
    ns.RichPanel.Level(p)
    if released or not g.tip:IsShown() then p:Hide() end
end

-- The card is lent out: Panel.Release leaves it showing and the ghost hides it
-- when it hands it back.
function Ghost.Holds(p)
    if lent[p] == nil then return false end
    lent[p] = false
    return true
end

local function done(g)
    g.run = nil
    g:Hide()
    giveBack(g)
end

-- The tooltip is going: from its OnHide, or as it's muted when the mouse
-- leaves something in the world.
function Ghost.Take(tip)
    local Tip = ns.Tooltip
    if not (DUI.Motion.On() and Tip.Shell(tip)) then return end
    if InCombatLockdown() or not UIParent:IsVisible() or Tip.Muted(tip) then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    -- Shown and gone in one frame: it was never drawn.
    if shownAt[tip] == GetTime() then return end
    local a = tip:GetAlpha()
    if not num(a) or a < Ghost.MIN_ALPHA then return end
    local n = notes[tip]
    local l, b, w, h
    if n and n.t >= (shownAt[tip] or 0) then
        l, b, w, h = n[1], n[2], n[3], n[4]
    else
        l, b, w, h = tip:GetRect()
    end
    if not (num(l) and num(b) and num(w) and num(h)) or w <= 0 or h <= 0 then return end
    local g = ghosts[tip] or make(tip)
    if g.run then done(g) end
    local p = ns.RichPanel.Get(tip)
    local card = p and p:IsShown() and not p.chrome and ns.Rich.On(tip)
    clear(g)
    if card then
        g.box:Hide()
    elseif not copyLook(g, tip) then
        clear(g)
        return
    end
    local scale = tip:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if not (num(scale) and scale > 0) then return end
    g:SetScale(scale)
    g:SetFrameStrata(tip:GetFrameStrata())
    local level = tip:GetFrameLevel()
    g:SetFrameLevel(math.max(0, level - 3))
    g.box:SetFrameLevel(math.max(0, level - 1))
    g.words:SetFrameLevel(level)
    if g.shell.over then g.shell.over:SetFrameLevel(level + 10) end
    if g.tab then g.tab:SetFrameLevel(math.max(0, level - 1)) end
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    g:SetSize(w, h)
    if card then lend(g, p) end
    local run = {}
    g.run, g.from = run, a
    g:SetAlpha(a)
    g:Show()
    DUI.Motion.Tween(run, 0, 1, DUI.Motion.NORMAL, function(e)
        if g.run ~= run then return end
        g:SetAlpha(a * (1 - e))
    end, function()
        if g.run == run then done(g) end
    end)
end

-- The tooltip shows again (OnShow, before anything else of Daylight UI's):
-- its ghost goes and the card comes home. Returns the alpha the ghost was at,
-- so the new tooltip can rise from there instead of from nothing.
function Ghost.Cancel(tip)
    shownAt[tip] = GetTime()
    local g = ghosts[tip]
    if not (g and g.run) then return nil end
    local a = g:GetAlpha()
    done(g)
    return num(a) and a or nil
end


function Ghost.Of(tip) return ghosts[tip] end
