-- Ledger page: gold made through the mail and the auction house. Left: range chips
-- (session, 7 days, 30 days, all time), the net total counting up to its value (good or
-- damage color), days as columns (W.DayBars), and where gold came from and went (a
-- W.Bar each, gold in, soft red out). Right: by item (bought vs sold, profit) and the
-- latest entries. Reads ns.Ledger and repaints on each new entry. While DaylightMogul
-- keeps the books (API 1.2+ and Ledger.Owns()), reads Mogul's ledger instead
-- (Page.Source) and also repaints on its LedgerChanged. The built-in ledger keeps
-- recording either way, so there's no gap if Mogul is removed.

local _, DUI = ...
DUI.Mail = DUI.Mail or {}
local ns = DUI.Mail
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Page = {}
ns.LedgerPage = Page

Page.LEFT_W = 300
Page.EDGE = 16
Page.CHIPS_Y = 12
Page.ROW = 24            -- came-in / went-out row: label, value, thin bar
Page.ITEMS = 6           -- items in the "by item" list
Page.LATEST = 40         -- entries shown
Page.RANGES = { "session", "week", "month", "all" }
Page.IN = { "sales", "players" }
Page.OUT = { "buys", "cuts", "deposits", "postage", "sent", "cod" }

Page.range = "week"

local function W() return DUI.Widgets end

-- Data source: DaylightMogul's ledger when it keeps the books, else the built-in one

-- DaylightMogul's public API when it's 1.2 or later (the first with a ledger), else
-- nil. Every call is guarded, so a missing, older or broken Mogul leaves the page on
-- the built-in ledger.
local function mogulAPI()
    local mog = _G.DaylightMogul
    local api = type(mog) == "table" and mog.API
    local v = type(api) == "table" and api.version
    if type(v) ~= "table" or type(v[1]) ~= "number" or type(v[2]) ~= "number" then return nil end
    if v[1] < 1 or (v[1] == 1 and v[2] < 2) then return nil end
    return api
end

-- The ledger to read: Mogul's API.Ledger while it claims the books (it has Range,
-- Recent and ItemID), else ns.Ledger.
function Page.Source()
    local api = mogulAPI()
    local led = api and api.Ledger
    if type(led) ~= "table" or type(led.Owns) ~= "function" or type(led.Range) ~= "function"
        or type(led.Recent) ~= "function" or type(led.ItemID) ~= "function" then
        return ns.Ledger
    end
    local ok, owns = pcall(led.Owns)
    if ok and owns == true then return led end
    return ns.Ledger
end

-- One read from the source, plus which source answered. A Mogul read that errors or
-- returns no table falls back to the built-in ledger.
local function read(src, what, ...)
    if src ~= ns.Ledger then
        local ok, r = pcall(src[what], ...)
        if ok and type(r) == "table" then return r, src end
    end
    return ns.Ledger[what](...), ns.Ledger
end

-- Item ID by name: the source's, else the built-in one.
function Page.ItemID(name)
    local src = Page.Source()
    if src ~= ns.Ledger then
        local ok, id = pcall(src.ItemID, name)
        if ok and type(id) == "number" then return id end
    end
    return ns.Ledger.ItemID(name)
end

-- Repaint on Mogul's LedgerChanged. Registered once, from the first build or paint that
-- finds a Mogul offering it (Mogul loads after this addon, so it may not exist yet at
-- file load).
local mogulHooked = false
local function hookMogul()
    if mogulHooked then return end
    local api = mogulAPI()
    if not (api and type(api.On) == "function") then return end
    mogulHooked = true
    pcall(api.On, "LedgerChanged", function()
        local page = Page.page
        if page and page:IsVisible() then Page.Render(page) end
    end)
end

-- Item icon and the game's tooltip, by the ID the ledger saved.
function Page.Icon(name)
    local id = Page.ItemID(name)
    if not id then return nil end
    local icon = C_Item and C_Item.GetItemIconByID and select(2, pcall(C_Item.GetItemIconByID, id))
    return icon
end

function Page.ItemTip(name, extra)
    return function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        local id = Page.ItemID(name)
        if id and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(id)
        else
            DUI.Tips.Clear()
            DUI.Tips.Title(name)
            if extra then extra() end
            DUI.Tips.Flush(GameTooltip)
        end
        GameTooltip:Show()
    end
end
local function hex(c) return Win.Parts.Hex(c) end
local function money(c) return DUI.MoneyString(math.abs(c)) end

function Page.KindName(kind)
    local names = { sales = L["Auction sales"], players = L["From players"], buys = L["Auction buys"],
        cuts = L["Auction house cuts"], deposits = L["Deposits"], postage = L["Postage"], sent = L["Gold you sent"],
        cod = L["Cash on delivery"] }
    return names[kind] or kind
end

local function rangeName(id)
    if id == "session" then return L["This session"] end
    if id == "week" then return L["7 days"] end
    if id == "month" then return L["30 days"] end
    return L["All time"]
end

