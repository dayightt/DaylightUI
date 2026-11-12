-- The spellbook binder. Adds a "Click-cast" switch at the top of the game's
-- spellbook. While it's on, a catcher frame is laid over the icon of the spell
-- under the mouse. Clicking it (any button, with Shift, Ctrl or Alt) binds that
-- click to the spell (ClickCast.lua), and the same click again removes it.
--
-- The game's spellbook is only read, never touched: no method hooks, no fields
-- written, nothing parented to it. EventRegistry reports when it shows and
-- hides. The switch and catcher sit on UIParent one strata above it (B.Above).
-- This code never opens the book either, since that would run the spellbook
-- under addon taint and casting from it could get blocked. Instead, "Bind in
-- spellbook" on the options page is a secure macro button that clicks the
-- game's own spellbook micro button (B.Opener). Closing the book ends the
-- mode, and if it was started from the options page, the page comes back.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local B = {}
ns.ClickBinder = B

B.on = false          -- binding mode
B.SCAN = 0.05         -- how often to look for the spell under the mouse
B.PAGE = "UnitFrames.clickcast"
-- The game's spellbook button (Blizzard_MicroMenu). Clicking it opens the book
-- in the game's own code, wherever the micro menu is.
B.BOOK_BUTTON = "SpellbookMicroButton"

local CC = ns.ClickCast
local function UI() return DUI.Widgets end

