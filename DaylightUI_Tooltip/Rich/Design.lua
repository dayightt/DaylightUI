-- The Tooltips page's live sample: a Rich card for a player, a creature, an
-- item or a spell (a chip each), drawn by the card's own Panel and laid out by
-- the player's own layout (Rich/Layout.lua). In Design mode each piece of it is
-- dragged up or down the card, onto a line to start a section, or into the
-- Hidden tray beside it (Options/SampleStrip.lua's list move and tray).
--
-- Every piece has made-up content here, so every piece can be grabbed. Nothing
-- of the game's tooltip is shown or owned.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local L = DUI.L

local Design = {}
ns.RichDesign = Design

Design.TRAY_GAP = 30      -- the card, then the tray
Design.TRAY_W = 200       -- the tray's width at most
Design.TRAY_MIN = 150     -- and at least
Design.OUT_X, Design.OUT_Y = 6, 3  -- a piece's hotspot reaches this far past its words
Design.HINT_GAP = 12

Design.VIEWS = {
    { key = "player", label = "Player" },
    { key = "mob", label = "Creature" },
    { key = "item", label = "Item" },
    { key = "spell", label = "Spell" },
}

-- The hints under the tray: each line's key words go in the accent.
Design.HINTS = {
    { "Drag", " a piece up or down the card." },
    { "Drop it on a line", " to start a new section; an empty section closes itself." },
    { "Drag it to Hidden", " to turn it off, and back to show it." },
    { "The name, tags and level", " stay at the top." },
}
Design.KEYS_HINT = { "Arrow keys", " move the picked piece." }

local function hex(c) return DUI.Win.Parts.Hex(c) end
local function pop() return { Style.Pop() } end

-- ---------------------------------------------------------------------
-- The made-up cards
-- ---------------------------------------------------------------------

-- Each kind: its card's kind for Panel.Begin, its spacing, its top light,
-- its header and every piece's draw. p: the panel.
Design.SAMPLES = {}

Design.SAMPLES.player = function(p)
    local Panel, INK, Players = ns.RichPanel, Style.INK, ns.RichPlayers
    local lo, hi = DUI.Gradients.PaintRGB("PALADIN")
    local cr, cg, cb = Style.ClassColor("PALADIN")
    local icon, coords = Players.Icon("PALADIN")
    Panel.Begin(p, "unit", { hi, lo })
    Panel.Header(p, { icon = icon, iconCoords = coords, iconSize = Players.ICON, iconInset = Players.ICON_INSET,
        iconTile = { lo, hi }, title = L["Aelric"] .. " " .. hex(INK.LABEL) .. L["Dawnmere"] .. "|r",
        tags = { ns.RichItems.Tag(L["Paladin"], { cr, cg, cb }), ns.RichItems.Tag(L["Human"], Players.FACTION_COLORS.Alliance) },
        wash = { cr, cg, cb }, right = "60", rightColor = INK.VALUE, rightSize = Style.SIZE.title })
    Panel.Gap(p, Players.AFTER_BANNER)
    local mlo, mhi = DUI.Gradients.PairFrom({ Style.PowerColor("MANA") })
    return {
        guild = function() Panel.Row(p, L["Guild"], L["Dawn Patrol"] .. " " .. hex(INK.LABEL) .. "· " .. L["Officer"] .. "|r", INK.TEXT) end,
        zone = function() Panel.Row(p, L["Zone"], L["Elwynn Forest"], INK.TEXT) end,
        ilvl = function() Panel.Row(p, L["Item level"], "64", pop()) end,
        target = function() Panel.Row(p, L["Targeting"], L["You"], INK.WARN) end,
        health = function() Panel.Bar(p, { value = 82, max = 100, pair = { lo, hi }, h = 7 }) end,
        power = function() Panel.Bar(p, { value = 60, max = 100, pair = { mlo, mhi }, h = 4 }) end,
        buffs = function() Panel.Icons(p, { 135932, 135987, 136078, 135964 }, 4) end,
        addons = function() Panel.Row(p, L["Note"], L["Great healer"], INK.VALUE, INK.TEXT) end,
    }
end

Design.SAMPLES.mob = function(p)
    local Panel, INK, World = ns.RichPanel, Style.INK, ns.RichWorld
    local lo, hi = DUI.Gradients.PaintRGB("HOSTILE")
    Panel.Begin(p, "mob", { hi, lo })
    p.padTop = World.PAD_TOP
    Panel.Header(p, { icon = "Interface\\Icons\\Ability_Hunter_Pet_Boar", iconSize = World.ICON, iconGap = World.ICON_GAP,
        iconTile = { lo, hi }, title = L["Ridgeback Boar"], titleSize = World.TITLE, right = "23",
        rightColor = INK.WARN, rightSize = Style.SIZE.title, tagGap = World.TAG_GAP,
        tags = { ns.RichItems.Tag(L["Hostile"], { Style.ReactionColor(2) }), ns.RichItems.Tag(L["Beast"], World.KIND_COLORS[1] or INK.TEXT) } })
    return {
        health = function() Panel.Bar(p, { value = 78, max = 100, pair = { lo, hi }, h = 7 }) end,
        quests = function()
            Panel.Section(p, L["Boar Hides for Farmer Rowan"])
            Panel.Row(p, L["Ridgeback hide"], "6/10", pop(), INK.TEXT)
            if Panel.Wants("questBars") then
                local qlo, qhi = DUI.Gradients.PairFrom(pop())
                Panel.Bar(p, { value = 6, max = 10, pair = { qlo, qhi }, h = 4 })
            end
        end,
        facts = function() Panel.Text(p, L["Requires Skinning (30)"], INK.LABEL, Style.SIZE.small) end,
        target = function() Panel.Row(p, L["Targeting"], L["You"], INK.WARN) end,
        addons = function() Panel.Text(p, L["Pet: Boar tamed"], INK.TEXT) end,
    }
end

Design.SAMPLES.item = function(p)
    local Panel, INK, Items, Tip = ns.RichPanel, Style.INK, ns.RichItems, ns.Tooltip
    local item = ns.RichSample.ITEM
    local r, g, b = Tip.QualityColor(item.quality)
    local c = r and { r, g, b } or INK.VALUE
    Panel.Begin(p, "item", { Items.Lift(c), c }, true)
    p.padTop, p.rowGap, p.ruleGap = Items.PAD_TOP, Items.ROW_GAP, Items.RULE_GAP
    p.washDown = true
    Panel.Header(p, { icon = item.icon, iconSize = Items.ICON, iconEdge = c, title = L[item.name], titleColor = c,
        tagGap = Items.TAG_GAP, wash = c, tags = {
            Items.Tag(string.format(L["ilvl %d"], item.level), c),
            Items.Tag(INVTYPE_ROBE or L["Chest"], Items.SLOT_ARMOR),
            Items.Tag(L["Cloth"], Items.ARMOR_COLORS[1]),
        } })
    Panel.Gap(p, Items.AFTER_HEADER)
    local function stat(n, word)
        local sc = Tip.StatColor(word) or pop()
        return hex(sc) .. "+" .. n .. "|r " .. L[word]
    end
    local good = hex(INK.GOOD)
    return {
        numbers = function() Panel.Line(p, hex(pop()) .. item.armor .. "|r " .. (ARMOR or L["Armor"])) end,
        stats = function()
            for _, s in ipairs(item.stats) do Panel.Line(p, stat(s[1], s[2])) end
        end,
        effects = function()
            Panel.Text(p, good .. (ITEM_SPELL_TRIGGER_ONUSE or "Use:") .. "|r " .. DUI.Tips.Numbers(L["Restores 600 mana over 30 sec."]), INK.TEXT)
        end,
        set = function()
            Panel.Line(p, Style.Upper(L["Vestments of the Evening"]) .. " " .. hex(pop()) .. "2/5|r", INK.LABEL, Style.SIZE.small)
            Panel.Text(p, L["+20 Spell Power"], INK.GOOD, Style.SIZE.small)
        end,
        facts = function() Panel.Text(p, L["Requires Level 60"], INK.LABEL, Style.SIZE.small) end,
        quote = function() Panel.Text(p, L["\"Woven under a falling star.\""], pop(), Style.SIZE.small) end,
        made = function()
            Panel.Line(p, L["Starweave Cord"], c)
            Panel.Text(p, L["Waist  Cloth"], INK.LABEL, Style.SIZE.small)
        end,
        addons = function() Panel.Row(p, L["Auction"], DUI.Widgets.Money(184500), INK.VALUE, INK.TEXT) end,
        foot = function()
            Panel.Row(p, L["Durability 100 / 100"], DUI.Widgets.Money(item.money), INK.VALUE, INK.LABEL, Style.SIZE.small, Style.SIZE.body)
        end,
    }
end

Design.SAMPLES.spell = function(p)
    local Panel, INK, Spells = ns.RichPanel, Style.INK, ns.RichSpells
    local fc = ns.Tooltip.SCHOOL_COLORS.Frost
    local lo, hi = DUI.Gradients.PairFrom(fc)
    Panel.Begin(p, "spell", { hi, lo })
    p.padTop = Spells.PAD_TOP
    Panel.Header(p, { icon = 135846, iconSize = Spells.ICON, iconGap = Spells.ICON_GAP, title = L["Frostbolt"],
        tagGap = Spells.TAG_GAP, tags = { ns.RichItems.Tag(L["Frost"], fc), ns.RichItems.Tag(L["Rank 4"], pop()) } })
    return {
        tiles = function()
            Panel.Tiles(p, { { L["2.5 sec"], L["Cast"] }, { "120", L["Cost"], { Style.PowerColor("MANA") } }, { L["30 yd"], L["Range"] } })
        end,
        cooldown = function()
            Panel.Row(p, L["Ready in"], L["4.2 sec"], pop(), INK.LABEL)
            Panel.Gap(p, Spells.BAR_GAP)
            local clo, chi = DUI.Gradients.PairFrom(pop())
            Panel.Bar(p, { value = 6, max = 10, pair = { clo, chi }, h = 4 })
        end,
        desc = function()
            Panel.Text(p, DUI.Tips.Numbers(L["Launches a bolt of frost at the enemy, causing 412 to 448 Frost damage and slowing it by 40% for 9 sec."], fc), INK.TEXT)
        end,
        reagents = function()
            Panel.Section(p, L["Reagents"])
            Panel.Row(p, L["Arcane Powder"], "1", pop(), INK.TEXT)
        end,
        facts = function() Panel.Text(p, L["Requires Mage"], INK.LABEL, Style.SIZE.small) end,
        addons = function() Panel.Text(p, L["Rotation helper: cast it first"], INK.TEXT) end,
    }
end

-- ---------------------------------------------------------------------
-- The sample
-- ---------------------------------------------------------------------

-- Every drawn region of a card's piece (texts, bars, icons), for its glide.
local function regionsOf(item)
    local out = {}
    for _, k in ipairs({ "fs", "title", "label", "value", "tail", "bar", "tex", "caption", "pct", "icon", "right", "sub" }) do
        if type(item[k]) == "table" then out[#out + 1] = item[k] end
    end
    for _, r in ipairs(item.list or {}) do out[#out + 1] = r end
    return out
end

local function cfg() return ns.Tooltip.Config() end

function Design.New(parent)
    local Panel, Layout, Strip = ns.RichPanel, ns.RichLayout, DUI.SampleStrip
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(1, 1)
    local holder = CreateFrame("Frame", nil, box)
    holder:SetSize(1, 1)
    holder:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    local p = Panel.For(holder)
    local tray = Strip.NewTray(box)
    local hints = Style.Text(box, Style.SIZE.small, "LEFT")
    hints:SetWordWrap(true)
    hints:SetSpacing(4)
    local keysHint = Style.Text(box, Style.SIZE.small, "LEFT")
    keysHint:SetWordWrap(true)
    -- The dragged piece drawn again inside the strip's lifted box.
    local ghostHolder = CreateFrame("Frame", nil, box)
    ghostHolder:SetSize(1, 1)
    local ghost = Panel.For(ghostHolder)
    local regions = {}   -- piece key -> the frame over its rows
    local view = "player"
    local sample = { frame = box, viewsExclusive = true, designHint = L["Click a piece for its settings."] }
    local parts = {}
    local drawn = {}     -- piece key -> its draw function in the current sample
    local lastTops, lastKind, lastLayout = {}, nil, nil
    local lastHidden = {}

    local function sections() return Layout.Of(view) end
    local function visible()
        local v = {}
        for _, piece in ipairs(Layout.PIECES[view]) do v[piece.key] = Layout.Shown(view, piece.key) end
        return v
    end
    local function top(key) local s = p.spans[key]; return s and p.items[s.from].y end
    local function bottom(key)
        local s = p.spans[key]
        if not s then return nil end
        local item = p.items[s.to]
        return item.y + (item.tall or 0)
    end

    -- Each place a piece can land, on the card in the panel's own units.
    local function slotsFor(key)
        local secs, vis = sections(), visible()
        local slots = Layout.Slots(secs, key, vis)
        local shown = Layout.Shows(secs, key, vis)
        local x, w = (p.padX or Panel.PAD_X), (p.wantW or Panel.MIN_W) - 2 * (p.padX or Panel.PAD_X)
        local out = {}
        for i, sl in ipairs(slots) do
            local y
            local sec = shown[sl.section]
            if sl.new then
                if sl.section == 1 then
                    y = (sec and top(sec[1]) or 0) - 8
                elseif not sec then
                    local prev = shown[sl.section - 1]
                    y = (prev and bottom(prev[#prev]) or 0) + 8
                else
                    local prev = shown[sl.section - 1]
                    y = (bottom(prev[#prev]) + top(sec[1])) / 2
                end
            elseif sl.index == 0 then
                y = top(sec[1]) - 2
            elseif sec[sl.index + 1] then
                y = (bottom(sec[sl.index]) + top(sec[sl.index + 1])) / 2
            else
                y = bottom(sec[sl.index]) + 2
            end
            out[#out + 1] = { x = x, y = y, w = w, new = sl.new, id = i, slot = sl }
        end
        out[#out + 1] = { region = tray.box, id = "hide" }
        return out
    end

    local function layoutKey() return "layout." .. view end

    local function moveOf(key, label)
        local showKey = Layout.ShowKey(view, key)
        local m = { list = true, owner = p }
        function m.slots() return slotsFor(key) end
        function m.place(id)
            if id == "hide" then
                if not Layout.Shown(view, key) then return nil end
                return { { showKey, false } }
            end
            local sl = slotsFor(key)[id]
            if not sl then return nil end
            local moved = Layout.Move(sections(), key, sl.slot, visible())
            local changes = { { layoutKey(), Layout.Encode(moved) } }
            if not Layout.Shown(view, key) then changes[#changes + 1] = { showKey, true } end
            return changes
        end
        function m.step(dir)
            if not Layout.Shown(view, key) then return nil end
            local moved = Layout.Step(sections(), key, dir, visible())
            if not moved then return nil end
            return { { layoutKey(), Layout.Encode(moved) } }
        end
        -- Lifted: the piece drawn again in the strip's box, its old spot an
        -- empty row until it's dropped.
        function m.lift(frame)
            local region = regions[key]
            if not frame then
                ghost:Hide()
                if region then region.blank:Hide() end
                return
            end
            local draw = drawn[key]
            if not draw then return end
            Panel.Begin(ghost, p.kind)
            ghost.padTop, ghost.rowGap, ghost.ruleGap = Design.OUT_Y, p.rowGap, p.ruleGap
            draw()
            Panel.Finish(ghost)
            ghost.shell:Hide()
            for _, t in ipairs(ghost.light) do t:Hide() end
            for _, t in ipairs(ghost.wash) do t:Hide() end
            ghostHolder:SetParent(frame)
            ghostHolder:SetScale(holder:GetScale())
            ghostHolder:ClearAllPoints()
            ghostHolder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            ghost:ClearAllPoints()
            ghost:SetPoint("TOPLEFT", frame, "TOPLEFT", -((p.padX or Panel.PAD_X) - Design.OUT_X) * ghost:GetScale(), 0)
            ghost.pinned = nil
            ghost:SetFrameLevel(frame:GetFrameLevel() + 2)
            ghost.body:SetFrameLevel(frame:GetFrameLevel() + 3)
            ghost:Show()
            if region then region.blank:Show() end
        end
        return m
    end

    local function region(key)
        local r = regions[key]
        if r then return r end
        r = CreateFrame("Frame", nil, p)
        r:EnableMouse(false)
        r.blank = r:CreateTexture(nil, "OVERLAY", nil, 7)
        r.blank:SetTexture("Interface\\Buttons\\WHITE8X8")
        r.blank:SetAllPoints(r)
        r.blank:Hide()
        regions[key] = r
        return r
    end

    local function hintLine(h)
        local r, g, b = Style.Accent()
        return hex({ r, g, b }) .. L[h[1]] .. "|r" .. L[h[2]]
    end

    -- The card's rows glide from where they were to their new spots.
    local function glide(kind, layoutText)
        if kind ~= lastKind or layoutText == lastLayout or not DUI.Motion.On() then return end
        for key, was in pairs(lastTops) do
            local span, now = p.spans[key], top(key)
            if span and now and math.abs(now - was) > 0.5 then
                for i = span.from, span.to do
                    for _, rg in ipairs(regionsOf(p.items[i])) do
                        DUI.SafeCall(DUI.Motion.Glide, rg, 0, now - was, DUI.Motion.NORMAL)
                    end
                end
            end
        end
    end

    function sample.Refresh(width, room)
        if not (cfg() and cfg().style == "rich") then
            box:Hide()
            return 0
        end
        box:Show()
        ghost:Hide()
        width = (type(width) == "number" and width > 0) and width or 600
        room = (type(room) == "number" and room > 0) and room or Strip.MAX_HEIGHT
        local kind = view
        local draws = Design.SAMPLES[kind](p)
        drawn = {}
        local pieces = {}
        for key, fn in pairs(draws) do
            drawn[key] = fn
            pieces[key] = { has = true, draw = fn }
        end
        if not Layout.Run(p, kind, pieces) then Layout.DropGap(p) end
        local w, h = Panel.Finish(p)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        p.pinned = nil
        local ps = p:GetScale()
        local trayW = math.max(Design.TRAY_MIN, math.min(Design.TRAY_W, width * 0.35))
        local fit = math.min(1, room / math.max(1, h * ps), (width - trayW - Design.TRAY_GAP) / math.max(1, w * ps))
        holder:SetScale(fit)
        holder:SetSize(w * ps, h * ps)
        local cardW = w * ps * fit
        -- Hotspot frames over each shown piece's rows.
        local layoutText = Layout.Encode(sections())
        glide(kind, layoutText)
        local hiddenLabels, hiddenKeys = {}, {}
        local nowTops = {}
        parts = {}
        for _, r in pairs(regions) do r:Hide() end
        local px, inner = (p.padX or Panel.PAD_X), w - 2 * (p.padX or Panel.PAD_X)
        for _, piece in ipairs(Layout.PIECES[kind]) do
            local key = piece.key
            local span = p.spans[key]
            if span then
                local r = region(key)
                local y0, y1 = top(key), bottom(key)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", p, "TOPLEFT", px - Design.OUT_X, -(y0 - Design.OUT_Y))
                r:SetSize(inner + 2 * Design.OUT_X, (y1 - y0) + 2 * Design.OUT_Y)
                r:SetFrameLevel(p.body:GetFrameLevel() + 2)
                r.blank:SetVertexColor(Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
                r.blank:Hide()
                r:Show()
                nowTops[key] = y0
                parts[#parts + 1] = { label = piece.label, keys = { piece.show }, region = r, move = moveOf(key, piece.label) }
            else
                hiddenLabels[#hiddenLabels + 1] = L[piece.label]
                hiddenKeys[#hiddenKeys + 1] = piece
            end
        end
        -- The tray: the pieces switched off, a fade for one that just went there.
        tray:ClearAllPoints()
        tray:SetPoint("TOPLEFT", box, "TOPLEFT", cardW + Design.TRAY_GAP, 0)
        local boxes = tray.Set(hiddenLabels, trayW)
        local nowHidden = {}
        for i, piece in ipairs(hiddenKeys) do
            nowHidden[piece.key] = true
            if kind == lastKind and not lastHidden[piece.key] then
                boxes[i]:SetAlpha(0)
                DUI.Motion.AlphaTo(boxes[i], 1, DUI.Motion.FAST)
            else
                boxes[i]:SetAlpha(1)
            end
            parts[#parts + 1] = { label = piece.label, keys = { piece.show }, region = boxes[i], move = moveOf(piece.key, piece.label) }
        end
        lastHidden, lastTops, lastKind, lastLayout = nowHidden, nowTops, kind, layoutText
        local lines = {}
        for i, hnt in ipairs(Design.HINTS) do lines[i] = hintLine(hnt) end
        hints:SetText(table.concat(lines, "\n"))
        Style.InkText(hints, "LABEL")
        hints:ClearAllPoints()
        hints:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -Design.HINT_GAP)
        hints:SetWidth(trayW)
        keysHint:SetText(hintLine(Design.KEYS_HINT))
        Style.InkText(keysHint, "LABEL")
        keysHint:SetWidth(trayW)
        local hh = hints:GetStringHeight()
        hh = (type(hh) == "number" and hh > 0) and hh or #Design.HINTS * (Style.SIZE.small + 8)
        local sideH = tray:GetHeight() + Design.HINT_GAP + hh + Design.HINT_GAP + Style.SIZE.small + 4
        local total = math.max(h * ps * fit, sideH)
        keysHint:ClearAllPoints()
        keysHint:SetPoint("BOTTOMLEFT", box, "TOPLEFT", cardW + Design.TRAY_GAP, -total)
        box:SetSize(width, total)
        return total
    end

    function sample.Parts() return parts end
    -- The strip lays chips out from the right: last first, so they read
    -- Player, Creature, Item, Spell.
    function sample.Views()
        local out = {}
        for i = #Design.VIEWS, 1, -1 do
            local v = Design.VIEWS[i]
            out[#out + 1] = { key = v.key, label = L[v.label], on = v.key == view }
        end
        return out
    end
    function sample.SetView(key, on)
        if on and Layout.PIECES[key] then view = key end
    end
    function sample.View() return view end
    function sample.Card() return p end
    function sample.Tray() return tray end
    return sample
end

-- The Tooltips page shows it (its options are built before this file loads).
if ns.OPTIONS and ns.OPTIONS.pages and ns.OPTIONS.pages[1] then
    ns.OPTIONS.pages[1].sample = function(parent) return Design.New(parent) end
end
