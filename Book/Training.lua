-- Training page: spells your trainer, quests, weapon masters or grimoires
-- will teach you, read from the What's Training addon's public API (WT_API).
-- The tab only appears while that addon is loaded, since its own tab lives on
-- the game's spellbook frame, which this window replaces.
--
-- Laid out like the NPC trainer page (Npc/Train.lua): learnable now first,
-- then upcoming spells by level, then known spells folded away. It's a
-- planning list only and never learns anything. The footer totals the cost
-- of everything learnable now.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Training = {}
ns.Training = Training

Training.EDGE = 12
Training.TOP = 44       -- chips and search row
Training.FOOT = 40      -- total row
Training.EVENTS = { "Ready", "SpellsChanged", "LevelChanged", "IgnoredChanged" }

-- Maps WT_API.Status values to display groups. "later" is grouped again by
-- level. Unlearned weapon skills fold into one row, as What's Training also
-- keeps them separate from the class trainer list.
Training.GROUP = {
    available = "now",
    missingReqs = "needs",
    nextLevel = "next",
    pet = "pet",
    notLevel = "later",
    weaponAvailable = "weapons", weaponNextLevel = "weapons", weaponNotLevel = "weapons",
    missingTalent = "talent",
    known = "known", knownPet = "known", weaponKnown = "known",
    ignored = "ignored", ignoredPet = "ignored", weaponIgnored = "ignored",
}
Training.ORDER = { "now", "needs", "next", "pet", "later", "talent", "weapons", "known", "ignored" }
Training.FOLDED = { weapons = true, known = true, ignored = true }   -- each collapses to one row

local S = { open = {}, filter = nil }
Training.state = S

local function api()
    local a = _G.WT_API
    if type(a) == "table" and type(a.GetSpells) == "function" then return a end
end

-- What's Training is loaded and new enough to have its API.
function Training.On() return api() ~= nil end

local function money() return type(GetMoney) == "function" and GetMoney() or 0 end
-- Uncolored, so the caller can paint it gold, or red when you can't afford it.
local function costText(c) return (type(c) == "number" and c > 0) and DUI.Widgets.Money(c, { color = false }) or "" end

-- ---------------------------------------------------------------------
-- Reading What's Training
-- ---------------------------------------------------------------------

