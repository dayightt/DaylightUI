local stub = require("stub")

-- Bar styles (BarFx.lua): a living fill that follows each bar's own settings
-- (handed in by the module that owns the bar), built only when a style is
-- picked, and never reading the bar's value.

-- A bar and the settings table it follows.
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

T.test("a bar wears its own settings; None takes it off", function()
    local DUI, bar, cfg, read = setup({ style = "flow" })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    T.eq(DUI.BarFx.StyleOf(bar), "flow")
    cfg.style = "none"
    DUI.BarFx.Apply(bar)
    T.isnil(DUI.BarFx.StyleOf(bar))
end)

T.test("a bar with no settings stays still", function()
    local DUI, bar = setup()
    DUI.BarFx.Track(bar, "health", nil, "player")
    T.isnil(DUI.BarFx.StyleOf(bar))
end)

T.test("a new setup starts its frames, cast and swing bars in Flow; raid tiles stay still", function()
    local DUI = stub.Load({ module = true })
    for _, path in ipairs({ "player.barFx.health", "target.barFx.power", "party.barFx.health", "personal.barFx.power",
                            "playerCastbar.barFx", "partyCastbar.barFx", "swing.barFx" }) do
        T.eq(DUI:Get("UnitFrames", path .. ".style"), "flow", path)
    end
    T.eq(DUI:Get("UnitFrames", "raid.barFx.health.style"), "none", "forty moving bars is busy")
    T.isnil(DUI:Get("general", "barFx"), "nothing left on General")
end)

T.test("a profile from before bar styles keeps its bars still", function()
    local DUI = stub.Load({ module = true, before = function()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { general = {}, modules = {}, positions = {} } } }
    end })
    T.eq(DUI:Get("UnitFrames", "player.barFx.health.style"), "none")
end)

T.test("a pick kept on General moves onto each bar", function()
    local DUI = stub.Load({ module = true, before = function()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = {}, positions = {},
            general = { barFx = { health = { style = "flow" }, cast = { style = "tide" } } } } } }
    end })
    T.eq(DUI:Get("UnitFrames", "player.barFx.health.style"), "flow")
    T.eq(DUI:Get("UnitFrames", "targetCastbar.barFx.style"), "tide")
    T.eq(DUI:Get("UnitFrames", "player.barFx.power.style"), "none", "a kind left off stays off")
    T.eq(DUI:Get("UnitFrames", "raid.barFx.health.style"), "none", "raid tiles stay still")
    T.isnil(DUI.DB.General().barFx, "gone from General")
end)

T.test("each frame and cast bar wears its own pick", function()
    local DUI, ns = stub.Load({ module = true })
    local player, target = ns.frames.player, ns.frames.target
    T.eq(DUI.BarFx.StyleOf(player.health), "flow")
    DUI:Set("UnitFrames", "player.barFx.health.style", "tide")
    T.eq(DUI.BarFx.StyleOf(player.health), "tide", "the player's own")
    T.eq(DUI.BarFx.StyleOf(target.health), "flow", "the target keeps its own")
    DUI:Set("UnitFrames", "playerCastbar.barFx.style", "none")
    T.isnil(DUI.BarFx.StyleOf(ns.playerCastbar.bar), "the cast bar's own")
end)

T.test("every page that owns bars has a Bar animation card", function()
    local _, ns = stub.Load({ module = true })
    local want = { player = 1, target = 1, focus = 1, party = 1, raid = 1, raid20 = 1, raid40 = 1, arena = 1, targettarget = 1,
                   focustarget = 1, partyTarget = 1, pet = 1, castbars = 1, swing = 1, personal = 1 }
    for _, page in ipairs(ns.OPTIONS.pages) do
        if want[page.id] then
            local found
            for _, g in ipairs(page.groups) do
                if g.label == "Bar animation" then found = g end
            end
            T.truthy(found, page.id)
            want[page.id] = nil
        end
    end
    T.isnil(next(want), "every page seen")
end)

