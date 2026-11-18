-- Turns the options map saved by /dui optionsmap into Options/options-map.json.
-- From the repo root, after /dui optionsmap and a /reload in game:
--   luajit tools/options_map.lua <WTF/Account/<name>/SavedVariables/DaylightUI.lua> [out.json]
-- Keys come out in a fixed order and lists keep the window's order, so a
-- release's diff shows only settings that changed.

local src, out = arg[1], arg[2] or "Options/options-map.json"
if not src then
    io.stderr:write("usage: luajit tools/options_map.lua <SavedVariables/DaylightUI.lua> [out.json]\n")
    os.exit(1)
end

local env = {}
local chunk = assert(loadfile(src, "t", env))
chunk()
local map = env.DaylightUIOptionsMap
if type(map) ~= "table" or type(map.settings) ~= "table" then
    io.stderr:write("no DaylightUIOptionsMap in " .. src .. ": run /dui optionsmap, then /reload\n")
    os.exit(1)
end

-- Fields first in reading order, any others after them by name.
local FIRST = { "version", "locale", "made", "missing", "errors", "settings",
    "path", "rail", "section", "page", "tab", "card", "pick", "label", "desc", "type", "button",
    "choices", "choicesVary", "min", "max", "step", "unit", "key", "text",
    "scope", "module", "name", "addon", "search", "searchable", "since",
    "conditional", "pageConditional", "reload", "restart" }
local RANK = {}
for i, k in ipairs(FIRST) do RANK[k] = i end

local function isList(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end

local function encode(v, indent, buf)
    local t = type(v)
    if t == "string" then buf[#buf + 1] = quote(v)
    elseif t == "number" then buf[#buf + 1] = (v == math.floor(v) and v < 1e15 and v > -1e15) and string.format("%d", v) or string.format("%.14g", v)
    elseif t == "boolean" then buf[#buf + 1] = tostring(v)
    elseif t == "table" then
        local list, n = isList(v)
        local pad, inner = string.rep("  ", indent), string.rep("  ", indent + 1)
        if list then
            if n == 0 then buf[#buf + 1] = "[]"; return end
            buf[#buf + 1] = "[\n"
            for i = 1, n do
                buf[#buf + 1] = inner
                encode(v[i], indent + 1, buf)
                buf[#buf + 1] = i < n and ",\n" or "\n"
            end
            buf[#buf + 1] = pad .. "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys, function(a, b)
                local ra, rb = RANK[a] or 1e9, RANK[b] or 1e9
                if ra ~= rb then return ra < rb end
                return a < b
            end)
            buf[#buf + 1] = "{\n"
            for i, k in ipairs(keys) do
                buf[#buf + 1] = inner .. quote(k) .. ": "
                encode(v[k], indent + 1, buf)
                buf[#buf + 1] = i < #keys and ",\n" or "\n"
            end
            buf[#buf + 1] = pad .. "}"
        end
    else
        buf[#buf + 1] = "null"
    end
end

local buf = {}
encode(map, 0, buf)
buf[#buf + 1] = "\n"
local f = assert(io.open(out, "wb"))
f:write(table.concat(buf))
f:close()
print(string.format("%s: %d settings from version %s (%s)", out, #map.settings, tostring(map.version), tostring(map.locale)))
if map.missing and #map.missing > 0 then
    print("not loaded when saved, so left out: " .. table.concat(map.missing, ", "))
end
