-- The addon's text, for translators.
-- Run from the repo root (needs tests/blizzard/, like the tests):
--   luajit tools/locale.lua keys              every English text, one per line
--   luajit tools/locale.lua missing deDE      deDE's missing lines, ready to paste
--   luajit tools/locale.lua stats             per language: reviewed, draft, missing
-- The text set is tests/locale_keys.lua's: every L["..."] in a shipped file
-- plus every text the options window and the setup guide draw from data.
-- A language file's lines below its "Machine draft" line count as drafts.

package.path = "tests/?.lua;" .. package.path
T = T or {}   -- tests/stub.lua reads the test helpers' table
local stub = require("stub")
local K = require("locale_keys")

local function keySet()
    local DUI = stub.Load{ module = true, actionbars = true, buffs = true, bags = true, nameplates = true,
        tooltip = true, qol = true, chat = true, infopanel = true, skins = true, quests = true }
    local keys = K.Walk(DUI, K.Scan())
    local list = {}
    for k in pairs(keys) do list[#list + 1] = k end
    table.sort(list)
    return list, keys
end

local function quote(s)
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

-- Which of a file's lines sit below its "Machine draft" line.
local function drafts(path)
    local out, below = {}, false
    for line in io.lines(path) do
        if line:find("Machine draft", 1, true) then below = true end
        local key = below and line:match('^L%["(.-)"%]%s*=')
        if key then out[key] = true end
    end
    return out
end

local cmd, arg = arg[1], arg[2]
if cmd == "keys" then
    for _, k in ipairs((keySet())) do print(quote(k)) end
elseif cmd == "missing" and arg then
    local path = K.LanguageFiles()[arg] or ("Locales/" .. arg .. ".lua")
    local have = (io.open(path) and K.LoadLanguage(path, arg)) or {}
    for _, k in ipairs((keySet())) do
        if have[k] == nil then print("L[" .. quote(k) .. '] = ""') end
    end
elseif cmd == "stats" then
    local list = keySet()
    print(string.format("%d texts", #list))
    for locale, path in pairs(K.LanguageFiles()) do
        local have, draft = K.LoadLanguage(path, locale) or {}, drafts(path)
        local reviewed, drafted, missing = 0, 0, 0
        for _, k in ipairs(list) do
            if have[k] == nil then missing = missing + 1
            elseif draft[k] then drafted = drafted + 1
            else reviewed = reviewed + 1 end
        end
        print(string.format("%s: %d reviewed, %d draft, %d missing", locale, reviewed, drafted, missing))
    end
else
    print("luajit tools/locale.lua keys | missing <locale> | stats")
end
