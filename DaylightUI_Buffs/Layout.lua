-- Layout: a faithful port of the client's flow layout, the one its aura
-- container uses to place buttons. Given the groups in order and how many
-- buttons each shows, it yields every button's offset from the container's
-- anchor corner. The bar uses it to map a cursor position back to
-- (group, index) - the client hides which of its buttons are live, but the
-- geometry is fully determined by data we can read out of combat - and the
-- preview uses it so a sample looks exactly like the real thing.
--
-- Offsets follow the client's convention: measured from the anchor point,
-- x positive to the right, y positive upward.

local _, BL = ...

local Layout = {}
BL.Layout = Layout

Layout.LEFT, Layout.RIGHT, Layout.DOWN = -1, 1, -1

-- groups: ordered list of { key, count, elementWidth, elementHeight, elementSpacing,
--   lineSpacing, groupSpacing, groupLineSpacing, forceNewLine }
-- options: { anchorPoint = "TOPLEFT"|"TOPRIGHT", horizontal = LEFT|RIGHT, vertical = DOWN|UP, maximumLineSize }
-- Returns { elements = { { key, index, x, y, width, height } ... }, width, height, lines }
function Layout.Flow(groups, options)
    local horizontal = options.horizontal or Layout.RIGHT
    local vertical = options.vertical or Layout.DOWN
    local maximumLineSize = options.maximumLineSize or math.huge

    local cursorPrimary, cursorCross = 0, 0
    local lineIndex, linePrimarySize, lineCrossSize = 1, 0, 0
    local layoutPrimarySize, layoutCrossSize = 0, 0
    local hasPlacedElement = false
    local elements = {}

    local function advance(crossGap)
        cursorPrimary = 0
        cursorCross = cursorCross + ((lineCrossSize + crossGap) * vertical)
        lineIndex = lineIndex + 1
        linePrimarySize = 0
        lineCrossSize = 0
    end

    for _, group in ipairs(groups) do
        local count = group.count or 0
        local elementSpacing = group.elementSpacing or 0
        local lineSpacing = group.lineSpacing or 0
        local groupSpacing = group.groupSpacing or 0
        local groupLineSpacing = group.groupLineSpacing or lineSpacing

        if hasPlacedElement and count > 0 then
            if group.forceNewLine then
                advance(groupLineSpacing)
            elseif groupSpacing > 0 then
                if linePrimarySize > 0 and linePrimarySize + groupSpacing > maximumLineSize then
                    advance(groupLineSpacing)
                else
                    cursorPrimary = cursorPrimary + (groupSpacing * horizontal)
                    linePrimarySize = linePrimarySize + groupSpacing
                end
            end
        end

        for index = 1, count do
            local width, height = group.elementWidth, group.elementHeight
            local nextLinePrimarySize = linePrimarySize > 0 and linePrimarySize + width or width
            if linePrimarySize > 0 and nextLinePrimarySize > maximumLineSize then
                advance(lineSpacing)
                nextLinePrimarySize = width
            end
            elements[#elements + 1] = { key = group.key, index = index, x = cursorPrimary, y = cursorCross, width = width, height = height }
            cursorPrimary = cursorPrimary + ((width + elementSpacing) * horizontal)
            linePrimarySize = nextLinePrimarySize + elementSpacing
            lineCrossSize = math.max(lineCrossSize, height)
            layoutPrimarySize = math.max(layoutPrimarySize, linePrimarySize - elementSpacing)
            layoutCrossSize = math.max(layoutCrossSize, math.abs(cursorCross) + height)
            hasPlacedElement = true
        end
    end

    return {
        elements = elements,
        width = hasPlacedElement and layoutPrimarySize or 0,
        height = hasPlacedElement and layoutCrossSize or 0,
        lines = hasPlacedElement and lineIndex or 0,
    }
end

-- The rectangle an element occupies, relative to the anchor corner.
function Layout.ElementRect(element, anchorPoint)
    local left = anchorPoint == "TOPRIGHT" and (element.x - element.width) or element.x
    local top = element.y
    return left, top - element.height, left + element.width, top
end

-- Element under a point given relative to the anchor corner, or nil.
function Layout.HitTest(flow, anchorPoint, x, y)
    for _, e in ipairs(flow.elements) do
        local l, b, r, t = Layout.ElementRect(e, anchorPoint)
        if x >= l and x <= r and y >= b and y <= t then return e end
    end
    return nil
end

-- ---------------------------------------------------------------------
-- Category helpers shared by the bar and the preview
-- ---------------------------------------------------------------------

function Layout.ConsolidateAllowed(category, settings, groupState)
    if not (category and category.consolidate) then return false end
    groupState = groupState or {}
    if settings.consolidateOnlyRaid and not groupState.inRaid then return false end
    if settings.consolidateOnlyGroup and not groupState.inGroup then return false end
    return true
end

local function sortByExpiry(list)
    table.sort(list, function(a, b)
        if a.timed ~= b.timed then return a.timed end
        if a.timed and a.expirationTime ~= b.expirationTime then
            return a.expirationTime < b.expirationTime
        end
        return (a.auraInstanceID or a.index or 0) < (b.auraInstanceID or b.index or 0)
    end)
    return list
end
Layout.SortLikeClient = sortByExpiry

-- Groups entries by resolved category in categoryOrder (hidden categories
-- dropped), each sorted the way the client sorts a group.
function Layout.ClusterEntries(entries, categories, order)
    local byCategory = {}
    for i = 1, #entries do
        local entry = entries[i]
        local id = BL.Classify.Resolve(entry)
        if not categories[id] then id = "other" end
        byCategory[id] = byCategory[id] or {}
        table.insert(byCategory[id], entry)
    end
    local clusters = {}
    for _, id in ipairs(order) do
        local list = byCategory[id]
        local cat = categories[id]
        if list and cat and not cat.hidden then
            clusters[#clusters + 1] = { categoryId = id, entries = sortByExpiry(list) }
        end
    end
    return clusters
end
