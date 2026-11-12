local stub = require("stub")

-- The game's nameplates: a plate frame per unit, each with the game's own
-- unit frame on it.
local plates

local function newPlate(i)
    local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
    np.UnitFrame = CreateFrame("Button", nil, np)
    np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
    np.UnitFrame.WidgetContainer = CreateFrame("Frame", nil, np.UnitFrame)
    np.UnitFrame.name = np.UnitFrame:CreateFontString(nil, "OVERLAY")
    np.UnitFrame:RegisterEvent("UNIT_HEALTH")
    np.UnitFrame.castBar:RegisterEvent("UNIT_SPELLCAST_START")
    function np:CanChangeHitTestPoints() return true end
    function np:SetAllHitTestPoints(f) self.__hit = f end
    function np:SetHitTestPoints() self.__hit = "the game's" end
    function np:ClearAllHitTestPoints() self.__hit = nil end
    function np:SetStackingBoundsFrame(f) self.__stack = f end
    return np
end

local function world()
    plates = {}
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        local i = tonumber(string.match(unit, "%d+"))
        if not i or not stub.units[unit] then return nil end
        plates[i] = plates[i] or newPlate(i)
        return plates[i]
    end }
    _G.issecure = function() return false end
    _G.UnitCanAttack = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile == true end
    _G.UnitReaction = function(u) local x = stub.units[u]; return x and x.reaction end
    _G.IsInInstance = function() return false end
    _G.UnitGroupRolesAssigned = function() return stub.role or "DAMAGER" end
    Enum.TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
    _G.C_TooltipInfo = { GetUnit = function(u) return stub.tooltips and stub.tooltips[u] end }
    stub.units = {
        player = { name = "Me", class = "PRIEST", isPlayer = true },
        nameplate1 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 },
        nameplate2 = { name = "Jaina", isPlayer = true, class = "MAGE", reaction = 5, health = 90, maxHealth = 100 },
    }
end

local function login(before)
    stub.Load({ nameplates = true, before = function()
        world()
        if before then before() end
    end })
    stub.RunTimers()
    -- The shipped default is the class gradient; most tests are about plain colors.
    DaylightUI:Set("Nameplates", "healthColor", "class")
    DaylightUI:Set("Nameplates", "nameColor", "class")
    DaylightUI:Set("Nameplates", "friendly.nameColor", "class")
    DaylightUI:Set("Nameplates", "friendly.healthColor", "class")
    -- Off as shipped (tested below). The threat tests want them on.
    DaylightUI:Set("Nameplates", "threat", true)
    stub.RunTimers()
    return stub.nameplates
end

-- A plate put up, and the frame after it, when its level, guild or job line,
-- quest mark and raid marker arrive (Plate.UpdateFirst).
local function added(unit)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", unit)
    stub.RunTimers()
    return stub.nameplates.Manager.byUnit[unit]
end

-- The bar's fill color, whichever way it was set.
local function fillRed(p)
    local tex = p.health:GetStatusBarTexture()
    if tex and tex.__vertex then return tex.__vertex[1] end
    return p.health.__barColor and p.health.__barColor[1]
end

T.test("nameplates: the game's plate is put away and ours shows the unit", function()
    local NP = login()
    local p = added("nameplate1")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local np = plates[1]
    T.eq(np.UnitFrame:GetAlpha(), 0, "the game's plate frame unseen")
    T.eq(np.UnitFrame:GetParent(), np, "left where the game put it (never re-parented)")
    -- Switched off, not just hidden. Left running under the addon's plate it
    -- answered ~46 events per plate and rebuilt its aura icons on every aura change.
    T.falsy(np.UnitFrame:IsEventRegistered("UNIT_HEALTH"), "its events stopped")
    T.falsy(np.UnitFrame.castBar:IsEventRegistered("UNIT_SPELLCAST_START"), "and its cast bar's")
    T.falsy(np.UnitFrame:IsEventRegistered("PLAYER_TARGET_CHANGED"), "nothing at all (its soft-target icon is the game's driver's)")
    -- Given back, it has what it registered when it was made. Its unit events
    -- come back with the next unit the game gives it.
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.truthy(np.UnitFrame:IsEventRegistered("UPDATE_MOUSEOVER_UNIT"), "given back: its own events again")
    T.truthy(np.UnitFrame:IsEventRegistered("PLAYER_TARGET_CHANGED"))
    p = added("nameplate1")
    T.falsy(np.UnitFrame:IsEventRegistered("UPDATE_MOUSEOVER_UNIT"), "and off again under ours")
    T.truthy(np.UnitFrame.WidgetContainer:IsIgnoringParentAlpha(), "its widgets stay in view")
    -- Alpha alone gets undone in combat, but its pieces are moved off it, so
    -- nothing of it can be drawn even then.
    T.falsy(np.UnitFrame.castBar:GetParent() == np.UnitFrame, "its pieces parked off it")
    T.falsy(np.UnitFrame.castBar:IsVisible(), "where they can't be seen")
    T.eq(np.UnitFrame.WidgetContainer:GetParent(), np.UnitFrame, "its widgets stay on it")
    -- Its name text stays on it, see-through, because the game hangs the plate's
    -- click area from it. Hiding it made plates invisible for EllesmereUI.
    T.eq(np.UnitFrame.name:GetParent(), np.UnitFrame, "its name stays on it")
    T.eq(np.UnitFrame.name:GetAlpha(), 0, "see-through")
    T.truthy(p:IsShown())
    T.eq(p.name.__text, "Searing Whelp")
    T.eq(stub.Plain(p.health:GetValue()), 60)
    T.eq(stub.Text(p.percent), "60%")
    T.isnil(np.__hit, "where it's clicked stays the game's (EllesmereUI's way)")
    T.eq(np.__stack, p.stack, "it stacks by our shape")
end)

T.test("nameplates: another nameplate addon loaded is warned about once in chat", function()
    login(function() stub.loadedAddOns.TidyPlates_ThreatPlates = true end)
    T.truthy(stub.ChatContains("Threat Plates is also loaded"))
    T.falsy(stub.ChatContains("Plater is also loaded"))
end)

T.test("nameplates: the game's plates (what takes the clicks) cover ours, centered on them", function()
    local size
    login(function()
        C_NamePlate.SetNamePlateSize = function(w, h) size = { w, h } end
    end)
    local c = stub.nameplates.cfg
    T.truthy(size, "set at login")
    local function expected()
        local pad = c.clickPad
        local up = c.offsetY + c.height / 2 + c.nameSize + stub.nameplates.Plate.NAME_GAP + 2
        local down = c.offsetY - c.height / 2
        return (c.width + 2 * pad) * c.scale, 2 * (math.max(math.abs(up), math.abs(down)) + pad) * c.scale
    end
    local w, h = expected()
    T.eq(size[1], w, "the bar's width and the click margin"); T.eq(size[2], h, "up to the name, either way from the center")
    local p = added("nameplate1")
    local point, rel, relPoint, x, y = p:GetPoint(1)
    T.eq(point, "CENTER"); T.eq(rel, plates[1]); T.eq(relPoint, "CENTER")
    T.eq(x, 0); T.eq(y, stub.nameplates.cfg.offsetY, "centered, raised by the Height offset")
    DaylightUI:Set("Nameplates", "height", 20)
    stub.RunTimers()
    T.eq(size[2], select(2, expected()), "again when the bar changes")
    DaylightUI:Set("Nameplates", "offsetY", 10)
    stub.RunTimers()
    local _, _, _, _, y2 = p:GetPoint(1)
    T.eq(y2, 10, "the height setting nudges it")
end)

T.test("nameplates: the level at the bar's left end, in its difficulty color; ?? and + as the game shows them", function()
    -- Use the server's answer for the unit, as the game's target frame does.
    -- Retail's level math (GetCreatureDifficultyColor) said grey for a level 42
    -- looking at a 36, the server says green.
    local lvl, class = 36, "normal"
    login(function()
        _G.UnitLevel = function(u) if u == "player" then return 42 end return lvl end
        _G.UnitClassification = function() return class end
    end)
    local p = added("nameplate1")
    T.truthy(p.level:IsShown())
    T.eq(p.level.__text, "36")
    T.truthy(p.level.__textColor[2] > p.level.__textColor[1], "green: 6 under a 42, not grey")
    lvl, class = 47, "elite"
    stub.FireEvent("UNIT_LEVEL", "nameplate1")
    T.eq(p.level.__text, "47+", "an elite")
    T.truthy(p.level.__textColor[1] > p.level.__textColor[2], "red: a hard one")
    lvl = -1
    stub.FireEvent("UNIT_CLASSIFICATION_CHANGED", "nameplate1")
    T.eq(p.level.__text, "??")
    local friend = added("nameplate2")
    T.falsy(friend.level:IsShown(), "not on friendly plates")
end)

T.test("nameplates: the level's own color and size (levelColor, levelCustom, levelSize); ?? stays red", function()
    local lvl = 12
    login(function()
        _G.UnitLevel = function() return lvl end
        _G.UnitClassification = function() return "normal" end
        _G.GetCreatureDifficultyColor = function() return { r = 0.25, g = 0.75, b = 0.25 } end
    end)
    local p = added("nameplate1")
    DaylightUI:Set("Nameplates", "levelColor", "custom")
    DaylightUI:Set("Nameplates", "levelCustom", { 0.2, 0.4, 0.9 })
    stub.RunTimers()
    T.eq(p.level.__textColor[3], 0.9, "the picked color")
    DaylightUI:Set("Nameplates", "levelColor", "white")
    stub.RunTimers()
    local w = DaylightUI.Style.INK.VALUE
    T.eq(p.level.__textColor[1], w[1], "white")
    lvl = -1
    stub.FireEvent("UNIT_LEVEL", "nameplate1")
    T.truthy(p.level.__textColor[1] > p.level.__textColor[2], "?? keeps its red")
    DaylightUI:Set("Nameplates", "levelSize", 17)
    stub.RunTimers()
    T.eq(select(2, p.level:GetFont()), 17, "its own size")
end)

T.test("nameplates: friendly plates are just the name by default, no casts or auras", function()
    login()
    local p = added("nameplate2")
    T.truthy(p.friendly)
    T.falsy(p.hp:IsShown(), "just the name")
    T.falsy(p:IsEventRegistered("UNIT_SPELLCAST_START"), "no casts")
    for _, c in pairs(p.auras) do T.falsy(c:IsShown(), "no auras") end
    DaylightUI:Set("Nameplates", "friendly.enabled", true)
    stub.RunTimers()
    T.truthy(p.hp:IsShown(), "or a thin bar under it")
    T.eq(p.hp:GetHeight(), DaylightUI:Get("Nameplates", "friendly.height"))
    -- Its border never swallows the whole thin bar. Some fill stays visible.
    T.truthy(2 * p.body.T < p.hp:GetHeight(), "room left for the fill")
end)

T.test("nameplates: friendly plates have their own width, health text, level, name size and buffs", function()
    login()
    local set = function(k, v) DaylightUI:Set("Nameplates", k, v) end
    set("friendly.enabled", true)
    set("friendly.width", 90)
    set("friendly.nameSize", 10)
    stub.RunTimers()
    local p, mob = added("nameplate2"), added("nameplate1")
    T.eq(p.hp:GetWidth(), 90, "its own width")
    T.eq(mob.hp:GetWidth(), DaylightUI:Get("Nameplates", "width"), "enemies keep theirs")
    T.falsy(p.percent:IsShown(), "no health text by default")
    T.falsy(p.level:IsShown(), "no level by default")
    set("friendly.percent", true)
    set("friendly.level", true)
    stub.RunTimers()
    T.truthy(p.percent:IsShown()); T.truthy(p.level:IsShown())
    set("percent", false)
    stub.RunTimers()
    T.truthy(p.percent:IsShown(), "the enemy switch leaves friends be")
    T.falsy(mob.percent:IsShown())
    -- Your buffs: only on friendly plates, only when on.
    T.falsy(p.auras.helps:IsShown())
    set("friendly.myBuffs", true)
    stub.RunTimers()
    T.truthy(p.auras.helps:IsShown(), "your buffs on a friend")
    T.falsy(mob.auras.helps:IsShown(), "never on an enemy")
    T.falsy(p.auras.debuffs:IsShown(), "no enemy auras on a friend")
end)

T.test("nameplates: a friendly plate's health bar is filled and follows health changes", function()
    login()
    DaylightUI:Set("Nameplates", "friendly.enabled", true)
    stub.RunTimers()
    local p = added("nameplate2")
    T.truthy(p.hp:IsShown())
    T.eq(stub.Plain(p.health:GetValue()), stub.units.nameplate2.health)
    stub.units.nameplate2.health = 40
    stub.FireEvent("UNIT_HEALTH", "nameplate2")
    T.eq(stub.Plain(p.health:GetValue()), 40, "updates on health changes")
end)

T.test("nameplates: incoming heals and an absorb shield show on the health bar, and can be turned off", function()
    login()
    local p = added("nameplate1")
    stub.units.nameplate1.incoming = 20
    stub.units.nameplate1.absorbs = 10
    stub.FireEvent("UNIT_HEAL_PREDICTION", "nameplate1")
    T.truthy(p.heals:IsShown())
    T.eq(stub.Plain(p.heals:GetValue()), 20)
    T.truthy(p.absorbs:IsShown())
    T.eq(stub.Plain(p.absorbs:GetValue()), 10)
    DaylightUI:Set("Nameplates", "predictHeals", false)
    stub.RunTimers()
    T.falsy(p.heals:IsShown())
    T.truthy(p.absorbs:IsShown(), "the shield stays on its own setting")
    stub.units.nameplate1.incoming = 30
    DaylightUI:Set("Nameplates", "predictHeals", true)
    stub.RunTimers()
    stub.FireEvent("UNIT_HEAL_PREDICTION", "nameplate1")
    T.truthy(p.heals:IsShown(), "back on")
    T.eq(stub.Plain(p.heals:GetValue()), 30, "with the amount now")
end)