T.test("Flow rolls the bar's own colors on a loop the client runs", function()
    local DUI, bar, cfg, read = setup({ style = "flow" })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    T.eq(DUI.BarFx.StyleOf(bar), "flow")
    -- On the bar itself, just over the fill, under anything laid over the fill
    -- (hidden-class colors at sublevel 1, a cast's locked color at 2).
    local _, fillSub = bar:GetStatusBarTexture():GetDrawLayer()
    local strips = 0
    for _, r in ipairs({ bar:GetRegions() }) do
        local layer, sub = r:GetDrawLayer()
        if r ~= bar:GetStatusBarTexture() and r:GetObjectType() == "Texture" and layer == "ARTWORK"
            and sub > fillSub and sub < 1 then
            strips = strips + 1
            T.truthy(#(r.__masks or {}) >= 1, "masked to the fill")
        end
    end
    T.eq(strips, 4, "a base in the bar's texture, the sweep, a soft wave and its mirror, between the fill and its overlays")
    cfg.style = "none"
    DUI.Fire("StyleChanged")
    T.isnil(DUI.BarFx.StyleOf(bar), "picking none takes it off")
end)

T.test("a one-color bar flows a lighter shade of its color, so it visibly moves", function()
    local DUI, bar, _, read = setup({ style = "flow" })
    DUI.Style.NoteFillRGB(bar:GetStatusBarTexture(), 1, 0.8, 0)
    DUI.BarFx.Track(bar, "power", nil, "player", nil, read)
    local lo, hi = DUI.BarFx.Colors({ bar = bar, cfg = read })
    T.eq(lo[1], 1); T.eq(lo[2], 0.8); T.eq(lo[3], 0)
    T.truthy(hi[2] > lo[2] and hi[3] > lo[3], "the wave is lighter than the fill")
end)

-- The shown wave layers' colors, as "r,g,b" strings.
local function waveColors(bar)
    local out = {}
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r:IsShown() and r.__texture == DaylightUI.BarFx.WAVE and r.__vertex then
            local v = r.__vertex
            out[#out + 1] = string.format("%g,%g,%g", v[1], v[2], v[3])
        end
    end
    table.sort(out)
    return out
end

T.test("Flow rolls every color of a custom gradient accent, each wave a share of the loop apart", function()
    local DUI, bar, cfg, read = setup({ style = "flow" })
    DUI:Set("general", "accent", "customGradient")
    DUI:Set("general", "accentGradient.count", 4)
    DUI:Set("general", "accentGradient.c1", { 1, 0, 0 })
    DUI:Set("general", "accentGradient.c2", { 0, 1, 0 })
    DUI:Set("general", "accentGradient.c3", { 0, 0, 1 })
    DUI:Set("general", "accentGradient.c4", { 1, 1, 0 })
    stub.RunTimers()
    local groups = {}
    local make = bar.CreateAnimationGroup
    bar.CreateAnimationGroup = function(self)
        local g = make(self)
        groups[#groups + 1] = g
        return g
    end
    DUI.Style.PaintAccentBar(bar)
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    T.eq(#groups, 3, "the main loop and one for each extra wave")
    T.truthy(groups[1]:IsPlaying())
    T.falsy(groups[2]:IsPlaying(), "the next wave waits its turn")
    T.deq(waveColors(bar), { "0,1,0" }, "hidden while it waits: a still flipbook draws its whole sheet")
    stub.RunTimers()
    T.truthy(groups[2]:IsPlaying() and groups[3]:IsPlaying(), "then joins in")
    T.deq(waveColors(bar), { "0,0,1", "0,1,0", "1,1,0" }, "a bar in the accent rolls a wave of each color after the first")
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    T.deq(waveColors(bar), { "0,1,0" }, "after a reload the waves wait their turn again, out of sight")
    stub.RunTimers()

    cfg.colors = "accent"
    DUI.BarFx.Apply(bar)
    stub.RunTimers()
    T.deq(waveColors(bar), { "0,0,1", "0,1,0", "1,1,0" }, "Flow colored by the accent too")

    DUI:Set("general", "accentGradient.count", 2)
    stub.RunTimers()
    DUI.Style.PaintAccentBar(bar)
    T.deq(waveColors(bar), { "0,1,0" }, "back to two colors: one wave, the extra ones hidden")
    T.falsy(groups[2]:IsPlaying(), "and still")
end)

T.test("motion off stills every bar style", function()
    local DUI, bar, _, read = setup({ style = "flow" })
    DUI:Set("general", "motion", false)
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    T.isnil(DUI.BarFx.StyleOf(bar))
end)

T.test("a fill with secret colors keeps its plain look", function()
    local DUI, bar, _, read = setup({ style = "flow" })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    local s = stub.Secret(0.5)
    DUI.Style.NoteFillRGB(bar:GetStatusBarTexture(), s, s, s)
    T.isnil(DUI.Style.FillColors(bar:GetStatusBarTexture()), "secret colors aren't kept")
end)

T.test("power by type picks per power and follows a change", function()
    local DUI, bar, _, read = setup({ style = "auto" })
    DUI.BarFx.Track(bar, "power", nil, "player", nil, read)
    DUI.BarFx.SetPower(bar, "MANA")
    T.eq(DUI.BarFx.StyleOf(bar), DUI.BarFx.AUTO.MANA)
end)

T.test("custom colors and strength paint the strips", function()
    local DUI, bar, _, read = setup({ style = "flow", colors = "custom", colorA = { 1, 0, 0 }, strength = 0.5 })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    local lo = DUI.BarFx.Colors({ bar = bar, kind = "health", cfg = read })
    T.eq(lo[1], 1)
    T.eq(DUI.BarFx.StyleOf(bar), "flow")
end)

local function upgrader()
    return stub.Load({ module = true, before = function()
        DaylightUIDB = { version = "1.8.4", notesSeen = "1.8.4", installerSeen = true,
                         profileData = { ["DPS/Tank"] = { general = {}, modules = {}, positions = {} } } }
    end })
end

T.test("a player updating from an older version is asked once, with sample bars", function()
    local DUI = upgrader()
    stub.Dismiss()
    DUI.BarFx.Ask()
    T.eq(stub.Asked(), "barFx")
    T.truthy(DaylightUIAsk.preview:IsShown(), "the box shows the preview")
    stub.Answer(true)
    for _, path in ipairs(DUI.BarFx.HOMES.UnitFrames) do
        T.eq(DUI:Get("UnitFrames", path .. ".style"), "flow", path)
    end
    T.eq(DUI:Get("UnitFrames", "raid.barFx.health.style"), "none", "raid tiles stay still")
    T.falsy(DUI.BarFx.ShouldAsk(), "never again")
end)

T.test("Not now keeps the bars still and doesn't ask again", function()
    local DUI = upgrader()
    stub.Dismiss()
    DUI.BarFx.Ask()
    stub.Answer(false)
    T.eq(DUI:Get("UnitFrames", "player.barFx.health.style"), "none")
    T.falsy(DUI.BarFx.ShouldAsk())
end)

T.test("a brand-new account isn't asked: its setup starts with them on", function()
    local DUI = stub.Load({ module = true })
    T.falsy(DUI.BarFx.ShouldAsk())
end)

T.test("a Daylight sweep bar flows its own sweep, never plain white", function()
    local DUI = stub.Load({})
    local Style = DUI.Style
    local bar = Style.Bar(UIParent)
    bar:SetSize(200, 20)
    Style.SetBarGradient(bar, true)
    DUI.BarFx.Track(bar, "health", nil, "player", nil, DUI.BarFx.Reader(function() return { style = "flow" } end))
    local sweeps = 0
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r.GetTexture and r:GetTexture() == DUI.BarFx.SWEEP then sweeps = sweeps + 1 end
    end
    T.eq(sweeps, 1, "the sweep's own colors, looped")
end)

-- Every style beyond Flow and Tide: built over the fill with the fill's masks,
-- never outside it, under the bar's own overlays, and gone when None is picked.
T.test("every style sits over the fill, inside its shape, and comes off cleanly", function()
    local DUI = stub.Load({})
    for _, key in ipairs(DUI.BarFx.ORDER) do
        if DUI.BarFx.DEFS[key] then
            local D, bar, cfg, read = setup({ style = key })
            D.BarFx.Track(bar, "health", nil, "player", nil, read)
            T.eq(D.BarFx.StyleOf(bar), key, key)
            local fill = bar:GetStatusBarTexture()
            local _, fillSub = fill:GetDrawLayer()
            local lights = 0
            for _, r in ipairs({ bar:GetRegions() }) do
                local layer, sub = r:GetDrawLayer()
                if r ~= fill and r:GetObjectType() == "Texture" and layer == "ARTWORK" and sub > fillSub then
                    T.truthy(sub < 1, key .. ": under the bar's overlays")
                    if r:IsShown() then
                        lights = lights + 1
                        T.truthy(#(r.__masks or {}) >= 1, key .. ": wears the fill's angled end (" .. tostring(r:GetTexture()) .. " " .. tostring(sub) .. ")")
                    end
                end
            end
            T.truthy(lights > 0, key .. ": shows something")
            cfg.style = "none"
            D.BarFx.Apply(bar)
            for _, r in ipairs({ bar:GetRegions() }) do
                local layer, sub = r:GetDrawLayer()
                if r ~= fill and r:GetObjectType() == "Texture" and layer == "ARTWORK" and sub > fillSub and sub < 1 then
                    T.falsy(r:IsShown(), key .. ": hidden with None")
                end
            end
        end
    end
end)

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
        if type(file) == "string" and (file:find("barfx%-comet") or file:find("barfx%-embers")) then return r, file end
    end
end

T.test("Tide swells on its own, surges on a heal, ebbs on a hit, then lets Lua rest", function()
    local DUI, bar, _, read = setup({ style = "tide", react = true })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    local swell, surge, ebb
    for _, r in ipairs(lights(bar)) do
        if r:GetTexture() == DUI.BarFx.TIDE then swell = r
        elseif r:GetBlendMode() == "ADD" then surge = r
        else ebb = r end
    end
    T.truthy(swell, "its own swell, not Flow's rolling colors")
    for _, r in ipairs(lights(bar)) do
        T.truthy(r:GetTexture() ~= DUI.BarFx.WAVE and r:GetTexture() ~= DUI.BarFx.WAVE_EBB
            and r:GetTexture() ~= DUI.BarFx.SWEEP, "no Flow under it")
    end
    T.eq(swell:GetNumPoints(), 1, "laid over the whole fill")
    T.eq(surge:GetAlpha(), 0)
    T.eq(ebb:GetAlpha(), 0)
    DUI.BarFx.Kick(bar, 1)
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.05)
    T.truthy(surge:GetAlpha() > 0, "a heal surges")
    T.eq(ebb:GetAlpha(), 0)
    DUI.BarFx.Kick(bar, -1)
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.05)
    T.truthy(ebb:GetAlpha() > 0, "a hit ebbs")
    for _ = 1, 10 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.1) end
    T.eq(surge:GetAlpha(), 0)
    T.eq(ebb:GetAlpha(), 0)
    T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, "then no Lua runs")
end)

T.test("a style that reacts flares on a hit and lets Lua rest after", function()
    local DUI, bar, cfg, read = setup({ style = "comet", react = true })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    local flare
    for _, r in ipairs(lights(bar)) do
        if r:GetTexture() == DUI.BarFx.FLARE then flare = r end
    end
    T.truthy(flare, "a flash at the end")
    T.eq(flare:GetAlpha(), 0, "dark until something happens")
    DUI.BarFx.Kick(bar, -1)
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.05)
    T.truthy(flare:GetAlpha() > 0, "it lights on a hit")
    DUI.Gradients.PaintUnit(bar, "player")
    T.truthy(flare:GetAlpha() > 0, "a repaint mid-fade doesn't put it out or full on")
    T.truthy(flare:GetAlpha() < 1, "nor full on")
    for _ = 1, 10 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.1) end
    T.eq(flare:GetAlpha(), 0, "and fades out")
    T.isnil(DUI.Motion.Driver().__scripts.OnUpdate, "then no Lua runs")
    T.eq(DUI.BarFx.StyleOf(bar), "comet")
end)

