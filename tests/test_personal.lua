local stub = require("stub")

-- The personal display (Personal.lua): your bars just under your character.
-- This client has no player nameplate, so the spot comes from the camera zoom,
-- eased to each new spot and idle while the camera holds still.

local function login(class, token, on)
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.cameraZoom, stub.race, stub.formID, stub.mounted = nil, nil, nil, nil
        stub.units.player = { name = "Stabby", isPlayer = true, class = class or "WARRIOR", powerToken = token or "RAGE",
                              health = 60, maxHealth = 100, power = 20, maxPower = 100 }
    end })
    if on ~= false then DUI:Set("UnitFrames", "personal.enabled", true) end
    return DUI, ns, ns.Personal
end

local function frames(PR, n)
    for _ = 1, n or 60 do
        if PR.follow:IsShown() then stub.RunOnUpdate(PR.follow, 1 / 60) end
    end
end

local function topY(PR)
    local p, rel, rp, x, y = PR.frame:GetPoint(1)
    T.eq(p, "TOP"); T.eq(rel, UIParent); T.eq(rp, "CENTER")
    return y, x
end

-- Where the display's top should sit for a zoom: a human's drop under the
-- middle, plus the default vertical offset.
local Y = -35
local function expected(PR, zoom, k)
    local H = UIParent:GetHeight()
    return -PR.FEET * (k or 1) * H / (zoom * PR.VIEW) + Y
end

T.test("off by default: nothing shown, no combo row, nothing running", function()
    local _, ns, PR = login("ROGUE", "ENERGY", false)
    T.falsy(PR.frame:IsShown())
    T.isnil(PR.frame.combo, "its combo row is made only once it's on")
    T.falsy(PR.frame.poll:IsShown())
    frames(PR)
    T.falsy(PR.follow:IsShown(), "the follow rests")
    T.truthy(ns.combo, "the target's own combo row is still there")
end)

T.test("on: your health and power, under the middle of the screen", function()
    local _, _, PR = login()
    local h = PR.frame
    T.truthy(h:IsShown())
    T.eq(stub.Plain(h.healthBar.__value), 60)
    T.eq(stub.Plain(h.powerBar.__value), 20)
    frames(PR)
    T.near(topY(PR), expected(PR, 15), 0.5, "at the default zoom, the human's drop under the middle")
    T.falsy(PR.follow:IsShown(), "and the follow rests once there")
end)

T.test("zooming in eases it down toward your feet, then rests", function()
    local _, _, PR = login()
    frames(PR)
    local before = topY(PR)
    stub.cameraZoom = 5
    MoveViewInStart(1.0, 0, true)
    T.truthy(PR.follow:IsShown(), "the zoom key (and mouse wheel) wakes the follow")
    stub.RunOnUpdate(PR.follow, 1 / 60)
    local mid = topY(PR)
    T.truthy(mid < before and mid > expected(PR, 5), "one frame in, it's on its way, not there yet")
    frames(PR, 120)
    T.near(topY(PR), expected(PR, 5), 0.5, "closer camera, bigger drop")
    T.falsy(PR.follow:IsShown())
end)

T.test("never past the bottom of the screen in first person", function()
    local _, _, PR = login()
    stub.cameraZoom = 0
    CameraZoomIn(1)
    frames(PR, 200)
    local H = UIParent:GetHeight()
    T.near(topY(PR), -H * (0.5 - PR.EDGE) + Y, 0.5)
end)

T.test("up / down is the only height setting: the same few pixels at every zoom", function()
    local _, ns, PR = login()
    for _, zoom in ipairs({ 5, 15, 28 }) do
        local _, plain = PR.Spot(zoom, { y = 0 })
        local _, raised = PR.Spot(zoom, { y = 30 })
        T.near(raised - plain, 30, 1e-6, "a flat shift, whatever the camera")
    end
    local _, plain = PR.Spot(15, { y = 0 })
    local _, old = PR.Spot(15, { y = 0, reach = 195 })
    T.near(old, plain, 1e-6, "a saved old distance does nothing")
    T.isnil(ns.DEFAULTS and ns.DEFAULTS.personal and ns.DEFAULTS.personal.reach)
end)

