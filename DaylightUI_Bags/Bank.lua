-- The bank: the bag window reused for the bank, with its own settings (bank.*)
-- and search. Character and Account tabs in the title bar, plus buying the next
-- tab, depositing reagents, moving gold in and out (Account) and the bank bag
-- slot strip.
--
-- Forever's bank is tabs. Each bank type has purchased tabs, each a container
-- read like a bag (C_Bank.FetchPurchasedBankTabData). On this client a character
-- tab is a bank bag sitting in a slot of the Characterbanktab container. Slots
-- are the game's own bag buttons, so right-click moves an item to the bags, and
-- right-clicking in the bags while the bank is open puts it in the shown bank.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Bank = {}
ns.Bank = Bank

Bank.NAME = "DaylightUIBank"
Bank.DEFAULT_POINT = { "LEFT", "LEFT", 24, 60 }
Bank.DEPOSIT_ICON = "ui-data-professions.png"   -- reagents and trade goods

local function enum(name) return Enum and Enum.BankType and Enum.BankType[name] end
-- A C_Bank function, or nil if the client doesn't have it.
local function bankFn(name) return C_Bank and C_Bank[name] end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

Bank.bankType = nil          -- the bank currently shown

function Bank.CanView(bankType)
    return bankType ~= nil and C_Bank and call(bankFn("CanViewBank"), bankType) == true
end

-- Bank containers: the purchased tabs of the shown bank.
function Bank.List()
    local out = {}
    local bankType = Bank.bankType
    if not (bankType and Bank.CanView(bankType)) then return out end
    local tabs = call(bankFn("FetchPurchasedBankTabData"), bankType)
    for _, tab in ipairs(type(tabs) == "table" and tabs or {}) do
        if type(tab.ID) == "number" then out[#out + 1] = { id = tab.ID, section = "bank" } end
    end
    return out
end

Bank.set = ns.Bags.NewSet(Bank.List)

-- Character and Account tabs

local function paintTabs(f)
    for _, t in ipairs(f.bankTabs or {}) do
        t.Pick(t.bankType == Bank.bankType, true)
        t:SetShown(Bank.CanView(t.bankType))
    end
end

-- Repaint the selected tab right away when the accent changes.
DUI.On("StyleChanged", function()
    if Bank.window then paintTabs(Bank.window) end
end)

-- Never tell the game's bank frame which bank is shown (BankPanel:SetBankType).
-- A bank type written by addon code is tainted, and the game passes
-- BankFrame:GetActiveBankType() into every right-click's UseContainerItem, so
-- using anything from the bags got blocked. The panel stays hidden, so the game
-- reads nil.

-- Switches to a bank.
function Bank.Select(bankType)
    if not Bank.CanView(bankType) then return end
    Bank.bankType = bankType
    local f = Bank.window
    if f then
        paintTabs(f)
        ns.Window.Relayout(f)
        ns.Window.FillAll(f)
        if Bank.strip then Bank.RefreshStrip() end
    end
end

-- In the header, right of the title and left of the X (like the window kit's tabs).
local function makeTabs(f)
    f.bankTabs = {}
    local right = f.close
    local defs = { { L["Character"], enum("Character") }, { L["Account"], enum("Account") } }
    for i = #defs, 1, -1 do
        local def = defs[i]
        local t = DUI.Widgets.Tab(f, def[1], { size = ns.Window.TEXT_SIZE })
        t.bankType = def[2]
        t:SetHeight(DUI.Widgets.TAB_H)
        t.FitWidth()
        t:SetPoint("RIGHT", right, "LEFT", -DUI.Win.TAB_GAP, 0)
        t:SetScript("OnClick", function(self) Bank.Select(self.bankType) end)
        table.insert(f.bankTabs, 1, t)
        right = t
    end
    -- The title and drag handle stop short of the tabs.
    f.title:SetPoint("RIGHT", right, "LEFT", -8, 0)
    f.sub:SetPoint("RIGHT", right, "LEFT", -8, 0)
    f.handle:ClearAllPoints()
    f.handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.handle:SetPoint("RIGHT", right, "LEFT", -4, 0)
    f.handle:SetHeight(ns.Window.TITLE)
end

-- Footer: gold (Account) and buying a tab

local money = DUI.MoneyString

-- Buying a tab. C_Bank.PurchaseBankTab is restricted: the game blocks it from
-- addon code, from its CONFIRM_BUY_BANK_TAB popup when addon code shows it, and
-- even from a secure macro's /run (which runs as "ForceTaint_Strong"). So the
-- button is the game's own purchase button (BankPanelPurchaseButtonScriptTemplate,
-- as used by the default bank). Its OnClick shows the game's popup, which does
-- the buying. Only overrideBankType is set here, the same way EllesmereUI does it.

local function nextTab()
    local data = call(bankFn("FetchNextPurchasableBankTabData"), Bank.bankType)
    return type(data) == "table" and type(data.tabCost) == "number" and data or nil
end

-- Show the cost only when there is one. The first tab costs 0 (Bank.Park) and
-- the game buys it by itself when its bank frame shows.
local function buyLabel()
    local data = nextTab()
    if not (data and data.tabCost > 0) then return L["Buy tab"] end
    return string.format(L["Buy tab: %s"], money(data.tabCost))
end

-- The Buy tab button sits on the free bar's row at the right, where the bags
-- keep Sell junk, clear of the gold below.
local function placeBuy(f)
    local W = ns.Window
    f.buyTab:ClearAllPoints()
    f.buyTab:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -W.EDGE, W.EDGE + W.FOOTER_ROW + W.BAR_GAP)
