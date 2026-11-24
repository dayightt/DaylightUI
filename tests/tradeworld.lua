-- A fake TradeFrame laid out as the game's (Blizzard_UIPanels_Game/Mainline/
-- TradeFrame.xml, MoneyInputFrame.xml, MoneyFrame.xml): every piece its skin
-- touches, by the same names, sizes and anchors. Its trade logic isn't copied:
-- TW.Fill writes what TradeFrame.lua's updates would.
local stub = require("stub")

local TW = {}

local function tex(parent, name, layer)
    return parent:CreateTexture(name, layer or "BACKGROUND")
end

-- InsetFrameTemplate: its own art, anchored by two corners to the window.
local function inset(f, name, x1, y1, x2, y2)
    local i = CreateFrame("Frame", name, f)
    i:SetPoint("TOPLEFT", f, "TOPLEFT", x1, y1)
    i:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", x2, y2)
    i.Bg = tex(i)
    i.Bg:SetAllPoints(i)
    i.NineSlice = CreateFrame("Frame", nil, i)
    i.NineSlice:SetAllPoints(i)
    return i
end

-- TradeItemTemplate with its ItemButton (37 x 37) and name.
local function item(f, name)
    local r = CreateFrame("Frame", name, f)
    r:SetSize(153, 37)
    r.SlotTexture = tex(r, name .. "SlotTexture")
    r.SlotTexture:SetSize(64, 64)
    r.SlotTexture:SetPoint("TOPLEFT", r, "TOPLEFT", -13, 13)
    local nf = tex(r, name .. "NameFrame")
    nf:SetSize(124, 64)
    nf:SetPoint("LEFT", r.SlotTexture, "RIGHT", -20, 0)
    local label = r:CreateFontString(name .. "Name")
    label:SetSize(90, 30)
    label:SetPoint("LEFT", nf, "LEFT", 15, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 0.82, 0)   -- GameFontNormalSmall
    local b = CreateFrame("Button", name .. "ItemButton", r)
    b:SetSize(37, 37)
    b:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    b.icon = b:CreateTexture(name .. "ItemButtonIconTexture", "BORDER")
    b.icon:SetAllPoints(b)
    b.IconBorder = b:CreateTexture(nil, "OVERLAY")
    b.IconBorder:SetAllPoints(b)
    b.Count = b:CreateFontString()
    local normal = b:CreateTexture()
    normal:SetAllPoints(b)
    function b:GetNormalTexture() return normal end
    return r
end

local function column(f, prefix, x)
    local rows = {}
    for i = 1, 7 do
        local r = item(f, prefix .. i)
        if i == 1 then
            r:SetPoint("TOPLEFT", f, "TOPLEFT", x, -89)
        else
            r:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, i == 7 and -28 or -7)
        end
        rows[i] = r
    end
    return rows
end

-- TradeHighlightTemplate: green art, shown while that side has accepted.
local function highlight(f, name)
    local h = CreateFrame("Frame", name, f)
    for _, part in ipairs({ "Top", "Bottom", "Middle" }) do
        local t = tex(h, name .. part, "ARTWORK")
        t:SetAllPoints(h)
    end
    h:Hide()
    return h
end

local function textButton(f, name, text, w)
    local b = CreateFrame("Button", name, f)
    b:SetSize(w, 22)
    b.Left, b.Middle, b.Right = tex(b), tex(b), tex(b)
    local label = b:CreateFontString()
    label:SetText(text)
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    function b:GetFontString() return label end
    b.Text = label
    return b
end

