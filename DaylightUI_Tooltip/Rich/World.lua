-- The rich cards for the world: a creature (its face, level in its difficulty
-- color, tags for how it reacts to you, what it is and whether it can be
-- skinned, its health, the quests it counts for, who it's targeting), a node
-- you gather from (your skill over a thin bar, in its skill-up color), and any
-- other thing in the world (a mailbox, a chest): its name and the game's lines.
--
-- Everything is read from the tooltip's own lines and the unit. In a fight a
-- creature is the fight pill (Rich.Build); with its lines secret (a dungeon)
-- its card comes from the unit alone.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style
local isSecret = DUI.IsSecret
local L = DUI.L

local World = {}
ns.RichWorld = World

World.ICON = 36
World.TITLE = Style.SIZE.head -- a creature's name, a size smaller than the title
World.ICON_GAP = 10
World.PAD_TOP = 16
World.TAG_GAP = 5       -- between the title and its tags
World.BEFORE_BAR = 12
World.NODE_PAD = 14     -- a node's card is tighter all round
World.SKILL_GAP = 8     -- its title, then your skill
World.SKILL_BAR_GAP = 5

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

local function hex(c) return DUI.Win.Parts.Hex(c) end

local function word(w, fallback) return type(w) == "string" and w ~= "" and w or fallback end

local function ownCount(data, n) return ns.Rich.Own(data, n) end

-- ---------------------------------------------------------------------
-- The game's words and colors
-- ---------------------------------------------------------------------

-- The words the game puts on a creature you can gather from, and the skill
-- each asks for (Skinning, Herbalism, Mining, Engineering by skill line).
World.SKIN = { UNIT_SKINNABLE_LEATHER = 393, UNIT_SKINNABLE_HERB = 182, UNIT_SKINNABLE_ROCK = 186,
               UNIT_SKINNABLE_BOLTS = 202 }

-- The game's own words for what the card reads and says, made once (English
-- when the client has none, as in the tests).
local words
function World.Words()
    if words then return words end
    local skin = {}
    for key, skill in pairs(World.SKIN) do
        local w = _G[key]
        if type(w) == "string" and w ~= "" then skin[w] = skill end
    end
    if not next(skin) then skin["Skinnable"] = World.SKIN.UNIT_SKINNABLE_LEATHER end
    words = {
        level = word(TOOLTIP_UNIT_LEVEL, "Level %s"),
        skin = skin,
        -- A lock you can open says only its skill's name; one you can't asks for it.
        needs = "^" .. DUI.GamePattern(word(LOCKED_WITH_SPELL, "Requires %s")) .. "$",
        needsRank = "^" .. DUI.GamePattern(word(ITEM_MIN_SKILL, "Requires %s (%d)")) .. "$",
        hostile = word(FACTION_STANDING_LABEL2, L["Hostile"]),
        neutral = word(FACTION_STANDING_LABEL4, L["Neutral"]),
        friendly = word(FACTION_STANDING_LABEL5, L["Friendly"]),
        elite = word(ELITE, L["Elite"]),
        rare = word(ITEM_QUALITY3_DESC, L["Rare"]),
        boss = word(BOSS, L["Boss"]),
    }
    return words
end

-- The game paints a level, a "Skinnable" line and a node's skill in its
-- difficulty colors: red (can't), orange, yellow, green, gray (nothing to
-- gain). The same meaning in the card's own colors; orange stays the game's.
function World.Ink(c)
    local INK = Style.INK
    if type(c) ~= "table" then return INK.VALUE end
    local r, g, b = c.r or c[1], c.g or c[2], c.b or c[3]
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return INK.VALUE end
    if r > 0.9 and g < 0.3 and b < 0.3 then return INK.BAD end
    if math.abs(r - g) < 0.1 and math.abs(g - b) < 0.1 then return r > 0.9 and INK.VALUE or INK.OFF end
    if g > r and g > b then return INK.GOOD end
    if r > 0.9 and g > 0.7 and b < 0.3 then return INK.WARN end
    return { r, g, b }
end

-- A color's pair as { dark, light }, for a bar or the top light.
local function pairOf(c)
    local lo, hi = DUI.Gradients.PairFrom(c)
    return { lo, hi }
end

