local AHW = require("ahworld")
local stub = require("stub")

-- A fake item database: info[itemID] = { sell = copper, bind = bindType }.
-- C_Item.GetItemInfo answers like the client: 17 returns, nothing when unknown.
local function itemInfo(info)
    return function(before)
        return function()
            local fake = {}
            for k, v in pairs(_G.C_Item or {}) do fake[k] = v end
            fake.GetItemInfo = function(what)
                local id = tonumber(what) or tonumber(tostring(what):match("item:(%d+)"))
                local it = id and info[id]
                if not it then return nil end
                return "Item " .. id, "link", 1, 1, 0, "Misc", "Junk", 20, "", 134400,
                    it.sell or 0, 15, 0, it.bind or 0, 0, nil, false
            end
            _G.C_Item = fake
            if before then before() end
        end
    end
end

-- A fake merchant: items = { { id =, price =, stack =, extended = } } on the
-- modern table API (C_MerchantFrame.GetItemInfo) or the legacy globals.
local function merchant(items, legacy)
    return function()
        _G.GetMerchantNumItems = function() return #items end
        _G.GetMerchantItemID = function(i) return items[i] and items[i].id end
        if legacy then
            _G.C_MerchantFrame = nil
            _G.GetMerchantItemInfo = function(i)
                local it = items[i]
                if not it then return nil end
                return "Item " .. it.id, 134400, it.price, it.stack or 1, -1, true, true, it.extended == true
            end
        else
            _G.C_MerchantFrame = {
                GetItemInfo = function(i)
                    local it = items[i]
                    if not it then return nil end
                    return { name = "Item " .. it.id, texture = 134400, price = it.price, stackCount = it.stack or 1,
                        numAvailable = -1, isPurchasable = true, isUsable = true, hasExtendedCost = it.extended == true }
                end,
            }
        end
    end
end

T.test("plain_item_key", function()
    local M = AHW.Mog({})
    local key, base = M.Items.Key("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r")
    T.eq(key, "2589")
    T.eq(base, "2589")
    key, base = M.Items.Key(2589)
    T.eq(key, "2589")
    T.eq(base, "2589")
    T.eq(M.Items.ID("2589"), 2589)
    T.eq(M.Items.ID("7429:-15"), 7429)
end)

T.test("suffixed_item_key", function()
    local M = AHW.Mog({})
    local key, base = M.Items.Key("|cff1eff00|Hitem:7429::::::-15:1234567:60:::::|h[Cloak of the Monkey]|h|r")
    T.eq(key, "7429:-15")
    T.eq(base, "7429")
    -- A zero suffix, and a link with no more fields than the suffix, are plain.
    T.eq(M.Items.Key("|Hitem:7429::::::0:1234567:60:::::|h[x]|h"), "7429")
    T.eq(M.Items.Key("item:7429:0:0:0:0:0:-15"), "7429:-15")
end)

T.test("key_accepts_its_own_keys", function()
    -- a price key in gives the same key back (callers holding keys need no itemID)
    local M = AHW.Mog({})
    local key, base = M.Items.Key("7429:-15")
    T.eq(key, "7429:-15")
    T.eq(base, "7429")
    key, base = M.Items.Key("2589")
    T.eq(key, "2589")
    T.eq(base, "2589")
    T.eq(M.Items.Key("7429:0"), "7429", "a zero suffix is the plain key")
    T.isnil(M.Items.Key("7429:"))
    T.isnil(M.Items.Key("7429:x"))
    T.isnil(M.Items.Key("0:-15"))
end)

