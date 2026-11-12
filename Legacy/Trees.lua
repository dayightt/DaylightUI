-- Legacy window, Legacy trees page. The three trees on the left (Professions, Adventure,
-- Progression) with points spent in each and points left to spend below. The selected
-- tree on the right uses the spellbook's talent tiles (Book/Talents.lua): rings, rank
-- clocks, arrows that light up, click adds a point (green until Apply), right-click
-- takes it back, Apply rolls the gold light down. Footer: Apply, Reset tree (with
-- W.Confirm) and Undo.
--
-- Each tree is a trait tree with its own config (C_Traits.GetConfigIDByTreeID), changed
-- only through the game's calls (Trees.Spend: PurchaseRank, RefundRank, SetSelection
-- for choice nodes, RollbackConfig, ResetTree, CommitConfig), as
-- LegacyTreeTraitPanelMixin does. Layout comes from the node positions (TalentData.Read
-- with step "auto").

local _, DUI = ...
DUI.Legacy = DUI.Legacy or {}
local ns = DUI.Legacy
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Trees = {}
ns.Trees = Trees

Trees.EDGE = 16
Trees.SIDE = 210
Trees.TOP = 44            -- search row above the tree
Trees.FOOT = 56
Trees.LEFT_H = 74         -- height of "To spend" under the tree list
Trees.COMMIT_WAIT = 5     -- s before an unanswered Apply counts as failed
Trees.SPAN = 20           -- max tree span in tiles (beyond it: a retired node)

Trees.pick = 1            -- the tree shown (this session)

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function W() return DUI.Widgets end
local function Data() return ns.Data end
local function Talents() return DUI.Book.Talents end
local function TD() return DUI.Book.TalentData end
local function hex(c) return Win.Parts.Hex(c) end
local function pop(n) return hex({ Style.Pop() }) .. tostring(n) .. "|r" end

local answers = function(ok, ...) if ok then return ... end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return answers(pcall(fn, ...))
end
local function traits() return type(C_Traits) == "table" and C_Traits or nil end

local function shown() return Data().Trees()[Trees.pick] end

-- Spending, only through the game's calls (LegacyTreeTraitPanelMixin, TalentFrameBaseMixin)

local Spend = {}
Trees.Spend = Spend

function Spend.Config() return Trees.data and Trees.data.configID end

-- Like the game's CanAfford: every cost covered by the points left.
function Spend.Afford(node, data)
    local C, configID = traits(), data and data.configID
    local costs = C and configID and call(C.GetNodeCost, configID, node.id)
    if type(costs) ~= "table" then return true end
    local have = data.currency or {}
    for _, cost in ipairs(costs) do
        if type(cost) == "table" and type(cost.amount) == "number" and (have[cost.ID] or 0) < cost.amount then return false end
    end
    return true
end

function Spend.CanBuy(node, data)
    return node ~= nil and not Trees.committing and node.canBuy and Spend.Afford(node, data or Trees.data) or false
end

function Spend.CanRefund(node)
    return node ~= nil and not Trees.committing and node.canRefund or false
end

