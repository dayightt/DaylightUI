local stub = require("stub")

-- The buff and debuff bars: their look (the target auras'), where they sit (beside
-- the info panel, following it), options, commands and preview.

local function world()
    _G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    CreateFrame("Frame", "BuffFrame", UIParent)
    CreateFrame("Frame", "DebuffFrame", UIParent)
    stub.units = { player = { name = "Me", class = "PRIEST" } }
end

local function login(opts)
    opts = opts or {}
    stub.Load({ buffs = true, infopanel = opts.infopanel, before = function()
        world()
        if opts.before then opts.before() end
    end })
    stub.RunTimers()
    return stub.buffs
end

local function group(key) return DaylightUIBuffs.__groups[key] end

-- The client's color curves, enough to read the points back.
local function fakeCurves()
    _G.C_CurveUtil = { CreateColorCurve = function()
        local c = { points = {} }
        function c:SetType() end
        function c:AddPoint(x, col) self.points[#self.points + 1] = { x, col } end
        return c
    end }
    _G.Enum.LuaCurveType = { Linear = 0 }
    _G.Enum.DurationTextBindingProperty = _G.Enum.DurationTextBindingProperty or { RemainingDuration = 0 }
end

T.test("buffs: the buff timer warms and breathes in its last 5 seconds; debuffs don't", function()
    local BL = login({ before = fakeCurves })
    local opts = group("priest").button.__timeOpts
    T.truthy(opts and opts.textColor, "the buff bar's timer has a color curve")
    local pts = opts.textColor.curve.points
    T.eq(#pts, 22, "21 orange points (every 0.25 s up to 5) and the normal color")
    T.eq(pts[1][1], 0); T.eq(pts[1][2].a, 1)
    T.eq(pts[2][1], 0.25); T.eq(pts[2][2].a, BL.Feel.DIM, "dims...")
    T.eq(pts[3][2].a, 1, "...and back")
    T.eq(pts[2][2].r, DaylightUI.Style.GRADIENT[2][1], "the gradient's orange end")
    T.eq(pts[22][2].r, BL.Widgets.TIME_COLOR[1], "the normal color above 5 s")
    T.eq(opts.textColor.property, Enum.DurationTextBindingProperty.RemainingDuration)
    local dopts = DaylightUIDebuffs.__groups.debuffs.button.__timeOpts
    T.isnil(dopts and dopts.textColor, "not on debuffs")
    _G.C_CurveUtil = nil
end)

T.test("buffs: the expiring setting off gives a plain timer; motion off, orange without breathing", function()
    local BL = login({ before = fakeCurves })
    DaylightUI.DB.General().motion = false
    BL.Bar:Restyle()
    for _, p in ipairs(group("priest").button.__timeOpts.textColor.curve.points) do
        T.eq(p[2].a, 1, "no breathing")
    end
    DaylightUI:Set("Buffs", "settings.expiring", false)
    stub.RunTimers()
    local o = group("priest").button.__timeOpts
    T.isnil(o and o.textColor, "off: plain")
    _G.C_CurveUtil = nil
end)

T.test("buffs: the time left sits on the top edge, the middle or the bottom edge; at the bottom the count moves up", function()
    login()
    local function spot(fs) local p, _, rel = fs:GetPoint(1); return p .. ">" .. rel end
    local btn = group("priest").button
    local dbtn = DaylightUIDebuffs.__groups.debuffs.button
    T.eq(spot(btn.Duration), "CENTER>TOP", "top by default")
    T.eq(spot(btn.Count), "BOTTOMRIGHT>BOTTOMRIGHT")
    DaylightUI:Set("Buffs", "settings.timePos", "middle")
    stub.RunTimers()
    T.eq(spot(btn.Duration), "CENTER>CENTER")
    T.eq(spot(dbtn.Duration), "CENTER>CENTER", "both bars")
    T.eq(spot(btn.Count), "BOTTOMRIGHT>BOTTOMRIGHT")
    DaylightUI:Set("Buffs", "settings.timePos", "bottom")
    stub.RunTimers()
    T.eq(spot(btn.Duration), "CENTER>BOTTOM")
    T.eq(spot(dbtn.Duration), "CENTER>BOTTOM")
    T.eq(spot(btn.Count), "TOPRIGHT>TOPRIGHT", "the count leaves the time's corner")
end)

local function auras()
    stub.SetAuras("player", "HELPFUL", {
        { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 },
        { name = "Divine Spirit", spellId = 14752, icon = 2, expirationTime = 2100 },
    })
end
local function landed(id, spell, harmful)
    stub.FireEvent("UNIT_AURA", "player", { addedAuras = { { auraInstanceID = id, spellId = spell,
        isHelpful = not harmful, isHarmful = harmful and true or false } } })
    stub.RunTimers()
end
local function left(id)
    stub.FireEvent("UNIT_AURA", "player", { removedAuraInstanceIDs = { id } })
    stub.RunTimers()
end
-- Where element (key, index) of a bar sits, in the bar's own units.
local function spot(bar, key, index)
    local flow = bar:CurrentFlow()
    for _, e in ipairs(flow.elements) do
        if e.key == key and e.index == index then
            local l, _, _, t = stub.buffs.Layout.ElementRect(e, bar:Corner())
            local sign = bar:Corner() == "TOPRIGHT" and -1 or 1
            return (sign * (bar.weaponWidth or 0) + l), t
        end
    end
end
local function ghost(BL) local g = BL.Feel.ghosts[1]; return g and g:IsShown() and g or nil end
local function settleMotion()
    local d = DaylightUI.Motion.Driver()
    if d then for _ = 1, 60 do stub.RunOnUpdate(d, 1 / 60) end end
end

T.test("buffs: every buff and debuff button slides in as the client shows it", function()
    login({ before = auras })
    for _, btn in ipairs({ group("priest").button, DaylightUIDebuffs.__groups.debuffs.button }) do
        T.eq(#(btn.__shownAnims or {}), 1, "one group handed to the client")
        T.eq(btn.slideOn, true, "tuned to slide")
    end
end)

T.test("buffs: setting or motion off tunes the slide to nothing, once auras are plain", function()
    local BL = login({ before = auras })
    local btn = group("priest").button
    DaylightUI:Set("Buffs", "settings.newGlow", false); stub.RunTimers()
    T.eq(btn.slideOn, false, "setting off")
    stub.SetRestriction("PvPMatch", true)
    DaylightUI:Set("Buffs", "settings.newGlow", true); stub.RunTimers()
    T.eq(btn.slideOn, false, "the button is locked in a PvP match")
    stub.SetRestriction("PvPMatch", false); stub.RunTimers()
    T.eq(btn.slideOn, true, "after it")
    DaylightUI.DB.General().motion = false
    BL.Bar:Restyle()
    T.eq(btn.slideOn, false, "motion off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: a buff that leaves lifts a copy of itself away from where it sat", function()
    local BL = login({ before = auras })
    stub.Advance(3)
    landed(2, 14752)
    local x, y = spot(BL.Bar, "priest", 2)
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 } })
    left(2)
    local g = ghost(BL)
    T.truthy(g, "a copy")
    local _, rel, rp, gx, gy = g:GetPoint(1)
    T.eq(rel, BL.Bar.holder, "on our holder, never the client's buttons or container")
    T.eq(rp, BL.Bar:Corner()); T.near(gx, x, 1e-6); T.near(gy, y, 1e-6)
    T.eq(g.Icon:GetTexture(), 2, "the leaving buff's icon")
    stub.RunOnUpdate(DaylightUI.Motion.Driver(), 0.1)
    T.truthy(select(5, g:GetPoint(1)) > y, "lifting")
    settleMotion()
    T.falsy(g:IsShown(), "gone once it has lifted away")
end)

T.test("buffs: a debuff that leaves lifts away too, in its dispel color's edge", function()
    local BL = login({ before = function()
        auras()
        stub.SetAuras("player", "HARMFUL", { { name = "Shadow Word: Pain", spellId = 589, icon = 9, dispelName = "Magic", expirationTime = 2000, auraInstanceID = 50 } })
    end })
    stub.Advance(3)
    landed(50, 589, true)
    stub.SetAuras("player", "HARMFUL", {})
    left(50)
    local g = ghost(BL)
    T.truthy(g, "a copy")
    T.eq(select(2, g:GetPoint(1)), BL.DebuffBar.holder, "on the debuff bar")
    T.eq(g.Icon:GetTexture(), 9)
end)

T.test("buffs: no copy in combat, under a restriction, right after login, with the setting off or over a faded bar", function()
    local BL = login({ before = auras })
    local function gone(id)
        stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 } })
        left(id)
        local g = ghost(BL)
        settleMotion()
        auras()
        landed(2, 14752)
        return g
    end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, true)     -- a /reload, since stub.Load doesn't fire it
    landed(2, 14752)
    T.falsy(gone(2), "within 2 s of entering the world")
    stub.Advance(3)
    stub.EnterCombat(); T.falsy(gone(2), "in combat"); stub.LeaveCombat(); stub.RunTimers()
    stub.SetRestriction("PvPMatch", true); T.falsy(gone(2), "in a PvP match"); stub.SetRestriction("PvPMatch", false); stub.RunTimers()
    DaylightUI:Set("Buffs", "settings.newGlow", false); stub.RunTimers()
    T.falsy(gone(2), "setting off")
    DaylightUI:Set("Buffs", "settings.newGlow", true); stub.RunTimers()
    T.truthy(gone(2), "and back on")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: a half-faded bar's copy is as faint as the bar; a faded-out one leaves none", function()
    local BL = login({ before = auras })
    local Fade = DaylightUI.Fade
    local function settle() stub.RunTimers(); Fade.Step(); for _ = 1, 120 do stub.RunOnUpdate(Fade.driver, 1 / 60) end end
    stub.Advance(3)
    DaylightUI:Set("Buffs", "settings.fade", { mode = "always", alpha = 0.4, delay = 0, mouseover = false })
    settle()
    landed(2, 14752)
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 } })
    left(2)
    T.near(ghost(BL):GetAlpha(), 0.4, 1e-3, "as faint as the bar")
    settleMotion()
    auras()
    DaylightUI:Set("Buffs", "settings.fade", { mode = "always", alpha = 0, delay = 0, mouseover = false })
    settle()
    landed(2, 14752)
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 } })
    left(2)
    T.falsy(ghost(BL), "none over a bar you can't see")
