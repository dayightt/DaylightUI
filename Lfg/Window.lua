-- Group finder window with three tabs: List yourself (Listing.lua, first), Find a group
-- (Browse.lua) and Who (Who.lua). The game still runs its group finder: its key, the
-- micro button and the queue eye open LFGParentFrame (Blizzard_GroupFinder_VanillaStyle),
-- which is parked under the kit's hidden frame (Win.Follow). This window shows in its
-- place and closes with it, and closing this one hides the game's.
--
-- Searching, listing and /who are all allowed from addon code, but only from a click or
-- key (the client's rule for restricted calls), so opening the window never searches on
-- its own; a tab or chip does. Works in combat too, like the NPC window: nothing here is
-- protected (the game's frame, its note box), so parking, borrowing and closing all
-- work. A search or listing the game refuses mid-fight just doesn't happen.

local _, DUI = ...
DUI.Lfg = DUI.Lfg or {}
local ns = DUI.Lfg
local L = DUI.L
local Win = DUI.Win
local Style = DUI.Style

local Lfg = {}
ns.Window = Lfg

Lfg.NAME = "DaylightUILfg"
Lfg.W, Lfg.H = 460, 560
Lfg.MIN_H = 420   -- min height for the resize grip (min width is Lfg.W)
Lfg.ICON = "Interface\\Icons\\INV_Misc_GroupLooking"
Lfg.PAGES = { "list", "find", "who" }

Lfg.page = "list"   -- page to open on: the last one shown this session; List yourself first, like the game

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

function Lfg.Game()
    local g = _G.LFGParentFrame
    return type(g) == "table" and g or nil
end

-- Header: title, current listing, tabs

function Lfg.Header()
    local f = Lfg.frame
    if not f then return end
    local e = ns.Data.Entry()
    local sub
    if e then
        local names = {}
        for _, id in ipairs(e.activityIDs) do names[#names + 1] = ns.Data.ActivityName(id) end
        sub = string.format(L["Listed: %s"], Win.Parts.Hex(Style.INK.VALUE) .. table.concat(names, ", ") .. "|r")
    else
        sub = L["Not listed"]
    end
    Win.SetTitle(f, LFG_TITLE or L["Group Finder"], nil, sub)
end

-- Tab click shows that page. Since it's a real click, the page may query the game:
-- Find searches the first time, Who asks for the player's level.
function Lfg.ShowTab(id, clicked)
    local f = Lfg.frame
    if not f then return end
    Lfg.page = id
    Win.PickTab(f, id)
    Win.ShowPage(f, id)
    if clicked then
        if id == "find" and not ns.Browse.searched then ns.Browse.Search() end
        if id == "who" and not ns.Who.asked then ns.Who.Send("") end
    end
end

-- New listing: go to Find a group, where the game searches for it.
function Lfg.Listed()
    Lfg.Header()
    ns.Browse.Listed()
    if Lfg.frame and Win.IsOpen(Lfg.frame) then Lfg.ShowTab("find") end
end

-- Open, close, follow the game's frame

local function spot() return Lfg.spot and Lfg.spot.Get() end

local function place(f)
    local s = spot()
    if s then return Win.PlaceTop(f, s[1], s[2]) end
    f:ClearAllPoints()
    local g = Lfg.Game()
    if g then f:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

function Lfg.Open(page)
    local f = Lfg.frame
    if not f then return end
    if page then Lfg.page = page end
    Lfg.Header()
    if Win.IsOpen(f) then return Lfg.ShowTab(Lfg.page) end
    place(f)
    Lfg.ShowTab(Lfg.page)
    Win.Open(f)
    if Lfg.follow then Win.Followers.WriteWidth(Lfg.follow) end
end

-- Closing under the mouse: the hovered piece never gets OnLeave.
local function shut(f)
    local tip = GameTooltip
    local owner = tip and tip:IsShown() and tip:GetOwner()
    while owner do
        if owner == f then tip:Hide(); break end
        owner = owner:GetParent()
    end
    if DUI.Widgets.CloseMenu then DUI.Widgets.CloseMenu() end
    Win.Close(f)
end

-- Close this one now; the game's closes its own way (HideUIPanel), deferred until after
-- combat only if the game ever makes its frame protected.
function Lfg.Close()
    local f = Lfg.frame
    if not f then return end
    shut(f)
    local g = Lfg.Game()
    if not (g and g:IsShown()) then return end
    if InCombatLockdown() and g:IsProtected() then
        DUI.AfterCombat(function()
            local now = Lfg.Game()
            if now and now:IsShown() and not Win.IsOpen(Lfg.frame) then HideUIPanel(now) end
        end, "lfg:close")
        return
    end
    HideUIPanel(g)
end

-- Which window opens, Daylight UI's or the game's own (Win.Swap): the header's swap
-- icon, a link on the game's window and the options switch all set "enabled".
function Lfg.Ours() return Lfg.swap ~= nil and Lfg.swap.Ours() end

-- Switched to the game's window: an open one shows as itself (this one closes and
-- hands the note box back first), a closed one is simply let go.
function Lfg.GiveAway()
    local f, g = Lfg.frame, Lfg.Game()
    if f and Win.IsOpen(f) then shut(f) end
    if ns.Listing then ns.Listing.ReturnNote() end
    if Lfg.follow and g then Win.Followers.Release(Lfg.follow, "lfg") end
end

-- The game's page shown, as one of this window's.
local GAME_TABS = { "list", "find", "who" }

-- Switched back: an open game window closes, is parked, and opens again out of
-- sight, so this one shows in its place on the same page. It parks under a hidden
-- frame, so it can't be parked while shown.
function Lfg.TakeBack()
    local g = Lfg.Game()
    if not (Lfg.follow and g and g:IsShown()) or Win.Followers.Parked(Lfg.follow, "lfg") then return end
    local tab = GAME_TABS[g.selectedTab]
    HideUIPanel(g)
    Win.Followers.Tick()
    if not Win.Followers.Parked(Lfg.follow, "lfg") then return end
    if tab then Lfg.page = tab end
    ShowUIPanel(g)
end

-- The game's window sits under this one (or will when it opens), so the Skins
-- leave it alone. Shown on its own, picked by the player, it isn't.
function Lfg.Covers()
    if not (Lfg.follow and Lfg.Ours()) then return false end
    local g = Lfg.Game()
    return not (g and g:IsShown() and not Win.Followers.Parked(Lfg.follow, "lfg"))
end

local function apply(ours)
    if ours and not Lfg.frame then Lfg.Build(ns.module) end
    if ours then Lfg.TakeBack() else Lfg.GiveAway() end
end

-- Made before the window is built: it's only built while it's the pick.
function Lfg.SwapInit()
    Lfg.swap = Win.Swap({ scope = "GroupFinder", game = Lfg.Game, addon = "Blizzard_GroupFinder_VanillaStyle",
        apply = apply })
end

-- Follower callback: the game's frame shown or hidden.
function Lfg.Changed(_, shown)
    local f = Lfg.frame
    if not shown then
        if Win.IsOpen(f) then shut(f) end
        return
    end
    Lfg.Open(Lfg.showSearch and "find" or nil)
    Lfg.showSearch = nil
end

-- Find a group and Who grow by the detail card's room (Social's, DUI.Social.Detail) while a
-- row is picked.
Lfg.side = {}
function Lfg.Span() return DUI.Social.Detail.SPAN end
local function width(id) return Lfg.W + (Lfg.side[id] and Lfg.Span() or 0) end

-- The detail card of a page opened or closed: the window makes room on its right (or
-- gives it back), easing like a change of page. Pages lay out for the width they are
-- going to have (goalW), as when a tab changes.
function Lfg.SetSide(id, on)
    on = on == true
    if (Lfg.side[id] == true) == on then return end
    Lfg.side[id] = on or nil
    local f = Lfg.frame
    if not f then return end
    local def = f.defs and f.defs[id]
    if def then def.w = width(id) end
    -- The controller finds a window's main button when the page changes or the window
    -- gets the focus, and hidden pieces aren't found: look again now the card has shown.
    if on and DUI.Pad and DUI.Pad.Scrolls then DUI.Pad.Scrolls(f) end
    Lfg.PadChanged()
    if f.current ~= id then return end
    local w, h = Lfg.sizer.Size(id)
    f.goalW, f.goalH = w, h
    if Win.IsOpen(f) then Win.Feel.Size(f, w, h) else f:SetSize(w, h) end
    if Win.Room then Win.Room.Changed(f) end
    if Lfg.follow then Win.Followers.WriteWidth(Lfg.follow) end
end

function Lfg.SaveSpot(x, y)
    if Lfg.spot then Lfg.spot.Save(x, y) end
end


-- Lay out the visible page for the grip's size (the others fill when shown; live while
-- dragging, rows only stretched).
function Lfg.Resized(_, _, live)
    local f = Lfg.frame
    if not (f and Win.IsOpen(f)) then return end
    if live then
        local page = f.pages[f.current]
        if f.current == "find" then ns.Browse.Stretch(page)
        elseif page and page.stack then page.stack:Stretch() end
        if f.current == "list" then ns.Listing.FitNote() end
        return
    end
    if f.current == "find" then ns.Browse.Render(nil, true)
    elseif f.current == "list" then ns.Listing.Render(); ns.Listing.FitNote()
    elseif f.current == "who" then ns.Who.Render() end
