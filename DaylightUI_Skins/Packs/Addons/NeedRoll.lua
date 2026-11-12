-- Skins NeedRoll (the loot browser for Forever): window, panes, lists, buttons,
-- scroll bars, dialogs and menus get our look, font and text colors. Its icons,
-- maps, class badges and crests are kept.
-- How (UI/Theme.lua, UI/MainFrame.lua, v0.16.2): NeedRoll has two looks. Native
-- is the default (a ButtonFrameTemplate window, InsetFrameTemplate panes over
-- Collections parchment, the game's buttons, checkboxes, edit boxes, tabs and
-- gold/white/gray text). Modern is flat panels in its own blues. We dress
-- Native (NeedRollNativeFrame); Modern is the author's own look and stays as is.
-- Its colors live in a private table (ns.Theme) we can't reach, so pieces are
-- recognized by what its builders create (Theme:Row's hover/selected/bar,
-- Theme:Pill's fill/edge/text, Theme:ScrollBar's thumb and Update,
-- Theme:Rounded's bg/border, a pane's parchment), never by color. Its text
-- styles are named font objects (NeedRollFontNative*, created on load), which
-- get our font and ink once and again on style changes. Text it colors itself
-- (gray notes, link blue, done/not done) is re-inked on each pass.
-- The window is created on first open (every path goes through its local
-- UI:Show), so we watch its slash command, key binding (the compartment
-- function), its API for other addons, and the first clicks until it exists.
-- Any click or wheel in it triggers another pass, since that's when it fills
-- its lists.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style = DUI.Style

local ADDON = "NeedRoll"
local FRAME = "NeedRollNativeFrame"

Engine.AddonSwitch({ key = "needroll", addon = ADDON, label = "NeedRoll",
    desc = "The loot browser's window, its lists, buttons and dialogs; its icons and maps kept." })

local function isTable(x) return type(x) == "table" end
local function kind(x) return isTable(x) and x.GetObjectType and x:GetObjectType() or nil end

local NR = {}
ns.NeedRoll = NR
NR.DEPTH = 16 -- how deep its window goes

-- Its font objects (Theme.lua BuildFonts, native) and the ink each one gets.
NR.FONTS = { Title = "VALUE", Heading = "LABEL", Tab = "LABEL", Body = "TEXT", Suffix = "TEXT",
    Small = "LABEL", Source = "LABEL", Note = "LABEL", Label = "LABEL", Pane = "LABEL", Ruled = "LABEL",
    Instance = "VALUE", FactLabel = "LABEL", FactValue = "VALUE", Section = "pop", Hint = "LABEL" }

-- Colors it applies itself from its native palette, mapped to our ink (its gold
-- and the game's gray are handled by Kit.GAME_INK): muted gray, link blue (a
-- clickable quest giver), quest done and not done.
NR.INK = {
    { 0.627, 0.627, 0.627, "LABEL" },
    { 0.443, 0.835, 1, "pop" },
    { 0.102, 1, 0.102, "GOOD" },
    { 1, 0.125, 0.125, "BAD" },
    { 0.988, 0.824, 0.624, "pop" }, -- a picked row's name
    { 0.949, 0.831, 0.361, "pop" }, -- a quest you can take
}
NR.NEAR = 0.03
-- The same colors baked into text as escape codes (the breadcrumb trail, "In
-- this dungeon"): its gold and similar become the accent.
NR.CODES = { "|c[fF][fF][fF][fF][dD]100", "|c[fF][fF][fF][cC][dD]29[fF]", "|c[fF][fF][fF]2[dD]45[cC]" }

-- Our font and ink on its font objects (and the larger copies it makes for
-- Large text, NeedRollScaledFont1...), sizes kept.
function NR.Fonts()
    local face = Style.FontFile(Style.WINDOW_SLOT)
    local function dress(obj, role)
        if not isTable(obj) or not obj.GetFont or not obj.SetFont then return end
        local ok, current, size, flags = pcall(obj.GetFont, obj)
        if ok and type(size) == "number" and size > 0 and current ~= face then
            obj:SetFont(face, size, flags or "")
        end
        if role and obj.SetTextColor then Style.InkText(obj, role) end
    end
    for name, role in pairs(NR.FONTS) do dress(_G["NeedRollFontNative" .. name], role) end
    local i = 1
    while _G["NeedRollScaledFont" .. i] do
        dress(_G["NeedRollScaledFont" .. i])
        i = i + 1
    end
end

local function near(a, b) return math.abs(a - b) <= NR.NEAR end
local function inkText(fs)
    local r, g, b = fs:GetTextColor()
    if type(r) ~= "number" or (issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b))) then return end
    for _, c in ipairs(NR.INK) do
        if near(r, c[1]) and near(g, c[2]) and near(b, c[3]) then
            Style.InkText(fs, c[4])
            break
        end
    end
    local text = fs:GetText()
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or not text:find("|c", 1, true) then return end
    local hex = DUI.Win.Parts.Hex({ Style.Accent() })
    local new = text
    for _, code in ipairs(NR.CODES) do new = new:gsub(code, hex) end
    if new ~= text then fs:SetText(new) end
