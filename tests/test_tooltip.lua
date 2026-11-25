local stub = require("stub")

-- The tooltips: our look over the game's frame, class and quality colors,
-- the health bar, and the cursor option.

local post, pre = {}, {}

local function world()
    post, pre = {}, {}
    Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }
    _G.TooltipDataProcessor = {
        AllTypes = "ALL",
        AddTooltipPreCall = function(kind, fn)
            pre[kind] = pre[kind] or {}
            table.insert(pre[kind], fn)
        end,
        AddTooltipPostCall = function(kind, fn)
            post[kind] = post[kind] or {}
            table.insert(post[kind], fn)
        end,
    }
    local function newTip(name)
        local tip = CreateFrame("GameTooltip", name, UIParent)
        tip.NineSlice = CreateFrame("Frame", nil, tip)
        tip:SetFrameLevel(0)
        CreateFrame("Frame", nil, tip) -- stand-in for the lines' parent
        local first = tip:CreateFontString(name .. "TextLeft1")
        _G[name .. "TextLeft1"] = first
        function tip:GetUnit() return self.__unitName, self.__unit end
        function tip:GetItem() return self.__itemName, self.__link end
        -- As the client's: a new owner clears the tooltip (OnTooltipCleared).
        function tip:SetOwner(owner, anchor)
            self.__owner, self.__anchor, self.default = owner, anchor, nil
            local cleared = self:GetScript("OnTooltipCleared")
            if cleared then cleared(self) end
        end
        function tip:GetOwner() return self.__owner end
        function tip:GetAnchorType() return self.__anchor end
        function tip:FadeOut() self.__fading = true end
        return tip
    end
    newTip("GameTooltip")
    newTip("ItemRefTooltip")
    -- As the game's (ItemRef.xml): UIPanelCloseButtonNoScripts, its art the game's own.
    ItemRefTooltip.CloseButton = CreateFrame("Button", nil, ItemRefTooltip)
    do
        local close = ItemRefTooltip.CloseButton
        close.__art = close:CreateTexture()
        function close:GetNormalTexture() return self.__art end
    end
    local bar = CreateFrame("StatusBar", "GameTooltipStatusBar", GameTooltip)
    function bar:SetStatusBarColor(r, g, b) self.__color = { r, g, b } end
    for _, n in ipairs({ "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }) do
        local f = stub.NewWidget("Font", n)
        function f:SetFont(file, size, flags) self.__font = { file, size, flags } end
    end
    -- As the game's: its default spot is a corner of its Edit Mode container.
    local spot = CreateFrame("Frame", "GameTooltipDefaultContainer", UIParent)
    spot:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100)
    _G.GameTooltip_SetDefaultAnchor = function(tip, parent)
        tip:SetOwner(parent, "ANCHOR_NONE")
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOMRIGHT", spot)
    end
    _G.GetCursorPosition = function() return 300, 200 end
    C_Item.GetItemQualityByID = function(link) return stub.qualities and stub.qualities[link] end
    C_Item.GetItemQualityColor = function(q) return 0.1 * q, 0.2, 0.3 end
    stub.units = {
        player = { name = "Me", class = "PRIEST", isPlayer = true },
        mouseover = { name = "Jaina", class = "MAGE", isPlayer = true },
        wolf = { name = "Wolf", isPlayer = false, reaction = 2 },
    }
    _G.UnitReaction = function(u) local x = stub.units[u]; return x and x.reaction end
end

local function login(before)
    stub.Load({ tooltip = true, before = function()
        world()
        -- A new profile starts in Rich. These tests are about the Simple look.
        _G.DaylightUIDB = { modules = { Tooltip = { style = "simple" } } }
        if before then before() end
    end })
    return stub.tooltip.Tooltip
end

-- The game filling a tooltip: cleared, then the data's post-calls.
local function show(tip, kind, set)
    local clear = tip:GetScript("OnTooltipCleared")
    if clear then clear(tip) end
    set(tip)
    for _, fn in ipairs(post.ALL or {}) do fn(tip, { type = kind }) end
    for _, fn in ipairs(post[kind] or {}) do fn(tip, { type = kind }) end
    local onShow = tip:GetScript("OnShow")
    if onShow then onShow(tip) end
end

T.test("tooltip: the game's art is hidden under our shell, behind the text", function()
    local Tip = login()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local s = Tip.Shell(GameTooltip)
    T.truthy(s, "skinned at login")
    T.eq(GameTooltip.NineSlice:GetAlpha(), 0, "the game's art out of sight")
    -- No hooks on the game's tooltip or its art: the game's own calls to a
    -- hooked method of it failed ("attempt to call a nil value", on every
    -- mouseover). Script hooks and events only.
    for _, m in ipairs({ "SetPoint", "SetAlpha", "Show" }) do
        T.isnil(rawget(GameTooltip, m), "no hook on GameTooltip:" .. m)
    end
    -- These two are the fake game's own (this file's), not a hook's wrapper.
    for _, m in ipairs({ "SetOwner", "FadeOut" }) do
        T.truthy(debug.getinfo(GameTooltip[m], "S").short_src:find("test_tooltip"), "no hook on GameTooltip:" .. m)
    end
    T.isnil(rawget(GameTooltip.NineSlice, "SetAlpha"), "or on its art")
    GameTooltip:Show()
    GameTooltip.NineSlice:SetAlpha(1)
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq(GameTooltip.NineSlice:GetAlpha(), 0, "and kept out when the game brings it back, before it's drawn")
    T.truthy(s:GetFrameLevel() < GameTooltip:GetFrameLevel(), "the shell under the text")
    T.truthy(Tip.Shell(ItemRefTooltip), "linked items too")
end)

-- A quick fade in (Motion.FAST) as it shows; never in combat (fight info
-- never waits), never with General's Motion off, never over a muted one.
T.test("tooltip: fades in quickly as it shows, at once in combat or with motion off", function()
    login()
    local M = DaylightUI.Motion
    local function tick(dt)
        local d = M.Driver()
        if d then stub.RunOnUpdate(d, dt) end
    end
    local tip = GameTooltip
    tip:Hide()
    stub.Advance(0.02)
    -- As the game: shown (OnShow), filled, then the fill's own Show, which
    -- puts the alpha back to 1 (the client's): the fade must hold on.
    tip:Show()
    T.eq(tip:GetAlpha(), 0, "starts clear")
    tip:Show()
    tick(0.01)
    T.truthy(tip:GetAlpha() < 0.5, "the fill's Show doesn't end the fade")
    tip:GetScript("OnUpdate")(tip, 0.01)
    T.truthy(tip:GetAlpha() < 0.5, "nor does a Show inside the tooltip's own update")
    tick(M.NORMAL / 6)
    T.truthy(tip:GetAlpha() > 0 and tip:GetAlpha() < 0.35, "a soft start, not half on at once")
    tick(M.NORMAL)
    T.eq(tip:GetAlpha(), 1, "there after NORMAL")
    stub.combat = true
    show(tip, Enum.TooltipDataType.Item, function() end)
    T.eq(tip:GetAlpha(), 1, "in combat: there at once")
    stub.combat = false
    DaylightUI.DB.General().motion = false
    show(tip, Enum.TooltipDataType.Item, function() end)
    T.eq(tip:GetAlpha(), 1, "motion off: there at once")
    DaylightUI.DB.General().motion = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- An owner's UpdateTooltip, every 0.2 s from the game's GameTooltip_OnUpdate:
-- some hide the tooltip first and fill it again (DialogueUI's reward items
-- with its Use Blizzard Tooltip option). Hidden and shown in one frame is
-- nothing on the screen: a fade from clear each time was a flicker.
T.test("tooltip: hidden and shown again in one frame doesn't fade again", function()
    login()
    local M = DaylightUI.Motion
    local function tick(dt)
        local d = M.Driver()
        if d then stub.RunOnUpdate(d, dt) end
    end
    local tip = GameTooltip
    local function refill()
        tip:Hide()
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:Show()
    end
    stub.Advance(1)
    tip:Hide()
    stub.Advance(1)
    tip:Show()
    T.eq(tip:GetAlpha(), 0, "a real show fades in")
    tick(M.NORMAL / 2)
    local partway = tip:GetAlpha()
    T.truthy(partway > 0 and partway < 1, "partway")
    stub.Advance(M.NORMAL / 2)
    refill()
    T.eq(tip:GetAlpha(), partway, "a refill mid-fade carries on from where it was")
    tick(M.NORMAL)
    T.eq(tip:GetAlpha(), 1, "and finishes")
    stub.Advance(0.2)
    refill()
    T.eq(tip:GetAlpha(), 1, "a refill leaves it on the screen")
    tick(0.02)
    T.eq(tip:GetAlpha(), 1, "and starts no fade")
    stub.Advance(1)
    tip:Hide()
    stub.Advance(0.02)
    tip:Show()
    T.eq(tip:GetAlpha(), 0, "really gone for a frame: it fades in again")
    tick(M.NORMAL)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: any other tooltip is skinned the first time it's filled", function()
    local Tip = login()
    local other = CreateFrame("GameTooltip", "SomeAddonTooltip", UIParent)
    other.NineSlice = CreateFrame("Frame", nil, other)
    function other:GetUnit() end
    show(other, Enum.TooltipDataType.Spell, function() end)
    T.truthy(Tip.Shell(other))
end)

T.test("tooltip: the flat box keeps its own thickness on the global style, or the one set", function()
    local Tip = login()
    local Style = DaylightUI.Style
    T.eq(Style.BorderPx(GameTooltip), 3, "a thin edge out of the box")
    DaylightUI:Set("Tooltip", "frameStyle.global", false)
    DaylightUI:Set("Tooltip", "frameStyle.borderPx", 5)
    stub.RunTimers()
    T.eq(Style.BorderPx(GameTooltip), 5, "its own thickness")
    DaylightUI:Set("general", "borderPx", 10)
    DaylightUI:Set("Tooltip", "frameStyle.global", true)
    stub.RunTimers()
    T.eq(Style.BorderPx(GameTooltip), 3, "a thick General border would fill the flat box with color")
    T.eq(Tip.BackAlpha(), 0.92, "and a background a little more solid than the windows'")
end)

T.test("tooltip: our font on the game's tooltip fonts, sized by the option", function()
    login()
    T.eq(GameTooltipText.__font[2], 12, "Simple keeps the size it always had")
    T.eq(GameTooltipHeaderText.__font[2], 14, "titles a little larger")
    DaylightUI:Set("Tooltip", "textSize", 16)
    stub.RunTimers()
    T.eq(GameTooltipText.__font[2], 16)
    T.eq(GameTooltipText.__font[1], DaylightUI.Style.FONT)
end)

-- A font other than the one General uses, to tell a part's own pick apart.
local function otherFont()
    local Style = DaylightUI.Style
    for _, key in ipairs(Style.FONT_ORDER) do
        local file = Style.FontFileOf(key)
        if file ~= Style.FONT then return key, file end
    end
end

T.test("tooltip: titles, text and small text each take their own size and font", function()
    login()
    local Style = DaylightUI.Style
    T.eq(GameTooltipTextSmall.__font[2], 11, "small text a little smaller")
    DaylightUI:Set("Tooltip", "titleSize", 20)
    DaylightUI:Set("Tooltip", "smallSize", 9)
    stub.RunTimers()
    T.eq(GameTooltipHeaderText.__font[2], 20)
    T.eq(GameTooltipTextSmall.__font[2], 9)
    T.eq(GameTooltipText.__font[2], 12, "the text keeps its size")
    DaylightUI:Set("Tooltip", "textSize", 16)
    stub.RunTimers()
    T.eq(GameTooltipHeaderText.__font[2], 20, "a title of its own doesn't follow the text")

    local key, file = otherFont()
    DaylightUI:Set("Tooltip", "media.titleFont", key)
    stub.RunTimers()
    T.eq(GameTooltipHeaderText.__font[1], file)
    T.eq(GameTooltipText.__font[1], Style.FONT, "the text keeps the tooltip font")
    DaylightUI:Set("Tooltip", "media.titleFont", "general")
    DaylightUI:Set("Tooltip", "media.font", key)
    stub.RunTimers()
    T.eq(GameTooltipTextSmall.__font[1], file, "small text follows the tooltip font")
    T.eq(GameTooltipHeaderText.__font[1], file, "so do titles")
end)

T.test("tooltip: a changed text size keeps its titles and small text where they were", function()
    login()
    local up = stub.tooltip.UpgradeSizes
    local p = { modules = { Tooltip = { textSize = 16 } } }
    up(p)
    T.eq(p.modules.Tooltip.titleSize, 18)
    T.eq(p.modules.Tooltip.smallSize, 15)
    p.modules.Tooltip.textSize = 10
    up(p)
    T.eq(p.modules.Tooltip.titleSize, 18, "only once")
    local fresh = { modules = { Tooltip = {} } }
    up(fresh)
    T.isnil(fresh.modules.Tooltip.titleSize, "an untouched profile keeps the defaults")
    fresh.modules.Tooltip.textSize = 16
    up(fresh)
    T.isnil(fresh.modules.Tooltip.titleSize, "a text size changed later leaves the titles alone")
end)

T.test("tooltip: a clicked link's X sits on the rich card's corner, not the tooltip's", function()
    login()
    local close = ItemRefTooltip.CloseButton
    local card = stub.tooltip.RichPanel.For(ItemRefTooltip)
    ItemRefTooltip:Show()
    ItemRefTooltip:GetScript("OnShow")(ItemRefTooltip)
    -- The card is filled and shown after the tooltip shows; the next frame sees it.
    card:Show()
    stub.RunTimers()
    local point, rel, relPoint, x, y = close:GetPoint(1)
    T.eq(point, "TOPRIGHT")
    T.eq(rel, card, "anchored to the card")
    T.eq(x, DaylightUI.Win.CLOSE_X, "the windows' X spot")
    T.eq(y, DaylightUI.Win.CloseY(true))
    -- Simple style, or a link the card doesn't draw: the card is hidden, with the
    -- size of the last link, so the X stays on the tooltip.
    card:Hide()
    ItemRefTooltip:GetScript("OnShow")(ItemRefTooltip)
    stub.RunTimers()
    T.eq(select(2, close:GetPoint(1)), ItemRefTooltip, "a hidden card is left alone")
end)

T.test("tooltip: a second link clicked with the tooltip open moves the X with the card", function()
    login()
    local close = ItemRefTooltip.CloseButton
    local card = stub.tooltip.RichPanel.For(ItemRefTooltip)
    ItemRefTooltip:Show()
    -- The game refills a shown tooltip for the next link and doesn't show it
    -- again: only the card comes and goes, so the X follows the card.
    card:Show()
    T.eq(select(2, close:GetPoint(1)), card, "a link with a card: the X is on the card")
    card:Hide()
    T.eq(select(2, close:GetPoint(1)), ItemRefTooltip, "the next link has none: the X is back on the tooltip")
    card:Show()
    T.eq(select(2, close:GetPoint(1)), card, "and a link with a card again: on the card")
    local _, _, _, x, y = close:GetPoint(1)
    T.eq(x, DaylightUI.Win.CLOSE_X, "the windows' X spot")
    T.eq(y, DaylightUI.Win.CloseY(true))
end)

T.test("tooltip: a rich card's title and small lines take their own size and font", function()
    login()
    local Panel = stub.tooltip.RichPanel
    local Style = DaylightUI.Style
    local p = Panel.For(GameTooltip)
    local function build()
        Panel.Begin(p, "other")
        Panel.Header(p, { title = "Thunderfury", sub = "Blessed Blade" })
        Panel.Text(p, "Some words", nil, Style.SIZE.body)
        Panel.Finish(p)
        return p.items[1].title, p.items[1].sub, p.items[2].fs
    end
    local title, sub, body = build()
    T.eq(title.size, Style.SIZE.title, "the defaults draw the card as it was")
    T.eq(sub.size, Style.SIZE.small)
    DaylightUI:Set("Tooltip", "titleSize", 28)
    DaylightUI:Set("Tooltip", "smallSize", 22)
    local key, file = otherFont()
    DaylightUI:Set("Tooltip", "media.titleFont", key)
    stub.RunTimers()
    title, sub, body = build()
    T.near(title.size, Style.SIZE.title * 2)
    T.near(sub.size, Style.SIZE.small * 2)
    T.eq(body.size, Style.SIZE.body)
    T.eq(title.__font[1], file)
    T.eq(body.__font[1], Style.FONT)
end)

-- A repaint also comes from a screen or UI scale change (an alt-tab can bring
-- one). With nothing about the tooltip changed, the game's own tooltip fonts,
-- its health bar and the tooltips' scale are left as they are.
T.test("tooltip: a repaint that changed nothing leaves the game's tooltip pieces alone", function()
    login()
    local writes = 0
    local function count(obj, method)
        local real = obj[method]
        obj[method] = function(...) writes = writes + 1 return real(...) end
    end
    count(GameTooltipText, "SetFont"); count(GameTooltipText, "SetShadowOffset")
    count(GameTooltipStatusBar, "ClearAllPoints"); count(GameTooltip, "SetScale")
    DaylightUI.NotifyStyleChanged()
    stub.RunTimers()
    T.eq(writes, 0, "nothing set again")
    DaylightUI:Set("Tooltip", "textSize", 15)
    stub.RunTimers()
    T.eq(GameTooltipText.__font[2], 15, "a real change still goes on")
end)

T.test("tooltip: a player's name, border and health bar take their class color", function()
    local Tip = login()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unitName, t.__unit = "Jaina", "mouseover" end)
    local r, g, b = DaylightUI.Style.ClassColor("MAGE")
    local c = GameTooltipTextLeft1.__textColor
    T.near(c[1], r); T.near(c[2], g); T.near(c[3], b)
    T.near(GameTooltipStatusBar.__color[1], r, 1e-6, "health bar")
    local s = Tip.Shell(GameTooltip)
    local tint = s.opts.bandColor or s.opts.borderColor
    T.near(tint[1], r, 1e-6, "border tinted")
    -- The next tooltip starts plain again.
    show(GameTooltip, Enum.TooltipDataType.Spell, function(t) t.__unit = nil end)
    T.isnil(s.opts.bandColor); T.isnil(s.opts.borderColor)
end)

T.test("tooltip: a player whose class the game hides (battlegrounds): class name and bar", function()
    local Tip = login()
    stub.units.mouseover.classHidden = true
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unitName, t.__unit = "Jaina", "mouseover" end)
    local c = GameTooltipTextLeft1.__textColor
    T.truthy(issecretvalue(c[1]), "the client's class color")
    T.eq(c[1].__value, RAID_CLASS_COLORS.MAGE.r)
    local mage = Tip.classLayers and Tip.classLayers.MAGE
    T.truthy(mage and mage:IsShown(), "the bar's class layers")
    T.eq(mage.__cell.__value, 8)
    -- the next tooltip: gone again
    stub.units.mouseover.classHidden = nil
    show(GameTooltip, Enum.TooltipDataType.Spell, function(t) t.__unit = nil end)
    T.falsy(mage:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: creatures take their reaction's color", function()
    login()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "wolf" end)
    local r = DaylightUI.Style.ReactionColor(2)
    T.near(GameTooltipTextLeft1.__textColor[1], r)
end)

