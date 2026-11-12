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
