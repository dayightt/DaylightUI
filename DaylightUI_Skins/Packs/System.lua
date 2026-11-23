-- System pack: game menu, addon list, macros, clock, loot, socketing and item
-- upgrades, the scrapper, the auction house, and the world map's frame. Each is
-- Engine.Window plus anything unique to it.
--
-- Deliberately left as the game draws them: the settings panel and the
-- dungeon-ready dialog.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local Engine = ns.Engine


-- Game menu: its dialog border (a separate frame) and header art go;
-- Kit.Window puts the title in the title row.
Engine.Window({ key = "gamemenu", pack = "system", frame = "GameMenuFrame", hide = { ".Border" },
    after = function(Kit, f)
        if type(f.Header) == "table" then Kit.Strip(f.Header) end
    end })
Engine.Window({ key = "addons", pack = "system", frame = "AddonList", watch = true })
-- The macro window, dressed quietly like the confirm boxes below. With the
-- controller UI on, its footer refreshes at the end of every tab switch, just
-- after the game enables and disables its buttons and tabs, and a hook on any of
-- those tainted the footer: the game then refused to bind a macro to the
-- controller bars. The macro slots keep the game's look.
local MACRO_BUTTONS = { "MacroEditButton", "MacroCancelButton", "MacroSaveButton",
    "MacroDeleteButton", "MacroNewButton", "MacroExitButton" }
Engine.Window({ key = "macros", pack = "system", addon = "Blizzard_MacroUI", frame = "MacroFrame",
    auto = false,
    window = { quiet = true },
    after = function(Kit, f)
        for _, name in ipairs(MACRO_BUTTONS) do Kit.Button(_G[name], f) end
        for i = 1, 2 do Kit.Tab(_G["MacroFrameTab" .. i], nil, f) end
        if type(f.MacroSelector) == "table" then Kit.ScrollBar(f.MacroSelector.ScrollBar) end
        local text = _G.MacroFrameScrollFrame
        if type(text) == "table" then Kit.ScrollBar(text.ScrollBar) end
        Kit.InkGameText(f)
    end })
