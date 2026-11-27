-- Missing buffs, the action picker (Right-click to choose, off by default), as
-- EllesmereUI's: right-click a class buff with two or more lines known, a
-- spell group, Well Fed or a scroll to choose what its icon uses, on the
-- shared icon ring round the cursor. Scroll over a spell to choose its rank:
-- up for a higher one, back at the top the pin goes. Never in a fight.

local _, BL = ...
local DUI = DaylightUI

local Picker = {}
BL.ReminderPicker = Picker

local function H() return BL.Reminder.H end
local function on() local c = BL.Reminder.Config() return c ~= nil and c.picker == true end

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

local function save(path, v)
    DUI:Set(BL.MODULE, "settings.reminder." .. path, v)
    BL.Reminder.RefreshSoon()
end

-- A spell's rank as the client words it ("Rank 3"), and its number.
local function subtext(id)
    local h = H()
    local s = C_Spell and C_Spell.GetSpellSubtext and h.call(C_Spell.GetSpellSubtext, id)
    return type(s) == "string" and s ~= "" and s or nil
end
local function rankNumber(id, ranks)
    local s = subtext(id)
    local n = s and s:match("(%d+)")
    if n then return n end
    for i, x in ipairs(ranks or {}) do if x == id then return tostring(i) end end
    return nil
end

