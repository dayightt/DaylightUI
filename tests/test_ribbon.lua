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
    T.truthy(f.ribbon)
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
    T.falsy(f.ribbon)
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
    T.near(p:GetWidth(), 2 * DaylightUI.Pixel.Snap(f, H * ns.UF.RIBBON_RING))
    T.near(f.portraitY, (f.hitTop - f.foot) / 2)
    local _, _, _, _, y = p:GetPoint(1)
    T.near(y, f.portraitY)
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
    T.truthy(b.ribbon)
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
    local cast = O.GetPage("UnitFrames.castbars")
    local at
    for _, g in ipairs(cast and cast.groups or {}) do
        for _, it in ipairs(g.items) do if it.key == "targetCastbar.at" then at = it end end
    end
    T.truthy(at, "the target's cast bar position row")
    local _, order = at.choices()
    for _, v in ipairs(order) do T.truthy(v ~= "power", "no Inside the frame") end
    T.eq(at.shownAs("power"), at.values.below, "a saved Inside reads as Below")
end)

-- Every option row of the four frames that wear Ribbon, set to each of its
-- values while Ribbon is on, with the frames laid out after each, raises no
-- error. The rows' own tests check what each does. This checks they still
-- work on the new shape.
T.test("Ribbon: every option of the player, target, focus and party pages works", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    local O = DUI.Options
    local tried = 0
    for _, id in ipairs(ns.RIBBON_FRAMES) do
        local page = O.GetPage("UnitFrames." .. id)
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items or {}) do
                if it.key and O.VALUE[it.type] and it.type ~= "color" and it.type ~= "gradient" and it.key ~= id .. ".style" then
                    local before = O.Get(page, it)
                    local values = {}
                    if it.type == "toggle" then
                        values = { true, false }
                    elseif it.type == "slider" then
                        values = { it.min, it.max }
                    elseif it.type == "dropdown" then
                        local vals, order = it.values, it.order
                        if it.choices then vals, order = it.choices() end
                        order = order or {}
                        if #order == 0 then for k in pairs(vals or {}) do order[#order + 1] = k end end
                        values = order
                        -- Every font and bar texture takes the same path, and each pick repaints
                        -- the whole UI, so General's, the next, the last and a display font stand
                        -- in for them all.
                        if string.match(it.key, "%.media%.") and #order > 4 then
                            values = { order[1], order[2], order[#order] }
                            for _, k in ipairs(order) do
                                local f = DUI.Style.FONTS[k]
                                if f and f.display then values[#values + 1] = k; break end
                            end
                        end
                    end
                    for _, v in ipairs(values) do
                        local ok, err = pcall(O.Set, page, it, v)
                        T.truthy(ok, id .. " " .. it.key .. " = " .. tostring(v) .. ": " .. tostring(err))
                        ok, err = pcall(stub.RunTimers)
                        T.truthy(ok, id .. " " .. it.key .. " = " .. tostring(v) .. " (layout): " .. tostring(err))
                        tried = tried + 1
                    end
                    pcall(O.Set, page, it, before)
                    stub.RunTimers()
                end
            end
        end
    end
    T.truthy(tried > 200, "it went through the rows: " .. tried)
    T.truthy(ns.frames.player.ribbon, "still Ribbon at the end")
end)

T.test("the setup guide's Frames page offers the style as two drawn cards", function()
    local DUI = login()
    local found
    for _, step in ipairs(DUI.InstallerPages.TOUR) do
        for _, g in ipairs(step.groups or {}) do
            if g.cards and g.cards.key == "look.style" then found = g end
        end
    end
    T.truthy(found, "a Frame style group")
    T.eq(found.cards.draw, "frameStyle")
    for _, key in ipairs({ "daylight", "ribbon" }) do
        local card = { inner = CreateFrame("Frame") }
        T.noerror(function() DUI.InstallerCards.Draw.frameStyle(card, key, 140, 50) end)
        T.noerror(card.redraw)
    end
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
