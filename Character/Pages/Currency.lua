-- The Currency page: each currency with its icon and
-- amount under group names; the pane says what it's for, this week's limit,
-- "Show in the backpack", and "Transfer to another character".
--
-- The list is read with C_CurrencyInfo; the game's own currency page
-- (TokenFrame), its list and its transfer menu are never touched (spec
-- 6.8). A transfer un-parks the game's window on its currency page, where
-- the game's own transfer works untouched; ours steps aside until the game
-- closes it.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L

local Currency = {}
ns.Currency = Currency

function Currency.Read()
    local C, out = C_CurrencyInfo, {}
    if type(C) ~= "table" or type(C.GetCurrencyListSize) ~= "function" then return out end
    for i = 1, C.GetCurrencyListSize() or 0 do
        local c = C.GetCurrencyListInfo(i)
        if c then
            out[#out + 1] = { index = i, name = c.name or "", header = c.isHeader == true, expanded = c.isHeaderExpanded == true,
                quantity = c.quantity or 0, icon = c.iconFileID, id = c.currencyID, weekly = c.quantityEarnedThisWeek or 0,
                weeklyMax = c.maxWeeklyQuantity or 0, backpack = c.isShowInBackpack == true }
        end
    end
    return out
end

function Currency.Items(list)
    local items = {}
    for _, c in ipairs(list) do
        if c.header then
            items[#items + 1] = { kind = "head", key = "h" .. c.index, text = c.name, folded = not c.expanded, data = c }
        else
            items[#items + 1] = { kind = "row", key = "c" .. tostring(c.id or c.index), text = c.name, icon = c.icon,
                                  right = ns.List.Number(c.quantity), rightColor = { DUI.Style.Pop() }, data = c }
        end
    end
    return items
end

function Currency.Week(c)
    if (c.weeklyMax or 0) <= 0 then return nil end
    return string.format(L["%s of %s this week"], ns.List.Number(c.weekly), ns.List.Number(c.weeklyMax))
end

-- Out of combat only. True when the game's window took over.
function Currency.Transfer()
    if InCombatLockdown() or type(_G.TokenFrame) ~= "table" then return false end
    return ns.Follow.Unpark("TokenFrame") == true
end

local function picked(page)
    for _, item in ipairs(page.list.items) do
        if item.kind == "row" and item.key == page.list.selectedKey then return item.data end
    end
end

function Currency.ShowPane(page)
    local P, c = page.pane, picked(page)
    P:SetShown(c ~= nil)
    if not c then return end
    P.title:SetText(c.name)
    P.sub:SetText(ns.List.Number(c.quantity))
    local week = Currency.Week(c)
    P.bar:SetShown(week ~= nil)
    if week then
        local key, rgb = ns.List.OwnBar()
        P.bar:SetMinMaxValues(0, c.weeklyMax)
        -- The same currency earning: the fill glides; another one picked: at once.
        DUI.Style.SetBarValue(P.bar, math.min(c.weekly, c.weeklyMax), P.barFor ~= (c.id or c.index))
        P.barFor = c.id or c.index
        ns.List.PaintBar(P.bar, key, rgb)
    end
    P.barText:SetText(week or "")
    local describe = C_CurrencyInfo.GetCurrencyDescription
    P.body:SetText(type(describe) == "function" and c.id and (describe(c.id) or "") or "")
    ns.List.SetToggle(P.toggles[1], c.backpack, true, c.id or c.index)
    P.button:SetShown(type(_G.TokenFrame) == "table")
    P.button.text:SetText(InCombatLockdown() and L["No transfers in combat"] or L["Transfer to another character"])
    P.currency = c
end

function Currency.Build(page)
    page.list = ns.List.Make(page, {
        onPick = function() Currency.ShowPane(page) end,
        onFold = function(item)
            C_CurrencyInfo.ExpandCurrencyList(item.data.index, item.folded == true)
            ns.Window.Refresh()
        end,
    })
    page.pane = ns.List.Pane(page)
    local P = page.pane
    ns.List.AddToggle(P, L["Show in the backpack"], function(t)
        if P.currency then C_CurrencyInfo.SetCurrencyBackpack(P.currency.index, not t.on) end
        ns.Window.Refresh()
    end)
    P.button:SetScript("OnClick", function() Currency.Transfer() end)
end

function Currency.Place(page)
    local E, W = ns.List.EDGE, ns.Window.Width()
    local paneW = ns.List.PANE_W
    ns.List.Place(page.list, E, W - 3 * E - paneW)
    ns.List.PlacePane(page.pane, W - E - paneW, paneW)
end

function Currency.Refresh(page)
    local items = Currency.Items(Currency.Read())
    local L = page.list
    local found = false
    for _, item in ipairs(items) do if item.key == L.selectedKey then found = true end end
    if not found then
        L.selectedKey = nil
        for _, item in ipairs(items) do
            if item.kind == "row" then L.selectedKey = item.key; break end
        end
    end
    ns.List.Set(L, items)
    Currency.ShowPane(page)
end

Currency.events = { "CURRENCY_DISPLAY_UPDATE" }
Currency.Available = function()
    local C = C_CurrencyInfo
    return type(C) == "table" and type(C.GetCurrencyListSize) == "function" and (C.GetCurrencyListSize() or 0) > 0
end

ns.Window.Register("currency", Currency)
