-- The breath bar (also fatigue, feign death and the release timer) drawn as one
-- of our bars: framed like the cast bar (Style.Shell, so border settings apply),
-- angled on the right end unless breathSlant is off, label inside, and filled
-- with its gradient pair (TIMER_<timer>). The game's bar keeps working,
-- invisible underneath; ours copies its range, value and label every frame
-- while it's shown. Positioning stays the game's.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style, Pixel = DUI.Style, DUI.Pixel

local Breath = {
    WIDTH = 200,
    HEIGHT = 8, -- fill height; the border goes around it, like the free power bar
    SLANT = 0.6, -- angled cut as a fraction of the height, like the nameplates' thin bars
    TEXT = Style.SIZE.small,
}
ns.Breath = Breath
Breath.holders = setmetatable({}, { __mode = "k" }) -- the game's timer frame -> ours

local function paint(h)
    local G = DUI.Gradients
    if not G then return end
    local key = "TIMER_" .. tostring(h.timer.timer)
    G.Paint(h.bar, G.Has(key) and key or "FALLBACK")
end

-- Copies the game's bar, label and timer kind onto ours. MirrorTimerMixin
-- updates them every frame; they're plain numbers, never secret.
function Breath.Sync(h)
    local t = h.timer
    local game = t.StatusBar
    local lo, hi = game:GetMinMaxValues()
    if type(lo) == "number" and type(hi) == "number" and (lo ~= h.lo or hi ~= h.hi) then
        h.lo, h.hi = lo, hi
        h.bar:SetMinMaxValues(lo, hi)
    end
    local v = game:GetValue()
    if type(v) == "number" and v ~= h.value then
        h.value = v
        h.bar:SetValue(v)
    end
    local label = type(t.Text) == "table" and t.Text.GetText and t.Text:GetText()
    if label ~= h.label then
        h.label = label
        h.text:SetText(label or "")
    end
    if t.timer ~= h.kind then
        h.kind = t.timer
        if t.timer then paint(h) end
    end
end

-- Size, angle and inner bar. Rerun when the style changes.
local function layout(h)
    local T = Pixel.Px(h, Style.BorderPx(h))
    -- A fixed outer height left no room for the fill under a thick border on a
    -- small UI scale (8 px at 0.65 showed a black bar).
    local height = Pixel.Snap(h, Breath.HEIGHT) + 2 * T
    h:SetSize(2 * Pixel.Snap(h, Breath.WIDTH / 2), height)
    local cut = DUI:Get("Skins", "breathSlant") == false and 0 or Pixel.Snap(h, height * Breath.SLANT)
    Style.Slant(h, "right", cut)
    Style.AngleFill(h.bar, "right", cut * (height - 2 * T) / height)
    h.bar:ClearAllPoints()
    h.bar:SetPoint("TOPLEFT", h, "TOPLEFT", T, -T)
    h.bar:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -T, T)
    if h.timer.timer then paint(h) end
end

local function build(Kit, t)
    local game = t.StatusBar
    local h = CreateFrame("Frame", nil, t)
    h.timer = t
    h:SetPoint("CENTER", game, "CENTER", 0, 0)
    Style.Shell(h)
    Style.Slant(h, nil, 0)
    h.bar = Style.Bar(h)
    Style.Clip(h, h.bar:GetStatusBarTexture(), "inner")
    Style.Clip(h, Style.BarBack(h.bar), "inner")
    local overlay = CreateFrame("Frame", nil, h)
    overlay:SetAllPoints(h)
    overlay:SetFrameLevel(h.bar:GetFrameLevel() + 3)
    h.text = Style.Text(overlay, Breath.TEXT, "CENTER")
    h.text:SetPoint("CENTER", h, "CENTER", 0, 0)
    -- The game's own: art stripped, bar and label kept but invisible.
    Kit.Strip(t)
    game:SetAlpha(0)
    if type(t.Text) == "table" then t.Text:SetAlpha(0) end
    -- Ours is a child of the game's timer, so it hides with it and nothing runs
    -- when no timer is up. It copies range, value, label and timer kind each
    -- frame, setting each only when it changed. No hooks on the game's bar.
    h:SetScript("OnUpdate", Breath.Sync)
    t:HookScript("OnShow", function() Breath.Sync(h) end)
    Breath.holders[t] = h
    Breath.Sync(h)
    layout(h)
end

Engine.Register({ key = "breath", pack = "system", apply = function(Kit)
    local c = _G.MirrorTimerContainer
    if type(c) ~= "table" or type(c.mirrorTimers) ~= "table" then return end
    for _, t in ipairs(c.mirrorTimers) do
        if type(t.StatusBar) == "table" and type(t.Setup) == "function" and not Breath.holders[t] then
            build(Kit, t)
        end
    end
    if Breath.wired then return end
    Breath.wired = true
    -- General changes repaint the style; StyleChanged follows once.
    DUI.On("StyleChanged", function()
        for _, h in pairs(Breath.holders) do layout(h) end
    end)
    DUI.On("SettingChanged", function(scope, path)
        if scope ~= "Skins" or path ~= "breathSlant" then return end
        for _, h in pairs(Breath.holders) do layout(h) end
    end)
end })
