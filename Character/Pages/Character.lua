-- The Character page: the slots in two columns
-- round the model, the weapons underneath, the stats on the right in a
-- slightly darker inset, and the footer (your item level, durability, the
-- equipment sets button).

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char
local L = DUI.L
local Style = DUI.Style

local CharacterPage = {}
ns.CharacterPage = CharacterPage

CharacterPage.EDGE = 16
CharacterPage.TOP = 12          -- under the header
CharacterPage.ROW = 58          -- slot to slot
CharacterPage.COL = 200         -- a slot column with names (snug to the model: the names sit close in)
CharacterPage.GAP = 8
CharacterPage.WEAPON_W = 190    -- a weapon slot with names (the row sits centered)
CharacterPage.ICON_GAP = 12     -- icons only: icon column to model
CharacterPage.STATS_W = 280         -- wide enough for most stat names beside their values in the longer languages
CharacterPage.STATS_PAD = 10
CharacterPage.FOOTER = 36
CharacterPage.FOOT_LIFT = 8     -- the footer up off the window's bottom edge, like the other windows' footers
CharacterPage.STAT_ROW = 24        -- a stat's least height; a name that wraps makes its row taller
CharacterPage.STAT_PAD = 3      -- above and under a name that wraps
CharacterPage.STAT_GAP = 10     -- between a stat's name and its value
CharacterPage.STAT_SECRET_W = 56  -- the room kept for a value that can't be measured
CharacterPage.STAT_INSET = 5    -- a stat's words in from its stripe's edges
CharacterPage.GROUP_HEAD = 26
CharacterPage.GROUP_GAP = 6
CharacterPage.LINE_ALPHA = 0.85 -- the line under a group's header
CharacterPage.WHEEL = 30        -- px per wheel notch in the stats
CharacterPage.STAT_SIZE, CharacterPage.GROUP_SIZE, CharacterPage.FOOT_SIZE = Style.SIZE.body, Style.SIZE.head, Style.SIZE.small
CharacterPage.INSET = { 0, 0, 0, 0.22 }
CharacterPage.LABEL = Style.INK.LABEL   -- a stat's name
CharacterPage.DIM = Style.INK.LABEL     -- the fold +/-, the footer's words
CharacterPage.VALUE = Style.INK.VALUE   -- a stat's plain value
CharacterPage.UP, CharacterPage.DOWN = { 0.45, 0.9, 0.45 }, { 1, 0.4, 0.4 }
CharacterPage.STALE = Style.INK.OFF    -- a value not read yet
-- The game's stat tooltips repainted in Daylight UI colors (StatText.Restyle).
CharacterPage.TIP = { title = Style.INK.VALUE, body = Style.INK.TEXT, value = "pop", up = CharacterPage.UP, down = CharacterPage.DOWN }

-- Where everything goes, as { x, y (down is negative), w, h } from the
-- page's top left. ammo: the room the small ammo slot takes beside the
-- ranged icon (0 or nil without): icons only keeps the row centered, with
-- names the row makes room for it.
-- Pure: tested without frames.
function CharacterPage.Rects(width, height, names, ammo)
    local E, T, G = CharacterPage.EDGE, CharacterPage.TOP, CharacterPage.GAP
    local icon = ns.Slots.ICON
    local col = names and CharacterPage.COL or icon
    local gap = names and G or CharacterPage.ICON_GAP
    local bodyH = height - CharacterPage.FOOTER - CharacterPage.FOOT_LIFT
    local statsX = width - E - CharacterPage.STATS_W
    local R = {}
    R.stats = { x = statsX, y = -T, w = CharacterPage.STATS_W, h = bodyH - T - 4 }
    R.left = { x = E, y = -T, w = col }
    R.right = { x = statsX - gap - col, y = -T, w = col }
    local modelX = E + col + gap
    local slotsH = 8 * CharacterPage.ROW
    R.model = { x = modelX, y = -T, w = R.right.x - gap - modelX, h = slotsH - (CharacterPage.ROW - icon) }
    local rowY = -T - slotsH
    R.bottom = {}
    local n = #ns.Gear.BOTTOM
    if names then
        -- The icons centered under the model (the middle one at its center,
        -- the others evenly either side), in from the side columns: the main
        -- hand doesn't line up under the armor. The last one's words stop at
        -- the right column's edge.
        -- With the ammo beside Ranged (the last), the row slides left by its
        -- room so Ranged's words get as much space as the others'.
        local room = ammo or 0
        local span = R.right.x + col - E
        local w = math.min(CharacterPage.WEAPON_W, math.floor((span - (n - 1) * G - room) / n))
        local mid = E + math.floor(span / 2) - math.floor(icon / 2) - room
        for i = 1, n do
            local x = mid + math.floor((i - (n + 1) / 2) * (w + G))
            local want = i == n and w + room or w
            R.bottom[i] = { x = x, y = rowY, w = math.min(want, E + span - x) }
        end
    else
        local rowW = n * icon + (n - 1) * gap + (ammo or 0)
        local x0 = R.model.x + math.floor((R.model.w - rowW) / 2)
        for i = 1, n do R.bottom[i] = { x = x0 + (i - 1) * (icon + gap), y = rowY, w = icon } end
    end
    R.footer = { x = E, y = -bodyH, w = width - 2 * E, h = CharacterPage.FOOTER }
    return R
