-- System pack: game menu, addon list, macros, clock, loot, socketing and item
-- upgrades, the scrapper, the auction house, and the world map's frame. Each is
-- Engine.Window plus anything unique to it.
--
-- Deliberately left as the game draws them: the settings panel and the
-- dungeon-ready dialog.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine


-- Game menu: its dialog border (a separate frame) and header art go;
-- Kit.Window puts the title in the title row.
Engine.Window({ key = "gamemenu", pack = "system", frame = "GameMenuFrame", hide = { ".Border" },
    after = function(Kit, f)
        if type(f.Header) == "table" then Kit.Strip(f.Header) end
    end })
Engine.Window({ key = "addons", pack = "system", frame = "AddonList", watch = true })
Engine.Window({ key = "macros", pack = "system", addon = "Blizzard_MacroUI", frame = "MacroFrame", watch = true })
Engine.Window({ key = "clock", pack = "system", addon = "Blizzard_TimeManager", frame = "TimeManagerFrame" })
-- Loot window: each item becomes one of our rows (the game's square card,
-- quality tint and hover glow removed; quality shows in the name and the icon
-- outline). The row takes no mouse itself. Its item button spans the row, so
-- the row lights from that. No animation of its own: an earlier light sweep was
-- removed after it left a stuck white card on some rows.
local function lootRow(row)
    local Kit = ns.Kit
    if type(row) ~= "table" or type(row.Item) ~= "table" or type(row.NameFrame) ~= "table" then return end
    Kit.Row(row, { [row.IconQuestTexture or row] = true }, nil, nil, row.Item)
    Kit.Font(row.Text, DUI.Style.SIZE.body)
    Kit.Font(row.QualityText, DUI.Style.SIZE.tiny)
    Kit.Light(row.QualityText, DUI.Style.INK.LABEL)
end

Engine.Window({ key = "loot", pack = "system", frame = "LootFrame", watch = true,
    after = function(Kit, f) Kit.EachRow(f.ScrollBox, lootRow, "lootrow") end })
-- Group loot rolls: each popup gets our window look with a quality-colored line
-- on top, the icon outlined in that color, the name on one line above a sub line
-- (slot, "BoP" in the warn color), and Need/Greed/Pass in a row of our control
-- boxes. The game's dice and coins are kept since nothing reads faster. The
-- timer is our pill bar following the game's hidden one, with seconds left; in
-- the last quarter it turns the warn color and pulses.
-- Motion: out of combat the popup glides up while fading in. Always (our own
-- pieces only) the top line draws out from the left and a quality-colored light
-- sweeps across. Closing leaves the window's fading ghost.
-- The game reuses and positions the popups itself (the container is left
-- alone), so they're revisited whenever one is added or the rolls change. Our
-- additions live in `rolls`, never in fields on the game's frames.
local LootRoll = {
    BUTTON = 26, -- roll button box size
    BUTTON_GAP = 4,
    BUTTON_PAD = 2, -- dice inset inside the box
    PAD = 10, -- popup inner padding
    LINE = 2, -- quality line height
    WARN_AT = 0.25, -- fraction of time left when the timer turns to warn
    SWEEP = { width = 110, dur = 0.7, alpha = 0.45 },
    RISE = 14, -- px the popup glides up when opening
}
ns.LootRoll = LootRoll
local rolls = setmetatable({}, { __mode = "k" }) -- popup -> our pieces

local function rollInfo(f)
    if type(f.rollID) ~= "number" or type(GetLootRollItemInfo) ~= "function" then return nil end
    local ok, _, _, _, quality, bop = pcall(GetLootRollItemInfo, f.rollID)
    if not ok then return nil end
    return quality, bop
end

local function qualityColor(quality)
    if type(quality) ~= "number" then return nil end
    local getColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if type(getColor) ~= "function" then return nil end
    local r, g, b = getColor(quality)
    if type(r) ~= "number" then return nil end
    return { r, g, b }
end

-- The item's slot ("Back", "Two-Hand"), or else its type ("Recipe"), in the
-- game's own words.
function LootRoll.Words(link)
    local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if type(link) ~= "string" or type(instant) ~= "function" then return nil end
    local ok, _, itemType, subType, equipLoc = pcall(instant, link)
    if not ok then return nil end
    local word = type(equipLoc) == "string" and equipLoc ~= "" and _G[equipLoc]
    if type(word) == "string" and word ~= "" then return word end
    if type(subType) == "string" and subType ~= "" then return subType end
    return type(itemType) == "string" and itemType or nil
end

local function slotText(f)
    if type(GetLootRollItemLink) ~= "function" then return nil end
    local ok, link = pcall(GetLootRollItemLink, f.rollID)
    return ok and LootRoll.Words(link) or nil
end

