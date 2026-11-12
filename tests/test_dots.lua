-- Your DoTs (Dots.lua), learned from your own casts and the UNIT_COMBAT hits on the
-- mob, never from the combat log (closed) or the mob's auras (secret).
local stub = require("stub")

local COR = 172      -- Corruption: 40 Shadow over 12 sec (4 ticks of 10)
local REND = 772     -- Rend: Physical bleed, 25 over 15 sec, 3 sec ticks
local AGONY = 980    -- Bane of Agony: 96 over 24 sec, 2 sec ticks, back-loaded
local RIP = 1079
local CLAW = 1082

local SPELLS = {
    [COR] = { name = "Corruption", desc = "Corrupts the target, causing 40 Shadow damage over 12 sec." },
    [REND] = { name = "Rend", desc = "Wounds the target causing them to bleed for 25 damage over 15 sec." },
    [AGONY] = { name = "Bane of Agony", desc = "Curses the target with agony, causing 96 Shadow damage over 24 sec." },
    [RIP] = { name = "Rip", desc = "Finishing move that causes damage over time.  Damage increases per combo point:\n   1 point : 42 damage over 12 sec.\n   2 points: 66 damage over 12 sec.\n   3 points: 90 damage over 12 sec.\n   4 points: 114 damage over 12 sec.\n   5 points: 138 damage over 12 sec." },
    [CLAW] = { name = "Claw", desc = "Claw the enemy, causing 27 additional damage.  Awards 1 combo point." },
    [686] = { name = "Shadow Bolt", desc = "Sends a shadowy bolt at the enemy, causing 13 to 18 Shadow damage." },
    [139] = { name = "Renew", desc = "Heals the target of 45 damage over 15 sec." },
    [5740] = { name = "Rain of Fire", desc = "Calls down a fiery rain to burn enemies in the area of effect for 240 Fire damage over 8 sec." },
}

local SHADOW, PHYSICAL = 32, 1
local n = 0

local function world()
    local DUI = stub.Load{ before = function()
        stub.units.player = { name = "Me", isPlayer = true, class = "WARLOCK", guid = "Player-1" }
        stub.units.target = { name = "Kobold", reaction = 2, guid = "Creature-1", health = 300, maxHealth = 300 }
        stub.spells = SPELLS
    end }
    DUI.Dots.Want("unitframes", true)
    DUI.Dots.Forget()
    return DUI, DUI.Dots
end

local function cast(id)
    n = n + 1
    local guid = "Cast-" .. n
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", guid, id)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id)
end

local function hit(amount, school, flag, unit)
    stub.FireEvent("UNIT_COMBAT", unit or "target", "WOUND", flag or "", amount, school)
end

local function tick(dt) stub.Advance(dt); stub.RunTickers() end

T.test("dots: the description gives total, school, duration, interval", function()
    local _, Dots = world()
    local total, school, dur = Dots.Parse(SPELLS[COR].desc)
    T.eq(total, 40); T.eq(school, SHADOW); T.eq(dur, 12)
    T.eq((Dots.Parse(SPELLS[RIP].desc, 3)), 90, "a finisher by combo points")
    T.eq((Dots.Parse(SPELLS[RIP].desc, 9)), 138, "points past the table take the top entry")
    T.isnil(Dots.Parse(SPELLS[686].desc), "a direct hit is no DoT")
    T.isnil(Dots.Parse(SPELLS[139].desc), "a heal over time is no DoT")
    T.eq((Dots.Parse("Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec.")), 150)
end)

T.test("dots: a cast shows its whole damage, each tick takes its share off", function()
    local _, Dots = world()
    T.isnil(Dots.Left("target"))
    cast(COR)
    T.eq(Dots.Left("target"), 40)
    tick(3); hit(10, SHADOW)
    T.eq(Dots.Left("target"), 30)
    tick(3); hit(10, SHADOW)
    T.eq(Dots.Left("target"), 20)
end)

