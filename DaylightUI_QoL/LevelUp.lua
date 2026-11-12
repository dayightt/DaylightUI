-- Level-up banner. A thin light spreads from the top middle of the screen, the
-- level number rolls up like an odometer, and the stat gains fade in below it.
-- Replaces the game's level-up toast by setting the toast manager to alpha 0
-- while it shows one (no hook, no Hide). It takes no clicks, so it works in combat.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local LevelUp = {
    Y = -170,           -- the line's height from the screen's top
    WIDTH = 520,        -- the line at full spread
    LINE = 2,           -- its thickness
    HAZE = 90,          -- the warm glow round the line
    FLARE = 110,        -- the flash when the number lands
    NUMBER = 64, LABEL = 13, GAINS = 14,
    ROLL = 34,          -- px the numbers travel in the roll
    HOLD = 6.6,         -- seconds before it drifts away (7 s in all with the fade)
    DRIFT = 16,         -- px it rises as it goes
    GLOW = DUI.MEDIA .. "char-glow.png",
    SEP = "  ·  ",
    -- The preview's gains (the game sends the real ones).
    SAMPLE = { 18, 15, 1, 0, 2, 0, 1, 0 },
}
ns.LevelUp = LevelUp
ns.features[#ns.features + 1] = LevelUp

local mod, f, wired, watch
local run = 0           -- each show's id: a newer one stops the older one's timers
local blanked = false   -- the game's toast manager is at alpha 0 by us

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.levelUp == true end

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

local function build()
    if f then return f end
    f = CreateFrame("Frame", "DaylightUILevelUp", UIParent)
    DUI.Movers.FollowScale(f)
    f:SetSize(LevelUp.WIDTH, 1)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()
    -- The top is free again: a zone change or reputation banner that came meanwhile plays now.
    f:SetScript("OnHide", function()
        if ns.ZoneTitle then ns.ZoneTitle.Resume() end
        if ns.RepBanner then ns.RepBanner.Resume() end
    end)

    f.haze = f:CreateTexture(nil, "BACKGROUND")
    f.haze:SetTexture(LevelUp.GLOW)
    f.haze:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.haze:SetBlendMode("ADD")

    -- The line: two halves from the middle out, bright in the middle, gone
    -- at the ends (colored per show, paint()).
    f.left = f:CreateTexture(nil, "ARTWORK")
    f.left:SetColorTexture(1, 1, 1, 1)
    f.left:SetPoint("RIGHT", f, "CENTER", 0, 0)
    f.right = f:CreateTexture(nil, "ARTWORK")
    f.right:SetColorTexture(1, 1, 1, 1)
    f.right:SetPoint("LEFT", f, "CENTER", 0, 0)
    f.left:SetHeight(LevelUp.LINE)
    f.right:SetHeight(LevelUp.LINE)

    f.flare = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.flare:SetTexture(LevelUp.GLOW)
    f.flare:SetSize(LevelUp.FLARE * 2, LevelUp.FLARE)
    f.flare:SetPoint("CENTER", f, "CENTER", 0, LevelUp.NUMBER * 0.45)
    f.flare:SetVertexColor(1, 0.92, 0.78)
    f.flare:SetBlendMode("ADD")
    f.flare:Hide()

    -- The number roll: the old and new level inside a clip, like an odometer.
    f.roll = CreateFrame("Frame", nil, f)
    f.roll:SetSize(240, LevelUp.NUMBER + 10)
    f.roll:SetPoint("BOTTOM", f, "CENTER", 0, 6)
    f.roll:SetClipsChildren(true)
    f.old = Style.Text(f.roll, LevelUp.NUMBER, "CENTER")
    f.new = Style.Text(f.roll, LevelUp.NUMBER, "CENTER")
    f.old:SetTextColor(1, 0.95, 0.85)
    f.new:SetTextColor(1, 0.95, 0.85)

    f.label = Style.Text(f, LevelUp.LABEL, "CENTER")
    f.label:SetPoint("BOTTOM", f.roll, "TOP", 0, 0)

    f.gains = Style.Text(f, LevelUp.GAINS, "CENTER")
    f.gains:SetPoint("TOP", f, "CENTER", 0, -12)
    Style.InkText(f.gains, "TEXT")
    f.talents = Style.Text(f, LevelUp.GAINS, "CENTER")
    f.talents:SetPoint("TOP", f.gains, "BOTTOM", 0, -6)
    return f
end

-- Colors the light, haze and talents line. Done on every show so an accent
-- change is picked up.
local function paint()
    local r1, g1, b1 = Style.SplashAt(0)
    local rm, gm, bm = Style.SplashAt(0.5)
    local r2, g2, b2 = Style.SplashAt(1)
    f.left:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 0), CreateColor(rm, gm, bm, 1))
    f.right:SetGradient("HORIZONTAL", CreateColor(rm, gm, bm, 1), CreateColor(r2, g2, b2, 0))
    f.haze:SetVertexColor(Style.SplashAt(0.85))
    f.talents:SetTextColor(Style.SplashAt(0.85))
