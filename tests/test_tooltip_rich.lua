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
    T.near(GameTooltip:GetWidth(), p.wantW, 0.01, "as wide as the card")
    T.near(GameTooltip:GetHeight(), p.wantH, 0.01, "as tall")
    -- Long lines: the game's would be wider than the card, so its padding
    -- goes below zero and it shrinks to the card.
    fill(Enum.TooltipDataType.Spell, { "Arcane Missiles", string.rep("A very long line of words. ", 4) })
    update()
    T.near(GameTooltip:GetWidth(), p.wantW, 0.01, "still the card's width")
    T.near(GameTooltip:GetHeight(), p.wantH, 0.01)
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
    T.near(GameTooltip:GetHeight(), p.wantH, 0.01, "and fitted again")
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
