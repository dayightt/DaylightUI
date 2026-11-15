-- The cooldown layout editor's floating card. It sits beside the picked piece's chain
-- and shows its settings in three tabs: Look, Behavior (one heading per moment:
-- ready, on cooldown, usable, buff up or missing) and Group (code name "chain").
-- Rows are ordinary option items (W.CompactRow) that read and write the picked piece
-- through CdmData's checked setters.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Data = ns.CdmData

local Card = {}
ns.CdmCard = Card

-- Wide, with sections in two columns, so it's half as tall as one column and stays
-- clear of the top bar and the tray. 480 still fits beside a group in the middle of
-- the screen at a large UI scale; 540 was too big.
Card.W = 480
Card.PAD = 12
Card.COL_GAP = 18
Card.CONTROL = 108      -- width of a slider or dropdown beside its label
Card.ROW_H = 23
Card.COL = (Card.W - 2 * Card.PAD - Card.COL_GAP) / 2
Card.HEAD_H = 20        -- section heading height
Card.HEAD_GAP = 8       -- space above a heading that isn't first in its column
Card.PLUS_ROOM = 28     -- how far the + buttons reach past a spell (22 px, 6 px out); the card never covers them
Card.GAP = 36           -- distance from the chain's edge, past the + buttons with room to spare
Card.TOP = 110          -- kept clear at the top for the pill and the banner
Card.TABS = { "look", "show", "chain" }
local TAB_TEXT = { look = L["Look"], show = L["Behavior"], chain = L["Group"] }
local SIDE_NAME = { up = L["Hooked above %s"], down = L["Hooked below %s"],
    left = L["Hooked left of %s"], right = L["Hooked right of %s"] }

local PAGE = { id = "cdm.card", scope = "ActionBars" }
local tab = "look"
local ui

local floor, max, min = math.floor, math.max, math.min

local function Ed() return ns.CdmEditor end
local function W() return DUI.Widgets end

-- The picked piece: set, id, piece (nothing when none is picked).
local function picked()
    local set, id = Ed().Set(), Ed().Selected()
    local p = id ~= nil and set.pieces[id]
    if p then return set, id, p end
end

local function changed() Ed().Changed() end

function Card.Tab() return tab end
function Card.SetTab(t)
    for _, k in ipairs(Card.TABS) do
        if k == t then
            tab = t
            if DUI.Sound then DUI.Sound.Play("click") end
            Card.Draw()
            return
        end
    end
end

-- ---------------------------------------------------------------------
-- Rows: option items bound to the picked piece
-- ---------------------------------------------------------------------

-- What a spell's color setting shows before it's set (nil in CdmEffects means these).
-- A bar's text size falls back to its group's.
function Card.Fallback(key, set, id)
    if key == "glowColor" or key == "readyGlowColor" or key == "usableGlowColor" or key == "missingGlowColor"
        or key == "upGlowColor" or key == "clipGlowColor" then
        return { DUI.Style.Accent() }
    end
    if key == "barColor" then
        local m = DUI.Style.GRADIENT_MID
        return { m[1], m[2], m[3] }
    end
    if (key == "backColor" or key == "backGradient") and ns.Cooldowns then return ns.Cooldowns.BackDefault(key) end
    if key == "barGradient" and DUI.Gradients then
        local G = DUI.Gradients
        local lo, hi = G.RGB(G.KeyFor("player"))
        return { lo = lo, hi = hi }
    end
    if key == "activeColor" and ns.CdmEffects then return ns.CdmEffects.ActiveColor(nil) end
    -- Icon text: unset follows the action bars' look (CD.TextLook).
    local Skin = ns.Skin
    if key == "cdNumbers" then return Skin.cooldownNumbers ~= false end
    if key == "cdSize" then return Skin.COOLDOWN_SIZE end
    if key == "countSize" then return Skin.COUNT end
    if key == "countSpot" then return "br" end
    if key == "low" then return false end
    if key == "lowAt" then return ns.Cooldowns.LOW_AT end
    if key == "lowColor" then local c = DUI.Style.INK.BAD; return { c[1], c[2], c[3] } end
    if key == "cdColor" then local c = Skin.LookFor("cdm").cooldownTextColor; return { c[1], c[2], c[3] } end
    if key == "countColor" then local c = Skin.COUNT_COLOR; return { c[1], c[2], c[3] } end
    if key == "keyShown" then return ns.Settings().cdmKeybinds == true end
    if key == "keySize" then return Skin.LookFor("cdm").keybindSize end
    if key == "keySpot" then return "tr" end
    -- Bar text: unset uses the group's text size, in white (CD.BarText).
    if key == "nameSize" or key == "timeSize" then
        return set and id and Data.PieceLook(set, id, "text") or Data.LOOK.text
    end
    if key == "nameColor" or key == "timeColor" then local c = DUI.Style.INK.VALUE; return { c[1], c[2], c[3] } end
end

-- A spell option (glow, on cooldown...) stored flat on the piece.
local function spell(key, item)
    item.key = "cdm.card." .. key
    item.get = function()
        local _, _, p = picked()
        local v = ns.CdmEffects.Get(p, key)
        if v == nil then v = Card.Fallback(key) end
        return v
    end
    item.set = function(v)
        local set, id = picked()
        if id and Data.SetSpellValue(set, id, key, v) then changed() end
    end
    return item
end

-- A look key, either the piece's own (over its chain's) or the whole chain's.
local function look(key, item, whole)
    item.key = "cdm.card." .. (whole and "chain." or "") .. key
    item.get = function()
        local set, id = picked()
        if not id then return nil end
        if not whole then
            if key == "size" then return (Data.Dims(set, id)) end
            local v = Data.PieceLook(set, id, key)
            if v == nil then v = Card.Fallback(key, set, id) end
            return v
        end
        local c, v = set.chains[Data.Root(set, id)], nil
        if type(c) == "table" and type(c.look) == "table" then v = c.look[key] end
        if v == nil then v = Data.LOOK[key] end
        if v == nil then v = Card.Fallback(key) end
        return v
    end
    item.set = function(v)
        local set, id = picked()
        if id and Data.SetLook(set, id, key, v, whole) then changed() end
    end
    return item
end

-- A chain toggle (grow, only in combat...).
local function chain(key, item)
    item.key = "cdm.card.chain." .. key
    item.get = function()
        local set, id = picked()
        if id then return Data.ChainValue(set, id, key) end
    end
    item.set = function(v)
        local set, id = picked()
        if id and Data.SetChainValue(set, id, key, v) then changed() end
    end
    return item
end

-- How a hooked piece sits: align or gap.
local function hook(key, name, item)
    item.key = "cdm.card." .. name
    item.get = function()
        local set, id, p = picked()
        if not id then return nil end
        if key == "align" then return p.align or "center" end
        return tonumber(p.gap) or Data.ChainValue(set, id, "spacing")
    end
    item.set = function(v)
        local set, id = picked()
        if id and Data.SetHookValue(set, id, key, v) then changed() end
    end
    return item