T.test("tooltip: a secret unit is left alone", function()
    local Tip = login()
    GameTooltipTextLeft1.__textColor = nil
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = stub.Secret("mouseover") end)
    T.isnil(GameTooltipTextLeft1.__textColor)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: class colors can be turned off; the health bar still colors", function()
    login()
    DaylightUI:Set("Tooltip", "classColors", false)
    stub.RunTimers()
    GameTooltipTextLeft1.__textColor = nil
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.isnil(GameTooltipTextLeft1.__textColor)
    T.truthy(GameTooltipStatusBar.__color)
end)

T.test("tooltip: the game recoloring the health bar keeps ours", function()
    login()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    local ours = GameTooltipStatusBar.__color[1]
    GameTooltipStatusBar:SetStatusBarColor(0, 1, 0)   -- the game's health color, as the value changes
    GameTooltipStatusBar:GetScript("OnValueChanged")(GameTooltipStatusBar)
    T.near(GameTooltipStatusBar.__color[1], ours)
end)

T.test("tooltip: the border takes the class gradient when set to, and is plain again after", function()
    local Tip = login()
    local s = Tip.Shell(GameTooltip)
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.isnil(s.opts.borderPair, "one color by default")
    DaylightUI:Set("Tooltip", "borderGradient", true)
    stub.RunTimers()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    local lo, hi = DaylightUI.Gradients.PaintRGB("MAGE")
    local top = s.border.TOP.__gradient
    T.truthy(top, "the top edge sweeps")
    T.near(top[2].r, lo[1], 1e-6); T.near(top[3].r, hi[1], 1e-6)
    show(GameTooltip, Enum.TooltipDataType.Spell, function(t) t.__unit = nil end)
    T.isnil(s.opts.borderPair, "the next tooltip starts plain")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: the health bar takes the class gradient when set to, and keeps it as health changes", function()
    login()
    local tex = GameTooltipStatusBar:GetStatusBarTexture()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.falsy(tex.__gradient, "flat: the unit frames (not loaded here) use no gradient")
    DaylightUI:Set("Tooltip", "barGradient", "gradient")
    stub.RunTimers()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    local lo = DaylightUI.Gradients.Colors("MAGE")
    T.near(tex.__gradient[2].r, lo.r, 1e-6, "the mage pair")
    tex.__gradient = nil
    GameTooltipStatusBar:GetScript("OnValueChanged")(GameTooltipStatusBar)
    T.truthy(tex.__gradient, "put back after the game recolors it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: the health bar in a custom gradient keeps every color as health changes", function()
    login()
    local S = DaylightUI.Style
    local tex = GameTooltipStatusBar:GetStatusBarTexture()
    DaylightUI:Set("Tooltip", "barGradient", "customGradient")
    stub.RunTimers()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.eq(#S.FillStops(tex), 3, "three colors by default")
    GameTooltipStatusBar:GetScript("OnValueChanged")(GameTooltipStatusBar)
    T.eq(#S.FillStops(tex), 3, "still every color after the game recolors it")
    DaylightUI:Set("Tooltip", "barGradient", "flat")
    stub.RunTimers()
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.isnil(S.FillStops(tex), "flat again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: items of uncommon quality and up get a border in their color", function()
    local Tip = login(function() stub.qualities = { rare = 3, common = 1 } end)
    local s = Tip.Shell(GameTooltip)
    show(GameTooltip, Enum.TooltipDataType.Item, function(t) t.__link = "rare" end)
    local tint = s.opts.bandColor or s.opts.borderColor
    T.near(tint[1], 0.3, 1e-6, "rare's color")
    show(GameTooltip, Enum.TooltipDataType.Item, function(t) t.__link = "common" end)
    T.isnil(s.opts.bandColor); T.isnil(s.opts.borderColor)
    DaylightUI:Set("Tooltip", "qualityBorder", false)
    stub.RunTimers()
    show(GameTooltip, Enum.TooltipDataType.Item, function(t) t.__link = "rare" end)
    T.isnil(s.opts.bandColor, "option off")
end)

T.test("tooltip: the health bar sits under the tooltip and can be hidden", function()
    login()
    local p = { GameTooltipStatusBar:GetPoint(1) }
    T.eq(p[2], GameTooltip); T.eq(p[3], "BOTTOMLEFT")
    T.eq(GameTooltipStatusBar:GetAlpha(), 1)
    DaylightUI:Set("Tooltip", "healthBar", false)
    stub.RunTimers()
    T.eq(GameTooltipStatusBar:GetAlpha(), 0)
end)

T.test("tooltip: a handle in unlock mode; the tooltip goes there, moved or not", function()
    login()
    local DUI = DaylightUI
    local tick = stub.tooltip.Tooltip.driver:GetScript("OnUpdate")
    T.truthy(DUI.Movers.Get("tooltip"), "it gets a mover")
    GameTooltip:Show()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    tick(GameTooltip, 0.02)
    local _, rel = GameTooltip:GetPoint(1)
    T.eq(rel, _G.DaylightUITooltipAnchor, "not moved yet: still our handle, not Edit Mode's spot")
    DUI.DB.Positions().tooltip = { 300, -100 }
    DUI.Movers.Apply("tooltip")
    stub.RunTimers()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    tick(GameTooltip, 0.02)
    local p, rel2, rp = GameTooltip:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel2, _G.DaylightUITooltipAnchor); T.eq(rp, "BOTTOMRIGHT")
    -- The game putting it back at its own spot doesn't win for a frame:
    -- back on ours from the tooltip's own update, before it's drawn.
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100)
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq(select(2, GameTooltip:GetPoint(1)), _G.DaylightUITooltipAnchor, "back on ours before it's drawn")
    -- Something else that placed the tooltip keeps its own spot.
    GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    tick(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "LEFT", "its own spot kept")
    DUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    T.truthy(DUI.Movers.Get("tooltip").suspended, "no handle while it follows the cursor")
    DUI:Set("Tooltip", "anchor", "game")
    stub.RunTimers()
    T.falsy(DUI.Movers.Get("tooltip").suspended)
end)

T.test("tooltip: placement is the game's unless set to follow the cursor", function()
    login()
    local tick = stub.tooltip.Tooltip.driver:GetScript("OnUpdate")
    GameTooltip:Show()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    tick(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMRIGHT", "the game's spot")
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    tick(GameTooltip, 0.02)
    local point, _, _, x, y = GameTooltip:GetPoint(1)
    T.eq(point, "BOTTOMLEFT", "on the cursor")
    T.eq(x, 300 / GameTooltip:GetEffectiveScale() + 12)
    T.eq(y, 200 / GameTooltip:GetEffectiveScale() + 12)
    T.eq(GameTooltip.__anchor, "ANCHOR_NONE", "never re-owned from our code")
    -- The offset sliders move it off the cursor.
    DaylightUI:Set("Tooltip", "cursorX", -30)
    DaylightUI:Set("Tooltip", "cursorY", 40)
    stub.RunTimers()
    tick(GameTooltip, 0.02)
    point, _, _, x, y = GameTooltip:GetPoint(1)
    T.eq(x, 300 / GameTooltip:GetEffectiveScale() - 30, "x offset")
    T.eq(y, 200 / GameTooltip:GetEffectiveScale() + 40, "y offset")
    -- A tooltip something else placed stays where it was put.
    GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
    tick(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "LEFT", "its own spot kept")
    -- A frame that places the tooltip itself (the minimap's fps) keeps it
    -- where it put it, though the game's code put it at the default spot first.
    local fps = CreateFrame("Frame", nil, UIParent)
    fps.__duiOwnTooltipSpot = true
    GameTooltip_SetDefaultAnchor(GameTooltip, fps)
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", fps, "BOTTOM", 0, -6)
    tick(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "TOP", "the frame's spot, not the setting's")
end)

-- Something can put the tooltip at the game's default spot without the
-- game's default anchor function (which path does in game isn't known yet):
-- anchored to the game's container all the same, it goes where the setting
-- says, before it's ever drawn there.
T.test("tooltip: any tooltip at the game's spot goes to the cursor before it's drawn", function()
    login()
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    local tick = stub.tooltip.Tooltip.driver:GetScript("OnUpdate")
    local plate = CreateFrame("Frame", nil, UIParent)
    GameTooltip:Hide()
    GameTooltip:SetOwner(plate, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", GameTooltipDefaultContainer)
    GameTooltip:Show()
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMLEFT", "on the cursor as it shows")
    -- Already shown, put back at the game's spot: back on the cursor next frame.
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", GameTooltipDefaultContainer)
    tick(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMLEFT", "on the cursor")
    -- It follows the cursor from then on.
    local gx = _G.GetCursorPosition
    _G.GetCursorPosition = function() return 350, 220 end
    tick(GameTooltip, 0.02)
    T.eq(select(4, GameTooltip:GetPoint(1)), 350 / GameTooltip:GetEffectiveScale() + 12, "follows")
    _G.GetCursorPosition = gx
    -- Its own anchor (another tooltip spot entirely) is left alone.
    GameTooltip:SetOwner(plate, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", plate, "BOTTOM", 0, -6)
    tick(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "TOP", "placed by its owner: kept")
end)

-- In a restricted dungeon a tooltip showing secret text has secret
-- anchoring: every GetPoint return reads secret. Placing it each frame
-- compared its point (an error every frame, the tooltip stuck on screen).
T.test("tooltip: a tooltip with secret anchoring still follows the cursor and parks, no errors", function()
    login()
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    local tick = stub.tooltip.Tooltip.driver:GetScript("OnUpdate")
    local plate = CreateFrame("Frame", nil, UIParent)
    GameTooltip:Hide()
    GameTooltip:SetOwner(plate, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", GameTooltipDefaultContainer)
    GameTooltip:Show()
    GameTooltip.__secretAnchoring = true
    local gx = _G.GetCursorPosition
    _G.GetCursorPosition = function() return 350, 220 end
    tick(GameTooltip, 0.02)
    _G.GetCursorPosition = gx
    GameTooltip.__secretAnchoring = nil
    T.eq(GameTooltip.__points[1][4], 350 / GameTooltip:GetEffectiveScale() + 12, "follows")
    GameTooltip.__secretAnchoring = true
    stub.tooltip.Tooltip.Park(GameTooltip)
    GameTooltip.__secretAnchoring = nil
    T.eq(GameTooltip.__points[1][1], "TOPRIGHT", "parked off the screen")
end)

-- The minimap re-owns the tooltip each frame (SetOwner(UIParent,
-- "ANCHOR_CURSOR")), the same owner as a world unit's. The client's clear
-- handler can run before the new anchor is stored, so only the anchor read
-- at placement time tells it's no longer at the default spot.
T.test("tooltip: the minimap's quest tooltip stays on the cursor after a world unit's", function()
    login()
    local tick = stub.tooltip.Tooltip.driver:GetScript("OnUpdate")
    GameTooltip:Show()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)      -- a unit in the world
    tick(GameTooltip, 0.02)
    T.eq(select(2, GameTooltip:GetPoint(1)), _G.DaylightUITooltipAnchor, "on the handle")
    -- Mouse onto a quest on the minimap: cleared under the old anchor, then re-owned.
    local cleared = GameTooltip:GetScript("OnTooltipCleared")
    if cleared then cleared(GameTooltip) end
    GameTooltip.__owner, GameTooltip.__anchor = UIParent, "ANCHOR_CURSOR"
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 300, 200)  -- the game puts it at the cursor
    tick(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMLEFT", "left at the cursor, not pulled to the handle")
end)

T.test("tooltip: size, background and health bar height follow their options", function()
    local Tip = login()
    DaylightUI:Set("Tooltip", "scale", 1.25)
    DaylightUI:Set("Tooltip", "frameStyle.global", false)
    DaylightUI:Set("Tooltip", "frameStyle.windowAlpha", 0.6)
    DaylightUI:Set("Tooltip", "barHeight", 8)
    stub.RunTimers()
    T.eq(GameTooltip:GetScale(), 1.25)
    T.eq(ItemRefTooltip:GetScale(), 1.25)
    T.near(Tip.Shell(GameTooltip).bg.__color[4], 0.6)
    T.eq(GameTooltipStatusBar:GetHeight(), 8)
    -- On the global style it keeps its own design, a little more solid.
    DaylightUI:Set("Tooltip", "frameStyle.global", true)
    DaylightUI:Set("general", "windowAlpha", 0.4)
    stub.RunTimers()
    T.near(Tip.Shell(GameTooltip).bg.__color[4], 0.92)
    -- The game setting its own scale is undone when it shows.
    GameTooltip:SetScale(1)
    GameTooltip:GetScript("OnShow")(GameTooltip)
    T.eq(GameTooltip:GetScale(), 1.25)
end)

-- In combat the client can hand a world tooltip's owner and anchor back
-- secret: read as "unknown", never as another owner (that showed the
-- tooltip for a moment on each new mouseover, until its unit arrived).
T.test("tooltip: a world unit's tooltip whose owner reads secret stays hidden in combat and keeps its spot", function()
    login()
    DaylightUI:Set("Tooltip", "hideInCombat", true)
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    _G.IsShiftKeyDown = function() return false end
    stub.combat = true
    function GameTooltip:GetOwner() return stub.Secret(self.__owner) end
    function GameTooltip:GetAnchorType() return stub.Secret(self.__anchor) end
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)      -- a new enemy under the mouse
    GameTooltip:GetScript("OnTooltipCleared")(GameTooltip)   -- the game fills it in
    GameTooltip:Show()                                       -- (the client's Show: alpha 1)
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)     -- its update, before it's drawn
    T.eq(GameTooltip:GetAlpha(), 0, "never shown, not even before its unit is known")
    _G.IsShiftKeyDown = function() return true end           -- Shift: shown where it belongs
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMLEFT", "still placed at the cursor")
    GameTooltip:GetScript("OnHide")(GameTooltip)
    stub.combat = false
end)

T.test("tooltip: the fishing bobber's tooltip is muted while the line is in, when set to", function()
    local Tip = login(function() Enum.TooltipDataType.Object = 33 end)
    stub.spells = stub.spells or {}
    stub.spells[7620] = { name = "Fishing" }
    local function bobber()
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
        show(GameTooltip, Enum.TooltipDataType.Object, function(t) t.__unit = nil end)
        GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
        return Tip.Muted(GameTooltip) == "bobber"
    end
    stub.units.player.channel = { name = "Fishing", spellID = 7620 }
    T.eq(bobber(), false, "off by default: it shows")
    DaylightUI:Set("Tooltip", "hideBobber", true)
    stub.RunTimers()
    T.eq(bobber(), true, "muted while fishing")
    T.eq(GameTooltip:GetAlpha(), 0)
    T.truthy(GameTooltip:IsShown(), "never hidden: the click still reaches the bobber")
    stub.units.player.channel = nil
    T.eq(bobber(), false, "a chest or a mailbox when not fishing shows")
    stub.units.player.channel = { name = "Arcane Missiles", spellID = 5143 }
    T.eq(bobber(), false, "another channel isn't fishing")
    stub.units.player.channel = nil
    GameTooltip:GetScript("OnHide")(GameTooltip)
end)

T.test("tooltip: hidden in combat when set to, unless Shift is held", function()
    login()
    DaylightUI:Set("Tooltip", "hideInCombat", true)
    stub.RunTimers()
    local shift = false
    _G.IsShiftKeyDown = function() return shift end
    stub.combat = true
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)       -- first hover, before unit data
    GameTooltip:Show()                                        -- (the client's Show: alpha 1)
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)      -- its update, before it's drawn
    T.eq(GameTooltip:GetAlpha(), 0, "unseen before its unit data arrives")
    show(GameTooltip, Enum.TooltipDataType.Item, function() end)
    T.eq(GameTooltip:GetAlpha(), 1, "not a unit: it shows")
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.eq(GameTooltip:GetAlpha(), 0, "unseen in combat (alpha, never hidden from our code)")
    GameTooltip:SetAlpha(1)                                   -- the game sets the alpha back
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq(GameTooltip:GetAlpha(), 0, "kept unseen from its own update, before it's drawn")
    GameTooltip.__alpha = 1; GameTooltip:Show()               -- Show() resets the alpha itself
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq(GameTooltip:GetAlpha(), 0, "kept unseen through the game's Show()")
    GameTooltip:GetScript("OnTooltipCleared")(GameTooltip)    -- the game refreshes the unit
    T.eq(GameTooltip:GetAlpha(), 0, "not shown while it's empty")
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)       -- the next enemy in the world
    T.eq(GameTooltip:GetAlpha(), 0, "not shown before its unit is known")
    local button = CreateFrame("Button", nil, UIParent)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")              -- an action button's tooltip
    T.eq(GameTooltip:GetAlpha(), 1, "a button's tooltip shows")
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    shift = true
    GameTooltip:GetScript("OnTooltipCleared")(GameTooltip)    -- the game clears it for the next one
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.eq(GameTooltip:GetAlpha(), 1, "Shift shows it")
    stub.combat = false
end)

-- The game's ProcessInfo runs our post-calls, THEN self:Show(), which puts
-- the alpha back to 1 (and stops a fade) on a tooltip already shown: no
-- OnShow, and that frame is drawn before any update of ours. Seen in game:
-- a flash on each new enemy. So a hidden one is also off the screen.
T.test("tooltip: a unit hidden in combat stays unseen through the game's Show() after our post-calls", function()
    login()
    DaylightUI:Set("Tooltip", "hideInCombat", true)
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    local shift = false
    _G.IsShiftKeyDown = function() return shift end
    GameTooltip:SetClampedToScreen(true)
    GameTooltip:Show()                                         -- already shown (the last enemy, fading)
    stub.combat = true
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)        -- the next enemy under the mouse
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    GameTooltip.__alpha = 1                                    -- the game's Show(): alpha back, no OnShow
    local _, _, _, x, y = GameTooltip:GetPoint(1)
    T.truthy(type(x) == "number" and x < 0 and y < 0, "off the screen, so the game's alpha shows nothing")
    T.eq(GameTooltip:IsClampedToScreen(), false, "free to leave the screen")
    shift = true                                               -- Shift: back at the cursor, on the screen
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq(GameTooltip:GetAlpha(), 1)
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMLEFT", "at the cursor")
    T.eq(GameTooltip:IsClampedToScreen(), true)
    GameTooltip:GetScript("OnHide")(GameTooltip)
    stub.combat = false
end)

T.test("tooltip: pressing Shift while hovering a unit hidden in combat shows it, dressed", function()
    login()
    DaylightUI:Set("Tooltip", "hideInCombat", true)
    stub.RunTimers()
    local shift = false
    _G.IsShiftKeyDown = function() return shift end
    stub.combat = true
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    T.eq(GameTooltip:GetAlpha(), 0, "hidden in combat")
    shift = true                                              -- Shift pressed, the mouse still on it
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.eq(GameTooltip:GetAlpha(), 1, "shows at once")
    T.truthy(GameTooltipStatusBar.__color, "with our health bar color")
    GameTooltip:GetScript("OnHide")(GameTooltip)
    stub.combat = false
end)

T.test("tooltip: hovering a unit frame shows its unit's tooltip, at the tooltip's placement", function()
    stub.Load({ module = true, tooltip = true, before = function()
        world()
        function GameTooltip:SetUnit(u) self.__setUnit = u end
        stub.units.target = { name = "Wolf", reaction = 2 }
    end })
    stub.RunTimers()
    local f = DaylightUIFrame_target
    f:GetScript("OnEnter")(f)
    T.eq(GameTooltip.__setUnit, "target")
    T.eq(GameTooltip.__anchor, "ANCHOR_NONE", "the game's spot")
    T.truthy(GameTooltip:IsShown())
    f:GetScript("OnLeave")(f)
    T.falsy(GameTooltip:IsShown())
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    f:GetScript("OnEnter")(f)
    stub.tooltip.Tooltip.driver:GetScript("OnUpdate")(stub.tooltip.Tooltip.driver, 0.02)
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMLEFT", "or the cursor")
end)

T.test("tooltip: leaving something in the world hides its tooltip at once, or fades it when set to", function()
    login()
    stub.RunTimers()
    -- The game fades it on the world cursor's update when nothing's under
    -- the mouse any more; we watch the same event (no hook on FadeOut).
    _G.C_TooltipInfo = { GetWorldCursor = function() return nil end }
    stub.units.mouseover = nil                        -- nothing under the mouse
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    GameTooltip:FadeOut()                             -- the mouse left a creature
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(GameTooltip:GetAlpha(), 0, "gone at once (unseen, never hidden from our code)")
    GameTooltip:GetScript("OnHide")(GameTooltip)       -- the game hides it after its fade
    T.eq(GameTooltip:GetAlpha(), 1, "back for the next one")
    DaylightUI:Set("Tooltip", "fadeOut", true)
    stub.RunTimers()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    GameTooltip:FadeOut()
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(GameTooltip:GetAlpha(), 1, "left to the game's fade")
    T.truthy(GameTooltip.__fading)
end)

T.test("tooltip: the world cursor's updates are looked at once a frame, however many came", function()
    login()
    stub.RunTimers()
    local asks = 0
    _G.C_TooltipInfo = { GetWorldCursor = function() asks = asks + 1; return nil end }
    stub.units.mouseover = nil
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    for _ = 1, 5 do stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0) end
    stub.RunTimers()
    T.eq(asks, 1, "five cursor moves in one frame: one read")
    GameTooltip:GetScript("OnHide")(GameTooltip)
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(asks, 2, "the next frame's move: read again")
end)

-- The client answers an addon's GetWorldCursor with nothing for an enemy
-- it keeps from us (a player's report: the tooltip vanished while on the
-- enemy, and only showed once the mouse moved off). The mouse is still on a
-- unit: left alone.
T.test("tooltip: on an enemy the client tells us nothing about, its tooltip stays", function()
    login()
    DaylightUI:Set("Tooltip", "fadeOut", false)
    stub.RunTimers()
    _G.C_TooltipInfo = { GetWorldCursor = function() return nil end }
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)  -- the mouse went onto the enemy
    stub.RunTimers()
    T.eq(GameTooltip:GetAlpha(), 1, "shown while the mouse is on it")
    stub.units.mouseover = nil                         -- the mouse left it
    GameTooltip:FadeOut()
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(GameTooltip:GetAlpha(), 0, "gone at once once it left")
    GameTooltip:GetScript("OnHide")(GameTooltip)
end)

