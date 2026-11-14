-- Move what you searched for. While the bag's search or a filter picks out some
-- items and a trade, the mail's send page, a vendor or the bank is open, a
-- button at the end of the filter row sends every match there, one at a time,
-- the same way a right-click would. Selling asks for a second click.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Move = {}
ns.Move = Move

Move.sending = false         -- the mail's send page is showing (the client's SetSendMailShowing)
Move.trading = false
local busy, queued = false, false

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

-- Where a right-click sends a bag item now, and how many more fit there (nil
-- for no limit), or nil when nothing open takes items.
function Move.Where()
    if Move.trading then
        local max, used = MAX_TRADABLE_ITEMS or 6, 0
        for i = 1, max do if call(GetTradePlayerItemLink, i) then used = used + 1 end end
        return "trade", max - used
    end
    if Move.sending then
        local max, used = ATTACHMENTS_MAX_SEND or 12, 0
        for i = 1, max do if call(HasSendMailItem, i) then used = used + 1 end end
        return "mail", max - used
    end
    if ns.Junk.vendorOpen then return "vendor" end
    if ns.Bank and ns.Bank.open then return "bank" end
end

local function label(where)
    if where == "vendor" then return L["Sell %d"] end
    if where == "trade" then return L["Move %d to trade"] end
    if where == "mail" then return L["Move %d to mail"] end
    return L["Move %d to bank"]
end

-- Whether the bag's search or a filter is picking out items.
function Move.Searching(f)
    local t = f.search and f.search:GetText()
    return f.chip ~= nil or (type(t) == "string" and t ~= "")
end

