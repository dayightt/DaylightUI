-- The Currency page: each currency with its icon and
-- amount under group names; the pane says what it's for, this week's limit,
-- "Show in the backpack", and "Transfer to another character".
--
-- The list is read with C_CurrencyInfo; the game's own currency page
-- (TokenFrame), its list and its transfer menu are never touched.
-- A transfer un-parks the game's window on its currency page, where
-- the game's own transfer works untouched; this page steps aside until the game
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
                weeklyMax = c.maxWeeklyQuantity or 0, backpack = c.isShowInBackpack == true, max = c.maxQuantity or 0,
                unused = c.isTypeUnused == true, discovered = c.discovered ~= false,
                transferable = c.isAccountTransferable == true, keeps = c.transferPercentage }
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

-- How many currencies the backpack has room for: Daylight UI's bag footer while
-- its bags are on, else the game's own bag (BackpackTokenFrame). nil = no limit known.
function Currency.MaxWatched()
    if DUI.BagCurrencyMax then return DUI.BagCurrencyMax end
    local b = _G.BackpackTokenFrame
    if type(b) == "table" and type(b.GetMaxTokensWatched) == "function" then
        local ok, n = DUI.SafeReturn(b.GetMaxTokensWatched, b)
        if ok and type(n) == "number" then return n end
    end
end

local function watchedCount()
    local fn = C_CurrencyInfo.GetBackpackCurrencyInfo
    if type(fn) ~= "function" then return 0 end
    local n = 0
    while n < 100 and fn(n + 1) do n = n + 1 end
    return n
end

-- In or out of the backpack, the game's way (TokenFrameMixin:SetTokenWatched): a
-- full backpack refuses one more and says so. False when refused.
function Currency.SetWatched(c, on)
    if on then
        local max = Currency.MaxWatched()
        if max and watchedCount() >= max then
            local say = _G.TOO_MANY_WATCHED_TOKENS
            if type(say) == "string" and UIErrorsFrame then UIErrorsFrame:AddMessage(string.format(say, max), 1.0, 0.1, 0.1, 1.0) end
            return false
        end
    end
    C_CurrencyInfo.SetCurrencyBackpack(c.index, on)
    ns.Window.Refresh()
    -- No event comes for it: the bag's footer is told.
    DUI.Fire("BackpackCurrencyChanged")
    return true
end

-- Shift-click a row: its link in the chat box while typing (CHATLINK), else in or
-- out of the backpack (TOKENWATCHTOGGLE), as the game's currency list does.
function Currency.ModifiedClick(item)
    local c = item and item.data
    if not c or c.header then return false end
    local C = C_CurrencyInfo
    if IsModifiedClick("CHATLINK") then
        local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
        local link = type(C.GetCurrencyListLink) == "function" and C.GetCurrencyListLink(c.index) or nil
        if link and type(insert) == "function" and insert(link) then return true end
    end
    if IsModifiedClick("TOKENWATCHTOGGLE") then
        Currency.SetWatched(c, not c.backpack)
        return true
    end
    return false
end

-- Why a transfer can't happen now, in the game's words (Blizzard_CurrencyTransfer.lua).
local REASONS = { MaxQuantity = "CURRENCY_TRANSFER_DISABLED_MAX_QUANTITY",
    NoValidSourceCharacter = "CURRENCY_TRANSFER_DISABLED_NO_VALID_SOURCES",
    CannotUseCurrency = "CURRENCY_TRANSFER_DISABLED_UNMET_REQUIREMENTS",
    TransactionInProgress = "CURRENCY_TRANSFER_IN_PROGRESS", CurrencyTransferDisabled = "ERR_CURRENCY_TRANSFER_DISABLED" }