Engine.Window({ key = "clock", pack = "system", addon = "Blizzard_TimeManager", frame = "TimeManagerFrame" })
-- Loot window: each item becomes a list row (the game's square card,
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

-- The loot window's header and room. The game puts the title in a 22 px strip
-- with its X in the corner, higher than the title. Here they sit where every
-- Daylight UI window has them (title at Win.TITLE_Y, the X level with it), and
-- the rows have the same MARGIN to the window's edge on the left, right and
-- bottom, and under the header at the top. The rows keep the game's 46 px
-- slots but draw a little shorter, so they stand further apart, with the icon
-- a bit smaller so its outline clears the row's, the name lower and the rarity
-- tucked into the corner so the two don't run together.
-- The game sizes the window from its rows with a minimum that leaves spare room
-- at the bottom for one or two, so the height is worked out here from the rows
-- instead, up to the game's own maximum. Past that the list scrolls, and only
-- then does its bar show (the game's shows always), with room made for it.
-- Nothing here is a hook on the game's methods: it runs after the window shows
-- and after each list update, next frame, and only sets what differs.
local LootLayout = {
    MARGIN = 12,     -- px between the window's edge (or the header) and the rows
    HEAD = DUI.Win and DUI.Win.COMPACT or 36, -- the header's height
    PAD = 6,         -- the game's padding inside its list (ScrollBoxPad)
    ROW_SLOT = 46,   -- the game's row height
    SLOT_GAP = 2,    -- the game's space between rows
    ROW_GAP = 2,     -- px a row draws shorter than its slot (so 4 px between rows, not 2)
    MAX_HEIGHT = 290, -- the game's panelMaxHeight, used when it can't be read
    BAR_W = 8,       -- the scroll bar's width
    BAR_INSET = 6,   -- px from the window's right edge to the bar
    BAR_GAP = 6,     -- px between the rows and the bar
    ICON = 30,       -- the item button, px square (the game's is 37); its quality outline sticks out ~2.5 px more each side
    ITEM_X = 8,      -- the icon's left edge in the row (the game's: 5)
    TEXT_GAP = 10,   -- px between the icon and the name
    TEXT_DROP = 6,   -- px a one-line name sits below the row's middle (clear of the rarity)
    TAG_X = -10, TAG_Y = -5, -- the rarity's corner
    TAG_GAP = 6,     -- px between a two-line name and the rarity
}
ns.LootLayout = LootLayout

-- Where the list sits (offsets from the window's corners) and how tall the
-- window is for n rows, and whether those rows need the bar.
function LootLayout.Plan(n, maxHeight, pad)
    local L = LootLayout
    pad = pad or L.PAD
    local left = L.MARGIN - pad
    local top = L.HEAD + L.MARGIN - pad
    local bottom = L.MARGIN - pad - L.ROW_GAP -- a row's last 2 px of its slot are empty
    local wanted = top + bottom + 2 * pad + n * L.ROW_SLOT + math.max(n - 1, 0) * L.SLOT_GAP
    local scrolls = wanted > maxHeight
    local right = scrolls and (L.BAR_INSET + L.BAR_W + L.BAR_GAP - pad) or (L.MARGIN - pad)
    return { left = left, top = top, bottom = bottom, right = right, height = math.min(wanted, maxHeight), scrolls = scrolls }
end

local function lootHeader(f)
    local Win = DUI.Win
    local close = f.ClosePanelButton
    if type(close) == "table" and close.SetPoint then
        local size = DUI.Widgets and DUI.Widgets.CLOSE or 24
        close:SetSize(size, size)
        close:ClearAllPoints()
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", Win.CLOSE_X, Win.CloseY(true))
    end
    local title = type(f.TitleContainer) == "table" and f.TitleContainer.TitleText
    if type(title) == "table" and title.SetPoint then
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", f, "TOPLEFT", Win.EDGE, Win.TITLE_Y)
        if type(close) == "table" then title:SetPoint("RIGHT", close, "LEFT", -12, 0) end
    end
end

-- True when the frame's points already are these (nothing to set).
local function pointsAre(frame, want)
    if frame:GetNumPoints() ~= #want then return false end
    for i, w in ipairs(want) do
        local point, rel, relPoint, x, y = frame:GetPoint(i)
        if point ~= w[1] or rel ~= w[2] or relPoint ~= w[3]
            or type(x) ~= "number" or type(y) ~= "number"
            or math.abs(x - w[4]) > 0.01 or math.abs(y - w[5]) > 0.01 then
            return false
        end
    end
    return true
end

local function placePoints(frame, want)
    if pointsAre(frame, want) then return end
    frame:ClearAllPoints()
    for _, w in ipairs(want) do frame:SetPoint(w[1], w[2], w[3], w[4], w[5]) end
end

-- The padding the game's list keeps inside itself (its view's), or our number
-- for it when the view can't be read.
local function listPad(box)
    local view = type(box.GetView) == "function" and box:GetView()
    local pad = type(view) == "table" and type(view.GetPadding) == "function" and view:GetPadding()
    local left = type(pad) == "table" and type(pad.GetLeft) == "function" and pad:GetLeft()
    if type(left) == "number" and left >= 0 then return left end
    return LootLayout.PAD
end

local function lootRoom(f)
    if DUI.Win.Held(f) then return end
    local L = LootLayout
    local box = f.ScrollBox
    if type(box) ~= "table" or not box.SetPoint or type(box.GetDataProviderSize) ~= "function" then return end
    local n = box:GetDataProviderSize()
    if type(n) ~= "number" or n < 1 then return end
    local max = L.MAX_HEIGHT
    if type(f.GetPanelMaxHeight) == "function" then
        local ok, h = pcall(f.GetPanelMaxHeight, f)
        if ok and type(h) == "number" and h > 0 then max = h end
    end
    local pad = listPad(box)
    local plan = L.Plan(n, max, pad)
    local h = f:GetHeight()
    if type(h) ~= "number" or math.abs(h - plan.height) > 0.01 then f:SetHeight(plan.height) end
    placePoints(box, {
        { "TOPLEFT", f, "TOPLEFT", plan.left, -plan.top },
        { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -plan.right, plan.bottom },
    })
    -- The bar: only when the rows need it, level with them. The game shows or
    -- hides it when it sizes the window (for its own height, which can fit five
    -- rows where ours scrolls), so its shown state is set here, not its alpha.
    local bar = f.ScrollBar
    if type(bar) == "table" and bar.SetPoint then
        local x = -(L.BAR_INSET + L.BAR_W)
        placePoints(bar, {
            { "TOPLEFT", f, "TOPRIGHT", x, -(plan.top + pad) },
            { "BOTTOMLEFT", f, "BOTTOMRIGHT", x, plan.bottom + pad },
        })
        if bar.SetAlpha then bar:SetAlpha(1) end
        if bar.SetShown and bar:IsShown() ~= plan.scrolls then bar:SetShown(plan.scrolls) end
    end
end

-- The item button is what answers clicks and hovers (it takes the item, shows its
-- tooltip and lights the row), and it is only the icon's size. Its hit area covers
-- the whole row instead, so the name and the empty part of the row answer too.
-- Reaching past the button's edges is what negative insets do; they follow the
-- row's size (the bar showing or hiding changes its width).
local function lootHit(row)
    local item = row.Item
    if type(item) ~= "table" or not item.SetHitRectInsets then return end
    if InCombatLockdown() and item.IsProtected and item:IsProtected() then return end
    local L = LootLayout
    local rowH, rowW = row:GetHeight(), row:GetWidth()
    local up = (type(rowH) == "number" and rowH > L.ICON) and -(rowH - L.ICON) / 2 or 0
    local left, right = 0, 0
    if type(rowW) == "number" and rowW > L.ITEM_X + L.ICON then
        left, right = -L.ITEM_X, -(rowW - L.ITEM_X - L.ICON)
    end
    item:SetHitRectInsets(left, right, up, up)
end

local lootHitWatched = setmetatable({}, { __mode = "k" }) -- rows whose size changes refit the hit area

-- A row draws ROW_GAP shorter than its slot. Its icon is smaller and in the
-- middle, the name sits just below the middle of the row, and the rarity is in
-- the top right corner, above the name's line.
local lootNameWidth = setmetatable({}, { __mode = "k" }) -- a name -> the width the game gave it
local function lootRoomRow(row)
    if type(row) ~= "table" or type(row.Item) ~= "table" or not row.SetHeight then return end
    local L = LootLayout
    local h = row:GetHeight()
    if type(h) == "number" and math.abs(h - L.ROW_SLOT) < 0.5 then row:SetHeight(L.ROW_SLOT - L.ROW_GAP) end
    local item = row.Item
    item:SetSize(L.ICON, L.ICON)
    item:ClearAllPoints()
    item:SetPoint("LEFT", row, "LEFT", L.ITEM_X, 0)
    -- The button is what answers clicks and hovers: its hit area covers the whole
    -- row, though the icon is smaller (and follows the row when its width changes).
    lootHit(row)
    if not lootHitWatched[row] and row.HookScript then
        lootHitWatched[row] = true
        row:HookScript("OnSizeChanged", lootHit)
    end
    if type(row.IconQuestTexture) == "table" and row.IconQuestTexture.SetSize then
        row.IconQuestTexture:SetSize(L.ICON, L.ICON)
    end
    local name = row.Text
    if type(name) == "table" and name.SetPoint then
        name:ClearAllPoints()
        -- One line sits below the rarity. Two lines are centered instead, or the
        -- second would touch the row's bottom edge.
        -- Measured at the game's own width (a reused row may still be narrowed).
        local base = lootNameWidth[name]
        if not base then base = name:GetWidth(); lootNameWidth[name] = base end
        if type(base) == "number" and base > 0 then name:SetWidth(base) end
        local height = name.GetStringHeight and name:GetStringHeight()
        local lines = type(height) == "number" and height > 1.5 * (DUI.Style.SIZE.body + 2)
        name:SetPoint("LEFT", item, "RIGHT", L.TEXT_GAP, (row.QualityText and not lines) and -L.TEXT_DROP or 0)
        if name.SetJustifyV then name:SetJustifyV("MIDDLE") end
        -- A two-line name is centered, level with the rarity in the corner, so its
        -- right edge stops short of it.
        local tag, rowW = row.QualityText, row:GetWidth()
        if lines and type(tag) == "table" and type(rowW) == "number" and type(base) == "number" then
            local tagW = tag.GetStringWidth and tag:GetStringWidth()
            if type(tagW) ~= "number" then tagW = 0 end
            local room = rowW - (L.ITEM_X + L.ICON + L.TEXT_GAP) + L.TAG_X - tagW - L.TAG_GAP
            if room > 0 and room < base then name:SetWidth(room) end
        end
    end
    local tag = row.QualityText
    if type(tag) == "table" and tag.SetPoint then
        tag:ClearAllPoints()
        tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", L.TAG_X, L.TAG_Y)
    end
end

Engine.Window({ key = "loot", pack = "system", frame = "LootFrame", watch = true,
    after = function(Kit, f)
        Kit.EachRow(f.ScrollBox, lootRow, "lootrow")
        Kit.EachRow(f.ScrollBox, lootRoomRow, "lootroom")
        -- Runs for each row, but sets only what differs, so after the first it
        -- changes nothing.
        Kit.EachRow(f.ScrollBox, function() lootRoom(f) end, "lootfit")
        lootHeader(f)
        lootRoom(f)
    end })
-- Group loot rolls: each popup gets the window look with a quality-colored line
-- on top, the icon outlined in that color, the name on one line above a sub line
-- (slot, "BoP" in the warn color), and Need/Greed/Pass in a row of control
-- boxes. The game's dice and coins are kept since nothing reads faster. The
-- timer is a pill bar following the game's hidden one, with seconds left; in
-- the last quarter it turns the warn color and pulses.
-- Motion: out of combat the popup glides up while fading in. Always (the added
-- pieces only) the top line draws out from the left and a quality-colored light
-- sweeps across. Closing leaves the window's fading ghost.
-- The game reuses and positions the popups itself (the container is left
-- alone), so they're revisited whenever one is added or the rolls change. The
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
    -- The buttons that show how many players picked them.
    COUNTED = { NeedButton = "need", GreedButton = "greed", TransmogButton = "transmog", PassButton = "pass" },
}
ns.LootRoll = LootRoll
local rolls = setmetatable({}, { __mode = "k" }) -- popup -> the pieces added to it

local function rollInfo(f)
    if type(f.rollID) ~= "number" or type(GetLootRollItemInfo) ~= "function" then return nil end
    local ok, _, _, _, quality, bop = pcall(GetLootRollItemInfo, f.rollID)
    if not ok then return nil end
    return quality, bop
end

-- An item quality's color { r, g, b }, or nil.
function LootRoll.QualityColor(quality)
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

-- The line under the item's name: its slot, and "BoP" in the warn color.
function LootRoll.Sub(slot, bop)
    if bop ~= true then return slot or "" end
    local Style, L = DUI.Style, DUI.L
    local Parts = DUI.Win and DUI.Win.Parts
    local bopText = Parts and (Parts.Hex(Style.INK.WARN) .. L["BoP"] .. "|r") or L["BoP"]
    return slot and (slot .. "  ·  " .. bopText) or bopText
end

-- Timer colors: the accent pair, or the warn color's pair near the end.
-- r holds the bar and whether time is low.
function LootRoll.PaintTimer(r)
    local W = DUI.Widgets
    if r.low then
        local c = DUI.Style.INK.WARN
        W.BarFrom(r.bar, c[1], c[2], c[3])
    else
        W.BarAccent(r.bar)
    end
end
local paintTimer = LootRoll.PaintTimer

-- Near the end the fill pulses its alpha down and back while low and shown.
-- With motion off it stays steady.
function LootRoll.Breathe(r, down)
    local M = DUI.Motion
    if not (r.low and M and M.On() and r.bar:IsVisible()) then
        r.bar.fill:SetAlpha(1)
        return
    end
    M.Tween(r, down and 1 or 0.45, down and 0.45 or 1, M.SLOW, function(a) r.bar.fill:SetAlpha(a) end,
        function() LootRoll.Breathe(r, not down) end)
end
local breathe = LootRoll.Breathe

local function followTimer(r, timer)
    local ok, lo, hi = pcall(timer.GetMinMaxValues, timer)
    local v = timer:GetValue()
    if not ok then return end
    r.bar:SetMinMaxValues(lo, hi)
    r.bar:SetValue(v)
    if isSecret(v) or isSecret(hi) then return end
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

-- How many players picked each way on a roll. Disenchant counts as Greed: the
-- popup has no button of its own for it.
function LootRoll.Tally(drop)
    local n = { need = 0, greed = 0, transmog = 0, pass = 0 }
    if type(drop) ~= "table" or type(drop.players) ~= "table" then return n end
    for _, p in pairs(drop.players) do
        local kind = p.pick == "disenchant" and "greed" or p.pick
        if n[kind] then n[kind] = n[kind] + 1 end
    end
    return n
end

-- The counts on a popup's buttons, from the roll data the Daylight UI roll
-- window uses too. A roll the data doesn't know yet (open across a reload) is
-- started from the game's roll API.
function LootRoll.PaintCounts(f)
    local r = rolls[f]
    local Data = ns.RollData
    if not (r and r.counts and Data) then return end
    local id = f.rollID
    if type(id) ~= "number" or not f:IsShown() then return end
    r.rollID = id
    local drop = Data.drops[id] or Data.Start(id, nil, GetTime())
    local n = LootRoll.Tally(drop)
    local M = DUI.Motion
    for kind, fs in pairs(r.counts) do
        local v = n[kind] or 0
        DUI.Style.InkText(fs, "pop")
        if v > 0 then
            M.CountTo(fs, v, tostring, M.FAST)
            M.AlphaTo(fs, 1, M.FAST)
        elseif fs:IsShown() then
            M.AlphaTo(fs, 0, M.FAST, true)
        end
    end
end

-- A popup reused for a new roll starts its counts from nothing.
local function clearCounts(r)
    for _, fs in pairs(r.counts or {}) do
        fs.__duiCountKey = nil
        fs:SetText("")
        fs:Hide()
    end
end

-- Each time a roll opens on the popup: colors, sub line, motion.
local function openRoll(Kit, f)
    local r = rolls[f]
    if not r then return end
    clearCounts(r)
    LootRoll.PaintCounts(f)
    local Style, M = DUI.Style, DUI.Motion
    local quality, bop = rollInfo(f)
    local color = LootRoll.QualityColor(quality)
    if type(f.IconFrame) == "table" then Kit.Paint(Kit.ShellOf(f.IconFrame), color) end
    local lo, hi = DUI.Gradients.PairFrom(color or { Style.Accent() })
    DUI.Gradients.PaintPair(r.line, lo, hi)
    r.sub:SetText(LootRoll.Sub(slotText(f), bop))
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
-- the popup itself never moves. State lives in a local table, not in
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
        -- How many players picked each button, at its bottom right corner.
        -- Outlined, since it sits over the dice and coins.
        r.counts = {}
        for key, kind in pairs(LootRoll.COUNTED) do
            local b = box[key]
            if type(b) == "table" and b.CreateFontString then
                local fs = b:CreateFontString(nil, "OVERLAY")
                Style.DressText(fs, Style.SIZE.tiny, { outline = "OUTLINE" })
                fs:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
                fs:Hide()
                r.counts[kind] = fs
            end
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

    -- The timer: the game's runs hidden, the pill bar follows it.
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
            -- Nothing shows this roll any more, so its data can go.
            if r.rollID and ns.RollData then ns.RollData.Remove(r.rollID) end
            r.rollID = nil
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

-- With Daylight UI's own roll window on (Rolls/Stack.lua) the popups are only
-- kept running, unseen, so this skin stays off. The player can also keep the
-- game's own look on its popups.
local function plainPopups() return DUI:Get("Skins", "rolls.popups") == false end
Engine.Register({ key = "lootroll", pack = "system",
    skip = function() return (ns.RollStack ~= nil and ns.RollStack.On()) or plainPopups() end,
    apply = function(Kit)
    local function all()
        for i = 1, 8 do skinRoll(Kit, _G["GroupLootFrame" .. i]) end
        local c = _G.GroupLootContainer
        if type(c) == "table" and type(c.rollFrames) == "table" then
            for _, f in pairs(c.rollFrames) do skinRoll(Kit, f) end
        end
    end
    local soon = DUI.Soon(function() DUI.SafeCall(all) end)
    for _, fn in ipairs({ "GroupLootContainer_AddFrame", "GroupLootContainer_Update" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, soon) end
    end
    DUI.RegisterEvent("START_LOOT_ROLL", soon)
    -- Everyone's picks, for the counts on the buttons. A pick shows at once.
    if ns.RollData then
        ns.RollData.Wire()
        local function paintAll()
            for f in pairs(rolls) do LootRoll.PaintCounts(f) end
        end
        DUI.On("RollChanged", function() DUI.SafeCall(paintAll) end)
        DUI.On("StyleChanged", function() DUI.SafeCall(paintAll) end)
    end
    all()
end })

-- Loot toasts ("You received", money): the window look on a box the size of the
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

-- The new recipe toast: its gold art is one unnamed atlas wider than what it
-- holds, so the box is drawn round the icon and words instead of the frame. The
-- icon stays round: the game puts its portrait mask back on every toast.
local RecipeToast = { boxes = setmetatable({}, { __mode = "k" }) }
ns.RecipeToast = RecipeToast
RecipeToast.BOX = { left = 10, right = -24, top = -8, bottom = 8 } -- from the frame's edges

local function recipeToast(Kit, f)
    local SIZE, INK = DUI.Style.SIZE, DUI.Style.INK
    if not RecipeToast.boxes[f] then
        for _, r in ipairs({ f:GetRegions() }) do
            if r ~= f.Icon and r.GetObjectType and r:GetObjectType() == "Texture" then Kit.Erase(r) end
        end
        Kit.Erase(f.glow)
        Kit.Erase(f.shine)
        local box, b = CreateFrame("Frame", nil, f), RecipeToast.BOX
        box:SetPoint("TOPLEFT", f, "TOPLEFT", b.left, b.top)
        box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", b.right, b.bottom)
        box:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
        box:EnableMouse(false)
        Kit.Shell(box, "window")
        RecipeToast.boxes[f] = box
    end
    Kit.Font(f.Title, SIZE.small, INK.LABEL)
    Kit.Font(f.Name, SIZE.body, INK.VALUE)
end

Engine.Register({ key = "loottoast", pack = "system", apply = function(Kit)
    if type(_G.AlertFrame_ShowNewAlert) ~= "function" then return end
    hooksecurefunc("AlertFrame_ShowNewAlert", function(f)
        if type(f) ~= "table" or f.queue == nil then return end
        if f.queue == _G.LootAlertSystem then
            DUI.SafeCall(lootToast, Kit, f)
        elseif f.queue == _G.MoneyWonAlertSystem then
            DUI.SafeCall(moneyToast, Kit, f)
        elseif f.queue == _G.NewRecipeLearnedAlertSystem then
            DUI.SafeCall(recipeToast, Kit, f)
        end
    end)
end })

Engine.Window({ key = "socketing", pack = "system", addon = "Blizzard_ItemSocketingUI", frame = "ItemSocketingFrame" })
Engine.Window({ key = "itemupgrade", pack = "system", addon = "Blizzard_ItemUpgradeUI", frame = "ItemUpgradeFrame" })
Engine.Window({ key = "scrapper", pack = "system", addon = "Blizzard_ScrappingMachineUI", frame = "ScrappingMachineFrame" })
-- Never walked while Daylight UI's Auction House window covers it, or while
-- DaylightMogul owns the Auction House.
Engine.Window({ key = "auction", pack = "system", addon = "Blizzard_AuctionHouseUI", frame = "AuctionHouseFrame", watch = true,
    skip = function()
        if DaylightUI.ahMogul == true then return true end
        local covers = DaylightUI.ahCovers
        return type(covers) == "function" and covers() == true
    end })

-- The layering notice (the game is about to move you to another copy of the
-- zone, and you can delay it): the window look and font, the gold glow removed. Its
-- It fades in with the game's own
-- alert animation, not Motion (Kit.Window ownFade). Its minimize button, the
-- notice folded away, is a small control with a chevron.
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
            -- The game's red expand arrow becomes a small control with a chevron.
            Kit.PageButton(m, "right")
        end
    end })

