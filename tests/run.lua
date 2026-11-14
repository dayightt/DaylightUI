-- Headless test runner. From the repo root:
--   luajit tests/run.lua          run everything but the slow sweeps, one file at a time
--   luajit tests/run.lua style    run only test files whose name contains "style"
--   luajit tests/run.lua --par    every file at once in its own process, minus the slow sweeps
--   luajit tests/run.lua --par --all   the same with the sweeps, before a release
--   luajit tests/run.lua --par style   the files whose name contains "style", sweeps included
--   luajit tests/run.lua --par --only test_a test_b   exactly these files (tools/affected.py picks them)

-- One slot of --par. It takes test files until none are left, each in its own
-- process. A file is claimed by renaming its ticket, so only one worker can win it.
-- The dot printed after each file fails once the runner is gone, so a stopped run
-- doesn't carry on through the whole list unseen.
-- On Windows each file also holds one of a set of named mutexes, one per slot of
-- --par, shared by every run on the machine. That way several runs at once never
-- go past that many tests in flight (three runs of 14 each kept the CPU at 100%
-- with the game open). Waiting takes no CPU, and the system frees the mutex of a
-- process that dies. Elsewhere only the run's own workers limit it.
if arg and arg[1] == "--worker" then
    local base = arg[2]
    local takeSlot, freeSlot = function() end, function() end
    if package.config:sub(1, 1) == "\\" then
        local ffi = require("ffi")
        ffi.cdef[[
            void *CreateMutexA(void *attrs, int owned, const char *name);
            uint32_t WaitForMultipleObjects(uint32_t count, void *const *handles, int all, uint32_t ms);
            int ReleaseMutex(void *handle);
        ]]
        local count = math.max(2, math.floor((tonumber(os.getenv("NUMBER_OF_PROCESSORS") or "") or 4) / 4))
        local handles = ffi.new("void *[?]", count)
        for i = 1, count do handles[i - 1] = ffi.C.CreateMutexA(nil, 0, "Local\\DaylightUI_tests_" .. i) end
        local held
        takeSlot = function()
            local r = ffi.C.WaitForMultipleObjects(count, handles, 0, 0xFFFFFFFF)
            held = r < 0x100 and handles[r % 0x80] or nil   -- 0x80 and up means its last owner died
        end
        freeSlot = function()
            if held then ffi.C.ReleaseMutex(held) end
            held = nil
        end
    end
    for file in io.lines(base .. ".jobs") do
        local ticket = base .. "." .. file
        takeSlot()
        if os.rename(ticket, ticket .. ".run") then
            local h = io.popen("luajit tests/run.lua --one " .. file .. " 2>&1")
            local out = h:read("*a")
            h:close()
            freeSlot()
            local fh = assert(io.open(ticket .. ".out", "wb"))
            fh:write(out)
            fh:close()
            os.remove(ticket .. ".run")
            if not (io.write(".") and io.flush()) then break end
        else
            freeSlot()
        end
    end
    os.exit(0)
end

-- The collector runs later than its default of 200: 15% less CPU across the suite
-- (1000 gained no more), at the cost of some memory.
collectgarbage("setpause", 400)

package.path = "./?.lua;./tests/?.lua;" .. package.path
require("stub")

local T = {}
_G.T = T

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", msg or "eq", fmt(expected), fmt(actual)), 2)
    end
end
function T.near(actual, expected, tol, msg)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tol or 1e-6) then
        error(string.format("%s: expected ~%s, got %s", msg or "near", fmt(expected), fmt(actual)), 2)
    end
end
-- Compares two colors given as {r, g, b} tables, channel by channel.
function T.rgb(actual, expected, msg)
    for i, ch in ipairs({ "r", "g", "b" }) do
        T.near(actual[i], expected[i], 1e-6, (msg or "rgb") .. " " .. ch)
    end
end
function T.truthy(v, msg) if not v then error((msg or "truthy") .. ": got " .. fmt(v), 2) end end
function T.falsy(v, msg) if v then error((msg or "falsy") .. ": got " .. fmt(v), 2) end end
function T.isnil(v, msg) if v ~= nil then error((msg or "isnil") .. ": got " .. fmt(v), 2) end end
function T.errors(fn, msg) if pcall(fn) then error((msg or "errors") .. ": expected an error", 2) end end
function T.noerror(fn, msg)
    local ok, err = pcall(fn)
    if not ok then error(string.format("%s: unexpected error: %s", msg or "noerror", tostring(err)), 2) end
end

local function deepEq(a, b, path)
    if type(a) ~= type(b) then return false, path .. ": type " .. type(a) .. " vs " .. type(b) end
    if type(a) ~= "table" then
        if a ~= b then return false, path .. ": " .. fmt(a) .. " vs " .. fmt(b) end
        return true
    end
    for k, v in pairs(a) do
        local ok, why = deepEq(v, b[k], path .. "." .. tostring(k))
        if not ok then return false, why end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing in actual" end
    end
    return true