-- A choice node's entries as menu labels (each entry's spell name).
local function choiceNames(configID, node)
    local C = traits()
    local keys, values = {}, {}
    for _, entryID in ipairs(node.choices) do
        local e = call(C.GetEntryInfo, configID, entryID)
        local def = type(e) == "table" and e.definitionID and call(C.GetDefinitionInfo, e.definitionID)
        local name = type(def) == "table" and (def.overrideName or (def.spellID and type(C_Spell) == "table" and call(C_Spell.GetSpellName, def.spellID)))
        keys[#keys + 1] = entryID
        values[entryID] = type(name) == "string" and name ~= "" and name or tostring(entryID)
    end
    return keys, values
end

-- true when the game accepted it; "asked" for a choice node (the menu is open and its
-- pick goes to SetSelection).
function Spend.Buy(node, data, owner)
    if not Spend.CanBuy(node, data) then return false end
    local C, configID = traits(), (data or Trees.data).configID
    if node.choices and not node.chosen then
        local keys, values = choiceNames(configID, node)
        W().OpenMenu(owner, keys, values, nil, function(entryID)
            if call(C.SetSelection, configID, node.id, entryID) == true then
                if DUI.Sound then DUI.Sound.Play("spend") end
                Trees.Soon()
            end
        end, nil, { atCursor = true })
        return "asked"
    end
    return call(C.PurchaseRank, configID, node.id) == true
end

function Spend.Refund(node)
    if not Spend.CanRefund(node) then return false end
    local C, configID = traits(), Spend.Config()
    if node.choices and node.rank <= 1 then return call(C.SetSelection, configID, node.id, nil) == true end
    local clear = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
    return call(C.RefundRank, configID, node.id, clear) == true
end

function Spend.HasChanges()
    if Trees.committing then return false end
    local C, configID = traits(), Spend.Config()
    return C and configID and call(C.ConfigHasStagedChanges, configID) == true or false
end

function Spend.Undo()
    if not Spend.HasChanges() then return false end
    return call(traits().RollbackConfig, Spend.Config()) == true
end

local function anyBought(data)
    for _, node in pairs(data and data.byID or {}) do if node.rank > 0 then return true end end
    return false
end

-- The game's rule for its Reset button (LegacyTreeTraitPanelMixin
-- UpdateConfigButtonsState): not on a tree flagged cannotRefund, whose points only come
-- back at the game's NPC, for gold.
function Spend.CanReset()
    local tree = shown()
    local configID = Spend.Config()
    if not (configID and tree and tree.treeID) then return false end
    local info = call(traits() and traits().GetTreeInfo, configID, tree.treeID)
    return not (type(info) == "table" and info.cannotRefund == true)
end

-- Like the game's ResetTree: refund every point, staged until Apply.
function Spend.Reset()
    local tree = shown()
    local configID = Spend.Config()
    if Trees.committing or not Spend.CanReset() then return false end
    call(traits().ResetTree, configID, tree.treeID)
    Trees.Soon()
    return true
end

