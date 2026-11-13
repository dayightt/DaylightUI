local stub = require("stub")

-- Nameplate pieces built on the threat, cast and group answers: plate size by
-- threat, the interrupt-ready mark, execute icons, the group focus mark and the
-- cast's target.

local plates

local function newPlate(i)
    local np = CreateFrame("Frame", "NamePlate" .. i, UIParent)
    np.UnitFrame = CreateFrame("Button", nil, np)
    np.UnitFrame.castBar = CreateFrame("StatusBar", nil, np.UnitFrame)
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
    stub.units = {
        player = { name = "Me", class = "WARRIOR", isPlayer = true },
        nameplate1 = { name = "Searing Whelp", hostile = true, reaction = 2, health = 60, maxHealth = 100, pct = 60 },
        nameplate2 = { name = "Dark Hound", hostile = true, reaction = 2, health = 90, maxHealth = 100, pct = 90 },
    }
end

local function login(before)
    stub.Load({ nameplates = true, before = function()
        world()
        if before then before() end
    end })
    stub.RunTimers()
    return stub.nameplates
end

local function added(unit)
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", unit)
    stub.RunTimers()
    return stub.nameplates.Manager.byUnit[unit]
end

local function threatOn(unit, status, scaled)
    stub.units[unit].threatList = { player = { status = status, scaled = scaled or 0, raw = 0, value = 0 } }
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", unit)
end

T.test("nameplates: plate size by threat is off as shipped and works without threat colors", function()
    local NP = login(function() stub.role = "TANK" end)
    T.eq(NP.DEFAULTS.threatSize, false, "off as shipped")
    local p = added("nameplate1")
    local ui = UIParent:GetEffectiveScale()
    stub.inGroup = true
    threatOn("nameplate1", 0, 40)
    T.near(p:GetScale(), ui, 1e-6, "off: normal size")
    DaylightUI:Set("Nameplates", "threat", false)
    DaylightUI:Set("Nameplates", "threatSize", true)
    stub.RunTimers()
    threatOn("nameplate1", 0, 40)
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6, "a tank who lost it: big")
    threatOn("nameplate1", 2, 100)
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeWarn, 1e-6, "about to lose it")
    threatOn("nameplate1", 3, 100)
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeAggro, 1e-6, "held: small")
    stub.units.nameplate1.threatList = nil
    stub.FireEvent("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    T.near(p:GetScale(), ui, 1e-6, "out of the fight: normal")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: a threat size change is one zoom, never a new layout, and your target keeps its own size", function()
    local NP = login(function() stub.role = "TANK" end)
    DaylightUI:Set("Nameplates", "threatSize", true)
    stub.RunTimers()
    local p = added("nameplate1")
    local ui = UIParent:GetEffectiveScale()
    stub.inGroup = true
    threatOn("nameplate1", 3, 100)
    local laid = p.laid
    local gen = laid.gen
    local layouts = 0
    local real = NP.Body.Layout
    NP.Body.Layout = function(...) layouts = layouts + 1; return real(...) end
    threatOn("nameplate1", 0, 40)
    NP.Body.Layout = real
    T.eq(layouts, 0, "no borders redrawn")
    T.eq(p.laid.gen, gen, "the layout cache kept")
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6)
    -- Your target: its own size wins.
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(p:GetScale(), ui * NP.DEFAULTS.target.scale, 1e-6, "the target's size, not the threat's")
    stub.units.target = nil
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6, "no longer your target: back to its threat size")
    -- Switched off: every plate back to normal.
    DaylightUI:Set("Nameplates", "threatSize", false)
    stub.RunTimers()
    T.near(p:GetScale(), ui, 1e-6, "off: normal")
    stub.inGroup = false
    stub.role = nil
end)

T.test("nameplates: plate size by threat in a boss fight, where the numbers are secret", function()
    local NP = login(function() stub.role = "TANK" end)
    DaylightUI:Set("Nameplates", "threatSize", true)
    stub.RunTimers()
    local p = added("nameplate1")
    local ui = UIParent:GetEffectiveScale()
    stub.inGroup = true
    stub.units.nameplate1.boss = true
    stub.EnterCombat()
    stub.SetRestriction("Encounter", true)
    threatOn("nameplate1", 0, 40)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.near(p:GetScale(), ui * NP.DEFAULTS.threatSizeLost, 1e-6, "the state stays plain: sized")
    stub.SetRestriction("Encounter", false)
    stub.LeaveCombat()
    stub.units.nameplate1.boss = nil
    stub.inGroup = false
    stub.role = nil
end)

