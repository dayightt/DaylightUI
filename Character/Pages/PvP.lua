-- The PvP page. In this client the rank is renown on
-- major faction 2800, with a weekly limit and a season end. In soft cards: your rank's
-- emblem, name and the next rank on the left; on the right this week against its limit,
-- the season, and your honorable kills (today, yesterday, in all).

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L
local Style = DUI.Style

local PvP = {}
ns.PvP = PvP

PvP.FACTION = 2800
-- Our own badges (Media/pvp-rank-NN.png), white so they take the accent: one to three chevrons,
-- a ring from the fourth rank, and a star more for each three after that.
PvP.EMBLEM = "pvp-rank-%02d.png"
-- The game's own art for the rank (atlases of its PvP tab): your faction's crest with no rank yet, and from
-- rank 1 that rank's own badge. They are used when the client has them, and our badges stand in when it
-- doesn't.
PvP.CRESTS = { Alliance = "UI-Character-Info-Honor-Icon-Alliance", Horde = "UI-Character-Info-Honor-Icon-Horde" }
PvP.BADGE = "UI-Character-Info-Honor-Icon-%d"
PvP.LAST_BADGE = 14
PvP.REWARD_ICON = 40               -- the next reward's icon
PvP.REWARD_H = PvP.REWARD_ICON + 4  -- its row; the room is kept even with no reward, so the card doesn't jump
PvP.REWARD_GAP = 16
PvP.EMBLEM_SIZE = 112
PvP.LEFT_W = 300
PvP.CARD = ns.List.INSET           -- a card's fill: the dark inset of the stats pane and the other pages' side panes
PvP.PAD = 14                    -- the same room on all four sides of a card
PvP.GAP = 12                    -- between cards
PvP.RANK_SIZE, PvP.MAIN_SIZE, PvP.LABEL_SIZE = 20, Style.SIZE.head, Style.SIZE.small
PvP.DAY, PvP.HOUR = 86400, 3600
PvP.ROW = 24                    -- a line of the honor card
-- A block's height, from its texts' (so a larger text scale keeps it): label, name, bar, line.
local function line(size) return math.ceil(size * 1.3) end
PvP.BLOCK_H = line(PvP.LABEL_SIZE) + 8 + line(PvP.MAIN_SIZE) + 10 + (ns.List.BAR_H + 2) + 6 + line(ns.List.SMALL)
PvP.HONOR_H = line(PvP.LABEL_SIZE) + 10 + line(PvP.LABEL_SIZE) + 4 + 2 * PvP.ROW
local isSecret = DUI.IsSecret
local function plain(v) return type(v) == "number" and not isSecret(v) end

-- The game's atlas for your rank (the faction crest at rank 0, that rank's badge after), and its
-- aspect ratio, or nil if the client has none.
local function crest(rank)
    local atlas
    if rank > 0 then
        atlas = string.format(PvP.BADGE, rank)
    else
        local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player")
        atlas = type(faction) == "string" and not isSecret(faction) and PvP.CRESTS[faction]
    end
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if type(info) ~= "table" or not plain(info.width) or not plain(info.height) or info.height <= 0 then return nil end
    return atlas, info.width / info.height
end

local function rankText(rank)
    if type(GetPVPRankText) == "function" then
        local ok, s = pcall(GetPVPRankText, rank)
        if ok and type(s) == "string" then return s end
    end
    return string.format(L["Rank %d"], rank)
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
    -- Honorable and dishonorable kills today and yesterday, and in all (nil where the client has none).
    local function kills(fn)
        if type(fn) ~= "function" then return nil end
        local ok2, a, b = pcall(fn)
        if ok2 and plain(a) then return { a, plain(b) and b or nil } end
        return nil
    end
    d.today, d.yesterday = kills(GetPVPSessionStats), kills(GetPVPYesterdayStats)
    d.lifetime = kills(GetPVPLifetimeStats)
    if d.lifetime then d.lifetime[2] = nil end   -- its second number is your highest rank, not kills
    d.reward = PvP.NextReward(d.rank, d.max)
    d.season = type(GetCurrentArenaSeason) == "function" and GetCurrentArenaSeason() or 0
    local ends = C_SeasonInfo and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd
    d.ends = type(ends) == "function" and ends() or 0
    return d