function TW.Install()
    _G.MoneyFrame_Update = _G.MoneyFrame_Update or function() end
    local f = CreateFrame("Frame", "TradeFrame", UIParent)
    f:SetSize(344, 446)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    f:Hide()
    -- ButtonFrameTemplate
    f.NineSlice = CreateFrame("Frame", nil, f)
    f.NineSlice:SetAllPoints(f)
    f.Bg = tex(f)
    f.Bg:SetAllPoints(f)
    f.TitleContainer = CreateFrame("Frame", nil, f)
    f.TitleContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 58, -1)
    f.TitleContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -1)
    f.TitleContainer:SetHeight(20)
    f.TitleContainer.TitleText = f.TitleContainer:CreateFontString()
    f.CloseButton = CreateFrame("Button", "TradeFrameCloseButton", f)
    f.CloseButton:SetSize(24, 24)
    f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    local closeArt = tex(f.CloseButton)
    function f.CloseButton:GetNormalTexture() return closeArt end
    f.Inset = inset(f, "TradeFrameInset", 4, -60, 340, -420)
    f.Inset:Hide()

    -- The other side's own frame art.
    local corner = tex(f, "TradeRecipientBotLeftCorner")
    corner:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -178, -3)
    local border = tex(f, "TradeRecipientLeftBorder")
    border:SetPoint("TOPLEFT", f, "TOPRIGHT", -178, -50)
    border:SetPoint("BOTTOMLEFT", corner, "TOPLEFT")
    f.leftBorderBar = border
    local bg = tex(f, "TradeRecipientBG")
    bg:SetPoint("TOPLEFT", f, "TOPRIGHT", -172, -20)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")

    local mine = f:CreateFontString("TradeFramePlayerNameText")
    mine:SetSize(100, 12)
    mine:SetPoint("TOPLEFT", f, "TOPLEFT", 65, -5)
    local theirs = f:CreateFontString("TradeFrameRecipientNameText")
    theirs:SetSize(80, 12)
    theirs:SetPoint("TOPLEFT", f, "TOPLEFT", 230, -5)
    local enchant = f:CreateFontString("TradeFramePlayerEnchantText")
    enchant:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -360)
    enchant:SetText("Will not be traded")
    local enchant2 = f:CreateFontString("TradeFrameRecipientEnchantText")
    enchant2:SetPoint("LEFT", enchant, "LEFT", 166, 0)
    enchant2:SetText("Will not be traded")

    f.RecipientOverlay = CreateFrame("Frame", nil, f)
    f.RecipientOverlay:SetPoint("TOPLEFT", f, "TOPRIGHT", -180, 7)
    f.RecipientOverlay:SetSize(60, 60)
    f.RecipientOverlay.portrait = tex(f.RecipientOverlay)
    f.RecipientOverlay.portraitFrame = tex(f.RecipientOverlay)

    local hp = highlight(f, "TradeHighlightPlayer")
    hp:SetSize(150, 266)
    hp:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -85)
    local hr = highlight(f, "TradeHighlightRecipient")
    hr:SetSize(150, 266)
    hr:SetPoint("TOPLEFT", f, "TOPLEFT", 176, -85)
    local hpe = highlight(f, "TradeHighlightPlayerEnchant")
    hpe:SetSize(150, 61)
    hpe:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -4)
    local hre = highlight(f, "TradeHighlightRecipientEnchant")
    hre:SetSize(150, 61)
    hre:SetPoint("TOPLEFT", hr, "BOTTOMLEFT", 0, -4)

    inset(f, "TradeRecipientItemsInset", 175, -83, 338, -352)
    inset(f, "TradeRecipientEnchantInset", 175, -354, 338, -418)
    inset(f, "TradePlayerItemsInset", 4, -83, 166, -352)
    inset(f, "TradePlayerEnchantInset", 4, -354, 166, -418)
    TW.recipient = column(f, "TradeRecipientItem", 182)
    TW.player = column(f, "TradePlayerItem", 14)

    f.TradeButton = textButton(f, "TradeFrameTradeButton", "Trade", 85)
    f.TradeButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -85, 5)
    f.CancelButton = textButton(f, "TradeFrameCancelButton", "Cancel", 77)
    f.CancelButton:SetPoint("TOPLEFT", f.TradeButton, "TOPRIGHT", 3, 0)

    inset(f, "TradePlayerInputMoneyInset", 4, -58, 166, -82)
    local mf = CreateFrame("Frame", "TradePlayerInputMoneyFrame", f)
    mf:SetSize(176, 18)
    mf:SetPoint("TOPLEFT", f, "TOPLEFT", 11, -61)
    local prev
    -- MoneyInputFrame_SetCompact(self, 62, 7, 35) in its OnLoad.
    for _, c in ipairs({ { "gold", 62 }, { "silver", 35 }, { "copper", 35 } }) do
        local box = CreateFrame("EditBox", "TradePlayerInputMoneyFrame" .. c[1], mf)
        box:SetSize(c[2], 20)
        if prev then box:SetPoint("LEFT", prev, "RIGHT", 10, 0) else box:SetPoint("TOPLEFT", mf, "TOPLEFT", 0, 0) end
        box.left, box.right, box.Middle = tex(box), tex(box), tex(box)
        box.left:SetPoint("TOPLEFT", box, "TOPLEFT", -5, 0)
        box.left:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", -5, 0)
        box.left:SetWidth(8)
        box.right:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
        box.right:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        box.right:SetWidth(8)
        box.Left, box.Right = box.left, box.right
        box.texture = box:CreateTexture(nil, "OVERLAY")
        box.texture:SetSize(13, 13)
        box.texture:SetPoint("RIGHT", box, "RIGHT", -4, 0)
        box.texture:SetAtlas("coin-" .. c[1])
        box.label = box:CreateFontString()
        box.label:SetPoint("RIGHT", box, "RIGHT", -4, 0)
        box.label:Hide()
        mf[c[1]] = box
        prev = box
    end
    -- TradeFrame_OnLoad: TradePlayerInputMoneyFrame:SetForbidden().
    mf.__forbidden = true

    inset(f, "TradeRecipientMoneyInset", 175, -58, 338, -81)
    local rbg = CreateFrame("Frame", "TradeRecipientMoneyBg", f)
    rbg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -7, -60)
    rbg:SetPoint("BOTTOMLEFT", f, "TOPRIGHT", -168, -80)
    rbg.Left, rbg.Right, rbg.Middle = tex(rbg), tex(rbg), tex(rbg)
    local rm = CreateFrame("Frame", "TradeRecipientMoneyFrame", f)
    rm:SetSize(160, 13)
    rm:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -64)
    local right
    for _, key in ipairs({ "CopperButton", "SilverButton", "GoldButton" }) do
        local b = CreateFrame("Button", nil, rm)
        b:SetSize(30, 13)
        if right then b:SetPoint("RIGHT", right, "LEFT", -4, 0) else b:SetPoint("RIGHT", rm, "RIGHT", -13, 0) end
        local coin = b:CreateTexture()
        coin:SetSize(13, 13)
        coin:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        coin:SetAtlas("coin-gold")
        function b:GetNormalTexture() return coin end
        b.Text = b:CreateFontString()
        b.Text:SetPoint("RIGHT", b, "RIGHT", -13, 0)
        rm[key] = b
        right = b
    end
    -- TradeFrame_OnLoad: each inset keeps its marble art, the other side's dimmed.
    TradeRecipientItemsInset.Bg:SetAlpha(0.1)
    TradeRecipientMoneyInset.Bg:SetAlpha(0)
    TradeRecipientEnchantInset.Bg:SetAlpha(0.1)
    rbg:SetAlpha(0.6)
    return f
