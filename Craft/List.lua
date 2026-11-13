-- Recipe list, the left side of the window. Search and chips on top (Skill-ups, Have
-- materials, and Slot for gear professions, which drives the game's own slot filter;
-- Rarity colors sits beside the search). Below, learned recipes under category headings
-- that collapse on click (saved per character). Each row shows the icon, the name in its
-- difficulty color (or item quality with Rarity colors on), the materials underneath,
-- and how many can be made on the right. Clicking a row shows it in Recipe.lua.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local List = {}
ns.List = List

List.W = 300          -- list width; the rest is the recipe side
List.EDGE = 12
List.TOP = 76         -- height of search and chips
List.SEARCH_Y = 10    -- search row (Rarity colors beside it)
List.CHIPS_Y = 46     -- chip row (a second row below when Slot doesn't fit)
List.EVENTS = { "TRADE_SKILL_LIST_UPDATE", "BAG_UPDATE_DELAYED", "NEW_RECIPE_LEARNED", "GET_ITEM_INFO_RECEIVED",
    "TRADE_SKILL_FAVORITES_CHANGED", "TRACKED_RECIPE_UPDATE" }
List.ITEM_WAIT = 0.2  -- s to let item info settle before re-reading the list

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Collapsed categories (per character, by profession and category name)

function List.Folds()
    local char = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if not char then return {} end
    if type(char.craftFolds) ~= "table" then char.craftFolds = {} end
    return char.craftFolds
end

local function foldKey(section)
    local prof = List.data and List.data.prof
    return (prof and prof.name or "") .. ":" .. (section.name or "")
end

function List.IsFolded(section) return List.Folds()[foldKey(section)] == true end

function List.Fold(section, folded)
    List.Folds()[foldKey(section)] = folded or nil
    if DUI.Sound then DUI.Sound.Play("toggle") end
    List.Render(List.pane, true)
end

-- Category heading: upper case in the accent with a faint line (like Stack:Section).
-- Click to collapse; shows "+" while collapsed.
local function makeHead(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp")
    b.text = Style.Text(b, Win.Parts.HEAD, "LEFT")
    b.text:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 4)
    b.state = Style.Text(b, Style.SIZE.body, "RIGHT")
    b.state:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 3)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetTexture(WHITE)
    b.line:SetVertexColor(1, 1, 1, 0.06)
    b.line:SetHeight(1)
    b.line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.isSection = true
    local function lit(on)
        Style.InkText(b.text, "pop", on and 1 or 0.85)
        Style.InkText(b.state, "pop", on and 1 or 0.85)
    end
    b.Lit = lit
    b:SetScript("OnEnter", function() lit(true) end)
    b:SetScript("OnLeave", function() lit(false) end)
    b:SetScript("OnClick", function(self)
        if self.section and not List.filter then List.Fold(self.section, not List.IsFolded(self.section)) end
    end)
    return b
end

local function head(s, section, folded)
    local b = s:Piece("head", makeHead, 22, 12, "section:" .. tostring(section.name))
    b.section = section
    b.text:SetText(string.upper(section.name or ""))
    b.state:SetText(folded and "+" or "")
    b.Lit(b:IsMouseOver() == true)
    return b
end

-- Filtering

List.chipOn = { skill = false, mats = false }   -- session only, like the game's filters

local function keep(recipe)
    if List.chipOn.skill and not ns.Data.SkillsUp(recipe) then return false end
    if List.chipOn.mats and recipe.count <= 0 then return false end
    if List.slot and not (List.inSlot and List.inSlot[recipe.id]) then return false end
    local want = List.filter
    if want and not string.find(string.lower(recipe.name), want, 1, true) then return false end
    return true
end

-- The list

local function tooltip(b)
    local r = b.lineSpec and b.lineSpec.recipe
    if not (r and GameTooltip) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if type(GameTooltip.SetRecipeResultItem) == "function" then
        GameTooltip:SetRecipeResultItem(r.id)
    elseif r.link and type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetHyperlink(r.link)
    end
    GameTooltip:Show()
end