T.test("one body: health over power in a single shell, angled on the right, rogues' pips following", function()
    local DUI, _, PR = login("ROGUE", "ENERGY")
    local h = PR.frame
    T.eq(h.healthBar:GetParent(), h.body)
    T.eq(h.powerBar:GetParent(), h.body, "no second box for the power")
    DUI:Set("UnitFrames", "personal.showPower", false)
    T.falsy(h.body.separator:IsShown(), "no power, no line")
    DUI:Set("UnitFrames", "personal.showPower", true)
    T.eq(h.cutSide, "right")
    T.truthy(h.cut > 0, "angled by default")
    local c = h.combo
    T.truthy(c, "a rogue has its combo row")
    local p, _, _, x = c:GetPoint(1)
    T.eq(p, "TOPRIGHT", "the row starts from the angled end")
    T.truthy(x < 0, "and clear of it")
    DUI:Set("UnitFrames", "personal.slant", false)
    T.eq(h.cut, 0, "angled ends off: square")
end)

T.test("buffs and debuffs: off and unmade until asked, then on the display", function()
    local DUI, ns, PR = login()
    T.isnil(PR.auras, "nothing made while off")
    DUI:Set("UnitFrames", "personal.auras.buffs", true)
    stub.RunTimers()
    T.truthy(PR.auras, "made the first time a row is on")
    T.eq(PR.auras.buffs:GetParent(), PR.frame, "they fade with the display")
    T.truthy(PR.auras ~= ns.playerAuras, "its own rows, not the player frame's")
    local _, rel = PR.auras.buffs:GetPoint(1)
    T.eq(rel, PR.frame)
end)

T.test("a row under the bars clears the combo row and what's docked", function()
    local DUI, _, PR = login("ROGUE", "ENERGY")
    DUI:Set("UnitFrames", "personal.auras.buffs", true)
    DUI:Set("UnitFrames", "personal.auras.buffSpot", "below")
    stub.RunTimers()
    local bare = PR.auras.buffDrop
    T.truthy(bare > 0, "past the combo row")
    DUI:Set("UnitFrames", "personal.castbar", true)
    stub.RunTimers()
    T.truthy(PR.auras.buffDrop > bare, "and past the cast bar")
end)

T.test("the cast bar and swing bars stand under it, then go back", function()
    local DUI, ns, PR = login()
    local h, cast, swing = PR.frame, ns.playerCastbar, ns.swing
    T.truthy(swing, "the fake game's warrior has swing bars")
    DUI:Set("UnitFrames", "swing.enabled", true)
    DUI:Set("UnitFrames", "personal.swing", true)
    DUI:Set("UnitFrames", "personal.castbar", true)
    stub.RunTimers()
    T.eq(ns.CastBar.At("player", ns.module.db.playerCastbar), "personal")
    local p, rel, rp, _, y = cast:GetPoint(1)
    T.eq(p, "TOP"); T.eq(rel, h); T.eq(rp, "TOP")
    local _, srel, _, _, sy = swing:GetPoint(1)
    T.eq(srel, h)
    T.truthy(sy > y, "swing bars first, so a cast never moves them")
    T.near(cast:GetWidth(), h:GetWidth(), 1, "as wide as the display")
    T.near(swing:GetWidth(), h:GetWidth(), 1)
    T.truthy(DUI.Movers.Get("unitframes.swing").suspended, "no second handle")
    T.truthy(DUI.Movers.Get("unitframes.playerCastbar").suspended)
    DUI:Set("UnitFrames", "personal.swing", false)
    DUI:Set("UnitFrames", "personal.castbar", false)
    stub.RunTimers()
    T.eq(ns.CastBar.At("player", ns.module.db.playerCastbar), "below", "back under the player frame")
    local _, back = cast:GetPoint(1)
    T.truthy(back ~= h)
end)

T.test("test mode wakes the display, with its rows", function()
    local DUI, _, PR = login()
    DUI:Set("UnitFrames", "personal.auras.buffs", true)
    stub.RunTimers()
    DUI.SetTestMode(true)
    for _ = 1, 20 do stub.Advance(0.1); DUI.Fade.Step(); DUI.Fade.Animate(0.1) end
    T.truthy(PR.frame:GetAlpha() > 0.9, "seen while you set it up")
    DUI.SetTestMode(false)
end)