T.test("dots: real tick sizes replace the description's and are kept per character", function()
    local DUI, Dots = world()
    cast(COR)
    tick(3); hit(14, SHADOW)
    T.eq(Dots.Left("target"), 42, "3 ticks left at the 14 seen")
    T.isnil(DUI.DB.Character().dots.ticks[COR], "one tick alone isn't kept: it may have been a white hit")
    tick(3); hit(14, SHADOW)
    T.eq(DUI.DB.Character().dots.ticks[COR], 14, "two that agree are")
    Dots.Forget()
    cast(COR)
    T.eq(Dots.Left("target"), 56, "the next cast starts from the learned 14 x 4")
end)

T.test("dots: a white hit off the rhythm is not a tick", function()
    local _, Dots = world()
    cast(REND)                       -- 25 over 15 sec: 5 ticks of 5
    tick(1.5); hit(5, PHYSICAL)      -- a melee swing between ticks
    T.eq(Dots.Left("target"), 25)
    tick(1.5); hit(5, PHYSICAL)      -- the real first tick, on the 3 sec rhythm
    T.eq(Dots.Left("target"), 20)
end)

T.test("dots: another school is never a tick", function()
    local _, Dots = world()
    cast(COR)
    tick(3); hit(10, 4)              -- a Fire hit right on the rhythm
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: a crit tick isn't learned as the normal size", function()
    local DUI, Dots = world()
    cast(COR)
    tick(3); hit(10, SHADOW)
    tick(3); hit(10, SHADOW)
    tick(3); hit(19, SHADOW, "CRITICAL")
    T.eq(Dots.Left("target"), 10)
    T.eq(DUI.DB.Character().dots.ticks[COR], 10)
end)

T.test("dots: a dodge right after the cast takes the DoT back", function()
    local _, Dots = world()
    cast(REND)
    stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, PHYSICAL)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a recast that misses keeps the one still running", function()
    local _, Dots = world()
    cast(COR)
    tick(3); hit(10, SHADOW)
    cast(COR)
    stub.FireEvent("UNIT_COMBAT", "target", "RESIST", "", 0, SHADOW)
    T.eq(Dots.Left("target"), 30)
end)

T.test("dots: a DoT that never ticks is dropped after three missed ticks", function()
    local _, Dots = world()
    cast(COR)
    tick(6.5)
    T.truthy(Dots.Left("target"), "two missed ticks keep it: finding the rhythm takes two")
    tick(3)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: the last tick is waited for even when it lands late, and ends it at once", function()
    local _, Dots = world()
    cast(COR)                        -- 4 ticks of 10, every 3 sec
    for _ = 1, 3 do tick(3); hit(10, SHADOW) end
    tick(3.8)
    T.eq(Dots.Left("target"), 10, "0.8 s past its time, the last tick still counts")
    tick(0.1); hit(10, SHADOW)
    T.isnil(Dots.Left("target"), "it landed: gone with it")
end)

T.test("dots: a last tick that never comes lets go half an interval on", function()
    local _, Dots = world()
    cast(COR)
    for _ = 1, 3 do tick(3); hit(10, SHADOW) end
    tick(4.6)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a tick that passes unseen redraws by the clock", function()
    local DUI, Dots = world()
    cast(COR)
    tick(3); hit(10, SHADOW)
    local fired = 0
    DUI.On("DotsChanged", function() fired = fired + 1 end)
    tick(3.5)                        -- the second tick never arrived
    T.eq(Dots.Left("target"), 20)
    T.truthy(fired > 0, "the shade shrinks with it")
end)

-- As recorded in a fight on Forever: action, flag and school are plain, and the
-- amount of every hit on a mob is secret.
local function wound(school, flag) stub.FireEvent("UNIT_COMBAT", "target", "WOUND", flag or "", stub.Secret(9), school) end

T.test("dots: with secret amounts a tick comes off the moment it lands, by school and time", function()
    local _, Dots = world()
    cast(REND)                       -- 25 over 15 sec: 5 ticks of 5
    for left = 20, 5, -5 do
        tick(3); wound(PHYSICAL)
        T.eq(Dots.Left("target"), left)
    end
    tick(3); wound(PHYSICAL)
    T.isnil(Dots.Left("target"), "gone with the last tick")
end)