-- Battle.net toasts (friend online/offline, broadcast, invite): the window look and
-- font, icon kept, glow removed. The game grays the last line again on every
-- toast and combat pauses the skin's passes, so that line is set to tan from
-- the toast's own OnShow. Fades like the layering notice.
local toastHooked = false
local splitHooked = false -- the split box's OnShow repaint, hooked once
local function toastLine(fs)
    local text = fs:GetText()
    if type(text) == "string" and not isSecret(text) then
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

-- Confirmation boxes (destroying an item, leaving a group, typing a name): the
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

-- The role check pop-ups (a leader's role poll, and the dungeon finder's
-- confirm-your-role box) dressed like the confirm boxes above, and just as
-- quietly: both set up controller focus as they open. The role icons and
-- their radio dots are the game's art and stay.
local function roleTitle(Kit, f)
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then Kit.Font(r, DUI.Style.SIZE.head) end
    end
end

Engine.Window({ key = "rolepoll", pack = "system", frame = "RolePollPopup",
    auto = false,
    window = { quiet = true },
    hide = { ".Border" },
    after = function(Kit, f)
        roleTitle(Kit, f)
        Kit.Button(f.acceptButton, f)
    end })

Engine.Window({ key = "rolecheck", pack = "system", frame = "LFDRoleCheckPopup",
    auto = false,
    window = { quiet = true },
    hide = { ".Border" },
    after = function(Kit, f)
        Kit.Font(f.Text, DUI.Style.SIZE.head)
        Kit.Button(_G.LFDRoleCheckPopupAcceptButton, f)
        Kit.Button(_G.LFDRoleCheckPopupDeclineButton, f)
        Kit.Font(_G.LFDRoleCheckPopupDescriptionText)
        local desc = _G.LFDRoleCheckPopupDescription
        if type(desc) == "table" then Kit.Font(desc.SubText, DUI.Style.SIZE.small, DUI.Style.INK.LABEL) end
    end })

