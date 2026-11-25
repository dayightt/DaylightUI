-- Tracked currencies in the footer next to the money, from the game's own
-- backpack list (C_CurrencyInfo.GetBackpackCurrencyInfo). Can be turned off.
-- Each one takes the clicks the game's backpack currencies take: a click opens
-- the Currency page, Shift-click links it while typing, else stops tracking it.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Currency = {}
ns.Currency = Currency

Currency.SIZE = 14
Currency.GAP = 8
Currency.MAX = 6             -- the footer only has so much room

-- The Currency page, as the game's tracked currencies open it. Not in a fight,
-- where the game refuses ToggleCharacter from addon code; with the controller
-- UI on, opening the game's window from here would taint it, so the character
-- window opens on its own.
function Currency.OpenPage()
    if InCombatLockdown() then return end
    if DUI.Pad and DUI.Pad.On() then
        local follow = DUI.Char and DUI.Char.Follow
        if follow and follow.OpenAlone then follow.OpenAlone("currency") end
        return
    end
    if type(ToggleCharacter) == "function" then DUI.SafeCall(ToggleCharacter, "TokenFrame") end
end

function Currency.Click(id)
    if type(id) ~= "number" then return end
    local C = C_CurrencyInfo
    if IsModifiedClick("CHATLINK") then
        local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
        local link = type(C.GetCurrencyLink) == "function" and C.GetCurrencyLink(id) or nil
        if link and type(insert) == "function" and insert(link) then return end
    end
    if IsModifiedClick("TOKENWATCHTOGGLE") then
        if type(C.SetCurrencyBackpackByID) == "function" then C.SetCurrencyBackpackByID(id, false) end
        DUI.Fire("BackpackCurrencyChanged")
        return
    end
    Currency.OpenPage()
end

local function slot(f, i)
    f.currencySlots = f.currencySlots or {}
    local b = f.currencySlots[i]
    if b then return b end
    b = CreateFrame("Button", nil, f)
    b:SetSize(Currency.SIZE, Currency.SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    Style.CropIcon(b.icon)
    b.count = Style.Text(b, Style.SIZE.tiny, "LEFT")
    Style.InkText(b.count, "VALUE")
    b:SetScript("OnClick", function(self) Currency.Click(self.currencyID) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not (self.index and pcall(GameTooltip.SetBackpackToken, GameTooltip, self.index)) then
            GameTooltip:SetText(CURRENCY or L["Currency"], 1, 1, 1)
        end
        local Tips = DUI.Tips
        Tips.Clear()
        Tips.Hint(L["Shift-click: stop showing it in your bag"])
        Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.currencySlots[i] = b
    return b
end

-- Lays out tracked currencies right to left from the money. Hides them (and
-- puts the money back) when the option is off or nothing is tracked.
function Currency.Update(f)
    if not f or f.kind ~= "bag" then return end
    local show = ns.Setting("showCurrency") ~= false
    local fn = C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
    local n, right = 0, f.money
    if show and type(fn) == "function" then
        for i = 1, Currency.MAX do
            local ok, info = pcall(fn, i)
            if not ok or type(info) ~= "table" then break end
            n = n + 1
            local b = slot(f, n)
            b.icon:SetTexture(info.iconFileID)
            local text = tostring(info.quantity or 0)
            if #text > 5 and type(AbbreviateNumbers) == "function" then
                local aok, s = pcall(AbbreviateNumbers, info.quantity)
                if aok and s then text = s end
            end
            b.count:SetText(text)
            b.index, b.currencyID = i, info.currencyTypesID
            -- The count sits to the right of its icon, so the count is what anchors to
            -- the next thing over (the money or the previous currency).
            b.count:ClearAllPoints()
            b.count:SetPoint("RIGHT", right, "LEFT", n == 1 and -10 or -Currency.GAP, 0)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", b.count, "LEFT", -2, 0)
            b:Show()
            right = b
        end
    end
    for i = n + 1, #(f.currencySlots or {}) do f.currencySlots[i]:Hide() end
end

-- Tracked or untracked from the Currency page or a Shift-click here: no game
-- event comes for it.
DUI.On("BackpackCurrencyChanged", function()
    if ns.window then Currency.Update(ns.window) end
end)