end

local function put(page, f, r)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", page, "TOPLEFT", r.x, r.y)
    if r.w then f:SetWidth(r.w) end
    if r.h then f:SetHeight(r.h) end
end

function CharacterPage.Place(page)
    local names = ns.Setting("names") ~= false

    local Slots, Gear = ns.Slots, ns.Gear
    page.usesAmmo = Gear.UsesAmmo()
    local room = page.usesAmmo and Slots.AmmoRoom() or 0
    local R = CharacterPage.Rects(ns.Window.Width(), ns.Window.H - ns.Window.HEADER, names, room)
    for i, key in ipairs(Gear.LEFT) do
        Slots.Layout(page.slots[key], R.left.w, names)
        put(page, page.slots[key], { x = R.left.x, y = R.left.y - (i - 1) * CharacterPage.ROW })
    end
    for i, key in ipairs(Gear.RIGHT) do
        Slots.Layout(page.slots[key], R.right.w, names)
        put(page, page.slots[key], { x = R.right.x, y = R.right.y - (i - 1) * CharacterPage.ROW })
    end
    for i, key in ipairs(Gear.BOTTOM) do
        local r = R.bottom[i]
        Slots.Layout(page.slots[key], r.w, names, key == "Ranged" and room or 0)
        put(page, page.slots[key], { x = r.x, y = r.y })
    end
    -- The ammo: small, right beside the ranged icon, as in the game's window.
    local ammo = page.slots.Ammo
    ammo:SetShown(page.usesAmmo)
    Slots.Layout(ammo, Slots.AMMO, false)
    ammo:ClearAllPoints()
    ammo:SetPoint("LEFT", page.slots.Ranged.icon, "RIGHT", Slots.AMMO_GAP, 0)
    put(page, page.model, R.model)
    ns.Model.Spread(R.model.x - R.left.x)   -- the model's box out under the slot columns
    put(page, page.stats, R.stats)
    page.stats.content:SetWidth(CharacterPage.STATS_W - 2 * CharacterPage.STATS_PAD)
    put(page, page.foot, R.footer)
end

-- ---------------------------------------------------------------------
-- The stats pane
-- ---------------------------------------------------------------------

local function groupHead(content, group)
    local head = CreateFrame("Button", nil, content)
    head.group = group
    head.text = Style.Text(head, CharacterPage.GROUP_SIZE, "LEFT")
    head.text:SetPoint("LEFT", head, "LEFT", 0, 0)
    head.state = Style.Text(head, CharacterPage.GROUP_SIZE, "RIGHT")   -- "+" while folded
    head.state:SetPoint("RIGHT", head, "RIGHT", 0, 0)
    head.state:SetTextColor(CharacterPage.DIM[1], CharacterPage.DIM[2], CharacterPage.DIM[3])
    -- White, so the line's color (ns.Colors.Line) is all its own.
    head.line = head:CreateTexture(nil, "ARTWORK")
    head.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    head.line:SetHeight(1)
    head.line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
    head.line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
    head:SetScript("OnClick", function(self) CharacterPage.ToggleGroup(self.group) end)
    return head
end

