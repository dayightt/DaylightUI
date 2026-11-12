-- Quest progress popup. Replaces the game's yellow quest lines in the middle of the
-- screen ("Mindless Zombie slain: 5/8") with small text over the world, the count
-- set apart in white, and a thin bar underneath in the tracker's bar color that
-- glides to the new count with a light sweeping along it. A finished objective
-- gets a tick, a finished quest turns gold. Each line holds a moment and leaves;
-- the same objective again updates its line in place, and up to ROWS lines show
-- at once.
--
-- The game's own lines are suppressed the same way QoL's quiet error messages do
-- it (QoL/Errors.lua). The game's error frame (Blizzard_UIErrorsFrame,
-- UIErrorsMixin:TryDisplayMessage) skips every message type in its global
-- BLACK_LISTED_MESSAGE_TYPES, so the quest types are claimed there through the
-- core (DUI.ClaimMessageType, which coordinates with QoL). No hook. The game then
-- plays no sound for them either, so the sound it would have played is played
-- here (DUI.PlayGameMessageSound). The text is the game's own, so every language
-- reads right; the count is the last "have/need" in the line.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local Progress = {
    MOVER = "quests.progress",
    -- Above the game's message frame (TOP -122, UIErrorsFrame.xml), so its red errors
    -- keep their own spot below.
    DEFAULT = { "TOP", nil, "TOP", 0, -92 },
    W = 260,
    ROW_H = 24,
    ROWS = 3,
    BAR_W = 150, BAR_H = 2,
    GAP = 3,            -- text to bar
    HOLD = 1.8,         -- seconds a line stays (default for the progressHold setting)
    RISE = 4,           -- px a new line rises in from
    SWEEP_W = 28,       -- width of the light sweeping along the bar
    SAMPLE_EVERY = 1.5, -- seconds between the sample's kills
    TEST_PART = "questprogress",
    OWNER = "questprogress",
    -- The game's quest message types drawn here, by LE_GAME_ERR_<name>. Names this
    -- client lacks are skipped (those lines stay the game's).
    TYPES = {
        QUEST_ADD_KILL_SII = "count", QUEST_ADD_ITEM_SII = "count", QUEST_ADD_FOUND_SII = "count",
        QUEST_ADD_PLAYER_KILL_SII = "count",
        QUEST_OBJECTIVE_COMPLETE_S = "done", QUEST_UNKNOWN_COMPLETE = "done",
        QUEST_COMPLETE_S = "complete",
    },
}
ns.Progress = Progress

local mod, holder, listening, sampleTicker, sampleStep
local kinds = {}   -- [type id] = kind, for the types drawn here
local rows = {}
Progress.rows = rows

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.progress == true end

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

local function apply()
    local claim = enabled()
    for name, kind in pairs(Progress.TYPES) do
        local id = _G["LE_GAME_ERR_" .. name]
        if type(id) == "number" then
            kinds[id] = kind
            if claim then DUI.ClaimMessageType(id, Progress.OWNER) else DUI.ReleaseMessageType(id, Progress.OWNER) end
        end
    end
end

-- Splits a line into its words and the last "have/need", in any word order:
-- "Mindless Zombie slain: 5/8" -> "Mindless Zombie slain", 5, 8. A line without
-- a count comes back whole.
function Progress.Parse(text)
    local s, e, have, need
    local at = 1
    while true do
        local a, b, h, n = string.find(text, "(%d+)%s*/%s*(%d+)", at)
        if not a then break end
        s, e, have, need, at = a, b, h, n, b + 1
    end
    if not s then return text end
    local before = string.gsub(string.sub(text, 1, s - 1), "[%s:]+$", "")
    local after = string.gsub(string.sub(text, e + 1), "^[%s:]+", "")
    local words = before ~= "" and before or after
    return words, tonumber(have), tonumber(need)
end

local function look() return ns.Look.Get(mod.db) end

local function textSize() return ((mod.db.sizes and mod.db.sizes.objective) or 11) + 1 end

local function newRow(i)
    local r = CreateFrame("Frame", nil, holder)
    r:SetSize(Progress.W, Progress.ROW_H)
    r:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * Progress.ROW_H)
    r:EnableMouse(false)
    r:Hide()
    -- Words and count sit together in the middle (the line frame is as wide as both).
    r.line = CreateFrame("Frame", nil, r)
    r.line:SetHeight(14)
    r.line:SetPoint("TOP", r, "TOP", 0, 0)
    r.size = textSize()
    r.label = Style.Text(r.line, r.size, "LEFT", ns.MEDIA.font)
    r.label:SetPoint("LEFT", r.line, "LEFT", 0, 0)
    r.label:SetWordWrap(false)
    r.count = Style.Text(r.line, r.size, "LEFT", ns.MEDIA.font)
    r.count:SetPoint("LEFT", r.label, "RIGHT", 4, 0)
    r.tick = r.line:CreateTexture(nil, "OVERLAY")
    r.tick:SetTexture(ns.Look.ICONS.tick)
    r.tick:SetDesaturated(true)
    r.tick:SetSize(10, 10)
    r.tick:Hide()
    r.bar = Style.Bar(r, nil, ns.MEDIA.bars.progress)
    r.bar:SetSize(Progress.BAR_W, Progress.BAR_H)
    r.bar:SetPoint("TOP", r.line, "BOTTOM", 0, -Progress.GAP)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(0)
    r.sweep = r.bar:CreateTexture(nil, "OVERLAY")
    r.sweep:SetTexture(ns.Look.WHITE)
    r.sweep:SetBlendMode("ADD")
    r.sweep:SetHeight(Progress.BAR_H + 2)
    r.sweep:Hide()
    r.frac = 0
    r.id = 0
    return r