-- The game's fade is its own (C) update setting the tooltip's alpha every
-- frame, and it can run after our alpha 0 in the same frame: the tooltip
-- still faded out slowly, at the cursor (a player's report).
T.test("tooltip: leaving something in the world, the game's fade never shows it", function()
    login()
    DaylightUI:Set("Tooltip", "fadeOut", false)
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    local Tip = stub.tooltip.Tooltip
    local tick = Tip.driver:GetScript("OnUpdate")
    _G.C_TooltipInfo = { GetWorldCursor = function() return nil end }
    stub.units.mouseover = nil                        -- nothing under the mouse
    GameTooltip:SetClampedToScreen(true)               -- as the game's template
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    tick(Tip.driver, 0.02)
    GameTooltip:FadeOut()                              -- the mouse left a creature
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    for _, a in ipairs({ 0.9, 0.7, 0.5 }) do
        tick(Tip.driver, 0.02)
        GameTooltip:SetAlpha(a)                        -- the game's fade, after ours
        local point, rel, relPoint, x, y = GameTooltip:GetPoint(1)
        T.eq(GameTooltip:IsClampedToScreen(), false, "free to leave the screen")
        T.eq(point, "TOPRIGHT"); T.eq(rel, UIParent); T.eq(relPoint, "BOTTOMLEFT")
        T.truthy(x < 0 and y < 0, "off the screen: the fade shows nothing")
    end
    -- The next unit brings it back at the cursor, kept on the screen.
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    tick(Tip.driver, 0.02)
    T.eq(GameTooltip:IsClampedToScreen(), true)
    T.eq(GameTooltip:GetAlpha(), 1)
    T.eq((GameTooltip:GetPoint(1)), "BOTTOMLEFT", "on the cursor")
    -- Or the game hides it at the fade's end: back as it was.
    GameTooltip:FadeOut()
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(GameTooltip:IsClampedToScreen(), false)
    GameTooltip:Hide()
    T.eq(GameTooltip:IsClampedToScreen(), true)
    T.eq(GameTooltip:GetAlpha(), 1)
end)

-- In combat the world tooltip's owner reads secret: the mouse leaving a
-- unit then left the game's fade on screen for seconds (a player's report).
T.test("tooltip: leaving a unit in combat hides its tooltip at once, though its owner reads secret", function()
    login()
    DaylightUI:Set("Tooltip", "fadeOut", false)
    stub.RunTimers()
    _G.C_TooltipInfo = { GetWorldCursor = function() return nil end }
    stub.units.mouseover = nil                        -- nothing under the mouse
    stub.combat = true
    local getOwner = GameTooltip.GetOwner
    function GameTooltip:GetOwner() return stub.Secret(self.__owner) end
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    GameTooltip:SetAlpha(1)                           -- shown (Shift held, or hiding in combat off)
    GameTooltip:FadeOut()                             -- the mouse left the unit
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(GameTooltip:GetAlpha(), 0, "gone at once")
    GameTooltip:GetScript("OnHide")(GameTooltip)
    DaylightUI:Set("Tooltip", "fadeOut", true)        -- fading on: a unit hidden in combat still never shows
    DaylightUI:Set("Tooltip", "hideInCombat", true)
    stub.RunTimers()
    _G.IsShiftKeyDown = function() return false end
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    GameTooltip:Show()
    GameTooltip:SetAlpha(1)
    GameTooltip:FadeOut()
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(GameTooltip:GetAlpha(), 0, "not shown by the game's fade")
    GameTooltip:GetScript("OnHide")(GameTooltip)
    GameTooltip.GetOwner = getOwner
    stub.combat = false
end)

