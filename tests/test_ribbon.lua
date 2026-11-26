local stub = require("stub")

-- Ribbon, the second frame style: a slim bar with the name and health number
-- on a row above it (the name tab, its shell hidden) and the power as a thin
-- line hung under it. Every option of the four frames that wear it must
-- still work.

local function login(before) return stub.Load({ module = true, before = before }) end

local function ribbon(DUI, ns, on)
    ns.SetStyle("look.style", on == false and "daylight" or "ribbon")
    stub.RunTimers()
end

T.test("a frame wears its own style, or with \"global\" the one for every frame; raid tiles never change", function()
    local DUI, ns = login()
    local UF = ns.UF
    T.eq(UF.StyleOf(DUI:Get("UnitFrames", "player")), "daylight", "Daylight by default")
    DUI:Set("UnitFrames", "look.style", "ribbon")
    T.eq(UF.StyleOf(DUI:Get("UnitFrames", "player")), "ribbon", "global follows look.style")
    DUI:Set("UnitFrames", "target.style", "daylight")
    T.eq(UF.StyleOf(DUI:Get("UnitFrames", "target")), "daylight", "its own pick wins")
    T.eq(UF.StyleOf(DUI:Get("UnitFrames", "raid")), "daylight", "settings with no style key stay Daylight")
    T.eq(UF.StyleOf(DUI:Get("UnitFrames", "targettarget")), "daylight")
end)

T.test("each style keeps its own heights: switching swaps them, switching back gives the old frame back", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "player.height", 50)
    ribbon(DUI, ns)
    T.eq(DUI:Get("UnitFrames", "player.height"), 24, "Ribbon's own bar height")
    T.eq(DUI:Get("UnitFrames", "player.powerHeight"), 5)
    T.eq(DUI:Get("UnitFrames", "party.spacing"), 48, "the party's spacing too")
    DUI:Set("UnitFrames", "player.height", 30)
    ribbon(DUI, ns, false)
    T.eq(DUI:Get("UnitFrames", "player.height"), 50, "Daylight's height, as it was")
    T.eq(DUI:Get("UnitFrames", "player.powerHeight"), 11)
    T.eq(DUI:Get("UnitFrames", "party.spacing"), 38)
    ribbon(DUI, ns)
    T.eq(DUI:Get("UnitFrames", "player.height"), 30, "Ribbon's height, as it was left")
end)

T.test("a frame's own pick swaps only its heights; a profile's style is swapped in at the next refresh", function()
    local DUI, ns = login()
    ns.SetStyle("target.style", "ribbon")
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "target.height"), 24)
    T.eq(DUI:Get("UnitFrames", "player.height"), 43, "the player stays Daylight")
    -- Written straight in, as an imported profile would. The refresh catches up.
    local db = ns.module.db
    db.focus.style = "ribbon"
    ns.Refresh(ns.module)
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "focus.height"), 20)
end)

T.test("Ribbon: the name and health number on a bare row above, the power a line hung under the bar", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    local f = ns.frames.player
    T.eq(f.style, "ribbon")
    T.truthy(f.tab:IsShown(), "the row shows")
    T.falsy(DaylightUI.Style.GetShell(f.tab):IsShown(), "with no shell of its own")
    local p, rel, rp = f.nameText:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, f.tab); T.eq(rp, "BOTTOMLEFT")
    T.eq(f.percentText:GetParent(), f.tab, "the number rides the row")
    p, rel, rp = f.percentText:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, f.tab); T.eq(rp, "BOTTOMRIGHT")
    -- The power line is its own bar hung under the frame, with the frame's pieces off.
    local line = f.line
    T.truthy(line:IsShown())
    T.eq(f.power, line.set.power, "f.power is the line's")
    T.eq(f.powerText, line.set.powerText)
    T.falsy(f.insidePower.power:IsShown(), "the frame's own power bar is off")
    T.falsy(f.separator:IsShown())
    p, rel, rp = line:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, f); T.eq(rp, "BOTTOMLEFT")
    T.truthy(f.foot > 0, "the room it takes under the frame")
    local hit = f.__hitRect
    T.truthy(hit[3] < 0 and hit[4] < 0, "the row and the line click like the frame")
    -- The target is mirrored, so the number sits at its left (inner) end.
    local tf = ns.frames.target
    p = tf.percentText:GetPoint(1)
    T.eq(p, "BOTTOMLEFT")
