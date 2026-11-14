-- Plugins are other people's addons built on top of DaylightUI, like ElvUI
-- plugins (whole feature suites welcome). A plugin registers once with
-- DaylightUI.RegisterPlugin and then adds one or more modules
-- (DaylightUI:RegisterModule with plugin = its name). Their settings are saved
-- in profiles and share strings like the built-in ones, and their pages go in
-- the plugin's own section of the options window, under a Plugins heading in
-- the sidebar with its own icon and color. General > Plugins lists every
-- plugin and profile pack, credited to its author.
--
-- DUI.API is the version promise to plugin authors: minor goes up when
-- something is added, major only when something promised changes or is
-- removed. A plugin states what it needs (needs = { 1, 0 }). One that needs
-- a newer version, or was made for another major, stays off with one line in
-- chat instead of an error.
--
-- DaylightUI:RegisterPlugin("MyPlugin", {
--     -- title, author, version, website, desc default to the .toc fields
--     -- (Title, Author, Version, X-Website, Notes). addon = its folder,
--     -- when that differs from the plugin's name.
--     needs = { 1, 0 },
--     icon = "Interface\\AddOns\\MyPlugin\\icon.png",   -- white on transparent, tinted with color
--     color = { 0.4, 0.8, 0.6 },                         -- or "66cc99"
--     short = "Mine",                                    -- its one-word name in the sidebar
--     blurb = "One line for the sidebar tooltip.",
-- })
-- DaylightUI:RegisterModule("MyPluginBars", { plugin = "MyPlugin", label = "Bars", options = ..., OnEnable = ... })

local _, DUI = ...
local L = DUI.L

local Plugins = {}
DUI.Plugins = Plugins

DUI.API = { major = 1, minor = 5 }

Plugins.ORDER = 2000 -- plugin sections go after all built-in ones (News is 1000), under their heading
Plugins.list, Plugins.order = {}, {}

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

-- A mistake by a plugin author: raise an error naming the call, pointing at their file.
local function pluginError(text) error("DaylightUI.RegisterPlugin: " .. text, 3) end

