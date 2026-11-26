local stub = require("stub")

-- Proc Alerts' flares (DaylightUI_Procs/Flares.lua): painted light around the
-- character, placed by design and lane, tinted with the accent pair.

local function load(opts)
    opts = opts or {}
    stub.Load({ procs = true, before = function()
        stub.SetUnits({ player = { name = "Me", class = opts.class or "WARRIOR", isPlayer = true } })
        if opts.before then opts.before() end
    end })
    return stub.procs
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 30) end
end

local function point(region)
    local p, _, _, x, y = region:GetPoint(1)
    return p, x, y
end

T.test("procs look: the right half of every design is the left half mirrored", function()
    local ns = load()
    for _, design in ipairs(ns.Data.DESIGN_ORDER) do
        local sp = ns.Data.SPOTS[ns.Data.DESIGNS[design].spot]
        if sp.mirrored then
            ns.Alerts.Set("overpower", "design", design)
            ns.Flares.Show("overpower")
            settle()
            local f = ns.Flares.live.overpower
            local l, r = f.parts[1], f.parts[2]
            T.truthy(r.frame:IsShown(), design .. ": both halves drawn")
            T.near(l.frame:GetWidth(), r.frame:GetWidth(), 0.01, design .. ": same width")
            T.near(l.frame:GetHeight(), r.frame:GetHeight(), 0.01, design .. ": same height")
            local _, lx, ly = point(l.frame)
            local _, rx, ry = point(r.frame)
            T.near(lx, -rx, 0.01, design .. ": opposite x")
            T.near(ly, ry, 0.01, design .. ": same y")
            local a = { l.tex:GetTexCoord() }
            local b = { r.tex:GetTexCoord() }
            T.eq(a[1], b[2], design .. ": left edge flipped")
            T.eq(a[2], b[1], design .. ": right edge flipped")
            ns.Flares.Hide("overpower", true)
        end
    end
end)

T.test("procs look: two procs up at once never share a design or a lane", function()
    local ns = load()
    ns.Alerts.Set("overpower", "design", "wings")
    ns.Alerts.Set("revenge", "design", "talons")
    ns.Alerts.Set("execute", "design", "flames")
    ns.Flares.Show("overpower")
    ns.Flares.Show("revenge")   -- the same frame, the same spot
    settle()
    local a, b = ns.Flares.live.overpower, ns.Flares.live.revenge
    T.eq(a.lane, 0)
    T.eq(b.lane, 1, "the second side design moves out a lane")
    T.truthy(a.design ~= b.design, "never the same design")
    local _, lx = point(b.parts[1].frame)
    local _, rx = point(b.parts[2].frame)
    T.near(lx, -128, 0.01, "lane 1's left inner edge")
    T.near(rx, 128, 0.01, "lane 1's right inner edge")
    ns.Flares.Hide("overpower", true)
    ns.Flares.Show("execute")
    settle()
    T.eq(ns.Flares.live.execute.lane, 0, "a freed lane is taken again")
    T.eq(ns.Flares.live.revenge.lane, 1, "a flare keeps its lane until hidden")
end)

T.test("procs look: a flare is tinted with the accent pair and repaints when the accent changes", function()
    local ns = load()
    local DUI = DaylightUI
    DUI:Set("general", "accent", "gradient")
    ns.Flares.Show("overpower")
    settle()
    local tex = ns.Flares.live.overpower.parts[1].tex
    local g = tex.__gradient
    T.eq(g[1], "VERTICAL")
    local lo, hi = DUI.Style.AccentPair()
    T.rgb({ g[2].r, g[2].g, g[2].b }, lo, "the bottom is the pair's first end")
    T.rgb({ g[3].r, g[3].g, g[3].b }, hi, "the top is the pair's second end")
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.8, 0.3 })
    DUI:GetModule("Procs").OnStyleChanged(DUI:GetModule("Procs"))
    g = tex.__gradient
    local c = { DUI.Style.Accent() }
    T.rgb({ g[3].r, g[3].g, g[3].b }, c, "a flat accent paints both ends")
    T.rgb({ g[2].r, g[2].g, g[2].b }, c)
end)

