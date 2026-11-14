-- Categories: which group each item goes in, plus group order, names, collapsed
-- state, custom groups and pinned items.
--
-- An item goes to, in order: the group it's pinned to (by item ID); the first
-- custom group whose search matches (a custom group without a search only takes
-- what's pinned to it); the first built-in group in Categories.PRIORITY whose
-- test passes (so Junk beats Weapons, and set or quest items beat Junk).
-- Anything left goes to Other. Keyring slots are Keys, empty slots are Empty.
--
-- Settings (module "Bags"): groupOrder (keys, nil = default), groupNames
-- (key -> name), groupColors (key -> { r, g, b }), customGroups (list of { key, name, search? }), collapsed
-- (key -> true), pins (item ID -> key), removedGroups (built-in key -> true,
-- see Cat.Delete), recentMinutes.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Cat = {}
ns.Categories = Cat

local C = ns.Search.CLASS
local K = ns.Search.KEYWORDS
Cat.HEARTHSTONE = 6948

-- Built-in groups in default order. A renamed one keeps the player's name in
-- groupNames. breakBefore / breakAfter start a new row of groups. color is the
-- group's default heading color; ink names a Style.INK one instead and quality
-- the item quality whose color the game uses (read when painting).
Cat.BUILTIN = {
    { key = "recent", name = L["Recent"], breakAfter = true },
    { key = "hearthstone", color = { 0.45, 0.72, 1.0 }, name = L["Hearthstone"] },
    { key = "consumable", color = { 0.45, 0.86, 0.5 }, name = L["Consumables"] },
    { key = "quest", color = { 1.0, 0.82, 0.25 }, name = L["Quest items"] },
    { key = "sets", color = { 0.72, 0.56, 1.0 }, name = L["Equipment sets"] },
    { key = "weapon", color = { 0.96, 0.52, 0.42 }, name = L["Weapons"] },
    { key = "armor", color = { 0.62, 0.74, 0.92 }, name = L["Armor"] },
    { key = "reagent", color = { 0.35, 0.82, 0.8 }, name = L["Reagents"] },
    { key = "tradegoods", color = { 0.88, 0.66, 0.4 }, name = L["Trade goods"] },
    { key = "recipe", color = { 0.96, 0.62, 0.82 }, name = L["Recipes"] },
    { key = "ammo", color = { 0.67, 0.83, 0.45 }, name = L["Ammo"] },
    { key = "container", color = { 0.78, 0.58, 0.38 }, name = L["Containers"] },
    { key = "quiver", color = { 0.67, 0.83, 0.45 }, name = L["Quivers"] },
    { key = "key", color = { 0.92, 0.8, 0.32 }, name = L["Keys"] },
    { key = "misc", ink = "LABEL", name = L["Miscellaneous"] },
    { key = "other", ink = "LABEL", name = L["Other"] },
    { key = "junk", quality = 0, name = L["Junk"] },
    { key = "empty", ink = "LABEL", name = L["Empty"] },
}
Cat.BY_KEY = {}
for _, g in ipairs(Cat.BUILTIN) do Cat.BY_KEY[g.key] = g end

-- Which built-in group an item goes to: the first whose test passes. Sets and
-- quest items come before Junk because Junk gets sold at vendors, and a gray
-- item kept in a set or needed for a quest must never be.
Cat.PRIORITY = { "recent", "hearthstone", "sets", "quest", "junk", "key", "consumable", "weapon", "armor",
                 "reagent", "tradegoods", "recipe", "ammo", "quiver", "container", "misc" }
Cat.TESTS = {
    recent = function(f) return f.recent == true end,
    hearthstone = function(f) return f.itemID == Cat.HEARTHSTONE end,
    -- Never a set or quest item, even if those groups were deleted (Cat.Delete).
    junk = function(f) return f.quality == 0 and not f.locked and not f.inSet and not K.quest(f) end,
    sets = function(f) return f.inSet == true end,
    quest = K.quest,
    key = K.key,
    consumable = K.consumable,
    weapon = K.weapon,
    armor = K.armor,
    reagent = function(f) return f.classID == C.reagent end,   -- not the search keyword's meaning (includes trade goods)
    tradegoods = K.tradegoods,
    recipe = K.recipe,
    ammo = function(f) return f.classID == C.projectile end,
    quiver = function(f) return f.classID == C.quiver end,
    container = K.container,
    misc = function(f) return f.classID == C.misc end,
}

local function db() return ns.module and ns.module.db or {} end
local function tbl(key)
    local d = db()
    if type(d[key]) ~= "table" then d[key] = {} end
    return d[key]
end

-- Groups

function Cat.Custom() return tbl("customGroups") end

local function customByKey(key)
    for _, g in ipairs(Cat.Custom()) do
        if g.key == key then return g end
    end
end

-- Built-in groups the player deleted (key -> true): their items fall through to
-- the next match. Other and Empty catch whatever's left, so they can't be deleted.
Cat.KEEP = { other = true, empty = true }
local function removed() return tbl("removedGroups") end

-- A group: { key, name, breakBefore, breakAfter, custom, search }.
function Cat.Get(key)
    if removed()[key] then return nil end
    local g = Cat.BY_KEY[key]
    local custom = not g and customByKey(key)
    if not g and not custom then return nil end
    local base = g or custom
    return { key = key, name = tbl("groupNames")[key] or base.name, breakBefore = base.breakBefore,
             breakAfter = base.breakAfter, custom = custom and true or nil, search = custom and custom.search or nil }
end

-- Groups in order: the saved order, with anything missing added where it
-- belongs (custom groups after Recent, built-ins in their default spot).
function Cat.Order()
    local saved = db().groupOrder
    local out, seen = {}, {}
    local function add(key)
        if not seen[key] and Cat.Get(key) then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    if type(saved) == "table" then
        for _, key in ipairs(saved) do add(key) end
    end
    local defaults = {}
    for _, g in ipairs(Cat.BUILTIN) do
        defaults[#defaults + 1] = g.key
        if g.key == "recent" then
            for _, c in ipairs(Cat.Custom()) do defaults[#defaults + 1] = c.key end
        end
    end
    for i, key in ipairs(defaults) do
        if not seen[key] and Cat.Get(key) then
            -- Right after the group that precedes it in the default order.
            local after = defaults[i - 1]
            local at = #out + 1
            for j, k in ipairs(out) do if k == after then at = j + 1 end end
            table.insert(out, at, key)
            seen[key] = true
        end
    end
    return out
end

local function changed()
    if ns.Relayout then ns.Relayout() end
    if ns.FillAll then ns.FillAll() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function Cat.Move(key, by)
    local order = Cat.Order()
    for i, k in ipairs(order) do
        if k == key then
            local j = i + by
            if j < 1 or j > #order then return end
            order[i], order[j] = order[j], order[i]
            db().groupOrder = order
            changed()
            return
        end
    end
end

-- A group's color: the player's own, else its default. Recent has none (it
-- keeps the accent), so it returns nil. Read when painting, never kept.
local function validColor(c)
    return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

function Cat.DefaultColor(key)
    if key == "recent" then return nil end
    local g = Cat.BY_KEY[key]
    local INK = DUI.Style.INK
    if not g then
        local c = INK.TEXT
        return c[1], c[2], c[3]
    end
    if g.color then return g.color[1], g.color[2], g.color[3] end
    if g.quality then
        local r, gr, b
        if C_Item and C_Item.GetItemQualityColor then r, gr, b = C_Item.GetItemQualityColor(g.quality) end
        if type(r) == "number" and type(gr) == "number" and type(b) == "number" then return r, gr, b end
        local q = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[g.quality]
        if type(q) == "table" and type(q.r) == "number" then return q.r, q.g, q.b end
        return 0.62, 0.62, 0.62
    end
    local c = INK[g.ink or "LABEL"]
    return c[1], c[2], c[3]
end

function Cat.Color(key)
    if key == "recent" then return nil end
    local own = tbl("groupColors")[key]
    if validColor(own) then return own[1], own[2], own[3] end
    return Cat.DefaultColor(key)
end

function Cat.HasOwnColor(key) return validColor(tbl("groupColors")[key]) end

function Cat.SetColor(key, c)
    if not Cat.Get(key) or key == "recent" or not validColor(c) then return end
    tbl("groupColors")[key] = { c[1], c[2], c[3] }
    changed()
end

function Cat.ResetColor(key)
    if not Cat.HasOwnColor(key) then return end
    tbl("groupColors")[key] = nil
    changed()
end

-- A group's name in its color, for a menu row.
function Cat.ColorText(key, text)
    local r, g, b = Cat.Color(key)
    if not r then return text end
    return DUI.Win.Parts.Hex({ r, g, b }) .. text .. "|r"
end

function Cat.Rename(key, name)
    if type(name) ~= "string" or name == "" or not Cat.Get(key) then return end
    tbl("groupNames")[key] = name
    changed()
end

-- The search is optional; without one the group holds what's moved into it.
function Cat.AddCustom(name, search)
    if type(name) ~= "string" or name == "" then return nil end
    if search == "" then search = nil end
    local list = Cat.Custom()
    local n = #list + 1
    local key = "custom" .. n
    while customByKey(key) do n = n + 1; key = "custom" .. n end
    list[#list + 1] = { key = key, name = name, search = search }
    changed()
    return key
end

-- An empty search removes it.
function Cat.SetSearch(key, search)
    local g = customByKey(key)
    if g and type(search) == "string" then
        g.search = search ~= "" and search or nil
        changed()
    end
end

local function dropPins(key)
    local pins = tbl("pins")
    for id, k in pairs(pins) do if k == key then pins[id] = nil end end
end

function Cat.DeleteCustom(key)
    local list = Cat.Custom()
    for i, g in ipairs(list) do
        if g.key == key then
            table.remove(list, i)
            dropPins(key)
            tbl("groupColors")[key] = nil
            changed()
            return
        end
    end
end

function Cat.CanDelete(key)
    return Cat.Get(key) ~= nil and not Cat.KEEP[key]
end

-- Custom groups are gone for good; built-in ones wait in Cat.Removed().
function Cat.Delete(key)
    if not Cat.CanDelete(key) then return end
    if not Cat.BY_KEY[key] then return Cat.DeleteCustom(key) end
    removed()[key] = true
    dropPins(key)
    changed()
end

-- Deleted built-in groups, in default order.
function Cat.Removed()
    local out = {}
    for _, g in ipairs(Cat.BUILTIN) do
        if removed()[g.key] then out[#out + 1] = g.key end
    end
    return out
end

function Cat.Restore(key)
    if not removed()[key] then return end
    removed()[key] = nil
    changed()
end

function Cat.IsCollapsed(key) return tbl("collapsed")[key] == true end
function Cat.ToggleCollapsed(key)
    local c = tbl("collapsed")
    c[key] = not c[key] or nil
    changed()
end

-- Empties Recent now (right-click its heading). Each item goes to its own group,
-- and the game's new-item flags are cleared too or they'd bring them back.
function Cat.ClearRecent()
    wipe(Cat.recent)
    if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end
    changed()
end

-- Pins

function Cat.Pin(itemID, key)
    if type(itemID) ~= "number" or not Cat.Get(key) or key == "empty" or key == "recent" then return end
    tbl("pins")[itemID] = key
    changed()
end

function Cat.Unpin(itemID)
    if type(itemID) ~= "number" then return end
    tbl("pins")[itemID] = nil
    changed()
end

function Cat.PinOf(itemID) return type(itemID) == "number" and tbl("pins")[itemID] or nil end

function Cat.ClearPins()
    db().pins = {}
    changed()
end

-- Sharing custom groups: each group's name, search and moved items, packed into
-- text (DUI.Profiles.Pack) to paste on another character or give to a friend.

Cat.SHARE_PREFIX = "!DUIBags1_"
Cat.SHARE_MAX = 100          -- max groups read from one string
Cat.SHARE_ITEMS = 500        -- max items per group

-- { v = 1, groups = { { name, search?, items = { itemID... } } } }, or nil if
-- there are no custom groups.
function Cat.ShareTable()
    local pinned = {}
    for id, k in pairs(tbl("pins")) do
        if type(id) == "number" then
            pinned[k] = pinned[k] or {}
            table.insert(pinned[k], id)
        end
    end
    local groups = {}
    for _, key in ipairs(Cat.Order()) do
        local g = customByKey(key)
        if g then
            local items = pinned[key] or {}
            table.sort(items)
            local own = tbl("groupColors")[key]
            groups[#groups + 1] = { name = tbl("groupNames")[key] or g.name, search = g.search, items = items,
                                    color = validColor(own) and { own[1], own[2], own[3] } or nil }
        end
    end
    if #groups == 0 then return nil end
    return { v = 1, groups = groups }
end

function Cat.Export()
    local t = Cat.ShareTable()
    if not t then return nil, L["you have no groups of your own yet"] end
    return DUI.Profiles.Pack(t, Cat.SHARE_PREFIX)
end

-- Baganator's categories export (plain JSON from its category options):
-- { version, categories = { { name, priority, search } }, modifications =
-- { { source, items, pets, group } }, hidden = { source }, order = { source } }.
-- A source is a custom category's name or "default_" plus a built-in key; older
-- exports kept items in the categories themselves. Anything else is ignored, so
-- a newer export still brings over what's recognized.

-- Baganator's built-in categories that have a group here: their moved items go
-- to that group instead of a copy of it.
Cat.BAGANATOR_BUILTIN = {
    hearthstone = "hearthstone", potion = "consumable", food = "consumable", consumable = "consumable",
    reagent = "reagent", auto_equipment_sets = "sets", weapon = "weapon", armor = "armor", quiver = "quiver",
    container = "container", tradegoods = "tradegoods", recipe = "recipe", questitem = "quest", key = "key",
    miscellaneous = "misc", other = "other", junk = "junk",
}

-- Baganator's other built-in categories, named for the player: the game's own
-- word for an item class where there is one, else a plain name.
Cat.BAGANATOR_CLASS = { gem = 3, itemenhancement = 8, battlepet = 17, profession = 19 }
Cat.BAGANATOR_NAMES = {
    gem = L["Gems"], itemenhancement = L["Item enhancements"], battlepet = L["Battle pets"],
    profession = L["Profession items"], toy = L["Toys"], auto_inventory_slots = L["Gear by slot"],
    auto_recents = L["Recent"], special_empty = L["Empty"],
}

function Cat.BaganatorName(base)
    local class = Cat.BAGANATOR_CLASS[base]
    if class and C_Item and C_Item.GetItemClassInfo then
        local ok, name = pcall(C_Item.GetItemClassInfo, class)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if base == "toy" and type(_G.TOY) == "string" and _G.TOY ~= "" then return _G.TOY end
    return Cat.BAGANATOR_NAMES[base] or (string.gsub(base, "_", " "))
end

local function isText(s) return type(s) == "string" and s ~= "" end

local function itemIDs(list, into)
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if type(id) == "number" and id > 0 and id == math.floor(id) and #into < Cat.SHARE_ITEMS then
            into[#into + 1] = id
        end
    end
end

-- A list for Cat.ImportShared (plus .notes: what was left out, in plain words),
-- or nil and the reason.
function Cat.ReadBaganator(text)
    local E = C_EncodingUtil
    if type(E) ~= "table" or type(E.DeserializeJSON) ~= "function" then
        return nil, L["this game client can't read bag groups"]
    end
    -- JSON escapes its own line breaks, so any here are the paste box's wrapping.
    text = string.gsub(text, "[\r\n]", "")
    local ok, v = pcall(E.DeserializeJSON, text)
    if not ok or type(v) ~= "table" or (type(v.categories) ~= "table" and type(v.modifications) ~= "table") then
        return nil, L["that isn't a Daylight UI or Baganator bag groups string"]
    end
    local notes, out, bySource, skipped, gone = {}, {}, {}, {}, {}
    local customs = {}
    for i, c in ipairs(type(v.categories) == "table" and v.categories or {}) do
        if #customs >= Cat.SHARE_MAX then break end
        if type(c) == "table" and isText(c.name) then
            customs[#customs + 1] = { c = c, i = i, priority = type(c.priority) == "number" and c.priority or 0 }
        end
    end
    -- Baganator tries the highest priority first; here the first group in the
    -- list wins, so the order carries it over.
    table.sort(customs, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.i < b.i
    end)
    for _, e in ipairs(customs) do
        local c = e.c
        local name = string.sub(c.name, 1, 60)
        local search, dropped
        if type(c.search) == "string" then search, dropped = ns.Search.FromSyndicator(c.search) end
        if dropped and #dropped > 0 then
            notes[#notes + 1] = string.format(L["%s (left out: %s)"], name, table.concat(dropped, ", "))
        end
        local g = { name = name, search = search, items = {} }
        itemIDs(c.items, g.items)
        out[#out + 1] = g
        bySource[name], bySource[c.name] = g, g
        if isText(c.source) then bySource[c.source] = g end
    end
    local pets, grouped = false, false
    local builtin = {}
    for _, m in ipairs(type(v.modifications) == "table" and v.modifications or {}) do
        local source = type(m) == "table" and (isText(m.source) and m.source or isText(m.name) and m.name) or nil
        if source then
            local g = bySource[source]
            local base = not g and string.match(source, "^default_(.+)$")
            local key = base and Cat.BAGANATOR_BUILTIN[base]
            local hasItems = type(m.items) == "table" and #m.items > 0
            if key and not g and not Cat.Get(key) then
                -- Deleted here: never pin to it, say so instead.
                if hasItems then gone[#gone + 1] = tbl("groupNames")[key] or Cat.BY_KEY[key].name end
            elseif key or g then
                if not g then
                    g = builtin[key]
                    if not g then
                        g = { builtin = key, items = {} }
                        builtin[key] = g
                        out[#out + 1] = g
                    end
                end
                itemIDs(m.items, g.items)
            elseif hasItems then
                skipped[#skipped + 1] = base and Cat.BaganatorName(base) or source
            end
            if type(m.pets) == "table" and #m.pets > 0 then pets = true end
            if isText(m.group) then grouped = true end
        end
    end
    if #skipped > 0 then
        notes[#notes + 1] = string.format(L["items moved to %s"], table.concat(skipped, ", "))
    end
    for _, name in ipairs(gone) do
        notes[#notes + 1] = string.format(L["items moved to %s, a group you deleted"], name)
    end
    if pets then notes[#notes + 1] = L["battle pets"] end
    if grouped then notes[#notes + 1] = L["grouping by type or quality"] end
    for _, source in ipairs(type(v.order) == "table" and v.order or {}) do
        if type(source) == "string" and (source == "----" or string.sub(source, 1, 1) == "_") then
            notes[#notes + 1] = L["sections and dividers"]
            break
        end
    end
    if type(v.hidden) == "table" and #v.hidden > 0 then notes[#notes + 1] = L["hidden categories"] end
    if #out == 0 then return nil, L["it has no groups in it"] end
    out.baganator, out.notes = true, notes
    return out
end

-- The paste box takes spaces out of long pasted text so it wraps. JSON keeps
-- them inside names and searches, so the text as pasted wins while it's the
-- same apart from spaces and line breaks.
function Cat.Unwrapped(shown, typed)
    if type(typed) ~= "string" or type(shown) ~= "string" then return shown end
    if string.gsub(typed, "%s", "") == string.gsub(shown, "%s", "") then return typed end
    return shown
end

-- Parses and validates shared text: a list of { name, search, items, color? }, or nil
-- plus the reason. A Baganator export is read too (Cat.ReadBaganator).
function Cat.ReadShared(text)
    if type(text) == "string" and string.match(text, "^%s*{") then return Cat.ReadBaganator(text) end
    local v, why = DUI.Profiles.Unpack(text, Cat.SHARE_PREFIX)
    if not v then
        local said = { empty = L["nothing pasted"], prefix = L["that isn't a Daylight UI bag groups string"],
                       client = L["this game client can't read profiles"],
                       damaged = L["the string is damaged (was all of it copied?)"] }
        return nil, said[why]
    end
    if type(v.v) ~= "number" or v.v > 1 then return nil, L["it's from a newer Daylight UI; update to import it"] end
    local out = {}
    for _, g in ipairs(type(v.groups) == "table" and v.groups or {}) do
        if #out >= Cat.SHARE_MAX then break end
        if type(g) == "table" and type(g.name) == "string" and g.name ~= "" then
            local items = {}
            for _, id in ipairs(type(g.items) == "table" and g.items or {}) do
                if type(id) == "number" and id > 0 and id == math.floor(id) and #items < Cat.SHARE_ITEMS then
                    items[#items + 1] = id
                end
            end
            local search = type(g.search) == "string" and g.search ~= "" and g.search or nil
            local color
            if validColor(g.color) then
                color = { math.max(0, math.min(1, g.color[1])), math.max(0, math.min(1, g.color[2])),
                          math.max(0, math.min(1, g.color[3])) }
            end
            out[#out + 1] = { name = string.sub(g.name, 1, 60), search = search, items = items, color = color }
        end
    end
    if #out == 0 then return nil, L["it has no groups in it"] end
    return out
end

-- Adds shared groups. One with the same name as an existing custom group updates
-- it (search, items and color); others are added. Returns how many groups, and
-- how many items went to each built-in group (key -> count).
function Cat.ImportShared(list)
    local byName = {}
    for _, g in ipairs(Cat.Custom()) do byName[tbl("groupNames")[g.key] or g.name] = g end
    local pins = tbl("pins")
    local count, moved = 0, {}
    for _, sg in ipairs(list) do
        local g = sg.name and byName[sg.name]
        local key
        if sg.builtin then
            -- Items moved to one of Baganator's own categories go to the group here.
            key = Cat.Get(sg.builtin) and sg.builtin
        elseif g then
            count = count + 1
            key = g.key
            if sg.search then g.search = sg.search end
        else
            local list2 = Cat.Custom()
            local n = #list2 + 1
            key = "custom" .. n
            while customByKey(key) do n = n + 1; key = "custom" .. n end
            list2[#list2 + 1] = { key = key, name = sg.name, search = sg.search }
            byName[sg.name] = list2[#list2]
            count = count + 1
        end
        if key then
            for _, id in ipairs(sg.items) do pins[id] = key end
            if sg.builtin and #sg.items > 0 then moved[key] = (moved[key] or 0) + #sg.items end
            if sg.color then tbl("groupColors")[key] = { sg.color[1], sg.color[2], sg.color[3] } end
        end
    end
    changed()
    return count, moved
end

-- What an import did, as chat lines. Junk is said on its own: the next vendor
-- sells it.
function Cat.ImportLines(count, moved, notes)
    local lines = {}
    if count > 0 or not next(moved) then lines[1] = string.format(L["Imported %d bag groups."], count) end
    for _, key in ipairs(Cat.Order()) do
        local n = moved[key]
        if n and key == "junk" then
            lines[#lines + 1] = n == 1 and L["1 item marked as junk. It'll be sold at the next vendor."]
                or string.format(L["%d items marked as junk. They'll be sold at the next vendor."], n)
        elseif n then
            lines[#lines + 1] = n == 1 and string.format(L["1 item moved to %s."], Cat.Get(key).name)
                or string.format(L["%d items moved to %s."], n, Cat.Get(key).name)
        end
    end
    if type(notes) == "table" and #notes > 0 then
        lines[#lines + 1] = string.format(L["Not brought over from Baganator: %s."], table.concat(notes, "; "))
    end
    return lines
end

-- Locks

-- A locked item is never sold or disenchanted: the junk seller skips it, it never
-- counts as junk, and Guard.lua blocks the clicks. Stored by item ID (every copy)
-- in "locks", like pins.
function Cat.IsLocked(itemID) return type(itemID) == "number" and tbl("locks")[itemID] == true end
DUI.ItemLocked = Cat.IsLocked   -- used by the NPC window's Sell junk

function Cat.ToggleLock(itemID)
    if type(itemID) ~= "number" then return end
    local locks = tbl("locks")
    locks[itemID] = not locks[itemID] or nil
    changed()
    DUI.Fire("ItemLockChanged")
end

-- Recent

-- Items the game flags as new, remembered per item until the timeout (the
-- game's flag clears on hover, Recent keeps it a while longer).
Cat.recent = {}

function Cat.IsRecent(bag, slot, itemID)
    local now = GetTime()
    if C_NewItems and C_NewItems.IsNewItem then
        local ok, new = pcall(C_NewItems.IsNewItem, bag, slot)
        if ok and new and itemID then Cat.recent[itemID] = Cat.recent[itemID] or now end
    end
    local seen = itemID and Cat.recent[itemID]
    if not seen then return false end
    local minutes = db().recentMinutes or 15
    if now - seen > minutes * 60 then
        Cat.recent[itemID] = nil
        return false
    end
    return true
end

-- Item menu (Alt-right-click an item): lock first, then its slot (bag-by-bag
-- view) or its group (categories view only, groups mean nothing elsewhere).
-- Every row shows without scrolling, up to Cat.MENU_ROWS; the menu's usual 12
-- cut off the last entries. A kept empty slot only offers the option to free it.
Cat.MENU_ROWS = 20


-- Manual junk (menu row or key binding): an item put in Junk sells with the rest
-- at a vendor. Marking a locked item unlocks it, since the player asked for it to
-- go, and a deleted Junk group comes back for it.
function Cat.CanMarkJunk(info)
    return type(info) == "table" and type(info.itemID) == "number" and not info.hasNoValue
end

function Cat.IsMarkedJunk(itemID) return Cat.PinOf(itemID) == "junk" end

function Cat.ToggleJunk(itemID, link)
    if type(itemID) ~= "number" then return end
    local name = link or tostring(itemID)
    if Cat.IsMarkedJunk(itemID) then
        Cat.Unpin(itemID)
        DUI.Print(string.format(L["%s is no longer junk."], name))
        return false
    end
    if removed().junk then removed().junk = nil end
    if Cat.IsLocked(itemID) then tbl("locks")[itemID] = nil end
    Cat.Pin(itemID, "junk")
    DUI.Print(string.format(L["%s will be sold as junk."], name))
    return true
end

-- Key binding (Bindings.xml): acts on the bag item under the mouse.
function Cat.JunkUnderMouse()
    local foci = type(GetMouseFoci) == "function" and GetMouseFoci() or nil
    local btn = type(foci) == "table" and foci[1] or nil
    if type(btn) ~= "table" or btn.dluiShown == nil or type(btn.GetParent) ~= "function" then return end
    local holder = btn:GetParent()
    local bag, slot = holder and holder:GetID(), btn:GetID()
    if type(bag) ~= "number" or (ns.Saved and bag >= ns.Saved.BASE) then return end
    local info = ns.Items.InfoAt(bag, slot)
    if Cat.CanMarkJunk(info) then Cat.ToggleJunk(info.itemID, info.hyperlink) end
end
DUI.BagsMarkJunk = function() Cat.JunkUnderMouse() end
_G.BINDING_NAME_DAYLIGHTUI_BAGS_JUNK = L["Mark the bag item under the mouse as junk"]
_G.BINDING_HEADER_DAYLIGHTUI_BAGS = string.format(L["Daylight UI: %s"], L["Bags"])

-- What Lock or Unlock does, beside its row while the mouse is on it. The menu
-- only says which row the mouse entered, so the row itself hides the tip when
-- the mouse leaves it or the menu closes.
local function lockTipOff(row)
    if Cat.lockTipRow ~= row then return end
    Cat.lockTipRow = nil
    GameTooltip:Hide()
end

local function lockTip(key, locked)
    if Cat.lockTipRow then lockTipOff(Cat.lockTipRow) end
    if key ~= "lock" then return end
    local W, row = DUI.Widgets, nil
    for i = 1, Cat.MENU_ROWS do
        local r = W.MenuRow(i)
        if not r then break end
        if r.key == "lock" then
            row = r
            break
        end
    end
    if not row then return end
    if not row.dluiLockTip then
        row.dluiLockTip = true
        row:HookScript("OnLeave", lockTipOff)
        row:HookScript("OnHide", lockTipOff)
    end
    Cat.lockTipRow = row
    local Tips = DUI.Tips
    GameTooltip:Hide()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    Tips.Clear()
    Tips.Title(locked and L["Unlock"] or L["Lock"])
    Tips.Text(locked and L["Can be sold again."] or L["Never sold or disenchanted."])
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

function Cat.Menu(btn)
    local holder = btn:GetParent()
    local bag, slot = holder:GetID(), btn:GetID()
    local info = ns.Items.InfoAt(bag, slot)
    local Keep = ns.Keep
    local keepable = Keep.Offered(btn, bag, slot)
    local keptSlot = Keep.At(bag, slot) ~= nil
    local keepRow = keptSlot and L["Stop keeping"] or L["Keep in this slot"]
    if not info or type(info.itemID) ~= "number" then
        if keepable and keptSlot then
            DUI.Widgets.OpenMenu(btn, { "keep" }, { keep = keepRow }, nil, function() Keep.Toggle(bag, slot) end,
                nil, { atCursor = true })
        end
        return
    end
    local itemID = info.itemID
    local current = Cat.Assign(Cat.Facts(holder:GetID(), btn:GetID(), info), "bags")
    local keys, values = { "lock" }, {}
    local locked = Cat.IsLocked(itemID)
    values.lock = locked and L["Unlock"] or L["Lock"]
    if keepable then
        keys[#keys + 1] = "keep"
        values.keep = keepRow
    end
    -- Junk in any view; for a gray item (junk already), Lock is how to say "never".
    if Cat.CanMarkJunk(info) and (current ~= "junk" or Cat.IsMarkedJunk(itemID)) then
        keys[#keys + 1] = "junkmark"
        values.junkmark = Cat.IsMarkedJunk(itemID) and L["Not junk"] or L["Sell as junk"]
    end
    local bank = ns.Bank and ns.Bank.window
    local window = bank and bank.set.Button(bag, slot) == btn and bank or ns.window
    if window and window.Setting("view") == "categories" then
        if Cat.PinOf(itemID) then
            keys[#keys + 1] = "unpin"
            values.unpin = L["Back to its own group"]
        end
        for _, key in ipairs(Cat.Order()) do
            if key ~= "recent" and key ~= "empty" then
                keys[#keys + 1] = key
                values[key] = Cat.ColorText(key, Cat.Get(key).name)
            end
        end
    end
    DUI.Widgets.OpenMenu(btn, keys, values, current, function(key)
        if key == "unpin" then Cat.Unpin(itemID)
        elseif key == "lock" then Cat.ToggleLock(itemID)
        elseif key == "keep" then Keep.Toggle(bag, slot, itemID)
        elseif key == "junkmark" then Cat.ToggleJunk(itemID, info.hyperlink)
        else Cat.Pin(itemID, key) end
    end, nil, { atCursor = true, rows = Cat.MENU_ROWS, onHover = function(key) lockTip(key, locked) end })
end

-- Assigning

-- Facts about the item in a slot, for grouping.
function Cat.Facts(bag, slot, info)
    local f = ns.Search.Facts(bag, slot, info)
    f.itemID = info.itemID
    f.link = info.hyperlink
    f.count = info.stackCount or 1
    -- Items in a saved copy are never new (Saved.lua).
    f.recent = not ns.Saved.Is(bag) and Cat.IsRecent(bag, slot, info.itemID)
    return f
end

-- Custom group searches, parsed once per text rather than per item.
local parsedSearch = {}
local function parsed(text)
    if type(text) ~= "string" then return nil end
    local m = parsedSearch[text]
    if m == nil then
        m = ns.Search.Parse(text) or false
        parsedSearch[text] = m
    end
    return m or nil
end

-- Group key for an item's facts (the slot's section decides keyring).
-- noRecent: the group the item falls in once it's no longer new.
function Cat.Assign(f, section, noRecent)
    local gone = removed()
    if section == "keyring" then return gone.key and "other" or "key" end
    local pinned = Cat.PinOf(f.itemID)
    if pinned and Cat.Get(pinned) then return pinned end
    for _, g in ipairs(Cat.Custom()) do
        local match = parsed(g.search)
        if match and match(f) then return g.key end
    end
    for _, key in ipairs(Cat.PRIORITY) do
        if not gone[key] and not (noRecent and key == "recent") and Cat.TESTS[key](f) then return key end
    end
    return "other"
end

-- Within a group: best quality first, then name, then smallest stack first.
function Cat.Before(a, b)
    local qa, qb = a.facts.quality or -1, b.facts.quality or -1
    if qa ~= qb then return qa > qb end
    local na, nb = a.facts.name or "", b.facts.name or ""
    if na ~= nb then return na < nb end
    if a.total ~= b.total then return a.total < b.total end
    return a.order < b.order
end
