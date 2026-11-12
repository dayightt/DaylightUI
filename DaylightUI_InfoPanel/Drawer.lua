-- Addon button drawer. A small button in the minimap's bottom-right corner
-- opens a strip holding every addon's minimap button, plus one square that
-- opens the game's addon compartment as a menu. The two lists are never
-- merged: there's no reliable way to match a button to its compartment
-- entry, and this way nothing shows twice.
--
-- Buttons are collected at login, a few seconds later, whenever the map
-- gains a child, and each time the drawer opens. The game's own map buttons
-- stay on the map.

local _, ns = ...
local DUI = DaylightUI
local Style, Motion = DUI.Style, DUI.Motion

local Drawer = {}
ns.Drawer = Drawer

Drawer.SIZE = 24             -- square size, corner button included
Drawer.GAP = 4
Drawer.PAD = 4               -- strip padding, and corner button inset
Drawer.DOT = 4               -- corner button dot size
Drawer.DOT_GAP = 2
Drawer.LATE = 3              -- seconds after login for a second scan
Drawer.WATCH = 0.1           -- mouse check interval
Drawer.LINGER = 1            -- seconds it stays open after the mouse leaves the map
-- Icon ripple: LEAD delay after the strip starts, STAGGER between icons
-- (compressed so the whole row fits in RIPPLE), RISE pixels of lift.
Drawer.LEAD = 0.03
Drawer.STAGGER = 0.02
Drawer.RIPPLE = 0.2
Drawer.RISE = 4
Drawer.MENU_ICON = "ui-section-module.png"   -- icon for the addon compartment square
Drawer.MENU_WIDTH = 160       -- minimum menu width
Drawer.MIN_WIDTH = 20        -- anything narrower is a map pin, not a button
Drawer.CROWD = 1000          -- above this many children the map is full of pins (see crowded)
-- Name patterns for pins that no library lists.
Drawer.PIN_NAMES = { "^HandyNotes", "^TomTom", "^HereBeDragons", "^Questie", "^GatherMate", "^[Pp]in" }
-- The game's own map buttons, left alone.
Drawer.SKIP = {
    GameTimeFrame = true, QueueStatusButton = true, AddonCompartmentFrame = true,
    MiniMapTrackingButton = true, MinimapZoomIn = true, MinimapZoomOut = true,
    MiniMapWorldMapButton = true, MiniMapMailFrame = true,
}
-- Border ring and background disc textures used by minimap buttons.
Drawer.RING_FILES = {
    [136430] = true, [136467] = true,
    ["Interface\\Minimap\\MiniMap-TrackingBorder"] = true,
    ["Interface\\Minimap\\UI-Minimap-Background"] = true,
}
Drawer.CROP = DaylightUI.Style.ICON_CROP

local buttons = {}           -- collected addon buttons
local owned = {}             -- button -> true
local cells = {}             -- button or menu square -> its cell
local items = {}             -- currently shown, nearest the corner first
local shownButtons = {}
local lateLook = false
local fullW, minW = 1, 1     -- strip width when open, and when closed (corner button only)

-- ---------------------------------------------------------------------
-- Gathering
-- ---------------------------------------------------------------------

local function ringed(f)
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetTexture and Drawer.RING_FILES[r:GetTexture()] then return true end
    end
    return false
end