-- The stack split box (Shift-click a stack in your bags): the window look, arrows and
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
-- left alone. Nothing here does more than hide the game's art and draw the skin.

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
-- removed (the window shows through), W.Button look, a plain rewards header, and
-- each reward outlined in its quality. Rewards are built per quest shown, so
-- this reruns then. Looks only: the buttons still act for the quest log.
local stripped = setmetatable({}, { __mode = "k" }) -- details buttons whose art is gone

-- Whether a frame sits inside the world map's quest log.
local function inMap(f)
    local qm = _G.QuestMapFrame
    for _ = 1, 12 do
        if type(f) ~= "table" or not f.GetParent then return false end
        if f == qm then return true end
        f = f:GetParent()
    end
    return false
end
-- Whether the quest text the map shares with the game's quest window was last
-- shown on the map (QuestInfo_Display moves it to whichever window shows a quest).
local questTextOnMap = false
local function questDetails(Kit)
    local qm = _G.QuestMapFrame
    local d = type(qm) == "table" and qm.DetailsFrame
    if type(d) ~= "table" then return end
    -- The game colors this text dark for the parchment that was removed.
    if questTextOnMap then ns.LightQuestInfo(Kit) end
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
        -- Once only, since the outline is drawn on the button too.
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
        -- the zone buttons). Bare like them, with a "filters changed" badge.
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
            if type(QuestMapFrame_ShowQuestDetails) == "function" then
                hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
                    questTextOnMap = true
                    questDetails(Kit)
                end)
            end
            -- The game's own quest window fills through QuestInfo_Display too, with
            -- the same text, and keeps its dark ink on its parchment: shown there,
            -- the text gets the game's look back.
            if type(QuestInfo_Display) == "function" then
                hooksecurefunc("QuestInfo_Display", function(_, parent)
                    questTextOnMap = inMap(parent)
                    if questTextOnMap then questDetails(Kit) else ns.DarkQuestInfo(Kit) end
                end)
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

