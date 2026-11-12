-- Spellbook and talents window.
-- The game's PlayerSpellsFrame stays alive but hidden under a veil
-- (Win.Follow). The game still decides when it opens and closes (keys, micro
-- menu, Escape, loading screens, other addons) and its own scripts and
-- EventRegistry events still run; this window just shows in its place.
--
-- With fightBook on (Fight.lua), a secure layer takes over in combat for
-- casting, scrolling, tabs and closing, and gets the keys. While it holds the
-- book (Fight.Holds), the game frame's show/hide is ignored. After combat an
-- open window gets the game frame reopened underneath, so the game's keys
-- close both again.
--
-- With fightBook off, or with the controller UI, the game's own book is used
-- in combat (it's the only one that allows dragging spells). On
-- PLAYER_REGEN_DISABLED, just before lockdown, the hidden game frame is
-- unparked so the keys open it, and it's parked again once closed after
-- combat. A window already open when combat starts stays until closed.
--
-- Inspecting someone else's talents and the spec tab are left to the game's
-- frame; this window only covers your own spells and talents.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local L = DUI.L
local Win = DUI.Win

local Book = {}
ns.Window = Book

Book.NAME = "DaylightUIBook"
Book.SIZE = { spells = { 600, 600 }, talents = { 720, 563 }, training = { 600, 600 } }
Book.TOP = -104   -- fallback when there's no game frame to read: the game's center panel spot

-- Fallback class icons from the core media, used when the UnitFrames module
-- isn't loaded to report the chosen icon style.
Book.ICONS = { WARRIOR = "warrior.tga", PALADIN = "paladin.tga", HUNTER = "hunter.tga", ROGUE = "rogue.tga",
    PRIEST = "priest.tga", SHAMAN = "shaman.tga", MAGE = "mage.tga", WARLOCK = "warlock.tga", DRUID = "druid.tga" }

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

function Book.Game()
    local g = _G.PlayerSpellsFrame
    return type(g) == "table" and g or nil
end

-- Map the game's tab id to a page. nil for tabs this window doesn't cover (spec).
function Book.PageOf(tabID)
    if tabID == nil then return nil end
    local g = Book.Game()
    if tabID == ((g and g.spellBookTabID) or 3) then return "spells" end
    if tabID == ((g and g.talentTabID) or 2) then return "talents" end
    return nil
end

-- True when the game frame shows your own spells or talents, i.e. not an
-- inspected tree and not the spec tab.
function Book.Ours(g)
    if type(g.IsInspecting) == "function" and g:IsInspecting() then return false end
    return Book.PageOf(type(g.GetTab) == "function" and g:GetTab() or nil) ~= nil
end

-- ---------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------

local function header(f, page)
    local title = page == "talents" and (TALENTS or L["Talents"])
        or page == "training" and L["Training"] or (SPELLBOOK or L["Spellbook"])
    local className = type(UnitClass) == "function" and UnitClass("player") or nil
    local level = Book.level or (type(UnitLevel) == "function" and UnitLevel("player")) or nil
    local sub = (type(className) == "string" and type(level) == "number") and string.format(L["%s · Level %d"], className, level) or ""
    Win.SetTitle(f, title, nil, sub)
end

-- Use the class icon style picked in the unit frame settings (DUI.ClassIcon),
-- else the fallback set.
local function classIcon(f)
    local _, token = UnitClass("player")
    local file, l, r, t, b
    if type(token) == "string" then
        if DUI.ClassIcon then file, l, r, t, b = DUI.ClassIcon(token) end
        if not file and Book.ICONS[token] then
            file, l, r, t, b = DUI.MEDIA .. "class\\" .. Book.ICONS[token], 0, 1, 0, 1
        end
    end
    if file then
        f.portrait:SetTexture(file)
        f.portrait:SetTexCoord(l, r, t, b)
    end
    f.portrait:SetShown(file and true or false)
    f.portraitRim:SetShown(file and true or false)
end

-- The dragged position (saved per profile through Win.Spot), else centered
-- under the top of where the game would open its frame. The game frame's
-- position is read once on open, never anchored to, since it's protected.
local function spot() return Book.spot and Book.spot.Get() end

local function place(f)
    if ns.Fight and ns.Fight.Place(f) then return end   -- in combat, follow the secure layer
    local s = spot()
    if s then return Win.PlaceTop(f, s[1], s[2]) end
    local g = Book.Game()
    local x, top
    if g then
        local cx, t = g:GetCenter(), g:GetTop()
        if type(cx) == "number" and type(t) == "number" then
            local k = (g:GetEffectiveScale() or 1) / (f:GetEffectiveScale() or 1)
            x, top = cx * k, t * k
        end
    end
    f:ClearAllPoints()
    if x then f:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top) else f:SetPoint("TOP", UIParent, "TOP", 0, Book.TOP) end