T.test("procs look: the numbers match the mock-up", function()
    local ns = load()
    local function show(design)
        ns.Alerts.Set("overpower", "design", design)
        ns.Flares.Show("overpower")
        settle()
        return ns.Flares.live.overpower
    end
    local f = show("wings")
    local l = f.parts[1].frame
    T.near(l:GetWidth(), 256, 0.01); T.near(l:GetHeight(), 256, 0.01)
    local p, x, y = point(l)
    T.eq(p, "RIGHT"); T.near(x, -64, 0.01); T.near(y, 10, 0.01)
    ns.Flares.Hide("overpower", true)
    f = show("crown")
    p, x, y = point(f.parts[1].frame)
    T.eq(p, "BOTTOM"); T.near(x, 0, 0.01); T.near(y, 104, 0.01)
    T.near(f.parts[1].frame:GetWidth(), 160, 0.01)
    T.falsy(f.parts[2].frame:IsShown(), "a centered design is one piece")
    ns.Flares.Hide("overpower", true)
    f = show("sun")
    p, x, y = point(f.parts[1].frame)
    T.eq(p, "CENTER"); T.near(y, 70, 0.01); T.near(f.parts[1].frame:GetWidth(), 208, 0.01)
    ns.Flares.Hide("overpower", true)
    f = show("ring")
    p, x, y = point(f.parts[1].frame)
    T.eq(p, "CENTER"); T.near(y, -118, 0.01); T.near(f.parts[1].frame:GetWidth(), 304, 0.01)
    ns.Flares.Hide("overpower", true)
    f = show("comet")
    p, x, y = point(f.parts[1].frame)
    T.eq(p, "BOTTOMRIGHT"); T.near(x, -36, 0.01); T.near(y, 96, 0.01)
    T.near(f.parts[1].frame:GetWidth(), 176, 0.01)
    p, x = point(f.parts[2].frame)
    T.eq(p, "BOTTOMLEFT"); T.near(x, 36, 0.01)
end)

local function run(seconds)
    local d = DaylightUI.Motion.Driver()
    local n = math.floor(seconds / 0.05 + 0.5)
    for _ = 1, n do
        stub.Advance(0.05)
        stub.RunOnUpdate(d, 0.05)
    end
end

-- Moving flares (every animation but Still): drawn sheets the client plays.

local ANIMS = { "strike", "breathe", "pulse", "impact", "flash" }
local WARM = { 1, 0.97, 0.9 }

local function media(name) return DaylightUI.MEDIA .. name end

local function lift(c, k)
    return { c[1] + (WARM[1] - c[1]) * k, c[2] + (WARM[2] - c[2]) * k, c[3] + (WARM[3] - c[3]) * k }
end

-- A group's FlipBook (its first).
local function flipbook(g)
    for _, a in ipairs({ g:GetAnimations() }) do
        if a:GetObjectType() == "FlipBook" then return a end
    end
end

-- How long one pass of a group takes: its orders one after another.
local function cycle(g)
    local by = {}
    for _, a in ipairs({ g:GetAnimations() }) do
        local o = a:GetOrder()
        local t = a:GetStartDelay() + a:GetDuration() + a:GetEndDelay()
        by[o] = math.max(by[o] or 0, t)
    end
    local sum = 0
    for _, t in pairs(by) do sum = sum + t end
    return sum
end