-- The game's popup menus (right-click a unit, the buff bar's category list,
-- bag categories): a window shell behind them, the Daylight font and row chrome.
--
-- How the game builds them drives the approach:
-- - While a menu is open nothing may create textures on it, so the look goes on
--   a separate frame parented outside the menu and kept on a lower strata. A
--   child of the menu draws in the same layer as the rows and, the second
--   time the menu opens, covers them. Every icon, tick and arrow below is one
--   the game already attached. Only its texture, color or alpha changes.
-- - Menus are reused and redraw their background each time, so each is dressed
--   again every time it opens.
-- - Every level, submenus included, is shown by the menu manager, which then
--   fires EventRegistry "MenuProxy.OnShow" with the menu frame
--   (Blizzard_Menu/Menu.lua, MenuProxyMixin:OnShow; the game's gamepad code
--   listens the same way). This listens there, with no hook on the manager or on
--   the menu styles' Generate.
-- - That callback runs inside the game's secure menu code, so it only records
--   the frame. The dressing happens a moment later from a timer.
-- - A ticked checkbox returns MenuResponse.Refresh. That rebuilds the rows
--   (MenuMixin:ReinitializeAll) without another OnShow, so the game's tick,
--   divider and icons come back while the menu is still open. The frame
--   put behind the menu watches for that art and dresses again. No hook on
--   the menu: Refresh runs on the private menu, not the proxy OnShow hands over.
--
-- Text keeps a color that means something (a class, an item quality, a disabled
-- row). Gold titles and ordinary white rows take Style.INK. A chosen radio is
-- the accent, same as W.OpenMenu. The raid-target submenu's icons are the
-- game's sheet; those become the Daylight marker files (the same 1 to 8 as the frames).
local menuShell = setmetatable({}, { __mode = "k" })
-- Set when the skin applies. The frame behind a menu calls it when the game
-- redraws a row without opening the menu again.
local requestMenu = function() end

