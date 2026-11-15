local stub = require("stub")

T.test("unit frame options validate against their defaults", function()
    local DUI, ns = stub.Load({ module = true, login = false })
    local errs = DUI.Options.Validate(ns.OPTIONS, ns.DEFAULTS)
    T.eq(#errs, 0, table.concat(errs, "; "))
end)

local function login(before)
    local DUI, ns = stub.Load({ module = true, before = before })
    return DUI, ns
end

T.test("login builds every frame with a mover and unit watch", function()
    local DUI, ns = login()
    for _, unit in ipairs({ "player", "target", "targettarget", "pet", "focus" }) do
        T.truthy(ns.frames[unit], unit)
        T.eq(_G["DaylightUIFrame_" .. unit], ns.frames[unit])
        T.truthy(DUI.Movers.Get("unitframes." .. unit), unit .. " mover")
    end
    T.truthy(DUI.Movers.Get("unitframes.playerCastbar"))
    T.truthy(ns.frames.target.__unitWatch)
    T.falsy(ns.frames.player.__unitWatch)
    T.truthy(DUI.Options.GetPage("UnitFrames.player"))
end)

T.test("frames take their default places", function()
    local _, ns = login()
    local p, rel, rp, x, y = ns.frames.player:GetPoint(1)
    local d = DaylightUI.Movers.DEFAULTS["unitframes.player"]
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER", "where the UI was built with it")
    T.near(x, d[1], 0.01); T.near(y, d[2], 0.01)
    DaylightUI.Movers.DEFAULTS["unitframes.player"] = nil   -- none: the module's own default
    DaylightUI.Movers.Apply("unitframes.player")
    stub.RunTimers()
    p, rel, rp, x, y = ns.frames.player:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, UIParent); T.eq(rp, "BOTTOM"); T.eq(x, -200); T.eq(y, 240)
    DaylightUI.Movers.DEFAULTS["unitframes.player"] = d
    local _, totRel = ns.frames.targettarget:GetPoint(1)
    T.eq(totRel, ns.frames.target)
end)

T.test("a saved position accounts for a non-default scale at login", function()
    local _, ns = stub.Load({ module = true, before = function()
        DaylightUIDB = { general = { scale = 2 }, positions = { ["unitframes.player"] = { 100, 50 } } }
    end })
    local p, rel, rp, x, y = ns.frames.player:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    T.near(x, 100 / 2); T.near(y, 50 / 2)
end)

T.test("changing target updates the target and its target", function()
    local _, ns = login()
    stub.units.target = { name = "Whelp", isPlayer = false, reaction = 2, health = 5, maxHealth = 10, pct = 50 }
    stub.units.targettarget = { name = "Me", isPlayer = true, class = "MAGE" }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(ns.frames.target.nameText.__text, "Whelp")
    T.eq(ns.frames.targettarget.nameText.__text, "Me")
end)

T.test("turning a frame off removes its unit watch and hides it", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "focus.enabled", false)
    T.falsy(ns.frames.focus.__unitWatch)
    T.falsy(ns.frames.focus:IsShown())
end)

T.test("a size changed in combat applies after combat", function()
    local DUI, ns = login()
    local f = ns.frames.player
    stub.EnterCombat()
    DUI:Set("UnitFrames", "player.width", 300)
    T.near(f:GetWidth(), 2 * DUI.Pixel.Snap(f, 187 / 2))
    stub.LeaveCombat()
    T.near(f:GetWidth(), 2 * DUI.Pixel.Snap(f, 300 / 2))
end)

T.test("the target aura settings reach the container", function()
    local DUI, ns = login()
    local g = ns.auras.debuffs.__groups
    T.eq(g.rest.max, 4, "others' debuffs as before")
    T.truthy(g.cure.max > 0, "the ones you can dispel get what the rows have left")
    DUI:Set("UnitFrames", "targetAuras.debuffFilter", "mine")
    T.eq(g.cure.max, 0); T.eq(g.rest.max, 0)
    T.eq(ns.auras.debuffs.__groups.mine.max, 8)
end)

