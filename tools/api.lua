-- What the game's own API docs say about a function, event or widget method, in
-- plain words: its arguments and returns, and above all when it hands back secret
-- values or refuses them.
-- Run from the repo root (needs tests/blizzard/: py tools/fetch_blizzard.py):
--   luajit tools/api.lua UnitHealth            a function (Namespace.Name works too)
--   luajit tools/api.lua UNIT_AURA             an event
--   luajit tools/api.lua SetText               a widget method, on every widget type that has it
--   luajit tools/api.lua Threat                no exact match: every name containing it
-- Each match also lists where shipped code already calls it.

package.path = "tests/?.lua;" .. package.path
local Blizz = require("blizzard")
local Secret = require("secret_api")
local Widgets = require("widget_api")

local query = arg[1]
if not query then
    print("usage: luajit tools/api.lua <function | event | widget method | part of a name>")
    os.exit(1)
end

-- What each flag means in play. A flag not listed is printed as the docs spell it.
local WHEN_WORDS = {
    always = "ALWAYS secret, out of combat too",
    combat = "secret in combat",
    restricted = "secret in combat and under the client's restrictions (boss fight, keystone, PvP match, restricted map)",
    spellcast = "secret for units other than you and your pet, in combat and under restrictions",
    threatValues = "secret vs bosses (ask C_Secrets.ShouldUnitThreatValuesBeSecret)",
    threatState = "secret outside your group (ask C_Secrets.ShouldUnitThreatStateBeSecret)",
    identity = "secret in a PvP match or a restricted map (enemy names, classes)",
    chat = "secret in chat lockdown",
}
local ARG_WORDS = {
    AllowedWhenTainted = "TAKES secret arguments from our code",
    AllowedWhenUntainted = "REFUSES secret arguments from our code (errors)",
    NotAllowed = "REFUSES secret arguments (errors)",
}
local KNOWN = { Name = true, Type = true, Arguments = true, Returns = true, Payload = true, Namespace = true,
                LiteralName = true, Documentation = true, SecretArguments = true, Fields = true }

local found = { functions = {}, events = {}, widgets = {} }
local function typeOf(file)
    return (file:gsub("Documentation%.lua$", ""):gsub("^FrameAPI", ""):gsub("^Simple", ""):gsub("API$", ""))
end