end)

T.test("back to Daylight puts every piece back", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    ribbon(DUI, ns, false)
    local f = ns.frames.player
    T.eq(f.style, "daylight")
    T.falsy(f.line:IsShown())
    T.eq(f.power, f.insidePower.power)
    T.truthy(f.power:IsShown())
    T.truthy(f.separator:IsShown())
    T.eq(f.percentText:GetParent(), f.overlay)
    T.truthy(DaylightUI.Style.GetShell(f.tab):IsShown(), "the tab has its shell again")
    T.eq(f.foot, 0)
    T.eq(f.__hitRect[3], 0); T.eq(f.__hitRect[4], 0)
end)

T.test("the player's power on its own still wins in Ribbon, and its line stays off", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "player.powerAt", "free")
    ribbon(DUI, ns)
    local f = ns.frames.player
    T.eq(f.power, f.freePower.set.power)
    T.falsy(f.line:IsShown())
    T.eq(f.foot, 0)
end)

T.test("Ribbon: a cast asked to sit inside the frame sits below it, under the power line", function()
    local DUI, ns = login()
    local CB = ns.CastBar
    T.eq(CB.At("target", DUI:Get("UnitFrames", "targetCastbar")), "power")
    ribbon(DUI, ns)
    T.eq(CB.At("target", DUI:Get("UnitFrames", "targetCastbar")), "below")
    T.eq(CB.At("focus", DUI:Get("UnitFrames", "focusCastbar")), "below")
    T.truthy(ns.targetCastbarFree.enabled, "its own bar")
    T.falsy(ns.targetCastbar.enabled, "not the one inside")
    local f = ns.frames.target
    local _, rel, rp, _, y = ns.targetCastbarFree:GetPoint(1)
    T.eq(rel, f); T.eq(rp, "BOTTOM")
    T.truthy(y < -f.foot, "under the line")
end)

T.test("Ribbon: the player's hung cast bar and the swing bars hang from the power line", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    local f, cb = ns.frames.player, ns.playerCastbar
    T.truthy(cb.column, "still hung")
    T.truthy(cb.column.lift < 0, "below the frame's bottom")
    local lineT = DaylightUI.Pixel.Px(f.line, DaylightUI.Style.BorderPx(f.line))
    T.near(cb.column.lift, lineT - f.foot)
    local s = ns.swing
    if s and s.column then
        T.eq(s.column.under, f.line, "the swing bars hang from the line while no cast shows")
        T.near(s.column.tuck, lineT)
    end
end)

T.test("Ribbon: combo points, aura rows and party pets clear the power line", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    local f = ns.frames.target
    local box = ns.AuraGroups.Box(f, DUI:Get("UnitFrames", "target"))
    T.eq(box.below, f.foot, "rows under the frame start past the line")
    T.eq(box.bottomInset, 0, "no power bar inside to keep clear of")
    local c = ns.combo
    if c then
        local _, _, _, _, y = c:GetPoint(1)
        T.truthy(y <= -4 - f.foot, "combo points under the line")
    end
end)

