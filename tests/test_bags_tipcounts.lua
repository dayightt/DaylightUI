local stub = require("stub")

-- Item counts under an item's tooltip (Bags > Bank and alts > Item counts on
-- tooltips): what this character's bank holds and what other characters
-- have, from what was saved, and this character's bags as they are now.

local function login()
    stub.Load({ bags = true, before = function()
        _G.Constants = _G.Constants or {}
        Constants.InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 1 }
        _G.C_Container = {
            GetContainerNumSlots = function() return 0 end,
            SetItemSearch = function() end,
            GetContainerItemInfo = function() return nil end,
            GetContainerNumFreeSlots = function() return 0, 0 end,
            HasContainerItem = function() return false end,
        }
        _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    end })
    stub.RunTimers()
    return stub.bags
end

-- This character's bags as they are now: item id -> how many.
local function bags(ns, counts)
    ns.Bags.List = function() return { { id = 0 } } end
    ns.Bags.NumSlots = function() return #counts end
    ns.Items.InfoAt = function(_, slot)
        local c = counts[slot]
        return c and { hyperlink = "|Hitem:" .. c[1] .. "|h", stackCount = c[2] } or nil
    end
    ns.Saved.ForgetBags()
end

-- What this character's bank held the last time it was open.
local function bank(ns, items)
    local own = DaylightUI.DB.Character()
    own.inventory = own.inventory or {}
    local list = {}
    for i, it in ipairs(items) do list[i] = { "|Hitem:" .. it[1] .. "|h", it[2] } end
    own.inventory.bank = { { section = "bank", size = 8, items = list } }
    ns.Saved.ForgetCounts()
end

local function rows(ns, data)
    local out, addLine, addDouble = {}, GameTooltip.AddLine, GameTooltip.AddDoubleLine
    GameTooltip.AddLine = function(_, text) out[#out + 1] = { text } end
    GameTooltip.AddDoubleLine = function(_, l, r) out[#out + 1] = { l, r } end
    ns.Saved.OnTip(GameTooltip, data)
    GameTooltip.AddLine, GameTooltip.AddDoubleLine = addLine, addDouble
    return out
end

local function plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- A player with one character: 56 Silk Cloth in the bank, 20 in the bags, the
-- switch on, and nothing under the tooltip. The game's own tooltip never says
-- what the bank holds.
T.test("bags: an item in this character's bank shows its count with no other character", function()
    local ns = login()
    bags(ns, { { 4306, 20 } })
    bank(ns, { { 4306, 56 } })
    local r = rows(ns, { id = 4306 })
    T.truthy(#r > 0, "counts under the tooltip")
    local me = DaylightUI.DB.CharKey():match("^(.-)%-")
    T.eq(r[2][1], me)
    T.eq(plain(r[2][2]), "Bags 20 · Bank 56")
    T.eq(r[#r][1], "Total")
    T.eq(plain(r[#r][2]), "76")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("bags: an item only in this character's bags adds nothing", function()
    local ns = login()
    bags(ns, { { 4306, 20 } })
    bank(ns, {})
    T.eq(#rows(ns, { id = 4306 }), 0, "the bags are right there")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
