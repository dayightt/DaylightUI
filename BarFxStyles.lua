-- Comet and Embers. Their art is pinned to the fill's moving end at a fixed
-- size, so it never stretches with the bar's value, and leans with the end's
-- angle. Every texture wears the fill's own masks and is cut to the fill's
-- rectangle, so nothing shows outside it. What moves is a flipbook sheet the
-- game steps through (tools/make_barfx.py), so no Lua runs while a bar sits
-- there; a hit or a heal is one short fade of a flash. Nothing reads the
-- bar's value.

local _, DUI = ...
local Style, BarFx, L = DUI.Style, DUI.BarFx, DUI.L
local M = DUI.MEDIA

BarFx.SHEET_FRAMES = 128  -- frames in each sheet,
BarFx.SHEET_COLS = 4      -- this many a row
BarFx.SHEET_LOOP = 3.2    -- seconds to play one through
BarFx.THIN = 13           -- a bar lower than this wears the sheet drawn for thin bars
BarFx.SHEET_SPAN = 8      -- a sheet's width in bar heights,
BarFx.THIN_SPAN = 16      -- and the thin one's
BarFx.FLARE_SPAN = 4
BarFx.FLARE = M .. "barfx-flare.png"
-- The pixel styles' sheets: 32 frames of 128 x 16 art pixels (8 rows for thin
-- bars), four a row, played through in 3.2 seconds.
BarFx.PIXEL = { frames = 32, cols = 4, loop = 3.2, wide = 128, tall = 16, thin = 8 }
local WHITE = BarFx.WHITE

