-- Bar sizes and default positions (Bars.lua).
--
-- Default arrangement: action bar 1 bottom center with bar 2 above it, a 2 x 6 grid
-- on each side with bottoms level with bar 1, and the small bars in a thin row
-- above. Default positions follow the shapes, so a bigger bar 1 pushes the rest out
-- instead of overlapping. A data bar along the screen's bottom lifts them all clear
-- of it (Movers.Above), as it does the chat.

local _, ns = ...
local DUI = DaylightUI

local Shape = {}
ns.Shape = Shape

Shape.BUTTON = 45           -- an action button's own width at 100%
Shape.SMALL_BUTTON = 30     -- the stance, pet and possess buttons' width (measured in game)
Shape.BOTTOM = 26           -- bar 1's bottom edge above the screen's
Shape.SIDE_GAP = 24         -- gap between the center bars and a side grid
Shape.SMALL_SIZE = 60       -- the small bars' size, percent
Shape.SMALL_GAP = 6         -- gap for the small bars' row above bar 2
-- Each setting's slider: min, max, step.
Shape.RANGES = { size = { 50, 200, 10 }, height = { 40, 150, 5 }, pad = { 2, 10, 1 }, rows = { 1, 4, 1 }, icons = { 1, 12, 1 } }

-- A bar's settings (db.bars[key]), else the defaults.
function Shape.Config(key)
    local db = ns.Settings()
    local cfg = db and type(db.bars) == "table" and db.bars[key]
    return type(cfg) == "table" and cfg or ns.DEFAULTS.bars[key]
end

-- A button's height as a share of its width (the "Button height" setting, 100 =
-- square). Only the action bars have it; the game's small buttons stay square.
function Shape.Tall(cfg)
    local h = tonumber(cfg and cfg.height)
    if not h or h <= 0 then return 1 end
    return h / 100
end

-- How big a bar comes out: width, height. count = number of buttons (else its
-- "Buttons" setting, else 12); base = one button's own width (45); square = keep
-- the buttons square whatever the height setting says.
function Shape.Extent(cfg, count, base, square)
    local btn = (base or Shape.BUTTON) * cfg.size / 100
    local tall = btn * (square and 1 or Shape.Tall(cfg))
    local n = count or cfg.icons or 12
    if n < 1 then return 0, 0 end
    local rows = math.max(1, math.min(cfg.rows or 1, n))
    local across = math.ceil(n / rows)
    local cols, lines = across, rows
    if cfg.vertical then cols, lines = rows, across end
    return cols * btn + (cols - 1) * cfg.pad, lines * tall + (lines - 1) * cfg.pad
end

-- Each bar's default position as an anchor on UIParent, from the shapes.
function Shape.Defaults()
    local C = Shape.Config
    local main = C("main")
    local mainW, mainH = Shape.Extent(main)
    local _, bar2H = Shape.Extent(C("bar2"))
    local leftW = Shape.Extent(C("left"))
    -- Both grids are placed by their left edge, where the game starts their
    -- buttons. Bar 3's frame can come out wider than its buttons (sized for a single
    -- row), and anchoring any other edge would shift the buttons by the difference.
    local inner = mainW / 2 + Shape.SIDE_GAP
    local bottom = DUI.Movers.Above(Shape.BOTTOM)
    local bar2Y = bottom + mainH + main.pad
    local smallY = bar2Y + bar2H + Shape.SMALL_GAP
    local d = {
        stance = { point = "BOTTOMLEFT", rel = "BOTTOM", x = -mainW / 2, y = smallY, size = C("stance").size },
        pet = { point = "BOTTOMRIGHT", rel = "BOTTOM", x = mainW / 2, y = smallY, size = C("pet").size },
        possess = { point = "BOTTOM", x = 0, y = smallY, size = C("possess").size },
        main = { point = "BOTTOM", x = 0, y = bottom },
        bar2 = { point = "BOTTOM", x = 0, y = bar2Y },
        left = { point = "BOTTOMLEFT", rel = "BOTTOM", x = -inner - leftW, y = bottom },
        right = { point = "BOTTOMLEFT", rel = "BOTTOM", x = inner, y = bottom },
        -- Bars 5-8 stack above the small bars, out of the way until moved.
        bar5 = { point = "BOTTOM", x = 0, y = smallY + (bar2H + Shape.SMALL_GAP) },
        bar6 = { point = "BOTTOM", x = 0, y = smallY + 2 * (bar2H + Shape.SMALL_GAP) },
        bar7 = { point = "BOTTOM", x = 0, y = smallY + 3 * (bar2H + Shape.SMALL_GAP) },
        bar8 = { point = "BOTTOM", x = 0, y = smallY + 4 * (bar2H + Shape.SMALL_GAP) },
    }
    -- The totem bar takes the stance bar's spot (a shaman has no stance bar).
    d.totem = { point = d.stance.point, rel = d.stance.rel, x = d.stance.x, y = d.stance.y }
    -- The game's Extra Abilities button sits on top of the center bars at its own
    -- default spot, so ours goes over the right grid.
    local rightW, rightH = Shape.Extent(C("right"))
    d.extra = { point = "BOTTOM", x = inner + rightW / 2, y = bottom + rightH + Shape.SIDE_GAP }
    return d
end

