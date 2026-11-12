-- Optional data bar along the bottom of the screen, off by default. It uses
-- the same texts as the panel's strip, built as three DT.New strips: left
-- side, center tab, right side.
--
-- It slides in by moving an inner frame, so the fade and mover on the outer
-- frame are untouched. When wide enough to reach the screen corners, it
-- reserves bottom room so unmoved pieces there shift up (Movers.SetBottomRoom).

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion
local DT = ns.DataTexts

local Bar = {}
ns.DataBar = Bar

Bar.KEY = "infopanel.databar"
Bar.HOME = { "BOTTOM", nil, "BOTTOM", 0, 0 }
Bar.SIDE = 4           -- texts on each side of the center slot
Bar.TAB_W = 128        -- center tab width and angled cut
Bar.TAB_CUT = 12
Bar.TAB_ALPHA = 0.14   -- accent tint on the tab
Bar.INSET = 22         -- text inset from the angled ends and the tab
Bar.CORNER = 460       -- width a screen corner needs for chat or a meter window
Bar.CLOCK_UP = 2       -- center text size bonus
Bar.LINE_ALPHA = 0.55  -- top accent line opacity and thickness
Bar.LINE_PX = 3
Bar.LIGHT_PX = 2       -- hover highlight line, padding and wash
Bar.LIGHT_PAD = 8
Bar.WASH = 0.12
Bar.STAGGER = 0.025    -- delay between texts fading in

-- Tooltip above the text, or below if the bar was moved to the top half.
local function tipSpot(s)
    local _, y = Bar.frame:GetCenter()
    if type(y) == "number" and y > UIParent:GetHeight() / 2 then
        GameTooltip:SetPoint("TOP", s, "BOTTOM", 0, -DT.TIP_GAP)
    else
        GameTooltip:SetPoint("BOTTOM", s, "TOP", 0, DT.TIP_GAP)
    end
end

local function hover(s, on) Bar.Hover(s, on) end

-- Each strip covers its own stretch of the accent gradient, left to right.
local function strip(from, to)
    return DT.New({}, { tip = tipSpot, hover = hover,
        spot = function(t) return from + (to - from) * t end })
end
Bar.left, Bar.center, Bar.right = strip(0, 0.42), strip(0.5, 0.5), strip(0.58, 1)

-- ---------------------------------------------------------------------
-- Hover highlight, which glides from text to text
-- ---------------------------------------------------------------------

local function layLight(l, x, w, r, g, b)
    l.x, l.w, l.r, l.g, l.b = x, w, r, g, b
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", Bar.body, "TOPLEFT", x, 0)
    l:SetPoint("BOTTOMLEFT", Bar.body, "BOTTOMLEFT", x, 0)
    l:SetWidth(w)
    l.line:SetColorTexture(r, g, b, 1)
    l.wash:SetColorTexture(1, 1, 1, 1)
    if l.wash.SetGradient and CreateColor then
        l.wash:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, Bar.WASH))
    end
end

function Bar.Hover(s, on)
    local l = Bar.light
    if not on then return Motion.AlphaTo(l, 0, Motion.NORMAL, true) end
    local a, b, base = s:GetLeft(), s:GetRight(), Bar.body:GetLeft()
    if type(a) ~= "number" or type(b) ~= "number" or type(base) ~= "number" then return end
    local w = (s.text:GetStringWidth() or 0) + s.iconW + 2 * Bar.LIGHT_PAD
    local x = (a + b - w) / 2 - base
    local r, g, c = Style.AccentAt(s.spot)
    if l:IsShown() and l.x then
        local x0, w0, r0, g0, c0 = l.x, l.w, l.r, l.g, l.b
        Motion.Tween(l, 0, 1, Motion.NORMAL, function(t)
            layLight(l, x0 + (x - x0) * t, w0 + (w - w0) * t, r0 + (r - r0) * t, g0 + (g - g0) * t, c0 + (c - c0) * t)
        end)
    else
        layLight(l, x, w, r, g, c)
    end
    Motion.AlphaTo(l, 1, Motion.FAST)
end

-- ---------------------------------------------------------------------
-- Build and layout
-- ---------------------------------------------------------------------

-- Offset of the inner body below its resting spot (0 = fully in).
function Bar.Slid(y)
    local body, f = Bar.body, Bar.frame
    Bar.slid = y
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -y)
end

