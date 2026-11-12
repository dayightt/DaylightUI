local stub = require("stub")

-- The core's tooltip kit (Tips.lua): rows gathered, then flushed onto a
-- tooltip with the words in the accent (down the sweep with the gradient one).

local function capture()
    local tip = { lines = {} }
    function tip:AddLine(t, r, g, b, wrap) self.lines[#self.lines + 1] = { t, lc = { r, g, b }, wrap = wrap } end
    function tip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
        self.lines[#self.lines + 1] = { l, r, lc = { lr, lg, lb }, rc = { rr, rg, rb } }
    end
    return tip
end

local function login(accent)
    local DUI = stub.Load({})
    stub.RunTimers()
    DUI:Set("general", "accent", accent or "daylight")
    return DUI, DUI.Tips, DUI.Style
end

local function build(Tips)
    Tips.Clear()
    Tips.Title("Gold")
    Tips.Sub("Westfall")
    Tips.Text("A sentence about it.")
    Tips.Line("This character", "12g")
    Tips.Gap()
    Tips.Person("Ellie 60", "Ironforge", { 0.2, 0.4, 0.6 })
    Tips.Hint("Click: bags")
end

T.test("tips: one accent paints every word; titles white, sentences light and wrapped", function()
    local DUI, Tips, S = login("custom")
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    local tip = capture()
    build(Tips)
    Tips.Flush(tip)
    local l = tip.lines
    T.eq(#l, 7)
    T.rgb(l[1].lc, { 1, 1, 1 }, "the title white")
    T.rgb(l[2].lc, S.INK.LABEL, "the sub a label")
    T.rgb(l[3].lc, Tips.TEXT, "a sentence soft white")
    T.eq(l[3].wrap, true, "a sentence wraps")
    T.rgb(l[4].lc, Tips.TEXT, "a line's label soft white")
    T.rgb(l[4].rc, Tips.VALUE, "its value light")
    T.eq(l[5][1], " ", "a gap")
    T.rgb(l[6].lc, { 0.2, 0.4, 0.6 }, "a person in their class color")
    T.rgb(l[6].rc, { 0.2, 0.6, 0.9 }, "where they are in the accent")
    T.rgb(l[7].lc, Tips.TEXT, "a hint's words calm")
    T.eq(l[7][1], DUI.Win.Parts.Hex({ 0.2, 0.6, 0.9 }) .. "Click:|r bags", "its click in the accent")
end)

T.test("tips: with the gradient accent every accent row is one color, the middle (no rainbow)", function()
    local DUI, Tips, S = login("gradient")
    local tip = capture()
    build(Tips)
    Tips.Flush(tip)
    local l, m = tip.lines, S.GRADIENT_MID
    T.rgb(l[1].lc, { 1, 1, 1 }, "the title stays white")
    T.rgb(l[6].rc, m, "where someone is: the middle")
    T.rgb(l[3].lc, Tips.TEXT, "a sentence soft white")
    T.eq(l[7][1], DUI.Win.Parts.Hex(m) .. "Click:|r bags", "the hint's click the same color")
end)

T.test("tips: flush empties the list; an empty flush adds nothing", function()
    local _, Tips = login()
    local tip = capture()
    build(Tips)
    Tips.Flush(tip)
    local n = #tip.lines
    Tips.Flush(tip)
    T.eq(#tip.lines, n, "nothing twice")
    Tips.Line("Left over", "1")
    Tips.Clear()
    Tips.Flush(tip)
    T.eq(#tip.lines, n, "Clear drops rows a broken build left")
end)

T.test("tips: the options window's tips take the Daylight middle whatever the accent", function()
    local _, Tips, S = login("custom")
    local tip = capture()
    Tips.Hint("A")
    Tips.Hint("B")
    Tips.Flush(tip, { sweep = "daylight" })
    local m = S.GRADIENT_MID
    T.rgb(tip.lines[1].lc, { m[1] * Tips.HINT, m[2] * Tips.HINT, m[3] * Tips.HINT })
    T.rgb(tip.lines[2].lc, tip.lines[1].lc, "every row the same")
end)

T.test("tips: progress runs red, amber, green; nothing to count stays plain", function()
    local _, Tips = login()
    T.rgb(Tips.Progress(0, 10), Tips.BAD)
    T.rgb(Tips.Progress(5, 10), Tips.WARN)
    T.rgb(Tips.Progress(10, 10), Tips.GOOD)
    T.rgb(Tips.Progress(12, 10), Tips.GOOD, "past the end still done")
    local nine = Tips.Progress(9, 15)
    T.truthy(nine[1] > nine[3] and nine[2] > nine[3], "9/15 reads amber")
    T.truthy(nine[1] > Tips.GOOD[1], "and not yet green")
    T.rgb(Tips.Progress(1, 0), Tips.VALUE)
    T.rgb(Tips.Progress(nil, 5), Tips.VALUE)
end)