-- The switch and catcher draw one strata above the spellbook. Its page is at
-- frameLevel 100 inside a toplevel window the game raises on every click, so
-- no frame level beside it stays on top. Under the page's dark background the
-- switch looked grayed out and clicks went to the book.
B.STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
function B.Above(frame)
    local strata = frame:GetFrameStrata()
    for i, s in ipairs(B.STRATA) do
        if s == strata then return B.STRATA[math.min(i + 1, #B.STRATA)] end
    end
    return "DIALOG"
end

-- The game's spellbook page, once its addon has loaded.
function B.Book()
    local f = _G.PlayerSpellsFrame
    local book = type(f) == "table" and f.SpellBookFrame
    if type(book) ~= "table" or type(book.IsShown) ~= "function" then return nil end
    return book
end

local function bookShown()
    local book = B.Book()
    return book ~= nil and book:IsShown() == true
end

-- What a spellbook entry would bind: { spell, name, rank } for a castable spell
-- of yours. No passives, nothing unlearned or from another specialization, no
-- pet actions or flyouts.
function B.EntryOf(item)
    if type(item) ~= "table" or item.isUnlearned then return nil end
    local info = item.spellBookItemInfo
    if type(info) ~= "table" then return nil end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
    if item.spellBank ~= bank or info.itemType ~= spellType or info.isPassive or info.isOffSpec then return nil end
    local spell = info.spellID or info.actionID
    if type(spell) ~= "number" or type(info.name) ~= "string" then return nil end
    return { spell = spell, name = info.name, rank = type(info.subName) == "string" and info.subName or nil }
end

-- The spell entry under the mouse, if any.
function B.Hovered()
    local book = B.Book()
    local paged = book and book.PagedSpellsFrame
    if type(paged) ~= "table" or type(paged.EnumerateFrames) ~= "function" then return nil end
    for _, item in paged:EnumerateFrames() do
        local icon = type(item) == "table" and item.Button
        if type(icon) == "table" and icon.IsVisible and icon:IsVisible() and icon:IsMouseOver() then
            local entry = B.EntryOf(item)
            if entry then return item, icon, entry end
        end
    end
end

-- The catcher, laid over the hovered spell's icon

local function showTip(c)
    local entry = c.entry
    if not (entry and GameTooltip) then return end
    GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
    local Tips = DUI.Tips
    Tips.Clear()
    Tips.Title(entry.rank and (entry.name .. " (" .. entry.rank .. ")") or entry.name)
    Tips.Text(L["Click with the mouse button you want, holding Shift, Ctrl or Alt if you like: "
        .. "that click on a unit frame then casts it on that unit."])
    local clicks = CC.ClicksFor(entry.spell)
    if #clicks > 0 then
        Tips.Gap()
        for _, text in ipairs(clicks) do Tips.Sub(text) end
        Tips.Hint(L["The same click again removes it."])
    end
    if InCombatLockdown() then Tips.Text(L["Takes effect once this fight is over."], Tips.WARN) end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function makeCatcher()
    local W = UI()
    local c = CreateFrame("Button", nil, UIParent)
    c:RegisterForClicks("AnyUp")
    c:Hide()
    c.ring = W.Round(c, "OVERLAY", 0, true)
    c.ring:SetPoint("TOPLEFT", c, "TOPLEFT", -3, 3)
    c.ring:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 3, -3)
    W.TintDaylight(c.ring)
    c.glow = W.Round(c, "ARTWORK")
    c.glow:SetAllPoints(c)
    W.TintDaylight(c.glow, 0.18)
    c:SetScript("OnClick", function(self, button) B.Click(button) end)
    c:SetScript("OnEnter", showTip)
    c:SetScript("OnLeave", function(self)
        self:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return c
end

-- Lays the catcher over icon for entry.
function B.Place(icon, entry)
    local c = B.catcher
    c.entry = entry
    c:ClearAllPoints()
    c:SetAllPoints(icon)
    c:SetFrameStrata(B.Above(icon))
    c:Show()
    if c:IsMouseOver() then showTip(c) end
end

-- A click on the catcher binds (or unbinds) that click.
function B.Click(button)
    local c = B.catcher
    local entry = c and c.entry
    if not entry then return end
    local done = CC.Toggle(CC.Mods(), button, entry.spell, entry.name, entry.rank)
    if DUI.Sound then DUI.Sound.Play(done == "bound" and "snap" or "click") end
    if DUI.Motion and DUI.Motion.Bump then DUI.Motion.Bump(c) end
    showTip(c)
end

-- The mode and the switch

local driver = CreateFrame("Frame")
driver:Hide()
local since = 0
driver:SetScript("OnUpdate", function(_, dt)
    since = since + (dt or 0)
    if since < B.SCAN then return end
    since = 0
    local c = B.catcher
    if not c then return end
    if c:IsShown() and c:IsMouseOver() then return end
    local _, icon, entry = B.Hovered()
    if icon then B.Place(icon, entry) else c:Hide() end
end)

function B.Driver() return driver end

-- The scan runs only while the mode is on and the spellbook is shown. Never
-- with the Daylight book window: the game's book is veiled under it and that
-- page binds by itself (DUI.ClickBind).
local function wake()
    local run = B.on and bookShown() and B.catcher ~= nil and not DUI.bookOwnWindow
    driver:SetShown(run)
    if not run and B.catcher then B.catcher:Hide() end
end

function B.SetMode(on)
    on = on and not CC.Stepped() or false
    if B.on == on then return end
    B.on = on
    if B.toggle then B.toggle.SetActive(on) end
    wake()
    DUI.Fire("ClickCastChanged")
    local panel = DUI.OptionsPanel
    if panel and type(panel.IsShown) == "function" and panel.IsShown() and type(panel.Refresh) == "function" then
        panel.Refresh()
    end
end

-- The key that opens the spellbook, for the options page's hint.
function B.BookKey()
    if type(GetBindingKey) ~= "function" then return nil end
    for _, action in ipairs({ "TOGGLESPELLBOOK", "TOGGLEPLAYERSPELLSFRAME" }) do
        local key = GetBindingKey(action)
        if type(key) == "string" and key ~= "" then return key end
    end
end

local function makeToggle()
    local W = UI()
    local t = W.Button(UIParent, L["Click-cast"], 22)
    t.FitWidth(84)
    t:Hide()
    t:SetScript("OnClick", function() B.SetMode(not B.on) end)
    t:HookScript("OnEnter", function(self)
        W.Tooltip(self, L["Click-cast"], L["Switch on, then click a spell with the mouse button you want "
            .. "(hold Shift, Ctrl or Alt for more): that click on a unit frame casts it. "
            .. "Closing the spellbook switches it off. /dui > Unit Frames > Click-casting lists them."])
    end)
    t:HookScript("OnLeave", W.HideTooltip)
    t.SetActive(B.on)
    return t
end

-- Beside the book's search box in its top bar, above the book.
local function placeToggle(book)
    local t = B.toggle
    t:ClearAllPoints()
    local search = book.SearchBox
    if type(search) == "table" and type(search.GetLeft) == "function" then
        t:SetPoint("RIGHT", search, "LEFT", -10, 0)
    else
        t:SetPoint("TOPRIGHT", book, "TOPRIGHT", -300, -24)
    end
    t:SetFrameStrata(B.Above(_G.PlayerSpellsFrame))
end

function B.OnBookShown()
    local book = B.Book()
    -- Nothing to bind to while the unit frames are off.
    if not (book and B.toggle and ns.module) or CC.Stepped() then return end
    -- The Daylight book window veils the game's, so a switch here would float
    -- over its header with nothing to bind below it.
    if DUI.bookOwnWindow then return end
    placeToggle(book)
    B.toggle.SetActive(B.on)
    B.toggle:Show()
    wake()
end

-- The book's page hides (also when switching to the talents tab). The mode
-- stays on for when it comes back.
function B.OnBookHidden()
    if B.toggle then B.toggle:Hide() end
    wake()
end

-- The whole window closed, so binding is over. If started from the options
-- page, the page comes back with the new bindings, one frame later since an
-- Escape that closed the book is still closing windows.
function B.OnBookClosed()
    local back = B.fromOptions
    B.fromOptions = nil
    B.SetMode(false)
    if not back or InCombatLockdown() then return end
    local function reopen()
        local panel = DUI.OptionsPanel
        if panel and type(panel.Show) == "function" and not InCombatLockdown() then panel.Show(B.PAGE) end
    end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, reopen) else reopen() end
end

-- Opening the book from the options page

-- A secure macro button (`/click SpellbookMicroButton`), so the game's own code
-- opens the book and it never runs under addon taint. Created out of combat on
-- UIParent and laid over the options page's button only while the mouse is on
-- it, positioned by screen coordinates and never anchored to addon frames. Its
-- PostClick (mouse up, the macro may have run on the way down) turns binding
-- on and moves the options window aside.
local function makeOpener()
    local ok, o = pcall(CreateFrame, "Button", "DaylightUIClickCastOpener", UIParent, "SecureActionButtonTemplate")
    if not ok or type(o) ~= "table" then return nil end
    o:SetAttribute("type", "macro")
    o:SetAttribute("macrotext", "/click " .. B.BOOK_BUTTON)
    o:RegisterForClicks("AnyUp", "AnyDown")
    o:SetFrameStrata("FULLSCREEN_DIALOG")
    o:Hide()
    -- It takes the mouse from the button under it, which keeps its hover look
    -- and its row's tooltip.
    o:SetScript("OnEnter", function(self)
        local b, W = self.over, UI()
        if b and b.Paint then b.Paint(true) end
        if self.row and self.row.Enter then self.row.Enter() end
    end)
    o:SetScript("OnLeave", function(self)
        local b, W = self.over, UI()
        if b and b.Paint then b.Paint(false) end
        if self.row and self.row.Leave then self.row.Leave() else W.HideTooltip() end
        if not InCombatLockdown() then self:Hide() end
    end)
    o:SetScript("PostClick", function(self, _, down)
        if down then return end
        if not InCombatLockdown() then self:Hide() end
        -- The same click closes an already open book, so there's nothing to turn on.
        if not bookShown() then return end
        B.fromOptions = true
        B.SetMode(true)
        local panel = DUI.OptionsPanel
        if panel and type(panel.IsShown) == "function" and panel.IsShown() and type(panel.Toggle) == "function" then
            panel.Toggle()
        end
    end)
    return o
end

-- Lays the opener over the options button b of row (from b's OnEnter). Skipped
-- in combat, while binding is on (b stops it then), with Clique, or without
-- the game's spellbook button. b's own click is the fallback.
function B.Opener(b, row)
    if InCombatLockdown() or B.on or CC.Stepped() or type(_G[B.BOOK_BUTTON]) ~= "table" then return nil end
    if not B.opener then B.opener = makeOpener() end
    local o = B.opener
    if not o then return nil end
    local left, bottom, w, h = b:GetLeft(), b:GetBottom(), b:GetWidth(), b:GetHeight()
    if type(left) ~= "number" or type(bottom) ~= "number" then return nil end
    local s = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
    o.over, o.row = b, row
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
    o:SetSize(w * s, h * s)
    o:SetFrameLevel((b:GetFrameLevel() or 0) + 20)
    o:Show()
    return o
end

-- The Daylight spellbook page (Book/Spells.lua) binds through this. The switch
-- sits on that page and a click on a spell row binds that click.

DUI.ClickBind = {
    -- Whether the page shows the switch at all: unit frames on and no Clique.
    Usable = function() return ns.module ~= nil and ns.module.enabled == true and not CC.Stepped() end,
    On = function() return B.on end,
    Set = function(on) B.SetMode(on) end,
    -- What a row on the page would bind: a castable spell of yours.
    Entry = function(cell)
        if type(cell) ~= "table" or cell.passive or cell.future or cell.pet then return nil end
        if type(cell.spellID) ~= "number" or type(cell.name) ~= "string" then return nil end
        return { spell = cell.spellID, name = cell.name, rank = cell.rank }
    end,
    -- A click on a row binds or unbinds that click. Returns "bound" or "removed".
    Click = function(entry, button)
        local done = CC.Toggle(CC.Mods(), button, entry.spell, entry.name, entry.rank)
        if DUI.Sound then DUI.Sound.Play(done == "bound" and "snap" or "click") end
        return done
    end,
    Clicks = function(spell) return CC.ClicksFor(spell) end,
}

-- Just before lockdown, the last moment a secure frame may hide.
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if B.opener then B.opener:Hide() end
end)

-- Once the game's spellbook exists. Its addon loads on demand.
function B.Setup()
    if B.toggle or CC.Stepped() or not B.Book() then return end
    if not DUI.Widgets then return end
    B.toggle = makeToggle()
    B.catcher = makeCatcher()
    if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.Show", B.OnBookShown, B)
        EventRegistry:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.Hide", B.OnBookHidden, B)
        EventRegistry:RegisterCallback("PlayerSpellsFrame.CloseFrame", B.OnBookClosed, B)
    end
    if bookShown() then B.OnBookShown() end
end

DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_PlayerSpells" then B.Setup() end
end)
DUI.RegisterEvent("PLAYER_LOGIN", function()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" and C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
        B.Setup()
    end
end)
