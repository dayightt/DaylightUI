-- Finds code nothing uses any more, so it can be cleaned up:
--   * functions no shipped code names (only the tests or the dev addon, or nothing)
--   * local functions their own file never calls
--   * settings in the defaults no code reads
--   * translated lines (Locales/<locale>.lua) whose English text is gone
-- Run from the repo root (needs tests/blizzard/, like the tests):
--   luajit tools/unused.lua              everything
--   luajit tools/unused.lua Book         only files whose path contains "Book"
--   luajit tools/unused.lua --tests      also the functions only the tests or the dev addon call
--                                         (often there for the tests: delete them with the test)
-- It matches by name, so read each one before deleting it. A name built at run time
-- ("On" .. kind, t[key]) or called by the game (a mixin's OnLoad) looks unused here.
-- Skipped: names in API.md (other addons call them), XML files and the game's
-- script names (On...), event handlers (ALL_CAPS), and dispatch tables (TYPES.X,
-- called by key).

package.path = "tests/?.lua;" .. package.path
T = T or {}   -- tests/stub.lua reads the test helpers' table
local stub = require("stub")
local K = require("locale_keys")

local only, withTests
for _, a in ipairs(arg) do
    if a == "--tests" then withTests = true else only = a end
end
local NOT_SHIPPED = { "^tests/", "^tools/", "^Libs/", "/Libs/", "^%.claude/", "^DaylightUI_Dev/", "^docs/" }

local function lines(cmd)
    local out, h = {}, io.popen(cmd)
    for l in h:lines() do out[#out + 1] = l end
    h:close()
    return out
end
local function readAll(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s
end

-- A line's code without its comment (a "--" outside a string).
local function code(line)
    local q
    for i = 1, #line do
        local c = line:sub(i, i)
        if q then
            if c == "\\" then i = i + 1 elseif c == q then q = nil end
        elseif c == '"' or c == "'" then q = c
        elseif c == "-" and line:sub(i + 1, i + 1) == "-" then return line:sub(1, i - 1) end
    end
    return line
end

-- Every file: its code lines (comments out, --[[ ]] blocks too).
local files = { shipped = {}, other = {} }
for _, path in ipairs(lines('git ls-files "*.lua"')) do
    local kind = "shipped"
    for _, pat in ipairs(NOT_SHIPPED) do if path:find(pat) then kind = "other" end end
    if not path:find("^Libs/") and not path:find("/Libs/") then
        local src = readAll(path):gsub("%-%-%[(=*)%[.-%]%1%]", function(s) return (s:gsub("[^\n]", "")) end)
        local ls = {}
        for l in (src .. "\n"):gmatch("(.-)\r?\n") do ls[#ls + 1] = code(l) end
        files[kind][path] = ls
    end
end

local function countWords(set)
    local n = {}
    for _, ls in pairs(set) do
        for _, l in ipairs(ls) do
            for w in l:gmatch("[%a_][%w_]*") do n[w] = (n[w] or 0) + 1 end
        end
    end
    return n
end
local shippedWords, otherWords = countWords(files.shipped), countWords(files.other)
-- Names other addons or the game call: API.md, the XML and .toc files.
local public = {}
for w in readAll("API.md"):gmatch("[%a_][%w_]*") do public[w] = true end
for _, path in ipairs(lines('git ls-files "*.xml" "*.toc"')) do
    for w in readAll(path):gmatch("[%a_][%w_]*") do public[w] = true end
end
-- The ends of every string joined with .., so a setting read as name .. "Mode"
-- counts as read for every <something>Mode.
local tails = {}
for _, ls in pairs(files.shipped) do
    for _, l in ipairs(ls) do
        for lit in l:gmatch('%.%.%s*"([%w_%.]+)"') do tails[lit:match("([%w_]+)$") or lit] = true end
    end
end

local function wanted(path) return not only or path:find(only, 1, true) end

-- Functions
local defs, locals = {}, {}
for path, ls in pairs(files.shipped) do
    for i, l in ipairs(ls) do
        local full = l:match("^%s*function%s+([%w_%.:]+)%s*%(")
        local field = l:match("([%w_]+[%.:][%w_%.:]+)%s*=%s*function%s*%(")
        local loc = l:match("^%s*local%s+function%s+([%w_]+)")
        local name = full or field
        if name and not name:find("^local") then
            local short = name:match("([%w_]+)$")
            defs[short] = defs[short] or {}
            table.insert(defs[short], { path = path, line = i, full = name })
        end
        if loc then table.insert(locals, { path = path, line = i, name = loc }) end
    end
end

local found = { fn = {}, testOnly = {}, loc = {}, settings = {}, texts = {} }
for short, list in pairs(defs) do
    local uses = (shippedWords[short] or 0) - #list
    if uses <= 0 and not public[short] and not short:find("On%u") and not short:find("^[%u%d_]+$") then
        for _, d in ipairs(list) do
            local owner = d.full:match("([%w_]+)[%.:][%w_]+$")
            if wanted(d.path) and not (owner and owner:find("^[%u%d_]+$") and #owner > 1) then
                local where = d.path .. ":" .. d.line .. "  " .. d.full
                if (otherWords[short] or 0) > 0 then table.insert(found.testOnly, where)
                else table.insert(found.fn, where) end
            end
        end
    end
end
for _, d in ipairs(locals) do
    if wanted(d.path) then
        local n = 0
        for _, l in ipairs(files.shipped[d.path]) do
            for w in l:gmatch("[%a_][%w_]*") do if w == d.name then n = n + 1 end end
        end
        if n <= 1 then table.insert(found.loc, d.path .. ":" .. d.line .. "  " .. d.name) end
    end
end

-- Settings
local DUI = stub.Load({ module = true, actionbars = true, buffs = true, skins = true, bags = true,
    nameplates = true, tooltip = true, qol = true, chat = true, infopanel = true, quests = true })
local defaults = DUI.DB.Fill({})
local function used(key)
    -- once is the default itself; a name built with a number ("bankLook" .. i) counts by its stem
    if (shippedWords[key] or 0) > 1 or (shippedWords[(key:gsub("%d+$", ""))] or 0) > 1 then return true end
    local tail = key:match("[%l%d](%u[%l%d]*)$")
    return tail ~= nil and tails[tail] == true
end
local function walk(t, where)
    if next(t) == nil then return end   -- free-form, the player's own entries
    for k in pairs(t) do   -- data keyed by name ("Mark of the Wild"), not settings
        if type(k) == "string" and not k:find("^[%a_][%w_]*$") then return end
    end
    for k, v in pairs(t) do
        if type(k) == "string" then
            if not used(k) then table.insert(found.settings, where .. "." .. k)
            elseif type(v) == "table" then walk(v, where .. "." .. k) end
        end
    end
end
if not only then
    walk(defaults.general, "general")
    for mod, d in pairs(defaults.modules) do walk(d, mod) end
end

-- Translations
if not only then
    local keys = K.Walk(DUI, K.Scan())
    for locale, path in pairs(K.LanguageFiles()) do
        local have = K.LoadLanguage(path, locale) or {}
        for english in pairs(have) do
            if not keys[english] then table.insert(found.texts, locale .. ': "' .. english .. '"') end
        end
    end
end

-- Report
local function section(title, list)
    if #list == 0 then return 0 end
    table.sort(list)
    print(title .. " (" .. #list .. "):")
    for _, l in ipairs(list) do print("  " .. l) end
    print("")
    return #list
end
local total = section("Functions no code names", found.fn)
    + (withTests and section("Functions only the tests or the dev addon use", found.testOnly) or 0)
    + section("Local functions their file never calls", found.loc)
    + section("Settings in the defaults no code reads", found.settings)
    + section("Translated lines whose English text is gone", found.texts)
if not withTests and #found.testOnly > 0 then
    print("(" .. #found.testOnly .. " more only the tests or the dev addon call: --tests lists them)")
end
if total == 0 then print("Nothing unused found" .. (only and (" in files matching \"" .. only .. "\"") or "") .. ".")
else print("Read each one before deleting: a name built at run time or called by the game looks unused here.") end
