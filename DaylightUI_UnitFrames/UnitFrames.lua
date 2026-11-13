-- Shared unit frame builder: a secure unit button in the core shell, with a
-- textured health bar and optional power bar. Player and target get the
-- DaylightUI silhouette: a soft angled inner end, the name in a tab above the
-- outer end and a big health number in the inner corner. Smaller frames keep
-- the name centered on the bar. Any value read from a unit may be secret, and
-- secrets only ever go into widget setters that accept them.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local UF = {}
ns.UF = UF

-- Each frame picks its own bar textures and fonts on its page (settings
-- <frame>.media.*, Defaults.lua; "general" follows General > Appearance).
-- UF.MEDIA[frame] = { bars = { health, power }, fonts = { name, health, power } }
-- slot ids. The cast bars (UF.MEDIA.cast[unit]), swing timer and combo points
-- have their own ({ bar, font }).
UF.MEDIA = { cast = {} }
local Media = DUI.Media
for _, k in ipairs(ns.MEDIA_FRAMES) do
    local p, m = "uf." .. k, { bars = {}, fonts = {} }
    for _, b in ipairs({ "health", "power" }) do
        m.bars[b] = p .. "." .. b
        Media.RegisterBar(m.bars[b], "UnitFrames", k .. ".media." .. b, k .. ".media." .. b .. "Back")
    end
    for _, t in ipairs({ "name", "health", "power" }) do
        m.fonts[t] = p .. ".font." .. t
        Media.RegisterSlot(m.fonts[t], "UnitFrames", k .. ".media." .. t .. "Font", "font")
    end
    UF.MEDIA[k] = m
end
local function barAndFont(id, key)
    Media.RegisterBar(id, "UnitFrames", key .. ".media.bar", key .. ".media.barBack")
    Media.RegisterSlot(id .. ".font", "UnitFrames", key .. ".media.font", "font")
    return { bar = id, font = id .. ".font" }
end
for _, u in ipairs({ "player", "target", "focus", "party" }) do UF.MEDIA.cast[u] = barAndFont("uf.cast." .. u, u .. "Castbar") end
UF.MEDIA.swing = barAndFont("uf.swing", "swing")
-- The target's threat % tag. With "general" it uses the health font.
UF.MEDIA.target.fonts.threat = "uf.target.font.threat"
Media.RegisterSlot(UF.MEDIA.target.fonts.threat, "UnitFrames", "target.media.threatFont", "font", UF.MEDIA.target.fonts.health)

-- You as a sample (test mode, the options pages, the setup guide): a copy of
-- base with your own class and your name as the element shows it
-- (DUI.UnitName). fallbackClass is used when the class can't be read.
function UF.You(element, base, fallbackClass)
    local _, class = UnitClass("player")
    local name = DUI.UnitName("player", element)
    local s = {}
    for k, v in pairs(base) do s[k] = v end
    s.class = type(class) == "string" and class or fallbackClass
    s.name = type(name) == "string" and name or DUI.L["You"]
    s.portraitClass = s.class
    return s
end
UF.MEDIA.combo = { bar = "uf.combo" }
Media.RegisterBar(UF.MEDIA.combo.bar, "UnitFrames", "combo.media.bar", "combo.media.barBack")
-- The personal display's bars. With "general" they use the player frame's.
UF.MEDIA.personal = { bars = { health = "uf.personal.health", power = "uf.personal.power" },
                      fonts = { health = "uf.personal.font.health", power = "uf.personal.font.power" } }
for _, b in ipairs({ "health", "power" }) do
    Media.RegisterBar(UF.MEDIA.personal.bars[b], "UnitFrames", "personal.media." .. b, "personal.media." .. b .. "Back",
                      UF.MEDIA.player.bars[b])
    Media.RegisterSlot(UF.MEDIA.personal.fonts[b], "UnitFrames", "personal.media." .. b .. "Font", "font", UF.MEDIA.player.fonts[b])
end

-- The settings key a frame's spec reads (player... party, raid, partyPet).
function UF.FrameKey(spec)
    if spec.group then return spec.group end
    local u = spec.unit or "player"
    if string.find(u, "^partypet") then return "partyPet" end
    if string.find(u, "^arena%d") then return "arena" end
    return u
end

-- A frame's slots (UF.MEDIA): its own, or the player's for a unit without a page.
function UF.MediaOf(spec)
    return UF.MEDIA[UF.FrameKey(spec)] or UF.MEDIA.player
end

UF.NAME_COLOR = DUI.Style.INK.VALUE   -- names: a warm soft white
UF.SLANT = 0.21         -- width of the angled end, as a share of frame height
UF.TAB_HEIGHT = 16
UF.TAB_INSET = 10       -- tab distance from the outer end
UF.TAB_PAD = 8
UF.BIG_NUMBER_COLOR = DUI.Style.INK.VALUE
UF.WHITE = { 1, 1, 1 }
UF.BIG_NUMBER_INSET = 3   -- gap from the angled end
UF.BIG_NUMBER_DROP = 1.5  -- below center, since the digits sit high in their line
-- Elite, rare and boss units get a crest on the name tab's outer corner: a
-- dark disc with a ring and a horned helm emblem, gold or silver, glowing.
UF.CREST = { elite = "gold", worldboss = "gold", rareelite = "gold", rare = "silver" }
UF.CREST_COLORS = { gold = { 0.94, 0.77, 0.31 }, silver = { 0.84, 0.86, 0.90 } }
UF.CREST_SIZE = 22
-- Portrait rings are flat graphic bands (tools/make_elite_ring.py), their
-- outer edge at RING_OUTER of the image's half-size. An elite's dragon wraps
-- the same ring from behind (tools/make_dragon_border.py). It has no ring of
-- its own, so the ring, its colors and the aggro fill are shared by every
-- portrait. The dragon image is bigger, with the ring filling DRAGON_RING of it.
UF.RING_OUTER = 0.60
UF.DRAGON_FILE = DUI.MEDIA .. "portrait-dragon.png"
UF.DRAGON_RING = 0.75
-- Aggro leaves the dragon's color alone (only the ring goes red and pulses).
-- Its eyes catch fire instead, a soft light flaring with the ring's pulse.
-- The eye position from the image's middle and the light's size are fractions
-- of the dragon image's width (x is for a ring on the right).
UF.DRAGON_EYE = { x = -0.0996, y = 0.285, size = 0.13, core = 0.06 }
-- The fire is painted (BLEND), not added: adding red to gold leaves it gold,
-- since gold's red channel is already full. The core and pulse add light on top.
UF.EYE_FIRE = { 0.8, 0.05, 0.03 }    -- the fire around the eye
UF.EYE_CORE = { 0.6, 0.15, 0.08 }    -- its hot middle, added to the fire for a bright red
UF.RING_COLOR = { 0.34, 0.34, 0.36 }
-- The plain ring's color (<frame>.portraitRing, UF.PaintRing). light: the gray
-- above. dark: the frame border's warm band, lit at the top like the shell.
-- class: the unit's gradient pair (same as the health bars: class, else
-- reaction), light end on top. accent: your accent on every frame (a gradient
-- accent's pair, else its single color on RING_LIT_FILE). daylight: the
-- Daylight gradient, oriented like the accent. With anything but light, the
-- red aggro band and its sweep use RING_LIT_FILE (the band shaded top to
-- bottom) so the flat red reads as a gradient too.
UF.RING_COLORS = { light = "Light", dark = "Dark", class = "Class gradient",
    accent = "Accent color", daylight = "Daylight gradient" }
UF.RING_COLOR_ORDER = { "light", "dark", "class", "accent", "daylight" }
UF.RING_FILE = DUI.MEDIA .. "portrait-band.png"
UF.RING_LIT_FILE = DUI.MEDIA .. "portrait-band-lit.png"
-- The ring's thickness (portraits.ringWidth): its opening as a fraction of its
-- outer edge, each with its own art (tools/make_elite_ring.py), with or without
-- the groove around its middle (portraits.ringLine). Every layer on the ring
-- (red band, sweep, pulse, arrival light) uses the same file, so each fits
-- whichever ring is picked.
UF.RING_WIDTHS = { thin = 0.85, normal = 0.772, thick = 0.68 }
UF.RING_WIDTH_NAMES = { thin = "Thin", normal = "Normal", thick = "Thick" }
UF.RING_WIDTH_ORDER = { "thin", "normal", "thick" }
function UF.RingFiles(width, line)
    width = UF.RING_WIDTHS[width] and width or "normal"
    local base = DUI.MEDIA .. "portrait-band" .. (width == "normal" and "" or "-" .. width) .. (line == false and "-smooth" or "")
    return base .. ".png", base .. "-lit.png", UF.RING_WIDTHS[width]
end
UF.ELITE_RING_COLORS = { gold = { 1.0, 0.8, 0.33 }, silver = { 0.84, 0.87, 0.92 } }
-- Your own dragon's color (player.portraitDragonColor): an elite's gold or
-- silver, the accent (its pair, light end on top, for a gradient accent), or
-- your class gradient like the class ring.
UF.DRAGON_COLORS = { gold = "Gold", silver = "Silver", accent = "Accent", class = "Class gradient" }
UF.DRAGON_COLOR_ORDER = { "gold", "silver", "accent", "class" }
-- Aggro on a target or focus ring (and your own when entering combat) fills
-- red clockwise behind a glowing head, and unwinds when it ends. Drawn with a
-- Cooldown swipe using the band as its texture (makeFill/drawFill). The
-- SetReverse direction for a clockwise fill was verified in game.
UF.RING_FILL_REVERSE = true
UF.RING_FILL_TIME = 0.57  -- a full turn; a partial turn takes its fraction
-- Threat: red while the unit is attacking you (and on your own frame while
-- you're in combat). With a portrait it's a bright band laid over the ring (an
-- elite's spikes stay gold), without one it's the name tab's border. In a
-- group the target's ring turns orange first as you near the pull threshold
-- (warn), and a small tag on its top inner corner shows your threat as a
-- percent of the pull (100 means it turns on you).
UF.THREAT_COLORS = { aggro = { 0.92, 0.2, 0.18 }, warn = { 1.0, 0.55, 0.12 } }
UF.PULSE_TIME = 0.6    -- aggro pulse: half a breath in seconds, bouncing
UF.PULSE_ALPHA = 0.75  -- its peak alpha
UF.HALO_ALPHA = 0.9    -- the halo past the ring, at its peak
UF.HALO_SIZE = 3.1     -- the halo's width, in ring radii
UF.THREAT_BAND_DIM = 0.45   -- the tab's band, as a fraction of the color
UF.THREAT_TAG_W = 36        -- the threat tag's width (fits "100%" and its angled end)

-- Status icons (tools/make_flat_icons.py), flat like the markers: a crown for
-- the group leader on top of the ring, Zzz on your ring's upper outer shoulder
-- while resting, and a level badge at the ring's foot (colored by difficulty
-- on other units). Sizes are fractions of the ring's radius.
UF.STATUS = {
    leader = { file = "status-leader.png", size = 0.52, color = { 1.0, 0.8, 0.33 } },
    rest = { file = "status-rest.png", size = 0.48, color = { 0.6, 0.75, 1.0 } },
    level = { file = "status-level.png", size = 0.8 },
    pvp = { file = "status-pvp.png", size = 0.66 },
}
-- PvP flagged: crossed swords, tinted by faction (Horde red, Alliance blue,
-- neither or unknown a soft gray).
UF.PVP_COLORS = { Horde = { 0.85, 0.2, 0.2 }, Alliance = { 0.25, 0.55, 0.95 } }
UF.PVP_NEUTRAL = { 0.65, 0.65, 0.68 }
-- Role icons (tank, healer, damage): flat badges from the role the member
-- picked (UnitGroupRolesAssigned). Party frames and raid tiles only
-- (spec.role). Unknown or none shows nothing.
UF.ROLE_ICON_TEXTURE = DUI.MEDIA .. "roles.png"
-- Each role's quarter of that 2 x 2 sheet.
UF.ROLE_COORDS = {
    TANK = { 0, 0.5, 0, 0.5 },
    HEALER = { 0.5, 1, 0, 0.5 },
    DAMAGER = { 0, 0.5, 0.5, 1 },   -- the game's word (UnitGroupRolesAssigned)
}
UF.ROLE_SIZE = 0.62      -- as a fraction of the portrait ring's radius
UF.LEVEL_SELF_COLOR = DUI.Style.INK.VALUE  -- warm white, like names and the big number
UF.LEVEL_NUDGE = { 1, -0.75 }
-- Without a portrait the badge is smaller, and the digits sat low in it.
UF.LEVEL_NUDGE_BARE = { 1, 0.75 }
UF.LEVEL_UP_BUMP = 1.4  -- how big the level badge swells as you gain a level, easing back (SLOW)
UF.LEVEL_LIFT = 0.3     -- difficulty colors eased toward white so they read on the dark badge
UF.SKULL_SIZE = 0.62    -- the skull, as a fraction of the badge
-- The badge's rim matches the portrait ring: dark gray, or an elite's gold or
-- a rare's silver.
UF.LEVEL_RING = UF.RING_COLOR
UF.MARKER_SIZE = 13
UF.CORNER_ICON = 11          -- a tile's raid marker and role icon, in the health bar's corners
UF.TALL_TILE = 36            -- a tile this tall stacks its name over its health text
-- The raid marker is a cell of the 4 x 2 marker sheet. SetSpriteSheetCell
-- accepts the client's secret index (a target's often is), while inline text
-- built from a secret index draws nothing with custom icons.
UF.MARKER_SHEET = DUI.MEDIA .. "markers.png"
UF.MARKER_ROWS, UF.MARKER_COLS = 2, 4
UF.CORNER_CROWN = 11
-- The marker, crown and role icon's "home" spot (the party's default) is with
-- the name tab or portrait. A frame with neither puts them at these corners.
UF.ICON_HOME = "home"
UF.HOME_CORNER = { markerPos = "bottomright", leaderPos = "topleft", rolePos = "bottomleft" }

-- An icon's spot (a Spots spot), or nil for home. home: the frame currently
-- has one. Only party buttons (spec.cornerIcons) move an icon away from home.
-- The player's and target's marker always stays with the name.
function UF.IconSpot(f, cfg, key, home)
    local spot = cfg[key]
    local valid = ns.Spots.Valid(spot)
    if home and not (valid and f.spec.cornerIcons) then return nil end
    return valid and spot or UF.HOME_CORNER[key]
end

UF.NO_NUDGE = { x = 0, y = 0 }

-- A size the player picked, or nil while it's still the default (an icon at
-- home then takes the size that fits there, like the marker in a tab).
function UF.PickedSize(v, default)
    local n = tonumber(v)
    return n and n ~= default and n or nil
end

