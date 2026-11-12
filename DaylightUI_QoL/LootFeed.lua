-- Loot feed: what you just looted, as angled ribbons in the bottom right.
-- Looting more of the same item bumps its count instead of adding a ribbon, and
-- money adds up on one ribbon. Skill-ups get their own ribbon, and epics arrive
-- with a burst. lootFeedFlip mirrors the whole thing to the left side.
--
-- Built from your own loot and money chat messages, matched through the game's
-- format strings so it works in every language. These stay plain in chat
-- lockdown, but a secret one is skipped anyway. Money shows on PLAYER_MONEY while
-- looting; the later chat line only adds what that missed (a group split).

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel, Motion = DUI.Style, DUI.Pixel, DUI.Motion

local Feed = {
    ROW_H = 30,
    GAP = 4,
    ICON = 20,
    SLANT = 0.4,      -- the angled ends' cut, as a share of the height
    PAD = 8,          -- space between the cut and the contents
    MAX_W = 300,      -- a long name is cut short past this
    MAX = 6,          -- ribbons at once; the oldest makes room (setting lootFeedMax)
    HOLD = 5,         -- seconds a ribbon stays after its last loot (setting lootFeedHold)
    GRACE = 1.5,      -- seconds every ribbon stays at least after the mouse leaves
    SLIDE = 48,       -- px it slides in from
    OUT = 24,         -- px it drifts left as it fades out
    SHINE_W = 70,
    SHINE_ALPHA = 0.35,
    SHINE_DUR = 0.55,
    SHINE_LIFT = 0.35,  -- the light: the quality color lifted towards white
    EPIC = 4,         -- this quality and up arrives with a burst and a flash
    BURST = DUI.MEDIA .. "char-glow.png",
    BURST_FROM = 24, BURST_TO = 140,   -- the burst's size, px, as it spreads
    BURST_ALPHA = 0.8,
    FLASH_LIFT = 0.6, -- the edge's flash: the quality color lifted towards white
    TICK = 0.1,
    MONEY_MATCH = 2,  -- seconds a money gain and its chat line count as the same coins
    MOVER = "qol.loot",
    TEST_PART = "loot",
    -- The game's own lines for your loot, most specific first.
    ITEM_STRINGS = { "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF",
        "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
        "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" },
    MONEY_STRINGS = { "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT" },
    COINS = { { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } },
    COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01",
    -- The game's skill-up lines (CHAT_MSG_SKILL); a skill with no spell or
    -- gear of its own (a language) shows the book.
    SKILL_STRINGS = { "SKILL_RANK_UP", "ERR_SKILL_UP_SI" },
    SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_09",
    -- A weapon skill shows the weapon you hold of that kind; Defense your
    -- shield, else a plain one.
    WEAPON_SLOTS = { 16, 17, 18 },   -- main hand, off hand, ranged
    SHIELD_SLOT = 17,
    SHIELD_ICON = "Interface\\Icons\\INV_Shield_06",
    WEAPON_CLASS = 2, ARMOR_CLASS = 4, SHIELD_SUBCLASS = 6,
    FONT = "qol.loot.font",   -- its font's Media slot (lootFeedFont)
    -- Lowest item quality shown (lootFeedQuality).
    QUALITY = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4 },
    -- Test mode, unlock mode and the preview.
    SAMPLE = {
        { money = 124 },
        { name = "Large Spider Fang", quality = 2, icon = "Interface\\Icons\\INV_Misc_Bone_06" },
        { name = "Tough Spider Silk", quality = 1, icon = "Interface\\Icons\\INV_Misc_Thread_01", count = 2 },
        { name = "Band of the Webweaver", quality = 3, icon = "Interface\\Icons\\INV_Jewelry_Ring_04" },
        { skill = "Tailoring", rank = 152, max = 225, icon = "Interface\\Icons\\Trade_Tailoring" },
        { name = "Venomspitter", quality = 4, icon = "Interface\\Icons\\INV_Sword_26" },
    },
}
ns.LootFeed = Feed
ns.features[#ns.features + 1] = Feed
DUI.Media.RegisterSlot(Feed.FONT, "QoL", "lootFeedFont", "font")

local mod, wired, holder
local rows, pool = {}, {}   -- rows showing, newest first; spare rows
local sampling = false      -- the test/unlock sample is up
local hovered = nil         -- the row under the mouse: nothing leaves meanwhile
local acc = 0

local function enabled() return mod ~= nil and mod.db ~= nil and mod.db.lootFeed == true end
local function db(key) return mod and mod.db and mod.db[key] end
local function on(key) return db(key) ~= false end

-- Seconds a ribbon stays, from the setting.
function Feed.Hold()
    local v = mod and mod.db and tonumber(mod.db.lootFeedHold)
    return v and v > 0 and v or Feed.HOLD
end

-- Ribbons at once, from the setting.
function Feed.Max()
    local v = tonumber(db("lootFeedMax"))
    return v and v >= 1 and math.floor(v) or Feed.MAX
end

local function flipped() return db("lootFeedFlip") == true end

local function textSize()
    local v = tonumber(db("lootFeedTextSize"))
    return v and v > 0 and v or Style.SIZE.body
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- ---------------------------------------------------------------------
-- Reading the game's messages
-- ---------------------------------------------------------------------

-- A game format string ("You receive loot: %sx%d.") as a Lua pattern with
-- its holes as captures; positional holes ("%1$s") too.
function Feed.Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    -- A decimal (the reputation bonus lines' "%.1f", its dot escaped above).
    p = p:gsub("%%%d?%$?%%%.%d+f", "([%%d%%.,]+)"):gsub("%%%d?%$?f", "([%%d%%.,]+)")
    p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
    return p
end

local patterns
local function itemPatterns()
    if patterns then return patterns end
    patterns = {}
    for _, name in ipairs(Feed.ITEM_STRINGS) do
        local p = Feed.Pattern(_G[name])
        if p then patterns[#patterns + 1] = "^" .. p .. "$" end
    end
    return patterns
end

-- "You receive loot: [Tough Spider Silk]x2." -> link, 2. Nil for anyone
-- else's loot or another line.
function Feed.ParseItem(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    for _, p in ipairs(itemPatterns()) do
        local a, b = msg:match(p)
        if a then
            -- A language may put the count first.
            if b and tonumber(a) and not tonumber(b) then a, b = b, a end
            if a:find("|H", 1, true) then return a, tonumber(b) or 1 end
        end
    end
    return nil
end

-- "You loot 1 Silver, 24 Copper" -> 124 (copper). Nil for another line.
function Feed.ParseMoney(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    for _, name in ipairs(Feed.MONEY_STRINGS) do
        local p = Feed.Pattern(_G[name])
        local amount = p and msg:match("^" .. p .. "$")
        if amount then
            local total = 0
            for _, coin in ipairs(Feed.COINS) do
                local cp = Feed.Pattern(_G[coin[1]])
                local n = cp and amount:match(cp)
                if n then total = total + tonumber(n) * coin[2] end
            end
            if total > 0 then return total end
        end
    end
    return nil
end

-- "Your skill in Tailoring has increased to 152." -> "Tailoring", 152.
function Feed.ParseSkill(msg)
    if type(msg) ~= "string" or secret(msg) then return nil end
    for _, name in ipairs(Feed.SKILL_STRINGS) do
        local p = Feed.Pattern(_G[name])
        local a, b
        if p then a, b = msg:match("^" .. p .. "$") end
        if a and b then
            -- A language may put the rank first.
            if tonumber(a) and not tonumber(b) then a, b = b, a end
            if tonumber(b) then return a, tonumber(b) end
        end
    end
    return nil
end

-- What's in an equipped slot: its icon, item class, subclass and the
-- subclass's name ("One-Handed Maces"). Nil for an empty slot.
local function equipped(slot)
    local id = type(GetInventoryItemID) == "function" and GetInventoryItemID("player", slot)
    local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not id or type(info) ~= "function" then return nil end
    local _, _, subName, _, icon, class, sub = info(id)
    if type(GetInventoryItemTexture) == "function" then icon = GetInventoryItemTexture("player", slot) or icon end
    return icon, class, sub, subName
end

-- Icon for a combat skill: the held weapon of that kind, or the shield for
-- Defense. An exact subclass name wins, so "Two-Handed Maces" never matches a
-- one-handed mace. Nil for any other skill.
function Feed.GearIcon(name)
    if name == (_G.DEFENSE or "Defense") then
        local icon, class, sub = equipped(Feed.SHIELD_SLOT)
        if icon and class == Feed.ARMOR_CLASS and sub == Feed.SHIELD_SUBCLASS then return icon end
        return Feed.SHIELD_ICON
    end
    local near
    for _, slot in ipairs(Feed.WEAPON_SLOTS) do
        local icon, class, _, subName = equipped(slot)
        if icon and class == Feed.WEAPON_CLASS and type(subName) == "string" then
            if subName == name then return icon end
            if not near and subName:find(name, 1, true) then near = icon end
        end
    end
    return near
end

-- A skill's ribbon: its spell's icon (a profession) or its gear's (a
-- weapon, a shield), and its cap from the skill list when it's there.
function Feed.SkillOf(name, rank)
    local icon = Feed.GearIcon(name)
    local tex = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
    if not icon and type(tex) == "function" then
        local ok, t = pcall(tex, name)
        if ok then icon = t end
    end
    local max
    if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
        for i = 1, GetNumSkillLines() or 0 do
            local n, header, _, _, _, _, m = GetSkillLineInfo(i)
            if n == name and not header then max = tonumber(m) break end
        end
    end
    return { key = "skill:" .. name, skill = name, name = name, rank = rank, max = max, icon = icon or Feed.SKILL_ICON }
end

-- What a link shows: name, quality, icon. The quality from the cache, else
-- from the link itself; an item the client hasn't loaded yet is common.
function Feed.ItemOf(link)
    local id = tonumber(link:match("item:(%d+)"))
    local name = link:match("|h%[(.-)%]|h") or link
    local quality, icon
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(getInfo) == "function" then
        local ok, _, _, q, _, _, _, _, _, _, tex = pcall(getInfo, link)
        if ok then quality, icon = q, tex end
    end
    if type(quality) ~= "number" then quality = tonumber(link:match("|cnIQ(%d+):")) end
    if not icon then
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if type(instant) == "function" then
            local ok, _, _, _, _, tex = pcall(instant, link)
            if ok then icon = tex end
        end
    end
    -- Keyed by the name too: "of the Monkey" and "of Agility" share one id.
    return { key = id and (id .. ":" .. name) or name, link = link, name = name, quality = quality or 1, icon = icon }
end

-- ---------------------------------------------------------------------
-- The ribbons
-- ---------------------------------------------------------------------

local function qualityColor(e)
    if e.money then return Style.INK.MONEY end
    if e.skill then return { Style.Accent() } end
    return { DUI.Win.Parts.QualityColor(e.quality) }
end

-- Which ends are angled (lootFeedSlantSide): "both", "left" or "right".
local function slantSide()
    local s = db("lootFeedSlantSide")
    return (s == "left" or s == "right") and s or "both"
end

-- The cut of the angled ends, 0 for straight ends. With end_ ("left" or
-- "right") it returns that end's cut only.
local function cutOf(row, end_)
    if db("lootFeedSlant") == false then return 0 end
    local side = slantSide()
    if end_ and side ~= "both" and side ~= end_ then return 0 end
    return Pixel.Snap(row, Feed.ROW_H * Feed.SLANT)
end

-- The angled ends, parallel, leaning with the side the feed lines up on;
-- one end alone keeps the lean it has in the pair.
local function slant(row)
    local side, under = slantSide(), flipped() and "right" or "left"
    Style.Slant(row, side, cutOf(row), nil, (side == "both" or side == under) and under or nil)
end

-- Shell options from the settings. Each row gets its own table because a
-- recolor writes into it. No border and no background means no shadow either.
local function shellOpts()
    local noBack, noBorder = db("lootFeedBack") == false, db("lootFeedBorder") == false
    return { noBackground = noBack, noBorder = noBorder, noBevel = noBack,
        shadowAlpha = (noBack and noBorder) and 0 or nil,
        bgAlpha = Style.BackAlpha(db("lootFeedAlphaOwn"), db("lootFeedAlpha")) }
end

-- Its border: ours, the item's quality, the accent or the player's own.
local function paintBorder(row)
    local s, mode = row.shell, db("lootFeedBorderColor")
    if not s then return end
    local c = db("lootFeedBorderCustom")
    if mode == "accent" then
        Style.LightShell(s)
    elseif mode == "quality" and row.entry then
        Style.SetShellColors(s, qualityColor(row.entry))
    elseif mode == "custom" and type(c) == "table" then
        Style.SetShellColors(s, { c[1], c[2], c[3] })
    else
        Style.SetShellColors(s, nil)
    end
end

-- The resting border color, which the epic flash eases back to.
local function borderGoal(row)
    local mode, c = db("lootFeedBorderColor"), db("lootFeedBorderCustom")
    if mode == "accent" then return { Style.Accent() } end
    if mode == "quality" and row.entry then return qualityColor(row.entry) end
    if mode == "custom" and type(c) == "table" then return { c[1], c[2], c[3] } end
    return Style.BORDER
end

-- The item's own tooltip; money and the sample have no link: the name alone.
local function enter(row)
    hovered = row
    local e = row.entry
    if not (e and GameTooltip) or e.money or e.skill then return end
    GameTooltip:SetOwner(row, flipped() and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
    if e.link and type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetHyperlink(e.link)
    else
        local c = qualityColor(e)
        DUI.Tips.Clear()
        DUI.Tips.Title(e.name, c[1], c[2], c[3])
        DUI.Tips.Flush(GameTooltip)
    end
    GameTooltip:Show()
end

local function leaveMouse(row)
    if hovered == row then hovered = nil end
    if GameTooltip and GameTooltip:GetOwner() == row then GameTooltip:Hide() end
    local soon = GetTime() + Feed.GRACE
    for _, r in ipairs(rows) do
        if r.untilT and r.untilT < soon then r.untilT = soon end
    end
end

local function makeRow()
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(Feed.ROW_H)
    -- Pointed at for the tooltip; clicks go through to the world.
    row:EnableMouse(true)
    if row.SetMouseClickEnabled then row:SetMouseClickEnabled(false) end
    row:SetScript("OnEnter", enter)
    row:SetScript("OnLeave", leaveMouse)
    row.shell = Style.Shell(row, shellOpts())
    slant(row)
    -- The icon in an outline of its quality, a dark well under it (the
    -- item tiles' way: Parts).
    row.edge = row:CreateTexture(nil, "ARTWORK")
    row.edge:SetTexture(DUI.Win.Parts.WHITE)
    row.edge:SetSize(Feed.ICON + 2, Feed.ICON + 2)
    row.well = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.well:SetTexture(DUI.Win.Parts.WHITE)
    row.well:SetVertexColor(0, 0, 0, 1)
    row.well:SetPoint("TOPLEFT", row.edge, "TOPLEFT", 1, -1)
    row.well:SetPoint("BOTTOMRIGHT", row.edge, "BOTTOMRIGHT", -1, 1)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetAllPoints(row.well)
    Style.CropIcon(row.icon)
    row.name = Style.Text(row, textSize(), "LEFT", Feed.FONT)
    row.name:SetWordWrap(false)
    row.count = Style.Text(row, textSize() - 1, "LEFT", Feed.FONT)
    -- The light that runs across as it lands, kept inside the angled ends.
    row.shine = row:CreateTexture(nil, "OVERLAY", nil, 7)
    row.shine:SetTexture(DUI.Win.Parts.WHITE)
    row.shine:SetBlendMode("ADD")
    row.shine:SetHeight(Feed.ROW_H)
    row.shine:Hide()
    Style.Clip(row, row.shine, "inner")
    -- An epic's burst, spreading out from the icon past the ribbon.
    row.burst = row:CreateTexture(nil, "ARTWORK", nil, -8)
    row.burst:SetTexture(Feed.BURST)
    row.burst:SetBlendMode("ADD")
    row.burst:SetPoint("CENTER", row.edge, "CENTER", 0, 0)
    row.burst:Hide()
    Style.LayoutSlant(row)
    return row
end

-- A skill's rank, out of its cap: "152 / 225".
local function skillText(e, rank)
    local cap = e.max and e.max > 0 and (" " .. DUI.Win.Parts.Hex(Style.INK.LABEL) .. "/ " .. e.max .. "|r") or ""
    return rank .. cap
end

-- Icon of the biggest coin in an amount. This client has no global
-- GetCoinIcon, only C_CurrencyInfo.GetCoinIcon.
function Feed.CoinIcon(copper)
    local get = type(C_CurrencyInfo) == "table" and C_CurrencyInfo.GetCoinIcon
    return type(get) == "function" and type(copper) == "number" and get(copper) or Feed.COIN_ICON
end

-- Text and size for what the row holds now.
local function fill(row)
    local e = row.entry
    local c = qualityColor(e)
    row.edge:SetVertexColor(c[1], c[2], c[3], 1)
    if e.money then
        row.icon:SetTexture(Feed.CoinIcon(e.money))
        row.name:SetText("+ " .. DUI.MoneyString(e.money))
        Style.InkText(row.name, "MONEY")
        row.count:SetText("")
    elseif e.skill then
        row.icon:SetTexture(e.icon)
        row.name:SetText(e.name)
        Style.InkText(row.name, "VALUE")
        row.count:SetText(skillText(e, e.rank))
        Style.InkText(row.count, "pop")
    else
        row.icon:SetTexture(e.icon or 134400)
        row.name:SetText(e.name)
        if db("lootFeedNameColor") == "white" then
            Style.InkText(row.name, "VALUE")
        else
            row.name:SetTextColor(c[1], c[2], c[3], 1)
        end
        row.count:SetText(e.count > 1 and ("x" .. e.count) or "")
        Style.InkText(row.count, "pop")
    end
    paintBorder(row)
    local flip = flipped()
    -- The icon's end and the far end each take their own cut.
    local near, far = cutOf(row, flip and "right" or "left"), cutOf(row, flip and "left" or "right")
    local left = near + Feed.PAD
    row.edge:ClearAllPoints()
    if flip then
        row.edge:SetPoint("RIGHT", row, "RIGHT", -left, 0)
    else
        row.edge:SetPoint("LEFT", row, "LEFT", left, 0)
    end
    local countW = row.count:GetText() ~= "" and (row.count:GetStringWidth() or 0) + 4 or 0
    local room = Feed.MAX_W - left - (Feed.ICON + 2) - 8 - countW - Feed.PAD - far
    row.name:SetWidth(0)   -- unbounded while measured
    local nameW = math.min(row.name:GetStringWidth() or 0, room)
    row.name:SetWidth(nameW)
    row.name:ClearAllPoints()
    if flip then
        row.name:SetPoint("LEFT", row, "LEFT", far + Feed.PAD, 0)
    else
        row.name:SetPoint("LEFT", row.edge, "RIGHT", 8, 0)
    end
    row.count:ClearAllPoints()
    row.count:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row:SetWidth(math.floor(left + Feed.ICON + 2 + 8 + nameW + countW + Feed.PAD + far + 0.5))
    Style.LayoutSlant(row)
end

local function shine(row)
    if db("lootFeedShine") == false then return end
    local c = qualityColor(row.entry)
    local k = Feed.SHINE_LIFT
    Motion.Sweep(row.shine, row, { width = Feed.SHINE_W, dur = Feed.SHINE_DUR, alpha = Feed.SHINE_ALPHA,
        color = { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }, key = row.shine,
        reverse = flipped() })
end

-- A skill's number counting up to its new rank (the ribbon's width is the
-- new rank's, set by fill).
local function rollSkill(row, from)
    local e = row.entry
    row.rollKey = row.rollKey or {}
    if type(from) ~= "number" or from >= e.rank then return end
    Motion.Tween(row.rollKey, from, e.rank, Motion.SLOW, function(v)
        if row.entry == e then row.count:SetText(skillText(e, math.floor(v + 0.5))) end
    end)
end

-- An epic's arrival: the burst spreads from the icon and fades, and the
-- edge flashes bright in its color, settling back to the border setting.
local function epic(row)
    local e = row.entry
    if not (Motion.On() and e and not e.money and not e.skill and (e.quality or 0) >= Feed.EPIC) then return end
    local c = qualityColor(e)
    row.burst:SetVertexColor(c[1], c[2], c[3])
    row.burst:Show()
    Motion.Tween(row.burst, 0, 1, Motion.SLOW, function(p)
        local w = Feed.BURST_FROM + (Feed.BURST_TO - Feed.BURST_FROM) * p
        row.burst:SetSize(w, w * 0.6)
        row.burst:SetAlpha(Feed.BURST_ALPHA * (1 - p))
    end, function() row.burst:Hide() end)
    if db("lootFeedBorder") == false or not row.shell then return end
    local k = Feed.FLASH_LIFT
    local hi = { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
    local to = borderGoal(row)
    row.flashKey = row.flashKey or {}
    Motion.Tween(row.flashKey, 0, 1, Motion.SLOW, function(p)
        if row.entry ~= e then return end
        Style.SetShellColors(row.shell, { hi[1] + (to[1] - hi[1]) * p, hi[2] + (to[2] - hi[2]) * p, hi[3] + (to[3] - hi[3]) * p })
    end, function() if row.entry == e then paintBorder(row) end end)
end

local function stepOf(i) return (i - 1) * (Feed.ROW_H + Feed.GAP) end

local function growDown() return db("lootFeedGrow") == "down" end

-- Places a row by lootFeedGrow and lootFeedFlip. `out` is how many px it has
-- drifted on its way out.
local function place(row, out, y)
    row:ClearAllPoints()
    row.grewDown, row.flipped = growDown(), flipped()
    local spot = (row.grewDown and "TOP" or "BOTTOM") .. (row.flipped and "LEFT" or "RIGHT")
    row:SetPoint(spot, holder, spot, row.flipped and out or -out, row.grewDown and -y or y)
end

local function slideIn(row)
    Motion.SlideIn(row, flipped() and -Feed.SLIDE or Feed.SLIDE, 0, Motion.NORMAL)
end

-- Every row in its place, newest at the bottom; a row that moved glides
-- from where it was.
local function layout()
    local i = 0
    for _, row in ipairs(rows) do
        if not row.leaving then
            i = i + 1
            local y = stepOf(i)
            if row.y ~= y then
                local was = row.y
                row.y = y
                place(row, 0, y)
                if was then Motion.Glide(row, 0, growDown() and (y - was) or (was - y), Motion.NORMAL) end
            end
        end
    end
end

local function release(row)
    for i, r in ipairs(rows) do
        if r == row then table.remove(rows, i) break end
    end
    Motion.Settle(row)
    if row.flashKey then Motion.Tween(row.flashKey, 0, 0, 0) end
    if row.rollKey then Motion.Tween(row.rollKey, 0, 0, 0) end
    Motion.Tween(row.burst, 0, 0, 0)
    row.burst:Hide()
    if hovered == row then leaveMouse(row) end
    row:Hide()
    row.entry, row.y, row.leaving = nil, nil, nil
    pool[#pool + 1] = row
    layout()
end

-- Fades out drifting away from where it came in, then the rows above glide down.
local function leave(row, quick)
    if row.leaving then return end
    row.leaving = true
    local y = row.y or 0
    Motion.Tween(row, 0, 1, quick and Motion.FAST or Motion.CLOSE, function(p)
        row:SetAlpha(1 - p)
        place(row, Feed.OUT * p, y)
    end, function() release(row) end)
end

local function find(key)
    for _, row in ipairs(rows) do
        if not row.leaving and row.entry.key == key then return row end
    end
end

local function showing()
    local n = 0
    for _, row in ipairs(rows) do if not row.leaving then n = n + 1 end end
    return n
end

-- Adds one loot: { key, name, quality, icon, count } or { money = copper }.
-- With `hold` it stays until the sample ends (test and unlock mode).
function Feed.Add(e, hold)
    if not holder then return end
    e.key = e.money and "money" or (e.key or e.name)
    e.count = e.count or 1
    local until_ = not hold and (GetTime() + Feed.Hold()) or nil
    local row = find(e.key)
    if row then
        local cur = row.entry
        local wasRank = cur.rank
        if e.money then
            cur.money = cur.money + e.money
        elseif e.skill then
            cur.rank, cur.max = e.rank, e.max or cur.max
        else
            cur.count = cur.count + e.count
        end
        if e.icon then cur.icon = e.icon end
        if e.link then cur.link = e.link end
        row.untilT = until_
        fill(row)
        -- The count swells and settles by its font size, never a Scale
        -- animation: that stretched the drawn letters (huge, pixelated, stuck).
        if not e.money then
            local size = textSize() - 1
            Motion.Tween(row.count, size * 1.6, size, Motion.NORMAL, function(v)
                Style.SetTextSize(row.count, v)
            end)
        end
        Motion.Bump(row, 1.04, Motion.FAST)
        if e.skill then rollSkill(row, wasRank) end
        shine(row)
        return row
    end
    while showing() >= Feed.Max() do
        for i = #rows, 1, -1 do
            if not rows[i].leaving then leave(rows[i], true) break end
        end
    end
    row = table.remove(pool) or makeRow()
    row.entry, row.untilT = e, until_
    row:SetAlpha(1)
    table.insert(rows, 1, row)
    fill(row)
    row:Show()
    layout()
    slideIn(row)
    if e.skill then rollSkill(row, e.rank - 1) end
    epic(row)
    shine(row)
    holder:Show()
    return row
end

function Feed.Rows() return rows end

-- Ribbons whose time is up leave; nothing left, the holder rests.
function Feed.Tick()
    if hovered and not hovered:IsShown() then hovered = nil end
    local now = GetTime()
    -- Leaving together: every ribbon waits for the newest one's time (a
    -- sample ribbon, with none, keeps them all).
    local together = db("lootFeedTogether") == true
    local last = 0
    if together then
        for _, row in ipairs(rows) do
            if not row.leaving then last = row.untilT and math.max(last, row.untilT) or math.huge end
        end
    end
    for i = #rows, 1, -1 do
        local row = rows[i]
        local due = row and row.untilT and (together and last or row.untilT)
        if row and not hovered and not row.leaving and due and now >= due then leave(row) end
    end
    if #rows == 0 and holder then holder:Hide() end
end

-- ---------------------------------------------------------------------
-- Events, sample, preview
-- ---------------------------------------------------------------------

function Feed.OnLoot(msg)
    if not enabled() or not on("lootFeedItems") then return end
    local link, count = Feed.ParseItem(msg)
    if not link then return end
    local e = Feed.ItemOf(link)
    if e.quality < (Feed.QUALITY[db("lootFeedQuality")] or 0) then return end
    e.count = count
    Feed.Add(e)
end

function Feed.OnSkill(msg)
    if not enabled() or not on("lootFeedSkills") then return end
    local name, rank = Feed.ParseSkill(msg)
    if name then Feed.Add(Feed.SkillOf(name, rank)) end
end

-- Money shows as soon as PLAYER_MONEY fires while a loot window is open or just
-- closed. The chat line for the same coins arrives later and only adds what's left.
local lastMoney, looting, lootEnd = nil, false, -math.huge
local owed, ahead, stamp = 0, 0, -math.huge   -- coins shown by money / by chat, not yet matched

local function fresh()
    local now = GetTime()
    if now - stamp > Feed.MONEY_MATCH then owed, ahead = 0, 0 end
    stamp = now
end

local function readMoney()
    local m = type(GetMoney) == "function" and GetMoney() or nil
    return type(m) == "number" and not secret(m) and m or nil
end

function Feed.OnLootWindow(open)
    looting = open
    if not open then lootEnd = GetTime() end
    lastMoney = readMoney() or lastMoney
end

function Feed.OnMoneyChanged()
    local now = readMoney()
    if not now then return end
    local gain = lastMoney and now - lastMoney or 0
    lastMoney = now
    if gain <= 0 or not enabled() or not on("lootFeedMoney") then return end
    if not looting and GetTime() - lootEnd > Feed.MONEY_MATCH then return end
    fresh()
    local take = math.min(ahead, gain)
    ahead, gain = ahead - take, gain - take
    if gain > 0 then
        owed = owed + gain
        Feed.Add({ money = gain })
    end
end

function Feed.OnMoney(msg)
    if not enabled() or not on("lootFeedMoney") then return end
    local copper = Feed.ParseMoney(msg)
    if not copper then return end
    fresh()
    local take = math.min(owed, copper)
    owed, copper = owed - take, copper - take
    if copper > 0 then
        ahead = ahead + copper
        Feed.Add({ money = copper })
    end
end

local function sampleEntry(s)
    if s.skill then
        local name = L[s.skill]
        return { key = "skill:" .. name, skill = name, name = name, rank = s.rank, max = s.max, icon = s.icon }
    end
    return { key = s.name, name = s.name and L[s.name], quality = s.quality, icon = s.icon,
        count = s.count, money = s.money }
end

local function sampleWanted()
    if not enabled() then return false end
    if DUI.testMode and DUI.TestPartShown(Feed.TEST_PART) then return true end
    return DUI.Movers and DUI.Movers.unlocked == true
end

-- The sample up while test or unlock mode wants it; after, it leaves like loot.
function Feed.Sample()
    local want = sampleWanted()
    if want == sampling then return end
    sampling = want
    if want then
        for i = #Feed.SAMPLE, 1, -1 do Feed.Add(sampleEntry(Feed.SAMPLE[i]), true) end
    else
        local now = GetTime()
        for _, row in ipairs(rows) do if not row.untilT then row.untilT = now end end
        Feed.Tick()
    end
end

-- Plays the sample in one after another, as a looted mob would.
function Feed.Preview()
    if not holder then return end
    for i, s in ipairs(Feed.SAMPLE) do
        C_Timer.After((i - 1) * 0.28, function() Feed.Add(sampleEntry(s)) end)
    end
    C_Timer.After(#Feed.SAMPLE * 0.28 + 0.4, function()
        Feed.Add(sampleEntry(Feed.SAMPLE[3]))
        Feed.Add({ money = 37 })
        local skill = sampleEntry(Feed.SAMPLE[5])
        skill.rank = skill.rank + 1
        Feed.Add(skill)
    end)
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "DaylightUILootFeed", UIParent)
    holder:SetSize(Feed.MAX_W, Feed.Max() * (Feed.ROW_H + Feed.GAP) - Feed.GAP)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
    holder:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < Feed.TICK then return end
        acc = 0
        Feed.Tick()
    end)
    DUI.Movers.Register(holder, Feed.MOVER, "Loot feed", { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -40, 200 },
        { active = enabled })
end

-- Every ribbon, shown or spare, in the current settings (shell, text size,
-- colors), the holder as tall as its rows, each row in its spot.
local function restyle()
    local function dress(row)
        row.shell = Style.Shell(row, shellOpts())
        slant(row)
        Style.SetTextSize(row.name, textSize())
        Style.SetTextSize(row.count, textSize() - 1)
        if row.entry then fill(row) end
    end
    for _, row in ipairs(rows) do dress(row) end
    for _, row in ipairs(pool) do dress(row) end
    if not holder then return end
    holder:SetHeight(Feed.Max() * (Feed.ROW_H + Feed.GAP) - Feed.GAP)
    while showing() > Feed.Max() do
        for i = #rows, 1, -1 do
            if not rows[i].leaving then leave(rows[i], true) break end
        end
    end
    -- A changed grow direction or side: every row placed again and sliding
    -- in there (no glide across).
    local moved = {}
    for _, row in ipairs(rows) do
        if not row.leaving and (row.grewDown ~= growDown() or row.flipped ~= flipped()) then
            row.y = nil
            moved[#moved + 1] = row
        end
    end
    layout()
    for _, row in ipairs(moved) do slideIn(row) end
end

function Feed.Enable(m)
    mod = m
    if not wired then
        wired = true
        DUI.RegisterEvent("CHAT_MSG_LOOT", function(_, msg) Feed.OnLoot(msg) end)
        DUI.RegisterEvent("CHAT_MSG_MONEY", function(_, msg) Feed.OnMoney(msg) end)
        DUI.RegisterEvent("CHAT_MSG_SKILL", function(_, msg) Feed.OnSkill(msg) end)
        DUI.RegisterEvent("PLAYER_MONEY", Feed.OnMoneyChanged)
        DUI.RegisterEvent("LOOT_OPENED", function() Feed.OnLootWindow(true) end)
        DUI.RegisterEvent("LOOT_CLOSED", function() Feed.OnLootWindow(false) end)
        lastMoney = readMoney()
        DUI.RegisterTestPart(Feed.TEST_PART, "Loot feed", 96, enabled)
        DUI.On("TestModeChanged", Feed.Sample)
        DUI.On("TestPartChanged", function(key) if key == Feed.TEST_PART then Feed.Sample() end end)
        DUI.On("UnlockChanged", Feed.Sample)
        DUI.On("StyleChanged", restyle)
        DUI.RegisterCommand("loot", function()
            if enabled() then Feed.Preview() end
        end, L["/dui loot - preview the loot feed"])
    end
    if enabled() then build() end
end

function Feed.Refresh(m)
    mod = m
    if enabled() then
        build()
        restyle()
        Feed.Sample()
    elseif holder then
        sampling = false
        for i = #rows, 1, -1 do leave(rows[i], true) end
    end
end