function Bar.Build(mod)
    local f = CreateFrame("Frame", "DaylightUIDataBar", UIParent)
    f:SetFrameStrata("LOW")
    f:Hide()
    Bar.frame = f
    local body = CreateFrame("Frame", nil, f)
    Style.Shell(body, { flat = true })
    Style.Slant(body, "both", Bar.TAB_CUT)
    Bar.body = body
    Bar.line = body:CreateTexture(nil, "OVERLAY")
    Bar.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    Style.Clip(body, Bar.line, "outer")

    local light = CreateFrame("Frame", nil, body)
    light:SetFrameLevel(body:GetFrameLevel() + 2)
    light.wash = light:CreateTexture(nil, "ARTWORK")
    light.wash:SetAllPoints(light)
    light.line = light:CreateTexture(nil, "OVERLAY")
    light.line:SetPoint("TOPLEFT", light, "TOPLEFT")
    light.line:SetPoint("TOPRIGHT", light, "TOPRIGHT")
    light:Hide()
    Bar.light = light

    local tab = CreateFrame("Frame", nil, body)
    tab:SetFrameLevel(body:GetFrameLevel() + 1)
    tab:SetPoint("TOP", body, "TOP")
    tab:SetPoint("BOTTOM", body, "BOTTOM")
    tab:SetPoint("CENTER", body, "CENTER")
    Style.Shell(tab, { noBorder = true, noBevel = true, noBackground = true, shadowAlpha = 0 })
    Style.Slant(tab, "both", Bar.TAB_CUT)
    tab.fill = tab:CreateTexture(nil, "ARTWORK")
    tab.fill:SetAllPoints(tab)
    Style.Clip(tab, tab.fill, "outer")
    Bar.tab = tab

    local function zone(s)
        local z = CreateFrame("Frame", nil, body)
        z:SetFrameLevel(body:GetFrameLevel() + 3)
        s.Attach(z, { enabled = false })
        return z
    end
    Bar.leftArea, Bar.centerArea, Bar.rightArea = zone(Bar.left), zone(Bar.center), zone(Bar.right)
    Bar.leftArea:SetPoint("LEFT", body, "LEFT", Bar.INSET, 0)
    Bar.centerArea:SetPoint("CENTER", tab, "CENTER")
    Bar.rightArea:SetPoint("RIGHT", body, "RIGHT", -Bar.INSET, 0)

    Bar.Slid(0)
    DUI.Movers.Register(f, Bar.KEY, "Data Bar", Bar.HOME, { scale = false })
    -- Recompute the reserved room when moved, or when screen size or UI
    -- scale changes its width.
    DUI.On("MoverApplied", function(key)
        if key == Bar.KEY and Bar.on then DUI.Movers.SetBottomRoom(Bar.Room(mod.db)) end
    end)
    local function screen()
        if Bar.on then DUI.AfterCombat(function() ns.Refresh(mod) end, "databar.screen") end
    end
    pcall(DUI.RegisterEvent, "UI_SCALE_CHANGED", screen)
    pcall(DUI.RegisterEvent, "DISPLAY_SIZE_CHANGED", screen)
    local function update()
        if Bar.on then
            Bar.left.Update()
            Bar.center.Update()
            Bar.right.Update()
        end
    end
    pcall(DUI.RegisterEvent, "PLAYER_ENTERING_WORLD", update)
    DUI.On("TestModeChanged", update)
    DUI.On("TestPartChanged", function(key) if key == "datatexts" then update() end end)

    local list = {}
    DUI.Fade.Register{ key = "InfoPanel.databar", scope = "InfoPanel", path = "databar.fade", page = "InfoPanel.databar", whole = true,
        frames = function()
            list[1] = f:IsShown() and f or nil
            return list
        end }
end

-- Sizes the three strips from the bar width, then lays out their texts.
function Bar.Zones()
    local c = ns.module.db.databar
    local W = math.floor(UIParent:GetWidth() * c.widthPct / 100)
    local middle = DT.TEXTS[c.center] ~= nil
    local tabW = middle and Bar.TAB_W or 0
    local side = math.max(1, (W - tabW) / 2 - 2 * Bar.INSET)
    Bar.frame:SetWidth(W)
    Bar.leftArea:SetWidth(side)
    Bar.rightArea:SetWidth(side)
    Bar.centerArea:SetWidth(math.max(1, tabW - 2 * Bar.TAB_CUT))
    Bar.left.Layout()
    Bar.center.Layout()
    Bar.right.Layout()
