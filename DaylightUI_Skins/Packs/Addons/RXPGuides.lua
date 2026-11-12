-- Skins RestedXP Guides: the guide window (header, step list, footer), current
-- step boxes and check marks, and the active items and targets boxes. Covers
-- both its default V1 window and the beta V2 window (below). Its options are
-- AceConfig, handled by Packs/Addons/Ace3.lua. Its minimap button goes in the
-- info panel's drawer.
-- What it builds: RXPFrame (GuideWindow.lua, on load) with .BottomFrame (step
-- list), RXPFrameGuideName (header), .Footer and .ScrollFrame. Step rows live
-- in .ScrollChild.framePool and current steps in .CurrentStepFrame.framePool
-- (created as steps come up; SetStep ends with CurrentStepFrame.UpdateText).
-- Its theme resets the backdrops (RXPFrame:UpdateVisuals) and scroll bar art
-- (RXPFrame.UpdateScrollBar).

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine

Engine.AddonSwitch({ key = "rxp", addon = "RXPGuides", label = "RestedXP Guides",
    desc = "The guide window (old and new), its steps and its item and target boxes." })

local function isTable(x) return type(x) == "table" end

-- One of its own boxes: backdrop removed, ours instead.
local function box(Kit, f, look)
    if not isTable(f) or not f.CreateTexture then return end
    Kit.Backdrop(f)
    Kit.Shell(f, look or "window")
end

-- Our font on every text region of a frame, keeping size and color.
local function fonts(Kit, f)
    if not isTable(f) or not f.GetRegions then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then Kit.Font(r) end
    end
end

-- Step boxes and list rows refresh many times a second (its ticker updates the
-- list one step at a time and the top text every cycle) without redrawing their
-- art. So each is dressed once, and fully only when its theme redraws
-- everything (`all`: UpdateVisuals, on show).
local dressedStep = setmetatable({}, { __mode = "k" })
local dressedRow = setmetatable({}, { __mode = "k" })

local function steps(Kit, all)
    local f = _G.RXPFrame
    local cur = isTable(f) and f.CurrentStepFrame
    if not isTable(cur) or not isTable(cur.framePool) then return end
    for _, stepframe in pairs(cur.framePool) do
        if isTable(stepframe) then
            if all or not dressedStep[stepframe] then
                dressedStep[stepframe] = true
                box(Kit, stepframe)
                box(Kit, stepframe.number, "control")
                if isTable(stepframe.number) then fonts(Kit, stepframe.number) end
            end
            -- Lines come and go with the step; give each new one our box once.
            for _, el in pairs(stepframe.elements or {}) do
                if isTable(el) and isTable(el.button) then Kit.Check(el.button) end
            end
        end
    end
end

local function rows(Kit, all)
    local f = _G.RXPFrame
    local child = isTable(f) and f.ScrollChild
    if not isTable(child) or not isTable(child.framePool) then return end
    for _, row in pairs(child.framePool) do
        if isTable(row) and row.CreateTexture and (all or not dressedRow[row]) then
            dressedRow[row] = true
            Kit.Backdrop(row)
            Kit.Row(row, "art")
        end
    end
end

local function window(Kit)
    local f = _G.RXPFrame
    box(Kit, f.BottomFrame)
    box(Kit, _G.RXPFrameGuideName)
    box(Kit, f.Footer)
    for _, part in ipairs({ _G.RXPFrameGuideName, f.Footer }) do
        if isTable(part) then
            Kit.Hide(part.bg) -- its banner art
            fonts(Kit, part)
        end
    end
    local sf = f.ScrollFrame
    if isTable(sf) and isTable(sf.ScrollBar) then
        Kit.ScrollBar(sf.ScrollBar)
        Kit.ScrollThumb(sf.ScrollBar)
    end
    for _, name in ipairs({ "RXPItemFrame", "RXPTargetFrame" }) do
        box(Kit, _G[name])
        box(Kit, _G[name .. "_title"], "control")
        fonts(Kit, _G[name .. "_title"])
    end
    rows(Kit, true)
    steps(Kit, true)
end