T.test("dots: with secret amounts a DoT that keeps ticking is never dropped", function()
    local _, Dots = world()
    cast(COR)
    tick(3); wound(SHADOW)
    tick(3); wound(SHADOW)
    tick(3); wound(SHADOW)
    tick(2.9)
    T.eq(Dots.Left("target"), 10, "the last tick is still to come")
end)

T.test("dots: a blocked or glancing hit is a swing, never a bleed's tick", function()
    local _, Dots = world()
    cast(REND)
    tick(3); wound(PHYSICAL, "BLOCK_REDUCED")
    T.eq(Dots.Left("target"), 25)
    wound(PHYSICAL, "GLANCING")
    T.eq(Dots.Left("target"), 25)
    wound(PHYSICAL)
    T.eq(Dots.Left("target"), 20)
end)

T.test("dots: a swing just before a tick doesn't move the rhythm", function()
    local _, Dots = world()
    cast(REND)
    tick(2.6); wound(PHYSICAL)       -- taken for tick 1, since nothing tells them apart
    tick(0.4); wound(PHYSICAL)       -- the real one, so that slot is spent
    T.eq(Dots.Left("target"), 20)
    tick(3); wound(PHYSICAL)         -- 0.4 s off the swing, right on the DoT's rhythm
    T.eq(Dots.Left("target"), 15)
end)

T.test("dots: a hit of another school with a secret amount is no tick", function()
    local _, Dots = world()
    cast(COR)
    tick(3); wound(4)
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: with secret amounts a projectile DoT counts from its first tick", function()
    local _, Dots = world()
    stub.spells[1978] = { name = "Serpent Sting", desc = "Stings the target, causing 40 Nature damage over 15 sec." }
    cast(1978)                       -- 5 ticks of 8, the first 0.8 s late in flight
    tick(3.8); wound(8)
    T.eq(Dots.Left("target"), 32)
    tick(3); wound(8)
    tick(3); wound(8)
    tick(3); wound(8)
    tick(3); wound(8)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a DoT ends with its last tick", function()
    local _, Dots = world()
    cast(COR)
    for _ = 1, 4 do tick(3); hit(10, SHADOW) end
    tick(1)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: Agony ticks back-loaded (4 at half, 4 at one, 4 at one and a half)", function()
    local _, Dots = world()
    cast(AGONY)                      -- 96 over 24 sec: 12 ticks, average 8, every 2 sec
    T.eq(Dots.Left("target"), 96)
    for _ = 1, 4 do tick(2); hit(4, SHADOW) end
    T.eq(Dots.Left("target"), 80, "the light ticks went first")
end)

T.test("dots: Rip counts the combo points the builders gave", function()
    local _, Dots = world()
    stub.units.player.class = "DRUID"
    cast(CLAW); hit(30, PHYSICAL)
    cast(CLAW); hit(30, PHYSICAL)
    cast(CLAW); hit(30, PHYSICAL)
    cast(RIP)
    T.eq(Dots.Left("target"), 90)
end)

T.test("dots: a builder that's dodged gives no point", function()
    local _, Dots = world()
    cast(CLAW); hit(30, PHYSICAL)
    cast(CLAW); stub.FireEvent("UNIT_COMBAT", "target", "DODGE", "", 0, PHYSICAL)
    stub.Advance(1)                  -- a global cooldown later
    cast(RIP)
    T.eq(Dots.Left("target"), 42, "one point counted")
end)

T.test("dots: a DoT goes on the mob it was sent at", function()
    local _, Dots = world()
    n = n + 1
    local guid = "Cast-" .. n
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", guid, COR)
    stub.units.target = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, COR)
    T.isnil(Dots.Left("target"), "not on the new target")
    stub.units.nameplate1 = { name = "Kobold", reaction = 2, guid = "Creature-1" }
    T.eq(Dots.Left("nameplate1"), 40, "on the mob it was aimed at")
