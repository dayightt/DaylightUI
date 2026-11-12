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
Window.TITLE = DUI.Win.COMPACT   -- title bar height, the window kit's compact header
Window.ROW = 22              -- tool row height (search and buttons)
Window.GAP = 6               -- between rows
Window.FOOTER = 18
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
    b:SetHeight(Window.FOOTER)
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

    -- The window kit's compact header: title, X, accent line.
    DUI.Win.Header(f, { compact = true, onClose = spec.onClose })
    DUI.Win.WheelScale(f, function() return f.Setting("scale") end, function(v) f.Set("scale", v) end, 0.5, 1.5)
    f.title:SetText(L[spec.title])

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

    f.items = CreateFrame("Frame", nil, f)
    f.items.dluiWindow = f
    f.items:SetPoint("TOPLEFT", f, "TOPLEFT", E, top - Window.ROW - Window.GAP)

    f.free = text(f, Window.TEXT_SIZE, "LEFT")
    f.free:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", E, E)
    DUI.Style.InkText(f.free, "VALUE")
    f.money = text(f, Window.TEXT_SIZE, "RIGHT")
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -E, E)
    if spec.footer then spec.footer(f) end

    f:SetScript("OnHide", function(self)
        -- A search only lasts while the window is open.
        if self.search:GetText() ~= "" then self.search:SetText("") end
        self.match = nil
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
    if DUI.Motion then DUI.Motion.Window(f) end
    ns.windows[#ns.windows + 1] = f
    return f
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

function Window.Sort()
    if InCombatLockdown and InCombatLockdown() then return end
    if type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then pcall(PlaySound, SOUNDKIT.UI_BAG_SORTING_01) end
    if ns.Keep.Any() then return ns.Keep.Sort() end
    pcall(C_Container.SortBags)
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
    if f.spec.updateFooter then
        f.spec.updateFooter(f)
    else
        f.money:SetText(DUI.MoneyString(GetMoney and GetMoney() or 0))
    end
    if ns.Currency then ns.Currency.Update(f) end
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
    local W, H = w + E * 2, Window.TITLE + Window.GAP + Window.ROW + Window.GAP + h + Window.GAP + Window.FOOTER + E
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
        defaultPoint = Window.DEFAULT_POINT,
        onClose = function() ns.OpenClose.CloseAll() end,
        onShow = function() ns.Stack.Run() end,
        onTitleRightClick = function() ns.Viewer.ToggleBank() end,
        tools = {
            { key = "sort", icon = Window.SORT_ICON, title = BAG_CLEANUP_BAGS or L["Clean Up Bags"], onClick = function() Window.Sort() end },
            { key = "viewerButton", icon = ns.Viewer.ICON, title = L["Bank and alts"],
              desc = L["Your bank and your other characters' bags, from anywhere."], onClick = function(w) ns.Viewer.Menu(w.viewerButton) end,
              hint = L["Right-click: your bank"], onRightClick = function() ns.Viewer.ToggleBank() end },
            { key = "slotsButton", icon = Window.BAGS_ICON, title = L["Bag slots"], desc = L["Show your bag slots: drag a bag out, or drop one in."],
              onClick = function(w) w.Set("showSlots", not w.Setting("showSlots")) end },
            { key = "viewButton", icon = Window.VIEW_ICON, title = L["Categories or bags"],
              desc = L["Switch between items grouped by kind and the plain bag-by-bag grid."],
              onClick = function(w) w.Set("view", w.Setting("view") == "categories" and "grid" or "categories") end },
            -- Last, next to the search. Only shown to characters who know Disenchant
            -- (Disenchant.lua puts a secure button over it on hover).
            { key = "disenchantButton", icon = ns.Disenchant.ICON, title = ns.Disenchant.Title,
              desc = L["Click, then click an item to disenchant it. Not during a fight."], onClick = function() end },
        },
    })
    ns.window = f
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
        return string.format(L["%s an item to move it to another group, lock it so it's never sold, or sell it as junk. %s at the top shows your bank and your other characters' bags from anywhere."],
            pop(L["Alt-right-click"]), pop(L["Bank and alts"]))
    end,
    available = function() return ns.module ~= nil and DUI:Get("Bags", "enabled") ~= false end,
    wait = true,
    part = function() return ns.window end,
})