-- The bag items the search and filter pick out, as { bag, slot, link, value }.
-- A vendor only gets what sells for something and isn't locked.
function Move.Matches(f, where)
    local out = {}
    local Cat, Items = ns.Categories, ns.Items
    for _, s in ipairs(ns.Bags.Slots()) do
        if s.section ~= "keyring" then
            local slot = s.button:GetID()
            local info = Items.InfoAt(s.bag, slot)
            if info and not info.isLocked and Items.Fits(s.bag, slot, info, f)
                and (not f.chip or ns.Window.ItemInChip(f, Cat.Facts(s.bag, slot, info))) then
                local value = 0
                if where == "vendor" then value = ns.Junk.PriceOf(info) * (info.stackCount or 1) end
                if where ~= "vendor" or (not info.hasNoValue and value > 0 and not Cat.IsLocked(info.itemID)) then
                    out[#out + 1] = { bag = s.bag, slot = slot, link = info.hyperlink, value = value }
                end
            end
        end
    end
    return out
end

-- What the button would move now: the list (cut to what fits) and where.
local function plan(f)
    local where, room = Move.Where()
    if not where or busy or not Move.Searching(f) then return {}, where end
    local list = Move.Matches(f, where)
    if room then
        while #list > math.max(room, 0) do table.remove(list) end
    end
    return list, where
end

local function sold(count, total)
    local money = DUI.MoneyString(total)
    DUI.Print(count == 1 and string.format(L["Sold 1 item for %s."], money)
        or string.format(L["Sold %d items for %s."], count, money))
end

function Move.Run(f)
    local list, where = plan(f)
    if #list == 0 then return end
    if where == "vendor" then
        busy = true
        Move.Sync(f)
        ns.Junk.Sell(list, sold, function()
            busy = false
            Move.Queue()
        end)
        return
    end
    busy = true
    Move.Sync(f)
    local i, moved = 0, {}
    local function finish()
        busy = false
        if #moved > 0 then ns.Junk.CloseUp(moved, GetTime()) end
        Move.Queue()
    end
    local function step()
        if Move.Where() ~= where then return finish() end
        i = i + 1
        local item = list[i]
        if not item then return finish() end
        -- Still the same item in that slot, not picked up since?
        local ok, info = pcall(C_Container.GetContainerItemInfo, item.bag, item.slot)
        if ok and info and not info.isLocked and info.hyperlink == item.link then
            pcall(C_Container.UseContainerItem, item.bag, item.slot)
            moved[#moved + 1] = item
        end
        C_Timer.After(ns.Junk.STEP, step)
    end
    step()
end

-- The two buttons (plain, and one that asks again before selling), at the end of
-- the filter row.
function Move.Build(f)
    local W = DUI.Widgets
    f.move = ns.Window.TextButton(f, "")
    f.move:SetScript("OnClick", function() Move.Run(f) end)
    f.move:Hide()
    f.moveSell = ns.Window.TextButton(f, "")
    f.moveSell.fit = 1
    W.Confirm(f.moveSell, function() return f.moveText or "" end, function() Move.Run(f) end)
    f.moveSell:Hide()
end

-- Shows the button that fits what's open, with how many it moves. A change lays
-- the window out again (eased), which places it (Move.Place).
function Move.Sync(f)
    if not (f and f.move) then return end
    local list, where = plan(f)
    local want = #list > 0 and (where == "vendor" and f.moveSell or f.move) or nil
    local text = want and string.format(label(where), #list) or nil
    if want == f.moveShown and text == f.moveText then return end
    f.moveShown, f.moveText = want, text
    if want == f.move then
        f.move.SetLabel(text)
    elseif want == f.moveSell and f.moveSell.Paint then
        f.moveSell.Paint()
    end
    if not f:IsShown() then return end
    ns.Layout.easing = true
    DUI.SafeCall(ns.Window.Relayout, f, true, true)
    ns.Layout.easing = false
end

-- Once on the next frame, however many times it's asked.
function Move.Queue()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        DUI.SafeCall(Move.Sync, ns.window)
    end)
end

-- Places the shown button at the right end of the filter row's last line, or on
-- a line of its own when the filters leave no room. Returns the lines it adds.
-- It fades in dropping a little like the filters and fades out where it was.
function Move.Place(f, on, x, line, top, width, eases)
    if not f.move then return 0 end
    local M, Wd, Feel = DUI.Motion, DUI.Widgets, DUI.Win.Feel
    local added = 0
    for _, b in ipairs({ f.move, f.moveSell }) do
        local show = on and f.moveShown == b
        if show then
            local bw = b:GetWidth()
            if x > 0 and x + bw > width then
                line, added = line + 1, 1
            end
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", f, "TOPLEFT", ns.Window.EDGE + width, top - line * Wd.TAB_H - (Wd.TAB_H - b:GetHeight()) / 2)
            if not b.laid and eases then
                b:SetAlpha(0)
                M.AlphaTo(b, 1, M.NORMAL)
                Feel.Glide(b, 0, ns.Layout.FOLD_DROP, M.NORMAL)
            elseif not b.laid then
                M.AlphaTo(b, 1, 0)
            end
            b.laid = true
        elseif b.laid then
            b.laid = nil
            if b.Disarm then b.Disarm() end
            if eases then
                M.AlphaTo(b, 0, M.FAST, true)
            else
                Feel.Settle(b)
                M.AlphaTo(b, 0, 0, true)
            end
        end
    end
    return added
end

function Move.Register()
    local function trade(on) Move.trading = on; Move.Queue() end
    DUI.RegisterEvent("TRADE_SHOW", function() trade(true) end)
    DUI.RegisterEvent("TRADE_CLOSED", function() trade(false) end)
    DUI.RegisterEvent("TRADE_PLAYER_ITEM_CHANGED", Move.Queue)
    -- The client takes right-clicked items for the mail only while a send page
    -- says so (the game's Send tab and the Daylight UI mailbox both do).
    if type(SetSendMailShowing) == "function" then
        hooksecurefunc("SetSendMailShowing", function(on) Move.sending = on == true; Move.Queue() end)
    end
    DUI.RegisterEvent("MAIL_CLOSED", function() Move.sending = false; Move.Queue() end)
    DUI.RegisterEvent("MAIL_SEND_INFO_UPDATE", Move.Queue)
    for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED" }) do
        DUI.RegisterEvent(e, Move.Queue)
    end
    DUI.On("ItemLockChanged", Move.Queue)
end
