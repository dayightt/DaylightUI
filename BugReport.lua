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
function Bug.Fields()
    return {
        { label = L["Daylight UI version"], text = tostring(DUI.VERSION) },
        { label = L["Other UI addons (bars, plates, bags...)"], text = Bug.Short(Bug.Addons()) },
        { label = L["Add to \"Error text, if one popped up\""], text = Bug.Setup() },
    }
end

local f

function Bug.Close()
    if not (f and DUI.Win.IsOpen(f)) then return end
    for _, row in ipairs(f.rows) do row.edit:ClearFocus() end
    DUI.Win.Close(f)
    DUI.Win.KeysOn(f, false)
end

local function build()
    local W, Win = DUI.Widgets, DUI.Win
    local count = #Bug.Fields()
    f = Win.New({ name = "DaylightUIBugReport", w = Bug.WIDTH,
        h = Win.HEADER + Bug.TOP + count * Bug.ROW + Bug.FOOT, strata = "DIALOG" })
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
        row.edit = W.Input(host)
        row.edit:SetPoint("TOPLEFT", host, "TOPLEFT", Win.EDGE, y - 18)
        row.edit:SetPoint("RIGHT", host, "RIGHT", -Win.EDGE, 0)
        row.edit:SetScript("OnEscapePressed", Bug.Close)
        f.rows[i] = row
    end
    f.foot = Win.Parts.Footer(host)
    f.foot:Set({ { text = _G.DONE or L["Done"], primary = true, onClick = Bug.Close } })
    Win.Drag(f, {})
    Win.Keys(f, function(key)
        if key == "ESCAPE" then Bug.Close(); return true end
    end)
end

-- Opens with every box filled and the first one selected.
function Bug.Show()
    if not f then build() end
    for i, field in ipairs(Bug.Fields()) do
        local row = f.rows[i]
        row.label:SetText(field.label)
        row.edit.Lock(field.text)
    end
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
