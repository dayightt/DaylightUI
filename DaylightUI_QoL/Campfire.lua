-- Campfire scene. When Welcoming Campfire lands on you, the bottom of the screen
-- glows with firelight and embers while bars and unit frames fade out
-- (Fade.Hush, alpha only, so mouseover still shows them). When Camp Benefits
-- lands the fire flares and everything fades back in. A countdown sits over the
-- fire meanwhile. Moving, targeting, casting or standing up ends it early, and
-- combat ends it at once.
--
-- Camp Benefits' own description rises from the fire a sentence at a time, so
-- it works in every language. Auras are only read out of combat and outside the
-- client's restrictions, by spell id.
--
-- A sleeping bag gets a countdown in the same spot: resting in one adds a stack
-- of Well-Rested each minute, up to three, and with the UI faded at camp there's
-- no buff to watch. The count shows how long until all three are on.
--
-- One BACKGROUND-strata frame, no clicks, its OnUpdate only runs while shown.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Motion = DUI.Motion

local Campfire = {
    SITTING = { 1229739, 1289723 },   -- Welcoming Campfire (wago.tools SpellName, Forever 1.60.1)
    BENEFITS = 1229741,               -- Camp Benefits
    HUSH = { "ActionBars.", "UnitFrames." },
    -- "Fade everything at the campfire" (campfireAll): every module's areas; the chat left
    -- out when it floats instead (campfireChat), so its lines stay.
    HUSH_ALL = { "ActionBars.", "UnitFrames.", "Buffs.", "InfoPanel.", "Quests.", "Chat." },
    HUSH_ALL_FLOAT = { "ActionBars.", "UnitFrames.", "Buffs.", "InfoPanel.", "Quests." },
    DECIDE = 0.6,       -- s after Welcoming goes: Camp Benefits refreshed by then = the minute is done
    GLOW_IN = 2.5,      -- s for the glow to rise in
    GLOW_OUT = 1.2,     -- s to fade away on waking
    REST = 0.6,         -- the glow's level while you sit
    DOME = 0.34,        -- the wide glow's alpha at level 1
    CORE = 0.30,        -- the bright middle's
    TALL = 0.25,        -- the glow grows this share of its height per level (it leaps on the flare)
    WARM = 0.95,        -- the glow's level as the minute ends: it grows from REST while you wait
    MINUTE = 60,        -- s to wait when Welcoming Campfire's time can't be read
    -- The fire reapplies Welcoming Campfire every minute. For campfireRest
    -- minutes after a flare it's ignored, so the UI doesn't fade out every minute.
    -- The flare (the second beat): up fast, then a slow settle back to REST.
    FLARE = 2.0,        -- the glow's level at its peak
    FLARE_UP = 0.45,    -- s up to the peak
    FLARE_SETTLE = 3.5, -- s back down
    BLOOM = 1.6,        -- s of the bloom of light from the fire
    BLOOM_ALPHA = 0.55,
    EMBERS = 44,        -- embers in the pool
    RATE = 1.8,         -- embers a second while sitting
    BURST = 30,         -- fast embers at once on the flare
    PREVIEW_REST = 3,   -- the preview's second beat comes after this
    CRACKLE = 7.5,      -- s between copies of the crackle loop (the file is 8 s, ends faded: they blend)
    CUT = 0.15,         -- s a fight takes to cut the crackle
    PREVIEW_END = 10,   -- and it ends after this (10 s in all), if nothing woke it first
    -- The words in the smoke: Camp Benefits' sentences, one at a time.
    WORDS_FIRST = 2.5,  -- s after sitting before the first one (the scene settles first)
    WORDS_EVERY = 5.5,  -- s between them
    WORDS_LIFE = 7,     -- s each one drifts up
    WORDS_FROM = 0.25,  -- they start this share of the screen up
    WORDS_RISE = 0.16,  -- and rise this share of it
    WORDS_WIDE = 0.42,  -- they wrap at this share of the screen's width
    WORDS_POOL = 4,
    -- The buff's mark after the flare: its icon and name by the fire.
    MARK_AT = 0.2,      -- this share of the screen up
    MARK_ICON = 30,
    MARK_HOLD = 3,      -- s it stays; then the bars and frames come back as it leaves
    -- Firelight: the wide glow orange, the middle and the embers warmer gold.
    FIRE = { 1, 0.50, 0.18 },
    GOLD = { 1, 0.74, 0.36 },
    BLOOM_COLOR = { 1, 0.84, 0.58 },
    -- The sleeping bag (Cozy Sleeping Bag). Ids from wago.tools (Spell, SpellEffect,
    -- SpellAuraOptions, Forever 1.60.1), not yet checked on a character in game.
    BAG = {
        UNROLL = 429961,    -- Unroll Bag, the item's spell
        TRACK = 429960,     -- Well-Rested Tracking Aura: on you in the bag, a stack each minute (hidden, so maybe never readable)
        RESTED = 429959,    -- Well-Rested, stacks to 3
        STACKS = 3,
        EVERY = 60,         -- s per stack
        BELOW = 52,         -- the bag's count sits this far under the fire's
    },
}
Campfire.Random = math.random   -- tests fix it
ns.Campfire = Campfire
ns.features[#ns.features + 1] = Campfire

local MEDIA_GLOW = DUI.MEDIA .. "char-glow.png"

local mod, f, events, wired, crackle
Campfire.state = "idle"     -- idle | sitting | resting
local run = 0               -- each sit's id: a newer one stops the older one's timers
local benefitsAt            -- Camp Benefits' end time when you sat down (an old one doesn't count)
local wasSitting = false    -- Welcoming Campfire was on at the last look
local deciding, preview = false, false
local restedAt              -- GetTime() of the last real flare (not a preview)
-- The sleeping bag's count: endAt (GetTime when full), seen (the bag's own aura
-- was read this time), doneAt (clock when "Fully rested" came), preview.
local bag = { stacks = 0, a = 0 }