-- Every texture under a frame.
local function textures(frame, out)
    out = out or {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetTexture then out[#out + 1] = r end
    end
    for _, c in ipairs({ frame:GetChildren() }) do textures(c, out) end
    return out
end

local SHEET = { "%-live", "%-burn", "%-gleam", "flare%-sparks", "flare%-embers" }
local function sheetsHeld(f)
    local held = {}
    for _, t in ipairs(textures(f)) do
        local file = t:GetTexture()
        if type(file) == "string" then
            for _, pat in ipairs(SHEET) do
                if file:find(pat) then held[#held + 1] = file end
            end
        end
    end
    return held
end

local OWN = { "breathe", "beat", "wave", "gleam" }
local function ownPlaying(f, part)
    local on = {}
    for _, name in ipairs(OWN) do
        if part[name] and part[name]:IsPlaying() then on[#on + 1] = name end
    end
    if f.burst and f.burst.again:IsPlaying() then on[#on + 1] = "again" end
    return table.concat(on, "+")
end

local function show(ns, design, anim, info)
    ns.Alerts.Set("overpower", "design", design)
    ns.Alerts.Set("overpower", "anim", anim)
    ns.Flares.Show("overpower", info)
    return ns.Flares.live.overpower
end

T.test("procs look: a moving flare plays each piece's own sheet, the right piece from its right-hand file", function()
    local ns = load()
    for _, anim in ipairs(ANIMS) do
        local f = show(ns, "wings", anim)
        settle()
        for i, part in ipairs(f.parts) do
            local want = media(i == 1 and "flare-wings-live.png" or "flare-wings-live-r.png")
            T.eq(part.liveTex:GetTexture(), want, anim .. ": piece " .. i .. "'s own sheet")
            T.isnil(part.liveTex.__texCoord, anim .. ": a played sheet's coordinates are never touched")
            local fb = flipbook(part.live)
            T.truthy(fb, anim .. ": a FlipBook")
            T.eq(fb:GetTarget(), part.liveTex)
            T.eq(fb:GetFlipBookFrames(), 32); T.eq(fb:GetFlipBookColumns(), 8); T.eq(fb:GetFlipBookRows(), 4)
            T.falsy(part.tex:IsShown(), anim .. ": the still painting is hidden")
            T.falsy(part.core:IsShown(), anim .. ": the still core is hidden")
            T.truthy(part.liveTex:IsShown())
        end
        ns.Flares.Hide("overpower", true)
    end
    local f = show(ns, "sun", "strike")
    settle()
    T.eq(f.parts[1].liveTex:GetTexture(), media("flare-sun-live.png"))
    T.falsy(f.parts[2].frame:IsShown(), "a one-piece design shows only its first piece")
end)

T.test("procs look: a flare loops its flicker and its embers with no Lua running", function()
    local ns = load()
    local f = show(ns, "wings", "strike")
    settle()
    local _, hi = ns.Alerts.Colors("overpower")
    for _, part in ipairs(f.parts) do
        T.truthy(part.live:IsPlaying(), "the flicker plays")
        T.eq(part.live:GetLooping(), "REPEAT")
        T.truthy(part.embers:IsPlaying(), "the embers play")
        T.eq(part.embers:GetLooping(), "REPEAT")
        T.eq(part.emberTex:GetTexture(), media("flare-embers.png"))
        local fb = flipbook(part.embers)
        T.eq(fb:GetFlipBookFrames(), 48); T.eq(fb:GetFlipBookColumns(), 8); T.eq(fb:GetFlipBookRows(), 6)
        local v = part.emberTex.__vertex
        T.rgb({ v[1], v[2], v[3] }, lift(hi, 0.3), "embers: the top color lifted toward white")
    end
    T.isnil(DaylightUI.Motion.Driver():GetScript("OnUpdate"), "nothing runs Lua per frame once it's up")
end)

T.test("procs look: with motion off, or on Still, a flare shows the still painting", function()
    for _, case in ipairs({ "motion off", "still" }) do
        local ns = load()
        if case == "motion off" then DaylightUI:Set("general", "motion", false) end
        local f = show(ns, "wings", case == "still" and "still" or "pulse")
        settle()
        T.eq(#sheetsHeld(f), 0, case .. ": no sheet set (" .. table.concat(sheetsHeld(f), ", ") .. ")")
        T.eq(f.parts[1].tex:GetTexture(), media("flare-wings.png"))
        T.truthy(f.parts[1].tex:IsShown(), case .. ": the painting shows")
        for _, part in ipairs(f.parts) do
            for _, g in ipairs(ns.Flares.AllLoops(part)) do T.falsy(g:IsPlaying(), case .. ": no loop plays") end
        end
    end
end)

-- The strike in, the burn out ------------------------------------------------

local function ease(p) return 1 - (1 - p) ^ 3 end

T.test("procs look: a flare is revealed outward from the character with a white front and a spark burst", function()
    local ns = load()
    local F = ns.Flares
    local f = show(ns, "wings", "strike")
    T.near(f:GetAlpha(), F.Opacity("overpower"), 0.001, "full brightness at once")
    local l, r = f.parts[1], f.parts[2]
    T.near(l.flashFrame:GetAlpha(), 1, 0.01, "the core flashes at full strength")
    T.truthy(f.burst.group:IsPlaying(), "the sparks fly")
    T.eq(f.burst.group:GetLooping(), "NONE", "once")
    T.near(f.burst.left.__vertex[4], 1, 0.001, "Strike's sparks at full brightness")
    T.eq(f.burst.left:GetTexture(), media("flare-sparks.png"))
    T.eq(f.burst.right:GetTexture(), media("flare-sparks-r.png"))
    T.near(f.burst.left:GetWidth(), 2 * 256, 0.5, "a spark frame is twice the piece")
    run(0.1)    -- halfway through the reveal (Motion.NORMAL)
    local w = ease(0.5) * 1.2 * 256
    T.near(l.liveFrame:GetWidth(), w, 1, "the left piece revealed from its inner edge")
    T.eq((point(l.liveFrame)), "BOTTOMRIGHT")
    T.eq((point(r.liveFrame)), "BOTTOMLEFT", "the right one mirrored")
    T.near(l.liveFrame:GetHeight(), 256, 0.5)
    T.near(l.liveTex:GetWidth(), 256, 0.01, "the sheet keeps its size inside the clip")
    T.truthy(l.liveFrame.__clips, "the reveal is a clipping frame")
    T.truthy(l.frontFrame:IsShown(), "the white front rides the edge")
    T.near(l.frontFrame:GetWidth(), 0.06 * 256, 0.01)
    local _, fx = point(l.frontFrame)
    T.near(fx, -(w - 0.06 * 256), 1, "at the reveal's edge")
    T.near(l.frontFrame:GetAlpha(), 1 - ease(0.5), 0.02, "fading as it goes")
    local flash = l.flashFrame:GetAlpha()
    T.truthy(flash < 1 and flash > 0, "the core's flash settling")
    settle()
    T.near(f.reveal, 1, 0.0001, "the reveal is whole")
    T.falsy(l.frontFrame:IsShown(), "the front is gone")
    T.near(l.flashFrame:GetAlpha(), 0, 0.001)
    ns.Flares.Hide("overpower", true)
    -- Calmer animations throw dimmer sparks.
    f = show(ns, "wings", "breathe")
    T.near(f.burst.left.__vertex[4], 0.5, 0.001, "Breathe's sparks")
    ns.Flares.Hide("overpower", true)
    -- An above piece grows from the bottom up.
    f = show(ns, "crown", "strike")
    run(0.05)   -- a quarter of the way: the front still inside the piece
    T.near(f.parts[1].liveFrame:GetHeight(), ease(0.25) * 1.2 * 160, 1, "above: from the bottom")
    T.near(f.parts[1].liveFrame:GetWidth(), 160, 0.5)
    T.eq((point(f.parts[1].liveFrame)), "BOTTOM")
    ns.Flares.Hide("overpower", true)
    -- Sun and feet have no inner edge: they grow from 0.7 and fade in.
    f = show(ns, "sun", "strike")
    run(0.1)
    T.near(f.parts[1].frame:GetWidth(), (0.7 + 0.3 * ease(0.5)) * 208, 1, "sun grows")
    T.near(f.parts[1].liveFrame:GetAlpha(), ease(0.5), 0.02, "and comes in")
    T.falsy(f.parts[1].frontFrame:IsShown(), "no front on a disc")
    settle()
    T.near(f.parts[1].frame:GetWidth(), 208, 0.01)
    T.near(f.parts[1].liveFrame:GetAlpha(), 1, 0.001)
end)

T.test("procs look: a flare burns away on its own sheet, then its frame is reused clean", function()
    local ns = load()
    local f = show(ns, "wings", "strike")
    run(0.1)
    ns.Flares.Hide("overpower")
    for i, part in ipairs(f.parts) do
        T.falsy(part.live:IsPlaying(), "the flicker stops")
        T.eq(ownPlaying(f, part), "")
        T.falsy(part.liveTex:IsShown(), "its sheet hides")
        T.truthy(part.burnTex:IsShown(), "the burn shows")
        T.eq(part.burnTex:GetTexture(), media(i == 1 and "flare-wings-burn.png" or "flare-wings-burn-r.png"))
        T.truthy(part.burn:IsPlaying())
        T.eq(part.burn:GetLooping(), "NONE", "once")
        T.near(flipbook(part.burn):GetDuration(), DaylightUI.Motion.SLOW, 0.0001)
        T.truthy(part.embers:IsPlaying(), "embers keep rising")
        T.falsy(part.frontFrame:IsShown(), "no front while it burns")
        T.near(part.flashFrame:GetAlpha(), 0, 0.001, "no flash while it burns")
    end
    T.truthy(f:IsShown(), "still burning")
    run(DaylightUI.Motion.SLOW + 0.05)
    T.falsy(f:IsShown(), "gone after the burn")
    ns.Alerts.Set("revenge", "anim", "still")
    ns.Flares.Show("revenge")
    T.eq(ns.Flares.live.revenge, f, "the pool hands the same frame back")
    T.near(f.reveal, 1, 0.0001)
    for _, part in ipairs(f.parts) do
        T.falsy(part.burnTex:IsShown(), "no burn left")
        T.falsy(part.liveTex:IsShown(), "no live sheet")
        T.falsy(part.frontFrame:IsShown(), "no front")
        T.near(part.flashFrame:GetAlpha(), 0, 0.001, "no flash")
        T.falsy(part.burn:IsPlaying())
    end
    T.falsy(f.burst.group:IsPlaying(), "no sparks")
    T.eq(#sheetsHeld(f), 0, "no sheet on a Still flare")
end)

T.test("procs look: a proc renewed or used during the strike leaves one flare and a clean pool", function()
    local ns = load()
    local f = show(ns, "wings", "impact")
    run(0.05)
    ns.Flares.Hide("overpower")
    run(0.05)
    local g = show(ns, "wings", "impact")
    T.truthy(g ~= f, "a new flare while the old one burns")
    run(0.6)
    T.falsy(f:IsShown(), "the old one went back to the pool")
    for _, part in ipairs(f.parts) do
        for _, grp in ipairs(ns.Flares.AllLoops(part)) do T.falsy(grp:IsPlaying(), "nothing left playing on the pooled one") end
        T.falsy(part.burn:IsPlaying())
    end
    T.falsy(f.burst.group:IsPlaying()); T.falsy(f.burst.again:IsPlaying())
    T.eq(ns.Flares.live.overpower, g, "one live flare")
    T.truthy(g.parts[1].live:IsPlaying())
end)

-- Each animation's own motion ------------------------------------------------

T.test("procs look: each animation adds its own motion to the flicker", function()
    local ns = load()
    local want = { strike = "", breathe = "breathe", pulse = "beat", impact = "wave+again", flash = "gleam" }
    local K = ns.Flares.KINDS
    for _, anim in ipairs(ANIMS) do
        local f = show(ns, "wings", anim)
        settle()
        for _, part in ipairs(f.parts) do
            T.eq(ownPlaying(f, part), want[anim], anim .. "'s own groups")
            T.near(flipbook(part.live):GetDuration(), anim == "breathe" and 4 or 2, 0.0001, anim .. ": the flicker's loop")
            T.near(part.emberTex.__vertex[4], K[anim].embers, 0.001, anim .. ": embers' brightness")
        end
        T.near(f.burst.left.__vertex[4], K[anim].sparks, 0.001, anim .. ": sparks' brightness")
        local p = f.parts[1]
        if anim == "breathe" then
            local a = p.breathe:GetAnimations()
            T.eq(p.breathe:GetLooping(), "BOUNCE")
            T.eq(a:GetFromAlpha(), 1); T.eq(a:GetToAlpha(), 0.55)
            T.near(a:GetDuration(), 1.6, 0.0001); T.eq(a:GetSmoothing(), "IN_OUT")
            T.eq(a:GetTarget() or p.frame, p.frame, "the whole piece dims")
        elseif anim == "pulse" then
            local a = p.beat:GetAnimations()
            T.eq(p.beat:GetLooping(), "REPEAT")
            T.eq(a:GetToAlpha(), 1, "the core lights to full"); T.near(a:GetDuration(), 0.03, 0.0001)
            T.near(cycle(p.beat), 1.0, 0.0001, "a beat a second")
            local peaks = {}
            for _, x in ipairs({ p.beat:GetAnimations() }) do peaks[#peaks + 1] = x:GetToAlpha() end
            T.truthy(table.concat(peaks, ","):find("0.7"), "a second, softer beat")
        elseif anim == "impact" then
            T.near(cycle(p.wave), 1.4, 0.0001, "a wave every 1.4 s")
            local sx
            for _, x in ipairs({ p.wave:GetAnimations() }) do
                if x:GetObjectType() == "Scale" then sx = x:GetScaleTo(); T.near(x:GetDuration(), 0.75, 0.0001) end
                if x:GetObjectType() == "Alpha" then T.eq(x:GetFromAlpha(), 0.5) end
            end
            T.near(sx, 1.45, 0.0001, "the ghost swells to 1.45")
            T.near(cycle(f.burst.again), 1.4, 0.0001, "the sparks fly again every wave")
            T.eq(f.burst.again:GetLooping(), "REPEAT")
        elseif anim == "flash" then
            T.near(cycle(p.gleam), 1.6, 0.0001, "a gleam every 1.6 s")
            T.near(flipbook(p.gleam):GetDuration(), 0.45, 0.0001)
            T.eq(p.gleamTex:GetTexture(), media("flare-wings-gleam.png"))
            T.eq(f.parts[2].gleamTex:GetTexture(), media("flare-wings-gleam-r.png"))
        end
        ns.Flares.Hide("overpower", true)
    end
end)

T.test("procs look: none of the old loops is left", function()
    local ns = load()
    T.isnil(ns.Flares.PULSE); T.isnil(ns.Flares.GLINT)
    for _, anim in ipairs(ANIMS) do
        local f = show(ns, "wings", anim)
        settle()
        for _, part in ipairs(f.parts) do
            for _, g in ipairs({ part.frame:GetAnimationGroups() }) do
                for _, a in ipairs({ g:GetAnimations() }) do
                    T.truthy(a:GetObjectType() ~= "Scale", anim .. ": nothing scales a piece")
                end
            end
            T.isnil(part.pulse); T.isnil(part.swell); T.isnil(part.glint)
        end
        ns.Flares.Hide("overpower", true)
    end
end)

T.test("procs look: changing the animation or motion while a flare is up swaps it at once", function()
    local ns = load()
    local f = show(ns, "wings", "pulse")
    settle()
    T.eq(ownPlaying(f, f.parts[1]), "beat")
    ns.Alerts.Set("overpower", "anim", "flash")
    f = ns.Flares.live.overpower
    settle()
    T.eq(ownPlaying(f, f.parts[1]), "gleam", "only Flash's group plays now")
    ns.Alerts.Set("overpower", "anim", "still")
    f = ns.Flares.live.overpower
    settle()
    T.eq(#sheetsHeld(f), 0, "no sheet on Still")
    T.truthy(f.parts[1].tex:IsShown())
    for _, part in ipairs(f.parts) do
        for _, g in ipairs(ns.Flares.AllLoops(part)) do T.falsy(g:IsPlaying(), "Still: nothing plays") end
    end
    ns.Alerts.Set("overpower", "anim", "pulse")
    settle()
    DaylightUI:Set("general", "motion", false)
    DaylightUI:GetModule("Procs").OnStyleChanged(DaylightUI:GetModule("Procs"))
    f = ns.Flares.live.overpower
    T.eq(#sheetsHeld(f), 0, "motion off: no sheet")
    for _, part in ipairs(f.parts) do
        for _, g in ipairs(ns.Flares.AllLoops(part)) do T.falsy(g:IsPlaying(), "motion off: nothing plays") end
    end
end)

-- The time drain on a moving flare -------------------------------------------

T.test("procs look: a moving flare drains from its tip by clipping, its sheet never squeezed", function()
    local ns = load()
    ns.Alerts.Set("overpower", "drain", true)
    local f = show(ns, "wings", "flash", { left = 10, dur = 10 })
    run(0.1)
    local part = f.parts[1]
    T.near(part.liveFrame:GetWidth(), ease(0.5) * 1.2 * 256, 1, "the strike holds its width")
    T.near(part.liveFrame:GetHeight(), 256 * 0.99, 1.5, "and the drain its height")
    run(4.9)
    T.near(part.liveFrame:GetHeight(), 128, 3, "half the time gone: half as tall, from the bottom")
    T.near(part.liveTex:GetHeight(), 256, 0.01, "the sheet keeps its full size")
    T.isnil(part.liveTex.__texCoord, "and its coordinates")
    T.truthy(part.gleamFrame:GetParent() == part.liveFrame, "the gleam is cut by the same clip")
    ns.Flares.Show("overpower", { left = 10, dur = 10 })
    run(0.1)
    T.near(part.liveFrame:GetHeight(), 256 * 0.99, 1.5, "a renewed proc grows back")
    ns.Flares.Hide("overpower", true)
    -- Impact's ghost is the still painting: cut by its coordinates, like the light.
    f = show(ns, "wings", "impact", { left = 10, dur = 10 })
    run(5)
    T.near(f.parts[1].echoTex:GetHeight(), 128, 3, "the wave's ghost is cut the same")
    ns.Flares.Hide("overpower", true)
    -- A ring at the feet fades instead.
    f = show(ns, "ring", "strike", { left = 10, dur = 10 })
    run(5)
    T.near(f.parts[1].liveTex.__gradient[3].a, 0.675, 0.03, "halfway from 1 to 0.35")
    T.near(f.parts[1].liveFrame:GetHeight(), 304, 0.5, "a ring stays whole")
end)

-- The still flare (Still, or motion off) keeps today's in and out.
T.test("procs look: a Still flare fades in and out, and its frame is reused", function()
    local ns = load()
    ns.Alerts.Set("overpower", "anim", "still")
    ns.Flares.Show("overpower")
    local f = ns.Flares.live.overpower
    T.truthy(f:GetAlpha() < 1, "starts faded")
    settle()
    T.near(f:GetAlpha(), 1, 0.001)
    ns.Flares.Hide("overpower")
    T.falsy(ns.Flares.Shown("overpower"), "gone from the live list at once")
    T.truthy(f:IsShown(), "still fading out")
    settle()
    T.falsy(f:IsShown())
    ns.Flares.Show("revenge")
    T.eq(ns.Flares.live.revenge, f, "the pool hands the same frame back")
end)

T.test("procs look: with motion off a flare shows at once and has no loop playing", function()
    local ns = load()
    DaylightUI:Set("general", "motion", false)
    ns.Alerts.Set("overpower", "anim", "pulse")
    ns.Flares.Show("overpower")
    local f = ns.Flares.live.overpower
    T.near(f:GetAlpha(), 1, 0.001, "full at once")
    T.near(f.parts[1].frame:GetWidth(), 256, 0.01, "full size at once")
    for _, part in ipairs(f.parts) do
        for _, g in ipairs(ns.Flares.AllLoops(part)) do T.falsy(g:IsPlaying()) end
    end
    ns.Flares.Hide("overpower")
    T.falsy(f:IsShown(), "gone at once")
end)

T.test("procs look: works with no other module loaded", function()
    local ns = load()
    T.truthy(DaylightUI:GetModule("Procs").enabled)
    T.truthy(_G.DaylightUIProcs, "the holder")
    T.isnil(DaylightUI:GetModule("ActionBars"))
    ns.Flares.Show("overpower")
    settle()
    T.truthy(ns.Flares.Shown("overpower"))
    T.eq(#stub.errors, 0)
end)

-- Time drain and stacks ---------------------------------------------------------


T.test("procs look: a flare drains from its tip as its time runs out", function()
    local ns = load()
    ns.Alerts.Set("overpower", "drain", true)
    ns.Alerts.Set("revenge", "drain", true)
    ns.Alerts.Set("overpower", "design", "wings")
    ns.Flares.Show("overpower", { left = 10, dur = 10 })
    run(5)
    local part = ns.Flares.live.overpower.parts[1]
    local _, _, top, bottom = part.tex:GetTexCoord()
    T.near(top, 0.5, 0.02, "the top half is gone")
    T.eq(bottom, 1)
    T.near(part.tex:GetHeight(), 128, 3, "and the light is half as tall, from its base")
    local _, _, top2 = ns.Flares.live.overpower.parts[2].tex:GetTexCoord()
    T.near(top2, top, 0.001, "both halves drain together")
    -- Renewed: full again, draining over the new time.
    ns.Flares.Show("overpower", { left = 10, dur = 10 })
    run(0.1)
    _, _, top = part.tex:GetTexCoord()
    T.near(top, 0.01, 0.02, "a renewed proc fills up again")
    -- A design at the feet fades instead.
    ns.Alerts.Set("revenge", "design", "ring")
    ns.Flares.Show("revenge", { left = 10, dur = 10 })
    run(5)
    local g = ns.Flares.live.revenge.parts[1].tex.__gradient
    T.near(g[3].a, 0.675, 0.03, "halfway from 1 to 0.35")
    _, _, top = ns.Flares.live.revenge.parts[1].tex:GetTexCoord()
    T.eq(top, 0, "a ring stays whole")
end)

T.test("procs look: a stacking proc stays dim until its last stack", function()
    local ns = load({ class = "MAGE" })
    ns.Flares.Show("hotstreak", { stacks = 2 })
    T.falsy(ns.Flares.Shown("hotstreak"), "below Show from (its most, 3)")
    ns.Alerts.Set("hotstreak", "fromStacks", 1)
    ns.Flares.Show("hotstreak", { stacks = 1 })
    T.truthy(ns.Flares.Shown("hotstreak"))
    local tex = ns.Flares.live.hotstreak.parts[1].tex
    T.near(tex.__gradient[3].a, 0.45 + 0.55 / 3, 0.001, "one stack of three")
    ns.Flares.Show("hotstreak", { stacks = 3 })
    T.near(tex.__gradient[3].a, 1, 0.001, "full at the last stack")
    ns.Flares.Show("hotstreak", { stacks = 2 })
    T.near(tex.__gradient[3].a, 0.45 + 0.55 * 2 / 3, 0.001)
    ns.Alerts.Set("hotstreak", "fromStacks", 3)
    ns.Flares.Show("hotstreak", { stacks = 2 })
    T.falsy(ns.Flares.Shown("hotstreak"), "dropping below Show from hides it")
end)

T.test("procs look: Drain is off by default and keeps the flare whole", function()
    local ns = load()
    ns.Flares.Show("overpower", { left = 10, dur = 10 })
    run(5)
    local _, _, top = ns.Flares.live.overpower.parts[1].tex:GetTexCoord()
    T.eq(top, 0)
end)

T.test("procs look: a proc with no timer never drains", function()
    local ns = load()
    ns.Flares.Show("execute", {})
    run(5)
    local _, _, top = ns.Flares.live.execute.parts[1].tex:GetTexCoord()
    T.eq(top, 0)
    T.near(ns.Flares.live.execute.parts[1].tex.__gradient[3].a, 1, 0.001)
end)

T.test("procs look: the hot core carries the alert's colors, never white over them", function()
    local ns = load()
    ns.Alerts.Set("overpower", "colorMode", "custom")
    ns.Alerts.Set("overpower", "colorTop", { 1, 0, 0 })
    ns.Alerts.Set("overpower", "colorBottom", { 0, 0, 1 })
    ns.Flares.Show("overpower", {})
    local core = ns.Flares.live.overpower.parts[1].core
    local g = core.__gradient
    T.truthy(g, "the core is tinted with the alert's pair")
    local lo, hi = g[2], g[3]
    T.truthy(hi.g < 0.5 and hi.b < 0.5, "top stays red, not white")
    T.truthy(lo.r < 0.5 and lo.g < 0.5, "bottom stays blue, not white")
    T.truthy(hi.a <= 0.4, "and it's soft")
end)

T.test("procs look: Animation speed scales every loop, and a change keeps the flare up", function()
    local ns = load()
    local own = { breathe = "breathe", pulse = "beat", impact = "wave", flash = "gleam" }
    for _, anim in ipairs({ "strike", "breathe", "pulse", "impact", "flash" }) do
        ns.Alerts.Set("overpower", "speed", 1)
        local f = show(ns, "wings", anim)
        settle()
        local p = f.parts[2]
        local live, embers = flipbook(p.live):GetDuration(), flipbook(p.embers):GetDuration()
        local mine = own[anim] and cycle(p[own[anim]])
        local sparks, burn = flipbook(f.burst.group):GetDuration(), flipbook(p.burn):GetDuration()
        ns.Alerts.Set("overpower", "speed", 2)
        T.eq(ns.Flares.live.overpower, f, anim .. ": the same flare, not shown again")
        T.near(f:GetAlpha(), 1, 0.001, anim .. ": no fade out and in")
        T.near(flipbook(p.live):GetDuration(), live / 2, 0.0001, anim .. ": the flicker twice as fast")
        T.near(flipbook(p.embers):GetDuration(), embers / 2, 0.0001, anim .. ": the embers too")
        if mine then T.near(cycle(p[own[anim]]), mine / 2, 0.0001, anim .. ": its own motion too") end
        T.near(flipbook(f.burst.group):GetDuration(), sparks, 0.0001, anim .. ": the strike's sparks keep their time")
        T.near(flipbook(p.burn):GetDuration(), burn, 0.0001, anim .. ": the burn keeps its time")
        T.truthy(p.live:IsPlaying(), anim .. " still plays")
        if own[anim] then T.truthy(p[own[anim]]:IsPlaying(), anim .. "'s own group still plays") end
        ns.Flares.Hide("overpower", true)
    end
    -- A profile from before the update: Pulse saved, at speed 2. The new Pulse plays at twice the speed.
    ns.Alerts.Set("overpower", "speed", 2)
    local f = show(ns, "wings", "pulse")
    settle()
    T.near(flipbook(f.parts[1].live):GetDuration(), 1, 0.0001, "the flicker at double speed")
    T.near(cycle(f.parts[1].beat), 0.5, 0.0001, "two beats a second")
    -- A flare shown later (from the pool) takes the speed too.
    ns.Flares.Hide("overpower", true)
    ns.Alerts.Set("overpower", "speed", 0.5)
    f = show(ns, "wings", "pulse")
    T.near(flipbook(f.parts[1].live):GetDuration(), 4, 0.0001, "half speed takes twice as long")
end)

-- The client stops a frame's animations while it's hidden (the UI hidden with
-- Alt+Z, a loading screen), and a sheet that isn't playing draws squashed.
local function clientHides(frame, groups)
    frame:Hide()
    for _, g in ipairs(groups) do g:Stop() end
end

T.test("procs look: a moving flare starts its loops again when the UI comes back", function()
    local ns = load()
    ns.Alerts.Set("overpower", "design", "wings")
    ns.Alerts.Set("overpower", "anim", "flash")
    ns.Flares.Show("overpower")
    settle()
    local f = ns.Flares.live.overpower
    local groups = {}
    for _, part in ipairs(f.parts) do
        for _, g in ipairs(ns.Flares.AllLoops(part)) do groups[#groups + 1] = g end
    end
    clientHides(ns.Flares.holder, groups)
    ns.Flares.holder:Show()
    for _, part in ipairs(f.parts) do
        T.truthy(part.live:IsPlaying(), "the flicker plays again")
        T.truthy(part.embers:IsPlaying(), "the embers too")
        T.truthy(part.gleam:IsPlaying(), "and Flash's gleam")
    end
    -- Hidden while it burns: no burn sheet left standing still.
    ns.Flares.Hide("overpower")
    local burns = {}
    for _, part in ipairs(f.parts) do burns[#burns + 1] = part.burn end
    clientHides(ns.Flares.holder, burns)
    ns.Flares.holder:Show()
    T.falsy(f:IsShown(), "a burning flare hidden mid-burn goes straight back to the pool")
    for _, part in ipairs(f.parts) do T.falsy(part.burnTex:IsShown()) end
end)

T.test("procs look: the options preview starts its loops again when the window opens again", function()
    local ns = load()
    local s = DaylightUI.Options.GetPage("Procs.alerts").sample(UIParent)
    ns.Alerts.Set("overpower", "anim", "pulse")
    s.Refresh(600, 200)
    local part = s.flare.parts[1]
    clientHides(s.frame, { part.live, part.embers, part.beat })
    s.frame:Show()
    T.truthy(part.live:IsPlaying(), "the flicker plays again")
    T.truthy(part.beat:IsPlaying(), "and Pulse's beat")
end)

T.test("procs look: a one-piece design lays out its hidden right piece without an error", function()
    local ns = load()
    for _, design in ipairs({ "ring", "wings", "ring" }) do
        local f = show(ns, design, "breathe")
        settle()
        T.truthy(f.parts[1].frame:IsShown(), design .. ": shows")
        ns.Flares.Layout(f)
    end
end)

T.test("procs look: Embers off: a flare sheds none, up, burning or changed while up", function()
    local ns = load()
    ns.Alerts.Set("overpower", "design", "wings")
    ns.Alerts.Set("overpower", "anim", "strike")
    ns.Alerts.Set("overpower", "embers", false)
    ns.Flares.Show("overpower")
    settle()
    local f = ns.Flares.live.overpower
    for _, part in ipairs(f.parts) do
        T.falsy(part.embers:IsPlaying(), "no embers while up")
        T.falsy(part.emberTex:IsShown())
        T.truthy(part.live:IsPlaying(), "the flicker stays")
    end
    ns.Alerts.Set("overpower", "embers", true)
    T.eq(ns.Flares.live.overpower, f, "switched on while up: the same flare")
    for _, part in ipairs(f.parts) do T.truthy(part.embers:IsPlaying(), "embers start") end
    ns.Alerts.Set("overpower", "embers", false)
    for _, part in ipairs(f.parts) do
        T.falsy(part.embers:IsPlaying(), "and stop again")
        T.falsy(part.emberTex:IsShown())
    end
    ns.Flares.Hide("overpower")
    for _, part in ipairs(f.parts) do
        T.falsy(part.embers:IsPlaying(), "none while it burns")
        T.falsy(part.emberTex:IsShown())
    end
end)
