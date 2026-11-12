local stub = require("stub")

local function demo(DUI, default)
    local f = CreateFrame("Frame", "DemoFrame", UIParent)
    DUI.Movers.Register(f, "demo", "Demo", default or { "BOTTOM", nil, "BOTTOM", -200, 240 })
    return f
end

T.test("Register applies the default point", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local p, rel, rp, x, y = f:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, UIParent); T.eq(rp, "BOTTOM"); T.eq(x, -200); T.eq(y, 240)
end)

T.test("a default can be relative to another frame by global name", function()
    local DUI = stub.Load()
    local anchor = CreateFrame("Frame", "AnchorFrame", UIParent)
    local f = demo(DUI, { "LEFT", "AnchorFrame", "RIGHT", 8, 0 })
    local _, rel = f:GetPoint(1)
    T.eq(rel, anchor)
end)

T.test("a saved position wins over the default", function()
    local DUI = stub.Load({ before = function() DaylightUIDB = { positions = { demo = { 100, 50 } } } end })
    local f = demo(DUI)
    local p, rel, rp, x, y = f:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER"); T.eq(x, 100); T.eq(y, 50)
end)

T.test("Save stores center offsets snapped to the grid", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { halfW + 100, halfH + 100 }
    DUI.Movers.Save("demo")
    local snapped = DUI.Pixel.Snap(UIParent, 96)
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo[1], snapped)
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo[2], snapped)
    local _, _, _, x = f:GetPoint(1)
    T.eq(x, snapped)
end)

T.test("Save without grid snaps to physical pixels", function()
    local DUI = stub.Load()
    DUI:Set("general", "gridSnap", false)
    local f = demo(DUI)
    f.__center = { UIParent:GetWidth() / 2 + 100, UIParent:GetHeight() / 2 }
    DUI.Movers.Save("demo")
    T.near(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo[1], DUI.Pixel.Snap(UIParent, 100))
end)

T.test("Reset returns to the default", function()
    local DUI = stub.Load({ before = function() DaylightUIDB = { positions = { demo = { 1, 2 } } } end })
    local f = demo(DUI)
    DUI.Movers.Reset("demo")
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo)
    T.eq((f:GetPoint(1)), "BOTTOM")
end)

T.test("positions apply after combat when changed in combat", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    stub.EnterCombat()
    DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo = { 5, 5 }
    DUI.Movers.Apply("demo")
    T.eq((f:GetPoint(1)), "BOTTOM", "unchanged in combat")
    stub.LeaveCombat()
    T.eq((f:GetPoint(1)), "CENTER")
end)

T.test("Unlock is refused in combat", function()
    local DUI = stub.Load()
    demo(DUI)
    stub.EnterCombat()
    T.falsy(DUI.Movers.Unlock())
    T.truthy(stub.ChatContains("combat"))
end)

T.test("entering combat locks again", function()
    local DUI = stub.Load()
    demo(DUI)
    T.truthy(DUI.Movers.Unlock())
    T.truthy(DUI.Movers.unlocked)
    stub.EnterCombat()
    T.falsy(DUI.Movers.unlocked)
end)

T.test("/dui unlock and /dui lock toggle unlock mode", function()
    local DUI = stub.Load()
    demo(DUI)
    SlashCmdList.DAYLIGHTUI("unlock")
    T.truthy(DUI.Movers.unlocked)
    SlashCmdList.DAYLIGHTUI("lock")
    T.falsy(DUI.Movers.unlocked)
end)

T.test("unlocking shows a Lock button; locking (however it happens) hides it again", function()
    local DUI = stub.Load()
    demo(DUI)
    T.isnil(DUI.Movers.LockButton())
    DUI.Movers.Unlock()
    local btn = DUI.Movers.LockButton()
    T.truthy(btn:IsShown())
    T.eq(btn.text:GetText(), "Lock")
    btn:Click()
    T.falsy(DUI.Movers.unlocked, "clicking it locks")
    T.falsy(btn:IsShown())
    -- The same button is reused (not rebuilt) next time.
    DUI.Movers.Unlock()
    T.eq(DUI.Movers.LockButton(), btn)
    T.truthy(btn:IsShown())
end)

T.test("the Snap to grid button beside Lock flips the setting and shows its state", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI:Set("general", "gridSnap", true)
    DUI.Movers.Unlock()
    local snap = DUI.Movers.SnapButton()
    T.truthy(snap:IsShown())
    T.truthy(snap.active, "lit while snapping is on")
    snap:Click()
    T.falsy(DUI.DB.General().gridSnap, "clicking turns snapping off")
    T.falsy(snap.active)
    snap:Click()
    T.truthy(DUI.DB.General().gridSnap)
    T.truthy(snap.active)
    DUI.Movers.Lock()
    T.falsy(snap:IsShown(), "hidden again once locked")
end)

