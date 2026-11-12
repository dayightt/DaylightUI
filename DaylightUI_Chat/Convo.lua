-- The conversation card: one whisper conversation (Thread.lua) on a card that
-- slides out from beside the whisper tiles (Tiles.lua). Clicking a tile toggles
-- it, Escape tucks it away, "All" opens the hub (Hub.lua).

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local L = DUI.L

local Convo = {}
ns.Convo = Convo

Convo.SIZE = { 200, 300 }
Convo.SLIDE = 16 -- px it slides in from, toward the tiles
Convo.MIN = { 160, 180 } -- resize grip limits (same as the sliders)
Convo.MAX = { 600, 700 }

local card, thread, cfg, grip
local open = false
local live -- { w, h } while resizing

-- A setting changed while open (position, size): lay it out again.
function Convo.Apply(c)
    cfg = c
    if not (card and open) or live then return end
    card:SetSize(Convo.Size())
    ns.Chat.GripCorner(grip, Convo.GripCorner())
    ns.Thread.Fit(thread)
    ns.Thread.Fill(thread)
end

-- Where it opens (cardAt): "side" folds out beside the chat at the chat's height,
-- "above" rises over the whisper tiles, "free" stays where it was dragged (saved
-- in the module db's cardSpot like the hub; /dui reset forgets it).
function Convo.At()
    local a = cfg and cfg.cardAt
    if a == "above" or a == "free" then return a end
    return "side"
end

local function db()
    local mod = DUI:GetModule("Chat")
    local d = mod and mod.db
    return type(d) == "table" and d or nil
end

-- Saved position: its center, in UIParent units from the screen center.
function Convo.Spot()
    local d = db()
    local s = d and d.cardSpot
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then return s end
    return nil
end

local function saveSpot(f)
    local d = db()
    local x, y = f:GetCenter()
    local s, u = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local ux, uy = UIParent:GetCenter()
    if not (d and type(x) == "number" and type(ux) == "number" and s and u and u > 0) then return end
    d.cardSpot = { DUI.Pixel.Snap(UIParent, x * s / u - ux), DUI.Pixel.Snap(UIParent, y * s / u - uy) }
end

DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = function()   -- /dui reset
    local d = db()
    if d then d.cardSpot = nil end
    if ns.Tiles.Layout then ns.Tiles.Layout() end
end

-- Is it open on this conversation?
function Convo.Showing(key) return open and thread ~= nil and thread.c == key end
function Convo.Key() return open and thread and thread.c or nil end
-- Typing a reply counts as chat activity, like typing in the main box.
function Convo.Typing()
    return open and thread ~= nil and thread.input:HasFocus() and true or false
end

-- Beside the chat: the width setting and the chat panel's height.
-- Above the chat or dragged away: its own height (cardHeight).
function Convo.Size()
    if live then return live[1], live[2] end
    if Convo.At() ~= "side" then
        return (cfg and cfg.cardWidth) or Convo.SIZE[1], (cfg and cfg.cardHeight) or Convo.SIZE[2]
    end
    local h = ns.Chat.PanelHeight()
    if type(h) ~= "number" or h <= 0 then h = Convo.SIZE[2] end
    return (cfg and cfg.cardWidth) or Convo.SIZE[1], h
end

local function build()
    -- Lives in the chat's drawer (Tiles.lua) and slides out from behind the tiles.
    card = CreateFrame("Frame", "DaylightUIChatTalk", ns.Tiles.Drawer())
    card:SetSize(Convo.Size())
    card:SetFrameStrata("HIGH") -- above action bars and unit frames (MEDIUM), like the Show window
    card:EnableMouse(true)
    card:Hide()
    -- Shares the chat panel's frame and accent line.
    Style.Shell(card, {})
    card.top = card:CreateTexture(nil, "OVERLAY")
    card.top:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.top:SetHeight(2)
    card.top:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -2)
    card.top:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -2)
    thread = ns.Thread.New(card, { onClose = function() Convo.Close() end, links = { "clear", "all" },
        size = function() return Convo.Size() end })
    -- Escape tucks it away; other keys pass through.
    DUI.Win.Keys(card, function(key)
        if key == "ESCAPE" then Convo.Close(); return true end
    end)
    Convo.BuildMove()
end

-- ---------------------------------------------------------------------
-- Dragged away and sized
-- ---------------------------------------------------------------------

-- Not while the chat is locked (header padlock) or in combat, so a slip can't
-- move it. Same as the chat's own drag.
local function free() return not (cfg and cfg.locked) and not InCombatLockdown() end

-- The grip goes on the corner away from the chat and tiles.
function Convo.GripCorner()
    local at, left = Convo.At(), ns.Tiles.Side() == "left"
    if at == "side" then return left and "BOTTOMLEFT" or "BOTTOMRIGHT" end
    if at == "above" then return left and "TOPRIGHT" or "TOPLEFT" end
    return "BOTTOMRIGHT"
end