-- Your skills by name (lower case) and by skill line: { name, rank, max }.
function World.Skills()
    local out = { byId = {} }
    local C = C_SkillInfo
    if type(C) ~= "table" or type(C.GetNumSkillLines) ~= "function" or type(C.GetSkillLineInfo) ~= "function" then
        return out
    end
    local count = plain(C.GetNumSkillLines())
    for i = 1, type(count) == "number" and count or 0 do
        local s = C.GetSkillLineInfo(i)
        if type(s) == "table" and plain(s.isHeader) ~= true then
            local name, rank, max = plain(s.name), plain(s.rank), plain(s.maxRank)
            if type(name) == "string" and type(rank) == "number" and type(max) == "number" and max > 1 then
                local skill = { name = name, rank = rank, max = max }
                out[name:lower()] = skill
                local id = plain(s.skillID)
                if type(id) == "number" then out.byId[id] = skill end
            end
        end
    end
    return out
end

-- The skill of yours a line names, and the rank it asks for when it says one:
-- "Herbalism", "Herbalism 125", "Requires Mining", "Requires Mining (65)", or
-- a corpse's "Skinnable".
function World.SkillIn(text, skills)
    local W = World.Words()
    if W.skin[text] then return skills.byId[W.skin[text]] end
    local s = skills[text:lower()]
    if s then return s end
    local name, need = text:match(W.needsRank)
    if not name then name, need = text:match("^(.-)%s+(%d+)$") end
    if name then
        s = skills[name:lower()]
        if s then return s, tonumber(need) end
    end
    name = text:match(W.needs)
    return name and skills[name:lower()] or nil
end

-- ---------------------------------------------------------------------
-- Lines the card doesn't lay out itself
-- ---------------------------------------------------------------------