-- Apply (CommitConfig): staged talents shine once the server confirms
-- (TRAIT_CONFIG_UPDATED for this config).
function Spend.Apply()
    if not Spend.HasChanges() then return false end
    local configID = Spend.Config()
    local sent = {}
    local buys, _, swaps = call(traits().GetStagedChanges, configID)
    for _, list in ipairs({ buys, swaps }) do
        for _, id in ipairs(type(list) == "table" and list or {}) do sent[#sent + 1] = id end
    end
    -- Set before the call, like the game's frame, since the answer can arrive inside it.
    Trees.committing, Trees.sent = configID, sent
    local token = {}
    Trees.token = token
    if call(traits().CommitConfig, configID) ~= true then
        if Trees.token == token then Trees.committing, Trees.sent, Trees.token = nil, nil, nil end
        return false
    end
    if Trees.token ~= token then return true end   -- already answered
    C_Timer.After(Trees.COMMIT_WAIT, function()
        if Trees.token == token then Trees.Finished(false) end
    end)
    Trees.Soon()
    return true
end

function Trees.Finished(ok)
    if not Trees.committing then return end
    local sent = Trees.sent
    Trees.committing, Trees.sent, Trees.token = nil, nil, nil
    if ok and DUI.Sound then DUI.Sound.Play("apply") end
    local page = Trees.page
    local T = Talents()
    T.wave = nil
    if ok and sent and #sent > 0 and page and page:IsVisible() then
        T.wave = {}
        for _, id in ipairs(sent) do T.wave[id] = true end
    end
    if page and page:IsVisible() then Trees.Render(true) end
    if T.wave then T.Wave(page, sent) end
end

-- Tree list

-- spentInTree, not spent: the currency is shared, so spent is all three trees combined
-- (the game's Blizzard_LegacyTree shows spentInTree too).
local function spentIn(tree)
    local configID = Data().ConfigOf(tree.treeID)
    local info = configID and call(traits() and traits().GetTreeCurrencyInfo, configID, tree.treeID, false)
    local c = type(info) == "table" and info[1]
    return type(c) == "table" and type(c.spentInTree) == "number" and c.spentInTree or 0
end

function Trees.RenderList()
    local page = Trees.page
    local s = page.list
    s:Begin()
    for i, tree in ipairs(Data().Trees()) do
        local spent = spentIn(tree)
        local b = s:Line({ text = tree.name, color = i == Trees.pick and Style.INK.VALUE or Style.INK.TEXT,
            sub = string.format(L["%s spent"], spent > 0 and pop(spent) or tostring(spent)), picked = i == Trees.pick,
            onClick = function() Trees.Pick(i) end })
        if b.icon.SetAtlas then b.icon:SetAtlas(tree.atlas) end
    end
    page.listPieces = s:End()
    local p = Data().Points()
    page.left:SetText(tostring(p.left))
    Style.InkText(page.left, p.left > 0 and "pop" or "OFF")
    page.leftHint:SetText(p.cap and string.format(L["At most %d this season"], p.cap) or "")
end

function Trees.Pick(i)
    if Trees.pick == i then return end
    Trees.pick = i
    Trees.page.shownBefore = nil
    Trees.Render()
    Win.Feel.Stagger({ Trees.page.box }, 0)
end

-- The board

-- Pitch, tile size and column pitch that fit this tree in w x h.
function Trees.Fit(t, w, h)
    local T = Talents()
    local byW = (w - 2 * T.PAD) / (math.max(t.cols, 2) - 1 + T.TILE)
    local byH = (h - T.HEAD - T.PAD) / (math.max(t.rows, 2) - 1 + T.TILE)
    local pitch = math.floor(math.min(byW, byH, T.MAX_PITCH))
    local size = math.floor(pitch * T.TILE)
    local fit = (w - 2 * T.PAD - size) / math.max(t.cols - 1, 1)
    local px = math.max(pitch, math.floor(math.min(pitch * T.WIDE, fit)))
    return pitch, size, px
end

function Trees.Buttons()
    local page = Trees.page
    local changes = Spend.HasChanges()
    page.foot:Set({
        { text = TALENT_FRAME_APPLY_BUTTON_TEXT or L["Apply"], primary = true, off = not changes or Trees.committing ~= nil,
            onClick = function() if Spend.Apply() then Trees.Buttons() end end },
        { text = L["Undo"], off = not changes, onClick = function() if Spend.Undo() then Trees.Soon() end end },
    })
    -- Reset tree sits left of Undo (two clicks via W.Confirm).
    page.reset:ClearAllPoints()
    page.reset:SetPoint("RIGHT", page.foot.buttons[2], "LEFT", -8, 0)
    page.reset:SetShown(Spend.CanReset())
    page.reset.SetOff(Trees.committing ~= nil or not anyBought(Trees.data))
end

-- Search: talents whose name contains the text light up, the rest dim.
function Trees.Search()
    local page = Trees.page
    local text = page.search:GetText() or ""
    local want = text ~= "" and string.lower(text) or nil
    for _, b in ipairs(page.box.tiles) do
        if b.node and b:IsShown() then
            local hit = want and string.find(string.lower(b.node.name or ""), want, 1, true) ~= nil
            b.hit = hit or nil
            b.dim = (want and not hit) or nil
            Talents().PaintTile(b)
        end
    end
end

function Trees.Render(keep)
    local page = Trees.page
    if not (page and page:IsShown()) then return end
    Trees.RenderList()
    local tree = shown()
    local configID = Data().ConfigOf(tree.treeID)
    local data = configID and TD().Read(configID, { treeID = tree.treeID, step = "auto", span = Trees.SPAN, cols = 2, rows = 2 }) or nil
    Trees.data = data
    local box = page.box
    if not data or #data.trees == 0 then
        box:Hide()
        page.note:SetText(L["This Legacy tree isn't available yet."])
        page.note:Show()
        page.seen = nil
        Trees.Buttons()
        return
    end
    page.note:Hide()
    box:Show()
    local t = data.trees[1]
    t.name, t.icon = tree.name, nil
    local main = page.main
    local w = (main:GetWidth() or 0) + Win.GoalGrowth(page)
    if w <= 0 then w = ns.Window.W - Trees.SIDE end
    local _, ph = ns.Window.PageSize()
    local bw, bh = w - 2 * Trees.EDGE, ph - Trees.TOP - Trees.FOOT
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", main, "TOPLEFT", Trees.EDGE, -Trees.TOP)
    box:SetSize(bw, bh)
    box.index = Trees.pick
    local pitch, size, px = Trees.Fit(t, bw, bh)
    Talents().FillTree(box, t, pitch, size, data, px)
    if box.icon.SetAtlas then box.icon:SetAtlas(tree.atlas) end
    box.icon:Show()
    Trees.Search()
    Trees.Buttons()
    if keep then Talents().Animate(page, data) end
    Talents().Remember(page, data)
    page.shownBefore = true
end

-- Trait events come in bursts: re-read next frame, only while the page shows.
function Trees.Soon()
    local page = Trees.page
    if not (page and page:IsVisible()) or Trees.pending then return end
    Trees.pending = true
    C_Timer.After(0, function()
        Trees.pending = nil
        if page:IsVisible() then Trees.Render(true) end
    end)
end

function Trees.Stretch() end   -- the board refills when the grip drag ends

function Trees.Build(page)
    Trees.page = page
    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    side:SetWidth(Trees.SIDE)
    side.win = page.win
    page.side = side
    side.rule = side:CreateTexture(nil, "ARTWORK")
    side.rule:SetTexture(WHITE)
    side.rule:SetVertexColor(1, 1, 1, 0.05)
    side.rule:SetWidth(1)
    side.rule:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, -8)
    side.rule:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 8)
    page.list = Win.Parts.Stack(side, { top = 12, bottom = Trees.LEFT_H + 12 })
    -- Points to spend, under the trees.
    local left = CreateFrame("Frame", nil, side)
    left:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", Trees.EDGE, 14)
    left:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -Trees.EDGE, 14)
    left:SetHeight(Trees.LEFT_H - 14)
    page.leftBox = left
    page.leftLabel = Style.Text(left, Style.SIZE.small, "LEFT")
    page.leftLabel:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
    page.leftLabel:SetText(L["To spend"])
    Style.InkText(page.leftLabel, "LABEL")
    page.left = Style.Text(left, 22, "LEFT")   -- display art: the number is the point
    page.left:SetPoint("TOPLEFT", page.leftLabel, "BOTTOMLEFT", 0, -4)
    page.leftHint = Style.Text(left, Style.SIZE.small, "LEFT")
    page.leftHint:SetPoint("TOPLEFT", page.left, "BOTTOMLEFT", 0, -4)
    page.leftHint:SetPoint("RIGHT", left, "RIGHT", 0, 0)
    Style.InkText(page.leftHint, "LABEL")
    local main = CreateFrame("Frame", nil, page)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    main:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    main.win = page.win
    page.main = main
    page.search = W().Input(main, { search = true, hint = L["Search the tree..."], maxLetters = 64,
        onChange = function() Trees.Search() end })
    page.search:SetPoint("TOPLEFT", main, "TOPLEFT", Trees.EDGE, -10)
    page.search:SetPoint("TOPRIGHT", main, "TOPRIGHT", -Trees.EDGE, -10)
    page.box = Talents().MakeTree(main)
    page.box.spend = Spend
    page.box.changed = Trees.Soon
    page.trees = { page.box }   -- Talents.Animate and Talents.Wave walk page.trees
    page.foot = Win.Parts.Footer(main)
    page.reset = W().Button(page.foot.frame, L["Reset tree"], 28)
    page.reset.fit = 96
    W().Confirm(page.reset, L["Reset tree"], function() Spend.Reset() end)
    page.note = Style.Text(main, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", main, "CENTER", 0, 0)
    Style.InkText(page.note, "LABEL")
    page.note:Hide()
    page:HookScript("OnHide", function(self) self.shownBefore = nil end)
    for _, e in ipairs({ "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "SPELLS_CHANGED" }) do
        DUI.RegisterEvent(e, function() Trees.Soon() end)
    end
    DUI.RegisterEvent("TRAIT_CONFIG_UPDATED", function(_, configID)
        local mine = Trees.committing
        if mine and (configID == mine or call(traits() and traits().ConfigHasStagedChanges, mine) == false) then
            Trees.Finished(true)
        else
            Trees.Soon()
        end
    end)
    DUI.RegisterEvent("CONFIG_COMMIT_FAILED", function() Trees.Finished(false) end)
end

function Trees.Fill(page)
    Trees.Render()
end

function Trees.Pieces(page)
    local out = {}
    for _, p in ipairs(page.listPieces or {}) do out[#out + 1] = p end
    out[#out + 1] = page.leftBox
    out[#out + 1] = page.search
    out[#out + 1] = page.box
    out[#out + 1] = page.foot.frame
    return out
end
