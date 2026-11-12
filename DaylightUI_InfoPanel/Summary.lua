-- Fight summary window: one row per player with damage, DPS, healing, HPS,
-- interrupts, dispels and deaths in sortable columns.
--
-- The game keeps one list per stat, and players are matched across them by
-- GUID, which must be plain. So rows are only rebuilt out of combat; during a
-- fight the last rows stay with a note saying so.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Summary = {}
ns.Summary = Summary

Summary.ROW = 20
Summary.NOTE = DUI.L["Fight on: updates when it ends."]
-- Out of a fight but the game still hides who's who (a keystone, a battleground).
Summary.HIDDEN = DUI.L["The game hides who's who here for now: it updates once it can."]
-- The columns in order: their game type, the head's label, their width.
Summary.COLUMNS = {
    { id = "damage", type = "DamageDone", text = "Damage", width = 56 },
    { id = "dps", type = "Dps", text = "DPS", width = 46, rate = true },
    { id = "healing", type = "HealingDone", text = "Healing", width = 56 },
    { id = "hps", type = "Hps", text = "HPS", width = 46, rate = true },
    { id = "interrupts", type = "Interrupts", text = "Int.", width = 34 },
    { id = "dispels", type = "Dispels", text = "Disp.", width = 38 },
    { id = "deaths", type = "Deaths", text = "Deaths", width = 44, count = true },
}

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function plain(v) return type(v) ~= "nil" and not isSecret(v) end

-- One kind's list for the window's fight: the game's (or the sample's).
local function listOf(s, col)
    if s.Sample() then
        local key = col.id == "damage" and "damage" or col.id == "healing" and "healing" or col.id
        return ns.Meter.SampleFor(key)
    end
    local E = Enum and Enum.DamageMeterType
    local mt = E and E[col.type]
    if mt == nil or not C_DamageMeter then return nil end
    local ok, sess
    if s.fight then
        ok, sess = pcall(C_DamageMeter.GetCombatSessionFromID or error, s.fight, mt)
    else
        local ST = Enum.DamageMeterSessionType
        local st = s.cfg.session == "overall" and ST.Overall or ST.Current
        ok, sess = pcall(C_DamageMeter.GetCombatSessionFromType or error, st, mt)
    end
    if ok and type(sess) == "table" then return sess.combatSources end
end