end

-- Its pieces, recognized by what its builders create.
local dressed = setmetatable({}, { __mode = "k" }) -- frame -> what it was dressed as
local function rowOf(f)
    return kind(f) == "Button" and kind(f.hover) == "Texture" and kind(f.selected) == "Texture"
        and type(f.SetSelected) == "function"
end
local function pillOf(f)
    return kind(f) == "Button" and kind(f.fill) == "Texture" and kind(f.edge) == "Texture"
        and kind(f.text) == "FontString" and type(f.SetLabel) == "function"
end
local function barOf(f)
    return isTable(f.thumb) and f.thumb.GetRegions and type(f.Update) == "function"
end
local function roundedOf(f)
    return kind(f.bg) == "Texture" and kind(f.border) == "Texture"
end

local function picked(row) return row.isSelected == true end

-- Its list row (Theme:Row) drawn as a line like our lists: no box, just its own
-- alternating band, a hover wash and the accent wash on the picked one, with its
-- icon and text kept. That way a list reads as one list and section headers
-- (below) stand apart.
NR.rows = setmetatable({}, { __mode = "k" })

local function row(Kit, f)
    Kit.Erase(f.hover)
    Kit.Erase(f.selected)
    Kit.Erase(f.bar)
    NR.rows[f] = {}
    Kit.Row(f, "art", picked, false)
    hooksecurefunc(f, "SetSelected", Engine.Safe(NR.def, function() Kit.RepaintRow(f) end))
end

-- Section headers (Overview, Quests, Encounters): a closed one sits on a faint
-- band where its card was, so it reads as a button. The open one's band is its
-- section card, with name and disc ring in the accent.
NR.SHUT = { 1, 1, 1, 0.045 }
NR.CARD = { 1, 1, 1, 0.03 }
local function paintHeader(f)
    local d = NR.rows[f]
    if not d or not d.band then return end
    d.band:SetShown(f.shut == true)
    if kind(f.title) == "FontString" then Style.InkText(f.title, f.shut and "TEXT" or "pop") end
    if not f.shut and isTable(f.disc) and kind(f.disc.ring) == "Texture" then
        local r, g, b = Style.Accent()
        f.disc.ring:SetVertexColor(r, g, b, 1)
    end
end

-- Some lists create this after the row (NewShutCard), so check on each pass.
local function header(Kit, f)
    local d = NR.rows[f]
    if not d or d.band or type(f.PaintShut) ~= "function" or kind(f.shutFill) ~= "Texture" then return end
    Kit.Erase(f.shutFill)
    Kit.Erase(f.shutEdge)
    d.band = DUI.Widgets.Round(f, "BACKGROUND", -2)
    d.band:SetAllPoints(f.shutFill)
    DUI.Widgets.Tint(d.band, NR.SHUT)
    hooksecurefunc(f, "PaintShut", Engine.Safe(NR.def, function() paintHeader(f) end))
    paintHeader(f)
end