-- "today", "yesterday", "3 days ago"
local function ago(t)
    local days = math.floor((time() - (t or time())) / 86400)
    if date("%Y-%m-%d", t) == date("%Y-%m-%d") then return L["today"] end
    if days <= 1 then return L["yesterday"] end
    return string.format(L["%d days ago"], days)
end

-- One recent entry as a line: what, where, when, and the signed gold.
function Page.EntryLine(e)
    local item = e.item and (e.count and e.count > 1 and string.format(L["%s x%d"], e.item, e.count) or e.item)
    local text, where
    if e.kind == "sales" then text, where = string.format(L["Sold: %s"], item or "?"), L["Auction house"]
    elseif e.kind == "buys" then text, where = string.format(L["Bought: %s"], item or "?"), L["Auction house"]
    elseif e.kind == "deposits" then text, where = L["Deposit"], L["Auction house"]
    elseif e.kind == "players" then text, where = string.format(L["From %s"], e.who or "?"), L["Letter"]
    elseif e.kind == "postage" then text, where = e.who and string.format(L["Postage to %s"], e.who) or L["Postage"], L["Sent"]
    elseif e.kind == "sent" then text, where = e.who and string.format(L["Gold to %s"], e.who) or L["Gold you sent"], L["Sent"]
    elseif e.kind == "cod" then text, where = e.who and string.format(L["Cash on delivery to %s"], e.who) or L["Cash on delivery"], L["Letter"]
    else text, where = Page.KindName(e.kind), "" end
    local v = e.net or e.amount or 0
    return { text = text, color = Style.INK.TEXT, sub = where .. "  ·  " .. ago(e.t),
        icon = e.item and Page.Icon(e.item) or nil, tooltip = e.item and Page.ItemTip(e.item) or nil,
        value = (v < 0 and "-" or "+") .. money(v), valueColor = v < 0 and Style.INK.DAMAGE or Style.INK.MONEY }
end

-- Painting

local function paintNet(page, net)
    local fs = page.net
    local c = net < 0 and Style.INK.DAMAGE or Style.INK.GOOD
    fs:SetTextColor(c[1], c[2], c[3])
    local from = page.netShown or 0
    page.netShown = net
    DUI.Motion.Tween(fs, from, net, DUI.Motion.SLOW, function(v)
        v = math.floor(v + 0.5)
        fs:SetText((v < 0 and "-" or "") .. DUI.MoneyString(math.abs(v)))
    end)
end

local function paintRows(rows, kinds, r, most, out)
    for i, kind in ipairs(kinds) do
        local row = rows[i]
        local v = r.kinds[kind] or 0
        row.value:SetText(v == 0 and "-" or ((v < 0 and "-" or "") .. money(v)))
        local c = v < 0 and Style.INK.DAMAGE or v > 0 and Style.INK.MONEY or Style.INK.LABEL
        row.value:SetTextColor(c[1], c[2], c[3])
        Style.SetBarValue(row.bar, most > 0 and math.abs(v) / most or 0)
        local tint = out and Style.INK.DAMAGE or Style.INK.MONEY
        W().BarFrom(row.bar, tint[1], tint[2], tint[3])
    end
end