end

local function opt(key) local _, _, p = picked(); return ns.CdmEffects.Get(p, key) end
-- The picked piece's look value: its own, its chain's, or the fallback.
local function lookOf(key)
    local set, id = picked()
    if not id then return nil end
    local v = Data.PieceLook(set, id, key)
    if v == nil then v = Card.Fallback(key, set, id) end
    return v
end

local function isIcon(_, _, p) return p.shape ~= "bar" end
local function isBar(_, _, p) return p.shape == "bar" end
local function hooked(_, _, p) return p.parent ~= nil end
-- A shield spell shown as a bar (Power Word: Shield...) can fill by the shield left.
local function isShield(_, id, p) return p.shape == "bar" and ns.CdmBars ~= nil and ns.CdmBars.IsShield(id) end
-- The same spell as an icon can show its amount where the time was.
local function isShieldIcon(_, id, p) return p.shape ~= "bar" and ns.CdmBars ~= nil and ns.CdmBars.IsShield(id) end
local function always() return true end
-- Shows a buff (CdmOwn.Track says what), alone or with its cooldown.
local function isBuff(_, id, p) return ns.CdmOwn ~= nil and ns.CdmOwn.Track(id, p) ~= nil end
-- Every game spell can pick what it shows, a buff known yet or not: the buff of one
-- picked blind is watched by the spell's own id until a cast teaches the real one.
local function gameSpell(_, id)
    return ns.CdmOwn ~= nil and not (ns.CdmCustom and ns.CdmCustom.Is(id)) and ns.CdmOwn.Entry(id) ~= nil