-- On a controller the game shows no tooltip of its own on these stops: a slot
-- is a plain frame (the game's button over its icon is skipped) and a stat row
-- is a plain frame too. So they show it when the D-pad lands on them, as the
-- options window's rows do (the game calls OnSmartNavSelect/Deselect).
local function hideTip()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

-- The slot's tooltip the way the game's own slot button shows it.
function CharacterPage.SlotTip(h)
    local id = h and ns.Gear.SlotId(h.key)
    if not id or type(GameTooltip) ~= "table" then return end
    local at = h.icon or h
    GameTooltip:SetOwner(at, "ANCHOR_RIGHT")
    if type(ItemUtil) == "table" and type(ItemUtil.DisplayEquipSlotTooltip) == "function" then
        ItemUtil.DisplayEquipSlotTooltip(at, GameTooltip, id, true)
    elseif not GameTooltip:SetInventoryItem("player", id) then
        GameTooltip:SetOwner(at, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.Gear.LABEL[h.key] or h.key)
        GameTooltip:Show()
    end
end

function CharacterPage.PadSlot(h)
    h.OnSmartNavSelect = function(self)
        self.ring:Show()
        CharacterPage.SlotTip(self)
    end
    h.OnSmartNavDeselect = function(self)
        self.ring:SetShown(self.over == true)
        hideTip()
    end
end

-- A plain frame is no stop for the D-pad until the game's own setter marks
-- it, which waits for the controller code to load and for a fight to end.
local padWaiting = setmetatable({}, { __mode = "k" })
function CharacterPage.PadStop(r)
    if type(SmartNavigation_MarkFrameFocusable) ~= "function" then
        padWaiting[r] = true
        return
    end
    padWaiting[r] = nil
    DUI.AfterCombat(function() SmartNavigation_MarkFrameFocusable(r) end, r)
end
DUI.On("PadChanged", function()
    for r in pairs(padWaiting) do CharacterPage.PadStop(r) end
end)

local function statRow(content, pool, i)
    if pool[i] then return pool[i] end
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(CharacterPage.STAT_ROW)
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:Hide()
    local inset = CharacterPage.STAT_INSET
    r.label = Style.Text(r, CharacterPage.STAT_SIZE, "LEFT")
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", inset, 0)
    r.label:SetWordWrap(true)   -- a long name wraps under itself rather than running under its value
    r.label:SetTextColor(CharacterPage.LABEL[1], CharacterPage.LABEL[2], CharacterPage.LABEL[3])
    r.value = Style.Text(r, CharacterPage.STAT_SIZE, "RIGHT")
    r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", -inset, 0)
    r.value:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetScript("OnEnter", CharacterPage.StatTip)
    r:SetScript("OnLeave", hideTip)
    r.OnSmartNavSelect = CharacterPage.StatTip
    r.OnSmartNavDeselect = hideTip
    CharacterPage.PadStop(r)
    pool[i] = r
    return r
end

-- groups: the stat groups it lists (default yours, ns.Stats.GROUPS; the
-- Pet page passes ns.Stats.PET_GROUPS).
function CharacterPage.BuildStats(page, groups)
    local pane = CreateFrame("Frame", nil, page)
    pane.list = groups or ns.Stats.GROUPS
    pane.bg = pane:CreateTexture(nil, "BACKGROUND")
    pane.bg:SetAllPoints()
    pane.bg:SetColorTexture(CharacterPage.INSET[1], CharacterPage.INSET[2], CharacterPage.INSET[3], CharacterPage.INSET[4])
    local P = CharacterPage.STATS_PAD
    pane.scroll = CreateFrame("ScrollFrame", nil, pane)
    pane.scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", P, -P)
    pane.scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -P, P)
    pane.content = CreateFrame("Frame", nil, pane.scroll)
    pane.content:SetSize(CharacterPage.STATS_W - 2 * P, 1)
    pane.scroll:SetScrollChild(pane.content)
    pane.bar = DUI.Widgets.Scroll(pane.scroll, { x = (P - DUI.Widgets.SCROLL.width) / 2, step = CharacterPage.WHEEL, whole = true })
    pane.groups = {}
    for _, g in ipairs(pane.list) do pane.groups[g] = { head = groupHead(pane.content, g), rows = {} } end
    return pane
end