end

local function footer(f)
    local W = ns.Window
    -- The game's purchase button: never SetScript its OnClick.
    f.buyTab = W.TextButton(f, L["Buy tab"], "BankPanelPurchaseButtonScriptTemplate")
    placeBuy(f)
    W.Tip(f.buyTab, L["Buy a bank tab"], function()
        local data = nextTab()
        return data and data.tabCost > 0 and string.format(L["Costs %s."], money(data.tabCost)) or nil
    end)
    f.withdraw = W.TextButton(f, L["Withdraw"])
    f.withdraw:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -W.EDGE, W.EDGE - 3)
    f.withdraw:SetScript("OnClick", function()
        if StaticPopup_Hide then StaticPopup_Hide("BANK_MONEY_DEPOSIT") end
        StaticPopup_Show("BANK_MONEY_WITHDRAW", nil, nil, { bankType = Bank.bankType })
    end)
    W.Tip(f.withdraw, L["Withdraw gold"], L["Take gold out of the account bank."])
    f.deposit = W.TextButton(f, L["Deposit"])
    f.deposit:SetPoint("RIGHT", f.withdraw, "LEFT", -4, 0)
    f.deposit:SetScript("OnClick", function()
        if StaticPopup_Hide then StaticPopup_Hide("BANK_MONEY_WITHDRAW") end
        StaticPopup_Show("BANK_MONEY_DEPOSIT", nil, nil, { bankType = Bank.bankType })
    end)
    W.Tip(f.deposit, L["Deposit gold"], L["Put gold into the account bank, for every character."])
end

local function updateFooter(f)
    local bankType = Bank.bankType
    local canBuy = bankType ~= nil and call(bankFn("CanPurchaseBankTab"), bankType) == true
    placeBuy(f)
    if canBuy then
        f.buyTab:SetAttribute("overrideBankType", bankType)
        f.buyTab.SetLabel(buyLabel())
    end
    f.buyTab:SetShown(canBuy)
    -- Deposit reagents only where the bank supports it.
    f.depositButton:SetShown(bankType ~= nil and call(bankFn("DoesBankTypeSupportAutoDeposit"), bankType) == true)
    -- Gold transfer only for banks that hold gold (the account bank).
    local holdsGold = bankType ~= nil and call(bankFn("DoesBankTypeSupportMoneyTransfer"), bankType) == true
    f.deposit:SetShown(holdsGold)
    f.withdraw:SetShown(holdsGold)
    f.money:ClearAllPoints()
    if holdsGold then
        f.money:SetPoint("RIGHT", f.deposit, "LEFT", -8, 0)
        -- A deposit or withdrawal tweens the bank's gold to the new amount, same as
        -- the footer gold (MoneyRoll).
        local amount = call(bankFn("FetchDepositedMoney"), bankType)
        local roll = ns.Setting("moneyRoll") ~= false and f:IsVisible()
        local coins = DUI.Widgets.Money
        if not roll then DUI.Motion.CountTo(f.money, nil, function() return coins(amount) end)
        else DUI.Motion.CountTo(f.money, amount, coins, DUI.Motion.SLOW) end
        f.deposit:SetEnabled(call(bankFn("CanDepositMoney"), bankType) == true)
        f.withdraw:SetEnabled(call(bankFn("CanWithdrawMoney"), bankType) == true)
    else
        f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ns.Window.EDGE, ns.Window.EDGE)
        DUI.Motion.CountTo(f.money, nil, function() return "" end)
    end
end

-- Bank bag slot strip (character bank)

local function bagSlot(i)
    local idx = Enum and Enum.BagIndex
    return idx and idx.Characterbanktab, i
end

local function tabContainer(i)
    local idx = Enum and Enum.BagIndex
    return idx and idx.CharacterBankTab_1 and (idx.CharacterBankTab_1 + i - 1)
end

