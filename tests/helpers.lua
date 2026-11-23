-- Test helpers not tied to one part of the addon.
local stub = require("stub")

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

function M.menuRowOf(W, key)
    local row = M.visibleMenuRowOf(W, key)
    if row then return row end
    W.ScrollMenu(-1000)
    row = M.visibleMenuRowOf(W, key)
    if row then return row end
    W.ScrollMenu(1000)
    return M.visibleMenuRowOf(W, key)
end

function M.countBlockedActions()
    local errorsBefore = #stub.errors
    return function()
        local blocked = 0
        for index = errorsBefore + 1, #stub.errors do
            if tostring(stub.errors[index]):find("ADDON_ACTION_", 1, true) then blocked = blocked + 1 end
        end
        return blocked
    end
end

function M.indexOf(list, value)
    for index, listed in ipairs(list) do
        if listed == value then return index end
    end
    return nil
end

function M.countCalls(frame, method)
    local counter = { calls = 0 }
    local original = frame[method]
    frame[method] = function(...)
        counter.calls = counter.calls + 1
        return original(...)
    end
    function counter.restore() frame[method] = original end
    return counter
end

function M.recordTooltips(W)
    local tooltips, showTooltip, hideTooltip = { shown = {}, hidden = 0 }, W.Tooltip, W.HideTooltip
    W.Tooltip = function(owner, title, body)
        tooltips.shown[#tooltips.shown + 1] = { owner, title, body }
        return showTooltip(owner, title, body)
    end
    W.HideTooltip = function()
        tooltips.hidden = tooltips.hidden + 1
        return hideTooltip()
    end
    function tooltips.restore() W.Tooltip, W.HideTooltip = showTooltip, hideTooltip end
    return tooltips
end

-- The relative frame is compared by identity: frames hold their parents, so can't be deep-compared.
function M.expectAnchor(frame, expected, context, index)
    local point, relative, relativePoint, x, y = frame:GetPoint(index or 1)
    T.deq({ point, relativePoint, x, y }, { expected[1], expected[3], expected[4], expected[5] }, context)
    T.truthy(relative == expected[2], context .. ": anchored to " .. tostring(relative and relative.GetName and relative:GetName()))
end

function M.recordReveals(DUI)
    local reveals = {}
    DUI.On("RevealFrame", function(key, on) reveals[#reveals + 1] = { key, on } end)
    return reveals
end

return M