-- A text's measure, or nil: in a fight a stat's value is a secret, and so is its measure; a secret
-- number can't be compared or worked on (and measuring may error), so it is never used.
local isSecret = DUI.IsSecret
local function measure(fs, what)
    local ok, v = pcall(fs[what], fs)
    if ok and type(v) == "number" and not isSecret(v) then return v end
    return nil
end

-- A text's height, or a guess from its size when the client has not measured it (or it is secret).
local function tall(fs, size)
    local h = measure(fs, "GetStringHeight")
    if h and h > 0 then return h end
    return size + 2
end

-- One stat's row, once its name and value are set: the name gets the room the value
-- leaves and wraps when it needs more; the row is as tall as its lines, and a row of
-- one line has them in the middle. Returns the row's height.
function CharacterPage.FitStat(r, w)
    local inset, size = CharacterPage.STAT_INSET, CharacterPage.STAT_SIZE
    -- A value that cannot be measured (secret, in a fight) keeps the width it last had, or a usual one.
    local vw = measure(r.value, "GetStringWidth")
    if vw then r.valueW = vw else vw = r.valueW or CharacterPage.STAT_SECRET_W end
    local indent = r.row and r.row.indent and ns.List.INDENT or 0
    local room = math.max(20, w - 2 * inset - indent - vw - CharacterPage.STAT_GAP)
    r.label:SetWidth(room)
    local lh, vh = tall(r.label, size), tall(r.value, size)
    local h = math.max(CharacterPage.STAT_ROW, math.ceil(lh) + 2 * CharacterPage.STAT_PAD)
    local wrapped = lh > vh * 1.5   -- the name takes more lines than the value does
    r.label:ClearAllPoints()
    r.value:ClearAllPoints()
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", inset + indent, -(wrapped and CharacterPage.STAT_PAD or math.floor((h - lh) / 2)))
    r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", -inset, -(wrapped and CharacterPage.STAT_PAD or math.floor((h - vh) / 2)))
    r:SetHeight(h)
    return h
end

-- A folded group's rows fade out where they were while the rest glides up.
function CharacterPage.FadeOut(r)
    r.closing = true
    DUI.Motion.Tween(r, 1, 0, DUI.Motion.FAST,
        function(a) if r.closing then r:SetAlpha(a) end end,
        function() if r.closing then r.closing = nil; r:Hide(); r:SetAlpha(1) end end)
end

function CharacterPage.RefreshStats(page)
    local pane = page.stats
    local cfg = ns.module and ns.module.db or {}
    local _, class = UnitClass("player")
    local role, folds = ns.Stats.Role(), ns.Stats.Folds(cfg)
    local w = CharacterPage.STATS_W - 2 * CharacterPage.STATS_PAD
    local Motion, List = DUI.Motion, ns.List
    local fold = CharacterPage.fold   -- the group just clicked: this redraw moves
    CharacterPage.fold = nil
    local y = 0
    for _, g in ipairs(pane.list) do
        local G = pane.groups[g]
        local open = ns.Stats.IsOpen(cfg, folds, g, class, role)
        G.head:ClearAllPoints()
        G.head:SetPoint("TOPLEFT", pane.content, "TOPLEFT", 0, -y)
        G.head:SetSize(w, CharacterPage.GROUP_HEAD)
        if fold and G.y and G.y ~= y then
            Motion.Settle(G.head)
            Motion.Glide(G.head, 0, y - G.y)
        end
        G.y = y
        ns.Colors.HeadText(G.head.text, ns.Stats.COLOR[g] or g, DUI.Style.Upper(ns.Stats.LABEL[g]))
        ns.Colors.Line(G.head.line, CharacterPage.LINE_ALPHA)
        G.head.state:SetText(open and "" or "+")
        y = y + CharacterPage.GROUP_HEAD + 2
        local rows = ns.Stats.Read(g)
        local n = 0
        for i, row in ipairs(rows) do
            local r = statRow(pane.content, G.rows, i)
            r.row = row
            local was = r:IsShown() and not r.closing and r.y
            if r.closing then r.closing = nil; r:SetAlpha(1) end
            if not open then
                if fold == g and was then CharacterPage.FadeOut(r) else r:Hide() end
            else
                r:Show()
                if fold then
                    Motion.Settle(r)
                    if not was then
                        Motion.SlideIn(r, 0, List.FOLD_DROP, nil, math.min(List.FOLD_STAGGER_MAX, n * List.FOLD_STAGGER))
                        n = n + 1
                    elseif was ~= y then
                        Motion.Glide(r, 0, y - was)
                    end
                end
                r.y = y
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", pane.content, "TOPLEFT", 0, -y)
                r:SetWidth(w)
                ns.Colors.Stripe(r.stripe, i)
                r.label:SetText(row.label)
                ns.Stats.Paint(r.value, row)
                local h = CharacterPage.FitStat(r, w)
                local c = (row.stale and CharacterPage.STALE) or (row.buff == "up" and CharacterPage.UP)
                    or (row.buff == "down" and CharacterPage.DOWN) or nil
                c = c or { Style.Pop() }   -- a plain value pops in the accent (read now)
                r.value:SetTextColor(c[1], c[2], c[3])
                y = y + h
            end
        end
        for i = #rows + 1, #G.rows do G.rows[i]:Hide() end
        y = y + CharacterPage.GROUP_GAP
    end
    pane.content:SetHeight(math.max(y, 1))
