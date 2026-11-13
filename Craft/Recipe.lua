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
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

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

local function itemTip(b)
    local m = b.spec and b.spec.mat
    if not (m and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if type(GameTooltip.SetItemByID) == "function" then GameTooltip:SetItemByID(m.itemID) end
    GameTooltip:Show()
end

local function resultTip(b)
    local r = b.lineSpec and b.lineSpec.recipe
    if not (r and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if type(GameTooltip.SetRecipeResultItem) == "function" then GameTooltip:SetRecipeResultItem(r.id)
    elseif r.link and type(GameTooltip.SetHyperlink) == "function" then GameTooltip:SetHyperlink(r.link) end
    GameTooltip:Show()
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
    local count = r.count > 0 and string.format(L["You can make %d"], r.count) or L["Missing materials"]
    s:Line({ recipe = r, icon = r.icon, text = r.name, color = name,
        sub = ns.Data.SkillWords(r.difficulty), subColor = ns.Data.Color(r.difficulty),
        value = count, valueColor = r.count > 0 and { Style.Accent() } or INK.LABEL, tooltip = resultTip })
    Recipe.Acts(s, r)
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
                tooltip = itemTip, link = function() return itemLink(m.itemID) end }
        end
        s:Items(items)
    end
    local req = requires(r.id)
    if req then s:Text(req, { color = INK.TEXT, size = Style.SIZE.small, gap = 12 }) end
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