end

-- The next reward the ranks hold: the first rank above yours that has one. The client gives each
-- reward its name and icon (the faction tabard is the first). nil when there is none, or the
-- client can't say.
function PvP.NextReward(rank, max)
    local C = C_MajorFactions
    if type(C) ~= "table" or type(C.GetRenownRewardsForLevel) ~= "function" then return nil end
    for level = rank + 1, math.min(max, rank + 40) do
        local ok, list = pcall(C.GetRenownRewardsForLevel, PvP.FACTION, level)
        local r = ok and type(list) == "table" and list[1]
        if type(r) == "table" then
            for _, o in ipairs(list) do if type(o.uiOrder) == "number" and type(r.uiOrder) == "number" and o.uiOrder < r.uiOrder then r = o end end
            -- The game's tab lists a reward by its description, which is there at once. The reward's own
            -- name is a general one ("Rank 1 rewards"), so the item's name stands in for a reward with no
            -- description, and an item the client hasn't loaded yet is asked for.
            local name, icon, quality = r.name, r.icon, nil
            if plain(r.itemID) then
                local item, _, q = nil, nil, nil
                if type(GetItemInfo) == "function" then item, _, q = GetItemInfo(r.itemID) end
                if plain(q) then quality = q end
                if type(item) == "string" and not isSecret(item) and item ~= "" then name = item
                elseif C_Item and C_Item.RequestLoadItemDataByID then DUI.SafeCall(C_Item.RequestLoadItemDataByID, r.itemID) end
            end
            local words = r.description
            if type(words) == "string" and not isSecret(words) and words ~= "" then name = words end
            if type(icon) ~= "number" and plain(r.itemID) and type(GetItemIcon) == "function" then icon = GetItemIcon(r.itemID) end
            if type(name) == "string" and not isSecret(name) and name ~= "" then
                return { rank = level, name = name, quality = quality, icon = type(icon) == "number" and not isSecret(icon) and icon or nil,
                         itemID = plain(r.itemID) and r.itemID or nil,
                         text = type(r.description) == "string" and not isSecret(r.description) and r.description or nil }
            end
        end
    end
    return nil
end

