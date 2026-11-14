-- Target auras through the client's custom aura container, so nothing reads
-- aura data in combat. Two containers: debuffs (the focus of attention) sit
-- above the frame, larger, running from over the name tab toward the angled
-- inner end, then up. Buffs sit in a row under the frame, smaller, from the
-- portrait side inward, then down. Icons are slightly wider than tall (the art
-- is cropped, not squashed) with the time on the top edge. Group filters are
-- fixed when declared, so every group is declared once and settings only change
-- counts and layout. The player frame can have the same two rows
-- (Auras.Create(f, "right", "player"), off by default), and each container
-- keeps its own icon size.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Auras = {}
ns.Auras = Auras

-- Debuffs you can dispel (your class and spec). Not HARMFUL|RAID, which is the
-- client's "worth showing on raid frames" list and leaves out other players'
-- debuffs (nothing showed in battlegrounds). EllesmereUI does the same.
Auras.DISPEL_FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"

-- Each container's groups, laid out in index order. Your debuffs come first,
-- then everyone else's: the ones you can dispel first, with a soft halo (`halo`,
-- so a friendly target's curse or poison stands out), then the rest. A client
-- that refuses either half keeps "others", everything in one group
-- (Auras.Splits). Listed in the order they claim room when the rows run short
-- (Auras.Limit): the rest before the dispellable ones, so an enemy's row
-- (never anything to dispel) keeps every icon it had.
Auras.KINDS = {
    debuff = { name = "DaylightUITargetDebuffs", groups = {
        { key = "mine", filter = "HARMFUL|PLAYER", index = 1 },
        { key = "rest", filter = "HARMFUL|!PLAYER|!RAID_PLAYER_DISPELLABLE", index = 3 },
        { key = "cure", filter = "HARMFUL|!PLAYER|RAID_PLAYER_DISPELLABLE", index = 2, halo = true },
        { key = "others", filter = "HARMFUL|!PLAYER", index = 3, fallback = true },
    } },
    -- The buff filter picks one group (buffFilter all|purge|mine). The other
    -- two are added the first time they're picked (lazy).
    buff = { name = "DaylightUITargetBuffs", groups = {
        { key = "buffs", filter = "HELPFUL", index = 1, pick = "all" },
        { key = "purge", filter = "HELPFUL|RAID_PLAYER_DISPELLABLE", index = 1, pick = "purge", lazy = true },
        { key = "mine", filter = "HELPFUL|PLAYER", index = 1, pick = "mine", lazy = true },
    } },
    -- The player frame's own rows (off by default). On yourself "mine and
    -- others" means nothing, so it's every debuff, or only the ones you can
    -- dispel (debuffFilter all|dispel).
    selfdebuff = { name = "DaylightUIPlayerDebuffs", groups = {
        { key = "all", filter = "HARMFUL", index = 1, pick = "all" },
        { key = "dispel", filter = Auras.DISPEL_FILTER, index = 1, pick = "dispel", lazy = true },
    } },
    -- Every buff, or only the ones you cast (buffFilter all|mine, the pet's
    -- rows: Mend Pet, your blessings on it).
    selfbuff = { name = "DaylightUIPlayerBuffs", groups = {
        { key = "buffs", filter = "HELPFUL", index = 1, pick = "all" },
        { key = "mine", filter = "HELPFUL|PLAYER", index = 1, pick = "mine", lazy = true },
    } },
    -- A unit frame's buffs group. Filters are fixed when declared, so all three
    -- are here and Auras.SetBuffCounts leaves one on. heals: your buffs from
    -- your class's heal list (HealSpells.lua), matched by spell id. yours: a
    -- group of your own buffs, off while the unit is out of sight. Plugins'
    -- spell lists are added here too (AuraGroups.TakePlugins).
    tilebuff = { groups = {
        { key = "mine", filter = "HELPFUL|PLAYER", index = 1, yours = true },
        { key = "heals", filter = "HELPFUL|PLAYER", index = 1, yours = true, ids = function() return ns.HealSpells.Ids() end },
        { key = "all", filter = "HELPFUL", index = 1 },
    } },
    -- A unit frame's aura groups (AuraGroups.lua). Every "which" choice is
    -- declared here and AuraGroups.Place leaves one on. notcc replaces all
    -- while the crowd control group shows those, so nothing shows twice.
    gdebuff = { groups = {
        { key = "all", filter = "HARMFUL", index = 1 },
        { key = "notcc", filter = "HARMFUL|!CROWD_CONTROL", index = 1 },
        { key = "dispel", filter = Auras.DISPEL_FILTER, index = 1 },
        { key = "raid", filter = "HARMFUL|RAID_IN_COMBAT", index = 1 },
    } },
    gcc = { groups = {
        { key = "cc", filter = "HARMFUL|CROWD_CONTROL", index = 1 },
    } },
}

-- Kinds that get a plain border (no dispel-colored edge).
local BUFF_KINDS = { buff = true, tilebuff = true, selfbuff = true }
-- Kinds whose buffs you can purge or steal get a soft halo (Style.AuraHalo),
-- i.e. the target's buffs. Dispellable debuffs get one through their group (`halo`).
local HALO_KINDS = { buff = true }

-- Gap between icons. Timers read "49m", not "49 m" (Style.SetAuraTime), so they
-- fit even on the small buff icons.
Auras.SPACING = { debuff = 3, buff = 3, tilebuff = 2, gdebuff = 2, gcc = 2, selfdebuff = 3, selfbuff = 3 }
Auras.GAP = 3               -- gap between the name tab and the debuffs above it
Auras.ASPECT = 0.88         -- icon height as a share of its width
Auras.BORDER_PX = 2         -- icons are small, so a lighter border than frames
Auras.DEBUFF_BORDER = { 0.6, 0.16, 0.18 }
-- A debuff's edge takes its dispel type's color. The client picks it, so
-- nothing is read. No type keeps the wine color.
Auras.DISPEL_COLORS = {
    Magic = { 0.25, 0.55, 0.95 }, Curse = { 0.62, 0.3, 0.9 }, Disease = { 0.7, 0.5, 0.18 },
    Poison = { 0.3, 0.7, 0.25 }, Bleed = { 0.78, 0.14, 0.14 }, None = Auras.DEBUFF_BORDER,
}
Auras.TIME_COLOR = DUI.Style.INK.VALUE
Auras.TIME_SIZE = { debuff = 12, buff = 9, tilebuff = 8, gdebuff = 8, gcc = 9, selfdebuff = 12, selfbuff = 9 }
Auras.COUNT_SIZE = 10
-- The client shows the aura tooltip itself once a button has an anchor for it.
-- Above the icon keeps it clear of the frames below.
Auras.TOOLTIP_ANCHOR = "ANCHOR_TOP"
-- Filters the client refused when a group was added (an older build without
-- the token). The options hide those choices and AuraGroups falls back.
Auras.REFUSED = {}