end
Book.Place = place

-- Switches this window's page only; the game frame keeps its own tab.
function Book.Show(page)
    local f = Book.frame
    page = page or "spells"
    Win.PickTab(f, page)
    header(f, page)
    Win.ShowPage(f, page)
    if Book.follow then Win.Followers.WriteWidth(Book.follow) end
end

function Book.Open(page)
    local f = Book.frame
    if Win.IsOpen(f) then return Book.Show(page) end
    if ns.Talents then ns.Talents.group = nil end   -- open talents on the active set, like the game
    place(f)
    classIcon(f)
    Book.Show(page)
    Win.Open(f)
end

-- A hovered row that hides never gets OnLeave, so hide the cast button
-- here and let Win.Shut drop the tooltip. Otherwise the spell tooltip
-- stayed on screen.
local function shut(f)
    if ns.Cast then ns.Cast.Hide() end
    Win.Shut(f)
end

-- Close this window now and the game frame with HideUIPanel. In combat
-- HideUIPanel is blocked for addon code, so that part waits.
function Book.Close()
    local f = Book.frame
    if not f then return end
    shut(f)
    local g = Book.Game()
    if not (g and g:IsShown()) then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function()
            local now = Book.Game()
            if now and now:IsShown() and not Win.IsOpen(Book.frame) then HideUIPanel(now) end
        end, "book:close")
        return
    end
    HideUIPanel(g)
end

-- Hand an inspected tree or the spec tab over to the game's window.
local function lend()
    if Win.IsOpen(Book.frame) then shut(Book.frame) end
    if Win.Followers.Lend(Book.follow, "book") then return end
    DUI.AfterCombat(function()
        local g = Book.Game()
        if g and g:IsShown() and not Book.Ours(g) then Win.Followers.Lend(Book.follow, "book") end
    end, "book:lend")
end

-- Win.Follow callback: the game frame was shown or hidden.
function Book.Changed(_, shown)
    local f = Book.frame
    if ns.Fight and ns.Fight.Holds() then return end   -- the secure layer is in charge
    if not shown then
        if Win.IsOpen(f) then shut(f) end
        return
    end
    local g = Book.Game()
    if not g then return end
    if not Book.Ours(g) then return lend() end
    Book.Open(Book.PageOf(g:GetTab()))
end

-- The game switched tabs, from a key press or an inspect.
function Book.OnTabSet(_, _, tabID)
    Book.SideArea()
    if ns.Fight and ns.Fight.Holds() then return end
    if not (Book.follow and Win.Followers.Shown(Book.follow, "book")) then return end
    local g = Book.Game()
    if g and not Book.Ours(g) then return lend() end
    local page = Book.PageOf(tabID)
    if not page then return end
    if not Win.IsOpen(Book.frame) then return Book.Open(page) end   -- closed by its X in combat while the game frame stayed up
    if page ~= Book.frame.current then Book.Show(page) end
end

