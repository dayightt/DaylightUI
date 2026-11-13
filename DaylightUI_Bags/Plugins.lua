local _, ns = ...
local DUI = DaylightUI

-- Other addons' item marks (upgrade arrows, transmog icons, junk tags...) on
-- Daylight UI's slots. Most of those addons already support Baganator through
-- its plugin API (`Baganator.API`). While Baganator itself is off, this answers
-- the same calls, so a plugin written for Baganator draws on these bags with no
-- Daylight UI specific code.
--   RegisterCornerWidget(label, id, onUpdate, onInit, { corner, priority })
--       onInit(button) creates the plugin's frame once per slot, placed here in
--       its corner (`padding`, `sizeFont` read the way Baganator reads them).
--       onUpdate(frame, details) says whether it shows (nil = can't tell yet,
--       asked again up to `Plugins.RETRIES` times). One widget per corner, by
--       priority. Live bags and bank only: a saved copy (Saved.lua) belongs to
--       another character and would be judged for this one.
--   RegisterUpgradePlugin(label, id, isUpgrade(link)): backs the `upgrade` search.
--   RequestItemButtonsRefresh(): re-asks every slot on the next frame.
--   Any other Register* call is accepted and ignored (no error).
-- A plugin that checks for Baganator before these bags load, or waits for
-- Baganator's own ADDON_LOADED, won't find this.

local Plugins = {}
ns.Plugins = Plugins

Plugins.CORNERS = { top_left = "TOPLEFT", top_right = "TOPRIGHT", bottom_left = "BOTTOMLEFT", bottom_right = "BOTTOMRIGHT" }
Plugins.FALLBACK = "top_right"   -- corner for widgets registered without one
Plugins.RETRIES = 3              -- times to re-ask a widget that can't tell yet...
Plugins.RETRY = 0.25             -- ...this many seconds apart
Plugins.FONT_BASE = 14           -- font size Baganator sizes `sizeFont` widgets for

local widgets = {}   -- { id, onUpdate, onInit, corner, priority, n }, sorted by corner, priority, then registration
local upgrades = {}  -- { id, isUpgrade }
local failed = {}    -- [id] = true once its call errored (reported once, never called again)
local made = setmetatable({}, { __mode = "k" })   -- button -> { box, seen, [id] = frame or false }

-- Calls into a plugin. An error is reported once and that plugin is dropped.
local function ask(id, fn, ...)
    if failed[id] then return false, nil end
    local ok, a = pcall(fn, ...)
    if not ok then
        failed[id] = true
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(a) end
        return false, nil
    end
    return true, a
end

-- btn's frame for widget w, created and placed the first time.
local function widgetOf(btn, m, w)
    local frame = m[w.id]
    if frame ~= nil then return frame end
    local ok, f = ask(w.id, w.onInit, btn)
    frame = ok and type(f) == "table" and type(f.SetParent) == "function" and f or false
    m[w.id] = frame
    if not frame then return frame end
    frame:SetParent(m.box)
    frame:Hide()
    local point = Plugins.CORNERS[w.corner]
    local scale = 1
    if frame.sizeFont and frame.SetScale then
        scale = ns.Items.COUNT_SIZE / Plugins.FONT_BASE
        frame:SetScale(scale)
    end
    local inset = ns.Items.Inset(btn) * (type(frame.padding) == "number" and frame.padding or 1) / scale
    local x = point:find("LEFT") and inset or -inset
    local y = point:find("TOP") and -inset or inset
    frame:ClearAllPoints()
    frame:SetPoint(point, btn, point, x, y)
    return frame
end