List.Tip = tooltip   -- also used by the small view window (View.lua)

-- Right-click: favorite and track, the game's own words.
function List.Menu(b)
    local r = b.lineSpec and b.lineSpec.recipe
    if not r then return end
    local D, T = ns.Data, ns.Track
    local keys, values = {}, {}
    if D.CanFavorite() then
        keys[#keys + 1] = "favorite"
        values.favorite = r.favorite and (BATTLE_PET_UNFAVORITE or L["Remove Favorite"]) or (BATTLE_PET_FAVORITE or L["Set Favorite"])
    end
    if D.CanTrack(r) then
        keys[#keys + 1] = "track"
        values.track = T.Is(r.id) and (PROFESSIONS_UNTRACK_RECIPE or L["Untrack"]) or (PROFESSIONS_TRACK_RECIPE or L["Track Recipe"])
    end
    if #keys == 0 then return end
    DUI.Widgets.OpenMenu(b, keys, values, nil, function(k)
        if k == "favorite" then List.Favorite(r, not r.favorite) else T.Set(r.id, not T.Is(r.id)) end
    end, nil, { atCursor = true })
end

-- The game says when a favorite changed (TRADE_SKILL_FAVORITES_CHANGED); the list is
-- read again then, and the row glides to its new place.
function List.Favorite(r, on)
    ns.Data.SetFavorite(r.id, on)
    List.Soon()
end

local function onClick(b)
    local r = b.lineSpec and b.lineSpec.recipe
    if not r then return end
    -- Shift-click links the recipe in chat, like the game's list.
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
        local link = ns.Data.RecipeLink(r)
        local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
        if link and type(insert) == "function" then insert(link) end
        return
    end
    List.Pick(r.id)
end

-- The skill-up chance under the count on a row's right: a small number in the
-- accent, the count moving up to the name's line to make room. Gray recipes show
-- none, and neither does one whose range isn't known.
List.chances = {}

local function chanceText(b)
    if not b.chance then
        b.chance = Style.Text(b, Style.SIZE.tiny, "RIGHT")
        b.chance:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 6)
    end
    return b.chance
end

function List.PaintChance(b, recipe)
    local fs = chanceText(b)
    local data = List.data
    local chance = ns.Setting("skillUps") == true and recipe.difficulty ~= ns.Data.TRIVIAL and ns.Data.Chance(recipe, ns.Data.Skill(data and data.prof)) or nil
    local text = ns.Data.ChanceText(chance)
    b.value:ClearAllPoints()
    fs:SetText(text or "")
    fs:SetShown(text ~= nil)
    -- The sub keeps the block's two bottom points; it stops short of the chance
    -- by how much wider the chance is than the count (the block ends at the count).
    local inset = 0
    if text then
        -- The count sits on the name's line: its top is the name's top, which is
        -- where the centered block starts.
        local top = (Win.Parts.LINE - b.block:GetHeight()) / 2
        b.value:SetPoint("TOPRIGHT", b, "TOPRIGHT", -8, -top)
        inset = math.max(0, fs:GetStringWidth() - b.value:GetStringWidth())
    else
        b.value:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    end
    b.sub:ClearAllPoints()
    b.sub:SetPoint("BOTTOMLEFT", b.block, "BOTTOMLEFT", 0, 0)
    b.sub:SetPoint("BOTTOMRIGHT", b.block, "BOTTOMRIGHT", -inset, 0)
    Style.InkText(fs, "pop")
    local was = List.chances[recipe.id]
    List.chances[recipe.id] = text
    if text and was and was ~= text and DUI.Motion then DUI.Motion.Fade(fs, 0, 1, DUI.Motion.FAST) end
end

-- Each recipe's last drawn color. When it changes (a skill-up turned it from orange to
-- yellow) it eases to the new one at SLOW speed.
List.colors = {}