T.test("Comet and Embers are pinned to the fill's end at a fixed size, never stretched over it", function()
    for _, key in ipairs({ "comet", "embers" }) do
        local DUI, bar, cfg, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local fill = bar:GetStatusBarTexture()
        local sheet, file = sheetOf(bar)
        T.truthy(sheet, key .. ": its sheet shows")
        T.eq(file, DUI.MEDIA .. "barfx-" .. key .. ".png", key .. ": the sheet for a tall bar")
        T.eq(sheet:GetWidth(), 20 * DUI.BarFx.SHEET_SPAN, key .. ": as wide as its art, whatever the bar's value")
        for _, r in ipairs(lights(bar)) do
            T.eq(r:GetNumPoints(), 2, key .. ": pinned by one side")
            local point, rel = r:GetPoint(1)
            T.eq(rel, fill, key .. ": to the fill")
            T.eq(point, "TOPRIGHT", key .. ": at its moving end")
            T.eq(r.__vertexOffsets[4][1], -8, key .. ": its bottom leans back with the angled end")
            T.eq(r.__vertexOffsets[3][1], 0, key .. ": its top stays on the end")
        end
        -- A thin bar gets the art drawn for thin bars.
        bar:SetSize(200, 8)
        DUI.BarFx.Apply(bar)
        local _, thin = sheetOf(bar)
        T.eq(thin, DUI.MEDIA .. "barfx-" .. key .. "-thin.png", key .. ": the thin sheet on a thin bar")
        -- A bar filling toward the left gets the art turned around, pinned to its left.
        bar:SetReverseFill(true)
        DUI.Style.AngleFill(bar, "left", 4)
        local turned, back = sheetOf(bar)
        T.eq(back, DUI.MEDIA .. "barfx-" .. key .. "-thin-l.png", key .. ": turned around")
        T.eq((turned:GetPoint(1)), "TOPLEFT", key .. ": pinned to the left end")
        T.eq(turned.__vertexOffsets[2][1], 4, key .. ": leaning the other way")
    end
end)