-- A ready check answer on a group tile (UF.UpdateReady): flat white icons,
-- tinted by meaning. They stay READY_HOLD seconds after the check ends (the
-- game's own stay 11), then ease away.
UF.READY = {
    ready = { file = "status-ready.png", ink = "GOOD" },
    notready = { file = "status-notready.png", ink = "BAD" },
    waiting = { file = "status-waiting.png", ink = "WARN" },
}
UF.READY_SIZE = 14
UF.READY_HOLD = 10
UF.TAB_MAX = 0.6  -- fraction of the frame; longer names are cut short with "..."
-- The name tab's border: half the frame's, but never too thin for the band.
UF.TAB_BORDER = function(px) return math.max(3, math.floor(px / 2 + 0.5)) end

-- Portraits: a ring over the outer end, its center pushed past the end by
-- PORTRAIT_OUT of its radius. The ring's inside is RING_INNER of its outer
-- edge. A 3D model is a square whose corners stay hidden under the ring.
UF.PORTRAIT_SIZE = 1.33   -- diameter, as a fraction of frame height
UF.PORTRAIT_OUT = 0.35
UF.RING_INNER = 0.772
-- A dark bezel just inside the ring (outer edge at RIM_OUTER of the radius,
-- solid in to 84% of that), covering a 3D model's straight edges. Only the 3D
-- portrait needs it. Icons and faces run right up to the ring.
UF.RIM_OUTER = 0.80
-- Class icons overfill the opening so the round mask crops them evenly at the
-- ring. Width as a fraction of the opening's radius (2 fills it exactly).
UF.CLASS_ICON_FILL = 2.3
UF.MODEL_CLOSER = 0.92    -- 3D camera distance, slightly closer than the game's portrait framing
UF.PORTRAIT_MODES = { none = "None", class = "Class icon", ["2d"] = "2D portrait", ["3d"] = "3D portrait" }
UF.PORTRAIT_ORDER = { "none", "class", "2d", "3d" }

UF.MIN_PORTRAIT_HEIGHT = 20   -- shorter frames get no ring, it would swamp them

-- The two styles (Defaults.lua, RIBBON_FRAMES). In Ribbon the frame is a slim
-- bar, its name and health number float on a row above it (the name tab with
-- its shell hidden), and its power is a thin line hung under it (PowerBar.lua),
-- with the angle carried through both.
UF.STYLES = { daylight = "Daylight", ribbon = "Ribbon" }
UF.STYLE_ORDER = { "daylight", "ribbon" }
UF.RIBBON_GAP = 2           -- gap between the bar and its line, when unset
UF.RIBBON_RING = 0.56       -- the ring's radius, as a fraction of the whole ribbon's height
UF.RIBBON_TEXT_LIFT = 1     -- the row's texts sit this far above the bar's top edge
UF.RIBBON_NUMBER_INSET = 2  -- the health number's inset from the row's inner end
UF.RIBBON_NAME_SHARE = 0.62 -- the fraction of the row the name may take (the number gets the rest)

-- The style a frame's settings ask for: its own pick, or with "global" the one
-- for every frame (look.style). Settings without a style key (raid tiles,
-- target of target, pet) are always Daylight.
function UF.StyleOf(cfg)
    local own = type(cfg) == "table" and cfg.style or nil
    if type(own) ~= "string" then return "daylight" end
    if own == "global" then
        local db = ns.module and ns.module.db
        own = db and db.look and db.look.style
    end
    return own == "ribbon" and "ribbon" or "daylight"
end

function UF.IsRibbon(f, cfg)
    return type(f.spec) == "table" and f.spec.ribbon == true and UF.StyleOf(cfg) == "ribbon"
end

-- Whether a frame with these settings draws its power bar (its own Power bar
-- switch). The personal display has its own instead.
function UF.ShowsPower(cfg)
    return cfg.showPower ~= false
end

-- How far a frame with these settings reaches above its top and below its
-- bottom in Ribbon: the name row (f.hitTop) and the power line (f.foot, with
-- the border UF.ApplyShell gives it), in the frame's units. 0, 0 in Daylight.
-- For code that sizes room before the frame is laid out (the party's holder,
-- Group:Pads).
function UF.RibbonReach(cfg, frame)
    if UF.StyleOf(cfg) ~= "ribbon" then return 0, 0 end
    local up = ((cfg.showName ~= false and cfg.nameOnBar ~= true) or cfg.showPercent == true)
        and (tonumber(cfg.tabHeight) or UF.TAB_HEIGHT) or 0
    local down = 0
    if UF.ShowsPower(cfg) then
        local own = type(cfg.shell) == "table" and cfg.shell.own == true and tonumber(cfg.shell.borderPx)
        local px = own and (own > 0 and UF.TAB_BORDER(own) or 0) or UF.TAB_BORDER(DUI.DB.General().borderPx)
        down = Pixel.Snap(frame, tonumber(cfg.ribbonGap) or UF.RIBBON_GAP) + Pixel.Snap(frame, tonumber(cfg.powerHeight) or 4)
            + 2 * Pixel.Px(frame, px)
    end
    return up, down
end

-- The height a portrait is measured against: the frame's, or in Ribbon the
-- whole ribbon's (row, bar, line).
function UF.PortraitHeight(f, cfg)
    local h = tonumber(cfg.height) or 0
    if not UF.IsRibbon(f, cfg) then return h end
    h = h + (tonumber(cfg.tabHeight) or UF.TAB_HEIGHT)
    if UF.ShowsPower(cfg) then h = h + (tonumber(cfg.ribbonGap) or UF.RIBBON_GAP) + (tonumber(cfg.powerHeight) or 0) end
    return h
end

-- The portrait a frame shows: its setting, or none on a frame that's too short.
function UF.PortraitMode(f, cfg)
    if not f.portrait then return "none" end
    local mode = UF.PORTRAIT_MODES[cfg.portrait] and cfg.portrait or "none"
    if mode ~= "none" and UF.PortraitHeight(f, cfg) < UF.MIN_PORTRAIT_HEIGHT then return "none" end
    return mode
end

-- Class icons: Daylight UI's own set, or a style from the Jiberish Fabled Icons
-- pack when that addon is installed. Its sheets are read in place from its own
-- folder, never copied, since its license forbids redistribution.
UF.CLASS_ICONS = {
    WARRIOR = "class\\warrior.tga", PALADIN = "class\\paladin.tga", HUNTER = "class\\hunter.tga",
    ROGUE = "class\\rogue.tga", PRIEST = "class\\priest.tga", SHAMAN = "class\\shaman.tga",
    MAGE = "class\\mage.tga", WARLOCK = "class\\warlock.tga", DRUID = "class\\druid.tga",
}
-- The pack's folder names, newest first. It used to be ElvUI_JiberishIcons.
UF.ICON_PACKS = { "JiberishIcons", "ElvUI_JiberishIcons" }
UF.ICON_STYLES = {
    daylight = "DaylightUI", game = "The game's own", fabled = "Fabled", fabledcore = "Fabled Core", fableddimension = "Fabled Dimension",
    fabledmyth = "Fabled Myth", fabledpixels = "Fabled Pixels", fabledpixelsv2 = "Fabled Pixels v2",
    fabledrealm = "Fabled Realm", fabledrealmv2 = "Fabled Realm v2", intothevoid = "Into the Void",
    fabledclass = "Fabled Class", fabledregalia = "Fabled Regalia",
}
UF.ICON_STYLE_ORDER = { "daylight", "game", "fabled", "fabledclass", "fabledcore", "fableddimension", "fabledmyth",
    "fabledpixels", "fabledpixelsv2", "fabledrealm", "fabledrealmv2", "fabledregalia", "intothevoid" }
-- Sheets only the new folder has (the old one has no spec sheet either). The
-- old folder is never asked for them, since a missing file draws nothing.
UF.ICON_NEW_PACK_ONLY = { fabledclass = true, fabledregalia = true }
-- The classes in this game, for the per-class picks.
UF.ICON_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- The pack's spec sheet (8 x 8, filled row by row): this game's classes' specs,
-- keyed by spec ID, with their square on the sheet.
UF.ICON_SPECS = {
    [102] = { 4, DUI.L["Balance"], "DRUID" }, [103] = { 5, DUI.L["Feral"], "DRUID" },
    [104] = { 6, DUI.L["Guardian"], "DRUID" }, [105] = { 7, DUI.L["Restoration"], "DRUID" },
    [253] = { 8, DUI.L["Beast Mastery"], "HUNTER" }, [254] = { 9, DUI.L["Marksmanship"], "HUNTER" }, [255] = { 10, DUI.L["Survival"], "HUNTER" },
    [62] = { 11, DUI.L["Arcane"], "MAGE" }, [63] = { 12, DUI.L["Fire"], "MAGE" }, [64] = { 13, DUI.L["Frost"], "MAGE" },
    [65] = { 17, DUI.L["Holy"], "PALADIN" }, [66] = { 18, DUI.L["Protection"], "PALADIN" }, [70] = { 19, DUI.L["Retribution"], "PALADIN" },
    [256] = { 20, DUI.L["Discipline"], "PRIEST" }, [257] = { 21, DUI.L["Holy"], "PRIEST" }, [258] = { 22, DUI.L["Shadow"], "PRIEST" },
    [259] = { 23, DUI.L["Assassination"], "ROGUE" }, [260] = { 24, DUI.L["Outlaw"], "ROGUE" }, [261] = { 25, DUI.L["Subtlety"], "ROGUE" },
    [262] = { 26, DUI.L["Elemental"], "SHAMAN" }, [263] = { 27, DUI.L["Enhancement"], "SHAMAN" }, [264] = { 28, DUI.L["Restoration"], "SHAMAN" },
    [265] = { 29, DUI.L["Affliction"], "WARLOCK" }, [266] = { 30, DUI.L["Demonology"], "WARLOCK" }, [267] = { 31, DUI.L["Destruction"], "WARLOCK" },
    [71] = { 32, DUI.L["Arms"], "WARRIOR" }, [72] = { 33, DUI.L["Fury"], "WARRIOR" }, [73] = { 34, DUI.L["Protection"], "WARRIOR" },
}
-- Where each class sits on the pack's sheets: an 8 x 8 grid, column and row.
UF.ICON_PACK_CELLS = {
    WARRIOR = { 0, 0 }, MAGE = { 1, 0 }, ROGUE = { 2, 0 }, DRUID = { 3, 0 }, EVOKER = { 4, 0 },
    HUNTER = { 0, 1 }, SHAMAN = { 1, 1 }, PRIEST = { 2, 1 }, WARLOCK = { 3, 1 },
    PALADIN = { 0, 2 }, DEATHKNIGHT = { 1, 2 }, MONK = { 2, 2 }, DEMONHUNTER = { 3, 2 },
}

-- The installed pack's folder name, or nil.
function UF.IconPack()
    local api = C_AddOns
    if not (api and api.DoesAddOnExist) then return nil end
    for _, name in ipairs(UF.ICON_PACKS) do
        if api.DoesAddOnExist(name) == true then return name end
    end
    return nil
end

function UF.HasIconPack() return type(UF.IconPack()) == "string" end

local function specOf(key)
    local id = type(key) == "string" and tonumber(key:match("^spec:(%d+)$"))
    return id and UF.ICON_SPECS[id]
end

-- Whether the installed pack is the old folder and lacks this style or spec.
local function oldPackLacks(key)
    if UF.IconPack() ~= UF.ICON_PACKS[2] then return false end
    return UF.ICON_NEW_PACK_ONLY[key] or specOf(key)
end

-- Styles that need no pack: Daylight UI's own and the game's.
UF.ICON_BUILT_IN = { daylight = true, game = true }

-- The Icon style menu: every name (so a saved pick still reads right), the
-- built-in styles, and the styles the installed pack has. all: every style
-- regardless of what's installed, as the per-class rows list them.
function UF.IconStyleChoices(all)
    local order = {}
    local pack = all == true or UF.HasIconPack()
    for _, style in ipairs(UF.ICON_STYLE_ORDER) do
        if UF.ICON_BUILT_IN[style] or (pack and not oldPackLacks(style)) then order[#order + 1] = style end
    end
    return UF.ICON_STYLES, order
end

-- The game's own round class icon (its classicon-<class> atlas): file and
-- coordinates, or nil when this client has none.
function UF.GameClassIcon(token)
    if type(token) ~= "string" or not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, "classicon-" .. string.lower(token))
    if not ok or type(info) ~= "table" or type(info.file) == "nil" then return nil end
    return info.file, info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
end

-- A class's choices for the picker: Daylight UI's own, each style, then its specs.
function UF.ClassIconChoices(token)
    local _, keys = UF.IconStyleChoices(true)
    local ids = {}
    for id, spec in pairs(UF.ICON_SPECS) do
        if spec[3] == token then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return UF.ICON_SPECS[a][1] < UF.ICON_SPECS[b][1] end)
    for _, id in ipairs(ids) do
        local key = "spec:" .. id
        if not oldPackLacks(key) then keys[#keys + 1] = key end
    end
    return keys
end

function UF.ClassIconName(key)
    local spec = specOf(key)
    if spec then return string.format(DUI.L["%s (spec)"], spec[2]) end
    return UF.ICON_STYLES[key]
end

-- The file and texture coordinates for a class's icon: its own pick in picks
-- (a style or "spec:<id>") if it has one, else the style.
function UF.ClassIcon(token, style, picks)
    local pick = type(picks) == "table" and picks[token]
    if type(pick) == "string" and pick ~= "" then style = pick end
    if style == "game" then
        local file, l, r, t, b = UF.GameClassIcon(token)
        if file then return file, l, r, t, b end
    end
    local pack = style and not UF.ICON_BUILT_IN[style] and not oldPackLacks(style) and UF.IconPack()
    local spec = pack and specOf(style)
    if spec and spec[3] == token then
        local i = spec[1] - 1
        local x, y = (i % 8) / 8, math.floor(i / 8) / 8
        return "Interface\\AddOns\\" .. pack .. "\\Media\\Spec\\fabledspecializations.tga", x, x + 0.125, y, y + 0.125
    end
    local cell = UF.ICON_PACK_CELLS[token]
    if pack and UF.ICON_STYLES[style] and cell then
        local x, y = cell[1] / 8, cell[2] / 8
        return "Interface\\AddOns\\" .. pack .. "\\Media\\Class\\" .. style .. ".tga", x, x + 0.125, y, y + 0.125
    end
    local own = UF.CLASS_ICONS[token]
    if own then return DUI.MEDIA .. own, 0, 1, 0, 1 end
end

-- For other areas (chat whisper portraits): a class's icon as the unit frames'
-- Class icons setting picks it (Daylight UI's own, or a Jiberish style).
function DUI.ClassIcon(token)
    return UF.ClassIcon(token, DUI:Get("UnitFrames", "portraits.icons"), DUI:Get("UnitFrames", "portraits.classIcons"))
end

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Incoming heals and absorbs: bars hung off the end of the health fill (heals
-- first, absorbs after), fed the client's amounts untouched since they may be
-- secret. Each starts with the frame's angle. A small wedge bar fills the
-- triangle between the fill's angled edge and the segment's square start. The
-- wedge's range is 0..1, so any amount fills it and none empties it, with no
-- comparison needed.
UF.PREDICTION = {
    heals = { color = { 0.55, 0.95, 0.6 }, alpha = 0.5 },
    absorbs = { color = { 0.85, 0.92, 1.0 }, alpha = 0.55 },     -- the overshield's stripes, the same way
}
-- An overshield: a shield bigger than the missing health. The part that doesn't
-- fit runs back over the health from the frame's end, striped like any shield,
-- with a bright line where it starts.
UF.OVERSHIELD = {
    stripes = "Interface\\RaidFrame\\Shield-Overlay",
    glow = "Interface\\RaidFrame\\Shield-Overshield",
    alpha = 0.55,            -- the stripes over the health (also a shield's alpha)
    glowWidth = 10,
}
local TRAIL_MASK = { right = DUI.MEDIA .. "mask-trail-r.png", left = DUI.MEDIA .. "mask-trail-l.png" }

-- Every unit button (these and the group headers' buttons) uses this template.
-- PingableUnitFrameTemplate is the game's own (its unit frames use it), so the
-- ping key over a frame pings its unit. The game's ping code reads
-- `self.unit or self:GetAttribute("unit")`, and these buttons keep their unit
-- as `unitToken`, so a ping always follows the secure attribute.
UF.BUTTON_TEMPLATE = "SecureUnitButtonTemplate, PingableUnitFrameTemplate"

function UF.Create(spec)
    local f = CreateFrame("Button", "DaylightUIFrame_" .. spec.unit, UIParent, UF.BUTTON_TEMPLATE)
    f:SetAttribute("unit", spec.unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    -- Clique (and anything else that click-casts) finds its targets here. Only
    -- write into its existing table, never create it: a global by that name
    -- would taint the game's frames that read it.
    if type(ClickCastFrames) == "table" then ClickCastFrames[f] = true end
    -- Set before its parts are made (each takes the frame's level plus its
    -- own), so a frame whose portrait can reach over another (spec.level)
    -- draws fully above it, never the other's bar over the ring.
    if spec.level then f:SetFrameLevel(spec.level) end
    return UF.Build(f, spec)
end

-- Sets up a button as a unit frame: shell, bars, text and whatever extras its
-- spec asks for. The button may be one from UF.Create or one a secure group
-- header made (raid frames), whose unit changes with the roster. Hovering a
-- frame shows its unit's tooltip, placed the way the game places world
-- tooltips (or at the cursor, when the tooltip options say so).
function UF.OnEnter(self)
    local unit = self.unitToken
    if type(unit) ~= "string" or not UnitExists(unit) then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    GameTooltip:SetUnit(unit)
    if ns.Happiness then ns.Happiness.AddTip(self) end
    GameTooltip:Show()
end

function UF.OnLeave()
    GameTooltip:Hide()
end

-- Scripts on a secure button can't be set in combat (a raid tile can be created
-- then), so this waits for combat to end if needed.
function UF.HookTooltip(f)
    DUI.AfterCombat(function()
        if f.tooltipHooked then return end
        f.tooltipHooked = true
        f:HookScript("OnEnter", UF.OnEnter)
        f:HookScript("OnLeave", UF.OnLeave)
    end)
end

function UF.Build(f, spec)
    f.unitToken, f.spec = f.unitToken or spec.unit, spec
    UF.HookTooltip(f)
    -- Its own copy of the spec's shell options, since UF.ApplyShell and the
    -- aggro colors write into them and raid tiles share one spec.
    local opts
    if spec.shell then
        opts = {}
        for key, v in pairs(spec.shell) do opts[key] = v end
    end
    Style.Shell(f, opts)
    local media = UF.MediaOf(spec)
    f.media = media
    f.health = Style.Bar(f, nil, media.bars.health)
    if spec.power then
        f.power = Style.Bar(f, nil, media.bars.power)
        f.separator = Style.Separator(f)
        -- Every power bar, however its frame is wired (unit events, a secure
        -- header's attributes...), see UF.PollPower. Your own polls every
        -- frame, everyone else's share one driver (UF.WatchPower).
        if spec.unit == "player" then
            f:SetScript("OnUpdate", function(self, dt) UF.PollPower(self, dt) end)
        else
            UF.WatchPower(f)
        end
    end
    if spec.slant then
        -- Register the shell first, then everything inside the border.
        Style.Slant(f, nil, 0)
        local inner = { f.health:GetStatusBarTexture(), Style.BarBack(f.health) }
        if f.power then
            inner[#inner + 1] = f.power:GetStatusBarTexture()
            inner[#inner + 1] = Style.BarBack(f.power)
            inner[#inner + 1] = f.separator
        end
        for _, tex in ipairs(inner) do Style.Clip(f, tex, "inner") end
        -- The target mirrors the player: its bars fill from the inner end
        -- (set again in Layout, which can reverse it).
        f.growLeft = spec.slant == "left"
        f.health:SetReverseFill(f.growLeft)
        if f.power then f.power:SetReverseFill(f.growLeft) end
    end
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f.health:GetFrameLevel() + 3)
    f.overlay = overlay
    f.percentText = Style.Text(overlay, 12, "RIGHT", media.fonts.health)
    if f.power then
        -- A small number on the power bar's inner end (off by default).
        f.powerText = Style.Text(overlay, 10, spec.slant == "left" and "LEFT" or "RIGHT", media.fonts.power)
        f.powerText:Hide()
    end
    if spec.unit == "player" and f.power then
        -- Druid forms hide your mana, so show a thin strip of it along the
        -- bottom of the power bar while they do.
        f.altMana = Style.Bar(f, nil, media.bars.power)
        f.altMana:SetFrameLevel(f.power:GetFrameLevel() + 1)
        if spec.slant then
            Style.Clip(f, f.altMana:GetStatusBarTexture(), "inner")
            Style.Clip(f, Style.BarBack(f.altMana), "inner")
        end
        f.altMana:SetReverseFill(spec.slant == "left")
        f.altMana:Hide()
        UF.CreateCost(f, spec)
    end
    -- Ribbon's power line under the frame, created with the frame (a party
    -- button may be created mid-fight). Hidden until the style needs it.
    if spec.ribbon and f.power then ns.PowerBar.CreateLine(f) end
    if spec.tab then
        -- Frames with a tab only show the name there. The tab lives in a frame
        -- that clips it at the body's top edge, so it can slide up from behind
        -- the body (Arrive.lua).
        f.tabClip = CreateFrame("Frame", nil, f)
        f.tabClip:SetFrameLevel(overlay:GetFrameLevel() + 1)
        f.tab = CreateFrame("Frame", nil, f.tabClip)
        f.tab:SetFrameLevel(overlay:GetFrameLevel() + 1)
        Style.Shell(f.tab, { borderPx = UF.TAB_BORDER })
        if spec.slant then Style.Slant(f.tab, nil, 0) end
        f.nameText = Style.Text(f.tab, 12, "CENTER", media.fonts.name)
    else
        f.nameText = Style.Text(overlay, 13, "CENTER", media.fonts.name)
    end
    if spec.marker then
        -- The raid marker sits in the name tab, before the name.
        f.marker = (f.tab or overlay):CreateTexture(nil, "OVERLAY")
        f.marker:SetTexture(UF.MARKER_SHEET)
        f.marker:SetSize(UF.MARKER_SIZE, UF.MARKER_SIZE)
        f.marker:Hide()
        f.markerNudge = { x = 0, y = 0 }   -- UF.Layout's markerX/Y
    end
    UF.CreatePrediction(f)
    if spec.dots then UF.CreateDots(f) end
    if spec.leaderIcon or spec.cornerIcons then
        f.leaderIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
        f.leaderIcon:SetTexture(DUI.MEDIA .. UF.STATUS.leader.file)
        local c = UF.STATUS.leader.color
        f.leaderIcon:SetVertexColor(c[1], c[2], c[3], 1)
        f.leaderIcon:Hide()
    end
    -- A ready check answer (UF.UpdateReady), for party and raid buttons.
    if spec.group then
        f.readyIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
        f.readyIcon:Hide()
    end
    -- A tile has no portrait to hang the role icon from, so it gets its own
    -- badge in a free corner. A portrait frame's lives in the status set below,
    -- next to the others.
    if spec.role and (not spec.portrait or spec.cornerIcons) then
        f.roleIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
        f.roleIcon:SetTexture(UF.ROLE_ICON_TEXTURE)
        f.roleIcon:Hide()
    end

    if spec.portrait then
        UF.CreatePortrait(f)
        UF.CreateStatus(f)
    end
    if spec.classification and f.tab then
        UF.CreateCrest(f)
    end
    if spec.threatTag then UF.CreateThreatTag(f) end
    return f
end

-- The threat tag: a small tab like the name's, on the frame's inner end.
function UF.CreateThreatTag(f)
    local tag = CreateFrame("Frame", nil, f)
    tag:SetFrameLevel(f.overlay:GetFrameLevel() + 1)
    Style.Shell(tag, { borderPx = UF.TAB_BORDER })
    if f.spec.slant then Style.Slant(tag, nil, 0) end
    local fonts = UF.MediaOf(f.spec).fonts
    tag.text = Style.Text(tag, 10, "CENTER", fonts.threat or fonts.health)
    tag.text:SetPoint("CENTER", tag, "CENTER", 0, 0)
    tag:Hide()
    f.threatTag = tag
end

-- The standalone tag (target.threatTagAt = "free"): a holder on UIParent with
-- its own mover, the tag moved into it. Never anchored to the protected frame.
-- It shows and hides with the frame through its scripts, and fades with it
-- (the frame's fade list, Units.lua).
UF.THREAT_KEY = "unitframes.targetThreat"
function UF.CreateThreatHolder(f)
    local h = CreateFrame("Frame", "DaylightUIThreatTag_target", UIParent)
    h:SetSize(UF.THREAT_TAG_W, UF.TAB_HEIGHT)
    h:Hide()
    f.threatHolder = h
    f:HookScript("OnShow", function()
        if f.threatTag:GetParent() == h then h:Show() end
    end)
    f:HookScript("OnHide", function() h:Hide() end)
    return h
end

-- A portrait of its own (<unit>.portraitAt = "free"): a holder on UIParent with
-- its own mover, the portrait and the icons riding on it moved into it. Built
-- like the threat tag's: never anchored to the frame, shown and hidden with it,
-- faded with it (the frame's fade list, Units.lua).
UF.PORTRAIT_FREE = { player = "unitframes.playerPortrait", target = "unitframes.targetPortrait",
                     focus = "unitframes.focusPortrait" }
function UF.CreatePortraitHolder(f)
    local unit = f.spec.unit
    local h = CreateFrame("Frame", "DaylightUIPortrait_" .. unit, UIParent)
    h:SetSize(40, 40)
    h.key = UF.PORTRAIT_FREE[unit]
    h:Hide()
    f.portraitHolder = h
    f:HookScript("OnShow", function() if h.want then h:Show() end end)
    f:HookScript("OnHide", function() h:Hide() end)
    return h
end

-- Puts the portrait, and the status icons that ride on it, on the frame or in
-- its holder. Pieces inside the secure frame can't be anchored to a frame of
-- the addon's own, so the icons go along with the ring.
function UF.HomePortrait(f)
    local p = f.portrait
    local home = f.portraitFree and f.portraitHolder or f
    if p:GetParent() ~= home then p:SetParent(home) end
    p:SetFrameLevel(home:GetFrameLevel() + (home == f and 6 or 1))
    local st = f.status
    if st then
        -- The player can keep the icons on the frame instead (portraitIconsStay).
        if f.iconsStay then home = f end
        if st:GetParent() ~= home then
            st:SetParent(home)
            st:ClearAllPoints()
            st:SetAllPoints(home)
        end
        st:SetFrameLevel(p:GetFrameLevel() + 6)
    end
end

function UF.LayoutThreatTag(f, cfg, side)
    local tag = f.threatTag
    f.showThreatTag = cfg.threatTag ~= false and f.showThreat
    f.threatTagColor = cfg.threatTagColor or "threat"
    local holder = f.threatHolder
    local free = holder and cfg.threatTagAt == "free" or false
    if holder then DUI.Movers.Suspend(UF.THREAT_KEY, not (free and f.showThreatTag)) end
    local inner = f.spec.slant == "left" and "LEFT" or "RIGHT"
    local h = tonumber(cfg.threatTagHeight) or 0
    if h <= 0 then h = tonumber(cfg.tabHeight) or UF.TAB_HEIGHT end
    if cfg.threatTagSlant == false then side = nil end
    local cut = side and Pixel.Snap(f, h * UF.SLANT) or 0
    local w = Pixel.Snap(f, (tonumber(cfg.threatTagWidth) or UF.THREAT_TAG_W) + cut)
    local nx, ny = tonumber(cfg.threatTagX) or 0, tonumber(cfg.threatTagY) or 0
    tag:ClearAllPoints()
    if free then
        if tag:GetParent() ~= holder then tag:SetParent(holder) end
        holder:SetScale(DUI.Movers.Scale(UF.THREAT_KEY))
        holder:SetSize(w, h)
        tag:SetFrameLevel(holder:GetFrameLevel() + 1)
        tag:SetPoint("CENTER", holder, "CENTER", 0, 0)
        holder:SetShown(f:IsShown())
    else
        if tag:GetParent() ~= f then tag:SetParent(f) end
        if holder then holder:Hide() end
        tag:SetFrameLevel(f.overlay:GetFrameLevel() + 1)
        if f.ribbon then
            -- Ribbon: off the bar's inner end, level with it (the row's inner
            -- end holds the health number).
            local away = inner == "LEFT" and "RIGHT" or "LEFT"
            tag:SetPoint(away, f, inner, (inner == "LEFT" and -1 or 1) * 3 + nx, ny)
        elseif f.tabAt == "inner" and f.tab and f.tab:IsShown() then
            -- The name tab took the inner corner, so go just outward of it.
            local outer = inner == "LEFT" and "RIGHT" or "LEFT"
            tag:SetPoint("BOTTOM" .. inner, f.tab, "BOTTOM" .. outer, (inner == "LEFT" and 1 or -1) * 2 + nx, ny)
        else
            -- Clear of the frame's angled end, outlines overlapping like the name tab.
            tag:SetPoint("BOTTOM" .. inner, f, "TOP" .. inner, (inner == "LEFT" and 1 or -1) * (f.cut or 0) + nx, -Pixel.Px(f, 1) + ny)
        end
    end
    tag:SetSize(w, h)
    if f.spec.slant then Style.Slant(tag, side, cut) end
    local shell = Style.GetShell(tag)
    Style.LayoutShell(shell)
    shell:SetShown(cfg.threatTagBox ~= false)
    local size = tonumber(cfg.threatTagSize) or 0
    if size <= 0 then size = math.max(8, math.floor(h * 0.62 + 0.5)) end
    Style.SetTextSize(tag.text, size)
    tag.text:ClearAllPoints()
    -- Centered in the part that's clear of its angled end.
    tag.text:SetPoint("CENTER", tag, "CENTER", (inner == "LEFT" and 1 or -1) * cut / 2, 0)
    if not f.showThreatTag then tag:Hide() end
end

-- The tag's number color (target.threatTagColor): "threat" is orange close to
-- pulling and red once it's on you, or "white", or "accent". level: plain or nil.
local function paintTag(f, level)
    local fs, mode = f.threatTag.text, f.threatTagColor
    if mode == "accent" then return Style.InkText(fs, "pop") end
    local c = mode ~= "white" and level and UF.THREAT_COLORS[level]
    if c then fs:SetTextColor(c[1], c[2], c[3]) else Style.InkText(fs, "VALUE") end
end

-- Your threat on the unit as a percent of the pull: a plain number, a secret
-- one (a boss, written whole in white), or nil to hide the tag.
function UF.ShowThreatTag(f, pct, level)
    local tag = f.threatTag
    if not tag then return end
    if not f.showThreatTag or type(pct) == "nil" then
        tag:Hide()
        return
    end
    if isSecret(pct) then
        tag.text:SetFormattedText("%.0f%%", pct)
        paintTag(f, nil)
    else
        tag.text:SetFormattedText("%d%%", math.floor(pct + 0.5))
        paintTag(f, level)
    end
    tag:Show()
end

-- A tile name's alignment setting to its justify value.
UF.NAME_ALIGN = { left = "LEFT", center = "CENTER", right = "RIGHT" }

-- Places a text where the layout wants it plus the player's own nudge (nx, ny).
-- Never read it back with GetPoint: a text showing a secret (health in combat
-- or a battleground) has secret anchoring, and its offsets come back secret.
function UF.PlaceText(fs, p, rel, rp, x, y, nx, ny)
    fs:SetPoint(p, rel, rp, x + (tonumber(nx) or 0), y + (tonumber(ny) or 0))
end

-- The nine spots a tile icon can sit in (role, marker, leader, dispel). sx/sy
-- point inward from that spot, so one padding insets any of them.
UF.ICON_SPOTS = {
    topleft = { "TOPLEFT", 1, -1 }, top = { "TOP", 0, -1 }, topright = { "TOPRIGHT", -1, -1 },
    left = { "LEFT", 1, 0 }, center = { "CENTER", 0, 0 }, right = { "RIGHT", -1, 0 },
    bottomleft = { "BOTTOMLEFT", 1, 1 }, bottom = { "BOTTOM", 0, 1 }, bottomright = { "BOTTOMRIGHT", -1, 1 },
}

-- Puts a texture, text or frame at a named spot of rel, padX/padY in from it,
-- nudged by nx/ny.
function UF.PlaceIcon(obj, rel, spot, padX, padY, nx, ny)
    local s = UF.ICON_SPOTS[spot] or UF.ICON_SPOTS.center
    obj:ClearAllPoints()
    obj:SetPoint(s[1], rel, s[1], s[2] * (padX or 0) + (tonumber(nx) or 0), s[3] * (padY or 0) + (tonumber(ny) or 0))
end

-- A frame's own icon (marker, crown, role, dispel) at a spot: one of the nine
-- on rel, padX/padY in from it (UF.PlaceIcon), or one of the eight around the
-- frame f itself (Spots: above, below, beside, off a corner), nudged by nx/ny.
function UF.PlaceSpot(obj, f, rel, spot, padX, padY, nx, ny)
    if UF.ICON_SPOTS[spot] or not ns.Spots.Valid(spot) then
        return UF.PlaceIcon(obj, rel, spot, padX, padY, nx, ny)
    end
    local L = ns.Spots.Layout(spot, "center", { w = f:GetWidth() }, { x = nx, y = ny })
    obj:ClearAllPoints()
    obj:SetPoint(L.point, f, L.relPoint, L.x, L.y)
end

-- How far in from its spot a corner icon sits: 1px, plus the angled end's width
-- on that side so it never sits in the cut (f.cut, from UF.Layout).
function UF.CornerPad(f, spot)
    local s = UF.ICON_SPOTS[spot] or UF.ICON_SPOTS.center
    local cut = f.cut or 0
    if cut > 0 and ((f.spec.slant == "right" and s[2] < 0) or (f.spec.slant == "left" and s[2] > 0)) then
        return 1 + cut
    end
    return 1
end

-- A tile's name: inside the health bar, clear of the angled end. A tall tile
-- (UF.TALL_TILE or more) puts it along the top and the health text along the
-- bottom so the two never meet. SetTileName stores what PlaceTileName needs (a
-- party button places it later, from UF.SizeTab).
function UF.SetTileName(f, cfg, text)
    local cut = (f.spec.slant and cfg.slant ~= false) and Pixel.Snap(f, cfg.height * UF.SLANT) or 0
    local pos = ((f.spec.group or ns.Spots.Valid(cfg.namePos)) and cfg.namePos) or "bar"
    f.tileName = {
        cutPad = cut,
        showPercent = cfg.showPercent == true,
        x = tonumber(cfg.nameX) or 0, y = tonumber(cfg.nameY) or 0,
        justify = (f.spec.group and UF.NAME_ALIGN[cfg.nameAlign]) or "CENTER",
        -- "bar": across the bar (above). Otherwise a Spots spot (namePos). A
        -- big frame (player, target...) only comes here for a spot.
        pos = pos,
        box = { w = cfg.width, h = cfg.height, padX = 3, padY = 2,
                cutL = f.spec.slant == "left" and cut or 0, cutR = f.spec.slant == "right" and cut or 0 },
        -- A group tile's name outside the tile sits on a name tab (nameTag).
        -- Ribbon has its own row above the frame instead.
        tag = (f.spec.group and not f.ribbon and cfg.nameTag ~= false and UF.TAG_SPOTS[pos]) == true,
        cut = cut > 0 and f.spec.slant or nil,
    }
    if f.tileName.tag then
        local size = text and tonumber(text.name) or 12
        f.tileName.tagH = Pixel.Snap(f, math.max(tonumber(cfg.tabHeight) or UF.TAB_HEIGHT, size + 6))
        if not f.nameTag then
            UF.CreateNameTag(f)
            UF.ApplyShell(f, cfg)   -- give the new tab this frame's tab border
        end
    end
    f.tallTile = (f.spec.group and cfg.height >= UF.TALL_TILE) == true
    -- A frame that isn't a compact tile keeps its health text at the inner end
    -- (a tall one without the big number puts it along the bottom), so the name
    -- stays in the outer half, as UF.PlaceBarName does.
    f.tileName.outerHalf = not f.spec.compact and (cfg.bigNumber == true or not f.tallTile)
end

-- A tile name at a spot (namePos), with a single anchor so it may run past the
-- tile. Outside left or right, the room beside the tile is up to the player.
local NAME_GROW = { topleft = "right", left = "right", bottomleft = "right", topright = "left", right = "left",
                    bottomright = "left", top = "center", center = "center", bottom = "center",
                    above = "center", below = "center", outtopleft = "left", outbottomleft = "left",
                    outtopright = "right", outbottomright = "right" }
local NAME_JUSTIFY = { right = "LEFT", left = "RIGHT", center = "CENTER" }

-- Outside spots, where a tile's name gets the name tab behind it.
UF.TAG_SPOTS = { above = true, below = true, outleft = true, outright = true, outtopleft = true,
                 outtopright = true, outbottomleft = true, outbottomright = true }

-- The name tab of a group tile whose name sits outside it: the same dark tab
-- the player and target wear, made the first time it's wanted.
function UF.CreateNameTag(f)
    local tag = CreateFrame("Frame", nil, f.overlay)
    tag:SetFrameLevel(f.overlay:GetFrameLevel() + 1)
    Style.Shell(tag, { borderPx = UF.TAB_BORDER })
    Style.Slant(tag, nil, 0)
    tag:Hide()
    f.nameTag = tag
    return tag
end

-- Shows or hides the tile's name tab, fading either way.
function UF.ShowNameTag(f, on)
    local tag = f.nameTag
    if not tag or f.nameTagOn == on then return end
    f.nameTagOn = on
    DUI.Motion.AlphaTo(tag, on and 1 or 0, DUI.Motion.NORMAL, true)
end

-- The tab fits the name, up to the tile's width. A secret name can't be
-- measured, so it takes the tile's width.
function UF.SizeNameTag(f, name)
    local tag, t = f.nameTag, f.tileName
    if not (tag and t and t.tag) then return end
    local sl = Style.GetSlant(tag)
    local extra = 2 * UF.TAB_PAD + ((sl and sl.side) and sl.cut or 0)
    local fw = f:GetWidth()
    if not isSecret(name) and name == nil then name = f.nameText:GetText() end
    local w = fw
    if not isSecret(name) and name ~= nil then
        f.nameText:SetWidth(0)
        local ok, sw = pcall(f.nameText.GetStringWidth, f.nameText)
        -- In an instance the width can be secret even when the text isn't.
        if ok and type(sw) == "number" and not isSecret(sw) then w = math.min(sw + extra, fw) end
    end
    w = Pixel.Snap(f, math.max(30, w))
    tag:SetWidth(w)
    -- A name too long for the tab is cut short with "...".
    f.nameText:SetWidth(math.max(1, w - extra + 2))
end

-- The tab sits where the name would, flush on the tile's edge above or below
-- it (outlines overlapping, as the player's tab), and the name in its middle.
local function placeNameTag(f, t)
    local tag, fs = f.nameTag, f.nameText
    local h = t.tagH or UF.TAB_HEIGHT
    tag:SetHeight(h)
    tag:ClearAllPoints()
    local px = Pixel.Px(f, 1)
    if t.pos == "above" or t.pos == "below" then
        local up = t.pos == "above"
        tag:SetPoint(up and "BOTTOM" or "TOP", f, up and "TOP" or "BOTTOM", t.x, (up and -px or px) + t.y)
    elseif t.pos == "outleft" or t.pos == "outright" then
        local left = t.pos == "outleft"
        tag:SetPoint(left and "RIGHT" or "LEFT", f, left and "LEFT" or "RIGHT", (left and -2 or 2) + t.x, t.y)
    else
        local L = ns.Spots.Layout(t.pos, NAME_GROW[t.pos] or "center", t.box, { x = t.x, y = t.y })
        tag:SetPoint(L.point, f.health or f, L.relPoint, L.x, L.y)
    end
    -- Angled like the tile, at the same end.
    Style.Slant(tag, t.cut, t.cut and Pixel.Snap(f, h * UF.SLANT) or 0)
    Style.LayoutShell(Style.GetShell(tag))
    fs:SetPoint("CENTER", tag, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    UF.SizeNameTag(f)
end

local function placeNameAtSpot(f, t)
    local fs = f.nameText
    fs:ClearAllPoints()
    fs:SetWidth(0)
    if t.tag and f.nameTag then return placeNameTag(f, t) end
    if t.pos == "outleft" or t.pos == "outright" then
        local left = t.pos == "outleft"
        fs:SetPoint(left and "RIGHT" or "LEFT", f, left and "LEFT" or "RIGHT", (left and -4 or 4) + t.x, t.y)
        fs:SetJustifyH(left and "RIGHT" or "LEFT")
        return
    end
    local grow = NAME_GROW[t.pos] or "center"
    local L = ns.Spots.Layout(t.pos, grow, t.box, { x = t.x, y = t.y })
    fs:SetPoint(L.point, f.health or f, L.relPoint, L.x, L.y)
    fs:SetJustifyH(NAME_JUSTIFY[grow])
end

function UF.PlaceTileName(f)
    local t = f.tileName
    -- The name lives in its tab while it has one, else back on the tile.
    if f.nameTag then f.nameText:SetParent(t.tag and f.nameTag or f.overlay) end
    if t.pos ~= "bar" and ns.Spots.Valid(t.pos) then return placeNameAtSpot(f, t) end
    local leftPad = 3 + (f.spec.slant == "left" and t.cutPad or 0) + (f.moodSide == "left" and f.moodPad or 0)
    local rightPad = 3 + (f.spec.slant == "right" and t.cutPad or 0) + (f.moodSide == "right" and f.moodPad or 0)
    -- Target of target and pet: clear of the health text, when it's shown.
    if not f.spec.group and t.showPercent then rightPad = rightPad + 26 end
    if t.outerHalf then
        local half = f:GetWidth() * 0.5
        if f.spec.slant == "left" then leftPad = math.max(leftPad, half)
        else rightPad = math.max(rightPad, half) end
    end
    local top = f.tallTile and -3 or 0
    local a, b = f.tallTile and "TOPLEFT" or "LEFT", f.tallTile and "TOPRIGHT" or "RIGHT"
    f.nameText:ClearAllPoints()
    f.nameText:SetPoint(a, f.health, a, leftPad + t.x, top + t.y)
    f.nameText:SetPoint(b, f.health, b, -rightPad + t.x, top + t.y)
    f.nameText:SetJustifyH(t.justify)
end

-- The frame's own border, corners and shadow (<frame>.shell, own = true), or
-- General > Appearance's (the spec's own for raid tiles). Its name and threat
-- tabs and Ribbon's power line keep half the frame's border, as they do with
-- General's. Laid out by the caller (UF.Layout lays out every shell it touches).
-- Also applies the Colors page's empty part opacity (colors.backAlpha) to the
-- frame's own dark inside. Below Style.BAR_BACK_ALPHA (the default) both thin
-- together, so the world shows through the missing health and power, like the
-- classic UI. The bar backgrounds take it as their own alpha, under whatever
-- color they're painted (UF.SetBarColor, gradients, Dark mode).
function UF.BackAlpha()
    local a = UF.colors and tonumber(UF.colors.backAlpha)
    if not a then return Style.BAR_BACK_ALPHA end
    return math.max(0, math.min(1, a))
end

function UF.ApplyBack(f, s)
    local a = UF.BackAlpha()
    local k = math.min(1, a / Style.BAR_BACK_ALPHA)
    for _, bar in ipairs({ f.health or false, f.power or false }) do
        local back = bar and Style.BarBack(bar)
        if back then back:SetAlpha(k) end
    end
    if s then
        local clear = a < Style.BAR_BACK_ALPHA and math.min(Style.BACKGROUND_ALPHA, a) or nil
        if s.opts.bgAlpha ~= clear then
            s.opts.bgAlpha = clear
            if s.bg then Style.PaintBack(s) end
        end
    end
end

-- A piece's own border, corners and shadow (<piece>.shell with own on: the
-- player's cast bar, the swing timer), else nil for General > Appearance's.
function UF.OwnShell(cfg)
    local s = type(cfg) == "table" and cfg.shell
    if type(s) == "table" and s.own == true then return s end
end

-- Writes a piece's own (or General's, for nil) border, corners and shadow into
-- shell s. The next Slant lays it out. Returns its border in px.
function UF.WriteShell(s, own)
    if s then
        s.opts.borderPx = own and tonumber(own.borderPx) or nil
        s.opts.cornerPx = own and tonumber(own.cornerPx) or nil
        s.opts.shadowPx = own and tonumber(own.shadowPx) or nil
    end
    return own and tonumber(own.borderPx) or DUI.DB.General().borderPx
end

function UF.ApplyShell(f, cfg)
    local s = Style.GetShell(f)
    if not s then return end
    UF.ApplyBack(f, s)
    local own = type(cfg.shell) == "table" and cfg.shell.own == true and cfg.shell or nil
    local base = f.spec.shell or {}   -- none for the personal display's body
    s.opts.borderPx = own and tonumber(own.borderPx) or base.borderPx
    s.opts.cornerPx = own and tonumber(own.cornerPx) or base.cornerPx
    s.opts.shadowPx = own and tonumber(own.shadowPx) or base.shadowPx
    local tabPx = UF.TAB_BORDER
    if own then
        local px = tonumber(own.borderPx) or 0
        tabPx = px > 0 and UF.TAB_BORDER(px) or 0
    end
    -- The name tab's own look (<frame>.tab, own = true), also used by the
    -- threat tag so the two still match. Ribbon's line keeps the frame's.
    local look = UF.TabLook(cfg)
    for _, tab in pairs({ f.tab or false, f.threatTag or false, f.line or false, f.nameTag or false }) do
        local ts = tab and Style.GetShell(tab)
        if ts then
            if look and tab ~= f.line then
                ts.opts.borderPx = tonumber(look.borderPx) or 0
                ts.opts.cornerPx = tonumber(look.cornerPx)
                ts.opts.shadowPx = tonumber(look.shadowPx)
            else
                ts.opts.borderPx = tabPx
                ts.opts.cornerPx = own and tonumber(own.cornerPx) or nil
                ts.opts.shadowPx = nil
            end
        end
    end
end

-- The name tab's own settings when it has its own look, else nil.
function UF.TabLook(cfg)
    local t = type(cfg) == "table" and cfg.tab
    if type(t) == "table" and t.own == true then return t end
end

-- Where the name tab sits and how wide it is (Daylight; Ribbon's row keeps its
-- place). Stored on the frame for UF.PlaceTab and UF.SizeTab.
UF.TAB_AT = { outer = true, middle = true, inner = true }
UF.TAB_WIDTHS = { fit = true, full = true, fixed = true }
UF.TAB_ALIGNS = { left = "LEFT", center = "CENTER", right = "RIGHT" }
function UF.ReadTab(f, cfg)
    local t = (not f.ribbon and type(cfg.tab) == "table") and cfg.tab or {}
    f.tabWidth = UF.TAB_WIDTHS[t.width] and t.width or "fit"
    f.tabWidthPx = tonumber(t.widthPx) or 90
    -- A full-width tab runs from past the portrait, so always at the outer end.
    f.tabAt = (f.tabWidth ~= "full" and UF.TAB_AT[t.at]) and t.at or "outer"
    f.tabX, f.tabY = tonumber(t.x) or 0, tonumber(t.y) or 0
    f.tabAlign = UF.TAB_ALIGNS[t.align] and t.align or "center"
    f.tabSlant = (t.slant == "on" or t.slant == "off") and t.slant or "frame"
end

-- The frame's height: its own, but never so low that the border eats the bars
-- inside. The border is whole screen pixels (8 by default), so on a small
-- screen it's more UI units. A 20-high pet frame at 1080p only kept its power
-- bar with 0 height of health. In that case the frame grows just enough for
-- the border, the power bar inside, the line between and UF.MIN_HEALTH of
-- health (like the breath bar, the border goes around, not into it).
UF.MIN_HEALTH = 6
function UF.OuterHeight(f, cfg, T)
    local h = 2 * Pixel.Snap(f, cfg.height / 2)
    local inner = Pixel.Snap(f, UF.MIN_HEALTH)
    if f.power and UF.ShowsPower(cfg) and (ns.PowerBar.Pick(f, cfg) or "inside") == "inside" then
        inner = inner + Pixel.Snap(f, cfg.powerHeight) + Pixel.Px(f, Style.SEPARATOR_PX)
    end
    return math.max(h, inner + 2 * T)
end

-- Protected, so only call through DUI.AfterCombat.
-- keepSize: leave the button's own size and scale alone (the raid header sizes
-- its buttons, and may create them during combat).
function UF.Layout(f, cfg, text, keepSize)
    local g = DUI.DB.General()
    if not keepSize then
        f:SetScale(f.moverKey and DUI.Movers.Scale(f.moverKey) or g.scale)
        f:SetSize(2 * Pixel.Snap(f, cfg.width / 2), 2 * Pixel.Snap(f, cfg.height / 2))
    end
    UF.ApplyShell(f, cfg)
    local T = Pixel.Px(f, Style.BorderPx(f))
    if not keepSize then f:SetHeight(UF.OuterHeight(f, cfg, T)) end
    -- Ribbon (UF.StyleOf): the row above and the line below. Their room
    -- (f.hitTop, f.foot) is read by everything placed above or below the frame.
    f.ribbon = UF.IsRibbon(f, cfg)
    f.foot = 0
    local rowOn = f.ribbon and type(f.tab) == "table"
        and ((cfg.showName ~= false and cfg.nameOnBar ~= true) or cfg.showPercent == true)
    f.hitTop = rowOn and (tonumber(cfg.tabHeight) or UF.TAB_HEIGHT) or 0
    -- Work out the angled end first, since corner icons keep clear of it.
    local side = cfg.slant ~= false and f.spec.slant or nil
    local cut = side and Pixel.Snap(f, cfg.height * UF.SLANT) or 0
    f.cut = cut
    -- Party buttons with neither a portrait nor a name tab showing carry their
    -- icons in the corners, like tiles.
    local tabOn = f.tab and ((cfg.showName ~= false and cfg.nameOnBar ~= true) or f.hitTop > 0) or false
    f.cornerMode = f.spec.cornerIcons == true and UF.PortraitMode(f, cfg) == "none" and not tabOn

    f.health:ClearAllPoints()
    -- A happiness stripe inside the pet frame takes a strip off one end
    -- (Happiness.Prepare). The bars stop short of it on a straight edge.
    local band = ns.Happiness and ns.Happiness.Prepare(f, cfg) or nil
    local insetL, insetR = T, T
    if band then
        local reserve = band.w + band.gap + (band.cut or 0)
        if band.side == "left" then insetL = T + reserve else insetR = T + reserve end
    end
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", insetL, -T)
    -- Tiles can optionally fill health bottom to top instead of across.
    f.health:SetOrientation(cfg.fillVertical == true and "VERTICAL" or "HORIZONTAL")
    -- The player's power bar may stand on its own, and in Ribbon every power
    -- bar is a line under the frame (PowerBar.lua). Then the frame is all
    -- health and f.power is that bar (laid out further down).
    local where = f.power and ns.PowerBar.Pick(f, cfg) or "inside"
    local freePower, hung = where == "free", where == "line"
    local showPower = f.power and UF.ShowsPower(cfg)
        and (where == "inside" or (freePower and type(f.freePower) == "table") or (hung and type(f.line) == "table"))
    if f.power then
        local was = f.power:IsShown()
        f.power:SetShown(showPower)
        f.separator:SetShown(showPower and where == "inside")
        if f.unitToken ~= "player" then UF.WatchPower(f, showPower and true or false) end
        -- Power events skip a hidden bar, which catches up when it comes back.
        if showPower and not was and not f.test and type(f.unitToken) == "string" and UnitExists(f.unitToken) then
            UF.UpdatePower(f, true)
        end
    end
    if showPower and where == "inside" then
        f.power:ClearAllPoints()
        f.power:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", insetL, T)
        f.power:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -insetR, T)
        f.power:SetHeight(Pixel.Snap(f, cfg.powerHeight))
        f.separator:ClearAllPoints()
        f.separator:SetPoint("BOTTOMLEFT", f.power, "TOPLEFT", 0, 0)
        f.separator:SetPoint("BOTTOMRIGHT", f.power, "TOPRIGHT", 0, 0)
        f.separator:SetHeight(Pixel.Px(f, Style.SEPARATOR_PX))
        f.health:SetPoint("BOTTOMRIGHT", f.separator, "TOPRIGHT", 0, 0)
    else
        f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -insetR, T)
    end

    -- Where the marker, crown and role icon sit (UF.IconSpot). nil means home,
    -- with the name tab or portrait.
    f.markerSpot = f.marker and UF.IconSpot(f, cfg, "markerPos", f.tab and not f.cornerMode) or nil
    f.leaderSpot = f.leaderIcon and UF.IconSpot(f, cfg, "leaderPos", f.status and not f.cornerMode) or nil
    f.roleSpot = f.roleIcon and UF.IconSpot(f, cfg, "rolePos",
        f.status and f.status.icons.role and not f.cornerMode) or nil
    -- At home, the nudges move them from there.
    f.markerNudge = { x = tonumber(cfg.markerX) or 0, y = tonumber(cfg.markerY) or 0 }
    f.leaderNudge = { x = tonumber(cfg.leaderX) or 0, y = tonumber(cfg.leaderY) or 0 }
    f.roleNudge = { x = tonumber(cfg.roleX) or 0, y = tonumber(cfg.roleY) or 0 }
    f.leaderPicked = UF.PickedSize(cfg.leaderPx, UF.CORNER_CROWN)
    f.rolePicked = UF.PickedSize(cfg.roleSize, UF.CORNER_ICON)
    f.showMarker, f.showClassification = cfg.showMarker, cfg.showClassification
    if f.markerSpot then
        -- At a spot (tiles, a party button in corner mode, or moved): small.
        f.markerSize = cfg.markerSize or UF.CORNER_ICON
        local spot = f.markerSpot
        UF.PlaceSpot(f.marker, f, f.health, spot, UF.CornerPad(f, spot), 1, cfg.markerX, cfg.markerY)
    elseif f.marker then
        -- In a name tab: the usual size unless the player picked another.
        f.markerSize = UF.PickedSize(cfg.markerSize, UF.MARKER_SIZE)
    end
    if f.marker then
        local px = f.markerSize or UF.MARKER_SIZE
        f.marker:SetSize(px, px)
    end
    f.hideLeaderFight = cfg.leaderHideInCombat == true
    if f.leaderSpot then
        local size = cfg.leaderPx or UF.CORNER_CROWN
        f.leaderIcon:SetSize(size, size)
        local pos = f.leaderSpot
        if pos == "topleft" then
            -- The crown's own spot: on the corner, slightly above the frame.
            UF.PlaceIcon(f.leaderIcon, f, pos, T - 0.5, -4.5, cfg.leaderX, cfg.leaderY)
        else
            UF.PlaceSpot(f.leaderIcon, f, f.health, pos, UF.CornerPad(f, pos), 1, cfg.leaderX, cfg.leaderY)
        end
    end
    if f.leaderIcon then f.showLeader = cfg.showLeader ~= false end
    if f.readyIcon then
        local size = cfg.readySize or UF.READY_SIZE
        f.readyIcon:SetSize(size, size)
        local pos = cfg.readyPos or "right"
        UF.PlaceSpot(f.readyIcon, f, f.health, pos, UF.CornerPad(f, pos), 0, cfg.readyX, cfg.readyY)
        f.showReady = cfg.showReady ~= false
    end
    f.showRole = cfg.showRole ~= false
    f.roleHideDamage, f.roleHideFight = cfg.roleHideDamage == true, cfg.roleHideInCombat == true
    if f.roleSpot then
        -- A tile's own corner, clear of the marker, leader crown and dispel
        -- icon (top-left, top-right).
        local size = cfg.roleSize or UF.CORNER_ICON
        f.roleIcon:SetSize(size, size)
        local spot = f.roleSpot
        UF.PlaceSpot(f.roleIcon, f, f.health, spot, UF.CornerPad(f, spot), 1, cfg.roleX, cfg.roleY)
    end
    local compact = f.spec.compact
    Style.SetTextSize(f.nameText, text.name)
    Style.SetTextSize(f.percentText, text.percent)

    f.tallTile, f.tileName = false, nil
    -- A party button with its name on the bar and no portrait is named like a
    -- tile, and UF.SizeTab places it once the tab block below has moved it.
    -- With a portrait it keeps the bar name (UF.PlaceBarName). Any frame with
    -- its name on the bar at a spot (namePos) is named the same way, while at
    -- "bar" a frame with a portrait keeps UF.PlaceBarName. A small frame (the
    -- pet) with its name on the bar is named as before, regardless of its tab.
    if f.tab and cfg.nameOnBar == true
        and ((f.spec.group and UF.PortraitMode(f, cfg) == "none") or f.spec.compact or ns.Spots.Valid(cfg.namePos)) then
        UF.SetTileName(f, cfg, text)
    end
    f.barNameX, f.barNameY = tonumber(cfg.nameX) or 0, tonumber(cfg.nameY) or 0
    f.nameText:ClearAllPoints()
    if f.tab then
        f.nameText:SetPoint("CENTER", f.tab, "CENTER", 0, 0)  -- refined by UF.SizeTab
    elseif compact then
        UF.SetTileName(f, cfg, text)
        UF.PlaceTileName(f)
    else
        local side = cfg.showPercent and 30 or 4
        f.nameText:SetPoint("BOTTOMLEFT", f.health, "BOTTOMLEFT", side, 2)
        f.nameText:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", -side, 2)
        f.nameText:SetJustifyH("CENTER")
    end
    f.nameText:SetWordWrap(false)
    f.nameText:SetShown(cfg.showName ~= false)
    UF.ShowNameTag(f, (f.tileName and f.tileName.tag and cfg.showName ~= false) == true)

    -- Which end the bars fill from: the frame's own direction, or reversed.
    f.flipped = cfg.reverseFill == true
    f.growLeft = (f.spec.slant == "left") ~= f.flipped
    f.health:SetReverseFill(f.growLeft)
    if f.power then f.power:SetReverseFill(f.growLeft) end
    if f.altMana then f.altMana:SetReverseFill(f.growLeft) end
    if f.spec.slant then
        Style.Slant(f, side, cut)
        -- Each fill's moving edge follows the frame's angle (straight when
        -- reversed, since the angle belongs to the other end).
        local H = f:GetHeight()
        local ph = (showPower and where == "inside") and (f.power:GetHeight() + Pixel.Px(f, Style.SEPARATOR_PX)) or 0
        f.healthCut = cut * (H - 2 * T - ph) / H
        -- The stripe owns the angled end, so the bars' fill stays square.
        local fillSide = (not f.flipped and cfg.fillVertical ~= true and not (band and band.along)) and side or nil
        Style.AngleFill(f.health, fillSide, f.healthCut)
        if f.power and where == "inside" then Style.AngleFill(f.power, fillSide, cut * f.power:GetHeight() / H) end
    end

    f.predictHeals, f.predictAbsorbs = cfg.predictHeals ~= false, cfg.predictAbsorbs ~= false
    if freePower and f.freePower then
        ns.PowerBar.Layout(f, cfg, text)
    elseif hung then
        ns.PowerBar.LayoutLine(f, cfg, text, side, cut, showPower)
    elseif not freePower then
        UF.LayoutPowerExtras(f, cfg, text, side, cut)
    elseif f.power then
        -- A sample frame: its power stands apart in game, so none here.
        f.powerText:Hide()
        if f.altMana then f.altMana:Hide() end
        if f.cost then f.cost:Hide() end
    end
    f.showThreat = cfg.showThreat ~= false
    UF.LayoutPrediction(f, side)

    f.percentText:ClearAllPoints()
    f.bigNumber = cfg.bigNumber == true
    f.healthFormat = cfg.healthText or "percent"
    f.percentSign = cfg.percentSign == true
    f.hideFullHealth = cfg.hideFullHealth == true
    f.powerFormat = cfg.powerFormat or "value"
    f.powerPercentSign = cfg.powerPercentSign == true
    f.hideFullPower = cfg.hideFullPower == true
    f.nameColorMode, f.nameCustom = cfg.nameColor, cfg.nameCustom
    f.percentColorMode, f.percentCustom = cfg.percentColor, cfg.percentCustom
    f.nameLimitLen = cfg.nameLimitLen
    -- Its own bar colors ("global" or nil uses the Colors page, Colors.lua).
    f.healthMode, f.healthCustom = cfg.colorHealth, cfg.colorHealthCustom
    f.powerMode, f.powerCustom = cfg.colorPower, cfg.colorPowerCustom
    UF.PaintPercent(f)
    -- Either size sits at the frame's inner end, clear of the angled edge.
    local inner = f.spec.slant == "left" and "LEFT" or "RIGHT"
    local dir = inner == "LEFT" and 1 or -1
    local mood = (f.moodPad and f.moodSide == (inner == "LEFT" and "left" or "right")) and f.moodPad or 0
    local nx, ny = cfg.healthTextX, cfg.healthTextY
    -- Ribbon: on the row above the bar at its inner end (bigger with the large
    -- number), sliding in with the row.
    f.percentText:SetParent((f.ribbon and f.tab) or f.overlay)
    if f.ribbon and f.tab then
        Style.SetTextSize(f.percentText, f.bigNumber and text.big or text.percent)
        UF.PlaceText(f.percentText, "BOTTOM" .. inner, f.tab, "BOTTOM" .. inner, dir * UF.RIBBON_NUMBER_INSET,
            UF.RIBBON_TEXT_LIFT, nx, ny)
        f.percentText:SetJustifyH(inner)
    elseif f.bigNumber then
        Style.SetTextSize(f.percentText, text.big)
        UF.PlaceText(f.percentText, inner, f.health, inner, (cut + UF.BIG_NUMBER_INSET + mood) * dir, -UF.BIG_NUMBER_DROP, nx, ny)
        f.percentText:SetJustifyH(inner)
    elseif f.tallTile then
        UF.PlaceText(f.percentText, "BOTTOM", f.health, "BOTTOM", 0, 3, nx, ny)
        f.percentText:SetJustifyH("CENTER")
    else
        UF.PlaceText(f.percentText, inner, f.health, inner, (cut + 4 + mood) * dir, 0, nx, ny)
        f.percentText:SetJustifyH(inner)
    end
    f.percentText:SetShown(cfg.showPercent == true)

    UF.LayoutPortrait(f, cfg)
    f.crestOnTab = not (f.portrait and f.portrait:IsShown())
    f.showLevel, f.showLeader, f.showResting = cfg.showLevel ~= false, cfg.showLeader ~= false, cfg.showResting ~= false
    f.showPvP = cfg.showPvP ~= false
    -- "ring" means the portrait's foot (or the frame's corner), else a Spots spot.
    f.levelSpot = ns.Spots.Valid(cfg.levelPos) and cfg.levelPos or nil
    f.levelNudge = { x = tonumber(cfg.levelX) or 0, y = tonumber(cfg.levelY) or 0 }
    f.iconScale = { leader = (cfg.leaderSize or 1), rest = (cfg.restSize or 1), pvp = (cfg.pvpSize or 1) }
    if f.tab then
        f.tabHeight = tonumber(cfg.tabHeight) or UF.TAB_HEIGHT
        f.nameOnBar = cfg.nameOnBar == true
        -- The name (and marker) move between the tab and the bar's overlay.
        local home = (f.nameOnBar or f.cornerMode) and f.overlay or f.tab
        f.nameText:SetParent(home)
        if f.marker then f.marker:SetParent(f.markerSpot and f.overlay or home) end
        -- Ribbon's row is the tab with its shell hidden. It shows while the
        -- name or the health number is on it.
        f.tab:SetShown((cfg.showName ~= false and not f.nameOnBar) or f.hitTop > 0)
        Style.GetShell(f.tab):SetShown(not f.ribbon)
        if f.tabEdge then f.tabEdge:SetShown((f.crestShown and not f.ribbon) or false) end
        -- Everything above the body's top edge, outlines overlapping.
        f.tabClip:ClearAllPoints()
        f.tabClip:SetPoint("TOPLEFT", f, "TOPLEFT", -UF.TAB_CLIP_PAD, UF.TAB_CLIP_PAD)
        f.tabClip:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", UF.TAB_CLIP_PAD, -Pixel.Px(f, 1))
        UF.ReadTab(f, cfg)
        UF.PlaceTab(f)
        f.tab:SetHeight(f.tabHeight)
        -- Its angled end: the frame's, or its own (<frame>.tab.slant).
        local tabSide = side
        if f.tabSlant == "on" then tabSide = f.spec.slant elseif f.tabSlant == "off" then tabSide = nil end
        if f.spec.slant then Style.Slant(f.tab, tabSide, tabSide and Pixel.Snap(f, f.tabHeight * UF.SLANT) or 0) end
        Style.LayoutShell(Style.GetShell(f.tab))
        UF.SizeTab(f)
    end
    if f.threatTag then UF.LayoutThreatTag(f, cfg, side) end
    if f.dotVeil then UF.LayoutDots(f, cfg) end

    if f.status then UF.LayoutStatus(f, cfg) end
    if f.crest then
        -- The badge sits on the name tab's outer corner. With a portrait the
        -- ring shows elite status instead.
        local outerRight = f.spec.slant == "left"
        f.crest:ClearAllPoints()
        f.crest:SetFrameLevel(f.tab:GetFrameLevel() + 4)
        f.crest:SetPoint("CENTER", f.tab, "TOP" .. (outerRight and "RIGHT" or "LEFT"), 0, 0)
        f.crest:SetSize(UF.CREST_SIZE, UF.CREST_SIZE)
    end
    -- Extra texts (Add piece), placed like any piece and written below.
    ns.Texts.Layout(f, cfg)
    Style.LayoutShell(Style.GetShell(f))
    -- The style changed since the last layout, so the frame arrives in its new
    -- shape (ns.Refresh, Arrive.lua).
    f.restyled = type(f.styleSeen) == "boolean" and f.styleSeen ~= f.ribbon
    f.styleSeen = f.ribbon
    UF.Painted(f)
end

-- The name tab on the frame: at its outer end clear of any portrait, in the
-- middle, or at the inner end clear of the angled end (UF.ReadTab), nudged.
-- drop is px lower (it slides up as the frame arrives).
UF.TAB_CLIP_PAD = 300
function UF.PlaceTab(f, drop)
    local outer = f.spec.slant == "left" and "RIGHT" or "LEFT"
    local inner = outer == "LEFT" and "RIGHT" or "LEFT"
    local inward = outer == "LEFT" and 1 or -1
    local x, y = f.tabX or 0, (f.tabY or 0) - Pixel.Px(f, 1) - (drop or 0)
    f.tab:ClearAllPoints()
    if f.tabAt == "middle" then
        f.tab:SetPoint("BOTTOM", f, "TOP", x, y)
    elseif f.tabAt == "inner" then
        f.tab:SetPoint("BOTTOM" .. inner, f, "TOP" .. inner, -inward * (f.cut or 0) + x, y)
    else
        f.tab:SetPoint("BOTTOM" .. outer, f, "TOP" .. outer, inward * f.tabInset + x, y)
    end
end

-- How far the tab slides up as the frame arrives: from behind the body,
-- however high it was lifted.
function UF.TabDrop(f)
    return (f.tabHeight or UF.TAB_HEIGHT) + 1 + math.max(0, f.tabY or 0)
end

-- Design mode's dots for the tab (owner px, top left, y down): its three
-- positions along the top, each where the tab's middle would be.
function UF.TabDots(f)
    local fw, w = f:GetWidth(), f.tab:GetWidth()
    local y = -(f.tabHeight or UF.TAB_HEIGHT) / 2
    local outerX, innerX = (f.tabInset or 0) + w / 2, fw - (f.cut or 0) - w / 2
    if f.spec.slant == "left" then outerX, innerX = fw - outerX, fw - innerX end
    return { { spot = "outer", x = outerX, y = y }, { spot = "middle", x = fw / 2, y = y },
             { spot = "inner", x = innerX, y = y } }
end

function UF.CreateCrest(f)
    local c = CreateFrame("Frame", nil, f.tabClip)
    c:SetFrameLevel(f.tab:GetFrameLevel() + 4)
    local function layer(file, level, sub, scale)
        local t = c:CreateTexture(nil, level, nil, sub)
        t:SetTexture(DUI.MEDIA .. file)
        t:SetPoint("CENTER", c, "CENTER", 0, 0)
        t.scale = scale
        return t
    end
    c.glow = layer("crest-glow.png", "BACKGROUND", 0, 2.0)
    c.disc = layer("crest-disc.png", "ARTWORK", 0, 1.0)
    c.ring = layer("crest-ring.png", "ARTWORK", 1, 1.0)
    c.emblem = layer("emblem.png", "OVERLAY", 0, 0.72)
    local b = Style.BORDER
    c.disc:SetVertexColor(b[1], b[2], b[3], 1)
    c:SetScript("OnSizeChanged", function(self, w)
        for _, t in ipairs({ self.glow, self.disc, self.ring, self.emblem }) do
            t:SetSize(w * t.scale, w * t.scale)
        end
    end)
    -- A thin line along the tab's top, in the crest's color.
    f.tabEdge = f.tab:CreateTexture(nil, "OVERLAY", nil, 7)
    f.tabEdge:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.tabEdge:SetPoint("TOPLEFT", f.tab, "TOPLEFT", 0, 0)
    f.tabEdge:SetPoint("TOPRIGHT", f.tab, "TOPRIGHT", 0, 0)
    f.tabEdge:SetHeight(Pixel.Px(f.tab, 1))
    f.tabEdge:Hide()
    c:Hide()
    f.crest = c
end

-- The aggro fill's drawing, kept in one place so the technique can change on
-- its own. A paused-looking Cooldown over the ring (a long one, reset each step
-- to show fraction v of its swipe), and a glow head on its own frame above it.
-- UF.LayoutPortrait sizes both and stores the band's middle in p.radius.
local FILL_D = 1000
local function makeFill(p)
    local cd = CreateFrame("Cooldown", nil, p.top)
    cd:SetPoint("CENTER", p, "CENTER", 0, 0)
    cd:SetFrameLevel(p.top:GetFrameLevel() + 1)
    cd:SetSwipeTexture(UF.RING_FILE)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(UF.RING_FILL_REVERSE)
    cd:Hide()
    local top = CreateFrame("Frame", nil, p.top)
    top:SetAllPoints(p)
    top:SetFrameLevel(cd:GetFrameLevel() + 1)
    local head = top:CreateTexture(nil, "OVERLAY")
    head:SetTexture(DUI.MEDIA .. "glow.png")
    head:SetBlendMode("ADD")
    head:Hide()
    p.fill, p.head = cd, head
    p.fillFile = UF.RING_FILE
    p.fillAt, p.fillGoal = 0, 0
end

-- v is how far around the red reaches (0-1, clockwise from the top), a is the
-- head's alpha. nil v hides both.
local function drawFill(p, v, a)
    if not v then
        p.fill:Hide()
        p.head:Hide()
        return
    end
    local red = UF.THREAT_COLORS.aggro
    p.fill:SetSwipeColor(red[1], red[2], red[3], 1)
    -- A full cooldown would be finished and draw nothing, so stop just short.
    p.fill:SetCooldown(GetTime() - math.min(v, 0.999) * FILL_D, FILL_D)
    p.fill:Show()
    local turn = v * 2 * math.pi
    local r = p.radius or 0
    p.head:ClearAllPoints()
    p.head:SetPoint("CENTER", p, "CENTER", math.sin(turn) * r, math.cos(turn) * r)
    p.head:SetAlpha(a)
    p.head:Show()
end

function UF.CreatePortrait(f)
    local p = CreateFrame("Frame", nil, f)
    p:SetFrameLevel(f:GetFrameLevel() + 6)
    p.shadow = p:CreateTexture(nil, "BACKGROUND", nil, -8)
    p.shadow:SetTexture(DUI.MEDIA .. "crest-glow.png")
    p.shadow:SetVertexColor(0, 0, 0, 0.8)
    p.shadow:SetPoint("CENTER", p, "CENTER", 0, -1)
    -- The aggro pulse's halo, a soft red reaching past the ring (UF.Pulse).
    -- Behind the portrait, breathing in step with the band's light.
    p.halo = p:CreateTexture(nil, "BACKGROUND", nil, -7)
    p.halo:SetTexture(DUI.MEDIA .. "crest-glow.png")
    p.halo:SetBlendMode("ADD")
    p.halo:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.halo:SetAlpha(0)
    p.halo:Hide()
    p.disc = p:CreateTexture(nil, "BACKGROUND")
    p.disc:SetTexture(DUI.MEDIA .. "crest-disc.png")
    p.disc:SetVertexColor(0.02, 0.02, 0.02, 1)
    p.disc:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.mask = p:CreateMaskTexture()
    p.mask:SetTexture(DUI.MEDIA .. "crest-disc.png", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.mask:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.icon:AddMaskTexture(p.mask)
    p.model = CreateFrame("PlayerModel", nil, p)
    p.model:SetFrameLevel(p:GetFrameLevel() + 1)
    p.model:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.model:Hide()
    -- Above the model: the bezel, then the ring.
    p.top = CreateFrame("Frame", nil, p)
    p.top:SetAllPoints(p)
    p.top:SetFrameLevel(p:GetFrameLevel() + 3)
    p.rim = p.top:CreateTexture(nil, "ARTWORK", nil, 1)
    p.rim:SetTexture(DUI.MEDIA .. "portrait-rim.png")
    p.rim:SetVertexColor(0.02, 0.02, 0.02, 1)
    p.rim:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.ring = p.top:CreateTexture(nil, "OVERLAY")
    p.ring:SetTexture(UF.RING_FILE)
    p.ring:SetVertexColor(UF.RING_COLOR[1], UF.RING_COLOR[2], UF.RING_COLOR[3], 1)
    p.ring:SetPoint("CENTER", p, "CENTER", 0, 0)
    -- The dragon behind the ring and the bezel (UF.ApplyCrest, UF.ApplyDragon).
    p.elite = p.top:CreateTexture(nil, "ARTWORK", nil, -2)
    p.elite:SetTexture(UF.DRAGON_FILE)
    p.elite:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.elite:Hide()
    p.eye = p.top:CreateTexture(nil, "OVERLAY", nil, 4)
    p.eye:SetTexture(DUI.MEDIA .. "glow.png")
    p.eye:SetBlendMode("BLEND")
    p.eye:SetVertexColor(UF.EYE_FIRE[1], UF.EYE_FIRE[2], UF.EYE_FIRE[3], 1)
    p.eye:Hide()
    p.eyeCore = p.top:CreateTexture(nil, "OVERLAY", nil, 5)
    p.eyeCore:SetTexture(DUI.MEDIA .. "glow.png")
    p.eyeCore:SetBlendMode("ADD")
    p.eyeCore:SetVertexColor(UF.EYE_CORE[1], UF.EYE_CORE[2], UF.EYE_CORE[3], 1)
    p.eyeCore:Hide()
    -- Threat: the plain band in red, over the ring.
    p.threatBand = p.top:CreateTexture(nil, "OVERLAY", nil, 2)
    p.threatBand:SetTexture(UF.RING_FILE)
    p.threatBand:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.threatBand:Hide()
    -- Aggro pulse: a light copy of the band breathing over the red, so "on you"
    -- reads differently from a red enemy bar. The animation runs on the glow
    -- frame's alpha, while whether it shows (possibly a secret flag) is set on
    -- its holder. A dragon's eyes flare with it (p.pulseEye).
    p.pulseHold = CreateFrame("Frame", nil, p.top)
    p.pulseHold:SetAllPoints(p)
    local glow = CreateFrame("Frame", nil, p.pulseHold)
    glow:SetAllPoints(p)
    p.pulse = glow:CreateTexture(nil, "OVERLAY", nil, 3)
    p.pulse:SetTexture(UF.RING_FILE)
    p.pulse:SetBlendMode("ADD")
    p.pulse:SetPoint("CENTER", p, "CENTER", 0, 0)
    p.pulseEye = glow:CreateTexture(nil, "OVERLAY", nil, 4)
    p.pulseEye:SetTexture(DUI.MEDIA .. "glow.png")
    p.pulseEye:SetBlendMode("ADD")
    p.pulseEye:SetVertexColor(UF.EYE_FIRE[1], UF.EYE_FIRE[2], UF.EYE_FIRE[3], 1)
    local anim = glow:CreateAnimationGroup()
    local a = anim:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(UF.PULSE_ALPHA)
    a:SetDuration(UF.PULSE_TIME)
    a:SetSmoothing("IN_OUT")
    anim:SetLooping("BOUNCE")
    p.pulseAnim = anim
    local haloAnim = p.halo:CreateAnimationGroup()
    local h = haloAnim:CreateAnimation("Alpha")
    h:SetFromAlpha(0)
    h:SetToAlpha(UF.HALO_ALPHA)
    h:SetDuration(UF.PULSE_TIME)
    h:SetSmoothing("IN_OUT")
    haloAnim:SetLooping("BOUNCE")
    p.haloAnim = haloAnim
    p.pulseHold:Hide()
    makeFill(p)
    p:Hide()
    f.portrait = p
end

-- A hit rect is protected on a secure button, so in combat (a party button made
-- mid-fight) it waits until combat ends. Ribbon's row above and line below are
-- clickable like the frame too (f.hitTop, f.foot from UF.Layout).
function UF.SetHitRect(f, l, r)
    local t, b = -(f.hitTop or 0), -(f.foot or 0)
    if InCombatLockdown() then
        DUI.AfterCombat(function() f:SetHitRectInsets(l, r, t, b) end, "hitrect:" .. tostring(f))
        return
    end
    f:SetHitRectInsets(l, r, t, b)
end

-- The hit rect waits for combat to end (UF.SetHitRect).
function UF.LayoutPortrait(f, cfg)
    local p = f.portrait
    f.tabInset = UF.TAB_INSET
    f.ringInset = 0
    f.ringReach = 0
    f.portraitOverlap = 0
    local shell = Style.GetShell(f)
    if shell then shell.opts.coveredEnd = nil end
    if not p then return end
    local mode = UF.PortraitMode(f, cfg)
    local holder = f.portraitHolder
    local free = UF.PORTRAIT_FREE[f.spec.unit] and cfg.portraitAt == "free"
    -- An options preview has no holder, so a portrait on its own leaves it,
    -- as a power bar on its own does.
    if free and not holder then mode = "none" end
    f.portraitFree = (free and mode ~= "none" and cfg.enabled ~= false) and true or false
    f.iconsStay = f.portraitFree and cfg.portraitIconsStay == true
    UF.HomePortrait(f)
    if holder then
        holder.want = f.portraitFree
        DUI.Movers.Suspend(holder.key, not f.portraitFree)
        if not f.portraitFree then holder:Hide() end
    end
    f.portraitMode = mode
    if mode == "none" then
        p:Hide()
        UF.SetHitRect(f, 0, 0)
        return
    end
    f.ringColor = cfg.portraitRing
    local outerRight = f.spec.slant == "left"
    f.portraitScale = tonumber(cfg.portraitScale) or 1
    local R
    if f.ribbon then
        -- Ribbon: as tall as the whole ribbon, centered on it.
        local up, down = f.hitTop or 0, f.foot or 0
        R = Pixel.Snap(f, (f:GetHeight() + up + down) * UF.RIBBON_RING * f.portraitScale)
        f.portraitY = (up - down) / 2
    else
        R = Pixel.Snap(f, f:GetHeight() * UF.PORTRAIT_SIZE * f.portraitScale / 2)
        f.portraitY = 0
    end
    if f.portraitFree then
        f.portraitY = 0
        holder:SetScale(DUI.Movers.Scale(holder.key))
        holder:SetSize(2 * R, 2 * R)
    end
    local off = R * UF.PORTRAIT_OUT
    f.portraitOverlap = R - off  -- how far the ring reaches over the bar
    local looks = ns.module and ns.module.db and ns.module.db.portraits or {}
    local ratio
    f.ringFile, f.ringLitFile, ratio = UF.RingFiles(looks.ringWidth, looks.ringLine)
    local inner = R * ratio
    p:SetSize(2 * R, 2 * R)
    f.portraitEdge, f.portraitX = outerRight and "RIGHT" or "LEFT", outerRight and off or -off
    UF.PlacePortrait(f, 1)
    local art = 2 * R / UF.RING_OUTER
    p.ring:SetSize(art, art)
    -- The dragon wraps the outer side. Drawn for a ring on the right, mirrored
    -- for one on the left.
    local dragon, l, r = art / UF.DRAGON_RING, 0, 1
    if not outerRight then l, r = 1, 0 end
    p.elite:SetSize(dragon, dragon)
    p.elite:SetTexCoord(l, r, 0, 1)
    local E = UF.DRAGON_EYE
    local ex, ey = (outerRight and 1 or -1) * E.x * dragon, E.y * dragon
    for _, t in ipairs({ p.eye, p.pulseEye, p.eyeCore }) do
        local k = t == p.eyeCore and E.core or E.size
        t:SetSize(k * dragon, k * dragon)
        t:ClearAllPoints()
        t:SetPoint("CENTER", p, "CENTER", ex, ey)
    end
    f.ownDragon = f.spec.unit == "player" and cfg.portraitDragon == true
    f.dragonColor = cfg.portraitDragonColor
    p.threatBand:SetSize(art, art)
    p.pulse:SetSize(art, art)
    p.fill:SetSize(art, art)
    p.head:SetSize(0.8 * R, 0.8 * R)
    p.radius = R * (1 + ratio) / 2   -- the band's middle
    p.shadow:SetSize(2.6 * R, 2.6 * R)
    p.halo:SetSize(UF.HALO_SIZE * R, UF.HALO_SIZE * R)
    p.disc:SetSize(2 * inner + 2, 2 * inner + 2)
    p.rim:SetSize(2 * R * UF.RIM_OUTER, 2 * R * UF.RIM_OUTER)
    p.mask:SetSize(2 * inner, 2 * inner)
    -- The model's corners reach just under the ring's outer edge.
    local side = 2 * R * 0.97 / math.sqrt(2)
    p.model:SetSize(side, side)
    p.classSize = UF.CLASS_ICON_FILL * inner
    p.faceSize = 2 * inner
    p:Show()
    if f.portraitFree then
        -- On its own: the frame keeps its whole length and its own hit rect.
        holder:SetShown(f:IsShown())
        UF.SetHitRect(f, 0, 0)
        return
    end
    -- The tab starts clear of the ring, and the ring is clickable like the frame.
    f.ringInset = R - off
    f.tabInset = f.ringInset + 8
    local reach = R + off
    f.ringReach = reach   -- how far the ring reaches past the outer end
    -- The shell's corner caps sit above the ring (Style.Shell's s.over). At the
    -- ring's end they're removed once the ring reaches past the corner's curve
    -- along the bar's top and bottom edges (a small ring leaves them showing).
    local edge = f:GetHeight() / 2 + math.abs(f.portraitY)
    local corner = Pixel.Px(f, shell and shell.opts.cornerPx or DUI:Get("general", "cornerPx") or 0)
    if shell and R > edge and math.sqrt(R * R - edge * edge) - off >= corner then
        shell.opts.coveredEnd = outerRight and "right" or "left"
    end
    UF.SetHitRect(f, outerRight and 0 or -reach, outerRight and -reach or 0)
end

-- The portrait at scale s (popping in as the frame arrives), its middle where
-- it rests, since a frame's offsets are in its own scale.
function UF.PlacePortrait(f, s)
    local p = f.portrait
    p:SetScale(s)
    p:ClearAllPoints()
    if f.portraitFree then
        p:SetPoint("CENTER", f.portraitHolder, "CENTER", 0, 0)
        return
    end
    p:SetPoint("CENTER", f, f.portraitEdge, f.portraitX / s, (f.portraitY or 0) / s)
end

-- The plain ring in the frame's ring color (UF.RING_COLORS), and the aggro band
-- and its sweep in the matching texture. A player whose class the game hides
-- gets the client's class color (secret numbers) on the lit band, since a
-- secret can't pick a pair. A sample shows its sample class.
-- Returns the ring's colors: mode, then a pair (lo, hi) or a single r, g, b for
-- the lit band (a hidden class's, secret, or a one-color accent), or neither
-- (the plain gray). mode: a ring color other than the frame's (your dragon's
-- class gradient).
local function ringColors(f, mode)
    mode = mode or f.ringColor
    mode = UF.RING_COLORS[mode] and mode or "light"
    local Grad = DUI.Gradients
    local lo, hi, sr, sg, sb
    if mode == "dark" then
        local b, l = Style.BAND, Style.BAND_LIT
        lo, hi = CreateColor(b[1], b[2], b[3], 1), CreateColor(l[1], l[2], l[3], 1)
    elseif mode == "class" then
        if f.test then
            lo, hi = Grad.Colors(f.test.portraitClass or "HOSTILE")
        else
            sr, sg, sb = Grad.HiddenClassColor(f.unitToken)
            if type(sr) == "nil" then lo, hi = Grad.Colors(Grad.KeyFor(f.unitToken)) end
        end
    elseif mode == "accent" then
        local a, b = Style.AccentPair()
        if a then
            lo, hi = CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1)
        else
            sr, sg, sb = Style.Accent()
        end
    elseif mode == "daylight" then
        local a, b = Style.GRADIENT_SHAPE[1], Style.GRADIENT_SHAPE[2]
        lo, hi = CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1)
    end
    return mode, lo, hi, sr, sg, sb
end

function UF.PaintRing(f)
    local p = f.portrait
    if not (p and p:IsShown()) then return end
    local mode, lo, hi, sr, sg, sb = ringColors(f)
    local file, lit = f.ringFile or UF.RING_FILE, f.ringLitFile or UF.RING_LIT_FILE
    if type(sr) ~= "nil" then
        p.ring:SetTexture(lit)
        p.ring:SetVertexColor(sr, sg, sb, 1)
    elseif lo then
        p.ring:SetTexture(file)
        p.ring:SetVertexColor(1, 1, 1, 1)
        p.ring:SetGradient("VERTICAL", lo, hi)   -- last, since a plain color clears it
    else
        local c = UF.RING_COLOR
        p.ring:SetTexture(file)
        p.ring:SetVertexColor(c[1], c[2], c[3], 1)
    end
    local red = mode == "light" and file or lit
    if p.fillFile ~= red then
        p.fillFile = red
        p.threatBand:SetTexture(red)
        p.pulse:SetTexture(red)
        p.fill:SetSwipeTexture(red)
    end
    UF.ApplyDragon(f)   -- your own dragon's class gradient follows the unit's
end

-- Class icons for players, faces for NPCs or when the class is secret.
function UF.UpdatePortrait(f)
    local p = f.portrait
    if not (p and p:IsShown()) then return end
    UF.PaintRing(f)
    local sample = f.test
    -- A sample shows its class icon. Faces and models come from you.
    local u = sample and "player" or f.unitToken
    local mode = f.portraitMode
    if mode == "class" then
        local isPlayer, token
        if sample then
            isPlayer, token = true, sample.portraitClass
        else
            isPlayer = UnitIsPlayer(u)
            token = select(2, UnitClass(u))
        end
        local known = not isSecret(isPlayer) and isPlayer == true and not isSecret(token) and type(token) == "string"
        local file, l, r, t, b
        if known then file, l, r, t, b = UF.ClassIcon(token, f.iconStyle, f.classIcons) end
        if file then
            p.model:Hide()
            p.rim:Hide()
            p.icon:SetTexture(file)
            -- A ring on the right (the target) mirrors its icon to face inward.
            if f.spec.slant == "left" then l, r = r, l end
            p.icon:SetTexCoord(l, r, t, b)
            p.icon:SetSize(p.classSize, p.classSize)
            p.icon:Show()
            return
        end
        mode = "2d"
    end
    if mode == "3d" then
        p.icon:Hide()
        p.rim:Show()
        p.model:Show()
        pcall(p.model.SetUnit, p.model, u)
        pcall(p.model.SetPortraitZoom, p.model, 1)
        pcall(p.model.SetCamDistanceScale, p.model, UF.MODEL_CLOSER)
        return
    end
    p.model:Hide()
    p.rim:Hide()
    pcall(SetPortraitTexture, p.icon, u)
    Style.CropIcon(p.icon)
    p.icon:SetSize(p.faceSize, p.faceSize)
    p.icon:Show()
end

-- Name on the bar: inside the health bar at the portrait's end, with the raid
-- marker before it. The big health number keeps the inner end.
function UF.PlaceBarName(f)
    local outerRight = f.spec.slant == "left"
    local outer = outerRight and "RIGHT" or "LEFT"
    local sign = outerRight and -1 or 1
    local p = f.portrait
    local pad = 4
    if p and p:IsShown() then
        pad = pad + math.max(0, f.portraitOverlap or 0)
    end
    local markerW = f.markerShown and not f.markerSpot and ((f.markerSize or UF.MARKER_SIZE) + 4) or 0
    if f.marker and not f.markerSpot then
        f.marker:ClearAllPoints()
        f.marker:SetPoint(outer, f.health, outer, sign * pad + f.markerNudge.x, f.markerNudge.y)
    end
    f.nameText:ClearAllPoints()
    UF.PlaceText(f.nameText, outer, f.health, outer, sign * (pad + markerW), 0, f.barNameX, f.barNameY)
    f.nameText:SetWidth(math.max(1, f:GetWidth() * 0.5 - pad - markerW))
    f.nameText:SetJustifyH(outer)
end

-- Ribbon: the name at the row's outer end, after the raid marker (and the crest
-- when it sits there), level with the health number at the inner end, which
-- keeps the rest of the row. A long name is cut short with "...".
function UF.PlaceRowName(f)
    local outerRight = f.spec.slant == "left"
    local outer = outerRight and "RIGHT" or "LEFT"
    local sign = outerRight and -1 or 1
    local markerW = f.markerShown and not f.markerSpot and ((f.markerSize or UF.MARKER_SIZE) + 4) or 0
    local crestW = (f.crestShown and f.crestOnTab ~= false) and (UF.CREST_SIZE / 2) or 0
    if f.marker and not f.markerSpot then
        f.marker:ClearAllPoints()
        f.marker:SetPoint(outer, f.tab, outer, sign * crestW + f.markerNudge.x, f.markerNudge.y)
    end
    f.nameText:ClearAllPoints()
    f.nameText:SetPoint("BOTTOM" .. outer, f.tab, "BOTTOM" .. outer, sign * (crestW + markerW), UF.RIBBON_TEXT_LIFT)
    f.nameText:SetWidth(math.max(1, f.tab:GetWidth() * UF.RIBBON_NAME_SHARE - crestW - markerW))
    f.nameText:SetJustifyH(outer)
