local stub = require("stub")

-- A hunter's pet, and how it feels.
local function login(mood, hunter, class)
    return stub.Load({ module = true, before = function()
        stub.units.player = { name = "Hunts", isPlayer = true, class = class or "HUNTER" }
        stub.mood = mood
        _G.HasPetUI = function() return true, hunter ~= false end
        _G.C_PetInfo = {
            GetPetHappiness = function() return stub.mood, 125, 1 end,
            GetPetFoodTypes = function() return { "Meat", "Fish" } end,
        }
    end })
end

T.test("pet happiness: a square in the mood's color by default; or the mood face, with the frame's own edge", function()
    local DUI, ns = login(2)
    local h = ns.happiness
    T.truthy(h.fill:IsShown()); T.falsy(h.face:IsShown(), "the square by default: the face blurs at 16 px")
    DUI:Set("UnitFrames", "pet.happinessLook", "icon")
    stub.RunTimers()
    local p, rel, rp = h:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, ns.frames.pet); T.eq(rp, "LEFT")
    T.eq(h:GetWidth(), 16); T.eq(h:GetHeight(), 16)
    T.truthy(h:IsShown())
    T.truthy(h.face:IsShown()); T.falsy(h.fill:IsShown())
    T.eq(h.face.__atlas, "UI-PetNeutral", "content")
    T.isnil(h.face.__texture, "the game's face, not a family strip")
    T.falsy(h.shell:IsShown(), "the mood face has no box")
    local fp = h.face:GetPoint(1)
    T.eq(fp, "ALL", "the face fills its size, with no border inset")
    stub.mood = 1
    stub.FireEvent("UNIT_HAPPINESS", "pet")
    T.eq(h.face.__atlas, "UI-PetMad")
    T.falsy(h.shell:IsShown(), "still no box when unhappy")
    -- The square again, anywhere, any size.
    DUI:Set("UnitFrames", "pet.happinessLook", "square")
    DUI:Set("UnitFrames", "pet.happinessSpot", "above")
    DUI:Set("UnitFrames", "pet.happinessSize", 22)
    stub.RunTimers()
    T.falsy(h.face:IsShown()); T.truthy(h.fill:IsShown())
    local S = DaylightUI.Style
    local c = ns.Happiness.COLORS[1]
    T.rgb(h.fill.__vertex, { S.Soften(c[1], c[2], c[3]) }, "red when unhappy")
    T.truthy(h.shell:IsShown(), "the square keeps its box")
    T.isnil(h.shell.opts.borderColor, "the square keeps the frame's edge")
    T.eq(h:GetWidth(), 22)
    T.eq((h:GetPoint(1)), "BOTTOM", "above the frame")
end)

T.test("pet happiness: the mood face is one face, even when the client hands over the whole sheet", function()
    local DUI, ns = login(2)
    DUI:Set("UnitFrames", "pet.happinessLook", "family")
    stub.RunTimers()
    local h = ns.happiness
    T.truthy(h.fill:IsShown(), "a removed look falls back to the square")
    T.falsy(h.face:IsShown())
    _G.C_Texture = { GetAtlasInfo = function(atlas)
        T.eq(atlas, "UI-PetNeutral")
        return { file = "Interface\\PetPaperDollFrame\\UI-PetHappiness", leftTexCoord = 0, rightTexCoord = 1,
                 topTexCoord = 0, bottomTexCoord = 1 }
    end }
    DUI:Set("UnitFrames", "pet.happinessLook", "icon")
    stub.RunTimers()
    T.eq(h.face.__texture, ns.Happiness.SHEET, "the whole sheet is not the face")
    T.eq(h.face.__texCoord[1], ns.Happiness.SHEET_COORD[2][1])
    T.eq(h.face.__texCoord[2], ns.Happiness.SHEET_COORD[2][2])
    T.falsy(h.shell:IsShown(), "the mood face has no box")
    _G.C_Texture = nil
end)

