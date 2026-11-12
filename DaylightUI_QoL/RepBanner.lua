-- Reputation banner, a smaller version of the level-up. When a faction's standing
-- goes up, the new standing fades in at the top of the screen in its color, with
-- the faction name and a bar showing progress into it.
-- It shares the top of the screen with the level-up and zone title, so it waits
-- while those or the game's toasts are up. Several banners play in order.
-- Each faction's last standing is remembered so only a rise shows. Factions not
-- seen before (inside a collapsed header) rely on the reputation chat message to
-- tell whether the gain crossed into a new standing.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion = DUI.Style, DUI.Motion

local RepBanner = {
    Y = -192,           -- the line's height from the screen's top: the zone title's spot
    WIDTH = 260,        -- the line at full spread
    LINE = 1,           -- its thickness
    HAZE = 54,          -- the soft glow round the line
    NAME = 22,          -- the standing's size (display text)
    RISE = 10,          -- px the standing rises as it comes in
    BAR_W = 150,        -- the bar under the faction's name
    HOLD = 2.5,         -- seconds it stays
    DRIFT = 6,          -- px it rises as it goes
    MATCH = 2,          -- seconds a chat line's gain counts for a faction first seen
    GLOW = DUI.MEDIA .. "char-glow.png",
    LAST = 8,           -- Exalted
    -- The game's "Your reputation with %s has increased by %d." lines.
    GAIN_STRINGS = { "FACTION_STANDING_INCREASED", "FACTION_STANDING_INCREASED_BONUS",
        "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_ACH_BONUS" },
    -- The preview's faction (the game sends the real ones): name, standing, share of the way.
    SAMPLE = { L["Stormwind"], 6, 0.35 },
}
ns.RepBanner = RepBanner
ns.features[#ns.features + 1] = RepBanner

local mod, f, wired
local tracking = false  -- the standings are being kept (it's on)
local run = 0           -- each show's id: a newer one stops the older one's timers
local current           -- the show up now: { name, reaction, share }
local queue = {}        -- standings waiting for the top of the screen
local seen = {}         -- factionID -> its standing at the last look
local gains = {}        -- faction name -> { amount, t } from the chat line
local dirty, scanAll, pending = {}, false, false

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.repBanner == true end

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- ---------------------------------------------------------------------
-- The banner
-- ---------------------------------------------------------------------

local function build()
    if f then return f end
    f = CreateFrame("Frame", "DaylightUIRepBanner", UIParent)
    DUI.Movers.FollowScale(f)
    f:SetSize(RepBanner.WIDTH, 1)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(false)
    f:Hide()
    -- The top is free again: what waited plays now (a zone change first).
    f:SetScript("OnHide", function()
        current = nil
        if ns.ZoneTitle then ns.ZoneTitle.Resume() end
        RepBanner.Resume()
    end)

    f.haze = f:CreateTexture(nil, "BACKGROUND")
    f.haze:SetTexture(RepBanner.GLOW)
    f.haze:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.haze:SetBlendMode("ADD")

    -- The line: two halves from the middle out (painted per show, paint()).
    f.left = f:CreateTexture(nil, "ARTWORK")
    f.left:SetColorTexture(1, 1, 1, 1)
    f.left:SetPoint("RIGHT", f, "CENTER", 0, 0)
    f.right = f:CreateTexture(nil, "ARTWORK")
    f.right:SetColorTexture(1, 1, 1, 1)
    f.right:SetPoint("LEFT", f, "CENTER", 0, 0)
    f.left:SetHeight(RepBanner.LINE)
    f.right:SetHeight(RepBanner.LINE)

    f.standing = Style.Text(f, RepBanner.NAME, "CENTER")
    f.faction = Style.Text(f, Style.SIZE.body, "CENTER")
    f.faction:SetPoint("TOP", f, "CENTER", 0, -8)
    Style.InkText(f.faction, "LABEL")
    f.bar = DUI.Widgets.Bar(f)
    f.bar:SetWidth(RepBanner.BAR_W)
    f.bar:SetPoint("TOP", f.faction, "BOTTOM", 0, -7)
    return f
end

-- The standing's color: the light end of its gradient pair, else the game's
-- bar color, else white.
function RepBanner.Color(reaction)
    local G, key = DUI.Gradients, "REP_" .. tostring(reaction)
    if G and G.Has(key) then
        local a, b = G.PaintRGB(key)
        local function lum(c) return c[1] * 0.299 + c[2] * 0.587 + c[3] * 0.114 end
        return lum(a) >= lum(b) and a or b
    end
    local c = type(FACTION_BAR_COLORS) == "table" and FACTION_BAR_COLORS[reaction]
    if c then return { c.r, c.g, c.b } end
    return Style.INK.VALUE
end

-- "Honored", in the player's gender where the language has one.
function RepBanner.StandingName(reaction)
    if type(GetText) == "function" then
        local ok, s = pcall(GetText, "FACTION_STANDING_LABEL" .. tostring(reaction), UnitSex and UnitSex("player") or 2)
        if ok and type(s) == "string" then return s end
    end
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or ""
end

local function paint(reaction)
    local c = RepBanner.Color(reaction)
    f.standing:SetTextColor(c[1], c[2], c[3])
    f.left:SetGradient("HORIZONTAL", CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], 1))
    f.right:SetGradient("HORIZONTAL", CreateColor(c[1], c[2], c[3], 1), CreateColor(c[1], c[2], c[3], 0))
    f.haze:SetVertexColor(c[1], c[2], c[3])
    local G, key = DUI.Gradients, "REP_" .. tostring(reaction)
    if G and G.Has(key) then
        local lo, hi = G.Colors(key)
        DUI.Widgets.BarPair(f.bar, lo, hi, G.Orientation())
    else
        DUI.Widgets.BarFrom(f.bar, c[1], c[2], c[3])
    end
