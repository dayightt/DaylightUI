-- Builds the unit frames (player, target, target of target, pet, focus), both
-- cast bars and the target auras, registers them with the core, and keeps them
-- in sync with settings and the game. Party and raid are group headers
-- (Party.lua, Raid.lua). All protected work goes through DaylightUI.AfterCombat.

local _, ns = ...
local DUI = DaylightUI
local UF, CB, Auras, Blizzard = ns.UF, ns.CastBar, ns.Auras, ns.Blizzard

ns.SPECS = {
    { unit = "player", label = "Player", power = true, slant = "right", tab = true, portrait = true, combat = true, ribbon = true,
      default = { "BOTTOM", nil, "BOTTOM", -200, 240 } },
    { unit = "target", label = "Target", power = true, slant = "left", tab = true, marker = true, classification = true,
      portrait = true, range = true, threat = true, threatTag = true, dots = true, arrive = true, ribbon = true,
      level = 30,   -- so the target of target beside it draws fully under its ring (its parts reach its own +15)
      default = { "BOTTOM", nil, "BOTTOM", 200, 240 } },
    { unit = "targettarget", label = "Target of Target", compact = true, power = true, slant = "left", poll = 0.1, range = true,
      default = { "LEFT", "DaylightUIFrame_target", "RIGHT", 48, 0 } },
    { unit = "pet", label = "Pet", compact = true, power = true, slant = "right", tab = true,
      default = { "TOPLEFT", "DaylightUIFrame_player", "BOTTOMLEFT", 30, -36 } },
    { unit = "focus", label = "Focus", power = true, slant = "right", tab = true, marker = true, portrait = true,
      range = true, threat = true, ribbon = true,
      default = { "LEFT", nil, "LEFT", 300, 0 } },
    -- Who your focus is targeting (the game's own focus frame has this too).
    { unit = "focustarget", label = "Focus Target", compact = true, power = true, slant = "right", poll = 0.1, range = true,
      default = { "LEFT", "DaylightUIFrame_focus", "RIGHT", 48, 0 } },
}


-- The settings and text sizes a frame reads (flag carriers share "arena").
function ns.ConfigFor(db, spec)
    local key = UF.FrameKey(spec)
    return db[key], db[key .. "Text"]
end

-- "Copy from" on each frame's page: the frames that can be copied, by settings
-- key, and what a copy leaves alone: the frame's switch, fade, and group
-- layout and sorting (plus a raid size's own follow).
ns.COPY_FRAMES = { "player", "target", "focus", "targettarget", "focustarget", "pet", "party", "raid", "raid20", "raid40", "arena" }
ns.COPY_KEEP = { enabled = true, showInParty = true, fade = true, follow = true, own = true,
                 direction = true, perLine = true, groupSpacing = true, sortBy = true, groups = true,
                 hideSelf = true, showSolo = true, growUp = true, growLeft = true, ownSpot = true, strata = true }

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end

-- The settings key a frame's page edits. A raid size that follows Raid 10
-- uses Raid 10's.
local function copyKey(d, key)
    local size = tonumber(string.match(key, "^raid(%d+)$"))
    if size then return ns.Raid.KeyFor(d, size) end
    return key
end

-- Copies to frame every setting (and text size) it shares with frame from,
-- except ns.COPY_KEEP. A raid size with its own setup never takes the settings
-- all raid sizes share (RAID_SHARED, Raid 10's).
function ns.CopyFrame(from, to)
    local d = ns.module and ns.module.db
    if type(d) ~= "table" then return false end
    from, to = copyKey(d, from), copyKey(d, to)
    if from == to or type(d[from]) ~= "table" or type(d[to]) ~= "table" then return false end
    local shared = string.find(to, "^raid%d") and ns.RAID_SHARED or {}
    local t = deepCopy(d[to])
    for k, v in pairs(d[from]) do
        if t[k] ~= nil and not ns.COPY_KEEP[k] and not shared[k] then t[k] = deepCopy(v) end
    end
    local text = deepCopy(d[to .. "Text"] or {})
    for k, v in pairs(d[from .. "Text"] or {}) do
        if text[k] ~= nil then text[k] = deepCopy(v) end
    end
    DUI.DB.SetPath(d, to .. "Text", text)
    DUI:Set("UnitFrames", to, t)
    return true
end

-- Each style keeps its own heights (Defaults.lua, sizes) and the live keys hold
-- the shown style's. When a frame's style changes (its own pick, the global
-- one, or a profile switch) it stores them and loads the other style's.
-- Returns true when anything changed.
function ns.SwapSizes(db)
    local moved = false
    for _, key in ipairs(ns.RIBBON_FRAMES) do
        local cfg = db[key]
        local want = type(cfg) == "table" and ns.UF.StyleOf(cfg)
        local was = want and (cfg.sizesFor == "ribbon" and "ribbon" or "daylight")
        if want and want ~= was and type(cfg.sizes) == "table" then
            local away, take = cfg.sizes[was] or {}, cfg.sizes[want] or {}
            cfg.sizes[was] = away
            for _, k in ipairs(ns.SIZE_KEYS) do
                if cfg[k] ~= nil then away[k] = cfg[k] end
                if take[k] ~= nil then cfg[k] = take[k] end
            end
            cfg.sizesFor = want
            moved = true
        end
    end
    return moved
end

-- A style pick from the options (look.style, <frame>.style): written, heights
-- swapped, then set once more through DUI:Set so the frames and the open page
-- redraw with the new heights already in place.
function ns.SetStyle(path, value)
    local db = ns.module and ns.module.db
    if type(db) ~= "table" then return end
    DUI.DB.SetPath(db, path, value)
    ns.SwapSizes(db)
    DUI:Set("UnitFrames", path, value)
end

-- Text sizes from when the main frames shared one set (db.text). Each frame
-- takes the ones that were changed. The small frames drew their names at the
-- health text's size.
function ns.MigrateText(db)
    local old = db.text
    if type(old) ~= "table" then return end
    for _, key in ipairs({ "name", "percent", "big" }) do
        local v = old[key]
        if v ~= nil then
            for _, unit in ipairs({ "player", "target", "focus" }) do db[unit .. "Text"][key] = v end
            if key == "percent" then
                for _, unit in ipairs({ "targettarget", "pet" }) do
                    db[unit .. "Text"].name, db[unit .. "Text"].percent = v, v
                end
            end
            old[key] = nil
        end
    end
end

-- Raid tiles drew their names at the health text's size.
function ns.MigrateRaidText(db)
    local r = db.raidText
    if r.migrated then return end
    r.migrated = true
    if r.percent ~= ns.DEFAULTS.raidText.percent and r.name == ns.DEFAULTS.raidText.name then r.name = r.percent end
end

ns.frames = {}

-- Protected, so only call through DUI.AfterCombat.
function ns.SetEnabled(f, enabled)
    if f.unitToken == "player" then
        f:SetShown(enabled)
        return
    end
    ns.Release(f)
    if not enabled then
        f:Hide()
    elseif f.spec.arrive then
        ns.Arrive.Watch(f)   -- it leaves the way it came (Arrive.lua)
    else
        RegisterUnitWatch(f)
    end
end

-- Stops whatever shows and hides a frame, so test mode can take over.
-- Protected, out of combat only.
function ns.Release(f)
    UnregisterUnitWatch(f)
    UnregisterStateDriver(f, "visibility")
    if f.spec.arrive then
        ns.Arrive.Stop(f)
        f:EnableMouse(true)
    end
end

-- Aura rows sit beside a frame's name tab, so they refit when the tab does.
-- Only what AuraGroups.Box reads off the frame counts. The tab's width doesn't,
-- since a name or flag change resizes it often. Settings changes place the
-- rows themselves (ns.Refresh). setOf() returns the frame's set, or nil.
function ns.RefitOnTab(frame, setOf)
    local placed, now = {}, {}
    frame.onTabSized = function(f)
        local set = setOf()
        if not set then return end
        local tab = f.tab
        now[1], now[2], now[3], now[4] = tab ~= nil and tab:IsShown() == true, f.tabHeight or 0, f:GetWidth(), f:GetHeight()
        now[5], now[6], now[7], now[8] = f.cut or 0, f.tabInset or 0, f.ringInset or 0, f.ringReach or 0
        now[9], now[10], now[11], now[12] = f.cornerMode == true, set.aboveLift or 0, set.buffDrop or 0, set.frameCfg or false
        now[13], now[14], now[15] = f.foot or 0, f.tabAt or "outer", f.tabY or 0
        local same = true
        for i = 1, 15 do
            if placed[i] ~= now[i] then same = false; placed[i] = now[i] end
        end
        if not same then Auras.Place(set, f) end
    end
end

-- The room kept above and below the target for what sits there, so its aura
-- rows land past it. Returns aboveLift, buffDrop (read by Auras.Place), and the
-- room for the pips alone, which its cast bar hangs from. Its page preview
-- asks the same, so rows sit where they do in game.
function ns.TargetAuraRoom(db)
    local cc, tc = db.combo, db.targetCastbar
    local onTarget = ns.combo and cc.enabled and cc.anchor ~= "player"
    local above = cc.side == "above"
    local pips = (onTarget and not above) and (ns.Combo.Height(cc) + 4 - (cc.y or 0)) or 0
    local lift = (onTarget and above) and ns.Combo.Lift(cc) or 0
    local at, room = CB.At("target", tc), tc.height + CB.AT_GAP
    if tc.enabled and at == "above" then return lift + room, pips, pips end
    if tc.enabled and (at == "below" or at == "slide") then return lift, pips + room, pips end
    return lift, pips, pips
end

-- The player frame's own buffs and debuffs (settings playerAuras, off by
-- default). The client's containers are created the first time a row is turned
-- on, so players who leave them off pay nothing. Rows sit exactly where the
-- settings and the page preview put them, nothing pushes them.
-- Protected parent, so only call through DUI.AfterCombat.
function ns.PlacePlayerAuras(db)
    local a, f = db.playerAuras, ns.frames.player
    if not (a and f) then return end
    if not ns.playerAuras and (a.debuffs or a.buffs) then
        ns.playerAuras = Auras.Create(f, "right", "player", a)
        if ns.playerAuras then ns.RefitOnTab(f, function() return ns.playerAuras end) end
    end
    local set = ns.playerAuras
    if not set then return end
    Auras.Apply(set, a)
    Auras.Place(set, f, db.player)
end

-- How far a changed setting reaches. A frame's own keys (player.*,
-- playerText.*) only lay out that frame, since each layout reads only its own.
-- Cast bar, swing, combo and aura row keys affect the five frames, and a party
-- key the party too. Anything else, or no path (a style or profile change),
-- also covers the raid's 40 tiles. A dragged slider goes through here every
-- frame. A refresh queued during combat keeps the widest scope requested.
local ONE, FRAMES, NO_RAID, ALL = 1, 2, 3, 4
local REACH = { playerCastbar = FRAMES, targetCastbar = FRAMES, focusCastbar = FRAMES, swing = FRAMES,
                targetAuras = FRAMES, playerAuras = FRAMES, combo = FRAMES, personal = ONE,
                arena = FRAMES, arenaText = FRAMES,
                party = NO_RAID, partyText = NO_RAID, partyCastbar = NO_RAID, partyPet = NO_RAID, partyPetText = NO_RAID }
local UNIT_OF = {}
for _, spec in ipairs(ns.SPECS) do
    UNIT_OF[spec.unit], UNIT_OF[spec.unit .. "Text"] = spec.unit, spec.unit
end
local pendingReach, pendingUnits = 0, {}

-- A saved strata, or the default when it's missing or unknown.
function ns.StrataOf(cfg, fallback)
    local s = type(cfg) == "table" and cfg.strata
    if type(s) == "string" and ns.STRATA_LABELS[s] then return s end
    return fallback or "MEDIUM"
end

-- Puts each frame in the strata its page picks. Children follow their parent,
-- so the holders carry the party, raid and PvP frames. Cast bars and the swing
-- timer pick theirs as they lay out, since a bar hung under a frame draws with
-- that frame. Unit frames are protected, so this runs out of combat (Refresh).
function ns.ApplyStrata(db)
    for _, spec in ipairs(ns.SPECS) do
        local f = ns.frames[spec.unit]
        local s = ns.StrataOf(db[spec.unit])
        for _, piece in ipairs(f and f.pieces or {}) do piece:SetFrameStrata(s) end
    end
    local holders = { { ns.Party.holder, db.party }, { ns.Raid.holder, db.raid }, { ns.Arena.holder, db.arena } }
    for _, h in ipairs(holders) do
        if h[1] then h[1]:SetFrameStrata(ns.StrataOf(h[2])) end
    end
    if ns.Personal.frame then ns.Personal.frame:SetFrameStrata(ns.StrataOf(db.personal, "LOW")) end
end

function ns.Refresh(mod, path)
    local top = type(path) == "string" and string.match(path, "^[^%.]+")
    local unit = top and UNIT_OF[top]
    if unit then pendingUnits[unit] = true end
    pendingReach = math.max(pendingReach, unit and ONE or (top and REACH[top]) or ALL)
    DUI.AfterCombat(function()
        local reach, units = pendingReach, pendingUnits
        pendingReach, pendingUnits = 0, {}
        local db = mod.db
        ns.SwapSizes(db)
        ns.ApplyStrata(db)
        UF.ConfigureColors(db.colors)
        UF.SLANT = tonumber(db.look and db.look.slant) or 0.21
        CB.Configure(db.casts, db.targetCasts)
        for _, spec in ipairs(ns.SPECS) do
            if reach >= FRAMES or units[spec.unit] then
                local f = ns.frames[spec.unit]
                local cfg, text = ns.ConfigFor(db, spec)
                f.iconStyle, f.classIcons = db.portraits.icons, db.portraits.classIcons
                f.rangeFade = spec.range and db.range.enabled or false
                f.rangeAlpha = UF.RangeAlpha(db.range, false)
                UF.Layout(f, cfg, text)
                local on = cfg.enabled
                ns.SetEnabled(f, on)
                UF.UpdateAll(f, true)
                DUI.APIReport.Styled("unit", f, false)
                -- A new style: the frame arrives in its new shape (Arrive.lua).
                if f.restyled and f:IsShown() then ns.Arrive.Start(f) end
            end
        end
        if reach >= FRAMES then ns.Arena.Layout(db) end
        if reach >= ALL then ns.Raid.LayoutNow(db) end
        if reach >= NO_RAID then
            ns.Party.group:Layout(db.party, db.partyText, db.range)
            for _, b in ipairs(ns.Party.group.buttons) do
                if b.restyled and b:IsShown() then ns.Arrive.Start(b, "UnitFrames.party") end
            end
        end
        ns.Leader.Apply(db)
        ns.Pull.Apply(db)
        -- The party's first frame starts at the same height regardless of its
        -- height (the default spot is the holder's top-left).
        local pm = DUI.Movers.Get("unitframes.party")
        if pm and pm.default then pm.default[5] = ns.Party.DefaultY(db.party) end
        -- The target's cast bar: inside its frame, or its own bar (above or
        -- below the frame, or on its own mover).
        local tc = db.targetCastbar
        local tAt = CB.At("target", tc)
        local tSlides = tAt == "slide"
        local _, _, tPips = ns.TargetAuraRoom(db)
        CB.Layout(ns.targetCastbar, { enabled = tc.enabled and tAt == "power", spell = tc.spell, time = tc.time,
                                      insideTextSize = tc.insideTextSize, insideTextX = tc.insideTextX, insideTextY = tc.insideTextY }, db.target)
        CB.Layout(ns.targetCastbarFree, { enabled = tc.enabled and tAt ~= "power", at = tAt, x = tc.x, y = tc.y, drop = (tSlides or tAt == "below") and tPips or 0,
                                          width = tc.width, fitFrame = tc.fitFrame, height = tc.height, showIcon = tc.showIcon, slant = tSlides or tc.slant,
                                          spell = tc.spell, time = tc.time, reverseFill = tc.reverseFill, strata = tc.strata })
        DUI.Movers.Suspend("unitframes.targetCastbar", tAt ~= "free")
        local fc = db.focusCastbar
        local fAt = CB.At("focus", fc)
        CB.Layout(ns.focusCastbar, { enabled = fc.enabled and fAt == "power", spell = fc.spell, time = fc.time }, db.focus)
        CB.Layout(ns.focusCastbarFree, { enabled = fc.enabled and fAt ~= "power", at = fAt, x = fc.x, y = fc.y,
                                         width = fc.width, fitFrame = fc.fitFrame, height = fc.height, showIcon = fc.showIcon, slant = fc.slant,
                                         spell = fc.spell, time = fc.time, reverseFill = fc.reverseFill, strata = fc.strata })
        DUI.Movers.Suspend("unitframes.focusCastbar", fAt ~= "free")
        -- The display first, since your cast bar and swing bars may stand under it.
        ns.Personal.Layout(db.personal)
        ns.PowerBar.RegenApply()
        CB.Layout(ns.playerCastbar, db.playerCastbar)
        ns.Swing.Layout(ns.swing, db.swing, ns.playerCastbar)
        ns.Personal.Dock()
        ns.Personal.PlaceAuras()
        Auras.Apply(ns.auras, db.targetAuras)
        -- The target's auras clear the combo points (rogues, druids): the buffs
        -- under it, or the rows above it when the pips sit above. A cast bar
        -- above or below the frame pushes that side's rows out too.
        if ns.auras then
            ns.auras.aboveLift, ns.auras.buffDrop = ns.TargetAuraRoom(db)
        end
        Auras.Place(ns.auras, ns.frames.target, db.target)
        ns.PlacePlayerAuras(db)
        ns.Combo.Layout(ns.combo, db.combo)
        ns.Happiness.Layout(ns.happiness, db.pet)
        ns.DruidBars.Layout(db.player.druidBars)
        Blizzard.Apply(db)
        DUI.Movers.ApplyAll()
        if ns.Test then ns.Test.Reapply() end
    end, "unitframes:refresh")
end

local function updateAll()
    for _, f in pairs(ns.frames) do UF.UpdateAll(f, true) end
end

-- Range and mouseover have no change events, so one shared ticker checks the
-- frames that fade (by range, or out of combat).
local rangeTicker
local function startRangeTicker()
    if rangeTicker then return end
    rangeTicker = CreateFrame("Frame")
    local elapsed = 0
    rangeTicker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UF.RANGE_INTERVAL then return end
        elapsed = 0
        for _, spec in ipairs(ns.SPECS) do
            local f = ns.frames[spec.unit]
            if f and spec.range and f:IsShown() then UF.UpdateRange(f) end
        end
        if ns.Arena.shown > 0 then
            for _, b in ipairs(ns.Arena.buttons) do
                if b:IsShown() then UF.UpdateRange(b) end
            end
        end
        for _, b in ns.Group.Buttons() do
            if b:IsShown() then
                UF.UpdateRange(b)
                ns.GroupParts.UpdateBuffsSeen(b)
            end
        end
    end)