end

-- The game's own tooltip, else one plain sentence and, dimmer, where it
-- comes from.
function CharacterPage.StatTip(r)
    if type(GameTooltip) ~= "table" or not (r and r.row) then return end
    if ns.StatText.GameTip(r, r.row, CharacterPage.TIP) then return end
    local say, from = ns.StatText.For(r.row)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")   -- the side the game's own stat tips open on
    GameTooltip:SetText(r.row.label, 1, 1, 1)
    local Tips = DUI.Tips
    Tips.Clear()
    if say then Tips.Text(say) end
    if from then Tips.Sub(from) end
    if not say and (r.row.secret or r.row.stale) then Tips.Hint(L["More after combat."]) end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

-- Remembered per character (learned, not a profile setting).
function CharacterPage.ToggleGroup(group)
    local db = ns.module and ns.module.db
    if not db then return end
    local _, class = UnitClass("player")
    local folds = ns.Stats.Folds(db)
    folds[group] = not ns.Stats.IsOpen(db, folds, group, class, ns.Stats.Role())
    CharacterPage.fold = group
    ns.Window.Refresh()
end

-- ---------------------------------------------------------------------
-- Footer, building, refreshing
-- ---------------------------------------------------------------------

-- The faint rule along the footer's top, as Parts.Footer's.
function CharacterPage.FootLine(foot)
    foot.line = foot:CreateTexture(nil, "ARTWORK")
    foot.line:SetColorTexture(1, 1, 1, 0.06)
    foot.line:SetHeight(1)
    foot.line:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
    foot.line:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
end

function CharacterPage.BuildFooter(page)
    local foot = CreateFrame("Frame", nil, page)
    local D = CharacterPage.DIM
    CharacterPage.FootLine(foot)
    foot.level = Style.Text(foot, CharacterPage.FOOT_SIZE, "LEFT")
    foot.level:SetPoint("LEFT", foot, "LEFT", 0, 0)
    foot.level:SetTextColor(D[1], D[2], D[3])
    -- An upgrade: the item level counts up and a soft light runs over it.
    foot.shine = foot:CreateTexture(nil, "OVERLAY")
    foot.shine:SetTexture(DUI.MEDIA .. "glow.png")
    foot.shine:SetBlendMode("ADD")
    foot.shine:Hide()
    foot.dura = Style.Text(foot, CharacterPage.FOOT_SIZE, "LEFT")
    foot.dura:SetPoint("LEFT", foot.level, "RIGHT", 24, 0)
    foot.dura:SetTextColor(D[1], D[2], D[3])
    foot.ammo = Style.Text(foot, CharacterPage.FOOT_SIZE, "LEFT")   -- how much ammo you carry, beside the durability
    foot.ammo:SetPoint("LEFT", foot.dura, "RIGHT", 24, 0)
    foot.ammo:SetTextColor(D[1], D[2], D[3])
    local sets = DUI.Widgets.Button(foot, L["Equipment sets"], 24)
    sets.FitWidth(124)   -- at least 124, wider when a language's words need it
    sets:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
    foot.ammo:SetPoint("RIGHT", sets, "LEFT", -16, 0)   -- a long ammo name ends in dots before the button
    sets:SetScript("OnClick", function() if ns.Sets then ns.Sets.Toggle() end end)
    foot.sets = sets
    return foot
