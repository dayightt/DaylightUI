-- The whisper hub: every conversation in one window. Search and the list on the
-- left (pinned first, then recent, with last line and unread count), the picked
-- conversation on the right (Thread.lua). Opened from "Whispers" in the tab row,
-- a conversation card's "All", or /dui whispers.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local L = DUI.L
local Win = DUI.Win

local Hub = {}
ns.Hub = Hub

Hub.W, Hub.H = 640, 440
Hub.LIST_W = 220
Hub.EDGE = 12
Hub.CLEAR_H = 24 -- Clear all button under the list
Hub.FOOT = Hub.CLEAR_H + Hub.EDGE + 6

local f, list, search, thread
local picked

local function M() return DUI.Motion end

function Hub.Showing(key) return f ~= nil and Win.IsOpen(f) and picked == key end
function Hub.Frame() return f end
function Hub.Thread() return thread end

local function matches(c, q)
    if q == "" then return true end
    local hay = string.lower((c.name or "") .. " " .. (ns.Talk.Note(c) or ""))
    for _, m in ipairs(c.msgs) do hay = hay .. " " .. string.lower(m.text) end
    return string.find(hay, q, 1, true) ~= nil
end

local function pick(key)
    picked = key
    ns.Thread.Set(thread, key)
    local c = key and ns.Talk.Get(key)
    if c then ns.Talk.Read(c) end
    Hub.Render()
end

function Hub.Render()
    if not (f and Win.IsOpen(f)) then return end
    local q = string.lower(search:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local pinned, recent = {}, {}
    for _, c in ipairs(ns.Talk.List()) do
        if matches(c, q) then
            if c.pinned then pinned[#pinned + 1] = c else recent[#recent + 1] = c end
        end
    end
    local s = list
    local spots = s:Spots()
    s:Begin()
    local function line(c)
        local last = c.msgs[#c.msgs]
        local unread = c.unread or 0
        local file, l, r, top, bt = ns.Thread.ClassIcon(c.class)
        local b = s:Line({ text = ns.Thread.Name(c), color = { Style.ClassTextColor(c.class) },
            icon = file or (DUI.MEDIA .. "ui-chat.png"),
            sub = last and last.text or "",
            value = unread > 0 and tostring(unread) or (last and date("%H:%M", last.t or time()) or ""),
            valueColor = unread > 0 and { Style.Accent() } or Style.INK.LABEL,
            onClick = function() pick(c.key) end,
            onRightClick = function(row) Hub.RowMenu(c.key, row) end })
        -- A cell of an icon sheet (Jiberish style) or the whole icon.
        if b and file and l then b.icon:SetTexCoord(l, r, top, bt) end
        if b and c.key == picked then DUI.Win.Parts.PickLine(b, true) end
    end
    if #pinned > 0 then
        s:Section(L["Pinned"])
        for _, c in ipairs(pinned) do line(c) end
    end
    if #recent > 0 then
        s:Section(L["Recent"])
        for _, c in ipairs(recent) do line(c) end
    end
    s:End()
    s:Ease(spots)
    f.none:SetShown(#pinned + #recent == 0)
    f.none:SetText(q ~= "" and L["No conversations match."] or L["No conversations yet."])
    f.clearAll:SetShown(ns.Talk.AnyLoose())
end

-- Right-click a conversation to pin it or forget it, without opening it first.
function Hub.RowMenu(key, row)
    local c = ns.Talk.Get(key)
    if not c then return end
    local values = { pin = c.pinned and L["Unpin"] or L["Pin"], forget = L["Forget conversation"] }
    DUI.Widgets.OpenMenu(row, { "pin", "forget" }, values, nil, function(a)
        local now = ns.Talk.Get(key)
        if not now then return end
        if a == "pin" then ns.Talk.Pin(now, not now.pinned)
        elseif a == "forget" then ns.Talk.Forget(now) end
    end, nil, { atCursor = true })
end

-- The module's db. Migrates a position saved the old way (the hubSpot setting) once.
local function db()
    local mod = DUI:GetModule("Chat")
    local d = mod and mod.db
    if type(d) ~= "table" then return nil end
    local old = rawget(d, "hubSpot")
    if old ~= nil then
        if d.spot == nil and type(old) == "table" and type(old[1]) == "number" and type(old[2]) == "number" then
            d.spot = { old[1], old[2] }
        end
        d.hubSpot = nil
    end
    return d
end

local function place()
    local spot = Hub.spot and Hub.spot.Get()
    if spot then
        Win.PlaceTop(f, spot[1], spot[2])
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

local function build()
    f = Win.New({ name = "DaylightUIWhispers", w = Hub.W, h = Hub.H })
    f.onClose = function() Hub.Close() end
    Win.SetTitle(f, L["Whispers"])
    local host = f.host
    local left = CreateFrame("Frame", nil, host)
    left:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    left:SetWidth(Hub.LIST_W)
    search = DUI.Widgets.Input(left, { search = true, hint = L["Search whispers..."], maxLetters = 64,
        onChange = function() Hub.Render() end })
    search:SetPoint("TOPLEFT", left, "TOPLEFT", Hub.EDGE, -10)
    search:SetPoint("TOPRIGHT", left, "TOPRIGHT", -Hub.EDGE, -10)
    list = Win.Parts.Stack(left, { top = 46, bottom = Hub.FOOT })
    f.clearAll = DUI.Widgets.Button(left, L["Clear all"], Hub.CLEAR_H)
    f.clearAll:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", Hub.EDGE, Hub.EDGE)
    f.clearAll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -Hub.EDGE, Hub.EDGE)
    DUI.Widgets.Confirm(f.clearAll, L["Clear all"], function() ns.Talk.ForgetAll() end, L["Click again: pinned ones stay"])
    f.none = Style.Text(left, Style.SIZE.body, "CENTER")
    f.none:SetPoint("CENTER", left, "CENTER", 0, 0)
    f.none:SetWidth(Hub.LIST_W - 24)
    Style.InkText(f.none, "LABEL")
    local rule = Win.Parts.Rule(host, true)
    rule:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -8)
    rule:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 8)
    local right = CreateFrame("Frame", nil, host)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 1, 0)
    right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    thread = ns.Thread.New(right, { links = { "clear", "pin", "note", "pop" }, size = function()
        return (f:GetWidth() or Hub.W) - Hub.LIST_W - 1, (f:GetHeight() or Hub.H) - Win.HEADER - 1
    end })
    -- Position is saved in the module db's spot (/dui reset forgets it). Quiet, so
    -- dragging doesn't repaint the chat.
    Hub.spot = Win.Spot(f, db, place)
    Win.Drag(f, { save = Hub.spot.Save, reset = Hub.spot.Reset })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Hub.spot.Reset   -- /dui reset
    Win.Keys(f, function(key)
        if key == "ESCAPE" then Hub.Close(); return true end
    end)
