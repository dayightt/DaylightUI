-- The Cooldown Manager layout editor, drawn on the real screen (out of combat only).
-- The live layout steps aside (CdmRows.SetEditing) and a preview stands in for each
-- piece, with sample timers. A tray at the bottom lists every spell the Cooldown
-- Manager tracks: click one (or drag it up) and pick Icon or Bar. Pieces drag with
-- unlock mode's magnets and guide lines and land on its grid. A drag always moves a
-- whole group and never regroups anything; that used to group and ungroup at random.
-- The + on each free side of the selected piece is the only way into a group (the
-- next spell picked goes there), and "Unhook it" on the card is the way out. Every
-- change writes the saved layout (CdmData) and the live layout follows at once.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Data, Rows = ns.CdmData, ns.CdmRows

local Ed = {}
ns.CdmEditor = Ed

Ed.DRAG_PX = 4          -- how far a press moves before it counts as a drag
Ed.CELL = 30            -- tray spell size
Ed.CELL_BIG = 38        -- tray spell size while a + waits for one
Ed.CELL_GAP = 4
Ed.MAGNET = 3           -- icons sit so close that the usual 8 left no spot free of a line,
                        -- and a piece hopped line to line instead of following the mouse
Ed.TRAY_COLS = 18       -- spells per tray line (leaves room for the buttons and hint)
Ed.TRAY_LINES = 3       -- lines shown; the wheel scrolls the rest
Ed.TRAY_EDGE = 16       -- the tray's default distance above the screen's bottom
Ed.FADED = 0.35         -- alpha of the tray, title and banner while a piece moves
Ed.TICK = 0.1           -- sample timer step
local QUESTION = 134400
local AURA = { TrackedBuff = true, TrackedBar = true, HiddenAura = true }

local ui                -- the frames, made on first open
local isOpen = false
local selected, attach  -- a piece id; { id, side } while a + waits for a spell
local drag              -- the current press or drag (Ed.StartDrag / StartTrayDrag)
local trayMove          -- the tray being dragged: { sx, sy, x, y } (Ed.StartTrayMove)
local pending           -- the chooser's spell: { id, kind, aura, x, y }
local live = true       -- sample timers running
local query, showUnlearned, showGroup, trayTop = "", false, false, 0
local trayGrow = 0      -- 0 = normal tray size, 1 = grown for a waiting +
local panelPage         -- the options page the editor hid, reopened on Done

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local function shiftDown() return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() == true end

-- ---------------------------------------------------------------------
-- Spells
-- ---------------------------------------------------------------------

-- Name of a spell, trinket slot or potion (CdmOwn.Look).
function Ed.SpellName(id)
    return ns.CdmOwn and (ns.CdmOwn.Look(id)) or nil
end

function Ed.SpellTexture(id)
    local tex = ns.CdmOwn and select(2, ns.CdmOwn.Look(id))
    return tex or QUESTION
end

-- The cooldowns the game lists for this spec, including ones the character doesn't
-- know: { [id] = { kind, aura } }.
local function allListed()
    local out = {}
    local CV, cats = _G.C_CooldownViewer, type(_G.Enum) == "table" and _G.Enum.CooldownViewerCategory
    if type(CV) ~= "table" or type(CV.GetCooldownViewerCategorySet) ~= "function" or type(cats) ~= "table" then
        return out
    end
    for name, cat in pairs(cats) do
        if type(cat) == "number" then
            local ok, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    if type(id) == "number" and not (issecretvalue and issecretvalue(id)) and not out[id] then
                        out[id] = { kind = name == "TrackedBar" and "bar" or "icon", aura = AURA[name] or false }
                    end
                end
            end
        end
    end
    return out
end

