-- Reads the talent trees from C_Traits into plain tables for the talents
-- page. Nothing here is class-specific: positions, ranks, arrows and rules
-- all come from the game.
--
-- On Forever a config holds one tree, with the class's three trees as
-- display groups (GetGroupDisplayInfoByTreeID). A node lists several
-- groupIDs, and its tree is whichever of them is a display group. Positions
-- sit on a 600-unit grid: rows are shared by all three trees, columns start
-- at each tree's own leftmost x. Tier requirements are trait conditions with
-- spentAmountRequired, and the game's own text is shown for them. Talent
-- data is never secret.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local L = DUI.L

local TD = {}
ns.TalentData = TD

TD.STEP = 600   -- grid spacing between tiles, both axes

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function traits() return type(C_Traits) == "table" and C_Traits or nil end

-- Active talent set, 1 or 2.
function TD.ActiveGroup()
    local S = C_SpecializationInfo
    local g = type(S) == "table" and call(S.GetActiveSpecGroup)
    return type(g) == "number" and g or 1
end

-- Use the global GetNumSpecGroups, as the game's IsDualSpecUnlocked does.
-- C_SpecializationInfo has no GetNumSpecGroups on Forever, and relying on it
-- kept the second set grayed out after learning dual spec.
function TD.NumGroups()
    local n = call(GetNumSpecGroups)
    return type(n) == "number" and n or 1
end

-- Combat config for a set, as in ClassTalentsFrameMixin:SetTab. nil for a
-- second set that was never activated. Defaults to the active set.
function TD.ConfigID(group)
    local S = C_SpecializationInfo
    if type(S) == "table" then
        local id = call(S.GetCombatConfigIDForSpecGroup, group or TD.ActiveGroup())
        if type(id) == "number" then return id end
        if group then return nil end
    end
    if type(C_ClassTalents) == "table" then
        local id = call(C_ClassTalents.GetActiveConfigID)
        if type(id) == "number" then return id end
    end
end

local function spellLook(spellID, def)
    local name = type(def) == "table" and def.overrideName or nil
    local icon = type(def) == "table" and def.overrideIcon or nil
    if type(C_Spell) == "table" and type(spellID) == "number" then
        if type(name) ~= "string" or name == "" then name = call(C_Spell.GetSpellName, spellID) end
        -- The game's talent buttons use the second return, the spell's base
        -- icon (TalentButtonUtil.CalculateIconTexture).
        if not icon then
            local now, own = call(C_Spell.GetSpellTexture, spellID)
            icon = (own ~= nil and own ~= 0 and own) or (now ~= nil and now ~= 0 and now) or nil
        end
    end
    return type(name) == "string" and name or "", icon or 134400   -- question mark icon
end

-- The node's first point-spending condition (tier requirement).
local function rule(C, configID, n)
    for _, condID in ipairs(type(n.conditionIDs) == "table" and n.conditionIDs or {}) do
        local c = call(C.GetConditionInfo, configID, condID)
        if type(c) == "table" and type(c.spentAmountRequired) == "number" and c.spentAmountRequired > 0 then
            return { amount = c.spentAmountRequired, format = c.tooltipFormat, met = c.isMet == true }
        end
    end
end

-- Entries of a choice (Selection) node, else nil. Class trees have none.
local SELECTION = { [2] = true, [3] = true }   -- Enum.TraitNodeType Selection, SubTreeSelection
local function choicesOf(n)
    local T = Enum and Enum.TraitNodeType
    local sel = T and (n.type == T.Selection or n.type == T.SubTreeSelection) or (not T and SELECTION[n.type])
    if sel and type(n.entryIDs) == "table" and #n.entryIDs > 1 then return n.entryIDs end
end

