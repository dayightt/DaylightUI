local stub = require("stub")

-- Daybreak (BarFxDaybreak.lua): a crescent riding the fill's moving end, a
-- shadow pushed into the fill on a hit, two rims closing in on a heal. Two
-- textures pinned to the end, one looping flipbook and one one-shot.

-- A bar and the settings table it follows. h is the health fill's height.
local function setup(cfg, w, h, opts)
    opts = opts or {}
    local DUI = stub.Load({})
    local Style = DUI.Style
    local bar = Style.Bar(UIParent)
    bar:SetSize(w or 187, h or 32)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(opts.value or 0.83)
    if opts.reverse then bar:SetReverseFill(true) end
    if opts.slant ~= false then
        Style.AngleFill(bar, opts.reverse and "left" or "right", opts.cut or 8, opts.under)
    end
    DUI.Gradients.PaintUnit(bar, "player")
    cfg = cfg or { style = "daybreak" }
    return DUI, bar, cfg, DUI.BarFx.Reader(function() return cfg end)
end

-- Every animation group and texture a bar makes from here on.
local function watch(bar)
    local made = { groups = {}, textures = 0 }
    local group, tex = bar.CreateAnimationGroup, bar.CreateTexture
    bar.CreateAnimationGroup = function(self, ...)
        local g = group(self, ...)
        made.groups[#made.groups + 1] = g
        return g
    end
    bar.CreateTexture = function(self, ...)
        made.textures = made.textures + 1
        return tex(self, ...)
    end
    return made
end

-- Daybreak's two textures: the idle crescent and the reaction.
local function parts(DUI, bar)
    local idle, react
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local layer, sub = r:GetDrawLayer()
            if layer == "ARTWORK" and r:GetBlendMode() == "BLEND" then
                if sub == DUI.BarFx.FX_SUB - 1 then idle = r elseif sub == DUI.BarFx.FX_SUB then react = r end
            end
        end
    end
    return idle, react
end

local function track(DUI, bar, read, unit, kind)
    local made = watch(bar)
    DUI.BarFx.Track(bar, kind or "health", nil, unit or "player", nil, read)
    local idle, react = parts(DUI, bar)
    return idle, react, made.groups[1], made.groups[2], made
end

local function flipbook(g)
    for _, a in ipairs({ g:GetAnimations() }) do
        if a:GetObjectType() == "FlipBook" then return a end
    end
end

-- The client ends a one-shot group by itself; the fake game has no clock for it.
local function finish(g)
    g.__playing = false
    local fn = g:GetScript("OnFinished")
    if fn then fn(g) end
end

local function hasMask(t, m)
    for i = 1, t:GetNumMaskTextures() do
        if t:GetMaskTexture(i) == m then return true end
    end
    return false
end

local function combat(unit, action)
    stub.FireEvent("UNIT_COMBAT", unit, action, "", stub.Secret(812), 1)
end

local function sheet(t) return tostring(t:GetTexture() or "") end

-- A new size, and the OnSizeChanged the client sends with it.
local function resize(f, w, h)
    f:SetSize(w, h)
    local fn = f:GetScript("OnSizeChanged")
    if fn then fn(f, w, h) end
end

T.test("Daybreak follows the live fill at both reference sizes", function()
    for _, size in ipairs({ { 187, 32, "" }, { 170, 16, "-thin" } }) do
        local DUI, bar, _, read = setup(nil, size[1], size[2])
        local idle, react, anim, shot = track(DUI, bar, read)
        local tag = size[2] .. " high: "
        T.eq(DUI.BarFx.StyleOf(bar), "daybreak", tag .. "the bar wears it")
        T.truthy(idle and react, tag .. "two textures over the fill")
        local fill = bar:GetStatusBarTexture()
        T.eq(sheet(idle), DUI.MEDIA .. "barfx-daybreak" .. size[3] .. ".png", tag .. "its sheet")
        for _, t in ipairs({ idle, react }) do
            local p1, rel1, rp1 = t:GetPoint(1)
            local p2, rel2, rp2 = t:GetPoint(2)
            T.eq(p1 .. rp1, "TOPRIGHTTOPRIGHT", tag .. "pinned to the moving end's top")
            T.eq(p2 .. rp2, "BOTTOMRIGHTBOTTOMRIGHT", tag .. "and bottom")
            T.truthy(rel1 == fill and rel2 == fill, tag .. "to the fill itself")
            T.eq(t:GetWidth(), 4 * size[2], tag .. "four bar heights wide")
            local _, sub = t:GetDrawLayer()
            local _, fillSub = fill:GetDrawLayer()
            T.truthy(sub > fillSub and sub < 1, tag .. "over the fill, under the bar's overlays")
        end
        local _, idleSub = idle:GetDrawLayer()
        local _, reactSub = react:GetDrawLayer()
        T.truthy(idleSub < reactSub, tag .. "a reaction draws over the resting crescent")
        T.eq(anim:GetLooping(), "REPEAT")
        T.truthy(anim:IsPlaying(), tag .. "the crescent breathes on its own")
        local a = flipbook(anim)
        T.eq(a:GetDuration(), 5)
        T.eq(a:GetFlipBookFrames(), 64)
        T.eq(a:GetFlipBookColumns(), 4)
        T.eq(a:GetFlipBookRows(), 16)
        T.eq(shot:GetLooping(), "NONE")
        T.eq(flipbook(shot):GetDuration(), 0.74)
        T.falsy(shot:IsPlaying(), tag .. "no reaction at rest")
        T.falsy(react:IsShown(), tag .. "and its texture hidden")
        T.isnil(bar:GetScript("OnUpdate"), tag .. "no Lua at rest")
    end
end)

T.test("Daybreak repaints without restarting the sun", function()
    local DUI, bar, cfg, read = setup()
    local idle, _, anim = track(DUI, bar, read)
    local stops, plays = 0, 0
    local stop, play = anim.Stop, anim.Play
    anim.Stop = function(self, ...) stops = stops + 1; return stop(self, ...) end
    anim.Play = function(self, ...) plays = plays + 1; return play(self, ...) end
    local before = { idle:GetVertexColor() }
    DUI.Gradients.Paint(bar, "HOSTILE")
    DUI.Gradients.PaintUnit(bar, "player")
    DUI.BarFx.Apply(bar)
    DUI.BarFx.Refresh()
    T.eq(stops, 0, "a repaint never stops the loop")
    T.eq(plays, 0, "nor starts it over")
    T.truthy(anim:IsPlaying())
    DUI.Gradients.Paint(bar, "HOSTILE")
    local after = { idle:GetVertexColor() }
    T.truthy(after[1] ~= before[1] or after[2] ~= before[2], "but takes the new colors")
    local lo, hi = DUI.BarFx.Colors({ bar = bar, cfg = read })
    local r, g, b = DUI.BarFx.DaybreakLight(hi)
    T.near(after[1], r); T.near(after[2], g); T.near(after[3], b)
    T.near(r, math.min(1, 0.34 * hi[1] + 176 / 255), nil, "the reference's tint")
    cfg.strength = 0.4
    DUI.BarFx.Apply(bar)
    T.near(select(4, idle:GetVertexColor()), 0.4, nil, "strength is its opacity")
end)

T.test("Daybreak clips at zero and near zero on square and independently slanted ends", function()
    local cases = {}
    for _, value in ipairs({ 0, 0.01, 0.53, 0.83, 1 }) do
        for _, shape in ipairs({ { slant = false }, { cut = 8 }, { cut = 8, under = true }, { cut = 3 } }) do
            for _, reverse in ipairs({ false, true }) do
                cases[#cases + 1] = { value = value, slant = shape.slant, cut = shape.cut, under = shape.under, reverse = reverse }
            end
        end
    end
    for _, c in ipairs(cases) do
        local tag = string.format("%.2f %s%s%s: ", c.value, c.slant == false and "square" or ("cut " .. c.cut),
            c.under and " under" or "", c.reverse and " reversed" or "")
        local DUI, bar, _, read = setup(nil, 187, 32, c)
        local idle, react = track(DUI, bar, read)
        local fill = bar:GetStatusBarTexture()
        local side = c.reverse and "LEFT" or "RIGHT"
        for _, t in ipairs({ idle, react }) do
            T.eq(t:GetPoint(1), "TOP" .. side, tag .. "pinned to the moving end")
            T.eq(select(2, t:GetPoint(1)), fill, tag .. "of the fill, even an empty one")
            for i = 1, fill:GetNumMaskTextures() do
                T.truthy(hasMask(t, fill:GetMaskTexture(i)), tag .. "wears the fill's mask " .. i)
            end
            if fill:GetNumMaskTextures() < 3 then
                T.truthy(t:GetNumMaskTextures() > fill:GetNumMaskTextures(), tag .. "and the bar's rectangle")
            end
            T.truthy(t:GetNumMaskTextures() <= 3, tag .. "never past three masks")
            local offs = t.__vertexOffsets or {}
            local moved = 0
            for _, o in pairs(offs) do if o[1] ~= 0 then moved = moved + 1 end end
            T.eq(moved, c.slant == false and 0 or 2, tag .. "leans with the angled end (two corners)")
        end
    end
    -- A fill already wearing three masks: none added past them.
    local DUI, bar, _, read = setup()
    local fill = bar:GetStatusBarTexture()
    while fill:GetNumMaskTextures() < 3 do fill:AddMaskTexture(bar:CreateMaskTexture()) end
    local idle = track(DUI, bar, read)
    DUI.Gradients.PaintUnit(bar, "player")
    T.eq(idle:GetNumMaskTextures(), 3, "three masks: the fill's own, nothing more")
    for i = 1, 3 do T.truthy(hasMask(idle, fill:GetMaskTexture(i))) end
    -- The art's own cutoff: 18 and lower draws the simple shape.
    for _, h in ipairs({ 16, 18, 19, 32 }) do
        local D, b, _, r = setup(nil, 187, h)
        local t = track(D, b, r)
        T.eq(sheet(t), D.MEDIA .. "barfx-daybreak" .. (h <= 18 and "-thin" or "") .. ".png", h .. " high")
    end
    -- A vertical bar keeps the core's opt-out.
    local D2, b2, _, r2 = setup()
    b2:SetOrientation("VERTICAL")
    D2.BarFx.Track(b2, "health", nil, "player", nil, r2)
    T.isnil(D2.BarFx.StyleOf(b2), "no style on a vertical bar")
end)

T.test("Daybreak mirrors without resizing its artwork", function()
    for _, h in ipairs({ 32, 16 }) do
        local DUI, bar, _, read = setup(nil, 187, h, { reverse = true })
        local idle, react, _, shot = track(DUI, bar, read)
        local thin = h <= 18 and "-thin" or ""
        T.eq(sheet(idle), DUI.MEDIA .. "barfx-daybreak" .. thin .. "-l.png", h .. ": the mirrored sheet")
        T.eq(idle:GetPoint(1), "TOPLEFT")
        T.eq(idle:GetWidth(), 4 * h, h .. ": the same size as the right-filling one")
        DUI.BarFx.Kick(bar, -1)
        T.eq(sheet(react), DUI.MEDIA .. "barfx-daybreak-hit" .. thin .. "-l.png", h .. ": a hit, mirrored")
        T.truthy(shot:IsPlaying())
        DUI.BarFx.Kick(bar, 1)
        T.eq(sheet(react), DUI.MEDIA .. "barfx-daybreak-heal" .. thin .. "-l.png", h .. ": a heal, mirrored")
    end
    -- Flipping a live bar's direction moves it to the other end.
    local DUI, bar, _, read = setup()
    local idle = track(DUI, bar, read)
    bar:SetReverseFill(true)
    DUI.Style.AngleFill(bar, "left", 8)
    resize(bar, 188, 32)
    T.eq(idle:GetPoint(1), "TOPLEFT", "follows a new fill direction")
    T.eq(sheet(idle), DUI.MEDIA .. "barfx-daybreak-l.png")
end)

T.test("WOUND sends the shadow inward and HEAL calls the double rim", function()
    local DUI, bar, cfg, read = setup()
    local idle, react, anim, shot = track(DUI, bar, read)
    T.truthy(bar:IsVisible())
    combat("player", "WOUND")
    T.eq(sheet(react), DUI.MEDIA .. "barfx-daybreak-hit.png", "a hit plays the shadow")
    T.truthy(react:IsShown() and shot:IsPlaying(), "once, now")
    T.truthy(anim:IsPlaying(), "the crescent keeps breathing under it")
    T.eq(flipbook(shot):GetDuration(), 0.74)
    DUI.Style.SetBarValue(bar, 0.53, true)
    T.eq(bar:GetValue(), 0.53, "the bar's value moves at once, not after the reaction")
    combat("player", "HEAL")
    T.eq(sheet(react), DUI.MEDIA .. "barfx-daybreak-heal.png", "a heal plays the rims")
    T.truthy(shot:IsPlaying(), "one reaction, replaced")
    finish(shot)
    T.falsy(react:IsShown(), "gone when it ends")
    -- None of these react.
    local function none(label, fn)
        finish(shot)
        fn()
        T.falsy(react:IsShown() or shot:IsPlaying(), label)
    end
    none("another unit", function() combat("target", "WOUND") end)
    none("an action that isn't a hit or a heal", function() combat("player", "MISS") end)
    none("a hidden bar", function() bar:Hide(); combat("player", "WOUND"); bar:Show() end)
    cfg.react = false
    DUI.BarFx.Apply(bar)
    none("reactions off", function() combat("player", "WOUND") end)
    cfg.react = true
    local D2, power, _, r2 = setup()
    local _, react2, _, shot2 = track(D2, power, r2, "player", "power")
    combat("player", "WOUND")
    T.falsy(react2:IsShown() or shot2:IsPlaying(), "a power bar keeps the idle crescent only")
end)

T.test("a burst of hits and heals always shows the newest", function()
    local DUI, bar, cfg, read = setup()
    local idle, react, anim, shot = track(DUI, bar, read)
    local seq = { -1, 1, -1 }
    for _, dir in ipairs(seq) do DUI.BarFx.Kick(bar, dir) end
    T.eq(sheet(react), DUI.MEDIA .. "barfx-daybreak-hit.png", "hit, heal, hit: the last hit")
    -- The one replaced ends late: it must not hide the one playing now.
    local fn = shot:GetScript("OnFinished")
    fn(shot)
    T.truthy(react:IsShown(), "a stale end leaves the new reaction")
    -- A repaint mid-reaction keeps it and its strength.
    cfg.reactSize = 0.5
    DUI.BarFx.Kick(bar, 1)
    local alpha = select(4, react:GetVertexColor())
    T.near(alpha, 0.5, nil, "strength times size")
    DUI.Gradients.Paint(bar, "HOSTILE")
    T.truthy(shot:IsPlaying() and react:IsShown(), "a repaint keeps the reaction")
    T.near(select(4, react:GetVertexColor()), 0.5, nil, "at its strength")
    T.eq(sheet(react), DUI.MEDIA .. "barfx-daybreak-heal.png")
    -- Size endpoints clamp.
    cfg.reactSize, cfg.strength = 2, 1
    DUI.BarFx.Kick(bar, -1)
    T.eq(select(4, react:GetVertexColor()), 1, "never past full")
    cfg.reactSize, cfg.strength = 0.25, 0.1
    DUI.BarFx.Kick(bar, -1)
    T.near(select(4, react:GetVertexColor()), 0.025)
    -- Crossing the cutoff mid-shot drops it; the next one is drawn for the new shape.
    cfg.reactSize, cfg.strength = 1, 1
    DUI.BarFx.Kick(bar, -1)
    resize(bar, 187, 16)
    T.falsy(react:IsShown() or shot:IsPlaying(), "a reaction drawn for the old shape goes")
    DUI.BarFx.Kick(bar, -1)
    T.eq(sheet(react), DUI.MEDIA .. "barfx-daybreak-hit-thin.png", "the next fits the new one")
    T.eq(sheet(idle), DUI.MEDIA .. "barfx-daybreak-thin.png")
    T.truthy(anim:IsPlaying())
end)

-- The nameplate world from test_nameplates.lua: a game plate per unit token.
local plates
local function plateWorld()
    plates = {}
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        local i = tonumber(string.match(unit, "%d+"))
        if not i or not stub.units[unit] then return nil end
        if not plates[i] then
            local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
            np.UnitFrame = CreateFrame("Button", nil, np)
            np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
            np.UnitFrame.WidgetContainer = CreateFrame("Frame", nil, np.UnitFrame)
            np.UnitFrame.name = np.UnitFrame:CreateFontString(nil, "OVERLAY")
            function np:CanChangeHitTestPoints() return true end
            function np:SetAllHitTestPoints(f) self.__hit = f end
            function np:SetHitTestPoints() self.__hit = "the game's" end
            function np:ClearAllHitTestPoints() self.__hit = nil end
            function np:SetStackingBoundsFrame(f) self.__stack = f end
            function np.UnitFrame.UpdateHitTestArea() np:SetHitTestPoints({}) end
            plates[i] = np
        end
        return plates[i]
    end }
    _G.issecure = function() return false end
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    _G.UnitReaction = function(u) local x = stub.units[u]; return x and x.reaction end
    _G.IsInInstance = function() return false end
    _G.UnitGroupRolesAssigned = function() return "DAMAGER" end
    Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
    _G.C_TooltipInfo = { GetUnit = function() return nil end }
    stub.units = { player = { name = "Me", class = "MAGE", isPlayer = true, health = 83, maxHealth = 100 } }
    for i = 1, 40 do
        stub.units["nameplate" .. i] = { name = "Scarlet Invoker " .. i, hostile = true, reaction = 2,
            health = 83, maxHealth = 100, pct = 83 }
    end
    stub.units.target = { name = "Scarlet Invoker", hostile = true, reaction = 2, health = 60, maxHealth = 100 }
end

local function loadWorld()
    local DUI, UF = stub.Load({ module = true, nameplates = true, before = plateWorld })
    stub.RunTimers()
    return DUI, UF
end

-- The fake game doesn't size a frame from its anchors: a plate's health bar
-- gets the 170 x 16 the client would give it.
local function added(unit)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", unit)
    stub.RunTimers()
    local p = stub.nameplates.Manager.byUnit[unit]
    if p and p.health:GetWidth() == 0 then resize(p.health, 170, 16) end
    return p
end

local function reactOf(DUI, bar)
    local _, react = parts(DUI, bar)
    return react
end

T.test("Daybreak does not carry a hit to a reused plate or swapped target", function()
    local DUI, UF = loadWorld()
    DUI:Set("Nameplates", "barFx.health.style", "daybreak")
    DUI:Set("UnitFrames", "target.barFx.health.style", "daybreak")
    stub.RunTimers()
    -- A plate: hit, then the plate goes and comes back for another mob.
    local p = added("nameplate3")
    T.eq(DUI.BarFx.StyleOf(p.health), "daybreak")
    combat("nameplate3", "WOUND")
    local react = reactOf(DUI, p.health)
    T.truthy(react:IsShown(), "the plate's hit plays")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    stub.RunTimers()
    stub.units.nameplate3.name = "Another Mob"
    local again = added("nameplate3")
    T.truthy(again == p, "the same pooled plate")
    T.falsy(react:IsShown(), "no hit left over on the next mob")
    -- Released while still shown (the pool hands it over within one frame).
    combat("nameplate3", "WOUND")
    T.truthy(react:IsShown())
    stub.nameplates.Plate.Uninstall(p)
    T.falsy(react:IsShown(), "released: the reaction goes with the old mob")
    stub.nameplates.Plate.Install(p, "nameplate3")
    -- The target frame: its token stays "target" while the unit behind it changes.
    local f = UF.frames.target
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.eq(DUI.BarFx.StyleOf(f.health), "daybreak")
    if f.health:GetWidth() == 0 then resize(f.health, 187, 32) end   -- sized from its anchors in the client
    local treact = reactOf(DUI, f.health)
    combat("target", "WOUND")
    T.truthy(treact:IsShown(), "the target's hit plays")
    UF.UF.UpdateIdentity(f)
    DUI.BarFx.SetUnit(f.health, "target")
    T.truthy(treact:IsShown(), "a repaint of the same unit keeps it")
    stub.units.target = { name = "Someone Else", hostile = true, reaction = 2, health = 90, maxHealth = 100 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.falsy(treact:IsShown(), "a new target starts with no hit of the old one's")
    -- A changed token clears it too.
    combat("target", "WOUND")
    DUI.BarFx.SetUnit(f.health, "focus")
    T.falsy(treact:IsShown(), "another token: cleared")
end)

T.test("Disabling or reloading Daybreak leaves only the intended idle motion", function()
    local DUI, bar, cfg, read = setup()
    local idle, react, anim, shot, made = track(DUI, bar, read)
    local function hit() DUI.BarFx.Kick(bar, -1); T.truthy(react:IsShown(), "a hit plays") end
    hit()
    cfg.react = false
    DUI.BarFx.Apply(bar)
    T.falsy(react:IsShown() or shot:IsPlaying(), "reactions off mid-hit: gone")
    T.truthy(anim:IsPlaying(), "the crescent stays")
    cfg.react = true
    hit()
    DUI:Set("general", "motion", false)
    DUI.BarFx.Refresh()
    T.falsy(idle:IsShown() or react:IsShown(), "motion off: no art left")
    T.falsy(anim:IsPlaying() or shot:IsPlaying())
    DUI:Set("general", "motion", true)
    DUI.BarFx.Refresh()
    T.truthy(idle:IsShown() and anim:IsPlaying(), "motion on: back")
    T.falsy(react:IsShown(), "with no old reaction")
    -- Colors the game keeps secret: the plain bar, then back on a usable pair.
    hit()
    local fill = bar:GetStatusBarTexture()
    DUI.Style.NoteFillRGB(fill, nil)
    DUI.BarFx.Painted(fill)
    if DUI.BarFx.Colors({ bar = bar, cfg = read }) == nil then
        T.falsy(idle:IsShown() or react:IsShown(), "unknown colors: hidden")
    end
    DUI.Gradients.PaintUnit(bar, "player")
    T.truthy(idle:IsShown() and anim:IsPlaying(), "known again: back")
    -- A loading screen: the client leaves a group "playing" that never moves.
    hit()
    stub.FireEvent("LOADING_SCREEN_DISABLED")
    T.falsy(react:IsShown() or shot:IsPlaying(), "a loading screen clears the old reaction")
    T.truthy(anim:IsPlaying(), "and starts the crescent over")
    -- Hidden and shown.
    hit()
    bar:Hide()
    bar:Show()
    T.falsy(react:IsShown(), "hidden and shown: no reaction")
    T.truthy(idle:IsShown() and anim:IsPlaying())
    -- A profile change and fast swaps between styles.
    hit()
    DUI.BarFx.Refresh()
    T.truthy(react:IsShown(), "a refresh of the same pick keeps the reaction")
    for _, style in ipairs({ "flow", "daybreak", "none", "tide", "daybreak", "comet", "daybreak" }) do
        cfg.style = style
        DUI.BarFx.Apply(bar)
        T.eq(idle:IsShown(), style == "daybreak", style .. ": the crescent only on Daybreak")
        T.falsy(react:IsShown(), style .. ": never a leftover reaction")
    end
    -- Nothing new is made by kicks and repaints once built.
    local before = { made.textures, #made.groups }
    for _ = 1, 30 do DUI.BarFx.Kick(bar, -1); DUI.BarFx.Kick(bar, 1); DUI.Gradients.PaintUnit(bar, "player"); DUI.BarFx.Apply(bar) end
    T.eq(made.textures, before[1], "no texture made by kicks or repaints")
    T.eq(#made.groups, before[2], "no animation group either")
    T.isnil(bar:GetScript("OnUpdate"), "no Lua running on the bar")
end)

T.test("Picking Daybreak reaches the player and nameplate independently", function()
    local DUI, UF = loadWorld()
    local values = DUI.BarFx.Choices()
    T.eq(values.daybreak, "Daybreak", "the picker's label")
    local player, target = UF.frames.player, UF.frames.target
    local targetStyle = DUI:Get("UnitFrames", "target.barFx.health.style")
    T.eq(DUI:Get("UnitFrames", "player.barFx.health.style"), "flow", "a new setup still starts in Flow")
    DUI:Set("UnitFrames", "player.barFx.health.style", "daybreak")
    stub.RunTimers()
    T.eq(DUI.BarFx.StyleOf(player.health), "daybreak", "the player's health")
    T.eq(DUI:Get("UnitFrames", "target.barFx.health.style"), targetStyle, "the target keeps its own pick")
    T.eq(DUI:Get("UnitFrames", "player.barFx.power.style"), "flow", "the power strip keeps its own")
    T.eq(DUI.BarFx.StyleOf(player.power), "flow")
    local p = added("nameplate1")
    T.falsy(DUI.BarFx.StyleOf(p.health), "plates stay plain until picked")
    DUI:Set("Nameplates", "barFx.health.style", "daybreak")
    stub.RunTimers()
    T.eq(DUI.BarFx.StyleOf(p.health), "daybreak", "the plate's health")
    T.eq(DUI.BarFx.StyleOf(player.health), "daybreak")
    -- The options sample wears it.
    local sample = DUI.BarFx.SampleBar(UIParent, "health", nil, DUI.BarFx.Reader(function()
        return DUI:Get("UnitFrames", "player.barFx.health")
    end))
    sample:SetSize(200, 14)
    T.eq(DUI.BarFx.StyleOf(sample.bar), "daybreak", "a visible options sample")
    -- By power type never picks it; explicit picks stay put.
    for power, style in pairs(DUI.BarFx.AUTO) do T.truthy(style ~= "daybreak", power) end
    DUI:Set("UnitFrames", "player.barFx.power.style", "auto")
    stub.RunTimers()
    T.truthy(DUI.BarFx.StyleOf(player.power) ~= "daybreak", "by power type")
    DUI:Set("UnitFrames", "player.barFx.health.style", "none")
    stub.RunTimers()
    T.isnil(DUI.BarFx.StyleOf(player.health), "an explicit None")
    DUI:Set("UnitFrames", "player.barFx.health.style", "tide")
    stub.RunTimers()
    T.eq(DUI.BarFx.StyleOf(player.health), "tide", "another style")
end)

T.test("Daybreak's settings: speed, strength and colors", function()
    local DUI, bar, cfg, read = setup()
    local idle, react, anim, shot = track(DUI, bar, read)
    for _, k in ipairs({ 0.25, 3 }) do
        cfg.speed = k
        DUI.BarFx.Apply(bar)
        T.near(anim:GetAnimationSpeedMultiplier(), k, nil, "idle speed " .. k)
        T.eq(flipbook(shot):GetDuration(), 0.74, "reactions keep their 0.74 s")
        T.near(shot:GetAnimationSpeedMultiplier(), 1)
    end
    for _, k in ipairs({ 0.1, 1 }) do
        cfg.strength = k
        DUI.BarFx.Apply(bar)
        T.near(select(4, idle:GetVertexColor()), k, nil, "strength " .. k)
    end
    -- From the bar's own colors to a custom pair, mid-reaction.
    DUI.BarFx.Kick(bar, 1)
    cfg.colors, cfg.colorA, cfg.colorB = "custom", { 0.1, 0.1, 0.1 }, { 1, 0, 0 }
    DUI.BarFx.Apply(bar)
    local r, g, b = idle:GetVertexColor()
    T.near(r, 1); T.near(g, 171 / 255); T.near(b, 159 / 255)
    local rr = react:GetVertexColor()
    T.near(rr, 1, nil, "the reaction takes the new tint")
    T.truthy(shot:IsPlaying(), "and keeps playing")
    -- Class and accent modes paint without error.
    for _, mode in ipairs({ "class", "accent" }) do
        cfg.colors = mode
        DUI.BarFx.Apply(bar)
        T.truthy(idle:IsShown(), mode)
    end
end)

T.test("Forty idle Daybreak plates reuse their regions across combat and profile refresh", function()
    local DUI = loadWorld()
    DUI:Set("Nameplates", "barFx.health.style", "daybreak")
    local list, made = {}, {}
    for i = 1, 40 do
        local p = added("nameplate" .. i)
        list[i] = p
        made[i] = watch(p.health)
        T.eq(DUI.BarFx.StyleOf(p.health), "daybreak", "plate " .. i)
    end
    combat("nameplate5", "WOUND")
    for i, p in ipairs(list) do
        local react = reactOf(DUI, p.health)
        T.eq(react:IsShown(), i == 5, "only the struck plate reacts: " .. i)
    end
    DUI.BarFx.Refresh()
    DUI:Set("Nameplates", "barFx.health.strength", 0.6)
    stub.RunTimers()
    for _ = 1, 5 do combat("nameplate5", "HEAL"); combat("nameplate7", "WOUND") end
    for i, p in ipairs(list) do
        T.eq(made[i].textures, 0, "plate " .. i .. " made no texture")
        T.eq(#made[i].groups, 0, "plate " .. i .. " made no group")
        T.isnil(p.health:GetScript("OnUpdate"), "plate " .. i .. ": no Lua on its bar")
    end
    -- Absorbs, incoming heals and an execute tint sit over the fill, above Daybreak.
    local p = list[1]
    local idle = parts(DUI, p.health)
    local _, sub = idle:GetDrawLayer()
    for _, r in ipairs({ p.health:GetRegions() }) do
        if r ~= idle and r:GetObjectType() == "Texture" and r:IsShown() then
            local layer, s = r:GetDrawLayer()
            if layer == "ARTWORK" and s >= 1 then T.truthy(s > sub, "an overlay stays over the crescent") end
        end
    end
end)