-- The Daylight font on every text in a menu, at any depth. Not Kit.Font, which does a
-- text only once: the game resets its own font every time it reuses a row, so
-- here it's checked every time and set only when it isn't right. The game blocks
-- SetFont on menu text while the menu is open, so the text gets one of the addon's font
-- objects instead (one per size, kept in sync with the font settings by
-- Style.DressText). If the game ever blocks that too, menus keep its font and
-- this stops trying.
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
local MENU_CHEVRON = DUI.MEDIA .. "ui-chevron.png"
local MENU_TICK = DUI.MEDIA .. "ui-check.png"
local MENU_LINE = "Interface\\Buttons\\WHITE8x8"
-- In game GetTexture() gives back a file id, not the path. Learned the first
-- time a line is painted, so a dressed hover is not treated as the game's art
-- on every following frame.
local menuLineIDs = {}
local function paintMenuLine(tex)
    tex:SetTexture(MENU_LINE)
    local id = tex.GetTexture and tex:GetTexture()
    if type(id) == "number" then menuLineIDs[id] = true end
end
local function menuIsOurLine(tex)
    local t = tex.GetTexture and tex:GetTexture()
    if t == MENU_LINE then return true end
    if type(t) == "string" and t:lower():find("white8x8", 1, true) then return true end
    return type(t) == "number" and menuLineIDs[t] == true
end
-- Points right. The chevron file points down; this is Kit.ROTATION.right.
local MENU_CHEVRON_RIGHT = math.pi / 2

local function menuPath(tex)
    local p = tex.GetTexture and tex:GetTexture()
    if type(p) ~= "string" then return "" end
    return p:lower():gsub("/", "\\")
end
local function menuAtlas(tex)
    if type(tex.GetAtlas) ~= "function" then return "" end
    local ok, name = pcall(tex.GetAtlas, tex)
    if not ok or type(name) ~= "string" then return "" end
    return name:lower()
end
-- "radial" is the radio (empty ring or the yellow dot). "checkmark" and
-- "ticksquare" are the checkbox. Read before the texture is replaced.
local function menuSelectKind(tex)
    local name = menuAtlas(tex) .. " " .. menuPath(tex)
    if name:find("radial", 1, true) then return "radio" end
    if name:find("checkmark", 1, true) or name:find("ticksquare", 1, true) then return "check" end
end
-- The game's raid-target sheet is one cell of a grid (4 x 4 or 4 x 2). The
-- cell's tex coords are the marker number, 1 star through 8 skull.
-- Interface/TargetingFrame/UI-RaidTargetingIcons. GetTexture() is an id in
-- game, not the path, so the path check alone never sees it. The marker menu
-- shows 137009.
local RAID_SHEET = { [137009] = true, [137010] = true }
local function menuFileID(tex)
    local id = tex.GetTexture and tex:GetTexture()
    if type(id) == "number" then return id end
    if type(tex.GetTextureFileID) ~= "function" then return nil end
    local ok, n = pcall(tex.GetTextureFileID, tex)
    if ok and type(n) == "number" then return n end
end
local function menuMarkerIndex(tex)
    if type(tex.GetTexCoord) ~= "function" then return nil end
    local u = { tex:GetTexCoord() }
    local left, right, top, bottom
    if #u >= 8 then
        left, top, right, bottom = u[1], u[2], u[7], u[8]
    else
        left, right, top, bottom = u[1], u[2], u[3], u[4]
    end
    if type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then
        return nil
    end
    local w, h = right - left, bottom - top
    if w < 0.05 or h < 0.05 or w > 0.6 then return nil end
    local cols = math.floor(1 / w + 0.5)
    local rows = math.floor(1 / h + 0.5)
    if cols < 1 or rows < 1 then return nil end
    local index = math.floor(top * rows + 0.5) * cols + math.floor(left * cols + 0.5) + 1
    if index < 1 or index > 8 then return nil end
    return index