end

-- Converts one side's settings to the panel strip's format. Empty slots are
-- skipped so the rest share the space.
local function sideSlots(c, prefix)
    local t = { enabled = true, labels = c.labels == true, icons = c.icons == true, textSize = c.textSize, count = 0 }
    for i = 1, Bar.SIDE do
        local key = c[prefix .. i]
        if DT.TEXTS[key] then
            t.count = t.count + 1
            t["slot" .. t.count] = key
        end
    end
    return t
end

local function stripsOff()
    local off = { enabled = false }
    Bar.left.Apply(off)
    Bar.center.Apply(off)
    Bar.right.Apply(off)
end

-- Fades texts in one after another, outward from the center.
local function arrive()
    local function list(s, first, step)
        for i, b in ipairs(s.slots) do
            if b:IsShown() then Motion.Fade(b, 0, 1, Motion.NORMAL, Bar.STAGGER * math.max(0, first + step * i)) end
        end
    end
    list(Bar.center, -1, 1)
    list(Bar.left, #Bar.left.slots + 1, -1)
    list(Bar.right, 0, 1)
end

-- Height the bar reserves at the bottom of the screen. Computed first so
-- pieces laid out after it (like a detached XP bar) leave room.
function Bar.Room(db)
    local c = db.databar
    if c.enabled ~= true or DUI.Movers.Valid(DUI.DB.Positions()[Bar.KEY]) then return 0 end
    return UIParent:GetWidth() * (100 - c.widthPct) / 200 < Bar.CORNER and c.height or 0
end

function Bar.Apply(db)
    local c, f, body = db.databar, Bar.frame, Bar.body
    local P = ns.Panel
    local was = Bar.on
    Bar.on = c.enabled == true
    DUI.Movers.Suspend(Bar.KEY, not Bar.on)
    -- No border by default; on a strip this thin the top accent line is enough.
    P.Look(body, Style.BackAlpha(c.alphaOwn, c.alpha), c.borderAlpha > 0)
    Style.GetShell(body).opts.borderAlpha = c.borderAlpha
    if c.angled == true then Style.Slant(body, "both", Bar.TAB_CUT) else Style.Slant(body, nil, 0) end
    Bar.tab.fill:SetColorTexture(1, 1, 1, 1)
    Style.PaintAccent(Bar.tab.fill, Bar.TAB_ALPHA)
    f:SetHeight(c.height)
    f:SetWidth(math.floor(UIParent:GetWidth() * c.widthPct / 100))
    for _, z in ipairs({ Bar.leftArea, Bar.centerArea, Bar.rightArea }) do z:SetHeight(c.height) end
    Style.LayoutShell(Style.GetShell(body))
    Style.LayoutShell(Style.GetShell(Bar.tab))
    local px = Pixel.Px(body, 1)
    Bar.line:ClearAllPoints()
    Bar.line:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    Bar.line:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    Bar.line:SetHeight(Pixel.Px(body, Bar.LINE_PX))
    Bar.line:SetShown(c.line == true)
    Style.PaintAccent(Bar.line, Bar.LINE_ALPHA)
    Bar.light.line:SetHeight(Pixel.Px(body, Bar.LIGHT_PX))
    if not Bar.on then
        if was and f:IsShown() then
            Motion.Tween(body, Bar.slid, c.height + px, Motion.NORMAL, Bar.Slid, function()
                f:Hide()
                stripsOff()
                Bar.Slid(0)
            end)
        elseif was == nil then
            f:Hide()
            stripsOff()
        end
        return
    end
    f:Show()
    -- Tab first, since the sides use whatever space it leaves.
    local middle = DT.TEXTS[c.center] ~= nil
    Bar.tab:SetWidth(middle and Bar.TAB_W or 1)
    Bar.tab:SetShown(middle)
    Bar.left.Apply(sideSlots(c, "left"))
    Bar.right.Apply(sideSlots(c, "right"))
    Bar.center.Apply({ enabled = middle, labels = false, icons = c.icons == true, textSize = c.textSize + Bar.CLOCK_UP, count = 1, slot1 = c.center })
    Bar.Zones()
    if was == false then
        if Bar.slid == 0 then Bar.Slid(c.height + px) end
        Motion.Tween(body, Bar.slid, 0, Motion.SLOW, Bar.Slid)
        arrive()
    end
end