-- Your interrupt: Pummel known, berserker stance, its cooldown per test.
local function kicker(cd)
    stub.knownSpells[6552] = true
    _G.GetShapeshiftForm = function() return 3 end
    _G.C_Spell.GetSpellCooldown = function(id)
        return { isActive = cd.on == true, isOnGCD = cd.gcd, isEnabled = true, startTime = 0, duration = 0 }
    end
    _G.C_Spell.GetSpellCooldownDuration = function(id) return cd.d end
end

local function span(from, to, secret)
    local d = C_DurationUtil.CreateDuration()
    if secret then d:SetTimeSpan(stub.Secret(from), stub.Secret(to)) else d:SetTimeSpan(from, to) end
    return d
end

T.test("DUI.Interrupt: your class's interrupt, by rank and stance", function()
    login()
    local I = DaylightUI.Interrupt
    stub.knownSpells = {}
    stub.knownSpells[6552], stub.knownSpells[6554] = true, true
    stub.knownSpells[72] = true
    _G.GetShapeshiftForm = function() return 3 end
    stub.FireEvent("SPELLS_CHANGED")
    T.eq(I.Spell(), 6554, "berserker: the highest Pummel")
    _G.GetShapeshiftForm = function() return 2 end
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM")
    T.eq(I.Spell(), 72, "defensive: Shield Bash")
    _G.GetShapeshiftForm = function() return 1 end
    stub.knownSpells[72] = nil
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM")
    T.isnil(I.Spell(), "battle stance with no Shield Bash: none")
    T.isnil(I.Ready(), "no interrupt: no answer")
    stub.knownSpells = {}
    _G.GetShapeshiftForm = nil
end)