end

local since = 0
function CharacterPage.OnUpdate(page, elapsed)
    since = since + (elapsed or 0)
    if since < ns.Slots.HOVER_TICK then return end
    since = 0
    ns.Slots.Hover(page)
end

-- ---------------------------------------------------------------------
-- A controller: the game's character window buttons (PaperDollFrame,
-- Camelot): A on a slot opens its swap menu; Y the slot's more actions
-- (place in bags, compare, put on a controller bar, share in chat). Not
-- here: its X (turn and zoom the model with the sticks) and Use (a protected
-- right click).
-- ---------------------------------------------------------------------

local function slotItem(h)
    if type(h) ~= "table" or not h.key or not ns.Gear then return nil end
    local id = ns.Gear.SlotId(h.key)
    local item = id and GetInventoryItemID("player", id)
    return item, id
end

-- A spell waiting for an item target (an enchant, a weapon scroll, a sharpening
-- stone) or the repair cursor.
function CharacterPage.Aiming()
    if type(SpellCanTargetItem) == "function" and SpellCanTargetItem() then return "spell" end
    if type(InRepairMode) == "function" and InRepairMode() then return "repair" end
end

-- A on a Daylight UI slot opens the swap menu, as the game's A does
-- (OpenEquipmentFlyoutForFocusedButton). With a spell or the repair cursor
-- waiting, A is CharacterPage.PadApply instead, so nothing happens here. The
-- mouse never gets here: it clicks the game's own button lent on top of the slot.
local function swapMenu(h)
    if not DUI.Pad.On() or CharacterPage.Aiming() then return end
    local pop = h.button and h.button.popoutButton
    if pop and pop:IsShown() then pop:Click() end
end

-- A with an enchant, a scroll or the repair cursor waiting clicks the game's own
-- slot button through a secure binding, as the game's footer does. Putting a
-- spell on an item is protected: PickupInventoryItem called from addon code is
-- blocked, even inside the player's press.
function CharacterPage.PadApply(f, b)
    if f.current ~= "character" or type(b) ~= "table" or not b.key or ns.Slots.frames[b.key] ~= b then return nil end
    if not CharacterPage.Aiming() or slotItem(b) == nil then return nil end
    local button = b.button
    if type(button) ~= "table" then return nil end
    return { type = "click", clickbutton = button }
end

-- What A says on a slot, as the game's footer: Apply for an enchant, Repair,
-- Select for another spell, nothing on an empty slot while one waits.
function CharacterPage.PadSelect(f, b)
    if f.current ~= "character" or type(b) ~= "table" or not b.key or ns.Slots.frames[b.key] ~= b then return nil end
    local aim = CharacterPage.Aiming()
    if not aim then return nil end
    if slotItem(b) == nil then return false end
    if aim == "repair" then return CONTEXT_ACTION_LABEL_REPAIR or L["Repair"] end
    if ns.Slots.Aimed() == C_Item.DoesItemMatchTargetEnchantingSpell then return CONTEXT_ACTION_LABEL_APPLY or L["Apply"] end
    return nil
end

-- The first slot whose piece the waiting spell can go on: down the left column,
-- then the right, then the weapons.
function CharacterPage.AimedSlot()
    local test = ns.Slots.Aimed()
    if not test then return nil end
    local G = ns.Gear
    for _, list in ipairs({ G.LEFT, G.RIGHT, G.BOTTOM }) do
        for _, key in ipairs(list) do
            local h, id = ns.Slots.frames[key], G.SlotId(key)
            if h and h:IsShown() and id and ns.Slots.Fits(test, id) then return h end
        end
    end
end

-- An enchant picked from the Daylight UI bag on a controller. The game's own bag
-- opens its character window for one (GameEvent.HandleEnchantSpellSelected,
-- when the pick came from a bag and some worn piece takes it), with the D-pad on
-- the gear. The Daylight UI bag uses items by bag and slot, which the game
-- doesn't count as a bag pick, so this window opens itself, on the piece.
function CharacterPage.OpenForEnchant()
    if not DUI.Pad.On() or InCombatLockdown() or not ns.Follow then return false end
    local h = CharacterPage.AimedSlot()
    if not h then return false end
    if not ns.Follow.OpenAlone("character") then return false end
    DUI.Pad.Settle(h)
    return true
