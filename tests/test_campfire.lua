local stub = require("stub")

-- The campfire (QoL/Campfire.lua): sitting by a campfire (Welcoming Campfire on
-- you) warms the screen and hushes the bars and unit frames. Camp Benefits landing
-- is the second beat, and any sign of play wakes it all.

local WELCOMING, WELCOMING2, BENEFITS = 1229739, 1289723, 1229741

local function auras(list)
    stub.SetAuras("player", "HELPFUL", list)
    stub.FireEvent("UNIT_AURA", "player")
end

local function sitAura(id) return { spellId = id or WELCOMING, name = "Welcoming Campfire", expirationTime = GetTime() + 60, duration = 60 } end
local function benefitsAura(expires) return { spellId = BENEFITS, name = "Camp Benefits", expirationTime = expires, duration = 1800 } end

local area

local function login(before)
    stub.Load({ qol = true, before = function()
        stub.SetAuras("player", "HELPFUL", {})
        if before then before() end
    end })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    -- A stand-in action bar area, to see the hush reach a real fade area.
    area = CreateFrame("Frame", nil, UIParent)
    area:Show()
    function area:IsMouseOver() return false end
    DaylightUI.DB.General().campTestFade = { mode = "never" }
    DaylightUI.Fade.Register{ key = "ActionBars.campTest", scope = "general", path = "campTestFade",
        frames = function() return { area } end }
    return stub.qol.Campfire
end

local function frame() return _G.DaylightUICampfire end

-- Runs secs worth of frames on the campfire's driver and the fade engine.
local function play(secs)
    local F = DaylightUI.Fade
    local n = math.max(1, math.floor(secs * 30 + 0.5))
    for i = 1, n do
        local f = frame()
        if f and f:IsShown() and f:GetScript("OnUpdate") then stub.RunOnUpdate(f, secs / n) end
        if i % 3 == 0 then F.Step() end
        stub.RunOnUpdate(F.driver, secs / n)
        stub.Advance(secs / n)
    end
end

local function embersShown(f)
    local n = 0
    for _, e in ipairs(f.embers) do if e.tex:IsShown() then n = n + 1 end end
    return n
end