-- A sheet's file: drawn for tall or thin bars, and turned around for a bar
-- that fills toward the left (a flipbook can't be mirrored by its coordinates).
local function sheetFile(name, thin, left)
    return M .. "barfx-" .. name .. (thin and "-thin" or "") .. (left and "-l" or "") .. ".png"
end

local function layer(p, s)
    local t = s.bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FX_SUB)
    t:SetBlendMode("ADD")
    -- Registered with the fill, so it gets the fill's angled end whenever that
    -- is set; pinned to the end in layout.
    Style.FollowFill(s.bar, t)
    p.layers[#p.layers + 1] = t
    return t
end

-- Pins a texture to the fill's moving end, width wide, inset in from it.
local function pin(t, fill, side, width, inset)
    local x = (side == "LEFT" and 1 or -1) * (inset or 0)
    t:ClearAllPoints()
    t:SetPoint("TOP" .. side, fill, "TOP" .. side, x, 0)
    t:SetPoint("BOTTOM" .. side, fill, "BOTTOM" .. side, x, 0)
    t:SetWidth(width)
end

-- Leans a texture like the fill's angled end: the corners on the side that
-- trails move back by the end's cut.
local TOP, BOTTOM = { 1, 3 }, { 2, 4 }
local function lean(t, side, cut, under)
    local dx = (side == "LEFT" and 1 or -1) * cut
    local moved, still = under and TOP or BOTTOM, under and BOTTOM or TOP
    for i = 1, 2 do
        t:SetVertexOffset(moved[i], dx, 0)
        t:SetVertexOffset(still[i], 0, 0)
    end
end

-- Pixel art keeps whole screen pixels: one art pixel is drawn as the whole
-- number of them that best fills the bar's height, so it stays crisp. It is
-- never leaned (that would shear its pixels): it sits back by half the angled
-- end's cut, its head on the middle of the slanted edge, and the mask trims
-- what pokes past.
local function pixelPin(t, bar, fill, side, h, cut, thin, sheet)
    local px = DUI.Pixel.Px(bar, 1)
    local rows = thin and sheet.thin or sheet.tall
    local m = math.max(1, math.floor(h / px / rows + 0.5))
    t:ClearAllPoints()
    t:SetPoint(side, fill, side, (side == "LEFT" and 1 or -1) * DUI.Pixel.Snap(bar, cut / 2), 0)
    t:SetSize(sheet.wide * m * px, rows * m * px)
    for i = 1, 4 do t:SetVertexOffset(i, 0, 0) end
end

local function layout(s, p, w, h)
    local bar = s.bar
    local fill = bar:GetStatusBarTexture()
    local left = bar.GetReverseFill ~= nil and bar:GetReverseFill() == true
    local side = left and "LEFT" or "RIGHT"
    local _, cut, under = Style.GetFillAngle(bar)
    cut = cut or 0
    local thin = h < BarFx.THIN
    local art = (thin and "thin" or "tall") .. side
    if p.art ~= art then
        p.art = art
        -- CLAMP, or the game blends each edge with the far one.
        if p.pixel then
            p.sheet:SetTexture(sheetFile(p.name, thin, left), "CLAMP", "CLAMP", "NEAREST")
        else
            p.sheet:SetTexture(sheetFile(p.name, thin, left), "CLAMP", "CLAMP")
        end
        p.flare:SetTexCoord(left and 1 or 0, left and 0 or 1, 0, 1)
    end
    local px = DUI.Pixel.Px(bar, 1)
    if p.pixel then
        pixelPin(p.sheet, bar, fill, side, h, cut, thin, p.pixel)
    else
        pin(p.sheet, fill, side, h * (thin and BarFx.THIN_SPAN or BarFx.SHEET_SPAN))
    end
    pin(p.flare, fill, side, h * BarFx.FLARE_SPAN)
    pin(p.line, fill, side, thin and px or 2 * px, px)
    for _, t in ipairs(p.layers) do
        if not (p.pixel and t == p.sheet) then lean(t, side, cut, under == true) end
    end
end

local function show(s, p, on)
    local was = p.on
    p.on = on
    for _, t in ipairs(p.layers) do t:SetShown(on) end
    if on then
        -- Coming on, it starts over; already on (a repaint), it keeps going.
        if not was then p.anim:Stop() end
        p.anim:Play()
        if p.anim.SetAnimationSpeedMultiplier then
            p.anim:SetAnimationSpeedMultiplier(math.max(0.05, s.speed or 1))
        end
    else
        p.anim:Stop()
    end
end

-- A hit or a heal: the flash at the end lights and fades. Lua runs only for
-- that fade.
local function kick(s, p, dir, size)
    local Motion = DUI.Motion
    local t = p.flare
    Motion.Tween(p, math.min(1, 0.85 * size), 0, Motion.SLOW, function(a) t:SetAlpha(a) end)
end

-- sheet: a pixel style's sheet numbers (BarFx.PIXEL), nil for Comet's and Embers'.
local function build(s, name, sheet)
    local p = { layers = {}, name = name, pixel = sheet }
    p.sheet = layer(p, s)
    p.flare = layer(p, s)
    p.flare:SetTexture(BarFx.FLARE, "CLAMP", "CLAMP")
    p.flare:SetAlpha(0)
    p.line = layer(p, s)
    p.line:SetTexture(WHITE)
    p.anim = s.bar:CreateAnimationGroup()
    p.anim:SetLooping("REPEAT")
    local a = p.anim:CreateAnimation("FlipBook")
    a:SetTarget(p.sheet)
    local frames = sheet and sheet.frames or BarFx.SHEET_FRAMES
    local cols = sheet and sheet.cols or BarFx.SHEET_COLS
    a:SetDuration(sheet and sheet.loop or BarFx.SHEET_LOOP)
    a:SetFlipBookRows(frames / cols)
    a:SetFlipBookColumns(cols)
    a:SetFlipBookFrames(frames)
    a:SetFlipBookFrameWidth(0)
    a:SetFlipBookFrameHeight(0)
    -- The game stops a frame's animations while it's hidden: start again on show.
    s.bar:HookScript("OnShow", function()
        if p.on and s.style == name then
            p.anim:Stop()
            show(s, p, true)
        end
    end)
    return p
end

local function mix(a, b, k)
    return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

-- The color to light with; a fill whose colors can't be known (secret)
-- lights in the accent.
local function lightOf(hi)
    if hi then return hi end
    local _, b = Style.AccentPair()
    if b then return b end
    return { Style.Accent() }
end

-- Shared with the soft styles (BarFxSoft.lua).
BarFx.SheetFile, BarFx.Pin, BarFx.Lean, BarFx.Mix, BarFx.LightOf = sheetFile, pin, lean, mix, lightOf

-- tints(hi) returns the sheet's, the line's and the flash's color.
local function def(name, tints, sheet)
    return {
        layout = layout, show = show, kick = kick,
        build = function(s) return build(s, name, sheet) end,
        paint = function(s, p, lo, hi, alpha)
            local fill = s.bar:GetStatusBarTexture()
            for _, t in ipairs(p.layers) do Style.SameMasks(t, fill, true) end
            local sheet, line, flash = tints(lightOf(hi))
            p.sheet:SetVertexColor(sheet[1], sheet[2], sheet[3], alpha)
            p.line:SetVertexColor(line[1], line[2], line[3], alpha)
            -- The flash keeps the alpha its fade left it at.
            p.flare:SetVertexColor(flash[1], flash[2], flash[3], p.flare:GetAlpha())
        end,
    }
end

-- A white-hot head riding the fill's end, with streaks racing back behind it.
local WHITE_HOT = { 1, 1, 1 }
BarFx.Add("comet", function() return L["Comet"] end, def("comet", function(hi)
    return mix(hi, WHITE_HOT, 0.6), WHITE_HOT, mix(hi, WHITE_HOT, 0.8)
end))

-- A glowing, flickering end with sparks lifting off it and cooling as they
-- rise. The sheet carries the cooling in its own colors.
BarFx.EMBER = { 1, 0.62, 0.28 }
BarFx.EMBER_HOT = { 1, 0.92, 0.66 }
BarFx.Add("embers", function() return L["Embers"] end, def("embers", function(hi)
    local warm = mix(hi, BarFx.EMBER, 0.5)
    return mix(warm, BarFx.EMBER_HOT, 0.6), BarFx.EMBER_HOT, mix(warm, BarFx.EMBER_HOT, 0.4)
end))

-- Chunky pixel art at the fill's end (sparks, a stepped flame, a crackling
-- bolt), kept on whole screen pixels so it stays crisp at any bar height.
local function pixelTints(hi)
    return mix(hi, WHITE_HOT, 0.6), WHITE_HOT, mix(hi, WHITE_HOT, 0.8)
