-- Live preview on the nameplate options pages, drawn above each page's settings
-- by Options/SampleStrip.lua like the unit frame pages. It's a real plate built
-- by the same code but never given a unit. An enemy target carries every piece
-- (outline, combo points, a cast, your debuffs, crowd control, a purgeable buff);
-- the Friendly page shows a friendly player. It's laid out from the current
-- settings on every redraw, so changes show at once. Clicking a piece jumps to
-- its settings; in Design mode dragging moves it to another spot around the bar
-- and its grips resize it. Nothing here touches the real plates.
--
-- A sample has: s.frame (its box), s.Refresh(width, maxHeight) -> height used,
-- s.Parts() -> { { region, label, keys, scale, move, size }, ... } for visible
-- pieces, s.missing (visible pieces with no setting on any nameplate page; the
-- tests keep it empty), s.Zoom/SetZoom/zoomRange (the strip's Zoom slider), and
-- s.Views/SetView (the strip's view chips, e.g. the enemy in execute range).
--
-- Loaded after Options.lua; it attaches a sample to every page.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local L = DUI.L
local Plate, Cast, Auras, Combo, Power = ns.Plate, ns.Cast, ns.Auras, ns.Combo, ns.Power

local Sample = {}
ns.Sample = Sample

Sample.PAD = 6 -- padding around the plate
Sample.ZOOM_MIN, Sample.ZOOM_MAX, Sample.ZOOM_STEP = 1, 4, 0.5
Sample.zoom = 1 -- the strip's Zoom, shared by every nameplate page for the session
Sample.inExecute = false -- "Execute range" chip: enemy at that health with the band lit (every page, for the session)
Sample.threatView = "aggro" -- Threat page chips: which threat state to show (Plate.ThreatState's)
Sample.THREAT_VIEWS = { -- chips are laid from the right; keep them short or they cover the aura rows
    { key = "lost", label = "Lost" },
    { key = "warn", label = "Switching" },
    { key = "aggro", label = "On you" },
}
-- Threat % shown per state (other pages use the calm "lost" one).
Sample.THREAT_PCT = { lost = 45, warn = 92, aggro = 100 }

Sample.friendView = "player" -- Friendly page chips: a player (with guild) or an NPC (with title)
Sample.FRIEND_VIEWS = {
    { key = "npc", label = "NPC" },
    { key = "player", label = "Player" },
}

Sample.enemyLine = nil -- Health & Names page chips: "guild" or "job" under the enemy's name, nil for neither
Sample.ENEMY_LINES = {
    { key = "job", label = "Job" },
    { key = "guild", label = "Guild" },
}

Sample.enemyKind = nil -- same page: show the enemy as a boss, rare or caster (each while its color is on)
Sample.ENEMY_KINDS = {
    { key = "boss", label = "Boss", on = "bossBar" },
    { key = "rare", label = "Rare", on = "rareBar" },
    { key = "quest", label = "Quest", on = "questBar" },
    { key = "caster", label = "Caster", on = "casterBar" },
}
-- What each choice makes the enemy: its kind (as Plate.MobKind returns) and how
-- the game would show it.
Sample.KIND_AS = {
    boss = { kind = "boss", classification = "worldboss", level = -1 },
    rare = { kind = "rare", classification = "rare" },
    quest = { kind = "quest" },
    caster = { kind = "caster" },
}

-- The sample units. The enemy is your target; the friend is a player, or an NPC
-- with the Friendly page's chip.
local I = "Interface\\Icons\\"
Sample.ENEMY = {
    name = "Sadeas", key = "HOSTILE", reaction = 2, level = 27, classification = "elite", health = 62, healthValue = 3120,
    heals = 8, absorbs = 6, dots = 24, marker = 8, quest = "4/10", combo = 3,
    power = 70, powerToken = "MANA", -- a caster, so the power bar shows whatever its setting
    cast = { text = L["Shadow Bolt"], icon = I .. "Spell_Shadow_ShadowBolt", value = 0.35, time = "1.4", kick = 0.7 },
    debuffs = {
        { icon = I .. "Spell_Shadow_ShadowWordPain", time = "14s", dispel = "Magic" },
        { icon = I .. "Spell_Shadow_CurseOfSargeras", time = "22s", dispel = "Curse" },
        { icon = I .. "Ability_Gouge", time = "9s", count = 3, dispel = "Bleed" },
    },
    cc = { { icon = I .. "Spell_Nature_Polymorph", time = "6s", dispel = "Magic" } },
    buffs = { { icon = I .. "Spell_Holy_PowerWordShield", time = "19s", dispel = "Magic" } },
}
Sample.FRIEND = {
    name = "Navani", class = "PRIEST", key = "PRIEST", reaction = 5, guild = "Bridge Four", level = 25, health = 90, healthValue = 1840,
    party = true, -- in your group, so Group names applies to her
    heals = 6, absorbs = 0, power = 55, powerToken = "MANA",
    helps = {
        { icon = I .. "Spell_Holy_Renew", time = "12s" },
        { icon = I .. "Spell_Holy_WordFortitude", time = "29m" },
    },
}
-- The enemy with a line under its name, otherwise the same.
Sample.ENEMY_AS = {
    guild = setmetatable({ guild = "Sons of Honor", class = "WARRIOR", key = "WARRIOR", otherFaction = true }, { __index = Sample.ENEMY }),
    job = setmetatable({ job = "Quartermaster" }, { __index = Sample.ENEMY }),
}
Sample.FRIEND_NPC = {
    name = "Rock", key = "FRIENDLY", reaction = 5, job = "Innkeeper", level = 25, health = 100, healthValue = 1840,
    heals = 0, absorbs = 0,
}

-- ---------------------------------------------------------------------
-- Pieces: where each sits on the sample plate, and its settings
-- ---------------------------------------------------------------------

local NONE_KEYS = {}

local function at(field) return function(p) return p[field] end end

-- A stand-in aura row's visible icons.
local function rowIcons(what)
    return function(p)
        local row = p.sampleAuras and p.sampleAuras[what]
        if not (row and row:IsShown()) then return nil end
        local out = {}
        for _, btn in ipairs(row.icons) do
            if btn:IsShown() then out[#out + 1] = btn end
        end
        return out
    end
end

-- Each piece in draw order (where pieces overlap, the later one gets the click).
-- keys: its settings on any nameplate page (each page keeps the ones it has).
-- move: what a Design mode drag writes (spot, x, y). outside: only spots around
-- the bar; only: just these spots; home(p): a single dot, nudges only; owner(p),
-- box(p): the frame and Spots box its dots surround instead of the health bar;
-- still(p): can't move on this plate.
-- size: the sliders a grip writes, w and h or s.
-- Each is a list of keys; the first one the page has wins (enemy or friendly).
local function spotKeys(prefix, friendly)
    return function(field)
        local list = { prefix .. field }
        if friendly then list[2] = "friendly." .. prefix .. field end
        return list
    end
end
local NAME, QUEST, MARK = spotKeys("name", true), spotKeys("quest"), spotKeys("marker")
local DEBUFF, CC, BUFF, MYBUFF = spotKeys("debuff"), spotKeys("cc"), spotKeys("buff"), spotKeys("friendly.myBuff")
local SKULL, PERCENT, LEVEL = spotKeys("dotSkull"), spotKeys("percent", true), spotKeys("level", true)
local THREATPCT = spotKeys("threatPct")
local function nameStill(p) return Plate.NameOnly(p, Plate.Cfg(p)) end
local NAME_MOVE = { spot = NAME("Pos"), x = NAME("X"), y = NAME("Y"), still = nameStill }
-- The cast bar's own dot: its center where it sits with no nudge.
local function castHome(p)
    return { spot = "home", x = p.hp:GetWidth() / 2,
             y = p.hp:GetHeight() + Cast.GAP + Combo.Drop(p) + Power.Drop(p) + p.cast:GetHeight() / 2 }
end
local function castOf(p) return p.cast end
local function castBox(p) return { w = p.cast:GetWidth(), h = p.cast:GetHeight(), padX = 0, padY = 0 } end
Sample.PARTS = {
    { label = "Health bar", at = at("hp"),
      keys = { "width", "height", "slant", "scale", "media.health", "healthColor", "healthCustom",
               "bossBar", "bossColor", "rareBar", "rareColor", "questBar", "questColor", "casterBar", "casterColor",
               "predictHeals", "predictAbsorbs", "dotTint", "execute", "executePct", "executeStyle",
               "threat", "threatBar", "threatBorder", "threatGlow", "threatPulse", "threatFill",
               "threatAggro", "threatWarn", "threatLost",
               "targetStyle", "targetAccent", "targetOutline", "targetGlow", "dimOthers",
               "targetScale", "target.width", "target.height", "target.scale",
               "friendly.enabled", "friendly.width", "friendly.height", "friendly.healthColor", "friendly.healthCustom" },
      size = { w = { "width", "friendly.width" }, h = { "height", "friendly.height" } } },
    { label = "Health text", at = at("percent"),
      keys = { "percent", "healthFormat", "healthSize", "media.healthFont",
               "friendly.percent", "friendly.healthFormat", "friendly.healthSize",
               "percentPos", "percentX", "percentY", "friendly.percentPos", "friendly.percentX", "friendly.percentY" },
      move = { spot = PERCENT("Pos"), x = PERCENT("X"), y = PERCENT("Y") } },
    { label = "Level", at = at("level"),
      keys = { "level", "levelColor", "levelCustom", "levelSize", "media.levelFont", "friendly.level", "levelPos", "levelX", "levelY",
               "friendly.levelPos", "friendly.levelX", "friendly.levelY" },
      move = { spot = LEVEL("Pos"), x = LEVEL("X"), y = LEVEL("Y") },
      size = { s = { "levelSize" } } },
    { label = "Threat %", at = at("threatPct"),
      keys = { "threatPct", "threatPctColor", "threatPctCustom", "threatPctSize", "media.threatPctFont",
               "threatPctPos", "threatPctX", "threatPctY" },
      move = { spot = THREATPCT("Pos"), x = THREATPCT("X"), y = THREATPCT("Y") },
      size = { s = { "threatPctSize" } } },
    { label = "Name", at = at("name"),
      keys = { "nameSize", "nameColor", "factionIcon", "media.nameFont", "lastNames.nameplates", "namePos", "nameX", "nameY",
               "friendly.nameSize", "friendly.nameColor", "friendly.namePlayer", "friendly.nameNpc", "friendly.nameOther", "friendly.partyName", "friendly.partyCustom", "friendly.partyMark", "friendly.namePos", "friendly.nameX", "friendly.nameY" },
      move = NAME_MOVE,
      size = { s = { "nameSize", "friendly.nameSize" } } },
    { label = "Guild name", at = at("sub"), keys = { "guild", "role", "friendly.guild", "friendly.role",
        "guildColor", "guildCustom", "guildSize", "roleColor", "roleCustom", "roleSize",
        "friendly.guildColor", "friendly.guildCustom", "friendly.guildSize",
        "friendly.roleColor", "friendly.roleCustom", "friendly.roleSize" },
      move = NAME_MOVE }, -- hangs off the name, so they move together
    { label = "Quest mark", at = function(p) return { p.quest, p.questCount } end,
      keys = { "quest", "questCount", "questPos", "questX", "questY" },
      move = { spot = QUEST("Pos"), x = QUEST("X"), y = QUEST("Y") } },
    { label = "Raid marker", at = at("marker"), keys = { "markerSize", "markerPos", "markerX", "markerY" },
      move = { spot = MARK("Pos"), x = MARK("X"), y = MARK("Y") }, size = { s = { "markerSize" } } },
    { label = "DoT skull", at = at("dotSkull"), keys = { "dotSkull", "dotSkullPos", "dotSkullX", "dotSkullY" },
      move = { spot = SKULL("Pos"), x = SKULL("X"), y = SKULL("Y") } },
    { label = "Cast bar", at = at("cast"),
      keys = { "castHeight", "castFill", "castColor", "media.cast", "media.castFont",
               "castX", "castY" },
      move = { home = castHome, x = { "castX" }, y = { "castY" } },
      size = { h = { "castHeight" } } },
    { label = "Power bar", at = at("power"),
      keys = { "power", "powerShow", "powerHeight", "powerGap", "powerColor", "powerCustom", "media.power", "friendly.power" },
      size = { h = { "powerHeight" } } },
    { label = "Spell icon", at = function(p) return p.cast.iconBox end, keys = { "castIcon", "castIconPos" },
      move = { spot = { "castIconPos" }, only = { outleft = true, outright = true }, owner = castOf, box = castBox } },
    { label = "Combo points", at = at("comboRow"),
      keys = { "comboPoints", "comboPosition", "comboHeight", "comboWidth", "comboGap", "comboBorder", "comboSlant", "media.combo" },
      move = { spot = { "comboPosition" }, only = { above = true, below = true } },
      size = { h = { "comboHeight" } } },
    { label = "Your debuffs", at = rowIcons("debuffs"),
      keys = { "debuffs", "debuffSize", "maxDebuffs", "debuffSpot", "debuffGrow", "debuffX", "debuffY" },
      move = { spot = DEBUFF("Spot"), x = DEBUFF("X"), y = DEBUFF("Y"), outside = true }, size = { s = { "debuffSize" } } },
    { label = "Crowd control", at = rowIcons("cc"), keys = { "cc", "ccSize", "ccSpot", "ccX", "ccY" },
      move = { spot = CC("Spot"), x = CC("X"), y = CC("Y"), outside = true }, size = { s = { "ccSize" } } },
    { label = "Buffs", at = rowIcons("buffs"), keys = { "buffs", "buffSize", "maxBuffs", "buffSpot", "buffGrow", "buffX", "buffY" },
      move = { spot = BUFF("Spot"), x = BUFF("X"), y = BUFF("Y"), outside = true }, size = { s = { "buffSize" } } },
    { label = "Your buffs", at = rowIcons("helps"),
      keys = { "friendly.myBuffs", "friendly.myBuffSize", "friendly.maxMyBuffs",
               "friendly.myBuffSpot", "friendly.myBuffGrow", "friendly.myBuffX", "friendly.myBuffY" },
      move = { spot = MYBUFF("Spot"), x = MYBUFF("X"), y = MYBUFF("Y"), outside = true },
      size = { s = { "friendly.myBuffSize" } } },
}

-- A page's settings by key (pages don't change once registered), plus every key
-- on any nameplate page.
local pageKeys = {}
local function keysOn(id)
    if pageKeys[id] then return pageKeys[id] end
    local page = DUI.Options.GetPage("Nameplates." .. id)
    local set = {}
    for _, group in ipairs(page and page.groups or {}) do
        for _, item in ipairs(group.items) do
            if item.key then set[item.key] = item end
        end
    end
    if page then pageKeys[id] = set end
    return set
end

-- A setting's row on any nameplate page, or nil.
local function itemOf(key)
    for _, page in ipairs(ns.OPTIONS.pages) do
        local item = keysOn(page.id)[key]
        if item then return item end
    end
end

local function anyPage(key) return itemOf(key) ~= nil end

-- Which of keys a drag or grip writes: the page's own first, else the first on
-- any page (every page shows the same plate, so each piece moves and resizes on
-- all of them), or the friendly plate's own on a friendly plate. Returns key, row.
local function pick(keys, have, p)
    for _, key in ipairs(keys or NONE_KEYS) do
        if type(have[key]) == "table" then return key, have[key] end
    end
    for pass = 1, 2 do
        for _, key in ipairs(keys or NONE_KEYS) do
            local mine = (key:find("^friendly%.") ~= nil) == (p.friendly == true)
            local item = (pass == 2 or mine) and itemOf(key)
            if item then return key, item end
        end
    end
end

-- A grip's new value: start plus the pixels dragged, snapped to the slider's
-- steps and limits.
function Sample.Resize(start, delta, min, max, step)
    step = step or 1
    local v = math.floor((start + delta) / step + 0.5) * step
    return math.max(min, math.min(max, v))
end

-- How a piece resizes on this page: { keys = { w, h } or { s }, min, max, step,
-- now, resize } for the strip's grips, or nil.
local function sizeOf(part, have, p)
    local z = part.size
    if not z then return nil end
    local out = { keys = {}, min = {}, max = {}, step = {}, now = {}, resize = Sample.Resize }
    local any
    for _, kind in ipairs({ "w", "h", "s" }) do
        local key, item = pick(z[kind], have, p)
        if key and item.type == "slider" then
            out.keys[kind], out.min[kind], out.max[kind], out.step[kind] = key, item.min, item.max, item.step or 1
            out.now[kind] = DUI:Get("Nameplates", key)
            any = true
        end
    end
    if not any then return nil end
    if out.keys.s then out.min, out.max, out.step = out.min.s, out.max.s, out.step.s end
    return out
end

-- How a piece moves: { spotKey, xKey, yKey, owner (the health bar), dots (bar px
-- from its top left, y down), drop(x, y) -> spot, x, y } for the strip's drag, or nil.
local function moveOf(part, have, p)
    local m = part.move
    if not m or (m.still and m.still(p)) then return nil end
    local spotKey = pick(m.spot, have, p)
    if not spotKey and not m.home then return nil end
    local dots = {}
    if m.home then
        dots[1] = m.home(p)
    else
        for _, d in ipairs(DUI.Spots.Dots(m.box and m.box(p) or Plate.SpotBox(p))) do
            if (not m.outside or Plate.OUTSIDE[d.spot]) and (not m.only or m.only[d.spot]) then
                dots[#dots + 1] = d
            end
        end
    end
    return { spotKey = spotKey, xKey = (pick(m.x, have, p)), yKey = (pick(m.y, have, p)),
             owner = m.owner and m.owner(p) or p.hp, dots = dots,
             drop = function(x, y) return DUI.Spots.Drop(dots, x, y) end }
end

-- Adds a piece's spots to out: each visible region, with this page's settings for
-- it. Visible with no setting on any nameplate page: missing. scale is the
-- plate's, for sizing spots over text.
local function collect(out, missing, part, p, id, scale)
    local found = part.at(p)
    if found == nil then return end
    if found.GetObjectType then found = { found } end
    local regions = {}
    for _, r in ipairs(found) do
        if r:IsVisible() then regions[#regions + 1] = r end
    end
    if #regions == 0 then return end
    local have, keys, known = keysOn(id), {}, false
    for _, key in ipairs(part.keys) do
        if have[key] then keys[#keys + 1] = key end
        known = known or anyPage(key)
    end
    if not known then missing[#missing + 1] = part.label end
    -- A piece whose settings live on another page has nothing to jump to here, but in
    -- Design mode it still moves and resizes.
    local size, move = sizeOf(part, have, p), moveOf(part, have, p)
    if #keys == 0 and not (size or move) then return end
    for _, r in ipairs(regions) do
        out[#out + 1] = { region = r, label = part.label, keys = keys, scale = scale, move = move, size = size }
    end
end

-- ---------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------

local NONE = {}

-- The first n items of a list.
local function first(list, n)
    local out = {}
    for i = 1, math.min(#list, tonumber(n) or #list) do out[i] = list[i] end
    return out
end

-- Health bar color, as Plate.UpdateBarColor paints a real unit: class or
-- reaction, a single color, by health, or the unit's gradient pair, with a threat
-- color on top (t, when shown on the bar).
local function paintBar(p, c, u, pct, t)
    local bar = p.health
    local onBar = t ~= nil and c.threatBar
    local r, g, b
    if u.class then r, g, b = Style.ClassColor(u.class) else r, g, b = Style.ReactionColor(u.reaction) end
    if c.healthColor == "custom" then r, g, b = Style.Soften(c.healthCustom[1], c.healthCustom[2], c.healthCustom[3]) end
    if onBar then r, g, b = Style.Soften(t[1], t[2], t[3]) end
    Style.SetBarColor(bar, r, g, b)
    if c.healthColor == "gradient" and not onBar and not (u.kind and c[Plate.KIND_COLOR[u.kind]]) then
        Style.SetBarColor(bar, DUI.Health.GradientAt(pct / 100))
    end
    -- Boss, rare or caster in its own color (Plate.MobKind), threat over it.
    local kc = u.kind and not onBar and c[Plate.KIND_COLOR[u.kind]] or nil
    if kc then
        Style.SetBarColor(bar, Style.Soften(kc[1], kc[2], kc[3]))
        Plate.PaintKindBar(bar, c, kc)
    end
    if c.healthColor == "classGradient" and not onBar and not kc then DUI.Gradients.Paint(bar, u.key) end
    if onBar then Plate.PaintThreatBar(p, c) end
    Plate.PaintClassLayers(p, nil, nil)
end

-- Name in its color (as Plate.UpdateNameColor), plus the guild line.
local function paintNames(p, c, u)
    local name = u.name
    if u.party and c.partyName == true then
        local t = c.partyCustom
        p.name:SetTextColor(t[1], t[2], t[3])
    elseif c.nameColor == "white" then
        Style.InkText(p.name, "VALUE")
    elseif c.nameColor == "custom" then
        local t = Plate.CustomNameColor(c, u.class ~= nil, u.otherFaction == true)
        p.name:SetTextColor(t[1], t[2], t[3])
    elseif c.nameColor == "classGradient" then
        p.name:SetTextColor(1, 1, 1) -- the letters carry their own colors
        name = DUI.Gradients.Text(u.key, name)
    elseif u.class and c.nameColor ~= "reaction" then
        p.name:SetTextColor(Style.ClassTextColor(u.class))
    else
        local r, g, b = Style.ReactionColor(u.reaction)
        p.name:SetTextColor(Style.Lighten(r, g, b, Plate.NAME_LIGHTEN))
    end
    p.name:SetText(name)
    Plate.ShowGroupMark(p, u.party == true and (c.partyMark or "none") ~= "none")
    -- An enemy player represents the other faction (factionIcon).
    local other
    if u.otherFaction and c.factionIcon == true then
        other = Plate.Plain(UnitFactionGroup, "player") == "Alliance" and "Horde" or "Alliance"
    end
    Plate.ShowFaction(p, other)
    local guild = u.guild ~= nil and c.guild == true
    local job = u.job ~= nil and c.role == true
    p.subJob = u.job ~= nil
    Plate.SizeSub(p, c)
    if guild then
        p.sub:SetFormattedText("<%s>", u.guild)
        if not Plate.PaintSub(p, c.guildColor, c.guildCustom) then
            p.sub:SetTextColor(Style.ClassTextColor(u.class))
        end
    elseif job then
        p.sub:SetText(L[u.job])
        if not Plate.PaintSub(p, c.roleColor, c.roleCustom) then Style.InkText(p.sub, "LABEL") end
    end
    p.sub:SetShown(guild or job)
    Plate.PlaceSpots(p)
end

-- Quest mark and count, and the raid marker past them (enemies).
local function paintMarks(p, c, u, friendly)
    local quest = not friendly and c.quest == true
    p.quest:SetShown(quest)
    p.questCount:SetText(u.quest or "")
    p.questCount:SetShown(quest and c.questCount == true)
    if friendly then
        p.marker:Hide()
    else
        p.marker:SetSpriteSheetCell(u.marker, Plate.MARKER_ROWS, Plate.MARKER_COLS)
        p.marker:Show()
    end
    Plate.PlaceSpots(p)
end

-- How far the plate's pieces extend past its health bar (up, down, left, right,
-- in its own units): name, marks and aura rows where Plate.PlaceSpots put them
-- (p.spotReach), the cast bar below, and a glow around it.
local function reach(p, c)
    local r = p.spotReach or NONE
    local up, down = r.up or 0, r.down or 0
    local left, right = math.max(10, r.left or 0), math.max(10, r.right or 0) -- the name is the bar's width plus 20
    local cast = p.cast
    if cast:IsShown() then
        local cx, cy = tonumber(c.castX) or 0, tonumber(c.castY) or 0
        local top = Cast.GAP + Combo.Drop(p) + Power.Drop(p) -- below the bar's bottom edge, no nudge
        down = math.max(down, top + c.castHeight - cy)
        up = math.max(up, cy - top - p.hp:GetHeight())
        local onLeft, onRight = math.max(0, -cx), math.max(0, cx)
        if cast.iconBox:IsShown() then
            local room = Cast.ICON_GAP + c.castHeight
            if c.castIconPos == "outright" then onRight = onRight + room else onLeft = onLeft + room end
        end
        left, right = math.max(left, onLeft), math.max(right, onRight)
    else
        down = math.max(down, Combo.Drop(p) + Power.Drop(p))
    end
    if p.glow:IsShown() or p.threatGlow:IsShown() then
        local g = Plate.GLOW_REACH
        up, down, left, right = math.max(up, g), math.max(down, g), math.max(left, g), math.max(right, g)
    end
    return up, down, left, right
end

-- Fits the plate into width by at most maxH: drawn at its size times the strip's
-- Zoom (and its own Scale), shrunk to fit, centered in the box. Returns the
-- height used.
local function fit(s, grow, width, maxH)
    local p = s.p
    local w, h = p.hp:GetWidth(), p.hp:GetHeight()
    local up, down, left, right = reach(p, Plate.Cfg(p))
    local pad = Sample.PAD
    local cw, ch = w + left + right + 2 * pad, h + up + down + 2 * pad
    local scale = math.min(grow, width / cw, maxH / ch)
    p:SetScale(scale)
    p:ClearAllPoints()
    p:SetPoint("CENTER", s.frame, "CENTER", (left - right) / 2, (down - up) / 2)
    local used = math.min(maxH, math.ceil(ch * scale))
    s.frame:SetSize(width, used)
    return used
end

local function refresh(s, width, maxH)
    local c = ns.cfg
    if not c then return 0 end
    local p = s.p
    local friendly = s.id == "friendly"
    local u = Sample.ENEMY
    if friendly then
        u = Sample.friendView == "npc" and Sample.FRIEND_NPC or Sample.FRIEND
    elseif s.id == "bars" and Sample.enemyLine then
        u = Sample.ENEMY_AS[Sample.enemyLine]
    end
    -- As a boss, rare or caster while that chip is selected and its color is on.
    local kind = s.id == "bars" and Sample.enemyKind
    if kind and c[kind .. "Bar"] == true then
        local as = {}
        for k, v in pairs(Sample.KIND_AS[kind]) do as[k] = v end
        u = setmetatable(as, { __index = u })
    end
    p.friendly, p.sampleTarget = friendly, not friendly
    local pc = Plate.Cfg(p)
    p.sizeGroup = (not friendly and c.targetScale) and "target" or nil
    -- The Threat page shows the size of the state its chips picked.
    if s.id == "threat" and not friendly and c.threatSize == true then p.sizeGroup = Sample.threatView end
    -- Combo points go before the layout since they move the cast bar or name. Only
    -- shown when you play a combo class (rogue, druid), as in game.
    local combo = not friendly and c.comboPoints == true and Combo.Mine()
    if combo and not s.combo then s.combo = Combo.NewRow(p) end
    p.comboRow = combo and s.combo or nil
    -- Laid out fresh every time: dragging a grip changes settings without the real
    -- plates' refresh (Plate.gen).
    p.laid = nil
    p:SetScale(1)
    p:Show()
    Plate.Layout(p)
    -- Power bar before what sits under it (the cast bar drops below).
    Power.ShowSample(p, u)

    -- The bar: your target at its health, or in execute range while the strip's chip
    -- says so (band lit). Toggling the chip glides the fill; any other redraw sets it.
    local pct = u.health
    local exec = p.execOn and Plate.ExecutePct(p)
    if exec and Sample.inExecute then pct = math.max(5, math.floor(exec * 100 + 0.5) - 4) end
    local value = math.floor(u.healthValue * pct / u.health + 0.5)
    Style.SetBarRange(p.health, 0, 100)
    local glide = s.glide
    s.glide = nil
    if glide and DUI.Motion.On() then Style.GlideBar(p.health, pct) else Style.SetBarValue(p.health, pct, true) end
    for _, key in ipairs({ "heals", "absorbs" }) do
        local on = (key == "heals" and c.predictHeals or key == "absorbs" and c.predictAbsorbs) == true
        p[key]:SetMinMaxValues(0, 100)
        p[key]:SetValue(u[key] or 0)
        p[key]:SetShown(on)
        p[key .. "On"] = on
    end
    local tint, skull = not friendly and c.dotTint ~= false, not friendly and c.dotSkull ~= false
    DUI.Dots.PaintSample(tint and p.dotVeil or nil, skull and p.dotSkull or nil, 100, u.dots or 0, true)
    if not tint then p.dotVeil:Hide() end
    if not skull then p.dotSkull:Hide() end
    if exec and p.exec.hotTex then
        local tex, to = p.exec.hotTex, pct / 100 <= exec and 1 or 0
        if glide and DUI.Motion.On() then
            DUI.Motion.Tween(tex, tex:GetAlpha(), to, DUI.Motion.FAST, function(v) tex:SetAlpha(v) end)
        else
            tex:SetAlpha(to)
        end
    end
    if p.percent:IsShown() then DUI.Health.WriteSample(p.percent, pc.healthFormat or "percent", pct, value, true) end
    if p.level:IsShown() then Plate.PaintLevel(p, u.level, u.classification) end
    Plate.PaintDragon(p, u.classification)

    -- Threat shows on its own page, in the state the chips picked.
    local state = (s.id == "threat" and c.threat) and Sample.threatView or nil
    local t = Plate.ThreatColorOf(state)
    p.threatNow, p.threatState = t, state
    paintBar(p, pc, u, pct, t)
    Plate.ApplyThreatBorder(p, t)
    Plate.ApplyThreatGlow(p, t)
    Plate.ApplyThreatPulse(p, t)
    if p.threatPctOn then
        local view = s.id == "threat" and Sample.threatView or "lost"
        p.threatPct:SetFormattedText("%d%%", Sample.THREAT_PCT[view])
        Plate.PaintThreatPct(p.threatPct, c.threatPctColor or "threat", view)
        p.threatPct:SetAlpha(1)
        p.threatPct:Show()
    end
    p.hover:Hide()
    paintNames(p, pc, u)
    paintMarks(p, c, u, friendly)
    p.markStyle = nil -- repaint the mark from the settings
    Plate.UpdateTarget(p)
    Plate.ShowFocus(p, s.id == "target" and not friendly and c.groupFocus == true)

    Cast.ShowSample(p, not friendly and u.cast or nil)
    Auras.ShowSample(p, "debuffs", (not friendly and c.debuffs) and first(u.debuffs, c.maxDebuffs) or NONE)
    Auras.ShowSample(p, "cc", (not friendly and c.cc) and u.cc or NONE)
    Auras.ShowSample(p, "buffs", (not friendly and c.buffs) and first(u.buffs, c.maxBuffs) or NONE)
    Auras.ShowSample(p, "helps", (friendly and c.friendly.myBuffs) and first(u.helps, c.friendly.maxMyBuffs) or NONE)
    local row = p.comboRow
    if row then
        row:SetFrameLevel(p.hp:GetFrameLevel() + 2)
        Combo.Paint(row)
        Combo.LayoutRow(row, p)
        for _, pip in ipairs(row.pips) do
            pip.bar:SetValue(u.combo)
            pip.full:SetValue(u.combo)
        end
        row:Show()
    elseif s.combo then
        s.combo:Hide()
    end

    local group = Plate.SizeGroup(c, p.sizeGroup)
    local grow = Sample.zoom * (c.scale or 1) * (group and group.scale or 1)
    return fit(s, grow, width, maxH)
end

-- The live sample for a nameplate page (its id: "plates", "target", ...,
-- "friendly"), on parent.
function Sample.New(id, parent)
    local s = { id = id, missing = {} }
    s.frame = CreateFrame("Frame", nil, parent)
    s.p = Plate.Create(s.frame, true)
    s.p:EnableMouse(false) -- display only; the strip's hotspots take the clicks
    -- Registered with the API as a preview while it shows (never looked up). Created
    -- once with no unit (no page's sample is a real unit, and the Friendly one isn't
    -- even an enemy), so showing it again is just a unit change, still to none.
    local function show()
        if s.p.apiSeen then DUI.APIReport.Back("nameplate", s.p)
        else s.p.apiSeen = true; DUI.APIReport.Made("nameplate", s.p, nil, true) end
    end
    s.frame:HookScript("OnShow", show)
    s.frame:HookScript("OnHide", function() DUI.APIReport.Gone("nameplate", s.p, true) end)
    if s.frame:IsVisible() then show() end
    function s.Zoom() return Sample.zoom end
    function s.SetZoom(v)
        v = tonumber(v) or 1
        Sample.zoom = math.max(Sample.ZOOM_MIN, math.min(Sample.ZOOM_MAX, v))
    end
    s.zoomRange = { min = Sample.ZOOM_MIN, max = Sample.ZOOM_MAX, step = Sample.ZOOM_STEP }
    -- The "Execute range" chip while that range shows on this plate. On the Threat
    -- page, one chip per threat state, one always selected.
    function s.Views()
        local list = {}
        if s.id == "threat" and (ns.cfg.threat or ns.cfg.threatPct or ns.cfg.threatSize) then
            for _, v in ipairs(Sample.THREAT_VIEWS) do
                list[#list + 1] = { key = v.key, label = L[v.label], on = Sample.threatView == v.key }
            end
        end
        if s.id == "friendly" then
            for _, v in ipairs(Sample.FRIEND_VIEWS) do
                list[#list + 1] = { key = v.key, label = L[v.label], on = Sample.friendView == v.key }
            end
        end
        if s.id == "bars" then
            for _, v in ipairs(Sample.ENEMY_LINES) do
                list[#list + 1] = { key = v.key, label = L[v.label], on = Sample.enemyLine == v.key }
            end
            for _, v in ipairs(Sample.ENEMY_KINDS) do
                if ns.cfg[v.on] == true then
                    list[#list + 1] = { key = v.key, label = L[v.label], on = Sample.enemyKind == v.key }
                end
            end
        end
        if s.id ~= "friendly" and s.p.execOn then
            list[#list + 1] = { key = "execute", label = L["Execute range"], on = Sample.inExecute }
        end
        return list
    end
    function s.SetView(key, on)
        if Plate.THREAT_KEY[key] then
            Sample.threatView = key
            return
        end
        if key == "player" or key == "npc" then
            Sample.friendView = key
            return
        end
        if key == "guild" or key == "job" then
            Sample.enemyLine = on and key or nil
            return
        end
        if Sample.KIND_AS[key] then
            Sample.enemyKind = on and key or nil
            return
        end
        if key ~= "execute" then return end
        Sample.inExecute = on == true
        s.glide = true
    end
    function s.Refresh(width, maxH) return refresh(s, width, maxH) end
    function s.Parts()
        local out, missing = {}, {}
        local scale = s.p:GetScale()
        for _, part in ipairs(Sample.PARTS) do collect(out, missing, part, s.p, id, scale) end
        s.missing = missing
        return out
    end
    return s
end

-- Every nameplate page shows it.
for _, page in ipairs(ns.OPTIONS.pages) do
    local id = page.id
    page.sample = function(parent) return Sample.New(id, parent) end
end
