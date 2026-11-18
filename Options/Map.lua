-- The options map: every setting as the options window shows it, saved to
-- DaylightUIOptionsMap for tools/options_map.lua to turn into
-- Options/options-map.json. It walks the same registry the window draws and
-- reads names through the window's own calls (Theme.Section, Options.Text,
-- Options.Label), so text built in code comes out as players see it.
-- Run /dui optionsmap on an English client with every module loaded, then /reload.

local _, DUI = ...
local L = DUI.L
local Options = DUI.Options
local T = Options.Text

local Map = {}
DUI.OptionsMap = Map

local SEP = " > "

local function str(v)
    if type(v) == "function" then
        local ok, r = pcall(v)
        v = ok and r or nil
    end
    if type(v) == "string" and v ~= "" then return T(v) end
end

-- The addon that has to be on for a module's rows to exist.
local function addonOf(name)
    local A = C_AddOns
    local own = "DaylightUI_" .. name
    if A and A.DoesAddOnExist and A.DoesAddOnExist(own) then return own end
    return "DaylightUI"
end

local function moduleOf(scope)
    local mod = type(scope) == "string" and DUI:GetModule(scope)
    if not mod then return nil end
    return { name = mod.name, label = L[mod.label or mod.name], addon = addonOf(mod.name) }
end

-- The dropdown's choices in the order its menu lists them.
local function choicesOf(item)
    local values, order
    if item.choices then
        local ok, v, o = pcall(item.choices)
        if not ok then return nil end
        values, order = v, o
    else
        values, order = item.values, item.order
    end
    if type(values) ~= "table" then return nil end
    order = order or DUI.Widgets.SortedKeys(values)
    local out = {}
    for _, k in ipairs(order) do
        if values[k] ~= nil then out[#out + 1] = { key = tostring(k), text = T(tostring(values[k])) } end
    end
    return out
end

-- The texts the search box matches (Options.Matches), as shown.
local function searchOf(group, item)
    if item.noSearch then return nil end
    local out = {}
    for _, s in ipairs({ item.label, item.desc, item.text, group.label }) do
        if type(s) == "string" and s ~= "" then out[#out + 1] = T(s) end
    end
    return out
end

local function entry(where, page, group, item)
    local label = Options.Label(item)
    local e = {
        rail = where.rail, section = where.section, page = where.page, tab = where.tab,
        card = str(group.label), pick = item.pickLabel and T(item.pickLabel) or nil,
        label = label, desc = str(item.desc), type = item.type,
        scope = group.module or page.scope,
        key = type(item.key) == "string" and Options.Key(page, item.key) or nil,
    }
    local parts = { e.rail, e.page }
    if e.tab then parts[#parts + 1] = e.tab end
    if e.card then parts[#parts + 1] = e.card end
    if e.pick then parts[#parts + 1] = e.pick end
    parts[#parts + 1] = label
    e.path = table.concat(parts, SEP)
    e.module = moduleOf(e.scope)
    if item.type == "dropdown" then
        e.choices = choicesOf(item)
        e.choicesVary = item.choices ~= nil or nil
    elseif item.type == "slider" then
        e.min, e.max, e.step, e.unit = item.min, item.max, item.step, item.unit
    elseif item.type == "button" then
        e.button = str(item.text) or label
    end
    e.search = searchOf(group, item)
    e.searchable = e.search ~= nil
    -- Facts about the row, not about whoever ran the command, so the file
    -- only changes when the options do.
    e.since = item.since
    e.conditional = (item.hidden ~= nil or item.disabled ~= nil or page.locked ~= nil) or nil
    e.pageConditional = where.pageConditional
    e.reload = item.reload or nil
    e.restart = type(item.restart) == "string" and T(item.restart) or nil
    return e
end

-- Rows a player can act on. Text and custom rows draw their own content.
local SKIP = { text = true, custom = true }

function Map.Build()
    local settings, errors = {}, {}
    for _, section in ipairs(Options.Sections(true)) do
        if not section.plugin then
            local rail = DUI.OptionsTheme.Section(section.id).short
            for _, page in ipairs(section.pages) do
                local where = { rail = rail, section = T(section.label), page = T(page.label),
                                pageConditional = page.hidden ~= nil or nil }
                -- A card's tab is its group's, else the previous card's; cards
                -- before the first named one go on the first tab (W.Page).
                local first
                for _, group in ipairs(page.groups or {}) do first = first or group.tab end
                local tab = first
                for _, group in ipairs(page.groups or {}) do
                    tab = group.tab or tab
                    where.tab = tab and T(tab) or nil
                    for _, item in ipairs(group.items or {}) do
                        if not SKIP[item.type] then
                            local ok, e = pcall(entry, where, page, group, item)
                            if ok then
                                settings[#settings + 1] = e
                            else
                                errors[#errors + 1] = tostring(page.id) .. ": " .. tostring(e)
                            end
                        end
                    end
                end
            end
        end
    end
    return settings, errors
end

-- Daylight UI addons installed but not loaded. Their rows are missing.
function Map.Missing()
    local A, out = C_AddOns, {}
    if not (A and A.GetNumAddOns and A.GetAddOnInfo and A.IsAddOnLoaded) then return out end
    for i = 1, A.GetNumAddOns() do
        local name = A.GetAddOnInfo(i)
        if type(name) == "string" and name:find("^DaylightUI_") and name ~= "DaylightUI_Dev"
            and not A.IsAddOnLoaded(name) then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

function Map.Save()
    local settings, errors = Map.Build()
    local missing = Map.Missing()
    local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
    _G.DaylightUIOptionsMap = {
        version = DUI.VERSION, locale = locale, made = type(date) == "function" and date("!%Y-%m-%dT%H:%M:%SZ") or nil,
        missing = missing, errors = errors, settings = settings,
    }
    DUI.Print(string.format(L["Options map: %d settings saved. Type /reload to write the file."], #settings))
    if locale ~= "enUS" and locale ~= "enGB" then
        DUI.Print(string.format(L["Options map: this client shows %s text, not English."], locale))
    end
    if #missing > 0 then
        DUI.Print(string.format(L["Options map: not loaded, so left out: %s"], table.concat(missing, ", ")))
    end
    if #errors > 0 then
        DUI.Print(string.format(L["Options map: %d rows could not be read: %s"], #errors, errors[1]))
    end
    return settings
end

DUI.RegisterCommand("optionsmap", Map.Save,
    L["/dui optionsmap - save every setting as the options window shows it, for Options/options-map.json"])