-- Built from the bag strip's pieces (Slots.lua).
function Bank.CreateStrip(f)
    local Slots = ns.Slots
    local strip = Slots.NewStrip(f)
    local max = call(bankFn("FetchMaxNumBankTabs"), enum("Character")) or 0
    for i = 1, max do
        local function pick() local c, s = bagSlot(i); if c then pcall(C_Container.PickupContainerItem, c, s) end end
        local b = Slots.NewButton(strip, { pick = pick, put = pick,
            slots = function() return f.set.Slots() end,
            lit = function() return tabContainer(i) end,
            tip = function(self)
                local c, s = bagSlot(i)
                local ok = c and pcall(GameTooltip.SetBagItem, GameTooltip, c, s)
                if not (ok and GameTooltip:NumLines() and GameTooltip:NumLines() > 0) then
                    GameTooltip:SetText(self.bought and (BANK_BAG or L["Bank bag"]) or (BANK_BAG_PURCHASE or L["Buy this bank slot"]), 1, 1, 1)
                end
            end })
        b.index = i
        strip.slots[i] = b
    end
    Bank.strip = strip
    Bank.LayoutStrip()
end

function Bank.LayoutStrip()
    local strip, f = Bank.strip, Bank.window
    if not strip then return end
    ns.Slots.LayoutStrip(strip, f.Setting("iconSize") or 35, f.Setting("spacing") or 2)
end