T.test("Ribbon: the ring spans the whole ribbon, centered on it", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    local f = ns.frames.player
    local p = f.portrait
    T.truthy(p:IsShown())
    local H = f:GetHeight() + f.hitTop + f.foot
    -- Set into the frame the ring is built out from that radius (Socket.lua).
    local S = ns.Socket
    local Rb = DaylightUI.Pixel.Snap(f, H * ns.STYLES.ribbon.ring * S.SIZE)
    local gap = DaylightUI.Pixel.Px(f, S.GAP_PX)
    T.near(p.mask:GetWidth() / 2, math.min(S.PICTURE * Rb, (S.PICTURE + S.HAIR) * Rb - gap), 1e-6)
    T.near(f.portraitY, DaylightUI.Pixel.Snap(f, (f.hitTop - f.foot) / 2), 1e-6, "centered, on a whole pixel")
    local _, _, _, _, y = p:GetPoint(1)
    T.near(y, f.portraitY)
    local T_ = DUI.Pixel.Px(f, DUI.Style.BorderPx(f))
    T.truthy(f.socketOn, "Ribbon takes the socket too")
    T.truthy(f.socket.gap:GetHeight() <= f:GetHeight() - 2 * T_ + 1e-6, "the cut-back stays inside the bar, not the name row or line")
end)

T.test("Ribbon without a portrait: threat colors the bar's border (the row has none)", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "target.portrait", "none")
    ribbon(DUI, ns)
    local f = ns.frames.target
    local Style = DaylightUI.Style
    ns.UF.ApplyThreat(f, "aggro")
    T.truthy(Style.GetShell(f).opts.borderColor, "the frame's border is red")
    T.isnil(Style.GetShell(f.tab).opts.borderColor, "the hidden row isn't")
    ribbon(DUI, ns, false)
    ns.UF.ApplyThreat(f, "aggro")
    T.isnil(Style.GetShell(f).opts.borderColor, "back in Daylight the frame's border is normal again")
    T.truthy(Style.GetShell(f.tab).opts.borderColor, "and the tab carries it")
end)

T.test("Ribbon: a secret name and health on the row draw whole", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    stub.units.target = { name = stub.Secret("Boss"), isPlayer = false, reaction = stub.Secret(2),
        health = stub.Secret(50), maxHealth = stub.Secret(100), pct = stub.Secret(50) }
    local f = ns.frames.target
    T.noerror(function() ns.UF.UpdateAll(f, true) end)
    T.eq(stub.Plain(stub.Text(f.nameText)), "Boss")
end)

T.test("Ribbon party buttons: the line under each, the boss debuffs measured on the whole bar", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton1", h)
    b:SetAttribute("unit", "party1")
    stub.units.party1 = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10, power = 3, maxPower = 10 }
    h.initialConfigFunction(h, b:GetName())
    stub.RunTimers()
    T.eq(b.style, "ribbon")
    T.truthy(b.line and b.line:IsShown(), "a line under the button")
    T.eq(b.power, b.line.set.power)
    local cfg = DUI:Get("UnitFrames", "party")
    local whole = ns.GroupPrivate.Size(cfg)
    DUI:Set("UnitFrames", "party.showPower", false)
    T.eq(ns.GroupPrivate.Size(cfg), whole, "the power line isn't taken off the bar's height")
end)

T.test("Ribbon options: its own words for the heights, no cast inside the frame", function()
    local DUI, ns = login()
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.player")
    local rows = {}
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do rows[it.label] = it end
    end
    T.falsy(O.IsHidden(page, rows["Height"]))
    T.truthy(O.IsHidden(page, rows["Bar height"]))
    ribbon(DUI, ns)
    T.truthy(O.IsHidden(page, rows["Height"]))
    T.falsy(O.IsHidden(page, rows["Bar height"]))
    T.falsy(O.IsHidden(page, rows["Name row height"]))
    T.truthy(O.IsHidden(page, rows["Name tab height"]))
    local at
    for _, g in ipairs(O.GetPage("UnitFrames.target").groups) do
        for _, it in ipairs(g.items) do if it.key == "targetCastbar.at" then at = it end end
    end
    T.truthy(at, "the target's cast bar position row")
    local _, order = at.choices()
    for _, v in ipairs(order) do T.truthy(v ~= "power", "no Inside the frame") end
    T.eq(at.shownAs("power"), at.values.below, "a saved Inside reads as Below")
end)

