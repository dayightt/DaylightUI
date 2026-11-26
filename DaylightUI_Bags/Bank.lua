-- The bank: the bag window reused for the bank, with its own settings (bank.*)
-- and search. Character and Account tabs in the title bar, plus buying the next
-- tab, depositing reagents, moving gold in and out (Account) and the bank bag
-- slot strip.
--
-- Forever's bank is tabs. Each bank type has purchased tabs, each a container
-- read like a bag (C_Bank.FetchPurchasedBankTabData). On this client a character
-- tab is a bank bag sitting in a slot of the Characterbanktab container; the
-- first tab is the bank's own slots, not a bag. Slots are the game's own bag
-- buttons, so right-click moves an item to the bags, and a right-click in the
-- bags while the bank is open puts it in the bank (the client picks which: the
-- game's panel, which would say, never shows here).

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
    -- The bank shown, in the game's own words for its title.
    local account = Bank.bankType ~= nil and Bank.bankType == enum("Account")
    f.title:SetText(account and (ACCOUNT_BANK_PANEL_TITLE or L["Account bank"]) or (BANK or L["Bank"]))
end

-- The game's bags dim what can't go into the bank shown while its bank panel is
-- up (ItemButtonUtil's BankDepositing context, C_Bank.IsItemAllowedInBankType).
-- That panel never shows here, so the bag window asks this instead.
function Bank.Refuses(bag, slot)
    if not (Bank.open and Bank.bankType ~= nil and ItemLocation) then return false end
    local where = ItemLocation:CreateFromBagAndSlot(bag, slot)
    return call(bankFn("IsItemAllowedInBankType"), Bank.bankType, where) == false
end

local function rematchBags()
    if ns.window and ns.window:IsShown() then ns.Window.MatchAll(ns.window) end
end

-- Why the shown bank can't be used, in the game's words (its lock prompt,
-- BankPanelLockPromptMixin), or nil.
Bank.LOCKED = { BankConversionFailed = "BANK_LOCKED_REASON_BANK_CONVERSION_FAILED",
                BankDisabled = "BANK_LOCKED_REASON_BANK_DISABLED",
                NoAccountInventoryLock = "BANK_LOCKED_REASON_NO_ACCOUNT_INVENTORY_LOCK" }

function Bank.Locked(bankType)
    if bankType == nil then return nil end
    local reason = call(bankFn("FetchBankLockedReason"), bankType)
    if reason == nil then return nil end
    local reasons = Enum and Enum.BankLockedReason or {}
    for key, global in pairs(Bank.LOCKED) do
        if reasons[key] == reason then return _G[global] or L["This bank can't be used right now."] end
    end
    return L["This bank can't be used right now."]
end

-- Why the gold buttons are off, for their tooltip (the game's disabledTooltip).
function Bank.WhyOff()
    local locked = Bank.Locked(Bank.bankType)
    if locked == nil then return nil end
    return ACCOUNT_BANK_ERROR_NO_LOCK or locked
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
        Bank.PaintNote(f)
        ns.Window.Relayout(f)
        ns.Window.FillAll(f)
        if Bank.strip then Bank.RefreshStrip() end
    end
    rematchBags()
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
-- In red while you can't pay it, as the game's cost (canAfford).
local function cost(data)
    local s = money(data.tabCost)
    if data.canAfford == false then s = DUI.Win.Parts.Hex(DUI.Style.INK.BAD) .. s .. "|r" end
    return s
end

local function buyLabel()
    local data = nextTab()
    if not (data and data.tabCost > 0) then return L["Buy tab"] end
    return string.format(L["Buy tab: %s"], cost(data))
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
        return data and data.tabCost > 0 and string.format(L["Costs %s."], cost(data)) or nil
    end)
    f.withdraw = W.TextButton(f, L["Withdraw"])
    f.withdraw:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -W.EDGE, W.EDGE - 3)
    f.withdraw:SetScript("OnClick", function() Bank.AskGold("withdraw") end)
    W.Tip(f.withdraw, L["Withdraw gold"], function() return Bank.WhyOff() or L["Take gold out of the account bank."] end)
    f.deposit = W.TextButton(f, L["Deposit"])
    f.deposit:SetPoint("RIGHT", f.withdraw, "LEFT", -4, 0)
    f.deposit:SetScript("OnClick", function() Bank.AskGold("deposit") end)
    W.Tip(f.deposit, L["Deposit gold"], function() return Bank.WhyOff() or L["Put gold into the account bank, for every character."] end)
end

-- How much gold to move, asked over the bank's gold in Daylight UI's own box:
-- the game's BANK_MONEY_* pop-ups, opened from addon code, would carry its
-- taint into the game's shared pop-ups. A second click on the same button
-- closes it, as the game's buttons do.
Bank.GOLD_KEY = "bankGold"

function Bank.AskGold(which)
    local W = DUI.Widgets
    local asking = W.Asking()
    if asking and asking.key == Bank.GOLD_KEY then
        W.Answer(false)
        if asking.which == which then return end
    end
    local bankType, f = Bank.bankType, Bank.window
    if bankType == nil or not f then return end
    local deposit = which == "deposit"
    W.Ask({ key = Bank.GOLD_KEY, which = which,
        text = deposit and L["Put how much in the account bank?"] or L["Take how much out of the account bank?"],
        yes = deposit and L["Deposit"] or L["Withdraw"], no = CANCEL or L["Cancel"],
        money = { initial = 0 }, owner = f.money,
        width = W.COINS.gold + 2 * W.COINS.small + 2 * W.COINS.gap + W.COINS.glyph + 2 * DUI.Win.EDGE,
        onYes = function(copper)
            local have = deposit and GetMoney() or call(bankFn("FetchDepositedMoney"), bankType)
            if type(have) == "number" and copper > have then
                DUI.ShowError(deposit and (ERR_NOT_ENOUGH_MONEY or L["You don't have enough money."])
                    or L["The account bank doesn't hold that much."])
                return
            end
            local move = bankFn(deposit and "DepositMoney" or "WithdrawMoney")
            if move then DUI.SafeCall(move, bankType, copper) end
        end })
end

-- Leaving the bank closes its question, as the game's bank closes its pop-ups.
local function closeGold()
    local asking = DUI.Widgets.Asking()
    if asking and asking.key == Bank.GOLD_KEY then DUI.Widgets.Answer(false) end
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
    -- Whose gold shows: the account's, or your own on the character bank (the
    -- game's money type PLAYER). A deposit or withdrawal counts to the new amount,
    -- as the footer gold does (MoneyRoll); switching banks shows the other gold at once.
    local whose = holdsGold and "bank" or "player"
    local roll = ns.Setting("moneyRoll") ~= false and f:IsVisible() and f.moneyWhose == whose
    f.moneyWhose = whose
    local amount
    if holdsGold then
        f.money:SetPoint("RIGHT", f.deposit, "LEFT", -8, 0)
        amount = call(bankFn("FetchDepositedMoney"), bankType)
        f.deposit:SetEnabled(call(bankFn("CanDepositMoney"), bankType) == true)
        f.withdraw:SetEnabled(call(bankFn("CanWithdrawMoney"), bankType) == true)
    else
        f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ns.Window.EDGE, ns.Window.EDGE)
        amount = GetMoney and GetMoney() or 0
    end
    local coins = DUI.Widgets.Money
    if roll then DUI.Motion.CountTo(f.money, amount, coins, DUI.Motion.SLOW)
    else DUI.Motion.CountTo(f.money, nil, function() return coins(amount) end) end