T.test("a cast shades its cost on the power bar, by the Player page's switch", function()
    local DUI, _, PR = login()
    local body = PR.frame.body
    local kind = UnitPowerType("player")
    stub.spellCosts = { [123] = { { type = kind, name = "RAGE", cost = 15 } } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.truthy(body.cost:IsShown(), "the shade shows")
    T.eq(stub.Plain(body.cost.__value), 15)
    T.eq(body.costHolder:GetParent(), body, "fades with the display")
    stub.FireEvent("UNIT_SPELLCAST_STOP", "player", "guid", 123)
    T.falsy(body.cost:IsShown(), "gone when the cast ends")
    DUI:Set("UnitFrames", "player.costPreview", false)
    stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.falsy(body.cost:IsShown(), "off on the Player page, off here")
    DUI:Set("UnitFrames", "player.costPreview", true)
    DUI:Set("UnitFrames", "personal.showPower", false)
    stub.RunTimers()
    stub.FireEvent("UNIT_SPELLCAST_START", "player", "guid", 123)
    T.falsy(body.cost:IsShown(), "no power bar, no shade")
    stub.spellCosts = nil
end)

T.test("health bar off: just the power bar in the shell, no health work", function()
    local DUI, _, PR = login("MAGE", "MANA")
    local h, body = PR.frame, PR.frame.body
    local both = h:GetHeight()
    DUI:Set("UnitFrames", "personal.showPercent", true)
    T.truthy(h.healthText:IsShown())
    T.truthy(body.heals:IsShown())
    DUI:Set("UnitFrames", "personal.showHealth", false)
    T.falsy(h.healthBar:IsShown(), "no health bar")
    T.falsy(h.healthText:IsShown(), "no health bar, no health text")
    T.falsy(body.separator:IsShown(), "no line with one bar")
    T.falsy(body.heals:IsShown(), "no heal bars over nothing")
    T.falsy(body.absorbs:IsShown())
    T.falsy(body.overshield:IsShown())
    T.truthy(h.powerBar:IsShown(), "the power bar stays")
    T.truthy(h:GetHeight() < both, "the shell shrinks to it")

    -- Health events no longer reach it, and the power keeps moving.
    stub.units.player.health = 40
    local value = h.healthBar.__value
    stub.FireEvent("UNIT_HEALTH", "player")
    T.eq(h.healthBar.__value, value)
    stub.units.player.power = 35
    PR.UpdatePower(true)
    T.eq(stub.Plain(h.powerBar.__value), 35)

    DUI:Set("UnitFrames", "personal.showHealth", true)
    T.truthy(h.healthBar:IsShown(), "back on")
    T.eq(stub.Plain(h.healthBar.__value), 40, "at your health now, not where it stopped")
    T.truthy(h.healthText:IsShown())
    T.truthy(body.separator:IsShown())
    T.eq(h:GetHeight(), both)
end)

T.test("health bar off from the start: no heal bars made, and both off keeps health", function()
    local DUI, _, PR = login("MAGE", "MANA", false)
    DUI:Set("UnitFrames", "personal.showHealth", false)
    DUI:Set("UnitFrames", "personal.enabled", true)
    local h = PR.frame
    T.isnil(h.body.heals, "nothing made for a bar that isn't there")
    stub.FireEvent("UNIT_HEAL_PREDICTION", "player")
    DUI:Set("UnitFrames", "personal.showPower", false)
    T.truthy(h.healthBar:IsShown(), "never an empty shell")
end)

T.test("no cost shade is made while the display is off", function()
    local _, _, PR = login(nil, nil, false)
    T.isnil(PR.frame.body.cost)
end)

T.test("the display off: everything stays where it was", function()
    local DUI, ns = login(nil, nil, false)
    DUI:Set("UnitFrames", "personal.castbar", true)
    DUI:Set("UnitFrames", "personal.swing", true)
    stub.RunTimers()
    T.eq(ns.CastBar.At("player", ns.module.db.playerCastbar), "below")
    T.falsy(ns.swing.docked)
end)

T.test("a mount or a bigger race drops it further, a form shrinks it", function()
    local _, _, PR = login()
    stub.mounted = true
    stub.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    frames(PR, 200)
    T.near(topY(PR), expected(PR, 15, PR.MOUNTED), 0.5)
    stub.mounted, stub.race = nil, "Gnome"
    stub.FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    frames(PR, 200)
    T.near(topY(PR), expected(PR, 15, PR.RACE.Gnome), 0.5)
    stub.race, stub.formID = nil, 1
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM")
    frames(PR, 200)
    T.near(topY(PR), expected(PR, 15, PR.FORM[1]), 0.5, "cat form")
    stub.formID = nil
end)

T.test("a secret race keeps the last plain one", function()
    local _, _, PR = login()
    stub.race = "Tauren"
    T.near(PR.Size(), PR.RACE.Tauren, 1e-6)
    local real = UnitRace
    _G.UnitRace = function() return stub.Secret("Gnome"), stub.Secret("Gnome"), 1 end
    T.near(PR.Size(), PR.RACE.Tauren, 1e-6, "no table lookup with a secret")
    _G.UnitRace, stub.race = real, nil
end)

T.test("no camera reading: a fixed spot under the middle", function()
    local _, _, PR = login()
    local real = GetCameraZoom
    _G.GetCameraZoom = nil
    CameraZoomIn(1)
    frames(PR, 200)
    T.near(topY(PR), -UIParent:GetHeight() * PR.NO_CAMERA + Y, 0.5)
    _G.GetCameraZoom = real
end)

T.test("where you put it: the mover places it, nothing follows", function()
    local DUI, _, PR = login()
    DUI:Set("UnitFrames", "personal.follow", "fixed")
    T.falsy(DUI.Movers.Get(PR.KEY).suspended)
    CameraZoomIn(1)
    T.falsy(PR.follow:IsShown())
    DUI:Set("UnitFrames", "personal.follow", "feet")
    T.truthy(DUI.Movers.Get(PR.KEY).suspended, "at your feet: the mover steps aside")
end)

T.test("power is polled while it moves, then rests", function()
    local DUI, _, PR = login()
    local h = PR.frame
    -- Shown in a fight. Out of combat with no target it fades away.
    stub.combat = true
    for _ = 1, 4 do stub.Advance(0.1); DUI.Fade.Step(); DUI.Fade.Animate(0.1) end
    stub.combat = false
    stub.units.player.power = 30
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
    T.truthy(h.poll:IsShown())
    stub.RunOnUpdate(h.poll, 0.06)
    T.eq(stub.Plain(h.powerBar.__value), 30)
    stub.units.player.power = 35
    stub.RunOnUpdate(h.poll, 0.06)
    T.eq(stub.Plain(h.powerBar.__value), 35, "between the game's events too")
    stub.Advance(PR.POWER_REST + 0.1)
    stub.RunOnUpdate(h.poll, 0.06)
    T.falsy(h.poll:IsShown(), "a second without change: the poll rests")
end)

T.test("rogues get combo points under the bars", function()
    local _, _, PR = login("ROGUE", "ENERGY")
    local c = PR.frame.combo
    T.truthy(c)
    local p, rel, rp = c:GetPoint(1)
    T.eq(rel, PR.frame); T.eq(rp, "BOTTOMRIGHT")
    stub.comboPoints = 4
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    T.eq(c.pips[1].bar.__value, 4)
    stub.comboPoints = nil
end)

T.test("the personal combo row takes its own size and nudges", function()
    local DUI, _, PR = login("ROGUE", "ENERGY")
    local c, h = PR.frame.combo, PR.frame
    local reach = h.comboReach
    T.truthy(c.pips[1]:GetWidth() > DUI:Get("UnitFrames", "personal.comboSize"), "as wide as the display by default")
    DUI:Set("UnitFrames", "personal.comboStretch", false)
    DUI:Set("UnitFrames", "personal.comboSize", 22)
    DUI:Set("UnitFrames", "personal.comboHeight", 9)
    stub.RunTimers()
    T.near(c.pips[1]:GetWidth(), 22, 0.5, "its own pip width")
    T.near(c.pips[1]:GetHeight(), 9, 0.5, "and height")
    T.eq(DUI:Get("UnitFrames", "combo.size"), 14, "the target's pips keep theirs")
    local _, _, _, x0, y0 = c:GetPoint(1)
    DUI:Set("UnitFrames", "personal.comboX", 12)
    DUI:Set("UnitFrames", "personal.comboY", -6)
    stub.RunTimers()
    local _, _, _, x1, y1 = c:GetPoint(1)
    T.near(x1 - x0, 12, 0.01, "nudged sideways")
    T.near(y1 - y0, -6, 0.01, "and down")
    T.truthy(h.comboReach > reach, "what's docked under it moves down past it")
end)

T.test("hidden while dead, back when alive", function()
    local _, _, PR = login()
    stub.units.player.dead = true
    stub.FireEvent("PLAYER_DEAD")
    T.falsy(PR.frame:IsShown())
    stub.units.player.dead = nil
    stub.FireEvent("PLAYER_ALIVE")
    T.truthy(PR.frame:IsShown())
end)

T.test("test mode shows sample values, then your own again", function()
    local DUI, _, PR = login()
    DUI.SetTestMode(true)
    T.truthy(PR.frame.test)
    T.eq(PR.frame.healthBar.__value, PR.SAMPLE.health)
    DUI.SetTestMode(false)
    T.falsy(PR.frame.test)
    T.eq(stub.Plain(PR.frame.healthBar.__value), 60)
end)

T.test("off: it listens to nothing and nothing follows the camera", function()
    local DUI, _, PR = login(nil, nil, false)
    local h = PR.frame
    T.falsy(h:IsEventRegistered("UNIT_HEALTH"), "no health events for a display that's off")
    T.falsy(h:IsEventRegistered("UNIT_POWER_FREQUENT"))
    CameraZoomIn(1)
    T.falsy(PR.follow:IsShown(), "a zoom wakes nothing")
    DUI:Set("UnitFrames", "personal.enabled", true)
    T.truthy(h:IsEventRegistered("UNIT_HEALTH"), "on: it listens")
    CameraZoomIn(1)
    T.truthy(PR.follow:IsShown(), "and follows")
    DUI:Set("UnitFrames", "personal.enabled", false)
    T.falsy(h:IsEventRegistered("UNIT_HEALTH"), "off again: quiet again")
    T.falsy(PR.follow:IsShown())
end)

T.test("gradient health color follows your health", function()
    local DUI, _, PR = login()
    DUI:Set("UnitFrames", "colors.health", "gradient")
    local real, painted = DUI.Health.ApplyGradient, false
    DUI.Health.ApplyGradient = function(bar, u)
        if bar == PR.frame.healthBar then painted = true end
        return real(bar, u)
    end
    stub.units.player.health = 30
    stub.FireEvent("UNIT_HEALTH", "player")
    DUI.Health.ApplyGradient = real
    T.truthy(painted, "repainted along its gradient on each health change")
end)

T.test("faded away: the power poll rests until it shows again", function()
    local DUI, _, PR = login()
    local h = PR.frame
    for _ = 1, 40 do stub.Advance(0.25); DUI.Fade.Step(); DUI.Fade.Animate(0.25) end
    T.eq(DUI.Fade.State(PR.FADE), 0, "out of a fight with no target: faded")
    h.poll:Hide()
    stub.FireEvent("UNIT_POWER_FREQUENT", "player", "RAGE")
    T.falsy(h.poll:IsShown(), "nothing to see, nothing polled")
    stub.combat = true
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    for _ = 1, 4 do stub.Advance(0.1); DUI.Fade.Step(); DUI.Fade.Animate(0.1) end
    stub.combat = false
    T.truthy(DUI.Fade.State(PR.FADE) > 0, "a fight shows it")
    T.truthy(h.poll:IsShown(), "and the poll runs again at once")
end)

-- The five second rule sweep (PowerBar.lua). A finished cast that costs mana
-- runs a light over the mana bar on the player frame and the display. Mana is
-- secret in a fight, so only the cast and the spell's cost are read.
local function sweepLogin(look, class, token)
    local DUI, ns, PR = login(class or "MAGE", token or "MANA")
    if look then DUI:Set("UnitFrames", "player.regenSweep", look) end
    stub.RunTimers()
    stub.spellCosts = { [10] = { { type = 0, name = "MANA", cost = 50 } },
                        [11] = { { type = 0, name = "MANA", cost = 0 } },
                        [12] = { { type = 3, name = "ENERGY", cost = 40 } } }
    ns.PowerBar.RegenStop()   -- picking a look plays one sweep to show it
    return DUI, ns, PR, ns.PowerBar.regen.sweeps
end

local function cast(id) stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id) end