end
-- A cooldown, or a buff tracked with its cooldown (matches the card's header).
local function isCooldown(_, id, p)
    local t = ns.CdmOwn and ns.CdmOwn.Track(id, p)
    if t then return t ~= "buff" end
    local known = ns.CdmOwn and ns.CdmOwn.Entry(id)
    return not (known and known.aura)
end
-- Shows a buff or debuff, alone or with its cooldown, so the missing rows apply.
local function hasBuff(set, id, p) return isBuff(set, id, p) or not isCooldown(set, id, p) end
-- Shows only its buff. That's the one kind with anything to show or hide while the
-- buff is down; the others show their cooldown.
local function buffOnly(set, id, p) return hasBuff(set, id, p) and not isCooldown(set, id, p) end
-- A Buff only piece while its buff is down: saved as `missing` (grayed icon, empty
-- bar) or `hideMissing`. Neither means nothing shows, except that a shield-filled bar
-- keeps its empty bar and a saved missing glow keeps its icon (Data.PieceBlock).
local function downShows(set, id, p)
    if opt("hideMissing") == true then return false end
    return opt("missing") == true or opt("missingGlow") == true
        or (isShield(set, id, p) and opt("fillBy") ~= "time")
end
-- Something shows while the buff is down, so that moment's rows mean something.
local function shownMissing(set, id, p)
    return hasBuff(set, id, p) and (isCooldown(set, id, p) or downShows(set, id, p))
end
local VISIBILITY = { values = { show = "Show", hide = "Hide" }, order = { "show", "hide" } }
local BUFF_UP = { type = "dropdown", key = "cdm.card.buffUp", label = "Visibility",
    values = VISIBILITY.values, order = VISIBILITY.order,
    desc = "With Show under Buff missing, Hide makes it appear only when you need to cast it, like Battle Shout.",
    get = function() return opt("hideActive") == true and "hide" or "show" end,
    set = function(v)
        local set, id = picked()
        if id and Data.SetSpellValue(set, id, "hideActive", v == "hide") then changed() end
    end }
local BUFF_DOWN = { type = "dropdown", key = "cdm.card.buffDown", label = "Visibility",
    values = VISIBILITY.values, order = VISIBILITY.order,
    desc = "Show keeps it as a grayed icon or an empty bar, so you see what's missing. Hide shows it only while the buff is up, like Power Word: Shield.",
    get = function()
        local set, id, p = picked()
        if id then return downShows(set, id, p) and "show" or "hide" end
    end,
    set = function(v)
        local set, id, p = picked()
        if not id then return end
        local hide = v == "hide"
        -- Hide alone keeps a spell at Buff only (CdmOwn.Picked), so Show has to
        -- set it too, or the spell would fall back to its cooldown.
        if not hide then
            if ns.CdmCustom.CanTrack(id) then Data.SetTrack(set, id, "aura")
            elseif ns.CdmOwn.Track(id, p) then Data.SetSpellValue(set, id, "track", "buff") end
        end
        Data.SetSpellValue(set, id, "hideMissing", hide)
        Data.SetSpellValue(set, id, "missing", not hide)
        changed()
    end }
-- A custom spell with both a cooldown and a buff (Bloodrage) shows one of them
-- (CdmCustom.Track). The game's spells use Track above.
local function canTrack(_, id) return ns.CdmCustom ~= nil and ns.CdmCustom.CanTrack(id) == true end
local OWN_TRACK = { type = "dropdown", key = "cdm.card.ownTrack", label = "What it shows",
    values = { both = "Both", cooldown = "Cooldown", aura = "Buff only" }, order = { "both", "cooldown", "aura" },
    desc = "Both keeps it in its spot: the buff's time while it's up, then the cooldown. Buff only shows it just while the buff is up.",
    get = function()
        local set, id = picked()
        return id and ns.CdmCustom.Track(id, set) or nil
    end,
    set = function(v)
        local set, id = picked()
        if id and Data.SetTrack(set, id, v) then changed() end
    end }
-- The header's word for what the piece shows.
local KIND = { both = L["Cooldown and buff"], cooldown = L["Cooldown"], buff = L["Buff or debuff"] }

-- Track: what a buff spell shows (CdmOwn.Track; unset means its guess).
local function track(item)
    item.key = "cdm.card.track"
    item.get = function()
        local _, id, p = picked()
        if not id then return nil end
        local t = ns.CdmOwn.Track(id, p)
        if t then return t end
        local e = ns.CdmOwn.Entry(id)
        return e and e.aura and "buff" or "cooldown"
    end
    item.set = function(v)
        local set, id = picked()
        if not id then return end
        -- Buff missing's visibility belongs to Buff only, so any other pick clears it.
        if v ~= "buff" then
            Data.SetSpellValue(set, id, "hideMissing", false)
            Data.SetSpellValue(set, id, "missing", false)
        end
        if Data.SetSpellValue(set, id, "track", v) then changed() end
    end
    return item
end
-- A sound row: the game's Cooldown Manager list plus more (Sound.AlertChoices).
-- Plays when the mouse rests on a row and again when it's picked.
local function soundRow(key, label, desc)
    -- A saved sound the list no longer has (the game's Short ones) reads as None.
    return spell(key, { type = "dropdown", label = label, desc = desc, fallback = "none",
        choices = function() return DUI.Sound.AlertChoices() end,
        hover = function(k) DUI.Sound.AlertHover(k) end,
        onPick = function(k) DUI.Sound.AlertSample(k) end })
end
-- Shows its buff at all. A spell set to its cooldown has no buff sound to play.
local function showsBuff(set, id, p)
    if not hasBuff(set, id, p) then return false end
    return not (ns.CdmOwn ~= nil and ns.CdmOwn.Track(id, p) == "cooldown")
end
-- Whether the picked piece's chain has a piece of this shape.
local function chainHas(shape)
    return function(set, id)
        for _, q in ipairs(Data.Subtree(set, Data.Root(set, id))) do
            if (set.pieces[q].shape == "bar") == (shape == "bar") then return true end
        end
        return false
    end
end
local function both(a, b) return function(...) return a(...) and b(...) end end
-- More than one spell in the picked chain. Alone, the group sizes would just repeat
-- its own.
local function several(set, id) return #Data.Subtree(set, Data.Root(set, id)) > 1 end
-- Whether the picked chain has this look value (the Look tab's Whole group).
local function chainLooks(key, value)
    return function(set, id)
        local c = set.chains[Data.Root(set, id)]
        local v = type(c) == "table" and type(c.look) == "table" and c.look[key] or nil
        if v == nil then v = Data.LOOK[key] end
        return v == value
    end
end

local COLOR_MODES = { values = { block = "Group's", solid = "Solid", gradient = "Gradient" },
    order = { "block", "solid", "gradient" } }

-- "Unhook it": free the piece where it is now.
local function unhook()
    local set, id = picked()
    if not id then return end
    local b = Data.Layout(set)[id]
    Data.Unhook(set, id, b and b.x, b and b.y)
    changed()
end

-- Move back / forward: swap places with the spell before or after it.
local function before() local set, id = picked(); return id and (Data.Neighbors(set, id)) or nil end
local function after() local set, id = picked(); return id and select(2, Data.Neighbors(set, id)) or nil end
local function swapWith(other)
    return function()
        local set, id = picked()
        local o = id and other()
        if o and Data.Swap(set, id, o) then changed() end
    end
end

local function hookTitle()
    local set, id, p = picked()
    if not (id and p.parent ~= nil) then return "" end
    return string.format(SIDE_NAME[p.side] or "%s", Ed().SpellName(p.parent) or L["Unknown spell"])
end

local function chainTitle()
    local set, id = picked()
    if not id then return "" end
    local n = #Data.Subtree(set, Data.Root(set, id))
    if n == 1 then return L["Just this spell, for now"] end
    return string.format(L["All %d spells snapped together"], n)
end

-- Each tab's rows, top to bottom: { head = text or fn, show }, { item, show }, or
-- { box = "position", show } (built by the card itself).
Card.ROWS = {
    look = {
        { head = L["Icon"], show = isIcon },
        { show = isIcon, item = look("size", { type = "slider", label = "Size", min = 16, max = 64, step = 1, unit = "px",
            desc = "This icon's own size. Whole group sizes every icon in the group." }) },
        { show = isShieldIcon, item = spell("shieldAmount", { type = "toggle", label = "Show shield amount",
            desc = "How much the shield can still soak, on the icon in place of its time. Its size and color are the cooldown numbers'." }) },
        { head = L["Swipe"], show = isIcon },
        { show = both(isIcon, isCooldown), item = spell("noSwipe", { type = "toggle", label = "Hide on cooldown",
            desc = "No dark sweep over the icon while the spell is on cooldown." }) },
        { show = function(...) return isIcon(...) and isCooldown(...) and opt("noSwipe") ~= true end,
          item = spell("noGcd", { type = "toggle", label = "Hide on global cooldown",
            desc = "No swipe for the short global cooldown after every cast, only for the spell's own." }) },
        { show = function(...) return isIcon(...) and opt("noSwipe") ~= true end,
          item = spell("reverse", { type = "toggle", label = "Reverse",
            desc = "The dark part shrinks away instead of filling in." }) },
        { show = both(isIcon, hasBuff), item = spell("noDurationSwipe", { type = "toggle", label = "Hide while buff is up",
            desc = "No sweep counting the buff down while it's up. Its time stays." }) },
        { head = L["Cooldown numbers"], show = isIcon },
        { show = isIcon, item = look("cdNumbers", { type = "toggle", label = "Show" }) },
        { show = function(...) return isIcon(...) and lookOf("cdNumbers") ~= false end,
          item = look("cdSize", { type = "slider", label = "Size", min = 8, max = 24, step = 1 }) },
        { show = function(...) return isIcon(...) and lookOf("cdNumbers") ~= false end,
          item = look("cdColor", { type = "color", label = "Color" }) },
        { show = function(...) return isIcon(...) and lookOf("cdNumbers") ~= false end,
          item = look("low", { type = "toggle", label = "Color when almost ready",
            desc = "The numbers change color for the last seconds of the cooldown." }) },
        { show = function(...) return isIcon(...) and lookOf("cdNumbers") ~= false and lookOf("low") == true end,
          item = look("lowAt", { type = "slider", label = "Almost ready at", min = 1, max = 10, step = 1,
            desc = "Seconds left on the cooldown when the numbers change color." }) },
        { show = function(...) return isIcon(...) and lookOf("cdNumbers") ~= false and lookOf("low") == true end,
          item = look("lowColor", { type = "color", label = "Almost ready color" }) },
        { head = L["Stacks and charges"], show = isIcon },
        { show = isIcon, item = look("countSize", { type = "slider", label = "Size", min = 8, max = 20, step = 1 }) },
        { show = isIcon, item = look("countColor", { type = "color", label = "Color" }) },
        { show = isIcon, item = look("countSpot", { type = "dropdown", label = "Position",
            values = { br = "Bottom right", tr = "Top right", tl = "Top left", center = "Middle", bottom = "Bottom" },
            order = { "br", "tr", "tl", "center", "bottom" } }) },
        { head = L["Keybind"], show = isIcon },
        { show = isIcon, item = look("keyShown", { type = "toggle", label = "Show",
            desc = "The key that casts this spell, read from your action bars." }) },
        { show = function(...) return isIcon(...) and lookOf("keyShown") == true end,
          item = look("keySize", { type = "slider", label = "Size", min = 8, max = 20, step = 1 }) },
        { show = function(...) return isIcon(...) and lookOf("keyShown") == true end,
          item = look("keySpot", { type = "dropdown", label = "Position",
            values = { tr = "Top right", tl = "Top left", br = "Bottom right", center = "Middle", bottom = "Bottom" },
            order = { "tr", "tl", "br", "center", "bottom" } }) },
        { head = L["Bar"], show = isBar },
        { show = isBar, item = look("width", { type = "slider", label = "Width", min = 60, max = 400, step = 1, unit = "px" }) },
        { show = isBar, item = look("height", { type = "slider", label = "Height", min = 10, max = 40, step = 1, unit = "px" }) },
        { show = isBar, item = look("icon", { type = "toggle", label = "Show icon" }) },
        { show = isShield, item = spell("fillBy", { type = "dropdown", label = "Fills by",
            desc = "A shield: the bar empties as it soaks damage, with the amount left on it. Or by its time, like any buff.",
            values = { shield = "Shield left", time = "Time left" }, order = { "shield", "time" } }) },
        { show = function(...) return isShield(...) and opt("fillBy") ~= "time" end,
          item = spell("shieldAmount", { type = "toggle", label = "Show shield amount",
            desc = "How much the shield can still soak, at the bar's right end." }) },
        { show = both(isBar, isCooldown), item = spell("chargeLines", { type = "toggle", label = "Charge lines",
            desc = "A spell with charges: the bar is cut into one piece per charge." }) },
        { show = isBar, item = spell("barMode", { type = "dropdown", label = "Fill",
            values = COLOR_MODES.values, order = COLOR_MODES.order }) },
        { show = function(...) return isBar(...) and opt("barMode") == "solid" end,
          item = spell("barColor", { type = "color", label = "Fill color" }) },
        { show = function(...) return isBar(...) and opt("barMode") == "gradient" end,
          item = spell("barGradient", { type = "gradient", label = "Fill" }) },
        { show = isBar, item = spell("backMode", { type = "dropdown", label = "Background",
            values = COLOR_MODES.values, order = COLOR_MODES.order }) },
        { show = function(...) return isBar(...) and opt("backMode") == "solid" end,
          item = spell("backColor", { type = "color", alpha = true, label = "Background color" }) },
        { show = function(...) return isBar(...) and opt("backMode") == "gradient" end,
          item = spell("backGradient", { type = "gradient", label = "Background" }) },
        { head = L["Name"], show = isBar },
        { show = isBar, item = spell("showName", { type = "toggle", label = "Show" }) },
        { show = function(...) return isBar(...) and opt("showName") ~= false end,
          item = spell("nameAlign", { type = "dropdown", label = "Position",
            values = { left = "Left", center = "Center" }, order = { "left", "center" } }) },
        { show = function(...) return isBar(...) and opt("showName") ~= false end,
          item = look("nameSize", { type = "slider", label = "Size", min = 8, max = 20, step = 1,
            desc = "This bar's own name size. Text size, under Whole group, sizes every bar's." }) },
        { show = function(...) return isBar(...) and opt("showName") ~= false end,
          item = look("nameColor", { type = "color", label = "Color" }) },
        { head = L["Time"], show = isBar },
        { show = isBar, item = look("time", { type = "toggle", label = "Show" }) },
        { show = function(...) return isBar(...) and lookOf("time") ~= false end,
          item = look("timeSize", { type = "slider", label = "Size", min = 8, max = 20, step = 1 }) },
        { show = function(...) return isBar(...) and lookOf("time") ~= false end,
          item = look("timeColor", { type = "color", label = "Color" }) },
        { head = L["Whole group"], show = function(set, id) return several(set, id) or chainHas("bar")(set, id) end },
        { show = both(chainHas("icon"), several), item = look("size", { type = "slider", label = "Icon size",
            min = 16, max = 64, step = 1, unit = "px" }, true) },
        { show = both(chainHas("bar"), several), item = look("width", { type = "slider", label = "Bar width",
            min = 60, max = 400, step = 1, unit = "px" }, true) },
        { show = both(chainHas("bar"), several), item = look("height", { type = "slider", label = "Bar height",
            min = 10, max = 40, step = 1, unit = "px" }, true) },
        { show = chainHas("bar"), item = look("color", { type = "dropdown", label = "Bar color",
            values = { class = "Class", gradient = "Daylight", spell = "Per spell" },
            order = { "class", "gradient", "spell" },
            desc = "Class uses your class's pair from the Gradients page. Daylight is the Daylight UI gradient." }, true) },
        { show = chainHas("bar"), item = look("back", { type = "dropdown", label = "Background",
            values = { dark = "Dark", solid = "Solid", gradient = "Gradient" },
            order = { "dark", "solid", "gradient" },
            desc = "The empty part of every bar in the group. A spell's own background wins." }, true) },
        { show = both(chainHas("bar"), chainLooks("back", "solid")),
          item = look("backColor", { type = "color", alpha = true, label = "Background color" }, true) },
        { show = both(chainHas("bar"), chainLooks("back", "gradient")),
          item = look("backGradient", { type = "gradient", label = "Background" }, true) },
        { show = both(chainHas("bar"), several), item = look("icon", { type = "toggle", label = "Icons on bars" }, true) },
        { show = chainHas("bar"), item = look("text", { type = "slider", label = "Text size", min = 8, max = 16, step = 1 }, true) },
        { show = both(chainHas("bar"), several), item = look("time", { type = "toggle", label = "Time on bars" }, true) },
    },
    show = {
        { show = gameSpell, item = track({ type = "dropdown", label = "What it shows",
            values = { both = "Both", cooldown = "Cooldown", buff = "Buff only" },
            order = { "both", "cooldown", "buff" },
            desc = "Both keeps it in its spot: the buff's time while it's up, then the cooldown. Buff only shows it just while the buff is up." }) },
        { show = canTrack, item = OWN_TRACK },
        { head = L["When ready"], show = isCooldown },
        { show = isCooldown, item = spell("onReady", { type = "dropdown", label = "Visibility",
            values = { show = "Show", fade = "Fade", hide = "Hide" }, order = { "show", "fade", "hide" },
            desc = "Hide shows the spell only while it's on cooldown. It keeps its gap: the other spells don't move." }) },
        { show = isCooldown, item = spell("readyGlow", { type = "toggle", label = "Glow",
            desc = "Glows while the spell is off cooldown." }) },
        { show = function(...) return isCooldown(...) and opt("readyGlow") == true end,
          item = spell("readyGlowColor", { type = "color", label = "Glow color" }) },
        { show = isCooldown, item = soundRow("readySound", "Sound",
            "Plays once as the spell comes off cooldown, never on the global cooldown.") },
        { head = L["On cooldown"], show = isCooldown },
        { show = isCooldown, item = spell("onCd", { type = "dropdown", label = "Visibility",
            values = { show = "Show", fade = "Fade", hide = "Hide" }, order = { "show", "fade", "hide" },
            desc = "Hide keeps its gap: the other spells don't move." }) },
        { show = function(set, id, p)
              return isCooldown(set, id, p)
                  and (opt("onCd") == "fade" or opt("onReady") == "fade" or opt("onUnusable") == "fade" or opt("onShort") == "fade")
          end,
          item = spell("cdAlpha", { type = "slider", label = "Fade to", min = 0, max = 1, step = 0.05, unit = "%",
            desc = "How see-through a spell set to Fade gets." }) },
        { show = both(isIcon, isCooldown), item = spell("desat", { type = "dropdown", label = "Gray out",
            values = { game = "Default", grey = "Gray", color = "Stay colored" }, order = { "game", "grey", "color" } }) },
        -- Usable applies to cooldowns only; Buff only has nothing to be usable.
        -- WoW Forever fires no proc alerts, so there's no proc glow row (its code
        -- stays idle in CdmEffects). Turned on for Slice and Dice, nothing glowed.
        { head = L["Usable"], show = isCooldown },
        { show = isCooldown, item = spell("onUnusable", { type = "dropdown", label = "Not usable",
            values = { show = "Show", fade = "Fade", hide = "Hide" }, order = { "show", "fade", "hide" },
            desc = "While it's off cooldown but you can't cast it: Overpower before a dodge, Riposte before a parry, Execute on a healthy target. Show leaves it dimmed. Hide keeps its gap: the other spells don't move." }) },
        { show = isCooldown, item = spell("onShort", { type = "dropdown", label = "Short of power",
            values = { show = "Show", fade = "Fade", hide = "Hide" }, order = { "show", "fade", "hide" },
            desc = "While it's off cooldown but you lack the energy, rage or mana for it: Kick shows only once you can afford it. Show tints it blue. Hide keeps its gap: the other spells don't move." }) },
        { show = isCooldown, item = spell("usableGlow", { type = "toggle", label = "Glow when usable",
            desc = "Glows while you can cast it and it's off cooldown: Revenge after a block, dodge or parry, Overpower after a dodge, Execute on a low target." }) },
        { show = function(...) return isCooldown(...) and opt("usableGlow") == true end,
          item = spell("usableGlowColor", { type = "color", label = "Usable glow color" }) },
        { show = isCooldown, item = soundRow("usableSound", "Sound when usable",
            "Plays once as you become able to cast it: Revenge after a block, Overpower after a dodge, Execute on a low target. Rage or mana coming back doesn't count.") },
        { head = L["Form or stance"], show = function(...) return isCooldown(...) and ns.CdmEffects.FormsOf() ~= nil end },
        { head = L["Buff up"], show = hasBuff },
        { show = hasBuff, item = BUFF_UP },
        { show = function(...) return showsBuff(...) and opt("hideActive") ~= true end,
          item = spell("upGlow", { type = "toggle", label = "Glow",
            desc = "Glows while the buff is up: Clearcasting, Nightfall." }) },
        { show = function(...) return showsBuff(...) and opt("hideActive") ~= true and opt("upGlow") == true end,
          item = spell("upGlowColor", { type = "color", label = "Glow color" }) },
        { show = function(...) return showsBuff(...) and opt("hideActive") ~= true end,
          item = spell("clipGlow", { type = "toggle", label = "Glow to recast",
            desc = "Glows when it's time to cast it again: your next cast would land just as it runs out. Cast any sooner and a damage over time spell loses the ticks it had left." }) },
        { show = function(...) return showsBuff(...) and opt("hideActive") ~= true and opt("clipGlow") == true end,
          item = spell("clipGlowColor", { type = "color", label = "Recast color" }) },
        { show = showsBuff, item = soundRow("buffSound", "Sound",
            "Plays once as the buff lands, like Clearcasting or Nightfall.") },
        { show = function(...) return isIcon(...) and hasBuff(...) and opt("noDurationSwipe") ~= true end,
          item = spell("activeGlow", { type = "toggle", label = "Highlight",
            desc = "The colored sweep over the icon while its buff is up. When off, only the timer shows." }) },
        { show = function(...) return isIcon(...) and hasBuff(...) and opt("activeGlow") ~= false
              and opt("noDurationSwipe") ~= true end,
          item = spell("activeColor", { type = "color", alpha = true, label = "Highlight color" }) },
        { head = L["Buff missing"], show = hasBuff },
        { show = buffOnly, item = BUFF_DOWN },
        { show = showsBuff, item = soundRow("buffEndSound", "Sound",
            "Plays once as the buff runs out or is used up, like a Seal, so you can hear it's time to cast it again.") },
        { show = shownMissing, item = spell("missingGlow", { type = "toggle", label = "Glow",
            desc = "Glows while the buff is down, to remind you to cast it." }) },
        { show = function(...) return shownMissing(...) and opt("missingGlow") == true end,
          item = spell("missingGlowColor", { type = "color", label = "Glow color" }) },
        { show = function(...) return isBar(...) and buffOnly(...) and opt("missing") == true end,
          item = spell("inactiveFlash", { type = "toggle", label = "Flash",
            desc = "The empty bar pulses while the buff is down." }) },
    },
    chain = {
        { head = chainTitle, show = always },
        { box = "position", show = always },
        { show = always, item = chain("spacing", { type = "slider", label = "Spacing", min = 0, max = 16, step = 1, unit = "px" }) },
        { show = always, item = chain("grow", { type = "dropdown", label = "Grow from",
            values = { start = "Start", center = "Middle", ["end"] = "End" }, order = { "start", "center", "end" },
            desc = "Which end of the group stays put when a spell in it hides." }) },
        { show = always, item = chain("collapse", { type = "toggle", label = "Slide over when a buff drops",
            desc = "When a buff runs out, the spells after it slide over to fill its spot. When off, every spell keeps its place. A spell set to Keep its spot (Behavior tab) keeps it either way." }) },
        -- Side by side as halves, always both in a group of several, with the one
        -- that has nowhere to go grayed. Hiding one made the other jump around.
        { show = several, half = 1,
          item = { type = "button", key = "cdm.card.back", label = "Swap with the one before", text = "Move back",
            desc = "Trades places with the spell before it in the group. Each keeps its own look and options.",
            func = swapWith(before), disabled = function() return before() == nil end } },
        { show = several, half = 2,
          item = { type = "button", key = "cdm.card.forward", label = "Swap with the one after", text = "Move forward",
            desc = "Trades places with the spell after it in the group. Each keeps its own look and options.",
            func = swapWith(after), disabled = function() return after() == nil end } },
        { head = L["When to show"], show = always },
        { show = always, item = chain("combat", { type = "toggle", label = "Only in combat",
            desc = "The whole group shows only during a fight." }) },
        { show = always, item = chain("group", { type = "toggle", label = "Only in a group",
            desc = "The whole group shows only in a party or raid." }) },
        { show = always, item = chain("target", { type = "toggle", label = "Only with a target" }) },
        { show = always, item = chain("mounted", { type = "toggle", label = "Hide while mounted" }) },
        { show = always, item = chain("where", { type = "dropdown", label = "Show in",
            values = { any = "Everywhere", instance = "Instances", world = "Open world" },
            order = { "any", "instance", "world" },
            desc = "Instances are dungeons, raids and battlegrounds." }) },
        { head = hookTitle, show = hooked },
        { show = function(...) local _, _, p = ...; return hooked(...) and (p.side == "up" or p.side == "down") end,
          item = hook("align", "alignAcross", { type = "dropdown", label = "Line up",
            values = { start = "Left edges", center = "Middle", ["end"] = "Right edges" }, order = { "start", "center", "end" } }) },
        { show = function(...) local _, _, p = ...; return hooked(...) and (p.side == "left" or p.side == "right") end,
          item = hook("align", "alignDown", { type = "dropdown", label = "Line up",
            values = { start = "Top edges", center = "Middle", ["end"] = "Bottom edges" }, order = { "start", "center", "end" } }) },
        { show = hooked, item = hook("gap", "gap", { type = "slider", label = "Gap", min = 0, max = 16, step = 1, unit = "px" }) },
        { show = hooked, item = { type = "button", key = "cdm.card.unhook", label = "Free it", text = "Unhook it",
            desc = "Frees it right where it is, with everything hanging off it.", func = unhook } },
    },
}

-- Show in (CdmEffects.FORMS): one switch per form, stance or stealth of the class,
-- under its heading, on by default. Off leaves the spell out in that form.
do
    local rows, at = Card.ROWS.show, nil
    for i, r in ipairs(rows) do if r.head == L["Form or stance"] then at = i end end
    local Fx = ns.CdmEffects
    for _, class in ipairs({ "DRUID", "WARRIOR", "ROGUE" }) do
        for _, f in ipairs(Fx.FORMS[class]) do
            local key = "hideIn" .. f.key
            at = at + 1
            table.insert(rows, at, {
                show = function(...) return isCooldown(...) and Fx.FormsOf() == Fx.FORMS[class] end,
                item = { type = "toggle", key = "cdm.card." .. key, label = f.name,
                    desc = "Off: the spell hides while you're in it, and the group's Slide over closes its gap.",
                    get = function() return opt(key) ~= true end,
                    set = function(v)
                        local set, id = picked()
                        if id and Data.SetSpellValue(set, id, key, v ~= true) then changed() end
                    end } })
        end
    end
end

-- Not on a registered page, so listed here for the translation key set.
ns.LOOSE_ITEMS = ns.LOOSE_ITEMS or {}
for _, t in ipairs(Card.TABS) do
    for _, r in ipairs(Card.ROWS[t]) do
        if r.item then table.insert(ns.LOOSE_ITEMS, r.item) end
    end
end

-- ---------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------

Card.NUDGE_H = 22
Card.REMOVE_H = 26

-- The chain's position: unlock mode's nudges (Left, Up, Down, Right) and X / Y boxes
-- (the chain's middle relative to screen center, same as unlock mode).
local function buildPosition(f, inner)
    local w = W()
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(inner, 2 * Card.NUDGE_H + 6)
    local bw = (inner - 3 * 4) / 4
    local function nudge(text, dx, dy, i)
        local b = w.Button(box, text, Card.NUDGE_H)
        b:SetWidth(bw)
        b:SetPoint("TOPLEFT", box, "TOPLEFT", (i - 1) * (bw + 4), 0)
        b:SetScript("OnClick", function() Ed().Nudge(dx, dy) end)
        return b
    end
    box.left = nudge(L["Left"], -1, 0, 1)
    box.up = nudge(L["Up"], 0, 1, 2)
    box.down = nudge(L["Down"], 0, -1, 3)
    box.right = nudge(L["Right"], 1, 0, 4)

    local function typed()
        local x, y = tonumber(box.x:GetText()), tonumber(box.y:GetText())
        if x and y then Ed().MoveTo(x, y) end
        box.x:ClearFocus()
        box.y:ClearFocus()
        box.Refresh()
    end
    local half = (inner - 8) / 2
    local function field(label, i)
        local fs = w.Font(box, w.BODY, DUI.Style.SIZE.small, DUI.Style.INK.LABEL, "LEFT")
        fs:SetText(label)
        fs:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", (i - 1) * (half + 8), 6)
        local e = w.Input(box, { height = Card.NUDGE_H, justify = "CENTER" })
        e:SetWidth(half - 18)
        e:SetPoint("BOTTOMRIGHT", box, "BOTTOMLEFT", (i - 1) * (half + 8) + half, 0)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); box.Refresh() end)
        e:SetScript("OnEnterPressed", typed)
        return e
    end
    box.x = field("X", 1)
    box.y = field("Y", 2)
    function box.Refresh()
        local x, y = Ed().Spot()
        if not x then return end
        box.x:SetText(string.format("%d", x))
        box.y:SetText(string.format("%d", y))
    end
    return box
end

function Card.Position() return ui and ui.position end

-- A section heading in Stack:Section's look: small upper case in the accent over a
-- faint line. Its text is set when it shows.
local function sectionHead(f, width)
    local h = CreateFrame("Frame", nil, f)
    h:SetSize(width, Card.HEAD_H)
    h.text = DUI.Style.Text(h, DUI.Style.SIZE.small, "LEFT")
    h.text:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 5)
    h.text:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.text:SetWordWrap(false)
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line:SetColorTexture(1, 1, 1, 0.06)
    h.line:SetHeight(1)
    h.line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    function h.Set(text)
        h.text:SetText(string.upper(text or ""))
        DUI.Style.InkText(h.text, "pop")
    end
    return h
