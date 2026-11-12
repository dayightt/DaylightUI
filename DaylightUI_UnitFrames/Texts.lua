-- Extra text lines on a frame (Add piece, Design mode): up to four per frame
-- in fixed slots, <frame>.texts.t1..t4 (Defaults.lua). Each combines up to
-- three parts (kind, kind2, kind3: level, health, power, name, class, status,
-- group, guild, classification) joined by a separator (sep), each part in its
-- own color, e.g. "Name 60" or "4.1K / 6.6K - 62". Placed by Spots like any
-- piece and written on the frame's own updates (health, power, identity,
-- flags, roster), so a frame with none turned on costs nothing.
-- Values go whole to SetFormattedText and the client does the formatting, so
-- secrets are never compared. A part whose answer is secret (AFK under chat
-- lockdown, the raid group under restrictions) shows nothing.

local _, ns = ...
local DUI = DaylightUI
local Style, Spots = DUI.Style, ns.Spots
local INK = Style.INK
local L = DUI.L
local isSecret = issecretvalue or function() return false end

local Texts = {}
ns.Texts = Texts

Texts.KINDS = { "level", "health", "power", "name", "class", "status", "group", "guild", "classification" }
Texts.LABELS = { level = "Level", health = "Health", power = "Power", name = "Name", class = "Class",
                 status = "Status (AFK, dead)", group = "Raid group", guild = "Guild", classification = "Elite or rare" }