-- Its pill button (Theme:Pill): our button look, label re-inked after each of
-- its own paints (gold at rest, a tone while it's asking).
NR.pills = setmetatable({}, { __mode = "k" })
function NR.Pill(f) return NR.pills[f] end
local function pill(Kit, f)
    Kit.Erase(f.fill)
    Kit.Erase(f.edge)
    local s = DUI.Widgets.ButtonLook(f, {}, f.text)
    NR.pills[f] = s
    local function words()
        local c = f.tone and Style.INK.WARN or DUI.Widgets.BUTTON.text
        f.text:SetTextColor(c[1], c[2], c[3])
        Kit.Refont(f.text)
        -- Its symbol (back, plus, close) is drawn in strokes in the text color.
        for _, r in ipairs({ f:GetRegions() }) do
            if kind(r) == "Texture" and r ~= f.fill and r ~= f.edge and r:GetDrawLayer() == "ARTWORK" then
                r:SetVertexColor(c[1], c[2], c[3], 1)
            end
        end
    end
    if type(f.Paint) == "function" then hooksecurefunc(f, "Paint", Engine.Safe(NR.def, words)) end
    f:HookScript("OnEnter", function() s.Hover(true); words() end)
    f:HookScript("OnLeave", function() s.Hover(false); words() end)
    f:HookScript("OnMouseDown", function() s.down = true; s.Paint() end)
    f:HookScript("OnMouseUp", function() s.down = false; s.Paint() end)
    words()
end

-- Its slim scroll bar (Theme:ScrollBar): our faint line and pill thumb. It sets
-- its own line's color and width when drawing, so that line is erased (a mask
-- survives whatever it sets) and ours is drawn beside it.
NR.thumbs = setmetatable({}, { __mode = "k" })
function NR.Thumb(bar) return NR.thumbs[bar] end
local function scrollBar(Kit, bar)
    local S = Kit.SCROLL
    for _, r in ipairs({ bar:GetRegions() }) do Kit.Erase(r) end
    for _, r in ipairs({ bar.thumb:GetRegions() }) do Kit.Erase(r) end
    local W = DUI.Widgets
    local line = W.Round(bar, "BACKGROUND")
    line:SetWidth(S.width)
    line:SetPoint("TOP", bar, "TOP", 0, 0)
    line:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    W.Tint(line, S.track)
    local p = W.Round(bar.thumb, "ARTWORK")
    p:SetWidth(S.width)
    p:SetPoint("TOP", bar.thumb, "TOP", 0, 0)
    p:SetPoint("BOTTOM", bar.thumb, "BOTTOM", 0, 0)
    W.Tint(p, S.thumb)
    NR.thumbs[bar] = p
    bar.thumb:HookScript("OnEnter", function() W.Tint(p, S.thumbHover) end)
    bar.thumb:HookScript("OnLeave", function() W.Tint(p, S.thumb) end)
end

-- Its rounded boxes in the Native look (Theme:Dialog, Theme:Menu) get our shell.
NR.fills = setmetatable({}, { __mode = "k" })
function NR.Fill(f) return NR.fills[f] end
local function rounded(Kit, f)
    Kit.Erase(f.bg)
    Kit.Erase(f.border)
    -- A quest card on a questline page (NewCard): a soft lifted block without
    -- a box, since a page holds many.
    if kind(f.giver) == "FontString" then
        local fill = DUI.Widgets.Round(f, "BACKGROUND")
        fill:SetAllPoints(f)
        DUI.Widgets.Tint(fill, NR.CARD)
        NR.fills[f] = fill
        Kit.HoverWash(f)
        return
    end
    Kit.Shell(f, kind(f) == "Button" and "control" or "window")
end

-- Its pane (Theme:CreatePanel): parchment removed, our inset. A pane it shows
-- unframed (nested in another pane, parchment hidden) stays clear.
local function pane(Kit, f)
    if f.parchment:IsShown() then Kit.Inset(f) else Kit.Erase(f.parchment) end
end

-- Its gold accents ------------------------------------------------------
-- Lines become our faint rule, the open section's card a soft lifted block, and
-- underlines and the picked word of its toggles the accent.
NR.RULE = { 1, 1, 1, 0.06 }
NR.ruled = setmetatable({}, { __mode = "k" }) -- lines and dividers already converted

local function rule(tex)
    if kind(tex) ~= "Texture" then return end
    tex:SetColorTexture(1, 1, 1, 1)
    DUI.Widgets.Tint(tex, NR.RULE)
    NR.ruled[tex] = true
