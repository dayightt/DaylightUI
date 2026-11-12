-- Height limit for the list. Past it the view clips and the mouse wheel scrolls.
-- Rows near an edge with more beyond fade out over the last EDGE px, and the
-- shared scroll bar (W.Scroll) shows while the mouse is over the list. The wheel
-- glides (bar.Wheel, FAST). In combat the list doesn't scroll while item buttons
-- are showing, since they can't follow.

local _, ns = ...
local DUI = DaylightUI

local Scroll = {}
ns.Scroll = Scroll

Scroll.STEP = 40
Scroll.EDGE = 24
Scroll.THUMB_GAP = 6     -- right of the list
Scroll.offset = 0
Scroll.topInset = 0      -- px between the view's top and the rows' top edge (the pinned header)

local view, content, bar
local total, visible = 0, 0

function Scroll.Build(v, c)
    view, content = v, c
    -- Shared scroll bar. The wheel is handled here (for the combat hold below, and the
    -- view's wheel turns off when the list fits); the glide is the bar's.
    bar = DUI.Widgets.Scroll(v, { wheel = false, x = Scroll.THUMB_GAP, step = Scroll.STEP,
        read = function()
            local most = math.max(0, total - visible)
            return math.min(Scroll.offset, most), most, visible   -- pulled back, the bar already shows it
        end,
        write = function(y) Scroll.Move(y) end })
    Scroll.bar = bar
    v:SetScript("OnMouseWheel", function(_, delta) DUI.SafeCall(Scroll.Wheel, delta) end)
end

function Scroll.Paint()
    if bar then bar.Update() end
end

function Scroll.To(y)
    local most = math.max(0, total - visible)
    Scroll.offset = math.max(0, math.min(most, y))
    if view then view:SetVerticalScroll(Scroll.offset) end
    Scroll.Paint()
end

-- A shrinking list pulls the scroll back. Past the bottom for now, on purpose,
-- while the rows glide up with it.
local function pulled(y)
    Scroll.offset = y
    if view then view:SetVerticalScroll(y) end
    if ns.Tracker and ns.Tracker.RefreshEdges then ns.Tracker.RefreshEdges() end
    if ns.Items then ns.Items.Follow() end
end

-- animate: rows are gliding to new spots. A scroll pulled back by the shorter
-- list glides with them, so the rows below what left stay put on screen instead
-- of jumping down and gliding back.
function Scroll.Set(h, max, animate)
    total = h
    visible = math.min(h, max)
    if view then view:EnableMouseWheel(h > max) end
    local most = math.max(0, total - visible)
    if animate and Scroll.offset > most and ns.Animate then
        if bar then bar.Stop() end
        ns.Animate.Follow(Scroll.offset, most, pulled)
        Scroll.Paint()
    else
        if ns.Animate then ns.Animate.Follow() end
        Scroll.To(Scroll.offset)
    end
    return visible
end

function Scroll.Held()
    return InCombatLockdown() and ns.Items and ns.Items.Any()
end

-- Scrolls to y, moving the row edge fades and item buttons along. Not in combat
-- while item buttons show (they can't follow). Glides call this every frame.
function Scroll.Move(y)
    if Scroll.Held() then return end
    if ns.Animate then ns.Animate.Follow() end
    Scroll.To(y)
    if ns.Tracker and ns.Tracker.RefreshEdges then ns.Tracker.RefreshEdges() end
    if ns.Items then ns.Items.Follow() end
end

function Scroll.Wheel(delta)
    if not bar then return end
    if Scroll.Held() then bar.Wake() else bar.Wheel(delta) end
end

function Scroll.EdgeAlpha(top, h, viewTop, viewH, moreAbove, moreBelow)
    local a = 1
    if moreBelow then
        local room = (viewTop + viewH) - top
        if room <= 0 then a = 0 elseif room < Scroll.EDGE then a = room / Scroll.EDGE end
    end
    if moreAbove then
        local room = (top + h) - viewTop
        if room <= 0 then a = 0 elseif room < Scroll.EDGE then a = math.min(a, room / Scroll.EDGE) end
    end
    return a
end

function Scroll.EdgeFor(y, h)
    h = type(h) == "number" and h or 0
    local inset = Scroll.offset > 0 and Scroll.topInset or 0
    if inset > 0 then
        -- Under the pinned header: fully faded by the time the row's top reaches the
        -- header's bottom (fading by its bottom let a tall block's first lines show
        -- through the header text).
        local a = Scroll.EdgeAlpha(y, h, Scroll.offset, visible, false, Scroll.offset + visible < total)
        local room = y - (Scroll.offset + inset)
        if room <= 0 then return 0 end
        if room < Scroll.EDGE then return math.min(a, room / Scroll.EDGE) end
        return a
    end
    return Scroll.EdgeAlpha(y, h, Scroll.offset, visible,
        Scroll.offset > 0, Scroll.offset + visible < total)
end
