-- Tracked currencies in the footer next to the money, from the game's own
-- backpack list (C_CurrencyInfo.GetBackpackCurrencyInfo). Can be turned off.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Currency = {}
ns.Currency = Currency

Currency.SIZE = 14
Currency.GAP = 8
Currency.MAX = 6             -- the footer only has so much room

local function slot(f, i)
    f.currencySlots = f.currencySlots or {}
    local b = f.currencySlots[i]
    if b then return b end
    b = CreateFrame("Frame", nil, f)
    b:SetSize(Currency.SIZE, Currency.SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    Style.CropIcon(b.icon)
    b.count = Style.Text(b, Style.SIZE.tiny, "LEFT")
    Style.InkText(b.count, "VALUE")
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not (self.index and pcall(GameTooltip.SetBackpackToken, GameTooltip, self.index)) then
            GameTooltip:SetText(CURRENCY or L["Currency"], 1, 1, 1)
        end
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
            b.index = i
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