-- The quest lines from 2 on: the game's own, then another addon's that
-- aren't a quest the game's lines already show (Rich/Foreign.lua's quest
-- adapter). taken: own lines the card has used. Returns the set of lines to
-- pass over when drawing them (Rich.Lines' skip) and whether there's any.
function World.Sort(p, lines, own, taken)
    local Rich = ns.Rich
    local notQuest, anyQuest = ns.RichForeign.QuestLines(p)
    for i = 2, own do
        local kind = not taken[i] and Rich.QuestLine(lines, i, own) or nil
        if kind then anyQuest = true else notQuest[i] = true end
    end
    return notQuest, anyQuest
end

-- In a restricted dungeon the tooltip's own lines are secret and the card is
-- built from the unit, but the quests it counts for are still in the data the
-- game filled it from (a nameplate reads the same lines there). Its quest
-- lines in order: plain ones as { left, type, id } for Rich.Lines, a secret
-- one as { secret = text, type }. A line whose type can't be read is left out.
local QUEST_KIND
function World.DataQuests(data)
    local out = {}
    local list = type(data) == "table" and data.lines or nil
    if isSecret(list) or type(list) ~= "table" then return out end
    local Rich = ns.Rich
    QUEST_KIND = QUEST_KIND or { [Rich.QUEST_TITLE] = true, [Rich.QUEST_OBJECTIVE] = true, [Rich.QUEST_PLAYER] = true }
    for _, line in ipairs(list) do
        local kind = not isSecret(line) and type(line) == "table" and line.type or nil
        if not isSecret(kind) and QUEST_KIND[kind] then
            local text, id = line.leftText, line.id
            if isSecret(text) then
                out[#out + 1] = { secret = text, type = kind }
            elseif type(text) == "string" and text ~= "" then
                if isSecret(id) or type(id) ~= "number" then id = nil end
                out[#out + 1] = { left = text, type = kind, id = id }
            end
        end
    end
    return out
end

-- Draws them: plain lines as the card's quest heading and rows, a secret one
-- as one line cut at the card's edge (it can't be read or measured).
function World.DrawDataQuests(p, quests)
    if #quests == 0 then return end
    local Rich, Panel, INK, SIZE = ns.Rich, ns.RichPanel, Style.INK, Style.SIZE
    -- The card's layout puts the line above the first.
    local plainRun, first = {}, true
    local function flush()
        if #plainRun > 0 then Rich.Lines(p, #plainRun, plainRun, 1, nil, first) end
        plainRun, first = {}, false
    end
    for _, q in ipairs(quests) do
        if q.secret ~= nil then
            flush()
            if q.type == Rich.QUEST_TITLE then
                local r, g, b = Style.Accent()
                Panel.Line(p, q.secret, { r, g, b }, SIZE.small)
            else
                Panel.Line(p, q.secret, q.type == Rich.QUEST_PLAYER and INK.LABEL or INK.TEXT, SIZE.small)
            end
        else
            plainRun[#plainRun + 1] = q
        end
    end
    flush()
end

-- One of the game's own lines the card has no place for, small: red stays a
-- warning, anything else is a tan fact.
local function fact(p, line)
    local Panel, INK, SIZE = ns.RichPanel, Style.INK, Style.SIZE
    local Bare = ns.Rich.Bare
    local c = line.hasLC and line.lc or nil
    local color = c and DUI.Tips.GameColor(c[1], c[2], c[3]) == "red" and INK.BAD or INK.LABEL
    if line.right then
        Panel.Row(p, line.left and Bare(line.left) or "", Bare(line.right), INK.TEXT, color, SIZE.small)
    else
        Panel.Text(p, Bare(line.left), color, SIZE.small)
    end
end

-- ---------------------------------------------------------------------
-- A creature
-- ---------------------------------------------------------------------

-- What kind of foe it is ("boss", "elite", "rare", "rareelite" or nil) and
-- the color that marks it: gold for an elite and silver for a rare, as the
-- game's own dragon frames are.
function World.Rank(unit)
    local class = plain(UnitClassification(unit))
    if class == "worldboss" then return "boss", Style.INK.BAD end
    if class == "elite" then return "elite", Style.INK.MONEY end
    if class == "rare" or class == "rareelite" then return class, World.RARE_COLOR end
    return nil
end

World.LEVEL_MARKS = { elite = "+", rare = "R", rareelite = "R+" }

-- Its level as the card shows it, and the color: how hard it is for you.
function World.Level(unit)
    local level = plain(UnitLevel(unit))
    if type(level) ~= "number" then return nil end
    if level <= 0 then return "??", Style.INK.BAD end
    -- How hard the unit is for you first; when the game can't say, a player's
    -- class color, then the unit's reaction.
    local c = DUI.LevelColor(unit, level)
    if c then return tostring(level), World.Ink(c) end
    if plain(UnitIsPlayer(unit)) == true then
        local _, token = UnitClass(unit)
        if type(token) == "string" and not isSecret(token) then return tostring(level), { Style.ClassTextColor(token) } end
    end
    local reaction = plain(UnitReaction(unit, "player"))
    if type(reaction) == "number" then return tostring(level), { Style.ReactionColor(reaction) } end
    return tostring(level), Style.INK.VALUE
end

-- The level as drawn: an elite's carries a gold "+", a rare's a silver "R"
-- ("R+" for a rare elite), so the pill in a fight tells it at a glance too.
-- Only for showing; the plain level finds the game's level line.
function World.LevelText(unit, text)
    if not text or text == "??" then return text end
    local rank, c = World.Rank(unit)
    local mark = rank and World.LEVEL_MARKS[rank]
    if mark then return text .. hex(c) .. mark .. "|r" end
    return text
end

-- Sorts a creature's own lines (2 to own): the level line is the header's,
-- a "Skinnable" line a tag in the color the game gave it, a line before the
-- level its title ("Innkeeper"), any other a fact.
function World.ReadMob(lines, own, level)
    local Bare, W = ns.Rich.Bare, World.Words()
    local r = { title = lines[1] and lines[1].left or "", tags = {}, facts = {}, taken = {}, lines = lines }
    local levelAt
    if level then
        local want = string.format(W.level, level)
        for i = 2, own do
            local t = lines[i].left
            if t and Bare(t):find(want, 1, true) then
                levelAt = i
                break
            end
        end
    end
    for i = 2, own do
        local line = lines[i]
        local t = line.left and Bare(line.left) or nil
        if i == levelAt then
            r.taken[i] = true
        elseif t and not line.right and W.skin[t] then
            r.tags[#r.tags + 1] = { t, World.Ink(line.hasLC and line.lc or nil) }
            r.taken[i] = true
        elseif levelAt and i < levelAt and t and not line.right then
            r.sub = r.sub and (r.sub .. L[" · "] .. t) or t
            r.taken[i] = true
        elseif (line.left or line.right) and not ns.Rich.QuestLine(lines, i, own) then
            r.facts[#r.facts + 1] = i
            r.taken[i] = true
        end
    end
    return r
end

-- What a creature is, each kind in a color of its own, keyed by the
-- creature type's id so it works in every language.
World.KIND_COLORS = {
    [1] = { 0.96, 0.72, 0.46 },  -- beast, amber
    [2] = { 1.00, 0.56, 0.42 },  -- dragonkin, ember
    [3] = { 0.86, 0.58, 1.00 },  -- demon, fel violet
    [4] = { 0.52, 0.84, 1.00 },  -- elemental, sky
    [5] = { 0.88, 0.78, 0.62 },  -- giant, stone
    [6] = { 0.66, 0.92, 0.72 },  -- undead, pale green
    [7] = { 1.00, 0.84, 0.70 },  -- humanoid, warm
    [8] = { 0.80, 0.92, 0.62 },  -- critter, leaf
    [9] = { 0.70, 0.82, 0.96 },  -- mechanical, steel
    [11] = { 0.96, 0.82, 0.48 }, -- totem, wood gold
    [12] = { 0.80, 0.92, 0.62 }, -- pet, as a critter
    [13] = { 0.72, 0.94, 0.90 }, -- gas cloud, mist
    [14] = { 0.80, 0.92, 0.62 }, -- wild pet, as a critter
    [15] = { 0.96, 0.60, 0.80 }, -- aberration, rose
}
World.RARE_COLOR = { 0.80, 0.88, 1.00 }

-- Hostile, Neutral or Friendly in its reaction's color, what it is, whether
-- it can be skinned, and Rare, Elite or Boss when it is one. Every tag in its
-- color, the outline tinted to match.
function World.Tags(unit, r)
    local W, INK, Tag = World.Words(), Style.INK, ns.RichItems.Tag
    local tags = {}
    -- Boss, elite and rare first: the tag a glance looks for.
    local class = plain(UnitClassification(unit))
    if class == "worldboss" then tags[#tags + 1] = Tag(W.boss, INK.BAD) end
    if class == "elite" or class == "rareelite" then tags[#tags + 1] = Tag(W.elite, INK.MONEY) end
    if class == "rare" or class == "rareelite" then tags[#tags + 1] = Tag(W.rare, World.RARE_COLOR) end
    local Wants = ns.RichPanel.Wants
    local reaction = Wants("tags.mob.reaction") and plain(UnitReaction(unit, "player")) or nil
    if type(reaction) == "number" then
        local name = reaction <= 3 and W.hostile or reaction == 4 and W.neutral or W.friendly
        tags[#tags + 1] = Tag(name, { Style.ReactionColor(reaction) })
    end
    local kindRaw, idRaw = UnitCreatureType(unit)
    local kind, kindID = plain(kindRaw), plain(idRaw)
    if type(kind) == "string" and kind ~= "" and Wants("tags.mob.type") then
        tags[#tags + 1] = Tag(kind, World.KIND_COLORS[kindID] or INK.TEXT)
    end
    for _, t in ipairs(r.tags) do tags[#tags + 1] = Tag(t[1], t[2]) end
    return tags
end

-- Leaves out the facts whose words the header already shows (the client may
-- put the creature's type, its reaction or "Elite" on a line of its own).
function World.DropShown(r, tags)
    local Bare = ns.Rich.Bare
    local shown = {}
    for _, t in ipairs(tags) do
        if type(t[1]) == "string" then shown[t[1]:lower()] = true end
    end
    if type(r.title) == "string" and not isSecret(r.title) then shown[Bare(r.title):lower()] = true end
    if type(r.sub) == "string" then shown[r.sub:lower()] = true end
    local kept = {}
    for _, i in ipairs(r.facts) do
        local line = r.lines[i]
        local t = not line.right and line.left and Bare(line.left):lower() or nil
        if not (t and shown[t]) then kept[#kept + 1] = i end
    end
    r.facts = kept
end

-- Builds a creature's card (board "A mob, for you").
function World.Mob(p, tip, unit, data, n, lines, light)
    local Panel, Rich = ns.RichPanel, ns.Rich
    local own = ownCount(data, n)
    local level, levelColor = World.Level(unit)
    local r = World.ReadMob(lines, own, level)
    -- No lines (the game hid them): its name from the unit, maybe secret.
    if n == 0 then r.title = DUI.UnitName(unit, "tooltip") or "" end
    local pair = ns.RichPlayers.ClassPair(unit)
    Panel.Begin(p, "mob", light)
    p.padTop = World.PAD_TOP
    local tags = World.Tags(unit, r)
    World.DropShown(r, tags)
    local cfg = ns.Tooltip.Config()
    local face = not (cfg and cfg.portraits == false) and unit or nil
    -- An elite's, rare's or boss's face wears its color's edge and glow, as
    -- an item's icon wears its quality.
    local _, rankColor = World.Rank(unit)
    Panel.Header(p, { portrait = face, iconSize = World.ICON, iconGap = World.ICON_GAP, iconTile = face and pair or nil,
        iconEdge = face and rankColor or nil,
        title = r.title, titleSize = World.TITLE, sub = r.sub,
        right = Panel.Wants("headerLevel") and World.LevelText(unit, level) or nil, rightColor = levelColor, rightSize = Style.SIZE.title,
        tags = #tags > 0 and tags or nil, tagGap = World.TAG_GAP })
    -- Its pieces, in the player's order (Rich/Layout.lua).
    local Foreign = ns.RichForeign
    local pieces = {}
    pieces.health = { has = true, draw = function() Panel.Bar(p, { unit = unit, health = true, h = 7, pair = pair }) end }
    if n == 0 then
        local quests = World.DataQuests(data)
        pieces.quests = { has = #quests > 0, draw = function() World.DrawDataQuests(p, quests) end }
    else
        -- Sorted even when hidden: another addon's quest rows count as the card's.
        local notQuest, anyQuest = World.Sort(p, lines, own, r.taken)
        pieces.quests = { has = anyQuest, draw = function() Rich.Lines(p, n, lines, 2, notQuest, true) end }
    end
    pieces.facts = { has = #r.facts > 0, draw = function()
        for _, i in ipairs(r.facts) do fact(p, lines[i]) end
    end }
    local target = ns.RichLayout.Shown("mob", "target") and ns.RichPlayers.Target(unit) or nil
    pieces.target = { has = target ~= nil, draw = function() Panel.Row(p, L["Targeting"], target[1], target[2]) end }
    pieces.addons = Foreign.Part(p, "mob")
    ns.RichLayout.Run(p, "mob", pieces)
    Panel.Finish(p)
end

-- ---------------------------------------------------------------------
-- A node, or anything else in the world
-- ---------------------------------------------------------------------

-- Builds the card for a thing in the world that isn't a unit (board "A
-- node"): its name, your skill when one of its lines names a skill of yours,
-- then the game's other lines.
function World.Object(p, tip, data, n, lines, light)
    local Panel, Rich, INK, SIZE = ns.RichPanel, ns.Rich, Style.INK, Style.SIZE
    local own = ownCount(data, n)
    local taken = {}
    local skill, need, color
    local skills
    for i = 2, own do
        local line = lines[i]
        if line.left and not line.right then
            skills = skills or World.Skills()
            skill, need = World.SkillIn(Rich.Bare(line.left), skills)
            if skill then
                color = World.Ink(line.hasLC and line.lc or nil)
                taken[i] = true
                break
            end
        end
    end
    local shade = skill and pairOf(color) or nil
    Panel.Begin(p, skill and "node" or "other", shade and { shade[2], shade[1] } or light)
    p.padTop, p.padX = World.NODE_PAD, World.NODE_PAD
    local first = lines[1]
    local title = first and first.hasLC and { first.lc[1], first.lc[2], first.lc[3] } or nil
    -- The game's white or yellow name is the card's white title; a color of
    -- its own stays.
    local game = title and DUI.Tips.GameColor(title[1], title[2], title[3])
    if game == "white" or game == "yellow" then title = nil end
    Panel.Header(p, { title = first and first.left or "", titleColor = title, titleSize = SIZE.head })
    if skill then
        local most = need or skill.max
        Panel.Gap(p, World.SKILL_GAP)
        Panel.Row(p, skill.name, skill.rank .. " " .. hex(INK.LABEL) .. string.format(L["/ %d"], most) .. "|r", color)
        Panel.Gap(p, World.SKILL_BAR_GAP)
        Panel.Bar(p, { value = math.min(skill.rank, most), max = most, pair = shade, h = 4 })
    end
    -- Its own lines, quests among them, in the game's order.
    Rich.Lines(p, own, lines, 2, taken)
    -- Then another addon's quests (not one its own lines already show), and
    -- the rest of other addons' lines.
    local Foreign = ns.RichForeign
    local notQuest, anyQuest = Foreign.QuestLines(p)
    if anyQuest then Rich.Lines(p, n, lines, own + 1, notQuest) end
    Foreign.Bottom(p)
    Panel.Finish(p)
end