end

-- Through Daylight UI's own prompt: the game's bind screen taints the
-- controller when addon code opens it.
function CharacterPage.Bind(item, id)
    local link = GetInventoryItemLink("player", id)
    DUI.Pad.BindAction({ icon = C_Item.GetItemIconByID(item), name = link or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)),
        pickup = function() C_Item.PickupItem(item) end })
end

-- Into the first free slot of a plain bag, as the game's "place in bags"
-- (EquipmentManager_PutItemInInventory). With no room it stays on.
function CharacterPage.Unequip(id)
    if InCombatLockdown() or IsInventoryItemLocked(id) then return false end
    ClearCursor()
    PickupInventoryItem(id)
    if not CursorHasItem() then return false end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if type(free) == "number" and free > 0 and (family or 0) == 0 then
            if bag == 0 then PutItemInBackpack() else PutItemInBag(C_Container.ContainerIDToInventoryID(bag)) end
            return true
        end
    end
    ClearCursor()   -- back on the character
    if UIErrorsFrame and ERR_INV_FULL then UIErrorsFrame:AddMessage(ERR_INV_FULL, 1, 0.1, 0.1) end
    return false
end

function CharacterPage.More(h)
    local item, id = slotItem(h)
    if not item then return end
    local keys = { "unequip", "compare", "bind", "share" }
    local values = {
        unequip = EQUIPMENT_MANAGER_PLACE_IN_BAGS or L["Place in bags"],
        compare = FRAME_ACTION_TOGGLE_ITEM_COMPARE or L["Compare items"],
        bind = CONTEXT_ACTION_LABEL_BIND_TO_GAMEPAD_ACTION_BAR or L["Put on a controller bar"],
        share = SHARE_IN_CHAT or L["Share in chat"],
    }
    DUI.Widgets.OpenMenu(h, keys, values, nil, function(k)
        if k == "unequip" then
            CharacterPage.Unequip(id)
        elseif k == "compare" then
            local on = not CharacterPage.AutoCompare()
            -- The Tooltip module's own switch holds the compare back without Shift.
            if CharacterPage.TipsCompare() then DUI:Set("Tooltip", "compareItems", on) end
            -- A game setting, so it's written out of a fight only.
            if on or not CharacterPage.TipsCompare() then
                DUI.AfterCombat(function() DUI.SafeCall(C_CVar.SetCVar, "alwaysCompareItems", on and "1" or "0") end, "character:compare")
            end
        elseif k == "bind" then
            CharacterPage.Bind(item, id)
        else
            local link = GetInventoryItemLink("player", id)
            if link then DUI.Pad.Share(link, h) end
        end
    end, nil, { checked = function(k) return k == "compare" and CharacterPage.AutoCompare() end })
end

-- Whether the Tooltip module decides the automatic compare (PrettyTooltip off).
function CharacterPage.TipsCompare()
    return DUI:GetModule("Tooltip") ~= nil and not DUI.PrettyAside.Draws()
end

-- Whether an item's tooltip shows what you wear without Shift.
function CharacterPage.AutoCompare()
    if CharacterPage.TipsCompare() and DUI:Get("Tooltip", "compareItems") ~= true then return false end
    return C_CVar.GetCVarBool("alwaysCompareItems") == true
end

function CharacterPage.PadSetup(f)
    f.padKeys = {
        { key = "A", label = function(b) return CharacterPage.PadSelect(f, b) or ACTION_LABEL_SELECT or L["Select"] end,
          secure = function(b) return CharacterPage.PadApply(f, b) end },
        { key = "Y", label = CONTEXT_ACTION_LABEL_MORE_ACTIONS or L["More"],
          when = function(b) return f.current == "character" and slotItem(b) ~= nil end,
          run = function(b) CharacterPage.More(b) end },
    }
    f.padSelect = function(b) return CharacterPage.PadSelect(f, b) end
end

