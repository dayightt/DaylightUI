-- A nameplate in the Daylight UI look: our bar (border, angled right end, soft
-- colors) with the health percent on it, the name under it, a gold mark on quest
-- targets and the raid marker beside it, the cast bar under the name, and auras
-- above (Auras.lua). Your target's plate gets the accent on its border; the one
-- under the mouse brightens. Friendly plates are simpler: a thin bar (or just the
-- name), no casts or auras.
--
-- Anything read from a unit may be secret on this client, so values go straight
-- into bars and text (which accept them) and are only compared when plain.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Plate = {}
Plate.MEDIA = DUI.Media.RegisterArea("plates", "Nameplates", ns.MEDIA_BARS, ns.MEDIA_FONTS)
ns.Plate = Plate
-- Threat % font: "general" uses the health text's.
Plate.MEDIA.fonts.threatPct = "plates.font.threatPct"
DUI.Media.RegisterSlot(Plate.MEDIA.fonts.threatPct, "Nameplates", "media.threatPctFont", "font", Plate.MEDIA.fonts.health)
-- Level font: "general" uses the health text's too.
Plate.MEDIA.fonts.level = "plates.font.level"
DUI.Media.RegisterSlot(Plate.MEDIA.fonts.level, "Nameplates", "media.levelFont", "font", Plate.MEDIA.fonts.health)

-- Never thicker than half the bar's own height, or a thin bar (friendly ones by
-- default) is all border and no visible fill.
Plate.BORDER = function(px, h)
    local t = math.max(3, math.floor(px * 0.5 + 0.5))
    if type(h) == "number" and h > 0 then
        t = math.min(t, math.max(1, math.floor((h - 2) / 2)))
    end
    return t
end
Plate.SLANT = 0.6 -- angled end cut, as a fraction of bar height
Plate.NAME_GAP = 2 -- gap between the bar and the name
Plate.HOVER = 0.15 -- mouseover brighten
Plate.MARKER = 16
-- A cell of our 4 x 2 raid marker sheet; SetSpriteSheetCell accepts a secret index.
Plate.MARKER_SHEET = DUI.MEDIA .. "markers.png"
Plate.MARKER_ROWS, Plate.MARKER_COLS = 2, 4
Plate.QUEST_COLOR = { 1, 0.82, 0.1 }
-- Heal and absorb prediction use the unit frames' colors (UF.PREDICTION).
Plate.PREDICTION = {
    heals = { color = { 0.55, 0.95, 0.6 }, alpha = 0.5 },
    absorbs = { color = { 0.85, 0.92, 1.0 }, alpha = 0.55 },
}
-- Ways to mark your target's plate, and the colors offered.
Plate.TARGET_STYLES = { outline = "Outline", glow = "Glow", none = "Nothing" }
-- Arrows pointing at your target's plate (targetArrows, off by default): beside
-- it, above it, or none. The chevron art points down; the side ones are rotated
-- to point inward.
Plate.TARGET_ARROWS = { none = "None", sides = "Beside it", top = "Over it" }
Plate.TARGET_ARROW_ORDER = { "none", "sides", "top" }
Plate.ARROW_ART = DUI.MEDIA .. "ui-chevron.png"
Plate.ARROW_GAP = 4 -- from the bar, or from whatever already sits on that side
Plate.ARROW_TURN = { left = math.pi / 2, right = -math.pi / 2, top = 0 }
Plate.TARGET_STYLE_ORDER = { "outline", "glow", "none" }
Plate.GLOW = DUI.MEDIA .. "glow.png"
Plate.GLOW_REACH = 12 -- how far the glow spreads from the bar
Plate.GLOW_ALPHA = 0.9
Plate.OUTLINE_PX = 2 -- outline thickness in screen pixels
Plate.LINE = "Interface\\Buttons\\WHITE8x8"

-- Target mark color: the accent (read each time so an accent change repaints it),
-- or the plate's own color setting when chosen.
function Plate.TargetColor(c, ownColor)
    if not c.targetAccent and type(ownColor) == "table" and type(ownColor[1]) == "number" then
        return ownColor[1], ownColor[2], ownColor[3]
    end
    return Style.Accent()
end
Plate.SUB_COLOR = DUI.Style.INK.LABEL -- guild or title line under the name
Plate.SUB_SCALE = 0.7 -- its text size as a fraction of the name's, unless guildSize/roleSize are set
Plate.NAME_OVER = 11 -- how far the name frame sits over the bar holder: past the border's corner caps (Body, +10)
Plate.NAME_LIGHTEN = 0.45 -- NPC names: reaction color, lightened to stand out from the bar
-- Threat: red while a mob is attacking you, yellow while it's on someone else,
-- orange when it's about to switch. Where it shows is a setting (threatBar,
-- threatBorder, threatGlow, any combination; bar color alone is the default).
-- Each state has a color setting, plus a pair for threatFill "pair":
Plate.THREAT = { aggro = { 0.92, 0.2, 0.18 }, warn = { 1.0, 0.55, 0.12 }, lost = { 0.98, 0.84, 0.26 } }
Plate.THREAT_KEY = { aggro = "threatAggro", warn = "threatWarn", lost = "threatLost" }
Plate.THREAT_PAIR = { aggro = "THREAT_ON", warn = "THREAT_WARN", lost = "THREAT_LOST" }
Plate.THREAT_BAND_DIM = 0.45 -- border band strength, as a fraction of the threat color
-- Threat pulse (threatPulse): a light over the fill in the threat color (peak
-- alpha), and the glow ring dimming to glowLow. Seconds per brighten or dim,
-- faster while a mob is about to switch.
Plate.THREAT_PULSE = { strength = 0.25, aggro = 0.7, warn = 0.4, glowLow = 0.35 }
-- Execute range: the bar's low end up to the execute %, in the accent. "auto"
-- shows it for classes whose finisher only works there: each class's finisher,
-- ranks low to high (the "icon" style shows the one you know). Execute and Hammer
-- of Wrath are in this client's trainer lists and always count. Shadow Word: Death
-- isn't, so a priest only gets it once the spell is known.
Plate.EXECUTE_CLASSES = {
    WARRIOR = { 5308, 20658, 20660, 20661, 20662, always = true }, -- Execute
    PALADIN = { 24275, 24274, 24239, always = true }, -- Hammer of Wrath
    PRIEST = { 32379, 32996 }, -- Shadow Word: Death
}
Plate.EXECUTE_ICON = 5308 -- the icon for "Always" on a class with no finisher (Execute's)
Plate.EXECUTE_ICON_SIZE = 1.25 -- the icon, in bar heights
Plate.EXECUTE_REST = 0.1 -- the band while the unit is above it (executeRest)
Plate.EXECUTE_LINE = 0.85 -- the line at its edge (executeLineSize px)
-- "pulse": the lit band dims down to low, seconds per brighten or dim (the threat
-- pulse's slow speed).
Plate.EXECUTE_PULSE = { low = 0.35, time = 0.7 }

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
local NONE, WHITE = {}, { 1, 1, 1 } -- never written

-- A call's plain first return, or nil (on an error or a secret result).
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v
end
Plate.Plain = plain

-- Whether a plate's unit is a game object (a fishing bobber, a chest the interact
-- key targets). Those have no health, so they show only the name.
function Plate.IsObject(unit)
    local obj = plain(UnitIsGameObject, unit)
    if obj ~= nil then return obj == true end
    local guid = plain(UnitGUID, unit)
    return type(guid) == "string" and string.find(guid, "^GameObject") ~= nil
end

-- Corpses: a lootable mob keeps its plate (the engine leaves it for the loot
-- sparkle and interact icon), and the game's plate then only shows its widgets
-- (UnitNameplateShowsWidgetsOnly, Blizzard_NamePlateUnitFrame). Ours shows nothing
-- there; the game's widgets and soft-target icon stay visible over its hidden
-- frame (Manager.Silence). Dead players keep theirs.
function Plate.IsCorpse(unit)
    if plain(UnitNameplateShowsWidgetsOnly, unit) == true then return true end
    return plain(UnitIsDead, unit) == true and plain(UnitIsPlayer, unit) ~= true
end

-- Our plate is shown unless it's on a corpse (or hidden for a test).
function Plate.ShowNow(p)
    p:SetShown(not p.corpse and not (ns.Manager and ns.Manager.testHidden))
end

-- Died (or resurrected) under the plate: hide at once, as if leaving view.
function Plate.UpdateCorpse(p)
    local now = p.unit ~= nil and Plate.IsCorpse(p.unit)
    if now == p.corpse then return end
    p.corpse = now
    Plate.ShowNow(p)
end

-- Name-only plates: game objects, and friendly plates while friendly bars are off.
function Plate.NameOnly(p, c)
    return p.object or (p.friendly and not c.friendly.enabled) or false
end

local function cfg() return ns.cfg end

-- A plate's settings. Friendly plates read their own (cfg.friendly) where set;
-- the rest is shared with enemies.
local friendlyCfg = setmetatable({}, { __index = function(_, k)
    local c = ns.cfg
    local f = c.friendly
    if type(f) == "table" and f[k] ~= nil then return f[k] end
    return c[k]
end })
function Plate.Cfg(p) return p and p.friendly and friendlyCfg or ns.cfg end

-- Name size: your target's own (target.nameSize, 0 = same as the rest; only while
-- targetScale sizes it separately), else Name size.
function Plate.NameSize(p, c)
    local t = p and p.sizeGroup == "target" and c and c.target
    local own = t and tonumber(t.nameSize)
    if own and own > 0 then return own end
    return c.nameSize
end

-- Missing health opacity (backAlpha, every plate): nil at the default
-- (Style.BAR_BACK_ALPHA, the usual plate), else how solid the empty part and the
-- plate's dark backing are (Body.Layout's see-through shell).
function Plate.Clear()
    local a = ns.cfg and tonumber(ns.cfg.backAlpha)
    if not a or a >= Style.BAR_BACK_ALPHA then return nil end
    return math.max(0, a)
end

-- A bar's empty part at that opacity, under whatever color it's painted.
function Plate.BackAlpha(bar)
    local back = Style.BarBack(bar)
    if not back then return end
    local a = Plate.Clear()
    back:SetAlpha(a and a / Style.BAR_BACK_ALPHA or 1)
end

-- ---------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------

-- Built away from the game's plates (under our own parent), then moved onto one
-- when needed (Plate.Attach): a frame created as a child of a game plate in combat
-- comes out forbidden to addons.
-- sample: the options preview (Sample.lua). It never has a unit, so no client aura
-- containers (stand-ins instead), and it uses its parent's scale.
function Plate.Create(parent, sample)
    local p = CreateFrame("Frame", nil, parent)
    p.isSample = sample == true
    -- The game scales each plate its own way (simplified ones way down). Ours is the
    -- UI scale times our Scale setting (Plate.ApplyScale).
    if p.SetIgnoreParentScale and not p.isSample then p:SetIgnoreParentScale(true) end
    p:SetSize(1, 1)

    local hp = CreateFrame("Frame", nil, p)
    -- Border: the shell look without masks (Body.lua).
    p.body = ns.Body.New(hp, { borderPx = Plate.BORDER, clear = Plate.Clear })
    local bar = Style.Bar(hp, nil, Plate.MEDIA.bars.health)
    p.hover = bar:CreateTexture(nil, "OVERLAY")
    p.hover:SetColorTexture(1, 1, 1, Plate.HOVER)
    p.hover:SetAllPoints(bar)
    p.hover:Hide()
    p.hp, p.health = hp, bar
    -- One layer per class over the fill, for hidden classes (Plate.PaintClassLayers).
    p.classLayers = DUI.Gradients.ClassLayers(bar)

    -- Incoming heals and absorb shield: two plain bars continuing where the health
    -- fill ends, in the unit frames' colors. No secret math: amounts go straight into
    -- SetValue.
    for _, key in ipairs({ "heals", "absorbs" }) do
        local s = Style.Bar(hp, "seamless", Plate.MEDIA.bars.health)
        Style.BarBack(s):Hide()
        s:SetFrameLevel(bar:GetFrameLevel() + 1)
        local c = Plate.PREDICTION[key].color
        s:SetStatusBarColor(c[1], c[2], c[3], Plate.PREDICTION[key].alpha)
        s:SetMinMaxValues(0, 1)
        s:SetValue(0)
        p[key] = s
    end
    -- Your DoTs' remaining damage (DUI.Dots): a veil over the part of the fill they'll
    -- still take, and a skull past the bar's end when it's lethal. Built with the
    -- plate (never on a plate in combat), hidden until used.
    p.dotVeil = DUI.Dots.NewVeil(bar, 2)
    p.dotSkull = DUI.Dots.NewSkull(hp, 14)
    -- Execute range (Plate.UpdateExecute), hidden until laid out, and its "icon"
    -- style: your finisher's icon by the bar.
    p.exec = Plate.NewExecute(bar)
    p.execIcon = Plate.NewExecuteIcon(hp)
    -- Target marks: a soft glow spreading from the bar's edge, or a crisp outline
    -- around it. Both are rings of eight pieces (four corners, four sides) that follow
    -- the bar's shape, with the right side sheared to match its angled end
    -- (Plate.LayoutRing).
    p.glow = Plate.Ring(p, hp, Plate.GLOW, "ADD", "BACKGROUND")
    p.outline = Plate.Ring(p, hp, Plate.LINE, "BLEND", "OVERLAY")
    Plate.AddGleam(p.outline)
    -- Threat glow: same shape, but its own ring so it never fights the target mark
    -- over one.
    p.threatGlow = Plate.Ring(p, hp, Plate.GLOW, "ADD", "BACKGROUND")
    -- Threat pulse: a light on the fill itself (clipped to its shape, like the cast
    -- bar's interrupt hit), plus the glow ring's own alpha.
    local P = Plate.THREAT_PULSE
    p.threatLight = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    p.threatLight:SetTexture(Plate.LINE)
    p.threatLight:SetBlendMode("ADD")
    p.threatLight:SetAllPoints(bar:GetStatusBarTexture())
    p.threatLight:Hide()
    p.threatPulse = p.threatLight:CreateAnimationGroup()
    p.threatPulseAnim = p.threatPulse:CreateAnimation("Alpha")
    p.threatPulseAnim:SetFromAlpha(1)
    p.threatPulseAnim:SetToAlpha(0)
    p.threatPulse:SetLooping("BOUNCE")
    p.threatGlowPulse = p.threatGlow:CreateAnimationGroup()
    p.threatGlowPulseAnim = p.threatGlowPulse:CreateAnimation("Alpha")
    p.threatGlowPulseAnim:SetFromAlpha(1)
    p.threatGlowPulseAnim:SetToAlpha(P.glowLow)
    p.threatGlowPulse:SetLooping("BOUNCE")

    -- Elite dragon around the bar's end, claws over the bar: above the fill and heal
    -- bars, below the text (Plate.LayoutDragon).
    local hold = CreateFrame("Frame", nil, hp)
    hold:SetAllPoints(hp)
    hold:SetFrameLevel(bar:GetFrameLevel() + 2)
    p.dragon = hold:CreateTexture(nil, "ARTWORK")
    p.dragon:SetTexture(Plate.DRAGON.file)
    p.dragon:Hide()

    -- Text over the bar, above its fill.
    local over = CreateFrame("Frame", nil, hp)
    over:SetAllPoints(hp)
    over:SetFrameLevel(bar:GetFrameLevel() + 3)
    p.percent = Style.Text(over, 10, "RIGHT", Plate.MEDIA.fonts.health)
    p.level = Style.Text(over, 10, "LEFT", Plate.MEDIA.fonts.level)
    -- Your threat on the mob as a % (threatPct), see Plate.UpdateThreatPct.
    p.threatPct = Style.Text(over, 10, "CENTER", Plate.MEDIA.fonts.threatPct)
    p.threatPct:Hide()

    -- Name and guild line on their own frame above everything on the bar (fill,
    -- target outline, border corner caps), so a name placed on the bar reads over it.
    -- A child of the plate, not the bar, since name-only plates hide the bar.
    local words = CreateFrame("Frame", nil, p)
    words:SetAllPoints(p)
    words:SetFrameLevel(hp:GetFrameLevel() + Plate.NAME_OVER)
    -- Group marks: small diamonds by a group member's name (friendly.partyMark).
    p.groupMarks = {}
    for _, side in ipairs({ "before", "after" }) do
        local m = words:CreateTexture(nil, "OVERLAY")
        m:SetTexture(Plate.GROUP_MARK_ART)
        m:Hide()
        p.groupMarks[side] = m
    end
    -- Opposite faction crest by a player's name (factionIcon).
    p.factionIcon = words:CreateTexture(nil, "OVERLAY")
    p.factionIcon:Hide()
    p.nameFrame = words
    p.name = Style.Text(words, 11, "CENTER", Plate.MEDIA.fonts.name)
    p.sub = Style.Text(words, 9, "CENTER", Plate.MEDIA.fonts.name)
    local sc = Plate.SUB_COLOR
    p.sub:SetTextColor(sc[1], sc[2], sc[3])
    p.quest = Style.Text(over, 14, "LEFT", Plate.MEDIA.font)
    p.quest:SetText("!")
    local q = Plate.QUEST_COLOR
    p.quest:SetTextColor(q[1], q[2], q[3])
    p.quest:Hide()
    -- Quest mark using our objective symbols (questIcon): the symbol on a frame just
    -- over the text, which holds the mark's place with the symbol's dark edge drawn
    -- inline (Plate.UpdateQuest).
    p.questArt = CreateFrame("Frame", nil, over)
    p.questArt:SetFrameLevel(over:GetFrameLevel() + 1)
    p.questArt:SetPoint("CENTER", p.quest, "CENTER")
    p.questArt:SetSize(14, 14)
    p.questArt.icon = p.questArt:CreateTexture(nil, "ARTWORK")
    p.questArt.icon:SetAllPoints()
    p.questArt:Hide()
    p.questCount = Style.Text(over, 10, "RIGHT", Plate.MEDIA.font)
    p.questCount:SetTextColor(q[1], q[2], q[3])
    p.questCount:Hide()
    p.marker = p:CreateTexture(nil, "OVERLAY")
    p.marker:SetTexture(Plate.MARKER_SHEET)
    p.marker:SetSize(Plate.MARKER, Plate.MARKER)
    p.marker:Hide()
    p.arrows = {}
    for key, turn in pairs(Plate.ARROW_TURN) do
        local a = p:CreateTexture(nil, "OVERLAY")
        a:SetTexture(Plate.ARROW_ART)
        a:SetRotation(turn)
        a:Hide()
        p.arrows[key] = a
    end

    -- The frame the game uses to keep plates from overlapping. Where a plate is
    -- clicked stays the game's (the plate size from Manager.ApplySize, with click
    -- insets past the edges from Manager.ApplyClickable) and is never set by us, the
    -- same as EllesmereUI. Plates went invisible while ours pointed the game's at our
    -- own frames.
    p.stack = CreateFrame("Frame", nil, p)
    -- The game measures a stacking frame by what's drawn in it, not its size: an empty
    -- one counts as nothing and plates don't stack. So it carries an invisible fill
    -- for the game to measure.
    p.stack.fill = p.stack:CreateTexture(nil, "BACKGROUND")
    p.stack.fill:SetColorTexture(0, 0, 0, 0)
    p.stack.fill:SetAllPoints(p.stack)

    p:SetScript("OnEvent", Plate.OnEvent)
    ns.Minion.Create(p)
    ns.Cast.Create(p)
    ns.Power.Create(p)
    if p.isSample then p.auras = {} else ns.Auras.Create(p) end
    p:Hide()
    return p