-- Returns nil while What's Training is still loading. Calls are pcall'd so
-- an error in the other addon can't break this window.
function Training.Read()
    local a = api()
    if not a then return nil end
    if type(a.IsReady) == "function" then
        local ok, ready = pcall(a.IsReady)
        if not (ok and ready) then return nil end
    end
    local ok, list = pcall(a.GetSpells)
    if not ok or type(list) ~= "table" then return nil end
    local out = {}
    for _, sp in ipairs(list) do
        if type(sp) == "table" and type(sp.name) == "string" and Training.GROUP[sp.status] then out[#out + 1] = sp end
    end
    return out
end

local function byLevel(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
    if a.name ~= b.name then return a.name < b.name end
    return (a.subText or "") < (b.subText or "")
end

-- Returns { now = {...}, later = { [level] = {...} }, ... }.
function Training.Groups(list)
    local g = {}
    for _, key in ipairs(Training.ORDER) do g[key] = {} end
    for _, sp in ipairs(list) do
        local key = Training.GROUP[sp.status]
        if key == "later" then
            local lv = sp.level or 0
            g.later[lv] = g.later[lv] or {}
            table.insert(g.later[lv], sp)
        else
            table.insert(g[key], sp)
        end
    end
    for key, t in pairs(g) do
        if key == "later" then for _, l in pairs(t) do table.sort(l, byLevel) end else table.sort(t, byLevel) end
    end
    return g
end

-- Total cost of the "Learn now" group.
function Training.Total(groups)
    local total = 0
    for _, sp in ipairs(groups.now) do total = total + (type(sp.cost) == "number" and sp.cost or 0) end
    return total
end

-- ---------------------------------------------------------------------
-- Lines
-- ---------------------------------------------------------------------

-- Source label for spells not taught by the class trainer.
local function fromWord(sp)
    if sp.quest then return L["From a quest"] end
    if sp.isItem then return L["From a grimoire"] end
    if string.find(sp.status or "", "^weapon") then return L["From a weapon master"] end
end

local function subOf(sp)
    local rank, from = sp.subText ~= "" and sp.subText or nil, fromWord(sp)
    if rank and from then return rank .. " · " .. from end
    return rank or from
end

-- Where each weapon master stands, by NPC id: the city's map (its name comes from the
-- game, in the player's language) and the district inside it. A district with an
-- area id is named by the game too. Woo Ping's district is a best guess from his
-- spot on the old Stormwind map; Ansekhwa's spot on Thunder Bluff's main mesa has no
-- district name, so only the city shows.
Training.MASTERS = {
    [11865] = { map = 1455, city = L["Ironforge"], district = L["The Military Ward"] },        -- Buliwyf Stonehand
    [13084] = { map = 1455, city = L["Ironforge"], district = L["The Military Ward"] },        -- Bixi Wobblebonk
    [11867] = { map = 1453, city = L["Stormwind City"], district = L["Trade District"] },      -- Woo Ping
    [11866] = { map = 1457, city = L["Darnassus"], district = L["Warrior's Terrace"], area = 1660 },   -- Ilyenia Moonfire
    [2704] = { map = 1454, city = L["Orgrimmar"], district = L["Valley of Honor"] },          -- Hanashi
    [11868] = { map = 1454, city = L["Orgrimmar"], district = L["Valley of Honor"] },         -- Sayoc
    [11869] = { map = 1456, city = L["Thunder Bluff"] },                                    -- Ansekhwa
    [11870] = { map = 1458, city = L["Undercity"], district = L["The War Quarter"] },          -- Archibald
}

local function mapName(id)
    if not (type(id) == "number" and C_Map and type(C_Map.GetMapInfo) == "function") then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    local name = ok and type(info) == "table" and info.name
    return type(name) == "string" and name ~= "" and name or nil
end

local function areaName(id)
    if not (type(id) == "number" and C_Map and type(C_Map.GetAreaInfo) == "function") then return nil end
    local ok, name = pcall(C_Map.GetAreaInfo, id)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

-- "Ilyenia Moonfire, Darnassus, Warrior's Terrace": the name, then the city and the
-- district when known. A master missing from the list keeps the city its record names.
function Training.MasterText(t)
    if ns.Setting("masterSpot") ~= true then return t.name end
    local spot = type(t.npc) == "number" and Training.MASTERS[t.npc] or nil
    local city = mapName(t.uiMapId) or (spot and (mapName(spot.map) or spot.city))
    local district = spot and spot.district and (areaName(spot.area) or spot.district)
    if city and district then return string.format(L["%s, %s, %s"], t.name, city, district) end
    if city then return string.format(L["%s, %s"], t.name, city) end
    return t.name
end

local function tooltip(sp)
    return function(b)
        local tip = GameTooltip
        if not tip then return end
        tip:SetOwner(b, "ANCHOR_RIGHT")
        if sp.isItem and type(sp.itemId) == "number" and type(tip.SetItemByID) == "function" then
            tip:SetItemByID(sp.itemId)
        elseif type(sp.id) == "number" and type(tip.SetSpellByID) == "function" then
            tip:SetSpellByID(sp.id)
        else
            tip:SetText(sp.name)
        end
        local Tips = DUI.Tips   -- extra lines go under the spell's own, as in the spellbook
        Tips.Clear()
        Tips.Gap()
        if type(sp.level) == "number" and sp.level > 0 then Tips.Line(LEVEL or L["Level"], tostring(sp.level)) end
        if type(sp.cost) == "number" and sp.cost > 0 then
            Tips.Line(L["Cost"], costText(sp.cost), sp.cost > money() and Style.INK.BAD or Style.INK.MONEY)
        end
        -- For weapon skills, list up to two weapon masters of your faction, with where
        -- they stand.
        local a = api()
        if string.find(sp.status or "", "^weapon") and a and type(a.GetSource) == "function" then
            local ok, src = pcall(a.GetSource, sp.id)
            if ok and type(src) == "table" and type(src.trainers) == "table" then
                for i, t in ipairs(src.trainers) do
                    if i > 2 then break end
                    if type(t.name) == "string" then Tips.Line(L["Weapon master"], Training.MasterText(t)) end
                end
            end
        end
        Tips.Flush(tip)
        tip:Show()
    end
end

local function lineFor(sp, cash)
    local key = Training.GROUP[sp.status]
    local spec = { icon = sp.icon, text = sp.name, sub = subOf(sp), value = costText(sp.cost), tooltip = tooltip(sp),
        id = "wt:" .. tostring(sp.id) }
    if key == "now" or sp.status == "weaponAvailable" then
        spec.valueColor = (type(sp.cost) == "number" and sp.cost > cash) and Style.INK.BAD or Style.INK.MONEY
        return spec
    end
    spec.dim = true
    if key == "known" or key == "ignored" then spec.value = "" end
    return spec
end

local function matches(sp)
    local want = S.filter
    if not want then return true end
    if string.find(string.lower(sp.name), want, 1, true) then return true end
    return type(sp.subText) == "string" and string.find(string.lower(sp.subText), want, 1, true) ~= nil
end

local function only(list)
    local out = {}
    for _, sp in ipairs(list) do if matches(sp) then out[#out + 1] = sp end end
    return out
end

-- ---------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------

Training.TITLE = {
    needs = function() return L["Needs another spell first"] end,
    next = function() return L["Next level"] end,
    pet = function() return L["Pet abilities"] end,
    talent = function() return L["Needs a talent"] end,
}
-- One chip per listed group; clicking scrolls to it.
Training.CHIP = {
    now = function() return L["Learn now"] end,
    needs = function() return L["Needs a spell"] end,
    next = function() return L["Next level"] end,
    pet = function() return L["Pet"] end,
    later = function() return L["Later"] end,
    talent = function() return L["Talent"] end,
    weapons = function() return L["Weapons"] end,
    known = function() return L["Known"] end,
}

local function makeChip(parent)
    local b = DUI.Widgets.Chip(parent)
    b:SetScript("OnClick", function(self) Training.Jump(self.group) end)
    return b
end

local layoutChips

function Training.Build(page)
    Training.page = page
    local W = DUI.Widgets
    local box = W.Input(page, { height = 24, search = true, hint = SEARCH or L["Search"],
        onChange = function(t) Training.Search(t) end })
    box:SetWidth(150)
    box:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Training.EDGE, -10)
    page.search = box
    page.chips = {}
    page.stack = Win.Parts.Stack(page, { top = Training.TOP, bottom = Training.FOOT })
    -- Footer with the "Learn now" total.
    local foot = CreateFrame("Frame", nil, page)
    foot:SetHeight(22)
    foot:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", Training.EDGE + 4, 10)
    foot:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Training.EDGE, 10)
    page.foot = foot
    page.totalLabel = Style.Text(foot, Style.SIZE.small, "LEFT")
    page.totalLabel:SetPoint("LEFT", foot, "LEFT", 0, 0)
    page.totalLabel:SetText(L["Learn now costs"])
    Style.InkText(page.totalLabel, "LABEL")
    page.total = Style.Text(foot, Style.SIZE.body, "LEFT")
    page.total:SetPoint("LEFT", page.totalLabel, "RIGHT", 8, 0)
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")   -- empty-list text
    page.note:Hide()
    local a = api()
    if a and type(a.RegisterCallback) == "function" then
        for _, e in ipairs(Training.EVENTS) do
            pcall(a.RegisterCallback, Training, e, function() Training.Soon() end)
        end
    end
    DUI.RegisterEvent("PLAYER_MONEY", function() Training.Soon() end)
    -- The search box follows the page's edge while the window is resized, so
    -- the chips are fitted again then, not only on the next refresh.
    page:HookScript("OnSizeChanged", function() layoutChips(page) end)
end

-- Changes arrive in bursts (a level up), so refresh once on the next frame,
-- and only while visible.
function Training.Soon()
    local page = Training.page
    if not (page and page:IsVisible()) or Training.pending then return end
    Training.pending = true
    C_Timer.After(0, function()
        Training.pending = nil
        if page:IsVisible() then Training.Refresh() end
    end)
end

local function foldText(key, open, n)
    local text
    if key == "weapons" then text = open and L["- %d weapon skills"] or L["+ %d weapon skills"]
    elseif key == "known" then text = open and L["- %d already known"] or L["+ %d already known"]
    else text = open and L["- %d ignored"] or L["+ %d ignored"] end
    return string.format(text, n)
end

-- One section per group, "later" split by level, weapons/known/ignored foldable.
function Training.Render(page)
    local s = page.stack
    local list = Training.list
    local cash = money()
    s:Begin()
    Training.at = {}
    if not list then
        page.note:SetText(L["What's Training is still reading your spells."])
        page.note:Show()
        page.pieces = s:End()
        return
    end
    local g = Training.Groups(list)
    local any = false
    for _, key in ipairs(Training.ORDER) do
        if key == "later" then
            local levels = {}
            for lv in pairs(g.later) do levels[#levels + 1] = lv end
            table.sort(levels)
            for _, lv in ipairs(levels) do
                local shown = only(g.later[lv])
                if #shown > 0 then
                    any = true
                    Training.at.later = Training.at.later or s.y
                    s:Section(string.format(L["Level %d"], lv))
                    for _, sp in ipairs(shown) do s:Line(lineFor(sp, cash)) end
                end
            end
        elseif Training.FOLDED[key] then
            local shown = only(g[key])
            if #shown > 0 then
                any = true
                -- Searching shows matches even in folded groups.
                local open = S.open[key] or S.filter ~= nil
                Training.at[key] = s.y
                s:Gap(6)
                s:Row({ text = foldText(key, open, #shown), color = Style.INK.LABEL, id = "wt:fold:" .. key,
                    onEnter = function(b) Style.InkText(b.text, "VALUE") end,
                    onLeave = function(b) Style.InkText(b.text, "LABEL") end,
                    onClick = function() Training.Fold(key, not S.open[key]) end })
                if open then for _, sp in ipairs(shown) do s:Line(lineFor(sp, cash)) end end
            end
        else
            local shown = only(g[key])
            if key == "now" and not S.filter then
                any = true
                Training.at.now = s.y
                s:Section(string.format(L["Learn now · %d"], #shown))
                if #shown == 0 then s:Text(L["Nothing new to learn right now."], { color = Style.INK.LABEL }) end
            elseif #shown > 0 then
                any = true
                Training.at[key] = s.y
                s:Section(key == "now" and string.format(L["Learn now · %d"], #shown) or Training.TITLE[key]())
            end
            for _, sp in ipairs(shown) do s:Line(lineFor(sp, cash)) end
        end
    end
    page.pieces = s:End()
    page.note:SetShown(not any)
    page.note:SetText(L["No spells match."])
    -- Gold, or red when you can't afford it.
    local total = Training.Total(g)
    page.total:SetText(total > 0 and costText(total) or L["Nothing"])
    if total > 0 then
        Style.InkText(page.total, total > cash and "BAD" or "MONEY")
    else
        Style.InkText(page.total, "LABEL")
    end
end

-- Groups whose chips didn't fit go into the More menu, as on the spells page,
-- so a long language or a narrow window never leaves a group out of reach.
function Training.MoreMenu(owner)
    local keys, values, current = {}, {}, nil
    for i, key in ipairs(Training.folded or {}) do
        keys[i] = i
        values[i] = Training.CHIP[key]()
        if key == Training.jumped then current = i end
    end
    DUI.Widgets.OpenMenu(owner, keys, values, current, function(i)
        local key = Training.folded and Training.folded[i]
        if key then Training.Jump(key) end
    end)
end

local function makeMore(page)
    local b = DUI.Widgets.MenuButton(page, L["More"], DUI.Widgets.CHIP_HEIGHT)
    b:SetScript("OnClick", function(self) Training.MoreMenu(self) end)
    b:Hide()
    return b
end

function layoutChips(page)
    local w = page:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = ns.Window.SIZE.training[1] end
    local room = w - 2 * Training.EDGE - 160
    local gap = DUI.Widgets.CHIP_GAP
    local keys = {}
    for _, key in ipairs(Training.ORDER) do
        if Training.CHIP[key] and Training.at and Training.at[key] then keys[#keys + 1] = key end
    end
    for i, key in ipairs(keys) do
        local c = page.chips[i]
        if not c then c = makeChip(page); page.chips[i] = c end
        c.group = key
        c.text:SetText(Training.CHIP[key]())
        c.FitWidth()
    end
    for i = #keys + 1, #page.chips do page.chips[i]:Hide() end
    -- Do they all fit? Otherwise keep room at the end for More.
    local total = 0
    for i = 1, #keys do total = total + page.chips[i]:GetWidth() + (i > 1 and gap or 0) end
    page.more = page.more or makeMore(page)
    local more = page.more
    local spare = room
    if total > room then
        more.SetLabel(L["More"], 0)
        spare = room - more:GetWidth() - gap
    end
    local M = DUI.Motion
    local x, folded = Training.EDGE, {}
    for i, key in ipairs(keys) do
        local c = page.chips[i]
        local cw = c:GetWidth()
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", page, "TOPLEFT", x, -11)
        local fits = #folded == 0 and x + cw - Training.EDGE <= spare
        -- A chip coming back out of More eases in.
        if fits and not c:IsShown() then c:Show(); M.Fade(c, 0, 1, M.FAST) end
        if not fits then c:Hide() end
        if fits then x = x + cw + gap else folded[#folded + 1] = key end
    end
    Training.folded = folded
    -- More glides from where it is now to its new spot, or eases in there.
    local function place(v)
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", page, "TOPLEFT", v, -11)
    end
    more.glide = more.glide or {}   -- its own tween key; the button's hover uses the button
    if #folded == 0 then
        M.Tween(more.glide, x, x, 0, place)   -- stops a glide still running
        more:Hide()
    elseif not more:IsShown() then
        M.Tween(more.glide, x, x, 0, place)
        more:Show()
        M.Fade(more, 0, 1, M.FAST)
    else
        M.Tween(more.glide, select(4, more:GetPoint(1)) or x, x, M.NORMAL, place)
    end
end

-- Scroll a group to the top, unfolding it if needed.
function Training.Jump(key)
    Training.jumped = key
    if Training.FOLDED[key] and not S.open[key] then Training.Fold(key, true) end
    local y = Training.at and Training.at[key]
    if y and Training.page then Training.page.stack:ScrollTo(y) end
end

-- Lines below a toggled fold glide into place through Refresh.
function Training.Fold(key, open)
    S.open[key] = open or nil
    if DUI.Sound then DUI.Sound.Play("toggle") end
    Training.Refresh()
end

function Training.Fill(page)
    page = page or Training.page
    if not page then return end
    Training.list = Training.Read()
    S.filter = nil
    local t = page.search:GetText() or ""
    if t ~= "" then S.filter = string.lower(t) end
    Training.Render(page)
    layoutChips(page)
end

-- Refill while open, keeping the scroll position and easing lines to their
-- new spots.
function Training.Refresh()
    local page = Training.page
    if not (page and page:IsShown()) then return end
    local s = page.stack
    local at = s:Scrolled()
    local spots = s:Spots()
    Training.Fill(page)
    s:Ease(spots)
    s:ScrollTo(at)
end

function Training.Search(text)
    local page = Training.page
    if not page then return end
    S.filter = (type(text) == "string" and text ~= "") and string.lower(text) or nil
    Training.Render(page)
    layoutChips(page)
end

-- Pieces in the order they animate in when the page opens.
function Training.Pieces(page)
    local out = {}
    for _, c in ipairs(page.chips) do if c:IsShown() then out[#out + 1] = c end end
    out[#out + 1] = page.search
    for i, p in ipairs(page.pieces or {}) do
        if i > 14 then break end
        out[#out + 1] = p
    end
    out[#out + 1] = page.foot
    return out
end

-- A controller: as on the spellbook page, LB and RB step the chips.
function Training.PadTabs()
    local out, at = {}, nil
    local page = Training.page
    if not page then return out end
    for _, c in ipairs(page.chips) do
        if c:IsShown() and c.group then
            out[#out + 1] = c
            if c.group == Training.jumped then at = #out end
        end
    end
    return out, at
end
