local stub = require("stub")
local PW = require("craftworld")
local NW = require("npcworld")

-- DaylightUI.API 1.2: the vendor's tiles and the profession window reported to
-- plugins (API.lua's Report.Row / Report.Event), the same way as the unit frames.

local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end

local function recorder(API, events)
    local log = {}
    for _, ev in ipairs(events) do
        API.On(ev, function(...) log[#log + 1] = { ev, ... } end, "Tester")
    end
    return log
end

local function only(log, ev, kind)
    local out = {}
    for _, c in ipairs(log) do
        if c[1] == ev and (not kind or c[2] == kind) then out[#out + 1] = c end
    end
    return out
end

-- ---------------------------------------------------------------------
-- Shop tiles
-- ---------------------------------------------------------------------

T.test("api windows: a vendor's tiles are made, found, told apart and styled", function()
    stub.Load({ before = NW.world({}) })
    local API = DaylightUI.API
    T.eq(API.minor, 4)
    local log = recorder(API, { "FrameMade", "FrameUnitChanged", "FrameRemoved", "FrameStyled" })
    NW.Merchant()
    frame(30)
    local made = only(log, "FrameMade", "shoptile")
    T.eq(#made, #NW.Goods(), "one per item on the shelf")
    T.eq(made[1][4], "buy:1")
    T.eq(made[1][5], false, "a real shop")
    local tile = API.GetShopTile("buy", 1)
    T.eq(tile, made[1][3])
    local tab, index, _, link = API.ShopItem(tile)
    T.eq(tab, "buy"); T.eq(index, 1)
    T.truthy(type(link) == "string" and link:find("Refreshing Spring Water", 1, true))
    T.eq(API.GetPart(tile, "name"):GetText(), "Refreshing Spring Water")
    T.truthy(API.GetPart(tile, "icon"), "the icon")
    T.isnil(API.GetPart(tile, "price"), "only the named parts")
    T.truthy(API.Attach(tile), "a holder on a tile")
    T.truthy(#only(log, "FrameStyled", "shoptile") >= #made, "styled after the fill")

    -- Bags or money change: the shelf refills and each tile is styled again, nothing remade.
    local styled = #only(log, "FrameStyled", "shoptile")
    stub.FireEvent("BAG_UPDATE_DELAYED")
    frame(3)
    T.truthy(#only(log, "FrameStyled", "shoptile") > styled, "a refill paints again")
    T.eq(#only(log, "FrameMade", "shoptile"), #made, "no tile made twice")

    -- A search leaves one, and the others let their items go.
    local page = stub.npc.Window.frame.pages.shop
    page.search:SetText("Tough Jerky")
    frame(3)
    local removed = only(log, "FrameRemoved", "shoptile")
    T.truthy(#removed >= #made - 1, "the hidden tiles let go")
    local jerky = API.GetShopTile("buy", 2)
    T.truthy(jerky, "the one left is found")
    T.eq(API.GetPart(jerky, "name"):GetText(), "Tough Jerky")
    T.isnil(API.GetShopTile("buy", 1), "a hidden one isn't")

    -- Goodbye: every tile lets go.
    stub.FireEvent("MERCHANT_CLOSED")
    frame(30)
    T.isnil(API.GetShopTile("buy", 2), "closed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api windows: another vendor's item at the same spot is a new occupant", function()
    stub.Load({ before = NW.world({}) })
    local API = DaylightUI.API
    NW.Merchant()
    frame(30)
    local log = recorder(API, { "FrameUnitChanged" })
    local tile = API.GetShopTile("buy", 1)
    local was = select(3, API.ShopItem(tile))
    -- The same window, the shelf read again with other goods.
    NW.Merchant({ items = { { name = "Mageweave Cloth", price = 50 }, { name = "Tough Jerky", price = 25, stack = 5 } } })
    frame(30)
    local now = API.GetShopTile("buy", 1)
    T.eq(API.GetPart(now, "name"):GetText(), "Mageweave Cloth")
    if was ~= select(3, API.ShopItem(now)) and now == tile then
        T.truthy(#only(log, "FrameUnitChanged", "shoptile") >= 1, "told it holds something else")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api windows: shop tile calls refuse what isn't a tile", function()
    stub.Load({ before = NW.world({}) })
    local API = DaylightUI.API
    T.isnil(API.GetShopTile("sell", 1))
    T.isnil(API.GetShopTile("buy", "1"))
    T.isnil(API.ShopItem(CreateFrame("Frame")))
    T.isnil(API.GetPart(CreateFrame("Frame"), "icon"))
    T.isnil(API.GetPart(nil, "icon"))
end)

-- ---------------------------------------------------------------------
-- The profession window
-- ---------------------------------------------------------------------

T.test("api windows: the profession window tells open, profession, recipe and close", function()
    stub.Load({ before = PW.world({}) })
    local API = DaylightUI.API
    local log = recorder(API, { "CraftShown", "CraftHidden", "CraftProfessionChanged", "CraftRecipeSelected" })
    T.isnil(API.GetCraftProfession(), "shut")
    PW.Open(197)
    frame(20)
    local order = {}
    for _, c in ipairs(log) do order[#order + 1] = c[1] end
    T.eq(table.concat(order, ","), "CraftShown,CraftProfessionChanged,CraftRecipeSelected")
    T.eq(log[2][2], 197, "the skill line")
    T.eq(type(log[3][2]), "number", "the first recipe picked")
    local line, name = API.GetCraftProfession()
    T.eq(line, 197); T.eq(name, "Tailoring")

    -- A pick from outside: lit, and reported once.
    T.eq(API.SelectCraftRecipe(103), true)
    frame(3)
    local sel = only(log, "CraftRecipeSelected")
    T.eq(sel[#sel][2], 103)
    T.eq(stub.craft.Window.Picked(), 103)
    T.eq(API.SelectCraftRecipe(103), true, "again: still picked")
    T.eq(#only(log, "CraftRecipeSelected"), #sel, "and not told twice")
    T.eq(API.SelectCraftRecipe(105), false, "not learned")
    T.eq(API.SelectCraftRecipe(999), false, "not there")
    T.eq(API.SelectCraftRecipe("103"), false)

    -- Another profession.
    PW.Open(185)
    frame(20)
    local prof = only(log, "CraftProfessionChanged")
    T.eq(prof[#prof][2], 185)

    PW.Close()
    frame(20)
    T.eq(#only(log, "CraftHidden"), 1)
    T.isnil(API.GetCraftProfession())
    T.eq(API.SelectCraftRecipe(103), false, "shut")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api windows: recipe lines are frames of their own, by recipe id", function()
    stub.Load({ before = PW.world({}) })
    local API = DaylightUI.API
    local log = recorder(API, { "FrameMade", "FrameRemoved", "FrameStyled" })
    PW.Open(197)
    frame(20)
    local made = only(log, "FrameMade", "craftrow")
    T.eq(#made, 4, "the learned recipes")
    local row = API.GetCraftRow(102)
    T.truthy(row, "found by its recipe")
    T.eq(row, stub.craft.List.lines[102])
    T.eq(API.GetPart(row, "name"):GetText(), "Bolt of Silk Cloth")
    T.truthy(API.Attach(row), "a holder on a line")
    T.truthy(#only(log, "FrameStyled", "craftrow") >= 4)
    -- A search: the hidden lines let go.
    stub.craft.List.Search("bolt")
    frame(3)
    T.isnil(API.GetCraftRow(101), "hidden by the search")
    T.truthy(API.GetCraftRow(104))
    PW.Close()
    frame(20)
    T.isnil(API.GetCraftRow(104), "closed: none")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api windows: making tells start, each one made, and stop", function()
    stub.Load({ before = PW.world({}) })
    local API = DaylightUI.API
    local log = recorder(API, { "CraftStarted", "CraftMade", "CraftStopped" })
    PW.Open(197)
    frame(20)
    API.SelectCraftRecipe(102)
    frame(3)
    local ns = stub.craft
    ns.Make.SetAmount(2)
    ns.Make.foot.buttons[1]:Click()
    PW.Cast()
    frame(2)
    PW.Cast()
    frame(5)
    local order = {}
    for _, c in ipairs(log) do order[#order + 1] = table.concat({ c[1], tostring(c[2]), tostring(c[3]), tostring(c[4]) }, ":") end
    T.eq(table.concat(order, ","), "CraftStarted:102:2:nil,CraftMade:102:1:2,CraftMade:102:2:2,CraftStopped:102:2:2")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api windows: a docked pane opens and closes with the window, and the game makes room", function()
    stub.Load({ before = PW.world({}) })
    local API = DaylightUI.API
    local me = API.For("PaneTester")
    local pane = me.AttachCraftPane(200)
    T.truthy(pane, "a pane")
    T.eq(me.AttachCraftPane(220), pane, "one per plugin")
    T.isnil(me.AttachCraftPane(0))
    local f = stub.craft.Window.frame
    T.eq(pane:GetParent(), f, "on the window")
    T.eq(pane:GetWidth(), 220, "the new width")
    local other = API.For("Second").AttachCraftPane(100)
    local _, rel = other:GetPoint(1)
    T.eq(rel, pane, "the next one docks beside the first")
    T.eq(stub.craft.Window.PanesWidth(), 2 * stub.craft.Window.PANE_GAP + 320)
    PW.Open(197)
    frame(20)
    T.eq(pane:IsVisible(), true, "open with the window")
    PW.Close()
    frame(20)
    T.eq(pane:IsVisible(), false, "gone with it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api windows: a pane asked for with the window switched off never shows", function()
    stub.Load({ before = PW.world({ enabled = false }) })
    local pane = DaylightUI.API.For("PaneTester").AttachCraftPane(200)
    if pane then T.eq(pane:IsVisible(), false) end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Options: the font row
-- ---------------------------------------------------------------------

T.test("api windows: a plugin's font row lands, saves a key, and API.FontFile reads it", function()
    stub.Load({ login = false })
    local DUI = DaylightUI
    local API = DUI.API
    DUI.RegisterPlugin("FontPlugin", { needs = { 1, 2 } })
    DUI:RegisterModule("FontPlugin", { label = "Font Plugin", defaults = { font = "general" } })
    local row = API.FontRow("font", "Font", "The font of its window.")
    T.eq(row.type, "dropdown")
    T.eq(row.preview, "font")
    T.isnil(API.FontRow(nil, "Font"))
    API.For("FontPlugin").AddOptionsGroup("appearance", { label = "Font Plugin", items = { row } })
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    local page, card = DUI.Options.GetPage("appearance")
    for _, g in ipairs(page.groups) do if string.find(g.label, "Font Plugin", 1, true) then card = g end end
    T.truthy(card, "landed")
    T.eq(#card.items, 1, "not left out")
    T.eq(API.FontFile(API.GetSetting("FontPlugin", "font")), DUI.Style.FONT, "general = the player's font")
    DUI.Options.Set(page, card.items[1], "expressway")
    T.eq(API.GetSetting("FontPlugin", "font"), "expressway")
    T.eq(API.FontFile("expressway"), DUI.Style.FontFileOf("expressway"))
    T.eq(API.FontFile(nil), DUI.Style.FONT)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Paint (1.3) on the vendor's tiles and the recipe lines
-- ---------------------------------------------------------------------

T.test("api windows: a painter on the vendor's tiles runs after each fill, with icon and name", function()
    stub.Load({ before = NW.world({}) })
    local API = DaylightUI.API
    local got = {}
    API.For("Neon").Paint("shoptile", function(tile, parts, info)
        got[#got + 1] = { tile, parts, info }
        parts.name:SetTextColor(1, 0, 1)
    end)
    NW.Merchant()
    frame(30)
    T.truthy(#got >= #NW.Goods(), "each tile")
    local last = got[#got]
    T.truthy(last[2].icon and last[2].name, "its pieces")
    T.eq(type(last[3]), "table", "what it holds")
    local n = #got
    stub.FireEvent("BAG_UPDATE_DELAYED")
    frame(3)
    T.truthy(#got > n, "again after a refill")
    local tile = API.GetShopTile("buy", 1)
    T.eq(API.GetPart(tile, "name"):GetTextColor(), 1, "the plugin's color on top")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api windows: a painter on the recipe lines runs as the list fills", function()
    stub.Load({ before = PW.world({}) })
    local API = DaylightUI.API
    local ids = {}
    API.For("Neon").Paint("craftrow", function(row, parts, info) ids[#ids + 1] = info end)
    PW.Open(197)
    frame(20)
    T.truthy(#ids >= 4, "each learned recipe")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