T.test("the setup guide can still draw the frame style on a plugin's cards", function()
    local DUI = login()
    for _, key in ipairs({ "daylight", "ribbon" }) do
        local card = { inner = CreateFrame("Frame") }
        T.noerror(function() DUI.InstallerCards.Draw.frameStyle(card, key, 140, 50) end)
        T.noerror(card.redraw)
    end
end)

-- A style is only a set of pieces (ns.STYLES), so a new one is a new entry.
-- These mix the pieces in ways no shipped style does, and the frames and the
-- options follow each piece on its own.
local function addStyle(ns, key, def)
    def.label, def.desc = def.label or key, def.desc or key
    ns.STYLES[key] = def
    ns.STYLE_ORDER[#ns.STYLE_ORDER + 1] = key
end

T.test("a new style made of a power line and no name row: the tab stays, the power hangs under", function()
    local DUI, ns = login()
    addStyle(ns, "lineonly", { line = true })
    ns.SetStyle("look.style", "lineonly")
    stub.RunTimers()
    local f = ns.frames.player
    T.eq(f.style, "lineonly")
    T.falsy(f.nameRow); T.truthy(f.powerLine)
    T.truthy(DaylightUI.Style.GetShell(f.tab):IsShown(), "the name tab keeps its shell")
    T.eq(f.percentText:GetParent(), f.overlay, "the number stays on the bar")
    T.truthy(f.line:IsShown(), "the line hangs under")
    T.eq(f.power, f.line.set.power)
    T.truthy(f.foot > 0); T.eq(f.hitTop, 0)
    T.eq(ns.CastBar.At("target", DUI:Get("UnitFrames", "targetCastbar")), "below", "no cast inside a line")
    local up, down = ns.UF.StyleReach(DUI:Get("UnitFrames", "party"), f)
    T.eq(up, 0); T.truthy(down > 0)
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.player")
    local rows = {}
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do rows[it.label] = it end
    end
    T.truthy(O.IsHidden(page, rows["Power bar height"])); T.falsy(O.IsHidden(page, rows["Power line height"]))
    T.falsy(O.IsHidden(page, rows["Name tab height"])); T.truthy(O.IsHidden(page, rows["Name row height"]))
end)

T.test("a new style made of a name row and no line: the power stays inside, the ring keeps the frame's size", function()
    local DUI, ns = login()
    addStyle(ns, "rowonly", { row = true })
    ns.SetStyle("look.style", "rowonly")
    stub.RunTimers()
    local f = ns.frames.player
    T.truthy(f.nameRow); T.falsy(f.powerLine)
    T.falsy(DaylightUI.Style.GetShell(f.tab):IsShown(), "a bare row")
    T.eq(f.percentText:GetParent(), f.tab)
    T.falsy(f.line:IsShown()); T.eq(f.power, f.insidePower.power)
    T.eq(f.foot, 0); T.truthy(f.hitTop > 0)
    T.eq(f.portraitY, 0, "no ring share: the ring sits on the frame as in Daylight")
    T.eq(ns.CastBar.At("target", DUI:Get("UnitFrames", "targetCastbar")), "power", "a cast still fits inside")
    -- A pick no style has (a profile from a newer version) reads as Daylight.
    ns.SetStyle("look.style", "gone")
    stub.RunTimers()
    T.eq(f.style, "daylight")
end)

T.test("a plugin's frame style joins every Frame style menu, keeps its heights, and its frames say they wear it", function()
    local DUI, ns = login()
    local me = DaylightUI.API.For("Slimmy")
    T.eq(me.AddFrameStyle("bad", { row = true }), false, "no label")
    T.eq(me.AddFrameStyle("slim", { label = "Slim", desc = "Slim: thin.", row = true, line = true, ring = 5,
        sizes = { player = { height = 18, powerHeight = 3 }, party = { spacing = 40 }, raid = { height = 9 } } }), true)
    local style = ns.STYLES["Slimmy:slim"]
    T.truthy(style, "taken into the unit frames")
    T.eq(style.ring, 1, "the ring share kept in range")
    T.isnil(ns.DEFAULTS.raid.sizes, "raid tiles take no style")
    local O = DUI.Options
    local look = O.GetPage("UnitFrames.colors")
    local row
    for _, page in ipairs({ look, O.GetPage("UnitFrames.player") }) do
        for _, g in ipairs(page and page.groups or {}) do
            for _, it in ipairs(g.items) do if it.label == "Frame style" then row = it end end
        end
        T.truthy(row, "a Frame style row")
        local values, order = row.choices()
        T.eq(values["Slimmy:slim"], "Slim"); T.eq(order[#order], "Slimmy:slim")
        T.truthy(string.find(row.desc, "Slim: thin.", 1, true), "its words in the row's description")
        T.eq(#O.ValidatePage(page), 0)
        row = nil
    end
    -- Wearing it: its own heights, Daylight's where it gave none.
    ns.SetStyle("look.style", "Slimmy:slim")
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "player.height"), 18)
    T.eq(DUI:Get("UnitFrames", "player.tabHeight"), ns.DEFAULTS.player.sizes.daylight.tabHeight)
    T.eq(DUI:Get("UnitFrames", "party.spacing"), 40)
    local f = ns.frames.player
    T.eq(f.style, "Slimmy:slim")
    local parts = DaylightUI.API.Parts(f)
    T.eq(parts.style, "Slimmy:slim")
    T.eq(parts.row, f.tab); T.eq(parts.line, f.line)
    DUI:Set("UnitFrames", "player.height", 22)
    -- The plugin gone (its style no longer known): Daylight, its heights kept for later.
    ns.STYLES["Slimmy:slim"] = nil
    ns.Refresh(ns.module)
    stub.RunTimers()
    T.eq(f.style, "daylight")
    T.eq(DUI:Get("UnitFrames", "player.height"), 43, "Daylight's heights back")
    T.eq(ns.module.db.player.sizes["Slimmy:slim"].height, 22, "the player's change to the style kept")
    T.eq(DaylightUI.API.Parts(f).style, "daylight")
    T.isnil(DaylightUI.API.Parts(f).line)
end)

T.test("a plugin's frame style draws as a setup guide card from its pieces", function()
    local DUI, ns = login()
    DaylightUI.API.For("Slimmy").AddFrameStyle("slim", { label = "Slim", line = true })
    local card = { inner = CreateFrame("Frame") }
    T.noerror(function() DUI.InstallerCards.Draw.frameStyle(card, "Slimmy:slim", 140, 50) end)
    T.noerror(card.redraw)
end)

-- A party button in Ribbon, made as the header would.
local function partyButton(ns, i)
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton" .. i, h)
    b:SetAttribute("unit", "party" .. i)
    stub.units["party" .. i] = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10, power = 3, maxPower = 10 }
    h.initialConfigFunction(h, b:GetName())
    stub.RunTimers()
    return b
end

T.test("Ribbon party: the target outline and the dispel glow go round the whole ribbon", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    local b = partyButton(ns, 1)
    T.truthy(b.hitTop > 0 and b.foot > 0)
    local m = b.targetMark
    local _, rel, _, _, y = m:GetPoint(1)
    T.eq(rel, b)
    T.truthy(y > b.hitTop, "over the name row")
    _, _, _, _, y = m:GetPoint(2)
    T.truthy(y < -b.foot, "under the power line")
    local up, down = ns.GroupParts.Reach(b)
    T.eq(up, b.hitTop); T.eq(down, b.foot)
    -- Back in Daylight only the tile is rounded, as before.
    ribbon(DUI, ns, false)
    up, down = ns.GroupParts.Reach(b)
    T.eq(up, 0); T.eq(down, 0)
    _, _, _, _, y = m:GetPoint(1)
    T.near(y, DaylightUI.Pixel.Px(b, ns.GroupParts.MARK_PX))
end)

T.test("Ribbon party: the holder (the unlock handle) takes in the first row and the last line", function()
    local DUI, ns = login()
    local g = ns.Party.group
    local holder = g.holder
    T.eq(holder.padUp, 0, "Daylight: no room added")
    local hDay = holder:GetHeight()
    ribbon(DUI, ns)
    local b = partyButton(ns, 1)
    T.near(holder.padUp, b.hitTop, 0.01)
    T.near(holder.padDown, b.foot, 0.01)
    local _, _, _, _, y = g.header:GetPoint(1)
    T.near(y, -holder.padUp, 0.01, "the frames start under the row")
    local cfg = DUI:Get("UnitFrames", "party")
    T.near(ns.Party.DefaultY(cfg), 160 + cfg.height / 2 + holder.padUp, 0.01, "the first frame stays where it starts")
    T.truthy(holder:GetHeight() ~= hDay)
end)

-- The backdrop piece (no shipped style uses it yet): the portrait fills the
-- frame with the name on it, and health and power are strips along its foot.
-- The ring is off, so everything that rides on it takes its place on a frame
-- without one. These build a made-up style with it.
local function backdrop(DUI, ns, style)
    if not ns.STYLES.card then addStyle(ns, "card", { backdrop = true }) end
    ns.SetStyle("look.style", style or "card")
    stub.RunTimers()
end

T.test("a backdrop style: the picture fills the frame, the name on it, health and power strips along the foot", function()
    local DUI, ns = login()
    backdrop(DUI, ns)
    local f = ns.frames.player
    T.eq(f.style, "card")
    T.truthy(f.backdropOn)
    T.truthy(f.backdrop:IsShown(), "the picture shows")
    T.falsy(f.portrait:IsShown(), "no ring")
    T.falsy(f.tab:IsShown(), "no name tab")
    T.near(f.health:GetHeight(), DaylightUI.Pixel.Snap(f, DUI:Get("UnitFrames", "player.stripHeight")))
    local p, rel, rp = f.health:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, f.separator); T.eq(rp, "TOPLEFT")
    T.eq(f.nameText:GetParent(), f.overlay, "the name on the art")
    p, rel, rp = f.nameText:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, f); T.eq(rp, "TOPLEFT")
    p, rel, rp = f.percentText:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, f.health); T.eq(rp, "TOPRIGHT")
    local _, rel3 = f.backdrop:GetPoint(3)
    T.eq(rel3, f.health, "the picture stops at the strip")
    -- The target is mirrored: its name at the right, its picture's face at the right.
    local tf = ns.frames.target
    p = tf.nameText:GetPoint(1)
    T.eq(p, "TOPRIGHT")
    p = tf.backdrop.art:GetPoint(1)
    T.eq(p, "TOPRIGHT")
