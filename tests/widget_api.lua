-- Every widget method the real client has, read from the game's own API
-- documentation (tests/blizzard/*Documentation.lua: Simple*, FrameAPI*, fetched by
-- tools/fetch_blizzard.py). The fake game answers these with a no-op; any
-- other capitalized name reads nil, so calling a method the client doesn't
-- have fails in the tests the way it fails in game.
local Blizz = require("blizzard")
local M = { names = {}, refusesSecrets = {} }

-- Real client methods the API docs leave out (checked against the game's
-- own UI code calling them). Add one only with a game file that calls it.
local UNDOCUMENTED = {
    -- GameTooltip: ActionButton.lua:655 and :1125, and nearly every game tooltip.
    "GetOwner", "SetOwner", "SetAction", "AddLine", "AddDoubleLine", "NumLines",
    -- GameTooltip: TooltipComparisonManager.lua:77 and :116.
    "GetAnchorType", "SetAnchorType",
}

-- Widget types' method lists only (tools/fetch_blizzard.py is_widget_doc):
-- the other API docs (UnitDocumentation...) list global functions.
function M.IsWidgetDoc(file)
    return string.find(file, "Documentation%.lua$") ~= nil and (string.find(file, "^Simple") ~= nil
        or string.find(file, "^FrameAPI") ~= nil or string.find(file, "FrameAPIDocumentation%.lua$") ~= nil)
end

function M.Load()
    local count = 0
    local docs = {}
    -- Secret arguments from addon code: refused by a method whose docs say
    -- AllowedWhenUntainted or NotAllowed, unless any widget type documents
    -- the same name as AllowedWhenTainted (names are shared across types).
    local accepts = {}
    function docs:AddDocumentationTable(t)
        for _, fn in ipairs(t.Functions or {}) do
            if not M.names[fn.Name] then M.names[fn.Name] = true; count = count + 1 end
            local s = fn.SecretArguments
            if s == "AllowedWhenTainted" then accepts[fn.Name] = true
            elseif s == "AllowedWhenUntainted" or s == "NotAllowed" then M.refusesSecrets[fn.Name] = true end
        end
    end
    local finish = function()
        for name in pairs(accepts) do M.refusesSecrets[name] = nil end
    end
    local env = setmetatable({ APIDocumentation = docs }, { __index = function() return Blizz.INERT end })
    for file in Blizz.List("") do
        if M.IsWidgetDoc(file) then
            local chunk = assert(loadfile(Blizz.DIR .. file))
            setfenv(chunk, env)
            chunk()
        end
    end
    for _, name in ipairs(UNDOCUMENTED) do
        if not M.names[name] then M.names[name] = true; count = count + 1 end
    end
    finish()
    return count
end

return M