end

-- A hidden ring of eight textures around the bar. The glow texture is cut into
-- quarter corners and middle strips; a plain texture is used whole.
local RING_COORDS = {
    TOPLEFT = { 0, 0.5, 0, 0.5 }, TOPRIGHT = { 0.5, 1, 0, 0.5 },
    BOTTOMLEFT = { 0, 0.5, 0.5, 1 }, BOTTOMRIGHT = { 0.5, 1, 0.5, 1 },
    TOP = { 0.5, 0.5, 0, 0.5 }, BOTTOM = { 0.5, 0.5, 0.5, 1 },
    LEFT = { 0, 0.5, 0.5, 0.5 }, RIGHT = { 0.5, 1, 0.5, 0.5 },
}
local RING_SIDES = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true }

-- parent owns the ring; around is the frame it surrounds (its level decides the
-- ring's: above it for an outline, below for a glow).
function Plate.Ring(parent, around, file, blend, layer)
    local ring = CreateFrame("Frame", nil, parent)
    ring:SetFrameLevel(layer == "OVERLAY" and around:GetFrameLevel() + 2 or math.max(0, around:GetFrameLevel() - 1))
    ring.pieces = {}
    local soft = file == Plate.GLOW
    ring.soft = soft
    for key, tc in pairs(RING_COORDS) do
        -- Sides draw over the corners (they reach into the ends of a curve).
        local tex = ring:CreateTexture(nil, layer, nil, RING_SIDES[key] and 1 or 0)
        tex:SetTexture(file)
        if soft then tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        tex:SetBlendMode(blend)
        ring.pieces[key] = tex
    end
    ring:Hide()
    return ring
end

-- The leading gleam: a soft warm light with a short tail riding the front of each
-- edge as the outline draws on (and off). It fades in at once and out as the
-- angled end closes. Shown only during the sweep.
Plate.GLEAM = { width = 20, height = 8, tail = 22, color = { 1, 0.95, 0.85 }, alpha = 0.9, tailAlpha = 0.55 }
local gleamTail
function Plate.AddGleam(ring)
    local G = Plate.GLEAM
    local c = G.color
    if not gleamTail and CreateColor then
        gleamTail = { CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], G.tailAlpha) }
    end
    ring.gleams = {}
    for _, key in ipairs({ "TOP", "BOTTOM" }) do
        local tail = ring:CreateTexture(nil, "OVERLAY", nil, 2)
        tail:SetTexture(Plate.LINE)
        tail:SetBlendMode("ADD")
        if gleamTail then tail:SetGradient("HORIZONTAL", gleamTail[1], gleamTail[2]) end
        tail:Hide()
        local blob = ring:CreateTexture(nil, "OVERLAY", nil, 3)
        blob:SetTexture(Plate.GLOW)
        blob:SetBlendMode("ADD")
        blob:SetVertexColor(c[1], c[2], c[3], 1)
        blob:Hide()
        ring.gleams[key] = { tail = tail, blob = blob }
    end
end

local function placeGleams(ring, p, right)
    local gl = ring.gleams
    if not gl then return end
    local G = Plate.GLEAM
    local a = (p < 0.08 and p / 0.08) or (p > Plate.WIPE_RIGHT and (1 - right)) or 1
    a = a * G.alpha
    for key, g in pairs(gl) do
        local edge = ring.pieces[key]
        g.blob:ClearAllPoints()
        g.blob:SetPoint("CENTER", edge, "RIGHT", 0, 0)
        g.blob:SetSize(G.width, G.height)
        g.blob:SetAlpha(a)
        g.blob:SetShown(a > 0)
        g.tail:ClearAllPoints()
        g.tail:SetPoint("TOPRIGHT", edge, "TOPRIGHT", 0, 0)
        g.tail:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, 0)
        -- Never longer than the edge drawn so far, or it would poke out past the plate's
        -- left end as the sweep starts.
        g.tail:SetWidth(math.max(0.001, math.min(G.tail, edge:GetWidth())))
        g.tail:SetAlpha(a)
        g.tail:SetShown(a > 0)
    end
end

local function hideGleams(ring)
    for _, g in pairs(ring.gleams or {}) do
        g.blob:Hide()
        g.tail:Hide()
    end
end

-- Lays a ring around a frame, depth deep: corners out from its corners, sides along
-- its edges. The right end may be angled: topCut and bottomCut are how far in from
-- the frame's right edge that end is at the top and bottom (a health bar's cut
-- starts at its top corner, so 0 and cut; the cast bar under it continues the
-- line further down). Top and bottom stop where the angle starts and the right
-- side leans with it (its corners moved in by the cut), so the ring follows the
-- real outline.
-- radius (outline only): the border's corner curve. A square end's corners become
-- curved pieces around it (an angled end's stay sharp like the border's);
-- ring.round records which.
function Plate.LayoutRing(ring, frame, depth, topCut, bottomCut, radius)
    topCut, bottomCut = topCut or 0, bottomCut or 0
    local e = ring.pieces
    local angled = topCut ~= 0 or bottomCut ~= 0
    local function curve(key)
        if not radius or radius <= 0 or (angled and key:find("RIGHT")) then return 0 end
        return radius
    end
    ring.round = ring.round or {}
    local function corner(key, x, y, dx)
        local t, r = e[key], curve(key)
        t:ClearAllPoints()
        t:SetSize(depth + r, depth + r)
        t:SetPoint(key, frame, key, x * depth + (dx or 0), y * depth)
        if radius then Style.RingCorner(t, key, r, Plate.LINE) end
        ring.round[key] = r > 0
    end
    corner("TOPLEFT", -1, 1)
    corner("TOPRIGHT", 1, 1, -topCut)
    corner("BOTTOMLEFT", -1, -1)
    corner("BOTTOMRIGHT", 1, -1, -bottomCut)
    -- Sides start a little inside the corner curves. A curve's ends fade (its edge is
    -- soft, the line's isn't), which showed as a step where they met. A quarter of the
    -- way in, the curve is still within a fifth of a pixel of the straight line (at
    -- the default rounding), so the overlap doesn't show.
    local rl, rr = curve("TOPLEFT") * 0.75, curve("TOPRIGHT") * 0.75
    ring.edges = { frame = frame, left = rl, topEnd = topCut + rr, bottomEnd = bottomCut + rr }
    e.TOP:ClearAllPoints()
    e.TOP:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", rl, 0)
    e.TOP:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -topCut - rr, 0)
    e.TOP:SetHeight(depth)
    e.BOTTOM:ClearAllPoints()
    e.BOTTOM:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", rl, 0)
    e.BOTTOM:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -bottomCut - rr, 0)
    e.BOTTOM:SetHeight(depth)
    e.LEFT:ClearAllPoints()
    e.LEFT:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, -rl)
    e.LEFT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, rl)
    e.LEFT:SetWidth(depth)
    e.RIGHT:ClearAllPoints()
    e.RIGHT:SetPoint("TOPLEFT", frame, "TOPRIGHT", -topCut, -rr)
    e.RIGHT:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", -topCut, rr)
    e.RIGHT:SetWidth(depth)
    -- Lean the right side with the angle: move its two lower corners in by the rest
    -- of the cut.
    local lean = bottomCut - topCut
    if e.RIGHT.SetVertexOffset then
        pcall(e.RIGHT.SetVertexOffset, e.RIGHT, 2, -lean, 0)   -- lower left
        pcall(e.RIGHT.SetVertexOffset, e.RIGHT, 4, -lean, 0)   -- lower right
    end
    -- A sweep in progress keeps its position (a target switch re-lays out the plate
    -- just after the sweep starts).
    if ring.wipeDir and Plate.WipeStep then Plate.WipeStep(ring, ring.wipeP or 0) end
end

function Plate.LayoutMarks(p, cut)
    p.cut = cut
    Plate.LayoutRing(p.glow, p.hp, Plate.GLOW_REACH, 0, cut)
    Plate.LayoutRing(p.outline, p.hp, Pixel.Px(p.hp, Plate.OUTLINE_PX), 0, cut, p.body.radius)
    Plate.LayoutRing(p.threatGlow, p.hp, Plate.GLOW_REACH, 0, cut)
end

-- A plate's scale: the UI scale times the Scale setting, times its size group's
-- zoom (Target: on your target, Others: on the rest while you have a target), set
-- in one step. Ours ignores the game plate's own scale: the game shrinks
-- "simplified" plates (minions, totems, minor mobs, friendlies:
-- nameplateSimplifiedScale, 0.3) and the target's (nameplateSelectedScale), and
-- Manager.ApplyScales pins its scales to 1 so its frames never resize under ours.
-- No glide: SetScale re-lays out the whole plate, and the old glide (up to 60 a
-- second, through intermediate sizes) was the biggest cost of a target switch and
-- slowed the game over a session. The stacking box keeps its own fixed size (Layout).
local function setScale(p, v)
    if p.scaleSet == v then return end
    p.scaleSet = v
    p:SetScale(v)
end

-- Plate size by threat (threatSize): each threat state is a size group of its
-- own, a zoom only (width and height stay), so a state change is one SetScale on
-- that plate and never a new layout.
Plate.THREAT_SIZE_KEY = { aggro = "threatSizeAggro", warn = "threatSizeWarn", lost = "threatSizeLost" }
local threatGroups = {}

-- The settings of a size group ("target", "others", a threat state, or nil).
function Plate.SizeGroup(c, group)
    if not group then return nil end
    local key = Plate.THREAT_SIZE_KEY[group]
    if key then
        local g = threatGroups[group]
        if not g then
            g = {}
            threatGroups[group] = g
        end
        g.scale = tonumber(c[key]) or 1
        return g
    end
    local t = c[group]
    return type(t) == "table" and t or nil
end

-- The threat state this plate is sized by, or nil. Enemies with a bar only (pets
-- and totems keep their badge size).
function Plate.UpdateThreatSize(p)
    local state
    if cfg().threatSize == true and p.unit and not (p.friendly or p.isSample or p.minion or p.minionBar) then
        state = Plate.ThreatStateOf(p.unit)
    end
    if state == p.threatSize then return end
    p.threatSize = state
    if ns.Manager and ns.Manager.Resize then ns.Manager.Resize(p) end
end

function Plate.ApplyScale(p)
    if p.isSample then return end -- the preview fits itself to its space (Sample.lua)
    local c = cfg()
    local group = Plate.SizeGroup(c, p.sizeGroup)
    local zoom = group and group.scale or 1
    setScale(p, UIParent:GetEffectiveScale() * (c.scale or 1) * zoom)
end

-- Attaches to the game's plate, our bar centered on it. The game's plate is sized
-- to our bar (Manager.ApplySize) and sits on the unit, so the bar sits just over
-- the unit and the game's damage numbers (drawn under all UI) rise above it. The
-- game's own taller plate put its center, and our bar, up where they start. The
-- Height setting offsets it from there.
function Plate.Anchor(p)
    local nameplate = p.nameplate
    if not nameplate then return end
    p:ClearAllPoints()
    p:SetPoint("CENTER", nameplate, "CENTER", 0, cfg().offsetY or 0)
end

function Plate.Attach(p, nameplate)
    p.nameplate = nameplate
    if p:GetParent() ~= nameplate then p:SetParent(nameplate) end
    Plate.Anchor(p)
end

-- The frame the game uses to keep this plate apart from others (p.stack), hung
-- like EllesmereUI's: directly on the game's plate and pinned to it, never through
-- our frames, so nothing on one game plate depends on a frame that moves on to
-- another (that made plates go invisible). Placed on every attach, since Layout
-- returns early for a plate that looks the same.
function Plate.PlaceStack(p)
    local np, s = p.nameplate, p.stack
    if type(np) ~= "table" or p.isSample or not s then return end
    if s:GetParent() ~= np then s:SetParent(np) end
    s:ClearAllPoints()
    s:SetPoint("CENTER", np, "CENTER", 0, p.stackY or 0)
    s:Show()
end

-- Off the game's plate: our stacking frame is hidden, unpinned and taken back, as
-- EllesmereUI clears its own. The game plate is never pointed at itself (the game
-- never sets its stacking frame on its own).
function Plate.Detach(p)
    local s = p.stack
    if not s then return end
    s:Hide()
    s:ClearAllPoints()
    if s:GetParent() ~= p then s:SetParent(p) end
end

-- ---------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------

-- p.sizeGroup ("target", "others", a threat state, or nil for normal size) picks
-- the width and height multipliers, set by Manager.UpdateTargets.
-- Plate.gen is bumped when settings or style change (Manager.Refresh); a plate
-- already laid out for the same size, kind and settings is left alone.
Plate.gen = 0