end

-- The tab fits the name, plus the raid marker before it and room for the crest
-- at the outer corner. A secret name can't be measured, so it gets a fixed
-- fraction of the frame instead.
function UF.SizeTab(f, name)
    if not f.tab then return end
    -- Ribbon's row runs from past the ring to the frame's inner end.
    if f.ribbon then f.tab:SetWidth(Pixel.Snap(f, math.max(30, f:GetWidth() - (f.tabInset or 0)))) end
    if f.nameOnBar then
        if f.tileName then
            UF.PlaceTileName(f)
            -- At a spot, the raid marker rides just before the name.
            if f.marker and not f.markerSpot and f.tileName.pos ~= "bar" then
                f.marker:ClearAllPoints()
                f.marker:SetPoint("RIGHT", f.nameText, "LEFT", -3 + f.markerNudge.x, f.markerNudge.y)
            end
        else
            UF.PlaceBarName(f)
        end
        if f.onTabSized then f.onTabSized(f) end
        return
    end
    if f.ribbon then
        UF.PlaceRowName(f)
        if f.onTabSized then f.onTabSized(f) end
        return
    end
    local fw = f:GetWidth()
    local sl = Style.GetSlant(f.tab)
    local tabCut = (sl and sl.side) and sl.cut or 0
    if not isSecret(name) and name == nil then name = f.nameText:GetText() end
    local markerW = f.markerShown and not f.markerSpot and ((f.markerSize or UF.MARKER_SIZE) + 4) or 0
    local crestW = (f.crestShown and f.crestOnTab ~= false) and (UF.CREST_SIZE / 2) or 0
    local extra = 2 * UF.TAB_PAD + tabCut + markerW + crestW
    local w
    if f.tabWidth == "full" then
        -- Past the portrait to where the frame's top ends (its angled end).
        w = fw - (f.tabInset or 0) - (f.cut or 0)
    elseif f.tabWidth == "fixed" then
        w = math.min(f.tabWidthPx or 90, fw)
    elseif isSecret(name) or name == nil then
        w = fw * 0.5
    else
        -- Measure the name at its natural width, then fit it to the tab.
        f.nameText:SetWidth(0)
        local ok, sw = pcall(f.nameText.GetStringWidth, f.nameText)
        -- In an instance the width can be secret even when the text isn't.
        w = (ok and type(sw) == "number" and not isSecret(sw)) and (sw + extra) or fw * 0.5
        w = math.min(w, fw * UF.TAB_MAX)
    end
    w = Pixel.Snap(f, math.max(30, w))
    f.tab:SetWidth(w)
    -- A name too long for the tab is cut short with "...".
    f.nameText:SetWidth(math.max(1, w - extra + 2))
    -- The marker sits at the tab's inner end and the crest at its outer end.
    -- The name is centered in what's left, or held to one side of it.
    local outerRight = f.spec.slant == "left"
    local sign = outerRight and 1 or -1
    local align = UF.TAB_ALIGNS[f.tabAlign] or "CENTER"
    f.nameText:ClearAllPoints()
    if align == "CENTER" then
        f.nameText:SetPoint("CENTER", f.tab, "CENTER", sign * (markerW - crestW) / 2, 0)
    else
        local innerRoom, outerRoom = tabCut + markerW, crestW
        local leftRoom = outerRight and innerRoom or outerRoom
        local rightRoom = outerRight and outerRoom or innerRoom
        f.nameText:SetPoint(align, f.tab, align,
            align == "LEFT" and (UF.TAB_PAD + leftRoom) or -(UF.TAB_PAD + rightRoom), 0)
    end
    f.nameText:SetJustifyH(align)
    if f.marker and not f.markerSpot then
        f.marker:ClearAllPoints()
        -- Inward from the tab's inner end, past its angled cut.
        local inner = outerRight and "LEFT" or "RIGHT"
        f.marker:SetPoint(inner, f.tab, inner, sign * (tabCut + 5) + f.markerNudge.x, f.markerNudge.y)
    end
    if sl and sl.side then Style.LayoutSlant(f.tab) end
    if f.onTabSized then f.onTabSized(f) end