end

-- Theme:Divider: a 1 px frame of two gradients fading out from the middle.
local function divider(d)
    if kind(d) ~= "Frame" or NR.ruled[d] then return end
    local parts = {}
    for _, r in ipairs({ d:GetRegions() }) do if kind(r) == "Texture" then parts[#parts + 1] = r end end
    if #parts ~= 2 then return end
    local c = NR.RULE
    local mid, clear = CreateColor(c[1], c[2], c[3], c[4]), CreateColor(c[1], c[2], c[3], 0)
    parts[1]:SetGradient("HORIZONTAL", clear, mid)
    parts[2]:SetGradient("HORIZONTAL", mid, clear)
    NR.ruled[d] = true
end

-- Its section cards (Theme:SectionCard: textures laid out on a pane and redrawn
-- on each refresh and scroll) are erased, and our own card (faint fill, no
-- outline) covers the same area, re-laid out after each of its draws.
NR.cards = setmetatable({}, { __mode = "k" }) -- its card (table or canvas) -> ours
function NR.CardOf(key) return NR.cards[key] end

local function syncCard(Kit, key, parent, textures)
    local c = NR.cards[key]
    if not c then
        c = CreateFrame("Frame", nil, parent)
        c:EnableMouse(false)
        c:SetAlpha(0)
        c.fill = DUI.Widgets.Round(c, "BACKGROUND", -3)
        c.fill:SetAllPoints(c)
        DUI.Widgets.Tint(c.fill, NR.CARD)
        NR.cards[key] = c
    end
    local l, t, r, b
    for _, tex in ipairs(textures) do
        Kit.Erase(tex)
        if tex:IsShown() then
            local tl, tt, tr, tb = tex:GetLeft(), tex:GetTop(), tex:GetRight(), tex:GetBottom()
            if tl and tt and tr and tb then
                l, t = l and math.min(l, tl) or tl, t and math.max(t, tt) or tt
                r, b = r and math.max(r, tr) or tr, b and math.min(b, tb) or tb
            end
        end
    end
    local pl, pt = parent:GetLeft(), parent:GetTop()
    if l and pl and pt and r > l and t > b then
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", parent, "TOPLEFT", l - pl, t - pt)
        c:SetSize(r - l, t - b)
        if not c.on then
            c.on = true
            DUI.Motion.Fade(c, c:GetAlpha(), 1, DUI.Motion.FAST)
        end
    elseif c.on then
        c.on = false
        DUI.Motion.Fade(c, c:GetAlpha(), 0, DUI.Motion.FAST)
    end
end

local function cardOf(t)
    return isTable(t) and not t.GetObjectType and type(t.all) == "table" and type(t.Draw) == "function"
        and type(t.Hide) == "function" and kind(t.all[1]) == "Texture"
end
local hookedCards = setmetatable({}, { __mode = "k" })
local function cardTable(Kit, card)
    if hookedCards[card] then return end
    hookedCards[card] = true
    local parent = card.all[1]:GetParent()
    local function sync() syncCard(Kit, card, parent, card.all) end
    hooksecurefunc(card, "Draw", Engine.Safe(NR.def, sync))
    hooksecurefunc(card, "Hide", Engine.Safe(NR.def, sync))
    sync()
end

-- A list pane (CreateList): its section card lives on its canvas and is drawn
-- in Refresh; every texture on the canvas belongs to that card.
local function listPane(Kit, pane)
    local canvas = pane.canvas
    local function sync()
        local texs = {}
        for _, r in ipairs({ canvas:GetRegions() }) do
            if kind(r) == "Texture" then texs[#texs + 1] = r end
        end
        if #texs > 0 then syncCard(Kit, canvas, canvas, texs) end
        -- Rows it just recolored while filling them get ours in the same frame.
        for _, r in ipairs({ canvas:GetChildren() }) do
            if r:IsShown() then
                Kit.InkGameText(r)
                NR.Ink(r)
                if isTable(r.marker) then NR.Marker(r.marker) end
                if isTable(r.arrow) and type(r.arrow.SetOpen) == "function" then NR.Arrow(r.arrow) end
            end
        end
    end
    hooksecurefunc(pane, "Refresh", Engine.Safe(NR.def, sync))
    sync()
end

-- A list marker (Level 20): its two gold lines become our rule.
function NR.Marker(m)
    rule(m.left)
    rule(m.right)
end

-- Theme:ChipUnderline: recolored to the accent after each of its Set calls.
local function chipLines(lines)
    hooksecurefunc(lines, "Set", Engine.Safe(NR.def, function(self, _, alpha)
        local r, g, b = Style.Accent()
        local a = type(alpha) == "number" and alpha or 1
        self[1]:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, a))
        self[2]:SetVertexColor(r, g, b, a)
        self[3]:SetGradient("HORIZONTAL", CreateColor(r, g, b, a), CreateColor(r, g, b, 0))
    end))
