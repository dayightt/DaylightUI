local stub = require("stub")

-- The rich tooltip: Daylight UI's own card over the game's muted tooltip, the
-- game's tooltip padded to the card's size, and the frame alone when a line
-- is secret.

local post = {}

-- A tooltip's lines as the game keeps them: <name>TextLeft<i> and Right.
local function lined(tip)
    local name = tip:GetName()
    tip.__n = 0
    local function line(side, i)
        local key = name .. "Text" .. side .. i
        _G[key] = _G[key] or tip:CreateFontString(key)
        return _G[key]
    end
    function tip:NumLines() return self.__n end
    function tip:ClearLines()
        for i = 1, self.__n do line("Left", i):SetText(nil); line("Right", i):SetText(nil) end
        self.__n = 0
    end
    function tip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
        self.__n = self.__n + 1
        local left, right = line("Left", self.__n), line("Right", self.__n)
        left:SetText(l); left:SetTextColor(lr or 1, lg or 1, lb or 1)
        right:SetText(r); right:SetTextColor(rr or 1, rg or 1, rb or 1)
    end
    function tip:AddLine(t, r, g, b) self:AddDoubleLine(t, nil, r, g, b) end
    function tip:SetOwner(owner, anchor)
        self.__owner, self.__anchor = owner, anchor
        self:ClearLines()
        local cleared = self:GetScript("OnTooltipCleared")
        if cleared then cleared(self) end
    end
    function tip:GetOwner() return self.__owner end
    function tip:GetAnchorType() return self.__anchor end
    stub.TooltipSizes(tip)
    return tip
end

local function world()
    post = {}
    Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }
    _G.TooltipDataProcessor = {
        AllTypes = "ALL",
        AddTooltipPostCall = function(kind, fn)
            post[kind] = post[kind] or {}
            table.insert(post[kind], fn)
        end,
    }
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    tip.NineSlice = CreateFrame("Frame", nil, tip)
    lined(tip)
    function tip:GetUnit() return self.__unitName, self.__unit end
    function tip:GetItem() return nil, self.__link end
    -- As the game's GameTooltip_OnShow / OnHide: the padding is cleared
    -- (GameTooltip_CalculatePadding with no embedded item, ClearPadding).
    tip:SetScript("OnShow", function(self) self:ClearPadding() end)
    tip:SetScript("OnHide", function(self) self:ClearPadding(); GameTooltip_ClearMoney(self) end)
    -- GameTooltip.xml's OnTooltipCleared: its money frames go.
    tip:SetScript("OnTooltipCleared", function(self) GameTooltip_ClearMoney(self) end)
    tip:Hide() -- as the game's, hidden until first filled
    -- The compare tooltips beside it (GameTooltip.xml: ShoppingTooltip1/2).
    tip.shoppingTooltips = { lined(stub.CompareTooltip("ShoppingTooltip1")), lined(stub.CompareTooltip("ShoppingTooltip2")) }
    CreateFrame("StatusBar", "GameTooltipStatusBar", tip)
    for _, n in ipairs({ "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }) do
        local f = stub.NewWidget("Font", n)
        function f:SetFont(file, size, flags) self.__font = { file, size, flags } end
    end
    local spot = CreateFrame("Frame", "GameTooltipDefaultContainer", UIParent)
    spot:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100)
    _G.GameTooltip_SetDefaultAnchor = function(t, parent)
        t:SetOwner(parent, "ANCHOR_NONE")
        t:ClearAllPoints()
        t:SetPoint("BOTTOMRIGHT", spot)
    end
    stub.units = {
        player = { name = "Me", class = "PRIEST", isPlayer = true },
        mouseover = { name = "Jaina", class = "MAGE", isPlayer = true },
    }
end

local function login(style)
    stub.Load({ tooltip = true, before = world })
    if style then
        DaylightUI:Set("Tooltip", "style", style)
        stub.RunTimers()
    end
    return stub.tooltip.Tooltip, stub.tooltip.RichPanel, stub.tooltip.Rich
end

-- The game filling and showing a tooltip: a new owner clears it, its lines,
-- the data's post-calls, then the fill's own Show.
local function fill(kind, lines, set)
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    for _, t in ipairs(lines) do
        if type(t) == "table" then tip:AddDoubleLine(unpack(t)) else tip:AddLine(t) end
    end
    if set then set(tip) end
    local data = { type = kind }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[kind] or {}) do fn(tip, data) end
    tip:Show()
end

local function update() GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02) end

local function used(p, kind) return p.used[kind] end

