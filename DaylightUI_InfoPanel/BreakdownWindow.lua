-- Breakdown window, opened by clicking a player's row in any meter.
-- The side list holds the meter's players; tabs show the selected player's
-- spells and their targets (or attackers, for damage taken).
--
-- Clicking a column sorts, but only with plain numbers; in combat the
-- game's order is kept. While open during a fight it follows the meter at
-- most twice a second, and says when a player's spells have to wait until
-- combat ends.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local BW = {}
ns.BreakdownWindow = BW

BW.NAME = "DaylightUIMeterDetails"
BW.W, BW.H = 640, 440
BW.SIDE = 170                 -- player list width
BW.ROW = 22
BW.BOTTOM = 52                -- footer height
BW.REFILL = 0.5               -- seconds between refills while the meter redraws
BW.WAIT_TEXT = DUI.L["Available after combat"]
BW.EMPTY_TEXT = DUI.L["Nothing here for this player yet."]
BW.tables, BW.waits = {}, {}

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Modes where the other side is an attacker rather than a target.
local ATTACKERS = { taken = true, avoidable = true }

-- ---------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------

local function text(b, size, justify)
    local fs = Style.Text(b, size or Style.SIZE.body, justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Positions a cell using the column header's layout ({ x, w } per column).
local function cell(b, fs, col, pad)
    fs:ClearAllPoints()
    if not col then fs:Hide() return end
    fs:Show()
    fs:SetPoint("LEFT", b, "LEFT", col.x + (pad or 0), 0)
    fs:SetWidth(math.max(1, col.w - (pad or 0)))
end

local function makePlayer(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.name = text(b)
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -4, 0)
end

local function fillPlayer(b, d)
    local src = d.src
    local file = ns.Rows.CLASS_ICON[not isSecret(src.classFilename) and src.classFilename or ""]
    b.icon:SetTexture(file)
    b.icon:SetShown(file ~= nil)
    b.name:SetText(src.name)
    b.name:SetTextColor(Style.ClassTextColor(src.classFilename))
    b.picked = d.picked == true
end

local function makeSpell(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    Style.CropIcon(b.icon)
    b.name = text(b)
    b.amount = text(b, nil, "RIGHT")
    b.rate = text(b, nil, "RIGHT")
    b.share = text(b, nil, "RIGHT")
    b.extra = text(b, Style.SIZE.small, "RIGHT")
    -- Thin share bar under the name.
    b.bar = DUI.Widgets.Bar(b, DUI.Widgets.BAR_H)
end

local function fillNumbers(b, d, cols)
    b.amount:SetText(ns.Meter.Short(d.amount))
    Style.InkText(b.amount, "VALUE")
    cell(b, b.amount, cols.amount)
    if b.rate then
        if type(d.rate) ~= "nil" then b.rate:SetText(ns.Meter.Short(d.rate)) else b.rate:SetText("") end
        Style.InkText(b.rate, "LABEL")
        cell(b, b.rate, cols.rate)
    end
    b.share:SetText(d.share and (d.share .. "%") or "")
    Style.InkText(b.share, "pop")
    cell(b, b.share, cols.share)
    b.bar:ClearAllPoints()
    local nc = cols.name
    if nc then
        b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", nc.x + 22, 2)
        b.bar:SetWidth(math.max(1, nc.w - 24))
    end
    b.bar:SetMinMaxValues(0, 1)
    b.bar:SetValue(d.ratio or 0)
    if d.class then
        DUI.Widgets.BarFrom(b.bar, Style.ClassColor(d.class))
    else
        DUI.Widgets.BarAccent(b.bar)
    end
end

local function fillSpell(b, d, cols)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", b, "LEFT", (cols.name and cols.name.x or 0) + 2, 1)
    b.icon:SetTexture(d.icon)
    b.icon:SetShown(d.icon ~= nil)
    b.name:SetText(d.name)
    Style.InkText(b.name, "TEXT")
    cell(b, b.name, cols.name, 22)
    fillNumbers(b, d, cols)
    if d.tag then
        b.extra:SetText(d.tag)
        Style.InkText(b.extra, d.tagInk or "WARN")
    elseif type(d.overkill) ~= "nil" then
        b.extra:SetText(ns.Meter.Short(d.overkill))
        Style.InkText(b.extra, "LABEL")
    else
        b.extra:SetText("")
    end
    cell(b, b.extra, cols.extra)
end

local function makeTarget(b)
    b.name = text(b)
    b.amount = text(b, nil, "RIGHT")
    b.share = text(b, nil, "RIGHT")
    b.bar = DUI.Widgets.Bar(b, DUI.Widgets.BAR_H)
end

local function fillTarget(b, d, cols)
    b.name:SetText(d.name)
    if d.class and d.class ~= "" then b.name:SetTextColor(Style.ClassTextColor(d.class)) else Style.InkText(b.name, "TEXT") end
    cell(b, b.name, cols.name, 4)
    fillNumbers(b, d, cols)
end

-- ---------------------------------------------------------------------
-- Tab contents
-- ---------------------------------------------------------------------

-- Fills in shares and bar ratios. Returns false if any amount is secret.
local function shares(list)
    local total, top = 0, 0
    for _, d in ipairs(list) do
        if type(d.amount) ~= "number" or isSecret(d.amount) then return false end
        total = total + d.amount
        if d.amount > top then top = d.amount end
    end
    for _, d in ipairs(list) do
        d.share = total > 0 and math.floor(100 * d.amount / total + 0.5) or nil
        d.ratio = top > 0 and d.amount / top or 0
    end
    return true
end

-- Sorts by column (sort = { id, desc }). Secret lists keep the game's order.
local function sorted(list, sort, plain)
    if not plain or not sort then return list end
    local id, desc = sort.id, sort.desc
    local key = (id == "share" or id == "extra") and "amount" or id
    if id == "extra" then key = "overkill" end
    table.sort(list, function(a, b)
        local x, y = a[key], b[key]
        if type(x) == "string" and type(y) == "string" then
            if desc then return x > y end
            return x < y
        end
        x, y = tonumber(x) or 0, tonumber(y) or 0
        if desc then return x > y end
        return x < y
    end)
    return list
end

BW.sort = { spells = { id = "amount", desc = true }, targets = { id = "amount", desc = true }, death = { id = "time" } }
BW.NO_DEATH = DUI.L["No death in this fight."]

-- Death tab: the last hits and heals before the death, oldest first.
local function makeDeath(b)
    b.time = text(b, Style.SIZE.small, "RIGHT")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    Style.CropIcon(b.icon)
    b.name = text(b)
    b.source = text(b, Style.SIZE.small)
    b.amount = text(b, nil, "RIGHT")
    b.hp = DUI.Widgets.Bar(b, DUI.Widgets.BAR_H)
    b.hpText = text(b, Style.SIZE.small, "RIGHT")
    b.extra = text(b, Style.SIZE.small, "RIGHT")
end

local function fillDeath(b, d, cols)
    b.time:SetText(string.format("-%.1fs", d.ago or 0))
    Style.InkText(b.time, "LABEL")
    cell(b, b.time, cols.time)
    local nc = cols.name
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", b, "LEFT", (nc and nc.x or 0) + 2, 0)
    b.icon:SetTexture(d.icon)
    b.icon:SetShown(d.icon ~= nil)
    b.name:SetText(d.spell)
    Style.InkText(b.name, "TEXT")
    cell(b, b.name, nc, 22)
    b.name:SetWidth(0)
    b.source:ClearAllPoints()
    b.source:SetPoint("LEFT", b.name, "RIGHT", 6, 0)
    b.source:SetText(d.source or "")
    Style.InkText(b.source, "LABEL")
    if d.heal then
        b.amount:SetText("+" .. ns.Meter.Short(d.amount))
        Style.InkText(b.amount, "GOOD")
    else
        b.amount:SetText("-" .. ns.Meter.Short(d.amount))
        Style.InkText(b.amount, "DAMAGE")
    end
    cell(b, b.amount, cols.amount)
    local hc = cols.hp
    b.hp:ClearAllPoints()
    b.hp:SetShown(d.hp ~= nil and hc ~= nil)
    if hc and d.hp then
        b.hp:SetPoint("LEFT", b, "LEFT", hc.x, 0)
        b.hp:SetWidth(math.max(1, hc.w - 34))
        b.hp:SetMinMaxValues(0, 1)
        b.hp:SetValue(d.hp)
        local ink = d.hp <= 0.25 and Style.INK.BAD or d.hp <= 0.5 and Style.INK.WARN or Style.INK.GOOD
        DUI.Widgets.BarFrom(b.hp, ink[1], ink[2], ink[3])
        b.hpText:SetText(math.floor(d.hp * 100 + 0.5) .. "%")
        Style.InkText(b.hpText, "LABEL")
        b.hpText:ClearAllPoints()
        b.hpText:SetPoint("RIGHT", b, "LEFT", hc.x + hc.w, 0)
        b.hpText:Show()
    else
        b.hpText:Hide()
    end
    if d.killing then
        b.extra:SetText(d.overkill and string.format(L["Overkill %s"], ns.Meter.Short(d.overkill)) or L["Killing blow"])
        Style.InkText(b.extra, "BAD")
        -- Shine once per death, not on every refill.
        if BW.shone ~= BW.recap then
            BW.shone = BW.recap
            DUI.Win.Parts.Shine(b)
        end
    else
        b.extra:SetText("")
    end
    cell(b, b.extra, cols.extra)
end

local function deathList()
    local src = BW.src
    local id = src and src.deathRecapID
    if type(id) ~= "number" or issecretvalue and issecretvalue(id) or id <= 0 then return nil, BW.NO_DEATH end
    local log, why = ns.DeathLog.Read(id)
    if not log then return nil, why or BW.NO_DEATH end
    return log.events
end

local function spellsList()
    local spells, why = ns.Breakdown.Spells(BW.src, BW.meter)
    if not spells then
        -- Deaths mode with no death, or no data from the game yet.
        return nil, why or (BW.meter.Mode().key == "deaths" and BW.NO_DEATH or BW.EMPTY_TEXT)
    end
    local md = BW.meter.Mode()
    for _, s in ipairs(spells) do
        if md.key == "taken" or md.key == "avoidable" then
            s.overkill = nil
            if not isSecret(s.deadly) and s.deadly == true then s.tag, s.tagInk = L["Deadly"], "BAD"
            elseif not isSecret(s.avoidable) and s.avoidable == true then s.tag, s.tagInk = L["Avoidable"], "WARN" end
        elseif not (md.key == "damage" or md.key == "dps") then
            s.overkill = nil
        end
    end
    local plain = shares(spells)
    return sorted(spells, BW.sort.spells, plain)
end

local function targetsList()
    local list, why = ns.Breakdown.Targets(BW.src, BW.meter)
    if not list then return nil, why end
    return sorted(list, BW.sort.targets, shares(list))
end

-- ---------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------

local function db() return ns.module and ns.module.db and ns.module.db.breakdownWin end

local function place(f)
    local s = BW.spot and BW.spot.Get()
    if s then return DUI.Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -340, -160)
end

local function rowsOf(list)
    local out = {}
    for i, d in ipairs(list or {}) do d.kind = "line"; out[i] = d end
    return out
end

local function fillPage(id)
    local t = BW.tables[id]
    if not (t and BW.src) then return end
    local list, why
    if id == "spells" then list, why = spellsList()
    elseif id == "death" then list, why = deathList()
    else list, why = targetsList() end
    t:SetRows(rowsOf(list), true)
    local w = BW.waits[id]
    w:SetText(list and #list == 0 and BW.EMPTY_TEXT or (why or ""))
    w:SetShown(not list or #list == 0)
end

local function buildPage(id, cols, make, fill)
    return function(page)
        local holder = CreateFrame("Frame", nil, page)
        holder:SetPoint("TOPLEFT", page, "TOPLEFT", BW.SIDE, 0)
        holder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
        holder:SetSize(BW.W - BW.SIDE, BW.H - DUI.Win.HEADER - 1)   -- size before the first layout
        local t = DUI.Win.Parts.Table(holder, {
            head = cols, rowHeight = { line = BW.ROW }, bottom = BW.BOTTOM,
            make = { line = make }, fill = { line = fill },
            onSort = function(col, desc)
                BW.sort[id] = { id = col, desc = desc }
                fillPage(id)
            end,
        })
        t.head:SetSort(BW.sort[id].id, BW.sort[id].desc)
        BW.tables[id] = t
        local w = Style.Text(holder, Style.SIZE.body, "CENTER")
        w:SetPoint("TOP", t.view, "TOP", 0, -24)
        w:SetPoint("LEFT", t.view, "LEFT", 12, 0)
        w:SetPoint("RIGHT", t.view, "RIGHT", -12, 0)
        Style.InkText(w, "LABEL")
        w:Hide()
        BW.waits[id] = w
        local foot = DUI.Win.Parts.Footer(page)
        foot:Set({
            { text = L["Report"], primary = true, onClick = function()
                if BW.meter and BW.src then ns.Report.Toggle(BW.meter, nil, BW.src) end
            end },
            { text = CLOSE or L["Close"], onClick = function() BW.Close() end },
        })
    end
end

local SPELL_COLS = {
    { id = "name", text = "Spell", fill = true, sort = true },
    { id = "amount", text = "Amount", width = 64, justify = "RIGHT", sort = true },
    { id = "rate", text = "Per second", width = 70, justify = "RIGHT", sort = true },
    { id = "share", text = "%", width = 40, justify = "RIGHT", sort = true },
    { id = "extra", text = "Overkill", width = 64, justify = "RIGHT", sort = true },
}
local TARGET_COLS = {
    { id = "name", text = "Name", fill = true, sort = true },
    { id = "amount", text = "Amount", width = 70, justify = "RIGHT", sort = true },
    { id = "share", text = "%", width = 44, justify = "RIGHT", sort = true },
}
local DEATH_COLS = {
    { id = "time", text = "When", width = 50, justify = "RIGHT" },
    { id = "name", text = "What", fill = true },
    { id = "amount", text = "Amount", width = 64, justify = "RIGHT" },
    { id = "hp", text = "Health", width = 96 },
    { id = "extra", text = "", width = 96, justify = "RIGHT" },
}
local function translated(cols)
    local out = {}
    for i, c in ipairs(cols) do
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        copy.text = (c.text == "%" or c.text == "") and c.text or L[c.text]
        out[i] = copy
    end
    return out
end

function BW.Build()
    if BW.frame then return BW.frame end
    local Win = DUI.Win
    local f = Win.New({ name = BW.NAME, back = "InfoPanel", w = BW.W, h = BW.H })
    BW.frame = f
    f.onClose = function() BW.Close() end
    BW.spot = Win.Spot(f, db, place)
    -- Player list, shared by every tab.
    local side = CreateFrame("Frame", nil, f.host)
    side:SetPoint("TOPLEFT", f.host, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", f.host, "BOTTOMLEFT", 0, 0)
    side:SetSize(BW.SIDE, BW.H - Win.HEADER - 1)
    side:SetFrameLevel(f.host:GetFrameLevel() + 5)
    BW.side = DUI.Win.Parts.Table(side, {
        head = { { id = "name", text = L["Players"], fill = true } }, rowHeight = { line = 20 }, bottom = BW.BOTTOM,
        make = { line = makePlayer }, fill = { line = fillPlayer },
        onClick = function(_, d) BW.Pick(d.src) end,
    })
    Win.AddPage(f, "spells", { Build = buildPage("spells", translated(SPELL_COLS), makeSpell, fillSpell),
                               Fill = function() fillPage("spells") end })
    Win.AddPage(f, "targets", { Build = buildPage("targets", translated(TARGET_COLS), makeTarget, fillTarget),
                                Fill = function() fillPage("targets") end })
    Win.AddPage(f, "death", { Build = buildPage("death", translated(DEATH_COLS), makeDeath, fillDeath),
                              Fill = function() fillPage("death") end })
    Win.Build(f, "spells")
    Win.Build(f, "targets")
    Win.Build(f, "death")
    Win.Tabs(f, { { id = "spells", text = L["Spells"] }, { id = "targets", text = L["Targets"] },
                  { id = "death", text = L["Death"] } }, BW.Show)
    Win.Drag(f, { save = BW.spot.Save, reset = BW.spot.Reset })
    Win.Keys(f, function(key)
        if key == "ESCAPE" then BW.Close() return true end
    end)
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = BW.spot.Reset   -- /dui reset
    return f
end

-- The selection survives refills and the end of combat by remembering the
-- plain GUID from Meter.GuidOf. A source matches if its GUID resolves the same.
local function isPicked(s)
    if s == BW.src then return true end
    -- In deaths mode each death is its own row, matched by recap ID.
    if BW.recap ~= nil then
        local r = s.deathRecapID
        return not issecretvalue(r) and r == BW.recap
    end
    local g, c = ns.Meter.GuidOf(s)
    if BW.guid ~= nil then return g == BW.guid end
    if BW.creature ~= nil then return c == BW.creature end
    return false
end
local function remember(src)
    BW.src = src
    BW.guid, BW.creature = ns.Meter.GuidOf(src)
    local r = src and src.deathRecapID
    BW.recap = (type(r) == "number" and not issecretvalue(r) and r > 0) and r or nil
    BW.shone = nil
end

-- Refreshes the player list and header from the meter.
local function fillSide()
    local sources = BW.meter and BW.meter.Sources() or nil
    local list = {}
    local picked
    for i, s in ipairs(type(sources) == "table" and sources or {}) do
        local mine = isPicked(s)
        if mine and not picked then
            picked = i
            BW.src = s
        end
        list[i] = { kind = "line", src = s, picked = mine }
    end
    BW.side:SetRows(list, true)
    if picked then BW.side:Pick(picked) end
    local src = BW.src
    local md = BW.meter.Mode()
    DUI.Win.SetTitle(BW.frame, src.name, { Style.ClassTextColor(src.classFilename) },
        string.format(L["%s · %s"], string.upper(L[md.name]), (BW.meter.FightTitle())))
    local tab = BW.frame.tabs and BW.frame.tabs[2]
    if tab and tab.text then
        tab.text:SetText(ATTACKERS[md.key] and L["Attackers"] or L["Targets"])
    end
end

function BW.Show(id)
    local f = BW.frame
    if not f then return end
    id = id or f.current or "spells"
    DUI.Win.PickTab(f, id)
    DUI.Win.ShowPage(f, id)
end

-- Opens the window for player src of meter m (any meter window).
function BW.Open(m, src)
    local f = BW.Build()
    BW.meter = m
    remember(src)
    BW.last = nil
    fillSide()
    if not DUI.Win.IsOpen(f) then place(f) end
    -- Deaths mode opens on the Death tab.
    local tab = m.Mode().key == "deaths" and "death" or (f.current ~= "death" and f.current) or "spells"
    BW.Show(tab)
    DUI.Win.Open(f)
end

function BW.Pick(src)
    remember(src)
    BW.Refill(true)
end

-- Refills from the meter. Meter redraws call this; it runs at most every
-- BW.REFILL seconds unless forced.
function BW.Refill(force)
    local f = BW.frame
    if not (f and BW.meter and BW.src and DUI.Win.IsOpen(f)) then return end
    local now = GetTime and GetTime() or 0
    if not force and BW.last and now - BW.last < BW.REFILL then
        -- Too soon, so schedule one more. Out of combat a mode or fight
        -- change may not trigger another redraw.
        if not BW.later then
            BW.later = true
            C_Timer.After(BW.REFILL - (now - BW.last), function()
                BW.later = false
                BW.Refill()
            end)
        end
        return
    end
    BW.last = now
    fillSide()
    fillPage(f.current or "spells")
end

function BW.Changed(m)
    if BW.meter == m then BW.Refill() end
end

-- Close if the meter window it follows was removed.
function BW.MeterGone(m)
    if BW.meter == m then BW.Close() end
end

function BW.Close()
    local f = BW.frame
    if not f then return end
    DUI.Win.Shut(f)
end