end


function Hub.Open(key)
    if not f then build() end
    place()
    f:SetScale(Win.Scale(1))
    Win.Open(f)
    Win.KeysOn(f, true)
    local list = ns.Talk.List()
    key = key or picked or (list[1] and list[1].key)
    pick(key)
end

function Hub.Close()
    if not (f and Win.IsOpen(f)) then return end
    Win.KeysOn(f, false)
    Win.Close(f)
end

function Hub.Toggle()
    if f and Win.IsOpen(f) then Hub.Close() else Hub.Open() end
end

function Hub.Changed(key, what)
    if not (f and Win.IsOpen(f)) then return end
    -- The shown conversation was cleared: move to the next one.
    if picked and not ns.Talk.Get(picked) then
        local first = ns.Talk.List()[1]
        pick(first and first.key)
        return
    end
    if key == picked then
        ns.Thread.Head(thread)
        ns.Thread.Fill(thread, what == "heard" or what == "sent")
        if what == "heard" then ns.Talk.Read(ns.Talk.Get(key)) end
    end
    Hub.Render()
end

function Hub.Apply() end

function Hub.Repaint()
    if f then Win.Repaint(f); Hub.Render() end
end

-- /dui whispers: the hub belongs to the Daylight chat box (Classic has no tiles,
-- card or live updates), so Classic users are told how to switch.
function Hub.Command()
    if not ns.Box.On() then
        DUI.Print(L["Whispers are part of the Daylight chat box: /dui chat daylight to use it."])
        return
    end
    Hub.Toggle()
end

DUI.RegisterCommand("whispers", function() Hub.Command() end, L["/dui whispers - every whisper conversation"])