function CharacterPage.Build(page)
    page.slots = ns.Slots.MakeAll(page)
    for _, h in pairs(page.slots) do
        h:SetScript("OnMouseUp", swapMenu)
        CharacterPage.PadSlot(h)
    end
    page.model = ns.Model.Build(page)
    -- The model reaches under the slot columns (Model.Spread): kept at the
    -- page's own level, below the slots and the game's lent buttons.
    local base = page:GetFrameLevel() or 0
    page.model:SetFrameLevel(base)
    if ns.Model.scene then ns.Model.scene:SetFrameLevel(base) end
    page.stats = CharacterPage.BuildStats(page)
    page.foot = CharacterPage.BuildFooter(page)
    page:SetScript("OnUpdate", CharacterPage.OnUpdate)
    ns.Slots.Lend()
end

-- The model rises with what's coming in: the whole window (still closed
-- here, it shows after) or just this page on a tab switch.
function CharacterPage.Open()
    ns.Model.SetUp(0)   -- the window and page move by their anchors and carry the model
end

-- The footer's numbers, in color unless that's off: the item level in
-- your gear's average quality, durability green to red.
function CharacterPage.PaintFooter(page, sum, repairAt)
    local on, C = ns.Setting("footColors") ~= false, ns.Colors
    local color = on and sum.quality and { ns.Gear.QualityColor(sum.quality) }
    local foot = page.foot
    local was = foot.levelShown
    foot.levelShown = sum.level
    local counts = DUI.Motion.CountTo(foot.level, sum.level, function(n)
        if not n then return "" end
        local level = tostring(n)
        if color then level = C.Wrap(level, unpack(color)) end
        return string.format(L["Item level %s"], level)
    end)
    if counts and was and sum.level > was then CharacterPage.Upgrade(foot) end
    local dura = sum.durability and string.format("%d%%", math.floor(sum.durability * 100 + 0.5))
    if dura and on then dura = C.Wrap(dura, C.Durability(sum.durability, repairAt)) end
    page.foot.dura:SetText(dura and string.format(L["Durability %s"], dura) or "")
    -- Ammo: the whole count (never cut), in the accent, and red when you're out.
    local ammo = sum.ammo and tostring(sum.ammo)
    if ammo and on then
        if sum.ammo == 0 then ammo = C.Wrap(ammo, unpack(Style.INK.BAD))
        else ammo = C.Wrap(ammo, Style.Pop()) end
    end
    local text = ammo and string.format(L["Ammo %s"], ammo) or ""
    if ammo and sum.ammoName then text = text .. " (" .. sum.ammoName .. ")" end   -- which ammo, if the game knows it yet
    page.foot.ammo:SetText(text)
end

-- The average went up: the number nudges and a light runs across it.
function CharacterPage.Upgrade(foot)
    local M = DUI.Motion
    M.Bump(foot.level, 1.12, M.NORMAL)
    local h = (foot.level:GetStringHeight() or 14) * 2
    foot.shine:SetHeight(h)
    M.Sweep(foot.shine, foot.level, { width = h * 1.6, dur = M.SLOW + M.NORMAL, alpha = 0.5,
        color = { Style.Accent() } })
end

function CharacterPage.Refresh(page)
    local cfg = ns.module and ns.module.db or {}
    if ns.Gear.UsesAmmo() ~= page.usesAmmo then CharacterPage.Place(page) end
    local all = ns.Gear.All(cfg.repairAt)
    local opts = { itemLevel = cfg.itemLevel ~= false, levelInIcon = cfg.levelInIcon == true,
                   missingEnchants = cfg.missingEnchants == true }
    for key, h in pairs(page.slots) do
        if all[key] then ns.Slots.Paint(h, all[key], opts) end
    end
    CharacterPage.PaintFooter(page, ns.Gear.Summary(all), cfg.repairAt)
    ns.Model.Paint()
    CharacterPage.RefreshStats(page)
    ns.Slots.Holding()
    DUI.AfterCombat(ns.Slots.Pin, "characterPin")
end

function CharacterPage.OnEvent(_, event, slot)
    if event == "PLAYER_EQUIPMENT_CHANGED" then ns.Model.Dress(slot)
    elseif event == "UNIT_MODEL_CHANGED" then ns.Model.SetUp() end
end

ns.Window.Register("character", CharacterPage)
