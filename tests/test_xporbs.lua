local stub = require("stub")

-- XP orbs: what each XP gain was and where it came from (XPSource), and the
-- burst that carries it into the XP bar (XPOrbs).

local PW = require("panelworld")

local KILL = "%s dies, you gain %d experience."

local function login()
    local DUI = PW.login()
    stub.cursorPos = { 0, 0 }
    -- The panel's world answers UnitGUID for the player only; mobs need theirs.
    _G.UnitGUID = function(u)
        local x = stub.units[u]
        if x then return x.guid end
        if u == "player" then return "Player-1" end
    end
    return DUI, stub.infopanel.XPSource, stub.infopanel.XPOrbs
end

-- A hostile mob under the cursor at (x, y), seen by the mouseover event.
local function hover(token, guid, name, x, y)
    local units = stub.units
    units.mouseover = { guid = guid, name = name, reaction = 2 }
    units[token] = units.mouseover
    stub.cursorPos = { x, y }
    stub.FireEvent("UPDATE_MOUSEOVER_UNIT")
    units.mouseover = nil
end

local function died(guid) stub.FireEvent("UNIT_DIED", guid) end
local function line(text) stub.FireEvent("CHAT_MSG_COMBAT_XP_GAIN", text) end

-- Asks the source about a gain of n XP; returns a table filled once it's decided.
local function take(Src, n)
    local got = {}
    Src.Resolve(n, function(src) got.src = src end)
    return got
end

-- Time passes and the waiting timers run.
local function wait(s)
    stub.Advance(s)
    stub.RunTimersOnce()
end

T.test("xp orbs: a kill gives one burst from where the cursor was over that mob", function()
    local _, Src = login()
    hover("nameplate1", "Creature-1", "Defias Pillager", 700, 600)
    died("Creature-1")
    line(KILL:format("Defias Pillager", 240))
    local got = take(Src, 240)
    T.truthy(got.src, "decided at once: the line was already there")
    T.eq(got.src.kind, "kill")
    T.truthy(got.src.known, "a fresh sample: the mob's spot is known")
    T.near(got.src.x, 700, 0.01)
    T.near(got.src.y, 600, 0.01)
end)

T.test("xp orbs: the chat line before or after the XP update, the same single burst", function()
    local _, Src = login()
    hover("nameplate1", "Creature-1", "Kobold Miner", 500, 400)
    died("Creature-1")
    local got = take(Src, 90)
    T.isnil(got.src, "the XP waits for the line that explains it")
    line(KILL:format("Kobold Miner", 90))
    T.eq(got.src and got.src.kind, "kill", "the late line claims it")
    T.near(got.src.x, 500, 0.01)
    local again = take(Src, 90)
    wait(0.5)
    T.eq(again.src and again.src.kind, "other", "the same line never pays for a second gain")
end)

T.test("xp orbs: eight kills in one pull give eight bursts, each from its own mob", function()
    local _, Src = login()
    for i = 1, 8 do hover("nameplate" .. i, "Creature-" .. i, "Mob " .. i, 100 * i, 300) end
    local got = {}
    -- Deaths, lines and XP updates arrive interleaved, as in an AoE pull.
    for i = 1, 8 do
        died("Creature-" .. i)
        if i % 2 == 0 then got[i] = take(Src, 50 + i); line(KILL:format("Mob " .. i, 50 + i))
        else line(KILL:format("Mob " .. i, 50 + i)); got[i] = take(Src, 50 + i) end
    end
    for i = 1, 8 do
        T.eq(got[i].src and got[i].src.kind, "kill", "burst " .. i)
        T.near(got[i].src.x, 100 * i, 0.01, "from its own mob " .. i)
    end
end)

T.test("xp orbs: with the chat line and the mob's GUID secret, kills pair by order, no error", function()
    local _, Src = login()
    hover("nameplate1", "Creature-1", "Mob", 800, 500)
    stub.FireEvent("UNIT_DIED", stub.Secret("Creature-1"))
    line(stub.Secret(KILL:format("Mob", 75)))
    local got = take(Src, 75)
    T.eq(got.src and got.src.kind, "kill", "a hidden line still means a kill")
    T.falsy(got.src.known, "nothing ties it to a sample: the default spot")
    T.near(got.src.x, UIParent:GetWidth() * 0.5, 0.01)
    T.near(got.src.y, UIParent:GetHeight() * 0.58, 0.01)
end)