function Page.Render(page)
    page = page or Page.page
    if not (page and page:IsShown()) then return end
    hookMogul()
    local src = Page.Source()
    local r
    r, src = read(src, "Range", Page.range, "auction")   -- the rest of the paint uses whichever source answered
    for id, b in pairs(page.chips) do b.SetOn(id == Page.range) end
    page.rangeLabel:SetText(string.format(L["Profit, %s"], rangeName(Page.range):lower()))
    paintNet(page, r.net)
    local sub
    if Page.range == "week" or Page.range == "month" then
        local per = math.floor(r.net / #r.days)
        sub = string.format(L["%s a day on average"], hex(per < 0 and Style.INK.DAMAGE or { Style.Pop() }) .. (per < 0 and "-" or "") .. money(per) .. "|r")
    elseif Page.range == "all" then
        local since = r.since or ns.Ledger.Data().since
        sub = since and string.format(L["Since %s"], date("%Y-%m-%d", since)) or ""
    else
        sub = L["Since you logged in"]
    end
    page.netSub:SetText(sub)
    page.days.Set(r.days)
    local most = 0
    for _, k in ipairs(Page.IN) do most = math.max(most, math.abs(r.kinds[k] or 0)) end
    for _, k in ipairs(Page.OUT) do most = math.max(most, math.abs(r.kinds[k] or 0)) end
    paintRows(page.inRows, Page.IN, r, most, false)
    paintRows(page.outRows, Page.OUT, r, most, true)

    local s = page.right.stack
    s:Begin()
    s:Section(L["By item, bought and sold"])
    if #r.items == 0 then
        s:Text(L["Nothing bought or sold yet."], { color = Style.INK.LABEL })
    end
    for i = 1, math.min(Page.ITEMS, #r.items) do
        local it = r.items[i]
        local bits = {}
        if it.boughtN > 0 then bits[#bits + 1] = string.format(L["bought %d for %s"], it.boughtN, money(it.bought)) end
        if it.soldN > 0 then bits[#bits + 1] = string.format(L["sold %d for %s"], it.soldN, money(it.sold)) end
        s:Line({ icon = Page.Icon(it.name), tooltip = Page.ItemTip(it.name), text = it.name, sub = table.concat(bits, ", "),
            value = (it.net < 0 and "-" or "+") .. money(it.net), valueColor = it.net < 0 and Style.INK.DAMAGE or Style.INK.GOOD })
    end
    s:Section(L["Latest"])
    local recent = (read(src, "Recent", "auction"))
    if #recent == 0 then s:Text(L["Nothing yet."], { color = Style.INK.LABEL }) end
    for i = 1, math.min(Page.LATEST, #recent) do s:Line(Page.EntryLine(recent[i])) end
    page.right.pieces = s:End()
end

function Page.Pick(id)
    Page.range = id
    Page.Render()
end

-- Building the page

local function rows(left, kinds, y)
    local out = {}
    for i, kind in ipairs(kinds) do
        local row = CreateFrame("Frame", nil, left)
        row:SetPoint("TOPLEFT", left, "TOPLEFT", Page.EDGE, -y)
        row:SetPoint("TOPRIGHT", left, "TOPRIGHT", -Page.EDGE, -y)
        row:SetHeight(Page.ROW)
        row.label = Style.Text(row, Style.SIZE.body, "LEFT")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        Style.InkText(row.label, "TEXT")
        row.label:SetText(Page.KindName(kind))
        row.value = Style.Text(row, Style.SIZE.body, "RIGHT")
        row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        row.bar = W().Bar(row, W().BAR_H)
        row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
        out[i] = row
        y = y + Page.ROW + 4
    end
    return out, y
end

local function section(left, text, y)
    local fs = Style.Text(left, Style.SIZE.tiny, "LEFT")
    fs:SetPoint("TOPLEFT", left, "TOPLEFT", Page.EDGE, -y)
    Style.InkText(fs, "pop")
    fs:SetText(text:upper())
    return fs
end

function Page.Build(page)
    Page.page = page
    local left = CreateFrame("Frame", nil, page)
    left:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    left:SetWidth(Page.LEFT_W)
    page.left = left
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(1, 1, 1, 0.06)
    rule:SetWidth(1)
    rule:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -12)
    rule:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 12)
    local right = CreateFrame("Frame", nil, page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 1, 0)
    right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    page.right = right
    right.stack = Win.Parts.Stack(right, { top = 4, bottom = 12 })

    page.chips = {}
    local x = Page.EDGE
    for _, id in ipairs(Page.RANGES) do
        local b = W().Chip(left, rangeName(id))
        b.FitWidth()
        b:SetPoint("TOPLEFT", left, "TOPLEFT", x, -Page.CHIPS_Y)
        b:SetScript("OnClick", function() Page.Pick(id) end)
        page.chips[id] = b
        x = x + b:GetWidth() + W().CHIP_GAP
    end
    local y = Page.CHIPS_Y + W().CHIP_HEIGHT + 14
    page.rangeLabel = Style.Text(left, Style.SIZE.small, "LEFT")
    page.rangeLabel:SetPoint("TOPLEFT", left, "TOPLEFT", Page.EDGE, -y)
    Style.InkText(page.rangeLabel, "LABEL")
    y = y + 16
    page.net = Style.Text(left, Style.SIZE.title, "LEFT")
    page.net:SetPoint("TOPLEFT", left, "TOPLEFT", Page.EDGE, -y)
    y = y + 24
    page.netSub = Style.Text(left, Style.SIZE.small, "LEFT")
    page.netSub:SetPoint("TOPLEFT", left, "TOPLEFT", Page.EDGE, -y)
    Style.InkText(page.netSub, "LABEL")
    y = y + 22
    page.days = W().DayBars(left, 56, { tip = function(day)
        if not day then return end
        DUI.Tips.Title(day.day)
        local v = day.net or 0
        DUI.Tips.Line(L["Profit"], (v < 0 and "-" or "") .. money(v), v < 0 and Style.INK.DAMAGE or Style.INK.MONEY)
    end })
    page.days:SetPoint("TOPLEFT", left, "TOPLEFT", Page.EDGE, -y)
    page.days:SetPoint("TOPRIGHT", left, "TOPRIGHT", -Page.EDGE, -y)
    y = y + 56 + 16
    page.inLabel = section(left, L["Came in"], y)
    y = y + 18
    page.inRows, y = rows(left, Page.IN, y)
    y = y + 6
    page.outLabel = section(left, L["Went out"], y)
    y = y + 18
    page.outRows = rows(left, Page.OUT, y)

    -- Closed but the page still counts as shown: only paint while visible (opening fills it).
    DUI.On("MailLedger", function() if page:IsVisible() then Page.Render(page) end end)
    hookMogul()
end

function Page.Fill(page) Page.Render(page) end

function Page.Pieces()
    local page = Page.page
    if not page then return {} end
    local out = { page.days }
    for _, r in ipairs(page.inRows) do out[#out + 1] = r end
    for _, r in ipairs(page.outRows) do out[#out + 1] = r end
    for _, p in ipairs(page.right.pieces or {}) do out[#out + 1] = p end
    return out
end