-- Timer colors: the accent pair, or the warn color's pair near the end.
local function paintTimer(r)
    local W = DUI.Widgets
    if r.low then
        local c = DUI.Style.INK.WARN
        W.BarFrom(r.bar, c[1], c[2], c[3])
    else
        W.BarAccent(r.bar)
    end
end

-- Near the end the fill pulses its alpha down and back while low and shown.
-- With motion off it stays steady.
local function breathe(r, down)
    local M = DUI.Motion
    if not (r.low and M and M.On() and r.bar:IsVisible()) then
        r.bar.fill:SetAlpha(1)
        return
    end
    M.Tween(r, down and 1 or 0.45, down and 0.45 or 1, M.SLOW, function(a) r.bar.fill:SetAlpha(a) end,
        function() breathe(r, not down) end)
end

local function followTimer(r, timer)
    local ok, lo, hi = pcall(timer.GetMinMaxValues, timer)
    local v = timer:GetValue()
    if not ok then return end
    r.bar:SetMinMaxValues(lo, hi)
    r.bar:SetValue(v)
    if issecretvalue and (issecretvalue(v) or issecretvalue(hi)) then return end
    if type(v) ~= "number" or type(hi) ~= "number" or hi <= 0 then return end
    local secs = math.max(0, math.ceil(v / 1000))
    if secs ~= r.secs then
        r.secs = secs
        r.time:SetText(secs .. "s")
    end
    local low = v / hi <= LootRoll.WARN_AT and v > 0
    if low ~= r.low then
        r.low = low
        paintTimer(r)
        DUI.Style.InkText(r.time, low and "WARN" or "pop")
        breathe(r, true)
    end
end

-- Each time a roll opens on the popup: colors, sub line, motion.
local function openRoll(Kit, f)
    local r = rolls[f]
    if not r then return end
    local Style, M = DUI.Style, DUI.Motion
    local quality, bop = rollInfo(f)
    local color = qualityColor(quality)
    if type(f.IconFrame) == "table" then Kit.Paint(Kit.ShellOf(f.IconFrame), color) end
    local lo, hi = DUI.Gradients.PairFrom(color or { Style.Accent() })
    DUI.Gradients.PaintPair(r.line, lo, hi)
    local slot = slotText(f)
    local L = DUI.L
    local sub = slot or ""
    if bop == true then
        local Parts = DUI.Win and DUI.Win.Parts
        local bopText = Parts and (Parts.Hex(Style.INK.WARN) .. L["BoP"] .. "|r") or L["BoP"]
        sub = slot and (slot .. "  ·  " .. bopText) or bopText
    end
    r.sub:SetText(sub)
    r.secs, r.low = nil, nil
    r.bar.fill:SetAlpha(1)
    paintTimer(r)
    Style.InkText(r.time, "pop")
    if f.Timer then followTimer(r, f.Timer) end
    if not (M and M.On()) then
        r.line:SetWidth(r.lineWidth())
        return
    end
    -- The line draws out, then the light sweeps across.
    M.Tween(r.line, 0, 1, M.SLOW, function(p) r.line:SetWidth(math.max(0.01, r.lineWidth() * p)) end)
    local s = LootRoll.SWEEP
    M.Sweep(r.sweep, f, { width = s.width, dur = s.dur, alpha = s.alpha, color = color or { 1, 0.95, 0.85 },
        key = r.sweep })
    if not (InCombatLockdown and InCombatLockdown()) and r.rise then
        r.rise:Stop()
        r.rise:Play()
    end
end

-- The glide up on open: drawn RISE px low, easing back to rest. Visual only,
-- the popup itself never moves. State lives in our table, not in
-- Motion.Glide's field on the frame.
local function riseOf(f)
    if not f.CreateAnimationGroup then return nil end
    local g = f:CreateAnimationGroup()
    local jump = g:CreateAnimation("Translation")
    jump:SetOffset(0, -LootRoll.RISE)
    jump:SetDuration(0)
    jump:SetOrder(1)
    local move = g:CreateAnimation("Translation")
    move:SetOffset(0, LootRoll.RISE)
    move:SetDuration(DUI.Motion.NORMAL)
    move:SetOrder(2)
    move:SetSmoothing("OUT")
    return g
end