local function on(key) return mod ~= nil and mod.db ~= nil and mod.db[key] == true end

-- Still in the wait after the last flare (campfireRest minutes)?
function Campfire.Waiting()
    local mins = mod and mod.db and mod.db.campfireRest
    if type(mins) ~= "number" or mins <= 0 or not restedAt then return false end
    return GetTime() - restedAt < mins * 60
end
local function enabled() return on("campfire") end

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- Our own auras are plain only out of combat and out of restrictions.
local function readable()
    if DUI.Restricted() then return false end
    local S = C_Secrets
    if S and type(S.ShouldAurasBeSecret) == "function" then
        local ok, yes = pcall(S.ShouldAurasBeSecret)
        if not ok or secret(yes) or yes == true then return false end
    end
    return true
end

local function aura(id)
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if type(get) ~= "function" then return nil end
    local ok, a = pcall(get, "player", id)
    if ok and type(a) == "table" then return a end
    return nil
end

local function sitAura()
    for _, id in ipairs(Campfire.SITTING) do
        local a = aura(id)
        if a then return a end
    end
    return nil
end

local function sitting() return sitAura() ~= nil end

local function plain(v) return type(v) == "number" and not secret(v) and v > 0 end

-- s left of the minute and its whole length: Welcoming Campfire's own time,
-- else MINUTE.
local function minuteLeft()
    local a = readable() and sitAura()
    local e = a and a.expirationTime
    if plain(e) then
        local left = math.max(0, e - GetTime())
        local d = a.duration
        return left, plain(d) and math.max(d, left) or math.max(Campfire.MINUTE, left)
    end
    return Campfire.MINUTE, Campfire.MINUTE
end

-- A spell's text or icon through C_Spell (plain, or nil).
local function spellCall(name, id)
    local fn = C_Spell and C_Spell[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, id)
    if not ok or secret(v) then return nil end
    return v
end