-- Everyone across the lists, by GUID (by name in samples): nil when any
-- GUID is secret (a fight).
function Summary.Collect(s)
    local byWho, out = {}, {}
    for _, col in ipairs(Summary.COLUMNS) do
        if s.cfg.columns == nil or s.cfg.columns[col.id] ~= false then
            local list = listOf(s, col)
            for _, src in ipairs(type(list) == "table" and list or {}) do
                local who = s.Sample() and src.name or src.sourceGUID
                if isSecret(who) or isSecret(src.name) then return nil end
                if type(who) == "string" then
                    local row = byWho[who]
                    if not row then
                        row = { kind = "line", src = src, name = src.name, class = src.classFilename }
                        byWho[who] = row
                        out[#out + 1] = row
                    end
                    local v
                    if col.count then v = (row[col.id] or 0) + 1
                    elseif col.rate then v = src.amountPerSecond
                    else v = src.totalAmount end
                    if isSecret(v) then return nil end
                    if col.id == "damage" then row.src = src end   -- the breakdown opens on their damage
                    row[col.id] = v
                end
            end
        end
    end
    return out
end

local function sortRows(s, rows)
    local key, desc = s.cfg.sort or "damage", s.cfg.sortDesc ~= false
    table.sort(rows, function(a, b)
        if key == "name" then
            local x, y = tostring(a.name), tostring(b.name)
            if desc then return x > y end
            return x < y
        end
        -- Nothing in the column: at the bottom, whichever way it's sorted.
        local x, y = tonumber(a[key]), tonumber(b[key])
        if x == nil or y == nil then
            if x == y then return tostring(a.name) < tostring(b.name) end
            return y == nil
        end
        if x == y then return tostring(a.name) < tostring(b.name) end
        if desc then return x > y end
        return x < y
    end)
end

-- The columns shown (cfg.columns), the name first.
local function headCols(cfg)
    local cols = { { id = "name", text = L["Name"], fill = true, sort = true } }
    for _, c in ipairs(Summary.COLUMNS) do
        if cfg.columns == nil or cfg.columns[c.id] ~= false then
            cols[#cols + 1] = { id = c.id, text = L[c.text], width = c.width, justify = "RIGHT", sort = true }
        end
    end
    return cols
end

local function makeRow(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(14, 14)
    b.cells = {}
    b.cells.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.cells.name:SetWordWrap(false)
    for _, c in ipairs(Summary.COLUMNS) do
        b.cells[c.id] = Style.Text(b, Style.SIZE.body, "RIGHT")
    end
end

local function fillRow(b, d, cols, size)
    local nc = cols.name
    b.icon:ClearAllPoints()
    b.icon:SetPoint("LEFT", b, "LEFT", (nc and nc.x or 0) + 2, 0)
    local file = ns.Rows.CLASS_ICON[type(d.class) == "string" and d.class or ""]
    b.icon:SetTexture(file)
    b.icon:SetShown(file ~= nil)
    local name = b.cells.name
    if size and b.size ~= size then
        b.size = size
        for _, fs in pairs(b.cells) do Style.SetTextSize(fs, size) end
    end
    name:SetText(d.name)
    name:SetTextColor(Style.ClassTextColor(d.class))
    name:ClearAllPoints()
    if nc then
        name:SetPoint("LEFT", b, "LEFT", nc.x + 20, 0)
        name:SetWidth(math.max(1, nc.w - 20))
    end
    for _, c in ipairs(Summary.COLUMNS) do
        local fs, col = b.cells[c.id], cols[c.id]
        fs:ClearAllPoints()
        if col then
            fs:Show()
            fs:SetPoint("LEFT", b, "LEFT", col.x, 0)
            fs:SetWidth(col.w)
            local v = d[c.id]
            fs:SetText(plain(v) and ns.Meter.Short(v) or "")
            if c.id == "deaths" then Style.InkText(fs, "BAD")
            elseif c.rate then Style.InkText(fs, "LABEL")
            else Style.InkText(fs, "pop") end
        else
            fs:Hide()
        end
    end
end

-- Creates a summary view for a MeterFrame host. Besides Draw and Apply it
-- answers what the shared ticker expects of a meter (Tick, MarkDirty, Cleared,
-- Config, ShowFight, Sample).
function Summary.New(host, part)
    local s = { host = host, rows = nil }
    local area = host.area
    s.note = Style.Text(area, Style.SIZE.small, "LEFT")
    s.note:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 4, 2)
    s.note:SetText(Summary.NOTE)
    Style.InkText(s.note, "LABEL")
    s.note:Hide()
    local dirty = true

    function s.Sample() return DUI.testMode and DUI.TestPartShown(part) or false end
    function s.Config() return s.cfg end
    function s.MarkDirty() dirty = true end
    function s.Tick(fight)
        if dirty and not s.dead then s.Draw() end
    end
    function s.Cleared()
        s.fight = nil
        s.last = nil
        dirty = true
    end
    function s.ShowFight(id)
        if s.fight == id then return end
        s.fight = id
        dirty = true
        s.Draw()
    end

    local function build(cfg)
        if s.table then
            -- The columns changed: the head is made again over the same rows.
            s.table.head:Hide()
        end
        s.colsKey = nil
        local t = DUI.Win.Parts.Table(area, {
            head = headCols(cfg), rowHeight = { line = tonumber(cfg.rowHeight) or Summary.ROW }, top = 2, bottom = 16,
            make = { line = makeRow },
            fill = { line = function(b, d, cols) fillRow(b, d, cols, tonumber(s.cfg and s.cfg.textSize)) end },
            onSort = function(id, desc)
                DUI:Set("InfoPanel", ns.Windows.Path(host.id) .. ".sort", id)
                DUI:Set("InfoPanel", ns.Windows.Path(host.id) .. ".sortDesc", desc)
                s.cfg.sort, s.cfg.sortDesc = id, desc
                if s.last then
                    sortRows(s, s.last)
                    s.table:SetRows(s.last, true)
                end
            end,
            onClick = function(_, d)
                if ns.BreakdownWindow and d.src then ns.BreakdownWindow.Open(ns.Meter, d.src) end
            end,
        })
        if s.table then s.table.view:Hide() end
        s.table = t
    end

    function s.Apply(cfg)
        s.cfg = cfg
        local key = {}
        for _, c in ipairs(Summary.COLUMNS) do key[#key + 1] = (cfg.columns == nil or cfg.columns[c.id] ~= false) and "1" or "0" end
        key[#key + 1] = tostring(cfg.rowHeight)   -- (the row height is the table's own)
        key = table.concat(key)
        if key ~= s.colsKey then
            build(cfg)
            s.colsKey = key
        end
        s.table.head:SetSort(cfg.sort or "damage", cfg.sortDesc ~= false)
        dirty = true
        s.Draw()
    end

    function s.Draw()
        dirty = false
        if not (s.cfg and s.table) or s.dead or not area:IsVisible() then return end
        local fight = InCombatLockdown and InCombatLockdown() or false
        local rows = not fight and Summary.Collect(s) or nil
        -- Why there are no fresh rows: a fight on, or the game hiding who's who.
        s.note:SetText(fight and Summary.NOTE or Summary.HIDDEN)
        s.note:SetShown(rows == nil and (s.last ~= nil or not fight))
        if rows then
            sortRows(s, rows)
            s.last = rows
            s.table:SetRows(rows, true)
        elseif not s.last then
            s.table:SetRows({}, true)
        end
    end

    return s
end
