-- Search results page. Matching settings are grouped into a card per source
-- page and card, headed "Section › Page · Card". Each result is the setting's
-- real row, so changes apply right away. Clicking a heading jumps to that page.
-- Rows are built on first use and reused.

local _, DUI = ...
local W, Options, Theme = DUI.Widgets, DUI.Options, DUI.OptionsTheme
local SIZE = DUI.Style.SIZE
local C = W.COLORS
local L = DUI.L
local T = Options.Text

local Results = {}
DUI.OptionsResults = Results

Results.MAX = 60          -- rows shown at most; past that, keep typing
Results.HEADING = 34      -- card heading height, down to its first row

local function sectionLabel(page, sections)
    for _, s in ipairs(sections or Options.Sections()) do
        if s.id == page.section then return s.label end
    end
    return ""
end

-- "Unit Frames › Raid", or just the page when it has the section's name.
-- sections is Options.Sections(), read once by the caller for the whole fill.
function Results.Where(page, sections)
    local section = sectionLabel(page, sections)
    if section == "" or section == page.label then return T(page.label) end
    return T(section) .. " › " .. T(page.label)
end

-- Hits near the current page come first: that page, then the rest of its
-- section, then everything else, each in window order.
function Results.Near(hits, here)
    if not here then return hits end
    local out = {}
    local function take(match)
        for _, hit in ipairs(hits) do
            if match(hit.page) then out[#out + 1] = hit end
        end
    end
    take(function(p) return p.id == here.id end)
    take(function(p) return p.id ~= here.id and p.section == here.section end)
    take(function(p) return p.section ~= here.section end)
    return out
end

local function newBlock(res, onOpen)
    local b = CreateFrame("Frame", nil, res)
    b.bg = W.Round(b, "BACKGROUND")
    b.bg:SetAllPoints(b)
    W.Tint(b.bg, C.card)
    b.edge = W.Round(b, "BORDER", 0, true)
    b.edge:SetAllPoints(b)
    W.Tint(b.edge, C.cardEdge)
    local h = CreateFrame("Button", nil, b)
    h:SetPoint("TOPLEFT", b, "TOPLEFT", W.PAD, -10)
    h:SetPoint("TOPRIGHT", b, "TOPRIGHT", -W.PAD, -10)
    h:SetHeight(18)
    h.text = W.Font(h, W.BODY, SIZE.body, C.text)
    h.text:SetPoint("LEFT", h, "LEFT", 0, 0)
    h.card = W.Font(h, W.BODY, SIZE.small, C.dim)
    h.card:SetPoint("LEFT", h.text, "RIGHT", 8, 0)
    h:SetScript("OnClick", function(self) onOpen(self.pageId, self.keys) end)
    h:SetScript("OnEnter", function(self)
        W.TextColor(self.card, C.text)
        W.Tooltip(self, self.text:GetText(), L["Open this page at these settings."])
    end)
    h:SetScript("OnLeave", function(self)
        W.TextColor(self.card, C.dim)
        W.HideTooltip()
    end)
    b.heading = h
    return b
end

-- onOpen(pageId, keys) runs when a heading is clicked.
-- res.Fill(query, width, here, hits?) lays out the results (here's section
-- first) and returns the total match count, shown or not. Pass hits if
-- Options.Search(query) was already called. res.Refresh() re-reads values.
function Results.New(parent, onOpen)
    local res = CreateFrame("Frame", nil, parent)
    res.blocks, res.rows, res.shown = {}, {}, {}
    res.more = W.Font(res, W.BODY, SIZE.small, C.dim)
    res.more:SetWordWrap(true)

    local function block(i)
        res.blocks[i] = res.blocks[i] or newBlock(res, onOpen)
        return res.blocks[i]
    end

    -- Rows are keyed by page, card and item because one item table can sit
    -- on two pages (Quick actions on Home and Layout).
    local function rowFor(hit, b)
        local key = tostring(hit.page.id) .. "|" .. tostring(hit.group) .. "|" .. tostring(hit.item)
        local row = res.rows[key]
        if not row then
            row = W.Row(b, hit.page, hit.group, hit.item)
            res.rows[key] = row
        end
        row:SetParent(b)
        return row
    end

    function res.Fill(query, width, here, found)
        for _, row in pairs(res.rows) do row:Hide() end
        for _, b in ipairs(res.blocks) do b:Hide() end
        res.shown = {}
        local hits = Results.Near(found or Options.Search(query), here)
        local sections = Options.Sections()
        -- A card per run of results from the same page and card.
        local groups = {}
        for i = 1, math.min(#hits, Results.MAX) do
            local hit = hits[i]
            local last = groups[#groups]
            if not last or last.page ~= hit.page or last.group ~= hit.group then
                last = { page = hit.page, group = hit.group, hits = {} }
                groups[#groups + 1] = last
            end
            last.hits[#last.hits + 1] = hit
        end
        -- Fewer blocks than columns: stretch them so no column sits empty.
        local n = math.max(1, math.min(W.Columns(width), #groups))
        local colW = math.floor((width - (n - 1) * W.CARD_GAP) / n)
        local heights = {}
        for c = 1, n do heights[c] = 0 end
        for i, g in ipairs(groups) do
            local b = block(i)
            local col = 1
            for c = 2, n do
                if heights[c] < heights[col] then col = c end
            end
            b:SetWidth(colW)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", res, "TOPLEFT", (col - 1) * (colW + W.CARD_GAP), -heights[col])
            local h = b.heading
            h.text:SetText(Results.Where(g.page, sections))
            W.TextColor(h.text, Theme.Section(g.page.section).color)
            h.card:SetText(g.group.bare and "" or ("· " .. T(g.group.label or "")))
            h.pageId, h.keys = g.page.id, {}
            local y = Results.HEADING
            for k, hit in ipairs(g.hits) do
                local row = rowFor(hit, b)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -y)
                row.line:SetShown(k > 1)
                row.Refresh()
                row.Measure()
                row:Show()
                y = y + row:GetHeight()
                if hit.item.key then h.keys[#h.keys + 1] = hit.item.key end
                res.shown[#res.shown + 1] = row
            end
            b:SetHeight(y + 6)
            b:Show()
            heights[col] = heights[col] + y + 6 + W.CARD_GAP
        end
        local bottom = 0
        for c = 1, n do bottom = math.max(bottom, heights[c]) end
        res.more:ClearAllPoints()
        res.more:SetPoint("TOPLEFT", res, "TOPLEFT", W.PAD, -bottom)
        res.more:SetWidth(width - 2 * W.PAD)
        if #hits > Results.MAX then
            res.more:SetText(string.format(L["And %d more: keep typing to narrow it down."], #hits - Results.MAX))
            res.more:Show()
            bottom = bottom + 24
        else
            res.more:Hide()
        end
        res:SetSize(width, math.max(1, bottom))
        return #hits
    end

    function res.Refresh()
        for _, row in ipairs(res.shown) do row.Refresh() end
    end

    function res.Row(key)
        for _, row in ipairs(res.shown) do
            if row.item.key == key then return row end
        end
    end
    return res
end