local function dress(Kit, f)
    if rolls[f] then return rolls[f] end
    local Style, Pixel, W = DUI.Style, DUI.Pixel, DUI.Widgets
    if not (W and W.Bar) then return nil end
    Kit.Window(f)
    local r = {}
    rolls[f] = r
    local P = LootRoll.PAD

    -- The quality line on top, inside the border.
    local edge = Pixel.Px(f, 1)
    r.line = f:CreateTexture(nil, "OVERLAY", nil, 6)
    r.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    r.line:SetPoint("TOPLEFT", f, "TOPLEFT", edge, -edge)
    r.line:SetHeight(Pixel.Px(f, LootRoll.LINE))
    function r.lineWidth() return math.max(0.01, (f:GetWidth() or 0) - 2 * edge) end
    r.line:SetWidth(r.lineWidth())

    -- The light that sweeps across when a roll opens.
    r.sweep = f:CreateTexture(nil, "OVERLAY", nil, 7)
    r.sweep:SetTexture(DUI.MEDIA .. "glow.png")
    r.sweep:SetBlendMode("ADD")
    r.sweep:SetHeight((f:GetHeight() or 67) * 1.6)
    r.sweep:Hide()

    -- The icon, outlined in the quality color.
    local icon = f.IconFrame
    if type(icon) == "table" then
        Kit.Item(icon)
        for _, key in ipairs({ "Border", "IconBorder" }) do Kit.Erase(icon[key]) end
    end

    -- Buttons in a row on the right: Need, Greed (or Transmog when the game
    -- shows that instead), Pass.
    local box = f.LootButtonContainer
    local need, greed, pass
    if type(box) == "table" then
        need, greed, pass = box.NeedButton, box.GreedButton, box.PassButton
        local B, G = LootRoll.BUTTON, LootRoll.BUTTON_GAP
        for _, b in ipairs({ need, greed, pass, box.TransmogButton }) do
            if type(b) == "table" and b.SetSize then
                b:SetSize(B, B)
                Kit.ArtButton(b, LootRoll.BUTTON_PAD)
            end
        end
        if type(pass) == "table" and type(greed) == "table" and type(need) == "table" then
            local up = Pixel.Px(f, 3)
            pass:ClearAllPoints()
            pass:SetPoint("RIGHT", f, "RIGHT", -P, up)
            greed:ClearAllPoints()
            greed:SetPoint("RIGHT", pass, "LEFT", -G, 0)
            need:ClearAllPoints()
            need:SetPoint("RIGHT", greed, "LEFT", -G, 0)
        end
    end

    -- Name on one line, sub line below.
    local name = f.Name
    if type(name) == "table" and name.SetPoint then
        Kit.Font(name, Style.SIZE.body)
        name:ClearAllPoints()
        if type(icon) == "table" then
            name:SetPoint("TOPLEFT", icon, "TOPRIGHT", P, -1)
        else
            name:SetPoint("TOPLEFT", f, "TOPLEFT", P, -P)
        end
        if type(need) == "table" then name:SetPoint("RIGHT", need, "LEFT", -P, 0) end
        name:SetHeight(Style.SIZE.body + 4)
        if name.SetWordWrap then name:SetWordWrap(false) end
        name:SetJustifyV("MIDDLE")
    end
    r.sub = Style.Text(f, Style.SIZE.small, "LEFT")
    Style.InkText(r.sub, "LABEL")
    if type(name) == "table" and name.GetObjectType then
        r.sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
        r.sub:SetPoint("RIGHT", name, "RIGHT", 0, 0)
    end
    if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end

    -- The timer: the game's runs hidden, ours follows it.
    r.bar = W.Bar(f, W.BAR_H)
    r.bar:SetFrameLevel((f:GetFrameLevel() or 0) + 2)
    r.time = Style.Text(r.bar, Style.SIZE.tiny, "RIGHT")
    r.time:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -P, P - 3)
    r.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
    r.bar:SetPoint("RIGHT", f, "RIGHT", -(P + 28), 0)
    local timer = f.Timer
    if type(timer) == "table" and timer.HookScript then
        Kit.Hide(timer)
        timer:HookScript("OnValueChanged", function() DUI.SafeCall(followTimer, r, timer) end)
    end

    r.rise = riseOf(f)
    if f.HookScript then
        f:HookScript("OnShow", function() DUI.SafeCall(openRoll, Kit, f) end)
        f:HookScript("OnHide", function()
            r.low = nil
            if r.rise then r.rise:Stop() end
        end)
    end
    if f:IsShown() then openRoll(Kit, f) end
    return r
end

local function skinRoll(Kit, f)
    if type(f) ~= "table" or not f.GetObjectType then return end
    if f.IsForbidden and f:IsForbidden() then return end
    dress(Kit, f)
end

-- For tests.
function LootRoll.Of(f) return rolls[f] end

