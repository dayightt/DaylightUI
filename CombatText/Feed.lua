-- Scrolling combat text feed: reads the game's combat text events the same
-- way Blizzard_CombatText does and hands them to a stage.
--
-- Everything GetCurrentEventInfo returns is secret, so values are only passed
-- through whole. type(x) == "nil" tells whether one arrived, and a FontString
-- shows it. When a value happens to be plain, the game's own checks (a heal's
-- name, a zero) run too. A gain's power type is secret as well, so gains are
-- shown as the player's main power.

local _, DUI = ...
local CT = DUI.CombatText
local Style = DUI.Style
local L = DUI.L

local function plain(v) return not (issecretvalue and issecretvalue(v)) end

-- Formats a number, keeping it secret if it came in secret.
local function amount(v)
    if plain(v) and type(v) ~= "number" then return v end
    if CT.Get("numbers") == "short" and type(AbbreviateNumbers) == "function" then return AbbreviateNumbers(v) end
    if type(BreakUpLargeNumbers) == "function" then return BreakUpLargeNumbers(v) end
    return v
end

local function sign(s) return CT.Get("signs") ~= false and s or "" end

-- Damage text, with an optional ! on crits.
local function hurt(kindCrit) return sign("-") .. "%s" .. ((kindCrit and CT.Get("critMark") == true) and "!" or "") end
local function mend(kindCrit) return sign("+") .. "%s" .. ((kindCrit and CT.Get("critMark") == true) and "!" or "") end

-- The game's own word for a message that has no number.
local function word(messageType)
    return _G["COMBAT_TEXT_" .. messageType] or _G[messageType]
end

local function healer(name)
    if CT.Get("healerNames") ~= true or type(name) == "nil" then return nil end
    if plain(name) and name == UnitName("player") then return nil end   -- name as the event reports it
    return name
end

-- Full text for a message (format plus values), or nil to show nothing.
-- Each branch mirrors one in Blizzard_CombatText's OnEvent.
local function compose(mt, data, a3, a4, crit)
    if mt == "DAMAGE" or mt == "SPELL_DAMAGE" or mt == "DAMAGE_SHIELD" or mt == "SPLIT_DAMAGE"
        or mt == "DAMAGE_CRIT" or mt == "SPELL_DAMAGE_CRIT" then
        if plain(data) and data == 0 then return end
        return hurt(crit), amount(data)
    end
    if mt == "HEAL" or mt == "PERIODIC_HEAL" or mt == "HEAL_CRIT" or mt == "PERIODIC_HEAL_CRIT" then
        local who = mt:find("PERIODIC", 1, true) == nil and healer(data)
        if who then return mend(crit) .. " [%s]", amount(a3), who end
        return mend(crit), amount(a3)
    end
    if mt == "HEAL_ABSORB" or mt == "PERIODIC_HEAL_ABSORB" or mt == "HEAL_CRIT_ABSORB" then
        return mend(crit) .. " " .. ABSORB_TRAILER, amount(a3), a4
    end
    if mt == "ABSORB_ADDED" then
        local who = healer(data)
        if who then return "+%s (%s) [%s]", amount(a3), COMBAT_TEXT_ABSORB, who end
        return "+%s (%s)", amount(a3), COMBAT_TEXT_ABSORB
    end
    if mt == "ENERGIZE" or mt == "PERIODIC_ENERGIZE" then
        if plain(data) and (tonumber(data) or 0) <= 0 then return end
        local _, token = UnitPowerType("player")
        local name = type(token) == "string" and _G[token] or nil
        if name then return "+%s %s", amount(data), name end
        return "+%s", amount(data)
    end
    if mt == "SPELL_CAST" or mt == "SPELL_AURA_START" or mt == "SPELL_AURA_START_HARMFUL" or mt == "SPELL_ACTIVE" then
        return "%s", data
    end
    if mt == "SPELL_AURA_END" or mt == "SPELL_AURA_END_HARMFUL" then
        return AURA_END, data
    end
    if mt == "BLOCK" or mt == "SPELL_BLOCK" then
        if type(a3) == "nil" then return "%s", COMBAT_TEXT_BLOCK end
        return hurt() .. " " .. BLOCK_TRAILER, amount(data), a3
    end
    if mt == "ABSORB" or mt == "SPELL_ABSORB" then
        if type(a3) == "nil" or (plain(data) and data == 0) then return "%s", COMBAT_TEXT_ABSORB end
        return hurt() .. " " .. ABSORB_TRAILER, amount(data), a3
    end
    if mt == "RESIST" or mt == "SPELL_RESIST" then
        if type(a3) == "nil" then return "%s", COMBAT_TEXT_RESIST end
        return hurt() .. " " .. RESIST_TRAILER, amount(data), a3
    end
    if mt == "FACTION" then
        if plain(a3) and (tonumber(a3) or 0) > 0 then return "%s +%s", data, a3 end
        return "%s %s", data, a3
    end
    if mt == "HONOR_GAINED" then
        if plain(data) and math.abs(tonumber(data) or 0) < 1 then return end
        return COMBAT_TEXT_HONOR_GAINED, data
    end
    local text = word(mt)
    if text then return "%s", text end
