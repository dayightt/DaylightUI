-- Damage meter built on the game's own data (C_DamageMeter). One row per
-- player, wheel to scroll, and a header with mode and fight pickers. The game
-- stores the fights; nothing is saved here. The game's own meter window is
-- turned off.
--
-- In combat amounts and names are secret. They go straight into bars and text
-- and are never compared or tested here. Class is always plain.
--
-- Meter.New builds one meter. ns.Meter is the panel's meter and also holds
-- what all meters share (modes, rows, colors). Extra windows: MeterWindows.lua.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Meter = {}
ns.Meter = Meter

Meter.SPACING = 1            -- between two bars (a window's own: rowGap)
Meter.TEXT = 11
Meter.REFRESH = 0.25          -- seconds between redraws: every one in combat, else when data changed (each reads a whole session; the bars glide between), else when data changed
Meter.WHITE = { 1, 1, 1 }    -- the names' color when none is set
-- Every mode the game tracks, in menu order. Labels are English here and
-- localized through L when drawn. Icons are Media/ui-meter-<icon>.png. `rate`
-- means it also has a per-second number; dps and hps rank by it.
Meter.MODES = {
    { key = "damage", group = "damage", rate = true, type = "DamageDone", label = L["DAMAGE"], name = "Damage done", icon = "damage", empty = "No damage yet." },
    { key = "dps", group = "damage", rate = true, byRate = true, type = "Dps", label = L["DPS"], name = "Damage per second", icon = "dps", empty = "No damage yet." },
    { key = "enemy", group = "damage", rate = true, type = "EnemyDamageTaken", label = L["ENEMY TAKEN"], name = "Enemy damage taken", icon = "enemy", empty = "No enemies yet." },
    { key = "healing", group = "healing", rate = true, type = "HealingDone", label = L["HEALING"], name = "Healing done", icon = "healing", empty = "No healing yet." },
    { key = "hps", group = "healing", rate = true, byRate = true, type = "Hps", label = L["HPS"], name = "Healing per second", icon = "hps", empty = "No healing yet." },
    { key = "absorbs", group = "healing", rate = true, type = "Absorbs", label = L["ABSORBS"], name = "Absorbs", icon = "absorbs", empty = "No absorbs yet." },
    { key = "taken", group = "taken", rate = true, type = "DamageTaken", label = L["TAKEN"], name = "Damage taken", icon = "taken", empty = "No damage taken yet." },
    { key = "avoidable", group = "taken", rate = true, type = "AvoidableDamageTaken", label = L["AVOIDABLE"], name = "Avoidable damage taken", icon = "avoidable", empty = "No avoidable damage yet." },
    { key = "interrupts", group = "utility", type = "Interrupts", label = L["INTERRUPTS"], name = "Interrupts", icon = "interrupts", empty = "No interrupts yet." },
    { key = "dispels", group = "utility", type = "Dispels", label = L["DISPELS"], name = "Dispels", icon = "dispels", empty = "No dispels yet." },
    { key = "deaths", group = "utility", type = "Deaths", label = L["DEATHS"], name = "Deaths", icon = "deaths", empty = "No deaths yet." },
}
-- The groups' headings in the mode menu.
Meter.GROUPS = { damage = "Damage", healing = "Healing", taken = "Taken", utility = "Utility" }
Meter.GROUP_ORDER = { "damage", "healing", "taken", "utility" }

-- A meter icon's file (tools/make_meter_icons.py).
function Meter.ICON(key) return DUI.MEDIA .. "ui-meter-" .. key .. ".png" end

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Past fights in test mode, most recent first (the first is the current one).
Meter.SAMPLE_FIGHTS = {
    { sessionID = 105, name = "Sadeas", durationSeconds = 94 },
    { sessionID = 104, name = "Chasmfiend", durationSeconds = 211 },
    { sessionID = 103, name = "Parshendi Warform", durationSeconds = 48 },
    { sessionID = 102, name = "Thunderclast", durationSeconds = 163 },
    { sessionID = 101, name = "Whitespine", durationSeconds = 37 },
}

-- A sample raid for test mode.
Meter.SAMPLE = {
    { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 2640, deathTimeSeconds = 71 },
    { name = "Shallan", classFilename = "MAGE", totalAmount = 2455 },
    { name = "Jasnah", classFilename = "WARLOCK", totalAmount = 2283 },
    { name = "Adolin", classFilename = "PALADIN", totalAmount = 2123 },
    { name = "Lift", classFilename = "ROGUE", totalAmount = 1974 },
    { name = "Navani", classFilename = "PRIEST", totalAmount = 1835 },
    { name = "Dalinar", classFilename = "WARRIOR", totalAmount = 1706 },
    { name = "Szeth", classFilename = "ROGUE", totalAmount = 1586 },
    { name = "Renarin", classFilename = "PRIEST", totalAmount = 1474 },
    { name = "Teft", classFilename = "WARRIOR", totalAmount = 1370 },
    { name = "Rock", classFilename = "HUNTER", totalAmount = 1274 },
    { name = "Sigzil", classFilename = "MAGE", totalAmount = 1184 },
    { name = "Lopen", classFilename = "ROGUE", totalAmount = 1101 },
    { name = "Moash", classFilename = "WARRIOR", totalAmount = 1023 },
    { name = "Venli", classFilename = "SHAMAN", totalAmount = 951 },
    { name = "Rlain", classFilename = "HUNTER", totalAmount = 884 },
    { name = "Taravangian", classFilename = "WARLOCK", totalAmount = 822 },
    { name = "Hoid", classFilename = "MAGE", totalAmount = 764 },
    { name = "Wit", classFilename = "DRUID", totalAmount = 710 },
    { name = "Syl", classFilename = "DRUID", totalAmount = 660 },
}

-- Test mode data for each mode, so switching modes visibly changes the list.
Meter.SAMPLE_SECONDS = 8     -- the sample fight's length, for its per-second numbers
local HEALS = { PRIEST = 3, DRUID = 2.6, PALADIN = 2.4, SHAMAN = 2.2 }
local TAKES = { WARRIOR = 4, PALADIN = 2.5, DRUID = 2 }
local KICKS = { ROGUE = 1, WARRIOR = 1, SHAMAN = 1, MAGE = 1 }
local CLEANSES = { PRIEST = 1, PALADIN = 1, SHAMAN = 1, MAGE = 1, DRUID = 1 }
local SHIELDS = { PRIEST = 1.4, PALADIN = 0.5 }
local ENEMIES = { "Chasmfiend", "Parshendi Warform", "Whitespine", "Axehound", "Thunderclast" }
local samples = {}

function Meter.SampleFor(key)
    if samples[key] then return samples[key] end
    local out = {}
    for i, s in ipairs(Meter.SAMPLE) do
        local c, amount = s.classFilename, s.totalAmount
        if key == "healing" or key == "hps" then amount = amount * (HEALS[c] or 0.15)
        elseif key == "absorbs" then amount = amount * (SHIELDS[c] or 0)
        elseif key == "taken" then amount = amount * (TAKES[c] or 0.6)
        elseif key == "avoidable" then amount = amount * ((i % 4) * 0.12)
        elseif key == "interrupts" then amount = KICKS[c] and (7 - i % 6) or 0
        elseif key == "dispels" then amount = CLEANSES[c] and (9 - i % 8) or 0
        elseif key == "deaths" then amount = (i % 7 == 1) and 1 or 0
        end
        if amount > 0 then
            out[#out + 1] = { name = s.name, classFilename = c, totalAmount = math.floor(amount),
                              amountPerSecond = math.floor(amount / Meter.SAMPLE_SECONDS),
                              deathTimeSeconds = key == "deaths" and (30 + i * 17) or nil }
        end
    end
    if key == "enemy" then
        out = {}
        for i, n in ipairs(ENEMIES) do
            local amount = 9000 - i * 1400
            out[i] = { name = n, totalAmount = amount, amountPerSecond = math.floor(amount / Meter.SAMPLE_SECONDS) }
        end
    end
    if key ~= "deaths" then table.sort(out, function(a, b) return a.totalAmount > b.totalAmount end) end
    samples[key] = out
    return out
end

-- Short numbers: whole below a thousand, one decimal with K, M or B above.
-- The game's shortener does it, so secret numbers work the same way.
Meter.TIERS = {
    { breakpoint = 1e9, abbreviation = "B", significandDivisor = 1e8, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e5, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1e3, abbreviation = "K", significandDivisor = 100, fractionDivisor = 10, abbreviationIsGlobal = false },
    { breakpoint = 1, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
    -- Below 1 (an early rate) must be whole too, and a secret can't be floored
    -- here. CreateAbbreviateConfig refuses a tier at 0, but passing it as
    -- `breakpointData` has no such rule.
    { breakpoint = 0, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false },
}
local shortOptions = { breakpointData = Meter.TIERS }
-- Should the client ever refuse that tier, the tiers from 1 up as a config
-- (below 1 then stays raw, as before), made once.
local fallback
local function fallbackOptions()
    if fallback == nil then
        fallback = false
        local tiers = {}
        for _, b in ipairs(Meter.TIERS) do
            if b.breakpoint >= 1 then tiers[#tiers + 1] = b end
        end
        local ok, c = pcall(CreateAbbreviateConfig, tiers)
        if ok and c then fallback = { config = c } end
    end
    return fallback or nil
end

-- Number format for meters, breakdowns and reports: shortened, or whole with
-- thousands separators (BreakUpLargeNumbers accepts secrets).
Meter.NUMBERS = { short = "Short (12.3K)", full = "Full (12,345)" }
Meter.NUMBER_ORDER = { "short", "full" }

function Meter.Short(n)
    local cfg = Meter.Config and Meter.Config()
    if type(n) == "number" and not (issecretvalue and issecretvalue(n)) then n = math.floor(n) end
    if cfg and cfg.numbers == "full" and BreakUpLargeNumbers then
        -- natural: whole, never "335.27" (a secret rate can't be floored here).
        local ok, s = pcall(BreakUpLargeNumbers, n, true)
        if ok then return s end
    end
    if shortOptions then
        local ok, s = pcall(AbbreviateNumbers, n, shortOptions)
        if ok then return s end
        shortOptions = false
    end
    return AbbreviateNumbers(n, fallbackOptions())
end

-- The GUID (or creature id) to query a source's spells with. In combat other
-- players' GUIDs are secret and the game won't accept them back, so this falls
-- back to your own (never secret) or the class+spec map from Meter.SnapGuids.
-- nil means wait.
Meter.guids = {}
function Meter.GuidOf(src)
    local guid, creature = src.sourceGUID, src.sourceCreatureID
    if not isSecret(guid) and not isSecret(creature) and (type(guid) == "string" or type(creature) == "number") then
        return guid, creature
    end
    -- A mob in a fight: its GUID is secret, its creature id is enough.
    if not isSecret(creature) and type(creature) == "number" then return nil, creature end
    local me = src.isLocalPlayer
    if not isSecret(me) and me == true then return UnitGUID("player"), nil end
    local key = Meter.WhoKey(src)
    local g = key and Meter.guids[key]
    if type(g) == "string" then return g, nil end
    return nil
end

-- Who a source is, without its name or GUID: its class, with its spec
-- when the game shows it (the game keeps the spec icon secret, even out
-- of a fight, though its docs say otherwise). nil: can't tell.
function Meter.WhoKey(src)
    local class, spec = src.classFilename, src.specIconID
    if isSecret(class) or type(class) ~= "string" or class == "" then return nil end
    if not isSecret(spec) and type(spec) == "number" then return class .. ":" .. spec end
    return class
end

-- Records class+spec -> GUID from plain sources out of combat, or false when
-- two players share both. Every meter adds to it; a roster change resets it.
-- Enemy lists are skipped.
function Meter.SnapGuids(sources, modeKey)
    if type(sources) ~= "table" or modeKey == "enemy" then return end
    local map = Meter.guids
    for _, s in ipairs(sources) do
        local guid = s.sourceGUID
        if isSecret(guid) then return end
        local key = Meter.WhoKey(s)
        if type(guid) == "string" and key then
            if map[key] == nil then map[key] = guid elseif map[key] ~= guid then map[key] = false end
        end
    end
end

-- Everyone's total in the shown fight, or nil while it's secret (a fight):
-- the session's own, else the plain sources' sum (samples have no session).
function Meter.Total(sources, session)
    local t = type(session) == "table" and session.totalAmount
    if type(t) == "number" and not isSecret(t) and t > 0 then return t end
    if type(sources) ~= "table" then return nil end
    local sum = 0
    for _, s in ipairs(sources) do
        local a = s.totalAmount
        if type(a) ~= "number" or isSecret(a) then return nil end
        sum = sum + a
    end
    return sum > 0 and sum or nil
end

-- A row's amount as SetFormattedText arguments, e.g. "2.6K (330, 18%)".
-- Pieces come from the client's shortener so secret amounts pass through.
-- The share is computed here, so only from plain numbers (never in combat).
local SHAPES = { "%s", "%s (%s)", "%s (%s, %s)" }
local pieces = {}
-- The per-second number: the game's, or (when it gives none or 0 for a
-- plain total, as it can outside a fight) the total over the fight's length.
function Meter.Rate(src, seconds)
    local rate, amount = src.amountPerSecond, src.totalAmount
    -- Out of a fight the game's own number can be far off (6234 damage
    -- read 0.0015 a second): with a plain total and length, worked out here.
    if type(amount) == "number" and not isSecret(amount)
       and type(seconds) == "number" and not isSecret(seconds) and seconds > 0 then
        return amount / seconds
    end
    return rate
end

-- Per second first where a mode has it ("330 (2.6K, 18%)"), else the total.
function Meter.Amount(src, md, cfg, total, seconds)
    local amount = src.totalAmount
    if type(amount) == "nil" then amount = 0 end
    for i = #pieces, 1, -1 do pieces[i] = nil end
    -- (The rate may be secret: only ever asked whether it's there.)
    if md.rate and cfg.showRate ~= false then
        local rate = Meter.Rate(src, seconds)
        if type(rate) ~= "nil" then pieces[#pieces + 1] = Meter.Short(rate) end
    end
    if cfg.showTotal ~= false then pieces[#pieces + 1] = Meter.Short(amount) end
    if cfg.showShare ~= false and type(total) == "number" and type(amount) == "number" and not isSecret(amount) then
        pieces[#pieces + 1] = math.floor(100 * amount / total + 0.5) .. "%"
    end
    if #pieces == 0 then pieces[1] = Meter.Short(amount) end
    return SHAPES[#pieces], pieces[1], pieces[2], pieces[3]
end

-- A row's name and amount colors: each in the player's class color
-- (cfg.classText), else the name in cfg.nameColor and the amount white.
function Meter.PaintText(row, token, cfg)
    if cfg.classText == true then
        local r, g, b = Style.ClassTextColor(token)
        row.name:SetTextColor(r, g, b)
        row.amount:SetTextColor(r, g, b)
        return
    end
    local nc = type(cfg.nameColor) == "table" and cfg.nameColor or Meter.WHITE
    row.name:SetTextColor(nc[1], nc[2], nc[3])
    local v = Style.INK.VALUE
    row.amount:SetTextColor(v[1], v[2], v[3])
end

-- Color a bar for a source: custom color, class gradient, or flat class color.
-- c is the color settings to use; defaults to the first meter's.
function Meter.PaintBar(sb, src, token, c)
    local cfg = c or Meter.Config()
    local G = cfg.gradient == true and DUI.Gradients
    if cfg.barColor == "custom" then
        local c = cfg.barCustom
        if G then G.PaintFrom(sb, c)
        else Style.SetBarColor(sb, Style.Soften(c[1], c[2], c[3])) end
    elseif G then
        token = token or src.classFilename
        if issecretvalue and issecretvalue(token) or type(token) ~= "string"
           or not G.Has(token) then token = "FALLBACK" end
        G.Paint(sb, token)
    else
        Style.SetBarColor(sb, Style.ClassColor(src.classFilename))
    end
end

-- ---------------------------------------------------------------------
-- What every meter shares
-- ---------------------------------------------------------------------

local all = {}               -- every meter made, the first one first
Meter.MENU_WIDTH = 200       -- the drop-down lists, wider than their buttons

local function sessionType(session)
    local E = Enum and Enum.DamageMeterSessionType
    if not E then return nil end
    return session == "overall" and E.Overall or E.Current
end

local function shortName(name)
    if type(name) == "nil" then return "" end
    if Ambiguate then
        local ok, n = pcall(Ambiguate, name, "short")
        if ok and type(n) ~= "nil" then return n end
    end
    return name
end

local function clock(s) return DUI.FormatClock(s) end

-- A fight's name: what the game calls it (usually what was fought), or
-- "Combat" when it has none or keeps it secret.
local function fightName(f)
    local n = f and f.name
    if type(n) ~= "string" or (issecretvalue and issecretvalue(n)) or n == "" then return L["Combat"] end
    return n
end

-- What a row was last painted for: its class (plain), "?" without one, or
-- nil for a secret one (painted every time, never compared).
local function paintKey(token)
    if issecretvalue and issecretvalue(token) then return nil end
    if type(token) ~= "string" then return "?" end
    return token
end
Meter.PaintKey = paintKey   -- the threat meter's rows too

-- The game keeps one set of fights for every meter: clearing them also
-- drops each meter's picked fight.
function Meter.ResetAll()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then pcall(C_DamageMeter.ResetAllCombatSessions) end
    Meter.FightsChanged()
    for _, m in ipairs(all) do
        if not m.dead then m.Cleared() end
    end
end

local function askReset()
    StaticPopupDialogs.DAYLIGHTUI_METER_RESET = StaticPopupDialogs.DAYLIGHTUI_METER_RESET or {
        text = L["Clear every fight from the damage meter?"],
        button1 = YES or L["Yes"], button2 = NO or L["No"],
        OnAccept = function() Meter.ResetAll() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("DAYLIGHTUI_METER_RESET")
end

local function hasFights()
    local ok, list = pcall(C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions or error)
    return not ok or type(list) ~= "table" or #list > 0
end

-- Keep, ask or clear when joining a group or entering an instance. With
-- nothing to clear it never asks.
local function clearFor(choice)
    if choice == "reset" then Meter.ResetAll()
    elseif choice == "ask" and hasFights() then askReset() end
end

-- Which instance you're in: its id, or nil outside.
local function instanceNow()
    if not IsInInstance or IsInInstance() ~= true then return nil end
    if type(GetInstanceInfo) ~= "function" then return true end
    return select(8, GetInstanceInfo()) or true
end

-- The game's fight list, newest first. Shared by all meters and only re-read
-- when it changes, since the header asks for it on every redraw.
local fightList, fightsStale = {}, true
function Meter.FightsChanged() fightsStale = true end
function Meter.FightList()
    if not fightsStale then return fightList end
    fightsStale = false
    fightList = {}
    local get = C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions
    local ok, list = pcall(get or error)
    if not ok or type(list) ~= "table" then return fightList end
    for i = #list, 1, -1 do fightList[#fightList + 1] = list[i] end
    return fightList
end

-- With meters.sameFight, an earlier fight picked in one window shows in every
-- window set to Current. nil returns them to the current fight.
local function meters()
    local db = ns.module and ns.module.db
    return type(db) == "table" and type(db.meters) == "table" and db.meters or {}
end
function Meter.ShareFight(from, id)
    if meters().sameFight == false then return end
    for _, m in ipairs(all) do
        local c = m.Config()
        if m ~= from and not m.dead and c and c.session == "current" then m.ShowFight(id) end
    end
end

-- A pull: every window showing an earlier fight goes back to its own
-- Current or Overall (meters.backToCurrent).
function Meter.BackToCurrent()
    if meters().backToCurrent == false then return end
    for _, m in ipairs(all) do
        if not m.dead and m.fight then m.ShowFight(nil) end
    end
end

-- Registers a non-meter view (Summary.lua) with the shared ticker, fight picks
-- and Reset. It must answer Tick, MarkDirty, Cleared, Config, ShowFight and
-- have .fight / .dead like a meter.
function Meter.Register(view) all[#all + 1] = view end

-- One set of events and one ticker for every meter.
local shared = false
local function share()
    if shared then return end
    shared = true
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        Meter.FightsChanged()
        Meter.BackToCurrent()
    end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", Meter.FightsChanged)
    -- Who's who starts over with a new group.
    DUI.RegisterEvent("GROUP_ROSTER_UPDATE", function()
        for k in pairs(Meter.guids) do Meter.guids[k] = nil end
    end)
    for _, e in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_RESET" }) do
        pcall(DUI.RegisterEvent, e, Meter.FightsChanged)
    end
    for _, e in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
                         "DAMAGE_METER_RESET", "GROUP_ROSTER_UPDATE" }) do
        pcall(DUI.RegisterEvent, e, function() for _, m in ipairs(all) do m.MarkDirty() end end)
    end
    -- In a fight the numbers are read again every tick, not only when the
    -- game says they changed (its word comes less often than the numbers do).
    C_Timer.NewTicker(Meter.REFRESH, function()
        local fight = InCombatLockdown and InCombatLockdown() or false
        for _, m in ipairs(all) do m.Tick(fight) end
    end)
end

-- ---------------------------------------------------------------------
-- One meter
-- ---------------------------------------------------------------------

-- Fills m (or a new table) with one meter's functions and returns it.
--   opts.id    window id, "main" for the panel's meter
--   opts.path  settings path: "meter" or "meters.windows.<id>"
--   opts.part  its test box
--   opts.main  true for the panel's meter
-- m.dead is set once its window is removed; it never draws again.
function Meter.New(m, opts)
    m = m or {}
    local path, part, main = opts.path, opts.part, opts.main == true
    m.id = opts.id or "main"
    local rows, area, cfg = {}, nil, nil
    local snap = true            -- the next draw jumps straight to its values
    -- What's on show (mode, session, fight), to notice a change.
    local shownMode, shownSession, shownFight
    local dirty = true
    local offset = 0             -- rows scrolled past, by the mouse wheel
    local whole = 1              -- rows that fit completely
    local reserve = 0            -- room kept free at the bottom (the threat meter under it)
    local header                 -- MeterHeader.lua: mode, fight, clock, the buttons
    local moddb                  -- the module's settings (the data texts' size)
    m.fight = nil                -- an earlier fight's session id, while one is picked
    m.hovered = nil              -- the bar under the mouse

    function m.Config() return cfg end
    -- Test mode with this meter's sample wanted (its test box can untick it:
    -- then it shows as it would, with the real fights).
    function m.Sample() return DUI.testMode and DUI.TestPartShown(part) or false end
    function m.Paint(sb, src) Meter.PaintBar(sb, src, nil, cfg) end

    -- The text size relative to its default; the hover breakdown follows it.
    function m.TextScale()
        local size = cfg and cfg.textSize
        if type(size) ~= "number" then return 1 end
        return size / Meter.TEXT
    end

    local function mode()
        for _, md in ipairs(Meter.MODES) do if md.key == cfg.mode then return md end end
        return Meter.MODES[1]
    end

    -- For the breakdown: the mode, and the fight being shown.
    m.Mode = function() return mode() end
    m.SessionType = function() return sessionType(cfg.session) end

    -- Every fight the game kept, most recent first: the current one, then
    -- those before it. Read again only when the game says the list changed
    -- (Meter.FightsChanged), not on every redraw in a fight.
    function m.Fights()
        if m.Sample() then return Meter.SAMPLE_FIGHTS end
        return Meter.FightList()
    end

    -- The current list of sources, best first, or nil; then the session.
    function m.Sources()
        if m.Sample() then return Meter.SampleFor(cfg.mode) end
        local E = Enum and Enum.DamageMeterType
        local mt = E and E[mode().type]
        if mt == nil or not C_DamageMeter then return nil end
        local ok, s
        if m.fight then
            ok, s = pcall(C_DamageMeter.GetCombatSessionFromID or error, m.fight, mt)
            -- The game dropped that fight: back to the current one.
            if not ok or type(s) ~= "table" then m.fight = nil end
        end
        if not m.fight then
            local st = sessionType(cfg.session)
            if st == nil then return nil end
            ok, s = pcall(C_DamageMeter.GetCombatSessionFromType or error, st, mt)
        end
        if ok and type(s) == "table" then return s.combatSources, s end
    end

    -- What the shown fight is called, for a report: "Overall", or the
    -- fight's name; then its length in seconds, when the list has it.
    -- How long the shown fight ran (plain), or nil: the session's own, else
    -- the game's clock for this window's Current or Overall, else the fight list's.
    function m.Seconds(session)
        local s = type(session) == "table" and session.durationSeconds
        if type(s) == "number" and not isSecret(s) and s > 0 then return s end
        if not m.fight and not m.Sample() and C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
            local st = m.SessionType()
            if st ~= nil then
                local ok, d = pcall(C_DamageMeter.GetSessionDurationSeconds, st)
                if ok and type(d) == "number" and not isSecret(d) and d > 0 then return d end
            end
        end
        if m.Sample() then return Meter.SAMPLE_SECONDS end
        local _, length = m.FightTitle()
        if type(length) == "number" and not isSecret(length) and length > 0 then return length end
    end

    function m.FightTitle()
        if m.fight then
            for _, f in ipairs(m.Fights()) do
                if f.sessionID == m.fight then return fightName(f), f.durationSeconds end
            end
        elseif cfg.session == "overall" then
            return L["Overall"]
        end
        local cur = m.Fights()[1]
        if cur then return fightName(cur), cur.durationSeconds end
        return L["Current fight"]
    end

    m.rows = rows

    local function newRow(i)
        local row = ns.Rows.New(area, cfg.textSize or Meter.TEXT)
        row.meter = m
        -- A click: the player's breakdown window; Shift: report their spells.
        -- The mouse coming in straight onto a row starts the hover too.
        row:EnableMouse(true)
        row:SetScript("OnEnter", function() if m.HoverStart then m.HoverStart() end end)
        row:SetScript("OnMouseUp", function(self, button) m.RowClick(self, button) end)
        rows[i] = row
        return row
    end

    function m.RowClick(row, button)
        local src = row.src
        if not (src and row:IsShown()) then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            ns.Report.Toggle(m, nil, src)
        elseif button == "LeftButton" and ns.BreakdownWindow then
            ns.BreakdownWindow.Open(m, src)
        end
    end

    -- A row's spot: its place down the column (under the header), dy off it
    -- while it glides.
    local step, top = 1, 0
    local function place(bar, dy)
        bar.dy = dy
        local y = -top - (bar.slot - 1) * step + dy
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", area, "TOPLEFT", 0, y)
        bar:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, y)
    end

    -- Lays out rows down the whole area: every one that fits, plus one more cut
    -- off at the bottom edge, so the column never ends in a gap.
    -- With room kept at the bottom, the column ends on a whole row instead.
    local function layoutRows()
        local h = cfg.rowHeight
        local gap = type(cfg.rowGap) == "number" and cfg.rowGap or Meter.SPACING
        step = h + gap
        top = ns.MeterHeader.Height(cfg)
        local span = (area:GetHeight() - top - reserve + gap) / step
        whole = math.max(1, math.floor(span))
        local n = reserve > 0 and whole or math.max(1, math.ceil(span))
        area:SetClipsChildren(true)
        for i = 1, math.max(n, #rows) do
            local bar = rows[i] or (i <= n and newRow(i))
            if bar then
                bar.slot = i
                place(bar, 0)
                bar:SetHeight(h)
                Style.SetTextSize(bar.name, cfg.textSize or Meter.TEXT)
                Style.SetTextSize(bar.amount, cfg.textSize or Meter.TEXT)
                ns.Rows.Track(bar, cfg.trackAlpha)
                ns.Rows.Layout(bar, cfg)
                bar.fits = i <= n
                if not bar.fits then bar:Hide() end
                -- Painted and shown again on the next draw, in the new look.
                bar.painted, bar.on, bar.iconFile, bar.mine = nil, bar:IsShown(), false, nil
            end
        end
    end

    -- Where each player was drawn last time (by plain name: out of a fight
    -- and in samples only), so a row taking someone who moved glides from
    -- their old place.
    local lastPlace, nextPlace = {}, {}
    local function glide(bar, key)
        local was = key and lastPlace[key]
        if snap or not was or was == bar.slot then
            if bar.dy ~= 0 then
                DUI.Motion.Tween(bar, 0, 0, 0)
                place(bar, 0)
            end
            return
        end
        local from = -(was - bar.slot) * step
        DUI.Motion.Tween(bar, from, 0, DUI.Motion.NORMAL, function(dy) place(bar, dy) end)
    end

    -- "Nothing here": no fights at all, or nobody in this mode yet.
    local function showEmpty(on, md)
        local e = m.empty
        if not e then return end
        if on then
            local none = not m.Sample() and #m.Fights() == 0
            e:SetText(none and L["No fights yet."] or L[md.empty or "No fights yet."])
            if not e:IsShown() then DUI.Motion.AlphaTo(e, 1, DUI.Motion.FAST) end
        elseif e:IsShown() then
            e:Hide()   -- the rows coming in take its place at once
        end
    end

    function m.MarkDirty() dirty = true end

    -- From the shared ticker: a draw when something changed, or every tick in a fight.
    function m.Tick(fight)
        if area and cfg and not m.dead and (dirty or fight) then m.Draw() end
    end

    -- Keeps px free at the meter's bottom (0: none): the rows stop above it.
    -- Laid out again only on a change.
    function m.Reserve(px)
        if px == reserve then return end
        reserve = px
        if not (area and cfg) then return end
        layoutRows()
        m.Draw()
    end
    m.Reserved = function() return reserve end

    function m.Draw()
        dirty = false
        -- A different mode or fight starts at the top and jumps straight there,
        -- rather than bars gliding from one player's number to another's.
        if cfg.mode ~= shownMode or cfg.session ~= shownSession or m.fight ~= shownFight then
            shownMode, shownSession, shownFight = cfg.mode, cfg.session, m.fight
            offset = 0
            snap = true
        end
        -- On screen only: a hidden window (or one waiting for a group or a
        -- fight) reads nothing; it's drawn again as it shows (OnShow, Build).
        if not (area and area:IsVisible()) then return end
        local sources, session = m.Sources()
        local count = type(sources) == "table" and #sources or 0
        local md = mode()
        local deaths = md.key == "deaths"
        -- DPS and HPS are ranked by the rate: their bars fill by it too.
        local field = md.byRate and "amountPerSecond" or "totalAmount"
        local top = count > 0 and sources[1][field]
        if type(top) == "nil" then top = 1 end
        local total = Meter.Total(sources, session)
        local seconds = m.Seconds(session)
        -- Scrolled to the end, the last player sits fully in view.
        offset = math.max(0, math.min(offset, count - whole))
        -- You, kept in the last whole row while scrolled out of view (by
        -- isLocalPlayer, which the game never keeps secret).
        local mine
        if cfg.showMe ~= false and count > whole then
            for i = 1, count do
                local me = sources[i].isLocalPlayer
                if not isSecret(me) and me == true then mine = i break end
            end
            if mine and mine > offset and mine <= offset + whole then mine = nil end
        end
        local fight = InCombatLockdown and InCombatLockdown() or false
        -- Out of a fight: who's who, for breakdowns once it starts.
        if not fight and count > 0 and not m.Sample() then Meter.SnapGuids(sources, md.key) end
        for k in pairs(nextPlace) do nextPlace[k] = nil end
        for i, bar in ipairs(rows) do
            local at = i + offset
            if mine and i == whole then at = mine end
            -- Pinned, the column ends on you: no cut-off row under you.
            local src = at <= count and bar.fits and not (mine and i > whole) and sources[at]
            local on = src and true or false
            if bar.on ~= on then
                bar.on = on
                bar:SetShown(on)
            end
            if src then
                -- The colors only follow the row's class (and the settings,
                -- which clear this): painted again only when that changes.
                local key = paintKey(src.classFilename)
                if key == nil or key ~= bar.painted then
                    bar.painted = key
                    m.Paint(bar.bar, src)
                    Meter.PaintText(bar, src.classFilename, cfg)
                end
                bar.src = src
                bar.rank:SetFormattedText("%d", at)
                ns.Rows.SetIcon(bar, src, cfg)
                local me = src.isLocalPlayer
                ns.Rows.SetMine(bar, not isSecret(me) and me == true)
                bar.name:SetText(shortName(src.name))
                if deaths then
                    -- A death: a full bar, and when it happened.
                    bar.bar:SetMinMaxValues(0, 1)
                    Style.SetBarValue(bar.bar, 1, snap)
                    bar.amount:SetText(clock(src.deathTimeSeconds))
                else
                    local amount = src[field]
                    if type(amount) == "nil" then amount = 0 end
                    bar.bar:SetMinMaxValues(0, top)
                    Style.SetBarValue(bar.bar, amount, snap)
                    bar.amount:SetFormattedText(Meter.Amount(src, md, cfg, total, seconds))
                end
                -- Out of a fight, someone who moved glides from their old place.
                local name = src.name
                local who = (not fight and type(name) == "string" and not isSecret(name)) and name or nil
                glide(bar, who)
                if who then nextPlace[who] = bar.slot end
            elseif bar.dy and bar.dy ~= 0 then
                place(bar, 0)
            end
        end
        lastPlace, nextPlace = nextPlace, lastPlace
        showEmpty(count == 0, md)
        if header then ns.MeterHeader.Update(header, m, cfg, session) end
        if ns.BreakdownWindow then DUI.SafeCall(ns.BreakdownWindow.Changed, m) end
        snap = false
        -- The breakdown follows the bar it's open for.
        if m.hovered then DUI.SafeCall(ns.Breakdown.Refresh) end
    end

    -- -----------------------------------------------------------------
    -- The header's buttons (MeterHeader.lua)
    -- -----------------------------------------------------------------

    -- The window's area (the report opens beside it).
    function m.Area() return area end

    -- The fight choices: overall, the current fight, then each earlier fight the
    -- game still has, named for what was fought.
    function m.FightChoices()
        local fights = m.Fights()
        local out = { { key = "overall", label = L["OVERALL"], text = L["Overall"], session = "overall" } }
        local cur = fights[1]
        out[#out + 1] = { key = "current", label = L["CURRENT"], session = "current",
                          text = cur and string.format(L["Current: %s"], fightName(cur)) or L["Current fight"] }
        for i = 2, #fights do
            local f = fights[i]
            local name, time = fightName(f), clock(f.durationSeconds)
            out[#out + 1] = { key = "fight" .. i, label = name, fight = f.sessionID,
                              text = time ~= "" and (name .. "  " .. time) or name }
        end
        return out
    end

    local function currentChoice(choices)
        for i, c in ipairs(choices) do
            if (c.fight and c.fight == m.fight) or (not c.fight and not m.fight and c.session == cfg.session) then
                return i
            end
        end
        return 2
    end

    -- Shows a fight (an earlier one, or this window's own Current or
    -- Overall), from now on.
    function m.ShowFight(id)
        if m.fight == id then return end
        m.fight = id
        offset = 0
        snap = true
        dirty = true
        m.Draw()
    end

    -- A pick from the fight menu. With "same fight" on, an earlier fight is
    -- shown in every window on Current, and Current again takes them all
    -- back (Meter.ShareFight); Overall is only this window's.
    local function pickFight(c)
        if c.session and c.session ~= cfg.session then
            DUI:Set("InfoPanel", path .. ".session", c.session)
        end
        m.ShowFight(c.fight)
        if c.fight or c.session == "current" then Meter.ShareFight(m, c.fight) end
    end
    m.PickFight = pickFight

    -- The fights were cleared (Meter.ResetAll): back to the current one.
    function m.Cleared()
        m.fight = nil
        offset = 0
        snap = true
        dirty = true
        if cfg and cfg.session ~= "current" then DUI:Set("InfoPanel", path .. ".session", "current") end
    end

    -- The fight and mode buttons open a drop-down of their choices, in the
    -- options window's own list.
    local function openFights(b)
        local choices = m.FightChoices()
        local keys, values, byKey = {}, {}, {}
        for _, c in ipairs(choices) do
            keys[#keys + 1] = c.key
            values[c.key] = c.text
            byKey[c.key] = c
        end
        DUI.Widgets.OpenMenu(b, keys, values, choices[currentChoice(choices)].key,
            function(k) pickFight(byKey[k]) end, Meter.MENU_WIDTH)
    end

    -- Every mode under its group's heading.
    local function openModes(b)
        local keys, values, titles = {}, {}, {}
        for _, g in ipairs(Meter.GROUP_ORDER) do
            local t = "#" .. g
            keys[#keys + 1] = t
            values[t] = L[Meter.GROUPS[g]]
            titles[t] = true
            for _, md in ipairs(Meter.MODES) do
                if md.group == g then
                    keys[#keys + 1] = md.key
                    values[md.key] = L[md.name]
                end
            end
        end
        DUI.Widgets.OpenMenu(b, keys, values, cfg.mode,
            function(k) if not titles[k] then DUI:Set("InfoPanel", path .. ".mode", k) end end,
            Meter.MENU_WIDTH, { titles = titles })
    end

    -- A new window, from a preset (MeterWindows.lua).
    local function openNew(b)
        local W = ns.Windows
        if #W.Own() >= W.MAX then
            DUI.Print(string.format(L["There are already %d meter windows of your own: remove one to make another."], W.MAX))
            return
        end
        local keys, values = {}, {}
        for _, p in ipairs(W.PRESETS) do
            keys[#keys + 1] = p.key
            values[p.key] = L[p.label]
        end
        -- A new window comes with the soft window sound, as any window of ours opens.
        DUI.Widgets.OpenMenu(b, keys, values, nil, function(k)
            if W.Add(k) and DUI.Sound then DUI.Sound.Play("open") end
        end, Meter.MENU_WIDTH)
    end

    -- This window's settings on the Meters page.
    local function openOptions()
        if not DUI.OptionsPanel then return end
        DUI.OptionsPanel.Show("InfoPanel.meter")
        if ns.MeterOptions and ns.MeterOptions.Pick then ns.MeterOptions.Pick(m.id) end
    end

    -- The bar under the mouse, if any (not under the header).
    local function hoveredBar()
        if header and header:IsShown() and header:IsMouseOver() then return nil end
        for _, bar in ipairs(rows) do
            if bar:IsShown() and bar.src and bar:IsMouseOver() then return bar end
        end
    end

    -- While the mouse is anywhere over the meter (header included) the
    -- header's buttons are out; watched only then.
    local function watchHover()
        if area:GetScript("OnUpdate") then return end   -- watching already
        ns.MeterHeader.Hover(header, true)
        area:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() then
                ns.MeterHeader.Hover(header, false)
                m.hovered = nil
                ns.Breakdown.Hide()
                self:SetScript("OnUpdate", nil)
                return
            end
            local bar = hoveredBar()
            if bar ~= m.hovered then
                m.hovered = bar
                if bar then ns.Breakdown.Show(bar) else ns.Breakdown.Hide() end
            end
        end)
    end

    -- Joining a group: clear the old fights, or ask first, if set to.
    local wasInGroup
    local function onRoster()
        local now = IsInGroup()
        if now and wasInGroup == false then
            clearFor(cfg.onJoin)
        end
        wasInGroup = now
    end

    -- Entering an instance has its own setting. A /reload, login, move inside
    -- or corpse run doesn't count, so the fights survive a wipe.
    local here, corpseRun
    local function onWorld(_, login, reloading)
        local now = instanceNow()
        if login == true or reloading == true then
            here = now
            return
        end
        if now then
            if now ~= here and now ~= corpseRun then clearFor(cfg.onInstance) end
            corpseRun = nil
        elseif here and type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
            corpseRun = here
        end
        here = now
    end

    function m.Build(parent, mod)
        area = parent
        moddb = mod.db
        cfg = DUI.DB.GetPath(mod.db, path)
        if main then
            wasInGroup = IsInGroup()
            DUI.RegisterEvent("GROUP_ROSTER_UPDATE", onRoster)
            here = instanceNow()
            DUI.RegisterEvent("PLAYER_ENTERING_WORLD", onWorld)
        end
        header = ns.MeterHeader.New(parent, {
            fight = openFights, mode = openModes, reset = askReset, new = openNew, options = openOptions,
            report = function(b) ns.Report.Toggle(m, b) end,
        })
        m.header = header
        -- The words for a meter with nobody in it.
        m.empty = Style.Text(parent, Style.SIZE.body, "CENTER")
        m.empty:SetPoint("LEFT", parent, "LEFT", 6, 0)
        m.empty:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
        Style.InkText(m.empty, "LABEL")
        m.empty:Hide()
        parent:HookScript("OnShow", function() dirty = true end)
        parent:EnableMouse(true)
        parent:SetScript("OnEnter", watchHover)
        m.HoverStart = watchHover
        parent:EnableMouseWheel(true)
        parent:SetScript("OnMouseWheel", function(_, delta)
            offset = math.max(0, offset - delta)
            snap = true
            m.Draw()
        end)
        share()
        local function resample()
            m.fight = nil
            snap = true
            dirty = true
        end
        -- A color setting changed (here or a General one, such as a gradient
        -- pair), even mid-fight: every row is painted afresh on the next draw.
        DUI.On("SettingChanged", function()
            for _, bar in ipairs(rows) do bar.painted, bar.mine = nil, nil end
            dirty = true
        end)
        DUI.On("TestModeChanged", resample)
        DUI.On("TestPartChanged", function(key) if key == part then resample() end end)
    end

    function m.Apply(c)
        cfg = c
        -- Keep the game's meter window off, even while ours is collapsed. Only
        -- written when it isn't off already.
        if c.enabled and SetCVar and not (GetCVar and GetCVar("damageMeterEnabled") == "0") then
            pcall(SetCVar, "damageMeterEnabled", "0")
        end
        ns.MeterHeader.Apply(header, c)
        layoutRows()
        m.Draw()
    end

    all[#all + 1] = m
    return m
end

-- The first meter (in the panel, or its own window) is ns.Meter itself.
Meter.New(Meter, { id = "main", path = "meter", part = "meter", main = true })