-- The transfer button's state: nil = hidden (this currency can't move between
-- characters), else { ok = bool, why = text or nil }.
function Currency.TransferState(c)
    local C = C_CurrencyInfo
    if not (c and c.id and c.transferable) or type(_G.TokenFrame) ~= "table" then return nil end
    if InCombatLockdown() then return { ok = false } end
    if type(C.IsAccountCharacterCurrencyDataReady) == "function" and not C.IsAccountCharacterCurrencyDataReady() then
        return { ok = false, why = _G.RETRIEVING_DATA }
    end
    if type(C.CanTransferCurrency) ~= "function" then return { ok = true } end
    local can, reason = C.CanTransferCurrency(c.id)
    if can then return { ok = true } end
    local why
    local E = Enum and Enum.AccountCurrencyTransferResult
    for key, global in pairs(REASONS) do
        if E and E[key] ~= nil and E[key] == reason then why = _G[global] end
    end
    return { ok = false, why = why }
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
    -- The most you can hold, when there is a most (the game's Total Maximum row).
    P.sub:SetText(c.max > 0 and string.format("%s / %s", ns.List.Number(c.quantity), ns.List.Number(c.max))
        or ns.List.Number(c.quantity))
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
    local body = type(describe) == "function" and c.id and (describe(c.id) or "") or ""
    -- What a transfer loses, as the game's pane says it.
    local lost = c.transferable and type(c.keeps) == "number" and 100 - c.keeps or 0
    if lost > 0 and type(_G.CURRENCY_TRANSFER_LOSS) == "string" then
        body = body .. (body ~= "" and "\n\n" or "") .. string.format(_G.CURRENCY_TRANSFER_LOSS, math.ceil(lost))
    end
    P.body:SetText(body)
    ns.List.SetToggle(P.toggles[1], c.backpack, c.discovered, c.id or c.index)
    ns.List.SetToggle(P.toggles[2], c.unused, c.discovered, c.id or c.index)
    local t = Currency.TransferState(c)
    P.button:SetShown(t ~= nil)
    if t then
        if P.button.wantData ~= c.id and type(C_CurrencyInfo.RequestCurrencyDataForAccountCharacters) == "function" then
            P.button.wantData = c.id
            C_CurrencyInfo.RequestCurrencyDataForAccountCharacters()
        end
        P.button.SetOff(not t.ok)
        P.button.why = t.why
        P.button.text:SetText(InCombatLockdown() and L["No transfers in combat"] or L["Transfer to another character"])
    end
    P.currency = c
end

function Currency.Build(page)
    page.list = ns.List.Make(page, {
        onPick = function() Currency.ShowPane(page) end,
        onModified = Currency.ModifiedClick,
        onFold = function(item)
            C_CurrencyInfo.ExpandCurrencyList(item.data.index, item.folded == true)
            ns.Window.Refresh()
        end,
    })
    page.pane = ns.List.Pane(page)
    local P = page.pane
    ns.List.AddToggle(P, L["Show in the backpack"], function(t)
        if not P.currency then return false end
        return Currency.SetWatched(P.currency, not t.on)
    end, function() return _G.TOKEN_SHOW_ON_BACKPACK end)
    -- Unused moves it to the game's Unused group (TOKEN_MOVE_TO_UNUSED).
    ns.List.AddToggle(P, L["Unused"], function(t)
        if not P.currency then return false end
        C_CurrencyInfo.SetCurrencyUnused(P.currency.index, not t.on)
        ns.Window.Refresh()
    end, function() return _G.TOKEN_MOVE_TO_UNUSED end)
    P.button:SetScript("OnClick", function() Currency.Transfer() end)
    -- Off, the button says why on hover (the game's disabled tooltip).
    P.button:HookScript("OnEnter", function(self)
        if not (self.off and type(self.why) == "string" and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        DUI.Tips.Clear()
        DUI.Tips.Text(self.why, DUI.Tips.WARN)
        DUI.Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    P.button:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end

-- A currency taken off the bag's footer (Shift-click there) unticks it here.
DUI.On("BackpackCurrencyChanged", function() ns.Window.Refresh() end)

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

Currency.events = { "CURRENCY_DISPLAY_UPDATE", "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", "CURRENCY_TRANSFER_FAILED",
    "CURRENCY_TRANSFER_INITIATED" }
Currency.Available = function()
    local C = C_CurrencyInfo
    return type(C) == "table" and type(C.GetCurrencyListSize) == "function" and (C.GetCurrencyListSize() or 0) > 0
end

ns.Window.Register("currency", Currency)