function Plate.Layout(p)
    local c = Plate.Cfg(p)
    local friendly = p.friendly
    local group = Plate.SizeGroup(c, p.sizeGroup)
    Plate.ApplyScale(p)
    Plate.Anchor(p)
    local nameOnly = Plate.NameOnly(p, c)
    -- Enemy pet or totem: a round badge instead of the bar and name, or a slim bar
    -- with its portrait.
    local kind = ns.Minion.Is(p, c)
    local minion = kind == "badge"
    local slim = kind == "bar"
    p.minion, p.minionBar = minion, slim
    local w = c.width * (group and group.width or 1)
    local h = c.height * (group and group.height or 1)
    if slim then
        w = math.floor(w * ns.Minion.BAR_W + 0.5)
        h = math.max(4, math.floor(h * ns.Minion.BAR_H + 0.5))
    end
    -- Nothing that affects the shape changed (a reused plate for another unit of the
    -- same kind, a target switch that only zooms), so no new layout. Laying out a
    -- plate redraws its borders, and in a crowd plates come and go every time the
    -- camera turns. Pixel sizes stay at the normal size, as a gliding zoom always
    -- left them.
    local base = UIParent:GetEffectiveScale() * (c.scale or 1)
    local nameSize = Plate.NameSize(p, c)
    local L = p.laid
    if L and L.gen == Plate.gen and L.w == w and L.h == h and L.nameOnly == nameOnly
        and L.friendly == friendly and L.base == base and L.minion == kind and L.nameSize == nameSize then
        return
    end
    L = L or {}
    p.laid = L
    L.gen, L.w, L.h, L.nameOnly, L.friendly, L.base = Plate.gen, w, h, nameOnly, friendly, base
    L.nameSize = nameSize
    L.minion = kind
    local hp = p.hp
    hp:ClearAllPoints()
    hp:SetPoint("CENTER", p, "CENTER", 0, 0)
    hp:SetSize(w, h)
    hp:SetShown(not nameOnly and not minion)
    p.name:SetShown(not minion)
    ns.Minion.Layout(p, c, kind, h)
    -- The border is clamped to this bar's height, so a thin friendly bar keeps some
    -- visible fill instead of being all border.
    if p.shellH ~= h then
        p.shellH = h
        p.body.opts.borderPx = function(px) return Plate.BORDER(px, h) end
    end
    local cut = (friendly or c.slant == false) and 0 or Pixel.Snap(hp, h * Plate.SLANT)
    ns.Body.Layout(p.body, 0, cut)
    local T = p.body.T
    -- Fill inside the border, its moving edge leaning with the cut (its one mask).
    -- The background and mouseover light are leaned without a mask.
    local fillCut = ns.Body.FitBar(p.body, p.health, { p.hover })
    Plate.BackAlpha(p.health)
    Plate.LayoutMarks(p, cut)
    -- Heals, then a shield, continuing where the health fill (or the previous bar)
    -- ends, out to the fill's right end, their moving edges leaning like the fill's.
    local anchor = p.health:GetStatusBarTexture()
    for _, key in ipairs({ "heals", "absorbs" }) do
        local s = p[key]
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
        s:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
        s:SetPoint("RIGHT", p.health, "RIGHT", 0, 0)
        Style.AngleFill(s, fillCut > 0 and "right" or nil, fillCut)
        anchor = s:GetStatusBarTexture()
    end
    -- Your DoTs' veil from the fill's moving edge back, and the skull's size (placed
    -- by Plate.PlaceSpots, past the bar's right end by default).
    DUI.Dots.LayoutVeil(p.dotVeil, p.health, false)
    DUI.Dots.TintVeil(p.dotVeil, DUI.Dots.Tint())
    DUI.Dots.SizeSkull(p.dotSkull, math.max(10, math.floor(h * 0.9 + 0.5)))
    Plate.LayoutExecute(p, not (nameOnly or kind))

    p.percent:SetShown(c.percent and not nameOnly and not kind)
    local hs = c.healthSize or 0
    Style.SetTextSize(p.percent, hs > 0 and hs or math.max(8, math.floor(h * 0.8 + 0.5)))
    p.level:SetShown(c.level and not nameOnly and not kind)
    Plate.LayoutDragon(p, h, c.eliteDragon ~= false and not friendly and not nameOnly and not kind)
    local ls = c.levelSize or 0
    Style.SetTextSize(p.level, ls > 0 and ls or math.max(8, math.floor(h * 0.8 + 0.5)))
    p.threatPctOn = c.threatPct == true and not friendly and not nameOnly and not kind
    local ts = c.threatPctSize or 0
    Style.SetTextSize(p.threatPct, ts > 0 and ts or math.max(8, math.floor(h * 0.8 + 0.5)))
    if not p.threatPctOn then p.threatPct:Hide() end

    Style.SetTextSize(p.name, nameSize)
    Plate.SizeSub(p, c)
    local qs = math.max(10, math.floor(h * 1.1 + 0.5))
    Style.SetTextSize(p.quest, qs)
    p.questArt:SetSize(qs, qs)
    Style.SetTextSize(p.questCount, math.max(8, math.floor(h * 0.8 + 0.5)))

    -- Stacking spaces plates by everything they draw: the name (and the line under it)
    -- down to the cast bar, following the name above or below the bar.
    local nameSpot, _, _, nameY = Plate.SpotOf(p, "name")
    if nameOnly then nameSpot, nameY = "above", 0 end
    local over, under = Plate.ABOVE[nameSpot], nameSpot == "below"
    local nameRoom = nameSize + Plate.NAME_GAP
    -- Space for the power bar while its setting is on (shown or not).
    local powerRoom = ns.Power.Room(c)
    local castRoom = ns.Cast.GAP + c.castHeight + powerRoom
    -- Either line can show up on this plate later, so reserve room for the larger.
    local subRoom = math.max(c.guild and Plate.SubSize(c) or 0, c.role and Plate.SubSize(c, true) or 0)
    if subRoom > 0 then subRoom = subRoom + 1 end
    -- The stacking box uses the plate's normal size, never the target zoom: its own
    -- scale (it ignores the plate's), its own size, one anchor. Pinned to the bar's
    -- corners it shrank and grew with every plate on a target switch, and the game
    -- restacked them all, sliding plates for seconds and costing ~50 fps in a crowd.
    local nameBlock = nameSize + subRoom + Plate.NAME_GAP
    local top, bottom = (over and nameBlock or 0) + 4, c.castHeight + 4 + powerRoom + (under and nameBlock or 0)
    p.stack:SetIgnoreParentScale(true)
    p.stack:SetScale(UIParent:GetEffectiveScale() * (cfg().scale or 1))
    p.stack:SetSize(w, h + top + bottom)
    p.stackY = (cfg().offsetY or 0) + (top - bottom) / 2
    Plate.PlaceStack(p)
    p.hpCut = cut
    -- Power bar first, since the cast bar drops below it.
    if p.powerOn then ns.Power.Layout(p, cut) end
    ns.Cast.Layout(p, cut)
    ns.Auras.Layout(p)
    local ms = c.markerSize or Plate.MARKER
    p.marker:SetSize(ms, ms)
    -- Last: the name, marks and aura rows around the bar at its new size.
    p.spotsStale = true
    Plate.PlaceSpots(p)
end

-- ---------------------------------------------------------------------
-- What it shows
-- ---------------------------------------------------------------------

-- The bar's range: set on plate setup and UNIT_MAXHEALTH only, not every health
-- event (max health is secret on mobs, so it's passed whole and never compared).
function Plate.UpdateHealthMax(p)
    Style.SetBarRange(p.health, 0, UnitHealthMax(p.unit))
end

-- instant: a freshly set up plate (its range is set too, the fill snaps).
function Plate.UpdateHealth(p, instant)
    local u, c = p.unit, Plate.Cfg(p)
    if instant then Plate.UpdateHealthMax(p) end
    Style.SetBarValue(p.health, UnitHealth(u), instant)
    -- The gradient follows health, unless a threat color is showing.
    if c.healthColor == "gradient" and not p.threatColored and not p.kindColored and not p.tapped then
        DUI.Health.ApplyGradient(p.health, u)
    end
    if p.percent:IsShown() then DUI.Health.Write(p.percent, c.healthFormat or "percent", u, true) end
    -- The skull compares against current health, so feed it again, but only while
    -- something of your DoTs shows (~1,000 health events a second in a fight).
    if p.dotVeil:IsShown() or p.dotSkull:IsShown() then Plate.UpdateDots(p) end
    if p.execOn then Plate.UpdateExecute(p) end
end

local function amount(fn, u)
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn, u)
    if not ok or type(v) == "nil" then return 0 end
    return v
end

-- Incoming heals and absorb shield: whole amounts (maybe secret) go straight into
-- the bars, never compared or tested. This runs on every health and prediction
-- event of every plate (~1,000 times a second on 40 plates in a fight), so no
-- tables, show/hide only when the setting changes, and nothing is read for a bar
-- that's off.
function Plate.UpdatePrediction(p)
    local u = p.unit
    local c = cfg()
    local heals, absorbs = c.predictHeals == true, c.predictAbsorbs == true
    if p.healsOn ~= heals then p.healsOn = heals; p.heals:SetShown(heals) end
    if p.absorbsOn ~= absorbs then p.absorbsOn = absorbs; p.absorbs:SetShown(absorbs) end
    if not (heals or absorbs) then return end
    local max = UnitHealthMax(u)
    if heals then
        p.heals:SetMinMaxValues(0, max)
        p.heals:SetValue(amount(UnitGetIncomingHeals, u))
    end
    if absorbs then
        p.absorbs:SetMinMaxValues(0, max)
        p.absorbs:SetValue(amount(UnitGetTotalAbsorbs, u))
    end
end

-- ---------------------------------------------------------------------
-- Execute range
-- ---------------------------------------------------------------------

-- A band over the bar's low end as wide as the execute %, a line at its edge, and
-- a lit copy of the band that lights once the unit is in range. Health is secret
-- on every mob, so the client evaluates it through a curve (1 at or under the %,
-- 0 above) and that result becomes the lit piece's alpha. The lit band sits on its
-- own frame (e.hot) so the "pulse" style can animate that frame's alpha while the
-- curve drives the band's.
function Plate.NewExecute(bar)
    local e = CreateFrame("Frame", nil, bar)
    e:SetAllPoints(bar)
    e:SetFrameLevel(bar:GetFrameLevel() + 2)
    e.hot = CreateFrame("Frame", nil, e)
    e.hot:SetAllPoints(e)
    e.band = e:CreateTexture(nil, "ARTWORK")
    e.lit = e.hot:CreateTexture(nil, "ARTWORK", nil, 1)
    e.line = e:CreateTexture(nil, "OVERLAY")
    for _, t in ipairs({ e.band, e.lit, e.line }) do t:SetTexture(Plate.LINE) end
    e.lit:SetAlpha(0)
    e.pulse = e.hot:CreateAnimationGroup()
    e.pulseAnim = e.pulse:CreateAnimation("Alpha")
    e.pulseAnim:SetFromAlpha(1)
    e.pulseAnim:SetToAlpha(Plate.EXECUTE_PULSE.low)
    e.pulseAnim:SetDuration(Plate.EXECUTE_PULSE.time)
    e.pulse:SetLooping("BOUNCE")
    e:Hide()
    return e
end

-- "Whole bar": a light over the health fill itself, clipped to its shape (the
-- fill's one mask, like the threat light). Created on first use.
function Plate.ExecuteFill(p)
    local e = p.exec
    if not e.fill then
        local bar = p.health
        e.fill = bar:CreateTexture(nil, "ARTWORK", nil, 4)
        e.fill:SetAllPoints(bar:GetStatusBarTexture())
        e.fill:SetAlpha(0)
    end
    local fm = Style.GetFillMask(p.health)
    if fm and e.fillMask ~= fm then
        if pcall(e.fill.AddMaskTexture, e.fill, fm) then e.fillMask = fm end
    end
    return e.fill
end

-- Execute color: the accent (its pair for a gradient accent, read at paint time)
-- or the player's own. fade: from transparent at the bar's low end to full at the line.
function Plate.PaintExecute(tex, alpha, c, fade)
    local lo, hi
    if c.executeAccent ~= false then
        lo, hi = Style.AccentPair()
        if not lo then
            local r, g, b = Style.Accent()
            lo = { r, g, b }
            hi = lo
        end
    else
        local own = type(c.executeColor) == "table" and c.executeColor or ns.DEFAULTS.executeColor
        lo, hi = own, own
    end
    if (fade or lo ~= hi) and tex.SetGradient and CreateColor then
        tex:SetVertexColor(1, 1, 1, alpha)
        tex:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], fade and 0 or alpha), CreateColor(hi[1], hi[2], hi[3], alpha))
        return
    end
    tex:SetVertexColor(lo[1], lo[2], lo[3], alpha)
end

-- Your finisher's spell id for "auto": your class's, if it always counts or you
-- know a rank (the highest known), or nil. Kept until your spells change.
local finisher, finisherRead = nil, false
function Plate.ExecuteSpell()
    if finisherRead then return finisher end
    finisherRead, finisher = true, nil
    local _, token = UnitClass("player")
    local list = type(token) == "string" and not isSecret(token) and Plate.EXECUTE_CLASSES[token]
    if not list then return nil end
    local book = C_SpellBook
    if type(book) == "table" and type(book.IsSpellKnown) == "function" then
        for i = #list, 1, -1 do
            local ok, yes = pcall(book.IsSpellKnown, list[i])
            if ok and yes == true then
                finisher = list[i]
                return finisher
            end
        end
    end
    if list.always then finisher = list[1] end
    return finisher
end

-- Spells learned: "auto" may now show (or not), so plates are laid out again
-- when the answer changed.
function Plate.ExecuteSpellsChanged()
    local was = finisher
    finisherRead = false
    if Plate.ExecuteSpell() ~= was and ns.Manager and ns.cfg and ns.cfg.execute == "auto" then
        ns.Manager.Refresh()
    end
end

-- The execute fraction for this plate (0.2 = 20%), or nil. Enemies only.
function Plate.ExecutePct(p)
    if p.friendly then return nil end
    local c = cfg()
    local mode = c.execute
    if mode == "off" then return nil end
    if mode ~= "on" and not Plate.ExecuteSpell() then return nil end
    local pct = tonumber(c.executePct) or 0.2
    return math.max(0.01, math.min(0.99, pct))
end

-- One curve per %: 1 at or under it, 0 above (like Health.FullCurve).
local execCurves = {}
function Plate.ExecuteCurve(pct)
    local c = execCurves[pct]
    if c == nil then
        c = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local ok, made = pcall(C_CurveUtil.CreateCurve)
            if ok and made then
                if Enum.LuaCurveType and made.SetType then pcall(made.SetType, made, Enum.LuaCurveType.Linear) end
                made:AddPoint(0, 1)
                made:AddPoint(pct, 1)
                made:AddPoint(math.min(1, pct + 0.001), 0)
                if pct + 0.001 < 1 then made:AddPoint(1, 0) end
                c = made
            end
        end
        execCurves[pct] = c
    end
    return c
end

-- The "icon" style's piece: your finisher's icon on a black edge, placed past the
-- bar like the DoT skull (Plate.PlaceSpots). Its alpha is the execute curve's.
function Plate.NewExecuteIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetColorTexture(0, 0, 0, 1)
    f.back:SetAllPoints(f)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    Style.CropIcon(f.icon)
    f:SetAlpha(0)
    f:Hide()
    return f
end

-- The icon's size for a bar this tall.
function Plate.ExecuteIconSize(h)
    return math.max(12, math.floor(h * Plate.EXECUTE_ICON_SIZE + 0.5))
end

-- Sizes and shows the icon for the "icon" style (on), else hides it.
function Plate.LayoutExecuteIcon(p, on, h)
    local f = p.execIcon
    p.execIconOn = on
    if not on then
        f:SetAlpha(0)
        f:Hide()
        return
    end
    local size = Plate.ExecuteIconSize(h)
    f:SetSize(size, size)
    local T = Pixel.Px(f, 1)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", T, -T)
    f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -T, T)
    local id = Plate.ExecuteSpell() or Plate.EXECUTE_ICON
    local tex = type(C_Spell) == "table" and type(C_Spell.GetSpellTexture) == "function"
        and C_Spell.GetSpellTexture(id) or nil
    f.icon:SetTexture(tex or "Interface\\Icons\\INV_Sword_48")
    f:Show()
end