-- Plugin marks for one slot, given what it holds (info from Items.InfoAt).
function Plugins.Paint(btn, info, bag, slot)
    if #widgets == 0 then return end
    local m = made[btn]
    if not m then
        m = { box = CreateFrame("Frame", nil, btn) }
        m.box:SetAllPoints(btn)
        m.box:SetFrameLevel(btn:GetFrameLevel() + 2)   -- above the cooldown swipe
        made[btn] = m
    end
    local details
    if info and not ns.Saved.Is(bag) then
        details = { itemID = info.itemID, itemLink = info.hyperlink, iconTexture = info.iconFileID,
            itemCount = info.stackCount, quality = info.quality, isBound = info.isBound,
            hasNoValue = info.hasNoValue, bagID = bag, slotID = slot }
    end
    local taken, unsure = {}, false
    for _, w in ipairs(widgets) do
        local frame = widgetOf(btn, m, w)
        if frame then
            local show = false
            if details and not taken[w.corner] then
                local ok, r = ask(w.id, w.onUpdate, frame, details)
                if ok and r == nil then unsure = true end
                show = ok and r and true or false
            end
            if show then taken[w.corner] = true end
            if show ~= (frame:IsShown() and true or false) then
                frame:SetShown(show)
                -- Fade in when a mark appears on a visible slot (not on the slot's first fill).
                if show and m.seen and btn:IsVisible() then DUI.Motion.Fade(frame, 0, 1, DUI.Motion.FAST) end
            end
        end
    end
    m.seen = true
    -- Item data not loaded yet for this plugin: ask again a bit later.
    local link = details and details.itemLink
    if m.link ~= link then m.link, m.tries = link, 0 end
    if unsure and link and m.tries < Plugins.RETRIES then
        m.tries = m.tries + 1
        C_Timer.After(Plugins.RETRY, function()
            if m.link == link then Plugins.Repaint(btn) end
        end)
    end
end

-- Re-asks one slot with its current contents.
function Plugins.Repaint(btn)
    local holder = btn:GetParent()
    local bag, slot = holder and holder:GetID(), btn:GetID()
    Plugins.Paint(btn, bag and ns.Items.InfoAt(bag, slot), bag, slot)
end

-- btn's frame for widget id (nil if none made yet).
function Plugins.Widget(btn, id)
    local m = made[btn]
    return m and m[id] or nil
end

function Plugins.IsUpgrade(link)
    if not link then return false end
    for _, u in ipairs(upgrades) do
        local ok, yes = ask(u.id, u.isUpgrade, link)
        if ok and yes then return true end
    end
    return false
end

-- Re-ask every slot of every live window, once per burst on the next frame.
-- An active search re-applies its matches.
local queued = false
function Plugins.Refresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        for _, f in ipairs(ns.windows or {}) do
            if not f.spec.still then
                for _, s in ipairs(f.set.Slots()) do Plugins.Repaint(s.button) end
                if f.match then ns.Window.MatchAll(f) end
            end
        end
    end)
end

local function sortWidgets(a, b)
    if a.corner ~= b.corner then return a.corner < b.corner end
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.n < b.n
end

local function registered(list, id)
    for _, e in ipairs(list) do if e.id == id then return true end end
    return false
end

local API = {}

function API.RegisterCornerWidget(_, id, onUpdate, onInit, position)
    if id == nil or type(onUpdate) ~= "function" or type(onInit) ~= "function" or registered(widgets, id) then return end
    position = type(position) == "table" and position or {}
    local corner = Plugins.CORNERS[position.corner] and position.corner or Plugins.FALLBACK
    widgets[#widgets + 1] = { id = id, onUpdate = onUpdate, onInit = onInit, corner = corner,
        priority = type(position.priority) == "number" and position.priority or math.huge, n = #widgets + 1 }
    table.sort(widgets, sortWidgets)
    Plugins.Refresh()
end

function API.IsCornerWidgetActive(id) return registered(widgets, id) end

function API.RegisterUpgradePlugin(_, id, isUpgrade)
    if id == nil or type(isUpgrade) ~= "function" or registered(upgrades, id) then return end
    upgrades[#upgrades + 1] = { id = id, isUpgrade = isUpgrade }
    ns.Search.KEYWORDS.upgrade = function(f) return Plugins.IsUpgrade(f.link) end
    Plugins.Refresh()
end

function API.IsUpgradePluginActive(id) return registered(upgrades, id) end

function API.RequestItemButtonsRefresh() Plugins.Refresh() end

local function noop() end

-- Created at load, before other addons look for it, and never while Baganator
-- itself is on (it answers its own calls). A shim left from an earlier load
-- (the tests) is rebuilt.
function Plugins.Shim()
    local old = _G.Baganator
    if old ~= nil and not (type(old) == "table" and old.DaylightUI) then return end
    if DUI.InstallerPages and DUI.InstallerPages.EnabledFor("Baganator") == true then return end
    _G.Baganator = {
        DaylightUI = true,
        API = setmetatable(API, { __index = function(_, key)
            if type(key) == "string" and key:find("^Register") then return noop end
        end }),
    }
end
Plugins.Shim()