-- A .toc field with color codes stripped (titles often have them).
local function meta(addon, field)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    local ok, v = pcall(get or error, addon, field)
    if not ok or type(v) ~= "string" then return nil end
    v = string.gsub(string.gsub(v, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
    return str(strtrim(v))
end

-- needs: a major number, { major, minor }, or "major.minor". Missing means
-- the first API (1.0), so a plugin that never said turns off once major moves.
function Plugins.ParseNeeds(needs)
    if type(needs) == "number" then return { math.floor(needs), 0 } end
    if type(needs) == "string" then
        local a, b = string.match(needs, "^(%d+)%.?(%d*)$")
        if a then return { tonumber(a), tonumber(b) or 0 } end
    end
    if type(needs) == "table" and type(needs[1]) == "number" then
        return { math.floor(needs[1]), type(needs[2]) == "number" and math.floor(needs[2]) or 0 }
    end
    return { 1, 0 }
end

-- Whether a plugin needing { major, minor } runs on this version. Returns
-- true, or false and a reason for the player.
function Plugins.Fits(needs, title)
    local api = DUI.API
    if needs[1] == api.major and needs[2] <= api.minor then return true end
    if needs[1] > api.major or (needs[1] == api.major and needs[2] > api.minor) then
        return false, string.format(L["%s needs a newer DaylightUI: update DaylightUI to use it."], title)
    end
    return false, string.format(L["%s was made for an older DaylightUI and is off: look for an update of it."], title)
end

local function color(v)
    if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" then
        return { v[1], v[2], v[3] }
    end
    local hex = type(v) == "string" and string.match(v, "^#?(%x%x%x%x%x%x)$")
    if hex then
        return { tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255,
                 tonumber(string.sub(hex, 5, 6), 16) / 255 }
    end
end

-- Called as DaylightUI.RegisterPlugin(name, spec) or
-- DaylightUI:RegisterPlugin(name, spec), like RegisterModule. Returns the plugin.
function Plugins.Register(name, spec, extra)
    if name == DUI then name, spec = spec, extra end
    if not str(name) then pluginError("the plugin needs a name (a string)") end
    if Plugins.list[name] then pluginError(string.format("there's a plugin called %s already", name)) end
    if spec ~= nil and type(spec) ~= "table" then pluginError("the second argument is a table of what it is") end
    spec = spec or {}
    local addon = str(spec.addon) or name
    local p = {
        name = name, addon = addon,
        title = str(spec.title) or meta(addon, "Title") or name,
        author = str(spec.author) or meta(addon, "Author"),
        version = spec.version ~= nil and tostring(spec.version) or meta(addon, "Version"),
        website = str(spec.website) or meta(addon, "X-Website"),
        desc = str(spec.desc) or meta(addon, "Notes"),
        needs = Plugins.ParseNeeds(spec.needs),
        section = "plugin:" .. name,
        modules = {},
    }
    local ok, why = Plugins.Fits(p.needs, p.title)
    if not ok then
        p.off, p.why = true, why
        DUI.Print(why)
    else
        local O = DUI.Options
        O.RegisterSection(p.section, p.title, Plugins.ORDER + #Plugins.order).plugin = name
        local Theme = DUI.OptionsTheme
        local c = color(spec.color) or Theme.GradientAt(#Plugins.order / 6)
        Theme.SECTIONS[p.section] = { color = c, icon = spec.icon or Theme.FALLBACK_ICON,
            short = str(spec.short) or p.title, blurb = str(spec.blurb) or p.desc or p.title }
    end
    Plugins.list[name] = p
    Plugins.order[#Plugins.order + 1] = name
    DUI.Fire("PluginsChanged", name)
    return p
end
DUI.RegisterPlugin = Plugins.Register

-- Called as a plugin's module is enabled (Core.lua EnableModule). Returns
-- true to go on, false while its plugin is off. Its pages go in the plugin's
-- section (unless it asked for another), one module after another.
function Plugins.Adopt(mod)
    local p = Plugins.list[mod.plugin]
    if not p then
        DUI.Print(string.format(L["%s says it's part of the plugin %s, which hasn't registered (DaylightUI.RegisterPlugin); it's shown on its own."],
            mod.label or mod.name, tostring(mod.plugin)))
        return true
    end
    if p.off then return false end
    mod.pluginTitle = p.title
    if not mod.section then
        mod.section = p.section
        mod.pageOrder = mod.pageOrder or #p.modules * 100
    end
    p.modules[#p.modules + 1] = mod.name
    return true
end

-- Every plugin, in the order they registered.
function Plugins.All()
    local out = {}
    for i, name in ipairs(Plugins.order) do out[i] = Plugins.list[name] end
    return out
end

-- The first options page of a plugin's section, or nil.
function Plugins.FirstPage(p)
    for _, s in ipairs(DUI.Options.Sections()) do
        if s.id == p.section and s.pages[1] then return s.pages[1].id end
    end
end

-- General > Plugins: every plugin and profile pack, credited

local function credit(author, version)
    local by = author and string.format(L["By %s."], author)
    local v = version and string.format(L["Version %s."], tostring(version))
    return by and v and (by .. " " .. v) or by or v
end

local function join(...)
    local out = {}
    for i = 1, select("#", ...) do
        local s = select(i, ...)
        if s then out[#out + 1] = s end
    end
    return #out > 0 and table.concat(out, " ") or nil
end

-- How each kind of frame reads in a sentence ("Paints cast bars.").
Plugins.KIND_WORDS = { castbar = "cast bars", unit = "unit frames", party = "party frames", raid = "raid frames",
    partypet = "party pets", nameplate = "nameplates", actionbutton = "action buttons", shoptile = "the vendor's items",
    craftrow = "recipes", questrow = "the quest tracker", bagslot = "bag slots" }
Plugins.KIND_ORDER = { "unit", "party", "raid", "partypet", "castbar", "nameplate", "actionbutton", "questrow",
    "bagslot", "shoptile", "craftrow" }

local function listed(words)
    if #words == 1 then return words[1] end
    return string.format(L["%s and %s"], table.concat(words, ", ", 1, #words - 1), words[#words])
end

-- One line on what an addon changes through DaylightUI.API (what it paints,
-- the texts and settings it adds, the functions it hooks), or nil.
function Plugins.ChangesLine(name)
    local c = DUI.APIReport.Changes(name)
    if not c then return nil end
    local out = {}
    local kinds = {}
    for _, kind in ipairs(Plugins.KIND_ORDER) do
        if (c.paints[kind] or 0) > 0 then kinds[#kinds + 1] = L[Plugins.KIND_WORDS[kind]] end
    end
    if #kinds > 0 then out[#out + 1] = string.format(L["Paints %s."], listed(kinds)) end
    if c.texts > 0 then
        out[#out + 1] = string.format(c.texts == 1 and L["Adds %d text."] or L["Adds %d texts."], c.texts)
    end
    if c.defaults > 0 then
        out[#out + 1] = string.format(c.defaults == 1 and L["Adds %d group of settings."] or L["Adds %d groups of settings."], c.defaults)
    end
    if c.hooks > 0 then
        out[#out + 1] = string.format(c.hooks == 1 and L["Hooks %d function."] or L["Hooks %d functions."], c.hooks)
    end
    if #out == 0 then return nil end
    return table.concat(out, " ")
end

-- On or off for this character, as the AddOns list sets it (needs a reload).
local function addonSwitch(addon)
    local P = DUI.InstallerPages
    return { type = "toggle", label = "On for this character", reload = true,
        desc = "Off, the addon stays installed but doesn't load on this character after a reload.",
        hidden = function() return not P.AddonInstalled(addon) end,
        get = function() return P.AddonOn(addon) end,
        set = function(v)
            local api, me = C_AddOns, P.Character()
            if not (api and me) then return end
            if v then api.EnableAddOn(addon, me) else api.DisableAddOn(addon, me) end
        end,
        default = function() return true end }
end

local function changesRow(name)
    return { type = "text", label = function() return Plugins.ChangesLine(name) or "" end,
        hidden = function() return Plugins.ChangesLine(name) == nil end }
end

local function pluginGroup(p)
    local items = {}
    if p.off then
        items[#items + 1] = { type = "text", label = function() return p.why end }
    else
        items[#items + 1] = { type = "button", label = p.title, text = "Open",
            desc = "Its own section in the list on the left, under Plugins.",
            hidden = function() return Plugins.FirstPage(p) == nil end,
            func = function() DUI.OptionsPanel.Show(Plugins.FirstPage(p)) end }
    end
    if p.website then
        items[#items + 1] = { type = "text", label = function() return string.format(L["Website: %s"], p.website) end }
    end
    items[#items + 1] = changesRow(p.name)
    items[#items + 1] = addonSwitch(p.addon)
    return { label = p.title, desc = join(credit(p.author, p.version), p.desc), items = items }
end

-- An addon that uses DaylightUI.API without registering as a plugin. Listed
-- under the name it gave, with a switch if that name is an addon.
local function looseGroup(name)
    return { label = name, desc = L["Uses Daylight UI's API without registering as a plugin."],
        items = { changesRow(name), addonSwitch(name) } }
end

local function packGroup(pack)
    local n = #DUI.Profiles.PackProfiles(pack)
    return { label = pack.label, desc = join(credit(pack.author, pack.version), pack.desc), items = {
        { type = "button", label = pack.label, text = "Profiles",
          desc = "Its ready-made profiles are on the Profiles page and in the setup guide.",
          func = function() DUI.OptionsPanel.Show("profiles") end },
        { type = "text", label = function()
              return string.format(n == 1 and L["%d ready-made profile"] or L["%d ready-made profiles"], n)
          end },
    } }
end

local function groups()
    local out = {}
    for _, p in ipairs(Plugins.All()) do out[#out + 1] = pluginGroup(p) end
    for _, name in ipairs(DUI.APIReport and DUI.APIReport.Changers() or {}) do
        if not Plugins.list[name] then out[#out + 1] = looseGroup(name) end
    end
    for _, id in ipairs(DUI.Profiles.PACK_ORDER) do out[#out + 1] = packGroup(DUI.Profiles.PACKS[id]) end
    return out
end

-- Built with the first plugin or pack (no page if none are installed) and
-- rebuilt as each one registers. Their addons load after ours but before the
-- window first draws the page, same as the Profiles page's pack cards.
local page
local function rebuild()
    if page then
        page.groups = groups()
        return
    end
    page = DUI.Options.RegisterPage({
        id = "plugins", section = "core", label = "Plugins", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
        order = 900,
        desc = "Addons made by other people on top of DaylightUI: plugins with features of their own, and profile packs with ready-made setups.",
        groups = groups(),
    })
end
DUI.On("PluginsChanged", rebuild)
DUI.On("PacksChanged", rebuild)