end

local function build()
    if holder then return holder end
    holder = CreateFrame("Frame", "DaylightUIQuestProgress", UIParent)
    holder:SetSize(Progress.W, Progress.ROW_H * Progress.ROWS)
    holder:SetFrameStrata("HIGH")
    holder:EnableMouse(false)
    for i = 1, Progress.ROWS do rows[i] = newRow(i) end
    DUI.Movers.Register(holder, Progress.MOVER, "Quest progress", Progress.DEFAULT, { active = enabled,
        scale = function(s) holder:SetScale((mod.db.progressScale or 1) * s) end })
    return holder
end

-- Lays out the words, count and tick as one centered piece. A secret line can't be
-- measured, so it takes the row's full width, centered.
local function fit(r, plain)
    r.label:ClearAllPoints()
    if not plain then
        r.label:SetPoint("LEFT", r.line, "LEFT", 0, 0)
        r.label:SetPoint("RIGHT", r.line, "RIGHT", 0, 0)
        r.label:SetJustifyH("CENTER")
        r.line:SetWidth(Progress.W)
        return
    end
    r.label:SetPoint("LEFT", r.line, "LEFT", 0, 0)
    r.label:SetJustifyH("LEFT")
    local lw = r.label:GetStringWidth()
    lw = type(lw) == "number" and lw or 0
    local cw = r.count:GetText() ~= "" and r.count:GetStringWidth() or 0
    cw = type(cw) == "number" and cw or 0
    local w = lw + (cw > 0 and cw + 4 or 0)
    r.tick:ClearAllPoints()
    if r.tick:IsShown() then
        r.tick:SetPoint("LEFT", cw > 0 and r.count or r.label, "RIGHT", 4, 0)
        w = w + 14
    end
    r.line:SetWidth(math.max(1, math.min(w, Progress.W)))
end

-- Which row a line goes into: the one already showing this objective, else a free
-- one, else the oldest.
local function rowFor(key)
    local free, oldest
    for _, r in ipairs(rows) do
        if r:IsShown() and not r.leaving and key ~= nil and r.key == key then return r end
        if not free and (not r:IsShown() or r.leaving) then free = r end
        if r:IsShown() and (not oldest or r.since < oldest.since) then oldest = r end
    end
    return free or oldest
end

local function leave(r)
    if not r:IsShown() then return end
    r.leaving = true
    r.id = r.id + 1
    local id = r.id
    Motion.Fade(r, r:GetAlpha(), 0, Motion.SLOW)
    C_Timer.After(Motion.SLOW, function()
        if r.id ~= id then return end
        r.leaving = nil
        r:Hide()
    end)
end

local function hold(r)
    r.id = r.id + 1
    local id = r.id
    if r.held then return end
    C_Timer.After(mod.db.progressHold or Progress.HOLD, function() if r.id == id then leave(r) end end)
end

local function paintBar(r, lk, kind)
    if kind == "complete" then
        local cr, cg, cb = ns.Look.Color(lk, "ready")
        Style.SetBarGradient(r.bar, false)
        Style.SetBarColor(r.bar, cr, cg, cb)
        return { cr, cg, cb }
    end
    ns.Look.PaintBar(r.bar, lk)
end

local function sweep(r, color)
    Motion.Sweep(r.sweep, r.bar, { width = Progress.SWEEP_W, alpha = 0.8, color = color or { 1, 1, 1 },
        key = r.sweep, dur = 0.5 })
end