end

-- Which group member a unit is ("player", "party2", "raid14") when the client
-- will say. nil when it won't, or the unit isn't in the group. One
-- UpdateIdentity asks this up to 4 times for the same unit (a hidden class in a
-- battleground: color, name, ring, class layers), so the answer is cached for
-- that pass (identityUnit, set and cleared by UF.UpdateIdentity).
local PARTY_TOKENS, RAID_TOKENS = {}, {}
for i = 1, 4 do PARTY_TOKENS[i] = "party" .. i end
for i = 1, 40 do RAID_TOKENS[i] = "raid" .. i end
local function sameUnit(unit, g)
    if not UnitExists(g) then return false end
    local ok, r = pcall(UnitIsUnit, unit, g)
    return ok and not isSecret(r) and r == true
end
local function findGroupToken(unit)
    if sameUnit(unit, "player") then return "player" end
    local list = (IsInRaid and IsInRaid()) and RAID_TOKENS or PARTY_TOKENS
    for i = 1, #list do
        if sameUnit(unit, list[i]) then return list[i] end
    end
end
local identityUnit, identityAt, identityToken   -- identityToken: false means asked, none found
function UF.GroupToken(unit)
    if unit == identityUnit and identityAt == GetTime() and type(identityToken) ~= "nil" then
        return identityToken or nil
    end
    local g = findGroupToken(unit)
    if unit == identityUnit then identityAt, identityToken = GetTime(), g or false end
    return g