Engine.Register({ key = "lootroll", pack = "system", apply = function(Kit)
    local function all()
        for i = 1, 8 do skinRoll(Kit, _G["GroupLootFrame" .. i]) end
        local c = _G.GroupLootContainer
        if type(c) == "table" and type(c.rollFrames) == "table" then
            for _, f in pairs(c.rollFrames) do skinRoll(Kit, f) end
        end
    end
    local pending = false
    local function soon()
        if pending then return end
        pending = true
        C_Timer.After(0, function()
            pending = false
            DUI.SafeCall(all)
        end)
    end
    for _, fn in ipairs({ "GroupLootContainer_AddFrame", "GroupLootContainer_Update" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, soon) end
    end
    DUI.RegisterEvent("START_LOOT_ROLL", soon)
    all()
end })

-- Loot toasts ("You received", money): our window look on a box the size of the
-- game's art, with its gold toast, glow and sheen removed and the item icon
-- outlined in quality color. The need/greed icon and roll stay. The game pools
-- these and sets one up before showing it, so each is dressed once on first
-- show and recolored every time.
local function itemQuality(link)
    if type(link) ~= "string" then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local getColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if type(getInfo) ~= "function" or type(getColor) ~= "function" then return nil end
    local ok, _, _, quality = pcall(getInfo, link)
    if not ok or type(quality) ~= "number" then return nil end
    local r, g, b = getColor(quality)
    if type(r) ~= "number" then return nil end
    return { r, g, b }
end

local toasts = setmetatable({}, { __mode = "k" })

local function toastBox(Kit, f, inset)
    Kit.Strip(f, { [f.RollTypeIcon or f] = true })
    Kit.Outline(f, -inset, "window")
    -- Erased rather than faded: in game the toast's background came back at
    -- full alpha by the next toast without any visible call setting it, so a
    -- transparent mask keeps every background it can pick hidden.
    for _, key in ipairs({ "glow", "shine", "Background", "BGAtlas", "PvPBackground", "RatedPvPBackground" }) do
        Kit.Erase(f[key])
    end
    Kit.Font(f.Label, DUI.Style.SIZE.small)
end

local function lootToast(Kit, f)
    if not toasts[f] then
        toasts[f] = true
        toastBox(Kit, f, 10)
        local item = f.lootItem
        if type(item) == "table" then
            Kit.Item(item)
            for _, key in ipairs({ "ItemBorderGlow", "IconBorderDropShadow" }) do Kit.Erase(item[key]) end
        end
        Kit.Font(f.ItemName, DUI.Style.SIZE.body)
        Kit.Font(f.RollValue, DUI.Style.SIZE.small)
    end
    -- nil (a currency, or an item not cached yet): use the outline's own color.
    if type(f.lootItem) == "table" then Kit.Paint(Kit.ShellOf(f.lootItem), itemQuality(f.hyperlink)) end
end

local function moneyToast(Kit, f)
    if toasts[f] then return end
    toasts[f] = true
    toastBox(Kit, f, 8)
    local icon = f.Icon
    if type(icon) == "table" and icon.SetTexCoord then
        DUI.Style.CropIcon(icon)
        Kit.Outline(icon, DUI.Pixel.Px(f, Kit.LOOK.outline.borderPx), "outline")
    end
    Kit.Hide(f.IconBorder)
    Kit.Font(f.Amount, DUI.Style.SIZE.body)
end

Engine.Register({ key = "loottoast", pack = "system", apply = function(Kit)
    if type(_G.AlertFrame_ShowNewAlert) ~= "function" then return end
    hooksecurefunc("AlertFrame_ShowNewAlert", function(f)
        if type(f) ~= "table" or f.queue == nil then return end
        if f.queue == _G.LootAlertSystem then
            DUI.SafeCall(lootToast, Kit, f)
        elseif f.queue == _G.MoneyWonAlertSystem then
            DUI.SafeCall(moneyToast, Kit, f)
        end
    end)
end })

Engine.Window({ key = "socketing", pack = "system", addon = "Blizzard_ItemSocketingUI", frame = "ItemSocketingFrame" })
Engine.Window({ key = "itemupgrade", pack = "system", addon = "Blizzard_ItemUpgradeUI", frame = "ItemUpgradeFrame" })
Engine.Window({ key = "scrapper", pack = "system", addon = "Blizzard_ScrappingMachineUI", frame = "ScrappingMachineFrame" })
Engine.Window({ key = "auction", pack = "system", addon = "Blizzard_AuctionHouseUI", frame = "AuctionHouseFrame", watch = true })

-- The layering notice (the game is about to move you to another copy of the
-- zone, and you can delay it): our window and font, the gold glow removed. Its
-- minimize button keeps its icon on our box. It fades in with the game's own
-- alert animation, not ours (Kit.Window ownFade).
Engine.Window({ key = "layering", pack = "system", addon = "Blizzard_SocialToast", frame = "ShardTransferImminentFrame",
    auto = false,
    window = { ownFade = true },
    after = function(Kit, f)
        Kit.Erase(_G.ShardTransferImminentFrameGlowFrame)
        Kit.Font(_G.ShardTransferImminentFrameText, DUI.Style.SIZE.body)
        local m = _G.ShardTransferImminentMinimizeButton
        if type(m) == "table" and m.CreateTexture and not (m.IsForbidden and m:IsForbidden()) then
            for _, key in ipairs({ "Center", "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
                Kit.Hide(m[key])
            end
            Kit.Shell(m, "window")
        end
    end })

-- Battle.net toasts (friend online/offline, broadcast, invite): our window and
-- font, icon kept, glow removed. The game grays the last line again on every
-- toast and combat pauses the skin's passes, so that line is set to tan from
-- the toast's own OnShow. Fades like the layering notice.
local toastHooked = false
local splitHooked = false -- the split box's OnShow repaint, hooked once
local function toastLine(fs)
    local text = fs:GetText()
    if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
        local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if plain ~= text then fs:SetText(plain) end
    end
    local c = DUI.Style.INK.LABEL
    fs:SetTextColor(c[1], c[2], c[3])
end

Engine.Window({ key = "bntoast", pack = "system", addon = "Blizzard_BNet", frame = "BNToastFrame",
    auto = false,
    window = { ownFade = true, keep = { "IconTexture" } },
    after = function(Kit, f)
        local SIZE, INK = DUI.Style.SIZE, DUI.Style.INK
        Kit.Erase(_G.BNToastFrameGlowFrame)
        Kit.Font(f.TopLine, SIZE.body)
        Kit.Font(f.MiddleLine, SIZE.small)
        Kit.Font(f.BottomLine, SIZE.small)
        Kit.Font(f.DoubleLine, SIZE.body, INK.TEXT)
        local tip = f.TooltipFrame
        if type(tip) == "table" then
            Kit.Panel(tip)
            Kit.Font(tip.Text, SIZE.small, INK.TEXT)
        end
        if toastHooked or type(f.BottomLine) ~= "table" then return end
        toastHooked = true
        f:HookScript("OnShow", function(self) toastLine(self.BottomLine) end)
        toastLine(f.BottomLine)
    end })

-- Confirmation boxes (destroying an item, leaving a group, typing a name): our
-- window, buttons and edit box. Their warning icon and progress bar are kept.
-- Dressed quietly, with nothing of the automatic walk: with the controller UI
-- on, the game stores each box's focus actions as it opens, and any hook on
-- the pieces inside would run first and taint them (Kit.Button).
for i = 1, 4 do
    Engine.Window({ key = "popup" .. i, pack = "system", frame = "StaticPopup" .. i,
        auto = false,
        window = { keep = { "AlertIcon", "ProgressBarBorder", "ProgressBarFill", "Separator" }, quiet = true },
        hide = { ".BG", ".Border" },
        after = function(Kit, f)
            local c = f.ButtonContainer
            if type(c) == "table" then
                for b = 1, 4 do Kit.Button(c["Button" .. b], f) end
            end
            Kit.Button(f.ExtraButton, f)
            Kit.EditBox(f.EditBox, f)
            Kit.Font(f.Text)
        end })
end

-- The stack split box (Shift-click a stack in your bags): our window, arrows and
-- buttons, the amount in the accent. The game moves its pieces and shows one of
-- two backgrounds on each open, so only their alpha is touched and its layout
-- stays.
Engine.Window({ key = "stacksplit", pack = "system", frame = "StackSplitFrame",
    auto = false,
    hide = { ".SingleItemSplitBackground", ".MultiItemSplitBackground" },
    after = function(Kit, f)
        local Style = DUI.Style
        Kit.PageButton(f.LeftButton, "left")
        Kit.PageButton(f.RightButton, "right")
        Kit.Button(f.OkayButton)
        Kit.Button(f.CancelButton)
        Kit.Font(f.StackSplitText, Style.SIZE.head)
        Kit.Font(f.StackItemCountText, Style.SIZE.small, Style.INK.LABEL)
        -- The amount is what you look at, so it gets the accent, read on open.
        local function pop() Style.InkText(f.StackSplitText, "pop") end
        pop()
        if not splitHooked and f.HookScript then
            splitHooked = true
            f:HookScript("OnShow", pop)
        end
    end })

-- The world map and the quest log beside it, looks only. The quest log feeds the
-- objective tracker, so its scripts, quest rows and the map's own buttons are
-- left alone. Nothing here does more than hide the game's art and draw ours.

-- A breadcrumb in the map's navigation bar ("World > Eastern Kingdoms").
local function crumb(Kit, btn)
    if type(btn) ~= "table" or not btn.GetRegions then return end
    Kit.Strip(btn)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if btn[get] then Kit.Hide(btn[get](btn)) end
    end
    Kit.Font(btn.text)
    Kit.Light(btn.text)
    -- Bare, like the rest of the slim top row (MapMove.Slim).
    local arrow = btn.MenuArrowButton
    if type(arrow) == "table" then Kit.BareButton(arrow) end
end

local function navBar(Kit, nav)
    if type(nav) ~= "table" or not nav.GetRegions then return end
    Kit.Strip(nav)
    for _, key in ipairs({ "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
                           "InsetBorderLeft", "InsetBorderRight" }) do
        Kit.Hide(nav[key])
    end
    if type(nav.overlay) == "table" then Kit.Strip(nav.overlay) end
    if not Kit.ShellOf(nav) then Kit.Shell(nav, "input") end
    crumb(Kit, nav.homeButton)
    if type(nav.navList) == "table" then
        for _, b in ipairs(nav.navList) do crumb(Kit, b) end
    end
end

-- The quest count box ("Quests: 15/40") right of the search box. Found by name
-- when possible; that name has moved before, so otherwise by scanning for a
-- child whose text mentions "Quests".
local function findQuestCount(qs)
    if type(_G.QuestLogCount) == "table" then return _G.QuestLogCount end
    if type(qs) ~= "table" then return end
    local contents = qs.Contents
    for _, host in ipairs({ qs, contents }) do
        if type(host) == "table" then
            for _, key in ipairs({ "QuestCount", "QuestsCount" }) do
                if type(host[key]) == "table" then return host[key] end
            end
        end
    end
    if type(contents) == "table" and contents.GetChildren then
        for _, c in ipairs({ contents:GetChildren() }) do
            -- Some of the list's children are forbidden frames; never ask
            -- them for their parts.
            if type(c) == "table" and c.GetRegions and not (c.IsForbidden and c:IsForbidden()) then
                for _, r in ipairs({ c:GetRegions() }) do
                    if r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText then
                        local t = r:GetText()
                        if type(t) == "string" and string.find(t, "Quest") then return c end
                    end
                end
            end
        end
    end
end

local function questCount(Kit, qs)
    local box = findQuestCount(qs)
    if type(box) ~= "table" or not box.GetRegions then return end
    Kit.Strip(box)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do Kit.Hide(box[key]) end
    Kit.Panel(box)
    for _, r in ipairs({ box:GetRegions() }) do
        if Kit.Kind(r) == "FontString" then
            Kit.Font(r)
            Kit.Light(r)
        end
    end
end

-- The quest log's zone headers ("Tirisfal Glades"): quiet rows, +/- kept. Quest
-- rows stay as the game draws them. The log updates often while the map is open,
-- and headers come from a pool that's never destroyed, so with no new children
-- and the same font every header is already done.
local headersSeen = setmetatable({}, { __mode = "k" }) -- contents -> child count when last visited
local headersFont = setmetatable({}, { __mode = "k" }) -- contents -> font at that time
local function questHeaders(Kit, contents)
    if type(contents) ~= "table" or not contents.GetChildren then return end
    local n = contents.GetNumChildren and contents:GetNumChildren()
    if type(n) == "number" then
        if headersSeen[contents] == n and headersFont[contents] == DUI.Style.FONT then return end
        headersSeen[contents], headersFont[contents] = n, DUI.Style.FONT
    end
    for _, c in ipairs({ contents:GetChildren() }) do
        if type(c.ButtonText) == "table" and type(c.CollapseButton) == "table" then
            Kit.Row(c, "art")
            Kit.Font(c.ButtonText)
        end
    end
end

-- A quest opened from the map's log: parchment, gold frame and button backdrop
-- removed (our window shows through), our buttons, a plain rewards header, and
-- each reward outlined in its quality. Rewards are built per quest shown, so
-- this reruns then. Looks only: the buttons still act for the quest log.
local stripped = setmetatable({}, { __mode = "k" }) -- details buttons whose art is gone
local function questDetails(Kit)
    local qm = _G.QuestMapFrame
    local d = type(qm) == "table" and qm.DetailsFrame
    if type(d) ~= "table" then return end
    -- The game colors this text dark for the parchment we removed.
    ns.LightQuestInfo(Kit)
    Kit.Hide(d.Bg)
    Kit.Erase(d.SealMaterialBG)
    Kit.Strip(d.BorderFrame)
    local back = d.BackFrame
    if type(back) == "table" then
        Kit.Strip(back)
        Kit.Button(back.BackButton)
    end
    for _, key in ipairs({ "AbandonButton", "ShareButton", "TrackButton" }) do
        local b = d[key]
        -- The dividers drawn on the middle button go with the rest of its art.
        -- Once only, since our outline is drawn on the button too.
        if type(b) == "table" and b.GetRegions and not stripped[b] then
            stripped[b] = true
            for _, r in ipairs({ b:GetRegions() }) do
                if Kit.Kind(r) == "Texture" and r ~= b:GetHighlightTexture() then Kit.Hide(r) end
            end
        end
        Kit.Button(b)
    end
    local sf = d.ScrollFrame
    if type(sf) == "table" then Kit.ScrollBar(sf.ScrollBar) end
    local container = d.RewardsFrameContainer
    local rf = type(container) == "table" and container.RewardsFrame
    if type(rf) == "table" then
        Kit.Hide(rf.Top)
        Kit.Hide(rf.Bottom)
        Kit.Hide(rf.Background)
        Kit.Font(rf.Label, DUI.Style.SIZE.head)
        Kit.Light(rf.Label, Kit.HEADER)
    end
    local rewards = _G.MapQuestInfoRewardsFrame
    if type(rewards) == "table" then
        for _, key in ipairs({ "ItemChooseText", "ItemReceiveText", "PlayerTitleText" }) do Kit.Light(rewards[key]) end
        if type(rewards.RewardButtons) == "table" then
            for _, b in ipairs(rewards.RewardButtons) do Kit.Item(b) end
        end
        for _, key in ipairs({ "XPFrame", "MoneyFrame", "HonorFrame", "SkillPointFrame", "ArtifactXPFrame", "WarModeBonusFrame" }) do
            Kit.Item(rewards[key])
        end
    end
end

local mapHooked = false
-- BorderFrame holds the close button, title and maximize button, so it's kept
-- and only its art is stripped.
Engine.Window({ key = "worldmap", pack = "system", frame = "WorldMapFrame", auto = false,
    window = { keep = { "BorderFrame" } },
    after = function(Kit, f)
        local border = f.BorderFrame
        if type(border) == "table" then
            Kit.Strip(border)
            Kit.Strip(border.PortraitContainer)
            Kit.Hide(border.NineSlice)
            Kit.Close(border.CloseButton)
            local title = type(border.TitleContainer) == "table" and border.TitleContainer.TitleText
            Kit.Font(title, DUI.Style.SIZE.title)
            Kit.Light(title)
            local mm = border.MaximizeMinimizeFrame
            if type(mm) == "table" then
                Kit.BareButton(mm.MinimizeButton, "down")
                Kit.BareButton(mm.MaximizeButton, "up")
            end
        end
        Kit.Hide(_G.WorldMapFramePortrait)
        navBar(Kit, f.NavBar)
        -- Skinned, its top is one slim row (MapMove.Slim).
        if type(ns.MapMove) == "table" then
            ns.MapMove.slim = true
            ns.MapMove.Apply()
        end
        -- The map's filter button sits in the top row (Forever puts it right of
        -- the zone buttons). Bare like them, with our "filters changed" badge.
        local filter = f.WorldMapTrackingOptionsButton
        if type(filter) == "table" then
            Kit.BareButton(filter)
            Kit.ResetBadge(filter.ResetButton)
        end
        -- The map's dropdowns along its top edge: either the game's dropdown
        -- type or a button whose icon is the dropdown arrow.
        if type(f.overlayFrames) == "table" then
            for _, o in ipairs(f.overlayFrames) do
                local k = Kit.Kind(o)
                local icon = type(o) == "table" and o.Icon
                local atlas = Kit.Kind(icon) == "Texture" and icon.GetAtlas and icon:GetAtlas()
                local arrow = type(atlas) == "string" and string.find(string.lower(atlas), "dropdown", 1, true)
                if o ~= filter and (k == "DropdownButton" or ((k == "Button" or k == "Frame") and arrow)) then Kit.Dropdown(o) end
            end
        end
        local toggle = f.SidePanelToggle
        if type(toggle) == "table" then
            Kit.PageButton(toggle.CloseButton, "left")
            Kit.PageButton(toggle.OpenButton, "right")
        end
        local qm = _G.QuestMapFrame
        if type(qm) == "table" then
            Kit.Hide(qm.Background)
            Kit.Hide(qm.VerticalSeparator)
            for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
                Kit.SideTab(qm[key], nil, Kit.SIDE_TAB_CROP)
            end
            local qs = _G.QuestScrollFrame
            if type(qs) == "table" then
                Kit.Hide(qs.BorderFrame)
                if type(qs.Contents) == "table" then Kit.Hide(qs.Contents.Separator) end
                Kit.EditBox(qs.SearchBox)
                Kit.ScrollBar(qs.ScrollBar)
                questHeaders(Kit, qs.Contents)
                questCount(Kit, qs)
            end
            questDetails(Kit)
        end
        if not mapHooked then
            mapHooked = true
            -- New breadcrumbs as you go deeper, and quest log headers as it
            -- fills. Post-hooks on the game's functions.
            if type(NavBar_AddButton) == "function" then
                hooksecurefunc("NavBar_AddButton", function(nav) navBar(Kit, nav) end)
            end
            -- A quest opened: its page and rewards were just built.
            for _, fn in ipairs({ "QuestMapFrame_ShowQuestDetails", "QuestInfo_Display" }) do
                if type(_G[fn]) == "function" then hooksecurefunc(fn, function() questDetails(Kit) end) end
            end
            if type(QuestLogQuests_Update) == "function" then
                hooksecurefunc("QuestLogQuests_Update", function()
                    local qs = _G.QuestScrollFrame
                    if type(qs) == "table" then questHeaders(Kit, qs.Contents) end
                end)
            end
            -- QuestLogMixin:SetDisplayMode checks the side tabs and announces
            -- it through EventRegistry.
            local reg = _G.EventRegistry
            if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
                reg:RegisterCallback("QuestLog.SetDisplayMode", Kit.RepaintSoon, Kit)
            end
        end
    end })

-- The game's popup menus (right-click menus, the buff bar's category list, bag
-- categories): window look behind them, our font, colors as the game set them.
--
-- How the game builds them drives the approach:
-- - While a menu is open nothing may create textures on it, so our look goes on
--   a frame of ours just behind it.
-- - Menus are reused and redraw their background each time, so each is dressed
--   again every time it opens.
-- - Every level, submenus included, is shown by the menu manager, which then
--   fires EventRegistry "MenuProxy.OnShow" with the menu frame
--   (Blizzard_Menu/Menu.lua, MenuProxyMixin:OnShow; the game's gamepad code
--   listens the same way). We listen there, with no hook on the manager or on
--   the menu styles' Generate.
-- - That callback runs inside the game's secure menu code, so it only records
--   the frame. The dressing happens a moment later from our timer.
local menuShell = setmetatable({}, { __mode = "k" })

-- Our font on every text in a menu, at any depth. Not Kit.Font, which does a
-- text only once: the game resets its own font every time it reuses a row, so
-- here it's checked every time and set only when it isn't ours. The game blocks
-- SetFont on menu text while the menu is open, so the text gets one of our font
-- objects instead (one per size, kept in sync with the font settings by
-- Style.DressText). If the game ever blocks that too, menus keep its font and
-- we stop trying.
local Style = DUI.Style
local menuFontObjects, menuFontsBlocked = {}, false
local function menuFontObject(size)
    size = math.floor((size or 12) + 0.5)
    local obj = menuFontObjects[size]
    if not obj then
        obj = CreateFont("DaylightUIMenuFont" .. size)
        -- Kept in sync with the font settings, so every text using it follows.
        Style.DressText(obj, size)
        menuFontObjects[size] = obj
    end
    return obj
end
local function menuText(r)
    local file, size = r:GetFont()
    if file == Style.FONT then return end
    -- SetFontObject resets the color to the font object's, so the game's
    -- color (a class name, a gray disabled entry) is put back after.
    local cr, cg, cb, ca = r:GetTextColor()
    r:SetFontObject(menuFontObject(size))
    r:SetTextColor(cr, cg, cb, ca)
end
local function menuFonts(frame, depth)
    if menuFontsBlocked then return end
    if type(frame) ~= "table" or not frame.GetRegions or (frame.IsForbidden and frame:IsForbidden()) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            if not pcall(menuText, r) then
                menuFontsBlocked = true
                return
            end
        end
    end
    if depth > 0 and frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do menuFonts(c, depth - 1) end
    end
end
local function dressMenu(Kit, menu)
    if type(menu) ~= "table" or not menu.GetRegions or (menu.IsForbidden and menu:IsForbidden()) then return end
    Kit.Strip(menu)
    local holder = menuShell[menu]
    if not holder then
        holder = CreateFrame("Frame", nil, menu)
        holder:SetAllPoints(menu)
        holder:EnableMouse(false)
        Kit.Shell(holder, "window")
        menuShell[menu] = holder
    end
    -- A reused menu opens at its owner's strata, so ours is moved back under
    -- it each time. Left where it was made, it could cover the rows.
    holder:SetFrameStrata(menu:GetFrameStrata())
    holder:SetFrameLevel(math.max(0, menu:GetFrameLevel() - 1))
    menuFonts(menu, 5)
end

local menuListener = {} -- our EventRegistry owner
Engine.Register({ key = "popupmenus", pack = "system", apply = function(Kit)
    local registry = _G.EventRegistry
    if type(registry) ~= "table" or type(registry.RegisterCallback) ~= "function" then return false end
    local pending, armed = {}, false
    local function flush()
        armed = false
        for menu in pairs(pending) do
            pending[menu] = nil
            DUI.SafeCall(dressMenu, Kit, menu)
        end
    end
    local function note(menu)
        if type(menu) ~= "table" then return end
        pending[menu] = true
        if not armed then
            armed = true
            C_Timer.After(0, flush)
        end
    end
    -- Every menu as it shows, and again a moment later since rows can arrive
    -- after.
    registry:RegisterCallback("MenuProxy.OnShow", function(_, menu)
        note(menu)
        C_Timer.After(0.1, function() note(menu) end)
    end, menuListener)
end })
