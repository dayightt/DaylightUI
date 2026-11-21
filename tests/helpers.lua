-- Test helpers not tied to one part of the addon.
local M = {}

-- KB of garbage left by calling work the given number of times.
function M.garbageMadeBy(work, calls)
    jit.off()   -- the game has no JIT, and its own bookkeeping isn't the addon's to count
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, calls do work() end
    local grown = collectgarbage("count") - before
    collectgarbage("restart")
    jit.on()
    return grown
end

function M.visibleMenuRowOf(W, key)
    for index = 1, W.MENU_MAX_ROWS do
        local row = W.MenuRow(index)
        if row and row.key == key then return row end
    end
end

return M