local function load(sub, filter)
    local file
    local docs = {}
    function docs:AddDocumentationTable(t)
        for _, fn in ipairs(t.Functions or {}) do
            local ns = fn.Namespace or t.Namespace
            local full = (ns and ns ~= "") and (ns .. "." .. fn.Name) or fn.Name
            if sub == "" then
                local w = found.widgets[fn.Name] or { types = {}, fn = fn }
                found.widgets[fn.Name] = w
                w.types[#w.types + 1] = { type = typeOf(file), fn = fn }
            else
                found.functions[full] = { fn = fn, short = fn.Name }
            end
        end
        for _, e in ipairs(t.Events or {}) do
            if e.LiteralName then found.events[e.LiteralName] = e end
        end
    end
    local env = setmetatable({ APIDocumentation = docs }, { __index = function() return Blizz.INERT end })
    for f in Blizz.List("", sub ~= "" and sub or nil) do
        if filter(f) then
            file = f
            local chunk = loadfile(Blizz.DIR .. sub .. f)
            if chunk then setfenv(chunk, env); pcall(chunk) end
        end
    end
end

if not Blizz.Have("api/FILES.txt") then
    print("tests/blizzard/ is missing: run py tools/fetch_blizzard.py once.")
    os.exit(1)
end
load("api/", function() return true end)
load("", Widgets.IsWidgetDoc)

local function list(fields)
    local out = {}
    for _, a in ipairs(fields or {}) do
        local s = a.Name .. ": " .. tostring(a.Type) .. (a.Nilable and "?" or "")
        if a.NeverSecret then s = s .. " (never secret)" end
        if a.SecretValue or a.ConditionalSecret then s = s .. " (can be SECRET)" end
        out[#out + 1] = s
    end
    return #out > 0 and table.concat(out, ", ") or "none"
end

local function extraFlags(t)
    local out = {}
    for k, v in pairs(t) do
        if not KNOWN[k] and not Secret.WHEN[k] and not Secret.EVENT_WHEN[k] and type(v) ~= "table" then out[#out + 1] = k .. (v ~= true and ("=" .. tostring(v)) or "") end
    end
    table.sort(out)
    return out
end

local function secretLine(t)
    for flag, when in pairs(Secret.WHEN) do
        if t[flag] then return "returns " .. (WHEN_WORDS[when] or when) .. "  [" .. flag .. "]" end
    end
    for flag, when in pairs(Secret.EVENT_WHEN) do
        if t[flag] then return "payload " .. (WHEN_WORDS[when] or when) .. "  [" .. flag .. "]" end
    end
    if t.ReturnsNeverSecret then return "returns never secret" end
end

-- Shipped code that calls the name: git grep, leaving out tests, Libs and the dev addon.
local function uses(name)
    local short = name:match("([%w_]+)$")
    local cmd = 'git grep -n -w "' .. short .. '" -- "*.lua" ":!tests" ":!Libs" ":!DaylightUI_Dev" ":!tools" 2>&1'
    local h = io.popen(cmd)
    local lines = {}
    for line in h:lines() do lines[#lines + 1] = line end
    h:close()
    if #lines == 0 then return "  ours: not called anywhere" end
    local out = { "  ours: " .. #lines .. " line(s)" }
    for i = 1, math.min(5, #lines) do out[#out + 1] = "    " .. lines[i]:sub(1, 140) end
    if #lines > 5 then out[#out + 1] = "    ..." end
    return table.concat(out, "\n")
end

local function showFunction(full, rec)
    local fn = rec.fn
    print(full .. "  (function)")
    print("  args:    " .. list(fn.Arguments))
    print("  returns: " .. list(fn.Returns))
    local s = secretLine(fn)
    print("  secret:  " .. (s or "no secret flag in the docs"))
    if fn.SecretArguments then print("  args in: " .. (ARG_WORDS[fn.SecretArguments] or fn.SecretArguments)) end
    local extra = extraFlags(fn)
    if #extra > 0 then print("  flags:   " .. table.concat(extra, ", ")) end
    print(uses(full))
end

local function showEvent(name, e)
    print(name .. "  (event)")
    print("  payload: " .. list(e.Payload))
    local s = secretLine(e)
    print("  secret:  " .. (s or "no event-wide secret flag (check (can be SECRET) above)"))
    local extra = extraFlags(e)
    if #extra > 0 then print("  flags:   " .. table.concat(extra, ", ")) end
    print(uses(name))
end

local function showWidget(name, w)
    print(name .. "  (widget method)")
    local by, order = {}, {}
    for _, t in ipairs(w.types) do
        local key = (ARG_WORDS[t.fn.SecretArguments] or "no secret-argument rule") ..
            (t.fn.SecretWhenAnchoringSecret and "; its returns go secret when anchoring is secret" or "")
        if not by[key] then by[key] = { fn = t.fn }; order[#order + 1] = key end
        table.insert(by[key], t.type)
    end
    for _, key in ipairs(order) do
        local g = by[key]
        table.sort(g)
        print("  " .. key .. ":  " .. table.concat(g, ", "))
        print("    args: " .. list(g.fn.Arguments) .. "   returns: " .. list(g.fn.Returns))
    end
    print(uses(name))
end

-- Exact matches first (a function by full or short name, an event, a widget
-- method), else every name containing the query.
local shown = 0
local function exact(q)
    if found.functions[q] then showFunction(q, found.functions[q]); shown = shown + 1 end
    for full, rec in pairs(found.functions) do
        if rec.short == q and full ~= q then showFunction(full, rec); shown = shown + 1 end
    end
    if found.events[q] then showEvent(q, found.events[q]); shown = shown + 1 end
    if found.widgets[q] then showWidget(q, found.widgets[q]); shown = shown + 1 end
end
exact(query)

if shown == 0 then
    local lq = query:lower()
    local names = {}
    for full in pairs(found.functions) do if full:lower():find(lq, 1, true) then names[#names + 1] = full end end
    for name in pairs(found.events) do if name:lower():find(lq, 1, true) then names[#names + 1] = name .. " (event)" end end
    for name in pairs(found.widgets) do if name:lower():find(lq, 1, true) then names[#names + 1] = name .. " (widget)" end end
    table.sort(names)
    if #names == 0 then
        print("Nothing in the game's API docs matches \"" .. query .. "\".")
        print("Not documented doesn't mean missing: grep tests/blizzard/ for the game's own UI code.")
        os.exit(1)
    end
    print(#names .. " name(s) contain \"" .. query .. "\"; run again with one:")
    for i = 1, math.min(60, #names) do print("  " .. names[i]) end
    if #names > 60 then print("  ... (" .. (#names - 60) .. " more: be more exact)") end
end