T.test("nameplates: a ring that never lit costs nothing when its plate leaves", function()
    login()
    local p = added("nameplate2")
    T.falsy(p.glow:IsShown())
    local writes, set = 0, p.glow.pieces.RIGHT.SetAlpha
    p.glow.pieces.RIGHT.SetAlpha = function(...) writes = writes + 1; return set(...) end
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    p.glow.pieces.RIGHT.SetAlpha = set
    T.eq(writes, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a targeted name-only plate gets no outline or glow round its hidden bar", function()
    login()
    local p = added("nameplate2")
    T.falsy(p.hp:IsShown(), "name only")
    stub.units.target = stub.units.nameplate2
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(p.outline:IsShown(), "no outline round nothing")
    DaylightUI:Set("Nameplates", "targetStyle", "glow")
    stub.RunTimers()
    T.falsy(p.glow:IsShown(), "no glow either")
    stub.units.target = nil
end)

T.test("nameplates: the name draws over the bar, the target outline and the border's caps", function()
    login()
    DaylightUI:Set("Nameplates", "namePos", "center")   -- on the bar
    stub.RunTimers()
    local p = added("nameplate1")
    local top = p.name:GetParent()
    T.eq(top, p.nameFrame)
    T.eq(p.sub:GetParent(), top, "the guild line too")
    T.truthy(top:GetFrameLevel() > p.health:GetFrameLevel(), "over the fill")
    T.truthy(top:GetFrameLevel() > p.outline:GetFrameLevel(), "over the target outline")
    T.truthy(top:GetFrameLevel() > p.body.over:GetFrameLevel(), "over the corner caps")
    -- Name-only: the bar hides, the name stays.
    local f = added("nameplate2")
    T.falsy(f.hp:IsShown())
    T.truthy(f.nameFrame:IsVisible() and f.name:IsShown(), "the name still shows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a game object (fishing bobber) shows its name with no health bar", function()
    login()
    stub.units.nameplate3 = { name = "Fishing Bobber", hostile = true, reaction = 2, health = 1, maxHealth = 1 }
    local old = UnitIsGameObject
    UnitIsGameObject = function(unit) return unit == "nameplate3" end
    local p = added("nameplate3")
    UnitIsGameObject = old
    T.falsy(p.hp:IsShown(), "no bar")
    T.falsy(p.level:IsShown(), "no level")
    local enemy = added("nameplate1")
    T.truthy(enemy.hp:IsShown(), "a real enemy keeps its bar")
end)

T.test("nameplates: every plate is the UI's size times Scale, whatever the game scales its plate to", function()
    login()
    local p = added("nameplate1")
    T.truthy(p:IsIgnoringParentScale(), "the game shrinks simplified plates (minions, totems) to 0.3: not ours")
    T.near(p:GetScale(), UIParent:GetEffectiveScale(), 1e-6)
    DaylightUI:Set("Nameplates", "scale", 1.5)
    stub.RunTimers()
    T.near(p:GetScale(), UIParent:GetEffectiveScale() * 1.5, 1e-6)
end)

T.test("nameplates: our plates are built ahead, away from the game's, then moved onto one", function()
    local NP = login()
    local before = NP.Manager.Spares()
    T.eq(before, NP.Manager.PREPARE - 2, "built at login; the two plates already up took theirs")
    stub.units.nameplate3 = { name = "Wolf", hostile = true, reaction = 2 }
    local p = added("nameplate3")
    T.eq(NP.Manager.Spares(), before - 1, "one of those taken, not a new one made on the plate")
    T.eq(p:GetParent(), plates[3], "moved onto the game's plate")
    T.eq(select(2, p:GetPoint(1)), plates[3], "centered on it")
end)

T.test("nameplates: your target's plate grows in one step; the game's own plate scaling is pinned off", function()
    local cvars = {}
    login(function() _G.SetCVar = function(k, v) cvars[k] = v end end)
    T.eq(cvars.nameplateMinScale, "1", "the game's distance scaling off")
    T.eq(cvars.nameplateMaxScale, "1")
    T.eq(cvars.nameplateSelectedScale, "1", "and its own target zoom (ours does it)")
    DaylightUI:Set("Nameplates", "others.scale", 0.85); stub.RunTimers()   -- the others shrink too (off by default)
    local a, b = added("nameplate1"), added("nameplate2")
    local ui = UIParent:GetEffectiveScale()
    T.near(a:GetScale(), ui, 1e-6, "no target: normal size")
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(a:GetScale(), ui * 1.15, 1e-6, "the target grows, at once")
    T.near(b:GetScale(), ui * 0.85, 1e-6, "the rest shrink, at once")
    DaylightUI:Set("Nameplates", "targetScale", false); stub.RunTimers()
    T.near(a:GetScale(), ui, 1e-6, "off: all normal")
    T.near(b:GetScale(), ui, 1e-6)
    DaylightUI:Set("Nameplates", "targetScale", true); stub.RunTimers()
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.near(b:GetScale(), ui, 1e-6, "the target's plate gone: back to normal")
    stub.units.target = nil
end)

T.test("nameplates: a target switch sets each size once and runs nothing per frame", function()
    login()
    DaylightUI:Set("Nameplates", "others.scale", 0.85); stub.RunTimers()   -- the others shrink too (off by default)
    local P = stub.nameplates.Plate
    local a, b = added("nameplate1"), added("nameplate2")
    T.isnil(P.ScaleDriver, "no glide driver: the game zooms the target")
    local calls = {}
    for _, p in ipairs({ a, b }) do
        local set = p.SetScale
        p.SetScale = function(self, v) calls[self] = (calls[self] or 0) + 1; return set(self, v) end
    end
    for i = 1, 10 do
        stub.units.target = (i % 2 == 0) and stub.units.nameplate1 or stub.units.nameplate2
        stub.FireEvent("PLAYER_TARGET_CHANGED")
    end
    T.truthy(calls[a] <= 10 and calls[b] <= 10, "at most one size per switch, no steps in between")
    T.truthy(calls[a] >= 9 and calls[b] >= 9, "(an unchanged size is skipped)")
    stub.units.target = nil
    a.SetScale, b.SetScale = nil, nil
end)

T.test("nameplates: the target outline draws on from left to right over 0.5 s, and back off; no clipping", function()
    login()
    local a = added("nameplate1")
    local ring = a.outline
    local e = ring.pieces
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(ring:IsShown(), "the outline is up at once")
    T.eq(ring:GetParent(), a, "no clipping window: clipping is costly to draw")
    T.eq(e.TOP:GetNumPoints(), 1, "the top edge grows from its left end")
    T.eq(e.RIGHT:GetAlpha(), 0, "the right end isn't there yet")
    T.eq(e.LEFT:GetAlpha(), 1, "the left end is")
    local full = a.hp:GetWidth()
    local d = DaylightUI.Motion.Driver()
    stub.RunOnUpdate(d, 0.1)
    local w = e.TOP:GetWidth()
    T.truthy(w > 0 and w < full, "part of the way across")
    for _ = 1, 40 do if d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end end
    T.eq(e.TOP:GetNumPoints(), 2, "then pinned at both ends again, following the bar")
    T.eq(e.RIGHT:GetAlpha(), 1, "the right end in")
    -- Untargeted: it runs back, right to left, then hides.
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(ring:IsShown(), "still there as it runs back")
    stub.RunOnUpdate(d, 0.1)
    w = e.TOP:GetWidth()
    T.truthy(w > 0 and w < full, "part of the way back")
    T.eq(e.RIGHT:GetAlpha(), 0, "the right end gone first")
    -- Targeted again halfway back: it turns round from where it is.
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(e.TOP:GetWidth(), w, 1e-6, "no jump")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    for _ = 1, 60 do if d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end end
    T.falsy(ring:IsShown(), "gone once it's back")
    T.eq(e.TOP:GetNumPoints(), 2, "and laid out whole for next time")
    DaylightUI.DB.General().motion = false
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(ring:IsShown()); T.eq(e.TOP:GetNumPoints(), 2, "motion off: all at once")
    T.eq(e.RIGHT:GetAlpha(), 1)
    stub.units.target = nil
end)

T.test("nameplates: the target's plate and the others can have their own width, height and scale", function()
    local NP = login(function() stub.units.nameplate3 = { name = "Wolf", hostile = true, reaction = 2 } end)
    local a, b = added("nameplate1"), added("nameplate3")
    local c = stub.nameplates.cfg
    -- Defaults: same width and height as everyone, only the scale differs,
    -- so the look stays exactly as before.
    T.eq(a.hp:GetWidth(), c.width, "no width change by default")
    T.eq(b.hp:GetWidth(), c.width)
    T.eq(b.hp:GetHeight(), c.height)
    DaylightUI:Set("Nameplates", "target.width", 1.5)
    DaylightUI:Set("Nameplates", "target.height", 2)
    DaylightUI:Set("Nameplates", "others.width", 0.5)
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(a.hp:GetWidth(), c.width * 1.5, "the target's own width")
    T.eq(a.hp:GetHeight(), c.height * 2, "and height")
    T.eq(b.hp:GetWidth(), c.width * 0.5, "an other plate's own width")
    T.eq(b.hp:GetHeight(), c.height, "others.height unset: unchanged")
    -- The cast bar and the debuff row line up with the (now wider) bar.
    T.eq(a.cast:GetWidth(), a.hp:GetWidth())
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(a.hp:GetWidth(), c.width, "no target: back to the plain size")
end)

T.test("nameplates: ours comes off a game plate when its unit goes, and a marked one is never reused", function()
    local NP = login()
    local p = added("nameplate1")
    local spares = NP.Manager.Spares()
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.falsy(p:GetParent() == plates[1], "off the game's plate")
    T.eq(NP.Manager.Spares(), spares + 1, "back with the spares")
    -- One that became forbidden anyway is left out.
    function p:IsForbidden() return true end
    local q = added("nameplate1")
    T.falsy(q == p, "a fresh one instead")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a plate that makes ours unusable once it's on is given up, and the game's stays", function()
    local NP = login()
    stub.units.nameplate4 = { name = "Guard", hostile = true, reaction = 2 }
    local np = C_NamePlate.GetNamePlateForUnit("nameplate4")
    -- The next spare can't be read once it's on this plate, as the client
    -- does with some plates that don't say they're forbidden.
    local p = NP.Manager.Take()
    function p:GetEffectiveScale() if self:GetParent() == np then error("forbidden") end return 1 end
    NP.Manager.Release(p)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate4")
    T.isnil(NP.Manager.byUnit.nameplate4, "not ours")
    T.eq(np.UnitFrame:GetAlpha(), 1, "the game's plate still showing")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a plate the game keeps from addons is left alone", function()
    local NP = login()
    stub.units.nameplate3 = { name = "Guard", reaction = 5 }
    local np = C_NamePlate.GetNamePlateForUnit("nameplate3")
    function np:IsForbidden() return true end
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
    T.isnil(NP.Manager.byUnit.nameplate3)
    T.eq(np.UnitFrame:GetAlpha(), 1, "the game's plate untouched")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: cast times are written at once, then every 0.05 s by one shared ticker", function()
    local NP = login()
    stub.units.nameplate3 = { name = "Wolf", hostile = true, reaction = 2 }
    local p, q = added("nameplate1"), added("nameplate3")
    local ticker = NP.Cast.Ticker
    T.falsy(ticker:IsShown(), "nothing casting: nothing runs")
    T.isnil(p.cast:GetScript("OnUpdate"), "no OnUpdate per plate")
    local writes = 0
    for _, c in ipairs({ p.cast, q.cast }) do
        local real = c.time.SetFormattedText
        c.time.SetFormattedText = function(self, ...) writes = writes + 1; return real(self, ...) end
    end
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.units.nameplate3.cast = { name = "Howl", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
    T.eq(writes, 2, "each new cast writes its time at once")
    T.truthy(ticker:IsShown(), "the ticker runs while something casts")
    local tick = ticker:GetScript("OnUpdate")
    tick(ticker, 0.016); tick(ticker, 0.016)
    T.eq(writes, 2, "not again within 0.05 s")
    tick(ticker, 0.03)
    T.eq(writes, 4, "then every casting plate, once")
    stub.units.nameplate1.cast, stub.units.nameplate3.cast = nil, nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    stub.FireEvent("UNIT_SPELLCAST_STOP", "nameplate3")
    tick(ticker, 0.06)
    T.falsy(ticker:IsShown(), "nothing casting: it stops")
    T.eq(NP.Cast.TIME_EVERY, 0.05)
end)

T.test("nameplates: the cast time sits inside the bar's angled end", function()
    local NP = login()
    local p = added("nameplate1")
    local c, g = p.cast, p.cast.body.geo
    T.truthy(g and g.cutBottom > 0, "the cast bar is angled")
    local _, _, _, x = c.time:GetPoint(1)
    local slantAtTextBottom = g.cutTop + g.lean * (0.5 + NP.Cast.TEXT * 0.5)
    T.truthy(-x >= slantAtTextBottom + c.body.T, "the time's right edge is in from the slant at its bottom")
end)

T.test("nameplates: a cast shows steady, whatever the interruptible flag says", function()
    login()
    local p = added("nameplate1")
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    local c = p.cast
    T.truthy(c:IsShown())
    T.eq(c.text.__text, "Fireball")
    T.eq(c.pulse, nil, "nothing to flash with")
    T.eq(c.light:GetAlpha(), 0, "the fill unlit")
    stub.units.nameplate1.cast.notInterruptible = stub.Secret(true)
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.eq(c.light:GetAlpha(), 0, "a secret flag: still unlit")
    T.falsy(c.light.__vertexFromBoolean, "and never asked")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1")
    T.eq(c.text.__text, INTERRUPTED or "Interrupted")
    stub.units.nameplate1.cast = nil
    stub.RunTimers()
    T.truthy(c:IsShown(), "fading out")
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 30 do stub.RunOnUpdate(d, 1 / 60) end
    T.falsy(c:IsShown(), "then gone")
end)

T.test("nameplates: the name sits above the bar; the cast bar is attached under it", function()
    login()
    local p = added("nameplate1")
    local point, rel, relPoint = p.name:GetPoint(1)
    T.eq(point, "BOTTOM"); T.eq(rel, p.hp); T.eq(relPoint, "TOP", "the name above the bar")
    local _, crel, crelPoint = p.cast:GetPoint(1)
    T.eq(crel, p.hp); T.eq(crelPoint, "TOPLEFT", "the cast bar hangs from the bar")
    T.eq(select(5, p.cast:GetPoint(1)), -(p.hp:GetHeight() + stub.nameplates.Cast.GAP), "under it, a small gap between")
    local g = p.cast.body.geo
    T.truthy(g.angled, "carrying the bar's angled end on")
    local cut, hh = p.hpCut, p.hp:GetHeight()
    T.near(g.cutTop, cut * (hh + stub.nameplates.Cast.GAP) / hh, 1e-6, "the line at its top: where the bar's line has got to")
    T.near(g.cutBottom - g.cutTop, cut * p.cast:GetHeight() / hh, 1e-6, "and on down at the same angle")
    -- Its interrupt highlight is flat light on its own fill, in its shape.
    local light = p.cast.light
    T.eq(select(2, light:GetPoint(1)), p.cast.bar:GetStatusBarTexture(), "on the fill, no lines round it")
    T.eq(light.__texture, "Interface\\Buttons\\WHITE8x8", "flat, not the shaded bar texture")
    T.truthy(light.__masks and #light.__masks == 1, "cut by the fill's angled edge (which is also the bar's end)")
end)

T.test("nameplates: the spell icon is off by default; on, it sits left of the cast bar", function()
    login()
    local p = added("nameplate1")
    local c = p.cast
    T.falsy(c.iconBox:IsShown(), "off by default")
    T.eq(select(2, c.bar:GetPoint(1)), c, "the bar takes the whole cast bar")
    DaylightUI:Set("Nameplates", "castIcon", true)
    stub.RunTimers()
    T.truthy(c.iconBox:IsShown())
    local point, rel, relPoint = c.iconBox:GetPoint(1)
    T.eq(point, "TOPRIGHT"); T.eq(rel, c); T.eq(relPoint, "TOPLEFT", "outside, left of the bar")
end)

T.test("nameplates: your target's plate wears the accent", function()
    login()
    DaylightUI:Set("general", "accent", "daylight")
    local p = added("nameplate1")
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(p.outline:IsShown(), "outlined")
    T.near(p.outline.pieces.TOP.__vertex[1], 0.72, 1e-3, "in the Daylight accent")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(p.outline:IsShown())
end)

T.test("nameplates: the target outline's corners follow the border's rounding", function()
    login()
    local p = added("nameplate1")
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local e = p.outline.pieces
    local R = p.body.radius
    T.truthy(R > 0, "the plate's border is rounded")
    T.truthy(p.outline.round.TOPLEFT, "the square end's corners curve")
    T.eq(p.body.layers.band.TOPLEFT.__wrap, "CLAMP", "the corner art never blends across its edges")
    T.eq(p.body.fillet.TOPLEFT.__wrap, "CLAMP", "nor do its caps")
    T.truthy(e.TOPLEFT:GetWidth() > e.LEFT:GetWidth(), "wider than the line, round the curve")
    T.falsy(e.TOPLEFT.__texture == e.LEFT.__texture, "a curved piece, not the plain line")
    T.falsy(p.outline.round.TOPRIGHT, "the angled end stays sharp")
    T.eq(select(5, e.TOP:GetPoint(1)), 0, "the top starts at the bar's top")
    T.truthy(select(4, e.TOP:GetPoint(1)) > 0, "past the corner")
    T.truthy(select(4, e.TOP:GetPoint(1)) < R, "a little inside the curve, so no step where they meet")
    -- Square corners in the look settings: square outline corners again.
    DaylightUI:Set("general", "cornerPx", 0)
    stub.RunTimers()
    T.falsy(p.outline.round.TOPLEFT, "follows a new corner rounding")
    T.eq(e.TOPLEFT.__texture, e.LEFT.__texture, "back to the plain line")
    stub.units.target = nil
end)

T.test("nameplates: a soft gleam rides the front of the outline as it draws on, then goes", function()
    login()
    local a = added("nameplate1")
    local gl = a.outline.gleams
    T.truthy(gl and gl.TOP and gl.BOTTOM, "a gleam per edge")
    T.falsy(gl.TOP.blob:IsShown(), "none at rest")
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local d = DaylightUI.Motion.Driver()
    stub.RunOnUpdate(d, 0.15)
    T.truthy(gl.TOP.blob:IsShown() and gl.BOTTOM.blob:IsShown(), "riding the edges mid-sweep")
    T.eq(select(2, gl.TOP.blob:GetPoint(1)), a.outline.pieces.TOP, "on the top edge's front")
    T.eq(select(3, gl.TOP.blob:GetPoint(1)), "RIGHT")
    T.truthy(gl.TOP.blob:GetAlpha() > 0.5, "bright while it travels")
    T.eq(gl.TOP.blob.__blend, "ADD", "light, added")
    for _ = 1, 60 do if d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end end
    T.falsy(gl.TOP.blob:IsShown(), "gone once the outline is whole")
    T.falsy(gl.TOP.tail:IsShown())
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    for _ = 1, 60 do if d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end end
    DaylightUI.DB.General().motion = false
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(gl.TOP.blob:IsShown(), "motion off: no sweep, no gleam")
    stub.units.target = nil
end)

T.test("nameplates: the target can be marked with an outline, a glow or nothing, in a chosen color", function()
    login()
    local p = added("nameplate1")
    stub.units.target = stub.units.nameplate1
    DaylightUI:Set("Nameplates", "targetAccent", false)
    DaylightUI:Set("Nameplates", "targetOutline", { 1, 0.8, 0.25 })
    stub.RunTimers()
    T.near(p.outline.pieces.RIGHT.__vertex[2], 0.8, 1e-6, "a gold outline")
    T.falsy(p.glow:IsShown())
    DaylightUI:Set("Nameplates", "targetStyle", "glow")
    DaylightUI:Set("Nameplates", "targetGlow", { 0.3, 0.6, 1 })
    stub.RunTimers()
    T.falsy(p.outline:IsShown(), "no outline")
    T.truthy(p.glow:IsShown(), "a glow")
    T.near(p.glow.pieces.TOP.__vertex[3], 1, 1e-6, "in blue")
    T.eq(p.glow.pieces.TOP.__texture, stub.nameplates.Plate.GLOW, "a soft glow, not a shadow")
    T.eq(select(2, p.glow.pieces.TOP:GetPoint(1)), p.hp, "spreading out from the bar's edge")
    DaylightUI:Set("Nameplates", "targetStyle", "none")
    stub.RunTimers()
    T.falsy(p.outline:IsShown())
    T.falsy(p.glow:IsShown(), "nothing")
    -- Both follow the angled end: the right side leans with the cut.
    local lean = p.glow.pieces.RIGHT.__vertexOffsets
    T.truthy(lean and lean[2] and lean[2][1] < 0, "the glow's right side leans in at the bottom")
    stub.units.target = nil
end)

T.test("nameplates: threat colors are off until you turn them on", function()
    local NP = login(function() stub.role = "TANK" end)
    T.eq(NP.DEFAULTS.threat, false, "off as shipped")
    DaylightUI:Set("Nameplates", "threat", false)
    stub.RunTimers()
    local p = added("nameplate1")
    stub.inGroup = true
    local normal = fillRed(p)
    stub.units.nameplate1.threatList = { player = { status = 3, scaled = 100, raw = 0, value = 0 } }
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.near(fillRed(p), normal, 1e-6, "no threat color")
    T.isnil(p.threatState)
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: threat colors the bar in a group", function()
    login()
    local p = added("nameplate1")
    stub.inGroup = true
    local real = _G.UnitThreatSituation
    _G.UnitThreatSituation = function() return 3 end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.near(fillRed(p), DaylightUI.Style.Soften(0.92, 0.2, 0.18), 1e-6, "you have it: red")
    stub.role = "TANK"
    stub.FireEvent("PLAYER_ROLES_ASSIGNED")   -- the game says so when a role changes
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    stub.role = nil
    _G.UnitThreatSituation = real
    T.near(fillRed(p), DaylightUI.Style.Soften(0.92, 0.2, 0.18), 1e-6, "a tank holding it: red")
end)

-- Threat on a plate's mob, per the game's two answers (stub threatList).
local function threatOn(unit, status, scaled)
    stub.units[unit].threatList = { player = { status = status, scaled = scaled or 0, raw = 0, value = 0 } }
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", unit)
end

T.test("nameplates: threat for damage and healers: yellow on someone else, orange close to pulling, red once it's on you, never solo", function()
    login(function() stub.role = "DAMAGER" end)
    local p = added("nameplate1")
    local S = DaylightUI.Style
    local normal = fillRed(p)
    stub.inGroup = false
    threatOn("nameplate1", 3, 100)
    T.near(fillRed(p), normal, 1e-6, "solo: every mob you fight is on you, no color")
    stub.inGroup = true
    threatOn("nameplate1", 0, 40)
    T.near(fillRed(p), S.Soften(0.98, 0.84, 0.26), 1e-6, "well below the tank: yellow")
    stub.units.nameplate1.threatList = nil
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.near(fillRed(p), normal, 1e-6, "not on its list: normal")
    threatOn("nameplate1", 0, 85)
    T.near(fillRed(p), S.Soften(1.0, 0.55, 0.12), 1e-6, "most of the way to the pull line: orange")
    threatOn("nameplate1", 1, 95)
    T.near(fillRed(p), S.Soften(1.0, 0.55, 0.12), 1e-6, "above the tank: orange")
    threatOn("nameplate1", 2, 100)
    T.near(fillRed(p), S.Soften(0.92, 0.2, 0.18), 1e-6, "it's on you: red")
    stub.inGroup = false
end)

T.test("nameplates: alone with a pet, threat colors the bar as in a group", function()
    login(function() stub.role = "DAMAGER" end)
    local p = added("nameplate1")
    local S = DaylightUI.Style
    local normal = fillRed(p)
    stub.inGroup = false
    stub.units.pet = { name = "Spot", class = "WARRIOR" }
    threatOn("nameplate1", 0, 40)
    T.near(fillRed(p), S.Soften(0.98, 0.84, 0.26), 1e-6, "the pet holds it: yellow")
    threatOn("nameplate1", 1, 95)
    T.near(fillRed(p), S.Soften(1.0, 0.55, 0.12), 1e-6, "about to take it from the pet: orange")
    threatOn("nameplate1", 2, 100)
    T.near(fillRed(p), S.Soften(0.92, 0.2, 0.18), 1e-6, "it's on you: red")
    -- The pet leaves: back to solo at once, with no threat event to say so.
    stub.units.pet = nil
    stub.FireEvent("UNIT_PET", "player")
    stub.RunTimers()
    T.near(fillRed(p), normal, 1e-6, "no pet: no color")
end)

T.test("nameplates: a tank sees what they hold in red, loose adds in yellow", function()
    login(function() stub.role = "TANK" end)
    local p = added("nameplate1")
    local S = DaylightUI.Style
    stub.inGroup = true
    stub.FireEvent("PLAYER_ROLES_ASSIGNED")
    threatOn("nameplate1", 3, 100)
    T.near(fillRed(p), S.Soften(0.92, 0.2, 0.18), 1e-6, "held: red")
    threatOn("nameplate1", 2, 100)
    T.near(fillRed(p), S.Soften(1.0, 0.55, 0.12), 1e-6, "slipping: orange")
    threatOn("nameplate1", 0, 60)
    T.near(fillRed(p), S.Soften(0.98, 0.84, 0.26), 1e-6, "on someone else: yellow")
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: only the threat state that needs you breathes", function()
    local NP = login(function() stub.role = "DAMAGER" end)
    local p = added("nameplate1")
    local P = NP.Plate
    stub.inGroup = true
    threatOn("nameplate1", 0, 40)
    T.falsy(p.threatLight:IsShown(), "damage, on someone else: calm")
    threatOn("nameplate1", 3, 100)
    T.eq(p.threatPulseTime, P.THREAT_PULSE.aggro, "damage, on you: it breathes")
    threatOn("nameplate1", 0, 85)
    T.eq(p.threatPulseTime, P.THREAT_PULSE.warn, "close to pulling: quicker")
    stub.role = "TANK"
    stub.FireEvent("PLAYER_ROLES_ASSIGNED")
    threatOn("nameplate1", 3, 100)
    T.falsy(p.threatLight:IsShown(), "tank, holding it: calm")
    threatOn("nameplate1", 0, 60)
    T.eq(p.threatPulseTime, P.THREAT_PULSE.aggro, "tank, lost it: it breathes")
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: threat can be a two-color gradient, the Gradients page's pairs", function()
    local NP = login(function() stub.role = "DAMAGER" end)
    local DUI = DaylightUI
    local G = DUI.Gradients
    local p = added("nameplate1")
    stub.inGroup = true
    DUI:Set("Nameplates", "healthColor", "class")
    DUI:Set("Nameplates", "threatFill", "pair")
    DUI:Set("Nameplates", "threatBorder", true)
    stub.RunTimers()
    threatOn("nameplate1", 3, 100)
    local fill = p.health:GetStatusBarTexture()
    local lo, hi = G.Colors("THREAT_ON")
    T.truthy(fill.__gradient, "a gradient, on a bar that's one color otherwise")
    T.near(fill.__gradient[2].r, lo.r, 1e-6, "its dark end")
    T.near(fill.__gradient[3].r, hi.r, 1e-6, "its light end")
    local _, light = G.RGB("THREAT_ON")
    T.eq(p.threatNow, light, "border and glow take the light end")
    threatOn("nameplate1", 0, 40)
    lo = G.Colors("THREAT_LOST")
    T.near(fill.__gradient[2].r, lo.r, 1e-6, "not attacking you: its own pair")
    T.eq(p.threatState, "lost")
    -- A changed pair reaches the plate.
    G.SetPair("THREAT_LOST", { 0, 0, 1 }, { 0, 1, 1 })
    stub.RunTimers()
    T.near(fill.__gradient[2].b, (G.Colors("THREAT_LOST")).b, 1e-6, "your pair")
    T.truthy(fill.__gradient[2].b > fill.__gradient[2].r, "blue now")
    G.ResetAll()
    DUI:Set("Nameplates", "threatFill", "plain")
    DUI:Set("Nameplates", "threatBorder", false)
    DUI:Set("Nameplates", "healthColor", "classGradient")
    stub.RunTimers()
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: on a boss the threat numbers are secret; the plate reads only the plain state", function()
    login(function() stub.role = "DAMAGER" end)
    local p = added("nameplate1")
    stub.inGroup = true
    stub.units.nameplate1.boss = true
    stub.EnterCombat()
    T.truthy(C_Secrets.ShouldUnitThreatValuesBeSecret("player", "nameplate1"), "the game says the numbers are hidden")
    T.falsy(C_Secrets.ShouldUnitThreatStateBeSecret("player", "nameplate1"), "but not your state")
    threatOn("nameplate1", 0, 85)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.near(fillRed(p), DaylightUI.Style.Soften(0.98, 0.84, 0.26), 1e-6, "no plain percent to go on: on someone else")
    threatOn("nameplate1", 2, 100)
    T.near(fillRed(p), DaylightUI.Style.Soften(0.92, 0.2, 0.18), 1e-6, "the state still says it's on you")
    stub.LeaveCombat()
    stub.inGroup = false
end)

T.test("nameplates: the threat % shows your threat by the bar in a group, colored only when the mob needs you", function()
    local NP = login(function() stub.role = "DAMAGER" end)
    T.eq(NP.DEFAULTS.threatPct, false, "off as shipped")
    DaylightUI:Set("Nameplates", "threat", false)       -- its own switch, so no threat colors are needed
    DaylightUI:Set("Nameplates", "threatPct", true)
    stub.RunTimers()
    local p = added("nameplate1")
    local fs, INK = p.threatPct, DaylightUI.Style.INK
    stub.inGroup = false
    threatOn("nameplate1", 3, 100)
    T.falsy(fs:IsShown(), "solo: no number")
    stub.inGroup = true
    threatOn("nameplate1", 0, 40)
    T.truthy(fs:IsShown(), "in a group: shown")
    T.eq(fs:GetText(), "40%")
    T.near(select(1, fs:GetTextColor()), INK.VALUE[1], 1e-6, "on someone else: calm white")
    threatOn("nameplate1", 0, 85)
    T.eq(fs:GetText(), "85%")
    T.near(select(2, fs:GetTextColor()), 0.55, 1e-6, "close to pulling: orange")
    threatOn("nameplate1", 2, 100)
    T.near(select(2, fs:GetTextColor()), 0.2, 1e-6, "on you: red")
    stub.units.nameplate1.threatList = nil
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.falsy(fs:IsShown(), "off its list: gone")
    -- A boss: the number comes secret and is written whole, never compared.
    stub.units.nameplate1.boss = true
    stub.EnterCombat()
    threatOn("nameplate1", 0, 85)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(fs:IsShown(), "a secret number still shows")
    stub.LeaveCombat()
    stub.units.nameplate1.boss = nil
    -- Off again: hidden.
    DaylightUI:Set("Nameplates", "threatPct", false)
    stub.RunTimers()
    T.falsy(fs:IsShown(), "switched off")
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: threat can show on the border or as a glow instead of (or with) the bar", function()
    local NP = login()
    local p = added("nameplate1")
    local S = DaylightUI.Style
    stub.inGroup = true
    local real = _G.UnitThreatSituation
    _G.UnitThreatSituation = function() return 3 end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    -- Default: the bar only, as it always worked.
    T.near(fillRed(p), S.Soften(0.92, 0.2, 0.18), 1e-6, "on the bar by default")
    T.isnil(p.body.borderColor, "not the border")
    T.falsy(p.threatGlow:IsShown(), "no glow")
    DaylightUI:Set("Nameplates", "threatBar", false)
    DaylightUI:Set("Nameplates", "threatBorder", true)
    DaylightUI:Set("Nameplates", "threatGlow", true)
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.near(fillRed(p), S.ReactionColor(2), 1e-6, "the bar off: back to normal")
    T.rgb(p.body.borderColor, { 0.92, 0.2, 0.18 }, "the border, on")
    T.near(p.body.layers.outline.mid.__vertex[1], 0.92, 1e-6, "painted on the outline")
    T.near(p.body.layers.band.mid.__vertex[1], 0.92 * NP.Plate.THREAT_BAND_DIM, 1e-6, "and the band, dimmed")
    T.truthy(p.threatGlow:IsShown(), "and a glow")
    T.near(p.threatGlow.pieces.TOP.__vertex[1], 0.92, 1e-6, "in the threat color")
    -- Threat gone: both let go.
    _G.UnitThreatSituation = function() return nil end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.isnil(p.body.borderColor, "border back to normal")
    T.near(p.body.layers.band.mid.__vertex[1], S.BAND[1], 1e-6, "the band's own color again")
    T.falsy(p.threatGlow:IsShown(), "glow gone")
    _G.UnitThreatSituation = real
end)

T.test("nameplates: threat breathes (its own switch): a light on the fill, faster when it's about to switch", function()
    local NP = login()
    local p = added("nameplate1")
    stub.inGroup = true
    local P = NP.Plate
    local real = _G.UnitThreatSituation
    _G.UnitThreatSituation = function() return 3 end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.truthy(p.threatLight:IsShown(), "on by default: a light over the fill")
    T.truthy(p.threatPulse:IsPlaying(), "breathing")
    T.near(p.threatLight.__vertex[1], 0.92, 1e-6, "in the threat color")
    T.eq(p.threatPulseTime, P.THREAT_PULSE.aggro, "aggro: the slow breath")
    -- About to switch (tank losing it): a faster breath.
    local tank = DaylightUI.Threat.IsTank
    DaylightUI.Threat.IsTank = function() return true end
    _G.UnitThreatSituation = function() return 2 end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.eq(p.threatPulseTime, P.THREAT_PULSE.warn, "warn: quicker")
    T.truthy(P.THREAT_PULSE.warn < P.THREAT_PULSE.aggro)
    DaylightUI.Threat.IsTank = tank
    -- The glow, when on, breathes too.
    DaylightUI:Set("Nameplates", "threatGlow", true)
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.truthy(p.threatGlowPulse:IsPlaying(), "the glow breathes")
    -- Its own switch.
    DaylightUI:Set("Nameplates", "threatPulse", false)
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.falsy(p.threatLight:IsShown(), "off: no light")
    T.falsy(p.threatPulse:IsPlaying(), "and no breath")
    T.falsy(p.threatGlowPulse:IsPlaying(), "the glow holds still")
    T.truthy(p.threatGlow:IsShown(), "but still shows")
    DaylightUI:Set("Nameplates", "threatPulse", true)
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    -- Bar, border and glow all off: no mark, so nothing breathes either.
    DaylightUI:Set("Nameplates", "threatBar", false)
    DaylightUI:Set("Nameplates", "threatGlow", false)
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.falsy(p.threatLight:IsShown(), "no mark on: no light")
    T.falsy(p.threatPulse:IsPlaying(), "no breath")
    DaylightUI:Set("Nameplates", "threatBar", true)
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.truthy(p.threatLight:IsShown(), "the bar back: the light too")
    -- Threat gone: it stops.
    _G.UnitThreatSituation = function() return nil end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.falsy(p.threatLight:IsShown(), "threat gone: no light")
    T.falsy(p.threatPulse:IsPlaying(), "stopped")
    T.falsy(p.threatGlowPulse:IsPlaying())
    _G.UnitThreatSituation = real
    stub.inGroup = false
end)

T.test("nameplates: threat on the border also colors your target's outline round it", function()
    login()
    local p = added("nameplate1")
    stub.inGroup = true
    stub.units.target = stub.units.nameplate1
    DaylightUI:Set("Nameplates", "targetAccent", false)
    DaylightUI:Set("Nameplates", "targetOutline", { 0.3, 0.6, 1 })
    DaylightUI:Set("Nameplates", "threatBorder", true)
    stub.RunTimers()
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(p.outline.pieces.TOP.__vertex[3], 1, 1e-6, "no threat: the outline's own blue")
    local real = _G.UnitThreatSituation
    _G.UnitThreatSituation = function() return 3 end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.near(p.outline.pieces.TOP.__vertex[1], 0.92, 1e-6, "threat: the outline turns the threat color")
    T.near(p.outline.pieces.RIGHT.__vertex[3], 0.18, 1e-6, "every piece of it")
    T.truthy(p.outline:IsShown(), "still marking the target")
    _G.UnitThreatSituation = function() return nil end
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.near(p.outline.pieces.TOP.__vertex[3], 1, 1e-6, "threat gone: blue again")
    _G.UnitThreatSituation = real
    stub.units.target = nil
    stub.inGroup = false
end)

T.test("nameplates: NPC names wear their reaction color; guilds and jobs go under names", function()
    login(function()
        _G.GetGuildInfo = function(u) if u == "nameplate2" then return "Daylight Crew" end end
        stub.units.nameplate3 = { name = "Rand Rhobart", reaction = 5 }
        stub.tooltips = { nameplate3 = { lines = { { leftText = "Rand Rhobart" }, { leftText = "Skinner" }, { leftText = "Level 13" } } },
                          nameplate1 = { lines = { { leftText = "Searing Whelp" }, { leftText = "Level 8 Dragonkin" } } } }
    end)
    local friend = added("nameplate3")
    local r, g, b = DaylightUI.Style.ReactionColor(5)
    local want = DaylightUI.Style.Lighten(r, g, b, stub.nameplates.Plate.NAME_LIGHTEN)
    T.near(friend.name.__textColor[1], want, 1e-6, "a friendly NPC's name is green")
    T.truthy(friend.sub:IsShown())
    T.eq(friend.sub.__text, "Skinner", "its job under its name")
    local mob = added("nameplate1")
    T.falsy(mob.sub:IsShown(), "a level line isn't a job")
    local player = added("nameplate2")
    T.eq(player.sub.__text, "<Daylight Crew>", "a player's guild")
    T.near(player.sub.__textColor[1], DaylightUI.Style.ClassColor("MAGE"), 1e-6, "in their class color")
    -- Both are friendly: their own switches (the enemy ones leave them be).
    DaylightUI:Set("Nameplates", "guild", false)
    DaylightUI:Set("Nameplates", "role", false)
    stub.RunTimers()
    T.truthy(player.sub:IsShown(), "the enemy switch leaves friends be")
    DaylightUI:Set("Nameplates", "friendly.guild", false)
    DaylightUI:Set("Nameplates", "friendly.role", false)
    stub.RunTimers()
    T.falsy(player.sub:IsShown()); T.falsy(friend.sub:IsShown(), "both can be turned off")
    stub.tooltips = nil
    _G.GetGuildInfo = nil
end)

T.test("nameplates: a quest target gets the gold mark until it's done", function()
    login(function()
        stub.tooltips = { nameplate1 = { lines = {
            { type = 17, leftText = "Wolves at the Door" },
            { type = 8, leftText = "Wolf Pelt: 3/8" },
        } } }
    end)
    local p = added("nameplate1")
    T.truthy(p.quest:IsShown())
    local point, rel, relPoint = p.quest:GetPoint(1)
    T.eq(point, "RIGHT"); T.eq(rel, p.hp); T.eq(relPoint, "LEFT", "just left of the bar")
    T.eq(select(2, p.marker:GetPoint(1)), p.questCount, "the raid marker beyond it and its count")
    stub.tooltips.nameplate1.lines[2].leftText = "Wolf Pelt: 8/8"
    stub.FireEvent("QUEST_LOG_UPDATE")
    T.truthy(p.quest:IsShown(), "quest-log events are gathered for a moment")
    stub.RunTimers()
    T.falsy(p.quest:IsShown())
    T.falsy(p.questCount:IsShown())
    stub.tooltips = nil
end)

-- In a group the game puts each member's name over their objectives. This
-- client's players have last names: the line can carry the whole name while
-- UnitName gives only the first.
T.test("nameplates: in a party your own objectives still mark the mob, a friend's don't", function()
    for _, mine in ipairs({ "Tester", "Tester Daylight", "|cffffd200Tester Daylight|r", " Tester " }) do
        login(function()
            stub.units.player = { name = "Tester", lastName = "Daylight", isPlayer = true }
            stub.tooltips = { nameplate1 = { lines = {
                { type = 17, leftText = "Wolves at the Door" },
                { type = 18, leftText = "Bone Money" },
                { type = 8, leftText = "Wolf Pelt: 8/8" },
                { type = 18, leftText = mine },
                { type = 8, leftText = "Wolf Pelt: 2/3" },
            } } }
        end)
        local p = added("nameplate1")
        T.truthy(p.quest:IsShown(), "marked: " .. mine)
        T.eq(p.questCount:GetText(), "2/3", "your own count: " .. mine)
    end
    login(function()
        stub.units.player = { name = "Tester", lastName = "Daylight", isPlayer = true }
        stub.tooltips = { nameplate1 = { lines = {
            { type = 17, leftText = "Wolves at the Door" },
            { type = 18, leftText = "Tester Daylight" },
            { type = 8, leftText = "Wolf Pelt: 3/3" },
            { type = 18, leftText = "Testerson Money" },
            { type = 8, leftText = "Wolf Pelt: 1/3" },
        } } }
    end)
    T.falsy(added("nameplate1").quest:IsShown(), "only the friend still needs it")
    stub.tooltips = nil
end)

T.test("nameplates: the quest count sits beside the mark and follows its switch", function()
    login(function()
        stub.tooltips = { nameplate1 = { lines = {
            { type = 17, leftText = "Wolves at the Door" },
            { type = 8, leftText = "Wolf Pelt: 8/8" },
            { type = 8, leftText = "Gray Wolf slain: 4/10" },
        } } }
    end)
    local p = added("nameplate1")
    T.truthy(p.questCount:IsShown())
    T.eq(p.questCount:GetText(), "4/10", "the first objective still to do")
    local point, rel, relPoint = p.questCount:GetPoint(1)
    T.eq(point, "RIGHT"); T.eq(rel, p.quest); T.eq(relPoint, "LEFT", "just left of the !")
    stub.tooltips.nameplate1.lines[3].leftText = "Explore the den: 45%"
    stub.FireEvent("QUEST_LOG_UPDATE")
    stub.RunTimers()
    T.eq(p.questCount:GetText(), "45%")
    DaylightUI:Set("Nameplates", "questCount", false)
    stub.RunTimers()
    T.truthy(p.quest:IsShown()); T.falsy(p.questCount:IsShown(), "switched off: the ! alone")
    T.eq(select(2, p.marker:GetPoint(1)), p.quest)
    stub.tooltips = nil
end)

-- A region's first anchor as one line: "POINT rel RELPOINT x y".
local function pointOf(r, names)
    local point, rel, relPoint, x, y = r:GetPoint(1)
    return string.format("%s %s %s %g %g", tostring(point), names[rel] or tostring(rel), tostring(relPoint), x or 0, y or 0)
end

T.test("nameplates: every piece's default spot is where it always was", function()
    local ns = login(function()
        stub.tooltips = { nameplate1 = { lines = {
            { type = 17, leftText = "Wolves at the Door" },
            { type = 8, leftText = "Gray Wolf slain: 4/10" },
        } } }
    end)
    DaylightUI:Set("Nameplates", "role", false)    -- the tooltip's lines would read as a job
    stub.units.nameplate1.raidTarget = 8
    local p = added("nameplate1")
    stub.tooltips = nil
    local names = { [p.hp] = "hp", [p.quest] = "quest", [p.questCount] = "count", [p.sub] = "sub", [p.name] = "name" }
    -- Counted by hand from before the pieces moved (Plate.PlaceNames,
    -- Auras.Anchor, Plate.PlaceMarker): the name 2 over the bar, the rows over
    -- a 1 px line at the name's top (2 + 13 + 1), the buffs past the debuffs'
    -- icons and times (2 + 21 + 2 + 6).
    T.eq(pointOf(p.name, names), "BOTTOM hp TOP 0 2", "the name just over the bar")
    T.eq(pointOf(p.auras.debuffs, names), "BOTTOM hp TOP 0 18", "your debuffs over the name")
    T.eq(pointOf(p.auras.buffs, names), "BOTTOMRIGHT hp TOPRIGHT 0 47", "the purgeable buffs over them, from the right")
    T.eq(pointOf(p.auras.cc, names), "LEFT hp RIGHT 4 0", "crowd control beside the bar's end")
    T.eq(pointOf(p.quest, names), "RIGHT hp LEFT -3 0", "the quest mark left of the bar")
    T.eq(pointOf(p.questCount, names), "RIGHT quest LEFT -1 0", "its count left of the !")
    T.truthy(p.marker:IsShown())
    T.eq(pointOf(p.marker, names), "RIGHT count LEFT -2 0", "the raid marker past both")
    T.eq(p.auras.buffs:GetWidth(), p.hp:GetWidth(), "the buffs' row as wide as the bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: friendly guild and job lines take their own color and size", function()
    login(function()
        _G.GetGuildInfo = function(u) if u == "nameplate2" then return "Daylight Crew" end end
        stub.units.nameplate3 = { name = "Rand Rhobart", reaction = 5 }
        stub.tooltips = { nameplate3 = { lines = { { leftText = "Rand Rhobart" }, { leftText = "Skinner" } } } }
    end)
    local DUI, Style = DaylightUI, DaylightUI.Style
    local job, guild = added("nameplate3"), added("nameplate2")
    T.eq(job.sub.__font[2], 9, "by default a share of the name")
    T.eq(guild.sub.__font[2], 9)
    T.rgb(job.sub.__textColor, { Style.INK.LABEL[1], Style.INK.LABEL[2], Style.INK.LABEL[3] }, "a job stays tan")

    DUI:Set("Nameplates", "friendly.guildColor", "white")
    DUI:Set("Nameplates", "friendly.guildSize", 14)
    DUI:Set("Nameplates", "friendly.roleColor", "custom")
    DUI:Set("Nameplates", "friendly.roleCustom", { 0.1, 0.2, 0.3 })
    DUI:Set("Nameplates", "friendly.roleSize", 11)
    stub.RunTimers()
    T.rgb(guild.sub.__textColor, { Style.INK.VALUE[1], Style.INK.VALUE[2], Style.INK.VALUE[3] }, "a white guild")
    T.eq(guild.sub.__font[2], 14, "the guild's own size")
    T.rgb(job.sub.__textColor, { 0.1, 0.2, 0.3 }, "the job's own color")
    T.eq(job.sub.__font[2], 11, "the job's own size")
    T.eq(stub.nameplates.Plate.SubSize(stub.nameplates.cfg), 9, "enemy plates have their own")
    DUI:Set("Nameplates", "guildSize", 12)
    DUI:Set("Nameplates", "roleSize", 10)
    T.eq(stub.nameplates.Plate.SubSize(stub.nameplates.cfg), 12, "an enemy guild's size")
    T.eq(stub.nameplates.Plate.SubSize(stub.nameplates.cfg, true), 10, "an enemy job's size")
    T.eq(guild.sub.__font[2], 14, "friends keep theirs")

    stub.tooltips = nil
    _G.GetGuildInfo = nil
end)

T.test("nameplates: a guild or job line goes between the name and the bar, the rows over both", function()
    local ns = login()
    local p = added("nameplate1")
    p.sub:Show()
    ns.Plate.PlaceSpots(p)    -- the line showing is enough to place again
    local names = { [p.hp] = "hp", [p.sub] = "sub" }
    T.eq(pointOf(p.sub, names), "BOTTOM hp TOP 0 2")
    T.eq(pointOf(p.name, names), "BOTTOM sub TOP 0 1")
    T.eq(pointOf(p.auras.debuffs, names), "BOTTOM hp TOP 0 28", "over the name and its line (2 + 13 + 1 + 9 + 1, + 2)")
end)

T.test("nameplates: pieces follow their spot settings", function()
    local ns = login()
    local p = added("nameplate1")
    local names = { [p.hp] = "hp", [p.quest] = "quest", [p.questCount] = "count", [p.marker] = "marker" }
    DaylightUI:Set("Nameplates", "namePos", "below")
    DaylightUI:Set("Nameplates", "nameX", 5)
    stub.RunTimers()
    local c = ns.cfg
    local below = ns.Cast.GAP + c.castHeight + ns.Plate.NAME_GAP
    T.eq(pointOf(p.name, names), "TOP hp BOTTOM 5 " .. -below, "under the cast bar's room, nudged")
    T.eq(pointOf(p.auras.debuffs, names), "BOTTOM hp TOP 0 2", "the debuffs close down onto the bar")
    DaylightUI:Set("Nameplates", "namePos", "left")
    stub.RunTimers()
    local point, _, relPoint = p.name:GetPoint(1)
    T.eq(point, "LEFT"); T.eq(relPoint, "LEFT", "on the bar, at its left end")
    T.eq(p.name:GetJustifyH(), "LEFT", "justified to its side")
    T.truthy(p.name:GetWidth() < p.hp:GetWidth(), "no wider than the room on the bar")
    DaylightUI:Set("Nameplates", "debuffSpot", "below")
    DaylightUI:Set("Nameplates", "debuffGrow", "right")
    stub.RunTimers()
    T.eq(pointOf(p.auras.debuffs, names), "TOPLEFT hp BOTTOMLEFT 0 " .. -(ns.Cast.GAP + c.castHeight + 2),
        "under the cast bar's room, from the left")
    T.eq(p.auras.debuffs.__anchorPoint, "TOPLEFT", "its flow from the left, downward")
    DaylightUI:Set("Nameplates", "ccSpot", "outleft")
    DaylightUI:Set("Nameplates", "markerPos", "outright")
    stub.RunTimers()
    T.eq(pointOf(p.auras.cc, names), "RIGHT hp LEFT -4 0", "crowd control by the bar's left end")
    DaylightUI:Set("Nameplates", "debuffSpot", "center")
    stub.RunTimers()
    T.eq(pointOf(p.auras.debuffs, names), "BOTTOMLEFT hp TOPLEFT 0 2", "a row never goes on the bar: its default spot, still from the left")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a mark showing or hiding moves only what lines up with it, once", function()
    local ns = login()
    local p = added("nameplate1")
    local placed = 0
    local P = ns.Plate
    local place = P.PlaceSpots
    local names = { [p.hp] = "hp" }
    T.falsy(p.marker:IsShown())
    T.eq(pointOf(p.marker, names), "RIGHT hp LEFT -4 0", "alone beside the bar")
    -- Counted through the anchors the placement sets on the name.
    local setPoint = p.name.SetPoint
    p.name.SetPoint = function(...) placed = placed + 1; return setPoint(...) end
    stub.units.nameplate1.raidTarget = 8
    stub.FireEvent("RAID_TARGET_UPDATE")
    stub.RunTimers()
    T.truthy(p.marker:IsShown())
    T.eq(placed, 1, "placed again once")
    placed = 0
    stub.FireEvent("RAID_TARGET_UPDATE")
    stub.RunTimers()
    T.eq(placed, 0, "nothing changed: nothing placed")
    p.name.SetPoint = setPoint
end)

T.test("nameplates: your debuffs, crowd control and purgeable buffs have their containers", function()
    login()
    local p = added("nameplate1")
    T.eq(p.auras.debuffs.__groups.mine.filter, "HARMFUL|PLAYER|!CROWD_CONTROL")
    T.eq(p.auras.debuffs.__groups.mine.max, DaylightUI:Get("Nameplates", "maxDebuffs"))
    T.eq(p.auras.cc.__groups.cc.filter, "HARMFUL|CROWD_CONTROL")
    T.eq(p.auras.cc.__groups.cc.max, 1, "one round icon")
    T.eq(p.auras.buffs.__groups.steal.filter, "HELPFUL|RAID_PLAYER_DISPELLABLE", "the client picks them, so it works when enemy auras are secret")
    T.eq(p.auras.buffs.__groups.steal.opts.candidateFilters, nil, "a candidate filter reads aura data, secret in PvP: it would show nothing")
    T.eq(p.auras.debuffs.__unit, "nameplate1")
    local point, rel, relPoint = p.auras.debuffs:GetPoint(1)
    T.eq(point, "BOTTOM"); T.eq(rel, p.hp); T.eq(relPoint, "TOP", "centered above the name, growing both ways")
    local btn = p.auras.debuffs.__groups.mine.button
    local s = DaylightUI:Get("Nameplates", "debuffSize")
    T.eq(btn:GetWidth(), s)
    T.eq(btn:GetHeight(), math.floor(s * 0.88 + 0.5), "a little wider than tall, like the target's")
    T.truthy(btn.__dispel, "edged by dispel type")
    T.eq(btn.__dispel.opts.style, Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset)
    T.truthy(btn.__cooldown, "the client's time runs through our quiet cooldown")
    local steal = p.auras.buffs.__groups.steal.button
    local halo = steal and steal.__dispels and steal.__dispels[2]
    T.truthy(halo, "a purgeable buff gets a halo")
    T.eq(halo.opts.stealableFilter, nil, "every buff in this row can be removed: each gets the halo")
    T.falsy(btn.__dispels[2], "your debuffs: no halo")
    for _, m in ipairs(stub.chat) do T.falsy(string.find(m, "Options (", 1, true), m) end
end)

T.test("nameplates: aura edges use the dispel colors picked on the unit frames' Colors page", function()
    stub.Load({ nameplates = true, module = true, before = world })
    stub.RunTimers()
    local A = stub.nameplates.Auras
    T.deq(A.DispelColor("Magic"), A.DISPEL_COLORS.Magic, "the default matches")
    DaylightUI:Set("UnitFrames", "colors.dispelMagic", { 1, 0, 0 })
    T.deq(A.DispelColor("Magic"), { 1, 0, 0 }, "a picked color carries over")
    T.deq(A.DispelColor("Bleed"), A.DISPEL_COLORS.Bleed, "no picker: ours")
    T.deq(A.DispelColor("None"), A.NO_DISPEL, "no type: the wine")
    DaylightUI:Set("UnitFrames", "colors.dispelMagic", nil)
end)

T.test("nameplates: a plate that goes away stops listening", function()
    local NP = login()
    local p = added("nameplate1")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.falsy(p:IsShown())
    T.falsy(p:IsEventRegistered("UNIT_HEALTH"))
    T.isnil(NP.Manager.byUnit.nameplate1)
end)

T.test("nameplates: the target colors are color-wheel settings: pick, cancel, reset", function()
    login()
    local picked = { 0.2, 0.9, 0.4 }
    local info
    _G.ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame", UIParent)
    function ColorPickerFrame:SetupColorPickerAndShow(i) info = i end
    function ColorPickerFrame:GetColorRGB() return picked[1], picked[2], picked[3] end
    DaylightUI:Set("Nameplates", "targetAccent", false)   -- its own color, so the swatch is live
    stub.RunTimers()
    DaylightUI.OptionsPanel.Show("Nameplates.target")
    local pf = DaylightUI.OptionsPanel.PageFrame()
    local row
    for _, card in ipairs(pf.cards) do
        for _, r in ipairs(card.rows) do if r.item.key == "targetOutline" then row = r end end
    end
    T.truthy(row, "an Outline color row")
    local d = DaylightUI:Get("Nameplates", "targetOutline")
    T.near(row.control.fill.__vertex[1], d[1], 1e-6, "its swatch shows the color")
    row.control:GetScript("OnClick")(row.control)
    T.near(info.r, d[1], 1e-6, "the picker opens on it")
    info.swatchFunc()
    stub.RunTimers()
    T.near(DaylightUI:Get("Nameplates", "targetOutline")[2], 0.9, 1e-6, "a pick is kept")
    info.cancelFunc()
    stub.RunTimers()
    T.near(DaylightUI:Get("Nameplates", "targetOutline")[2], d[2], 1e-6, "a cancel puts it back")
    DaylightUI:Set("Nameplates", "targetOutline", { 1, 1, 1 })
    DaylightUI.Options.ResetItem(row.page, row.item)
    local now = DaylightUI:Get("Nameplates", "targetOutline")
    T.near(now[1], d[1], 1e-6, "reset to the default")
    now[1] = 0
    T.near(stub.nameplates.DEFAULTS.targetOutline[1], d[1], 1e-6, "the default itself untouched")
end)

T.test("nameplates: an aura icon the game has closed off is skipped on relayout, not an error", function()
    login()
    local p = added("nameplate1")
    local btn = p.auras.debuffs.__groups.mine.button
    local function refuse() error("Attempt to access forbidden object from code tainted by an AddOn") end
    btn.GetEffectiveScale, btn.SetSize = refuse, refuse
    DaylightUI:Set("Nameplates", "debuffSize", 30)
    stub.RunTimers()
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    added("nameplate1")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    -- A font change doesn't reach into it either.
    DaylightUI:Set("general", "font", "lato")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the range setting sets the game's plate distance, after combat if need be", function()
    local cvars = {}
    login(function() _G.SetCVar = function(k, v) cvars[k] = v end end)
    T.eq(cvars.nameplateMaxDistance, "60", "the most, at login")
    stub.combat = true
    DaylightUI:Set("Nameplates", "range", 40)
    T.eq(cvars.nameplateMaxDistance, "60", "not in combat")
    stub.LeaveCombat()
    T.eq(cvars.nameplateMaxDistance, "40", "once it's over")
end)

T.test("nameplates: name-only friendly plates ask the game for its light name-only plate", function()
    local cvars = {}
    login(function() _G.SetCVar = function(k, v) cvars[k] = v end end)
    local K = "nameplateShowOnlyNameForFriendlyPlayerUnits"
    T.eq(cvars[K], "1", "name only by default")
    stub.combat = true
    DaylightUI:Set("Nameplates", "friendly.enabled", true)
    T.eq(cvars[K], "1", "not in combat")
    stub.LeaveCombat()
    T.eq(cvars[K], "0", "health bar on: the game's full plate again")
end)

T.test("nameplates: the cast bar wears a slim plain border", function()
    login()
    local p = added("nameplate1")
    T.near(p.cast.body.T, DaylightUI.Pixel.Px(p.cast, 2), 1e-6, "2 px")
    T.falsy(p.cast.body.heavy, "no warm band")
    T.falsy(p.cast.body.layers.band.mid:IsShown())
end)

T.test("nameplates: the target's mark follows the accent color by default", function()
    login()
    local p = added("nameplate1")
    stub.units.target = stub.units.nameplate1
    DaylightUI:Set("general", "accent", "custom")
    DaylightUI:Set("general", "accentColor", { 0.2, 0.7, 0.4 })
    stub.RunTimers()
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(p.outline.pieces.TOP.__vertex[2], 0.7, 1e-6, "in the accent")
    DaylightUI:Set("Nameplates", "targetOutline", { 1, 0.8, 0.25 })
    stub.RunTimers()
    T.near(p.outline.pieces.TOP.__vertex[2], 0.7, 1e-6, "its own color only when asked")
end)

T.test("nameplates: a rogue's combo points under the target's plate; its cast bar drops below them", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    local p = added("nameplate1")
    local other = added("nameplate2")
    local row = ns.Combo.row
    T.truthy(row, "a row for a rogue")
    T.falsy(row:IsShown(), "no target: hidden")
    local _, _, _, _, castY = p.cast:GetPoint(1)
    stub.comboPoints = 3
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(row:IsShown(), "on the target's plate")
    T.eq(row:GetParent(), p)
    local _, rel, rp = row:GetPoint(1)
    T.eq(rel, p.hp); T.eq(rp, "BOTTOMLEFT", "under its health bar")
    T.eq(row.pips[3].bar:GetValue(), 3, "three points")
    -- A hidden cast bar moves when it next shows, so there's no layout per target switch.
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.truthy(p.cast:IsShown())
    local _, _, _, _, dropped = p.cast:GetPoint(1)
    T.eq(dropped, castY - ns.Combo.HEIGHT - ns.Combo.GAP, "the cast bar below the pips")
    stub.units.nameplate1.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    stub.comboPoints = 5
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    T.eq(row.pips[5].bar:GetValue(), 5, "follows the count")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(row:IsShown(), "no target: gone")
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    local _, _, _, _, back = p.cast:GetPoint(1)
    T.eq(back, castY, "and the cast bar back up")
    -- A cast showing while the row comes moves at once.
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local _, _, _, _, now = p.cast:GetPoint(1)
    T.eq(now, castY - ns.Combo.HEIGHT - ns.Combo.GAP, "a showing cast bar drops at once")
    stub.units.target, stub.units.nameplate1.cast = nil, nil
    T.truthy(other)
end)

-- Runs the motion kit's tweens to their end (a fade out hides at its end).
local function settle()
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then return end
        stub.RunOnUpdate(d, 1 / 60)
    end
end

T.test("nameplates: the power bar: off as shipped; on, under a caster's health bar, the cast bar below it, secret power drawn whole", function()
    local ns = login()
    DaylightUI:Set("general", "smoothBars", false)
    local mob = stub.units.nameplate1
    mob.power, mob.maxPower = 40, 100     -- a mana user (the fake game's default power type)
    local p = added("nameplate1")
    T.falsy(p.power:IsShown(), "off by default")
    T.falsy(p:IsEventRegistered("UNIT_POWER_UPDATE"), "and nothing listened to")
    local _, _, _, _, castY = p.cast:GetPoint(1)
    DaylightUI:Set("Nameplates", "power", true)
    stub.RunTimers()
    T.truthy(p.power:IsShown(), "on: a caster gets one")
    T.eq(p.power:GetAlpha(), 1)
    local _, rel, rp, _, y = p.power:GetPoint(1)
    T.eq(rel, p.hp); T.eq(rp, "TOPLEFT")
    T.eq(y, -(p.hp:GetHeight() + ns.Power.GAP), "just under the health bar")
    T.eq(stub.Plain(p.power.bar:GetValue()), 40)
    T.truthy(p:IsEventRegistered("UNIT_POWER_UPDATE"), "its events while it shows")
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    local _, _, _, _, dropped = p.cast:GetPoint(1)
    T.eq(dropped, castY - ns.Power.HEIGHT - ns.Power.GAP, "the cast bar below it")
    -- In a fight the amounts are secret, so they go straight into the bar, never read.
    mob.power, mob.maxPower = stub.Secret(25), stub.Secret(100)
    stub.FireEvent("UNIT_MAXPOWER", "nameplate1", "MANA")
    stub.FireEvent("UNIT_POWER_UPDATE", "nameplate1", "MANA")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(stub.Plain(p.power.bar:GetValue()), 25, "a secret amount drawn")
    -- A warrior mob uses rage, so it isn't under "players and mana users".
    mob.power, mob.maxPower = 10, 100
    mob.powerType, mob.powerToken = 1, "RAGE"
    stub.FireEvent("UNIT_DISPLAYPOWER", "nameplate1")
    settle()
    T.falsy(p.power:IsShown(), "rage: gone")
    T.falsy(p:IsEventRegistered("UNIT_POWER_UPDATE"), "and its events with it")
    local _, _, _, _, back = p.cast:GetPoint(1)
    T.eq(back, castY, "the cast bar back up")
    DaylightUI:Set("Nameplates", "powerShow", "all")
    stub.RunTimers()
    T.truthy(p.power:IsShown(), "everyone with power: rage too")
    local player = added("nameplate2")
    T.falsy(player.power:IsShown(), "a friendly plate: its own switch, off")
    DaylightUI:Set("Nameplates", "powerShow", "target")
    stub.RunTimers()
    settle()
    T.falsy(p.power:IsShown(), "your target only: not targeted")
    stub.units.target = mob
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.truthy(p.power:IsShown(), "targeted: it comes")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    settle()
    T.falsy(p.power:IsShown(), "and goes with the target")
    -- The plate reused for another unit starts with none.
    DaylightUI:Set("Nameplates", "powerShow", "all")
    stub.RunTimers()
    T.truthy(p.power:IsShown())
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.falsy(p.power:IsShown(), "gone with its unit")
    T.falsy(p:IsEventRegistered("UNIT_POWER_UPDATE"))
    stub.units.nameplate1.cast = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the power bar's color: the power type's pair, or one color", function()
    login()
    DaylightUI:Set("general", "smoothBars", false)
    DaylightUI:Set("Nameplates", "power", true)
    stub.RunTimers()
    stub.units.nameplate1.power, stub.units.nameplate1.maxPower = 50, 100
    local p = added("nameplate1")
    T.truthy(p.power:IsShown())
    local lo, hi = DaylightUI.Gradients.Colors("MANA")
    local fill = p.power.bar:GetStatusBarTexture()
    T.truthy(fill.__gradient, "a gradient")
    T.near(fill.__gradient[2].r, lo.r, 1e-6, "mana's pair: its dark end")
    T.near(fill.__gradient[3].r, hi.r, 1e-6, "its light end")
    DaylightUI:Set("Nameplates", "powerColor", "custom")
    DaylightUI:Set("Nameplates", "powerCustom", { 1, 0, 0 })
    stub.RunTimers()
    fill = p.power.bar:GetStatusBarTexture()
    T.truthy(fill.__gradient, "one color, made a gradient")
    T.truthy(fill.__gradient[3].r > 0.5 and fill.__gradient[3].b < 0.5, "a red one")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a reused plate starts clean: no old outline fading, its cast bar not dropped for old combo points", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    DaylightUI:Set("Nameplates", "targetScale", false)   -- the target at the same size keeps the plate's layout
    stub.RunTimers()
    local p = added("nameplate1")
    local _, _, _, _, castY = p.cast:GetPoint(1)
    stub.comboPoints = 3
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.truthy(p.outline:IsShown())
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    -- The target's plate goes away (out of range), then your target is gone.
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.falsy(p.outline:IsShown(), "the outline gone with its unit")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    -- The plate comes back for another mob, casting.
    stub.units.nameplate1 = { name = "Another", hostile = true, reaction = 2, health = 5, maxHealth = 5,
        cast = { name = "Frostbolt", texture = 1, notInterruptible = false, duration = stub.Duration(2) } }
    local again = added("nameplate1")
    T.eq(again, p, "the same plate, reused")
    T.falsy(p.outline:IsShown(), "no old target's outline fading away")
    T.truthy(p.cast:IsShown())
    local _, _, _, _, y = p.cast:GetPoint(1)
    T.eq(y, castY, "the cast bar right under the bar")
    stub.units.nameplate1.cast = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: combo pop: a point gained flashes its pip, five sweeps the row, a new target only seeds", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    stub.units.nameplate3 = { name = "Whelp", hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 }
    added("nameplate1"); added("nameplate3")
    local row = ns.Combo.row
    local function settle() local d = DaylightUI.Motion.Driver(); if d then stub.RunOnUpdate(d, 1) end end
    local function lit(pip)
        local c, p = pip.bar.__barColor, pip.color
        return (c[1] + c[2] + c[3]) - (p[1] + p[2] + p[3])
    end
    stub.comboPoints = 3
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    settle()
    T.near(lit(row.pips[3]), 0, 1e-6, "onto a target: seeded, no flash")
    stub.comboPoints = 4
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    T.truthy(lit(row.pips[4]) > 0.1, "pip 4 flashes")
    T.near(lit(row.pips[3]), 0, 1e-6, "pip 3 doesn't")
    settle()
    stub.comboPoints = 5
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    T.truthy(row.sweep:IsShown(), "five: the light runs")
    T.eq(#(row.sweep.__masks or {}), 0, "no mask: it fades at its ends")
    T.truthy(row.glow:IsShown(), "and the row glows once")
    T.eq(#(row.glow.__masks or {}) + #(row.pips[5].burst.__masks or {}), 0, "the glows: no masks")
    settle()
    T.falsy(row.sweep:IsShown())
    stub.comboPoints = 0
    -- A finisher's spend comes with its energy, no COMBO_POINTS event (seen in game).
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY")
    T.eq(row.pips[5].bar:GetValue(), 0, "spent: the pips empty")
    stub.comboPoints = 0
    stub.units.target = stub.units.nameplate3
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.comboPoints = 5
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(row.sweep:IsShown(), "a swap to a target at five: no sweep")
    T.near(lit(row.pips[5]), 0, 1e-6, "nor a flash")
    stub.comboPoints = stub.Secret(5)
    T.noerror(function() stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS") end)
    stub.comboPoints, stub.units.target = nil, nil
end)

T.test("nameplates: no combo row for other classes; none on a friendly target", function()
    local ns = login()
    T.falsy(ns.Combo.row, "a priest has none")
    ns = login(function() stub.units.player.class = "ROGUE" end)
    added("nameplate2")
    stub.units.target = stub.units.nameplate2
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.falsy(ns.Combo.row:IsShown(), "a friend: no combo points on it")
end)

T.test("nameplates: combo points above the bar lift the name, leave the cast bar; size settings apply", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    local DUI = DaylightUI
    local p = added("nameplate1")
    local _, _, _, _, castY = p.cast:GetPoint(1)
    local _, _, _, _, nameY = p.name:GetPoint(1)
    DUI:Set("Nameplates", "comboPosition", "above")
    DUI:Set("Nameplates", "comboHeight", 10)
    DUI:Set("Nameplates", "comboWidth", 0.5)
    DUI:Set("Nameplates", "comboBorder", 1)
    DUI:Set("Nameplates", "comboSlant", true)
    stub.RunTimers()
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local row = ns.Combo.row
    T.truthy(row:IsShown())
    local pt, rel, rp, x, y = row:GetPoint(1)
    T.eq(pt, "BOTTOMLEFT"); T.eq(rel, p.hp); T.eq(rp, "TOPLEFT", "over the bar")
    T.eq(y, ns.Combo.GAP)
    T.eq(row:GetHeight(), 10, "taller pips")
    T.near(row:GetWidth(), p.hp:GetWidth() * 0.5, 1e-6, "half the bar")
    T.near(x, p.hp:GetWidth() * 0.25, 1e-6, "centred")
    local _, _, _, _, castNow = p.cast:GetPoint(1)
    T.eq(castNow, castY, "the cast bar stays up")
    local _, _, _, _, nameNow = p.name:GetPoint(1)
    T.eq(nameNow, nameY + 10 + ns.Combo.GAP, "the name rises over the pips")
    stub.comboPoints = 2
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    T.eq(row.pips[2].bar:GetValue(), 2, "the count still follows")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local _, _, _, _, nameBack = p.name:GetPoint(1)
    T.eq(nameBack, nameY, "no target: the name back down")
end)

T.test("nameplates: combo pips follow the unit frames' combo color", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    local S = DaylightUI.Style
    local row = ns.Combo.row
    local real = DaylightUI.Get
    DaylightUI.Get = function(self, scope, key)
        if scope == "UnitFrames" and key == "combo" then
            return { color = { 0.2, 0.6, 0.9 }, fullRed = false, colorMode = "color" }
        end
        return real(self, scope, key)
    end
    ns.Combo.Paint(row)
    T.rgb(row.pips[1].bar.__barColor, { S.Soften(0.2, 0.6, 0.9) }, "pip 1")
    T.rgb(row.pips[5].bar.__barColor, { S.Soften(0.2, 0.6, 0.9) }, "no red")
    DaylightUI.Get = function(self, scope, key)
        if scope == "UnitFrames" and key == "combo" then return { fullAll = true, colorMode = "class" } end
        return real(self, scope, key)
    end
    ns.Combo.Paint(row)
    DaylightUI.Get = real
    T.rgb(row.pips[2].bar.__barColor, { S.ClassColor("ROGUE") }, "class color")
    T.truthy(row.pips[1].full:IsShown(), "the whole row at full points")
end)

T.test("nameplates: health text formats, size, one-color bars, white names and cast colors", function()
    local NP = login()
    local DUI = DaylightUI
    local S = DUI.Style
    local p = added("nameplate1")
    DUI:Set("Nameplates", "healthFormat", "value")
    DUI:Set("Nameplates", "healthSize", 15)
    stub.RunTimers()
    NP.Plate.UpdateHealth(p, true)
    T.eq(stub.Text(p.percent), "60", "the value")
    T.eq(p.percent.__font[2], 15, "its own size")
    DUI:Set("Nameplates", "healthColor", "custom")
    DUI:Set("Nameplates", "healthCustom", { 0, 0, 1 })
    DUI:Set("Nameplates", "nameColor", "white")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.rgb(p.health.__barColor, { S.Soften(0, 0, 1) }, "one color")
    T.eq(p.name.__textColor[1], DUI.Style.INK.VALUE[1], "white name: warm white")
    DUI:Set("Nameplates", "castColor", { 0, 1, 0 })
    stub.units.nameplate1.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.eq(p.cast.bar.__barColor[2], 1, "the cast color")
end)

T.test("nameplates: cast fill choices, one look for every cast", function()
    local NP = login()
    local DUI = DaylightUI
    local p = added("nameplate1")
    local u = stub.units.nameplate1
    DUI:Set("Nameplates", "castFill", "pair")
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    local lo, hi = DUI.Gradients.Colors("CAST")
    local grad = p.cast.bar:GetStatusBarTexture().__gradient
    T.truthy(grad, "cast gradient set")
    T.eq(grad[2], lo); T.eq(grad[3], hi)
    -- a channel takes the Channel pair
    u.cast = nil
    u.channel = { name = "Drain", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "nameplate1")
    lo, hi = DUI.Gradients.Colors("CHANNEL")
    grad = p.cast.bar:GetStatusBarTexture().__gradient
    T.eq(grad[2], lo, "channel pair"); T.eq(grad[3], hi)
    u.channel = nil
    -- can't be interrupted: the same color
    DUI:Set("Nameplates", "castFill", "plain")
    DUI:Set("Nameplates", "castColor", { 0, 1, 0 })
    u.cast = { name = "Fireball", notInterruptible = true, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.rgb(p.cast.bar.__barColor, { 0, 1, 0 }, "no gray for uninterruptible")
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    -- interrupted: red, even over a gradient
    DUI:Set("Nameplates", "castFill", "pair")
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1")
    T.rgb(p.cast.bar:GetStatusBarTexture().__vertex, NP.Cast.INTERRUPTED, "red")
end)

-- The interrupt's white flash lies over the fill in ADD blend. It must be
-- cleared on every cast, or the whole bar reads white (seen in game).
T.test("nameplates: the interrupt flash is off while a cast runs", function()
    stub.AlphaRule = true    -- a texture's one alpha, as in game
    local ok, err = pcall(function()
    login()
    local p = added("nameplate1")
    local u = stub.units.nameplate1
    T.eq(p.cast.light:GetAlpha(), 0, "off on a new plate")
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(1) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.eq(p.cast.light:GetAlpha(), 0, "off on the first cast")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1")
    T.truthy(p.cast.light:GetAlpha() > 0, "the hit flashes")
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.eq(p.cast.light:GetAlpha(), 0, "off again on the next cast")
    end)
    stub.AlphaRule = nil
    if not ok then error(err, 0) end
end)

T.test("nameplates: class gradient paints the unit's pair; threat bar wins", function()
    local NP = login()
    local DUI = DaylightUI
    local p = added("nameplate1")
    DUI:Set("Nameplates", "healthColor", "classGradient")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    local lo, hi = DUI.Gradients.Colors("HOSTILE")
    local grad = p.health:GetStatusBarTexture().__gradient
    T.truthy(grad, "gradient set")
    T.eq(grad[2], lo); T.eq(grad[3], hi)
    -- a threat color on the bar replaces it
    DUI:Set("Nameplates", "threat", true)
    DUI:Set("Nameplates", "threatBar", true)
    local old = NP.Plate.ThreatColor
    NP.Plate.ThreatColor = function() return { 1, 0, 0 } end
    p.health:GetStatusBarTexture().__gradient = nil
    NP.Plate.UpdateColor(p)
    local tg = p.health:GetStatusBarTexture().__gradient
    T.truthy(tg, "threat color keeps a gradient")
    T.truthy(tg[2] ~= lo or tg[3] ~= hi, "but not the class pair")
    -- a flat health mode keeps the flat threat color
    DUI:Set("Nameplates", "healthColor", "class")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.rgb(p.health.__barColor, { DUI.Style.Soften(1, 0, 0) }, "flat threat color")
    NP.Plate.ThreatColor = old
end)

T.test("nameplates: bosses, rares and casters in their own colors (off by default; threat wins)", function()
    local NP = login(function()
        -- An earlier test swaps it: the fake game's own again.
        _G.UnitClassification = function(u) local x = stub.units[u]; return x and x.classification or "normal" end
    end)
    local DUI = DaylightUI
    local S = DUI.Style
    local p = added("nameplate1")
    local u = stub.units.nameplate1
    u.powerType, u.powerToken = 1, "RAGE"
    DUI:Set("Nameplates", "healthColor", "class")
    stub.RunTimers()
    -- Off by default: a rare looks like any mob.
    u.classification = "rare"
    NP.Plate.UpdateColor(p)
    T.eq(p.kind, nil, "off by default")
    T.rgb(p.health.__barColor, { S.ReactionColor(u.reaction) }, "reaction color")
    -- On: the rare in its color.
    DUI:Set("Nameplates", "rareBar", true)
    DUI:Set("Nameplates", "rareColor", { 0, 0, 1 })
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.eq(p.kind, "rare")
    T.rgb(p.health.__barColor, { S.Soften(0, 0, 1) }, "rare color")
    -- A boss wins over a rare.
    DUI:Set("Nameplates", "bossBar", true)
    DUI:Set("Nameplates", "bossColor", { 1, 0, 0 })
    stub.RunTimers()
    u.boss = true
    NP.Plate.UpdateColor(p)
    T.eq(p.kind, "boss", "UnitIsBossMob")
    u.boss, u.classification = nil, "worldboss"
    NP.Plate.UpdateColor(p)
    T.eq(p.kind, "boss", "a world boss")
    T.rgb(p.health.__barColor, { S.Soften(1, 0, 0) }, "boss color")
    -- Only a mana user counts as a caster. A druid's form change repaints.
    u.classification = "normal"
    DUI:Set("Nameplates", "casterBar", true)
    DUI:Set("Nameplates", "casterColor", { 0, 1, 0 })
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.eq(p.kind, nil, "rage: not a caster")
    u.powerType, u.powerToken = 0, "MANA"
    stub.FireEvent("UNIT_DISPLAYPOWER", "nameplate1")
    T.eq(p.kind, "caster", "mana now")
    T.rgb(p.health.__barColor, { S.Soften(0, 1, 0) }, "caster color")
    -- On a gradient bar it stays a gradient, made from its color.
    DUI:Set("Nameplates", "healthColor", "classGradient")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    local lo, hi = DUI.Gradients.Colors("HOSTILE")
    local grad = p.health:GetStatusBarTexture().__gradient
    T.truthy(grad and (grad[2] ~= lo or grad[3] ~= hi), "a gradient, not the class pair")
    -- Threat on the bar wins.
    DUI:Set("Nameplates", "healthColor", "class")
    DUI:Set("Nameplates", "threat", true)
    DUI:Set("Nameplates", "threatBar", true)
    stub.RunTimers()
    local old = NP.Plate.ThreatColor
    NP.Plate.ThreatColor = function() return { 1, 1, 0 } end
    NP.Plate.UpdateColor(p)
    T.rgb(p.health.__barColor, { S.Soften(1, 1, 0) }, "threat over it")
    NP.Plate.ThreatColor = old
    -- Never on players.
    u.isPlayer, u.class = true, "MAGE"
    NP.Plate.UpdateColor(p)
    T.eq(p.kind, nil, "a player is never a caster")
    u.isPlayer, u.class = nil, nil
end)

T.test("nameplates: a hidden class (battlegrounds) still shows its own colors", function()
    local NP = login(function()
        stub.units.nameplate3 = { name = "Rival", isPlayer = true, class = "MAGE", classHidden = true,
            reaction = 2, hostile = true, health = 80, maxHealth = 100 }
    end)
    local DUI = DaylightUI
    local p = added("nameplate3")
    DUI:Set("Nameplates", "healthColor", "classGradient")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    local mage, other = p.classLayers.MAGE, p.classLayers.ROGUE
    T.truthy(mage:IsShown(), "class layers shown")
    T.truthy(issecretvalue(mage.__cell), "the secret id goes straight to the sheet")
    T.eq(mage.__cell.__value, 8, "mage's cell")
    T.truthy(string.find(mage:GetTexture(), "classcell-8.png", 1, true), "mage's sheet")
    local lo, hi = DUI.Gradients.Colors("MAGE")
    T.eq(mage.__gradient[2], lo, "the mage pair"); T.eq(mage.__gradient[3], hi)
    lo = DUI.Gradients.Colors("ROGUE")
    T.eq(other.__gradient[2], lo, "each layer its own class's pair")
    -- The name and guild get a copy per class in its own window, hung off a bar
    -- holding the secret id. The plain ones step aside.
    _G.GetGuildInfo = function(u) if u == "nameplate3" then return "Horde Crew" end end
    DUI:Set("Nameplates", "nameColor", "classGradient")
    stub.RunTimers()
    NP.Plate.UpdateSub(p)
    NP.Plate.UpdateColor(p)
    -- A guild picked its own color: it stays on the plain line.
    NP.cfg.guildColor = "white"
    NP.Plate.UpdateSub(p)
    NP.Plate.UpdateColor(p)
    T.eq(p.sub:GetAlpha(), 1, "a guild in its own color isn't a class copy")
    NP.cfg.guildColor = "class"
    NP.Plate.UpdateSub(p)
    NP.Plate.UpdateColor(p)
    local ct = p.classText
    T.truthy(ct, "class text built")
    T.truthy(issecretvalue(ct.sel.__value), "the secret id goes straight into the bar")
    T.eq(ct.sel.__value.__value, 8)
    T.eq(p.name:GetAlpha(), 0, "plain name steps aside")
    T.eq(p.sub:GetAlpha(), 0, "plain guild steps aside")
    local name = ct.name.MAGE
    T.eq(name.__text, DUI.Gradients.Text("MAGE", "Rival"), "the mage pair's letters, as anywhere else")
    T.eq(ct.name.ROGUE.__text, DUI.Gradients.Text("ROGUE", "Rival"), "each copy its own class")
    T.truthy(name:IsShown() and ct.wins.MAGE:IsShown())
    T.eq(ct.sub.MAGE.__text, "<Horde Crew>")
    T.rgb(ct.sub.MAGE.__textColor, { DUI.Style.ClassColor("MAGE") }, "guild in the class color")
    DUI:Set("Nameplates", "nameColor", "class")
    stub.RunTimers()
    NP.Plate.UpdateSub(p)
    NP.Plate.UpdateColor(p)
    -- A flat class color needs no copies. The game's own (secret) color goes
    -- straight onto the name and guild line, no windows.
    T.falsy(ct.wins.MAGE:IsShown(), "no windows for a flat class color")
    T.eq(p.name:GetAlpha(), 1, "the plain name shows")
    T.truthy(issecretvalue(p.name.__textColor[1]), "in the game's class color, secret")
    T.eq(p.name.__textColor[1].__value, RAID_CLASS_COLORS.MAGE.r, "mage")
    T.truthy(issecretvalue(p.sub.__textColor[1]), "the guild line too")
    T.eq(p.sub:GetAlpha(), 1)
    _G.GetGuildInfo = nil
    -- flat class colors: each layer in its class color
    DUI:Set("Nameplates", "healthColor", "class")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.rgb(mage.__vertex, { DUI.Style.ClassColor("MAGE") }, "flat mage color")
    -- other modes, or a class that isn't hidden: no layers
    DUI:Set("Nameplates", "healthColor", "gradient")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.falsy(mage:IsShown(), "hidden in health-gradient mode")
    DUI:Set("Nameplates", "healthColor", "class")
    stub.RunTimers()
    stub.units.nameplate3.classHidden = nil
    NP.Plate.UpdateColor(p)
    T.falsy(mage:IsShown(), "a known class paints the bar itself")
    T.rgb(p.health.__barColor, { DUI.Style.ClassColor("MAGE") }, "mage")
    T.falsy(ct.wins.MAGE:IsShown(), "and the name itself")
    T.eq(p.name:GetAlpha(), 1)
end)

T.test("nameplates: class gradient names color each letter", function()
    local NP = login()
    local DUI = DaylightUI
    local p = added("nameplate1")
    DUI:Set("Nameplates", "nameColor", "classGradient")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    local t = p.name.__text
    T.truthy(t:find("|cff%x%x%x%x%x%x%S|r"), "letters colored")
    T.eq(t:gsub("|cff%x%x%x%x%x%x", ""):gsub("|r", ""), "Searing Whelp", "same words")
    T.eq(p.name.__textColor[1], 1, "drawn on white")
    DUI:Set("Nameplates", "nameColor", "white")
    stub.RunTimers()
    NP.Plate.UpdateColor(p)
    T.eq(p.name.__text, "Searing Whelp", "plain again")
end)

T.test("nameplates: threat colors are settings", function()
    local NP = login(function() stub.role = "DAMAGER" end)
    local DUI = DaylightUI
    DUI:Set("Nameplates", "threatAggro", { 0, 1, 1 })
    stub.RunTimers()
    local p = added("nameplate1")
    _G.IsInGroup = function() return true end
    _G.UnitThreatSituation = function() return 3 end
    NP.Plate.UpdateColor(p)
    T.rgb(p.health.__barColor, { DUI.Style.Soften(0, 1, 1) }, "pulled, in your color")
    DUI:Set("Nameplates", "threatLost", { 1, 0, 1 })
    stub.RunTimers()
    _G.UnitThreatSituation = function() return 0 end
    NP.Plate.UpdateColor(p)
    T.rgb(p.health.__barColor, { DUI.Style.Soften(1, 0, 1) }, "on someone else, in your color")
    _G.UnitThreatSituation = nil
end)

T.test("nameplates: the last combo pip fills red, its empty part gold like the rest", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    local S = DaylightUI.Style
    local row = ns.Combo.row
    local red = { S.Soften(ns.Combo.FULL_COLOR[1], ns.Combo.FULL_COLOR[2], ns.Combo.FULL_COLOR[3]) }
    local gold = { S.Soften(ns.Combo.COLOR[1], ns.Combo.COLOR[2], ns.Combo.COLOR[3]) }
    T.rgb(row.pips[5].bar.__barColor, red, "the fifth fills red")
    T.rgb(row.pips[4].bar.__barColor, gold)
    T.near(S.BarBack(row.pips[5].bar).__vertex[1], gold[1] * S.BAR_BACK_DIM, 1e-6, "its empty part gold")
end)

T.test("nameplates: the click margin widens the game's plate, in and out of combat alike", function()
    local size
    login(function()
        C_NamePlate.SetNamePlateSize = function(w, h) size = { w, h } end
    end)
    local before = size[1]
    DaylightUI:Set("Nameplates", "clickPad", DaylightUI:Get("Nameplates", "clickPad") + 5)
    stub.RunTimers()
    T.eq(size[1], before + 10 * stub.nameplates.cfg.scale, "5 more each side")
    added("nameplate1")
    T.isnil(plates[1].__hit, "the plate's click points stay the game's")
end)

T.test("nameplates: stacking or overlapping, the game's own setting", function()
    local set = {}
    login(function()
        Enum.NamePlateStackType = { None = 0, Enemy = 1, Friendly = 2 }
        _G.C_CVar = { SetCVarBitfield = function(name, i, v) set[name .. i] = v end }
    end)
    DaylightUI:Set("Nameplates", "stacking", "stack")
    T.eq(set["nameplateStackingTypes1"], true, "enemies stack")
    T.eq(set["nameplateStackingTypes2"], false)
    DaylightUI:Set("Nameplates", "stacking", "overlap")
    T.eq(set["nameplateStackingTypes1"], false, "they overlap")
end)

T.test("nameplates: a plate reused for another unit shows nothing of the last one, even for a frame", function()
    local realMarker, realGuild = _G.GetRaidTargetIndex, _G.GetGuildInfo
    login(function()
        _G.GetRaidTargetIndex = function(u) if u == "nameplate2" then return 8 end end
        _G.GetGuildInfo = function(u) if u == "nameplate2" then return "Daylight Crew" end end
    end)
    local p = added("nameplate2")
    T.truthy(p.marker:IsShown() and p.sub:IsShown(), "the last unit's marker and guild")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    stub.units.nameplate3 = { name = "Wolf", hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 }
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")      -- the frame it comes up: no timers yet
    local q = stub.nameplates.Manager.byUnit.nameplate3
    T.eq(q, p, "the same plate, reused")
    T.falsy(q.marker:IsShown(), "no old raid marker")
    T.falsy(q.sub:IsShown(), "no old guild line")
    T.eq(q.level.__text, "", "no old level")
    T.falsy(q.quest:IsShown())
    T.isnil(q.guild)
    T.eq(q.name.__text, "Wolf", "its own name at once")
    stub.RunTimers()
    T.truthy(q.level.__text ~= "", "its own level the frame after")
    _G.GetRaidTargetIndex, _G.GetGuildInfo = realMarker, realGuild
end)

T.test("nameplates: the bar's end can be straight", function()
    local NP = login()
    DaylightUI:Set("Nameplates", "slant", false)
    stub.RunTimers()
    local p = added("nameplate1")
    T.eq(p.hpCut, 0)
end)

T.test("nameplates: the game setting a new plate's click area keeps it (no hook on the plate)", function()
    login()
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    local np = plates[1]
    np:SetHitTestPoints({})   -- the game's own setup, as the plate comes up
    stub.RunTimers()
    T.eq(np.__hit, "the game's", "left as the game set it")
    T.isnil(rawget(np, "__hooked_SetHitTestPoints"))
end)

T.test("nameplates: the game's click insets reach past the frame, so its whole area can be clicked", function()
    local got = {}
    login(function()
        Enum.NamePlateType = { Enemy = 0, Friendly = 1 }
        _G.C_NamePlateManager = { SetNamePlateHitTestInsets = function(k, l, r, t, b) got[k] = { l, r, t, b } end }
    end)
    T.eq(got[0][1], -10000); T.eq(got[1][4], -10000)
    _G.C_NamePlateManager = nil
end)

T.test("nameplates: the stacking frame carries an unseen fill, so the game can measure it", function()
    login()
    local p = added("nameplate1")
    T.truthy(p.stack.fill, "a fill")
    T.eq(p.stack.fill.__color[4], 0, "never seen")
    T.eq(plates[1].__stack, p.stack)
end)

T.test("nameplates: the game's own plate is seen again when the unit leaves", function()
    login()
    added("nameplate1")
    local uf = plates[1].UnitFrame
    T.eq(uf:GetAlpha(), 0, "unseen while ours is up")
    T.truthy(uf.castBar:GetParent() ~= uf, "its pieces parked off it")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.eq(uf:GetAlpha(), 1, "back in view for the game's next unit")
    T.eq(uf.castBar:GetParent(), uf, "with its pieces back")
    T.eq(uf.name:GetParent(), uf, "and its name")
    T.eq(uf.name:GetAlpha(), 1, "seen again")
    T.falsy(uf.WidgetContainer:IsIgnoringParentAlpha())
end)

-- The game shares plate frames from a pool and hands one out as a plate gets
-- its unit, which can be after the addon's event handler ran. Its OnEvent
-- hands the frame out. The last argument stands in for the pool's choice so
-- a test can pick the frame. As in the game's Blizzard_NamePlates and
-- CompactUnitFrame.lua, the only Lua that sets the frame's alpha is
-- CompactUnitFrame_UpdateCenterStatusIcon (SetAlpha(1), since plates don't
-- fade out of range). It's reached from this OnEvent: SetUnit -> UpdateAll
-- as a frame is handed out, and UpdateNamePlateOptions -> ApplyFrameOptions
-- on every plate (DISPLAY_SIZE_CHANGED, VARIABLES_LOADED, CVAR_UPDATE of its
-- option CVars). The frame's own events are stopped while the addon's plate
-- is on it.
local function driver()
    local d = CreateFrame("Frame")
    d.optionCVars = { nameplateShowClassColor = true, nameplateShowFriendlyClassColor = true }
    function d:OnNamePlateAdded(unit, uf)
        local np = C_NamePlate.GetNamePlateForUnit(unit)
        np.UnitFrame = uf or CreateFrame("Button", nil, np)
        np.UnitFrame:SetAlpha(1)
    end
    function d:UpdateNamePlateOptions()
        for _, np in pairs(plates) do
            if np.UnitFrame then np.UnitFrame:SetAlpha(1) end
        end
    end
    d:SetScript("OnEvent", function(self, event, unit, uf)
        if event == "NAME_PLATE_UNIT_ADDED" then self:OnNamePlateAdded(unit, uf)
        elseif event == "DISPLAY_SIZE_CHANGED" or event == "VARIABLES_LOADED" then self:UpdateNamePlateOptions()
        elseif event == "CVAR_UPDATE" and self.optionCVars[unit] then self:UpdateNamePlateOptions()
        end
    end)
    _G.NamePlateDriverFrame = d
end
local function handOut(unit, uf)
    NamePlateDriverFrame:GetScript("OnEvent")(NamePlateDriverFrame, "NAME_PLATE_UNIT_ADDED", unit, uf)
end
local function driverEvent(event, ...)
    NamePlateDriverFrame:GetScript("OnEvent")(NamePlateDriverFrame, event, ...)
end

T.test("nameplates: the frame the game hands a plate after our handler is hidden too", function()
    login(driver)
    added("nameplate1")
    handOut("nameplate1")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(plates[1].UnitFrame:GetAlpha(), 0, "the game's new frame unseen under ours")
    -- The same frame handed to the same plate again: the game shows it, the addon doesn't.
    handOut("nameplate1", plates[1].UnitFrame)
    T.eq(plates[1].UnitFrame:GetAlpha(), 0, "and kept unseen")
end)

T.test("nameplates: the game's options update showing its frames again leaves them unseen under ours", function()
    login(driver)
    added("nameplate1")
    added("nameplate2")
    for _, e in ipairs({ { "DISPLAY_SIZE_CHANGED" }, { "CVAR_UPDATE", "nameplateShowClassColor" }, { "VARIABLES_LOADED" } }) do
        driverEvent(e[1], e[2])
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        T.eq(plates[1].UnitFrame:GetAlpha(), 0, e[1] .. ": unseen")
        T.eq(plates[2].UnitFrame:GetAlpha(), 0, e[1] .. ": every one")
    end
    -- A plate ours isn't on keeps the game's.
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    driverEvent("DISPLAY_SIZE_CHANGED")
    T.eq(plates[2].UnitFrame:GetAlpha(), 1, "the game's own plate left seen")
end)

T.test("nameplates: no hook on the game's plate frame's own methods", function()
    login(driver)
    local real = _G.hooksecurefunc
    local hooked = {}
    _G.hooksecurefunc = function(a, b, ...)
        if type(a) == "table" then hooked[#hooked + 1] = tostring(b) end
        return real(a, b, ...)
    end
    added("nameplate1")
    handOut("nameplate1")
    _G.hooksecurefunc = real
    T.eq(#hooked, 0, "hooked: " .. tostring(hooked[1]))
end)

T.test("nameplates: the game's frame, switched off under ours, works again when the game hands it on", function()
    login(driver)
    added("nameplate1")
    local uf = plates[1].UnitFrame
    T.falsy(uf:IsEventRegistered("UNIT_HEALTH"), "off under ours")
    -- The game's SetUnit registers the unit events again as it hands the frame
    -- to a plate. One the addon doesn't take (the unit is gone) keeps them.
    uf:RegisterEvent("UNIT_HEALTH")
    stub.units.nameplate3 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 50, maxHealth = 100 }
    handOut("nameplate3", uf)
    T.falsy(stub.nameplates.Manager.byUnit.nameplate3, "ours isn't on it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(uf:IsEventRegistered("UNIT_HEALTH"), "not ours: left running")
    T.eq(uf:GetAlpha(), 1, "and seen")
end)

T.test("nameplates: a hidden frame handed to a plate without ours is seen again", function()
    login(driver)
    added("nameplate1")
    local uf = plates[1].UnitFrame
    T.eq(uf:GetAlpha(), 0)
    -- The game takes the plate back before the addon hears of it, and gives
    -- its frame to a plate the addon isn't on.
    stub.units.nameplate3 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 50, maxHealth = 100 }
    handOut("nameplate3", uf)
    T.falsy(stub.nameplates.Manager.byUnit.nameplate3, "ours isn't on it")
    T.eq(uf:GetAlpha(), 1, "the game's plate drawn where ours isn't")
    uf:SetAlpha(0.5)
    T.eq(uf:GetAlpha(), 0.5, "and left to the game")
end)

T.test("options: nameplates are split into tabs and every setting has one home", function()
    login()
    local section
    for _, s in ipairs(DaylightUI.Options.Sections()) do
        if s.id == "Nameplates" then section = s end
    end
    T.truthy(section, "a Nameplates section")
    T.truthy(#section.pages >= 5, "several tabs")
    local seen = {}
    for _, page in ipairs(section.pages) do
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do
                if item.key then
                    T.falsy(seen[item.key], "only once: " .. item.key)
                    seen[item.key] = true
                end
            end
        end
    end
    T.truthy(seen.targetOutline and seen["friendly.myBuffs"] and seen.kickStyle, "nothing dropped")
end)

T.test("options: nameplates are split into tabs and every setting has one home", function()
    login()
    local section
    for _, s in ipairs(DaylightUI.Options.Sections()) do
        if s.id == "Nameplates" then section = s end
    end
    T.truthy(section, "a Nameplates section")
    T.truthy(#section.pages >= 5, "several tabs")
    local seen = {}
    for _, page in ipairs(section.pages) do
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do
                if item.key then
                    T.falsy(seen[item.key], "only once: " .. item.key)
                    seen[item.key] = true
                end
            end
        end
    end
    T.truthy(seen.targetOutline and seen["friendly.myBuffs"] and seen.kickStyle, "nothing dropped")
end)

T.test("nameplates: the raid marker is our own icon", function()
    local NP = login()
    T.truthy(string.find(NP.Plate.MARKER_SHEET, "Media\\markers.png", 1, true))
end)

T.test("nameplates: the stacking box keeps its size when you target (the game re-stacks every plate when it changes)", function()
    login()
    local a = added("nameplate1")
    local b = added("nameplate2")
    local function box(p) return { p.stack:GetWidth(), p.stack:GetHeight(), p.stack:GetScale(), p.stack:GetNumPoints() } end
    local before = box(b)
    T.eq(before[4], 1, "one anchor and its own size: not pinned to the bar's corners")
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.deq(box(b), before, "another plate shrinking: its stacking box doesn't")
    local ui = UIParent:GetEffectiveScale()
    T.near(a.stack:GetScale(), ui, 1e-6, "the target's box: its plain size, not the zoom")
    stub.units.target = nil
end)

T.test("nameplates: by default only your target grows; the other plates aren't touched on a target switch", function()
    login()
    local P = stub.nameplates.Plate
    local a, b = added("nameplate1"), added("nameplate2")
    local ui = UIParent:GetEffectiveScale()
    local laid = {}
    local layout = P.Layout
    P.Layout = function(p, ...) laid[p] = (laid[p] or 0) + 1; return layout(p, ...) end
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(a:GetScale(), ui * 1.15, 1e-6, "the target grows")
    T.eq(b:GetScale(), ui, "the rest stay their size")
    T.isnil(laid[b], "and aren't laid out again (each layout costs the game a redraw)")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.isnil(laid[b], "nor when you clear it")
    P.Layout = layout
end)

-- What one plate asks the client to draw: every texture shown under it, and
-- how many of those go through a mask (the slow kind of drawing).
local function Style_back(p) return DaylightUI.Style.BarBack(p.health) end

-- What a plate draws, leaving out its aura buttons (the client's own, only
-- there while an aura shows).
local function drawCost(root)
    local shown, masked, masks = 0, 0, 0
    local skip = {}
    for _, c in pairs(root.auras or {}) do skip[c] = true end
    local function walk(f)
        for _, w in ipairs(stub.Children(f)) do
            if w.__type == "Texture" and w:IsVisible() then
                shown = shown + 1
                if w.__masks and #w.__masks > 0 then
                    masked = masked + 1
                    masks = masks + #w.__masks
                end
            end
            if not skip[w] then walk(w) end
        end
    end
    walk(root)
    return shown, masked, masks
end

T.test("nameplates: a plate stays light: the border has no masks, the fill one", function()
    login()
    local p = added("nameplate1")
    stub.RunTimers()
    -- Before the lean rebuild this was 41 shown, 24 masked (59 / 37 casting),
    -- with 69 mask textures built per plate.
    local s, m = drawCost(p)
    -- The fill's angled moving edge, and the heal and shield bars' edges (empty
    -- unless something is incoming).
    T.truthy(m <= 3, "an enemy plate draws only its fills masked, got " .. m .. " of " .. s)
    T.truthy(s <= 30, "and at most 30 textures, got " .. s)
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    s, m = drawCost(p)
    T.truthy(m <= 5, "casting: and the cast fill and its light, got " .. m .. " of " .. s)
    T.truthy(s <= 46, "casting: at most 46 textures, got " .. s)
    stub.units.nameplate1.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    -- Built, shown or not, masks go only where a fill moves.
    local built = 0
    local function walk(f)
        for _, w in ipairs(stub.Children(f)) do
            if w.__type == "MaskTexture" then built = built + 1 end
            walk(w)
        end
    end
    walk(p)
    -- The health, heal, shield and cast fills, the target outline's two rounded
    -- corners (on your target only), the crowd-control icon's round cut (the
    -- client's aura button), and your DoTs' veil's angled back end (only while
    -- your DoTs are on it). It was 69 before the lean rebuild.
    T.truthy(built <= 8, "at most 8 mask textures on a plate, got " .. built)
    -- The border's angled end is one leaned texture per ring, no mask.
    local L = p.body.layers.outline
    T.eq(#(L.mid.__masks or {}), 0, "the outline's angled end: no mask")
    T.truthy(L.mid.__vertexOffsets and L.mid.__vertexOffsets[4][1] < 0, "leaned along the cut")
    T.eq(#(Style_back(p).__masks or {}), 0, "the bar's back: leaned, no mask")
end)

T.test("nameplates: a see-through border (Border opacity) wears the shell itself; full opacity the lean rings", function()
    login()
    local p = added("nameplate1")
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    local S = DaylightUI.Style
    T.isnil(S.GetShell(p.hp), "full opacity (the default): no shell built at all")
    DaylightUI:Set("general", "borderAlpha", 0.5)
    stub.RunTimers()
    -- Stacked rings would show through each other, so it's the usual shell.
    T.truthy(p.body.shellMode, "see-through: the shell")
    local sh = S.GetShell(p.hp)
    T.truthy(sh and sh:IsShown(), "built and shown")
    T.falsy(p.body.holder:IsShown(), "the rings hidden")
    T.eq(S.GetSlant(p.hp).side, "right", "cut at its angled end")
    local csl = S.GetSlant(p.cast)
    T.truthy(csl and csl.ref and csl.ref.frame == p.hp, "the cast bar's shell carries the bar's angle on")
    -- Threat on the border reaches the shell.
    p.body.borderColor = nil
    stub.nameplates.Body.SetColors(p.body, { 1, 0, 0 }, { 0.5, 0, 0 })
    T.rgb(sh.opts.borderColor, { 1, 0, 0 }, "threat colors on the shell")
    stub.nameplates.Body.SetColors(p.body, nil, nil)
    DaylightUI:Set("general", "borderAlpha", 1)
    stub.RunTimers()
    T.falsy(p.body.shellMode)
    T.falsy(sh:IsShown(), "back to full: the shell hidden")
    T.truthy(p.body.holder:IsShown(), "the rings back")
    stub.units.nameplate1.cast = nil
end)

T.devtest("nameplates: /dui platecost (dev) takes the border away, hides plates, and puts them back", function()
    login()
    local p = added("nameplate1")
    local dev = {}
    assert(loadfile("DaylightUI_Dev/PlateCost.lua"))("DaylightUI_Dev", dev)
    local shell = p.body.holder
    DaylightUI.RunCommand("platecost noborder")
    T.falsy(shell:IsShown(), "no border")
    T.truthy(p.health:IsVisible(), "the bar stays")
    DaylightUI.RunCommand("platecost hidden")
    T.eq(p:GetAlpha(), 0, "not drawn")
    DaylightUI.RunCommand("platecost full")
    T.truthy(shell:IsShown(), "border back")
    T.eq(p:GetAlpha(), 1)
end)

-- How much work the moments that drop frames cost: a plate appearing, a
-- target switch, quest and threat events, in a crowd of ten.
local function crowd()
    login()
    for i = 3, 10 do
        stub.units["nameplate" .. i] = { name = "Whelp " .. i, hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 }
    end
    local scans = 0
    local get = C_TooltipInfo.GetUnit
    C_TooltipInfo.GetUnit = function(u) scans = scans + 1; return get(u) end
    local B = stub.nameplates.Body
    local function work(fn)
        B.TakeLayoutCount(); scans = 0
        fn()
        return B.TakeLayoutCount(), scans
    end
    return work
end

T.test("nameplates: a plate appearing, a target switch and quest events do little work", function()
    -- This made the game stutter when turning the camera in a crowd or switching
    -- targets (/dui perf showed the core over 5 ms on 58 frames in 10 s).
    local work = crowd()
    for i = 3, 9 do added("nameplate" .. i) end
    stub.RunTimers()
    local layouts, scans = work(function() stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate10") end)
    -- Before the fix: 9 layouts and 3 reads (laid out twice, tooltip read three times).
    T.eq(layouts, 2, "a new plate: its bar and its cast bar, once each")
    T.eq(scans, 0, "the tooltip waits for the frame after (the camera turning puts up many at once)")
    local p10 = stub.nameplates.Manager.byUnit.nameplate10
    T.truthy(p10.name.__text, "the name is there at once")
    layouts, scans = work(function()
        for i = 11, 13 do
            stub.units["nameplate" .. i] = { name = "Whelp " .. i, hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 }
            added("nameplate" .. i)
        end
        stub.RunTimers()
    end)
    T.eq(scans, 4, "then one read per new plate, in one pass (job line and quest mark share it)")
    for i = 11, 13 do stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
    layouts, scans = work(function()
        stub.units.target = stub.units.nameplate5
        stub.FireEvent("PLAYER_TARGET_CHANGED")
    end)
    T.eq(layouts, 0, "targeting only zooms the plate: no new layout")
    T.eq(scans, 0, "and no tooltip read")
    layouts, scans = work(function()
        stub.units.target = stub.units.nameplate6
        stub.FireEvent("PLAYER_TARGET_CHANGED")
    end)
    T.eq(layouts, 0, "a target switch: before, 8 layouts and 2 reads")
    T.eq(scans, 0)
    layouts, scans = work(function() stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate9") end)
    T.eq(layouts + scans, 0, "a plate going does nothing to the rest")
    layouts, scans = work(function()
        for _ = 1, 5 do stub.FireEvent("QUEST_LOG_UPDATE") end
        stub.RunTimers()
    end)
    T.eq(scans, 8, "five quest-log events: one pass over the 8 plates, not five (40 before)")
    -- Progress on a quest you have re-reads only plates that were quest units.
    -- A mob that isn't one can't become one without a quest coming or going.
    layouts, scans = work(function()
        for _ = 1, 5 do stub.FireEvent("QUEST_LOG_UPDATE") end
        stub.RunTimers()
    end)
    T.eq(scans, 0, "objective progress: no plate was a quest unit, none read (8 before)")
    stub.tooltips = { nameplate4 = { lines = {
        { type = 17, leftText = "Whelp Hunt" },
        { type = 8, leftText = "Whelp slain: 1/5" },
    } } }
    layouts, scans = work(function() stub.FireEvent("QUEST_ACCEPTED", 7); stub.RunTimers() end)
    T.eq(scans, 8, "a quest taken: every plate is read again")
    T.truthy(stub.nameplates.Manager.byUnit.nameplate4.quest:IsShown(), "and the new quest's mob is marked")
    layouts, scans = work(function() stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers() end)
    T.eq(scans, 1, "progress: only the quest unit is read")
    local QL0 = _G.C_QuestLog
    _G.C_QuestLog = { GetNumQuestLogEntries = function() return 3, 3 end }
    layouts, scans = work(function() stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers() end)
    T.eq(scans, 8, "the log's count changed (a quest came or went): every plate")
    layouts, scans = work(function() stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers() end)
    T.eq(scans, 1, "the same count: the quest unit only")
    _G.C_QuestLog = QL0
    stub.tooltips = nil
    layouts, scans = work(function() stub.FireEvent("QUEST_REMOVED", 7); stub.RunTimers() end)
    T.eq(scans, 8, "a quest gone: every plate again")
    T.falsy(stub.nameplates.Manager.byUnit.nameplate4.quest:IsShown())
    -- Players are never quest targets, and an empty quest log needs no reads.
    stub.units.nameplate3.isPlayer = true
    layouts, scans = work(function() stub.FireEvent("QUEST_ACCEPTED", 8); stub.RunTimers() end)
    T.eq(scans, 7, "a player's plate: no tooltip read")
    stub.units.nameplate3.isPlayer = nil
    local QL = _G.C_QuestLog
    _G.C_QuestLog = { GetNumQuestLogEntries = function() return 0, 0 end }
    layouts, scans = work(function() stub.FireEvent("QUEST_ACCEPTED", 9); stub.RunTimers() end)
    _G.C_QuestLog = QL
    T.eq(scans, 0, "no quests in the log: no tooltip read")
    -- Nothing changed: the marks and the raid markers aren't moved again.
    local moves = 0
    for _, q in pairs(stub.nameplates.Manager.byUnit) do
        local orig = q.marker.ClearAllPoints
        q.marker.ClearAllPoints = function(...) moves = moves + 1; return orig(...) end
    end
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.eq(moves, 0, "an unchanged quest log moves nothing")
    -- Marks off: quest events read nothing at all.
    DaylightUI:Set("Nameplates", "quest", false); stub.RunTimers()
    layouts, scans = work(function()
        stub.FireEvent("QUEST_LOG_UPDATE")
        stub.RunTimers()
    end)
    T.eq(scans, 0, "marks off: no tooltip read")
    stub.units.target = nil
end)

-- A quest log the plates can read finished flags from, using C_QuestLog's
-- GetInfo / GetQuestObjectives fields.
local function questLog(obj)
    return {
        GetNumQuestLogEntries = function() return 2, 1 end,
        GetInfo = function(i)
            if i == 1 then return { isHeader = true, title = "Elwynn Forest" } end
            if i == 2 then return { questID = 7, title = "Whelp Hunt" } end
        end,
        GetQuestObjectives = function(id)
            if id == 7 then return { obj } end
        end,
    }
end
local WHELP_TIP = { nameplate4 = { lines = {
    { type = 17, leftText = "Whelp Hunt" },
    { type = 8, leftText = "Whelp Fang: 9/10" },
} } }

T.test("nameplates: an objective that opens again (some sold) marks its mob again", function()
    local work = crowd()
    for i = 3, 9 do added("nameplate" .. i) end
    local QL0 = _G.C_QuestLog
    local obj = { text = "Whelp Fang: 9/10", finished = false, numFulfilled = 9, numRequired = 10 }
    _G.C_QuestLog = questLog(obj)
    stub.tooltips = WHELP_TIP
    stub.FireEvent("QUEST_ACCEPTED", 7); stub.RunTimers()
    local p4 = stub.nameplates.Manager.byUnit.nameplate4
    T.truthy(p4.quest:IsShown(), "the quest's mob is marked")
    -- All ten: the tooltip's line goes, the mark with it.
    obj.finished, obj.numFulfilled = true, 10
    stub.tooltips = nil
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.falsy(p4.quest:IsShown(), "done: no mark")
    -- Some sold: the objective is open again while the plate stays up.
    obj.finished, obj.numFulfilled = false, 9
    stub.tooltips = WHELP_TIP
    local _, scans = work(function() stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers() end)
    T.truthy(p4.quest:IsShown(), "open again: marked again")
    T.eq(scans, 8, "what's done changed: every plate read once (the 8 the perf test reads)")
    -- A tick of progress that finishes nothing: only the marked plate.
    obj.text = "Whelp Fang: 9/10"
    _, scans = work(function() stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers() end)
    T.eq(scans, 1, "nothing finished or opened: the marked plate only")
    _G.C_QuestLog = QL0
    stub.tooltips = nil
end)

-- The tooltip's quest lines can lag the accept, so there's one more pass a moment later.
T.test("nameplates: a quest taken reads every plate again a moment later", function()
    crowd()
    for i = 3, 9 do added("nameplate" .. i) end
    local QL0 = _G.C_QuestLog
    _G.C_QuestLog = questLog({ finished = false })
    local late, After = {}, C_Timer.After
    C_Timer.After = function(d, fn)
        if d >= 0.5 then late[#late + 1] = fn else After(d, fn) end
    end
    stub.tooltips = nil
    stub.FireEvent("QUEST_ACCEPTED", 7); stub.RunTimers()
    local p4 = stub.nameplates.Manager.byUnit.nameplate4
    T.falsy(p4.quest:IsShown(), "the tooltip hadn't its quest lines yet")
    stub.tooltips = WHELP_TIP
    T.eq(#late, 1, "one more pass waits")
    for _, fn in ipairs(late) do fn() end
    stub.RunTimers()
    C_Timer.After = After
    T.truthy(p4.quest:IsShown(), "a moment later: marked")
    _G.C_QuestLog = QL0
    stub.tooltips = nil
end)

T.test("nameplates: a threat event that doesn't change the threat color repaints nothing", function()
    crowd()
    local p = added("nameplate3")
    local P = stub.nameplates.Plate
    local painted = 0
    local real = P.UpdateColor
    P.UpdateColor = function(...) painted = painted + 1; return real(...) end
    for _ = 1, 5 do P.OnEvent(p, "UNIT_THREAT_LIST_UPDATE", "nameplate3") end
    T.eq(painted, 0, "same color: left alone")
    P.OnEvent(p, "UNIT_FACTION", "nameplate3")
    T.eq(painted, 1, "other color events still repaint")
    P.UpdateColor = real
end)

T.test("nameplates: a fight's events do little work (health, flags, combat)", function()
    crowd()
    for i = 3, 10 do added("nameplate" .. i) end
    local ns = stub.nameplates
    local P, M = ns.Plate, ns.Manager
    local p = M.byUnit.nameplate3
    -- Health: the heal and absorb amounts have their own events.
    local reads, realHeals = 0, _G.UnitGetIncomingHeals
    _G.UnitGetIncomingHeals = function(...) reads = reads + 1; return realHeals(...) end
    for _ = 1, 10 do P.OnEvent(p, "UNIT_HEALTH", "nameplate3") end
    T.eq(reads, 0, "a hit doesn't re-read incoming heals")
    P.OnEvent(p, "UNIT_MAXHEALTH", "nameplate3")
    T.eq(reads, 1, "a new max does")
    _G.UnitGetIncomingHeals = realHeals
    -- The bar's range: set by a new max, not by every hit.
    local ranges, realRange = 0, p.health.SetMinMaxValues
    p.health.SetMinMaxValues = function(...) ranges = ranges + 1; return realRange(...) end
    for _ = 1, 10 do P.OnEvent(p, "UNIT_HEALTH", "nameplate3") end
    T.eq(ranges, 0, "a hit leaves the range alone")
    stub.units.nameplate3.maxHealth = 200
    P.OnEvent(p, "UNIT_MAXHEALTH", "nameplate3")
    T.eq(ranges, 1, "a new max sets it")
    T.eq(select(2, p.health:GetMinMaxValues()), 200)
    p.health.SetMinMaxValues = realRange
    -- Flags (tagging, entering combat) and threat: the bar, not the name.
    local names, realName = 0, P.UpdateName
    P.UpdateName = function(...) names = names + 1; return realName(...) end
    for _ = 1, 5 do P.OnEvent(p, "UNIT_FLAGS", "nameplate3") end
    T.eq(names, 0, "flags leave the name alone")
    -- Combat starting and a roster burst cost one pass over the bars, the frame after.
    local bars, realBar = 0, P.UpdateBarColor
    P.UpdateBarColor = function(...) bars = bars + 1; return realBar(...) end
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    for _ = 1, 10 do stub.FireEvent("GROUP_ROSTER_UPDATE") end
    T.eq(bars, 0, "nothing in the same frame")
    stub.RunTimers()
    local plates = 0
    for _ in pairs(M.byUnit) do plates = plates + 1 end
    T.eq(bars, plates, "one pass over the plates, not 11")
    T.eq(names, 0, "and no names")
    -- A roster burst that changes neither "in a group" nor "the tank": nothing.
    bars = 0
    for _ = 1, 10 do stub.FireEvent("GROUP_ROSTER_UPDATE") end
    stub.RunTimers()
    T.eq(bars, 0, "same group state: no repaint")
    -- Flags that change neither tapped nor the reaction: no repaint.
    for _ = 1, 5 do P.OnEvent(p, "UNIT_FLAGS", "nameplate3") end
    T.eq(bars, 0, "unchanged flags: bar left alone")
    stub.units.nameplate3.tapped = true
    P.OnEvent(p, "UNIT_FLAGS", "nameplate3")
    T.eq(bars, 1, "tapped by someone else: repainted")
    stub.units.nameplate3.tapped = nil
    P.UpdateName, P.UpdateBarColor = realName, realBar
    -- The class layers stay hidden without being touched again.
    local shows = 0
    for _, tex in pairs(p.classLayers) do
        local orig = tex.SetShown
        tex.SetShown = function(...) shows = shows + 1; return orig(...) end
    end
    P.UpdateColor(p)
    T.eq(shows, 0, "class layers already hidden: untouched")
end)

T.test("nameplates: the mouse lights only the plate it's on, asking only that plate", function()
    crowd()
    for i = 3, 10 do added("nameplate" .. i) end
    local M = stub.nameplates.Manager
    -- The game answers "mouseover" with that unit's plate.
    local get = C_NamePlate.GetNamePlateForUnit
    C_NamePlate.GetNamePlateForUnit = function(unit, ...)
        if unit == "mouseover" then
            for u, data in pairs(stub.units) do
                if data == stub.units.mouseover and u:find("^nameplate") then return get(u, ...) end
            end
            return nil
        end
        return get(unit, ...)
    end
    local asks, real = 0, _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b) if b == "mouseover" then asks = asks + 1 end; return real(a, b) end
    local a, b = M.byUnit.nameplate4, M.byUnit.nameplate7
    stub.units.mouseover = stub.units.nameplate4; stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    T.truthy(a.hover:IsShown(), "the plate under the mouse lights")
    stub.units.mouseover = stub.units.nameplate7; stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    T.falsy(a.hover:IsShown(), "the one it left goes out")
    T.truthy(b.hover:IsShown())
    T.truthy(asks <= 2, "only the plate under the mouse is asked (" .. asks .. ", 20 before)")
    stub.units.mouseover = nil
    stub.RunOnUpdate(M.hoverWatcher, 0.01)
    T.falsy(b.hover:IsShown(), "the mouse off every unit: out")
    -- Its strength is the player's choice: brighter, or none at all.
    DaylightUI:Set("Nameplates", "hoverLight", 0.4)
    stub.units.mouseover = stub.units.nameplate4; stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    T.truthy(a.hover:IsShown())
    T.near(a.hover:GetAlpha(), 0.4, 0.001)
    stub.units.mouseover = nil
    stub.RunOnUpdate(M.hoverWatcher, 0.01)
    DaylightUI:Set("Nameplates", "hoverLight", 0)
    stub.units.mouseover = stub.units.nameplate4; stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    T.falsy(a.hover:IsShown(), "at 0 a plate never lights")
    stub.units.mouseover = nil
    stub.RunOnUpdate(M.hoverWatcher, 0.01)
    _G.UnitIsUnit, C_NamePlate.GetNamePlateForUnit = real, get
end)

T.test("nameplates: the mouse going straight from a totem to another plate puts the badge's light out", function()
    login()
    stub.units.nameplate3 = { name = "Searing Totem", minion = true, hostile = true, reaction = 2, health = 5, maxHealth = 5 }
    local totem, mob = added("nameplate3"), added("nameplate1")
    local get = C_NamePlate.GetNamePlateForUnit
    C_NamePlate.GetNamePlateForUnit = function(unit, ...)
        if unit == "mouseover" then
            for u, data in pairs(stub.units) do
                if data == stub.units.mouseover and u:find("^nameplate") then return get(u, ...) end
            end
            return nil
        end
        return get(unit, ...)
    end
    stub.units.mouseover = stub.units.nameplate3; stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    T.truthy(totem.badge.hover:IsShown(), "the badge lights under the mouse")
    stub.units.mouseover = stub.units.nameplate1; stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    T.falsy(totem.badge.hover:IsShown(), "and goes out when the mouse moves on")
    T.truthy(mob.hover:IsShown())
    C_NamePlate.GetNamePlateForUnit = get
end)

T.test("nameplates: a rogue's target switch moves the combo row without rebuilding it", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    for i = 3, 6 do
        stub.units["nameplate" .. i] = { name = "Whelp " .. i, hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 }
        added("nameplate" .. i)
    end
    stub.units.target = stub.units.nameplate3
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local S = DaylightUI.Style
    local shells, slants = 0, 0
    local realShell, realSlant = S.Shell, S.Slant
    S.Shell = function(...) shells = shells + 1; return realShell(...) end
    S.Slant = function(...) slants = slants + 1; return realSlant(...) end
    for i = 4, 6 do
        stub.units.target = stub.units["nameplate" .. i]
        stub.FireEvent("PLAYER_TARGET_CHANGED")
    end
    S.Shell, S.Slant = realShell, realSlant
    local row = ns.Combo.row
    T.eq(row:GetParent(), ns.Manager.byUnit.nameplate6, "on the new target")
    T.eq(shells, 0, "same-size plates: the pips keep their shells (15 before)")
    T.eq(slants, 0, "no pip slants, no hidden cast bars laid out (21 before)")
    -- A setting change still lays the pips out again.
    DaylightUI:Set("Nameplates", "comboHeight", 7); stub.RunTimers()
    T.eq(row.pips[1]:GetHeight(), 7)
    stub.units.target = nil
end)

T.test("nameplates: a plate coming or going doesn't check every other plate", function()
    crowd()
    for i = 3, 9 do added("nameplate" .. i) end
    local M = stub.nameplates.Manager
    local checks, real = 0, M.Usable
    M.Usable = function(...) checks = checks + 1; return real(...) end
    added("nameplate10")
    T.truthy(checks <= 2, "a new plate checks itself, not the other nine (" .. checks .. ")")
    local names, realName = 0, stub.nameplates.Plate.UpdateName
    stub.nameplates.Plate.UpdateName = function(...) names = names + 1; return realName(...) end
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate10")
    added("nameplate10")
    stub.nameplates.Plate.UpdateName = realName
    T.eq(names, 1, "set up: its name written once")
    checks = 0
    checks = 0
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate4")
    T.truthy(checks <= 2, "a plate going: the same (" .. checks .. ")")
    M.Usable = real
    -- Your target coming into view still sizes everything.
    stub.units.target = stub.units.nameplate6
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate6")
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    added("nameplate6")
    T.truthy(M.byUnit.nameplate6.isTarget)
    T.eq(M.byUnit.nameplate6.sizeGroup, "target")
    stub.units.target = nil
end)

T.test("nameplates: a rogue's energy ticks don't walk every plate", function()
    local ns = login(function() stub.units.player.class = "ROGUE" end)
    for i = 3, 10 do
        stub.units["nameplate" .. i] = { name = "Whelp " .. i, hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 }
        added("nameplate" .. i)
    end
    stub.units.target = stub.units.nameplate5
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local row = ns.Combo.row
    T.eq(row:GetParent(), ns.Manager.byUnit.nameplate5)
    local checks, real = 0, ns.Manager.StillUsable
    ns.Manager.StillUsable = function(...) checks = checks + 1; return real(...) end
    stub.comboPoints = 2
    for _ = 1, 20 do stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS") end
    ns.Manager.StillUsable = real
    T.eq(checks, 0, "20 ticks on the same target: no plate walked")
    T.eq(row.pips[2].bar:GetValue(), 2, "the count still follows")
    -- Energy ticks (the same event, another power) leave the row alone.
    local placed, realPlace = 0, ns.Combo.Place
    ns.Combo.Place = function(...) placed = placed + 1; return realPlace(...) end
    for _ = 1, 20 do stub.FireEvent("UNIT_POWER_FREQUENT", "player", "ENERGY") end
    T.eq(placed, 0, "energy ticks: no combo update")
    T.falsy(ns.Combo.row:IsEventRegistered("UNIT_POWER_UPDATE"), "one power event, not two")
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", stub.Secret("COMBO_POINTS"))
    T.eq(placed, 1, "a secret power type still updates")
    ns.Combo.Place = realPlace
    stub.units.target = nil
end)

T.devtest("nameplates: /dui platecost (dev) noauras and off switch the aura containers and the plates off, and full puts them back", function()
    login()
    local p = added("nameplate1")
    local dev = {}
    assert(loadfile("DaylightUI_Dev/PlateCost.lua"))("DaylightUI_Dev", dev)
    local d = p.auras.debuffs
    T.truthy(d:IsShown(), "debuffs on to start")
    DaylightUI.RunCommand("platecost noauras")
    T.falsy(d:IsShown(), "aura containers off")
    T.truthy(p:IsShown(), "the plate stays")
    DaylightUI.RunCommand("platecost off")
    T.falsy(p:IsShown(), "the plate hidden for real")
    DaylightUI.RunCommand("platecost full")
    T.truthy(p:IsShown())
    T.truthy(d:IsShown(), "aura containers back")
end)


-- Locked aura buttons under restrictions
local function lockSites()
    local out = {}
    for site, n in pairs(stub.lockSites) do out[#out + 1] = string.format("%4d  %s", n, site) end
    table.sort(out)
    return "\n" .. table.concat(out, "\n")
end

T.test("nameplates: a plate put up in a battleground touches no locked aura button; a new size waits for the match's end", function()
    local NP = login()
    stub.units.nameplate3 = { name = "Kobold", hostile = true, reaction = 2, health = 10, maxHealth = 10 }
    stub.SetRestriction("PvPMatch", true)
    local p = added("nameplate3")    -- a fresh plate from the spares, laid out from scratch
    T.truthy(p, "put up")
    T.eq(stub.lockErrors, 0, lockSites())
    local btn = p.auras.debuffs.__groups.mine.button
    local w = btn:GetWidth()
    DaylightUI:Set("Nameplates", "debuffSize", 30)
    stub.RunTimers()
    T.eq(stub.lockErrors, 0, lockSites())
    T.eq(btn:GetWidth(), w, "waits for the match to end")
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.eq(btn:GetWidth(), 30, "then takes the new size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the game's frame comes back when the game took it off its plate before telling us", function()
    login()
    added("nameplate1")
    local uf = plates[1].UnitFrame
    plates[1].UnitFrame = nil      -- the game releases its frame to its pool first
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.eq(uf:GetAlpha(), 1, "back in view")
    T.truthy(uf:IsEventRegistered("UPDATE_MOUSEOVER_UNIT"), "its own events again")
end)

T.test("nameplates: an error while putting ours on leaves nothing half done", function()
    local NP = login()
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")    -- up since login
    local spares = NP.Manager.Spares()
    local real = NP.Plate.Anchor
    NP.Plate.Anchor = function() error("boom") end
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    NP.Plate.Anchor = real
    stub.RunTimers()
    T.isnil(NP.Manager.byUnit.nameplate1, "not counted as ours")
    T.eq(NP.Manager.Spares(), spares, "our plate back with the spares")
    T.eq(plates[1].UnitFrame:GetAlpha(), 1, "the game's plate still in view")
    T.truthy(#stub.errors >= 1, "the error is reported")
end)

T.test("nameplates: a game plate let go no longer points at our frames", function()
    login()
    local p = added("nameplate1")
    local np = plates[1]
    T.eq(np.__stack, p.stack)
    T.eq(p.stack:GetParent(), np, "right on the game's plate (EllesmereUI's way)")
    local _, rel = p.stack:GetPoint(1)
    T.eq(rel, np, "pinned to it, never through our frames")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.falsy(p.stack:IsShown(), "ours hidden")
    T.eq(p.stack:GetNumPoints(), 0, "unpinned")
    T.eq(p.stack:GetParent(), p, "and taken back")
    T.falsy(np.__stack == np, "never pointed at itself")
    T.isnil(np.__hit, "its click area was never ours")
end)

T.test("nameplates: a plate of ours that can't be used any more still takes its stacking frame off", function()
    local NP = login()
    local p = added("nameplate1")
    local real = NP.Manager.Usable
    NP.Manager.Usable = function() return false end
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    NP.Manager.Usable = real
    T.falsy(p.stack:IsShown())
    T.eq(p.stack:GetParent(), p)
end)

T.test("nameplates: the stacking frame moves with our plate onto its next game plate", function()
    login()
    local p = added("nameplate1")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    local NP = stub.nameplates
    local np = plates[2]
    NP.Plate.Attach(p, np)         -- as Manager.Added puts a spare on the next game plate
    NP.Plate.Install(p, "nameplate2")
    T.eq(p.stack:GetParent(), np)
    local _, rel = p.stack:GetPoint(1)
    T.eq(rel, np, "pinned to the new one, not the old")
    T.truthy(p.stack:IsShown())
end)

T.test("nameplates: the pool covers every plate the game can show, built at login", function()
    local NP = login()
    T.eq(NP.Manager.PREPARE, 40)
    for i = 3, 40 do
        stub.units["nameplate" .. i] = { name = "Mob" .. i, hostile = true, reaction = 2, health = 10, maxHealth = 10 }
    end
    local made, real = 0, NP.Plate.Create
    NP.Plate.Create = function(...) made = made + 1; return real(...) end
    stub.EnterCombat()
    for i = 1, 40 do stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
    NP.Plate.Create = real
    T.eq(made, 0, "no plate built mid-fight")
end)

T.test("nameplates: a walk over the plates asks each plate once, not its pieces", function()
    local NP = login()
    local p = added("nameplate1")
    local asks = 0
    for _, f in ipairs({ p, p.hp, p.cast }) do
        local real = f.GetEffectiveScale
        f.GetEffectiveScale = function(...) asks = asks + 1; return real(...) end
    end
    NP.Manager.Each(function() end)
    T.eq(asks, 1)
end)

T.test("nameplates: a settings refresh writes the name once", function()
    local NP = login()
    local p = added("nameplate2")
    local names, real = 0, NP.Plate.UpdateName
    NP.Plate.UpdateName = function(...) names = names + 1; return real(...) end
    local texts, realC = 0, NP.Plate.UpdateClassText
    NP.Plate.UpdateClassText = function(...) texts = texts + 1; return realC(...) end
    NP.Plate.UpdateAll(p)
    NP.Plate.UpdateName, NP.Plate.UpdateClassText = real, realC
    T.eq(names, 1)
    T.eq(texts, 1)
end)

T.test("nameplates: an interrupt slices the cast bar (a line across, then it splits in two); a new cast or the plate going ends it", function()
    login()
    local DUI = DaylightUI
    stub.units.player.guid = "Player-1-00000001"
    local p = added("nameplate1")
    local k = p.blade
    T.truthy(k and not k:IsShown(), "built with the plate, hidden")
    T.eq(k:GetParent(), p, "on the plate, so it outlives the bar's hold")
    local u = stub.units.nameplate1
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000001", nil)
    T.truthy(k:IsShown(), "your kick")
    local r, g, b = DUI.Style.Accent()
    T.rgb(k.line.__vertex, { r, g, b }, "cut in the accent")
    T.truthy(p.cast.light:GetAlpha() > 0.8, "the bar flashes")
    T.falsy(k.halves[1]:IsShown(), "the bar holds while the line runs across")
    local d = DUI.Motion.Driver()
    for _ = 1, 12 do stub.RunOnUpdate(d, 1 / 60) end
    T.truthy(k.halves[1]:IsShown() and k.halves[2]:IsShown(), "then it splits in two")
    T.eq(p.cast:GetAlpha(), 0, "the halves stand in for the bar")
    T.rgb(k.halves[1].fill.__vertex, stub.nameplates.Cast.INTERRUPTED, "in the interrupted red")
    u.cast = nil
    stub.RunTimers()
    for _ = 1, 120 do
        if not (d and d:GetScript("OnUpdate")) then break end
        stub.RunOnUpdate(d, 1 / 60)
    end
    T.falsy(k:IsShown(), "then gone")
    T.eq(p.cast:GetAlpha(), 1, "the bar's own alpha back for the next cast")
    -- Someone else's, or a secret one under restrictions: warm white.
    local W = DUI.Motion.BLADE_EDGE
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.SetRestriction("Encounter", true)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000001", nil)
    stub.SetRestriction("Encounter", false)
    T.truthy(k:IsShown())
    T.rgb(k.line.__vertex, W, "a secret kicker: warm white")
    for _ = 1, 12 do stub.RunOnUpdate(d, 1 / 60) end
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.falsy(k:IsShown(), "a new cast ends it")
    T.eq(p.cast:GetAlpha(), 1, "and shows its bar")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000002", nil)
    T.rgb(k.line.__vertex, W, "someone else's: warm white")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.falsy(k:IsShown(), "the plate going ends it")
    local masks = #(k.line.__masks or {}) + #(k.tip.__masks or {}) + #(k.burst.__masks or {})
    for _, h in ipairs(k.halves) do masks = masks + #(h.edge.__masks or {}) + #(h.fill.__masks or {}) end
    T.eq(masks, 0, "no masks")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: every interrupt animation plays, stands in for the bar, and gives it back (no masks)", function()
    login()
    local DUI = DaylightUI
    stub.units.player.guid = "Player-1-00000001"
    local p = added("nameplate1")
    local k, u = p.blade, stub.units.nameplate1
    local d
    for _, style in ipairs(DUI.Motion.KICKS) do
        DUI:Set("Nameplates", "kickStyle", style)
        u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
        stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
        stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000001", nil)
        T.truthy(k:IsShown(), style .. " plays")
        T.eq(k.style, style, style .. " is the one picked")
        d = d or DUI.Motion.Driver()
        for _ = 1, 20 do stub.RunOnUpdate(d, 1 / 60) end
        local shown = 0
        for _, h in ipairs(k.pieces) do if h:IsShown() then shown = shown + 1 end end
        T.truthy(shown > 0, style .. ": its pieces stand in for the bar")
        T.eq(p.cast:GetAlpha(), 0, style .. ": the bar hidden under them")
        u.cast = nil
        stub.RunTimers()
        for _ = 1, 120 do
            if not d:GetScript("OnUpdate") then break end
            stub.RunOnUpdate(d, 1 / 60)
        end
        T.falsy(k:IsShown(), style .. ": then gone")
        T.eq(p.cast:GetAlpha(), 1, style .. ": the bar's alpha back")
    end
    local masks = 0
    for _, h in ipairs(k.pieces) do masks = masks + #(h.edge.__masks or {}) + #(h.fill.__masks or {}) end
    for _, e in ipairs(k.sparks) do masks = masks + #(e.__masks or {}) end
    T.eq(masks, 0, "no masks")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: 'Kicked by' names who interrupted in their class color, secret or not; the plate going hides it", function()
    login()
    local DUI = DaylightUI
    stub.units.player.guid = "Player-1-00000001"
    stub.units.party1 = { name = "Valeera", isPlayer = true, class = "ROGUE", guid = "Player-1-00000002" }
    local p = added("nameplate1")
    local t, u = p.kickTag, stub.units.nameplate1
    T.truthy(t and not t:IsShown(), "built with the plate, hidden")
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000002", nil)
    T.truthy(t:IsShown(), "shown")
    T.eq(stub.Text(t.name), "Valeera")
    T.eq(stub.Text(t.label), "Kicked by")
    T.rgb(t.name.__textColor, { DUI.Style.ClassTextColor("ROGUE") }, "in the rogue's class color")
    local _, rel = t:GetPoint(1)
    T.eq(rel, p.cast, "beside the cast bar")
    -- Under restrictions the client hands the GUID over as a secret. The name
    -- still shows (SetText takes it) and the color falls back to white.
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.SetRestriction("Encounter", true)
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000002", nil)
    stub.SetRestriction("Encounter", false)
    T.eq(stub.Text(t.name), "Valeera", "a secret kicker's name still shows")
    stub.RunTimers()
    local d = DUI.Motion.Driver()
    for _ = 1, 60 do
        if not d:GetScript("OnUpdate") then break end
        stub.RunOnUpdate(d, 1 / 60)
    end
    T.falsy(t:IsShown(), "then it fades out")
    -- Switched off: nothing.
    DUI:Set("Nameplates", "kickedBy", false)
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000002", nil)
    T.falsy(t:IsShown(), "off: no tag")
    DUI:Set("Nameplates", "kickedBy", true)
    u.cast = { name = "Fireball", notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1", "Cast-1", 133, "Player-1-00000002", nil)
    T.truthy(t:IsShown())
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    T.falsy(t:IsShown(), "the plate going hides it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the target outline runs along a gradient accent: Daylight's image, or the class pair", function()
    login()
    stub.units.player = stub.units.player or { name = "Me", isPlayer = true }
    stub.units.player.class = "MAGE"
    local p = added("nameplate1")
    stub.units.target = stub.units.nameplate1
    DaylightUI:Set("Nameplates", "targetAccent", true)
    DaylightUI:Set("general", "accent", "classGradient")
    stub.RunTimers()
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local S = DaylightUI.Style
    local lo, hi = S.AccentPair()
    local top = p.outline.pieces.TOP
    T.eq(top.__texture, stub.nameplates.Plate.LINE, "a plain line")
    T.truthy(top.__gradient, "the class pair across the long edge")
    T.near(top.__gradient[2].r, lo[1], 1e-6); T.near(top.__gradient[3].r, hi[1], 1e-6)
    T.near(p.outline.pieces.RIGHT.__vertex[1], hi[1], 1e-6, "the right end its light color")
    DaylightUI:Set("general", "accent", "gradient")
    stub.RunTimers()
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(top.__texture, S.GRADIENT_FILE, "the Daylight sweep's image")
    stub.units.target = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: an enemy totem is a round badge in its element's color, and the game's minion plates are switched on", function()
    local cvars = {}
    login(function()
        _G.SetCVar = function(k, v) cvars[k] = v end
        stub.spells = { [3599] = { name = "Searing Totem" }, [8143] = { name = "Tremor Totem" } }
    end)
    T.eq(cvars.nameplateShowEnemyMinions, "1", "the game shows enemy pets and totems")
    stub.units.nameplate3 = { name = "Searing Totem III", minion = true, hostile = true, reaction = 2, health = 5, maxHealth = 5 }
    local NP = stub.nameplates
    local p = added("nameplate3")
    T.truthy(p.badge:IsShown(), "a badge")
    T.falsy(p.hp:IsShown(), "no bar")
    T.falsy(p.name:IsShown(), "no name")
    T.eq(p.badge.icon.__portraitUnit, "nameplate3", "its portrait, drawn by the game")
    T.rgb(p.badge.ring.__vertex, NP.Minion.COLORS.fire, "the fire color (any rank)")
    local enemy = added("nameplate1")
    T.falsy(enemy.badge:IsShown(), "a mob keeps its bar")
    T.truthy(enemy.hp:IsShown())
    -- Targeted: the accent glow eases in.
    stub.units.target = stub.units.nameplate3
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    local d = DaylightUI.Motion.Driver()
    for _ = 1, 30 do if d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end end
    T.truthy(p.badge.glow:GetAlpha() > 0.5, "glows as your target")
    stub.units.target = nil
    -- Switched off: the bar again, and the game's switch off too.
    DaylightUI:Set("Nameplates", "minions", false)
    stub.RunTimers()
    T.falsy(p.badge:IsShown())
    T.truthy(p.hp:IsShown(), "a bar again")
    T.eq(cvars.nameplateShowEnemyMinions, "0")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: friendly plates off in instances hands the player's own switches back on the way out", function()
    local cvars = { nameplateShowFriendlyPlayers = "1", nameplateShowFriendlyNpcs = "0" }
    login(function()
        _G.SetCVar = function(k, v) cvars[k] = v end
        _G.GetCVar = function(k) return cvars[k] end
    end)
    local root = DaylightUI.DB.Root()
    T.eq(cvars.nameplateShowFriendlyPlayers, "1", "off by default: left alone")
    DaylightUI:Set("Nameplates", "friendly.hideInInstance", true)
    stub.RunTimers()
    T.eq(cvars.nameplateShowFriendlyPlayers, "1", "the open world: left alone")
    T.eq(root.friendlyPlatesWas, nil)
    stub.instance = "party"; _G.IsInInstance = function() return stub.instance ~= nil end
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(cvars.nameplateShowFriendlyPlayers, "0", "a dungeon: friendly players off")
    T.eq(cvars.nameplateShowFriendlyNpcs, "0")
    T.eq(root.friendlyPlatesWas.nameplateShowFriendlyPlayers, "1", "kept to hand back (saved: logging out inside)")
    -- Turned on again by the player inside, the kept value stays the first one.
    stub.FireEvent("ZONE_CHANGED_NEW_AREA")
    stub.RunTimers()
    T.eq(root.friendlyPlatesWas.nameplateShowFriendlyPlayers, "1")
    stub.instance = nil
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(cvars.nameplateShowFriendlyPlayers, "1", "out: the player's own back")
    T.eq(cvars.nameplateShowFriendlyNpcs, "0", "their NPC plates were off: still off")
    T.eq(root.friendlyPlatesWas, nil)
    -- Switched off while inside: back at once.
    stub.instance = "raid"
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(cvars.nameplateShowFriendlyPlayers, "0")
    DaylightUI:Set("Nameplates", "friendly.hideInInstance", false)
    stub.RunTimers()
    T.eq(cvars.nameplateShowFriendlyPlayers, "1", "the setting off: back")
    stub.instance = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a reused plate for the next totem shows its badge again (and the slim bar its portrait)", function()
    login(function() stub.spells = { [3599] = { name = "Searing Totem" } } end)
    stub.units.nameplate3 = { name = "Searing Totem", minion = true, hostile = true, reaction = 2, health = 5, maxHealth = 5 }
    local p = added("nameplate3")
    T.truthy(p.badge:IsShown())
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    local again = added("nameplate3")
    T.eq(again, p, "the same plate, reused")
    T.truthy(again.badge:IsShown(), "the badge again, not an empty plate")
    DaylightUI:Set("Nameplates", "minionStyle", "bar")
    stub.RunTimers()
    T.truthy(p.badge.mini:IsShown())
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    added("nameplate3")
    T.truthy(p.badge.mini:IsShown(), "the slim bar's portrait again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: in a battleground a minion's name is hidden: still a badge, in the enemy color", function()
    login(function() stub.spells = { [3599] = { name = "Searing Totem" } } end)
    stub.units.nameplate3 = { name = stub.Secret("Searing Totem"), minion = true, hostile = true, reaction = 2, health = 5, maxHealth = 5 }
    local p = added("nameplate3")
    T.truthy(p.badge:IsShown(), "a badge all the same")
    local r = p.badge.ring.__vertex[1]
    T.truthy(r > p.badge.ring.__vertex[3], "the enemy red, not an element")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the slim bar look: a short bar in the totem's color, its portrait beside it, the name above", function()
    login(function() stub.spells = { [5394] = { name = "Healing Stream Totem" } } end)
    DaylightUI:Set("Nameplates", "minionStyle", "bar")
    stub.RunTimers()
    stub.units.nameplate3 = { name = "Healing Stream Totem", minion = true, hostile = true, reaction = 2, health = 5, maxHealth = 5 }
    local NP = stub.nameplates
    local p = added("nameplate3")
    local enemy = added("nameplate1")
    T.falsy(p.badge:IsShown(), "no badge")
    T.truthy(p.hp:IsShown(), "a bar")
    T.truthy(p.name:IsShown(), "and its name")
    T.falsy(p.level:IsShown(), "no level")
    T.truthy(p.hp:GetWidth() < enemy.hp:GetWidth(), "shorter than a mob's")
    T.truthy(p.badge.mini:IsShown(), "its portrait beside it")
    T.eq(p.badge.mini.__portraitUnit, "nameplate3")
    local grad = p.health:GetStatusBarTexture().__gradient
    T.truthy(grad, "a gradient fill")
    local hi = grad[3]
    T.truthy(hi.b > hi.r, "in the water color")
    -- Back to the badge: the bar goes, the portrait beside it too.
    DaylightUI:Set("Nameplates", "minionStyle", "badge")
    stub.RunTimers()
    T.truthy(p.badge:IsShown())
    T.falsy(p.badge.mini:IsShown())
    T.falsy(p.hp:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: Fade other plates dims every plate but your target and a casting one", function()
    login()
    stub.units.nameplate3 = { name = "Wolf", hostile = true, reaction = 2 }
    local a, b, c = added("nameplate1"), added("nameplate2"), added("nameplate3")
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(c:GetAlpha(), 1, "off by default: nothing fades")
    DaylightUI:Set("Nameplates", "dimOthers", true)
    DaylightUI:Set("Nameplates", "dimAlpha", 0.4)
    stub.RunTimers()
    -- Eased down, not a jump.
    local d = DaylightUI.Motion.Driver()
    stub.RunOnUpdate(d, 0.05)
    local mid = c:GetAlpha()
    T.truthy(mid < 1 and mid > 0.4, "on its way down")
    for _ = 1, 30 do if d:GetScript("OnUpdate") then stub.RunOnUpdate(d, 1 / 60) end end
    T.eq(a:GetAlpha(), 1, "your target stays full")
    T.near(b:GetAlpha(), 0.4, 1e-6, "a friendly plate fades")
    T.near(c:GetAlpha(), 0.4, 1e-6, "another enemy fades")
    -- A cast brings it back to full; its end fades it again.
    DaylightUI.DB.General().motion = false
    stub.units.nameplate3.cast = { name = "Howl", texture = 1, notInterruptible = false, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate3")
    T.eq(c:GetAlpha(), 1, "casting: full")
    stub.units.nameplate3.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "nameplate3")
    T.near(c:GetAlpha(), 0.4, 1e-6, "cast over: faded again")
    -- A plate put up while you have a target starts faded.
    stub.units.nameplate4 = { name = "Boar", hostile = true, reaction = 2 }
    T.near(added("nameplate4"):GetAlpha(), 0.4, 1e-6, "a new plate starts faded")
    -- No target: every plate full.
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(b:GetAlpha(), 1); T.eq(c:GetAlpha(), 1)
    -- A plate going away is handed on full.
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate3")
    T.eq(c:GetAlpha(), 1, "reset for its next unit")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- As in the client, the curve is evaluated inside the game and the answer
-- comes back secret. Runs fn(alpha) with that in place.
local function withExecuteCurves(fn)
    local saved = { curves = _G.C_CurveUtil, pct = _G.UnitHealthPercent }
    _G.C_CurveUtil = { CreateCurve = function()
        local c = { pts = {} }
        function c:AddPoint(x, y) self.pts[#self.pts + 1] = { x, y } end
        function c:Eval(x)
            for i = 2, #self.pts do
                local a, b = self.pts[i - 1], self.pts[i]
                if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
            end
            return self.pts[#self.pts][2]
        end
        return c
    end }
    _G.UnitHealthPercent = function(u, predicted, curve)
        if type(curve) ~= "table" or not curve.Eval then return saved.pct(u, predicted, curve) end
        local x = stub.units[u]
        return stub.Secret(curve:Eval(stub.Plain(x.health) / stub.Plain(x.maxHealth)))
    end
    local function alpha(t)
        local a = t:GetAlpha()
        if type(a) == "table" then return stub.Plain(a) end
        return a
    end
    local ok, err = pcall(fn, alpha)
    _G.C_CurveUtil, _G.UnitHealthPercent = saved.curves, saved.pct
    if not ok then error(err, 0) end
end

T.test("nameplates: the execute range lights up once an enemy is in it (health secret)", function()
    withExecuteCurves(function(alpha)
        login()
        local p = added("nameplate1")
        T.eq(DaylightUI:Get("Nameplates", "execute"), "off", "off by default")
        T.falsy(p.exec:IsShown(), "off: nothing")
        DaylightUI:Set("Nameplates", "execute", "auto")
        stub.RunTimers()
        T.falsy(p.exec:IsShown(), "Your class: a priest has no execute, nothing")
        DaylightUI:Set("Nameplates", "execute", "on")
        stub.RunTimers()
        T.truthy(p.exec:IsShown(), "Always: shown")
        T.near(p.exec.band:GetWidth(), p.health:GetWidth() * 0.2, 1, "the band reaches 20% of the bar")
        T.eq(alpha(p.exec.lit), 0, "at 60%: not lit")
        stub.units.nameplate1.health = stub.Secret(15)
        stub.FireEvent("UNIT_HEALTH", "nameplate1")
        T.eq(alpha(p.exec.lit), 1, "at 15%: lit")
        DaylightUI:Set("Nameplates", "executePct", 0.1)
        stub.RunTimers()
        T.eq(alpha(p.exec.lit), 0, "the range set to 10%: 15% is out of it")
        T.falsy(added("nameplate2").exec:IsShown(), "never on a friendly plate")
        DaylightUI:Set("Nameplates", "execute", "off")
        stub.RunTimers()
        T.falsy(p.exec:IsShown(), "Off: gone")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end)
end)

T.test("nameplates: the execute range's styles, color, texture and line", function()
    withExecuteCurves(function(alpha)
        local ns = login(function() stub.units.player.class = "WARRIOR" end)
        local p = added("nameplate1")
        local e = p.exec
        local function set(k, v) DaylightUI:Set("Nameplates", k, v); stub.RunTimers() end
        set("execute", "auto")
        T.truthy(e.band:IsShown() and e.line:IsShown(), "Band (default): the faint band and the line")
        T.eq(e.hotTex, e.lit, "the band is what lights")
        T.falsy(e.pulse:IsPlaying(), "still")

        set("executeStyle", "line")
        T.falsy(e.band:IsShown(), "Line only: no band")
        T.falsy(e.lit:IsShown(), "...nothing lights")
        T.truthy(e.line:IsShown(), "...the line stays")

        set("executeStyle", "bar")
        T.truthy(e.fill and e.fill:IsShown(), "Whole bar: a light over the fill")
        T.falsy(e.lit:IsShown(), "...not the band")
        T.eq(alpha(e.fill), 0, "at 60%: not lit")
        stub.units.nameplate1.health = stub.Secret(15)
        stub.FireEvent("UNIT_HEALTH", "nameplate1")
        T.eq(alpha(e.fill), 1, "at 15%: the whole bar lights")

        set("executeStyle", "pulse")
        T.falsy(e.fill:IsShown(), "back to a band: the fill's light goes")
        T.eq(alpha(e.lit), 1, "the band lights at once")
        T.truthy(e.pulse:IsPlaying(), "Band, breathing: it pulses")
        set("executeStyle", "band")
        T.falsy(e.pulse:IsPlaying(), "Band: still again")

        set("executeAccent", false)
        set("executeColor", { 0.1, 0.8, 0.2 })
        local r, g = e.line:GetVertexColor()
        T.near(r, 0.1, 0.01, "accent off: the player's own color")
        T.near(g, 0.8, 0.01)

        set("executeStrength", 0.9)
        T.near(select(4, e.lit:GetVertexColor()), 0.9, 0.01, "brightness: how strongly it lights")
        set("executeTexture", "bar")
        T.eq(e.lit:GetTexture(), DaylightUI.Style.BarFile("fill"), "Bar texture: the shared bar texture")
        set("executeTexture", "fade")
        T.eq(e.lit:GetTexture(), ns.Plate.LINE, "Fade in: a plain fill, faded")

        set("executeLineSize", 0)
        T.falsy(e.line:IsShown(), "line 0: no line")
        set("executeRest", false)
        T.falsy(e.band:IsShown(), "no faint band")
        T.truthy(e.lit:IsShown(), "...the lit band still there")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end)
end)

T.test("nameplates: the execute range is off by default, a warrior too; Your class shows it", function()
    login(function() stub.units.player.class = "WARRIOR" end)
    local p = added("nameplate1")
    T.falsy(p.exec:IsShown(), "off by default")
    DaylightUI:Set("Nameplates", "execute", "auto")
    stub.RunTimers()
    T.truthy(p.exec:IsShown(), "Your class: a warrior has Execute")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- The quest mark in the addon's objective symbols (the Quests module names
-- the kind through DaylightUI.QuestKindForUnit)
-- ---------------------------------------------------------------------

local WOLF = { lines = { { type = 17, leftText = "Wolves at the Door" }, { type = 8, leftText = "Gray Wolf slain: 3/8" } } }

local function questUnit(kindFn, guid, plain)
    login(function()
        stub.tooltips = { nameplate1 = { lines = { WOLF.lines[1], { type = 8, leftText = WOLF.lines[2].leftText } } } }
        stub.units.nameplate1 = stub.units.nameplate1 or {}
        stub.units.nameplate1.guid = guid or "Creature-0-1-2-3-7-0"
    end)
    DaylightUI.QuestKindForUnit = kindFn
    -- The symbols are off by default because the plain ! reads better on a plate.
    if not plain then DaylightUI:Set("Nameplates", "questIcon", true) end
    stub.RunTimers()
    local p = added("nameplate1")
    return p
end

T.test("plate icon: a reused plate shows no quest symbol of its last mob, not even for a frame", function()
    local p = questUnit(function() return "kill", 1, 1, 1 end)
    T.truthy(p.questArt:IsShown())
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    DaylightUI.QuestKindForUnit, stub.tooltips = nil, nil
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    T.eq(stub.nameplates.Manager.byUnit.nameplate1, p, "the same plate")
    T.falsy(p.questArt:IsShown(), "no symbol from before")
    T.falsy(p.quest:IsShown())
end)

T.test("plate icon: by default the plain !", function()
    local p = questUnit(function() return "kill", 1, 1, 1 end, nil, true)
    T.truthy(p.quest:IsShown())
    T.eq(p.quest:GetText(), "!")
    T.falsy(p.questArt:IsShown())
    DaylightUI.QuestKindForUnit, stub.tooltips = nil, nil
end)

T.test("plate icon: a needed mob shows the sword", function()
    local asked
    local p = questUnit(function(guid) asked = guid; return "kill", 0.9, 0.2, 0.1 end)
    T.eq(asked, "Creature-0-1-2-3-7-0")
    T.truthy(p.quest:IsShown())
    T.truthy(p.questArt:IsShown(), "our symbol")
    T.eq(p.questArt.icon.__texture, DaylightUI.MEDIA .. "objective-kill.png")
    T.eq(p.questArt.icon.__vertex[1], 0.9, "in the quest's color")
    T.truthy(p.quest:GetText():find("objective-kill-edge", 1, true), "its dark edge holds the mark's place")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    DaylightUI.QuestKindForUnit, stub.tooltips = nil, nil
end)

T.test("plate icon: a secret GUID draws nothing", function()
    local called = false
    local p = questUnit(function() called = true; return "kill", 1, 1, 1 end, stub.Secret("Creature-0-1-2-3-7-0"))
    T.falsy(called, "a secret GUID never asked")
    T.falsy(p.questArt:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    DaylightUI.QuestKindForUnit, stub.tooltips = nil, nil
end)

T.test("plate icon: Quests off draws nothing", function()
    local p = questUnit(nil)
    T.truthy(p.quest:IsShown(), "the game's quest line still marks it")
    T.eq(p.quest:GetText(), "!")
    T.falsy(p.questArt:IsShown())
    stub.tooltips = nil
end)

T.test("plate icon: done objective clears", function()
    local p = questUnit(function() return "loot", 1, 1, 1 end)
    T.truthy(p.questArt:IsShown())
    stub.tooltips.nameplate1.lines[2].leftText = "Gray Wolf slain: 8/8"
    stub.FireEvent("QUEST_LOG_UPDATE"); stub.RunTimers()
    T.falsy(p.quest:IsShown()); T.falsy(p.questArt:IsShown())
    DaylightUI.QuestKindForUnit, stub.tooltips = nil, nil
end)

T.test("nameplates: an elite's dragon wraps the bar's end, sized by the bar's height; rares silver; + stays", function()
    local NP = login(function()
        _G.UnitLevel = function() return 20 end
        -- An earlier test leaves its own classification answer behind.
        _G.UnitClassification = function(u) local x = stub.units[u]; return x and x.classification or "normal" end
    end)
    stub.units.nameplate1.classification = "elite"
    local p = added("nameplate1")
    local D = NP.Plate.DRAGON
    T.truthy(p.dragon:IsShown(), "an enemy elite")
    T.eq(p.dragon.__texture, D.file)
    T.rgb(p.dragon.__vertex, NP.Plate.DRAGON_COLORS.gold, "gold")
    local h = p.hp:GetHeight()
    T.near(p.dragon:GetWidth(), D.w * h, 0.01, "as wide as its share of the bar's height")
    T.near(p.dragon:GetHeight(), D.h * h, 0.01, "never stretched: both sides from the height")
    local point, rel, relPoint, x, y = p.dragon:GetPoint(1)
    T.eq(point, "TOPLEFT"); T.eq(rel, p.hp); T.eq(relPoint, "TOPRIGHT")
    T.near(x, -D.endX * h, 0.01); T.near(y, D.topY * h, 0.01, "pinned to the bar's top-right corner")
    T.eq(p.level.__text, "20+", "the level keeps its +")
    -- A taller bar: a bigger dragon, the same shape.
    DaylightUI:Set("Nameplates", "height", 24)
    stub.RunTimers()
    T.near(p.dragon:GetHeight(), D.h * p.hp:GetHeight(), 0.01)
    T.near(p.dragon:GetWidth() / p.dragon:GetHeight(), D.w / D.h, 0.001, "same proportions")
    -- A rare: silver; a plain mob: none.
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    stub.units.nameplate1.classification = "rare"
    p = added("nameplate1")
    T.rgb(p.dragon.__vertex, NP.Plate.DRAGON_COLORS.silver, "silver")
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    stub.units.nameplate1.classification = "normal"
    p = added("nameplate1")
    T.falsy(p.dragon:IsShown(), "a plain mob: no dragon")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the elite dragon has an off switch, and no friendly or name-only plate gets one", function()
    local NP = login(function()
        _G.UnitLevel = function() return 20 end
        -- An earlier test leaves its own classification answer behind.
        _G.UnitClassification = function(u) local x = stub.units[u]; return x and x.classification or "normal" end
    end)
    stub.units.nameplate1.classification = "elite"
    local p = added("nameplate1")
    T.truthy(p.dragon:IsShown())
    DaylightUI:Set("Nameplates", "eliteDragon", false)
    stub.RunTimers()
    T.falsy(p.dragon:IsShown(), "switched off")
    T.eq(p.level.__text, "20+", "the + stays")
    DaylightUI:Set("Nameplates", "eliteDragon", true)
    stub.RunTimers()
    T.truthy(p.dragon:IsShown(), "back on")
    stub.units.nameplate2.classification = "elite"
    local f = added("nameplate2")
    T.falsy(f.dragon:IsShown(), "a friendly plate: none")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Friend or foe isn't fixed for a plate's whole life. The game's own plate
-- re-asks on UNIT_FACTION (OnUnitFactionChanged), and you can't attack
-- anything while dead, so everything that comes into view on the run back
-- answers "can't attack".
local function deadWorld(login_)
    local dead = true
    login_()
    local attack = _G.UnitCanAttack
    _G.UnitIsDeadOrGhost = function() return dead end
    _G.UnitIsFriend = function(_, u) local x = stub.units[u]; return x ~= nil and x.hostile ~= true end
    _G.UnitCanAttack = function(a, u) if dead then return false end return attack(a, u) end
    return function(now) dead = now end, function()
        _G.UnitIsDeadOrGhost, _G.UnitIsFriend, _G.UnitCanAttack = nil, nil, attack
    end
end

T.test("nameplates: a mob seen while you're dead keeps its bar, alive or ghost", function()
    local _, undo = deadWorld(login)
    local p = added("nameplate1")
    T.truthy(p.hp:IsShown(), "still an enemy: the bar stays")
    T.falsy(p.friendly, "not friendly")
    local f = added("nameplate2")
    T.falsy(f.hp:IsShown(), "a friend is still just a name")
    undo()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a plate put up as friendly becomes an enemy when the game says so", function()
    local NP = login()
    stub.units.nameplate3 = { name = "Turned Guard", reaction = 4, health = 50, maxHealth = 100 }
    local p = added("nameplate3")
    T.falsy(p.hp:IsShown(), "name only at first")
    stub.units.nameplate3.hostile = true
    stub.units.nameplate3.reaction = 2
    NP.Plate.OnEvent(p, "UNIT_FACTION", "nameplate3")
    stub.RunTimers()
    T.truthy(p.hp:IsShown(), "a bar now")
    T.falsy(p.friendly)
    stub.units.nameplate3.hostile = false
    NP.Plate.OnEvent(p, "UNIT_FLAGS", "nameplate3")
    stub.RunTimers()
    T.falsy(p.hp:IsShown(), "and back to a name when it calms down")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A mob you killed and can loot keeps its game plate (the engine leaves it
-- for the loot sparkle and interact icon). The game shows only its widgets
-- there, so the addon's plate goes too, whether the plate stays on the
-- corpse or the engine hands it over again. Plates used to stay on corpses.
T.test("nameplates: a lootable corpse shows no plate of ours, only the game's loot icon", function()
    local NP = login()
    local p = added("nameplate1")
    T.truthy(p:IsShown(), "alive: ours")
    local mob = stub.units.nameplate1
    mob.dead, mob.hostile, mob.health, mob.widgetsOnly = true, false, 0, true
    NP.Plate.OnEvent(p, "UNIT_HEALTH", "nameplate1")
    NP.Plate.OnEvent(p, "UNIT_FLAGS", "nameplate1")
    stub.RunTimers()
    T.falsy(p:IsShown(), "dead and lootable: ours gone at once")
    -- handed over again as a corpse
    local again = added("nameplate1")
    T.truthy(again == nil or not again:IsShown(), "re-added as a corpse: still nothing of ours")
    -- a corpse the engine doesn't mark widgets-only is still a corpse
    stub.units.nameplate4 = { name = "Dead Boar", reaction = 2, health = 0, maxHealth = 100, dead = true }
    local d = added("nameplate4")
    T.truthy(d == nil or not d:IsShown(), "a dead mob: no plate of ours")
    -- a dead player keeps theirs (the game shows it)
    stub.units.nameplate5 = { name = "Fallen Friend", isPlayer = true, class = "MAGE", reaction = 5, health = 0, maxHealth = 100, dead = true }
    local f = added("nameplate5")
    T.truthy(f and f:IsShown(), "a dead player: still shown")
    -- nothing lost from the pool
    local up = 0
    for _ in pairs(NP.Manager.byUnit) do up = up + 1 end
    T.eq(NP.Manager.Spares() + up, NP.Manager.PREPARE, "nothing leaked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: coming back to life re-asks every plate, also a moment later", function()
    login()
    stub.units.nameplate3 = { name = "Turned Guard", reaction = 4, health = 50, maxHealth = 100 }
    local p = added("nameplate3")
    T.falsy(p.hp:IsShown(), "name only at first")
    stub.units.nameplate3.hostile = true
    stub.FireEvent("PLAYER_UNGHOST")
    stub.RunTimers()
    T.truthy(p.hp:IsShown(), "bar back on the event")
    stub.units.nameplate3.hostile = false
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.falsy(p.hp:IsShown(), "a loading screen re-asks too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A layer or phase change swaps every unit around you with no loading screen.
-- What the game sends then isn't in its Lua source (the engine does it), so
-- a plate must survive a swap whatever arrives. No plate may stay on a unit
-- that's gone, or on a game plate that moved on to another unit. Every plate
-- is either on a unit or with the spares.
local function noneLost(NP)
    local up = 0
    for _ in pairs(NP.Manager.byUnit) do up = up + 1 end
    T.eq(NP.Manager.Spares() + up, NP.Manager.PREPARE, "nothing leaked")
end

T.test("nameplates: a game plate handed to a new unit with no removal takes the old plate of ours off it", function()
    local NP = login()
    local old = added("nameplate1")
    local np = old.nameplate
    stub.units.nameplate3, stub.units.nameplate1 = stub.units.nameplate1, nil
    local get = C_NamePlate.GetNamePlateForUnit
    C_NamePlate.GetNamePlateForUnit = function(u) if u == "nameplate3" then return np end return get(u) end
    local new = added("nameplate3")
    C_NamePlate.GetNamePlateForUnit = get
    T.falsy(NP.Manager.byUnit.nameplate1, "the gone unit is forgotten")
    T.eq(new.nameplate, np, "ours is on the game's plate")
    noneLost(NP)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a swap the game never announced heals itself", function()
    local NP = login()
    added("nameplate1")
    added("nameplate2")
    -- nameplate1 gone without a word, nameplate4 here without a word
    stub.units.nameplate1 = nil
    stub.units.nameplate4 = { name = "New Wolf", hostile = true, reaction = 2, health = 50, maxHealth = 100 }
    NP.Manager.Sync()
    stub.RunTimers()
    T.falsy(NP.Manager.byUnit.nameplate1, "gone")
    T.truthy(NP.Manager.byUnit.nameplate2, "the plate that stayed is left alone")
    T.truthy(NP.Manager.byUnit.nameplate4, "the new one is up")
    noneLost(NP)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a plate left standing isn't rebuilt by the check", function()
    local NP = login()
    local p = added("nameplate1")
    local installs, real = 0, NP.Plate.Install
    NP.Plate.Install = function(...) installs = installs + 1; return real(...) end
    NP.Manager.Sync()
    NP.Plate.Install = real
    T.eq(installs, 0, "nothing to do")
    T.eq(NP.Manager.byUnit.nameplate1, p)
end)

-- /dui platecheck: what a player sends in when a plate is missing.
local function checkText(NP) return table.concat(NP.Manager.CheckLines(), "\n") end

T.test("nameplates: /dui platecheck says when all is well", function()
    local NP = login()
    added("nameplate1")
    local text = checkText(NP)
    T.truthy(text:find("Game plates 2, ours 2", 1, true), text)
    T.truthy(text:find("nameplate1: enemy", 1, true), text)
    T.truthy(text:find("Nothing looks wrong", 1, true), text)
end)

T.test("nameplates: /dui platecheck names a plate of ours that is on but not showing", function()
    local NP = login()
    local p = added("nameplate1")
    p:Hide()
    local text = checkText(NP)
    T.truthy(text:find("ours shown=false", 1, true), text)
    T.truthy(text:find("LOOKS WRONG", 1, true), text)
end)

T.test("nameplates: /dui platecheck names a game plate we refused", function()
    local NP = login()
    local real = NP.Plate.Attach
    NP.Plate.Attach = function() error("nope") end
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    NP.Plate.Attach = real
    local text = checkText(NP)
    T.truthy(text:find("Game plates 2, ours 1", 1, true), text)
    T.truthy(text:find("no plate of ours, refused=true", 1, true), text)
    T.truthy(text:find("LOOKS WRONG", 1, true), text)
end)

T.test("nameplates: /dui platecheck reads a see-through game plate and never a secret", function()
    local NP = login()
    local p = added("nameplate1")
    p.nameplate:SetAlpha(0)
    local text = checkText(NP)
    T.truthy(text:find("game plate shown=true visible=true alpha=0.00", 1, true), text)
    T.truthy(text:find("LOOKS WRONG", 1, true), text)
    _G.UnitCanAttack = function() return stub.Secret(true) end
    T.truthy(pcall(NP.Manager.CheckLines), "a secret answer doesn't stop it")
end)

T.test("nameplates: /dui plateprobe hands each plate it can reach its own stacking frame", function()
    local NP = login()
    local p = added("nameplate1")
    local np = p.nameplate
    T.eq(np.__stack, p.stack)
    local done, failed = NP.Manager.Probe()
    T.eq(np.__stack, np)
    T.truthy(done >= 1)
    T.eq(failed, 0)
end)

T.test("nameplates: Group names paints your party and raid on friendly plates in their own color, and follows the roster", function()
    login()
    local DUI = DaylightUI
    local set = function(k, v) DUI:Set("Nameplates", k, v) end
    local p = added("nameplate2")
    local class = { DUI.Style.ClassTextColor("MAGE") }
    T.rgb(p.name.__textColor, class, "off by default: class color")
    stub.units.nameplate2.party = true
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.rgb(p.name.__textColor, class, "in the group, switch off: still class color")
    set("friendly.partyName", true); stub.RunTimers()
    T.rgb(p.name.__textColor, DUI:Get("Nameplates", "friendly.partyCustom"), "in the group: the group color")
    set("friendly.partyCustom", { 0.2, 0.9, 0.3 }); stub.RunTimers()
    T.rgb(p.name.__textColor, { 0.2, 0.9, 0.3 }, "the picked color")
    set("friendly.nameColor", "classGradient"); stub.RunTimers()
    T.eq(stub.Text(p.name), "Jaina", "no per-letter gradient over the group color")
    set("friendly.nameColor", "class"); stub.RunTimers()
    -- Left the group: back to class color on the roster event.
    stub.units.nameplate2.party = nil
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.rgb(p.name.__textColor, class, "left the group: class color again")
    -- A raid member counts too.
    stub.units.nameplate2.raid = true
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.rgb(p.name.__textColor, { 0.2, 0.9, 0.3 }, "raid member: the group color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: Group mark marks your group's friendly plates beside the name, which keeps its class color", function()
    login()
    local DUI = DaylightUI
    local set = function(k, v) DUI:Set("Nameplates", k, v) end
    local p = added("nameplate2")
    local m = p.groupMarks
    local class = { DUI.Style.ClassTextColor("MAGE") }
    stub.units.nameplate2.party = true
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.falsy(m.before:IsShown() or m.after:IsShown(), "off by default")
    set("friendly.partyMark", "before"); stub.RunTimers()
    T.truthy(m.before:IsShown(), "a mark before the name")
    T.falsy(m.after:IsShown())
    T.rgb(p.name.__textColor, class, "the name keeps its class color")
    T.rgb({ m.before:GetVertexColor() }, DUI:Get("Nameplates", "friendly.partyCustom"), "in the group color")
    local _, rel = m.before:GetPoint(1)
    T.eq(rel, p.name, "by the name")
    set("friendly.partyMark", "around"); stub.RunTimers()
    T.truthy(m.before:IsShown() and m.after:IsShown(), "one each side")
    stub.units.nameplate2.party = nil
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.falsy(m.before:IsShown() or m.after:IsShown(), "left the group: no mark")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: Reaction names paint enemy players red, not their class color", function()
    login()
    local DUI = DaylightUI
    T.eq(stub.nameplates.DEFAULTS.nameColor, "reaction", "the default for enemy plates")
    T.eq(stub.nameplates.DEFAULTS.friendly.nameColor, "class", "friendly plates keep class colors")
    DUI:Set("Nameplates", "nameColor", "reaction")
    stub.units.nameplate3 = { name = "Stabitha", isPlayer = true, class = "ROGUE", hostile = true, reaction = 2,
        health = 50, maxHealth = 100 }
    local p = added("nameplate3")
    local S = DUI.Style
    local r, g, b = S.ReactionColor(2)
    T.rgb(p.name.__textColor, { S.Lighten(r, g, b, stub.nameplates.Plate.NAME_LIGHTEN) }, "an enemy player in hostile red")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: a player of the other faction gets the faction crest by the name", function()
    login()
    local DUI = DaylightUI
    local set = function(k, v) DUI:Set("Nameplates", k, v) end
    stub.units.player.faction = "Horde"
    stub.units.nameplate3 = { name = "Stabitha", isPlayer = true, class = "ROGUE", hostile = true, reaction = 2,
        faction = "Alliance", health = 50, maxHealth = 100 }
    stub.units.nameplate2.faction = "Horde"
    local foe, friend = added("nameplate3"), added("nameplate2")
    T.truthy(foe.factionIcon:IsShown(), "on by default, on the other faction's player")
    T.eq(foe.factionIcon.__atlas, "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", "their faction's crest")
    local _, rel = foe.factionIcon:GetPoint(1)
    T.eq(rel, foe.name, "by the name")
    T.falsy(friend.factionIcon:IsShown(), "none on your own faction")
    -- Not flagged for PvP, the other faction reads friendly, but the crest still says who they are.
    stub.units.nameplate2.faction = "Alliance"
    stub.FireEvent("UNIT_FACTION", "nameplate2"); stub.RunTimers()
    T.truthy(friend.factionIcon:IsShown(), "a friendly plate of the other faction too")
    set("factionIcon", false); stub.RunTimers()
    T.falsy(foe.factionIcon:IsShown() or friend.factionIcon:IsShown(), "switched off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: custom friendly names: players, NPCs and the other faction each in their picked color", function()
    login()
    local DUI = DaylightUI
    local set = function(k, v) DUI:Set("Nameplates", k, v) end
    stub.units.player.faction = "Horde"
    stub.units.nameplate2.faction = "Horde"
    stub.units.nameplate3 = { name = "Rock", reaction = 5, health = 100, maxHealth = 100 }
    stub.units.nameplate4 = { name = "Navani", isPlayer = true, class = "PRIEST", reaction = 4, faction = "Alliance",
        health = 100, maxHealth = 100 }
    local friend, npc, other = added("nameplate2"), added("nameplate3"), added("nameplate4")
    set("friendly.nameColor", "custom")
    set("friendly.namePlayer", { 0.1, 0.2, 0.9 })
    set("friendly.nameNpc", { 0.1, 0.9, 0.2 })
    set("friendly.nameOther", { 0.9, 0.6, 0.1 }); stub.RunTimers()
    T.rgb(friend.name.__textColor, { 0.1, 0.2, 0.9 }, "a friendly player")
    T.rgb(npc.name.__textColor, { 0.1, 0.9, 0.2 }, "a friendly NPC")
    T.rgb(other.name.__textColor, { 0.9, 0.6, 0.1 }, "a player of the other faction")
    -- Your group's own color still wins.
    set("friendly.partyName", true)
    stub.units.nameplate2.party = true
    stub.FireEvent("GROUP_ROSTER_UPDATE"); stub.RunTimers()
    T.rgb(friend.name.__textColor, DUI:Get("Nameplates", "friendly.partyCustom"), "the group color first")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- /dui platefix tries one step per run while plates are invisible. The step
-- that brings them back names the cause.
local function fixWorld(cvars)
    _G.SetCVar = function(k, v) cvars[k] = v end
    _G.GetCVar = function(k) return cvars[k] end
    _G.C_CVar = _G.C_CVar or {}
    C_CVar.GetCVarDefault = function(k) return "default:" .. k end
end

T.test("nameplates: /dui platefix waits for the fight to end", function()
    local NP = login()
    stub.combat = true
    T.truthy(NP.Manager.Fix():find("leave combat", 1, true))
    T.isnil(NP.Manager.fixStep, "no step used up")
    stub.combat = false
end)

T.test("nameplates: /dui platefix step 1 sets the plate size and click area again", function()
    local size
    local NP = login(function()
        C_NamePlate.SetNamePlateSize = function(w, h) size = { w, h } end
    end)
    size = nil
    local text = NP.Manager.Fix()
    T.truthy(size, "the size set again")
    T.truthy(text:find("platefix 1/4", 1, true), text)
end)

T.test("nameplates: /dui platefix step 2 hands every plate back, and takes none until step 3 is done", function()
    local cvars = { nameplateShowEnemies = "1", nameplateShowFriendlyPlayers = "1" }
    local NP = login(function() fixWorld(cvars) end)
    local p = added("nameplate1")
    local uf = plates[1].UnitFrame
    NP.Manager.Fix()
    NP.Manager.Fix()
    T.isnil(NP.Manager.byUnit.nameplate1, "ours off")
    T.falsy(p:IsShown())
    T.eq(uf:GetAlpha(), 1, "the game's own frame seen again")
    T.isnil(added("nameplate2"), "a new plate stays the game's for now")
    NP.Manager.Sync()
    T.isnil(NP.Manager.byUnit.nameplate1, "the 2 s check leaves them too")
    -- 3: off and on again, then ours back.
    local text = NP.Manager.Fix()
    T.truthy(text:find("platefix 3/4", 1, true), text)
    T.eq(cvars.nameplateShowEnemies, "0", "off a moment")
    stub.RunTimers()
    T.eq(cvars.nameplateShowEnemies, "1", "back on")
    T.isnil(cvars.nameplateShowFriendlyNpcs, "a switch it didn't have is left alone")
    T.isnil(NP.Manager.fixPaused, "ours take plates again")
    T.truthy(NP.Manager.byUnit.nameplate1, "ours back on")
end)

T.test("nameplates: /dui platefix step 4 puts our plate settings to the game's defaults, then starts over", function()
    local cvars = {}
    local NP = login(function() fixWorld(cvars) end)
    for _ = 1, 3 do NP.Manager.Fix() end
    stub.RunTimers()
    NP.Manager.Fix()
    T.eq(cvars.nameplateMaxDistance, "default:nameplateMaxDistance")
    T.eq(cvars.nameplateMinScale, "default:nameplateMinScale")
    T.eq(cvars.nameplateShowEnemyMinions, "default:nameplateShowEnemyMinions")
    T.truthy(NP.Manager.Fix():find("every step", 1, true), "the end")
    T.truthy(NP.Manager.Fix():find("platefix 1/4", 1, true), "and round again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: missing health opacity lets the world show through the empty part, the plate's dark inside with it", function()
    login()
    local p = added("nameplate1")
    local S = DaylightUI.Style
    local back = S.BarBack(p.health)
    T.near(back:GetAlpha(), 1, 0.001, "as ever by default")
    T.falsy(p.body.shellMode, "the lean rings by default: no shell, no masks")
    DaylightUI:Set("Nameplates", "backAlpha", 0)
    stub.RunTimers()
    T.near(back:GetAlpha(), 0, 0.001, "the empty part see-through")
    T.truthy(p.body.shellMode, "the shell: stacked rings would fill the inside")
    local sh = S.GetShell(p.hp)
    T.eq(sh.opts.bgAlpha, 0, "the plate's inside see-through")
    T.falsy(p.body.holder:IsShown(), "the rings hidden")
    DaylightUI:Set("Nameplates", "backAlpha", 0.8)
    stub.RunTimers()
    T.near(back:GetAlpha(), 1, 0.001, "back to the usual")
    T.falsy(p.body.shellMode)
    T.truthy(p.body.holder:IsShown(), "the rings back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: target arrows (off by default) point at your target from both sides or over it, and its name can be bigger", function()
    login()
    local p = added("nameplate1")
    local a = p.arrows
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.falsy(a.left:IsShown() or a.right:IsShown() or a.top:IsShown(), "no arrows by default")
    DaylightUI:Set("Nameplates", "targetArrows", "sides")
    stub.RunTimers()
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.truthy(a.left:IsShown() and a.right:IsShown(), "both sides")
    T.falsy(a.top:IsShown())
    T.near(a.left.__rotation, math.pi / 2, 0.001, "the left one turned to point in")
    local _, rel = a.left:GetPoint(1)
    T.eq(rel, p.hp, "beside the bar")
    T.rgb({ a.left:GetVertexColor() }, { DaylightUI.Style.Accent() }, "in the accent")
    DaylightUI:Set("Nameplates", "targetArrowPaint", "custom")
    DaylightUI:Set("Nameplates", "targetArrows", "top")
    stub.RunTimers()
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.truthy(a.top:IsShown(), "over it")
    T.falsy(a.left:IsShown(), "the side ones gone")
    T.rgb({ a.top:GetVertexColor() }, { 0.85, 0.22, 0.20 }, "its own color")
    -- The target's name.
    local before = select(2, p.name:GetFont())
    DaylightUI:Set("Nameplates", "target.nameSize", 22)
    stub.RunTimers()
    T.eq(select(2, p.name:GetFont()), 22, "your target's name bigger (was " .. tostring(before) .. ")")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    stub.RunTimers()
    T.falsy(a.top:IsShown(), "untargeted: gone")
    T.eq(select(2, p.name:GetFont()), before, "the name back to the rest's size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