end)

T.test("a backdrop style: the portrait setting picks the picture, and the model stays clear of the angled end", function()
    local DUI, ns = login()
    backdrop(DUI, ns)
    local f = ns.frames.player
    local b = f.backdrop
    DUI:Set("UnitFrames", "player.portrait", "class")
    stub.RunTimers()
    T.truthy(b.art:IsShown()); T.falsy(b.model:IsShown())
    DUI:Set("UnitFrames", "player.portrait", "3d")
    stub.RunTimers()
    T.falsy(b.art:IsShown()); T.truthy(b.model:IsShown())
    local T2 = DaylightUI.Pixel.Px(f, DaylightUI.Style.BorderPx(f))
    T.near(b.model:GetWidth(), f:GetWidth() - 2 * T2 - f.cut, 0.01, "stops before the angled end")
    DUI:Set("UnitFrames", "player.portrait", "2d")
    stub.RunTimers()
    T.truthy(b.art:IsShown()); T.falsy(b.model:IsShown())
    DUI:Set("UnitFrames", "player.portrait", "none")
    stub.RunTimers()
    T.falsy(b.art:IsShown()); T.falsy(b.model:IsShown())
    T.truthy(b:IsShown(), "the unit's colors still fill the frame")
end)

T.test("a backdrop style: a secret name, class and health draw whole", function()
    local DUI, ns = login()
    backdrop(DUI, ns)
    stub.units.target = { name = stub.Secret("Boss"), isPlayer = stub.Secret(false), reaction = stub.Secret(2),
        health = stub.Secret(50), maxHealth = stub.Secret(100), pct = stub.Secret(50) }
    local f = ns.frames.target
    T.noerror(function() ns.UF.UpdateAll(f, true) end)
    T.eq(stub.Plain(stub.Text(f.nameText)), "Boss")
end)