end

-- A button item drawn as a plain button of the given width. Its label and desc go
-- in the tooltip. disabled() grays it.
local function buttonRow(f, item, width)
    local w = W()
    local Options = DUI.Options
    local b = w.Button(f, Options.Text(item.text or item.label), 24)
    b:SetWidth(width)
    b:SetScript("OnClick", function() item.func() end)
    b:HookScript("OnEnter", function(self) w.Tooltip(self, Options.Label(item), Options.Text(item.desc)) end)
    b:HookScript("OnLeave", function() w.HideTooltip() end)
    function b.Refresh() b.SetOff(item.disabled ~= nil and item.disabled() == true) end
    return b
end

local function build()
    local o = Ed().Overlay()
    if not o then return end
    ui = { tabs = {} }
    local w = W()
    local inner = Card.W - 2 * Card.PAD
    local f = CreateFrame("Frame", nil, o)
    f:SetFrameLevel(o:GetFrameLevel() + 35)
    f:SetWidth(Card.W)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)    -- so the wheel doesn't scroll the tray from here
    f:SetScript("OnMouseWheel", function() end)
    DUI.Style.Shell(f, {})
    f:Hide()
    ui.card = f

    -- Header: icon, name, kind, then the Icon | Bar chips and the close button on
    -- the right (the X closes only the card).
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(30, 30)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD, -Card.PAD)
    DUI.Style.CropIcon(f.icon)
    f.close = w.Close(f, function() Ed().Select(nil) end)
    f.close:SetPoint("RIGHT", f, "TOPRIGHT", -Card.PAD + 4, -(Card.PAD + 15))
    local function shapeChip(text, shape)
        local b = w.Chip(f, text)
        b:SetScript("OnClick", function()
            local set, id = picked()
            if id and Data.SetShape(set, id, shape) then changed() end
        end)
        b.FitWidth()
        return b
    end
    f.asBar = shapeChip(L["Bar"], "bar")
    f.asBar:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
    f.asIcon = shapeChip(L["Icon"], "icon")
    f.asIcon:SetPoint("RIGHT", f.asBar, "LEFT", -6, 0)
    f.name = DUI.Style.Text(f, DUI.Style.SIZE.head, "LEFT")
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -1)
    f.name:SetPoint("RIGHT", f.asIcon, "LEFT", -10, 0)
    f.name:SetWordWrap(false)
    f.kind = w.Font(f, w.BODY, DUI.Style.SIZE.small, DUI.Style.INK.LABEL, "LEFT")
    f.kind:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, 1)

    -- Removing the spell gets its own button in the warning color, placed under the
    -- rows by Card.Draw.
    f.remove = w.Button(f, L["Remove from layout"], Card.REMOVE_H)
    f.remove:SetWidth(inner)
    w.TextColor(f.remove.text, w.COLORS.warn)
    f.remove:SetScript("OnClick", function() Ed().Remove(Ed().Selected()) end)
    f.remove:HookScript("OnEnter", function(self)
        w.Tooltip(self, L["Remove from layout"], L["Takes the spell out of the layout; it goes back to the tray. Delete does too."])
    end)
    f.remove:HookScript("OnLeave", function() w.HideTooltip() end)
    -- On the Group tab: remove the whole group, with a confirm click.
    f.removeGroup = w.Button(f, L["Remove group from layout"], Card.REMOVE_H)
    f.removeGroup:SetWidth(inner)
    w.Confirm(f.removeGroup, L["Remove group from layout"], function() Ed().RemoveChain(Ed().Selected()) end)
    w.TextColor(f.removeGroup.text, w.COLORS.warn)
    f.removeGroup:HookScript("OnEnter", function(self)
        w.Tooltip(self, L["Remove group from layout"], L["Takes every spell of this group out of the layout; they go back to the tray."])
    end)
    f.removeGroup:HookScript("OnLeave", function() w.HideTooltip() end)
    f.removeGroup:Hide()

    -- Tabs, with a faint rule under them.
    local tabY = -(Card.PAD + 38)
    local left
    for _, t in ipairs(Card.TABS) do
        local b = w.Tab(f, TAB_TEXT[t])
        b.FitWidth()
        if left then b:SetPoint("LEFT", left, "RIGHT", 4, 0)
        else b:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD - 4, tabY) end
        b:SetScript("OnClick", function() if tab ~= t then Card.SetTab(t) end end)
        ui.tabs[t] = b
        left = b
    end
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetColorTexture(1, 1, 1, 0.06)
    f.rule:SetHeight(1)
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD, tabY - w.TAB_H)
    f.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Card.PAD, tabY - w.TAB_H)
    -- A faint line between the two columns, a touch brighter than the rule so it
    -- reads at a glance. stackRows sizes it to the taller column.
    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetColorTexture(1, 1, 1, 0.1)
    f.divider:SetWidth(1)

    -- Rows are made once, one column wide (a half row is half of that).
    ui.top = Card.PAD + 38 + w.TAB_H + 6
    local col = Card.COL
    for _, t in ipairs(Card.TABS) do
        for _, r in ipairs(Card.ROWS[t]) do
            if r.head then
                r.frame = sectionHead(f, col)
                r.height = Card.HEAD_H
            elseif r.box == "position" then
                r.frame = buildPosition(f, col)
                r.height = r.frame:GetHeight() + 6
                ui.position = r.frame
            elseif r.item.type == "button" then
                r.frame = buttonRow(f, r.item, r.half and (col - 6) / 2 or col)
                r.height = r.frame:GetHeight() + 4
            else
                r.frame = w.CompactRow(f, PAGE, r.item, col, { inline = true, control = Card.CONTROL, height = Card.ROW_H })
                r.height = r.frame.height
            end
            r.frame:Hide()
        end
    end
