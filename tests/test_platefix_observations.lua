local stub = require("stub")

local SHOW = { "nameplateShowEnemies", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNpcs" }

-- Native plates follow the enemy switch; ownership follows Manager's processing.
-- A count proves existence, not that the client painted the plate.
local function login(moduleOn, enabled)
    local values, np = {}, nil
    for _, name in ipairs(SHOW) do values[name] = enabled and "1" or "0" end
    local DUI = stub.Load({ nameplates = moduleOn, before = function()
        _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
            if unit ~= "nameplate1" or values[SHOW[1]] ~= "1" then return nil end
            if not np then
                np = CreateFrame("Frame", nil, UIParent)
                np.UnitFrame = CreateFrame("Button", nil, np)
                function np:SetStackingBoundsFrame() end
            end
            return np
        end }
        C_NamePlate.GetNamePlates = function()
            local p = C_NamePlate.GetNamePlateForUnit("nameplate1")
            return p and { p } or {}
        end
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
    -- Ten fresh-pool batches, then switch restoration and reattachment.
    for _ = 1, 4 do stub.RunTimers() end
end

local function boxText()
    local box = _G.DaylightUIProfileBox
    return box and box:IsShown() and box.edit:GetText() or nil
end

local function resetStep(DUI, M)
    if M then M.Fix(); M.Fix() end
    return (M or DUI.PlateReport).Fix()
end

local function report(DUI, M)
    return (M or DUI.PlateReport).FixReport()
end

T.test("platefix observations: all-off resets stay off, and yes records later changes", function()
    for _, moduleOn in ipairs({ true, false }) do
        local DUI, M, values = login(moduleOn, false)
        if M then for _ = 1, 5 do M.Fix(); drain() end
        else DUI.PlateReport.Fix(); drain() end
        for _, name in ipairs(SHOW) do T.eq(values[name], "0", "disabled categories stay off") end
        local text = report(DUI, M)
        T.truthy(text:find("all three show switches were off", 1, true), text)
        T.falsy(text:find("plates rebuilt", 1, true), "zero-to-zero is not a rebuild")
        T.truthy(text:find("E0 FP0 FN0 G0", 1, true), text)
        values[SHOW[1]] = "1" -- after completion, before the player's answer
        if M then stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1") end
        DUI.RunCommand("platefix yes")
        text = boxText()
        T.truthy(text:find("player reported recovery after step " .. (M and 5 or 1), 1, true), text)
        T.truthy(text:find("At yes: E1 FP0 FN0 G1" .. (M and " O1" or ""), 1, true), text)
        T.truthy(text:find("E0 FP0 FN0 G0", 1, true), "earlier observations stay frozen")
        if not M then T.falsy(text:match("G%d O%d"), "no invented ownership count with module off") end
    end
end)

T.test("platefix observations: a reset still blocks advance and yes after five seconds", function()
    for _, moduleOn in ipairs({ true, false }) do
        local DUI, M = login(moduleOn, true)
        local R = DUI.PlateReport
        resetStep(DUI, M)
        T.truthy(R.FixBusy())
        T.truthy(report(DUI, M):find("pending", 1, true), "unfinished result is labeled pending")
        stub.Advance(6) -- do not execute its queued completion
        T.truthy(R.FixBusy(), "elapsed time cannot complete an intervention")
        local said = (M or R).Fix()
        T.truthy(said:find("still finishing", 1, true), said)
        DUI.RunCommand("platefix yes")
        T.isnil(boxText(), "yes also waits past five seconds")
        drain()
        T.falsy(R.FixBusy())
        T.truthy(report(DUI, M):find("=> E1 FP1 FN1 G1" .. (M and " O1" or ""), 1, true))
        if M then T.eq(M.fixRun.trace[3].after.ours, 1, "after follows reattachment") end
    end
end)

T.test("platefix observations: step seven waits for actual pool completion and reattachment", function()
    local DUI, M = login(true, true)
    for _ = 1, 6 do M.Fix(); drain() end
    local finishPool, oldPool = nil, M.FreshPool
    M.FreshPool = function(done) finishPool = done end
    M.Fix()
    stub.Advance(6)
    drain()
    T.truthy(DUI.PlateReport.FixBusy(), "an unfinished pool has no completion timeout")
    T.isnil(M.fixRun.trace[7].after)
    T.eq(M.fixStep, 7)
    finishPool()
    drain()
    M.FreshPool = oldPool
    T.falsy(DUI.PlateReport.FixBusy())
    T.eq(M.fixRun.trace[7].after.game, 1)
    T.eq(M.fixRun.trace[7].after.ours, 1)
end)

T.test("platefix observations: unknown and secret reads stay unknown and are never written back", function()
    for _, moduleOn in ipairs({ true, false }) do
        local DUI, M = login(moduleOn, false)
        if M then M.Fix(); M.Fix() end
        -- The fake client normally wraps secrets in tables. Tag a string here too,
        -- so the CVar guard cannot rely on type(string) implying a plain value.
        local isSecret = DUI.IsSecret
        DUI.IsSecret = function(v) return (type(v) == "string" and v == "1") or isSecret(v) end
        _G.GetCVar = function(name)
            if name == SHOW[1] then return "1" end
            if name == SHOW[2] then error("unavailable") end
            return "0"
        end
        C_NamePlate.GetNamePlates = function() return stub.Secret({}) end
        local writes = {}
        _G.SetCVar = function(name, value) writes[#writes + 1] = { name, value } end
        local s
        T.noerror(function() s = DUI.PlateReport.Snapshot() end)
        T.deq({ s[1], s[2], s[3], s.game }, { "?", "?", "0", "?" })
        C_NamePlate.GetNamePlates = function() error("restricted") end
        T.eq(DUI.PlateReport.Snapshot().game, "?", "getter failures are not zero plates")
        C_NamePlate.GetNamePlates = nil
        T.eq(DUI.PlateReport.Snapshot().game, "?", "missing API is not zero plates")
        local runner = M or DUI.PlateReport
        runner.Fix()
        drain()
        DUI.IsSecret = isSecret
        for _, write in ipairs(writes) do
            T.eq(write[1], SHOW[3], "unknown and secret categories are never mutated")
            T.eq(write[2], "0")
        end
        T.truthy(#writes > 0, "the known category still participates")
    end
end)

T.test("platefix observations: completed trace survives noisy log and report truncation", function()
    local DUI, M = login(true, true)
    for i = 1, 40 do stub.FireEvent("CVAR_UPDATE", "someLongSettingName" .. i, "1") end
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.GetNumAddOns = function() return 40 end
    _G.C_AddOns.GetAddOnInfo = function(i) return "SomeLongAddonNameForTheReport" .. i end
    _G.C_AddOns.IsAddOnLoaded = function() return true end
    for _ = 1, M.FIX_STEPS do M.Fix(); drain() end
    local expected = DUI.PlateReport.TraceLines(M.fixRun)
    DUI.RunCommand("platefix yes")
    local text = boxText()
    T.truthy(#text <= M.REPORT_MAX, #text)
    for _, line in ipairs(expected) do T.truthy(text:find(line, 1, true), "retained: " .. line) end
    T.truthy(text:find("At yes: E1 FP1 FN1 G1 O1", 1, true), text)
end)

T.test("platefix observations: combat before restoration delays mutation and completion", function()
    for _, moduleOn in ipairs({ true, false }) do
        local DUI, M, values = login(moduleOn, true)
        resetStep(DUI, M)
        _G.SetCVar = function(name, value)
            assert(not InCombatLockdown(), "restore attempted in combat")
            values[name] = value
        end
        stub.EnterCombat()
        drain()
        stub.Advance(6)
        T.truthy(DUI.PlateReport.FixBusy(), "waiting for combat remains pending")
        T.eq(values[SHOW[1]], "0")
        if M then T.isnil(M.fixRun.trace[3].after) end
        stub.LeaveCombat()
        drain()
        T.falsy(DUI.PlateReport.FixBusy())
        T.eq(values[SHOW[1]], "1")
        T.truthy(report(DUI, M):find("E1 FP1 FN1 G1", 1, true))
        if M then T.eq(M.fixRun.trace[3].after.ours, 1) end
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

T.test("platefix observations: combat between fresh-pool batches pauses building and completion", function()
    local DUI, M = login(true, true)
    for _ = 1, 6 do M.Fix(); drain() end
    local oldPrepare, built, batches = M.Prepare, 0, 0
    M.Prepare = function(n)
        assert(not InCombatLockdown(), "fresh plate batch attempted in combat")
        built, batches = built + n, batches + 1
        return oldPrepare(n)
    end
    M.Fix()
    T.eq(built, M.FRESH_PER_FRAME)
    stub.EnterCombat()
    drain()
    T.eq(built, M.FRESH_PER_FRAME, "later batches wait for combat to end")
    T.truthy(DUI.PlateReport.FixBusy())
    T.isnil(M.fixRun.trace[7].after)
    T.eq(M.Spares(), M.FRESH_PER_FRAME, "no attachment from an unfinished pool")
    stub.LeaveCombat()
    drain()
    M.Prepare = oldPrepare
    T.eq(built, M.PREPARE)
    T.eq(batches, math.ceil(M.PREPARE / M.FRESH_PER_FRAME))
    T.falsy(DUI.PlateReport.FixBusy())
    T.falsy(M.fixRun.trace[7].failed)
    T.eq(M.fixRun.trace[7].after.ours, 1, "completion follows reattachment")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("platefix observations: first or later pool failure releases busy and preserves failure evidence", function()
    for _, failAt in ipairs({ 1, 2 }) do
        local DUI, M = login(true, true)
        for _ = 1, 6 do M.Fix(); drain() end
        local oldPrepare, calls = M.Prepare, 0
        M.Prepare = function(n)
            calls = calls + 1
            if calls == failAt then error("pool batch refused") end
            return oldPrepare(n)
        end
        M.Fix()
        T.noerror(drain)
        M.Prepare = oldPrepare
        T.falsy(DUI.PlateReport.FixBusy(), "a failed callback cannot hold the run forever")
        T.truthy(M.fixRun.trace[7].failed)
        T.truthy(M.fixRun.trace[7].after, "state at failure is retained")
        local text = M.FixReport()
        T.truthy(text:find("pool batch refused", 1, true), text)
        T.truthy(text:find("failed", 1, true), text)
    end
end)

T.test("platefix observations: restore failure releases busy and preserves actual switches", function()
    for _, moduleOn in ipairs({ true, false }) do
        for _, throws in ipairs({ true, false }) do
            local DUI, M, values = login(moduleOn, true)
            resetStep(DUI, M)
            _G.SetCVar = function(name, value)
                if name == SHOW[1] and value == "1" then
                    if throws then error("enemy restore refused") end
                    return false
                end
                values[name] = value -- nil is the successful legacy return
            end
            T.noerror(drain)
            T.falsy(DUI.PlateReport.FixBusy())
            T.eq(values[SHOW[1]], "0")
            T.eq(values[SHOW[2]], "1", "one refusal does not skip another known restoration")
            T.eq(values[SHOW[3]], "1")
            local text = report(DUI, M)
            T.truthy(text:find(throws and "enemy restore refused" or SHOW[1], 1, true), text)
            T.truthy(text:find("failed", 1, true), "false must be recorded as failure: " .. text)
            T.truthy(text:find("=> E0 FP1 FN1 G0", 1, true), text)
        end
    end
end)

T.test("platefix observations: stale queued timers cannot mutate a later run", function()
    for _, moduleOn in ipairs({ true, false }) do
        local DUI, M, values = login(moduleOn, true)
        if M then M.Fix(); M.Fix() end
        local R, queue, after = DUI.PlateReport, {}, C_Timer.After
        local runner = M or R
        local n = M and 3 or 1
        local action, complete = runner.FIX[n], nil
        runner.FIX[n] = function(done, current)
            complete = done
            return action(done, current)
        end
        C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
        runner.Fix()
        C_Timer.After = after
        runner.FIX[n] = action
        local oldRun = M and M.fixRun
        -- A failure can finish a step while its earlier timer is still queued.
        -- Close and restart normally, then deliver that abandoned callback.
        complete("intervention interrupted")
        local oldAfter = oldRun and oldRun.trace[3].after
        DUI.RunCommand("platefix yes")
        T.truthy(boxText(), "the failed round was closed before restarting")
        if _G.DaylightUIProfileBox then DaylightUIProfileBox:Hide() end
        local restarted = runner.Fix()
        T.truthy(restarted:find("platefix 1/", 1, true), "a new round starts at step one: " .. restarted)
        drain()
        local nextReport = report(DUI, M)
        T.falsy(nextReport:find("intervention interrupted", 1, true), "the new round does not retain old evidence")
        values[SHOW[1]], values[SHOW[2]], values[SHOW[3]] = "0", "1", "0"
        local writes, set = 0, SetCVar
        _G.SetCVar = function(name, value) writes = writes + 1; return set(name, value) end
        for _, fn in ipairs(queue) do fn() end
        drain()
        _G.SetCVar = set
        T.eq(writes, 0, "old callbacks never restore switches in the new run")
        T.deq({ values[SHOW[1]], values[SHOW[2]], values[SHOW[3]] }, { "0", "1", "0" })
        T.eq(report(DUI, M), nextReport, "the later run's evidence stays unchanged")
        if M then T.eq(oldRun.trace[3].after, oldAfter, "the failure snapshot stays frozen") end
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

T.test("platefix observations: a stale restore already queued for combat cannot mutate a later run", function()
    local DUI, M, values = login(true, true)
    M.Fix(); M.Fix(); drain()
    local timers, after = {}, C_Timer.After
    C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
    M.Fix()
    C_Timer.After = after
    T.eq(#timers, 1)
    local oldRun = M.fixRun
    stub.EnterCombat()
    timers[1]()
    T.truthy(DUI.PlateReport.FixBusy())
    T.isnil(oldRun.trace[3].after)
    DUI.PlateReport.FixClear()
    local replacement = { did = { "replacement" }, before = {}, trace = {} }
    M.fixRun = replacement
    values[SHOW[1]], values[SHOW[2]], values[SHOW[3]] = "0", "1", "0"
    local writes, set = 0, SetCVar
    _G.SetCVar = function(name, value) writes = writes + 1; return set(name, value) end
    stub.LeaveCombat()
    drain()
    _G.SetCVar = set
    T.eq(writes, 0, "the callback checks identity again after leaving the combat queue")
    T.deq({ values[SHOW[1]], values[SHOW[2]], values[SHOW[3]] }, { "0", "1", "0" })
    T.deq(replacement, { did = { "replacement" }, before = {}, trace = {} })
    T.isnil(oldRun.trace[3].after)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
