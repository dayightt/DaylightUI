local stub = require("stub")

local function open(id)
    local DUI, ns = stub.Load({ module = true })
    DUI.OptionsPanel.Show(id)
    return DUI, DUI.OptionsPanel, ns
end

-- The first shown hotspot with this part label.
local function spot(P, label)
    for _, b in ipairs(P.Strip().Hotspots()) do
        if b.part.label == label then return b end
    end
end

-- How far down the settings start (the scroll frame's top offset).
local function scrollTop(P)
    local _, _, _, _, y = P.PageFrame():GetParent():GetPoint(1)
    return y
end

T.test("a frame's page shows its live sample above the settings; other pages don't", function()
    local DUI, P = open("UnitFrames.colors")
    T.falsy(P.Strip():IsShown(), "Colors has no frame")
    P.Show("UnitFrames.target")
    local strip, S = P.Strip(), DUI.SampleStrip
    T.truthy(strip:IsShown())
    T.truthy(strip:GetHeight() > 0 and strip:GetHeight() <= S.MAX_HEIGHT + 2 * S.PAD + S.HINT_HEIGHT,
        "height " .. strip:GetHeight())
    local _, _, _, _, stripTop = strip:GetPoint(1)
    T.truthy(scrollTop(P) <= stripTop - strip:GetHeight(), "the settings start under it")
    T.eq(strip.Sample().f.spec.unit, "target")
    P.Show("appearance")
    T.falsy(P.Strip():IsShown())
    T.eq(#stub.errors, 0)
end)

T.test("each page keeps its own sample; changing a setting redraws it at once", function()
    local DUI, P = open("UnitFrames.target")
    local s = P.Strip().Sample()
    DUI:Set("UnitFrames", "target.width", 250)
    T.near(s.f:GetWidth(), 250, 2, "redrawn with the new width")
    P.Show("UnitFrames.focus")
    T.eq(P.Strip().Sample().f.spec.unit, "focus")
    P.Show("UnitFrames.target")
    T.eq(P.Strip().Sample(), s, "built once per page")
end)

T.test("in combat too: the sample redraws and nothing errors", function()
    local DUI, P = open("UnitFrames.player")
    stub.EnterCombat()
    DUI:Set("UnitFrames", "player.width", 240)
    T.near(P.Strip().Sample().f:GetWidth(), 240, 2)
    T.eq(#stub.errors, 0)
    stub.LeaveCombat()
end)

T.test("every part of the sample has a hotspot; hovering outlines it", function()
    local DUI, P = open("UnitFrames.target")
    local name, bar = spot(P, "Name"), spot(P, "Health bar")
    T.truthy(name and bar and spot(P, "Debuffs"), "the name, the health bar, the debuffs")
    T.truthy(name:GetFrameLevel() > bar:GetFrameLevel(), "the name over the bar")
    T.truthy(bar:GetFrameLevel() > P.Strip().Sample().f:GetFrameLevel(), "over the sample itself")
    name:GetScript("OnEnter")(name)
    T.truthy(name.outline:IsShown())
    name:GetScript("OnLeave")(name)
    T.falsy(name.outline:IsShown())
end)

T.test("clicking a part scrolls to its settings and lights them up", function()
    local DUI, P = open("UnitFrames.target")
    local scroll = P.PageFrame():GetParent()
    T.eq(scroll:GetVerticalScroll(), 0)
    spot(P, "Name"):Click()
    T.truthy(scroll:GetVerticalScroll() > 0, "down to the Text card")
    local _, row = P.PageFrame().Find("target.showName")
    T.truthy(row.flash and row.flash:IsShown(), "lit up")
    local _, size = P.PageFrame().Find("targetText.name")
    T.truthy(size.flash and size.flash:IsShown(), "its size too")
    T.eq(P.Current(), "UnitFrames.target", "on the same page")
end)

T.test("a search is cleared first", function()
    local DUI, P = open("UnitFrames.target")
    P.Search("absorbs")
    T.truthy(P.Results():IsShown(), "the results in the page's place")
    spot(P, "Health bar"):Click()
    T.falsy(P.Results():IsShown(), "back on the page")
    T.eq(P.Current(), "UnitFrames.target")
    local _, width = P.PageFrame().Find("target.width")
    T.truthy(width:IsShown())
    T.truthy(width.flash:IsShown())
end)

T.test("a setting hidden right now: the click lands on its card", function()
    local DUI, P = open("UnitFrames.target")
    local pf = P.PageFrame()
    local card, row = pf.Find("target.nameCustom")
    T.falsy(row:IsShown(), "only with a custom name color")
    local lit = P.JumpTo({ "target.nameCustom" })
    T.eq(#lit, 0, "nothing to light up")
    T.near(pf:GetParent():GetVerticalScroll(), math.max(0, card.offsetY - P.JUMP_MARGIN), 1e-6, "its card at the top")
end)

T.test("a redraw never leaves an outline on the wrong part", function()
    local DUI, P = open("UnitFrames.target")
    local b = spot(P, "Name")
    b:GetScript("OnEnter")(b)
    DUI:Set("UnitFrames", "target.showPercent", false)
    for _, h in ipairs(P.Strip().Hotspots()) do T.falsy(h.outline:IsShown(), h.part.label) end
end)

T.test("the party page shows its members, each one clickable", function()
    local DUI, P, ns = open("UnitFrames.party")
    T.truthy(P.Strip():IsShown())
    local n = 0
    for _, b in ipairs(P.Strip().Hotspots()) do
        if b.part.label == "Health bar" then n = n + 1 end
    end
    T.eq(n, ns.PageSample.PARTY_COUNT)
    T.eq(#stub.errors, 0)
end)

T.test("a zoom slider at the preview's bottom right, on previews that zoom", function()
    local DUI, P = open("UnitFrames.raid")
    local z = P.Strip().ZoomControl()
    T.truthy(z:IsShown(), "the Raid preview zooms")
    local _, _, rp = z:GetPoint(1)
    T.eq(rp, "BOTTOMRIGHT")
    z.control.slider:GetScript("OnValueChanged")(z.control.slider, 2)
    T.eq(P.Strip().Sample().holder:GetScale(), 2, "redrawn at once")
    P.Show("UnitFrames.target")
    T.truthy(P.Strip().ZoomControl():IsShown(), "the target's preview zooms too")
    T.eq(P.Strip().Sample().Zoom(), 1, "from 1x: its own zoom")
    P.Show("UnitFrames.raid")
    T.eq(P.Strip().Sample().Zoom(), 2, "kept for the session")
    T.eq(#stub.errors, 0)
end)

T.test("the sample gets more room in a taller window, within its bounds", function()
    local DUI = open("UnitFrames.target")
    local S = DUI.SampleStrip
    T.eq(S.Room(680), 204, "30% of the default window")
    T.eq(S.Room(300), S.MIN_HEIGHT, "never less")
    T.eq(S.Room(2000), S.MAX_HEIGHT, "never more")
end)

-- Design mode. The fake game doesn't lay frames out, so a piece's tile is
-- put on the fake screen by hand before a drag is aimed at its dots.
local function onScreen(owner)
    owner.GetLeft = function() return 300 end
    owner.GetTop = function() return 500 end
end

-- The cursor over owner's px x, y (top left, y down).
local function cursorAt(owner, x, y)
    local s = owner:GetEffectiveScale()
    stub.cursorPos = { (owner:GetLeft() + x) * s, (owner:GetTop() - y) * s }
end

-- Presses on hotspot b, moves to (toX, toY) of the piece's tile, lets go.
-- Returns how many dots showed during the drag.
local function drag(P, b, toX, toY)
    local owner = b.part.move and b.part.move.owner or P.Strip().Sample().members[1]
    onScreen(owner)
    cursorAt(owner, 1, 1)
    b:GetScript("OnMouseDown")(b, "LeftButton")
    cursorAt(owner, toX, toY)
    stub.RunOnUpdate(P.Strip(), 0.016)
    local during = P.Strip().DotsShown()
    b:GetScript("OnMouseUp")(b, "LeftButton")
    return during
end

local function dot(part, name)
    for _, d in ipairs(part.move.dots) do if d.spot == name then return d end end
end

T.test("Design mode: a switch on frame pages whose preview has movable pieces, kept per page", function()
    local DUI, P = open("UnitFrames.raid")
    T.truthy(P.DesignSwitch():IsShown())
    T.falsy(P.Strip().design, "off at first")
    P.SetDesign(true)
    T.truthy(P.Strip().design)
    P.Show("UnitFrames.colors")
    T.falsy(P.DesignSwitch():IsShown(), "no preview, no switch")
    P.Show("UnitFrames.raid")
    T.truthy(P.Strip().design, "remembered for the session")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode on every frame page: pieces that only resize count too (the player's bars)", function()
    local DUI, P = open("UnitFrames.player")
    for _, id in ipairs({ "player", "target", "focus", "targettarget", "pet", "party", "raid" }) do
        P.Show("UnitFrames." .. id)
        T.truthy(P.DesignSwitch():IsShown(), id)
    end
    P.Show("UnitFrames.player")
    local sized
    for _, b in ipairs(P.Strip().Hotspots()) do
        if b.part.label == "Health bar" and b.part.size then sized = b.part.size end
    end
    T.truthy(sized, "the player's health bar resizes")
    T.eq(sized.keys.w, "player.width"); T.eq(sized.keys.h, "player.height")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode off: a drag moves nothing, a click still jumps", function()
    local DUI, P = open("UnitFrames.raid")
    local b = spot(P, "Debuffs")
    local before = DUI:Get("UnitFrames", "raid.auras.debuffs.spot")
    T.eq(drag(P, b, 1, 1), 0, "no dots")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.spot"), before)
    spot(P, "Debuffs"):Click()
    local _, row = P.PageFrame().Find("raid.auras.debuffs.spot")
    T.truthy(row.flash and row.flash:IsShown(), "jumped to its settings")
end)

T.test("Design mode: a plain click still jumps and saves nothing", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    local before = DUI:Get("UnitFrames", "raid.auras.debuffs.spot")
    spot(P, "Debuffs"):Click()
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.spot"), before)
    local _, row = P.PageFrame().Find("raid.auras.debuffs.spot")
    T.truthy(row.flash and row.flash:IsShown())
end)

T.test("Design mode: dropped on a dot, the piece snaps to that spot", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    local b = spot(P, "Debuffs")
    local d = dot(b.part, "topleft")
    T.eq(drag(P, b, d.x + 2, d.y + 1), 17, "every dot showed while dragging")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.spot"), "topleft")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.x"), 0)
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.y"), 0)
    T.eq(P.Strip().DotsShown(), 0, "gone after")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: dropped away from the dots, it keeps the nearest spot and the offset", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    local b = spot(P, "Debuffs")
    local c = dot(b.part, "center")
    drag(P, b, c.x + 10, c.y)
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.spot"), "center")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.x"), 10, "past the magnet, nearer the middle than the side")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.y"), 0)
end)

T.test("Design mode: the health bar can't be dragged, only picked", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    local w = DUI:Get("UnitFrames", "raid.width")
    T.eq(drag(P, spot(P, "Health bar"), 30, 10), 0)
    T.eq(DUI:Get("UnitFrames", "raid.width"), w)
    T.eq(P.Strip().Selected(), "Health bar")
end)

T.test("Design mode in combat: the drag saves at once, the real tiles follow after the fight", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    stub.EnterCombat()
    local b = spot(P, "Crowd control")
    local d = dot(b.part, "top")
    drag(P, b, d.x, d.y)
    T.eq(DUI:Get("UnitFrames", "raid.auras.cc.spot"), "top")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(#stub.errors, 0)
end)

-- Drags grip g by dx, dy of its piece's own px (dy down), then lets go.
local function gripDrag(P, g, dx, dy)
    local s = g.part.region:GetEffectiveScale()
    stub.cursorPos = { 100, 100 }
    g:GetScript("OnMouseDown")(g, "LeftButton")
    stub.cursorPos = { 100 + dx * s, 100 - dy * s }
    stub.RunOnUpdate(P.Strip(), 0.016)
    local label = P.Strip().GripLabel()
    local live = label:IsShown() and label:GetText() or nil
    g:GetScript("OnMouseUp")(g, "LeftButton")
    return live
end

T.test("Design mode: the picked piece's corner grip resizes it, within its slider's limits", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    spot(P, "Debuffs"):Click()
    local g = P.Strip().Grips().s
    T.truthy(g and g:IsShown(), "the picked piece has its grip")
    local start = DUI:Get("UnitFrames", "raid.auras.debuffs.size")
    T.eq(gripDrag(P, g, 6, 0), tostring(start + 6), "the size shows live while dragging")
    T.falsy(P.Strip().GripLabel():IsShown(), "and goes once let go")
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.size"), start + 6)
    gripDrag(P, P.Strip().Grips().s, 200, 0)
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.size"), 32, "no bigger than the slider goes")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: the health bar's edge grips resize the whole tile", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    spot(P, "Health bar"):Click()
    local w, h = DUI:Get("UnitFrames", "raid.width"), DUI:Get("UnitFrames", "raid.height")
    gripDrag(P, P.Strip().Grips().w, 6, 0)
    T.eq(DUI:Get("UnitFrames", "raid.width"), w + 6)
    gripDrag(P, P.Strip().Grips().h, 0, 4)
    T.eq(DUI:Get("UnitFrames", "raid.height"), h + 4, "pulled down: taller")
end)

T.test("a plain click on a grip saves nothing; grips only on the picked piece, only in Design mode", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    T.falsy(P.Strip().Grips().s:IsShown(), "nothing picked yet")
    spot(P, "Debuffs"):Click()
    local g = P.Strip().Grips().s
    local start = DUI:Get("UnitFrames", "raid.auras.debuffs.size")
    gripDrag(P, g, 0, 0)
    T.eq(DUI:Get("UnitFrames", "raid.auras.debuffs.size"), start)
    T.falsy(P.Strip().Grips().w:IsShown(), "debuffs have one size, not a width")
    P.SetDesign(false)
    T.falsy(P.Strip().Grips().s:IsShown(), "Design mode off: no grips")
end)

-- The page's cards showing now, by title.
local function shownCards(P)
    local out, n = {}, 0
    for _, card in ipairs(P.PageFrame().cards) do
        if card:IsShown() then out[card.group.label] = true; n = n + 1 end
    end
    return out, n
end

T.test("Design mode: the cards show only the picked piece's settings; nothing picked, a hint", function()
    local DUI, P = open("UnitFrames.raid")
    local _, all = shownCards(P)
    T.truthy(all >= 3, "Settings: the Basics tab's cards")
    P.SetDesign(true)
    local _, n = shownCards(P)
    T.eq(n, 0, "nothing picked: no cards")
    T.truthy(P.EmptyText():IsShown())
    T.eq(P.EmptyText():GetText(), DUI.SampleStrip.DESIGN_EMPTY)
    P.SetDesign(false)
    local _, back = shownCards(P)
    T.eq(back, all, "Design mode off: every card at once")
    T.falsy(P.EmptyText():IsShown())
    P.SetDesign(true)
    spot(P, "Debuffs"):Click()
    local shown
    shown, n = shownCards(P)
    T.eq(n, 1); T.truthy(shown["Debuffs"], "only the Debuffs card")
    T.falsy(P.EmptyText():IsShown())
    T.falsy(P.Chips():IsShown(), "no card chips in Design mode")
    spot(P, "Name"):Click()
    shown = shownCards(P)
    T.truthy(shown["Text"], "the name's card")
end)

T.test("Design mode: 'Every setting for this piece' goes back to Settings at that piece", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    spot(P, "Crowd control"):Click()
    local link = P.Strip().AllLink()
    T.truthy(link:IsShown())
    link:Click()
    T.falsy(P.Strip().design, "back in Settings")
    local _, row = P.PageFrame().Find("raid.auras.cc.spot")
    T.truthy(row.flash and row.flash:IsShown(), "at that piece's settings")
    P.Focus(nil)
    local _, n = shownCards(P)
    T.truthy(n > 3, "every card back")
end)

T.test("zooming the preview moves the settings up or down with it", function()
    local DUI, P = open("UnitFrames.raid")
    local strip = P.Strip()
    local z = strip.ZoomControl()
    z.control.slider:GetScript("OnValueChanged")(z.control.slider, 3)
    local tall, topTall = strip:GetHeight(), scrollTop(P)
    z.control.slider:GetScript("OnValueChanged")(z.control.slider, 1)
    T.truthy(strip:GetHeight() < tall, "the preview is shorter at 1x")
    T.near(topTall - scrollTop(P), strip:GetHeight() - tall, 0.01, "the settings moved up by as much: no blank space")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: the arrow keys nudge the picked piece, Shift by more, and saves", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    local strip, S = P.Strip(), DUI.SampleStrip
    T.falsy(strip.keys:IsKeyboardEnabled(), "nothing picked: the keys stay the game's")
    local b = spot(P, "Raid marker")
    T.truthy(b, "the marker's on the preview")
    b:GetScript("OnClick")(b)
    T.eq(strip.Selected(), "Raid marker")
    T.truthy(strip.keys:IsKeyboardEnabled(), "picked: the arrows are ours")
    local press = strip.keys:GetScript("OnKeyDown")
    press(strip.keys, "RIGHT")
    press(strip.keys, "UP")
    T.eq(DUI:Get("UnitFrames", "raid.markerX"), 1)
    T.eq(DUI:Get("UnitFrames", "raid.markerY"), 1)
    local shift = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    press(strip.keys, "LEFT")
    IsShiftKeyDown = shift
    T.eq(DUI:Get("UnitFrames", "raid.markerX"), 1 - S.NUDGE_BIG)
    press(strip.keys, "W")
    T.truthy(strip.keys:GetPropagateKeyboardInput(), "any other key goes on to the game")
    P.SetDesign(false)
    T.falsy(strip.keys:IsKeyboardEnabled(), "Design mode off: the keys go back")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: the health text drags, its one dot at home, and saves a nudge", function()
    local DUI, P = open("UnitFrames.raid")
    DUI:Set("UnitFrames", "raid.showPercent", true)
    P.SetDesign(true)
    local b = spot(P, "Health text")
    T.truthy(b and b.part.move, "it moves")
    T.eq(drag(P, b, 40, 20), 1, "its home's dot")
    T.truthy(DUI:Get("UnitFrames", "raid.healthTextX") ~= 0, "saved a nudge")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: the piece itself follows the cursor while dragged", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    local b = spot(P, "Raid marker")
    local region, owner = b.part.region, b.part.move.owner
    onScreen(owner)
    cursorAt(owner, 1, 1)
    b:GetScript("OnMouseDown")(b, "LeftButton")
    cursorAt(owner, 40, 20)
    stub.RunOnUpdate(P.Strip(), 0.016)
    local p, rel, _, x, y = region:GetPoint(1)
    local s = region:GetEffectiveScale()
    T.eq(p, "CENTER"); T.eq(rel, UIParent, "under the cursor, not at its spot")
    T.near(x, stub.cursorPos[1] / s, 0.01); T.near(y, stub.cursorPos[2] / s, 0.01)
    b:GetScript("OnMouseUp")(b, "LeftButton")
    local _, rel2 = region:GetPoint(1)
    T.truthy(rel2 ~= UIParent, "back on the tile once dropped")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: a row made of several icons (the target's debuffs) follows the cursor as one", function()
    local DUI, P = open("UnitFrames.target")
    P.SetDesign(true)
    local icons = {}
    for _, h in ipairs(P.Strip().Hotspots()) do
        if h:IsShown() and h.part.label == "Debuffs" then icons[#icons + 1] = h end
    end
    T.truthy(#icons >= 2, "the target's debuffs are one hotspot per icon")
    -- The fake game lays nothing out: put the icons in a row by hand.
    for i, h in ipairs(icons) do
        local cx = 100 + 20 * i
        h.part.region.GetCenter = function() return cx, 200 end
    end
    local b = icons[2]
    local owner = b.part.move.owner
    onScreen(owner)
    cursorAt(owner, 1, 1)
    b:GetScript("OnMouseDown")(b, "LeftButton")
    cursorAt(owner, 40, 20)
    stub.RunOnUpdate(P.Strip(), 0.016)
    local _, _, _, gx, gy = b.part.region:GetPoint(1)
    for i, h in ipairs(icons) do
        local p, rel, _, x, y = h.part.region:GetPoint(1)
        T.eq(p, "CENTER", "icon " .. i); T.eq(rel, UIParent, "icon " .. i .. " is lifted too")
        T.near(x, gx + 20 * (i - 2), 0.01, "icon " .. i .. " keeps its place in the row")
        T.near(y, gy, 0.01)
    end
    b:GetScript("OnMouseUp")(b, "LeftButton")
    for i, h in ipairs(icons) do
        T.truthy(select(2, h.part.region:GetPoint(1)) ~= UIParent, "icon " .. i .. " back on the frame")
    end
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: a grip resizes the preview live, and saves once let go", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    spot(P, "Health bar"):Click()
    local w = DUI:Get("UnitFrames", "raid.width")
    local fired = 0
    DUI.On("SettingChanged", function() fired = fired + 1 end)
    local g = P.Strip().Grips().w
    local s = g.part.region:GetEffectiveScale()
    stub.cursorPos = { 100, 100 }
    g:GetScript("OnMouseDown")(g, "LeftButton")
    stub.cursorPos = { 100 + 10 * s, 100 }
    stub.RunOnUpdate(P.Strip(), 0.016)
    local tile = P.Strip().Sample().members[1]
    T.near(tile:GetWidth(), w + 10, 1, "the preview's tile is wider while dragging")
    T.eq(fired, 0, "nothing saved yet: the real frames wait")
    g:GetScript("OnMouseUp")(g, "LeftButton")
    T.eq(DUI:Get("UnitFrames", "raid.width"), w + 10)
    T.truthy(fired > 0, "saved on release")
    T.eq(#stub.errors, 0)
end)

-- Escape mid-drag used to close the window with the grip still held, and the
-- next open kept writing the cursor's value into the settings.
T.test("Design mode: the window closing mid-drag saves the grip once and lets it go", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    spot(P, "Health bar"):Click()
    local w = DUI:Get("UnitFrames", "raid.width")
    local g = P.Strip().Grips().w
    local s = g.part.region:GetEffectiveScale()
    stub.cursorPos = { 100, 100 }
    g:GetScript("OnMouseDown")(g, "LeftButton")
    stub.cursorPos = { 100 + 10 * s, 100 }
    stub.RunOnUpdate(P.Strip(), 0.016)
    P.Frame():Hide()
    T.falsy(P.Strip():GetScript("OnUpdate"), "the drag ends with the window")
    T.eq(DUI:Get("UnitFrames", "raid.width"), w + 10, "saved, like a release")
    P.Show("UnitFrames.raid")
    stub.cursorPos = { 100 + 30 * s, 100 }
    if P.Strip():GetScript("OnUpdate") then stub.RunOnUpdate(P.Strip(), 0.016) end
    T.eq(DUI:Get("UnitFrames", "raid.width"), w + 10, "the cursor writes nothing after")
    T.eq(#stub.errors, 0)
end)

T.test("Design mode: pulling the power bar down thickens it and the tile by as much", function()
    local DUI, P = open("UnitFrames.raid")
    P.SetDesign(true)
    spot(P, "Power bar"):Click()
    local ph, h = DUI:Get("UnitFrames", "raid.powerHeight"), DUI:Get("UnitFrames", "raid.height")
    gripDrag(P, P.Strip().Grips().h, 0, 3)
    T.eq(DUI:Get("UnitFrames", "raid.powerHeight"), ph + 3, "thicker")
    T.eq(DUI:Get("UnitFrames", "raid.height"), h + 3, "the tile grows by as much: the health bar keeps its size")
    T.eq(#stub.errors, 0)
end)

-- A dragged slider on a page with a preview works like a grip. Each step only
-- redraws the preview and the real frames lay out once on release. Laying out
-- the real frames (40 raid tiles) on every step made the game stutter.
T.test("a slider dragged on a frame's page: the preview follows each step, the real frame lays out once on release", function()
    local DUI, P, ns = open("UnitFrames.player")
    local row
    for _, card in ipairs(P.PageFrame().cards) do
        for _, r in ipairs(card.rows) do if r.item.key == "player.width" then row = r end end
    end
    local s = row.control.slider
    local real, layouts = ns.frames.player, 0
    local layout = ns.UF.Layout
    ns.UF.Layout = function(f, ...)
        if f == real then layouts = layouts + 1 end
        return layout(f, ...)
    end
    local sample = P.Strip().Sample().f
    local start, was, realWas = DUI:Get("UnitFrames", "player.width"), sample:GetWidth(), real:GetWidth()
    s:GetScript("OnMouseDown")(s, "LeftButton")
    for i = 1, 5 do s:GetScript("OnValueChanged")(s, start + i * 4) end
    T.eq(layouts, 0, "the real frame waits")
    T.truthy(sample:GetWidth() - was > 15, "the preview follows (drawn at its own scale)")
    T.eq(DUI:Get("UnitFrames", "player.width"), start + 20)
    s:GetScript("OnMouseUp")(s, "LeftButton")
    stub.RunTimers()
    T.eq(layouts, 1, "once, on release")
    T.truthy(real:GetWidth() - realWas > 15, "the real frame takes it")
    -- Not held (mouse wheel, number box): applies at once.
    s:GetScript("OnValueChanged")(s, start)
    T.eq(layouts, 2)
    T.eq(#stub.errors, 0)
end)
