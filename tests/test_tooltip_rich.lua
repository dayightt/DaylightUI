local stub = require("stub")

-- The rich tooltip: Daylight UI's own card over the game's muted tooltip, the
-- game's tooltip padded to the card's size, and the frame alone when a line
-- is secret.

local post = {}

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
    tip.__n = 0
    local function line(side, i)
        local key = "GameTooltipText" .. side .. i
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
    function tip:GetUnit() return self.__unitName, self.__unit end
    function tip:GetItem() return nil, self.__link end
    function tip:SetOwner(owner, anchor)
        self.__owner, self.__anchor = owner, anchor
        self:ClearLines()
        local cleared = self:GetScript("OnTooltipCleared")
        if cleared then cleared(self) end
    end
    function tip:GetOwner() return self.__owner end
    function tip:GetAnchorType() return self.__anchor end
    -- As the game's GameTooltip_OnShow / OnHide: the padding is cleared
    -- (GameTooltip_CalculatePadding with no embedded item, ClearPadding).
    tip:SetScript("OnShow", function(self) self:ClearPadding() end)
    tip:SetScript("OnHide", function(self) self:ClearPadding() end)
    stub.TooltipSizes(tip)
    tip:Hide() -- as the game's, hidden until first filled
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
    T.eq(p.__points[1][1], "ALL", "laid over the whole tooltip")
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
    fill(Enum.TooltipDataType.Item, { "Linen Cloth", "Trade Goods" })
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
    T.near(({ pill.name:GetTextColor() })[1], DaylightUI.Style.INK.WARN[1], 1e-6, "on you: its name orange")
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
    stub.units.mouseover = { name = "Southsea Pirate", isPlayer = false, reaction = 2, health = 50, maxHealth = 100 }
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