-- The old way: every field split on ':' (empty ones kept), suffix the 7th.
local function oldKey(linkOrID)
    local id, suffix
    if type(linkOrID) == "number" then
        id = linkOrID
    elseif type(linkOrID) == "string" then
        local body = string.match(linkOrID, "item:([^|]*)")
        if body then
            local fields, from = {}, 1
            while true do
                local at = string.find(body, ":", from, true)
                if not at then fields[#fields + 1] = string.sub(body, from); break end
                fields[#fields + 1] = string.sub(body, from, at - 1)
                from = at + 1
            end
            id, suffix = tonumber(fields[1]), tonumber(fields[7])
        else
            id = tonumber(linkOrID)
        end
    end
    if not id or id <= 0 or id ~= math.floor(id) then return nil end
    local base = string.format("%d", id)
    if suffix and suffix ~= 0 then return base .. ":" .. string.format("%d", suffix), base end
    return base, base
end

T.test("key_reads_links_as_before", function()
    -- one string.match instead of a table per call: the same answers
    local M = AHW.Mog({})
    local cases = {
        "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r",
        "|cff1eff00|Hitem:7429::::::-15:1234567:60:::::|h[Cloak of the Monkey]|h|r",
        "|cff1eff00|Hitem:7429:0:0:0:0:0:-15:0:60:::::|h[Cloak of the Monkey]|h|r",
        "|Hitem:7429::::::0:1234567:60:::::|h[x]|h",
        "item:7429:0:0:0:0:0:-15", "item:7429:0:0:0:0:0:15", "item:7429", "item:7429:", "item:7429::::::",
        "|cffffffff|Hitem:15210::::::-16:::60::::::::|h[Blade]|h|r",
        "|Hitem:|h[x]|h", "item:-5:0:0:0:0:0:-15", "item:abc", "junk", "", "2589", "12.5", "-3",
        2589, 7429, 0, -1, 12.5,
    }
    for _, c in ipairs(cases) do
        local k1, b1 = M.Items.Key(c)
        local k2, b2 = oldKey(c)
        T.eq(k1, k2, "key of " .. tostring(c))
        T.eq(b1, b2, "base of " .. tostring(c))
    end
end)

T.test("bad_links_give_nil", function()
    local M = AHW.Mog({})
    T.isnil(M.Items.Key(nil))
    T.isnil(M.Items.Key("junk"))
    T.isnil(M.Items.Key(""))
    T.isnil(M.Items.Key("|Hitem:|h[x]|h"))
    T.isnil(M.Items.Key({}))
end)

T.test("vendor_sell_from_item_info", function()
    local M = AHW.Mog({ before = itemInfo({ [2589] = { sell = 25 }, [4306] = { sell = 0 } })() })
    T.eq(M.Items.VendorSell(2589), 25)
    T.isnil(M.Items.VendorSell(4306))   -- 0 = cannot be sold
    T.isnil(M.Items.VendorSell(99999))  -- not loaded / unknown
end)

T.test("bound_items_cant_be_auctioned", function()
    local M = AHW.Mog({ before = itemInfo({
        [1] = { bind = 1 }, [2] = { bind = 0 }, [3] = { bind = 2 }, [4] = { bind = 4 }, [5] = { bind = 3 } })() })
    T.eq(M.Items.CanAuction(1), false)
    T.eq(M.Items.CanAuction(2), true)
    T.eq(M.Items.CanAuction(3), true)
    T.eq(M.Items.CanAuction(4), false)
    T.eq(M.Items.CanAuction(5), true)
    T.eq(M.Items.CanAuction(999), true)   -- unknown: assume yes
end)

T.test("hyperlink_is_the_whole_link", function()
    local M = AHW.Mog({})
    local old = C_Item.GetItemInfo
    C_Item.GetItemInfo = function(v)
        if v == 2589 then return "Linen Cloth", "|Hitem:2589|h[Linen Cloth]|h" end
        if v == "item:7429:0:0:0:0:0:-15" then return "Cloak", "|Hitem:7429::::::-15|h[Cloak of the Monkey]|h" end
    end
    T.eq(M.Items.Hyperlink(2589), "|Hitem:2589|h[Linen Cloth]|h")
    T.eq(M.Items.Hyperlink("2589"), "|Hitem:2589|h[Linen Cloth]|h", "a plain key")
    T.eq(M.Items.Hyperlink("7429:-15"), "|Hitem:7429::::::-15|h[Cloak of the Monkey]|h", "a suffixed key keeps its suffix")
    T.eq(M.Items.Hyperlink("|Hitem:9|h[x]|h"), "|Hitem:9|h[x]|h", "a link is itself")
    T.eq(M.Items.Hyperlink(55555), nil, "not loaded yet: nothing half-made for chat")
    T.eq(M.Items.Hyperlink(nil), nil)
    T.eq(M.Items.RowLink({ kind = "line", key = "2589" }), "|Hitem:2589|h[Linen Cloth]|h")
    T.eq(M.Items.RowLink({ kind = "line", out = 2589 }), "|Hitem:2589|h[Linen Cloth]|h", "a recipe's item")
    T.eq(M.Items.RowLink({ kind = "own", key = "2589" }), nil, "only item rows")
    C_Item.GetItemInfo = old
end)