end

-- UNIT_COMBAT gives a hit's school and the combat text gives its amount, in
-- either order within the same frame. These hold whichever half came first.
local waitingLines, waitingSchools = {}, {}

local function fresh(list)
    local now = GetTime()
    while list[1] and list[1].at ~= now do table.remove(list, 1) end
end

local function paintSchool(line, mask)
    local c = CT.SchoolColor(mask)
    if c then
        line.fs:SetTextColor(c[1], c[2], c[3])
        line.tick:SetVertexColor(c[1], c[2], c[3], 0.85)
        line.flare:SetVertexColor(c[1], c[2], c[3])
    end
end

-- Sends one message to a stage. Partial resists with their kind turned off
-- show as plain damage, like the default UI.
function CT.Show(stage, mt, data, a3, a4)
    local kind = CT.MESSAGES[mt] or "other"
    local k = CT.Get("kinds." .. kind)
    if type(k) ~= "table" then return end
    if k.on == false then
        if kind ~= "reduce" or type(a3) == "nil" then return end
        kind = mt:sub(1, 5) == "SPELL" and "spell" or "hit"
        k = CT.Get("kinds." .. kind)
        mt = kind == "spell" and "SPELL_DAMAGE" or "DAMAGE"
        if type(k) ~= "table" or k.on == false then return end
    end
    local crit = CT.CRIT_TYPES[mt] == true
    local fmt, a, b, c = compose(mt, data, a3, a4, crit)
    if not fmt then return end
    local color = k.color
    local r, g, bl = color[1], color[2], color[3]
    if CT.KINDS[kind].power and CT.Get("kinds." .. kind .. ".power") ~= false then
        local _, token = UnitPowerType("player")
        if type(token) == "string" then
            local pr, pg, pb = Style.PowerColor(token)
            if type(pr) == "number" then r, g, bl = pr, pg, pb end
        end
    end
    local line = stage:Add(k.stream, r, g, bl, crit, fmt, a, b, c)
    return line, kind
end

-- Live stage

local stage, events
local warn = {}

function CT.Stage() return stage end
function CT.Warn() return warn end

-- Blizzard's frame stays hidden so its events cost nothing (its OnEvent bails
-- on the first line). Nothing is hooked.
local function hideGames()
    local f = _G.CombatText
    if type(f) == "table" and type(f.Hide) == "function" then pcall(f.Hide, f) end
end

local function setActiveUnit()
    if not (C_CombatText and C_CombatText.SetActiveUnit) then return end
    local unit = "player"
    if type(UnitHasVehicleUI) == "function" and UnitHasVehicleUI("player") then unit = "vehicle" end
    pcall(C_CombatText.SetActiveUnit, unit)
end

-- Low health/mana warning. The percent is secret, so a curve maps it directly
-- to the warning's alpha: 1 below the threshold, fading to 0 just above it.
local function curve()
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or type(c) ~= "table" and type(c) ~= "userdata" then return nil end
    local at = CT.Get("warnAt") or 0.3
    c:AddPoint(0, 0)        -- zero health means dead, not low
    c:AddPoint(0.001, 1)
    c:AddPoint(at, 1)
    c:AddPoint(math.min(at + 0.04, 1), 0)
    c:AddPoint(1, 0)
    return c
end

local function warnOn()
    local k = CT.Get("kinds.low")
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then return false end
    return CT.Live() and type(k) == "table" and k.on ~= false
end

local function paintWarn()
    if not warn.health then return end
    local on = warnOn()
    warn.health:SetShown(on)
    warn.mana:SetShown(on)
    if not on then return end
    if not warn.curve then warn.curve = curve() end
    if not warn.curve then
        warn.health:Hide()
        warn.mana:Hide()
        return
    end
    if type(UnitHealthPercent) == "function" then
        local ok, a = pcall(UnitHealthPercent, "player", true, warn.curve)
        if ok then warn.health:SetAlpha(a) end
    end
    local _, token = UnitPowerType("player")
    if token ~= "MANA" or type(UnitPowerPercent) ~= "function" then
        warn.mana:SetAlpha(0)
    else
        local ok, a = pcall(UnitPowerPercent, "player", Enum.PowerType.Mana, false, warn.curve)
        if ok then warn.mana:SetAlpha(a) end
    end
