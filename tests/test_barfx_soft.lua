local stub = require("stub")

-- The soft bar styles (BarFxSoft.lua): Slosh (water), Molten (soft lava) and
-- Cinders (soft embers). The fill stays a plain, readable bar; the life sits in
-- soft light inside it, at its surface and at its end.

local function setup(cfg, w, h)
    local DUI = stub.Load({})
    local Style = DUI.Style
    local bar = Style.Bar(UIParent)
    bar:SetSize(w or 200, h or 20)
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

-- A layer's alpha as painted (its vertex color carries it, as in the client).
local function alphaOf(t) return select(4, t:GetVertexColor()) end

local SOFT = { "slosh", "molten", "cinders" }

local function media(name) return DaylightUI.MEDIA .. "barfx-" .. name .. ".png" end

-- The pattern layers: repeated along the fill, scrolled by the client.
local function patterns(bar)
    local out = {}
    for _, r in ipairs(lights(bar)) do
        if r:GetHorizTile() then out[#out + 1] = r end
    end
    return out
end

-- The scroll playing on a pattern layer, and its animation.
local function scrollOf(t)
    for _, g in ipairs({ t:GetAnimationGroups() }) do
        if g:IsPlaying() then return g, (g:GetAnimations()) end
    end
end

local function run(DUI, seconds)
    -- No driver yet when nothing has reacted (a hit on Molten lights nothing).
    if not DUI.Motion.Driver() then return end
    for _ = 1, math.floor(seconds / 0.05 + 0.5) do stub.RunOnUpdate(DUI.Motion.Driver(), 0.05) end
end

-- A PNG's width and height, read from its header.
local function pngSize(file)
    local path = file:gsub("^Interface\\AddOns\\DaylightUI\\", ""):gsub("\\", "/")
    local fh = assert(io.open(path, "rb"), path)
    local head = fh:read(24)
    fh:close()
    local function be(i) local a, b, c, d = head:byte(i, i + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
    return be(17), be(21)
end
-- ---- The soft styles: Slosh (water), Molten (soft lava), Cinders (soft embers) ----

local function find(bar, file)
    for _, r in ipairs(lights(bar)) do
        if r:GetTexture() == file then return r end
    end
end

T.test("Cinders is pinned to the end like Embers, with its own soft sheet", function()
    local DUI, bar, cfg, read = setup({ style = "cinders" })
    local BarFx = DUI.BarFx
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    T.eq(BarFx.StyleOf(bar), "cinders")
    local fill = bar:GetStatusBarTexture()
    local motes = find(bar, DUI.MEDIA .. "barfx-cinders.png")
    T.truthy(motes, "its own sheet of soft motes")
    T.eq(motes:GetWidth(), 20 * BarFx.SHEET_SPAN, "as wide as its art")
    T.eq(motes:GetBlendMode(), "ADD")
    local glow = find(bar, BarFx.GLOW)
    T.truthy(glow, "a glow behind the end")
    T.eq(glow:GetWidth(), 20 * BarFx.CINDERS_GLOW, "reaching five bar heights back")
    T.truthy(find(bar, BarFx.BLOOM), "a bloom on the end")
    T.truthy(find(bar, BarFx.DEPTH), "sheen and shade over the fill")
    for _, r in ipairs(lights(bar)) do
        if r:GetTexture() ~= BarFx.DEPTH then
            T.eq(r:GetNumPoints(), 2, "pinned by one side")
            local point, rel = r:GetPoint(1)
            T.eq(rel, fill, "to the fill")
            T.eq(point, "TOPRIGHT", "at its moving end")
            T.eq(r.__vertexOffsets[4][1], -8, "leaning back with the angled end")
        end
        T.truthy(r:GetBlendMode() ~= "MOD", "never MOD")
    end
    T.truthy(#lights(bar) <= 8, "at most 8 textures")
    -- Its motion is the client's: a flipbook on its own long loop.
    bar:SetSize(200, 8)
    DUI.BarFx.Apply(bar)
    T.truthy(find(bar, DUI.MEDIA .. "barfx-cinders-thin.png"), "the thin sheet on a thin bar")
    bar:SetReverseFill(true)
    DUI.Style.AngleFill(bar, "left", 4)
    local turned = find(bar, DUI.MEDIA .. "barfx-cinders-thin-l.png")
    T.truthy(turned, "turned around for a leftward bar")
    T.eq((turned:GetPoint(1)), "TOPLEFT", "pinned to the left end")
end)

T.test("Cinders brightens on a hit, swells on a heal, then lets Lua rest", function()
    local DUI, bar, cfg, read = setup({ style = "cinders", react = true })
    local BarFx = DUI.BarFx
    BarFx.Track(bar, "health", nil, "player", nil, read)
    local motes, glow, bloom = find(bar, DUI.MEDIA .. "barfx-cinders.png"), find(bar, BarFx.GLOW), find(bar, BarFx.BLOOM)
    local m0, g0, w0 = alphaOf(motes), alphaOf(glow), bloom:GetWidth()
    T.truthy(m0 > 0 and m0 < 1, "the motes rest below full, so a hit can lift them")
    BarFx.Kick(bar, -1)
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.02)
    T.truthy(alphaOf(motes) > m0, "a hit lifts the motes")
    T.truthy(alphaOf(glow) > g0, "and the glow")
    T.truthy(bloom:GetWidth() > w0, "and widens the bloom")
    BarFx.Kick(bar, -1)
    BarFx.Kick(bar, 1)
    DUI.Gradients.PaintUnit(bar, "player")
    bar:Hide(); bar:Show()
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.02)
    T.truthy(alphaOf(glow) > g0, "a heal lifts the glow")
    for _ = 1, 15 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.1) end
    T.near(alphaOf(motes), m0, 0.001, "back to rest")
    T.near(alphaOf(glow), g0, 0.001)
    T.near(bloom:GetWidth(), w0, 0.001)
    T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, "then no Lua runs")
