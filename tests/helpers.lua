-- Test helpers not tied to one part of the addon.
local M = {}

local GARBAGE_ROUNDS = 3

-- The kilobytes of garbage left by calling work the given number of times, in
-- steady state: the smallest growth of several rounds with the collector stopped.
-- The game has no JIT, so code compiled by earlier tests is flushed too: it still
-- runs after jit.off(), and its exits can allocate at moments that vary run to run.
-- A one-off (the Lua stack regrowing after the collect shrank it) lands in one
-- round only; an allocation in every call lands in every round. The collector
-- restarts even on error: later test files share the process.
function M.garbageMadeBy(work, calls)
    local function smallestRoundGrowth()
        local smallest = math.huge
        for _ = 1, GARBAGE_ROUNDS do
            local before = collectgarbage("count")
            for _ = 1, calls do work() end
            smallest = math.min(smallest, collectgarbage("count") - before)
        end
        return smallest
    end
    jit.off(); jit.flush()
    collectgarbage("collect"); collectgarbage("stop")
    local ok, smallestOrError = xpcall(smallestRoundGrowth, debug.traceback)
    collectgarbage("restart")
    jit.on()
    if not ok then error(smallestOrError, 0) end
    return smallestOrError
end

function M.visibleMenuRowOf(W, key)
    for index = 1, W.MENU_MAX_ROWS do
        local row = W.MenuRow(index)
        if row and row.key == key then return row end
    end
end

M.SHIFTED = true

function M.withShiftHeld(shifted, work)
    local isShiftKeyDown = _G.IsShiftKeyDown
    if shifted then _G.IsShiftKeyDown = function() return true end end
    local ok, err = pcall(work)
    _G.IsShiftKeyDown = isShiftKeyDown
    if not ok then error(err, 0) end
end

return M
