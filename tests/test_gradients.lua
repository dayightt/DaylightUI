local stub = require("stub")

T.test("players get their class pair, others their reaction's", function()
    local DUI = stub.Load()
    stub.SetUnits({
        player = { isPlayer = true, class = "MAGE" },
        target = { isPlayer = false, reaction = 2 },
        focus = { isPlayer = false, reaction = 4 },
        pet = { isPlayer = false, reaction = 5 },
        mouseover = { isPlayer = false, reaction = 2, tapped = true },
    })
    local G = DUI.Gradients
    T.eq(G.KeyFor("player"), "MAGE")
    T.eq(G.KeyFor("target"), "HOSTILE")
    T.eq(G.KeyFor("focus"), "NEUTRAL")
    T.eq(G.KeyFor("pet"), "FRIENDLY")
    T.eq(G.KeyFor("mouseover"), "TAPPED")
end)

T.test("secret, unknown or missing answers fall back", function()
    local DUI = stub.Load()
    stub.SetUnits({
        player = { isPlayer = true, class = stub.Secret("MAGE") },
        target = { isPlayer = false, reaction = stub.Secret(2) },
        focus = { isPlayer = true, class = "NOPE" },
        pet = { isPlayer = stub.Secret(true) },
    })
    local G = DUI.Gradients
    T.eq(G.KeyFor("player"), "FALLBACK", "secret class")
    T.eq(G.KeyFor("target"), "FALLBACK", "secret reaction")
    T.eq(G.KeyFor("focus"), "FALLBACK", "unknown class")
    T.eq(G.KeyFor("pet"), "FALLBACK", "secret player check")
    T.eq(G.KeyFor(nil), "FALLBACK", "no unit")
end)

T.test("your colors replace one end of a pair", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    local lo, hi = G.RGB("ROGUE")
    DUI:Set("general", "gradients.colors.ROGUE.hi", { 0, 0, 1 })
    local lo2, hi2 = G.RGB("ROGUE")
    T.deq(lo2, lo, "untouched end keeps the default")
    T.deq(hi2, { 0, 0, 1 })
    T.truthy(hi ~= hi2)
    local _, c = G.Colors("ROGUE")
    T.rgb({ c.r, c.g, c.b }, { DUI.Style.Soften(0, 0, 1) }, "the cache follows the change")
end)

T.test("invert swaps the pair; orientation defaults to horizontal", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    local a, b = G.Colors("DRUID")
    DUI:Set("general", "gradients.invert", true)
    local c, d = G.Colors("DRUID")
    T.deq(c, b); T.deq(d, a)
    T.eq(G.Orientation(), "HORIZONTAL")
    DUI:Set("general", "gradients.orientation", "BOGUS")
    T.eq(G.Orientation(), "HORIZONTAL", "an unknown value is ignored")
end)

T.test("Paint puts the gradient on the fill after the bar's color", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    local bar = DUI.Style.Bar(UIParent)
    local backed
    G.Paint(bar, "WARRIOR", function(_, r, g, b) backed = { r, g, b } end)
    T.rgb(backed, { G.Mid("WARRIOR") }, "the empty part in the pair's middle")
    local grad = bar:GetStatusBarTexture().__gradient
    T.truthy(grad, "gradient set")
    local lo, hi = G.Colors("WARRIOR")
    T.eq(grad[1], "HORIZONTAL"); T.eq(grad[2], lo); T.eq(grad[3], hi)
end)