end

local function paintWarnLook()
    if not warn.health then return end
    local c = CT.Get("kinds.low.color")
    local s = CT.Get("streams.notes")
    local face = DUI.GameFonts.CombatTextWanted() or Style.FONT
    for _, fs in ipairs({ warn.health, warn.mana }) do
        fs:SetFont(face, s.size, CT.Get("outline") or "")
        fs:SetTextColor(c[1], c[2], c[3])
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.75)
    end
end

function CT.Live()
    return CT.Get("enabled") ~= false
end

-- The game only sends the feed while its own CVar is on, and it defaults to
-- off. Turn it on at login and again when something turns it off (game options,
-- another addon, a settings sync). Capped per session so a fight with another
-- addon can't loop.
CT.SWITCH_TRIES = 3
local switchTries = 0

local function gameSwitchOn(counted)
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return end
    if GetCVar(CT.GAME_SWITCH) ~= "0" then return end
    if counted then
        if switchTries >= CT.SWITCH_TRIES then return end
        switchTries = switchTries + 1
    end
    pcall(SetCVar, CT.GAME_SWITCH, "1")
end

local function onEvent(_, event, a1, a2, a3, a4, a5)
    if event == "COMBAT_TEXT_UPDATE" then
        if not plain(a1) or type(a1) ~= "string" then return end
        local data, x3, x4 = C_CombatText.GetCurrentEventInfo()
        local line, kind = CT.Show(stage, a1, data, x3, x4)
        if line and kind == "spell" and CT.Get("schoolColors") ~= false then
            fresh(waitingSchools)
            local s = table.remove(waitingSchools, 1)
            if s then paintSchool(line, s.mask)
            else waitingLines[#waitingLines + 1] = { at = GetTime(), line = line } end
        end
    elseif event == "UNIT_COMBAT" then
        -- unit, action, flag, amount, school. Action and school stay plain.
        if a2 ~= "WOUND" or not plain(a5) or a5 == 1 then return end
        fresh(waitingLines)
        local l = table.remove(waitingLines, 1)
        if l then paintSchool(l.line, a5)
        else waitingSchools[#waitingSchools + 1] = { at = GetTime(), mask = a5 } end
    elseif event == "PLAYER_REGEN_DISABLED" then
        CT.Show(stage, "ENTERING_COMBAT")
    elseif event == "PLAYER_REGEN_ENABLED" then
        CT.Show(stage, "LEAVING_COMBAT")
    elseif event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXHEALTH"
        or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        paintWarn()
    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITING_VEHICLE" then
        if a1 == "player" then setActiveUnit() end
    elseif event == "CVAR_UPDATE" then
        if type(a1) == "string" and a1:lower() == CT.GAME_SWITCH:lower() then gameSwitchOn(true) end
    end
end

local function listen()
    local on = CT.Live()
    events:UnregisterAllEvents()
    if on then
        events:RegisterEvent("COMBAT_TEXT_UPDATE")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterUnitEvent("UNIT_COMBAT", "player")
        events:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        events:RegisterUnitEvent("UNIT_EXITING_VEHICLE", "player")
        events:RegisterUnitEvent("UNIT_HEALTH", "player")
        events:RegisterEvent("PLAYER_DEAD")
        events:RegisterEvent("PLAYER_ALIVE")
        events:RegisterEvent("PLAYER_UNGHOST")
        events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        events:RegisterEvent("CVAR_UPDATE")
        gameSwitchOn(false)
        setActiveUnit()
    else
        stage:Clear()
    end
    hideGames()   -- off means nothing shows, including the game's
    paintWarn()
end

local function placeStreams()
    for _, id in ipairs(CT.STREAM_ORDER) do
        local anchor = stage.streams[id].anchor
        anchor:SetSize(180, 28)
        DUI.Movers.Register(anchor, "combattext." .. id, L["Combat text"] .. ": " .. L[CT.STREAMS[id].label], CT.STREAMS[id].place,
            { active = function() return CT.Live() and CT.Get("streams." .. id .. ".on") ~= false end })
    end
end

DUI.On("Login", function()
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("MEDIUM")
    stage = CT.NewStage(root)
    placeStreams()

    warn.health = root:CreateFontString(nil, "OVERLAY")
    warn.mana = root:CreateFontString(nil, "OVERLAY")
    warn.health:SetPoint("BOTTOM", stage.streams.notes.anchor, "TOP", 0, 6)
    warn.mana:SetPoint("BOTTOM", warn.health, "TOP", 0, 2)
    paintWarnLook()   -- set the font first, the client refuses text on a FontString without one
    warn.health:SetText(_G.HEALTH_LOW or L["Low health"])
    warn.mana:SetText(_G.MANA_LOW or L["Low mana"])

    events = CreateFrame("Frame")
    events:SetScript("OnEvent", onEvent)
    listen()
end)

DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= "Blizzard_CombatText" then return end
    hideGames()
    if stage and CT.Live() then setActiveUnit() end
end)

DUI.On("SettingChanged", function(scope, path)
    if scope ~= "general" or type(path) ~= "string" or not stage then return end
    if path == "sct.enabled" then
        listen()
        for _, id in ipairs(CT.STREAM_ORDER) do DUI.Movers.Recheck("combattext." .. id) end
    end
    if path:find("^sct%.") or path == "damage.sctFont" then
        if path == "sct.warnAt" then warn.curve = nil end
        paintWarnLook()
        paintWarn()
        for _, id in ipairs(CT.STREAM_ORDER) do
            if path == "sct.streams." .. id .. ".on" then DUI.Movers.Recheck("combattext." .. id) end
        end
    end
end)

DUI.On("StyleChanged", paintWarnLook)

-- Test mode and the options preview: the real path, fed made-up numbers

CT.DEMO_EVERY = 0.55
CT.DEMO = {
    { "DAMAGE", 412 }, { "HEAL", "", 918 }, { "SPELL_DAMAGE", 684, school = 4 }, { "DAMAGE_CRIT", 1386 },
    { "DODGE" }, { "SPELL_ACTIVE", L["Overpower"] }, { "PERIODIC_HEAL", "", 240 }, { "SPELL_DAMAGE", 523, school = 16 },
    { "HEAL_CRIT", "", 2140 }, { "DAMAGE", 298 }, { "BLOCK" }, { "SPELL_DAMAGE_CRIT", 1720, school = 32 },
    { "ABSORB_ADDED", "", 860 }, { "PARRY" }, { "ENERGIZE", 25 },
}

-- Pushes the next fake message onto a stage. Returns the line for tests.
function CT.DemoStep(s, n)
    local m = CT.DEMO[(n - 1) % #CT.DEMO + 1]
    local line, kind = CT.Show(s, m[1], m[2], m[3], m[4])
    if line and m.school and kind == "spell" and CT.Get("schoolColors") ~= false then paintSchool(line, m.school) end
    return line
end

local demoTicker, demoN = nil, 0

local function syncTest()
    local want = DUI.testMode and DUI.TestPartShown("combattext") and stage ~= nil and CT.Live()
    if want and not demoTicker then
        demoTicker = C_Timer.NewTicker(CT.DEMO_EVERY, function()
            demoN = demoN + 1
            CT.DemoStep(stage, demoN)
        end)
    elseif not want and demoTicker then
        demoTicker:Cancel()
        demoTicker = nil
    end
end

DUI.On("Login", function() DUI.RegisterTestPart("combattext", "Combat text", 86, function() return CT.Live() end) end)
DUI.On("TestModeChanged", syncTest)
DUI.On("TestPartChanged", syncTest)

-- Options preview: the three streams side by side at a smaller scale.
-- Only runs while visible.
CT.SAMPLE_HEIGHT = 190

function CT.Sample(parent)
    local s = {}
    local f = CreateFrame("Frame", nil, parent)
    s.frame = f
    local inner = CreateFrame("Frame", nil, f)
    inner:SetAllPoints(f)
    local mini = CT.NewStage(inner, { scale = 0.5, fontScale = 0.8 })

    local clock, n = CT.DEMO_EVERY, 0
    local run = CreateFrame("Frame", nil, f)
    run:SetScript("OnUpdate", function(_, dt)
        clock = clock + dt
        if clock >= CT.DEMO_EVERY then
            clock = 0
            n = n + 1
            CT.DemoStep(mini, n)
        end
    end)
    f:SetScript("OnHide", function() mini:Clear() end)

    function s.Refresh(width, maxHeight)
        local h = math.min(CT.SAMPLE_HEIGHT, maxHeight or CT.SAMPLE_HEIGHT)
        f:SetSize(width, h)
        mini.streams.hits.anchor:ClearAllPoints()
        mini.streams.hits.anchor:SetPoint("BOTTOM", f, "BOTTOM", -width * 0.2, h * 0.16)
        mini.streams.heals.anchor:ClearAllPoints()
        mini.streams.heals.anchor:SetPoint("BOTTOM", f, "BOTTOM", width * 0.2, h * 0.16)
        mini.streams.notes.anchor:ClearAllPoints()
        mini.streams.notes.anchor:SetPoint("TOP", f, "TOP", 0, -h * 0.2)
        mini:Restyle()
        return h
    end

    function s.Parts()
        return { { region = mini.streams.hits.anchor, label = L["Combat text"], keys = { "sct.crit" } } }
    end

    s.stage = mini
    return s
end
