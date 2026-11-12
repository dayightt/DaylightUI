-- Skins Attune (attunement and quest chains for Forever): its window and quest
-- side panels get our look, and each chain is drawn like the talent and Legacy
-- trees. Every step is a dark tile with the talent ring (gold = done, accent =
-- next or in progress, dark = locked), its icon cropped and grayed while
-- locked. Lines between steps are talent arrows (gold out of a done step,
-- accent into the next, dark otherwise) with a chevron where they enter a step.
-- A step completed since the last draw flashes like a talent being filled.
--
-- What Attune builds (Attune.lua, 16001-34): its window is an AceGUI Frame
-- (dressed by the Ace3 skin) under a PortraitFrameTemplate "AttuneBronzeChrome",
-- created in the global Attune_Frame. The global Attune_Select draws a chain.
-- Each step is a BackdropTemplate button "Attune_Node_<id>" (from the global
-- Attune_CreateNode) holding "Attune_Icon_<id>", "Attune_Title_<id>",
-- "Attune_Type_<id>", and lines on the node ("Attune_Line1/2/3_<id>_<from>",
-- where Line3 runs into its top; "Attune_SpacerFill_<id>",
-- "Attune_SideFeeder_<id>"), plus an "Inside the dungeon" box "Attune_SideBox".
-- A step's state exists only as the backdrop color it's given (green done,
-- yellow next, gray locked, red/blue the goal), and a line's as its draw
-- sublevel (2 done, 1 ready, 0 not), so both are read back after each draw.
-- Quest panels: "AttuneQuestDetail" (Attune_ShowQuestDetail) and
-- "AttuneQuestRewardFrame" under a ButtonFrameTemplate (Attune_ShowQuestRewards).

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style = DUI.Style
local Motion = DUI.Motion

local ADDON = "Attune"

Engine.AddonSwitch({ key = "attune", addon = ADDON, label = "Attune",
    desc = "Its window, and each attunement chain drawn like the talent trees." })

local function isTable(x) return type(x) == "table" end
local function kind(x) return isTable(x) and x.GetObjectType and x:GetObjectType() or nil end

local AT = {
    NODE = "^Attune_Node_",
    GOAL = { 0.557, 0.055 }, -- red and blue backdrops mark the goal; matched by red
    DONE = { 0.373, 0.055 }, -- green (a step) or blue (the goal) = done
    NEXT = 0.851, -- yellow = next step, or in progress
}
ns.Attune = AT
AT.tiles = setmetatable({}, { __mode = "k" }) -- node -> our pieces on it
AT.state = {} -- node name -> its state at the last draw
AT.boxes = setmetatable({}, { __mode = "k" }) -- frames already given our shell

local function talents() return DUI.Book and DUI.Book.Talents end
local function arrows() return DUI.Book and DUI.Book.Arrows end
local function hex(c) return DUI.Win.Parts.Hex(c) end

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.02 end

-- "done" | "next" | "goal" | "locked" | "spacer", from the step's backdrop color.
function AT.StateOf(node)
    if type(node.GetBackdropColor) ~= "function" then return "locked" end
    local r, g, _, a = node:GetBackdropColor()
    if type(r) ~= "number" or (issecretvalue and issecretvalue(r)) then return "locked" end
    if a == 0 then return "spacer" end
    if near(r, AT.DONE[1]) or (near(r, AT.DONE[2]) and near(g, 0.306)) then return "done" end
    if near(r, AT.NEXT) then return "next" end
    if near(r, AT.GOAL[1]) then return "goal" end
    return "locked"
end

local function tex(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    return t
end

local function tileOf(node)
    local t = AT.tiles[node]
    if t then return t end
    local TL = talents()
    local r = TL.RING
    t = {}
    t.ring = tex(node, "BACKGROUND", -2)
    t.ring:SetPoint("TOPLEFT", node, "TOPLEFT", -r, r)
    t.ring:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", r, -r)
    t.well = tex(node, "BACKGROUND", -1)
    t.well:SetPoint("TOPLEFT", node, "TOPLEFT", -1, 1)
    t.well:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 1, -1)
    t.well:SetVertexColor(0.02, 0.02, 0.025, 1)
    t.iconWell = tex(node, "BACKGROUND", 2)
    t.iconWell:SetVertexColor(0, 0, 0, 1)
    t.flash = tex(node, "OVERLAY", 6)
    t.flash:SetPoint("TOPLEFT", node, "TOPLEFT", -r, r)
    t.flash:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", r, -r)
    t.flash:SetBlendMode("ADD")
    local w = TL.WAKE
    t.flash:SetVertexColor(w[1], w[2], w[3], 0.55)
    t.flash:Hide()
    local A = arrows()
    t.head = node:CreateTexture(nil, "OVERLAY", nil, 5)
    t.head:SetTexture(A.CHEVRON)
    t.head:SetSize(A.HEAD, A.HEAD)
    t.head:SetPoint("BOTTOM", node, "TOP", 0, r - 1)
    t.head:Hide()
    -- On hover the ring gets a step lighter, like a talent icon.
    node:HookScript("OnEnter", function() t.over = true; AT.PaintTile(node) end)
    node:HookScript("OnLeave", function() t.over = nil; AT.PaintTile(node) end)
    AT.tiles[node] = t
    return t
