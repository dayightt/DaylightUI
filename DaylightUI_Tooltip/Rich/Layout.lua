-- The order of a Rich card's pieces, which the player can change in the
-- Tooltips page's Design mode. A card is a list of sections; each section a
-- list of pieces (a player's guild, a creature's health bar, an item's set).
-- A line sits between two sections, never inside one.
--
-- The card builders decide what each piece holds (has) and how it draws
-- (draw); Layout.Run only puts them in order. It never reads the game, so
-- nothing here can touch a secret value.
--
-- Saved as text, one setting per card kind ("guild,zone|health,power"):
-- sections split by "|", pieces by ",". A list would be merged with the
-- default list entry by entry when the profile loads. Hiding a piece is its
-- own Show setting, so a hidden piece keeps its place for when it comes back.

local _, ns = ...
local DUI = DaylightUI

local Layout = {}
ns.RichLayout = Layout

Layout.KINDS = { "player", "mob", "item", "spell" }

local function P() return ns.RichPlayers end
local function I() return ns.RichItems end
local function S() return ns.RichSpells end

-- Each piece: key, label (its row's label), show (the setting that shows it),
-- bar (a bar: a section starting with one gets a gap instead of a line),
-- lead(prev) the gap before it: prev is the piece drawn just before it in its
-- section, or nil when it starts the card or a section after a bar's gap.
Layout.PIECES = {
    player = {
        { key = "guild", label = "Guild", show = "pieces.player.guild" },
        { key = "zone", label = "Zone", show = "pieces.player.zone" },
        { key = "ilvl", label = "Item level", show = "pieces.player.ilvl" },
        { key = "target", label = "Show who they're targeting", show = "showTarget" },
        { key = "health", label = "Health bar", show = "pieces.player.health", bar = true,
          lead = function() return P().BEFORE_BARS end },
        { key = "power", label = "Power bar", show = "pieces.player.power", bar = true,
          lead = function(prev) return prev == "health" and P().BAR_GAP or P().BEFORE_BARS end },
        { key = "buffs", label = "Friendly players' buffs", show = "buffs",
          lead = function(prev) return prev and P().BEFORE_BARS or nil end },
        { key = "addons", label = "Other addons' lines", show = "pieces.player.addons" },
    },
    mob = {
        { key = "health", label = "Health bar", show = "pieces.mob.health", bar = true,
          lead = function() return ns.RichWorld.BEFORE_BAR end },
        { key = "quests", label = "Quests", show = "pieces.mob.quests" },
        { key = "facts", label = "Small facts", show = "pieces.mob.facts" },
        { key = "target", label = "Show who they're targeting", show = "showTarget" },
        { key = "addons", label = "Other addons' lines", show = "pieces.mob.addons" },
    },
    item = {
        { key = "numbers", label = "Damage and armor", show = "pieces.item.numbers",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
        -- Stats follow the base numbers with no gap: one list of numbers.
        { key = "stats", label = "Stats", show = "pieces.item.stats",
          lead = function(prev) return prev and prev ~= "numbers" and I().GROUP_GAP or nil end },
        { key = "effects", label = "Effects", show = "pieces.item.effects",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
        { key = "set", label = "Set", show = "pieces.item.set",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
        { key = "facts", label = "Requirements", show = "pieces.item.facts",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
        { key = "quote", label = "Quote", show = "pieces.item.quote",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
        { key = "made", label = "Crafted item", show = "pieces.item.made",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
        { key = "addons", label = "Other addons' lines", show = "pieces.item.addons",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
        { key = "foot", label = "Durability and vendor price", show = "pieces.item.foot",
          lead = function(prev) return prev and I().GROUP_GAP or nil end },
    },
    spell = {
        { key = "tiles", label = "Cast, cost and range", show = "pieces.spell.tiles",
          lead = function() return S().AFTER_HEADER end },
        { key = "cooldown", label = "Cooldown countdown", show = "pieces.spell.cooldown",
          lead = function() return S().AFTER_HEADER end },
        { key = "desc", label = "Description", show = "pieces.spell.desc",
          lead = function() return S().AFTER_STRIP end },
        { key = "reagents", label = "Reagents", show = "pieces.spell.reagents",
          lead = function() return S().AFTER_STRIP end },
        { key = "facts", label = "Small facts", show = "pieces.spell.facts",
          lead = function(prev) return prev == "reagents" and S().AFTER_STRIP or nil end },
        { key = "addons", label = "Other addons' lines", show = "pieces.spell.addons" },
    },
}

-- Today's cards, piece for piece.
Layout.DEFAULT = {
    player = { { "guild", "zone", "ilvl", "target" }, { "health", "power", "buffs" }, { "addons" } },
    mob = { { "health" }, { "quests" }, { "facts", "target" }, { "addons" } },
    item = { { "numbers", "stats" }, { "effects", "set", "facts", "quote" }, { "made" }, { "addons", "foot" } },
    spell = { { "tiles", "cooldown", "desc", "reagents", "facts" }, { "addons" } },
}

local byKey = {}
for kind, list in pairs(Layout.PIECES) do
    byKey[kind] = {}
    for _, piece in ipairs(list) do byKey[kind][piece.key] = piece end
end
function Layout.Piece(kind, key) return byKey[kind] and byKey[kind][key] end

-- ---------------------------------------------------------------------
-- Saved text
-- ---------------------------------------------------------------------

function Layout.Encode(sections)
    local parts = {}
    for i, sec in ipairs(sections) do parts[i] = table.concat(sec, ",") end
    return table.concat(parts, "|")
end

function Layout.Decode(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for part in (text .. "|"):gmatch("([^|]*)|") do
        local sec = {}
        for key in part:gmatch("[^,%s]+") do sec[#sec + 1] = key end
        out[#out + 1] = sec
    end
    return out
end

-- The saved text's default, for Defaults.lua.
function Layout.DefaultText(kind) return Layout.Encode(Layout.DEFAULT[kind]) end

local function copy(sections)
    local out = {}
    for i, sec in ipairs(sections) do
        out[i] = {}
        for j, k in ipairs(sec) do out[i][j] = k end
    end
    return out
end

-- Where a piece sits in the default layout: its section and the pieces
-- before it there.
local function defaultSpot(kind, key)
    for s, sec in ipairs(Layout.DEFAULT[kind]) do
        for i, k in ipairs(sec) do
            if k == key then return s, i end
        end
    end
end

-- A layout made whole: unknown pieces and repeats dropped, empty sections
-- closed, a piece it's missing (one added in a later release) put back after
-- the piece it follows by default, or in a section of its own after the
-- pieces that come before it.
function Layout.Repair(kind, sections)
    local known = byKey[kind]
    if not known then return {} end
    local out, seen = {}, {}
    for _, sec in ipairs(type(sections) == "table" and sections or {}) do
        local keep = {}
        for _, k in ipairs(sec) do
            if known[k] and not seen[k] then
                seen[k] = true
                keep[#keep + 1] = k
            end
        end
        if #keep > 0 then out[#out + 1] = keep end
    end
    for _, piece in ipairs(Layout.PIECES[kind]) do
        local k = piece.key
        if not seen[k] then
            seen[k] = true
            local s, i = defaultSpot(kind, k)
            local placed = false
            -- After the nearest piece before it in its default section.
            local dsec = Layout.DEFAULT[kind][s]
            for j = i - 1, 1, -1 do
                for _, sec in ipairs(out) do
                    for at, other in ipairs(sec) do
                        if other == dsec[j] and not placed then
                            table.insert(sec, at + 1, k)
                            placed = true
                        end
                    end
                end
                if placed then break end
            end
            if not placed then
                -- Before the nearest piece after it in its default section.
                for j = i + 1, #dsec do
                    for _, sec in ipairs(out) do
                        for at, other in ipairs(sec) do
                            if other == dsec[j] and not placed then
                                table.insert(sec, at, k)
                                placed = true
                            end
                        end
                    end
                    if placed then break end
                end
            end
            if not placed then
                -- A section of its own, after the section holding the last
                -- piece that comes before it by default.
                local after = 0
                for _, d in ipairs(Layout.PIECES[kind]) do
                    if d.key == k then break end
                    for at, sec in ipairs(out) do
                        for _, other in ipairs(sec) do
                            if other == d.key then after = math.max(after, at) end
                        end
                    end
                end
                table.insert(out, after + 1, { k })
            end
        end
    end
    return out
end

local function cfg() return ns.Tooltip.Config() end

-- The player's layout for a kind, repaired.
function Layout.Of(kind)
    local c = cfg()
    local text = type(c) == "table" and DUI.DB.GetPath(c, "layout." .. kind) or nil
    if type(text) ~= "string" or text == "" then return copy(Layout.DEFAULT[kind] or {}) end
    return Layout.Repair(kind, Layout.Decode(text))
end

function Layout.ShowKey(kind, key)
    local piece = Layout.Piece(kind, key)
    return piece and piece.show
end

function Layout.Shown(kind, key)
    local k = Layout.ShowKey(kind, key)
    local c = cfg()
    if not k or type(c) ~= "table" then return true end
    return DUI.DB.GetPath(c, k) ~= false
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

local function leadOf(kind, key, prev)
    local piece = Layout.Piece(kind, key)
    return piece and piece.lead and piece.lead(prev) or nil
end

-- Draws the card's pieces in the player's order. pieces[key] = { has = bool,
-- draw = fn(p), keep = bool (shown whatever its Show setting: the card
-- decides, as other addons' lines do with Daylight UI plugins' pieces) }.
-- sections: a layout to draw instead of the player's (the Design sample's
-- drag in progress). Records p.spans[key] = { from, to } in p.items.
-- Returns whether it drew anything.
function Layout.Run(p, kind, pieces, sections)
    local Panel = ns.RichPanel
    p.spans = {}
    local drewAny = false
    for _, sec in ipairs(sections or Layout.Of(kind)) do
        local prev
        for _, key in ipairs(sec) do
            local piece = pieces[key]
            if piece and piece.has and (piece.keep or Layout.Shown(kind, key)) then
                local def = Layout.Piece(kind, key)
                if prev == nil and drewAny then
                    -- A new section: a line, or a gap when it starts with a
                    -- bar (the bar reads as the divider).
                    if def and def.bar then
                        local gap = leadOf(kind, key, nil)
                        if gap then Panel.Gap(p, gap) end
                    else
                        Panel.Rule(p)
                    end
                else
                    local gap = leadOf(kind, key, prev)
                    if gap then Panel.Gap(p, gap) end
                end
                local from = p.count + 1
                piece.draw(p)
                p.spans[key] = { from = from, to = p.count }
                prev, drewAny = key, true
            end
        end
    end
    return drewAny
end

-- Takes a trailing gap off the card (its room under the header, kept only
-- when something comes under it).
function Layout.DropGap(p)
    while p.count > 0 and p.items[p.count].kind == "gap" do
        p.items[p.count] = nil
        p.count = p.count - 1
    end
end

-- ---------------------------------------------------------------------
-- Moving (Design mode)
-- ---------------------------------------------------------------------

-- The layout with a piece taken out, sections left empty closed.
function Layout.Without(sections, piece)
    local out = {}
    for _, sec in ipairs(sections) do
        local keep = {}
        for _, k in ipairs(sec) do
            if k ~= piece then keep[#keep + 1] = k end
        end
        if #keep > 0 then out[#out + 1] = keep end
    end
    return out
end

-- Where a piece is: its section and index.
function Layout.Find(sections, piece)
    for s, sec in ipairs(sections) do
        for i, k in ipairs(sec) do
            if k == piece then return s, i end
        end
    end
end

-- Only the pieces the card shows (visible[key]), and which section of the
-- whole layout each of its sections is.
local function onCard(sections, visible)
    local out, map = {}, {}
    for s, sec in ipairs(sections) do
        local keep = {}
        for _, k in ipairs(sec) do
            if visible[k] then keep[#keep + 1] = k end
        end
        if #keep > 0 then
            out[#out + 1] = keep
            map[#out] = s
        end
    end
    return out, map
end

-- The layout as the card shows it without a piece: the shown pieces only.
function Layout.Shows(sections, piece, visible) return (onCard(Layout.Without(sections, piece), visible)) end

-- Every place a piece can land on the card, top to bottom, as the card shows
-- it without that piece: { section, index, new }. new: the line above that
-- section (or past the last), where a new section starts; else after the
-- index-th piece of the section (0 = at its top).
function Layout.Slots(sections, piece, visible)
    local shown = onCard(Layout.Without(sections, piece), visible)
    local out = {}
    for s, sec in ipairs(shown) do
        out[#out + 1] = { section = s, index = 0, new = true }
        for i = 0, #sec do out[#out + 1] = { section = s, index = i } end
    end
    out[#out + 1] = { section = #shown + 1, index = 0, new = true }
    return out
end

-- A new layout with the piece at a slot from Layout.Slots. Pieces the card
-- doesn't show stay where they are.
function Layout.Move(sections, piece, slot, visible)
    local rest = Layout.Without(sections, piece)
    local shown, map = onCard(rest, visible)
    local out = copy(rest)
    if slot.new then
        local at = map[slot.section] or (#out + 1)
        table.insert(out, at, { piece })
        return out
    end
    local s = map[slot.section]
    if not s then
        out[#out + 1] = { piece }
        return out
    end
    local sec, vis = out[s], shown[slot.section]
    local at
    if slot.index <= 0 then
        at = 1
        for i, k in ipairs(sec) do
            if k == vis[1] then at = i break end
        end
    else
        at = #sec + 1
        for i, k in ipairs(sec) do
            if k == vis[slot.index] then at = i + 1 break end
        end
    end
    table.insert(sec, at, piece)
    return out
end

-- Which slot the piece is at now, among Layout.Slots.
function Layout.SlotOf(sections, piece, visible, slots)
    local shown = onCard(sections, visible)
    local before, s = 0, nil
    for i, sec in ipairs(shown) do
        for j, k in ipairs(sec) do
            if k == piece then s, before = i, j - 1 end
        end
    end
    if not s then return nil end
    -- Its section without it: gone when it was alone there.
    local alone = #shown[s] == 1
    for i, sl in ipairs(slots) do
        if alone and sl.new and sl.section == s then return i end
        if not alone and not sl.new and sl.section == s and sl.index == before then return i end
    end
end

-- The piece one slot up (dir -1) or down (1): past a neighbour, onto a line
-- of its own, or into the next section. Returns the new layout, or nil at
-- the top or bottom.
function Layout.Step(sections, piece, dir, visible)
    local slots = Layout.Slots(sections, piece, visible)
    local at = Layout.SlotOf(sections, piece, visible, slots)
    if not at then return nil end
    local to = slots[at + dir]
    if not to then return nil end
    return Layout.Move(sections, piece, to, visible)
end