end

-- The line and its glow at a share p of their full spread.
local function spread(p)
    local w = math.max(1, RepBanner.WIDTH * p)
    f.left:SetWidth(w / 2)
    f.right:SetWidth(w / 2)
    f.left:SetShown(p > 0)
    f.right:SetShown(p > 0)
    f.haze:SetSize(w * 1.1, RepBanner.HAZE)
    f.haze:SetAlpha(0.3 * p)
end

local function place(p)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "TOP", 0, RepBanner.Y + RepBanner.DRIFT * p)
end

local function rise(p)
    f.standing:SetPoint("BOTTOM", f, "CENTER", 0, 6 - RepBanner.RISE * (1 - p))
end

local function out(id, dur)
    Motion.Tween("repbanner:out", 0, 1, dur or Motion.CLOSE, function(p)
        if id ~= run then return end
        place(p)
        f:SetAlpha(1 - p)
    end, function() if id == run then f:Hide() end end)
end

-- Plays one standing: { name, reaction, share }.
local function play(item)
    build()
    run = run + 1
    local id = run
    local function later(t, fn)
        C_Timer.After(t, function() if id == run then fn() end end)
    end
    current = item
    paint(item.reaction)
    f.standing:SetText(RepBanner.StandingName(item.reaction))
    f.faction:SetText(item.name)
    f.standing:SetAlpha(0)
    Motion.Fade(f.faction, 0, 0, 0)   -- stops a fade-in still playing from the last show
    Motion.Fade(f.bar, 0, 0, 0)
    f.bar:SetValue(0)
    spread(0)
    rise(0)
    place(0)
    f:SetAlpha(1)
    f:Show()

    -- 1. The standing rises in as the line draws out from the middle.
    Motion.Tween("repbanner:in", 0, 1, Motion.SLOW, function(p)
        if id ~= run then return end
        rise(p)
        f.standing:SetAlpha(p)
        spread(p)
    end)
    -- 2. The faction's name, then its bar filling to where you are now.
    later(0.25, function()
        Motion.Fade(f.faction, 0, 1, Motion.NORMAL)
        Motion.Fade(f.bar, 0, 1, Motion.NORMAL)
    end)
    later(0.45, function()
        Motion.Tween("repbanner:bar", 0, item.share, Motion.SLOW, function(v)
            if id == run then f.bar:SetValue(v) end
        end)
    end)
    -- 3. It holds, then goes.
    later(Motion.SLOW + RepBanner.HOLD, function() out(id) end)
end