T.test("pet happiness: hidden without a hunter pet, and when turned off", function()
    local DUI, ns = login(3, false)
    T.falsy(ns.happiness:IsShown(), "a warlock's minion")
    DUI, ns = login(3)
    T.truthy(ns.happiness:IsShown())
    DUI:Set("UnitFrames", "pet.happiness", false)
    stub.RunTimers()
    T.falsy(ns.happiness:IsShown(), "off")
end)

T.test("pet happiness: a stripe inside the frame, straight on the left and along the angle on the right", function()
    local DUI, ns = login(2)
    local f, h = ns.frames.pet, ns.happiness
    local function anchorX(bar, point)
        for i = 1, bar:GetNumPoints() do
            local p, _, _, x = bar:GetPoint(i)
            if p == point then return x end
        end
    end
    local left0 = anchorX(f.health, "TOPLEFT")
    local right0 = anchorX(f.power, "BOTTOMRIGHT")
    DUI:Set("UnitFrames", "pet.happinessLook", "frame")
    stub.RunTimers()
    T.falsy(h:IsShown(), "the square steps aside")
    T.truthy(h.band:IsShown() and h.stripe:IsShown(), "the stripe shows")
    local lo, hi = DaylightUI.Gradients.PaintRGBOf(DaylightUI.Gradients.PairFrom(ns.Happiness.COLORS[2]))
    local g = h.stripe.__gradient
    T.truthy(g, "a gradient, like the bars")
    T.eq(g[1], "VERTICAL")
    T.rgb({ g[2].r, g[2].g, g[2].b }, lo, "darker at the bottom")
    T.rgb({ g[3].r, g[3].g, g[3].b }, hi, "content yellow on top")
    T.eq(anchorX(f.health, "TOPLEFT"), left0, "the other end stays put")
    T.truthy(anchorX(f.power, "BOTTOMRIGHT") < right0, "the bars stop short of the stripe")
    T.eq(DaylightUI.Style.ClipSpan(f.health:GetStatusBarTexture()), "inner", "the bars keep a straight end")
    T.truthy(h.stripe:GetWidth() > DaylightUI.Pixel.Px(f, ns.Happiness.STRIPE), "the block covers the angled corner")
    DUI:Set("UnitFrames", "pet.happinessSide", "left")
    stub.RunTimers()
    T.truthy(anchorX(f.health, "TOPLEFT") > left0, "the straight end gives the stripe a rectangle")
    T.eq(DaylightUI.Style.ClipSpan(f.health:GetStatusBarTexture()), "inner", "the angle is the other end")
    T.eq(h.stripe:GetWidth(), DaylightUI.Pixel.Px(f, ns.Happiness.STRIPE))
end)

T.test("pet happiness: the stripe fades in and out and slides to the next mood's color", function()
    local DUI, ns = login(2)
    local h = ns.happiness
    local function run() local d = DaylightUI.Motion.Driver(); if d then stub.RunOnUpdate(d, 1) end end
    local function top() local c = h.stripe.__gradient[3]; return { c.r, c.g, c.b } end
    DUI:Set("UnitFrames", "pet.happinessLook", "frame")
    stub.RunTimers()
    run()
    T.eq(h.band:GetAlpha(), 1, "faded in")
    stub.mood = 3
    stub.FireEvent("UNIT_HAPPINESS", "pet")
    local _, hi = DaylightUI.Gradients.PaintRGBOf(DaylightUI.Gradients.PairFrom(ns.Happiness.COLORS[3]))
    T.truthy(math.abs(top()[2] - hi[2]) > 0.001, "not there yet")
    run()
    T.rgb(top(), hi, "happy green once it settles")
    stub.mood = nil
    stub.FireEvent("UNIT_HAPPINESS", "pet")
    run()
    T.falsy(h.band:IsShown(), "gone once it has faded out")
end)