-- HereBeDragons map pins (Questie, HandyNotes, GatherMate...) are named
-- buttons on the minimap but must stay where they point. Addons embed the
-- library under their own names (e.g. "HereBeDragonsQuestie-Pins-2.0"), so
-- check every library for a minimapPins table instead of matching by name.
-- Gathered once per look: a map can hold hundreds of children.
local function pinLists()
    local lists = {}
    if type(LibStub) ~= "table" or type(LibStub.IterateLibraries) ~= "function" then return lists end
    for _, lib in LibStub:IterateLibraries() do
        local pins = type(lib) == "table" and rawget(lib, "minimapPins")
        if type(pins) == "table" then lists[#lists + 1] = pins end
    end
    return lists
end

local function pinned(f, lists)
    for i = 1, #lists do
        if lists[i][f] then return true end
    end
    return false
end

-- Whether a button is safe to take at all.
local function free(f)
    if type(f) ~= "table" or owned[f] or not f.GetObjectType then return false end
    if f:GetObjectType() ~= "Button" then return false end
    if f.IsForbidden and f:IsForbidden() then return false end
    if f.IsProtected and f:IsProtected() then return false end
    local name = f:GetName()
    return not (type(name) == "string" and Drawer.SKIP[name])
end

local function pinNamed(name)
    for _, pattern in ipairs(Drawer.PIN_NAMES) do
        if name:find(pattern) then return true end
    end
    return false
end

local function clickable(f)
    return f:GetScript("OnClick") or f:GetScript("OnMouseUp") or f:GetScript("OnMouseDown")
end

-- Is this map child an addon's minimap button? Pins are always excluded.
-- Otherwise it needs the button ring (some are unnamed), a LibDBIcon name
-- ("LibDBIcon10_Questie" is a real button, so this is checked before the pin
-- names), or a name of its own plus a click handler and button size.
-- Names ending in a digit are pooled pin frames ("QuestieFrame12").
-- Hidden ones are skipped since pin libraries park removed pins hidden;
-- a real button gets picked up once it shows. The pin lists are checked
-- last, only for what looks like a button.
local function looksLikeButton(f)
    if ringed(f) then return true end
    local name = f:GetName()
    if type(name) ~= "string" or not f:IsShown() then return false end
    if name:find("^LibDBIcon10_") then return true end
    if pinNamed(name) or name:find("%d$") then return false end
    return clickable(f) ~= nil and (f:GetWidth() or 0) >= Drawer.MIN_WIDTH
end

local function wanted(f, pins)
    return free(f) and looksLikeButton(f) and not pinned(f, pins)
end

-- Strips color codes, links and inline icons from compartment titles.
local function plain(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function paintEdge(cell, lit)
    local s = Style.GetShell(cell)
    if not s then return end
    if lit then
        Style.LightShell(s)
    else
        Style.SetShellColors(s, nil)
    end
end

-- A bordered square with no fill; the strip is the backdrop.
local function newCell(parent)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(Drawer.SIZE, Drawer.SIZE)
    local s = Style.Shell(cell, { borderPx = ns.Panel.XP_BORDER })
    if s and s.bg then s.bg:SetAlpha(0) end
    cell.rise = 0
    return cell
end

-- Restyles a minimap button: hide the ring and disc, crop the icon square,
-- and stop it dragging around the map.
local function skin(btn)
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.GetTexture and Drawer.RING_FILES[r:GetTexture()] then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "border", "background" }) do
        local t = btn[key]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
    end
    local icon = btn.icon
    if type(icon) == "table" and icon.SetTexCoord then
        local c = Drawer.CROP
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        -- Some addons round the icon with a mask. Masked textures can't be
        -- cropped, so remove the masks.
        local n = icon.GetNumMaskTextures and icon:GetNumMaskTextures()
        if type(n) == "number" then
            for i = n, 1, -1 do
                local m = icon:GetMaskTexture(i)
                if type(m) == "table" then icon:RemoveMaskTexture(m) end
            end
        end
        -- An old-style SetMask mask isn't counted above and can't be removed, but
        -- still refuses tex coords. Such an icon keeps its own round shape.
        local cropped = pcall(icon.SetTexCoord, icon, c[1], c[2], c[3], c[4])
        icon:SetVertexColor(1, 1, 1)
        icon:SetAlpha(1)
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        -- LibDBIcon re-crops the icon on press; keep our crop.
        if cropped and icon.UpdateCoord then
            icon.UpdateCoord = function(self) self:SetTexCoord(c[1], c[2], c[3], c[4]) end
        end
    end
    -- Dragging reorders the button within the strip instead of moving it
    -- around the map. Buttons with no drag script are left alone.
    if btn:GetScript("OnDragStart") then
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", function() Drawer.DragStart(btn) end)
        btn:SetScript("OnDragStop", function() Drawer.DragStop() end)
    elseif btn:GetScript("OnDragStop") then
        btn:SetScript("OnDragStop", nil)
    end