-- Camp Benefits' description as lines: one per sentence, color codes out
-- (its numbers are colored our way, Tips.Numbers).
function Campfire.Lines(desc)
    local out = {}
    if type(desc) ~= "string" or secret(desc) then return out end
    desc = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    desc = desc:gsub("([%.!?])%s+", "%1\n")   -- a sentence's end (1.5 has no space after its dot)
    for line in (desc .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then out[#out + 1] = line end
    end
    return out
end

-- Camp Benefits' end time (0 if it can't be read), or nil without it.
local function benefits()
    local a = aura(Campfire.BENEFITS)
    if not a then return nil end
    local e = a.expirationTime
    if type(e) ~= "number" or secret(e) then return 0 end
    return e
end

----------------------------------------------------------------------------
-- The picture
----------------------------------------------------------------------------

local glow = { now = 0, from = 0, to = 0, t = 0, dur = 0 }
local glowNext                  -- { to, dur } to run once this ease lands (the flare settling)
local clock, spawnDebt = 0, 0
local bloomAt                   -- clock when the bloom started, or nil
local lines, lineAt, lineNext = {}, 1, 0   -- the sentences, the next one's index, when it rises
local markAt                    -- clock when the buff's mark came, or nil
local minuteEnd                 -- the minute's end (GetTime) while it runs, else nil
local timerA = 0                -- the count's own fade: in while the minute runs, out on the flare

local function glowTo(to, dur, after)
    if not Motion.On() then
        -- No motion: straight to where it ends up (a flare just settles).
        to = after and after[1] or to
        after = nil
        glow.now, dur = to, 0
    end
    glow.from, glow.to, glow.t, glow.dur = glow.now, to, 0, dur
    glowNext = after
end

local function ease(p) return 0.5 - 0.5 * math.cos(math.pi * p) end

local function tex(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(MEDIA_GLOW)
    t:SetBlendMode("ADD")
    return t
end

local function layout()
    local W = UIParent:GetWidth() or 1024
    local H = UIParent:GetHeight() or 768
    f.dome:SetSize(W * 1.5, H * 0.9)
    f.dome:ClearAllPoints()
    f.dome:SetPoint("CENTER", f, "BOTTOM", 0, -H * 0.12)
    f.core:SetSize(W * 0.8, H * 0.5)
    f.core:ClearAllPoints()
    f.core:SetPoint("CENTER", f, "BOTTOM", 0, -H * 0.08)
    f.flare:ClearAllPoints()
    f.flare:SetPoint("CENTER", f, "BOTTOM", 0, 0)
    for _, w in ipairs(f.words) do w.fs:SetWidth(W * Campfire.WORDS_WIDE) end
    f.mark:ClearAllPoints()
    f.mark:SetPoint("CENTER", f, "BOTTOM", 0, H * Campfire.MARK_AT)
    f.count:ClearAllPoints()
    f.count:SetPoint("CENTER", f, "BOTTOM", 0, H * Campfire.MARK_AT)
    f.bagTime:ClearAllPoints()
    f.bagTime:SetPoint("CENTER", f, "BOTTOM", 0, H * Campfire.MARK_AT - Campfire.BAG.BELOW)
    f.w, f.h = W, H
end

local step

local function build()
    if f then return f end
    f = CreateFrame("Frame", "DaylightUICampfire", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(0)
    f:EnableMouse(false)
    f:Hide()
    f.dome = tex(f, "BACKGROUND", 0)
    f.dome:SetVertexColor(Campfire.FIRE[1], Campfire.FIRE[2], Campfire.FIRE[3])
    f.core = tex(f, "BACKGROUND", 1)
    f.core:SetVertexColor(Campfire.GOLD[1], Campfire.GOLD[2], Campfire.GOLD[3])
    f.flare = tex(f, "BACKGROUND", 2)
    f.flare:SetVertexColor(Campfire.BLOOM_COLOR[1], Campfire.BLOOM_COLOR[2], Campfire.BLOOM_COLOR[3])
    f.flare:SetAlpha(0)
    f.embers = {}
    for i = 1, Campfire.EMBERS do
        local t = tex(f, "ARTWORK", 0)
        t:Hide()
        f.embers[i] = { tex = t }
    end
    local Style = DUI.Style
    f.words = {}
    for i = 1, Campfire.WORDS_POOL do
        local fs = Style.Text(f, Style.SIZE.head, "CENTER")
        fs:SetWordWrap(true)
        fs:Hide()
        f.words[i] = { fs = fs }
    end
    -- The buff's mark: its icon, its name under it. No mouse: it sits where
    -- the hushed bars are, and they take the mouse (and wake) there.
    local m = CreateFrame("Frame", nil, f)
    m:SetSize(Campfire.MARK_ICON, Campfire.MARK_ICON)
    m:EnableMouse(false)
    m:SetAlpha(0)
    m:Hide()
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    Style.CropIcon(m.icon)
    m.name = Style.Text(m, Style.SIZE.small, "CENTER")
    m.name:SetPoint("TOP", m, "BOTTOM", 0, -4)
    Style.InkText(m.name, "LABEL")
    f.mark = m
    -- The minute's time: the seconds left sit where the mark comes after.
    f.count = Style.Text(f, Style.SIZE.title, "CENTER")
    f.count:SetAlpha(0)
    -- The sleeping bag's time, its buff and stacks under it.
    f.bagTime = Style.Text(f, Style.SIZE.title, "CENTER")
    f.bagTime:SetAlpha(0)
    f.bagLabel = Style.Text(f, Style.SIZE.small, "CENTER")
    f.bagLabel:SetPoint("TOP", f.bagTime, "BOTTOM", 0, -4)
    f.bagLabel:SetAlpha(0)
    f:SetScript("OnUpdate", function(_, dt) step(dt) end)
    return f
end

-- An ember; fast = one of the flare's spray (quicker, bigger, brighter,
-- closer to the middle).
local function spawn(fast)
    local R = Campfire.Random
    for _, e in ipairs(f.embers) do
        if not e.tex:IsShown() then
            local spread = fast and 0.4 or 0.7
            e.x = f.w * (0.5 - spread / 2 + spread * (R() + R()) / 2)   -- most near the middle
            e.y = -4 + R() * f.h * 0.04
            e.vy = fast and 80 + R() * 90 or 22 + R() * 34
            e.life = fast and 2.2 + R() * 1.4 or 3 + R() * 2.5
            e.age = 0
            e.size = fast and 4 + R() * 5 or 3 + R() * 4
            e.sway, e.phase = 0.8 + R() * 1.6, R() * 6.28
            e.peak = fast and 0.8 + R() * 0.2 or 0.55 + R() * 0.45
            local k = R()   -- between the fire's orange and gold
            e.tex:SetVertexColor(1, Campfire.FIRE[2] + (Campfire.GOLD[2] - Campfire.FIRE[2]) * k,
                Campfire.FIRE[3] + (Campfire.GOLD[3] - Campfire.FIRE[3]) * k)
            e.tex:SetSize(e.size, e.size)
            e.tex:Show()
            return true
        end
    end
    return false
end

local function stepEmbers(dt, level)
    local fade = math.min(1, level / Campfire.REST)
    for _, e in ipairs(f.embers) do
        if e.tex:IsShown() then
            e.age = e.age + dt
            if e.age >= e.life then
                e.tex:Hide()
            else
                e.y = e.y + e.vy * dt
                local x = e.x + math.sin(e.age * e.sway + e.phase) * 9
                e.tex:ClearAllPoints()
                e.tex:SetPoint("CENTER", f, "BOTTOMLEFT", x, e.y)
                e.tex:SetAlpha(e.peak * math.sin(math.pi * e.age / e.life) * fade)
            end
        end
    end
end

-- A line rises from the fire; big = the flare's own, brighter.
local function rise(text, big)
    for _, w in ipairs(f.words) do
        if not w.fs:IsShown() then
            local Style = DUI.Style
            Style.SetTextSize(w.fs, big and Style.SIZE.title or Style.SIZE.head)
            Style.InkText(w.fs, big and "TITLE" or "TEXT")
            w.fs:SetText(big and text or DUI.Tips.Numbers(text))
            w.age, w.phase, w.out = 0, Campfire.Random() * 6.28, nil
            w.fs:SetAlpha(0)
            w.fs:Show()
            return w
        end
    end
    return nil
end

-- The lines drift up and sway a little: in, then slowly out.
local function stepWords(dt, fade)
    for _, w in ipairs(f.words) do
        if w.fs:IsShown() then
            w.age = w.age + dt
            local p = w.age / Campfire.WORDS_LIFE
            -- out: making way for the flare's line, leaving over NORMAL
            local away = w.out and 1 - (clock - w.out) / Motion.NORMAL or 1
            if p >= 1 or away <= 0 then
                w.fs:Hide()
            else
                local y = f.h * (Campfire.WORDS_FROM + Campfire.WORDS_RISE * (1 - (1 - p) ^ 1.6))
                w.fs:ClearAllPoints()
                w.fs:SetPoint("BOTTOM", f, "BOTTOM", math.sin(w.age * 0.6 + w.phase) * 6, y)
                w.fs:SetAlpha(math.min(1, p / 0.18) * math.min(1, (1 - p) / 0.45) * away * fade)
            end
        end
    end
end

local function hideMark()
    markAt = nil
    f.mark:Hide()
end

-- The buff's mark: in, a while, out.
local function stepMark(fade, moving)
    if not markAt then return end
    local m = f.mark
    local t, fadeT, hold = clock - markAt, Motion.SLOW, Campfire.MARK_HOLD
    if t >= (moving and hold + 2 * fadeT or hold) then return hideMark() end
    local a = 1
    if moving then a = math.min(1, t / fadeT, (hold + 2 * fadeT - t) / fadeT) end
    m:SetAlpha(a * fade)
end

-- The bloom: a burst of light from the fire, up in a blink, then fading
-- as it rises and widens.
local function stepBloom()
    if not bloomAt then return end
    local t = clock - bloomAt
    local up = 0.25
    if t >= Campfire.BLOOM then
        bloomAt = nil
        f.flare:SetAlpha(0)
        return
    end
    local a = t < up and t / up or (1 - (t - up) / (Campfire.BLOOM - up)) ^ 2
    local p = t / Campfire.BLOOM
    f.flare:SetSize(f.w * (0.45 + 0.35 * p), f.h * (0.5 + 0.7 * p))
    f.flare:SetAlpha(Campfire.BLOOM_ALPHA * a)
end

-- The minute's time: the count says the seconds. Not motion but
-- information, so it runs with motion off too (then without its fades).
local function stepTimer(dt, fade, moving)
    local goal = 0
    if minuteEnd then
        local left = math.max(0, minuteEnd - GetTime())
        local secs = math.ceil(left)
        if secs ~= f.count.secs then
            f.count.secs = secs
            f.count:SetText(tostring(secs))
        end
        if left > 0 then goal = 1 end
    end
    if not moving then
        timerA = goal
    elseif timerA < goal then
        timerA = math.min(goal, timerA + dt / Motion.NORMAL)
    elseif timerA > goal then
        timerA = math.max(goal, timerA - dt / Motion.NORMAL)
    end
    f.count:SetAlpha(timerA * fade)
end

-- The sleeping bag's count: the time to full Well-Rested, then "Fully rested"
-- for a moment. Information, so it runs with motion off too (without its fades).
local function bagShowing() return bag.endAt ~= nil or bag.doneAt ~= nil end

local function bagStacksText(n)
    local name = spellCall("GetSpellName", Campfire.BAG.RESTED)
    if type(name) ~= "string" then name = L["Well-Rested"] end
    return string.format("%s  %d / %d", name, n, Campfire.BAG.STACKS)
end

local function stepBag(dt, moving)
    local goal = 0
    if bag.endAt then
        local left = math.max(0, bag.endAt - GetTime())
        local secs = math.ceil(left)
        if secs ~= f.bagTime.secs then
            f.bagTime.secs = secs
            f.bagTime:SetText(string.format("%d:%02d", math.floor(secs / 60), secs % 60))
            -- The stacks on so far: one more each minute until the last lands.
            local B = Campfire.BAG
            local have = math.max(bag.stacks or 0, B.STACKS - math.ceil(left / B.EVERY))
            f.bagLabel:SetText(bagStacksText(math.min(have, B.STACKS - 1)))
        end
        goal = 1
    elseif bag.doneAt and clock - bag.doneAt < Campfire.MARK_HOLD then
        goal = 1
    end
    if not moving then
        bag.a = goal
    elseif bag.a < goal then
        bag.a = math.min(goal, bag.a + dt / Motion.NORMAL)
    elseif bag.a > goal then
        bag.a = math.max(goal, bag.a - dt / Motion.SLOW)
    end
    f.bagTime:SetAlpha(bag.full and 0 or bag.a)
    f.bagLabel:SetAlpha(bag.a)
    if bag.doneAt and goal == 0 and bag.a == 0 then bag.doneAt = nil end
end

-- Everything off: the glow, embers, sentences, mark and bloom, so the next
-- fire starts clean (none of them left flagged up).
local function hideAll()
    if not f then return end
    bloomAt = nil
    f.flare:SetAlpha(0)
    for _, e in ipairs(f.embers) do e.tex:Hide() end
    for _, w in ipairs(f.words) do w.fs:Hide() end
    hideMark()
    minuteEnd, timerA = nil, 0
    stepTimer(0, 0, false)
    glow.now, glow.from, glow.to, glowNext = 0, 0, 0, nil
    -- The sleeping bag's count stays (the fire may go while you lie in the bag).
    if not bagShowing() then f:Hide() end
end

step = function(dt)
    clock = clock + dt
    if glow.now ~= glow.to then
        glow.t = glow.t + dt
        local p = glow.dur > 0 and math.min(1, glow.t / glow.dur) or 1
        glow.now = p >= 1 and glow.to or glow.from + (glow.to - glow.from) * ease(p)
        if p >= 1 and glowNext then
            local n = glowNext
            glowTo(n[1], n[2])
        end
    end
    local level = glow.now
    local moving = Motion.On()
    -- Firelight: three slow waves each, never in step, so it never pulses.
    local flick, flick2 = 1, 1
    if moving then
        flick = 1 + 0.07 * math.sin(clock * 7.3) + 0.05 * math.sin(clock * 12.9 + 1.3) + 0.04 * math.sin(clock * 2.3)
        flick2 = 1 + 0.09 * math.sin(clock * 9.1 + 2.1) + 0.05 * math.sin(clock * 15.7) + 0.03 * math.sin(clock * 1.7 + 0.4)
    end
    f.dome:SetAlpha(math.min(0.8, math.max(0, Campfire.DOME * level * flick)))
    f.core:SetAlpha(math.min(0.8, math.max(0, Campfire.CORE * level * flick2)))
    local tall = 1 - Campfire.TALL + Campfire.TALL * level
    f.dome:SetSize(f.w * 1.5, f.h * 0.9 * tall)
    f.core:SetSize(f.w * 0.8, f.h * 0.5 * tall)
    if moving then
        if Campfire.state ~= "idle" then
            spawnDebt = spawnDebt + Campfire.RATE * dt
            while spawnDebt >= 1 do
                spawnDebt = spawnDebt - 1
                spawn()
            end
        end
        stepEmbers(dt, level)
        if Campfire.state == "sitting" and #lines > 0 and clock >= lineNext then
            rise(lines[lineAt])
            lineAt = lineAt % #lines + 1
            lineNext = clock + Campfire.WORDS_EVERY
        end
        stepWords(dt, math.min(1, level / Campfire.REST))
    end
    stepTimer(dt, math.min(1, level / Campfire.REST), moving)
    stepMark(math.min(1, level / Campfire.REST), moving)
    stepBloom()
    stepBag(dt, moving)
    if Campfire.state == "idle" and glow.now == 0 and glow.to == 0 and not bagShowing() then hideAll() end
end

----------------------------------------------------------------------------
-- The beats
----------------------------------------------------------------------------

-- What sitting fades: the bars and unit frames, or every area of ours.
function Campfire.Hushes()
    if not on("campfireAll") then return Campfire.HUSH end
    return on("campfireChat") and Campfire.HUSH_ALL_FLOAT or Campfire.HUSH_ALL
end

local function showFrame()
    build()
    layout()
    if not f:IsShown() then
        clock, spawnDebt = 0, 0
        f.dome:SetAlpha(0)
        f.core:SetAlpha(0)
        f:Show()
    end
end

-- Beat 1: you sat down.
local function sitDown(isPreview)
    showFrame()
    run = run + 1
    preview = isPreview == true
    deciding = false
    Campfire.state = "sitting"
    benefitsAt = benefits()
    -- The words: Camp Benefits' own text, read now (talents can change it).
    lines = Campfire.Lines(spellCall("GetSpellDescription", Campfire.BENEFITS))
    lineAt, lineNext = 1, clock + Campfire.WORDS_FIRST
    if not Motion.On() then
        -- No motion: the sentences stand still over the fire while you sit.
        for i = 1, math.min(#lines, #f.words) do
            local w = rise(lines[i])
            if w then
                w.fs:ClearAllPoints()
                w.fs:SetPoint("BOTTOM", f, "BOTTOM", 0, f.h * (Campfire.WORDS_FROM + Campfire.WORDS_RISE * (i - 1) / #lines))
                w.fs:SetAlpha(1)
            end
        end
    end
    -- The minute's time: the count (the preview's minute is short).
    local left = minuteLeft()
    if isPreview then left = Campfire.PREVIEW_REST end
    minuteEnd = GetTime() + left
    f.count.secs = nil
    DUI.Style.InkText(f.count, "pop")
    -- The fire rises in, then keeps growing slowly through the minute.
    local grow = left - Campfire.GLOW_IN
    glowTo(Campfire.REST, Campfire.GLOW_IN, grow > 1 and Motion.On() and { Campfire.WARM, grow } or nil)
    DUI.Fade.Hush("campfire", Campfire.Hushes())
    -- The chat module floats while this says so (Chat.FloatWanted).
    if on("campfireChat") then DUI.Fire("Campfire", true) end
    if not crackle then crackle = DUI.Sound.Loop("campfire", Campfire.CRACKLE) end
end

-- Beat 2: the minute is done (the preview and the translation sweep call it too).
function Campfire.Rested()
    if Campfire.state ~= "sitting" then return end
    Campfire.state = "resting"
    if not preview then restedAt = GetTime() end
    minuteEnd = nil   -- the count makes way for the mark
    glowTo(Campfire.FLARE, Campfire.FLARE_UP, { Campfire.REST, Campfire.FLARE_SETTLE })
    DUI.Sound.Play("flare")
    for _, w in ipairs(f.words) do
        if not Motion.On() then w.fs:Hide() elseif w.fs:IsShown() then w.out = clock end
    end
    -- The buff's mark by the fire, and a last line rising from it.
    local m = f.mark
    local icon = spellCall("GetSpellTexture", Campfire.BENEFITS)
    local name = spellCall("GetSpellName", Campfire.BENEFITS)
    m.icon:SetTexture(icon)
    m.icon:SetShown(icon ~= nil)
    m.name:SetText(type(name) == "string" and name or "")
    m:SetAlpha(0)
    m:Show()
    markAt = clock
    stepMark(1, Motion.On())
    if Motion.On() then
        rise(L["Warmed by the fire"], true)
        for _ = 1, Campfire.BURST do spawn(true) end
        bloomAt = clock
        stepBloom()
    end
    -- Rested: the bars and frames come back as the mark leaves (you may sit on
    -- by the fire; it glows on behind them until you move).
    local id = run
    C_Timer.After(Campfire.MARK_HOLD, function()
        if id == run and Campfire.state == "resting" then Campfire.Return() end
    end)
end

-- The hushed areas come back and the chat stops floating (snap: at once).
function Campfire.Return(snap)
    DUI.Fade.Unhush("campfire", snap)
    DUI.Fire("Campfire", false, snap)
end

-- Back to play: the bars come back, the glow fades (snap: all at once).
function Campfire.Wake(snap)
    if Campfire.state == "idle" then return end
    Campfire.state = "idle"
    run = run + 1
    preview, deciding = false, false
    Campfire.Return(snap)
    DUI.Sound.StopLoop(crackle, snap and Campfire.CUT or Campfire.GLOW_OUT)
    crackle = nil
    if snap or not Motion.On() then
        hideAll()
    else
        glowTo(0, Campfire.GLOW_OUT)
    end
end

-- Welcoming Campfire went: give Camp Benefits a moment to land.
local function decide(id)
    deciding = false
    if id ~= run or Campfire.state ~= "sitting" or not readable() then return end
    local b = benefits()
    if b and b ~= benefitsAt then
        Campfire.Rested()
    elseif not sitting() then
        Campfire.Wake()
    end
end

-- A look at your auras; quiet = only note what's on (login, a reload).
function Campfire.Check(quiet)
    if not readable() then return end
    local sit = sitting()
    if quiet or not enabled() or preview then
        wasSitting = sit
        return
    end
    local state = Campfire.state
    if sit and not wasSitting and state ~= "sitting" then
        if not Campfire.Waiting() then sitDown() end
    elseif state == "sitting" then
        local b = benefits()
        if b and b ~= benefitsAt then
            Campfire.Rested()
        elseif not sit and not deciding then
            deciding = true
            local id = run
            C_Timer.After(Campfire.DECIDE, function() decide(id) end)
        end
    end
    wasSitting = sit
end

----------------------------------------------------------------------------
-- The sleeping bag
----------------------------------------------------------------------------

local function bagOn() return on("sleepingBag") end

-- Well-Rested's stacks on you (0 without it), or nil when they can't be read.
local function restedStacks()
    if not readable() then return nil end
    local a = aura(Campfire.BAG.RESTED)
    if not a then return 0 end
    local n = a.applications
    if type(n) ~= "number" or secret(n) or n < 1 then return 1 end
    return n
end

-- All three stacks are on: the count gives way to "Fully rested" for a moment.
local function bagFull()
    showFrame()
    bag.endAt, bag.doneAt, bag.full = nil, clock, true
    f.bagTime.secs = nil
    f.bagLabel:SetText(L["Fully rested"])
    DUI.Style.InkText(f.bagLabel, "GOOD")
end

-- The count from now: a stack a minute until all are on. Called again on every
-- stack that lands, so it keeps in step with the game's own minute.
function Campfire.BagStart(stacks, isPreview)
    local B = Campfire.BAG
    stacks = stacks or 0
    if stacks >= B.STACKS then return bagFull() end
    showFrame()
    bag.preview = isPreview == true
    bag.doneAt, bag.full = nil, nil
    bag.endAt = GetTime() + B.EVERY * (B.STACKS - stacks)
    bag.stacks = stacks
    f.bagTime.secs = nil
    DUI.Style.InkText(f.bagTime, "pop")
    DUI.Style.InkText(f.bagLabel, "LABEL")
end

-- Out of the bag: the count leaves (snap: at once).
function Campfire.BagStop(snap)
    if not bagShowing() then return end
    bag.endAt, bag.seen, bag.preview = nil, nil, nil
    if snap or not Motion.On() then
        bag.doneAt, bag.a = nil, 0
        if f then
            f.bagTime:SetAlpha(0)
            f.bagLabel:SetAlpha(0)
        end
    else
        bag.doneAt = clock - Campfire.MARK_HOLD
    end
end

-- A look at Well-Rested and the bag's own aura; quiet = only note the stacks.
function Campfire.BagCheck(quiet)
    local stacks = restedStacks()
    if stacks == nil then return end
    local B = Campfire.BAG
    local inBag = aura(B.TRACK) ~= nil
    local before = bag.stacks or 0
    bag.stacks = stacks
    if quiet or not bagOn() or bag.preview then return end
    if inBag then bag.seen = true end
    if stacks > before then
        -- A stack only lands in a bag: start the count, or keep it in step.
        if stacks < B.STACKS then
            Campfire.BagStart(stacks)
        elseif bag.endAt then
            bagFull()
        end
    elseif inBag and not bagShowing() then
        Campfire.BagStart(stacks)
    elseif bag.endAt and bag.seen and not inBag then
        Campfire.BagStop()
    end
end

-- The bag was laid out: the count starts (the only sign when the bag's own
-- aura can't be read).
local function bagUnrolled()
    if not bagOn() then return end
    bag.seen = nil
    Campfire.BagStart(restedStacks() or bag.stacks or 0)
end

function Campfire.PreviewBag()
    if InCombatLockdown() then return end
    Campfire.BagStart(1, true)
end

function Campfire.Preview()
    if InCombatLockdown() then return end
    sitDown(true)
    local id = run
    C_Timer.After(Campfire.PREVIEW_REST, function() if id == run then Campfire.Rested() end end)
    C_Timer.After(Campfire.PREVIEW_END, function() if id == run then Campfire.Wake() end end)
end

local WAKE = { PLAYER_STARTED_MOVING = true, PLAYER_TARGET_CHANGED = true, UNIT_SPELLCAST_SENT = true }

local function onEvent(_, event, ...)
    if event == "UNIT_AURA" then
        Campfire.Check()
        Campfire.BagCheck()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
        Campfire.BagStop(true)
        Campfire.Wake(true)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Your own casts stay plain: unit, cast id, spell.
        if select(3, ...) == Campfire.BAG.UNROLL then bagUnrolled() end
    elseif event == "UNIT_SPELLCAST_SENT" and select(4, ...) == Campfire.BAG.UNROLL then
        -- Laying the bag out by the fire isn't getting up.
        return
    elseif WAKE[event] then
        -- Walking off ends the bag's count when its own aura can't say so.
        if event == "PLAYER_STARTED_MOVING" and (bag.preview or (bag.endAt and not bag.seen)) then
            Campfire.BagStop()
        end
        Campfire.Wake()
    end
end

local function wire()
    if wired then return end
    wired = true
    events = CreateFrame("Frame")
    events:RegisterUnitEvent("UNIT_AURA", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    events:RegisterEvent("PLAYER_STARTED_MOVING")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", onEvent)
    DUI.RegisterCommand("campfire", Campfire.Preview, L["/dui campfire - preview the campfire glow"])
    DUI.RegisterCommand("sleepingbag", Campfire.PreviewBag, L["/dui sleepingbag - preview the sleeping bag timer"])
end

function Campfire.Enable(m)
    mod = m
    wire()
    -- So its description is there by the time you sit.
    if C_Spell and type(C_Spell.RequestLoadSpellData) == "function" then
        pcall(C_Spell.RequestLoadSpellData, Campfire.BENEFITS)
    end
    Campfire.Check(true)
    Campfire.BagCheck(true)
end

function Campfire.Refresh(m)
    mod = m
    if not enabled() then Campfire.Wake(true) end
    if not bagOn() then Campfire.BagStop(true) end
end
