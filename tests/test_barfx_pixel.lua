local stub = require("stub")

-- The pixel-art bar styles (BarFxStyles.lua): Pixel Sparks, Pixel Blaze and
-- Pixel Arc. Chunky art pinned to the fill's moving end like Comet's, drawn on
-- whole screen pixels at any bar height and never leaned with an angled end.

local PIXEL = { "pixelsparks", "pixelblaze", "pixelarc" }

-- A bar angled on the right and the settings table it follows.
local function setup(cfg)
    local DUI = stub.Load({})
    local Style = DUI.Style
    local bar = Style.Bar(UIParent)
    bar:SetSize(200, 20)
    Style.AngleFill(bar, "right", 8)
    DUI.Gradients.PaintUnit(bar, "player")
    cfg = cfg or {}
    return DUI, bar, cfg, DUI.BarFx.Reader(function() return cfg end)
end

-- The textures a style lays on a bar, over its fill.
local function lights(bar)
    local fill, out = bar:GetStatusBarTexture(), {}
    local _, fillSub = fill:GetDrawLayer()
    for _, r in ipairs({ bar:GetRegions() }) do
        local layer, sub = r:GetDrawLayer()
        if r ~= fill and r:GetObjectType() == "Texture" and layer == "ARTWORK" and sub > fillSub and sub < 1 and r:IsShown() then
            out[#out + 1] = r
        end
    end
    return out
end

local function sheetOf(bar)
    for _, r in ipairs(lights(bar)) do
        local file = r:GetTexture()
        if type(file) == "string" and (file:find("barfx%-pixel") or file:find("barfx%-comet")) then return r, file end
    end
end

-- Every animation group a bar makes from here on.
local function watchGroups(bar)
    local groups = {}
    local make = bar.CreateAnimationGroup
    bar.CreateAnimationGroup = function(self)
        local g = make(self)
        groups[#groups + 1] = g
        return g
    end
    return groups
end

local function flipbookOf(groups)
    for _, g in ipairs(groups) do
        for _, a in ipairs({ g:GetAnimations() }) do
            if a:GetObjectType() == "FlipBook" then return a, g end
        end
    end
end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.001 end

T.test("the pixel styles can be picked like any other", function()
    local DUI = stub.Load({ module = true })
    local BarFx = DUI.BarFx
    local values, order = BarFx.Choices()
    local at = {}
    for i, k in ipairs(order) do at[k] = i end
    local labels = { pixelsparks = "Pixel Sparks", pixelblaze = "Pixel Blaze", pixelarc = "Pixel Arc" }
    local last = at.embers
    T.truthy(last, "Embers is listed")
    for _, key in ipairs(PIXEL) do
        T.truthy(at[key] and at[key] > last, key .. ": listed after Embers, in order")
        last = at[key] or last
        T.eq(values[key], labels[key], key .. ": its English label")
        local _, bar, _, read = setup({ style = key })
        DaylightUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        T.eq(DaylightUI.BarFx.StyleOf(bar), key, key .. ": a bar wears it")
    end
    local D = stub.Load({ module = true })
    for power, style in pairs(D.BarFx.AUTO) do
        T.truthy(not tostring(style):find("^pixel"), power .. ": by power type picks no pixel style")
    end
    T.eq(D:Get("UnitFrames", "player.barFx.health.style"), "flow", "a new setup still starts in Flow")
end)

T.test("pixel art keeps whole pixels at any bar height", function()
    for _, scale in ipairs({ 1, 0.53 }) do
        for _, key in ipairs(PIXEL) do
            local DUI, bar, cfg, read = setup({ style = key })
            UIParent:SetScale(scale)
            DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
            local fill = bar:GetStatusBarTexture()
            for _, h in ipairs({ 8, 12, 20, 33, 40 }) do
                bar:SetSize(200, h)
                DUI.BarFx.Apply(bar)
                local where = key .. " at " .. h .. " high, scale " .. scale
                local px = DUI.Pixel.Px(bar, 1)
                local thin = h < DUI.BarFx.THIN
                local R = thin and 8 or 16
                local m = math.max(1, math.floor(h / px / R + 0.5))
                local sheet, file = sheetOf(bar)
                T.truthy(sheet, where .. ": its sheet shows")
                T.eq(file, DUI.MEDIA .. "barfx-" .. key .. (thin and "-thin" or "") .. ".png", where .. ": the art drawn for its height")
                T.truthy(near(sheet:GetWidth(), 128 * m * px), where .. ": 128 art pixels of " .. m .. " screen pixels wide ("
                    .. tostring(sheet:GetWidth()) .. " vs " .. 128 * m * px .. ")")
                T.truthy(near(sheet:GetHeight(), R * m * px), where .. ": " .. R .. " art pixels tall ("
                    .. tostring(sheet:GetHeight()) .. " vs " .. R * m * px .. ")")
                T.eq(sheet:GetNumPoints(), 1, where .. ": one point, never stretched between two")
                local point, rel, relPoint = sheet:GetPoint(1)
                T.eq(point, "RIGHT", where)
                T.eq(rel, fill, where .. ": on the fill")
                T.eq(relPoint, "RIGHT", where .. ": at its moving end")
                T.eq(sheet.__filter, "NEAREST", where .. ": crisp, not blurred")
                T.eq(sheet.__wrap, "CLAMP", where .. ": edges not blended with the far side")
            end
            UIParent:SetScale(1)
        end
    end
end)

T.test("a pixel sheet sits on an angled end without leaning", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local sheet = sheetOf(bar)
        local _, _, _, x, y = sheet:GetPoint(1)
        T.truthy(near(x, -DUI.Pixel.Snap(bar, 4)), key .. ": pulled back by half the cut (" .. tostring(x) .. ")")
        T.eq(y, 0, key .. ": centered")
        for i = 1, 4 do
            local o = (sheet.__vertexOffsets or {})[i] or { 0, 0 }
            T.eq(o[1], 0, key .. ": corner " .. i .. " not leaned")
            T.eq(o[2], 0, key .. ": corner " .. i .. " not moved up or down")
        end
        local flash
        for _, r in ipairs(lights(bar)) do
            if r:GetTexture() == DUI.BarFx.FLARE then flash = r end
        end
        T.truthy(flash, key .. ": a flash at the end")
        T.eq(flash.__vertexOffsets[4][1], -8, key .. ": the flash still leans like Comet's")

        local square = DUI.Style.Bar(UIParent)
        square:SetSize(200, 20)
        DUI.Gradients.PaintUnit(square, "player")
        DUI.BarFx.Track(square, "health", nil, "player", nil, read)
        local _, _, _, sx = sheetOf(square):GetPoint(1)
        T.eq(sx, 0, key .. ": a square end, right on it")
    end
end)

T.test("pixel styles turn around on a leftward bar", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local fill = bar:GetStatusBarTexture()
        bar:SetReverseFill(true)
        DUI.Style.AngleFill(bar, "left", 4)
        local sheet, file = sheetOf(bar)
        T.eq(file, DUI.MEDIA .. "barfx-" .. key .. "-l.png", key .. ": turned around")
        T.eq(sheet:GetNumPoints(), 1, key)
        local point, rel, relPoint, x = sheet:GetPoint(1)
        T.eq(point, "LEFT", key .. ": pinned to the left end")
        T.eq(rel, fill, key)
        T.eq(relPoint, "LEFT", key)
        T.truthy(near(x, DUI.Pixel.Snap(bar, 2)), key .. ": pulled in by half the cut (" .. tostring(x) .. ")")
        bar:SetSize(200, 8)
        DUI.BarFx.Apply(bar)
        local _, thin = sheetOf(bar)
        T.eq(thin, DUI.MEDIA .. "barfx-" .. key .. "-thin-l.png", key .. ": the thin art, turned around")
    end
end)

T.test("a pixel sheet plays its 32 frames in 3.2 seconds", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, cfg, read = setup({ style = key })
        local groups = watchGroups(bar)
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local a, g = flipbookOf(groups)
        T.truthy(a, key .. ": a flipbook the client steps")
        T.eq(a:GetFlipBookFrames(), 32, key)
        T.eq(a:GetFlipBookColumns(), 4, key)
        T.eq(a:GetFlipBookRows(), 8, key)
        T.eq(a:GetDuration(), 3.2, key .. ": ten frames a second")
        T.eq(g:GetLooping(), "REPEAT", key .. ": looped")
        T.truthy(g:IsPlaying(), key .. ": playing")
        cfg.speed = 2
        DUI.BarFx.Apply(bar)
        T.eq(g:GetAnimationSpeedMultiplier(), 2, key .. ": follows the speed setting")
    end
    local DUI, bar, _, read = setup({ style = "comet" })
    local groups = watchGroups(bar)
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    local a = flipbookOf(groups)
    T.eq(a:GetFlipBookFrames(), 128, "Comet's sheet is unchanged")
    T.eq(a:GetFlipBookColumns(), 4, "Comet")
    T.eq(a:GetFlipBookRows(), 32, "Comet")
end)

T.test("a pixel sheet is cut to the bar", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local shown = lights(bar)
        T.truthy(#shown > 0, key .. ": shows something")
        for _, r in ipairs(shown) do
            T.eq(r:GetNumMaskTextures(), 2, key .. ": the angled end and the bar's rectangle")
            -- An empty bar's fill has no width, so the cut is the bar's rectangle.
            local _, rel = r:GetMaskTexture(2):GetPoint(1)
            T.eq(rel, bar, key .. ": cut to the bar, never to the empty fill")
        end
        local square = DUI.Style.Bar(UIParent)
        square:SetSize(200, 20)
        DUI.Gradients.PaintUnit(square, "player")
        DUI.BarFx.Track(square, "health", nil, "player", nil, read)
        for _, r in ipairs(lights(square)) do
            T.eq(r:GetNumMaskTextures(), 1, key .. ": a square fill, the rectangle alone")
        end
    end
end)

T.test("a pixel style flares on a hit and lets Lua rest after", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, _, read = setup({ style = key, react = true })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local flare
        for _, r in ipairs(lights(bar)) do
            if r:GetTexture() == DUI.BarFx.FLARE then flare = r end
        end
        T.truthy(flare, key .. ": a flash at the end")
        T.eq(flare:GetAlpha(), 0, key .. ": dark until something happens")
        DUI.BarFx.Kick(bar, -1)
        stub.RunOnUpdate(DUI.Motion.Driver(), 0.05)
        T.truthy(flare:GetAlpha() > 0, key .. ": it lights on a hit")
        DUI.Gradients.PaintUnit(bar, "player")
        T.truthy(flare:GetAlpha() > 0 and flare:GetAlpha() < 1, key .. ": a repaint mid-fade leaves it fading")
        for _ = 1, 10 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.1) end
        T.eq(flare:GetAlpha(), 0, key .. ": and fades out")
        T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, key .. ": then no Lua runs")
        T.eq(DUI.BarFx.StyleOf(bar), key)
    end
end)

T.test("after a loading screen a pixel style starts its animation over", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, _, read = setup({ style = key })
        local groups = watchGroups(bar)
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local playing, stops = {}, 0
        for _, g in ipairs(groups) do
            if g:IsPlaying() then
                playing[#playing + 1] = g
                local stop = g.Stop
                g.Stop = function(self) stops = stops + 1; return stop(self) end
            end
        end
        T.truthy(#playing > 0, key .. ": its animation plays")
        stub.FireEvent("LOADING_SCREEN_DISABLED")
        T.truthy(stops > 0, key .. ": stopped and")
        for _, g in ipairs(playing) do T.truthy(g:IsPlaying(), key .. ": played again") end
        stops = 0
        DUI.Gradients.PaintPair(bar:GetStatusBarTexture(), { 1, 0, 0 }, { 0, 0, 1 })
        T.eq(stops, 0, key .. ": a repaint doesn't restart it")
        -- Hidden and shown again (a party member leaving and joining): it plays.
        bar:Hide()
        bar:Show()
        for _, g in ipairs(playing) do T.truthy(g:IsPlaying(), key .. ": playing after a hide and show") end
    end
end)

T.test("no pixel style multiplies a layer over the bar", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        T.truthy(#lights(bar) > 0, key .. ": shows something")
        for _, r in ipairs(lights(bar)) do
            T.truthy(r:GetBlendMode() ~= "MOD", key .. ": " .. tostring(r:GetTexture()) .. " isn't MOD")
        end
    end
end)

T.test("a pixel sheet is tinted from the bar's second color mixed toward white", function()
    for _, key in ipairs(PIXEL) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.Style.NoteFill(bar:GetStatusBarTexture(), { 0.02, 0.22, 0.5 }, { 0.6, 0.92, 1 })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local _, hi = DUI.BarFx.Colors({ bar = bar, cfg = read })
        local sheet = sheetOf(bar)
        for i = 1, 3 do
            T.truthy(near(sheet.__vertex[i], hi[i] + (1 - hi[i]) * 0.6), key .. ": 0.6 toward white, channel " .. i)
        end
    end
end)