end

-- Right-click on the header (or /dui reset): back to the game's spot and size.
function Lfg.ResetSpot()
    if not (ns.module and ns.module.db) then return end
    if Lfg.sizer then Lfg.sizer.Reset() end
    if Lfg.spot then Lfg.spot.Reset() end
end

function Lfg.Apply()
    local f = Lfg.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end
    Win.Repaint(f)
    if Win.IsOpen(f) then
        Lfg.Header()
        if f.current == "find" then ns.Browse.Render(nil, true)
        elseif f.current == "list" then ns.Listing.Render()
        elseif f.current == "who" then ns.Who.Render() end
    end
    if Lfg.follow then Win.Followers.WriteWidth(Lfg.follow) end
end

-- Header gear: the game finder's options menu (LFGListingOptionsButton), one switch to
-- show every activity, not just those suggested for the player's level (the game's own
-- CVar disableSuggestedLevelActivityFilter; CVAR_UPDATE redraws).
Lfg.ALL_LEVELS = "disableSuggestedLevelActivityFilter"
Lfg.OPTIONS_ICON = "ui-options.png"
Lfg.MENU_W = 220

function Lfg.AllLevels()
    local ok, on = pcall(GetCVarBool, Lfg.ALL_LEVELS)
    return ok and on == true
end