-- TrySetTab makes the talents tab a "center" panel, which closes every other
-- window. This window can share the screen, so use the spellbook's
-- "centerOrLeft" instead. Inspects keep the game's setting, and the call is
-- refused in combat.
function Book.SideArea()
    local g = Book.Game()
    if not g or InCombatLockdown() or type(SetUIPanelAttribute) ~= "function" then return end
    if not Book.Ours(g) then return end
    pcall(SetUIPanelAttribute, g, "area", "centerOrLeft")
end

-- Arm the secure layer, or hand the game its book for this fight.
function Book.FightStarts()
    if ns.Fight and ns.Fight.Arm() then return end
    if Book.follow then Win.Followers.Unpark(Book.follow, "book") end
end

-- A window opened in combat by the secure keys has no game frame behind it.
-- Reopen the game frame (hidden) on the same page so its keys and Escape
-- close both again.
function Book.FightEnds()
    if not (ns.Fight and ns.Fight.Disarm()) then return end
    local f, g = Book.frame, Book.Game()
    if not Win.IsOpen(f) or (g and g:IsShown()) then return end
    local U = _G.PlayerSpellsUtil
    if type(U) ~= "table" then return end
    local open = f.current == "talents" and U.OpenToClassTalentsTab or U.OpenToSpellBookTab
    if type(open) == "function" then pcall(open) end
end

-- Saved directly, without a SettingChanged, since nothing needs refilling.
function Book.SaveSpot(x, y) Book.spot.Save(x, y) end

-- The resized size from Win.Resizable, else the default from Book.SIZE.
function Book.PageSize(id)
    if Book.sizer then return Book.sizer.Size(id) end
    local s = Book.SIZE[id] or Book.SIZE.spells
    return s[1], s[2]
end

-- While dragging (live), only stretch or move the trees; refill fully when
-- the drag ends.
function Book.Resized(w, h, live)
    local f = Book.frame
    if not (f and Win.IsOpen(f)) then return end
    local page = f.pages[f.current]
    if f.current == "talents" then
        local T = ns.Talents
        if live and T.data and #T.data.trees > 0 then
            T.Layout(page, T.data, w, h)
            T.Search(page.search:GetText() or "")
        elseif not live then
            T.Fill(page)
        end
    elseif f.current == "spells" then
        if live then page.stack:Stretch() else ns.Spells.Fill(page, true) end
    elseif f.current == "training" then
        if live then page.stack:Stretch() else ns.Training.Refresh() end
    end
end

-- Header right-click or /dui reset: back to the default position and sizes.
function Book.ResetSpot()
    if not (ns.module and ns.module.db) then return end
    if Book.sizer then Book.sizer.Reset() end
    return Book.spot.Reset()
end

function Book.Apply()
    local f = Book.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end   -- keep the dragged position at the new scale
    Win.Repaint(f)
    local talents = f.pages.talents
    if talents and talents:IsVisible() then ns.Talents.Fill(talents) end   -- repaint accent rings and glows
    local spells = f.pages.spells
    if spells and spells:IsVisible() then ns.Spells.Fill(spells, true)
    elseif ns.Spells then ns.Spells.dirty = true end   -- refill on next use, including combat cast buttons
    local training = f.pages.training
    if training and training:IsVisible() then ns.Training.Refresh() end   -- repaint accent and gold
    if Book.follow then Win.Followers.WriteWidth(Book.follow) end
end

-- ---------------------------------------------------------------------
-- A controller: each page brings the game's own buttons for it (the
-- spellbook's, the talents', the trainer list's). LB and RB step what the
-- page has to step (schools, talent sets, chips), else the window's tabs.
-- ---------------------------------------------------------------------