T.test("campfire: sitting down warms the screen, embers rise and the bars fade out slowly", function()
    local C = login()
    auras({ sitAura() })
    local f = frame()
    T.truthy(f and f:IsShown(), "shown when you sit")
    T.eq(C.state, "sitting")
    T.truthy(DaylightUI.Fade.Hushed(), "the bars and unit frames are hushed")
    T.falsy(f:IsMouseEnabled(), "takes no clicks")
    T.eq(f:GetFrameStrata(), "BACKGROUND", "under every frame")
    play(0.6)
    T.truthy(area:GetAlpha() > 0.3, "the bars leave slowly, not in a blink")
    play(3)
    T.truthy(f.dome:GetAlpha() > 0.1, "the glow is up")
    T.truthy(embersShown(f) > 0, "embers drift up")
    T.eq(area:GetAlpha(), 0, "the bars are gone")
    T.eq(f.flare:GetAlpha(), 0, "no flare yet")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("campfire: either Welcoming Campfire spell counts", function()
    local C = login()
    auras({ sitAura(WELCOMING2) })
    T.eq(C.state, "sitting")
end)

T.test("campfire: Camp Benefits landing flares the fire up big, then it settles and rests", function()
    local C = login()
    auras({ sitAura() })
    play(3)
    local f = frame()
    local rest, restH = f.dome:GetAlpha(), f.dome:GetHeight()
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    T.eq(C.state, "resting")
    T.isnil(f.title, "no words: the fire says it")
    play(0.5)
    T.truthy(f.dome:GetAlpha() > rest * 2, "the fire flares up bright")
    T.truthy(f.dome:GetHeight() > restH * 1.15, "and tall")
    T.truthy(f.flare:GetAlpha() > 0.2, "a bloom of light from the fire")
    T.truthy(embersShown(f) >= 20, "a big spray of embers")
    play(8)
    stub.RunTimers()
    play(1)
    T.near(f.dome:GetAlpha(), rest, rest * 0.25, "settled back to the calm glow")
    T.eq(f.flare:GetAlpha(), 0, "the bloom has gone")
    T.truthy(f:IsShown(), "the glow stays while you rest")
    T.falsy(DaylightUI.Fade.Hushed(), "the bars and frames came back")
    T.truthy(area:GetAlpha() > 0.9, "eased back in")
end)

T.test("campfire: rested, the bars and frames come back as the mark leaves; the chat stops floating", function()
    local C = login()
    local said = {}
    DaylightUI.On("Campfire", function(on, snap) said[#said + 1] = { on, snap } end)
    auras({ sitAura() })
    play(3)
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    play(1)
    T.truthy(DaylightUI.Fade.Hushed(), "the flare plays on a quiet screen first")
    T.eq(area:GetAlpha(), 0)
    stub.RunTimers()
    T.falsy(DaylightUI.Fade.Hushed(), "then they come back")
    T.eq(said[#said][1], false, "the chat lets go")
    T.falsy(said[#said][2], "at the normal speed, not a snap")
    play(0.15)
    T.truthy(area:GetAlpha() < 0.9, "easing in, not popping")
    play(1)
    T.truthy(area:GetAlpha() > 0.9)
    T.eq(C.state, "resting", "still by the fire until you move")
    T.truthy(frame():IsShown())
    stub.FireEvent("PLAYER_STARTED_MOVING")
    T.eq(C.state, "idle")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("campfire: rested, a new Welcoming Campfire doesn't fade the UI again until the rest wait is over", function()
    local C = login()
    auras({ sitAura() })
    play(3)
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    stub.RunTimers()
    play(1)
    T.falsy(DaylightUI.Fade.Hushed(), "rested: the UI is back")
    -- The fire hands out the next minute while you sit and chat.
    auras({ benefitsAura(GetTime() + 1800) })
    auras({ benefitsAura(GetTime() + 1800), sitAura() })
    T.eq(C.state, "resting", "no new sit inside the wait")
    T.falsy(DaylightUI.Fade.Hushed(), "the UI stays")
    -- Moving and coming back inside the wait stays quiet too.
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(3)
    auras({ benefitsAura(GetTime() + 1800) })
    auras({ benefitsAura(GetTime() + 1800), sitAura() })
    T.eq(C.state, "idle")
    T.falsy(DaylightUI.Fade.Hushed())
    -- After the wait the fire sits you down again.
    stub.Advance(DaylightUI:Get("QoL", "campfireRest") * 60)
    auras({ benefitsAura(GetTime() + 1800) })
    auras({ benefitsAura(GetTime() + 1800), sitAura() })
    T.eq(C.state, "sitting", "the wait is over")
    T.truthy(DaylightUI.Fade.Hushed())

    -- 0 means every minute, as before.
    C = login()
    DaylightUI:Set("QoL", "campfireRest", 0)
    auras({ sitAura() })
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    stub.RunTimers()
    auras({ benefitsAura(GetTime() + 1800) })
    auras({ benefitsAura(GetTime() + 1800), sitAura() })
    T.eq(C.state, "sitting")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("campfire: the seconds left sit over the fire, no bar along the bottom", function()
    local C = login()
    auras({ sitAura() })
    local f = frame()
    play(2.5)
    T.eq(f.count:GetText(), "58", "the seconds left")
    T.truthy(f.count:GetAlpha() > 0.9, "in with the fire")
    T.eq(f.fuse, nil, "no timer bar: it spoils the mood")
    play(27)
    T.eq(f.count:GetText(), "31")
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    T.truthy(f.count:GetAlpha() > 0.5, "the count eases out, not a blink")
    play(0.5)
    T.eq(f.count:GetAlpha(), 0, "making way for the mark")
    T.eq(C.state, "resting")

    -- Motion off: it still counts, with no fades.
    login()
    DaylightUI:Set("general", "motion", false)
    stub.RunTimers()
    auras({ sitAura() })
    f = frame()
    play(0.1)
    T.eq(f.count:GetText(), "60")
    T.truthy(f.count:GetAlpha() > 0.9, "the count at once")
    play(19.5)
    T.eq(f.count:GetText(), "41", "counting with motion off too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("campfire: Welcoming going with Camp Benefits refreshed is the second beat; unchanged is standing up", function()
    local old = GetTime() + 600
    local C = login()
    auras({ benefitsAura(old) })          -- still up from an earlier camp
    auras({ benefitsAura(old), sitAura() })
    T.eq(C.state, "sitting", "an old Camp Benefits doesn't count")
    auras({ benefitsAura(GetTime() + 1800) })
    T.eq(C.state, "resting", "refreshed: the minute is done")

    C = login()
    auras({ benefitsAura(old) })
    auras({ benefitsAura(old), sitAura() })
    auras({ benefitsAura(old) })           -- stood up early
    T.eq(C.state, "sitting", "waits a moment for Camp Benefits")
    stub.RunTimers()
    T.eq(C.state, "idle", "nothing new: you stood up")
    T.falsy(DaylightUI.Fade.Hushed())
end)

T.test("campfire: moving, targeting or casting wakes everything", function()
    for _, wake in ipairs({
        function() stub.FireEvent("PLAYER_STARTED_MOVING") end,
        function() stub.FireEvent("PLAYER_TARGET_CHANGED") end,
        function() stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "x", 1) end,
    }) do
        local C = login()
        auras({ sitAura() })
        play(3)
        wake()
        T.eq(C.state, "idle")
        T.falsy(DaylightUI.Fade.Hushed(), "the bars come back")
        play(0.6)
        T.truthy(area:GetAlpha() > 0.9, "back at the normal speed")
        T.truthy(frame():IsShown(), "the glow fades out, not a blink")
        play(2)
        T.falsy(frame():IsShown(), "then it's gone")
    end
end)

T.test("campfire: a fight snaps it away and never starts it", function()
    local C = login()
    auras({ sitAura() })
    play(3)
    stub.EnterCombat()
    T.eq(C.state, "idle")
    T.falsy(frame():IsShown(), "gone at once")
    T.eq(area:GetAlpha(), 1, "the bars are back at once")
    auras({ sitAura() })
    T.eq(C.state, "idle", "nothing starts in a fight")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("campfire: under restrictions it reads nothing", function()
    local C = login()
    stub.SetRestriction("Encounter", true)
    auras({ sitAura() })
    T.eq(C.state, "idle")
    stub.SetRestriction("Encounter", false)
end)

T.test("campfire: a reload while sitting stays quiet", function()
    local C = login(function() stub.SetAuras("player", "HELPFUL", { sitAura() }) end)
    stub.FireEvent("UNIT_AURA", "player")
    T.eq(C.state, "idle")
    T.falsy(frame() and frame():IsShown())
end)

T.test("campfire: off does nothing, and turning it off while sitting wakes", function()
    local C = login()
    DaylightUI:Set("QoL", "campfire", false)
    auras({ sitAura() })
    T.eq(C.state, "idle")
    DaylightUI:Set("QoL", "campfire", true)
    auras({})
    auras({ sitAura() })
    T.eq(C.state, "sitting")
    DaylightUI:Set("QoL", "campfire", false)
    T.eq(C.state, "idle")
    T.falsy(DaylightUI.Fade.Hushed())
end)

T.test("campfire: with motion off the glow just appears, no embers", function()
    local C = login()
    DaylightUI:Set("general", "motion", false)
    auras({ sitAura() })
    play(0.1)
    local f = frame()
    T.truthy(f.dome:GetAlpha() > 0.1, "at rest at once")
    T.eq(embersShown(f), 0)
    T.eq(C.state, "sitting")
end)

T.test("campfire: a crackle loops while you sit, the flare whooshes, and both stop when you get up", function()
    local played, stopped, handles = {}, {}, 0
    local was, wasStop = _G.PlaySoundFile, _G.StopSound
    _G.PlaySoundFile = function(file)
        played[#played + 1] = file
        handles = handles + 1
        return true, handles
    end
    _G.StopSound = function(h, ms) stopped[#stopped + 1] = { h, ms } end
    local C = login()
    local S = DaylightUI.Sound
    auras({ sitAura() })
    T.eq(played[#played], S.FILES.campfire, "the crackle starts as you sit")
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    T.eq(played[#played], S.FILES.flare, "the flare's whoosh")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    T.truthy(#stopped >= 1, "the crackle stops")
    T.eq(stopped[#stopped][2], math.floor(C.GLOW_OUT * 1000), "fading with the glow")
    -- A fight cuts it short (no rest wait, so the fire sits you down again).
    DaylightUI:Set("QoL", "campfireRest", 0)
    auras({})
    auras({ sitAura() })
    stub.EnterCombat()
    T.truthy(stopped[#stopped][2] <= 200, "a fight cuts it quickly")
    stub.LeaveCombat()
    -- Soft UI sounds off: silence.
    DaylightUI:Set("general", "sounds", false)
    local n = #played
    auras({})
    auras({ sitAura() })
    T.eq(C.state, "sitting")
    T.eq(#played, n, "nothing plays with sounds off")
    _G.PlaySoundFile, _G.StopSound = was, wasStop
end)

T.test("campfire: the preview plays both beats and ends on a move", function()
    local C = login()
    DaylightUI.RunCommand("campfire")
    T.eq(C.state, "sitting")
    T.truthy(frame():IsShown())
    stub.FireEvent("UNIT_AURA", "player")   -- no real campfire, so the preview isn't ended by it
    T.eq(C.state, "sitting")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    T.eq(C.state, "idle")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A stand-in area of another module, to see "Fade everything" reach it.
local function otherArea(key)
    local a = CreateFrame("Frame", nil, UIParent)
    a:Show()
    function a:IsMouseOver() return false end
    local path = "campTest" .. key:gsub("%.", "")
    DaylightUI.DB.General()[path] = { mode = "never" }
    DaylightUI.Fade.Register{ key = key, scope = "general", path = path, frames = function() return { a } end }
    return a
end

T.test("campfire: Fade everything hushes every area; the chat floats instead with Float the chat", function()
    local C = login()
    local buffs, chat = otherArea("Buffs.campTest"), otherArea("Chat.campTest")
    local said = {}
    DaylightUI.On("Campfire", function(on, snap) said[#said + 1] = { on, snap } end)
    T.eq(DaylightUI:Get("QoL", "campfireAll"), true, "Fade everything ships on")
    T.eq(DaylightUI:Get("QoL", "campfireChat"), true, "and Float the chat")
    DaylightUI:Set("QoL", "campfireAll", false)
    DaylightUI:Set("QoL", "campfireChat", false)
    stub.RunTimers()
    auras({ sitAura() })
    play(4)
    T.eq(area:GetAlpha(), 0, "the bars go")
    T.eq(buffs:GetAlpha(), 1, "both off: other areas stay")
    T.eq(chat:GetAlpha(), 1, "and the chat")
    T.eq(#said, 0, "both off: no float asked")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(1)
    T.eq(#said, 1, "the wake is said (the chat lets go)")
    T.falsy(said[1][1])

    DaylightUI:Set("QoL", "campfireAll", true)
    stub.RunTimers()
    auras({})
    auras({ sitAura() })
    play(4)
    T.eq(buffs:GetAlpha(), 0, "Fade everything: the buffs go too")
    T.eq(chat:GetAlpha(), 0, "and the chat")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(1)
    T.truthy(buffs:GetAlpha() > 0.9, "a move brings them back")

    DaylightUI:Set("QoL", "campfireChat", true)
    stub.RunTimers()
    local n = #said
    auras({})
    auras({ sitAura() })
    play(4)
    T.eq(said[n + 1][1], true, "the chat is asked to float")
    T.eq(buffs:GetAlpha(), 0, "everything else still goes")
    T.eq(chat:GetAlpha(), 1, "the chat isn't faded: its lines stay")
    stub.EnterCombat()
    T.eq(C.state, "idle")
    T.eq(said[#said][1], false, "a fight ends the float")
    T.truthy(said[#said][2], "at once")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- What the fire gives you: Camp Benefits' own words rise from it, the fire grows
-- through the minute, and its mark sits by the fire after the flare.
local DESC = "Rested experience gathers 2 times faster. You regenerate 5% health every 3 sec."

local function words(f)
    local out = {}
    for _, w in ipairs(f.words) do
        if w.fs:IsShown() and w.fs:GetAlpha() > 0 then out[#out + 1] = w.fs:GetText() end
    end
    return out
end

T.test("campfire: Camp Benefits' sentences rise from the fire one at a time, numbers colored", function()
    local C = login()
    stub.spells[BENEFITS] = { name = "Camp Benefits", desc = DESC }
    T.eq(#C.Lines(DESC), 2, "one line a sentence")
    T.eq(C.Lines("Heals 1.5 per sec.")[1], "Heals 1.5 per sec.", "a decimal isn't a sentence's end")
    T.eq(#C.Lines(nil), 0)
    auras({ sitAura() })
    local f = frame()
    play(1)
    T.eq(#words(f), 0, "the scene settles first")
    play(2.5)
    local seen = words(f)
    T.eq(#seen, 1, "one sentence at a time")
    T.truthy(seen[1]:find("Rested", 1, true), "the first one")
    T.truthy(seen[1]:find("|c", 1, true), "its numbers colored")
    local y1 = select(5, f.words[1].fs:GetPoint())
    play(1)
    T.truthy(select(5, f.words[1].fs:GetPoint()) > y1, "it drifts up")
    play(5)
    local text = table.concat(words(f), " ")
    T.truthy(text:find("regenerate", 1, true), "then the next")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(2)
    T.eq(#words(f), 0, "standing up takes them with the glow")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The glow fading out after you stand up takes the sentences and the mark with it,
-- so none are left flagged up for the next fire.
T.test("campfire: getting up leaves no sentence behind for the next fire", function()
    login()
    stub.spells[BENEFITS] = { name = "Camp Benefits", desc = DESC }
    auras({ sitAura() })
    local f = frame()
    play(4)
    T.truthy(#words(f) > 0, "a sentence is up")
    auras({})
    stub.RunTimers()   -- no Camp Benefits, so you stood up
    play(10)
    T.falsy(f:IsShown(), "the glow is gone")
    for _, w in ipairs(f.words) do T.falsy(w.fs:IsShown(), "no sentence left up") end
    T.falsy(f.mark:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("campfire: the fire grows slowly through the minute", function()
    local C = login()
    auras({ sitAura() })
    local f = frame()
    play(3)
    local early = f.dome:GetHeight()
    play(30)
    T.truthy(f.dome:GetHeight() > early * 1.03, "taller as the minute goes")
    T.truthy(f.dome:GetAlpha() > 0, "still the glow")
    T.eq(C.state, "sitting")
end)

T.test("campfire: after the flare its mark sits by the fire, then leaves; a fight takes it at once", function()
    local C = login()
    stub.spells[BENEFITS] = { name = "Camp Benefits", desc = DESC }
    auras({ sitAura() })
    play(3)
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    local f = frame()
    T.truthy(f.mark:IsShown(), "the mark comes")
    T.truthy(f.mark:GetAlpha() < 0.5, "easing in, not popping")
    play(1)
    T.truthy(f.mark:GetAlpha() > 0.9)
    T.falsy(f.mark:IsMouseEnabled(), "no mouse: the hushed bars sit there")
    local seen = words(f)
    T.eq(#seen, 1, "the sentence still up has made way")
    T.eq(seen[1], "Warmed by the fire", "a last line rises")
    play(8)
    T.falsy(f.mark:IsShown(), "gone after a while")

    login()
    auras({ sitAura() })
    play(3)
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    stub.EnterCombat()
    T.falsy(frame().mark:IsShown(), "a fight snaps it away")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("campfire: with motion off the sentences stand still over the fire and the mark shows at once", function()
    local C = login()
    stub.spells[BENEFITS] = { name = "Camp Benefits", desc = DESC }
    DaylightUI:Set("general", "motion", false)
    stub.RunTimers()
    auras({ sitAura() })
    local f = frame()
    T.eq(#words(f), 2, "both sentences, standing still")
    auras({ sitAura(), benefitsAura(GetTime() + 1800) })
    T.eq(#words(f), 0, "they make way for the mark")
    T.eq(f.mark:GetAlpha(), 1, "the mark at once")
    play(7)
    T.falsy(f.mark:IsShown(), "and gone after its while")
    T.eq(C.state, "resting")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The sleeping bag: Unroll Bag, then a stack of Well-Rested each minute, up to three.
local UNROLL, TRACK, RESTED = 429961, 429960, 429959
local function rested(n) return { spellId = RESTED, name = "Well-Rested", applications = n, expirationTime = GetTime() + 7200, duration = 7200 } end
local function unroll() stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", UNROLL) end

-- The timer is off as shipped: these tests switch it on.
local function bagLogin(before)
    local C = login(before)
    DaylightUI:Set("QoL", "sleepingBag", true)
    stub.RunTimers()
    return C
end

T.test("sleeping bag: laying it out starts a three-minute count to full Well-Rested", function()
    login()
    T.eq(DaylightUI:Get("QoL", "sleepingBag"), false, "off as shipped")
    local C = bagLogin()
    unroll()
    local f = frame()
    T.truthy(f and f:IsShown(), "shown without a fire")
    play(0.5)
    T.eq(f.bagTime:GetText(), "3:00")
    T.truthy(f.bagTime:GetAlpha() > 0.9, "eased in")
    T.eq(f.bagLabel:GetText(), "Well-Rested  0 / 3")
    T.eq(C.state, "idle", "no campfire scene: the UI stays")
    T.falsy(DaylightUI.Fade.Hushed())
    -- The first stack lands a minute in: the count keeps in step with it.
    play(59.5)
    auras({ rested(1) })
    play(0.1)
    T.eq(f.bagTime:GetText(), "2:00")
    T.eq(f.bagLabel:GetText(), "Well-Rested  1 / 3")
    auras({ rested(2) })
    play(0.1)
    T.eq(f.bagTime:GetText(), "1:00")
    auras({ rested(3) })
    play(0.1)
    T.eq(f.bagLabel:GetText(), "Fully rested")
    T.eq(f.bagTime:GetAlpha(), 0, "the time gives way")
    play(5)
    T.eq(f.bagLabel:GetAlpha(), 0, "then it leaves")
    T.falsy(f:IsShown(), "and the frame goes with nothing left on it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("sleeping bag: stacks already on count from where they are; full already says so", function()
    bagLogin(function() stub.SetAuras("player", "HELPFUL", { rested(2) }) end)
    unroll()
    local f = frame()
    play(0.5)
    T.eq(f.bagTime:GetText(), "1:00")
    play(5)
    auras({ rested(3) })
    play(5)
    unroll()
    play(0.3)
    T.eq(f.bagLabel:GetText(), "Fully rested")
end)

T.test("sleeping bag: walking off, a fight or switching it off ends the count; the bag's own aura is believed over walking", function()
    local C = bagLogin()
    unroll()
    play(1)
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(1)
    T.eq(frame().bagTime:GetAlpha(), 0, "walked off")
    T.falsy(frame():IsShown())
    -- The bag's aura read: walking about inside it keeps the count.
    auras({ { spellId = TRACK, name = "Well-Rested Tracking Aura" } })
    play(0.5)
    T.truthy(frame().bagTime:GetAlpha() > 0.9, "in the bag")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(1)
    T.truthy(frame().bagTime:GetAlpha() > 0.9, "still in the bag")
    auras({})
    play(1)
    T.eq(frame().bagTime:GetAlpha(), 0, "out of it")
    unroll()
    play(0.5)
    stub.EnterCombat()
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    T.eq(frame().bagLabel:GetAlpha(), 0, "a fight snaps it away")
    stub.LeaveCombat()
    unroll()
    play(0.5)
    DaylightUI:Set("QoL", "sleepingBag", false)
    stub.RunTimers()
    play(0.1)
    T.eq(frame().bagLabel:GetAlpha(), 0, "switched off")
    unroll()
    play(0.5)
    T.eq(frame().bagLabel:GetAlpha(), 0, "stays off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("sleeping bag: laying it out by the fire doesn't wake the campfire; the two counts share the screen", function()
    local C = bagLogin()
    auras({ sitAura() })
    play(3)
    stub.FireEvent("UNIT_SPELLCAST_SENT", "player", "", "x", UNROLL)
    T.eq(C.state, "sitting", "still by the fire")
    unroll()
    play(0.5)
    local f = frame()
    T.truthy(f.count:GetAlpha() > 0.3 and f.bagTime:GetAlpha() > 0.9, "both counts")
    local _, _, _, _, y1 = f.count:GetPoint(1)
    local _, _, _, _, y2 = f.bagTime:GetPoint(1)
    T.truthy(y2 < y1 - 30, "the bag's under the fire's")
    stub.FireEvent("PLAYER_STARTED_MOVING")
    play(3)
    T.eq(C.state, "idle")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