end

-- A unit's class, read from its group token when the client hides it for this
-- one (in an instance, the target's target). nil when unknown.
local function classOf(unit)
    local _, token = UnitClass(unit)
    if isSecret(token) then
        token = nil
        local g = UF.GroupToken(unit)
        if g then _, token = UnitClass(g) end
    end
    if isSecret(token) then return nil end
    return token
end
UF.ClassOf = classOf

function UF.UnitColor(unit)
    local isPlayer = UnitIsPlayer(unit)
    if isSecret(isPlayer) then
        -- Anyone in the group is a player, whatever else is hidden.
        local g = UF.GroupToken(unit)
        if not g then return Style.Neutral() end
        local _, token = UnitClass(g)
        return Style.ClassColor(token)
    end
    if isPlayer then return Style.ClassColor(classOf(unit)) end
    local tapped = UnitIsTapDenied(unit)
    if not isSecret(tapped) and tapped then return UF.TappedColor() end
    return UF.ReactionColor(UnitReaction(unit, "player"))
end

-- A shield's bar uses the overshield's stripes, so a shield looks the same
-- whether it fits in the missing health or runs past it. Not the Bar texture
-- setting, since stripes are what say "shield".
local function striped(f)
    local O = UF.OVERSHIELD
    local s = CreateFrame("StatusBar", nil, f)
    s:SetStatusBarTexture(O.stripes)
    local tex = s:GetStatusBarTexture()
    tex:SetTexture(O.stripes, "REPEAT", "REPEAT")
    if tex.SetHorizTile then tex:SetHorizTile(true); tex:SetVertTile(true) end
    return s
end

local function predictionBar(f, kind)
    if kind == "absorbs" then return striped(f) end
    local s = Style.Bar(f, "seamless", UF.MediaOf(f.spec).bars.health)
    Style.BarBack(s):Hide()
    return s
end

local function segment(f, kind, level)
    local c = UF.PREDICTION[kind]
    local s = predictionBar(f, kind)
    s:SetFrameLevel(f.health:GetFrameLevel() + level)
    s:SetStatusBarColor(c.color[1], c.color[2], c.color[3], c.alpha)
    s:SetMinMaxValues(0, 1)
    s:SetValue(0)
    local w = predictionBar(f, kind)
    w:SetFrameLevel(f.health:GetFrameLevel() + level)
    w:SetStatusBarColor(c.color[1], c.color[2], c.color[3], c.alpha)
    w:SetMinMaxValues(0, 1)
    w:SetValue(0)
    w.mask = w:CreateMaskTexture()
    w:GetStatusBarTexture():AddMaskTexture(w.mask)
    s.wedge = w
    -- Nothing past the frame's own angled end.
    if f.spec.slant then
        Style.Clip(f, s:GetStatusBarTexture(), "inner")
        Style.Clip(f, w:GetStatusBarTexture(), "inner")
    end
    return s
end

function UF.CreatePrediction(f)
    f.heals = segment(f, "heals", 1)
    f.absorbs = segment(f, "absorbs", 1)
    UF.CreateOvershield(f)
    -- The bars are as long as the health bar and kept in sync whenever it
    -- resizes, so one laid out before its tile had a size (0 px) still shows.
    f.health:HookScript("OnSizeChanged", function(bar, w, h)
        if bar:GetOrientation() == "VERTICAL" then
            f.heals:SetHeight(h); f.absorbs:SetHeight(h)
        else
            f.heals:SetWidth(w); f.absorbs:SetWidth(w)
        end
    end)
end

function UF.CreateOvershield(f)
    local O, c = UF.OVERSHIELD, UF.PREDICTION.absorbs.color
    local o = CreateFrame("StatusBar", nil, f)
    o:SetFrameLevel(f.health:GetFrameLevel() + 2)
    o:SetStatusBarTexture(O.stripes)
    local tex = o:GetStatusBarTexture()
    tex:SetTexture(O.stripes, "REPEAT", "REPEAT")
    if tex.SetHorizTile then tex:SetHorizTile(true); tex:SetVertTile(true) end
    o:SetStatusBarColor(c[1], c[2], c[3], O.alpha)
    o:SetMinMaxValues(0, 1)
    o:SetValue(0)
    o:SetAlpha(0)
    o.glow = o:CreateTexture(nil, "OVERLAY")
    o.glow:SetTexture(O.glow)
    o.glow:SetBlendMode("ADD")
    if f.spec.slant then
        Style.Clip(f, tex, "inner")
        Style.Clip(f, o.glow, "inner")
    end
    f.overshield = o
end

-- Health filling bottom to top (fillVertical): heals and shields stack upward
-- from the fill's top edge and the overshield comes down from the top. No
-- angled ends on a tile.
local function layoutPredictionVertical(f)
    local h = f.health:GetHeight()
    local anchor = f.health:GetStatusBarTexture()
    for _, s in ipairs({ f.heals, f.absorbs }) do
        s:ClearAllPoints()
        s:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
        s:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
        s:SetHeight(h)
        s:SetOrientation("VERTICAL")
        s:SetReverseFill(false)
        Style.AngleFill(s, nil, 0)
        s.wedge:Hide()
        anchor = s:GetStatusBarTexture()
    end
    local o = f.overshield
    if o then
        o:ClearAllPoints()
        o:SetAllPoints(f.health)
        o:SetOrientation("VERTICAL")
        -- From the top down, or reversed from the bottom up.
        local fromTop = not f.overshieldReverse
        o:SetReverseFill(fromTop)
        local edge = fromTop and "BOTTOM" or "TOP"
        local fill = o:GetStatusBarTexture()
        o.glow:ClearAllPoints()
        o.glow:SetPoint("LEFT", fill, edge .. "LEFT", 0, 0)
        o.glow:SetPoint("RIGHT", fill, edge .. "RIGHT", 0, 0)
        o.glow:SetHeight(UF.OVERSHIELD.glowWidth)
        -- The game's art is an upright line, rotated to lie along the top
        -- (stretched as is, it smeared into a blob).
        o.glow:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        o:SetShown(f.predictAbsorbs and f.overshieldOn)
    end
    f.heals:SetShown(f.predictHeals)
    f.absorbs:SetShown(f.predictAbsorbs)
end

-- The shield's texture per the Colors page: stripes (the default, and the
-- fallback when a shared bar isn't registered), plain, or "lsm:<name>".
-- Returns the file and whether it tiles.
function UF.ShieldTexture(style)
    if style == "plain" then return "Interface\\Buttons\\WHITE8x8", false end
    local shared = DUI.Media and DUI.Media.Fetch("statusbar", style)
    if shared then return shared, false end
    return UF.OVERSHIELD.stripes, true
end

-- The heal and shield colors and the shield's texture, from db.colors. The
-- wedge bars follow the shield, and so does the overshield unless the Colors
-- page gives it its own color (overshieldPaint) or texture (overshieldStyle).
-- Also stores on the frame whether it shows (overshield) and which end it fills
-- from (overshieldReverse), for LayoutPrediction.
function UF.StylePrediction(f)
    local c = UF.colors or {}
    local P = UF.PREDICTION
    local hc = type(c.healColor) == "table" and c.healColor or P.heals.color
    local ac = type(c.absorbColor) == "table" and c.absorbColor or P.absorbs.color
    local oc = c.overshieldPaint == "custom" and type(c.overshieldColor) == "table" and c.overshieldColor or ac
    f.overshieldOn = c.overshield ~= false
    f.overshieldReverse = c.overshieldReverse == true
    if f.heals then
        f.heals:SetStatusBarColor(hc[1], hc[2], hc[3], P.heals.alpha)
        f.heals.wedge:SetStatusBarColor(hc[1], hc[2], hc[3], P.heals.alpha)
    end
    local file, tile = UF.ShieldTexture(c.absorbStyle)
    local oFile, oTile = file, tile
    local os = c.overshieldStyle
    if type(os) == "string" and os ~= "shield" then oFile, oTile = UF.ShieldTexture(os) end
    local bars = { f.absorbs, f.absorbs and f.absorbs.wedge, f.overshield }
    for i = 1, 3 do
        local s = bars[i]
        if s then
            local over = i == 3
            local col = over and oc or ac
            s:SetStatusBarColor(col[1], col[2], col[3], over and UF.OVERSHIELD.alpha or P.absorbs.alpha)
            local tex = s:GetStatusBarTexture()
            if type(tex) == "table" then
                local fl, tl = file, tile
                if over then fl, tl = oFile, oTile end
                tex:SetTexture(fl, tl and "REPEAT" or nil, tl and "REPEAT" or nil)
                if tex.SetHorizTile then tex:SetHorizTile(tl); tex:SetVertTile(tl) end
            end
        end
    end
end

-- side is the frame's angled end ("right": bars grow right) or nil.
function UF.LayoutPrediction(f, side)
    UF.StylePrediction(f)
    if f.health:GetOrientation() == "VERTICAL" then return layoutPredictionVertical(f) end
    for _, s in ipairs({ f.heals, f.absorbs, f.overshield }) do s:SetOrientation("HORIZONTAL") end
    local growLeft = f.growLeft
    if type(growLeft) ~= "boolean" then growLeft = f.spec.slant == "left" end
    if f.flipped then side = nil end
    local lead = growLeft and "LEFT" or "RIGHT"
    local back = growLeft and "RIGHT" or "LEFT"
    local c = side and f.healthCut or 0
    local w = f.health:GetWidth()
    local anchor = f.health:GetStatusBarTexture()
    for _, s in ipairs({ f.heals, f.absorbs }) do
        s:ClearAllPoints()
        s:SetPoint("TOP" .. back, anchor, "TOP" .. lead, 0, 0)
        s:SetPoint("BOTTOM" .. back, anchor, "BOTTOM" .. lead, 0, 0)
        s:SetWidth(w)
        s:SetReverseFill(growLeft)
        Style.AngleFill(s, side and (growLeft and "left" or "right") or nil, c)
        local wedge = s.wedge
        wedge:ClearAllPoints()
        wedge:SetPoint("TOP" .. lead, anchor, "TOP" .. lead, 0, 0)
        wedge:SetPoint("BOTTOM" .. lead, anchor, "BOTTOM" .. lead, 0, 0)
        wedge:SetWidth(math.max(c, 0.01))
        wedge.mask:SetTexture(TRAIL_MASK[growLeft and "left" or "right"], "CLAMP", "CLAMP")
        -- The mask's line runs from the fill's edge at the top to a cut back at
        -- the bottom, so it hangs off the wedge's back side.
        wedge.mask:ClearAllPoints()
        wedge.mask:SetPoint("TOP" .. back, wedge, "TOP" .. back, 0, 0)
        wedge.mask:SetPoint("BOTTOM" .. back, wedge, "BOTTOM" .. back, 0, 0)
        wedge.mask:SetWidth(4 * math.max(c, 0.01))
        -- The next segment starts where this one's fill ends.
        anchor = s:GetStatusBarTexture()
    end
    -- The overshield fills from the frame's end back over the health (or, when
    -- reversed, from where the health starts). Its line sits on the edge it
    -- grows from.
    local o = f.overshield
    if o then
        o:ClearAllPoints()
        o:SetAllPoints(f.health)
        local fromEnd = not f.overshieldReverse
        o:SetReverseFill(growLeft ~= fromEnd)
        local free = (growLeft == fromEnd) and "RIGHT" or "LEFT"
        local fill = o:GetStatusBarTexture()
        o.glow:ClearAllPoints()
        o.glow:SetPoint("TOP", fill, "TOP" .. free, 0, 0)
        o.glow:SetPoint("BOTTOM", fill, "BOTTOM" .. free, 0, 0)
        o.glow:SetWidth(UF.OVERSHIELD.glowWidth)
        o.glow:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
        o:SetShown(f.predictAbsorbs and f.overshieldOn)
    end
    f.heals:SetShown(f.predictHeals)
    f.absorbs:SetShown(f.predictAbsorbs)
    f.heals.wedge:SetShown(c > 0 and f.predictHeals)
    f.absorbs.wedge:SetShown(c > 0 and f.predictAbsorbs)