T.test("nameplates: the interrupt mark sits where your interrupt comes back, only while it's on cooldown", function()
    local NP = login()
    local cd = { on = true }
    kicker(cd)
    stub.FireEvent("SPELLS_CHANGED")
    T.eq(NP.DEFAULTS.castKickMark, true, "on as shipped")
    local p = added("nameplate1")
    local now = GetTime()
    cd.d = span(now - 5, now + 1)
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, duration = span(now, now + 3) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    local m = p.cast.kickMark
    T.truthy(m.clip:IsShown(), "on cooldown: the mark shows")
    local lo, hi = m.probe:GetMinMaxValues()
    T.eq(stub.Plain(lo), now, "over the cast's span (the cast's times are always secret)")
    T.eq(stub.Plain(hi), now + 3)
    T.eq(stub.Plain(m.probe:GetValue()), now + 1, "at the moment it's ready")
    T.eq(m.clip:GetNumPoints(), 4, "clipped to the part still to come")
    -- Ready now: no mark.
    cd.on = false
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    stub.RunTimers()
    T.falsy(m.clip:IsShown(), "ready: gone")
    -- Only the global cooldown: ready too.
    cd.on, cd.gcd = true, true
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.falsy(m.clip:IsShown(), "the global cooldown alone: no mark")
    cd.gcd = nil
    -- Off: never.
    DaylightUI:Set("Nameplates", "castKickMark", false)
    stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.falsy(m.clip:IsShown(), "switched off")
    DaylightUI:Set("Nameplates", "castKickMark", true)
    stub.RunTimers()
    -- The cast ends: the mark goes with it.
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.truthy(m.clip:IsShown())
    stub.units.nameplate1.cast = nil
    stub.FireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    stub.RunTimers()
    T.falsy(m.clip:IsShown(), "cast over: gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.knownSpells = {}
end)

T.test("nameplates: the interrupt mark in a boss fight, every time secret, is placed without touching them", function()
    login()
    local cd = { on = true }
    kicker(cd)
    stub.FireEvent("SPELLS_CHANGED")
    local p = added("nameplate1")
    stub.EnterCombat()
    stub.SetRestriction("Encounter", true)
    local now = GetTime()
    cd.d = span(now - 5, now + 1, true)
    stub.units.nameplate1.cast = { name = "Fireball", texture = 1, duration = span(now, now + 3, true) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local m = p.cast.kickMark
    T.truthy(m.clip:IsShown(), "shown")
    T.eq(stub.Plain(m.probe:GetValue()), now + 1, "the secret end time went in whole")
    -- Channels drain: the mark comes from the far end.
    stub.units.nameplate1.cast = nil
    stub.units.nameplate1.channel = { name = "Drain Life", texture = 1, duration = span(now, now + 3, true) }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "nameplate1")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(m.probe:GetReverseFill(), "a channel's mark counts from the other end")
    stub.units.nameplate1.channel = nil
    stub.SetRestriction("Encounter", false)
    stub.LeaveCombat()
    stub.knownSpells = {}
end)

-- As in the client, the execute curve is evaluated inside the game and the answer
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

T.test("nameplates: execute range on Your class for a priest once Shadow Word: Death is known", function()
    login(function() stub.units.player.class = "PRIEST" end)
    stub.knownSpells = {}
    DaylightUI:Set("Nameplates", "execute", "auto")
    stub.RunTimers()
    local p = added("nameplate1")
    T.falsy(p.exec:IsShown(), "no Shadow Word: Death: nothing")
    stub.knownSpells[32379] = true
    stub.FireEvent("SPELLS_CHANGED")
    stub.RunTimers()
    T.truthy(p.exec:IsShown(), "learned: shown")
    T.eq(stub.nameplates.Plate.ExecuteSpell(), 32379)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("nameplates: the execute range as your finisher's icon by the bar, lit only in range", function()
    withExecuteCurves(function(alpha)
        local NP = login()
        stub.knownSpells = {}
        stub.knownSpells[20660] = true
        local asked
        _G.C_Spell.GetSpellTexture = function(id) asked = id; return 1000 + id end
        DaylightUI:Set("Nameplates", "execute", "auto")
        DaylightUI:Set("Nameplates", "executeStyle", "icon")
        stub.RunTimers()
        local p = added("nameplate1")
        local f, e = p.execIcon, p.exec
        T.truthy(f:IsShown(), "the icon is there")
        T.eq(asked, 20660, "the rank you know")
        T.eq(f.icon:GetTexture(), 21660)
        T.eq(e.hotTex, f, "the icon is what lights")
        T.falsy(e.band:IsShown(), "no band")
        T.falsy(e.lit:IsShown(), "nothing else lights")
        T.truthy(e.line:IsShown(), "the line stays")
        T.eq(alpha(f), 0, "at 60%: unseen")
        stub.units.nameplate1.health = stub.Secret(15)
        stub.FireEvent("UNIT_HEALTH", "nameplate1")
        T.eq(alpha(f), 1, "at 15%: seen")
        -- It sits past the bar's end like the skull, which goes past it.
        local point, rel = f:GetPoint(1)
        T.eq(rel, p.hp, "beside the bar")
        T.eq(select(2, p.dotSkull:GetPoint(1)), f, "the DoT skull past it")
        DaylightUI:Set("Nameplates", "executeStyle", "band")
        stub.RunTimers()
        T.falsy(f:IsShown(), "another style: gone")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        stub.knownSpells = {}
    end)
end)

T.test("nameplates: the group focus mark goes over the enemy most of your party targets, counted after a burst", function()
    local NP = login()
    T.eq(NP.DEFAULTS.groupFocus, false, "off as shipped")
    DaylightUI:Set("Nameplates", "groupFocus", true)
    stub.RunTimers()
    local a, b = added("nameplate1"), added("nameplate2")
    stub.units.nameplate1.guid = "Creature-1"
    stub.units.nameplate2.guid = "Creature-2"
    stub.SetGroup(true)
    stub.units.party1 = { name = "Ann", isPlayer = true, class = "MAGE" }
    stub.units.party2 = { name = "Bo", isPlayer = true, class = "ROGUE" }
    stub.units.party1target = stub.units.nameplate2
    stub.units.party2target = stub.units.nameplate2
    stub.units.target = stub.units.nameplate1
    stub.FireEvent("UNIT_TARGET", "party1")
    stub.FireEvent("UNIT_TARGET", "party2")
    T.falsy(b.focusOn, "nothing at once: counted after the burst")
    stub.RunTimers()
    T.truthy(b.focusOn, "two on the hound: marked")
    T.falsy(a.focusOn, "your own target alone: no")
    T.truthy(b.focusMark[1]:IsShown())
    local r = b.focusMark[1]:GetVertexColor()
    T.near(r, (DaylightUI.Style.Accent()), 1e-6, "in the accent")
    -- A tie marks nothing.
    stub.units.party2target = stub.units.nameplate1
    stub.FireEvent("UNIT_TARGET", "party2")
    stub.RunTimers()
    T.truthy(a.focusOn, "you and Bo on the whelp: it")
    T.falsy(b.focusOn)
    stub.units.party3 = { name = "Cy", isPlayer = true, class = "PRIEST" }
    stub.units.party3target = stub.units.nameplate2
    stub.FireEvent("UNIT_TARGET", "party3")
    stub.RunTimers()
    T.falsy(a.focusOn, "two and two: no mark")
    T.falsy(b.focusOn)
    -- A mob changing its target doesn't count anything.
    local queued = 0
    local real = NP.Manager.CountFocus
    NP.Manager.CountFocus = function() queued = queued + 1; return real() end
    stub.FireEvent("UNIT_TARGET", "nameplate1")
    stub.RunTimers()
    T.eq(queued, 0, "a plate's own target change: ignored")
    NP.Manager.CountFocus = real
    -- Solo, or switched off: none.
    stub.units.party3target = stub.units.nameplate1
    stub.FireEvent("UNIT_TARGET", "party3")
    stub.RunTimers()
    T.truthy(a.focusOn)
    DaylightUI:Set("Nameplates", "groupFocus", false)
    stub.RunTimers()
    T.falsy(a.focusOn, "off: gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.SetGroup(false)
    for _, k in ipairs({ "party1", "party2", "party3", "party1target", "party2target", "party3target", "target" }) do stub.units[k] = nil end
end)

T.test("nameplates: no group focus mark in a battleground, where who's who is secret", function()
    login()
    DaylightUI:Set("Nameplates", "groupFocus", true)
    stub.RunTimers()
    local a = added("nameplate1")
    stub.units.nameplate1.guid = "Creature-1"
    stub.SetGroup(true)
    stub.units.party1 = { name = "Ann", isPlayer = true, class = "MAGE" }
    stub.units.party1target = stub.units.nameplate1
    stub.units.target = stub.units.nameplate1
    stub.SetRestriction("PvPMatch", true)
    stub.FireEvent("UNIT_TARGET", "party1")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.falsy(a.focusOn, "secret GUIDs match nothing")
    stub.SetRestriction("PvPMatch", false)
    stub.FireEvent("UNIT_TARGET", "party1")
    stub.RunTimers()
    T.truthy(a.focusOn, "out of it: marked")
    stub.SetGroup(false)
    stub.units.party1, stub.units.party1target, stub.units.target = nil, nil, nil
end)

T.test("nameplates: the cast bar names who the cast is aimed at, in their class color, secret names and all", function()
    local NP = login()
    T.eq(NP.DEFAULTS.castTarget, true, "on as shipped")
    -- The client always answers these secret.
    local aimed = { name = "Jaina", class = "MAGE" }
    _G.UnitSpellTargetName = function() if aimed.name then return stub.Secret(aimed.name) end end
    _G.UnitSpellTargetClass = function() if aimed.class then return stub.Secret(aimed.class) end end
    local realColor = _G.C_ClassColor
    _G.C_ClassColor = { GetClassColor = function(cls)
        if stub.Plain(cls) == "MAGE" then return { r = stub.Secret(0.25), g = stub.Secret(0.78), b = stub.Secret(0.92) } end
    end }
    local p = added("nameplate1")
    stub.EnterCombat()
    stub.units.nameplate1.cast = { name = "Frostbolt", texture = 1, duration = stub.Duration(2) }
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local fs = p.cast.target
    T.truthy(fs:IsShown())
    T.eq(stub.Text(fs), "Jaina", "the secret name, written whole")
    local r, g = fs:GetTextColor()
    while type(g) == "table" do g = stub.Plain(g) end -- a secret color reads back secret
    T.near(g, 0.78, 1e-6, "in the game's class color")
    -- An NPC or no target: white, or empty.
    aimed.class = nil
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    local w = fs:GetTextColor()
    while type(w) == "table" do w = stub.Plain(w) end
    T.near(w, DaylightUI.Style.INK.VALUE[1], 1e-6, "no class: white")
    aimed.name = nil
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.eq(stub.Text(fs), "", "an area spell: nothing")
    -- Off (settings apply after the fight): hidden, the spell name reaching the time again.
    stub.LeaveCombat()
    DaylightUI:Set("Nameplates", "castTarget", false)
    stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_START", "nameplate1")
    T.falsy(fs:IsShown(), "switched off")
    T.eq(select(2, p.cast.text:GetPoint(2)), p.cast.time, "the spell name runs to the time")
    _G.UnitSpellTargetName, _G.UnitSpellTargetClass, _G.C_ClassColor = nil, nil, realColor
    stub.units.nameplate1.cast = nil
end)
