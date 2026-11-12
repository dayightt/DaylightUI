local stub = require("stub")
local MW = require("mailworld")
local function money(c) return DaylightUI.MoneyString(math.abs(c)) end

-- The mailbox's Ledger page with DaylightMogul (an AH addon) loaded. While Mogul
-- books gold, the page shows Mogul's numbers and repaints when they change.
-- Otherwise it shows DaylightUI's own ledger. The Mogul API here is a fake;
-- Mogul's own tests cover the real one.

local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end

local function settle()
    for _ = 1, 30 do
        MW.Settle()
        frame(2)
        if MW.Waiting() == 0 then frame(2); if MW.Waiting() == 0 then return end end
    end
end

local function load(letters)
    stub.Load({ before = MW.world({ money = 0, letters = letters or {} }) })
    return stub.mail
end

local function ledgerPage(ns)
    MW.Open()
    frame(20)
    ns.Window.ShowTab("ledger")
    frame(20)
    return ns.LedgerPage.page
end

local function rightLines(page)
    local out = {}
    for _, b in ipairs(page.right.stack.used) do
        if b:IsShown() and b.lineSpec then out[#out + 1] = b end
    end
    return out
end

local function days(n, net)
    local out = {}
    for i = 1, n do out[i] = { day = date("%Y-%m-%d", time() - (n - i) * 86400), net = i == n and net or 0 } end
    return out
end

-- A stand-in for DaylightMogul.API.
local function fakeMogul(spec)
    local mog = { asked = {}, handlers = {}, net = spec.net or 0 }
    local api = { version = spec.version or { 1, 2 } }
    api.Ledger = {
        Owns = function() return spec.owns ~= false end,
        Range = function(range, view)
            mog.asked[#mog.asked + 1] = { range = range, view = view }
            return { net = mog.net,
                kinds = { sales = mog.net, players = 0, buys = 0, cuts = 0, deposits = 0, postage = 0, sent = 0, cod = 0 },
                days = days(range == "month" and 30 or 7, mog.net),
                items = { { name = "Runecloth", bought = 0, boughtN = 0, sold = mog.net, soldN = 20, net = mog.net } } }
        end,
        Recent = function(view)
            mog.recentView = view
            return { { kind = "sales", amount = mog.net, t = time(), item = "Runecloth", count = 20, who = "Korrin", net = mog.net } }
        end,
        ItemID = function(name) if name == "Runecloth" then return 14047 end end,
    }
    function api.On(name, fn)
        mog.handlers[name] = mog.handlers[name] or {}
        table.insert(mog.handlers[name], fn)
        return true
    end
    function mog.Fire(name)
        for _, fn in ipairs(mog.handlers[name] or {}) do fn() end
    end
    _G.DaylightMogul = { API = api }
    return mog
end

T.test("mail ledger with mogul: page_reads_mogul_when_it_owns", function()
    local ns = load({ { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 } })
    local mog = fakeMogul({ net = 250000 })
    local page = ledgerPage(ns)
    T.truthy(ns.LedgerPage.Source() == DaylightMogul.API.Ledger, "Mogul's ledger is the source")
    T.eq(stub.Text(page.net), money(250000), "Mogul's net")
    T.eq(stub.Text(page.inRows[1].value), money(250000), "Mogul's sales")
    T.eq(mog.asked[#mog.asked].view, "auction", "asked for the auction view")
    T.eq(mog.asked[#mog.asked].range, "week")
    T.eq(mog.recentView, "auction")
    local ls = rightLines(page)
    T.eq(stub.Text(ls[1].name), "Runecloth", "Mogul's items")
    T.eq(ls[1].icon:GetTexture(), "icon:14047", "the icon from Mogul's ItemID")
    T.truthy(stub.Text(ls[2].name):find("Sold: Runecloth", 1, true), "Mogul's latest: " .. stub.Text(ls[2].name))
    _G.DaylightMogul = nil
end)

T.test("mail ledger with mogul: page_reads_its_own_without_mogul", function()
    local ns = load({ { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 } })
    _G.DaylightMogul = nil
    local page = ledgerPage(ns)
    TakeInboxMoney(1)
    settle()
    frame(20)
    T.truthy(ns.LedgerPage.Source() == ns.Ledger, "our own ledger")
    T.eq(stub.Text(page.net), money(15000), "our own net")
    -- Mogul loaded but not booking: still ours.
    fakeMogul({ net = 250000, owns = false })
    ns.LedgerPage.Render()
    frame(20)
    T.truthy(ns.LedgerPage.Source() == ns.Ledger, "Mogul doesn't own it")
    T.eq(stub.Text(page.net), money(15000))
    _G.DaylightMogul = nil
end)

T.test("mail ledger with mogul: page_reads_its_own_when_mogul_is_older", function()
    local ns = load({ { sender = "Brannoc Ironhide", subject = "Ore money", money = 15000 } })
    fakeMogul({ net = 250000, version = { 1, 1 } })
    local page = ledgerPage(ns)
    TakeInboxMoney(1)
    settle()
    frame(20)
    T.truthy(ns.LedgerPage.Source() == ns.Ledger, "Mogul 1.1 has no ledger to give")
    T.eq(stub.Text(page.net), money(15000))
    -- A broken version field never errors.
    DaylightMogul.API.version = "junk"
    T.truthy(ns.LedgerPage.Source() == ns.Ledger)
    -- Nor a Mogul whose Range errors: the page falls back to ours.
    DaylightMogul.API.version = { 1, 2 }
    DaylightMogul.API.Ledger.Range = function() error("boom") end
    T.noerror(function() ns.LedgerPage.Render() end)
    frame(20)
    T.eq(stub.Text(page.net), money(15000), "ours when Mogul's read fails")
    _G.DaylightMogul = nil
end)

T.test("mail ledger with mogul: repaints_on_mogul_change", function()
    local ns = load()
    local mog = fakeMogul({ net = 1000 })
    local page = ledgerPage(ns)
    T.eq(stub.Text(page.net), money(1000))
    T.eq(#(mog.handlers.LedgerChanged or {}), 1, "listens to Mogul's LedgerChanged, once")
    mog.net = 99000
    mog.Fire("LedgerChanged")
    frame(20)
    T.eq(stub.Text(page.net), money(99000), "painted again on Mogul's change")
    ns.LedgerPage.Render()
    T.eq(#mog.handlers.LedgerChanged, 1, "still once after another paint")
    _G.DaylightMogul = nil
end)
