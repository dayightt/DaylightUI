-- Profession window. The game still runs the trade skill: casting a profession spell
-- opens it (TRADE_SKILL_SHOW), Forever's ProfessionsFrame shows, and its OnHide closes
-- the trade skill (C_TradeSkillUI.CloseTradeSkill). That frame is parked under the
-- kit's veil (Win.Follow) so all of it keeps running, and this window shows in its
-- place and closes with it.
--
-- The game's all-professions overview (BookPage, inside the same frame on Forever) is
-- never shown. The Professions key casts the last used profession (Key.lua). Opened any
-- other way (micro menu), the window starts with no profession and its tabs ask for
-- one, since addon code can't call OpenTradeSkill without a click or key.
-- Unlearn is the little link beside the name, or right-click the profession icon or name.
-- Linked recipes get the small view window (View.lua); the guild list and NPC crafting
-- are handed back to the game's window.
-- Works in combat too: nothing in it is protected, so the game's frame stays parked
-- through a fight and a profession opened then still uses this window.
--
-- Tabs switch professions with C_TradeSkillUI.OpenTradeSkill, like the game's
-- OpenProfessionUIToSkillLine. Only from a click: it works from a slash command but is
-- blocked from an update.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L
local Win = DUI.Win

local Craft = {}
ns.Window = Craft

Craft.NAME = "DaylightUICraft"
Craft.W, Craft.H = 720, 560
Craft.BAR_W = 96   -- skill bar in the header
Craft.MIN_H = 420   -- min height for the resize grip (min width is Craft.W)
Craft.LIST_SHARE = 0.35   -- share of the grip's added width that goes to the list

Craft.picked = {}   -- profession id -> selected recipe (this session)
Craft.skills = {}   -- profession id -> skill when last drawn (for the "+1")

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

