-- Grid layout: bag slots in rows, then the profession bag's after a thin line
-- (or inline when merged), then the keyring's after another. With empty slots
-- grouped, each section shows its items and then one free tile (its first empty
-- slot, labeled with the free count).
--
-- Only lays out when slots change, a setting changes, or (grouped) contents
-- change, and never in combat. While open, items leaving (sold, used) don't
-- trigger a layout: their slots stay put and empty so nothing slides under the
-- cursor (Layout.Holds). The next open lays it out.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Layout = {}
ns.Layout = Layout

Layout.SECTION_GAP = 6       -- above and below a section divider
Layout.LINE = { 0.28, 0.28, 0.3, 0.8 }

local function slotsInView(window)
    return window.set.Slots()
end

local function isEmpty(bag, slot)
    return ns.Items.InfoAt(bag, slot) == nil
end

-- A slot's contents as far as layout cares (false = empty), and its count.
local function itemIn(bag, slot)
    local info = ns.Items.InfoAt(bag, slot)
    if not info then return false end
    return info.itemID or info.hyperlink or true, info.stackCount or 1
end

local function bagOf(btn)
    local holder = btn:GetParent()
    return holder and holder:GetID()
end

-- Records what each slot held when laid out (window.laid[button]), plus the
-- grouped free tiles (window.tiles: { button, slots, key }) so Layout.Hold can
-- recount them.
local function noteLaid(window)
    window.laid = window.laid or {}
    wipe(window.laid)
    for _, s in ipairs(window.set.Slots()) do
        window.laid[s.button] = itemIn(s.bag, s.button:GetID())
    end
    window.held = window.held or {}
    wipe(window.held)
    window.tiles = window.tiles or {}
    wipe(window.tiles)
end