-- Sizes and paints it (from Plate.Layout). show false: a name-only plate, or an
-- enemy pet or totem.
function Plate.LayoutExecute(p, show)
    local e = p.exec
    local pct = show and Plate.ExecutePct(p) or nil
    p.execOn = pct ~= nil
    local c = cfg()
    local style = c.executeStyle or "band"
    Plate.LayoutExecuteIcon(p, pct ~= nil and style == "icon", p.hp:GetHeight())
    if not pct then
        e:Hide()
        e.pulse:Stop()
        if e.fill then e.fill:Hide() end
        return
    end
    local bar = p.health
    local x = Pixel.Snap(bar, bar:GetWidth() * pct)
    -- Its right edge leans with the fill's moving edge.
    local side, cut = Style.GetFillAngle(bar)
    local lean = side == "right" and cut or side == "left" and -cut or 0
    local file = c.executeTexture == "bar" and Style.BarFile("fill") or Plate.LINE
    local fade = c.executeTexture == "fade"
    for _, t in ipairs({ e.band, e.lit }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        t:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        t:SetWidth(math.max(x, 1))
        t:SetTexture(file)
        if t.SetVertexOffset then pcall(t.SetVertexOffset, t, 3, lean, 0) end
    end
    local l = e.line
    local px = tonumber(c.executeLineSize) or 2
    l:ClearAllPoints()
    l:SetPoint("TOP", bar, "TOPLEFT", x, 0)
    l:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 0)
    l:SetWidth(Pixel.Px(bar, math.max(px, 1)))
    if l.SetVertexOffset then
        pcall(l.SetVertexOffset, l, 1, lean, 0)
        pcall(l.SetVertexOffset, l, 3, lean, 0)
    end
    l:SetShown(px > 0)
    local strength = tonumber(c.executeStrength) or 0.45
    local lined = style == "line" or style == "icon"
    e.band:SetShown(not lined and c.executeRest ~= false)
    Plate.PaintExecute(e.band, Plate.EXECUTE_REST, c, fade)
    Plate.PaintExecute(e.line, Plate.EXECUTE_LINE, c, false)
    -- The piece that lights: the band or the whole fill; none for "line".
    local hot
    if style == "bar" then
        hot = Plate.ExecuteFill(p)
        hot:SetTexture(file)
        e.lit:Hide()
    elseif not lined then
        hot = e.lit
        if e.fill then e.fill:Hide() end
    else
        e.lit:Hide()
        if e.fill then e.fill:Hide() end
    end
    e.hotTex = hot
    if hot then
        Plate.PaintExecute(hot, strength, c, fade)
        hot:Show()
    elseif style == "icon" then
        e.hotTex = p.execIcon -- the icon lights instead
    end
    -- "pulse": the lit band pulses; motion off holds it still.
    if style == "pulse" and DUI.Motion.On() then
        if not e.pulse:IsPlaying() then e.pulse:Play() end
    else
        e.pulse:Stop()
    end
    e.curve = Plate.ExecuteCurve(pct)
    e:Show()
    if p.unit then Plate.UpdateExecute(p) end
end

-- Lights it while the unit is in range. The curve's result (maybe secret) goes
-- straight to SetAlpha, never tested.
function Plate.UpdateExecute(p)
    local e = p.exec
    local hot = e.hotTex
    if not hot then return end
    if e.curve and UnitHealthPercent then
        local ok, a = pcall(UnitHealthPercent, p.unit, true, e.curve)
        if ok then
            hot:SetAlpha(a)
            return
        end
    end
    hot:SetAlpha(0)
end

-- Your DoTs on this plate's unit (DUI.Dots): enemies only, each piece by its switch.
function Plate.UpdateDots(p)
    local c = cfg()
    local tint, skull = c.dotTint ~= false, c.dotSkull ~= false
    if p.friendly or not p.unit or not (tint or skull) then
        p.dotVeil:Hide()
        p.dotSkull:Hide()
        return
    end
    DUI.Dots.Paint(p.unit, tint and p.dotVeil or nil, skull and p.dotSkull or nil)
    if not tint then p.dotVeil:Hide() end
    if not skull then p.dotSkull:Hide() end
end

-- Class color for players, reaction color for everyone else.
function Plate.BaseColor(u)
    if plain(UnitIsPlayer, u) == true then
        local _, token = UnitClass(u)
        return Style.ClassColor(token)
    end
    return Style.ReactionColor(UnitReaction(u, "player"))
end

-- A special mob's own bar color (bossBar/rareBar/questBar/casterBar on): "boss",
-- "rare", "quest" or "caster", or nil. Enemy NPCs only, never players, minions or
-- name-only plates. Classification, UnitIsBossMob and power type stay plain in
-- combat; a secret or missing answer counts as no. A quest mob is one the quest
-- mark's tooltip read found (p.questUnit, Plate.UpdateQuest). c: the plate's
-- settings (Plate.Cfg).
Plate.KIND_COLOR = { boss = "bossColor", rare = "rareColor", quest = "questColor", caster = "casterColor" }
Plate.RARE = { rare = true, rareelite = true }
function Plate.MobKind(p, c)
    if p.friendly or p.minion or not p.unit then return nil end
    if not (c.bossBar or c.rareBar or c.questBar or c.casterBar) then return nil end
    local u = p.unit
    if plain(UnitIsPlayer, u) == true then return nil end
    local class = plain(UnitClassification, u)
    if c.bossBar and (class == "worldboss" or plain(UnitIsBossMob, u) == true) then return "boss" end
    if c.rareBar and Plate.RARE[class or ""] then return "rare" end
    if c.questBar and p.questUnit then return "quest" end
    -- Enum.PowerType.Mana is 0.
    if c.casterBar and plain(UnitPowerType, u) == 0 then return "caster" end
    return nil
end

-- In battlegrounds the game hides enemy players' class (secret), so the bar's
-- class layers carry the color (DUI.Gradients, hidden classes).
Plate.CLASS_IDS = DUI.Gradients.CLASS_IDS

-- Whether the game hides a player's class: true plus the (secret) class id, else
-- false. Never test the id itself.
function Plate.HiddenClass(u)
    if plain(UnitIsPlayer, u) ~= true then return false end
    local id = DUI.Gradients.HiddenClassID(u)
    if type(id) == "nil" then return false end
    return true, id
end

-- Shows the class layers for a hidden class id in mode "class" (flat) or
-- "classGradient"; mode nil hides them.
function Plate.PaintClassLayers(p, id, mode)
    DUI.Gradients.PaintClassLayers(p.classLayers, id, mode)
end

-- Text can't use the sprite trick, so for a hidden class the name and guild line
-- are selected by position: one copy of each per class, in that class's colors,
-- inside its own clip window. The windows sit side by side CLASS_SLOT apart, hung
-- off the end of an invisible bar whose value is the secret class id (bars accept
-- secrets; the heal bars hang off a secret health fill the same way), so only the
-- unit's own class's window lands over the name.
Plate.CLASS_SLOT = 1000 -- window width: wider than any name
Plate.CLASS_SLOT_H = 400 -- window height: covers the name and guild line wherever they sit
Plate.CLASS_MAX = 12 -- bar range: past the highest class id

local function classText(p)
    if p.classText then return p.classText end
    local W = Plate.CLASS_SLOT
    local sel = CreateFrame("StatusBar", nil, p)
    sel:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    sel:SetStatusBarColor(0, 0, 0, 0)
    sel:SetMinMaxValues(0, Plate.CLASS_MAX)
    sel:SetSize(Plate.CLASS_MAX * W, Plate.CLASS_SLOT_H)
    sel:SetPoint("LEFT", p, "CENTER", -W / 2, 0)
    local fill = sel:GetStatusBarTexture()
    local ct = { sel = sel, wins = {}, name = {}, sub = {} }
    for token, id in pairs(Plate.CLASS_IDS) do
        -- Class id's window ends (id - 1) slots before the fill's end, so it's right over
        -- the name exactly when the fill ends at id.
        local win = CreateFrame("Frame", nil, p.nameFrame) -- over the bar, like the name
        win:SetClipsChildren(true)
        win:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -(id - 1) * W, 0)
        win:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -(id - 1) * W, 0)
        win:SetWidth(W)
        local inner = CreateFrame("Frame", nil, win)
        inner:SetAllPoints(win)
        ct.name[token] = Style.Text(inner, 11, "CENTER", Plate.MEDIA.fonts.name)
        ct.name[token]:SetAllPoints(p.name)
        ct.sub[token] = Style.Text(inner, 9, "CENTER", Plate.MEDIA.fonts.name)
        ct.sub[token]:SetAllPoints(p.sub)
        ct.wins[token] = win
    end
    p.classText = ct
    return ct
end

-- Name and guild line in the unit's class colors when the game hides its class.
-- A flat class color goes straight onto the text as the game's own secret color
-- values (a secret can't be softened; the unit frames do the same). Only
-- per-letter class gradients ("classGradient" names) need the windowed copies;
-- doing it for everything meant ten clip windows with two texts each on every
-- enemy player plate in a battleground.
function Plate.UpdateClassText(p)
    local u, c = p.unit, Plate.Cfg(p)
    local hidden, id = Plate.HiddenClass(u)
    local copies = hidden and c.nameColor == "classGradient" and not p.groupName
    local classy = Plate.GuildInClass(c)
    local subOn = copies and classy and p.guild ~= nil and p.sub:IsShown()
    p.name:SetAlpha(copies and 0 or 1)
    p.sub:SetAlpha(subOn and 0 or 1)
    if hidden and not copies then
        local r, g, b = DUI.Gradients.HiddenClassColor(u)
        if type(r) ~= "nil" then
            if c.nameColor == "class" and not p.groupName then p.name:SetTextColor(r, g, b) end
            if p.guild ~= nil and classy then p.sub:SetTextColor(r, g, b) end
        end
    end
    if not copies then
        if p.classText then
            for _, win in pairs(p.classText.wins) do win:Hide() end
        end
        return
    end
    local ct = classText(p)
    ct.sel:SetValue(id)
    local name = DUI.UnitName(u, "nameplates")
    for token, win in pairs(ct.wins) do
        win:Show()
        local fs, sub = ct.name[token], ct.sub[token]
        fs:SetFont(p.name:GetFont())
        fs:SetJustifyH(p.nameJustify or "CENTER") -- the name's side of its spot (Plate.PlaceSpots)
        fs:SetText(DUI.Gradients.Text(token, name))
        fs:SetTextColor(1, 1, 1) -- the letters carry their own colors
        fs:Show()
        sub:SetFont(p.sub:GetFont())
        sub:SetJustifyH(p.nameJustify or "CENTER")
        if subOn then pcall(sub.SetFormattedText, sub, "<%s>", p.guild[1]) end
        sub:SetTextColor(Style.ClassTextColor(token))
        sub:SetShown(subOn)
    end
end

-- Your standing on a mob: "aggro" (attacking you), "warn" (about to switch),
-- "lost" (you're on its list, it's on someone else), or nil (normal color). Only
-- in a group or with a pet (solo, every mob you fight is on you anyway), and only
-- while the game reports it (DUI.Threat reads plain answers only). One rule for
-- every role except who "about to switch" means: for a tank, losing it; for
-- anyone else, getting close to pulling (above the tank, or most of the way to
-- the pull threshold).
function Plate.ThreatState(u)
    if not cfg().threat then return nil end
    return Plate.ThreatStateOf(u)
end

-- Same, whether or not Threat colors are on (for the threat % color).
function Plate.ThreatStateOf(u)
    if not DUI.Threat.Shared() then return nil end
    local level, status = DUI.Threat.Level("player", u)
    if not level then return nil end
    if DUI.Threat.IsTank() then
        if status == 3 then return "aggro" end
        if status == 2 then return "warn" end
        return "lost"
    end
    if level == "aggro" then return "aggro" end
    if level == "warn" then return "warn" end
    return "lost"
end

-- A state's color { r, g, b } (the pair's light end for threatFill "pair"). Returns
-- the setting's own table while it's valid, so a plate can compare it. No table
-- per call: this runs on every threat event of every plate.
function Plate.ThreatColorOf(state)
    if not state then return nil end
    local c = cfg()
    if c.threatFill == "pair" then
        local _, hi = DUI.Gradients.RGB(Plate.THREAT_PAIR[state])
        return hi
    end
    return c[Plate.THREAT_KEY[state]] or Plate.THREAT[state]
end

-- A threat color, or nil for normal; then the state.
function Plate.ThreatColor(u)
    local state = Plate.ThreatState(u)
    return Plate.ThreatColorOf(state), state
end

-- A threat color on the bar (p.threatNow, p.threatState) as a gradient: its pair,
-- or on a gradient bar the same color as a gradient, so the plate keeps its look.
-- c: the plate's settings (Plate.Cfg).
function Plate.PaintThreatBar(p, c)
    local G = DUI.Gradients
    if not G then return end
    if cfg().threatFill == "pair" then
        G.Paint(p.health, Plate.THREAT_PAIR[p.threatState])
    elseif c.healthColor == "classGradient" or c.healthColor == "gradient" then
        G.PaintFrom(p.health, p.threatNow)
    end
end

-- A special mob's color on the bar (Plate.MobKind). On a gradient bar (class
-- gradient, by health) it becomes a gradient, as threat's single color does
-- (Plate.PaintThreatBar); otherwise flat, already set. bar: the health bar (a
-- real plate's or the preview's).
function Plate.PaintKindBar(bar, c, rgb)
    if DUI.Gradients and (c.healthColor == "classGradient" or c.healthColor == "gradient") then
        DUI.Gradients.PaintFrom(bar, rgb)
    end
end

-- Threat on the bar's border: outline and warm band in the threat color, or back
-- to normal. The dimmed band is cached per color, since threat events come many
-- times a second.
local bandOf = setmetatable({}, { __mode = "k" })
function Plate.ApplyThreatBorder(p, t)
    if t and cfg().threatBorder then
        local band = bandOf[t]
        if not band then
            local k = Plate.THREAT_BAND_DIM
            band = { t[1] * k, t[2] * k, t[3] * k }
            bandOf[t] = band
        end
        ns.Body.SetColors(p.body, t, band)
    else
        ns.Body.SetColors(p.body, nil, nil)
    end
    -- Your target's outline sits around the border, so it takes the threat color too;
    -- otherwise it would box the warning in.
    if p.isTarget and p.markThreat ~= (cfg().threatBorder and t or nil) then Plate.UpdateTarget(p) end
end

-- Threat as a glow around the bar, on its own ring (Plate.Create).
function Plate.ApplyThreatGlow(p, t)
    local on = t ~= nil and cfg().threatGlow == true
    if on then
        for _, tex in pairs(p.threatGlow.pieces) do tex:SetVertexColor(t[1], t[2], t[3], Plate.GLOW_ALPHA) end
    end
    p.threatGlow:SetShown(on)
end

-- Pulse speed for a state, or nil to hold still. Only states that need you pulse:
-- about to switch always, a mob you lost as a tank, a mob on you otherwise. The
-- everyday state, every mob in a pull, stays calm.
function Plate.ThreatBreath(state)
    local P = Plate.THREAT_PULSE
    if state == "warn" then return P.warn end
    if state == (DUI.Threat.IsTank() and "lost" or "aggro") then return P.aggro end
    return nil
end

-- Your threat on the mob as a % (threatPct, enemy plates only): the game's scaled
-- percent (100 = it turns on you), only in a group or with a pet (solo every mob
-- is on you), hidden while you're not on its list. A boss can return a secret
-- value, which is written whole in white and never compared. Colored
-- (threatPctColor "threat") only while the state needs you (Plate.ThreatBreath),
-- otherwise white. A number that appears fades in FAST so it's there at once.
function Plate.UpdateThreatPct(p)
    local fs = p.threatPct
    if not p.threatPctOn then return end
    local pct
    if DUI.Threat.Shared() and type(UnitDetailedThreatSituation) == "function" then
        local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, "player", p.unit)
        if ok then pct = scaled end
    end
    if type(pct) == "nil" then fs:Hide(); return end
    local mode, state = cfg().threatPctColor or "threat", nil
    if isSecret(pct) then
        fs:SetFormattedText("%.0f%%", pct)
    else
        fs:SetFormattedText("%d%%", math.floor(pct + 0.5))
        if mode == "threat" then state = Plate.ThreatStateOf(p.unit) end
    end
    Plate.PaintThreatPct(fs, mode, state)
    if not fs:IsShown() then
        fs:Show()
        local M = DUI.Motion
        M.Tween("plates:threatPct:" .. tostring(p), 0, 1, M.FAST, function(a) fs:SetAlpha(a) end)
    end
end

-- Number color: the state's threat color while it needs you, the accent, the
-- player's own (threatPctCustom), or white.
function Plate.PaintThreatPct(fs, mode, state)
    if mode == "accent" then return Style.InkText(fs, "pop") end
    if mode == "custom" then
        local t = cfg().threatPctCustom
        if type(t) == "table" then return fs:SetTextColor(t[1], t[2], t[3]) end
    end
    local t = state and Plate.ThreatBreath(state) and Plate.ThreatColorOf(state)
    if t then fs:SetTextColor(t[1], t[2], t[3]) else Style.InkText(fs, "VALUE") end
end

-- Threat pulse (threatPulse, Plate.THREAT_PULSE): on while the plate's threat state
-- needs you (Plate.ThreatBreath), whichever way it shows. Motion off holds it
-- still. With bar, border and glow all off there's nothing to pulse.
-- Threat events only reach here on a change (Plate.UpdateBarColor).
function Plate.ApplyThreatPulse(p, t)
    local c = cfg()
    local P = Plate.THREAT_PULSE
    local marked = c.threatBar ~= false or c.threatBorder == true or c.threatGlow == true
    local time = t ~= nil and marked and c.threatPulse ~= false and DUI.Motion.On() and Plate.ThreatBreath(p.threatState)
    local on = time and true or false
    if on then
        if p.threatPulseTime ~= time then
            p.threatPulseTime = time
            p.threatPulseAnim:SetDuration(time)
            p.threatGlowPulseAnim:SetDuration(time)
            -- A new speed takes effect on the next play.
            p.threatPulse:Stop()
            p.threatGlowPulse:Stop()
        end
        local fm = Style.GetFillMask(p.health)
        if fm and p.threatLightMask ~= fm then
            if pcall(p.threatLight.AddMaskTexture, p.threatLight, fm) then p.threatLightMask = fm end
        end
        p.threatLight:SetVertexColor(t[1], t[2], t[3], P.strength)
        p.threatLight:Show()
        if not p.threatPulse:IsPlaying() then p.threatPulse:Play() end
    else
        p.threatLight:Hide()
        p.threatPulse:Stop()
        p.threatPulseTime = nil
    end
    if on and p.threatGlow:IsShown() then
        if not p.threatGlowPulse:IsPlaying() then p.threatGlowPulse:Play() end
    else
        p.threatGlowPulse:Stop()
    end