local function moveStop()
    if not Convo.moving then return end
    Convo.moving = nil
    local drawer = ns.Tiles.Drawer()
    drawer:StopMovingOrSizing()
    drawer:SetUserPlaced(false) -- saved by us, not in the game's layout file
    drawer:SetClampedToScreen(false)
    ns.Feel.Sizing(false, card)
    saveSpot(drawer)
    if Convo.At() == "free" then ns.Tiles.Layout(); return end
    -- Pulled off the chat, it keeps the height it had there.
    local h = drawer:GetHeight()
    if Convo.At() == "side" and type(h) == "number" and h > 0 then
        DUI:Set("Chat", "cardHeight", math.max(Convo.MIN[2], math.min(Convo.MAX[2], math.floor(h + 0.5))))
    end
    DUI:Set("Chat", "cardAt", "free")
end

function Convo.BuildMove()
    local drawer = ns.Tiles.Drawer()
    drawer:SetMovable(true)
    -- Dragged by its header above the rule; the links and the X keep their clicks.
    card:RegisterForDrag("LeftButton")
    local function onHead()
        local top, s = card:GetTop(), card:GetEffectiveScale()
        local _, y = GetCursorPosition()
        if type(top) ~= "number" or type(y) ~= "number" or not s or s <= 0 then return false end
        return y / s >= top - ns.Thread.HEAD
    end
    card:SetScript("OnDragStart", function()
        if not (open and free() and onHead()) then return end
        Convo.moving = true
        drawer:SetClampedToScreen(true)
        ns.Feel.Sizing(true, card)
        drawer:StartMoving()
    end)
    card:SetScript("OnDragStop", moveStop)
    card:HookScript("OnHide", moveStop)
    -- Live resize: the card fills the drawer and the lines re-layout.
    drawer:SetScript("OnSizeChanged", function(_, w, h)
        if not (live and type(w) == "number" and type(h) == "number") then return end
        live[1], live[2] = w, h
        card:SetSize(w, h)
        ns.Thread.Fit(thread)
        ns.Thread.Fill(thread)
    end)
    local fromH
    grip = ns.Chat.MakeGrip({ holder = drawer, parent = card, panel = card, name = "DaylightUIChatTalkGrip",
        strata = "HIGH",
        edges = function() return 0, 0 end,
        allowed = function() return open and free() end,
        -- Beside the chat its height matches the chat, so only the width changes.
        bounds = function()
            if Convo.At() == "side" then return Convo.MIN[1], fromH, Convo.MAX[1], fromH end
            return Convo.MIN[1], Convo.MIN[2], Convo.MAX[1], Convo.MAX[2]
        end,
        sizing = function(on)
            if on then
                local w, h = Convo.Size()
                fromH = math.floor(h + 0.5)
                live = { w, h }
                Convo.sizing = true
            else
                Convo.sizing = nil
            end
        end,
        done = function(w, h)
            live = nil
            drawer:SetUserPlaced(false)
            if Convo.At() == "free" then saveSpot(drawer) end
            if Convo.At() ~= "side" then DUI:Set("Chat", "cardHeight", h) end
            DUI:Set("Chat", "cardWidth", w)
            card:SetSize(Convo.Size())
            ns.Thread.Fit(thread)
            ns.Thread.Fill(thread)
            ns.Tiles.Layout()
        end })
    grip:SetFrameLevel(card:GetFrameLevel() + 20)
end

function Convo.Grip() return grip end

-- Mouse over it (the grip fades in, Chat.UpdateFade).
function Convo.Over() return open and card ~= nil and card:IsShown() and card:IsMouseOver() end

function Convo.Open(key)
    if not card then build() end
    local c = ns.Talk.Get(key)
    if not c then return end
    local was = open
    open = true
    card:SetSize(Convo.Size())
    ns.Chat.GripCorner(grip, Convo.GripCorner())
    ns.Thread.Fit(thread)
    Style.PaintAccent(card.top, 0.9)
    card.top:SetShown(not cfg or cfg.topLine ~= false)
    ns.Thread.Set(thread, key)
    ns.Talk.Read(c)
    if not was then
        card:Show()
        DUI.Win.KeysOn(card, true)
        ns.Tiles.Layout()
        ns.Tiles.Card(true)
        DUI.Sound.Play("open")
    end
    thread.input:SetFocus()
    ns.Tiles.Refresh()
end

function Convo.Close()
    if not open then return end
    open = false
    DUI.Win.KeysOn(card, false)
    thread.input:ClearFocus()
    ns.Tiles.Card(false, function() if not open then card:Hide() end end)
    DUI.Sound.Play("close")
    ns.Tiles.Refresh()
end

function Convo.Toggle(key)
    if Convo.Showing(key) then Convo.Close() else Convo.Open(key) end
end

-- A line heard or sent, a pin, a note: redraw if it's the one shown.
function Convo.Changed(key, what)
    if not (open and thread and thread.c == key) then return end
    ns.Thread.Head(thread)
    ns.Thread.Fill(thread, what == "heard" or what == "sent")
    if what == "heard" then ns.Talk.Read(ns.Talk.Get(key)) end
end

function Convo.Repaint()
    if card then Style.PaintAccent(card.top, 0.8); if open then ns.Thread.Fill(thread) end end
end

function Convo.Thread() return thread end
function Convo.Card() return card end