end

-- The line and its haze at a share p of their full spread.
local function spread(p)
    local w = math.max(1, LevelUp.WIDTH * p)
    f.left:SetWidth(w / 2)
    f.right:SetWidth(w / 2)
    f.haze:SetSize(w * 1.1, LevelUp.HAZE)
    f.haze:SetAlpha(0.45 * p)
end

local function place(p)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "TOP", 0, LevelUp.Y + LevelUp.DRIFT * p)
end

-- "+18 Health  ·  +2 Strength  ·  +1 Stamina", from PLAYER_LEVEL_UP's gains.
function LevelUp.GainsText(hp, power, str, agi, sta, int)
    local powerName
    if type(UnitPowerType) == "function" then
        local _, token = UnitPowerType("player")
        powerName = type(token) == "string" and _G[token] or nil
    end
    local parts = {}
    local good = DUI.Win.Parts.Hex(Style.INK.GOOD)
    local function add(n, name)
        if type(n) == "number" and not secret(n) and n > 0 and name then
            -- The "+N" green, the stat's name the line's warm text.
            local gain = string.gsub(string.format(L["+%d %s"], n, name), "(%+%d+)", good .. "%1|r", 1)
            parts[#parts + 1] = gain
        end
    end
    add(hp, HEALTH or L["Health"])
    add(power, powerName)
    add(str, SPELL_STAT1_NAME or L["Strength"])
    add(agi, SPELL_STAT2_NAME or L["Agility"])
    add(sta, SPELL_STAT3_NAME or L["Stamina"])
    add(int, SPELL_STAT4_NAME or L["Intellect"])
    return table.concat(parts, LevelUp.SEP)
end

function LevelUp.TalentsText(n)
    if type(n) ~= "number" or secret(n) or n <= 0 then return "" end
    if n == 1 then return L["1 new talent point"] end
    return string.format(L["%d new talent points"], n)
end

-- Plays it for `level`, with the gains in PLAYER_LEVEL_UP's order.
function LevelUp.Play(level, hp, power, talents, _, str, agi, sta, int)
    if type(level) ~= "number" or secret(level) then return end
    if ns.ZoneTitle then ns.ZoneTitle.Stop() end   -- the zone title steps aside
    if ns.RepBanner then ns.RepBanner.Stop() end   -- a reputation banner too, and plays after
    build()
    paint()
    run = run + 1
    local id = run
    local function later(t, fn)
        C_Timer.After(t, function() if id == run then fn() end end)
    end

    Style.PaintAccentText(f.label, ((LEVEL or L["Level"]):upper()))
    f.old:SetText(tostring(level - 1))
    f.new:SetText(tostring(level))
    f.gains:SetText(LevelUp.GainsText(hp, power, str, agi, sta, int))
    f.talents:SetText(LevelUp.TalentsText(talents))
    f.label:SetAlpha(0)
    f.old:SetAlpha(0)
    f.new:SetAlpha(0)
    f.gains:SetAlpha(0)
    f.talents:SetAlpha(0)
    f.flare:Hide()
    place(0)
    f:SetAlpha(1)
    f:Show()

    -- 1. The light spreads out from the middle.
    Motion.Tween("levelup:spread", 0, 1, Motion.SLOW, spread)
    -- 2. "LEVEL" and the old number come in over it.
    later(0.1, function()
        Motion.Fade(f.label, 0, 1, Motion.NORMAL)
        f.old:SetPoint("CENTER", f.roll, "CENTER", 0, 0)
        Motion.Fade(f.old, 0, 1, Motion.NORMAL)
    end)
    -- 3. The roll: the old number goes up and out, the new one comes up from under it and lands with a flare.
    later(0.45, function()
        Motion.Tween("levelup:roll", 0, 1, Motion.SLOW, function(p)
            f.old:SetPoint("CENTER", f.roll, "CENTER", 0, LevelUp.ROLL * p)
            f.old:SetAlpha(1 - p)
            f.new:SetPoint("CENTER", f.roll, "CENTER", 0, LevelUp.ROLL * (p - 1))
            f.new:SetAlpha(p)
        end, function() Motion.Flash(f.flare, Motion.SLOW * 2) end)
    end)
    -- 4. What you gained.
    later(0.85, function() Motion.Fade(f.gains, 0, 1, Motion.SLOW) end)
    later(1.05, function() Motion.Fade(f.talents, 0, 1, Motion.SLOW) end)
    -- 5. It drifts up and fades away.
    later(LevelUp.HOLD, function()
        Motion.Tween("levelup:out", 0, 1, Motion.SLOW, function(p)
            place(p)
            f:SetAlpha(1 - p)
        end, function() if id == run then f:Hide() end end)
    end)
end

-- Up on screen (the zone title waits for it).
function LevelUp.Showing() return f ~= nil and f:IsShown() end

function LevelUp.Preview()
    local level = type(UnitLevel) == "function" and UnitLevel("player") or 2
    if type(level) ~= "number" or secret(level) or level < 2 then level = 2 end
    LevelUp.Play(level, unpack(LevelUp.SAMPLE))
end

-- Keeps the game's toast manager at alpha 0, mouse off, while its current toast
-- is a level up. Checked every frame while the manager is shown, because its own
-- fade-in animates the alpha and it moves to the next toast without hiding.
local LEVEL_TOAST = Enum and Enum.EventToastEventType and Enum.EventToastEventType.LevelUp or 0

local function levelToast(m)
    local t = m.currentDisplayingToast
    local info = type(t) == "table" and t.toastInfo
    return type(info) == "table" and info.eventType == LEVEL_TOAST
end

function LevelUp.CheckToast()
    local m = _G.EventToastManagerFrame
    if type(m) ~= "table" then return end
    local want = enabled() and m:IsShown() and levelToast(m) or false
    if want then m:SetAlpha(0) end
    if want ~= blanked then
        blanked = want
        if not want then m:SetAlpha(1) end
        m:EnableMouse(not want)
    end
end

local function wire()
    if wired then return end
    wired = true
    DUI.RegisterEvent("PLAYER_LEVEL_UP", function(_, ...)
        if enabled() then LevelUp.Play(...) end
    end)
    DUI.RegisterCommand("levelup", LevelUp.Preview, L["/dui levelup - preview the level-up animation"])
    local m = _G.EventToastManagerFrame
    if type(m) == "table" and m.HookScript then
        watch = CreateFrame("Frame")
        m:HookScript("OnShow", function()
            LevelUp.Watch()
            LevelUp.CheckToast()
        end)
        m:HookScript("OnHide", function()
            LevelUp.CheckToast()
            watch:SetScript("OnUpdate", nil)
            if ns.ZoneTitle then ns.ZoneTitle.Resume() end
            if ns.RepBanner then ns.RepBanner.Resume() end
        end)
    end
end

-- The every-frame look runs only while it's on and the manager shows.
function LevelUp.Watch()
    if not watch then return end
    local m = _G.EventToastManagerFrame
    local want = enabled() and type(m) == "table" and m:IsShown()
    watch:SetScript("OnUpdate", want and LevelUp.CheckToast or nil)
end

function LevelUp.Enable(m)
    mod = m
    wire()
end

function LevelUp.Refresh(m)
    mod = m
    LevelUp.CheckToast()
    LevelUp.Watch()
    if not enabled() and f then run = run + 1; f:Hide() end
end