T.test("new kinds register into their own group", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    G.Register("INTERRUPTIBLE", { group = "sample", label = "Interruptible", lo = { 0, 0, 0.5 }, hi = { 0, 0.5, 1 } })
    T.deq(G.Keys("sample"), { "INTERRUPTIBLE" })
    T.truthy(#G.Keys("class") >= 9)
    T.eq(G.Label("INTERRUPTIBLE"), "Interruptible")
end)

T.test("SetPair keeps only the ends you changed", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    local d = G.Default("MAGE")
    G.SetPair("MAGE", d.lo, { 1, 0, 0 })
    local saved = DUI:Get("general", "gradients.colors.MAGE")
    T.falsy(saved.lo, "the untouched end isn't stored")
    T.deq(saved.hi, { 1, 0, 0 })
    T.truthy(G.AnyChanged())
    G.SetPair("MAGE", d.lo, d.hi)
    T.eq(DUI:Get("general", "gradients.colors.MAGE"), nil, "back to default leaves nothing")
    T.falsy(G.AnyChanged())
end)

local function gradientRow(pf, label)
    for _, card in ipairs(pf.cards) do
        for _, row in ipairs(card.rows) do
            if row.item.type == "gradient" and row.item.label == label then return row end
        end
    end
end

T.test("the Gradients page: a row per pair, swatches, resets", function()
    local DUI = stub.Load()
    local G, O = DUI.Gradients, DUI.Options
    local page = O.GetPage("gradients")
    T.truthy(page, "page registered")
    T.eq(#O.ValidatePage(page), 0)
    T.eq(#page.groups, 1 + #G.GROUPS, "settings card, then one per group")
    T.eq(#page.groups[2].items, #G.Keys("class") - 4, "not the four classes this client has not got")

    local picked
    _G.ColorPickerFrame = { SetupColorPickerAndShow = function(_, info) picked = info end,
                            GetColorRGB = function() return 0.1, 0.2, 0.3 end }
    DUI.OptionsPanel.Show("gradients")
    local row = gradientRow(DUI.OptionsPanel.PageFrame(), "Rogue")
    T.truthy(row, "a Rogue row")
    T.falsy(row.reset:IsShown(), "no reset arrow at default")
    row.control.hi:GetScript("OnClick")()
    picked.swatchFunc()
    local lo, hi = G.RGB("ROGUE")
    T.deq(hi, { 0.1, 0.2, 0.3 }, "the light end is the picked color")
    T.deq(lo, G.Default("ROGUE").lo, "the dark end is untouched")
    row.Refresh()
    T.truthy(row.reset:IsShown(), "reset arrow once changed")
    T.truthy(row.control.preview.__gradient, "the preview is painted")

    -- Dragged round the wheel, each move only paints the swatch. Saving a General
    -- setting repaints the whole UI, so doing it once a frame during the drag caused
    -- big frame drops. The pick is saved once, on release.
    local W, oldDown, held = DUI.Widgets, _G.IsMouseButtonDown, true
    _G.IsMouseButtonDown = function() return held end
    local saves = 0
    DUI.On("SettingChanged", function(_, path) if path:find("ROGUE", 1, true) then saves = saves + 1 end end)
    row.control.hi:GetScript("OnClick")()
    _G.ColorPickerFrame.GetColorRGB = function() return 0.4, 0.5, 0.6 end
    picked.swatchFunc(); picked.swatchFunc(); picked.swatchFunc()
    T.eq(saves, 0, "nothing saved while the wheel is held")
    T.deq({ row.control.hi.fill:GetVertexColor() }, { 0.4, 0.5, 0.6, 1 }, "the swatch follows the drag")
    stub.RunOnUpdate(W.colorWait, 0.016)
    T.eq(saves, 0, "still held: still not saved")
    held = false
    stub.RunOnUpdate(W.colorWait, 0.016)
    T.eq(saves, 1, "saved once, on release")
    T.deq(select(2, G.RGB("ROGUE")), { 0.4, 0.5, 0.6 }, "the dragged color")
    T.falsy(W.colorWait:GetScript("OnUpdate"), "the wait stops once saved")
    -- Escape mid-drag puts the starting color back; the release then saves nothing.
    held = true
    row.control.hi:GetScript("OnClick")()
    _G.ColorPickerFrame.GetColorRGB = function() return 0.9, 0.9, 0.9 end
    picked.swatchFunc()
    picked.cancelFunc()
    held = false
    stub.RunOnUpdate(W.colorWait, 0.016)
    T.deq(select(2, G.RGB("ROGUE")), { 0.4, 0.5, 0.6 }, "cancel kept the color it opened on")
    _G.IsMouseButtonDown = oldDown
    _G.ColorPickerFrame.GetColorRGB = function() return 0.1, 0.2, 0.3 end

    O.ResetItem(page, row.item)
    T.eq(DUI:Get("general", "gradients.colors.ROGUE"), nil, "reset one")

    G.SetPair("DRUID", { 0, 0, 0 }, { 1, 1, 1 })
    DUI:Set("general", "gradients.invert", true)
    local palette = page.groups[1].items[2]
    T.eq(palette.key, "gradients.palette", "the palette dropdown comes after the switch")
    T.eq(palette.values.classcolor, "Game class colors")
    local resetAll = page.groups[1].items[5]
    T.falsy(resetAll.disabled())
    resetAll.func()
    T.falsy(G.AnyChanged(), "reset all colors")
    T.truthy(DUI:Get("general", "gradients.invert"), "invert stays")
    T.truthy(resetAll.disabled(), "nothing left to reset")

    G.SetPair("DRUID", { 0, 0, 0 }, { 1, 1, 1 })
    O.ResetPage(page)
    T.falsy(G.AnyChanged(), "page reset clears the pairs")
    T.falsy(DUI:Get("general", "gradients.invert"), "and the painting settings")
    DUI:Set("general", "gradients.palette", "soft")
    O.ResetPage(page)
    T.eq(G.Palette(), "daylight", "page reset puts the palette back")
    T.eq(#stub.errors, 0)
end)

T.test("power types get their own pair; secret or unknown ones mana's", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    T.eq(G.PowerKey("RAGE"), "RAGE")
    T.eq(G.PowerKey("FOCUS"), "FOCUS")
    T.eq(G.PowerKey("RUNIC_POWER"), "MANA", "no pair for it")
    T.eq(G.PowerKey("WARRIOR"), "MANA", "a class isn't a power")
    T.eq(G.PowerKey(stub.Secret("RAGE")), "MANA", "secret")
    T.eq(G.PowerKey(nil), "MANA")
    T.eq(#G.Keys("power"), 4)
end)

T.test("palettes: daylight by default, unknown ids ignored", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    T.eq(G.Palette(), "daylight")
    T.deq(G.PALETTE_ORDER, { "daylight", "classcolor", "soft" })
    T.eq(G.PaletteValues().soft, "Soft")
    DUI:Set("general", "gradients.palette", "BOGUS")
    T.eq(G.Palette(), "daylight", "an unknown palette is ignored")
    T.deq(G.Default("ROGUE").lo, { 0.70, 0.40, 0.00 }, "daylight is the shipped pairs")
end)

T.test("the game class colors palette builds class pairs from RAID_CLASS_COLORS", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    DUI:Set("general", "gradients.palette", "classcolor")
    local lo, hi = G.RGB("MAGE")
    T.rgb(lo, { 0.1125, 0.351, 0.414 }, "dark end")
    T.rgb(hi, { 0.4375, 0.835, 0.94 }, "light end")
    T.deq((G.RGB("WARRIOR")), { 0.35, 0.16, 0.08 }, "no game color: shipped pair")
    T.deq((G.RGB("HOSTILE")), { 0.42, 0.04, 0.04 }, "not a class: shipped pair")
end)

T.test("the soft palette washes every pair out, and the cache follows it", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    G.Colors("ROGUE")
    DUI:Set("general", "gradients.palette", "soft")
    local lo, hi = G.RGB("ROGUE")
    T.rgb(lo, { 0.64, 0.43, 0.15 })
    T.rgb(hi, { 1, 0.9675, 0.6425 })
    local _, c = G.Colors("ROGUE")
    T.rgb({ c.r, c.g, c.b }, { DUI.Style.Soften(1, 0.9675, 0.6425) }, "cache rebuilt")
end)

T.test("a palette's own set wins; your changes sit on top and survive a switch", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    G.RegisterPalette("test", { label = "Test", set = { MAGE = { lo = { 0, 0, 0 }, hi = { 1, 1, 1 } } } })
    DUI:Set("general", "gradients.palette", "test")
    local lo, hi = G.RGB("MAGE")
    T.deq(lo, { 0, 0, 0 }); T.deq(hi, { 1, 1, 1 })
    T.deq(G.Default("MAGE").hi, { 1, 1, 1 }, "reset goes to the palette's pair")
    G.SetPair("MAGE", { 0, 0, 0 }, { 1, 0, 0 })
    local saved = DUI:Get("general", "gradients.colors.MAGE")
    T.falsy(saved.lo, "same as the palette: not stored")
    T.deq(saved.hi, { 1, 0, 0 })
    DUI:Set("general", "gradients.palette", "daylight")
    lo, hi = G.RGB("MAGE")
    T.deq(hi, { 1, 0, 0 }, "your change survives the switch")
    T.deq(lo, { 0.02, 0.22, 0.50 }, "the other end is daylight's")
end)

T.test("swing and cast pairs: a queued attack and an interrupt have their own", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    T.deq(G.Keys("swing"), { "SWING_MAIN", "SWING_OFF", "SWING_RANGED", "SWING_QUEUED" })
    T.deq(G.Keys("cast"), { "CAST", "CHANNEL", "CAST_INTERRUPTED", "CAST_LOCKED" })
end)

T.test("every palette has its own swing and cast pairs", function()
    local DUI = stub.Load()
    local G = DUI.Gradients
    local keys = { "SWING_MAIN", "SWING_OFF", "SWING_RANGED", "SWING_QUEUED", "CAST", "CHANNEL", "CAST_INTERRUPTED", "CAST_LOCKED" }
    local daylight = {}
    for _, key in ipairs(keys) do daylight[key] = G.Default(key) end
    for _, id in ipairs({ "classcolor", "soft" }) do
        DUI:Set("general", "gradients.palette", id)
        for _, key in ipairs(keys) do
            local p = G.Default(key)
            T.truthy(p.lo[1] ~= daylight[key].lo[1] or p.hi[1] ~= daylight[key].hi[1]
                  or p.lo[2] ~= daylight[key].lo[2] or p.hi[3] ~= daylight[key].hi[3], id .. " " .. key)
        end
    end
end)

T.test("raw pairs: made from a color, painted softened in the chosen direction", function()
    local DUI = stub.Load()
    local G, Style = DUI.Gradients, DUI.Style
    local lo, hi = G.PairFrom({ 0.8, 0.4, 0.2 })
    T.near(lo[1], 0.8 * G.FROM_DIM, 1e-9); T.near(lo[3], 0.2 * G.FROM_DIM, 1e-9)
    T.near(hi[1], 0.8, 1e-9); T.near(hi[2], 0.4, 1e-9)

    local lr = Style.Soften(lo[1], lo[2], lo[3])
    local hr = Style.Soften(hi[1], hi[2], hi[3])
    local mr = G.MidOf(lo, hi)
    T.near(mr, (lr + hr) / 2, 1e-9, "the softened middle")

    local tex = CreateFrame("Frame"):CreateTexture()
    G.PaintPair(tex, lo, hi)
    T.deq(tex.__vertex, { 1, 1, 1, 1 }, "white under the gradient")
    T.eq(tex.__gradient[1], G.Orientation())
    T.near(tex.__gradient[2].r, lr, 1e-9, "dark end first")
    T.near(tex.__gradient[3].r, hr, 1e-9)

    DUI:Set("general", "gradients.invert", true)
    local a, b = G.PaintRGBOf(lo, hi)
    T.near(a[1], hr, 1e-9, "invert: light end first"); T.near(b[1], lr, 1e-9)
    G.PaintPair(tex, lo, hi)
    T.near(tex.__gradient[2].r, hr, 1e-9)
end)

T.test("gradients off: every pair, the accent and the bar sweep paint one flat color", function()
    local DUI = stub.Load()
    stub.SetUnits({ player = { isPlayer = true, class = "MAGE" } })
    local G, Style = DUI.Gradients, DUI.Style
    DUI:Set("general", "accent", "classGradient")
    local rawLo, rawHi = G.RGB("DRUID")
    T.truthy(Style.AccentSweep(), "on: the class gradient accent sweeps")

    DUI:Set("general", "gradients.off", true)
    T.truthy(G.Flat())
    local a, b = G.Colors("DRUID")
    T.deq({ a.r, a.g, a.b }, { b.r, b.g, b.b }, "a pair's two ends are one color")
    local mr, mg, mb = G.Mid("DRUID")
    T.rgb({ a.r, a.g, a.b }, { mr, mg, mb }, "its middle")
    T.deq({ G.RGB("DRUID") }, { rawLo, rawHi }, "the saved pair itself is kept")

    local lo, hi = G.PairFrom({ 0.8, 0.4, 0.2 })
    T.deq(lo, { 0.8, 0.4, 0.2 }); T.deq(hi, { 0.8, 0.4, 0.2 }, "one color stays itself")
    local p, q = G.PaintRGBOf({ 0, 0, 0 }, { 1, 1, 1 })
    T.deq(p, q, "a raw pair paints its middle")

    T.eq(Style.AccentSweep(), nil, "the accent is one color")
    T.eq(Style.AccentPair(), nil)
    T.rgb({ Style.AccentAt(0) }, { Style.Accent() }, "a list runs in the one accent")

    local bar = Style.Bar(CreateFrame("Frame"))
    T.eq(Style.SetBarGradient(bar, true), false, "no Daylight sweep")
    T.rgb(bar.__barColor, { Style.FlatSweep() }, "the bar is the sweep's middle, not white")

    DUI:Set("general", "gradients.off", false)
    T.eq(Style.SetBarGradient(bar, true), true, "back on")
    T.truthy(Style.AccentSweep())
end)

T.test("gradients off: the Gradients page's switch, the rows that stop mattering dimmed", function()
    local DUI = stub.Load()
    local page = DUI.Options.GetPage("gradients")
    local items = page.groups[1].items
    T.eq(items[1].key, "gradients.off")
    T.eq(items[1].invert, true, "shown as Gradients on")
    T.eq(DUI.Options.Get(page, items[1]), true)
    DUI:Set("general", "gradients.off", true)
    T.eq(DUI.Options.Get(page, items[1]), false)
    for _, it in ipairs(items) do
        if it.key == "gradients.orientation" or it.key == "gradients.invert" then
            T.eq(it.disabled(), true, it.key)
        end
    end
end)