T.test("tooltip: every tooltip the game already made is skinned at load, the buff bar's too", function()
    login(function()
        -- The buff bar's tooltip: the client fills it itself, so no data hook ever sees it.
        local buff = CreateFrame("GameTooltip", "BuffFrameTooltip", UIParent)
        buff.NineSlice = CreateFrame("Frame", nil, buff)
        local other = CreateFrame("GameTooltip", "SomeOtherTooltip", UIParent)
        other.NineSlice = CreateFrame("Frame", nil, other)
        local list = { buff, other, CreateFrame("Frame", nil, UIParent) }
        _G.EnumerateFrames = function(prev)
            if prev == nil then return list[1] end
            for i, f in ipairs(list) do if f == prev then return list[i + 1] end end
        end
    end)
    local Tip = stub.tooltip.Tooltip
    T.truthy(Tip.Shell(BuffFrameTooltip), "the buff bar's tooltip in our look")
    T.eq(BuffFrameTooltip.NineSlice:GetAlpha(), 0, "its own art hidden")
    T.truthy(Tip.Shell(SomeOtherTooltip), "and any other the game made")
    _G.EnumerateFrames = nil
end)

T.test("tooltip: a loading screen walks the frames again only after an addon loaded", function()
    login()
    local walks = 0
    _G.EnumerateFrames = function(prev) if prev == nil then walks = walks + 1 end end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.eq(walks, 0, "nothing new since login: no walk")
    stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI")
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.eq(walks, 1, "a game addon loaded in: its tooltips get skinned")
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.eq(walks, 1)
    _G.EnumerateFrames = nil
end)

T.test("tooltip: the aura buttons' tooltip (the client's own) gets our backdrop through its styling hook", function()
    local got
    login(function()
        _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
        _G.AuraContainerInbound = { SetTooltipBackdrop = function(info) got = info end }
    end)
    T.truthy(got, "styled at load")
    T.eq(got.centerColor.r, DaylightUI.Style.BACKGROUND[1], "our background")
    T.eq(got.borderColor.r, DaylightUI.Style.BORDER[1], "our border")
    T.truthy(got.backdropInfo.edgeSize > 0)
    DaylightUI:Set("Tooltip", "frameStyle.global", false)
    DaylightUI:Set("Tooltip", "frameStyle.windowAlpha", 0.5)
    stub.RunTimers()
    T.eq(got.centerColor.a, 0.5, "follows the Background opacity setting")
    _G.AuraContainerInbound = nil
end)

T.test("tooltip: their target and guild rank as extra lines", function()
    login()
    local lines = {}
    function GameTooltip:AddDoubleLine(l, r, ...) lines[#lines + 1] = { l, r, ... } end
    local second = GameTooltip:CreateFontString("GameTooltipTextLeft2")
    _G.GameTooltipTextLeft2 = second
    second:SetText("<Knights Radiant>")
    _G.GetGuildInfo = function() return "Knights Radiant", "Stormwarden" end
    stub.units.mouseover = { name = "Kaladin", isPlayer = true, class = "WARRIOR" }
    stub.units.mouseovertarget = { name = "Me", isPlayer = true, class = "MAGE" }
    stub.units.player = stub.units.mouseovertarget
    show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unitName, t.__unit = "Kaladin", "mouseover" end)
    T.eq(second.__text, "<Knights Radiant> - Stormwarden", "the rank after the guild")
    T.eq(lines[1][1], "Target:")
    T.eq(lines[1][2], ">> You <<", "you, when it's you")
    _G.GetGuildInfo = nil
end)