T.test("xp orbs: an old cursor sample fades toward the default spot, gone at 3 s", function()
    local _, Src = login()
    local mx, my = UIParent:GetWidth() * 0.5, UIParent:GetHeight() * 0.58
    hover("nameplate1", "Creature-1", "Mob", mx + 200, my)
    stub.Advance(2)
    died("Creature-1")
    line(KILL:format("Mob", 10))
    local got = take(Src, 10)
    T.near(got.src.x, mx + 100, 0.5, "2 s old: halfway")
    stub.Advance(2)
    hover("nameplate2", "Creature-2", "Mob", 100, 100)
    stub.Advance(3.5)
    died("Creature-2")
    line(KILL:format("Mob", 11))
    got = take(Src, 11)
    T.near(got.src.x, mx, 0.5, "3.5 s old: the default spot")
end)

T.test("xp orbs: a quest turn-in's XP is a quest burst", function()
    local _, Src = login()
    stub.FireEvent("QUEST_TURNED_IN", 176, 1450, 0)
    local got = take(Src, 1450)
    T.eq(got.src and got.src.kind, "quest")
    T.near(got.src.x, UIParent:GetWidth() * 0.30, 0.01, "no NPC window: the quest default")
end)

T.test("xp orbs: discovering a place starts at the zone text", function()
    local _, Src = login()
    local zone = CreateFrame("Frame", "SubZoneTextFrame", UIParent)
    zone.__center = { 600, 620 }   -- the fake game lays nothing out
    zone:Show()
    stub.FireEvent("CHAT_MSG_SYSTEM", ERR_ZONE_EXPLORED_XP:format("Goldshire", 120))
    local got = take(Src, 120)
    T.eq(got.src and got.src.kind, "explore")
    T.near(got.src.y, 620, 0.01)
end)

T.test("xp orbs: XP nobody explains is other XP after 0.4 s", function()
    local _, Src = login()
    local got = take(Src, 33)
    wait(0.2)
    T.isnil(got.src, "still waiting")
    wait(0.25)
    T.eq(got.src and got.src.kind, "other")
    T.near(got.src.y, UIParent:GetHeight() * 0.65, 0.01)
end)

T.test("xp orbs: a rested kill reports its bonus from the line, else half the rested pool's drop", function()
    local _, Src = login()
    hover("nameplate1", "Creature-1", "Mob", 700, 600)
    died("Creature-1")
    line(COMBATLOG_XPGAIN_EXHAUSTION1:format("Mob", 240, "+120", "Rested"))
    local got = take(Src, 240)
    T.eq(got.src and got.src.bonus, 120, "the line's bonus")
    hover("nameplate2", "Creature-2", "Mob", 700, 600)
    died("Creature-2")
    line(KILL:format("Mob", 200))
    got = {}
    Src.Resolve(200, function(src) got.src = src end, 200)
    T.eq(got.src and got.src.bonus, 100, "no bonus in the line: half the pool's drop")
end)

T.test("xp orbs: a group kill reads the group line", function()
    local _, Src = login()
    hover("nameplate1", "Creature-1", "Mob", 640, 480)
    died("Creature-1")
    line(COMBATLOG_XPGAIN_FIRSTPERSON_GROUP:format("Mob", 130, 22))
    local got = take(Src, 130)
    T.eq(got.src and got.src.kind, "kill")
    T.near(got.src.x, 640, 0.01)
end)

-- The bar's colors and landing spot (XPBar.lua), for the orbs.

