-- Spellbook page: all spells in one scrolling list, two per line, one
-- section per skill line (SpellData). Chips jump to sections, and search
-- matches name and rank. Cooldown sweeps come from the game's duration objects.
--
-- With hideLowRanks off, lower ranks are listed after their spell. The switch
-- only appears when the character has lower ranks at all (the game hides its
-- own for warriors and rogues).
--
-- Out of combat, clicks cast through the single secure button from Cast.lua.
-- In combat, Fight.lua lays a cast button over every row and search, chips
-- and folds are frozen (Spells.Freeze). Dragging picks the spell up, which
-- the game blocks for addon code in combat. Shift-click links the spell, or
-- inserts its name into the macro being edited. Spells learned since the book
-- was last opened glow until hovered (DB.Character().spellsSeen).

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Spells = {}
ns.Spells = Spells

Spells.EDGE = 12
Spells.TOP = 44       -- chips and search row
Spells.FOOT = 40      -- lower ranks switch row
Spells.ROW = 40       -- one line of spells
Spells.COL_GAP = 10
Spells.CELL_MIN = 270 -- minimum cell width; resizing wider adds columns
Spells.ICON = 34
Spells.BORDER = 2     -- icon border, in screen pixels
Spells.EVENTS = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "UNIT_PET", "PET_BAR_UPDATE" }