T.test("a light pinned to the end is cut to the fill's rectangle, and never takes a fourth mask", function()
    local DUI, bar, cfg, read = setup({ style = "comet" })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    local fill = bar:GetStatusBarTexture()
    T.eq(fill:GetNumMaskTextures(), 1, "the fill: its angled end")
    for _, r in ipairs(lights(bar)) do
        T.eq(r:GetNumMaskTextures(), 2, "the angled end and the bar's rectangle")
        -- An empty bar's fill has no width (seen in game: a rage bar at 0 showed
        -- its light past its end), so the cut is the bar's rectangle, which the
        -- fill always reaches.
        local rect = r:GetMaskTexture(2)
        local _, rel = rect:GetPoint(1)
        T.eq(rel, bar, "cut to the bar, never to the empty fill")
    end
    -- A square bar: only the rectangle. Angled later, the layers follow.
    local square = DUI.Style.Bar(UIParent)
    square:SetSize(200, 20)
    DUI.Gradients.PaintUnit(square, "player")
    DUI.BarFx.Track(square, "health", nil, "player", nil, read)
    for _, r in ipairs(lights(square)) do
        T.eq(r:GetNumMaskTextures(), 1, "a square fill: the rectangle alone")
        T.eq((r.__vertexOffsets[4] or { 0 })[1], 0, "and no lean")
    end
    DUI.Style.AngleFill(square, "right", 6)
    for _, r in ipairs(lights(square)) do
        T.eq(r:GetNumMaskTextures(), 2, "angled later: both")
        T.eq(r.__vertexOffsets[4][1], -6, "and leaning")
    end