-- Shows one line. kind: count | done | complete. text: the game's words (plain or
-- secret). held: stays until released (the sample). messageType is the game's
-- (plain). A secret line can't be read or compared, so it gets one row per type
-- (otherwise per kind).
function Progress.Show(kind, text, held, messageType)
    build()
    local lk = look()
    local plain = not secret(text)
    local words, have, need
    if plain then words, have, need = Progress.Parse(text) end
    local key = words
    if not plain then key = "secret:" .. tostring(messageType or kind) end
    local r = rowFor(key)
    local fresh = not r:IsShown() or r.leaving
    local was = r.key == key and not fresh and r.have or nil
    r.key, r.have, r.held = key, have, held
    r.since = GetTime()
    r.leaving = nil

    if r.size ~= textSize() then
        r.size = textSize()
        Style.SetTextSize(r.label, r.size)
        Style.SetTextSize(r.count, r.size)
    end

    -- Words, count and colors.
    r.label:SetText(plain and words or text)
    if kind == "complete" then
        r.label:SetTextColor(ns.Look.Color(lk, "ready"))
    else
        r.label:SetTextColor(ns.Look.Color(lk, "objective"))
    end
    r.count:SetText((plain and have and need and kind ~= "complete") and (have .. "/" .. need) or "")
    r.count:SetTextColor(ns.Look.Color(lk, "count"))
    r.tick:SetVertexColor(ns.Look.Color(lk, "tick"))
    r.tick:SetShown(kind == "done" and plain)
    fit(r, plain)

    -- The bar shows the count, full for a finished objective or quest.
    local frac
    if kind == "done" or kind == "complete" then frac = 1
    elseif have and need and need > 0 then frac = math.min(1, have / need) end
    r.bar:SetShown(frac ~= nil)
    local color
    if frac then
        color = paintBar(r, lk, kind)
        local from = fresh and (have and need and need > 0 and math.max(0, (have - 1) / need) or 0) or r.frac
        r.frac = frac
        Motion.Tween(r.bar, from, frac, Motion.SLOW, function(v) r.bar:SetValue(v) end)
    end

    if fresh then
        Motion.Fade(r, 1, 1, 0)   -- stops a fade-out still in progress
        r:Show()
        Motion.Appear(r, Progress.RISE)
    elseif was and have and have > was then
        Motion.Bump(r.count, 1.15, Motion.FAST)
    end
    if kind == "done" and r.tick:IsShown() then Motion.Pop(r.tick, 0.6, Motion.NORMAL) end
    if frac then sweep(r, color) end
    hold(r)
    return r
end

-- Removes every line (switched off, or the sample ended).
function Progress.Clear()
    for _, r in ipairs(rows) do
        r.held = nil
        leave(r)
    end
end

local function onInfo(_, messageType, message)
    if secret(messageType) or type(messageType) ~= "number" then return end
    local kind = kinds[messageType]
    if not kind or not enabled() or DUI.GameMessagesSuppressed() then return end
    if DUI.MessageTypeOwner(messageType) ~= Progress.OWNER then return end
    if not secret(message) and type(message) ~= "string" then return end
    DUI.SafeCall(Progress.Show, kind, message, nil, messageType)
    DUI.PlayGameMessageSound(messageType)
end

-- The sample: a few kills counting up, the objective done, the quest done, and
-- around again, for as long as test mode or unlock mode needs it.
Progress.SAMPLE = {
    { "count", L["Mindless Zombie slain"], 3 }, { "count", L["Mindless Zombie slain"], 4 },
    { "count", L["Mindless Zombie slain"], 5 }, { "count", L["Mindless Zombie slain"], 6 },
    { "count", L["Mindless Zombie slain"], 7 }, { "done", L["Mindless Zombie slain"], 8 },
    { "complete", L["The Mindless Ones completed."] },
}

local function sampleShow()
    local s = Progress.SAMPLE[sampleStep]
    local text = s[3] and (s[2] .. ": " .. s[3] .. "/8") or s[2]
    if s[1] == "complete" then
        for _, r in ipairs(rows) do r.held = nil; leave(r) end
    end
    Progress.Show(s[1], text, true)
    sampleStep = sampleStep % #Progress.SAMPLE + 1
end

local function sampleWanted()
    if not enabled() then return false end
    if DUI.testMode and DUI.TestPartShown(Progress.TEST_PART) then return true end
    return DUI.Movers ~= nil and DUI.Movers.unlocked == true
end

function Progress.UpdateSample()
    if sampleWanted() then
        if sampleTicker then return end
        build()
        sampleStep = 1
        sampleShow()
        sampleTicker = C_Timer.NewTicker(Progress.SAMPLE_EVERY, function() DUI.SafeCall(sampleShow) end)
    elseif sampleTicker then
        sampleTicker:Cancel()
        sampleTicker = nil
        Progress.Clear()
    end
end

function Progress.Enable(m)
    mod = m
    if not listening then
        listening = true
        -- Always registered (the shared event frame has no unregister). Nothing is
        -- claimed while this is off, so nothing shows then.
        DUI.RegisterEvent("UI_INFO_MESSAGE", onInfo)
        DUI.RegisterTestPart(Progress.TEST_PART, "Quest progress", 96, enabled)
        DUI.On("TestModeChanged", Progress.UpdateSample)
        DUI.On("TestPartChanged", function(key) if key == Progress.TEST_PART then Progress.UpdateSample() end end)
        DUI.On("UnlockChanged", Progress.UpdateSample)
    end
    build()
    apply()
end

function Progress.Refresh()
    if not mod then return end
    apply()
    if holder then
        -- The whole popup scales through the mover (its size times the piece's), and the
        -- mover puts it back on its saved center.
        DUI.Movers.Apply(Progress.MOVER)
    end
    if DUI.Movers.Recheck then DUI.Movers.Recheck(Progress.MOVER) end
    if not enabled() then
        if sampleTicker then sampleTicker:Cancel(); sampleTicker = nil end
        Progress.Clear()
    else
        Progress.UpdateSample()
    end
end