T.test("tooltip: a friendly player's buffs as rows of icons; none in combat (secret) or with the switch off", function()
    login()
    local lines = {}
    local add = GameTooltip.AddLine
    function GameTooltip:AddLine(text, ...) lines[#lines + 1] = text; return add(self, text, ...) end
    stub.units.player = { name = "Me", isPlayer = true, class = "PRIEST" }
    stub.units.mouseover = { name = "Kaladin", isPlayer = true, class = "WARRIOR", friend = true }
    local list = {}
    for i = 1, 12 do list[i] = { icon = 1000 + i, name = "Buff " .. i } end
    stub.auras.mouseover = { HELPFUL = list }
    local function hover()
        lines = {}
        show(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unitName, t.__unit = "Kaladin", "mouseover" end)
        local rows = {}
        for _, l in ipairs(lines) do if type(l) == "string" and l:find("|T1", 1, true) then rows[#rows + 1] = l end end
        return rows
    end
    T.eq(#hover(), 0, "off by default")
    DaylightUI:Set("Tooltip", "buffs", true)
    stub.RunTimers()
    local rows = hover()
    T.eq(#rows, 2, "twelve buffs: a row of ten, then two")
    T.truthy(rows[1]:find("|T1001:", 1, true) and rows[2]:find("|T1012:", 1, true), "each one's icon")
    stub.auraReadsThrow = true
    T.eq(#hover(), 0, "in combat the game hides them: nothing")
    stub.auraReadsThrow = nil
    DaylightUI:Set("Tooltip", "buffs", false)
    stub.RunTimers()
    T.eq(#hover(), 0, "switched off")
    GameTooltip.AddLine = add
    stub.auras.mouseover = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: kept in place without re-anchoring it every frame (each re-anchor lays its text out again)", function()
    login()
    local tick = stub.tooltip.Tooltip.driver:GetScript("OnUpdate")
    GameTooltip:Show()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    tick(GameTooltip, 0.02)
    local cleared = 0
    local real = GameTooltip.ClearAllPoints
    GameTooltip.ClearAllPoints = function(self) cleared = cleared + 1; return real(self) end
    for _ = 1, 10 do tick(GameTooltip, 0.02) end
    T.eq(cleared, 0, "at its handle already: left alone")
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    tick(GameTooltip, 0.02)
    cleared = 0
    for _ = 1, 10 do tick(GameTooltip, 0.02) end
    T.eq(cleared, 0, "on the cursor, the cursor still: left alone")
    local gx = _G.GetCursorPosition
    _G.GetCursorPosition = function() return 350, 220 end
    tick(GameTooltip, 0.02)
    T.eq(cleared, 1, "the cursor moved: it follows")
    _G.GetCursorPosition = gx
    GameTooltip.ClearAllPoints = real
end)

T.test("tooltip: its per-frame work runs once a frame, and our driver rests while it's hidden", function()
    local Tip = login()
    local n, orig = 0, Tip.OnUpdate
    Tip.OnUpdate = function(...) n = n + 1; return orig(...) end
    local own, drive = GameTooltip:GetScript("OnUpdate"), Tip.driver:GetScript("OnUpdate")
    GameTooltip:Show()
    for _ = 1, 10 do own(GameTooltip, 0.02); drive(Tip.driver, 0.02) end
    T.eq(n, 10, "the tooltip's own update did it: our driver had nothing to do")
    n = 0
    for _ = 1, 3 do drive(Tip.driver, 0.02) end      -- the game stops its update while it fades
    T.eq(n, 3, "while the game's update is stopped, ours keeps it on the cursor")
    GameTooltip:Hide()
    T.eq(Tip.driver:IsShown(), false, "nothing to look after while it's hidden")
    GameTooltip:Show()
    T.eq(Tip.driver:IsShown(), true)
    Tip.OnUpdate = orig
end)

-- The game refilling a tooltip from its data (TooltipDataHandlerMixin:
-- InternalProcessInfo): its info list emptied, cleared, the post-calls at once.
local function refill(tip, kind, set)
    tip.infoList = {}
    show(tip, kind, set)
    tip.infoList = { {} }
end

T.test("tooltip: a refill of the same thing (every 0.2 s on an item) doesn't lay the border out again", function()
    local Tip = login(function() stub.qualities = { rare = 3, epic = 4, common = 1 } end)
    local Style, Item = DaylightUI.Style, Enum.TooltipDataType.Item
    local s = Tip.Shell(GameTooltip)
    refill(GameTooltip, Item, function(t) t.__link = "rare" end)
    Style.TakeLayoutCount()
    for _ = 1, 5 do refill(GameTooltip, Item, function(t) t.__link = "rare" end) end
    T.eq(Style.TakeLayoutCount(), 0, "same color: left as it is")
    T.near(s.opts.borderColor[1], 0.3, 1e-6)
    refill(GameTooltip, Item, function(t) t.__link = "epic" end)
    T.eq(Style.TakeLayoutCount(), 0, "another color: repainted, not laid out")
    T.near(s.opts.borderColor[1], 0.4, 1e-6)
    T.near(s.border.LEFT.__vertex[1], 0.4, 1e-6, "the outline wears it")
    refill(GameTooltip, Enum.TooltipDataType.Spell, function(t) t.__link = nil end)
    T.isnil(s.opts.borderColor, "something else: plain again")
    refill(GameTooltip, Item, function(t) t.__link = "rare" end)
    refill(GameTooltip, Item, function(t) t.__link = "common" end)
    T.isnil(s.opts.borderColor, "an item below the quality line: plain")
    -- A unit's class gradient, refilled.
    DaylightUI:Set("Tooltip", "borderGradient", true)
    stub.RunTimers()
    refill(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end)
    local pair = s.opts.borderPair
    T.truthy(pair)
    Style.TakeLayoutCount()
    for _ = 1, 3 do refill(GameTooltip, Enum.TooltipDataType.Unit, function(t) t.__unit = "mouseover" end) end
    T.eq(Style.TakeLayoutCount(), 0)
    T.eq(s.opts.borderPair, pair, "no new table either")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The X on a clicked item (the game's button, its click the game's): the same
-- X as every window's, with or without the Skins module.
T.test("tooltip: the clicked item's X is Daylight UI's", function()
    login()
    local close, W, Style = ItemRefTooltip.CloseButton, DaylightUI.Widgets, DaylightUI.Style
    T.eq(close.__art:GetAlpha(), 0, "the game's red art gone")
    local x = W.DressClose(close)   -- dressed once: this only hands back its X
    T.truthy(x, "our X on it")
    T.isnil(rawget(close, "icon"), "nothing written on the game's button (/dui taint)")
    local label = Style.INK.LABEL
    T.eq(({ x:GetVertexColor() })[1], label[1], "tan at rest")
    close:GetScript("OnEnter")(close)
    T.eq(({ x:GetVertexColor() })[1], (Style.Accent()), "the accent under the mouse")
    close:GetScript("OnLeave")(close)
    T.eq(({ x:GetVertexColor() })[1], label[1], "back to tan")
    T.isnil(rawget(close, "SetScript"), "no method of the game's button replaced")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: a refill whose post-calls never come still ends plain", function()
    local Tip = login(function() stub.qualities = { rare = 3 } end)
    local s = Tip.Shell(ItemRefTooltip)
    show(ItemRefTooltip, Enum.TooltipDataType.Item, function(t) t.__link = "rare" end)
    T.truthy(s.opts.borderColor)
    -- Another addon's pre-call stops the refill after the clear.
    ItemRefTooltip.infoList = {}
    ItemRefTooltip:GetScript("OnTooltipCleared")(ItemRefTooltip)
    stub.RunTimers()
    T.isnil(s.opts.borderColor, "the frame after")
    local g = Tip.Shell(GameTooltip)
    show(GameTooltip, Enum.TooltipDataType.Item, function(t) t.__link = "rare" end)
    GameTooltip.infoList = {}
    GameTooltip:GetScript("OnTooltipCleared")(GameTooltip)
    GameTooltip:GetScript("OnUpdate")(GameTooltip, 0.02)
    T.isnil(g.opts.borderColor, "the main tooltip: on its update, before it's drawn")
end)

-- Item level and IDs: lines the tooltip really holds (the fake game's
-- GameTooltip has no lines of its own), filled as the game does: cleared,
-- then the data's post-calls with its data.
local function withLines(tip)
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
        left:SetText(l); left:SetTextColor(lr, lg, lb)
        right:SetText(r); right:SetTextColor(rr, rg, rb)
    end
    function tip:AddLine(t, r, g, b) self:AddDoubleLine(t, nil, r, g, b) end
    return function(i, side) return line(side or "Left", i) end
end

local function fill(tip, kind, data, gameLines)
    tip:ClearLines()
    local clear = tip:GetScript("OnTooltipCleared")
    if clear then clear(tip) end
    for _, t in ipairs(gameLines or { "Something" }) do
        if type(t) == "table" then tip:AddDoubleLine(unpack(t)) else tip:AddLine(t) end
    end
    data.type = kind
    for _, fn in ipairs(post.ALL or {}) do fn(tip, data) end
    for _, fn in ipairs(post[kind] or {}) do fn(tip, data) end
end

local function itemWorld()
    Enum.TooltipDataType.UnitAura = 7
    _G.ITEM_LEVEL = "Item Level %d"
    -- id, type, subtype, equip slot, icon, class
    local items = {
        sword = { 1001, "Weapon", "Swords", "INVTYPE_WEAPON", 1, 2, level = 45 },
        shirt = { 1002, "Armor", "Miscellaneous", "INVTYPE_BODY", 1, 4, level = 1 },
        potion = { 1003, "Consumable", "Potion", "", 1, 0, level = 5 },
    }
    C_Item.GetItemInfoInstant = function(link)
        local it = items[link]
        if it then return unpack(it, 1, 6) end
    end
    C_Item.GetDetailedItemLevelInfo = function(link)
        local it = items[link]
        if it then return it.level, false, it.level end
    end
end

T.test("tooltip: item level and IDs are off out of the box", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "sword" })
    fill(GameTooltip, Enum.TooltipDataType.Spell, { id = 133 })
    T.eq(GameTooltip:NumLines(), 1, "only the game's line")
    T.eq(at(1):GetText(), "Something")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: item level on gear only, once per fill, never twice with the game's", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    DaylightUI:Set("Tooltip", "itemLevel", true)
    stub.RunTimers()
    local Item = Enum.TooltipDataType.Item
    fill(GameTooltip, Item, { id = 1001, hyperlink = "sword" })
    T.eq(GameTooltip:NumLines(), 2)
    T.eq(at(2):GetText(), "Item Level 45")
    T.rgb(at(2).__textColor, { 0.95, 0.82, 0.45 }, "soft gold")
    -- The game refills an item's tooltip every 0.2 s: one line each time.
    for _ = 1, 3 do fill(GameTooltip, Item, { id = 1001, hyperlink = "sword" }) end
    T.eq(GameTooltip:NumLines(), 2, "a refill adds it once")
    -- The same data's post-calls twice in one fill: not a second line.
    for _, fn in ipairs(post[Item]) do fn(GameTooltip, { type = Item, id = 1001, hyperlink = "sword" }) end
    T.eq(GameTooltip:NumLines(), 2, "not twice in one tooltip")
    fill(GameTooltip, Item, { id = 1001, hyperlink = "sword" }, { "Sword", "Item Level 45" })
    T.eq(GameTooltip:NumLines(), 2, "the game's own line is enough")
    fill(GameTooltip, Item, { id = 1002, hyperlink = "shirt" })
    T.eq(GameTooltip:NumLines(), 1, "a shirt: no level")
    fill(GameTooltip, Item, { id = 1003, hyperlink = "potion" })
    T.eq(GameTooltip:NumLines(), 1, "a potion: no level")
    -- No link in the data: the tooltip's own.
    fill(GameTooltip, Item, { id = 1001 })
    T.eq(GameTooltip:NumLines(), 1, "no link anywhere: nothing")
    GameTooltip.__link = "sword"
    fill(GameTooltip, Item, { id = 1001 })
    T.eq(at(2):GetText(), "Item Level 45", "from the tooltip's item")
    GameTooltip.__link = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: stack size on items that stack, once switched on, the number in the accent", function()
    login(itemWorld)
    T.eq(DaylightUI:Get("Tooltip", "stackSize"), false, "off as shipped")
    DaylightUI:Set("Tooltip", "stackSize", true)
    stub.RunTimers()
    local at = withLines(GameTooltip)
    local stacks, before = { potion = 20, sword = 1 }, C_Item.GetItemInfo
    C_Item.GetItemInfo = function(link)
        if stacks[link] then return link, link, 1, 1, 1, "", "", stacks[link] end
    end
    local Item = Enum.TooltipDataType.Item
    local Hex, accent = DaylightUI.Win.Parts.Hex, { DaylightUI.Style.Accent() }
    fill(GameTooltip, Item, { id = 1003, hyperlink = "potion" })
    T.eq(GameTooltip:NumLines(), 2)
    T.eq(at(2):GetText(), "Stacks to " .. Hex(accent) .. "20|r")
    T.rgb(at(2).__textColor, DaylightUI.Style.INK.LABEL, "the words in the label color")
    for _ = 1, 3 do fill(GameTooltip, Item, { id = 1003, hyperlink = "potion" }) end
    T.eq(GameTooltip:NumLines(), 2, "a refill adds it once")
    fill(GameTooltip, Item, { id = 1001, hyperlink = "sword" })
    T.eq(GameTooltip:NumLines(), 1, "a sword doesn't stack: no line")
    fill(GameTooltip, Item, { id = 1002, hyperlink = "shirt" })
    T.eq(GameTooltip:NumLines(), 1, "not loaded yet: no line")
    stacks.potion = stub.Secret(20)
    fill(GameTooltip, Item, { id = 1003, hyperlink = "potion" })
    T.eq(GameTooltip:NumLines(), 1, "a secret size: no line")
    stacks.potion = 20
    DaylightUI:Set("Tooltip", "stackSize", false)
    stub.RunTimers()
    fill(GameTooltip, Item, { id = 1003, hyperlink = "potion" })
    T.eq(GameTooltip:NumLines(), 1, "off: no line")
    C_Item.GetItemInfo = before
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: short item stats, on out of the box, procs left alone", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local Item = Enum.TooltipDataType.Item
    fill(GameTooltip, Item, { id = 1001, hyperlink = "sword" }, {
        "Sword",
        "Equip: Improves your chance to hit by 1%.",
        "Equip: Increases damage and healing done by magical spells and effects by up to 9.",
        "Equip: Increases damage done by Fire spells and effects by up to 12.",
        "Equip: Restores 2 mana per 5 sec.",
        "Equip: Increased Swords +5.",
        "Equip: Increased Defense +7.",
        "Chance on hit: Blasts the target for 50 Fire damage.",
        "(3) Set: Improves your chance to hit by 1%.",
    })
    local function words(i) return (at(i):GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    T.eq(words(2), "+1% Hit")
    T.eq(words(3), "+9 Spell Power")
    T.eq(words(4), "+12 Fire Damage")
    T.eq(words(5), "+2 Mana per 5 sec")
    T.eq(words(6), "+5 Swords Skill")
    T.eq(words(7), "+7 Defense")
    local Tip = stub.tooltip.Tooltip
    T.eq(at(2):GetText():sub(1, 10), "|cffffdb8f", "hit in its color")
    T.eq(at(4):GetText():sub(1, 10), "|cffff8547", "fire in fire's")
    T.eq(at(8):GetText(), "Chance on hit: Blasts the target for 50 Fire damage.", "a proc stays")
    T.eq(at(9):GetText(), "(3) Set: Improves your chance to hit by 1%.", "a set bonus stays")
    fill(GameTooltip, Item, { id = 1001, hyperlink = "sword" }, {
        "Sword", "+10 Stamina", "+5 Frost Resistance", "-3 Spirit", "Equip: Increases healing done by up to 44 and damage done by up to 15 for all magical spells and effects.",
    })
    T.eq(at(2):GetText(), "|cfff5a361+10 Stamina|r", "a white base stat in its color")
    T.eq(at(3):GetText(), "|cff85d1ff+5 Frost Resistance|r", "a resistance by its school")
    T.eq(at(4):GetText(), "-3 Spirit", "a minus stays the game's")
    T.eq(words(5), "+44 Healing\n+15 Spell Damage", "healing and spell damage on lines of their own")
    T.truthy(Tip.StatColor("Two-handed Swords Skill"), "a weapon skill")
    DaylightUI:Set("Tooltip", "greenStats", false)
    stub.RunTimers()
    fill(GameTooltip, Item, { id = 1001, hyperlink = "sword" }, { "Sword", "Equip: Improves your chance to hit by 1%." })
    T.eq(at(2):GetText(), "Equip: Improves your chance to hit by 1%.", "off: the game's sentence")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: food, drink, potions and bandages in a few words, under the short stats switch", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local Item = Enum.TooltipDataType.Item
    local function words(i) return (at(i):GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local FOOD = "Use: Restores 530 health over 24 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and gain 5 Stamina and 5% increased experience from kills for 15 min."
    local OLD_FOOD = "Use: Restores 1,338 health over 27 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and gain 12 Stamina and Spirit for 900 sec."
    local LONG = "Use: Restores 2,148 health over 30 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and restore 8 mana every 5 seconds for 10 min."
    fill(GameTooltip, Item, { id = 1001, hyperlink = "food" }, {
        "Smoked Bear Meat", FOOD, OLD_FOOD,
        "Use: Restores 1,344 mana over 30 sec. Must remain seated while drinking.",
        "Use: Restores 900 health and 900 mana over 30 sec. Must remain seated while eating.",
        "Use: Restores 455 to 585 health.",
        "Use: Instantly restores 700 to 900 mana.",
        "Use: Heals 400 damage over 8 sec.",
        LONG,
        "Use: Returns you to your home.",
    })
    T.eq(words(2), "Use: 530 health over 24 sec\nWell Fed: +5 Stamina, +5% XP (15 min)")
    T.eq(words(3), "Use: 1,338 health over 27 sec\nWell Fed: +12 Stamina, +12 Spirit (15 min)", "an old food's both stats, seconds read as minutes")
    T.eq(words(4), "Use: 1,344 mana over 30 sec", "a drink")
    T.eq(words(5), "Use: 900 health and 900 mana over 30 sec", "a mage's food")
    T.eq(words(6), "Use: 455-585 health", "a potion")
    T.eq(words(7), "Use: 700-900 mana", "a mana potion")
    T.eq(words(8), "Use: 400 health over 8 sec", "a bandage")
    T.eq(at(9):GetText(), LONG, "a sentence it can't read stays whole")
    T.eq(at(10):GetText(), "Use: Returns you to your home.", "other use effects stay")
    local hex = DaylightUI.Win.Parts.Hex
    local Style, Tip = DaylightUI.Style, stub.tooltip.Tooltip
    T.truthy(at(2):GetText():find(hex(Style.INK.GOOD) .. "530|r", 1, true), "health in heal green")
    T.truthy(at(4):GetText():find(hex({ Style.PowerColor("MANA") }) .. "1,344|r", 1, true), "mana in mana's color")
    T.truthy(at(2):GetText():find(hex(Tip.STAT_COLORS.Stamina) .. "+5 Stamina|r", 1, true), "a stat in its color")
    DaylightUI:Set("Tooltip", "greenStats", false)
    stub.RunTimers()
    fill(GameTooltip, Item, { id = 1001, hyperlink = "food" }, { "Smoked Bear Meat", FOOD })
    T.eq(at(2):GetText(), FOOD, "off: the game's sentence")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: item stats keep their colors in other languages", function()
    -- The game's own stat formats, as a German and a Korean client have them.
    local saved = {}
    local function set(k, v) saved[k] = saved[k] == nil and { _G[k] } or saved[k]; _G[k] = v end
    set("ITEM_MOD_STRENGTH", "%c%s St\195\164rke")
    set("ITEM_MOD_STAMINA", "\236\178\180\235\160\165 %c%s")
    set("ITEM_RESIST_SINGLE", "%c%d %swiderstand")
    set("DAMAGE_SCHOOL3", "Feuer")
    login(itemWorld)
    local at = withLines(GameTooltip)
    local Tip = stub.tooltip.Tooltip
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "sword" }, {
        "Sword", "+24 St\195\164rke", "\236\178\180\235\160\165 +10", "+5 Feuerwiderstand", "-3 St\195\164rke",
    })
    local hex = DaylightUI.Win.Parts.Hex
    T.eq(at(2):GetText(), hex(Tip.STAT_COLORS.Strength) .. "+24 St\195\164rke|r", "German strength in its color")
    T.eq(at(3):GetText(), hex(Tip.STAT_COLORS.Stamina) .. "\236\178\180\235\160\165 +10|r", "Korean puts the name first")
    T.eq(at(4):GetText(), hex(Tip.SCHOOL_COLORS.Fire) .. "+5 Feuerwiderstand|r", "a resistance by its school")
    T.eq(at(5):GetText(), "-3 St\195\164rke", "a minus stays the game's")
    local num, name, c = Tip.ReadStat("\236\178\180\235\160\165 +10")
    T.eq(num, "+10")
    T.eq(name, "\236\178\180\235\160\165")
    T.rgb(c, Tip.STAT_COLORS.Stamina)
    for k, v in pairs(saved) do _G[k] = v[1] end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: the game's money lines wear Daylight UI's coins, and Sell Price reads Vendor", function()
    login(itemWorld)
    _G.SELL_PRICE = "Sell Price"
    local at = withLines(GameTooltip)
    local coin = function(n, what) return n .. "|A:coin-" .. what .. ":14:14:2:0|a" end   -- the game's FormatMoney
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "paw" }, {
        "Small Furry Paw",
        "Sell Price: " .. coin(2, "silver") .. " " .. coin(76, "copper"),
        coin("1,234", "gold") .. " " .. coin(5, "silver"),
        coin("1 234", "gold"),
        "Sells for 2 coins",
    })
    local W = DaylightUI.Widgets
    T.eq(at(2):GetText(), "Vendor: " .. W.Money(200) .. " " .. W.Money(76))
    T.eq(at(3):GetText(), W.Money(12340000) .. " " .. W.Money(500), "a thousands separator")
    T.eq(at(4):GetText(), W.Money(12340000), "a locale's separator")
    T.falsy(at(2):GetText():find("|A:", 1, true), "none of the game's coins left")
    T.eq(at(5):GetText(), "Sells for 2 coins", "other lines stay")
    DaylightUI:Set("Tooltip", "greenStats", false)
    stub.RunTimers()
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "paw" }, {
        "Small Furry Paw", "Sell Price: " .. coin(76, "copper"),
    })
    T.eq(at(2):GetText(), "Vendor: " .. W.Money(76), "whatever the other switches")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The client leaves the sell price out of a quest reward's data, so the game
-- prints none (TooltipDataRules.SellPrice only paints a SellPrice line it's given).
T.test("tooltip: quest rewards show their sell price, the whole stack, once", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local was = { Enum.TooltipDataLineType, C_Item.GetItemInfo, _G.GetQuestLogChoiceInfo, _G.GetQuestItemInfo }
    _G.SELL_PRICE = "Sell Price"
    Enum.TooltipDataLineType = { SellPrice = 11 }   -- the game's TooltipInfoSharedDocumentation
    local prices = { sword = 1554, potion = 25 }
    C_Item.GetItemInfo = function(link)
        if prices[link] then return link, link, 2, 10, 1, "", "", 1, "", 1, prices[link] end
    end
    _G.GetQuestLogChoiceInfo = function(i, id) return "Sword", 1, 1, 2, true, 1001 end
    _G.GetQuestItemInfo = function(kind, i) return "Potion", 1, 5, 1, true, 1003 end
    local W = DaylightUI.Widgets
    local function asked(getter, ...)
        GameTooltip.infoList = { { getterName = getter, getterArgs = { n = select("#", ...), ... } } }
    end

    asked("GetQuestLogItem", "choice", 1, 99)
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "sword" }, { "Sword" })
    T.eq(GameTooltip:NumLines(), 2, "the price added")
    T.eq(at(2):GetText(), "Vendor: " .. W.Money(1554), "in the quest log")

    asked("GetQuestItem", "reward", 1)
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1003, hyperlink = "potion" }, { "Potion" })
    T.eq(at(2):GetText(), "Vendor: " .. W.Money(125), "at the NPC, five potions")

    local coin = function(n, what) return n .. "|A:coin-" .. what .. ":14:14:2:0|a" end
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1003, hyperlink = "potion",
        lines = { { type = Enum.TooltipDataLineType.SellPrice, price = 125 } } },
        { "Potion", "Sell Price: " .. coin(25, "copper") })
    T.eq(GameTooltip:NumLines(), 2, "never twice when the game sent one")

    asked("GetBagItem", 0, 1)
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "sword" }, { "Sword" })
    T.eq(GameTooltip:NumLines(), 1, "other items keep the game's own lines")

    prices.sword = 0
    asked("GetQuestLogItem", "choice", 1, 99)
    fill(GameTooltip, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "sword" }, { "Sword" })
    T.eq(GameTooltip:NumLines(), 1, "nothing for an item vendors won't buy")
    GameTooltip.infoList = nil
    Enum.TooltipDataLineType, C_Item.GetItemInfo, _G.GetQuestLogChoiceInfo, _G.GetQuestItemInfo = unpack(was, 1, 4)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: spell, aura and item IDs at the bottom, the label in the accent, secret ones left out", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    DaylightUI:Set("Tooltip", "showIDs", true)
    DaylightUI:Set("Tooltip", "itemLevel", true)
    stub.RunTimers()
    local types = Enum.TooltipDataType
    fill(GameTooltip, types.Item, { id = 1001, hyperlink = "sword" })
    T.eq(GameTooltip:NumLines(), 3)
    T.eq(at(2):GetText(), "Item Level 45", "the level first")
    T.eq(at(3):GetText(), "Item ID")
    T.eq(at(3, "Right"):GetText(), "1001")
    T.rgb(at(3).__textColor, { DaylightUI.Style.Accent() }, "the label in the accent, as our own tooltips")
    for _ = 1, 3 do fill(GameTooltip, types.Item, { id = 1001, hyperlink = "sword" }) end
    T.eq(GameTooltip:NumLines(), 3, "a refill adds them once")
    fill(GameTooltip, types.Item, { hyperlink = "potion" })
    T.eq(at(2):GetText(), "Item ID", "no id in the data: the link's")
    T.eq(at(2, "Right"):GetText(), "1003")
    fill(GameTooltip, types.Spell, { id = 133 })
    T.eq(at(2):GetText(), "Spell ID")
    T.eq(at(2, "Right"):GetText(), "133")
    fill(GameTooltip, types.UnitAura, { id = 774 })
    T.eq(at(2, "Right"):GetText(), "774", "an aura: its spell")
    fill(GameTooltip, types.UnitAura, { id = stub.Secret(774) })
    T.eq(GameTooltip:NumLines(), 1, "a secret id: no line")
    fill(GameTooltip, types.Spell, {})
    T.eq(GameTooltip:NumLines(), 1, "no id: no line")
    fill(GameTooltip, types.Unit, { id = 5 })
    T.eq(GameTooltip:NumLines(), 1, "a unit: none")
    DaylightUI:Set("Tooltip", "showIDs", false)
    stub.RunTimers()
    fill(GameTooltip, types.Spell, { id = 133 })
    T.eq(GameTooltip:NumLines(), 1, "off again: gone with the next fill")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: a spell's cost in its power color, numbers popped, heals green, damage soft red", function()
    login(itemWorld)
    _G.MANA = "Mana"
    local at = withLines(GameTooltip)
    local S, INK = DaylightUI.Style, DaylightUI.Style.INK
    DaylightUI:Set("general", "accent", "custom")
    DaylightUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    stub.RunTimers()
    local H = DaylightUI.Win.Parts.Hex
    local pop, good, dmg = H({ 0.2, 0.6, 0.9 }), H(INK.GOOD), H(INK.DAMAGE)
    fill(GameTooltip, Enum.TooltipDataType.Spell, { id = 1 }, {
        { "Holy Shock", nil, 1, 1, 1 },
        { "30 Mana", "30 yd range", 1, 1, 1, 1, 1, 1 },
        { "Instant", "Requires Paladin", 1, 1, 1, 1, 0.13, 0.13 },
        { "Heals a friendly target for 120 to 145, or deals 30 to 45 Holy damage. Lasts 3 sec.", nil, 1, 0.82, 0 },
        { "Causes 12 damage every 3 sec.", nil, 1, 0.82, 0 },
        { "Glowing Copper Boots", nil, 0.12, 1, 0 },
        { "Equip: Increases healing done by up to 9.", nil, 0, 1, 0 },
    })
    T.rgb(at(6).__textColor, { 0.12, 1, 0 }, "a recipe's item keeps its quality color")
    T.eq(at(7):GetText(), "Equip: Increases healing done by up to 9.", "and its green lines stay as they are")
    T.rgb(at(7).__textColor, { 0, 1, 0 })
    T.rgb(at(2).__textColor, { S.PowerColor("MANA") }, "the cost in mana's color")
    T.eq(at(2):GetText(), "30 Mana")
    T.eq(at(2, "Right"):GetText(), pop .. "30|r yd range", "the range's number pops")
    T.rgb(at(2, "Right").__textColor, INK.LABEL)
    T.rgb(at(3, "Right").__textColor, { 1, 0.13, 0.13 }, "a red requirement left")
    T.eq(at(4):GetText(), "Heals a friendly target for " .. good .. "120|r to " .. good .. "145|r, or deals "
        .. dmg .. "30|r to " .. dmg .. "45|r Holy damage. Lasts " .. pop .. "3|r sec.")
    T.rgb(at(4).__textColor, INK.TEXT, "the game's yellow description: our text color")
    T.eq(at(5):GetText(), "Causes " .. dmg .. "12|r damage every " .. pop .. "3|r sec.")
    T.rgb(at(1).__textColor, { 1, 1, 1 }, "the title left")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A macro on an action bar fills the tooltip with its spell's lines under the