local buttons = setmetatable({}, { __mode = "k" })
-- The same, per container, so a container's change only walks its own.
local byContainer = setmetatable({}, { __mode = "k" })
local function ownButtons(c) return byContainer[c] or {} end

-- Stand-ins for the client's containers (Auras.Plain): plain frames the same
-- layout and sample code draws on, for samples shown in another window. They
-- hold no buttons, so laying one out resizes no real ones.
local plain = setmetatable({}, { __mode = "k" })

local function dims(w)
    return { w, math.floor(w * Auras.ASPECT + 0.5) }
end

local sizeOf = { debuff = dims(30), buff = dims(18), tilebuff = dims(14), gdebuff = dims(14), gcc = dims(18),
                 selfdebuff = dims(30), selfbuff = dims(18) }

-- A container's own icon size and gap, where it has one (aura groups, and the
-- target's and player's rows, since each frame lays out its own with its own
-- settings).
local ownSize = setmetatable({}, { __mode = "k" })   -- container -> { s = {w, h}, gap = n }

-- Container c's icon size and gap: its own, else its kind's.
local function dimsOf(c, kind)
    local own = c and ownSize[c]
    return own and own.s or sizeOf[kind], own and own.gap or Auras.SPACING[kind]
end

-- A container's own text sizes, where it has them (the target's, player's and
-- personal display's rows, Auras.SetTextSizes): container -> { time, count }.
local ownText = setmetatable({}, { __mode = "k" })

-- Container c's time and stack count sizes: its own, else its kind's.
local function textOf(c, kind)
    local own = c and ownText[c]
    return own and own.time or Auras.TIME_SIZE[kind], own and own.count or Auras.COUNT_SIZE
end

-- Containers whose icons show no time number (Auras.SetTimers).
local noTimers = setmetatable({}, { __mode = "k" })

-- Containers whose icons show the time left as a clock sweep (Auras.SetSwipe).
local swipeOn = setmetatable({}, { __mode = "k" })
-- Containers whose icons hide their stack count (Auras.SetCounts).
local noCounts = setmetatable({}, { __mode = "k" })
local tipsOn = setmetatable({}, { __mode = "k" })

-- The sweep: elapsed time shades the icon clockwise, like the action bars'
-- cooldown shade (black at SWIPE_ALPHA), so a buff darkens as it runs out. The
-- client drives it from the aura's own duration, in combat too.
Auras.SWIPE_ALPHA = 0.6
function Auras.StyleSwipe(cd, on)
    cd:SetDrawSwipe(on)
    if not on then return end
    cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    cd:SetSwipeColor(0, 0, 0, Auras.SWIPE_ALPHA)
    cd:SetReverse(true)
end

-- Containers whose time numbers show only under a minute (true) or always
-- (false, once switched). nil means never switched, using the plain binding.
local shortOnly = setmetatable({}, { __mode = "k" })

-- The formatter the client writes the time with. short writes nothing from SHORT
-- seconds up, so only an expiring time shows. The client runs it on the time
-- left itself, in combat too. A transparent color curve was tried first, but
-- long times still showed in game.
Auras.SHORT = 60
function Auras.TimeFormatter(short)
    return Style.DurationFormatter(short and Auras.SHORT or nil)
end

-- A container's formatter. With timers off it writes nothing
-- (Style.DurationFormatter(0)). Hiding the text didn't stick, since the client
-- owns it and shows it again.
local function formatterOf(c)
    if c and noTimers[c] then return Style.DurationFormatter(0) end
    return Auras.TimeFormatter(c and shortOnly[c])
end

-- Newer builds renamed the container layout setters; use whichever exists.
local function call(c, names, ...)
    for _, n in ipairs(names) do
        local fn = c[n]
        if fn then return fn(c, ...) end
    end
end

local function groupLayout(kind, index, c)
    local s, gap = dimsOf(c, kind)
    return { layoutIndex = index, elementWidth = s[1], elementHeight = s[2],
             elementSpacing = gap, lineSpacing = gap + 4 }
end

-- Crop the icon art top and bottom so a wide button doesn't squash it.
local function iconCoords(w, h)
    local span = 0.84 * h / w
    return 0.08, 0.92, 0.5 - span / 2, 0.5 + span / 2
end

Auras.DISPEL_KEYS = Style.DISPEL_KEYS

-- Registers edge to be tinted by the aura's dispel type (Style.DispelEdge) and
-- returns which method worked. withoutType false: nothing shows for an aura
-- without a dispel type. asset: a texture to use instead of the plain square.
function Auras.RegisterDispelEdge(btn, edge, withoutType, asset, coords)
    return Style.DispelEdge(btn, edge, function(key) return Auras.DISPEL_COLORS[key] or Auras.DEBUFF_BORDER end,
        { withoutType = withoutType, asset = asset, coords = coords })
end

-- An icon on a party or raid tile. Clicks always pass through to the tile
-- (click-casting), and hover too unless its tooltip is on. An icon that takes
-- the hover keeps the mouse off the tile, so a mouseover cast misses that
-- player.
Auras.TILE_KINDS = { tilebuff = true, gdebuff = true, gcc = true }
function Auras.TileMouse(btn, tips)
    pcall(btn.EnableMouse, btn, tips == true)
    pcall(btn.SetMouseClickEnabled, btn, false)
    pcall(btn.SetMouseMotionEnabled, btn, tips == true)
end