end

-- In place of the slots: why a locked bank can't be used (the game's lock
-- prompt), or what an account bank with no tab bought is (its purchase prompt,
-- in the game's own title and text).
function Bank.NoteText(bankType)
    local locked = Bank.Locked(bankType)
    if locked then return locked end
    if bankType == nil or bankType == enum("Character") or #Bank.List() > 0 then return nil end
    if call(bankFn("CanPurchaseBankTab"), bankType) ~= true then return nil end
    local data = nextTab()
    local body = data and data.purchasePromptBody
    if type(body) ~= "string" or body == "" then return nil end
    local title = data.purchasePromptTitle
    if type(title) == "string" and title ~= "" then
        return DUI.Win.Parts.Hex(DUI.Style.INK.VALUE) .. title .. "|r\n" .. body
    end
    return body
end

function Bank.PaintNote(f)
    local text = Bank.NoteText(Bank.bankType)
    f.bankNote:SetText(text or "")
    f.bankNote:SetShown(text ~= nil)
end

-- Room for the note where the slots would be.
local function noteRoom(f)
    if not (f.bankNote and f.bankNote:IsShown()) then return 0 end
    local h = f.bankNote:GetStringHeight()
    return (type(h) == "number" and math.ceil(h) or DUI.Style.SIZE.body) + 2 * ns.Window.GAP
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
    -- From the second tab: the first is the bank's own slots, not a bag slot
    -- (the game's bag row skips it too).
    for i = 2, max do
        local function pick() local c, s = bagSlot(i); if c then DUI.SafeCall(C_Container.PickupContainerItem, c, s) end end
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
        strip.slots[#strip.slots + 1] = b
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
    for _, b in ipairs(strip.slots) do
        local i = b.index
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
-- on the kit's aside holder, where the game's show really shows it. After that it's parked
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
    local home = hasTab and hidden or DUI.Win.Followers.aside
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
    Bank.PaintNote(f)
    ns.Window.Relayout(f)
    f:Show()
    Bank.RefreshStrip()
    rematchBags()
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
        itemsMin = function(w) return noteRoom(w) end,
        tools = {
            { key = "sort", icon = W.SORT_ICON, title = L["Clean up the bank"],
              onClick = function(w)
                  if InCombatLockdown and InCombatLockdown() then return end
                  -- Nothing to sort before a tab is bought (the game's Clean Up skips it too).
                  local n = Bank.bankType ~= nil and call(bankFn("FetchNumPurchasedBankTabs"), Bank.bankType)
                  if type(n) == "number" and n == 0 then return end
                  if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then
                      DUI.SafeCall(PlaySound, SOUNDKIT.UI_BAG_SORTING_01)
                  end
                  W.BeginSort(w)
                  ns.Keep.TellGame()
                  if C_Container.SortBank and Bank.bankType then DUI.SafeCall(C_Container.SortBank, Bank.bankType)
                  elseif C_Container.SortBankBags then DUI.SafeCall(C_Container.SortBankBags) end
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
    -- The game's bank window plays no sound of its own (the bags it opens play
    -- theirs), so under the game's sounds this one stays quiet too.
    f.duiGameSounds = { open = false, close = false }
    f.bankNote = DUI.Style.Text(f.items, DUI.Style.SIZE.body, "CENTER")
    f.bankNote:SetPoint("TOPLEFT", f.items, "TOPLEFT", 0, -ns.Window.GAP)
    f.bankNote:SetPoint("TOPRIGHT", f.items, "TOPRIGHT", 0, -ns.Window.GAP)
    f.bankNote:SetWordWrap(true)
    DUI.Style.InkText(f.bankNote, "LABEL")
    f.bankNote:Hide()
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
    -- never gets. The bag is shown here instead, never through the game's
    -- OpenAllBags (OC.Hold says why), and closed with the bank if it was opened for it.
    DUI.RegisterEvent("BANKFRAME_OPENED", function()
        Bank.open = true
        Bank.Open()
        Bank.Reread()
        Bank.openedBags = ns.OpenClose.Hold() or Bank.openedBags
    end)
    DUI.RegisterEvent("BANKFRAME_CLOSED", function()
        Bank.open = false
        closeGold()
        Bank.Close()
        rematchBags()
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
        DUI.RegisterEvent(e, function()
            if f:IsShown() then
                Bank.PaintNote(f)
                W.Changed(f)
                Bank.RefreshStrip()
            end
            ns.Saved.SaveBankSoon()
        end)
    end
    -- A bank bag swapped: the game's bag buttons refresh on this one too.
    DUI.RegisterEvent("BAG_CONTAINER_UPDATE", function()
        if f:IsShown() then Bank.RefreshStrip() end
    end)
    -- Account bank gold only appears in the footer.
    DUI.RegisterEvent("ACCOUNT_MONEY", function() W.UpdateFooter(f) end)
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
        Bank.PaintNote(f)
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