end

-- Your DoTs' remaining damage (DUI.Dots): a veil over the end of the health
-- fill they'll still take, and a skull on the portrait (or past the frame's
-- outer end) once they're enough to kill. Only the target has these.
function UF.CreateDots(f)
    local Dots = DUI.Dots
    f.dotVeil = Dots.NewVeil(f.health, 1)
    -- Nothing past the frame's own angled end (a reversed fill starts there).
    if f.spec.slant then Style.Clip(f, f.dotVeil.bar:GetStatusBarTexture(), "inner") end
    f.dotSkull = Dots.NewSkull(f.overlay, 18)
    f.dotSkull:SetFrameLevel(f:GetFrameLevel() + 12)   -- above the portrait's ring
    f.health:HookScript("OnSizeChanged", function()
        if f.dotCfg then UF.LayoutDots(f, f.dotCfg) end
    end)
end

function UF.LayoutDots(f, cfg)
    local Dots = DUI.Dots
    f.dotCfg = cfg
    f.dotTint = cfg.dotTint ~= false
    f.dotSkullOn = cfg.dotSkull ~= false
    Dots.Want("unitframes", f.dotTint or f.dotSkullOn)
    Dots.LayoutVeil(f.dotVeil, f.health, f.growLeft == true)
    Dots.TintVeil(f.dotVeil, Dots.Tint())
    local s = f.dotSkull
    s:ClearAllPoints()
    -- With the portrait on its own, the skull goes along with it, unless the
    -- icons were asked to stay on the frame.
    local home = (f.portraitFree and not f.iconsStay) and f.portraitHolder or f.overlay
    if s:GetParent() ~= home then s:SetParent(home) end
    s:SetFrameLevel((home == f.overlay and f or home):GetFrameLevel() + 12)
    local p = f.portrait
    if p and f.portraitMode and f.portraitMode ~= "none" and not f.iconsStay then
        Dots.SizeSkull(s, math.max(12, math.floor(p:GetHeight() * 0.55 + 0.5)))
        s:SetPoint("CENTER", p, "CENTER", 0, 0)
    else
        -- The outer end is the one without the angle, however the bars fill.
        Dots.SizeSkull(s, 16)
        if f.spec.slant == "left" then
            s:SetPoint("LEFT", f, "RIGHT", 4, 0)
        else
            s:SetPoint("RIGHT", f, "LEFT", -4, 0)
        end
    end
    UF.UpdateDots(f)
end

function UF.UpdateDots(f)
    if not f.dotVeil then return end
    local Dots = DUI.Dots
    local veil = f.dotTint and f.dotVeil or nil
    local skull = f.dotSkullOn and f.dotSkull or nil
    if f.test then
        local s = f.test
        Dots.PaintSample(veil, skull, 100, s.dots or 0, s.dotSkull == true)
    else
        Dots.Paint(f.unitToken, veil, skull)
    end
    if not veil then f.dotVeil:Hide() end
    if not skull then f.dotSkull:Hide() end
end

local function amount(fn, u)
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn, u)
    if not ok or type(v) == "nil" then return 0 end
    return v
end

local function setPredictBar(s, max, v)
    s:SetMinMaxValues(0, max)
    s:SetValue(v)
    s.wedge:SetValue(v)
end

-- Runs on every health change of every frame and tile, so no tables per call.
function UF.SetPrediction(f, max, heals, absorbs)
    setPredictBar(f.heals, max, heals)
    setPredictBar(f.absorbs, max, absorbs)
end

-- The frame's heal prediction calculator (one per frame, never shared), filled
-- for the unit. nil when the client has none or it can't be read. Heals are
-- capped by the client at the missing health plus UF.HEAL_OVERFLOW's fraction
-- of the bar (the game's raid frames use 1.05), so an overheal still shows past
-- the health's end but never longer than that (a 5 health totem once showed
-- one a whole frame long). Absorbs fit in the missing health, and what doesn't
-- fit is the overshield.
UF.HEAL_OVERFLOW = 1.25
local function filledCalc(f, u)
    if type(CreateUnitHealPredictionCalculator) ~= "function" or type(UnitGetDetailedHealPrediction) ~= "function" then
        return nil
    end
    local calc = f.healCalc
    if not calc then
        local ok, made = pcall(CreateUnitHealPredictionCalculator)
        if not ok or not made then return nil end
        calc = made
        local mode = Enum.UnitDamageAbsorbClampMode and Enum.UnitDamageAbsorbClampMode.MissingHealth
        if type(mode) == "number" and calc.SetDamageAbsorbClampMode then pcall(calc.SetDamageAbsorbClampMode, calc, mode) end
        local heal = Enum.UnitIncomingHealClampMode and Enum.UnitIncomingHealClampMode.MissingHealth
        if type(heal) == "number" and calc.SetIncomingHealClampMode then pcall(calc.SetIncomingHealClampMode, calc, heal) end
        if calc.SetIncomingHealOverflowPercent then pcall(calc.SetIncomingHealOverflowPercent, calc, UF.HEAL_OVERFLOW) end
        f.healCalc = calc
    end
    if not pcall(UnitGetDetailedHealPrediction, u, nil, calc) then return nil end
    return calc
end

-- The absorbs that fit in the missing health, and whether there's more (an
-- overshield), from the client's heal prediction calculator. Both may be secret,
-- so they only go to the bars and the alpha setter. Without the calculator:
-- the whole shield and no overshield. calc: one already filled.
function UF.Absorbs(f, u, calc)
    calc = calc or filledCalc(f, u)
    if not calc then return amount(UnitGetTotalAbsorbs, u), nil end
    local ok, fits, over = pcall(calc.GetDamageAbsorbs, calc)
    if not ok or type(fits) == "nil" then return amount(UnitGetTotalAbsorbs, u), nil end
    return fits, over
end

-- The incoming heal, capped at UF.HEAL_OVERFLOW. May be secret, so it only goes
-- to the bars. Without the calculator, the whole heal.
function UF.Heals(f, u, calc)
    if calc and calc.GetIncomingHeals then
        local ok, fits = pcall(calc.GetIncomingHeals, calc)
        if ok and type(fits) ~= "nil" then return fits end
    end
    return amount(UnitGetIncomingHeals, u)
end

-- max: the unit's max health when the caller already read it.
function UF.UpdatePrediction(f, max)
    if f.test then return end
    local u = f.unitToken
    -- No "x and amount or 0": an amount may be secret and can't be tested.
    local heals, absorbs, over = 0, 0, nil
    local calc = (f.predictHeals or f.predictAbsorbs) and filledCalc(f, u) or nil
    if f.predictHeals then heals = UF.Heals(f, u, calc) end
    if f.predictAbsorbs then absorbs, over = UF.Absorbs(f, u, calc) end
    if type(max) == "nil" then max = UnitHealthMax(u) end
    UF.SetPrediction(f, max, heals, absorbs)
    local o = f.overshield
    if o then
        if f.predictAbsorbs and f.overshieldOn ~= false and type(over) ~= "nil" then
            o:SetMinMaxValues(0, max)
            o:SetValue(amount(UnitGetTotalAbsorbs, u))
            if not pcall(o.SetAlphaFromBoolean, o, over, 1, 0) then o:SetAlpha(0) end
        else
            o:SetAlpha(0)
        end
    end
end

-- A tile's heals and absorbs, read once per frame. A heal landing sends its
-- health and prediction events together, and 40 tiles get hundreds per second.
-- Other frames read immediately, and so does a new unit (UpdateHealth's
-- instant). max: same as UpdatePrediction's.
local predictDue, predictArmed = {}, false
local function flushPrediction()
    predictArmed = false
    for f in pairs(predictDue) do
        predictDue[f] = nil
        -- The header can remove the member from a tile before this read (a
        -- release, a roster shuffle), leaving no unit to read. A new one redraws
        -- the whole tile.
        if UnitExists(f.unitToken) then DUI.SafeCall(UF.UpdatePrediction, f) end
    end
end
function UF.PredictSoon(f, max)
    if not (f.spec and f.spec.group) then return UF.UpdatePrediction(f, max) end
    predictDue[f] = true
    if predictArmed then return end
    predictArmed = true
    C_Timer.After(0, flushPrediction)
end

-- Turns the aggro pulse on (true, or a secret "is tanking" flag the client
-- turns into shown or hidden) or off. Motion off keeps the band still.
function UF.Pulse(p, on)
    local secret = type(on) ~= "nil" and issecretvalue and issecretvalue(on)
    if type(on) == "nil" or (not secret and not on) or not DUI.Motion.On() then
        p.pulseAnim:Stop()
        p.pulseHold:Hide()
        p.haloAnim:Stop()
        p.halo:Hide()
        return
    end
    -- The halo's alpha belongs to its animation, so a secret answer can't gate
    -- it. In that case only the band's light pulses.
    if secret then
        p.haloAnim:Stop()
        p.halo:Hide()
    else
        local red = UF.THREAT_COLORS.aggro
        p.halo:SetVertexColor(red[1], red[2], red[3], 1)
        p.halo:Show()
    end
    local red = UF.THREAT_COLORS.aggro
    local r, g, b = math.min(1, red[1] + 0.3), math.min(1, red[2] + 0.3), math.min(1, red[3] + 0.3)
    p.pulse:SetVertexColor(r, g, b, 1)
    p.pulseEye:SetShown(p.elite:IsShown())
    p.pulseHold:Show()
    if secret then p.pulseHold:SetAlphaFromBoolean(on, 1, 0) else p.pulseHold:SetAlpha(1) end
    if not p.pulseAnim:IsPlaying() then
        p.pulseAnim:Play()
        if not secret then p.haloAnim:Play() end
    elseif not secret and not p.haloAnim:IsPlaying() then
        p.pulseAnim:Stop()   -- start both together, in step
        p.pulseAnim:Play()
        p.haloAnim:Play()
    end
end

-- The red ring filling (on) or unwinding (off) from wherever it is. snap (or
-- Motion off) lands immediately. Once full, the plain red band takes over.
-- Unwinding, the band goes at the start and the wipe removes the red. While a
-- fill runs, any band shown before it (orange) stays underneath.
function UF.RingFill(f, on, snap)
    local p = f.portrait
    local goal = on and 1 or 0
    if p.fillGoal == goal and (p.fillAt == goal or not snap) then
        if p.fillAt == 1 then
            local red = UF.THREAT_COLORS.aggro   -- the color may have changed
            p.threatBand:SetVertexColor(red[1], red[2], red[3], 1)
            UF.Pulse(p, true)
        end
        return
    end
    p.fillGoal = goal
    if not on then p.threatBand:Hide(); UF.Pulse(p, nil) end
    local from = p.fillAt
    DUI.Motion.Tween(p, from, goal, snap and 0 or UF.RING_FILL_TIME * math.abs(goal - from), function(v)
        p.fillAt = v
        -- The head fades over the last 15% of the way.
        drawFill(p, v, math.min(1, math.abs(goal - v) / 0.15))
    end, function()
        drawFill(p, nil)
        if goal == 1 then
            local red = UF.THREAT_COLORS.aggro
            p.threatBand:SetVertexColor(red[1], red[2], red[3], 1)
            p.threatBand:SetAlpha(1)
            p.threatBand:Show()
            UF.Pulse(p, true)
        end
    end)
end

-- level is "aggro" or nil. flag (used instead) is a secret "is tanking"
-- boolean, which the client's setters turn into aggro or nothing.
function UF.ApplyThreat(f, level, flag)
    local p = f.portrait
    local ring = p and p:IsShown()
    local red = UF.THREAT_COLORS.aggro
    if not f.showThreat then level, flag = nil, nil end
    local c = level and UF.THREAT_COLORS[level]
    if p then
        -- Plain red fills around the ring on the target, focus and you. A swap,
        -- a sample, orange and the secret path (Lua can't see what the client
        -- picks) land at once.
        local fill = ring and level == "aggro" and type(flag) == "nil"
        local calm = f.threatFresh or f.test or not (f.spec.threat or f.spec.combat)
        UF.RingFill(f, fill, calm or (not fill and (c or type(flag) ~= "nil" or not ring)))
        -- The same bright band over either ring, so the red is equally punchy.
        if fill then
            -- The fill controls the band's visibility (UF.RingFill).
        elseif type(flag) ~= "nil" and ring then
            p.threatBand:SetVertexColor(red[1], red[2], red[3], 1)
            p.threatBand:Show()
            p.threatBand:SetAlphaFromBoolean(flag, 1, 0)
            UF.Pulse(p, flag)
        elseif c and ring then
            p.threatBand:SetVertexColor(c[1], c[2], c[3], 1)
            p.threatBand:SetAlpha(1)
            p.threatBand:Show()
            UF.Pulse(p, level == "aggro")
        else
            p.threatBand:Hide()
            UF.Pulse(p, nil)
        end
        -- An elite's dragon keeps its color and its eyes catch fire (UF.PaintElite).
        f.threatNow = (c and ring) and c or nil
        f.threatFlag = ring and flag or nil
        UF.PaintElite(f)
    end
    -- No portrait: the name tab's border while it shows, else the frame's own
    -- (tiles, party buttons without a tab, and Ribbon, whose row has none).
    local tabOn = f.tab and f.tab:IsShown() and not f.ribbon or false
    local s = (tabOn and Style.GetShell(f.tab))
        or ((f.spec.threatOnFrame or f.ribbon or (f.spec.group and not tabOn)) and Style.GetShell(f))
        or nil
    -- A style change can move it, so reset the shell it left.
    if f.threatShell and f.threatShell ~= s then
        if f.threatSecret then Style.PaintShellColors(f.threatShell) end
        Style.SetShellColors(f.threatShell, nil, nil)
        f.threatSecret = nil
    end
    f.threatShell = s
    if not s then return end
    local k = UF.THREAT_BAND_DIM
    if type(flag) ~= "nil" and not ring then
        Style.SetShellColors(s, nil, nil)
        Style.ShellColorsFromBoolean(s, flag, red, { red[1] * k, red[2] * k, red[3] * k })
        f.threatSecret = true
        return
    end
    -- Colors the client picked stay until the shell is painted again.
    if f.threatSecret then
        f.threatSecret = nil
        Style.PaintShellColors(s)
    end
    if c and not ring then
        f.threatBand = f.threatBand or {}
        local band = f.threatBand
        band[1], band[2], band[3] = c[1] * k, c[2] * k, c[3] * k
        Style.SetShellColors(s, c, band)
    else
        Style.SetShellColors(s, nil, nil)
    end
end

