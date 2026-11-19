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
    tip:SetScript("OnHide", function(self) self:ClearPadding() end)
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
    fill(Enum.TooltipDataType.Unit, { "Ridgeback Boar", "Level 23 Beast" }, function(t)
        GameTooltipTextLeft1:SetText(stub.Secret("Ridgeback Boar"))
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
    fill(Enum.TooltipDataType.Unit, { "Ridgeback Boar", "Level 23 Beast" })
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
    T.eq(stub.Text(head.tags[2].text), "60 · NIGHT ELF")
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
    stub.units.mouseover = { name = "Ridgeback Boar", isPlayer = false, reaction = 2, health = 31, maxHealth = 100 }
    stub.units.mouseovertarget = stub.units.player
    stub.EnterCombat()
    hover("mouseover", { "Ridgeback Boar", "Level 23 Beast" })
    local pill = _G.DaylightUITooltipPill
    T.truthy(pill and pill:IsShown(), "the pill shows")
    T.eq(pill:GetWidth(), 200)
    T.eq(GameTooltip:GetAlpha(), 0, "the tooltip itself out of sight")
    T.eq(Tip.Muted(GameTooltip), "pill")
    T.eq(stub.Text(pill.name), "Ridgeback Boar")
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
            class = 4, level = 66, dressable = true },
        legplates = { id = 19002, quality = 3, kind = "Armor", sub = "Plate", equip = "INVTYPE_LEGS", icon = 135001,
            class = 4, level = 58, dressable = true },
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
    T.eq(stub.Text(head.tags[2].text), "LEGS · PLATE")
    T.eq(stub.Text(head.tags[3].text), "BINDS WHEN EQUIPPED", "its binding a tag under its name, as the game puts it")
    T.truthy(p.washDown and p.wash[1]:IsShown(), "the quality washing down from the top")
    T.truthy(p.lightFade, "the light fades out along its right part")
    -- One column of numbers, number first at the left edge, as the game
    -- writes them: armor, then each stat in its color.
    local lines = kinds(p, "line")
    local Tip = stub.tooltip.Tooltip
    local hex = DaylightUI.Win.Parts.Hex
    T.eq(stub.Text(lines[1].fs), hex(DaylightUI.Style.INK.VALUE) .. "742|r Armor")
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

