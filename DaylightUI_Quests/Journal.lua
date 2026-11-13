-- Quest journal in the world map's quest log slot. The game's panel
-- (QuestMapFrame) keeps running underneath. The journal is a child of it, one
-- level up, so it shows, hides, moves and fades with it automatically. The game's
-- own pieces in the panel only go to alpha 0 (never Hide, a hook on its methods,
-- or a field written on it) and come back when the journal is switched off.
--
-- Layout: quests by zone, then a single quest opening as its own page, with Show
-- on map, Track, Share and Abandon along the bottom. It only acts through the
-- game's plain quest functions and the same map ping the tracker uses. A hovered
-- or opened quest's area lights up on the map through a separate blob frame
-- (Journal.Light), never through the map's code. The reverse works too: hovering a
-- quest on the map (the game's icon or Questie's) lights its row (Journal.MapHover).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Journal = {}
ns.Journal = Journal

Journal.LEVEL = 500        -- above the panel's own pieces (frameLevel 100 in its XML)
Journal.ZONE = 24
Journal.ROW_ROOM = 6       -- px padding around a row's text, regardless of `journalRowHeight`
Journal.ZONE_ROOM = 11     -- same for a zone line, whose text is 2 larger
Journal.LEVEL_W = 1.55     -- level column width in text sizes, fits two digits
Journal.OBJ = 22
Journal.TOP = 40           -- room for the search line on the list page
Journal.FOOT = 52          -- room for the footer on a quest page
Journal.WARN_Y = 16        -- px the item warning sits above the footer, clear of its rule
Journal.TIP_GAP = 8        -- px between the panel's edge and a row's tooltip beside it
Journal.PARTY_GAP = 6      -- px between a row's party mark and its progress
Journal.SPOT_DIM = 0.2     -- alpha of other quests' map icons while a quest name is hovered
Journal.SPOT_GROW = 1.35   -- scale of the hovered quest's map icons
Journal.WATCH_MAX = 25     -- fallback for the game's MAX_QUEST_WATCHES
Journal.WANT_WAIT = 2      -- seconds a tracker click waits for the log to show (the first map open is slow)
Journal.WHITE = "Interface\\Buttons\\WHITE8X8"
-- Readable at a glance on the dark panel (45% gray levels and zone names were too
-- faint).
Journal.DIM = Style.INK.LABEL     -- level and zone line, "nothing here", the search hint
Journal.FAINT = Style.INK.OFF     -- search box icon
Journal.VALUE = Style.INK.VALUE   -- counts and progress
Journal.LEVEL_TEXT = Style.INK.LABEL    -- level in front of each quest
Journal.ZONE_TEXT = Style.INK.TEXT     -- zone headers
Journal.TEXT = Style.INK.TEXT

local db, f, blob, ring
local data = { groups = {}, count = 0, max = 0 }
local S = { page = "list", quest = nil, query = "" }
local want, wantUntil      -- the quest a tracker click is opening the log to, and until when
local veiled = {}          -- game pieces set to alpha 0 -> their previous alpha
local mapHover = {}        -- questID -> true while hovered on the map

local function pick(ok, ...) if ok then return ... end end
local function call(fn, ...)
    if type(fn) == "function" then return pick(pcall(fn, ...)) end
