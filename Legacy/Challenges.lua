-- Legacy window, Challenges page. Categories on the left (the player's class first, as
-- in the game), each with a done count and a dot when a newly earned challenge is
-- waiting there, plus a search and All / Not yet / Done chips (the game's filter menu).
-- On the right, Legacy Points from challenges as a bar, then each challenge: icon, name,
-- one-line description and points; completed ones in full color with the date. Clicking
-- one expands it: full description, steps in two columns (counted steps as bars), and a
-- track switch. Shift-click links it in chat.
--
-- The lists are the game's achievement lists, filtered the same way it does
-- (Data.Categories / Data.Challenges). Search uses the client's own
-- SetAchievementSearchString, which answers with ACHIEVEMENT_SEARCH_UPDATED.

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win
local Motion = DUI.Motion

local Challenges = {}
ns.Challenges = Challenges

Challenges.EDGE = 16
Challenges.SIDE = 236          -- category column width
Challenges.TOP = 76            -- search and chips above the categories
Challenges.SUM = 52            -- points bar above the challenges
Challenges.CAT = 26
Challenges.ROW = 54            -- collapsed challenge row
Challenges.ICON = 34
Challenges.STEP = 22           -- step line
Challenges.STEP_BAR = 30       -- counted step: text and a bar
Challenges.FILTERS = { "all", "todo", "done" }
Challenges.STEPS_WAIT = 0.5     -- s to let a burst of counted steps settle before repainting
Challenges.FILTER_WORD = { all = ALL or L["All"], todo = L["Not yet"], done = L["Done"] }

Challenges.folds = {}          -- collapsed parent categories (this session)

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end
local function Rows() return DUI.Lfg.Rows end
local function Data() return ns.Data end
local function hex(c) return Win.Parts.Hex(c) end
local function pop(n) return hex({ Style.Pop() }) .. tostring(n) .. "|r" end
local function sound(name) if DUI.Sound then DUI.Sound.Play(name) end end

local function tex(parent, layer, c, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return t
end

-- Categories

local function count(c)
    local done, total = 0, 0
    if c.has then done, total = Data().Count(c.id) end
    for _, k in ipairs(c.kids) do
        local d, t = count(k)
        done, total = done + d, total + t
    end
    return done, total
end

local function catRow(s, c, name, sub)
    local done, total = Data().Count(c.id)
    local b = Rows().Row(s, { kind = "cat", height = Challenges.CAT, text = name or c.name,
        color = Challenges.cat == c.id and Style.INK.VALUE or Style.INK.TEXT,
        value = pop(done) .. "/" .. total, valueColor = Style.INK.LABEL,
        dot = Data().Unviewed(c.id) and { Style.Pop() } or nil, picked = Challenges.cat == c.id,
        onClick = function() Challenges.Pick(c.id) end })
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", b, "LEFT", (sub and 18 or 8) + (b.dot:IsShown() and 14 or 0), 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -60, 0)
    return b
end

-- Every category id in the tree, in order.
local function flat(list, out)
    for _, c in ipairs(list) do
        out[#out + 1] = c
        flat(c.kids, out)
    end
    return out
end

function Challenges.RenderCats(keep)
    local page = Challenges.page
    local s = page.cats
    local at = keep and s:Scrolled()
    s:Begin()
    local function walk(list, sub)
        for _, c in ipairs(list) do
            if #c.kids > 0 then
                local d, t = count(c)
                local shut = DUI.Social.Friends.Head(s, c.id, c.name, pop(d) .. "/" .. t,
                    Challenges.folds, function() Challenges.RenderCats(true) end)
                if not shut then
                    if c.has then catRow(s, c, c.name, true) end
                    walk(c.kids, true)
                end
            elseif not sub then
                -- A top category with no subcategories (Dungeons, Raids) gets its own heading like the
                -- others, with its row under it.
                local d, t = count(c)
                local shut = DUI.Social.Friends.Head(s, c.id, c.name, pop(d) .. "/" .. t,
                    Challenges.folds, function() Challenges.RenderCats(true) end)
                if not shut then catRow(s, c, nil, true) end
            else
                catRow(s, c, nil, sub)
            end
        end
    end
    walk(Challenges.tree or {}, false)
    page.catPieces = s:End()
    if at then s:ScrollTo(at) end
end

-- Challenge row

local function makeStep(parent)
    local st = CreateFrame("Frame", nil, parent)
    st.dot = st:CreateTexture(nil, "ARTWORK")
    st.dot:SetTexture(DUI.MEDIA .. "shape-circle.png")
    st.dot:SetSize(6, 6)
    st.dot:SetPoint("LEFT", st, "LEFT", 2, 0)
    st.text = Style.Text(st, Style.SIZE.small, "LEFT")
    st.text:SetPoint("LEFT", st, "LEFT", 14, 0)
    st.text:SetPoint("RIGHT", st, "RIGHT", 0, 0)
    st.text:SetWordWrap(false)
    st.bar = W().Bar(st)
    st.bar:SetPoint("BOTTOMLEFT", st, "BOTTOMLEFT", 0, 2)
    st.bar:SetPoint("BOTTOMRIGHT", st, "BOTTOMRIGHT", 0, 2)
    return st
end

local function makeRow(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")
    b.hi = tex(b, "BACKGROUND", Win.Parts.HI)
    b.hi:SetAllPoints(b)
    b.hi:Hide()
    b.open = tex(b, "BACKGROUND", { 1, 1, 1, 0.03 }, 1)
    b.open:SetAllPoints(b)
    b.edge = tex(b, "ARTWORK")
    b.edge:SetSize(Challenges.ICON + 2, Challenges.ICON + 2)
    b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -9)
    b.well = tex(b, "ARTWORK", { 0, 0, 0, 1 }, 1)
    b.well:SetPoint("TOPLEFT", b.edge, "TOPLEFT", 1, -1)
    b.well:SetPoint("BOTTOMRIGHT", b.edge, "BOTTOMRIGHT", -1, 1)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints(b.well)
    Style.CropIcon(b.icon)
    b.points = Style.Text(b, Style.SIZE.body, "RIGHT")
    b.points:SetPoint("TOPRIGHT", b, "TOPRIGHT", -10, -12)
    b.date = Style.Text(b, Style.SIZE.tiny, "RIGHT")
    b.date:SetPoint("TOPRIGHT", b.points, "BOTTOMRIGHT", 0, -4)
    Style.InkText(b.date, "GOOD")
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetPoint("TOPLEFT", b.edge, "TOPRIGHT", 10, -1)
    b.name:SetPoint("RIGHT", b, "RIGHT", -70, 0)
    b.name:SetWordWrap(false)
    b.desc = Style.Text(b, Style.SIZE.small, "LEFT")
    b.desc:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -4)
    b.desc:SetPoint("RIGHT", b, "RIGHT", -70, 0)
    b.desc:SetJustifyV("TOP")
    -- Expanded: the steps, then the track switch.
    b.more = CreateFrame("Frame", nil, b)
    b.more:SetPoint("LEFT", b, "LEFT", 8 + Challenges.ICON + 12, 0)
    b.more:SetPoint("RIGHT", b, "RIGHT", -16, 0)
    b.steps = {}
    b.track = W().Switch(b.more)
    b.track:SetScript("OnClick", function(self)
        local id = b.ch and b.ch.id
        if id then Data().SetTracked(id, not Data().Tracked(id)) end
        self.SetOn(id and Data().Tracked(id) or false)
    end)
    b.trackText = Style.Text(b.more, Style.SIZE.small, "LEFT")
    b.trackText:SetPoint("LEFT", b.track, "RIGHT", 8, 0)
    b.trackText:SetText(TRACK_ACHIEVEMENT or L["Track"])
    Style.InkText(b.trackText, "LABEL")
    b:SetScript("OnEnter", function(self) Win.Parts.Light(self.hi, true) end)
    b:SetScript("OnLeave", function(self) Win.Parts.Light(self.hi, false) end)
    b:SetScript("OnClick", function(self)
        local c = self.ch
        if not c then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") then return Data().Link(c.id) end
        sound("click")
        Challenges.Open(Challenges.opened ~= c.id and c.id or nil)
    end)
    return b
end

-- Lay out steps in two columns (a lone counted step spans both), from y down.
local function laySteps(b, steps, w, y)
    local colW = math.floor((w - 16) / 2)
    local col, rowY, lineH = 0, y, 0
    for i, st in ipairs(steps) do
        local p = b.steps[i]
        if not p then p = makeStep(b.more); b.steps[i] = p end
        p:Show()
        local counted = st.need ~= nil
        local alone = counted and #steps == 1
        local h = counted and Challenges.STEP_BAR or Challenges.STEP
        p:ClearAllPoints()
        p:SetSize(alone and w or colW, h)
        p:SetPoint("TOPLEFT", b.more, "TOPLEFT", (alone and 0) or col * (colW + 16), -rowY)
        p.text:SetText(counted and (st.text ~= "" and (st.text .. "  ") or "") .. pop(st.have) .. " / " .. st.need or st.text)
        Style.InkText(p.text, st.done and "TEXT" or "LABEL")
        local c = st.done and Style.INK.GOOD or Style.INK.OFF
        p.dot:SetVertexColor(c[1], c[2], c[3], 1)
        p.dot:SetShown(not counted)
        p.text:ClearAllPoints()
        if counted then p.text:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -2) else p.text:SetPoint("LEFT", p, "LEFT", 14, 0) end
        p.text:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        p.bar:SetShown(counted)
        if counted then
            p.bar:SetMinMaxValues(0, st.need)
            p.bar:SetValue(st.have)
            W().BarAccent(p.bar)
        end
        lineH = math.max(lineH, h)
        if alone or col == 1 then col, rowY, lineH = 0, rowY + lineH + 4, 0 else col = 1 end
    end
    if col == 1 then rowY = rowY + lineH + 4 end
    for i = #steps + 1, #b.steps do b.steps[i]:Hide() end
    return rowY
end

-- Row height for this challenge, expanded or not (text measured at row width before
-- it's placed).
local function measure(page, c, w, open)
    if not open then return Challenges.ROW end
    local m = page.measure
    m:SetWidth(w - (8 + Challenges.ICON + 10) - 70)
    m:SetText(c.desc)
    local dh = m:GetStringHeight()
    dh = type(dh) == "number" and dh or 14
    local steps = Data().Steps(c.id)
    local sw = w - (8 + Challenges.ICON + 12) - 16
    local probe = page.probeRow
    local sh = laySteps(probe, steps, sw, 0)
    probe.more:Hide()
    local h = 9 + 15 + 4 + dh + 10 + sh + (c.done and 0 or 26) + 10
    return math.max(Challenges.ROW, math.floor(h + 0.5)), steps, dh
end

local function fillRow(b, c, open, steps, dh, w)
    b.ch = c
    local done = c.done
    b.icon:SetTexture(c.icon or 134400)
    b.icon:SetDesaturated(not done and not open)
    local l = done and 1 or 0.6
    b.icon:SetVertexColor(l, l, l, 1)
    local e = done and { Style.Accent() } or Style.INK.OFF
    b.edge:SetVertexColor(e[1], e[2], e[3], done and 0.9 or 0.5)
    b.name:SetText(c.name)
    Style.InkText(b.name, done and "VALUE" or "TEXT")
    b.desc:SetText(c.desc)
    b.desc:SetWordWrap(open)
    if open then
        b.desc:SetHeight(dh)
        Style.InkText(b.desc, "TEXT")
    else
        b.desc:SetHeight(14)
        Style.InkText(b.desc, "LABEL")
    end
    b.points:SetText(c.points > 0 and pop("+" .. c.points) or "")
    b.date:SetText(c.date or "")
    b.open:SetShown(open)
    b.more:SetShown(open)
    if open then
        local top = 9 + 15 + 4 + dh + 10
        b.more:ClearAllPoints()
        b.more:SetPoint("TOPLEFT", b, "TOPLEFT", 8 + Challenges.ICON + 12, -top)
        b.more:SetPoint("RIGHT", b, "RIGHT", -16, 0)
        b.more:SetHeight(1)
        local sh = laySteps(b, steps, w - (8 + Challenges.ICON + 12) - 16, 0)
        b.track:SetShown(not done)
        b.trackText:SetShown(not done)
        b.track:ClearAllPoints()
        b.track:SetPoint("TOPLEFT", b.more, "TOPLEFT", 0, -(sh + 4))
        b.track.SetOn(Data().Tracked(c.id))
    end
end

-- Lists

-- Search filter: none while empty. While the client works on new text, the previous
-- answer stays.
local function filtered()
    local text = Challenges.page.search:GetText() or ""
    if text == "" then return nil end
    if Challenges.waiting then return Challenges.lastFilter end
    Challenges.lastFilter = Data().Filtered() or {}
    return Challenges.lastFilter
end

local function holds(list, id)
    for _, c in ipairs(flat(list, {})) do if c.id == id and c.has then return true end end
    return false
end

-- Category to show: the selected one, else the class's, else the first.
local function settle()
    local tree = Challenges.tree
    if Challenges.cat and holds(tree, Challenges.cat) then return end
    local want = Challenges.cat or Data().DefaultCategory()
    if want and holds(tree, want) then Challenges.cat = want return end
    for _, c in ipairs(flat(tree, {})) do
        if c.has then Challenges.cat = c.id return end
    end
    Challenges.cat = nil
end

function Challenges.RenderList(keep)
    local page = Challenges.page
    local s = page.list
    local at = keep and s:Scrolled()
    local list = Challenges.cat and Data().Challenges(Challenges.cat, filtered()) or {}
    Challenges.list = list
    s:Begin()
    local w = s:Width()
    local openRow
    for _, c in ipairs(list) do
        local open = Challenges.opened == c.id
        local h, steps, dh = measure(page, c, w, open)
        local b = s:Piece("ch", makeRow, h, 2)
        fillRow(b, c, open, steps, dh, w)
        if open then openRow = b end
    end
    page.pieces = s:End()
    if at then s:ScrollTo(at) end
    local text = page.search:GetText() or ""
    page.note:SetShown(#list == 0)
    page.note:SetText(text ~= "" and L["No challenges match."] or L["No challenges yet."])
    -- Points from challenges: earned out of the maximum.
    local p = Data().Points()
    local max = p.max or p.cap
    -- New points count up and the bar glides.
    DUI.Motion.CountTo(page.sumValue, p.earned, function(n)
        return max and (pop(n) .. " / " .. max .. "  " .. L["Legacy Points"]) or (pop(n) .. "  " .. L["Legacy Points"])
    end)
    Style.SetBarValue(page.sumBar, max and max > 0 and math.min(p.earned / max, 1) or 0)
    W().BarAccent(page.sumBar)
    return openRow
end

function Challenges.Render(keep)
    local page = Challenges.page
    if not (page and page:IsShown()) then return end
    Challenges.tree = Data().Categories(filtered())
    settle()
    if Challenges.cat then Data().MarkViewed(Challenges.cat) end
    Challenges.RenderCats(keep)
    local open = Challenges.RenderList(keep)
    if Challenges.scrollTo and open then
        Challenges.scrollTo = nil
        local _, _, _, _, y = open:GetPoint(1)
        if type(y) == "number" then page.list:ScrollTo(-y - 8) end
    end
end

function Challenges.Pick(id)
    if Challenges.cat == id then return end
    Challenges.cat = id
    Challenges.opened = nil
    Data().MarkViewed(id)
    Challenges.RenderCats(true)
    Challenges.RenderList()
    Win.Feel.Stagger(Challenges.page.pieces or {}, 0)
    ns.Window.Header()
end

-- Expand one challenge (nil: none); its steps fade in.
function Challenges.Open(id)
    Challenges.opened = id
    local open = Challenges.RenderList(true)
    if open and Motion.On() then
        open.more:SetAlpha(0)
        Motion.Tween(open.more, 0, 1, Motion.FAST, function(a) open.more:SetAlpha(a) end)
    end
end

-- Open on this challenge (from a tracked one's click, ShowLegacyChallenge): select its
-- category, expand its parents, reset the chips to All if they hid it (like the game's
-- TrySelectChallengeResettingFilters), and clear the search.
function Challenges.Want(id)
    local cat = Data().CategoryOf(id)
    if not cat then return end
    Challenges.cat, Challenges.opened, Challenges.scrollTo = cat, id, true
    -- Expand its parents (GetCategoryInfo returns name, parentID; -1 = top).
    local at = cat
    for _ = 1, 4 do
        local ok, _, parent = pcall(GetCategoryInfo, at)
        if not ok or type(parent) ~= "number" or parent == -1 then break end
        Challenges.folds[parent] = nil
        at = parent
    end
    if Data().show ~= "all" then Challenges.Filter("all", true) end
    local page = Challenges.page
    if page and (page.search:GetText() or "") ~= "" then page.search:SetText("") end
end

function Challenges.Filter(id, quiet)
    Data().show = id
    for k, b in pairs(Challenges.page.chips) do b.SetOn(k == id) end
    if not quiet then Challenges.Render(true) end
end

-- A step of the grip drag: rows stretch, and the lists refill when it ends.
function Challenges.Stretch()
    local page = Challenges.page
    if page and page:IsShown() then page.cats:Stretch(); page.list:Stretch() end
end

function Challenges.Build(page)
    Challenges.page = page
    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    side:SetWidth(Challenges.SIDE)
    side.win = page.win
    page.side = side
    side.rule = tex(side, "ARTWORK", { 1, 1, 1, 0.05 })
    side.rule:SetWidth(1)
    side.rule:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, -8)
    side.rule:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 8)
    local main = CreateFrame("Frame", nil, page)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    main:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    main.win = page.win
    page.main = main
    page.search = W().Input(side, { search = true, hint = L["Search challenges..."], maxLetters = 64,
        onChange = function(text)
            Challenges.waiting = (text or "") ~= ""
            Data().Search(text or "")
            Challenges.Render()
        end })
    page.search:SetPoint("TOPLEFT", side, "TOPLEFT", Challenges.EDGE, -10)
    page.search:SetPoint("TOPRIGHT", side, "TOPRIGHT", -Challenges.EDGE, -10)
    page.chips = {}
    local x = Challenges.EDGE
    for _, id in ipairs(Challenges.FILTERS) do
        local b = W().Chip(side, Challenges.FILTER_WORD[id])
        b.FitWidth()
        b:SetPoint("TOPLEFT", side, "TOPLEFT", x, -44)
        b:SetScript("OnClick", function() Challenges.Filter(id) end)
        b.SetOn(Data().show == id)
        page.chips[id] = b
        x = x + b:GetWidth() + W().CHIP_GAP
    end
    page.cats = Win.Parts.Stack(side, { top = Challenges.TOP, bottom = 12 })
    -- Points from challenges, above the list.
    local sum = CreateFrame("Frame", nil, main)
    sum:SetPoint("TOPLEFT", main, "TOPLEFT", Challenges.EDGE, -14)
    sum:SetPoint("TOPRIGHT", main, "TOPRIGHT", -Challenges.EDGE, -14)
    sum:SetHeight(26)
    page.sum = sum
    page.sumLabel = Style.Text(sum, Style.SIZE.small, "LEFT")
    page.sumLabel:SetPoint("TOPLEFT", sum, "TOPLEFT", 0, 0)
    page.sumLabel:SetText(L["From challenges"])
    Style.InkText(page.sumLabel, "LABEL")
    page.sumValue = Style.Text(sum, Style.SIZE.body, "RIGHT")
    page.sumValue:SetPoint("TOPRIGHT", sum, "TOPRIGHT", 0, 0)
    Style.InkText(page.sumValue, "TEXT")
    page.sumBar = W().Bar(sum)
    page.sumBar:SetPoint("BOTTOMLEFT", sum, "BOTTOMLEFT", 0, 0)
    page.sumBar:SetPoint("BOTTOMRIGHT", sum, "BOTTOMRIGHT", 0, 0)
    page.list = Win.Parts.Stack(main, { top = Challenges.SUM, bottom = 12 })
    page.note = Style.Text(main, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", main, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    -- For measuring: a hidden string in the description font, and a row of steps.
    page.measure = Style.Text(page, Style.SIZE.small, "LEFT")
    page.measure:SetWordWrap(true)
    page.measure:Hide()
    page.probeRow = makeRow(page)
    page.probeRow:Hide()
    DUI.RegisterEvent("ACHIEVEMENT_SEARCH_UPDATED", function()
        Challenges.waiting = nil
        ns.Window.Refresh("challenges")
    end)
    for _, e in ipairs({ "ACHIEVEMENT_EARNED", "CONTENT_TRACKING_UPDATE", "TRACKED_ACHIEVEMENT_LIST_CHANGED" }) do
        DUI.RegisterEvent(e, function() ns.Window.Refresh("challenges") end)
    end
    DUI.RegisterEvent("CRITERIA_UPDATE", Challenges.Progress)
end

-- A step was counted (CRITERIA_UPDATE fires on every kill and loot, in bursts). Redraw
-- the shown list's steps once, Challenges.STEPS_WAIT s after the first. Categories stay,
-- since their done counts change on ACHIEVEMENT_EARNED.
function Challenges.Progress()
    local page = Challenges.page
    if Challenges.stepsSoon or not (page and page:IsVisible()) then return end
    Challenges.stepsSoon = true
    C_Timer.After(Challenges.STEPS_WAIT, function()
        Challenges.stepsSoon = nil
        if page:IsVisible() then Challenges.RenderList(true) end
    end)
end

-- On show, set the search again. The client drops its data on every loading screen and
-- only rebuilds it when a search is set (the game's page does the same).
function Challenges.Fill(page)
    local text = page.search:GetText() or ""
    Challenges.waiting = text ~= ""
    Data().Search(text)
    Challenges.Render()
end

function Challenges.Pieces(page)
    local out = { page.search }
    for _, id in ipairs(Challenges.FILTERS) do out[#out + 1] = page.chips[id] end
    for i, p in ipairs(page.catPieces or {}) do
        if i > 10 then break end
        out[#out + 1] = p
    end
    out[#out + 1] = page.sum
    for i, p in ipairs(page.pieces or {}) do
        if i > 8 then break end
        out[#out + 1] = p
    end
    return out
end
