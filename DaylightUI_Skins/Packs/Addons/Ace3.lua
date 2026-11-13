-- Skins AceGUI-3.0 widgets. That covers most addons' options windows
-- (AceConfigDialog builds them from AceGUI: Questie, RestedXP...), their own
-- AceGUI windows (Questie's My Journey), and their pages in the game's settings.
--
-- How it works (AceGUI-3.0.lua, minor 41): every widget constructor ends with
-- AceGUI:RegisterAsWidget(widget) or RegisterAsContainer(widget), with
-- widget.type already set. Widgets are pooled (Release / Create), so each is
-- dressed once when first made. Later changes on a reused widget (a checkbox's
-- value, a tree's buttons, a tab group's tabs) are followed by post-hooks on
-- that widget's own methods, since each instance carries its own copies. Only
-- post-hooks, and only on the library and its widgets, never on the game's code
-- (see tests/guards_allow.lua).
-- The hooks go in as soon as the library exists: when this file loads and after
-- every later addon load, because AceGUI is embedded in other addons and Questie
-- builds its options window while loading, before our settings can be read.
-- Widgets made before the skin is switched on wait in a list, which is dropped
-- if it's switched off. A newer copy of the library loaded later replaces the
-- hooked functions, so they get hooked again.
-- Widget types added by other addons (Questie's GameTooltipWidget) aren't dressed.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local Engine = ns.Engine

local function ace() return LibStub and LibStub("AceGUI-3.0", true) end

Engine.AddonSwitch({ key = "ace3", label = "Addon options (Ace3)", present = function() return ace() ~= nil end,
    desc = "Options windows of addons built on Ace3, in the game's settings and their own windows: Questie, RestedXP and many more." })

local function isTable(x) return type(x) == "table" end
local function kind(x) return isTable(x) and x.GetObjectType and x:GetObjectType() or nil end

local Ace = {}
ns.Ace3 = Ace
Ace.waiting = setmetatable({}, { __mode = "k" }) -- widgets made before the skin started
Ace.dressed = setmetatable({}, { __mode = "k" })
Ace.headings = setmetatable({}, { __mode = "k" }) -- heading label -> true (repainted with the accent)
Ace.washes = setmetatable({}, { __mode = "k" }) -- tree button highlight -> true (accent)
Ace.switchOf = setmetatable({}, { __mode = "k" }) -- checkbox widget -> its switch look
local def -- the skin def, once it runs

-- ---------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------

-- A label above a control (edit box, slider): tan, dim while the control is
-- disabled. AceGUI resets its colors on enable/disable.
local function label(Kit, w, fs)
    if kind(fs) ~= "FontString" then return end
    Kit.Font(fs)
    local function paint()
        Kit.Light(fs, w.disabled and Style.INK.OFF or Kit.DIM)
    end
    paint()
    if type(w.SetDisabled) == "function" then hooksecurefunc(w, "SetDisabled", Engine.Safe(def, paint)) end
end

-- A pane inside a window (a tree's list, a group's box): quiet outline,
-- backdrop removed.
local function pane(Kit, f)
    if not isTable(f) or not f.CreateTexture then return end
    Kit.Backdrop(f)
    Kit.Shell(f, "row", { noBackground = true })
end

-- A box with a dropdown arrow on its right (Ace's dropdown, a SharedMedia
-- picker): the input look on our own frame over the control, our chevron,
-- lighter on hover.
local function dropBox(Kit, frame, arrow, hovers)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetPoint("LEFT", frame, "LEFT", 0, 0)
    holder:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    holder:SetPoint("TOP", arrow, "TOP", 0, 1)
    holder:SetPoint("BOTTOM", arrow, "BOTTOM", 0, -1)
    holder:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
    holder:EnableMouse(false)
    local s = Kit.Shell(holder, "input")
    Kit.BareButton(arrow, "down")
    for _, h in ipairs(hovers) do
        if isTable(h) and h.HookScript then
            h:HookScript("OnEnter", function() Kit.Paint(s, Kit.ROW_HOVER) end)
            h:HookScript("OnLeave", function() Kit.Paint(s, nil) end)
        end
    end
end

-- A window's plain text buttons (a Frame's Close, Questie's extras).
local function textButtons(Kit, f)
    for _, c in ipairs({ f:GetChildren() }) do
        if kind(c) == "Button" and kind(c.Left) == "Texture" and kind(c.Right) == "Texture" then Kit.Button(c) end
    end
end

local function title(Kit, f, fs)
    if kind(fs) ~= "FontString" then return end
    Kit.Font(fs, Style.SIZE.title)
    Kit.Light(fs, Style.INK.VALUE)
    Kit.Title(f, fs)
end

-- ---------------------------------------------------------------------
-- Widget types
-- ---------------------------------------------------------------------

local TYPES = {}

TYPES.Frame = function(Kit, w)
    local f = w.frame
    Kit.Window(f)
    title(Kit, f, w.titletext)
    textButtons(Kit, f)
    -- Addons add their own buttons after AceGUI creates the window (Questie's
    -- "My Journey" is built along with its options after login), so look for
    -- them again on every open.
    f:HookScript("OnShow", Engine.Safe(def, function() textButtons(Kit, f) end))
    local status = kind(w.statustext) == "FontString" and w.statustext:GetParent()
    if isTable(status) then
        Kit.Backdrop(status)
        Kit.Shell(status, "input")
        Kit.Font(w.statustext, Style.SIZE.small)
        Kit.Light(w.statustext, Kit.DIM)
    end
end

TYPES.Window = function(Kit, w)
    Kit.Window(w.frame)
    title(Kit, w.frame, w.titletext)
    Kit.Close(w.closebutton)
end

TYPES.Button = function(Kit, w) Kit.Button(w.frame) end

TYPES.CheckBox = function(Kit, w)
    local W = DUI.Widgets
    Kit.Hide(w.checkbg)
    Kit.Hide(w.check)
    Kit.Hide(w.highlight)
    if not isTable(w.checkbg) then return end
    -- Our switch replaces the box and follows its size (a radio's is smaller).
    local holder = CreateFrame("Frame", nil, w.frame)
    holder:SetAllPoints(w.checkbg)
    holder:EnableMouse(false)
    local bw = w.checkbg:GetWidth()
    if type(bw) ~= "number" or bw <= 0 then bw = 24 end
    local s = W.SwitchLook(holder, {}, math.max(Kit.CHECK_MIN, math.min(W.SWITCH_W, bw - Kit.CHECK_ROOM)))
    Ace.switchOf[w] = s
    local function paint()
        s.off = w.disabled and true or nil
        s.SetOn(w.checked == true)
    end
    paint()
    for _, m in ipairs({ "SetValue", "SetDisabled", "SetType", "SetTriState" }) do
        if type(w[m]) == "function" then hooksecurefunc(w, m, Engine.Safe(def, paint)) end
    end
    -- On click AceGUI sets checked, then notifies the addon.
    w.frame:HookScript("OnMouseUp", Engine.Safe(def, paint))
    Kit.Font(w.text)
end

TYPES.EditBox = function(Kit, w)
    Kit.EditBox(w.editbox)
    Kit.Button(w.button)
    label(Kit, w, w.label)
end

TYPES.MultiLineEditBox = function(Kit, w)
    if isTable(w.scrollBG) then
        Kit.Backdrop(w.scrollBG)
        Kit.Shell(w.scrollBG, "input")
    end
    Kit.ScrollBar(w.scrollBar)
    Kit.Button(w.button)
    Kit.Font(w.editBox)
    label(Kit, w, w.label)
end

TYPES.Dropdown = function(Kit, w)
    local dd = w.dropdown
    if not isTable(dd) or not isTable(w.button) then return end
    local name = dd.GetName and dd:GetName()
    for _, k in ipairs({ "Left", "Middle", "Right" }) do
        Kit.Hide(dd[k])
        if type(name) == "string" then Kit.Hide(_G[name .. k]) end
    end
    dropBox(Kit, w.frame, w.button, { w.button, w.button_cover })
    Kit.Font(w.text)
    label(Kit, w, w.label)
end

TYPES["Dropdown-Pullout"] = function(Kit, w)
    Kit.Backdrop(w.frame)
    Kit.Shell(w.frame, "window")
    if isTable(w.slider) then
        Kit.Backdrop(w.slider)
        Kit.ScrollThumb(w.slider)
    end
end

local function item(Kit, w)
    if kind(w.frame) ~= "Button" then return end
    Kit.Hide(w.highlight)
    Kit.HoverWash(w.frame)
    Kit.Font(w.text)
    if kind(w.line) == "Texture" then
        Style.Follow(w.line, Style.BORDER, 1, true)
    end
end

TYPES.Slider = function(Kit, w)
    local sl = w.slider
    if kind(sl) ~= "Slider" then return end
    Kit.Backdrop(sl)
    local look = DUI.Widgets.SliderLook(sl, {})
    local function fill()
        local lo, hi = sl:GetMinMaxValues()
        local v = sl:GetValue()
        if type(lo) == "number" and type(hi) == "number" and type(v) == "number" and hi > lo then
            look.Fill((v - lo) / (hi - lo))
        else
            look.Fill(0)
        end
    end
    fill()
    sl:HookScript("OnValueChanged", Engine.Safe(def, fill))
    sl:HookScript("OnSizeChanged", Engine.Safe(def, fill))
    sl:HookScript("OnShow", Engine.Safe(def, fill))
    if kind(w.editbox) == "EditBox" then
        Kit.Backdrop(w.editbox)
        Kit.EditBox(w.editbox)
    end
    for _, fs in ipairs({ w.lowtext, w.hightext }) do
        if kind(fs) == "FontString" then
            Kit.Font(fs, Style.SIZE.small)
            Kit.Light(fs, Kit.DIM)
        end
    end
    label(Kit, w, w.label)
end

-- Headings use the accent like list sections; their lines are a faint rule.
local function paintHeading(fs) Style.InkText(fs, "pop") end
TYPES.Heading = function(Kit, w)
    for _, line in ipairs({ w.left, w.right }) do
        if kind(line) == "Texture" then
            Style.Follow(line, Style.BORDER, 1, true)
            line:SetHeight(1)
        end
    end
    if kind(w.label) == "FontString" then
        Kit.Font(w.label)
        Ace.headings[w.label] = true
        paintHeading(w.label)
    end
end

TYPES.Label = function(Kit, w) Kit.Font(w.label) end
TYPES.Icon = function(Kit, w) Kit.Font(w.label) end
TYPES.ColorPicker = function(Kit, w) Kit.Font(w.text) end

TYPES.Keybinding = function(Kit, w)
    Kit.Button(w.button)
    if isTable(w.msgframe) then
        Kit.Backdrop(w.msgframe)
        Kit.Shell(w.msgframe, "window")
    end
    label(Kit, w, w.label)
end

-- Tree buttons: our font, accent wash for hover and for the picked one (AceGUI
-- locks the highlight on the picked one), our chevron for the +/-.
local PLUS = { [130838] = true, [130836] = true }
local function isPlus(tex)
    local t = kind(tex) == "Texture" and tex:GetTexture()
    if type(t) == "number" then return PLUS[t] == true end
    return type(t) == "string" and string.find(string.lower(t), "plus", 1, true) ~= nil
end
local function treeButton(Kit, b)
    if not isTable(b) then return end
    local t = Ace.dressed[b]
    if not t then
        t = {}
        Ace.dressed[b] = t
        Kit.Font(b.text)
        local hl = b.GetHighlightTexture and b:GetHighlightTexture()
        if kind(hl) == "Texture" then
            hl:SetTexture("Interface\\Buttons\\WHITE8X8")
            hl:SetTexCoord(0, 1, 0, 1)
            Style.PaintAccent(hl, 0.18)
            Ace.washes[hl] = true
        end
        if isTable(b.toggle) then t.chevron = Kit.BareButton(b.toggle, "right") end
    end
    local tg = b.toggle
    if t.chevron and isTable(tg) then
        local normal = tg.GetNormalTexture and tg:GetNormalTexture()
        Kit.Hide(normal)
        Kit.Hide(tg.GetPushedTexture and tg:GetPushedTexture())
        t.chevron:SetRotation(isPlus(normal) and Kit.ROTATION.right or Kit.ROTATION.down)
    end
end

TYPES.TreeGroup = function(Kit, w)
    pane(Kit, w.treeframe)
    pane(Kit, w.border)
    Kit.Backdrop(w.dragger)
    Kit.ScrollBar(w.scrollbar)
    local function buttons(self)
        for _, b in ipairs((self or w).buttons or {}) do treeButton(Kit, b) end
    end
    if type(w.RefreshTree) == "function" then hooksecurefunc(w, "RefreshTree", Engine.Safe(def, buttons)) end
    buttons(w)
end

local function tabSelected(tab) return tab.selected == true end
TYPES.TabGroup = function(Kit, w)
    pane(Kit, w.border)
    local function tabs(self)
        for _, tab in ipairs((self or w).tabs or {}) do Kit.Tab(tab, tabSelected) end
    end
    if type(w.BuildTabs) == "function" then hooksecurefunc(w, "BuildTabs", Engine.Safe(def, tabs)) end
    tabs(w)
    if kind(w.titletext) == "FontString" then Kit.Font(w.titletext); Kit.Light(w.titletext, Kit.HEADER) end
end

TYPES.InlineGroup = function(Kit, w)
    local border = isTable(w.content) and w.content:GetParent()
    if border and border ~= w.frame then pane(Kit, border) end
    if kind(w.titletext) == "FontString" then Kit.Font(w.titletext); Kit.Light(w.titletext, Kit.HEADER) end
end

TYPES.ScrollFrame = function(Kit, w) Kit.ScrollBar(w.scrollbar) end

TYPES.DropdownGroup = function(Kit, w)
    pane(Kit, w.border)
    if kind(w.titletext) == "FontString" then Kit.Font(w.titletext); Kit.Light(w.titletext, Kit.HEADER) end
end

TYPES.BlizOptionsGroup = function(Kit, w)
    if kind(w.label) == "FontString" then
        Kit.Font(w.label, Style.SIZE.title)
        Kit.Light(w.label, Style.INK.VALUE)
    end
end

-- SharedMedia pickers (AceGUI-3.0-SharedMediaWidgets, prototypes.lua
-- DataVersion 9004): the box and the list it opens. The list is a pooled frame
-- (GetDropDownFrame) assigned to w.dropdown when the arrow is clicked, filled
-- with pooled lines (contentRepo). A returned list gets its dialog backdrop
-- back (ReturnDropDownFrame), so it's removed again on every open. A font
-- picker shows each entry in its own font, and a border picker's backdrop
-- previews the hovered border, so those are left alone.
Ace.lists = setmetatable({}, { __mode = "k" }) -- open list frame -> true (dressed)
Ace.lines = setmetatable({}, { __mode = "k" }) -- list line -> true (dressed)

local function backdropAlpha(Kit, f, a)
    for _, key in ipairs(Kit.BACKDROP) do
        if kind(f[key]) == "Texture" then f[key]:SetAlpha(a) end
    end
end

local function openList(Kit, w)
    local d = w.dropdown
    if not isTable(d) or not d.CreateTexture then return end
    Kit.Backdrop(d)
    if not Ace.lists[d] then
        Ace.lists[d] = true
        Kit.Shell(d, "window")
        if isTable(d.slider) then
            Kit.Backdrop(d.slider)
            Kit.ScrollThumb(d.slider)
        end
    end
    local border = w.type == "LSM30_Border"
    for _, line in ipairs(type(d.contentRepo) == "table" and d.contentRepo or {}) do
        if kind(line) == "Button" and not Ace.lines[line] then
            Ace.lines[line] = true
            Kit.Hide(line.GetHighlightTexture and line:GetHighlightTexture())
            Kit.HoverWash(line)
            if border then
                -- Its own OnEnter puts the hovered border on the list; keep it.
                line:HookScript("OnEnter", Engine.Safe(def, function(self)
                    if isTable(self.dropdown) then backdropAlpha(Kit, self.dropdown, 1) end
                end))
            end
        end
    end
end

local function media(Kit, w)
    local f = w.frame
    if not isTable(f) or not isTable(f.dropButton) then return end
    for _, k in ipairs({ "DLeft", "DMiddle", "DRight" }) do Kit.Hide(f[k]) end
    dropBox(Kit, f, f.dropButton, { f.dropButton, f })
    if w.type ~= "LSM30_Font" then Kit.Font(f.text) end
    label(Kit, w, f.label)
    -- The arrow opens or closes the list; dress it right after.
    f.dropButton:HookScript("OnClick", Engine.Safe(def, function() openList(Kit, w) end))
end

function Ace.Skin(w)
    if not isTable(w) or Ace.dressed[w] then return end
    local t = type(w.type) == "string" and w.type or ""
    local fn = TYPES[t]
    if not fn and string.find(t, "^Dropdown%-Item%-") then fn = item end
    if not fn and string.find(t, "^LSM30_") then fn = media end
    if not fn or not isTable(w.frame) then return end
    if w.frame.IsForbidden and w.frame:IsForbidden() then return end
    Ace.dressed[w] = true
    fn(ns.Kit, w)
end

-- ---------------------------------------------------------------------
-- Library hooks
-- ---------------------------------------------------------------------

local hooked = {} -- method name -> the function we hooked (our wrapper runs after)
local function made(_, w)
    if not def then
        Ace.waiting[w] = true
        return
    end
    if def.broken or not Engine.Wanted(def) then return end
    local ok, err = pcall(Ace.Skin, w)
    if not ok then Engine.Broke(def, err) end
end

function Ace.Hook()
    local lib = ace()
    if not isTable(lib) then return false end
    for _, m in ipairs({ "RegisterAsWidget", "RegisterAsContainer" }) do
        if type(lib[m]) == "function" and lib[m] ~= hooked[m] then
            hooksecurefunc(lib, m, made)
            hooked[m] = lib[m]
        end
    end
    return true
end

Ace.Hook()
DUI.RegisterEvent("ADDON_LOADED", function() Ace.Hook() end)

DUI.On("StyleChanged", function()
    for fs in pairs(Ace.headings) do paintHeading(fs) end
    for hl in pairs(Ace.washes) do Style.PaintAccent(hl, 0.18) end
end)

Engine.Register({ key = "ace3", pack = "addons", switch = "ace3", label = "Ace3",
    thirdParty = true, apply = function(_, d)
        def = d
        Ace.Hook()
        for w in pairs(Ace.waiting) do
            Ace.waiting[w] = nil
            made(nil, w)
        end
    end })