end

-- Bar color and threat marks (threat, combat, roster and flag events), then the
-- name's color and text (Plate.UpdateNameColor).
function Plate.UpdateColor(p)
    Plate.UpdateBarColor(p)
    Plate.UpdateNameColor(p)
end

-- Threat lists change many times a second in combat and every plate is recolored
-- on combat and roster changes, so the name, which none of those affect, is left
-- alone.
-- Tapped and untapped colors for a secret "tapped" answer: color objects cached,
-- not created on every threat and roster event.
local tappedObj, tappedFor
local function tappedColor()
    local n = Style.NEUTRAL
    if tappedFor ~= n then tappedObj, tappedFor = CreateColor(n[1], n[2], n[3], 1), n end
    return tappedObj
end
local untappedObj, uR, uG, uB
local function untappedColor(r, g, b)
    if not (untappedObj and uR == r and uG == g and uB == b) then
        untappedObj, uR, uG, uB = CreateColor(r, g, b, 1), r, g, b
    end
    return untappedObj
end

-- What UNIT_FLAGS can change on the bar: tapped state and reaction. nil when
-- either answer is secret (then it always repaints).
function Plate.FlagSig(u)
    local tapped, react = UnitIsTapDenied(u), UnitReaction(u, "player")
    if isSecret(tapped) or isSecret(react) then return nil end
    return (tapped == true and 100 or 0) + (type(react) == "number" and react or 0)
end

function Plate.UpdateBarColor(p)
    local u = p.unit
    p.flagSig = Plate.FlagSig(u)
    local c = Plate.Cfg(p)
    local r, g, b = Plate.BaseColor(u)
    if c.healthColor == "custom" then r, g, b = Style.Soften(c.healthCustom[1], c.healthCustom[2], c.healthCustom[3]) end
    local t, state = Plate.ThreatColor(u)
    p.threatNow, p.threatState, p.colored = t, state, true
    local onBar = t ~= nil and c.threatBar
    p.threatColored = onBar
    -- Boss, rare or caster in its own color (threat still wins).
    p.kind = Plate.MobKind(p, c)
    local kc = p.kind and not onBar and c[Plate.KIND_COLOR[p.kind]] or nil
    p.kindColored = kc ~= nil
    if kc then r, g, b = Style.Soften(kc[1], kc[2], kc[3]) end
    if onBar then r, g, b = Style.Soften(t[1], t[2], t[3]) end
    Style.SetBarColor(p.health, r, g, b)
    if c.healthColor == "gradient" and not onBar and not kc then
        Style.SetBarColor(p.health, Style.Neutral())
        DUI.Health.ApplyGradient(p.health, u)
    end
    -- Class gradient: the unit's pair, painted last so nothing plain clears it. A
    -- tapped mob (below) still goes gray.
    if c.healthColor == "classGradient" and not onBar and not kc and DUI.Gradients then
        DUI.Gradients.PaintUnit(p.health, u)
    end
    if kc then Plate.PaintKindBar(p.health, c, kc) end
    if onBar then Plate.PaintThreatBar(p, c) end
    -- A player whose class the game hides: the class layers carry the color.
    local hidden, classID = Plate.HiddenClass(u)
    local classMode = hidden and not onBar and (c.healthColor == "class" or c.healthColor == "classGradient")
    -- Already hidden (every plate outside battlegrounds): nothing to touch.
    if classMode or not p.layersOff then
        Plate.PaintClassLayers(p, classID, classMode and c.healthColor or nil)
        p.layersOff = not classMode
    end
    if p.minionBar and not onBar then ns.Minion.PaintBar(p) end
    Plate.ApplyThreatBorder(p, t)
    Plate.ApplyThreatGlow(p, t)
    Plate.ApplyThreatPulse(p, t)
    Plate.UpdateThreatPct(p)
    Plate.UpdateThreatSize(p)
    -- A mob tagged by someone else goes gray (the answer may be secret).
    local tapped = UnitIsTapDenied(u)
    p.tapped = not isSecret(tapped) and tapped == true
    if isSecret(tapped) then
        local fill = p.health:GetStatusBarTexture()
        if fill and fill.SetVertexColorFromBoolean then
            pcall(fill.SetVertexColorFromBoolean, fill, tapped, tappedColor(), untappedColor(r, g, b))
        end
    elseif tapped then
        Style.SetBarColor(p.health, Style.Neutral())
    end
end

-- A friendly plate on someone in your party or raid, with Group names on: the name
-- uses that one color (friendly.partyCustom) over Name color. A secret answer
-- (under restrictions) counts as not in the group.
function Plate.InGroupName(p)
    return Plate.Cfg(p).partyName == true and Plate.InGroup(p)
end

-- Someone else in your party or raid, on a friendly plate (a secret answer counts
-- as no).
function Plate.InGroup(p)
    if not p.friendly or p.isSample then return false end
    local u = p.unit
    if not u or plain(UnitIsPlayer, u) ~= true or plain(UnitIsUnit, u, "player") == true then return false end
    return plain(UnitInParty, u) == true or type(plain(UnitInRaid, u)) == "number"
end

function Plate.UpdateNameColor(p)
    local u = p.unit
    local c = Plate.Cfg(p)
    p.groupName = Plate.InGroupName(p)
    -- Players' names in their class color, NPCs' in their reaction color (green
    -- friendly, yellow neutral, red hostile), slightly lighter. "reaction" applies to
    -- players too, so an enemy player reads red. Or all white. Group members get
    -- their own color when that's on.
    if p.groupName then
        local t = c.partyCustom
        p.name:SetTextColor(t[1], t[2], t[3])
    elseif c.nameColor == "white" then
        Style.InkText(p.name, "VALUE")
    elseif c.nameColor == "custom" then
        local t = Plate.CustomNameColor(c, plain(UnitIsPlayer, u) == true, Plate.OtherFaction(u) ~= nil)
        p.name:SetTextColor(t[1], t[2], t[3])
    elseif c.nameColor == "classGradient" and DUI.Gradients then
        p.name:SetTextColor(1, 1, 1) -- the letters carry their own colors
    elseif c.nameColor ~= "reaction" and plain(UnitIsPlayer, u) == true then
        local _, token = UnitClass(u)
        p.name:SetTextColor(Style.ClassTextColor(token))
    else
        local nr, ng, nb = Style.ReactionColor(UnitReaction(u, "player"))
        p.name:SetTextColor(Style.Lighten(nr, ng, nb, Plate.NAME_LIGHTEN))
    end
    Plate.UpdateName(p)
    Plate.UpdateClassText(p)
    Plate.ShowGroupMark(p, (c.partyMark or "none") ~= "none" and Plate.InGroup(p))
    Plate.ShowFaction(p, c.factionIcon == true and Plate.OtherFaction(u))
end

-- The name, each letter in the unit's gradient when chosen.
function Plate.UpdateName(p)
    local text = DUI.UnitName(p.unit, "nameplates")
    if Plate.Cfg(p).nameColor == "classGradient" and DUI.Gradients and not p.groupName then
        text = DUI.Gradients.Text(DUI.Gradients.KeyFor(p.unit), text)
    end
    p.name:SetText(text)
    -- Things next to the name follow its new width.
    if p.groupMarkOn then Plate.PlaceGroupMark(p) end
    if p.factionOn then Plate.PlaceFaction(p) end
end

-- Elite dragon (plate-dragon.png), drawn for a 32 px bar. All sizes below are in
-- bar heights, so it follows the plate's Height and zoom without stretching.
-- Pinned by the bar's top-right corner (endX in from the image's left, topY down
-- from its top).
Plate.DRAGON = { file = DUI.MEDIA .. "plate-dragon.png", tex = 128, px = 32,
                 w = 3.15625, h = 2.4375, endX = 2.2636, topY = 1.1636 }
-- The unit frames' elite colors (UF.ELITE_RING_COLORS); bosses are gold too.
Plate.DRAGON_COLORS = { gold = { 1.0, 0.8, 0.33 }, silver = { 0.84, 0.87, 0.92 } }
Plate.DRAGON_KIND = { elite = "gold", rareelite = "gold", worldboss = "gold", rare = "silver" }

function Plate.LayoutDragon(p, h, allowed)
    local D, t = Plate.DRAGON, p.dragon
    p.dragonAllowed = allowed
    t:SetSize(D.w * h, D.h * h)
    t:SetTexCoord(0, D.w * D.px / D.tex, 0, D.h * D.px / D.tex)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", p.hp, "TOPRIGHT", -D.endX * h, D.topY * h)
    if not allowed then t:Hide() end
end

-- A plain classification (nil when unknown or secret, so no dragon).
function Plate.PaintDragon(p, classification)
    local kind = p.dragonAllowed and Plate.DRAGON_KIND[classification or ""]
    if not kind then p.dragon:Hide() return end
    local c = Plate.DRAGON_COLORS[kind]
    p.dragon:SetVertexColor(c[1], c[2], c[3], 1)
    p.dragon:Show()
end

function Plate.UpdateDragon(p)
    Plate.PaintDragon(p, plain(UnitClassification, p.unit))
end

-- The unit's level in the game's difficulty color (softened like the rest of the
-- plate) or the player's choice (levelColor). "??" for one far above you, "+" for
-- an elite.
Plate.ELITE = { elite = true, rareelite = true, worldboss = true }
Plate.SKULL = { 1, 0.15, 0.15 }

function Plate.UpdateLevel(p)
    if not p.level:IsShown() then return end
    local u = p.unit
    local lvl = plain(UnitLevel, u)
    if type(lvl) ~= "number" then
        p.level:SetText("")
        return
    end
    Plate.PaintLevel(p, lvl, plain(UnitClassification, u), u)
end

-- A plain level and classification ("elite"...) into the level text. Also used by
-- the preview's sample, which has no unit token, just its level.
function Plate.PaintLevel(p, lvl, classification, unit)
    local text, r, g, b
    if lvl <= 0 then
        text = "??"
        r, g, b = Plate.SKULL[1], Plate.SKULL[2], Plate.SKULL[3]
    else
        text = tostring(lvl)
        if Plate.ELITE[classification or ""] then text = text .. "+" end
        local c = DUI.LevelColor(unit, lvl) or plain(GetQuestDifficultyColor, lvl)
        if type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
    end
    p.level:SetText(text)
    -- "??" keeps its skull red whatever the setting: danger is what the glance needs.
    local mode = lvl > 0 and Plate.Cfg(p).levelColor or "difficulty"
    if mode == "white" then return Style.InkText(p.level, "VALUE") end
    if mode == "accent" then return Style.InkText(p.level, "pop") end
    if mode == "custom" then
        local t = Plate.Cfg(p).levelCustom
        if type(t) == "table" then return p.level:SetTextColor(t[1], t[2], t[3]) end
    end
    if r then p.level:SetTextColor(Style.Soften(r, g, b)) end
end

