-- The Skills page: two columns, professions and
-- secondary skills on the left, weapon skills (then armor and languages,
-- folded) on the right. Each skill a name, "285 / 300" and a thin bar in
-- the accent. Folding is the game's own (its header click
-- does the same), armor and languages once per login.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

local Skills = {}
ns.Skills = Skills

-- The game's skill line categories (a header's skillID is its category).
Skills.LEFT = { [11] = true, [9] = true }     -- professions, secondary skills
Skills.HIDDEN = { [7] = true }                -- class skills: the game hides them too
Skills.FOLD = { [8] = true, [10] = true }     -- armor, languages

function Skills.Read()
    local C, out = C_SkillInfo, {}
    if type(C) ~= "table" or type(C.GetNumSkillLines) ~= "function" then return out end
    for i = 1, C.GetNumSkillLines() do
        local s = C.GetSkillLineInfo(i)
        -- A line with a parent repeats its parent's name and rank: the game's own window skips it too.
        -- isChild (a sub-header or a line under one) is missing from the API docs, but the game's
        -- own skills window reads it the same way (Camelot/SkillsFrame.lua).
        if s and (s.parentSkillLineID or 0) == 0 then
            out[#out + 1] = { index = i, name = s.name or "", header = s.isHeader == true, child = s.isChild == true,
                category = s.isHeader and s.skillID or s.skillLineCategoryID, rank = s.rank or 0, max = s.maxRank or 0,
                modifier = s.modifier or 0, collapsed = s.isCollapsed == true }
        end
    end
    return out
end

local function skillItem(s, key, rgb)
    local item = { kind = "row", key = "s" .. s.index, text = s.name, indent = s.child and 1 or 0, data = s }
    if s.max > 1 then
        if s.modifier > 0 then
            item.right = string.format("%d (+%d) / %d", s.rank, s.modifier, s.max)
        else
            item.right = string.format("%d / %d", s.rank, s.max)
        end
        item.bar = { value = s.rank, max = s.max, key = key, rgb = rgb }
    end
    return item
end

-- Two item lists. A top header starts a group; its lines follow it until
-- the next top header. A collapsed group shows its header only.
function Skills.Columns(lines)
    local left, right = {}, {}
    local key, rgb = ns.List.OwnBar()
    local into, skip = nil, false
    for _, s in ipairs(lines) do
        if s.header and not s.child then
            skip = Skills.HIDDEN[s.category or 0] == true
            into = Skills.LEFT[s.category or 0] and left or right
            if not skip then
                into[#into + 1] = { kind = "head", key = "h" .. s.index, text = s.name, folded = s.collapsed, data = s }
            end
            if s.collapsed then skip = true end
        elseif not skip and into then
            if s.header then
                into[#into + 1] = { kind = "head", key = "h" .. s.index, text = s.name, folded = s.collapsed, indent = 1, data = s }
            else
                into[#into + 1] = skillItem(s, key, rgb)
            end
        end
    end
    return left, right
end

local foldedOnce = false
-- Armor and languages folded once per login. True when it folded something.
function Skills.FoldDefaults(lines)
    if foldedOnce then return false end
    foldedOnce = true
    local did = false
    for i = #lines, 1, -1 do   -- from the bottom, so folding doesn't move the lines still to fold
        local s = lines[i]
        if s.header and not s.child and Skills.FOLD[s.category or 0] and not s.collapsed then
            C_SkillInfo.CollapseSkillHeader(s.index)
            did = true
        end
    end
    return did
end

local function fold(item)
    local s = item.data
    if s.collapsed then C_SkillInfo.ExpandSkillHeader(s.index) else C_SkillInfo.CollapseSkillHeader(s.index) end
    ns.Window.Refresh()
end

function Skills.Build(page)
    page.left = ns.List.Make(page, { onFold = fold, row = ns.List.BAR_ROW })
    page.right = ns.List.Make(page, { onFold = fold, row = ns.List.BAR_ROW })
end

function Skills.Place(page)
    local E, W = ns.List.EDGE, ns.Window.Width()
    local w = math.floor((W - 3 * E) / 2)
    ns.List.Place(page.left, E, w)
    ns.List.Place(page.right, 2 * E + w, w)
end

function Skills.Refresh(page)
    local lines = Skills.Read()
    if Skills.FoldDefaults(lines) then lines = Skills.Read() end
    local left, right = Skills.Columns(lines)
    ns.List.Set(page.left, left)
    ns.List.Set(page.right, right)
end

Skills.events = { "SKILL_LINES_CHANGED" }
Skills.Available = function() return type(C_SkillInfo) == "table" and type(C_SkillInfo.GetNumSkillLines) == "function" end

ns.Window.Register("skills", Skills)