end)

T.test("the soft styles show nothing on a fill whose colors are secret", function()
    for _, key in ipairs({ "cinders", "molten", "slosh" }) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        T.truthy(#lights(bar) > 0, key .. ": shows with plain colors")
        local s = stub.Secret(0.5)
        DUI.Style.NoteFillRGB(bar:GetStatusBarTexture(), s, s, s)
        T.eq(#lights(bar), 0, key .. ": the plain fill stays")
    end
end)

-- Seen in game: asked from Lua for a TextureCoordTranslation, this client hands
-- back a plain Animation with no SetOffset, so a scroll built that way errors.
T.test("the client makes no texture-scrolling animation from Lua", function()
    stub.Load({})
    local t = UIParent:CreateTexture()
    local a = t:CreateAnimationGroup():CreateAnimation("TextureCoordTranslation")
    T.eq(a:GetObjectType(), "Animation", "a plain animation")
    T.isnil(a.SetOffset, "with no SetOffset")
end)

T.test("Slosh, Molten and Cinders are in every bar's style list", function()
    local DUI = stub.Load({})
    local values, order = DUI.BarFx.Choices(true)
    local at = {}
    for i, k in ipairs(order) do at[k] = i end
    for _, key in ipairs(SOFT) do T.truthy(values[key] and at[key], key) end
    T.truthy(at.slosh < at.molten and at.molten < at.cinders, "in that order")
    T.eq(values.slosh, "Slosh"); T.eq(values.molten, "Molten"); T.eq(values.cinders, "Cinders")
end)

T.test("Molten's seams drift on their own, stay still on a hit and warm on a heal", function()
    local DUI, bar, _, read = setup({ style = "molten", react = true }, 240, 30)
    local BarFx = DUI.BarFx
    BarFx.Track(bar, "health", nil, "player", nil, read)
    T.eq(BarFx.StyleOf(bar), "molten")
    local seam, seamB, crust
    for _, r in ipairs(patterns(bar)) do
        if r:GetTexture() == media("seam") then seam = r
        elseif r:GetTexture() == media("seam-b") then seamB = r
        elseif r:GetTexture() == media("crust") then crust = r end
    end
    T.truthy(seam and seamB and crust, "two seam layers and the crust, repeated along the fill")
    T.eq(crust:GetBlendMode(), "BLEND"); T.eq(seam:GetBlendMode(), "ADD")
    for _, r in ipairs({ seam, seamB, crust }) do
        local g, a = scrollOf(r)
        T.truthy(g, "drifting: the client runs it")
        T.eq(a:GetObjectType(), "TextureCoordTranslation", "a scroll made from the XML template")
        T.eq((a:GetOffset()), -1, "one whole tile toward the end each loop")
        T.eq(g:GetLooping(), "REPEAT")
        T.eq(r:GetNumPoints(), 1, "laid over the whole fill")
    end
    local _, a = scrollOf(seam)
    T.near(a:GetDuration(), 256 / 3, 0.01, "3 px a second on a 30 px bar")
    local _, b = scrollOf(seamB)
    T.near(b:GetDuration(), 256 / 5.5, 0.01, "the second copy drifts faster, so the seams change shape")
    T.truthy(#lights(bar) <= 8, "at most 8 textures")
    local s0, b0 = alphaOf(seam), alphaOf(seamB)
    local ends = {}
    for _, r in ipairs(lights(bar)) do ends[r] = alphaOf(r) end
    BarFx.Kick(bar, -1)
    run(DUI, 0.05)
    for r, a in pairs(ends) do T.near(alphaOf(r), a, 0.001, "a hit lights nothing") end
    BarFx.Kick(bar, 1)
    run(DUI, 0.05)
    T.truthy(alphaOf(seam) > s0, "a heal warms the seams")
    run(DUI, 1.5)
    T.near(alphaOf(seam), s0, 0.001, "and they settle")
    T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, "then no Lua runs")
end)

T.test("Slosh rocks on a hit and on a heal, then lets Lua rest", function()
    local DUI, bar, _, read = setup({ style = "slosh", react = true }, 240, 30)
    local BarFx = DUI.BarFx
    BarFx.Track(bar, "health", nil, "player", nil, read)
    T.eq(BarFx.StyleOf(bar), "slosh")
    local surface = {}
    for _, r in ipairs(lights(bar)) do
        if r:GetTexture() == media("surface") then surface[#surface + 1] = r end
    end
    T.truthy(#surface >= 1, "the waterline")
    local caustics = patterns(bar)
    T.eq(#caustics, 2, "two layers of light drifting inside")
    local _, a1 = scrollOf(caustics[1])
    local _, a2 = scrollOf(caustics[2])
    T.truthy((a1:GetOffset()) ~= (a2:GetOffset()), "one each way")
    -- Corners: 1 top left, 2 bottom left, 3 top right, 4 bottom right. The end is right.
    local function ends(t)
        local o = t.__vertexOffsets or {}
        return (o[3] or { 0, 0 })[2], (o[1] or { 0, 0 })[2]
    end
    BarFx.Kick(bar, -1)
    run(DUI, 0.1)
    local endY, farY = ends(surface[1])
    T.truthy(endY < 0, "a hit tips the end down")
    T.truthy(farY > endY, "and the far side up")
    run(DUI, 1.5)
    BarFx.Kick(bar, 1)
    run(DUI, 0.1)
    endY = ends(surface[1])
    T.truthy(endY > 0, "a heal tips it the other way")
    run(DUI, 1.5)
    for _, t in ipairs(surface) do
        for i = 1, 4 do T.eq(((t.__vertexOffsets or {})[i] or { 0, 0 })[2], 0, "level again") end
    end
    T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, "then no Lua runs")
end)

-- "very readable": nothing reaches past the fill, nothing darkens it past
-- SHADE_MAX, and a line marks the moving end.
T.test("the soft styles never hide where a bar ends", function()
    for _, key in ipairs(SOFT) do
        for _, shape in ipairs({ "angled", "square", "empty", "leftward" }) do
            local DUI, bar, _, read = setup({ style = key, react = true }, 240, 30)
            local fill = bar:GetStatusBarTexture()
            if shape == "square" then DUI.Style.AngleFill(bar, nil) end
            if shape == "empty" then bar:SetValue(0) end
            if shape == "leftward" then bar:SetReverseFill(true); DUI.Style.AngleFill(bar, "left", 8) end
            DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
            DUI.BarFx.Kick(bar, -1)
            run(DUI, 0.05)
            local endLine
            for _, r in ipairs(lights(bar)) do
                local name = key .. " " .. shape .. " " .. tostring(r:GetTexture())
                local _, rel = r:GetPoint(1)
                T.eq(rel, fill, name .. ": anchored to the fill, so it can't reach past it")
                local r1, g1, b1, a = r:GetVertexColor()
                if r:GetBlendMode() == "BLEND" and r1 + g1 + b1 == 0 then
                    T.truthy(a <= DUI.BarFx.SHADE_MAX, name .. ": never darker than SHADE_MAX")
                end
                if r:GetTexture() == DUI.BarFx.WHITE and r:GetNumPoints() == 2 then endLine = r end
                T.truthy(r:GetNumMaskTextures() <= 3, name .. ": never a fourth mask")
            end
            T.truthy(endLine, key .. " " .. shape .. ": a line on the end")
            local point = endLine and endLine:GetPoint(1)
            T.eq(point, shape == "leftward" and "TOPLEFT" or "TOPRIGHT", key .. " " .. shape .. ": on the moving end")
        end
    end
end)

-- "striking, high resolution": art drawn at a bar's size or better, and the
-- patterns repeated, never stretched with the value.
T.test("the soft styles' art is drawn at a bar's real size or better", function()
    for _, key in ipairs(SOFT) do
        for _, h in ipairs({ 30, 10 }) do
            local DUI, bar, _, read = setup({ style = key }, 240, h)
            DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
            for _, r in ipairs(lights(bar)) do
                local file = r:GetTexture()
                if type(file) == "string" and file:find("barfx%-")
                    and not (file:find("glow") or file:find("band") or file:find("depth") or file:find("flare")) then
                    local _, fh = pngSize(file)
                    local B = DUI.BarFx
                    local rows = file:find("surface") and fh / (B.SURFACE_FRAMES / B.SHEET_COLS)
                        or (file:find("cinders") and fh / (B.CINDERS_FRAMES / B.CINDERS_COLS) or fh)
                    local covers = file:find("surface") and 40 / 64 * h or h   -- the surface covers the bar's top 5/8
                    T.truthy(rows >= covers, key .. " " .. h .. ": " .. file .. " has " .. rows .. " rows for " .. covers .. " px of bar")
                end
            end
            for _, r in ipairs(patterns(bar)) do
                if h < DUI.BarFx.THIN then T.truthy(r:GetTexture():find("%-thin"), key .. ": the thin tile on a thin bar") end
            end
            if key ~= "cinders" then T.truthy(#patterns(bar) >= 2, key .. ": its patterns repeat along the bar") end
        end
    end
end)

T.test("after a loading screen the soft styles start over", function()
    for _, key in ipairs(SOFT) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local groups = {}
        for _, r in ipairs(lights(bar)) do
            for _, g in ipairs({ r:GetAnimationGroups() }) do if g:IsPlaying() then groups[#groups + 1] = g end end
        end
        for _, g in ipairs({ bar:GetAnimationGroups() }) do if g:IsPlaying() then groups[#groups + 1] = g end end
        T.truthy(#groups > 0, key .. ": something plays")
        local stops = 0
        for _, g in ipairs(groups) do
            local stop = g.Stop
            g.Stop = function(self) stops = stops + 1; return stop(self) end
        end
        stub.FireEvent("LOADING_SCREEN_DISABLED")
        T.truthy(stops >= #groups, key .. ": every one stopped and")
        for _, g in ipairs(groups) do T.truthy(g:IsPlaying(), key .. ": played again") end
    end
end)

-- Forty raid tiles in a soft style, all hit (Molten: healed, since a hit
-- lights nothing there) in the same moment.
T.test("a raid of soft bars all hit at once runs one driver, then rests", function()
    for _, key in ipairs(SOFT) do
        local DUI = stub.Load({})
        local read = DUI.BarFx.Reader(function() return { style = key, react = true } end)
        local bars = {}
        for i = 1, 40 do
            local bar = DUI.Style.Bar(UIParent)
            bar:SetSize(80, 30)
            DUI.Style.AngleFill(bar, "right", 8)
            DUI.Gradients.PaintUnit(bar, "player")
            DUI.BarFx.Track(bar, "health", "raid", "raid" .. i, nil, read)
            bars[i] = bar
        end
        for i = 1, 40 do DUI.BarFx.Kick(bars[i], key == "molten" and 1 or -1) end
        T.truthy(DUI.Motion.Driver().__scripts.OnUpdate, key .. ": reacting")
        run(DUI, 1.5)
        T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, key .. ": the driver is gone after")
    end
end)

T.test("hit, heal and hit with a repaint and a hide in between leave nothing lit or tipped", function()
    for _, key in ipairs(SOFT) do
        local DUI, bar, _, read = setup({ style = key, react = true }, 240, 30)
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local rest = {}
        for _, r in ipairs(lights(bar)) do rest[r] = { alphaOf(r), r:GetWidth() } end
        DUI.BarFx.Kick(bar, -1)
        run(DUI, 0.05)
        DUI.BarFx.Kick(bar, 1)
        DUI.Gradients.PaintUnit(bar, "player")
        bar:Hide(); bar:Show()
        DUI.BarFx.Kick(bar, -1)
        run(DUI, 2)
        for r, v in pairs(rest) do
            local name = key .. ": " .. tostring(r:GetTexture())
            T.near(alphaOf(r), v[1], 0.001, name .. " back to rest")
            T.near(r:GetWidth(), v[2], 0.001, name .. " its size too")
            for i = 1, 4 do T.eq(((r.__vertexOffsets or {})[i] or { 0, 0 })[2], 0, name .. " level") end
        end
        T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, key .. ": no Lua runs")
    end
end)

T.test("a bar cut at both ends takes no fourth mask", function()
    for _, key in ipairs(SOFT) do
        local DUI, bar, _, read = setup({ style = key }, 240, 30)
        local fill = bar:GetStatusBarTexture()
        for _ = 1, 3 - fill:GetNumMaskTextures() do fill:AddMaskTexture(bar:CreateMaskTexture()) end
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        T.eq(DUI.BarFx.StyleOf(bar), key)
        for _, r in ipairs(lights(bar)) do T.truthy(r:GetNumMaskTextures() <= 3, key) end
    end
end)

-- Seen in game: 128 frames over 18 s stepped about 7 times a second and the
-- motes looked choppy. A flipbook needs about 30 a second to glide.
T.test("the soft styles' flipbooks step at least 30 times a second", function()
    for _, key in ipairs(SOFT) do
        local DUI, bar, _, read = setup({ style = key }, 240, 30)
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        for _, g in ipairs({ bar:GetAnimationGroups() }) do
            for _, a in ipairs({ g:GetAnimations() }) do
                if a:GetObjectType() == "FlipBook" then
                    local fps = a:GetFlipBookFrames() / a:GetDuration()
                    T.truthy(fps >= 30, key .. ": " .. string.format("%.1f", fps) .. " frames a second")
                end
            end
        end
    end
end)

-- Seen in game: Molten's end washed out to white. Its bloom was Comet's flash,
-- bright over most of its width and all of the bar's height; the mock-up's is
-- a small round light fading straight from its middle.
T.test("the soft styles' end wears the mock-up's round bloom, not Comet's flash", function()
    for _, key in ipairs({ "molten", "cinders" }) do
        local DUI, bar, _, read = setup({ style = key }, 240, 30)
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local bloom
        for _, r in ipairs(lights(bar)) do
            T.truthy(r:GetTexture() ~= DUI.BarFx.FLARE, key .. ": not Comet's flash")
            if r:GetTexture() == DUI.BarFx.BLOOM then bloom = r end
        end
        T.truthy(bloom, key .. ": its own bloom")
        T.near(bloom:GetWidth(), 30 * DUI.BarFx.BLOOM_SPAN, 0.01, key .. ": 1.5 bar heights back from the end's middle")
    end
end)

-- Seen in game: at the mock-up's strengths Molten's end washed out nearly
-- white on a player bar. Molten's and Cinders' end light rests at half of them.
T.test("Molten's and Cinders' ends glow softly, never washing the end out", function()
    for key, want in pairs({ molten = 0.20, cinders = 0.21 }) do
        local DUI, bar, _, read = setup({ style = key }, 240, 30)
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local glow, bloom
        for _, r in ipairs(lights(bar)) do
            if r:GetTexture() == DUI.BarFx.GLOW then glow = r elseif r:GetTexture() == DUI.BarFx.BLOOM then bloom = r end
        end
        T.near(alphaOf(glow), want, 0.001, key .. ": the glow")
        T.near(alphaOf(bloom), 0.30, 0.001, key .. ": the round light on the end")
    end
end)

-- Seen in game: a thin line of the fill showed along the top of Slosh's dark
-- surface. The cut that keeps a light inside its bar was the game's 8 x 8
-- white square stretched over the bar, and the client blurs a stretched
-- mask's edge by half a texel: about 1.4 px on a 22 px bar, 15 px at its ends.
T.test("the cut inside a bar is sharp to the pixel at its edges", function()
    local DUI, bar, _, read = setup({ style = "slosh" }, 360, 30)
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    local fill, seen = bar:GetStatusBarTexture(), 0
    for _, r in ipairs(lights(bar)) do
        for i = 1, r:GetNumMaskTextures() do
            local m = r:GetMaskTexture(i)
            local _, rel = m:GetPoint(1)
            if rel == bar then
                seen = seen + 1
                local file = m:GetTexture()
                T.eq(file, DUI.Style.MASK_SOLID, "a large white image, not the 8 x 8 square")
                local w, h = pngSize(file)
                T.truthy(360 / w / 2 < 1 and 30 / h / 2 < 1, "half a texel stays under a pixel")
            end
        end
    end
    T.truthy(seen > 0, "the surface wears the cut")
end)
