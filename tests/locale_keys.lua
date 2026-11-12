-- The set of English texts the language files may translate (DUI.L's keys):
-- every L["..."] literal in a shipped file, plus every text the options window and
-- the setup guide draw from their data (labels, help, button texts, dropdown
-- values, the guide's pages). Shared by tests/test_locale.lua and tools/locale.lua.

local K = {}

-- Modules whose own text isn't translated yet. The hygiene rule skips their
-- folders and the pseudo sweep skips their pages. Empty now that every module's
-- text goes through L, but kept for a new module brought in before its text is.
K.NOT_YET = {}

-- Folders and files that never ship, or whose text stays English.
K.SKIP = { "^tests/", "^tools/", "^Libs/", "^docs/", "^%.claude/", "^DaylightUI_Dev/", "/Libs/",
           "^PatchNotes%.lua$" }   -- the notes themselves stay English

function K.ShippedFiles()
    local out = {}
    local p = io.popen('git ls-files "*.lua"')   -- double quotes, since cmd.exe on Windows keeps single ones
    for path in p:lines() do
        local skip = false
        for _, pat in ipairs(K.SKIP) do
            if path:find(pat) then skip = true end
        end
        if not skip then out[#out + 1] = path end
    end
    p:close()
    table.sort(out)
    return out
end

local ESC = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }

-- A quoted string at i (src:sub(i, i) is the quote): its text and the position
-- after it.
local function quoted(src, i)
    local q = src:sub(i, i)
    local out, j = {}, i + 1
    while j <= #src do
        local c = src:sub(j, j)
        if c == "\\" then
            local n = src:sub(j + 1, j + 1)
            out[#out + 1] = ESC[n] or n
            j = j + 2
        elseif c == q then
            return table.concat(out), j + 1
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
end

-- Every L["..."] in src: { text, line }. Adjacent literals joined with .. count as
-- one text (a long sentence split over lines).
function K.Literals(src)
    local out = {}
    local pos = 1
    while true do
        local s, e = src:find("%f[%w_]L%[", pos)
        if not s then break end
        pos = e + 1
        local i = src:find("%S", pos)
        local parts, ok = {}, false
        while i and (src:sub(i, i) == '"' or src:sub(i, i) == "'") do
            local text, after = quoted(src, i)
            if not text then break end
            parts[#parts + 1] = text
            i = src:find("%S", after)
            if i and src:sub(i, i + 1) == ".." then
                i = src:find("%S", i + 2)
            elseif i and src:sub(i, i) == "]" then
                ok = true
                break
            else
                break
            end
        end
        if ok then
            local _, line = src:sub(1, s):gsub("\n", "")
            out[#out + 1] = { text = table.concat(parts), line = line + 1 }
        end
    end
    return out
end

-- Every L["..."] literal in shipped files: { [text] = "file:line" }.
function K.Scan(files)
    local keys = {}
    for _, path in ipairs(files or K.ShippedFiles()) do
        local f = io.open(path)
        local src = f:read("*a")
        f:close()
        for _, lit in ipairs(K.Literals(src)) do
            keys[lit.text] = keys[lit.text] or (path .. ":" .. lit.line)
        end
    end
    return keys
end

-- The texts the options window and the setup guide draw from data. DUI is a
-- stub.Load with every module on.
function K.Walk(DUI, keys)
    keys = keys or {}
    local function add(s, where)
        if type(s) == "string" and s:find("%a") then keys[s] = keys[s] or where end
    end
    local function addItem(item, at)
        add(item.label, at); add(item.desc, at); add(item.text, at)
        local values = item.values
        if item.choices then
            local ok, v = pcall(item.choices)
            values = ok and v or nil
        end
        if type(values) == "table" then
            for _, v in pairs(values) do add(v, at) end
        end
    end
    local O = DUI.Options
    for _, section in ipairs(O.Sections()) do
        add(section.label, "section " .. section.id)
        for _, page in ipairs(section.pages) do
            local at = "page " .. page.id
            add(page.label, at); add(page.desc, at)
            for _, group in ipairs(page.groups or {}) do
                add(group.label, at); add(group.desc, at)
                for _, item in ipairs(group.items or {}) do addItem(item, at) end
            end
        end
    end
    -- Options items a module draws outside the registered pages (the CDM editor's
    -- side panel), from its ns.LOOSE_ITEMS.
    for name, mod in DUI.Modules() do
        local list = type(mod.ns) == "table" and mod.ns.LOOSE_ITEMS
        for _, item in ipairs(type(list) == "table" and list or {}) do addItem(item, "module " .. name) end
    end
    for _, label in ipairs(DUI.Movers.Labels()) do add(label, "mover") end
    for _, part in ipairs(DUI.TestBox.parts) do add(part.label, "test part") end
    -- The unit frames' page samples. Each part's name shows in the strip's tooltip
    -- through Options.Text (the label is also the part's id there).
    local uf = DUI:GetModule("UnitFrames")
    for _, list in pairs(uf and uf.ns and uf.ns.PageSample or {}) do
        if type(list) == "table" then
            for _, part in ipairs(list) do
                if type(part) == "table" then add(part.label, "page sample") end
            end
        end
    end
    -- The nameplates' plate preview (Sample.lua) the same way.
    local np = DUI:GetModule("Nameplates")
    local npSample = np and np.ns and np.ns.Sample
    for _, part in ipairs(npSample and npSample.PARTS or {}) do add(part.label, "page sample") end
    local P = DUI.InstallerPages
    for _, m in ipairs(P.MODULES) do add(m.label, "guide modules"); add(m.pitch, "guide modules") end
    for _, c in ipairs(P.CLASHES) do add(c.what, "guide clashes") end
    for _, def in ipairs(P.TOUR) do
        local at = "guide " .. def.id
        add(def.title, at); add(def.desc, at)
        for _, g in ipairs(def.groups or {}) do
            add(g.label, at)
            if g.cards then add(g.cards.more, at) end
            for _, r in ipairs(g.rows or {}) do
                add(r.label, at)
                for _, c in ipairs(r.choice or {}) do add(c, at) end
            end
        end
    end
    return keys
end

-- The % holes of a text, in order ("%s", "%d", "%.1f"; "%%" counts too). No space
-- flag: none of the holes use one, and a plain percent sign in a sentence ("at
-- 100% it turns", "Show % sign") would read as one.
function K.Holes(s)
    local out = {}
    for h in s:gmatch("%%[-+#0]*%d*%.?%d*[%%cdeEfgGiouxXqs]") do out[#out + 1] = h end
    return table.concat(out, " ")
end

-- Color and texture codes, which must stay in step with the English.
function K.Codes(s)
    local _, c = s:gsub("|c", "")
    local _, r = s:gsub("|r", "")
    local _, t = s:gsub("|T", "")
    return c .. " " .. r .. " " .. t
end

-- The language files (Locales/<locale>.lua), by locale.
function K.LanguageFiles()
    local out = {}
    local p = io.popen("git ls-files -co --exclude-standard Locales")   -- no ls in cmd.exe; -o includes a new file not yet added
    for path in p:lines() do
        local locale = path:match("^Locales/(%a%a%a%a)%.lua$")
        if locale then out[locale] = path end
    end
    p:close()
    return out
end

-- A language file's lines on their own, { [english] = translation }, or nil and
-- the error when it doesn't load.
function K.LoadLanguage(path, locale, clientLocale)
    local L = setmetatable({}, { __index = function(_, k) return k end })
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    local ok, e = pcall(chunk, "DaylightUI", { LOCALE = clientLocale or locale, L = L })
    if not ok then return nil, e end
    local out = {}
    for k, v in pairs(L) do out[k] = v end
    return out
end

return K
