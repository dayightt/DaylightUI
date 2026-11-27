-- The Skills page: one list (professions and secondary skills first, then
-- weapon skills, armor and languages, the last two folded once per login), each
-- skill a name, "285 / 300" and a thin bar in the accent. A click picks a skill
-- and the pane on the right says what it is, as the game's skill pane does; a
-- weapon skill adds its hit, crit and glancing numbers against a mob of your
-- level and a raid boss. Folding is the game's own (its header click does the same).

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

local Skills = {}
ns.Skills = Skills

-- The game's skill line categories (a header's skillID is its category).
Skills.LEFT = { [11] = true, [9] = true }     -- professions, secondary skills
Skills.HIDDEN = { [7] = true }                -- class skills: the game hides them too
Skills.FOLD = { [8] = true, [10] = true }     -- armor, languages
Skills.DEFENSE = 95                           -- the Defense skill line

-- The game's weapon skill lines (its SkillsFrame.lua WEAPON_SKILL_LINES), true for ranged.
Skills.WEAPONS = { [43] = false, [44] = false, [45] = true, [46] = true, [54] = false, [55] = false, [136] = false,
    [160] = false, [172] = false, [173] = false, [176] = true, [226] = true, [228] = true, [229] = false,
    [162] = false, [3014] = false }
-- Its numbers: a level is worth 5 skill points, each point 0.04% hit and crit, a raid boss is level 63.
Skills.PER_LEVEL, Skills.PER_POINT, Skills.BOSS_LEVEL = 5, 0.04, 63
Skills.ROW_GAP = 4      -- between the pane's number lines
Skills.SECTION_GAP = 12 -- above each section heading

-- What a click asked for, by header name, until the game's list says the same (or WANT_FOR
-- seconds pass): the game may not have changed the fold by the time the page reads it again,
-- and the page would draw the old state, or flip back when the game's late answer arrives.
Skills.want = {}
Skills.WANT_FOR = 1.5

function Skills.Read()
    local C, out = C_SkillInfo, {}
    if type(C) ~= "table" or type(C.GetNumSkillLines) ~= "function" then return out end
    for i = 1, C.GetNumSkillLines() do
        local s = C.GetSkillLineInfo(i)
        -- A line with a parent repeats its parent's name and rank: the game's own window skips it too.
        -- isChild (a sub-header or a line under one) is missing from the API docs, but the game's
        -- own skills window reads it the same way (Camelot/SkillsFrame.lua).
        if s and (s.parentSkillLineID or 0) == 0 then
            out[#out + 1] = { index = i, id = s.skillID, desc = s.description, name = s.name or "",
                header = s.isHeader == true, child = s.isChild == true,
                category = s.isHeader and s.skillID or s.skillLineCategoryID, rank = s.rank or 0, max = s.maxRank or 0,
                modifier = s.modifier or 0, collapsed = s.isCollapsed == true }
            local line = out[#out]
            -- Defense takes its bonus from UnitDefenseSkill, as the game's own skills window does.
            -- In a fight that number is secret: the line's own stays.
            if s.skillID == Skills.DEFENSE and type(UnitDefenseSkill) == "function" then
                local _, mod = UnitDefenseSkill("player")
                if type(mod) == "number" and not DUI.IsSecret(mod) then line.modifier = mod end
            end
            local w = line.header and Skills.want[line.name]
            if w then
                if w.collapsed == line.collapsed or GetTime() > w.till then Skills.want[line.name] = nil
                else line.collapsed = w.collapsed end
            end
        end
    end
    return out
end

local function skillItem(s, key, rgb)
    -- Keyed by name: folding a group above moves the index, and the pick should stay.
    local item = { kind = "row", key = "s" .. s.name, text = s.name, indent = s.child and 1 or 0, data = s }
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
    Skills.want[s.name] = { collapsed = not s.collapsed, till = GetTime() + Skills.WANT_FOR }
    if s.collapsed then C_SkillInfo.ExpandSkillHeader(s.index) else C_SkillInfo.CollapseSkillHeader(s.index) end
    ns.Window.Refresh()
end

-- "+0.08%", "-0.68%", "0.00%", as the game's skill pane writes them.
function Skills.Percent(v)
    if v == 0 then v = 0 end   -- no "-0.00%"
    local text = string.format("%.2f%%", v)
    if v > 0 then text = "+" .. text end
    return text
end

-- A weapon skill's numbers, the game's way (SkillDetailFrameMixin:AddWeaponSkillRows):
-- each point short of what a target's level expects costs 0.04% hit and crit. nil
-- for anything but a weapon skill.
function Skills.Weapon(s)
    local ranged = s and not s.header and Skills.WEAPONS[s.id or 0]
    if ranged == nil then return nil end
    local skill = s.rank + s.modifier
    local level = type(UnitLevel) == "function" and UnitLevel("player") or 0
    local function vs(targetLevel) return (targetLevel * Skills.PER_LEVEL - skill) * -Skills.PER_POINT end
    local out = { ranged = ranged, same = vs(level), boss = vs(Skills.BOSS_LEVEL) }
    -- Glancing blows (melee only). The game's own pane calls these two; they aren't in its API docs.
    if not ranged and type(GetGlancingBlowChance) == "function" and type(GetGlancingBlowPenalty) == "function" then
        local defense = Skills.BOSS_LEVEL * Skills.PER_LEVEL
        out.glance = GetGlancingBlowChance(skill, defense) * 100
        out.penalty = GetGlancingBlowPenalty(skill, defense) * 100
    end
    return out
end

-- The pane's lines for a weapon skill: section headings and label/value pairs.
function Skills.WeaponLines(w)
    local L = DUI.L
    local function pct(v) return { text = Skills.Percent(v), bad = v < 0 } end
    local lines = {
        { head = L["Vs a mob of your level"] },
        { label = L["Hit"], value = pct(w.same) }, { label = L["Crit"], value = pct(w.same) },
        { head = L["Vs a raid boss"] },
        { label = L["Hit"], value = pct(w.boss) }, { label = L["Crit"], value = pct(w.boss) },
    }
    if w.glance then
        lines[#lines + 1] = { label = L["Glancing"], value = { text = string.format(L["%s for %s less"],
            string.format("%.0f%%", w.glance), string.format("%.0f%%", w.penalty)) } }
    end
    return lines
