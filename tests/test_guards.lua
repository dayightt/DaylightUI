-- Scans every shipped file (each .toc's list) for patterns that broke the game
-- before. Each rule names its bug. A reviewed exception goes in
-- tests/guards_allow.lua with a reason, so nothing risky slips in quietly.
local ALLOW = require("guards_allow")

-- New module: add its .toc here.
local TOCS = {
    "DaylightUI.toc",
    "DaylightUI_ActionBars/DaylightUI_ActionBars.toc", "DaylightUI_AuctionHouse/DaylightUI_AuctionHouse.toc", "DaylightUI_Bags/DaylightUI_Bags.toc",
    "DaylightUI_Buffs/DaylightUI_Buffs.toc", "DaylightUI_Chat/DaylightUI_Chat.toc",
    "DaylightUI_InfoPanel/DaylightUI_InfoPanel.toc", "DaylightUI_Nameplates/DaylightUI_Nameplates.toc",
    "DaylightUI_QoL/DaylightUI_QoL.toc", "DaylightUI_Quests/DaylightUI_Quests.toc", "DaylightUI_Skins/DaylightUI_Skins.toc",
    "DaylightUI_Tooltip/DaylightUI_Tooltip.toc", "DaylightUI_UnitFrames/DaylightUI_UnitFrames.toc", "DaylightUI_Procs/DaylightUI_Procs.toc",
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
    -- Opening the game's chat box from addon code leaves its active and last box
    -- tainted for the session: a reply to a hidden name then errors on every
    -- Enter (the game's UpdateHeader), and with the controller UI on the pad
    -- stays dead until a reload (SetPreferredGamepadInteractTarget refused).
    -- Pad.Whisper and Pad.Share whisper and share without it.
    { "open-chat", "opening the game's chat box from addon code taints the controller: use DUI.Pad.Whisper / DUI.Pad.Share",
      function(l)
          return l:find("OpenChat", 1, true) or l:find("SendTell", 1, true) or l:find("SendBNetTell", 1, true)
      end },
    -- DELETE_ITEM_CONFIRM is a synchronous event, so the game's delete pop-up
    -- opens inside our call and carries our taint. With the controller UI on,
    -- that pop-up's focus then taints the controller's bindings for the rest
    -- of the session (logging out, Escape, the interact target all refused).
    { "confirm-delete-item", "C_Item.ConfirmDeleteItem opens the game's delete pop-up under our taint: ask with a menu confirm and C_Item.DeleteItem",
      function(l) return l:find("ConfirmDeleteItem(", 1, true) end },
    -- StaticPopup_Show run by addon code writes the game's shared pop-up state
    -- (dialog fields, its order ids) under our taint. The game's own pop-ups
    -- read it later, so Leave Instance Group (LeaveInstanceParty) or logging out
    -- (CancelLogout) was refused and blamed on Daylight UI.
    { "static-popup", "the game's pop-ups opened or defined by Daylight UI taint them: ask with DUI.Widgets.Ask",
      function(l)
          return l:find("StaticPopup_Show(", 1, true) or l:find("StaticPopup_Queue(", 1, true)
              or l:match("StaticPopupDialogs[%.%[][%w_\"'%]]*%s*=[^=]")
      end },
    -- The game's Escape and losing control close every frame on UISpecialFrames.
    -- One maker (Motion.EscapeFor) knows when a window is open and closes it
    -- through its own close; a second stand-in would close a window twice or
    -- keep Escape from the game menu while the window fades out.
    { "special-frames", "Escape for a window of ours goes through Motion.EscapeFor (Win.New and Motion.Window use it)",
      function(l) return l:find("UISpecialFrames", 1, true) and l:find("insert", 1, true) end },
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

-- The game runs Lua 5.1, which refuses a line that starts with "(" right after
-- something that could be called ("ambiguous syntax (function call x new
-- statement)"). The tests run on LuaJIT, which takes it, so one such line once
-- got as far as the game and Style.lua failed to load, taking every file that
-- uses it down too. Strings and comments are blanked first so their text can't
-- look like code; newlines stay so line numbers still match.
local function blank(s) return (s:gsub("[^\n]", "")) end

local function codeOnly(text)
    local out, i, n = {}, 1, #text
    while i <= n do
        local s = text:find("[\"'%-%[]", i)
        if not s then out[#out + 1] = text:sub(i); break end
        out[#out + 1] = text:sub(i, s - 1)
        local c = text:sub(s, s)
        local level = text:match("^%[(=*)%[", c == "-" and s + 2 or s)
        if c == "-" and text:sub(s + 1, s + 1) ~= "-" or c == "[" and not level then
            out[#out + 1] = c
            i = s + 1
        elseif level then
            -- A long comment or long string, to its matching close.
            local _, e = text:find("]" .. level .. "]", s + 2, true)
            e = e or n
            out[#out + 1] = (c == "[" and '""' or "") .. blank(text:sub(s, e))
            i = e + 1
        elseif c == "-" then
            i = text:find("\n", s, true) or n + 1
        else
            local j, stop = s + 1, c == '"' and '[\\\n"]' or "[\\\n']"
            while true do
                local k = text:find(stop, j)
                if not k or text:sub(k, k) ~= "\\" then j = k or n + 1; break end
                j = k + 2
            end
            out[#out + 1] = c .. c .. blank(text:sub(s + 1, j - 1))
            i = j + 1
        end
    end
    return table.concat(out)
end

local KEYWORDS = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")
        :gmatch("%a+") do KEYWORDS[w] = true end

-- The line numbers in text where Lua 5.1 stops with "ambiguous syntax".
local function ambiguousLines(text)
    local found, prev, n = {}, nil, 0
    for line in (codeOnly((text:gsub("\r", ""))) .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if line:find("^%s*%(") and prev then
            local word = prev:match("([%a_][%w_]*)$")
            if (word and not KEYWORDS[word]) or (not word and prev:find("[%)%]}\"']$")) then
                found[#found + 1] = n
            end
        end
        local trimmed = line:match("^(.-)%s*$")
        if trimmed ~= "" then prev = trimmed end
    end
    return found
end

T.test("guards: the ambiguous-syntax check finds what Lua 5.1 refuses, and only that", function()
    T.deq(ambiguousLines("local a = b\n(c or d)()\n"), { 2 })
    T.deq(ambiguousLines("f(x)\n    (g)()\n"), { 2 })
    T.deq(ambiguousLines("local t = t[1]  -- a note\n\n(c)()\n"), { 3 })
    T.deq(ambiguousLines('local s = "a"\n(c)()\n'), { 2 })
    -- A line before that leaves the expression open is fine in 5.1 too.
    T.deq(ambiguousLines("local a = b or\n(c)\nlocal e = f,\n(g)\nif x then y() else\n(z)() end\n"), {})
    -- Strings and comments don't count, wherever they sit.
    T.deq(ambiguousLines('local s = "a (b"\nlocal t = [[x\n(y)]]\n--[[ c\n(d) ]]\nlocal u = "\\"" -- e\nreturn\n(u)\n'), {})
end)

T.test("guards: no shipped line starts with ( where Lua 5.1 reads it as a call", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close()
        for _, n in ipairs(ambiguousLines(text)) do
            bad[#bad + 1] = string.format("%s:%d  the game refuses this file (\"ambiguous syntax\"): end the line"
                .. " above with ; or start this one without (", path, n)
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- A bare pcall throws its error away, so nothing ever reaches BugSack and the
-- tests (which count reported errors) pass over a call that fails. A call that
-- does something goes through DUI.SafeCall, which reports and goes on. A bare
-- pcall is only for a read the client may refuse on purpose (a secret value, a
-- forbidden frame, a locked aura button). Each file may hold only as many as it
-- has in guards_allow.lua's pcalls list; that list only ever goes down.
local function barePcalls(path)
    local n = 0
    for line in io.lines(path) do
        for _ in (" " .. code(line)):gmatch("[^%w_%.:]pcall%(") do n = n + 1 end
    end
    return n
end

T.test("guards: no new bare pcall hides an error (use DUI.SafeCall)", function()
    local bad, budget = {}, ALLOW.pcalls or {}
    for _, path in ipairs(shippedFiles()) do
        local n, max = barePcalls(path), budget[path] or 0
        if n > max then
            bad[#bad + 1] = string.format("%s has %d bare pcall(s), %d allowed: use DUI.SafeCall for a call"
                .. " that does something; only a read the client may refuse on purpose stays a pcall", path, n, max)
        elseif n < max then
            bad[#bad + 1] = string.format('%s has %d bare pcall(s): lower its line in guards_allow.lua to ["%s"] = %d,',
                path, n, path, n)
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

-- A file the code names has to be one players get. The game draws nothing
-- for a missing image and reports nothing, so a file renamed or deleted while
-- the code kept its old name goes unseen. A name built round a changing part
-- ("objective-" .. kind .. ".png") needs at least one file that fits it.
local function mediaFiles()
    local set, list = {}, {}
    local p = io.popen('git ls-files -- Media')
    for line in p:lines() do
        local name = line:gsub("\r", ""):match("^Media/(.+)$")
        if name then
            set[name:lower()] = true
            list[#list + 1] = name:lower()
        end
    end
    p:close()
    return set, list
end

-- A name as a pattern: a format hole ("marker-%d.png") fits anything.
local function namePattern(s)
    s = s:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    return (s:gsub("%%%%?%d*[ds]", ".+"))
end

-- The file name in a quoted piece: up to its extension, dropping what an
-- inline image adds after it (":0|t").
local function fileIn(s)
    s = s:gsub("\\\\", "/"):lower()
    return s:match("^(.-%.%a%a%a)$") or s:match("^(.-%.%a%a%a)[:|]")
end

T.test("guards: every Media file named in the code is one players get", function()
    local set, list = mediaFiles()
    if #list == 0 then return end -- not a git checkout (a ZIP of the source): nothing to compare with
    local function fits(want)
        if set[want] then return true end
        local pattern = "^" .. namePattern(want) .. "$"
        for _, name in ipairs(list) do
            if name:find(pattern) then return true end
        end
        return false
    end
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local n = 0
        for line in io.lines(path) do
            n = n + 1
            local c = code(line)
            for first, rest in c:gmatch('%.MEDIA%s*%.%.%s*"([^"]*)"([^\n]*)') do
                local want = fileIn(first)
                if not want then
                    -- prefix .. something .. "suffix.ext"
                    local last = rest:match('^%s*%.%.[^"]-%.%.%s*"([^"]*)"')
                    last = last and fileIn(last)
                    if last then want = first:gsub("\\\\", "/"):lower() .. "%s" .. last end
                end
                if want and not fits(want) and not (ALLOW.media or {})[want] then
                    bad[#bad + 1] = string.format("%s:%d names Media/%s, which isn't in the repository", path, n, want)
                end
            end
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- An item tooltip drawn by a hover of ours goes through Parts.ItemTip (or a
-- kit list row's tooltip, which uses it). The game's tooltip asks its owner
-- again every 0.2 s, and its own buttons answer, so Shift pressed mid-hover
-- shows the compare. Hovers built by hand kept missing that.
local ITEM_SETTERS = { "Hyperlink", "BagItem", "InventoryItem", "LootRollItem", "LootItem", "MerchantItem",
    "BuybackItem", "QuestItem", "QuestLogItem", "QuestCurrency", "ItemByID", "ItemByGUID", "ItemKey",
    "SendMailItem", "InboxItem", "RecipeResultItem", "RecipeReagentItem", "TradeSkillItem", "AuctionItem" }

local function setsItem(c)
    for _, m in ipairs(ITEM_SETTERS) do
        if c:find("GameTooltip:Set" .. m .. "(", 1, true) then return true end
    end
    return c:find("SetTip(GameTooltip", 1, true) ~= nil
end

local function indentOf(l) return #(l:match("^%s*")) end

-- The names a function header gives its function, if any.
local function headerName(h)
    return h:match("local%s+function%s+([%w_]+)") or h:match("^%s*function%s+([%w_.:]+)%s*%(")
        or h:match("([%w_.]+)%s*=%s*[%w_.]*%(?%s*function") or h:match("local%s+([%w_]+)%s*=")
end

-- Routed: a header on the way out says so, or the function is handed to a
-- list row (tooltip = name) or wrapped by name.
local function routed(lines, n, text)
    local at = indentOf(lines[n])
    for i = n - 1, 1, -1 do
        local l = lines[i]
        if l:find("%f[%w_]function%f[^%w_]") and indentOf(l) < at then
            at = indentOf(l)
            if l:find("ItemTip(", 1, true) or l:find("tooltip%s*=") or l:find("onEnter%s*=") then return true end
            local name = headerName(l)
            if name then
                local short = name:match("([%w_]+)$")
                for _, pat in ipairs({ "tooltip%s*=%s*", "onEnter%s*=%s*", "ItemTip%(%s*" }) do
                    if text:find(pat .. name:gsub("%p", "%%%0") .. "%f[^%w_]")
                        or text:find(pat .. short .. "%f[^%w_.]") then return true end
                end
            end
            if at == 0 then return false end
        end
    end
    return false
end

T.test("guards: the item tooltip check tells a hand-built hover from a routed one", function()
    local function check(src)
        local lines = {}
        for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
        for n, l in ipairs(lines) do if setsItem(l) then return routed(lines, n, src) end end
    end
    T.falsy(check("b:SetScript(\"OnEnter\", function(self)\n    GameTooltip:SetHyperlink(self.link)\nend)"), "by hand")
    T.truthy(check("b:SetScript(\"OnEnter\", Parts.ItemTip(function(self)\n    GameTooltip:SetHyperlink(self.link)\nend))"),
        "wrapped")
    T.truthy(check("local function tip(b)\n    GameTooltip:SetItemByID(b.id)\nend\ns:Line({ tooltip = tip })"), "a list row's")
end)

T.test("guards: every item tooltip of a hover redraws for the Shift compare (Parts.ItemTip)", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local f = io.open(path, "rb")
        local raw = f:read("*a")
        f:close()
        local text = codeOnly((raw:gsub("\r", "")))
        local lines = {}
        for l in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
        for n, l in ipairs(lines) do
            if setsItem(l) and not routed(lines, n, text) and not ALLOW.itemTips[path] then
                bad[#bad + 1] = string.format("%s:%d an item tooltip outside Parts.ItemTip", path, n)
            end
        end
    end
    if #bad > 0 then error("\n  " .. table.concat(bad, "\n  "), 0) end
end)

-- A window of the kit closes on the game's Escape through a stand-in (Win.New).
-- One that follows a game window must leave that to the game: the game closes
-- its own window and this one follows, and a second close from the stand-in
-- would run the window's own close (a HideUIPanel from addon code) inside the
-- game's Escape.
T.test("guards: every window of the kit that follows a game window leaves Escape to it", function()
    local bad = {}
    for _, path in ipairs(shippedFiles()) do
        local f = io.open(path, "rb")
        local text = f:read("*a")
        f:close()
        local follows = not path:find("^Windows/") and (text:find("Win.Follow", 1, true) or text:find("Followers.", 1, true))
        if follows then
            for spec in text:gmatch("Win%.New(%b())") do
                if not spec:find("escape%s*=%s*false") then bad[#bad + 1] = path .. ": Win.New" .. spec end
            end
        end
    end
    T.eq(table.concat(bad, "\n"), "", "pass escape = false")
end)
