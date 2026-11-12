-- The PvP page. In this client the rank is renown on
-- major faction 2800, with a weekly limit and a season end. Your
-- rank's emblem and name big on the left; three plain blocks on the right:
-- the next rank and how far, this week against its limit, the season.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L
local Style = DUI.Style

local PvP = {}
ns.PvP = PvP

PvP.FACTION = 2800
PvP.EMBLEM = "Interface\\PvPRankBadges\\PvPRank%02d"
PvP.EMBLEM_SIZE = 96
PvP.LEFT_W = 260
PvP.BLOCK_H = 96
PvP.RANK_SIZE, PvP.MAIN_SIZE, PvP.LABEL_SIZE = 20, Style.SIZE.head, Style.SIZE.small
PvP.DAY, PvP.HOUR = 86400, 3600

local function rankText(rank)
    if type(GetPVPRankText) == "function" then
        local ok, s = pcall(GetPVPRankText, rank)
        if ok and type(s) == "string" then return s end
    end
    return "Rank " .. rank
end

function PvP.Read()
    local C = C_MajorFactions
    if type(C) ~= "table" or type(C.GetMajorFactionProgressionInfo) ~= "function" then return nil end
    local ok, p = pcall(C.GetMajorFactionProgressionInfo, PvP.FACTION)
    if not ok or type(p) ~= "table" then return nil end
    local function total(level)
        local ok2, v = pcall(C.GetTotalReputationForRenownLevel, PvP.FACTION, level or 0)
        return ok2 and type(v) == "number" and v or 0
    end
    local d = { rank = p.renownLevel or 0, earned = p.renownReputationEarned or 0,
                threshold = p.renownLevelThreshold or 0, max = p.maxLevel or 0 }
    d.name = d.rank > 0 and rankText(d.rank) or (PVP_RANK_0_NAME or L["No rank yet"])
    d.nextName = d.rank < d.max and rankText(d.rank + 1) or nil
    d.weekLevel = p.currentWeekProgressiveMaxLevel or 0
    local prev, cap = total(p.previousWeekProgressiveMaxLevel), total(d.weekLevel)
    d.weekCap = math.max(0, cap - prev)
    d.weekValue = math.min(d.weekCap, math.max(0, total(d.rank) + d.earned - prev))
    d.season = type(GetCurrentArenaSeason) == "function" and GetCurrentArenaSeason() or 0
    local ends = C_SeasonInfo and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd
    d.ends = type(ends) == "function" and ends() or 0
    return d
end

function PvP.Ends(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    local days = math.floor(seconds / PvP.DAY)
    if days >= 1 then return string.format(days == 1 and L["Ends in %d day"] or L["Ends in %d days"], days) end
    local hours = math.floor(seconds / PvP.HOUR)
    if hours >= 1 then return string.format(hours == 1 and L["Ends in %d hour"] or L["Ends in %d hours"], hours) end
    return L["Ends within the hour"]
end
-- A number in a sentence, in the accent (read now: follows an accent switch).
function PvP.Pop(s) return DUI.Win.Parts.Hex({ Style.Pop() }) .. s .. "|r" end

local function block(page, i)
    local b = CreateFrame("Frame", nil, page)
    b.label = Style.Text(b, PvP.LABEL_SIZE, "LEFT")
    b.label:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.main = Style.Text(b, PvP.MAIN_SIZE, "LEFT")
    b.main:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -8)
    Style.InkText(b.main, "TEXT")
    b.bar = DUI.Widgets.Bar(b, ns.List.BAR_H + 2)
    b.bar:SetPoint("TOPLEFT", b.main, "BOTTOMLEFT", 0, -10)
    b.bar:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.sub = Style.Text(b, ns.List.SMALL, "LEFT")
    b.sub:SetPoint("TOPLEFT", b.bar, "BOTTOMLEFT", 0, -6)
    b.sub:SetTextColor(ns.List.DIM[1], ns.List.DIM[2], ns.List.DIM[3])
    page.blocks[i] = b
    return b