T.test("rich tooltip: off by default, the skinned look untouched", function()
    local Tip, Panel = login()
    fill(Enum.TooltipDataType.Spell, { "Frostbolt", "Hurls a bolt of frost." })
    update()
    local p = Panel.Get(GameTooltip)
    T.truthy(not p or not p:IsShown(), "no card")
    T.truthy(Tip.Shell(GameTooltip):IsShown(), "the skinned shell")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 1, "the game's lines")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a card over the muted game tooltip, carried by it", function()
    local Tip, Panel = login("rich")
    -- A data type with no painter of its own (a mailbox, a world object).
    fill(99, { "Frostbolt", { "Range", "30 yd" }, "Hurls a bolt of frost." })
    local p = Panel.Get(GameTooltip)
    T.truthy(p and p:IsShown(), "the card shows with the tooltip")
    T.eq(p:GetParent(), GameTooltip, "a child: the tooltip's alpha, fade, scale and spot carry it")
    T.eq(p.__points[1][2], GameTooltip, "pinned to the tooltip")
    T.eq(p:GetWidth(), p.wantW, "at the card's own size")
    T.truthy(p:GetFrameLevel() < GameTooltip:GetFrameLevel(), "under the tooltip's own text (the frame-only look)")
    T.isnil(p:GetScript("OnUpdate"), "nothing of its own runs every frame")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 0, "the game's lines muted")
    T.eq(GameTooltipTextRight2:GetAlpha(), 0, "both sides")
    T.eq(GameTooltip:GetAlpha() > 0 or GameTooltip:IsShown(), true, "the tooltip itself still shows (never hidden)")
    T.falsy(Tip.Shell(GameTooltip):IsShown(), "the skinned shell steps aside")
    T.eq(p.count, 3, "title, row, sentence")
    T.eq(p.items[1].kind, "header")
    T.eq(stub.Text(p.items[1].title), "Frostbolt")
    T.eq(p.items[2].kind, "row")
    T.eq(stub.Text(p.items[2].value), "30 yd")
    T.eq(p.items[3].kind, "text")
    T.eq(DaylightUI.Style.GetCut(p), 12, "the bottom-right corner cut")
    T.truthy(p.light[1]:IsShown(), "the top light")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the game's tooltip takes the card's size", function()
    local _, Panel = login("rich")
    -- A short line: the card is wider than the game's own lines (padding grows it).
    fill(Enum.TooltipDataType.Spell, { "Ice", "Cold." })
    local p = Panel.Get(GameTooltip)
    T.near(GameTooltip:GetWidth(), p.wantW * p:GetScale(), 0.01, "as wide as the card")
    T.near(GameTooltip:GetHeight(), p.wantH * p:GetScale(), 0.01, "as tall")
    -- Long lines: the game's would be wider than the card, so its padding
    -- goes below zero and it shrinks to the card.
    fill(Enum.TooltipDataType.Spell, { "Arcane Missiles", string.rep("A very long line of words. ", 4) })
    update()
    T.near(GameTooltip:GetWidth(), p.wantW * p:GetScale(), 0.01, "still the card's width")
    T.near(GameTooltip:GetHeight(), p.wantH * p:GetScale(), 0.01)
    local r = GameTooltip:GetPadding()
    T.truthy(r < 0, "a negative padding shrinks it")
    -- Once fitted, a frame later nothing is asked again.
    local calls = 0
    local orig = GameTooltip.SetPadding
    GameTooltip.SetPadding = function(...) calls = calls + 1; return orig(...) end
    update(); update()
    GameTooltip.SetPadding = nil
    T.eq(calls, 0, "idle once fitted")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: lines another addon adds after the fill join the card", function()
    local _, Panel = login("rich")
    fill(99, { "Linen Cloth", "Trade Goods" })
    local p = Panel.Get(GameTooltip)
    T.eq(p.count, 2)
    -- Another addon's line, after every post-call (a price line).
    GameTooltip:AddDoubleLine("Auction", "12s", 1, 1, 1, 1, 1, 1)
    GameTooltip:Show()
    update()
    T.eq(p.count, 3, "rebuilt with it before the next draw")
    T.eq(stub.Text(p.items[3].value), "12s")
    T.eq(GameTooltipTextLeft3:GetAlpha(), 0, "its line muted too")
    T.near(GameTooltip:GetHeight(), p.wantH * p:GetScale(), 0.01, "and fitted again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a secret line leaves the frame around the game's own lines", function()
    local _, Panel = login("rich")
    -- A thing in the world: a unit's card is built from the unit instead.
    fill(4, { "Ox Bones", "Quest item" }, function(t)
        GameTooltipTextLeft1:SetText(stub.Secret("Ox Bones"))
    end)
    update()
    local p = Panel.Get(GameTooltip)
    T.truthy(p:IsShown(), "the card's frame still shows")
    T.truthy(p.chrome, "the frame only")
    T.eq(p.count, 0, "no pieces: their size couldn't be known")
    T.eq(GameTooltipTextLeft2:GetAlpha(), 1, "the game's lines show in it")
    local r, b = GameTooltip:GetPadding()
    T.eq(r, 0); T.eq(b, 0, "no padding: the game sizes it")
    T.truthy(p.light[1]:IsShown(), "the top light still")
    -- Out of the fight: plain again, the full card.
    fill(4, { "Ox Bones", "Quest item" })
    update()
    T.falsy(p.chrome)
    T.eq(GameTooltipTextLeft2:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: hidden, the lines and padding go back; Simple puts the skinned look back", function()
    local Tip, Panel = login("rich")
    fill(Enum.TooltipDataType.Spell, { "Ice", "Cold." })
    local p = Panel.Get(GameTooltip)
    GameTooltip:Hide()
    T.falsy(p:IsShown())
    T.eq(GameTooltipTextLeft1:GetAlpha(), 1, "the game's lines back for whoever shows it next")
    fill(Enum.TooltipDataType.Spell, { "Ice", "Cold." })
    T.truthy(p:IsShown())
    DaylightUI:Set("Tooltip", "style", "simple")
    stub.RunTimers()
    update()
    T.falsy(p:IsShown(), "switched at once, no reload")
    T.truthy(Tip.Shell(GameTooltip):IsShown(), "the skinned shell back")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 1)
    local r, b = GameTooltip:GetPadding()
    T.eq(r, 0); T.eq(b, 0)
    DaylightUI:Set("Tooltip", "style", "rich")
    stub.RunTimers()
    update()
    T.truthy(p:IsShown(), "and back to Rich while it shows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: an item refilling every 0.2 s reuses its pieces", function()
    local _, Panel = login("rich")
    local function refill()
        fill(Enum.TooltipDataType.Item, { "Dawnforged Greaves", { "Armor", "742" }, "+24 Strength" })
        update()
    end
    refill()
    local p = Panel.Get(GameTooltip)
    local texts, made = used(p, "text"), #p.pool.text
    for _ = 1, 5 do refill() end
    T.eq(used(p, "text"), texts)
    T.eq(#p.pool.text, made, "no new text made")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the shared tag and value tile", function()
    login("rich")
    local W, Style = DaylightUI.Widgets, DaylightUI.Style
    local tag = W.Tag(UIParent)
    tag.Set("Frost", { 0.5, 0.8, 1 })
    T.eq(stub.Text(tag.text), "FROST", "small capitals")
    T.near(({ tag.text:GetTextColor() })[1], 0.5, 1e-6, "its meaning's color")
    T.eq(tag:GetWidth(), 5 * 7 + 2 * W.TAG_PAD, "fitted to its text")
    T.truthy(Style.GetSlant(tag), "slanted ends")
    local tile = W.Tile(UIParent)
    tile.Set("2.5 sec", "Cast")
    T.eq(stub.Text(tile.value), "2.5 sec")
    T.eq(stub.Text(tile.caption), "CAST")
    T.eq(Style.GetCut(tile), W.TILE_CUT, "its corner cut")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Players: the board's banner, rows, bars and buffs.
local function player(extra)
    stub.units.mouseover = { name = "Aelindra", lastName = "Moonvale", class = "MAGE", isPlayer = true, level = 60,
        race = "Night Elf", guild = "Dawnwatch", guildRank = "Officer", health = 80, maxHealth = 100,
        power = 50, maxPower = 100, powerToken = "MANA", friend = true }
    stub.units.mouseovertarget = { name = "Gorvak", isPlayer = false, reaction = 2 }
    for k, v in pairs(extra or {}) do stub.units.mouseover[k] = v end
end

local function hover(unit, lines)
    fill(Enum.TooltipDataType.Unit, lines, function(t) t.__unit = unit end)
    update() -- a refill of a shown tooltip builds before the next draw
end

T.test("rich tooltip: a player's card, banner first", function()
    local Tip, Panel = login("rich")
    player()
    local data = { type = Enum.TooltipDataType.Unit, lines = { {}, {}, {} } }
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Aelindra")
    tip:AddLine("Level 60 Night Elf Mage")
    tip:AddLine("<Dawnwatch>")
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    tip:AddDoubleLine("Raider score", "2140") -- another addon's, after the post-calls
    tip:Show()
    local p = Panel.Get(tip)
    local head = p.items[1]
    T.eq(head.kind, "header")
    local title = stub.Text(head.title)
    T.truthy(title:find("^Aelindra ") and title:find("Moonvale"), "first and last name: " .. title)
    T.truthy(title:find(DaylightUI.Win.Parts.Hex(DaylightUI.Style.INK.LABEL), 1, true), "the last name tan")
    T.truthy(head.icon and head.icon.tile:IsShown(), "the class icon on its class tile")
    T.eq(#head.tags, 3)
    T.eq(stub.Text(head.tags[1].text), "MAGE", "spec unknown: the class")
    T.eq(stub.Text(head.tags[2].text), "60")
    local _, lvInk = stub.tooltip.RichWorld.Level("mouseover")
    T.rgb({ head.tags[2].text:GetTextColor() }, lvInk, "the level in how hard they are for you")
    T.eq(stub.Text(head.tags[3].text), "NIGHT ELF")
    T.truthy(p.washColor, "the banner's class light")
    local rows = {}
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "row" then rows[stub.Text(it.label)] = stub.Text(it.value) end
    end
    T.truthy(rows.Guild and rows.Guild:find("Dawnwatch") and rows.Guild:find("Officer"), "guild and rank")
    T.eq(rows.Targeting, "Gorvak")
    T.eq(rows["Raider score"], "2140", "another addon's line, in the card")
    T.isnil(rows["Item level"], "never inspected: no item level")
    local bars = 0
    for i = 1, p.count do if p.items[i].kind == "bar" then bars = bars + 1 end end
    T.eq(bars, 2, "health and power")
    T.eq(GameTooltipStatusBar:GetAlpha(), 0, "the game's bar under the tooltip put away")
    T.eq(GameTooltipTextLeft4:GetAlpha(), 0, "the addon's own line muted: it's in the card")
    -- Targeting you.
    stub.units.mouseovertarget = stub.units.player
    hover("mouseover", { "Aelindra" })
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "row" and stub.Text(it.label) == "Targeting" then
            T.eq(stub.Text(it.value), "You")
            T.near(({ it.value:GetTextColor() })[1], DaylightUI.Style.INK.WARN[1], 1e-6, "in WARN")
        end
    end
    -- Back to Simple: the game's bar as its setting says.
    DaylightUI:Set("Tooltip", "style", "simple")
    stub.RunTimers()
    update()
    T.eq(GameTooltipStatusBar:GetAlpha(), 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The client's roster and map calls for a group member's zone, put back after.
local function withZones(party, raid, fn)
    local realMap, realRoster = _G.C_Map, _G.GetRaidRosterInfo
    _G.C_Map = {
        GetBestMapForUnit = function(u) return party[u] and 1429 or nil end,
        GetMapInfo = function(id) if id == 1429 then return { mapID = id, name = "Elwynn Forest" } end end,
    }
    _G.GetRaidRosterInfo = function(i)
        if i == 1 and raid then return "Aelindra", 0, 1, 60, "Mage", "MAGE", raid, true, false end
    end
    local ok, err = pcall(fn)
    _G.C_Map, _G.GetRaidRosterInfo = realMap, realRoster
    if not ok then error(err, 0) end
end

local function rowsOf(p)
    local out = {}
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "row" then out[stub.Text(it.label)] = stub.Text(it.value) end
    end
    return out
end

T.test("rich tooltip: a group member's card says where they are", function()
    local _, Panel = login("rich")
    -- A stranger: no zone, the client gives none either.
    player()
    withZones({}, nil, function()
        hover("mouseover", { "Aelindra" })
        T.isnil(rowsOf(Panel.Get(GameTooltip)).Zone, "not in your group")
        -- In your party: their map's name.
        player({ party = true })
        withZones({ mouseover = true }, nil, function()
            hover("mouseover", { "Aelindra" })
            T.eq(rowsOf(Panel.Get(GameTooltip)).Zone, "Elwynn Forest")
        end)
    end)
    -- In your raid: the roster's zone, even inside a dungeon where the map says nothing.
    player({ raid = true })
    withZones({}, "The Deadmines", function()
        hover("mouseover", { "Aelindra" })
        T.eq(rowsOf(Panel.Get(GameTooltip)).Zone, "The Deadmines")
    end)
    -- Offline: nowhere to say.
    player({ party = true, offline = true })
    withZones({ mouseover = true }, nil, function()
        hover("mouseover", { "Aelindra" })
        T.isnil(rowsOf(Panel.Get(GameTooltip)).Zone, "offline")
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("simple tooltip: a party member's zone as a line, once", function()
    local Tip = login()
    player({ party = true })
    withZones({ mouseover = true }, nil, function()
        hover("mouseover", { "Aelindra", "Level 60 Night Elf Mage" })
        T.truthy(Tip.HasLine(GameTooltip, Tip.ZONE_LABEL, "Elwynn Forest"), "the zone line")
        -- The game naming the zone itself: no second line.
        hover("mouseover", { "Aelindra", "Level 60 Night Elf Mage", "Elwynn Forest" })
        T.truthy(not Tip.HasLine(GameTooltip, Tip.ZONE_LABEL), "the game's own line is enough")
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a friendly player's buffs, out of combat only", function()
    local _, Panel = login("rich")
    DaylightUI:Set("Tooltip", "buffs", true)
    stub.RunTimers()
    player()
    stub.SetAuras("mouseover", "HELPFUL", { { spellId = 1, icon = 111 }, { spellId = 2, icon = 222 } })
    hover("mouseover", { "Aelindra" })
    local p = Panel.Get(GameTooltip)
    local icons
    for i = 1, p.count do if p.items[i].kind == "icons" then icons = p.items[i] end end
    T.truthy(icons, "a row of buff icons")
    T.eq(#icons.list, 2)
    T.eq(GameTooltip:NumLines(), 1, "no icon lines added to the game's tooltip")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: in a fight a unit is the pill by the cursor; Shift shows the card", function()
    local Tip, Panel = login("rich")
    player()
    stub.units.mouseover = { name = "Ridgeback Boar", isPlayer = false, reaction = 2, health = 31, maxHealth = 100, level = 23 }
    stub.units.mouseovertarget = stub.units.player
    stub.EnterCombat()
    hover("mouseover", { "Ridgeback Boar", "Level 23 Beast" })
    local pill = _G.DaylightUITooltipPill
    T.truthy(pill and pill:IsShown(), "the pill shows")
    T.eq(pill:GetWidth(), 200)
    T.eq(GameTooltip:GetAlpha(), 0, "the tooltip itself out of sight")
    T.eq(Tip.Muted(GameTooltip), "pill")
    T.eq(stub.Text(pill.name), "Ridgeback Boar")
    T.eq(stub.Text(pill.level), "23", "its level in front of the name")
    local _, lvInk = stub.tooltip.RichWorld.Level("mouseover")
    T.rgb({ pill.level:GetTextColor() }, lvInk, "in how hard it is for you")
    T.truthy(pill.name.__points[1][4] > 12, "the name after the level")
    -- Seen in game: an orange name on a hostile mob read as neutral.
    T.near(({ pill.name:GetTextColor() })[1], (DaylightUI.Style.ReactionColor(2)), 1e-6, "its name in its reaction's color")
    -- Seen in game: a long name ran into the health.
    stub.units.mouseover.name = "Southsea Dock Worker of the Long Name Coast"
    hover("mouseover", { "Southsea Dock Worker of the Long Name Coast" })
    T.truthy(pill.name:GetWidth() > 0 and pill.name:GetWidth() <= 200 - 2 * 12 - 4 * 7 - 8, "cut short before the health")
    stub.units.mouseover.name = "Ridgeback Boar"
    hover("mouseover", { "Ridgeback Boar" })
    T.eq(pill.name:GetWidth(), 0, "a short one keeps its own width")
    T.isnil(pill:GetScript("OnUpdate"), "nothing of its own every frame")
    local p = Panel.Get(GameTooltip)
    T.truthy(not p or not p:IsShown(), "no card under it")
    -- Placed where its owner put the tooltip (this one: by hand).
    T.eq(pill.__points[1][2], GameTooltip, "the tooltip's spot")
    -- Shift: the full card at once.
    stub.shift = true
    update()
    T.falsy(pill:IsShown())
    T.isnil(Tip.Muted(GameTooltip))
    T.truthy(Panel.Get(GameTooltip):IsShown(), "the card")
    stub.shift = false
    update()
    T.truthy(pill:IsShown(), "let go: the pill again")
    -- The fight over: the card.
    stub.LeaveCombat()
    update()
    T.falsy(pill:IsShown())
    T.truthy(Panel.Get(GameTooltip):IsShown())
    stub.EnterCombat()
    update()
    T.truthy(pill:IsShown())
    GameTooltip:Hide()
    T.falsy(pill:IsShown(), "gone with the tooltip")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the pill can be never or always", function()
    local Tip = login("rich")
    player()
    DaylightUI:Set("Tooltip", "pill", "never")
    stub.RunTimers()
    stub.EnterCombat()
    hover("mouseover", { "Aelindra" })
    local pill = _G.DaylightUITooltipPill
    T.truthy(not pill or not pill:IsShown(), "never")
    stub.LeaveCombat()
    DaylightUI:Set("Tooltip", "pill", "always")
    stub.RunTimers()
    hover("mouseover", { "Aelindra" })
    pill = _G.DaylightUITooltipPill
    T.truthy(pill and pill:IsShown(), "always, out of a fight too")
    local r = ({ pill.name:GetTextColor() })[1]
    T.near(r, (DaylightUI.Style.ClassColor("MAGE")), 1e-6, "a player's name in their class color")
    T.near(({ pill.name:GetTextColor() })[1], (DaylightUI.Style.ClassColor("MAGE")), 1e-6, "not on anyone: its own color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the mail icon's "Unread mail from:" cut short with "...", in
-- the game's yellow.
T.test("rich tooltip: a short card's title is never cut, a yellow heading is white", function()
    local _, Panel = login("rich")
    fill(99, { { "Unread mail from:", nil, 1, 0.82, 0 }, "Thrall" })
    local p = Panel.Get(GameTooltip)
    local title = p.items[1].title
    T.eq(title:GetWidth(), 0, "no width set: nothing cut")
    T.near(({ title:GetTextColor() })[1], DaylightUI.Style.INK.TITLE[1], 1e-6, "white")
    T.eq(stub.Text(p.items[2].fs), "Thrall", "the senders under it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a creature's quest lines came through as plain sentences.
T.test("rich tooltip: quest lines as headings in their difficulty color, objectives with bars", function()
    local _, Panel = login("rich")
    DaylightUI.Npc.Data.QuestColor = function(id) return id == 77 and { 0.1, 0.9, 0.1 } or { 0.9, 0.5, 0.1 } end
    _G.C_QuestLog = _G.C_QuestLog or {}
    C_QuestLog.GetNumQuestLogEntries = function() return 1 end
    C_QuestLog.GetInfo = function(i) return { title = "Southsea Shakedown", questID = 88 } end
    stub.units.mouseover = { name = "Southsea Pirate", isPlayer = false, reaction = 2, level = 44, health = 50, maxHealth = 100 }
    local data = { type = Enum.TooltipDataType.Unit, lines = { {}, {}, { type = 17, id = 77 }, { type = 8 } } }
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Southsea Pirate")
    tip:AddLine("Level 44")
    tip:AddLine("Pirate Hats Ahoy!")                    -- the game's quest title (typed)
    tip:AddLine(" - 0/20 Southsea Pirate Hat")          -- the game's objective (typed)
    tip:AddLine("Southsea Shakedown")                   -- Questie's: text only
    tip:AddLine("   |cffffffffSouthsea Pirate: 3/10|r |cff999999[37%]|r")
    tip:AddLine("   |cffffffffBuccaneer slain: 5/5|r")
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    tip:Show()
    local p = Panel.Get(tip)
    local sections, rows, bars, rules = {}, {}, 0, 0
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "section" then sections[#sections + 1] = it end
        if it.kind == "row" then rows[#rows + 1] = it end
        if it.kind == "bar" and it.spec.value then bars = bars + 1 end
        if it.kind == "rule" then rules = rules + 1 end
    end
    T.eq(#sections, 2, "two quests")
    T.eq(stub.Text(sections[1].fs), "PIRATE HATS AHOY!")
    T.near(({ sections[1].fs:GetTextColor() })[2], 0.9, 1e-6, "its difficulty color from the quest id")
    T.near(({ sections[2].fs:GetTextColor() })[1], 0.9, 1e-6, "Questie's: found by name in the log")
    T.eq(#rows, 3)
    T.eq(stub.Text(rows[1].label), "Southsea Pirate Hat")
    T.eq(stub.Text(rows[1].value), "0 / 20")
    T.truthy(stub.Text(rows[2].label):find("37%%"), "Questie's drop chance kept beside it")
    T.eq(stub.Text(rows[3].value), "Complete", "a finished one")
    T.near(({ rows[3].label:GetTextColor() })[1], DaylightUI.Style.INK.OFF[1], 1e-6, "dimmed")
    T.eq(bars, 2, "a bar under each one still going")
    T.eq(rules, 1, "a rule before the quests")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a full health bar's angled end showed a black corner.
T.test("rich tooltip: a bar's track is cut at the same angle as its fill", function()
    login("rich")
    local Panel, Style = stub.tooltip.RichPanel, DaylightUI.Style
    local bar = Panel.MakeBar(UIParent)
    Panel.ShapeBar(bar, 7)
    T.eq(Style.GetCut(bar), 7, "the track's corner, 45 degrees over the bar's height")
    T.eq(select(2, Style.GetFillAngle(bar)), 7, "the fill's end, the same")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: in a fight the pill rode the cursor whatever the Tooltip
-- position, and stayed 2-3 s after the mouse left the mob.
T.test("rich tooltip: the pill sits where the tooltip would, and goes when the mouse leaves", function()
    local Tip = login("rich")
    stub.units.mouseover = { name = "Southsea Swashbuckler", isPlayer = false, reaction = 2, health = 87, maxHealth = 100 }
    stub.EnterCombat()
    local function world()
        local tip = GameTooltip
        GameTooltip_SetDefaultAnchor(tip, UIParent)
        tip.__unit = "mouseover"
        tip:AddLine("Southsea Swashbuckler")
        local data = { type = Enum.TooltipDataType.Unit }
        for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
        for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
        tip:Show()
        update()
    end
    world()
    local pill = _G.DaylightUITooltipPill
    T.truthy(pill:IsShown())
    T.eq(pill.__points[1][2], Tip.anchor, "Default position: at the tooltip's spot")
    T.eq(pill.__points[1][1], "BOTTOMRIGHT", "growing from the spot's corner")
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    world()
    stub.cursorPos = { 500, 300 }
    update()
    local x = pill.__points[1][4]
    stub.cursorPos = { 600, 300 }
    update()
    T.truthy(pill.__points[1][4] > x, "At the cursor: it follows the mouse")
    -- The mouse leaves the mob: nothing under it now.
    _G.C_TooltipInfo = _G.C_TooltipInfo or {}
    C_TooltipInfo.GetWorldCursor = function() return nil end
    stub.units.mouseover = nil
    Tip.OnWorldCursor()
    T.falsy(pill:IsShown(), "Fade out world tooltips off: gone at once")
    -- With it on: a short fade, not the game's seconds.
    DaylightUI:Set("Tooltip", "fadeOut", true)
    stub.RunTimers()
    stub.units.mouseover = { name = "Southsea Swashbuckler", isPlayer = false, reaction = 2, health = 87, maxHealth = 100 }
    world()
    T.truthy(pill:IsShown())
    stub.units.mouseover = nil
    Tip.OnWorldCursor()
    T.truthy(pill:IsShown(), "fading")
    local M = DaylightUI.Motion
    local d = M.Driver()
    if d then stub.RunOnUpdate(d, M.SLOW + 0.05) end
    T.falsy(pill:IsShown(), "gone after SLOW")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the full card key can be another key, or none", function()
    login("rich")
    stub.units.mouseover = { name = "Gorvak", isPlayer = false, reaction = 2, health = 31, maxHealth = 100 }
    stub.EnterCombat()
    hover("mouseover", { "Gorvak" })
    local pill = _G.DaylightUITooltipPill
    T.truthy(pill:IsShown())
    DaylightUI:Set("Tooltip", "pillKey", "ctrl")
    stub.RunTimers()
    update()
    stub.shift = true
    update()
    T.truthy(pill:IsShown(), "Shift does nothing now")
    stub.shift, stub.ctrl = nil, true
    update()
    T.falsy(pill:IsShown(), "Ctrl shows the card")
    DaylightUI:Set("Tooltip", "pillKey", "none")
    stub.RunTimers()
    update()
    T.truthy(pill:IsShown(), "None: the pill stays")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Items: the board's item card and compare card. The game's own words and
-- line formats (GlobalStrings), and the items this test knows.
local GREEN, GRAY, YELLOW = { 0.1, 1, 0.1 }, { 0.5, 0.5, 0.5 }, { 1, 0.82, 0 }

local function items()
    _G.ARMOR_TEMPLATE, _G.DAMAGE_TEMPLATE, _G.DPS_TEMPLATE = "%s Armor", "%s - %s Damage", "(%s damage per second)"
    _G.DURABILITY_TEMPLATE, _G.ITEM_LEVEL = "Durability %d / %d", "Item Level %d"
    _G.ITEM_SET_NAME, _G.ITEM_SET_BONUS, _G.ITEM_SET_BONUS_GRAY = "%s (%d/%d)", "Set: %s", "(%d) Set: %s"
    _G.ITEM_SPELL_TRIGGER_ONEQUIP, _G.ITEM_SPELL_TRIGGER_ONUSE = "Equip:", "Use:"
    _G.SELL_PRICE, _G.EQUIPPED, _G.ARMOR, _G.DAMAGE = "Sell Price", "Equipped", "Armor", "Damage"
    _G.ITEM_DELTA_DESCRIPTION = "If you replace this item, the following stat changes will occur:"
    _G.SHIFT_KEY_TEXT, _G.CTRL_KEY_TEXT = "Shift", "Ctrl"
    _G.INVTYPE_LEGS, _G.INVTYPE_WEAPON = "Legs", "One-Hand"
    stub.SetItems({
        greaves = { id = 19001, quality = 4, kind = "Armor", sub = "Plate", equip = "INVTYPE_LEGS", icon = 135000,
            class = 4, subClass = 4, level = 66, dressable = true },
        legplates = { id = 19002, quality = 3, kind = "Armor", sub = "Plate", equip = "INVTYPE_LEGS", icon = 135001,
            class = 4, subClass = 4, level = 58, dressable = true },
        sword = { id = 19003, quality = 3, kind = "Weapon", sub = "Swords", equip = "INVTYPE_WEAPON", icon = 135002,
            class = 2, level = 60 },
        cloth = { id = 2589, quality = 1, kind = "Tradeskill", sub = "Cloth", icon = 132889, class = 7 },
    })
end

-- The game filling a tooltip with an item: its lines (each { left, right,
-- color } or text), its data's own lines (types: line types by index), the
-- post-calls, then Show.
local function fillItem(tip, link, list, after, types)
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__link = link
    local own = {}
    for i, t in ipairs(list) do
        if type(t) == "table" then
            local c = t[3] or { 1, 1, 1 }
            tip:AddDoubleLine(t[1], t[2], c[1], c[2], c[3], 1, 1, 1)
        else
            tip:AddLine(t)
        end
        own[i] = { type = types and types[i] or nil }
    end
    local data = { type = Enum.TooltipDataType.Item, hyperlink = link, lines = own }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    if after then after(tip) end
    tip:Show()
end

local EPIC = { 0.639, 0.208, 0.933 }
local GREAVES = {
    { "Dawnforged Greaves", nil, EPIC },
    "Binds when equipped",
    { "Legs", "Plate" },
    "742 Armor",
    "+24 Strength",
    "+31 Stamina",
    "Durability 98 / 100",
    { "Item Level 66", nil, YELLOW },
    { "Equip: Improves your chance to get a critical strike by 1%.", nil, GREEN },
    "",
    { "Dawnforged Battlegear (2/5)", nil, YELLOW },
    { "  Dawnforged Helm", nil, GRAY },
    "  Dawnforged Greaves",
    "",
    { "Set: Increases attack power by 40.", nil, GREEN },
    { "(4) Set: 5% chance on hit to heal you for 120.", nil, GRAY },
    "Sell Price: 3|A:coin-gold:0:0|a 42|A:coin-silver:0:0|a",
}

local function kinds(p, kind)
    local out = {}
    for i = 1, p.count do if p.items[i].kind == kind then out[#out + 1] = p.items[i] end end
    return out
end

T.test("rich tooltip: an item's card, as the board lays it out", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    local p = Panel.Get(GameTooltip)
    T.eq(p.kind, "item")
    T.near(GameTooltip:GetWidth(), 290 * p:GetScale(), 0.01, "the board's 290, fitted")
    local head = p.items[1]
    T.eq(head.kind, "header")
    T.eq(stub.Text(head.title), "Dawnforged Greaves")
    local lift = stub.tooltip.RichItems.Lift(EPIC)
    T.near(({ head.title:GetTextColor() })[1], lift[1], 1e-6, "the name in the quality's light end")
    T.eq(head.icon:GetWidth(), 44, "a 44 px icon")
    T.truthy(head.icon.edge:IsShown() and head.icon.glow:IsShown(), "in a quality outline and glow")
    T.near(({ head.icon.edge:GetVertexColor() })[1], EPIC[1], 1e-6)
    T.eq(stub.Text(head.tags[1].text), "ILVL 66")
    T.eq(stub.Text(head.tags[2].text), "LEGS")
    T.eq(stub.Text(head.tags[3].text), "PLATE", "the armor type a tag of its own")
    local plate = stub.tooltip.RichItems.ARMOR_COLORS[4]
    T.near(({ head.tags[3].text:GetTextColor() })[2], plate[2], 1e-6, "in plate's color")
    T.eq(stub.Text(head.tags[4].text), "BINDS WHEN EQUIPPED", "its binding a tag under its name, as the game puts it")
    T.truthy(p.washDown and p.wash[1]:IsShown(), "the quality washing down from the top")
    T.truthy(p.lightFade, "the light fades out along its right part")
    -- One column of numbers, number first at the left edge, as the game
    -- writes them: armor, then each stat in its color.
    local lines = kinds(p, "line")
    local Tip = stub.tooltip.Tooltip
    local hex = DaylightUI.Win.Parts.Hex
    T.eq(stub.Text(lines[1].fs), hex({ DaylightUI.Style.Pop() }) .. "742|r Armor", "a plain number in the accent")
    T.eq(stub.Text(lines[2].fs), hex(Tip.STAT_COLORS.Strength) .. "+24|r Strength", "the number in its stat's color")
    T.eq(stub.Text(lines[3].fs), hex(Tip.STAT_COLORS.Stamina) .. "+31|r Stamina")
    T.eq(stub.Text(lines[4].fs), hex(Tip.STAT_COLORS.Crit) .. "+1%|r Crit")
    T.eq(stub.Text(lines[4].tail), "Equip", "an Equip line's stat says so after it")
    T.isnil(lines[2].tail)
    T.truthy(stub.Text(lines[5].fs):find("^DAWNFORGED BATTLEGEAR "), "the set's name")
    T.truthy(stub.Text(lines[5].fs):find("2/5", 1, true), "its count")
    local texts = kinds(p, "text")
    local said = {}
    for _, t in ipairs(texts) do said[#said + 1] = stub.Text(t.fs) end
    T.eq(said[1], "+40 Attack Power", "a bonus you have, short")
    T.near(({ texts[1].fs:GetTextColor() })[1], DaylightUI.Style.INK.GOOD[1], 1e-6)
    T.eq(said[2], "(4) 5% chance on hit to heal you for 120.", "one you don't")
    T.near(({ texts[2].fs:GetTextColor() })[1], DaylightUI.Style.INK.OFF[1], 1e-6)
    T.eq(#said, 2, "nothing else in words")
    for _, t in ipairs(said) do T.falsy(t:find("Binds", 1, true), "the binding only in its tag") end
    for _, t in ipairs(said) do
        T.falsy(t:find("Dawnforged Helm", 1, true), "the set's pieces left out: the count says it")
        T.falsy(t:find("Item Level", 1, true), "item level only in its tag")
    end
    local rows = kinds(p, "row")
    local foot = rows[#rows]
    T.eq(stub.Text(foot.label), "Durability 98 / 100")
    T.truthy(stub.Text(foot.value):find("3", 1, true) and stub.Text(foot.value):find("42", 1, true), "the sell price")
    T.falsy(stub.Text(foot.value):find("Sell Price", 1, true))
    T.eq(#kinds(p, "hints"), 0, "no key hints: the card is what you read")
    T.eq(#kinds(p, "rule"), 2, "a rule between the parts: the numbers, the words, the foot")
    for i = 1, GameTooltip:NumLines() do T.eq(_G["GameTooltipTextLeft" .. i]:GetAlpha(), 0, "the game's lines muted") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: an item's number lines sit evenly, armor and block on one line", function()
    local _, Panel = login("rich")
    items()
    _G.SHIELD_BLOCK_TEMPLATE, _G.BLOCK = "%d Block", "Block"
    -- Seen in game: each row measured from its own text came out a few pixels
    -- taller or shorter, so the stats sat at uneven gaps. Here every text
    -- measures a different height by its letters.
    stub.measure = function(fs)
        local t = fs.__text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return #t * 7, 14 + (#t % 4)
    end
    fillItem(GameTooltip, "greaves", { { "Chromite Shield", nil, { 0, 0.44, 0.87 } }, "1436 Armor", "21 Block",
        "+9 Strength", "+5 Stamina", "+12 Agility" })
    local p = Panel.Get(GameTooltip)
    local row = kinds(p, "row")[1]
    local ys = { row and row.y }
    for _, l in ipairs(kinds(p, "line")) do ys[#ys + 1] = l.y end
    stub.measure = nil
    T.truthy(row and stub.Text(row.label):find("1436|r Armor", 1, true), "armor on the left")
    T.truthy(row and stub.Text(row.value):find("21|r Block", 1, true), "block on the same line")
    T.eq(#ys, 4)
    for i = 3, #ys do T.near(ys[i] - ys[i - 1], ys[2] - ys[1], 1e-6, "row " .. i .. " the same step") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a weapon's damage and speed as rows, a plain item's card", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "sword", { { "Thunderforge Blade", nil, { 0, 0.44, 0.87 } }, { "One-Hand", "Sword" },
        { "41 - 77 Damage", "Speed 2.60" }, "(22.7 damage per second)", "+5 Agility" })
    local p = Panel.Get(GameTooltip)
    local function bare(fs) return (stub.Text(fs):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local said = {}
    for _, l in ipairs(kinds(p, "line")) do said[#said + 1] = bare(l.fs) end
    local row = kinds(p, "row")[1]
    T.eq(bare(row.label), "41 - 77 Damage", "number first")
    T.eq(bare(row.value), "2.60 Speed", "speed on the damage's line, at the right")
    T.eq(said[1], "(22.7 damage per second)", "the game's own brackets, under them")
    T.eq(stub.Text(p.items[1].tags[2].text), "ONE-HAND", "the slot")
    T.eq(stub.Text(p.items[1].tags[3].text), "SWORD", "the slot line's own word, a tag of its own")
    local RI = stub.tooltip.RichItems
    T.rgb({ p.items[1].tags[2].text:GetTextColor() }, RI.SLOT_WEAPON, "a weapon's slot")
    T.rgb({ p.items[1].tags[3].text:GetTextColor() }, RI.WEAPON_COLOR, "a weapon's type")
    -- Linen Cloth: common, no level, no slot.
    fillItem(GameTooltip, "cloth", { "Linen Cloth", "Max Stack: 20" })
    update() -- refilled while shown: built before the next draw
    p = Panel.Get(GameTooltip)
    local head = p.items[1]
    T.near(({ head.title:GetTextColor() })[1], DaylightUI.Style.INK.TITLE[1], 1e-6, "common: a white title")
    T.falsy(head.icon.edge:IsShown(), "no quality outline")
    T.eq(#head.tags, 1)
    T.eq(stub.Text(head.tags[1].text), "TRADESKILL · CLOTH")
    T.falsy(p.lightFade, "the accent's light, not a quality")
    T.eq(#kinds(p, "hints"), 0, "nothing to compare or try on")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: an epic item's light sweeps once, not on every refill", function()
    local _, Panel = login("rich")
    items()
    local P = stub.tooltip.RichPanel
    local swept = 0
    local orig = P.Sweep
    P.Sweep = function(...) swept = swept + 1; return orig(...) end
    fillItem(GameTooltip, "greaves", GREAVES)
    T.eq(swept, 1, "on show")
    T.truthy(Panel.Get(GameTooltip).sweep:IsShown(), "running")
    for _ = 1, 3 do fillItem(GameTooltip, "greaves", GREAVES); update() end
    T.eq(swept, 1, "the 0.2 s refills: no new sweep")
    fillItem(GameTooltip, "legplates", { { "Tarnished Legplates", nil, { 0, 0.44, 0.87 } } })
    update()
    T.eq(swept, 1, "a rare one: none")
    GameTooltip:Hide()
    Panel.Get(GameTooltip).sweep:Hide()
    stub.EnterCombat()
    fillItem(GameTooltip, "greaves", GREAVES)
    T.eq(swept, 2, "asked again after a hide")
    T.falsy(Panel.Get(GameTooltip).sweep:IsShown(), "but not in a fight")
    P.Sweep = orig
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the quote ("Miners need a mining pick for digging.") read
-- as one more line. It's in the accent, small.
T.test("rich tooltip: a thing's quote is in the accent", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "cloth", { "Linen Cloth", { '"Woven from the finest flax."', nil, { 1, 0.82, 0 } } })
    local p = Panel.Get(GameTooltip)
    local quote
    for _, t in ipairs(kinds(p, "text")) do if stub.Text(t.fs):find("flax", 1, true) then quote = t end end
    T.truthy(quote, "the quote on the item card")
    local r, g, b = DaylightUI.Style.Accent()
    T.near(({ quote.fs:GetTextColor() })[1], r, 1e-6, "in the accent")
    T.eq(quote.fs.size, DaylightUI.Style.SIZE.small)
    -- Any other card (a world thing): the same.
    fill(99, { "Copper Vein", { '"Miners need a mining pick for digging."', nil, 1, 0.82, 0 } })
    update()
    p = Panel.Get(GameTooltip)
    quote = nil
    for _, t in ipairs(kinds(p, "text")) do if stub.Text(t.fs):find("Miners", 1, true) then quote = t end end
    T.truthy(quote)
    T.near(({ quote.fs:GetTextColor() })[2], g, 1e-6, "in the accent")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's compare: the item's own lines (the post-calls run here), then
-- TooltipComparisonManager adds a blank line, its "If you replace" line and
-- the changes, then shows it.
local LEGPLATES = { { "Tarnished Legplates", nil, { 0, 0.439, 0.867 } }, { "Legs", "Plate" }, "646 Armor", "+16 Strength" }
local CHANGES = { "+8 Strength", "+11 Stamina", "+1% Crit", "-96 Armor" }

local function compare(tip, changes, addon)
    tip:SetOwner(GameTooltip, "ANCHOR_NONE")
    tip.CompareHeader:Show()
    tip.CompareHeader.Label:SetText("Equipped")
    fillItem(tip, "legplates", LEGPLATES, function(t)
        if addon then t:AddDoubleLine(addon[1], addon[2]) end
        if changes then
            t:AddLine(" ")
            t:AddLine(ITEM_DELTA_DESCRIPTION, 1, 0.82, 0)
            for _, c in ipairs(changes) do t:AddLine(c) end
        end
    end)
end

-- Seen in game: the board's small compare card next to the full item card
-- read as two different things. The compare is the same card, under its
-- Equipped tag, with what changes at the bottom.
T.test("rich tooltip: a compare tooltip is the same card as the item's, its changes at the bottom", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    local shop = ShoppingTooltip1
    compare(shop, CHANGES)
    local p = Panel.Get(shop)
    local main = Panel.Get(GameTooltip)
    T.truthy(p and p:IsShown(), "a card on the compare tooltip")
    T.eq(p.wantW, main.wantW, "as wide as the item's card")
    T.near(shop:GetHeight(), p.wantH * p:GetScale(), 0.01)
    T.eq(p.items[1].kind, "tags")
    T.eq(stub.Text(p.items[1].list[1].text), "EQUIPPED", "the tag on top")
    T.eq(shop.CompareHeader:GetAlpha(), 0, "the game's tab out of sight")
    local head = p.items[3]
    T.eq(head.kind, "header", "then the item card's own header")
    T.eq(stub.Text(head.title), "Tarnished Legplates")
    T.near(({ head.title:GetTextColor() })[3], stub.tooltip.RichItems.Lift({ 0, 0.439, 0.867 })[3], 1e-6, "in its quality")
    T.truthy(head.icon and head.icon:IsShown(), "its icon")
    T.eq(stub.Text(head.tags[1].text), "ILVL 58")
    T.eq(stub.Text(head.tags[2].text), "LEGS")
    T.eq(stub.Text(head.tags[3].text), "PLATE")
    local lines = kinds(p, "line")
    T.truthy(stub.Text(lines[1].fs):find("646|r Armor", 1, true), "the same number lines as the item's")
    T.truthy(stub.Text(lines[2].fs):find("+16|r Strength", 1, true))
    local last = p.items[p.count]
    T.eq(last.kind, "tags", "the changes last")
    T.eq(#last.list, 4)
    T.eq(stub.Text(last.list[1].text), "+8 STR")
    T.near(({ last.list[1].text:GetTextColor() })[1], DaylightUI.Style.INK.GOOD[1], 1e-6, "a gain")
    T.eq(stub.Text(last.list[3].text), "+1% CRIT")
    T.eq(stub.Text(last.list[4].text), "\226\136\14696 ARMOR", "a loss with a real minus sign")
    T.near(({ last.list[4].text:GetTextColor() })[1], DaylightUI.Style.INK.DAMAGE[1], 1e-6)
    T.eq(p.items[p.count - 1].kind, "rule", "under a rule")
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "text" then T.falsy(stub.Text(it.fs):find("If you replace", 1, true), "the game's change heading left out") end
    end
    T.eq(#kinds(p, "hints"), 0, "no key hints on a compare")
    -- Gone: the tab and its padding back for the skinned look.
    shop:Hide()
    T.eq(shop.CompareHeader:GetAlpha(), 1)
    local r, b = shop:GetPadding()
    T.eq(r, 0); T.eq(b, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: change lines added while a compare tooltip shows join its card next frame", function()
    local _, Panel = login("rich")
    items()
    local shop = ShoppingTooltip2
    -- Another addon's line comes in the fill, before the game's changes.
    compare(shop, nil, { "Pawn", "+12%" })
    local p = Panel.Get(shop)
    T.eq(#kinds(p, "tags"), 1, "no chips yet")
    local pawn
    for _, r in ipairs(kinds(p, "row")) do if stub.Text(r.label) == "Pawn" then pawn = r end end
    T.eq(pawn and stub.Text(pawn.value), "+12%", "the addon's line in the card")
    shop:AddLine(" ")
    shop:AddLine(ITEM_DELTA_DESCRIPTION, 1, 0.82, 0)
    shop:AddLine("+3 Agility")
    shop:Show() -- as the game's AnchorShoppingTooltips (SetShown) after its lines
    shop:GetScript("OnUpdate")(shop, 0.02)
    T.eq(#kinds(p, "tags"), 2, "the chips, before the next draw")
    T.eq(stub.Text(kinds(p, "tags")[2].list[1].text), "+3 AGI")
    T.near(shop:GetHeight(), p.wantH * p:GetScale(), 0.01, "fitted again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: compare tooltips keep the skinned look in Simple", function()
    local Tip, Panel = login()
    items()
    compare(ShoppingTooltip1, CHANGES)
    local p = Panel.Get(ShoppingTooltip1)
    T.truthy(not p or not p:IsShown(), "no card")
    T.eq(ShoppingTooltip1.CompareHeader:GetAlpha(), 1, "the tab shows")
    T.truthy(Tip.Shell(ShoppingTooltip1):IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the icon a solid square of the quality color (the outline
-- drawn over the art), the art showing for a moment before its mask loaded.
T.test("rich tooltip: an item's quality outline sits under its art", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    local ic = Panel.Get(GameTooltip).items[1].icon
    local artLayer, artSub = ic.art:GetDrawLayer()
    local edgeLayer, edgeSub = ic.edge:GetDrawLayer()
    T.eq(artLayer, edgeLayer)
    T.truthy(artSub > edgeSub, "the art on top, the outline a ring around it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game with DaylightMogul: it rewrites the game's Sell Price line as
-- "Vendor price" with the coins on the right, and the foot read "ce".
T.test("rich tooltip: a sell price line another addon rewrote keeps its coins", function()
    local _, Panel = login("rich")
    items()
    local list = { { "Chromite Greaves", nil, { 0.118, 1, 0 } }, "Soulbound", { "Feet", "Plate" }, "294 Armor",
        "Durability 51 / 55", { "Vendor price", "1g 25s" } }
    fillItem(GameTooltip, "greaves", list, nil, { [6] = 11 })
    local p = Panel.Get(GameTooltip)
    local rows = kinds(p, "row")
    local foot = rows[#rows]
    T.eq(stub.Text(foot.label), "Durability 51 / 55")
    T.eq(stub.Text(foot.value), "1g 25s", "the coins from its right side")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: so many rules the card wasted space. A rule only between
-- the card's parts: its numbers, what it says in words, its foot.
T.test("rich tooltip: rules only between the card's big parts", function()
    local _, Panel = login("rich")
    items()
    local list = { { "Chromite Greaves", nil, { 0.118, 1, 0 } }, "Soulbound", { "Legs", "Plate" }, "294 Armor",
        "+4 Strength", "+12 Stamina", "Durability 51 / 55", "Requires Level 40",
        "Sell Price: 1|A:coin-gold:0:0|a 25|A:coin-silver:0:0|a" }
    fillItem(GameTooltip, "greaves", list, function(t) t:AddDoubleLine("AH price", "1g 25s") end)
    local p = Panel.Get(GameTooltip)
    T.eq(#kinds(p, "rule"), 2, "armor and stats | requirements | the foot with other addons' lines")
    -- The board's set item: armor and stats | set | foot.
    fillItem(GameTooltip, "greaves", GREAVES)
    update()
    T.eq(#kinds(p, "rule"), 2)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A fill, then a hide and a show in the same frame (an owner refilling it):
-- the card must be built on that show, never the skinned look.
T.test("rich tooltip: a fill then a quick hide and show still gets its card", function()
    local Tip, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    local p = Panel.Get(GameTooltip)
    fillItem(GameTooltip, "legplates", LEGPLATES, function(t) t:Hide() end)
    T.truthy(p:IsShown(), "the card")
    T.eq(stub.Text(p.items[1].title), "Tarnished Legplates", "for what it shows now")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 0, "the game's lines muted")
    T.falsy(Tip.Shell(GameTooltip):IsShown(), "the skinned look out of sight")
    -- Hidden and shown with nothing new: the same card again.
    GameTooltip:Hide()
    GameTooltip:Show()
    T.truthy(p:IsShown())
    T.eq(GameTooltipTextLeft1:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game refills the compare tooltips from the main tooltip's own update
-- (an item button's UpdateTooltip, every 0.2 s while Shift is held): their
-- cards are rebuilt then, before anything is drawn.
T.test("rich tooltip: compare tooltips refilled in the main tooltip's update are rebuilt before the draw", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    compare(ShoppingTooltip1, CHANGES)
    local p = Panel.Get(ShoppingTooltip1)
    -- Refilled with one change less, while shown, then the main tooltip's update.
    compare(ShoppingTooltip1, { "+8 Strength" })
    update()
    T.eq(#kinds(p, "tags")[2].list, 1, "rebuilt in the same frame")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the card could be seen arranging itself as it showed. It's
-- its own size from the first frame, pinned at the corner the tooltip is
-- anchored by, even before the tooltip has taken its padding.
T.test("rich tooltip: the card is its own size at once, pinned where the tooltip is anchored", function()
    local _, Panel = login("rich")
    items()
    local tip = GameTooltip
    -- The client taking the padding a frame late.
    local orig = tip.SetPadding
    tip.SetPadding = function() end
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100)
    fillItem(tip, "greaves", GREAVES)
    local p = Panel.Get(tip)
    T.eq(p.__points[1][1], "BOTTOMRIGHT", "pinned at the tooltip's own corner")
    T.eq(p.__points[1][2], tip)
    T.eq(p:GetWidth(), p.wantW, "its own width")
    T.eq(p:GetHeight(), p.wantH, "and height, whatever the tooltip's size now")
    tip.SetPadding = orig
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: something new in a showing card fades its words in; a refill doesn't", function()
    local _, Panel = login("rich")
    items()
    local M = DaylightUI.Motion
    fillItem(GameTooltip, "greaves", GREAVES)
    local p = Panel.Get(GameTooltip)
    T.eq(p.body:GetAlpha(), 1, "a first show: the tooltip's own fade does it")
    -- The 0.2 s refill of the same item.
    fillItem(GameTooltip, "greaves", GREAVES)
    update()
    T.eq(p.body:GetAlpha(), 1, "a refill: no fade")
    -- Another bag slot.
    fillItem(GameTooltip, "legplates", LEGPLATES)
    update()
    T.eq(p.body:GetAlpha(), 0, "new content starts clear")
    T.eq(p.shell:GetAlpha(), 1, "the frame stays")
    local d = M.Driver()
    if d then stub.RunOnUpdate(d, M.FAST + 0.02) end
    T.eq(p.body:GetAlpha(), 1, "there after FAST")
    -- In a fight: at once.
    stub.EnterCombat()
    fillItem(GameTooltip, "greaves", GREAVES)
    update()
    T.eq(p.body:GetAlpha(), 1, "in a fight it shows at once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Spells: the board's spell card, the cooldown card on an
-- action button, and the frame alone in a fight. The game's own words
-- (GlobalStrings) and what C_Spell answers for the spells this test knows.
local WHITE_LINE, RANK_GRAY = { 1, 1, 1 }, { 0.5, 0.5, 0.5 }

local function spells()
    _G.MANA, _G.DAMAGE = "Mana", "Damage"
    _G.STRING_SCHOOL_FROST, _G.STRING_SCHOOL_SHADOW, _G.STRING_SCHOOL_ARCANE = "Frost", "Shadow", "Arcane"
    Enum.TooltipDataType.UnitAura, Enum.TooltipDataType.Macro = 7, 25
    Enum.TooltipDataLineType = { SpellName = 13, SpellDescription = 34 }
    stub.spells = {
        [116] = { name = "Frostbolt", icon = 135846, cast = 2500, cost = 120 },
        [172] = { name = "Corruption", icon = 136118, cast = 0, cost = 35 },
    }
    C_Spell.GetSpellTexture = function(id) local s = stub.spells[id]; return s and s.icon end
    C_Spell.GetSpellName = function(id) local s = stub.spells[id]; return s and s.name end
    C_Spell.GetSpellInfo = function(id)
        local s = stub.spells[id]
        return s and { name = s.name, castTime = s.cast, spellID = id }
    end
    C_Spell.GetSpellPowerCost = function(id)
        local s = stub.spells[id]
        return s and { { type = 0, name = "MANA", cost = s.cost } }
    end
    stub.spellPower = 40
    _G.GetSpellBonusDamage = function() return stub.spellPower end
    _G.GetSpellBonusHealing = function() return stub.spellPower end
end

-- The game filling the tooltip with a spell (owner: what it's on, else the
-- screen), then Show. Each line { left, right, color, rightColor } or text.
local function fillSpell(id, list, kind, owner, dataLines)
    local tip = GameTooltip
    tip:SetOwner(owner or UIParent, "ANCHOR_NONE")
    local own = {}
    for i, t in ipairs(list) do
        if type(t) == "table" then
            local c, rc = t[3] or WHITE_LINE, t[4] or WHITE_LINE
            tip:AddDoubleLine(t[1], t[2], c[1], c[2], c[3], rc[1], rc[2], rc[3])
        else
            tip:AddLine(t)
        end
        own[i] = {}
    end
    local data = { type = kind or Enum.TooltipDataType.Spell, id = id, lines = dataLines or own }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    tip:Show()
end

local FROSTBOLT = {
    { "Frostbolt", "Rank 4", WHITE_LINE, RANK_GRAY },
    { "120 Mana", "30 yd range" },
    "2.5 sec cast",
    { "Launches a bolt of frost at the enemy, causing 412 to 448 Frost damage and slowing movement speed by 40% for 9 sec.",
      nil, YELLOW },
}

T.test("rich tooltip: a spell's card, as the board lays it out", function()
    local Tip, Panel = login("rich")
    spells()
    fillSpell(116, FROSTBOLT)
    local p = Panel.Get(GameTooltip)
    local Style, INK = DaylightUI.Style, DaylightUI.Style.INK
    T.eq(p.kind, "spell")
    T.near(GameTooltip:GetWidth(), 270 * p:GetScale(), 0.01, "the board's 270, fitted")
    local frost = Tip.SCHOOL_COLORS.Frost
    T.rgb(p.lightPair[1], frost, "the top light in the school's color")
    local head = p.items[1]
    T.eq(stub.Text(head.title), "Frostbolt")
    T.eq(head.icon:GetWidth(), 36, "a 36 px icon")
    T.eq(head.icon.art:GetTexture(), 135846)
    T.eq(stub.Text(head.tags[1].text), "FROST")
    T.rgb({ head.tags[1].text:GetTextColor() }, frost, "the school tag in its color")
    T.eq(stub.Text(head.tags[2].text), "RANK 4")
    T.rgb({ head.tags[2].text:GetTextColor() }, { DaylightUI.Style.Pop() }, "the rank pops")
    local tiles = kinds(p, "tiles")[1].list
    T.eq(#tiles, 3)
    T.eq(stub.Text(tiles[1].value), "2.5 sec")
    T.eq(stub.Text(tiles[1].caption), "CAST")
    T.eq(stub.Text(tiles[2].value), "120 Mana")
    T.rgb({ tiles[2].value:GetTextColor() }, { Style.PowerColor("MANA") }, "the cost in its power color")
    T.eq(stub.Text(tiles[3].value), "30 yd")
    T.eq(stub.Text(tiles[3].caption), "RANGE")
    local H = DaylightUI.Win.Parts.Hex
    local desc = stub.Text(kinds(p, "text")[1].fs)
    T.truthy(desc:find(H(INK.DAMAGE) .. "412|r to " .. H(INK.DAMAGE) .. "448|r", 1, true), "damage soft red: " .. desc)
    T.truthy(desc:find(H(frost) .. "40|r%", 1, true), "the slow in the school's color")
    T.truthy(desc:find(H(frost) .. "9|r sec", 1, true), "its duration too")
    T.eq(#kinds(p, "hints"), 0, "no hint line under the card")
    T.eq(GameTooltipTextLeft4:GetAlpha(), 0, "the game's lines muted under the card")
    T.eq(GameTooltipTextLeft4:GetText(), FROSTBOLT[4][1], "and not repainted: the card reads the game's colors")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a spell's cooldown takes the range's tile", function()
    local _, Panel = login("rich")
    spells()
    fillSpell(172, {
        "Corruption",
        { "35 Mana", "30 yd range" },
        { "Instant", "8 sec cooldown" },
        { "Corrupts the target, causing 40 Shadow damage over 12 sec.", nil, YELLOW },
    })
    local p = Panel.Get(GameTooltip)
    local tiles = kinds(p, "tiles")[1].list
    T.eq(stub.Text(tiles[1].value), "Instant")
    T.eq(stub.Text(tiles[3].value), "8 sec")
    T.eq(stub.Text(tiles[3].caption), "COOLDOWN")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: Shift changes nothing on a spell's card", function()
    local _, Panel = login("rich")
    spells()
    fillSpell(116, FROSTBOLT)
    local p = Panel.Get(GameTooltip)
    stub.shift = true
    update()
    T.eq(p.items[1].kind, "header", "the card, as it was")
    T.eq(stub.Text(p.items[1].title), "Frostbolt")
    stub.shift = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The action button the tooltip is on: its slot, as the game's buttons keep it.
local function actionButton(slot)
    local b = CreateFrame("Button", nil, UIParent)
    b.action = slot
    return b
end

T.test("rich tooltip: a spell cooling down on an action button shows when it's ready, the client draining the bar", function()
    local _, Panel = login("rich")
    spells()
    stub.ActionSlots({ [5] = { spellID = 116, cooldown = true, cdStart = GetTime() - 5.8, cdDuration = 10 } })
    fillSpell(116, FROSTBOLT, nil, actionButton(5))
    local p = Panel.Get(GameTooltip)
    local INK = DaylightUI.Style.INK
    T.eq(p.kind, "cooldown")
    T.eq(p.wantW, 200, "the board's 200")
    local lo, hi = DaylightUI.Gradients.PairFrom(INK.WARN)
    T.rgb(p.lightPair[1], hi, "a warn top light")
    T.eq(stub.Text(p.items[1].fs), "Frostbolt")
    local ready = kinds(p, "row")[1]
    T.eq(stub.Text(ready.label), "Ready in")
    T.eq(stub.Text(ready.value), "4.2 sec")
    T.rgb({ ready.value:GetTextColor() }, INK.WARN)
    local bar = kinds(p, "bar")[1]
    T.eq(bar.h, 4)
    local timer = bar.bar.__timer
    T.truthy(timer and timer[1].slot == 5 and timer[1].kind == "cooldown", "the action's own cooldown duration")
    T.eq(timer[3], Enum.StatusBarTimerDirection.RemainingTime, "drains as it comes back")
    T.isnil(bar.bar:GetScript("OnUpdate"), "the client drains it: no Lua each frame")
    T.isnil(p:GetScript("OnUpdate"))
    stub.Advance(1)
    update()
    T.eq(stub.Text(kinds(p, "row")[1].value), "3.2 sec", "counts down from the tooltip's own update")
    stub.Advance(4)
    update()
    T.eq(p.kind, "spell", "ready: the card again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a recharging spell shows its charges; the global cooldown alone shows the card", function()
    local _, Panel = login("rich")
    spells()
    stub.ActionSlots({
        [5] = { spellID = 116, charges = true, chargesNow = 1, chargesMax = 2, chargeStart = GetTime() - 2, chargeDuration = 8 },
        [6] = { spellID = 116, cooldown = true, gcd = true, cdStart = GetTime(), cdDuration = 1.5 },
    })
    fillSpell(116, FROSTBOLT, nil, actionButton(5))
    local p = Panel.Get(GameTooltip)
    local INK = DaylightUI.Style.INK
    T.eq(p.kind, "cooldown")
    local rows = kinds(p, "row")
    T.eq(stub.Text(rows[1].value), "6.0 sec", "the next charge")
    T.eq(stub.Text(rows[2].label), "Charges")
    T.eq(stub.Text(rows[2].value), "1 " .. DaylightUI.Win.Parts.Hex(INK.LABEL) .. "/ 2|r")
    T.eq(kinds(p, "bar")[1].bar.__timer[1].kind, "charges", "the charge's own duration")
    fillSpell(116, FROSTBOLT, nil, actionButton(6))
    update()
    T.eq(p.kind, "spell", "the global cooldown: no cooldown card")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: in a fight a spell is the frame around the game's lines, painted as before", function()
    local _, Panel = login("rich")
    spells()
    stub.shift = true
    local desc = stub.Secret("Causes 12 damage every 3 sec.")
    fillSpell(172, {
        { stub.Secret("Corruption"), nil },
        { stub.Secret("Instant"), nil },
        { desc, nil, YELLOW },
    })
    local p = Panel.Get(GameTooltip)
    T.truthy(p.chrome, "the frame only")
    T.eq(p.count, 0, "no pieces")
    T.eq(GameTooltipTextLeft3:GetAlpha(), 1, "the game's lines show")
    T.rgb(GameTooltipTextLeft3.__textColor, DaylightUI.Style.INK.TEXT, "the description painted as the skinned look does")
    T.eq(GameTooltipTextLeft3:GetText(), desc, "its text left as the game gave it")
    update()
    T.truthy(p.chrome, "Shift held changes nothing")
    stub.shift = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the Spell ID line and other addons' lines go under a rule", function()
    local _, Panel = login("rich")
    spells()
    DaylightUI:Set("Tooltip", "showIDs", true)
    stub.RunTimers()
    fillSpell(116, FROSTBOLT)
    update()
    local p = Panel.Get(GameTooltip)
    local rows = kinds(p, "row")
    T.eq(stub.Text(rows[#rows].label), "Spell ID")
    T.eq(stub.Text(rows[#rows].value), "116")
    T.eq(#kinds(p, "rule"), 1)
    GameTooltip:AddLine("Rank 3 known by your alt")
    update()
    T.truthy(stub.Text(kinds(p, "text")[2].fs):find("known by your alt", 1, true), "another addon's line, after it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: an aura and a macro's spell get the card; an item macro the plain one", function()
    local _, Panel = login("rich")
    spells()
    fillSpell(10157, {
        "Arcane Intellect",
        "Increases Intellect by 31 for all party members.",
        "29 min remaining",
    }, Enum.TooltipDataType.UnitAura)
    local p = Panel.Get(GameTooltip)
    T.eq(p.kind, "spell")
    T.truthy(stub.Text(kinds(p, "text")[1].fs):find("Increases Intellect by", 1, true), "the aura's sentence")
    T.eq(stub.Text(kinds(p, "text")[2].fs), "29 min remaining", "the time left small")
    T.eq(#kinds(p, "tiles"), 0, "no strip")
    T.eq(#kinds(p, "hints"), 0, "no hint for an aura")
    -- A macro casting Frostbolt: its lines carry the spell's line types.
    stub.ActionSlots({ [7] = { macro = 3, texture = 135846 } })
    fillSpell(3, FROSTBOLT, Enum.TooltipDataType.Macro, actionButton(7), { { type = 13 }, {}, {}, { type = 34 } })
    update()
    T.eq(p.kind, "spell")
    T.eq(p.items[1].icon.art:GetTexture(), 135846, "the icon from its action slot")
    T.eq(#kinds(p, "hints"), 0, "no hint for a macro")
    fillSpell(4, { "Hearthstone", { "Use: Returns you to your home.", nil, { 0, 1, 0 } } }, Enum.TooltipDataType.Macro, nil,
        { {}, {} })
    update()
    T.eq(#kinds(p, "tiles"), 0)
    T.eq(stub.Text(p.items[1].title), "Hearthstone", "an item macro: the plain card")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game (a frame by frame recording): the character window's stat
-- tooltips are only the game's own lines, no data. The game clears the
-- tooltip, hides it and shows it again with new lines: the card has to come.
T.test("rich tooltip: a tooltip with no data, cleared and hidden before it shows, still gets its card", function()
    local Tip, Panel = login("rich")
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:AddLine("Agility 75")
    tip:Show()
    update()
    -- The next stat: cleared first, then hidden, then shown with its lines.
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:Hide()
    tip:AddLine("Strength 133")
    tip:Show()
    tip:AddLine("Increases attack power by 266.")
    tip:Show()
    update()
    local p = Panel.Get(tip)
    T.truthy(p:IsShown(), "the card")
    T.eq(stub.Text(p.items[1].title), "Strength 133")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 0, "the game's lines out of sight")
    T.falsy(Tip.Shell(tip):IsShown(), "and the skinned look")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in the same recording: hovering one bag item after another, the main
-- tooltip and its compare hide together and show together a moment later.
-- The compare fades in with the main one, not at full while it fades.
T.test("rich tooltip: a compare tooltip fades in with its main tooltip", function()
    login("rich")
    items()
    local shop = ShoppingTooltip1
    fillItem(GameTooltip, "greaves", GREAVES)
    compare(shop, CHANGES)
    local M = DaylightUI.Motion
    local d = M.Driver()
    if d then stub.RunOnUpdate(d, M.NORMAL + 0.05) end
    stub.Advance(0.3)
    GameTooltip:Hide()
    shop:Hide() -- as the game's GameTooltip_OnHide (TooltipComparisonManager:Clear)
    stub.Advance(0.05)
    compare(shop, CHANGES)
    fillItem(GameTooltip, "greaves", GREAVES)
    T.eq(GameTooltip:GetAlpha(), 0, "the main tooltip fades in")
    T.eq(shop:GetAlpha(), 0, "and its compare with it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game in a fight: the game filled the tooltip with the thing behind
-- a creature (an object, its lines secret) and then the creature, a frame
-- apart, and the pill and the whole card took turns. In a fight anything in
-- the world is the pill.
T.test("rich tooltip: in a fight a world object is the pill too, so it never swaps with the card", function()
    local Tip, Panel = login("rich")
    stub.units.mouseover = { name = "Southsea Swashbuckler", isPlayer = false, reaction = 2, health = 87, maxHealth = 100 }
    stub.EnterCombat()
    local function world(kind, set)
        local tip = GameTooltip
        GameTooltip_SetDefaultAnchor(tip, UIParent)
        tip.__unit = kind == Enum.TooltipDataType.Unit and "mouseover" or nil
        set(tip)
        local data = { type = kind }
        for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
        for _, fn in ipairs(post[kind] or {}) do fn(tip, data) end
        tip:Show()
        update()
    end
    world(Enum.TooltipDataType.Unit, function(t) t:AddLine("Southsea Swashbuckler") end)
    local pill = _G.DaylightUITooltipPill
    T.truthy(pill:IsShown())
    -- The object behind it, its lines secret in a fight.
    world(4, function(t)
        t:AddLine("Ox Bones")
        t:AddLine("Quest item")
        GameTooltipTextLeft1:SetText(stub.Secret("Ox Bones"))
        GameTooltipTextLeft2:SetText(stub.Secret("Quest item"))
    end)
    T.truthy(pill:IsShown(), "still the pill")
    T.eq(stub.Text(pill.name), "Ox Bones", "with the object's name")
    T.falsy(pill.bar:IsShown(), "no health for an object")
    T.eq(GameTooltip:GetAlpha(), 0, "the tooltip itself out of sight")
    local p = Panel.Get(GameTooltip)
    T.truthy(not p or not p:IsShown(), "no card or frame")
    -- Back on the creature.
    world(Enum.TooltipDataType.Unit, function(t) t:AddLine("Southsea Swashbuckler") end)
    T.eq(stub.Text(pill.name), "Southsea Swashbuckler")
    T.truthy(pill.bar:IsShown(), "its health again")
    -- Shift: the full card, for an object too.
    world(4, function(t) t:AddLine("Ox Bones") end)
    stub.shift = true
    update()
    T.falsy(pill:IsShown(), "Shift: no pill")
    T.truthy(Panel.Get(GameTooltip):IsShown(), "the card")
    stub.shift = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game in a dungeon out of combat: under the map restriction the game's
-- GetUnit hands back the unit's token secret (UnitTokenFromGUID is
-- SecretWhenUnitIdentityRestricted) and every line is secret. The tooltip
-- there must look as it does anywhere else: the whole card out of a fight,
-- built from the unit, and the pill in one.
local function hoverRestricted(name, second)
    local tip = GameTooltip
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    tip.__unit = stub.Secret("mouseover")
    tip:AddLine(name)
    tip:AddLine(second)
    GameTooltipTextLeft1:SetText(stub.Secret(name))
    GameTooltipTextLeft2:SetText(stub.Secret(second))
    local data = { type = Enum.TooltipDataType.Unit }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[Enum.TooltipDataType.Unit] or {}) do fn(tip, data) end
    tip:Show()
    update()
    return tip
end

T.test("rich tooltip: a mob in a restricted dungeon gets its whole card out of a fight", function()
    local _, Panel = login("rich")
    stub.units.mouseover = { name = "Krol'dok Brute", isPlayer = false, reaction = 2, level = 41,
        classification = "elite", health = 87, maxHealth = 100 }
    stub.SetRestriction("Map", true)
    local tip = hoverRestricted("Krol'dok Brute", "Level 41 (Elite)")
    local pill = _G.DaylightUITooltipPill
    T.truthy(not pill or not pill:IsShown(), "no pill out of a fight")
    local p = Panel.Get(tip)
    T.truthy(p and p:IsShown(), "the card")
    T.falsy(p.chrome, "the whole card, not the frame only")
    T.eq(p.kind, "mob")
    T.eq(stub.Text(p.items[1].title), "Krol'dok Brute", "its name from the unit")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 0, "the game's hidden lines out of sight")
    -- In a fight: the pill, as anywhere.
    stub.EnterCombat()
    hoverRestricted("Krol'dok Brute", "Level 41 (Elite)")
    pill = _G.DaylightUITooltipPill
    T.truthy(pill and pill:IsShown(), "the pill in a fight")
    T.eq(stub.Text(pill.name), "Krol'dok Brute", "with the mob's name")
    T.truthy(pill.bar:IsShown(), "and its health")
    stub.LeaveCombat()
    stub.SetRestriction("Map", false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a player in a restricted dungeon gets their whole card out of a fight", function()
    local _, Panel = login("rich")
    stub.units.mouseover = { name = "Saki", class = "MAGE", isPlayer = true, level = 44, health = 50, maxHealth = 100 }
    stub.SetRestriction("Map", true)
    local tip = hoverRestricted("Saki", "Level 44 Human (Player)")
    local pill = _G.DaylightUITooltipPill
    T.truthy(not pill or not pill:IsShown(), "no pill out of a fight")
    local p = Panel.Get(tip)
    T.truthy(p and p:IsShown() and not p.chrome, "the whole card")
    T.eq(p.kind, "unit")
    T.truthy(stub.Text(p.items[1].title):find("Saki", 1, true), "their name")
    stub.SetRestriction("Map", false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The tooltip's own Show is hooked once Rich is in use: a refill of a tooltip
-- already showing builds its card at the Show, not a frame later.
T.test("rich tooltip: a refill's Show builds the card at once, before any update", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    local p = Panel.Get(GameTooltip)
    fillItem(GameTooltip, "legplates", LEGPLATES) -- shown already: no OnShow
    T.eq(stub.Text(p.items[1].title), "Tarnished Legplates", "built at the Show")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a muted tooltip goes back to alpha 0 whatever sets it", function()
    local Tip = login("rich")
    stub.units.mouseover = { name = "Southsea Swashbuckler", isPlayer = false, reaction = 2, health = 87, maxHealth = 100 }
    stub.EnterCombat()
    hover("mouseover", { "Southsea Swashbuckler" })
    T.eq(Tip.Muted(GameTooltip), "pill")
    GameTooltip:SetAlpha(0.6) -- the game's own fade
    T.eq(GameTooltip:GetAlpha(), 0, "back to 0 at once")
    GameTooltip:Show()
    T.eq(GameTooltip:GetAlpha(), 0, "and after a Show")
    -- Not muted: left alone.
    stub.LeaveCombat()
    update()
    GameTooltip:SetAlpha(0.6)
    T.eq(GameTooltip:GetAlpha(), 0.6)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the Simple look never gets the method hooks", function()
    login()
    local raw = rawget(GameTooltip, "Show")
    hover("mouseover", { "Jaina" })
    T.eq(rawget(GameTooltip, "Show"), raw, "no hook on Show")
    T.isnil(rawget(GameTooltip, "SetAlpha"), "nor on SetAlpha")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: "RAGING DAYLIGHT" (the player's own name) under each quest on
-- a creature's card. The game names whose progress it is, for a group.
T.test("rich tooltip: your own name under a quest is left out, a party member's stays", function()
    local _, Panel = login("rich")
    stub.units.player.name = "Daylight"
    stub.units.mouseover = { name = "Southsea Pirate", isPlayer = false, reaction = 2, level = 44, health = 50, maxHealth = 100 }
    local data = { type = Enum.TooltipDataType.Unit, lines = { {}, { type = 17 }, { type = 18 }, { type = 8 }, { type = 18 }, { type = 8 } } }
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Southsea Pirate")
    tip:AddLine("Pirate Hats Ahoy!", 1, 0.82, 0)
    tip:AddLine("Daylight", 1, 0.82, 0)
    tip:AddLine(" - 15/20 Southsea Pirate Hat")
    tip:AddLine("Thrall", 1, 0.82, 0)
    tip:AddLine(" - 3/20 Southsea Pirate Hat")
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    tip:Show()
    local p = Panel.Get(tip)
    local said = {}
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "section" or it.kind == "text" then said[#said + 1] = stub.Text(it.fs) end
    end
    T.eq(said[1], "PIRATE HATS AHOY!", "the quest")
    T.eq(said[2], "Thrall", "a party member's name, small")
    for _, t in ipairs(said) do T.falsy(t:upper():find("DAYLIGHT", 1, true), "never your own") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a quest reward's card showed coins at the foot with no word
-- beside them (it has no durability to sit on the left).
T.test("rich tooltip: a sell price with no durability beside it says what it is", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Southsea Head Bucket", nil, { 0.118, 1, 0 } }, "Binds when picked up",
        "Sell Price: 48|A:coin-silver:0:0|a 12|A:coin-copper:0:0|a" })
    local rows = kinds(Panel.Get(GameTooltip), "row")
    local foot = rows[#rows]
    T.eq(stub.Text(foot.label), "Sell Price")
    T.truthy(stub.Text(foot.value):find("48", 1, true))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a player with no guild and no target had the banner sitting
-- right on top of HEALTH. The bars keep the same room under the banner as
-- when rows sit between them.
T.test("rich tooltip: a player card with no rows keeps the banner's room above the health", function()
    local _, Panel = login("rich")
    player()
    stub.units.mouseover.guild, stub.units.mouseover.guildRank = nil, nil
    stub.units.mouseovertarget = nil
    hover("mouseover", { "Aelindra" })
    local p = Panel.Get(GameTooltip)
    local room, header, bar = 0, nil, nil
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "header" then header = i end
        if it.kind == "bar" and not bar then bar = i end
        if header and not bar and it.kind == "gap" then room = room + it.h end
    end
    T.truthy(header and bar, "a banner and a health bar")
    local P = stub.tooltip.RichPlayers
    T.eq(room, P.AFTER_BANNER + P.BEFORE_BARS, "the same room as around the rows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The world: the board's mob, node and other things.
local function itemsOf(p, kind)
    local out = {}
    for i = 1, p.count do if p.items[i].kind == kind then out[#out + 1] = p.items[i] end end
    return out
end

local function rowsOf(p)
    local out = {}
    for _, it in ipairs(itemsOf(p, "row")) do out[stub.Text(it.label)] = it end
    return out
end

local function boar(extra)
    stub.units.player.level = 22
    stub.units.mouseover = { name = "Ridgeback Boar", isPlayer = false, reaction = 2, level = 23, health = 78, pct = 78,
        maxHealth = 100, creatureType = "Beast", creatureTypeID = 1 }
    stub.units.mouseovertarget = stub.units.player
    for k, v in pairs(extra or {}) do stub.units.mouseover[k] = v end
end

-- The game's lines for the boar (its own come first), then another addon's.
local function hoverBoar(addon)
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Ridgeback Boar")
    tip:AddLine("Level 23 Beast")
    tip:AddLine("Skinnable", 1, 0.82, 0)
    tip:AddLine("Boar Hides for Farmer Rowan")
    tip:AddLine(" - 6/10 Ridgeback hide")
    tip:AddLine(" - 8/8 Boars slain")
    local data = { type = Enum.TooltipDataType.Unit,
        lines = { {}, {}, {}, { type = 17, id = 77 }, { type = 8 }, { type = 8 } } }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    for _, t in ipairs(addon or {}) do tip:AddLine(t) end
    tip:Show()
    update()
    return tip
end

local function tagWords(head)
    local out = {}
    for i, t in ipairs(head.tags or {}) do out[i] = stub.Text(t.text) end
    return table.concat(out, ",")
end

T.test("rich tooltip: a mob's card, as the board lays it out", function()
    local _, Panel = login("rich")
    DaylightUI.Npc.Data.QuestColor = function() return { 0.5, 0.88, 0.97 } end
    boar()
    local p = Panel.Get(hoverBoar())
    T.eq(p.wantW, 260, "the board's width")
    local head = p.items[1]
    T.eq(head.kind, "header")
    T.eq(stub.Text(head.title), "Ridgeback Boar")
    T.eq(head.title.size, DaylightUI.Style.SIZE.title)
    T.eq(head.icon.art.__portraitUnit, "mouseover", "its face as the icon")
    T.truthy(head.icon.art.__portraitSquare, "square: the card cuts the corner")
    T.eq(stub.Text(head.right), "23", "the level on the right")
    T.rgb({ head.right:GetTextColor() }, DaylightUI.Style.INK.WARN, "yellow for you: WARN")
    T.eq(tagWords(head), "HOSTILE,BEAST,SKINNABLE")
    T.rgb({ head.tags[1].text:GetTextColor() }, { DaylightUI.Style.ReactionColor(2) }, "hostile in its color")
    T.rgb({ head.tags[2].text:GetTextColor() }, stub.tooltip.RichWorld.KIND_COLORS[1], "a beast in its color")
    T.rgb({ head.tags[3].text:GetTextColor() }, DaylightUI.Style.INK.WARN, "skinnable in the game's skill-up color")
    local bars = itemsOf(p, "bar")
    T.eq(bars[1].h, 7, "health first, 7 px")
    T.eq(bars[1].spec.unit, "mouseover")
    T.truthy(bars[1].spec.pair, "in the reaction pair")
    local sections = itemsOf(p, "section")
    T.eq(#sections, 1)
    T.eq(stub.Text(sections[1].fs), "BOAR HIDES FOR FARMER ROWAN")
    local rows = rowsOf(p)
    T.eq(stub.Text(rows["Ridgeback hide"].value), "6 / 10")
    T.eq(stub.Text(rows["Boars slain"].value), "Complete")
    T.eq(stub.Text(rows.Targeting.value), "You")
    T.rgb({ rows.Targeting.value:GetTextColor() }, DaylightUI.Style.INK.WARN)
    T.eq(#itemsOf(p, "rule"), 2, "a rule before the quest and before Targeting")
    T.eq(p.items[p.count].kind, "row", "Targeting last")
    for _, it in ipairs(itemsOf(p, "text")) do
        T.falsy(stub.Text(it.fs):find("Level 23"), "the level line lives in the header")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a mob's rare and elite tags, a skull level, a friendly NPC's title", function()
    local _, Panel = login("rich")
    boar({ classification = "rareelite", level = -1 })
    local p = Panel.Get(hoverBoar())
    local head = p.items[1]
    T.eq(tagWords(head), "HOSTILE,BEAST,SKINNABLE,RARE,ELITE")
    T.eq(stub.Text(head.right), "??")
    T.rgb({ head.right:GetTextColor() }, DaylightUI.Style.INK.BAD)
    -- An innkeeper: its title under its name, no quest, no skinning.
    stub.units.mouseover = { name = "Innkeeper Farley", isPlayer = false, reaction = 5, level = 30, health = 100,
        maxHealth = 100, creatureType = "Humanoid" }
    stub.units.mouseovertarget = nil
    hover("mouseover", { "Innkeeper Farley", "Innkeeper", "Level 30 Humanoid", "Stormwind" })
    head = p.items[1]
    T.eq(stub.Text(head.sub), "Innkeeper")
    T.eq(tagWords(head), "FRIENDLY,HUMANOID")
    local texts = itemsOf(p, "text")
    T.eq(stub.Text(texts[#texts].fs), "Stormwind", "the game's other lines small, under a rule")
    T.eq(texts[#texts].fs.size, DaylightUI.Style.SIZE.small)
    T.isnil(rowsOf(p).Targeting, "targeting no one: no row")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: another addon's rows for a quest the game's lines show are left out, others stay", function()
    local _, Panel = login("rich")
    boar()
    local p = Panel.Get(hoverBoar({
        "[23] Boar Hides for Farmer Rowan", "   |cffffffffRidgeback hide: 6/10|r",
        "Tusks of the Ridge", "   |cffffffffBoar tusk: 2/6|r |cff999999[22%]|r",
        "Raider score 2140",
    }))
    local sections = itemsOf(p, "section")
    T.eq(#sections, 2, "the game's quest once, the other quest")
    T.eq(stub.Text(sections[2].fs), "TUSKS OF THE RIDGE")
    local hides, tusks = 0, 0
    for _, it in ipairs(itemsOf(p, "row")) do
        if stub.Text(it.label):find("Ridgeback hide", 1, true) then hides = hides + 1 end
        if stub.Text(it.label):find("Boar tusk", 1, true) then tusks = tusks + 1 end
    end
    T.eq(hides, 1, "the hide count once")
    T.eq(tusks, 1, "the other quest's row")
    local texts = itemsOf(p, "text")
    T.truthy(stub.Text(texts[#texts].fs):find("^Raider score"), "another addon's line at the bottom")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a mob's type stays out when the client hides who it is", function()
    local _, Panel = login("rich")
    DaylightUI:Set("Tooltip", "pill", "never")
    stub.RunTimers()
    boar()
    stub.SetRestriction("Map", true)
    local p = Panel.Get(hoverBoar())
    stub.SetRestriction("Map", false)
    T.truthy(p:IsShown())
    T.falsy(tagWords(p.items[1]):find("BEAST"), "no type: " .. tagWords(p.items[1]))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A node, a lock, a mailbox: things in the world that aren't units.
local function hoverThing(lines)
    local tip = GameTooltip
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    tip.__unit = nil
    for _, t in ipairs(lines) do
        if type(t) == "table" then tip:AddLine(unpack(t)) else tip:AddLine(t) end
    end
    local own = {}
    for i = 1, tip:NumLines() do own[i] = {} end
    local data = { type = 4, lines = own }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    tip:Show()
    update()
    return tip
end

T.test("rich tooltip: a node's card shows your skill in its skill-up color over a thin bar", function()
    local _, Panel = login("rich")
    stub.SetSkills({ { name = "Professions", isHeader = true }, { name = "Herbalism", rank = 125, maxRank = 150 },
        { name = "Mining", rank = 50, maxRank = 75 } })
    local p = Panel.Get(hoverThing({ "Kingsblood", { "Herbalism", 0.25, 0.75, 0.25 } }))
    T.eq(p.wantW, 210, "the board's width")
    T.eq(p.items[1].title.size, DaylightUI.Style.SIZE.head, "title 15")
    T.isnil(p.items[1].icon, "no icon")
    local row = rowsOf(p).Herbalism
    T.truthy(row, "your skill")
    T.truthy(stub.Text(row.value):find("^125 ") and stub.Text(row.value):find("/ 150"), stub.Text(row.value))
    T.rgb({ row.value:GetTextColor() }, DaylightUI.Style.INK.GOOD, "green: it still teaches you")
    local bar = itemsOf(p, "bar")[1]
    T.eq(bar.h, 4)
    T.eq(bar.spec.value, 125)
    T.eq(bar.spec.max, 150)
    T.eq(#itemsOf(p, "text"), 0, "no made-up contents line")
    T.truthy(p.lightPair[1][2] > p.lightPair[1][1], "a green top light")
    -- A vein you can't mine yet: what it asks for, in red.
    hoverThing({ "Iron Deposit", { "Requires Mining (75)", 1, 0.1, 0.1 } })
    row = rowsOf(p).Mining
    T.truthy(row, "your mining")
    T.truthy(stub.Text(row.value):find("^50 ") and stub.Text(row.value):find("/ 75"), stub.Text(row.value))
    T.rgb({ row.value:GetTextColor() }, DaylightUI.Style.INK.BAD)
    T.eq(itemsOf(p, "bar")[1].spec.max, 75)
    -- A skinnable corpse: your Skinning, found by its skill line.
    stub.SetSkills({ { name = "Skinning", skillID = 393, rank = 80, maxRank = 150 } })
    hoverThing({ "Ridgeback Boar", { "Skinnable", 1, 0.82, 0 } })
    row = rowsOf(p).Skinning
    T.truthy(row and stub.Text(row.value):find("^80 "), "your skinning")
    T.rgb({ row.value:GetTextColor() }, DaylightUI.Style.INK.WARN)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a mailbox is its name and the game's lines, as wide as it needs", function()
    local _, Panel = login("rich")
    stub.SetSkills({})
    local p = Panel.Get(hoverThing({ "Mailbox", { "Unread mail", 1, 0.82, 0 } }))
    T.eq(p.kind, "other")
    T.truthy(p.wantW < 210, "a small card: " .. tostring(p.wantW))
    T.eq(p.items[1].title.size, DaylightUI.Style.SIZE.head)
    T.eq(stub.Text(p.items[1].title), "Mailbox")
    T.eq(#itemsOf(p, "bar"), 0)
    T.eq(stub.Text(itemsOf(p, "text")[1].fs), "Unread mail")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: an Equip sentence sat right under the stat lines.
T.test("rich tooltip: an item's effects sit a little apart from its stats", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Ring of Thorns", nil, { 0, 0.44, 0.87 } }, "+8 Stamina",
        { "Equip: When struck in melee combat, has a 10% chance of stealing 39 life from the target enemy.", nil, { 0.1, 1, 0.1 } } })
    local p = Panel.Get(GameTooltip)
    local stat
    for i = 1, p.count do if p.items[i].kind == "line" then stat = i end end
    T.eq(p.items[stat + 1].kind, "rule", "a rule after the stats")
    T.eq(p.items[stat + 2].kind, "text", "then the effect")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Binding and Unique are tags under the name. Long ones go on a second row
-- rather than past the card's edge.
T.test("rich tooltip: an item's binding and Unique tags wrap onto a second row", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when picked up", "Unique",
        { "Legs", "Plate" }, "742 Armor" })
    local head = Panel.Get(GameTooltip).items[1]
    T.eq(#head.tags, 5)
    T.eq(stub.Text(head.tags[4].text), "BINDS WHEN PICKED UP")
    T.eq(stub.Text(head.tags[5].text), "UNIQUE")
    T.eq(head.tags[1].row, 1)
    T.truthy(head.tags[5].row > 1, "the last ones on another row")
    local room = 290 - 2 * 16 - 44 - 12
    for _, tag in ipairs(head.tags) do T.truthy(tag.at + tag:GetWidth() <= room + 0.5, "never past the edge") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: an Equip sentence's wrapped lines ran into each other.
T.test("rich tooltip: a wrapped sentence on the card has room between its lines", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Maw of Min'loth", nil, { 0, 0.44, 0.87 } }, "+8 Stamina",
        { "Equip: When struck in melee combat, has a 10% chance of stealing 39 life from the target enemy.", nil, { 0.1, 1, 0.1 } } })
    local text = kinds(Panel.Get(GameTooltip), "text")[1]
    T.eq(text.fs:GetSpacing(), stub.tooltip.RichPanel.LINE_SPACING)
    local line = kinds(Panel.Get(GameTooltip), "line")[1]
    T.eq(line.fs:GetSpacing(), 0, "a one-line number keeps none")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the health bar flashed black as the mouse left a unit. The
-- card and pill kept repainting from "mouseover", which then answers no
-- health, so the bar emptied to its black track while it faded out.
T.test("rich tooltip: a card's and the pill's health keep their last value once the unit is gone", function()
    local _, Panel = login("rich")
    boar()
    local p = Panel.Get(hoverBoar())
    local bar = itemsOf(p, "bar")[1].bar
    T.eq(stub.Plain(bar:GetValue()), 78)
    stub.units.mouseover = nil
    stub.Advance(0.5)
    update()
    T.eq(stub.Plain(bar:GetValue()), 78, "the card's bar as it was")
    -- The pill, in a fight.
    boar()
    stub.EnterCombat()
    hoverBoar()
    local pill = _G.DaylightUITooltipPill
    T.truthy(pill:IsShown())
    T.eq(stub.Plain(pill.bar:GetValue()), 78)
    T.eq(stub.Text(pill.pct), "78%", "its health before")
    stub.units.mouseover = nil
    stub.Advance(0.5)
    update()
    T.eq(stub.Plain(pill.bar:GetValue()), 78, "the pill's bar as it was")
    T.eq(stub.Text(pill.pct), "78%", "and its health")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game, on many cards (the game menu's latency, a map pin's quest
-- list): a row's value cut with "..." ("2...", "(Dung..."). It sat squeezed
-- between its label and the card's edge, and a card exactly as wide as its
-- widest row had no room left after rounding. The value takes its own width
-- at the edge; only a label too long for what's left is shortened.
T.test("rich tooltip: a row's value is never squeezed: it keeps its own width at the edge", function()
    local _, Panel = login("rich")
    fill(99, { "Performance", { "Framerate", "119 fps" }, { "Latency (home)", "24 ms" },
        { string.rep("A very long label ", 6), "(Dungeon)" } })
    local p = Panel.Get(GameTooltip)
    local rows = kinds(p, "row")
    for _, r in ipairs(rows) do
        T.eq(#r.value.__points, 1, "the value anchored once")
        T.eq(r.value.__points[1][1], "TOPRIGHT", "at the card's right edge")
        T.eq(r.value:GetWidth(), 0, "as wide as its own text")
    end
    T.eq(rows[1].label:GetWidth(), 0, "a label that fits keeps its own width")
    local long = rows[3]
    local inner = p.wantW - 2 * stub.tooltip.RichPanel.PAD_X
    T.truthy(long.label:GetWidth() > 0 and long.label:GetWidth() <= inner - long.value:GetStringWidth() - 16,
        "a label too long is shortened, before the value")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a crawfish showed HUMANOID as a tag and "Humanoid" again as a
-- small line, its type on a line of its own under "Level 40".
T.test("rich tooltip: a creature's lines that repeat what the header shows are left out", function()
    local _, Panel = login("rich")
    stub.units.player.level = 40
    stub.units.mouseover = { name = "Jumbo Crawfish", isPlayer = false, reaction = 4, level = 40, health = 100,
        maxHealth = 100, creatureType = "Humanoid", classification = "elite" }
    stub.units.mouseovertarget = nil
    hover("mouseover", { "Jumbo Crawfish", "Level 40", "Humanoid", "NEUTRAL", "Elite", "Jumbo Crawfish", "Coastal" })
    local p = Panel.Get(GameTooltip)
    T.eq(tagWords(p.items[1]), "NEUTRAL,HUMANOID,ELITE")
    local said = {}
    for _, it in ipairs(itemsOf(p, "text")) do said[#said + 1] = stub.Text(it.fs) end
    T.eq(table.concat(said, ","), "Coastal", "only what the header doesn't say")
    T.eq(#itemsOf(p, "rule"), 1, "one rule, above it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The card goes to the tooltip's fading ghost as it is, and comes back hidden
-- once the fade ends, or at once when the tooltip shows again.
T.test("rich tooltip: the card fades out with the ghost, then goes home", function()
    local Tip, Panel = login("rich")
    local G = stub.tooltip.TipGhost
    local M = DaylightUI.Motion
    local function tick(dt)
        local d = M.Driver()
        if d then stub.RunOnUpdate(d, dt) end
    end
    local tip = GameTooltip
    local function up()
        tip:Hide()
        stub.Advance(1)
        fill(99, { "Mailbox", "Your mail." })
        function tip:GetRect() return 400, 240, 160, 60 end
        stub.Advance(0.02)
        update()
        tick(M.NORMAL * 2)
    end
    up()
    local p = Panel.Get(tip)
    T.truthy(p:IsShown())
    tip:Hide()
    local g = G.Of(tip)
    T.truthy(g and g:IsShown(), "a ghost")
    T.eq(p:GetParent(), g, "carrying the card")
    T.truthy(p:IsShown(), "still showing while it fades")
    T.falsy(g.box:IsShown(), "no copied box under it")
    tick(M.NORMAL * 2)
    T.falsy(g:IsShown())
    T.eq(p:GetParent(), tip, "the card back with its tooltip")
    T.falsy(p:IsShown(), "hidden, as the tooltip is")
    up()
    tip:Hide()
    tick(M.NORMAL / 2)
    stub.Advance(0.1)
    fill(99, { "Mailbox", "Your mail." })
    T.eq(p:GetParent(), tip, "shown again: the card comes home first")
    T.truthy(p:IsShown(), "and is built again")
    T.eq(GameTooltipTextLeft1:GetAlpha(), 0, "the game's lines stay muted under it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the mail icon's tooltip is one line, the game putting each
-- sender after a line break (FormatUnreadMailTooltip), and the card's title
-- showed "Unread mail from:..." with the senders cut off.
T.test("rich tooltip: a first line holding several lines is the title and lines under it", function()
    local _, Panel = login("rich")
    fill(99, { { "Unread mail from:\nThrall\nJaina", nil, 1, 0.82, 0 } })
    local p = Panel.Get(GameTooltip)
    T.eq(stub.Text(p.items[1].title), "Unread mail from:", "the title is the first line alone")
    T.eq(p.items[2] and stub.Text(p.items[2].fs), "Thrall", "each sender under it")
    T.eq(p.items[3] and stub.Text(p.items[3].fs), "Jaina")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the minimap's mail icon drew its lines twice, the second time
-- as another addon's. Its data comes with an empty lines table and the game
-- writes the text itself, so no line can be told to be the data's own: all
-- of them are the card's, and line 1 is never another addon's.
T.test("rich tooltip: data with no lines of its own puts nothing in the other addons' area", function()
    local _, Panel = login("rich")
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:AddLine("Unread mail from:")
    tip:AddLine("Alliance Auction House")
    local data = { type = 21, lines = {} }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    tip:Show()
    local p = Panel.Get(tip)
    T.eq(stub.Text(p.items[1].title), "Unread mail from:")
    local texts = 0
    for i = 1, p.count do
        local item = p.items[i]
        T.truthy(item.kind ~= "rule", "no other addons' area")
        if item.kind == "text" then texts = texts + 1 end
    end
    T.eq(texts, 1, "the sender once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: the card's cut corner had no border: the outline and band ran
-- along the straight edges and stopped where the corner was cut away.
T.test("rich tooltip: the cut corner carries the border round it", function()
    local _, Panel = login("rich")
    fill(99, { "Unread mail from:", "Thrall" })
    local p = Panel.Get(GameTooltip)
    local Style = DaylightUI.Style
    local s = Style.GetShell(p)
    local e = s.cutEdge
    T.truthy(e and e.outline:IsShown(), "a line along the cut in the outline's color")
    T.truthy(e.band:IsShown(), "and the band's down its middle")
    -- As thick as the shell's own outline, the band a pixel in from each side.
    local T_ = e.outline:GetThickness()
    T.truthy(T_ > 0)
    T.truthy(e.band:GetThickness() > 0 and e.band:GetThickness() < T_, "the band inside the outline, as on the straight edges")
    local point, rel, x, y = e.outline:GetStartPoint()
    T.eq(point, "BOTTOMRIGHT"); T.eq(rel, s)
    local cut = Style.GetCut(p)
    T.near(x, -(cut + T_ / math.sqrt(2) - T_ / 2), 1e-6, "on the cut, half the border in")
    T.near(y, T_ / 2, 1e-6)
    local _, _, ex, ey = e.outline:GetEndPoint()
    T.near(ex, -T_ / 2, 1e-6); T.near(ey, cut + T_ / math.sqrt(2) - T_ / 2, 1e-6)
    local c = ({ e.outline:GetVertexColor() })
    T.near(c[1], Style.BORDER[1], 1e-6, "the outline's color")
    -- The fight pill and a value tile have one too.
    local tile = DaylightUI.Widgets.Tile(UIParent)
    T.truthy(Style.GetShell(tile).cutEdge.outline:IsShown(), "a tile's cut too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- Other addons' lines (Rich/Foreign.lua)
-- ---------------------------------------------------------------------

local foreignPanel

-- A tooltip with the data's own lines, then another addon's added after
-- every post-call (addon(tip)), shown and laid out. Returns its card.
local function withAddon(own, addon, kind)
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    local data = { type = kind or 99, lines = {} }
    for i, t in ipairs(own) do
        if type(t) == "table" then tip:AddDoubleLine(unpack(t)) else tip:AddLine(t) end
        data.lines[i] = {}
    end
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    if addon then addon(tip) end
    tip:Show()
    update()
    return foreignPanel.Get(tip)
end

local function foreignLogin()
    local Tip, Panel = login("rich")
    foreignPanel = Panel
    return Tip, Panel
end

-- The pieces after the card's last rule: the other addons' area.
local function afterRule(p)
    local out, seen = {}, false
    for i = 1, p.count do
        local item = p.items[i]
        if seen then out[#out + 1] = item end
        if item.kind == "rule" then
            seen = true
            out = {}
        end
    end
    return seen and out or {}
end

local function hexOf(c) return DaylightUI.Win.Parts.Hex(c) end

T.test("other addons: their own area under a rule, left soft white, right white", function()
    foreignLogin()
    local p = withAddon({ "Mailbox", "Your mail." }, function(t)
        t:AddDoubleLine("Bags", "5")
        t:AddLine("Some note from an addon")
    end)
    local area = afterRule(p)
    T.eq(#area, 2, "a row and a sentence")
    T.eq(area[1].kind, "row")
    T.eq(stub.Text(area[1].label), "Bags")
    T.eq(stub.Text(area[1].value), "5")
    T.rgb(area[1].label.__textColor, DaylightUI.Style.INK.TEXT, "left soft white")
    T.rgb(area[1].value.__textColor, DaylightUI.Style.INK.VALUE, "right white")
    T.eq(area[2].kind, "text")
    T.eq(GameTooltipTextLeft3:GetAlpha(), 0, "the addon's own line muted under the card")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: an unknown addon's colors, grays and icons", function()
    foreignLogin()
    local Style = DaylightUI.Style
    local p = withAddon({ "Peacebloom" }, function(t)
        t:AddLine("Dropped by |cff999999Hogger|r")
        t:AddLine("Seen on 3 alts", 0.5, 0.5, 0.5)
        t:AddLine("Danger", 1, 0.1, 0.1)
        t:AddLine("Druid only", 1, 0.49, 0.04)
        t:AddLine("|TInterface\\Icons\\INV_Misc_Bag_08:0|t In your bank")
        t:AddLine("|TInterface\\Icons\\Role:16:16:0:0:64:64:0:19:22:41|t Tank")
    end)
    local area = afterRule(p)
    T.eq(#area, 6)
    local first = stub.Text(area[1].fs)
    T.truthy(first:find(hexOf(Style.INK.LABEL), 1, true) and not first:find("999999", 1, true), "the typed-in gray tan: " .. first)
    T.rgb(area[2].fs.__textColor, Style.INK.LABEL, "a gray line tan")
    T.rgb(area[3].fs.__textColor, Style.INK.BAD, "red a warning")
    T.near(area[4].fs.__textColor[3], 0.04, 1e-6, "its own color kept")
    T.truthy(stub.Text(area[5].fs):find(":0:0:0:0:100:100:8:92:8:92|t", 1, true), "the icon cropped: " .. stub.Text(area[5].fs))
    T.truthy(stub.Text(area[6].fs):find(":64:64:0:19:22:41|t", 1, true), "its own coordinates kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: blank lines are one gap, never first or last", function()
    foreignLogin()
    local p = withAddon({ "Peacebloom" }, function(t)
        t:AddLine(" ")
        t:AddLine("First addon")
        t:AddLine(" ")
        t:AddLine("")
        t:AddLine("Second addon")
        t:AddLine(" ")
    end)
    local kinds = {}
    for _, item in ipairs(afterRule(p)) do kinds[#kinds + 1] = item.kind end
    T.deq(kinds, { "text", "gap", "text" })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: prices (Auctionator, TSM, a money frame) as a label and the coins", function()
    foreignLogin()
    local W = DaylightUI.Widgets
    local p = withAddon({ "Copper Ore", "Trade Goods" }, function(t)
        t:AddDoubleLine("Auction x5", "|cffffffff12|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 34|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t|r")
        t:AddDoubleLine("|cff82c5ffDBMarket:|r", "12|cffffd70ag|r 34|cffc7c7cfs|r 56|cffeda55fc|r")
        t:AddLine("Vendor: 1|A:coin-gold:0:0|a 5|A:coin-copper:0:0|a")
        SetTooltipMoney(t, 4321, nil, "Disenchant:")
    end)
    local rows = {}
    for _, item in ipairs(afterRule(p)) do if item.kind == "row" then rows[#rows + 1] = item end end
    T.eq(#rows, 4)
    T.eq(stub.Text(rows[1].label), "Auction x5")
    T.eq(stub.Text(rows[1].value), W.Money(123400), "Auctionator's coins")
    T.eq(stub.Text(rows[2].label), "DBMarket", "the label without its color or colon")
    T.eq(stub.Text(rows[2].value), W.Money(123456), "TSM's lettered coins")
    T.eq(stub.Text(rows[3].label), "Vendor")
    T.eq(stub.Text(rows[3].value), W.Money(10005))
    T.eq(stub.Text(rows[4].label), "Disenchant", "the money frame's words")
    T.eq(stub.Text(rows[4].value), W.Money(4321), "and its amount")
    T.eq(GameTooltipMoneyFrame1:GetAlpha(), 0, "the game's money frame muted under the card")
    -- Filled again without it: no money frame left over.
    withAddon({ "Copper Ore", "Trade Goods" })
    T.eq(#afterRule(p), 0, "nothing of the last fill")
    T.falsy(GameTooltipMoneyFrame1:IsShown(), "the game put its money frame away")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a score popped; Questie's rows as a quest", function()
    foreignLogin()
    local p = withAddon({ "Aelindra" }, function(t)
        t:AddDoubleLine("Raider.IO M+ Score", "|cffff80002140|r")
        t:AddLine("Southsea Shakedown")
        t:AddLine("   |cffffffffSouthsea Pirate: 3/10|r |cff999999[37%]|r")
    end)
    local score
    local kinds = {}
    for i = 1, p.count do
        local item = p.items[i]
        kinds[#kinds + 1] = item.kind
        if item.kind == "row" and stub.Text(item.label) == "Raider.IO M+ Score" then score = item end
    end
    T.truthy(score, "the score's row")
    T.eq(stub.Text(score.value), "2140", "the number alone")
    T.rgb(score.value.__textColor, { DaylightUI.Style.Pop() }, "popped")
    T.truthy(table.concat(kinds, " "):find("section row bar", 1, true), "a heading, the objective, its bar: " .. table.concat(kinds, " "))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a look of their own can be switched off, the plain repaint stays", function()
    foreignLogin()
    DaylightUI:Set("Tooltip", "addonAdapters.prices", false)
    DaylightUI:Set("Tooltip", "addonAdapters.questie", false)
    stub.RunTimers()
    local p = withAddon({ "Copper Ore" }, function(t)
        t:AddDoubleLine("|cff82c5ffDBMarket:|r", "12|cffffd70ag|r")
        t:AddLine("Southsea Shakedown")
        t:AddLine("   |cffffffffSouthsea Pirate: 3/10|r")
    end)
    local area = afterRule(p)
    T.truthy(stub.Text(area[1].label):find("DBMarket:", 1, true), "its own words as they were")
    T.eq(stub.Text(area[1].value), DaylightUI.Widgets.Money(120000), "money is still coins")
    for _, item in ipairs(area) do T.truthy(item.kind ~= "bar" and item.kind ~= "section", "no quest look") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: mixed in, or hidden with Daylight UI plugins' lines still there", function()
    foreignLogin()
    local me = DaylightUI.API.For("Notes")
    me.AddTooltipLines("item", function(lines) lines.Row("Fish caught", 12) end)
    items()
    DaylightUI:Set("Tooltip", "addonLines", "hidden")
    stub.RunTimers()
    fillItem(GameTooltip, "greaves", GREAVES, function(t) t:AddDoubleLine("AH price", "9") end)
    update()
    local p = foreignPanel.Get(GameTooltip)
    local labels = {}
    for i = 1, p.count do
        local item = p.items[i]
        if item.kind == "row" then labels[stub.Text(item.label)] = stub.Text(item.value) end
    end
    T.isnil(labels["AH price"], "another addon's line left out")
    T.eq(labels["Fish caught"], "12", "a plugin's row stays")
    DaylightUI:Set("Tooltip", "addonLines", "mixed")
    stub.RunTimers()
    local p2 = withAddon({ "Mailbox", "Your mail." }, function(t) t:AddLine("A note") end)
    T.eq(#afterRule(p2), 0, "no area of their own")
    T.eq(stub.Text(p2.items[p2.count].fs), "A note", "right after the card's own lines")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: secret in a fight, shown as they are inside the frame", function()
    foreignLogin()
    local p = withAddon({ "Peacebloom" }, function(t)
        t:AddLine("A note")
        GameTooltipTextLeft2:SetText(stub.Secret("A note"))
    end)
    T.truthy(p.chrome, "the frame only")
    T.eq(GameTooltipTextLeft2:GetAlpha(), 1, "the line itself shows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a plugin's row, bar, tag, section and tiles on the card", function()
    foreignLogin()
    local me = DaylightUI.API.For("Pieces")
    local style
    me.AddTooltipLines("item", function(lines, data)
        style = data.style
        lines.Row("Fish caught", 12)
        lines.Bar("Collected", 3, 8)
        lines.Tag("Rare find", { 0.2, 0.6, 1 })
        lines.Section("Fishing")
        lines.Tiles({ { "12", "caught" }, { "3", "today" } })
    end)
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    update()
    T.eq(style, "rich")
    local p = foreignPanel.Get(GameTooltip)
    local by, collected = {}, nil
    for i = 1, p.count do
        local item = p.items[i]
        by[item.kind] = (by[item.kind] or 0) + 1
        if item.kind == "row" and stub.Text(item.label) == "Collected" then collected = stub.Text(item.value) end
    end
    T.eq(by.tiles, 1, "the tiles")
    T.truthy((by.bar or 0) >= 1, "the bar")
    T.truthy((by.section or 0) >= 1, "the heading")
    T.eq(collected, "3 / 8", "the bar's row")
    T.eq(#p.items[1].tags, 5, "the tag in the header, after the card's own four")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a plugin paints the card once it's laid out, a claimed light left to it", function()
    foreignLogin()
    local me = DaylightUI.API.For("Painter")
    local calls = {}
    me.Paint("tooltip", function(_, parts, info)
        if info then calls[#calls + 1] = { parts = parts, info = info } end
        if parts.light then parts.light[1]:SetVertexColor(0, 1, 0, 1) end
    end, { owns = { "light" } })
    local p = withAddon({ "Mailbox", "Your mail." })
    T.truthy(#calls >= 1, "painted")
    local last = calls[#calls]
    T.eq(last.info.kind, "other")
    T.eq(last.info.style, "rich")
    T.eq(stub.Text(last.parts.title), "Mailbox", "the title among the parts")
    T.eq(last.parts.panel, p)
    local n = #calls
    update()
    T.eq(#calls, n, "not on every frame")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: every header tag in a color of what it says, its outline tinted to match", function()
    local _, Panel = login("rich")
    items()
    local RI = stub.tooltip.RichItems
    _G.ITEM_SOULBOUND, _G.ITEM_BIND_ON_EQUIP, _G.ITEM_UNIQUE = "Soulbound", "Binds when equipped", "Unique"
    stub.items.plans = { id = 12682, quality = 2, kind = "Recipe", sub = "Blacksmithing", icon = 134939,
        class = 9, subClass = 4 }
    fillItem(GameTooltip, "plans", { { "Plans: Shining Mithril Gauntlets", nil, { 0.12, 1, 0 } }, "Soulbound",
        "Unique (5)" })
    local head = Panel.Get(GameTooltip).items[1]
    local function tag(i) return stub.Text(head.tags[i].text), { head.tags[i].text:GetTextColor() } end
    local word, color = tag(1)
    T.eq(word, "RECIPE")
    T.rgb(color, RI.CLASS_COLORS[9], "a recipe in the recipe color")
    word, color = tag(2)
    T.eq(word, "BLACKSMITHING", "its profession a tag of its own")
    T.rgb(color, RI.RECIPE_COLORS[4], "in the profession's color")
    word, color = tag(3)
    T.eq(word, "SOULBOUND")
    T.rgb(color, RI.BIND_YOURS)
    word, color = tag(4)
    T.eq(word, "UNIQUE (5)", "a Unique line with a count is a tag too")
    T.rgb(color, DaylightUI.Style.INK.MONEY, "any Unique line one of a kind")
    -- Armor: the slot in the worn-armor color, binds-on-equip free to trade.
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when equipped", { "Legs", "Plate" } })
    head = Panel.Get(GameTooltip).items[1]
    T.rgb({ head.tags[2].text:GetTextColor() }, RI.SLOT_ARMOR, "a worn slot")
    T.rgb({ head.tags[4].text:GetTextColor() }, RI.BIND_TRADE, "binds when equipped: still free to trade")
    -- Plain trade goods: one tag in its class color.
    fillItem(GameTooltip, "cloth", { "Linen Cloth" })
    head = Panel.Get(GameTooltip).items[1]
    T.eq(stub.Text(head.tags[1].text), "TRADESKILL · CLOTH")
    T.rgb({ head.tags[1].text:GetTextColor() }, RI.CLASS_COLORS[7])
    -- A creature of a kind with no color of its own reads soft white, never tan.
    boar({ creatureType = "Not specified", creatureTypeID = 10 })
    head = Panel.Get(hoverBoar()).items[1]
    T.rgb({ head.tags[2].text:GetTextColor() }, DaylightUI.Style.INK.TEXT)
    -- A player's race in their faction's color.
    player({ faction = "Horde" })
    head = Panel.Get(hover("mouseover", { "Aelindra", "Level 60 Night Elf Mage" }) or GameTooltip).items[1]
    T.eq(stub.Text(head.tags[3].text), "NIGHT ELF")
    T.rgb({ head.tags[3].text:GetTextColor() }, stub.tooltip.RichPlayers.FACTION_COLORS.Horde)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