T.test("rich tooltip: a weapon's damage and speed as rows, a plain item's card", function()
    local _, Panel = login("rich")
    items()
    fillItem(GameTooltip, "sword", { { "Thunderforge Blade", nil, { 0, 0.44, 0.87 } }, { "One-Hand", "Sword" },
        { "41 - 77 Damage", "Speed 2.60" }, "(22.7 damage per second)", "+5 Agility" })
    local p = Panel.Get(GameTooltip)
    local said = {}
    for _, l in ipairs(kinds(p, "line")) do said[#said + 1] = stub.Text(l.fs):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    T.eq(said[1], "41 - 77 Damage", "number first")
    T.eq(said[2], "2.60 Speed")
    T.eq(said[3], "22.7 Damage per second")
    T.eq(stub.Text(p.items[1].tags[2].text), "ONE-HAND · SWORD", "the slot line's own word")
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
    T.eq(stub.Text(head.tags[2].text), "LEGS · PLATE")
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

-- Spells: the board's spell card, the math on Shift, the cooldown card on an
-- action button, and the frame alone in a fight. The game's own words
-- (GlobalStrings) and what C_Spell answers for the spells this test knows.
local WHITE_LINE, RANK_GRAY = { 1, 1, 1 }, { 0.5, 0.5, 0.5 }

local function spells()
    _G.MANA, _G.DAMAGE, _G.SHIFT_KEY_TEXT = "Mana", "Damage", "Shift"
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
    T.rgb({ head.tags[2].text:GetTextColor() }, INK.LABEL)
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
    local hint = stub.Text(kinds(p, "hints")[1].list[1])
    T.eq(hint, H(frost) .. "Shift|r the math", "Shift the math, the key in the school's color")
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

T.test("rich tooltip: Shift lays a spell out as the math, and back", function()
    local Tip, Panel = login("rich")
    spells()
    fillSpell(116, FROSTBOLT)
    local p = Panel.Get(GameTooltip)
    local INK = DaylightUI.Style.INK
    stub.shift = true
    update()
    T.eq(stub.Text(p.items[1].fs), "Frostbolt", "Name · the math")
    T.eq(stub.Text(p.items[1].tail), "· the math")
    local rows = kinds(p, "row")
    T.eq(stub.Text(rows[1].label), "Base")
    T.eq(stub.Text(rows[1].value), "412 to 448", "the description's range")
    local H = DaylightUI.Win.Parts.Hex
    -- Frostbolt's own share (its slow costs it), not the rule's 2.5 / 3.5.
    T.eq(stub.Text(rows[2].label), "Spell power " .. H(INK.OFF) .. "(81%)|r")
    T.eq(stub.Text(rows[2].value), "+33", "40 spell power at 81%")
    T.rgb({ rows[2].value:GetTextColor() }, INK.GOOD)
    local tiles = kinds(p, "tiles")[1].list
    T.eq(stub.Text(tiles[1].value), "185", "(430 + 33) over its 2.5 sec cast")
    T.eq(stub.Text(tiles[1].caption), "DAMAGE / SEC")
    T.rgb({ tiles[1].value:GetTextColor() }, Tip.SCHOOL_COLORS.Frost)
    T.eq(stub.Text(tiles[2].value), "3.9", "463 per 120 mana")
    T.eq(stub.Text(tiles[2].caption), "PER MANA")
    T.eq(stub.Text(rows[3].label), "Spell ID 116")
    T.eq(stub.Text(rows[3].value), "Frost · Bolt")
    T.rgb({ rows[3].label:GetTextColor() }, INK.OFF)
    T.eq(#kinds(p, "rule"), 2)
    stub.shift = false
    update()
    T.eq(p.items[1].kind, "header", "the card again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("rich tooltip: the spell power rule, and no number when it isn't known", function()
    login("rich")
    spells()
    local S = stub.tooltip.RichSpells
    local function shape(desc, castKind, castSecs)
        return S.Shape({ desc = { desc }, castKind = castKind, castSecs = castSecs })
    end
    local dot = shape("Corrupts the target, causing 40 Shadow damage over 12 sec.", "instant")
    T.eq(dot.kind, "over")
    T.near(S.Coefficient(nil, dot), 12 / 15, 1e-9, "over time: its duration over 15")
    local aoe = shape("Causes 34 to 38 Arcane damage to all enemies within 10 yards.", "instant")
    T.truthy(aoe.area)
    T.near(S.Coefficient(nil, aoe, 0), 1.5 / 3.5 * 0.5, 1e-9, "an instant area spell: the GCD's share, halved")
    local slow = shape("Hurls a fiery ball for 600 to 700 Fire damage.", "cast", 6)
    T.near(S.Coefficient(nil, slow, 6), 1, 1e-9, "never more than all of it")
    local hybrid = shape("Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec.", "cast", 2)
    T.eq(hybrid.kind, "hybrid")
    T.isnil(S.Coefficient(nil, hybrid, 2), "a hit and a burn: not known without its own number")
    local heal = shape("Heals the target of 45 damage over 15 sec.", "instant")
    T.truthy(heal.heal, "a heal, though the game calls it damage")
    local channel = shape("Causes 26 Arcane damage each second for 3 sec.", "channeled")
    T.eq(channel.kind, "channel")
    T.eq(channel.ticks, 3)
    T.near(S.Coefficient(nil, channel), 3 / 3.5, 1e-9)
    -- Another language: the base alone.
    local was = DaylightUI.LOCALE
    DaylightUI.LOCALE = "deDE"
    local de = shape("Verursacht 40 Schattenschaden im Verlauf von 12 Sek.", "instant")
    T.isnil(de and S.Coefficient(nil, de), "words it can't read: no spell power number")
    DaylightUI.LOCALE = was
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

T.test("rich tooltip: in a fight a spell is the frame around the game's lines, painted as before, no math", function()
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
    T.eq(p.count, 0, "no pieces, no math")
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

T.test("rich tooltip: an aura and a macro's spell get the card, no math; an item macro the plain one", function()
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
    T.eq(#kinds(p, "hints"), 0, "no math for an aura")
    -- A macro casting Frostbolt: its lines carry the spell's line types.
    stub.ActionSlots({ [7] = { macro = 3, texture = 135846 } })
    fillSpell(3, FROSTBOLT, Enum.TooltipDataType.Macro, actionButton(7), { { type = 13 }, {}, {}, { type = 34 } })
    update()
    T.eq(p.kind, "spell")
    T.eq(p.items[1].icon.art:GetTexture(), 135846, "the icon from its action slot")
    T.eq(#kinds(p, "hints"), 0, "its id is the macro's: no math")
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
    T.rgb({ head.tags[2].text:GetTextColor() }, DaylightUI.Style.INK.LABEL, "what it is, tan")
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
    T.eq(#head.tags, 4)
    T.eq(stub.Text(head.tags[3].text), "BINDS WHEN PICKED UP")
    T.eq(stub.Text(head.tags[4].text), "UNIQUE")
    T.eq(head.tags[1].row, 1)
    T.truthy(head.tags[4].row > 1, "the last ones on another row")
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
