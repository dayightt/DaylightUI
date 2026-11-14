local stub = require("stub")

-- The two shared pieces DaylightMogul reads: W.Money and the why card.

T.test("controls_mogul: money_pads_and_colors", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local s = W.Money(12345, { pad = true })
    T.truthy(s:find("1|r|T", 1, true) and s:find("23|r|T", 1, true) and s:find("45|r|T", 1, true), "1g 23s 45c: " .. s)
    for _, coin in ipairs({ "coin-gold.png", "coin-silver.png", "coin-copper.png" }) do
        T.truthy(s:find(coin, 1, true), coin)
    end
    T.truthy(s:find("|cff", 1, true), "digits colored")
    local p = W.Money(105, { pad = true })
    T.truthy(p:find("1|r|T", 1, true), "silver 1")
    T.truthy(p:find("05|r|T", 1, true), "copper 05: " .. p)
    T.falsy(p:find("coin-gold", 1, true), "no gold")
    T.truthy(W.Money(10905, { pad = true }):find("09|r|T", 1, true), "silver 09 under gold")
    T.falsy(W.Money(12345, { color = false }):find("|cff", 1, true), "uncolored")
    T.eq(W.Money(stub.Secret(5)), "")
    T.eq(W.Money("x"), "")
    local zero = W.Money(0)
    T.truthy(zero:find("0|r|T", 1, true) and zero:find("coin-copper.png", 1, true), "0 = copper alone: " .. zero)
    T.falsy(zero:find("coin-gold", 1, true))
    local big = W.Money(12345678, { pad = true })   -- 1,234g 56s 78c
    T.truthy(big:find("1,234|r|T", 1, true), "thousands comma kept: " .. big)
    T.truthy(big:find("56|r|T", 1, true) and big:find("78|r|T", 1, true), "silver/copper: " .. big)
    T.falsy(W.Money(1230000, { pad = true }):find("coin-silver", 1, true), "no silver part when zero")
    -- The client draws an inline texture's x offset but leaves it out of the text's
    -- width, so right-aligned money hung its last coin past the bag's edge.
    for xoff in DUI.MoneyString(12345):gmatch("%.png:%d+:%d+:(%-?%d+):") do
        T.eq(xoff, "0", "coins carry no x offset")
    end
end)

T.test("controls_mogul: why_card_wraps_and_paints", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    local card = Parts.Why(page)
    card:SetWidth(300)
    card.text.GetStringHeight = function() return 12 end
    card:Set("short")
    local one = card:GetHeight()
    card.text.GetStringHeight = function() return 48 end
    card:Set("a much longer sentence that wraps over several lines")
    T.truthy(card:GetHeight() > one, "taller with more lines")
    T.eq(card:GetHeight(), 48 + 16)
    T.eq(card.edge:GetWidth(), 2)
    -- a solid accent colors the edge, and a new accent repaints it
    DUI:Set("general", "accent", "daylight")
    DUI.NotifyStyleChanged()
    stub.RunTimers()
    local ar, ag, ab = DUI.Style.Accent()
    local r1, g1, b1 = card.edge:GetVertexColor()
    T.near(r1, ar, 0.01, "edge is the accent"); T.near(g1, ag, 0.01); T.near(b1, ab, 0.01)
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.1, 0.9, 0.2 })
    DUI.NotifyStyleChanged()
    stub.RunTimers()
    local r2, g2, b2 = card.edge:GetVertexColor()
    local nr, ng, nb = DUI.Style.Accent()
    T.near(r2, nr, 0.01, "edge follows the new accent"); T.near(g2, ng, 0.01); T.near(b2, nb, 0.01)
    T.truthy(math.abs(r2 - r1) + math.abs(g2 - g1) + math.abs(b2 - b1) > 0.05, string.format("the edge changed color %.2f %.2f %.2f -> %.2f %.2f %.2f (accent %.2f %.2f %.2f)", r1,g1,b1,r2,g2,b2,nr,ng,nb))
end)

T.test("controls_mogul: stack_why_takes_its_place", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 500)
    local s = Parts.Stack(page)
    local function fill()
        s:Begin()
        local line = s:Line({ text = "A row" })
        local why = s:Why("Because.")
        s:End()
        return line, why
    end
    local line, why = fill()
    T.truthy(select(5, why:GetPoint(1)) < select(5, line:GetPoint(1)), "under the line")
    local line2, why2 = fill()
    T.eq(why2, why, "pooled")
    T.eq(line2, line)
    s:Begin(); s:End()
    T.eq(why:IsShown(), false)
end)

T.test("controls_mogul: why_card_does_not_blink_on_refill", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 500)
    local s = Parts.Stack(page)
    local fades = 0
    local M = DUI.Motion
    local old = M.Fade
    M.Fade = function(...) fades = fades + 1; return old(...) end
    local function fill(withWhy)
        s:Begin()
        s:Line({ text = "A row" })
        local why = withWhy and s:Why("Because.") or nil
        s:End()
        return why
    end
    local why = fill(true)
    T.eq(fades, 1, "fades in when it first appears")
    local again = fill(true)
    T.eq(again, why)
    T.eq(fades, 1, "a refill with the same card does not fade again")
    T.eq(why:GetAlpha(), 1)
    fill(false)
    fill(true)
    T.eq(fades, 2, "gone for a fill, then back: a new appearance fades")
    M.Fade = old
end)

-- ---------------------------------------------------------------------
-- W.ColumnHead and Parts.Table (the virtual list with columns)
-- ---------------------------------------------------------------------

local COLS = {
    { id = "item", text = "Item", fill = true, justify = "LEFT", sort = true },
    { id = "qty", text = "Qty", width = 50, justify = "RIGHT", sort = true },
    { id = "note", text = "Note", width = 60, justify = "LEFT" },
}

