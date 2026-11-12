-- Cast button for the spellbook page. Wraps Win.Caster, a secure button laid
-- over the hovered row out of combat, and passes hover, drag and Shift-click
-- back to the page.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

local Cast = {}
ns.Cast = Cast

Cast.NAME = "DaylightUIBookCast"

-- Player spells cast by id, so lower ranks work too. Pet spells go through
-- /cast, and right click toggles autocast.
function Cast.Attributes(cell)
    if cell.future or cell.passive then return nil end
    if cell.pet then
        local a = { type1 = "macro", macrotext1 = "/cast " .. cell.name }
        if cell.autocast then a.type2, a.macrotext2 = "macro", "/petautocasttoggle " .. cell.name end
        return a
    end
    if type(cell.spellID) ~= "number" then return nil end
    return { type1 = "spell", spell = cell.spellID }
end

-- Called from the row's OnEnter. Does nothing in combat or for rows that
-- can't be cast.
function Cast.Over(row)
    if not Cast.caster then return nil end
    local b = Cast.caster.Over(row, row.cell and Cast.Attributes(row.cell))
    Cast.button = Cast.caster.button
    return b
end

function Cast.Hide(entering)
    if Cast.caster then Cast.caster.Hide(entering) end
end

function Cast.Init()
    if Cast.caster then return end
    Cast.caster = DUI.Win.Caster({ name = Cast.NAME,
        above = function() return ns.Window and ns.Window.frame end,
        enter = function(row) if ns.Spells then ns.Spells.Enter(row) end end,
        leave = function(row) if ns.Spells then ns.Spells.Leave(row) end end,
        drag = function(row) if ns.Spells then ns.Spells.Drag(row) end end,
        post = function(row, button) if ns.Spells then ns.Spells.Modified(row, button) end end })
end
