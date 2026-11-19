-- One loot roll, drawn: the item, the time left, your roll buttons, a line
-- saying where the roll stands, and the group under it (each player's pick and
-- roll, best first, the winner lit). Compact, the list folds into a row of
-- ticks. Built once per card and filled again on every change: only what
-- changed moves.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Motion, Pixel = DUI.Style, DUI.Motion, DUI.Pixel

local RollCard = {
    PAD = 10,
    ICON = 36,
    HEAD = 52,     -- item, name and sub line
    TIMER = 10,    -- the time bar, while picking
    SUM = 22,      -- the line saying where the roll stands
    HEAD_SMALL = 42, -- a compact card's head
    ICON_SMALL = 28,
    ROW = 24,      -- one player in the list
    FOOT = 8,
    PICK = 17,     -- a row's pick icon
    GAP = 6,       -- between the roll buttons
    TICK_W = 4,
    TICK_GAP = 3,
    DIM = 0.6,     -- a player who passed
    ROLL_BAR = 56, -- a row's roll bar at 100
    WASH = 0.14,   -- the winner row's accent wash
    -- Bar colors by pick, the roll buttons' icon colors.
    COLORS = {
        need = Style.INK.TEXT,
        greed = Style.INK.MONEY,
        transmog = { 0.75, 0.55, 1 },
        disenchant = { 0.5, 0.77, 1 },
    },
    KINDS = { "need", "greed", "transmog", "disenchant", "pass" },
    TEXT = {
        choose = L["Pick Need, Greed or Pass"],
        count = L["%d of %d picked"],
        countSome = L["%d picked"],
        mine = L["You picked %s"],
        mineCount = L["You picked %s · %d of %d picked"],
        rolling = L["Rolling"],
        waiting = L["Waiting on %d"],
        won = L["%s won with %s %d."],
        wonNoRoll = L["%s won."],
        youWon = L["You won with %s %d!"],
        youWonNoRoll = L["You won!"],
        youRolled = L[" You rolled %d."],
        youPassed = L[" You passed."],
        timedOut = L[" Time ran out, so you passed."],
        allPassed = L["Everyone passed."],
        tied = L["Tied: the game rolls again."],
        noResult = L["No result seen."],
        choosing = L["choosing"],
        you = L["you"],
        hasOne = L["has one"],
        twin = L["%d of %d"],
    },
}
ns.RollCard = RollCard

-- RollOnLoot, kept as a field so tests can watch it.
RollCard.roll = function(rollID, id) RollOnLoot(rollID, id) end

-- The game's own word for each pick.
local function word(kind)
    if kind == "need" then return _G.NEED or L["Need"] end
    if kind == "greed" then return _G.GREED or L["Greed"] end
    if kind == "pass" then return _G.PASS or L["Pass"] end
    if kind == "disenchant" then return _G.ROLL_DISENCHANT or L["Disenchant"] end
    if kind == "transmog" then return _G.TRANSMOGRIFICATION or L["Transmog"] end
    return kind
end
RollCard.Word = word

local function hex(c) return DUI.Win.Parts.Hex(c) end

-- First names unless the player asked for full ones (General's last-name
-- switches), or two on the roll share a first name.
local function shownName(p, drop)
    if DUI:Get("general", "lastNames.rolls") == true or p.key ~= p.first then return p.name or p.first end
    for key, q in pairs(drop and drop.players or {}) do
        if q ~= p and q.first == p.first and key ~= p.first then return p.name or p.first end
    end
    return p.first
end

-- A pick's icon: Daylight UI's art, or the game's when picked in the options
-- (it has none for Disenchant).
local function setPickIcon(tex, kind, settings)
    if settings.icons == "game" and kind ~= "disenchant" then
        tex:SetAtlas("lootroll-toast-icon-" .. kind .. "-up")
    else
        tex:SetTexture(DUI.MEDIA .. "roll-" .. kind .. ".png")
    end