end

-- Line color by level: 2 done, 1 ready, 0 not.
local function lineColor(level)
    if level >= 2 then return talents().FULL end
    if level == 1 then return { Style.Accent() } end
    return arrows().OFF
end

local function lineLevel(line)
    local _, sub = line:GetDrawLayer()
    return type(sub) == "number" and sub or 0
end

function AT.PaintTile(node)
    local t = AT.tiles[node]
    if not t or not t.state then return end
    local TL = talents()
    local state = t.state
    local ring
    if state == "done" then ring = TL.FULL
    elseif state == "next" then ring = { Style.Accent() }
    elseif state == "goal" then ring = TL.AVAIL
    else ring = TL.LOCKED end
    if t.over and (state == "goal" or state == "locked") then ring = TL.AVAIL end
    t.ring:SetVertexColor(ring[1], ring[2], ring[3], 1)
    local icon = t.icon
    if icon then
        local light = t.over and 1 or (state == "locked" and 0.36) or (state == "goal" and TL.AVAIL_LIGHT) or 1
        icon:SetDesaturated(state == "locked")
        icon:SetVertexColor(light, light, light, 1)
    end
end

-- Rewrites the type line's color codes (yellow, translucent gray) to our ink.
local function inkRuns(fs)
    local text = fs:GetText()
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
    local INK = Style.INK
    local new = text:gsub("|c[fF][fF][fF][fF][dD]100", hex(INK.LABEL)):gsub("|c%x%x808080", hex(INK.OFF))
    if new ~= text then fs:SetText(new) end
end

local function words(id, state)
    local INK = Style.INK
    local title, kindLine = _G["Attune_Title_" .. id], _G["Attune_Type_" .. id]
    if kind(title) == "FontString" then
        local goal = kind(kindLine) ~= "FontString" or not kindLine:IsShown()
        Style.DressText(title, goal and Style.SIZE.body or Style.SIZE.small, { slot = Style.WINDOW_SLOT })
        local c = state == "locked" and INK.OFF or state == "next" and INK.VALUE or INK.TEXT
        if goal then c = state == "done" and INK.GOOD or INK.LABEL end
        title:SetTextColor(c[1], c[2], c[3], 1)
    end
    if kind(kindLine) == "FontString" and kindLine:IsShown() then
        Style.DressText(kindLine, Style.SIZE.tiny, { slot = Style.WINDOW_SLOT })
        inkRuns(kindLine)
    end
    local count = _G["Attune_NotifText_" .. id]
    if kind(count) == "FontString" then
        Style.DressText(count, Style.SIZE.tiny, { slot = Style.WINDOW_SLOT })
        Style.InkText(count, "pop")
    end
end

-- One step, after it's drawn: backdrop hidden, our tile, our lines.
function AT.Dress(node)
    local name = node:GetName()
    local id = type(name) == "string" and name:match(AT.NODE .. "(.+)$")
    if not id then return end
    ns.Kit.Backdrop(node)
    local state = AT.StateOf(node)
    local t = tileOf(node)
    local was = AT.state[name]
    AT.state[name] = state
    t.state = state
    local box = state ~= "spacer"
    t.ring:SetShown(box)
    t.well:SetShown(box)
    local iconButton = _G["Attune_Icon_" .. id]
    local icon = isTable(iconButton) and iconButton.GetNormalTexture and iconButton:GetNormalTexture()
    t.icon = kind(icon) == "Texture" and icon or nil
    if t.icon and box then
        Style.CropIcon(t.icon)
        ns.Kit.Hide(iconButton:GetHighlightTexture())
        t.iconWell:ClearAllPoints()
        t.iconWell:SetPoint("TOPLEFT", iconButton, "TOPLEFT", -1, 1)
        t.iconWell:SetPoint("BOTTOMRIGHT", iconButton, "BOTTOMRIGHT", 1, -1)
        t.iconWell:Show()
    else
        t.iconWell:Hide()
    end
    if box then
        AT.PaintTile(node)
        words(id, state)
    end
    -- Lines: arrow width and colors, with a chevron where they come in.
    local width = arrows().WIDTH
    local into = -1
    for _, r in ipairs({ node:GetRegions() }) do
        if kind(r) == "Line" and r:IsShown() then
            local level = lineLevel(r)
            local c = lineColor(level)
            r:SetColorTexture(c[1], c[2], c[3], 1)
            r:SetThickness(width)
            local n = r:GetName()
            if type(n) == "string" and n:find("^Attune_Line3_") and level > into then into = level end
        end
    end
    if into >= 0 and box then
        local c = lineColor(into)
        t.head:SetVertexColor(c[1], c[2], c[3], 1)
        t.head:Show()
    else
        t.head:Hide()
    end
    -- Completed since the last draw: the talent flash as the ring closes.
    if box and state == "done" and was ~= nil and was ~= "done" then Motion.Flash(t.flash, Motion.SLOW) end