T.test("pet happiness: a warlock's demon keeps its whole frame with the stripe look on", function()
    local DUI, ns = login(nil, false, "WARLOCK")
    local f, h = ns.frames.pet, ns.happiness
    local function anchorX(bar, point)
        for i = 1, bar:GetNumPoints() do
            local p, _, _, x = bar:GetPoint(i)
            if p == point then return x end
        end
    end
    local before = anchorX(f.power, "BOTTOMRIGHT")
    DUI:Set("UnitFrames", "pet.happinessLook", "frame")
    stub.RunTimers()
    T.eq(anchorX(f.power, "BOTTOMRIGHT"), before, "no gap at the end of the frame")
    T.falsy(h.band:IsShown(), "no stripe either")
end)

T.test("pet happiness: hovering says what the game says", function()
    local _, ns = login(3)
    local lines = {}
    _G.GameTooltip = { SetOwner = function() end, AddLine = function(_, t) lines[#lines + 1] = t end,
                       Show = function() end, Hide = function() end }
    _G.PET_HAPPINESS3, _G.PET_DAMAGE_PERCENTAGE, _G.GAINING_LOYALTY = "Happy", "Damage: %d%%", "Gaining loyalty"
    _G.PET_DIET_TEMPLATE = "Diet: %s"
    ns.happiness:GetScript("OnEnter")(ns.happiness)
    T.eq(lines[1], "Happy")
    T.eq(lines[2], "Damage: 125%")
    T.eq(lines[3], "Gaining loyalty")
    T.eq(lines[4], "Diet: Meat, Fish")
end)

T.test("pet happiness: the test-mode sample keeps its name with 'color the bar' on", function()
    local DUI, ns = login(2)
    stub.units.pet = { name = "Rex", class = "HUNTER", reaction = 5, health = 50, maxHealth = 100 }
    DUI:Set("UnitFrames", "pet.happinessBar", true)
    stub.RunTimers()
    DUI.SetTestMode(true)
    stub.RunTimers()
    stub.FireEvent("UNIT_HAPPINESS", "pet")
    local f = ns.frames.pet
    T.truthy(f.nameText:GetText():find("Syl"), "the sample's name, not the real pet's")
    DUI.SetTestMode(false)
end)

-- Druid resource bars (DruidBars.lua): the powers you're not using now.
T.test("druid bars: rage and energy in caster form, mana and energy as a bear; only forms you know", function()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Leafy", isPlayer = true, class = "DRUID", powerType = 0, powerToken = "MANA" }
        stub.knownSpells[5487] = true      -- Bear Form, no Cat Form yet
    end })
    local h = _G.DaylightUIDruidBars
    T.truthy(h, "made with the player frame")
    T.falsy(h:IsShown(), "off by default")
    DUI:Set("UnitFrames", "player.druidBars.enabled", true)
    stub.RunTimers()
    local B = ns.DruidBars
    local function shown()
        local out = {}
        for _, i in ipairs(B.Wanted()) do out[#out + 1] = B.POWERS[i].token end
        return table.concat(out, ",")
    end
    T.eq(shown(), "RAGE", "caster form: rage (no Cat Form: no energy)")
    T.truthy(h:IsShown())
    stub.knownSpells[768] = true
    stub.FireEvent("SPELLS_CHANGED")
    T.eq(shown(), "RAGE,ENERGY")
    stub.units.player.powerType, stub.units.player.powerToken = 1, "RAGE"
    stub.FireEvent("UNIT_DISPLAYPOWER", "player")
    T.eq(shown(), "MANA,ENERGY", "a bear: mana and energy")
    DUI:Set("UnitFrames", "player.druidBars.enabled", false)
    stub.RunTimers()
    T.falsy(h:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("druid bars: never for another class", function()
    local DUI = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Hunts", isPlayer = true, class = "HUNTER" }
    end })
    DUI:Set("UnitFrames", "player.druidBars.enabled", true)
    stub.RunTimers()
    T.falsy(_G.DaylightUIDruidBars:IsShown())
end)