T.test("the Snap to frames button beside Snap to grid flips the magnet and shows its state", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI.Movers.Unlock()
    local mag = DUI.Movers.MagnetButton()
    T.truthy(mag:IsShown())
    T.truthy(mag.active, "lit: on by default")
    mag:Click()
    T.falsy(DUI.DB.General().magnet, "clicking turns it off")
    T.falsy(mag.active)
    mag:Click()
    T.truthy(DUI.DB.General().magnet)
    DUI.Movers.Lock()
    T.falsy(mag:IsShown(), "hidden again once locked")
end)

T.test("a mover whose frame isn't in use (active says no) gets no handle when unlocked", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", nil, UIParent)
    local inUse = false
    DUI.Movers.Register(f, "maybe", "Maybe", nil, { proxy = true, active = function() return inUse end })
    DUI.Movers.Unlock()
    T.isnil(DUI.Movers.Handle("maybe"))
    DUI.Movers.Lock()
    inUse = true
    DUI.Movers.Unlock()
    T.truthy(DUI.Movers.Handle("maybe"):IsShown(), "turned on: it gets one next time")
end)

T.test("/dui unlock with no options open just shows the Lock button", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI.Movers.Unlock()
    T.falsy(DUI.OptionsPanel.IsShown())
    T.truthy(DUI.Movers.LockButton():IsShown())
end)

