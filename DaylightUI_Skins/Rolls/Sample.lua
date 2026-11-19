-- Made-up rolls for the options page's sample and for test mode: two copies of
-- one ring and a robe, at different points of a roll, with a group of seven.
-- No game calls beyond item names; nothing here can roll on anything.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local RollSample = {
    LOOP = 22,      -- seconds one test mode round takes before it starts over
    PICK_EVERY = 1.4,
    ROLL_EVERY = 0.6,
    RING = 17063,   -- Band of Accuria
    ROBE = 19145,   -- Robe of Volatile Power
}
ns.RollSample = RollSample

-- name, class, pick, roll, you
RollSample.GROUP = {
    { "Bram Holloway", "WARRIOR", "need", 91 },
    { "Kaelith Dawnmere", "MAGE", "need", 64 },
    { "Mira Calloway", "HUNTER", "need", 72, true },
    { "Tomas Reed", "ROGUE", "greed", 37 },
    { "Sera Voss", "PRIEST", "greed", 98 },
    { "Ilyra Fenwick", "DRUID", "greed", 22 },
    { "Doran Ashby", "PALADIN", "pass" },
}

-- The item's real name, icon and quality when the game knows it.
local function item(id, name, quality)
    local get = C_Item and C_Item.GetItemInfo
    local n, link, q, _, _, _, _, _, _, icon
    if type(get) == "function" then n, link, q, _, _, _, _, _, _, icon = get(id) end
    if type(n) ~= "string" then n = name end
    return {
        name = n, link = type(link) == "string" and link or ("|Hitem:" .. id .. "|h[" .. n .. "]|h"),
        itemID = id, quality = type(q) == "number" and q or quality, icon = icon or 134400,
    }
end

local function drop(rollID, it, now, twin)
    return {
        rollID = rollID, link = it.link, itemID = it.itemID, name = it.name, icon = it.icon, quality = it.quality,
        bop = true, count = 1, sample = true, twin = twin,
        can = { need = true, greed = true, disenchant = false, transmog = false },
        reasons = {}, start = now, duration = 60, players = {}, order = {}, lootListKey = 0,
    }
end