T.test("the target cast bar covers the target's power bar and follows the angle", function()
    local _, ns = login()
    local _, rel = ns.targetCastbar:GetPoint(1)
    T.eq(rel, ns.frames.target.power)
    local fill = ns.targetCastbar.bar:GetStatusBarTexture()
    T.eq(#(fill.__masks or {}), #(ns.frames.target.power:GetStatusBarTexture().__masks or {}),
         "clipped to the angled end, as the power bar")
end)

T.test("Blizzard's frames are hidden at login", function()
    local _, ns = login()
    T.eq(PlayerFrame:GetParent(), ns.Blizzard.hiddenParent)
    T.eq(TargetFrame:GetParent(), ns.Blizzard.hiddenParent)
end)

T.test("logging in during combat builds when combat ends", function()
    local _, ns = login(function() stub.combat = true end)
    T.isnil(ns.frames.player)
    stub.LeaveCombat()
    T.truthy(ns.frames.player)
end)

T.test("player: angled right end clips the bars, tab sits over the left end", function()
    local _, ns = login()
    local f = ns.frames.player
    local fill = f.health:GetStatusBarTexture()
    T.eq(#(fill.__masks or {}), 2, "fill is masked at the frame end and its moving edge")
    local mask = fill.__masks[1]
    T.eq(mask.__texture, DaylightUI.MEDIA .. "mask-slant-r.png")
    T.eq(mask.__wrap, "CLAMP")
    local p, rel = mask:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, f)
    T.truthy(f.tab:IsShown())
    local tp, trel, trp = f.tab:GetPoint(1)
    T.eq(tp, "BOTTOMLEFT"); T.eq(trel, f); T.eq(trp, "TOPLEFT")
    T.eq(f.nameText:GetParent(), f.tab, "the name lives in the tab")
end)

T.test("target mirrors the player: left cut, reverse fill, tab on the right", function()
    local _, ns = login()
    local f = ns.frames.target
    T.truthy(f.health.__reverse)
    T.eq(f.health:GetStatusBarTexture().__masks[1].__texture, DaylightUI.MEDIA .. "mask-slant-l.png")
    T.eq((f.tab:GetPoint(1)), "BOTTOMRIGHT")
end)

T.test("the tab fits the name, and a secret name gets a fixed width", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "targetAuras.debuffs", false)  -- no column cap here
    local f = ns.frames.target
    stub.units.target = { name = "Whelp", isPlayer = false, reaction = 2, health = 5, maxHealth = 10, pct = 50 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local short = f.tab:GetWidth()
    stub.units.target.name = "Deadwood Pathfinder"
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(f.tab:GetWidth() > short, "longer name, wider tab")
    stub.units.target.name = stub.Secret("Boss")
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(f.tab:GetWidth(), DaylightUI.Pixel.Snap(f, f:GetWidth() * 0.5))
end)

T.test("the big health number sits in the inner corner", function()
    local _, ns = login()
    local f = ns.frames.player
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 9, maxHealth = 10, pct = 97 }
    ns.UF.UpdateAll(f, true)
    T.eq(stub.Text(f.percentText), "9", "player shows its health value")
    T.eq(f.percentText.__font[2], 20)
    local p, rel, rp = f.percentText:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, f.health); T.eq(rp, "RIGHT")
end)

T.test("turning the slant off removes the masks", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "player.slant", false)
    T.eq(#(ns.frames.player.health:GetStatusBarTexture().__masks or {}), 0)
end)

T.test("the target's debuffs start at the same spot whatever the name", function()
    local _, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Whelp", isPlayer = false, reaction = 2, health = 5, maxHealth = 10, pct = 50 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local row, x = ns.auras.debuffs.__lineSize, select(4, ns.auras.debuffs:GetPoint(1))
    stub.units.target.name = "Deadwood Pathfinder of the Long Name"
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(ns.auras.debuffs.__lineSize, row)
    T.eq(select(4, ns.auras.debuffs:GetPoint(1)), x)
end)