end

-- What TradeFrame.lua writes on its updates: names, each side's items (name in
-- its quality color, icon, border) and money.
function TW.Fill(f, spec)
    TradeFramePlayerNameText:SetText(spec.me or "Tester")
    TradeFrameRecipientNameText:SetText(spec.them or "Someone")
    local q = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 } }
    for side, rows in pairs({ mine = TW.player, theirs = TW.recipient }) do
        for i, r in ipairs(rows) do
            local it = spec[side] and spec[side][i]
            local b = _G[r:GetName() .. "ItemButton"]
            local label = _G[r:GetName() .. "Name"]
            if it then
                b.icon:SetTexture(it.icon or 134400)
                b.icon:Show()
                local c = q[it.quality or 1]
                b.IconBorder:SetVertexColor(c[1], c[2], c[3])
                b.IconBorder:SetShown((it.quality or 1) > 1)
                label:SetText(it.name)
                label:SetTextColor(c[1], c[2], c[3])
            else
                b.icon:SetTexture(nil)
                b.IconBorder:Hide()
                label:SetText("")
            end
            if _G.SetItemButtonQuality then _G.SetItemButtonQuality(b) end
        end
    end
    TradePlayerInputMoneyFrame.gold:SetText(spec.gold or "")
    for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        TradeRecipientMoneyFrame[key].Text:SetText(spec.theirMoney and spec.theirMoney[key] or "0")
    end
    if spec.accepted then TradeHighlightRecipient:Show(); TradeHighlightRecipientEnchant:Show() end
    f:Show()
    stub.RunTimers()
end

return TW