local function knownRanks(ids)
    local out = {}
    for _, id in ipairs(ids) do if H().known(id) then out[#out + 1] = id end end
    return out
end

-- The cast: by name (the highest rank), or a pinned lower rank by its rank.
local function castMacro(id, pinned)
    local name = H().spellName(id)
    if not name then return nil end
    local sub = pinned and subtext(id)
    if sub then return "/cast [nocombat,@player] " .. name .. "(" .. sub .. ")" end
    return "/cast [nocombat,@player] " .. name
end

-- A choice's rank to cast: its pin while still known and not the top one.
local function rankOf(ranks, pin)
    for i, id in ipairs(ranks) do
        if id == pin and i < #ranks then return id, true end
    end
    return ranks[#ranks], false
end

-- Spell choices (a class buff's lines, a group's members): the picked one
-- (or the one the icon already casts) with its rank, written onto the entry.
local function applySpells(e, lines, settings, kind, ref)
    local h = H()
    local chosen
    for _, line in ipairs(lines) do
        if settings.castSpellID == line.key then chosen = line end
    end
    if not chosen then
        for _, line in ipairs(lines) do
            for _, id in ipairs(line.ranks) do if id == e.spell then chosen = line end end
        end
    end
    if not chosen then return end
    local pins = settings.castRanks or {}
    local id, pinned = rankOf(chosen.ranks, pins[chosen.key])
    e.spell, e.tipSpell, e.icon = id, id, h.spellIcon(id)
    e.macro = castMacro(id, pinned)
    if #chosen.ranks > 1 then e.badge = rankNumber(id, chosen.ranks) end
    if #lines > 1 then e.picks = { kind = kind, ref = ref, lines = lines } end
end

-- A class buff: its lines with a rank known (Self buffs calls this).
function Picker.ClassBuff(e, buff)
    if not on() then return end
    local lines = {}
    for _, line in ipairs(buff.lines) do
        local ranks = knownRanks(line)
        if #ranks > 0 then lines[#lines + 1] = { key = line[1], ranks = ranks } end
    end
    local actions = BL.Reminder.Section("self").classActions
    applySpells(e, lines, type(actions) == "table" and actions[buff.key] or {}, "class", buff.key)
end

-- A spell group: its members you know.
function Picker.Group(e, group)
    if not on() then return end
    local S = BL.ReminderSelf
    local lines = {}
    for _, id in ipairs(group.ids or {}) do
        local name = H().spellName(id)
        local ranks = {}
        for _, x in ipairs(S.RanksOf(id)) do
            if H().known(x) and H().spellName(x) == name then ranks[#ranks + 1] = x end
        end
        table.sort(ranks)
        if #ranks > 0 then lines[#lines + 1] = { key = id, ranks = ranks } end
    end
    applySpells(e, lines, group, "group", e.group)
end

-- ---------------------------------------------------------------------
-- Saving a choice
-- ---------------------------------------------------------------------

local function spellSettings(picks)
    if picks.kind == "class" then
        local all = copy(BL.Reminder.Section("self").classActions) or {}
        all[picks.ref] = all[picks.ref] or {}
        return all[picks.ref], function() save("self.classActions", all) end
    end
    local groups = copy(BL.Reminder.Section("self").groups) or {}
    local g = groups[picks.ref]
    if not g then return nil end
    return g, function() save("self.groups", groups) end
end

local function pickSpell(picks, key)
    local s, commit = spellSettings(picks)
    if not s then return end
    s.castSpellID = key
    commit()
end

-- The wheel over a spell: a rank up (delta > 0) or down; at the top the pin goes.
local function wheel(picks, key, delta)
    local line
    for _, l in ipairs(picks.lines) do if l.key == key then line = l end end
    if not line then return nil end
    local s, commit = spellSettings(picks)
    if not s then return nil end
    s.castRanks = s.castRanks or {}
    local current = rankOf(line.ranks, s.castRanks[key])
    local at = #line.ranks
    for i, id in ipairs(line.ranks) do if id == current then at = i end end
    at = math.max(1, math.min(#line.ranks, at + (delta > 0 and 1 or -1)))
    s.castRanks[key] = at < #line.ranks and line.ranks[at] or nil
    if not next(s.castRanks) then s.castRanks = nil end
    commit()
    return rankNumber(line.ranks[at], line.ranks)
end

-- ---------------------------------------------------------------------
-- Opening
-- ---------------------------------------------------------------------

local openFor -- { key, sig } of the icon the ring was opened on

-- A choice's tooltip: the game's own; an item's through Parts.ItemTip, which
-- redraws it for Shift's compare.
local function drawTip(cell)
    if not GameTooltip then return end
    GameTooltip:SetOwner(cell, "ANCHOR_TOPRIGHT")
    local item, spell = cell.tipItem, cell.tipSpell
    if item and GameTooltip.SetItemByID then GameTooltip:SetItemByID(item)
    elseif spell and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(spell) end
    GameTooltip:Show()
    if item then return "item:" .. item end
end
local itemTip
local function tip(cell, spell, item)
    cell.tipItem, cell.tipSpell = item, spell
    local Parts = DUI.Win and DUI.Win.Parts
    if item and Parts and Parts.ItemTip then
        itemTip = itemTip or Parts.ItemTip(drawTip)
        itemTip(cell)
    else
        drawTip(cell)
    end
end

-- What an entry offers, as ring items: nil when there's no choice to make.
local function itemsOf(e)
    local h = H()
    local items, onPick, onWheel, tipOf = {}, nil, nil, nil
    if e.picks then
        for _, line in ipairs(e.picks.lines) do
            local s = spellSettings(e.picks) or {}
            local id = rankOf(line.ranks, (s.castRanks or {})[line.key])
            local mine = false
            for _, x in ipairs(line.ranks) do if x == e.spell then mine = true end end
            items[#items + 1] = { key = line.key, icon = h.spellIcon(id), badge = rankNumber(id, line.ranks), picked = mine, spell = id }
        end
        onPick = function(key) pickSpell(e.picks, key) end
        onWheel = function(key, delta) return wheel(e.picks, key, delta) end
    elseif e.foods then
        for id, n in pairs(e.foods) do items[#items + 1] = { key = id, icon = h.itemIcon(id), badge = n, picked = id == e.item, item = id } end
        table.sort(items, function(a, b) return a.key < b.key end)
        onPick = function(key) save("items.wellFedItem", key) end
    elseif e.choices then
        for id, n in pairs(e.choices) do items[#items + 1] = { key = id, icon = h.itemIcon(id), badge = n, picked = id == e.item, item = id } end
        table.sort(items, function(a, b) return a.key < b.key end)
        onPick = function(key)
            local class = h.myClass()
            local picks = copy(BL.Reminder.Section("items").statPick) or {}
            local value = key ~= e.autoItem and key or nil
            if e.key == "scrollsAndElixirs" then
                picks[class] = value
            else
                picks[class] = type(picks[class]) == "table" and picks[class] or {}
                picks[class][e.key] = value
            end
            save("items.statPick", picks)
        end
    end
    if #items < 2 then return nil end
    local byKey = {}
    for _, it in ipairs(items) do byKey[it.key] = it end
    tipOf = function(cell, key) local it = byKey[key]; if it then tip(cell, it.spell, it.item) end end
    return items, onPick, onWheel, tipOf
end

local function signature(e)
    local items = e and itemsOf(e)
    if not items then return nil end
    local keys = {}
    for _, it in ipairs(items) do keys[#keys + 1] = tostring(it.key) .. (it.item and (":" .. tostring(it.badge)) or "") end
    return table.concat(keys, ",")
end

-- Right-click on an icon (or its button).
function Picker.Open(tile)
    local e = tile and tile.entry
    if not e or e.sample or not on() or BL.Reminder.Fighting() then return end
    local W = DUI.Widgets
    local items, onPick, onWheel, tipOf = itemsOf(e)
    if not items or not (W and W.IconRing) then return end
    openFor = { key = e.key, sig = signature(e) }
    W.IconRing({ items = items, onPick = onPick, onWheel = onWheel, tip = tipOf })
end

local function close()
    openFor = nil
    local W = DUI.Widgets
    if W and W.CloseIconRing then W.CloseIconRing() end
end
Picker.Close = close

-- After the row changes: the ring goes when its icon went, or its choices
-- changed under it (a bag change, a spell learned).
function Picker.Validate(active)
    if not openFor then return end
    local W = DUI.Widgets
    if not (W and W.IconRingOpen and W.IconRingOpen()) then openFor = nil return end
    for _, t in ipairs(active or {}) do
        if t.entry and t.entry.key == openFor.key and not t.leaving then
            if signature(t.entry) == openFor.sig then return end
            break
        end
    end
    close()
end

BL.Reminder.handlers.picker = function(event)
    if event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" or event == "PLAYER_ENTERING_WORLD" then close() end
end