end

-- The open tab's sections: a heading (when shown) and the rows under it that apply
-- now. A heading with no rows under it is left out.
local function sections(set, id, p)
    local out, cur = {}, nil
    for _, r in ipairs(Card.ROWS[tab]) do
        if r.head then
            cur = { head = r.show(set, id, p) == true and r or nil, rows = {} }
            out[#out + 1] = cur
        elseif r.show(set, id, p) == true then
            if not cur then
                cur = { rows = {} }
                out[#out + 1] = cur
            end
            cur.rows[#cur.rows + 1] = r
        end
    end
    local kept = {}
    for _, s in ipairs(out) do if #s.rows > 0 then kept[#kept + 1] = s end end
    return kept
end

-- A section's height. A second half row sits beside the first.
local function sectionHeight(s, first)
    local h = s.head and (Card.HEAD_H + 4 + (first and 0 or Card.HEAD_GAP)) or (first and 0 or Card.HEAD_GAP)
    for i, r in ipairs(s.rows) do
        if not (r.half == 2 and s.rows[i - 1] and s.rows[i - 1].half == 1) then h = h + r.height + 2 end
    end
    return h
end

-- Lays the open tab's sections out in two columns, in order, filling the left to
-- about half. Returns how far down the rows reach from the card's top.
local function stackRows(set, id, p)
    local list = sections(set, id, p)
    -- Only rows leaving the card are hidden. Every change redraws it (each step of a
    -- Size slider), and hiding a slider mid-drag drops it, so a row that stays on
    -- the card is never hidden and shown again.
    local keep = {}
    for _, s in ipairs(list) do
        if s.head then keep[s.head.frame] = true end
        for _, r in ipairs(s.rows) do keep[r.frame] = true end
    end
    for _, t in ipairs(Card.TABS) do
        for _, r in ipairs(Card.ROWS[t]) do
            if not keep[r.frame] then r.frame:Hide() end
        end
    end
    -- Where the right column starts: the split that makes the taller column shortest.
    local split, best = #list + 1, math.huge
    for k = 2, #list + 1 do
        local a, b = 0, 0
        for i, s in ipairs(list) do
            if i < k then a = a + sectionHeight(s, i == 1) else b = b + sectionHeight(s, i == k) end
        end
        if max(a, b) < best then split, best = k, max(a, b) end
    end
    local used = { 0, 0 }
    for i, s in ipairs(list) do
        local col = i < split and 1 or 2
        local first = used[col] == 0
        local x = Card.PAD + (col - 1) * (Card.COL + Card.COL_GAP)
        local y = -ui.top - used[col] - (first and 0 or Card.HEAD_GAP)
        if s.head then
            local h = s.head.frame
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", ui.card, "TOPLEFT", x, y)
            h.Set(type(s.head.head) == "function" and s.head.head() or s.head.head)
            h:Show()
            y = y - Card.HEAD_H - 4
        end
        for j, r in ipairs(s.rows) do
            local beside = r.half == 2 and s.rows[j - 1] and s.rows[j - 1].half == 1
            local region = r.frame
            region:ClearAllPoints()
            if beside then
                region:SetPoint("TOPLEFT", ui.card, "TOPLEFT", x + (Card.COL + 6) / 2, y + r.height + 2)
            else
                region:SetPoint("TOPLEFT", ui.card, "TOPLEFT", x, y)
                y = y - r.height - 2
            end
            region.Refresh()
            region:Show()
        end
        used[col] = used[col] + sectionHeight(s, first)
    end
    local d = ui.card.divider
    d:ClearAllPoints()
    d:SetPoint("TOP", ui.card, "TOPLEFT", Card.PAD + Card.COL + Card.COL_GAP / 2, -ui.top)
    d:SetHeight(max(1, max(used[1], used[2])))
    d:SetShown(used[2] > 0)
    return ui.top + math.max(used[1], used[2])
end

local function moveTo(x, y)
    ui.pos = { x, y }
    ui.card:ClearAllPoints()
    ui.card:SetPoint("TOPLEFT", Ed().Overlay(), "CENTER", x, y)
end

-- True while the mouse is holding something on the card (a slider being dragged).
local function held()
    return ui.card:IsMouseOver() and type(IsMouseButtonDown) == "function" and IsMouseButtonDown("LeftButton") == true
end

local place

-- Once the mouse is released, the card settles where it should be.
local function settleOnRelease()
    ui.card:SetScript("OnUpdate", function(self)
        if held() then return end
        self:SetScript("OnUpdate", nil)
        local set, id = picked()
        if id and self:IsShown() then place(set, id) end
    end)
end

-- Places the card beside the picked chain, centered on it: to the right, or the left
-- when there's no room, kept on screen and under the pill. Glides when it moves. For
-- the same piece it stays put while it's clear of the chain, fully on screen, and the
-- chain's first piece hasn't moved, so a slider on it (bar width) stays under the
-- mouse. If the chain grows under it, it waits for the mouse to be released.
place = function(set, id)
    local boxes = Data.Layout(set)
    local root = Data.Root(set, id)
    local l, r, t, bottom
    for _, q in ipairs(Data.Subtree(set, root)) do
        local b = boxes[q]
        if b then
            l = l and min(l, b.x) or b.x
            r = r and max(r, b.x + b.w) or b.x + b.w
            t = t and max(t, b.y) or b.y
            bottom = bottom and min(bottom, b.y - b.h) or b.y - b.h
        end
    end
    if not l then return end
    local w, h = Card.W, ui.card:GetHeight()
    local rb = boxes[root]
    local anchor = rb and (rb.x .. "," .. rb.y) or ""
    local from = ui.pos
    local sw, sh = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    if from and ui.card:IsShown() and ui.placedFor == id and ui.anchor == anchor then
        local g = Card.PLUS_ROOM   -- keep the + buttons clickable
        local clear = from[1] >= r + g or from[1] + w <= l - g or from[2] - h >= t + g or from[2] <= bottom - g
        -- A taller tab (Group) can push the bottom off screen, so then it moves up
        -- like any other re-place.
        local fits = from[2] - h >= -sh + 8
        if clear and fits then return end
        if held() then
            settleOnRelease()
            return
        end
    end
    ui.placedFor, ui.anchor = id, anchor
    -- Vertically centered on the chain, pulled in at the screen's edge.
    local y = (t + bottom) / 2 + h / 2
    local x = r + Card.GAP
    if x + w > sw - 8 then x = l - Card.GAP - w end
    if x < -sw + 8 then
        -- No room on either side (a group in the middle at a large scale): go
        -- under the group, else over it, so it never covers it.
        x = (l + r) / 2 - w / 2
        if bottom - Card.GAP - h >= -sh + 8 then y = bottom - Card.GAP
        elseif t + Card.GAP + h <= sh - Card.TOP then y = t + Card.GAP + h
        elseif sw - r > l + sw then x = sw - 8 - w   -- no room anywhere: take the roomier side
        else x = -sw + 8 end
    end
    x = floor(max(-sw + 8, min(x, sw - 8 - w)) + 0.5)
    y = floor(max(-sh + 8 + h, min(y, sh - Card.TOP)) + 0.5)
    if not (from and ui.card:IsShown()) or (from[1] == x and from[2] == y) then
        DUI.Motion.Tween("cdmCard", 1, 1, 0, function() end)
        moveTo(x, y)
        return
    end
    local fx, fy = from[1], from[2]
    DUI.Motion.Tween("cdmCard", 0, 1, DUI.Motion.FAST, function(k)
        moveTo(fx + (x - fx) * k, fy + (y - fy) * k)
    end)
end

function Card.Hide()
    if ui then ui.card:Hide() end
end

function Card.Shown() return ui ~= nil and ui.card:IsShown() end
function Card.Frame() return ui and ui.card end

-- Draws everything for the picked piece. Hidden with nothing picked, during a drag,
-- or while the Icon/Bar chooser is up. A + waiting for a spell eases it away, since it
-- would lie over the tray you're picking from.
function Card.Draw()
    if not ui then build() end
    if not ui then return end
    local set, id, p = picked()
    local E = Ed()
    if not (id and E.IsOpen() and not E.Dragging() and not E.Pending()) then
        ui.card:Hide()
        return
    end
    local f = ui.card
    if E.Attach() then
        DUI.Motion.AlphaTo(f, 0, DUI.Motion.FAST, true)
        return
    end
    f.icon:SetTexture(E.SpellTexture(id))
    f.name:SetText(E.SpellName(id) or L["Unknown spell"])
    local known = ns.CdmOwn and ns.CdmOwn.Entry(id)
    local t = ns.CdmOwn and ns.CdmOwn.Track(id, p)
    f.kind:SetText(t and KIND[t] or known and known.aura and L["Buff or debuff"] or L["Cooldown"])
    f.asIcon.SetOn(p.shape ~= "bar")
    f.asBar.SetOn(p.shape == "bar")
    for t, b in pairs(ui.tabs) do b.Pick(t == tab, f:IsShown()) end
    local rows = stackRows(set, id, p)
    -- The Group tab's button removes the whole group; the others remove the spell.
    local groupTab = tab == "chain"
    local bottom = groupTab and f.removeGroup or f.remove
    f.remove:SetShown(not groupTab)
    if groupTab and not f.removeGroup:IsShown() and f.removeGroup.Disarm then f.removeGroup.Disarm() end
    f.removeGroup:SetShown(groupTab)
    bottom:ClearAllPoints()
    bottom:SetPoint("TOPLEFT", f, "TOPLEFT", Card.PAD, -(rows + 10))
    f:SetHeight(rows + 10 + Card.REMOVE_H + Card.PAD)
    local fresh = not f:IsShown()
    place(set, id)
    if fresh then
        DUI.Motion.AlphaTo(f, 1, 0)
        DUI.Motion.Pop(f)
    else
        DUI.Motion.AlphaTo(f, 1, DUI.Motion.FAST)
    end
end