end
function T.deq(actual, expected, msg)
    local ok, why = deepEq(actual, expected, msg or "deq")
    if not ok then error(why, 2) end
end
function T.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local tests = {}
function T.test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

-- The dev tools (DaylightUI_Dev) and local notes aren't in the public repo.
-- Tests that need the dev tools register with T.devtest and are left out without them.
local function exists(p) local f = io.open(p, "r"); if f then f:close() end; return f ~= nil end
T.dev = exists("DaylightUI_Dev/DaylightUI_Dev.toc")
T.docs = exists("docs/cheatsheet.md")
function T.devtest(name, fn) if T.dev then T.test(name, fn) end end

local TEST_FILES = {
    "test_core", "test_db", "test_pixel", "test_motion", "test_feel", "test_pad", "test_windows", "test_controls_mogul", "test_sound", "test_style", "test_damagetext", "test_combattext", "test_tips", "test_gradients", "test_movers", "test_gamemovers", "test_options", "test_optionsui", "test_options_motion", "test_samplestrip", "test_gamemenu",
    "test_unitframes", "test_castbar", "test_castfade", "test_swing", "test_strata", "test_auras", "test_player_auras", "test_spots", "test_auragroups", "test_indicators", "test_bg_auras", "test_texts", "test_looks", "test_combo", "test_personal", "test_dots", "test_dots_frames", "test_happiness", "test_colors", "test_portraits", "test_arrive", "test_ribbon", "test_testmode", "test_pagesample", "test_testbox", "test_party", "test_party_pets", "test_party_targets", "test_party_casts", "test_arena", "test_raid", "test_leader", "test_clickcast", "test_ping", "test_group", "test_group_sweep", "test_privateauras", "test_blizzard", "test_units", "test_secrets", "test_actionbars", "test_bars", "test_padskin", "test_gamecode", "test_cdm", "test_cdm_import", "test_infopanel", "test_meters", "test_tracker", "test_datatexts",
    "test_buffs_categories", "test_buffs_data", "test_buffs_classify", "test_buffs_spells", "test_buffs_layout", "test_buffs", "test_buffs_reminder", "test_tooltip", "test_qol", "test_afk", "test_flight", "test_lootfeed", "test_levelup", "test_zonetitle", "test_repbanner", "test_campfire", "test_nameplates", "test_nameplate_sample", "test_nameplate_more", "test_platefix", "test_skins", "test_addonskins", "test_chat", "test_profiles", "test_plugins", "test_api", "test_api_frames", "test_api_promise", "test_api_windows", "test_api_paint", "test_api_castbar", "test_api_unitparts", "test_api_plates", "test_api_bars", "test_api_info", "test_api_more", "test_api_hooks", "test_api_texts", "test_api_quests", "test_api_defaults", "test_installer", "test_tour", "test_patchnotes", "test_fade", "test_media", "test_bags", "test_guards", "test_locked", "test_hostile_bg", "test_hostile_fight", "test_hostile_party", "test_hostile_testmode", "test_quests", "test_quest_progress", "test_questnav", "test_questie_bridge", "test_towns", "test_givertips", "test_journal", "test_character", "test_character_pet", "test_inspect", "test_craft", "test_lfg", "test_mailworld", "test_mail_ledger", "test_mail", "test_mail_ledger_mogul", "test_social", "test_legacy", "test_npc", "test_npc_trainer", "test_npc_popups", "test_book", "test_book_talents", "test_book_spend", "test_book_spells", "test_book_training", "test_book_fight", "test_ptrbutton", "test_bugreport",
    "test_stub_reuse", "test_mogul_contract", "test_lag", "test_locale", "test_dev", "test_hygiene",
}
if T.docs then TEST_FILES[#TEST_FILES + 1] = "test_docs" end

-- Slow files: every-combination sweeps (group frames; every setting and event
-- in a battleground, a fight, a keystone, test mode), over half the suite's
-- time. Skipped by a plain run and by --par; included by --all, or when named.
local SLOW = { test_group = true, test_group_sweep = true, test_hostile_bg = true, test_hostile_fight = true,
               test_hostile_party = true, test_hostile_testmode = true }

local filter, all, par, one, only
for _, a in ipairs(arg or {}) do
    if a == "--all" then all = true
    elseif a == "--par" then par = true
    elseif a == "--one" then one = true
    elseif a == "--only" then only = {}
    elseif only then only[a] = true
    else filter = a end
end

local function onDisk(file)
    local fh = io.open("tests/" .. file .. ".lua")
    if fh then fh:close() end
    return fh ~= nil
end

local function wanted(file)
    if not onDisk(file) then return false end
    if one then return file == filter end
    if only then return only[file] == true end
    if filter then return string.find(file, filter, 1, true) ~= nil end
    return all or not SLOW[file]
end

-- Parallel: one child process per file, each run with --one, one slot per four
-- logical cores, at low priority on Windows. All ~70 at once froze the PC and the
-- game, and one per physical core still swamped it, since low priority doesn't
-- shield memory (up to 2.7 GB a file). Each slot takes the next file when it's
-- free; starting them in list order instead left every other slot idle behind one
-- slow file. Results print in list order.
if par then
    local jobs, skippedSlow = {}, {}
    for _, file in ipairs(TEST_FILES) do
        if wanted(file) then
            jobs[#jobs + 1] = { file = file }
        elseif SLOW[file] and not filter and not only and onDisk(file) then
            skippedSlow[#skippedSlow + 1] = file
        end
    end
    local windows = package.config:sub(1, 1) == "\\"
    local cores = tonumber(os.getenv("NUMBER_OF_PROCESSORS") or "") or 4
    local pool = math.max(2, math.floor(cores / 4))
    -- Names unique to this run, since other runs may happen at the same time.
    local base = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/dui_par_" .. os.time()
        .. "_" .. string.match(tostring({}), "%x+$")
    local function put(path, text)
        local fh = assert(io.open(path, "wb"))
        fh:write(text)
        fh:close()
    end
    local names = {}
    for i, job in ipairs(jobs) do
        names[i] = job.file
        put(base .. "." .. job.file, "")
    end
    put(base .. ".jobs", table.concat(names, "\n") .. "\n")
    local workers = {}
    for i = 1, math.min(pool, #jobs) do
        local cmd = 'luajit tests/run.lua --worker "' .. base .. '" 2>&1'
        if windows then cmd = 'start "" /b /low /wait ' .. cmd end
        workers[i] = io.popen(cmd)
    end
    for _, h in ipairs(workers) do
        h:read("*a")
        h:close()
    end
    os.remove(base .. ".jobs")
    local passed, failed, failures = 0, 0, {}
    for _, job in ipairs(jobs) do
        local fh = io.open(base .. "." .. job.file .. ".out", "rb")
        local out = fh and fh:read("*a") or ""
        if fh then fh:close() end
        os.remove(base .. "." .. job.file .. ".out")
        local p, f = string.match(out, "(%d+) passed, (%d+) failed")
        if not p then
            failed = failed + 1
            failures[#failures + 1] = job.file .. ": no result\n" .. out
        else
            passed, failed = passed + tonumber(p), failed + tonumber(f)
            -- Only failing files are named. A line per file was ~70 lines of noise.
            if tonumber(f) > 0 then
                io.write(string.format("FAIL %s (%d of %d)\n", job.file, tonumber(f), tonumber(p) + tonumber(f)))
                failures[#failures + 1] = out
            end
        end
    end
    io.write(string.format("%d passed, %d failed (%d files, in parallel)\n", passed, failed, #jobs))
    if #skippedSlow > 0 then io.write("(the ", #skippedSlow, " slow sweeps skipped: --par --all runs them)\n") end
    for _, f in ipairs(failures) do io.write("\n--- ", f, "\n") end
    os.exit(failed == 0 and 0 or 1)
end

-- One process runs every file here, so each file starts from the globals the first
-- one saw. Test files swap in their own GameTooltip, EventRegistry, C_* tables...,
-- and a later file would meet them (the game's ActionButton.lua then failed on a
-- GameTooltip with no GetOwner). --par needs none of this.
local baseline = {}
for k, v in pairs(_G) do baseline[k] = v end
local function restoreGlobals()
    for k in pairs(_G) do
        if baseline[k] == nil then _G[k] = nil end
    end
    for k, v in pairs(baseline) do
        if rawget(_G, k) ~= v then _G[k] = v end
    end
end

local passed, failed, failures = 0, 0, {}
local skipped = {}
for _, file in ipairs(TEST_FILES) do
    if wanted(file) then
        restoreGlobals()
        tests = {}
        local path = "tests/" .. file .. ".lua"
        local chunk, err = loadfile(path)
        if not chunk then
            failed = failed + 1
            failures[#failures + 1] = path .. ": " .. err
        else
            chunk()
            for _, t in ipairs(tests) do
                local ok, terr = xpcall(t.fn, debug.traceback)
                if ok then
                    passed = passed + 1
                else
                    failed = failed + 1
                    failures[#failures + 1] = file .. " / " .. t.name .. "\n" .. tostring(terr)
                    io.write("FAIL ", file, " / ", t.name, "\n")
                end
            end
            io.write(string.format("%-18s %d tests\n", file, #tests))
        end
    elseif SLOW[file] and not filter and not only and onDisk(file) then
        skipped[#skipped + 1] = file
    end
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if #skipped > 0 then io.write("skipped slow: ", table.concat(skipped, ", "), " (run with --par --all)\n") end
for _, f in ipairs(failures) do io.write("\n--- ", f, "\n") end
os.exit(failed == 0 and 0 or 1)
