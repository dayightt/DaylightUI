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
-- grouped free tiles (window.tiles: { button, slots }) so Layout.Hold can
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

-- A free tile: its button shows how many of `slots` are empty.
local function noteTile(window, button, slots)
    if window.tiles then window.tiles[#window.tiles + 1] = { button = button, slots = slots } end
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

Layout.HEAD = 15             -- group heading height
Layout.HEAD_SIZE = DUI.Style.SIZE.small
Layout.GROUP_GAP = 12        -- between groups side by side
Layout.ROW_GAP = 8           -- between rows of groups
Layout.HEAD_DIM = DUI.Style.INK.LABEL

Layout.HEAD_CHEV = 8         -- chevron size
Layout.HEAD_TEXT_X = 13      -- where the name starts, after the chevron
Layout.FOLDED_TURN = math.pi / 2   -- the chevron points right while folded

-- Group heading: chevron, upper case name, count and a faint rule out to the
-- group's edge. Click folds or unfolds,
-- right-click on Recent clears it, and an item dropped or clicked onto it from
-- the cursor gets pinned to the group.
local function heading(window, i)
    window.headings = window.headings or {}
    local h = window.headings[i]
    if h then return h end
    h = CreateFrame("Button", nil, window.items)
    h:SetHeight(Layout.HEAD)
    h.chev = DUI.Widgets.Icon(h, "ui-chevron.png", Layout.HEAD_CHEV, DUI.Style.INK.LABEL)
    h.chev:SetPoint("LEFT", h, "LEFT", 1, 0)
    h.text = DUI.Style.Text(h, Layout.HEAD_SIZE, "LEFT")
    h.text:SetPoint("LEFT", h, "LEFT", Layout.HEAD_TEXT_X, 1)
    h.count = DUI.Style.Text(h, DUI.Style.SIZE.tiny, "LEFT")
    h.count:SetPoint("LEFT", h.text, "RIGHT", 5, 0)
    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    h.rule:SetHeight(1)
    h.rule:SetPoint("LEFT", h.count, "RIGHT", 6, 0)
    h.rule:SetPoint("RIGHT", h, "RIGHT", 0, 0)
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
-- change of accent repaints through the next layout. Open groups read in the
-- accent (Recent letter by letter under a gradient accent), folded ones in the
-- label color until the mouse is over them. The chevron turns as it folds.
function Layout.PaintHeading(h, folded)
    local Style, Motion = DUI.Style, DUI.Motion
    local lit = not folded or h.hover
    local shown = h.name and string.upper(h.name) or ""
    if lit and h.key == "recent" then
        Style.PaintAccentText(h.text, shown)
    else
        h.text:SetText(shown)
        if lit then
            h.text:SetTextColor(Style.Accent())
        else
            local d = Layout.HEAD_DIM
            h.text:SetTextColor(d[1], d[2], d[3])
        end
    end
    local rc = Style.BAND_LIT
    h.rule:SetVertexColor(rc[1], rc[2], rc[3], 1)
    Style.InkText(h.count, "pop")
    if lit then
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
    if ns.Setting("emptyGroups") == true or not f or not f:IsShown() or ns.Setting("view") ~= "categories" then return end
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
                        noteTile(window, list[1].button, members[section])
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

-- Groups flow left to right and wrap at the grid's width. A group wider than the
-- remaining space starts a new row; one wider than a full row spans several.
-- Folded group headings never share a row with open groups (it left a hole under
-- them and shuffled the others). Consecutive folded ones line up on their own
-- row, one heading tall.
function Layout.Categories(window, cfg)
    local Cat = ns.Categories
    local size, cols, gap = cfg.iconSize, math.max(1, math.floor(cfg.columns)), cfg.spacing
    local maxW = cols * size + (cols - 1) * gap
    local was = Layout.easing and window:IsShown() and DUI.Motion.On() and Layout.Spots(window) or nil
    for _, s in ipairs(window.set.Slots()) do
        s.button:Hide()
        s.button.dluiCount = nil
    end
    for _, l in ipairs(window.lines or {}) do l:Hide() end
    noteLaid(window)
    local x, y, lineH, used, wasFolded = 0, 0, 0, 0, nil
    local function newRow()
        if x > 0 then
            y = y + lineH + Layout.ROW_GAP
            x, lineH = 0, 0
        end
    end
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
    for i, g in ipairs(shown) do
        used = i
        local folded = Cat.IsCollapsed(g.key)
        local h = heading(window, i)
        h.key, h.name = g.key, g.name
        h.count:SetText(#g.entries == 0 and L["(drag items here)"] or tostring(#g.entries))
        Layout.PaintHeading(h, folded)
        local textW = (h.text.GetStringWidth and h.text:GetStringWidth()) or 0
        if type(textW) ~= "number" then textW = 0 end
        local countW = (h.count.GetStringWidth and h.count:GetStringWidth()) or 0
        if type(countW) ~= "number" then countW = 0 end
        textW = Layout.HEAD_TEXT_X + textW + 5 + countW
        local n = folded and 0 or #g.entries
        local across = math.min(n, cols)
        local rows = n > 0 and math.ceil(n / across) or 0
        local slotsW = across > 0 and (across * size + (across - 1) * gap) or 0
        local w = math.max(slotsW, textW + 4)
        if g.breakBefore or (wasFolded ~= nil and folded ~= wasFolded) then newRow() end
        wasFolded = folded
        if x > 0 and x + w > maxW then newRow() end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", window.items, "TOPLEFT", x, -y)
        h:SetWidth(w)
        h:Show()
        for k = 1, n do
            local e = g.entries[k]
            local col, row = (k - 1) % across, math.floor((k - 1) / across)
            local b = e.button
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", b:GetParent(), "TOPLEFT", x + col * (size + gap), -(y + Layout.HEAD + row * (size + gap)))
            b:Show()
            ns.Items.Place(b)
            ns.Items.SetFree(b, e.free)
            if e.extra and #e.extra > 0 then
                b.dluiCount = e.total
                local all = { b }
                for _, x in ipairs(e.extra) do all[#all + 1] = x end
                window.held[#window.held + 1] = { button = b, all = all, x = x + col * (size + gap),
                                                  y = -(y + Layout.HEAD + row * (size + gap)), size = size }
            end
        end
        local gh = Layout.HEAD + (rows > 0 and (rows * size + (rows - 1) * gap) or 0)
        lineH = math.max(lineH, gh)
        x = x + w + Layout.GROUP_GAP
        if g.breakAfter then newRow() end
    end
    for i = used + 1, #(window.headings or {}) do window.headings[i]:Hide() end
    if was then Layout.Ease(window, was) end
    return maxW, y + lineH
end

-- Fold animation (clicking a heading). Only folds animate; loot, sorting and
-- setting changes lay out instantly. Everything runs on one driver and one curve
-- (NORMAL): moved slots glide by their anchor (Feel.Glide, fractional) in step
-- with the window height (Feel.Size, same duration). A Translation animation
-- (Motion.Glide) moved them in whole pixels on a different curve while the
-- bottom-anchored window's top moved smoothly, so the icons jittered.
-- Only the moved slots, and only for that long: each is re-placed every frame
-- (moving the whole grid instead cost about 10 fps).

Layout.FOLD_DROP = 6         -- px an opened group's items drop in from (same as the character window's folds)
Layout.easing = false        -- true while a heading click is laying out the bag

-- Current position of every shown slot and heading, as the layout set them:
-- { slots = { [button] = { x, y } }, heads = { [group key] = { x, y } } }.
function Layout.Spots(window)
    local slots, heads = {}, {}
    for _, s in ipairs(window.set.Slots()) do
        local b = s.button
        if b:IsShown() and b:GetNumPoints() == 1 then
            local _, _, _, x, y = b:GetPoint(1)
            slots[b] = { x, y }
        end
    end
    for _, h in ipairs(window.headings or {}) do
        if h:IsShown() and h.key and h:GetNumPoints() == 1 then
            local _, _, _, x, y = h:GetPoint(1)
            heads[h.key] = { x, y }
        end
    end
    return { slots = slots, heads = heads }
end

-- Animates from the old spots (Layout.Spots) to the new layout. Moved pieces
-- glide from where they were, new ones fade in with a small drop, and folded
-- ones fade out in place (window.fading, restored by the next layout).
function Layout.Ease(window, was)
    local Motion, Feel = DUI.Motion, DUI.Win.Feel
    window.gliding = window.gliding or {}
    local function from(r, old)
        if r:GetNumPoints() ~= 1 then return end
        local _, _, _, x, y = r:GetPoint(1)
        if not old then
            r:SetAlpha(0)
            Motion.AlphaTo(r, 1, Motion.NORMAL)
            Feel.Glide(r, 0, Layout.FOLD_DROP, Motion.NORMAL)
            window.gliding[r] = true
        elseif x ~= old[1] or y ~= old[2] then
            Feel.Glide(r, old[1] - x, old[2] - y, Motion.NORMAL)
            window.gliding[r] = true
        end
    end
    for _, s in ipairs(window.set.Slots()) do
        local b, old = s.button, was.slots[s.button]
        if b:IsShown() then
            from(b, old)
        elseif old then
            window.fading = window.fading or {}
            window.fading[b] = true
            b:Show()
            Motion.AlphaTo(b, 0, Motion.FAST, true)
        end
    end
    for _, h in ipairs(window.headings or {}) do
        if h:IsShown() and h.key then from(h, was.heads[h.key]) end
    end
end

-- Places every shown slot. Returns the grid's width and height.
function Layout.Apply(window, cfg)
    -- Items from a fold that are fading out (or done): restore them but keep them
    -- hidden so the layout places them like any slot (a fold then eases them in as new).
    if window.fading then
        for b in pairs(window.fading) do
            DUI.Motion.AlphaTo(b, 1, 0)
            b:Hide()
        end
        wipe(window.fading)
    end
    -- Fold glides still running: settle them first so the spots read and set below
    -- are the layout's own.
    if window.gliding then
        for r in pairs(window.gliding) do DUI.Win.Feel.Settle(r) end
        wipe(window.gliding)
    end
    if cfg.view == "categories" then return Layout.Categories(window, cfg) end
    for _, h in ipairs(window.headings or {}) do h:Hide() end
    local size, cols, gap = cfg.iconSize, math.max(1, math.floor(cfg.columns)), cfg.spacing
    local grouped = cfg.emptySlots == "grouped"
    if grouped then noteLaid(window) else window.laid = nil end
    local sections = Layout.Sections((slotsInView(window)), cfg.reagentMerged == true)
    local y, lines = 0, 0
    for i, section in ipairs(sections) do
        if i > 1 then
            lines = lines + 1
            local l = line(window, lines)
            y = y + Layout.SECTION_GAP
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", window.items, "TOPLEFT", 0, -y)
            l:SetPoint("TOPRIGHT", window.items, "TOPRIGHT", 0, -y)
            l:SetHeight(DUI.Pixel.Px(window, 1))
            l:Show()
            y = y + Layout.SECTION_GAP
        end
        local shown, frees = section.slots, {}
        if grouped then
            local tiles, members, kinds
            shown, frees, tiles, members, kinds = Layout.Group(section)
            for _, t in ipairs(tiles) do noteTile(window, t.button, members[kinds[t.bag]]) end
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
    return cols * size + (cols - 1) * gap, y
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
