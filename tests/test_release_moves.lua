local Check = require("release_check")
local data = require("release_data")
local accepted = require("release_moves")

-- A player updating from the last release must find everything where they left
-- it. Only what differs from a default is saved, so a changed default moves
-- everyone who never touched that setting, and a new piece at a shared spot
-- can push the ones already there. tests/release_data.lua is what that
-- release gave a player who changed nothing. Every module loads here, some
-- without the game parts they'd need to build, so only moves are checked.

local function same(a, b)
    if type(a) == "number" and type(b) == "number" then
        return string.format("%.10g", a) == string.format("%.10g", b)
    end
    return a == b
end

local HOW = "\nA returning player's setup would move. Keep existing profiles on the old value with an "
    .. "upgrade step, or if the move is wanted, list it in tests/release_moves.lua with why."

T.test("release moves: a player from the last release keeps every setting", function()
    local DUI = Check.Load(data.saved)
    local now = Check.Values(DUI)
    local moved = {}
    for path, was in pairs(data.values) do
        local is = now[path]
        if is ~= nil and not same(is, was) and not accepted.values[path] then
            moved[#moved + 1] = string.format("  %s: %s -> %s", path, tostring(was), tostring(is))
        end
    end
    table.sort(moved)
    T.eq(#moved, 0, "settings changed since " .. data.version .. ":\n" .. table.concat(moved, "\n") .. HOW)
end)

T.test("release moves: every movable frame stays where the last release put it", function()
    local DUI = Check.Load(data.saved)
    local now = Check.Frames(DUI)
    local moved = {}
    for key, was in pairs(data.frames or {}) do
        local is = now[key]
        if is ~= nil and is ~= was and not accepted.frames[key] then
            moved[#moved + 1] = string.format("  %s: %s -> %s", key, was, is)
        end
    end
    table.sort(moved)
    T.eq(#moved, 0, "frames moved since " .. data.version .. ":\n" .. table.concat(moved, "\n") .. HOW)
end)

T.test("release moves: every nameplate piece stays where the last release put it", function()
    local DUI = Check.Load(data.saved)
    local now = Check.Plates(DUI)
    local moved = {}
    for key, was in pairs(data.plates) do
        local case, piece = key:match("^(.-)|(.*)$")
        local is = now[key]
        local ok = accepted.plates[key] or accepted.plates[case] or accepted.plates["*|" .. piece]
        if is ~= nil and is ~= was and not ok then
            moved[#moved + 1] = string.format("  %s: %s -> %s", key, was, is)
        end
    end
    table.sort(moved)
    T.eq(#moved, 0, "nameplate pieces moved since " .. data.version .. ":\n" .. table.concat(moved, "\n") .. HOW)
end)
