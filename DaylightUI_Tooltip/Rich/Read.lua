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
    -- A secret is handed back as it is: comparing one errors.
    if isSecret(t) then return t end
    if t == "" then return nil end
    return t
end

local function color(fs)
    local r, g, b = fs:GetTextColor()
    if isSecret(r) or isSecret(g) or isSecret(b) then return nil end
    return r, g, b
end

-- Which drawn line a data line's own text sits on, or nil. The game stamps
-- each data line with NumLines after adding its text, so a line with no text
-- (a recipe's empty spacer, the SellPrice line) carries the stamp of the line
-- above it. The SellPrice line's post-call then adds the coins line, so that
-- one is its own, one below the stamp. Read as its stamp, the line above (a
-- ring's last stat, a level requirement) was taken for the sell price.
local SELL = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice or 11
local function hasWords(v) return isSecret(v) or (type(v) == "string" and v ~= "") end
function Read.Landed(line)
    if type(line) ~= "table" then return nil end
    local at = line.lineIndex
    if isSecret(at) or type(at) ~= "number" then return nil end
    if hasWords(line.leftText) or hasWords(line.rightText) then return at end
    local kind = line.type
    if not isSecret(kind) and kind == SELL then return at + 1 end
    return nil
end

-- Which data line landed on each drawn line (Read.Landed). Empty when the
-- data has no indexes: then they're matched by position.
local landed = {}
local function mapLanded(data)
    for k in pairs(landed) do landed[k] = nil end
    local list = type(data) == "table" and data.lines
    if type(list) ~= "table" then return end
    for _, line in ipairs(list) do
        local at = Read.Landed(line)
        if at then landed[at] = line end
    end
end

-- The data's line type and id (a quest title's quest), by line, when plain.
local function typeOf(data, i)
    local list = type(data) == "table" and data.lines
    local line
    if next(landed) then
        line = landed[i]
    else
        line = type(list) == "table" and list[i]
    end
    if type(line) ~= "table" then return nil end
    local t, id = line.type, line.id
    if isSecret(t) then t = nil end
    if isSecret(id) or type(id) ~= "number" then id = nil end
    return t, id
end

-- Returns the number of lines, the list (lines[i] = { left, right, lc, rc,
-- type, id }; lc and rc are { r, g, b } or nil) and whether any line is secret.
-- A secret line stops the read: nothing about its size can be known then.
function Read.Lines(tip, data)
    local Tip = ns.Tooltip
    local n = tip.NumLines and tip:NumLines()
    if isSecret(n) then return 0, lines, true end
    if type(n) ~= "number" then n = 0 end
    mapLanded(data)
    for i = 1, n do
        local left, right = Tip.Line(tip, i), Tip.Line(tip, i, "Right")
        local lt, rt = text(left), text(right)
        if isSecret(lt) or isSecret(rt) then return i - 1, lines, true end
        local line = lines[i]
        if not line then
            line = { lc = {}, rc = {} }
            lines[i] = line
        end
        line.left, line.right = lt, rt
        line.type, line.id = typeOf(data, i)
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

-- What the last build showed, line by line, in tables kept per tooltip: a
-- refill that brings the same lines (an item's, every 0.2 s) is told apart
-- from new content without building the card again.
function Read.Keep(seen, n, lines)
    seen.n = n
    for i = 1, n do
        local a, b = lines[i], seen[i]
        if not b then
            b = {}
            seen[i] = b
        end
        b.left, b.right, b.type = a.left, a.right, a.type
        b.l1, b.l2, b.l3 = a.hasLC and a.lc[1], a.hasLC and a.lc[2], a.hasLC and a.lc[3]
        b.r1, b.r2, b.r3 = a.hasRC and a.rc[1], a.hasRC and a.rc[2], a.hasRC and a.rc[3]
    end
end

function Read.Same(seen, n, lines)
    if seen.n ~= n then return false end
    for i = 1, n do
        local a, b = lines[i], seen[i]
        if a.left ~= b.left or a.right ~= b.right or a.type ~= b.type
            or (a.hasLC and a.lc[1]) ~= b.l1 or (a.hasLC and a.lc[2]) ~= b.l2 or (a.hasLC and a.lc[3]) ~= b.l3
            or (a.hasRC and a.rc[1]) ~= b.r1 or (a.hasRC and a.rc[2]) ~= b.r2 or (a.hasRC and a.rc[3]) ~= b.r3 then
            return false
        end
    end
    return true
end

-- The unit a tooltip shows, plain, or nil.
function Read.Unit(tip)
    if type(tip.GetUnit) ~= "function" then return nil end
    local _, unit = tip:GetUnit()
    if isSecret(unit) then return Read.WorldUnit(tip) end
    if type(unit) ~= "string" then return nil end
    return unit
end

-- Under a map or PvP restriction the game hands back a creature's token
-- secret (it finds it with UnitTokenFromGUID). The world's tooltip is always
-- about the unit under the mouse, so that one is it.
function Read.WorldUnit(tip)
    if tip ~= GameTooltip then return nil end
    local owner = tip.GetOwner and tip:GetOwner()
    if not isSecret(owner) and owner ~= UIParent then return nil end
    if UnitExists("mouseover") ~= true then return nil end
    return "mouseover"
end
