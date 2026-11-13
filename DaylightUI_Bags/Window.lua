-- Bag windows: a draggable title bar with the close X, a tool row (search plus
-- the window's buttons), the grid and a footer. The bag is one window; the bank
-- (Bank.lua) is built the same way with its own slot set, settings, search and
-- tools. Also the module's wiring: building, settings, and keeping each window
-- filled and laid out as the bags change.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel = DUI.Style, DUI.Pixel

local Window = {}
ns.Window = Window

Window.NAME = "DaylightUIBag"
Window.EDGE = 10             -- inner margin
Window.TITLE = DUI.Win.HEADER   -- header height: portrait, title and sub line
Window.ROW = 22              -- tool row height (search and buttons)
Window.GAP = 6               -- between rows
Window.FOOTER_ROW = 18       -- the footer's text and button row
Window.BAR_GAP = 2           -- between that row and the row above it
Window.SELL_ROW = 18         -- the row holding the free-slots bar and Sell junk
Window.BAR_W = 64            -- the free-slots bar's width
Window.FOOTER = Window.FOOTER_ROW + Window.BAR_GAP + Window.SELL_ROW
Window.CHIP_ROW = DUI.Widgets.CHIP_HEIGHT   -- the filter chips under the search
-- Filter chips: a chip shows only the groups listed (keys of Cat.PRIORITY).
Window.CHIPS = {
    { id = "all" },
    { id = "gear", groups = { "sets", "weapon", "armor" } },
    { id = "use", groups = { "hearthstone", "consumable" } },
    { id = "trade", groups = { "reagent", "tradegoods", "recipe" } },
    { id = "quest", groups = { "quest" } },
    { id = "junk", groups = { "junk" } },
}
local CHIP_LABEL = {
    all = function() return ALL or L["All"] end,
    gear = function() return L["Gear"] end,
    use = function() return L["Use"] end,
    trade = function() return L["Trade"] end,
    quest = function() return QUESTS_LABEL or L["Quest"] end,
    junk = function() return L["Junk"] end,
}
Window.TEXT_SIZE = Style.SIZE.body
Window.DIM = DUI.Style.INK.LABEL   -- hints, small icons, count labels
-- Free slot thresholds for warn and bad colors, same as the InfoPanel bag
-- data text (DT.BAGS_WARN/BAGS_BAD).
Window.FREE_WARN, Window.FREE_BAD = 4, 0
Window.DEFAULT_POINT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -24, 220 }
Window.SORT_ICON = "Interface\\Icons\\INV_Pet_Broom"
Window.BAGS_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
Window.VIEW_ICON = "Interface\\Icons\\INV_Misc_Note_01"

ns.windows = {}              -- every window created, bag first

