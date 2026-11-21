-- The price lines on item tooltips: what the cheapest one cost when it was last
-- seen at the Auction House, its usual price, and how old that is. Holding
-- Shift over a stack prices the whole stack. Nothing for an item never seen.
--
-- The lines are added here rather than by the Tooltip module, so they show
-- with that module off too. The game fills an item tooltip again every 0.2 s
-- (cleared, then every post-call), so each fill adds them again with no memory
-- of the last one, and nothing here shows, hides or hooks a tooltip.

local _, ns = ...
local DUI = DaylightUI
local L = ns.L

local Tooltip = {}
ns.Tooltip = Tooltip

-- A value from the game, or nil when it reads secret.
local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The item as a link or an item ID: the data's link, else the tooltip's own
-- item, else the data's ID.
local function itemOf(tip, data)
    local link = type(data) == "table" and plain(data.hyperlink) or nil
    if type(link) == "string" then return link end
    if type(tip.GetItem) == "function" then
        local _, got = tip:GetItem()
        got = plain(got)
        if type(got) == "string" then return got end
    end
    local id = type(data) == "table" and plain(data.id) or nil
    if type(id) == "number" then return id end
    return nil
end

-- True when a left text of the tooltip already reads `text`: the post-calls
-- can run twice over one fill, and the lines go in once.
local function hasLine(tip, name, text)
    local n = plain(tip:NumLines())
    if type(n) ~= "number" then return false end
    for i = 1, n do
        local fs = _G[name .. "TextLeft" .. i]
        local got = fs and fs.GetText and plain(fs:GetText())
        if got == text then return true end
    end
    return false
end

-- A tooltip switch from the options; on until the settings are read.
local function on(key)
    return not (ns.Setting and ns.Setting(key) == false)
end