function List.Line(s, recipe, picked)
    local accent = { Style.Accent() }
    local c = ns.Data.NameColor(recipe, ns.Setting("rarityNames") == true)
    local b = s:Line({ recipe = recipe, icon = recipe.icon, text = recipe.name, color = c,
        sub = recipe.sub, value = recipe.count > 0 and tostring(recipe.count) or "", valueColor = accent,
        picked = picked, onClick = onClick, onRightClick = List.Menu, tooltip = tooltip, id = "recipe:" .. tostring(recipe.id) })
    List.PaintChance(b, recipe)
    local was = List.colors[recipe.id]
    List.colors[recipe.id] = c
    if was and (was[1] ~= c[1] or was[2] ~= c[2] or was[3] ~= c[3]) and DUI.Motion then
        DUI.Motion.Tween(b.name, 0, 1, DUI.Motion.SLOW, function(t)
            b.name:SetTextColor(was[1] + (c[1] - was[1]) * t, was[2] + (c[2] - was[2]) * t, was[3] + (c[3] - was[3]) * t)
        end)
    end
    return b
end

-- keep: a refill (bags, skill-up, collapse) keeps the scroll position.
function List.Render(pane, keepScroll)
    pane = pane or List.pane
    local data = List.data
    if not (pane and data) then return end
    pane.rarity.SetOn(ns.Setting("rarityNames") == true)   -- the options page switch updates this too
    local s = pane.stack
    local at = keepScroll and s:Scrolled() or 0
    -- Same profession refilled while open (search, chip, collapse, skill-up): rows that
    -- stay glide to their new spot, new ones fade in.
    local spots = pane:IsVisible() and pane.shownProf == data.prof and s:Spots() or nil
    pane.shownProf = data.prof
    s:Begin()
    List.lines = {}
    List.order = {}
    local any = false
    local picked = ns.Window and ns.Window.Picked()
    for _, section in ipairs(data.sections) do
        local shown = {}
        for _, r in ipairs(section.recipes) do if keep(r) then shown[#shown + 1] = r end end
        if #shown > 0 then
            any = true
            local folded = not List.filter and List.IsFolded(section)
            head(s, section, folded)
            if not folded then
                for _, r in ipairs(shown) do
                    local b = List.Line(s, r, r.id == picked)
                    List.lines[r.id] = b
                    List.order[#List.order + 1] = r.id
                end
            end
        end
    end
    pane.pieces = s:End()
    pane.note:SetShown(not any)
    local filtered = List.filter or List.chipOn.skill or List.chipOn.mats or List.slot
    if not data.prof then
        local tabs, known = #ns.Data.Tabs(), #ns.Data.Primaries()
        pane.note:SetText(tabs > 0 and L["Pick a profession above."]
            or known > 0 and L["No recipes yet."] or L["No professions yet."])
    else
        pane.note:SetText(filtered and L["No recipes match."] or L["No recipes yet."])
    end
    s:ScrollTo(at)
    s:Ease(spots)
    local win = ns.Window and ns.Window.frame
    if win and Win.IsOpen(win) then List.ReportRows() end
end

-- Visible rows are passed to plugins (DaylightUI.API kind "craftrow", recipe id as the
-- unit) after each fill while open, and on open (Craft.Open, since the first fill
-- happens before).
function List.ReportRows()
    local R = DUI.APIReport
    if not R then return end
    for _, id in ipairs(List.order or {}) do
        local b = List.lines[id]
        if b then
            local info = b.apiInfo or {}
            b.apiInfo = info
            info.recipeID = id
            R.Row("craftrow", b, id, info, false)
        end
    end
    R.ListDone("craftrow")
end

-- Highlight the selected row only, without a refill.
function List.PaintPick(id)
    for rid, b in pairs(List.lines or {}) do
        if b:IsShown() then Win.Parts.PickLine(b, rid == id) end
    end
end

function List.Pick(id)
    if ns.Window then ns.Window.Pick(id) end
end

-- First visible recipe (a profession opened with nothing selected).
function List.First()
    for _, section in ipairs(List.data and List.data.sections or {}) do
        for _, r in ipairs(section.recipes) do if keep(r) then return r.id end end
    end
    return nil
end

function List.Search(text)
    List.filter = (type(text) == "string" and text ~= "") and string.lower(text) or nil
    List.Render(List.pane)
end

local function chip(pane, key, text, x)
    local b = DUI.Widgets.Chip(pane, text)
    b.FitWidth()
    b:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -List.CHIPS_Y)
    b:SetScript("OnClick", function(self)
        List.chipOn[key] = not List.chipOn[key]
        self.SetOn(List.chipOn[key])
        List.Render(List.pane)
    end)
    b.SetOn(List.chipOn[key])
    return b
end

-- Rarity colors isn't a filter, so it sits apart from the chips, next to the search.
-- A click repaints right away (setting changes wait out combat); names ease to the new
-- colors (List.colors) and the scroll stays.
local function rarityChip(pane)
    local W = DUI.Widgets
    local b = W.Chip(pane, L["Rarity colors"])
    b.FitWidth()
    b:SetPoint("RIGHT", pane, "TOPRIGHT", -List.EDGE, -(List.SEARCH_Y + W.INPUT_H / 2))
    b:SetScript("OnClick", function()
        DUI:Set("Professions", "rarityNames", ns.Setting("rarityNames") ~= true)
        List.Render(pane, true)
    end)
    b:HookScript("OnEnter", function(self)
        W.Tooltip(self, L["Rarity colors"], L["Recipe names take the rarity color of what they make. Off, they show how likely a skill-up is."])
    end)
    b:HookScript("OnLeave", W.HideTooltip)
    return b
end

-- The list side of the page (pane: a frame on the page's left, List.W wide).
function List.Build(pane)
    List.pane = pane
    local box = DUI.Widgets.Input(pane, { search = true, hint = SEARCH or L["Search"],
        onChange = function(t) List.Search(t) end })
    pane.rarity = rarityChip(pane)
    box:SetPoint("TOPLEFT", pane, "TOPLEFT", List.EDGE, -List.SEARCH_Y)
    box:SetPoint("RIGHT", pane.rarity, "LEFT", -DUI.Widgets.CHIP_GAP, 0)
    pane.search = box
    pane.skill = chip(pane, "skill", L["Skill-ups"], List.EDGE)
    pane.mats = chip(pane, "mats", L["Have materials"], List.EDGE + pane.skill:GetWidth() + DUI.Widgets.CHIP_GAP)
    pane.slot = DUI.Widgets.Chip(pane, L["Slot"])
    pane.slot:SetScript("OnClick", function(self) List.SlotMenu(self) end)
    pane.slot:Hide()
    pane.stack = Win.Parts.Stack(pane, { top = List.TOP, bottom = ns.Spells.FOOT })
    ns.Spells.Build(pane)   -- profession spells under the list, to drag to a bar
    pane.note = Style.Text(pane, Style.SIZE.body, "CENTER")
    pane.note:SetPoint("CENTER", pane, "CENTER", 0, 0)
    Style.InkText(pane.note, "LABEL")   -- empty-list text
    pane.note:Hide()
    for _, e in ipairs(List.EVENTS) do
        -- Item info arrives (GET_ITEM_INFO_RECEIVED fires for any item, often many in a row):
        -- read once things settle.
        DUI.RegisterEvent(e, function(event) List.Soon(event == "GET_ITEM_INFO_RECEIVED" and List.ITEM_WAIT or 0) end)
    end
end

-- Slot chip: a menu for one slot or all

-- Next to the other chips, or on its own row when it doesn't fit (the list starts
-- lower then).
function List.LayoutChips(pane)
    local b = pane.slot
    local top = List.TOP
    if b:IsShown() then
        b.FitWidth()
        local x = List.EDGE + pane.skill:GetWidth() + pane.mats:GetWidth() + 2 * DUI.Widgets.CHIP_GAP
        local w = pane:GetWidth()
        if type(w) ~= "number" or w <= 0 then w = List.W end
        b:ClearAllPoints()
        if x + b:GetWidth() <= w - List.EDGE then
            b:SetPoint("TOPLEFT", pane, "TOPLEFT", x, -List.CHIPS_Y)
        else
            b:SetPoint("TOPLEFT", pane, "TOPLEFT", List.EDGE, -(List.CHIPS_Y + DUI.Widgets.CHIP_HEIGHT + DUI.Widgets.CHIP_GAP))
            top = top + DUI.Widgets.CHIP_HEIGHT + DUI.Widgets.CHIP_GAP
        end
    end
    local sf = pane.stack.scroll
    sf:SetPoint("TOPLEFT", pane, "TOPLEFT", Win.Parts.EDGE, -top)
end

local function paintSlot(pane)
    local name
    for _, s in ipairs(List.slots or {}) do if s.index == List.slot then name = s.name end end
    pane.slot.text:SetText(name or L["Slot"])
    pane.slot.SetOn(List.slot ~= nil)
    pane.slot:SetShown(#(List.slots or {}) > 0)
    List.LayoutChips(pane)
end

-- Pick one slot (nil = all): set the game's filter, then use the list it leaves.
function List.PickSlot(index)
    List.slot = index
    ns.Data.SetSlot(index)
    List.inSlot = index and ns.Data.Filtered() or nil
    paintSlot(List.pane)
    List.Render(List.pane)
end

function List.SlotMenu(owner)
    local keys, values = { 0 }, { [0] = L["All slots"] }
    for _, s in ipairs(List.slots or {}) do
        keys[#keys + 1] = s.index
        values[s.index] = s.name
    end
    DUI.Widgets.OpenMenu(owner, keys, values, List.slot or 0, function(k) List.PickSlot(k ~= 0 and k or nil) end, 140)
end

-- Re-read (profession opened or switched) and scroll to the top. A different
-- profession starts on all slots with the game's filter cleared.
function List.Fill(pane)
    pane = pane or List.pane
    if not pane then return end
    local prof = ns.Data.Profession()
    if (prof and prof.id) ~= List.slotProf then
        List.slotProf = prof and prof.id
        if List.slot then ns.Data.SetSlot(nil) end
        List.slot, List.inSlot = nil, nil
        List.slots = ns.Data.Slots()
    end
    List.data = ns.Data.Read()
    if List.slot then List.inSlot = ns.Data.Filtered() end
    paintSlot(pane)
    List.Render(pane)
    ns.Spells.Fill()
end

-- List events come in bursts (a craft touches bags, the list and skill). Re-read the
-- next frame (or `wait` s later for item info), only while shown, keeping the scroll.
-- One read covers the burst: a sooner request replaces a later pending one.
function List.Soon(wait)
    local pane = List.pane
    if not (pane and pane:IsVisible()) then return end
    wait = wait or 0
    local at = GetTime() + wait
    if List.pending and List.pending <= at then return end
    List.pending = at
    C_Timer.After(wait, function()
        if List.pending ~= at then return end
        List.pending = nil
        if not pane:IsVisible() or ns.Data.Changing() then return end
        List.data = ns.Data.Read()
        if List.slot then List.inSlot = ns.Data.Filtered() end
        List.Render(pane, true)
        if ns.Window then ns.Window.Refreshed() end
    end)
end

-- Lift-in order: search, chips, visible rows.
-- The first rows (a profession switch lifts in only these; search and chips stay put).
function List.Rows(pane, out)
    out = out or {}
    for i, p in ipairs(pane.pieces or {}) do
        if i > 12 then break end
        out[#out + 1] = p
    end
    return out
end

function List.Pieces(pane)
    local out = { pane.search, pane.rarity, pane.skill, pane.mats }
    if pane.slot:IsShown() then out[#out + 1] = pane.slot end
    List.Rows(pane, out)
    for _, b in ipairs(ns.Spells.Pieces()) do out[#out + 1] = b end
    return out
end

-- What plugins get for a row (DaylightUI.API Paint, kind "craftrow"): icon and name.
-- A refill restores the Daylight UI look.
if DUI.APIReport then
    DUI.APIReport.Parts("craftrow", function(b) return { icon = b.icon, name = b.name } end)
    DUI.APIReport.Repainter("craftrow", function() if List.pane then List.Render(List.pane, true) end end, true)
end
