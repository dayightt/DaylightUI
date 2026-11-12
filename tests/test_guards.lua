-- Scans every shipped file (each .toc's list) for patterns that broke the game
-- before. Each rule names its bug. A reviewed exception goes in
-- tests/guards_allow.lua with a reason, so nothing risky slips in quietly.
local ALLOW = require("guards_allow")

-- New module: add its .toc here.
local TOCS = {
    "DaylightUI.toc",
    "DaylightUI_ActionBars/DaylightUI_ActionBars.toc", "DaylightUI_Bags/DaylightUI_Bags.toc",
    "DaylightUI_Buffs/DaylightUI_Buffs.toc", "DaylightUI_Chat/DaylightUI_Chat.toc",
    "DaylightUI_InfoPanel/DaylightUI_InfoPanel.toc", "DaylightUI_Nameplates/DaylightUI_Nameplates.toc",
    "DaylightUI_QoL/DaylightUI_QoL.toc", "DaylightUI_Quests/DaylightUI_Quests.toc", "DaylightUI_Skins/DaylightUI_Skins.toc",
    "DaylightUI_Tooltip/DaylightUI_Tooltip.toc", "DaylightUI_UnitFrames/DaylightUI_UnitFrames.toc",
}

local function shippedFiles()
    local files = {}
    for _, toc in ipairs(TOCS) do
        local dir = toc:match("^(.*/)") or ""
        for line in io.lines(toc) do
            line = line:gsub("\r", ""):gsub("\\", "/")
            if not line:find("^%s*#") and line:find("%.lua%s*$") then
                files[#files + 1] = dir .. line:gsub("%s+$", "")
            end
        end
    end
    return files
end

local function code(line) return (line:gsub("%-%-.*$", "")) end    -- drop a trailing comment

local TRACKER = { "SetPoint", "ClearAllPoints", "SetParent", "Hide", "Show", "SetShown", "SetScript", "Update" }

-- { id, why, test(line) -> true when the line breaks the rule }
local RULES = {
    { "load-game-addon", "loading the game's own addons from ours (45cdef0)",
      function(l) return l:find("LoadAddOn(", 1, true) end },
    { "tracker-structural", "ObjectiveTrackerFrame touched structurally: breaks the world map",
      function(l)
          for _, m in ipairs(TRACKER) do
              if l:find("ObjectiveTrackerFrame:" .. m .. "(", 1, true) then return true end
          end
      end },
    { "quest-marker-show", "a quest marker's Show/Hide taints the world map",
      function(l)
          return l:find("poiButton:Show(", 1, true) or l:find("poiButton:Hide(", 1, true)
              or l:find("poiButton:SetShown(", 1, true)
      end },
    -- DELETE_ITEM_CONFIRM is a synchronous event, so the game's delete pop-up
    -- opens inside our call and carries our taint. With the controller UI on,
    -- that pop-up's focus then taints the controller's bindings for the rest
    -- of the session (logging out, Escape, the interact target all refused).
    { "confirm-delete-item", "C_Item.ConfirmDeleteItem opens the game's delete pop-up under our taint: ask with a menu confirm and C_Item.DeleteItem",
      function(l) return l:find("ConfirmDeleteItem(", 1, true) end },
    { "mouseisover", "MouseIsOver is gone in this client: use frame:IsMouseOver()",
      function(l) return (" " .. l):find("[^%w_:%.]MouseIsOver%(") end },
    { "events-list-remove", "our buttons leave the game's events list by nil in place, never tremove (rule 4)",
      function(l) return l:find("ActionBarButtonEventsFrame.frames", 1, true) and l:find("remove", 1, true) end },
    -- UNIT_AURA's updateInfo fields are secret in combat and under restrictions
    -- (a reload in combat errored "boolean test on a secret boolean"). The fake
    -- game can't trap a truth test because its secrets are tables, so truthy.
    { "aura-update-secret", "UNIT_AURA's isFullUpdate can be secret: ask issecretvalue on the same line",
      function(l) return l:find("isFullUpdate", 1, true) and not l:find("issecretvalue", 1, true) end },
}

T.test("guards: no shipped file breaks a rule that broke the game before", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local n = 0
        for line in io.lines(path) do
            n = n + 1
            local c = code(line)
            for _, r in ipairs(RULES) do
                if r[3](c) and not ALLOW.rules[path .. "|" .. r[1]] then
                    bad[#bad + 1] = string.format("%s:%d [%s] %s", path, n, r[1], r[2])
                end
            end
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- Hooks on a game object's own methods caused the "call a nil value" floods,
-- so each one needs a reviewed reason.
-- Catches hooksecurefunc(obj, "Method", fn) and hooksecurefunc(obj, m, fn),
-- not the two-argument global form hooksecurefunc("Name", fn). Also the same
-- wrapped in pcall: pcall(hooksecurefunc, obj, "Method", fn).
local function hookOf(c)
    local obj, method = c:match('pcall%(%s*hooksecurefunc%s*,%s*([^,"\'%s][^,]-)%s*,%s*"([%w_]+)"')
    if obj then return obj, method end
    obj, method = c:match('hooksecurefunc%(%s*([^,"\'%s][^,]-)%s*,%s*"([%w_]+)"')
    if obj then return obj, method end
    return c:match('hooksecurefunc%(%s*([^,"\'%s][^,]-)%s*,%s*([%w_%.%[%]]+)%s*,')
end

T.test("guards: every hook on an object's method is on the allow-list with a reason", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        for line in io.lines(path) do
            local obj, method = hookOf(code(line))
            if obj and obj ~= "" then
                local key = path .. "|" .. obj .. "|" .. method
                if not ALLOW.hooks[key] then bad[#bad + 1] = string.format('["%s"] = "?",', key) end
            end
        end
    end
    if #bad > 0 then
        error("hooks not on tests/guards_allow.lua (only with a good reason):\n  "
            .. table.concat(bad, "\n  "), 0)
    end
end)

-- SetScript on a game global replaces the game's own handler (taint at the source).
T.test("guards: no SetScript on a game frame's global name unless allowed", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local f = assert(io.open(path)); local text = f:read("*a"); f:close()
        for name in text:gmatch("%f[%w_]([A-Z][%w_]*):SetScript%(") do
            if not name:find("^DaylightUI") and not text:find("local " .. name .. "%f[^%w_]")
               and not text:find("local [%w_, ]-%f[%w_]" .. name .. "%f[^%w_]")
               and not ALLOW.setscript[path .. "|" .. name] then
                bad[#bad + 1] = string.format('["%s|%s"] = "?",', path, name)
            end
        end
    end
    if #bad > 0 then error("SetScript on game frames:\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- Each file's own part (its first top-level `ns.Name = local`, or
-- `DUI.Name = local` in the core, names needn't match as in `ns.Minimap = Map`)
-- must be in its module's parts list in Module.lua or in DUI.CORE_PARTS, and
-- load before Module.lua, so a file missing after an update is caught. A
-- folder with its own Module.lua (Character/, DaylightUI_Chat/Window/) is
-- checked as a module of its own.
local NOT_A_PART = { ["true"] = true, ["false"] = true, ["nil"] = true }

local function partsOf(path, owner)
    for line in io.lines(path) do
        local name, rhs = line:match("^" .. owner .. "%.([%w_]+)%s*=%s*([%a_][%w_]*)%s*$")
        if name and not NOT_A_PART[rhs] then return name end
    end
end

local function exists(path)
    local f = io.open(path)
    if f then f:close() end
    return f ~= nil
end

local function listed(path, field)
    local f = assert(io.open(path)); local text = f:read("*a"); f:close()
    local body = text:match(field .. "%s*=%s*(%b{})")
    local set = {}
    for n in (body or ""):gmatch('"([%w_]+)"') do set[n] = true end
    return set, body ~= nil
end

T.test("guards: every module lists the parts its files define (restart message)", function()
    local bad, lists = {}, {}
    local function list(listFile, core)
        if not lists[listFile] then
            local set, found = listed(listFile, core and "DUI%.CORE_PARTS" or "parts")
            if not found then bad[#bad + 1] = listFile .. ": no parts list" end
            lists[listFile] = set
        end
        return lists[listFile]
    end
    for _, toc in ipairs(TOCS) do
        local dir = toc:match("^(.*/)") or ""
        local seenModule = {}
        for line in io.lines(toc) do
            line = line:gsub("\r", ""):gsub("\\", "/"):gsub("%s+$", "")
            if not line:find("^#") and line:find("%.lua$") then
                local path = dir .. line
                local sub = dir == "" and path:match("^[^/]+/")
                local inner = dir ~= "" and path:match("^(.*/)")
                local home = (inner and inner ~= dir and exists(inner .. "Module.lua") and inner)
                    or (dir ~= "" and dir) or (sub and exists(sub .. "Module.lua") and sub) or ""
                local core = home == ""
                local listFile = core and "Core.lua" or (home .. "Module.lua")
                if path == listFile then seenModule[listFile] = true
                elseif path ~= "Core.lua" then
                    local set = list(listFile, core)
                    local part = partsOf(path, core and "DUI" or "ns")
                    if part and not set[part] then bad[#bad + 1] = listFile .. ": add \"" .. part .. "\" (" .. path .. ")" end
                    if part and seenModule[listFile] and not core then bad[#bad + 1] = path .. " loads after Module.lua" end
                end
            end
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

T.test("guards: every .toc has the core's version", function()
    local function version(path)
        local f = assert(io.open(path)); local text = f:read("*a"); f:close()
        return text:match("## Version:%s*(%S+)")
    end
    local core, bad = version("DaylightUI.toc"), {}
    for _, toc in ipairs(TOCS) do
        if version(toc) ~= core then bad[#bad + 1] = toc .. ": " .. tostring(version(toc)) end
    end
    if #bad > 0 then error("not " .. core .. ":\n  " .. table.concat(bad, "\n  "), 0) end
end)