end

function PvP.Build(page)
    page.emblem = page:CreateTexture(nil, "ARTWORK")
    page.emblem:SetSize(PvP.EMBLEM_SIZE, PvP.EMBLEM_SIZE)
    page.rankName = Style.Text(page, PvP.RANK_SIZE, "CENTER")
    page.rankSub = Style.Text(page, ns.List.TEXT, "CENTER")
    page.blocks = {}
    for i, label in ipairs({ L["NEXT RANK"], L["THIS WEEK"], L["SEASON"] }) do block(page, i).label:SetText(label) end
end

function PvP.Place(page)
    local E, W = ns.List.EDGE, ns.Window.Width()
    page.emblem:ClearAllPoints()
    page.emblem:SetPoint("TOP", page, "TOPLEFT", E + PvP.LEFT_W / 2, -60)
    page.rankName:ClearAllPoints()
    page.rankName:SetPoint("TOP", page.emblem, "BOTTOM", 0, -16)
    page.rankSub:ClearAllPoints()
    page.rankSub:SetPoint("TOP", page.rankName, "BOTTOM", 0, -6)
    local x = E + PvP.LEFT_W + 2 * E
    for i, b in ipairs(page.blocks) do
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", page, "TOPLEFT", x, -ns.List.TOP - 24 - (i - 1) * (PvP.BLOCK_H + 24))
        b:SetSize(W - x - E, PvP.BLOCK_H)
    end
end

function PvP.Refresh(page)
    local d = PvP.Read()
    if not d then return end
    local key, rgb = ns.List.OwnBar()
    page.emblem:SetShown(d.rank > 0)
    if d.rank > 0 then page.emblem:SetTexture(string.format(PvP.EMBLEM, d.rank)) end
    page.rankName:SetText(d.name)
    Style.InkText(page.rankName, "VALUE")
    Style.InkText(page.rankSub, "pop")   -- read at paint time: follows an accent change
    page.rankSub:SetText(d.rank > 0 and ("Rank " .. d.rank) or "")
    local b1, b2, b3 = page.blocks[1], page.blocks[2], page.blocks[3]
    b1.main:SetText(d.nextName or L["The highest rank"])
    b1.bar:SetMinMaxValues(0, d.threshold > 0 and d.threshold or 1)
    Style.SetBarValue(b1.bar, d.threshold > 0 and d.earned or 1)   -- honor coming in glides
    ns.List.PaintBar(b1.bar, key, rgb)
    b1.sub:SetText(string.format(L["%s of %s points"], PvP.Pop(ns.List.Number(d.earned)), PvP.Pop(ns.List.Number(d.threshold))))
    b2.main:SetText(d.weekLevel > 0 and string.format(L["You can reach rank %d this week"], d.weekLevel) or L["No weekly limit"])
    b2.bar:SetShown(d.weekCap > 0)
    if d.weekCap > 0 then
        b2.bar:SetMinMaxValues(0, d.weekCap)
        Style.SetBarValue(b2.bar, d.weekValue)
        ns.List.PaintBar(b2.bar, key, rgb)
    end
    b2.sub:SetText(d.weekCap > 0 and string.format(L["%s of %s this week"], PvP.Pop(ns.List.Number(d.weekValue)), PvP.Pop(ns.List.Number(d.weekCap))) or "")
    b3.main:SetText(d.season > 0 and string.format(L["Season %s"], d.season) or L["No season right now"])
    b3.bar:Hide()
    b3.sub:SetText(PvP.Ends(d.ends) or "")
    -- A season ending within the day reads amber.
    Style.InkText(b3.sub, (d.ends > 0 and d.ends < PvP.DAY) and "WARN" or "VALUE")
    for _, b in ipairs(page.blocks) do Style.InkText(b.label, "pop") end
end

-- Rank 0 too, as the game's own window (its PvP tab always shows).
PvP.Available = function() return PvP.Read() ~= nil end
PvP.events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION" }

ns.Window.Register("pvp", PvP)
