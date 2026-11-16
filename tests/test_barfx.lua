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
    T.eq(strips, 3, "a base, a soft wave and the bar texture over them, between the fill and its overlays")
    cfg.style = "none"
    DUI.Fire("StyleChanged")
    T.isnil(DUI.BarFx.StyleOf(bar), "picking none takes it off")
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

T.test("Tide eases back after a hit, then lets Lua rest", function()
    local DUI, bar, _, read = setup({ style = "tide" })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    DUI.BarFx.Kick(bar, -1)
    for _ = 1, 30 do stub.RunOnUpdate(DUI.BarFx.ticker, 0.1) end
    T.isnil(DUI.BarFx.ticker.__scripts.OnUpdate, "the ticker stops")
    T.eq(DUI.BarFx.Easing(), 0, "nothing left easing")
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

T.test("a style that reacts flares on a hit and lets Lua rest after", function()
    local DUI, bar, cfg, read = setup({ style = "comet", react = true })
    DUI.BarFx.Track(bar, "health", nil, "player", nil, read)
    DUI.BarFx.Kick(bar, -1)
    T.eq(DUI.BarFx.StyleOf(bar), "comet")
end)

T.test("by power type picks a style per power", function()
    local DUI, bar, cfg, read = setup({ style = "auto" })
    DUI.BarFx.Track(bar, "power", nil, "player", nil, read)
    DUI.BarFx.SetPower(bar, "RAGE")
    T.eq(DUI.BarFx.StyleOf(bar), "embers")
    DUI.BarFx.SetPower(bar, "MANA")
    T.eq(DUI.BarFx.StyleOf(bar), "liquid")
end)