end
ns.RangeTicker = function() return rangeTicker end

-- A unit token shown by one of the frames or group buttons. The client sends a
-- unit event once per token, so "target" arrives on its own.
local OWN_UNITS = { player = true, pet = true, target = true, focus = true, targettarget = true, focustarget = true }
function ns.OurUnit(unit)
    if type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) then return false end
    return OWN_UNITS[unit] == true or unit:find("^party%d") ~= nil or unit:find("^arena%d") ~= nil or unit:find("^raid%d") ~= nil
end

-- Who is on a unit token, as a plain string to compare with last time: the
-- GUID, else name and realm (a GUID is secret in a battleground, a name isn't).
-- nil when neither can be read.
local function plain(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) end
function ns.WhoOn(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and plain(guid) then return guid end
    local okName, name, realm = pcall(UnitName, unit)
    if not okName or not plain(name) then return nil end
    if realm ~= nil and not plain(realm) then return nil end
    return name .. "-" .. (realm or "")
end

-- Event bursts collected into one pass on the next frame (the queued fns).
local queued, pending = {}, false
local function flush()
    pending = false
    for fn in pairs(queued) do
        queued[fn] = nil
        DUI.SafeCall(fn)
    end
end
local function later(fn)
    queued[fn] = true
    if pending then return end
    pending = true
    C_Timer.After(0, flush)
end

-- The API's notice that a single frame has a new occupant (its unit token
-- stays the same, empty or not).
local function occupant(unit)
    local f = ns.frames[unit]
    if f then DUI.APIReport.Occupant("unit", f, unit) end
end

local function registerEvents()
    startRangeTicker()
    UF.ResolveRangeSpell()
    DUI.RegisterEvent("SPELLS_CHANGED", UF.ResolveRangeSpell)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", updateAll)
    -- Total RP 3 learned a roleplay name (DUI.UnitName), so each shown frame
    -- and tile with a unit redraws its name.
    DUI.On("NamesChanged", function()
        local function one(f)
            if f:IsShown() and type(f.unitToken) == "string" and UnitExists(f.unitToken) then UF.UpdateIdentity(f) end
        end
        for _, f in pairs(ns.frames) do one(f) end
        for _, b in ipairs(ns.Party.group.buttons) do one(b) end
        for _, b in ipairs(ns.Raid.buttons) do one(b) end
        for _, b in ipairs(ns.Arena.buttons) do one(b) end
    end)
    DUI.RegisterEvent("PLAYER_TARGET_CHANGED", function()
        UF.UpdateAll(ns.frames.target, true)
        UF.UpdateAll(ns.frames.targettarget, true)
        occupant("target")
        occupant("targettarget")
        CB.Refresh(ns.targetCastbar)
        CB.Refresh(ns.targetCastbarFree)
        Auras.Refresh(ns.auras)
        ns.Combo.Update(ns.combo, true)
        ns.GroupParts.UpdateTargetMarks()
    end)
    -- Your DoTs on the target changed (a cast, a tick, one expired). key is the
    -- one mob that changed (Dots.KeyOf), nil for any number of them. A tick on
    -- another mob (every nameplate's) leaves the frame alone.
    DUI.On("DotsChanged", function(key)
        local f = ns.frames.target
        if not (f and f:IsShown()) then return end
        if key ~= nil and key ~= DUI.Dots.KeyOf("target") then return end
        UF.UpdateDots(f)
    end)
    DUI.RegisterEvent("PLAYER_FOCUS_CHANGED", function()
        UF.UpdateAll(ns.frames.focus, true)
        UF.UpdateAll(ns.frames.focustarget, true)
        occupant("focus")
        occupant("focustarget")
        CB.Refresh(ns.focusCastbar)
        CB.Refresh(ns.focusCastbarFree)
    end)
    DUI.RegisterEvent("UNIT_PET", function(_, unit)
        if unit == "player" then UF.UpdateAll(ns.frames.pet, true); occupant("pet") end
    end)
    DUI.RegisterEvent("UNIT_TARGET", function(_, unit)
        if unit == "target" then UF.UpdateAll(ns.frames.targettarget, true); occupant("targettarget") end
        if unit == "focus" then UF.UpdateAll(ns.frames.focustarget, true); occupant("focustarget") end
    end)
    for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
        DUI.RegisterEvent(e, function()
            UF.UpdateAll(ns.frames.player)
            UF.UpdateAll(ns.frames.target)
        end)
    end
    -- Threat changes arrive for you or for the mob, so re-read both. In a raid
    -- they come for every mob and member many times a second, so they're
    -- batched into one pass on the next frame. A tile only reads its own
    -- member's state, which changes with UNIT_THREAT_SITUATION_UPDATE for that
    -- member, so only those tiles are redone (a mob's list update, many per
    -- second, only touches target and focus). Your own change, or combat
    -- ending, redoes every tile.
    local tilesDue, allDue = {}, false
    local function threat()
        UF.UpdateThreat(ns.frames.target)
        UF.UpdateThreat(ns.frames.focus)
        if not (allDue or next(tilesDue)) then return end
        for _, b in ns.Group.Buttons() do
            if allDue or tilesDue[b.unitToken] then UF.UpdateThreat(b) end
        end
        wipe(tilesDue)
        allDue = false
    end
    DUI.RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", function(_, unit)
        if type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) or unit == "player" then
            allDue = true
        else
            tilesDue[unit] = true
        end
        later(threat)
    end)
    DUI.RegisterEvent("UNIT_THREAT_LIST_UPDATE", function() later(threat) end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() allDue = true; later(threat) end)
    UF.fighting = InCombatLockdown() and true or false
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        DUI.RegisterEvent(e, function()
            UF.fighting = e == "PLAYER_REGEN_DISABLED"
            UF.UpdateCombat(ns.frames.player)
            ns.Moments.Fight(UF.fighting)
            -- Tile icons set to hide in combat.
            for _, b in ns.Group.Buttons() do
                UF.UpdateLeader(b, nil, true)
                UF.UpdateRole(b)
            end
        end)
    end
    -- Leader, resting and your own level have no unit events of their own. A
    -- member's faction update only redoes their tile, like the threat pass.
    local statusDue, statusAll = {}, false
    local function status()
        for _, f in pairs(ns.frames) do
            if not f.test then UF.UpdateStatus(f, nil, true) end
        end
        if statusAll or next(statusDue) then
            for _, b in ns.Group.Buttons() do
                if statusAll or statusDue[b.unitToken] then
                    UF.UpdateStatus(b, nil, true)   -- the tab's crown, PvP flag and level
                    UF.UpdateLeader(b, nil, true)   -- the corner crown
                end
            end
        end
        wipe(statusDue)
        statusAll = false
    end
    for _, e in ipairs({ "PLAYER_UPDATE_RESTING", "PARTY_LEADER_CHANGED", "PLAYER_LEVEL_UP" }) do
        DUI.RegisterEvent(e, function() statusAll = true; later(status) end)
    end
    -- PvP flag changes arrive as a faction update for every unit the client
    -- knows (every nameplate too, many per second in a battleground), so only
    -- the frames' own units start a pass.
    DUI.RegisterEvent("UNIT_FACTION", function(_, unit)
        if not ns.OurUnit(unit) then return end
        if type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) or unit == "player" then
            statusAll = true
        else
            statusDue[unit] = true
        end
        later(status)
    end)
    -- Role icons: someone picked a role, or the roster changed who's there.
    local function roles()
        for _, f in pairs(ns.frames) do
            if not f.test then UF.UpdateRole(f) end
        end
        for _, b in ns.Group.Buttons() do UF.UpdateRole(b) end
    end
    DUI.RegisterEvent("PLAYER_ROLES_ASSIGNED", function() later(roles) end)
    -- Ready checks: each tile's answer (UF.UpdateReady). A raid's answers arrive
    -- one by one, batched into one pass on the next frame. They stay READY_HOLD
    -- seconds after the check ends, and a new check restarts the clock.
    local function ready()
        for _, b in ns.Group.Buttons() do UF.UpdateReady(b) end
    end
    DUI.RegisterEvent("READY_CHECK", function()
        UF.readyCheck = "running"
        UF.readyRound = (UF.readyRound or 0) + 1
        ready()
    end)
    DUI.RegisterEvent("READY_CHECK_CONFIRM", function() later(ready) end)
    DUI.RegisterEvent("READY_CHECK_FINISHED", function()
        UF.readyCheck = "finished"
        -- Everyone ready: the ripple lights every tile, so an answer landing
        -- now gets no light of its own (it would restart the ripple).
        local all = ns.Moments.EveryoneReady()
        UF.readyRipple = all
        ready()
        UF.readyRipple = nil
        if all then ns.Moments.AllReady() end
        local round = UF.readyRound
        C_Timer.After(UF.READY_HOLD, function()
            if UF.readyRound ~= round then return end
            UF.readyCheck = nil
            ready()
        end)
    end)
    -- A roster change can put someone new on a button that keeps its unit token
    -- ("party2"), so the header never re-sends it. Re-read them all, batched
    -- into one pass on the next frame since a filling raid sends dozens at
    -- once. A button whose player is unchanged (most of them on every pass in a
    -- battleground or a filling raid) only reads what a roster change can
    -- affect: online, crown, role. A changed unit token already redid
    -- everything (Group.lua's OnAttributeChanged, which keeps rosterWho).
    -- Someone new on the same token gets everything, including the target
    -- outline and their pet's button (the pet token stays, but its owner's
    -- class and pet are new).
    local function roster()
        for _, f in pairs(ns.frames) do
            if not f.test then
                UF.UpdateStatus(f)
                UF.UpdateRole(f)
            end
            ns.Texts.Update(f, "roster")   -- a group part (moved to another group)
        end
        for _, b in ns.Group.Buttons() do
            ns.Texts.Update(b, "roster")
            local who = UnitExists(b.unitToken) and ns.WhoOn(b.unitToken) or nil
            if who and who == b.rosterWho then
                UF.UpdateStatus(b)
                UF.UpdateLeader(b)
                UF.UpdateRole(b)
            elseif UnitExists(b.unitToken) then
                b.rosterWho = who
                ns.GroupParts.PointAuras(b)
                UF.UpdateAll(b, true)   -- status, crown and role included
                ns.GroupParts.UpdateTargetMark(b)
                if b.pet then ns.PartyPets.Refresh(b.pet) end
            else
                b.rosterWho = nil
                ns.GroupParts.PointAuras(b)
                UF.UpdateStatus(b)
                UF.UpdateLeader(b)
                UF.UpdateRole(b)
                ns.GroupParts.UpdateTargetMark(b)
                if b.pet then ns.PartyPets.Refresh(b.pet) end
            end
        end
    end
    -- Float: someone joining brings the tiles back. Only on a rise, since
    -- leaving or a reshuffle fires this too. Applies to both party and raid.
    local members = GetNumGroupMembers()
    DUI.RegisterEvent("GROUP_ROSTER_UPDATE", function()
        UF.rosterGen = UF.rosterGen + 1   -- invalidates the range check's cached answers (UF.UpdateRange)
        local now = GetNumGroupMembers()
        if now > members then
            DUI.Fade.Wake("UnitFrames.party")
            DUI.Fade.Wake("UnitFrames.raid")
        end
        members = now
        later(roster)
    end)
    DUI.RegisterEvent("RAID_TARGET_UPDATE", function()
        for _, f in pairs(ns.frames) do UF.UpdateMarker(f, true) end
        for _, b in ns.Group.Buttons() do UF.UpdateMarker(b, true) end
    end)