end)

T.test("by power type picks a style per power", function()
    local DUI, bar, cfg, read = setup({ style = "auto" })
    DUI.BarFx.Track(bar, "power", nil, "player", nil, read)
    DUI.BarFx.SetPower(bar, "RAGE")
    T.eq(DUI.BarFx.StyleOf(bar), "embers")
    DUI.BarFx.SetPower(bar, "MANA")
    T.eq(DUI.BarFx.StyleOf(bar), "flow")
end)

T.test("a frame still set to a style that was taken out shows Flow", function()
    local DUI, bar, cfg, read = setup({ style = "aurora" })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    T.eq(DUI.BarFx.StyleOf(bar), "flow")
end)

-- In game an animation started behind a loading screen stayed "playing"
-- without moving, and Play did nothing to it, until another style was picked.
T.test("after a loading screen every style starts its animation over", function()
    for _, key in ipairs({ "flow", "tide", "comet", "embers" }) do
        local DUI, bar, _, read = setup({ style = key })
        local groups = {}
        local make = bar.CreateAnimationGroup
        bar.CreateAnimationGroup = function(self)
            local g = make(self)
            groups[#groups + 1] = g
            return g
        end
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
        -- A repaint keeps it going rather than starting it over.
        stops = 0
        DUI.Gradients.PaintPair(bar:GetStatusBarTexture(), { 1, 0, 0 }, { 0, 0, 1 })
        T.eq(stops, 0, key .. ": a repaint doesn't restart it")
    end
end)

-- A masked layer drawn in MOD wiped out what lay under it where its mask cut it
-- away, so the world showed through past the fill's angled edge (seen in game).
T.test("no style multiplies a layer over the bar", function()
    for _, key in ipairs({ "flow", "tide", "comet", "embers" }) do
        local DUI, bar, _, read = setup({ style = key })
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        for _, r in ipairs(lights(bar)) do
            T.truthy(r:GetBlendMode() ~= "MOD", key .. ": " .. tostring(r:GetTexture()) .. " isn't MOD")
        end
        if key == "flow" then
            local base
            for _, r in ipairs(lights(bar)) do
                if r:GetTexture() == DUI.Style.BarGrainOf(bar) then base = r end
            end
            T.truthy(base, "Flow's base wears the bar's own texture, so its shading stays")
        end
    end
end)

-- What Flow draws at one spot of the bar, worked out from its shown layers the
-- way the client blends them: a texel of the bar's texture with shading g
-- (1 = its brightest), where the rolling wave stands at w (1 = its crest).
-- barfx-wave.png's alpha at the spot is w, its partner sheet's is 1 - w.
local function flowAt(bar, g, w)
    local DUI = DaylightUI
    local grain = DUI.Style.BarGrainOf(bar)
    local layers = lights(bar)
    table.sort(layers, function(a, b)
        local _, sa = a:GetDrawLayer()
        local _, sb = b:GetDrawLayer()
        return sa < sb
    end)
    local out = { 0, 0, 0 }
    for _, r in ipairs(layers) do
        local file = r:GetTexture()
        local v = r.__vertex or { 1, 1, 1, 1 }
        local texel, a = 1, v[4] or 1
        if file == grain then texel = g
        elseif file == DUI.BarFx.WAVE then a = a * w
        elseif file == DUI.BarFx.WAVE_EBB then a = a * (1 - w) end
        for i = 1, 3 do
            local c = v[i] * texel
            if r:GetBlendMode() == "ADD" then out[i] = out[i] + c * a
            else out[i] = out[i] * (1 - a) + c * a end
        end
    end
    return out
end

local function near(a, b) return math.abs(a - b) < 0.002 end

-- A player's report: with motion on, Flow made every health and power bar
-- look the same and their picked texture (Silk) no longer showed; turning the
-- bar animations off brought it back.
T.test("Flow keeps the picked bar texture's shading all along the bar, crest and trough, in its own colors", function()
    for _, pair in ipairs({
        { "one color (power by type)", { 0.2, 0.4, 0.9 } },
        { "two colors (a class gradient)", { 0.9, 0.4, 0.6 }, { 1, 0.75, 0.55 } },
        { "colors that cross over", { 0.12, 0.56, 1 }, { 1, 0.6, 0.12 } },
    }) do
        local DUI, bar, _, read = setup({ style = "flow" })
        DUI:Set("general", "barTexture", "silk")
        stub.RunTimers()
        DUI.Style.NoteFill(bar:GetStatusBarTexture(), pair[2], pair[3] or pair[2])
        DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
        local lo, hi = DUI.BarFx.Colors({ bar = bar, cfg = read })
        for _, w in ipairs({ 0, 0.5, 1 }) do
            local lit, shaded = flowAt(bar, 1, w), flowAt(bar, 0.76, w)
            local want = { lo[1] + (hi[1] - lo[1]) * w, lo[2] + (hi[2] - lo[2]) * w, lo[3] + (hi[3] - lo[3]) * w }
            for i = 1, 3 do
                T.truthy(near(lit[i], want[i]), pair[1] .. ": the colors roll as before at " .. w
                    .. " (" .. lit[i] .. " vs " .. want[i] .. ")")
            end
            T.truthy(lit[1] + lit[2] + lit[3] - (shaded[1] + shaded[2] + shaded[3]) > 0.05,
                pair[1] .. ": Silk's shading shows at " .. w .. " along the wave")
        end
    end
end)

T.test("a texture picked while Flow runs shows on the bar at once", function()
    local DUI, bar, _, read = setup({ style = "flow" })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    DUI:Set("general", "barTexture", "glass")
    stub.RunTimers()
    local glass = DUI.Style.BarGrainOf(bar)
    T.truthy(type(glass) == "string" and glass:find("bar%-glass"), "the bar follows the pick")
    local found
    for _, r in ipairs(lights(bar)) do if r:GetTexture() == glass then found = true end end
    T.truthy(found, "and Flow's layers wear it")
end)