end)

T.test("dots: one hit reported for target and its plate counts once", function()
    local _, Dots = world()
    stub.units.nameplate1 = stub.units.target
    cast(COR)
    tick(3); hit(10, SHADOW, nil, "target"); hit(10, SHADOW, nil, "nameplate1")
    T.eq(Dots.Left("target"), 30)
end)

T.test("dots: skipped spells (area, heals) are never tracked", function()
    local _, Dots = world()
    cast(5740); cast(139); cast(686)
    T.isnil(Dots.Left("target"))
end)

T.test("dots: secret payloads are skipped, never compared", function()
    local _, Dots = world()
    cast(COR)
    stub.Advance(3)
    T.noerror(function()
        stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", stub.Secret(10), stub.Secret(SHADOW))
        stub.FireEvent("UNIT_COMBAT", stub.Secret("target"), stub.Secret("WOUND"), "", 10, SHADOW)
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", stub.Secret("x"), stub.Secret(COR))
    end)
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: a secret target GUID still tracks the target", function()
    local _, Dots = world()
    stub.units.target.guid = stub.Secret("Creature-1")
    cast(COR)
    T.eq(Dots.Left("target"), 40)
end)

T.test("dots: DotsChanged fires on a cast and a tick, the ticker stops with nothing tracked", function()
    local DUI, Dots = world()
    -- Other parts of the core keep tickers of their own (the fade engine's).
    local function live()
        local c = 0
        for _, t in ipairs(stub.tickers) do if not t.cancelled then c = c + 1 end end
        return c
    end
    local before = live()
    local fired = 0
    DUI.On("DotsChanged", function() fired = fired + 1 end)
    cast(COR)
    T.eq(fired, 1)
    T.eq(live(), before + 1, "a ticker while a DoT runs")
    tick(3); hit(10, SHADOW)
    T.eq(fired, 2)
    Dots.Forget()
    T.eq(live(), before, "no ticker of ours left running")
end)

-- Plates redraw only the mob whose DoTs changed (Nameplates' Manager).
T.test("dots: DotsChanged names the one mob that changed", function()
    local DUI, Dots = world()
    local got = {}
    DUI.On("DotsChanged", function(key) got[#got + 1] = key end)
    cast(COR)
    T.eq(got[1], stub.units.target.guid, "a cast: its mob")
    tick(3); hit(10, SHADOW)
    T.eq(got[2], stub.units.target.guid, "a tick: its mob")
    Dots.Forget()
    T.eq(#got, 2, "Forget: every mob (nil key)")
end)

T.test("dots: nothing tracked while nobody wants it", function()
    local _, Dots = world()
    Dots.Want("unitframes", false)
    cast(COR)
    T.isnil(Dots.Left("target"))
    Dots.Want("nameplates", true)
    cast(COR)
    T.eq(Dots.Left("target"), 40)
end)

-- ---------------------------------------------------------------------
-- Drawing (DotsDraw.lua)
-- ---------------------------------------------------------------------

local function bar()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(200, 20)
    local b = CreateFrame("StatusBar", nil, f)
    b:SetAllPoints(f)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    return f, b
end

T.test("dots draw: secret health and max go straight into the bars", function()
    local _, Dots = world()
    local f, b = bar()
    local veil, skull = Dots.NewVeil(b), Dots.NewSkull(f, 16)
    local hp, max = stub.Secret(25), stub.Secret(300)
    stub.units.target.health, stub.units.target.maxHealth = hp, max
    cast(COR)
    T.truthy(Dots.Paint("target", veil, skull))
    T.eq(veil.bar.__max, max); T.eq(veil.bar.__value, 40)
    T.eq(skull.bar.__max, hp); T.eq(skull.bar.__value, 40)
    T.truthy(veil:IsShown()); T.truthy(skull:IsShown())
end)

T.test("dots draw: no DoTs or a dead target shows nothing", function()
    local _, Dots = world()
    local f, b = bar()
    local veil, skull = Dots.NewVeil(b), Dots.NewSkull(f, 16)
    T.falsy(Dots.Paint("target", veil, skull))
    T.falsy(veil:IsShown()); T.falsy(skull:IsShown())
    cast(COR)
    stub.units.target.dead = true
    T.falsy(Dots.Paint("target", veil, skull))
    T.falsy(veil:IsShown())
end)

T.test("dots draw: the veil hangs off the fill's moving edge and grows back into it", function()
    local _, Dots = world()
    local _, b = bar()
    local veil = Dots.NewVeil(b)
    Dots.LayoutVeil(veil, b, false)
    local p, rel, rp = veil.bar:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, b:GetStatusBarTexture()); T.eq(rp, "TOPRIGHT")
    T.truthy(veil.bar:GetReverseFill(), "grows leftward from the fill's right edge")
    Dots.LayoutVeil(veil, b, true)
    p, rel, rp = veil.bar:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rp, "TOPLEFT")
    T.falsy(veil.bar:GetReverseFill())
    T.truthy(veil:DoesClipChildren(), "never past the bar's start when lethal")
end)

T.test("dots draw: an angled fill angles both ends of the veil, and its line leans", function()
    local DUI, Dots = world()
    local _, b = bar()
    DUI.Style.AngleFill(b, "right", 6)
    local veil = Dots.NewVeil(b)
    Dots.LayoutVeil(veil, b, false)
    local masks = veil.bar:GetStatusBarTexture().__masks or {}
    T.eq(#masks, 2, "the fill's edge plus the trail at the damage's end")
    T.eq(masks[1], DUI.Style.GetFillMask(b))
    local off = veil.edge.__vertexOffsets
    T.eq(off[1][1], 6); T.eq(off[3][1], 6)
    -- A square fill: no masks, and the line upright again.
    DUI.Style.AngleFill(b, nil, 0)
    Dots.LayoutVeil(veil, b, false)
    T.eq(#(veil.bar:GetStatusBarTexture().__masks or {}), 0)
    T.eq(veil.edge.__vertexOffsets[1][1], 0)
end)

T.test("dots draw: the skull rides the end of a long bar in a small window", function()
    local _, Dots = world()
    local f = bar()
    local skull = Dots.NewSkull(f, 16)
    T.truthy(skull:DoesClipChildren())
    T.eq(skull.bar:GetWidth(), Dots.SKULL_BAR)
    local p, rel, rp = skull.icon:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, skull.bar:GetStatusBarTexture()); T.eq(rp, "RIGHT")
end)

T.test("dots draw: a sample shows plain numbers, lethal fills the skull", function()
    local _, Dots = world()
    local f, b = bar()
    local veil, skull = Dots.NewVeil(b), Dots.NewSkull(f, 16)
    Dots.PaintSample(veil, skull, 100, 24, true)
    T.eq(veil.bar.__max, 100); T.eq(veil.bar.__value, 24)
    T.eq(skull.bar.__value, 1); T.truthy(skull:IsShown())
    Dots.PaintSample(veil, skull, 100, 24, false)
    T.falsy(skull:IsShown())
end)

-- ---------------------------------------------------------------------
-- Edge cases
-- ---------------------------------------------------------------------

T.test("dots: a secret-GUID target's DoTs don't carry over to the next target", function()
    local _, Dots = world()
    stub.units.target.guid = stub.Secret("Player-A")    -- an enemy player in a battleground
    cast(COR)
    T.eq(Dots.Left("target"), 40)
    stub.units.target = { name = "Bee", reaction = 2, guid = stub.Secret("Player-B"), health = 10, maxHealth = 300 }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.isnil(Dots.Left("target"), "no false veil or skull on the new target")
end)

T.test("dots: a cast with no target is kept nowhere", function()
    local _, Dots = world()
    stub.units.target = nil
    cast(COR)
    stub.units.target = { name = "Bee", reaction = 2, guid = stub.Secret("Player-B"), health = 10, maxHealth = 300 }
    T.isnil(Dots.Left("target"))
end)

T.test("dots: an on-rhythm white hit far bigger than a bleed's tick isn't taken or kept", function()
    local DUI, Dots = world()
    cast(REND)                       -- 5 a tick
    tick(3); hit(60, PHYSICAL)       -- a white hit right on the rhythm
    T.eq(Dots.Left("target"), 25)
    T.isnil(DUI.DB.Character().dots.ticks[REND])
end)

T.test("dots: hits on your group's tokens cost no GUID read", function()
    local _, Dots = world()
    cast(COR)
    local real, reads = UnitGUID, 0
    _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
    for i = 1, 10 do
        stub.FireEvent("UNIT_COMBAT", "raid" .. i, "WOUND", "", 100, PHYSICAL)
        stub.FireEvent("UNIT_COMBAT", "party1", "WOUND", "", 100, PHYSICAL)
        stub.FireEvent("UNIT_COMBAT", "player", "WOUND", "", 100, PHYSICAL)
    end
    _G.UnitGUID = real
    T.eq(reads, 0)
end)

T.test("dots: a mouseover cast goes on the mob it was cast at, not the target", function()
    local _, Dots = world()
    stub.units.mouseover = { name = "Gnoll", reaction = 2, guid = "Creature-2", health = 300, maxHealth = 300 }
    n = n + 1
    local guid = "Cast-" .. n
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "Gnoll", guid, COR)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", guid, COR)
    T.isnil(Dots.Left("target"), "the target (Kobold) has nothing")
    T.eq(Dots.Left("mouseover"), 40)
end)

T.test("dots: hits on mobs aren't read while nothing is cast or tracked", function()
    local _, Dots = world()
    local real, reads = UnitGUID, 0
    local function hits()
        reads = 0
        _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
        for _ = 1, 10 do stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", 100, PHYSICAL) end
        _G.UnitGUID = real
        return reads
    end
    T.eq(hits(), 0, "nothing cast yet")
    cast(COR)
    T.truthy(hits() > 0, "a DoT running hears them")
    tick(3); hit(10, SHADOW); tick(3); hit(10, SHADOW); tick(3); hit(10, SHADOW); tick(3); hit(10, SHADOW)
    tick(1)
    T.isnil(Dots.Left("target"))
    T.eq(hits(), 0, "the DoT ran out: deaf again")
end)

-- A heal, a mount, a direct hit: nothing to learn from the hits after it.
T.test("dots: a cast that's no DoT, finisher or builder hears no hits", function()
    local _, Dots = world()
    local function live()
        local c = 0
        for _, t in ipairs(stub.tickers) do if not t.cancelled then c = c + 1 end end
        return c
    end
    local before = live()
    local real, reads = UnitGUID, 0
    -- Still being cast (sent, not yet succeeded): the hits around it.
    for i, id in ipairs({ 139, 686, 5740 }) do
        stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-other" .. i, id)
    end
    _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
    for _ = 1, 10 do stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", 100, PHYSICAL) end
    _G.UnitGUID = real
    T.eq(reads, 0, "no GUID read for the hits while a heal or a direct hit is cast")
    T.eq(live(), before, "no ticker for them")
    T.isnil(Dots.Left("target"))
end)

T.test("dots: a failed or interrupted cast stops hearing at once", function()
    local _, Dots = world()
    local real, reads = UnitGUID, 0
    for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "Cast-x", COR)
        stub.FireEvent(event, "player", "Cast-x", COR)
        _G.UnitGUID = function(u) reads = reads + 1; return real(u) end
        reads = 0
        for _ = 1, 10 do stub.FireEvent("UNIT_COMBAT", "target", "WOUND", "", 100, PHYSICAL) end
        _G.UnitGUID = real
        T.eq(reads, 0, event .. ": the send is dropped, no hits read")
    end
    T.isnil(Dots.Left("target"))
end)