-- Warm text tones for name, rank and unavailable spells.
Spells.NAME = { 0.93, 0.89, 0.82 }
Spells.SOFT = { 0.74, 0.70, 0.63 }
Spells.QUIET = { 0.55, 0.51, 0.45 }

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function color(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

-- ---------------------------------------------------------------------
-- New spell glow
-- ---------------------------------------------------------------------

local function seenKey(cell) return cell.spellID or cell.name end

-- The very first read only records what's there, so nothing glows.
function Spells.Seen()
    local char = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if not char then return nil end
    if not char.spellsSeen then
        char.spellsSeen = {}
        Spells.seeding = true
    end
    return char.spellsSeen
end

function Spells.IsNew(cell)
    local seen = Spells.Seen()
    -- Lower ranks are never new, even if they only now appear in the list.
    if not seen or cell.passive or cell.future or cell.low then return false end
    local key = seenKey(cell)
    if key == nil then return false end
    if Spells.seeding then seen[key] = true; return false end
    return not seen[key]
end

function Spells.MarkSeen(cell)
    local seen = Spells.Seen()
    local key = cell and seenKey(cell)
    if seen and key ~= nil then seen[key] = true end
end

-- ---------------------------------------------------------------------
-- Spell cells
-- ---------------------------------------------------------------------

local function makeCell(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("AnyUp")   -- click-cast mode can bind any mouse button
    b:RegisterForDrag("LeftButton")
    b.hover = b:CreateTexture(nil, "BACKGROUND")
    b.hover:SetTexture(WHITE)
    b.hover:SetAllPoints(b)
    b.hover:Hide()
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.glow:SetTexture(WHITE)
    b.glow:SetAllPoints(b)
    b.glow:SetBlendMode("ADD")
    b.glow:Hide()
    -- Icon framed like the action bar buttons.
    b.well = CreateFrame("Frame", nil, b)
    b.well:SetSize(Spells.ICON, Spells.ICON)
    b.well:SetPoint("LEFT", b, "LEFT", 4, 0)
    Style.Shell(b.well, { borderPx = Spells.BORDER, noBevel = true })
    b.icon = b.well:CreateTexture(nil, "ARTWORK")
    Style.CropIcon(b.icon)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    b.name = Style.Text(b, Style.SIZE.body, "LEFT")
    b.name:SetPoint("TOPLEFT", b.well, "TOPRIGHT", 8, -2)
    b.name:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.name:SetWordWrap(false)
    b.rank = Style.Text(b, Style.SIZE.small, "LEFT")
    b.rank:SetPoint("BOTTOMLEFT", b.well, "BOTTOMRIGHT", 8, 2)
    b.rank:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.rank:SetWordWrap(false)
    b.shine = b:CreateTexture(nil, "OVERLAY")
    b.shine:SetTexture(WHITE)
    b.shine:SetBlendMode("ADD")
    b.shine:Hide()
    b:SetScript("OnEnter", function(self)
        Spells.Enter(self)
        if ns.Cast and not Spells.binding then ns.Cast.Over(self) end
    end)
    b:SetScript("OnLeave", function(self) Spells.Leave(self) end)
    b:SetScript("OnDragStart", function(self) if not Spells.binding then Spells.Drag(self) end end)
    b:SetScript("OnClick", function(self, button)
        if Spells.binding then Spells.BindClick(self, button) else Spells.Modified(self, button) end
    end)
    return b
end

-- How many columns fit in width w.
function Spells.Cols(w)
    return math.max(2, math.floor((w + Spells.COL_GAP) / (Spells.CELL_MIN + Spells.COL_GAP)))
end

local function layPair(pair, w)
    local n = pair.n or 2
    local cw = math.floor((w - (n - 1) * Spells.COL_GAP) / n)
    pair.cw = cw   -- read by Spells.Rows for the combat cast buttons
    for k = 1, n do
        local b = pair.cells[k]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", pair, "TOPLEFT", (k - 1) * (cw + Spells.COL_GAP), 0)
        b:SetSize(cw, Spells.ROW)
    end
end

local function makePair(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.cells = { makeCell(f), makeCell(f) }
    f.Stretch = function(w) layPair(f, w) end
    return f
end

function Spells.PaintCooldown(b)
    local c = b.cell
    local d
    if c and c.slot and type(C_SpellBook.GetSpellBookItemCooldownDuration) == "function" then
        d = C_SpellBook.GetSpellBookItemCooldownDuration(c.slot, c.bank)
    elseif c and c.spellID and C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function" then
        d = C_Spell.GetSpellCooldownDuration(c.spellID)
    end
    if type(d) == "nil" or c.passive then
        if b.cd.Clear then b.cd:Clear() end
        return
    end
    if type(b.cd.SetCooldownFromDurationObject) == "function" then pcall(b.cd.SetCooldownFromDurationObject, b.cd, d, true) end
end

function Spells.PaintCell(b, cell)
    b.cell = cell
    b.icon:SetTexture(cell.icon)
    -- Inset by the border on every fill, since the UI scale may have changed.
    local t = DUI.Pixel.Px(b.well, Spells.BORDER)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", b.well, "TOPLEFT", t, -t)
    b.icon:SetPoint("BOTTOMRIGHT", b.well, "BOTTOMRIGHT", -t, t)
    local off = cell.future
    b.icon:SetDesaturated(off and true or false)
    b.icon:SetAlpha(1)
    b.name:SetText(cell.name)
    color(b.name, off and Spells.QUIET or Spells.NAME)
    b.rank:SetText(cell.rank or "")
    color(b.rank, off and Spells.QUIET or Spells.SOFT)
    -- In click-cast mode the rank line shows the bound clicks instead, and
    -- spells that can't be bound are dimmed.
    if Spells.binding then
        local entry = DUI.ClickBind.Entry(cell)
        local clicks = entry and DUI.ClickBind.Clicks(entry.spell) or {}
        if #clicks > 0 then
            b.rank:SetText(table.concat(clicks, ", "))
            b.rank:SetTextColor(Style.Accent())
        end
        if not entry then color(b.name, Spells.QUIET) end
    end
    b.hover:SetVertexColor(unpack(DUI.Win.Parts.HI))   -- shared list row hover color
    b.new = Spells.IsNew(cell) or nil
    if b.new then
        local r, g, bl = Style.Accent()
        b.glow:SetVertexColor(r, g, bl, 0.14)
    end
    b.glow:SetShown(b.new and true or false)
    Spells.PaintCooldown(b)
end

-- ---------------------------------------------------------------------
-- Hover, drag, clicks
-- ---------------------------------------------------------------------

function Spells.Enter(b)
    local cell = b.cell
    if not cell then return end
    DUI.Win.Parts.Light(b.hover, true)
    if b.new then
        b.new = nil
        b.glow:Hide()
        Spells.MarkSeen(cell)
    end
    local tip = GameTooltip
    if not tip then return end
    if Spells.binding then return Spells.BindTip(b) end
    tip:SetOwner(b, "ANCHOR_RIGHT")
    if cell.slot and type(tip.SetSpellBookItem) == "function" then
        tip:SetSpellBookItem(cell.slot, cell.bank)
    elseif cell.spellID and type(tip.SetSpellByID) == "function" then
        tip:SetSpellByID(cell.spellID)
    end
    if InCombatLockdown() and not cell.passive then
        local Tips = DUI.Tips   -- appended under the spell's own lines
        Tips.Clear()
        -- When frozen, Fight.lua's buttons still cast; only dragging is blocked.
        Tips.Text(Spells.frozen and L["Dragging spells to your bars works out of combat."]
            or L["Clicking and dragging work out of combat."], Tips.WARN)
        Tips.Flush(tip)
    end
    tip:Show()
end

function Spells.Leave(b)
    DUI.Win.Parts.Light(b.hover, false)
    if GameTooltip and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
end

-- The game blocks addon code from picking up spells in combat.
function Spells.Pickup(cell)
    if not cell or InCombatLockdown() or cell.future then return end
    if cell.slot then
        C_SpellBook.PickupSpellBookItem(cell.slot, cell.bank)
    elseif cell.spellID and C_Spell and type(C_Spell.PickupSpell) == "function" then
        C_Spell.PickupSpell(cell.spellID)
    end
end

function Spells.Drag(b) Spells.Pickup(b.cell) end

-- Shift-click links the spell in chat, or inserts its name into the macro
-- being edited, like SpellBookItemMixin:OnModifiedIconClick.
function Spells.Modified(b, button)
    local cell = b.cell
    if not cell or button ~= "LeftButton" or not IsModifiedClick("CHATLINK") then return end
    local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    if type(insert) ~= "function" then return end
    local macro = _G.MacroFrameText
    if type(macro) == "table" and macro.HasFocus and macro:HasFocus() then
        if cell.passive then return end
        insert(cell.rank and (cell.name .. "(" .. cell.rank .. ")") or cell.name)
        return
    end
    local link
    if cell.slot then
        link = C_SpellBook.GetSpellBookItemTradeSkillLink and C_SpellBook.GetSpellBookItemTradeSkillLink(cell.slot, cell.bank)
        link = link or (C_SpellBook.GetSpellBookItemLink and C_SpellBook.GetSpellBookItemLink(cell.slot, cell.bank))
    elseif cell.spellID and C_Spell and C_Spell.GetSpellLink then
        link = C_Spell.GetSpellLink(cell.spellID)
    end
    if link then insert(link) end
end

-- ---------------------------------------------------------------------
-- Click-cast mode, using the unit frames' binder (DUI.ClickBind). While on,
-- clicking a spell binds that click and modifiers on unit frames, and the
-- same click again removes it. Spells don't cast or drag in this mode.
-- ---------------------------------------------------------------------

local function bindUsable() return DUI.ClickBind ~= nil and DUI.ClickBind.Usable() end

-- Called on ClickCastChanged with the binder's current state.
function Spells.BindMode(on)
    on = on and bindUsable() or false
    Spells.binding = on or nil
    local page = Spells.page
    if not page then return end
    if page.bind then page.bind.SetActive(on) end
    if on and ns.Cast then ns.Cast.Hide() end
    if page:IsVisible() and Spells.data then Spells.Render(page) end
end

function Spells.BindTip(b)
    local entry = b.cell and DUI.ClickBind.Entry(b.cell)
    local Tips = DUI.Tips
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    Tips.Clear()
    Tips.Title(b.cell.rank and (b.cell.name .. " (" .. b.cell.rank .. ")") or b.cell.name)
    if not entry then
        Tips.Text(L["Only spells you cast can be bound."], Tips.WARN)
    else
        Tips.Text(L["Click with the mouse button you want, holding Shift, Ctrl or Alt if you like: "
            .. "that click on a unit frame then casts it on that unit."])
        local clicks = DUI.ClickBind.Clicks(entry.spell)
        if #clicks > 0 then
            Tips.Gap()
            for _, text in ipairs(clicks) do Tips.Sub(text) end
            Tips.Hint(L["The same click again removes it."])
        end
        if InCombatLockdown() then Tips.Text(L["Takes effect once this fight is over."], Tips.WARN) end
    end
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

function Spells.BindClick(b, button)
    local entry = b.cell and DUI.ClickBind.Entry(b.cell)
    if not entry then
        if DUI.Sound then DUI.Sound.Play("nope") end
        return
    end
    DUI.ClickBind.Click(entry, button)
    if DUI.Motion and DUI.Motion.Bump then DUI.Motion.Bump(b.icon) end
    Spells.PaintCell(b, b.cell)
    if b:IsMouseOver() then Spells.BindTip(b) end
end

local function makeBind(page)
    local W = DUI.Widgets
    local t = W.Button(page, L["Click-cast"], 22)
    t.FitWidth(84)
    t:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -Spells.EDGE - 4, 10)
    t:SetScript("OnClick", function() DUI.ClickBind.Set(not DUI.ClickBind.On()) end)
    t:HookScript("OnEnter", function(self)
        W.Tooltip(self, L["Click-cast"], L["Switch on, then click a spell with the mouse button you want "
            .. "(hold Shift, Ctrl or Alt for more): that click on a unit frame casts it. "
            .. "/dui > Unit Frames > Click-casting lists them."])
    end)
    t:HookScript("OnLeave", W.HideTooltip)
    return t
end

-- Clique puts its own tab on the game's spellbook, which this window covers,
-- so the page carries a link to Clique's bindings window instead. Both the
-- original addon and its Forever port name their addon table after the folder.
Spells.CLIQUE = { "Clique", "CliqueForever" }

function Spells.Clique()
    local A = C_AddOns
    if not (A and type(A.IsAddOnLoaded) == "function") then return nil end
    for _, name in ipairs(Spells.CLIQUE) do
        local addon = _G[name]
        if A.IsAddOnLoaded(name) == true and type(addon) == "table"
            and type(addon.ShowBindingConfig) == "function" then
            return addon
        end
    end
    return nil
end

-- Clique's window takes the book's place, as its own spellbook tab does.
-- In a fight Clique refuses with a message of its own, and the book stays.
function Spells.OpenClique()
    local addon = Spells.Clique()
    if not addon then return end
    local ok = pcall(addon.ShowBindingConfig, addon)
    if ok and not InCombatLockdown() and ns.Window then ns.Window.Close() end
end

local function makeClique(page)
    local link = DUI.Widgets.Link(page)
    link.SetLabel(L["Open Clique"])
    link:SetScript("OnClick", function() Spells.OpenClique() end)
    link:Hide()
    return link
end

-- Where the Click-cast button would be, or just left of it when both show.
local function placeClique(page)
    local link = page.clique
    link:ClearAllPoints()
    if page.bind:IsShown() then
        link:SetPoint("RIGHT", page.bind, "LEFT", -12, 0)
    else
        link:SetPoint("RIGHT", page, "BOTTOMRIGHT", -Spells.EDGE - 4, 21)
    end
end

-- ---------------------------------------------------------------------
-- Page
-- ---------------------------------------------------------------------

-- Section chip; clicking jumps to that section.
local function makeChip(parent)
    local b = DUI.Widgets.Chip(parent)
    b:SetScript("OnClick", function(self) Spells.Jump(self.section) end)
    return b
end

-- "Hide lower ranks" switch. Clicking the label toggles it too.
local function makeSwitch(page)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(180, 22)
    b:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", Spells.EDGE + 4, 10)
    b.sw = DUI.Widgets.Switch(b)
    b.sw:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text = Style.Text(b, Style.SIZE.small, "LEFT")
    b.text:SetPoint("LEFT", b.sw, "RIGHT", 8, 0)
    b.text:SetText(L["Hide lower ranks"])
    color(b.text, Spells.SOFT)
    b.sw:SetScript("OnClick", function()
        local on = ns.Setting("hideLowRanks") ~= false
        DUI:Set("Book", "hideLowRanks", not on)
        Spells.Fill(Spells.page, true)
    end)
    b:SetScript("OnClick", function() b.sw:Click() end)
    return b
end

local function paintSwitch(b)
    b.sw.SetOn(ns.Setting("hideLowRanks") ~= false)
end

local layoutChips

function Spells.Build(page)
    Spells.page = page
    if ns.Cast then ns.Cast.Init() end
    local box = DUI.Widgets.Input(page, { height = 24, search = true, hint = SEARCH or L["Search"],
        onChange = function(t) Spells.Search(t) end })
    box:SetWidth(150)
    box:SetPoint("TOPRIGHT", page, "TOPRIGHT", -Spells.EDGE, -10)
    page.search = box
    page.chips = {}
    page.stack = Win.Parts.Stack(page, { top = Spells.TOP, bottom = Spells.FOOT })
    page.switch = makeSwitch(page)
    page.bind = makeBind(page)
    page.clique = makeClique(page)
    DUI.On("ClickCastChanged", function() Spells.BindMode(DUI.ClickBind and DUI.ClickBind.On()) end)
    page.note = Style.Text(page, Style.SIZE.body, "CENTER")
    page.note:SetPoint("CENTER", page, "CENTER", 0, 0)
    color(page.note, Style.INK.LABEL)   -- empty-list text
    page.note:Hide()
    page:HookScript("OnHide", function()
        if ns.Cast then ns.Cast.Hide() end
        -- Closing the window ends click-cast mode; switching tabs doesn't.
        local f = ns.Window and ns.Window.frame
        if Spells.binding and not (f and Win.IsOpen(f)) then DUI.ClickBind.Set(false) end
    end)
    for _, e in ipairs(Spells.EVENTS) do
        DUI.RegisterEvent(e, function() Spells.Soon() end)
    end
    DUI.RegisterEvent("SPELL_UPDATE_COOLDOWN", function() Spells.Cooldowns() end)
    -- The search box follows the page's edge while the window is resized, so
    -- the chips are fitted again then, not only once the drag ends.
    page:HookScript("OnSizeChanged", function() if Spells.data then layoutChips(page) end end)
end

-- Spell events arrive in bursts, so refill once on the next frame, and only
-- while visible.
function Spells.Soon()
    local page = Spells.page
    if not page then return end
    -- Hidden or frozen for combat: refill when next needed.
    if Spells.frozen or not page:IsVisible() then Spells.dirty = true; return end
    if Spells.pending then return end
    Spells.pending = true
    C_Timer.After(0, function()
        Spells.pending = nil
        if page:IsVisible() then Spells.Fill(page, true) end
    end)
end

function Spells.Cooldowns()
    local page = Spells.page
    if not (page and page:IsVisible()) then return end
    for _, b in ipairs(page.stack.used) do
        if b.cells then for _, c in ipairs(b.cells) do if c:IsShown() and c.cell then Spells.PaintCooldown(c) end end end
    end
end

-- ---------------------------------------------------------------------
-- Section folds, saved per character by skill line name (those don't change)
-- ---------------------------------------------------------------------

function Spells.Folds()
    local char = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if not char then return {} end
    if type(char.spellFolds) ~= "table" then char.spellFolds = {} end
    return char.spellFolds
end

function Spells.IsFolded(section) return Spells.Folds()[section.name] == true end

function Spells.Fold(section, folded)
    if Spells.frozen then return end
    Spells.Folds()[section.name] = folded or nil
    if DUI.Sound then DUI.Sound.Play("toggle") end
    if Spells.page then Spells.Fill(Spells.page, true) end
end

-- Section header styled like the window kit's. Click to fold; shows "+"
-- while folded, like the character window's stat groups.
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
    DUI.Widgets.PadSpot(b)
    b:SetScript("OnEnter", function(self) color(self.text, Spells.SOFT); color(self.state, Spells.SOFT) end)
    b:SetScript("OnLeave", function(self) color(self.text, Spells.QUIET); color(self.state, Spells.QUIET) end)
    b:SetScript("OnClick", function(self)
        if self.section and not Spells.filter then Spells.Fold(self.section, not Spells.IsFolded(self.section)) end
    end)
    return b
end

local function head(s, section, folded)
    local b = s:Piece("head", makeHead, 22, 12)
    b.section = section
    b.text:SetText(string.upper(section.name or ""))
    b.state:SetText(folded and "+" or "")
    color(b.text, Spells.QUIET)
    color(b.state, Spells.QUIET)
    return b
end

local function matches(cell, want)
    if not want then return true end
    if string.find(string.lower(cell.name), want, 1, true) then return true end
    return cell.rank ~= nil and string.find(string.lower(cell.rank), want, 1, true) ~= nil
end

-- Build the list from Spells.data and the current search.
function Spells.Render(page)
    local data = Spells.data
    local s = page.stack
    local want = Spells.filter
    s:Begin()
    Spells.sectionAt = {}
    local any = false
    for _, section in ipairs(data.sections) do
        local cells = {}
        for _, cell in ipairs(section.spells) do
            local lows = {}
            for _, low in ipairs(cell.lows) do if matches(low, want) then lows[#lows + 1] = low end end
            if matches(cell, want) or #lows > 0 then cells[#cells + 1] = cell end
            for _, low in ipairs(lows) do cells[#cells + 1] = low end
        end
        if #cells > 0 then
            any = true
            Spells.sectionAt[section] = s.y
            -- Searching shows matches even in folded sections.
            local folded = not want and Spells.IsFolded(section)
            head(s, section, folded)
            if folded then cells = {} end
            local width = s:Width()
            Spells.renderW = width   -- lets Spells.Prepare skip a refill at the same width
            local n = Spells.Cols(width)
            for i = 1, #cells, n do
                local pair = s:Piece("pair", makePair, Spells.ROW, i == 1 and 8 or 2)
                for k = #pair.cells + 1, n do pair.cells[k] = makeCell(pair) end
                pair.n = n
                layPair(pair, width)
                for k = 1, #pair.cells do
                    local b, cell = pair.cells[k], k <= n and cells[i + k - 1] or nil
                    if cell then Spells.PaintCell(b, cell); b:Show() else b.cell = nil; b:Hide() end
                end
            end
        end
    end
    page.pieces = s:End()
    page.note:SetShown(not any)
    page.note:SetText(want and L["No spells match."] or L["No spells yet."])
    Spells.seeding = nil
end

function Spells.Jump(section)
    if Spells.frozen then return end
    Spells.jumped = section
    if Spells.IsFolded(section) then Spells.Fold(section, false) end
    local y = Spells.sectionAt and Spells.sectionAt[section]
    if y and Spells.page then Spells.page.stack:ScrollTo(y) end
end

-- Sections whose chips didn't fit go into the More menu, so a long language or a
-- narrow window never leaves a section out of reach.
function Spells.MoreMenu(owner)
    local keys, values = {}, {}
    for i, section in ipairs(Spells.folded or {}) do
        keys[i] = i
        values[i] = section.name
    end
    local current
    for i, section in ipairs(Spells.folded or {}) do if section == Spells.jumped then current = i end end
    DUI.Widgets.OpenMenu(owner, keys, values, current, function(i)
        local section = Spells.folded and Spells.folded[i]
        if section then Spells.Jump(section) end
    end)
end

local function makeMore(page)
    local b = DUI.Widgets.MenuButton(page, L["More"], DUI.Widgets.CHIP_HEIGHT)
    b:SetScript("OnClick", function(self) Spells.MoreMenu(self) end)
    b:Hide()
    return b
end

function layoutChips(page)
    local w = page:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = ns.Window.SIZE.spells[1] end
    local room = w - 2 * Spells.EDGE - 160
    local gap = DUI.Widgets.CHIP_GAP
    local sections = Spells.data.sections
    for i, section in ipairs(sections) do
        local c = page.chips[i]
        if not c then c = makeChip(page); page.chips[i] = c end
        c.section = section
        c.text:SetText(section.name)
        c.FitWidth()
    end
    for i = #sections + 1, #page.chips do page.chips[i]:Hide() end
    -- Do they all fit? Otherwise keep room at the end for More.
    local total = 0
    for i = 1, #sections do total = total + page.chips[i]:GetWidth() + (i > 1 and gap or 0) end
    page.more = page.more or makeMore(page)
    local more = page.more
    local spare = room
    if total > room then
        more.SetLabel(L["More"], 0)
        spare = room - more:GetWidth() - gap
    end
    local M = DUI.Motion
    local lit = Spells.frozen and Spells.REST or 1   -- a fight keeps them dimmed
    local x, folded = Spells.EDGE, {}
    for i, section in ipairs(sections) do
        local c = page.chips[i]
        local cw = c:GetWidth()
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", page, "TOPLEFT", x, -11)
        local fits = #folded == 0 and x + cw - Spells.EDGE <= spare
        -- A chip coming back out of More eases in.
        if fits and not c:IsShown() then c:Show(); M.Fade(c, 0, lit, M.FAST) end
        if not fits then c:Hide() end
        if fits then x = x + cw + gap else folded[#folded + 1] = section end
    end
    Spells.folded = folded
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
        M.Fade(more, 0, lit, M.FAST)
    else
        M.Tween(more.glide, select(4, more:GetPoint(1)) or x, x, M.NORMAL, place)
    end
end

-- keep preserves the scroll position (spell events, the ranks switch).
function Spells.Fill(page, keep)
    page = page or Spells.page
    if not page then return end
    if Spells.frozen then Spells.dirty = true; return end   -- combat cast buttons sit on these rows
    Spells.dirty = nil
    local at = keep and page.stack:Scrolled() or 0
    Spells.data = ns.SpellData.Read(ns.Setting("hideLowRanks") == false)
    layoutChips(page)
    page.switch:SetShown(Spells.data.anyLow)
    paintSwitch(page.switch)
    page.bind:SetShown(bindUsable())
    Spells.binding = (bindUsable() and DUI.ClickBind.On()) or nil
    page.bind.SetActive(Spells.binding and true or false)
    page.clique:SetShown(Spells.Clique() ~= nil)
    placeClique(page)
    Spells.filter = nil
    local t = page.search:GetText() or ""
    if t ~= "" then Spells.filter = string.lower(t) end
    Spells.Render(page)
    page.stack:ScrollTo(at)
end

function Spells.Search(text)
    local page = Spells.page
    if not (page and Spells.data) then return end
    if Spells.frozen then Spells.dirty = true; return end
    Spells.filter = (type(text) == "string" and text ~= "") and string.lower(text) or nil
    Spells.Render(page)
end

-- ---------------------------------------------------------------------
-- Combat support for Fight.lua
-- ---------------------------------------------------------------------

-- Lay out the list at the spells page's size before combat. The window may
-- be closed or on another page, so f.goalW tells Stack:Width the target width.
function Spells.Prepare(f)
    local page = Spells.page
    if not page then return end
    local w = ns.Window.PageSize("spells")
    local onIt = Win.IsOpen(f) and f.current == "spells"
    -- Usually already laid out at the right width.
    local want = w - 2 * (page.stack.side or Win.Parts.EDGE)
    if Spells.data and not Spells.dirty and (onIt or Spells.renderW == want) then return end
    local keep = f.goalW
    if not onIt then f.goalW = w end
    Spells.Fill(page, true)
    f.goalW = keep
end

-- Every castable row with its box in list coordinates (x, y from the top, w, h).
function Spells.Rows(page)
    local out = {}
    local cast = ns.Cast
    for _, p in ipairs(page.stack.used) do
        if p.cells and p.cw and type(p.stackY) == "number" then
            for k = 1, p.n or 2 do
                local b = p.cells[k]
                if b and b:IsShown() and b.cell and cast and cast.Attributes(b.cell) then
                    out[#out + 1] = { row = b, x = (k - 1) * (p.cw + Spells.COL_GAP), y = p.stackY, w = p.cw, h = Spells.ROW }
                end
            end
        end
    end
    return out
end

-- Dim and disable controls that would change the list while combat cast
-- buttons sit on it. Scrolling then only happens through the secure wheel.
Spells.REST = 0.4
function Spells.Freeze(on)
    on = on and true or nil
    if Spells.frozen == on then return end
    Spells.frozen = on
    local page = Spells.page
    if not page then return end
    local M = DUI.Motion
    local parts = { page.search, page.switch, page.bind, page.clique }
    for _, c in ipairs(page.chips) do parts[#parts + 1] = c end
    if page.more then parts[#parts + 1] = page.more end
    for _, c in ipairs(parts) do
        local from, to = on and 1 or Spells.REST, on and Spells.REST or 1
        if M then M.Fade(c, from, to, M.FAST) else c:SetAlpha(to) end
        c:EnableMouse(not on)
    end
    if on and page.search.ClearFocus then page.search:ClearFocus() end
    page.stack.bar.Lock(on)
    if not on and Spells.dirty and page:IsVisible() then Spells.Fill(page, true) end
end

-- Follow the secure wheel instantly so rows stay under their cast buttons.
function Spells.ScrollTo(at)
    local page = Spells.page
    if not page then return end
    local s = page.stack
    s.bar.Stop()
    s.scroll:SetVerticalScroll(at)
    s.at = at
    s.bar.Wake()
end

-- Pieces in the order they animate in when the page opens. While frozen the
-- dimmed controls are left out so they keep their dim.
function Spells.Pieces(page)
    local out = {}
    local rest = Spells.frozen
    if not rest then
        for _, c in ipairs(page.chips) do if c:IsShown() then out[#out + 1] = c end end
        if page.more and page.more:IsShown() then out[#out + 1] = page.more end
        out[#out + 1] = page.search
    end
    for i, p in ipairs(page.pieces or {}) do
        if i > 14 then break end
        out[#out + 1] = p
    end
    if not rest and page.switch:IsShown() then out[#out + 1] = page.switch end
    if not rest and page.bind:IsShown() then out[#out + 1] = page.bind end
    if not rest and page.clique:IsShown() then out[#out + 1] = page.clique end
    return out
end

-- ---------------------------------------------------------------------
-- A controller: the game's spellbook buttons (SetUpSpellBookGamepad in
-- Blizzard_PlayerSpellsFrame.lua). A casts, X puts the spell on a
-- controller bar, the right menu button flips the ranks switch, LB and RB
-- step through the schools (the left menu button searches, as on every window).
-- ---------------------------------------------------------------------

local function padCell(b)
    return type(b) == "table" and type(b.cell) == "table" and b.cell or nil
end

-- What A casts on this row, through the controller's secure key.
function Spells.PadCast(b)
    local cell = padCell(b)
    if not cell or Spells.binding or Spells.frozen or not ns.Cast then return nil end
    return ns.Cast.Attributes(cell)
end

function Spells.CanBind(b)
    local cell = padCell(b)
    return cell ~= nil and not Spells.binding and not cell.future and not cell.passive
end

function Spells.Bind(b)
    local cell = padCell(b)
    if not cell then return end
    DUI.Pad.BindAction({ icon = cell.icon, name = cell.rank and (cell.name .. " (" .. cell.rank .. ")") or cell.name,
        pickup = function() Spells.Pickup(cell) end })
end

-- The school chips LB and RB step through, and the one last jumped to.
function Spells.PadTabs()
    local out, at = {}, nil
    local page = Spells.page
    if not page then return out end
    for _, c in ipairs(page.chips) do
        if c:IsShown() and c.section then
            out[#out + 1] = c
            if c.section == Spells.jumped then at = #out end
        end
    end
    return out, at
end

function Spells.PadKeys(on)
    local page = function() return Spells.page end
    return {
        { key = "A", label = CONTEXT_ACTION_LABEL_CAST or L["Cast"], when = on, secure = Spells.PadCast },
        { key = "X", label = CONTEXT_ACTION_LABEL_BIND_TO_GAMEPAD_ACTION_BAR or L["Bind"],
          when = function(b) return on() and Spells.CanBind(b) end, run = Spells.Bind },
        { key = "MENU_RIGHT", label = L["Hide lower ranks"],
          when = function() return on() and page().switch:IsShown() and not Spells.frozen end,
          run = function() page().switch.sw:Click() end },
    }
end