-- Level lines the tooltip's second line can hold instead of a title (built once,
-- on first use, when the game's strings exist).
local LEVEL_PATTERNS
local function levelPatterns()
    local out = {}
    for _, tpl in ipairs({ UNIT_TYPE_LEVEL_TEMPLATE, UNIT_LEVEL_TEMPLATE }) do
        if type(tpl) == "string" then out[#out + 1] = "^" .. string.gsub(tpl, "%%.", ".+") .. "$" end
    end
    out[#out + 1] = "^Level "
    return out
end

-- A unit's tooltip data. Reading it is slow and allocates a big table, so while a
-- plate is set up (Plate.UpdateAll) the title line and quest mark share one read.
local tipOpen, tipFor, tipInfo = false, nil, nil
local function unitTooltip(u)
    if tipOpen and tipFor == u then return tipInfo end
    local get = C_TooltipInfo and C_TooltipInfo.GetUnit
    local info = get and plain(get, u)
    if tipOpen then tipFor, tipInfo = u, info end
    return info
end

-- An NPC's title from the second line of its tooltip, outside instances.
function Plate.RoleOf(u)
    if plain(IsInInstance) == true then return nil end
    local info = unitTooltip(u)
    if type(info) ~= "table" or type(info.lines) ~= "table" then return nil end
    local line = info.lines[2]
    if type(line) ~= "table" or isSecret(line) then return nil end
    local text = line.leftText
    if isSecret(text) or type(text) ~= "string" or text == "" then return nil end
    LEVEL_PATTERNS = LEVEL_PATTERNS or levelPatterns()
    for _, pat in ipairs(LEVEL_PATTERNS) do
        if string.find(text, pat) then return nil end
    end
    return text
end

-- ---------------------------------------------------------------------
-- Where the pieces sit
-- ---------------------------------------------------------------------

-- Movable pieces (Design mode in the options preview, or each one's Position on
-- its page) sit at a spot around the health bar (DaylightUI.Spots, the unit frames'
-- rule) plus a nudge; aura rows also have a grow direction. Pieces sharing a spot
-- stack outward from the bar in this order (beside the bar the name goes last,
-- past the marks): above it the name, your debuffs, then purgeable buffs; left of
-- it the quest mark, then the raid marker. Spots under the bar start below the
-- cast bar's space, so nothing jumps when a cast starts. Settings go through
-- Plate.Cfg (friendly plates have their own name spot); your buffs' row is the
-- Friendly page's. A name-only friendly plate keeps the name centered.
-- The bar's texts, the execute icon and the DoT skull go last (Plate.SPOT_LAST): they sit past
-- whatever shares their spot and push nothing. The skull never takes space at
-- all, since its frame shows with any DoT up and only a secret-safe clip decides
-- whether you see it, so nothing can line up against it.
Plate.SPOT_ORDER = { "name", "quest", "marker", "debuffs", "helps", "buffs", "cc" }
Plate.SPOT_LAST = { "percent", "level", "threatPct", "execIcon", "skull" }
Plate.SPOT_KEYS = {
    name = { spot = "namePos", x = "nameX", y = "nameY" },
    quest = { spot = "questPos", x = "questX", y = "questY" },
    marker = { spot = "markerPos", x = "markerX", y = "markerY" },
    debuffs = { spot = "debuffSpot", grow = "debuffGrow", x = "debuffX", y = "debuffY" },
    helps = { spot = "myBuffSpot", grow = "myBuffGrow", x = "myBuffX", y = "myBuffY", friendly = true },
    buffs = { spot = "buffSpot", grow = "buffGrow", x = "buffX", y = "buffY" },
    cc = { spot = "ccSpot", x = "ccX", y = "ccY" },
    percent = { spot = "percentPos", x = "percentX", y = "percentY" },
    level = { spot = "levelPos", x = "levelX", y = "levelY" },
    threatPct = { spot = "threatPctPos", x = "threatPctX", y = "threatPctY" },
    skull = { spot = "dotSkullPos", x = "dotSkullX", y = "dotSkullY" },
    execIcon = { spot = "executeIconPos", x = "executeIconX", y = "executeIconY" },
}
Plate.ROWS = { debuffs = true, helps = true, buffs = true, cc = true } -- outside spots only
Plate.OUTSIDE = {}
for _, s in ipairs(ns.OUTSIDE_SPOTS) do Plate.OUTSIDE[s] = true end
Plate.ABOVE = { above = true, outtopleft = true, outtopright = true }
-- Distance from the bar's end to the first piece beside it (where the marks always
-- were), and between pieces sharing a spot.
Plate.BESIDE_GAP = { name = 2, quest = 3, marker = 4, debuffs = 4, helps = 4, buffs = 4, cc = 4,
                     percent = 3, level = 3, threatPct = 3, skull = 3, execIcon = 3 }
Plate.CHAIN_GAP = 2

local Spots = DUI.Spots
local BESIDE = { outleft = true, outright = true }
-- Pieces that are a single region of the plate.
local SINGLE = { marker = "marker", percent = "percent", level = "level", threatPct = "threatPct", skull = "dotSkull",
                 execIcon = "execIcon" }
local BAR_TEXT = { percent = true, level = true, threatPct = true }

-- A piece's spot, grow direction (an aura row's own; the name and marks follow
-- their spot's side) and nudge.
function Plate.SpotOf(p, piece)
    local k = Plate.SPOT_KEYS[piece]
    local c = k.friendly and ns.cfg.friendly or Plate.Cfg(p)
    if type(c) ~= "table" then c = {} end
    local spot = c[k.spot]
    if not Spots.Valid(spot) or (Plate.ROWS[piece] and not Plate.OUTSIDE[spot]) then
        spot = (k.friendly and ns.DEFAULTS.friendly or ns.DEFAULTS)[k.spot]
    end
    local grow = k.grow and c[k.grow]
    if not grow then
        grow = "center"
        if not spot:find("^out") then
            if spot:find("left$") then grow = "right" elseif spot:find("right$") then grow = "left" end
        end
    end
    return spot, grow, tonumber(c[k.x]) or 0, tonumber(c[k.y]) or 0
end

-- The health bar as a Spots box (into: a table to fill, else a new one). Spots on
-- it are kept clear of its border, level text and angled end.
function Plate.SpotBox(p, into)
    local box, hp = into or {}, p.hp
    local T = p.body and p.body.T or 0
    box.w, box.h = hp:GetWidth(), hp:GetHeight()
    box.padX, box.padY, box.cutR = T + 3, T, p.hpCut or 0
    box.above, box.below, box.outL, box.outR = 0, 0, 0, 0
    return box
end

local function textWidth(fs, fallback)
    local ok, v = pcall(fs.GetStringWidth, fs)
    if ok and type(v) == "number" and not isSecret(v) and v > 0 then return v end
    return fallback
end

-- Group member names marked (friendly.partyMark), since Group names replaces the
-- class color: a small diamond before the name, or one on each side, in the group
-- color while the name keeps its own color. Placed by the name's measured width;
-- a name that can't be measured (a secret one) gets none.
function Plate.ShowGroupMark(p, on)
    local marks = p.groupMarks
    if not marks then return end
    local c = Plate.Cfg(p)
    local mode = on and c.partyMark or "none"
    p.groupMarkOn = mode ~= "none"
    if p.groupMarkOn then
        local t = c.partyCustom
        for _, m in pairs(marks) do m:SetVertexColor(t[1], t[2], t[3], 1) end
        if not Plate.PlaceGroupMark(p) then p.groupMarkOn, mode = false, "none" end
    end
    local M = DUI.Motion
    for side, m in pairs(marks) do
        local want = (mode == "around") or (mode == "before" and side == "before")
        if want or m:IsShown() then M.AlphaTo(m, want and 1 or 0, M.FAST, true) end
    end
end

Plate.GROUP_MARK_ART = DUI.MEDIA .. "shape-diamond.png"
Plate.GROUP_MARK_SCALE = 0.6 -- size, as a fraction of the name's
Plate.GROUP_MARK_GAP = 3
function Plate.PlaceGroupMark(p)
    local marks, name = p.groupMarks, p.name
    local tw = textWidth(name, nil)
    if not (marks and tw) then return false end
    local size = math.max(6, math.floor(Plate.NameSize(p, Plate.Cfg(p)) * Plate.GROUP_MARK_SCALE + 0.5))
    local gap, H = Plate.GROUP_MARK_GAP, p.nameJustify or "CENTER"
    local before, after = marks.before, marks.after
    before:SetSize(size, size)
    after:SetSize(size, size)
    before:ClearAllPoints()
    after:ClearAllPoints()
    if H == "LEFT" then
        before:SetPoint("RIGHT", name, "LEFT", -gap, 0)
        after:SetPoint("LEFT", name, "LEFT", tw + gap, 0)
    elseif H == "RIGHT" then
        before:SetPoint("RIGHT", name, "RIGHT", -(tw + gap), 0)
        after:SetPoint("LEFT", name, "RIGHT", gap, 0)
    else
        before:SetPoint("RIGHT", name, "CENTER", -(tw / 2 + gap), 0)
        after:SetPoint("LEFT", name, "CENTER", tw / 2 + gap, 0)
    end
    return true
end

-- Opposite faction crest by a player's name (factionIcon): Alliance or Horde, using
-- the game's own unit frame crests, so the other side is obvious at a glance,
-- flagged or not. A secret answer or an unmeasurable name gets none.
Plate.FACTION_ATLAS = {
    Alliance = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
    Horde = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",
}
Plate.FACTION_SCALE = 1.15 -- size, as a fraction of the name's
Plate.FACTION_GAP = 3

-- Name color "custom" (friendly plates): the chosen color for a player, an NPC or
-- an opposite-faction player.
function Plate.CustomNameColor(c, isPlayer, other)
    local t = (other and c.nameOther) or (isPlayer and c.namePlayer) or (not isPlayer and c.nameNpc)
    return type(t) == "table" and t or WHITE
end

-- The unit's faction if it's a player of the other faction, else nil.
function Plate.OtherFaction(u)
    if not u or plain(UnitIsPlayer, u) ~= true then return nil end
    local theirs, mine = plain(UnitFactionGroup, u), plain(UnitFactionGroup, "player")
    if type(theirs) ~= "string" or type(mine) ~= "string" then return nil end
    if theirs ~= mine and Plate.FACTION_ATLAS[theirs] and Plate.FACTION_ATLAS[mine] then return theirs end
    return nil
end

function Plate.ShowFaction(p, faction)
    local icon = p.factionIcon
    if not icon then return end
    local atlas = faction and p.name:IsShown() and Plate.FACTION_ATLAS[faction]
    if atlas then
        icon:SetAtlas(atlas)
        p.factionOn = Plate.PlaceFaction(p)
    else
        p.factionOn = false
    end
    if p.factionOn or icon:IsShown() then
        local M = DUI.Motion
        M.AlphaTo(icon, p.factionOn and 1 or 0, M.FAST, true)
    end
end

-- Left of the name (past the group mark when that sits before it).
function Plate.PlaceFaction(p)
    local icon, name = p.factionIcon, p.name
    local tw = textWidth(name, nil)
    if not (icon and tw) then return false end
    local c = Plate.Cfg(p)
    local nameSize = Plate.NameSize(p, c)
    local size = math.max(8, math.floor(nameSize * Plate.FACTION_SCALE + 0.5))
    local gap = Plate.FACTION_GAP
    local mark = p.groupMarks and p.groupMarks.before
    if p.groupMarkOn and mark and (c.partyMark == "before" or c.partyMark == "around") then
        gap = gap + math.max(6, math.floor(nameSize * Plate.GROUP_MARK_SCALE + 0.5)) + Plate.GROUP_MARK_GAP
    end
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    local H = p.nameJustify or "CENTER"
    if H == "LEFT" then
        icon:SetPoint("RIGHT", name, "LEFT", -gap, 0)
    elseif H == "RIGHT" then
        icon:SetPoint("RIGHT", name, "RIGHT", -(tw + gap), 0)
    else
        icon:SetPoint("RIGHT", name, "CENTER", -(tw / 2 + gap), 0)
    end
    return true
end

-- Whether a piece takes space now and how much: across (beside the bar) and up
-- (above or below it). Text widths only matter for the preview's fit.
local function room(p, piece, c, w, h)
    if piece == "name" then
        if not p.name:IsShown() then return false end
        -- One pixel above the name too, where the rows have always started.
        local up = Plate.NameSize(p, c) + 1
        if p.sub:IsShown() then up = up + 1 + p.subPx end
        return true, p.isSample and math.min(w + 20, textWidth(p.name, w)) or w + 20, up
    elseif piece == "quest" then
        if not p.quest:IsShown() then return false end
        local across = 0
        if p.isSample then
            across = textWidth(p.quest, 6) + (p.questCount:IsShown() and 1 + textWidth(p.questCount, 20) or 0)
        end
        return true, across, math.max(10, math.floor(h * 1.1 + 0.5))
    elseif piece == "marker" then
        if not p.marker:IsShown() then return false end
        local ms = c.markerSize or Plate.MARKER
        return true, ms, ms
    elseif BAR_TEXT[piece] then
        local fs = p[piece]
        -- The threat % reserves its space while enabled, shown or not: it comes and goes
        -- with every pull and nothing should jump.
        if piece == "threatPct" then
            if not p.threatPctOn then return false end
        elseif not fs:IsShown() then return false end
        local size = (piece == "percent" and (c.healthSize or 0)) or (piece == "threatPct" and (c.threatPctSize or 0))
            or (piece == "level" and (c.levelSize or 0)) or 0
        if size <= 0 then size = math.max(8, math.floor(h * 0.8 + 0.5)) end
        return true, p.isSample and textWidth(fs, 20) or 0, size
    elseif piece == "execIcon" then
        -- Its space is kept while the style is on, lit or not, so nothing moves as the
        -- enemy drops into range (its alpha may be secret).
        if not p.execIconOn then return false end
        local size = Plate.ExecuteIconSize(h)
        return true, size, size
    elseif piece == "skull" then
        if not p.isSample or p.friendly or c.dotSkull == false then return false end -- for the preview's fit
        local size = p.dotSkull:GetWidth()
        return true, size, size
    end
    local all = ns.cfg
    local on
    if piece == "helps" then
        on = p.friendly == true and type(all.friendly) == "table" and all.friendly.myBuffs == true
    else
        on = not p.friendly and all[piece] == true
    end
    if not on then return false end
    return true, ns.Auras.Room(piece)
end

-- The side of a spot's anchor point ("LEFT", "RIGHT" or "" for centered).
local function sideOf(point)
    return (point:find("LEFT") and "LEFT") or (point:find("RIGHT") and "RIGHT") or ""
end

-- The name and its guild or title line as one block: above the bar the line sits
-- closest to it, anywhere else under the name. Justified to the spot's side; on
-- the bar as wide as the space there.
local function placeName(p, L, rel, spot, nameOnly, w)
    local name, sub = p.name, p.sub
    name:ClearAllPoints()
    sub:ClearAllPoints()
    if nameOnly then
        name:SetWidth(w + 20)
        sub:SetWidth(w + 20)
        p.nameJustify = "CENTER"
        name:SetJustifyH("CENTER")
        sub:SetJustifyH("CENTER")
        name:SetPoint("CENTER", p, "CENTER", 0, 0)
        sub:SetPoint("TOP", name, "BOTTOM", 0, -1)
        if p.groupMarkOn then Plate.PlaceGroupMark(p) end
        if p.factionOn then Plate.PlaceFaction(p) end
        return
    end
    local H = sideOf(L.point)
    local width = Plate.OUTSIDE[spot] and w + 20 or L.line
    name:SetWidth(width)
    sub:SetWidth(width)
    -- Kept to pass along (to the class text copies), since nothing should read it back
    -- from a text that may hold a secret name.
    p.nameJustify = H == "" and "CENTER" or H
    name:SetJustifyH(p.nameJustify)
    sub:SetJustifyH(p.nameJustify)
    if sub:IsShown() and Plate.ABOVE[spot] then
        sub:SetPoint(L.point, rel, L.relPoint, L.x, L.y)
        name:SetPoint("BOTTOM" .. H, sub, "TOP" .. H, 0, 1)
    else
        name:SetPoint(L.point, rel, L.relPoint, L.x, L.y)
        sub:SetPoint("TOP" .. H, name, "BOTTOM" .. H, 0, -1)
    end
    if p.groupMarkOn then Plate.PlaceGroupMark(p) end
    if p.factionOn then Plate.PlaceFaction(p) end
end

-- The quest mark, with its count on the side away from the bar (left of the ! when
-- centered).
local function placeQuest(p, L, rel)
    p.quest:ClearAllPoints()
    p.quest:SetPoint(L.point, rel, L.relPoint, L.x, L.y)
    p.questCount:ClearAllPoints()
    if sideOf(L.point) == "LEFT" then
        p.questCount:SetPoint("LEFT", p.quest, "RIGHT", 1, 0)
    else
        p.questCount:SetPoint("RIGHT", p.quest, "LEFT", -1, 0)
    end
end

local function place(p, x, piece)
    local spot, grow, nx, ny = Plate.SpotOf(p, piece)
    if piece == "name" and x.nameOnly then spot, grow, nx, ny = "above", "center", 0, 0 end
    local on, across, up = room(p, piece, x.c, x.w, x.h)
    local box = x.box
    box.above, box.below, box.outL, box.outR = 0, 0, 0, 0
    local rel, lead = p.hp, piece == "name" and Plate.NAME_GAP or Plate.CHAIN_GAP
    local b = BESIDE[spot] and x.side[spot]
    if b then
        -- Beside the bar: past the last mark there (its far side, so a count's width
        -- counts) and any rows since. Not past the skull: a row's space is there with no
        -- aura showing, so it would float away.
        if piece == "skull" then b.dist, b.px = b.dist - b.px, 0 end
        lead = (b.rel == p.hp and b.px == 0) and Plate.BESIDE_GAP[piece] or Plate.CHAIN_GAP
        local off = b.px + lead - Spots.GAP
        if spot == "outleft" then box.outL = off else box.outR = off end
        rel = b.rel
    elseif x.used[spot] then
        -- Above or below the bar, or off a corner: past the earlier pieces.
        local off = x.used[spot] + lead - Spots.GAP
        if Plate.ABOVE[spot] then box.above = off else box.below = off end
    end
    -- The bar's texts: centering the text box leaves digits a pixel low (room for
    -- descenders), so both move up a pixel, the health text a bit further into the
    -- angled end than the rest.
    local cutR = box.cutR
    if piece == "percent" then box.cutR = cutR * 0.5 - 1 end
    local L = Spots.Layout(spot, grow, box, { x = nx, y = ny + (BAR_TEXT[piece] and Pixel.Px(p.hp, 1) or 0),
                                              line = Plate.ROWS[piece] and x.w or nil })
    box.cutR = cutR
    if piece == "name" then
        placeName(p, L, rel, spot, x.nameOnly, x.w)
    elseif piece == "quest" then
        placeQuest(p, L, rel)
    elseif SINGLE[piece] then
        local region = p[SINGLE[piece]]
        region:ClearAllPoints()
        region:SetPoint(L.point, rel, L.relPoint, L.x, L.y)
    else
        -- A row: the client's container or the preview's stand-in (Auras.ShowSample
        -- places a new one from here).
        local at = p.spotAt[piece] or {}
        p.spotAt[piece] = at
        at.L, at.rel = L, rel
        local f = p.auras and p.auras[piece]
        if f then ns.Auras.Place(f, piece, at, p) end
        f = p.sampleAuras and p.sampleAuras[piece]
        if f then ns.Auras.Place(f, piece, at, p) end
    end
    if not on then return end
    local r = x.reach
    if b then
        if Plate.ROWS[piece] then
            b.px = b.px + lead + across
        else
            b.rel = (piece == "quest" and p.questCount:IsShown() and p.questCount) or (piece == "quest" and p.quest)
                or (SINGLE[piece] and p[SINGLE[piece]]) or p.name
            b.px = 0
        end
        b.dist = b.dist + lead + across
        if r then
            local k = spot == "outleft" and "left" or "right"
            r[k] = math.max(r[k], b.dist + math.abs(nx))
            local over = math.max(0, up / 2 - x.h / 2)
            r.up, r.down = math.max(r.up, over + math.max(0, ny)), math.max(r.down, over + math.max(0, -ny))
        end
    elseif x.used[spot] then
        local far = x.used[spot] + lead + up
        x.used[spot] = far
        if r then
            if Plate.ABOVE[spot] then r.up = math.max(r.up, far + math.max(0, ny))
            else r.down = math.max(r.down, far + math.max(0, -ny)) end
            if spot ~= "above" and spot ~= "below" then
                local k = spot:find("left$") and "left" or "right"
                r[k] = math.max(r[k], Spots.GAP + across + math.abs(nx))
            end
        end
    end
end

