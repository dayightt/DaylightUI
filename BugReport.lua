-- /dui bug: the answers the Discord bug form asks for, one box each, to copy
-- across. The form takes one paste a box, so each of its fields gets its own:
-- the version, the other addons loaded, and a line about the setup to put with
-- the error text. Nothing runs until it's opened, and no character or
-- realm name goes into it.
-- The values stay English whatever the client's language: they're read by
-- whoever works on the bug.

local _, DUI = ...
local L = DUI.L
local Style = DUI.Style

local Bug = {}
DUI.BugReport = Bug

Bug.WIDTH = 520
Bug.FOOT = 56        -- room for the footer
Bug.ROW = 50        -- a label and its box
Bug.TOP = 12        -- under the header
Bug.LAST = 84       -- height of the last box, which holds several lines
Bug.LABEL = 18      -- from a label's top to its box's

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

local function ours(name) return name == "DaylightUI" or string.find(name, "^DaylightUI_") ~= nil end

-- Every other addon that is loaded, by folder name, A to Z.
function Bug.Addons()
    local A, out = C_AddOns, {}
    if not (A and A.GetNumAddOns and A.GetAddOnInfo and A.IsAddOnLoaded) then return out end
    for i = 1, A.GetNumAddOns() do
        local name = A.GetAddOnInfo(i)
        if type(name) == "string" and not ours(name) and A.IsAddOnLoaded(name) then out[#out + 1] = name end
    end
    table.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)
    return out
end