-- Macro data type (seen in game: it kept the game's blue and yellow).
T.test("tooltip: a macro's spell lines get the same look as the spell's, without a Spell ID", function()
    login(function() itemWorld(); Enum.TooltipDataType.Macro = 25 end)
    _G.MANA = "Mana"
    local at = withLines(GameTooltip)
    local S, INK = DaylightUI.Style, DaylightUI.Style.INK
    DaylightUI:Set("Tooltip", "showIDs", true)
    stub.RunTimers()
    fill(GameTooltip, Enum.TooltipDataType.Macro, { id = 3 }, {
        { "Smite", "Rank 4", 1, 1, 1, 0.5, 0.5, 0.5 },
        { "95 Mana", "30 yd range", 1, 1, 1, 1, 1, 1 },
        { "Smite an enemy for 82 to 91 Holy damage.", nil, 1, 0.82, 0 },
    })
    T.rgb(at(2).__textColor, { S.PowerColor("MANA") }, "the cost in mana's color")
    T.rgb(at(3).__textColor, INK.TEXT, "the yellow description: our text color")
    T.eq(GameTooltip:NumLines(), 3, "no Spell ID: the id is the macro's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- In a fight (the global cooldown) a macro's lines and colors all read secret,
-- like a spell's. Its data's lines say which one is the spell's description.
T.test("tooltip: in a fight a macro's spell description still turns white", function()
    local was = Enum.TooltipDataLineType
    login(function()
        itemWorld()
        Enum.TooltipDataType.Macro = 25
        Enum.TooltipDataLineType = { SpellName = 13, SpellDescription = 34 }   -- the game's TooltipInfoSharedDocumentation
    end)
    local at = withLines(GameTooltip)
    local INK = DaylightUI.Style.INK
    fill(GameTooltip, Enum.TooltipDataType.Macro, { id = 3, lines = { { type = 13 }, {}, { type = 34 } } }, {
        { stub.Secret("Smite"), stub.Secret("Rank 4"), 1, 1, 1, 0.5, 0.5, 0.5 },
        { stub.Secret("95 Mana"), stub.Secret("30 yd range"), 1, 1, 1, 1, 1, 1 },
        { stub.Secret("Smite an enemy for 82 to 91 Holy damage."), nil, 1, 0.82, 0 },
    })
    T.rgb(at(3).__textColor, INK.TEXT, "the description our text color")
    T.rgb(at(2).__textColor, { 1, 1, 1 }, "a secret white line left, as a spell's is")
    -- A macro that uses an item has no spell lines: its last line is the item's.
    fill(GameTooltip, Enum.TooltipDataType.Macro, { id = 4, lines = { {}, {}, {} } }, {
        { stub.Secret("Hearthstone"), nil, 1, 1, 1 },
        { stub.Secret("Use: Returns you to your home."), nil, 0, 1, 0 },
        { stub.Secret("A flavor line."), nil, 1, 0.82, 0 },
    })
    T.rgb(at(3).__textColor, { 1, 0.82, 0 }, "an item's lines keep the game's colors")
    Enum.TooltipDataLineType = was
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Mend Pet: "while you focus" once painted its heal Focus orange. A power word
-- only colors a number when it comes right after it.
T.test("tooltip: a heal with 'focus' later in the sentence stays a heal; an aura's sentence our text color", function()
    login(itemWorld)
    _G.FOCUS = "Focus"
    local at = withLines(GameTooltip)
    local INK = DaylightUI.Style.INK
    local H = DaylightUI.Win.Parts.Hex
    fill(GameTooltip, Enum.TooltipDataType.Spell, { id = 1 }, {
        { "Mend Pet", nil, 1, 1, 1 },
        { "Heals your pet 20 health every second while you focus.  Lasts 5 sec.", nil, 1, 0.82, 0 },
        { "Your pet is being healed for a while and feels much better now.", nil, 1, 1, 1 },
    })
    T.truthy(at(2):GetText():find(H(INK.GOOD) .. "20|r health", 1, true), "the heal green: " .. at(2):GetText())
    T.rgb(at(3).__textColor, INK.TEXT, "a long white line (an aura's sentence) our text color, not the game's white")
    _G.FOCUS = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A secret text reads its color back secret too. The text is left whole,
-- only the description's color changes.
T.test("tooltip: in a fight a spell's secret description still turns white, its text untouched", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local desc = stub.Secret("Causes 12 damage every 3 sec.")
    fill(GameTooltip, Enum.TooltipDataType.Spell, { id = 1, lines = { {}, {}, {} } }, {
        { stub.Secret("Corruption"), nil, 1, 1, 1 },
        { stub.Secret("Instant"), nil, 1, 1, 1 },
        { desc, nil, 1, 0.82, 0 },
    })
    T.rgb(at(3).__textColor, DaylightUI.Style.INK.TEXT, "the yellow line our text color")
    T.eq(at(3):GetText(), desc, "its text left as the game gave it")
    T.rgb(at(2).__textColor, { 1, 1, 1 }, "a secret white line left: short or a sentence can't be told")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A spell in the global cooldown during a fight: every line's text and color
-- read secret, but the data's type and id don't (seen in game). The description
-- is the data's last line.
T.test("tooltip: a spell whose lines and colors all read secret: its last data line (the description) turns white", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    fill(GameTooltip, Enum.TooltipDataType.Spell, { id = 17, lines = { {}, {}, {}, {}, {} } }, {
        { stub.Secret("Power Word: Shield"), stub.Secret("Rank 1"), 1, 1, 1, 0.5, 0.5, 0.5 },
        { stub.Secret("45 Mana"), stub.Secret("40 yd range"), 1, 1, 1, 1, 1, 1 },
        { stub.Secret("Instant"), stub.Secret("4 sec cooldown"), 1, 1, 1, 1, 1, 1 },
        { stub.Secret("Cooldown remaining: 2 sec"), nil, 1, 1, 1 },
        { stub.Secret("Draws on the soul of the party member."), nil, 1, 0.82, 0 },
        { stub.Secret("Press F6 to submit an issue"), nil, 1, 0.82, 0 },
    })
    T.rgb(at(5).__textColor, DaylightUI.Style.INK.TEXT, "the description our text color")
    T.rgb(at(6).__textColor, { 1, 0.82, 0 }, "a line added after the game's (the PTR reporter's) left")
    T.rgb(at(1, "Right").__textColor, { 0.5, 0.5, 0.5 }, "the rank left")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: a secret line whose data line says yellow turns white, whatever its place", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local yellow = { r = 1, g = 0.82, b = 0 }
    fill(GameTooltip, Enum.TooltipDataType.Spell, { id = 17, lines = { {}, { leftColor = yellow }, { leftColor = { r = 1, g = 1, b = 1 } } } }, {
        { stub.Secret("Spell"), nil, 1, 1, 1 },
        { stub.Secret("A description."), nil, 1, 0.82, 0 },
        { stub.Secret("Some white line"), nil, 1, 1, 1 },
    })
    T.rgb(at(2).__textColor, DaylightUI.Style.INK.TEXT, "the yellow one our text color")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: in a fight a recipe's item line (its quality color) still ends the painting", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    fill(GameTooltip, Enum.TooltipDataType.Spell, { id = 1 }, {
        { "Pattern: Boots", nil, 1, 1, 1 },
        { stub.Secret("Glowing Copper Boots"), nil, 0.12, 1, 0 },
        { stub.Secret("Some flavor."), nil, 1, 0.82, 0 },
    })
    T.rgb(at(3).__textColor, { 1, 0.82, 0 }, "the item's own lines keep the game's colors")
end)

T.test("tooltip: a recipe's item keeps the game's colors whole, white lines and numbers too, like an item's tooltip", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local INK = DaylightUI.Style.INK
    local function recipe(item, color, data)
        fill(GameTooltip, Enum.TooltipDataType.Spell, data or { id = 2 }, {
            { "Blacksmithing: " .. item, nil, 1, 0.82, 0 },
            { "Tools: Blacksmith Hammer", nil, 1, 1, 1 },
            { item, nil, color[1], color[2], color[3] },
            { "Binds when picked up", nil, 1, 1, 1 },
            { "109 Armor", nil, 1, 1, 1 },
            { "Equip: Increases healing done by up to 9.", nil, 0, 1, 0 },
            { "Requires Level 10", nil, 1, 1, 1 },
        })
    end
    recipe("Glowing Copper Boots", { 0.12, 1, 0 })
    T.rgb(at(2).__textColor, INK.LABEL, "the recipe's own lines are ours")
    T.rgb(at(3).__textColor, { 0.12, 1, 0 }, "the item's name in its quality")
    T.eq(at(5):GetText(), "109 Armor", "no popped numbers in the item")
    T.rgb(at(5).__textColor, { 1, 1, 1 })
    T.eq(at(6):GetText(), "Equip: Increases healing done by up to 9.")
    T.rgb(at(7).__textColor, { 1, 1, 1 })
    -- a common (white) item: found by the data's item name line
    Enum.TooltipDataLineType = Enum.TooltipDataLineType or { ItemName = 22 }
    recipe("Copper Mace", { 1, 1, 1 }, { id = 3, lines = { { type = 22, leftText = "Copper Mace" } } })
    T.rgb(at(2).__textColor, INK.LABEL)
    T.rgb(at(3).__textColor, { 1, 1, 1 }, "a common item's name stays the game's white")
    T.eq(at(5):GetText(), "109 Armor")
    T.rgb(at(5).__textColor, { 1, 1, 1 })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: numbers in a sentence by what they are (Tips.Numbers)", function()
    login(itemWorld)
    _G.MANA = "Mana"
    local Tips, INK, H = DaylightUI.Tips, DaylightUI.Style.INK, DaylightUI.Win.Parts.Hex
    local good, pop = H(INK.GOOD), H({ DaylightUI.Style.Pop() })
    local dmg = H(INK.DAMAGE)
    T.eq(Tips.Numbers("inflicts32 to 35 Holy damage"), "inflicts " .. dmg .. "32|r to " .. dmg .. "35|r Holy damage", "a glued number gets its space back")
    T.eq(Tips.Numbers("Restores 50 health."), "Restores " .. good .. "50|r health.")
    T.eq(Tips.Numbers("Heals 30 every 3 sec."), "Heals " .. good .. "30|r every " .. pop .. "3|r sec.", "a HoT: the tick green, the time the accent")
    T.eq(Tips.Numbers("Restores 100 Mana."), "Restores " .. H({ DaylightUI.Style.PowerColor("MANA") }) .. "100|r Mana.", "mana in its color")
    T.eq(Tips.Numbers("|cffff0000Red 5|r"), "|cffff0000Red 5|r", "a line with its own code left")
    T.eq(Tips.Numbers("|CFFFF2020Requires Bear Form|r"), "|CFFFF2020Requires Bear Form|r", "an upper case color code is a code too")
    -- the game's plural code (|4hour:hrs;) and textures carry digits of their own
    T.eq(Tips.Numbers("an effect that lasts 2 |4hour:hrs;."), "an effect that lasts " .. pop .. "2|r |4hour:hrs;.", "the plural code stays whole")
    T.eq(Tips.Numbers("Costs |TInterface\\Icons\\Coin:14:14|t 5"), "Costs |TInterface\\Icons\\Coin:14:14|t " .. pop .. "5|r", "a texture's size stays whole")
    local StatText = DaylightUI.Char and DaylightUI.Char.StatText
    T.truthy(type(StatText) == "table", "stat text loaded")
    T.eq(StatText.Numbers("Lasts 2 |4hour:hrs;.", INK.GOOD), "Lasts " .. good .. "2|r |4hour:hrs;.", "stat text keeps the plural code too")
end)

T.test("tooltip: a loot row near the right edge opens its tooltip on the left when its compares can't fit", function()
    local Tip = login()
    local function at(f, left, w)
        function f:GetLeft() return left end
        function f:GetRight() return left + w end
        function f:GetWidth() return w end
    end
    function UIParent:GetWidth() return 1920 end
    local row = CreateFrame("Frame", nil, UIParent)
    local shop1 = CreateFrame("Frame", nil, UIParent)
    local shop2 = CreateFrame("Frame", nil, UIParent)
    GameTooltip.shoppingTooltips = { shop1, shop2 }
    function GameTooltip:SetAnchorType(a) self.__anchor = a end
    at(GameTooltip, 0, 300)
    at(shop1, 0, 300)
    at(shop2, 0, 300)
    shop1:Hide()
    shop2:Hide()

    -- room on the right for it alone: left as its owner asked
    at(row, 1300, 250)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    show(GameTooltip, 0, function() end)
    T.eq(GameTooltip:GetAnchorType(), "ANCHOR_RIGHT", "it fits on the right")

    -- the compares show (Shift): no room for all three, more on the left
    shop1:Show()
    shop2:Show()
    Tip.OnCompareShown(shop2)
    T.eq(GameTooltip:GetAnchorType(), "ANCHOR_LEFT", "mirrored at once, so the compares clear the loot window")

    -- a row on the left half keeps its right side
    at(row, 200, 250)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    show(GameTooltip, 0, function() end)
    T.eq(GameTooltip:GetAnchorType(), "ANCHOR_RIGHT", "plenty of room on the right")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: a compare tooltip's Equipped tab wears our shell, joined to the tooltip, in its border color", function()
    local art
    local Tip = login(function()
        -- As the game's ShoppingTooltipTemplate: a CompareHeader with its
        -- art and a gold label, hung on the tooltip's top.
        local tip = CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent)
        tip.NineSlice = CreateFrame("Frame", nil, tip)
        tip:SetFrameLevel(2)
        local h = CreateFrame("Frame", nil, tip)
        h:SetFrameLevel(1)
        h:SetSize(100, 22)
        h:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", 0, -1)
        art = h:CreateTexture(nil, "BACKGROUND")
        art:SetAllPoints(h)
        h.Label = h:CreateFontString(nil, "ARTWORK")
        h.Label:SetTextColor(1, 0.82, 0)
        tip.CompareHeader = h
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local h = ShoppingTooltip1.CompareHeader
    local s = DaylightUI.Style.GetShell(h)
    T.truthy(s, "the tab has our shell")
    T.eq(art:GetAlpha(), 0, "the game's tab art out of sight")
    local r, g, b = h.Label:GetTextColor()
    local tan = DaylightUI.Style.INK.LABEL
    T.near(r, tan[1], 1e-6); T.near(g, tan[2], 1e-6); T.near(b, tan[3], 1e-6, "the label tan, not gold")
    Tip.Tint(ShoppingTooltip1, 0.5, 0.2, 0.9)
    T.eq(s.opts.borderColor[1], 0.5, "the tab follows the tooltip's quality border")
    Tip.ResetColors(ShoppingTooltip1)
    T.isnil(s.opts.borderColor, "and back with it")
end)

-- As the game's: ShoppingTooltipTemplate has TooltipDataHandlerMixin only, so
-- no GetItem (that's GameTooltipDataMixin), and the data of an equipped item
-- carries a guid and no hyperlink (TooltipComparisonManager:SetItemTooltip).
local function compareWorld()
    itemWorld()
    stub.qualities = { sword = 3 }
    C_Item.GetItemLinkByGUID = function(guid) if guid == "Item-1" then return "sword" end end
    local tip = CreateFrame("GameTooltip", "ShoppingTooltip1", UIParent)
    tip.NineSlice = CreateFrame("Frame", nil, tip)
    tip:SetFrameLevel(2)
    tip.CompareHeader = CreateFrame("Frame", nil, tip)
end

T.test("tooltip: a compare tooltip's equipped item gets its quality border and its item level", function()
    local Tip = login(compareWorld)
    withLines(ShoppingTooltip1)
    DaylightUI:Set("Tooltip", "itemLevel", true)
    stub.RunTimers()
    T.isnil(ShoppingTooltip1.GetItem, "as the game's: a compare tooltip has no GetItem")
    local s = Tip.Shell(ShoppingTooltip1)
    fill(ShoppingTooltip1, Enum.TooltipDataType.Item, { id = 1001, guid = "Item-1" })
    T.truthy(s.opts.borderColor, "tinted")
    T.near(s.opts.borderColor[1], 0.3, 1e-6, "the equipped item's quality color")
    T.truthy(Tip.HasLine(ShoppingTooltip1, "Item Level 45"), "its item level too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: a compare tooltip showing a linked item takes the link's quality", function()
    local Tip = login(compareWorld)
    withLines(ShoppingTooltip1)
    fill(ShoppingTooltip1, Enum.TooltipDataType.Item, { id = 1001, hyperlink = "sword" })
    T.truthy(Tip.Shell(ShoppingTooltip1).opts.borderColor, "tinted from the data's hyperlink")
end)

T.test("tooltip: a shown compare tooltip filled again keeps its border, with no reset in between", function()
    local Tip = login(compareWorld)
    withLines(ShoppingTooltip1)
    local s = Tip.Shell(ShoppingTooltip1)
    fill(ShoppingTooltip1, Enum.TooltipDataType.Item, { id = 1001, guid = "Item-1" })
    ShoppingTooltip1:Show()
    local had = s.opts.borderColor
    local cleared = ShoppingTooltip1:GetScript("OnTooltipCleared")
    cleared(ShoppingTooltip1)
    T.eq(s.opts.borderColor, had, "the game's ClearLines lays nothing out")
    fill(ShoppingTooltip1, Enum.TooltipDataType.Item, { id = 1001, guid = "Item-1" })
    T.eq(s.opts.borderColor, had, "the same color again is the same table")
    cleared(ShoppingTooltip1)
    stub.RunTimers()
    T.isnil(s.opts.borderColor, "cleared with nothing after it: the reset still comes")
end)

-- Questie's drop chance, as its Tooltip.lua writes it: typed-in gray, on a
-- line it adds from its own post-call, after ours.
T.test("tooltip: Questie's drop chance is the accent, after its own line lands and after a refill", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local Parts, Unit = DaylightUI.Win.Parts, Enum.TooltipDataType.Unit
    local pop = Parts.Hex({ DaylightUI.Style.Accent() })
    local update = GameTooltip:GetScript("OnUpdate")
    local function show()
        fill(GameTooltip, Unit, {})
        GameTooltip:AddLine("   |cFFEEEEEE0/8 Linen Cloth  |cFF999999[37%]|r  |cFF999999[1.5%]|r")
        GameTooltip:AddLine("A plain line, 50% gray")
        update(GameTooltip, 0.02)
    end
    show()
    T.eq(at(2):GetText(), "   |cFFEEEEEE0/8 Linen Cloth  " .. pop .. "[37%]|r  " .. pop .. "[1.5%]|r")
    T.eq(at(3):GetText(), "A plain line, 50% gray", "other lines stay")
    update(GameTooltip, 0.02)
    T.eq(at(2):GetText(), "   |cFFEEEEEE0/8 Linen Cloth  " .. pop .. "[37%]|r  " .. pop .. "[1.5%]|r", "painted once")
    show()   -- the same number of lines after a refill: gray again until repainted
    T.truthy(string.find(at(2):GetText(), pop .. "[37%]|r", 1, true), "a refill is repainted")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Questie's objective rows, as its Tooltip.lua writes them: three spaces, the
-- row's color, the count, then the drop chance.
T.test("tooltip: a finished Questie objective says Complete, dim, with no drop chance", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local Parts, Style = DaylightUI.Win.Parts, DaylightUI.Style
    local off, good = Parts.Hex(Style.INK.OFF), Parts.Hex(Style.INK.GOOD)
    local pop = Parts.Hex({ Style.Accent() })
    local word = DaylightUI.L["Complete"]
    local update = GameTooltip:GetScript("OnUpdate")
    local shows = 0
    local show = GameTooltip.Show
    function GameTooltip:Show(...) shows = shows + 1; return show(self, ...) end
    fill(GameTooltip, Enum.TooltipDataType.Unit, {})
    GameTooltip:AddLine("|cFF40C040[5] Zenn's Bidding|r")
    GameTooltip:AddLine("   |cFFEEEEEE3/3 Nightsaber Fang  |cFF999999[21%]|r")
    GameTooltip:AddLine("   |cFFEEEEEE2/3 Strigid Owl Feather  |cFF999999[40%]|r")
    GameTooltip:AddLine("   |cFFEEEEEEWebwood Venom Sac: 8/8")
    GameTooltip:Show()
    shows = 0
    update(GameTooltip, 0.02)
    T.eq(at(2):GetText(), "|cFF40C040[5] Zenn's Bidding|r", "the quest's title stays")
    T.eq(at(3):GetText(), "   " .. off .. "3/3 Nightsaber Fang  " .. good .. word .. "|r", "no chance left to bait you")
    T.eq(at(4):GetText(), "   |cFFEEEEEE2/3 Strigid Owl Feather  " .. pop .. "[40%]|r", "still needed: as it was")
    T.eq(at(5):GetText(), "   " .. off .. "Webwood Venom Sac: 8/8  " .. good .. word .. "|r", "the game's own wording too")
    T.eq(shows, 1, "the tooltip re-fits to the longer line")
    -- A line added later recounts: the finished rows aren't marked again.
    GameTooltip:AddLine("Target: Someone")
    update(GameTooltip, 0.02)
    T.eq(at(3):GetText(), "   " .. off .. "3/3 Nightsaber Fang  " .. good .. word .. "|r", "marked once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game menu's performance tooltip is the one micro button tooltip the game
-- sends to its default corner (MainMenuBarPerformanceBarFrame_OnEnter): every
-- other one is ANCHOR_RIGHT on its button.
T.test("tooltip: the game menu button's performance tooltip sits by the button, not at the handle", function()
    login()
    local tick = stub.tooltip.Tooltip.driver:GetScript("OnUpdate")
    local place = function(f, right, top, w, h)
        function f:GetRight() return right end
        function f:GetTop() return top end
        function f:GetWidth() return w end
        function f:GetHeight() return h end
    end
    function UIParent:GetWidth() return 1920 end
    function UIParent:GetHeight() return 1080 end
    local button = CreateFrame("Button", "MainMenuMicroButton", UIParent)
    GameTooltip:Show()
    local function hover()
        GameTooltip_SetDefaultAnchor(GameTooltip, button)
        tick(GameTooltip, 0.02)
        local p, rel, rp = GameTooltip:GetPoint(1)
        T.eq(rel, button, "hangs on the button")
        return p, rp
    end

    place(GameTooltip, 0, 0, 300, 690)
    place(button, 1000, 40, 32, 40)
    local p, rp = hover()
    T.eq(p, "BOTTOMLEFT", "as its neighbours: up and right of the button")
    T.eq(rp, "TOPRIGHT")

    -- The game writes it again every second: it stays by the button.
    p = hover()
    T.eq(p, "BOTTOMLEFT")

    -- Lines arrive after the game's anchor: read each frame, before it's drawn.
    place(button, 1800, 40, 32, 40)
    p = hover()
    T.eq(p, "BOTTOMRIGHT", "no room on the right: the left of the button's edge")

    place(button, 1000, 1000, 32, 40)
    p, rp = hover()
    T.eq(p, "TOPLEFT", "a menu at the top of the screen: under the button")
    T.eq(rp, "BOTTOMRIGHT")

    -- The cursor setting moves default tooltips; the neighbours stay on their
    -- buttons, so this one does too.
    DaylightUI:Set("Tooltip", "anchor", "cursor")
    stub.RunTimers()
    hover()

    -- Any other default tooltip still goes where the setting says.
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    tick(GameTooltip, 0.02)
    local _, rel = GameTooltip:GetPoint(1)
    T.eq(rel, UIParent, "at the cursor")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ---------------------------------------------------------------------
-- With PrettyTooltip on, this module stands down completely. Nothing is left to
-- change its lines, fight its alpha or hold a tooltip up after the mouse leaves.
-- ---------------------------------------------------------------------

T.test("prettytooltip on: our tooltips are off: no shell, no handle, no hooks, and a setting or style change builds nothing", function()
    local PW = require("prettyworld")
    local Tip = login(function() PW.Install(stub) end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.isnil(Tip.Shell(GameTooltip), "not skinned")
    T.isnil(Tip.anchor, "no unlock handle")
    T.isnil(post.ALL, "no post-calls on its data")
    T.isnil(post[0], "or items")
    T.isnil(GameTooltip:GetScript("OnTooltipCleared"), "no scripts on the game's tooltip")
    DaylightUI:Set("Tooltip", "scale", 1.2)
    DaylightUI.NotifyStyleChanged()
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.isnil(Tip.Shell(GameTooltip), "still nothing")
    PW.Uninstall(stub)
end)

T.test("prettytooltip on: the health bar its unit panels borrow is ours, in the unit's color", function()
    local PW = require("prettyworld")
    local Tip = login(function() PW.Install(stub) end)
    Enum.TooltipDataType.Unit = 2
    GameTooltip.__unit, GameTooltip.__unitName = "wolf", "Wolf"
    Tip.BarOnly(DaylightUI:GetModule("Tooltip"))
    T.eq(GameTooltipStatusBar:GetAlpha(), 1, "shown")
    Tip.OnBarUnit(GameTooltip)
    T.truthy(GameTooltipStatusBar.__color, "its reaction's color")
    GameTooltip.__unit = nil
    T.noerror(function() Tip.OnBarUnit(GameTooltip) end, "no unit: nothing to paint")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    PW.Uninstall(stub)
end)

T.test("prettytooltip on: the Tooltips options page goes; set to the game's own tooltips, ours run as usual", function()
    local PW = require("prettyworld")
    login(function() PW.Install(stub) end)
    local page = stub.tooltip.OPTIONS.pages[1]
    T.eq(page.hidden(), true, "no page of settings that do nothing")
    PW.Uninstall(stub)
    local Tip = login(function() PW.Install(stub, { layout = "blizzard" }) end)
    T.truthy(Tip.Shell(GameTooltip), "it draws no panels: ours are on")
    T.falsy(stub.tooltip.OPTIONS.pages[1].hidden(), "and their page")
    PW.Uninstall(stub)
end)

T.test("tooltip: plugins add lines in Daylight UI's look, once each, after its own", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local me = DaylightUI.API.For("Lines")
    local seen = {}
    me.AddTooltipLines("item", function(lines, data)
        seen.item = data
        lines.Line("Fish caught", 12)
        lines.Hint("Shift: more")
    end)
    me.AddTooltipLines("spell", function(lines, data) seen.spell = data.spellID; lines.Text("A plugin's note") end)
    local types = Enum.TooltipDataType
    fill(GameTooltip, types.Item, { id = 1001, hyperlink = "sword" })
    T.eq(seen.item.itemID, 1001); T.eq(seen.item.link, "sword")
    local n = GameTooltip:NumLines()
    T.eq(at(n - 1):GetText(), "Fish caught"); T.eq(at(n - 1, "Right"):GetText(), "12")
    T.rgb(at(n - 1).__textColor, DaylightUI.Style.INK.TEXT, "label soft white")
    T.eq(at(n):GetText(), "Shift: more")
    for _ = 1, 3 do fill(GameTooltip, types.Item, { id = 1001, hyperlink = "sword" }) end
    T.eq(GameTooltip:NumLines(), n, "a refill adds them once")
    fill(GameTooltip, types.Spell, { id = 133 })
    T.eq(seen.spell, 133)
    seen.spell = 0
    fill(GameTooltip, types.Spell, { id = stub.Secret(133) })
    T.isnil(seen.spell, "a secret id comes as nil")
    local broken = me.AddTooltipLines("item", function() error("boom") end)
    fill(GameTooltip, types.Item, { id = 1001, hyperlink = "sword" })
    T.truthy(GameTooltip:NumLines() >= n, "an error in one leaves the others")
    DaylightUI.API.Off(broken)
    T.isnil(me.AddTooltipLines("weather", function() end), "an unknown kind is refused")
end)

-- The game hides a tooltip itself (an owner's OnLeave) and it can't be held
-- open, so a copy of it fades out where it was drawn. Never in combat, never
-- with Motion off, never when its spots are secret.
T.test("tooltip: fades out as a ghost where it was, as the game hides it", function()
    local Tip = login()
    local G = stub.tooltip.TipGhost
    local M = DaylightUI.Motion
    local function tick(dt)
        local d = M.Driver()
        if d then stub.RunOnUpdate(d, dt) end
    end
    local tip = GameTooltip
    local line = withLines(tip)
    local function place(f, l, t, w, h)
        function f:GetLeft() return l end
        function f:GetTop() return t end
        function f:GetWidth() return w end
        function f:GetHeight() return h end
        function f:GetRect() return l, t - h, w, h end
    end
    local function up()
        tip:Hide()
        stub.Advance(1)
        fill(tip, Enum.TooltipDataType.Item, {}, { "Linen Cloth", { "Sell", "1s" } })
        tip:Show()
        place(tip, 400, 300, 160, 60)
        place(line(1), 410, 290, 80, 14)
        place(line(2), 410, 270, 30, 12)
        place(line(2, "Right"), 520, 270, 30, 12)
        line(2, "Right"):SetJustifyH("RIGHT")
        stub.Advance(0.02)
        tip:GetScript("OnUpdate")(tip, 0.02) -- drawn once
        tick(M.NORMAL * 2)
    end
    local function words(g)
        local out = {}
        for _, fs in ipairs(g.texts) do
            if fs:IsShown() then out[fs:GetText()] = fs end
        end
        return out
    end
    up()
    Tip.Tint(tip, 0.9, 0.1, 0.1)
    tip:Hide()
    local g = G.Of(tip)
    T.truthy(g and g:IsShown(), "a ghost where it was")
    T.eq(g:GetAlpha(), 1, "at the alpha it had")
    local pt, rel, rp, x, y = g:GetPoint(1)
    T.eq(pt .. rp .. x .. "," .. y, "BOTTOMLEFTBOTTOMLEFT400,240", "on its last drawn spot")
    T.eq(rel, UIParent)
    T.eq(g:GetWidth(), 160)
    local w = words(g)
    T.truthy(w["Linen Cloth"], "its lines")
    local function spot(fs)
        local a, to, b, fx, fy = fs:GetPoint(1)
        T.eq(to, g)
        return a .. ">" .. b .. " " .. fx .. "," .. fy
    end
    T.eq(spot(w["Linen Cloth"]), "TOPLEFT>TOPLEFT 10,-10", "where they were")
    T.eq(spot(w["1s"]), "TOPRIGHT>TOPLEFT 150,-30", "a right line by its right edge")
    T.rgb(g.shell.opts.borderColor, { 0.9, 0.1, 0.1 }, "in the border color it had")
    T.isnil(rawget(tip, "SetAlpha"), "the game's tooltip itself never touched")
    tick(M.NORMAL / 2)
    T.truthy(g:GetAlpha() > 0 and g:GetAlpha() < 1, "fading")
    tick(M.NORMAL)
    T.falsy(g:IsShown(), "gone after NORMAL")

    -- Shown again mid-fade: the ghost goes and the new one rises from there.
    up()
    tip:Hide()
    tick(M.NORMAL / 2)
    local at = g:GetAlpha()
    stub.Advance(0.1)
    tip:Show()
    T.falsy(g:IsShown(), "the ghost goes as it shows again")
    T.near(tip:GetAlpha(), at, 0.01, "rising from where the ghost was")
    tick(M.NORMAL)
    T.eq(tip:GetAlpha(), 1)

    -- Hidden and shown again in one frame: never drawn as gone.
    up()
    tip:Hide()
    tip:Show()
    T.falsy(g:IsShown(), "a refill leaves no ghost")

    up()
    stub.combat = true
    tip:Hide()
    T.falsy(g:IsShown(), "in combat it just goes")
    stub.combat = false
    up()
    DaylightUI.DB.General().motion = false
    tip:Hide()
    T.falsy(g:IsShown(), "motion off: it just goes")
    DaylightUI.DB.General().motion = nil
    up()
    function GameTooltipTextLeft1:GetLeft() return stub.Secret(410) end
    tip:Hide()
    T.falsy(g:IsShown(), "a line's spot secret: it just goes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: leaving something in the world, its ghost fades as it's muted", function()
    local Tip = login()
    stub.RunTimers()
    local G = stub.tooltip.TipGhost
    local tip = GameTooltip
    withLines(tip)
    _G.C_TooltipInfo = { GetWorldCursor = function() return nil end }
    stub.units.mouseover = nil
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    fill(tip, Enum.TooltipDataType.Unit, {}, { "Wolf" })
    tip:Show()
    function tip:GetRect() return 400, 240, 160, 60 end
    function tip:GetLeft() return 400 end
    function tip:GetTop() return 300 end
    for _, side in ipairs({ "Left", "Right" }) do
        local fs = _G["GameTooltipText" .. side .. "1"]
        function fs:GetLeft() return 410 end
        function fs:GetTop() return 290 end
        function fs:GetWidth() return 40 end
        function fs:GetHeight() return 14 end
    end
    stub.Advance(0.02)
    tip:GetScript("OnUpdate")(tip, 0.02)
    local d = DaylightUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
    tip:FadeOut()
    stub.FireEvent("WORLD_CURSOR_TOOLTIP_UPDATE", 0)
    stub.RunTimers()
    T.eq(tip:GetAlpha(), 0, "the tooltip itself out of sight at once")
    T.truthy(G.Of(tip) and G.Of(tip):IsShown(), "its ghost fades instead")
    tip:GetScript("OnHide")(tip)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: 1.12's lines fall back to plain lines in the Simple look", function()
    login(itemWorld)
    local at = withLines(GameTooltip)
    local me = DaylightUI.API.For("Pieces")
    local seen = {}
    me.AddTooltipLines("item", function(lines, data)
        seen.style = data.style
        lines.Row("Fish caught", 12)
        lines.Bar("Collected", 3, 8)
        lines.Tag("Rare find", { 0.2, 0.6, 1 })
        lines.Section("Fishing")
        lines.Tiles({ { "12", "caught" }, { "3", "today" } })
    end)
    local types = Enum.TooltipDataType
    fill(GameTooltip, types.Item, { id = 1001, hyperlink = "sword" })
    T.eq(seen.style, "simple", "told which look it's in")
    local n = GameTooltip:NumLines()
    T.eq(at(n - 4):GetText(), "Fish caught"); T.eq(at(n - 4, "Right"):GetText(), "12")
    T.eq(at(n - 3):GetText(), "Collected"); T.eq(at(n - 3, "Right"):GetText(), "3 / 8", "a bar as label and value / max")
    T.eq(at(n - 2):GetText(), "Rare find", "a tag as a line")
    T.near(at(n - 2).__textColor[3], 1, 1e-6, "in its color")
    T.eq(at(n - 1):GetText(), "Fishing")
    T.eq(at(n):GetText(), "12 caught · 3 today", "tiles as one line")
    fill(GameTooltip, types.Item, { id = 1001, hyperlink = "sword" })
    T.eq(GameTooltip:NumLines(), n, "a refill adds them once")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: world things and compare tooltips run their plugins; the look is asked and heard", function()
    local shop
    login(function()
        itemWorld()
        Enum.TooltipDataType.Object = 4
        shop = stub.CompareTooltip("ShoppingTooltip1")
    end)
    local at = withLines(GameTooltip)
    withLines(shop)
    local types = Enum.TooltipDataType
    local me = DaylightUI.API.For("Kinds")
    local seen = {}
    me.AddTooltipLines("world", function(lines, data) seen.world = data.name; lines.Row("Herbs", 3) end)
    me.AddTooltipLines("compare", function(_, data) seen.compare = data.link end)
    local heard = {}
    DaylightUI.API.On("TooltipStyleChanged", function(style) heard[#heard + 1] = style end)
    fill(GameTooltip, types.Object, {}, { "Peacebloom" })
    T.eq(seen.world, "Peacebloom", "a world thing's name")
    local n = GameTooltip:NumLines()
    T.eq(at(n):GetText(), "Herbs")
    fill(shop, types.Item, { id = 1001, hyperlink = "sword" })
    T.eq(seen.compare, "sword", "the item you have on")
    T.eq(DaylightUI.API.TooltipStyle(), "simple")
    DaylightUI:Set("Tooltip", "style", "rich")
    stub.RunTimers()
    T.eq(DaylightUI.API.TooltipStyle(), "rich")
    T.deq(heard, { "rich" }, "heard once, as it switched")
    DaylightUI:Set("Tooltip", "style", "simple")
    stub.RunTimers()
    T.deq(heard, { "rich", "simple" })
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("tooltip: the card's own lines end at the last one the game drew, not at its data's count", function()
    login(itemWorld)
    local Own = stub.tooltip.Rich.Own
    -- A recipe's spell, as the game hands it: an empty spacer second that adds
    -- no line, so four drawn lines from five data lines, then another addon's.
    local recipe = { lines = { { type = 13, lineIndex = 1 }, { type = 0, leftText = "", rightText = "", lineIndex = 1 },
        { leftText = "Reagents: Bronze Tube", lineIndex = 2 }, { leftText = "Requires Engineering (190)", lineIndex = 3 },
        { type = 34, leftText = "Teaches you how to make a mortar.", lineIndex = 4 } } }
    T.eq(Own(recipe, 5), 4, "the fifth line is the other addon's")
    -- An item's SellPrice line has no words: stamped with the line above, its
    -- coins drawn one below by the game's post-call. Those coins are the game's.
    local ring = { lines = { { type = 22, leftText = "Ring", lineIndex = 1 }, { leftText = "+7 Stamina", lineIndex = 2 },
        { type = 11, price = 4630, lineIndex = 2 } } }
    T.eq(Own(ring, 4), 3, "the coins line is the game's, the fourth another addon's")
    T.eq(Own({ lines = { {}, {}, {} } }, 5), 3, "no line indexes: the data's count, as before")
    T.eq(Own({ lines = {} }, 5), 5, "no lines of its own: all are the card's")
    T.eq(Own({ lines = { { lineIndex = stub.Secret(1) }, {} } }, 4), 2, "a secret index is skipped")
end)

-- A recipe's spacer draws no line, so every data line after it sits one line
-- higher. Read by data position, the line under the sell price (an Auction
-- price added by an addon) took the SellPrice type, and the card showed the
-- crafted item's auction price as the recipe's vendor price.
T.test("tooltip: a recipe's drawn lines take their own data line's type, past the spacer", function()
    login(itemWorld)
    local Read = stub.tooltip.RichRead
    local tip = GameTooltip
    withLines(tip)
    tip:AddLine("Schematic: EZ-Thro Bronze Mortar", 1, 1, 1)
    tip:AddLine("Requires Engineering (190)", 1, 0, 0)
    tip:AddDoubleLine("Sell Price:", "6s", 1, 1, 1, 1, 1, 1)
    tip:AddDoubleLine("Auction", "95s", 1, 1, 1, 1, 1, 1)
    local data = { lines = {
        { type = 0, leftText = "Schematic: EZ-Thro Bronze Mortar", lineIndex = 1 },
        { type = 0, leftText = "", rightText = "", lineIndex = 1 },
        { type = 23, leftText = "Requires Engineering (190)", lineIndex = 2 },
        { type = 11, leftText = "Sell Price:", lineIndex = 3 },
    } }
    local n, lines = Read.Lines(tip, data)
    T.eq(n, 4)
    T.eq(lines[2].type, 23, "the second drawn line is the Requires line")
    T.eq(lines[3].type, 11, "the sell price keeps its own type")
    T.eq(lines[4].type, nil, "the Auction line is another addon's, with no type")
    -- Data with no line indexes: matched by position, as before.
    local plain = { lines = { { type = 0 }, { type = 23 }, { type = 11 } } }
    n, lines = Read.Lines(tip, plain)
    T.eq(lines[3].type, 11)
    T.eq(lines[4].type, nil)
end)

-- The game compares an item with what you wear when its alwaysCompareItems
-- setting is on or Shift is held, unless the tooltip's flag says no
-- (TooltipUtil.ShouldDoItemComparison, GameTooltip_SuppressAutomaticCompareItem;
-- its OnHide clears the flag).
T.test("tooltip: an item compares with what you wear only while Shift is held, unless switched back on", function()
    local cvar, shift = true, false
    local Tip = login(function()
        _G.GetCVarBool = function(name) return name == "alwaysCompareItems" and cvar end
        _G.IsModifiedClick = function(what) return what == "COMPAREITEMS" and shift end
        _G.GameTooltip_SuppressAutomaticCompareItem = function(tip) tip.suppressAutomaticCompareItem = true end
    end)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local function compares()
        GameTooltip.suppressAutomaticCompareItem = false
        for _, fn in ipairs(pre[Enum.TooltipDataType.Item] or {}) do fn(GameTooltip, { type = 0 }) end
        local auto = not GameTooltip.suppressAutomaticCompareItem and GetCVarBool("alwaysCompareItems")
        return (auto or IsModifiedClick("COMPAREITEMS")) and true or false
    end
    T.eq(compares(), false, "the game's always compare is on, but no Shift: the item stands alone")
    shift = true
    T.eq(compares(), true, "Shift shows what you wear")
    shift = false
    DaylightUI:Set("Tooltip", "compareItems", true)
    stub.Advance(0.1)
    T.eq(compares(), true, "switched on: the game's setting decides again")
    cvar = false
    T.eq(compares(), false, "and with it off, nothing compares")
    T.truthy(type(Tip.NoAutoCompare) == "function")
end)