-- Places every piece at its spot. Called from Plate.Layout (p.spotsStale, every
-- time), and when something it lines up with shows or hides (guild line, quest
-- mark or count, raid marker) or the combo points arrive or leave; otherwise it
-- returns at once. The preview plate also records how far the pieces reach
-- (p.spotReach, Sample.lua).
function Plate.PlaceSpots(p)
    local c = Plate.Cfg(p)
    if not c then return end
    local Combo = ns.Combo
    local lift = Combo and Combo.Lift(p) or 0
    local drop = (Combo and Combo.Drop(p) or 0) + ns.Power.Drop(p)
    local sub, quest, count, marker = p.sub:IsShown(), p.quest:IsShown(), p.questCount:IsShown(), p.marker:IsShown()
    local s = p.spotSig
    if not s then
        s = {}
        p.spotSig = s
        p.spotsStale = true
    end
    if not p.spotsStale and s.sub == sub and s.subPx == p.subPx and s.quest == quest and s.count == count and s.marker == marker
        and s.lift == lift and s.drop == drop then
        return
    end
    p.spotsStale = nil
    s.sub, s.subPx, s.quest, s.count, s.marker, s.lift, s.drop = sub, p.subPx, quest, count, marker, lift, drop

    local x = p.spotCtx
    if not x then
        x = { used = {}, side = { outleft = {}, outright = {} }, box = {} }
        p.spotCtx = x
    end
    local hp = p.hp
    x.c, x.w, x.h = c, hp:GetWidth(), hp:GetHeight()
    x.nameOnly = Plate.NameOnly(p, c)
    local u = x.used
    u.above, u.below = lift, ns.Cast.GAP + drop + c.castHeight
    u.outtopleft, u.outtopright, u.outbottomleft, u.outbottomright = 0, 0, 0, 0
    for _, b in pairs(x.side) do b.rel, b.px, b.dist = hp, 0, 0 end
    Plate.SpotBox(p, x.box)
    x.reach = nil
    if p.isSample then x.reach = { up = 0, down = 0, left = 0, right = 0 } end
    p.spotAt = p.spotAt or {}

    local nameLast = not x.nameOnly and BESIDE[(Plate.SpotOf(p, "name"))]
    if not nameLast then place(p, x, "name") end
    for i = 2, #Plate.SPOT_ORDER do place(p, x, Plate.SPOT_ORDER[i]) end
    if nameLast then place(p, x, "name") end
    for _, piece in ipairs(Plate.SPOT_LAST) do place(p, x, piece) end
    p.spotReach = x.reach
    -- The target arrows go past everything placed around the bar.
    p.arrowUp, p.arrowL, p.arrowR = u.above, x.side.outleft.dist, x.side.outright.dist
    Plate.PlaceArrows(p)
end

-- Target arrow size and position: above the bar past what sits there, or beside
-- it past what's on each side.
function Plate.PlaceArrows(p)
    local c = cfg()
    local arrows = p.arrows
    if not (arrows and c) or (c.targetArrows or "none") == "none" then return end
    local size = tonumber(c.targetArrowSize) or 16
    local gap, hp = Plate.ARROW_GAP, p.hp
    for _, a in pairs(arrows) do
        a:SetSize(size, size)
        a:ClearAllPoints()
    end
    arrows.top:SetPoint("BOTTOM", hp, "TOP", 0, (p.arrowUp or 0) + gap)
    arrows.left:SetPoint("RIGHT", hp, "LEFT", -((p.arrowL or 0) + gap), 0)
    arrows.right:SetPoint("LEFT", hp, "RIGHT", (p.arrowR or 0) + gap, 0)
end