function Bank.RefreshStrip()
    local strip, f = Bank.strip, Bank.window
    if not strip then return end
    local show = f.Setting("showSlots") == true and Bank.bankType == enum("Character") and #strip.slots > 0
    strip:SetShown(show)
    if not show then return end
    local tabs = call(bankFn("FetchPurchasedBankTabData"), enum("Character"))
    local bought = {}
    for _, tab in ipairs(type(tabs) == "table" and tabs or {}) do bought[#bought + 1] = tab end
    for i, b in ipairs(strip.slots) do
        b.bought = i <= #bought
        local c, s = bagSlot(i)
        local ok, info = pcall(C_Container.GetContainerItemInfo, c, s)
        local tex = ok and info and info.iconFileID
        ns.Slots.Paint(b, tex, tex and info.quality)
        b.icon:SetAlpha(b.bought and 1 or 0.35)
    end
end

-- The window

local hidden = CreateFrame("Frame")
hidden:Hide()

-- Forever's first bank tab costs 0 and nobody ever clicks to get it. The game's
-- own bank frame buys it when it shows (Camelot/BankFrame.lua, BankFrameMixin:
-- OnShow > SetTab > PurchaseFirstSlot). Without that tab the bank has no slots
-- at all: an empty window and "your bank is full" on right-click.
-- PurchaseBankTab is refused to addon code (see the footer above), and a frame
-- shown by addon code would run that OnShow tainted, so only the game's own
-- ShowUIPanel can do it. Until this character has a tab, the bank frame waits
-- under the veil where the game's show really shows it. After that it's parked
-- for good: its BankPanel stays hidden, the game reads nil, and right-clicks go
-- to the bank being viewed (see the top of this file).
function Bank.HasTab()
    local n = call(bankFn("FetchNumPurchasedBankTabs"), enum("Character"))
    if type(n) == "number" and n > 0 then Bank.tabSeen = true end
    -- The live count only reads at a banker, so a saved bank counts too.
    return Bank.tabSeen == true or ns.Saved.HasBank()
end

local function park(hasTab)
    local game = _G.BankFrame
    if not game then return end
    local home = hasTab and hidden or DUI.Win.Followers.veil
    if game:GetParent() ~= home then game:SetParent(home) end
end

function Bank.Park() park(Bank.HasTab()) end

function Bank.Open()
    local f = Bank.window
    if not f then return end
    local pick = Bank.bankType
    if not Bank.CanView(pick) then
        pick = Bank.CanView(enum("Character")) and enum("Character") or enum("Account")
    end
    Bank.bankType = pick
    paintTabs(f)
    ns.Window.Relayout(f)
    f:Show()
    Bank.RefreshStrip()
end

function Bank.Close()
    local f = Bank.window
    if not f then return end
    if DUI.Motion then DUI.Motion.Vanish(f) else f:Hide() end
end

function Bank.Build()
    local W = ns.Window
    local f = W.Create({
        kind = "bank", name = Bank.NAME, title = "Bank", set = Bank.set, prefix = "bank.",
        portrait = "Interface\\Icons\\INV_Misc_Ornatebox",
        defaultPoint = Bank.DEFAULT_POINT,
        onClose = function() call(bankFn("CloseBankFrame")) end,
        footer = footer, updateFooter = updateFooter,
        afterLayout = function() Bank.LayoutStrip() end,
        tools = {
            { key = "sort", icon = W.SORT_ICON, title = L["Clean up the bank"],
              onClick = function(w)
                  if InCombatLockdown and InCombatLockdown() then return end
                  W.BeginSort(w)
                  if C_Container.SortBank and Bank.bankType then pcall(C_Container.SortBank, Bank.bankType)
                  elseif C_Container.SortBankBags then pcall(C_Container.SortBankBags) end
              end },
            { key = "depositButton", icon = Bank.DEPOSIT_ICON, title = L["Deposit reagents"],
              desc = L["Puts every reagent and trade good from your bags into this bank."],
              onClick = function()
                  if Bank.bankType then call(bankFn("AutoDepositItemsIntoBank"), Bank.bankType) end
              end },
            { key = "slotsButton", icon = W.SLOTS_ICON, title = L["Bank bag slots"],
              desc = L["Show the bank's bag slots: drag a bag out, or drop one in."],
              onClick = function(w)
                  W.SortTouched(w)
                  w.Set("showSlots", not w.Setting("showSlots"))
              end },
            { key = "viewButton", icon = W.VIEW_ICON, title = L["Shelf, grid or list"],
              desc = L["Switch between Shelf, grouped by kind, Grid, tab by tab, and List, a row per item."],
              onClick = function(w)
                  W.SortTouched(w)
                  w.Set("view", W.NextView(w.Setting("view")))
              end },
        },
    })
    Bank.window = f
    ns.bank = f
    makeTabs(f)
    Bank.CreateStrip(f)
    -- Closing this window (Escape) closes the game's bank too.
    f:HookScript("OnHide", function()
        if Bank.open then call(bankFn("CloseBankFrame")) end
    end)
    -- The game's bank window stays out of sight and this one follows it.
    Bank.Park()
    -- The game opens and closes the bags along with the bank in its bank frame's
    -- OnShow/OnHide (BankFrameTemplates.lua), which a frame under a hidden parent
    -- never gets, so do the same here. Twice under the veil, since the game's
    -- OpenAllBags does nothing with the bags already open. Don't pass the bank as
    -- the opener: that goes in a game local and would be tainted if written from
    -- here (see OC.CloseGame in OpenClose.lua). Remember who opened them instead.
    DUI.RegisterEvent("BANKFRAME_OPENED", function()
        Bank.open = true
        Bank.Open()
        Bank.Reread()
        Bank.openedBags = Bank.openedBags or not ns.OpenClose.AnyOpen()
        if type(OpenAllBags) == "function" then pcall(OpenAllBags) end
    end)
    DUI.RegisterEvent("BANKFRAME_CLOSED", function()
        Bank.open = false
        Bank.Close()
        if Bank.openedBags then ns.OpenClose.CloseAll() end
        Bank.openedBags = nil
        -- Read while still at the banker; move it only after the game's frame has
        -- closed (moving a frame that's still shown would run its OnHide tainted).
        local hasTab = Bank.HasTab()
        C_Timer.After(0, function()
            if Bank.open or (_G.BankFrame and _G.BankFrame:IsShown()) then return end
            park(hasTab)
        end)
    end)
    for _, e in ipairs({ "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED",
                         "BANK_TAB_SETTINGS_UPDATED" }) do
        pcall(DUI.RegisterEvent, e, function()
            if f:IsShown() then
                W.Changed(f)
                Bank.RefreshStrip()
            end
            ns.Saved.SaveBankSoon()
        end)
    end
    -- Account bank gold only appears in the footer.
    pcall(DUI.RegisterEvent, "ACCOUNT_MONEY", function() W.UpdateFooter(f) end)
end

-- Tabs and slot counts arrive from the server a moment after BANKFRAME_OPENED,
-- and a first visit's free tab only after the game's purchase (Bank.Park). So
-- read again on the next frame, then every READ_EVERY seconds for READ_FOR
-- seconds while the bank still shows no slots.
Bank.READ_EVERY, Bank.READ_FOR = 0.5, 5

local function noSlots()
    for _, b in ipairs(Bank.List()) do
        if (C_Container.GetContainerNumSlots(b.id) or 0) > 0 then return false end
    end
    return true
end

function Bank.Reread()
    local f = Bank.window
    local tries = math.floor(Bank.READ_FOR / Bank.READ_EVERY)
    local function read(again)
        if not (Bank.open and f and f:IsShown()) then return end
        -- Still empty: pick the bank again (Character first), like on open.
        if noSlots() then Bank.bankType = nil; Bank.Open() end
        ns.Window.Changed(f)
        ns.Window.UpdateFooter(f)
        Bank.RefreshStrip()
        ns.Saved.SaveBankSoon()
        if again and tries > 0 and noSlots() then
            tries = tries - 1
            C_Timer.After(Bank.READ_EVERY, function() read(true) end)
        end
    end
    C_Timer.After(0, function() read(true) end)
end

function Bank.Refresh()
    if Bank.window then
        Bank.LayoutStrip()
        Bank.RefreshStrip()
    end
end