T.test("mana sweep: off by default, nothing made, no event listened to", function()
    local _, ns, PR, Sweeps = sweepLogin()
    T.eq(ns.module.db.player.regenSweep, "off")
    T.isnil(Sweeps[PR.frame.powerBar], "made the first time a look is picked")
    T.isnil(Sweeps[ns.frames.player.power])
    T.falsy(ns.PowerBar.regen.listening, "off, it costs nothing")
    stub.spellCosts = nil
end)

T.test("mana sweep: a cast that costs mana runs it on both bars, for five seconds", function()
    local _, ns, PR, Sweeps = sweepLogin("spark")
    local player, personal = Sweeps[ns.frames.player.power], Sweeps[PR.frame.powerBar]
    T.truthy(player and personal, "one on each bar")
    T.falsy(player.holder:IsShown(), "nothing up before a cast")
    cast(10)
    T.truthy(player.holder:IsShown())
    T.truthy(personal.holder:IsShown())
    local t = player.timer.__timer
    T.truthy(t and t[1], "the client runs the bar, no Lua each frame")
    T.eq(t[2], Enum.StatusBarInterpolation.Immediate)
    T.eq(t[3], Enum.StatusBarTimerDirection.ElapsedTime)
    T.eq(t[1].e - t[1].s, ns.PowerBar.REGEN_WINDOW)
    stub.spellCosts = nil
end)