-- A free tile: its button shows how many of `slots` are empty. key names the
-- tile itself, so an eased layout can move it like an item when another empty
-- slot becomes the tile.
local function noteTile(window, button, slots, key)
    if window.tiles then window.tiles[#window.tiles + 1] = { button = button, slots = slots, key = key } end
end

-- Sections in order, each a list of slots ({ button, bag, section }).
function Layout.Sections(slots, merged)
    local order, by = {}, {}
    for _, s in ipairs(slots) do
        local key = s.section
        if key == "profession" and merged then key = "bags" end
        if not by[key] then
            by[key] = {}
            order[#order + 1] = key
        end
        table.insert(by[key], s)
    end
    local out = {}
    for _, key in ipairs(order) do out[#out + 1] = { key = key, slots = by[key] } end
    return out
end

-- Grouped empty slots: a section's items, then one free tile per bag type
-- (ordinary, herb, soul... each in its bag's color) using the first empty slot
-- of that type, other empty slots hidden. Also returns slot -> free count for
-- each tile. members: type -> every slot of that bag type in the section
-- (what its tile counts).
function Layout.Group(section)
    local shown, tiles, frees, tileOf, members, kinds = {}, {}, {}, {}, {}, {}
    for _, s in ipairs(section.slots) do
        local kind = kinds[s.bag]
        if kind == nil then
            kind = ns.Items.BagKind(s.bag)
            kinds[s.bag] = kind
        end
        members[kind] = members[kind] or {}
        table.insert(members[kind], s)
        if isEmpty(s.bag, s.button:GetID()) then
            local tile = tileOf[kind]
            if not tile then
                tileOf[kind] = s
                tiles[#tiles + 1] = s
                frees[s] = 1
            else
                frees[tile] = frees[tile] + 1
                s.button:Hide()
            end
        else
            shown[#shown + 1] = s
        end
    end
    for _, t in ipairs(tiles) do shown[#shown + 1] = t end
    return shown, frees, tiles, members, kinds
end

local function line(window, i)
    window.lines = window.lines or {}
    local l = window.lines[i]
    if not l then
        l = window.items:CreateTexture(nil, "ARTWORK")
        local c = Layout.LINE
        l:SetColorTexture(c[1], c[2], c[3], c[4])
        window.lines[i] = l
    end
    return l
end

-- Categories view

Layout.HEAD_SIZE = DUI.Style.SIZE.tiny
Layout.HEAD_TEXT = math.ceil(Layout.HEAD_SIZE * 1.2)   -- the heading's text row: its line height
Layout.HEAD_DIM = DUI.Style.INK.LABEL

-- The Shelf's spacing is drawn to a reference picture whose slots are 70 px
-- across, rings included. Each length below is in that picture's pixels as seen
-- on screen and scales with the slot size, so a bigger or smaller iconSize keeps
-- the same proportions. Slots within a group keep the player's spacing setting.
Layout.REF_SLOT = 70
Layout.REF = {
    pad = 6,         -- from the heading's text row down to its line
    line = 2,        -- the line's thickness (never under LINE_MIN_PX)
    toRing = 4,      -- from the line down to the first ring's outer edge
    rowGap = 10,     -- from the last ring's outer edge to the next heading's top
    groupGap = 18,   -- between groups side by side, ring edge to ring edge
    inset = 4,       -- a heading and its line start and end this far inside the rings
}
Layout.LINE_MIN_PX = 2       -- one pixel read as too thin

-- A reference length at this slot size, in whole units like every other spot in
-- the Shelf (fractions added up differently along a row and a glide), at least one.
function Layout.Ref(window, cfg, px)
    return math.max(1, math.floor(px * cfg.iconSize / Layout.REF_SLOT + 0.5))
end

local function cfgOf(window, cfg) return cfg or window.Cfg() end

-- The line under a heading, on whole pixels.
function Layout.LineH(window, cfg)
    cfg = cfgOf(window, cfg)
    local Pixel = DUI.Pixel
    local scaled = Pixel.Snap(window.items, Layout.REF.line * cfg.iconSize / Layout.REF_SLOT)
    return math.max(scaled, Pixel.Px(window.items, Layout.LINE_MIN_PX))
end

-- The whole heading: its text row, the room under it and the line at its
-- bottom, rounded up to a whole unit.
function Layout.HeadH(window, cfg)
    cfg = cfgOf(window, cfg)
    local line = math.ceil(Layout.LineH(window, cfg) - 0.001)
    return Layout.HEAD_TEXT + Layout.Ref(window, cfg, Layout.REF.pad) + line
end

-- Never so tight that a heading's count meets the next group's chevron or their
-- click areas overlap, which small slots would otherwise do.
function Layout.GroupGap(window, cfg)
    cfg = cfgOf(window, cfg)
    local clear = Layout.HEAD_REACH + Layout.HEAD_AIR - 2 * Layout.Ref(window, cfg, Layout.REF.inset)
    return math.max(Layout.Ref(window, cfg, Layout.REF.groupGap), clear)
end
function Layout.RowGap(window, cfg)
    return Layout.Ref(window, cfgOf(window, cfg), Layout.REF.rowGap)
end

-- Where a group's first slot starts below its heading's top.
function Layout.SlotTop(window, cfg)
    cfg = cfgOf(window, cfg)
    return Layout.HeadH(window, cfg) + Layout.Ref(window, cfg, Layout.REF.toRing)
end

Layout.HEAD_CHEV = 6         -- chevron size, a little smaller than the name
Layout.HEAD_CHEV_GAP = 2     -- between the chevron and the name
Layout.HEAD_REACH = Layout.HEAD_CHEV + Layout.HEAD_CHEV_GAP + 2   -- how far a heading's click area reaches left
Layout.HEAD_AIR = 2          -- the least room between one heading's click area and the next
Layout.FOLDED_TURN = math.pi / 2   -- the chevron points right while folded
Layout.SHELF_INSET = 4       -- extra left margin in the Shelf, where the chevrons hang

-- The line under an open heading, in the group's color at this strength.
Layout.RULE_ALPHA = 0.55
Layout.COUNT_ALPHA = 0.7     -- an open group's count, a little dimmer than its name

-- The line under a heading: the group's color, or while folded (no color
-- given) the same dim line an empty slot's ring has.
function Layout.PaintRule(rule, r, g, b)
    local c = ns.Items.EMPTY
    if r then
        rule:SetColorTexture(r, g, b, Layout.RULE_ALPHA)
    else
        rule:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

-- Group heading: upper case name and count over the group's first slot, a line
-- under them the width of the group, and the chevron hanging in the margin to
-- the left of the name. A click folds or unfolds it, a right-click on Recent clears it,
-- and an item dropped or clicked onto it from the cursor gets pinned to the group.
local function heading(window, i)
    window.headings = window.headings or {}
    local h = window.headings[i]
    if h then return h end
    h = CreateFrame("Button", nil, window.items)
    h.chev = DUI.Widgets.Icon(h, "ui-chevron.png", Layout.HEAD_CHEV, DUI.Style.INK.LABEL)
    h.text = DUI.Style.Text(h, Layout.HEAD_SIZE, "LEFT")
    -- Centered on the text row at the top, with the line at the bottom.
    h.text:SetPoint("LEFT", h, "TOPLEFT", 0, 1 - Layout.HEAD_TEXT / 2)
    h.chev:SetPoint("RIGHT", h.text, "LEFT", -Layout.HEAD_CHEV_GAP, 0)
    -- The chevron sits outside the heading, so it takes clicks too.
    h:SetHitRectInsets(-Layout.HEAD_REACH, 0, 0, 0)
    h.count = DUI.Style.Text(h, DUI.Style.SIZE.tiny, "LEFT")
    h.count:SetPoint("LEFT", h.text, "RIGHT", 5, 0)
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    h.rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    local function pinFromCursor(self)
        if not GetCursorInfo then return false end
        local kind, itemID = GetCursorInfo()
        if kind == "item" and type(itemID) == "number" then
            ns.Categories.Pin(itemID, self.key)
            if ClearCursor then ClearCursor() end
            return true
        end
    end
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:SetScript("OnClick", function(self, button)
        if pinFromCursor(self) then return end
        -- Recent's right-click: a menu to empty it now instead of waiting for its timer.
        if button == "RightButton" then
            if self.key == "recent" then
                DUI.Widgets.OpenMenu(self, { "clear" }, { clear = L["Clear recent items"] }, nil,
                    function() ns.Categories.ClearRecent() end, nil, { atCursor = true })
            end
            return
        end
        -- Mid-cleanup the fold would wait for the hold: end it first.
        ns.Window.SortTouched(window)
        -- The layout triggered by this click is animated (Layout.Ease).
        Layout.easing = true
        DUI.SafeCall(ns.Categories.ToggleCollapsed, self.key)
        Layout.easing = false
    end)
    h:SetScript("OnReceiveDrag", pinFromCursor)
    h:SetScript("OnEnter", function(self)
        self.hover = true
        Layout.PaintHeading(self, self.folded)
    end)
    h:SetScript("OnLeave", function(self)
        self.hover = nil
        Layout.PaintHeading(self, self.folded)
    end)
    window.headings[i] = h
    return h
end

-- Paints a heading from its name and fold state. Colors are read now, so a
-- change of accent or of a group's color repaints through the next layout. Open
-- groups read in their own color (Recent keeps the accent, letter by letter
-- under a gradient one), folded ones in the label color; the mouse over a heading
-- lifts it to the accent. The chevron turns as it folds.
function Layout.PaintHeading(h, folded)
    local Style, Motion = DUI.Style, DUI.Motion
    local lit = not folded or h.hover
    local shown = h.name and string.upper(h.name) or ""
    local gr, gg, gb
    if not folded then gr, gg, gb = ns.Categories.Color(h.key) end
    if lit and h.key == "recent" then
        Style.PaintAccentText(h.text, shown)
    else
        h.text:SetText(shown)
        if h.hover then
            h.text:SetTextColor(Style.Accent())
        elseif gr then
            h.text:SetTextColor(gr, gg, gb)
        elseif lit then
            h.text:SetTextColor(Style.Accent())
        else
            local d = Layout.HEAD_DIM
            h.text:SetTextColor(d[1], d[2], d[3])
        end
    end
    if gr then
        Layout.PaintRule(h.rule, gr, gg, gb)
    elseif not folded then
        Layout.PaintRule(h.rule, Style.Accent())
    else
        Layout.PaintRule(h.rule)
    end
    -- An open group's count wears its color a little dimmer; a folded one reads
    -- label, the "drag items here" hint stays quiet, and the mouse lifts it.
    if h.hover then
        Style.InkText(h.count, "pop")
    elseif gr and not h.empty then
        h.count:SetTextColor(gr, gg, gb, Layout.COUNT_ALPHA)
    elseif lit and not h.empty then
        Style.InkText(h.count, "pop")
    else
        Style.InkText(h.count, "LABEL")
    end
    if h.hover then
        h.chev:SetVertexColor(Style.Accent())
    elseif gr then
        h.chev:SetVertexColor(gr, gg, gb)
    elseif lit then
        h.chev:SetVertexColor(Style.Accent())
    else
        local d = Layout.HEAD_DIM
        h.chev:SetVertexColor(d[1], d[2], d[3])
    end
    local to = folded and Layout.FOLDED_TURN or 0
    if h.turnKey == h.key and h.turn ~= to and h:IsVisible() then
        h.chevKey = h.chevKey or {}
        Motion.Tween(h.chevKey, h.turn or 0, to, Motion.NORMAL, function(v) h.chev:SetRotation(v) end)
    else
        h.chev:SetRotation(to)
    end
    h.turn, h.turnKey, h.folded = to, h.key, folded
end

-- Stacks show separately while one of these is open so a stack can be split to
-- hand over (the split box only splits a real stack). Open ones: event -> true.
Layout.APART = {
    TRADE_SHOW = "TRADE_CLOSED",
    MAIL_SHOW = "MAIL_CLOSED",
    AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED",
}
Layout.apart = {}

-- Whether stacks of the same item are currently shown as one.
function Layout.Combining()
    return ns.Setting("combineStacks") ~= false and next(Layout.apart) == nil
end

-- Items that never stack but pile up, shown as one stack with a count (warlock
-- Soul Shards), and whether that's on right now.
Layout.PILES = { [6265] = true }
function Layout.Piling()
    return ns.Setting("stackShards") ~= false and next(Layout.apart) == nil
end

-- Whether a view lays items out by group (the Shelf and the list) rather than
-- bag by bag.
function Layout.Grouped(view) return view == "categories" or view == "list" end

-- Empty custom groups show always with "Show empty groups", otherwise only while
-- Shift is held with an item on the cursor, so they don't clutter the bag but
-- are there to drop on.
Layout.dropping = false
function Layout.ShowEmpty()
    return ns.Setting("emptyGroups") == true or Layout.dropping
end

-- Shift or cursor changed: re-lay out the open bag if that shows or hides the
-- empty groups.
function Layout.CheckDrop()
    local on = ns.Items.CursorBusy() and type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
    if on == Layout.dropping then return end
    Layout.dropping = on
    local f = ns.window
    if ns.Setting("emptyGroups") == true or not f or not f:IsShown() or not Layout.Grouped(ns.Setting("view")) then return end
    if #ns.Categories.Custom() > 0 then ns.Window.Relayout(f) end
end

local registered = false
function Layout.Register()
    if registered then return end
    registered = true
    DUI.RegisterEvent("MODIFIER_STATE_CHANGED", Layout.CheckDrop)
    DUI.RegisterEvent("CURSOR_CHANGED", Layout.CheckDrop)
    for show, closed in pairs(Layout.APART) do
        local function set(open)
            if (Layout.apart[show] == true) == open then return end
            Layout.apart[show] = open or nil
            ns.Relayout()
            ns.FillAll()
        end
        pcall(DUI.RegisterEvent, show, function() set(true) end)
        pcall(DUI.RegisterEvent, closed, function() set(false) end)
    end
end

-- Groups and their contents: { key, name, entries, breakBefore, breakAfter }.
-- An entry is { button, facts, total, order, extra }, where extra holds the
-- other stacks of the same item, hidden while combined.
function Layout.Groups(cfg, window)
    local Cat = ns.Categories
    -- Empty slots per section (bags, profession, keyring, bank...), in section order.
    -- members: every slot of a section and bag type, i.e. what its free tile counts.
    local lists, empties, sections, combine, members, kinds = {}, {}, {}, {}, {}, {}
    local combining, piling = Layout.Combining(), Layout.Piling()
    window = window or ns.window
    for i, s in ipairs((slotsInView(window))) do
        local btn = s.button
        local slot = btn:GetID()
        local kind = kinds[s.bag]
        if kind == nil then
            kind = ns.Items.BagKind(s.bag)
            kinds[s.bag] = kind
        end
        -- Split by section and bag type (a herb bag's empty slots get their own tile
        -- in its color).
        local ek = s.section .. "|" .. kind
        members[ek] = members[ek] or {}
        table.insert(members[ek], s)
        local info = ns.Items.InfoAt(s.bag, slot)
        if not info then
            if not empties[ek] then
                empties[ek] = {}
                sections[#sections + 1] = ek
            end
            table.insert(empties[ek], s)
        else
            local f = Cat.Facts(s.bag, slot, info)
            local key = Cat.Assign(f, s.section)
            -- Stack size not loaded yet (first time seen this session). Lay out again once
            -- it loads so it can combine.
            if combining and f.link and f.maxStack == nil then Layout.WaitForStack(window, s.bag, slot, f.link) end
            local pile = piling and f.itemID and Layout.PILES[f.itemID]
            local ck = (pile and (key .. "|" .. f.itemID))
                or ((combining and f.link and f.maxStack and f.maxStack > 1) and (key .. "|" .. f.link)) or nil
            local e = ck and combine[ck]
            if e then
                e.total = e.total + f.count
                e.extra[#e.extra + 1] = btn
            else
                e = { button = btn, facts = f, total = f.count, order = i, extra = {} }
                if ck then combine[ck] = e end
                lists[key] = lists[key] or {}
                table.insert(lists[key], e)
            end
        end
    end
    local out = {}
    for _, key in ipairs(Cat.Order()) do
        local g = Cat.Get(key)
        local entries = lists[key] or {}
        if key == "empty" then
            entries = {}
            for _, section in ipairs(sections) do
                local list = empties[section]
                if cfg.emptySlots == "grouped" then
                    if #list > 0 then
                        entries[#entries + 1] = { button = list[1].button, free = #list, empty = true }
                        noteTile(window, list[1].button, members[section], "free:" .. tostring(section))
                    end
                else
                    for _, s in ipairs(list) do entries[#entries + 1] = { button = s.button, empty = true } end
                end
            end
        else
            table.sort(entries, Cat.Before)
        end
        -- An empty custom group shows in the bag only while it can be dropped on
        -- (Layout.ShowEmpty); its heading is where the first item goes. Never in the
        -- bank's or a saved copy's list.
        if #entries > 0 or (g.custom and window == ns.window and Layout.ShowEmpty()) then
            out[#out + 1] = { key = key, name = g.name, entries = entries,
                              breakBefore = g.breakBefore, breakAfter = g.breakAfter }
        end
    end
    return out
end

-- Items whose stack size is still loading (link -> true), each waited on once per
-- session. When one loads, the window is laid out again (if shown, on the next
-- frame, once per burst), otherwise the next open does it (f.stale). Never
-- cleared: some links never report a stack size even when loaded (keystone:,
-- battlepet: cages). They would ask again on every layout, the game answers each
-- ask with ITEM_DATA_LOAD_RESULT, and the open bag would re-layout every frame.
local waited = {}
function Layout.WaitForStack(window, bag, slot, link)
    if waited[link] or not Item then return end
    -- A saved copy (Saved.lua) has no real bag slot, so load it by link.
    local make = ns.Saved.Is(bag) and Item.CreateFromItemLink or Item.CreateFromBagAndSlot
    if not make then return end
    local ok, item
    if ns.Saved.Is(bag) then ok, item = pcall(make, Item, link) else ok, item = pcall(make, Item, bag, slot) end
    if not ok or not item or item:IsItemEmpty() then return end
    waited[link] = true
    item:ContinueOnItemLoad(function()
        if not window:IsShown() then
            window.stale = true
            return
        end
        if window.dluiStackLoad then return end
        window.dluiStackLoad = true
        C_Timer.After(0, function()
            window.dluiStackLoad = nil
            if not window:IsShown() then
                window.stale = true
                return
            end
            ns.Window.Relayout(window)
            ns.Window.FillDirty(window)
        end)
    end)
end

-- Packing the Shelf. Each group is a box with one or more shapes ({ w, h, fill }):
-- a group too big for one row may be laid out a row taller and narrower, and fill
-- is the room its items really take, so a half-empty last row isn't counted as used.
-- Rows are built one at a time. A row starts with the next group in order, and is
-- tried at each height a waiting group could need. The space to its right is filled
-- by later groups, the one that fills the most first (ties keep order), and beside a
-- tall group shorter ones stack in columns. The row that wastes least is kept. A
-- group only ever moves earlier to fill a gap. Groups that must start or end a row
-- split the list into parts packed on their own. A box with `drawnH` is planned at
-- its shape's height and drawn at drawnH. `prev` (key -> { row, shape }) is
-- the last layout's answer: when two choices are equally good, the one that keeps
-- groups where they were wins, so a small change in counts moves little.
Layout.PACK_EVEN = 0.02      -- choices this close count as equally good

local function better(a, b)
    if not b then return true end
    local even = Layout.PACK_EVEN * math.max(a.fill, b.fill, 1)
    if a.fill > b.fill + even then return true end
    if b.fill > a.fill + even then return false end
    if a.kept ~= b.kept then return a.kept > b.kept end
    if a.order ~= b.order then return a.order < b.order end
    if a.shape ~= b.shape then return a.shape < b.shape end
    return a.stack and not b.stack
end

-- Fills one row of height `H` starting with box `lead` in shape `si`.
local function fillRow(boxes, todo, lead, si, H, maxW, gapX, gapY, prev, rowNo)
    local s = boxes[lead].shapes[si]
    local cols = { { x = 0, w = s.w, used = s.h } }
    local placed = { { i = lead, shape = si, x = 0, y = 0, col = 1 } }
    local taken = { [lead] = true }
    local fill, right = s.fill, s.w
    local function keeps(i, shape)
        local p = prev and prev[boxes[i].key]
        return (p and p.row == rowNo and 1 or 0) + (p and p.shape == shape and 1 or 0)
    end
    local kept = keeps(lead, si)
    while true do
        local best
        for order, i in ipairs(todo) do
            if not taken[i] then
                for k, sh in ipairs(boxes[i].shapes) do
                    if sh.h <= H then
                        local kp = keeps(i, k)
                        for ci, c in ipairs(cols) do
                            local room = ci == #cols and (maxW - c.x) or c.w
                            if sh.w <= room and c.used + gapY + sh.h <= H then
                                local cand = { fill = sh.fill, kept = kp, order = order, shape = k, stack = true,
                                               i = i, col = ci, x = c.x, y = c.used + gapY }
                                if better(cand, best) then best = cand end
                            end
                        end
                        if right + gapX + sh.w <= maxW then
                            local cand = { fill = sh.fill, kept = kp, order = order, shape = k, stack = false,
                                           i = i, x = right + gapX, y = 0 }
                            if better(cand, best) then best = cand end
                        end
                    end
                end
            end
        end
        if not best then break end
        local sh = boxes[best.i].shapes[best.shape]
        taken[best.i] = true
        placed[#placed + 1] = { i = best.i, shape = best.shape, x = best.x, y = best.y, col = best.col or #cols + 1 }
        fill, kept = fill + sh.fill, kept + best.kept
        if best.stack then
            local c = cols[best.col]
            c.used = best.y + sh.h
            if best.col == #cols and sh.w > c.w then
                c.w = sh.w
                right = c.x + c.w
            end
        else
            cols[#cols + 1] = { x = best.x, w = sh.w, used = sh.h }
            right = best.x + sh.w
        end
    end
    local rowH = 0
    for _, c in ipairs(cols) do rowH = math.max(rowH, c.used) end
    return { placed = placed, taken = taken, fill = fill, h = rowH, kept = kept, shape = si }
end

-- Packs `boxes` into `maxW`. Returns each box's { x, y, shape } by index, the total
-- height, and the answer to hand back as `prev` next time.
function Layout.Pack(boxes, maxW, gapX, gapY, prev)
    local spots, memo, y, rowNo = {}, {}, 0, 0
    local parts, part = {}, nil
    for i, b in ipairs(boxes) do
        if not part or b.breakBefore then
            part = {}
            parts[#parts + 1] = part
        end
        part[#part + 1] = i
        if b.breakAfter then part = nil end
    end
    for _, todo in ipairs(parts) do
        while #todo > 0 do
            rowNo = rowNo + 1
            local lead = todo[1]
            -- The heights a row could take: any waiting group's.
            local hs, seen = {}, {}
            for _, i in ipairs(todo) do
                for _, sh in ipairs(boxes[i].shapes) do
                    if not seen[sh.h] then seen[sh.h] = true; hs[#hs + 1] = sh.h end
                end
            end
            table.sort(hs)
            local best
            for si, s in ipairs(boxes[lead].shapes) do
                for _, H in ipairs(hs) do
                    if H >= s.h then
                        local r = fillRow(boxes, todo, lead, si, H, maxW, gapX, gapY, prev, rowNo)
                        r.density = r.fill / (maxW * (r.h + gapY))
                        local pick = not best
                        if best then
                            local even = Layout.PACK_EVEN * math.max(r.density, best.density)
                            if r.density > best.density + even then pick = true
                            elseif r.density >= best.density - even then
                                if r.kept ~= best.kept then pick = r.kept > best.kept
                                elseif r.h ~= best.h then pick = r.h < best.h
                                else pick = r.shape < best.shape end
                            end
                        end
                        if pick then best = r end
                    end
                end
            end
            -- The row's columns, and the groups stacked in each, read in group order;
            -- only which groups share the row comes from the packing. A box drawn
            -- shorter than planned (a folded group) collapses where it is: what's
            -- under it in its column moves up, nothing beside it moves.
            local byCol, list, rowH, cx = {}, {}, 0, 0
            for _, p in ipairs(best.placed) do
                local c = byCol[p.col]
                if not c then
                    c = { first = p.i, w = 0 }
                    byCol[p.col] = c
                    list[#list + 1] = c
                end
                c[#c + 1] = p
                c.first = math.min(c.first, p.i)
                c.w = math.max(c.w, boxes[p.i].shapes[p.shape].w)
                memo[boxes[p.i].key] = { row = rowNo, shape = p.shape }
            end
            table.sort(list, function(a, b) return a.first < b.first end)
            for _, c in ipairs(list) do
                table.sort(c, function(a, b) return a.i < b.i end)
                local cy = 0
                for k, p in ipairs(c) do
                    if k > 1 then cy = cy + gapY end
                    spots[p.i] = { x = cx, y = y + cy, shape = p.shape }
                    cy = cy + (boxes[p.i].drawnH or boxes[p.i].shapes[p.shape].h)
                end
                rowH = math.max(rowH, cy)
                cx = cx + c.w + gapX
            end
            y = y + rowH + gapY
            local left = {}
            for _, i in ipairs(todo) do if not best.taken[i] then left[#left + 1] = i end end
            todo = left
        end
    end
    return spots, math.max(0, y - gapY), memo
end

-- The groups the window shows now (chips and Recent applied), each with its
-- heading: the one it had, so an eased layout glides a heading with its group
-- and one whose group left fades out still reading its name. Returns
-- { g, h, folded, textW } in order, and the headings in use.
function Layout.Headed(window, cfg)
    local Cat = ns.Categories
    local shown = {}
    for _, g in ipairs(Layout.Groups(cfg, window)) do
        if g.key == "recent" and window.chip then
            -- Under a chip, Recent keeps only the new items that belong to it.
            local kept = {}
            for _, e in ipairs(g.entries) do
                if ns.Window.ItemInChip(window, e.facts) then kept[#kept + 1] = e end
            end
            g.entries = kept
            if #kept > 0 then shown[#shown + 1] = g end
        elseif ns.Window.InChip(window, g.key) then
            shown[#shown + 1] = g
        end
    end
    -- Each group keeps the heading it had, so an eased layout glides a heading
    -- with its group and one whose group left fades out still reading its name.
    local mine, spare, taken = {}, {}, {}
    for _, g in ipairs(shown) do mine[g.key] = false end
    for _, h in ipairs(window.headings or {}) do
        if h.key ~= nil and mine[h.key] == false then mine[h.key] = h else spare[#spare + 1] = h end
    end
    local nextSpare, out = 1, {}
    for _, g in ipairs(shown) do
        local folded = Cat.IsCollapsed(g.key)
        local h = mine[g.key]
        if not h then
            h = spare[nextSpare]
            if h then
                nextSpare = nextSpare + 1
            else
                h = heading(window, #(window.headings or {}) + 1)
            end
        end
        taken[h] = true
        h.key, h.name, h.empty = g.key, g.name, #g.entries == 0
        -- Empty counts the slots its tiles stand for, as the tile does.
        local shownN = #g.entries
        if g.key == "empty" then
            shownN = 0
            for _, e in ipairs(g.entries) do shownN = shownN + (e.free or 1) end
        end
        h.count:SetText(#g.entries == 0 and L["(drag items here)"] or tostring(shownN))
        Layout.PaintHeading(h, folded)
        local textW = (h.text.GetStringWidth and h.text:GetStringWidth()) or 0
        if type(textW) ~= "number" then textW = 0 end
        local countW = (h.count.GetStringWidth and h.count:GetStringWidth()) or 0
        if type(countW) ~= "number" then countW = 0 end
        textW = textW + 5 + countW
        out[#out + 1] = { g = g, h = h, folded = folded, textW = textW }
    end
    return out, taken
end

-- The Shelf: each group's heading over its slots, packed by Layout.Pack. A folded
-- group keeps its spot and the width it has open: only its items go.
function Layout.Categories(window, cfg)
    local Cat = ns.Categories
    local size, cols, gap = cfg.iconSize, math.max(1, math.floor(cfg.columns)), cfg.spacing
    local maxW = cols * size + (cols - 1) * gap
    for _, s in ipairs(window.set.Slots()) do
        s.button:Hide()
        s.button.dluiCount = nil
    end
    for _, l in ipairs(window.lines or {}) do l:Hide() end
    noteLaid(window)
    local top, headH, ruleH = Layout.SlotTop(window, cfg), Layout.HeadH(window, cfg), Layout.LineH(window, cfg)
    local groupGap, rowGap = Layout.GroupGap(window, cfg), Layout.RowGap(window, cfg)
    local inset = Layout.Ref(window, cfg, Layout.REF.inset)
    local headed, taken = Layout.Headed(window, cfg)
    local boxes = {}
    for _, hd in ipairs(headed) do
        local g, h, folded, textW = hd.g, hd.h, hd.folded, hd.textW
        -- The heading sits inside the rings' outer edges by inset at both ends, so
        -- its name starts over the first icon and the line spans the icons.
        local headW = textW + 2 * inset
        local total = #g.entries
        local function shape(across)
            local rows = math.ceil(total / across)
            local slotsW = across * size + (across - 1) * gap
            return { w = math.max(slotsW, headW), h = top + rows * size + (rows - 1) * gap,
                     fill = total * (size + gap) * (size + gap), across = across }
        end
        local shapes = {}
        if total == 0 then
            shapes[1] = { w = headW, h = headH, fill = headW * headH, across = 0 }
        elseif total <= cols then
            shapes[1] = shape(total)
        else
            -- A row taller and narrower, if that fits the bag better.
            local least = math.ceil(total / cols)
            shapes[1] = shape(math.ceil(total / least))
            local narrow = math.ceil(total / (least + 1))
            if narrow < shapes[1].across then shapes[2] = shape(narrow) end
        end
        -- A folded group is planned open and drawn one heading tall, so folding
        -- one never reshuffles the bag.
        boxes[#boxes + 1] = { key = g.key, shapes = shapes, breakBefore = g.breakBefore, breakAfter = g.breakAfter,
                              g = g, h = h, folded = folded, drawnH = folded and headH or nil }
    end
    local spots, height, memo = Layout.Pack(boxes, maxW, groupGap, rowGap, window.packed)
    window.packed = memo
    for bi, box in ipairs(boxes) do
        local g, h, spot = box.g, box.h, spots[bi]
        local sh = box.shapes[spot.shape]
        local x, y, w = spot.x, spot.y, sh.w
        local n = box.folded and 0 or #g.entries
        local across = math.max(1, sh.across)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", window.items, "TOPLEFT", x + inset, -y)
        h:SetWidth(w - 2 * inset)
        h:SetHeight(headH)
        h.rule:SetHeight(ruleH)
        h:Show()
        for k = 1, n do
            local e = g.entries[k]
            local col, row = (k - 1) % across, math.floor((k - 1) / across)
            local b = e.button
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", x + col * (size + gap), -(y + top + row * (size + gap)))
            b:Show()
            ns.Items.Place(b)
            ns.Items.SetFree(b, e.free)
            if e.extra and #e.extra > 0 then
                b.dluiCount = e.total
                local all = { b }
                for _, other in ipairs(e.extra) do all[#all + 1] = other end
                window.held[#window.held + 1] = { button = b, all = all, x = x + col * (size + gap),
                                                  y = -(y + top + row * (size + gap)), size = size }
            end
        end
    end
    for _, h in ipairs(window.headings or {}) do
        if not taken[h] then h:Hide() end
    end
    return maxW, height
end

-- The list view: the Shelf's groups as headings, a row per item under each,
-- column heads on top to sort by. A row is the item's own slot button, kept
-- square at the row's height on the left with its click area stretched over the
-- whole row, so using, dragging, the tooltip and other addons' marks all work as
-- on any slot. The words beside it live on a frame of their own on the button.
Layout.LIST_GAP = 2          -- between rows
Layout.LIST_TEXT = 6         -- from the icon to the name

function Layout.ListIcon(cfg)
    return math.max(20, math.floor(cfg.iconSize * 0.62 + 0.5))
end

-- Column heads; the icon's column has no head.
Layout.LIST_COLS = {
    { id = "icon", width = 0 },
    { id = "name", fill = true, sort = true },
    { id = "kind", width = 66, sort = true },
    { id = "level", width = 30, sort = true, justify = "RIGHT" },
    { id = "count", width = 30, sort = true, justify = "RIGHT" },
    { id = "value", width = 62, sort = true, justify = "RIGHT" },
}
local function colText(id)
    if id == "name" then return L["Name"] end
    if id == "kind" then return L["Kind"] end
    if id == "level" then return L["Lvl"] end
    if id == "count" then return L["Count"] end
    if id == "value" then return L["Sells for"] end
    return ""
end

local function listHead(window)
    local head = window.listHead
    if head then return head end
    local cols = {}
    for i, c in ipairs(Layout.LIST_COLS) do
        cols[i] = { id = c.id, width = c.width, fill = c.fill, sort = c.sort, justify = c.justify, text = colText(c.id) }
    end
    head = DUI.Widgets.ColumnHead(window.items, cols, function(id, desc)
        ns.Window.SortTouched(window)
        DUI:Set("Bags", "listDesc", desc)
        DUI:Set("Bags", "listSort", id)
    end)
    window.listHead = head
    return head
end

-- What a row shows for an entry: name, quality, kind, level, count, value.
function Layout.RowFacts(e)
    if e.empty then
        return { name = L["Empty slots"], kind = "", level = 0, count = e.free or 1, value = 0 }
    end
    local f = e.facts or {}
    local link = f.link
    local name = f.name
    if (not name or name == "") and link and C_Item and C_Item.GetItemInfo then
        name = (C_Item.GetItemInfo(link))
    end
    if (not name or name == "") and type(link) == "string" then name = link:match("%[(.-)%]") end
    local kind = ""
    if link and C_Item and C_Item.GetItemInfoInstant then
        local _, itemType = C_Item.GetItemInfoInstant(link)
        if type(itemType) == "string" then kind = itemType end
    end
    local value = 0
    if link and not f.hasNoValue then
        value = ns.Junk.PriceOf({ hyperlink = link }) * (e.total or f.count or 1)
    end
    return { name = name or "", quality = f.quality, kind = kind, level = f.itemLevel or 0,
             count = e.total or f.count or 1, value = value }
end

local function rowOf(btn, width, icon, at)
    local row = btn.dluiRow
    if not row then
        local Style = DUI.Style
        row = CreateFrame("Frame", nil, btn)
        row.hi = row:CreateTexture(nil, "BACKGROUND")
        row.hi:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.hi:Hide()
        row.name = Style.Text(row, Style.SIZE.body, "LEFT")
        row.kind = Style.Text(row, Style.SIZE.small, "LEFT")
        row.level = Style.Text(row, Style.SIZE.small, "RIGHT")
        row.count = Style.Text(row, Style.SIZE.small, "RIGHT")
        row.value = Style.Text(row, Style.SIZE.small, "RIGHT")
        for _, k in ipairs({ "name", "kind", "level", "count", "value" }) do row[k]:SetWordWrap(false) end
        btn:HookScript("OnEnter", function() if row:IsShown() then DUI.Win.Parts.Light(row.hi, true) end end)
        btn:HookScript("OnLeave", function() DUI.Win.Parts.Light(row.hi, false) end)
        btn.dluiRow = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    row:SetSize(width, icon)
    row.hi:ClearAllPoints()
    row.hi:SetPoint("TOPLEFT", row, "TOPLEFT", icon + Layout.LIST_TEXT / 2, 0)
    row.hi:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    local nameX = icon + Layout.LIST_TEXT
    for _, k in ipairs({ "name", "kind", "level", "count", "value" }) do
        local c = at[k]
        local fs = row[k]
        fs:ClearAllPoints()
        local x, w = c.x, c.w
        if k == "name" then x, w = nameX, c.x + c.w - nameX end
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        fs:SetWidth(math.max(1, w))
    end
    row:Show()
    return row
end

-- Paints a row from its entry (at layout, and after each fill of its slot).
function Layout.PaintRow(btn)
    local row, e = btn.dluiRow, btn.dluiEntry
    if not (row and e and row:IsShown()) then return end
    local Style = DUI.Style
    local d = Layout.RowFacts(e)
    row.name:SetText(d.name)
    local r, g, b
    if type(d.quality) == "number" and C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(d.quality)
    end
    if type(r) == "number" then row.name:SetTextColor(r, g, b) else Style.InkText(row.name, e.empty and "LABEL" or "VALUE") end
    row.kind:SetText(d.kind)
    Style.InkText(row.kind, "LABEL")
    row.level:SetText(d.level > 0 and tostring(math.floor(d.level + 0.5)) or "")
    Style.InkText(row.level, "VALUE")
    row.count:SetText(tostring(d.count))
    Style.InkText(row.count, "pop")
    row.value:SetText(d.value > 0 and DUI.Widgets.Money(d.value) or "")
    Style.InkText(row.value, "VALUE")
    -- The count reads in its column, so the icon carries none.
    if type(btn.Count) == "table" and btn.Count.Hide then btn.Count:Hide() end
end

-- The order inside a group by the picked column (nil keeps the Shelf's own order).
-- Words read A to Z and numbers biggest first; a second click flips either.
local function sorter(by, desc)
    if not by then return nil end
    return function(a, b)
        local x, y = a.row[by], b.row[by]
        if x ~= y then
            if type(x) == "string" then
                x, y = string.lower(x), string.lower(y)
                if desc then return x > y end
                return x < y
            end
            if desc then return x < y end
            return x > y
        end
        return a.i < b.i
    end
end

-- Puts every slot back to a plain square slot when the view isn't the list.
function Layout.EndList(window)
    if window.listHead then window.listHead:Hide() end
    for _, s in ipairs(window.set.Slots()) do
        local b = s.button
        if b.dluiRow and b.dluiRow:IsShown() then
            b.dluiRow:Hide()
            b:SetHitRectInsets(0, 0, 0, 0)
        end
        b.dluiEntry = nil
    end
end

function Layout.List(window, cfg)
    local size, cols, gap = cfg.iconSize, math.max(1, math.floor(cfg.columns)), cfg.spacing
    local width = cols * size + (cols - 1) * gap
    local icon = Layout.ListIcon(cfg)
    for _, s in ipairs(window.set.Slots()) do
        local b = s.button
        b:Hide()
        b.dluiCount = nil
        if b.dluiRow then b.dluiRow:Hide() end
        b:SetHitRectInsets(0, 0, 0, 0)
        b.dluiEntry = nil
    end
    for _, l in ipairs(window.lines or {}) do l:Hide() end
    noteLaid(window)
    local head = listHead(window)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", window.items, "TOPLEFT", 0, 0)
    head:SetWidth(width)
    local at = head:Layout(width)
    local by, desc = ns.Setting("listSort"), ns.Setting("listDesc") == true
    if by == "shelf" then by = nil end
    head:SetSort(by, desc)
    head:Show()
    local headH, ruleH = Layout.HeadH(window, cfg), Layout.LineH(window, cfg)
    local inset = Layout.Ref(window, cfg, Layout.REF.inset)
    local toRows = Layout.SlotTop(window, cfg) - headH
    local rowGap = Layout.RowGap(window, cfg)
    local y = head:GetHeight() + rowGap
    local headed, taken = Layout.Headed(window, cfg)
    local order = sorter(by, desc)
    for gi, hd in ipairs(headed) do
        local g, h = hd.g, hd.h
        if gi > 1 then y = y + rowGap end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", window.items, "TOPLEFT", inset, -y)
        h:SetWidth(width - 2 * inset)
        h:SetHeight(headH)
        h.rule:SetHeight(ruleH)
        h:Show()
        y = y + headH
        if not hd.folded and #g.entries > 0 then
            local list = {}
            for i, e in ipairs(g.entries) do list[i] = { e = e, i = i, row = Layout.RowFacts(e) } end
            if order then table.sort(list, order) end
            y = y + toRows
            for i, it in ipairs(list) do
                local e = it.e
                local b = e.button
                if i > 1 then y = y + Layout.LIST_GAP end
                b:SetSize(icon, icon)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", 0, -y)
                b:SetHitRectInsets(0, -(width - icon), 0, 0)
                b:Show()
                ns.Items.Place(b)
                ns.Items.SetFree(b, e.free)
                if e.extra and #e.extra > 0 then
                    b.dluiCount = e.total
                    local all = { b }
                    for _, other in ipairs(e.extra) do all[#all + 1] = other end
                    window.held[#window.held + 1] = { button = b, all = all, x = 0, y = -y, size = icon }
                end
                b.dluiEntry = e
                rowOf(b, width, icon, at)
                Layout.PaintRow(b)
                y = y + icon
            end
        end
    end
    for _, h in ipairs(window.headings or {}) do
        if not taken[h] then h:Hide() end
    end
    return width, y
end

-- Eased layouts (a heading click, a chip, loot while open). Everything runs on one driver and one
-- curve (NORMAL): moved slots glide by their anchor (Feel.Glide, fractional) in
-- step with the window height (Feel.Size, same duration). A Translation animation
-- (Motion.Glide) moved them in whole pixels on a different curve while the
-- bottom-anchored window's top moved smoothly, so the icons jittered.
-- Only the moved slots, and only for that long: each is re-placed every frame
-- (moving the whole grid instead cost about 10 fps).

Layout.FOLD_DROP = 6         -- px an opened group's items drop in from (same as the character window's folds)
Layout.easing = false        -- true while a layout should animate (a heading click, a chip, loot)

-- Whether the layout being made now animates. Never in a fight or under the
-- client's restrictions, where the bag has to be right at once.
function Layout.Eases(window)
    return Layout.easing and window:IsShown() and DUI.Motion.On() and not DUI.Restricted()
        and not (InCombatLockdown and InCombatLockdown()) and true or false
end

local function keyOf(held, seen)
    local t = type(held)
    if t ~= "number" and t ~= "string" then return nil end
    local base = tostring(held)
    if not seen then return base end
    local n = (seen[base] or 0) + 1
    seen[base] = n
    return base .. "#" .. n
end

-- Which item a slot shows: its item ID (a link when there's none), nil when empty.
-- With `seen`, stacks of the same item are numbered in the order they're met, so
-- a slot's item can be matched with the same item somewhere else after a move.
function Layout.ItemKey(button, seen)
    return keyOf((itemIn(bagOf(button), button:GetID())), seen)
end

-- Where every shown slot, heading and section line is right now (mid-glide too):
-- { slots = { [button] = { x, y } }, items = { [item key] = { x, y } },
--   keys = { [button] = item key }, heads = { [group key] = { x, y } }, headings = { [heading] = true },
--   lines = { [i] = { x, y } } }. A free tile's spot is also kept under its tile
-- key among the items.
function Layout.Spots(window)
    local slots, items, keys, heads, headings, lines, seen = {}, {}, {}, {}, {}, {}, {}
    for _, s in ipairs(window.set.Slots()) do
        local b = s.button
        if b:IsShown() and b:GetNumPoints() == 1 then
            local _, _, _, x, y = b:GetPoint(1)
            slots[b] = { x, y }
            -- Its last fill (Items.Fill): the bags have already changed by now.
            local key = keyOf(b.dluiKey, seen)
            if key then
                items[key] = slots[b]
                keys[b] = key
            end
        end
    end
    for _, t in ipairs(window.tiles or {}) do
        if t.key and slots[t.button] then items[t.key] = slots[t.button] end
    end
    for _, h in ipairs(window.headings or {}) do
        if h:IsShown() and h.key and h:GetNumPoints() == 1 then
            local _, _, _, x, y = h:GetPoint(1)
            heads[h.key] = { x, y }
            headings[h] = true
        end
    end
    for i, l in ipairs(window.lines or {}) do
        if l:IsShown() and l:GetNumPoints() == 1 then
            local _, _, _, x, y = l:GetPoint(1)
            lines[i] = { x, y }
        end
    end
    return { slots = slots, items = items, keys = keys, heads = heads, headings = headings, lines = lines }
end

-- Animates from the old spots (Layout.Spots) to the new layout. A slot that now
-- holds something else glides from where that item was (a sort or a swap moved
-- it), a free tile from where the tile was; one that holds the same as before,
-- or nothing, glides from its own spot.
-- New ones (and an item that wasn't in the window before) fade in with a small
-- drop, and ones no longer shown fade out in place (window.fading, restored by
-- the next layout). More than EASE_MAX moving pieces cross-fade instead.
function Layout.Ease(window, was)
    local moves = {}
    local function from(r, old)
        if r:GetNumPoints() ~= 1 then return end
        local _, _, _, x, y = r:GetPoint(1)
        if not old or x ~= old[1] or y ~= old[2] then
            moves[#moves + 1] = { r = r, old = old, x = x, y = y }
        end
    end
    local function fadeOut(r)
        window.fading = window.fading or {}
        window.fading[r] = true
        r:Show()
        DUI.Motion.AlphaTo(ns.Items.Fader(r), 0, DUI.Motion.FAST, true)
    end
    local items, tiles, claimed = was.items or {}, {}, {}
    for _, t in ipairs(window.tiles or {}) do
        if t.key then tiles[t.button] = t.key end
    end
    -- Slots still holding what they held keep their own stack's spot, so a slot
    -- with a changed item can only take a spot no one kept: with several stacks
    -- of one item, an extra stack fades in instead of gliding over another.
    local slots = window.set.Slots()
    local nows = {}
    for _, s in ipairs(slots) do
        local b = s.button
        local now = b:IsShown() and Layout.ItemKey(b)
        nows[b] = now
        if now and keyOf(b.dluiKey) == now and was.keys and was.keys[b] then claimed[was.keys[b]] = true end
    end
    local function claim(base)
        local n = 1
        while items[base .. "#" .. n] do
            local key = base .. "#" .. n
            if not claimed[key] then
                claimed[key] = true
                return items[key]
            end
            n = n + 1
        end
    end
    for _, s in ipairs(slots) do
        local b = s.button
        if b:IsShown() then
            local now = nows[b]
            if now and keyOf(b.dluiKey) ~= now then
                from(b, claim(now))   -- nil: the item wasn't in the window (loot), so it fades in
            else
                from(b, (tiles[b] and items[tiles[b]]) or was.slots[b])
            end
        elseif was.slots[b] then
            fadeOut(b)
        end
    end
    for _, h in ipairs(window.headings or {}) do
        if h:IsShown() then
            if h.key then from(h, was.heads[h.key]) end
        elseif was.headings and was.headings[h] then
            fadeOut(h)   -- its group left (all of it sold or used)
        end
    end
    for i, l in ipairs(window.lines or {}) do
        if l:IsShown() then
            from(l, was.lines and was.lines[i])
        elseif was.lines and was.lines[i] then
            fadeOut(l)
        end
    end
    if #moves > Layout.EASE_MAX then return Layout.CrossFade(window, moves) end
    local Motion, Feel = DUI.Motion, DUI.Win.Feel
    window.gliding = window.gliding or {}
    for _, m in ipairs(moves) do
        local r, old = m.r, m.old
        if old then
            Feel.Glide(r, old[1] - m.x, old[2] - m.y, Motion.NORMAL)
            window.gliding[r] = true
        else
            local fade = ns.Items.Fader(r)
            fade:SetAlpha(0)
            Motion.AlphaTo(fade, 1, Motion.NORMAL)
            Feel.Glide(r, 0, Layout.FOLD_DROP, Motion.NORMAL)
            window.gliding[r] = "new"
        end
    end
end

-- Gliding each slot re-places it every frame, which a full bank sort can't
-- afford. Past this many moving pieces the grid fades out where it was and back
-- in where it's going, placing each piece only twice.
Layout.EASE_MAX = 60

local function arrive(cross)
    if cross.arrived then return end
    cross.arrived = true
    for _, m in ipairs(cross.moves) do
        local r = m.r
        if m.old then
            -- Unless something placed it since (a held spot taken by the next stack).
            local _, _, _, x, y = r:GetPoint(1)
            if x == m.old[1] and y == m.old[2] then
                r:ClearAllPoints()
                r:SetPoint(m.point, m.rel, m.relPoint, m.x, m.y)
            end
        else
            ns.Items.Fader(r):SetAlpha(1)
        end
    end
end

-- One tween key per window for the grid's alpha, so a new cross-fade or a
-- settle takes over from the one running.
local function gridKey(window)
    local key = window.gridFade
    if not key then
        key = { step = function(a) window.items:SetAlpha(a) end }
        window.gridFade = key
    end
    return key
end

function Layout.CrossFade(window, moves)
    local Motion, grid = DUI.Motion, window.items
    local cross = { moves = moves }
    window.crossing = cross
    for _, m in ipairs(moves) do
        local r = m.r
        if m.old then
            m.point, m.rel, m.relPoint = r:GetPoint(1)
            r:ClearAllPoints()
            r:SetPoint(m.point, m.rel, m.relPoint, m.old[1], m.old[2])
        else
            ns.Items.Fader(r):SetAlpha(0)
        end
    end
    local key = gridKey(window)
    Motion.Tween(key, grid:GetAlpha(), 0, Motion.FAST, key.step, function()
        arrive(cross)
        Motion.Tween(key, 0, 1, Motion.NORMAL, key.step, function()
            if window.crossing == cross then window.crossing = nil end
        end)
    end)
end

-- Pieces that faded out come back hidden, so a layout places them like any slot
-- (a fold then eases them in as new).
local function restoreFading(window)
    if not window.fading then return end
    for b in pairs(window.fading) do
        DUI.Motion.AlphaTo(ns.Items.Fader(b), 1, 0)
        b:Hide()
    end
    wipe(window.fading)
end

-- Ends running glides and a cross-fade where they were going. full: new pieces
-- that were fading in show whole at once too, and so does the grid; otherwise
-- the grid fades back in from where it was (a layout made mid-way).
local function settleMoves(window, full)
    if window.gliding then
        for r, how in pairs(window.gliding) do
            DUI.Win.Feel.Settle(r)
            if full and how == "new" then DUI.Motion.AlphaTo(ns.Items.Fader(r), 1, 0) end
        end
        wipe(window.gliding)
    end
    local cross = window.crossing
    if cross then
        window.crossing = nil
        arrive(cross)
        local key = gridKey(window)
        if full then
            DUI.Motion.Tween(key, 1, 1, 0)
            window.items:SetAlpha(1)
        else
            DUI.Motion.Tween(key, window.items:GetAlpha(), 1, DUI.Motion.NORMAL, key.step)
        end
    end
end

-- Everything moving in the window lands at once: a fight needs the bag as it is.
function Layout.Settle(window)
    restoreFading(window)
    settleMoves(window, true)
end

-- Places every shown slot. Returns the grid's width and height.
function Layout.Apply(window, cfg)
    restoreFading(window)
    -- Where things are now, mid-glide too, so a layout made during one (loot
    -- arriving in a burst) glides on from there instead of jumping.
    local was = Layout.Eases(window) and Layout.Spots(window) or nil
    -- Then glides still running settle, so the layout below starts from its own spots.
    settleMoves(window)
    local w, h
    if cfg.view == "list" then
        w, h = Layout.List(window, cfg)
    else
        Layout.EndList(window)
        if cfg.view == "categories" then
            w, h = Layout.Categories(window, cfg)
        else
            w, h = Layout.Grid(window, cfg)
        end
    end
    if was then Layout.Ease(window, was) end
    return w, h
end

-- The grid view: every slot in bag order, a line between sections.
function Layout.Grid(window, cfg)
    for _, h in ipairs(window.headings or {}) do h:Hide() end
    local size, cols, gap = cfg.iconSize, math.max(1, math.floor(cfg.columns)), cfg.spacing
    local grouped = cfg.emptySlots == "grouped"
    if grouped then
        noteLaid(window)
    else
        window.laid = nil
        if window.tiles then wipe(window.tiles) end
    end
    local width = cols * size + (cols - 1) * gap
    local sections = Layout.Sections((slotsInView(window)), cfg.reagentMerged == true)
    local y, lines = 0, 0
    for i, section in ipairs(sections) do
        if i > 1 then
            lines = lines + 1
            local l = line(window, lines)
            y = y + Layout.SECTION_GAP
            -- One anchor and a width, so an eased layout can glide it with the slots.
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", window.items, "TOPLEFT", 0, -y)
            l:SetSize(width, DUI.Pixel.Px(window, 1))
            l:Show()
            y = y + Layout.SECTION_GAP
        end
        local shown, frees = section.slots, {}
        if grouped then
            local tiles, members, kinds
            shown, frees, tiles, members, kinds = Layout.Group(section)
            for _, t in ipairs(tiles) do
                noteTile(window, t.button, members[kinds[t.bag]], "free:" .. section.key .. ":" .. tostring(kinds[t.bag]))
            end
        end
        for n, s in ipairs(shown) do
            local col, row = (n - 1) % cols, math.floor((n - 1) / cols)
            local b = s.button
            b.dluiCount = nil
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", col * (size + gap), -(y + row * (size + gap)))
            b:Show()
            ns.Items.Place(b)
            ns.Items.SetFree(b, frees[s])
        end
        if not grouped then
            for _, s in ipairs(section.slots) do ns.Items.SetFree(s.button, nil) end
        end
        local rows = math.max(1, math.ceil(#shown / cols))
        y = y + rows * size + (rows - 1) * gap
    end
    for i = lines + 1, #(window.lines or {}) do window.lines[i]:Hide() end
    return width, y
end

-- Holding still while open

-- Whether the window can keep its layout: no slot gained an item it didn't have
-- when laid out (loot, buyback, moves and sorting all re-lay it out).
function Layout.Holds(window)
    local laid = window.laid
    if not laid then return false end
    for _, s in ipairs(window.set.Slots()) do
        local was = laid[s.button]
        if was == nil then return false end
        local now = itemIn(s.bag, s.button:GetID())
        if now and now ~= was then return false end
    end
    return true
end

-- Keeps the layout. A combined stack whose visible slot emptied moves the next
-- stack of that item into its spot, and totals follow. Returns the bags whose
-- slots need refilling (bag -> true).
function Layout.Hold(window)
    local bags, laid = {}, window.laid
    for _, e in ipairs(window.held or {}) do
        local live, total = {}, 0
        for _, b in ipairs(e.all) do
            local id, count = itemIn(bagOf(b), b:GetID())
            if id and id == laid[b] then
                live[#live + 1] = b
                total = total + count
            end
        end
        local b = e.button
        local moveTo = live[1]
        if moveTo and moveTo ~= b and not itemIn(bagOf(b), b:GetID()) then
            if ns.CanLayout(window) then
                moveTo:SetSize(e.size, e.size)
                moveTo:ClearAllPoints()
                moveTo:SetPoint("TOPLEFT", moveTo:GetParent(), "TOPLEFT", e.x, e.y)
                moveTo:Show()
                ns.Items.Place(moveTo)
                ns.Items.SetFree(moveTo, nil)
                b:Hide()
                b.dluiCount = nil
                bags[bagOf(b)] = true
                e.button, b = moveTo, moveTo
            else
                DUI.AfterCombat(function()
                    if window:IsShown() and Layout.Holds(window) then
                        for bag in pairs(Layout.Hold(window)) do ns.Window.MarkDirty(window, bag) end
                        ns.Window.FillDirty(window)
                    end
                end, "bags:hold:" .. window.kind)
            end
        end
        local want = (#live > 1 and live[1] == b) and total or nil
        if b.dluiCount ~= want then
            b.dluiCount = want
            bags[bagOf(b)] = true
        end
    end
    -- Free tiles also count the slots that just emptied.
    for _, t in ipairs(window.tiles or {}) do
        local n = 0
        for _, s in ipairs(t.slots) do
            if isEmpty(s.bag, s.button:GetID()) then n = n + 1 end
        end
        ns.Items.SetFree(t.button, n)
    end
    return bags
end