-- The level-up, the zone title or the game's toasts have the top of the
-- screen (the game's IsCurrentlyToasting hands back the toast frame or nil).
local function busy()
    if ns.LevelUp and ns.LevelUp.Showing() then return true end
    if ns.ZoneTitle and ns.ZoneTitle.Showing() then return true end
    local m = _G.EventToastManagerFrame
    return type(m) == "table" and type(m.IsCurrentlyToasting) == "function" and m:IsShown()
        and m:IsCurrentlyToasting() ~= nil
end

function RepBanner.Showing() return f ~= nil and f:IsShown() end

-- The next standing waiting, once the top is free.
function RepBanner.Resume()
    if #queue == 0 or RepBanner.Showing() or busy() or not enabled() then return end
    play(table.remove(queue, 1))
end

-- A standing gone up: { name, reaction, share }.
function RepBanner.Push(item)
    queue[#queue + 1] = item
    RepBanner.Resume()
end

-- A level-up takes the spot: this one steps aside and plays again after it.
function RepBanner.Stop()
    if not RepBanner.Showing() then return end
    if current and not current.sample then table.insert(queue, 1, current) end   -- a preview just goes
    current = nil
    run = run + 1
    out(run, Motion.FAST)
end

-- Preview. Plays right away even when switched off or the top is busy, and is
-- never queued. The zone title steps aside for it.
function RepBanner.Preview()
    local s = RepBanner.SAMPLE
    if ns.ZoneTitle then ns.ZoneTitle.Stop() end
    play({ name = s[1], reaction = s[2], share = s[3], sample = true })
end

-- ---------------------------------------------------------------------
-- Reading the standings
-- ---------------------------------------------------------------------

-- A faction's show: its name, standing and how far into it you are.
function RepBanner.ItemOf(d)
    local lo, hi, now = d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
    local share = 1
    if type(lo) == "number" and type(hi) == "number" and type(now) == "number" and hi > lo
        and d.reaction < RepBanner.LAST then
        share = math.max(0, math.min(1, (now - lo) / (hi - lo)))
    end
    return { name = d.name or "", reaction = d.reaction, share = share }
end

-- "Your reputation with Stormwind has increased by 250." -> "Stormwind", 250.
local gainPatterns
function RepBanner.ParseGain(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    if not gainPatterns then
        gainPatterns = {}
        for _, name in ipairs(RepBanner.GAIN_STRINGS) do
            local p = ns.LootFeed.Pattern(_G[name])
            if p then gainPatterns[#gainPatterns + 1] = "^" .. p .. "$" end
        end
    end
    for _, p in ipairs(gainPatterns) do
        local a, b = msg:match(p)
        if a and b then
            -- A language may put the amount first.
            if tonumber(a) and not tonumber(b) then a, b = b, a end
            if tonumber(b) then return a, tonumber(b) end
        end
    end
    return nil
end

local function byID(id)
    local get = C_Reputation and C_Reputation.GetFactionDataByID
    if type(get) ~= "function" then return nil end
    local d = get(id)
    if type(d) ~= "table" or type(d.reaction) ~= "number" or secret(d.reaction) then return nil end
    return d
end

-- Re-reads one faction. With `quiet` it only records the standing (login, switching on).
local function check(id, quiet)
    local d = byID(id)
    if not d then return end
    local was = seen[id]
    if was == nil and not quiet then
        -- First seen now: its chat line tells whether the gain crossed in.
        local g = type(d.name) == "string" and gains[d.name]
        local now, lo = d.currentStanding, d.currentReactionThreshold
        if g and GetTime() - g.t <= RepBanner.MATCH and type(now) == "number" and type(lo) == "number"
            and now - g.amount < lo then
            was = d.reaction - 1
        end
    end
    seen[id] = d.reaction
    if not quiet and was and d.reaction > was then RepBanner.Push(RepBanner.ItemOf(d)) end
end

-- Every faction the list shows (collapsed headers hide theirs), plus every one
-- already known.
local function scan(quiet)
    local C = C_Reputation
    if type(C) ~= "table" or type(C.GetNumFactions) ~= "function" then return end
    local ids, listed = {}, {}
    for i = 1, C.GetNumFactions() or 0 do
        local d = C.GetFactionDataByIndex(i)
        if type(d) == "table" and type(d.factionID) == "number" and d.factionID > 0
            and (not d.isHeader or d.isHeaderWithRep) then
            ids[#ids + 1] = d.factionID
            listed[d.factionID] = true
        end
    end
    for id in pairs(seen) do
        if not listed[id] then ids[#ids + 1] = id end
    end
    for _, id in ipairs(ids) do check(id, quiet) end
end

-- Looked at one frame later, so the chat line of the same gain is in.
local function flush()
    pending = false
    if not enabled() then dirty, scanAll = {}, false return end
    local all = scanAll
    local ids = dirty
    dirty, scanAll = {}, false
    if all then scan(false) end
    for id in pairs(ids) do check(id, false) end
end

local function soon()
    if pending then return end
    pending = true
    C_Timer.After(0, flush)
end

local function wire()
    if wired then return end
    wired = true
    DUI.RegisterEvent("FACTION_STANDING_CHANGED", function(_, id)
        if not enabled() or type(id) ~= "number" or secret(id) then return end
        dirty[id] = true
        soon()
    end)
    DUI.RegisterEvent("UPDATE_FACTION", function()
        if not enabled() then return end
        scanAll = true
        soon()
    end)
    DUI.RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE", function(_, msg)
        if not enabled() then return end
        local name, amount = RepBanner.ParseGain(msg)
        if name then gains[name] = { amount = amount, t = GetTime() } end
    end)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if enabled() then scan(true) end
    end)
    DUI.RegisterCommand("rep", RepBanner.Preview, L["/dui rep - preview the reputation banner"])
end

function RepBanner.Enable(m)
    mod = m
    wire()
    tracking = enabled()
    if tracking then scan(true) end
end

-- Switched on: today's standings remembered first, so nothing old shows.
function RepBanner.Refresh(m)
    mod = m
    if not enabled() then
        tracking = false
        queue, seen = {}, {}
        if f then run = run + 1; current = nil; f:Hide() end
    elseif not tracking then
        tracking = true
        scan(true)
    end
end