local function plainThreat(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, tanking, status, scaled = pcall(fn, ...)
    if not ok then return nil end
    return tanking, status, scaled
end

-- The dragon: an elite's gold or silver (its rank at a glance, whatever the
-- ring's color), or your own (eliteColor "own") in your chosen color
-- (UF.DRAGON_COLORS). Aggro never recolors it, its eyes catch fire instead (a
-- secret "is tanking" lights them through the client).
function UF.PaintElite(f)
    local p = f.portrait
    local rc = p and p.eliteColor
    if not rc then return end
    for _, t in ipairs({ p.eye, p.eyeCore }) do
        if not p.elite:IsShown() then
            t:Hide()
        elseif f.threatNow then
            t:SetAlpha(1)
            t:Show()
        elseif type(f.threatFlag) ~= "nil" then
            t:Show()
            t:SetAlphaFromBoolean(f.threatFlag, 1, 0)
        else
            t:Hide()
        end
    end
    if not p.elite:IsShown() then return end
    if rc ~= "own" then
        p.elite:SetVertexColor(rc[1], rc[2], rc[3], 1)
        return
    end
    local pick = UF.DRAGON_COLORS[f.dragonColor] and f.dragonColor or "class"
    local metal = UF.ELITE_RING_COLORS[pick]
    if metal then
        p.elite:SetVertexColor(metal[1], metal[2], metal[3], 1)
        return
    end
    if pick == "accent" then
        local a, b = Style.AccentPair()
        if a then
            p.elite:SetVertexColor(1, 1, 1, 1)
            p.elite:SetGradient("VERTICAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
        else
            p.elite:SetVertexColor(Style.Accent())
        end
        return
    end
    local _, lo, hi, sr, sg, sb = ringColors(f, "class")
    if type(sr) ~= "nil" then
        p.elite:SetVertexColor(sr, sg, sb, 1)
    elseif lo then
        p.elite:SetVertexColor(1, 1, 1, 1)
        p.elite:SetGradient("VERTICAL", lo, hi)   -- last, since a plain color clears it
    else
        local g = UF.RING_COLOR
        p.elite:SetVertexColor(g[1], g[2], g[3], 1)
    end
end

-- Your own frame's dragon (player.portraitDragon): no rank, your chosen color.
function UF.ApplyDragon(f)
    local p = f.portrait
    if f.ownDragon then
        p.elite:Show()
        p.eliteColor = "own"
        UF.PaintElite(f)
    elseif p.eliteColor == "own" then
        p.elite:Hide()
        p.eye:Hide()
        p.eyeCore:Hide()
        p.eliteColor = nil
    end
end

function UF.UpdateThreat(f)
    if f.test then return end
    if f.spec.groupThreat then
        -- A party member: red while anything is attacking them.
        local ok, status = pcall(UnitThreatSituation, f.unitToken)
        if not ok or isSecret(status) then status = nil end
        UF.ApplyThreat(f, (status == 2 or status == 3) and "aggro" or nil)
        return
    end
    if not f.spec.threat then return end
    -- The tag and the orange step only in a group or with a pet. Alone, aggro is always on you.
    local grouped = DUI.Threat.Shared()
    local tanking, status, scaled = plainThreat(UnitDetailedThreatSituation, "player", f.unitToken)
    if isSecret(status) or isSecret(tanking) then
    -- A boss: the numbers are secret, but the state can stay plain.
        local level = DUI.Threat.Level("player", f.unitToken)
        if level == "aggro" or (level == "warn" and grouped) then
            UF.ApplyThreat(f, level)
        elseif isSecret(tanking) and level == nil then
            -- Only the "is tanking" answer is usable, straight into the setters.
            UF.ApplyThreat(f, nil, tanking)
        else
            UF.ApplyThreat(f, nil)
        end
        UF.ShowThreatTag(f, grouped and scaled or nil)
        return
    end
    local level = (status == 2 or status == 3) and "aggro" or nil
    if not level and grouped and type(status) == "number" then
        if status == 1 or (type(scaled) == "number" and not isSecret(scaled) and scaled >= DUI.Threat.WARN_PCT) then
            level = "warn"
        end
    end
    UF.ApplyThreat(f, level)
    UF.ShowThreatTag(f, grouped and scaled or nil, level)
end

function UF.CreateStatus(f)
    local st = CreateFrame("Frame", nil, f)
    st:SetAllPoints(f)
    st:SetFrameLevel(f.portrait:GetFrameLevel() + 6)
    st.icons = {}
    for key, s in pairs(UF.STATUS) do
        local t = st:CreateTexture(nil, "ARTWORK")
        t:SetTexture(DUI.MEDIA .. s.file)
        if s.color then t:SetVertexColor(s.color[1], s.color[2], s.color[3], 1) end
        t:Hide()
        st.icons[key] = t
    end
    local m = UF.LEVEL_RING
    st.icons.level:SetVertexColor(m[1], m[2], m[3], 1)
    local n = UF.PVP_NEUTRAL
    st.icons.pvp:SetVertexColor(n[1], n[2], n[3], 1)
    -- Units too high to show a level get a skull in the badge instead.
    st.skull = st:CreateTexture(nil, "OVERLAY")
    st.skull:SetTexture(DUI.MEDIA .. "status-skull.png")
    st.skull:SetPoint("CENTER", st.icons.level, "CENTER", 0, 0)
    st.skull:Hide()
    st.levelText = Style.Text(st, 10, "CENTER", UF.MediaOf(f.spec).fonts.name)
    -- The font's digits carry extra space on their right and sit high in the
    -- line, so the box is nudged to center the glyphs themselves.
    st.levelText:SetPoint("CENTER", st.icons.level, "CENTER", UF.LEVEL_NUDGE[1], UF.LEVEL_NUDGE[2])
    st.levelText:Hide()
    -- Role icons only where spec.role asks for them (party frames). Uses the
    -- badge sheet (UF.ROLE_ICON_TEXTURE), not one of the recolored status
    -- icons, and isn't sized by UF.STATUS like the rest (UF.LayoutStatus sizes
    -- it separately).
    if f.spec.role then
        local t = st:CreateTexture(nil, "ARTWORK")
        t:SetTexture(UF.ROLE_ICON_TEXTURE)
        t:Hide()
        st.icons.role = t
    end
    f.status = st
end

-- With a portrait: crown on top, Zzz on the outer shoulder, PvP at the outer
-- hip (clear of an attached cast bar and swing timers), level at the foot.
-- Without: crown and Zzz above the name tab, the PvP flag beside the tab, level
-- at the frame's outer bottom corner.
function UF.LayoutStatus(f, cfg)
    local st, p = f.status, f.portrait
    local outerRight = f.spec.slant == "left"
    local out = outerRight and 1 or -1
    local icons = st.icons
    local scale = f.iconScale or {}
    for _, t in pairs(icons) do t:ClearAllPoints() end
    -- The crown and role icon at home are nudged from there (leaderX/Y,
    -- roleX/Y), and sized by Corner crown / Role icon size once picked.
    local ln, rn = f.leaderNudge or UF.NO_NUDGE, f.roleNudge or UF.NO_NUDGE
    -- Icons kept on the frame while the portrait is on its own sit as if there
    -- were no portrait.
    local onRing = p:IsShown() and not f.iconsStay
    if onRing then
        local R = p:GetWidth() / 2
        for key, t in pairs(icons) do
            if key ~= "role" then
                local z = R * UF.STATUS[key].size * (scale[key] or 1)
                t:SetSize(z, z)
            end
        end
        icons.leader:SetPoint("CENTER", p, "CENTER", ln.x, R * 0.98 + ln.y)
        icons.rest:SetPoint("CENTER", p, "CENTER", out * R * 0.82, R * 0.82)
        icons.pvp:SetPoint("CENTER", p, "CENTER", out * R * 0.82, -R * 0.82)
        icons.level:SetPoint("CENTER", p, "CENTER", 0, -R * 0.9)
        Style.SetTextSize(st.levelText, math.max(8, math.floor(R * 0.38 + 0.5)))
        if icons.role then
            local z = f.rolePicked or R * UF.ROLE_SIZE
            icons.role:SetSize(z, z)
            -- The inner shoulder: rest's spot, mirrored to the other side.
            icons.role:SetPoint("CENTER", p, "CENTER", -out * R * 0.82 + rn.x, R * 0.82 + rn.y)
        end
    else
        -- Crown and Zzz at name text size. The level badge as big as it would
        -- be on a portrait of this frame.
        local s = f.tabHeight or UF.TAB_HEIGHT
        local sl, sr, sp = s * 0.9 * (scale.leader or 1), s * 0.9 * (scale.rest or 1), s * 1.15 * (scale.pvp or 1)
        icons.leader:SetSize(sl, sl)
        icons.rest:SetSize(sr, sr)
        icons.pvp:SetSize(sp, sp)
        local R = Pixel.Snap(f, f:GetHeight() * UF.PORTRAIT_SIZE * (f.portraitScale or 1) / 2)
        icons.level:SetSize(R * UF.STATUS.level.size, R * UF.STATUS.level.size)
        local outer = outerRight and "RIGHT" or "LEFT"
        local inner = outerRight and "LEFT" or "RIGHT"
        icons.leader:SetPoint("BOTTOM", f.tab, "TOP", ln.x, -3 + ln.y)
        icons.rest:SetPoint("BOTTOM" .. outer, f.tab, "TOP" .. outer, 0, -2)
        -- The PvP flag beside the name tab, level with it, on its outer side.
        icons.pvp:SetPoint(inner, f.tab, outer, (outerRight and 1 or -1) * 3, 0)
        icons.level:SetPoint("CENTER", f, "BOTTOM" .. outer, 0, 0)
        Style.SetTextSize(st.levelText, math.max(8, math.floor(R * 0.38 + 0.5)))
        if icons.role then
            local z = f.rolePicked or s * 0.9
            icons.role:SetSize(z, z)
            -- Rest's spot, mirrored to the tab's inner side.
            icons.role:SetPoint("BOTTOM" .. inner, f.tab, "TOP" .. inner, rn.x, -2 + rn.y)
        end
    end
    -- Moved to its own spot (Design mode, levelPos): the badge goes with its
    -- size and digits.
    if f.leaderPicked then
        local z = f.leaderPicked * (scale.leader or 1)
        icons.leader:SetSize(z, z)
    end
    if f.levelSpot then
        local at = ns.Spots.Layout(f.levelSpot, "center", ns.AuraGroups.Box(f, cfg), f.levelNudge)
        icons.level:ClearAllPoints()
        icons.level:SetPoint(at.point, f, at.relPoint, at.x, at.y)
    end
    local nudge = onRing and UF.LEVEL_NUDGE or UF.LEVEL_NUDGE_BARE
    st.levelText:ClearAllPoints()
    st.levelText:SetPoint("CENTER", icons.level, "CENTER", nudge[1], nudge[2])
    local b = icons.level:GetWidth() * UF.SKULL_SIZE
    st.skull:SetSize(b, b)
end

local function plainFlag(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not isSecret(v) and v == true
end

-- A call's plain first return, or nil on errors or a secret answer.
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or isSecret(v) then return nil end
    return v
end

-- sample: a test mode unit { level, leader, pvp } instead of the real one.
-- A status icon appearing or disappearing eases (NORMAL) when the same unit's
-- state changed (animate: resting, a new leader, the PvP flag), and changes
-- instantly on a unit swap, a setting or a sample.
local function showIcon(tex, on, animate)
    DUI.Motion.AlphaTo(tex, on and 1 or 0, animate and DUI.Motion.NORMAL or 0, true)
end

-- animate: a state change on the same unit (Units.lua's status pass,
-- UNIT_LEVEL). Icons ease and a level gained bumps the badge.
function UF.UpdateStatus(f, sample, animate)
    local st = f.status
    if not st then return end
    -- Icons in the corners (UF.UpdateLeader, UF.UpdateRole), so none on the set.
    if f.cornerMode then
        for _, t in pairs(st.icons) do t:Hide() end
        st.skull:Hide()
        st.levelText:Hide()
        return
    end
    local u = f.unitToken
    local leader, resting, pvp, faction
    if sample then
        leader = sample.leader == true
        pvp = sample.pvp == true
    else
        leader = plainFlag(UnitIsGroupLeader, u)
        resting = u == "player" and plainFlag(IsResting)
        pvp = plainFlag(UnitIsPVP, u)
        faction = pvp and select(1, plain(UnitFactionGroup, u))
    end
    -- When moved to a spot, the crown is the corner one (UF.UpdateLeader).
    showIcon(st.icons.leader, f.showLeader and leader and not f.leaderSpot
        and not (f.hideLeaderFight and UF.fighting), animate)
    showIcon(st.icons.rest, f.showResting and resting == true, animate)
    showIcon(st.icons.pvp, f.showPvP and pvp, animate)
    if f.showPvP and pvp then
        local c = (faction and UF.PVP_COLORS[faction]) or UF.PVP_NEUTRAL
        st.icons.pvp:SetVertexColor(c[1], c[2], c[3], 1)
    end
    -- Level: yours in white, anyone else's by how hard they'd be for you.
    local level
    -- An empty group slot has no unit yet, so no level.
    if sample then level = sample.level elseif u then level = UnitLevel(u) end
    local show = f.showLevel and type(level) ~= "nil"
    st.icons.level:SetShown(show)
    local skull = show and not isSecret(level) and level < 1
    st.skull:SetShown(skull)
    st.levelText:SetShown(show and not skull)
    if not show or skull then return end
    local c = UF.LEVEL_SELF_COLOR
    if isSecret(level) then
        st.shownLevel = nil
        st.levelText:SetFormattedText("%d", level)
    else
        -- A level gained: the badge and its number bump (only for the same
        -- unit, a swap passes no animate).
        if animate and type(st.shownLevel) == "number" and level > st.shownLevel then
            DUI.Motion.Bump(st.levelText, UF.LEVEL_UP_BUMP, DUI.Motion.SLOW)
            DUI.Motion.Bump(st.icons.level, UF.LEVEL_UP_BUMP, DUI.Motion.SLOW)
        end
        st.shownLevel = level
        st.levelText:SetText(level)
        if u ~= "player" then
            -- A sample has no unit, just its level.
            local dc = DUI.LevelColor(not sample and u or nil, level)
            if dc then c = { Style.Lighten(dc.r, dc.g, dc.b, UF.LEVEL_LIFT) } end
        end
    end
    st.levelText:SetTextColor(c[1], c[2], c[3])
end

-- The corner crown (frames without a status set, like raid tiles). animate:
-- the same unit's crown changing (a new leader, combat starting with
-- hideLeaderFight), so it eases.
function UF.UpdateLeader(f, sample, animate)
    if not f.leaderIcon then return end
    -- A frame with a status set shows its crown there, unless it sits at a
    -- spot (corner mode, or moved, see UF.IconSpot).
    local leader
    if sample then leader = sample.leader == true else leader = plainFlag(UnitIsGroupLeader, f.unitToken) end
    local hide = f.hideLeaderFight and UF.fighting
    if not f.leaderSpot then
        f.leaderIcon:Hide()
        -- Its crown at home also hides in combat (Show leader crown in combat).
        if f.status and f.status.icons.leader then
            showIcon(f.status.icons.leader, f.showLeader ~= false and leader and not hide, animate)
        end
        return
    end
    showIcon(f.leaderIcon, f.showLeader ~= false and leader and not hide, animate)
end

-- A ready check answer, from the check's start until READY_HOLD seconds after
-- it ends (UF.readyCheck = "running" | "finished" | nil, Units.lua). Once it's
-- over, no answer counts as not ready (the game's rule). The icon fades in,
-- bumps when the answer changes, and eases away. A sample shows instantly
-- unless animate is set (the leader drawer's practice check).
function UF.UpdateReady(f, sample, animate)
    local icon = f.readyIcon
    if not icon then return end
    local status
    if sample then
        status = sample.ready
    elseif UF.readyCheck then
        status = plain(GetReadyCheckStatus, f.unitToken)
        if status == "waiting" and UF.readyCheck == "finished" then status = "notready" end
    end
    local look = f.showReady ~= false and type(status) == "string" and UF.READY[status]
    if not look then
        if f.readyStatus and icon:IsShown() and (animate or not sample) and DUI.Motion.On() then
            f.readyStatus = nil
            -- Its own alpha as last set. GetAlpha reads as secret on a tile the
            -- range fade dims by a secret answer.
            DUI.Motion.Tween(icon, f.readyAlpha or 1, 0, DUI.Motion.NORMAL, function(a) f.readyAlpha = a; icon:SetAlpha(a) end,
                function() if not f.readyStatus then icon:Hide() end end)
        else
            f.readyStatus = nil
            icon:Hide()
        end
        return
    end
    if f.readyStatus == status and icon:IsShown() then return end
    local fresh = not icon:IsShown() or not f.readyStatus
    -- Answering ready: the tile shines once (Moments.lua).
    if status == "ready" and f.readyStatus ~= "ready" and (animate or not sample) and not UF.readyRipple then ns.Moments.Ready(f) end
    f.readyStatus = status
    icon:SetTexture(DUI.MEDIA .. look.file)
    local c = Style.INK[look.ink]
    icon:SetVertexColor(c[1], c[2], c[3], 1)
    icon:Show()
    if (sample and not animate) or not DUI.Motion.On() then
        f.readyAlpha = 1
        icon:SetAlpha(1)
    elseif fresh then
        DUI.Motion.Tween(icon, 0, 1, DUI.Motion.FAST, function(a) f.readyAlpha = a; icon:SetAlpha(a) end)
    else
        f.readyAlpha = 1
        icon:SetAlpha(1)
        DUI.Motion.Bump(icon, 1.3)
    end
end

-- Tank, healer or damage, from the role the member picked. Unknown or "NONE"
-- shows nothing. Uses f.roleIcon (tiles) or f.status.icons.role (party frames),
-- whichever this frame has.
function UF.UpdateRole(f, sample)
    local icon
    local home = f.status and f.status.icons.role
    if home and not f.roleSpot then
        icon = home
        if f.roleIcon then f.roleIcon:Hide() end
    else
        icon = f.roleIcon or home
        if home and icon ~= home then home:Hide() end
    end
    if not icon then return end
    local role
    if sample then
        role = sample.role
    else
        role = plain(UnitGroupRolesAssigned, f.unitToken)
    end
    local hidden = (f.roleHideDamage and role == "DAMAGER") or (f.roleHideFight and UF.fighting)
    local c = f.showRole ~= false and not hidden and type(role) == "string" and UF.ROLE_COORDS[role]
    if c then icon:SetTexCoord(c[1], c[2], c[3], c[4]) end
    icon:SetShown(c and true or false)
end

-- Your own frame goes red while you're in combat, the way a target's does
-- while it's on you.
function UF.UpdateCombat(f)
    if not f.spec.combat or f.test then return end
    local ok, fighting = pcall(UnitAffectingCombat, f.unitToken)
    if not ok or isSecret(fighting) then fighting = InCombatLockdown() end
    UF.ApplyThreat(f, fighting == true and "aggro" or nil)
end

-- Dead, ghost or offline, or nil. Each flag may be secret, and a secret one
-- can't be tested, so the frame then just shows the unit as it is.
local function flag(fn, u)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, u)
    if not ok or isSecret(v) then return false end
    return v == true
end

UF.STATE_TEXT = { offline = DUI.L["OFFLINE"], ghost = DUI.L["GHOST"], dead = DUI.L["DEAD"] }

function UF.UnitState(u)
    local isPlayer = UnitIsPlayer(u)
    local player = not isSecret(isPlayer) and isPlayer == true
    -- Only players go offline. The call means nothing for NPCs.
    if player then
        local on = UnitIsConnected(u)
        if not isSecret(on) and on == false then return "offline" end
    end
    if flag(UnitIsGhost, u) then return "ghost" end
    if flag(UnitIsDead, u) then return "dead" end
    return nil
end

function UF.UpdateHealth(f, instant)
    local u = f.unitToken
    -- A new unit (a swap): the previous one's death fade must not carry over.
    if instant and f.moments then ns.Moments.Still(f) end
    local max = UnitHealthMax(u)
    Style.SetBarRange(f.health, 0, max)
    -- Arriving (Arrive.lua): the fill keeps growing whatever comes in.
    if f.arriving and GetTime() < f.arriving then Style.GlideBar(f.health, UnitHealth(u)) else Style.SetBarValue(f.health, UnitHealth(u), instant) end
    UF.ApplyGradient(f)
    -- A change of state recolors the bar (gray while dead or away).
    if instant then UF.UpdatePrediction(f, max) else UF.PredictSoon(f, max) end
    if f.dotVeil then UF.UpdateDots(f) end
    local state = UF.UnitState(u)
    -- Your target or focus dying before your eyes (not a swap to a corpse).
    local died = state == "dead" and not f.state and not instant and (u == "target" or u == "focus")
    if state ~= f.state then
        f.state = state
        UF.UpdateIdentity(f)
    end
    ns.Texts.Update(f, "health")
    -- DEAD fades in with the breath. With motion off (no breath) it just shows.
    local fading = died and ns.Moments.Breath(f)
    if not f.percentText:IsShown() then return end
    if state then
        if not fading and not ns.Moments.Breathing(f) then f.percentText:SetAlpha(1) end
        f.percentText:SetText(UF.STATE_TEXT[state])
    else
        -- The client does the formatting (4.1K, 62), so a secret value is fine.
        UF.WriteHealth(f.percentText, f.healthFormat, u, f.percentSign, f.hideFullHealth)
    end
end

-- H: the height the angle is measured over (the frame's, or the free power
-- bar's in PowerBar.lua, with free set).
-- endPad (optional): how far in from either end the power text sits (Ribbon's
-- line, far down the frame's angle).
function UF.LayoutPowerExtras(f, cfg, text, side, cut, H, free, endPad)
    if not f.power then return end
    H = H or f:GetHeight()
    local ph = f.power:GetHeight()
    -- Things riding on the bar are parented to the frame, so they don't leave with it.
    local on = UF.ShowsPower(cfg)
    -- Power text: inside the power bar, clear of its angled end.
    local inner = f.spec.slant == "left" and "LEFT" or "RIGHT"
    local pad = endPad or ((side and cut * (ph + Pixel.Px(f, 2)) / H or 0) + 4)
    local moodEnd = (f.moodPad and f.moodSide == (inner == "LEFT" and "left" or "right")) and f.moodPad or 0
    pad = pad + moodEnd
    -- Under the big health number, it lines up with it.
    if not free and cfg.bigNumber == true and cfg.showPercent == true then
        pad = (cut or 0) + UF.BIG_NUMBER_INSET + moodEnd
    end
    local pos = cfg.powerTextPos or "inner"
    local nx, ny = cfg.powerTextX, cfg.powerTextY
    f.powerText:ClearAllPoints()
    if pos == "center" then
        UF.PlaceText(f.powerText, "CENTER", f.power, "CENTER", 0, Pixel.Px(f, 1), nx, ny)
        f.powerText:SetJustifyH("CENTER")
    elseif pos == "outer" then
        local outer = inner == "LEFT" and "RIGHT" or "LEFT"
        local opad = endPad and 4 or ((side and cut * (ph + Pixel.Px(f, 2)) / H or 0) + 4)
        if f.moodPad and f.moodSide == (outer == "LEFT" and "left" or "right") then opad = opad + f.moodPad end
        UF.PlaceText(f.powerText, outer, f.power, outer, (outer == "LEFT" and 1 or -1) * opad, Pixel.Px(f, 1), nx, ny)
        f.powerText:SetJustifyH(outer)
    else
        UF.PlaceText(f.powerText, inner, f.power, inner, (inner == "LEFT" and 1 or -1) * pad, Pixel.Px(f, 1), nx, ny)
        f.powerText:SetJustifyH(inner)
    end
    local psize = text.power
    if type(psize) ~= "number" or psize <= 0 then
        psize = math.min(text.percent, math.floor(cfg.powerHeight * 0.85 + 0.5))
    end
    Style.SetTextSize(f.powerText, psize)
    f.powerText:SetShown(on and cfg.showPowerText == true)
    -- Druid mana: along the bottom of the power bar, a third of its height.
    if f.altMana then
        local h = math.max(2, Pixel.Snap(f, cfg.powerHeight * 0.3))
        f.altMana:ClearAllPoints()
        f.altMana:SetPoint("BOTTOMLEFT", f.power, "BOTTOMLEFT", 0, 0)
        f.altMana:SetPoint("BOTTOMRIGHT", f.power, "BOTTOMRIGHT", 0, 0)
        f.altMana:SetHeight(h)
        Style.AngleFill(f.altMana, not f.flipped and side or nil, side and cut * h / H or 0)
        Style.SetBarColor(f.altMana, Style.PowerColor("MANA"))
        f.druidMana = on and cfg.druidMana ~= false
    end
    if f.cost then
        UF.LayoutCost(f, side, side and cut * ph / H or 0, cfg)
        if not on then
            f.costPreview = false
            f.cost:Hide()
        end
    end
end

-- The spell cost shade over f.power (the player frame's and the personal
-- display's). side and cut are the power bar's angle. cfg is the frame's
-- costPreview, costColor and costAlpha.
function UF.LayoutCost(f, side, cut, cfg)
    local lead = f.growLeft == true and "LEFT" or "RIGHT"
    local fill = f.power:GetStatusBarTexture()
    f.cost:ClearAllPoints()
    -- Lead edge on the fill's lead edge, growing back over the fill.
    f.cost:SetPoint("TOP" .. lead, fill, "TOP" .. lead, 0, 0)
    f.cost:SetPoint("BOTTOM" .. lead, fill, "BOTTOM" .. lead, 0, 0)
    f.cost:SetWidth(f.power:GetWidth())
    f.cost:SetReverseFill(f.growLeft ~= true)
    -- Both ends of the band take the frame's angle, like the fill's own.
    local fillSide = not f.flipped and side or nil
    local dir = fillSide and (f.growLeft == true and "left" or "right") or nil
    local c = fillSide and cut or 0
    Style.AngleFill(f.cost, dir, c)
    Style.AngleTrail(f.cost, dir, c)
    local color = cfg.costColor or { 0, 0, 0 }
    f.cost:SetStatusBarColor(color[1], color[2], color[3], cfg.costAlpha or 0.45)
    f.costPreview = cfg.costPreview ~= false
    if not f.costPreview then f.cost:Hide() end
    ns.PowerBar.PlaceRegen(f)
end

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

function UF.UpdatePower(f, instant)
    ns.Texts.Update(f, "power")   -- a power text shows even with the bar off
    -- Power bar off (common on raid tiles): nothing to show, and every power
    -- event for every tile is skipped. The druid mana strip still needs it.
    if not f.power or (not f.power:IsShown() and not f.altMana) then return end
    local u = f.unitToken
    f.power:SetMinMaxValues(0, UnitPowerMax(u))
    UF.FeedPower(f, UnitPower(u), instant)
    local _, token = UnitPowerType(u)
    UF.PaintPower(f.power, token, u, f)
    if f.powerText:IsShown() then UF.WritePower(f.powerText, f.powerFormat, u, f.hideFullPower, f.powerPercentSign) end
    if f.altMana then
        -- Shown only while your power isn't mana (a form) and you have mana.
        local shown = f.druidMana and not isSecret(token) and token ~= "MANA" and token ~= nil
        if shown then
            local _, class = UnitClass(u)
            shown = class == "DRUID"
        end
        f.altMana:SetShown(shown and true or false)
        if shown then
            f.altMana:SetMinMaxValues(0, UnitPowerMax(u, MANA))
            Style.SetBarValue(f.altMana, UnitPower(u, MANA), instant)
        end
    end
end

-- A plain power change (UNIT_POWER_FREQUENT, every tile, hundreds per second in
-- a raid fight): only the value and its text update. The max, color and druid
-- strip visibility change with UNIT_MAXPOWER/UNIT_DISPLAYPOWER
-- (UF.UpdatePower), and a new unit runs UpdateAll.
function UF.UpdatePowerValue(f)
    ns.Texts.Update(f, "power")
    if not f.power or (not f.power:IsShown() and not f.altMana) then return end
    local u = f.unitToken
    UF.FeedPower(f, UnitPower(u))
    if f.powerText:IsShown() then UF.WritePower(f.powerText, f.powerFormat, u, f.hideFullPower, f.powerPercentSign) end
    if f.altMana and f.altMana:IsShown() then
        Style.SetBarValue(f.altMana, UnitPower(u, MANA))
    end
end

-- The part of the power a cast in progress, or a queued next-swing attack, will
-- spend: a shade over the end of the fill, from the spell's cost (see
-- UF.UpdateCost).
function UF.CreateCost(f, spec)
    f.costHolder, f.cost = UF.CostBar(f, f.power, spec.slant and f or nil)
    local h = CreateFrame("Frame", nil, f)
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }) do
        pcall(h.RegisterUnitEvent, h, e, "player")
    end
    pcall(h.RegisterEvent, h, "ACTIONBAR_UPDATE_STATE")
    h:SetScript("OnEvent", function(_, event, _, _, spellID)
        if f.test then return end
        if event == "UNIT_SPELLCAST_START" then
            f.costCast = spellID
        elseif event ~= "ACTIONBAR_UPDATE_STATE" then
            f.costCast = nil
        end
        -- Turned off, so don't ask the client (this fires often).
        if not f.costPreview then f.cost:Hide(); return end
        UF.UpdateCost(f, f.costCast or UF.QueuedSwingSpell())
    end)
    f.costEvents = h
end

-- The shade itself over power bar bar, owned by owner. A holder clips it so a
-- cost above your current power can't poke out. clip is the shell whose angle
-- it takes, if any. Returns holder, shade.
function UF.CostBar(owner, bar, clip)
    local holder = CreateFrame("Frame", nil, owner)
    holder:SetAllPoints(bar)
    holder:SetFrameLevel(bar:GetFrameLevel() + 1)
    if holder.SetClipsChildren then holder:SetClipsChildren(true) end
    local cost = Style.Bar(holder, "seamless", Style.BarSlot(bar))   -- the power bar's texture
    Style.BarBack(cost):Hide()
    cost:SetMinMaxValues(0, 1)
    cost:SetValue(0)
    cost:Hide()
    if clip then Style.Clip(clip, cost:GetStatusBarTexture(), "inner") end
    return holder, cost
end

-- The cost of spellID in the bar's power type, or nil. The amount may be
-- secret, so it's only ever passed to SetValue.
function UF.SpellCost(spellID, powerType)
    local api = C_Spell and C_Spell.GetSpellPowerCost
    if type(api) ~= "function" or type(spellID) == "nil" then return nil end
    local ok, costs = pcall(api, spellID)
    if not ok or type(costs) ~= "table" then return nil end
    for _, c in ipairs(costs) do
        if type(c) == "table" and not isSecret(c.type) and c.type == powerType then
            local aura, has = c.requiredAuraID, c.hasRequiredAura
            local needsAura = not isSecret(aura) and type(aura) == "number" and aura ~= 0
            if not (needsAura and not isSecret(has) and has ~= true) then return c.cost end
        end
    end
    return nil
end

-- The next-swing attack queued now (Heroic Strike, Cleave, Maul) as a spell ID,
-- or nil. The swing timer's single check (Swing.lua ST.Queued).
function UF.QueuedSwingSpell()
    local queued = ns.Swing and ns.Swing.Queued
    if type(queued) ~= "function" then return nil end
    return (queued())
end

function UF.UpdateCost(f, spellID)
    if not f.cost then return end
    if not f.costPreview then f.cost:Hide(); return end
    local cost = UF.SpellCost(spellID, (UnitPowerType("player")))
    if type(cost) == "nil" then f.cost:Hide(); return end
    f.cost:SetMinMaxValues(0, UnitPowerMax("player"))
    f.cost:SetValue(cost)
    f.cost:Show()
end

-- What a tile's look depends on from its flags: a number to compare, or nil
-- when an answer is secret (then it always repaints). Same as Plate.FlagSig.
function UF.FlagSig(u)
    local tapped, react = UnitIsTapDenied(u), UnitReaction(u, "player")
    if isSecret(tapped) or isSecret(react) then return nil end
    return (tapped == true and 100 or 0) + (type(react) == "number" and react or 0)
end

function UF.UpdateIdentity(f)
    local u = f.unitToken
    if f.spec and f.spec.group then f.flagSig = UF.FlagSig(u) end
    identityUnit, identityToken = type(u) == "string" and u or nil, nil
    local r, g, b = UF.UnitColor(u)
    -- A party pet in its owner's class color (PartyPets.lua).
    if f.ownerClass then r, g, b = Style.ClassColor(f.ownerClass) end
    if f.state then r, g, b = UF.StateColor(f.state) end
    UF.PaintHealth(f, r, g, b)
    UF.ApplyHiddenClass(f)
    UF.PaintRing(f)   -- a tapped or changed reaction changes its pair
    UF.PaintName(f, r, g, b)
    -- A group button reads its group's switch (your own button included).
    local element = f.spec and f.spec.group or nil
    local name = UF.NameText(f, UF.LimitName(DUI.UnitName(u, element), f.nameLimitLen))
    f.nameText:SetText(name)
    UF.ApplyCrest(f, UnitClassification(u))
    if f.tab then UF.SizeTab(f, name) elseif f.nameTag then UF.SizeNameTag(f, name) end
    ns.Texts.Update(f, "identity")
    identityUnit, identityToken = nil, nil
    UF.Painted(f)
end

-- UNIT_FLAGS and UNIT_FACTION fire for many things that don't affect a tile
-- (combat starting, sitting), for all 40, so a tile only repaints when tapped
-- or its reaction changed. Other frames always repaint (a mob being tagged).
function UF.FlagsChanged(f)
    if f.spec and f.spec.group then
        local sig = UF.FlagSig(f.unitToken)
        if type(sig) == "number" and sig == f.flagSig then return end
    end
    UF.UpdateIdentity(f)
end

-- A player outside the group whose class the client hides (enemies in a
-- battleground): its secret class id, else nil (also for samples and dead or
-- offline units).
local function hiddenClassID(f)
    if f.state or f.test or classOf(f.unitToken) then return nil end
    return DUI.Gradients.HiddenClassID(f.unitToken)
end

-- That player's class color as secret numbers, for text. Otherwise nil.
function UF.HiddenClassColor(f)
    if type(hiddenClassID(f)) == "nil" then return nil end
    return DUI.Gradients.HiddenClassColor(f.unitToken)
end

-- Its health bar: the class layers over the fill (DUI.Gradients, hidden
-- classes) in the class color modes, created the first time a frame needs them.
function UF.ApplyHiddenClass(f)
    local mode = UF.HealthMode(f)
    local id    -- no "and/or" here, that would truth-test the secret
    -- A plugin's fill takes no class layers over it.
    if (mode == "class" or mode == "classGradient") and not UF.Owned(f, "healthFill") then id = hiddenClassID(f) end
    if type(id) == "nil" then
        if f.classLayers then DUI.Gradients.PaintClassLayers(f.classLayers, nil, nil) end
        return
    end
    if not f.classLayers then
        f.classLayers = DUI.Gradients.ClassLayers(f.health, f.spec.slant and function(tex) Style.Clip(f, tex, "inner") end)
    end
    local flip = UF.MirrorGradient(f) and DUI.Gradients.Orientation() == "HORIZONTAL"
    DUI.Gradients.PaintClassLayers(f.classLayers, id, mode, flip)
end

-- c is a classification, possibly secret (then no crest).
function UF.ApplyCrest(f, c)
    if f.crest then
        local kind = not isSecret(c) and UF.CREST[c]
        f.crestShown = (kind and f.showClassification) and true or false
        if f.crestShown then
            local col = UF.CREST_COLORS[kind]
            f.crest.ring:SetVertexColor(col[1], col[2], col[3], 1)
            f.crest.emblem:SetVertexColor(col[1], col[2], col[3], 1)
            f.crest.glow:SetVertexColor(col[1], col[2], col[3], 0.8)
            f.tabEdge:SetVertexColor(col[1], col[2], col[3], 1)
        end
        -- With a portrait a dragon wraps the ring. The badge is only for frames
        -- without one, and goes with the tab.
        local p = f.portrait
        local onRing = (f.crestShown and p and p:IsShown()) and true or false
        if p then
            p.elite:SetShown(onRing)
            p.eliteColor = onRing and UF.ELITE_RING_COLORS[kind] or nil
            if not onRing then p.eye:Hide(); p.eyeCore:Hide() end
            UF.PaintElite(f)
        end
        f.crest:SetShown(f.crestShown and not onRing and f.tab:IsShown())
        if f.status then
            local m = f.crestShown and UF.ELITE_RING_COLORS[kind] or UF.LEVEL_RING
            f.status.icons.level:SetVertexColor(m[1], m[2], m[3], 1)
        end
        -- The tab's lit top edge. Ribbon's row has no shell to edge.
        f.tabEdge:SetShown(f.crestShown and not f.ribbon)
    end
end

-- A newly placed raid marker fades in FAST (it's for the fight). Its index is
-- always secret (SecretReturns), so only "none to one" can be detected, and a
-- marker replacing another swaps in place. Only from RAID_TARGET_UPDATE
-- (arrive). A unit swap snaps.
function UF.MarkerIn(tex)
    local M = DUI.Motion
    M.Tween(tex, 0, 1, M.FAST, function(a) tex:SetAlpha(a) end)
end

function UF.UpdateMarker(f, arrive)
    if not f.marker then return end
    -- A raid tile can be waiting for its unit.
    if type(f.unitToken) ~= "string" then f.marker:Hide() return end
    local i = GetRaidTargetIndex(f.unitToken)
    local shown = false
    if f.showMarker then
        if isSecret(i) then
            -- A secret can't be tested. Picking the cell fails if there's no marker.
            shown = pcall(f.marker.SetSpriteSheetCell, f.marker, i, UF.MARKER_ROWS, UF.MARKER_COLS)
        elseif type(i) == "number" then
            f.marker:SetSpriteSheetCell(i, UF.MARKER_ROWS, UF.MARKER_COLS)
            shown = true
        end
    end
    f.marker:SetShown(shown)
    if arrive and shown and not f.markerShown then UF.MarkerIn(f.marker) end
    if f.markerShown ~= shown then
        f.markerShown = shown
        if f.tab then UF.SizeTab(f) end
    end
end

-- Range fade: friendly units the game can range-check (group members) dim when
-- out of range. Anyone it can't check stays at full strength rather than
-- guessing. A secret answer goes straight to the client's boolean alpha setter.
UF.RANGE_INTERVAL = 0.2

-- Set from PLAYER_REGEN_DISABLED / ENABLED (Units.lua).
UF.fighting = false

-- The fade on top. The fade engine ("UnitFrames.<unit>", "UnitFrames.party",
-- "UnitFrames.raid") hands its alpha to UF.PaintFade, and the range fade
-- multiplies it (a secret range answer still goes to SetAlphaFromBoolean).
function UF.CombatAlpha(f)
    if f.test then return 1 end
    return type(f.fadeNow) == "number" and f.fadeNow or 1
end

-- While the fade engine eases (every frame, every tile) the range isn't asked
-- again. The alpha is reapplied with the answer the range ticker cached
-- (UF.UpdateRange, 5 times a second; a secret answer is cached as is).
local paintRange
function UF.PaintFade(f, a)
    f.fadeNow = a
    if f.rangeRead then paintRange(f) else UF.UpdateRange(f) end
end

-- "Only at full health" (player, pet): the faded look only at full health.
-- Health is secret here even out of combat, so the game decides through a curve
-- over the health fraction: hi below full (the frame's opacity, 1 if not
-- given) and a at full. One curve per step of a and hi.
UF.fullCurves = {}
function UF.FullHealthAlpha(u, a, hi)
    hi = type(hi) == "number" and hi or 1
    local lo, top = math.floor(a * 100 + 0.5), math.floor(hi * 100 + 0.5)
    local key = top * 1000 + lo
    local c = UF.fullCurves[key]
    if type(c) == "nil" then
        c = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local ok, made = pcall(C_CurveUtil.CreateCurve)
            if ok and made then
                if Enum and Enum.LuaCurveType and made.SetType then pcall(made.SetType, made, Enum.LuaCurveType.Linear) end
                made:AddPoint(0, top / 100)
                made:AddPoint(0.999, top / 100)
                made:AddPoint(1, lo / 100)
                c = made
            end
        end
        UF.fullCurves[key] = c
    end
    if c and UnitHealthPercent then
        local ok, v = pcall(UnitHealthPercent, u, true, c)
        if ok then return v end
    end
    -- No curves: plain numbers can be compared, a secret one stays shown.
    local hp, max = UnitHealth(u), UnitHealthMax(u)
    if isSecret(hp) or isSecret(max) then return hi end
    return hp >= max and a or hi
end

-- Sets a frame the range check leaves alone; m is the fade's alpha. The
-- full-health wait is only for the player and pet frames. A party or raid tile
-- on "player" fades by its group's settings.
local fullPaths = {}   -- unit -> { "<unit>.fade.fullHealth", "<unit>.fade" }
local function setFaded(f, m)
    local u = f.unitToken
    if not f.test and not f.group and ns.FADE_FULL_HEALTH[u] then
        local paths = fullPaths[u]
        if not paths then
            paths = { u .. ".fade.fullHealth", u .. ".fade" }
            fullPaths[u] = paths
        end
        if DUI:Get("UnitFrames", paths[1]) == true then
            local hi = DUI.Fade.Opacity("UnitFrames", paths[2])
            if m < hi and pcall(f.SetAlpha, f, UF.FullHealthAlpha(u, m, hi)) then return end
        end
    end
    f:SetAlpha(m)
end

-- Your party or raid, the units the game range-checks. Not you, and not your
-- pet, since the check reads pets as out of range even right beside you.
function UF.InGroup(u)
    if plain(UnitIsUnit, u, "player") == true or plain(UnitIsUnit, u, "pet") == true then return false end
    -- UnitInRaid returns the raid slot number.
    return plain(UnitInParty, u) == true or type(plain(UnitInRaid, u)) == "number"
end

-- The same answer, cached per frame between roster changes (UF.rosterGen,
-- incremented on GROUP_ROSTER_UPDATE in Units.lua). Who is on "party2" or
-- "raid17" only changes with the roster, and the range ticker asks for every
-- tile 5 times a second. Target, focus and target of target change without a
-- roster update, so they ask each time, as does an answer read while the game
-- hides the group (a secret UnitInParty/UnitInRaid under restrictions reads false).
UF.rosterGen = 0
local function rosterToken(u)   -- u: a plain unit token
    return u == "player" or u:find("^party%d+$") or u:find("^raid%d+$")
end
local function inGroupCached(f, u)
    if f.groupFor == u and f.groupGen == UF.rosterGen then return f.inGroup end
    local yes = UF.InGroup(u)
    if rosterToken(u) and (yes or not DUI.Restricted()) then
        f.groupFor, f.groupGen, f.inGroup = u, UF.rosterGen, yes
    else
        f.groupFor = nil
    end
    return yes
end

-- A healer's range is their heal's. The game's UnitInRange uses a fixed
-- distance a little short of 40 yd, so members you could still heal faded.
-- Best spell first. A class with none (or before it's learned) keeps UnitInRange.
UF.RANGE_SPELLS = {
    PRIEST  = { 2061, 2050 },   -- Flash Heal, Lesser Heal
    PALADIN = { 19750, 635 },   -- Flash of Light, Holy Light
    SHAMAN  = { 8004, 331 },    -- Lesser Healing Wave, Healing Wave
    DRUID   = { 8936, 5185 },   -- Regrowth, Healing Touch
}

-- Picks UF.rangeSpell from the spellbook (at login and on SPELLS_CHANGED).
function UF.ResolveRangeSpell()
    UF.rangeSpell = nil
    local list = UF.RANGE_SPELLS[select(2, UnitClass("player"))]
    if not (list and C_Spell and C_Spell.IsSpellInRange and C_SpellBook and C_SpellBook.IsSpellKnown) then return end
    for _, id in ipairs(list) do
        if C_SpellBook.IsSpellKnown(id) then
            UF.rangeSpell = id
            return
        end
    end
end

-- Reads the range and stores the answer on the frame. f.rangeRead is "none"
-- (no range check, just the fade), "unchecked" (the game couldn't tell, so
-- full), or "read" with the answer in f.rangeIn (possibly secret, never
-- compared here).
local function readRange(f)
    if not f.rangeFade or f.test then
        f.rangeRead = "none"
        return
    end
    local u = f.unitToken
    -- Only units the game really range-checks, i.e. your group. Anyone else
    -- (you, your pet, strangers, enemies) gives no usable answer.
    if type(u) ~= "string" or not inGroupCached(f, u) then
        f.rangeRead = "none"
        return
    end
    local inRange, checked
    if UF.rangeSpell then
        inRange = C_Spell.IsSpellInRange(UF.rangeSpell, u)
        -- nil means the check was invalid this time, so use the game's check.
        if not isSecret(inRange) and inRange == nil then inRange = nil else checked = true end
    end
    if not checked then inRange, checked = UnitInRange(u) end
    if not isSecret(checked) and checked ~= true then
        f.rangeRead, f.rangeIn = "unchecked", nil
        return
    end
    f.rangeRead, f.rangeIn = "read", inRange
end

-- The fade's alpha times the kept range answer.
function paintRange(f)
    local m = UF.CombatAlpha(f)
    local r = f.rangeRead
    -- A secret answer can't tell when it dims, so it's on for as long as it's asked.
    DUI.Fade.Whole(f, "range", r == "read" and f.rangeFade == true and not f.test)
    if r == "none" or not f.rangeFade or f.test then
        setFaded(f, m)
        return
    end
    if r == "unchecked" then
        f:SetAlpha(m)
        return
    end
    local inRange = f.rangeIn
    if isSecret(inRange) then
        if not (f.SetAlphaFromBoolean and pcall(f.SetAlphaFromBoolean, f, inRange, m, m * f.rangeAlpha)) then
            f:SetAlpha(m)
        end
        return
    end
    f:SetAlpha(m * (inRange == true and 1 or f.rangeAlpha))
end

function UF.UpdateRange(f)
    readRange(f)
    paintRange(f)
end

-- Draws the frame from f.test, a sample unit (test mode), instead of a real
-- one: { name, class | reaction, health, healthValue, power, powerToken,
-- classification, marker, portraitClass }.
function UF.ShowSample(f)
    local s = f.test
    local r, g, b
    if s.class then r, g, b = Style.ClassColor(s.class) else r, g, b = UF.ReactionColor(s.reaction) end
    f.state = nil
    UF.PaintHealth(f, r, g, b, s.health)
    UF.ApplyHiddenClass(f)
    Style.SetBarRange(f.health, 0, 100)
    Style.SetBarValue(f.health, s.health, true)
    UF.SetPrediction(f, 100, f.predictHeals and (s.heals or 0) or 0, f.predictAbsorbs and (s.absorbs or 0) or 0)
    UF.UpdateDots(f)
    if f.power then
        f.power:SetMinMaxValues(0, 100)
        Style.SetBarValue(f.power, s.power or 0, true)
        UF.PaintPower(f.power, s.powerToken or "MANA", f.unitToken, f)
        if f.powerText:IsShown() then
            UF.WriteSamplePower(f.powerText, f.powerFormat, s.power, s.powerValue, f.powerPercentSign, f.hideFullPower,
                s.powerToken)
        end
    end
    UF.PaintName(f, r, g, b)
    local name = UF.NameText(f, UF.LimitName(s.name, f.nameLimitLen))
    f.nameText:SetText(name)
    if f.percentText:IsShown() then
        UF.WriteSampleHealth(f.percentText, f.healthFormat, s.health, s.healthValue, f.percentSign, f.hideFullHealth)
    end
    if f.marker then
        local shown = f.showMarker and type(s.marker) == "number"
        if shown then f.marker:SetSpriteSheetCell(s.marker, UF.MARKER_ROWS, UF.MARKER_COLS) end
        f.marker:SetShown(shown)
        f.markerShown = shown
    end
    UF.ApplyCrest(f, s.classification)
    if f.tab then UF.SizeTab(f, name) elseif f.nameTag then UF.SizeNameTag(f, name) end
    UF.UpdatePortrait(f)
    UF.ApplyThreat(f, s.threat)
    UF.ShowThreatTag(f, s.threatPct, s.threat)
    UF.UpdateStatus(f, s)
    UF.UpdateLeader(f, s)
    UF.UpdateReady(f, s)
    UF.UpdateRole(f, s)
    ns.Texts.ShowSample(f, s)
    f:SetAlpha(1)
    UF.Painted(f)
end

-- instant snaps the bars instead of gliding (the unit itself changed).
function UF.UpdateAll(f, instant)
    if f.test then
        UF.ShowSample(f)
        return
    end
    if not UnitExists(f.unitToken) then return end
    UF.UpdateIdentity(f)
    UF.UpdateHealth(f, instant)
    UF.UpdatePower(f, instant)
    UF.UpdateMarker(f)
    UF.UpdatePortrait(f)
    UF.UpdateRange(f)
    -- A new unit (a target swap): the aggro ring lands at once with no fill.
    f.threatFresh = instant
    UF.UpdateThreat(f)
    UF.UpdateCombat(f)
    f.threatFresh = nil
    UF.UpdateStatus(f)
    UF.UpdateLeader(f)
    UF.UpdateReady(f)
    UF.UpdateRole(f)
end

local UNIT_EVENTS = {
    UNIT_HEALTH = UF.UpdateHealth,
    UNIT_MAXHEALTH = UF.UpdateHealth,
    -- Fires on every change. UNIT_POWER_UPDATE is a slower copy of it and isn't
    -- wired, since it doubled the work. This keeps the color, text and druid
    -- mana strip (which the OnUpdate poll below doesn't touch) as current as
    -- the fill. Only the value here; the max and color come with the two
    -- events after it.
    UNIT_POWER_FREQUENT = UF.UpdatePowerValue,
    UNIT_MAXPOWER = UF.UpdatePower,
    UNIT_DISPLAYPOWER = UF.UpdatePower,
    UNIT_NAME_UPDATE = UF.UpdateIdentity,
    UNIT_FACTION = UF.FlagsChanged,
    UNIT_FLAGS = UF.FlagsChanged,       -- tagging a mob changes its flags
    UNIT_CONNECTION = UF.UpdateHealth,  -- offline is part of the health state
    UNIT_CLASSIFICATION_CHANGED = UF.UpdateIdentity,
    UNIT_PORTRAIT_UPDATE = UF.UpdatePortrait,
    UNIT_HEAL_PREDICTION = UF.PredictSoon,
    UNIT_LEVEL = function(f)
        UF.UpdateStatus(f, nil, true)
        ns.Texts.Update(f, "identity")
    end,
    UNIT_ABSORB_AMOUNT_CHANGED = UF.PredictSoon,
    PLAYER_FLAGS_CHANGED = function(f) ns.Texts.Update(f, "flags") end,   -- AFK, DND (extra texts)
    UNIT_MODEL_CHANGED = UF.UpdatePortrait,
}

-- Events unknown to this client are skipped rather than breaking the frame.
function UF.RegisterUnitEvents(f)
    f:UnregisterAllEvents()
    if type(f.unitToken) ~= "string" then return end
    for event in pairs(UNIT_EVENTS) do pcall(f.RegisterUnitEvent, f, event, f.unitToken) end
end

-- On this client power doesn't wait for a tick to move. The game's own frames
-- read it fresh every frame, so it fills continuously instead of in steps.
-- This does the same: while the frame is shown, poll UnitPower and pass it
-- straight to the bar untouched (fine even if secret) through
-- Style.SetBarValue, so a jump (a spell cast, a big gain) still glides with
-- Smooth bars on. The max is left to UNIT_MAXPOWER, since setting it every
-- frame would cut the glide short.
-- At most UF.POWER_POLL times a second (the easing fills in between), and only
-- when the value moved. A secret value can't be compared, so it's passed on
-- every time.
-- Only your own power moves between the game's events. Everyone else's comes
-- with UNIT_POWER_FREQUENT (every frame and tile listens for it), so their poll
-- is a slow safety net (UF.POWER_POLL_OTHERS). 40 raid tiles at 20 a second
-- each was 800 bar writes a second in combat. Nothing is polled while the
-- power bar itself is hidden (Power bar off).
UF.POWER_POLL = 0.05
UF.POWER_POLL_OTHERS = 0.25
function UF.PollPower(f, dt)
    dt = dt or UF.POWER_POLL
    if f.glideTo then UF.StepGlide(f, dt) end
    f.powerWait = (f.powerWait or 0) - dt
    if f.powerWait > 0 then return end
    f.powerWait = f.unitToken == "player" and UF.POWER_POLL or UF.POWER_POLL_OTHERS
    UF.PollOnce(f)
end

function UF.PollOnce(f)
    if f.test or not f.power or not f:IsShown() or not f.power:IsShown() then return end
    local u = f.unitToken
    if type(u) ~= "string" or not UnitExists(u) then return end
    UF.FeedPower(f, UnitPower(u))
end

-- The game only fills in your own power between ticks. Everyone else's (target,
-- focus, party...) arrives in steps, one per server tick, so a gain on another
-- unit is spread over UF.POWER_GLIDE seconds (about a tick), keeping the bar
-- moving until the next one lands. It runs a tick behind but never jumps.
-- Drops (a spell, rage decay) and secret values go straight to the bar.
UF.POWER_GLIDE = 2
local watched, gliding = {}, {}   -- UF.WatchPower's frames, and the ones currently gliding
function UF.FeedPower(f, v, instant)
    if isSecret(v) then
        f.polledPower, f.glideTo = nil, nil
        Style.SetBarValue(f.power, v, instant)
        return
    end
    if v == f.polledPower and not instant then return end
    local old = f.polledPower
    f.polledPower = v
    if not instant and old and v > old and f.unitToken ~= "player" then
        local from = f.glideTo and f.glideShown or old
        f.glideShown, f.glideTo = from, v
        f.glideRate = (v - from) / UF.POWER_GLIDE
        gliding[f] = true
        return
    end
    f.glideTo = nil
    Style.SetBarValue(f.power, v, instant)
end

function UF.StepGlide(f, dt)
    local shown = f.glideShown + f.glideRate * dt
    if shown >= f.glideTo then
        shown, f.glideTo = f.glideTo, nil
    end
    f.glideShown = shown
    f.power:SetValue(shown)
end

-- Everyone else's power bars (target, focus, party, 40 raid tiles) share one
-- driver instead of a script per frame. Each frame it only steps the bars that
-- are gliding (a frame hidden mid-glide lands at once, unseen), and every
-- UF.POWER_POLL_OTHERS it polls them all once. on false means no longer watched
-- (its power bar is off), so a frame whose bar is off costs nothing.
local driver, waited
function UF.WatchPower(f, on)
    if on == false then
        if not f.powerWatched then return end
        f.powerWatched = nil
        for i = #watched, 1, -1 do if watched[i] == f then table.remove(watched, i) end end
        return
    end
    if f.powerWatched then return end
    f.powerWatched = true
    watched[#watched + 1] = f
    if driver then return end
    driver, waited = CreateFrame("Frame"), 0
    driver:SetScript("OnUpdate", function(_, dt)
        for g in pairs(gliding) do
            if not g.glideTo then
                gliding[g] = nil
            elseif g:IsShown() then
                UF.StepGlide(g, dt)
            else
                g.power:SetValue(g.glideTo)   -- out of sight, so land at once
                g.glideTo, gliding[g] = nil, nil
            end
        end
        waited = waited + dt
        if waited < UF.POWER_POLL_OTHERS then return end
        waited = 0
        for i = 1, #watched do UF.PollOnce(watched[i]) end
    end)
end
UF.watchedPower, UF.glidingPower = watched, gliding

-- Float: a health change brings its frame (or its group) back for a while.
-- Power doesn't. In combat the frame is already shown, and outside combat mana
-- or energy ticking up or rage draining kept it from ever fading.
local WAKES = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true }

function UF.Wire(f)
    UF.RegisterUnitEvents(f)
    f:SetScript("OnEvent", function(self, event)
        if self.test then return end
        local fn = UNIT_EVENTS[event]
        if fn then fn(self) end
        local wake = WAKES[event]
        if wake then
            -- Kept, since health can fire many times a second.
            local key = self.wakeKey
            if not key then
                key = "UnitFrames." .. tostring(self.group and self.group.key or self.spec.unit)
                self.wakeKey = key
            end
            DUI.Fade.Wake(key)
        end
    end)
    -- Shown means a unit appeared where there was none (a target swap keeps it shown).
    f:HookScript("OnShow", function(self)
        if self.group and self.group.making then return end   -- Group:MakeAhead
        UF.UpdateAll(self, true)
        if self.spec.arrive then ns.Arrive.Start(self) end
    end)
    if f.spec.arrive then
        f:HookScript("OnHide", function(self) ns.Arrive.Finish(self) end)
        ns.Arrive.Wire(f)
    end
end

-- For units with no change events (target of target). Health, power and threat
-- every interval. The rest (name, marker, portrait, status) changes with who it
-- is, which UNIT_TARGET and PLAYER_TARGET_CHANGED redo at once, so the full
-- pass is just a safety net every UF.POLL_FULL intervals.
UF.POLL_FULL = 5
function UF.EnablePolling(f, interval)
    local elapsed, n = 0, 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < interval then return end
        elapsed = 0
        n = n % UF.POLL_FULL
        if n == 0 or self.test then
            UF.UpdateAll(self)
        elseif UnitExists(self.unitToken) then
            UF.UpdateHealth(self)
            UF.UpdatePower(self)
            UF.UpdateThreat(self)
        end
        n = n + 1
    end)
end

-- What plugins get from a unit frame or group tile (DaylightUI.API's Paint,
-- kinds "unit", "party", "raid", "partypet"), and how one gets its own look back
-- when a plugin releases a piece. A piece the frame doesn't have is nil.
if DUI.APIReport then
    local function parts(f)
        local shell = Style.GetShell(f)
        local p = f.portrait
        return {
            health = f.health, healthFill = f.health and f.health:GetStatusBarTexture(),
            healthBack = f.health and Style.BarBack(f.health),
            power = f.power, powerFill = f.power and f.power:GetStatusBarTexture(),
            powerBack = f.power and Style.BarBack(f.power),
            name = f.nameText, level = f.status and f.status.levelText,
            texts = f.extraTexts, portrait = p, classIcon = p and p.icon,
            border = shell and shell.border, band = shell and shell.band,
        }
    end
    local function repaintFrame(f)
        -- Remove a plugin's fill texture from the bars it released.
        if f.health and not UF.Owned(f, "healthFill") then Style.ResetBarFill(f.health) end
        if f.power and not UF.Owned(f, "powerFill") then Style.ResetBarFill(f.power) end
        if f.test then return UF.ShowSample(f) end
        if type(f.unitToken) ~= "string" then return end
        UF.UpdateIdentity(f)
        if f.power then UF.UpdatePower(f, true) end
    end
    for _, kind in ipairs({ "unit", "party", "raid", "partypet" }) do
        DUI.APIReport.Parts(kind, parts)
        DUI.APIReport.Repainter(kind, repaintFrame)
    end
end
