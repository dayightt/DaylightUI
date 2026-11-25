local stub = require("stub")

-- Proc Alerts' options (DaylightUI_Procs/Options.lua): one page edits the
-- picked proc's own look and sound; General holds what applies to every alert.

local function load(opts)
    opts = opts or {}
    stub.Load({ procs = true, before = function()
        if opts.saved then _G.DaylightUIDB = opts.saved end
        stub.SetUnits({ player = { name = "Me", class = opts.class or "WARRIOR", isPlayer = true } })
    end })
    return stub.procs
end

local function settle()
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 30) end
end

local function page(id) return DaylightUI.Options.GetPage("Procs." .. id) end

-- The row on the Alerts page with this label.
local function row(label)
    for _, group in ipairs(page("alerts").groups) do
        for _, item in ipairs(group.items) do
            if item.label == label then return item end
        end
    end
    error("no row " .. label)
end

local function pick(key) row("Alert").set(key) end

T.test("procs options: every row on the Alerts page has a default and passes Options.Validate", function()
    load()
    local Options = DaylightUI.Options
    for _, id in ipairs({ "alerts", "general" }) do
        local p = page(id)
        T.truthy(p, id .. " page")
        T.eq(#Options.ValidatePage(p), 0, id .. ": " .. table.concat(Options.ValidatePage(p), "; "))
    end
    for _, group in ipairs(page("alerts").groups) do
        for _, item in ipairs(group.items) do
            if item.get and item.label ~= "Alert" then
                T.truthy(item.default, item.label .. " has a default")
                T.truthy(item.default() ~= nil, item.label .. " default is a value")
            end
            if item.type ~= "text" then T.truthy(type(item.desc) == "string" and item.desc ~= "", item.label .. " has a description") end
        end
    end
    T.eq(row("Alert").get(), "overpower", "a warrior edits Overpower first")
    local values, order, titles = row("Alert").choices()
    T.eq(order[1], "overpower")
    local head
    for _, k in ipairs(order) do if titles[k] then head = k end end
    T.truthy(head, "a heading before the gear procs")
    T.isnil(values.clearcasting, "only the player's class")
    T.truthy(values.edward, "the gear procs too")
end)

T.test("procs options: size, opacity, colors, design, place apply to that proc only", function()
    local ns = load()
    ns.Flares.Show("overpower")
    ns.Flares.Show("revenge")
    settle()
    pick("overpower")
    row("Size").set(1.5)
    row("Opacity").set(0.5)
    row("Colors").set("custom")
    row("Top color").set({ 0.1, 0.9, 0.2 })
    row("Move sideways").set(20)
    row("Move up").set(30)
    settle()
    local a, b = ns.Flares.live.overpower, ns.Flares.live.revenge
    T.near(a.parts[1].frame:GetWidth(), 256 * 1.5, 0.01, "this one bigger")
    T.near(b.parts[1].frame:GetWidth(), 160, 0.01, "the other untouched")
    T.near(a:GetAlpha(), 0.5, 0.001)
    T.near(b:GetAlpha(), 1, 0.001)
    local g = a.parts[1].tex.__gradient
    T.rgb({ g[3].r, g[3].g, g[3].b }, { 0.1, 0.9, 0.2 }, "its top color")
    local h = b.parts[1].tex.__gradient
    T.falsy(math.abs(h[3].g - 0.9) < 0.01 and math.abs(h[3].r - 0.1) < 0.01, "the other keeps the accent")
    local _, _, _, x, y = a.parts[1].frame:GetPoint(1)
    T.near(x, -84, 0.01, "+X moves both halves outward")
    T.near(y, 40, 0.01)
    _, _, _, x = a.parts[2].frame:GetPoint(1)
    T.near(x, 84, 0.01)
    _, _, _, x, y = b.parts[1].frame:GetPoint(1)
    T.near(y, 104, 0.01, "the other stays put")
    row("Design").set("flames")
    settle()
    T.eq(ns.Flares.live.overpower.design, "flames", "a design change shows at once")
    T.eq(ns.Flares.live.revenge.design, "crown")
end)

T.test("procs options: each proc's animation can be changed and the flare restarts with it", function()
    local ns = load()
    pick("overpower")
    ns.Flares.Show("overpower")
    T.truthy(ns.Flares.live.overpower.parts[1].impact:IsPlaying(), "Overpower lands with Impact")
    for _, anim in ipairs({ "pulse", "breathe", "still" }) do
        row("Animation").set(anim)
        local f = ns.Flares.live.overpower
        T.eq(f.anim, anim)
        local part = f.parts[1]
        T.eq(part.pulse:IsPlaying(), anim == "pulse", anim .. " pulse")
        T.eq(part.breathe:IsPlaying(), anim == "breathe", anim .. " breathe")
        T.falsy(part.impact:IsPlaying(), anim .. " no impact")
    end
end)

T.test("procs options: a proc plays its chosen sound once when it lands, none when set to None", function()
    local ns = load()
    local played = {}
    local real = DaylightUI.Sound.Alert
    DaylightUI.Sound.Alert = function(key) played[#played + 1] = key end
    ns.Flares.Show("overpower")
    ns.Flares.Show("overpower")
    T.deq(played, { "file:568016" }, "once, the game's proc sound")
    ns.Flares.Hide("overpower", true)
    pick("overpower")
    row("Sound").set("none")
    ns.Flares.Show("overpower")
    T.eq(#played, 1, "None plays nothing")
    ns.Flares.Hide("overpower", true)
    row("Sound").set("dui:chime")
    DaylightUI:Set("Procs", "soundOn", false)
    ns.Flares.Show("overpower")
    T.eq(#played, 1, "Alert sounds off plays nothing")
    DaylightUI.Sound.Alert = real
end)

T.test("procs options: the custom colors show only for Two colors of my own", function()
    load()
    local Options = DaylightUI.Options
    pick("overpower")
    local p = page("alerts")
    T.truthy(Options.IsHidden(p, row("Top color")))
    T.truthy(Options.IsHidden(p, row("Bottom color")))
    row("Colors").set("class")
    T.truthy(Options.IsHidden(p, row("Top color")))
    row("Colors").set("custom")
    T.falsy(Options.IsHidden(p, row("Top color")))
    T.falsy(Options.IsHidden(p, row("Bottom color")))
    pick("revenge")
    T.truthy(Options.IsHidden(p, row("Top color")), "each proc its own")
end)

T.test("procs options: the stack and drain rows show only where they mean something", function()
    load({ class = "MAGE" })
    local Options = DaylightUI.Options
    local p = page("alerts")
    pick("hotstreak")
    T.falsy(Options.IsHidden(p, row("Show from")), "Heating Up stacks")
    T.eq(row("Show from").default(), 3, "from its most stacks")
    pick("clearcasting")
    T.truthy(Options.IsHidden(p, row("Show from")))
    T.falsy(Options.IsHidden(p, row("Drain as time runs out")))
    pick("fingers")
    T.truthy(Options.IsHidden(p, row("Drain as time runs out")), "no timer, no drain")
end)

T.test("procs options: copy to my other alerts copies the look but keeps each design", function()
    local ns = load()
    pick("overpower")
    row("Animation").set("breathe")
    row("Size").set(1.25)
    row("Colors").set("class")
    row("Sound").set("none")
    row("Copy this look to my other alerts").func()
    for _, p in ipairs(ns.Data.Mine()) do
        T.eq(ns.Alerts.Get(p.key, "anim"), "breathe", p.key)
        T.eq(ns.Alerts.Get(p.key, "size"), 1.25, p.key)
        T.eq(ns.Alerts.Get(p.key, "colorMode"), "class", p.key)
        T.eq(ns.Alerts.Get(p.key, "sound"), "none", p.key)
        T.eq(ns.Alerts.Get(p.key, "design"), p.design, p.key .. " keeps its design")
    end
    row("Reset this alert").func()
    T.eq(ns.Alerts.Get("overpower", "anim"), "impact", "reset goes back to the proc's own")
    T.eq(ns.Alerts.Get("revenge", "anim"), "breathe", "only that one")
end)

T.test("procs options: a profile switch rebuilds every flare from the new settings", function()
    local ns = load()
    ns.Alerts.Set("overpower", "design", "wings")
    local saved = _G.DaylightUIDB
    local key = DaylightUI.DB.CharKey()
    saved.profileData.Other = { modules = { Procs = { scale = 1.5, alerts = { overpower = { design = "sun", alpha = 0.4 } } } } }
    saved.characters[key].profile = "Other"
    ns = load({ saved = saved })
    T.eq(DaylightUI.DB.ActiveName(), "Other")
    ns.Flares.Show("overpower")
    settle()
    local f = ns.Flares.live.overpower
    T.eq(f.design, "sun")
    T.near(f.parts[1].frame:GetWidth(), 208 * 1.5, 0.01, "the profile's size for every alert")
    T.near(f:GetAlpha(), 0.4, 0.001)
end)

T.test("procs options: the test part shows the selected proc's flare and hides it when test mode ends", function()
    local ns = load()
    pick("revenge")
    DaylightUI.SetTestMode(true)
    T.truthy(ns.Flares.Shown("revenge"), "the picked proc")
    T.falsy(ns.Flares.Shown("overpower"))
    DaylightUI.SetTestMode(false)
    settle()
    T.falsy(ns.Flares.Shown("revenge"))
end)

T.test("procs options: Show it now shows the picked flare for ten seconds", function()
    local ns = load()
    pick("execute")
    row("Show it now").func()
    T.truthy(ns.Flares.Shown("execute"))
    stub.RunTimers()
    T.falsy(ns.Flares.Shown("execute"), "gone after its time")
end)

T.test("procs options: the General page's size, opacity and switch reach every alert", function()
    local ns = load()
    ns.Flares.Show("overpower")
    settle()
    DaylightUI:Set("Procs", "scale", 2)
    DaylightUI:Set("Procs", "alpha", 0.5)
    settle()
    local f = ns.Flares.live.overpower
    T.near(f.parts[1].frame:GetWidth(), 512, 0.01)
    local _, _, _, x = f.parts[1].frame:GetPoint(1)
    T.near(x, -128, 0.01, "the gap grows with it")
    T.near(f:GetAlpha(), 0.5, 0.001)
    DaylightUI:Set("Procs", "enabled", false)
    settle()
    T.falsy(ns.Flares.Shown("overpower"), "off hides every flare")
    ns.Flares.Show("overpower")
    T.falsy(ns.Flares.Shown("overpower"), "and shows none")
end)