end

local function paneLine(page, i)
    page.lines = page.lines or {}
    local l = page.lines[i]
    if l then return l end
    local P, Style = page.pane, DUI.Style
    l = { label = Style.Text(P, Style.SIZE.body, "LEFT"), value = Style.Text(P, Style.SIZE.body, "RIGHT"),
          head = Style.Text(P, Style.SIZE.tiny, "LEFT") }
    l.label:Hide(); l.value:Hide(); l.head:Hide()   -- each line shows only the parts it uses
    page.lines[i] = l
    return l
end

local function picked(page)
    for _, item in ipairs(page.list.items) do
        if item.kind == "row" and item.key == page.list.selectedKey then return item.data end
    end
end

function Skills.ShowPane(page)
    local P, s, Style = page.pane, picked(page), DUI.Style
    P:SetShown(s ~= nil)
    for _, l in ipairs(page.lines or {}) do l.label:Hide(); l.value:Hide(); l.head:Hide() end
    if not s then return end
    P.title:SetText(s.name)
    local ranked = s.max > 1
    P.sub:SetText(ranked and (s.modifier > 0 and string.format("%d (+%d) / %d", s.rank, s.modifier, s.max)
        or string.format("%d / %d", s.rank, s.max)) or "")
    Style.InkText(P.sub, "pop")
    P.bar:SetShown(ranked)
    if ranked then
        local key, rgb = ns.List.OwnBar()
        P.bar:SetMinMaxValues(0, s.max)
        -- The same skill rising: the fill glides; another one picked: at once.
        Style.SetBarValue(P.bar, s.rank, P.skill ~= s.name)
        ns.List.PaintBar(P.bar, key, rgb)
    end
    P.barText:SetText("")
    P.body:SetText(type(s.desc) == "string" and s.desc or "")
    P.skill = s.name
    local w = Skills.Weapon(s)
    if not w then return end
    local pad, above = ns.List.PANE_PAD, P.body
    for i, line in ipairs(Skills.WeaponLines(w)) do
        local l = paneLine(page, i)
        if line.head then
            l.head:ClearAllPoints()
            l.head:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -Skills.SECTION_GAP)
            l.head:SetText(Style.Upper(line.head))
            Style.InkText(l.head, "pop")
            l.head:Show()
            above = l.head
        else
            l.label:ClearAllPoints()
            l.label:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -Skills.ROW_GAP)
            l.label:SetPoint("RIGHT", P, "RIGHT", -pad, 0)   -- the row's full width: its value sits at its right end
            l.label:SetText(line.label)
            Style.InkText(l.label, "LABEL")
            l.value:ClearAllPoints()
            l.value:SetPoint("TOPRIGHT", l.label, "TOPRIGHT", 0, 0)
            l.value:SetText(line.value.text)
            if line.value.bad then Style.InkText(l.value, "DAMAGE") else Style.InkText(l.value, "pop") end
            l.label:Show()
            l.value:Show()
            above = l.label
        end
    end
end

function Skills.Build(page)
    page.list = ns.List.Make(page, { onFold = fold, row = ns.List.BAR_ROW, onPick = function() Skills.ShowPane(page) end })
    page.pane = ns.List.Pane(page)
end

function Skills.Place(page)
    local E, W = ns.List.EDGE, ns.Window.Width()
    local paneW = ns.List.PANE_W
    ns.List.Place(page.list, E, W - 3 * E - paneW)
    ns.List.PlacePane(page.pane, W - E - paneW, paneW)
end

function Skills.Refresh(page)
    local lines = Skills.Read()
    if Skills.FoldDefaults(lines) then lines = Skills.Read() end
    local left, right = Skills.Columns(lines)
    local items = left
    for _, item in ipairs(right) do items[#items + 1] = item end
    local L = page.list
    local found = false
    for _, item in ipairs(items) do if item.key == L.selectedKey then found = true end end
    if not found then
        L.selectedKey = nil
        for _, item in ipairs(items) do
            if item.kind == "row" then L.selectedKey = item.key; break end
        end
    end
    ns.List.Set(L, items)
    Skills.ShowPane(page)
end

Skills.events = { "SKILL_LINES_CHANGED" }
Skills.Available = function() return type(C_SkillInfo) == "table" and type(C_SkillInfo.GetNumSkillLines) == "function" end

ns.Window.Register("skills", Skills)