-- ---------------------------------------------------------------------
-- V2, the beta window (RestedXP's "Enable V2 Interface", UI/V2/Core.lua,
-- v4.11.26). Every piece is one of its own unnamed AceGUI widgets
-- (RXPV2GuideWindow, RXPV2GuideStepsItem, RXPV2ActiveStepItem...). Its whole
-- look comes from two functions on the global RXP (`RXP = addon`):
-- RXP.ui.v2:ApplyFrameBackdrop(frame, ...) gives a frame rxpBackground and
-- rxpBorder (created once, recolored on every call: theme change, a step, a
-- checkbox hover), and AddFrameShadow gives it rxpShadow. Post-hooking those,
-- every V2 frame loses that art and gets one of our shells, with the look picked
-- by the dressers below (`V2.role`). Frames with no role (its party window, its
-- importer) are windows; frames with no border of their own (inner panes) get
-- nothing. The shell goes on next frame, once the widget is dressed and its
-- role known. Its menus (the game's DropDownList, its "menu theme") are left as
-- RXP draws them. Text gets our font and ink: values white, quest names keep
-- their colors (Kit.Light only relights dark runs).
-- ---------------------------------------------------------------------

local V2 = {}
ns.RXPv2 = V2
V2.role = setmetatable({}, { __mode = "k" }) -- frame -> a Kit look, or false (no shell)
V2.shelled = setmetatable({}, { __mode = "k" }) -- frame -> the look it wears
V2.pending = setmetatable({}, { __mode = "k" }) -- frame -> its border color (shelled next frame)
V2.pops = setmetatable({}, { __mode = "k" }) -- font string -> true (painted in the accent)
V2.dressed = setmetatable({}, { __mode = "k" })    -- widget -> true
local def -- the skin def, once it runs

local function kind(x) return isTable(x) and x.GetObjectType and x:GetObjectType() or nil end

-- RXP resets its own font on every refresh, so put ours back, keeping the size.
local function font(fs) ns.Kit.Refont(fs) end

local function ink(Kit, fs, color)
    if kind(fs) ~= "FontString" then return end
    font(fs)
    Kit.Light(fs, color)
end

local function pop(fs)
    if kind(fs) ~= "FontString" then return end
    font(fs)
    V2.pops[fs] = true
    DUI.Style.InkText(fs, "pop")
end

-- Hides a button's art (RXP sets it again on a theme change).
local function hideArt(Kit, btn)
    if not isTable(btn) then return end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if btn[get] then Kit.Hide(btn[get](btn)) end
    end
end

local function shellNow(Kit)
    for frame, border in pairs(V2.pending) do
        V2.pending[frame] = nil
        local look = V2.role[frame]
        if look == nil then
            look = not (isTable(border) and type(border[4]) == "number" and border[4] <= 0) and "window" or false
            V2.role[frame] = look
        end
        if look and V2.shelled[frame] == nil then
            V2.shelled[frame] = look
            Kit.Shell(frame, look)
        end
    end
end

function V2.Backdrop(Kit, frame, border)
    if not isTable(frame) then return end
    local name = frame.GetName and frame:GetName()
    if type(name) == "string" and string.find(name, "DropDownList", 1, true) then return end
    for _, key in ipairs({ "rxpBackground", "rxpBorder" }) do
        if isTable(frame[key]) and frame[key].SetAlpha then frame[key]:SetAlpha(0) end
    end
    -- The box beside a step line. Its hover frame (the skip icon) has no box of its own.
    if kind(frame) == "CheckButton" then
        V2.role[frame] = V2.role[frame] or "control"
        if isTable(frame.rxpHoverFrame) then V2.role[frame.rxpHoverFrame] = false end
    end
    if V2.shelled[frame] == nil and V2.pending[frame] == nil then
        V2.pending[frame] = border or false
        C_Timer.After(0, Engine.Safe(def, function() shellNow(Kit) end))
    end
end

-- Same, for frames RXP drew before the skin started.
local function made(Kit, frame)
    if not isTable(frame) then return end
    if isTable(frame.rxpBackground) or isTable(frame.rxpBorder) then V2.Backdrop(Kit, frame, nil) end
    if isTable(frame.rxpShadow) then frame.rxpShadow:SetAlpha(0) end
end

-- Its resize corner: our window kit's grip look, accent on hover.
local function grip(Kit, btn)
    if not isTable(btn) or not btn.CreateTexture or V2.dressed[btn] then return end
    V2.dressed[btn] = true
    hideArt(Kit, btn)
    local Style, Motion = DUI.Style, DUI.Motion
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(DUI.MEDIA .. "ui-grip.png")
    icon:SetAllPoints(btn)
    local c = Style.INK.LABEL
    icon:SetVertexColor(c[1], c[2], c[3], 0.6)
    local lit = btn:CreateTexture(nil, "OVERLAY")
    lit:SetTexture(DUI.MEDIA .. "ui-grip.png")
    lit:SetAllPoints(btn)
    local glow = 0
    Style.PaintAccent(lit, 0)
    -- The glow rides on the accent's alpha, since a gradient ignores SetAlpha in game.
    local function light(on)
        Motion.Tween(lit, glow, on and 1 or 0, Motion.FAST, function(a) glow = a; Style.PaintAccent(lit, a) end)
    end
    btn:HookScript("OnEnter", function() light(true) end)
    btn:HookScript("OnLeave", function() light(false) end)
end

-- The guide window: one window of ours around it all, with the header, name pane
-- and step pane plain inside. Tan title, white guide name, our X, our icon
-- buttons (its gear and guide list), its logo kept.
local function windowTheme(Kit, w)
    hideArt(Kit, w.settingsButton)
    hideArt(Kit, w.guideSelectButton)
    hideArt(Kit, w.sizer)
    Kit.Hide(w.banner)
    Kit.Hide(w.footerBackground)
    ink(Kit, w.title, DUI.Style.INK.LABEL)
    ink(Kit, w.subtitle, DUI.Style.INK.VALUE)
    ink(Kit, w.footerText, DUI.Style.INK.LABEL)
    local sc = isTable(w.guideSteps) and w.guideSteps.scroll
    if isTable(sc) and isTable(sc.scrollbar) then Kit.ScrollThumb(sc.scrollbar) end
end

local function iconButton(Kit, btn, file)
    if not isTable(btn) or V2.dressed[btn] then return end
    V2.dressed[btn] = true
    Kit.IconButton(btn, 2, type(file) == "string" and file or nil)
end

local function stepRows(Kit, steps)
    for _, item in pairs(isTable(steps) and steps.items or {}) do
        if isTable(item) then
            V2.role[item.frame] = "row"
            V2.role[item.numberFrame] = false
            made(Kit, item.frame)
            made(Kit, item.numberFrame)
            ink(Kit, item.text, DUI.Style.INK.TEXT)
            local row = item.row
            if isTable(row) and row.current then pop(item.number) else ink(Kit, item.number, DUI.Style.INK.LABEL) end
        end
    end
end

function V2.Window(Kit, w)
    if not isTable(w) or not isTable(w.frame) or V2.dressed[w] then return end
    V2.dressed[w] = true
    for _, part in ipairs({ w.upperFrame, w.guideNameFrame, w.guideStepsFrame }) do
        if isTable(part) then
            V2.role[part] = false
            made(Kit, part)
        end
    end
    Kit.Window(w.frame)
    Kit.Close(w.closebutton)
    local RXP = _G.RXP
    local theme = RXP and RXP.v2 and RXP.v2.GetTheme and RXP.v2:GetTheme()
    local icons = isTable(theme) and theme.guideWindow or {}
    iconButton(Kit, w.settingsButton, icons.settingsIcon)
    iconButton(Kit, w.guideSelectButton, icons.guideSelectIcon)
    grip(Kit, w.sizer)
    local sc = isTable(w.guideSteps) and w.guideSteps.scroll
    if isTable(sc) and isTable(sc.scrollbar) then Kit.ScrollBar(sc.scrollbar) end
    windowTheme(Kit, w)
    stepRows(Kit, w.guideSteps)
    hooksecurefunc(w, "UpdateSubTheme", Engine.Safe(def, function(self) windowTheme(Kit, self) end))
    if isTable(w.guideSteps) and type(w.guideSteps.SetRows) == "function" then
        hooksecurefunc(w.guideSteps, "SetRows", Engine.Safe(def, function(self) stepRows(Kit, self) end))
    end
end

-- A "Step N" box: our window with its number tab as an accent tab. Each line's
-- box is ours (V2.Backdrop), its text soft white.
local function itemText(Kit, item)
    pop(item.titletext)
    for i = 1, item.activeElementRows or 0 do
        local row = isTable(item.elementRows) and item.elementRows[i]
        if isTable(row) then
            ink(Kit, row.text, DUI.Style.INK.TEXT)
            made(Kit, row.button)
            if isTable(row.button) then made(Kit, row.button.rxpHoverFrame) end
        end
    end
end

function V2.Item(Kit, item)
    if not isTable(item) then return end
    if not V2.dressed[item] then
        V2.dressed[item] = true
        V2.role[item.card] = "window"
        V2.role[item.title] = "tab"
        made(Kit, item.card)
        made(Kit, item.title)
        local again = Engine.Safe(def, function(self) itemText(Kit, self) end)
        for _, m in ipairs({ "SetElements", "UpdateSubTheme", "SetTitle" }) do
            if type(item[m]) == "function" then hooksecurefunc(item, m, again) end
        end
    end
    itemText(Kit, item)
end

local function playerItems(Kit)
    local v2 = _G.RXP and _G.RXP.v2
    local state = isTable(v2) and v2.state
    if not isTable(state) then return end
    V2.Window(Kit, state.guideWindow)
    for _, player in pairs(isTable(state.player) and state.player or {}) do
        for _, item in pairs(isTable(player) and isTable(player.activeStepItems) and player.activeStepItems or {}) do
            V2.Item(Kit, item)
        end
    end
end

function V2.Hook(Kit, d)
    def = d
    local RXP = _G.RXP
    local ui = RXP and RXP.ui and RXP.ui.v2
    local v2 = RXP and RXP.v2
    if not isTable(ui) or not isTable(v2) or V2.hooked then return end
    V2.hooked = true
    if type(ui.ApplyFrameBackdrop) == "function" then
        hooksecurefunc(ui, "ApplyFrameBackdrop", Engine.Safe(def, function(_, frame, _, _, border)
            V2.Backdrop(Kit, frame, border)
        end))
    end
    if type(ui.AddFrameShadow) == "function" then
        hooksecurefunc(ui, "AddFrameShadow", Engine.Safe(def, function(_, frame)
            if isTable(frame) and isTable(frame.rxpShadow) then frame.rxpShadow:SetAlpha(0) end
        end))
    end
    if type(v2.GetGuideWindow) == "function" then
        hooksecurefunc(v2, "GetGuideWindow", Engine.Safe(def, function(self)
            V2.Window(Kit, isTable(self.state) and self.state.guideWindow)
        end))
    end
    if type(v2.UpdatePlayerActiveStepItem) == "function" then
        hooksecurefunc(v2, "UpdatePlayerActiveStepItem", Engine.Safe(def, function(_, item) V2.Item(Kit, item) end))
    end
    -- What it built before the skin started: art removed now, pieces dressed.
    playerItems(Kit)
end

DUI.On("StyleChanged", function()
    for fs in pairs(V2.pops) do DUI.Style.InkText(fs, "pop") end
end)

Engine.Register({ key = "rxp", pack = "addons", addon = "RXPGuides", switch = "rxp", label = "RestedXP Guides",
    thirdParty = true, apply = function(Kit, def)
        local f = _G.RXPFrame
        if not isTable(f) or not isTable(f.CurrentStepFrame) then return false end
        V2.Hook(Kit, def)
        window(Kit)
        local again = Engine.Safe(def, function() window(Kit) end)
        -- Its theme redrew its art, so put ours back on top.
        if type(f.UpdateVisuals) == "function" then hooksecurefunc(f, "UpdateVisuals", again) end
        if type(f.UpdateScrollBar) == "function" then hooksecurefunc(f, "UpdateScrollBar", again) end
        -- A new step came up (its boxes are created then), or the list was filled.
        if type(f.CurrentStepFrame.UpdateText) == "function" then
            hooksecurefunc(f.CurrentStepFrame, "UpdateText", Engine.Safe(def, function() steps(Kit) end))
        end
        if isTable(f.BottomFrame) and type(f.BottomFrame.UpdateFrame) == "function" then
            hooksecurefunc(f.BottomFrame, "UpdateFrame", Engine.Safe(def, function() rows(Kit) end))
        end
        f:HookScript("OnShow", again)
    end })
