-- The Statistics page: categories on the left (their
-- sub-categories under them), the picked one's numbers on the right as a
-- plain two-column list.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

local Statistics = {}
ns.Statistics = Statistics

Statistics.LIST_W = 220

function Statistics.Categories()
    if type(GetStatisticsCategoryList) ~= "function" then return {} end
    local ids = GetStatisticsCategoryList() or {}
    local info, inList = {}, {}
    for _, id in ipairs(ids) do
        local title, parent = GetCategoryInfo(id)
        info[id] = { title = title or "", parent = parent }
        inList[id] = true
    end
    -- Each top category in the header colors in turn, its sub-categories dimmer.
    local items, n = {}, 0
    for _, id in ipairs(ids) do
        if not inList[info[id].parent or -1] then
            n = n + 1
            local color = { ns.Colors.Head(n) }
            local dim = { ns.Colors.Dim(color[1], color[2], color[3]) }
            items[#items + 1] = { kind = "row", key = "c" .. id, text = info[id].title, indent = 0, data = id, color = color }
            for _, child in ipairs(ids) do
                if info[child].parent == id then
                    items[#items + 1] = { kind = "row", key = "c" .. child, text = info[child].title, indent = 1, data = child,
                                          color = dim }
                end
            end
        end
    end
    return items
end

-- The game shows a number above 0, else "--"; text that isn't a number
-- (money) as it comes.
function Statistics.Value(q)
    local n = tonumber(q)
    if n then return n > 0 and ns.List.Number(n) or "--" end
    if type(q) == "string" and q ~= "" then return q end
    return "--"
end

-- color: the picked category's, for the numbers.
function Statistics.Rows(category, color)
    local out = {}
    if not category or type(GetCategoryNumAchievements) ~= "function" then return out end
    for i = 1, GetCategoryNumAchievements(category) or 0 do
        local quantity, skip, id = GetStatistic(category, i)
        if not skip and id then
            local _, name = GetAchievementInfo(id)
            out[#out + 1] = { kind = "row", key = "s" .. id, text = name or "", right = Statistics.Value(quantity),
                              rightColor = color or { DUI.Style.Pop() } }
        end
    end
    return out
end

function Statistics.Build(page)
    page.list = ns.List.Make(page, { onPick = function()
        page.right.offset = 0   -- a new category starts at its top
        Statistics.Refresh(page)
    end })
    page.right = ns.List.Make(page, {})
end

function Statistics.Place(page)
    local E, W = ns.List.EDGE, ns.Window.Width()
    ns.List.Place(page.list, E, Statistics.LIST_W)
    ns.List.Place(page.right, 2 * E + Statistics.LIST_W, W - 3 * E - Statistics.LIST_W)
end

function Statistics.Refresh(page)
    local cats = Statistics.Categories()
    local L = page.list
    local picked, color
    for _, item in ipairs(cats) do if item.key == L.selectedKey then picked, color = item.data, item.color end end
    if not picked and cats[1] then
        L.selectedKey, picked, color = cats[1].key, cats[1].data, cats[1].color
    end
    ns.List.Set(L, cats)
    ns.List.Set(page.right, Statistics.Rows(picked, color))
end

Statistics.Available = function() return type(GetStatisticsCategoryList) == "function" end

ns.Window.Register("statistics", Statistics)
