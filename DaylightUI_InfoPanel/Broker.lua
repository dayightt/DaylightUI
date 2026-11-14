-- LibDataBroker-1.1 objects from other addons, usable in any data text slot
-- under the key "ldb:<name>". The library is only read, never shipped, so
-- with no broker addon installed the list is empty.
--
-- Objects can appear late (load-on-demand addons). A slot saved with one
-- that doesn't exist yet stays empty until it does. Attribute changes are
-- batched for Broker.WAIT seconds since some objects update many times a second.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local DT = ns.DataTexts
local Broker = {}
ns.Broker = Broker

Broker.PREFIX = "ldb:"
Broker.WAIT = 0.1        -- changes gathered this long before a redraw

function Broker.Lib()
    local stub = _G.LibStub
    if type(stub) ~= "table" or type(stub.GetLibrary) ~= "function" then return nil end
    return stub:GetLibrary("LibDataBroker-1.1", true)
end

local function str(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == "number" then return tostring(v) end
    return type(v) == "string" and v ~= "" and v or nil
end

-- What an object says: its text, else its value and suffix, else its label.
function Broker.Text(obj)
    local t = str(obj.text)
    if t then return t end
    local v = str(obj.value)
    if v then return v .. (str(obj.suffix) and (" " .. obj.suffix) or "") end
    return nil
end

local function label(name, obj) return str(obj.label) or name end

local function textFor(name, obj)
    return function()
        local words = label(name, obj)
        local t = Broker.Text(obj)
        if not t then
            local v = DT.Value(words)
            return v, v
        end
        local v = DT.Value(t)
        return DT.Word(words .. " ") .. v, v
    end
end

-- The object's own tooltip lines, shown where our tooltips go.
local function tipFor(name, obj)
    return function()
        if type(obj.OnTooltipShow) == "function" then
            DUI.Tips.Title(label(name, obj))
            DT.FlushTip()
            obj.OnTooltipShow(GameTooltip)
            return
        end
        DUI.Tips.Title(label(name, obj))
        local t = Broker.Text(obj)
        if t then DUI.Tips.Text(t) end
    end
end

function Broker.Add(name, obj)
    if type(name) ~= "string" or type(obj) ~= "table" then return end
    local key = Broker.PREFIX .. name
    if DT.TEXTS[key] then return end
    local text = {
        name = label(name, obj), broker = name,
        text = textFor(name, obj),
        -- Keeps its own icon colors, never tinted with the accent.
        iconOf = function()
            local icon = obj.icon
            if type(icon) ~= "string" and type(icon) ~= "number" then return nil end
            return icon, obj.iconCoords, obj.iconR and { obj.iconR, obj.iconG or 1, obj.iconB or 1 } or nil
        end,
        click = function(button, slot)
            if type(obj.OnClick) == "function" then obj.OnClick(slot, button) end
        end,
    }
    -- Objects with their own hover handling (their own tooltip library) get the slot.
    if type(obj.OnEnter) == "function" and type(obj.OnTooltipShow) ~= "function" then
        text.enter = function(slot) obj.OnEnter(slot) end
        text.leave = function(slot) if type(obj.OnLeave) == "function" then obj.OnLeave(slot) end end
    else
        text.tip = tipFor(name, obj)
    end
    DT.TEXTS[key] = text
    DT.NAMES[key] = text.name
    DT.ORDER[#DT.ORDER + 1] = key
    Broker.Used(key)
end

-- If a saved slot was waiting for this object, lay the strips out again.
function Broker.Used(key)
    local db = ns.module and ns.module.db
    if not db then return end
    local used = false
    for _, c in ipairs({ db.data, db.databar }) do
        for _, v in pairs(c) do if v == key then used = true end end
    end
    if not used then return end
    if db.data.enabled == true then DUI.SafeCall(DT.Apply, db.data) end
    if db.databar.enabled == true and ns.DataBar and ns.DataBar.body then DUI.SafeCall(ns.DataBar.Apply, db) end
end

-- Batched changes, so each object's slots redraw once.
local pending, waiting = {}, false
local function flush()
    waiting = false
    for key in pairs(pending) do
        pending[key] = nil
        DT.Redraw(key)
    end
end
function Broker.Changed(name)
    local key = Broker.PREFIX .. tostring(name)
    if not DT.TEXTS[key] then return end
    pending[key] = true
    if waiting then return end
    waiting = true
    C_Timer.After(Broker.WAIT, flush)
end

-- Picks up existing objects and listens for new ones. Runs when the module
-- enables and once more at login.
local hooked = false
function Broker.Watch()
    local lib = Broker.Lib()
    if not lib then return end
    if type(lib.DataObjectIterator) == "function" then
        for name, obj in lib:DataObjectIterator() do Broker.Add(name, obj) end
    end
    if hooked or type(lib.RegisterCallback) ~= "function" then return end
    hooked = true
    lib.RegisterCallback(Broker, "LibDataBroker_DataObjectCreated", function(_, name, obj) Broker.Add(name, obj) end)
    lib.RegisterCallback(Broker, "LibDataBroker_AttributeChanged", function(_, name) Broker.Changed(name) end)
end

-- ---------------------------------------------------------------------
-- Data texts and data panels from Daylight UI plugins (DaylightUI.API's
-- me.AddDataText and me.AddDataPanel). A plugin's text is keyed
-- "<plugin>:<key>" and sits in every slot menu beside the built-in ones.
-- ---------------------------------------------------------------------

local Tips = DUI.Tips

-- What a plugin's tooltip function gets: Daylight UI's tooltip rows, so its
-- lines read like every other data text's.
Broker.TIP = {
    Title = function(text) Tips.Title(text) end,
    Line = function(label, val) Tips.Line(label, val) end,
    Text = function(text) Tips.Text(text) end,
    Hint = function(text) Tips.Hint(text) end,
}

-- Runs one of a plugin's functions and hands back what it returned. An error
-- is reported once under the plugin's name and returns nothing.
local box = {}
local function keep(fn, ...) box = { fn(...) } end
local function run(owner, fn, ...)
    box = {}
    if not DUI.SafeCallAs(owner, keep, fn, ...) then return end
    return box[1], box[2], box[3], box[4], box[5]
end

local function plainString(v)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) == "number" then return tostring(v) end
    return type(v) == "string" and v or nil
end

-- The plugin's text() returns label, value and an optional color for the
-- value. The label is tan and drops first when the strip is short of room;
-- the value takes the accent at its slot unless the plugin colored it.
local function pluginText(spec)
    return function()
        local inSample = DUI.TestPartShown and DUI.TestPartShown("datatexts")
        local label, val, r, g, b
        if inSample and spec.sample ~= nil then
            val = spec.sample
        else
            label, val, r, g, b = run(spec.owner, spec.text)
        end
        label, val = plainString(label), plainString(val)
        if not val then
            if not label then return nil end
            local v = DT.Value(label)
            return v, v
        end
        local c = type(r) == "number" and type(g) == "number" and type(b) == "number" and { r, g, b } or nil
        local v = DT.Value(val, c)
        if not label or label == "" then return v, v end
        return DT.Word(label .. " ") .. v, v
    end
end

function Broker.AddPlugin(spec)
    local key = spec.key
    local text = {
        name = spec.label, plugin = spec.owner, events = spec.events, poll = spec.poll == true or nil,
        text = pluginText(spec),
    }
    if spec.onEvent then
        text.onEvent = function(event, ...) run(spec.owner, spec.onEvent, event, ...) end
    end
    if spec.tooltip then
        text.tip = function()
            Tips.Title(spec.label)
            run(spec.owner, spec.tooltip, Broker.TIP)
        end
    end
    if spec.click then text.click = function(button, slot) run(spec.owner, spec.click, button, slot) end end
    if spec.wheel then text.wheel = function(delta, slot) run(spec.owner, spec.wheel, delta, slot) end end
    if spec.icon then
        text.iconOf = function()
            local icon = spec.icon
            if type(icon) == "function" then icon = run(spec.owner, icon) end
            if type(icon) ~= "string" and type(icon) ~= "number" then return nil end
            return icon
        end
    end
    local had = DT.TEXTS[key] ~= nil
    DT.TEXTS[key] = text
    DT.NAMES[key] = spec.label
    if not had then DT.ORDER[#DT.ORDER + 1] = key end
    Broker.Used(key)
    Broker.UsedInPanels(key)
end

-- Every plugin text registered so far, then each new one as it comes.
function Broker.TakePlugins()
    local Report = DUI.APIReport
    if not (Report and Report.DataTexts) then return end
    local order, all = Report.DataTexts()
    for _, key in ipairs(order) do
        if not DT.TEXTS[key] or DT.TEXTS[key].plugin then Broker.AddPlugin(all[key]) end
    end
end
DUI.On("DataTextsChanged", function(key)
    local Report = DUI.APIReport
    local _, all = Report.DataTexts()
    if all[key] then Broker.AddPlugin(all[key]) end
end)
DUI.On("DataTextRedraw", function(key)
    if DT.TEXTS[key] then DT.Redraw(key) end
end)

-- A plugin's own panel: a strip of slots on the plugin's frame, laid out and
-- drawn like the panel's own. The player picks each slot's text with a
-- Shift+right-click on it; the picks are kept in the module's settings
-- (data.panels[key]), else the panel's own defaults.
Broker.panels = {}

-- A slot with nothing picked yet: a quiet + that says how to pick. Never in
-- the slot menus.
Broker.EMPTY = "panel:empty"
DT.TEXTS[Broker.EMPTY] = {
    name = "",
    text = function() local v = DT.Word("+") return v, v end,
    tip = function()
        Tips.Title(L["Empty slot"])
        Tips.Hint(L["Shift+right-click: pick a text"])
    end,
}

local function panelCfg(p)
    local db = ns.module and ns.module.db
    local saved = db and type(db.data) == "table" and type(db.data.panels) == "table" and db.data.panels[p.key]
    local c = { enabled = true, count = p.count, labels = p.labels, icons = p.icons, textSize = p.textSize }
    for i = 1, p.count do
        local key = (type(saved) == "table" and saved["slot" .. i]) or p.slots[i]
        c["slot" .. i] = DT.TEXTS[key] and key or Broker.EMPTY
    end
    return c
end

local function savePick(p, i, key)
    local db = ns.module and ns.module.db
    if not (db and type(db.data) == "table") then return end
    db.data.panels = type(db.data.panels) == "table" and db.data.panels or {}
    local saved = db.data.panels[p.key] or {}
    db.data.panels[p.key] = saved
    saved["slot" .. i] = key
end

function Broker.ApplyPanel(p)
    if not (ns.module and ns.module.enabled) then return end
    p.strip.Attach(p.frame, panelCfg(p))
    p.strip.Apply(panelCfg(p))
end

local function openPick(p, s)
    local idx
    for i, x in ipairs(p.strip.slots) do if x == s then idx = i end end
    if not idx then return end
    local keys, names = { Broker.EMPTY }, { [Broker.EMPTY] = L["None"] }
    for _, k in ipairs(DT.ORDER) do
        keys[#keys + 1] = k
        names[k] = DT.NAMES[k]
    end
    DUI.Widgets.OpenMenu(s, keys, names, panelCfg(p)["slot" .. idx], function(key)
        savePick(p, idx, key)
        Broker.ApplyPanel(p)
    end, nil, { atCursor = true })
end

function Broker.AddPanel(spec)
    local p = Broker.panels[spec.key]
    if not p then
        p = { key = spec.key, strip = {} }
        Broker.panels[spec.key] = p
        DT.New(p.strip, {
            pick = function(s) openPick(p, s) end,
            tip = function(s)
                GameTooltip:SetPoint("BOTTOM", s, "TOP", 0, DT.TIP_GAP)
            end,
        })
    end
    p.frame, p.count = spec.frame, spec.count
    p.slots, p.labels, p.icons, p.textSize = spec.slots, spec.labels, spec.icons, spec.textSize
    Broker.ApplyPanel(p)
    -- A plugin frame that resizes lays its slots out again.
    if not p.sized then
        p.sized = true
        p.frame:HookScript("OnSizeChanged", function() p.strip.Layout(false) end)
        p.frame:HookScript("OnShow", function() Broker.ApplyPanel(p) end)
    end
end

-- A panel whose saved slot waited for this text shows it now.
function Broker.UsedInPanels(key)
    for _, p in pairs(Broker.panels) do
        local c = panelCfg(p)
        for i = 1, p.count do
            if c["slot" .. i] == key then Broker.ApplyPanel(p) break end
        end
    end
end

function Broker.TakePanels()
    local Report = DUI.APIReport
    if not (Report and Report.DataPanels) then return end
    local order, all = Report.DataPanels()
    for _, key in ipairs(order) do Broker.AddPanel(all[key]) end
end
DUI.On("DataPanelsChanged", function(key)
    if not (ns.module and ns.module.enabled) then return end
    local _, all = DUI.APIReport.DataPanels()
    if all[key] then Broker.AddPanel(all[key]) end
end)