-- Shows the arrows pointing at your target (on: it's your target and has a bar),
-- fading in FAST and out, in the accent or their own color.
function Plate.ShowArrows(p, on)
    local arrows = p.arrows
    if not arrows then return end
    local c = cfg()
    local mode = on and c and c.targetArrows or "none"
    if mode ~= "none" then
        Plate.PlaceArrows(p)
        local r, g, b
        local own = c.targetArrowColor
        if c.targetArrowPaint == "custom" and type(own) == "table" and type(own[1]) == "number" then
            r, g, b = own[1], own[2], own[3]
        else
            r, g, b = Style.Accent()
        end
        for _, a in pairs(arrows) do a:SetVertexColor(r, g, b, 1) end
    end
    local M = DUI.Motion
    for key, a in pairs(arrows) do
        local want = (mode == "sides" and key ~= "top") or (mode == "top" and key == "top")
        if want or a:IsShown() then M.AlphaTo(a, want and 1 or 0, M.FAST, true) end
    end
end

-- Guild or title line text size: its own setting, else a fraction of the name's.
-- job: the NPC title's, else the guild's.
function Plate.SubSize(c, job)
    local size = c.guildSize
    if job then size = c.roleSize end
    if type(size) == "number" and size > 0 then return size end
    return math.max(8, math.floor(c.nameSize * Plate.SUB_SCALE + 0.5))
end

-- Sizes the line for what it holds now (p.subJob). Guild and title share one text,
-- so a plate reused for another kind of unit changes here.
function Plate.SizeSub(p, c)
    local px = Plate.SubSize(c, p.subJob)
    if p.subPx == px then return end
    p.subPx = px
    Style.SetTextSize(p.sub, px)
end

-- Whether the guild uses its player's class color (the default).
function Plate.GuildInClass(c)
    return c.guildColor ~= "white" and c.guildColor ~= "custom"
end

-- White or one chosen color. False: the caller sets the line's color.
function Plate.PaintSub(p, mode, custom)
    if mode == "white" then
        Style.InkText(p.sub, "VALUE")
    elseif mode == "custom" and type(custom) == "table" then
        p.sub:SetTextColor(custom[1], custom[2], custom[3])
    else
        return false
    end
    return true
end

-- With the name: a player's <guild>, or an NPC's title.
-- noClassText: the caller runs Plate.UpdateColor next, which redoes it.
function Plate.UpdateSub(p, noClassText)
    local c, u = Plate.Cfg(p), p.unit
    local shown = false
    p.guild = nil -- the guild shown (maybe secret), for Plate.UpdateClassText
    local isPlayer = plain(UnitIsPlayer, u) == true
    p.subJob = not isPlayer
    Plate.SizeSub(p, c)
    if isPlayer then
        -- Guild in the player's class color, an NPC title in tan. Either can have its own
        -- color instead.
        if not Plate.PaintSub(p, c.guildColor, c.guildCustom) then
            local _, token = UnitClass(u)
            p.sub:SetTextColor(Style.ClassTextColor(token))
        end
        if c.guild and GetGuildInfo then
            local guild = GetGuildInfo(u)
            if isSecret(guild) then
                shown = pcall(p.sub.SetFormattedText, p.sub, "<%s>", guild)
            elseif type(guild) == "string" and guild ~= "" then
                p.sub:SetFormattedText("<%s>", guild)
                shown = true
            end
            if shown then p.guild = { guild } end
        end
    elseif c.role then
        if not Plate.PaintSub(p, c.roleColor, c.roleCustom) then
            local sc = Plate.SUB_COLOR
            p.sub:SetTextColor(sc[1], sc[2], sc[3])
        end
        local role = Plate.RoleOf(u)
        if role then
            p.sub:SetText(role)
            shown = true
        end
    end
    p.sub:SetShown(shown and not (p.minion or p.minionBar))
    Plate.PlaceSpots(p)
    if not noClassText then Plate.UpdateClassText(p) end
end

-- arrive: from RAID_TARGET_UPDATE, a newly set marker fades in FAST (like the unit
-- frames' UF.MarkerIn; the index is always secret, so only "none to one" can be
-- detected). A freshly shown plate snaps.
function Plate.UpdateMarker(p, arrive)
    local i = GetRaidTargetIndex(p.unit)
    local shown = false
    if isSecret(i) then
        -- Can't test a secret; picking the cell fails if there's no marker.
        shown = pcall(p.marker.SetSpriteSheetCell, p.marker, i, Plate.MARKER_ROWS, Plate.MARKER_COLS)
    elseif type(i) == "number" then
        p.marker:SetSpriteSheetCell(i, Plate.MARKER_ROWS, Plate.MARKER_COLS)
        shown = true
    end
    local was = p.marker:IsShown()
    p.marker:SetShown(shown)
    if arrive and shown and not was then
        local M = DUI.Motion
        M.Tween(p.marker, 0, 1, M.FAST, function(a) p.marker:SetAlpha(a) end)
    end
    Plate.PlaceSpots(p) -- pieces lined up with it close up or make room
end

-- Whether a unit is part of one of your quests with something left to do, from
-- its tooltip, outside instances (where the game makes it secret). Second value:
-- the first unfinished objective's progress ("4/10", "45%").
-- How many quests are in your log (plain), or nil when the game won't say.
function Plate.QuestCount()
    local QL = C_QuestLog
    if type(QL) ~= "table" or type(QL.GetNumQuestLogEntries) ~= "function" then return nil end
    local ok, _, n = pcall(QL.GetNumQuestLogEntries)
    if not ok or isSecret(n) or type(n) ~= "number" then return nil end
    return n
end

-- Your log's completion state as one string: each quest's id and its objectives'
-- finished flags. Changes when an objective finishes or reopens (you sold or
-- destroyed some of the items), not on a progress tick. nil when the game won't
-- say; secret parts read "?".
local sigParts = {}
function Plate.QuestSig()
    local QL = C_QuestLog
    if type(QL) ~= "table" or type(QL.GetNumQuestLogEntries) ~= "function"
        or type(QL.GetInfo) ~= "function" or type(QL.GetQuestObjectives) ~= "function" then return nil end
    local ok, n = pcall(QL.GetNumQuestLogEntries)
    if not ok or isSecret(n) or type(n) ~= "number" then return nil end
    local k = 0
    for i = 1, n do
        local okI, info = pcall(QL.GetInfo, i)
        local id = okI and type(info) == "table" and info.questID
        if type(id) == "number" and not isSecret(id) and not isSecret(info.isHeader) and info.isHeader ~= true then
            k = k + 1
            sigParts[k] = id
            local okO, objs = pcall(QL.GetQuestObjectives, id)
            if okO and type(objs) == "table" then
                for _, o in ipairs(objs) do
                    local done = type(o) == "table" and o.finished
                    k = k + 1
                    sigParts[k] = isSecret(done) and "?" or (done == true and "1" or "0")
                end
            end
        end
    end
    for j = #sigParts, k + 1, -1 do sigParts[j] = nil end
    return table.concat(sigParts, ",", 1, k)
end

-- Whether your quest log is empty (then no plate needs its tooltip read). Unknown
-- answers count as "has quests".
function Plate.NoQuests()
    return Plate.QuestCount() == 0
end

-- Whether a tooltip's quest player line (in a group, each member's name above their
-- objectives) is you. me is your first name; the line can include the last name
-- too, so only the first word is compared.
function Plate.IsMyQuestLine(text, me)
    if type(text) ~= "string" or type(me) ~= "string" or me == "" then return false end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:match("^%s*(.-)%s*$")
    if text:sub(1, #me) ~= me then return false end
    local rest = text:sub(#me + 1)
    return rest == "" or rest:find("^[%s%-]") ~= nil
end

function Plate.IsQuestUnit(u)
    if plain(IsInInstance) == true then return false end
    -- Players are never quest targets, so their tooltips aren't read.
    if plain(UnitIsPlayer, u) == true or Plate.NoQuests() then return false end
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret and plain(C_Secrets.ShouldUnitIdentityBeSecret, u) ~= false then
        return false
    end
    local info = unitTooltip(u)
    local types = Enum and Enum.TooltipDataLineType
    if type(info) ~= "table" or type(info.lines) ~= "table" or not types then return false end
    local me = plain(UnitName, "player")
    local mine = true
    for _, line in ipairs(info.lines) do
        local kind, text = line.type, line.leftText
        if not isSecret(kind) and not isSecret(text) then
            if kind == types.QuestTitle then
                mine = true
            elseif kind == types.QuestPlayer then
                mine = Plate.IsMyQuestLine(text, me)
            elseif kind == types.QuestObjective and mine and type(text) == "string" then
                local have, need = string.match(text, "(%d+)/(%d+)")
                if have and have ~= need then return true, have .. "/" .. need end
                local pct = string.match(text, "(%d+)%%")
                if pct and pct ~= "100" then return true, pct .. "%" end
            end
        end
    end
    return false
end

-- What the Quests module says this unit is needed for (questIcon): kind (kill,
-- loot, use, explore) and the quest's color. Uses the GUID only when plain.
function Plate.QuestKind(p)
    local fn = DUI.QuestKindForUnit
    if type(fn) ~= "function" or p.isSample then return nil end
    local guid = UnitGUID(p.unit)
    if type(guid) ~= "string" or isSecret(guid) then return nil end
    local ok, kind, r, g, b = pcall(fn, guid)
    if not ok or type(kind) ~= "string" then return nil end
    return kind, r, g, b
end

function Plate.UpdateQuest(p)
    local c = cfg()
    local isQuest, progress = false, nil
    if (c.quest or c.questBar) and not p.friendly then isQuest, progress = Plate.IsQuestUnit(p.unit) end
    p.questUnit = isQuest
    -- Quest mobs in their own color (questBar): repaint only when that changed.
    if p.colored and Plate.MobKind(p, Plate.Cfg(p)) ~= p.kind then Plate.UpdateBarColor(p) end
    local shown = isQuest and c.quest and true or false
    -- The count ("4/10") just left of the !, the raid marker past both.
    local counted = shown and cfg().questCount and progress ~= nil or false
    local text = counted and progress or ""
    local kind, r, g, b
    if shown and cfg().questIcon ~= false then kind, r, g, b = Plate.QuestKind(p) end
    -- Runs on every plate for every quest log burst, so only touch it on a change
    -- (the count is a plain string read from the tooltip).
    if p.questShownNow == shown and p.questTextNow == text and p.questKindNow == kind and p.questRNow == r then return end
    local appear = shown and not p.questShownNow
    p.questShownNow, p.questTextNow, p.questKindNow, p.questRNow = shown, text, kind, r
    if kind then
        -- The symbol's dark edge drawn inline holds the mark's space; the symbol goes over it.
        p.quest:SetText("|T" .. DUI.MEDIA .. "objective-" .. kind .. "-edge.png:0|t")
        p.questArt.icon:SetTexture(DUI.MEDIA .. "objective-" .. kind .. ".png")
        p.questArt.icon:SetVertexColor(r or 1, g or 1, b or 1)
    else
        p.quest:SetText("!")
    end
    p.quest:SetShown(shown)
    p.questArt:SetShown(kind ~= nil)
    p.questCount:SetText(text)
    p.questCount:SetShown(counted)
    -- A new mark fades in FAST, since it matters in combat too.
    if appear then
        local M = DUI.Motion
        M.Tween("plates:quest:" .. tostring(p), 0, 1, M.FAST, function(a)
            p.quest:SetAlpha(a)
            p.questArt:SetAlpha(a)
        end)
    end
    Plate.PlaceSpots(p)
end

-- Other plates fade while your target is on a plate (dimOthers, to dimAlpha); your
-- target and any casting plate stay full. Plate.hasTarget is set by
-- Manager.UpdateTargets. Back up FAST (a cast must be seen at once), down at
-- NORMAL; snaps for a freshly shown plate.
Plate.hasTarget = false
function Plate.Dim(p, snap)
    local c = cfg()
    local goal = 1
    if c.dimOthers and Plate.hasTarget and not p.isTarget and not ns.Cast.Shown(p) then
        goal = c.dimAlpha or 0.5
    end
    if p.dimGoal == goal then return end
    local from = p.dimGoal or 1
    p.dimGoal = goal
    local M = DUI.Motion
    M.Tween(p, snap and goal or from, goal,
        goal > from and M.FAST or M.NORMAL, function(v) p:SetAlpha(v) end)
end

-- Marks your target as configured: a colored outline, a colored glow, or nothing.
function Plate.UpdateTarget(p)
    local target
    if p.isSample then target = p.sampleTarget == true else target = plain(UnitIsUnit, p.unit, "target") == true end
    local was = p.isTarget == true
    p.isTarget = target
    -- Power bar on your target only: it comes and goes with the target.
    if p.powerSet and was ~= target then ns.Power.Refresh(p) end
    ns.Minion.Target(p, target)
    local c = cfg()
    -- A name-only plate has no bar to mark (the ring would outline nothing).
    local style = (target and p.hp:IsShown()) and c.targetStyle or "none"
    -- Called for every plate whenever a plate comes or goes. If nothing changed (and
    -- no setting or style change since), there's nothing to repaint.
    -- Threat on the border also colors the outline around it (ApplyThreatBorder).
    local threat = c.threatBorder and p.threatNow or nil
    local marked = target and p.hp:IsShown()
    if p.markStyle == style and p.markGen == Plate.gen and p.markThreat == threat and p.markOn == marked then return end
    p.markStyle, p.markGen, p.markThreat, p.markOn = style, Plate.gen, threat, marked
    if style == "outline" then
        local r, g, b = Plate.TargetColor(c, c.targetOutline)
        if threat then r, g, b = threat[1], threat[2], threat[3] end
        local sweep = not threat and c.targetAccent and Style.AccentSweep()
        local lo, hi
        if sweep == "class" or sweep == "gold" then lo, hi = Style.AccentPair() end
        local round = p.outline.round or NONE
        for key, tex in pairs(p.outline.pieces) do
            local long = key == "TOP" or key == "BOTTOM"
            -- A curved corner keeps its own texture (Plate.LayoutRing).
            if not round[key] then
                tex:SetTexture((sweep == "daylight" and long) and Style.GRADIENT_FILE or Plate.LINE)
            end
            if sweep then
                -- Long edges carry the whole sweep (Daylight's image, or the class pair across a
                -- plain line); the ends take its first and last colors.
                local right = key:find("RIGHT") ~= nil
                local a = sweep == "daylight" and Style.GRADIENT[right and 2 or 1] or (right and hi or lo)
                if long and lo and tex.SetGradient then
                    tex:SetVertexColor(1, 1, 1, 1)
                    tex:SetGradient("HORIZONTAL", CreateColor(lo[1], lo[2], lo[3], 1), CreateColor(hi[1], hi[2], hi[3], 1))
                else
                    if long and sweep == "daylight" then a = WHITE end
                    tex:SetVertexColor(a[1], a[2], a[3], 1)
                end
            else
                tex:SetVertexColor(r, g, b, 1)
            end
        end
    end
    Plate.ShowRing(p.outline, style == "outline")
    if style == "glow" then
        local r, g, b = Plate.TargetColor(c, c.targetGlow)
        for _, tex in pairs(p.glow.pieces) do tex:SetVertexColor(r, g, b, Plate.GLOW_ALPHA) end
    end
    Plate.ShowRing(p.glow, style == "glow")
    Plate.ShowArrows(p, marked)
end

-- A target ring draws on from left to right over WIPE_TIME, eased out, starting
-- the frame you target so the information is never late. On untarget it runs back
-- right to left, then hides; either way it reverses from where it is (ring.wipeP,
-- 0 to 1). Drawn with the ring's own pieces: left side and corners at once, top and
-- bottom edges growing (one anchor plus a width), right side and corners fading in
-- as the edges reach them. No clip frame: clipping is expensive to draw and cost
-- frames on every target switch. Motion off: all at once.
Plate.WIPE_TIME = 0.5 -- a bit slower than SLOW (0.4 felt fast)
Plate.WIPE_RIGHT = 0.85 -- how far across the edges get before the right end starts to show

local function wipeStep(ring, p)
    ring.wipeP = p
    local e, g = ring.pieces, ring.edges
    if not g then return end
    local w = g.frame:GetWidth()
    e.TOP:ClearAllPoints()
    e.TOP:SetPoint("BOTTOMLEFT", g.frame, "TOPLEFT", g.left, 0)
    e.TOP:SetWidth(math.max(0.001, (w - g.left - g.topEnd) * p))
    e.BOTTOM:ClearAllPoints()
    e.BOTTOM:SetPoint("TOPLEFT", g.frame, "BOTTOMLEFT", g.left, 0)
    e.BOTTOM:SetWidth(math.max(0.001, (w - g.left - g.bottomEnd) * p))
    if not ring.soft then
        -- A gradient edge keeps its colors in place: cropped, not squeezed.
        e.TOP:SetTexCoord(0, p, 0, 1); e.BOTTOM:SetTexCoord(0, p, 0, 1)
    end
    local right = math.max(0, math.min(1, (p - Plate.WIPE_RIGHT) / (1 - Plate.WIPE_RIGHT)))
    e.RIGHT:SetAlpha(right); e.TOPRIGHT:SetAlpha(right); e.BOTTOMRIGHT:SetAlpha(right)
    placeGleams(ring, p, right)
end

Plate.WipeStep = wipeStep

-- Back to the ring's own layout (both edges pinned at both ends).
local function wipeDone(ring)
    local e, g = ring.pieces, ring.edges
    hideGleams(ring)
    e.RIGHT:SetAlpha(1); e.TOPRIGHT:SetAlpha(1); e.BOTTOMRIGHT:SetAlpha(1)
    if not g then return end
    if not ring.soft then e.TOP:SetTexCoord(0, 1, 0, 1); e.BOTTOM:SetTexCoord(0, 1, 0, 1) end
    e.TOP:ClearAllPoints()
    e.TOP:SetPoint("BOTTOMLEFT", g.frame, "TOPLEFT", g.left, 0)
    e.TOP:SetPoint("BOTTOMRIGHT", g.frame, "TOPRIGHT", -g.topEnd, 0)
    e.BOTTOM:ClearAllPoints()
    e.BOTTOM:SetPoint("TOPLEFT", g.frame, "BOTTOMLEFT", g.left, 0)
    e.BOTTOM:SetPoint("TOPRIGHT", g.frame, "BOTTOMRIGHT", -g.bottomEnd, 0)
end

-- Off at once, no sweep: the unit is gone, and a reused plate must never play the
-- previous unit's outline fading away.
function Plate.DropRing(ring)
    -- Never lit (most plates, each time one leaves): nothing to restore.
    if not ring:IsShown() and not ring.wipeDir then return end
    ring.wipeToken = nil
    DUI.Motion.Tween(ring, 0, 0, 0) -- stops a sweep in progress
    ring.wipeDir, ring.wipeP = nil, 0
    wipeDone(ring)
    ring:Hide()
end

function Plate.ShowRing(ring, on)
    local showing = ring:IsShown() and ring.wipeDir ~= "out"
    if on == showing then return end
    ring.wipeToken = nil
    if not DUI.Motion.On() then
        DUI.Motion.Tween(ring, 0, 0, 0) -- stops a sweep in progress
        ring.wipeDir, ring.wipeP = nil, on and 1 or 0
        wipeDone(ring)
        ring:SetShown(on)
        return
    end
    local from = ring:IsShown() and (ring.wipeP or 1) or 0
    local to = on and 1 or 0
    wipeStep(ring, from)
    ring:Show()
    ring.wipeDir = on and "in" or "out"
    local token = {}
    ring.wipeToken = token
    DUI.Motion.Tween(ring, from, to, Plate.WIPE_TIME * math.abs(to - from), function(v)
        if ring.wipeToken ~= token then return end
        ring.wipeP = v
        wipeStep(ring, v)
    end, function()
        if ring.wipeToken ~= token then return end
        ring.wipeToken, ring.wipeDir, ring.wipeP = nil, nil, to
        wipeDone(ring)
        if not on then ring:Hide() end
    end)
end

-- Mouseover highlight strength, 0 to 1 (hoverLight setting).
function Plate.HoverLight()
    local k = ns.cfg and tonumber(ns.cfg.hoverLight)
    return k and math.max(0, math.min(1, k)) or Plate.HOVER
end

-- Plate.hovered: the one plate lit for the mouse (Manager clears it).
function Plate.UpdateHover(p)
    local on = plain(UnitIsUnit, p.unit, "mouseover") == true
    -- Brightness from hoverLight (0 = never lit). Its alpha is the color's alpha; the
    -- client treats them as one number.
    local k = Plate.HoverLight()
    p.hover:SetAlpha(k)
    p.hover:SetShown(on and k > 0)
    ns.Minion.Hover(p, on and k > 0, k)
    if on then Plate.hovered = p elseif Plate.hovered == p then Plate.hovered = nil end
end

-- Calls fn(p) with the unit's tooltip read at most once (title line and quest mark
-- share it).
local function withTooltip(fn, p)
    tipOpen, tipFor, tipInfo = true, nil, nil
    local ok, err = pcall(fn, p)
    tipOpen, tipFor, tipInfo = false, nil, nil
    if not ok then error(err, 0) end
end

-- What you see first: the bar, its colors, the name, the target mark, a cast.
local function updateNow(p)
    Plate.UpdateHealth(p, true)
    Plate.UpdatePrediction(p)
    ns.Minion.Update(p)
    Plate.UpdateDots(p)
    Plate.UpdateColor(p)
    Plate.UpdateTarget(p)
    Plate.UpdateHover(p)
    ns.Power.Refresh(p, true)
    ns.Cast.Update(p)
end

-- The rest: level, guild or title line, quest mark, raid marker.
-- colorNext: Plate.UpdateColor runs right after (it redoes the class text).
local function updateRest(p, colorNext)
    Plate.UpdateLevel(p)
    Plate.UpdateDragon(p)
    Plate.UpdateSub(p, colorNext)
    Plate.UpdateMarker(p)
    Plate.UpdateQuest(p)
end

-- Everything at once (a settings change). New plate pieces go in updateNow (seen
-- first) or updateRest (the frame after a plate appears); both run here.
local function updateAll(p)
    updateRest(p, true)
    updateNow(p)
end

function Plate.UpdateAll(p) withTooltip(updateAll, p) end

-- A new plate shows the essentials at once and does the rest the next frame, in
-- one pass for every plate that appeared meanwhile. Turning the camera in a crowd
-- shows many plates at once, and each one's tooltip read and text were the spike.
-- Nothing shows late: the pass runs before the next frame is drawn.
local later, laterQueued = {}, false
local function finishLater()
    laterQueued = false
    for p, unit in pairs(later) do
        later[p] = nil
        local usable = not ns.Manager or ns.Manager.Usable(p)
        if usable and p.unit == unit then DUI.SafeCall(withTooltip, updateRest, p) end
    end
end

function Plate.UpdateFirst(p)
    updateNow(p)
    later[p] = p.unit
    if not laterQueued then
        laterQueued = true
        C_Timer.After(0, finishLater)
    end
end

-- ---------------------------------------------------------------------
-- Its unit
-- ---------------------------------------------------------------------

Plate.UNIT_EVENTS = {
    UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health",
    UNIT_HEAL_PREDICTION = "predict", UNIT_ABSORB_AMOUNT_CHANGED = "predict",
    UNIT_NAME_UPDATE = "name", UNIT_FACTION = "color", UNIT_FLAGS = "color",
    UNIT_LEVEL = "level", UNIT_CLASSIFICATION_CHANGED = "level",
    -- A mob changing power type (a druid's form): a caster color comes or goes.
    UNIT_DISPLAYPOWER = "kind",
    -- Not UNIT_THREAT_SITUATION_UPDATE: it names the unit whose situation changed
    -- (you, a party member; the game's UnitFrame.lua matches it to the frame's
    -- feedbackUnit "player"), never the mob a plate shows.
    UNIT_THREAT_LIST_UPDATE = "color",
}

local THREAT_EVENTS = { UNIT_THREAT_LIST_UPDATE = true }

function Plate.OnEvent(p, event, unit, ...)
    if not p.unit then return end
    local what = Plate.UNIT_EVENTS[event]
    if what == "health" then
        Plate.UpdateCorpse(p)
        if event == "UNIT_MAXHEALTH" then Plate.UpdateHealthMax(p) end
        Plate.UpdateHealth(p)
        -- The heal and absorb bars only follow the max (their amounts have their own
        -- events, and they hang off the fill's end on their own).
        if event == "UNIT_MAXHEALTH" then Plate.UpdatePrediction(p) end
    elseif what == "predict" then
        Plate.UpdatePrediction(p)
    elseif what == "name" then
        Plate.UpdateSub(p, true)
        Plate.UpdateColor(p) -- the name and its class copies
    elseif what == "color" then
        -- Threat lists change many times a second in combat; the plate only changes when
        -- the threat color does. The threat % follows every update (it changes while the
        -- color holds).
        if THREAT_EVENTS[event] and p.colored and Plate.ThreatColor(p.unit) == p.threatNow then
            Plate.UpdateThreatPct(p)
            Plate.UpdateThreatSize(p)
            return
        end
        -- Friend or foe can change under a plate; then everything is redone.
        if not THREAT_EVENTS[event] and Plate.UpdateFriendly(p) then return end
        -- Flags change for many reasons (combat, PvP, sitting...); only repaint the bar
        -- when tapped or reaction changed.
        if event == "UNIT_FLAGS" and p.colored then
            local sig = Plate.FlagSig(p.unit)
            if sig ~= nil and sig == p.flagSig then return end
        end
        -- Only a faction change can recolor the name.
        if event == "UNIT_FACTION" then Plate.UpdateColor(p) else Plate.UpdateBarColor(p) end
    elseif what == "level" or what == "kind" then
        if what == "level" then
            Plate.UpdateLevel(p)
            Plate.UpdateDragon(p)
        end
        -- Its special color, only when that changed.
        if p.colored and Plate.MobKind(p, Plate.Cfg(p)) ~= p.kind then Plate.UpdateBarColor(p) end
        -- New power type: update the power bar's color, or show or hide it.
        if what == "kind" and p.powerSet then ns.Power.Refresh(p) end
    elseif event == "UNIT_POWER_UPDATE" then
        ns.Power.Value(p)
    elseif event == "UNIT_MAXPOWER" then
        ns.Power.Update(p)
    elseif ns.Cast.EVENTS[event] then
        ns.Cast.OnEvent(p, event, unit, ...)
    end
end

-- A friendly plate is one you can't attack. While dead you can't attack anything,
-- so then the game's own check decides (its plate asks UnitIsFriend); otherwise
-- every mob seen on the corpse run would be name-only.
function Plate.IsFriendly(unit)
    if plain(UnitCanAttack, "player", unit) ~= false then return false end
    if plain(UnitIsDeadOrGhost, "player") == true then
        return plain(UnitIsFriend, "player", unit) == true
    end
    return true
end

local function listen(p, unit)
    p:UnregisterAllEvents()
    p.powerEvents = nil -- the power bar's own, re-registered by Power.Refresh
    for event in pairs(Plate.UNIT_EVENTS) do
        if event == "UNIT_FACTION" then -- your own changing counts too (a duel, PvP), as on the game's plate
            pcall(p.RegisterUnitEvent, p, event, unit, "player")
        else
            pcall(p.RegisterUnitEvent, p, event, unit)
        end
    end
    if not p.friendly then
        for event in pairs(ns.Cast.EVENTS) do pcall(p.RegisterUnitEvent, p, event, unit) end
    end
end

-- Checked again whenever the answer can change (a mob turning hostile, dying or
-- resurrecting, a loading screen: Manager.Recheck). Returns true if it changed,
-- and the plate is then set up again as the other kind.
function Plate.UpdateFriendly(p)
    local unit = p.unit
    if not unit then return false end
    Plate.UpdateCorpse(p)
    local now = Plate.IsFriendly(unit)
    if now == p.friendly then return false end
    p.friendly = now
    listen(p, unit)
    if now then ns.Cast.Stop(p, true) end
    Plate.Layout(p)
    ns.Auras.SetUnit(p, unit)
    Plate.UpdateAll(p)
    if p.isTarget and ns.Manager then ns.Manager.UpdateTargets() end
    return true
end

function Plate.Install(p, unit)
    p.unit = unit
    p.friendly = Plate.IsFriendly(unit)
    p.object = Plate.IsObject(unit)
    listen(p, unit)
    Plate.Layout(p)
    ns.Auras.SetUnit(p, unit)
    Plate.UpdateFirst(p)
    local np = p.nameplate
    Plate.PlaceStack(p)
    if np.SetStackingBoundsFrame then pcall(np.SetStackingBoundsFrame, np, p.stack) end
    p.corpse = Plate.IsCorpse(unit)
    Plate.ShowNow(p)
end

function Plate.Uninstall(p)
    p:UnregisterAllEvents()
    -- The next unit starts clean: no size group, no known color or mark, nothing of
    -- this unit left showing. Its level, guild or title line, quest mark and raid
    -- marker arrive the frame after it's shown (Plate.UpdateFirst).
    p.sizeGroup, p.colored, p.corpse, p.threatSize = nil, nil, nil, nil
    p.guild, p.questShownNow, p.questTextNow, p.questUnit = nil, nil, nil, nil
    p.questKindNow, p.questRNow = nil, nil
    p.level:SetText("")
    p.threatPct:Hide()
    p.dragon:Hide()
    p.sub:SetText("")
    p.sub:Hide()
    p.quest:Hide()
    p.questArt:Hide()
    p.questCount:Hide()
    -- No longer your target: its marks go now, with no sweep out on the next unit.
    p.isTarget, p.markStyle = nil, nil
    Plate.DropRing(p.outline)
    Plate.DropRing(p.glow)
    -- The combo row leaves, and its cast bar is laid out fresh for the next unit (it
    -- may have dropped below the row).
    if ns.Combo and ns.Combo.Leave then ns.Combo.Leave(p) end
    ns.Power.Leave(p)
    p.castStale = true
    p.marker:Hide()
    p.dotVeil:Hide()
    p.dotSkull:Hide()
    p.exec.lit:SetAlpha(0)
    p.execIcon:SetAlpha(0)
    ns.Auras.SetUnit(p, nil)
    ns.Cast.Stop(p, true)
    ns.Cast.Unkick(p)
    DUI.Motion.KickTagOff(p.kickTag)
    ns.Minion.Clear(p)
    DUI.Motion.Tween(p, 1, 1, 0) -- stops a fade in progress
    p.dimGoal = nil
    p:SetAlpha(1)
    p.unit = nil
    p:Hide()
end