T.test("mana sweep: free spells, other powers and a plain 0 don't start it", function()
    local _, ns, _, Sweeps = sweepLogin("trail")
    local s = Sweeps[ns.frames.player.power]
    cast(11); T.falsy(s.holder:IsShown(), "cost 0 is free")
    cast(12); T.falsy(s.holder:IsShown(), "energy isn't mana")
    cast(99); T.falsy(s.holder:IsShown(), "no cost at all")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 10)
    T.falsy(s.holder:IsShown(), "someone else's cast")
    stub.spellCosts = nil
end)

T.test("mana sweep: a secret cost still counts, and is never compared", function()
    local _, ns, _, Sweeps = sweepLogin("spark")
    stub.spellCosts[10][1].cost = stub.Secret(50)
    cast(10)
    T.truthy(Sweeps[ns.frames.player.power].holder:IsShown())
    stub.spellCosts = nil
end)

T.test("mana sweep: a new cast restarts it, and the old one's end does nothing", function()
    local _, ns, _, Sweeps = sweepLogin("spark")
    local s = Sweeps[ns.frames.player.power]
    cast(10)
    local first = s.timer.__timer[1].s
    stub.Advance(3)
    cast(10)
    T.truthy(s.timer.__timer[1].s > first, "starts again from now")
    local regen = ns.PowerBar.regen
    T.truthy(regen.ends, "still running after the restart")
    stub.RunTimers()   -- both casts' ends come due, only the last one counts
    T.isnil(regen.ends, "the sweep's end stops it")
    stub.spellCosts = nil
end)