end)

T.test("buffs: a combined category leaves a copy only when its last buff goes", function()
    local BL = login({ before = auras })
    BL.Categories.SetConsolidate("priest", true)
    stub.RunTimers(); stub.Advance(3)
    landed(2, 14752)
    stub.SetAuras("player", "HELPFUL", { { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 } })
    left(2)
    T.falsy(ghost(BL), "the group's icon stays")
    stub.SetAuras("player", "HELPFUL", {})
    left(1)
    T.truthy(ghost(BL), "its last buff left")
end)

T.test("buffs: both bars build at login, one aura group per category", function()
    local BL = login()
    T.eq(#stub.errors, 0, "no errors: " .. tostring(stub.errors[1]))
    T.truthy(DaylightUIBuffs, "the buff container")
    T.truthy(DaylightUIDebuffs, "the debuff container")
    -- Weapon too: its enchants are the addon's own buttons, and its group holds
    -- buffs moved into it.
    for _, id in ipairs(BL.Categories.Order()) do
        T.truthy(group(id), "group for " .. id)
        T.eq(group(id).filter, "HELPFUL")
    end
    T.eq(DaylightUIDebuffs.__groups.debuffs.filter, "HARMFUL")
end)

T.test("buffs: buttons wear the target auras' look, edged by category", function()
    local BL = login()
    local W = BL.Widgets
    local btn = group("priest").button
    T.eq(btn:GetWidth(), 30, "the default width")
    T.eq(btn:GetHeight(), 30, "square")
    T.falsy(btn.Edge.__gradient, "solid by default")
    BL.Categories.SetStyle("priest", "gradient")
    btn = group("priest").button
    T.deq(btn.Edge.__vertex, { 1, 1, 1, 1 }, "white under the gradient")
    T.truthy(btn.Edge.__gradient, "edged by the category's gradient")
    local p = btn.Duration.__points[1]
    T.eq(p[1], "CENTER"); T.eq(p[3], "TOP", "the time sits on the top edge")
    T.eq(btn.__time, btn.Duration, "the client drives our time text")
    T.eq(btn.__count, btn.Count)
    local layout = group("priest").layout
    T.eq(layout.elementWidth, 30)
    T.eq(layout.elementHeight, W.Height(30))
    T.truthy(layout.lineSpacing > layout.elementSpacing, "rows leave room for the time")
end)

-- In the client a FontString's alpha is its text color's alpha, and the warm-timer
-- curve sets that color every frame, so SetAlpha(0) came back at 1.
T.test("buffs: Time left off hides the time (not alpha: the color curve would bring it back)", function()
    local BL = login({ before = fakeCurves })
    BL.module.db.settings.showTimers = false
    BL.Bar:Restyle()
    local btn = group("priest").button
    T.truthy(btn.__timeOpts and btn.__timeOpts.textColor, "the curve is still bound")
    T.falsy(btn.Duration:IsShown(), "hidden")
    BL.module.db.settings.showTimers = true
    BL.Bar:Restyle()
    T.truthy(btn.Duration:IsShown(), "back")
    _G.C_CurveUtil = nil
end)

T.test("buffs: icons follow the general corner rounding", function()
    local BL = login()
    local DUI = DaylightUI
    local btn = group("priest").button
    T.eq(#btn.Edge.__masks, 2, "the left half rounded at its two corners")
    T.eq(#btn.EdgeR.__masks, 2, "the right half at its two")
    T.truthy(btn.edgeShape.F > 0, "the curve is rounder than the edge is thick")
    T.eq(btn.Caps.TOPLEFT:GetAlpha(), 1, "caps over the icon's corners")
    T.eq(btn.Caps.BOTTOMRIGHT.__texture, BL.Widgets.FILLET)
    -- Debuffs: the client tints every piece, and the caps are cropped fillets.
    local d = DaylightUIDebuffs.__groups.debuffs.button
    T.eq(#d.__dispels, 6, "both halves and four caps")
    T.eq(d.__dispels[2].tex, d.EdgeR)
    local cap = d.__dispels[4].opts.customDispelAssetMap.Magic
    T.eq(cap.asset, BL.Widgets.FILLET)
    T.eq(cap.texCoords.left, 1, "the top-right cap, mirrored")
    T.eq(#d.Edge.__masks, 2, "debuffs rounded too")
    -- Square: no masks, no caps.
    DUI:Set("general", "cornerPx", 0)
    BL.Bar:Restyle()
    T.eq(#btn.Edge.__masks, 0)
    T.eq(#btn.EdgeR.__masks, 0)
    T.eq(btn.Caps.TOPLEFT:GetAlpha(), 0)
end)

T.test("buffs: a gradient edge runs across both halves", function()
    local BL = login()
    BL.Categories.SetStyle("priest", "gradient")
    local btn = group("priest").button
    local a, b = DaylightUI.Gradients.PaintRGBOf(BL.Categories.Pair("priest"))
    local L, R = btn.Edge.__gradient, btn.EdgeR.__gradient
    T.near(L[2].r, a[1], 1e-6, "the left half starts at the pair's start")
    T.near(L[3].r, R[2].r, 1e-6, "the halves meet in the middle")
    T.near(R[3].r, b[1], 1e-6, "the right half ends at the pair's end")
end)

T.test("buffs: debuffs are bigger than buffs, wine until the client tints them", function()
    local BL = login()
    local btn = DaylightUIDebuffs.__groups.debuffs.button
    T.eq(btn:GetWidth(), 36)
    T.eq(btn:GetHeight(), BL.Widgets.Height(36))
    local c = btn.Edge.__vertex
    T.near(c[1], BL.DISPEL_COLORS.None[1], 1e-6, "wine")
end)

T.test("buffs: they start beside the info panel and follow its left edge", function()
    login({ infopanel = true })
    local p = { DaylightUIBuffsAnchor:GetPoint(1) }
    T.eq(p[1], "TOPRIGHT")
    T.eq(p[2], DaylightUIInfoPanelEdge, "hung off the panel's left edge (past the threat meter), so they slide when it narrows")
    T.eq(p[3], "TOPLEFT")
    local e = { DaylightUIInfoPanelEdge:GetPoint(1) }
    T.eq(e[2], DaylightUIInfoPanelBody, "the edge sits on the panel under the XP bar")
    T.eq(e[3], "TOPLEFT")
    T.truthy(p[4] < 0, "left of it")
    local h = { DaylightUIBuffsHolder:GetPoint(1) }
    T.eq(h[2], DaylightUIBuffsAnchor, "the bar starts at the anchor")
    local d = { DaylightUIDebuffsHolder:GetPoint(1) }
    T.eq(d[2], DaylightUIDebuffsAnchor, "debuffs start at their own anchor")
    local a = { DaylightUIDebuffsAnchor:GetPoint(1) }
    T.eq(a[2], DaylightUIInfoPanelBody)
    T.eq(a[3], "BOTTOMLEFT", "on the panel's bottom edge")
    T.eq(a[5], stub.buffs.Widgets.Height(36), "a row's height up, so the icons' bottom edge sits on it")
end)

T.test("buffs: a saved Scale moves to the bar's own size, so nothing changes size", function()
    login({ before = function()
        DaylightUIDB = {
            general = { frameScales = { ["buffs.debuff"] = 1.5 } },
            modules = { Buffs = { settings = { scale = 1.25, debuff = { scale = 0.8 } } } },
        }
    end })
    local M = DaylightUI.Movers
    T.near(M.PieceScale("buffs.buff"), 1.25, 0.001)
    T.near(M.PieceScale("buffs.debuff"), 1.2, 0.001, "on top of what the wheel had set")
    T.near(stub.buffs.Bar:Scale(), 1.25, 0.001)
    T.eq(DaylightUI:Get("Buffs", "settings.scale"), nil, "the old setting is gone")
    T.eq(DaylightUI:Get("Buffs", "settings.debuff.scale"), nil)
end)

T.test("buffs: the anchors make room at the bars' drawn size, wheel included", function()
    login({ infopanel = true })
    local W = stub.buffs.Widgets
    DaylightUI.Movers.SetPieceScale("buffs.debuff", 1.5)
    stub.RunTimers()
    local a = { DaylightUIDebuffsAnchor:GetPoint(1) }
    T.near(a[5], W.Height(36) * 1.5, 0.001)
end)

T.test("buffs: attached, a moved bar still follows the panel; detached, it keeps its spot", function()
    login({ infopanel = true, before = function()
        DaylightUIDB = { positions = { ["buffs.buff"] = { 100, 200 } } }
    end })
    local h = { DaylightUIBuffsHolder:GetPoint(1) }
    T.eq(h[2], DaylightUIBuffsAnchor, "attached by default: the saved spot is ignored")
    T.falsy(DaylightUI.Movers.Get("buffs.buff").suspended == false, "no unlock handle")
    DaylightUI:Set("Buffs", "settings.attach", false)
    stub.RunTimers()
    h = { DaylightUIBuffsHolder:GetPoint(1) }
    T.eq(h[1], "CENTER", "detached: back to where it was moved")
    T.eq(h[4], 100)
    local d = { DaylightUIDebuffsHolder:GetPoint(1) }
    T.eq(d[2], DaylightUIDebuffsAnchor, "the debuffs keep their own setting")
    T.truthy(DaylightUI.Movers.Get("buffs.debuff").suspended, "still attached")
    DaylightUI:Set("Buffs", "settings.debuff.attach", false)
    stub.RunTimers()
    T.falsy(DaylightUI.Movers.Get("buffs.debuff").suspended, "debuffs detached on their own")
    DaylightUI:Set("Buffs", "settings.attach", true)
    stub.RunTimers()
    h = { DaylightUIBuffsHolder:GetPoint(1) }
    T.eq(h[2], DaylightUIBuffsAnchor, "attached again")
end)

T.test("buffs: detached for the first time, a bar stays where it was beside the panel", function()
    login({ infopanel = true })
    DaylightUIBuffsHolder.__center = { UIParent:GetWidth() / 2 + 300, UIParent:GetHeight() / 2 + 250 }
    DaylightUIDebuffsHolder.__center = { UIParent:GetWidth() / 2 + 300, UIParent:GetHeight() / 2 + 100 }
    DaylightUI:Set("Buffs", "settings.attach", false)
    DaylightUI:Set("Buffs", "settings.debuff.attach", false)
    stub.RunTimers()
    local h = { DaylightUIBuffsHolder:GetPoint(1) }
    T.eq(h[1], "CENTER", "buffs: on their own spot")
    T.truthy(math.abs(h[4] - 300) < 1 and math.abs(h[5] - 250) < 1, "buffs: where they were, not the mover default")
    local d = { DaylightUIDebuffsHolder:GetPoint(1) }
    T.truthy(math.abs(d[4] - 300) < 1 and math.abs(d[5] - 100) < 1, "debuffs: where they were")
end)

T.test("buffs: without the info panel, the screen's top-right corner", function()
    login()
    local p = { DaylightUIBuffsAnchor:GetPoint(1) }
    T.eq(p[2], UIParent)
    T.eq(p[1], "TOPRIGHT"); T.eq(p[3], "TOPRIGHT")
    local d = { DaylightUIDebuffsAnchor:GetPoint(1) }
    T.eq(d[2], DaylightUIBuffsAnchor, "debuffs below the buffs")
    T.truthy(d[5] < 0)
end)

T.test("buffs: a bigger debuff icon keeps its bottom edge on the panel's", function()
    login({ infopanel = true })
    DaylightUI:Set("Buffs", "settings.debuff.iconSize", 40)
    stub.RunTimers()
    local a = { DaylightUIDebuffsAnchor:GetPoint(1) }
    T.eq(a[5], stub.buffs.Widgets.Height(40))
end)

T.test("buffs: a size change re-lays the groups and restyles the buttons", function()
    local BL = login()
    DaylightUI:Set("Buffs", "settings.iconSize", 20)
    stub.RunTimers()
    T.eq(group("priest").layout.elementWidth, 20)
    T.eq(group("priest").button:GetWidth(), 20)
    DaylightUI:Set("Buffs", "settings.debuff.iconSize", 30)
    stub.RunTimers()
    T.eq(DaylightUIDebuffs.__groups.debuffs.layout.elementWidth, 30)
    T.eq(DaylightUIDebuffs.__groups.debuffs.button:GetWidth(), 30)
    T.eq(group("priest").layout.elementWidth, 20, "the buffs keep theirs")
end)

T.test("buffs: in combat, restyling the client's buttons waits for combat to end", function()
    local BL = login()
    stub.EnterCombat()
    BL.Bar:Restyle()
    T.truthy(BL.Bar.restylePending)
    stub.LeaveCombat()
    T.falsy(BL.Bar.restylePending)
end)

T.test("buffs: a consolidated category collapses to one icon with a count", function()
    local BL = login({ before = function()
        stub.SetAuras("player", "HELPFUL", {
            { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 },
            { name = "Divine Spirit", spellId = 14752, icon = 2, expirationTime = 2100 },
        })
    end })
    BL.Categories.SetConsolidate("priest", true)
    stub.RunTimers()
    T.eq(group("priest").max, 1, "one icon")
    T.truthy(BL.Bar.consolidated.priest)
    local badge = group("priest").button.Badge
    T.eq(badge.__text or badge:GetText(), 2, "how many it holds")
end)

T.test("buffs: the game's buff frames are hidden, and back when the option is off", function()
    login()
    T.falsy(BuffFrame:IsShown(), "buffs hidden")
    T.falsy(DebuffFrame:IsShown(), "debuffs hidden")
    DaylightUI:Set("Buffs", "settings.hideBlizzardFrames", false)
    stub.RunTimers()
    T.truthy(BuffFrame:IsShown())
end)

-- The game re-shows its aura frames with SetShown (AuraFrameEditModeMixin:UpdateShownState)
-- or Show (Edit Mode). Neither has an OnShow in the game's XML. Both are caught
-- through a script hook, never a hook on the frame's own Show method.
T.test("buffs: the game's buff frames, re-shown by the game, hide again at once (script hook, no method hook)", function()
    local gameRan = 0
    login({ before = function()
        DebuffFrame:SetScript("OnShow", function() gameRan = gameRan + 1 end)
    end })
    T.isnil(rawget(BuffFrame, "Show"), "no hook on BuffFrame's own Show")
    T.isnil(rawget(DebuffFrame, "Show"), "no hook on DebuffFrame's own Show")
    BuffFrame:SetShown(true)
    T.falsy(BuffFrame:IsShown(), "SetShown(true) is undone in the same call")
    DebuffFrame:Show()
    T.falsy(DebuffFrame:IsShown(), "Show() is undone in the same call")
    T.truthy(gameRan > 0, "the game's own OnShow still runs")
    stub.EnterCombat()
    BuffFrame:Show()
    T.truthy(BuffFrame:IsShown(), "left alone in combat")
    stub.LeaveCombat()
    stub.RunTimers()
    T.falsy(BuffFrame:IsShown(), "hidden again when the fight ends")
end)

T.test("buffs: shaman imbues get our own buttons, in the weapon color", function()
    local BL = login({ before = function()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    end })
    BL.Categories.SetStyle("weapon", "gradient")
    BL.Bar:UpdateWeapons()
    local b = DaylightUIBuffsWeapons.buttons[1]
    T.truthy(b and b:IsShown(), "one weapon button")
    T.eq(b:GetWidth(), 30)
    local a = DaylightUI.Gradients.PaintRGBOf(BL.Categories.Pair("weapon"))
    T.near(b.Edge.__gradient[2].r, a[1], 1e-6, "the weapon pair")
    T.eq(b.Duration.__text or b.Duration:GetText(), "10m")
end)

-- The game's secure "cancelaura" by weapon slot errors on Forever: its
-- SecureTemplates.lua reads CANCELABLE_ITEMS, which this client never defines
-- (found from a player's right-click), and CancelTemporaryEnchantment is restricted
-- to the game's own code. So the imbue icons are plain buttons.
T.test("buffs: an imbue button is no secure cancel button (the game's cancel by slot errors here)", function()
    local BL = login({ before = function()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    end })
    BL.Bar:UpdateWeapons()
    local b = DaylightUIBuffsWeapons.buttons[1]
    T.isnil(b:GetAttribute("type2"), "no cancelaura")
    T.isnil(b:GetAttribute("target-slot"))
    T.falsy(b:IsProtected(), "plain")
    T.falsy(DaylightUIBuffsWeapons:IsProtected(), "so the strip isn't protected either")
end)

-- Plain events ride the core's DUI.RegisterEvent. The unit events about you
-- (UNIT_AURA, UNIT_INVENTORY_CHANGED) stay filtered to the player.
T.test("buffs: only your own item and aura changes reach the bar, not a party member's", function()
    local BL = login()
    local n, real = 0, BL.Bar.UpdateWeapons
    BL.Bar.UpdateWeapons = function(...) n = n + 1; return real(...) end
    stub.FireEvent("UNIT_INVENTORY_CHANGED", "party1")
    T.eq(n, 0, "a party member's gear change")
    stub.FireEvent("UNIT_INVENTORY_CHANGED", "player")
    T.eq(n, 1, "yours")
    BL.Bar.UpdateWeapons = real
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: a shaman imbue cast mid-fight shows at once, the buffs making room", function()
    local BL = login()
    for _ = 1, 70 do stub.RunOnUpdate(DaylightUIBuffsWeapons, 1 / 60) end
    stub.EnterCombat()
    stub.SetWeaponEnchants({ { slot = 0, timeLeft = 1800000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    stub.FireEvent("WEAPON_ENCHANT_CHANGED")
    local b = DaylightUIBuffsWeapons.buttons[1]
    T.truthy(b and b:IsShown() and b:GetAlpha() == 1, "the imbue's icon")
    T.eq(b.Duration.__text or b.Duration:GetText(), "30m")
    T.truthy(BL.Bar.weaponWidth > 0, "the strip grew")
    local p, rel, rp, x = DaylightUIBuffs:GetPoint(1)
    T.eq(rel, BL.Bar.holder, "the container hangs off the holder, never the strip (that would lock the strip in a fight)")
    T.eq(p, "TOPRIGHT"); T.eq(rp, "TOPRIGHT")
    T.near(x, -BL.Bar.weaponWidth, 1e-6, "pushed past the strip")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Oils, stones and poisons use the container's own weapon slots, so one put on
-- mid-fight shows at once (a secure strip could only grow out of combat).
T.test("buffs: the container draws oils, stones and poisons, in the weapon color, ahead of the buffs", function()
    local BL = login()
    BL.Categories.SetStyle("weapon", "gradient")
    BL.Bar:Restyle()
    local c = DaylightUIBuffs
    for slot = 0, 2 do
        local e = c.__enchants[slot]
        T.truthy(e, "weapon slot " .. slot)
        T.eq(e.enabled, true)
        T.eq(e.opts.hidePermanent, true, "a permanent enchant isn't a buff")
        local b = e.button
        T.eq(b.__cancelButtons, "RightButtonUp", "right-click cancels it")
        local a = DaylightUI.Gradients.PaintRGBOf(BL.Categories.Pair("weapon"))
        T.near(b.Edge.__gradient[2].r, a[1], 1e-6, "the weapon pair")
        T.truthy(b.__time, "the client writes its time")
    end
    T.eq(c.__enchantLayout.placement, CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups)
    T.eq(c.__enchantLayout.elementWidth, BL.Bar:Size())
    T.deq(c.__enchantSort, { AuraContainerItemEnchantmentSortMethod.Slot, AuraContainerSortDirection.Normal }, "main hand first")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: an oil put on mid-fight is the container's (shows at once), never the strip's", function()
    local BL = login()
    for _ = 1, 70 do stub.RunOnUpdate(DaylightUIBuffsWeapons, 1 / 60) end
    stub.EnterCombat()
    stub.SetWeaponEnchants({ { slot = 0, timeLeft = 1800000, charges = 0, enchantIconID = 135, enchantType = 2 } })
    stub.FireEvent("WEAPON_ENCHANT_CHANGED")
    T.eq(DaylightUIBuffs.__enchants[0].enabled, true, "its slot is on: the client fills it")
    local strip = DaylightUIBuffsWeapons.buttons[1]
    T.falsy(strip and strip:IsShown() and strip:GetAlpha() > 0, "no second icon in our strip")
    T.eq(BL.Bar.weaponWidth, 0, "the buffs don't wait for room")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(BL.Bar.weaponWidth, 0, "nor after the fight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: a poison the container draws isn't drawn again in the strip, whatever its enchant type", function()
    -- A rogue poison: the container's slot shows it (the weapon's icon), and
    -- GetWeaponEnchantInfo lists it under another type. A shaman imbue on the off
    -- hand stays on the strip.
    local BL = login({ before = function()
        stub.SetWeaponEnchants({
            { slot = 0, timeLeft = 1800000, charges = 0, enchantIconID = 135, enchantType = 3, temporary = true, enchantID = 7 },
            { slot = 1, timeLeft = 1800000, charges = 0, enchantIconID = 136, enchantType = 3, enchantID = 8 } })
    end })
    BL.Bar:UpdateWeapons()
    T.eq(BL.Bar.weaponCount, 1, "one icon in the strip: the imbue")
    T.eq(DaylightUIBuffsWeapons.buttons[1].slot, 17, "on the off hand")
    T.eq(BL.Bar.enchantCount, 1, "the poison counts as the container's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: the hover's layout counts the container's weapon icons before the buffs", function()
    local BL = login({ before = function()
        auras()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 2 },
            { slot = 1, timeLeft = 600000, charges = 0, enchantIconID = 136, enchantType = 2 } })
    end })
    BL.Bar:UpdateWeapons()
    local flow = BL.Bar:CurrentFlow()
    T.eq(flow.elements[1].key, "enchants"); T.eq(flow.elements[2].key, "enchants")
    T.eq(flow.elements[3].key, "priest", "then the buffs")
    stub.SetWeaponEnchants({})
    BL.Bar:UpdateWeapons()
    T.eq(BL.Bar:CurrentFlow().elements[1].key, "priest", "gone: laid out again")
end)

T.test("buffs: hiding the Weapon category switches the weapon slots off, and back on", function()
    local BL = login({ before = function()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 2 } })
    end })
    BL.Categories.SetHidden("weapon", true)
    stub.RunTimers(); BL.Bar:UpdateWeapons()
    T.eq(DaylightUIBuffs.__enchants[0].enabled, false)
    T.eq(BL.Bar.enchantCount, 0, "nothing in the hover's layout")
    BL.Categories.SetHidden("weapon", false)
    stub.RunTimers(); BL.Bar:UpdateWeapons()
    T.eq(DaylightUIBuffs.__enchants[0].enabled, true)
    T.eq(BL.Bar.enchantCount, 1)
    -- Switched in a fight: only the container is asked, which is allowed then.
    stub.EnterCombat()
    BL.Categories.SetHidden("weapon", true)
    stub.RunTimers()
    T.eq(DaylightUIBuffs.__enchants[0].enabled, false)
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: an edge paints its category's gradient, or its one color", function()
    local BL = login()
    local W, G, Style = BL.Widgets, DaylightUI.Gradients, DaylightUI.Style
    local tex = CreateFrame("Frame"):CreateTexture()
    BL.Categories.SetStyle("priest", "gradient")
    W.PaintEdge(tex, "priest")
    local a, b = G.PaintRGBOf(BL.Categories.Pair("priest"))
    T.eq(tex.__gradient[1], G.Orientation())
    T.near(tex.__gradient[2].g, a[2], 1e-6); T.near(tex.__gradient[3].g, b[2], 1e-6)
    local mr = G.MidOf(BL.Categories.Pair("priest"))
    T.near((W.CategoryColor("priest")), mr, 1e-6, "text color: the pair's middle")

    BL.Categories.SetStyle("priest", "solid")
    W.PaintEdge(tex, "priest")
    local c = BL.Categories.Get("priest").color
    local r, g = Style.Soften(c[1], c[2], c[3])
    T.near(tex.__vertex[1], r, 1e-6, "solid: its color"); T.near(tex.__vertex[2], g, 1e-6)
    T.near((W.CategoryColor("priest")), r, 1e-6)

    local other = CreateFrame("Frame"):CreateTexture()
    W.PaintEdge(other, "other")
    W.PaintEdge(tex, "no-such-category")
    T.deq(tex.__vertex, other.__vertex, "unknown ids paint as Other")
    T.eq(tex.__gradient == nil, other.__gradient == nil)
end)

T.test("buffs: the preview shows sample buffs and hides the live bar", function()
    local BL = login()
    BL.RunCommand("test 50%")
    T.truthy(BL.Preview.Active())
    T.eq(DaylightUIBuffs:GetAlpha(), 0, "live bar out of the way")
    T.truthy(DaylightUIBuffsPreview:IsShown())
    BL.RunCommand("test off")
    T.falsy(BL.Preview.Active())
    T.eq(DaylightUIBuffs:GetAlpha(), 1)
end)

T.test("buffs: the preview shows sample debuffs too, soonest first, edged by dispel type", function()
    local BL = login()
    BL.RunCommand("test")
    T.truthy(DaylightUIDebuffsPreview:IsShown(), "sample debuffs")
    T.eq(DaylightUIDebuffs:GetAlpha(), 0, "the live debuffs out of the way")
    local shown = {}
    for _, b in ipairs(stub.Children(DaylightUIDebuffsPreview)) do
        if b.sample and b:IsShown() then shown[#shown + 1] = b end
    end
    T.eq(#shown, #BL.SAMPLE_DEBUFFS, "one of each")
    T.eq(shown[1].sample.name, "Frost Nova", "the soonest first")
    T.eq(shown[1]:GetWidth(), 36, "the debuff size")
    local c = BL.DISPEL_COLORS.Magic
    local r = DaylightUI.Style.Soften(c[1], c[2], c[3])
    T.near(shown[1].Edge.__vertex[1], r, 1e-6, "magic blue")
    BL.RunCommand("test off")
    T.falsy(DaylightUIDebuffsPreview:IsShown())
    T.eq(DaylightUIDebuffs:GetAlpha(), 1)
end)

T.test("buffs: DaylightUI's frame preview shows sample buffs too, and takes them away", function()
    local BL = login()
    DaylightUI.SetTestMode(true)
    T.truthy(BL.Preview.Active())
    DaylightUI.SetTestMode(false)
    T.falsy(BL.Preview.Active())
    -- A preview the player started stays.
    BL.RunCommand("test")
    DaylightUI.SetTestMode(true)
    DaylightUI.SetTestMode(false)
    T.truthy(BL.Preview.Active())
end)

T.test("buffs: /bl is ours unless the standalone addon is loaded, which is warned about", function()
    login()
    T.eq(SlashCmdList.DAYLIGHTUIBUFFS ~= nil, true, "/bl registered")
    login({ before = function() stub.loadedAddOns.BuffLedger = true end })
    T.isnil(SlashCmdList.DAYLIGHTUIBUFFS, "left to BuffLedger")
    T.truthy(stub.ChatContains("BuffLedger is also loaded"))
end)

T.test("buffs: options pages validate and the categories editor edits", function()
    local BL = login()
    for _, m in ipairs(stub.chat) do T.falsy(string.find(m, "Options (", 1, true), m) end
    DaylightUI.OptionsPanel.Show("Buffs.categories")
    local pf = DaylightUI.OptionsPanel.PageFrame()
    local row = pf.cards[1].rows[1]
    T.eq(row.count, #BL.Categories.Order(), "a line per category")
    local line = row.lines[5]
    local id = line.id
    line.hide:GetScript("OnClick")(line.hide)
    T.truthy(BL.Categories.Get(id).hidden, "hide pill")
    line.up:GetScript("OnClick")(line.up)
    T.eq(BL.Categories.Order()[4], id, "moved up")
    -- Delete takes two clicks.
    local del = row.lines[4].delete
    del:GetScript("OnClick")(del)
    T.truthy(BL.Categories.Get(id), "armed, not deleted")
    del:GetScript("OnClick")(del)
    T.isnil(BL.Categories.Get(id), "deleted")
    T.eq(row.count, #BL.Categories.Order(), "the list followed")
    -- Other can't be hidden, moved or deleted.
    local other = row.lines[row.count]
    T.eq(other.id, "other")
    T.eq(other.delete.enabled, false)
    T.eq(other.up.enabled, false)
    T.eq(other.down.enabled, false)
    T.truthy(row.lines[2].stripe and row.lines[2].stripe:IsShown(), "every other line striped")
    T.falsy(row.lines[1].stripe and row.lines[1].stripe:IsShown())
end)

T.test("buffs: moving a buff by name lands in the history", function()
    local BL = login()
    BL.Classify.Assign("Arcane Intellect", "world", "settings")
    DaylightUI.OptionsPanel.Show("Buffs.categories")
    local pf = DaylightUI.OptionsPanel.PageFrame()
    local history = pf.cards[3].rows[1]
    T.eq(history.count, 1)
    T.truthy(string.find(history.lines[1].text.__text or history.lines[1].text:GetText(), "Arcane Intellect", 1, true))
end)

T.test("buffs: the preview shows at most 20 sample buffs, unless a share is asked for", function()
    local BL = login()
    DaylightUI.SetTestMode(true)
    T.eq(#BL.Preview.Entries(), BL.PREVIEW_MAX, "the frame preview: 20")
    DaylightUI.SetTestMode(false)
    BL.RunCommand("test")
    T.eq(#BL.Preview.Entries(), 20, "the plain command too")
    BL.RunCommand("test 100%")
    T.truthy(#BL.Preview.Entries() > 20, "all of them when asked")
    BL.RunCommand("test off")
end)

T.test("buffs: time and count sizes, and times can be hidden", function()
    local BL = login()
    local W = BL.Widgets
    DaylightUI:Set("Buffs", "settings.timeSize", 15)
    DaylightUI:Set("Buffs", "settings.countSize", 13)
    T.eq(W.TimeSize(30), 15)
    T.eq(W.CountSize(), 13)
    DaylightUI:Set("Buffs", "settings.timeSize", 0)
    T.eq(W.TimeSize(30), math.max(8, math.floor(30 * 0.3 + 4 + 0.5)), "0 follows the icon")
end)

T.test("buffs: the time and count can wear their own outline, apart from General's", function()
    local BL = login()
    local W = BL.Widgets
    local btn = CreateFrame("Frame", nil, UIParent)
    W.Dress(btn)
    local function flags(fs) return select(3, fs:GetFont()) end
    DaylightUI:Set("general", "textOutline", "")
    stub.RunTimers()
    W.Font(btn.Duration, 12)
    T.eq(flags(btn.Duration), "", "Same as General: General's (none here)")
    DaylightUI:Set("Buffs", "settings.textOutline", "thick")
    stub.RunTimers()
    W.Font(btn.Duration, 12)
    T.eq(flags(btn.Duration), "THICKOUTLINE", "its own: thick while General has none")
    DaylightUI:Set("Buffs", "settings.textOutline", "thin")
    stub.RunTimers()
    W.Font(btn.Count, 10)
    T.eq(flags(btn.Count), "OUTLINE", "the stack count too")
    DaylightUI:Set("Buffs", "settings.textOutline", "general")
    DaylightUI:Set("general", "textOutline", "OUTLINE")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: a category's square opens the border editor; Solid and Gradient switch", function()
    local BL = login()
    for _, cid in ipairs(BL.Categories.Order()) do BL.Categories.SetStyle(cid, "gradient") end
    DaylightUI.OptionsPanel.Show("Buffs.categories")
    local row = DaylightUI.OptionsPanel.PageFrame().cards[1].rows[1]
    local line = row.lines[1]
    local id = line.id
    T.truthy(line.swatch.fill.__gradient, "the square shows the gradient")

    line.swatch:GetScript("OnClick")(line.swatch)
    local ed = BL.EdgeEditor.Frame()
    T.truthy(ed and ed:IsShown(), "open")
    T.eq(ed.id, id)
    T.truthy(ed.pair:IsShown(), "the gradient maker by default")
    T.falsy(ed.color:IsShown(), "no single swatch")

    ed.solid:GetScript("OnClick")(ed.solid)
    T.eq(BL.Categories.Get(id).style, "solid")
    T.truthy(ed.color:IsShown()); T.falsy(ed.pair:IsShown())
    T.truthy(ed.solid.active, "Solid lit")

    ed.gradient:GetScript("OnClick")(ed.gradient)
    T.eq(BL.Categories.Get(id).style, "gradient")

    line.swatch:GetScript("OnClick")(line.swatch)
    T.falsy(DaylightUI.Motion.Shown(ed), "a second click on the same square closes it")
    line.swatch:GetScript("OnClick")(line.swatch)
    T.truthy(DaylightUI.Motion.Shown(ed), "a third, mid-fade, opens it again")
    ed.close:GetScript("OnClick")(ed.close)
    stub.FinishFade(ed)
    T.falsy(ed:IsShown(), "its x fades it out")
    T.eq(#stub.errors, 0, "no errors: " .. tostring(stub.errors[1]))
end)

T.test("buffs: the bar fades through the fade engine; old settings move over", function()
    local p = { general = {}, modules = { Buffs = { settings = { fadeOOC = true, oocAlpha = 0.3,
                                                                 debuff = { fadeOOC = true } } } } }
    local DUI = stub.Load({ buffs = true })
    DUI.FadeUpgrade.Run(p)
    local s = p.modules.Buffs.settings
    T.eq(s.fade.mode, "ooc"); T.eq(s.fade.alpha, 0.3)
    T.eq(s.debuff.fade.mode, "ooc"); T.isnil(s.debuff.fade.alpha, "General's was the default")
    T.isnil(s.fadeOOC); T.isnil(s.debuff.fadeOOC)

    local BL = stub.buffs   -- the module namespace, the name test_buffs.lua uses
    DUI:Set("Buffs", "settings.fade.mode", "always")
    DUI:Set("Buffs", "settings.fade.delay", 0)
    stub.Advance(3)
    DUI.Fade.Step()
    for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    T.eq(BL.Bar.frame:GetAlpha(), 0, "faded")
end)

T.test("buffs: the imbue strip fades with the bar", function()
    local BL = login({ before = function()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    end })
    local DUI = DaylightUI
    BL.Bar:UpdateWeapons()
    DUI:Set("Buffs", "settings.fade.mode", "always")
    DUI:Set("Buffs", "settings.fade.alpha", 0.2)
    DUI:Set("Buffs", "settings.fade.delay", 0)
    stub.Advance(3)
    DUI.Fade.Step()
    for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    T.near(BL.Bar.frame:GetAlpha(), 0.2, 1e-6, "the bar faded")
    T.near(DaylightUIBuffsWeapons:GetAlpha(), 0.2, 1e-6, "the weapon strip with it")
    T.eq(#stub.errors, 0, "no errors: " .. tostring(stub.errors[1]))
end)

T.test("buffs: the live bar stays hidden under the preview while its fade runs", function()
    local BL = login()
    local DUI = DaylightUI
    DUI:Set("Buffs", "settings.fade.mode", "always")
    DUI:Set("Buffs", "settings.fade.alpha", 0.4)
    DUI:Set("Buffs", "settings.fade.delay", 0)
    BL.RunCommand("test 50%")
    stub.Advance(3)
    DUI.Fade.Step()
    for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    T.eq(DaylightUIBuffs:GetAlpha(), 0, "the fade doesn't bring the live bar back through the preview")
    BL.RunCommand("test off")
    DUI.Fade.Step()
    for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    T.truthy(DaylightUIBuffs:GetAlpha() > 0, "the fade has it again after the preview")
end)

T.test("buffs: a fade slider doesn't lay the bar out again (the fade engine owns it)", function()
    local BL = login()
    local DUI = DaylightUI
    local n = 0
    local apply = BL.Bar.ApplyAll
    BL.Bar.ApplyAll = function(...) n = n + 1; return apply(...) end
    DUI:Set("Buffs", "settings.fade.alpha", 0.3)
    DUI:Set("Buffs", "settings.debuff.fade.mode", "always")
    BL.Bar.ApplyAll = apply
    T.eq(n, 0)
end)

T.test("buffs: under a boss or PvP restriction aura changes wait instead of failing reads", function()
    local BL = login()
    local reads = 0
    local collect = BL.Auras.Collect
    BL.Auras.Collect = function(...) reads = reads + 1; return collect(...) end
    stub.SetRestriction("Encounter", true)
    stub.FireEvent("UNIT_AURA", "player")
    stub.FireEvent("UNIT_AURA", "player")
    T.eq(reads, 0, "no reads while auras are secret")
    stub.SetRestriction("Encounter", false)
    stub.RunTimers()
    BL.Auras.Collect = collect
    T.eq(reads, 1, "one read once it lifts")
end)

T.test("buffs: the mouse over a faded bar brings it back, in a fight too", function()
    local BL = login({ before = function()
        stub.SetAuras("player", "HELPFUL", {
            { name = "Power Word: Fortitude", spellId = 1243, icon = 1, expirationTime = 2000 },
            { name = "Divine Spirit", spellId = 14752, icon = 2, expirationTime = 2100 },
        })
        stub.SetAuras("player", "HARMFUL", { { name = "Poison", spellId = 99, icon = 3, expirationTime = 2000 } })
    end })
    local DUI = DaylightUI
    -- As in the game, the containers' geometry is the client's and secret.
    for _, bar in ipairs({ BL.Bar, BL.DebuffBar }) do
        function bar.frame:IsMouseOver() return stub.Secret(true) end
        function bar.frame:GetLeft() return stub.Secret(0) end
    end
    -- The holders are the addon's, with plain edges. Both bars grow left from the right edge.
    function BL.Bar.holder:GetRight() return 700 end
    function BL.Bar.holder:GetTop() return 800 end
    function BL.DebuffBar.holder:GetRight() return 700 end
    function BL.DebuffBar.holder:GetTop() return 600 end
    for _, p in ipairs({ "settings.fade.", "settings.debuff.fade." }) do
        DUI:Set("Buffs", p .. "mode", "always"); DUI:Set("Buffs", p .. "alpha", 0); DUI:Set("Buffs", p .. "delay", 0)
    end
    local function settle()   -- past the faded look a changed setting shows
        stub.Advance(3)
        DUI.Fade.Step()
        for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    end
    stub.cursorPos = { 100, 100 }
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 0, "faded")
    T.eq(BL.DebuffBar.frame:GetAlpha(), 0, "debuffs faded")

    stub.cursorPos = { 690, 790 }   -- on the first buff icon
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 1, "the mouse over a buff shows the bar")
    T.eq(BL.DebuffBar.frame:GetAlpha(), 0, "not the debuffs")
    stub.cursorPos = { 668, 790 }   -- in the gap between the two
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 1, "still shown")
    stub.cursorPos = { 600, 790 }   -- left of both icons
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 0, "off the icons: fades again")

    stub.cursorPos = { 690, 590 }
    settle()
    T.eq(BL.DebuffBar.frame:GetAlpha(), 1, "the mouse over a debuff shows that bar")

    stub.EnterCombat()
    stub.cursorPos = { 690, 790 }
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 1, "in a fight the last readable layout still answers")
    stub.LeaveCombat()

    DUI:Set("Buffs", "settings.fade.mouseover", false)
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 0, "show on mouseover off: stays faded")

    -- Hushed (at the campfire) the mouse shows the bar whatever its own fade says,
    -- including the default "never".
    DUI:Set("Buffs", "settings.fade.mode", "never")
    DUI:Set("Buffs", "settings.fade.mouseover", true)
    DUI.Fade.Hush("test", { "Buffs." })
    stub.cursorPos = { 100, 100 }
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 0, "hushed: gone")
    stub.cursorPos = { 690, 790 }
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 1, "hushed, fade never: the mouse over a buff shows the bar")
    DUI:Set("Buffs", "settings.fade.mouseover", false)
    settle()
    T.eq(BL.Bar.frame:GetAlpha(), 1, "hushed: the mouse shows it with show on mouseover off too")
    DUI.Fade.Unhush("test", true)
    T.eq(#stub.errors, 0, "no errors: " .. tostring(stub.errors[1]))
end)

-- Redundant work: each of these counts what the bars ask the game for, and failed
-- before the fix it guards.

-- Counts calls through tbl[name] (a C function or an addon one) until undone.
local function counting(tbl, name)
    local orig, c = tbl[name], { n = 0 }
    tbl[name] = function(...) c.n = c.n + 1; return orig(...) end
    c.undo = function() tbl[name] = orig end
    return c
end

-- Aura reads per filter (each pass reads every aura and one past the end).
local function auraReads()
    local orig, c = C_UnitAuras.GetAuraDataByIndex, { HELPFUL = 0, HARMFUL = 0 }
    C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
        c[filter] = (c[filter] or 0) + 1
        return orig(unit, index, filter)
    end
    c.undo = function() C_UnitAuras.GetAuraDataByIndex = orig end
    return c
end

T.test("buffs: the imbue strip looks once a second with no enchant, and shows one the moment it lands", function()
    login()
    local f = DaylightUIBuffsWeapons
    local reads = counting(C_Item, "GetWeaponEnchantInfo")
    for _ = 1, 600 do stub.Advance(1 / 60); stub.RunOnUpdate(f, 1 / 60) end   -- 10 s
    T.truthy(reads.n <= 11 * 3, "about once a second, three slots each: " .. reads.n)
    stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    stub.FireEvent("WEAPON_ENCHANT_CHANGED")
    local b = f.buttons[1]
    T.truthy(b and b:IsShown(), "shown at once, not at the next look")
    T.eq(b.Duration.__text or b.Duration:GetText(), "10m")
    reads.undo()
end)

T.test("buffs: a weapon enchant's time, icon and count are set only when they change", function()
    login({ before = function()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    end })
    local f = DaylightUIBuffsWeapons
    for _ = 1, 30 do stub.RunOnUpdate(f, 1 / 60) end
    local b = f.buttons[1]
    T.eq(b.Duration.__text or b.Duration:GetText(), "10m")
    local text, icon, alpha = counting(b.Duration, "SetText"), counting(b.Icon, "SetTexture"), counting(b, "SetAlpha")
    for _ = 1, 120 do stub.RunOnUpdate(f, 1 / 60) end   -- 2 s: ten ticks, still "10m"
    T.eq(text.n, 0, "the time")
    T.eq(icon.n, 0, "the icon")
    T.eq(alpha.n, 0, "its alpha")
    stub.SetWeaponEnchants({ { slot = 0, timeLeft = 59000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    for _ = 1, 15 do stub.RunOnUpdate(f, 1 / 60) end
    T.eq(b.Duration.__text or b.Duration:GetText(), "59s", "a new time is set")
    T.eq(text.n, 1)
    text.undo(); icon.undo(); alpha.undo()
end)

-- The game compares every item tooltip with what you wear when "always compare" is
-- on, and a weapon buff's tooltip is the worn weapon. So the game's own flag
-- (GameTooltip_SuppressAutomaticCompareItem, kept until it hides) must be set after
-- SetOwner, because a new owner hides it, which clears the flag.
T.test("buffs: a weapon buff's tooltip doesn't compare the weapon with itself", function()
    login({ before = function()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    end })
    local f = DaylightUIBuffsWeapons
    for _ = 1, 30 do stub.RunOnUpdate(f, 1 / 60) end
    local b = f.buttons[1]
    local orig, owned, suppressed = _G.GameTooltip_SuppressAutomaticCompareItem, false, nil
    local setOwner = GameTooltip.SetOwner
    GameTooltip.SetOwner = function(...) owned = true; return setOwner(...) end
    _G.GameTooltip_SuppressAutomaticCompareItem = function(tip) suppressed = owned and tip == GameTooltip end
    b:GetScript("OnEnter")(b)
    _G.GameTooltip_SuppressAutomaticCompareItem = orig
    GameTooltip.SetOwner = setOwner
    T.eq(suppressed, true, "the game's no-compare flag, set after SetOwner")
end)

T.test("buffs: the hover over a faded bar reads the auras and lays the icons out once per change", function()
    local BL = login({ before = function()
        auras()
        stub.SetAuras("player", "HARMFUL", { { name = "Poison", spellId = 99, icon = 3, expirationTime = 2000 } })
    end })
    local DUI = DaylightUI
    -- Fade off (the default): an aura change reads no debuffs.
    local reads = auraReads()
    stub.FireEvent("UNIT_AURA", "player")
    stub.RunTimers()                                -- the learn runs the frame after (one for a burst)
    T.eq(reads.HARMFUL, 0, "nothing asks for the debuff count")
    T.eq(reads.HELPFUL, 3, "the buffs once (two and the end)")
    reads.undo()

    for _, p in ipairs({ "settings.fade.", "settings.debuff.fade." }) do DUI:Set("Buffs", p .. "mode", "always") end
    stub.RunTimers()
    stub.Advance(3)   -- past the look a changed setting gives
    DUI.Fade.Step()
    reads = auraReads()
    local flows = counting(BL.Layout, "Flow")
    for _ = 1, 20 do DUI.Fade.Step() end
    T.eq(flows.n, 0, "the layout is kept")
    T.eq(reads.HELPFUL + reads.HARMFUL, 0, "no aura read")
    stub.FireEvent("UNIT_AURA", "player")
    stub.RunTimers()
    for _ = 1, 20 do DUI.Fade.Step() end
    T.eq(flows.n, 1, "the buffs' once after a change (the debuffs', with the same count, kept)")
    T.eq(reads.HELPFUL, 3, "the buffs read once for that change")
    T.eq(reads.HARMFUL, 2, "the debuffs once (one and the end)")
    DUI:Set("Buffs", "settings.columns", 1)
    T.near(BL.Bar:CurrentFlow().width, 30, 1e-6, "a setting lays it out again at once: one column")
    flows.undo(); reads.undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("buffs: a burst of aura changes in one frame (a rebuff before a pull) is read once", function()
    login({ before = function() auras() end })
    stub.RunTimers()
    local reads = auraReads()
    for _ = 1, 5 do stub.FireEvent("UNIT_AURA", "player") end
    T.eq(reads.HELPFUL, 0, "nothing read in the burst itself")
    stub.RunTimers()
    T.eq(reads.HELPFUL, 3, "one read the frame after (two and the end)")
    reads.undo()
end)

T.test("buffs: an aura change with a combined category reads the auras once, and no weapon tooltips", function()
    local BL = login({ before = function()
        auras()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    end })
    BL.Categories.SetConsolidate("priest", true)
    stub.RunTimers()
    local tips = { n = 0 }
    _G.C_TooltipInfo = { GetInventoryItem = function() tips.n = tips.n + 1 end }
    local reads, cats = auraReads(), counting(BL.Spells, "CategoryOf")
    stub.FireEvent("UNIT_AURA", "player")
    stub.RunTimers()                                -- the learn runs the frame after (one for a burst)
    T.eq(reads.HELPFUL, 3, "once (two and the end)")
    T.eq(tips.n, 0, "no enchant names")
    T.eq(cats.n, 0, "the spells' categories are kept")
    local badge = group("priest").button.Badge
    T.eq(badge.__text or badge:GetText(), 2, "the count still shows")
    reads.undo(); cats.undo()
    _G.C_TooltipInfo = nil
end)

T.test("buffs: the slide's look at the bar after an aura change reads the buffs no second time", function()
    local BL = login({ before = auras })
    stub.Advance(3)
    local reads = auraReads()
    landed(2, 14752)
    T.truthy(BL.Feel.snaps[BL.Bar], "a look taken")
    T.eq(reads.HELPFUL, 3, "one read for the change and the look")
    reads.undo()
end)

T.test("buffs: roster changes re-apply the groups only when in a group or raid changes", function()
    local BL = login()
    local applied = counting(BL.Bar, "ApplyGroups")
    for _ = 1, 5 do stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers() end
    T.eq(applied.n, 0, "same state")
    stub.SetGroup(true, false)
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.eq(applied.n, 1, "joined a group")
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.eq(applied.n, 1)
    stub.SetGroup(true, true)
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.eq(applied.n, 2, "now a raid")
    applied.undo()
end)

T.test("buffs: debuff edges use the dispel colors picked on the unit frames' Colors page", function()
    local DUI = stub.Load({ buffs = true, module = true })
    local BL = stub.buffs
    T.deq(BL.DispelColor("Magic"), BL.DISPEL_COLORS.Magic, "the default matches")
    DUI:Set("UnitFrames", "colors.dispelMagic", { 1, 0, 0 })
    T.deq(BL.DispelColor("Magic"), { 1, 0, 0 }, "a picked color carries over")
    T.deq(BL.DispelColor("Bleed"), BL.DISPEL_COLORS.Bleed, "no picker: ours")
end)

T.test("buffs: with Float on, an aura gained or lost wakes its bar; a refresh or a loading screen doesn't", function()
    login()
    local woke = {}
    local wake = DaylightUI.Fade.Wake
    DaylightUI.Fade.Wake = function(key) woke[#woke + 1] = key end
    local function heard() local t = woke; woke = {}; table.sort(t); return table.concat(t, " ") end
    landed(1, 1243)
    T.eq(heard(), "", "Float off: nothing")
    DaylightUI:Set("Buffs", "settings.fade.mode", "float")
    landed(2, 1243)
    T.eq(heard(), "Buffs.buffs", "a buff gained: the buffs")
    landed(3, 589, true)
    T.eq(heard(), "Buffs.debuffs", "a debuff gained: the debuffs")
    left(3)
    T.eq(heard(), "Buffs.debuffs", "the debuff gone: its bar")
    left(2)
    T.eq(heard(), "Buffs.buffs")
    left(1)
    T.eq(heard(), "Buffs.buffs Buffs.debuffs", "one from before: both")
    stub.FireEvent("UNIT_AURA", "player", { updatedAuraInstanceIDs = { 4 } })
    T.eq(heard(), "", "a refresh: nothing")
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
    T.eq(heard(), "", "a loading screen: nothing")
    stub.FireEvent("UNIT_AURA", "player", stub.Secret({ addedAuras = {} }))
    T.eq(heard(), "Buffs.buffs Buffs.debuffs", "unreadable: both")
    DaylightUI.Fade.Wake = wake
end)

-- A player's error between the setup guide's Finish and its reload. Finish rebuilt
-- the profile in use (Profiles.Replace) and the module was pointed at the new
-- tables, but the buff groups, only filled in as the module started, weren't
-- there: "Categories.lua:130: attempt to index a nil value" from the weapon strip,
-- every tick until the reload.
T.test("buffs: the profile in use made over again keeps its buff groups; the weapon strip goes on", function()
    local BL = login({ before = function()
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 600000, charges = 0, enchantIconID = 135, enchantType = 3 } })
    end })
    local DUI = DaylightUI
    local fresh = DUI.Profiles.ReadyData("DPS/Tank")
    T.truthy(fresh, "a clean profile")
    DUI.Profiles.Replace(DUI.DB.ActiveName(), fresh)
    T.noerror(function() stub.RunOnUpdate(DaylightUIBuffsWeapons, 1) end, "the strip ticks on")
    T.truthy(BL.Categories.Get("weapon"), "the shipped groups are there")
    T.truthy(#BL.Categories.Order() > 0, "in their order")
    local b = DaylightUIBuffsWeapons.buttons[1]
    T.truthy(b and b:IsShown(), "the imbue still shows")
end)