local function seat(d, i)
    local g = RollSample.GROUP[i]
    local first = g[1]:match("^(%S+)")
    local p = { key = first, first = first, name = g[1], class = g[2], self = g[5] or nil }
    d.players[first] = p
    d.order[#d.order + 1] = first
    if p.self then d.me = first end
    return p, g
end

local function pickAll(d, rolls)
    for i in ipairs(RollSample.GROUP) do
        local p, g = seat(d, i)
        p.pick, p.seq = g[3], i
        if rolls then p.roll = g[4] end
    end
end

-- Three rolls: the first ring just won, the second ring still being picked (you
-- haven't yet), the robe rolling after your Need.
function RollSample.Demo(now)
    now = now or GetTime()
    local ring = item(RollSample.RING, "Band of Accuria", 4)
    local robe = item(RollSample.ROBE, "Robe of Volatile Power", 4)
    local won = drop(-1, ring, now - 40, { 1, 2 })
    pickAll(won, true)
    won.players.Bram.won, won.winner, won.done, won.doneAt = true, "Bram", true, now
    local open = drop(-2, ring, now - 18, { 2, 2 })
    for i in ipairs(RollSample.GROUP) do seat(open, i) end
    open.players.Bram.hasOne = true
    for i, key in ipairs({ "Bram", "Sera", "Doran" }) do
        local p = open.players[key]
        for _, g in ipairs(RollSample.GROUP) do if g[1]:match("^(%S+)") == key then p.pick, p.seq = g[3], i end end
    end
    local rolling = drop(-3, robe, now - 30, nil)
    pickAll(rolling, false)
    rolling.mine = "need"
    rolling.players.Tomas.roll = 37
    return { won, open, rolling }
end

-- Test mode's round: the open ring's picks come in one by one, then the
-- numbers, then a winner; after a pause it starts over.
local round
function RollSample.Current(now)
    now = now or GetTime()
    if not round or now - round.t0 >= RollSample.LOOP then
        round = { t0 = now, drops = RollSample.Demo(now), step = 0 }
        local d = round.drops[2]
        d.start, d.duration = now, 14
        for _, p in pairs(d.players) do p.pick, p.seq, p.roll = nil, nil, nil end
        d.players.Bram.hasOne = true
        d.mine = nil
        round.drops[1].doneAt = now
    end
    return round.drops
end

-- Moves the round on; true when something changed.
function RollSample.Advance(now)
    local drops = RollSample.Current(now)
    local d, t = drops[2], now - round.t0
    local n = #RollSample.GROUP
    local want = math.floor(t / RollSample.PICK_EVERY)
    local picks = math.min(n, want)
    local rolls = math.max(0, math.floor((t - n * RollSample.PICK_EVERY) / RollSample.ROLL_EVERY))
    local step = picks + rolls
    if step == round.step then return false end
    round.step = step
    for i = 1, picks do
        local g = RollSample.GROUP[i]
        local p = d.players[g[1]:match("^(%S+)")]
        if not p.pick then p.pick, p.seq = g[3], i; if p.self then d.mine = g[3] end end
    end
    local rolled = 0
    for i = 1, n do
        local g = RollSample.GROUP[i]
        if g[4] and rolled < rolls then
            rolled = rolled + 1
            d.players[g[1]:match("^(%S+)")].roll = g[4]
        end
    end
    if picks == n and rolled == 6 and not d.done then
        d.players.Sera.won, d.winner, d.done, d.doneAt = true, "Sera", true, now
    end
    return true
end

-- The options page's sample: a compact card still being picked over a full
-- card just won, drawn with the page's settings.
function RollSample.New(parent)
    local Card, Stack = ns.RollCard, ns.RollStack
    local s = {}
    local f = CreateFrame("Frame", nil, parent)
    s.frame = f
    -- The cards keep their real size inside, scaled down as a whole to fit.
    local inner = CreateFrame("Frame", nil, f)
    inner:SetPoint("TOP", f, "TOP", 0, 0)
    local demo = RollSample.Demo(GetTime())
    local top = Card.New(inner)
    local bottom = Card.New(inner)
    top.sample, bottom.sample = true, true

    function s.Refresh(width, maxHeight)
        local set = Stack.Settings()
        local w = math.min(set.width or 300, width or 300)
        local copy = {}
        for k, v in pairs(set) do copy[k] = v end
        copy.width = w
        Card.Fill(top, demo[2], { mode = "compact", open = false, settings = copy })
        Card.Fill(bottom, demo[1], { mode = "full", open = true, settings = copy })
        local gap = set.spacing or 6
        local h, iw
        top:ClearAllPoints()
        bottom:ClearAllPoints()
        if width and width >= 2 * w + 24 then
            -- Room for both side by side: the one being picked on the left.
            iw, h = 2 * w + 24, math.max(top:GetHeight(), bottom:GetHeight())
            top:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
            bottom:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, 0)
        else
            iw, h = w, top:GetHeight() + gap + bottom:GetHeight()
            top:SetPoint("TOP", inner, "TOP", 0, 0)
            bottom:SetPoint("TOP", top, "BOTTOM", 0, -gap)
        end
        inner:SetSize(iw, h)
        local k = 1
        if maxHeight and maxHeight > 0 and h > maxHeight then k = maxHeight / h end
        inner:SetScale(k)
        f:SetSize(width or w, h * k)
        return h * k
    end

    function s.Parts()
        return {
            { region = top.buttonBox, label = L["Roll buttons"], keys = { "rolls.buttonSize", "rolls.buttonWords", "rolls.icons" } },
            { region = top.ticks, label = L["Pick ticks"], keys = { "rolls.ticks", "rolls.compact" } },
            { region = top.time, label = L["Seconds left"], keys = { "rolls.timerText" } },
            { region = bottom.list, label = L["Group list"], keys = { "rolls.list", "rolls.sort", "rolls.showPass", "rolls.rollBars" } },
            { region = bottom.line, label = L["Quality color line"], keys = { "rolls.qualityLine" } },
            { region = bottom.dup, label = L["Mark duplicate drops"], keys = { "rolls.twins" } },
        }
    end
    return s
end