T.test("mana sweep: hides in a form, and joins the running sweep back on mana", function()
    local _, ns, _, Sweeps = sweepLogin("spark", "DRUID", "MANA")
    local s = Sweeps[ns.frames.player.power]
    stub.units.player.powerToken = "ENERGY"
    stub.FireEvent("UNIT_DISPLAYPOWER", "player")
    cast(10)
    T.falsy(s.holder:IsShown(), "a form: nothing on the energy bar")
    T.truthy(ns.PowerBar.regen.ends, "the rule still runs")
    stub.units.player.powerToken = "MANA"
    stub.FireEvent("UNIT_DISPLAYPOWER", "player")
    T.truthy(s.holder:IsShown(), "back on mana, it joins the sweep")
    stub.spellCosts = nil
end)

T.test("mana sweep: warriors and rogues get nothing, whatever the setting", function()
    local _, ns, PR, Sweeps = sweepLogin("spark", "WARRIOR", "RAGE")
    T.isnil(Sweeps[PR.frame.powerBar])
    T.falsy(ns.PowerBar.regen.listening)
    stub.spellCosts = nil
end)

T.test("mana sweep: each look draws its own way, and follows a right-to-left bar", function()
    local DUI, ns, _, Sweeps = sweepLogin("line")
    local s = Sweeps[ns.frames.player.power]
    cast(10)
    T.eq(s.timer.__timer[3], Enum.StatusBarTimerDirection.RemainingTime, "the line shrinks away")
    T.falsy(s.spark:IsShown()); T.falsy(s.trail:IsShown())
    DUI:Set("UnitFrames", "player.regenSweep", "trail")
    stub.RunTimers()
    cast(10)
    T.eq(s.timer.__timer[3], Enum.StatusBarTimerDirection.ElapsedTime)
    T.truthy(s.trail:IsShown()); T.falsy(s.spark:IsShown())
    DUI:Set("UnitFrames", "player.regenSweep", "off")
    stub.RunTimers()
    T.falsy(s.holder:IsShown(), "switched off mid-sweep goes at once")
    T.falsy(ns.PowerBar.regen.listening)
    stub.spellCosts = nil
end)

T.test("mana sweep: follows the bar to its free spot and Ribbon's line", function()
    local DUI, ns, _, Sweeps = sweepLogin("spark")
    local f = ns.frames.player
    DUI:Set("UnitFrames", "player.powerAt", "free")
    stub.RunTimers()
    cast(10)
    T.truthy(Sweeps[f.power], "the live bar has one")
    T.eq(Sweeps[f.power].holder:GetParent(), f.power:GetParent())
    T.truthy(Sweeps[f.power].holder:IsShown())
    T.falsy(Sweeps[f.insidePower.power].holder:IsVisible(), "the frame's own bar is hidden")
    stub.spellCosts = nil
end)

T.test("own border: follows General until asked, then its own thickness, corners and shadow", function()
    local DUI, _, PR = login()
    local body = PR.frame.body
    local s = DUI.Style.GetShell(body)
    T.isnil(s.opts.borderPx, "untouched, General's border")
    local H = body:GetHeight()
    DUI:Set("UnitFrames", "personal.shell.borderPx", 2)
    T.isnil(s.opts.borderPx, "the sliders do nothing until Own border and shadow is on")
    DUI:Set("UnitFrames", "personal.shell.own", true)
    DUI:Set("UnitFrames", "personal.shell.cornerPx", 0)
    DUI:Set("UnitFrames", "personal.shell.shadowPx", 0)
    T.eq(s.opts.borderPx, 2); T.eq(s.opts.cornerPx, 0); T.eq(s.opts.shadowPx, 0)
    T.truthy(body:GetHeight() < H, "a thinner border makes the body shorter: the bars keep their height")
    DUI:Set("UnitFrames", "personal.shell.borderPx", 0)
    T.eq(s.opts.borderPx, 0, "0 is no border, not General's")
    DUI:Set("UnitFrames", "personal.shell.own", false)
    T.isnil(s.opts.borderPx, "back to General's")
end)