function PvP.Ends(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    local days = math.floor(seconds / PvP.DAY)
    if days >= 1 then return string.format(days == 1 and L["Ends in %d day"] or L["Ends in %d days"], days) end
    local hours = math.floor(seconds / PvP.HOUR)
    if hours >= 1 then return string.format(hours == 1 and L["Ends in %d hour"] or L["Ends in %d hours"], hours) end
    return L["Ends within the hour"]
end
-- Seconds until PvP.Ends would say something else (the next whole day or hour,
-- or the season's end), nil with no end known.
function PvP.NextChange(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    local step = seconds >= PvP.DAY and PvP.DAY or seconds >= PvP.HOUR and PvP.HOUR or nil
    if not step then return seconds + 1 end
    return seconds % step + 1
end

-- While the page is open, one timer to the moment the countdown's words change,
-- so it moves on as the game's ticking one does, and a new season shows when it
-- starts. Nothing runs between those moments.
function PvP.Watch(page, seconds)
    page.watch = (page.watch or 0) + 1
    local wait = PvP.NextChange(seconds)
    if not wait then return end
    local mine = page.watch
    C_Timer.After(wait, function()
        if page.watch ~= mine or not page:IsShown() then return end
        if ns.window and ns.window.current == "pvp" then ns.Window.Refresh() end
    end)
end

-- Where the rank rewards are sold, in the game's words for your faction.
function PvP.Vendor()
    local horde = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") == "Horde"
    local text = horde and _G.PVP_RANK_REWARDS_VENDOR_HORDE or _G.PVP_RANK_REWARDS_VENDOR_ALLIANCE
    return type(text) == "string" and text or nil
end

-- A number in a sentence, in the accent (read now: follows an accent switch).
function PvP.Pop(s) return DUI.Win.Parts.Hex({ Style.Pop() }) .. s .. "|r" end

local function block(page, i, parent)
    local b = CreateFrame("Frame", nil, parent)
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

-- A soft card: a faint fill.
local function card(page)
    local c = CreateFrame("Frame", nil, page)
    c.fill = c:CreateTexture(nil, "BACKGROUND")
    c.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    c.fill:SetAllPoints()
    c.fill:SetVertexColor(PvP.CARD[1], PvP.CARD[2], PvP.CARD[3], PvP.CARD[4])
    return c
end

-- The honor card: Today, Yesterday and in all, honorable and dishonorable kills.
local function honor(c)
    local h = { cols = {}, rows = {} }
    h.label = Style.Text(c, PvP.LABEL_SIZE, "LEFT")
    h.label:SetText(L["HONOR"])
    for i, word in ipairs({ L["Today"], L["Yesterday"], L["Lifetime"] }) do
        local t = Style.Text(c, PvP.LABEL_SIZE, "RIGHT")
        t:SetText(word)
        Style.InkText(t, "LABEL")
        h.cols[i] = t
    end
    for r, word in ipairs({ L["Honorable kills"], L["Dishonorable kills"] }) do
        local name = Style.Text(c, ns.List.TEXT, "LEFT")
        name:SetText(word)
        Style.InkText(name, "TEXT")
        local cells = {}
        for i = 1, 3 do cells[i] = Style.Text(c, ns.List.TEXT, "RIGHT") end
        h.rows[r] = { name = name, cells = cells }
    end
    return h
end

function PvP.Build(page)
    page.cards = { rank = card(page), week = card(page), season = card(page), honor = card(page) }
    local R = page.cards.rank
    page.emblem = R:CreateTexture(nil, "ARTWORK")
    page.emblem:SetSize(PvP.EMBLEM_SIZE, PvP.EMBLEM_SIZE)
    page.rankName = Style.Text(R, PvP.RANK_SIZE, "CENTER")
    page.rankSub = Style.Text(R, ns.List.TEXT, "CENTER")
    local W = CreateFrame("Button", nil, R)
    page.reward = W
    DUI.Win.Parts.ItemIcon(W, PvP.REWARD_ICON)   -- the same edge and crop as the windows' other item icons
    W.edge:SetPoint("LEFT", W, "LEFT", 0, 0)
    W.label = Style.Text(W, PvP.LABEL_SIZE, "LEFT")
    W.label:SetText(L["NEXT REWARD"])
    W.name = Style.Text(W, ns.List.TEXT, "LEFT")
    W.sub = Style.Text(W, ns.List.SMALL, "LEFT")
    W.label:SetPoint("TOPLEFT", W.edge, "TOPRIGHT", 10, 2)
    W.name:SetPoint("LEFT", W.edge, "RIGHT", 10, 0)
    W.sub:SetPoint("BOTTOMLEFT", W.edge, "BOTTOMRIGHT", 10, -2)
    W.name:SetPoint("RIGHT", W, "RIGHT", 0, 0)
    W:SetScript("OnEnter", DUI.Win.Parts.ItemTip(function(self)
        local r = self.data
        if not r or type(GameTooltip) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local Tips = DUI.Tips
        Tips.Clear()
        if r.itemID and type(GameTooltip.SetItemByID) == "function" then GameTooltip:SetItemByID(r.itemID)
        else
            Tips.Title(r.name)
            if r.text and r.text ~= r.name then Tips.Text(r.text) end
        end
        -- The game's PvP page says where the rewards are sold.
        local vendor = PvP.Vendor()
        if vendor then Tips.Text(vendor, Tips.LABEL) end
        Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end))
    W:SetScript("OnLeave", function(self)
        self.UpdateTooltip = nil
        if type(GameTooltip) == "table" then GameTooltip:Hide() end
    end)
    page.blocks = {}
    block(page, 1, R).label:SetText(L["NEXT RANK"])
    block(page, 2, page.cards.week).label:SetText(L["THIS WEEK"])
    block(page, 3, page.cards.season).label:SetText(L["SEASON"])
    page.honor = honor(page.cards.honor)
end

function PvP.Place(page)
    local E, W, P, G = ns.List.EDGE, ns.Window.Width(), PvP.PAD, PvP.GAP
    local C = page.cards
    local blockCard = PvP.BLOCK_H + 2 * P
    local honorCard = PvP.HONOR_H + 2 * P
    -- The cards reach the foot of the page: what the page has beyond what they need is shared
    -- by the three on the right, and their words sit in the middle of the room they get.
    local least = 2 * blockCard + honorCard + 2 * G
    local total = math.max(least, ns.List.Room())
    local extra = total - least
    local each = math.floor(extra / 3)
    local weekH, seasonH, honorH = blockCard + each, blockCard + each, honorCard + extra - 2 * each
    local x = E + PvP.LEFT_W + G
    local w = W - x - E
    local function put(c, cx, cy, cw, ch)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", page, "TOPLEFT", cx, -cy)
        c:SetSize(cw, ch)
    end
    local top = ns.List.TOP
    put(C.rank, E, top, PvP.LEFT_W, total)
    put(C.week, x, top, w, weekH)
    put(C.season, x, top + weekH + G, w, seasonH)
    put(C.honor, x, top + weekH + seasonH + 2 * G, w, honorH)
    -- Left: the emblem, the name and the rank in the middle of what is above the next rank, which
    -- is at the card's foot.
    local R = C.rank
    local blockTop = total - P - PvP.BLOCK_H
    local rewardTop = blockTop - PvP.REWARD_GAP - PvP.REWARD_H
    page.reward:ClearAllPoints()
    page.reward:SetPoint("TOPLEFT", R, "TOPLEFT", P, -rewardTop)
    page.reward:SetPoint("TOPRIGHT", R, "TOPRIGHT", -P, -rewardTop)
    page.reward:SetHeight(PvP.REWARD_H)
    local aboveTop = rewardTop - PvP.REWARD_GAP   -- the emblem and name are centered above the reward
    local group = PvP.EMBLEM_SIZE + 16 + line(PvP.RANK_SIZE) + 6 + line(ns.List.TEXT)
    page.emblem:ClearAllPoints()
    page.emblem:SetPoint("TOP", R, "TOP", 0, -(P + math.max(0, math.floor((aboveTop - 2 * P - group) / 2))))
    page.rankName:ClearAllPoints()
    page.rankName:SetPoint("TOP", page.emblem, "BOTTOM", 0, -16)
    page.rankSub:ClearAllPoints()
    page.rankSub:SetPoint("TOP", page.rankName, "BOTTOM", 0, -6)
    local function inCard(b, c, y)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", c, "TOPLEFT", P, -y)
        b:SetPoint("TOPRIGHT", c, "TOPRIGHT", -P, -y)
        b:SetHeight(PvP.BLOCK_H)
    end
    inCard(page.blocks[1], R, blockTop)   -- at the card's foot
    inCard(page.blocks[2], C.week, math.floor((weekH - PvP.BLOCK_H) / 2))
    inCard(page.blocks[3], C.season, math.floor((seasonH - PvP.BLOCK_H) / 2))
    -- The honor card: a title, the three columns, two lines.
    local h, inner = page.honor, w - 2 * P
    local nameW = math.floor(inner * 0.4)
    local colW = math.floor((inner - nameW) / 3)
    h.label:ClearAllPoints()
    local lift = math.floor((honorH - PvP.HONOR_H) / 2)   -- its lines in the middle of the card
    h.label:SetPoint("TOPLEFT", C.honor, "TOPLEFT", P, -lift)
    local headY = lift + line(PvP.LABEL_SIZE) + 10
    for i, t in ipairs(h.cols) do
        t:ClearAllPoints()
        t:SetWidth(colW - 6)
        t:SetPoint("TOPRIGHT", C.honor, "TOPLEFT", P + nameW + colW * i - 6, -headY)
    end
    for r, row in ipairs(h.rows) do
        local y = headY + line(PvP.LABEL_SIZE) + 4 + (r - 1) * PvP.ROW
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", C.honor, "TOPLEFT", P, -(y + 3))
        row.name:SetWidth(nameW)
        for i, cell in ipairs(row.cells) do
            cell:ClearAllPoints()
            cell:SetWidth(colW - 6)
            cell:SetPoint("TOPRIGHT", C.honor, "TOPLEFT", P + nameW + colW * i - 6, -(y + 3))
        end
    end
end

-- The honor card's numbers: a dash where the client has none (or in all for the dishonorable).
local function paintHonor(page, d)
    local h = page.honor
    local any = d.today or d.yesterday or d.lifetime
    page.cards.honor:SetShown(any ~= nil)
    local sets = { d.today, d.yesterday, d.lifetime }
    for r, row in ipairs(h.rows) do
        for i, cell in ipairs(row.cells) do
            local v = sets[i] and sets[i][r]
            cell:SetText(v and ns.List.Number(v) or "-")
            if v then Style.InkText(cell, "pop") else Style.InkText(cell, "OFF") end
        end
    end
    Style.InkText(h.label, "LABEL")
end

function PvP.Refresh(page)
    local d = PvP.Read()
    if not d then return end
    local key, rgb = ns.List.OwnBar()
    -- With no rank yet the first rank's badge stands there faint, so the card isn't just a word.
    page.emblem:Show()
    local atlas, ratio = crest(d.rank)
    if atlas then
        -- The game's crest, in its own colors (the accent doesn't tint it), faint with no rank yet.
        page.emblem:SetAtlas(atlas)
        page.emblem:SetSize(math.floor(PvP.EMBLEM_SIZE * ratio + 0.5), PvP.EMBLEM_SIZE)
        page.emblem:SetVertexColor(1, 1, 1)
        page.emblem:SetAlpha(d.rank > 0 and 1 or 0.35)
    else
        page.emblem:SetSize(PvP.EMBLEM_SIZE, PvP.EMBLEM_SIZE)
        page.emblem:SetTexture(DUI.MEDIA .. string.format(PvP.EMBLEM, math.min(math.max(d.rank, 1), PvP.LAST_BADGE)))
        if d.rank > 0 then
            page.emblem:SetVertexColor(Style.Accent())   -- read now: follows an accent switch
            page.emblem:SetAlpha(1)
        else
            page.emblem:SetVertexColor(1, 1, 1)
            page.emblem:SetAlpha(0.2)
        end
    end
    page.rankName:SetText(d.name)
    Style.InkText(page.rankName, "VALUE")
    Style.InkText(page.rankSub, "pop")   -- read at paint time: follows an accent change
    page.rankSub:SetText(d.rank > 0 and string.format(L["Rank %d"], d.rank) or "")
    local W, rw = page.reward, d.reward
    W.data = rw
    W:SetShown(rw ~= nil)
    if rw then
        local Parts = DUI.Win.Parts
        Parts.FitItemIcon(W)
        if rw.icon then Parts.SetItemIcon(W, rw.icon, rw.quality) end
        W.edge:SetShown(rw.icon ~= nil)
        W.well:SetShown(rw.icon ~= nil)
        W.icon:SetShown(rw.icon ~= nil)
        W.name:SetText(rw.name)
        Style.InkText(W.name, "VALUE")
        W.sub:SetText(string.format(L["At rank %d"], rw.rank))
        Style.InkText(W.sub, "LABEL")   -- tan, a sub line
    end
    Style.InkText(W.label, "LABEL")
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
    PvP.Watch(page, d.ends)
    -- A season ending within the day reads amber.
    Style.InkText(b3.sub, (d.ends > 0 and d.ends < PvP.DAY) and "WARN" or "VALUE")
    for _, b in ipairs(page.blocks) do Style.InkText(b.label, "LABEL") end   -- tan: the accent stays for numbers
    paintHonor(page, d)
end

-- Rank 0 too, as the game's own window (its PvP tab always shows).
PvP.Available = function() return PvP.Read() ~= nil end
-- Kills and honor each fire their own event; the rank's events only cover a new rank.
PvP.events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION", "PLAYER_PVP_KILLS_CHANGED",
    "PLAYER_PVP_RANK_CHANGED", "HONOR_XP_UPDATE", "CHAT_MSG_COMBAT_HONOR_GAIN" }

ns.Window.Register("pvp", PvP)