end

-- The smallest a folded part gets. The game reads a size of 0 as no size at
-- all: what hangs below it loses its place and its clipping stops.
RollCard.FOLDED = 0.001

-- Eases a box of the card to a height, the card growing or shrinking with it.
-- Folded all the way, the box hides, so nothing in it can show.
local function easeBox(card, box, to, dur)
    local from = box:GetHeight() or 0
    if box.goal == to then return end
    box.goal = to
    if to > 0 then box:Show() end
    Motion.Tween(box, from, to, dur, function(h)
        box:SetHeight(math.max(RollCard.FOLDED, h))
        card:SetHeight(RollCard.LiveHeight(card))
        if card.onHeight then card.onHeight(card) end
    end, function()
        if to <= 0 then box:Hide() end
    end)
end

function RollCard.LiveHeight(card)
    local h = (card.headH or RollCard.HEAD) + RollCard.FOOT
    for _, box in ipairs(card.boxes) do h = h + (box:GetHeight() or 0) end
    return h
end

local function box(card, after)
    local f = CreateFrame("Frame", nil, card)
    f:SetPoint("TOPLEFT", after, "BOTTOMLEFT", 0, 0)
    f:SetPoint("RIGHT", card, "RIGHT", 0, 0)
    f:SetHeight(RollCard.FOLDED)
    f:SetClipsChildren(true)
    f:Hide()
    card.boxes[#card.boxes + 1] = f
    return f
end

local function tooltip(b)
    if not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_TOP")
    DUI.Tips.Clear()
    DUI.Tips.Title(word(b.kind))
    if b.reason then DUI.Tips.Text(b.reason, Style.INK.WARN) end
    DUI.Tips.Flush()
    GameTooltip:Show()
end

local function press(card, kind)
    local drop = card.drop
    if not drop or drop.done or drop.mine or drop.sample or drop.watch then return end
    -- Noted as pressed first: the game takes the pick inside RollOnLoot, or
    -- only after its own "this item will bind" box. Said no to that, the
    -- buttons stay and another can be pressed.
    ns.RollData.Press(drop.rollID, kind)
    RollCard.roll(drop.rollID, ns.RollData.ID[kind])
    RollCard.Fill(card, drop, card.look)
end

function RollCard.New(parent)
    local W, Kit = DUI.Widgets, ns.Kit
    local P = RollCard.PAD
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(300, RollCard.HEAD)
    Style.Shell(card, { window = true })
    card.boxes = {}

    -- The quality pair along the top, inside the border.
    local edge = Pixel.Px(card, 1)
    card.line = card:CreateTexture(nil, "OVERLAY", nil, 6)
    card.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.line:SetPoint("TOPLEFT", card, "TOPLEFT", edge, -edge)
    card.line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -edge, -edge)
    card.line:SetHeight(Pixel.Px(card, ns.LootRoll.LINE))

    -- The light that crosses a won roll.
    card.sweep = card:CreateTexture(nil, "OVERLAY", nil, 7)
    card.sweep:SetTexture(DUI.MEDIA .. "glow.png")
    card.sweep:SetBlendMode("ADD")
    card.sweep:SetHeight(RollCard.HEAD * 1.6)
    card.sweep:Hide()

    local head = CreateFrame("Frame", nil, card)
    head:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    head:SetHeight(RollCard.HEAD)
    card.head = head

    -- The item: its tooltip on hover, Shift and Ctrl clicks like any item.
    local icon = CreateFrame("Button", nil, head)
    icon:SetSize(RollCard.ICON, RollCard.ICON)
    icon:SetPoint("LEFT", head, "LEFT", P, -1)
    icon.icon = icon:CreateTexture(nil, "ARTWORK")
    icon.icon:SetAllPoints(icon)
    Kit.Item(icon)
    icon:SetScript("OnEnter", function(self)
        local drop = card.drop
        if not (drop and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- The game's own rolls have positive ids; samples and rolls rebuilt from the
        -- Loot History don't, so those show the item from its link.
        if type(GameTooltip.SetLootRollItem) == "function" and not drop.done and drop.rollID > 0 then
            GameTooltip:SetLootRollItem(drop.rollID)
        elseif drop.link then
            GameTooltip:SetHyperlink(drop.link)
        end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    icon:SetScript("OnClick", function() if card.drop then DUI.Win.Parts.ItemClick(card.drop.link) end end)
    card.icon = icon

    card.dup = Style.Text(head, Style.SIZE.tiny, "RIGHT")
    card.dup:SetPoint("TOPRIGHT", head, "TOPRIGHT", -P, -P)
    Style.InkText(card.dup, "LABEL")
    card.name = Style.Text(head, Style.SIZE.head, "LEFT")
    card.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", P, 0)
    card.name:SetPoint("RIGHT", card.dup, "LEFT", -6, 0)
    card.name:SetWordWrap(false)
    card.sub = Style.Text(head, Style.SIZE.small, "LEFT")
    card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.sub:SetPoint("RIGHT", head, "RIGHT", -P, 0)
    card.sub:SetWordWrap(false)
    Style.InkText(card.sub, "LABEL")

    -- Time left: a thin bar and the seconds.
    card.timerBox = box(card, head)
    card.time = Style.Text(card.timerBox, Style.SIZE.tiny, "RIGHT")
    card.time:SetPoint("RIGHT", card.timerBox, "RIGHT", -P, 0)
    card.bar = W.Bar(card.timerBox, W.BAR_H)
    card.bar:SetPoint("LEFT", card.timerBox, "LEFT", P, 0)
    card.bar:SetPoint("RIGHT", card.timerBox, "RIGHT", -(P + 28), 0)
    card.timer = { bar = card.bar }

    -- Your roll buttons, folding away once you've picked.
    card.buttonBox = box(card, card.timerBox)
    card.buttons = {}
    for _, kind in ipairs(RollCard.KINDS) do
        local b = W.Button(card.buttonBox, word(kind), 30)
        b.kind = kind
        W.ButtonIcon(b, "roll-" .. kind .. ".png")
        b:SetScript("OnClick", function() press(card, kind) end)
        b:HookScript("OnEnter", tooltip)
        b:HookScript("OnLeave", function(self) if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        b:Hide()
        card.buttons[kind] = b
    end

    card.sumBox = box(card, card.buttonBox)
    -- The ticks of a compact card sit at the right end of the summary line.
    card.ticks = CreateFrame("Frame", nil, card.sumBox)
    card.ticks:SetPoint("TOPRIGHT", card.sumBox, "TOPRIGHT", -P, 0)
    card.ticks:SetPoint("BOTTOMRIGHT", card.sumBox, "BOTTOMRIGHT", -P, 0)
    card.ticks:SetWidth(1)
    card.tickBars = {}
    card.sum = Style.Text(card.sumBox, Style.SIZE.small, "LEFT")
    card.sum:SetPoint("LEFT", card.sumBox, "LEFT", P, 0)
    card.sum:SetPoint("RIGHT", card.ticks, "LEFT", -8, 0)
    card.sum:SetWordWrap(false)
    Style.InkText(card.sum, "LABEL")

    card.list = box(card, card.sumBox)
    card.rows = {}
    card.rowOf = {}
    card.freeRows = {}
    return card
end

-- A row for one player, kept for them so a new order glides each row to its
-- new place.
local function rowFor(card, key)
    local row = card.rowOf[key]
    if row then return row end
    row = table.remove(card.freeRows)
    if row then
        card.rowOf[key] = row
        return row
    end
    local W, P = DUI.Widgets, RollCard.PAD
    local f = CreateFrame("Frame", nil, card.list)
    f:SetHeight(RollCard.ROW)
    f:SetPoint("LEFT", card.list, "LEFT", 0, 0)
    f:SetPoint("RIGHT", card.list, "RIGHT", 0, 0)
    row = { frame = f }
    row.wash = f:CreateTexture(nil, "BACKGROUND")
    row.wash:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.wash:SetAllPoints(f)
    row.wash:Hide()
    row.sweep = f:CreateTexture(nil, "OVERLAY")
    row.sweep:SetTexture(DUI.MEDIA .. "glow.png")
    row.sweep:SetBlendMode("ADD")
    row.sweep:SetHeight(RollCard.ROW * 1.6)
    row.sweep:Hide()
    row.pick = f:CreateTexture(nil, "ARTWORK")
    row.pick:SetSize(RollCard.PICK, RollCard.PICK)
    row.pick:SetPoint("LEFT", f, "LEFT", P, 0)
    row.num = Style.Text(f, Style.SIZE.body, "RIGHT")
    row.num:SetPoint("RIGHT", f, "RIGHT", -P, 0)
    row.num:SetWidth(52)
    row.bar = W.Bar(f, W.BAR_H)
    row.bar:SetWidth(RollCard.ROLL_BAR)
    row.bar:SetPoint("RIGHT", row.num, "LEFT", -6, 0)
    row.name = Style.Text(f, Style.SIZE.body, "LEFT")
    row.name:SetPoint("LEFT", row.pick, "RIGHT", 6, 0)
    row.name:SetWordWrap(false)
    row.tag = Style.Text(f, Style.SIZE.tiny, "LEFT")
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.tag:SetPoint("RIGHT", row.bar, "LEFT", -6, 0)
    Style.InkText(row.tag, "LABEL")
    card.rowOf[key] = row
    return row
end

local function paintRow(card, row, p, drop, settings, first)
    local won = drop.winner == p.key
    row.name:SetText(shownName(p, drop))
    row.name:SetTextColor(Style.ClassTextColor(p.class))
    local tag = (p.self and RollCard.TEXT.you) or (p.hasOne and not won and RollCard.TEXT.hasOne) or ""
    row.tag:SetText(tag)
    Style.InkText(row.tag, p.hasOne and not p.self and "VALUE" or "LABEL")

    -- A new pick pops in.
    local pick = p.pick
    if pick ~= row.shownPick then
        row.shownPick = pick
        if pick then
            setPickIcon(row.pick, pick, settings)
            row.pick:Show()
            if not first then Motion.Pop(row.pick, 0.6, Motion.FAST) end
        else
            row.pick:Hide()
        end
    end

    if p.roll then
        Motion.CountTo(row.num, p.roll, tostring, first and 0 or Motion.SLOW)
        Style.InkText(row.num, won and "pop" or "VALUE")
    else
        row.num.__duiCountKey = nil
        row.num:SetText(pick and "" or RollCard.TEXT.choosing)
        Style.InkText(row.num, "LABEL")
    end

    local showBar = settings.rollBars ~= false and p.roll ~= nil
    row.bar:SetShown(showBar)
    if showBar then
        row.bar:SetMinMaxValues(0, 100)
        Style.SetBarValue(row.bar, p.roll, first)
        if won then DUI.Widgets.BarAccent(row.bar)
        else
            local c = RollCard.COLORS[pick] or Style.INK.LABEL
            DUI.Widgets.BarFrom(row.bar, c[1], c[2], c[3])
        end
    end

    row.frame:SetAlpha(pick == "pass" and RollCard.DIM or 1)
    row.lit = won or nil
    row.wash:SetShown(won)
    if won then Style.PaintAccent(row.wash, RollCard.WASH) end
    if won and not row.shone and settings.winShine ~= false then
        row.shone = true
        local times = p.self and 2 or 1
        local function shine(n)
            Motion.Sweep(row.sweep, row.frame, { width = 90, dur = 0.7, alpha = 0.5,
                done = n > 1 and function() shine(n - 1) end or nil })
        end
        shine(times)
    end
end

-- The players shown, in order.
local function listed(drop, settings)
    local out = {}
    for _, p in ipairs(ns.RollData.Sorted(drop, settings.sort)) do
        if settings.showPass ~= false or p.pick ~= "pass" then out[#out + 1] = p end
    end
    return out
end

local function layRows(card, drop, settings, first)
    local players = listed(drop, settings)
    local keep = {}
    wipe(card.rows)
    for i, p in ipairs(players) do
        local row = rowFor(card, p.key)
        keep[p.key] = true
        card.rows[i] = row
        local y = -(i - 1) * RollCard.ROW
        if row.y and row.y ~= y and not first then Motion.Glide(row.frame, 0, row.y - y, Motion.SLOW) end
        row.y = y
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", card.list, "TOPLEFT", 0, y)
        row.frame:SetPoint("TOPRIGHT", card.list, "TOPRIGHT", 0, y)
        row.frame:Show()
        paintRow(card, row, p, drop, settings, first)
    end
    for key, row in pairs(card.rowOf) do
        if not keep[key] then row.frame:Hide(); row.y = nil end
    end
    return #players
end

-- A row of ticks, one per player: tall for a high roll, faint for Greed,
-- flat for Pass, a dot while choosing.
local function layTicks(card, drop)
    local players = ns.RollData.Sorted(drop, "best")
    local x = 0
    for i, p in ipairs(players) do
        local t = card.tickBars[i]
        if not t then
            t = card.ticks:CreateTexture(nil, "ARTWORK")
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            card.tickBars[i] = t
        end
        local h = 3
        if p.roll then h = 4 + 8 * math.min(100, p.roll) / 100
        elseif p.pick and p.pick ~= "pass" then h = 6 end
        if p.pick == "pass" then h = 2 end
        t:SetSize(RollCard.TICK_W, h)
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", card.ticks, "LEFT", x, -5)
        local c = RollCard.COLORS[p.pick] or Style.INK.LABEL
        if drop.winner == p.key then
            local r, g, b = Style.Accent()
            t:SetVertexColor(r, g, b, 1)
        else
            t:SetVertexColor(c[1], c[2], c[3], (p.pick == "greed" and 0.55) or (p.pick and 1) or 0.4)
        end
        t:Show()
        x = x + RollCard.TICK_W + RollCard.TICK_GAP
    end
    for i = #players + 1, #card.tickBars do card.tickBars[i]:Hide() end
    card.ticks:SetWidth(math.max(1, x - RollCard.TICK_GAP))
end

-- Where the roll stands, in one calm line: a name or a number in color, the
-- rest a label.
local function summary(drop)
    local T = RollCard.TEXT
    local pop = hex({ Style.Pop() })
    if drop.done then
        if drop.winner then
            local p = drop.players[drop.winner]
            local kind = p.pick and word(p.pick)
            if p.self then
                if p.roll and kind then return T.youWon:format(kind, p.roll) end
                return T.youWonNoRoll
            end
            local name = hex({ Style.ClassTextColor(p.class) }) .. shownName(p, drop) .. "|r"
            local text = (p.roll and kind) and T.won:format(name, kind, p.roll) or T.wonNoRoll:format(name)
            local me = drop.me and drop.players[drop.me]
            if drop.timedOut then text = text .. T.timedOut
            elseif me and me.pick == "pass" then text = text .. T.youPassed
            elseif me and me.roll then text = text .. T.youRolled:format(me.roll) end
            return text
        end
        if drop.allPassed then return T.allPassed end
        if drop.expired then return T.noResult end
        return T.noResult
    end
    if drop.tied then return T.tied end
    local picked, total, rolled = 0, 0, false
    for _, p in pairs(drop.players) do
        total = total + 1
        if p.pick then picked = picked + 1 end
        if p.roll and not p.self then rolled = true end
    end
    -- Without the Loot History only players who spoke are known: no total.
    local known = drop.lootListKey ~= nil
    if drop.mine then
        if rolled then return T.rolling end
        local mine = pop .. word(drop.mine) .. "|r"
        if known and total > picked then return T.mineCount:format(mine, picked, total) end
        return T.mine:format(mine)
    end
    if picked == 0 then return T.choose end
    if known then return T.count:format(picked, total) end
    return T.countSome:format(picked)
end

-- The roll buttons: Need, Greed (Transmog in its place when the game offers
-- it), Disenchant when it can be, Pass. One the game won't let you press is
-- dimmed and says why.
local function layButtons(card, drop, settings)
    local size = settings.buttonSize or 30
    local shown = {}
    for _, kind in ipairs(RollCard.KINDS) do
        local b = card.buttons[kind]
        local on
        if kind == "need" or kind == "pass" then on = true
        elseif kind == "greed" then on = not drop.can.transmog
        elseif kind == "transmog" then on = drop.can.transmog
        elseif kind == "disenchant" then on = drop.can.disenchant end
        b:SetShown(on and true or false)
        if on then
            shown[#shown + 1] = b
            local can = kind == "pass" or drop.can[kind == "transmog" and "transmog" or kind]
            local reasonID = drop.reasons[kind]
            b.reason = (not can and type(reasonID) == "number" and reasonID > 0) and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reasonID] or nil
            if (not can) ~= (b.off == true) then b.SetOff(not can) end
            b:SetHeight(size)
            b.SetWords(settings.buttonWords ~= false and word(kind) or "")
            if settings.icons == "game" and kind ~= "disenchant" then
                b.SetIcon("lootroll-toast-icon-" .. kind .. "-up", true)
            else
                b.SetIcon("roll-" .. kind .. ".png")
            end
            b.LayIcon(size - 8)
            b.SetActive(drop.mine == kind or drop.pending == kind)
        end
    end
    local P, G = RollCard.PAD, RollCard.GAP
    local width = (card:GetWidth() or 300) - 2 * P
    local each = (width - G * (#shown - 1)) / math.max(1, #shown)
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetWidth(each)
        b:SetPoint("TOPLEFT", card.buttonBox, "TOPLEFT", P + (i - 1) * (each + G), -4)
    end
end

-- Whether the group list shows: the stack says so with look.open; on its own
-- a full card shows it.
function RollCard.ListOpen(look)
    if look.settings.list == "off" then return false end
    if look.open ~= nil then return look.open == true end
    return look.mode == "full"
end

-- What a card would measure, settled.
function RollCard.Height(card, look)
    local drop, s = card.drop, look.settings
    local open = RollCard.ListOpen(look)
    local small = look.mode == "compact" and not open
    local h = (small and RollCard.HEAD_SMALL or RollCard.HEAD) + RollCard.SUM + RollCard.FOOT
    if not drop then return h end
    if not drop.done then h = h + RollCard.TIMER end
    if not drop.done and not drop.mine then h = h + (s.buttonSize or 30) + 10 end
    if open then h = h + #listed(drop, s) * RollCard.ROW end
    return h
end

function RollCard.Fill(card, drop, look)
    local s = look.settings
    local first = card.drop ~= drop
    card.drop, card.look = drop, look
    if s.width then card:SetWidth(s.width) end

    -- Item, quality and sub line.
    local color = ns.LootRoll.QualityColor(drop.quality) or { Style.INK.VALUE[1], Style.INK.VALUE[2], Style.INK.VALUE[3] }
    if first then
        card.icon.icon:SetTexture(drop.icon)
        ns.Kit.Paint(ns.Kit.ShellOf(card.icon), color)
        card.name:SetText(drop.name)
        card.name:SetTextColor(color[1], color[2], color[3])
        card.sub:SetText(ns.LootRoll.Sub(ns.LootRoll.Words(drop.link), drop.bop))
        local lo, hi = DUI.Gradients.PairFrom(color)
        DUI.Gradients.PaintPair(card.line, lo, hi)
        -- A new roll on this card: its rows go back to be reused for the new players.
        for key, row in pairs(card.rowOf) do
            row.frame:Hide()
            row.y, row.shone, row.shownPick = nil, nil, nil
            row.num.__duiCountKey = nil
            card.rowOf[key] = nil
            card.freeRows[#card.freeRows + 1] = row
        end
        card.shone = nil
    end
    card.line:SetShown(s.qualityLine ~= false)
    local i, n
    if drop.twin then i, n = drop.twin[1], drop.twin[2] else i, n = ns.RollData.TwinIndex(drop) end
    card.dup:SetText((s.twins ~= false and n > 1) and RollCard.TEXT.twin:format(i, n) or "")

    -- Timer, buttons, summary.
    local dur = first and 0 or nil
    easeBox(card, card.timerBox, drop.done and 0 or RollCard.TIMER, dur or Motion.NORMAL)
    card.time:SetShown(s.timerText ~= false)
    RollCard.Tick(card, GetTime())
    if drop.done and card.timer.low then
        -- Over while time was low: the pulse stops with it.
        card.timer.low, card.timer.painted = nil, nil
        Motion.Tween(card.timer, 0, 0, 0)
        card.bar.fill:SetAlpha(1)
    end
    layButtons(card, drop, s)
    easeBox(card, card.buttonBox, (drop.done or drop.mine) and 0 or (s.buttonSize or 30) + 10, dur or Motion.NORMAL)
    easeBox(card, card.sumBox, RollCard.SUM, 0)
    card.sum:SetText(summary(drop))

    -- The list or the ticks.
    local open = RollCard.ListOpen(look)
    local small = look.mode == "compact" and not open
    local ticks = small and s.ticks ~= false
    card.ticks:SetShown(ticks)
    if ticks then layTicks(card, drop) else card.ticks:SetWidth(1) end
    -- Compact, the head is smaller too.
    local headH = small and RollCard.HEAD_SMALL or RollCard.HEAD
    if card.headH ~= headH then
        card.headH = headH
        card.head:SetHeight(headH)
        local size = small and RollCard.ICON_SMALL or RollCard.ICON
        card.icon:SetSize(size, size)
    end
    local count = 0
    if open then count = layRows(card, drop, s, first)
    else
        for _, row in pairs(card.rowOf) do row.frame:Hide() end
        wipe(card.rows)
    end
    easeBox(card, card.list, count * RollCard.ROW, dur or Motion.SLOW)

    -- A light crosses the card once it's won, twice when it's yours.
    if drop.winner and not card.shone and s.winShine ~= false then
        card.shone = true
        local me = drop.players[drop.winner]
        local function shine(times)
            Motion.Sweep(card.sweep, card, { width = 110, dur = 0.7, alpha = 0.45, color = color,
                done = times > 1 and function() shine(times - 1) end or nil })
        end
        shine(me and me.self and 2 or 1)
    end
    card:SetHeight(RollCard.LiveHeight(card))
end

-- The time bar and seconds, run by the stack's one driver while picking.
function RollCard.Tick(card, now)
    local drop = card.drop
    if not drop or drop.done then return end
    local left = math.max(0, drop.start + drop.duration - now)
    card.bar:SetMinMaxValues(0, drop.duration)
    card.bar:SetValue(left)
    local secs = math.ceil(left)
    if secs ~= card.secs then
        card.secs = secs
        card.time:SetText(secs .. "s")
    end
    local r = card.timer
    local low = drop.duration > 0 and left / drop.duration <= ns.LootRoll.WARN_AT
    if low ~= r.low or r.painted == nil then
        r.low, r.painted = low, true
        ns.LootRoll.PaintTimer(r)
        Style.InkText(card.time, low and "WARN" or "pop")
        ns.LootRoll.Breathe(r, true)
    end
end
