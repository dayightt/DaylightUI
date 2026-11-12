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