T.test("switching straight to another target re-reads both aura rows", function()
    local _, ns = login()
    local before = ns.auras.debuffs.__refreshes or 0
    stub.units.target = { name = "Whelp", isPlayer = false, reaction = 2, health = 5, maxHealth = 10, pct = 50 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(ns.auras.debuffs.__refreshes, before + 1)
    T.eq(ns.auras.buffs.__refreshes, (before) + 1)
end)

T.test("target cast text starts after the angled cut and fits the power bar", function()
    local _, ns = login()
    local h, f = ns.targetCastbar, ns.frames.target
    local _, _, _, x = h.text:GetPoint(1)
    T.near(x, ns.CastBar.PAD + f.cut, nil, "clear of the cut")
    T.eq(h.text.__font[2], 9, "shrunk to fit the power bar")
end)

T.test("no line along the health bar's top", function()
    local _, ns = login()
    T.eq(ns.frames.target.rim, nil)
    T.eq(ns.frames.player.rim, nil)
end)

T.test("the player's big number is its shortened health; the target's is a percent", function()
    local _, ns = login()
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = 4120, maxHealth = 5000, pct = 82 }
    ns.UF.UpdateAll(ns.frames.player, true)
    T.eq(stub.Text(ns.frames.player.percentText), "4.1K")
    stub.units.target = { name = "Whelp", isPlayer = false, reaction = 2, health = 5, maxHealth = 10, pct = 50 }
    ns.UF.UpdateAll(ns.frames.target, true)
    T.eq(stub.Text(ns.frames.target.percentText), "50")
end)

T.test("a secret health value goes straight to the shortener and the text", function()
    local _, ns = login()
    local hp = stub.Secret(4120)
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", health = hp, maxHealth = stub.Secret(5000), pct = stub.Secret(82) }
    ns.UF.UpdateAll(ns.frames.player, true)
    local t = ns.frames.player.percentText.__text
    T.eq(type(t) == "table" and t.secretFormat, "%s", "still secret: whole to the client's formatting")
    T.eq(stub.Text(ns.frames.player.percentText), "4.1K")
end)