-- Every spell the tray lists: { id, kind (the game's shape), aura, name, placed,
-- unlearned }. First the ones the game shows, then other known ones, then (with
-- Other talents on) ones this character doesn't know, and placed spells it no longer
-- has. One per spell name since the game lists every rank: a placed rank wins, else
-- the first (the newest known one).
function Ed.Spells()
    local set = Ed.Set()
    local Custom = ns.CdmCustom
    local list, seen, byName = {}, {}, {}
    local function add(id, kind, aura, unlearned)
        if seen[id] then return end
        seen[id] = true
        -- An empty trinket slot, or a cooldown the game gives no name or icon,
        -- has nothing to show. A placed one stays so it can be removed.
        if not set.pieces[id] and ns.CdmOwn and ns.CdmOwn.EmptySlot(id) then return end
        local name, tex = nil, nil
        if ns.CdmOwn then name, tex = ns.CdmOwn.Look(id) end
        if not set.pieces[id] and name == nil and tex == nil then return end
        local e = { id = id, kind = kind, aura = aura and true or false, name = name or "",
                    placed = set.pieces[id] ~= nil, unlearned = unlearned or nil,
                    custom = Custom ~= nil and Custom.Is(id) or nil }
        local at = name and byName[name]
        if at then
            if e.placed and not list[at].placed then list[at] = e end
            return
        end
        list[#list + 1] = e
        if name then byName[name] = #list end
    end
    local known = ns.CdmOwn and ns.CdmOwn.Known() or {}
    Rows.EachItem(function(_, id, kind)
        local k = known[id]
        add(id, kind, k and k.aura)
    end)
    local ids = {}
    for id in pairs(known) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return a > b end)
    for _, id in ipairs(ids) do add(id, known[id].kind, known[id].aura) end
    -- The custom list (CdmCustom): your class's spells and the group buffs. A spell
    -- the game also lists (same name) stays the game's; add skips it.
    if Custom then
        -- Group buffs (cast on you by others) only with Group buffs on, or when
        -- already placed.
        for _, c in ipairs(Custom.Tray()) do
            if showGroup or not Custom.IsGroup(c.id) or set.pieces[c.id] then add(c.id, "icon", c.aura) end
        end
    end
    if showUnlearned then
        local all, rest = allListed(), {}
        for id in pairs(all) do rest[#rest + 1] = id end
        table.sort(rest)
        for _, id in ipairs(rest) do add(id, all[id].kind, all[id].aura, true) end
        if Custom then
            for _, c in ipairs(Custom.Unlearned()) do add(c.id, "icon", c.aura, true) end
        end
    end
    -- Spells and items added by ID show in the tray while placed.
    local mine = {}
    for id in pairs(set.pieces) do
        if not seen[id] and Custom and Custom.IsAdded(id) then mine[#mine + 1] = id end
    end
    table.sort(mine, Data.ByKey)
    for _, id in ipairs(mine) do
        add(id, set.pieces[id].shape, Custom.Track(id) == "aura", ns.CdmOwn.Entry(id) == nil or nil)
    end
    local gone = {}
    for id in pairs(set.pieces) do if not seen[id] then gone[#gone + 1] = id end end
    table.sort(gone, Data.ByKey)
    for _, id in ipairs(gone) do add(id, set.pieces[id].shape, false, true) end
    return list
end

-- Add by ID (the tray button, like EllesmereUI's Custom Spell ID / Item ID). Returns
-- the piece key a typed spell or item ID stands for, or nil and the reason. A spell
-- the tray already has (the game's, or a rank of one on the custom list, matched by
-- name) maps to that; any other spell is "s<id>", and an item with a use is
-- "i<id>". An item the game hasn't loaded yet returns "wait"; it's requested and
-- ITEM_DATA_LOAD_RESULT tries again.
local waitingItem
function Ed.KeyForID(kind, text)
    local n = tonumber((tostring(text or ""):gsub("%s", "")))
    if not n or n <= 0 or n % 1 ~= 0 then return nil, "number" end
    local Custom = ns.CdmCustom
    if kind == "item" then
        local get = type(C_Item) == "table" and C_Item.GetItemInfoInstant
        local ok, found = false, nil
        if type(get) == "function" then ok, found = pcall(get, n) end
        if not (ok and found) then return nil, "item" end
        local cached = type(C_Item.IsItemDataCachedByID) ~= "function" or C_Item.IsItemDataCachedByID(n)
        if not Custom.Family("i" .. n) then
            if not cached then return nil, "wait" end
            return nil, "use"
        end
        return "i" .. n
    end
    local ok, name = false, nil
    if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then ok, name = pcall(C_Spell.GetSpellName, n) end
    if not (ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "") then
        return nil, "spell"
    end
    for _, e in ipairs(Ed.Spells()) do
        if e.name == name and not Custom.ItemOf(e.id) then return e.id end
    end
    return Custom.KeyOfSpell(n) or "s" .. n
end

local ID_ERRORS = {
    number = L["Type a number."],
    spell = L["No spell has that ID."],
    item = L["No item has that ID."],
    use = L["That item has no use to time."],
}

-- Asks for the ID, then picks it like a tray click (the Icon / Bar chooser, or
-- selected if already placed). A bad ID asks again, saying why.
function Ed.AskID(kind, why)
    local ask = kind == "item" and L["Item ID:"] or L["Spell ID:"]
    if why then ask = why .. "\n" .. ask end
    DUI.Widgets.Prompt(ask, "", function(text)
        if not isOpen then return end
        local key, err = Ed.KeyForID(kind, text)
        if key then
            waitingItem = nil
            Ed.Choose(key)
        elseif err == "wait" then
            waitingItem = tonumber((tostring(text):gsub("%s", "")))
        else
            Ed.AskID(kind, ID_ERRORS[err])
        end
    end, { now = true })
end

function Ed.OpenAddMenu(owner)
    -- Values by key, as W.OpenMenu expects (a plain list drew blank rows).
    DUI.Widgets.OpenMenu(owner, { "spell", "item" }, { spell = L["Spell ID"], item = L["Item ID"] }, nil,
        function(k) Ed.AskID(k) end, 140)
end

pcall(DUI.RegisterEvent, "ITEM_DATA_LOAD_RESULT", function(_, item, success)
    if waitingItem == nil or item ~= waitingItem then return end
    waitingItem = nil
    if not isOpen then return end
    local key, err = Ed.KeyForID("item", item)
    if key then Ed.Choose(key)
    elseif success then Ed.AskID("item", ID_ERRORS[err] or ID_ERRORS.use)
    else Ed.AskID("item", ID_ERRORS.item) end
end)

function Ed.SetShowGroup(on)
    showGroup = on and true or false
    trayTop = 0
    Ed.Draw()
end

function Ed.SetShowUnlearned(on)
    showUnlearned = on and true or false
    trayTop = 0
    Ed.Draw()
end

function Ed.SetQuery(text)
    query = string.lower(text or "")
    trayTop = 0
    Ed.Draw()
end

-- ---------------------------------------------------------------------
-- State and changes (no frames; this is what the tests drive)
-- ---------------------------------------------------------------------

function Ed.IsOpen() return isOpen end
function Ed.Set() return Data.Current() end
function Ed.Selected() return selected end
function Ed.Attach() return attach end
function Ed.Pending() return pending end
function Ed.Dragging() return drag end
function Ed.Live() return live end
function Ed.Overlay() return ui and ui.overlay end
function Ed.Tray() return ui and ui.tray end
function Ed.Banner() return ui and ui.banner end
function Ed.TrayCell(i) return ui and ui.cells[i] end
function Ed.Pill() return ui and ui.pill end
function Ed.PillButton(key) return ui and ui[key] end   -- "import", "reset", "live"...
function Ed.PreviewOf(id) return ui and ui.pieces[id] end

-- After a layout change: update the live layout, then the editor.
function Ed.Changed()
    Data.Changed()
    Rows.Refresh()
    Ed.Draw()
end

function Ed.Select(id)
    if id ~= nil and not Ed.Set().pieces[id] then id = nil end
    selected = id
    if not (attach and attach.id == id) then attach = nil end
    Ed.Draw()
end

-- The + on a free side: the next spell picked goes there.
function Ed.SetAttach(id, side)
    if id ~= nil and Ed.Set().pieces[id] then
        selected, attach = id, { id = id, side = side }
    else
        attach = nil
    end
    Ed.Draw()
end

-- Which talent set's layout is being edited (nil = the one in use).
function Ed.Group() return Data.CurrentIndex() end
function Ed.SetGroup(g)
    if g == DUI.DB.SpecGroup() then g = nil end
    Data.SetViewing(g)
    Data.Ensure(Data.CurrentIndex())
    selected, attach, pending = nil, nil, nil
    Rows.Refresh()
    Ed.Draw()
end

function Ed.SetLive(on)
    live = on and true or false
    Ed.Draw()
end

-- The size a piece of this shape gets with the default look.
local function defaultDims(shape)
    if shape == "bar" then return Data.LOOK.width, Data.LOOK.height end
    return Data.LOOK.size, Data.LOOK.size
end

-- A free spot for a new w x h piece: above the middle of the screen, stepping
-- across and then down past what's placed.
function Ed.FreeSpot(w, h)
    local boxes = Data.Layout(Ed.Set())
    for i = 0, 29 do
        local cx, cy = ((i % 5) - 2) * 70, 140 - floor(i / 5) * 60
        local x, y = cx - w / 2, cy + h / 2
        local clear = true
        for _, b in pairs(boxes) do
            if x < b.x + b.w + 8 and b.x < x + w + 8 and y - h < b.y + 8 and b.y - b.h < y + 8 then
                clear = false
                break
            end
        end
        if clear then return floor(x + 0.5), floor(y + 0.5) end
    end
    return floor(-w / 2 + 0.5), floor(h / 2 + 0.5)
end

-- How a spell of `shape` aligns on `side` of a piece.
local function alignOn(host, shape, side)
    if host.shape == shape then return "center" end
    return (side == "up" or side == "down") and "start" or "center"
end

-- A placed spell picked while a + waits moves there, with anything hanging off it.
-- Returns false when no + waits or it can't go there.
local function joinWaiting(id)
    if not attach or attach.id == id then return false end
    local set = Ed.Set()
    local p, host = set.pieces[id], set.pieces[attach.id]
    if not (p and host) then return false end
    if not Data.Hook(set, id, attach.id, attach.side, alignOn(host, p.shape, attach.side)) then return false end
    attach, pending = nil, nil
    selected = id
    Ed.Changed()
    if DUI.Sound then DUI.Sound.Play("snap") end
    return true
end

-- Adds a spell to the layout as `shape`: on the waiting + side, at x, y (its
-- top-left), or at a free spot.
function Ed.Add(id, shape, x, y)
    local set = Ed.Set()
    shape = shape == "bar" and "bar" or "icon"
    if attach and set.pieces[attach.id] and not set.pieces[id] then
        local side = attach.side
        Data.AddPiece(set, id, shape, 0, 0)
        Data.Hook(set, id, attach.id, side, alignOn(set.pieces[attach.id], shape, side))
    else
        if not x then x, y = Ed.FreeSpot(defaultDims(shape)) end
        Data.AddPiece(set, id, shape, x, y)
    end
    attach, pending = nil, nil
    selected = id
    if ui then ui.born = id end
    Ed.Changed()
    if DUI.Sound then DUI.Sound.Play("snap") end
end

function Ed.Remove(id)
    local set = Ed.Set()
    if id == nil or not set.pieces[id] then return end
    Data.RemovePiece(set, id)
    if selected == id then selected = nil end
    attach = nil
    Ed.Changed()
end

-- Removes every spell from the layout being edited. The profile stays, empty.
function Ed.Reset()
    local set = Ed.Set()
    if next(set.pieces) == nil then return end
    Data.Changed()
    set.pieces, set.chains = {}, {}
    selected, attach, pending = nil, nil, nil
    Ed.Changed()
end

-- Removes id's whole group (chain); its spells go back to the tray.
function Ed.RemoveChain(id)
    local set = Ed.Set()
    if id == nil or not set.pieces[id] then return end
    Data.RemoveChain(set, id)
    if selected ~= nil and not set.pieces[selected] then selected = nil end
    attach = nil
    Ed.Changed()
end

-- Opens the Icon/Bar chooser for a tray spell (Ed.Pick answers it). A placed spell
-- isn't chosen again: it goes to a waiting +, otherwise its piece gets selected.
function Ed.Choose(id, x, y)
    if Ed.Set().pieces[id] then
        if joinWaiting(id) then return end
        pending = nil
        Ed.Select(id)
        return
    end
    local e
    for _, s in ipairs(Ed.Spells()) do if s.id == id then e = s end end
    local ax, ay = x, y
    if not ax then ax, ay = Ed.Cursor() end
    pending = { id = id, kind = e and e.kind or "icon", aura = e and e.aura, x = x, y = y, ax = ax, ay = ay }
    Ed.Draw()
end

function Ed.Pick(shape)
    local p = pending
    if not p then return end
    local x, y = p.x, p.y
    -- A drop point is where the piece's middle goes; its corner then snaps to the
    -- grid, the same as a dragged piece.
    if x then
        local w, h = defaultDims(shape)
        x, y = floor(x - w / 2 + 0.5), floor(y + h / 2 + 0.5)
        if DUI.DB.General().gridSnap then x, y = DUI.Movers.OnGrid(x), DUI.Movers.OnGrid(y) end
    end
    Ed.Add(p.id, shape, x, y)
end

function Ed.CancelPick()
    pending = nil
    Ed.Draw()
end

-- ---------------------------------------------------------------------
-- Dragging (cursor in UIParent units from screen center, y up)
-- ---------------------------------------------------------------------

function Ed.Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s - UIParent:GetWidth() / 2, y / s - UIParent:GetHeight() / 2
end

-- What a dragged piece snaps to: other pieces and every frame on screen.
local function snapTargets(set, mine)
    local out = {}
    local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    for id, b in pairs(Data.Layout(set)) do
        if not mine[id] then out[#out + 1] = { l = cx + b.x, r = cx + b.x + b.w, b = cy + b.y - b.h, t = cy + b.y } end
    end
    for _, r in ipairs(DUI.Movers.FrameRects()) do out[#out + 1] = r end
    return out
end

-- A press on a piece: a click selects it, a drag moves its whole group.
function Ed.StartDrag(id, cx, cy)
    if not Ed.Set().pieces[id] then return end
    drag = { id = id, sx = cx, sy = cy }
    pending = nil
end

-- A press on a tray spell: a click opens the chooser, a drag carries it up.
function Ed.StartTrayDrag(id, cx, cy)
    drag = { id = id, sx = cx, sy = cy, tray = true }
end

local function startMoving(set)
    drag.moved = true
    attach = nil
    ns.CdmCard.Hide()
    if drag.tray then
        local kind = "icon"
        for _, s in ipairs(Ed.Spells()) do if s.id == drag.id then kind = s.kind end end
        drag.w, drag.h = defaultDims(kind)
        return
    end
    selected = drag.id
    drag.id = Data.Root(set, drag.id)
    local p = set.pieces[drag.id]
    drag.ox, drag.oy = p.x, p.y
    drag.mine = {}
    for _, q in ipairs(Data.Subtree(set, drag.id)) do drag.mine[q] = true end
    drag.others = DUI.DB.General().magnet ~= false and snapTargets(set, drag.mine) or nil
end

function Ed.DragTo(cx, cy)
    if not drag then return end
    local set = Ed.Set()
    local dx, dy = cx - drag.sx, cy - drag.sy
    if not drag.moved then
        if abs(dx) < Ed.DRAG_PX and abs(dy) < Ed.DRAG_PX then return end
        startMoving(set)
    end
    drag.cx, drag.cy = cx, cy
    local gx, gy
    if not drag.tray then
        local p = set.pieces[drag.id]
        local nx, ny = drag.ox + dx, drag.oy + dy
        if drag.others and not shiftDown() then
            local w, h = Data.Dims(set, drag.id)
            local ox, oy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
            local mx, my
            mx, my, gx, gy = DUI.Movers.Magnet({ l = ox + nx, r = ox + nx + w, b = oy + ny - h, t = oy + ny }, drag.others, Ed.MAGNET)
            nx, ny = nx + (mx or 0), ny + (my or 0)
        end
        p.x, p.y = nx, ny
    end
    drag.gx, drag.gy = gx, gy
    DUI.Movers.ShowGuides(gx, gy)
    Ed.DrawPieces()
end

-- overTray: the drop landed back on the tray, which cancels a tray drag.
function Ed.Drop(overTray)
    local d = drag
    drag = nil
    if not d then return end
    DUI.Movers.ShowGuides(nil, nil)
    local set = Ed.Set()
    if not d.moved then
        if d.tray then
            Ed.Choose(d.id)
        elseif not joinWaiting(d.id) then
            Ed.Select(d.id)
        end
        return
    end
    if d.tray then
        if overTray then Ed.Draw(); return end
        Ed.Choose(d.id, d.cx, d.cy)
        return
    end
    local p = set.pieces[d.id]
    if not p then Ed.Draw(); return end
    -- Snap the corner to the grid like unlock mode, except along an axis the magnet
    -- already lined up. The last bit glides.
    local x0, y0 = p.x, p.y
    local x, y = p.x, p.y
    if DUI.DB.General().gridSnap then
        if not d.gx then x = DUI.Movers.OnGrid(x) end
        if not d.gy then y = DUI.Movers.OnGrid(y) end
    end
    p.x, p.y = floor(x + 0.5), floor(y + 0.5)
    if ui and (p.x ~= x0 or p.y ~= y0) then ui.glide, ui.from = d.id, { x0, y0 } end
    if DUI.Sound then DUI.Sound.Play("snap") end
    Ed.Changed()
end

-- Offset from the first piece's top-left to the middle of id's whole chain. Saved
-- positions use that corner, but players think in terms of the chain's middle.
local function chainMiddle(set, id)
    local root = Data.Root(set, id)
    local boxes = Data.Layout(set)
    local l, r, t, b
    for _, q in ipairs(Data.Subtree(set, root)) do
        local c = boxes[q]
        if c then
            l, r = math.min(l or c.x, c.x), math.max(r or c.x + c.w, c.x + c.w)
            t, b = math.max(t or c.y, c.y), math.min(b or c.y - c.h, c.y - c.h)
        end
    end
    local p = set.pieces[root]
    if not l then return 0, 0 end
    return (l + r) / 2 - (tonumber(p.x) or 0), (t + b) / 2 - (tonumber(p.y) or 0)
end

-- Moves the picked chain so its middle is at x, y from screen center (0, 0 is
-- centered, as in unlock mode). Used by the card's Position row.
function Ed.MoveTo(x, y)
    local set = Ed.Set()
    if selected == nil or not set.pieces[selected] then return false end
    local mx, my = chainMiddle(set, selected)
    if not Data.MoveChain(set, selected, x - mx, y - my) then return false end
    Ed.Changed()
    return true
end

function Ed.Nudge(dx, dy)
    local set = Ed.Set()
    if selected == nil or not set.pieces[selected] then return false end
    local p = set.pieces[Data.Root(set, selected)]
    if not Data.MoveChain(set, selected, (tonumber(p.x) or 0) + dx, (tonumber(p.y) or 0) + dy) then return false end
    Ed.Changed()
    return true
end

-- Where the picked chain's middle is relative to screen center, or nil.
function Ed.Spot()
    local set = Ed.Set()
    if selected == nil or not set.pieces[selected] then return nil end
    local p = set.pieces[Data.Root(set, selected)]
    local mx, my = chainMiddle(set, selected)
    return floor((tonumber(p.x) or 0) + mx + 0.5), floor((tonumber(p.y) or 0) + my + 0.5)
end

-- The tray can be moved out of the way by dragging any empty spot. It's kept fully
-- on screen and remembered account-wide in DB.Root().cdmTray as its bottom-center
-- relative to the screen's bottom-center.
function Ed.TrayAt()
    local s = DUI.DB.Root().cdmTray
    if type(s) == "table" and type(s.x) == "number" and type(s.y) == "number" then return s.x, s.y end
    return 0, Ed.TRAY_EDGE
end

local function clampTray(x, y)
    local mx = max(0, (UIParent:GetWidth() - ui.tray:GetWidth()) / 2)
    local my = max(0, UIParent:GetHeight() - ui.tray:GetHeight())
    return max(-mx, min(x, mx)), max(0, min(y, my))
end

-- The "what to do now" banner sits under the title, but a waiting + puts it on the
-- tray, where your eyes go next (up top it went unnoticed). A tray pushed to the top
-- of the screen has it underneath.
local function placeBanner(onTray)
    local b, tray = ui.banner, ui.tray
    b:ClearAllPoints()
    if not onTray then
        b:SetPoint("TOP", ui.pill, "BOTTOM", 0, -8)
        return
    end
    local _, y = clampTray(Ed.TrayAt())
    local grown = (Ed.CELL_BIG - Ed.CELL) * Ed.TRAY_LINES
    if y + tray:GetHeight() + grown + b:GetHeight() + 8 > UIParent:GetHeight() then
        b:SetPoint("TOP", tray, "BOTTOM", 0, -8)
    else
        b:SetPoint("BOTTOM", tray, "TOP", 0, 8)
    end
end

local function placeTray()
    local x, y = clampTray(Ed.TrayAt())
    ui.tray:ClearAllPoints()
    ui.tray:SetPoint("BOTTOM", ui.overlay, "BOTTOM", x, y)
end

function Ed.StartTrayMove(cx, cy)
    if not ui then return end
    local x, y = clampTray(Ed.TrayAt())
    trayMove = { sx = cx, sy = cy, x = x, y = y }
end

function Ed.MoveTray(cx, cy)
    if not (trayMove and ui) then return end
    local x, y = clampTray(trayMove.x + cx - trayMove.sx, trayMove.y + cy - trayMove.sy)
    local root = DUI.DB.Root()
    local s = type(root.cdmTray) == "table" and root.cdmTray or {}
    s.x, s.y = x, y
    root.cdmTray = s
    placeTray()
    if ui.banner.asking then placeBanner(true) end
end

function Ed.EndTrayMove() trayMove = nil end

-- ---------------------------------------------------------------------
-- Opening and closing
-- ---------------------------------------------------------------------

local build

-- g = the talent set to edit (nil = the one in use).
function Ed.Open(g)
    -- Switched off (setting `cooldowns`): leave the game's Cooldown Manager alone.
    if not ns.Cooldowns.enabled then
        DUI.Print(L["DaylightUI's Cooldown Manager is off: switch it on under Cooldown Manager > Layout in /dui."])
        return false
    end
    if InCombatLockdown() then
        DUI.Print(L["The cooldown layout can't be edited during combat."])
        return false
    end
    if isOpen then
        if g then Ed.SetGroup(g) end
        return true
    end
    Rows.Init()
    isOpen = true
    selected, attach, pending, drag, trayMove = nil, nil, nil, nil, nil
    if g == DUI.DB.SpecGroup() then g = nil end
    Data.SetViewing(g)
    Data.Ensure(Data.CurrentIndex())   -- so edits land in a saved profile
    local Panel = DUI.OptionsPanel
    panelPage = nil
    if Panel and Panel.IsShown() then
        panelPage = Panel.Current()
        Panel.Toggle()
    end
    Rows.SetEditing(true)
    DUI.Movers.HoldGrid("cdm", true)
    if not ui then build() end
    ui.overlay:Show()
    Ed.Draw()
    if DUI.Sound then DUI.Sound.Play("open") end
    return true
end

function Ed.Close()
    if not isOpen then return end
    isOpen = false
    if Ed.FlowCheck then Ed.FlowCheck() end   -- stop the outline colors from cycling
    selected, attach, pending, drag, trayMove = nil, nil, nil, nil, nil
    Data.SetViewing(nil)
    DUI.Movers.ShowGuides(nil, nil)
    ns.CdmCard.Hide()
    trayGrow = 0
    DUI.Motion.Tween("cdmTrayGrow", 0, 0, 0)
    if ui then
        ui.tray.growTo = nil
        ui.overlay:Hide()
    end
    if GameTooltip then GameTooltip:Hide() end
    Rows.SetEditing(false)
    DUI.Movers.HoldGrid("cdm", false)
    if DUI.Sound then DUI.Sound.Play("close") end
    if panelPage and not InCombatLockdown() then DUI.OptionsPanel.Show(panelPage) end
    panelPage = nil
end

-- ---------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------

local function W() return DUI.Widgets end
local function C() return DUI.Widgets.COLORS end

-- A lit outline: an accent gradient line around f, px screen pixels thick, with a
-- soft halo fading out just outside it (Ed.HALO). The colors flow around it. Each
-- edge is Ed.SEGMENTS short pieces that take the color of their spot on the loop,
-- and the loop turns once every Ed.FLOW seconds. One driver serves every lit
-- outline and only runs while the editor is open with one lit; with motion off it
-- holds still. A gradient accent uses its two ends; a single-color accent runs from
-- the accent to a lighter shade (Ed.LIFT). The pieces are plain color fills, since a
-- texture with nothing set draws nothing whatever its tint.
Ed.HALO = { { spread = 2, alpha = 0.3 }, { spread = 3, alpha = 0.1 } }   -- inner, then outer
Ed.LIFT = 0.45
Ed.SEGMENTS = 6
Ed.FLOW = 2.5    -- seconds per lap of the colors around an outline
local function accentEnds()
    local S = DUI.Style
    local a, b = S.AccentPair()
    if a and b then return a, b end
    local r, g, bl = S.Accent()
    local k = Ed.LIFT
    return { r, g, bl }, { r + (1 - r) * k, g + (1 - g) * k, bl + (1 - bl) * k }
end
-- The color at t (0..1) around the loop: first end to last and back.
local function colorAt(a, b, t, alpha)
    local k = 1 - abs(2 * (t % 1) - 1)
    return CreateColor(a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, alpha)
end
-- A ring: 4 edges of n pieces each, clockwise from the top-left.
local function ring(f, layer)
    local t = {}
    for i = 1, 4 * Ed.SEGMENTS do
        t[i] = f:CreateTexture(nil, "OVERLAY", nil, layer)
        t[i]:SetColorTexture(1, 1, 1, 1)
        t[i]:Hide()
    end
    return t
end
-- Lays out the ring w thick, `out` px outside f. Each piece records where it starts
-- and ends around the loop (p0, p1).
local function layRing(t, f, w, out)
    local n = Ed.SEGMENTS
    local o = out + w
    local fw, fh = f:GetWidth(), f:GetHeight()
    if type(fw) ~= "number" or type(fh) ~= "number" then return end
    local W, H = fw + 2 * o, fh + 2 * o - 2 * w   -- the sides fit between top and bottom
    local per = 2 * (fw + 2 * o) + 2 * H
    local at = 0
    for e = 1, 4 do
        local horiz = e == 1 or e == 3
        local len = horiz and W or H
        for k = 0, n - 1 do
            local tex = t[(e - 1) * n + k + 1]
            local s0, s1 = len * k / n, len * (k + 1) / n
            tex:ClearAllPoints()
            if e == 1 then          -- top, left to right
                tex:SetPoint("TOPLEFT", f, "TOPLEFT", -o + s0, o); tex:SetSize(s1 - s0, w)
            elseif e == 2 then      -- right, top to bottom
                tex:SetPoint("TOPRIGHT", f, "TOPRIGHT", o, o - w - s0); tex:SetSize(w, s1 - s0)
            elseif e == 3 then      -- bottom, right to left
                tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", o - s0, -o); tex:SetSize(s1 - s0, w)
            else                    -- left, bottom to top
                tex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -o, -o + w + s0); tex:SetSize(w, s1 - s0)
            end
            tex.p0, tex.p1, tex.edge = (at + s0) / per, (at + s1) / per, e
        end
        at = at + len
    end
end
local function paintRing(t, a, b, alpha, phase)
    for _, tex in ipairs(t) do
        if tex.p0 then
            local c0, c1 = colorAt(a, b, tex.p0 + phase, alpha), colorAt(a, b, tex.p1 + phase, alpha)
            tex:SetVertexColor(1, 1, 1, alpha)
            -- each piece spans from its start to its end around the loop
            local e = tex.edge
            if e == 1 then tex:SetGradient("HORIZONTAL", c0, c1)
            elseif e == 3 then tex:SetGradient("HORIZONTAL", c1, c0)
            elseif e == 2 then tex:SetGradient("VERTICAL", c1, c0)
            else tex:SetGradient("VERTICAL", c0, c1) end
        end
    end
end
local flows, flowDriver, phase = {}, nil, 0
local function flowOn()
    if not flowDriver then flowDriver = CreateFrame("Frame") end
    if next(flows) and isOpen and DUI.Motion.On() then
        flowDriver:SetScript("OnUpdate", function(_, elapsed)
            if not (isOpen and next(flows)) then flowDriver:SetScript("OnUpdate", nil); return end
            phase = (phase + elapsed / Ed.FLOW) % 1
            for paint in pairs(flows) do paint(phase) end
        end)
    else
        flowDriver:SetScript("OnUpdate", nil)
    end
end
Ed.FlowCheck = function() flowOn() end
function Ed.Flowing() return flowDriver ~= nil and flowDriver:GetScript("OnUpdate") ~= nil end
local function outline(f, px)
    local line, halos = ring(f, 7), { ring(f, 6), ring(f, 5) }
    local a, b
    local function paint(ph)
        if not f:IsVisible() then return end   -- faded out, nothing to turn
        paintRing(line, a, b, 1, ph)
        for n, h in ipairs(Ed.HALO) do paintRing(halos[n], a, b, h.alpha, ph) end
    end
    return function(on)
        if on then
            local w = DUI.Pixel.Px(f, px)
            layRing(line, f, w, 0)
            local out = w
            for n, h in ipairs(Ed.HALO) do
                local hw = DUI.Pixel.Px(f, h.spread)
                layRing(halos[n], f, hw, out)
                out = out + hw
            end
            a, b = accentEnds()
            paint(phase)
            flows[paint] = true
        else
            flows[paint] = nil
        end
        for i = 1, #line do
            line[i]:SetShown(on)
            for _, h in ipairs(halos) do h[i]:SetShown(on) end
        end
        flowOn()
    end
end

local function onPieceDown(self, button)
    if button ~= "LeftButton" then return end
    Ed.StartDrag(self.id, Ed.Cursor())
end
local function onPieceUp(self, button)
    if button == "RightButton" then Ed.Select(self.id); return end
    if drag then Ed.Drop() end
end
local function onPieceEnter(self)
    if drag then return end
    W().Tooltip(self, Ed.SpellName(self.id) or L["Unknown spell"],
        L["Drag to move. Drop it beside another piece to hook it on, drag it away to free it. Delete removes it."])
end

-- One preview piece: a frame with the spell's icon (icon shape), or an icon square
-- plus a bar with the spell's name and a time (bar shape).
local function previewFor(id)
    local f = ui.pieces[id]
    if f then return f end
    f = CreateFrame("Frame", nil, ui.overlay)
    f:SetFrameLevel(ui.overlay:GetFrameLevel() + 10)
    f:EnableMouse(true)
    f.id = id
    DUI.Style.Shell(f, {})
    f.icon = f:CreateTexture(nil, "ARTWORK")
    DUI.Style.CropIcon(f.icon)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)
    f.cd:SetDrawEdge(false)
    f.bar = DUI.Style.Bar(f)
    f.name = DUI.Style.Text(f.bar, 11, "LEFT")
    f.name:SetPoint("LEFT", f.bar, "LEFT", 4, 0)
    f.time = DUI.Style.Text(f.bar, 11, "RIGHT")
    f.time:SetPoint("RIGHT", f.bar, "RIGHT", -4, 0)
    f.key = f:CreateFontString(nil, "OVERLAY")
    f.lit = outline(f, 2)
    f:SetScript("OnMouseDown", onPieceDown)
    f:SetScript("OnMouseUp", onPieceUp)
    f:SetScript("OnEnter", onPieceEnter)
    f:SetScript("OnLeave", function() W().HideTooltip() end)
    ui.pieces[id] = f
    return f
end

-- The sample timer: a length derived from the spell id, with staggered starts.
local function sample(id)
    -- Custom spell keys are "s<spell id>"; take the number.
    if type(id) ~= "number" then id = tonumber(tostring(id):match("%d+")) or 0 end
    local dur = 8 + (id % 23)
    local t = ((GetTime() or 0) + id * 1.7) % dur
    return dur, t
end

local function paintPiece(f, set, id, b)
    local p = set.pieces[id]
    local bar = p.shape == "bar"
    local look = function(k) return Data.PieceLook(set, id, k) end
    f.icon:SetTexture(Ed.SpellTexture(id))
    f.icon:ClearAllPoints()
    f.bar:SetShown(bar)
    if bar then
        local showIcon = look("icon") ~= false
        f.icon:SetShown(showIcon)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        f.icon:SetSize(b.h, b.h)
        f.bar:ClearAllPoints()
        f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", showIcon and b.h or 0, 0)
        f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        -- The spell's own name and time size and color, matching its real bar.
        local CD = ns.Cooldowns
        local t = CD.BarText({ text = look("text"), barText = Data.TextOf(set, id, Data.BAR_TEXT_KEYS) })
        DUI.Style.SetTextSize(f.name, t.nameSize)
        DUI.Style.SetTextSize(f.time, t.timeSize)
        CD.Ink(f.name, t.nameColor)
        CD.Ink(f.time, t.timeColor)
        f.name:SetText(Ed.SpellName(id) or "")
        -- The spell's own Show name / Name position, matching its real bar.
        local Fx = ns.CdmEffects
        ns.Cooldowns.PlaceName(f.name, f.bar, Fx.Get(p, "showName") ~= false, Fx.Get(p, "nameAlign") == "center")
        f.time:SetShown(look("time") ~= false)
        DUI.Style.SetBarColor(f.bar, DUI.Style.ClassColor(select(2, UnitClass("player"))))
        -- A dark empty part, like the real bars.
        local back, c = DUI.Style.BarBack(f.bar), DUI.Style.BACKGROUND
        if back then back:SetVertexColor(c[1], c[2], c[3], DUI.Style.BAR_BACK_ALPHA) end
        f.cd:Hide()
        f.key:Hide()
    else
        f.icon:SetShown(true)
        f.icon:SetAllPoints(f)
        f.cd:Show()
        -- The key that casts it, as the real icon will show it.
        local CD = ns.Cooldowns
        local text, t = CD.KeyText({ iconText = Data.TextOf(set, id) }, Ed.SpellName(id))
        CD.StyleKey(f.key, f, t)
        f.key:SetText(text or "")
        f.key:Show()
    end
    f.aura = ns.CdmOwn and (ns.CdmOwn.Entry(id) or {}).aura or false
end

-- Steps the sample timers every Ed.TICK while Live preview is on.
local function tickSamples()
    local now = GetTime() or 0
    for id, f in pairs(ui.pieces) do
        if f:IsShown() then
            local dur, t = sample(id)
            if not live then t = dur * 0.4 end
            if f.bar:IsShown() then
                f.bar:SetValue(f.aura and 1 - t / dur or t / dur)
                f.time:SetText(live and string.format("%d", floor(dur - t + 0.5)) or "")
            elseif live then
                if not f.cdUntil or now >= f.cdUntil then
                    f.cd:SetCooldown(now - t, dur)
                    f.cdUntil = now - t + dur
                end
            elseif f.cdUntil then
                f.cd:Clear()
                f.cdUntil = nil
            end
        end
    end
end

local function placePiece(f, b)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", ui.overlay, "CENTER", b.x, b.y)
    f:SetSize(max(1, b.w), max(1, b.h))
end

-- The + buttons around the selected piece.
local PLUS_AT = {
    right = { "LEFT", "RIGHT", 6, 0 }, left = { "RIGHT", "LEFT", -6, 0 },
    up = { "BOTTOM", "TOP", 0, 6 }, down = { "TOP", "BOTTOM", 0, -6 },
}
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

local function drawPlus(set)
    local f = selected and not drag and ui.pieces[selected]
    local p = f and set.pieces[selected]
    for _, side in ipairs(Data.SIDES) do
        local b = ui.plus[side]
        local free = p and not Data.Child(set, selected, side) and not (p.parent ~= nil and side == OPPOSITE[p.side])
        if free then
            local at = PLUS_AT[side]
            b:ClearAllPoints()
            b:SetPoint(at[1], f, at[2], at[3], at[4])
            b.SetActive(attach ~= nil and attach.side == side)
        end
        b:SetShown(free and true or false)
    end
end

local SIDE_TEXT = {
    up = L["Pick a spell to put above %s"], down = L["Pick a spell to put below %s"],
    left = L["Pick a spell to put left of %s"], right = L["Pick a spell to put right of %s"],
}

local function drawBanner(set)
    local text
    local asking = attach ~= nil and set.pieces[attach.id] ~= nil
    if asking then
        local name = Ed.SpellName(attach.id) or "?"
        local hex = DUI.Win.Parts.Hex({ DUI.Style.Accent() })
        text = string.format(SIDE_TEXT[attach.side], hex .. name .. "|r") .. "  (" .. L["Esc"] .. ")"
    elseif not next(set.pieces) then
        text = L["Click a spell in the tray, or drag it up onto the screen."]
    elseif not selected then
        text = L["Click a piece to change it, + to add a spell beside it. Arrow keys nudge it, Shift turns the magnet off."]
    end
    local b = ui.banner
    if not text then
        DUI.Motion.AlphaTo(b, 0, DUI.Motion.FAST, true)
        b.asking = nil
        return
    end
    local fresh = asking ~= (b.asking == true)
    if fresh or not b:IsShown() then
        DUI.Style.SetTextSize(b.text, asking and DUI.Style.SIZE.body or DUI.Style.SIZE.small)
        b:SetHeight(asking and 32 or 26)
    end
    b.text:SetText(text)
    b:SetWidth(b.text:GetStringWidth() + 28)
    placeBanner(asking)
    DUI.Motion.AlphaTo(b, 1, 0)
    if fresh then DUI.Motion.Pop(b) end
    b.asking = asking or nil
end

local function drawPill()
    local g = Ed.Group()
    local using = g == DUI.DB.SpecGroup()
    local prof = Data.Profile(Data.Use(g))
    local setText = string.format(using and L["Talent set %d (in use)"] or L["Talent set %d"], g)
    ui.set.text:SetText(prof and string.format(L["%s: %s"], setText, tostring(prof.name)) or setText)
    ui.set.FitWidth(120)
    ui.live.SetActive(live)
    ui.snap.Sync()
    ui.mag.Sync()
    -- The talent set label just changed its button's width.
    ui.fitPill()
end

function Ed.SnapButtons() return ui and ui.snap, ui and ui.mag end

local function cellFor(i)
    local c = ui.cells[i]
    if c then return c end
    c = CreateFrame("Button", nil, ui.tray)
    c:SetSize(Ed.CELL, Ed.CELL)
    c:EnableMouse(true)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints(c)
    DUI.Style.CropIcon(c.icon)
    c.mark = c:CreateTexture(nil, "OVERLAY")
    c.mark:SetSize(8, 8)
    c.mark:SetPoint("TOPRIGHT", c, "TOPRIGHT", 2, 2)
    W().TintDaylight(c.mark)
    c:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and self.id then Ed.StartTrayDrag(self.id, Ed.Cursor()) end
    end)
    c:SetScript("OnMouseUp", function()
        if drag then Ed.Drop(ui.tray:IsMouseOver()) end
    end)
    c:SetScript("OnEnter", function(self)
        if drag or not self.e then return end
        local e = self.e
        local what = e.aura and L["Buff or debuff"] or L["Cooldown"]
        local shape = e.custom and L["Pick an icon or a bar."]
            or e.kind == "bar" and L["The game shows it as a bar."] or L["The game shows it as an icon."]
        local how = e.placed and attach and L["In your layout: click to move it here."]
            or e.placed and L["In your layout: click to pick it."]
            or e.unlearned and L["Not known right now (other talents). It shows once you have it."]
            or L["Click to add it, or drag it up onto the screen."]
        W().Tooltip(self, e.name ~= "" and e.name or L["Unknown spell"], what .. ". " .. shape .. "\n" .. how)
    end)
    c:SetScript("OnLeave", function() W().HideTooltip() end)
    ui.cells[i] = c
    return c
end

-- Sizes the tray and its spells by trayGrow; a waiting + eases them bigger.
local function layTray()
    local size = floor(Ed.CELL + (Ed.CELL_BIG - Ed.CELL) * trayGrow + 0.5)
    local cols, step = Ed.TRAY_COLS, size + Ed.CELL_GAP
    for n, c in ipairs(ui.cells) do
        if c.id ~= nil then
            c:SetSize(size, size)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", ui.tray, "TOPLEFT", 12 + ((n - 1) % cols) * step, -46 - floor((n - 1) / cols) * step)
        end
    end
    ui.tray:SetWidth(24 + cols * step - Ed.CELL_GAP)
    ui.tray:SetHeight(46 + ui.tray.shownLines * step + 8)
    placeTray()
end

local function drawTray()
    local list = {}
    for _, e in ipairs(Ed.Spells()) do
        if query == "" or string.find(string.lower(e.name), query, 1, true) then list[#list + 1] = e end
    end
    local cols = Ed.TRAY_COLS
    local lines = max(1, math.ceil(#list / cols))
    trayTop = max(0, min(trayTop, lines - Ed.TRAY_LINES))
    local shownLines = min(lines, Ed.TRAY_LINES)
    local first = trayTop * cols + 1
    local n = 0
    for i = first, min(#list, first + shownLines * cols - 1) do
        n = n + 1
        local e, c = list[i], cellFor(n)
        c.id, c.e = e.id, e
        c.icon:SetTexture(Ed.SpellTexture(e.id))
        c.icon:SetDesaturated(e.unlearned == true)
        c:SetAlpha((e.placed or e.unlearned) and 0.45 or 1)
        c.mark:SetShown(e.placed)
        c:Show()
    end
    for i = n + 1, #ui.cells do ui.cells[i]:Hide(); ui.cells[i].id, ui.cells[i].e = nil, nil end
    ui.empty:SetShown(#list == 0)
    ui.tray.lines, ui.tray.shownLines = lines, shownLines
    local goal = attach and 1 or 0
    if goal ~= ui.tray.growTo then
        ui.tray.growTo = goal
        DUI.Motion.Tween("cdmTrayGrow", trayGrow, goal, DUI.Motion.NORMAL, function(k)
            trayGrow = k
            layTray()
        end)
    else
        layTray()
    end
    ui.unlearned.SetActive(showUnlearned)
    ui.group.SetActive(showGroup)
    ui.tray.glow(attach ~= nil)
end

local function drawChooser()
    local p = pending
    ui.chooser:SetShown(p ~= nil)
    if not p then return end
    DUI.Style.InkText(ui.chooser.ask, "pop")   -- accent, read when it shows
    ui.chooser.icon:SetTexture(Ed.SpellTexture(p.id))
    ui.chooser.title:SetText(Ed.SpellName(p.id) or L["Unknown spell"])
    ui.chooser.icon_.text:SetText(p.kind == "icon" and L["Icon (the game's)"] or L["Icon"])
    ui.chooser.bar.text:SetText(p.kind == "bar" and L["Bar (the game's)"] or L["Bar"])
    local x, y = p.ax, p.ay
    local w, h = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    x = max(-w + 130, min(x, w - 130))
    y = max(-h + 150, min(y, h - 20))
    ui.chooser:ClearAllPoints()
    ui.chooser:SetPoint("TOP", ui.overlay, "CENTER", x, y - 14)
end

-- The outline around the picked spell's group, Ed.GROUP_PAD px out from its spells.
-- Only shown for a group of 2+, easing in and out.
Ed.GROUP_PAD = 4
local function drawGroup(set, boxes)
    local grp = ui.groupLine
    local list = selected ~= nil and set.pieces[selected] and Data.Subtree(set, Data.Root(set, selected))
    local l, t, r, b
    if list and #list > 1 then
        for _, q in ipairs(list) do
            local c = boxes[q]
            if c and c.w > 0 and c.h > 0 then
                l = l and min(l, c.x) or c.x
                r = r and max(r, c.x + c.w) or c.x + c.w
                t = t and max(t, c.y) or c.y
                b = b and min(b, c.y - c.h) or c.y - c.h
            end
        end
    end
    if not l then
        if grp:IsShown() then DUI.Motion.AlphaTo(grp, 0, DUI.Motion.FAST, true) end
        return
    end
    local pad = Ed.GROUP_PAD
    placePiece(grp, { x = l - pad, y = t + pad, w = r - l + 2 * pad, h = t - b + 2 * pad })
    grp.lit(true)
    if not grp:IsShown() or grp:GetAlpha() < 1 then
        if not grp:IsShown() then grp:SetAlpha(0); grp:Show() end
        DUI.Motion.AlphaTo(grp, 1, DUI.Motion.FAST)
    end
end
function Ed.GroupOutline() return ui and ui.groupLine end

local function drawPieces()
    local set = Ed.Set()
    local boxes = Data.Layout(set)
    for id, f in pairs(ui.pieces) do
        if not set.pieces[id] then f:Hide() end
    end
    for id, b in pairs(boxes) do
        local f = previewFor(id)
        paintPiece(f, set, id, b)
        placePiece(f, b)
        f.lit(selected == id)
        f:SetAlpha(drag and drag.mine and drag.mine[id] and 0.8 or 1)
        f:Show()
        if ui.born == id then DUI.Motion.Pop(f) end
    end
    -- Hooked on a drop: the chain glides the rest of the way.
    local g = ui.glide
    if g and ui.from and boxes[g] then
        local set0, dx, dy = set, ui.from[1] - boxes[g].x, ui.from[2] - boxes[g].y
        local part = Data.Subtree(set0, g)
        DUI.Motion.Tween("cdmEditorGlide", 1, 0, DUI.Motion.FAST, function(t)
            for _, q in ipairs(part) do
                local qf, qb = ui.pieces[q], boxes[q]
                if qf and qb then placePiece(qf, { x = qb.x + dx * t, y = qb.y + dy * t, w = qb.w, h = qb.h }) end
            end
        end)
    end
    ui.glide, ui.from, ui.born = nil, nil, nil
    drawGroup(set, boxes)
    -- A tray spell on its way up: its icon follows the cursor.
    local carry = drag and drag.tray and drag.moved
    ui.carry:SetShown(carry and true or false)
    -- While a piece moves, the tray, title and banner go see-through so a piece
    -- passing under them still shows.
    local a = drag and drag.moved and not drag.tray and Ed.FADED or 1
    ui.tray:SetAlpha(a); ui.pill:SetAlpha(a); ui.banner:SetAlpha(a)
    if carry then
        ui.carry.icon:SetTexture(Ed.SpellTexture(drag.id))
        ui.carry:ClearAllPoints()
        ui.carry:SetPoint("CENTER", ui.overlay, "CENTER", drag.cx, drag.cy)
    end
    drawPlus(set)
    return set
end

function Ed.DrawPieces()
    if ui and isOpen then drawPieces() end
end

-- Redraws everything. A drag only redraws the pieces (Ed.DrawPieces).
function Ed.Draw()
    if not (ui and isOpen) then return end
    local set = drawPieces()
    drawBanner(set)
    drawPill()
    drawTray()
    drawChooser()
    tickSamples()
    ns.CdmCard.Draw()
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

-- Arrow keys nudge the picked chain one step (Shift: one grid step).
local ARROWS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

local function onKey(self, key)
    if InCombatLockdown() then return end
    local arrow = ARROWS[key] and selected ~= nil and not drag and not pending and ARROWS[key]
    local mine = key == "ESCAPE" or key == "DELETE" or key == "BACKSPACE" or arrow and true or false
    self:SetPropagateKeyboardInput(not mine)
    if arrow then
        local step = shiftDown() and DUI.Movers.GRID or 1
        Ed.Nudge(arrow[1] * step, arrow[2] * step)
        return
    end
    if key == "ESCAPE" then
        if drag then
            drag = nil
            DUI.Movers.ShowGuides(nil, nil)
            Ed.Draw()
        elseif pending then Ed.CancelPick()
        elseif attach then Ed.SetAttach(nil)
        elseif selected then Ed.Select(nil)
        else Ed.Close() end
    elseif mine and selected and not drag then
        Ed.Remove(selected)
    end
end

local function pillButton(parent, text, onClick)
    local b = W().Button(parent, text, 26)
    b.FitWidth(90)
    b:SetScript("OnClick", onClick)
    return b
end

function build()
    ui = { pieces = {}, cells = {}, plus = {} }
    local o = CreateFrame("Frame", "DaylightUICdmEditor", UIParent)
    o:SetAllPoints(UIParent)
    o:SetFrameStrata("DIALOG")
    o:EnableMouse(true)
    o:EnableKeyboard(true)
    o:SetPropagateKeyboardInput(true)
    o:SetScript("OnKeyDown", onKey)
    o:Hide()
    ui.overlay = o
    local dim = o:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(o)
    dim:SetColorTexture(0, 0, 0, 0.25)
    -- A click on empty space clears the selection.
    o:SetScript("OnMouseDown", function()
        pending, attach = nil, nil
        Ed.Select(nil)
    end)
    -- The drag follows the cursor. A release the piece didn't catch (off the
    -- screen's edge) ends it.
    local acc = 0
    o:SetScript("OnUpdate", function(_, elapsed)
        if trayMove then
            if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
                Ed.EndTrayMove()
            else
                Ed.MoveTray(Ed.Cursor())
            end
        end
        if drag then
            if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
                Ed.Drop(drag.tray and ui.tray:IsMouseOver())
            else
                Ed.DragTo(Ed.Cursor())
            end
        end
        acc = acc + (elapsed or 0)
        if acc >= Ed.TICK then
            acc = 0
            if live then tickSamples() end
        end
    end)

    -- Top: title, talent set, Live preview, Done.
    local pill = CreateFrame("Frame", nil, o)
    pill:SetFrameLevel(o:GetFrameLevel() + 30)
    pill:SetHeight(42)
    pill:SetPoint("TOP", o, "TOP", 0, -16)
    pill:EnableMouse(true)
    DUI.Style.Shell(pill, {})
    local title = DUI.Style.Text(pill, DUI.Style.SIZE.title, "LEFT")
    title:SetPoint("LEFT", pill, "LEFT", 14, 0)
    title:SetText(L["Cooldown layout"])
    ui.set = pillButton(pill, "", function()
        local g = Ed.Group() % Data.SETS + 1
        Ed.SetGroup(g)
    end)
    ui.set:SetPoint("LEFT", title, "RIGHT", 14, 0)
    -- Import turns a game Cooldown Manager string into a new profile for this talent
    -- set. Reset empties the profile in use, with a confirm.
    ui.import = pillButton(pill, L["Import"], function()
        ns.CdmImport.Open(Ed.Group(), function() Ed.SetGroup(Ed.Group()) end)
    end)
    ui.import:SetPoint("LEFT", ui.set, "RIGHT", 8, 0)
    ui.reset = pillButton(pill, RESET or L["Reset"], nil)
    W().Confirm(ui.reset, RESET or L["Reset"], function() Ed.Reset() end)
    ui.reset:SetPoint("LEFT", ui.import, "RIGHT", 8, 0)
    ui.live = pillButton(pill, L["Live preview"], function() Ed.SetLive(not live) end)
    ui.live:SetPoint("LEFT", ui.reset, "RIGHT", 8, 0)
    -- Unlock mode's grid and magnet toggles (the same settings).
    ui.snap, ui.mag = DUI.Movers.SnapButtons(pill, 26, 90)
    ui.snap:SetPoint("LEFT", ui.live, "RIGHT", 8, 0)
    ui.mag:SetPoint("LEFT", ui.snap, "RIGHT", 8, 0)
    ui.done = pillButton(pill, DONE or L["Done"], Ed.Close)
    ui.done:SetPoint("LEFT", ui.mag, "RIGHT", 8, 0)
    ui.done.SetActive(true)
    ui.pill = pill
    local function fitPill()
        local tw = title:GetStringWidth()
        if type(tw) ~= "number" then tw = 120 end
        pill:SetWidth(14 + tw + 14 + ui.set:GetWidth() + 8 + ui.import:GetWidth() + 8 + ui.reset:GetWidth() + 8 + ui.live:GetWidth()
            + 8 + ui.snap:GetWidth() + 8 + ui.mag:GetWidth() + 8 + ui.done:GetWidth() + 14)
    end
    ui.fitPill = fitPill

    -- Below it: what to do now.
    local banner = CreateFrame("Frame", nil, o)
    banner:SetFrameLevel(o:GetFrameLevel() + 30)
    banner:SetHeight(26)
    banner:SetPoint("TOP", pill, "BOTTOM", 0, -8)
    DUI.Style.Shell(banner, { bgAlpha = 0.7 })
    banner.text = DUI.Style.Text(banner, DUI.Style.SIZE.small, "CENTER")
    banner.text:SetPoint("CENTER", banner, "CENTER", 0, 0)
    ui.banner = banner

    -- Bottom: the spell tray.
    local step = Ed.CELL + Ed.CELL_GAP
    local tray = CreateFrame("Frame", nil, o)
    tray:SetFrameLevel(o:GetFrameLevel() + 30)
    tray:SetWidth(24 + Ed.TRAY_COLS * step - Ed.CELL_GAP)
    tray:SetPoint("BOTTOM", o, "BOTTOM", 0, Ed.TRAY_EDGE)
    tray:EnableMouse(true)
    tray:EnableMouseWheel(true)
    tray:SetScript("OnMouseWheel", function(_, delta)
        trayTop = trayTop - delta
        Ed.Draw()
    end)
    -- Any empty spot drags the tray (spells, search and buttons take their own
    -- presses). The move cursor shows it.
    tray:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then Ed.StartTrayMove(Ed.Cursor()) end
    end)
    tray:SetScript("OnMouseUp", function() Ed.EndTrayMove() end)
    tray:SetScript("OnEnter", function() if type(SetCursor) == "function" then SetCursor("UI_MOVE_CURSOR") end end)
    tray:SetScript("OnLeave", function() if type(ResetCursor) == "function" then ResetCursor() end end)
    DUI.Style.Shell(tray, {})
    tray.glow = outline(tray, 2)
    -- A grip on its top edge, like a drawer handle.
    local grip = tray:CreateTexture(nil, "OVERLAY")
    grip:SetSize(36, 3)
    grip:SetPoint("TOP", tray, "TOP", 0, -4)
    W().Tint(grip, C().faint)
    ui.tray = tray
    local box = W().Input(tray, { search = true, hint = SEARCH or L["Search"],
        onChange = function(text) Ed.SetQuery(text) end })
    box:SetPoint("TOPLEFT", tray, "TOPLEFT", 12, -10)
    box:SetWidth(160)
    ui.search = box
    ui.unlearned = pillButton(tray, L["Other talents"], function() Ed.SetShowUnlearned(not showUnlearned) end)
    ui.unlearned:SetHeight(26)
    ui.unlearned:SetPoint("LEFT", box, "RIGHT", 8, 0)
    ui.group = pillButton(tray, L["Group buffs"], function() Ed.SetShowGroup(not showGroup) end)
    ui.group:SetHeight(26)
    ui.group:SetPoint("LEFT", ui.unlearned, "RIGHT", 8, 0)
    -- A spell or item the tray doesn't list, added by ID.
    ui.byID = pillButton(tray, L["Add by ID"], function(self) Ed.OpenAddMenu(self) end)
    ui.byID:SetHeight(26)
    ui.byID:SetPoint("LEFT", ui.group, "RIGHT", 8, 0)
    local hint = W().Font(tray, W().BODY, DUI.Style.SIZE.small, DUI.Style.INK.LABEL, "RIGHT")
    hint:SetPoint("RIGHT", tray, "TOPRIGHT", -14, -23)
    hint:SetText(L["Click or drag a spell."])
    ui.empty = W().Font(tray, W().BODY, DUI.Style.SIZE.body, DUI.Style.INK.LABEL, "LEFT")
    ui.empty:SetPoint("TOPLEFT", tray, "TOPLEFT", 14, -52)
    ui.empty:SetText(L["No spells match. The Cooldown Manager lists what your class tracks."])

    -- The + buttons on the selected piece (removing it is on its card).
    for _, side in ipairs(Data.SIDES) do
        local b = W().Button(o, "+", 22)
        b:SetWidth(22)
        b:SetFrameLevel(o:GetFrameLevel() + 20)
        b:SetScript("OnClick", function() Ed.SetAttach(selected, side) end)
        b:Hide()
        ui.plus[side] = b
    end
    -- A tray spell being carried.
    local carry = CreateFrame("Frame", nil, o)
    carry:SetFrameLevel(o:GetFrameLevel() + 40)
    carry:SetSize(Data.LOOK.size, Data.LOOK.size)
    carry.icon = carry:CreateTexture(nil, "ARTWORK")
    carry.icon:SetAllPoints(carry)
    DUI.Style.CropIcon(carry.icon)
    carry:SetAlpha(0.85)
    carry:Hide()
    ui.carry = carry
    -- The picked spell's whole group, outlined in the accent (2+ spells).
    local grp = CreateFrame("Frame", nil, o)
    grp:SetFrameLevel(o:GetFrameLevel() + 2)
    grp.lit = outline(grp, 2)
    grp:Hide()
    ui.groupLine = grp

    -- The Icon / Bar chooser.
    local ch = CreateFrame("Frame", nil, o)
    ch:SetFrameStrata("FULLSCREEN_DIALOG")
    ch:SetSize(240, 96)
    ch:EnableMouse(true)
    DUI.Style.Shell(ch, {})
    ch.icon = ch:CreateTexture(nil, "ARTWORK")
    ch.icon:SetSize(24, 24)
    ch.icon:SetPoint("TOPLEFT", ch, "TOPLEFT", 12, -12)
    DUI.Style.CropIcon(ch.icon)
    ch.title = DUI.Style.Text(ch, DUI.Style.SIZE.head, "LEFT")
    ch.title:SetPoint("LEFT", ch.icon, "RIGHT", 8, 0)
    ch.title:SetPoint("RIGHT", ch, "RIGHT", -12, 0)
    local ask = W().Font(ch, W().BODY, DUI.Style.SIZE.small, DUI.Style.INK.LABEL, "LEFT")
    ch.ask = ask
    ask:SetPoint("TOPLEFT", ch.icon, "BOTTOMLEFT", 0, -6)
    ask:SetText(L["How should it look?"])
    ch.icon_ = W().Button(ch, L["Icon"], 26)
    ch.icon_:SetPoint("BOTTOMLEFT", ch, "BOTTOMLEFT", 12, 10)
    ch.icon_:SetWidth(104)
    ch.icon_:SetScript("OnClick", function() Ed.Pick("icon") end)
    ch.bar = W().Button(ch, L["Bar"], 26)
    ch.bar:SetPoint("BOTTOMRIGHT", ch, "BOTTOMRIGHT", -12, 10)
    ch.bar:SetWidth(104)
    ch.bar:SetScript("OnClick", function() Ed.Pick("bar") end)
    ch:Hide()
    ui.chooser = ch

    fitPill()
end

-- ---------------------------------------------------------------------
-- Opening it: /cdm, /dui cdm, the options page
-- ---------------------------------------------------------------------

-- /cdm opens this editor instead of the game's Cooldown Manager settings. Whatever
-- command owns "/cdm" gets its handler swapped, and the chat box's lookup cache is
-- pointed at ours too. Skipped while the module is switched off; the core's login
-- handler (which enables the modules) runs first.
local function takeOverSlash()
    if not ns.Cooldowns.enabled then return end
    local open = function() Ed.Open() end
    for key in pairs(SlashCmdList) do
        for i = 1, 9 do
            local s = _G["SLASH_" .. key .. i]
            if type(s) ~= "string" then break end
            if string.lower(s) == "/cdm" then SlashCmdList[key] = open end
        end
    end
    if type(hash_SlashCmdList) == "table" then hash_SlashCmdList["/CDM"] = open end
    if not SlashCmdList.DAYLIGHTUICDM then
        SLASH_DAYLIGHTUICDM1 = "/cdm"
        SlashCmdList.DAYLIGHTUICDM = open
    end
end

DUI.RegisterEvent("PLAYER_LOGIN", takeOverSlash)
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if not isOpen then return end
    Ed.Close()
    DUI.Print(L["Cooldown layout closed for combat."])
end)
DUI.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function()
    if not isOpen then return end
    Data.SetViewing(nil)
    selected, attach, pending = nil, nil, nil
    Ed.Draw()
end)
DUI.RegisterEvent("SPELLS_CHANGED", function() Ed.Draw() end)
DUI.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() if isOpen then Ed.Draw() end end)
DUI.On("StyleChanged", function() Ed.Draw() end)
