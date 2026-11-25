-- Selected recipe, the right side of the window: what it makes (icon, name in item
-- quality, skill-up text in the difficulty color, how many can be made), its
-- description, materials as item tiles (have / need, short ones in red), and what it
-- requires (an anvil, a fire). Crafting controls are in the footer (Make.lua).
-- Enchants can also name a target: pick an item once and the footer enchants it with
-- no click; pick nothing and the game asks for a click (own gear or a trade item).

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Recipe = {}
ns.Recipe = Recipe

local function TS() return type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil end
local secret = DUI.IsSecret

local function call(name, ...)
    local ts = TS()
    local fn = ts and ts[name]
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    return ok and a or nil
end

local function itemLink(itemID)
    if not (C_Item and type(C_Item.GetItemInfo) == "function") then return nil end
    local _, link = C_Item.GetItemInfo(itemID)
    return type(link) == "string" and not secret(link) and link or nil
end

-- The open profession's learned recipe that makes an item, if any (a material you
-- can craft yourself, like Bolt of Silk Cloth for Tailoring).
function Recipe.MakerOf(itemID)
    local data = ns.List.data
    if not (data and data.byID and itemID) then return nil end
    for id in pairs(data.byID) do
        if ns.Data.OutputItem(id) == itemID then return id end
    end
    return nil
end