-- The lines for `link`, as { left, right, leftInk, rightInk } rows, or nil
-- when there's no price. held: Shift is down; stack: how many the tooltip
-- stands for. Kept apart from the tooltip so the options page can show it.
function Tooltip.Lines(link, held, stack)
    local rkey = ns.Ruleset.Key()
    if not rkey then return nil end
    local key, _, unplaced = ns.Items.Key(link)
    -- A random-suffix item whose suffix hasn't been seen at the AH: the plain
    -- item's price is another roll's, so nothing.
    if not key or unplaced then return nil end
    local min = ns.Store.Min(rkey, key)
    if not min then return nil end
    local now = ns.Game.Now()
    local usual = ns.Store.Market(rkey, key, now)
    local seenAt = ns.Store.SeenAt(rkey, key)
    local wholeStack = on("tooltipStack")
    local count = (wholeStack and held and type(stack) == "number" and stack > 1) and stack or 1
    local INK = DUI.Style.INK
    local rows = {}
    rows[1] = { L["Auction"], DUI.Widgets.Money(min * count), INK.TEXT, INK.VALUE }
    if usual and on("tooltipUsual") then
        local label = count > 1 and string.format(L["Usual, stack of %d"], count) or L["Usual"]
        rows[#rows + 1] = { label, DUI.Widgets.Money(usual * count), INK.LABEL, INK.VALUE }
    end
    local last = {}
    if on("tooltipAge") then
        last[1] = string.format(L["Seen %s ago"], ns.Ago(type(seenAt) == "number" and now - seenAt or nil))
    end
    if wholeStack and count == 1 and type(stack) == "number" and stack > 1 then
        last[#last + 1] = L["Shift: the whole stack"]
    end
    if last[1] then rows[#rows + 1] = { table.concat(last, "  ·  "), nil, INK.LABEL } end
    return rows
end

-- The tooltip's own text lines, from the fill's data when it has them, else
-- from the drawn left texts. Secret ones are skipped.
local function textLines(tip, name, data)
    local out = {}
    local lines = type(data) == "table" and plain(data.lines) or nil
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            local text = type(line) == "table" and plain(line.leftText) or nil
            if type(text) == "string" then out[#out + 1] = text end
        end
        if out[1] then return out end
    end
    local n = plain(tip:NumLines())
    if type(n) ~= "number" then return out end
    for i = 1, n do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and fs.GetText and plain(fs:GetText())
        if type(text) == "string" then out[#out + 1] = text end
    end
    return out
end

-- Bundle lines such as "- 20 Peacebloom" (a Waylaid Crate's use text lists
-- the bundles that fill it, one per line). Color codes are dropped and an
-- "x" after the count is allowed, as some languages write "20 x Name".
function Tooltip.Bundles(lines)
    local found = {}
    for _, text in ipairs(lines) do
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        for piece in (text .. "\n"):gmatch("([^\n]*)\n") do
            local count, item = piece:match("^%s*%-%s*(%d+)%s*[xX\195\151]?%s+(.-)%s*$")
            if count and item ~= "" then
                found[#found + 1] = { count = tonumber(count), name = item }
            end
        end
    end
    return found
end

-- The itemID for a bundle's name: the game's cache first, then the names the
-- Buy page has already gathered.
local function idOfName(itemName)
    local id = ns.Items.IDByName(itemName)
    if id then return id end
    local index = ns.BuyPage and ns.BuyPage.nameIndex
    local lower = itemName:lower()
    for _, e in ipairs(index and index.entries or {}) do
        if e[1] == lower then return e[3] end
    end
    return nil
end

-- What each bundle costs at its last seen price, the cheapest total on the
-- heading row. Nil unless at least one bundle names an item the game knows,
-- so a "- 3 ..." line in some other item's text adds nothing.
function Tooltip.FillLines(lines)
    local rkey = ns.Ruleset.Key()
    if not rkey then return nil end
    local bundles = Tooltip.Bundles(lines)
    if not bundles[1] then return nil end
    local INK = DUI.Style.INK
    local rows, cheapest, known = {}, nil, false
    for _, b in ipairs(bundles) do
        local id = idOfName(b.name)
        if id then known = true end
        local key = id and ns.Items.Key(id)
        local min = key and ns.Store.Min(rkey, key)
        local label = b.count .. " " .. b.name
        if min then
            local total = min * b.count
            if not cheapest or total < cheapest then cheapest = total end
            rows[#rows + 1] = { label, DUI.Widgets.Money(total), INK.TEXT, INK.VALUE }
        else
            rows[#rows + 1] = { label, L["no price yet"], INK.TEXT, INK.OFF }
        end
    end
    if not known then return nil end
    table.insert(rows, 1, { L["Cheapest to fill"],
        cheapest and DUI.Widgets.Money(cheapest) or L["no price yet"],
        INK.LABEL, cheapest and INK.VALUE or INK.OFF })
    return rows
end

local function addRows(tip, rows)
    for _, r in ipairs(rows) do
        local a, b = r[3], r[4]
        if r[2] then
            tip:AddDoubleLine(r[1], r[2], a[1], a[2], a[3], b[1], b[2], b[3])
        else
            tip:AddLine(r[1], a[1], a[2], a[3])
        end
    end
end

local function addLines(tip, data)
    if ns.mogul or not on("tooltip") then return end
    local name = tip.GetName and tip:GetName()
    if type(name) ~= "string" then return end
    local link = itemOf(tip, data)
    if link == nil then return end
    local fill = Tooltip.FillLines(textLines(tip, name, data))
    local rows = Tooltip.Lines(link, IsShiftKeyDown and IsShiftKeyDown(), ns.Items.StackCount(tip))
    if rows and not hasLine(tip, name, rows[1][1]) then addRows(tip, rows) end
    if fill and not hasLine(tip, name, fill[1][1]) then addRows(tip, fill) end
end

-- What one of an item costs at its cheapest: the Auction House price the
-- profession window uses, or what a vendor sells it for.
local function cheapest(itemID)
    local best = ns.Bridge.Item(itemID)
    local vendor = ns.Vendor.Price(itemID)
    if vendor and (not best or vendor < best) then best = vendor end
    return best
end

-- A recipe's reagents, once per recipe: a schematic never changes. A spell
-- that isn't a recipe has no reagent slots, so it gets nothing.
local recipes = {}

local function reagentsOf(spellID)
    local hit = recipes[spellID]
    if hit ~= nil then return hit or nil end
    local TS = C_TradeSkillUI
    local s = TS and TS.GetRecipeSchematic and TS.GetRecipeSchematic(spellID, false)
    local out = { mats = {} }
    for _, slot in ipairs(type(s) == "table" and type(s.reagentSlotSchematics) == "table" and s.reagentSlotSchematics or {}) do
        local first = type(slot.reagents) == "table" and slot.reagents[1]
        local itemID = type(first) == "table" and plain(first.itemID)
        if type(itemID) == "number" and slot.required ~= false and slot.hiddenInCraftingForm ~= true then
            out.mats[#out.mats + 1] = { itemID = itemID, need = plain(slot.quantityRequired) or 1 }
        end
    end
    local kinds = Enum and Enum.TradeskillRecipeType
    out.enchant = type(s) == "table" and kinds ~= nil and s.recipeType == kinds.Enchant
    recipes[spellID] = out.mats[1] and out or false
    return out.mats[1] and out or nil
end

-- "Enchant cost" (or "Cost to make") for a recipe: every reagent at its
-- cheapest known price. A reagent with no price yet is named under it, and
-- the total waits for it, since a part of the cost would read as the whole.
function Tooltip.CostLines(spellID)
    local r = reagentsOf(spellID)
    if not (r and ns.Ruleset.Key()) then return nil end
    local INK = DUI.Style.INK
    local sum, missing = 0, {}
    for _, m in ipairs(r.mats) do
        local each = cheapest(m.itemID)
        if each then
            sum = sum + each * m.need
        else
            local name = C_Item and C_Item.GetItemNameByID and plain(C_Item.GetItemNameByID(m.itemID))
            missing[#missing + 1] = type(name) == "string" and name ~= "" and name or string.format(L["Item %d"], m.itemID)
        end
    end
    local label = r.enchant and L["Enchant cost"] or L["Cost to make"]
    if not missing[1] then
        return { { label, DUI.Widgets.Money(math.floor(sum + 0.5)), INK.TEXT, INK.VALUE } }
    end
    return {
        { label, L["no price yet"], INK.TEXT, INK.OFF },
        { string.format(L["No price yet for %s"], table.concat(missing, ", ")), nil, INK.LABEL },
    }
end

local function addCost(tip, data)
    if ns.mogul or not on("tooltip") then return end
    local name = tip.GetName and tip:GetName()
    local id = type(data) == "table" and plain(data.id) or nil
    if type(name) ~= "string" or type(id) ~= "number" then return end
    local rows = Tooltip.CostLines(id)
    if rows and not hasLine(tip, name, rows[1][1]) then addRows(tip, rows) end
end

-- The spell post-call: a recipe linked in chat, or hovered.
function Tooltip.OnSpell(tip, data)
    if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    ns.SafeCall(addCost, tip, data)
end

-- The post-call: the two item tooltips, never a compare or a forbidden one.
function Tooltip.OnItem(tip, data)
    if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    ns.SafeCall(addLines, tip, data)
end

-- Registered at load: the Tooltip module loads after this addon, so its own
-- post-calls (the rich card reading other addons' lines) run after these.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Tooltip.OnItem)
    if Enum.TooltipDataType.Spell then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, Tooltip.OnSpell)
    end
end