T.test("xp orbs: orbs wear the XP bar's own colors, whatever it's set to", function()
    local DUI = login()
    local XP, Style = stub.infopanel.XP, DUI.Style
    local fill = XP.bar:GetStatusBarTexture()
    for _, pick in ipairs({ "accent", "class", "blue" }) do
        DUI:Set("InfoPanel", "xp.color", pick)
        local g = fill.__gradient
        T.truthy(g, pick .. ": the fill is a gradient")
        T.rgb({ XP.ColorAt(0) }, { g[2].r, g[2].g, g[2].b }, pick .. ": the first orb is the fill's start")
        T.rgb({ XP.ColorAt(1) }, { g[3].r, g[3].g, g[3].b }, pick .. ": the last orb is its end")
    end
    DUI:Set("InfoPanel", "xp.color", "custom")
    DUI:Set("InfoPanel", "xp.customGradient.count", 4)
    local stops = Style.FillStops(fill)
    T.eq(#stops, 4)
    T.rgb({ XP.ColorAt(0.5) }, { Style.StopsAt(stops, 0.5) }, "four colors: each orb its spot along all of them")
    DUI:Set("InfoPanel", "xp.gradient", false)
    T.rgb({ XP.ColorAt(0) }, { XP.ColorAt(1) }, "no gradient: one color")
end)

T.test("xp orbs: they land on the fill's end, and at the top of an upright bar's fill", function()
    local DUI = login()
    local XP = stub.infopanel.XP
    XP.bar.__center = { 500, 700 }
    XP.bar:SetSize(200, 10)
    XP.bar:SetMinMaxValues(0, 1200)
    local x, y = XP.LandAt(300)
    T.near(x, 400 + 50, 0.01)
    T.near(y, 700, 0.01)
    DUI:Set("InfoPanel", "xp.detached", true)
    DUI:Set("InfoPanel", "xp.orientation", "vertical")
    XP.bar.__center = { 500, 700 }
    XP.bar:SetSize(10, 200)
    XP.bar:SetMinMaxValues(0, 1200)
    x, y = XP.LandAt(600)
    T.near(x, 500, 0.01)
    T.near(y, 600 + 100, 0.01, "half way up")
end)

-- The Bloom burst (XPOrbs.lua) and the bar it fills.

local function setXP(value, max)
    _G.UnitXP = function() return value end
    _G.UnitXPMax = function() return max or 1200 end
    stub.FireEvent("PLAYER_XP_UPDATE")
end

-- The panel's XP bar on screen: 200 wide, its middle at (680, 740).
local function barLogin()
    local DUI, Src, Orbs = login()
    local XP = stub.infopanel.XP
    XP.bar.__center = { 680, 740 }
    XP.bar:SetSize(200, 10)
    setXP(300)
    return DUI, XP, Orbs
end

local function kill(guid, amount, value, max)
    hover("nameplate1", guid, "Mob", 600, 400)
    died(guid)
    line(KILL:format("Mob", amount))
    setXP(value, max)
end

-- Frames go by: the orbs and the tweens move on, timers run.
local function run(Orbs, secs, each)
    for _ = 1, math.ceil(secs * 60) do
        if Orbs.layer then stub.RunOnUpdate(Orbs.layer, 1 / 60) end
        local d = DaylightUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 1 / 60) end
        stub.Advance(1 / 60)
        -- Looked at before the timers: the fake game runs them at once.
        if each then each() end
        stub.RunTimersOnce()
    end
end