local function itemTip(b)
    local m = b.spec and b.spec.mat
    if not (m and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if type(GameTooltip.SetItemByID) == "function" then GameTooltip:SetItemByID(m.itemID) end
    if Recipe.MakerOf(m.itemID) then
        DUI.Tips.Clear()
        DUI.Tips.Hint(L["Click: show its recipe"])
        DUI.Tips.Flush(GameTooltip)
    end
    GameTooltip:Show()
end

-- A click on a material you can make picks its recipe.
local function matClick(b)
    local m = b.spec and b.spec.mat
    local id = m and Recipe.MakerOf(m.itemID)
    if id then ns.Window.Select(id) end
end

local function resultTip(b)
    local r = b.lineSpec and b.lineSpec.recipe
    if not (r and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if type(GameTooltip.SetRecipeResultItem) == "function" then GameTooltip:SetRecipeResultItem(r.id)
    elseif r.link and type(GameTooltip.SetHyperlink) == "function" then GameTooltip:SetHyperlink(r.link) end
    GameTooltip:Show()
    return ns.Data.ResultLink(r)   -- Shift compares the made item
end

-- Requirements: "Requires Anvil, Blacksmith Hammer", each colored met or not.
local function requires(id)
    local list = call("GetRecipeRequirements", id)
    if type(list) ~= "table" or #list == 0 then return nil end
    local INK, Hex = Style.INK, Win.Parts.Hex
    local bits = {}
    for _, req in ipairs(list) do
        if type(req) == "table" and type(req.name) == "string" and not secret(req.name) then
            bits[#bits + 1] = Hex(req.met == false and INK.BAD or INK.GOOD) .. req.name .. "|r"
        end
    end
    if #bits == 0 then return nil end
    return Hex(INK.LABEL) .. (REQUIRES_LABEL or L["Requires"]) .. "|r " .. table.concat(bits, Hex(INK.LABEL) .. ", |r")
end

local function targetTip(b)
    local guid = b.lineSpec and b.lineSpec.guid
    if not (guid and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if type(GameTooltip.SetItemByGUID) == "function" then GameTooltip:SetItemByGUID(guid) end
    GameTooltip:Show()
end

local function openTargets(b, r, list, current)
    local keys, values = { "" }, { [""] = L["None: click the item"] }
    for _, t in ipairs(list) do
        keys[#keys + 1] = t.guid
        values[t.guid] = t.name
    end
    DUI.Widgets.OpenMenu(b, keys, values, current and current.guid or "", function(guid)
        if guid == "" then ns.Make.ClearTarget(r) else ns.Make.SetTarget(guid) end
        Recipe.Fill(Recipe.pane, r, true)
        local line = Recipe.pane.target
        if line and DUI.Motion then DUI.Motion.Fade(line, 0, 1, DUI.Motion.FAST) end
    end, 240)
end

-- "Enchant on": the item, or the text offering to pick one. Empty when the game lists
-- no item; the enchant then asks for a click as usual.
local function target(pane, s, r)
    local t, list = ns.Make.TargetFor(r)
    pane.target = nil
    if #list == 0 then return end
    local INK = Style.INK
    s:Section(L["Enchant on"])
    local function pick(b) openTargets(b, r, list, t) end
    if t then
        local color = type(t.quality) == "number" and { Win.Parts.QualityColor(t.quality) } or INK.VALUE
        pane.target = s:Line({ guid = t.guid, icon = t.icon, text = t.name, color = color,
            sub = L["Click to pick another"], subColor = INK.LABEL, onClick = pick, tooltip = targetTip })
    else
        pane.target = s:Line({ text = L["Click the item to enchant"], color = INK.TEXT,
            sub = L["Or pick one here to skip the click"], subColor = INK.LABEL, onClick = pick })
    end
end

-- Skill-up range: where the recipe turns yellow, green and gray, as a bar of four
-- colored pieces with your skill marked on it, and the chance of a point now.
Recipe.RANGE_H = 46
Recipe.RANGE_BAR = 6
Recipe.TICK = { 2, 14 }      -- the marker for your skill: width, height
Recipe.LABEL_ROOM = 26       -- a threshold's number needs this much room to show

local function rangeTip(b)
    local range = b.range
    if not range then return end
    local D = ns.Data
    local function word(diff, n)
        local c = D.Color(diff)
        return Win.Parts.Hex(c) .. tostring(n) .. "|r"
    end
    DUI.Widgets.Tooltip(b, L["Skill-up range"], string.format(
        L["Yellow from %s, green from %s, gray from %s. Orange recipes always give a point; yellow ones usually, green ones sometimes, gray ones never."],
        word(D.MEDIUM, range.yellow), word(D.EASY, range.green), word(D.TRIVIAL, range.gray)))
end

local function makeRange(parent)
    local W = DUI.Widgets
    local b = CreateFrame("Frame", nil, parent)
    b:EnableMouse(true)
    b.you = Style.Text(b, Style.SIZE.small, "LEFT")
    b.you:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.odds = Style.Text(b, Style.SIZE.small, "RIGHT")
    b.odds:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    b.parts = {}
    for i = 1, 4 do b.parts[i] = W.Bar(b, Recipe.RANGE_BAR) end
    b.tick = b:CreateTexture(nil, "OVERLAY")
    b.tick:SetTexture("Interface\\Buttons\\WHITE8X8")
    local white = Style.INK.VALUE
    b.tick:SetVertexColor(white[1], white[2], white[3], 1)
    local white = Style.INK.VALUE
    b.tick:SetVertexColor(white[1], white[2], white[3], 1)
    b.tick:SetSize(Recipe.TICK[1], Recipe.TICK[2])
    b.marks = {}
    for i = 1, 3 do b.marks[i] = Style.Text(b, Style.SIZE.tiny, "CENTER") end
    b:SetScript("OnEnter", rangeTip)
    b:SetScript("OnLeave", W.HideTooltip)
    return b
end

-- Lay the pieces out over width w: the bar runs from a little before yellow (or your
-- skill, if lower) to a little past gray (or your skill, if higher).
local function layRange(b, w)
    local range, skill = b.range, b.skill
    if not (range and skill) then return end
    local span = math.max(10, range.gray - range.yellow)
    local lo = math.max(0, math.min(skill, range.yellow - math.ceil(span / 2)))
    local hi = math.max(skill + 1, range.gray + math.ceil(span / 4))
    local function x(v) return math.floor((v - lo) / (hi - lo) * w + 0.5) end
    local D = ns.Data
    local cuts = { lo, range.yellow, range.green, range.gray, hi }
    local kinds = { D.OPTIMAL, D.MEDIUM, D.EASY, D.TRIVIAL }
    local y = -(Style.SIZE.small + 8)
    for i, bar in ipairs(b.parts) do
        local x1, x2 = x(cuts[i]), x(cuts[i + 1])
        bar:ClearAllPoints()
        if x2 - x1 >= Recipe.RANGE_BAR then
            bar:SetPoint("TOPLEFT", b, "TOPLEFT", x1 + (i > 1 and 1 or 0), y)
            bar:SetWidth(x2 - x1 - (i > 1 and 1 or 0))
            bar:SetValue(1)
            local c = D.Color(kinds[i])
            DUI.Widgets.BarFrom(bar, c[1], c[2], c[3])
            bar:Show()
        else
            bar:Hide()
        end
    end
    local tickX = x(math.min(skill, hi))
    local M = DUI.Motion
    local function at(v)
        b.tickX = v
        b.tick:ClearAllPoints()
        b.tick:SetPoint("CENTER", b, "TOPLEFT", v, y - Recipe.RANGE_BAR / 2)
    end
    if M and b.tickX and b.tickX ~= tickX and b:IsVisible() then
        b.glide = b.glide or {}
        M.Tween(b.glide, b.tickX, tickX, M.SLOW, at)
    else
        at(tickX)
    end
    -- The three threshold numbers under the bar, each in its color. Green steps aside
    -- when it would crowd the others (a range only a few points wide).
    local marks = { { range.yellow, D.MEDIUM }, { range.green, D.EASY }, { range.gray, D.TRIVIAL } }
    for i, m in ipairs(marks) do
        local fs = b.marks[i]
        local mx = x(m[1])
        local crowd = i == 2 and (mx - x(range.yellow) < Recipe.LABEL_ROOM or x(range.gray) - mx < Recipe.LABEL_ROOM)
        local half = Recipe.LABEL_ROOM / 2
        fs:ClearAllPoints()
        fs:SetPoint("TOP", b, "TOPLEFT", math.max(half, math.min(w - half, mx)), y - Recipe.RANGE_BAR - 4)
        fs:SetText(tostring(m[1]))
        local c = D.Color(m[2])
        fs:SetTextColor(c[1], c[2], c[3])
        fs:SetShown(not crowd)
    end
    if range.gray <= range.yellow then b.marks[2]:Hide() end
end

-- The range piece for recipe r, or nothing when its range isn't known.
function Recipe.Range(s, r)
    if ns.Setting("skillUps") ~= true then return nil end
    local D = ns.Data
    local prof = ns.List.data and ns.List.data.prof
    local skill = D.Skill(prof)
    local range = D.RangeFor(r, skill)
    if not range then return nil end
    local b = s:Piece("range", makeRange, Recipe.RANGE_H, 10, "range")
    b.range, b.skill = range, skill
    local Hex, INK = Win.Parts.Hex, Style.INK
    local pop = Hex({ Style.Pop() })
    b.you:SetText(string.format(L["You: %s"], pop .. tostring(skill) .. "|r"))
    Style.InkText(b.you, "LABEL")
    local chance = D.ChanceText(D.Chance(r, skill))
    b.odds:SetText(chance and string.format(L["%s chance of a skill point"], pop .. chance .. "|r") or "")
    b.odds:SetTextColor(INK.TEXT[1], INK.TEXT[2], INK.TEXT[3])
    b.Stretch = function(w) layRange(b, w) end
    layRange(b, s:Width())
    return b
end

-- Favorite and Track, quiet links under the recipe's name, in the game's own words.
-- Each says what a click does next and changes as it's clicked.
Recipe.ACTS_H = 20
Recipe.ACTS_GAP = 16

local function actWords(r)
    local fav = r.favorite and (BATTLE_PET_UNFAVORITE or L["Remove Favorite"]) or (BATTLE_PET_FAVORITE or L["Set Favorite"])
    local track = ns.Track.Is(r.id) and (PROFESSIONS_UNTRACK_RECIPE or L["Untrack"]) or (PROFESSIONS_TRACK_RECIPE or L["Track Recipe"])
    return fav, track
end

function Recipe.PaintActs(b)
    local r = b.recipe
    if not r then return end
    local fav, track = actWords(r)
    local M = DUI.Motion
    for _, pair in ipairs({ { b.fav, fav }, { b.track, track } }) do
        local link, words = pair[1], pair[2]
        if link.words ~= words then
            if link.words and M then M.Fade(link.text, 0, 1, M.FAST) end
            link.words = words
            link.SetLabel(words)
        end
    end
    b.track:ClearAllPoints()
    if b.fav:IsShown() then
        b.track:SetPoint("LEFT", b.fav, "RIGHT", Recipe.ACTS_GAP, 0)
    else
        b.track:SetPoint("LEFT", b, "LEFT", 0, 0)
    end
end

local function makeActs(parent)
    local W = DUI.Widgets
    local b = CreateFrame("Frame", nil, parent)
    b.fav = W.Link(b)
    b.fav:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.fav:SetScript("OnClick", function()
        local r = b.recipe
        if not r then return end
        r.favorite = not r.favorite
        ns.List.Favorite(r, r.favorite)
        Recipe.PaintActs(b)
    end)
    b.track = W.Link(b)
    b.track:SetScript("OnClick", function()
        local r = b.recipe
        if not r then return end
        ns.Track.Set(r.id, not ns.Track.Is(r.id))
        Recipe.PaintActs(b)
    end)
    return b
end

function Recipe.Acts(s, r)
    local D = ns.Data
    local canFav, canTrack = D.CanFavorite(), D.CanTrack(r)
    if not (canFav or canTrack) then return nil end
    local b = s:Piece("acts", makeActs, Recipe.ACTS_H, 2, "acts")
    b.recipe = r
    b.fav:SetShown(canFav)
    b.track:SetShown(canTrack)
    Recipe.PaintActs(b)
    Recipe.acts = b
    return b
end

-- Profit: what the materials cost, what it sells for, the Auction House's cut and
-- what's left, one row each with the number on the right. A row with no number
-- stays out; a short sentence under them says why one is missing.
Recipe.PROFIT_ROW = 20

local function sourceWords(src)
    if src == "vendor" then return L["vendor"] end
    if src == "craft" then return L["made by you"] end
    return L["Auction House"]
end

local function matsTip(row)
    local p = row.profit
    if not (p and GameTooltip) then return end
    local Tips, INK = DUI.Tips, Style.INK
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    Tips.Clear()
    Tips.Title(L["Materials"])
    for _, m in ipairs(p.mats) do
        local label = m.n > 1 and string.format(L["%d %s"], m.n, m.name) or m.name
        if m.each then
            Tips.Line(label .. "  " .. Win.Parts.Hex(INK.LABEL) .. sourceWords(m.src) .. "|r", DUI.Widgets.Money(m.each * m.n), INK.VALUE)
        else
            Tips.Line(label, L["No price yet"], INK.LABEL)
        end
    end
    if p.yield ~= 1 then Tips.Text(string.format(L["One craft makes about %s."], string.format("%g", p.yield))) end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function sellTip(row)
    local p = row.profit
    if not (p and GameTooltip) then return end
    local Tips = DUI.Tips
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    Tips.Clear()
    Tips.Title(L["Sells for"])
    if p.yield ~= 1 and p.each then
        Tips.Text(string.format(L["About %s made, at %s each on the Auction House."], string.format("%g", p.yield), DUI.Widgets.Money(p.each)))
    else
        Tips.Text(L["Its usual price at the Auction House."])
    end
    local P = DUI.AuctionPrices
    if p.seenAt and P and P.Ago then Tips.Sub(string.format(L["Seen %s ago"], P.Ago(p.seenAt))) end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function cutTip(row)
    if not GameTooltip then return end
    DUI.Widgets.Tooltip(row, L["Auction House cut"],
        string.format(L["The Auction House keeps %s of every sale."], string.format("%g%%", (DUI.AuctionPrices and DUI.AuctionPrices.CUT or 0.05) * 100)))
end

local function makeProfit(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, b)
        row:SetHeight(Recipe.PROFIT_ROW)
        row:EnableMouse(true)
        row.label = Style.Text(row, Style.SIZE.body, "LEFT")
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.value = Style.Text(row, Style.SIZE.body, "RIGHT")
        row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row:SetScript("OnLeave", DUI.Widgets.HideTooltip)
        b.rows[i] = row
    end
    return b
end

-- The rows' last values, so a number that changes while shown eases in.
Recipe.profitShown = {}

local function profitRow(b, i, y, label, value, color, tip)
    local row = b.rows[i]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -y)
    row.label:SetText(label)
    Style.InkText(row.label, "TEXT")
    row.value:SetText(value)
    row.value:SetTextColor(color[1], color[2], color[3])
    row:SetScript("OnEnter", tip)
    row:Show()
    local key = b.recipeID .. ":" .. i
    local was = Recipe.profitShown[key]
    Recipe.profitShown[key] = value
    if was and was ~= value and DUI.Motion then DUI.Motion.Fade(row.value, 0, 1, DUI.Motion.FAST) end
    return y + Recipe.PROFIT_ROW
end

function Recipe.Profit(s, r)
    local p = ns.Profit.Of(r)
    if not (p and p.known) then return nil end
    local INK, W = Style.INK, DUI.Widgets
    s:Section(L["Profit"])
    local rows = {}
    if p.cost then rows[#rows + 1] = { L["Materials"], W.Money(p.cost), INK.VALUE, matsTip } end
    if p.value then
        rows[#rows + 1] = { L["Sells for"], W.Money(p.value), INK.VALUE, sellTip }
        rows[#rows + 1] = { L["Auction House cut"], "-" .. W.Money(p.cut, { color = false }), INK.LABEL, cutTip }
    end
    if p.profit then
        local text = ns.Profit.Money(p.profit)
        if p.pct then text = text .. "  (" .. p.pct .. "%)" end
        rows[#rows + 1] = { L["Profit"], text, ns.Profit.Color(p.profit) }
    end
    local b = s:Piece("profit", makeProfit, #rows * Recipe.PROFIT_ROW, 2, "profit")
    b.recipeID = r.id
    local y = 0
    for i, row in ipairs(rows) do
        b.rows[i].profit = p
        y = profitRow(b, i, y, row[1], row[2], row[3], row[4])
    end
    for i = #rows + 1, #b.rows do b.rows[i]:Hide() end
    if p.why then s:Why(p.why) end
    return b
end

-- A recipe's cooldown, worded the way the game's recipe page does it: charges when it
-- has them, else the time left (a daily one under a day says it resets at midnight).
-- Nil when it's ready.
Recipe.CD_TICK = 30   -- s between repaints of the time left

local function timeLeft(sec)
    if type(SecondsToTime) == "function" then
        local s = SecondsToTime(sec, sec >= 60, false, 2)
        if type(s) == "string" and s ~= "" then return s end
    end
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return string.format(L["%d d %d h"], d, h) end
    if h > 0 then return string.format(L["%d h %d min"], h, m) end
    if m > 0 then return string.format(L["%d min"], m) end
    return string.format(L["%d sec"], math.ceil(sec))
end

function Recipe.CooldownWords(id)
    local left, isDay, charges, max = ns.Data.Cooldown(id)
    local Hex, INK = Win.Parts.Hex, Style.INK
    if max and max > 0 and charges and (charges > 0 or not left) then
        local have = Hex({ Style.Pop() }) .. string.format("%d/%d", charges, max) .. "|r"
        if charges < max and left then
            return Hex(INK.LABEL) .. string.format(L["Charges: %s, the next in %s"], have .. Hex(INK.LABEL),
                Hex(INK.VALUE) .. timeLeft(left) .. "|r")
        end
        return Hex(INK.LABEL) .. string.format(L["Charges: %s"], have)
    end
    if not left then return nil end
    if isDay and left <= 86400 then
        return Hex(INK.BAD) .. (COOLDOWN_EXPIRES_AT_MIDNIGHT or L["Cooldown expires at midnight"]) .. "|r"
    end
    return Hex(INK.LABEL) .. (COOLDOWN_REMAINING or L["Cooldown remaining:"]) .. "|r " .. Hex(INK.BAD) .. timeLeft(left) .. "|r"
end

-- Keeps the time left current while the recipe is shown; once it's ready the list
-- reads again, which drops the line and frees Create.
function Recipe.WatchCooldown(r, line)
    local token = {}
    Recipe.cdWatch = token
    if not (line and C_Timer) then return end
    C_Timer.After(Recipe.CD_TICK, function()
        if Recipe.cdWatch ~= token or ns.Make.recipe ~= r then return end
        local pane = Recipe.pane
        if not (pane and pane:IsVisible()) then return end
        local words = Recipe.CooldownWords(r.id)
        if words then
            line.text:SetText(words)
            Recipe.WatchCooldown(r, line)
        else
            ns.List.Soon(0)
        end
    end)
end

function Recipe.Build(pane)
    Recipe.pane = pane
    pane.stack = Win.Parts.Stack(pane, { top = 12, bottom = ns.Make.FOOT })
    ns.Make.Build(pane)
    pane.note = Style.Text(pane, Style.SIZE.body, "CENTER")
    pane.note:SetPoint("CENTER", pane, "CENTER", 0, 0)
    Style.InkText(pane.note, "LABEL")
    pane.note:SetText(L["Pick a recipe."])
    pane.note:Hide()
end

-- Show recipe r (from List.data), nil = none. keep: a refill keeps the scroll.
function Recipe.Fill(pane, r, keepScroll)
    pane = pane or Recipe.pane
    if not pane then return end
    local s = pane.stack
    local at = keepScroll and s:Scrolled() or 0
    s:Begin()
    pane.note:SetShown(r == nil)
    ns.Make.Paint(r)
    if not r then pane.pieces = s:End(); return end
    local INK = Style.INK
    local q = ns.Data.OutputQuality(r.id)
    local name = type(q) == "number" and { Win.Parts.QualityColor(q) } or INK.TITLE
    local count = r.count > 0 and string.format(L["You can make %d"], r.count) or (not r.free and L["Missing materials"]) or ""
    s:Line({ recipe = r, icon = r.icon, text = r.name, color = name,
        sub = ns.Data.SkillWords(r.difficulty), subColor = ns.Data.Color(r.difficulty),
        value = count, valueColor = r.count > 0 and { Style.Accent() } or INK.LABEL, tooltip = resultTip,
        link = function() return ns.Data.ResultLink(r) end })
    Recipe.Acts(s, r)
    local cd = Recipe.CooldownWords(r.id)
    pane.cooldown = cd and s:Text(cd, { color = INK.TEXT, size = Style.SIZE.small, gap = 8 }) or nil
    Recipe.WatchCooldown(r, pane.cooldown)
    Recipe.Range(s, r)
    local desc = call("GetRecipeDescription", r.id, {})
    if type(desc) == "string" and not secret(desc) and desc ~= "" then
        s:Text(DUI.Tips and DUI.Tips.Numbers and DUI.Tips.Numbers(desc) or desc, { color = INK.TEXT, gap = 10 })
    end
    if r.enchant then target(pane, s, r) end
    if #r.mats > 0 then
        s:Section(L["Materials"])
        local items = {}
        for _, m in ipairs(r.mats) do
            local short = m.have < m.need
            items[#items + 1] = { mat = m, name = m.name or "", texture = m.icon, quality = m.quality, nameColor = INK.VALUE,
                sub = string.format(L["%d / %d"], m.have, m.need), subColor = short and INK.BAD or INK.GOOD,
                tooltip = itemTip, onClick = matClick, link = function() return itemLink(m.itemID) end }
        end
        s:Items(items)
    end
    local req = requires(r.id)
    if req then s:Text(req, { color = INK.TEXT, size = Style.SIZE.small, gap = 12 }) end
    Recipe.Profit(s, r)
    pane.pieces = s:End()
    s:ScrollTo(at)
end

function Recipe.Pieces(pane)
    local out = {}
    for i, p in ipairs(pane.pieces or {}) do
        if i > 10 then break end
        out[#out + 1] = p
    end
    return out
end
