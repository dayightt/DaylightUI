local stub = require("stub")

local SHOW = { "nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs" }

-- Engine plates follow the enemy switch; Daylight-owned plates follow its
-- add/remove processing. Neither count is a proxy for the other's state.
local function login(moduleOn, enabled)
    local values, np = {}, nil
    for _, name in ipairs(SHOW) do values[name] = enabled and "1" or "0" end
    local DUI = stub.Load({ nameplates = moduleOn, before = function()
        _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
            if unit ~= "nameplate1" or values.nameplateShowEnemies ~= "1" then return nil end
            if not np then
                np = CreateFrame("Frame", nil, UIParent)
                np.UnitFrame = CreateFrame("Button", nil, np)
                function np:SetStackingBoundsFrame() end
            end
            return np
        end }
        _G.issecure = function() return false end
        _G.IsInInstance = function() return false end
        _G.UnitCanAttack = function(_, unit) return unit == "nameplate1" end
        stub.units = {
            player = { name = "Me", class = "PRIEST", isPlayer = true },
            nameplate1 = { name = "Whelp", hostile = true, reaction = 2, health = 50, maxHealth = 100, pct = 50 },
        }
    end })
    stub.RunTimers()
    _G.GetCVar = function(name) return values[name] end
    _G.SetCVar = function(name, value) values[name] = value end
    _G.C_CVar = _G.C_CVar or {}
    C_CVar.GetCVarDefault = function(name) return "default:" .. name end
    if moduleOn and enabled then stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1") end
    stub.RunTimers()
    return DUI, moduleOn and stub.nameplates.Manager or nil, values
end

local function drain()
    -- The pool is deliberately built over ten callbacks, followed by its reset.
    for _ = 1, 4 do stub.RunTimers() end
end

local function boxText()
    local box = _G.DaylightUIProfileBox
    return box and box:IsShown() and box.edit:GetText() or nil
end

T.test("platefix observations: all-off switches stay off and are not described as rebuilt", function()
    local DUI, M, values = login(true, false)
    local said
    for _ = 1, 5 do said = M.Fix(); drain() end
    for _, name in ipairs(SHOW) do T.eq(values[name], "0", "never force a disabled category on") end
    T.truthy(said:find("off", 1, true), said)
    T.falsy(said:find("plates rebuilt", 1, true), "cannot claim a zero-to-zero rebuild")
    for i = 1, 5 do
        local row = M.fixRun.trace[i]
        T.truthy(row.before:find("E=0 FP=0 FN=0 G=0 O=0", 1, true), row.before)
        T.truthy(row.after:find("E=0 FP=0 FN=0 G=0 O=0", 1, true), row.after)
    end
    values.nameplateShowEnemies = "1" -- a change between completion and the player's answer
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    DUI.RunCommand("platefix yes")
    local text = boxText()
    T.truthy(text:find("player reported recovery after step 5", 1, true), text)
    T.truthy(text:match("At yes:[^\n]*E=1 FP=0 FN=0 G=1 O=1"), text)
    T.truthy(text:find("E=0 FP=0 FN=0 G=0 O=0", 1, true), "earlier observations stay frozen")
end)