end

-- Theme:LabelToggle (Overview / Details): our tab text, the picked one and its
-- underline in the accent, the others dim. Reapplied after each SetActive.
local function labelToggle(bar)
    local function paint()
        local r, g, b = Style.Accent()
        for _, btn in pairs(bar.buttons) do
            if kind(btn.text) == "FontString" then Style.InkText(btn.text, btn.active and "pop" or "OFF") end
            if kind(btn.underline) == "Frame" then
                local parts = { btn.underline:GetRegions() }
                local solid, clear = CreateColor(r, g, b, 1), CreateColor(r, g, b, 0)
                if kind(parts[1]) == "Texture" then parts[1]:SetGradient("HORIZONTAL", clear, solid) end
                if kind(parts[2]) == "Texture" then parts[2]:SetGradient("HORIZONTAL", solid, clear) end
                if kind(parts[3]) == "Texture" then parts[3]:SetColorTexture(r, g, b, 1) end
            end
        end
    end
    hooksecurefunc(bar, "SetActive", Engine.Safe(NR.def, paint))
    paint()
end

-- Theme:CardBackdrop (a recipe's Creates / Learned from / Materials, a boss
-- ability): its dark fill stays and its gold outline (a child of the holder,
-- above the box) goes. The fill becomes the box.
local function recipeBox(Kit, box)
    for _, holder in ipairs({ box:GetChildren() }) do
        for _, outline in ipairs({ holder:GetChildren() }) do
            for _, r in ipairs({ outline:GetRegions() }) do Kit.Erase(r) end
        end
    end
end

-- Theme:StatBackdrop (native): a wash, then a 1 px gold rule down its left.
local function statRule(f)
    local a, b = f:GetRegions()
    if kind(a) == "Texture" and kind(b) == "Texture" and select("#", f:GetRegions()) == 2
        and a:GetDrawLayer() == "BACKGROUND" and b:GetDrawLayer() == "BORDER" and b:GetWidth() == 1 then
        rule(b)
    end
end

-- Its top tabs (CreateNativeTab, PanelTopTabButtonTemplate) become our text tabs,
-- selected per tab.active. The game sizes each to its font and raises the picked
-- one's text; ours are as wide as the text and level.
NR.tabs = setmetatable({}, { __mode = "k" })
NR.TAB_PAD = 28
local function fitTab(Kit, tab)
    local text = tab.Text
    Kit.Refont(text)
    text:ClearAllPoints()
    text:SetPoint("CENTER", tab, "CENTER", 0, 1)
    text:SetWidth(0)
    tab:SetWidth(text:GetStringWidth() + NR.TAB_PAD)
    local t = Kit.TabOf(tab)
    if isTable(t) and t.picked and t.line then t.line:SetWidth(tab:GetWidth()) end
end
local function topTab(Kit, tab)
    if NR.tabs[tab] then return end
    NR.tabs[tab] = true
    Kit.Tab(tab, function(t) return t.active == true end)
    local t = Kit.TabOf(tab)
    hooksecurefunc(tab, "SetActive", Engine.Safe(NR.def, function(_, on)
        fitTab(Kit, tab)
        if isTable(t) and t.Pick then t.Pick(on == true, tab:IsMouseOver() == true) end
    end))
    fitTab(Kit, tab)
    if isTable(t) and t.Pick then t.Pick(tab.active == true) end