end

-- The whole chain, after Attune_Select has drawn it.
function AT.Chain(attuneId)
    local root = _G.Attune_GraphRoot
    if not isTable(root) then return end
    for _, c in ipairs({ root:GetChildren() }) do
        local n = c.GetName and c:GetName()
        if type(n) == "string" and n:find(AT.NODE) and c:IsShown() then AT.Dress(c) end
    end
    local side = _G.Attune_SideBox
    if isTable(side) and side:IsShown() then
        ns.Kit.Backdrop(side)
        if not AT.boxes[side] then
            AT.boxes[side] = true
            ns.Kit.Shell(side, "row", { noBackground = true })
        end
    end
    local sideTitle = _G.Attune_SideBoxTitle
    if kind(sideTitle) == "FontString" then
        Style.DressText(sideTitle, Style.SIZE.small, { slot = Style.WINDOW_SLOT })
        inkRuns(sideTitle)
    end
    -- A different chain was picked, so it eases in like our pages.
    if attuneId ~= AT.shown then
        AT.shown = attuneId
        Motion.FadeIn(root)
    end
end

-- The window: our border instead of the bronze one, its game controls ours.
function AT.Window()
    local Kit = ns.Kit
    local chrome = _G.AttuneBronzeChrome
    if isTable(chrome) then
        Kit.GHOST.AttuneBronzeChrome = true -- the AceGUI window under it leaves the ghost
        Kit.Window(chrome)
        local host = chrome:GetParent()
        if isTable(host) then Kit.Auto(host, { controlsOnly = true }) end
    end
end

local function textOf(f, key, size, color)
    if kind(f[key]) ~= "FontString" then return end
    ns.Kit.Font(f[key], size)
    ns.Kit.Light(f[key], color)
end

-- Quest panels: our window look, X, buttons and ink.
function AT.Panels()
    local Kit, INK, SIZE = ns.Kit, Style.INK, Style.SIZE
    local detail = _G.AttuneQuestDetail
    if isTable(detail) then
        Kit.Backdrop(detail)
        if not AT.boxes[detail] then
            AT.boxes[detail] = true
            Kit.Shell(detail, "window")
            if isTable(detail.map) then
                Kit.Backdrop(detail.map)
                Kit.Shell(detail.map, "row", { noBackground = true })
            end
            if kind(detail.separator) == "Texture" then DUI.Widgets.Tint(detail.separator, { 1, 1, 1, 0.06 }) end
            Kit.Auto(detail, { controlsOnly = true })
        end
        textOf(detail, "title", SIZE.head, INK.VALUE)
        textOf(detail, "subtitle", SIZE.small, INK.LABEL)
        textOf(detail, "empty", SIZE.body, INK.LABEL)
        if kind(detail.xpText) == "FontString" then Kit.Font(detail.xpText); Style.InkText(detail.xpText, "pop") end
    end
    local rewards = _G.AttuneQuestRewardFrame
    if isTable(rewards) then
        if not AT.boxes[rewards] then
            AT.boxes[rewards] = true
            Kit.Backdrop(rewards)
            if isTable(rewards.bronze) then
                Kit.Window(rewards.bronze)
            else
                Kit.Shell(rewards, "window")
            end
            Kit.Button(rewards.urlBtn)
            Kit.Auto(rewards, { controlsOnly = true })
        end
        textOf(rewards, "title", SIZE.head, INK.VALUE)
        textOf(rewards, "empty", SIZE.body, INK.LABEL)
    end
end

-- Style changed: redo every shown step. Goes through the skin's own guard, so a
-- broken or disabled skin stops this too.
function AT.Restyle()
    for node in pairs(AT.tiles) do
        if node:IsShown() then AT.Dress(node) end
    end
end

Engine.Register({ key = "attune", pack = "addons", addon = ADDON, switch = "attune", label = "Attune",
    thirdParty = true, apply = function(_, def)
    if type(_G.Attune_Select) ~= "function" or type(_G.Attune_CreateNode) ~= "function" or not talents() then
        return false
    end
    AT.def = def
    hooksecurefunc("Attune_Select", Engine.Safe(def, AT.Chain))
    if type(_G.Attune_Frame) == "function" then hooksecurefunc("Attune_Frame", Engine.Safe(def, AT.Window)) end
    for _, name in ipairs({ "Attune_ShowQuestDetail", "Attune_ShowQuestRewards" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, Engine.Safe(def, AT.Panels)) end
    end
    DUI.On("StyleChanged", Engine.Safe(def, AT.Restyle))
    -- Opened before the skin started (it reopens at login if left open).
    AT.Window()
    AT.Chain(AT.shown)
end })