T.test("xp orbs: a gain blooms more orbs the more of a level it is (3% = 12, 18% = 24, at most 30)", function()
    local _, XP, Orbs = barLogin()
    T.eq(Orbs.Count(36, 1200), 12)
    T.eq(Orbs.Count(216, 1200), 24)
    T.eq(Orbs.Count(1200, 1200), 30)
    kill("Creature-1", 216, 516)
    T.eq(#Orbs.bursts, 1, "one burst")
    T.eq(#Orbs.bursts[1].orbs, 24)
    T.eq(XP.bar:GetValue(), 300, "the bar waits for the orbs")
end)

T.test("xp orbs: the fill steps once per landed orb and eases there, never jumping", function()
    local _, XP, Orbs = barLogin()
    kill("Creature-1", 240, 540)
    local n, step = #Orbs.bursts[1].orbs, 240 / #Orbs.bursts[1].orbs
    -- The orbs land over NORMAL, so a few share a frame; the rise is spread
    -- over many frames and never past the true value (the client eases on top).
    local last, landedSeen, worst, frames, over = XP.bar:GetValue(), 0, 0, 0, false
    run(Orbs, 2.2, function()
        local v = XP.bar:GetValue()
        if v > last then frames = frames + 1 end
        worst = math.max(worst, v - last)
        over = over or v > 540
        last = v
        landedSeen = math.max(landedSeen, Orbs.landed or 0)
    end)
    T.eq(landedSeen, n, "every orb landed")
    T.truthy(frames >= 8, "the fill rose in many frames: " .. frames)
    T.truthy(worst <= 240 / 4, "never a quarter of the gain at once: " .. worst)
    T.falsy(over, "never past the true value")
    T.truthy(step > 0)
    T.near(XP.bar:GetValue(), 540, 0.001, "ends on the true value")
end)

T.test("xp orbs: the orbs wear the bar's colors, rested ones the rested color", function()
    local DUI, XP, Orbs = barLogin()
    hover("nameplate1", "Creature-1", "Mob", 600, 400)
    died("Creature-1")
    line(COMBATLOG_XPGAIN_EXHAUSTION1:format("Mob", 240, "+120", "Rested"))
    setXP(540)
    local orbs = Orbs.bursts[1].orbs
    local rested = 0
    for _, o in ipairs(orbs) do if o.rested then rested = rested + 1 end end
    T.eq(rested, math.floor(#orbs / 2 + 0.5), "half the XP was the rested bonus: half the orbs")
    local plain = {}
    for _, o in ipairs(orbs) do if not o.rested then plain[#plain + 1] = o else T.rgb(o.color, XP.RESTED) end end
    T.rgb(plain[1].color, { XP.ColorAt(0) }, "the first along the bar's start")
end)

T.test("xp orbs: the last landing sweeps the gained piece and shows +N", function()
    local _, XP, Orbs = barLogin()
    local G = stub.infopanel.XPGain
    kill("Creature-1", 240, 540)
    run(Orbs, 1.0)
    T.falsy(G.riser and G.riser:IsShown(), "no +N while orbs fly")
    run(Orbs, 0.8)
    T.truthy(G.riser and G.riser:IsShown(), "+N at the last landing")
    T.eq(G.riser.text:GetText(), "+240")
    T.truthy(G.piece and G.piece.light:IsShown(), "a light sweeps the gained piece")
    T.near(G.piece:GetWidth(), 200 * 240 / 1200, 0.01, "as wide as the gain")
end)

T.test("xp orbs: a kill that levels you fills to the end, sweeps, then the bar starts the new level", function()
    _G.UnitLevel = function() return 10 end
    local _, XP, Orbs = barLogin()
    DaylightUI:Set("InfoPanel", "xpGain", false)
    setXP(1100)
    DaylightUI:Set("InfoPanel", "xpGain", true)
    setXP(1100)
    hover("nameplate1", "Creature-1", "Mob", 600, 400)
    died("Creature-1")
    line(KILL:format("Mob", 300))
    _G.UnitLevel = function() return 11 end
    stub.FireEvent("PLAYER_LEVEL_UP", 11)
    setXP(200, 1500)
    T.eq(#Orbs.bursts, 1)
    local peak, sweeps = 0, 0
    local G = stub.infopanel.XPGain
    run(Orbs, 2, function()
        peak = math.max(peak, XP.bar:GetValue())
        if G.band and G.band:IsShown() then sweeps = sweeps + 1 end
    end)
    T.near(peak, 1500, 0.001, "full while the level-up light crosses")
    T.truthy(sweeps > 0, "the level-up band crossed")
    T.near(XP.bar:GetValue(), 200, 0.001, "then the new level's XP")
end)

T.test("xp orbs: with XP gain effects or motion off there are no orbs and the bar moves at once", function()
    local DUI, XP, Orbs = barLogin()
    DUI:Set("InfoPanel", "xpGain", false)
    kill("Creature-1", 100, 400)
    T.eq(#Orbs.bursts, 0)
    T.eq(XP.bar:GetValue(), 400)
    DUI:Set("InfoPanel", "xpGain", true)
    DUI.DB.General().motion = false
    kill("Creature-2", 100, 500)
    T.eq(#Orbs.bursts, 0)
    T.eq(XP.bar:GetValue(), 500)
end)

T.test("xp orbs: the bar hidden mid-burst ends it at once, nothing left on screen", function()
    local _, XP, Orbs = barLogin()
    kill("Creature-1", 240, 540)
    run(Orbs, 0.3)
    XP.frame:Hide()
    XP.Update()
    T.eq(#Orbs.bursts, 0)
    for _, t in ipairs(Orbs.textures or {}) do T.falsy(t:IsShown(), "no orb left drawn") end
    T.isnil(Orbs.layer:GetScript("OnUpdate"), "nothing runs")
end)

T.test("xp orbs: with the XP Orbs addon loaded, Daylight UI draws none", function()
    local _, XP, Orbs = barLogin()
    stub.loadedAddOns["XPOrbs"] = true
    kill("Creature-1", 240, 540)
    T.eq(#Orbs.bursts, 0)
end)

T.test("xp orbs: eight kills in one pull, eight bursts, the bar ends on the true value", function()
    local _, XP, Orbs = barLogin()
    local value = 300
    for i = 1, 8 do
        value = value + 40 + i
        kill("Creature-" .. i, 40 + i, value)
    end
    T.eq(#Orbs.bursts, 8)
    run(Orbs, 2.5)
    T.near(XP.bar:GetValue(), value, 0.001)
    T.eq(#Orbs.bursts, 0, "all done")
    T.isnil(Orbs.layer:GetScript("OnUpdate"), "and nothing runs once they have landed")
end)

-- Quest bursts start at the talk window's Complete button (Npc/Window.lua),
-- where the player clicked.

T.test("xp orbs: a turn-in blooms at the talk window's Complete button, even once the window has closed", function()
    local NW = require("npcworld")
    stub.Load({ before = NW.world(), infopanel = true })
    local Src = stub.infopanel.XPSource
    NW.Quest("COMPLETE", NW.Candles({ choices = {} }))
    stub.RunTimersOnce()           -- the page fills
    stub.Advance(1)                -- the rewards have had time to load
    stub.RunTimers()
    local N = DaylightUI.Npc.Window
    local done = N.frame.pages.talk.foot.buttons[1]
    T.truthy(done.text:GetText():find("^Complete"), done.text:GetText())
    done.__center = { 640, 120 }   -- the fake game lays nothing out
    local x, y = DaylightUI.Npc.XPSpot()
    T.near(x, 640, 0.01, "the spot is the Complete button")
    T.near(y, 120, 0.01)
    done:GetScript("OnClick")(done, "LeftButton")
    -- The window goes before the XP arrives.
    NW.Escape()
    done.__center = nil
    stub.FireEvent("QUEST_TURNED_IN", 60, 450, 80)
    local got = {}
    Src.Resolve(450, function(src) got.src = src end)
    T.eq(got.src and got.src.kind, "quest")
    T.truthy(got.src.known, "the button's spot, noted at the click")
    T.near(got.src.x, 640, 0.01)
    T.near(got.src.y, 120, 0.01)
end)

-- Size, flight time and color are the player's (InfoPanel "orbs.*"), and the
-- stream bows like the mock-up's at any distance.

-- The time from the gain to the last orb's landing.
local function lastLanding(Orbs)
    local t, n, landedAt = 0, #Orbs.bursts[1].orbs, nil
    run(Orbs, 3, function()
        t = t + 1 / 60
        if not landedAt and (Orbs.landed or 0) >= n then landedAt = t end
    end)
    return landedAt
end

T.test("xp orbs: twice as slow by default (the last lands ~1.6 s in), and the flight time setting changes it", function()
    local DUI, XP, Orbs = barLogin()
    kill("Creature-1", 216, 516)
    local t = lastLanding(Orbs)
    T.truthy(t and t > 1.55 and t < 1.75, "default: about 1.6 s, got " .. tostring(t))
    DUI:Set("InfoPanel", "orbs.flight", 0.4)
    kill("Creature-2", 216, 732)
    t = lastLanding(Orbs)
    T.truthy(t and t > 0.85 and t < 1.0, "0.4 s flights: about 0.9 s, got " .. tostring(t))
end)

T.test("xp orbs: bigger by default, and the size setting scales them", function()
    local DUI, XP, Orbs = barLogin()
    kill("Creature-1", 216, 516)
    run(Orbs, 0.1)
    local o = Orbs.bursts[1].orbs[1]
    local w = o.halo:GetWidth()
    T.truthy(w >= 20, "a default orb's glow is at least 20 wide: " .. w)
    DUI:Set("InfoPanel", "orbs.size", 2)
    kill("Creature-2", 216, 732)
    run(Orbs, 0.1)
    local o2 = Orbs.bursts[#Orbs.bursts].orbs[1]
    T.truthy(o2.r >= 2 * Orbs.SIZE[1], "twice the radius: " .. o2.r)
    T.near(o2.halo:GetWidth(), 2 * Orbs.HALO * o2.r, 0.001, "and the glow with it")
end)

T.test("xp orbs: the orb color setting: the bar's, accent, Daylight gradient, class gradient, class color, one color", function()
    local DUI, XP, Orbs = barLogin()
    local Style, G = DUI.Style, DUI.Gradients
    local function first(mode, custom)
        DUI:Set("InfoPanel", "orbs.color", mode)
        if custom then DUI:Set("InfoPanel", "orbs.custom", custom) end
        return { Orbs.ColorAt(0) }, { Orbs.ColorAt(1) }
    end
    local a, b = first("bar")
    T.rgb(a, { XP.ColorAt(0) }); T.rgb(b, { XP.ColorAt(1) })
    a, b = first("accent")
    T.rgb(a, { Style.AccentAt(0) }); T.rgb(b, { Style.AccentAt(1) })
    a = first("daylight")
    T.rgb(a, { Style.SweepAt(0) })
    a, b = first("gradient")
    local lo, hi = G.PaintRGB(G.KeyFor("player"))
    T.rgb(a, lo); T.rgb(b, hi)
    a = first("class")
    T.rgb(a, { Style.ClassColor(select(2, UnitClass("player"))) })
    a, b = first("custom", { 0.2, 0.9, 0.4 })
    T.rgb(a, { 0.2, 0.9, 0.4 }); T.rgb(b, { 0.2, 0.9, 0.4 })
    kill("Creature-1", 216, 516)
    T.rgb(Orbs.bursts[1].orbs[1].color, { 0.2, 0.9, 0.4 }, "a burst wears it")
end)

T.test("xp orbs: the stream bows out from the straight line by a share of the distance, however far", function()
    local _, XP, Orbs = barLogin()
    kill("Creature-1", 216, 516)
    local b = Orbs.bursts[1]
    local o = b.orbs[1]
    local tx, ty = XP.LandAt(XP.bar:GetValue())
    local dist = math.sqrt((o.rx - tx) ^ 2 + (o.ry - ty) ^ 2)
    local worst = 0
    run(Orbs, 2, function()
        if o.done or not o.halo then return end
        local _, _, _, px, py = o.halo:GetPoint(1)
        -- distance from the straight line ring spot -> bar
        local dx, dy = tx - o.rx, ty - o.ry
        local d = math.abs(dy * (px - o.rx) - dx * (py - o.ry)) / dist
        worst = math.max(worst, d)
    end)
    -- The mock-up's shape bows about 14% at its widest; fixed bows read as a
    -- beeline across a whole screen (6%).
    T.truthy(worst >= 0.10 * dist, "bows at least 10% of the way: " .. worst .. " of " .. dist)
end)

-- For addon authors (API 1.17): read the orbs' settings, hear each gain and
-- each landing, and fly a burst of their own.

T.test("xp orbs api: the version, the settings, and an event per gain and per landing", function()
    local DUI, XP, Orbs = barLogin()
    local API = DUI.API
    T.truthy(API.minor >= 17, "API 1.17")
    local o = API.XPOrbs()
    T.eq(o.on, true); T.eq(o.size, 1); T.eq(o.flight, 0.8); T.eq(o.color, "bar")
    local me = API.For("OrbWatcher")
    local gained, landed = {}, {}
    me.On("XPGained", function(amount, kind, x, y, known) gained[#gained + 1] = { amount, kind, x, y, known } end)
    me.On("XPOrbsLanded", function(amount) landed[#landed + 1] = amount end)
    kill("Creature-1", 240, 540)
    T.eq(#gained, 1, "heard once")
    T.eq(gained[1][1], 240); T.eq(gained[1][2], "kill"); T.near(gained[1][3], 600, 0.01); T.eq(gained[1][5], true)
    T.eq(#landed, 0, "not landed yet")
    run(Orbs, 2.5)
    T.eq(#landed, 1); T.eq(landed[1], 240)
    DUI:Set("InfoPanel", "xpGain", false)
    T.eq(API.XPOrbs().on, false, "off with XP gain effects")
end)

T.test("xp orbs api: a plugin's own burst flies to the bar and changes nothing", function()
    local DUI, XP, Orbs = barLogin()
    local me = DUI.API.For("Sparkles")
    local landed = 0
    me.On("XPOrbsLanded", function() landed = landed + 1 end)
    T.eq(me.ShowXPOrbs(300, 500, 12), true)
    T.eq(#Orbs.bursts, 1); T.eq(#Orbs.bursts[1].orbs, 12)
    run(Orbs, 2.5)
    T.eq(#Orbs.bursts, 0, "landed")
    T.eq(XP.bar:GetValue(), 300, "the bar is untouched")
    T.eq(landed, 0, "a plugin's burst is no gain")
    T.eq(me.ShowXPOrbs(300, 500, 99) and #Orbs.bursts[1].orbs, 30, "at most 30")
    T.eq(me.ShowXPOrbs("x", 500), false, "a spot is two numbers")
end)
