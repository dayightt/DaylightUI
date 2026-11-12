-- EdgeEditor: the small pop-up a category's color square opens. Solid or
-- Gradient, then either the one color swatch or the gradient maker (the
-- same one the Gradients page uses). No full-screen click catcher like the
-- dropdowns have: the game's color picker opens over it, and a catcher
-- would close it on the first click in the picker. It closes on its x
-- button, Escape, a second click on the same square, or with the options
-- window.

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local EdgeEditor = {}
BL.EdgeEditor = EdgeEditor

local function UI() return DUI.Widgets end
local function colors() return DUI.Widgets.COLORS end

local WIDTH, PAD, GAP = 240, 12, 6
local frame

local function currentPair()
    if not frame or not BL.Categories.Get(frame.id) then return nil end
    local lo, hi = BL.Categories.Pair(frame.id)
    return { lo = lo, hi = hi }
end

local function build()
    local W, C = UI(), colors()
    frame = CreateFrame("Frame", "DaylightUIBuffsEdgeEditor", UIParent)
    frame:SetSize(WIDTH, 110)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    DUI.Style.Shell(frame, { bgAlpha = 0.97 })

    frame.title = W.Font(frame, W.BODY, DUI.Style.SIZE.head, C.text)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)

    frame.close = W.Button(frame, "x", 20)
    frame.close:SetWidth(20)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD + 4, -PAD + 4)
    frame.close:SetScript("OnClick", function() DUI.Motion.Vanish(frame) end)

    local half = (WIDTH - PAD * 2 - GAP) / 2
    frame.solid = W.Button(frame, L["Solid"], 22)
    frame.solid:SetWidth(half)
    frame.solid:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -40)
    frame.solid:SetScript("OnClick", function() BL.Categories.SetStyle(frame.id, "solid") end)
    frame.gradient = W.Button(frame, L["Gradient"], 22)
    frame.gradient:SetWidth(half)
    frame.gradient:SetPoint("LEFT", frame.solid, "RIGHT", GAP, 0)
    frame.gradient:SetScript("OnClick", function() BL.Categories.SetStyle(frame.id, "gradient") end)

    -- Live picker updates are quiet: a repaint, not a rebuild of the bar.
    frame.color = W.Swatch(frame, frame,
        function()
            local cat = BL.Categories.Get(frame.id)
            return cat and cat.color
        end,
        function(c) BL.Categories.SetColor(frame.id, c, true) end)
    frame.color:SetPoint("TOPLEFT", frame.solid, "BOTTOMLEFT", 0, -12)

    frame.pair = W.GradientPair(frame, frame, currentPair,
        function(v) BL.Categories.SetGradient(frame.id, v.lo, v.hi, true) end,
        function()
            local p = currentPair()
            return DUI.Gradients.PaintRGBOf(p.lo, p.hi)
        end)
    frame.pair:SetPoint("TOPLEFT", frame.solid, "BOTTOMLEFT", 0, -12)

    local options = _G.DaylightUIOptions
    if options then options:HookScript("OnHide", EdgeEditor.Close) end
    frame:Hide()
    -- Glides in, fades out (Escape too).
    DUI.Motion.Window(frame, 6)
end

function EdgeEditor.Refresh()
    if not frame or not frame:IsShown() then return end
    local cat = BL.Categories.Get(frame.id)
    if not cat then frame:Hide(); return end
    frame.title:SetText(BL.Categories.Label(frame.id))
    local grad = BL.Categories.IsGradient(frame.id)
    frame.solid.SetActive(not grad)
    frame.gradient.SetActive(grad)
    if grad then
        frame.color:Hide()
        frame.pair:Show()
        frame.pair.Refresh()
    else
        frame.pair:Hide()
        frame.color:Show()
        frame.color.Refresh()
    end
end

function EdgeEditor.Open(id, owner)
    if not frame then build() end
    if DUI.Motion.Shown(frame) and frame.id == id then DUI.Motion.Vanish(frame); return end
    frame.id = id
    frame:ClearAllPoints()
    if owner then
        frame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -4, -6)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:Show()
    EdgeEditor.Refresh()
end

-- Closes along with the options window, which closes instantly.
function EdgeEditor.Close()
    if frame then frame:Hide() end
end

function EdgeEditor.Frame() return frame end

BL.On("CATEGORY_COLOR_CHANGED", function() EdgeEditor.Refresh() end)
BL.On("CATEGORIES_CHANGED", function() EdgeEditor.Refresh() end)