T.test("textures: its own pick, else the player frame's, else General's", function()
    local DUI, ns = login()
    local Media = DUI.Media
    local slot = ns.UF.MEDIA.personal.bars
    T.isnil(Media.Pick(slot.health))
    DUI:Set("UnitFrames", "player.media.health", "flat")
    DUI:Set("UnitFrames", "player.media.powerBack", "flat")
    T.eq(Media.Pick(slot.health), "flat", "untouched, it wears the player frame's")
    T.eq(Media.Pick(slot.power .. ".back"), "flat", "the bar's background too")
    DUI:Set("UnitFrames", "personal.media.health", "glass")
    T.eq(Media.Pick(slot.health), "glass", "its own pick wins")
    T.eq(Media.Pick(ns.UF.MEDIA.player.bars.health), "flat", "and the player frame keeps its own")
end)

T.test("colors: the player frame's until it picks its own, health and power each", function()
    local DUI, _, PR = login()
    local paint = PR.frame.paint
    DUI:Set("UnitFrames", "player.colorHealth", "accent")
    DUI:Set("UnitFrames", "player.colorPower", "type")
    T.eq(paint.healthMode, "accent", "untouched, your player frame's health color")
    T.eq(paint.powerMode, "type", "and power color")
    DUI:Set("UnitFrames", "personal.colorHealth", "custom")
    DUI:Set("UnitFrames", "personal.colorHealthCustom", { 1, 0, 0 })
    T.eq(paint.healthMode, "custom")
    T.eq(paint.healthCustom[1], 1)
    T.eq(paint.powerMode, "type", "one pick leaves the other alone")
    DUI:Set("UnitFrames", "personal.colorPower", "global")
    T.eq(paint.powerMode, "global", "Same as the Colors page")
end)

T.test("a look change shows on the test sample straight away", function()
    local DUI, _, PR = login()
    PR.ShowSample()
    DUI:Set("UnitFrames", "personal.colorPower", "custom")
    T.truthy(PR.frame.test, "still the sample")
    T.eq(PR.frame.paint.powerMode, "custom")
    T.eq(stub.Plain(PR.frame.healthBar.__value), PR.SAMPLE.health, "showing the sample's values, not yours")
end)

T.test("numbers: off until asked, then your health and power on their bars", function()
    local DUI, _, PR = login()
    local h = PR.frame
    T.falsy(h.healthText:IsShown()); T.falsy(h.powerText:IsShown())
    stub.units.player.pct = 60
    DUI:Set("UnitFrames", "personal.showPercent", true)
    DUI:Set("UnitFrames", "personal.showPowerText", true)
    T.truthy(h.healthText:IsShown()); T.truthy(h.powerText:IsShown())
    T.eq(stub.Text(h.healthText), "60")
    T.eq(stub.Text(h.powerText), "20")
    stub.units.player.power = 35
    PR.UpdatePower()
    T.eq(stub.Text(h.powerText), "35", "follows the bar")
    DUI:Set("UnitFrames", "personal.showPower", false)
    T.falsy(h.powerText:IsShown(), "no power bar, no power text")
end)

T.test("numbers: a size of 0 fits the bar and never goes under the minimum", function()
    local DUI, _, PR = login()
    DUI:Set("UnitFrames", "personal.showPercent", true)
    local function size() return select(2, PR.frame.healthText:GetFont()) end
    DUI:Set("UnitFrames", "personal.height", 20)
    local tall = size()
    DUI:Set("UnitFrames", "personal.height", 9)
    local thin = size()
    T.truthy(tall > thin, "it fits its bar")
    DUI:Set("UnitFrames", "personal.height", 4)
    T.eq(size(), thin, "and stops shrinking at the minimum, still readable")
    DUI:Set("UnitFrames", "personal.healthTextSize", 24)
    T.truthy(size() > tall, "its own size wins")
end)

T.test("numbers: the test sample shows sample values", function()
    local DUI, _, PR = login()
    DUI:Set("UnitFrames", "personal.showPercent", true)
    DUI:Set("UnitFrames", "personal.showPowerText", true)
    PR.ShowSample()
    T.eq(stub.Text(PR.frame.healthText), tostring(PR.SAMPLE.health))
    T.eq(tostring(stub.Text(PR.frame.powerText)), tostring(PR.SAMPLE.power))
end)

