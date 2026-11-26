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
    local count = C_Item.GetItemCount
    C_Item.GetItemCount = function(id) return id == 2243 and 1 or 0 end
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
    C_Item.GetItemCount = count
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
    settle()
    T.truthy(ns.Flares.live.overpower.parts[1].wave:IsPlaying(), "Overpower sends out Impact's wave")
    local own = { pulse = "beat", breathe = "breathe", flash = "gleam" }
    for _, anim in ipairs({ "pulse", "breathe", "flash", "strike", "still" }) do
        row("Animation").set(anim)
        settle()
        local f = ns.Flares.live.overpower
        T.eq(f.anim, anim)
        local part = f.parts[1]
        for a, name in pairs(own) do T.eq(part[name]:IsPlaying(), a == anim, anim .. ": " .. name) end
        T.falsy(part.wave:IsPlaying(), anim .. ": no wave")
        T.eq(part.live:IsPlaying(), anim ~= "still", anim .. ": the flicker")
    end
end)

T.test("procs options: Strike leads the Animation list; every proc's default is unchanged", function()
    local ns = load()
    T.eq(ns.Data.ANIM_ORDER[1], "strike", "the first choice")
    T.eq(ns.Data.ANIMS.strike.name, "Strike")
    T.eq(ns.Data.ANIM_ORDER[#ns.Data.ANIM_ORDER], "still", "Still stays last")
    local r = row("Animation")
    local order = type(r.order) == "function" and r.order() or r.order
    T.eq(order[1], "strike", "the dropdown lists it first")
    for _, p in ipairs(ns.Data.PROCS) do
        T.truthy(p.anim ~= "strike", p.key .. " keeps its own default")
        T.eq(ns.Alerts.Get(p.key, "anim"), p.anim, p.key)
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
    -- Made since Proc Alerts came out, so the step that starts older profiles
    -- with them off leaves it alone.
    saved.profileData.Other = { procsOff1 = true, modules = { Procs = { scale = 1.5, alerts = { overpower = { design = "sun", alpha = 0.4 } } } } }
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

-- One switch for every alert, where the page opens: without it at the top,
-- turning them off looked like ticking off each proc one by one.
T.test("procs options: the switch for every alert leads the Proc Alerts page, and off dims the rest", function()
    load()
    local Options = DaylightUI.Options
    local p = page("alerts")
    local first = p.groups[1].items[1]
    T.eq(first.key, "enabled", "the first row")
    T.eq(first.type, "toggle")
    T.eq(first.label, "Show proc alerts")
    for _, group in ipairs(page("general").groups) do
        for _, item in ipairs(group.items) do T.falsy(item.key == "enabled", "one place for it") end
    end
    for _, group in ipairs(p.groups) do
        for _, item in ipairs(group.items) do
            if item ~= first then T.falsy(Options.IsDisabled(p, item), tostring(item.label) .. " usable while on") end
        end
    end
    DaylightUI:Set("Procs", "enabled", false)
    for _, group in ipairs(p.groups) do
        for _, item in ipairs(group.items) do
            if item ~= first and item.type ~= "text" then
                T.truthy(Options.IsDisabled(p, item), tostring(item.label) .. " dimmed while every alert is off")
            end
        end
    end
    T.falsy(Options.IsDisabled(p, first), "the switch itself stays usable")
end)

T.test("procs options: the Show button plays the alert's own sound", function()
    local ns = load()
    local played = {}
    local real = DaylightUI.Sound.Alert
    DaylightUI.Sound.Alert = function(key) played[#played + 1] = key end
    pick("overpower")
    row("Show it now").func()
    T.deq(played, { "file:568016" }, "the click shows the flare and plays its sound")
    row("Sound").set("none")
    row("Show it now").func()
    T.eq(#played, 1, "None stays quiet")
    row("Sound").set("dui:chime")
    DaylightUI:Set("Procs", "soundOn", false)
    row("Show it now").func()
    T.eq(#played, 1, "Alert sounds off stays quiet")
    DaylightUI.Sound.Alert = real
end)

T.test("procs options: weapons and enchants are listed only when the character has them", function()
    local I = C_Item
    local count, equipped = I.GetItemCount, I.IsEquippedItem
    local owned = {}
    I.GetItemCount = function(id) return owned[id] or 0 end
    I.IsEquippedItem = function() return false end
    load()
    local values, order, titles = row("Alert").choices()
    T.isnil(values.edward, "no Hand of Edward the Odd: not listed")
    T.isnil(values.revelation, "an enchant Proc Alerts can't see yet: not listed")
    T.isnil(values.insight)
    for _, k in ipairs(order) do T.falsy(titles[k], "no empty Weapons and enchants heading") end
    owned[2243] = 1
    values = row("Alert").choices()
    T.truthy(values.edward, "in the bags or worn: listed")
    I.GetItemCount, I.IsEquippedItem = count, equipped
end)

T.test("procs options: the page's preview shows the picked proc's flare and follows each change", function()
    local ns = load()
    local p = page("alerts")
    T.truthy(p.sample, "the Alerts page has a preview")
    local s = p.sample(UIParent)
    pick("overpower")
    local h = s.Refresh(600, 200)
    T.truthy(h > 0 and h <= 200, "fits the room")
    local tex = s.flare.parts[1].tex
    T.truthy(string.find(tex:GetTexture(), "flare%-" .. ns.Alerts.Get("overpower", "design") .. "%.png$"), "its design")
    row("Design").set("crown")
    s.Refresh(600, 200)
    T.truthy(string.find(tex:GetTexture(), "flare%-crown%.png$"), "a new design shows at once")
    T.falsy(s.flare.parts[2].frame:IsShown(), "a centered design has no right half")
    pick("revenge")
    s.Refresh(600, 200)
    T.eq(s.flare.key, "revenge", "follows the Alert picker")
    T.falsy(ns.Flares.lanes.side and ns.Flares.lanes.side[0] == "revenge", "takes no lane")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("procs options: the Alerts page preview plays the picked animation's loops", function()
    local ns = load()
    local s = page("alerts").sample(UIParent)
    pick("overpower")
    local own = { strike = {}, breathe = { "breathe" }, pulse = { "beat" }, impact = { "wave" }, flash = { "gleam" } }
    for anim, groups in pairs(own) do
        row("Animation").set(anim)
        s.Refresh(600, 200)
        local part = s.flare.parts[1]
        T.truthy(part.live:IsPlaying(), anim .. ": the flicker")
        T.truthy(part.embers:IsPlaying(), anim .. ": the embers")
        T.truthy(part.liveTex:IsShown(), anim .. ": its sheet shows")
        for _, name in ipairs(groups) do T.truthy(part[name]:IsPlaying(), anim .. ": " .. name) end
        T.eq(s.flare.burst.again:IsPlaying(), anim == "impact", anim .. ": Impact's sparks again")
    end
    row("Animation").set("still")
    s.Refresh(600, 200)
    T.falsy(s.flare.parts[1].live:IsPlaying(), "Still: no flicker")
    T.truthy(s.flare.parts[1].tex:IsShown(), "Still: the painting")
end)

T.test("procs options: picking a design or animation shows nothing on screen, only the preview", function()
    local ns = load()
    pick("overpower")
    local design, anim = row("Design"), row("Animation")
    if design.hover then design.hover("crown") end
    T.falsy(ns.Flares.Shown("overpower"), "hovering a design: nothing on screen")
    design.set("wave")
    if design.onPick then design.onPick("wave") end
    T.falsy(ns.Flares.Shown("overpower"), "picking one: nothing on screen")
    anim.set("pulse")
    if anim.onPick then anim.onPick("pulse") end
    T.falsy(ns.Flares.Shown("overpower"), "an animation too")
end)

T.test("procs options: a test flare the engine also showed still goes after a look change", function()
    local ns = load()
    local now, due = 0, {}
    local after = C_Timer.After
    C_Timer.After = function(t, fn) due[#due + 1] = { at = now + t, fn = fn } end
    ns.Flares.Test("overpower")
    ns.Flares.Show("overpower", {})   -- the engine's own update, while the test is up
    ns.Alerts.Set("overpower", "design", "wave")
    stub.RunTimers()
    T.truthy(ns.Flares.live.overpower.test, "still the test's flare after it restarts")
    now = 11
    for i = #due, 1, -1 do if due[i].at <= now then table.remove(due, i).fn() end end
    T.falsy(ns.Flares.Shown("overpower"), "and it goes when the test's time is up")
    C_Timer.After = after
end)

T.test("procs options: Animation speed sits under Animation, dims on Still, and is copied with the look", function()
    local ns = load()
    pick("overpower")
    local r = row("Animation speed")
    T.truthy(r, "the row is there")
    r.set(1.5)
    T.eq(ns.Alerts.Get("overpower", "speed"), 1.5)
    T.falsy(r.disabled(), "on while it moves")
    ns.Alerts.Set("overpower", "anim", "still")
    T.truthy(r.disabled(), "nothing to speed up on Still")
    ns.Alerts.CopyToClass("overpower")
    T.eq(ns.Alerts.Get("revenge", "speed"), 1.5, "copied with the look")
end)

T.test("procs options: Embers sits under Animation speed, on by default, dims on Still, and is copied with the look", function()
    local ns = load()
    pick("overpower")
    local r = row("Embers")
    T.eq(r.type, "toggle")
    T.eq(ns.Alerts.Get("overpower", "embers"), true, "on by default")
    local look
    for _, group in ipairs(page("alerts").groups) do
        for i, item in ipairs(group.items) do
            if item.label == "Animation speed" then look = group.items[i + 1] end
        end
    end
    T.eq(look and look.label, "Embers", "right under Animation speed")
    T.falsy(r.disabled(), "on while it moves")
    r.set(false)
    T.eq(ns.Alerts.Get("overpower", "embers"), false)
    ns.Alerts.CopyToClass("overpower")
    T.eq(ns.Alerts.Get("revenge", "embers"), false, "copied with the look")
    ns.Alerts.Set("overpower", "anim", "still")
    T.truthy(r.disabled(), "no embers on Still")
    ns.Alerts.Set("overpower", "anim", "pulse")
    DaylightUI:Set("general", "motion", false)
    T.truthy(r.disabled(), "none with motion off")
end)