T.test("a backdrop style: casts sit below it, threat colors its border, elites wear the crest on its corner", function()
    local DUI, ns = login()
    backdrop(DUI, ns)
    local CB, Style = ns.CastBar, DaylightUI.Style
    T.eq(CB.At("target", DUI:Get("UnitFrames", "targetCastbar")), "below", "too thin a strip to sit inside")
    local f = ns.frames.target
    ns.UF.ApplyThreat(f, "aggro")
    T.truthy(Style.GetShell(f).opts.borderColor, "the frame's border is red")
    if f.crest then
        local _, rel = f.crest:GetPoint(1)
        T.eq(rel, f, "the crest on the frame's corner")
        T.eq(f.crest:GetParent(), f.overlay, "out of the tab's clip")
    end
end)

T.test("back to Daylight from a backdrop style puts the ring, tab and full health bar back", function()
    local DUI, ns = login()
    backdrop(DUI, ns)
    backdrop(DUI, ns, "daylight")
    local f = ns.frames.player
    T.eq(f.style, "daylight")
    T.falsy(f.backdrop:IsShown())
    T.truthy(f.portrait:IsShown())
    T.truthy(f.tab:IsShown())
    local _, rel = f.health:GetPoint(1)
    T.eq(rel, f, "the health fills the frame again")
    T.eq(f.nameText:GetParent(), f.tab)
end)

