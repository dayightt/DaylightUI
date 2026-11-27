-- Cast button for the spellbook page. Wraps Win.Caster, a secure button laid
-- over the hovered row out of combat, and passes hover, drag and Shift-click
-- back to the page.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book

local Cast = {}
ns.Cast = Cast

Cast.NAME = "DaylightUIBookCast"

-- The secure attribute prefix ("alt-", "alt-ctrl-") for one of the game's
-- modified clicks as the player set it (Settings > Modified clicks), or nil.
-- The secure templates put held keys in this order (SecureButton_GetModifierPrefix).
local KEY_ORDER = { "ALT", "CTRL", "SHIFT" }
function Cast.Prefix(action)
    local keys = type(GetModifiedClick) == "function" and GetModifiedClick(action)
    if type(keys) ~= "string" then return nil end
    local held = {}
    for key in string.gmatch(keys, "%a+") do held[key] = true end
    local prefix = ""
    for _, key in ipairs(KEY_ORDER) do
        if held[key] then prefix = prefix .. string.lower(key) .. "-" end
    end
    return prefix ~= "" and prefix or nil
end

-- The game's book casts on you on the self-cast click, but its link and pick-up
-- clicks come first, so a self-cast sharing their keys never casts.
function Cast.SelfPrefix()
    local prefix = Cast.Prefix("SELFCAST")
    if not prefix or prefix == Cast.Prefix("CHATLINK") or prefix == Cast.Prefix("PICKUPACTION") then return nil end
    return prefix
end

-- Player spells cast by id, so lower ranks work too. Pet spells go through
-- /cast, and right click toggles autocast. "type1" alone is an unmodified
-- left click only, so a Shift-click links (Spells.Modified) without casting.
function Cast.Attributes(cell)
    if cell.future or cell.passive then return nil end
    local me = Cast.SelfPrefix()
    if cell.pet then
        local a = { type1 = "macro", macrotext1 = "/cast " .. cell.name }
        if cell.autocast then a.type2, a.macrotext2 = "macro", "/petautocasttoggle " .. cell.name end
        if me then a[me .. "type1"], a[me .. "macrotext1"] = "macro", "/cast [@player] " .. cell.name end
        return a
    end
    if type(cell.spellID) ~= "number" then return nil end
    local a = { type1 = "spell", spell = cell.spellID }
    if me then a[me .. "type1"], a[me .. "unit1"] = "spell", "player" end
    return a
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