end

-- A heading's long rule (Overview's Description): its gold becomes our faint
-- rule after each SetColor.
local function headingRule(f)
    local function paint()
        local c = NR.RULE
        local solid, clear = CreateColor(c[1], c[2], c[3], c[4]), CreateColor(c[1], c[2], c[3], 0)
        f.solid:SetColorTexture(c[1], c[2], c[3], c[4])
        f.fadeIn:SetGradient("HORIZONTAL", clear, solid)
        f.fadeOut:SetGradient("HORIZONTAL", solid, clear)
    end
    hooksecurefunc(f, "SetColor", Engine.Safe(NR.def, paint))
    paint()
end

-- Theme:Arrow (a fold chevron, a +): gold strokes become our label ink.
NR.arrows = setmetatable({}, { __mode = "k" })
function NR.Arrow(f)
    if NR.arrows[f] then return end
    NR.arrows[f] = true
    local c = Style.INK.LABEL
    local function paint()
        for _, r in ipairs({ f:GetRegions() }) do
            if kind(r) == "Texture" and isTable(f.bars) then
                r:SetColorTexture(c[1], c[2], c[3], 1)
            elseif kind(r) == "Texture" then
                r:SetDesaturated(true)
                r:SetVertexColor(c[1], c[2], c[3], 1)
            end
        end
    end
    hooksecurefunc(f, "SetOpen", Engine.Safe(NR.def, paint))
    paint()
end

-- A click or wheel in its window means it may have filled something, so re-pass.
local heard = setmetatable({}, { __mode = "k" })
local function again() if NR.def.again then NR.def.again() end end

function NR.Ink(f)
    for _, r in ipairs({ f:GetRegions() }) do
        if kind(r) == "FontString" then inkText(r) end
    end
end

-- Every non-control frame Kit.Auto visits in its window.
function NR.Each(f)
    local Kit = ns.Kit
    local was = dressed[f]
    if kind(f.left) == "Texture" and kind(f.right) == "Texture" and kind(f.text) == "FontString" then
        NR.Marker(f)
    end
    if not was then
        for _, c in ipairs({ f:GetChildren() }) do
            if kind(c) == "Button" and c.key ~= nil and type(c.SetActive) == "function" and kind(c.Text) == "FontString" then
                topTab(Kit, c)
            end
        end
        if type(f.SetOpen) == "function" then NR.Arrow(f) end
        if kind(f.fadeIn) == "Texture" and type(f.SetColor) == "function" then headingRule(f) end
        -- Gold accents on whatever holds them.
        for _, key in ipairs({ "card", "edge" }) do
            if cardOf(f[key]) then cardTable(Kit, f[key]) end
        end
        -- Only CreateList's panes (with label and rule). Other pages with a
        -- canvas (Overview) draw their art on it.
        if type(f.Refresh) == "function" and kind(f.canvas) == "Frame" and kind(f.label) == "FontString"
            and kind(f.rule) == "Texture" then
            listPane(Kit, f)
        end
        if kind(f.rule) == "Texture" then rule(f.rule) end
        divider(f.divider)
        divider(f.rule)
        if isTable(f.lines) and type(f.lines.Set) == "function" and kind(f.lines[2]) == "Texture" then chipLines(f.lines) end
        if isTable(f.buttons) and type(f.SetActive) == "function" then labelToggle(f) end
        if kind(f.strip) == "Frame" then
            for _, r in ipairs({ f.strip:GetRegions() }) do
                if kind(r) == "Texture" and r:GetDrawLayer() == "BORDER" then rule(r) end
            end
        end
        statRule(f)
        if rowOf(f) then
            dressed[f] = "row"; row(Kit, f)
        elseif pillOf(f) then
            dressed[f] = "pill"; pill(Kit, f)
        elseif barOf(f) then
            dressed[f] = "bar"; scrollBar(Kit, f)
        elseif roundedOf(f) then
            dressed[f] = "rounded"; rounded(Kit, f)
        elseif type(f.FitCard) == "function" then
            dressed[f] = "recipe"; recipeBox(Kit, f)
        elseif kind(f.parchment) == "Texture" then
            dressed[f] = "pane"; pane(Kit, f)
        else
            dressed[f] = true
        end
        local t = kind(f)
        if not heard[f] and (t == "Button" or t == "CheckButton") then
            heard[f] = true
            f:HookScript("OnClick", function()
                Kit.RepaintSoon()
                C_Timer.After(0, again)
            end)
        elseif not heard[f] and f.GetScript and f:GetScript("OnMouseWheel") then
            heard[f] = true
            f:HookScript("OnMouseWheel", function() C_Timer.After(0, again) end)
        end
    elseif was == "row" then
        Kit.RepaintRow(f)
        paintHeader(f)
    end
    if dressed[f] == "row" then header(Kit, f) end
    if was ~= "pill" then NR.Ink(f) end