local function headerTabs(f)
    local out, at = {}, nil
    for _, b in ipairs(f.tabs or {}) do
        if b:IsShown() then
            out[#out + 1] = b
            if b.id == f.current then at = #out end
        end
    end
    return out, at
end

local PAGE_TABS = { spells = "Spells", talents = "Talents", training = "Training" }

local function pageTabs(f)
    local part = ns[PAGE_TABS[f.current] or ""]
    if part and part.PadTabs then
        local list, at = part.PadTabs()
        if #list > 1 then return list, at, true end
    end
    local list, at = headerTabs(f)
    return list, at, false
end

function Book.PadSetup(f)
    local function on(page) return function() return f.current == page end end
    local list = {}
    local function add(entries) for _, e in ipairs(entries) do list[#list + 1] = e end end
    add(ns.Spells.PadKeys(on("spells")))
    add(ns.Talents.PadKeys(on("talents")))
    f.padKeys = list
    f.padSelect = function(b)
        if f.current == "talents" then return ns.Talents.PadSelect(b) end
        -- A casts through its secure key; a row it can't cast does nothing.
        if f.current == "spells" and type(b) == "table" and b.cell then return false end
        return nil
    end
    f.padTabs = function()
        local items, at = pageTabs(f)
        return items, at
    end
    f.padTabsLabel = function()
        local _, _, own = pageTabs(f)
        if not own then return L["Tabs"] end
        if f.current == "talents" then return L["Talent sets"] end
        return CATEGORIES or L["Categories"]
    end
end

function Book.Build(mod)
    ns.module = mod
    if Book.frame then return Book.frame end
    local S = Book.SIZE
    local f = Win.New({ name = Book.NAME, back = "Book", w = S.spells[1], h = S.spells[2], portrait = true })
    Book.frame = f
    f.onClose = Book.Close
    Book.spot = Win.Spot(f, function() return ns.module and ns.module.db end, place)
    local SP = ns.Spells
    Win.AddPage(f, "spells", { Build = SP.Build, Fill = SP.Fill, w = S.spells[1], h = S.spells[2], pieces = SP.Pieces })
    local T = ns.Talents
    Win.AddPage(f, "talents", { Build = T.Build, Fill = T.Fill, w = S.talents[1], h = S.talents[2], pieces = T.Pieces })
    Win.Build(f, "spells")
    Win.Build(f, "talents")
    -- Training tab only when What's Training is loaded (Training.lua).
    local tabs = { { id = "spells", text = SPELLBOOK or L["Spellbook"] }, { id = "talents", text = TALENTS or L["Talents"] } }
    local TR = ns.Training
    if TR and TR.On() then
        Win.AddPage(f, "training", { Build = TR.Build, Fill = TR.Fill, w = S.training[1], h = S.training[2], pieces = TR.Pieces })
        Win.Build(f, "training")
        tabs[#tabs + 1] = { id = "training", text = L["Training"] }
    end
    Win.Drag(f, { save = Book.SaveSpot, reset = Book.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Book", "scale", v) end)
    Book.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end,
        base = function(id) local s = S[id] or S.spells; return s[1], s[2] end,
        save = Book.SaveSpot, resized = Book.Resized, follow = function() return Book.follow end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Book.ResetSpot   -- /dui reset
    Win.Tabs(f, tabs, Book.Show)
    if ns.Fight then ns.Fight.Build(f) end   -- after close and tabs exist, since the layer covers them
    Book.PadSetup(f)
    local reg = _G.EventRegistry
    if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
        reg:RegisterCallback("PlayerSpellsFrame.TabSet", Book.OnTabSet, Book)
    end
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() Book.FightStarts() end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() Book.FightEnds() end)
    DUI.RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
        Book.level = type(level) == "number" and level or nil
        if Win.IsOpen(f) then header(f, f.current) end
    end)
    Book.follow = Win.Follow({ key = "book", frames = { book = Book.Game }, veil = { book = true }, changed = Book.Changed,
        width = function() return (Book.PageSize(f.current or "spells")) * Win.Scale(ns.Setting("scale")) end })
    Book.Apply()
    return f
end