local function TS() return type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil end
local function ask(name, ...)
    local ts = TS()
    local fn = ts and ts[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    return ok and v or nil
end

function Craft.Game()
    local g = _G.ProfessionsFrame
    return type(g) == "table" and g or nil
end

-- What the game's frame is showing: "overview" (open a profession instead), "recipes"
-- (the player's own), "view" (someone else's, View.lua), or nil (guild list or NPC,
-- left to the game's window).
function Craft.PageFor(g)
    if type(g.BookPage) == "table" and g.BookPage:IsShown() then return "overview" end
    if ns.Data.Viewing() ~= nil then return "view" end
    if ask("IsTradeSkillGuild") or ask("IsNPCCrafting") then return nil end
    return ns.Data.Profession() and "recipes" or nil
end

function Craft.Ours(g) return Craft.PageFor(g) ~= nil end

-- Header: profession icon and name, skill and its bar, one tab per profession with a
-- crafting window

local function tabOf(prof)
    for _, t in ipairs(Craft.tabs or {}) do
        if prof and t.skillLine == prof.id then return t end
    end
    return nil
end

-- The Unlearn link fades in and out rather than popping.
local function eased(f, piece, on)
    local M = DUI.Motion
    if Win.IsOpen(f) and M and M.On() then
        if on or piece:IsShown() then M.AlphaTo(piece, on and 1 or 0, M.FAST, true) end
    else
        piece:SetAlpha(1)
        piece:SetShown(on)
    end
end

local function header(f, prof)
    if not prof then eased(f, f.drop, false) end
    f.skill.wanted = prof ~= nil
    f.skill:SetShown(prof ~= nil)
    if not prof then   -- no profession open: the tabs ask for one
        Win.SetTitle(f, TRADE_SKILLS or L["Professions"], nil, "")
        f.portrait:Hide()
        f.portraitRim:Hide()
        if f.tabs then Win.PickTab(f, nil) end
        return
    end
    local tab = tabOf(prof)
    Win.SetTitle(f, prof.name, nil, string.format(L["Skill %d / %d"], prof.skill + prof.bonus, prof.max))
    local icon = tab and tab.icon
    if icon then Win.SetIcon(f, icon) end
    f.portrait:SetShown(icon ~= nil)
    f.portraitRim:SetShown(icon ~= nil)
    -- The bar right after the sub line's text, skill in the accent.
    local w = f.sub:GetStringWidth()
    if type(w) ~= "number" then w = 80 end
    f.skill:ClearAllPoints()
    f.skill:SetPoint("LEFT", f.sub, "LEFT", math.ceil(w) + 10, 0)
    f.skillX = math.ceil(w) + 10
    Craft.FitBar(f)
    f.skill:SetMinMaxValues(0, math.max(1, prof.max))
    DUI.Style.SetBarValue(f.skill, math.min(prof.skill + prof.bonus, prof.max), not Win.IsOpen(f))
    DUI.Widgets.BarAccent(f.skill)
    -- A skill point while open: the bar glides up and a soft green "+1" floats over its
    -- end, then fades.
    local was = Craft.skills[prof.id]
    Craft.skills[prof.id] = prof.skill
    if was and prof.skill > was and Win.IsOpen(f) then Craft.Plus(f, prof.skill - was) end
    -- Icon and name take Shift-click (link) and right-click (Unlearn) over their own width.
    local tw = f.title:GetStringWidth()
    if type(tw) ~= "number" then tw = 120 end
    f.who:SetWidth(Win.PORTRAIT + 12 + math.ceil(tw))
    f.dropWanted = tab ~= nil and tab.primary == true
    Craft.FitBar(f)
    eased(f, f.drop, f.dropWanted)
    if f.tabs then Win.PickTab(f, prof.id) end
end

-- Right end of the header: the X, then each tab (Win.Tabs' own total).
function Craft.TabsRoom(f)
    local room = 40 + (f.headerRoom or 0)
    for _, b in ipairs(f.tabs or {}) do room = room + b:GetWidth() + Win.TAB_GAP end
    return room
end

-- The skill bar stops short of the tabs (six professions fill the header). It takes
-- what room is left; below Craft.BAR_MIN it hides, and the sub line still shows the
-- skill as text.
Craft.BAR_MIN = 24
Craft.DROP_GAP = 6   -- gap between the bar and the Unlearn link
function Craft.FitBar(f)
    local W = f:GetWidth()
    if type(W) ~= "number" or not f.skillX then return end
    local left = Win.EDGE + Win.PORTRAIT + 12 + f.skillX
    -- The Unlearn link sits at the end of the sub line after the bar. The bar makes room
    -- for it, so every primary profession shows it whatever the name length.
    local drop = f.dropWanted and math.ceil(f.drop and f.drop:GetWidth() or 0) + Craft.DROP_GAP or 0
    local room = math.floor(W - Craft.TabsRoom(f) - 10 - left - drop)
    f.skill:SetWidth(math.max(Craft.BAR_MIN, math.min(Craft.BAR_W, room)))
    local bar = f.skill.wanted == true and room >= Craft.BAR_MIN
    f.skill:SetShown(bar)
    if f.drop then
        f.drop:ClearAllPoints()
        if bar then f.drop:SetPoint("LEFT", f.skill, "RIGHT", Craft.DROP_GAP, 0)
        else f.drop:SetPoint("LEFT", f.sub, "LEFT", f.skillX, 0) end
    end
end

-- Tooltip on the profession icon or name: what its clicks do.
function Craft.WhoTip(owner)
    local prof = ns.List.data and ns.List.data.prof
    if not (prof and GameTooltip) then return end
    local tab = tabOf(prof)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
    DUI.Tips.Clear()
    DUI.Tips.Title(prof.name)
    if ns.Share.Link() then DUI.Tips.Hint(L["Shift-click: link it in chat"]) end
    if tab and tab.primary then DUI.Tips.Hint(L["Right-click: unlearn"]) end
    DUI.Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

-- Right-click on the profession icon or name: a small menu with Unlearn, only for
-- primary professions (the game's overview only has the button on those).
function Craft.WhoMenu(owner)
    local tab = tabOf(ns.List.data and ns.List.data.prof)
    if not (tab and tab.primary) then return end
    DUI.Widgets.OpenMenu(owner, { "unlearn" }, { unlearn = L["Unlearn"] }, nil, function(key)
        if key == "unlearn" then Craft.Unlearn(tab.name, tab.skillLine) end
    end, nil, { atCursor = true })
end

function Craft.Plus(f, n)
    local M = DUI.Motion
    f.plus:SetText("+" .. n)
    DUI.Style.InkText(f.plus, "GOOD")
    if not (M and M.On()) then f.plus:SetAlpha(0); return end
    M.Tween(f.plus, 0, 1, M.SLOW * 3, function(t)
        local a = t < 0.15 and t / 0.15 or (t > 0.6 and (1 - t) / 0.4 or 1)
        f.plus:SetAlpha(a)
        f.plus:SetPoint("BOTTOMRIGHT", f.skill, "TOPRIGHT", 0, 2 + 6 * t)
    end)
end

-- The game's own confirm popup (UNLEARN_SKILL; accepting calls AbandonSkill).
function Craft.Unlearn(name, skillLine)
    if type(StaticPopup_Show) ~= "function" then return end
    StaticPopup_Show("UNLEARN_SKILL", name, nil, skillLine)
end

-- Tooltip for the Unlearn link, shown before the game's popup asks.
function Craft.UnlearnTip(owner)
    local tab = tabOf(ns.List.data and ns.List.data.prof)
    if not (tab and GameTooltip) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    DUI.Tips.Clear()
    DUI.Tips.Title(string.format(L["Unlearn %s"], tab.name))
    DUI.Tips.Text(L["Forget this profession and every recipe you know in it, to make room for another. You can learn it again from a trainer, starting over from skill 1."])
    DUI.Tips.Hint(L["Click: the game asks you to confirm first"])
    DUI.Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

-- Rebuild the tabs when professions change (one learned or dropped).
local function sameTabs(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i].skillLine ~= b[i].skillLine or a[i].name ~= b[i].name then return false end end
    return true
end

function Craft.MakeTabs(f)
    local tabs = ns.Data.Tabs()
    if Craft.tabs and sameTabs(tabs, Craft.tabs) then return end
    Craft.tabs = tabs
    for _, b in ipairs(f.tabs or {}) do b:Hide() end
    if #tabs < 2 then
        f.tabs = nil
        f.title:SetPoint("RIGHT", f, "RIGHT", -Craft.TabsRoom(f), 0)
        f.sub:SetPoint("RIGHT", f, "RIGHT", -Craft.TabsRoom(f), 0)
        return
    end
    local list = {}
    for _, t in ipairs(tabs) do list[#list + 1] = { id = t.skillLine, text = t.name } end
    Win.Tabs(f, list, Craft.Switch)
end

-- A tab opens that profession in the game; its window stays up and this one with it.
-- Works in combat: OpenTradeSkill isn't protected, it only needs the click.
function Craft.Switch(id)
    local open = ns.Data.Profession()
    if open and open.id == id then return end
    ask("OpenTradeSkill", id)
end

-- The page and header, remembering the profession for the next K press.
-- filled: the page was just filled in place (a switch, Craft.Refill).
function Craft.Show(filled)
    local f = Craft.frame
    if not filled then Win.ShowPage(f, "recipes") end
    local prof = ns.List.data and ns.List.data.prof
    header(f, prof)
    local char = prof and DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if char and char.craftLast ~= prof.id then
        char.craftLast = prof.id
        if ns.Key then ns.Key.Apply() end   -- the key casts this one next
    end
    if Craft.follow then Win.Followers.WriteWidth(Craft.follow) end
    Craft.TellState()
end

-- Page: list on the left, selected recipe on the right

local function build(page)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    list:SetWidth(Craft.ListWidth(Craft.Size()))
    page.list = list
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(1, 1, 1, 0.06)
    rule:SetWidth(1)
    rule:SetPoint("TOPLEFT", list, "TOPRIGHT", 0, -12)
    rule:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 0, 12)
    local recipe = CreateFrame("Frame", nil, page)
    recipe:SetPoint("TOPLEFT", list, "TOPRIGHT", 1, 0)
    recipe:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    page.recipe = recipe
    ns.List.Build(list)
    ns.Recipe.Build(recipe)
end

-- The open profession's selected recipe, or the first visible one.
function Craft.Picked()
    local prof = ns.List.data and ns.List.data.prof
    if not prof then return nil end
    local id = Craft.picked[prof.id]
    if id and ns.List.data.byID[id] then return id end
    return nil
end

local function showRecipe(page, keep)
    local data = ns.List.data
    local id = Craft.Picked()
    ns.Recipe.Fill(page.recipe, id and data and data.byID[id] or nil, keep)
end

local function fill(page)
    page.list:SetWidth(Craft.ListWidth((Craft.Size())))   -- grip size (Win.Resizable)
    ns.List.Fill(page.list)
    local prof = ns.List.data.prof
    if prof and not Craft.Picked() then
        Craft.picked[prof.id] = ns.List.First()
        ns.List.PaintPick(Craft.picked[prof.id])
    end
    showRecipe(page)
    Craft.shown = prof and prof.id or nil
end

local function pieces(page)
    local out = ns.List.Pieces(page.list)
    for _, p in ipairs(ns.Recipe.Pieces(page.recipe)) do out[#out + 1] = p end
    return out
end

-- Clicking a recipe highlights it and lifts the right side in again.
function Craft.Pick(id)
    local prof = ns.List.data and ns.List.data.prof
    local page = Craft.frame and Craft.frame.pages.recipes
    if not (prof and page) then return end
    if Craft.picked[prof.id] == id then return end
    Craft.picked[prof.id] = id
    ns.List.PaintPick(id)
    showRecipe(page)
    Win.Feel.Stagger(ns.Recipe.Pieces(page.recipe), 0)
    Craft.TellState()
end

-- List re-read (bags, a craft, a skill-up): the right side and header follow, scrolls kept.
function Craft.Refreshed()
    local f = Craft.frame
    local page = f and f.pages.recipes
    if not (page and Win.IsOpen(f)) then return end
    local prof = ns.List.data.prof
    if prof and prof.id ~= Craft.shown then return Craft.Refill() end
    header(f, prof)
    showRecipe(page, true)
    Craft.TellState()
end

-- Open, close, follow the game's frame

-- Dragged position (header, Win.Drag, saved per profile in the module's `spot`), else
-- the game's own spot: anchored to the top-left of its veiled window, the left panel spot.
local function spot()
    local s = ns.module and ns.module.db and ns.module.db.spot
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then return s end
    return nil
end

-- While this window is open the game's veiled window sits with its top right just
-- above it. Other addons pin buttons inside its top-right corner (ItemTree's View,
-- TradeSkillMaster's switch) and only check whether it's shown, so otherwise they'd
-- float alone at the game's spot. This way they sit on this window's top edge.
-- Craft.LIFT is in UIParent units.
Craft.LIFT = 26

local function ours()
    if Craft.frame and Win.IsOpen(Craft.frame) then return Craft.frame end
    local v = ns.View and ns.View.frame
    if v and Win.IsOpen(v) then return v end
end

local function pinnedTo(g)
    local _, rel = g:GetPoint(1)
    return rel ~= nil and (rel == Craft.frame or rel == (ns.View and ns.View.frame))
end

-- Checked each time the follower looks while the game's window is parked and shown,
-- and when this window is placed: re-pin whenever the game moved it.
function Craft.Pin(_, g)
    g = g or Craft.Game()
    local f = ours()
    if not (f and g and Craft.follow and Win.Followers.Parked(Craft.follow, "craft")) then return end
    local _, rel, _, _, y = g:GetPoint(1)
    local lift = Craft.LIFT * UIParent:GetEffectiveScale() / g:GetEffectiveScale()
    if rel == f and y == lift then return end
    if not pinnedTo(g) then Craft.home = nil end   -- the game placed it, so its spot changed
    if Craft.home == nil then
        local l, t = g:GetLeft(), g:GetTop()
        if type(l) == "number" and type(t) == "number" then
            local k = g:GetEffectiveScale() / UIParent:GetEffectiveScale()
            Craft.home = { l * k, t * k }
        end
    end
    g:ClearAllPoints()
    g:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, lift)
end

-- Its own spot, else the game's left panel spot, read before the game's window is
-- pinned to this one. Never anchored to it, which would loop.
local function place(f)
    local s = spot()
    local g = Craft.Game()
    if s then
        Win.PlaceTop(f, s[1], s[2])
    else
        if g and not pinnedTo(g) then
            local l, t = g:GetLeft(), g:GetTop()
            if type(l) == "number" and type(t) == "number" then
                local k = g:GetEffectiveScale() / UIParent:GetEffectiveScale()
                Craft.home = { l * k, t * k }
            end
        end
        f:ClearAllPoints()
        local h = Craft.home
        if h then
            local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", h[1] * k, h[2] * k)
        else
            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
    end
end

-- Re-read everything for the profession the game has open now (a switch). Filled in
-- place: only the recipes lift in, under tabs, search and chips that stay still (fading
-- the whole page in looked like a flash).
-- The same profession again (TRADE_SKILL_SHOW after the list's own refill) stays put;
-- a list still loading waits for its TRADE_SKILL_LIST_UPDATE (List.Soon, which calls
-- Craft.Refreshed back here).
function Craft.Refill()
    local f = Craft.frame
    if not (f and Win.IsOpen(f)) then return end
    Craft.MakeTabs(f)
    local page = f.pages.recipes
    if f.current ~= "recipes" or not page then return Craft.Show() end
    if ns.Data.Changing() then return end
    local was = Craft.shown
    fill(page)
    Craft.Show(true)
    if Craft.shown ~= was then
        local lift = ns.List.Rows(page.list)
        for _, p in ipairs(ns.Recipe.Pieces(page.recipe)) do lift[#lift + 1] = p end
        Win.Feel.Stagger(lift, 0)
    end
end

-- any: open with no profession too (the game's overview came up).
function Craft.Open(any)
    local f = Craft.frame
    if not any and not ns.Data.Profession() then return false end
    ns.View.Shut()
    Craft.MakeTabs(f)
    if Win.IsOpen(f) then Craft.Show(); return true end
    place(f)
    Craft.Show()
    Win.Open(f)
    ns.List.ReportRows()
    Craft.TellState()
    return true
end

-- Closing under the mouse: the hovered piece never gets OnLeave, so its tooltip is
-- hidden here.
local function shut(f)
    local tip = GameTooltip
    local owner = tip and tip:IsShown() and tip:GetOwner()
    while owner do
        if owner == f then tip:Hide(); break end
        owner = owner:GetParent()
    end
    Win.Close(f)
    if f == Craft.frame then Craft.TellShut() end
end

Craft.Place, Craft.Shut = place, shut   -- the small view window (View.lua) uses the same spot

-- Close this one now; the game's closes its own way (HideUIPanel, whose OnHide closes
-- the trade skill). In combat HideUIPanel does nothing from addon code
-- (CheckProtectedFunctionsAllowed), so close the trade skill instead and the game's
-- frame hides itself on TRADE_SKILL_CLOSE.
function Craft.Close()
    local f = Craft.frame
    if not f then return end
    shut(f)
    ns.View.Shut()
    local g = Craft.Game()
    if not (g and g:IsShown()) then return end
    if InCombatLockdown() then
        if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then C_TradeSkillUI.CloseTradeSkill() end
        DUI.AfterCombat(function()
            local now = Craft.Game()
            if now and now:IsShown() and not Win.IsOpen(Craft.frame) then HideUIPanel(now) end
        end, "craft:close")
        return
    end
    HideUIPanel(g)
end

-- Guild list or NPC crafting: the game's own window, for now.
local function lend()
    if Win.IsOpen(Craft.frame) then shut(Craft.frame) end
    ns.View.Shut()
    if Win.Followers.Lend(Craft.follow, "craft") then return end
    DUI.AfterCombat(function()
        local g = Craft.Game()
        if g and g:IsShown() and not Craft.Ours(g) then Win.Followers.Lend(Craft.follow, "craft") end
    end, "craft:lend")
end

-- Follower callback: the game's frame shown or hidden.
function Craft.Changed(_, shown)
    local f = Craft.frame
    if not shown then
        if Win.IsOpen(f) then shut(f) end
        ns.View.Shut()
        return
    end
    local g = Craft.Game()
    if not g then return end
    local page = Craft.PageFor(g)
    if page == "overview" then return Craft.Open(true) end
    if page == "view" then return ns.View.Open() end
    if not page then
        -- Someone's list hasn't arrived, so there's no way to tell whose it is yet. Craft.Settled
        -- checks again.
        if ns.Data.Changing() then Craft.waiting = true; return end
        return lend()
    end
    Craft.Open()
end

-- The trade skill changed under a shown frame (a tab, a profession spell cast while
-- open): the game keeps its frame up, this window refills.
function Craft.TradeSkillShown()
    if not Craft.follow then return end
    local g = Craft.Game()
    -- Was handed back (someone's recipes, the overview) and now the player's own
    -- profession opened: take over again (the follower's next look opens it).
    if g and g:IsShown() and not Win.Followers.Parked(Craft.follow, "craft") then
        if Craft.Ours(g) then Win.Followers.Reclaim(Craft.follow, "craft") end
        return
    end
    if not Win.Followers.Shown(Craft.follow, "craft") then return end
    local page = g and Craft.PageFor(g)
    if page == "view" then
        if Win.IsOpen(Craft.frame) then shut(Craft.frame) end
        return ns.View.Open()
    end
    if g and page ~= "recipes" then return lend() end
    if Win.IsOpen(Craft.frame) then Craft.Refill() else Craft.Open() end
end

-- A list arrived. A link's list comes after the game's frame shows, so the first look
-- can't tell it apart: the deferred look happens now, and a frame that was handed
-- back returns if it turned out to be someone's or the player's own.
function Craft.Settled()
    if not Craft.follow then return end
    local g = Craft.Game()
    if not (g and g:IsShown()) then Craft.waiting = nil; return end
    if not Win.Followers.Parked(Craft.follow, "craft") then
        if Craft.Ours(g) then Win.Followers.Reclaim(Craft.follow, "craft") end
        return
    end
    if not Craft.waiting then return end
    Craft.waiting = nil
    Craft.Changed("craft", true)
end

-- Dragged by the header: just saved (no SettingChanged, nothing to refill).
function Craft.SaveSpot(x, y)
    local db = ns.module and ns.module.db
    if db then db.spot = { DUI.Pixel.Snap(UIParent, x), DUI.Pixel.Snap(UIParent, y) } end
end

-- Size set by the grip (Win.Resizable), else Craft.W x Craft.H.
function Craft.Size()
    if Craft.sizer then return Craft.sizer.Size() end
    return Craft.W, Craft.H
end

-- The list side grows by a share of the width the window gained.
function Craft.ListWidth(w)
    return ns.List.W + math.floor(math.max(0, (w or Craft.W) - Craft.W) * Craft.LIST_SHARE)
end

-- Lay out the page for the grip's size: list width, chips and spells, recipe side
-- (live while dragging, rows only stretched).
function Craft.Resized(w, _, live)
    local page = Craft.frame and Craft.frame.pages.recipes
    if not page then return end
    page.list:SetWidth(Craft.ListWidth(w))
    if not Win.IsOpen(Craft.frame) then return end
    ns.List.LayoutChips(page.list)
    ns.Spells.Fill()
    Craft.FitBar(Craft.frame)
    if live then
        page.list.stack:Stretch()
        page.recipe.stack:Stretch()
        return
    end
    ns.List.Render(page.list, true)
    showRecipe(page, true)
end

-- Plugins (DaylightUI.API 1.2): window state, recipe picks from outside, and panes
-- docked to the right edge

function Craft.Tell(event, a, b, c)
    local R = DUI.APIReport
    if R then R.Event(event, a, b, c) end
end

-- Only sent on change: open, then profession, then selected recipe.
function Craft.TellState()
    local f = Craft.frame
    if not (f and Win.IsOpen(f)) then return end
    if not Craft.toldOpen then
        Craft.toldOpen = true
        Craft.Tell("CraftShown")
    end
    local prof = ns.List.data and ns.List.data.prof
    local id = prof and prof.id or nil
    if id ~= Craft.toldProf then
        Craft.toldProf, Craft.toldRecipe = id, nil
        if id then Craft.Tell("CraftProfessionChanged", id) end
    end
    local r = Craft.Picked()
    if r ~= Craft.toldRecipe then
        Craft.toldRecipe = r
        if r then Craft.Tell("CraftRecipeSelected", r) end
    end
end

function Craft.TellShut()
    local R = DUI.APIReport
    if R then R.ListClear("craftrow") end
    if not Craft.toldOpen then return end
    Craft.toldOpen, Craft.toldProf, Craft.toldRecipe = nil, nil, nil
    Craft.Tell("CraftHidden")
end

-- The open profession: skillLine, name (nil while the window is closed).
function Craft.Current()
    local f = Craft.frame
    local prof = ns.List.data and ns.List.data.prof
    if not (f and Win.IsOpen(f) and prof) then return nil end
    return prof.id, prof.name
end

-- Select a recipe from outside, like a click on its row: highlighted, scrolled into
-- view (unless its category is collapsed or the search hides it), and shown on the
-- right. False when the window isn't open on a profession that knows it.
function Craft.Select(id)
    local f = Craft.frame
    local data = ns.List.data
    if not (f and Win.IsOpen(f) and f.current == "recipes" and data and data.prof and data.byID[id]) then return false end
    Craft.Pick(id)
    local line = ns.List.lines and ns.List.lines[id]
    local page = f.pages.recipes
    if line and line:IsShown() and page and page.list.stack then page.list.stack:Reveal(line) end
    return true
end

-- Docked panes, left to right in request order, each the window's full height on its
-- right edge. They're children of the window so they move, scale, open and close with
-- it; game windows beside it make room (Followers.WriteWidth counts them).
Craft.PANE_GAP = 6
Craft.panes = {}   -- { name, frame, width }

function Craft.Pane(name, width)
    for _, p in ipairs(Craft.panes) do
        if p.name == name then
            p.width = width
            Craft.DockPanes()
            return p.frame
        end
    end
    local pane = CreateFrame("Frame", nil, UIParent)
    pane:Hide()   -- until the window exists to hold it
    Craft.panes[#Craft.panes + 1] = { name = name, frame = pane, width = width }
    Craft.DockPanes()
    return pane
end

function Craft.PanesWidth()
    local w = 0
    if not Craft.frame then return w end
    for _, p in ipairs(Craft.panes) do w = w + Craft.PANE_GAP + p.width end
    return w
end

function Craft.DockPanes()
    local f = Craft.frame
    if not f then return end
    local prev = f
    for _, p in ipairs(Craft.panes) do
        local pane = p.frame
        pane:SetParent(f)
        pane:ClearAllPoints()
        pane:SetPoint("TOPLEFT", prev, "TOPRIGHT", Craft.PANE_GAP, 0)
        pane:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", Craft.PANE_GAP, 0)
        pane:SetWidth(p.width)
        if not p.shell then p.shell = DUI.Style.Shell(pane, { window = true }) or true end
        pane:Show()
        prev = pane
    end
    if Craft.follow then Win.Followers.WriteWidth(Craft.follow) end
end

-- Right-click on the header (or /dui reset): back to the game's spot and size.
function Craft.ResetSpot()
    local db = ns.module and ns.module.db
    if not db then return end
    if Craft.sizer then Craft.sizer.Reset() end
    if not db.spot then return end
    db.spot = nil
    if Craft.frame and Win.IsOpen(Craft.frame) then place(Craft.frame) end
    if ns.View.frame and Win.IsOpen(ns.View.frame) then place(ns.View.frame) end
end

function Craft.Apply()
    local f = Craft.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then place(f) end   -- new UI scale keeps the dragged spot
    Win.Repaint(f)
    if Win.IsOpen(f) then
        ns.List.Render(f.pages.recipes.list, true)   -- repaint counts and headings in the new accent
        Craft.Refreshed()
    end
    if Craft.follow then Win.Followers.WriteWidth(Craft.follow) end
    ns.View.Apply()
end

-- Controller, like the game's crafting footer (Blizzard_ProfessionsFrame.lua): X Create,
-- held X Create all (Make.PadKeys), Y more actions for a recipe (share in chat), right
-- menu button the slot filter, left one the search box.
function Craft.PadKeys(f)
    ns.Make.PadKeys(f)
    local List = ns.List
    local function recipeOf(at) return at and at.lineSpec and at.lineSpec.recipe end
    table.insert(f.padKeys, { key = "Y", label = CONTEXT_ACTION_LABEL_MORE_ACTIONS or L["More"],
        when = function(at) local r = recipeOf(at); return r ~= nil and r.link ~= nil end,
        run = function(at)
            local r = recipeOf(at)
            DUI.Widgets.OpenMenu(at, { "share" }, { share = SOCIAL_SHARE_TEXT or L["Share"] }, nil, function()
                local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
                if type(insert) == "function" then insert(r.link) end
            end, 160)
        end })
    table.insert(f.padKeys, { key = "MENU_RIGHT", label = FILTER or L["Filter"],
        when = function() local p = List.pane; return p ~= nil and p.slot ~= nil and p.slot:IsShown() end,
        run = function() List.SlotMenu(List.pane.slot) end })
    table.insert(f.padKeys, { key = "MENU_LEFT", label = SEARCH or L["Search"],
        when = function(at) local p = List.pane; return p ~= nil and p.search ~= nil and at ~= p.search end,
        run = function() List.pane.search:SetFocus() end })
end

function Craft.Build(mod)
    ns.module = mod
    if Craft.frame then return Craft.frame end
    local f = Win.New({ name = Craft.NAME, back = "Professions", w = Craft.W, h = Craft.H, portrait = true })
    Craft.frame = f
    f.onClose = Craft.Close
    Craft.PadKeys(f)
    f.skill = DUI.Widgets.Bar(f)
    f.skill:SetWidth(Craft.BAR_W)
    f.plus = DUI.Style.Text(f, DUI.Style.SIZE.small, "RIGHT")
    f.plus:SetPoint("BOTTOMRIGHT", f.skill, "TOPRIGHT", 0, 2)
    f.plus:SetAlpha(0)
    Win.AddPage(f, "recipes", { Build = build, Fill = fill, pieces = pieces, w = Craft.W, h = Craft.H })
    Win.Build(f, "recipes")
    Craft.DockPanes()
    -- Over the icon and name: Shift-click links the profession into the open chat box
    -- (ns.Share, as the game's book does on its icon), right-click opens Unlearn
    -- (Craft.WhoMenu), and a left drag still moves the window.
    f.who = CreateFrame("Button", nil, f)
    f.who:SetPoint("TOPLEFT", f, "TOPLEFT", Win.EDGE, -8)
    f.who:SetSize(Win.PORTRAIT, Win.PORTRAIT)
    f.who:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.who:RegisterForDrag("LeftButton")
    f.who:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return Craft.WhoMenu(self) end
        if IsModifiedClick("CHATLINK") then ns.Share.Insert() end
    end)
    f.who:SetScript("OnEnter", function(self) Craft.WhoTip(self) end)
    f.who:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    f.who:SetScript("OnDragStart", function() local fn = f:GetScript("OnDragStart"); if fn then fn(f) end end)
    f.who:SetScript("OnDragStop", function() local fn = f:GetScript("OnDragStop"); if fn then fn(f) end end)
    -- Unlearn spelled out, since a tiny X didn't say what it does: a red link, dim at
    -- rest, with a tooltip saying what it costs. The game's confirm popup still asks.
    f.drop = DUI.Widgets.Link(f, DUI.Style.SIZE.small, { own = true })
    f.drop.SetLabel(L["Unlearn"])
    DUI.Style.InkText(f.drop.text, "BAD")
    f.drop:SetScript("OnClick", function()
        local tab = tabOf(ns.List.data and ns.List.data.prof)
        if tab and tab.primary then Craft.Unlearn(tab.name, tab.skillLine) end
    end)
    f.drop:HookScript("OnEnter", function(self) Craft.UnlearnTip(self) end)
    f.drop:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    f.drop:Hide()
    if ns.Key then ns.Key.Init() end
    Win.Drag(f, { save = Craft.SaveSpot, reset = Craft.ResetSpot })
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("Professions", "scale", v) end)
    Craft.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end, shared = true,
        base = function() return Craft.W, Craft.H end, minH = Craft.MIN_H,
        save = Craft.SaveSpot, resized = Craft.Resized, follow = function() return Craft.follow end })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Craft.ResetSpot   -- /dui reset
    DUI.RegisterEvent("TRADE_SKILL_SHOW", function() C_Timer.After(0, Craft.TradeSkillShown) end)
    DUI.RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() C_Timer.After(0, Craft.Settled) end)
    -- A skill point can arrive without a list update, so re-read the skill for the header.
    DUI.RegisterEvent("SKILL_LINES_CHANGED", function()
        if not Win.IsOpen(f) then return end
        Craft.MakeTabs(f)
        local data = ns.List.data
        local now = ns.Data.Profession()
        if data and data.prof and now and now.id == data.prof.id then data.prof = now end
        header(f, data and data.prof)
    end)
    Craft.follow = Win.Follow({ key = "craft", frames = { craft = Craft.Game }, veil = { craft = true },
        changed = Craft.Changed, pin = Craft.Pin,
        width = function() return ((Craft.Size()) + Craft.PanesWidth()) * Win.Scale(ns.Setting("scale")) end })
    Craft.Apply()
    return f
end