-- A second or third part: the same kinds, or nothing.
Texts.MORE_KINDS, Texts.MORE_LABELS = { "none" }, { none = "Nothing" }
for _, k in ipairs(Texts.KINDS) do
    Texts.MORE_KINDS[#Texts.MORE_KINDS + 1] = k
    Texts.MORE_LABELS[k] = Texts.LABELS[k]
end
-- What goes between two parts.
Texts.SEPS = { space = " ", dot = " \194\183 ", bar = " | ", slash = " / ", dash = " - " }
Texts.SEP_ORDER = { "space", "dot", "bar", "slash", "dash" }
Texts.SEP_LABELS = { space = "A space", dot = "A dot ( \194\183 )", bar = "A bar ( | )", slash = "A slash ( / )",
                     dash = "A dash ( - )" }
-- The frames that have slots (Defaults.lua).
Texts.FRAMES = { player = true, target = true, focus = true, party = true, raid = true }
-- Which update writes which kind: the frame's health, power and identity
-- updates, PLAYER_FLAGS_CHANGED (flags: AFK, DND), and the roster (group).
local ON = { health = { health = true, status = true }, power = { power = true },
             identity = { level = true, name = true, class = true, status = true, group = true, guild = true,
                          classification = true },
             flags = { status = true }, roster = { group = true } }

-- An elite's or rare's label, in its crest's color (UF.CREST_COLORS).
local CLASSIFICATION = { elite = "Elite", rareelite = "Rare elite", rare = "Rare", worldboss = "Boss" }

-- How a text reads from its spot: away from the side it's pinned to.
local LEFT = { topleft = true, left = true, bottomleft = true, outright = true, outtopright = true, outbottomright = true }
local RIGHT = { topright = true, right = true, bottomright = true, outleft = true, outtopleft = true, outbottomleft = true }
local function growOf(spot)
    if LEFT[spot] then return "right", "LEFT" end
    if RIGHT[spot] then return "left", "RIGHT" end
    return "center", "CENTER"
end

-- A slot's non-empty parts, in order.
local function kindsOf(t)
    local out = {}
    for _, field in ipairs({ "kind", "kind2", "kind3" }) do
        local k = t[field]
        if type(k) == "string" and Texts.LABELS[k] then out[#out + 1] = k end
    end
    return out
end

-- Places the frame's extra texts from cfg (its settings). Created the first
-- time a slot is turned on, hidden when turned off.
function Texts.Layout(f, cfg)
    local slots = type(cfg) == "table" and cfg.texts
    if type(slots) ~= "table" and not f.extraTexts then return end
    f.extraTexts = f.extraTexts or {}
    local any, box = false, nil
    for i, key in ipairs(ns.TEXT_SLOTS) do
        local t = type(slots) == "table" and slots[key]
        local fs = f.extraTexts[i]
        local kinds = type(t) == "table" and t.show == true and kindsOf(t) or {}
        if #kinds > 0 then
            local size = tonumber(t.size) or 11
            if not fs then
                fs = Style.Text(f.overlay or f, size, "CENTER")
                f.extraTexts[i] = fs
            end
            local fonts = (f.media or ns.UF.MediaOf(f.spec or {})).fonts
            Style.SetTextSlot(fs, fonts[kinds[1]] or fonts.name)
            Style.SetTextSize(fs, size)
            box = box or ns.AuraGroups.Box(f, cfg)
            local grow, justify = growOf(t.spot)
            local at = Spots.Layout(t.spot, grow, box, { x = t.x, y = t.y })
            fs:SetJustifyH(justify)
            fs:ClearAllPoints()
            fs:SetPoint(at.point, f, at.relPoint, at.x, at.y)
            fs.kind, fs.kinds = kinds[1], kinds
            fs.sep = Texts.SEPS[t.sep] or Texts.SEPS.space
            fs.healthFormat, fs.powerFormat = t.healthFormat, t.powerFormat
            -- The updates that rewrite it: any of its parts' updates.
            fs.wants = {}
            for _, k in ipairs(kinds) do fs.wants[k] = true end
            fs:Show()
            any = true
        elseif fs then
            fs.kind, fs.kinds = nil, nil
            fs:Hide()
        end
    end
    f.extraOn = any or nil
end

local function levelColor(u, level)
    local c = INK.VALUE
    if u ~= "player" and type(level) == "number" then
        local dc = DUI.LevelColor(u, level)
        if dc then c = { Style.Lighten(dc.r, dc.g, dc.b, ns.UF.LEVEL_LIFT) } end
    end
    return c
end

local function classColor(token)
    if type(token) == "string" and not isSecret(token) then return { Style.ClassTextColor(token) } end
    return INK.VALUE
end

-- A plain result from fn, or nil on an error or a secret.
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v
end

-- The unit's raid group (1-8), or nil outside a raid or when the client won't say.
local function raidGroup(u)
    local index = tonumber(string.match(u, "^raid(%d+)$")) or plain(UnitInRaid, u)
    if type(index) ~= "number" or type(GetRaidRosterInfo) ~= "function" then return nil end
    local ok, _, _, group = pcall(GetRaidRosterInfo, index)
    if not ok or isSecret(group) or type(group) ~= "number" then return nil end
    return group
end

-- Each part returns color, format, values (whole, possibly secret), or nil when
-- there's nothing to show. u is the unit, s a test mode sample instead, and fs
-- the text (its formats and other parts).
local PART = {}

function PART.health(f, u, fs, s)
    if s then return INK.VALUE, DUI.Health.FormatSample(fs.healthFormat or "value", s.health or 100, s.healthValue, true) end
    -- Dead, ghost or offline: show the word, unless a status part already does.
    if f.state then
        if fs.wants.status then return nil end
        return INK.LABEL, "%s", ns.UF.STATE_TEXT[f.state]
    end
    return INK.VALUE, DUI.Health.Format(fs.healthFormat or "value", u, true)
end

function PART.power(f, u, fs, s)
    if s then return INK.VALUE, "%s", tostring(s.power or 0) end
    return INK.VALUE, ns.UF.PowerFormat(fs.powerFormat or "value", u)
end

function PART.name(f, u, fs, s)
    local name
    if s then name = s.name else name = DUI.UnitName(u, f.spec and f.spec.group or nil) end
    if type(name) == "nil" then return nil end
    return INK.VALUE, "%s", name
end

-- Players only. Every mob has a class too, and it means nothing.
function PART.class(f, u, fs, s)
    if s then
        local names = LOCALIZED_CLASS_NAMES_MALE
        local name = s.class and type(names) == "table" and names[s.class] or s.class
        if not name then return nil end
        return classColor(s.class), "%s", name
    end
    if plain(UnitIsPlayer, u) ~= true then return nil end
    local name, token = UnitClass(u)
    if type(name) == "nil" then return nil end
    return classColor(token), "%s", name
end

function PART.level(f, u, fs, s)
    local level
    if s then level = s.level or 60 else level = UnitLevel(u) end
    if isSecret(level) then return INK.VALUE, "%d", level end
    if type(level) ~= "number" then return nil end
    if level < 1 then return INK.VALUE, "%s", "??" end
    return levelColor(s and "player" or u, level), "%d", level
end

-- Dead, ghost or offline first, then away or busy.
function PART.status(f, u, fs, s)
    if s then return INK.LABEL, "%s", L["AFK"] end
    if f.state then return INK.LABEL, "%s", ns.UF.STATE_TEXT[f.state] end
    if plain(UnitIsAFK, u) == true then return INK.LABEL, "%s", L["AFK"] end
    if plain(UnitIsDND, u) == true then return INK.LABEL, "%s", L["DND"] end
    return nil
end

function PART.group(f, u, fs, s)
    local group
    if s then group = 1 else group = raidGroup(u) end
    if not group then return nil end
    return INK.LABEL, L["G%d"], group
end

function PART.guild(f, u, fs, s)
    local guild
    if s then
        guild = L["Guild"]
    elseif type(GetGuildInfo) == "function" then
        local ok, g = pcall(GetGuildInfo, u)
        if ok then guild = g end
    end
    if type(guild) == "nil" then return nil end
    return INK.LABEL, "<%s>", guild
end

function PART.classification(f, u, fs, s)
    local c
    if s then c = s.classification or "elite" else c = plain(UnitClassification, u) end
    local word = c and CLASSIFICATION[c]
    if not word then return nil end
    return ns.UF.CREST_COLORS[ns.UF.CREST[c]] or INK.VALUE, "%s", L[word]
end

-- Builds the whole text from its parts as one format with every value passed
-- whole. A single part's color becomes the text's color. With two or more,
-- each wraps its own in a color code.
local fmtParts, colors, args = {}, {}, {}
local function compose(fs, f, u, s)
    local np, na = 0, 0
    for _, kind in ipairs(fs.kinds) do
        local c, fmt, a, b = PART[kind](f, u, fs, s)
        if fmt then
            np = np + 1
            fmtParts[np], colors[np] = fmt, c
            if type(a) ~= "nil" then na = na + 1; args[na] = a end
            if type(b) ~= "nil" then na = na + 1; args[na] = b end
        end
    end
    fs:SetAlpha(1)
    if np == 0 then
        fs:SetText("")
        return
    end
    local whole
    if np == 1 then
        whole = fmtParts[1]
        fs:SetTextColor(colors[1][1], colors[1][2], colors[1][3])
    else
        local Hex = DUI.Win.Parts.Hex
        for i = 1, np do fmtParts[i] = Hex(colors[i]) .. fmtParts[i] .. "|r" end
        whole = table.concat(fmtParts, fs.sep, 1, np)
        fs:SetTextColor(INK.VALUE[1], INK.VALUE[2], INK.VALUE[3])
    end
    fs:SetFormattedText(whole, unpack(args, 1, na))
end

-- A text with a single health or power part keeps the old behavior (full-health
-- fade, the client's own power text). Everything else is composed.
local function writeOne(fs, f, u)
    local kind = fs.kind
    if kind == "health" and not f.state then
        fs:SetTextColor(INK.VALUE[1], INK.VALUE[2], INK.VALUE[3])
        DUI.Health.Write(fs, fs.healthFormat or "value", u, true)
    elseif kind == "power" then
        fs:SetTextColor(INK.VALUE[1], INK.VALUE[2], INK.VALUE[3])
        ns.UF.WritePower(fs, fs.powerFormat or "value", u)
    else
        compose(fs, f, u)
    end
end

-- From the frame's updates. which = "health", "power", "identity" (name,
-- class, level...), "flags" or "roster", or nil for all.
function Texts.Update(f, which)
    if not f.extraOn or f.test then return end
    local u = f.unitToken
    if type(u) ~= "string" then return end
    local want = which and ON[which]
    for _, fs in ipairs(f.extraTexts) do
        if fs.kinds then
            local hit = not want
            if want then
                for k in pairs(fs.wants) do
                    if want[k] then hit = true end
                end
            end
            if hit then
                if #fs.kinds == 1 then writeOne(fs, f, u) else compose(fs, f, u) end
            end
        end
    end
end

-- A sample frame (test mode, the options preview). s is UF.ShowSample's unit.
function Texts.ShowSample(f, s)
    if not f.extraOn then return end
    for _, fs in ipairs(f.extraTexts) do
        if fs.kinds then compose(fs, f, nil, s) end
    end
end

-- Moving a raid member to another group doesn't change any unit token, so
-- every frame with a group part is updated by Units.lua's roster pass, one
-- frame after a burst of GROUP_ROSTER_UPDATE.

-- Add and remove (the options' Add piece menu and Remove buttons)

-- Writes a slot's fields straight into the settings, then sets one key so the
-- frames lay out once (same as Looks.Apply).
local function writeSlot(path, fields, last)
    local mod = DUI:GetModule("UnitFrames")
    if not (mod and type(mod.db) == "table") then return false end
    for field, v in pairs(fields) do
        if field ~= last then
            if type(v) == "table" then v = { unpack(v) } end
            DUI.DB.SetPath(mod.db, path .. "." .. field, v)
        end
    end
    return DUI:Set("UnitFrames", path .. "." .. last, fields[last])
end

-- The first free slot of frame's list at sub ("texts" or "auras"), or nil.
function Texts.FreeSlot(frame, sub, slots)
    for _, key in ipairs(slots) do
        if DUI:Get("UnitFrames", frame .. "." .. sub .. "." .. key .. ".show") ~= true then return key end
    end
end

-- Resets a slot to its defaults with fields applied on top, turned on.
local function fill(frame, sub, key, fields)
    local d = ns.DEFAULTS[frame] and ns.DEFAULTS[frame][sub] and ns.DEFAULTS[frame][sub][key]
    if type(d) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(d) do out[k] = v end
    for k, v in pairs(fields or {}) do out[k] = v end
    out.show = true
    if not writeSlot(frame .. "." .. sub .. "." .. key, out, "show") then return nil end
    return key
end

-- Adds a text showing kind to frame ("target"). Returns its slot key, or nil
-- when all four are in use.
function Texts.Add(frame, kind)
    if not Texts.LABELS[kind] then return nil end
    local key = Texts.FreeSlot(frame, "texts", ns.TEXT_SLOTS)
    return key and fill(frame, "texts", key, { kind = kind })
end

-- An extra aura group (debuffs or buffs) on frame ("raid").
function Texts.AddAuras(frame, what)
    local key = Texts.FreeSlot(frame, "auras", ns.AURA_SLOTS)
    return key and fill(frame, "auras", key, { what = what == "buffs" and "buffs" or "debuffs" })
end

-- Resets a slot (text or aura group) to its defaults, which means off.
function Texts.Remove(frame, sub, key)
    local d = ns.DEFAULTS[frame] and ns.DEFAULTS[frame][sub] and ns.DEFAULTS[frame][sub][key]
    if type(d) ~= "table" then return false end
    return writeSlot(frame .. "." .. sub .. "." .. key, d, "show")
end

-- Plugin texts (DaylightUI.API's AddText): a kind like the ones above, in the
-- same pickers, written by the plugin's function under its name.

local pluginEvents, eventFrame = {}, nil   -- event -> { key = true }

local function pluginPart(spec)
    return function(f, u, fs, s)
        if s then return INK.VALUE, "%s", spec.sample or spec.label end
        local ok, text, r, g, b = pcall(spec.text, u, f)
        if not ok then
            DUI.SafeCallAs(spec.owner, function() error(text, 0) end)
            return nil
        end
        if type(text) == "nil" then return nil end
        local c = INK.VALUE
        if type(r) == "number" and not isSecret(r) and not isSecret(g) and not isSecret(b) then c = { r, g, b } end
        return c, "%s", text
    end
end

-- A game event a plugin's text listens to. Frames showing that unit redraw it.
-- Read straight off the frames when they show, without building lists, since
-- in a raid these events fire many times a second.
local EVENT_KINDS = { "unit", "party", "raid" }
local function onEvent(_, event, unit)
    local keys = pluginEvents[event]
    if not keys or isSecret(unit) or type(unit) ~= "string" then return end
    local R = DUI.APIReport
    for i = 1, #EVENT_KINDS do
        local live = R.Live(EVENT_KINDS[i])
        if live then
            for f, shown in pairs(live) do
                if shown == unit then
                    for key in pairs(keys) do Texts.Update(f, key) end
                end
            end
        end
    end
end

function Texts.AddKind(spec)
    local key = spec.key
    if not Texts.LABELS[key] then
        Texts.KINDS[#Texts.KINDS + 1] = key
        Texts.MORE_KINDS[#Texts.MORE_KINDS + 1] = key
    end
    Texts.LABELS[key], Texts.MORE_LABELS[key] = spec.label, spec.label
    PART[key] = pluginPart(spec)
    ON[key] = { [key] = true }
    for _, which in ipairs(type(spec.on) == "table" and spec.on or {}) do
        if ON[which] then ON[which][key] = true end
    end
    for _, event in ipairs(type(spec.events) == "table" and spec.events or {}) do
        if type(event) == "string" then
            if not eventFrame then
                eventFrame = CreateFrame("Frame")
                eventFrame:SetScript("OnEvent", onEvent)
            end
            if not pluginEvents[event] then
                pluginEvents[event] = {}
                pcall(eventFrame.RegisterEvent, eventFrame, event)
            end
            pluginEvents[event][key] = true
        end
    end
end

-- Registers the ones requested before this module loaded, then each later one.
do
    local R = DUI.APIReport
    if R and R.Texts then
        local order, all = R.Texts()
        for _, key in ipairs(order) do Texts.AddKind(all[key]) end
        DUI.On("TextsChanged", function(key)
            local _, now = R.Texts()
            if now[key] then Texts.AddKind(now[key]) end
        end)
    end
end