end
-- The raid-target submenu's rows are named RAID_TARGET_1 .. RAID_TARGET_8
-- (the client's own words). A small grid icon on any other checkbox row, such
-- as the minimap tracking menu, is not one of these.
local function menuRaidLabel(frame)
    if type(frame) ~= "table" or not frame.GetRegions then return nil end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
            local text = region:GetText()
            if type(text) == "string" and text ~= "" then
                for i = 1, 8 do
                    local name = _G["RAID_TARGET_" .. i]
                    if type(name) == "string" and name ~= "" and text == name then return i end
                end
            end
        end
    end
end
local function menuMarkerKnown(tex)
    local path, atlas = menuPath(tex), menuAtlas(tex)
    if path:find("raidtargeting", 1, true) or atlas:find("raidtarget", 1, true) then return true end
    local id = menuFileID(tex)
    return id ~= nil and RAID_SHEET[id] == true
end
-- The row's name is the marker ("Calavera", "Estrella", ...), and that name
-- sits on the whole row. The hover covers the row and often has no size of
-- its own (SetAllPoints). Only a texture with a real small size is the icon.
-- A target's menu holds the target's name, a secret, and then every size on it
-- reads back secret. There the icon is told apart by its anchors: it sits on
-- one point with a size of its own, while the hover is pinned to the row on two.
local function menuIconSized(tex)
    local w = tex.GetWidth and tex:GetWidth()
    local h = tex.GetHeight and tex:GetHeight()
    if isSecret(w) or isSecret(h) then
        return tex.GetNumPoints ~= nil and tex:GetNumPoints() == 1
    end
    if type(w) ~= "number" or type(h) ~= "number" then return false end
    return w > 0 and h > 0 and w <= 24 and h <= 24
end
local function menuMarkerNumber(tex, frame)
    if type(frame) == "table" and (frame.highlight == tex or frame.Highlight == tex
        or frame.arrow == tex or frame.divider == tex or frame.Divider == tex) then
        return nil
    end
    if not menuIconSized(tex) then return nil end
    local known = menuMarkerKnown(tex)
    local index = menuRaidLabel(frame)
    if known then index = menuMarkerIndex(tex) or index end
    return index
end
local function menuMarkerArt(tex, frame)
    local index = menuMarkerNumber(tex, frame)
    if not index then return false end
    tex:SetTexture((DUI.MEDIA .. "marker-%d.png"):format(index))
    if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
    if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
    tex:SetVertexColor(1, 1, 1, 1)
    return true
end
local function menuOurFile(tex, needle)
    local t = tex.GetTexture and tex:GetTexture()
    if t == needle then return true end
    return type(t) == "string" and t:lower():find(needle:lower(), 1, true) ~= nil
end
local function menuIsArrow(owner, tex)
    if owner.arrow == tex then return true end
    local name = menuAtlas(tex) .. " " .. menuPath(tex)
    return name:find("expandarrow", 1, true) ~= nil
end
local function menuIsHighlight(owner, tex)
    if owner.arrow == tex or owner.divider == tex or owner.Divider == tex then return false end
    if owner.highlight == tex or owner.Highlight == tex then return true end
    local name = menuAtlas(tex) .. " " .. menuPath(tex)
    if name:find("questtitlehighlight", 1, true) then return true end
    -- The menu pools its textures, so a raid icon can come back still in ADD
    -- blend from an earlier hover. A hover spans the row; an icon-sized one is no hover.
    if menuIconSized(tex) then return false end
    if tex.GetBlendMode and tex:GetBlendMode() == "ADD" then return true end
    -- The hover is the texture stretched across the row. In game it often
    -- reports no width, so the icon's picture was ending up as the wash.
    return owner.IsObjectType and owner:IsObjectType("Button") and not menuIconSized(tex)
end
-- CreateDivider never sets frame.divider. It attaches one short texture
-- (height 13) on a frame that is not a row and has no text. GetTexture() is
-- a file id in game, so the path is not there to read.
local function menuThinLine(owner, tex)
    if owner.IsObjectType and owner:IsObjectType("Button") then return false end
    if owner.GetRegions then
        for _, region in ipairs({ owner:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then return false end
        end
    end
    -- A focus glow with secret anchoring reports a secret height. It is no divider.
    local h = tex.GetHeight and tex:GetHeight()
    return type(h) == "number" and not isSecret(h) and h > 0 and h <= 16
end
local function menuIsDivider(owner, tex)
    if owner.divider == tex or owner.Divider == tex then return true end
    local name = menuAtlas(tex) .. " " .. menuPath(tex)
    if name:find("tooltipdivider", 1, true) then return true end
    return menuThinLine(owner, tex)
end
local function menuClose(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= 0.08
end
-- Disabled rows are a flat gray. Ordinary rows are near white. Titles use the
-- game's gold (NORMAL_FONT_COLOR). Anything else (class, quality) stays.
local function menuGray(r, g, b)
    return menuClose(r, g) and menuClose(g, b) and type(r) == "number" and r < 0.8 and r > 0.2
end
local function menuWhite(r, g, b)
    return type(r) == "number" and r > 0.92 and g > 0.92 and b > 0.92
end
local function menuGold(r, g, b)
    return type(r) == "number" and r > 0.9 and g > 0.72 and g < 0.9 and b < 0.15
end
-- role: "radio" the chosen one, "marker" a raid-target row, "title" a heading.
local function menuInk(fs, role)
    local r, g, b = fs:GetTextColor()
    if menuGray(r, g, b) then return end
    if role == "radio" then Style.InkText(fs, "pop"); return end
    if role == "title" then
        if menuGold(r, g, b) or menuWhite(r, g, b) then Style.InkText(fs, "pop") end
        return
    end
    if menuGold(r, g, b) then Style.InkText(fs, "pop"); return end
    if role == "marker" or menuWhite(r, g, b) then Style.InkText(fs, "TEXT") end
end
local function menuShown(tex)
    return tex and (not tex.IsShown or tex:IsShown())
end
-- One row, or a title or divider frame. Textures already on it, never new ones.
local function dressEntry(frame)
    if type(frame) ~= "table" or not frame.GetRegions then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local isButton = frame.IsObjectType and frame:IsObjectType("Button")
    local radial, hasMarker, picked = false, false, false
    if frame.leftTexture1 then
        if menuSelectKind(frame.leftTexture1) == "radio" then radial = true end
        frame.leftTexture1:SetAlpha(0)
    end
    if menuShown(frame.leftTexture2) then
        if menuSelectKind(frame.leftTexture2) == "radio" then radial = true end
        picked = true
        frame.leftTexture2:SetAlpha(1)
        frame.leftTexture2:SetTexture(MENU_TICK)
        if frame.leftTexture2.SetTexCoord then frame.leftTexture2:SetTexCoord(0, 1, 0, 1) end
        if frame.leftTexture2.SetSize then frame.leftTexture2:SetSize(14, 14) end
        Style.PaintAccent(frame.leftTexture2)
    end
    for _, tex in ipairs({ frame:GetRegions() }) do
        if tex.GetObjectType and tex:GetObjectType() == "Texture"
            and tex ~= frame.leftTexture1 and tex ~= frame.leftTexture2 then
            -- Hover, arrow and divider first. The marker name matches the
            -- whole row, and the hover would otherwise become the icon.
            if menuIsHighlight(frame, tex) then
                paintMenuLine(tex)
                if tex.SetBlendMode then tex:SetBlendMode("ADD") end
                Style.PaintAccent(tex, ns.Kit.ROW_PICK)
            elseif menuIsArrow(frame, tex) then
                tex:SetTexture(MENU_CHEVRON)
                if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
                if tex.SetSize then tex:SetSize(10, 10) end
                if tex.SetRotation then tex:SetRotation(MENU_CHEVRON_RIGHT) end
                local c = Style.INK.LABEL
                tex:SetVertexColor(c[1], c[2], c[3], 1)
            elseif menuIsDivider(frame, tex) then
                paintMenuLine(tex)
                if tex.SetHeight then tex:SetHeight(1) end
                local c = Style.NEUTRAL
                tex:SetVertexColor(c[1], c[2], c[3], 0.85)
            elseif menuMarkerArt(tex, frame) then hasMarker = true
            end
        end
    end
    local role
    if picked and (radial or hasMarker) then role = "radio"
    elseif hasMarker then role = "marker"
    elseif not isButton then role = "title" end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then menuInk(region, role) end
    end
end
local function menuArtBack(menu)
    local holder = menuShell[menu]
    if not menu.GetChildren then return false end
    for _, child in ipairs({ menu:GetChildren() }) do
        if child ~= holder and child.GetRegions and not (child.IsForbidden and child:IsForbidden()) then
            local tick = child.leftTexture2
            if menuShown(tick) and tick.GetTexture and not menuOurFile(tick, MENU_TICK) then
                local kind = menuSelectKind(tick)
                if kind == "check" or kind == "radio" then return true end
            end
            for _, tex in ipairs({ child:GetRegions() }) do
                if tex.GetObjectType and tex:GetObjectType() == "Texture"
                    and tex ~= child.leftTexture1 and tex ~= child.leftTexture2 and tex.GetTexture then
                    if menuIsHighlight(child, tex) then
                        if not menuIsOurLine(tex) then return true end
                    elseif menuIsArrow(child, tex) then
                        if not menuOurFile(tex, MENU_CHEVRON) then return true end
                    elseif menuIsDivider(child, tex) then
                        if not menuIsOurLine(tex) then return true end
                    elseif menuMarkerNumber(tex, child) and not menuOurFile(tex, "marker-") then
                        return true
                    end
                end
            end
        end
    end
end
-- One step under the menu, so the whole menu (rows included) paints over the
-- panel. A child cannot sit on a lower strata than its parent, which is why
-- the panel is not parented to the menu.
local MENU_UNDER = {
    TOOLTIP = "FULLSCREEN_DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", FULLSCREEN = "DIALOG",
    DIALOG = "HIGH", HIGH = "MEDIUM", MEDIUM = "LOW", LOW = "BACKGROUND",
}
-- The game gives a menu no parent and shows it over the screen's top frame:
-- UIParent, or the barber shop's own while it hides UIParent. The panel goes on
-- that same frame, or the hidden UIParent took it out of sight with it.
local function menuParent(menu)
    local p = menu.GetParent and menu:GetParent()
    if p then return p end
    if type(GetAppropriateTopLevelParent) == "function" then
        p = GetAppropriateTopLevelParent()
        if type(p) == "table" then return p end
    end
    return UIParent
end
local function placeMenuShell(menu, holder)
    local parent = menuParent(menu)
    if holder:GetParent() ~= parent then holder:SetParent(parent) end
    local strata = menu.GetFrameStrata and menu:GetFrameStrata()
    holder:SetFrameStrata(MENU_UNDER[strata] or "MEDIUM")
    local level = menu.GetFrameLevel and menu:GetFrameLevel()
    holder:SetFrameLevel(type(level) == "number" and level > 0 and level - 1 or 0)
    holder:ClearAllPoints()
    holder:SetAllPoints(menu)
    holder:Show()
end
local function dressMenu(Kit, menu)
    if type(menu) ~= "table" or not menu.GetRegions or (menu.IsForbidden and menu:IsForbidden()) then return end
    Kit.Strip(menu)
    local holder = menuShell[menu]
    if not holder then
        holder = CreateFrame("Frame", nil, menuParent(menu))
        holder:EnableMouse(false)
        holder.includeInLayout = false
        holder.ignoreInLayout = true
        Kit.Shell(holder, "window")
        menuShell[menu] = holder
    end
    placeMenuShell(menu, holder)
    -- Refresh rebuilds rows in place, so this frame watches for the game's tick,
    -- line or raid icon coming back (ten times a second is quicker than the eye).
    -- The font is checked every frame, or the game's wider text would flash.
    holder.wait = 0
    holder:SetScript("OnUpdate", function(self, elapsed)
        if menu.IsShown and not menu:IsShown() then self:Hide(); return end
        menuFonts(menu, 5)
        self.wait = self.wait + (elapsed or 0)
        if self.wait < 0.1 then return end
        self.wait = 0
        if menuArtBack(menu) then requestMenu(menu) end
    end)
    menuFonts(menu, 5)
    if menu.GetChildren then
        for _, child in ipairs({ menu:GetChildren() }) do
            if child ~= holder then DUI.SafeCall(dressEntry, child) end
        end
    end
end

local menuListener = {} -- the EventRegistry owner
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
    requestMenu = note
    -- Every menu as it shows, and again a moment later since rows can arrive
    -- after.
    registry:RegisterCallback("MenuProxy.OnShow", function(_, menu)
        note(menu)
        C_Timer.After(0.1, function() note(menu) end)
    end, menuListener)
end })