T.test("unlocking repeatedly does not create a second grid frame or leak its lines", function()
    local DUI = stub.Load()
    demo(DUI)
    -- The grid is the only Frame child of UIParent with a big pile of line
    -- textures, so a leak would show up as a second one.
    local function gridCandidates()
        local out = {}
        for _, w in ipairs(stub.Children(UIParent)) do
            if w:GetObjectType() == "Frame" and #stub.Children(w) > 50 then
                out[#out + 1] = w
            end
        end
        return out
    end
    DUI.Movers.Unlock()
    local c1 = gridCandidates()
    T.eq(#c1, 1, "exactly one grid frame after first unlock")
    local lines1 = #stub.Children(c1[1])
    DUI.Movers.Lock()
    DUI.Movers.Unlock()
    local c2 = gridCandidates()
    T.eq(#c2, 1, "still exactly one grid frame, not a second one")
    T.eq(c2[1], c1[1], "same grid frame reused")
    T.eq(#stub.Children(c2[1]), lines1, "line count did not grow")
    DUI.NotifyStyleChanged()
    local c3 = gridCandidates()
    T.eq(#c3, 1, "still exactly one grid frame after a style change")
    T.eq(c3[1], c1[1], "same grid frame after rebuild")
    T.eq(#stub.Children(c3[1]), lines1, "lines pooled, not duplicated, on rebuild")
end)

T.test("save and apply agree when the frame has its own scale", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    DUI.Movers.SetPieceScale("demo", 2)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { (halfW + 100) / 2, (halfH + 100) / 2 }
    DUI.Movers.Save("demo")
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo[1], 96)
    local _, _, _, x, y = f:GetPoint(1)
    T.eq(x, 48); T.eq(y, 48)
end)

T.test("a piece's size: master Scale times its own, saved, reset by right-click", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    T.eq(f:GetScale(), 1)
    DUI:Set("general", "scale", 1.2)
    DUI.Movers.ApplyAll()
    T.near(f:GetScale(), 1.2)
    DUI.Movers.SetPieceScale("demo", 1.5)
    T.near(f:GetScale(), 1.8)
    T.near(DUI.DB.General().frameScales.demo, 1.5)
    DUI.Movers.SetPieceScale("demo", 9)
    T.near(DUI.Movers.PieceScale("demo"), DUI.Movers.MAX, 1e-6, "kept within the range")
    DUI.Movers.SetPieceScale("demo", 1)
    T.isnil(DUI.DB.General().frameScales.demo, "1 is stored as nothing")
    DUI.Movers.SetPieceScale("demo", 0.8)
    DUI.Movers.Reset("demo")
    T.isnil(DUI.DB.General().frameScales.demo, "reset puts the size back too")
    T.near(f:GetScale(), 1.2)
end)

T.test("a saved spot stays put whatever the piece's size", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    DUI.DB.Positions().demo = { 100, 50 }
    DUI.Movers.SetPieceScale("demo", 2)
    local _, _, _, x, y = f:GetPoint(1)
    T.eq(x, 50); T.eq(y, 25)

end)

T.test("the wheel over a handle sizes the piece; proxies and opted-out pieces take none", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local g = CreateFrame("Frame", "DemoFixed", UIParent)
    DUI.Movers.Register(g, "fixed", "Fixed", { "CENTER", nil, "CENTER", 0, 0 }, { scale = false })
    local got
    local o = CreateFrame("Frame", "DemoOwn", UIParent)
    DUI.Movers.Register(o, "own", "Own", { "CENTER", nil, "CENTER", 0, 0 }, { scale = function(s) got = s end })
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("demo")
    h:GetScript("OnMouseWheel")(h, 1)
    h:GetScript("OnMouseWheel")(h, 1)
    T.near(f:GetScale(), 1.1)
    h:GetScript("OnMouseWheel")(h, -1)
    T.near(f:GetScale(), 1.05)
    T.isnil(DUI.Movers.Handle("fixed"):GetScript("OnMouseWheel"), "scale = false: no wheel")
    g:SetScale(0.7)
    DUI.Movers.ApplyAll()
    T.near(g:GetScale(), 0.7, 1e-6, "scale = false: never touched")
    local oh = DUI.Movers.Handle("own")
    oh:GetScript("OnMouseWheel")(oh, -1)
    T.near(got, 0.95, 1e-6, "an area that sizes itself is handed the size")
    T.near(o:GetScale(), 1, 1e-6, "and its frame left alone")
    DUI.Movers.Lock()
end)

-- ---------------------------------------------------------------------
-- The mover editor: click to open, nudge, type an exact X/Y
-- ---------------------------------------------------------------------

T.test("Position reads the mover's current CENTER offset", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { halfW + 30, halfH - 20 }
    local x, y = DUI.Movers.Position("demo")
    T.near(x, 30, 1e-6); T.near(y, -20, 1e-6)
end)

-- Nudge and SetExact both end with Movers.Save, which re-anchors a real
-- frame from the saved position right away, so a test would only see
-- Save's CENTER/CENTER anchor. Swapping Save out while they're called
-- isolates their own anchor math. A separate test below checks the real
-- Save still runs.
local function withoutSave(DUI, fn)
    local real = DUI.Movers.Save
    DUI.Movers.Save = function() end
    fn()
    DUI.Movers.Save = real
end

T.test("Nudge moves the anchor by exactly one physical pixel, each direction", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    local px = DUI.Pixel.Px(f, 1)
    local function at(dx, dy)
        f.__center = { halfW, halfH }
        local x, y
        withoutSave(DUI, function()
            DUI.Movers.Nudge("demo", dx, dy)
            local _, rel, relPoint
            _, rel, relPoint, x, y = f:GetPoint(1)
            T.eq(rel, UIParent); T.eq(relPoint, "BOTTOMLEFT")
        end)
        return x, y
    end
    local x, y = at(0, 1); T.near(x, halfW, 1e-6); T.near(y, halfH + px, 1e-6, "up")
    x, y = at(0, -1); T.near(y, halfH - px, 1e-6, "down")
    x, y = at(-1, 0); T.near(x, halfW - px, 1e-6, "left")
    x, y = at(1, 0); T.near(x, halfW + px, 1e-6, "right")
end)

T.test("with grid snap on, a nudge still moves: it saves off the grid", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    DUI:Set("general", "gridSnap", true)
    f.__center = { UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 }
    local saved
    local real = DUI.Movers.Save
    DUI.Movers.Save = function(key, exact) saved = exact end
    DUI.Movers.Nudge("demo", 1, 0)
    DUI.Movers.Save = real
    T.eq(saved, true, "no snapping back to the grid")
end)

T.test("Nudge saves through Movers.Save, same as dragging", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { halfW, halfH }
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo)
    DUI.Movers.Nudge("demo", 1, 0)
    T.truthy(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo)
end)

T.test("SetExact sets the position directly", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    withoutSave(DUI, function() DUI.Movers.SetExact("demo", 123, -45) end)
    local p, rel, relPoint, x, y = f:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(relPoint, "CENTER")
    T.eq(x, 123); T.eq(y, -45)
end)

T.test("SetExact saves through Movers.Save, same as dragging", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { halfW, halfH }
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo)
    DUI.Movers.SetExact("demo", 123, -45)
    T.truthy(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo)
end)

T.test("clicking a handle (no drag) opens the editor for that frame", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("demo")
    h:GetScript("OnMouseDown")(h, "LeftButton")
    h:GetScript("OnMouseUp")(h, "LeftButton")
    local editor = DUI.Movers.Editor()
    T.truthy(editor:IsShown())
    T.eq(editor.key, "demo")
    T.eq(editor.title:GetText(), "Demo")
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo, "a click alone doesn't save a position")
end)

T.test("the editor opens below a frame, or above it when the frame is near the bottom", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("demo")
    h.GetBottom = function() return 500 end
    DUI.Movers.OpenEditor("demo")
    local editor = DUI.Movers.Editor()
    T.eq(select(1, editor:GetPoint()), "TOP", "room below: hangs under the frame")
    h.GetBottom = function() return 10 end
    DUI.Movers.OpenEditor("demo")
    T.eq(select(1, editor:GetPoint()), "BOTTOM", "no room below: sits on top of the frame")
end)

T.test("a real drag still saves, and does not open the editor", function()
    local DUI = stub.Load()
    DUI.DB.General().magnet = false     -- the grid path (the drop sits on the screen's center line)
    local f = demo(DUI)
    DUI.Movers.Unlock()
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { halfW, halfH }
    local h = DUI.Movers.Handle("demo")
    h:GetScript("OnMouseDown")(h, "LeftButton")
    h:GetScript("OnDragStart")(h)
    f.__center = { halfW + 50, halfH }
    h:GetScript("OnDragStop")(h)
    h:GetScript("OnMouseUp")(h, "LeftButton")
    T.falsy(DUI.Movers.Editor() and DUI.Movers.Editor():IsShown())
    T.truthy(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.demo)
end)

T.test("the editor's nudge buttons move the frame the same way Nudge does", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { halfW, halfH }
    DUI.Movers.OpenEditor("demo")
    local editor = DUI.Movers.Editor()
    T.eq(editor.x:GetText(), "0")
    withoutSave(DUI, function() editor.up:Click() end)
    local _, _, _, x, y = f:GetPoint(1)
    T.near(y, halfH + DUI.Pixel.Px(f, 1), 1e-6)
end)

T.test("typing an exact X/Y and pressing enter sets the position", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    DUI.Movers.OpenEditor("demo")
    local editor = DUI.Movers.Editor()
    editor.x:SetText("55")
    editor.y:SetText("-10")
    withoutSave(DUI, function() editor.x:GetScript("OnEnterPressed")(editor.x) end)
    local _, _, _, x, y = f:GetPoint(1)
    T.eq(x, 55); T.eq(y, -10)
end)

-- Two bars both reading "517" sat 2-3 pixels apart in game because the
-- boxes cut the decimals off (517.9 read 517). Same number, same spot.
T.test("the editor's X/Y never show two spots as the same number", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    DUI.Movers.OpenEditor("demo")
    local editor = DUI.Movers.Editor()
    f.__center = { halfW + 12, halfH + 517.9 }
    DUI.Movers.RefreshEditor()
    local high = editor.y:GetText()
    f.__center = { halfW + 12, halfH + 517.1 }
    DUI.Movers.RefreshEditor()
    T.truthy(high ~= editor.y:GetText(), "517.9 and 517.1 read " .. high .. " and " .. editor.y:GetText())
    T.eq(editor.x:GetText(), "12", "a whole number stays whole")
    f.__center = { halfW - 0.02, halfH + 517 }
    DUI.Movers.RefreshEditor()
    T.eq(editor.y:GetText(), "517")
    T.eq(editor.x:GetText(), "0", "never -0")
end)

T.test("locking closes the editor", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI.Movers.Unlock()
    DUI.Movers.OpenEditor("demo")
    T.truthy(DUI.Movers.Editor():IsShown())
    DUI.Movers.Lock()
    T.falsy(DUI.Motion.Shown(DUI.Movers.Editor()), "fading out")
    stub.FinishFade(DUI.Movers.Editor())
    T.falsy(DUI.Movers.Editor():IsShown())
end)

-- Proxies: frames the game places (action bars, pop-ups). The handle moves
-- on its own, and with opts.follow the real frame goes along.
local function proxy(DUI, opts)
    local f = CreateFrame("Frame", "ProxyFrame", UIParent)
    f:SetSize(200, 40)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    f.__center = { halfW, halfH - 300 }
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 20)
    opts = opts or {}
    opts.proxy = true
    DUI.Movers.Register(f, "px", "Proxy", nil, opts)
    return f, halfW, halfH
end

local function dragHandle(h, toX, toY)
    h:GetScript("OnMouseDown")(h, "LeftButton")
    h:GetScript("OnDragStart")(h)
    h.__center = { toX, toY }
    local tick = h:GetScript("OnUpdate")
    if tick then tick(h, 0.016) end
    h:GetScript("OnDragStop")(h)
    h:GetScript("OnMouseUp")(h, "LeftButton")
end

T.test("a proxy's handle lands on the grid spot it saved, like every other frame", function()
    local DUI = stub.Load()
    DUI.DB.General().magnet = false     -- the grid path (the drop sits on the screen's center line)
    proxy(DUI)
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("px")
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    dragHandle(h, halfW + 100, halfH + 100)
    local saved = DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.px
    local p, rel, rp, x, y = h:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.eq(x, saved[1]); T.eq(y, saved[2])
    T.eq(saved[1], DUI.Pixel.Snap(UIParent, 96))
end)

T.test("a plain proxy's frame is never touched", function()
    local DUI = stub.Load()
    local f = proxy(DUI)
    DUI.Movers.Unlock()
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    dragHandle(DUI.Movers.Handle("px"), halfW + 100, halfH + 100)
    local p, _, _, _, y = f:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(y, 20)
end)

T.test("a following proxy's frame moves with its handle while dragging", function()
    local DUI = stub.Load()
    local f, halfW, halfH = proxy(DUI, { follow = true })
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("px")
    h:GetScript("OnMouseDown")(h, "LeftButton")
    h:GetScript("OnDragStart")(h)
    h.__center = { halfW + 37, halfH + 11 }
    h:GetScript("OnUpdate")(h, 0.016)
    local p, rel, rp, x, y = f:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.near(x, 37, 1e-6); T.near(y, 11, 1e-6)
    h:GetScript("OnDragStop")(h)
    T.isnil(h:GetScript("OnUpdate"), "stops following once dropped")
end)

T.test("a following proxy's frame ends on the saved (snapped) spot", function()
    local DUI = stub.Load()
    DUI.DB.General().magnet = false     -- the grid path (the drop sits on the screen's center line)
    local f, halfW, halfH = proxy(DUI, { follow = true })
    DUI.Movers.Unlock()
    dragHandle(DUI.Movers.Handle("px"), halfW + 100, halfH + 100)
    local saved = DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.px
    local p, _, _, x, y = f:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(x, saved[1]); T.eq(y, saved[2])
end)

T.test("a following proxy's frame isn't moved in combat", function()
    local DUI = stub.Load()
    local f, halfW, halfH = proxy(DUI, { follow = true })
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("px")
    stub.combat = true
    h.__center = { halfW + 100, halfH + 100 }
    DUI.Movers.Save("px")
    stub.combat = false
    T.eq((f:GetPoint(1)), "BOTTOM")
end)

T.test("resetting a following proxy puts handle and frame at its home", function()
    local DUI = stub.Load({ before = function() DaylightUIDB = { positions = { px = { 300, 200 } } } end })
    local f = proxy(DUI, { follow = true, home = function() return -40, -250 end })
    DUI.Movers.Unlock()
    DUI.Movers.Reset("px")
    T.isnil(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.px)
    local _, _, _, hx, hy = DUI.Movers.Handle("px"):GetPoint(1)
    T.eq(hx, -40); T.eq(hy, -250)
    local p, _, _, x, y = f:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(x, -40); T.eq(y, -250)
end)

T.test("moving a following proxy leaves the other following frames where they are", function()
    local DUI = stub.Load()
    local f, halfW, halfH = proxy(DUI, { follow = true })
    -- The game hangs some bars off others. This one sits on top of f.
    local g = CreateFrame("Frame", "ProxyFrame2", UIParent)
    g:SetSize(200, 40)
    g.__center = { halfW, halfH - 250 }
    g:SetPoint("BOTTOM", f, "TOP", 0, 10)
    DUI.Movers.Register(g, "px2", "Proxy 2", nil, { proxy = true, follow = true })
    DUI.Movers.Unlock()
    dragHandle(DUI.Movers.Handle("px"), halfW + 100, halfH + 100)
    local p, rel, rp, x, y = g:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.near(x, 0, 1e-6); T.near(y, -250, 1e-6)
end)

-- ---------------------------------------------------------------------
-- Magnet: edges and centers line up with other frames
-- ---------------------------------------------------------------------

local function R(l, b, w, h) return { l = l, r = l + w, b = b, t = b + h } end

T.test("magnet: aligned and flush snaps within 8, nothing at 9", function()
    local M = stub.Load().Movers
    local other = R(300, 300, 100, 50)
    local dx, dy, gx = M.Magnet(R(205, 100, 90, 20), { other })   -- right edge 295, 5 short of their left
    T.eq(dx, 5); T.eq(gx, 300); T.isnil(dy)
    dx = M.Magnet(R(303, 100, 40, 20), { other })                 -- left edges 3 apart
    T.eq(dx, -3)
    dx = M.Magnet(R(200, 100, 91, 20), { other })                 -- right edge 291: 9 short
    T.isnil(dx)
    local _, dy2, _, gy = M.Magnet(R(0, 357, 40, 20), { other })  -- bottom 7 over their top (350)
    T.eq(dy2, -7); T.eq(gy, 350)
end)

T.test("magnet: flush beats aligned on a tie, then the nearer frame", function()
    local M = stub.Load().Movers
    -- dragged 100 wide at l=96: its right (196) is 4 short of A's left (200, flush),
    -- its left (96) is 4 past B's left (100, aligned)
    local A, B = R(200, 0, 50, 50), R(100, 500, 50, 50)
    local dx, _, gx = M.Magnet(R(96, 0, 100, 50), { B, A })
    T.eq(dx, 4); T.eq(gx, 200, "flush wins")
    -- two aligned at the same distance: the nearer frame wins
    local near, far = R(100, 60, 50, 50), R(100, 900, 50, 50)
    dx, _, gx = M.Magnet(R(104, 0, 50, 50), { far, near })
    T.eq(dx, -4); T.eq(gx, 100)
end)

T.test("magnet: the screen's center lines count", function()
    local M = stub.Load().Movers
    local cx, cy = 500, 400
    local centre = { l = cx, r = cx, b = cy, t = cy }
    local dx, dy = M.Magnet(R(cx - 26, cy - 23, 50, 50), { centre })   -- its center 1 left, 2 down
    T.eq(dx, 1); T.eq(dy, -2)
end)

-- Another frame, off the grid on purpose: px (200 x 40) dropped at
-- (48, 80) from the center is 5 short of its left edge and 3 above its
-- center line. The grid alone would land it on (48, 80).
local function besideOther(DUI)
    local halfW, halfH = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    local other = CreateFrame("Frame", "OtherFrame", UIParent)
    other:SetSize(100, 40)
    DUI.Movers.Register(other, "other", "Other", { "CENTER", nil, "CENTER", 0, 0 })
    other.__center = { halfW + 203, halfH + 77 }
    proxy(DUI)
    DUI.Movers.Unlock()
    return DUI.Movers.Handle("px"), halfW, halfH
end
local function savedPx(DUI) return DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.px end

T.test("magnet: a drop near another frame lands flush and level, exactly, off the grid", function()
    local DUI = stub.Load()
    DUI.DB.General().motion = false
    local h, halfW, halfH = besideOther(DUI)
    dragHandle(h, halfW + 48, halfH + 80)
    T.near(savedPx(DUI)[1], DUI.Pixel.Snap(UIParent, 53), 1e-6, "flush against its left edge")
    T.near(savedPx(DUI)[2], DUI.Pixel.Snap(UIParent, 77), 1e-6, "level with it, not grid-rounded")
end)

T.test("magnet: Shift or the setting off drops on the grid as before", function()
    local DUI = stub.Load()
    DUI.DB.General().motion = false
    local h, halfW, halfH = besideOther(DUI)
    _G.IsShiftKeyDown = function() return true end
    dragHandle(h, halfW + 48, halfH + 80)
    T.near(savedPx(DUI)[1], DUI.Pixel.Snap(UIParent, 48), 1e-6, "Shift: the grid")
    _G.IsShiftKeyDown = nil
    DUI.DB.General().magnet = false
    dragHandle(h, halfW + 48, halfH + 80)
    T.near(savedPx(DUI)[1], DUI.Pixel.Snap(UIParent, 48), 1e-6, "off: the grid")
end)

T.test("magnet: with motion on, it glides there, then saves and ticks", function()
    local played = {}
    local DUI = stub.Load({ before = function()
        _G.PlaySoundFile = function(f) played[#played + 1] = f end
    end })
    local h, halfW, halfH = besideOther(DUI)
    dragHandle(h, halfW + 48, halfH + 80)
    local d = DUI.Motion.Driver()
    T.truthy(d and d:GetScript("OnUpdate"), "gliding")
    for _ = 1, 30 do if d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end end
    T.near(savedPx(DUI)[1], DUI.Pixel.Snap(UIParent, 53), 1e-6)
    T.eq(played[#played], DUI.Sound.FILES.snap, "a soft tick")
end)

T.test("magnet: guide lines show while dragging and hide on drop", function()
    local DUI = stub.Load()
    DUI.DB.General().motion = false
    local h, halfW, halfH = besideOther(DUI)
    h:GetScript("OnMouseDown")(h, "LeftButton")
    h:GetScript("OnDragStart")(h)
    h.__center = { halfW + 48, halfH + 80 }
    h:GetScript("OnUpdate")(h, 0.016)
    local v, hz = DUI.Movers.Guides()
    T.truthy(v:IsShown(), "a vertical line"); T.truthy(hz:IsShown(), "and a level one")
    h:GetScript("OnDragStop")(h)
    T.falsy(v:IsShown()); T.falsy(hz:IsShown())
end)

T.test("unlock handles take the accent picked since they were made", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI.Movers.Unlock()
    DUI.Movers.Lock()
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.8, 0.3 })
    stub.RunTimers()
    DUI.Movers.Unlock()
    local v = DUI.Movers.Handle("demo").tint.__vertex
    local r, g, b = DUI.Style.Accent()
    T.near(v[1], r, 1e-6); T.near(v[2], g, 1e-6); T.near(v[3], b, 1e-6)
    T.near(v[4], 0.25, 1e-6)
end)

T.test("a damaged saved position falls back to the default spot instead of erroring", function()
    for _, bad in ipairs({ "x", { 1 }, { "a", 2 }, { 1, 0 / 0 }, { math.huge, 2 } }) do
        local DUI = stub.Load({ before = function() DaylightUIDB = { positions = { demo = bad } } end })
        local f
        T.noerror(function() f = demo(DUI) end, "applied without error")
        local p, rel, rp, x, y = f:GetPoint(1)
        T.eq(p, "BOTTOM"); T.eq(rel, UIParent); T.eq(rp, "BOTTOM"); T.eq(x, -200); T.eq(y, 240)
        T.noerror(function() DUI.Movers.Unlock() end, "its handle places too")
    end
end)

T.test("a fight starting mid-drag drops the handle: saved, no follow left running", function()
    local DUI = stub.Load()
    local _, halfW, halfH = proxy(DUI, { follow = true })
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("px")
    h:GetScript("OnMouseDown")(h, "LeftButton")
    h:GetScript("OnDragStart")(h)
    h.__center = { halfW + 40, halfH + 20 }
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.isnil(h:GetScript("OnUpdate"), "follow stopped")
    T.truthy(DaylightUIDB.profileData[DUI.DB.DEFAULT].positions.px, "the drop was saved")
    T.falsy(DUI.Movers.unlocked)
end)

T.test("a suspended piece (attached to another frame) still follows the master Scale, its spot left alone", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    DUI.Movers.Suspend("demo", true)
    local host = CreateFrame("Frame", "DemoHost", UIParent)
    f:ClearAllPoints()
    f:SetPoint("TOP", host, "BOTTOM", 0, -4)
    DUI:Set("general", "scale", 1.3)
    stub.RunTimers()
    T.near(f:GetScale(), 1.3)
    local _, rel = f:GetPoint(1)
    T.eq(rel, host, "still hung where its area put it")
end)

T.test("a frame with no handle (a pop-up, a banner) follows the master Scale", function()
    local DUI = stub.Load()
    local f = CreateFrame("Frame", "DemoPopup", UIParent)
    DUI:Set("general", "scale", 1.2)
    stub.RunTimers()
    DUI.Movers.FollowScale(f)
    T.near(f:GetScale(), 1.2, 1e-6, "at once")
    DUI:Set("general", "scale", 0.8)
    stub.RunTimers()
    T.near(f:GetScale(), 0.8, 1e-6, "and on a change")
    local g = CreateFrame("Frame", "DemoOwnSize", UIParent)
    DUI.Movers.FollowScale(g, function() return 1.5 end)
    T.near(g:GetScale(), 1.2, 1e-6, "its own size on top")
end)

-- The editor's Options button: a piece with an options page opens it at
-- its settings.
T.test("movers: the editor's Options button opens the piece's options at its rows", function()
    local DUI = stub.Load({ module = true, actionbars = true })
    local M = DUI.Movers
    T.eq(M.OptionsOf("unitframes.party"), "UnitFrames.party")
    local page, jump = M.OptionsOf("actionbars.bar5")
    T.eq(page, "ActionBars.barlayout"); T.eq(jump, "bars.bar5.visible")
    T.isnil(M.OptionsOf("nothing.here"))
    M.Unlock()
    M.OpenEditor("actionbars.bar5")
    local ed = M.Editor()
    T.truthy(ed.options:IsShown())
    ed.options:Click()
    local P = DUI.OptionsPanel
    T.truthy(P.IsShown(), "the options window")
    T.eq(P.Current(), "ActionBars.barlayout")
    local card = P.PageFrame().Find("bars.bar5.visible")
    T.eq(card.group.Picked(), "bar5", "Settings for picked the bar")
    M.Lock()
end)

T.test("an anchor pins that point: the frame stays put, then grows away from it", function()
    local DUI = stub.Load()
    local f = demo(DUI)
    f:SetSize(100, 60)
    f.__center = { UIParent:GetWidth() / 2 + 200, UIParent:GetHeight() / 2 - 100 }
    T.eq(DUI.Movers.Corner("demo"), "CENTER")
    DUI.Movers.SetCorner("demo", "BOTTOMRIGHT")
    local p, rel, rp, x, y = f:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.near(x, 250, 1); T.near(y, -130, 1)
    local saved = DUI.DB.Positions().demo
    T.near(saved[1], 200, 1, "the center stays what every reader expects")
    T.near(saved[2], -100, 1)
    DUI.Movers.Reset("demo")
    T.eq(DUI.Movers.Corner("demo"), "CENTER", "put back: the anchor too")
end)

T.test("a proxy can't take an anchor unless it places itself", function()
    local DUI = stub.Load()
    local a, b = CreateFrame("Frame", nil, UIParent), CreateFrame("Frame", nil, UIParent)
    local told
    DUI.Movers.Register(a, "plain", "Plain", nil, { proxy = true })
    DUI.Movers.Register(b, "own", "Own", nil, { proxy = true, corner = "TOPLEFT", onCorner = function(k) told = k end })
    T.falsy(DUI.Movers.Cornerable("plain"))
    DUI.Movers.SetCorner("plain", "TOP")
    T.eq(DUI.Movers.Corner("plain"), "CENTER")
    DUI.Movers.SetCorner("own", "BOTTOMRIGHT")
    T.eq(told, "own")
    T.eq(DUI.Movers.Corner("own"), "BOTTOMRIGHT")
end)

T.test("the editor offers the anchor and keeps its word", function()
    local DUI = stub.Load()
    demo(DUI):SetSize(50, 50)
    DUI.Movers.SetExact("demo", 0, 0)
    DUI.Movers.Unlock()
    DUI.Movers.OpenEditor("demo")
    local editor = DUI.Movers.Editor()
    T.truthy(editor.corner:IsShown())
    T.eq(editor.corner.text:GetText(), "Anchor: Center")
    DUI.Movers.SetCorner("demo", "TOPLEFT")
    DUI.Movers.RefreshEditor()
    T.eq(editor.corner.text:GetText(), "Anchor: Top left")
end)

local function two(DUI)
    local a, b = demo(DUI), CreateFrame("Frame", nil, UIParent)
    DUI.Movers.Register(b, "demo2", "Demo 2", { "CENTER", nil, "CENTER", 0, 0 })
    local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    a.__center, b.__center = { cx + 100, cy }, { cx + 300, cy }
    return a, b
end

T.test("a group moves as one: a drag carries the others the same distance", function()
    local DUI = stub.Load()
    local a, b = two(DUI)
    DUI:Set("general", "gridSnap", false)
    DUI:Set("general", "magnet", false)
    DUI.Movers.SetGroup("demo", 1)
    DUI.Movers.SetGroup("demo2", 1)
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("demo")
    h:GetScript("OnDragStart")(h)
    a.__center = { UIParent:GetWidth() / 2 + 90, UIParent:GetHeight() / 2 + 20 }
    h:GetScript("OnDragStop")(h)
    local pos = DUI.DB.Positions()
    T.near(pos.demo[1], 90, 1)
    T.near(pos.demo2[1], 290, 1, "the same 10 left")
    T.near(pos.demo2[2], 20, 1, "and 20 up")
end)

T.test("out of a group a frame moves alone", function()
    local DUI = stub.Load()
    two(DUI)
    DUI.Movers.SetGroup("demo", 1)
    DUI.Movers.SetExact("demo", 90, 20)
    T.isnil(DUI.DB.Positions().demo2, "demo2 isn't in it")
end)

T.test("a group left with one frame is no group", function()
    local DUI = stub.Load()
    two(DUI)
    DUI.Movers.ToggleInGroup("demo", "demo2")
    T.eq(DUI.Movers.GroupOf("demo"), DUI.Movers.GroupOf("demo2"))
    T.truthy(DUI.Movers.GroupOf("demo"), "Ctrl-click starts one")
    DUI.Movers.ToggleInGroup("demo", "demo2")
    T.isnil(DUI.Movers.GroupOf("demo2"), "and takes it out")
    T.isnil(DUI.Movers.GroupOf("demo"))
    T.eq(#DUI.Movers.Groups(), 0)
end)

T.test("the arrow keys nudge the clicked frame, Shift a grid step, and others pass on", function()
    local DUI = stub.Load()
    local a = demo(DUI)
    a.__center = { UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 }
    DUI.Movers.Unlock()
    DUI.Movers.OpenEditor("demo")
    local editor = DUI.Movers.Editor()
    local seen = {}
    local nudge = DUI.Movers.Nudge
    DUI.Movers.Nudge = function(key, dx, dy) seen[#seen + 1] = dx .. "," .. dy end
    editor:GetScript("OnKeyDown")(editor, "LEFT")
    T.eq(seen[1], "-1,0")
    local was = _G.IsShiftKeyDown
    _G.IsShiftKeyDown = function() return true end
    editor:GetScript("OnKeyDown")(editor, "UP")
    _G.IsShiftKeyDown = was
    T.eq(seen[2], "0," .. DUI.Movers.GRID)
    editor:GetScript("OnKeyDown")(editor, "A")
    T.eq(#seen, 2, "any other key is the game's")
    DUI.Movers.Nudge = nudge
end)

T.test("Options leaves unlock mode for the frame's settings", function()
    local DUI = stub.Load()
    demo(DUI)
    DUI.Movers.OPTIONS.demo = { "General.layout" }
    local opened
    local panel = DUI.OptionsPanel
    local show = panel.Show
    panel.Show = function(page) opened = page; T.falsy(DUI.Movers.unlocked, "locked first") end
    local get = DUI.Options.GetPage
    DUI.Options.GetPage = function() return {} end
    DUI.Movers.Unlock()
    DUI.Movers.OpenOptions("demo")
    panel.Show, DUI.Options.GetPage = show, get
    T.eq(opened, "General.layout")
end)
