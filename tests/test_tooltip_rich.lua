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
        -- The game's own lines read plain again after a clear (seen in game).
        for i = 1, self.__n do
            for _, side in ipairs({ "Left", "Right" }) do
                local fs = line(side, i)
                fs:SetText(nil)
                fs.__secretAspect = nil
            end
        end
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

-- Starts from a saved Simple look (a new profile starts in Rich), so a test
-- that wants Rich switches to it the way a player would.
local function login(style)
    stub.Load({ tooltip = true, before = function()
        world()
        _G.DaylightUIDB = { modules = { Tooltip = { style = "simple", pill = "combat" } } }
    end })
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

T.test("rich tooltip: a new profile starts in Rich, one made before keeps Simple", function()
    stub.Load({ tooltip = true, before = world })
    T.eq(DaylightUI:Get("Tooltip", "style"), "rich", "new profile")
    login()
    T.eq(DaylightUI:Get("Tooltip", "style"), "simple", "saved profile")
end)

T.test("rich tooltip: Simple leaves the skinned look untouched", function()
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
    T.eq(#head.tags, 2)
    T.eq(stub.Text(head.tags[1].text), "MAGE", "spec unknown: the class")
    T.eq(stub.Text(head.right), "60", "the level on the right, as on a creature's card")
    T.rgb({ head.right:GetTextColor() }, DaylightUI.Style.INK.WARN, "the level by how hard they are for you")
    -- When the game can't say how hard: their class color.
    local real = DaylightUI.LevelColor
    DaylightUI.LevelColor = function() return nil end
    local text, ink = stub.tooltip.RichWorld.Level("mouseover")
    DaylightUI.LevelColor = real
    T.eq(text, "60")
    T.rgb(ink, { DaylightUI.Style.ClassTextColor("MAGE") }, "no difficulty: the class color")
    T.eq(stub.Text(head.tags[2].text), "NIGHT ELF")
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
    T.eq(pill:GetWidth(), 224)
    T.eq(GameTooltip:GetAlpha(), 0, "the tooltip itself out of sight")
    T.eq(Tip.Muted(GameTooltip), "pill")
    T.eq(stub.Text(pill.name), "Ridgeback Boar")
    T.eq(stub.Text(pill.level), "23", "its level in front of the name")
    local _, lvInk = stub.tooltip.RichWorld.Level("mouseover")
    T.rgb({ pill.level:GetTextColor() }, lvInk, "in how hard it is for you")
    T.eq(pill.name.__points[1][2], pill.level, "the name after the level")
    -- Seen in game: an orange name on a hostile mob read as neutral.
    T.near(({ pill.name:GetTextColor() })[1], (DaylightUI.Style.ReactionColor(2)), 1e-6, "its name in its reaction's color")
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

-- Seen in game: in a fight the pill showed the level and the health, no name.
-- Once the pill shows a secret health the client gives everything anchored to
-- it secret anchoring, so nothing on it can be measured from the second
-- enemy on: the name has to sit between the level and the health by its
-- points alone.
T.test("rich tooltip: the pill's name sits between the level and the health without measuring", function()
    login("rich")
    player()
    stub.units.mouseover = { name = "Ridgeback Boar", isPlayer = false, reaction = 2, health = 31, maxHealth = 100, level = 23 }
    stub.EnterCombat()
    hover("mouseover", { "Ridgeback Boar", "Level 23 Beast" })
    local pill = _G.DaylightUITooltipPill
    for _, fs in ipairs({ pill.level, pill.name, pill.room, pill.pct }) do stub.HeldSecret(fs) end
    stub.units.mouseover = { name = "Southsea Dock Worker of the Long Name Coast", isPlayer = false, reaction = 2,
        health = 50, maxHealth = 100, level = 35 }
    hover("mouseover", { "Southsea Dock Worker of the Long Name Coast", "Level 35 Humanoid" })
    T.eq(stub.Text(pill.name), "Southsea Dock Worker of the Long Name Coast")
    T.eq(stub.Text(pill.level), "35")
    local left, right
    for _, pt in ipairs(pill.name.__points) do
        if pt[1] == "TOPLEFT" then left = pt elseif pt[1] == "TOPRIGHT" then right = pt end
    end
    T.truthy(left and left[2] == pill.level and left[3] == "TOPRIGHT", "the name starts after the level")
    T.truthy(right and right[2] == pill.room and right[3] == "TOPLEFT" and right[4] < 0, "and ends before the health")
    T.falsy(pill.name:CanWordWrap(), "one line, cut with ... by the client")
    -- No level known: the name starts at the pill's edge.
    stub.units.mouseover.level = nil
    hover("mouseover", { "Southsea Dock Worker of the Long Name Coast" })
    for _, pt in ipairs(pill.name.__points) do
        if pt[1] == "TOPLEFT" then left = pt end
    end
    T.eq(left[2], pill, "no level: from the pill's own edge")
    stub.LeaveCombat()
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

-- Seen in game: on a mob the game already lists a quest for, Questie's copy is
-- left out as a repeat, and its drop chance went with it.
T.test("rich tooltip: Questie's drop chance lands on the game's own row for the same quest", function()
    local _, Panel = login("rich")
    DaylightUI.Npc.Data.QuestColor = function() return { 0.9, 0.5, 0.1 } end
    stub.units.mouseover = { name = "Dark Iron Lookout", isPlayer = false, reaction = 2, level = 47, health = 50, maxHealth = 100 }
    local data = { type = Enum.TooltipDataType.Unit, lines = { {}, {}, { type = 17, id = 77 }, { type = 8 } } }
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Dark Iron Lookout")
    tip:AddLine("Level 47")
    tip:AddLine("Stolen: Smithing Tuyere and Lookout's Spyglass")  -- the game's title (typed)
    tip:AddLine(" - Lookout's Spyglass: 0/1")                      -- the game's objective (typed)
    tip:AddLine("[47] Stolen: Smithing Tuyere and Lookout's Spyglass") -- Questie's, the same quest
    tip:AddLine("   |cffffffffLookout's Spyglass: 0/1|r |cff999999[23.5%]|r")
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    tip:Show()
    local p = Panel.Get(tip)
    local sections, rows = 0, {}
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "section" then sections = sections + 1 end
        if it.kind == "row" then rows[#rows + 1] = it end
    end
    T.eq(sections, 1, "the quest once")
    T.eq(#rows, 1, "its objective once")
    T.truthy(stub.Text(rows[1].label):find("23.5%%"), "with Questie's drop chance")
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
        mahi = { id = 9001, quality = 1, kind = "Quest", sub = "Quest", icon = 133887, class = 12 },
    })
end

-- The game filling a tooltip with an item: its lines (each { left, right,
-- color } or text), its data's own lines (types: line types by index), the
-- post-calls, then Show.
local function fillItem(tip, link, list, after, types, guid, dataLines)
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__link = link
    local own = {}
    for i, t in ipairs(list) do
        if type(t) == "table" then
            local c, rc = t[3] or { 1, 1, 1 }, t[4] or { 1, 1, 1 }
            tip:AddDoubleLine(t[1], t[2], c[1], c[2], c[3], rc[1], rc[2], rc[3])
        else
            tip:AddLine(t)
        end
        -- The game's own sell price line is always a SellPrice data line (11).
        local sell = type(t) == "string" and t:sub(1, 11) == "Sell Price:" and 11 or nil
        own[i] = { type = types and types[i] or sell }
    end
    local data = { type = Enum.TooltipDataType.Item, hyperlink = link, lines = dataLines or own, guid = guid }
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
    T.isnil(lines[4].tail, "an Equip line's stat reads like any other stat")
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
    local wear = DaylightUI.Win.Parts.Hex(DaylightUI.Tips.Wear(98))
    T.eq(stub.Text(foot.label), "Durability " .. wear .. "98|r / 100", "the current number in how worn it is")
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
    T.eq(said[1], "22.7 damage per second", "damage per second without the brackets")
    local dps, rowAt
    for i = 1, p.count do
        if p.items[i] == row then rowAt = i end
        if p.items[i].kind == "line" and bare(p.items[i].fs) == said[1] then dps = i end
    end
    T.truthy(dps < rowAt, "above the damage and speed")
    T.truthy(p.items[dps].fs.size > row.label.size, "bigger than the rows")
    T.eq(Panel.Parts(p).dps, p.items[dps].fs, "a plugin painting the card gets it as dps")
    DaylightUI:Set("Tooltip", "dpsSize", 20)
    GameTooltip:Hide()
    fillItem(GameTooltip, "sword", { { "Thunderforge Blade", nil, { 0, 0.44, 0.87 } }, { "One-Hand", "Sword" },
        { "41 - 77 Damage", "Speed 2.60" }, "(22.7 damage per second)", "+5 Agility" })
    p = Panel.Get(GameTooltip)
    local grown
    for _, l in ipairs(kinds(p, "line")) do if bare(l.fs) == said[1] then grown = l.fs.size end end
    T.truthy(grown > 20, "its own size setting")
    DaylightUI:Set("Tooltip", "dpsSize", nil)
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

T.test("rich tooltip: a quest item says Quest Item once, not its type as well", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "mahi", { "Misty Reed Mahi Mahi", "Quest Item", "Unique" })
    update()
    local head = Panel.Get(GameTooltip).items[1]
    local words = {}
    for i, tag in ipairs(head.tags) do words[i] = stub.Text(tag.text) end
    T.eq(table.concat(words, ", "), "QUEST ITEM, UNIQUE")
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

-- Seen by a player who dual wields: both compare tooltips said only
-- "Equipped", and opening to the right the game put the off hand next to the
-- item, where it read as the main hand.
T.test("rich tooltip: with a weapon in each hand each compare says which hand, the main hand next to the item", function()
    local Tip, Panel = login("rich")
    items()
    _G.INVTYPE_WEAPONMAINHAND, _G.INVTYPE_WEAPONOFFHAND = "Main Hand", "Off Hand"
    local oldLoc, oldGuid, oldExists = _G.ItemLocation, C_Item.GetItemGUID, C_Item.DoesItemExist
    _G.ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
    local worn = { [16] = "Item-sabre", [17] = "Item-claw" }
    C_Item.GetItemGUID = function(loc) return worn[loc.slot] end
    C_Item.DoesItemExist = function(loc) return worn[loc.slot] ~= nil end
    fillItem(GameTooltip, "greaves", GREAVES)
    local function shop(tip, guid, name)
        tip:SetOwner(GameTooltip, "ANCHOR_NONE")
        tip.CompareHeader:Show()
        tip.CompareHeader.Label:SetText("Equipped")
        fillItem(tip, "sword", { { name or "Outlaw Sabre", nil, { 0, 0.439, 0.867 } }, "One-Hand" }, nil, nil, guid)
    end
    -- The game's primary is the main hand; opening to the right it hangs the
    -- secondary on the item and the primary beyond it.
    local a, b = ShoppingTooltip1, ShoppingTooltip2
    shop(a, "Item-sabre")
    shop(b, "Item-claw")
    T.eq(stub.Text(Panel.Get(a).items[1].list[1].text), "EQUIPPED · MAIN HAND")
    T.eq(stub.Text(Panel.Get(b).items[1].list[1].text), "EQUIPPED · OFF HAND")
    a:ClearAllPoints()
    b:ClearAllPoints()
    b:SetPoint("TOP", GameTooltip, "TOP", 0, 0)
    b:SetPoint("LEFT", GameTooltip, "RIGHT", 0, 0)
    a:SetPoint("TOP", GameTooltip, "TOP", 0, 0)
    a:SetPoint("TOPLEFT", b, "TOPRIGHT", 0, 0)
    update()
    local function on(f, other)
        for i = 1, f:GetNumPoints() do
            local _, rel = f:GetPoint(i)
            if rel == other then return true end
        end
        return false
    end
    T.truthy(on(a, GameTooltip) and not on(a, b), "the main hand hangs on the item now")
    T.truthy(on(b, a), "the off hand beyond it")
    update()
    T.truthy(on(b, a) and not on(a, b), "and it stays put")
    -- The main hand already next to the item (opening to the left): left alone.
    a:ClearAllPoints()
    b:ClearAllPoints()
    a:SetPoint("TOP", GameTooltip, "TOP", 0, 0)
    a:SetPoint("RIGHT", GameTooltip, "LEFT", 0, 0)
    b:SetPoint("TOP", GameTooltip, "TOP", 0, 0)
    b:SetPoint("TOPRIGHT", a, "TOPLEFT", 0, 0)
    update()
    T.truthy(on(a, GameTooltip) and on(b, a), "the game's own order kept")
    -- A two-hander or one weapon: just Equipped.
    worn = {}
    shop(a, "Item-other", "Polished Zweihander")
    T.eq(stub.Text(Panel.Get(a).items[1].list[1].text), "EQUIPPED")
    _G.ItemLocation, C_Item.GetItemGUID, C_Item.DoesItemExist = oldLoc, oldGuid, oldExists
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

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
    T.eq(p.items[p.count - 1].kind, "section", "a heading says they're the swap")
    T.eq(stub.Text(p.items[p.count - 1].fs), "IF YOU SWAP")
    T.eq(p.items[p.count - 2].kind, "rule", "under a rule")
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

-- Forever Leveling BiS draws boxes, an arrow and text right on the tooltip
-- after it shows. Made after the card hid the tooltip's own pieces, they drew
-- over the card (seen in game on loot and compare tooltips).
T.test("rich tooltip: pieces another addon makes on a shown tooltip are hidden under the card", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "legplates", LEGPLATES)
    local p = Panel.Get(GameTooltip)
    T.truthy(p and p:IsShown(), "the card")
    local band = GameTooltip:CreateTexture(nil, "BORDER")
    local words = GameTooltip:CreateFontString(nil, "OVERLAY")
    words:SetText("No use found for you")
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq(band:GetAlpha(), 0, "the addon's band")
    T.eq(words:GetAlpha(), 0, "the addon's text")
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

T.test("rich tooltip: durability is colored by how worn the item is", function()
    login("rich")
    local Items = stub.tooltip.RichItems
    local Tips, hex = DaylightUI.Tips, DaylightUI.Win.Parts.Hex
    T.eq(Items.WearText("Durability 55 / 55"), "Durability " .. hex(Tips.GOOD) .. "55|r / 55", "whole: green")
    T.eq(Items.WearText("Durability 5 / 55"), "Durability " .. hex(Tips.BAD) .. "5|r / 55", "nearly broken: red")
    T.eq(Items.WearText("Durability 0 / 55"), "Durability " .. hex(Tips.BAD) .. "0|r / 55", "broken: red")
    T.eq(Items.WearText("Durability 1 / 0"), "Durability 1 / 0", "no most: left as it is")
    local half = hex(Tips.Wear(50))
    T.eq(half, hex(Tips.WARN), "half worn: amber")
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
    T.truthy(stub.Text(foot.label):find("51|r / 55", 1, true), "the durability line")
    T.eq(stub.Text(foot.value), "1g 25s", "the coins from its right side")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's report with TSM: its "Vendor Buy Price" and "Vendor Sell Price"
-- rows start with the word the card used to find the game's sell price, so
-- both went missing from TSM's block and TSM's sell price, in its own
-- lettered text, took the game's coins' place at the foot.
T.test("rich tooltip: TSM's vendor price rows stay TSM's, the foot keeps the game's coins", function()
    local _, Panel = login("rich")
    items()
    local W = DaylightUI.Widgets
    local list = { "Coal", "Crafting Reagent", "Sell Price: 2|A:coin-silver:0:0|a 50|A:coin-copper:0:0|a" }
    fillItem(GameTooltip, "cloth", list, function(t)
        t:AddLine("TSM General Info", 1, 0.82, 0)
        t:AddDoubleLine("  Vendor Buy Price", "5|cffc7c7cfs|r 00|cffeda55fc|r")
        t:AddDoubleLine("  Vendor Sell Price", "1|cffc7c7cfs|r 25|cffeda55fc|r")
        t:AddDoubleLine("TSM AuctionDB", "194 auctions", 1, 0.82, 0)
        t:AddDoubleLine("  Min Buyout", "4|cffc7c7cfs|r 98|cffeda55fc|r")
    end, { [3] = 11 })
    local p = Panel.Get(GameTooltip)
    local rows = kinds(p, "row")
    local byLabel = {}
    -- TSM indents its rows; the card keeps that.
    for _, r in ipairs(rows) do byLabel[(stub.Text(r.label):gsub("^%s+", ""))] = r end
    T.truthy(byLabel["Vendor Buy Price"], "TSM's buy price row is on the card")
    T.truthy(byLabel["Vendor Sell Price"], "TSM's sell price row is on the card")
    T.eq(stub.Text(byLabel["Vendor Sell Price"].value), W.Money(125), "in coins, under TSM's heading")
    local foot = rows[#rows]
    T.eq(stub.Text(foot.label), "Vendor")
    T.eq(stub.Text(foot.value), W.Money(250), "the game's own sell price at the foot, in coins")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A quest reward's price is added by Daylight UI (the client's data has no
-- sell price line then): it still goes to the foot, and an addon's row
-- starting with the same word stays with that addon.
T.test("rich tooltip: a quest reward's added price goes to the foot, not an addon's Vendor row", function()
    local _, Panel = login("rich")
    items()
    local W = DaylightUI.Widgets
    local was = { C_Item.GetItemInfo, _G.GetQuestLogChoiceInfo }
    C_Item.GetItemInfo = function(link, ...)
        if link == "mahi" then return link, link, 1, 10, 1, "", "", 20, "", 1, 175 end
        return was[1](link, ...)
    end
    _G.GetQuestLogChoiceInfo = function() return "Mahi Kebab", 1, 1, 1, true, 9001 end
    GameTooltip.infoList = { { getterName = "GetQuestLogItem", getterArgs = { "choice", 1, 99 } } }
    fillItem(GameTooltip, "mahi", { "Mahi Kebab", "Quest Item" }, function(t)
        t:AddDoubleLine("Vendor Sell Price", "9|cffc7c7cfs|r")
    end)
    GameTooltip.infoList = nil
    C_Item.GetItemInfo, _G.GetQuestLogChoiceInfo = was[1], was[2]
    T.eq(GameTooltipTextLeft3:GetText(), "Vendor: " .. W.Money(175), "the price Daylight UI added")
    local rows = kinds(Panel.Get(GameTooltip), "row")
    local foot = rows[#rows]
    T.eq(stub.Text(foot.label), "Vendor")
    T.eq(stub.Text(foot.value), W.Money(175), "the added price at the foot")
    local seen = false
    for _, r in ipairs(rows) do
        if stub.Text(r.label) == "Vendor Sell Price" then seen = true end
    end
    T.truthy(seen, "the addon's row on the card")
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

-- Seen by a player: with an item and its compares up, the compares jumped
-- sideways five times a second. A bag slot refills its tooltip every 0.2 s
-- (ContainerFrameItemButtonMixin:OnUpdate) starting with SetOwner, which hides
-- a shown tooltip, and the game's OnHide and OnShow clear the padding
-- (GameTooltip_CalculatePadding, ClearPadding). Modeled here, a guess that
-- fits the video: the client takes a new padding when it lays the frame out,
-- so until then the tooltip reads back its old size. The card measured
-- nothing to fix, the cleared padding won, and for one frame the tooltip was
-- its bare lines' width with the compares hanging off its moved edge.
T.test("rich tooltip: a refill that hides and shows the tooltip keeps its size, so its compares stay put", function()
    local _, Panel = login("rich")
    items()
    local layouts = {}
    local function lagging(tip)
        local set, pending = tip.SetPadding, nil
        tip.SetPadding = function(self, r, b, l, t) pending = { r, b, l or 0, t or 0 } end
        local get = tip.GetPadding
        tip.GetPadding = function(self)
            if pending then return unpack(pending) end
            return get(self)
        end
        layouts[#layouts + 1] = function()
            if pending then set(tip, unpack(pending)) end
            pending = nil
        end
    end
    local function layout() for _, f in ipairs(layouts) do f() end end
    local tip, shop = GameTooltip, ShoppingTooltip1
    lagging(tip)
    lagging(shop)
    local function refresh(first)
        if not first then
            -- SetOwner on the shown tooltip: it hides, and its compares with it.
            tip:Hide()
            shop:Hide()
        end
        fillItem(tip, "greaves", GREAVES)
        compare(shop, CHANGES)
        update()
        layout()
    end
    refresh(true)
    stub.Advance(0.02)
    update()
    layout()
    local function size(t) local p = Panel.Get(t); return p.wantW * p:GetScale() end
    T.near(tip:GetWidth(), size(tip), 0.5, "first show: the tooltip is the card's width")
    T.near(shop:GetWidth(), size(shop), 0.5, "and the compare's")
    for i = 1, 3 do
        stub.Advance(0.2)
        refresh()
        T.near(tip:GetWidth(), size(tip), 0.5, "refill " .. i .. ": the tooltip keeps the card's width")
        T.near(shop:GetWidth(), size(shop), 0.5, "refill " .. i .. ": the compare keeps it too")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player switched equipment sets and the compares still showed the old
-- set's items. The game picks what to compare (TooltipComparisonManager);
-- the card is read from the compare tooltip's own lines on every fill, so a
-- refill with the newly worn item shows that item, with nothing kept.
T.test("rich tooltip: after an equipment set switch the compare card shows what is worn now", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    compare(ShoppingTooltip1, CHANGES)
    update()
    local p = Panel.Get(ShoppingTooltip1)
    T.eq(stub.Text(kinds(p, "header")[1].title), "Tarnished Legplates", "worn before the switch")
    -- The set switched; the hovered item's 0.2 s refill compares the new one.
    stub.Advance(0.2)
    fillItem(GameTooltip, "greaves", GREAVES)
    local shop = ShoppingTooltip1
    shop:SetOwner(GameTooltip, "ANCHOR_NONE")
    shop.CompareHeader:Show()
    shop.CompareHeader.Label:SetText("Equipped")
    fillItem(shop, "sword", { { "Runed Blade", nil, { 0, 0.439, 0.867 } }, { "Legs", "Plate" }, "512 Armor" })
    update()
    T.eq(stub.Text(kinds(p, "header")[1].title), "Runed Blade", "the newly worn item")
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

-- Seen by a player: on cooldown the card showed only "Ready in" and lost
-- everything the spell does.
T.test("rich tooltip: a spell cooling down on an action button keeps its card and adds when it's ready", function()
    local _, Panel = login("rich")
    spells()
    stub.ActionSlots({ [5] = { spellID = 116, cooldown = true, cdStart = GetTime() - 5.8, cdDuration = 10 } })
    fillSpell(116, FROSTBOLT, nil, actionButton(5))
    local p = Panel.Get(GameTooltip)
    local INK = DaylightUI.Style.INK
    T.eq(p.kind, "spell", "the spell's own card")
    T.eq(stub.Text(p.items[1].title), "Frostbolt")
    T.eq(#kinds(p, "tiles")[1].list, 3, "cast, cost and range still there")
    local desc = stub.Text(kinds(p, "text")[1].fs)
    T.truthy(desc:find("Launches a bolt of frost", 1, true), "the description still there: " .. desc)
    local ready = kinds(p, "row")[1]
    T.eq(stub.Text(ready.label), "Ready in")
    T.eq(stub.Text(ready.value), "4.2 sec")
    T.rgb({ ready.value:GetTextColor() }, INK.WARN)
    T.truthy(ready.y < kinds(p, "text")[1].y, "when it's ready under the strip, above the description")
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
    T.eq(p.kind, "spell")
    T.eq(#kinds(p, "row"), 0, "ready: no countdown left")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a recharging spell shows its charges; the global cooldown alone adds nothing", function()
    local _, Panel = login("rich")
    spells()
    stub.ActionSlots({
        [5] = { spellID = 116, charges = true, chargesNow = 1, chargesMax = 2, chargeStart = GetTime() - 2, chargeDuration = 8 },
        [6] = { spellID = 116, cooldown = true, gcd = true, cdStart = GetTime(), cdDuration = 1.5 },
    })
    fillSpell(116, FROSTBOLT, nil, actionButton(5))
    local p = Panel.Get(GameTooltip)
    local INK = DaylightUI.Style.INK
    T.eq(p.kind, "spell")
    local rows = kinds(p, "row")
    T.eq(stub.Text(rows[1].value), "6.0 sec", "the next charge")
    T.eq(stub.Text(rows[2].label), "Charges")
    T.eq(stub.Text(rows[2].value), "1 " .. DaylightUI.Win.Parts.Hex(INK.LABEL) .. "/ 2|r")
    T.eq(kinds(p, "bar")[1].bar.__timer[1].kind, "charges", "the charge's own duration")
    fillSpell(116, FROSTBOLT, nil, actionButton(6))
    update()
    T.eq(#kinds(p, "row"), 0, "the global cooldown: no countdown")
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

T.test("a party member's name under a quest is in their class color, rich and simple", function()
    for _, style in ipairs({ "rich", "simple" }) do
        local _, Panel = login(style)
        stub.units.player.name = "Daylight"
        stub.units.player.class = "PRIEST"
        stub.units.party1 = { name = "Relio", lastName = "Lightsong", class = "PALADIN", isPlayer = true }
        stub.units.mouseover = { name = "Barbed Lasher", isPlayer = false, reaction = 2, level = 45, health = 50, maxHealth = 100 }
        local data = { type = Enum.TooltipDataType.Unit, lines = { {}, { type = 17 },
            { type = 18, leftText = "Daylight" }, { type = 8 },
            { type = 18, leftText = "Relio Lightsong" }, { type = 8 },
            { type = 18, leftText = "Stranger" }, { type = 8 } } }
        local tip = GameTooltip
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip.__unit = "mouseover"
        tip:AddLine("Barbed Lasher")
        tip:AddLine("Twisted Evils", 1, 0.82, 0)
        tip:AddLine("Daylight", 1, 0.82, 0)
        tip:AddLine(" - 2/25 Theradric Crystal Carving")
        tip:AddLine("Relio Lightsong", 1, 0.82, 0)
        tip:AddLine(" - 3/25 Theradric Crystal Carving")
        tip:AddLine("Stranger", 1, 0.82, 0)
        tip:AddLine(" - 1/25 Theradric Crystal Carving")
        for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
        for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
        tip:Show()
        local Style = DaylightUI.Style
        local paladin = { Style.ClassTextColor("PALADIN") }
        if style == "rich" then
            local p = Panel.Get(tip)
            local colors = {}
            for i = 1, p.count do
                local it = p.items[i]
                if it.kind == "text" then colors[stub.Text(it.fs)] = { it.fs:GetTextColor() } end
            end
            T.rgb(colors["Relio Lightsong"], paladin, "rich: the paladin's name in paladin color")
            T.rgb(colors["Stranger"], Style.INK.LABEL, "rich: someone not in the group stays tan")
        else
            T.rgb({ _G.GameTooltipTextLeft3:GetTextColor() }, { Style.ClassTextColor("PRIEST") }, "simple: your own name in your class color")
            T.rgb({ _G.GameTooltipTextLeft5:GetTextColor() }, paladin, "simple: the paladin's name")
            T.rgb({ _G.GameTooltipTextLeft7:GetTextColor() }, { 1, 0.82, 0 }, "simple: a stranger keeps the game's color")
        end
        tip:Hide()
        stub.units.party1 = nil
    end
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
    T.eq(stub.Text(foot.label), "Vendor")
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

-- Seen on a German client: a long tag ran out of the card, cut at its
-- edge, and a long sub line ("Begleiter von ...") ran into the edge.
T.test("rich tooltip: a tag or sub line too long for the card wraps instead of running past its edge", function()
    local _, Panel = login("rich")
    local long = "Himmelsgeborene des Hohen Ordens der Ewigen Morgenroete"
    boar({ creatureType = long, creatureTypeID = 1 })
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip.__unit = "mouseover"
    tip:AddLine("Ridgeback Boar")
    tip:AddLine("Begleiter von Racketz Reloaded aus dem Hause der Langen Namen")
    tip:AddLine("Level 23 Beast")
    local data = { type = Enum.TooltipDataType.Unit, lines = { {}, {}, {} } }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[data.type] or {}) do fn(tip, data) end
    tip:Show()
    update()
    local p = Panel.Get(tip)
    local head = p.items[1]
    local pad = Panel.PAD_X
    local edge = p.wantW - (p.padX or pad)
    local sub = head.sub
    T.truthy(sub, "the sub line")
    local x = sub.__points[1][4]
    T.truthy(sub:GetWidth() > 0 and x + sub:GetWidth() <= edge + 0.5, "the sub line kept inside the card")
    T.truthy(sub:CanWordWrap(), "and wrapped")
    local tag
    for _, t in ipairs(head.tags) do
        if stub.Text(t.text) == DaylightUI.Style.Upper(long) then tag = t end
    end
    T.truthy(tag, "the long tag")
    local tx = tag.__points[1][4]
    T.truthy(tx + tag:GetWidth() <= edge + 0.5, "the tag kept inside the card: " .. (tx + tag:GetWidth()) .. " > " .. edge)
    T.truthy(tag.text:CanWordWrap() and tag:GetHeight() > DaylightUI.Widgets.TAG_H, "its words on two lines, the tag taller")
    T.truthy(head.h >= tag:GetHeight(), "the header makes room for it")
    -- Reused for a short one: back to one line.
    boar()
    hoverBoar()
    for _, t in ipairs(Panel.Get(tip).items[1].tags) do
        T.near(t:GetHeight(), DaylightUI.Widgets.TAG_H, 0.5, "a short tag one line again")
        T.falsy(t.text:CanWordWrap())
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

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
    T.eq(head.title.size, DaylightUI.Style.SIZE.head)
    T.eq(head.icon.art.__portraitUnit, "mouseover", "its face as the icon")
    T.truthy(head.icon.art.__portraitSquare, "square: the card cuts the corner")
    T.eq(stub.Text(head.right), "23", "the level on the right")
    T.rgb({ head.right:GetTextColor() }, DaylightUI.Style.INK.WARN, "the level by how hard it is for you, not its reaction")
    -- Seen in game: a gray level 12 mob's card showed its level hostile red,
    -- while its plate showed it gray.
    stub.units.mouseover.difficulty = 0
    p = Panel.Get(hoverBoar())
    T.rgb({ p.items[1].right:GetTextColor() }, DaylightUI.Style.INK.OFF, "a trivial mob's level stays gray")
    local real = DaylightUI.LevelColor
    DaylightUI.LevelColor = function() return nil end
    local _, ink = stub.tooltip.RichWorld.Level("mouseover")
    DaylightUI.LevelColor = real
    T.rgb(ink, { DaylightUI.Style.ReactionColor(2) }, "no difficulty and not a player: its reaction")
    T.eq(tagWords(head), "HOSTILE,BEAST,SKINNABLE")
    T.falsy(head.icon and head.icon.edge:IsShown(), "a plain mob's face has no edge")
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
    T.eq(tagWords(head), "ELITE,RARE,HOSTILE,BEAST,SKINNABLE", "elite and rare first, where a glance looks")
    T.eq(stub.Text(head.right), "??", "no + after a skull level")
    T.rgb({ head.right:GetTextColor() }, DaylightUI.Style.INK.BAD)
    T.truthy(head.icon and head.icon.edge:IsShown(), "a rare elite's face wears an edge")
    T.rgb({ head.icon.edge:GetVertexColor() }, stub.tooltip.RichWorld.RARE_COLOR, "in silver, as the game's rare elite dragon")
    -- A rare at a known level: a silver R after it.
    boar({ classification = "rare", level = 20 })
    hoverBoar()
    head = p.items[1]
    T.truthy(stub.Text(head.right):find("^20|c%x+R|r$"), "a rare's level carries an R")
    T.eq(tagWords(head), "RARE,HOSTILE,BEAST,SKINNABLE")
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

-- Seen in game: in a dungeon the nameplate said 3/8 and the tooltip card had
-- no quest at all. The tooltip's lines are secret there and the card is built
-- from the unit, but the game's data still names the quests (a nameplate
-- reads the same lines).
T.test("rich tooltip: a mob in a restricted dungeon keeps the quests it counts for", function()
    local _, Panel = login("rich")
    stub.units.mouseover = { name = "Pathstrider", isPlayer = false, reaction = 2, level = 58, health = 90, maxHealth = 100 }
    stub.SetRestriction("Map", true)
    local tip = GameTooltip
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    tip.__unit = stub.Secret("mouseover")
    for i, t in ipairs({ "Pathstrider", "Level 58 Humanoid", "The Highborne", " - Pathstrider slain: 3/8", "Hidden Goal" }) do
        tip:AddLine(t)
        _G["GameTooltipTextLeft" .. i]:SetText(stub.Secret(t))
    end
    local data = { type = Enum.TooltipDataType.Unit, lines = {
        { leftText = stub.Secret("Pathstrider"), type = 2 },
        { leftText = stub.Secret("Level 58 Humanoid"), type = 0 },
        { leftText = "The Highborne", type = 17, id = 501 },
        { leftText = " - Pathstrider slain: 3/8", type = 8 },
        { leftText = stub.Secret("Hidden Goal"), type = 17 },
    } }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[Enum.TooltipDataType.Unit] or {}) do fn(tip, data) end
    tip:Show()
    update()
    local p = Panel.Get(tip)
    T.truthy(p and p:IsShown() and not p.chrome, "the whole card")
    local sections = itemsOf(p, "section")
    T.eq(#sections, 1)
    T.eq(stub.Text(sections[1].fs), "THE HIGHBORNE", "the quest's heading")
    T.eq(stub.Text(rowsOf(p)["Pathstrider slain"].value), "3 / 8", "and its count")
    local lines = itemsOf(p, "line")
    T.eq(#lines, 1, "a secret quest line as one line")
    T.eq(stub.Text(lines[1].fs), "Hidden Goal")
    T.truthy(lines[1].fs:GetWidth() > 0, "cut at the card's edge")
    stub.SetRestriction("Map", false)
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

T.test("rich tooltip: a Wanted Poster's card shows the quests another addon lists on it", function()
    local _, Panel = login("rich")
    stub.SetSkills({})
    local tip = GameTooltip
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    tip.__unit = nil
    tip:AddLine("Wanted Poster")
    local data = { type = 4, lines = { {} } }
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    -- The Quests module's lines for what it starts, as GiverTips adds them.
    tip:AddLine(" ")
    tip:AddDoubleLine("|A:QuestNormal:14:14|a |cffffff00Wanted: Hogger|r", "|cffffff0011|r", 1, 1, 0, 1, 1, 0)
    tip:Show()
    update()
    local p = Panel.Get(tip)
    T.eq(stub.Text(p.items[1].title), "Wanted Poster")
    local found
    for i = 1, p.count do
        local item = p.items[i]
        if item.kind == "row" and (stub.Text(item.label) or ""):find("Wanted: Hogger", 1, true) then found = item end
    end
    T.truthy(found, "the quest on the card")
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

T.test("rich tooltip: food reads in a few words on its card, under the short stats switch", function()
    local _, Panel = login("rich")
    items()
    local FOOD = "Use: Restores 530 health over 24 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and gain 5 Stamina and 5% increased experience from kills for 15 min."
    local function said()
        local p, out = Panel.Get(GameTooltip), {}
        for _, t in ipairs(kinds(p, "text")) do
            out[#out + 1] = (stub.Text(t.fs):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        end
        return out
    end
    fillItem(GameTooltip, "cloth", { "Smoked Bear Meat", { FOOD, nil, GREEN } })
    local out = said()
    T.eq(out[1], "Use: 530 health over 24 sec")
    T.eq(out[2], "Well Fed: +5 Stamina, +5% XP (15 min)")
    DaylightUI:Set("Tooltip", "greenStats", false)
    stub.RunTimers()
    GameTooltip:Hide()
    fillItem(GameTooltip, "cloth", { "Smoked Bear Meat", { FOOD, nil, GREEN } })
    T.eq(said()[1], FOOD, "off: the game's sentence")
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
    -- Under the icon, across the card's inside; the last ones on a lower row.
    local _, _, _, x1, y1 = head.tags[1]:GetPoint(1)
    local _, _, _, _, y5 = head.tags[5]:GetPoint(1)
    T.truthy(y5 < y1, "the last ones on another row")
    local inside = 290 - 2 * 16
    for _, tag in ipairs(head.tags) do
        local _, _, _, x = tag:GetPoint(1)
        T.truthy(x - x1 + tag:GetWidth() <= inside + 0.5, "never past the edge")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Spanish "CONSUMIBLE · COMIDA Y BEBIDA" is one tag wider than the row beside the
-- icon: it is cut there, not run past the card.
T.test("rich tooltip: a single tag wider than its row is cut at the row's edge", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when picked up",
        { "Legs", "Plate" }, "742 Armor" })
    local head = Panel.Get(GameTooltip).items[1]
    local tag = head.tags[1]
    tag.Set("A long kind of item and then more", nil)
    local room = 290 - 2 * 16 - 44 - 12
    tag.FitWidth(room)
    T.truthy(tag:GetWidth() <= room + 0.5, "cut to the room")
    tag.FitWidth()
    T.truthy(tag:GetWidth() > room, "its own width again when the room is not limited")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Tags sit beside the icon while each fits on one row there;
-- one that would wrap sends them all under the icon, across the card's width.
T.test("rich tooltip: tags beside the icon while they fit, under it when one would wrap", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when picked up",
        { "Legs", "Plate" }, "742 Armor" })
    local p = Panel.Get(GameTooltip)
    local function spots()
        local head = p.items[1]
        local byTag = {}
        for _, sp in ipairs(p.tagSpots) do byTag[sp[1]] = sp end
        return head, byTag
    end
    Panel.Finish(p)
    local head, byTag = spots()
    local first = byTag[head.tags[1]]
    T.truthy(first[2] > 16 + 40, "short tags: right of the icon")
    local beside = first[3]
    local tag = head.tags[1]
    tag.Set("A long kind of item and then more", nil)
    Panel.Finish(p)
    head, byTag = spots()
    local sp
    for _, c in ipairs(p.tagSpots) do if c[1] == tag then sp = c end end
    T.truthy(sp, "placed")
    local icon = head.icon:GetHeight()
    T.truthy(sp[2] < first[2], "a long one: back at the card's left edge, under the icon")
    T.truthy(sp[3] >= icon, "below the icon's bottom")
    T.truthy(sp[3] > beside - 0.01, "never above where it sat")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: "Desgarracortez..." (a creature's name is one long word, which
-- can't wrap): the title's letters shrink until the word fits.
T.test("rich tooltip: a title with one long word shrinks to fit instead of being cut", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when picked up",
        { "Legs", "Plate" }, "742 Armor" })
    local p = Panel.Get(GameTooltip)
    Panel.Begin(p, "mob")
    Panel.Header(p, { title = "Desgarracortezasdelmundoantiguo", right = "26" })
    local title = p.items[1].title
    local before = title.size
    Panel.Finish(p)
    T.truthy(title.size < before, "smaller letters")
    T.truthy(title.size >= before * Panel.SHRINK_MIN - 0.01, "not past the least")
    p.items[1].title:SetText("Short")
    Panel.Begin(p, "mob")
    Panel.Header(p, { title = "Short", right = "26" })
    local short = p.items[1].title
    local full = short.size
    Panel.Finish(p)
    T.eq(short.size, full, "a short name keeps its size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A name on two lines is taller than the icon: the icon sits in the middle of
-- the words, not at their top.
T.test("rich tooltip: the icon is centered against a header's taller words", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when picked up",
        { "Legs", "Plate" }, "742 Armor" })
    local p = Panel.Get(GameTooltip)
    Panel.Begin(p, "mob")
    Panel.Header(p, { icon = 134400, iconSize = 20, title = "Desgarracortezas Sombramatorral of the Long Name Indeed Yes", right = "26" })
    Panel.Finish(p)
    local head = p.items[1]
    local _, _, _, _, iy = head.icon:GetPoint(1)
    local _, _, _, _, ty = head.title:GetPoint(1)
    T.truthy(iy < ty, "the icon lower than the words' top")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: "35 Ma..." (a spell's tiles, equal widths): each tile takes what
-- its words need, the card widens a little for them, and none is cut.
T.test("rich tooltip: a spell's tiles take what their words need", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when picked up",
        { "Legs", "Plate" }, "742 Armor" })
    local p = Panel.Get(GameTooltip)
    Panel.Begin(p, "spell")
    Panel.Tiles(p, { { "1,5 sec", "Cast time" }, { "35 Mana", "Cost" }, { "30 sec", "Cooldown time" } })
    Panel.Finish(p)
    local list = p.items[1].list
    local sum = 2 * Panel.TILE_GAP
    for _, t in ipairs(list) do
        T.truthy(t:GetWidth() >= t.Need() - 0.5, "wide enough for its words")
        sum = sum + t:GetWidth()
    end
    T.truthy(list[3]:GetWidth() > list[1]:GetWidth(), "the long one wider")
    T.truthy(sum <= p.wantW - 2 * 16 + 0.5, "inside the card")
    T.truthy(p.wantW <= math.ceil(270 * Panel.GROW), "the card widens only so far")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: a quest's heading on an item's card ("[24M] INVESTIGACIONES ACERCA
-- DE LA CORRUPCION") ran past the card's edge: it wraps onto a second line.
T.test("rich tooltip: a quest heading longer than the card wraps instead of running past it", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when picked up",
        { "Legs", "Plate" }, "742 Armor" })
    local p = Panel.Get(GameTooltip)
    Panel.Begin(p, "item")
    Panel.Section(p, "[20] Short")
    local _, shortH = Panel.Finish(p)
    Panel.Begin(p, "item")
    Panel.Section(p, "[24M] Research about the corruption of the old world and more")
    local _, longH = Panel.Finish(p)
    T.truthy(longH > shortH + 8, "a second line, not one running past the card")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: "Scalping Tomahawk of H..." lost the words that say what the
-- item is for. A name too long for the card takes a second line.
T.test("rich tooltip: a long item name wraps instead of being cut", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", { { "Scalping Tomahawk of Healing and Everlasting Fortitude", nil, EPIC },
        "Binds when equipped", "742 Armor" })
    local head = Panel.Get(GameTooltip).items[1]
    local title = head.title
    T.truthy(title:CanWordWrap(), "wraps")
    T.eq(title:GetMaxLines(), 2, "at most two lines")
    T.truthy(head.tags[1]:GetHeight() > 0)
    local _, _, _, _, top = head.tags[1]:GetPoint(1)
    local _, _, _, _, ttop = title:GetPoint(1)
    T.truthy(-top - -ttop >= 2 * title.size, "the tags sit under both lines")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seen in game: "Green Hills of Stranglethorn - Pag..." on a narrow card. Two
-- lines weren't enough for its words, so the second one ended in "...".
T.test("rich tooltip: a name that needs three lines gets three", function()
    local _, Panel = login("rich")
    items()
    local name = "Green Hills of Stranglethorn Valley Collected Works - Page 6"
    fillItem(GameTooltip, "greaves", { { name, nil, EPIC }, "742 Armor" })
    local title = Panel.Get(GameTooltip).items[1].title
    -- Wrap it word by word at the title's width, as the client does.
    local room, lines, row = title:GetWidth(), 1, ""
    for word in name:gmatch("%S+") do
        local try = row == "" and word or (row .. " " .. word)
        title:SetText(try)
        if row ~= "" and title:GetStringWidth() > room then lines, row = lines + 1, word else row = try end
    end
    title:SetText(name)
    T.truthy(lines == 3, "the name needs three lines here: " .. lines)
    T.eq(title:GetMaxLines(), 3, "all of them")
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

-- Seen in game on a quest's tooltip: an objective with a long name was cut ("Marca de
-- honor de la Cuenc...  0 / 3"). It wraps onto another line, the count staying at the edge.
T.test("rich tooltip: a quest objective's long name wraps instead of being cut", function()
    local _, Panel = login("rich")
    fill(99, { "A quest", "Zone", "0/3 " .. string.rep("Honor mark of the Arathi Basin ", 4) })
    local p = Panel.Get(GameTooltip)
    local row
    for _, it in ipairs(kinds(p, "row")) do if stub.Text(it.value) == "0 / 3" then row = it end end
    T.truthy(row, "the objective is a row with its count")
    T.truthy(row.label.__wordWrap == true, "its name may wrap")
    T.truthy(row.label:GetWidth() > 0, "held to the room before the count")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A quest's tooltip has a gap between its heading and its objectives, and its reward
-- under a "Rewards" heading in money's own color. The card reads the gap as no section
-- break, and money isn't read as a yellow description.
T.test("rich tooltip: a gap between a quest's heading and its objectives is no section, money keeps its color", function()
    local _, Panel = login("rich")
    local coins = "5|T" .. "Interface/AddOns/DaylightUI/Media/coin-gold.png:0:0:0:0:64:64:-4:60:0:64|t"
    fill(99, { "A quest", "Level 29", "The Barrens", " ", "0/3 Honor mark", " ", "Rewards", coins })
    local p = Panel.Get(GameTooltip)
    local seq = {}
    for i = 1, p.count do seq[#seq + 1] = p.items[i].kind end
    local list = table.concat(seq, ",")
    T.truthy(list:find("section,row,bar", 1, true), "the zone is the heading right over the objectives: " .. list)
    T.falsy(list:find("rule,section,rule", 1, true), "no empty section from the gap: " .. list)
    T.falsy(list:find("section,text,rule,section", 1, true))
    local money
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "text" and it.fs and stub.Text(it.fs):find("coin-gold", 1, true) then money = it end
    end
    T.truthy(money, "the reward's line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A tooltip line with two sides (an objective and its count, written by Daylight UI's
-- quest tracker) had its long left side cut. It wraps now, and the row grows with it;
-- the count keeps its own color at the edge.
T.test("rich tooltip: a two-sided line's long left side wraps and the row grows, the value keeps its color", function()
    local _, Panel = login("rich")
    local long = string.rep("Honor mark of the Arathi Basin ", 4)
    fill(99, { "A quest", { long, "0/3", 1, 1, 1, 1, 0.3, 0.3 }, { "Short", "1/2", 1, 1, 1, 1, 0.8, 0.2 } })
    local p = Panel.Get(GameTooltip)
    local rows = kinds(p, "row")
    local tall, short
    for _, it in ipairs(rows) do
        if stub.Text(it.value) == "0/3" then tall = it elseif stub.Text(it.value) == "1/2" then short = it end
    end
    T.truthy(tall and short, "both lines are rows")
    T.truthy(tall.label.__wordWrap == true, "the long name may wrap")
    local ty = select(5, tall.label:GetPoint(1))
    local sy = select(5, short.label:GetPoint(1))
    T.truthy(ty - sy > 2 * DaylightUI.Style.SIZE.body, "the next row sits under both lines of the wrapped one: " .. tostring(ty - sy))
    T.rgb({ tall.value:GetTextColor() }, { 1, 0.3, 0.3 }, "the count keeps the line's own color")
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
    T.eq(tagWords(p.items[1]), "ELITE,NEUTRAL,HUMANOID")
    T.truthy(stub.Text(p.items[1].right):find("^40|c%x+%+|r$"), "an elite's level carries a gold +")
    T.rgb({ p.items[1].icon.edge:GetVertexColor() }, DaylightUI.Style.INK.MONEY, "an elite's face edged in gold")
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

-- Seen in game: after one fade out, the card came home stretched over the
-- tooltip and never pinned again, so every refill that changed the tooltip's
-- size showed on the card as a flicker, several times a second.
T.test("rich tooltip: after the ghost hands the card back it's pinned at its own size again", function()
    local _, Panel = login("rich")
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
    local function pinned(p, why)
        -- The fake game keeps SetAllPoints as one "ALL" point.
        T.eq(p:GetNumPoints(), 1, why .. ": one point")
        T.eq(p.__points[1][1], "TOPLEFT", why .. ": held by one corner, not stretched over the tooltip")
        T.eq(p.__points[1][2], tip, why .. ": on its tooltip")
        T.eq(p:GetWidth(), p.wantW, why .. ": at the card's own width")
    end
    up()
    local p = Panel.Get(tip)
    pinned(p, "first show")
    -- Faded out in full, then shown again.
    tip:Hide()
    tick(M.NORMAL * 2)
    up()
    pinned(p, "after a whole fade")
    -- Shown again while the ghost still holds it.
    tip:Hide()
    tick(M.NORMAL / 2)
    stub.Advance(0.1)
    fill(99, { "Mailbox", "Your mail." })
    update()
    pinned(p, "back in the middle of a fade")
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
local function withAddon(own, addon, kind, id)
    local tip = GameTooltip
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    local data = { type = kind or 99, lines = {}, id = id }
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
-- A profession's recipe as the game writes it on a spell's tooltip.
local RECOVERY = {
    { "Enchanting: Enchant Weapon - Recovery" },
    "Reagents:",
    "Soul Dust (6), Large Glimmering Shard (4), Pyrite (4)",
    { "Permanently enchant a Melee Weapon to trigger Recovery when you are Parried or Dodged.", nil, YELLOW },
    "Tools: Runed Silver Rod",
}

local function recipeWorld()
    spells()
    stub.SetItems({
        [20001] = { id = 20001, quality = 1, icon = 1001 },
        [20002] = { id = 20002, quality = 2, icon = 1002 },
        [20003] = { id = 20003, quality = 1, icon = 1003 },
        ["Runed Silver Rod"] = { id = 20010, quality = 1, icon = 1010 },
    })
    stub.bagCounts = {}
    C_Item.GetItemCount = function(id) return stub.bagCounts[id] or 0 end
    _G.C_TradeSkillUI = { GetRecipeSchematic = function(id)
        if id ~= 13890 then return { reagentSlotSchematics = {} } end
        local function slot(item, n) return { reagents = { { itemID = item } }, quantityRequired = n, required = true } end
        return { reagentSlotSchematics = { slot(20001, 6), slot(20002, 4), slot(20003, 4) } }
    end }
end

T.test("rich tooltip: a recipe's card lists its reagents with icons and counts, the profession as a tag", function()
    local _, Panel = login("rich")
    recipeWorld()
    fillSpell(13890, RECOVERY)
    update()
    local p = Panel.Get(GameTooltip)
    local head = kinds(p, "header")[1]
    T.eq(stub.Text(head.title), "Enchant Weapon - Recovery", "the profession leaves the title")
    T.eq(stub.Text(head.tags[1].text), "ENCHANTING")
    -- The description first, then the reagents under their heading.
    local order = {}
    for i = 1, p.count do order[#order + 1] = p.items[i].kind end
    local text, section = kinds(p, "text")[1], kinds(p, "section")[1]
    T.truthy(text and section, "a description and a heading")
    T.truthy(stub.Text(text.fs):find("^Permanently"), "the description")
    T.eq(stub.Text(section.fs), "REAGENTS")
    local rows = kinds(p, "row")
    T.eq(#rows, 4, "three reagents and a tool")
    T.eq(stub.Text(rows[1].label), "|T1001:0:0:0:0:64:64:5:59:5:59|t Soul Dust", "its icon from the recipe")
    T.eq(stub.Text(rows[1].value), "6")
    T.eq(stub.Text(rows[2].label), "|T1002:0:0:0:0:64:64:5:59:5:59|t Large Glimmering Shard")
    T.eq(stub.Text(rows[4].label), "|T1010:0:0:0:0:64:64:5:59:5:59|t Runed Silver Rod", "the tool")
    T.eq(stub.Text(rows[4].value), "Tool")
    -- None of the recipe's lines are read again as sentences or facts.
    T.eq(#kinds(p, "text"), 1, "only the description is a sentence")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.C_TradeSkillUI = nil
end)

T.test("rich tooltip: a recipe's reagents on the same line, and a short one in the bags", function()
    local _, Panel = login("rich")
    recipeWorld()
    stub.bagCounts[20001] = 2
    stub.bagCounts[20002] = 9
    fillSpell(13890, {
        { "Enchanting: Enchant Weapon - Recovery" },
        "Reagents: |nSoul Dust (6), Large Glimmering Shard (4), |cffff2020Pyrite|r (4)",
        { "Permanently enchant a Melee Weapon.", nil, YELLOW },
    })
    update()
    local p = Panel.Get(GameTooltip)
    local rows = kinds(p, "row")
    T.eq(#rows, 3)
    local hex = DaylightUI.Win.Parts.Hex
    local INK = DaylightUI.Style.INK
    T.eq(stub.Text(rows[1].value), hex(INK.BAD) .. "2|r" .. hex(INK.LABEL) .. " / |r6", "two of six in the bags")
    T.eq(stub.Text(rows[2].value), "4", "enough of it")
    T.eq(stub.Text(rows[3].label), "|T1003:0:0:0:0:64:64:5:59:5:59|t Pyrite", "the game's red code left out")
    local r, g = rows[3].value:GetTextColor()
    T.eq(r, INK.BAD[1], "none in the bags: red")
    T.eq(g, INK.BAD[2])
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.C_TradeSkillUI = nil
end)

T.test("rich tooltip: a spell that only looks like a recipe keeps its title", function()
    local _, Panel = login("rich")
    recipeWorld()
    fillSpell(116, { { "Frostbolt" }, { "Hurls a bolt of frost: it slows.", nil, YELLOW } })
    update()
    local p = Panel.Get(GameTooltip)
    T.eq(#kinds(p, "section"), 0)
    T.eq(stub.Text(kinds(p, "header")[1].title), "Frostbolt")
    _G.C_TradeSkillUI = nil
end)

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

T.test("other addons: a title over its own lines is a heading, a rule between addons", function()
    foreignLogin()
    local p = withAddon({ "Skinning Knife" }, function(t)
        t:AddDoubleLine("Inventory", "Total: 1")
        t:AddLine(" ")
        t:AddLine("|TInterface\\AddOns\\Some\\Icon:14:14|t |cffffd100Forever Leveling BiS|r")
        t:AddLine(" ")
        t:AddDoubleLine("Beast Mastery", "0.8")
        t:AddLine(" ")
        t:AddLine("Lonely gold line", 1, 0.82, 0)
    end)
    local kinds = {}
    for _, item in ipairs(afterRule(p)) do kinds[#kinds + 1] = item.kind end
    -- The last rule is the heading's: after it, its own lines.
    T.deq(kinds, { "section", "row", "gap", "text" })
    T.eq(stub.Text(afterRule(p)[1].fs), "FOREVER LEVELING BIS", "the title alone, as the card's own headings")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a white line or a label is never a heading", function()
    foreignLogin()
    local p = withAddon({ "Skinning Knife" }, function(t)
        t:AddLine("First addon")
        t:AddLine("Second line")
        t:AddLine(" ")
        t:AddLine("|cffffd100Recommendation:|r", 1, 0.82, 0)
        t:AddLine("Vendor")
    end)
    for _, item in ipairs(afterRule(p)) do T.truthy(item.kind ~= "section", "no heading") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: hints small, their key in the accent; Altar is no Alt", function()
    foreignLogin()
    local Style = DaylightUI.Style
    local p = withAddon({ "Skinning Knife" }, function(t)
        t:AddLine("Hold Ctrl for details", 0.6, 0.6, 0.6)
        t:AddLine("Alt-click: guide me", 0.6, 0.6, 0.6)
        t:AddLine("Altar of Storms")
    end)
    local area = afterRule(p)
    T.eq(#area, 3)
    local hex = hexOf({ Style.Accent() })
    T.eq(stub.Text(area[1].fs), "Hold " .. hex .. "Ctrl|r for details")
    T.eq(stub.Text(area[2].fs), hex .. "Alt-click:|r guide me")
    T.eq(area[1].fs.size, Style.SIZE.small, "small")
    T.eq(area[3].fs.size, Style.SIZE.body, "a place is a line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a row too wide for the card puts its right side under, never cut", function()
    foreignLogin()
    local p = withAddon({ "Skinning Knife" }, function(t)
        t:AddDoubleLine("-55.1 (-99%) Beast Mastery gain", "vs Grimlok's Charge of the Monkey")
        t:AddDoubleLine("Bags", "5")
    end)
    local area = afterRule(p)
    T.eq(#area, 3, "the words, the right side, the short row")
    T.eq(area[1].kind, "text")
    T.eq(stub.Text(area[1].fs), "-55.1 (-99%) Beast Mastery gain")
    T.eq(area[2].kind, "row")
    T.eq(stub.Text(area[2].value), "vs Grimlok's Charge of the Monkey")
    T.eq(stub.Text(area[3].label), "Bags")
    local shown = 0
    for i = 1, p.used.text do if p.pool.text[i]:IsShown() then shown = shown + 1 end end
    T.eq(shown, p.used.text, "no text left over from the undone row")
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
        -- Daylight UI's own coins (the Auction House's price lines).
        t:AddDoubleLine("Auction", W.Money(29400))
    end)
    local rows = {}
    for _, item in ipairs(afterRule(p)) do if item.kind == "row" then rows[#rows + 1] = item end end
    T.eq(#rows, 5)
    T.eq(stub.Text(rows[5].value), W.Money(29400), "Daylight UI's own coins kept")
    T.eq(stub.Text(rows[1].label), "Auction x5")
    T.eq(stub.Text(rows[1].value), W.Money(123400), "Auctionator's coins")
    T.eq(stub.Text(rows[2].label), "|cff82c5ffDBMarket|r", "the label in its own color, without its colon")
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

T.test("other addons: TSM's lettered coins after a percent become coins, the percent kept", function()
    foreignLogin()
    local W = DaylightUI.Widgets
    local p = withAddon({ "Peacebloom" }, function(t)
        t:AddDoubleLine("  Market Value", "[|cff00ff00+46%|r] 1|cffc7c7cfs|r 01|cffeda55fc|r")
        t:AddDoubleLine("  Region Avg", "[|cff00ff00+16%|r] |cffffffff52|r|cffeda55fc|r")
    end)
    local rows = {}
    for _, item in ipairs(afterRule(p)) do if item.kind == "row" then rows[#rows + 1] = item end end
    T.eq(#rows, 2)
    local v1, v2 = stub.Text(rows[1].value), stub.Text(rows[2].value)
    T.truthy(v1:find(W.Money(101), 1, true), "1s 01c as coins: " .. v1)
    T.truthy(v1:find("+46%", 1, true) and v1:find("cff00ff00", 1, true), "the percent and its color kept: " .. v1)
    T.falsy(v1:find("c7c7cfs", 1, true), "no letter left: " .. v1)
    T.truthy(v2:find(W.Money(52), 1, true), "52c as coins: " .. v2)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a color code ending in a digit stays whole beside coins", function()
    foreignLogin()
    local W = DaylightUI.Widgets
    local p = withAddon({ "Murloc Skin Bag" }, function(t)
        -- TSM paints its digits ecf4f3 and Disenchantry its counts ffd100: both
        -- end in a digit right before the price's own digits.
        t:AddDoubleLine("  Market Value", "[|cff00ff00+13%|r] |cffecf4f33|r|cffffd70ag|r |cffecf4f340|r|cffc7c7cfs|r |cffecf4f352|r|cffeda55fc|r")
        t:AddDoubleLine("Large Glimmering Shard", "1x 100% |cffffd10095|A:coin-silver:0:0|a|r")
    end)
    local rows = {}
    for _, item in ipairs(afterRule(p)) do if item.kind == "row" then rows[#rows + 1] = item end end
    T.eq(#rows, 2)
    local v1, v2 = stub.Text(rows[1].value), stub.Text(rows[2].value)
    T.truthy(v1:find(W.Money(34052), 1, true), "3g 40s 52c as coins: " .. v1)
    T.falsy(v1:find("|cffecf4f|", 1, true) or v1:find("cffecf4f3", 1, true), "no torn color code: " .. v1)
    T.eq(v2, "1x 100% |cffffd100" .. W.Money(9500) .. "|r", "95s as coins, the color code whole")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a price line keeps its own colored label", function()
    foreignLogin()
    local W = DaylightUI.Widgets
    local p = withAddon({ "Shimmering Trousers" }, function(t)
        t:AddDoubleLine("  Disenchant Value:", "6|cffc7c7cfs|r 21|cffeda55fc|r")
        t:AddDoubleLine("    |cff0070dd10% Small Glimmering Shard x0.1|r |cffffd100[1]|r", "55|cffeda55fc|r")
    end)
    local rows = {}
    for _, item in ipairs(afterRule(p)) do if item.kind == "row" then rows[#rows + 1] = item end end
    T.eq(#rows, 2)
    local l1 = stub.Text(rows[1].label)
    T.falsy(l1:find(":", 1, true), "the colon dropped: " .. l1)
    -- Too long beside its price: the words wrap on a line of their own above it.
    local words
    for _, item in ipairs(afterRule(p)) do
        if item.fs and stub.Text(item.fs):find("Glimmering", 1, true) then words = stub.Text(item.fs) end
    end
    T.truthy(words and words:find("cff0070dd", 1, true) and words:find("[1]", 1, true), "its quality color and count kept: " .. tostring(words))
    T.eq(stub.Text(rows[2].value), W.Money(55))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("other addons: a right side too long for the card wraps instead of running off it", function()
    foreignLogin()
    local zones = "Dun Morogh 60%, Mulgore 60%, Elwynn Forest 59%, Tirisfal Glades 45%, Teldrassil 26%, Darkshore 12%"
    local p = withAddon({ "Raw Brilliant Smallfish" }, function(t) t:AddDoubleLine(" ", zones) end)
    local found
    for _, item in ipairs(afterRule(p)) do
        if item.kind == "row" then T.falsy(stub.Text(item.value or item.label):find("Mulgore", 1, true), "never a row") end
        if item.kind == "text" and stub.Text(item.fs):find("Mulgore", 1, true) then found = item end
    end
    T.truthy(found, "a wrapped line")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a card text that once showed a secret draws plain text and coins again when reused", function()
    foreignLogin()
    local W = DaylightUI.Widgets
    local p = withAddon({ "Copper Ore" }, function(t) t:AddDoubleLine("Auction", W.Money(29400)) end)
    -- A unit's card wrote a secret into every pooled text (a name, health).
    for _, fs in ipairs(p.pool.text) do fs:SetText(stub.Secret("Hogger")) end
    withAddon({ "Tin Ore" }, function(t) t:AddDoubleLine("Auction", W.Money(29400)) end)
    local row = afterRule(p)[1]
    T.eq(row.kind, "row")
    T.falsy(row.value:HasAnySecretAspect(), "the price's text is plain again")
    T.eq(row.value:GetText(), W.Money(29400), "with its coins")
    T.falsy(issecretvalue(row.value:GetStringWidth()), "and can be measured")
    T.truthy(row.value.__font, "its font back on")
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
    DaylightUI:Set("Tooltip", "pieces.item.addons", false)
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
    -- Mixed in: the card's layout puts them with its words, before the foot.
    DaylightUI:Set("Tooltip", "pieces.item.addons", true)
    DaylightUI:Set("Tooltip", "layout.item", "numbers,stats|effects,set,facts,quote,addons|made|foot")
    stub.RunTimers()
    fillItem(GameTooltip, "greaves", GREAVES, function(t) t:AddLine("A note") end)
    update()
    local p2 = foreignPanel.Get(GameTooltip)
    T.eq(#afterRule(p2), 1, "no area of their own: only the foot after the last rule")
    local note
    for i = 1, p2.count do
        if p2.items[i].fs and stub.Text(p2.items[i].fs) == "A note" then note = i end
    end
    T.truthy(note and p2.items[note - 2].kind ~= "rule", "right after the card's own lines")
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

-- Seen by a player: a recipe's tags showed "Binds when picked up" twice, the
-- recipe's and the boots' it makes, with no telling which was which.
-- Seen in game: the game's SellPrice data line draws no text. It is stamped
-- with the line above it (lineIndex = NumLines before the coins), and its
-- post-call then adds the coins line. Read as landing on its stamp, the line
-- above (a ring's last stat, a level requirement) took the sell price's type
-- and vanished from the card.
T.test("rich tooltip: the line above the sell price stays on the card", function()
    local _, Panel = login("rich")
    items()
    _G.ITEM_SOULBOUND = "Soulbound"
    local list = { { "Jaina's Signet Ring", nil, { 0.118, 1, 0 } }, "Soulbound", "Finger", "+3 Strength",
        "+7 Stamina", "Requires Level 33", "Sell Price: 46|A:coin-silver:0:0|a 30|A:coin-copper:0:0|a" }
    local data = {
        { type = 22, leftText = "Jaina's Signet Ring", lineIndex = 1 },
        { type = 20, leftText = "Soulbound", lineIndex = 2 },
        { type = 21, leftText = "Finger", lineIndex = 3 },
        { type = 0, leftText = "+3 Strength", lineIndex = 4 },
        { type = 0, leftText = "+7 Stamina", lineIndex = 5 },
        { type = 0, leftText = "Requires Level 33", lineIndex = 6 },
        { type = 11, price = 4630, lineIndex = 6 },
    }
    fillItem(GameTooltip, "greaves", list, nil, nil, nil, data)
    local p = Panel.Get(GameTooltip)
    local words = {}
    for i = 2, p.count do
        local it = p.items[i]
        for _, fs in ipairs({ it.fs or false, it.label or false, it.value or false }) do
            if fs then words[#words + 1] = stub.Text(fs) end
        end
    end
    local all = table.concat(words, "|")
    T.truthy(all:find("Stamina", 1, true), "the last stat: " .. all)
    T.truthy(all:find("Requires Level 33", 1, true), "the level requirement: " .. all)
    T.truthy(all:find("46", 1, true), "the sell price still in the foot: " .. all)
    local Read = stub.tooltip.RichRead
    local _, lines = Read.Lines(GameTooltip, { lines = data })
    T.eq(lines[6].type, 0, "the requirement keeps its own type")
    T.eq(lines[7].type, 11, "the coins line is the sell price")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: a recipe keeps its own binding in its tags, the crafted item's goes with that item", function()
    local _, Panel = login("rich")
    items()
    _G.ITEM_BIND_ON_PICKUP, _G.INVTYPE_FEET = "Binds when picked up", "Feet"
    stub.items.pattern = { id = 4352, quality = 2, kind = "Recipe", sub = "Tailoring", icon = 134942, class = 9, subClass = 2 }
    fillItem(GameTooltip, "pattern", {
        { "Pattern: Shadow Boots", nil, { 0.12, 1, 0 } },
        "Binds when picked up",
        { "Use: Teaches you how to craft Shadow Boots.", nil, GREEN },
        "",
        { "Shadow Boots", nil, { 0.12, 1, 0 } },
        "Binds when picked up",
        { "Feet", "Cloth" },
        "23 Armor",
        "+4 Stamina",
        "Requires Level 12",
        "Bolt of Woolen Cloth (8), Fine Thread (2)",
        "Requires Tailoring (60)",
    })
    local p = Panel.Get(GameTooltip)
    local head = p.items[1]
    T.eq(tagWords(head), "RECIPE,TAILORING,BINDS WHEN PICKED UP", "the recipe's own tags, its binding once")
    local after = {}
    for i = 2, p.count do
        local it = p.items[i]
        local fs = it.fs or it.label
        if fs then after[#after + 1] = stub.Text(fs) end
    end
    local list = table.concat(after, "|")
    local at = function(word) return list:find(word, 1, true) end
    T.truthy(at("Teaches you"), "the recipe's own words: " .. list)
    T.truthy(at("Shadow Boots|BINDS WHEN PICKED UP"), "the boots' name, then what they bind as: " .. list)
    T.truthy(at("Teaches you") < at("Shadow Boots|"), "the boots after the recipe's words")
    T.truthy(at("Shadow Boots|") < at("Armor") and at("Armor") < at("Bolt of Woolen Cloth"),
        "their numbers and materials together under them: " .. list)
    T.truthy(at("Feet  Cloth"), "their slot a word of theirs, not a recipe tag")
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
    T.rgb({ head.tags[3].text:GetTextColor() }, RI.ARMOR_COLORS[4], "plate you can wear in its own color")
    -- Armor your class can't wear: the game paints its type red, and so does the tag.
    fillItem(GameTooltip, "greaves", { { "Dawnforged Greaves", nil, EPIC }, "Binds when equipped",
        { "Legs", "Plate", nil, { 1, 0.125, 0.125 } } })
    head = Panel.Get(GameTooltip).items[1]
    T.eq(stub.Text(head.tags[3].text), "PLATE")
    T.rgb({ head.tags[3].text:GetTextColor() }, DaylightUI.Style.INK.BAD, "armor you can't wear reads red")
    T.rgb({ head.tags[2].text:GetTextColor() }, RI.SLOT_ARMOR, "the slot keeps its color")
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
    T.eq(stub.Text(head.tags[2].text), "NIGHT ELF")
    T.rgb({ head.tags[2].text:GetTextColor() }, stub.tooltip.RichPlayers.FACTION_COLORS.Horde)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: Portraits off leaves the face and class icon off the cards", function()
    local _, Panel = login("rich")
    DaylightUI:Set("Tooltip", "portraits", false)
    stub.RunTimers()
    boar()
    local head = Panel.Get(hoverBoar()).items[1]
    T.isnil(head.icon, "no face on a creature's card")
    T.eq(stub.Text(head.title), "Ridgeback Boar", "the name still leads")
    player()
    hover("mouseover", { "Aelindra", "Level 60 Night Elf Mage" })
    head = Panel.Get(GameTooltip).items[1]
    T.isnil(head.icon, "no class icon on a player's card")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the fight pill is off unless picked, so a fight shows the card", function()
    stub.Load({ tooltip = true, before = function()
        world()
        _G.DaylightUIDB = { modules = { Tooltip = { style = "rich" } } }
    end })
    player()
    stub.units.mouseover = { name = "Ridgeback Boar", isPlayer = false, reaction = 2, health = 31, maxHealth = 100, level = 23 }
    stub.EnterCombat()
    hover("mouseover", { "Ridgeback Boar", "Level 23 Beast" })
    local pill = _G.DaylightUITooltipPill
    T.falsy(pill and pill:IsShown(), "no pill")
    T.isnil(stub.tooltip.Tooltip.Muted(GameTooltip))
    stub.LeaveCombat()
end)

-- The game refreshes a compare tooltip by clearing it and filling it again
-- (TooltipComparisonManager:SetItemTooltip), the changes after the post-calls.
T.test("rich tooltip: a refreshed compare tooltip keeps its lines muted and its changes", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    local shop = ShoppingTooltip1
    compare(shop, CHANGES)
    update()
    local p = Panel.Get(shop)
    local function check(what)
        local bad = {}
        for i = 1, shop:NumLines() do
            local fs = _G["ShoppingTooltip1TextLeft" .. i]
            if fs:GetAlpha() ~= 0 then bad[#bad + 1] = i .. ":" .. tostring(fs:GetText()) end
        end
        T.eq(table.concat(bad, ","), "", what .. " lines muted")
        T.eq(#kinds(p, "tags"), 2, what .. " chips")
    end
    check("first")
    -- The game's refresh: ClearLines, the item appended (post-calls), the changes, SetShown.
    local function refresh(hideFirst)
        if hideFirst then shop:Hide() end
        shop:ClearLines()
        shop:GetScript("OnTooltipCleared")(shop)
        for _, t in ipairs(LEGPLATES) do
            if type(t) == "table" then shop:AddDoubleLine(t[1], t[2]) else shop:AddLine(t) end
        end
        local data = { type = Enum.TooltipDataType.Item, hyperlink = "legplates", lines = { {}, {}, {}, {} } }
        for _, fn in ipairs(post.ALL or {}) do fn(shop, data) end
        for _, fn in ipairs(post[data.type] or {}) do fn(shop, data) end
        shop:AddLine(" ")
        shop:AddLine(ITEM_DELTA_DESCRIPTION, 1, 0.82, 0)
        for _, c in ipairs(CHANGES) do shop:AddLine(c) end
        shop:SetShown(true)
        update()
        shop:GetScript("OnUpdate")(shop, 0.02)
    end
    refresh(false)
    check("refresh")
    refresh(true)
    check("hidden and shown")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Forever Leveling BiS draws its upgrade arrow on a frame of its own laid over
-- the tooltip (a child frame, not a texture of the tooltip), pinned to one of
-- the game's lines. On the card that line sits elsewhere, so the arrow showed
-- in the middle of other rows (seen in game, next to an Auction price).
T.test("rich tooltip: another addon's frame over the tooltip is hidden under the card, one beside it stays", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "legplates", LEGPLATES)
    local p = Panel.Get(GameTooltip)
    T.truthy(p and p:IsShown(), "the card")
    local arrow = CreateFrame("Frame", nil, GameTooltip)
    arrow:SetAllPoints()
    arrow:CreateTexture(nil, "OVERLAY")
    local beside = CreateFrame("Frame", nil, GameTooltip)
    beside:SetSize(40, 40)
    beside:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 4, 0)
    -- Where the game would put them (the fake game lays nothing out).
    function GameTooltip:GetRect() return 100, 100, 200, 150 end
    function arrow:GetRect() return 100, 100, 200, 150 end
    function beside:GetRect() return 304, 210, 40, 40 end
    update()
    T.eq(arrow:GetAlpha(), 0, "the addon's arrow frame")
    T.eq(beside:GetAlpha(), 1, "a frame beside the tooltip is left")
    T.eq(GameTooltipStatusBar:GetAlpha(), 1, "the game's health bar is left to the card")
    GameTooltip:Hide()
    T.eq(arrow:GetAlpha(), 1, "back with the tooltip's own look")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A tag's outline is one pixel thick: between screen pixels its top or bottom
-- line is lost. The card moves with its tooltip after it's laid out (with the
-- cursor, as a padding grows it), so the tags go back on the pixel grid each
-- time it has moved (seen in game with tags missing an edge).
T.test("rich tooltip: header tags go back on whole pixels when the card moves", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "greaves", GREAVES)
    local p = Panel.Get(GameTooltip)
    local tag = p.tagSpots[1] and p.tagSpots[1][1]
    T.truthy(tag, "a header tag")
    local snap = DaylightUI.Pixel.Snap
    local left, top = 100, 500
    function p:GetLeft() return left end
    function p:GetTop() return top end
    local function onGrid(what)
        local _, _, _, x, y = tag:GetPoint(1)
        T.near(snap(p, left + x), left + x, 1e-6, what .. " left edge on a pixel")
        T.near(snap(p, top + y), top + y, 1e-6, what .. " top edge on a pixel")
    end
    update()
    onGrid("laid out")
    left, top = 211.37, 433.81
    update()
    onGrid("moved")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A price addon's long label (TSM's "Region Market Value Avg") put its price
-- on a second line under it. An item's card widens, as far as it may, to keep
-- the two side by side; a line too long even then still wraps.
T.test("rich tooltip: an item card widens to keep a long price label beside its price", function()
    local _, Panel = login("rich")
    items()
    local W = DaylightUI.Widgets
    fillItem(GameTooltip, "legplates", LEGPLATES, function(t)
        t:AddLine("TSM AuctionDB", 1, 0.82, 0)
        t:AddDoubleLine("  Region Market Value Avg", "[|cffff0000-3%|r] 9|cffc7c7cfs|r 68|cffeda55fc|r")
    end)
    update()
    local p = Panel.Get(GameTooltip)
    local row
    for i = 1, p.count do
        local it = p.items[i]
        if it.kind == "row" and stub.Text(it.label):find("Region Market", 1, true) then row = it end
    end
    T.truthy(row, "label and price on one row")
    T.truthy(stub.Text(row.value):find(W.Money(968), 1, true), "the price beside it")
    T.truthy(p.wantW > Panel.WIDTH.item, "the card wider than usual: " .. tostring(p.wantW))
    T.truthy(p.wantW <= math.floor(Panel.WIDTH.item * Panel.GROW), "never past its most")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ItemTree's block, as it writes it (captured in game): a blank line, its
-- verdict tag drawn as a picture with "ItemTree" on the right, a blank, an
-- optional "Changed in Forever" status with its badge, a blank, its reasons and
-- uses, then a key hint. The card reads the verdict from ItemTree's API and
-- draws the block as a section of its own with colored tags.
local ITEMTREE_LINES = {
    { "|TInterface\\AddOns\\ItemTree\\Art\\keep-tags:17:63:0:0:512:512:278:404:84:118:150:153:161|t", "ItemTree" },
    " ",
    "|TInterface\\AddOns\\ItemTree\\Art\\badge-changed:14:14|t Changed in Forever",
    " ",
    "Too weak for your level",
    "|TInterface\\Icons\\Trade_Mining:14:14|t Smelt Mithril",
    "Ctrl + right click or ALT-I for the full tree",
}

T.test("other addons: ItemTree's block is a section with its verdict as tags", function()
    foreignLogin()
    local Style = DaylightUI.Style
    _G.ItemTreeAPI = { version = 1, IsReady = function() return true end,
        GetItemFacts = function(id)
            if id == 4601 then return { keep = { tags = { "vendor", "auction" }, marked = false } } end
        end }
    local p = withAddon({ "Soft Banana Bread", "Use: Restores 1,338 health." }, function(t)
        t:AddLine(" ")
        for _, l in ipairs(ITEMTREE_LINES) do
            if type(l) == "table" then t:AddDoubleLine(l[1], l[2]) else t:AddLine(l) end
        end
    end, nil, 4601)
    local area = afterRule(p)
    T.eq(area[1].kind, "section", "a heading of its own")
    T.eq(stub.Text(area[1].fs), Style.Upper("ItemTree"))
    T.eq(area[2].kind, "tags", "the verdict as tags, not its picture")
    local tags = area[2].list
    T.eq(#tags, 3, "vendor, auction, and the status")
    T.eq(stub.Text(tags[1].text), Style.Upper("Vendor"))
    T.rgb(tags[1].text.__textColor, Style.INK.MONEY, "in gold")
    T.eq(stub.Text(tags[3].text), Style.Upper("Changed in Forever"), "its status")
    for _, item in ipairs(area) do
        local fs = item.fs or item.label
        local text = fs and stub.Text(fs) or ""
        T.falsy(text:find("keep-tags", 1, true), "ItemTree's tag picture is gone: " .. text)
        T.falsy(text:find("Changed in Forever", 1, true), "the status became a tag: " .. text)
    end
    local last = area[#area]
    T.truthy(stub.Text(last.fs):find("full tree", 1, true), "the hint is last")
    T.truthy(stub.Text(last.fs):find(DaylightUI.Win.Parts.Hex({ Style.Accent() }), 1, true), "its key in the accent")
    -- Without its API (an older ItemTree), its picture stays, still under the heading.
    _G.ItemTreeAPI = nil
    p = withAddon({ "Soft Banana Bread" }, function(t)
        t:AddLine(" ")
        for _, l in ipairs(ITEMTREE_LINES) do
            if type(l) == "table" then t:AddDoubleLine(l[1], l[2]) else t:AddLine(l) end
        end
    end, nil, 4601)
    area = afterRule(p)
    T.eq(area[1].kind, "section")
    T.truthy(stub.Text(area[2].fs or area[2].label):find("keep-tags", 1, true), "its own picture kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's loot window fills its row's tooltip again every frame (SetOwner,
-- then SetLootItem), after the tooltip's own update. Other addons add their
-- lines after the game's and call Show to fit them: those lines were drawn
-- over the card and never joined it (seen in game on loot and roll tooltips).
T.test("rich tooltip: lines another addon adds after the show join the card at its Show", function()
    local _, Panel = login("rich")
    items()
    local owner = CreateFrame("Button", nil, UIParent)
    local function check(what, rows)
        local bad = {}
        for i = 1, GameTooltip:NumLines() do
            for _, side in ipairs({ "Left", "Right" }) do
                local fs = _G["GameTooltipText" .. side .. i]
                if fs:GetText() and fs:GetAlpha() ~= 0 then bad[#bad + 1] = side .. i .. ":" .. tostring(fs:GetText()) end
            end
        end
        T.eq(table.concat(bad, ","), "", what .. ": the game's lines muted")
        T.eq(Panel.Get(GameTooltip).count, rows, what .. ": the card's rows")
    end
    local function lootFrame(hide, late)
        update()
        if hide and GameTooltip:IsShown() then GameTooltip:Hide() end
        fillItem(GameTooltip, "legplates", LEGPLATES, function(t) t:AddDoubleLine("AH price", "2s 99c") end)
        GameTooltip.__owner, GameTooltip.__anchor = owner, "ANCHOR_RIGHT"
        if late then
            GameTooltip:AddLine("Quest Drop Rate:")
            GameTooltip:AddDoubleLine("  ForeverDB (Buzzard):", "14%")
            GameTooltip:Show()
        end
    end
    lootFrame(false, false)
    local rows = Panel.Get(GameTooltip).count
    for _, hide in ipairs({ false, true }) do
        for k = 1, 3 do
            lootFrame(hide, true)
            check((hide and "hidden first, " or "") .. "frame " .. k, rows + 2)
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A hunter pet's tooltip says "Attack Speed 1.49s": a time, not 1 gold 49
-- silver. Coins never have one or two digits after a decimal mark; a
-- thousands mark always has three after it.
T.test("other addons: a time with a decimal stays a time, not coins", function()
    foreignLogin()
    local Foreign, W = stub.tooltip.RichForeign, DaylightUI.Widgets
    T.eq(Foreign.CopperOf("1.49s"), nil, "1.49s is seconds")
    T.eq(Foreign.CopperOf("2,5s"), nil, "a comma decimal too")
    T.eq(Foreign.Money("1.49s"), "1.49s")
    T.eq(Foreign.CopperOf("1,234g 5s"), 12340500, "a thousands mark is still coins")
    T.eq(Foreign.CopperOf("12g 34s"), 123400)
    T.eq(Foreign.Words("1.49s"), "1.49s")
    T.truthy(W)
end)

-- Volley "fires a volley of ammo ... causing 71 Arcane damage": the card
-- tagged it Fire, finding "fire" inside "fires".
T.test("rich spells: the school is a whole word, not part of one", function()
    login("rich")
    _G.STRING_SCHOOL_FIRE, _G.STRING_SCHOOL_ARCANE = "Fire", "Arcane"
    local Spells = stub.tooltip.RichSpells
    local s = Spells.School("Continuously fires a volley of ammo at the target area, causing 71 Arcane damage to enemy targets within 8 yards every 1 sec for 6 sec.")
    T.eq(s and s.key, "Arcane")
    T.eq(Spells.School("Fires a shot that has no school."), nil, "English never reads a school inside a word")
    local get = _G.GetLocale
    _G.GetLocale = function() return "deDE" end
    _G.STRING_SCHOOL_FIRE = "Feuer"
    local de = Spells.School("Verursacht 50 Feuerschaden.")
    _G.GetLocale, _G.STRING_SCHOOL_FIRE = get, "Fire"
    T.eq(de and de.key, "Fire", "German joins the school onto the damage word")
end)

-- The profession window's result icon fills the tooltip again from its own
-- OnUpdate every frame (Blizzard_ProfessionsRecipeSchematicForm: OnEnter sets
-- an OnUpdate that calls SetRecipeResultItem), anchored ANCHOR_RIGHT, so the
-- card is pinned by its bottom. Auction addons add their lines in the fill
-- and more after the game's Show, then Show again. Seen in game: their lines
-- stood over and above the card, never in it.
T.test("rich tooltip: a profession result refilled every frame keeps auction lines in the card", function()
    local _, Panel = login("rich")
    items()
    local icon = CreateFrame("Button", nil, UIParent)
    local function check(what, rows)
        local bad = {}
        for i = 1, GameTooltip:NumLines() do
            for _, side in ipairs({ "Left", "Right" }) do
                local fs = _G["GameTooltipText" .. side .. i]
                if fs:GetText() and fs:GetAlpha() ~= 0 then bad[#bad + 1] = side .. i .. ":" .. tostring(fs:GetText()) end
            end
        end
        T.eq(table.concat(bad, ","), "", what .. ": the game's lines muted")
        T.eq(Panel.Get(GameTooltip).count, rows, what .. ": the card's rows")
        local p = Panel.Get(GameTooltip)
        T.near(GameTooltip:GetHeight(), p.wantH * p:GetScale(), 0.01, what .. ": fitted to the card")
    end
    local function frame(first)
        if not first then update() end
        fillItem(GameTooltip, "legplates", LEGPLATES, function(t)
            t:AddDoubleLine("Auction", "6s 45c")
        end)
        GameTooltip.__owner, GameTooltip.__anchor = icon, "ANCHOR_RIGHT"
        GameTooltip:AddLine("TSM AuctionDB")
        GameTooltip:AddDoubleLine("  Min Buyout", "6s 45c")
        GameTooltip:AddDoubleLine("  Region Sale Avg", "3s 14c")
        GameTooltip:Show()
    end
    frame(true)
    local rows = Panel.Get(GameTooltip).count
    for k = 1, 3 do
        frame(false)
        check("frame " .. k, rows)
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