-- Module names, those on and those off.
function Bug.Modules()
    local on, off = {}, {}
    for name, mod in DUI.Modules() do
        local list = mod.enabled and on or off
        list[#list + 1] = name
    end
    table.sort(on)
    table.sort(off)
    return on, off
end

local function listed(names) return #names > 0 and table.concat(names, ", ") or "None" end

-- One line about the setup: the game build, class and level, screen, and the
-- modules switched off.
function Bug.Setup()
    local version, build = call(GetBuildInfo)
    local width, height = call(GetPhysicalScreenSize)
    local scale = UIParent:GetEffectiveScale()
    local _, off = Bug.Modules()
    return string.format("[Game %s (%s) %s, %s %s, screen %sx%s at UI scale %s, modules off: %s]",
        tostring(version or "?"), tostring(build or "?"), tostring(DUI.LOCALE),
        tostring(call(UnitClassBase, "player") or "?"), tostring(call(UnitLevel, "player") or "?"),
        tostring(width or "?"), tostring(height or "?"),
        type(scale) == "number" and string.format("%.2f", scale) or "?", listed(off))
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

-- Whether an error BugGrabber caught is Daylight UI's: a DaylightUI file is named
-- where it was raised, in its message or the top line of its stack. An error
-- another addon raised inside something of ours (a callback, a plugin's module)
-- only has us further down, and isn't.
local function named(text, stack)
    if string.find(text, "DaylightUI", 1, true) then return true end
    local top = type(stack) == "string" and string.match(stack, "[^\r\n]+")
    return top and string.find(top, "DaylightUI", 1, true) ~= nil or false
end

-- This session's Daylight UI errors, the latest last, each { text, count, stack }:
-- a list of its own, so it stays as it was while the window is open.
-- Ours (DUI.Errors: through DUI.SafeCall, and the actions the game blocked) come
-- in the order they last happened. BugGrabber, when loaded, adds the ones raised
-- outside SafeCall. It keeps a repeated error where it first saw it, so those go
-- first, in its order.
function Bug.Errors()
    local out, own, known = {}, {}, {}
    for _, e in ipairs(DUI.Errors()) do
        known[e.text] = true
        own[#own + 1] = { text = e.text, count = e.count, stack = e.stack }
    end
    local grabber = rawget(_G, "BugGrabber")
    local db = type(grabber) == "table" and call(grabber.GetDB, grabber)
    if type(db) == "table" then
        local session = call(grabber.GetSessionId, grabber)
        local seen = {}
        for _, e in ipairs(db) do
            local msg = type(e) == "table" and e.session == session and e.message
            if type(msg) == "string" and not secret(msg) then
                -- Ours repeat there as "(seen 10 times) ...".
                local text = string.gsub(string.match(msg, "^[^\n]*"), "^%(seen %d+ times%) ", "")
                local stack = type(e.stack) == "string" and not secret(e.stack) and e.stack or nil
                if not known[text] and named(text, stack) then
                    local entry = seen[text]
                    if not entry then
                        entry = { text = text, count = 0 }
                        seen[text] = entry
                        out[#out + 1] = entry
                    end
                    entry.count = entry.count + (tonumber(e.counter) or 1)
                    entry.stack = stack
                end
            end
        end
    end
    for _, e in ipairs(own) do out[#out + 1] = e end
    return out
end

-- An error as it's pasted: its first line and how often it happened, then the
-- calls nearest to it. The whole stack would crowd out the rest of the box.
Bug.STACK_LINES = 8
local function errorText(e)
    local lines = { (e.count or 1) > 1 and string.format("%s (x%d)", e.text, e.count) or e.text }
    if type(e.stack) == "string" then
        for line in string.gmatch(e.stack, "[^\r\n]+") do
            if #lines > Bug.STACK_LINES then break end
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, "\n")
end

-- The form's addons box takes 200 characters and cuts a longer paste short.
Bug.ADDONS_MAX = 200

-- The names worth the box's room, in order: an addon's own parts ("Spoken_Quests"
-- beside "Spoken") are left out, and helpers named to load first ("!BugGrabber")
-- go last.
function Bug.Main(names)
    local have, main, helpers = {}, {}, {}
    for _, name in ipairs(names) do have[name] = true end
    for _, name in ipairs(names) do
        local base = string.match(name, "^(.-)_")
        if not (base and base ~= "" and have[base]) then
            local list = string.sub(name, 1, 1) == "!" and helpers or main
            list[#list + 1] = name
        end
    end
    for _, name in ipairs(helpers) do main[#main + 1] = name end
    return main
end

-- As many names as that box takes, then how many were left out.
function Bug.Short(names)
    local all = listed(names)
    if #all <= Bug.ADDONS_MAX then return all end
    names = Bug.Main(names)
    all = listed(names)
    if #all <= Bug.ADDONS_MAX then return all end
    local out, fit = "", 0
    for i, name in ipairs(names) do
        local try = i == 1 and name or (out .. ", " .. name)
        if #try + #string.format(" +%d more", #names - i) > Bug.ADDONS_MAX then break end
        out, fit = try, i
    end
    return string.format("%s +%d more", out, #names - fit)
end

-- The form's fields we can answer, in its order. The labels are the form's own.
-- A report is about one bug, so the last box carries one error: `err`, or none.
function Bug.Fields(err)
    local last = Bug.Setup()
    if err then last = errorText(err) .. "\n" .. last end
    return {
        { label = L["Daylight UI version"], text = tostring(DUI.VERSION) },
        { label = L["Other UI addons (bars, plates, bags...)"], text = Bug.Short(Bug.Addons()) },
        { label = L["Add to \"Error text, if one popped up\""], text = last },
    }
end

local f

function Bug.Close()
    if not (f and DUI.Win.IsOpen(f)) then return end
    for _, row in ipairs(f.rows) do row.edit:ClearFocus() end
    DUI.Win.Close(f)
    DUI.Win.KeysOn(f, false)
end

-- The last box: a copy box several lines tall, locked the way W.Input's are.
local function lines(host, y)
    local W, Win = DUI.Widgets, DUI.Win
    local area = W.TextArea(host, { width = Bug.WIDTH - 2 * Win.EDGE - 28, step = 40, onEscape = Bug.Close })
    area:SetPoint("TOPLEFT", host, "TOPLEFT", Win.EDGE, y)
    area:SetPoint("RIGHT", host, "RIGHT", -Win.EDGE, 0)
    area:SetHeight(Bug.LAST)
    local e = area.edit
    e:SetTextInsets(6, 6, 6, 6)   -- off the box's edge, like the one-line boxes
    e:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    function e.Lock(text)
        area.Lock(text, true)
        e:SetText(text)
        e:SetCursorPosition(0)
        area:SetVerticalScroll(0)
    end
    return e
end

local function build()
    local W, Win = DUI.Widgets, DUI.Win
    local count = #Bug.Fields()
    f = Win.New({ name = "DaylightUIBugReport", w = Bug.WIDTH,
        h = Win.HEADER + Bug.TOP + (count - 1) * Bug.ROW + Bug.LABEL + Bug.LAST + 12 + Bug.FOOT, strata = "DIALOG" })
    f.title:SetText(L["Report a bug"])
    if f.sub then f.sub:SetText(L["Click a box and press Ctrl+C, then paste it into the Discord form."]) end
    f.onClose = Bug.Close
    local host = f.host
    f.rows = {}
    for i = 1, count do
        local row = {}
        local y = -(Bug.TOP + (i - 1) * Bug.ROW)
        row.label = Style.Text(host, Style.SIZE.small, "LEFT")
        Style.InkText(row.label, "LABEL")
        row.label:SetPoint("TOPLEFT", host, "TOPLEFT", Win.EDGE, y)
        if i < count then
            row.edit = W.Input(host)
            row.edit:SetPoint("TOPLEFT", host, "TOPLEFT", Win.EDGE, y - Bug.LABEL)
            row.edit:SetPoint("RIGHT", host, "RIGHT", -Win.EDGE, 0)
            row.edit:SetScript("OnEscapePressed", Bug.Close)
        else
            row.edit = lines(host, y - Bug.LABEL)
        end
        f.rows[i] = row
    end
    -- Earlier and later errors, beside the last box's label. The chevron art
    -- points down.
    local last = f.rows[count]
    f.next = W.IconButton(host, "ui-chevron.png", L["Later error"], function() Bug.Step(1) end)
    f.next.icon:SetRotation(math.pi / 2)
    f.next:SetPoint("RIGHT", host, "RIGHT", -Win.EDGE, 0)
    f.next:SetPoint("TOP", last.label, "TOP", 0, 4)
    f.prev = W.IconButton(host, "ui-chevron.png", L["Earlier error"], function() Bug.Step(-1) end)
    f.prev.icon:SetRotation(-math.pi / 2)
    f.prev:SetPoint("RIGHT", f.next, "LEFT", -2, 0)
    f.count = Style.Text(host, Style.SIZE.small, "RIGHT")
    Style.InkText(f.count, "pop")
    f.count:SetPoint("RIGHT", f.prev, "LEFT", -6, 0)
    f.foot = Win.Parts.Footer(host)
    f.foot:Set({ { text = _G.DONE or L["Done"], primary = true, onClick = Bug.Close } })
    Win.Drag(f, {})
    Win.Keys(f, function(key)
        if key == "ESCAPE" then Bug.Close(); return true end
    end)
end

-- Shows or hides one of the error controls, easing it in.
local function ease(region, on)
    local M = DUI.Motion
    if on and not region:IsShown() then
        region:Show()
        M.Fade(region, 0, 1, M.FAST)
    elseif not on then
        region:Hide()
    end
end

-- stepped: the last box changed under the reader, so its new text eases in.
local function fill(stepped)
    for i, field in ipairs(Bug.Fields(f.errors[f.at])) do
        local row = f.rows[i]
        row.label:SetText(field.label)
        row.edit.Lock(field.text)
    end
    local many = #f.errors > 1
    ease(f.prev, many)
    ease(f.next, many)
    ease(f.count, many)
    if many then f.count:SetText(string.format(L["%d of %d"], f.at, #f.errors)) end
    if stepped then
        local M = DUI.Motion
        M.Fade(f.rows[#f.rows].edit, 0, 1, M.FAST)
        M.Fade(f.count, 0, 1, M.FAST)
    end
end

-- Shows the error before or after the one in the last box.
function Bug.Step(by)
    if not (f and f.errors) then return end
    local at = math.max(1, math.min(#f.errors, f.at + by))
    if at == f.at then return end
    f.at = at
    fill(true)
end

-- Opens with every box filled, the latest error in the last one, and the first
-- box selected.
function Bug.Show()
    if not f then build() end
    f.errors = Bug.Errors()
    f.at = #f.errors
    fill()
    if not DUI.Win.IsOpen(f) then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        f:SetScale(DUI.Win.Scale(1))
        DUI.Win.Open(f)
        DUI.Win.KeysOn(f, true)
    end
    f:Raise()
    f.rows[1].edit:SetFocus()
end

DUI.RegisterCommand("bug", Bug.Show, L["/dui bug - your version, addons and setup, ready to copy into the Discord bug form"])