end

-- A failure on one frame (its frames change between versions) skips only that frame.
local function each(f)
    local ok, err = pcall(NR.Each, f)
    if not ok and C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DaylightUI_Dev") then
        geterrorhandler()(err)
    end
end

-- Its title: its own (icon and name centered in a holder over the emptied
-- template title) is hidden, and the name goes in the template's title, which
-- our window places on the left like our headers.
local function title(Kit, f)
    local tc = isTable(f.TitleContainer) and f.TitleContainer or f
    local text = isTable(f.TitleContainer) and f.TitleContainer.TitleText or f.TitleText
    if kind(text) ~= "FontString" then return end
    for _, c in ipairs({ tc:GetChildren() }) do
        for _, r in ipairs({ c:GetRegions() }) do
            if kind(r) == "FontString" and r:GetText() == ADDON then
                Kit.Hide(c)
                text:SetText(ADDON)
            end
        end
    end
end

NR.def = { key = "needroll", pack = "addons", addon = ADDON, switch = "needroll", label = "NeedRoll",
    thirdParty = true, frame = FRAME, watch = true, auto = { each = each, depth = NR.DEPTH } }
NR.def.after = function(Kit, f) title(Kit, f) end
NR.reg = Engine.Window(NR.def)

-- Its fonts: ours as soon as it loads, and again on style changes.
NR.fonts = { key = "needrollFonts", pack = "addons", addon = ADDON, switch = "needroll", label = "NeedRoll",
    thirdParty = true, apply = function() NR.Fonts() end }
Engine.Register(NR.fonts)
DUI.On("StyleChanged", Engine.Safe(NR.fonts, function() if NR.fonts.done then NR.Fonts() end end))

-- Dresses its window once it exists (the skin was waiting for it).
function NR.Look()
    if NR.reg.done or not _G[FRAME] then return end
    Engine.Try(NR.reg)
end
local function soon() C_Timer.After(0, NR.Look) end
local hooked = false
local function hookOpeners()
    if hooked or not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDON)) then return end
    hooked = true
    for _, name in ipairs({ "NeedRoll_OnCompartmentClick", "NeedRoll_ShowLoot", "NeedRoll_ShowMap",
        "NeedRoll_ShowQuest", "NeedRoll_ShowItem", "NeedRoll_ShowProfession", "NeedRoll_ShowFaction" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, soon) end
    end
    if type(SlashCmdList) == "table" and type(SlashCmdList.NEEDROLL) == "function" then
        hooksecurefunc(SlashCmdList, "NEEDROLL", soon)
    end
    -- Its minimap button and links from other windows (the world map's): watch
    -- the first clicks until the window is dressed, then stop listening. Not
    -- while it can't be dressed: skin off or broken, or NeedRoll set to Modern
    -- (its saved `skin`; the Native window is only created once that's picked,
    -- and a later click finds it).
    local clicks = CreateFrame("Frame")
    clicks:RegisterEvent("GLOBAL_MOUSE_UP")
    clicks:SetScript("OnEvent", function(self)
        if NR.reg.done then return self:UnregisterEvent("GLOBAL_MOUSE_UP") end
        if NR.def.broken or not Engine.Wanted(NR.reg) then return end
        local saved = _G.NeedRollDB
        if type(saved) == "table" and saved.skin == "modern" then return end
        soon()
    end)
end
hookOpeners()
DUI.RegisterEvent("ADDON_LOADED", function(_, name) if name == ADDON then hookOpeners() end end)