-- The switch was flipped (here, or in the game's own window): the categories and activities
-- are read again for the new filter and the open page is drawn again. The client says
-- so with CVAR_UPDATE, but that is not relied on: the menu calls this itself, straight
-- after SetCVar. What Find a group already shows was searched with the old filter's
-- activities, and searching needs a click, so its Refresh lights up instead of searching.
function Lfg.LevelsChanged()
    ns.Data.Forget()
    if ns.Browse and ns.Browse.searched then ns.Browse.stale = true end
    local f = Lfg.frame
    if f and Win.IsOpen(f) then Lfg.Apply() end
end

-- A game setting, so it's written out of a fight only.
function Lfg.SetAllLevels(on)
    DUI.AfterCombat(function()
        DUI.SafeCall(SetCVar, Lfg.ALL_LEVELS, on and "1" or "0")
        Lfg.LevelsChanged()
    end, "lfg:levels")
end

function Lfg.OptionsMenu(owner)
    local W = DUI.Widgets
    if W.menuOwner == owner then return W.CloseMenu() end
    W.OpenMenu(owner, { "all" }, { all = LFG_LIST_IGNORE_SUGGESTED_LEVEL or L["Show all levels"] }, nil,
        function() Lfg.SetAllLevels(not Lfg.AllLevels()) end, Lfg.MENU_W,
        { keepOpen = true, rows = 1, checked = function() return Lfg.AllLevels() end })
end

-- Controller (the game's finder has no controller buttons of its own): footer buttons on
-- X and Y like the game's other windows (X main, Y second), Y is Refresh on Find a
-- group, the menu button opens the gear options, LB / RB switch tabs.
-- The card's main button on the page in view, when a card is open and the button can act.
function Lfg.CardButton()
    local page = Lfg.page == "find" and ns.Browse.page or Lfg.page == "who" and ns.Who.page or nil
    local d = page and page.detail
    if not (d and d:IsOpen()) then return nil end
    local b = d.buttons[1]
    if b and b:IsShown() and b.spec and not b.spec.off then return b end
    return nil
end

-- What the controller's keys show changed (the card opened, closed or moved to someone else).
function Lfg.PadChanged()
    local f = Lfg.frame
    if f and DUI.Pad and DUI.Pad.Refresh then DUI.Pad.Refresh(f) end
end

function Lfg.PadKeys(f)
    local Listing, Data = ns.Listing, ns.Data
    local function on(id) return Lfg.page == id end
    local function listed() return Data.Entry() ~= nil end
    f.padKeys = {
        { key = "X", label = function() return listed() and (LFG_LIST_UPDATE or L["Update"]) or L["List me"] end,
          run = function() Listing.Post() end,
          when = function() return on("list") and Listing.Refusal() == nil and Listing.Changed() end },
        { key = "Y", label = L["Unlist"], run = function() Listing.Unlist() end,
          when = function() return on("list") and listed() and Data.CanEdit() end },
        { key = "Y", label = L["Clear"], run = function() Listing.Clear() end,
          when = function() return on("list") and not listed() and next(Listing.sel or {}) ~= nil end },
        { key = "Y", label = REFRESH or L["Refresh"], run = function() ns.Browse.Refresh() end,
          when = function() return on("find") end },
        -- The card beside Find a group / Who: X presses its main button (the first one). The window
        -- binds X itself (List me), so the controller's own footer lookup is never added: this is it.
        { key = "X", label = function() local b = Lfg.CardButton(); return b and b.text:GetText() or "" end,
          run = function() local b = Lfg.CardButton(); if b then b:Click() end end,
          when = function() return Lfg.CardButton() ~= nil end },
        { key = "MENU_RIGHT", label = OPTIONS or L["Options"], run = function() Lfg.OptionsMenu(f.gear or f) end },
    }
end

function Lfg.Build(mod)
    ns.module = mod
    if Lfg.frame then return Lfg.frame end
    local f = Win.New({ name = Lfg.NAME, escape = false, back = "GroupFinder", w = Lfg.W, h = Lfg.H, portrait = true })
    Lfg.frame = f
    f.onClose = Lfg.Close
    Lfg.spot = Win.Spot(f, function() return ns.module and ns.module.db end, place)
    Win.SetIcon(f, Lfg.ICON)
    Win.AddPage(f, "find", { Build = ns.Browse.Build, Fill = ns.Browse.Fill, pieces = ns.Browse.Pieces, w = width("find"), h = Lfg.H })
    Win.AddPage(f, "list", { Build = ns.Listing.Build, Fill = ns.Listing.Fill, pieces = ns.Listing.Pieces, w = Lfg.W, h = Lfg.H })
    Win.AddPage(f, "who", { Build = ns.Who.Build, Fill = ns.Who.Fill, pieces = ns.Who.Pieces, w = width("who"), h = Lfg.H })
    for _, id in ipairs(Lfg.PAGES) do Win.Build(f, id) end
    f.gear = Win.HeaderIcon(f, Lfg.OPTIONS_ICON, OPTIONS or L["Options"], Lfg.OptionsMenu)
    if Lfg.swap then Lfg.swap.Icon(f) end   -- left of the gear: the game's own window instead
    Win.Tabs(f, { { id = "list", text = L["List yourself"] }, { id = "find", text = L["Find a group"] },
        { id = "who", text = WHO or L["Who"] } }, function(id) Lfg.ShowTab(id, true) end)
    Lfg.PadKeys(f)
    Win.Drag(f, { save = Lfg.SaveSpot, reset = Lfg.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("GroupFinder", "scale", v) end)
    Lfg.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end, shared = true,
        base = function(id) return width(id), Lfg.H end, minH = Lfg.MIN_H,
        extra = function(id) return Lfg.side[id] and Lfg.Span() or 0 end,   -- the card's room isn't part of the size kept
        save = Lfg.SaveSpot, resized = Lfg.Resized, follow = function() return Lfg.follow end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Lfg.ResetSpot   -- /dui reset
    DUI.RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", function() Lfg.Header() end)
    DUI.RegisterEvent("CVAR_UPDATE", function(_, name)
        if name == Lfg.ALL_LEVELS then Lfg.LevelsChanged() end
    end)
    -- The game shows its browse page for some activities (LFG_LIST_SHOW_SEARCH, and its own
    -- code searches them): open on Find a group.
    DUI.RegisterEvent("LFG_LIST_SHOW_SEARCH", function(_, acts)
        Lfg.showSearch = true
        ns.Browse.Listed(acts)
        if Win.IsOpen(f) then Lfg.ShowTab("find") end
    end)
    Lfg.follow = Win.Follow({ key = "lfg", frames = { lfg = Lfg.Game }, changed = Lfg.Changed,
        leave = function() return not Lfg.Ours() end,
        width = function() return (Lfg.sizer and Lfg.sizer.Size(Lfg.page) or Lfg.W) * Win.Scale(ns.Setting("scale")) end })
    Lfg.Apply()
    return f
end