end

-- Puts a button in its square. Called again if its addon moves it.
local function place(f)
    local cell = cells[f]
    if not cell then return end
    f:SetParent(cell)
    -- LibDBIcon resets the strata to MEDIUM later, so lock it to the cell's.
    if f.SetFixedFrameStrata then f:SetFixedFrameStrata(false) end
    f:SetFrameStrata(cell:GetFrameStrata())
    if f.SetFixedFrameStrata then f:SetFixedFrameStrata(true) end
    f:SetFrameLevel(cell:GetFrameLevel() + 3)
    f:ClearAllPoints()
    f:SetSize(Drawer.SIZE, Drawer.SIZE)
    f:SetPoint("CENTER", cell, "CENTER", 0, 0)
end

local function take(f)
    owned[f] = true
    buttons[#buttons + 1] = f
    cells[f] = newCell(Drawer.clip)
    skin(f)
    -- Use HookScript, never method hooks. Game map buttons can land here
    -- and the game calls them from protected code; a method hook made
    -- those calls fail with "attempt to call a nil value".
    f:HookScript("OnShow", function() Drawer.Layout() end)
    f:HookScript("OnHide", function() Drawer.Layout() end)
    f:HookScript("OnEnter", function() paintEdge(cells[f], true) end)
    f:HookScript("OnLeave", function() paintEdge(cells[f], false) end)
end

-- Addon compartment entries, sorted like the game's own menu.
local function compartment()
    local list = {}
    local frame = _G.AddonCompartmentFrame
    local reg = type(frame) == "table" and frame.registeredAddons
    if type(reg) ~= "table" then return list end
    for _, data in ipairs(reg) do
        if type(data) == "table" then list[#list + 1] = data end
    end
    table.sort(list, function(a, b) return plain(a.text):lower() < plain(b.text):lower() end)
    return list
end

-- Calls an entry the way the game's menu does (data, input, menu). Older
-- LibDBIcon entries expect the mouse button as the fifth argument, as the
-- old dropdown menus passed it.
local function runEntry(data, owner)
    if type(data.func) ~= "function" then return end
    local ctx = type(MenuInputContext) == "table" and MenuInputContext.MouseButton or nil
    DUI.SafeCall(data.func, owner, { context = ctx, buttonName = "LeftButton" }, owner, nil, "LeftButton")
end

-- The square that shows the addon compartment as our own menu.
local function menuHeld()
    local W = DUI.Widgets
    return Drawer.more ~= nil and W.menuOwner == Drawer.more.button
end

local function moreCell()
    if Drawer.more then return Drawer.more end
    local W = DUI.Widgets
    local cell = newCell(Drawer.clip)
    local b = W.IconButton(cell, Drawer.MENU_ICON, ADDONS or DUI.L["AddOns"], function(self)
        if W.menuOwner == self then return W.CloseMenu() end
        local list, keys, values = compartment(), {}, {}
        for i, data in ipairs(list) do
            keys[i], values[i] = i, plain(data.text)
        end
        W.OpenMenu(self, keys, values, nil, function(i) runEntry(list[i], self) end, Drawer.MENU_WIDTH)
    end, Drawer.SIZE)
    b:SetAllPoints(cell)
    b:SetFrameLevel(cell:GetFrameLevel() + 3)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() Drawer.DragStart(cell) end)
    b:SetScript("OnDragStop", function() Drawer.DragStop() end)
    b:HookScript("OnEnter", function() paintEdge(cell, true) end)
    b:HookScript("OnLeave", function() paintEdge(cell, false) end)
    cell.button = b
    Drawer.more = cell
    cells[cell] = cell
    return cell
end

-- ---------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------

function Drawer.Shown() return shownButtons end
function Drawer.Items() return items end
function Drawer.CellOf(thing) return cells[thing] end

-- Offset of square k from the strip's bottom-right corner, filling right to
-- left then upward. The corner button is square 0.
local function slot(k, cols)
    local step = Drawer.SIZE + Drawer.GAP
    return -(Drawer.PAD + (k % cols) * step), Drawer.PAD + math.floor(k / cols) * step
end

local function setRise(cell, a, rise)
    cell:SetAlpha(a)
    if cell.rise == rise and cell.placed then return end
    cell.rise = rise
    cell:ClearAllPoints()
    cell:SetPoint("BOTTOMRIGHT", Drawer.clip, "BOTTOMRIGHT", cell.x, cell.y - rise)
end

-- Stable key for saving order: the addon's name, or MENU_KEY for the menu
-- square. Unnamed buttons get none and can't be reordered.
Drawer.MENU_KEY = "*menu"

local function keyOf(thing)
    if thing == Drawer.more then return Drawer.MENU_KEY end
    local name = plain(thing:GetName())
    name = plain(name:match("^LibDBIcon10_(.+)$") or name)
    return name ~= "" and name or nil
end

local function savedOrder()
    local o = Drawer.cfg and Drawer.cfg.drawerOrder
    return type(o) == "table" and o or {}
end

local dropDrag

function Drawer.Layout()
    local strip = Drawer.strip
    if not strip then return end
    -- A button showing or hiding mid-drag ends the drag.
    if dropDrag then dropDrag() end
    local list = {}
    for i = #shownButtons, 1, -1 do shownButtons[i] = nil end
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            shownButtons[#shownButtons + 1] = b
            local key = keyOf(b)
            -- "~" sorts unnamed buttons after named ones.
            list[#list + 1] = { thing = b, key = key, name = key or "~" }
        end
    end
    if #compartment() > 0 then
        local more = moreCell()
        list[#list + 1] = { thing = more, key = Drawer.MENU_KEY, name = "", menu = true }
    end
    -- Saved order first, then by name, with the menu square last.
    local rank = {}
    for i, key in ipairs(savedOrder()) do
        if rank[key] == nil then rank[key] = i end
    end
    table.sort(list, function(a, b)
        local ra, rb = a.key and rank[a.key], b.key and rank[b.key]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end
        if a.menu or b.menu then return b.menu == true and not a.menu end
        return a.name:lower() < b.name:lower()
    end)
    local listed = {}
    for _, it in ipairs(list) do listed[it.thing] = true end
    for thing, cell in pairs(cells) do
        if not listed[thing] then
            -- For an addon button, fade the cell instead of hiding it. A
            -- hidden parent would stop the button's OnShow from firing when
            -- its addon shows it again, so it would never come back.
            if owned[thing] then cell:SetAlpha(0) else cell:Hide() end
        end
    end
    for i = #items, 1, -1 do items[i] = nil end
    local width = ns.Panel.mapSize or 200
    local step = Drawer.SIZE + Drawer.GAP
    local cols = math.max(1, math.floor((width - 2 * Drawer.PAD + Drawer.GAP) / step))
    Drawer.cols = cols
    local count = #list + 1
    local rows = math.ceil(count / cols)
    local across = math.min(count, cols)
    fullW = 2 * Drawer.PAD + across * Drawer.SIZE + (across - 1) * Drawer.GAP
    minW = 2 * Drawer.PAD + Drawer.SIZE
    strip:SetHeight(2 * Drawer.PAD + rows * Drawer.SIZE + (rows - 1) * Drawer.GAP)
    Style.LayoutShell(Style.GetShell(strip))
    for k, it in ipairs(list) do
        items[k] = it.thing
        local cell = cells[it.thing]
        cell.x, cell.y = slot(k, cols)
        cell.placed = nil
        cell:Show()
        setRise(cell, cell:GetAlpha(), cell.rise)
        cell.placed = true
        if cell.button == nil then ns.Minimap.Pin(it.thing, place) end
    end
    Drawer.Paint()
    local any = #list > 0
    Drawer.glyph:SetShown(any and Drawer.on == true)
    if not any and Drawer.open then Drawer.Close(true) end
end

-- Scanning the map (and LibDBIcon's list) for new buttons.
local SOURCES = { "Minimap", "MinimapBackdrop" }
local counts = {}            -- source name -> child count at the last scan

-- Map pins pile up on the minimap and stay there hidden when removed.
-- GetChildren returns every child on the Lua stack, which holds about 8000
-- values. Past that it fails with "stack overflow", and well before that
-- it's too slow to run on every count change.
local function childCount(src)
    return type(src) == "table" and src.GetNumChildren and src:GetNumChildren() or 0
end

local function crowded(src)
    return childCount(src) > Drawer.CROWD
end

-- Has the map gained or lost a child since the last scan? Catches addons
-- that create buttons late. A crowded map changes with every pin, so it's
-- only scanned at login, the late scan, and on opening.
local function changed()
    for _, key in ipairs(SOURCES) do
        local src = _G[key]
        if not crowded(src) and counts[key] ~= childCount(src) then return true end
    end
    return false
end

-- A crowded frame can't be read in chunks, so walk every frame in the game
-- instead. The pcall is for locked aura buttons, which refuse every method.
local function lookIn(src, pins)
    if not crowded(src) then
        for _, f in ipairs({ src:GetChildren() }) do
            if wanted(f, pins) then take(f) end
        end
        return
    end
    local f = EnumerateFrames()
    while f do
        local ok, parent = pcall(f.GetParent, f)
        if ok and parent == src and wanted(f, pins) then take(f) end
        f = EnumerateFrames(f)
    end
end

function Drawer.Collect()
    if not (Drawer.strip and Drawer.on) then return end
    local pins = pinLists()
    for _, key in ipairs(SOURCES) do
        local src = _G[key]
        if type(src) == "table" and src.GetChildren then lookIn(src, pins) end
    end
    local lib = type(LibStub) == "table" and LibStub("LibDBIcon-1.0", true)
    if type(lib) == "table" and lib.GetButtonList then
        for _, name in ipairs(lib:GetButtonList()) do
            local f = lib:GetMinimapButton(name)
            if free(f) then take(f) end
        end
    end
    Drawer.Layout()
    -- Count after taking, since taken buttons have left the map.
    for _, key in ipairs(SOURCES) do
        counts[key] = childCount(_G[key])
    end
end

-- ---------------------------------------------------------------------
-- Drag to reorder, like the chat tabs. The others glide aside, and the drop
-- saves map.drawerOrder directly (nothing else needs a re-layout). Only
-- while the drawer is fully open.
-- ---------------------------------------------------------------------

local drag

function Drawer.Dragging() return drag ~= nil end

-- Cursor offset from the strip's bottom-right corner, where squares anchor.
local function cursorAt()
    local clip = Drawer.clip
    local x, y = GetCursorPosition()
    local s = clip:GetEffectiveScale() or 1
    return x / s - (clip:GetRight() or 0), y / s - (clip:GetBottom() or 0)
end

local function moveCell(cell, x, y)
    cell.x, cell.y = x, y
    cell.placed = nil
    setRise(cell, cell:GetAlpha(), 0)
    cell.placed = true
end

-- A square eased from where it's drawn to (x, y).
local function slideCell(cell, x, y)
    local fx, fy = cell.x, cell.y
    cell.slideKey = cell.slideKey or {}
    Motion.Tween(cell.slideKey, 0, 1, Motion.FAST, function(e)
        moveCell(cell, fx + (x - fx) * e, fy + (y - fy) * e)
    end)
end

local function inner(cell, thing)
    return cell.button or thing
end

-- Ends a drag: restore frame levels and stop any glides in place.
dropDrag = function()
    local d = drag
    if not d then return end
    drag = nil
    Drawer.dragger:SetScript("OnUpdate", nil)
    d.cell:SetFrameLevel(d.level)
    inner(d.cell, d.thing):SetFrameLevel(d.level + 3)
    for _, thing in ipairs(items) do
        local c = cells[thing]
        if c and c.slideKey then Motion.Tween(c.slideKey, 0, 0, 0) end
    end
    return d
end

function Drawer.DragStart(thing)
    if drag or not Drawer.open or Drawer.driver:GetScript("OnUpdate") then return end
    local cell = cells[thing]
    if not cell or not keyOf(thing) then return end
    local from
    for k, it in ipairs(items) do
        if it == thing then from = k end
    end
    if not from then return end
    local cx, cy = cursorAt()
    drag = { thing = thing, cell = cell, from = from, to = from,
             dx = cx - cell.x, dy = cy - cell.y, level = cell:GetFrameLevel() }
    -- Keep it above the others while dragging.
    cell:SetFrameLevel(drag.level + 6)
    inner(cell, thing):SetFrameLevel(drag.level + 9)
    if GameTooltip:GetOwner() == inner(cell, thing) then GameTooltip:Hide() end
    Drawer.dragger:SetScript("OnUpdate", Drawer.DragMove)
end

function Drawer.DragMove()
    local d = drag
    if not d then return end
    local cx, cy = cursorAt()
    local strip, size, pad = Drawer.strip, Drawer.SIZE, Drawer.PAD
    -- Clamp to the strip.
    local x = math.min(-pad, math.max(-((strip:GetWidth() or 0) - pad - size), cx - d.dx))
    local y = math.max(pad, math.min((strip:GetHeight() or 0) - pad - size, cy - d.dy))
    moveCell(d.cell, x, y)
    -- Nearest slot.
    local cols, best, j = Drawer.cols or 1, math.huge, d.to
    for k = 1, #items do
        local sx, sy = slot(k, cols)
        local dist = (sx - x) ^ 2 + (sy - y) ^ 2
        if dist < best then best, j = dist, k end
    end
    if j == d.to then return end
    d.to = j
    -- Move the others to make room at slot j.
    local k = 0
    for _, thing in ipairs(items) do
        if thing ~= d.thing then
            k = k + 1
            if k == j then k = k + 1 end
            slideCell(cells[thing], slot(k, cols))
        end
    end
end

-- Saves the shown squares in their current order, followed by saved keys
-- that aren't shown, so hidden buttons keep their place.
local function saveOrder(order)
    local keys, seen = {}, {}
    local function add(k)
        if k and not seen[k] then
            seen[k] = true
            keys[#keys + 1] = k
        end
    end
    for _, thing in ipairs(order) do add(keyOf(thing)) end
    for _, k in ipairs(savedOrder()) do add(k) end
    if Drawer.cfg then Drawer.cfg.drawerOrder = keys end
end

function Drawer.DragStop()
    local d = dropDrag()
    if not d then return end
    -- Each square glides from where it's drawn now.
    local seen = {}
    for _, thing in ipairs(items) do
        local c = cells[thing]
        seen[c] = { c.x, c.y }
    end
    if d.to ~= d.from then
        local order = {}
        for _, thing in ipairs(items) do
            if thing ~= d.thing then order[#order + 1] = thing end
        end
        table.insert(order, d.to, d.thing)
        saveOrder(order)
    end
    Drawer.Layout()
    for c, at in pairs(seen) do
        local x, y = c.x, c.y
        if at[1] ~= x or at[2] ~= y then
            moveCell(c, at[1], at[2])
            slideCell(c, x, y)
        end
    end
end

-- ---------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------

local function ease(p)
    if p <= 0 then return 0 end
    if p >= 1 then return 1 end
    return 1 - (1 - p) ^ 3
end

-- Delay between icons, shrunk so a long row still finishes within RIPPLE.
local function stagger()
    local n = #items
    if n <= 1 then return 0 end
    return math.min(Drawer.STAGGER, Drawer.RIPPLE / (n - 1))
end

-- Draws the strip t seconds into opening or closing.
function Drawer.Paint()
    local strip, a = Drawer.strip, Drawer.anim
    if not strip then return end
    local t, open = a.t, Drawer.open
    local n, gap = #items, stagger()
    local w, alpha
    if open then
        w = minW + (fullW - minW) * ease(t / Motion.NORMAL)
        alpha = ease(t / Motion.FAST)
    else
        w = minW + (fullW - minW) * (1 - ease(t / Motion.CLOSE))
        alpha = 1 - ease((t - (Motion.CLOSE - Motion.FAST)) / Motion.FAST)
    end
    strip:SetWidth(math.max(minW, w))
    strip:SetAlpha(alpha)
    for k, thing in ipairs(items) do
        local e
        if open then
            e = ease((t - Drawer.LEAD - (k - 1) * gap) / Motion.NORMAL)
        else
            e = 1 - ease((t - (n - k) * gap / 2) / Motion.FAST)
        end
        setRise(cells[thing], e, Drawer.RISE * (1 - e))
    end
end

local function length()
    if not Drawer.open then return Motion.CLOSE end
    return Drawer.LEAD + math.max(0, #items - 1) * stagger() + Motion.NORMAL
end

local function finish()
    Drawer.driver:SetScript("OnUpdate", nil)
    Drawer.anim.t = length()
    Drawer.Paint()
    if not Drawer.open then Drawer.strip:Hide() end
end

local function tick(_, dt)
    local a = Drawer.anim
    a.t = a.t + dt
    if a.t >= length() then return finish() end
    Drawer.Paint()
end

-- The corner button's dots light up in the accent on hover or while open.
-- Only repainted when that changes; Drawer.Apply forces a repaint in case
-- the accent changed.
local function paintGlyph()
    local g = Drawer.glyph
    local lit = (Drawer.open or g:IsMouseOver()) and true or false
    if g.lit == lit then return end
    g.lit = lit
    local c = ns.Panel.ARROW_COLOR
    for _, d in ipairs(g.dots) do
        if lit then d:SetVertexColor(Style.AccentAt(d.t)) else d:SetVertexColor(c[1], c[2], c[3]) end
    end
end

-- Reversing mid-animation continues from the strip's current width.
local function start(open)
    local a = Drawer.anim
    local was = Drawer.strip:IsShown() and Drawer.driver:GetScript("OnUpdate") ~= nil
    local w = Drawer.strip:GetWidth() or minW
    local share = fullW > minW and math.min(1, math.max(0, (w - minW) / (fullW - minW))) or 1
    Drawer.open = open
    if was then
        -- Find the point on the new curve matching the current width.
        a.t = open and Motion.NORMAL * (1 - (1 - share) ^ (1 / 3)) or Motion.CLOSE * (1 - share ^ (1 / 3))
    else
        a.t = 0
    end
    Drawer.strip:Show()
    paintGlyph()
    if not Motion.On() then return finish() end
    Drawer.Paint()
    Drawer.driver:SetScript("OnUpdate", tick)
end

function Drawer.Open()
    if not Drawer.strip or Drawer.open then return end
    Drawer.Collect()
    if #items == 0 then return end
    Drawer.lastOver = GetTime()
    start(true)
end

function Drawer.Close(now)
    if not Drawer.strip or not Drawer.open then return end
    dropDrag()
    start(false)
    if now then finish() end
end

function Drawer.Toggle()
    if Drawer.open then Drawer.Close() else Drawer.Open() end
end

function Drawer.IsOpen() return Drawer.open == true end

-- Runs every WATCH seconds. Shows the corner button while the mouse is over
-- the map or the drawer is open, and closes the drawer LINGER seconds after
-- the mouse leaves.
function Drawer.Watch()
    local g, P = Drawer.glyph, ns.Panel
    if not (g and Drawer.on) then return end
    if changed() then Drawer.Collect() end
    local over = P.mapArea:IsMouseOver() == true or g:IsMouseOver() == true or menuHeld() or drag ~= nil
    local now = GetTime()
    if over then Drawer.lastOver = now end
    if Drawer.open and not over and now - (Drawer.lastOver or now) >= Drawer.LINGER then Drawer.Close() end
    local want = (over or Drawer.open) and 1 or 0
    if g.goal ~= want then
        g.goal = want
        local from = g:GetAlpha()
        Motion.Tween("infopanel:drawerGlyph", from, want, Motion.FAST, function(v) g:SetAlpha(v) end)
    end
    paintGlyph()
end

-- ---------------------------------------------------------------------
-- Build and apply
-- ---------------------------------------------------------------------

local function build()
    local P = ns.Panel
    local area = P.mapArea
    local base = (Minimap and Minimap:GetFrameLevel() or area:GetFrameLevel()) + 8

    local strip = CreateFrame("Frame", nil, area)
    strip:SetFrameLevel(base)
    Style.Shell(strip, { borderPx = P.XP_BORDER })
    strip:Hide()
    Drawer.strip = strip
    -- Clip the squares to the strip so they're hidden until it sweeps over them.
    local clip = CreateFrame("Frame", nil, strip)
    clip:SetAllPoints(strip)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(base + 2)
    Drawer.clip = clip
    Drawer.driver = CreateFrame("Frame", nil, strip)
    Drawer.dragger = CreateFrame("Frame", nil, strip)
    Drawer.anim = { t = 0 }

    local g = CreateFrame("Button", nil, area)
    g:SetSize(Drawer.SIZE, Drawer.SIZE)
    g:SetFrameLevel(base + 12)
    local s = Style.Shell(g, { borderPx = P.XP_BORDER })
    if s and s.bg then s.bg:SetAlpha(0.6) end
    -- Four dots in a square.
    g.dots = {}
    local d, gap = Drawer.DOT, Drawer.DOT_GAP
    local half = (d + gap) / 2
    for i, at in ipairs({ { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }) do
        local dot = g:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(1, 1, 1, 1)
        dot:SetSize(d, d)
        dot:SetPoint("CENTER", g, "CENTER", at[1] * half, at[2] * half)
        -- Gradient position: mostly left to right, a little top to bottom.
        dot.t = (at[1] + 1) / 2 * 0.75 + (1 - at[2]) / 2 * 0.25
        g.dots[i] = dot
    end
    g:SetScript("OnClick", function(self)
        Motion.Bump(self, 0.88)
        Drawer.Toggle()
    end)
    g:SetScript("OnEnter", function(self)
        paintGlyph()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ADDONS or DUI.L["AddOns"], 1, 1, 1)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function()
        paintGlyph()
        GameTooltip:Hide()
    end)
    g:SetAlpha(0)
    g.goal = 0
    g:Hide()
    Drawer.glyph = g
    C_Timer.NewTicker(Drawer.WATCH, function() DUI.SafeCall(Drawer.Watch) end)
end

function Drawer.Apply(cfg)
    Drawer.cfg = cfg
    Drawer.on = cfg.drawer == true and cfg.enabled ~= false
    if not Drawer.on then
        if Drawer.glyph then
            Drawer.Close(true)
            Drawer.glyph:Hide()
        end
        return
    end
    if not Drawer.glyph then build() end
    local P, strip, g = ns.Panel, Drawer.strip, Drawer.glyph
    g:ClearAllPoints()
    g:SetPoint("BOTTOMRIGHT", P.mapArea, "BOTTOMRIGHT", -Drawer.PAD, Drawer.PAD)
    Style.LayoutShell(Style.GetShell(g))
    strip:ClearAllPoints()
    strip:SetPoint("BOTTOMRIGHT", P.mapArea, "BOTTOMRIGHT", 0, 0)
    Drawer.Collect()
    Style.LayoutShell(Style.GetShell(strip))
    g.lit = nil
    paintGlyph()
    if not lateLook then
        lateLook = true
        C_Timer.After(Drawer.LATE, Drawer.Collect)
    end
end
