-- Options registry. Sections and pages are plain data, validated against the
-- defaults they edit. The window draws whatever is registered, so a module
-- can add its own pages without touching window code.
--
-- Page:  { id, section, label, desc?, scope, defaults, groups, hidden? }
--        hidden(get) returning true unlists the page entirely.
-- Group: a card { label, desc?, tab?, items }. tab starts a new tab on long
--        pages; later cards belong to it until the next tab.
-- Items:
--   toggle   { key, label }
--   slider   { key, label, min, max, step?, unit? ("%", "px" or "x") }
--   dropdown { key, label, values = { key = text }, order? }   or choices() returning values, order;
--                                               fallback (key shown when the saved one is gone), onPick(k),
--                                               preview ("font"/"bar") with fetch(k) giving the file
--   button   { label, text?, func, confirm? }   text may be a function
--   text     { label }                          label may be a function
--   color    { key, label, alpha? }             the value is { r, g, b(, a) }; a swatch opens the color picker
--   custom   { label, build(row), update?(row), height?(row) }   draws its own row; never searched
--   gradient { label, get, set, default? }      the value is { lo = rgb, hi = rgb }: a preview and two swatches;
--                                               preview() may give the preview's two ends instead
-- Toggles may set invert = true to show the value flipped.
-- Any item may have:
--   desc           hover text
--   disabled(get), hidden(get)   get(key) reads another setting in the scope
--   reload = true  a change prompts for a reload
--   restart = "sentence"   shown with only an Okay, for things the game reads at startup
--   noSearch = true   leave it out of search (e.g. a row duplicated on another page)
--   alsoKeys = { keys }   other settings a get/set row also writes, for jumps
-- Value items can use get()/set(v) instead of a key, plus default() to
-- support reset. A page's resetAll() runs first on Reset page.

local _, DUI = ...
local L = DUI.L

local Options = {}
DUI.Options = Options

-- Item tables hold English text and get translated only when drawn, since
-- one table can sit on two pages and code reads `values` directly.
function Options.Text(s)
    if type(s) == "string" then return L[s] end
    return s
end

local sections, pages = {}, {}

local KNOWN = { toggle = true, slider = true, dropdown = true, button = true, text = true, custom = true, color = true, gradient = true }
local VALUE = { toggle = true, slider = true, dropdown = true, color = true, gradient = true }
-- s = seconds, c = copper.
local UNITS = { ["%"] = true, px = true, x = true, s = true, c = true }
Options.VALUE = VALUE