local function tweens(DUI, dt)
    local d = DUI.Motion.Driver()
    if d and d:GetScript("OnUpdate") then stub.RunOnUpdate(d, dt) end
end

local function color(fs) local r, g, b = fs:GetTextColor(); return { r, g, b } end
local function near3(c, d, msg)
    T.near(c[1], d[1], 0.01, msg); T.near(c[2], d[2], 0.01, msg); T.near(c[3], d[3], 0.01, msg)
end

T.test("controls_mogul: column_head_sorts_and_flips", function()
    local DUI = stub.Load()
    local W, Style = DUI.Widgets, DUI.Style
    local calls = {}
    local head = W.ColumnHead(UIParent, COLS, function(id, desc) calls[#calls + 1] = { id, desc } end)
    local at = head:Layout(400)
    T.eq(at.qty.w, 50)
    T.eq(at.note.w, 60)
    T.eq(at.item.x, 0)
    T.truthy(at.qty.x > at.item.x + at.item.w - 1 and at.note.x > at.qty.x, "left to right")
    T.eq(at.note.x + at.note.w, 400, "the columns fill the width")
    local qty = head.cells.qty
    T.eq(qty.text:GetText(), "Qty", "only the word: the arrow is art")
    T.eq(qty.arrow:GetTexture(), DUI.MEDIA .. "ui-chevron.png", "DaylightUI's chevron")
    T.falsy(qty.arrow:IsShown(), "no arrow before a sort")
    near3(color(qty.text), Style.INK.LABEL, "a label at rest is tan")
    qty:Click()
    T.eq(#calls, 1); T.eq(calls[1][1], "qty"); T.eq(calls[1][2], false)
    -- the recolor eases (FAST): partway at first, then the accent
    local accent = { Style.Accent() }
    tweens(DUI, DUI.Motion.FAST / 2)
    local mid = color(qty.text)
    local L0 = Style.INK.LABEL
    local function dist(x, y) return math.abs(x[1] - y[1]) + math.abs(x[2] - y[2]) + math.abs(x[3] - y[3]) end
    T.truthy(dist(L0, accent) > 0.05, "the test's accent differs from tan")
    T.truthy(dist(mid, accent) > 0.005 and dist(mid, L0) > 0.005, "eases into the accent, not at once")
    tweens(DUI, DUI.Motion.FAST)
    near3(color(qty.text), accent, "the sorted label is the accent")
    T.truthy(qty.arrow:IsShown(), "the chevron shows")
    T.near(qty.arrow:GetAlpha(), 1, 0.01)
    T.near(qty.arrow.__rotation or 0, math.pi, 0.001, "ascending: the chevron points up")
    local ar, ag, ab = qty.arrow:GetVertexColor()
    near3({ ar, ag, ab }, accent, "tinted with the label's color")
    qty:Click()
    tweens(DUI, DUI.Motion.FAST)
    T.eq(calls[2][1], "qty"); T.eq(calls[2][2], true, "the same column again flips it")
    T.near(qty.arrow.__rotation or 0, 0, 0.001, "descending: down")
    head.cells.item:Click()
    tweens(DUI, DUI.Motion.FAST)
    T.eq(calls[3][1], "item"); T.eq(calls[3][2], false, "a new column starts ascending")
    T.falsy(qty.arrow:IsShown(), "the old column's arrow goes")
    near3(color(qty.text), Style.INK.LABEL, "and its accent")
    head.cells.note:Click()
    T.eq(#calls, 3, "a column without sort does nothing")
    head:SetSort("qty", true)
    tweens(DUI, DUI.Motion.FAST)
    T.truthy(qty.arrow:IsShown(), "SetSort paints")
    T.eq(#calls, 3, "SetSort calls nothing")
    T.truthy(head.rule ~= nil, "a faint rule under it")
    -- motion off: a sort change paints at once
    DUI:Set("general", "motion", false)
    head:SetSort("item", false)
    near3(color(head.cells.item.text), accent, "motion off: at once")
end)

T.test("controls_mogul: column_head_hover_eases_to_value", function()
    local DUI = stub.Load()
    local W, Style = DUI.Widgets, DUI.Style
    local head = W.ColumnHead(UIParent, COLS, function() end)
    head:Layout(400)
    local qty = head.cells.qty
    qty:GetScript("OnEnter")(qty)
    tweens(DUI, DUI.Motion.FAST / 2)
    local mid = color(qty.text)
    T.truthy(mid[1] > Style.INK.LABEL[1] + 0.005 and mid[1] < Style.INK.VALUE[1] - 0.005, "partway: " .. mid[1])
    tweens(DUI, DUI.Motion.FAST)
    near3(color(qty.text), Style.INK.VALUE, "white under the mouse")
    qty:GetScript("OnLeave")(qty)
    tweens(DUI, DUI.Motion.FAST)
    near3(color(qty.text), Style.INK.LABEL, "tan again")
    local note = head.cells.note
    note:GetScript("OnEnter")(note)
    tweens(DUI, DUI.Motion.FAST)
    near3(color(note.text), Style.INK.LABEL, "a column without sort stays tan")
end)

T.test("controls_mogul: column_head_two_fills_share_the_rest", function()
    local DUI = stub.Load()
    local head = DUI.Widgets.ColumnHead(UIParent, {
        { id = "a", text = "A", fill = true }, { id = "b", text = "B", fill = true },
        { id = "c", text = "C", width = 51, justify = "RIGHT" },
    })
    local at = head:Layout(402)   -- 335 px for two fills, so one gets the odd px
    T.eq(at.c.x + at.c.w, 402, "the fixed last column ends at the edge")
    T.eq(at.b.x + at.b.w + DUI.Widgets.COLUMN_GAP, at.c.x, "the last fill takes the rounding")
    T.truthy(math.abs(at.a.w - at.b.w) <= 1, "shared evenly: " .. at.a.w .. " " .. at.b.w)
end)

local function table400(DUI, n, opts)
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(432, 500)
    local made = 0
    opts = opts or {}
    local t = Parts.Table(page, {
        head = COLS,
        rowHeight = { line = Parts.LINE, step = 26 },
        make = { line = function(row) made = made + 1; row.label = DUI.Style.Text(row, DUI.Style.SIZE.body, "LEFT") end },
        fill = { line = function(row, data, cols) row.label:SetText(data.text) end },
    })
    t.view:SetSize(400, 400)
    local list = {}
    for i = 1, n do list[i] = { kind = "line", text = "Row " .. i } end
    if opts.rows then list = opts.rows end
    t:SetRows(list)
    return t, function() return made end, list
end

T.test("controls_mogul: virtual_rows_only", function()
    local DUI = stub.Load()
    local t, made = table400(DUI, 2000)
    local line = DUI.Win.Parts.LINE
    local most = math.ceil(400 / line) + 1
    T.truthy(made() <= most, "made " .. made() .. " line frames for 2000 rows, at most " .. most)
    T.truthy(t.shown[1] ~= nil and t.shown[1].data.text == "Row 1", "row 1 at the top")
    T.truthy(t.shown[1].label:GetText() == "Row 1", "filled")
    T.eq(t.shown[40], nil, "a row far below has no frame")
    local before = made()
    t:Scroll(1e9)
    T.eq(made(), before, "scrolling to the end reuses the frames")
    local first = 2000 - math.ceil(400 / line) + 1
    for i = first, 2000 do
        T.truthy(t.shown[i] and t.shown[i]:IsShown() and t.shown[i].label:GetText() == "Row " .. i, "row " .. i .. " shows")
    end
    T.eq(t.shown[1], nil, "row 1 gave its frame back")
    local n = 0
    for _ in pairs(t.shown) do n = n + 1 end
    T.truthy(n <= most, "only the rows in view: " .. n)
    local _, max, view = t:Range()
    T.eq(view, 400); T.eq(max, 2000 * line - 400)
    -- a row's frame sits where the row is in the view
    local top = select(5, t.shown[2000]:GetPoint(1))
    T.eq(-top + line, 400, "the last row ends at the view's bottom")
end)

T.test("controls_mogul: open_glides_rows_in", function()
    local DUI = stub.Load()
    local rows = {}
    for i = 1, 6 do rows[i] = { kind = (i == 4 or i == 5) and "step" or "line", text = "R" .. i } end
    local t = table400(DUI, 0, { rows = rows })
    T.eq(t:RowHeight(4), 26)
    t:Open(3, 2)
    T.eq(t:RowHeight(4), 0, "starts closed")
    tweens(DUI, DUI.Motion.NORMAL / 2)
    local h4, h5 = t:RowHeight(4), t:RowHeight(5)
    T.truthy(h4 > 0 and h4 < 26 and h5 > 0 and h5 < 26, "partly tall: " .. h4 .. " " .. h5)
    T.truthy(t.shown[4]:GetHeight() > 0 and t.shown[4]:GetHeight() < 26, "its frame too")
    local line = DUI.Win.Parts.LINE
    local y6 = select(5, t.shown[6]:GetPoint(1))
    T.near(-y6, 3 * line + h4 + h5, 0.01, "the rows below glide")
    tweens(DUI, DUI.Motion.NORMAL)
    T.eq(t:RowHeight(4), 26); T.eq(t:RowHeight(5), 26)
    T.eq(select(5, t.shown[6]:GetPoint(1)), -(3 * line + 52), "full")
    DUI:Set("general", "motion", false)
    t:SetRows(rows)
    t:Open(3, 2)
    T.eq(t:RowHeight(4), 26, "motion off: open at once")
end)

T.test("controls_mogul: why_row_measures", function()
    local DUI = stub.Load()
    local rows = { { kind = "line", text = "A" }, { kind = "why", text = "Because it is cheap." }, { kind = "line", text = "B" } }
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(432, 500)
    local t = Parts.Table(page, {
        head = COLS,
        make = { line = function(row) row.label = DUI.Style.Text(row, DUI.Style.SIZE.body, "LEFT") end },
        fill = { line = function(row, data) row.label:SetText(data.text) end },
    })
    t.view:SetSize(400, 400)
    t.ruler.text.GetStringHeight = function() return 48 end
    t:SetRows(rows)
    T.eq(t:RowHeight(2), 48 + 2 * Parts.WHY_Y, "measured")
    local card = t.shown[2]
    T.truthy(card and card.edge ~= nil, "a why card")
    T.eq(card:GetHeight(), t:RowHeight(2), "the row is the card's height")
    T.eq(card.text:GetText(), "Because it is cheap.")
    T.eq(select(5, t.shown[3]:GetPoint(1)), -(Parts.LINE + t:RowHeight(2)), "the next row under it")
    -- pick: the accent wash on the picked line only
    t:Pick(1)
    T.truthy(t.shown[1].pick:IsShown(), "picked")
    t:Pick(3)
    T.falsy(t.shown[1].pick:IsShown(), "unpicked")
    T.truthy(t.shown[3].pick:IsShown())
end)

local function lines(n, tag)
    local list = {}
    for i = 1, n do list[i] = { kind = "line", text = (tag or "R") .. i } end
    return list
end
local function yOf(t, i) return -select(5, t.shown[i]:GetPoint(1)) end

T.test("controls_mogul: open_interrupted_lays_out_from_the_old_rows", function()
    local DUI = stub.Load()
    local t = table400(DUI, 0, { rows = lines(10) })
    t:Open(3, 2)
    tweens(DUI, DUI.Motion.NORMAL / 2)
    local line = DUI.Win.Parts.LINE
    T.truthy(t:RowHeight(4) < line, "half open")
    t:Open(5, 1)
    T.eq(t:RowHeight(4), line, "the old grow snapped to full")
    T.eq(t:RowHeight(6), 0, "the new one starts closed")
    T.eq(yOf(t, 6), 5 * line, "row 6 sits under row 5 at once (no stale tops)")
    T.eq(yOf(t, 7), 5 * line, "and row 7 under the closed row 6")
    tweens(DUI, DUI.Motion.NORMAL * 2)
    T.eq(yOf(t, 7), 6 * line)
end)

T.test("controls_mogul: close_done_order_and_setrows", function()
    local DUI = stub.Load()
    local t, _, list = table400(DUI, 0, { rows = lines(6) })
    -- a Close cut short by an Open runs its done after the Open is set up, and a
    -- done that refills ends that Open with every row full
    local doneA = 0
    t:Close(2, 1, function()
        doneA = doneA + 1
        local short = {}
        for i, r in ipairs(list) do if i ~= 3 then short[#short + 1] = r end end
        t:SetRows(short, true)
    end)
    tweens(DUI, DUI.Motion.NORMAL / 2)
    t:Open(3, 1)
    T.eq(doneA, 1, "the cut-short close's done ran once")
    T.eq(#t.rows, 5)
    T.eq(t.growing, nil, "its refill ended the open")
    local line = DUI.Win.Parts.LINE
    for i = 1, 5 do T.eq(t:RowHeight(i), line, "row " .. i .. " full") end
    tweens(DUI, DUI.Motion.NORMAL * 2)
    T.eq(doneA, 1)
    for i = 1, 5 do T.eq(yOf(t, i), (i - 1) * line) end
    -- SetRows during a Close: the new list wins and the close's done isn't called
    local doneB = 0
    t:Close(1, 1, function() doneB = doneB + 1 end)
    tweens(DUI, DUI.Motion.NORMAL / 2)
    t:SetRows(lines(4, "N"))
    tweens(DUI, DUI.Motion.NORMAL * 2)
    T.eq(doneB, 0, "SetRows drops a running close's done")
    T.eq(t:RowHeight(2), line, "the new rows full")
    T.eq(t.shown[2].alpha or t.shown[2]:GetAlpha(), 1)
end)

T.test("controls_mogul: pick_clears_on_new_rows_and_follows_on_keep", function()
    local DUI = stub.Load()
    local t, _, list = table400(DUI, 0, { rows = lines(5) })
    t:Pick(2)
    T.truthy(t.shown[2].pick:IsShown())
    t:SetRows(lines(5, "N"))
    T.eq(t.picked, nil, "a new list: no pick")
    T.falsy(t.shown[2].pick:IsShown(), "no wash on whatever sits there now")
    t:SetRows(list)
    t:Pick(2)
    local reversed = {}
    for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
    t:SetRows(reversed, true)
    T.eq(t.picked, 4, "keep: the pick follows its row (a re-sort)")
    T.truthy(t.shown[4].pick:IsShown()); T.falsy(t.shown[2].pick:IsShown())
end)

T.test("controls_mogul: mouse_row_swap_leaves_and_enters", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(432, 500)
    local log = {}
    local t = Parts.Table(page, {
        head = COLS,
        onEnter = function(row, d) log[#log + 1] = "enter " .. d.text end,
        onLeave = function(row, d) log[#log + 1] = "leave " .. d.text end,
    })
    t.view:SetSize(400, 400)
    local old = lines(5)
    t:SetRows(old)
    local b = t.shown[1]
    b.IsMouseOver = function() return true end
    local sorted = {}
    for i = #old, 1, -1 do sorted[#sorted + 1] = old[i] end
    t:SetRows(sorted, true)
    T.eq(t.shown[1], b, "the same frame, another row")
    T.eq(table.concat(log, ","), "leave R1,enter R5", "the tooltip follows: " .. table.concat(log, ","))
    t:SetRows(sorted, true)
    T.eq(#log, 2, "the same row again: nothing")
end)

-- W.Complete: suggestions under a W.Input.
local function completeBox(stub)
    local DUI = stub.Load()
    local W = DUI.Widgets
    local parent = CreateFrame("Frame", nil, UIParent)
    local box = W.Input(parent, {})
    local cursor = 0
    function box:GetCursorPosition() return cursor end
    function box:SetCursorPosition(n) cursor = n end
    local focus = true
    function box:HasFocus() return focus end
    local submitted = 0
    box:SetScript("OnEnterPressed", function() submitted = submitted + 1 end)
    local function type_(text)
        box:SetText(text)
        cursor = #text
        box:GetScript("OnTextChanged")(box, true)
    end
    local c = W.Complete(box, function(text, cur)
        if text == "perc" then
            return {
                { insert = "percent/", from = 1, to = 4, label = "percent/", note = "profit share" },
                { insert = "price/", from = 1, to = 4, label = "price/", note = "gold" },
            }
        end
    end)
    return DUI, W, box, c, type_, function() return submitted end, function() return cursor end
end

T.test("controls_mogul: complete_opens_and_fills", function()
    local DUI, W, box, c, type_, submitted, cursor = completeBox(stub)
    T.truthy(c, "W.Complete returns a control")
    type_("perc")
    stub.RunTimers()
    T.truthy(c:IsOpen(), "opens on typing")
    T.eq(#c.rows, 2)
    local label = c.rows[1].text:GetText()
    T.truthy(label:find("|cff", 1, true) and label:find("|rent/", 1, true), "typed part colored: " .. label)
    box:GetScript("OnEnterPressed")(box)
    T.eq(box:GetText(), "percent/")
    T.eq(cursor(), #"percent/", "cursor at the end of the fill")
    T.eq(submitted(), 0, "Enter filled, did not submit")
    T.falsy(c:IsOpen(), "closed after the fill")
end)

T.test("controls_mogul: keys_move_and_close", function()
    local DUI, W, box, c, type_ = completeBox(stub)
    type_("perc")
    T.eq(c.pick, 1)
    box:GetScript("OnArrowPressed")(box, "DOWN")
    T.eq(c.pick, 2, "Down picks row 2")
    box:GetScript("OnArrowPressed")(box, "DOWN")
    T.eq(c.pick, 2, "stays on the last row")
    box:GetScript("OnArrowPressed")(box, "UP")
    T.eq(c.pick, 1)
    box:GetScript("OnArrowPressed")(box, "DOWN")
    box:GetScript("OnTabPressed")(box)
    T.eq(box:GetText(), "price/", "Tab fills the picked row")
    type_("perc")
    box:GetScript("OnEscapePressed")(box)
    T.falsy(c:IsOpen(), "Esc closes")
    T.eq(box:GetText(), "perc", "text unchanged")
end)

T.test("controls_mogul: enter_with_none_open_submits", function()
    local DUI, W, box, c, type_, submitted = completeBox(stub)
    type_("zzz")
    T.falsy(c:IsOpen())
    box:GetScript("OnEnterPressed")(box)
    T.eq(submitted(), 1, "the input's own Enter ran once")
end)

T.test("controls_mogul: clicks_elsewhere_still_work", function()
    local DUI, W, box, c, type_ = completeBox(stub)
    local hits = 0
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetScript("OnClick", function() hits = hits + 1 end)
    type_("perc")
    T.falsy(c:IsMouseEnabled(), "the list frame takes no clicks of its own")
    T.eq(c:GetParent(), UIParent)
    btn:GetScript("OnClick")(btn)
    T.eq(hits, 1, "other controls work with the list open")
    c:Close()
    stub.RunTimers()
    T.falsy(c:IsShown(), "closed list gone")
    btn:GetScript("OnClick")(btn)
    T.eq(hits, 2)
    T.truthy(#c.rows <= 8)
end)

T.test("controls_mogul: complete_width_follows_scale", function()
    local DUI, W, box, c, type_ = completeBox(stub)
    local win = CreateFrame("Frame", nil, UIParent)
    win:SetScale(2)
    box:SetParent(win)
    box:SetWidth(200)
    type_("perc")
    T.eq(box:GetEffectiveScale(), 2 * (UIParent:GetEffectiveScale() or 1), "box really scaled")
    local want = 200 * box:GetEffectiveScale() / c:GetEffectiveScale()
    T.near(c:GetWidth(), want, 0.01, "list width in its own scale")
end)

T.test("controls_mogul: complete_fill_does_not_blink", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local box = W.Input(CreateFrame("Frame", nil, UIParent), {})
    local list
    -- always offers something, so a fill keeps the list open
    list = W.Complete(box, function(text) return { { insert = text .. "x", from = 1, to = #text, label = text .. "x" } } end)
    box:SetText("ab")
    box:GetScript("OnTextChanged")(box, true)
    T.truthy(list:IsOpen(), "opened")
    local fromZero = 0
    local M = DUI.Motion
    local orig = M.Fade
    M.Fade = function(r, from, to, ...) if r == list and from == 0 then fromZero = fromZero + 1 end return orig(r, from, to, ...) end
    box:GetScript("OnTabPressed")(box)   -- fills, and the list stays open
    box:GetScript("OnTabPressed")(box)
    M.Fade = orig
    T.eq(box:GetText(), "abxx")
    T.truthy(list:IsOpen(), "still open after fills")
    T.eq(fromZero, 0, "no fade from 0 while it stays open")
end)

T.test("controls_mogul: complete_reopen_mid_fade_out_stays", function()
    local DUI, W, box, c, type_ = completeBox(stub)
    type_("perc")
    c:Close()
    T.truthy(c:IsShown(), "still fading out")
    type_("perc")   -- reopens before the fade-out ends
    T.truthy(c:IsOpen())
    stub.RunTimers()   -- the old fade-out's finish
    T.truthy(c:IsShown(), "the old fade-out's finish did not hide it")
    T.eq(c:GetAlpha(), 1)
    -- and a second close right after the reopen still hides it, once
    c:Close()
    stub.RunTimers()
    T.falsy(c:IsShown(), "closed for real")
end)

T.test("controls_mogul: complete_mid_string_replaces_only_its_range", function()
    local DUI, W, box = completeBox(stub)
    local cursor = 0
    function box:GetCursorPosition() return cursor end
    function box:SetCursorPosition(n) cursor = n end
    local got
    local c = W.Complete(box, function(text, cur)
        got = cur
        return { { insert = "price/", from = 5, to = 8, label = "price/" } }
    end)
    box:SetText("a/b/perc/z")
    cursor = 8   -- after "perc"
    box:GetScript("OnTextChanged")(box, true)
    T.eq(got, 8, "suggest got the cursor, not the end")
    box:GetScript("OnEnterPressed")(box)
    T.eq(box:GetText(), "a/b/price//z", "only from..to replaced")
    T.eq(cursor, 4 + #"price/", "cursor after the insert")
end)

-- ---------------------------------------------------------------------
-- Tree rows, the menu button, the footer's beside, and the item icon (for Mogul's
-- search: the category tree, "Rarity: Uncommon+", "Buy 60" and "Buy 260" side by
-- side, results outlined in their quality)
-- ---------------------------------------------------------------------

local function stackOn(DUI)
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(250, 400)
    return DUI.Win.Parts.Stack(page)
end

T.test("controls_mogul: stack_line_right_click", function()
    local DUI = stub.Load()
    local s = stackOn(DUI)
    local clicks, rights = 0, 0
    s:Begin()
    local a = s:Line({ text = "2 x Silk Cloth", sub = "have 5 / 2", onClick = function() clicks = clicks + 1 end,
        onRightClick = function() rights = rights + 1 end })
    local b = s:Line({ text = "Fine Thread", onClick = function() clicks = clicks + 1 end })
    local c = s:Line({ text = "Later", dim = true, onRightClick = function() rights = rights + 1 end })
    s:End()
    a:Click("RightButton")
    T.eq(rights, 1); T.eq(clicks, 0, "a right-click never runs onClick")
    a:Click("LeftButton")
    T.eq(clicks, 1); T.eq(rights, 1)
    b:Click("RightButton")   -- no onRightClick, so nothing
    T.eq(clicks, 1, "nor a left click's")
    c:Click("RightButton")
    T.eq(rights, 1, "a dim line takes no click")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("controls_mogul: stack_line_key_caps_its_number", function()
    local DUI = stub.Load()
    local s = stackOn(DUI)
    s:Begin()
    local a = s:Line({ text = "First", key = "1" })
    local b = s:Line({ text = "Tenth", key = "" })     -- past 9 it keeps only the room, so the lines stay even
    local c = s:Line({ text = "Plain" })
    s:End()
    T.eq(stub.Text(a.key), "1")
    T.truthy(a.key:IsShown() and a.keyBox:IsShown(), "a key shows")
    T.falsy(b.key:IsShown(), "an empty key shows nothing")
    T.falsy(c.key:IsShown(), "no key, no cap")
    local _, _, _, ax = a.edge:GetPoint(1)
    local _, _, _, bx = b.edge:GetPoint(1)
    local _, _, _, cx = c.edge:GetPoint(1)
    T.eq(ax, bx, "the icons line up")
    T.truthy(ax > cx, "the key takes the room left of the icon")
    s:Begin()
    local again = s:Line({ text = "Reused" })          -- a line used again drops its key
    s:End()
    T.falsy(again.key:IsShown())
    local _, _, _, x = again.edge:GetPoint(1)
    T.eq(x, cx)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("controls_mogul: stack_row_tree_and_right_click", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local s = stackOn(DUI)
    local clicks, rights = 0, 0
    s:Begin()
    local a = s:Row({ text = "Armor", chevron = "open", onClick = function() clicks = clicks + 1 end,
        onRightClick = function() rights = rights + 1 end })
    local b = s:Row({ text = "Leather", depth = 1, chevron = "closed" })
    local c = s:Row({ text = "Head", depth = 2 })
    s:End()
    T.eq(select(4, a.icon:GetPoint(1)), 6)
    T.eq(select(4, b.icon:GetPoint(1)), 6 + Parts.INDENT, "one level in")
    T.eq(select(4, c.icon:GetPoint(1)), 6 + 2 * Parts.INDENT)
    T.truthy(a.chevron:IsShown()); T.eq(a.chevron.__rotation, 0, "open points down")
    T.near(b.chevron.__rotation, math.pi / 2, 0.001, "closed points right")
    T.falsy(c.chevron:IsShown(), "a leaf has none")
    near3({ a.chevron:GetVertexColor() }, DUI.Style.INK.LABEL, "tan")
    a:Click("RightButton")
    T.eq(rights, 1); T.eq(clicks, 0, "a right-click never runs onClick")
    a:Click("LeftButton")
    T.eq(clicks, 1); T.eq(rights, 1)
    c:Click("RightButton")   -- no onRightClick, so nothing
    -- the same frame shows the node shut, and it turns (FAST)
    s:Begin()
    a = s:Row({ text = "Armor", chevron = "closed" })
    s:End()
    T.truthy(a.chevron.__rotation < math.pi / 2, "turning, not jumped")
    tweens(DUI, 1)
    T.near(a.chevron.__rotation, math.pi / 2, 0.001)
end)

T.test("controls_mogul: stack_ease_glides_and_fades", function()
    local DUI = stub.Load()
    local s = stackOn(DUI)
    local function fill(open)
        s:Begin()
        s:Section("Categories")
        s:Row({ id = "armor", text = "Armor", chevron = open and "open" or "closed" })
        if open then s:Row({ id = "armor/plate", text = "Plate", depth = 1 }) end
        s:Row({ id = "weapons", text = "Weapons" })
        return s:End()
    end
    fill(false)
    local before = s:Spots()
    local fades, real = {}, DUI.Motion.Fade
    DUI.Motion.Fade = function(r, from, to, dur) fades[#fades + 1] = { r = r, from = from, dur = dur }; return real(r, from, to, dur) end
    local pieces = fill(true)
    s:Ease(before)
    local plate, weapons = pieces[3], pieces[4]
    T.eq(fades[1].r, plate, "the new row fades in")
    T.eq(fades[1].dur, DUI.Motion.NORMAL)
    local y0 = before.weapons
    local y = -select(5, weapons:GetPoint(1))
    T.eq(y, y0, "the row below starts where it was")
    tweens(DUI, DUI.Motion.NORMAL / 2)
    y = -select(5, weapons:GetPoint(1))
    T.truthy(y > y0 and y < weapons.stackY, "gliding down: " .. y)
    tweens(DUI, 1)
    T.eq(-select(5, weapons:GetPoint(1)), weapons.stackY)
    DUI.Motion.Fade = real
    -- motion off: everything at its spot
    DUI:Set("general", "motion", false)
    before = s:Spots()
    pieces = fill(false)
    s:Ease(before)
    T.eq(-select(5, pieces[3]:GetPoint(1)), pieces[3].stackY)
end)

T.test("controls_mogul: stack_ease_from_leaves_earlier_pieces_gliding", function()
    local DUI = stub.Load()
    local s = stackOn(DUI)
    s:Begin()
    s:Row({ id = "a", text = "A" })
    s:Row({ id = "b", text = "B" })
    s:End()
    local before = s:Spots()
    s:Begin()
    s:Row({ id = "new", text = "New" })
    s:Row({ id = "a", text = "A" })
    local pieces = s:End()
    s:Ease(before)
    local a = pieces[2]
    tweens(DUI, DUI.Motion.NORMAL / 2)
    local mid = -select(5, a:GetPoint(1))
    T.truthy(mid > before.a and mid < a.stackY, "A gliding down: " .. mid)
    -- a slice more (Mogul's sliced fill): only the pieces from 3 on are eased
    s:Row({ id = "b", text = "B" })
    pieces = s:End()
    local fades, real = {}, DUI.Motion.Fade
    DUI.Motion.Fade = function(r, from, to, dur) fades[#fades + 1] = r; return real(r, from, to, dur) end
    s:Ease(before, 3)
    DUI.Motion.Fade = real
    T.eq(#fades, 0, "nothing earlier fades in again")
    T.eq(-select(5, a:GetPoint(1)), mid, "A still mid-glide, not snapped to its spot")
    tweens(DUI, 1)
    T.eq(-select(5, a:GetPoint(1)), a.stackY)
    T.eq(-select(5, pieces[3]:GetPoint(1)), pieces[3].stackY)
end)

T.test("controls_mogul: menu_button_words_left_chevron_right", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local b = W.MenuButton(UIParent, "Rarity: Any")
    T.eq((b.text:GetPoint(1)), "LEFT")
    T.eq((b.chevron:GetPoint(1)), "RIGHT")
    T.eq(b.text:GetText(), "Rarity: Any")
    T.truthy(b:GetWidth() >= W.MENU_BUTTON_MIN)
    b.text.GetStringWidth = function() return 200 end
    b.SetLabel("Rarity: Uncommon+")
    T.eq(b.text:GetText(), "Rarity: Uncommon+")
    T.truthy(b:GetWidth() >= 200 + 30, "room for the words and the chevron")
end)

T.test("controls_mogul: footer_beside_sits_after_main", function()
    local DUI = stub.Load()
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(600, 400)
    local foot = DUI.Win.Parts.Footer(page)
    foot:Set({ { text = "Buy 60", primary = true }, { text = "Buy 260", beside = true }, { text = "Search again" } })
    local _, rel, relPoint = foot.buttons[2]:GetPoint(1)
    T.eq(rel, foot.buttons[1], "beside the main one")
    T.eq(relPoint, "RIGHT")
    local p, rel3 = foot.buttons[3]:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel3, foot.frame, "the last in the right corner")
end)

T.test("controls_mogul: item_icon_quality_edge", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local b = Parts.ItemIcon(CreateFrame("Frame", nil, UIParent), 28)
    T.eq(b.edge:GetWidth(), 30)
    Parts.SetItemIcon(b, 134400, 3)
    local r, g, bl = Parts.QualityColor(3)
    near3({ b.edge:GetVertexColor() }, { r, g, bl }, "the quality's outline")
    T.eq(select(4, b.edge:GetVertexColor()), 1, "at full")
    Parts.SetItemIcon(b, nil, nil)
    near3({ b.edge:GetVertexColor() }, Parts.FAINT, "not cached yet: faint")
end)

T.test("controls_mogul: rule_is_faint", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local r = Parts.Rule(CreateFrame("Frame", nil, UIParent), true)
    T.eq(r:GetWidth(), 1)
    T.eq(select(4, r:GetVertexColor()), Parts.RULE[4])
end)

-- A double-click must not get past the ask. The acting click only counts
-- W.CONFIRM_GAP s after arming (Mogul's "Buy for" at 312% of market).
T.test("controls_mogul: confirm_ignores_a_double_click", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    T.eq(W.CONFIRM_GAP, 0.25)   -- a click at a normal pace (0.3 s, seen in Mogul) must act
    local b = W.Button(UIParent, "", 24)
    local acted = 0
    W.Confirm(b, "Buy", function() acted = acted + 1 end)
    b:Click()
    T.eq(b.text:GetText(), "Click again")
    stub.Advance(0.1)
    b:Click()
    T.eq(acted, 0, "a double-click acts on nothing")
    T.eq(b.text:GetText(), "Click again", "still armed")
    stub.Advance(W.CONFIRM_GAP)
    b:Click()
    T.eq(acted, 1, "after the gap the second click acts")
    T.eq(b.text:GetText(), "Buy")
end)

-- Clearing a list costs nothing but a re-add, and the player double-clicks it on
-- purpose (Mogul's crafting queue).
T.test("controls_mogul: quick_confirm_takes_a_double_click", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local b = W.Button(UIParent, "", 24)
    local acted = 0
    W.Confirm(b, "Clear", function() acted = acted + 1 end, nil, true)
    b:Click()
    T.eq(acted, 0, "one click still only asks")
    T.eq(b.text:GetText(), "Click again")
    b:Click()
    T.eq(acted, 1, "the double-click's second half acts")
    T.eq(b.text:GetText(), "Clear")
    -- Asked again on the same button without it, the gap is back.
    W.Confirm(b, "Delete", function() acted = acted + 1 end)
    b:Click()
    b:Click()
    T.eq(acted, 1, "a plain ask still ignores a double-click")
end)

T.test("controls_mogul: menu_confirm_ignores_a_double_click", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local owner = W.Button(UIParent, "x", 24)
    local picked = 0
    W.OpenMenu(owner, { "del" }, { del = "Delete" }, nil, function() picked = picked + 1 end, 120, { confirm = { del = true } })
    local row = W.MenuRow(1)
    T.truthy(row, "a menu row")
    row:Click()
    stub.Advance(0.1)
    row:Click()
    T.eq(picked, 0, "a double-click on an asking row picks nothing")
    stub.Advance(W.CONFIRM_GAP)
    row:Click()
    T.eq(picked, 1, "after the gap it picks")
end)

T.test("controls_mogul: column_head_flip_eases_the_chevron", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local head = W.ColumnHead(UIParent, COLS, function() end)
    head:Layout(400)
    head:SetSort("item", false)
    tweens(DUI, 1)
    local a = head.cells.item.arrow
    T.near(a.__rotation, math.pi, 0.001, "ascending points up")
    head:SetSort("item", true)
    tweens(DUI, DUI.Motion.FAST / 2)
    T.truthy(a.__rotation > 0.01 and a.__rotation < math.pi - 0.01, "turning, not snapped: " .. a.__rotation)
    tweens(DUI, 1)
    T.near(a.__rotation, 0, 0.001, "descending points down")
    DUI:Set("general", "motion", false)
    head:SetSort("item", false)
    T.near(a.__rotation, math.pi, 0.001, "motion off: at once")
end)

T.test("controls_mogul: stack_ease_skips_item_tiles", function()
    local DUI = stub.Load()
    local s = stackOn(DUI)
    local function fill(extra)
        s:Begin()
        s:Section("Loot")
        if extra then s:Row({ id = "x", text = "X" }) end
        s:Items({ { name = "A", texture = 134400, quality = 2 }, { name = "B", texture = 134400, quality = 3 } })
        return s:End()
    end
    fill(false)
    local before = s:Spots()
    local pieces = fill(true)
    s:Ease(before)
    tweens(DUI, 1)
    local tile2 = pieces[#pieces]
    local _, _, _, x = tile2:GetPoint(1)
    T.truthy(x > 0, "the second tile keeps its column: " .. tostring(x))
end)

-- A section with a total and a link on the right (Mogul's Post tab: "TRADE GOODS  Sell all  9s 06c").
T.test("controls_mogul: section_value_and_action", function()
    local DUI = stub.Load()
    local s = stackOn(DUI)
    local clicked = 0
    s:Begin()
    local a = s:Section("Trade Goods", { value = "9s 06c", action = { text = "Sell all", onClick = function() clicked = clicked + 1 end } })
    local b = s:Section("Recipe")
    local c = s:Section("Herbs", { lit = true, value = "3s" })
    s:End()
    T.eq(a.text:GetText(), "TRADE GOODS")
    T.eq(a.value:GetText(), "9s 06c")
    T.truthy(a.value:IsShown())
    T.truthy(a.action:IsShown())
    T.eq(a.action.text:GetText(), "Sell all")
    a.action:Click()
    T.eq(clicked, 1)
    T.falsy(b.value:IsShown(), "no value: nothing on the right")
    T.falsy(b.action:IsShown())
    local near = function(got, want) for i = 1, 3 do T.near(got[i], want[i], 0.01) end end
    near({ b.text:GetTextColor() }, { DUI.Style.Pop() })
    near({ c.text:GetTextColor() }, DUI.Style.INK.VALUE)
    near({ c.value:GetTextColor() }, DUI.Style.INK.LABEL)
    -- the same frame reused without opts is plain again
    s:Begin()
    a = s:Section("Trade Goods")
    s:End()
    T.falsy(a.value:IsShown()); T.falsy(a.action:IsShown())
    near({ a.text:GetTextColor() }, { DUI.Style.Pop() })
end)

-- A held key on an item: Shift links it, Ctrl tries it on (the game's
-- HandleModifiedItemClick). Anything it doesn't take (a plain click) stays a click.
T.test("controls_mogul: a modified click on an item row or line goes to the game, a plain one picks", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 300)
    local took, modified = {}, true
    _G.HandleModifiedItemClick = function(link)
        if not link or not modified then return false end
        took[#took + 1] = link
        return true
    end
    local picks = 0
    local t = Parts.Table(page, {
        head = { { id = "name", text = "Item", fill = true } },
        make = { line = function() end }, fill = { line = function() end },
        link = function(d) return d.link end,
        onClick = function() picks = picks + 1 end,
    })
    t:SetRows({ { kind = "line", link = "row-link" }, { kind = "line" } })
    local row = t:Row(1)
    row:GetScript("OnClick")(row, "LeftButton")
    T.eq(took[1], "row-link"); T.eq(picks, 0)
    row:GetScript("OnClick")(row, "RightButton")
    T.eq(#took, 1, "a right-click is the row's own"); T.eq(picks, 1)
    local bare = t:Row(2)
    bare:GetScript("OnClick")(bare, "LeftButton")
    T.eq(#took, 1, "no link, no game call"); T.eq(picks, 2)
    modified = false
    row:GetScript("OnClick")(row, "LeftButton")
    T.eq(picks, 3, "a plain click picks")

    modified = true
    local s = Parts.Stack(page)
    local lines = 0
    s:Begin()
    local line = s:Line({ text = "Sword", link = function() return "line-link" end, onClick = function() lines = lines + 1 end })
    s:End()
    line:GetScript("OnClick")(line, "LeftButton")
    T.eq(took[2], "line-link"); T.eq(lines, 0)
    modified = false
    line:GetScript("OnClick")(line, "LeftButton")
    T.eq(lines, 1, "a plain click on a line")
    _G.HandleModifiedItemClick = nil
end)