T.test("a backdrop style's options: the picture's rows, no ring or name tab rows", function()
    local DUI, ns = login()
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.player")
    local rows = {}
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do rows[it.label] = rows[it.label] or {}; table.insert(rows[it.label], it) end
    end
    local function hidden(label) return O.IsHidden(page, rows[label][1]) end
    T.truthy(hidden("Card picture")); T.truthy(hidden("Health strip height"))
    backdrop(DUI, ns)
    T.falsy(hidden("Card picture")); T.falsy(hidden("Health strip height"))
    T.truthy(hidden("Ring color")); T.truthy(hidden("Portrait size")); T.truthy(hidden("Name tab height"))
    T.truthy(hidden("Name on the bar"))
    T.eq(#O.ValidatePage(page), 0)
end)

T.test("a backdrop style on party buttons, and as a setup guide card", function()
    local DUI, ns = login()
    backdrop(DUI, ns)
    local b = partyButton(ns, 1)
    T.eq(b.style, "card")
    T.truthy(b.backdrop and b.backdrop:IsShown(), "a picture on the button")
    local c = { inner = CreateFrame("Frame") }
    T.noerror(function() DUI.InstallerCards.Draw.frameStyle(c, "card", 140, 70) end)
    T.noerror(c.redraw)
end)

T.test("bar ends: Ribbon's power line leans back in under a flipped end, and its fill follows the end it runs toward", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    DUI:Set("UnitFrames", "player.slantUnder", true)
    stub.RunTimers()
    local S = DaylightUI.Style
    local f = ns.frames.player
    local sl = S.GetSlant(f.line)
    T.eq(sl.side, "right"); T.isnil(sl.under, "the line leans the usual way")
    T.eq(sl.ref.drop.right, f:GetHeight(), "from the frame's bottom corner")
    T.eq((S.GetFillAngle(f.line.set.power)), "right")
    -- Only the outer end angled: the line follows that end alone, its fill square.
    DUI:Set("UnitFrames", "player.slant", false)
    DUI:Set("UnitFrames", "player.portrait", "none")
    DUI:Set("UnitFrames", "player.slantOuter", true)
    stub.RunTimers()
    sl = S.GetSlant(f.line)
    T.eq(sl.side, "left")
    T.isnil((S.GetFillAngle(f.line.set.power)), "its fill runs toward the straight end")
end)
