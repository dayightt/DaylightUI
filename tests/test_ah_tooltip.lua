local AHW = require("ahworld")
local stub = require("stub")

-- The price lines the Auction House addon adds to item tooltips: the game's
-- post-call over a tooltip, prices read from the store under the ruleset.

local HERB = 2449
local NOW = 1700000000
local post

-- The game's tooltip data processor and an item tooltip with its lines, as
-- the client keeps them (TextLeftN font strings by the tooltip's name).
local function tipWorld()
    post = {}
    Enum.TooltipDataType = Enum.TooltipDataType or {}
    Enum.TooltipDataType.Item = 0
    _G.TooltipDataProcessor = {
        AddTooltipPostCall = function(kind, fn)
            post[kind] = post[kind] or {}
            table.insert(post[kind], fn)
        end,
    }
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tip = CreateFrame("GameTooltip", name, UIParent)
        tip.__rows = {}
        function tip:NumLines() return #self.__rows end
        local function put(self, left, right, color)
            local i = #self.__rows + 1
            local fs = _G[name .. "TextLeft" .. i] or self:CreateFontString(name .. "TextLeft" .. i)
            _G[name .. "TextLeft" .. i] = fs
            fs:SetText(left)
            self.__rows[i] = { left = left, right = right, color = color }
        end
        function tip:AddLine(text, r, g, b) put(self, text, nil, { r, g, b }) end
        function tip:AddDoubleLine(l, rt, r, g, b, rr, rg, rb) put(self, l, rt, { r, g, b, rr, rg, rb }) end
        function tip:ClearLines() self.__rows = {} end
        function tip:GetItem() return nil, self.__link end
        _G[name] = tip
    end
end

local function load(opts)
    opts = opts or {}
    local M = AHW.Mog({
        before = function()
            stub.SetTime(NOW)
            tipWorld()
            if opts.mogul then _G.DaylightMogul = {} end
        end,
    })
    _G.DaylightMogul = nil
    return M
end

-- The game filling the tooltip with an item: cleared, its own lines, then
-- the post-calls.
local function fill(link, stack)
    local tip = GameTooltip
    tip:ClearLines()
    tip.__link = link
    tip:AddLine("Peacebloom")
    tip.info = stack and { getterName = "GetBagItem", getterArgs = { 0, 1 } } or nil
    local data = { type = 0, hyperlink = link }
    for _, fn in ipairs(post[0] or {}) do fn(tip, data) end
    return tip.__rows
end

local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::60::::::::|h[Peacebloom]|h|r" end

local function lefts(rows)
    local out = {}
    for i = 2, #rows do out[#out + 1] = rows[i].left end
    return out
end

T.test("ah tooltip: price, usual and age for an item seen at the AH", function()
    local M = load()
    M.Store.Record("US-PvE", tostring(HERB), 105, 60, NOW - 2 * 3600)
    local rows = fill(link(HERB))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.deq(lefts(rows), { "Auction", "Usual", "Seen 2 h ago" })
    T.truthy(rows[2].right:find("05", 1, true), "the price in our coins: " .. tostring(rows[2].right))
    local INK = DaylightUI.Style.INK
    T.deq({ rows[3].color[1], rows[3].color[2], rows[3].color[3] }, { INK.LABEL[1], INK.LABEL[2], INK.LABEL[3] }, "Usual in the label color")
end)

T.test("ah tooltip: nothing for an item never seen, or with no ruleset", function()
    local M = load()
    T.deq(lefts(fill(link(HERB))), {})
    T.isnil(M.Tooltip.Lines(link(HERB), false, 1))
end)

T.test("ah tooltip: Shift prices the whole stack, and the hint says so", function()
    local M = load()
    M.Store.Record("US-PvE", tostring(HERB), 100, 60, NOW - 120)
    _G.C_Container = { GetContainerItemInfo = function() return { stackCount = 20 } end }
    local rows = fill(link(HERB), true)
    T.deq(lefts(rows), { "Auction", "Usual", "Seen 2 min ago  ·  Shift: the whole stack" })
    stub.shift = true
    rows = fill(link(HERB), true)
    stub.shift = nil
    T.deq(lefts(rows), { "Auction", "Usual, stack of 20", "Seen 2 min ago" })
    T.eq(rows[2].right, DaylightUI.Widgets.Money(2000))
end)

T.test("ah tooltip: the lines go in once when the post-call runs twice", function()
    local M = load()
    M.Store.Record("US-PvE", tostring(HERB), 100, 60, NOW)
    fill(link(HERB))
    M.Tooltip.OnItem(GameTooltip, { hyperlink = link(HERB) })
    T.deq(lefts(GameTooltip.__rows), { "Auction", "Usual", "Seen 1 min ago" })
end)

T.test("ah tooltip: no line while DaylightMogul owns the Auction House", function()
    local M = load({ mogul = true })
    T.eq(M.mogul, true)
    T.eq(DaylightUI.ahMogul, true)
    M.Store.Record("US-PvE", tostring(HERB), 100, 60, NOW)
    T.deq(lefts(fill(link(HERB))), {})
end)

T.test("ah tooltip: a suffix never seen at the AH gets no price of the plain item", function()
    local M = load()
    local getInfo = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(id)
        if id == 7429 then return "Bandit Cinch" end
        if getInfo then return getInfo(id) end
    end
    M.Store.Record("US-PvE", "7429", 100, 1, NOW)
    local unplaced = "|cff1eff00|Hitem:7429::::::::60::::::::|h[Bandit Cinch of the Monkey]|h|r"
    T.deq(lefts(fill(unplaced)), {})
    C_Item.GetItemInfo = getInfo
end)

T.test("ah tooltip: the options switch the price lines off one by one", function()
    local M = load()
    M.Store.Record("US-PvE", tostring(HERB), 100, 60, NOW - 120)
    _G.C_Container = { GetContainerItemInfo = function() return { stackCount = 20 } end }
    local off = {}
    M.Setting = function(key) if off[key] then return false end return true end
    off.tooltipUsual = true
    T.deq(lefts(fill(link(HERB), true)), { "Auction", "Seen 2 min ago  ·  Shift: the whole stack" })
    off.tooltipAge = true
    T.deq(lefts(fill(link(HERB), true)), { "Auction", "Shift: the whole stack" })
    off.tooltipStack = true
    stub.shift = true
    local rows = fill(link(HERB), true)
    stub.shift = nil
    T.deq(lefts(rows), { "Auction" })
    T.eq(rows[2].right, DaylightUI.Widgets.Money(100), "Shift does nothing with the stack switch off")
    off.tooltip = true
    T.deq(lefts(fill(link(HERB), true)), {})
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
