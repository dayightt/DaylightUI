-- What a tooltip shows, line by line, for the rich panel. Read from the
-- tooltip's own text after every post-call, so lines another addon added after
-- the game's are there too, with the data line's type where the data has one.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret

local Read = {}
ns.RichRead = Read

-- One reused table per line: an item's tooltip refills every 0.2 s.
local lines = {}

local function text(fs)
    if type(fs) ~= "table" or not fs.GetText then return nil end
    if fs.IsShown and fs:IsShown() == false then return nil end
    local t = fs:GetText()
    if t == "" then return nil end
    return t
end

local function color(fs)
    local r, g, b = fs:GetTextColor()
    if isSecret(r) or isSecret(g) or isSecret(b) then return nil end
    return r, g, b
end

-- The data's line types, by line, when the data has them plain.
local function typeOf(data, i)
    local list = type(data) == "table" and data.lines
    local line = type(list) == "table" and list[i]
    local t = type(line) == "table" and line.type or nil
    if isSecret(t) then return nil end
    return t
end

-- Returns the number of lines, the list (lines[i] = { left, right, lc, rc,
-- type }; lc and rc are { r, g, b } or nil) and whether any line is secret.
-- A secret line stops the read: nothing about its size can be known then.
function Read.Lines(tip, data)
    local Tip = ns.Tooltip
    local n = tip.NumLines and tip:NumLines()
    if isSecret(n) then return 0, lines, true end
    if type(n) ~= "number" then n = 0 end
    for i = 1, n do
        local left, right = Tip.Line(tip, i), Tip.Line(tip, i, "Right")
        local lt, rt = text(left), text(right)
        if isSecret(lt) or isSecret(rt) then return i - 1, lines, true end
        local line = lines[i]
        if not line then
            line = { lc = {}, rc = {} }
            lines[i] = line
        end
        line.left, line.right, line.type = lt, rt, typeOf(data, i)
        line.hasLC, line.hasRC = false, false
        if lt then
            local r, g, b = color(left)
            if r == nil then return i - 1, lines, true end
            line.lc[1], line.lc[2], line.lc[3], line.hasLC = r, g, b, true
        end
        if rt then
            local r, g, b = color(right)
            if r == nil then return i - 1, lines, true end
            line.rc[1], line.rc[2], line.rc[3], line.hasRC = r, g, b, true
        end
    end
    return n, lines, false
end

-- The unit a tooltip shows, plain, or nil.
function Read.Unit(tip)
    if type(tip.GetUnit) ~= "function" then return nil end
    local _, unit = tip:GetUnit()
    if isSecret(unit) or type(unit) ~= "string" then return nil end
    return unit
end
