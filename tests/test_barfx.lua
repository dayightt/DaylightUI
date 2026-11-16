local stub = require("stub")

-- Bar styles (BarFx.lua): a living fill that follows General's picks, built
-- only when a style is picked, and never reading the bar's value.

local function setup()
    local DUI = stub.Load({})
    local Style = DUI.Style
    local bar = Style.Bar(UIParent)
    bar:SetSize(200, 20)
    Style.AngleFill(bar, "right", 8)
    DUI.Gradients.PaintUnit(bar, "player")
    return DUI, bar
end

T.test("a new setup starts in Flow; None takes it off", function()
    local DUI, bar = setup()
    DUI.BarFx.Track(bar, "health", nil, "player")
    T.eq(DUI.BarFx.StyleOf(bar), "flow", "a brand-new account's first profile")
    DUI:Set("general", "barFx.health.style", "none")
    DUI.Fire("StyleChanged")
    T.isnil(DUI.BarFx.StyleOf(bar))
end)

T.test("a profile from before bar styles keeps its bars still", function()
    local DUI = stub.Load({ before = function()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { general = {}, modules = {}, positions = {} } } }
    end })
    T.eq(DUI:Get("general", "barFx.health.style"), "none")
end)

T.test("Flow rolls the bar's own colors on a loop the client runs", function()
    local DUI, bar = setup()
    DUI:Set("general", "barFx.health.style", "flow")
    DUI.BarFx.Track(bar, "health", nil, "player")
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
    DUI:Set("general", "barFx.health.style", "none")
    DUI.Fire("StyleChanged")
    T.isnil(DUI.BarFx.StyleOf(bar), "picking none takes it off")
end)

T.test("motion off stills every bar style", function()
    local DUI, bar = setup()
    DUI:Set("general", "barFx.health.style", "flow")
    DUI:Set("general", "motion", false)
    DUI.BarFx.Track(bar, "health", nil, "player")
    T.isnil(DUI.BarFx.StyleOf(bar))
end)

T.test("plates and raid tiles wait for their own switch", function()
    local DUI, bar = setup()
    DUI:Set("general", "barFx.health.style", "flow")
    DUI.BarFx.Track(bar, "health", "plate", "nameplate1")
    T.isnil(DUI.BarFx.StyleOf(bar))
    DUI:Set("general", "barFx.plates", true)
    DUI.Fire("StyleChanged")
    T.eq(DUI.BarFx.StyleOf(bar), "flow")
end)

T.test("a fill with secret colors keeps its plain look", function()
    local DUI, bar = setup()
    DUI:Set("general", "barFx.health.style", "flow")
    DUI.BarFx.Track(bar, "health", nil, "player")
    local s = stub.Secret(0.5)
    DUI.Style.NoteFillRGB(bar:GetStatusBarTexture(), s, s, s)
    T.isnil(DUI.Style.FillColors(bar:GetStatusBarTexture()), "secret colors aren't kept")
end)

T.test("power by type picks per power and follows a change", function()
    local DUI, bar = setup()
    DUI:Set("general", "barFx.power.style", "auto")
    DUI.BarFx.Track(bar, "power", nil, "player")
    DUI.BarFx.SetPower(bar, "MANA")
    T.eq(DUI.BarFx.StyleOf(bar), DUI.BarFx.AUTO.MANA)
end)

T.test("custom colors and strength paint the strips", function()
    local DUI, bar = setup()
    DUI:Set("general", "barFx.health.style", "flow")
    DUI:Set("general", "barFx.health.colors", "custom")
    DUI:Set("general", "barFx.health.colorA", { 1, 0, 0 })
    DUI:Set("general", "barFx.health.strength", 0.5)
    DUI.BarFx.Track(bar, "health", nil, "player")
    local lo = DUI.BarFx.Colors({ bar = bar, kind = "health" })
    T.eq(lo[1], 1)
    T.eq(DUI.BarFx.StyleOf(bar), "flow")
end)

T.test("Tide eases back after a hit, then lets Lua rest", function()
    local DUI, bar = setup()
    DUI:Set("general", "barFx.health.style", "tide")
    DUI.BarFx.Track(bar, "health", nil, "player")
    DUI.BarFx.Kick(bar, -1)
    for _ = 1, 30 do stub.RunOnUpdate(DUI.BarFx.ticker, 0.1) end
    T.isnil(DUI.BarFx.ticker.__scripts.OnUpdate, "the ticker stops")
    T.eq(DUI.BarFx.Easing(), 0, "nothing left easing")
end)

local function upgrader()
    return stub.Load({ before = function()
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
    for _, kind in ipairs(DUI.BarFx.KINDS) do
        T.eq(DUI:Get("general", "barFx." .. kind .. ".style"), "flow", kind)
    end
    T.falsy(DUI.BarFx.ShouldAsk(), "never again")
end)

T.test("Not now keeps the bars still and doesn't ask again", function()
    local DUI = upgrader()
    stub.Dismiss()
    DUI.BarFx.Ask()
    stub.Answer(false)
    T.eq(DUI:Get("general", "barFx.health.style"), "none")
    T.falsy(DUI.BarFx.ShouldAsk())
end)

T.test("a brand-new account isn't asked: its setup starts with them on", function()
    local DUI = stub.Load({})
    T.falsy(DUI.BarFx.ShouldAsk())
end)

T.test("a Daylight sweep bar flows its own sweep, never plain white", function()
    local DUI = stub.Load({})
    local Style = DUI.Style
    local bar = Style.Bar(UIParent)
    bar:SetSize(200, 20)
    Style.SetBarGradient(bar, true)
    DUI.BarFx.Track(bar, "health", nil, "player")
    local sweeps = 0
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:GetObjectType() == "Texture" and r.GetTexture and r:GetTexture() == DUI.BarFx.SWEEP then sweeps = sweeps + 1 end
    end
    T.eq(sweeps, 1, "the sweep's own colors, looped")
end)