end
BarFx.Add("pixelsparks", function() return L["Pixel Sparks"] end, def("pixelsparks", pixelTints, BarFx.PIXEL))
BarFx.Add("pixelblaze", function() return L["Pixel Blaze"] end, def("pixelblaze", pixelTints, BarFx.PIXEL))
BarFx.Add("pixelarc", function() return L["Pixel Arc"] end, def("pixelarc", pixelTints, BarFx.PIXEL))

-- Tide: a soft band of light swelling up and sinking back through the fill,
-- the same all along it, so it never stretches with the value. A heal sends a
-- bright surge over the fill, a hit makes it ebb dark for a moment.
BarFx.TIDE = M .. "barfx-tide.png"
BarFx.TIDE_FRAMES = 128
BarFx.TIDE_LOOP = 5.5
BarFx.TIDE_GLOW = 0.6     -- the band's strength at full
BarFx.TIDE_EBB = 0.45     -- how dark a hit makes the fill at full

local function tideShow(s, p, on)
    local was = p.on
    p.on = on
    p.swell:SetShown(on)
    p.surge:SetShown(on)
    p.ebb:SetShown(on)
    if on then
        -- Coming on, it starts over; already on (a repaint), it keeps going.
        if not was then p.anim:Stop() end
        p.anim:Play()
        if p.anim.SetAnimationSpeedMultiplier then
            p.anim:SetAnimationSpeedMultiplier(math.max(0.05, s.speed or 1))
        end
    else
        p.anim:Stop()
    end
end

local function over(s, blend)
    local t = s.bar:CreateTexture(nil, "ARTWORK", nil, BarFx.FX_SUB)
    t:SetTexture(WHITE)
    t:SetBlendMode(blend)
    Style.FollowFill(s.bar, t)
    return t
end

BarFx.Add("tide", function() return L["Tide"] end, {
    build = function(s)
        local p = {}
        p.swell = over(s, "ADD")
        -- CLAMP, or the game blends the top edge with the bottom one.
        p.swell:SetTexture(BarFx.TIDE, "CLAMP", "CLAMP")
        p.surge = over(s, "ADD")
        p.surge:SetAlpha(0)
        p.ebb = over(s, "BLEND")
        p.ebb:SetAlpha(0)
        p.anim = s.bar:CreateAnimationGroup()
        p.anim:SetLooping("REPEAT")
        local a = p.anim:CreateAnimation("FlipBook")
        a:SetTarget(p.swell)
        a:SetDuration(BarFx.TIDE_LOOP)
        a:SetFlipBookRows(BarFx.TIDE_FRAMES)
        a:SetFlipBookColumns(1)
        a:SetFlipBookFrames(BarFx.TIDE_FRAMES)
        a:SetFlipBookFrameWidth(0)
        a:SetFlipBookFrameHeight(0)
        -- The game stops a frame's animations while it's hidden: start again on show.
        s.bar:HookScript("OnShow", function()
            if p.on and s.style == "tide" then
                p.anim:Stop()
                tideShow(s, p, true)
            end
        end)
        return p
    end,
    -- Laid over the fill, so a size change needs nothing.
    layout = function() end,
    show = tideShow,
    paint = function(s, p, lo, hi, alpha)
        local fill = s.bar:GetStatusBarTexture()
        -- Laid exactly over the fill, so its own masks are all it needs.
        for _, t in ipairs({ p.swell, p.surge, p.ebb }) do Style.SameMasks(t, fill) end
        local c = mix(lightOf(hi), WHITE_HOT, 0.35)
        p.swell:SetVertexColor(c[1], c[2], c[3], alpha * BarFx.TIDE_GLOW)
        p.surge:SetVertexColor(c[1], c[2], c[3])
        p.ebb:SetVertexColor(0, 0, 0)
    end,
    kick = function(s, p, dir, size)
        local Motion = DUI.Motion
        local t = dir > 0 and p.surge or p.ebb
        local peak = dir > 0 and 0.7 * size or BarFx.TIDE_EBB * size
        Motion.Tween(t, math.min(1, peak), 0, Motion.SLOW, function(a) t:SetAlpha(a) end)
    end,
})

-- By power type: the style that suits each power.
BarFx.AUTO.RAGE = "embers"

-- Styles there once, now gone: a frame still set to one shows Flow.
for _, key in ipairs({ "silk", "prism", "aurora", "stars", "liquid", "heart", "storm" }) do BarFx.RETIRED[key] = "flow" end