end
local function api(t, name) return type(t) == "table" and t[name] or nil end
local function plain(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" end
local function sound(name) if DUI.Sound then DUI.Sound.Play(name) end end

local function tex(parent, layer, c)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(Journal.WHITE)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function refuse(text)
    DUI.ShowError(text)
end

local function look() return ns.Look.Get(db) end
local function Win() return DUI.Win end

-- The game's panel, if this client has it.
function Journal.Panel()
    local qm = _G.QuestMapFrame
    return type(qm) == "table" and type(qm.GetChildren) == "function" and qm or nil
end

-- Reading the log

local function watchedSet()
    local out = {}
    local n = call(api(C_QuestLog, "GetNumQuestWatches"))
    for i = 1, (type(n) == "number" and n or 0) do
        local id = call(api(C_QuestLog, "GetQuestIDForQuestWatchIndex"), i)
        if type(id) == "number" then out[id] = true end
    end
    return out, type(n) == "number" and n or 0
end

-- Every quest the game's log lists (no headers, tasks or hidden quests; bounties
-- only when done), by zone, current zone first.
function Journal.Read()
    local QL = C_QuestLog
    local watched, nWatched = watchedSet()
    local focus = call(api(C_SuperTrack, "GetSuperTrackedQuestID"))
    local out = { groups = {}, watched = nWatched }
    local byZone, zone = {}, nil
    local n = call(api(QL, "GetNumQuestLogEntries"))
    for i = 1, (type(n) == "number" and n or 0) do
        local info = call(api(QL, "GetInfo"), i)
        if type(info) == "table" then
            if info.isHeader then
                zone = type(info.title) == "string" and info.title or nil
            elseif type(info.questID) == "number" and not info.isTask and not info.isHidden then
                local name = zone or ns.Data.OTHER
                local q = ns.Data.Quest(info.questID, nil, name, i, info, focus)
                if q and not (info.isBounty and q.state ~= "ready") then
                    q.watched = watched[q.id] == true
                    local g = byZone[name]
                    if not g then
                        g = { name = name, quests = {} }
                        byZone[name] = g
                        out.groups[#out.groups + 1] = g
                    end
                    g.quests[#g.quests + 1] = q
                end
            end
        end
    end
    if db.journalHereFirst ~= false then
        local here = ns.Data.Here(function(name) return byZone[name] ~= nil end)
        for i, g in ipairs(out.groups) do
            if g.name == here and i > 1 then table.insert(out.groups, 1, table.remove(out.groups, i)); break end
        end
    end
    for _, g in ipairs(out.groups) do ns.Layout.Sort(g.quests, { sort = db.journalSort }) end
    local _, numQuests = call(api(QL, "GetNumQuestLogEntries"))
    out.count = type(numQuests) == "number" and numQuests or 0
    local most = call(api(QL, "GetMaxNumQuestsCanAccept"))
    out.max = type(most) == "number" and most or ns.Data.LOG_MAX
    return out
end

local function find(id)
    for _, g in ipairs(data.groups) do
        for _, q in ipairs(g.quests) do if q.id == id then return q end end
    end
end

-- A quest's progress in a few characters: Ready, Failed, 5/8, 40%.
function Journal.Progress(q)
    if q.state == "ready" then return L["Ready"] end
    if q.state == "failed" then return FAILED or L["Failed"] end
    local have, need, pct = 0, 0, nil
    for _, o in ipairs(q.objs or {}) do
        if o.kind == "count" then have, need = have + (o.have or 0), need + (o.need or 0)
        elseif o.kind == "bar" then pct = o.pct end
    end
    if need > 0 then return have .. "/" .. need end
    if pct then return pct .. "%" end
    return ""
end

-- Folds (per character, like the tracker's)

local function folds()
    local c = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if type(c) ~= "table" then return {} end
    if type(c.journalFolds) ~= "table" then c.journalFolds = {} end
    return c.journalFolds
end

function Journal.ToggleFold(name)
    local t = folds()
    t[name] = not t[name] or nil
    sound("toggle")
    Journal.FillList(false)
end

-- List page pieces

local function makeZone(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.chevron = b:CreateTexture(nil, "ARTWORK")
    b.chevron:SetTexture(ns.Look.CHEVRON)
    b.chevron:SetSize(10, 10)
    b.chevron:SetPoint("LEFT", b, "LEFT", 2, -2)
    b.text = Style.Text(b, Style.SIZE.head, "LEFT")
    b.text:SetPoint("LEFT", b.chevron, "RIGHT", 6, 0)
    b.count = Style.Text(b, Style.SIZE.tiny, "RIGHT")
    b.count:SetPoint("RIGHT", b, "RIGHT", -4, -2)
    b.line = tex(b, "ARTWORK", { 1, 1, 1, 0.06 })
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local function paint(over)
        local c = over and Style.INK.VALUE or Journal.ZONE_TEXT
        b.text:SetTextColor(c[1], c[2], c[3])
        b.chevron:SetVertexColor(c[1], c[2], c[3], 1)
    end
    b.Paint = paint
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", function(self, button)
        if not self.zone then return end
        if button == "RightButton" then return Journal.ZoneMenu(self.zone, self) end
        Journal.ToggleFold(self.zone)
    end)
    return b
end

-- A hovered quest name grows its map icons a little and fades the other quests'
-- (`journalHoverIcons`); nil restores them. The icons are Questie's, so without it
-- the map has nothing to change.
function Journal.Spot(id)
    Journal.spot = id and db and db.journalHoverIcons ~= false and id or nil
    ns.Bridge.FocusIcons(Journal.spot, Journal.SPOT_DIM, Journal.SPOT_GROW)
end

-- One of Questie's icons hovered on the world map or minimap: its quest gets the
-- same highlight, and its row lights up if the log is open.
function Journal.IconHover(id)
    Journal.MapHover(id and { id } or nil)
    Journal.Spot(id)
end

-- A quest row's tooltip: the tracker's (objectives, rewards) with the journal's
-- clicks. With `journalTipBeside` on it's placed like the game's log does
-- (QuestMapLogTitleButton_OnEnter): right of the panel level with the row, or left
-- of it over the map when there's no room on the right (at the mouse it covered
-- the list). Off: at the mouse.
function Journal.Tip(b)
    if not (GameTooltip and ns.Clicks) then return end
    local GT = GameTooltip
    local beside = f and db and db.journalTipBeside ~= false
    GT:SetOwner(b, beside and "ANCHOR_NONE" or "ANCHOR_CURSOR")
    ns.Clicks.QuestTip(b.quest, ns.Clicks.JOURNAL_HINTS)
    GT:Show()
    if not beside then return end
    GT:ClearAllPoints()
    -- Measured in screen space: the log rides on the map (its own scale, MapMove),
    -- the tooltip has another (the Tooltip module's size), and its offsets are in
    -- its own scale.
    local fs, ts = f:GetEffectiveScale() or 1, GT:GetEffectiveScale() or 1
    local room = (UIParent:GetRight() or 0) * (UIParent:GetEffectiveScale() or 1) - (f:GetRight() or 0) * fs
    if ((GT:GetWidth() or 0) + Journal.TIP_GAP) * ts <= room then
        GT:SetPoint("TOPLEFT", b, "TOPRIGHT", ((f:GetRight() or 0) - (b:GetRight() or 0)) * fs / ts + Journal.TIP_GAP, 0)
    else
        GT:SetPoint("TOPRIGHT", b, "TOPLEFT", ((f:GetLeft() or 0) - (b:GetLeft() or 0)) * fs / ts - Journal.TIP_GAP, 0)
    end
end

-- Left end of the title: after the level, or where the level would start with
-- levels off. `y` = the row's pressed offset.
local function placeTitle(b, y)
    if b.leveled then b.title:SetPoint("LEFT", b.level, "RIGHT", 8, y)
    else b.title:SetPoint("LEFT", b, "LEFT", b.textX, y) end
end

-- A row's text size and contents, from the Map page's settings.
local function fitQuest(b)
    local size = db.journalTextSize
    if b.fitted ~= size then
        b.fitted = size
        Style.SetTextSize(b.title, size)
        Style.SetTextSize(b.level, size - 1)
        Style.SetTextSize(b.prog, size - 1)
        b.level:SetWidth(math.ceil(size * Journal.LEVEL_W))
    end
    local dots = db.journalDots ~= false
    b.leveled = db.journalLevels ~= false
    b.textX = dots and 14 or 6
    b.level:SetPoint("LEFT", b, "LEFT", dots and 10 or 0, 0)
    b.level:SetShown(b.leveled)
    placeTitle(b, 0)
end

local function makeQuest(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hi = tex(b, "BACKGROUND", DUI.Win.Parts.HI)   -- the shared list row hover
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.dot = tex(b, "ARTWORK")
    b.dot:SetSize(5, 5)
    b.dot:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.level = Style.Text(b, Style.SIZE.small, "RIGHT")
    b.level:SetWidth(20)
    b.level:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.level:SetTextColor(Journal.LEVEL_TEXT[1], Journal.LEVEL_TEXT[2], Journal.LEVEL_TEXT[3])
    b.prog = Style.Text(b, Style.SIZE.small, "RIGHT")
    b.prog:SetPoint("RIGHT", b, "RIGHT", -6, 0)
    b.title = Style.Text(b, Style.SIZE.body, "LEFT")
    b.title:SetPoint("RIGHT", b.prog, "LEFT", -8, 0)
    b.title:SetWordWrap(false)
    b.tag = ns.Look.NewTag(b)
    b.party = ns.Look.NewParty(b)
    b.party:SetPoint("RIGHT", b.prog, "LEFT", -Journal.PARTY_GAP, 0)
    b:SetScript("OnEnter", function(self)
        Win().Parts.Light(self.hi, true)
        if self.quest then
            Journal.Spot(self.quest.id)
            Journal.Light(self.quest.id)
            Journal.Tip(self)
        end
    end)
    b:SetScript("OnLeave", function(self)
        Win().Parts.Light(self.hi, self.quest ~= nil and mapHover[self.quest.id] == true)
        Journal.Spot(nil)
        Journal.Light(S.page == "quest" and S.quest or nil)
        if GameTooltip then GameTooltip:Hide() end
    end)
    b:SetScript("OnMouseDown", function(self) placeTitle(self, -1) end)
    b:SetScript("OnMouseUp", function(self) placeTitle(self, 0) end)
    b:SetScript("OnClick", function(self, button)
        if not self.quest then return end
        if button == "RightButton" then return Journal.Menu(self.quest, self) end
        -- Shift-click links it into an open chat box, like the game's log.
        if IsModifiedClick and IsModifiedClick("CHATLINK") and ns.Clicks.LinkQuest(self.quest.id) then return end
        sound("click")
        -- No chat box open: Shift-click tracks or untracks it, like the game's log.
        if IsShiftKeyDown and IsShiftKeyDown() then return Journal.Track(self.quest) end
        Journal.ShowQuest(self.quest.id)
    end)
    return b
end

local function paintQuest(b, q)
    local lk = look()
    local sameQuest = b.quest ~= nil and b.quest.id == q.id   -- the party mark only eases on its own row
    b.quest = q
    fitQuest(b)
    b.title:SetText(q.title)
    -- A ready quest keeps its level color while "Ready" at the end says so. With
    -- progress hidden, the title color has to say it.
    local byLevel = q.state == "ready" and db.journalProgress ~= false
    b.title:SetTextColor((byLevel and ns.Look.LevelColor or ns.Look.TitleColor)(lk, q))
    -- the quest's tag right after its title, which makes room for it
    local tagged = ns.Look.PaintTag(b.tag, lk, db.questTags and q.tag or nil)
    local room = tagged and (b.tag:GetWidth() + ns.Look.TAG_GAP) or 0
    if ns.Look.PaintParty(b.party, db.questParty and q.party or nil, sameQuest) then
        room = room + ns.Layout.PARTY_W + Journal.PARTY_GAP
    end
    b.title:SetPoint("RIGHT", b.prog, "LEFT", -8 - room, 0)
    if tagged then
        local sw = ns.Look.Number(b.title:GetStringWidth()) or 0
        local w = ns.Look.Number(b.title:GetWidth())
        if w and w > 0 then sw = math.min(sw, w) end
        b.tag:ClearAllPoints()
        b.tag:SetPoint("LEFT", b.title, "LEFT", sw + ns.Look.TAG_GAP, 0)
    end
    b.level:SetText(type(q.level) == "number" and q.level > 0 and tostring(q.level) or "")
    b.prog:SetText(db.journalProgress ~= false and Journal.Progress(q) or "")
    if q.state == "ready" or q.state == "failed" then b.prog:SetTextColor(ns.Look.TitleColor(lk, q))
    else Style.InkText(b.prog, "pop") end   -- progress uses the accent
    local dot = q.watched == true and db.journalDots ~= false
    b.dot:SetShown(dot)
    if dot then Style.PaintAccent(b.dot, 1) end
    Win().Parts.Light(b.hi, b:IsMouseOver() == true or mapHover[q.id] == true, true)
end

-- A quest hovered on the map (the game's quest icon; a list of ids, nil = none):
-- its row lights as if hovered, scrolling into view if it's off the edge. List
-- page only.
function Journal.MapHover(ids)
    local was = mapHover
    mapHover = {}
    for _, id in ipairs(ids or {}) do if type(id) == "number" then mapHover[id] = true end end
    if not (f and f:IsVisible() and S.page == "list") then return end
    local first
    for _, b in ipairs(f.list.stack.pieces) do
        local id = b.quest and b.quest.id
        if id and b.hi and (mapHover[id] or was[id]) then
            Win().Parts.Light(b.hi, mapHover[id] == true or b:IsMouseOver() == true)
            if mapHover[id] and not first then first = b end
        end
    end
    if first then f.list.stack:Reveal(first) end
end

local function matches(q)
    if S.query == "" then return true end
    return string.find(string.lower(q.title or ""), string.lower(S.query), 1, true) ~= nil
end

function Journal.FillList(lift)
    if not f then return end
    local s = f.list.stack
    local keep = s:Scrolled()
    local t = folds()
    s:Begin()
    local shown = 0
    local size = db.journalTextSize
    local rowH = math.max(db.journalRowHeight, size + Journal.ROW_ROOM)
    local zoneH = math.max(Journal.ZONE, size + Journal.ZONE_ROOM)
    for _, g in ipairs(data.groups) do
        local list = {}
        for _, q in ipairs(g.quests) do if matches(q) then list[#list + 1] = q end end
        if #list > 0 then
            -- A search shows every match, including in folded zones.
            local folded = S.query == "" and t[g.name] == true
            local z = s:Piece("zone", makeZone, zoneH, 8)
            z.zone = g.name
            if z.fitted ~= size then
                z.fitted = size
                Style.SetTextSize(z.text, size + 2)
            end
            z.text:SetText(db.journalZoneCaps ~= false and string.upper(g.name) or g.name)
            z.count:SetText(folded and tostring(#list) or "")
            z.count:SetTextColor(Journal.VALUE[1], Journal.VALUE[2], Journal.VALUE[3])
            z.chevron:SetRotation(folded and math.pi / 2 or 0)
            z.Paint(z:IsMouseOver() == true)
            if not folded then
                for _, q in ipairs(list) do
                    paintQuest(s:Piece("quest", makeQuest, rowH, 0), q)
                    shown = shown + 1
                end
            end
        end
    end
    if #s.pieces == 0 then
        s:Text(S.query ~= "" and L["No quests match."] or L["No quests yet."], { size = Style.SIZE.body, color = Journal.DIM })
    end
    s:End()
    s:ScrollTo(keep)
    if Journal.spot then Journal.Spot(Journal.spot) end   -- Questie may have drawn new icons
    local over = data.count > data.max
    f.list.count:SetText(data.count .. "/" .. data.max)
    local c = over and Style.INK.BAD or Journal.VALUE
    f.list.count:SetTextColor(c[1], c[2], c[3])
    if lift then Win().Feel.Stagger(s.pieces, 0) end
end

-- Quest page

local function makeBack(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")
    b.text = Style.Text(b, Style.SIZE.small, "LEFT")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetText("\226\128\185  " .. L["All quests"])
    local function paint(over)
        Style.InkText(b.text, over and "VALUE" or "pop")   -- the accent, read at paint time
    end
    b.Paint = paint
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    b:SetScript("OnClick", function() sound("click"); Journal.ShowList() end)
    return b
end

local function makeObj(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.count = Style.Text(b, Style.SIZE.small, "RIGHT")
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.text = Style.Text(b, Style.SIZE.body, "LEFT")
    b.text:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.text:SetPoint("RIGHT", b.count, "LEFT", -8, 0)
    b.text:SetWordWrap(false)
    b.bar = DUI.Widgets.Bar(b)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 1)
    b.bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 1)
    return b
end

local function paintObj(b, o, lk)
    b.text:SetText(o.text or "")
    local done = o.done == true
    local c = done and Style.INK.GOOD or Journal.TEXT
    b.text:SetTextColor(c[1], c[2], c[3])
    local frac
    if o.kind == "count" and (o.need or 0) > 0 then
        b.count:SetText(o.have .. "/" .. o.need)
        frac = math.min(1, (o.have or 0) / o.need)
    elseif o.kind == "bar" then
        b.count:SetText(o.pct .. "%")
        frac = math.min(1, (o.pct or 0) / 100)
    else
        b.count:SetText("")
    end
    local cc = done and Style.INK.GOOD or { Style.Pop() }   -- a count in progress uses the accent
    b.count:SetTextColor(cc[1], cc[2], cc[3])
    local bar = frac ~= nil
    b.bar:SetShown(bar)
    if bar then
        b.bar:SetValue(frac)
        if done or frac >= 1 then DUI.Widgets.BarFrom(b.bar, ns.Look.Color(lk, "ready")) else DUI.Widgets.BarAccent(b.bar, 0.9) end
    end
end

-- A reward's item link for modified clicks (Shift links, Ctrl tries on). The
-- game's own call (QuestInfoRewardItemMixin:OnClick) only takes type and index and
-- answers for the log's selected quest, which the journal never sets (that would
-- write the map's state tainted). So it's only correct for that quest; otherwise
-- the link is built from the item.
local function rewardLink(q, kind, i, itemID)
    if call(api(C_QuestLog, "GetSelectedQuest")) == q.id then
        local link = call(GetQuestLogItemLink, kind, i)
        if plain(link) then return link end
    end
    if type(itemID) ~= "number" then return nil end
    local _, link = call(api(C_Item, "GetItemInfo"), itemID)
    return plain(link) and link or nil
end

-- Rewards as tiles: what it gives, then what you choose from.
local function rewardTiles(q, kind)
    local count = kind == "choice" and call(GetNumQuestLogChoices, q.id) or call(GetNumQuestLogRewards, q.id)
    local read = kind == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
    local tiles = {}
    for i = 1, (type(count) == "number" and count or 0) do
        local name, texture, qty, quality, _, itemID = call(read, i, q.id)
        if plain(name) then
            tiles[#tiles + 1] = {
                name = name, texture = texture, count = qty, quality = quality,
                link = function() return rewardLink(q, kind, i, itemID) end,
                tooltip = function(b)
                    if not (GameTooltip and GameTooltip.SetQuestLogItem) then return end
                    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                    pcall(GameTooltip.SetQuestLogItem, GameTooltip, kind, i, q.id)
                    GameTooltip:Show()
                end,
            }
        end
    end
    return tiles
end

-- A quest page's tag (Look.NewTag), under its title.
local function makeTag(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.tag = ns.Look.NewTag(b)
    b.tag:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    return b
end

-- A timed quest's time left, counting down while its page shows.
local function makeTime(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.label = Style.Text(b, Style.SIZE.body, "LEFT")
    b.label:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    return b
end

function Journal.TickTime()
    local b = Journal.time
    if b and b:IsVisible() then
        return ns.Rows.PaintTimer(b, math.max(0, b.ends - GetTime()), look())
    end
    if Journal.timeTicker then Journal.timeTicker:Cancel() end
    Journal.timeTicker = nil
end

local function paintTime(s, q, lk)
    local left = ns.Data.TimeLeft(q.id, ns.Data.Timers())
    Journal.time = nil
    if not left or q.state == "failed" then return end
    local b = s:Piece("time", makeTime, Journal.OBJ, 4)
    b.ends = GetTime() + left
    ns.Rows.PaintTimer(b, left, lk)
    Journal.time = b
    if not Journal.timeTicker then
        Journal.timeTicker = C_Timer.NewTicker(1, function() DUI.SafeCall(Journal.TickTime) end)
    end
end

function Journal.FillQuest(lift)
    local q = S.quest and find(S.quest)
    if not (f and q) then return Journal.ShowList() end
    local page = f.quest
    local s = page.stack
    local lk = look()
    local keep = lift and 0 or s:Scrolled()
    s:Begin()
    s:Piece("back", makeBack, 20, 0).Paint(false)
    s:Text(q.title, { size = Style.SIZE.head, color = { ns.Look.TitleColor(lk, q) }, gap = 6 })
    local tagged = db.questTags and q.tag
    if tagged then ns.Look.PaintTag(s:Piece("tag", makeTag, ns.Look.TAG_H, 4).tag, lk, q.tag) end
    s:Text(ns.Look.LevelLine(q), { size = Style.SIZE.small, color = Journal.DIM, gap = tagged and 5 or 2 })
    local story, steps = call(GetQuestLogQuestText, q.logIndex)
    if plain(story) then s:Text(story, { size = Style.SIZE.body, gap = 10 }) end
    if q.state == "ready" then
        s:Section(ns.Data.READY)
        if plain(q.turnIn) then s:Text(q.turnIn, { size = Style.SIZE.body }) end
    elseif #q.objs > 0 then
        s:Section(L["Objectives"])
        for _, o in ipairs(q.objs) do
            paintObj(s:Piece("obj", makeObj, Journal.OBJ, 4), o, lk)
        end
    elseif plain(steps) then
        s:Section(L["Objectives"])
        s:Text(steps, { size = Style.SIZE.body })
    end
    paintTime(s, q, lk)
    local money = call(GetQuestLogRewardMoney, q.id)
    local xp = call(GetQuestLogRewardXP, q.id)
    local given, choices = rewardTiles(q, "reward"), rewardTiles(q, "choice")
    if (type(money) == "number" and money > 0) or (type(xp) == "number" and xp > 0) or #given > 0 or #choices > 0 then
        s:Section(L["Rewards"])
        s:Money(money, xp)
        if #given > 0 then s:Items(given) end
        if #choices > 0 then
            s:Text(L["You choose one of these:"], { size = Style.SIZE.small, color = Journal.DIM, gap = 10 })
            s:Items(choices)
        end
    end
    s:End()
    s:ScrollTo(keep)
    Journal.PaintFooter(q)
    if lift then Win().Feel.Stagger(s.pieces, 0) end
end

-- Footer actions

-- Never in combat: the game blocks QuestLogPushQuest from addons there ("the game
-- blocked QuestLogPushQuest()").
function Journal.CanShare(q)
    return not InCombatLockdown() and IsInGroup and IsInGroup()
        and call(api(C_QuestLog, "IsPushableQuest"), q.id) == true
end

function Journal.CanAbandon(q)
    local fn = api(C_QuestLog, "CanAbandonQuest")
    if type(fn) ~= "function" then return true end
    return call(fn, q.id) == true
end

-- Out of combat the map turns to the quest's zone (same as the tracker). In combat
-- addon code can't change the map, so just the ping.
function Journal.Map(q)
    if InCombatLockdown() then
        if EventRegistry and EventRegistry.TriggerEvent then EventRegistry:TriggerEvent("MapCanvas.PingQuestID", q.id) end
        return
    end
    ns.Clicks.OpenMap(q.id)
    Journal.LightAgain(q.id)
end

-- The map may be on another zone now, so redraw the area there.
function Journal.LightAgain(id)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() if S.page == "quest" and S.quest == id then Journal.Light(id) end end)
    end
end

-- The quest's area on the map. The game's own log highlights it by calling the
-- map's code (WorldMapFrame:SetHighlightedQuestID), which from addon code would
-- leave the map's state tainted. So it's drawn here instead: a separate blob frame
-- (the client's QuestPOIFrame, the same kind as the game's quest blob pin) laid
-- over the map's canvas at the game's blob level. The map's canvas, level table
-- and map id are only read.

Journal.BLOB_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
Journal.BLOB_BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"
Journal.BLOB_LEVEL = 2007   -- the game's PIN_FRAME_LEVEL_QUEST_BLOB, if its table can't be read

local function canvas()
    local map = _G.WorldMapFrame
    local sc = type(map) == "table" and map.ScrollContainer
    local child = type(sc) == "table" and sc.Child
    if type(child) ~= "table" then return nil end
    return child, map
end

local function blobLevel(map)
    local m = map.pinFrameLevelsManager
    local d = type(m) == "table" and type(m.definitions) == "table" and m.definitions.PIN_FRAME_LEVEL_QUEST_BLOB
    -- (On OpenMap's stitched map, above its art.)
    return DUI.OpenMap.Level(type(d) == "table" and type(d.startLevel) == "number" and d.startLevel or Journal.BLOB_LEVEL, 2)
end

-- The game's rule (MapUtil.ShouldMapTypeShowQuests): no blobs on the world,
-- continent or cosmic map.
function Journal.MapShowsQuests(mapID)
    local info = call(api(C_Map, "GetMapInfo"), mapID)
    local kind = type(info) == "table" and info.mapType
    local kinds = type(Enum) == "table" and Enum.UIMapType
    if type(kind) ~= "number" or type(kinds) ~= "table" then return false end
    return kind ~= kinds.World and kind ~= kinds.Continent and kind ~= kinds.Cosmic
end

local function makeBlob(child)
    local ok, b = pcall(CreateFrame, "QuestPOIFrame", nil, child)
    if not ok or type(b) ~= "table" then return nil end
    b:SetAllPoints(child)
    b:EnableMouse(false)
    pcall(b.SetFillTexture, b, Journal.BLOB_FILL)
    pcall(b.SetBorderTexture, b, Journal.BLOB_BORDER)
    pcall(b.SetFillAlpha, b, 128)
    pcall(b.SetBorderAlpha, b, 192)
    pcall(b.SetBorderScalar, b, 1)
    return b
end

-- Ring on the quest's own map icon. The game's quest log shows the pin's inner
-- glow and outer "link" glow (QuestDataProvider OnHighlightedQuestPOIChange,
-- through POIButtonHighlightManager, a game table never written here). This draws
-- the same two textures on a separate frame over the pin, at its scale.
Journal.RING_OUTER = "ui-questpoi-outerglow"     -- the pin's LinkGlow (QuestDataProvider.xml), 75 px
Journal.RING_INNER = "UI-QuestPoi-InnerGlow"     -- its HighlightTexture (POIButton.lua), 32 px
Journal.RING_OUTER_SIZE, Journal.RING_INNER_SIZE = 75, 32
Journal.RING_ALPHA = 0.45                        -- softer than the game's full-strength glow
Journal.PIN_TEMPLATE = "QuestPinTemplate"        -- QuestDataProviderMixin:GetPinTemplate()

-- The map's pin for a quest, read from its pin pool (nothing written).
function Journal.PinFor(map, questID)
    local pools = map.pinPools
    local pool = type(pools) == "table" and pools[Journal.PIN_TEMPLATE]
    if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return nil end
    local ok, iter, state, start = pcall(pool.EnumerateActive, pool)
    if not ok or type(iter) ~= "function" then return nil end
    for a, b in iter, state, start do
        -- pairs over activeObjects: the pin is either the key (a plain pool) or the value.
        for _, pin in ipairs({ a, b }) do
            if type(pin) == "table" and rawget(pin, "questID") == questID and pin.IsShown and pin:IsShown() then return pin end
        end
    end
    return nil
end

local function makeRing(child)
    local r = CreateFrame("Frame", nil, child)
    r:SetSize(Journal.RING_OUTER_SIZE, Journal.RING_OUTER_SIZE)
    r:EnableMouse(false)
    r.outer = r:CreateTexture(nil, "OVERLAY")
    r.outer:SetSize(Journal.RING_OUTER_SIZE, Journal.RING_OUTER_SIZE)
    r.outer:SetPoint("CENTER", r, "CENTER", 0, 0)
    r.outer:SetBlendMode("ADD")
    r.inner = r:CreateTexture(nil, "OVERLAY", nil, 1)
    r.inner:SetSize(Journal.RING_INNER_SIZE, Journal.RING_INNER_SIZE)
    r.inner:SetPoint("CENTER", r, "CENTER", 0, 0)
    r.inner:SetBlendMode("ADD")
    if r.outer.SetAtlas then pcall(r.outer.SetAtlas, r.outer, Journal.RING_OUTER) end
    if r.inner.SetAtlas then pcall(r.inner.SetAtlas, r.inner, Journal.RING_INNER) end
    r.outer:SetAlpha(Journal.RING_ALPHA)
    r.inner:SetAlpha(Journal.RING_ALPHA)
    r:Hide()
    return r
end

local function ringOn(child, map, questID)
    local pin = Journal.PinFor(map, questID)
    if not pin then return end
    if not ring then ring = makeRing(child); Journal.ring = ring end
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", pin, "CENTER", 0, 0)
    -- The pin keeps its size as the map zooms (its own scale); match it.
    local ps, cs = pin:GetEffectiveScale(), child:GetEffectiveScale()
    if type(ps) == "number" and type(cs) == "number" and cs > 0 then ring:SetScale(ps / cs) end
    ring:SetFrameLevel((pin:GetFrameLevel() or 0) + 1)
    ring:Show()
end

-- Lights questID's area and icon on the map (nil = none). Only on a map that shows
-- quests, and with the game's "Quest objectives on the map" (questPOI) on.
function Journal.Light(questID)
    if blob then pcall(blob.DrawNone, blob) end
    if ring then ring:Hide() end
    if type(questID) ~= "number" then return end
    if type(GetCVarBool) == "function" and GetCVarBool("questPOI") == false then return end
    local child, map = canvas()
    if not child then return end
    local mapID = map.mapID
    if type(mapID) ~= "number" or not Journal.MapShowsQuests(mapID) then return end
    ringOn(child, map, questID)
    if Journal.noBlob then return end
    if not blob then
        blob = makeBlob(child)
        if not blob then Journal.noBlob = true; return end   -- this client can't create one; the ring and ping still work
        Journal.blob = blob
    end
    blob:SetFrameLevel(blobLevel(map))
    pcall(blob.SetMapID, blob, mapID)
    pcall(blob.DrawBlob, blob, questID, true)
end

function Journal.Track(q)
    local QL = C_QuestLog
    if q.watched then
        if QL and QL.RemoveQuestWatch then QL.RemoveQuestWatch(q.id) end
        q.watched = false
        data.watched = math.max(0, (data.watched or 1) - 1)
    else
        local most = type(MAX_QUEST_WATCHES) == "number" and MAX_QUEST_WATCHES or Journal.WATCH_MAX
        if (data.watched or 0) >= most then
            refuse(type(QUEST_WATCH_TOO_MANY) == "string" and QUEST_WATCH_TOO_MANY:format(most)
                or L["You can track up to %d quests."]:format(most))
            return
        end
        if QL and QL.AddQuestWatch then QL.AddQuestWatch(q.id) end
        q.watched = true
        data.watched = (data.watched or 0) + 1
    end
    if S.page == "list" then Journal.FillList(false) else Journal.PaintFooter(q) end
end

function Journal.Share(q)
    -- A menu left open as combat started still ends up here.
    if InCombatLockdown() then
        refuse(ERR_NOT_IN_COMBAT or L["Not in combat."])
        return
    end
    if type(QuestLogPushQuest) == "function" and q.logIndex then QuestLogPushQuest(q.logIndex) end
end

-- The footer's Abandon asks first (W.Confirm: "Abandon?", 3 s). Its second click
-- lands here, as does the tracker popup's yes. Runs the game's own steps (like its
-- quest log: select, mark, abandon) and restores the old selection. The quest's
-- page goes back to the list if open; any other page stays.
function Journal.Abandon(q)
    local QL = C_QuestLog
    if not (QL and QL.SetSelectedQuest and QL.SetAbandonQuest and QL.AbandonQuest) then return end
    local before = call(QL.GetSelectedQuest)
    QL.SetSelectedQuest(q.id)
    QL.SetAbandonQuest()
    QL.AbandonQuest()
    if type(PlaySound) == "function" and SOUNDKIT then PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST) end
    if type(before) == "number" and before ~= q.id then QL.SetSelectedQuest(before) end
    if S.page == "quest" and S.quest == q.id then Journal.ShowList() end
end

-- What abandoning removes, the game's way (QuestMapQuestOptions_AbandonQuest: the
-- same steps, then the names of the items it can name). nil = nothing.
function Journal.AbandonItems(q)
    local QL = C_QuestLog
    if not (QL and QL.GetAbandonQuestItems and QL.SetSelectedQuest and QL.SetAbandonQuest) then return nil end
    local before = call(QL.GetSelectedQuest)
    QL.SetSelectedQuest(q.id)
    QL.SetAbandonQuest()
    local items = call(QL.GetAbandonQuestItems)
    if type(before) == "number" and before ~= q.id then QL.SetSelectedQuest(before) end
    if type(items) ~= "table" then return nil end
    local names = {}
    for _, id in ipairs(items) do
        local name = call(api(C_Item, "GetItemNameByID"), id)
        if type(name) == "string" then names[#names + 1] = name end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

local function alsoDestroys(items)
    return L["Also destroys %s."]:format(Win().Parts.Hex(Style.INK.WARN) .. items .. "|r")
end

-- The warning card over the page while Abandon is asking about q; nil removes it.
function Journal.Warn(q)
    local c = Journal.warn
    if not c then return end
    local items = q and Journal.AbandonItems(q)
    if items then
        c:Set(alsoDestroys(items))
        if not c.up then
            c.up = true
            DUI.Motion.Fade(c, 0, 1, DUI.Motion.FAST)
        end
    elseif c.up then
        c.up = false
        DUI.Motion.Fade(c, 1, 0, DUI.Motion.FAST)
    end
end

-- The tracker's Abandon: a yes/no box right there naming the quest and what it
-- removes, no map or log needed (the journal may be off or folded). Checked again
-- on yes, since the quest may be gone by then.
function Journal.AbandonPopup(q)
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    local which = "DAYLIGHTUI_ABANDON_QUEST"
    StaticPopupDialogs[which] = StaticPopupDialogs[which] or {
        text = "%s", button1 = YES or L["Yes"], button2 = NO or L["No"],
        OnAccept = function(_, d)
            if d and Journal.CanAbandon(d) then Journal.Abandon(d) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local text = L["Abandon \"%s\"?"]:format(q.title or "")
    local items = Journal.AbandonItems(q)
    if items then text = text .. "\n" .. alsoDestroys(items) end
    StaticPopup_Show(which, text, nil, { id = q.id })
end

-- Right-click menus. The game's quest log has them (QuestMapFrame.lua
-- QuestMapLogTitleButton_CreateContextMenu, QuestMapLogHeaderButton_...); these
-- offer the same through W.OpenMenu and the journal's own actions. Abandon opens
-- the quest with the footer's Abandon already asking, so one stray click never
-- drops a quest.

function Journal.MenuKeys(q)
    local keys, text = {}, {}
    local function add(k, t) keys[#keys + 1] = k; text[k] = t end
    add("map", L["Show on map"])
    add("track", q.watched and (UNTRACK_QUEST or L["Untrack"]) or (TRACK_QUEST or L["Track"]))
    local focused = call(api(C_SuperTrack, "GetSuperTrackedQuestID")) == q.id
    add("focus", focused and (STOP_SUPER_TRACK_QUEST or L["Stop focusing"]) or (SUPER_TRACK_QUEST or L["Focus"]))
    if Journal.CanShare(q) then add("share", SHARE_QUEST or L["Share"]) end
    if Journal.CanAbandon(q) then add("abandon", ABANDON_QUEST or L["Abandon"]) end
    return keys, text
end

function Journal.Do(k, q)
    if k == "map" then Journal.Map(q)
    elseif k == "track" then Journal.Track(q)
    elseif k == "focus" then
        local ST = C_SuperTrack
        if ST and ST.SetSuperTrackedQuestID then
            ST.SetSuperTrackedQuestID(call(ST.GetSuperTrackedQuestID) == q.id and 0 or q.id)
        end
    elseif k == "share" then Journal.Share(q)
    elseif k == "abandon" then
        Journal.ShowQuest(q.id)
        Journal.AskAbandon()
    end
end

-- The footer's Abandon (button 4) with W.Confirm, set up once on the footer's own
-- button. Switching between rest and asking lays out the footer again, so the row
-- shares its space by the label shown. The right-click menu arrives here already
-- asking, so the label names what happens; a longer "Click again to abandon"
-- doesn't fit in this row.
Journal.ASKING = L["Abandon?"]

local function abandonButton()
    local b = f and f.quest.footer.buttons[4]
    if not b then return nil end
    if not b.confirm then
        b.confirm = true
        DUI.Widgets.Confirm(b, function() return ABANDON_QUEST_ABBREV or L["Abandon"] end, function()
            local now = S.page == "quest" and S.quest and find(S.quest)
            if now then
                Journal.Abandon(now)
                return true   -- the game's abandon sound, not W.Confirm's
            end
        end, Journal.ASKING)
        local paint = b.Paint
        function b.Paint()
            paint()
            if b.armed ~= b.wasArmed then
                b.wasArmed = b.armed
                local now = S.page == "quest" and S.quest and find(S.quest)
                if now then Journal.PaintFooter(now) end
                Journal.Warn(b.armed and now or nil)
            end
        end
    end
    return b
end

-- The open quest's Abandon starts asking (from the journal's right-click menu).
function Journal.AskAbandon()
    local b = abandonButton()
    if b and not b.armed and not b.off and b:IsVisible() then b:GetScript("OnClick")(b) end
end

-- Back to rest (another page, or the journal closed).
local function calm()
    local b = f and f.quest.footer.buttons[4]
    if b and b.armed then b.armed = false; b.Paint() end
end

-- Close the menu when the journal goes (map closed, log folded), but only if it's
-- a journal row or zone menu.
function Journal.CloseMenu()
    local W = DUI.Widgets
    local owner = W and W.menuOwner
    while type(owner) == "table" and owner.GetParent do
        if owner == f then return W.CloseMenu() end
        owner = owner:GetParent()
    end
end

function Journal.Menu(q, owner)
    local W = DUI.Widgets
    if not (W and W.OpenMenu) then return end
    local keys, text = Journal.MenuKeys(q)
    W.OpenMenu(owner, keys, text, nil, function(k) DUI.SafeCall(Journal.Do, k, q) end)
end

-- Zone menu: track or untrack every quest in it (like the game's header menu).
function Journal.TrackZone(name, on)
    local QL = C_QuestLog
    if not QL then return end
    local most = type(MAX_QUEST_WATCHES) == "number" and MAX_QUEST_WATCHES or Journal.WATCH_MAX
    local count = data.watched or 0
    for _, g in ipairs(data.groups) do
        if g.name == name then
            for _, q in ipairs(g.quests) do
                if on and not q.watched and count < most and QL.AddQuestWatch then
                    QL.AddQuestWatch(q.id); q.watched = true; count = count + 1
                elseif not on and q.watched and QL.RemoveQuestWatch then
                    QL.RemoveQuestWatch(q.id); q.watched = false; count = count - 1
                end
            end
        end
    end
    data.watched = count
    Journal.FillList(false)
end

function Journal.ZoneMenu(name, owner)
    local W = DUI.Widgets
    if not (W and W.OpenMenu) then return end
    local keys = { "all", "none" }
    local text = { all = QUEST_LOG_TRACK_ALL or L["Track all"], none = QUEST_LOG_UNTRACK_ALL or L["Untrack all"] }
    W.OpenMenu(owner, keys, text, nil, function(k) DUI.SafeCall(Journal.TrackZone, name, k == "all") end)
end

function Journal.PaintFooter(q)
    if not f then return end
    local ab = f.quest.footer.buttons[4]
    local asking = ab and ab.armed
    f.quest.footer:Set({
        { text = L["Show on map"], primary = true, onClick = function() Journal.Map(q) end },
        { text = q.watched and (UNTRACK_QUEST_ABBREV or L["Untrack"]) or (TRACK_QUEST_ABBREV or L["Track"]),
          onClick = function() Journal.Track(q) end },
        { text = SHARE_QUEST_ABBREV or L["Share"], off = not Journal.CanShare(q), onClick = function() Journal.Share(q) end },
        { text = asking and Journal.ASKING or (ABANDON_QUEST_ABBREV or L["Abandon"]),
          off = not Journal.CanAbandon(q) },
    })
    abandonButton()
end

-- Pages

function Journal.ShowList(lift)
    if not f then return end
    S.page, S.quest = "list", nil
    calm()
    Journal.Light(nil)
    f.quest:Hide()
    f.list:Show()
    Journal.FillList(lift ~= false)
    -- The page's own pieces lift in with its rows (the window kit's page swap).
    if lift ~= false then Win().Feel.Stagger({ f.list.search }, 0) end
end

function Journal.ShowQuest(id)
    if not (f and find(id)) then return end
    S.page, S.quest = "quest", id
    calm()
    Journal.Spot(nil)
    f.list:Hide()
    f.quest:Show()
    Journal.FillQuest(true)
    Win().Feel.Stagger({ f.quest.footer.frame }, 0)
    Journal.Light(id)
end

-- A controller: the game gives the D-pad to its world map, not to the journal
-- over it, so the journal takes its own buttons while it shows (Pad.Take), as
-- the game's quest log does: X tracks or untracks the quest on the row or page
-- (no walk down to the footer), Y its menu, the left menu button the search,
-- and B on a quest's page goes back to the list.
local function padQuest(stop)
    if type(stop) == "table" and type(stop.quest) == "table" and stop.quest.id then return stop.quest, stop end
    if S.page == "quest" and S.quest then return find(S.quest), nil end
end

function Journal.PadSetup()
    f.padNoDefaults = true
    f.padSelect = function(stop) if type(stop) == "table" and stop.quest then return L["Open"] end end
    f.padKeys = {
        { key = "X", follow = true, when = function(at) return padQuest(at) ~= nil end,
          label = function(at)
              local q = padQuest(at)
              return q and q.watched and (UNTRACK_QUEST or L["Untrack"]) or (TRACK_QUEST or L["Track"])
          end,
          run = function(at) local q = padQuest(at); if q then Journal.Track(q) end end },
        { key = "Y", follow = true, label = CONTEXT_ACTION_LABEL_MORE_ACTIONS or L["More"],
          when = function(at) return padQuest(at) ~= nil end,
          run = function(at)
              local q, row = padQuest(at)
              if q then Journal.Menu(q, row or f.quest.footer.frame) end
          end },
        { key = "MENU_LEFT", follow = true, label = SEARCH or L["Search"],
          when = function() return S.page == "list" and f.list.search:IsVisible() end,
          run = function() f.list.search:SetFocus() end },
        { key = "B", follow = true, label = BACK or L["Back"],
          when = function() return S.page == "quest" end,
          run = function() Journal.ShowList() end },
    }
end

-- The tracker's click: open the map with the log on this quest's page. The map's
-- own opening calls can't do it (QuestMapFrame_OpenToQuestDetails taints the map),
-- so the request waits here for OnShow, during or after the call. A folded log
-- doesn't take it, so it expires and a later open shows the list.
function Journal.OpenTo(id, mapID)
    if InCombatLockdown() then return ns.Clicks.OpenMap(id, mapID) end
    want, wantUntil = id, GetTime() + Journal.WANT_WAIT
    ns.Clicks.OpenMap(id, mapID)
    if not (f and f:IsVisible()) then return end
    if want then    -- already open
        if S.page == "quest" and S.quest == id then
            want, wantUntil = nil, nil
        else
            data = Journal.Read()
            Journal.Arrive()
        end
    end
    Journal.LightAgain(id)
end

-- The quest's page if a tracker click asked for it, otherwise the list.
function Journal.Arrive()
    local id = want
    local late = id and GetTime() > wantUntil
    want, wantUntil = nil, nil
    if id and not late and find(id) then Journal.ShowQuest(id) else Journal.ShowList(true) end
end

-- Re-read the log and fill the visible page (no lift, it's an update).
function Journal.Refresh(lift)
    if not (f and f:IsVisible()) then return end
    data = Journal.Read()
    if S.page == "quest" and S.quest and find(S.quest) then Journal.FillQuest(lift) else Journal.ShowList(lift) end
end

local pending = false
function Journal.Soon()
    if pending then return end
    pending = true
    local function run() pending = false; DUI.SafeCall(Journal.Refresh, false) end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

Journal.EVENTS = { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
                   "QUEST_TURNED_IN", "GROUP_ROSTER_UPDATE", "UNIT_QUEST_LOG_CHANGED", "ZONE_CHANGED_NEW_AREA", "SUPER_TRACKING_CHANGED",
                   "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

-- Covering the game's panel

-- Sets the game's pieces in the panel to alpha 0 under the journal (on), or back (off).
-- The game's pieces under the journal, see-through but still there, would be
-- stops for the controller's D-pad, which then got stuck on things nobody can
-- see. The game's own mark keeps them out (out of combat only).
local skipped = setmetatable({}, { __mode = "k" })   -- marked by the journal, so only those are cleared
local function skipOnPad(frames, on)
    if type(SmartNavigation_MarkFrameIgnored) ~= "function" then return end
    DUI.AfterCombat(function()
        for _, o in ipairs(frames) do
            if on and not skipped[o] then
                skipped[o] = true
                SmartNavigation_MarkFrameIgnored(o)
            elseif not on and skipped[o] then
                skipped[o] = nil
                if type(SmartNavigation_ClearIgnoreStatus) == "function" then SmartNavigation_ClearIgnoreStatus(o) end
            end
        end
    end, "journal:padskip")
end

function Journal.Veil(on)
    local qm = Journal.Panel()
    if not qm then return end
    local frames = {}
    local function each(o)
        if o == f or type(o) ~= "table" or type(o.SetAlpha) ~= "function" then return end
        if on then
            if veiled[o] == nil then veiled[o] = o:GetAlpha() or 1 end
            o:SetAlpha(0)
        elseif veiled[o] ~= nil then
            o:SetAlpha(veiled[o])
            veiled[o] = nil
        end
    end
    for _, c in ipairs({ qm:GetChildren() }) do
        each(c)
        if c ~= f then frames[#frames + 1] = c end
    end
    for _, r in ipairs({ qm:GetRegions() }) do each(r) end
    skipOnPad(frames, on)
end

local function searchBox(page)
    local E = DUI.Win.EDGE
    local e = DUI.Widgets.Input(page, { search = true, maxLetters = 60, hint = SEARCH or L["Search"],
        onChange = function(text)
            if text ~= S.query then
                S.query = text
                Journal.FillList(false)
            end
        end })
    e:SetPoint("TOPLEFT", page, "TOPLEFT", E, -8)
    e:SetPoint("TOPRIGHT", page, "TOPRIGHT", -64, -8)
    return e
end

-- The panel's background at `journalOpacity`.
function Journal.PaintBack()
    local bg = Style.BACKGROUND
    f.bg:SetVertexColor(bg[1], bg[2], bg[3], db.journalOpacity)
end

function Journal.Build()
    local qm = Journal.Panel()
    if f or not qm then return f end
    f = CreateFrame("Frame", "DaylightUIQuestJournal", qm)
    f:SetAllPoints(qm)
    f:SetFrameLevel(Journal.LEVEL)
    f:EnableMouse(true)
    f.bg = tex(f, "BACKGROUND")
    Journal.PaintBack()
    f.bg:SetAllPoints(f)
    f.edge = tex(f, "BORDER", { 1, 1, 1, 0.06 })
    f.edge:SetWidth(1)
    f.edge:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.edge:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)

    local Parts = DUI.Win.Parts
    f.list = CreateFrame("Frame", nil, f)
    f.list:SetAllPoints(f)
    f.list.search = searchBox(f.list)
    f.list.count = Style.Text(f.list, Style.SIZE.small, "RIGHT")
    f.list.count:SetPoint("RIGHT", f.list, "TOPRIGHT", -DUI.Win.EDGE, -21)
    f.list.stack = Parts.Stack(f.list, { top = Journal.TOP, bottom = 8 })

    f.quest = CreateFrame("Frame", nil, f)
    f.quest:SetAllPoints(f)
    f.quest:Hide()
    f.quest.stack = Parts.Stack(f.quest, { bottom = Journal.FOOT })
    f.quest.footer = Parts.Footer(f.quest, { equal = true })
    local warn = Parts.Why(f.quest, { warn = true })
    warn:SetPoint("BOTTOMLEFT", f.quest.footer.frame, "TOPLEFT", 0, Journal.WARN_Y)
    warn:SetPoint("BOTTOMRIGHT", f.quest.footer.frame, "TOPRIGHT", 0, Journal.WARN_Y)
    warn:SetFrameLevel(f.quest.footer.frame:GetFrameLevel() + 30)
    warn:SetAlpha(0)
    warn.seen = true   -- Journal.Warn fades it both ways
    warn:SetScript("OnHide", nil)
    Journal.warn = warn

    f.events = CreateFrame("Frame")
    f.events:SetScript("OnEvent", function() Journal.Soon() end)
    f:SetScript("OnShow", function()
        -- The game sets the panel's strata when the map takes it (HIGH).
        if qm.GetFrameStrata then f:SetFrameStrata(qm:GetFrameStrata()) end
        f:SetFrameLevel(Journal.LEVEL)
        for _, e in ipairs(Journal.EVENTS) do pcall(f.events.RegisterEvent, f.events, e) end
        Journal.Veil(true)   -- a piece the game created since
        S.query = f.list.search:GetText() or ""
        data = Journal.Read()
        Journal.Arrive()
        if DUI.Pad.On() then DUI.Pad.Take(f) end
    end)
    f:SetScript("OnHide", function()
        f.events:UnregisterAllEvents()
        f.list.search:ClearFocus()
        calm()
        Journal.Light(nil)
        Journal.Spot(nil)
        mapHover = {}
        Journal.CloseMenu()
        DUI.Pad.Release(f)
    end)
    -- The game's quest icon on the map reports its hover (QuestPinMixin:OnMouseEnter/
    -- Leave). Only listened to, nothing of the map's is touched.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("MapCanvas.QuestPin.OnEnter", function(_, _, questID) Journal.MapHover({ questID }) end, Journal)
        EventRegistry:RegisterCallback("MapCanvas.QuestPin.OnLeave", function() Journal.MapHover(nil) end, Journal)
    end
    Journal.PadSetup()
    Journal.frame = f
    return f
end

-- On (the setting): the journal covers the game's panel. Off: the game's own again.
function Journal.Apply()
    local on = db and db.journal ~= false
    -- Questie's map icons hover a quest the same way the game's own do.
    local spot = db and db.journalHoverIcons ~= false
    ns.Bridge.WatchHover((on or spot) and Journal.IconHover or nil)
    if on then
        if not Journal.Build() then return end
        Journal.Veil(true)
        f:Show()
        if f:IsVisible() then Journal.Refresh(true) end
    elseif f then
        f:Hide()
        Journal.Veil(false)
    end
end

function Journal.Enable(mod)
    db = mod.db
    Journal.Apply()
end

function Journal.OnStyleChanged()
    if f then
        Journal.PaintBack()
        Journal.Refresh(false)
    end
end