T.test("target of target angles like the target, pet like the player, cast bar on the right", function()
    local _, ns = login()
    local tot = ns.frames.targettarget.health:GetStatusBarTexture()
    T.eq(#tot.__masks, 2); T.eq(tot.__masks[1].__texture, DaylightUI.MEDIA .. "mask-slant-l.png")
    T.truthy(ns.frames.targettarget.health.__reverse, "mirrors the target's fill")
    local pet = ns.frames.pet.health:GetStatusBarTexture()
    T.eq(#pet.__masks, 2); T.eq(pet.__masks[1].__texture, DaylightUI.MEDIA .. "mask-slant-r.png")
    local cast = ns.playerCastbar.bar:GetStatusBarTexture()
    T.eq(#cast.__masks, 2); T.eq(cast.__masks[1].__texture, DaylightUI.MEDIA .. "mask-slant-r-sharp.png")
end)

T.test("the player cast bar hangs under the player and shares its angled line", function()
    local DUI, ns = login()
    local f, h = ns.frames.player, ns.playerCastbar
    local fT = DUI.Pixel.Px(f, DUI.DB.General().borderPx)
    local p, rel, rp, x, y = h:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, f); T.eq(rp, "BOTTOMLEFT")
    T.near(y, fT, nil, "borders overlap")
    T.eq(x, 0, "the whole width, its left end under the portrait ring")
    T.eq(h:GetWidth(), f:GetWidth())
    T.truthy(h:GetFrameLevel() < f.portrait:GetFrameLevel(), "the ring covers it")
    T.falsy(h.icon:IsShown(), "no spell icon while attached: that corner's under the ring")
    local _, _, _, tx = h.text:GetPoint(1)
    T.eq(tx, ns.CastBar.PAD, "the text 3px in from the bar's edge")
    local _, brel, _, bx = h.bar:GetPoint(1)
    T.eq(brel, h); T.truthy(bx < f.ringInset, "the fill runs the whole length, under the ring too")
    DUI:Set("UnitFrames", "player.portrait", "none")
    _, _, _, x = h:GetPoint(1)
    T.eq(x, 0, "no ring: as wide as the frame")
    T.eq(h:GetWidth(), f:GetWidth())
    DUI:Set("UnitFrames", "player.portrait", "class")
    T.truthy(h:GetFrameLevel() > f:GetFrameLevel(), "drawn over the join")
    local sl = DUI.Style.GetSlant(h)
    T.eq(sl.side, "right")
    T.eq(sl.ref.frame, f, "measured from the frame")
    local total = f:GetHeight() + h:GetHeight() - fT
    T.near(sl.ref.height, total)
    T.near(sl.cut / total, f.cut / f:GetHeight(), 1e-9, "same slope as the frame")
    local mask = h.bar:GetStatusBarTexture().__masks[1]
    local mp, mrel, mrp = mask:GetPoint(1)
    T.eq(mp, "TOPRIGHT"); T.eq(mrel, f); T.eq(mrp, "TOPRIGHT")
    T.near(mask:GetHeight(), total)
end)

T.test("detaching the player cast bar hands it back to its mover", function()
    local DUI, ns = login()
    local h = ns.playerCastbar
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    local p, rel = h:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, UIParent)
    DUI:Set("UnitFrames", "playerCastbar.at", "below")
    local _, rel2 = h:GetPoint(1)
    T.eq(rel2, ns.frames.player)
end)

T.test("the joined cast bar casts no shadow along its top", function()
    local DUI, ns = login()
    local s = DUI.Style.GetShell(ns.playerCastbar)
    T.falsy(s.shadow.TOP:IsShown())
    T.falsy(s.shadow.TOPLEFT:IsShown())
    T.falsy(s.shadow.TOPRIGHT:IsShown())
    T.truthy(s.shadow.BOTTOM:IsShown(), "still shadowed underneath")
end)

T.test("focus gets an angled inner end on the right", function()
    local _, ns = login()
    local sl = DaylightUI.Style.GetSlant(ns.frames.focus)
    T.eq(sl.side, "right")
    T.truthy(sl.cut > 0)
end)

T.test("target cast text stops short of the portrait ring", function()
    local DUI, ns = login()
    local h, target = ns.targetCastbar, ns.frames.target
    local _, _, _, x = h.time:GetPoint(1)
    T.truthy(-x > target.ringInset, "time clears the ring")
    DUI:Set("UnitFrames", "target.portrait", "none")
    _, _, _, x = h.time:GetPoint(1)
    T.truthy(-x < 10)
end)

T.test("target of target and pet start clear of the rings and the cast bar", function()
    local _, ns = login()
    local tot, pet = ns.SPECS[3].default, ns.SPECS[4].default
    local R = 50 * ns.UF.PORTRAIT_SIZE / 2
    T.truthy(tot[4] > R * (1 + ns.UF.PORTRAIT_OUT), "right of the target's ring")
    T.truthy(-pet[5] > ns.DEFAULTS.playerCastbar.height, "below the attached cast bar")
end)

T.test("friendly units out of range fade; unchecked ones and enemies don't", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", friend = true, party = true, inRange = false }
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 0.45)
    T.truthy(f.fadeWhole, "dims as one picture, not layer by layer")
    stub.units.target.inRange = true
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1)
    T.truthy(f.fadeWhole, "stays ready: it can't change in a fight")
    stub.units.target = { name = "Stranger", isPlayer = true, class = "MAGE", friend = true }
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "not in the group: the game can't check, so no fade")
    stub.units.target = { name = "Wolf", isPlayer = false, reaction = 2, friend = false, inRange = false }
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "enemies never fade")
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", friend = true, party = true, inRange = stub.Secret(false) }
    ns.UF.UpdateRange(f)
    T.eq(f.__alphaFromBoolean[3], 0.45, "a secret answer goes to the client's setter")
    DUI:Set("UnitFrames", "range.enabled", false)
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", friend = true, party = true, inRange = false }
    -- (The refresh found a target for the hidden frame: it arrived, fading in.)
    for _ = 1, 20 do DUI.Fade.Animate(0.1) end
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "off")
end)