end

-- Units whose fade can wait for full health (the Fade card's "fullHealth").
ns.FADE_FULL_HEALTH = { player = true, pet = true }

-- Frames that can't float (Fade.Register's float = false). They already come
-- and go with their unit.
ns.FLOAT = { target = false, targettarget = false, focus = false, focustarget = false }

-- Health is secret, so whether it's full is left to the game at paint time
-- (UF.FullHealthAlpha). A change counts as activity instead: the frame comes
-- back and fades again a delay after the last change (a heal back to full).
ns.healthAt = {}
local healthWatch = CreateFrame("Frame")
healthWatch:RegisterUnitEvent("UNIT_HEALTH", "player", "pet")
healthWatch:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "pet")
healthWatch:SetScript("OnEvent", function(_, _, unit) ns.healthAt[unit] = GetTime() end)

ns.HEALTH_WAKE = 0.3   -- seconds a change keeps waking it (a few fade ticks)

function ns.HealthWake(unit)
    local t = ns.healthAt[unit]
    if t == nil or GetTime() - t > ns.HEALTH_WAKE then return false end
    return DUI:Get("UnitFrames", unit .. ".fade.fullHealth") == true
end

function ns.Build(mod)
    ns.module = mod
    ns.MigrateText(mod.db)
    ns.MigrateRaidText(mod.db)
    -- A failed upgrade is reported, but the frames still get built.
    DUI.SafeCall(ns.UpgradeGroupFrames, DUI.DB.Active())
    DUI.AfterCombat(function()
        for _, spec in ipairs(ns.SPECS) do
            local f = UF.Create(spec)
            ns.frames[spec.unit] = f
            UF.Wire(f)
            DUI.APIReport.Made("unit", f, spec.unit, false)
            if spec.poll then UF.EnablePolling(f, spec.poll) end
            f.moverKey = "unitframes." .. spec.unit
            DUI.Movers.Register(f, f.moverKey, spec.label, spec.default)
            local list = { f }   -- requested ten times a second, so reuse one table
            f.pieces = list      -- and these share the frame's strata (ns.ApplyStrata)
            if spec.unit == "player" and f.power then
                -- Its standalone power bar, when used (fades with the frame).
                list[2] = ns.PowerBar.Create(f)
                DUI.Movers.Register(list[2], ns.PowerBar.KEY, "Player Power Bar", { "BOTTOM", nil, "BOTTOM", 0, 215 })
                -- A druid's other powers (also fade with the frame).
                local druid = ns.DruidBars.Create(f)
                list[#list + 1] = druid
                DUI.Movers.Register(druid, ns.DruidBars.KEY, "Druid Resource Bars", ns.DruidBars.HOME)
            end
            if f.threatTag then
                -- Its standalone threat % tag, when used (fades with the frame).
                list[#list + 1] = UF.CreateThreatHolder(f)
                DUI.Movers.Register(f.threatHolder, UF.THREAT_KEY, "Target Threat %", { "CENTER", nil, "CENTER", 0, 120 })
            end
            DUI.Fade.Register{ key = "UnitFrames." .. spec.unit, scope = "UnitFrames", path = spec.unit .. ".fade",
                page = "UnitFrames." .. spec.unit, frames = function() return list end, paint = UF.PaintFade, whole = true,
                float = ns.FLOAT[spec.unit],
                wake = ns.FADE_FULL_HEALTH[spec.unit] and function() return ns.HealthWake(spec.unit) end or nil }
        end
        -- The target's cast bar covers its power bar and follows the angled end.
        local target = ns.frames.target
        ns.targetCastbar = CB.Create("target", target, target.power)
        -- The focus's the same way, in its power bar.
        local focus = ns.frames.focus
        ns.focusCastbar = CB.Create("focus", focus, focus.power)
        for _, tex in ipairs({ ns.focusCastbar.bg, ns.focusCastbar.bar:GetStatusBarTexture(),
                               DUI.Style.BarBack(ns.focusCastbar.bar) }) do
            DUI.Style.Clip(focus, tex, "inner")
        end
        ns.focusCastbarFree = CB.Create("focus")
        ns.focusCastbarFree.near = focus
        ns.focusCastbarFree.moverKey = "unitframes.focusCastbar"
        DUI.Movers.Register(ns.focusCastbarFree, "unitframes.focusCastbar", "Focus Cast Bar",
            { "TOP", "DaylightUIFrame_focus", "BOTTOM", 0, -40 })
        -- Or a bar of its own, when it's detached.
        ns.targetCastbarFree = CB.Create("target")
        ns.targetCastbarFree.near = target
        ns.targetCastbarFree.under, ns.targetCastbarFree.hangAt = target, "slide"
        -- Under the frame it only clears the combo pips while they show.
        ns.targetCastbarFree.pips = DUI.Motion.Slider(function() CB.PlacePips(ns.targetCastbarFree) end,
            { parent = ns.targetCastbarFree, dur = DUI.Motion.FAST, p = 0 })
        ns.targetCastbarFree.moverKey = "unitframes.targetCastbar"
        DUI.Movers.Register(ns.targetCastbarFree, "unitframes.targetCastbar", "Target Cast Bar",
            { "TOP", "DaylightUIFrame_target", "BOTTOM", 0, -40 })
        for _, tex in ipairs({ ns.targetCastbar.bg, ns.targetCastbar.bar:GetStatusBarTexture(),
                               DUI.Style.BarBack(ns.targetCastbar.bar) }) do
            DUI.Style.Clip(target, tex, "inner")
        end
        ns.playerCastbar = CB.Create("player")
        -- It hangs under the player frame unless detached in the options.
        ns.playerCastbar.under = ns.frames.player
        ns.playerCastbar.near = ns.frames.player
        ns.playerCastbar.moverKey = "unitframes.playerCastbar"
        DUI.Movers.Register(ns.playerCastbar, "unitframes.playerCastbar", "Player Cast Bar", { "BOTTOM", nil, "BOTTOM", 0, 180 })
        -- The swing timers hang under the cast bar unless detached.
        ns.swing = ns.Swing.Create()
        if ns.swing then
            DUI.Movers.Register(ns.swing, "unitframes.swing", "Swing Timer", { "BOTTOM", nil, "BOTTOM", 0, 150 })
            -- Each detached bar gets its own handle, just under the group's spot.
            local own = { { "main", "Main Hand Swing Timer", 124 }, { "off", "Off Hand Swing Timer", 100 },
                          { "ranged", "Ranged Swing Timer", 76 } }
            for _, o in ipairs(own) do
                DUI.Movers.Register(ns.swing.pods[o[1]], ns.Swing.MOVERS[o[1]], o[2], { "BOTTOM", nil, "BOTTOM", 0, o[3] })
                DUI.Movers.Suspend(ns.Swing.MOVERS[o[1]], true)
            end
        end
        -- Enemy flag carriers in a battleground (Arena.lua).
        ns.Arena.Create()
        -- Your bars at your feet (Personal.lua).
        ns.Personal.Create()
        -- The raid: a header of buttons in a plain holder that carries the mover.
        local raid = ns.Raid.Create()
        DUI.Movers.Register(raid, "unitframes.raid", "Raid", { "TOPLEFT", nil, "TOPLEFT", 20, -220 })
        -- Raid 20 and Raid 40 can each have their own spot (Raid.lua).
        for n, spot in pairs(ns.Raid.CreateSpots()) do
            DUI.Movers.Register(spot, ns.Raid.SpotKey(n), n == 20 and "Raid 20" or "Raid 40", ns.Raid.SpotDefault,
                { scale = false, active = function() return ns.Raid.OwnSpot(n) end })
        end
        ns.Raid.CreatePreview()
        -- The party: a header of buttons in a plain holder that carries the
        -- mover. Its first frame starts where the first party frame always did
        -- (LEFT 70, 160, by its center).
        local party = ns.Party.Create()
        DUI.Movers.Register(party, "unitframes.party", "Party",
            { "TOPLEFT", nil, "LEFT", 70, ns.Party.DefaultY(mod.db.party) })
        ns.Party.CreatePreview()
        -- Party and raid: every tile in the group fades together, and hovering
        -- one wakes them all since you're about to click one.
        for _, g in ipairs(ns.Group.all) do
            if g.key == "party" or g.key == "raid" then
                DUI.Fade.Register{ key = "UnitFrames." .. g.key, scope = "UnitFrames", path = g.key .. ".fade",
                    page = "UnitFrames." .. g.key, frames = function() return g.buttons end, paint = UF.PaintFade, whole = true }
            end
        end
        ns.auras = Auras.Create(ns.frames.target, "left", nil, mod.db.targetAuras)
        ns.combo = ns.Combo.Create(ns.frames.target)
        ns.happiness = ns.Happiness.Create(ns.frames.pet)
        ns.RefitOnTab(ns.frames.target, function() return ns.auras end)
        registerEvents()
        ns.ClickCast.Start()
        ns.Refresh(mod)
    end, "unitframes:build")
end