T.test("angle: its own lean, else the shared one, and docked bars lean with it", function()
    local DUI, ns, PR = login()
    local h = PR.frame
    T.eq(PR.Angle(), ns.UF.SLANT, "untouched, the Slant angle")
    local before = h.cut
    DUI:Set("UnitFrames", "personal.angle", 0.5)
    T.eq(PR.Angle(), 0.5)
    T.truthy(h.cut > before, "the cut grows")
    DUI:Set("UnitFrames", "personal.castbar", true)
    local slant, cuts = DUI.Style.Slant, {}
    DUI.Style.Slant = function(f, side, cut, ...)
        if f == ns.playerCastbar then cuts[#cuts + 1] = cut end
        return slant(f, side, cut, ...)
    end
    DUI:Set("UnitFrames", "personal.angle", 0.6)
    DUI:Set("UnitFrames", "personal.angle", 0.1)
    DUI.Style.Slant = slant
    T.truthy(#cuts >= 2 and cuts[#cuts] < cuts[1], "the docked cast bar leans with it")
    DUI:Set("UnitFrames", "personal.slant", false)
    T.eq(h.cut, 0, "angled ends off: square, whatever the angle")
end)

T.test("incoming heals and shields hang off the health fill, the player frame's bars, secret amounts untouched", function()
    local DUI, ns, PR = login()
    local body = PR.frame.body
    T.truthy(body.heals and body.absorbs and body.overshield, "the same bars as the player frame")
    T.eq(body.heals:GetParent(), body.predictClip, "in the clip over its health bar")
    T.eq(body.predictClip:GetParent(), body)
    T.eq(body.heals:GetPoint(1), "TOPLEFT", "starting where the health fill ends")
    local _, rel = body.heals:GetPoint(1)
    T.eq(rel, PR.frame.healthBar:GetStatusBarTexture())
    T.truthy(body.healthCut > 0 and body.heals.wedge:IsShown(), "and leaning with the angled end")

    local heals, shield = stub.Secret(25), stub.Secret(10)
    stub.units.player.incoming = heals
    stub.FireEvent("UNIT_HEAL_PREDICTION", "player")
    T.eq(body.heals.__value, heals, "a heal on its way shows at once")
    stub.units.player.absorbs = shield
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(body.absorbs.__value, shield, "so does a shield")

    stub.units.player.incoming = stub.Secret(5)
    stub.units.player.health = 40
    stub.FireEvent("UNIT_HEALTH", "player")
    T.eq(body.heals.__value, stub.units.player.incoming, "a health change reads them again")

    DUI:Set("UnitFrames", "personal.predictHeals", false)
    T.falsy(body.heals:IsShown(), "each has its own switch")
    T.truthy(body.absorbs:IsShown())
    DUI:Set("UnitFrames", "personal.predictAbsorbs", false)
    T.falsy(body.absorbs:IsShown())
    T.falsy(body.overshield:IsShown())
    DUI:Set("UnitFrames", "personal.predictHeals", true)
    T.truthy(body.heals:IsShown())

    DUI:Set("UnitFrames", "personal.slant", false)
    T.falsy(body.heals.wedge:IsShown(), "square ends: nothing to lean past")
    DUI:Set("UnitFrames", "colors.healColor", { 1, 0, 0 })
    T.eq(body.heals.__barColor[2], 0, "the Colors page's heal color")
end)

T.test("incoming heals and shields cost nothing while the display is off, and the sample shows them", function()
    local DUI, ns, PR = login(nil, nil, false)
    T.isnil(PR.frame.body.heals, "no bars made")
    DUI:Set("UnitFrames", "personal.enabled", true)
    local body = PR.frame.body
    T.truthy(body.heals, "made the first time it's on")
    PR.ShowSample()
    T.eq(stub.Plain(body.heals.__value), PR.SAMPLE.heals)
    T.eq(stub.Plain(body.absorbs.__value), PR.SAMPLE.absorbs)
    T.eq(body.overshield:GetAlpha(), 0)
    stub.units.player.incoming = 30
    stub.FireEvent("UNIT_HEAL_PREDICTION", "player")
    T.eq(stub.Plain(body.heals.__value), PR.SAMPLE.heals, "the sample stands still")
    DUI:Set("UnitFrames", "personal.predictHeals", false)
    T.eq(stub.Plain(body.heals.__value), 0, "switched off, none in the sample")
    PR.HideSample()
    DUI:Set("UnitFrames", "personal.predictHeals", true)
    T.eq(stub.Plain(body.heals.__value), 30, "back to the real amount")
end)
