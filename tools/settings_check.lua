-- Checks a player's saved settings (DaylightUIDB) against the defaults, the way a
-- profile switch or an old character would meet them:
--   * a saved value of a different kind than its default (a number where a switch
--     belongs), which can break the code reading it
--   * a saved setting whose name no shipped code mentions any more, left behind by
--     a rename or a removed feature
--   * a module's settings saved under a name no module registers
-- Run from the repo root (needs tests/blizzard/, like the tests):
--   luajit tools/settings_check.lua               every account's file in WTF/
--   luajit tools/settings_check.lua <file.lua>    one saved file (a player's, sent in)
-- Settings with an empty table as their default ({}: lists, spots, groups the
-- player fills) are free-form and not looked inside.

package.path = "tests/?.lua;" .. package.path
T = T or {}   -- tests/stub.lua reads the test helpers' table
local stub = require("stub")

local DUI = stub.Load({ module = true, actionbars = true, buffs = true, skins = true, bags = true,
    nameplates = true, tooltip = true, qol = true, chat = true, infopanel = true, quests = true })
local defaults = DUI.DB.Fill({})

-- Every word in shipped Lua, to tell a stale key from one read under a built name
-- ("bankLook" .. i). A key counts as used when its name, or its name without
-- trailing digits, is a word there.
local words = {}
do
    local h = io.popen('git ls-files -- "*.lua" ":!tests" ":!Libs" ":!DaylightUI_Dev" ":!tools"')
    for path in h:lines() do
        local f = io.open(path, "r")
        if f then
            for w in f:read("*a"):gmatch("[%a_][%w_]*") do words[w] = true end
            f:close()
        end
    end
    h:close()
end
local function used(key)
    return words[key] or words[(key:gsub("%d+$", ""))] or false
end

local function kind(v)
    if type(v) == "table" then return next(v) == nil and "table" or (v[1] ~= nil and "list" or "table") end
    return type(v)
end

local function shown(v)
    if type(v) == "table" then return "table" end
    return type(v) .. " (" .. tostring(v) .. ")"
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

local problems
local function report(where, msg)
    problems[#problems + 1] = "  " .. where .. ": " .. msg
end

-- plugin: keys a plugin added to this module (DaylightUIDB.pluginKeys). They're
-- kept on purpose while the plugin is off and never count as stale.
local function walk(saved, def, where, plugin)
    if type(saved) ~= "table" or type(def) ~= "table" then return end
    if next(def) == nil then return end   -- free-form, the player's own entries
    for k, v in pairs(saved) do
        local path = where .. "." .. tostring(k)
        local d = def[k]
        if d == nil and type(plugin) == "table" and plugin[k] then
            -- a plugin's own setting
        elseif d == nil then
            if type(k) == "string" and not used(k) then
                report(path, "saved, but no shipped code mentions \"" .. k .. "\" (stale?)")
            end
        elseif type(d) ~= type(v) then
            report(path, "saved as a " .. shown(v) .. ", its default is a " .. shown(d))
        elseif type(v) == "table" then
            walk(v, d, path)
        end
    end
end

local function checkFile(path)
    local chunk = loadfile(path)
    if not chunk then print(path .. ": can't read it"); return 0 end
    local env = {}
    setfenv(chunk, env)
    if not pcall(chunk) or type(env.DaylightUIDB) ~= "table" then
        print(path .. ": no DaylightUIDB in it"); return 0
    end
    problems = {}
    local pd = env.DaylightUIDB.profileData or {}
    local names = {}
    for name in pairs(pd) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local p = pd[name]
        local at = "[" .. name .. "]"
        if type(p) ~= "table" then
            report(at, "a profile that isn't a table")
        else
            -- Old settings get migrated first (DB.Fill), so check what is read after that.
            p = copy(p)
            if DUI.FadeUpgrade then DUI.FadeUpgrade.Run(p) end
            walk(p.general, defaults.general, at .. " general")
            for mod, saved in pairs(p.modules or {}) do
                if defaults.modules[mod] == nil then
                    if not used(mod) then report(at .. " modules." .. mod, "no module registers this name (stale?)") end
                else
                    local pk = type(env.DaylightUIDB.pluginKeys) == "table" and env.DaylightUIDB.pluginKeys[mod] or nil
                    walk(saved, defaults.modules[mod], at .. " " .. mod, pk)
                end
            end
        end
    end
    table.sort(problems)
    print(path .. ": " .. #names .. " profile(s), " .. #problems .. " finding(s)")
    for _, line in ipairs(problems) do print(line) end
    return #problems
end

local files = {}
if arg[1] then
    files[1] = arg[1]
else
    local h = io.popen('dir /b /s "..\\..\\..\\WTF\\Account\\DaylightUI.lua" 2>nul')
    for line in h:lines() do
        if line:find("SavedVariables\\DaylightUI%.lua$") then files[#files + 1] = line end
    end
    h:close()
end
if #files == 0 then
    print("No saved file found: pass one, luajit tools/settings_check.lua <path>")
    os.exit(1)
end
local total = 0
for _, f in ipairs(files) do total = total + checkFile(f) end
os.exit(total == 0 and 0 or 1)