T.test("platefix observations: advance and yes cannot overlap a pending reset", function()
    local DUI, M = login(true, true)
    M.Fix(); M.Fix()
    local queue, originalAfter = {}, C_Timer.After
    C_Timer.After = function(delay, fn) queue[#queue + 1] = { delay, fn } end
    M.Fix()
    T.eq(M.fixRun.pending, 3)
    T.isnil(M.fixRun.trace[3].after, "no result at scheduling time")
    local said = M.Fix()
    T.eq(M.fixStep, 3, said)
    DUI.RunCommand("platefix yes")
    T.isnil(boxText(), "yes waits too")
    local count = 0
    while #queue > 0 do
        local nextCall = table.remove(queue, 1)
        stub.Advance(nextCall[1])
        nextCall[2]()
        count = count + 1
        assert(count < 100, "timer chain did not finish")
    end
    C_Timer.After = originalAfter
    T.falsy(M.fixRun.pending)
    T.truthy(M.fixRun.trace[3].after:find("E=1 FP=1 FN=1 G=1 O=1", 1, true))
    M.Fix()
    T.eq(M.fixStep, 4)
end)

T.test("platefix observations: step seven waits for pool completion and reattachment", function()
    local _, M = login(true, true)
    for _ = 1, 6 do M.Fix(); drain() end
    local finishPool, oldPool = nil, M.FreshPool
    M.FreshPool = function(done) finishPool = done end
    M.Fix()
    drain()
    T.eq(M.fixRun.pending, 7, "no fixed timeout can complete an unfinished pool")
    T.isnil(M.fixRun.trace[7].after)
    finishPool()
    drain()
    M.FreshPool = oldPool
    T.falsy(M.fixRun.pending)
    T.truthy(M.fixRun.trace[7].after:find("G=1 O=1", 1, true))
end)

T.test("platefix observations: fallback records completed state and at-yes state", function()
    local DUI, _, values = login(false, false)
    DUI.RunCommand("platefix")
    DUI.RunCommand("platefix yes")
    T.isnil(boxText(), "fallback reset is pending")
    drain()
    values.nameplateShowEnemies = "1"
    DUI.RunCommand("platefix yes")
    local text = boxText()
    T.truthy(text:find("E=0 FP=0 FN=0 G=0", 1, true), text)
    T.truthy(text:match("At yes:[^\n]*E=1 FP=0 FN=0 G=1"), text)
    T.falsy(text:find(" O=", 1, true), "no invented ownership count with module off")
end)

T.test("platefix observations: unavailable or secret reads never become zero", function()
    local DUI = login(false, false)
    local secret = stub.Secret("0")
    _G.GetCVar = function(name)
        if name == SHOW[1] then return secret end
        if name == SHOW[2] then error("unavailable") end
        return "0"
    end
    C_NamePlate.GetNamePlateForUnit = function() error("restricted") end
    local snapshot
    T.noerror(function() snapshot = DUI.PlateReport.StepSnapshot() end)
    T.truthy(snapshot:find("E=? FP=? FN=0 G=?", 1, true), snapshot)
end)

T.test("platefix observations: completed trace survives noisy log and long report", function()
    local DUI, M = login(true, true)
    local R = DUI.PlateReport
    for i = 1, 40 do stub.FireEvent("CVAR_UPDATE", "someLongSettingName" .. i, "1") end
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.GetNumAddOns = function() return 40 end
    _G.C_AddOns.GetAddOnInfo = function(i) return "SomeLongAddonNameForTheReport" .. i end
    _G.C_AddOns.IsAddOnLoaded = function() return true end
    for _ = 1, M.FIX_STEPS do M.Fix(); drain() end
    local expected = R.TraceLines(M.fixRun)
    DUI.RunCommand("platefix yes")
    local text = boxText()
    T.truthy(#text <= M.REPORT_MAX, #text)
    for _, line in ipairs(expected) do T.truthy(text:find(line, 1, true), "retained: " .. line) end
    T.truthy(text:find("At yes:", 1, true), text)
    T.truthy(text:find("E=1 FP=1 FN=1 G=1 O=1", 1, true), text)
end)

T.test("platefix observations: combat during a reset defers restoration and completion", function()
    local _, M, values = login(true, true)
    M.Fix(); M.Fix(); M.Fix()
    _G.SetCVar = function(name, value)
        assert(not InCombatLockdown(), "restore attempted in combat")
        values[name] = value
    end
    stub.EnterCombat()
    drain()
    T.eq(M.fixRun.pending, 3)
    T.isnil(M.fixRun.trace[3].after)
    T.eq(values.nameplateShowEnemies, "0")
    stub.LeaveCombat()
    drain()
    T.falsy(M.fixRun.pending)
    T.eq(values.nameplateShowEnemies, "1")
    T.truthy(M.fixRun.trace[3].after:find("G=1 O=1", 1, true))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("platefix observations: combat between fresh-pool batches pauses building and completion", function()
    local _, M = login(true, true)
    for _ = 1, 6 do M.Fix(); drain() end
    local oldPrepare, built, batches = M.Prepare, 0, 0
    M.Prepare = function(n)
        assert(not InCombatLockdown(), "fresh plate batch attempted in combat")
        built, batches = built + n, batches + 1
        return oldPrepare(n)
    end
    M.Fix()
    T.eq(built, M.FRESH_PER_FRAME, "the first batch is built before combat")
    T.eq(batches, 1)
    stub.EnterCombat()
    drain()
    T.eq(built, M.FRESH_PER_FRAME, "later batches wait in the combat queue")
    T.eq(M.fixRun.pending, 7)
    T.isnil(M.fixRun.trace[7].after, "the partial pool is not a completed step")
    T.eq(M.Spares(), M.FRESH_PER_FRAME, "nothing attaches the unfinished pool")
    stub.LeaveCombat()
    drain()
    M.Prepare = oldPrepare
    T.eq(built, M.PREPARE, "every remaining plate is built after combat")
    T.eq(batches, math.ceil(M.PREPARE / M.FRESH_PER_FRAME))
    T.falsy(M.fixRun.pending)
    T.eq(M.fixRun.trace[7].failed, false)
    T.truthy(M.fixRun.trace[7].after:find("G=1 O=1", 1, true), "completion follows reattachment")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("platefix observations: an asynchronous pool error finishes with failure evidence", function()
    local _, M = login(true, true)
    for _ = 1, 6 do M.Fix(); drain() end
    local oldPrepare, calls = M.Prepare, 0
    M.Prepare = function(n)
        calls = calls + 1
        if calls == 2 then error("pool batch refused") end
        return oldPrepare(n)
    end
    M.Fix()
    drain()
    M.Prepare = oldPrepare
    T.falsy(M.fixRun.pending, "failed timer cannot leave the diagnostic permanently busy")
    T.truthy(M.fixRun.trace[7].after, "state at failure retained")
    local report = M.FixReport()
    T.truthy(report:find("pool batch refused", 1, true), report)
end)

T.test("platefix observations: stale callbacks cannot alter a replacement run", function()
    local _, M, values = login(true, true)
    M.Fix(); M.Fix()
    local queue, originalAfter = {}, C_Timer.After
    C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
    M.Fix()
    local oldRun = M.fixRun
    M.fixRun = { did = {}, before = {}, trace = {} }
    values.nameplateShowEnemies = "0"
    local steps = 0
    while #queue > 0 do
        table.remove(queue, 1)()
        steps = steps + 1
        assert(steps < 100, "stale callbacks did not stop")
    end
    C_Timer.After = originalAfter
    T.eq(values.nameplateShowEnemies, "0", "old restore is discarded")
    T.eq(next(M.fixRun.trace), nil, "replacement run untouched")
    T.isnil(oldRun.trace[3].after, "stale result not invented")
end)

T.test("platefix observations: a stale restore already in the combat queue cannot alter a replacement run", function()
    local DUI, M, values = login(true, true)
    M.Fix(); M.Fix(); drain()
    local timers, oldAfter = {}, C_Timer.After
    C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
    M.Fix()
    C_Timer.After = oldAfter
    T.eq(#timers, 1, "the reset has scheduled its restore")
    local oldRun = M.fixRun
    stub.EnterCombat()
    local queued, oldAfterCombat = 0, DUI.AfterCombat
    DUI.AfterCombat = function(fn, key)
        if InCombatLockdown() then queued = queued + 1 end
        return oldAfterCombat(fn, key)
    end
    timers[1]() -- it is still current when the timer enters the combat queue
    DUI.AfterCombat = oldAfterCombat
    T.eq(queued, 1, "the old restore is now waiting inside AfterCombat")
    T.eq(oldRun.pending, 3)
    T.isnil(oldRun.trace[3].after)
    local replacement = { did = { "replacement" }, before = {}, trace = {}, pending = 3 }
    M.fixRun = replacement
    values.nameplateShowEnemies, values.nameplateShowFriendlyPlayers, values.nameplateShowFriendlyNpcs = "0", "1", "0"
    local writes, oldSet = 0, SetCVar
    _G.SetCVar = function(name, value)
        for _, show in ipairs(SHOW) do if name == show then writes = writes + 1 end end
        return oldSet(name, value)
    end
    stub.LeaveCombat()
    drain()
    _G.SetCVar = oldSet
    T.eq(writes, 0, "the queued stale restore never writes the show switches")
    T.eq(values.nameplateShowEnemies, "0")
    T.eq(values.nameplateShowFriendlyPlayers, "1")
    T.eq(values.nameplateShowFriendlyNpcs, "0")
    T.eq(M.fixRun, replacement)
    T.deq(replacement, { did = { "replacement" }, before = {}, trace = {}, pending = 3 }, "replacement run untouched")
    T.isnil(oldRun.trace[3].after, "no completion is invented for the abandoned run")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