local function readNode(C, configID, id, n)
    local entryID = type(n.activeEntry) == "table" and n.activeEntry.entryID or (type(n.entryIDs) == "table" and n.entryIDs[1]) or nil
    local entry = entryID and call(C.GetEntryInfo, configID, entryID)
    local def = type(entry) == "table" and entry.definitionID and call(C.GetDefinitionInfo, entry.definitionID) or nil
    local spellID = type(def) == "table" and def.spellID or nil
    local name, icon = spellLook(spellID, def)
    local rank = type(n.ranksPurchased) == "number" and n.ranksPurchased or 0
    local active = type(n.activeRank) == "number" and n.activeRank or rank
    local edges = {}
    for _, e in ipairs(type(n.visibleEdges) == "table" and n.visibleEdges or {}) do
        if type(e) == "table" and type(e.targetNode) == "number" then
            edges[#edges + 1] = { to = e.targetNode, active = e.isActive == true }
        end
    end
    return {
        id = id, x = n.posX, y = n.posY, rank = rank, active = active, max = type(n.maxRanks) == "number" and n.maxRanks or 1,
        staged = rank > active, entryID = entryID, spellID = spellID, name = name, icon = icon,
        canBuy = n.canPurchaseRank == true, canRefund = n.canRefundRank == true,
        available = n.isAvailable ~= false and n.meetsEdgeRequirements ~= false,
        edgesMet = n.meetsEdgeRequirements ~= false, rule = rule(C, configID, n), edges = edges,
        choices = choicesOf(n), chosen = type(n.activeEntry) == "table" and n.activeEntry.entryID ~= nil,
    }
end

local function round(v) return math.floor(v + 0.5) end

-- Forever keeps a few retired talents in its trees, parked far off the
-- board (e.g. the hunter's old Lightning Reflexes at x = 102800, the
-- priest's old Holy Specialization at 9280, 21300). The game's frame never
-- shows them. No tree is more than SPAN tiles in either direction, so
-- anything beyond that is skipped.
TD.SPAN = 10

-- Smallest value within span of the median, so a stray node can't set the edge.
local function edge(values, o)
    table.sort(values)
    local mid, low = values[math.ceil(#values / 2)], nil
    for _, v in ipairs(values) do
        if math.abs(v - mid) <= o.span * o.step and (not low or v < low) then low = v end
    end
    return low
end

-- Grid index, or nil when off the board.
local function cell(v, from, o)
    local c = round((v - from) / o.step)
    if c >= 0 and c < o.span then return c end
end

-- Guess the grid step for trees with their own spacing (the Legacy trees):
-- the smallest gap along an axis, ignoring tiny ones from near-overlapping nodes.
function TD.Step(values)
    table.sort(values)
    local best
    for i = 2, #values do
        local d = values[i] - values[i - 1]
        if d > 50 and (not best or d < best) then best = d end
    end
    return best or TD.STEP
end

-- Rows count from the top of the whole config so tiers line up across
-- trees; columns from each tree's left edge. Off-board nodes are dropped
-- from the tree and byID, though any points in them still count.
local function grid(trees, byID, o)
    local ys = {}
    for _, t in ipairs(trees) do
        for _, n in ipairs(t.nodes) do ys[#ys + 1] = n.y end
    end
    local minY = edge(ys, o)
    for _, t in ipairs(trees) do
        local xs = {}
        for _, n in ipairs(t.nodes) do xs[#xs + 1] = n.x end
        local minX = edge(xs, o)
        t.cols, t.rows = o.cols, o.rows   -- at least the classic 4 x 7, so all trees match
        local kept = {}
        for _, n in ipairs(t.nodes) do
            n.col, n.row = cell(n.x, minX, o), cell(n.y, minY, o)
            if n.col and n.row then
                kept[#kept + 1] = n
                if n.col + 1 > t.cols then t.cols = n.col + 1 end
                if n.row + 1 > t.rows then t.rows = n.row + 1 end
            else
                byID[n.id] = nil
            end
        end
        t.nodes = kept
        table.sort(t.nodes, function(a, b) if a.row ~= b.row then return a.row < b.row end return a.col < b.col end)
    end
end

-- Returns { configID, trees = { { groupID, name, icon, spent, cols, rows,
-- nodes = { ... } } }, left, spent, byID = { [nodeID] = node },
-- currency = { [traitCurrencyID] = points left } }, or nil when there's no
-- tree (no C_Traits or no config).
-- opts, used by the Legacy trees: treeID limits to one tree, step sets the
-- grid step ("auto" uses TD.Step), plus span and minimum cols/rows.
function TD.Read(configID, opts)
    local C = traits()
    configID = configID or TD.ConfigID()
    opts = opts or {}
    if not (C and configID) then return nil end
    local info = call(C.GetConfigInfo, configID)
    if type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil end
    local out = { configID = configID, trees = {}, left = 0, spent = 0, byID = {}, currency = {} }
    -- Mark staged nodes from GetStagedChanges, as the game's talent window
    -- does, rather than only comparing purchased and active ranks.
    local pending = {}
    local buys, _, swaps = call(C.GetStagedChanges, configID)
    for _, list in ipairs({ buys, swaps }) do
        for _, id in ipairs(type(list) == "table" and list or {}) do pending[id] = true end
    end
    for _, treeID in ipairs(opts.treeID and { opts.treeID } or info.treeIDs) do
        local groups = call(C.GetGroupDisplayInfoByTreeID, treeID)
        local mine, order = {}, {}
        for _, g in ipairs(type(groups) == "table" and groups or {}) do
            local t = { groupID = g.groupID, name = g.displayName or "", icon = g.icon, order = g.orderIndex or #order, spent = 0, nodes = {} }
            mine[g.groupID] = t
            order[#order + 1] = t
        end
        table.sort(order, function(a, b) return a.order < b.order end)
        local whole   -- used when the tree has no display groups
        for _, id in ipairs(call(C.GetTreeNodes, treeID) or {}) do
            local n = call(C.GetNodeInfo, configID, id)
            if type(n) == "table" and n.isVisible ~= false and type(n.posX) == "number" and type(n.posY) == "number" then
                local t
                for _, g in ipairs(type(n.groupIDs) == "table" and n.groupIDs or {}) do
                    if mine[g] then t = mine[g] break end
                end
                if not t and #order == 0 then
                    whole = whole or { name = "", spent = 0, nodes = {} }
                    t = whole
                end
                if t then
                    local node = readNode(C, configID, id, n)
                    if pending[id] then node.staged = true end
                    node.tree = t
                    t.nodes[#t.nodes + 1] = node
                    t.spent = t.spent + node.rank
                    out.byID[id] = node
                end
            end
        end
        if whole then order[#order + 1] = whole end
        for _, t in ipairs(order) do
            if #t.nodes > 0 then out.trees[#out.trees + 1] = t; t.index = #out.trees; out.spent = out.spent + t.spent end
        end
        local cur = call(C.GetTreeCurrencyInfo, configID, treeID, false)
        for i, c in ipairs(type(cur) == "table" and cur or {}) do
            if type(c) == "table" and type(c.quantity) == "number" then
                if i == 1 then out.left = out.left + c.quantity end
                if c.traitCurrencyID then out.currency[c.traitCurrencyID] = (out.currency[c.traitCurrencyID] or 0) + c.quantity end
            end
        end
    end
    local o = { step = opts.step or TD.STEP, span = opts.span or TD.SPAN, cols = opts.cols or 4, rows = opts.rows or 7 }
    if o.step == "auto" then
        local xs, ys = {}, {}
        for _, node in pairs(out.byID) do xs[#xs + 1] = node.x; ys[#ys + 1] = node.y end
        o.step = math.min(TD.Step(xs), TD.Step(ys))
    end
    grid(out.trees, out.byID, o)
    return out
end

-- Re-query only the given nodes (ids = { [nodeID] = true }) and the point
-- pool, updating data in place: ranks, staged state, buy/refund flags.
-- Layout, names and icons are left alone. Builds.Load uses this between
-- ranks instead of re-reading the whole tree.
function TD.Refresh(data, ids)
    local C = traits()
    if not (C and data and data.configID) then return data end
    local configID = data.configID
    local pending = {}
    local buys, _, swaps = call(C.GetStagedChanges, configID)
    for _, list in ipairs({ buys, swaps }) do
        for _, id in ipairs(type(list) == "table" and list or {}) do pending[id] = true end
    end
    for id in pairs(ids) do
        local node = data.byID[id]
        local n = node and call(C.GetNodeInfo, configID, id)
        if type(n) == "table" then
            local rank = type(n.ranksPurchased) == "number" and n.ranksPurchased or 0
            local delta = rank - node.rank
            if node.tree then node.tree.spent = node.tree.spent + delta end
            data.spent = data.spent + delta
            node.rank = rank
            node.active = type(n.activeRank) == "number" and n.activeRank or rank
            node.staged = pending[id] == true or rank > node.active
            node.canBuy, node.canRefund = n.canPurchaseRank == true, n.canRefundRank == true
            node.available = n.isAvailable ~= false and n.meetsEdgeRequirements ~= false
            node.edgesMet = n.meetsEdgeRequirements ~= false
        end
    end
    local info = call(C.GetConfigInfo, configID)
    if type(info) == "table" and type(info.treeIDs) == "table" then
        data.left, data.currency = 0, {}
        for _, treeID in ipairs(info.treeIDs) do
            local cur = call(C.GetTreeCurrencyInfo, configID, treeID, false)
            for i, c in ipairs(type(cur) == "table" and cur or {}) do
                if type(c) == "table" and type(c.quantity) == "number" then
                    if i == 1 then data.left = data.left + c.quantity end
                    if c.traitCurrencyID then data.currency[c.traitCurrencyID] = (data.currency[c.traitCurrencyID] or 0) + c.quantity end
                end
            end
        end
    end
    return data
end

-- Description for a rank (rank 0 uses rank 1). Empty until the client has
-- loaded the spell, typically on the first hover after login; the second
-- return is then true and TD.LoadSpell can request it.
function TD.Description(node, rank)
    local C = traits()
    if not (C and node and node.entryID) then return nil end
    local text = call(C.GetTraitDescription, node.entryID, math.max(rank or node.rank, 1))
    if type(text) == "string" and text ~= "" then return text end
    return nil, TD.Loading(node)
end

-- Full tooltip lines for a rank from C_TooltipInfo.GetTraitEntry, the same
-- data the game's talent buttons show (cost, range, cast time, cooldown,
-- then the description). Returns { left, right, lc, rc } entries with false
-- for blank lines, trimmed at both ends, or nil if there are none (use
-- TD.Description then). The title line and any secret text are dropped.
local function plainText(v)
    if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) or v == "" then return nil end
    return v
end
function TD.EntryLines(node, rank)
    local TI = C_TooltipInfo
    if not (type(TI) == "table" and node and type(node.entryID) == "number") then return nil end
    local data = call(TI.GetTraitEntry, node.entryID, math.max(rank or node.rank, 1))
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(data.lines) do
        if type(line) == "table" then
            local left, right = plainText(line.leftText), plainText(line.rightText)
            if left or right then
                if not (left == node.name and not right) then
                    out[#out + 1] = { left = left or "", right = right, lc = line.leftColor, rc = line.rightColor }
                end
            elseif #out > 0 and out[#out] then
                out[#out + 1] = false
            end
        end
    end
    while #out > 0 and not out[#out] do out[#out] = nil end
    return #out > 0 and out or nil
end

-- True while the node's spell data isn't cached yet. The game's talent
-- buttons wait the same way (Spell:ContinueWithCancelOnSpellLoad).
function TD.Loading(node)
    local S = C_Spell
    if not (type(S) == "table" and node and type(node.spellID) == "number") then return false end
    return call(S.IsSpellDataCached, node.spellID) == false
end

-- SPELL_DATA_LOAD_RESULT fires when it arrives.
function TD.LoadSpell(node)
    local S = C_Spell
    if type(S) == "table" and node and type(node.spellID) == "number" then call(S.RequestLoadSpellData, node.spellID) end
end

-- Unmet requirements, in the game's words where possible: the tier rule
-- ("Spend 10 more points in Arms Talents"), then any prerequisite talent not
-- yet maxed. Each line is { text, name, tree }, where name is the tree or
-- talent to highlight and tree gives its color. nil when nothing is missing.
function TD.Missing(node, data)
    local out = {}
    local r = node.rule
    if r and not r.met then
        -- spentAmountRequired is already the remaining amount; the game
        -- prints it as is.
        local more = r.amount
        local ok, text = false, nil
        if type(r.format) == "string" then
            -- The client picks |4one:many; forms from the preceding number,
            -- so the tree name ("Enhancement |4Talent:Talents;") came out
            -- singular after "1 more point". It's a tree name, so force plural.
            local fmt = r.format
            local at = string.find(fmt, "%s", 1, true)
            if at then fmt = string.sub(fmt, 1, at + 1) .. (string.gsub(string.sub(fmt, at + 2), "|4[^:;]*:([^;]*);", "%1")) end
            ok, text = pcall(string.format, fmt, more, node.tree.name)
        end
        out[#out + 1] = { text = ok and text or string.format(L["Spend %d more |4point:points; in %s"], more, node.tree.name),
            name = node.tree.name, tree = node.tree }
    end
    if not node.edgesMet and data then
        for _, t in ipairs(data.trees) do
            for _, src in ipairs(t.nodes) do
                for _, e in ipairs(src.edges) do
                    if e.to == node.id and src.rank < src.max then
                        out[#out + 1] = { text = string.format(L["Requires %d |4point:points; in %s"], src.max, src.name), name = src.name }
                    end
                end
            end
        end
    end
    return #out > 0 and out or nil
end
