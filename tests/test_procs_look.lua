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

-- Every loop a part can play, by its field name.
local LOOPS = { "breathe", "pulse", "echo", "swell", "glint" }

local function playing(part)
    local on = {}
    for _, name in ipairs(LOOPS) do
        if part[name] and part[name]:IsPlaying() then on[#on + 1] = name end
    end
    return table.concat(on, "+")
end

T.test("procs look: each animation keeps moving its own way, and a hide stops it", function()
    local ns = load()
    ns.Alerts.Set("overpower", "design", "wings")
    local seen = {}
    for _, anim in ipairs({ "breathe", "pulse", "impact", "flash" }) do
        ns.Alerts.Set("overpower", "anim", anim)
        ns.Flares.Show("overpower")
        local f = ns.Flares.live.overpower
        for i = 1, 2 do
            local part = f.parts[i]
            local on = playing(part)
            T.truthy(on ~= "", anim .. " plays a loop")
            if i == 1 then
                T.falsy(seen[on], anim .. " looks like " .. tostring(seen[on]))
                seen[on] = anim
            end
            -- A one-shot stops moving a moment after it shows: every group loops.
            for _, name in ipairs(LOOPS) do
                if part[name] and part[name]:IsPlaying() then
                    T.truthy(part[name].__looping == "REPEAT" or part[name].__looping == "BOUNCE", anim .. " " .. name .. " loops")
                end
            end
        end
        ns.Flares.Hide("overpower", true)
        for _, part in ipairs(f.parts) do T.eq(playing(part), "", anim .. " stops") end
    end
end)

T.test("procs look: the shockwave and glint copies follow the flare's art, colors and drain", function()
    local ns = load()
    ns.Alerts.Set("overpower", "design", "wings")
    ns.Flares.Show("overpower", { left = 2.5, dur = 5 })
    local f = ns.Flares.live.overpower
    f.frac = 0.5
    ns.Flares.Cut(f, f.parts[2], 2)
    local part = f.parts[2]
    T.eq(part.echoTex:GetTexture(), part.tex:GetTexture(), "the shockwave is the light")
    T.eq(part.glintTex:GetTexture(), part.core:GetTexture(), "the glint is the core")
    T.near(part.echoTex:GetHeight(), part.tex:GetHeight(), 0.01, "shortened with the drain")
    T.near(part.glintTex:GetHeight(), part.core:GetHeight(), 0.01)
    T.deq({ part.echoTex:GetTexCoord() }, { part.tex:GetTexCoord() }, "mirrored like the light")
    T.near(part.echoFrame:GetAlpha(), 0, 0.001, "hidden between waves")
    T.near(part.glintFrame:GetAlpha(), 0, 0.001, "hidden between glints")
end)

T.test("procs look: a flare fades in and out, and its frame is reused", function()
    local ns = load()
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

local function run(seconds)
    local d = DaylightUI.Motion.Driver()
    local n = math.floor(seconds / 0.05 + 0.5)
    for _ = 1, n do
        stub.Advance(0.05)
        stub.RunOnUpdate(d, 0.05)
    end
end

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