-- Runs on every page at login, so it allocates nothing for valid items.
local failErrors, failWhere, failAt
local function fail(msg) failErrors[#failErrors + 1] = failWhere .. "[" .. failAt .. "]: " .. msg end

function Options.Validate(items, defaults, errors, where)
    errors = errors or {}
    where = where or "options"
    failErrors, failWhere = errors, where
    for i, item in ipairs(items) do
        failAt = i
        local labelOk = type(item.label) == "string" or (item.type == "text" and type(item.label) == "function")
        if not KNOWN[item.type] then
            fail("unknown type " .. tostring(item.type))
        elseif not labelOk then
            fail("missing label")
        elseif item.desc ~= nil and type(item.desc) ~= "string" then
            fail("desc is not a string")
        elseif item.disabled ~= nil and type(item.disabled) ~= "function" then
            fail("disabled is not a function")
        elseif item.hidden ~= nil and type(item.hidden) ~= "function" then
            fail("hidden is not a function")
        elseif item.type == "button" then
            if type(item.func) ~= "function" then fail("button without func") end
        elseif item.type == "custom" then
            if type(item.build) ~= "function" then fail("custom without build") end
        elseif item.ends ~= nil then
            -- A bar end's menu (Options.EndRows): two switches behind one dropdown.
            local e = item.ends
            if item.type ~= "dropdown" or type(e) ~= "table" or (e.side ~= "left" and e.side ~= "right") then
                fail("ends needs a dropdown and a side")
            elseif item.key ~= e.on then
                fail("ends: key is not its angled switch")
            elseif type(DUI.DB.GetPath(defaults, e.on)) ~= "boolean" or type(DUI.DB.GetPath(defaults, e.flip or "")) ~= "boolean" then
                fail("ends: " .. tostring(e.on) .. " or " .. tostring(e.flip) .. " has no true/false default")
            end
        elseif VALUE[item.type] and (item.get or item.set) then
            if type(item.get) ~= "function" or type(item.set) ~= "function" then fail("get without set")
            elseif item.default ~= nil and type(item.default) ~= "function" then fail("default is not a function") end
        elseif item.type == "gradient" then
            fail("gradient without get and set")
        elseif VALUE[item.type] then
            local d = type(item.key) == "string" and DUI.DB.GetPath(defaults, item.key)
            if type(item.key) ~= "string" then
                fail("missing key")
            elseif d == nil then
                fail("no default for " .. item.key)
            elseif item.type == "toggle" and type(d) ~= "boolean" then
                fail(item.key .. " default is not a boolean")
            elseif item.type == "slider" then
                if type(item.min) ~= "number" or type(item.max) ~= "number" or item.min >= item.max then
                    fail(item.key .. " has a bad range")
                elseif item.step ~= nil and (type(item.step) ~= "number" or item.step <= 0) then
                    fail(item.key .. " has a bad step")
                elseif item.unit ~= nil and not UNITS[item.unit] then
                    fail(item.key .. " has an unknown unit")
                elseif type(d) ~= "number" or d < item.min or d > item.max then
                    fail(item.key .. " default is outside the range")
                end
            elseif item.type == "dropdown" then
                local values = item.values
                if item.choices then values = item.choices() end
                if type(values) ~= "table" or values[d] == nil then
                    fail(item.key .. " default is not one of the values")
                end
            elseif item.type == "color" then
                if type(d) ~= "table" or type(d[1]) ~= "number" or type(d[2]) ~= "number" or type(d[3]) ~= "number" then
                    fail(item.key .. " default is not an { r, g, b } color")
                end
            end
        end
    end
    return errors
end

function Options.ValidatePage(page, errors)
    errors = errors or {}
    if page.hidden ~= nil and type(page.hidden) ~= "function" then
        errors[#errors + 1] = tostring(page.id) .. ": hidden is not a function"
    end
    if type(page.groups) ~= "table" or #page.groups == 0 then
        errors[#errors + 1] = tostring(page.id) .. ": no groups"
        return errors
    end
    for g, group in ipairs(page.groups) do
        local at = page.id .. ".groups[" .. g .. "]"
        if type(group.label) ~= "string" then errors[#errors + 1] = at .. ": missing label" end
        if group.tab ~= nil and (type(group.tab) ~= "string" or group.tab == "") then errors[#errors + 1] = at .. ": tab is not a name" end
        Options.Validate(group.items or {}, page.defaults or {}, errors, at)
    end
    return errors
end

-- ---------------------------------------------------------------------
-- Sections and pages
-- ---------------------------------------------------------------------

function Options.RegisterSection(id, label, order)
    if not sections[id] then
        sections[id] = { id = id, label = label, order = order or 100, pages = {} }
    end
    return sections[id]
end

function Options.RegisterPage(page)
    assert(not pages[page.id], "options page already registered: " .. tostring(page.id))
    local section = assert(sections[page.section], "unknown options section: " .. tostring(page.section))
    for _, e in ipairs(Options.ValidatePage(page)) do DUI.Print(string.format(L["Options (%s): %s"], page.id, e)) end
    page.order = page.order or (#section.pages + 1) * 10
    pages[page.id] = page
    section.pages[#section.pages + 1] = page
    table.sort(section.pages, function(a, b) return a.order < b.order end)
    DUI.Fire("OptionsChanged")
    return page
end

local function pageShown(page)
    return page.hidden == nil or page.hidden(Options.Getter(page)) ~= true
end

-- Returns nil for a hidden page so it can't be opened.
function Options.GetPage(id)
    local page = pages[id]
    if page and pageShown(page) then return page end
end

-- Sections in window order, each holding its shown pages in order.
function Options.Sections()
    local list = {}
    for _, s in pairs(sections) do
        local shown = {}
        for _, p in ipairs(s.pages) do
            if pageShown(p) then shown[#shown + 1] = p end
        end
        list[#list + 1] = setmetatable({ pages = shown }, { __index = s })
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return list
end

-- A visible section by id, with its visible pages in order, or nil.
function Options.Section(id)
    for _, s in ipairs(Options.Sections()) do
        if s.id == id then return s end
    end
end

-- Every page, in window order.
function Options.Pages()
    local list = {}
    for _, s in ipairs(Options.Sections()) do
        for _, p in ipairs(s.pages) do list[#list + 1] = p end
    end
    local i = 0
    return function()
        i = i + 1
        local p = list[i]
        if p then return p.id, p end
    end
end

-- A module's options: { pages = { { id, label, desc?, preview?, groups } } }.
-- They get a section named after the module, with the module as scope.
-- preview lists the test parts the "Test frame" switch shows.
-- sample(parent) builds the live sample (Options/SampleStrip.lua).
-- mod.section files the pages under another section, ordered by
-- mod.pageOrder. Skins and the extra windows go under Extras this way.
function Options.RegisterModule(mod)
    if mod.windowCard then return Options.AddWindowCard(mod) end
    local section = mod.section or mod.name
    if not mod.section then Options.RegisterSection(mod.name, mod.label or mod.name, mod.order or 100) end
    for i, p in ipairs(mod.options.pages or {}) do
        Options.RegisterPage({
            id = mod.name .. "." .. tostring(p.id), section = section, label = p.label, desc = p.desc,
            order = (mod.pageOrder or 0) + i * 10, scope = mod.name, defaults = mod.defaults or {}, groups = p.groups,
            preview = p.preview, sample = p.sample, hidden = p.hidden, mapKey = p.mapKey, locked = p.locked,
            onShow = p.onShow, hideLocked = p.hideLocked,
        })
    end
end

-- Smaller windows (mod.windowCard: spellbook, inspect, professions, group
-- finder, mail, social, Legacy) share one Extras > Windows page with a card
-- each, rather than a near-empty page each. Rows still read and write their
-- own module's settings through get/set/default.
Options.WINDOWS_PAGE = "windows"
local windowsPage
function Options.AddWindowCard(mod)
    local defaults = mod.defaults or {}
    local function get(key) return DUI:Get(mod.name, key) end
    for _, p in ipairs(mod.options.pages or {}) do
        local items = {}
        for _, group in ipairs(p.groups or {}) do
            for _, e in ipairs(Options.Validate(group.items, defaults, nil, mod.name .. "." .. tostring(p.id))) do
                DUI.Print(string.format(L["Options (%s): %s"], Options.WINDOWS_PAGE, e))
            end
            for _, src in ipairs(group.items) do
                local item = {}
                for k, v in pairs(src) do item[k] = v end
                if VALUE[src.type] and not src.get then
                    item.get = function() return DUI:Get(mod.name, src.key) end
                    item.set = function(v) DUI:Set(mod.name, src.key, v) end
                    item.default = function() return DUI.DB.GetPath(defaults, src.key) end
                end
                if src.disabled then item.disabled = function() return src.disabled(get) end end
                if src.hidden then item.hidden = function() return src.hidden(get) end end
                items[#items + 1] = item
            end
        end
        local card = { label = p.label, desc = p.desc, items = items }
        if windowsPage then
            windowsPage.groups[#windowsPage.groups + 1] = card
            DUI.Fire("OptionsChanged")
        else
            windowsPage = Options.RegisterPage({ id = Options.WINDOWS_PAGE, section = mod.section, label = "More windows",
                desc = "Spellbook, inspect, professions, group finder, mailbox, social and Legacy: each window's switch, its size and its own extras.",
                order = (mod.pageOrder or 0) + 10, scope = "general", defaults = {}, groups = { card } })
        end
    end
end

-- ---------------------------------------------------------------------
-- Values, defaults, state
-- ---------------------------------------------------------------------

-- page.mapKey(key) redirects rows to other settings, e.g. the Raid page
-- editing the 10, 20 or 40 player setup. page.locked(key, item) grays a
-- row out and keeps Reset page away from it.
function Options.Key(page, key)
    if page and page.mapKey and type(key) == "string" then return page.mapKey(key) or key end
    return key
end

-- page may be nil for a standalone switch with its own get/set (Test frame).
-- A row with no setting of its own (a preview) locks with item.lockWith's.
function Options.Locked(page, item)
    return page ~= nil and page.locked ~= nil and page.locked(item.key or item.lockWith, item) == true
end

-- One cached reader per page. A fresh closure on every IsHidden/IsDisabled
-- call made garbage on each refresh and keystroke.
local getters = setmetatable({}, { __mode = "k" })
function Options.Getter(page)
    local g = getters[page]
    if not g then
        g = function(key) return DUI:Get(page.scope, Options.Key(page, key)) end
        getters[page] = g
    end
    return g
end

-- item.invert shows a switch flipped, so a "Hide X" setting can read
-- "Show X" without changing anyone's saved value.
local function saved(page, item)
    if item.get then return item.get() end
    local e = item.ends
    if e then
        return DUI.Style.EndGlyph(e.side, DUI:Get(page.scope, Options.Key(page, e.on)),
            DUI:Get(page.scope, Options.Key(page, e.flip)))
    end
    return DUI:Get(page.scope, Options.Key(page, item.key))
end

-- The choices of every bar end's menu, in order.
Options.END_VALUES = { straight = "Straight", slash = "Leans /", backslash = "Leans \\" }
Options.END_ORDER = { "straight", "slash", "backslash" }

-- A bar's two end menus, one per end, each read from and written to two
-- switches: whether that end is angled, and whether it's flipped (its bottom
-- corner out). o.name names the bar in both labels ("Cast bar"), o.left and
-- o.right are { on = key, flip = key } plus their own optional disabled,
-- hidden and note; o.disabled, o.hidden, o.note and o.since apply to both.
-- Returns the two rows, left first.
function Options.EndRows(o)
    local rows = {}
    for _, side in ipairs({ "left", "right" }) do
        local e = o[side]
        local note = (e.note and (" " .. e.note) or "") .. (o.note and (" " .. o.note) or "")
        local own, all = e.disabled, o.disabled
        local ownH, allH = e.hidden, o.hidden
        rows[#rows + 1] = {
            type = "dropdown", key = e.on, alsoKeys = { e.flip },
            ends = { side = side, on = e.on, flip = e.flip },
            label = o.name .. " " .. side .. " end", since = o.since,
            values = Options.END_VALUES, order = Options.END_ORDER,
            desc = "Straight, or angled either way. On the right end / puts the top corner out and \\ the bottom one; on the left end it's the other way round. Each end is set on its own." .. note,
            disabled = (own or all) and function(get) return (all and all(get)) or (own and own(get)) or false end or nil,
            hidden = (ownH or allH) and function(get) return (allH and allH(get)) or (ownH and ownH(get)) or false end or nil,
        }
    end
    return rows
end

function Options.Get(page, item)
    local v = saved(page, item)
    if item.invert then return v ~= true end
    return v
end

-- item.reload: some game frames are only built at login and addon code
-- can't redo that, so prompt for a reload with the core's usual prompt.
local function askReload(item)
    if DUI.EditMode and DUI.EditMode.AskReload then
        DUI.EditMode.AskReload(string.format(L["%s needs a reload to take effect. Reload now?"], Options.Label(item) or L["This setting"]))
    end
end

-- item.restart: the game only reads this at startup. Show the sentence
-- with just an Okay so it can't be missed.
local function tellRestart(item)
    DUI.Widgets.Ask({ key = "restart", text = L[item.restart], yes = OKAY or L["Okay"], no = false })
end

function Options.Set(page, item, value)
    if Options.Locked(page, item) then return false end
    if item.invert then value = value ~= true end
    -- `value` is the saved value here, not the displayed (inverted) one.
    local before = (item.reload or item.restart) and saved(page, item)
    local ok
    if item.set then
        ok = item.set(value) ~= false   -- only an explicit false means refused
    elseif item.ends then
        -- Straight clears the flip too, so nothing is left saved for that end.
        local e = item.ends
        local on, flip = DUI.Style.EndFromGlyph(e.side, value)
        ok = DUI:Set(page.scope, Options.Key(page, e.flip), flip)
        ok = DUI:Set(page.scope, Options.Key(page, e.on), on) and ok
    else
        ok = DUI:Set(page.scope, Options.Key(page, item.key), value)
    end
    if ok and before ~= value then
        if item.reload then askReload(item) end
        if item.restart then tellRestart(item) end
    end
    return ok
end

-- While a slider is dragged on a page with a preview (Options.previewer),
-- write the value quietly so only the preview redraws. The caller Sets it
-- on release. Returns false when there's no preview: Set as usual.
-- item.onRelease: a slider whose every step would be costly (the UI scale
-- resizes the whole interface) is set once, when it's let go.
function Options.Preview(page, item, value)
    if item.onRelease then return not Options.Locked(page, item) end
    if item.set or item.reload or not Options.previewer or Options.Locked(page, item) then return false end
    return Options.previewer(page, item, value) == true
end

function Options.Default(page, item)
    local d
    if item.get then
        d = item.default and item.default()
    elseif item.ends then
        local e, defaults = item.ends, page.defaults or {}
        d = DUI.Style.EndGlyph(e.side, DUI.DB.GetPath(defaults, Options.Key(page, e.on)),
            DUI.DB.GetPath(defaults, Options.Key(page, e.flip)))
    else
        d = DUI.DB.GetPath(page.defaults or {}, Options.Key(page, item.key))
    end
    if item.invert and d ~= nil then return d ~= true end
    return d
end

local function sameRGB(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for i = 1, 3 do
        if type(a[i]) ~= "number" or type(b[i]) ~= "number" or math.abs(a[i] - b[i]) > 1e-3 then return false end
    end
    return true
end

local function copyRGB(c) return { c[1], c[2], c[3] } end

-- A row with its own get and item.reset (no default) is changed while
-- item.isSet() says it holds a value. Its reset clears it to nil.
function Options.IsDefault(page, item)
    if not VALUE[item.type] then return true end
    if item.get and item.reset and item.isSet then return not item.isSet() end
    if item.get and not item.default then return true end
    local v, d = Options.Get(page, item), Options.Default(page, item)
    if type(v) == "number" and type(d) == "number" then return math.abs(v - d) < 1e-6 end
    if item.type == "gradient" and type(v) == "table" and type(d) == "table" then
        return sameRGB(v.lo, d.lo) and sameRGB(v.hi, d.hi)
    end
    if type(v) == "table" and type(d) == "table" then return sameRGB(v, d) end
    return v == d
end

function Options.ResetItem(page, item)
    if Options.Locked(page, item) or Options.IsDefault(page, item) then return end
    if item.get and item.reset and not item.default then
        Options.Set(page, item, nil)
        return
    end
    local d = Options.Default(page, item)
    -- Copy colors so the setting never shares the default's table.
    if item.type == "gradient" and type(d) == "table" then
        d = { lo = copyRGB(d.lo), hi = copyRGB(d.hi) }
    elseif type(d) == "table" then
        d = copyRGB(d)
    end
    Options.Set(page, item, d)
end

function Options.ResetPage(page)
    if page.resetAll then page.resetAll() end
    for _, group in ipairs(page.groups) do
        for _, item in ipairs(group.items) do Options.ResetItem(page, item) end
    end
end

function Options.HasValues(page)
    for _, group in ipairs(page.groups) do
        for _, item in ipairs(group.items) do
            if VALUE[item.type] then return true end
        end
    end
    return false
end

function Options.IsDisabled(page, item)
    if Options.Locked(page, item) then return true end
    return item.disabled ~= nil and item.disabled(Options.Getter(page)) == true
end

-- page.hideLocked hides locked rows instead of graying them (Raid 20 and 40
-- while they follow Raid 10).
function Options.IsHidden(page, item)
    if page.hideLocked and Options.Locked(page, item) then return true end
    return item.hidden ~= nil and item.hidden(Options.Getter(page)) == true
end

-- An item's displayed label, resolving label functions.
function Options.Label(item)
    if type(item.label) == "function" then return Options.Text(item.label()) end
    return Options.Text(item.label)
end

-- ---------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------

-- Matches both the translated text and the English, since support and most
-- guides use English.
local function has(text, query)
    if type(text) ~= "string" then return false end
    if string.find(string.lower(text), query, 1, true) ~= nil then return true end
    local shown = L[text]
    return shown ~= text and string.find(string.lower(shown), query, 1, true) ~= nil
end

-- Matches an item's label, description, button text, card title or its
-- search words (the name players know a setting by when the row doesn't
-- print it, like "paging" for the bars' page rows). Text items never match.
function Options.Matches(group, item, query)
    if query == nil or query == "" then return true end
    if item.type == "text" or item.type == "custom" or item.noSearch then return false end
    query = string.lower(query)
    return has(item.label, query) or has(item.desc, query) or has(item.text, query) or has(group.label, query)
        or has(item.search, query)
end

-- ---------------------------------------------------------------------
-- NEW tags. A row with since = "<version>" is tagged while that version is
-- newer than the player's baseline: the version they updated from
-- (Options.NoteVersion), or an older one picked on Home. Fresh characters
-- get no tags. Searching "new" lists them all.
-- ---------------------------------------------------------------------

Options.NEW_START = "1.5.0"   -- baseline for players from before NEW tags existed

function Options.NewSince()
    local db = DUI.DB
    return db.Root().newSince or (not db.Unsaved() and Options.NEW_START or nil)
end

function Options.IsNew(item)
    local base = Options.NewSince()
    return type(item.since) == "string" and base ~= nil and DUI.IsNewerVersion(item.since, base)
end

-- If the version changed since last login, count from the old one.
function Options.NoteVersion()
    local root = DUI.DB.Root()
    local was = root.lastVersion
    if type(was) == "string" and was ~= DUI.VERSION and DUI.IsNewerVersion(DUI.VERSION, was) then root.newSince = was end
    root.lastVersion = DUI.VERSION
end
DUI.On("Login", Options.NoteVersion)

-- Every version in the patch notes, newest first, for the Home row.
function Options.NewSinceChoices()
    local values, order = { none = L["Nothing, hide the tags"] }, {}
    for _, v in ipairs(DUI.PatchNotes or {}) do
        if v.version ~= "Unreleased" then
            values[v.version] = v.version
            order[#order + 1] = v.version
        end
    end
    order[#order + 1] = "none"
    return values, order
end

-- The languages Daylight UI's text comes in, each named in its own words,
-- after Automatic (the game's language).
function Options.LanguageChoices()
    local names = {}
    for _, lang in ipairs(DUI.LANGUAGES) do names[lang[1]] = lang[2] end
    local client = names[DUI.LANGUAGE_FILE[DUI.CLIENT_LOCALE] or DUI.CLIENT_LOCALE]
    local values = { auto = client and string.format(L["Automatic (%s)"], client) or L["Automatic"] }
    local order = { "auto" }
    for _, lang in ipairs(DUI.LANGUAGES) do
        values[lang[1]] = lang[2]
        order[#order + 1] = lang[1]
    end
    return values, order
end

-- A language's name drawn in a font that has its letters: the options' own
-- font may have no Russian, Korean or Chinese ones.
function Options.LanguageFont(locale)
    local body = DUI.Widgets.BODY
    local alphabet = DUI.OptionsTheme.ALPHABET[locale]
    if not alphabet or locale == DUI.CLIENT_LOCALE then return body end
    if alphabet == "russian" and DUI.Style.HasCyrillic(body) then return body end
    return DUI.Style.ALPHABET_FONTS[alphabet]
end

-- Typing "new" (any case, stray spaces too) also lists every row tagged NEW.
local function asksForNew(query)
    return string.lower(query):match("^%s*(.-)%s*$") == string.lower(L["NEW"])
end

-- Shared by results and counts: not a text item, matches, not hidden now.
local function found(page, group, item, query)
    if item.type == "text" or Options.IsHidden(page, item) then return false end
    return Options.Matches(group, item, query) or (asksForNew(query) and Options.IsNew(item))
end

-- Every visible setting matching query, in window order, as
-- { page, group, item }.
function Options.Search(query)
    local out = {}
    if query == nil or query == "" then return out end
    for _, page in Options.Pages() do
        for _, group in ipairs(page.groups) do
            for _, item in ipairs(group.items) do
                if found(page, group, item, query) then
                    out[#out + 1] = { page = page, group = group, item = item }
                end
            end
        end
    end
    return out
end

function Options.CountMatches(page, query)
    local n = 0
    for _, group in ipairs(page.groups) do
        for _, item in ipairs(group.items) do
            if found(page, group, item, query) then n = n + 1 end
        end
    end
    return n
end

-- ---------------------------------------------------------------------
-- Picker cards: one card for several similar things (heal indicators, bars)
-- with a "Settings for" row choosing which one the rows edit. Every choice's
-- rows stay in the card with real keys, hidden unless picked, so search,
-- Reset page, the setup guide and jumps still work. group.reveal(key)
-- selects the choice a key belongs to.
-- spec: { label, desc?, tab?, lead? (rows above the picker, shared),
--   pickDesc, pickHidden(get)?, choices = { { id, label, items } },
--   disabled(get)?, copy = { label, desc, button, buttonDesc, fn(fromId, toId), can(id)? }? }
-- ---------------------------------------------------------------------

local function refreshPanel()
    local P = DUI.OptionsPanel
    if P and P.IsShown and P.IsShown() then P.Refresh() end
end

function Options.PickCard(spec)
    local state = { pick = spec.choices[1].id }
    local values, order = {}, {}
    for _, c in ipairs(spec.choices) do values[c.id] = c.label; order[#order + 1] = c.id end
    local items = {}
    for _, item in ipairs(spec.lead or {}) do items[#items + 1] = item end
    local pickHidden = spec.pickHidden
    items[#items + 1] =
        { type = "dropdown", label = "Settings for", desc = spec.pickDesc, values = values, order = order,
          hidden = pickHidden,
          disabled = spec.disabled,
          get = function() return state.pick end,
          set = function(id) state.pick = id; state.from = nil; refreshPanel() end }
    local copy = spec.copy
    if copy then
        local function can(id) return copy.can == nil or copy.can(id) == true end
        items[#items + 1] = { type = "dropdown", label = copy.label, desc = copy.desc, noSearch = true,
            choices = function()
                local v, o = {}, {}
                for _, id in ipairs(order) do
                    if id ~= state.pick and can(id) then v[id] = values[id]; o[#o + 1] = id end
                end
                return v, o
            end,
            hidden = function() return not can(state.pick) end,
            disabled = spec.disabled,
            get = function() return state.from end,
            set = function(id) state.from = id; refreshPanel() end }   -- enables the Copy button
        items[#items + 1] = { type = "button", label = copy.button, text = "Copy", confirm = true, noSearch = true,
            desc = copy.buttonDesc,
            hidden = function() return not can(state.pick) end,
            disabled = function(get) return state.from == nil or (spec.disabled ~= nil and spec.disabled(get) == true) end,
            func = function()
                if state.from == nil or state.from == state.pick then return end
                copy.fn(state.from, state.pick)
                state.from = nil
            end }
    end
    local owner = {}
    for _, c in ipairs(spec.choices) do
        for _, item in ipairs(c.items) do
            local own = item.hidden
            -- Keep the original hidden() as baseHidden, the Fade page copies these rows.
            item.inPick, item.baseHidden = true, own
            item.hidden = function(get) return state.pick ~= c.id or (own ~= nil and own(get) == true) end
            if item.key then owner[item.key] = c.id end
            for _, also in ipairs(item.alsoKeys or {}) do owner[also] = c.id end
            items[#items + 1] = item
        end
    end
    local group = { label = spec.label, desc = spec.desc, tab = spec.tab, items = items }
    -- Selects the choice a key belongs to and returns true, else does nothing.
    function group.reveal(key)
        local id = owner[key]
        if id == nil then return false end
        if state.pick ~= id then state.pick = id; state.from = nil end
        return true
    end
    function group.Picked() return state.pick end
    return group
end

-- ---------------------------------------------------------------------
-- Core pages
-- ---------------------------------------------------------------------

local function movers() return DUI.Movers end

local function moduleList()
    local names = {}
    for _, mod in DUI.Modules() do
        if mod.enabled then names[#names + 1] = L[mod.label or mod.name] end
    end
    if #names == 0 then return L["No modules loaded yet. Turn on Daylight UI modules in the AddOns list."] end
    return string.format(L["Loaded modules: %s."], table.concat(names, ", "))
end

local UNLOCK = { type = "button", label = "Move frames",
    text = function() return movers().unlocked and L["Lock"] or L["Unlock"] end,
    desc = "Shows a handle on every frame. Drag to move it; right-click a handle to reset that frame.",
    func = function()
        if movers().unlocked then movers().Lock() else movers().Unlock() end
    end }

local PREVIEW = { type = "button", label = "Preview frames",
    text = function() return DUI.testMode and L["Hide"] or L["Show"] end,
    desc = "Shows target, focus, pet, target of target and the party with sample units, and both cast bars mid-cast, "
        .. "so you can style and move them without a real target. Ends when combat starts.",
    func = function() DUI.SetTestMode(not DUI.testMode) end }

local RESET_POSITIONS = { type = "button", label = "Reset all positions", text = "Reset", confirm = true,
    desc = "Puts every frame back where it started.",
    func = function() movers().ResetAll() end }

local SETUP = { type = "button", label = "Setup guide", text = "Open",
    desc = "The guide that set this character up, to run again: a quick setup, every step page by page, or another profile.",
    func = function()
        if DUI.OptionsPanel and DUI.OptionsPanel.IsShown() then DUI.OptionsPanel.Toggle() end
        if DUI.Installer then DUI.Installer.Show() end
    end }

local TOUR = { type = "button", since = "1.6.9", label = "Take the tour", text = "Start",
    desc = "A one-minute walk past what Daylight UI adds: the damage meter, buff and bag groups, moving frames and these options.",
    func = function() if DUI.Tour then DUI.Tour.Start() end end }

-- Font dropdown: ours plus shared fonts from other addons, sorted by name.
-- Built each time it opens since addons register fonts as they load.
local GENERAL_PICK = "General"

-- withGeneral (true, or the "general" choice's text) lists "General" first.
local function fontChoices(withGeneral)
    local values, order = {}, {}
    if withGeneral then
        values[DUI.Media.GENERAL] = type(withGeneral) == "string" and withGeneral or GENERAL_PICK
        order[1] = DUI.Media.GENERAL
    end
    local own, sorted = {}, {}
    for _, key in ipairs(DUI.Style.FONT_ORDER) do
        local f, drawn = DUI.Style.FONTS[key], DUI.Style.FontEntry(key)
        -- A font with no letters for this client's language says which one draws for it.
        values[key] = drawn ~= f and string.format(L["%s (in Russian: %s)"], f.label, L[drawn.label]) or f.label
        sorted[#sorted + 1] = key
        own[f.label] = true
    end
    local shared, sharedOrder = DUI.Media.List("font", own)
    for _, key in ipairs(sharedOrder) do
        values[key] = shared[key]
        sorted[#sorted + 1] = key
    end
    table.sort(sorted, function(a, b) return string.lower(values[a]) < string.lower(values[b]) end)
    for _, key in ipairs(sorted) do order[#order + 1] = key end
    return values, order
end

-- Bar texture dropdown: ours, then shared ones.
local function barChoices(withGeneral)
    local values, order = { daylight = "DaylightUI" }, { "daylight" }
    if withGeneral then
        values[DUI.Media.GENERAL] = type(withGeneral) == "string" and withGeneral or GENERAL_PICK
        table.insert(order, 1, DUI.Media.GENERAL)
    end
    local skip = DUI.Media.OwnBars(values, order)
    local shared, sharedOrder = DUI.Media.List("statusbar", skip)
    for _, key in ipairs(sharedOrder) do
        values[key] = shared[key]
        order[#order + 1] = key
    end
    return values, order
end

-- The actual name behind the General pick, e.g. "Expressway" rather than
-- "General".
local function pickName(kind, key)
    local shared = DUI.Media.SharedName(key)
    if shared then return shared end
    if kind == "font" then
        local f = DUI.Style.FONTS[key] or DUI.Style.FONTS.expressway
        return f.label
    end
    for _, b in ipairs(DUI.Media.BARS) do
        if b.key == key then return b.label end
    end
    return "DaylightUI"
end
local GENERAL_KEY = { font = "font", bar = "barTexture", back = "barBack" }

-- The rows of a custom gradient, the colors a bar (or the accent) runs through:
-- how many, then each color, a row per color shown only while counted. key is
-- the saved { count, c1 to c5 } table's path. spec: shown(get) (true while
-- its color menu is on Custom gradient), what ("health": the labels' word),
-- bar ("the health bar": the descriptions'), disabled(get), since, and
-- countLabel / colorLabels / countDesc / colorDescs to word them otherwise
-- (the accent's).
local ORDINAL = { "First", "Second", "Third", "Fourth", "Fifth" }

-- Lists of rows one after another, for a group that takes in a helper's rows.
function Options.Join(...)
    local out = {}
    for i = 1, select("#", ...) do
        for _, item in ipairs((select(i, ...))) do out[#out + 1] = item end
    end
    return out
end

function Options.StopsRows(key, spec)
    local shown = spec.shown or function() return true end
    local title = spec.what and (string.upper(string.sub(spec.what, 1, 1)) .. string.sub(spec.what, 2))
    local rows = {}
    rows[1] = { type = "slider", key = key .. ".count", min = 2, max = DUI.Style.CUSTOM_STOPS_MAX, step = 1,
        label = spec.countLabel or (title .. " gradient colors"),
        desc = spec.countDesc or ("How many colors " .. spec.bar .. " runs through, left to right, when its color is Custom gradient."),
        since = spec.since, disabled = spec.disabled,
        hidden = function(get) return shown(get) ~= true end }
    for i = 1, DUI.Style.CUSTOM_STOPS_MAX do
        rows[#rows + 1] = { type = "color", key = key .. ".c" .. i, since = spec.since, disabled = spec.disabled,
            label = spec.colorLabels and spec.colorLabels[i]
                or (title .. " gradient " .. string.lower(ORDINAL[i]) .. " color"),
            desc = spec.colorDescs and spec.colorDescs[i]
                or i == 1 and ("Where the custom gradient of " .. spec.bar .. " starts.")
                or ("The next color along the custom gradient of " .. spec.bar .. "."),
            hidden = function(get)
                return shown(get) ~= true or (i > 2 and (get(key .. ".count") or 0) < i)
            end }
    end
    return rows
end

-- Per-area media dropdown. When following General, the box shows the
-- General pick's name, and the list leads with "Expressway (General)".
-- kind: "font" | "bar" | "back". extra: more item fields.
-- extra.follows = { slot, label } for a slot with a parent
-- (Media.RegisterSlot): "General" then means the parent's pick.
function Options.MediaPick(kind, key, label, desc, extra)
    local item = { type = "dropdown", key = key, label = label, desc = desc, fallback = DUI.Media.GENERAL }
    local follows = extra and extra.follows
    local function inherited() return follows and DUI.DB.sv and DUI.Media.Pick(follows.slot) or nil end
    -- Pages are validated at file load, before settings exist. Reading them
    -- now would create the saved table too early (before Profiles.lua has
    -- migrated old profiles), so use the default.
    local function generalName()
        local k = GENERAL_KEY[kind]
        return pickName(kind, inherited() or DUI.DB.sv and DUI:Get("general", k) or DUI.DB.GENERAL_DEFAULTS[k])
    end
    item.shownAs = function(v)
        if v == DUI.Media.GENERAL then return generalName() end
    end
    local function listed() return generalName() .. " (" .. (inherited() and follows.label or GENERAL_PICK) .. ")" end
    if kind == "font" then
        item.choices = function() return fontChoices(listed()) end
        item.preview = "font"
        item.fetch = function(k)
            if k == DUI.Media.GENERAL then
                local own = inherited()
                if not own then return DUI.Style.FONT end
                k = own
            end
            return DUI.Style.FontFileOf(k)
        end
    else
        item.choices = function() return barChoices(listed()) end
        item.preview = "bar"
        item.fetch = function(k)
            if k == DUI.Media.GENERAL then k = inherited() or DUI:Get("general", GENERAL_KEY[kind]) end
            return DUI.Media.Fetch("statusbar", k) or (kind == "back" and DUI.Style.BAR.back or DUI.Style.BAR.fill)
        end
    end
    for k, v in pairs(extra or {}) do item[k] = v end
    return item
end

-- Media rows placed next to their setting, like a bar's texture under its
-- size. key is the setting (key .. "Back" for the background), what is
-- "the health bar" etc.
function Options.BarRow(key, label, what, dis)
    local item = Options.MediaPick("bar", key, label .. " texture",
        "The fill of " .. what .. ". General uses the bar texture on General > Appearance.")
    item.disabled = dis
    return item
end
function Options.BackRow(key, label, what, dis)
    local item = Options.MediaPick("back", key .. "Back", label .. " background",
        "The empty part of " .. what .. ", behind the fill. General uses the bar background on General > Appearance.")
    item.disabled = dis
    return item
end
-- A window's or panel's look: "Use Daylight UI global style" (path .. ".global"),
-- and under it, while it's off, the same rows General > Appearance has for
-- borders, shadows and the background, in the same order and words, saved in
-- the section's own look table (Style.LookOf). Switching it off starts the
-- section from General's values (Style.lua). extra: more rows that belong to
-- the section's own look (a border color), shown only while it's off too.
local function lookOff(path) return function(get) return get(path .. ".global") ~= false end end
function Options.LookRows(path, dis, since, extra)
    local off = lookOff(path)
    local function row(item)
        item.since = item.since or since
        local own = item.disabled
        item.disabled = own and function(get) return (dis and dis(get) == true) or own(get) == true end or dis
        item.hidden = off
        return item
    end
    local rows = {
        { type = "toggle", key = path .. ".global", label = "Use Daylight UI global style", since = "2.2", disabled = dis,
          desc = "When on, this wears the borders, shadows and background set on General > Appearance, like every Daylight UI window. Turn it off to give it its own in the rows below." },
        row({ type = "toggle", key = path .. ".heavyBorder", label = "Heavy border",
              desc = "Adds a warm band inside the black outline, lit along the top. When off, the border is a plain dark line." }),
        row({ type = "toggle", key = path .. ".gradientBorder", label = "Accent gradient border",
              desc = "When the accent color is a gradient (Daylight's, your class's or your own), the border runs along it. Needs Gradients on (General > Gradients).",
              disabled = function()
                  local a = DUI:Get("general", "accent")
                  return (a ~= "gradient" and a ~= "classGradient" and a ~= "customGradient") or DUI.Gradients.Flat()
              end }),
        row({ type = "slider", key = path .. ".borderPx", label = "Border thickness", min = 1, max = 16, step = 1, unit = "px",
              desc = "In screen pixels, so it stays sharp at any UI scale. Heavy border needs 3 or more." }),
        row({ type = "slider", key = path .. ".cornerPx", label = "Corner rounding", min = 0, max = 24, step = 1, unit = "px",
              desc = "Rounds the corners, up to about three times the border thickness." }),
        row({ type = "slider", key = path .. ".borderAlpha", label = "Border opacity", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How solid the border is: at 0 it's fully see-through." }),
        row({ type = "slider", key = path .. ".shadowPx", label = "Shadow size", min = 0, max = 12, step = 1, unit = "px",
              desc = "How far the soft shadow around it reaches." }),
        row({ type = "slider", key = path .. ".shadowAlpha", label = "Shadow opacity", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How dark the shadow around it is." }),
        row({ type = "slider", key = path .. ".windowAlpha", label = "Background opacity", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How solid its background is: at 0 it's fully see-through." }),
        row({ type = "dropdown", key = path .. ".windowTint", label = "Background color",
              values = { daylight = "Daylight", class = "Class tint", custom = "One color" },
              order = { "daylight", "class", "custom" },
              desc = "The color behind it: Daylight's own dark tone, a dark tint of your class color, or a color you pick." }),
        row({ type = "color", key = path .. ".windowTintColor", label = "Custom background color",
              desc = "The background, when Background color is One color. Dark colors keep text easy to read.",
              disabled = function(get) return get(path .. ".windowTint") ~= "custom" end }),
    }
    for _, item in ipairs(extra or {}) do rows[#rows + 1] = row(item) end
    return rows
end

-- Turns every section's global style back on, so every window and panel
-- matches General again. Disabled modules keep theirs, like Media.ApplyToAll.
function Options.ApplyGlobalStyle()
    for _, b in ipairs(DUI.DB.LOOKS) do
        if DUI:Get(b[1], b[2] .. ".global") == false then DUI:Set(b[1], b[2] .. ".global", true) end
    end
    -- Sections made at runtime (meter windows) aren't on the fixed list, so
    -- their owners listen for this and reset themselves.
    DUI.Fire("GlobalStyleApplied")
end
-- extra: optional fields for the row (e.g. the action bars' cdm = true).
function Options.FontRow(key, label, what, dis, extra)
    local item = Options.MediaPick("font", key, label, what .. ". General uses the font on General > Appearance.", extra)
    item.disabled = dis
    return item
end

-- Resets every area's own pick of a kind back to General. Always enabled,
-- because a dimmed button looked broken when nothing had its own pick.
local function resetPicks(kinds, label, desc)
    return { type = "button", label = label, text = "Apply", confirm = true, desc = desc,
             func = function() for _, k in ipairs(kinds) do DUI.Media.ApplyToAll(k) end end }
end

-- A UI sound picker (Sound.KINDS): ours, the game's, or none. Picking plays
-- it once. noGame: the game has no sound for this kind.
local SOUND_VALUES = { soft = "Soft", game = "The game's own", none = "None" }
local SOUND_SOFT = { soft = "Soft", none = "None" }
local function soundKind(kind, label, desc, noGame)
    return { type = "dropdown", key = "soundKinds." .. kind, label = label, desc = desc,
             values = noGame and SOUND_SOFT or SOUND_VALUES,
             order = noGame and { "soft", "none" } or { "soft", "game", "none" },
             fallback = "soft",
             onPick = function() if DUI.Sound then DUI.Sound.Sample(kind) end end,
             disabled = function(get) return get("sounds") == false end }
end

Options.RegisterSection("core", "General", 0)
-- The Extras section lives here rather than in QoL because skins and the
-- character, NPC and spellbook windows use it even with QoL disabled.
Options.RegisterSection("QoL", "Extras", 150)

-- Home page banner (1024 x 512, cropped to its middle band), assembled from
-- layers (tools/make_logo.py --layers) so it can animate a sunrise: horizon
-- lines slide in, the sun rises with a glow, then the wordmark and tagline
-- fade in and a light sweeps across. With motion off it's just shown.
Options.BANNER_CROP = { 0.2, 0.8 }   -- visible fraction of its height
Options.BANNER_W, Options.BANNER_H = 1024, 512
-- Layer boxes in banner px (x0, y0, x1, y1), as printed by make_logo.py.
Options.BANNER_LAYERS = {
    sun = { 119, 170, 345, 320 }, glow = { 60, 109, 404, 384 },
    line1 = { 121, 266, 343, 335 }, line2 = { 156, 284, 308, 349 }, line3 = { 188, 304, 276, 360 },
    title = { 417, 206, 875, 278 }, tagline = { 417, 308, 766, 333 },
}
Options.BANNER_FILES = {
    sun = "logo-sun.png", glow = "logo-sun-glow.png", line1 = "logo-line1.png", line2 = "logo-line2.png",
    line3 = "logo-line3.png", title = "logo-title.png", tagline = "logo-tagline.png",
}
Options.BANNER_HORIZON = 297   -- top of the horizon line, the sun hides below it
-- Start times in seconds. Each piece takes Motion.SLOW, the sun twice that.
Options.SUNRISE = { line3 = 0, line2 = 0.1, line1 = 0.2, sun = 0.25, glow = 0.6, title = 0.85, tagline = 1.1 }
Options.SUNRISE_SLIDE = 36            -- line slide distance, alternating sides
Options.SUNRISE_RISE = 6              -- how far the words rise while fading in
Options.SUNRISE_GLOW = { 0.85, 0.35 } -- glow peak, then resting alpha
Options.HOME_SHINE = 0.3              -- light sweep peak alpha
Options.HOME_SHINE_DUR = 1.2          -- one slow pass at the end

local function sunriseLength()
    local M = DUI.Motion
    return Options.SUNRISE.tagline + M.SLOW
end

-- Eased-out progress at time t for a piece starting at `at` lasting `dur`.
local function phase(t, at, dur)
    local p = math.max(0, math.min(1, (t - at) / dur))
    return 1 - (1 - p) ^ 3
end

-- Places every layer as it is t seconds into the sunrise.
local function placeSunrise(sr, t)
    local M = DUI.Motion
    local w = sr:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = (DUI.OptionsPanel and DUI.OptionsPanel.CONTENT_WIDTH) or 600 end
    local s = w / Options.BANNER_W
    local top = sr.crop[1] * Options.BANNER_H
    local L, S = Options.BANNER_LAYERS, Options.SUNRISE
    local function lay(tex, box, dx, dy, k)
        k = k or 1
        local cx, cy = (box[1] + box[3]) / 2 + dx, (box[2] + box[4]) / 2 + dy
        local bw, bh = (box[3] - box[1]) * k, (box[4] - box[2]) * k
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", sr, "TOPLEFT", (cx - bw / 2) * s, -(cy - bh / 2 - top) * s)
        tex:SetSize(bw * s, bh * s)
    end
    sr.clip:SetHeight((Options.BANNER_HORIZON - top) * s)
    for i, key in ipairs({ "line1", "line2", "line3" }) do
        local p = phase(t, S[key], M.SLOW)
        local from = (i % 2 == 0 and 1 or -1) * Options.SUNRISE_SLIDE
        lay(sr.pieces[key], L[key], from * (1 - p), 0)
        sr.pieces[key]:SetAlpha(p)
    end
    local rise = phase(t, S.sun, 2 * M.SLOW)
    lay(sr.pieces.sun, L.sun, 0, (Options.BANNER_HORIZON - L.sun[2]) * (1 - rise))
    local up, down = phase(t, S.glow, M.SLOW), phase(t, S.glow + M.SLOW, M.NORMAL)
    local peak, rest = Options.SUNRISE_GLOW[1], Options.SUNRISE_GLOW[2]
    lay(sr.pieces.glow, L.glow, 0, 0, 0.7 + 0.3 * up)
    sr.pieces.glow:SetAlpha(peak * up + (rest - peak) * down)
    for _, key in ipairs({ "title", "tagline" }) do
        local p = phase(t, S[key], M.SLOW)
        lay(sr.pieces[key], L[key], 0, Options.SUNRISE_RISE * (1 - p))
        sr.pieces[key]:SetAlpha(p)
    end
    sr.t = t
end

-- Sunrise banner frame showing the crop band ({ top, bottom } fractions).
-- Height = width / 2 * band. sr.Play() runs it from the start, sr.Place(t)
-- jumps to t seconds. Used on Home and in the setup guide's welcome.
function Options.NewSunrise(parent, crop)
    local M = DUI.Motion
    local sr = CreateFrame("Frame", nil, parent)
    sr.crop = crop
    sr.sky = sr:CreateTexture(nil, "BACKGROUND")
    sr.sky:SetTexture(DUI.MEDIA .. "logo-sky.png")
    sr.sky:SetTexCoord(0, 1, crop[1], crop[2])
    sr.sky:SetAllPoints(sr)
    sr.pieces = {}
    local function piece(key, owner, layer, blend)
        local tex = owner:CreateTexture(nil, layer)
        tex:SetTexture(DUI.MEDIA .. Options.BANNER_FILES[key])
        if blend then tex:SetBlendMode(blend) end
        sr.pieces[key] = tex
    end
    piece("glow", sr, "BORDER", "ADD")
    -- The sun's frame is clipped at the horizon so it rises from behind it.
    sr.clip = CreateFrame("Frame", nil, sr)
    sr.clip:SetPoint("TOPLEFT", sr, "TOPLEFT", 0, 0)
    sr.clip:SetPoint("TOPRIGHT", sr, "TOPRIGHT", 0, 0)
    sr.clip:SetClipsChildren(true)
    piece("sun", sr.clip, "ARTWORK")
    sr.front = CreateFrame("Frame", nil, sr)
    sr.front:SetAllPoints(sr)
    for _, key in ipairs({ "line1", "line2", "line3", "title", "tagline" }) do piece(key, sr.front, "ARTWORK") end
    sr.shine = sr.front:CreateTexture(nil, "OVERLAY")
    sr.shine:SetTexture(DUI.MEDIA .. "glow.png")
    sr.shine:SetBlendMode("ADD")
    sr.shine:Hide()
    sr.key = {}
    function sr.Place(t) placeSunrise(sr, t or sr.t or sunriseLength()) end
    -- Start from an empty sky, otherwise the finished banner flashes first.
    -- Begin one frame later so a slow window-opening frame can't eat the
    -- start. Repeated calls before then only start it once.
    function sr.Play()
        local length = sunriseLength()
        if not M.On() then return placeSunrise(sr, length) end
        M.Tween(sr.key, 0, 0, 0)
        placeSunrise(sr, 0)
        if sr.waiting then return end
        sr.waiting = true
        C_Timer.After(0, function()
            sr.waiting = nil
            if sr:IsVisible() then sr.Run() else placeSunrise(sr, length) end
        end)
    end
    function sr.Run()
        local length = sunriseLength()
        -- Tween hands over eased values (out cubic). Undo that here so each
        -- piece can time itself in plain seconds.
        M.Tween(sr.key, 0, length, length, function(v)
            placeSunrise(sr, length * (1 - (1 - v / length) ^ (1 / 3)))
        end, function()
            sr.shine:SetHeight(sr:GetHeight() or 200)
            M.Sweep(sr.shine, sr, { width = (sr:GetWidth() or 600) * 0.3, dur = Options.HOME_SHINE_DUR,
                alpha = Options.HOME_SHINE, key = sr.shine })
        end)
    end
    sr:SetScript("OnSizeChanged", function() sr.Place() end)
    sr.Place(M.On() and 0 or sunriseLength())
    return sr
end

local BANNER = {
    type = "custom", label = "",
    build = function(row)
        row.sunrise = Options.NewSunrise(row, Options.BANNER_CROP)
        row.sunrise:SetAllPoints(row)
        row:SetScript("OnShow", function() row.sunrise.Play() end)
        row.sunrise.Play()   -- the row is built already shown, so no OnShow fires
    end,
    update = function(row) row.sunrise.Place() end,
    height = function(row)
        local w = row:GetWidth()
        if type(w) ~= "number" or w <= 0 then w = (DUI.OptionsPanel and DUI.OptionsPanel.CONTENT_WIDTH) or 600 end
        return w * Options.BANNER_H / Options.BANNER_W * (Options.BANNER_CROP[2] - Options.BANNER_CROP[1])
    end,
}

-- Greeting under the banner, plus profile, module count and version, with
-- What's new and Ko-fi links below.
Options.HOME_RISE = 10      -- greeting rise distance, px
Options.HOME_STAT_W = 104   -- width of each stat column
Options.HOME_GREETING_H = 112
local function moduleCount()
    local on, all = 0, 0
    for _, mod in DUI.Modules() do
        all = all + 1
        if mod.enabled then on = on + 1 end
    end
    return on, all
end

local GREETING = {
    type = "custom", label = "",
    build = function(row)
        local W, M, Style = DUI.Widgets, DUI.Motion, DUI.Style
        local SIZE = Style.SIZE
        row.hold = CreateFrame("Frame", nil, row)
        row.hold:SetAllPoints(row)
        local h = row.hold

        -- Stats, right to left: version, modules, profile.
        local function stat(i, label)
            local s = {}
            s.value = Style.Text(h, SIZE.head, "LEFT")
            s.value:SetPoint("TOPRIGHT", h, "TOPRIGHT", -W.PAD - (i - 1) * Options.HOME_STAT_W, -14)
            s.value:SetWidth(Options.HOME_STAT_W - 12)
            s.value:SetWordWrap(false)
            s.label = Style.Text(h, SIZE.small, "LEFT")
            s.label:SetPoint("TOPLEFT", s.value, "BOTTOMLEFT", 0, -4)
            s.label:SetText(L[label])
            return s
        end
        row.version = stat(1, "Version")
        row.modules = stat(2, "Modules on")
        row.profile = stat(3, "Profile")
        -- Profile name and version are values, not text to translate.
        row.profile.value.english, row.version.value.english = true, true
        local tip = CreateFrame("Frame", nil, h)
        tip:SetPoint("TOPLEFT", row.modules.value, "TOPLEFT", 0, 2)
        tip:SetPoint("BOTTOMRIGHT", row.modules.label, "BOTTOMRIGHT", 0, -2)
        tip:EnableMouse(true)
        tip:SetScript("OnEnter", function(self) W.Tooltip(self, L["Modules on"], moduleList()) end)
        tip:SetScript("OnLeave", W.HideTooltip)

        -- Links under the stats.
        local news = W.Link(h)
        news.SetLabel(L["What's new"])
        news:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -W.PAD, 10)
        news:SetScript("OnClick", function()
            local P = DUI.OptionsPanel
            if P then P.ShowSection("patchnotes") end
        end)

        local edge = row.profile.value
        row.hello = Style.Text(h, SIZE.title, "LEFT")
        row.hello:SetPoint("TOPLEFT", h, "TOPLEFT", W.PAD, -12)
        row.hello:SetPoint("RIGHT", edge, "LEFT", -16, 0)
        row.hello:SetWordWrap(false)
        row.line1 = Style.Text(h, SIZE.body, "LEFT")
        row.line1:SetPoint("TOPLEFT", row.hello, "BOTTOMLEFT", 0, -8)
        row.line1:SetPoint("RIGHT", edge, "LEFT", -16, 0)
        row.line1:SetText(L["Pick a page on the left to shape your interface. Changes apply as you make them."])
        row.line2 = Style.Text(h, SIZE.small, "LEFT")
        row.line2:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", W.PAD, 14)
        row.line2:SetPoint("RIGHT", news, "LEFT", -16, 0)
        row.line2:SetWordWrap(false)
        row.line2:SetText(L["Hover a setting to see what it does; the arrow beside a changed setting puts it back."])

        -- Painted on show so the name, accent and stats are current.
        -- count makes the module number count up from 0.
        function row.Paint(count)
            local I = DUI.Installer
            row.hello:SetText(I and I.GreetingText() or "")
            Style.InkText(row.hello, "VALUE")
            Style.InkText(row.line1, "TEXT")
            Style.InkText(row.line2, "LABEL")
            for _, s in ipairs({ row.profile, row.modules, row.version }) do Style.InkText(s.label, "LABEL") end
            row.profile.value:SetText(DUI.DB.ActiveName() or "")
            Style.InkText(row.profile.value, "VALUE")
            row.version.value:SetText(tostring(DUI.VERSION or ""))
            Style.InkText(row.version.value, "VALUE")
            -- Uses the window's Daylight color, not the accent.
            row.modules.value:SetTextColor(Style.SweepAt())
            local on, all = moduleCount()
            local function fmt(n) return string.format("%d / %d", n, all) end
            if count then M.CountTo(row.modules.value, 0, fmt) end
            M.CountTo(row.modules.value, on, fmt, M.SLOW)
        end
        row:SetScript("OnShow", function()
            M.SlideIn(row.hold, 0, -Options.HOME_RISE, M.NORMAL, M.FAST)
            row.Paint(true)
        end)
        row.Paint()
    end,
    update = function(row) row.Paint() end,
    height = function() return Options.HOME_GREETING_H end,
}

-- Shared profiles card: points to setups other players share on the
-- Daylight UI site. The button shows the link to copy, since addons can't
-- open a browser, and a smaller link imports one here.
Options.HOME_PROFILES_H = 118
local SHARED_PROFILES = {
    type = "custom", label = "", noSearch = true,
    build = function(row)
        local W, M, Style = DUI.Widgets, DUI.Motion, DUI.Style
        local SIZE = Style.SIZE
        row.hold = CreateFrame("Frame", nil, row)
        row.hold:SetAllPoints(row)
        local h = row.hold

        -- Soft Daylight wash from the left, under everything.
        row.wash = h:CreateTexture(nil, "BACKGROUND")
        row.wash:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.wash:SetAllPoints(h)
        W.TintDaylight(row.wash, 0.07)

        local P = DUI.OptionsPanel
        row.browse = P.SupportButton(h, L["Browse profiles"], function() P.ShowProfilesSite() end, 32, 160)
        row.browse:SetPoint("TOPRIGHT", h, "TOPRIGHT", -W.PAD, -24)
        row.import = W.Link(h)
        row.import.SetLabel(L["Import one here"])
        row.import:SetPoint("TOP", row.browse, "BOTTOM", 0, -10)
        row.import:SetScript("OnClick", function() P.Show("profiles") end)

        row.kicker = Style.Text(h, SIZE.small, "LEFT")
        row.kicker:SetPoint("TOPLEFT", h, "TOPLEFT", W.PAD, -14)
        row.kicker:SetText(L["Shared by players"])
        row.title = Style.Text(h, SIZE.title, "LEFT")
        row.title:SetPoint("TOPLEFT", row.kicker, "BOTTOMLEFT", 0, -6)
        row.title:SetText(DUI.GradientText(L["Find your perfect setup"]))
        row.text = Style.Text(h, SIZE.body, "LEFT")
        row.text:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -8)
        -- Its width is set by height(row), which runs on every layout, so it wraps at the width it gets.
        row.text:SetText(L["Ready-made profiles from other Daylight UI players, from calm questing looks to raid healer layouts. Pick one you like, copy its string, import it in a click."])
        row.site = Style.Text(h, SIZE.small, "LEFT")
        row.site:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -6)
        row.site:SetText((P.PROFILES_SITE:gsub("^https?://www%.", "")))
        row.site.english = true

        -- Light sweep across the card on show.
        row.shine = h:CreateTexture(nil, "OVERLAY")
        row.shine:SetTexture(DUI.MEDIA .. "glow.png")
        row.shine:SetBlendMode("ADD")
        row.shine:SetHeight(Options.HOME_PROFILES_H + 20)
        row.shine:Hide()

        function row.Paint()
            Style.InkText(row.kicker, "LABEL")
            Style.InkText(row.text, "TEXT")
            W.TextDaylight(row.site)   -- window color, not the accent
        end
        row:SetScript("OnShow", function()
            M.SlideIn(row.hold, 0, -Options.HOME_RISE, M.NORMAL, M.FAST)
            M.Sweep(row.shine, h, { width = 120, dur = M.SLOW * 3, alpha = 0.18,
                color = { Style.SweepAt() } })
        end)
        row.Paint()
    end,
    update = function(row) row.Paint() end,
    -- Taller than HOME_PROFILES_H when a narrow window wraps the text to more lines.
    height = function(row)
        local W = DUI.Widgets
        local w = row:GetWidth()
        if type(w) ~= "number" or w <= 0 then w = (DUI.OptionsPanel and DUI.OptionsPanel.CONTENT_WIDTH) or 600 end
        local tw = w - 2 * W.PAD - row.browse:GetWidth() - 24
        if tw <= 0 then return Options.HOME_PROFILES_H end
        row.text:SetWidth(tw)
        local function tall(fs) local v = fs:GetStringHeight(); return type(v) == "number" and v or 0 end
        local h = 14 + tall(row.kicker) + 6 + tall(row.title) + 8 + tall(row.text) + 6 + tall(row.site) + 14
        return math.max(Options.HOME_PROFILES_H, math.ceil(h))
    end,
}

Options.RegisterPage({
    id = "home", section = "core", label = "Home", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "A soft, minimal interface.",
    groups = {
        { label = "", bare = true, items = { BANNER } },
        { label = "", items = { GREETING } },
        { label = "", items = { SHARED_PROFILES } },
        { label = "Quick actions", items = { PREVIEW, UNLOCK, RESET_POSITIONS, SETUP, TOUR } },
        { label = "Language", items = {
            { type = "dropdown", label = "Daylight UI's language", since = "2.2.5", reload = true,
              search = "Language Translation",
              desc = "The language of Daylight UI's own text: these options, the setup guide and its frames. "
                  .. "The game's own text, such as spell and item names, stays in your game's language. Shows after a /reload.",
              choices = Options.LanguageChoices, preview = "font", fetch = Options.LanguageFont,
              get = function() return DUI.DB.Root().language or "auto" end,
              set = function(v) DUI.DB.Root().language = v ~= "auto" and v or nil end },
        } },
        { label = "New options", items = {
            { type = "dropdown", label = "Show NEW on options added since", noSearch = true,
              desc = "Rows added after this version carry a NEW tag as you go through the pages. Search for new to list them all.",
              choices = Options.NewSinceChoices,
              get = function() return Options.NewSince() or "none" end,
              set = function(v)
                  DUI.DB.Root().newSince = v
                  local P = DUI.OptionsPanel
                  if P and P.IsShown and P.IsShown() then P.Refresh() end
              end },
        } },
    },
})

Options.RegisterPage({
    id = "appearance", section = "core", label = "Appearance", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "The look shared by everything Daylight UI draws.",
    groups = {
        { label = "Font", items = {
            { type = "dropdown", key = "font", label = "Font", choices = fontChoices, fallback = "expressway",
              preview = "font", fetch = function(key)
                  return DUI.Media.Fetch("font", key) or (DUI.Style.FontEntry(key) and DUI.Style.FontEntry(key).file)
              end,
              desc = "Used by all Daylight UI text, except where a frame's own page picks another font. Game font is the client's own, "
                  .. "including a font you've replaced it with. Fonts other addons share (SharedMedia) are listed with them, A to Z." },
            resetPicks({ "font" }, "Use this font everywhere",
                "The font above shows everywhere at once, except where a frame's own page or the window font below picks another. "
                    .. "This puts every one of those back on the font above."),
            Options.MediaPick("font", "windowFont", "Window font",
                "The text in Daylight UI's windows (character, spellbook, professions, bags, quest journal) "
                    .. "and the game's windows it restyles. General uses the font above."),
            { type = "toggle", key = "localFont", label = "Use my language's font",
              hidden = function() return not DUI.DB.NonLatinClient() end,
              desc = "Uses the game's own font in place of Daylight UI's fonts, which only have Latin letters. "
                  .. "The options window changes after /reload." },
            { type = "toggle", key = "gameText", label = "Use this font for the game's text", reload = true,
              hidden = function(get) return get("font") == "game" or DUI.DB.UseLocalFont() end,
              desc = "Puts this font on the game's own text as well: menus, tooltips, quest text, popups, nameplate names. "
                  .. "Sizes and outlines stay the game's. It's put on once as you log in, so a change here, "
                  .. "or a new font above, shows on the game's text after a /reload." },
            { type = "dropdown", key = "textOutline", label = "Text outline",
              values = { OUTLINE = "Thin", THICKOUTLINE = "Thick", [""] = "None" }, order = { "OUTLINE", "THICKOUTLINE", "" },
              desc = "A dark edge around the letters on Daylight UI's frames, so text stays readable over a busy world. Combat text has its own (General > Combat text)." },
            { type = "toggle", key = "textShadow", label = "Text shadow", desc = "A small soft drop shadow under text. Combat text has its own (General > Combat text)." },
            { type = "dropdown", key = "numbers", label = "Health and power numbers",
              values = DUI.Health.NUMBERS, order = DUI.Health.NUMBER_ORDER,
              desc = "How health and power numbers are written on unit frames, extra texts and nameplates. "
                  .. "Percents stay as they are." },
        } },
        { label = "Names", items = {
            { type = "toggle", key = "rpNames", label = "Roleplay names", since = "1.6.5",
              hidden = function() return type(AddOn_TotalRP3) ~= "table" end,
              desc = "Players with a Total RP 3 profile show by their roleplay name on unit frames, nameplates, the threat meter "
                  .. "and windows. Each frame's First and last names switch still picks first name or full name." },
        } },
        { label = "Bars", items = {
            { type = "dropdown", key = "barTexture", label = "Bar texture", choices = barChoices, fallback = "daylight",
              preview = "bar", fetch = function(key) return DUI.Media.Fetch("statusbar", key) or DUI.Style.BAR.fill end,
              desc = "The fill of every bar: health, power, cast bars, swing timers, experience, the damage meter, nameplates and more, "
                  .. "except where a frame's own page picks another. Textures other addons share (SharedMedia) are listed after ours." },
            { type = "dropdown", key = "barBack", label = "Bar background", choices = barChoices, fallback = "daylight",
              preview = "bar", fetch = function(key) return DUI.Media.Fetch("statusbar", key) or DUI.Style.BAR.back end,
              desc = "The empty part behind every bar's fill, tinted in the bar's color, except where a frame's own page picks another." },
            resetPicks({ "bar", "back" }, "Use these textures everywhere",
                "The textures above show on every bar at once, except where a frame's own page or the window bars below pick another. "
                    .. "This puts every one of those back on the textures above."),
            Options.MediaPick("bar", "windowBar", "Window bar texture",
                "The fill of the bars in Daylight UI's windows: reputation, skills, professions, pet experience, quest objectives. "
                    .. "They keep their round shape. General uses the bar texture above."),
            Options.MediaPick("back", "windowBack", "Window bar background",
                "The empty part behind the bars in Daylight UI's windows. General uses the bar background above."),
        } },
        { label = "Size", items = {
            { type = "slider", label = "UI scale", min = DUI.Pixel.SCALE_MIN, max = DUI.Pixel.SCALE_MAX, step = 0.01,
              unit = "x", free = true, snapTo = function() return DUI.Pixel.perfect end, since = "1.7.4", onRelease = true,
              get = function() return DUI.Pixel.UIScale() or UIParent:GetScale() end,
              set = function(v) DUI.Pixel.SetUIScale(v) end,
              default = function() return DUI.Pixel.GameScale() or UIParent:GetScale() end,
              desc = "The size of the whole interface, the game's windows too. Daylight UI keeps it the same when the game "
                  .. "changes its own (a new resolution, another monitor), so your frames stay where you put them. "
                  .. "It takes the place of the game's UI scale setting, for every character on this account." },
            { type = "slider", key = "scale", label = "Daylight UI scale", min = 0.5, max = 2, step = 0.05, unit = "x",
              desc = "Makes every Daylight UI frame and window bigger or smaller. To size one frame alone, unlock the frames and scroll over it." },
            { type = "slider", key = "fontScale", label = "Text scale", min = 0.7, max = 1.6, step = 0.05, unit = "x",
              desc = "Makes all text on Daylight UI's frames bigger or smaller, on top of each frame's own text size." },
        } },
        { label = "Color", items = Options.Join({
            { type = "dropdown", key = "accent", label = "Accent color", values = DUI.Style.ACCENTS,
              order = DUI.Style.ACCENT_ORDER,
              desc = "The highlight color: Daylight's own quiet tone, the Daylight gradient, your class's color or its gradient (from the Gradients page), or one of your own.",
              onPick = function(k)
                  if k ~= "custom" or not DUI.Widgets then return end
                  local c = DUI:Get("general", "accentColor") or { DUI.Style.ACCENT[1], DUI.Style.ACCENT[2], DUI.Style.ACCENT[3] }
                  DUI.Widgets.PickCustom(c, function(col) DUI:Set("general", "accentColor", col) end)
              end },
            { type = "color", key = "accentColor", label = "Custom accent color",
              desc = "Your own accent, when Accent color is Custom color.",
              hidden = function(get) return get("accent") == "customGradient" end,
              disabled = function(get) return get("accent") ~= "custom" end },
        }, Options.StopsRows("accentGradient", { since = "1.9.2",
                shown = function(get) return get("accent") == "customGradient" end,
                countLabel = "Gradient colors", countDesc = "How many colors your custom gradient runs through, left to right.",
                colorLabels = { "First color", "Second color", "Third color", "Fourth color", "Fifth color" },
                colorDescs = { "Where your custom gradient starts.", "The next color along your custom gradient.",
                    "The next color along your custom gradient.", "The next color along your custom gradient.",
                    "The next color along your custom gradient." } }), {
            { type = "slider", key = "softness", label = "Color softness", min = 0, max = 0.8, step = 0.05, unit = "%",
              desc = "Eases class, reaction and power colors toward gray for a gentler look." },
            { type = "slider", key = "brightness", label = "Bar brightness", min = 0.4, max = 1, step = 0.05, unit = "%",
              desc = "Dims every bar color." },
        }) },
        { label = "Borders and shadows", items = {
            { type = "toggle", key = "heavyBorder", label = "Heavy border",
              desc = "Adds a warm band inside the black outline, lit along the top. When off, the border is a plain dark line." },
            { type = "toggle", key = "gradientBorder", label = "Gradient window borders",
              desc = "When the accent color is a gradient (Daylight's, your class's or your own), every Daylight UI border runs along it: windows, panels, frames and nameplates. Needs Gradients on (General > Gradients).",
              disabled = function(get)
                  local a = get("accent")
                  return (a ~= "gradient" and a ~= "classGradient" and a ~= "customGradient") or DUI.Gradients.Flat()
              end },
            { type = "slider", key = "borderPx", label = "Border thickness", min = 1, max = 16, step = 1, unit = "px",
              desc = "In screen pixels, so it stays sharp at any UI scale. Heavy border needs 3 or more." },
            { type = "slider", key = "cornerPx", label = "Corner rounding", min = 0, max = 24, step = 1, unit = "px",
              desc = "Rounds the corners, up to about three times the border thickness." },
            { type = "slider", key = "borderAlpha", label = "Border opacity", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How solid the borders around Daylight UI's frames and windows are: at 0 they're fully see-through." },
            { type = "slider", key = "shadowPx", label = "Shadow size", min = 0, max = 12, step = 1, unit = "px",
              desc = "How far the soft shadow around Daylight UI's frames and windows reaches." },
            { type = "slider", key = "shadowAlpha", label = "Shadow opacity", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How dark the shadow around Daylight UI's frames and windows is." },
        } },
        { label = "Windows", items = {
            { type = "slider", key = "windowAlpha", label = "Window background opacity", min = 0, max = 1, step = 0.05, unit = "%",
              desc = "How solid every window and panel is: bags, character, spellbook, NPC, group finder, the game's windows Daylight UI restyles, "
                  .. "chat, the info panel, the quest box and the buff bars. At 0 they're fully see-through. One with Use Daylight UI global style off keeps its own." },
            { type = "dropdown", key = "windowTint", label = "Window background color", since = "1.8.4",
              values = { daylight = "Daylight", class = "Class tint", custom = "One color" },
              order = { "daylight", "class", "custom" },
              desc = "The color behind every window and panel: Daylight's own dark tone, a dark tint of your class color, or a color you pick.",
              onPick = function(k)
                  if k ~= "custom" or not DUI.Widgets then return end
                  local c = DUI:Get("general", "windowTintColor") or { DUI.Style.BACKGROUND[1], DUI.Style.BACKGROUND[2], DUI.Style.BACKGROUND[3] }
                  DUI.Widgets.PickCustom(c, function(col) DUI:Set("general", "windowTintColor", col) end)
              end },
            { type = "color", key = "windowTintColor", label = "Custom window background color", since = "1.8.4",
              desc = "The window background, when Window background color is One color. Dark colors keep text easy to read.",
              disabled = function(get) return get("windowTint") ~= "custom" end },
            { type = "button", since = "2.2", label = "Apply global style everywhere", text = "Apply", confirm = true,
              desc = "Turns Use Daylight UI global style back on for every window and panel, so they all match the borders, shadows and background here.",
              func = function() Options.ApplyGlobalStyle() end },
        } },
        { label = "Motion", items = {
            { type = "toggle", key = "motion", label = "Motion effects",
              desc = "Windows glide in and out, tooltips fade in, a spell's icon pops when it's ready, gold and XP count up. When off, everything snaps into place." },
            { type = "dropdown", key = "buttonGlow", label = "Main button glow",
              choices = function() return DUI.Motion.GlowChoices("Off") end,
              disabled = function(get) return get("motion") == false end,
              desc = "The soft light moving round the main button of a Daylight UI window (Accept, Complete, Send...), in the style you pick, or Off for none. Needs Motion effects (General > Appearance)." },
            { type = "toggle", key = "portraitFlare", label = "Window icon flare", since = "1.8.3",
              disabled = function(get) return get("motion") == false end,
              desc = "A halo and a ring of embers light the round icon at the top of a window as it opens. Needs Motion effects (General > Appearance)." },
            { type = "toggle", key = "smoothBars", label = "Smooth bars",
              disabled = function(get) return get("motion") == false end,
              desc = "Bars glide to their new value instead of jumping. Needs Motion effects (General > Appearance)." },
        } },
        { label = "Sound", items = {
            { type = "toggle", key = "sounds", label = "Soft UI sounds",
              desc = "Quiet, soft clicks for windows, menus and toggles, in place of the game's own. When off, you hear the game's own sounds everywhere." },
            soundKind("windows", "Windows open & close",
                "Opening and closing windows: bags, character, spellbook, quest log, the game menu and Daylight UI's own windows."),
            soundKind("clicks", "Menu & tab clicks",
                "Clicking menu buttons, tabs and pages, in the game's windows and in /dui."),
            soundKind("toggles", "Option toggles",
                "Switching an option on or off in /dui."),
            soundKind("snaps", "Snap when placing frames",
                "A frame dropped in unlock mode, a spell placed in the Cooldown Manager editor, a click-cast bound. The game has no sound of its own for these.",
                true),
            soundKind("confirms", "Confirmations",
                "A soft chime when talents are applied, a talent set is switched, a spell is learned at a trainer or a letter is sent.",
                true),
            -- Saved on the quest tracker (Quests.sound), which plays it.
            { type = "toggle", label = "Quest ready chime",
              desc = "A soft, warm chime when a tracked quest is ready to hand in.",
              get = function() return DUI:Get("Quests", "sound") ~= false end,
              set = function(v) DUI:Set("Quests", "sound", v == true) end,
              default = function() return true end,
              hidden = function() local m = DUI:GetModule("Quests") return not (m and m.enabled) end,
              disabled = function(get) return get("sounds") == false end },
        } },
    },
})

-- Bar animation (BarFx.lua): one card for the bars a page owns, each bar's
-- settings in its own module. spec = { module, choices = { { id, label, base,
-- kind, gate } } (only a health bar reacts to hits and heals), gate = fn(get) (true = the bar is off; a choice's own gate
-- wins), read = fn(key)
-- (where a preview reads; the module's own settings when nil), pickHidden
-- (hides the "Settings for" pick), tab, desc (the card's own line) }. One
-- choice is a plain card, more get a "Settings for" pick. Each choice starts
-- with a sample bar wearing its settings.
local BARFX_PREVIEW_H = 14
local function barFxItems(spec, c)
    local base, gate = c.base, c.gate or spec.gate
    local function off(get) return DUI:Get("general", "motion") == false or (gate ~= nil and gate(get) == true) end
    local function none(get) return off(get) or get(base .. "style") == "none" end
    local read = spec.read or function(key) return DUI:Get(spec.module, key) end
    local cfg = function(key) return read(base .. key) end
    return {
        { type = "custom", label = "", noSearch = true, fits = true, lockWith = base .. "style",
          build = function(row)
              row.sample = DUI.BarFx.Sample(row, { c.kind }, { bare = true, height = BARFX_PREVIEW_H, cfg = function() return cfg end })
              -- Spans the row by its anchors, so it fits any width.
              local f, bar = row.sample.frame, row.sample.bars[1]
              f:ClearAllPoints()
              f:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
              f:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -8)
              f:SetHeight(BARFX_PREVIEW_H)
              bar:ClearAllPoints()
              bar:SetAllPoints(f)
          end,
          update = function(row) row.sample.Apply() end,
          height = function() return BARFX_PREVIEW_H + 16 end },
        { type = "dropdown", key = base .. "style", label = c.label .. " animation", since = "1.8.5",
          choices = function() return DUI.BarFx.Choices(c.kind == "power") end,
          disabled = off,
          desc = "How the bar moves. Flow rolls the bar's colors along it; Tide swells softly through it and surges with every heal and hit." ..
                 (c.kind == "power" and " By power type picks one that suits mana, rage or energy." or "") ..
                 " Needs Motion effects (General > Appearance)." },
        { type = "slider", key = base .. "speed", label = "Animation speed", min = 0.25, max = 3, step = 0.05, unit = "x", since = "1.8.5",
          disabled = none, desc = "How fast the animation moves. 1x is its usual pace." },
        { type = "slider", key = base .. "strength", label = "Animation strength", min = 0.1, max = 1, step = 0.05, unit = "%", since = "1.8.5",
          disabled = none, desc = "How strongly the animation shows over the bar's own fill. Lower blends it in softly." },
        { type = "dropdown", key = base .. "colors", label = "Animation colors", since = "1.8.5",
          values = { bar = "The bar's own", accent = "Accent color", class = "Class colors", custom = "Custom colors" },
          order = { "bar", "accent", "class", "custom" },
          disabled = none, desc = "The colors the animation moves: the ones the bar already has, your accent, your class's pair, or two of your own." },
        { type = "color", key = base .. "colorA", label = "First color", since = "1.8.5",
          hidden = function(get) return get(base .. "colors") ~= "custom" end, disabled = none,
          desc = "One end of the custom pair." },
        { type = "color", key = base .. "colorB", label = "Second color", since = "1.8.5",
          hidden = function(get) return get(base .. "colors") ~= "custom" end, disabled = none,
          desc = "The other end of the custom pair." },
        { type = "toggle", key = base .. "react", label = "React to hits and heals", since = "1.8.5",
          hidden = function() return c.kind ~= "health" end, disabled = none, desc = "Animations that react (Tide, Daybreak) move with every heal and hit. When off, they keep their steady pace." },
        { type = "slider", key = base .. "reactSize", label = "Reaction size", min = 0.25, max = 2, step = 0.05, unit = "x", since = "1.8.5",
          hidden = function() return c.kind ~= "health" end, disabled = function(get) return none(get) or get(base .. "react") == false end,
          desc = "How big a reaction is. The game doesn't say how big a hit or heal was, so every one moves the same." },
    }
end

function Options.BarFxCard(spec)
    local label, desc = "Bar animation", spec.desc or "Bars that move: their colors roll along them and react to the fight."
    if #spec.choices == 1 then
        return { label = label, desc = desc, tab = spec.tab, items = barFxItems(spec, spec.choices[1]) }
    end
    local choices = {}
    for i, c in ipairs(spec.choices) do choices[i] = { id = c.id, label = c.label, items = barFxItems(spec, c) } end
    return Options.PickCard({ label = label, desc = desc, tab = spec.tab, since = "1.8.5", choices = choices,
        pickDesc = "Which of this page's bars the rows below set.", pickHidden = spec.pickHidden })
end

-- Fade page: global switches, then each module's fade rows (Fade.HubGroups,
-- copies sharing the same settings), added once module pages exist.
local fadePage = Options.RegisterPage({
    id = DUI.Fade.HUB_PAGE, section = "core", label = "Fade", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "Every part's fade in one place. Each is the same setting as on that part's own page.",
    resetAll = function() DUI.Fade.ResetAll() end,
    groups = {
        { label = "Everywhere", items = {
            -- Sets every part to "Only when something changes". Reads on only if all are.
            { type = "toggle", label = "Show everything only when something changes",
              desc = "Sets Visible to Only when something changes on every part that has it: gone out of a fight, back in one, and back for a moment when it changes. Turned off, each goes back to what it was before. Each part's own Visible on its page still works on its own.",
              get = function() return DUI.Fade.AllFloat() end,
              set = function(v) DUI.Fade.SetAllFloat(v == true) end,
              default = function() return false end },
            { type = "toggle", key = "fadeIn", label = "Fade in on login",
              desc = "After a login or /reload the UI starts invisible and glides in. Anything set to fade ends faded." },
            { type = "toggle", key = "fadeOpenWorldOnly", label = "Fade only in the open world",
              desc = "In dungeons, raids, battlegrounds and arenas, everything set to fade stays shown, as if its fade were Never. It fades again once you're back outside." },
            { type = "toggle", key = "fadeOnFlight", since = "2.2.1", label = "Fade everything on a flight path",
              desc = "While a flight master flies you somewhere, the whole UI slowly fades away so you can watch the world go by. Point at a part to see it. It all comes back as you land; the flight timer stays." },
        } },
    },
})
DUI.On("Login", function()
    for _, group in ipairs(DUI.Fade.HubGroups()) do fadePage.groups[#fadePage.groups + 1] = group end
end)

-- Damage numbers page: the game's own floating numbers (DamageText.lua).
local DT = DUI.DamageText

local function damageFontChoices()
    local values, order = fontChoices()
    values.auto = "Automatic"
    table.insert(order, 1, "auto")
    return values, order
end

Options.DamageFontChoices = damageFontChoices

local PRESETS = { game = "Game default", soft = "Soft", punchy = "Punchy", clean = "Clean", custom = "Custom" }

local function motion(key, label, min, max, desc)
    return { type = "slider", key = "damage." .. key, label = label, min = min, max = max, step = 0.1,
             desc = desc, hidden = function() return DT.Has(key) ~= true end }
end

local function show(what, label, desc)
    return { type = "toggle", label = label, desc = desc,
             get = function() return DT.Shown(what) == true end,
             set = function(v) DT.SetShown(what, v) end,
             default = function() return DT.ShownDefault(what) end,
             hidden = function() return DT.Shown(what) == nil end }
end

Options.RegisterPage({
    id = "damage", section = "core", label = "Damage numbers", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "The game's numbers that pop off what you hit and heal. Hits and heals on you: General > Combat text.",
    sample = function(parent) return DT.Sample(parent) end,
    groups = {
        { label = "Style", items = {
            { type = "dropdown", label = "Damage number preset", values = PRESETS, order = DT.PRESET_ORDER,
              get = function() return DT.Preset() end,
              set = function(v) DT.SetPreset(v) end,
              default = function() return "game" end,
              hidden = function() return DT.Has("spread") ~= true end,
              desc = "Game default sends the numbers straight up. Soft drifts them out to the sides, Punchy flings them wide off the target, "
                  .. "Clean keeps them tight and close, out of the way in a raid. Moving a slider below makes it Custom." },
            { type = "dropdown", key = "damage.font", label = "Damage number font", choices = damageFontChoices, fallback = "auto",
              preview = "font", fetch = function(key)
                  if key == "auto" then return DUI.GameFonts.DamageWanted() or DUI.GameFonts.ClientFont() end
                  return DUI.Media.Fetch("font", key) or (DUI.Style.FontEntry(key) and DUI.Style.FontEntry(key).file)
              end,
              restart = "You must restart the game for the new damage numbers font to take effect.",
              desc = "Automatic is your Appearance font. "
                  .. "The sample above shows it at once; the numbers in the world change after you restart the game." },
            motion("size", "Damage number size", 0.5, 2.5, "How big the numbers are. 1 is the game's own size."),
        } },
        { label = "Motion", desc = "The game's own settings for how the numbers leave the target.", items = {
            motion("spread", "Damage number spread", 0, 5, "How far the numbers fly out to the sides. At 0 they go straight up, the game's own way."),
            motion("height", "Damage number start distance", 0, 5, "How far from the target the numbers start."),
        } },
        { label = "Which numbers", desc = "The game's own switches.", items = {
            show("damage", "Damage you deal", "The numbers over what you hit."),
            show("healing", "Healing you do", "The green numbers over who you heal."),
            show("pet", "Your pet's damage", "The numbers over what your pet or totems hit."),
        } },
    },
})

Options.RegisterPage(DUI.CombatText.Page(Options))

-- Gradients page: paint options, then a card per group with a row per pair.
-- Rebuilt when a module registers a pair later. Classes this client doesn't
-- have get no rows.
local NO_SUCH_CLASS = { DEATHKNIGHT = true, DEMONHUNTER = true, MONK = true, EVOKER = true }

local function gradientGroups()
    local G = DUI.Gradients
    local flat = function() return G.Flat() end
    local groups = { { label = "Gradient settings", items = {
        { type = "toggle", key = "gradients.off", invert = true, label = "Gradients",
          desc = "When off, every bar, border and highlight uses one flat color instead of two blended ones. The colors below still pick that color: the middle of each pair." },
        { type = "dropdown", key = "gradients.palette", label = "Gradient palette",
          values = G.PaletteValues(), order = G.PALETTE_ORDER,
          desc = "Picks a whole set of colors at once. Colors you changed yourself are kept; a row's reset button sets it back to the palette." },
        { type = "dropdown", key = "gradients.orientation", label = "Gradient direction", disabled = flat,
          values = G.ORIENTATIONS, order = G.ORIENTATION_ORDER,
          desc = "Which way the color runs along a bar." },
        { type = "toggle", key = "gradients.invert", label = "Invert gradients", disabled = flat,
          desc = "Swaps the ends: light to dark instead of dark to light." },
        { type = "button", label = "Reset all colors", text = "Reset", confirm = true,
          desc = "Sets every pair back to the palette's colors. Gradient direction and Invert gradients are kept.",
          disabled = function() return not G.AnyChanged() end, func = G.ResetAll },
    } } }
    for _, group in ipairs(G.GROUPS) do
        local items = {}
        for _, key in ipairs(G.Keys(group.id)) do
            if not NO_SUCH_CLASS[key] then
                items[#items + 1] = G.Item(key)
            end
        end
        if #items > 0 then groups[#groups + 1] = { label = group.label, desc = group.desc, items = items } end
    end
    return groups
end

local gradientPage = Options.RegisterPage({
    id = "gradients", section = "core", label = "Gradients", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "The two-color pairs behind the gradient accent, bars, cast bars, reputation and more, wherever a gradient is picked.",
    groups = gradientGroups(),
})
DUI.On("GradientsRegistered", function() gradientPage.groups = gradientGroups() end)

Options.RegisterPage({
    id = "layout", section = "core", label = "Layout", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "Where things sit on your screen.",
    groups = {
        { label = "Moving frames", items = {
            PREVIEW,
            UNLOCK,
            { type = "toggle", key = "gridSnap", label = "Snap to grid",
              desc = "Shows a grid while frames are unlocked, and snaps them to it." },
            { type = "toggle", key = "magnet", label = "Snap to other frames",
              desc = "While moving frames, edges and centers line up with other frames. Hold Shift to drop anywhere." },
            RESET_POSITIONS,
        } },
        { label = "Beta", items = {
            { type = "toggle", key = "hidePTRButton", invert = true, label = "Show the issue reporter",
              hidden = function() return not (DUI.PTRButton and DUI.PTRButton.Available()) end,
              desc = "Blizzard's bug-report button and the quest feedback box that test clients show. When off, they're hidden. Only on beta and PTR." },
        } },
    },
})