T.test("the range ticker checks fading frames and never the player", function()
    local _, ns = login()
    T.falsy(ns.frames.player.rangeFade)
    T.truthy(ns.frames.focus.rangeFade)
    stub.units.focus = { name = "Pal", isPlayer = true, class = "MAGE", friend = true, raid = true, inRange = false }
    ns.frames.focus:Show()
    stub.RunOnUpdate(ns.RangeTicker(), 0.25)
    T.eq(stub.Plain(ns.frames.focus:GetAlpha()), 0.45)
end)

T.test("yourself and ungrouped allies never fade, whatever the game answers", function()
    local _, ns = login()
    local f = ns.frames.target
    stub.units.player = { name = "Me", isPlayer = true, class = "PALADIN", friend = true, inRange = false }
    stub.units.target = stub.units.player
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "self-target")
    stub.units.pet = { name = "Wolf", friend = true, party = true, inRange = false }
    stub.units.target = stub.units.pet
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "your pet, targeted")
    stub.units.target = { name = "Stranger", isPlayer = true, class = "MAGE", friend = true, inRange = stub.Secret(false) }
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "not grouped: a secret answer is not trusted")
    T.isnil(f.__alphaFromBoolean)
end)

T.test("a picked range spell fades an enemy target out of its reach", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.player = { name = "Me", isPlayer = true, class = "MAGE", friend = true }
    stub.units.target = { name = "Boar", friend = false, spellRange = false }
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "nothing picked: strangers never fade")
    stub.knownSpells[116] = true
    DUI:Set("UnitFrames", "range.spell", "116")
    T.eq(f.rangePick, 116)
    stub.Advance(3)
    DUI.Fade.Step()
    for _ = 1, 120 do stub.RunOnUpdate(DUI.Fade.driver, 1 / 60) end
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 0.45, "out of the spell's reach")
    stub.units.target.spellRange = true
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "in reach")
    stub.units.target.spellRange = stub.Secret(false)
    ns.UF.UpdateRange(f)
    T.eq(f.__alphaFromBoolean[3], 0.45, "a secret answer goes to the client's setter")
    f.__alphaFromBoolean = nil
    stub.units.target.spellRange = nil
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "a spell that can't be cast on them leaves them alone")
    stub.knownSpells[116] = nil
    stub.units.target.spellRange = false
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "a pick this character doesn't know does nothing")
end)

T.test("a healer's range follows their heal, not the game's fixed check", function()
    local DUI, ns = login()
    local f = ns.frames.target
    stub.units.player = { name = "Me", isPlayer = true, class = "PRIEST", friend = true }
    stub.knownSpells[2050] = true
    ns.UF.ResolveRangeSpell()
    stub.units.target = { name = "Pal", isPlayer = true, class = "MAGE", friend = true, party = true,
        inRange = false, spellRange = true }
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 1, "inside Lesser Heal's range though UnitInRange says no")
    stub.units.target.spellRange = false
    stub.units.target.inRange = true
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 0.45, "outside the heal's range")
    stub.units.target.spellRange = stub.Secret(false)
    ns.UF.UpdateRange(f)
    T.eq(f.__alphaFromBoolean[3], 0.45, "a secret answer goes to the client's setter")
    f.__alphaFromBoolean = nil
    stub.units.target.spellRange = nil
    stub.units.target.inRange = false
    ns.UF.UpdateRange(f)
    T.eq(stub.Plain(f:GetAlpha()), 0.45, "an invalid spell check falls back to the game's check")
    stub.knownSpells[2050] = nil
    stub.units.player.class = "WARRIOR"
    ns.UF.ResolveRangeSpell()
    T.isnil(ns.UF.rangeSpell, "no heal: the game's check")
end)