-- Bag settings (the module's own table).
function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

local function text(parent, size, justify)
    return Style.Text(parent, size, justify)
end

-- Hide first, which clears what the tooltip showed last.
local function tip(owner, title, line, hint)
    owner:SetScript("OnEnter", function(self)
        if self.hover then self.hover(true) end
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local Tips = DUI.Tips
        Tips.Clear()
        Tips.Title(type(title) == "function" and title() or title)
        local l = type(line) == "function" and line() or line
        if l then Tips.Text(l) end
        if hint then Tips.Hint(hint) end
        Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function(self)
        if self.hover then self.hover(false) end
        GameTooltip:Hide()
    end)
end
Window.Tip = tip

-- Small square icon button built on W.Button with the icon over its fill.
-- tip() keeps the hover trace going through b.hover.
local function iconButton(parent, file)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(Window.ROW, Window.ROW)
    DUI.Widgets.DressButton(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(file)
    Style.CropIcon(b.icon)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
    b.icon:SetAlpha(0.75)
    b.hover = function(on) b.icon:SetAlpha(on and 1 or 0.75); b.Hover(on) end
    return b
end

-- Small text button (footer buy and gold buttons), built on W.Button.
-- template: a game template to build from (the bank's Buy tab).
function Window.TextButton(parent, label, template)
    local b = CreateFrame("Button", nil, parent, template)
    b:SetHeight(Window.FOOTER_ROW)
    DUI.Widgets.DressButton(b)
    b.text:SetFont(b.text:GetFont(), Window.TEXT_SIZE, "")
    function b.SetLabel(s)
        b.text:SetText(s)
        local w = b.text.GetStringWidth and b.text:GetStringWidth()
        b:SetWidth((type(w) == "number" and w or 40) + 20)
    end
    b.SetLabel(label)
    b.hover = b.Hover
    return b
end

local function searchBox(f)
    -- Each window has its own search.
    local eb = DUI.Widgets.Input(f, { height = Window.ROW, size = Window.TEXT_SIZE, search = true,
        hint = L["Search, or try quest, food, rare"],
        onChange = function(t)
            f.match = ns.Search.Parse(t)
            Window.MatchAll(f)
        end })
    -- Hovering the box shows the search syntax.
    eb:HookScript("OnEnter", function(self)
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        DUI.Tips.Clear()
        DUI.Tips.Title(SEARCH or L["Search"])
        DUI.Tips.Text(ns.Search.HELP)
        DUI.Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    eb:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return eb
end

-- Position

function Window.Place(f)
    if InCombatLockdown and InCombatLockdown() then return end
    f:SetScale(DUI.Win.Scale(f.Setting("scale")))
    f:ClearAllPoints()
    local pos = f.Setting("position")
    local s, u = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if type(pos) == "table" and type(pos[1]) == "number" and type(s) == "number" and s > 0 then
        f:SetPoint(type(pos.at) == "string" and pos.at or "TOPLEFT", UIParent, "BOTTOMLEFT", pos[1] * u / s, pos[2] * u / s)
    else
        local d = f.defaultPoint
        f:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

-- The saved spot is relative to the anchor picked in unlock mode's editor
-- (TOPLEFT until one is picked), so the window grows away from it.
local function anchorOf(f) return DUI.Movers.Corner("bags." .. f.kind) or "TOPLEFT" end

local function save(f)
    local left, top, right, bottom = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
    if type(left) ~= "number" or type(top) ~= "number" or type(right) ~= "number" or type(bottom) ~= "number" then return end
    local s, u = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local at = anchorOf(f)
    local x, y = DUI.Movers.PointOf(at, (left + right) / 2, (top + bottom) / 2, right - left, top - bottom)
    f.Set("position", { x * s / u, y * s / u, at = at })
end

-- Unlock mode gets a proxy handle since the window is hidden most of the time.
-- Dragging it sets the window's top-left like a title bar drag would, and the
-- movers' own copy is dropped so the window's setting is the only one.
Window.MOVER_MIN = { 200, 150 }

local function onHandleMoved(f, key)
    local positions = DUI.DB.Positions()
    local p = positions[key]
    if p then
        local h = DUI.Movers.Handle(key)
        local w, hgt = 0, 0
        if h then w, hgt = h:GetWidth(), h:GetHeight() end
        local at = anchorOf(f)
        local x, y = DUI.Movers.PointOf(at, UIParent:GetWidth() / 2 + p[1], UIParent:GetHeight() / 2 + p[2], w, hgt)
        f.Set("position", { x, y, at = at })
        positions[key] = nil
    else
        f.Set("position", nil)    -- reset to the default spot
    end
    DUI.AfterCombat(function()
        Window.Place(f)
        local e, h = DUI.Movers.Get(key), DUI.Movers.Handle(key)
        if DUI.Movers.unlocked and e and h then DUI.Movers.PlaceHandle(e, h) end
    end, "bags:mover:" .. key)
end

-- A window

-- spec: kind ("bag", "bank"), name (global), title, set (a slot set), prefix
-- (settings path in the module, "" or "bank."), defaultPoint, tools (right to
-- left: { icon, title, desc, onClick, onRightClick?, hint? }), onTitleRightClick,
-- onClose, footer(f) to add footer pieces, updateFooter(f), still (shows a saved
-- copy, Viewer.lua, so bag changes never touch it).
function Window.Create(spec)
    local f = CreateFrame("Frame", spec.name, UIParent)
    f.kind, f.set, f.prefix, f.spec = spec.kind, spec.set, spec.prefix or "", spec
    f.defaultPoint = spec.defaultPoint or Window.DEFAULT_POINT
    -- What still needs filling while closed (see Window.MarkDirty).
    f.dirty, f.dirtyAll, f.cdDirty = {}, true, false
    -- Settings: the module's own table, or the one under its prefix. While the bank
    -- has no look of its own, it reads and writes the bags' values for the shared
    -- keys (ns.BANK_SHARED, bank.ownLook).
    local function own()
        local db = ns.module and ns.module.db or {}
        if f.prefix == "" then return db end
        local key = string.match(f.prefix, "^(.-)%.$")
        if type(db[key]) ~= "table" then db[key] = {} end
        return db[key]
    end
    local function shared(key)
        return f.prefix ~= "" and ns.BANK_SHARED[key] and own().ownLook ~= true
    end
    function f.Setting(key)
        if shared(key) then return ns.Setting(key) end
        return own()[key]
    end
    function f.Set(key, value) DUI:Set("Bags", (shared(key) and "" or f.prefix) .. key, value) end
    local view = f.prefix == "" and nil or setmetatable({}, { __index = function(_, k) return f.Setting(k) end })
    function f.Cfg() return view or own() end
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    Style.Shell(f, { window = "Bags" })
    local E = Window.EDGE

    -- The window kit's header: portrait, title, sub line, X, accent line.
    DUI.Win.Header(f, { portrait = true, onClose = spec.onClose })
    DUI.Win.WheelScale(f, function() return f.Setting("scale") end, function(v) f.Set("scale", v) end, 0.5, 1.5)
    f.title:SetText(L[spec.title])
    Window.SetPortrait(f, spec.portrait)

    -- Dragged by the title bar (not over the X).
    local handle = CreateFrame("Frame", nil, f)
    handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Window.TITLE, 0)
    handle:SetHeight(Window.TITLE)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        f:SetMovable(true)
        f:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        save(f)
        Window.Place(f)
    end)
    -- Right-click on the title bar (for the bag: toggle the bank, like Bagnon).
    if spec.onTitleRightClick then
        handle:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then spec.onTitleRightClick(f) end
        end)
    end
    f.handle = handle

    local moverKey = "bags." .. f.kind
    if not DUI.Movers.Get(moverKey) then
        DUI.Movers.Register(f, moverKey, spec.title, nil, { proxy = true, corner = "TOPLEFT",
            minW = Window.MOVER_MIN[1], minH = Window.MOVER_MIN[2],
            onCorner = function() save(f); Window.Place(f) end,
            onMoved = function(key) onHandleMoved(f, key) end })
    end

    -- Tool row: the window's buttons right to left, the search fills the rest.
    local top = -(Window.TITLE + Window.GAP)
    f.tools = {}
    for _, t in ipairs(spec.tools or {}) do
        local b = iconButton(f, t.icon)
        if t.onRightClick then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" and t.onRightClick then t.onRightClick(f) else t.onClick(f) end
        end)
        tip(b, t.title, t.desc, t.hint)
        if t.key then f[t.key] = b end
        f.tools[#f.tools + 1] = b
    end
    f.search = searchBox(f)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", E, top)
    Window.LayoutTools(f)

    Window.Chips(f)
    f.items = CreateFrame("Frame", nil, f)
    f.items.dluiWindow = f
    f.items:SetPoint("TOPLEFT", f, "TOPLEFT", E, top - Window.ROW - Window.GAP - Window.CHIP_ROW - Window.GAP)

    f.free = text(f, Window.TEXT_SIZE, "LEFT")
    f.free:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", E, E)
    DUI.Style.InkText(f.free, "VALUE")
    -- A thin bar of used slots above the free count.
    f.freeBar = DUI.Widgets.Bar(f, DUI.Widgets.BAR_H)
    f.freeBar:SetWidth(Window.BAR_W)
    f.freeBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", E,
        E + Window.FOOTER_ROW + Window.BAR_GAP + (Window.SELL_ROW - DUI.Widgets.BAR_H) / 2)
    f.money = text(f, Window.TEXT_SIZE, "RIGHT")
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -E, E)
    if spec.kind == "bag" then
        -- Shown only at a vendor with something to sell (Window.UpdateSell).
        f.sellJunk = Window.TextButton(f, L["Sell junk"])
        -- On the bar's row, away from the money and currencies below.
        f.sellJunk:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -E, E + Window.FOOTER_ROW + Window.BAR_GAP)
        f.sellJunk:SetScript("OnClick", function() ns.Junk.SellNow() end)
        f.sellJunk:Hide()
        -- A warlock over their Soul Shard limit (Window.UpdateShards). Deletes only
        -- on a second click.
        f.dropShards = Window.TextButton(f, "")
        f.dropShards.fit = 1
        DUI.Widgets.Confirm(f.dropShards, function() return Window.ShardLabel(f.shardsExtra or 0) end, function()
            ns.Junk.DeleteShards()
            DUI.Widgets.EaseShown(f.dropShards, false)
        end)
        f.dropShards:Hide()
    end
    if spec.footer then spec.footer(f) end

    f:SetScript("OnHide", function(self)
        -- A search only lasts while the window is open.
        if self.search:GetText() ~= "" then self.search:SetText("") end
        self.match = nil
        if self.chip then Window.PickChip(self, nil, true) end
        self.search:ClearFocus()
    end)
    -- On open, lay out and fill whatever changed while closed and wasn't already
    -- done in the background (Prep.lua). New loot shines after the window has
    -- finished appearing, not while it's filled here.
    f:SetScript("OnShow", function(self)
        self.opening = true
        if self.stale then Window.Relayout(self) end
        Window.FillDirty(self)
        self.opening = nil
        ns.Items.ShineNew(self)
        if spec.onShow then spec.onShow(self) end
    end)
    -- Fades in and out, Escape included. Must come after the scripts above since it
    -- hooks them. Fade only, never a lift: lifting moves every piece of every slot
    -- each frame (about 10 fps), and pinning the grid for a lift re-placed them all
    -- on every open (about 280 ms frozen).
    f.padSecond = true   -- opened with the character window, which keeps the D-pad
    f.padFirst = function() return Window.FirstSlot(f) end   -- start on the items, not the tools above them
    Window.PadSetup(f)
    if DUI.Motion then DUI.Motion.Window(f) end
    ns.windows[#ns.windows + 1] = f
    return f
end

-- ---------------------------------------------------------------------
-- A controller: the game's bag buttons (ContainerFrameCombinedBagsMixin's
-- SetupGamepad). A picks the item up, X does what a right click does (use,
-- equip, sell, open, read, move to or from the bank), Y has more actions,
-- LB and RB jump between the groups (the search is every window's).
-- ---------------------------------------------------------------------

local function padItem(b)
    if type(b) ~= "table" or not b.GetID or type(b.GetParent) ~= "function" then return nil end
    local holder = b:GetParent()
    local bag = b.GetBagID and b:GetBagID() or (holder and holder.GetID and holder:GetID())
    local slot = b:GetID()
    if type(bag) ~= "number" or type(slot) ~= "number" or (ns.Saved and ns.Saved.Is(bag)) then return nil end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" or not info.itemID then return nil end
    return info, bag, slot
end

-- What a right click does to this item here, in the game's own words.
function Window.PadUseLabel(f, b)
    local info = padItem(b)
    if not info then return nil end
    if f.kind == "bank" then return L["To your bags"] end
    if ns.Bank and ns.Bank.open then return L["To the bank"] end
    local merchant = _G.MerchantFrame
    if merchant and merchant:IsShown() and not info.hasNoValue then return CONTEXT_ACTION_LABEL_SELL or L["Sell"] end
    if info.hasLoot then return CONTEXT_ACTION_LABEL_OPEN or L["Open"] end
    if info.isReadable then return CONTEXT_ACTION_LABEL_READ or L["Read"] end
    local link = info.hyperlink
    if link and C_Item.IsEquippableItem and C_Item.IsEquippableItem(link) then return CONTEXT_ACTION_LABEL_EQUIP or L["Equip"] end
    if C_Item.GetItemSpell and C_Item.GetItemSpell(info.itemID) then return CONTEXT_ACTION_LABEL_USE or L["Use"] end
    return nil
end

-- Deletes the item once the menu row has asked twice. The game's own delete
-- question can't be used: it opens inside the call that asks for it, so asked
-- from here it carries Daylight UI's taint, and with the controller UI on its
-- focus then breaks the controller for the rest of the session.
function Window.PadDestroy(b)
    local info, bag, slot = padItem(b)
    if not info or InCombatLockdown() or not (ItemLocation and C_Item.DeleteItem) then return end
    local guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
    if guid then C_Item.DeleteItem(guid) end
end

function Window.PadMore(b)
    local info = padItem(b)
    if not info then return end
    local keys, values = {}, {}
    if C_Item.GetItemSpell and C_Item.GetItemSpell(info.itemID) then
        keys[#keys + 1] = "bind"
        values.bind = CONTEXT_ACTION_LABEL_BIND_TO_GAMEPAD_ACTION_BAR or L["Put on a controller bar"]
    end
    -- Destroy asks again on the row itself ("Click again") before it goes through.
    keys[#keys + 1] = "destroy"
    values.destroy = CONTEXT_ACTION_LABEL_DESTROY_ITEM or L["Destroy"]
    if info.hyperlink then
        keys[#keys + 1] = "share"
        values.share = SHARE_IN_CHAT or L["Share in chat"]
    end
    DUI.Widgets.OpenMenu(b, keys, values, nil, function(k)
        if k == "bind" then
            DUI.Pad.BindAction({ icon = info.iconFileID, name = info.hyperlink,
                pickup = function() C_Item.PickupItem(info.itemID) end })
        elseif k == "destroy" then
            Window.PadDestroy(b)
        elseif k == "share" then
            local U = ChatFrameUtil
            if U and not U.InsertLink(info.hyperlink) then U.OpenChat(info.hyperlink) end
        end
    end, nil, { confirm = { destroy = true } })
end

-- The groups' headings, as stops LB and RB move the D-pad to.
local function padGroups(f)
    local heads = {}
    for _, h in ipairs(f.headings or {}) do
        if h:IsVisible() and type(h:GetTop()) == "number" then heads[#heads + 1] = h end
    end
    table.sort(heads, function(a, b)
        local ta, tb = a:GetTop(), b:GetTop()
        if ta ~= tb then return ta > tb end
        return a:GetLeft() < b:GetLeft()
    end)
    local at = DUI.Pad.Stop()
    local top, left = at and at.GetTop and at:GetTop(), at and at.GetLeft and at:GetLeft()
    local out, here = {}, nil
    for i, h in ipairs(heads) do
        out[i] = { Click = function() DUI.Pad.Settle(h) end }
        if at == h then
            here = i
        elseif type(top) == "number" and type(left) == "number" and h:GetTop() >= top and h:GetLeft() <= left + 1 then
            here = i
        end
    end
    return out, here
end

function Window.PadSetup(f)
    f.padKeys = {
        { key = "X", label = function(b) return Window.PadUseLabel(f, b) end, button = "RightButton",
          secure = function(b)
              if not Window.PadUseLabel(f, b) then return nil end
              return { type = "click", clickbutton = b }
          end },
        { key = "Y", label = CONTEXT_ACTION_LABEL_MORE_ACTIONS or L["More"],
          when = function(b) return padItem(b) ~= nil end, run = Window.PadMore },
    }
    f.padTabs = function() return padGroups(f) end
    f.padTabsLabel = L["Groups"]
end

-- The item at the top left of the grid.
function Window.FirstSlot(f)
    local best, top, left
    for _, s in ipairs(f.set.Slots()) do
        local b = s.button
        if b:IsShown() then
            local t, l = b:GetTop(), b:GetLeft()
            if t and l and (not best or t > top or (t == top and l < left)) then
                best, top, left = b, t, l
            end
        end
    end
    return best
end

function Window.LayoutTools(f)
    local right
    for _, b in ipairs(f.tools) do
        b:ClearAllPoints()
        if b:IsShown() then
            if right then b:SetPoint("RIGHT", right, "LEFT", -4, 0)
            else b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Window.EDGE, -(Window.TITLE + Window.GAP)) end
            right = b
        end
    end
    if right then f.search:SetPoint("RIGHT", right, "LEFT", -6, 0)
    else f.search:SetPoint("RIGHT", f, "RIGHT", -Window.EDGE, 0) end
end

-- A chip shows only its groups; nothing picked shows everything. Custom groups
-- belong to All only. Recent is judged item by item (Window.ItemInChip).
function Window.InChip(f, key)
    local id = f and f.chip
    if not id then return true end
    for _, c in ipairs(Window.CHIPS) do
        if c.id == id then
            for _, g in ipairs(c.groups or {}) do if g == key then return true end end
        end
    end
    return false
end

-- Whether an item shows under the picked chip. New loot is judged by the group
-- it falls in once it's no longer new, so a fresh weapon still shows under Gear.
function Window.ItemInChip(f, facts, section)
    if not (f and f.chip) then return true end
    return Window.InChip(f, ns.Categories.Assign(facts, section, true))
end

function Window.PaintChips(f)
    for _, b in ipairs(f.chips or {}) do b.SetOn(b.id == (f.chip or "all")) end
end

-- Picks a chip (nil or "all" = everything). The grid view dims at once; the
-- categories view lays out again, gliding like a fold. quiet: closing, so the
-- categories view lays out on the next open instead of now.
function Window.PickChip(f, id, quiet)
    if id == "all" then id = nil end
    if f.chip == id then return end
    f.chip = id
    Window.PaintChips(f)
    if f.Setting("view") == "categories" then
        if quiet then
            f.stale = true
            return
        end
        ns.Layout.easing = true
        DUI.SafeCall(Window.Relayout, f)
        ns.Layout.easing = false
    else
        Window.MatchAll(f)
    end
end

-- Places the chips in as many lines as the grid's width needs and moves the
-- slots below them. Returns the chip block's height.
function Window.LayoutChips(f, width)
    local Wd = DUI.Widgets
    local top = -(Window.TITLE + Window.GAP + Window.ROW + Window.GAP)
    local x, line = 0, 0
    for _, b in ipairs(f.chips or {}) do
        local bw = b:GetWidth()
        if x > 0 and x + bw > width then x, line = 0, line + 1 end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT", Window.EDGE + x, top - line * (Wd.CHIP_HEIGHT + Wd.CHIP_GAP))
        x = x + bw + Wd.CHIP_GAP
    end
    local h = (line + 1) * Wd.CHIP_HEIGHT + line * Wd.CHIP_GAP
    f.items:ClearAllPoints()
    f.items:SetPoint("TOPLEFT", f, "TOPLEFT", Window.EDGE, top - h - Window.GAP)
    return h
end

-- The chip row under the search, one W.Chip per CHIPS entry.
function Window.Chips(f)
    f.chips = {}
    for _, c in ipairs(Window.CHIPS) do
        local b = DUI.Widgets.Chip(f, CHIP_LABEL[c.id]())
        b.id = c.id
        b.FitWidth()
        b:SetScript("OnClick", function() Window.PickChip(f, c.id) end)
        f.chips[#f.chips + 1] = b
    end
    Window.PaintChips(f)
end

-- Header tabs of the bag window: Bags (this window), Bank and Alts open the
-- bank and the saved characters. They sit right of the title like the other
-- windows' tabs, and the title, sub line and drag handle stop short of them.
function Window.LayoutTabs(f)
    if not f.tabs then return end
    local right
    for i = #f.tabs, 1, -1 do
        local b = f.tabs[i]
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("RIGHT", right or f.close, "LEFT", -DUI.Win.TAB_GAP, 0)
            right = b
        end
    end
    local stop = right or f.close
    f.title:SetPoint("RIGHT", stop, "LEFT", -8, 0)
    f.sub:SetPoint("RIGHT", stop, "LEFT", -8, 0)
    f.handle:ClearAllPoints()
    f.handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.handle:SetPoint("RIGHT", stop, "LEFT", -4, 0)
    f.handle:SetHeight(Window.TITLE)
end

function Window.Tabs(f)
    f.tab = "bags"
    DUI.Win.Tabs(f, {
        { id = "bags", text = L["Bags"] },
        { id = "bank", text = BANK or L["Bank"] },
        { id = "alts", text = L["Alts"] },
    }, function(id)
        -- This window is the bags: the tab springs back once the other part is open.
        DUI.Win.PickTab(f, "bags")
        if id == "bank" then ns.Viewer.OpenBank()
        elseif id == "alts" then ns.Viewer.OpenAlts() end
    end)
    Window.SyncTabs(f)
end

-- Alts is hidden while the viewer is switched off; the other tabs close up.
function Window.SyncTabs(f)
    if not f.tabs then return end
    for _, b in ipairs(f.tabs) do
        if b.id == "alts" then b:SetShown(ns.Viewer.On()) end
    end
    Window.LayoutTabs(f)
end

function Window.Sort()
    if InCombatLockdown and InCombatLockdown() then return end
    if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then pcall(PlaySound, SOUNDKIT.UI_BAG_SORTING_01) end
    if ns.Keep.Any() then return ns.Keep.Sort() end
    pcall(C_Container.SortBags)
end

-- Puts an icon in the header's round portrait, cropped like our other icons.
function Window.SetPortrait(f, file, l, r, t, b)
    if not f.portrait then return end
    f.portrait:SetTexture(file)
    if l then f.portrait:SetTexCoord(l, r, t, b) else DUI.Style.CropIcon(f.portrait) end
    f.portrait:SetShown(file and true or false)
    f.portraitRim:SetShown(file and true or false)
end

-- The sub line under the title. The bag reads "<name> · 12 of 32 free", the bank
-- "12 of 32 free" (the number in the accent, warn or bad colors when low); the
-- viewer paints its own through spec.updateSub.
function Window.UpdateSub(f)
    if not f or not f.sub then return end
    DUI.Style.InkText(f.sub, "LABEL")
    if f.spec.updateSub then return f.spec.updateSub(f) end
    local bag = f.spec.kind == "bag"
    local free, total = f.set.Free(bag)
    if type(free) ~= "number" or type(total) ~= "number" or total == 0 then return f.sub:SetText("") end
    local role = bag and ((free <= Window.FREE_BAD and "BAD") or (free <= Window.FREE_WARN and "WARN")) or nil
    local hex = DUI.Win.Parts.Hex(role and DUI.Style.INK[role] or { DUI.Style.Pop() })
    local count = hex .. free .. "|r"
    local name = bag and DUI.UnitName("player", "player")
    -- A name can be secret in combat; it is only shown when it is plain text.
    if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
        f.sub:SetText(string.format(L["%s · %s of %d free"], name, count, total))
    else
        f.sub:SetText(string.format(L["%s of %d free"], count, total))
    end
end

-- Footer free slots and money (plus the window's own pieces). Only while shown;
-- opening fills the footer (FillDirty).
function Window.UpdateFooter(f)
    f = f or ns.window
    if not f or not f:IsShown() then return end
    -- For the bag, count plain bags only (a profession bag only holds its own item
    -- type), so the count and its color match the data text. After it, each
    -- profession bag type's free slots in that type's color (the accent if it has
    -- none): "30 / 3".
    local bag = f.spec.kind == "bag"
    local free, total = f.set.Free(bag)
    if bag then
        local s = tostring(free)
        for _, e in ipairs(f.set.FreeSpecial()) do
            local c = ns.Items.BAG_COLORS[e.kind]
            local hex = DUI.Win.Parts.Hex(c and c.color or { DUI.Style.Pop() })
            s = s .. " / " .. hex .. e.free .. "|r"
        end
        f.free:SetText(s)
    else
        f.free:SetText(string.format("%d / %d", free, total))
    end
    local role = "pop"   -- free slots use the accent, read at paint time
    if bag and type(free) == "number" then
        role = (free <= Window.FREE_BAD and "BAD") or (free <= Window.FREE_WARN and "WARN") or "pop"
    end
    DUI.Style.InkText(f.free, role)
    Window.UpdateFreeBar(f, free, total, role)
    if f.spec.updateFooter then
        f.spec.updateFooter(f)
    else
        f.money:SetText(DUI.Widgets.Money(GetMoney and GetMoney() or 0))
    end
    if ns.Currency then ns.Currency.Update(f) end
    Window.UpdateSell(f)
    if bag then
        ns.Junk.MarkCheapest(f)
        Window.UpdateShards(f)
    end
    Window.UpdateSub(f)
end

-- The bar fills with the slots in use and eases there; warn and bad colors
-- when the bag is nearly full, the accent otherwise.
function Window.UpdateFreeBar(f, free, total, role)
    local W = DUI.Widgets
    if type(free) ~= "number" or type(total) ~= "number" or total <= 0 then
        return Style.SetBarValue(f.freeBar, 0, true)
    end
    local c = (role == "BAD" or role == "WARN") and Style.INK[role] or nil
    if c then W.BarFrom(f.freeBar, c[1], c[2], c[3]) else W.BarAccent(f.freeBar) end
    Style.SetBarValue(f.freeBar, (total - free) / total, not f.freeBar:IsVisible())
end

-- Sell junk shows at a vendor while something is worth selling, and says what
-- it comes to.
function Window.UpdateSell(f)
    if not f.sellJunk then return end
    local list = ns.Junk.vendorOpen and ns.Junk.Items() or {}
    local total = 0
    for _, item in ipairs(list) do total = total + item.value end
    if #list > 0 then
        f.sellJunk.SetLabel(string.format(L["Sell junk · %s"], DUI.Widgets.Money(total, { color = false })))
    end
    DUI.Widgets.EaseShown(f.sellJunk, #list > 0)
end

function Window.ShardLabel(n)
    return n == 1 and L["Delete 1 extra shard"] or string.format(L["Delete %d extra shards"], n)
end

-- Delete extra shards shows while a warlock carries more Soul Shards than their
-- limit, left of Sell junk when that's up.
function Window.UpdateShards(f)
    local b = f and f.dropShards
    if not b then return end
    local n = ns.Junk.ExtraShards()
    if n > 0 and n ~= f.shardsExtra then
        f.shardsExtra = n
        if b.Disarm then b.Disarm() end
        b.Paint()
    end
    local E = Window.EDGE
    b:ClearAllPoints()
    if f.sellJunk and f.sellJunk:IsShown() then
        b:SetPoint("BOTTOMRIGHT", f.sellJunk, "BOTTOMLEFT", -Window.GAP, 0)
    else
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -E, E + Window.FOOTER_ROW + Window.BAR_GAP)
    end
    DUI.Widgets.EaseShown(b, n > 0)
end

-- Keeping it up to date

-- Whether a window's slots can be laid out now: out of combat, or in combat if
-- the game's bag buttons aren't protected (the game lays out its own bags in combat).
function ns.CanLayout(f)
    if not (InCombatLockdown and InCombatLockdown()) then return true end
    for _, s in ipairs((f or ns.window).set.Slots()) do
        local ok, protected = pcall(s.button.IsProtected, s.button)
        if not ok or protected then return false end
        break
    end
    return true
end

-- Sizes a window from its grid. synced: slots were just synced (Window.Changed),
-- so skip that. moved: only items moved (same slots, same settings), so only
-- slots whose combined count changed or whose fill is stale get refilled;
-- otherwise every slot does.
local countBefore = {}
function Window.Relayout(f, synced, moved)
    if not f or not ns.module then return end
    if not ns.CanLayout(f) then
        DUI.AfterCombat(function() Window.Relayout(f) end, "bags:layout:" .. f.kind)
        return
    end
    f.stale = false
    if moved then
        wipe(countBefore)
        for _, s in ipairs(f.set.Slots()) do countBefore[s.button] = s.button.dluiCount or false end
    else
        Window.MarkDirty(f)
    end
    if not synced then f.set.Sync(f.items) end
    local w, h = ns.Layout.Apply(f, f.Cfg())
    if moved then
        for _, s in ipairs(f.set.Slots()) do
            -- A bag that didn't change can still hold an item its last fill missed. This
            -- layout shows it, so it needs its icon.
            if (s.button.dluiCount or false) ~= countBefore[s.button]
                or ns.Items.Outdated(s.button, ns.Items.InfoAt(s.bag, s.button:GetID())) then
                Window.MarkDirty(f, s.bag)
            end
        end
        wipe(countBefore)
    end
    local E = Window.EDGE
    f.items:SetSize(w, math.max(h, 1))
    -- Header, tool row, slots and footer, a gap between each; the footer sits on the edge.
    local W = w + E * 2
    local chipH = Window.LayoutChips(f, w)
    local H = Window.TITLE + Window.GAP + Window.ROW + Window.GAP + chipH + Window.GAP + h + Window.GAP + Window.FOOTER + E
    -- A fold (heading click) glides the window to its new size along with the slots
    -- (Layout.Ease); anything else snaps.
    local Feel = DUI.Win.Feel
    if ns.Layout.easing and f:IsShown() then
        Feel.Size(f, W, H, DUI.Motion.NORMAL)   -- in step with the slots' Feel.Glide
    else
        if Feel.Moving(f) then Feel.Settle(f) end
        f:SetSize(W, H)
    end
    if f.kind == "bag" and ns.Slots then ns.Slots.Layout() end
    if f.spec.afterLayout then f.spec.afterLayout(f) end
end

-- Marks what a window still needs to fill: f.dirty[bag] = true for one bag, or
-- every bag when bag is nil (f.dirtyAll). Filled on open, or earlier on idle
-- frames (Prep.lua).
function Window.MarkDirty(f, bag)
    if bag == nil then f.dirtyAll = true else f.dirty[bag] = true end
    if ns.Prep then ns.Prep.Dirtied(f, bag) end
end

-- Fills slots of the dirty bags (all of them for dirtyAll), and cooldowns if
-- one changed while closed.
function Window.FillDirty(f)
    local all, dirty = f.dirtyAll, f.dirty
    if all or next(dirty) then
        local owner = GameTooltip and GameTooltip:GetOwner()
        for _, s in ipairs(f.set.Slots()) do
            if all or dirty[s.bag] then ns.Items.Fill(s.button, owner) end
        end
    end
    if f.cdDirty and not all then
        for _, s in ipairs(f.set.Slots()) do ns.Items.FillCooldown(s.button) end
    end
    f.dirtyAll, f.cdDirty = false, false
    wipe(dirty)
    Window.UpdateFooter(f)
end

-- Fills a window's shown slots from the game; if closed, only marks them. The
-- categories view also groups by contents, so it re-lays out too.
function Window.FillAll(f)
    if not f then return end
    if not f:IsShown() then
        if f.Setting("view") == "categories" then f.stale = true end
        Window.MarkDirty(f)
        return
    end
    f.dirtyAll = true
    Window.FillDirty(f)
end

-- New search text: each slot only dims or lights up (Items.Match), nothing is
-- filled or laid out (groups don't follow the search). Runs while closed too, so
-- clearing the search on close leaves nothing dimmed for the next open.
function Window.MatchAll(f)
    if not f then return end
    for _, s in ipairs(f.set.Slots()) do ns.Items.Match(s.button) end
end

-- Bags changed (`bags` = the changed ids, nil = maybe all). Resync pools and
-- layout if the slots changed, then fill those bags. The categories view and
-- grouped empty slots also depend on contents.
function Window.Changed(f, bags)
    if not f or f.spec.still then return end
    local changed, synced = false, false
    if not (InCombatLockdown and InCombatLockdown()) then
        changed, synced = f.set.Sync(f.items), true
    else
        -- One cached function and key per window (loot in a fight calls this often).
        if not f.changedLater then
            f.changedLater = function() Window.Changed(f) end
            f.changedKey = "bags:changed:" .. f.kind
        end
        DUI.AfterCombat(f.changedLater, f.changedKey)
    end
    local laidOut = false
    local relay = changed or f.Setting("emptySlots") == "grouped" or f.Setting("view") == "categories"
    if relay and not changed and f:IsShown() and ns.Layout.Holds(f) then
        -- Open, and items only left (fast selling): slots stay put and the next open
        -- lays it out (Layout.Holds).
        relay = false
        f.stale = true
        for bag in pairs(ns.Layout.Hold(f)) do Window.MarkDirty(f, bag) end
    end
    if relay then
        if f:IsShown() or changed then
            laidOut = ns.CanLayout(f)
            -- Same slots: only the changed bags and moved counts refill.
            Window.Relayout(f, synced, synced and not changed)
        else
            f.stale = true
        end
    end
    if laidOut and changed then
        -- Relayout marked every bag dirty; a closed window fills them later.
        if f:IsShown() then Window.FillDirty(f) end
    elseif not bags then
        Window.FillAll(f)
    else
        for bag in pairs(bags) do Window.MarkDirty(f, bag) end
        if f:IsShown() then Window.FillDirty(f) end
    end
end

function ns.Relayout() for _, f in ipairs(ns.windows) do Window.Relayout(f) end end
function ns.FillAll() for _, f in ipairs(ns.windows) do Window.FillAll(f) end end
function ns.BagsChanged(bags) for _, f in ipairs(ns.windows) do Window.Changed(f, bags) end end

-- Re-checks usability and updates only the red tint (no fill). Out of combat
-- every slot (learning a recipe turns its other copies red, unlearning a skill
-- turns gear red); in combat only red slots and recipes (Items.Retint).
function ns.RecheckUnusable()
    local all = not ns.Items.InCombat()
    for _, f in ipairs(ns.windows) do
        if not f.spec.still then
            for _, s in ipairs(f.set.Slots()) do ns.Items.Retint(s.button, all) end
        end
    end
end

-- Cooldowns: shown windows' slots on the next frame (a cast can bring a burst
-- of these); closed ones are marked for later.
local function fillCooldowns()
    for _, f in ipairs(ns.windows) do
        if f:IsShown() then
            for _, s in ipairs(f.set.Slots()) do ns.Items.FillCooldown(s.button) end
        else
            f.cdDirty = true
            if ns.Prep then ns.Prep.CooldownsDirtied(f) end
        end
    end
end

-- Runs fn once on the next frame, however many times it's requested this frame.
local function soon(fn)
    local armed = false
    local function run()
        armed = false
        fn()
    end
    return function()
        if armed then return end
        armed = true
        C_Timer.After(0, run)
    end
end

local function registerEvents()
    -- Bags changed during a burst; only those get refilled.
    local changedBags = {}
    DUI.RegisterEvent("BAG_UPDATE", function(_, bag)
        if type(bag) == "number" then changedBags[bag] = true end
    end)
    DUI.RegisterEvent("BAG_UPDATE_DELAYED", function()
        ns.BagsChanged(next(changedBags) and changedBags or nil)
        wipe(changedBags)
    end)
    -- A bag was equipped or removed. Not PLAYER_EQUIPMENT_CHANGED: gear moving to or
    -- from a bag fires that bag's BAG_UPDATE, and the game's bags ignore it too.
    DUI.RegisterEvent("BAG_CONTAINER_UPDATE", function() ns.BagsChanged() end)
    -- Refill every slot once on the next frame (one fill, not one per event).
    local fillAll = soon(ns.FillAll)
    DUI.RegisterEvent("EQUIPMENT_SETS_CHANGED", fillAll)
    -- Level up: usability is re-checked during that one fill.
    DUI.RegisterEvent("PLAYER_LEVEL_UP", function() ns.Items.ForgetUsable(); fillAll() end)
    DUI.RegisterEvent("INVENTORY_SEARCH_UPDATE", fillAll)
    DUI.RegisterEvent("BAG_NEW_ITEMS_UPDATED", fillAll)
    -- A slot's quest mark (GetContainerItemQuestInfo: a quest item, or a quest it
    -- starts and whether that's in the log) only changes when a quest is accepted or
    -- leaves the log, not when an objective ticks (UNIT_QUEST_LOG_CHANGED). The
    -- game's bags make the same choice.
    DUI.RegisterEvent("QUEST_ACCEPTED", fillAll)
    DUI.RegisterEvent("QUEST_REMOVED", fillAll)
    -- Usability changed (skill up, recipe learned): re-check the red tint without a
    -- fill, since weapon skills go up often in combat.
    local recheck = soon(ns.RecheckUnusable)
    for _, event in ipairs({ "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED" }) do
        DUI.RegisterEvent(event, function() ns.Items.ForgetUsable(); recheck() end)
    end
    DUI.RegisterEvent("ITEM_LOCK_CHANGED", function(_, bag, slot)
        if type(slot) ~= "number" then return end
        for _, f in ipairs(ns.windows) do
            local btn = f.set.Button(bag, slot)
            if btn and f:IsShown() then ns.Items.FillLocked(btn)
            elseif btn then Window.MarkDirty(f, bag) end
        end
    end)
    DUI.RegisterEvent("BAG_UPDATE_COOLDOWN", soon(fillCooldowns))
    DUI.RegisterEvent("PLAYER_MONEY", function() for _, f in ipairs(ns.windows) do Window.UpdateFooter(f) end end)
    DUI.RegisterEvent("CURRENCY_DISPLAY_UPDATE", function() if ns.window then Window.UpdateFooter(ns.window) end end)
end

-- The bag

local function bagWindow()
    local f = Window.Create({
        kind = "bag", name = Window.NAME, title = "Bags", set = ns.Bags, prefix = "",
        portrait = Window.BAGS_ICON,
        defaultPoint = Window.DEFAULT_POINT,
        onClose = function() ns.OpenClose.CloseAll() end,
        onShow = function() ns.Stack.Run() end,
        onTitleRightClick = function() ns.Viewer.ToggleBank() end,
        tools = {
            { key = "sort", icon = Window.SORT_ICON, title = BAG_CLEANUP_BAGS or L["Clean Up Bags"], onClick = function() Window.Sort() end },
            { key = "slotsButton", icon = Window.BAGS_ICON, title = L["Bag slots"], desc = L["Show your bag slots: drag a bag out, or drop one in."],
              onClick = function(w) w.Set("showSlots", not w.Setting("showSlots")) end },
            { key = "viewButton", icon = Window.VIEW_ICON, title = L["Shelf or grid"],
              desc = L["Switch between Shelf, grouped by kind, and Grid, bag by bag."],
              onClick = function(w) w.Set("view", w.Setting("view") == "categories" and "grid" or "categories") end },
            -- Last, next to the search. Only shown to characters who know Disenchant
            -- (Disenchant.lua puts a secure button over it on hover).
            { key = "disenchantButton", icon = ns.Disenchant.ICON, title = ns.Disenchant.Title,
              desc = L["Click, then click an item to disenchant it. Not during a fight."], onClick = function() end },
        },
    })
    ns.window = f
    Window.Tabs(f)
    return f
end

-- Build and refresh

function ns.Build(mod)
    ns.module = mod
    DUI.SafeCall(ns.UpgradeBank, DUI.DB.Active())
    if not mod.db.enabled then return end
    -- Warn about other bag addons (the setup guide's list: Baganator, Bagnon).
    for _, c in ipairs(DUI.InstallerPages.ClashesFor("Bags")) do DUI.WarnIfLoaded(c.addon, c.label, c.what) end
    DUI.AfterCombat(function()
        local f = bagWindow()
        if ns.Slots then ns.Slots.Create(f) end
        registerEvents()
        ns.Disenchant.Register(f)
        ns.Prep.Start(f)
        ns.Junk.Register()
        ns.Guard.Register()
        ns.Repair.Register()
        ns.Layout.Register()
        -- This addon's search decides what dims; the game's own search stays empty.
        pcall(C_Container.SetItemSearch, "")
        ns.OpenClose.Take()
        if ns.Bank then ns.Bank.Build() end
        ns.Viewer.Build()
        ns.Saved.Start()
        for _, w in ipairs(ns.windows) do
            Window.Place(w)
            DUI.Win.Repaint(w)
            Window.Relayout(w)
        end
    end, "bags:build")
end

function ns.Refresh(mod)
    ns.module = mod
    if not ns.window then return end
    DUI.AfterCombat(function()
        for _, w in ipairs(ns.windows) do
            Window.Place(w)
            DUI.Win.Repaint(w)
            Window.Relayout(w)
            Window.FillAll(w)
        end
        if ns.Slots then ns.Slots.Apply() end
        if ns.Bank and ns.Bank.Refresh then ns.Bank.Refresh() end
        ns.Viewer.Sync()
    end, "bags:refresh")
end

-- Setup tour stop (Tour.lua). Opening the game's bags from here would run its
-- bag code tainted (see OpenClose.lua), so the player opens them (the card says
-- how) and the highlight glides onto the window once it's up.

local function bagsOpen() return ns.window ~= nil and ns.window:IsVisible() end

-- The player's own bag key (B unless rebound).
local function bagKey()
    if type(GetBindingKey) == "function" then
        local key = GetBindingKey("OPENALLBAGS")
        if type(key) == "string" and key ~= "" then
            return type(GetBindingText) == "function" and GetBindingText(key, true) or key
        end
    end
    return "B"
end

DUI.Tour.Add("bags", {
    order = 30,
    title = L["Bags in groups"],
    text = function()
        local pop = DUI.Tour.Pop
        if not bagsOpen() then
            return string.format(L["Your bags sort items into groups by kind. Press %s to open them."], pop(bagKey()))
        end
        return string.format(L["%s an item to move it to another group, lock it so it's never sold, or sell it as junk. The %s and %s tabs at the top show your bank and your other characters' bags from anywhere."],
            pop(L["Alt-right-click"]), pop(BANK or L["Bank"]), pop(L["Alts"]))
    end,
    available = function() return ns.module ~= nil and DUI:Get("Bags", "enabled") ~= false end,
    wait = true,
    part = function() return ns.window end,
})