-- cure: the button belongs to a group of debuffs you can dispel (a group's `halo`).
function Auras.InitButton(btn, kind, container, cure)
    local s = dimsOf(container, kind)
    btn:SetSize(s[1], s[2])
    if Auras.TILE_KINDS[kind] then
        Auras.TileMouse(btn, container ~= nil and tipsOn[container] == true)
    elseif container and tipsOn[container] == false then
        pcall(btn.EnableMouse, btn, false)
    end
    local T = Pixel.Px(btn, Auras.BORDER_PX)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", T, -T)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
    icon:SetTexCoord(iconCoords(s[1], s[2]))
    btn:SetIcon(icon)
    -- Soft dark edges fading inward give the icon depth.
    local shade = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    shade:SetAllPoints(icon)
    shade:SetTexture(DUI.MEDIA .. "inner-shadow.png")
    shade:SetVertexColor(0, 0, 0, 1)
    -- The clock sweep, off unless the container asks for it (Auras.SetSwipe).
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    Auras.StyleSwipe(cd, container ~= nil and swipeOn[container] == true)
    cd:SetDrawEdge(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    cd:SetHideCountdownNumbers(true)
    cd:EnableMouse(false)
    btn:SetDurationCooldown(cd)
    local timeSize, countSize = textOf(container, kind)
    local time = Style.Text(btn, timeSize, "CENTER")
    time:SetPoint("CENTER", btn, "TOP", 0, 0)
    local c = Auras.TIME_COLOR
    time:SetTextColor(c[1], c[2], c[3])
    local f = formatterOf(container)
    Style.SetAuraTime(btn, time, nil, f)
    if not f and container and noTimers[container] then time:Hide() end
    local count = Style.Text(btn, countSize, "RIGHT")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn:SetApplicationCount(count)
    if container and noCounts[container] then count:SetAlpha(0) end
    pcall(btn.SetTooltipAnchorPoint, btn, Auras.TOOLTIP_ANCHOR)
    if not BUFF_KINDS[kind] then
        -- A square edge the size of the button, behind the icon, tinted by the
        -- client from the aura's dispel type. It's the debuff's whole border,
        -- because the client reorders a button's frames and a shell border
        -- could end up on top and hide it. Wine until the client colors it.
        local edge = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        edge:SetTexture("Interface\\Buttons\\WHITE8x8")
        edge:SetAllPoints(btn)
        local w = Auras.DEBUFF_BORDER
        edge:SetVertexColor(w[1], w[2], w[3], 1)
        Auras.RegisterDispelEdge(btn, edge)
    end
    local shell = Style.Shell(btn, {
        noBackground = true, noBevel = true, borderPx = Auras.BORDER_PX, lean = true,
        noBorder = not BUFF_KINDS[kind],
    })
    -- The client owns and redraws aura buttons itself; keep them out of the
    -- global style repaint sets so a settings change doesn't touch them.
    Style.Untrack(shell)
    Style.Untrack(time)
    Style.Untrack(count)
    local halo = (HALO_KINDS[kind] or cure) and Style.AuraHalo(btn, Auras.DISPEL_COLORS, cure)
    Style.PlaceAuraHalo(halo, btn, s[1])
    local parts = { icon = icon, kind = kind, container = container, time = time, count = count, halo = halo, cd = cd }
    buttons[btn] = parts
    if container then
        byContainer[container] = byContainer[container] or setmetatable({}, { __mode = "k" })
        byContainer[container][btn] = parts
    end
end

local function groupOf(kind, key)
    for _, g in ipairs(Auras.KINDS[kind].groups) do
        if g.key == key then return g end
    end
end

-- Adds group key of c's kind, once. The client builds a batch of buttons right
-- here and runs InitButton on each. In a PvP match that's the only moment they
-- can be styled, so the container's settings (size, timers, swipe) are applied
-- before its groups. Returns true when the group exists.
function Auras.AddGroup(c, key)
    if not c or plain[c] or not c.dluiGroups then return false end
    if c.dluiGroups[key] then return true end
    local kind = c.dluiKind
    local g = groupOf(kind, key)
    if not g then return false end
    local ids = g.ids and g.ids()
    if g.ids and not ids then return false end   -- a spell list your class doesn't have
    local ok, err = pcall(function()
        c:AddAuraGroup(g.key, g.filter, {
            sortMethod = AuraContainerSortMethod.ExpirationOnly,
            sortDirection = AuraContainerSortDirection.Normal,
            maxFrameCount = 0,
            candidateFilters = ids and { includeSpellIDs = ids } or nil,
            layout = groupLayout(kind, g.index, c),
            initializeFrame = function(btn) Auras.InitButton(btn, kind, c, g.halo) end,
        })
    end)
    if ok then
        c.dluiGroups[key] = true
        return true
    end
    -- Only a refusal outside combat and restrictions belongs to the filter
    -- itself. A group made mid-fight or after a /reload in a BG can fail for
    -- other reasons and is retried on the next layout. A real refusal hides
    -- that choice for the session.
    if not DUI.Restricted() then
        if not Auras.REFUSED[g.filter] then
            DUI.Print(string.format(DUI.L["Aura group '%s' failed: %s"], g.key, tostring(err)))
        end
        Auras.REFUSED[g.filter] = true
    end
    return false
end

-- unit: whose auras (the target by default). down: rows start at the top and
-- wrap downward (under a frame) instead of up. prep(c) applies the settings
-- before any group is added. lazy: no groups now, each is added the first time
-- it shows (Auras.AddGroup, AuraGroups.Place).
local function newContainer(frame, kind, side, unit, down, prep, lazy, name)
    local ok, c = pcall(CreateFrame, "AuraContainer", name or Auras.KINDS[kind].name, frame, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end
    c:SetUnit(unit or "target")
    c:EnableMouse(false)
    c.dluiKind = kind
    c.dluiGroups = {}   -- key -> true for each group the client accepted
    -- Rows start at their outer edge and grow toward the inner end, then up or
    -- down.
    local edge = side == "left" and "RIGHT" or "LEFT"
    call(c, { "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint" }, (down and "TOP" or "BOTTOM") .. edge)
    local fd = AnchorUtil and AnchorUtil.FlowDirection
    if fd then
        call(c, { "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection" },
            side == "left" and fd.Left or fd.Right, down and fd.Down or fd.Up)
    end
    if prep then prep(c) end
    if lazy then return c end
    for _, g in ipairs(Auras.KINDS[kind].groups) do
        if not g.fallback and not g.lazy then Auras.AddGroup(c, g.key) end
    end
    -- The all-in-one group only when the client refused the split.
    for _, g in ipairs(Auras.KINDS[kind].groups) do
        if g.fallback and not Auras.Splits(c) then Auras.AddGroup(c, g.key) end
    end
    return c
end

-- Which Auras.KINDS each row of a set uses: the target's, or the player
-- frame's own (unit "player").
local SET_KINDS = {
    target = { debuff = "debuff", buff = "buff" },
    -- The focus's rows work like the target's, in containers of their own name.
    focus = { debuff = "debuff", buff = "buff", names = { debuff = "DaylightUIFocusDebuffs", buff = "DaylightUIFocusBuffs" } },
    player = { debuff = "selfdebuff", buff = "selfbuff" },
    -- A friendly unit like you: every debuff (or the ones you can dispel) and its buffs.
    pet = { debuff = "selfdebuff", buff = "selfbuff", names = { debuff = "DaylightUIPetDebuffs", buff = "DaylightUIPetBuffs" } },
}

-- side is the frame's inner end ("left" for the target, "right" for the
-- player). unit: whose auras ("target" by default, or "player"). Returns
-- { debuffs = container, buffs = container, side = side, kinds } or nil.
-- cfg: the rows' settings (targetAuras or playerAuras). Their size goes on each
-- container before its buttons are built.
-- Never LoadAddOn("Blizzard_AuraContainer") from here. It's a game addon
-- ("AllowLoad: game") that runs in the secure environment, and loading it from
-- addon code before the game did broke every game call to a method an addon
-- had hooked ("attempt to call a nil value"). The containers don't need it
-- loaded; the game loads it itself.
local warned
function Auras.Create(frame, side, unit, cfg)
    unit = unit or "target"
    local kinds = SET_KINDS[unit] or SET_KINDS.target
    local function prep(kind)
        return function(c)
            local w = cfg and tonumber(cfg[kind .. "Size"])
            if w then Auras.SetOwnSize(c, w, tonumber(cfg[kind .. "Spacing"]) or Auras.SPACING[kind]) end
            if cfg then
                Auras.SetTextSizes(c, cfg[kind .. "TimeSize"], cfg[kind .. "CountSize"])
                Auras.SetRowLook(c, cfg, kind)
            end
        end
    end
    local names = kinds.names or {}
    local debuffs = newContainer(frame, kinds.debuff, side, unit, false, prep("debuff"), nil, names.debuff)
    if not debuffs then
        if not warned then DUI.Print(DUI.L["This client has no aura container; target auras are off."]) end
        warned = true
        return nil
    end
    -- Buffs under the frame: their rows start at the top and go down.
    return { debuffs = debuffs, buffs = newContainer(frame, kinds.buff, side, unit, true, prep("buff"), nil, names.buff), side = side,
             kinds = kinds }
end

-- A stand-in for a container on frame: a plain frame the samples are drawn on
-- (the options pages' live samples, test mode). The client never fills it.
function Auras.Plain(frame)
    local c = CreateFrame("Frame", nil, frame)
    c:EnableMouse(false)
    plain[c] = true
    return c
end

-- A target set made of stand-ins. Apply, Place and ShowSample accept it like
-- the real one.
function Auras.PlainSet(frame, side)
    return { debuffs = Auras.Plain(frame), buffs = Auras.Plain(frame), side = side }
end

-- Where each container was placed, so a test mode sample holder can go to the
-- same spot. Nothing may be anchored to a container itself: once it has aura
-- groups the client forbids it ("UntrustedLayoutScriptExecution").
local spots = setmetatable({}, { __mode = "k" })   -- container -> { points, w, h }

local function clear(c)
    c:ClearAllPoints()
    spots[c] = spots[c] or {}
    spots[c].points = {}
end

local function put(c, point, rel, relPoint, x, y)
    c:SetPoint(point, rel, relPoint, x, y)
    local s = spots[c]
    s.points[#s.points + 1] = { point, rel, relPoint, x, y }
end

local function size(c, w, h)
    c:SetSize(w, h)
    spots[c] = spots[c] or { points = {} }
    spots[c].w, spots[c].h = w, h
end

-- Whether a target's debuff container has the dispellable debuffs in their own
-- group (the client accepted both halves).
function Auras.Splits(c)
    local g = c and c.dluiGroups
    return g ~= nil and g.cure == true and g.rest == true
end

-- Whether c is a stand-in (Auras.Plain). The client's calls skip it.
function Auras.IsPlain(c) return plain[c] == true end

-- For AuraGroups.lua: a container of any kind in Auras.KINDS.
Auras.NewContainer = newContainer

-- A container's own icon width and gap. Its groups' layouts and its buttons
-- follow (a stand-in only stores the numbers). Returns { w, h }. Called on
-- every layout, but only a change does anything.
function Auras.SetOwnSize(c, width, gap)
    local own = ownSize[c]
    if own and own.width == width and own.gap == gap then return own.s end
    local s = dims(width)
    ownSize[c] = { s = s, gap = gap, width = width }
    local kind = c.dluiKind
    if plain[c] then return s end
    if kind and Auras.KINDS[kind] then
        for _, g in ipairs(Auras.KINDS[kind].groups) do
            if c.dluiGroups and c.dluiGroups[g.key] then
                pcall(c.SetAuraGroupLayout, c, g.key, groupLayout(kind, g.index, c))
            end
        end
    end
    -- Locked while auras are secret (combat, a PvP match, a boss), so sized once that lifts.
    DUI.AfterRestrictions(function()
        for btn, parts in pairs(ownButtons(c)) do
            pcall(btn.SetSize, btn, s[1], s[2])
            pcall(parts.icon.SetTexCoord, parts.icon, iconCoords(s[1], s[2]))
            if parts.halo then pcall(Style.PlaceAuraHalo, parts.halo, btn, s[1]) end
        end
    end, "auras:ownsize:" .. tostring(c))
    return s
end

-- A container's own time and stack count sizes (nil uses its kind's). A
-- stand-in only stores the numbers. Only a change touches the buttons, once
-- restrictions lift since they're locked. The client owns these texts, so they
-- stay out of the style repaint sets (Style.SetTextSize tracks them).
local function sizeText(fs, size)
    pcall(Style.SetTextSize, fs, size)
    Style.Untrack(fs)
end

function Auras.SetTextSizes(c, time, count)
    local own = ownText[c]
    if own and own.time == time and own.count == count then return end
    ownText[c] = { time = time, count = count }
    if plain[c] then return end
    DUI.AfterRestrictions(function()
        for _, parts in pairs(ownButtons(c)) do
            local t, n = textOf(c, parts.kind)
            sizeText(parts.time, t)
            sizeText(parts.count, n)
        end
    end, "auras:text:" .. tostring(c))
end

-- Whether a container's icons show their time left as a number. Only a change
-- touches the buttons, once restrictions lift (they're locked).
function Auras.SetTimers(c, on)
    if plain[c] or noTimers[c] == (not on) then return end
    noTimers[c] = not on
    DUI.AfterRestrictions(function()
        local f = formatterOf(c)
        for btn, parts in pairs(ownButtons(c)) do
            if parts.time then
                pcall(Style.SetAuraTime, btn, parts.time, nil, f)
                if not f then pcall(parts.time.SetShown, parts.time, on) end
            end
        end
    end, "auras:timers:" .. tostring(c))
end

-- Whether a container's icons show their stack count. The client writes the
-- number, so off only turns the text see-through. Locked buttons wait, as above.
function Auras.SetCounts(c, on)
    on = on ~= false
    if plain[c] or (noCounts[c] == true) == not on then return end
    noCounts[c] = not on or nil
    DUI.AfterRestrictions(function()
        for _, parts in pairs(ownButtons(c)) do
            if parts.count then pcall(parts.count.SetAlpha, parts.count, on and 1 or 0) end
        end
    end, "auras:counts:" .. tostring(c))
end

-- Whether a container's icons show the clock sweep. Locked buttons wait, as
-- above.
function Auras.SetSwipe(c, on)
    on = on == true
    if plain[c] or (swipeOn[c] == true) == on then return end
    swipeOn[c] = on
    DUI.AfterRestrictions(function()
        for _, parts in pairs(ownButtons(c)) do
            if parts.cd then pcall(Auras.StyleSwipe, parts.cd, on) end
        end
    end, "auras:swipe:" .. tostring(c))
end

-- Whether a tile's icons show their tooltip on hover. Locked buttons wait, as
-- above.
function Auras.SetTips(c, on)
    on = on == true
    -- nil until set: a target row's icons take the hover unless switched off.
    if plain[c] or tipsOn[c] == on then return end
    tipsOn[c] = on
    DUI.AfterRestrictions(function()
        for btn, parts in pairs(ownButtons(c)) do
            -- A tile's icons never take clicks. The target's and player's
            -- rows keep what the client gives them, only the hover goes.
            if Auras.TILE_KINDS[parts.kind] then Auras.TileMouse(btn, on) else pcall(btn.EnableMouse, btn, on) end
        end
    end, "auras:tips:" .. tostring(c))
end

-- A target, player or personal row's time numbers, sweep and tooltips from
-- its settings (<kind>Timers, <kind>ShortTimers, <kind>Swipe, <kind>Tips).
-- Called before the row's groups are added too, since locked buttons only
-- take them while they're built.
function Auras.SetRowLook(c, cfg, kind)
    if not (c and cfg) then return end
    Auras.SetTimers(c, cfg[kind .. "Timers"] ~= false)
    Auras.SetShortTimers(c, cfg[kind .. "ShortTimers"] == true)
    Auras.SetSwipe(c, cfg[kind .. "Swipe"] == true)
    Auras.SetTips(c, cfg[kind .. "Tips"] ~= false)
end

-- Whether a container's time numbers show only under a minute. Locked buttons
-- wait, as above.
function Auras.SetShortTimers(c, on)
    on = on == true
    -- Never switched on (nil), so the plain binding stays.
    if plain[c] or shortOnly[c] == on or (shortOnly[c] == nil and not on) then return end
    shortOnly[c] = on
    DUI.AfterRestrictions(function()
        local f = formatterOf(c)
        for btn, parts in pairs(ownButtons(c)) do
            if parts.time then pcall(Style.SetAuraTime, btn, parts.time, nil, f) end
        end
    end, "auras:short:" .. tostring(c))
end

-- Where a container's flow starts and which way it runs (hDir/vDir are
-- AnchorUtil.FlowDirection keys), and the maximum row length.
function Auras.SetFlow(c, anchorPoint, hDir, vDir, line)
    if plain[c] then return end
    pcall(call, c, { "SetFlowLayoutAnchorPoint", "SetAuraLayoutAnchorPoint" }, anchorPoint)
    local fd = AnchorUtil and AnchorUtil.FlowDirection
    if fd then
        pcall(call, c, { "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection" }, fd[hDir], fd[vDir])
    end
    if line then pcall(call, c, { "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth" }, line) end
end

-- A set's row of kind ("debuff" or "buff"): its icon size and gap.
local function rowDims(set, kind)
    return dimsOf(set[kind .. "s"], kind)
end

-- The groups a set's row of kind is made of.
local function groupsOf(set, kind)
    return Auras.KINDS[(set.kinds or SET_KINDS.target)[kind]].groups
end

-- How many icons fit in `rows` lines of the container's current width.
local function perRowOf(set, kind)
    local s, gap = rowDims(set, kind)
    return math.max(1, math.floor(((set[kind .. "Row"] or s[1]) + gap) / (s[1] + gap)))
end

-- The wanted counts per group in turn, cut to what `rows` lines can hold.
local function capCounts(set, kind, want, rows)
    local room = rows and rows * perRowOf(set, kind) or math.huge
    local out = {}
    for i, n in ipairs(want) do
        out[i] = math.min(n, room)
        room = room - out[i]
    end
    return out
end

-- Sets how many of each group can show (Auras.Height reserves their rows).
-- Called again whenever the row width is known, since it decides icons per row.
function Auras.Limit(set)
    if not set or not set.want then return end
    local rows = set.rows or {}
    set.counts = {
        debuff = capCounts(set, "debuff", set.want.debuff, rows.debuff),
        buff = capCounts(set, "buff", set.want.buff, rows.buff),
    }
    local d = set.debuffs
    for i, g in ipairs(groupsOf(set, "debuff")) do
        pcall(d.SetAuraGroupMaxFrameCount, d, g.key, set.counts.debuff[i] or 0)
    end
    local b = set.buffs
    if b then
        for i, g in ipairs(groupsOf(set, "buff")) do
            pcall(b.SetAuraGroupMaxFrameCount, b, g.key, set.counts.buff[i] or 0)
        end
    end
end

-- The wanted count of each group of a picked-filter row (groups with `pick`):
-- n for the picked one, 0 for the rest. A picked group not made yet is added
-- now, after the row's settings are on its container.
local function pickedWant(set, kind, pick, n)
    local c, out = set[kind .. "s"], {}
    local groups = groupsOf(set, kind)
    local known = false
    for _, g in ipairs(groups) do known = known or g.pick == pick end
    if not known then pick = groups[1].pick end
    for i, g in ipairs(groups) do
        local on = g.pick == pick and n > 0
        if on and g.lazy and not Auras.AddGroup(c, g.key) then on = false end
        out[i] = on and n or 0
    end
    return out
end

-- Where each row sits (Spots.lua): its spot, growth direction, and nudge.
-- Without settings (a sample's), debuffs go above and buffs below, both from
-- the outer end inward.
local function spotOf(cfg, kind, spot)
    local g = cfg[kind .. "Grow"]
    return { spot = ns.Spots.Valid(cfg[kind .. "Spot"]) and cfg[kind .. "Spot"] or spot,
             grow = (g == "right" or g == "center") and g or "left",
             x = tonumber(cfg[kind .. "X"]) or 0, y = tonumber(cfg[kind .. "Y"]) or 0 }
end

function Auras.Apply(set, cfg)
    if not set then return end
    set.spots = { debuff = spotOf(cfg, "debuff", "above"), buff = spotOf(cfg, "buff", "below") }
    -- Each row's own size and gap, so the target's and player's never mix.
    -- It re-lays the groups and sizes the buttons once restrictions lift.
    Auras.SetOwnSize(set.debuffs, cfg.debuffSize or sizeOf.debuff[1], cfg.debuffSpacing or Auras.SPACING.debuff)
    Auras.SetTextSizes(set.debuffs, cfg.debuffTimeSize, cfg.debuffCountSize)
    Auras.SetRowLook(set.debuffs, cfg, "debuff")
    if set.buffs then
        Auras.SetOwnSize(set.buffs, cfg.buffSize or sizeOf.buff[1], cfg.buffSpacing or Auras.SPACING.buff)
        Auras.SetTextSizes(set.buffs, cfg.buffTimeSize, cfg.buffCountSize)
        Auras.SetRowLook(set.buffs, cfg, "buff")
    end
    -- Others' debuffs: the dispellable ones and the rest, each up to the count,
    -- or all in one group when the client refused the split.
    local others = (cfg.debuffs and cfg.debuffFilter == "all") and cfg.maxOtherDebuffs or 0
    local split = Auras.Splits(set.debuffs)
    local debuffWant
    if groupsOf(set, "debuff")[1].pick then
        debuffWant = pickedWant(set, "debuff", cfg.debuffFilter, cfg.debuffs and cfg.maxDebuffs or 0)
    else
        debuffWant = { cfg.debuffs and cfg.maxDebuffs or 0,
                       split and others or 0, split and others or 0, split and 0 or others }
    end
    set.want = {
        debuff = debuffWant,
        buff = set.buffs and pickedWant(set, "buff", cfg.buffFilter, cfg.buffs and cfg.maxBuffs or 0) or {},
    }
    set.rows = { debuff = cfg.debuffRows, buff = cfg.buffRows }
    Auras.Limit(set)
end

-- The container only re-reads auras on an aura change or when shown, so
-- switching straight from one target to another would keep the old icons.
-- Call this whenever the unit behind "target" changes.
function Auras.Refresh(set)
    if not set then return end
    for _, c in ipairs({ set.debuffs, set.buffs }) do
        if c and c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end
    end
end

-- Sets how many buffs show. Only one of the two groups is ever non-zero, so
-- they share rows. cfg.showBuffs false or missing (a sample's settings may
-- leave it out) means off.
-- Out of sight range the game no longer knows who cast someone's buffs and
-- counts others' as yours, so "mine" stays off until they're seen again.
local mineCount, unseen = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local mineKey = setmetatable({}, { __mode = "k" })   -- the group that shows

function Auras.SetBuffCounts(c, cfg, count)
    if not c or plain[c] then return end
    local n = cfg.showBuffs and count or 0
    local which = groupOf("tilebuff", cfg.buffFilter) and cfg.buffFilter or "mine"
    mineCount[c] = n
    for _, g in ipairs(Auras.KINDS.tilebuff.groups) do
        if g.key == "mine" or g.key == "all" or (c.dluiGroups and c.dluiGroups[g.key]) then
            local hide = g.key ~= which or (g.yours and unseen[c])
            pcall(c.SetAuraGroupMaxFrameCount, c, g.key, hide and 0 or n)
        end
    end
    mineKey[c] = which
end

-- seen: the unit is within sight range. Only a change touches the container.
function Auras.SetBuffsSeen(c, seen)
    if not c or unseen[c] == not seen then return end
    unseen[c] = not seen
    local g = groupOf("tilebuff", mineKey[c] or "mine")
    if g and g.yours then
        pcall(c.SetAuraGroupMaxFrameCount, c, g.key, seen and (mineCount[c] or 0) or 0)
    end
end

-- Debuffs go above the frame by default: over the name tab, from its outer end
-- inward, rows stacking up, as wide as the frame. Buffs go below it: from just
-- inside the portrait ring inward, rows going down, under the combo points if
-- there are any (set.buffDrop; set.aboveLift lifts rows above the frame past
-- them instead). Any other spot comes from Spots.lua, clear of the angled end,
-- ring and tab (AuraGroups.Box). When both share a spot above or below the
-- frame, buffs sit nearest (small, so they fit one row) and the debuffs start
-- past every row the buffs could fill (Auras.Height), free to wrap outward
-- without covering anything. Both anchor to the frame, never to each other,
-- since the client forbids anchoring to a container.

-- The room a container's rows can take: every row its groups could fill (each
-- group starts its own row), plus the time on the top row.
function Auras.Height(set, kind)
    local s, gap = rowDims(set, kind)
    local line = set[kind .. "Row"] or s[1]
    local perRow = math.max(1, math.floor((line + gap) / (s[1] + gap)))
    local rows = 0
    for _, n in ipairs(set.counts and set.counts[kind] or {}) do
        rows = rows + math.ceil(n / perRow)
    end
    if rows == 0 then return 0 end
    return rows * s[2] + (rows - 1) * (gap + 4) + (textOf(set[kind .. "s"], kind)) * 0.6 + 2
end

-- Above or below the frame (off a corner too). Rows there stack and push that
-- side's reach.
local function sideOf(spot)
    if spot == "above" or spot:find("^outtop") then return "above" end
    if spot == "below" or spot:find("^outbottom") then return "below" end
end

-- Puts the rows where the settings say. frameCfg: the frame's own settings
-- (its power bar, for the inside spots; kept for the next call). Returns how
-- far they reach above their anchor (the name tab's top when shown, else the
-- frame's top) and below the frame's bottom, 0 for an empty side.
function Auras.Place(set, frame, frameCfg)
    if not set then return end
    set.frameCfg = frameCfg or set.frameCfg
    local box = ns.AuraGroups.Box(frame, set.frameCfg)
    local tabH, foot, fw = box.above, box.below, frame:GetWidth()
    local spots = set.spots or { debuff = spotOf({}, "debuff", "above"), buff = spotOf({}, "buff", "below") }
    local up, down = set.aboveLift or 0, set.buffDrop or 0
    local any = {}
    set.flow = {}
    -- Both rows over (or under) the frame, buffs running right from the left
    -- end and debuffs left from the right end: they share the line side by
    -- side, each in its own half, instead of stacking.
    local sb, sd = spots.buff, spots.debuff
    local paired = set.buffs and sb and sd and sb.spot == sd.spot and (sb.spot == "above" or sb.spot == "below")
        and sb.grow == "right" and sd.grow == "left"
    local pairTall, buffLine = 0, 0
    local function total(list) local n = 0; for _, v in ipairs(list or {}) do n = n + v end; return n end
    -- With either row empty the other keeps the whole line.
    if paired and (total(set.want and set.want.buff) == 0 or total(set.want and set.want.debuff) == 0) then
        paired = false
    end
    -- Buffs first, so they're nearest the frame when both share a side.
    for _, entry in ipairs({ { set.buffs, "buff" }, { set.debuffs, "debuff" } }) do
        local c, kind = entry[1], entry[2]
        local sp = spots[kind]
        if c and sp then
            local side = sideOf(sp.spot)
            box.above, box.below = tabH + up, foot + down
            -- A row above the frame spans it from past the tab's start, one
            -- below from past the ring. Other spots take their own room.
            local line
            if sp.spot == "above" then
                line = fw - (sp.grow == "right" and box.aboveInL or box.aboveInR)
            elseif sp.spot == "below" then
                line = fw - (sp.grow == "right" and box.belowInL or box.belowInR)
            end
            -- Paired, the buffs take what their rows need, up to half, and the
            -- debuffs the rest: they're bigger and matter more.
            if paired and line then
                local full = fw - box[sp.spot .. "InL"] - box[sp.spot .. "InR"]
                if kind == "buff" then
                    local s, gap = rowDims(set, "buff")
                    local per = math.ceil(total(set.want.buff) / math.max(1, set.rows and set.rows.buff or 1))
                    buffLine = math.min(math.floor(full / 2) - Auras.GAP, per * (s[1] + gap) - gap)
                    line = buffLine
                else
                    line = full - buffLine - 2 * Auras.GAP
                end
            end
            local L = ns.Spots.Layout(sp.spot, sp.grow, box, { x = sp.x, y = sp.y, line = line })
            line = math.max(rowDims(set, kind)[1], L.line)
            -- The time sits on each icon's top edge, so leave room for it under the frame.
            if side == "below" then L.y = L.y - (textOf(c, kind)) * 0.6 end
            set[kind .. "Row"] = line
            Auras.Limit(set)
            Auras.SetFlow(c, L.flowAnchor, L.hDir, L.vDir, line)
            clear(c)
            put(c, L.point, frame, L.relPoint, L.x, L.y)
            size(c, line, rowDims(set, kind)[2])
            set.flow[kind] = L
            if paired then
                pairTall = math.max(pairTall, Auras.Height(set, kind))
            elseif side == "above" then
                up = up + Auras.Height(set, kind) + Auras.GAP
            elseif side == "below" then
                down = down + Auras.Height(set, kind) + Auras.GAP
            end
            if side then any[side] = true end
        end
    end
    if paired and sideOf(sb.spot) == "above" then up = up + pairTall + Auras.GAP end
    if paired and sideOf(sb.spot) == "below" then down = down + pairTall + Auras.GAP end
    local top = any.above and Auras.GAP + up or 0
    local bottom = any.below and down or 0

    if set.sample then Auras.ShowSample(set, frame, set.sample.cfg, set.sample.list) end
    return top, bottom
end

-- Test mode: sample auras in the same look, where the real ones go. The
-- client's containers only show a unit's real auras, so the samples are plain
-- icons on a holder placed where the container is (the container is hidden by
-- alpha meanwhile).

local holders = setmetatable({}, { __mode = "k" })  -- container -> sample holder

-- The holder for a container, placed by the container's own points (another
-- container among them is swapped for its holder).
local function holderFor(c)
    local h = holders[c]
    if not h then
        h = CreateFrame("Frame", nil, c:GetParent())
        h.pool = {}
        holders[c] = h
    end
    local s = spots[c]
    h:ClearAllPoints()
    if s then
        for _, p in ipairs(s.points or {}) do
            local rel = p[2]
            if spots[rel] then rel = holderFor(rel) end
            h:SetPoint(p[1], rel, p[3], p[4], p[5])
        end
        h:SetSize(s.w or 1, s.h or 1)
    end
    return h
end

local function sampleButton(parent, kind)
    local btn = CreateFrame("Frame", nil, parent)
    btn.kind = kind
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.shade = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    btn.shade:SetTexture(DUI.MEDIA .. "inner-shadow.png")
    btn.shade:SetVertexColor(0, 0, 0, 1)
    btn.shade:SetAllPoints(btn.icon)
    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints(btn.icon)
    btn.cd:SetDrawEdge(false)
    btn.cd:SetHideCountdownNumbers(true)
    btn.cd:EnableMouse(false)
    Auras.StyleSwipe(btn.cd, false)
    btn.timeSize, btn.countSize = textOf(nil, kind)
    btn.time = Style.Text(btn, btn.timeSize, "CENTER")
    btn.time:SetPoint("CENTER", btn, "TOP", 0, 0)
    local c = Auras.TIME_COLOR
    btn.time:SetTextColor(c[1], c[2], c[3])
    btn.count = Style.Text(btn, btn.countSize, "RIGHT")
    btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    if HALO_KINDS[kind] or kind == "debuff" then
        btn.halo = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        btn.halo:SetTexture(Style.AURA_HALO)
        btn.halo:SetBlendMode("ADD")
    end
    if BUFF_KINDS[kind] then
        Style.Shell(btn, { noBackground = true, noBevel = true, borderPx = Auras.BORDER_PX, lean = true })
    else
        btn.edge = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        btn.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
        btn.edge:SetAllPoints(btn)
    end
    return btn
end

-- A sample's sweep frozen at left (the fraction of time left, nil for none):
-- a long cooldown started that far back barely moves.
Auras.SAMPLE_SWIPE_SPAN = 3600
function Auras.ShowSampleSwipe(btn, left)
    Auras.StyleSwipe(btn.cd, left ~= nil and left ~= false)
    if not left then btn.cd:Hide() return end
    local span = Auras.SAMPLE_SWIPE_SPAN
    btn.cd:SetCooldown(GetTime() - (1 - left) * span, span)
    btn.cd:Show()
end

local function fitSample(btn, s, sample, c)
    btn:SetSize(s[1], s[2])
    local time, count = textOf(c, btn.kind)
    if btn.timeSize ~= time then btn.timeSize = time; Style.SetTextSize(btn.time, time) end
    if btn.countSize ~= count then btn.countSize = count; Style.SetTextSize(btn.count, count) end
    local T = Pixel.Px(btn, Auras.BORDER_PX)
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", T, -T)
    btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -T, T)
    btn.icon:SetTexCoord(iconCoords(s[1], s[2]))
    btn.icon:SetTexture(sample.icon)
    btn.time:SetText(sample.time or "")
    btn.count:SetText(sample.count or "")
    if btn.edge then
        local col = Auras.DISPEL_COLORS[sample.dispel or "None"] or Auras.DEBUFF_BORDER
        btn.edge:SetVertexColor(Style.Soften(col[1], col[2], col[3]))
    end
    if btn.halo then
        -- A buff you can purge, or a debuff you can dispel (sample.cure).
        local glow = sample.purge or (sample.cure and sample.dispel)
        local col = Auras.DISPEL_COLORS[glow or "Magic"] or Auras.DISPEL_COLORS.Magic
        btn.halo:SetVertexColor(Style.Soften(col[1], col[2], col[3]))
        btn.halo:SetShown(glow ~= nil)
        Style.PlaceAuraHalo(btn.halo, btn, s[1])
    end
end

-- n samples in rows from the outer end inward. vert is the edge rows start from
-- ("BOTTOM" stacks up, "TOP" down), matching how the container lays out real ones.
-- cfg, when given: the row's time numbers and sweep follow its settings.
local function showRow(c, kind, list, n, perRow, outer, dir, vert, cfg)
    local h = holderFor(c)
    local s, gap = dimsOf(c, kind)
    local vdir = vert == "BOTTOM" and 1 or -1
    for i = 1, n do
        local btn = h.pool[i] or sampleButton(h, kind)
        h.pool[i] = btn
        fitSample(btn, s, list[i], c)
        if cfg then
            btn.time:SetShown(cfg[kind .. "Timers"] ~= false and not (cfg[kind .. "ShortTimers"] and list[i].long))
            Auras.ShowSampleSwipe(btn, cfg[kind .. "Swipe"] == true and (list[i].left or 0.5))
        end
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        btn:ClearAllPoints()
        btn:SetPoint(vert .. outer, h, vert .. outer, dir * col * (s[1] + gap), vdir * row * (s[2] + gap + 4))
        btn:Show()
    end
    for i = n + 1, #h.pool do h.pool[i]:Hide() end
    h:Show()
    c:SetAlpha(0)
end

local function hideRow(c)
    if not c then return end
    local h = holders[c]
    if h then h:Hide() end
    c:SetAlpha(1)
end
Auras.HolderFor = function(c) return holders[c] end

-- Sample icons drawn on a stand-in (Auras.Plain) the way the client lays out
-- real ones: from flow.anchor, running flow.hDir then flow.vDir, flow.perRow
-- per row, at the stand-in's own size (Auras.SetOwnSize). The stand-in takes
-- the block's size, like a container sizing itself to its icons, so a middle
-- point keeps the block centered. Returns its w, h.
function Auras.DrawSample(c, list, n, kind, flow)
    c.pool = c.pool or {}
    local s, gap = dimsOf(c, kind)
    local per = math.max(1, flow.perRow or n)
    local sx, sy = flow.hDir == "Left" and -1 or 1, flow.vDir == "Up" and 1 or -1
    for i = 1, n do
        local btn = c.pool[i] or sampleButton(c, kind)
        c.pool[i] = btn
        fitSample(btn, s, list[i], c)
        btn.time:SetShown(flow.timers ~= false and not (flow.shortTimers and list[i].long))
        btn.count:SetShown(flow.counts ~= false)
        Auras.ShowSampleSwipe(btn, flow.swipe == true and list[i].left)
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        btn:ClearAllPoints()
        btn:SetPoint(flow.anchor, c, flow.anchor, sx * col * (s[1] + gap), sy * row * (s[2] + gap + 4))
        btn:Show()
    end
    for i = n + 1, #c.pool do c.pool[i]:Hide() end
    local cols, rows = math.min(n, per), math.ceil(n / per)
    local w = math.max(1, cols * (s[1] + gap) - gap)
    local h = math.max(1, rows * s[2] + (rows - 1) * (gap + 4))
    c:SetSize(w, h)
    c:SetShown(n > 0)
    return w, h
end

-- samples: { debuffs = { { icon, time, count?, dispel? }, ... }, buffs = { ... } }.
function Auras.ShowSample(set, frame, cfg, samples)
    if not set then return end
    set.sample = { cfg = cfg, list = samples }
    local left = set.side == "left"
    local outer, dir = left and "RIGHT" or "LEFT", left and -1 or 1
    -- A row filtered to what you can dispel or purge shows only those samples.
    local function only(list, field)
        local out = {}
        for _, a in ipairs(list) do if a[field] then out[#out + 1] = a end end
        return out
    end
    local debuffList, buffList = samples.debuffs, samples.buffs
    if set.side == "right" and cfg.debuffFilter == "dispel" then debuffList = only(debuffList, "cure") end
    if cfg.buffFilter == "purge" then buffList = only(buffList, "purge") end
    local nd = 0
    if cfg.debuffs then
        local got = capCounts(set, "debuff", { cfg.maxDebuffs,
            cfg.debuffFilter == "all" and cfg.maxOtherDebuffs or 0 }, cfg.debuffRows)
        nd = math.min(#debuffList, got[1] + got[2])
    end
    -- Each row's samples run the way Place laid out the row: from its flow's
    -- corner, across, then up or down.
    local function flowOf(kind, vert)
        local L = set.flow and set.flow[kind]
        if not L then return outer, dir, vert end
        local left = L.hDir == "Left"
        return left and "RIGHT" or "LEFT", left and -1 or 1, L.vDir == "Up" and "BOTTOM" or "TOP"
    end
    local o, d, v = flowOf("debuff", "BOTTOM")
    showRow(set.debuffs, "debuff", debuffList, nd, perRowOf(set, "debuff"), o, d, v, cfg)
    if set.buffs then
        local nb = cfg.buffs and math.min(#buffList,
            capCounts(set, "buff", { cfg.maxBuffs }, cfg.buffRows)[1]) or 0
        o, d, v = flowOf("buff", "TOP")
        showRow(set.buffs, "buff", buffList, nb, perRowOf(set, "buff"), o, d, v, cfg)
    end
end

function Auras.HideSample(set)
    if not set or not set.sample then return end
    set.sample = nil
    hideRow(set.debuffs)
    hideRow(set.buffs)
end
