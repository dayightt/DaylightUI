-- Default settings for the unit frames module. Sizes are in UI units;
-- borders are drawn by the core in physical pixels on top of these.

local _, ns = ...

-- Where pieces sit (spots, grow, nudge) comes from the core, shared with the nameplates.
ns.Spots = DaylightUI.Spots

-- Add piece (Design mode): every frame has a few empty slots for extra pieces,
-- all off. Adding one turns a free slot on, removing it resets the slot to
-- these values. Fixed slots mean every option row has a default.
ns.TEXT_SLOTS = { "t1", "t2", "t3", "t4" }
ns.AURA_SLOTS = { "x1", "x2", "x3", "x4" }
-- kind (and kind2, kind3, where "none" means nothing more): level | health |
-- power | name | class | status | group | guild | classification, joined by sep (Texts.lua).
local function textSlots()
    local out = {}
    for _, k in ipairs(ns.TEXT_SLOTS) do
        out[k] = { show = false, kind = "level", kind2 = "none", kind3 = "none", sep = "space", spot = "left",
                   x = 0, y = 0, size = 11,
                   healthFormat = "value", powerFormat = "value" }
    end
    return out
end
-- what: debuffs | buffs, each with its own filter (AuraGroups.lua).
local function auraSlots(into)
    for _, k in ipairs(ns.AURA_SLOTS) do
        into[k] = { show = false, what = "debuffs", debuffWhich = "dispel", buffWhich = "heals", spot = "topleft",
                    grow = "right", size = 14, max = 3, rows = 1, spacing = 2, x = 0, y = 0, timers = false,
                    shortTimers = false, swipe = false, tooltips = false }
    end
    return into
end

-- Heal indicators (Indicators.lua). Off by default (the Healer setup turns them
-- on). Three squares along the top and one under them for a priest's Weakened
-- Soul, using your class's picks. Two more, off, in the bottom corners for a
-- group buff or two.
local function indicators(size)
    local function sq(spot, show)
        return { show = show, spell = "auto", spot = spot, x = 0, y = 0, paint = "spell", custom = { 1, 1, 1 } }
    end
    return { show = false, size = size, swipe = true, look = "square", i1 = sq("topleft", true), i2 = sq("top", true),
             i3 = sq("topright", true), i4 = sq("bottom", true), i5 = sq("bottomleft", false),
             i6 = sq("bottomright", false) }
end

ns.DEFAULTS = {
    player = { enabled = true, texts = textSlots(), namePos = "bar", nameX = 0, nameY = 0, nameColor = "global", nameCustom = { 1, 1, 1 }, percentColor = "white", percentCustom = { 1, 1, 1 }, nameLimitLen = 0, tabHeight = 16, portraitScale = 1, width = 187, height = 43, showPower = true, powerHeight = 11, powerAt = "inside", powerWidth = 187, powerSlant = true, showName = true, nameOnBar = false, showPercent = true,
               slant = true, bigNumber = true, healthText = "value", percentSign = false, hideFullHealth = false, reverseFill = false, portrait = "class", portraitRing = "class", portraitDragon = false, portraitDragonColor = "class",
               predictHeals = true, predictAbsorbs = true, showThreat = true,
               showLevel = false, levelPos = "ring", levelX = 0, levelY = 0, showLeader = true, showResting = true, showPvP = true, pvpSize = 1, leaderSize = 1, restSize = 1, showPowerText = false, powerFormat = "value", hideFullPower = false, powerTextPos = "inner", healthTextX = 0, healthTextY = 0, powerTextX = 0, powerTextY = 0, druidMana = true,
               druidBars = { enabled = false, width = 94, height = 6, spacing = 2, showText = false }, costPreview = true, costColor = { 0, 0, 0 }, costAlpha = 0.45, regenSweep = "off", fade = DaylightUI.Fade.Defaults({ fullHealth = false, target = true }) },
    target = { enabled = true, texts = textSlots(), namePos = "bar", nameX = 0, nameY = 0, nameColor = "global", nameCustom = { 1, 1, 1 }, percentColor = "white", percentCustom = { 1, 1, 1 }, nameLimitLen = 0, tabHeight = 16, portraitScale = 1, markerSize = 16, width = 187, height = 43, showPower = true, powerHeight = 11, showName = true, nameOnBar = false, showPercent = true,
               showMarker = true, showClassification = true, slant = true, bigNumber = true, healthText = "percent", percentSign = false, hideFullHealth = false, reverseFill = false,
               portrait = "class", portraitRing = "class", predictHeals = true, predictAbsorbs = true, showThreat = true, threatTag = true,
               -- The threat % tag (UF.LayoutThreatTag), on the frame or on its own
               -- mover. 0 height means the name tab's, 0 size fits the tag.
               threatTagAt = "frame", threatTagX = 0, threatTagY = 0, threatTagWidth = 36, threatTagHeight = 0,
               threatTagSize = 0, threatTagColor = "threat", threatTagBox = true, threatTagSlant = true,
               dotTint = true, dotSkull = true,
               showLevel = true, levelPos = "ring", levelX = 0, levelY = 0, showLeader = true, showPvP = true, pvpSize = 1, leaderSize = 1, showPowerText = false, powerFormat = "value", hideFullPower = false, powerTextPos = "inner", healthTextX = 0, healthTextY = 0, powerTextX = 0, powerTextY = 0, fade = DaylightUI.Fade.Defaults() },
    targettarget = { enabled = true, showPercent = false, namePos = "bar", nameX = 0, nameY = 0, healthText = "percent", healthTextX = 0, healthTextY = 0, percentSign = false, hideFullHealth = false, nameColor = "global", nameCustom = { 1, 1, 1 }, percentColor = "white", percentCustom = { 1, 1, 1 }, nameLimitLen = 0, width = 94, height = 22, showName = true, slant = true, reverseFill = false,
                     -- Power bar off by default, since most people only glance to see who it is.
                     showPower = false, powerHeight = 4, powerTextPos = "inner", powerTextX = 0, powerTextY = 0,
                     showPowerText = false, powerFormat = "value", hideFullPower = false,
                     predictHeals = true, predictAbsorbs = true, fade = DaylightUI.Fade.Defaults() },
    pet = { enabled = true, showPercent = false, namePos = "bar", nameX = 0, nameY = 0, healthText = "percent", healthTextX = 0, healthTextY = 0, percentSign = false, hideFullHealth = false, powerTextPos = "inner", powerTextX = 0, powerTextY = 0, nameColor = "global", nameCustom = { 1, 1, 1 }, percentColor = "white", percentCustom = { 1, 1, 1 }, nameLimitLen = 0, width = 94, height = 20, powerHeight = 4, showPower = true, showName = true, slant = true,
            reverseFill = false, showPowerText = false, powerFormat = "value", hideFullPower = false,
            predictHeals = true, predictAbsorbs = true, fade = DaylightUI.Fade.Defaults({ fullHealth = false }), happiness = true, happinessBar = false,
            happinessLook = "square", happinessSpot = "outleft", happinessSize = 16, happinessX = 0, happinessY = 0,
            -- The name on the bar, or with nameOnBar off, in a small tab above the frame like the others.
            nameOnBar = true, tabHeight = 14 },
    focus = { enabled = true, texts = textSlots(), namePos = "bar", nameX = 0, nameY = 0, nameColor = "global", nameCustom = { 1, 1, 1 }, percentColor = "white", percentCustom = { 1, 1, 1 }, nameLimitLen = 0, tabHeight = 16, portraitScale = 1, markerSize = 13, powerTextPos = "inner", powerTextX = 0, powerTextY = 0, width = 153, height = 34, showPower = true, powerHeight = 7, showName = true, nameOnBar = false, showPercent = true,
              showMarker = true, slant = true, portrait = "class", portraitRing = "class", predictHeals = true, predictAbsorbs = true,
              showThreat = true, showLevel = true, levelPos = "ring", levelX = 0, levelY = 0, showLeader = true, showPvP = true, pvpSize = 1, leaderSize = 1, showPowerText = false, powerFormat = "value", hideFullPower = false, fade = DaylightUI.Fade.Defaults(),
              healthText = "percent", healthTextX = 0, healthTextY = 0, percentSign = false, hideFullHealth = false, reverseFill = false },
    -- at: where it sits (CastBar.AT). "below" hangs under your frame, "above"
    -- sits over it, "free" uses its own mover. x/y nudge it above or below.
    playerCastbar = { enabled = true, at = "below", x = 0, y = 0, width = 285, height = 27, showIcon = false, slant = true, textSize = 12, reverseFill = false,
                      from = "frame",   -- when hung "below": under the player frame, or "power" for under a free-standing power bar (player.powerAt free)
                      shell = { own = false, borderPx = 8, cornerPx = 6, shadowPx = 4 } },   -- its own border (UF.OwnShell)
    -- The target's cast bar: inside its frame over the power bar (at = "power"),
    -- or its own bar with its own size above or below the frame (nudged by
    -- x/y) or on its own mover ("free").
    -- insideText*: its text while inside the frame (size 0 fits the power bar,
    -- X/Y nudge it). textColor applies to the spell name and timer either way.
    targetCastbar = { enabled = true, at = "power", x = 0, y = 0, fitFrame = true, width = 240, height = 22, showIcon = true, slant = false, textSize = 12, reverseFill = false,
                      insideTextSize = 0, insideTextX = 0, insideTextY = 0, textColor = { 1, 1, 1 } },
    -- Both cast bars: colors, the spell name, the timer ("left", "total", "none").
    casts = { cast = { 0.78, 0.62, 0.30 }, channel = { 0.78, 0.62, 0.30 }, locked = { 0.42, 0.42, 0.45 },
              interrupted = { 0.52, 0.17, 0.15 }, flash = true, showName = true, timer = "left",
              -- fill: "plain" (the colors above), "daylight" (the Daylight
              -- gradient) or "pair" (the Gradients page's Cast / Channel pairs).
              classColor = false, fill = "pair",
              -- Target and focus: an interrupt animation (Motion.KICKS) and
              -- "Kicked by <name>" to the right of the bar or "below" it.
              kickStyle = "blade", kickedBy = true, kickedByPos = "right" },
    -- The focus cast bar: inside its frame over the power bar, or its own.
    focusCastbar = { enabled = true, at = "power", x = 0, y = 0, fitFrame = true, width = 200, height = 20, showIcon = true, slant = false, textSize = 12, reverseFill = false },
    -- Each party member's cast bar (PartyCasts.lua): inside the frame over the
    -- power bar ("power"), hung under it and sliding out ("slide"), or its own
    -- bar beside the frame ("free", with spot right|left|below|above and x/y).
    -- insideTextSize: its text inside the frame (0 fits the power bar).
    partyCastbar = { enabled = true, at = "power", spot = "right", x = 0, y = 0, width = 140, height = 16, showIcon = true,
                     slant = false, textSize = 11, insideTextSize = 0, reverseFill = false, textColor = { 1, 1, 1 } },
    -- The target's and focus's own cast bar colors.
    targetCasts = { cast = { 0.78, 0.62, 0.30 }, channel = { 0.78, 0.62, 0.30 }, locked = { 0.42, 0.42, 0.45 },
                    interrupted = { 0.52, 0.17, 0.15 }, classColor = false },
    -- Swing timers: under the player cast bar (attach) or on their own mover.
    swing = { enabled = true, attach = true, mainHand = true, width = 204, height = 14, visibility = "swinging",
              shell = { own = false, borderPx = 8, cornerPx = 6, shadowPx = 4 },   -- its own border (UF.OwnShell)
              offHand = true, ranged = true, stopCue = false, rangeText = false, showText = true, queue = true, classColor = false, fill = "pair",
              slant = false, showIcon = false, textSize = 12, reverseFill = false, spacing = 0, growUp = false,
              colors = { main = { 0.80, 0.68, 0.46 }, off = { 0.62, 0.56, 0.46 }, ranged = { 0.50, 0.66, 0.52 },
                         queued = { 0.86, 0.44, 0.32 } } },
    combo = { enabled = true, size = 14, fullRed = true,
        height = 0, gap = 3, x = 0, y = 0,
        color = { 1.0, 0.82, 0.25 }, fullColor = { 0.95, 0.22, 0.2 },
        colorMode = "color", fullAll = false, empty = 0.4, border = 2, slant = true, anchor = "target",
        side = "below", align = "inner", stretch = false },
    party = { enabled = true, texts = textSlots(), nameColor = "global", nameCustom = { 1, 1, 1 }, percentColor = "white", percentCustom = { 1, 1, 1 }, nameLimitLen = 0, tabHeight = 16, portraitScale = 1, markerSize = 13, powerTextPos = "inner", width = 170, height = 34, showPower = true, powerHeight = 7, spacing = 38, showName = true, nameOnBar = false,
              showPercent = true, slant = true, bigNumber = true, healthText = "percent", percentSign = false, hideFullHealth = false, reverseFill = false, portrait = "class", portraitRing = "class",
              showMarker = true, predictHeals = true, predictAbsorbs = true, showThreat = true,
              showLevel = true, levelPos = "ring", levelX = 0, levelY = 0, showLeader = true, showPvP = true, pvpSize = 1, leaderSize = 1, leaderPx = 11, showPowerText = false, powerFormat = "value", hideFullPower = false, healthTextX = 0, healthTextY = 0, powerTextX = 0, powerTextY = 0,
              fade = DaylightUI.Fade.Defaults(), showRole = true,
              -- Aura groups (AuraGroups.lua), matching the old party rows: debuffs
              -- under the frame from its right end, your buffs from its left.
              indicators = indicators(10),
              auras = auraSlots({
                  -- Debuff tooltips on: what's on a party member matters
                  -- more than a mouseover cast while the cursor is over an icon.
                  debuffs = { show = true, which = "all", spot = "below", grow = "left", size = 18, max = 4,
                              rows = 1, spacing = 2, x = 0, y = 0, timers = true, shortTimers = false, swipe = false, tooltips = true },
                  cc = { show = false, spot = "center", grow = "center", size = 18, max = 1, rows = 1, spacing = 2,
                         x = 0, y = 0, timers = true, shortTimers = false, swipe = false, tooltips = true },
                  buffs = { show = true, which = "heals", spot = "below", grow = "right", size = 14, max = 4,
                            rows = 1, spacing = 2, x = 0, y = 0, timers = true, shortTimers = false, swipe = false, tooltips = false },
              }),
              -- Header layout: down or across, frames per line, sorting, you.
              direction = "columns", perLine = 5, groupSpacing = 4, sortBy = "role", hideSelf = true, showSolo = false,
              -- Grow from the bottom and/or the right (Group.Corner).
              growUp = false, growLeft = false,
              -- Tile look pieces, off or unused in the default look.
              fillVertical = false, showPower = true, namePos = "bar", nameAlign = "center", nameX = 0, nameY = 0,
              rolePos = "home", roleSize = 11, roleX = 0, roleY = 0, markerPos = "home", markerX = 0, markerY = 0, leaderPos = "home", leaderX = 0, leaderY = 0, showReady = true, readyPos = "right", readySize = 14, readyX = 0, readyY = 0,
              roleHideDamage = false, roleHideInCombat = false, leaderHideInCombat = false,
              showDispel = false, dispelSize = 14, dispelHighlight = "none", dispelGlow = true, dispelAlpha = 0.3,
              dispelOnlyMine = true, dispelPos = "topright", dispelX = 0, dispelY = 0,
              -- Your target's tile gets an outline (GroupParts.lua).
              targetMark = true, targetMarkColor = "accent", targetMarkCustom = { 1, 1, 1 },
              -- Private boss debuffs addon code can't read (GroupPrivate.lua), big icons in the middle.
              privateAuras = true },
    partyText = { name = 11, percent = 10, big = 17, power = 0 },
    -- Party pets (PartyPets.lua): a small bar beside each member's frame while
    -- their pet is out, in the owner's class colors (color = owner|own).
    partyPet = { enabled = false, spot = "right", x = 0, y = 0, width = 80, height = 18, showPower = true, powerHeight = 3,
                 slant = true, reverseFill = false, color = "owner", showName = true, nameColor = "global", nameCustom = { 1, 1, 1 },
                 nameLimitLen = 0, showPercent = false, healthText = "percent", percentSign = false, hideFullHealth = false,
                 percentColor = "white", percentCustom = { 1, 1, 1 }, showPowerText = false, powerFormat = "value",
                 hideFullPower = false, powerTextPos = "inner", predictHeals = true, predictAbsorbs = true },
    partyPetText = { name = 10, percent = 10, power = 0 },
    raid = { enabled = true, texts = textSlots(), showInParty = false, width = 72, height = 28, spacing = 2, groupSpacing = 4, showName = true,
             nameColor = "global", nameCustom = { 1, 1, 1 }, nameLimitLen = 0,
             direction = "columns", sortBy = "group", groups = 8, growUp = false, growLeft = false,
             perLine = 5, fillVertical = false, hideSelf = false, namePos = "bar", nameAlign = "center", nameX = 0, nameY = 0,
             -- Aura groups (AuraGroups.lua), placed by Spots on the tile.
             indicators = indicators(8),
             auras = auraSlots({
                 -- Calm by default: two small debuffs in the corner, crowd control
                 -- in the middle only while it lasts, no timer numbers.
                 debuffs = { show = true, which = "all", spot = "bottomright", grow = "left", size = 12, max = 2,
                             rows = 1, spacing = 2, x = 0, y = 0, timers = false, shortTimers = false, swipe = false, tooltips = false },
                 cc = { show = true, spot = "center", grow = "center", size = 16, max = 1, rows = 1, spacing = 2,
                        x = 0, y = 0, timers = false, shortTimers = false, swipe = false, tooltips = false },
                 -- bottomleft matches the old tile buffs' "below". An upgrade step leaves an unsaved spot at this.
                 buffs = { show = false, which = "heals", spot = "bottomleft", grow = "right", size = 14, max = 4,
                           rows = 1, spacing = 2, x = 0, y = 0, timers = false, shortTimers = false, swipe = false, tooltips = false },
             }),
             showPercent = false, slant = false, showPower = true, powerHeight = 3, showMarker = true,
             predictHeals = true, predictAbsorbs = true, showThreat = true, showDispel = true, dispelSize = 12, dispelHighlight = "none", dispelGlow = true, dispelAlpha = 0.3, dispelOnlyMine = true, dispelPos = "topright", dispelX = 0, dispelY = 0, rolePos = "bottomleft", roleSize = 11, roleX = 0, roleY = 0, markerPos = "bottomright", markerSize = 11, markerX = 0, markerY = 0, leaderPos = "topleft", leaderPx = 11, leaderX = 0, leaderY = 0, showReady = true, readyPos = "right", readySize = 14, readyX = 0, readyY = 0, roleHideDamage = false, roleHideInCombat = false, leaderHideInCombat = false,
             showLeader = true, fade = DaylightUI.Fade.Defaults(), healthText = "percent", healthTextX = 0, healthTextY = 0, percentSign = false, hideFullHealth = false, showRole = true,
             targetMark = true, targetMarkColor = "accent", targetMarkCustom = { 1, 1, 1 },
             privateAuras = true },
    raidText = { name = 10, percent = 10 },
    portraits = { icons = "daylight", classIcons = {},   -- a pick per class token
                  ringWidth = "normal", ringLine = true }, -- every portrait ring: thin | normal | thick, and the groove around its middle
    range = { enabled = true, alpha = 0.45, groupOwn = false, alphaGroup = 0.45 },
    -- The leader drawer beside the group frames (Leader.lua).
    leader = { enabled = true, show = "tank" },
    -- The pull timer's big number (Pull.lua).
    pull = { enabled = true },
    -- Your bars at your feet, like Legion's personal resource display
    -- (Personal.lua). Shown in combat or with a target, hidden otherwise.
    personal = { enabled = false, follow = "feet", x = 0, y = -35, width = 150, height = 10,
                 powerHeight = 5, showHealth = true, showPower = true, combo = true, slant = true, castbar = false, swing = false,
                 predictHeals = true, predictAbsorbs = true,
                 -- Its own rows, shaped like playerAuras: off, centered over the bars, buffs nearest.
                 auras = { debuffs = false, buffs = false, debuffSpot = "above", debuffGrow = "center", debuffX = 0, debuffY = 0,
                           buffSpot = "above", buffGrow = "center", buffX = 0, buffY = 0, debuffSize = 26, maxDebuffs = 8,
                           buffSize = 20, maxBuffs = 8, debuffSpacing = 3, buffSpacing = 3, debuffRows = 2, buffRows = 2,
                           debuffTimeSize = 12, buffTimeSize = 9, debuffCountSize = 10, buffCountSize = 10 },
                 fade = DaylightUI.Fade.Defaults({ mode = "ooc", target = true, delay = 2, mouseover = false }) },
    -- Spot, grow and nudge (Spots.lua) for each row: debuffs over the name
    -- tab, buffs under the frame, both from the outer end inward.
    targetAuras = { debuffSpot = "above", debuffGrow = "left", debuffX = 0, debuffY = 0,
                    buffSpot = "below", buffGrow = "left", buffX = 0, buffY = 0, debuffSize = 26, debuffs = true, debuffFilter = "all",
                    maxDebuffs = 8, maxOtherDebuffs = 4, buffSize = 16, buffs = true, maxBuffs = 6,
                    debuffSpacing = 3, buffSpacing = 3, debuffRows = 3, buffRows = 2,
                    debuffTimeSize = 12, buffTimeSize = 9, debuffCountSize = 10, buffCountSize = 10 },
    -- The player frame's own aura rows, styled like the target's. Off by
    -- default, since the Buffs module shows yours. Both sit over the frame,
    -- clear of the cast bar and swing timers below, buffs nearest, running from
    -- the portrait end toward the angled one. All debuffs on you form one group.
    playerAuras = { debuffs = false, buffs = false, debuffSpot = "above", debuffGrow = "right", debuffX = 0, debuffY = 0,
                    buffSpot = "above", buffGrow = "right", buffX = 0, buffY = 0, debuffSize = 26, maxDebuffs = 8,
                    buffSize = 16, maxBuffs = 8, debuffSpacing = 3, buffSpacing = 3, debuffRows = 2, buffRows = 2,
                    debuffTimeSize = 12, buffTimeSize = 9, debuffCountSize = 10, buffCountSize = 10 },
    -- Text sizes per frame. Party and raid share theirs.
    playerText = { name = 12, percent = 11, big = 20, power = 0 },
    targetText = { name = 12, percent = 11, big = 20, power = 0 },
    focusText = { name = 12, percent = 11, power = 0 },
    targettargetText = { name = 11, percent = 11, power = 0 },
    petText = { name = 11, percent = 11, power = 0 },
    -- slant: the angled end's width as a share of frame height (every frame).
    -- style: the frames' look, "daylight" or "ribbon" (UF.StyleOf). Each frame
    -- can pick its own, see RIBBON_FRAMES below.
    look = { slant = 0.21, style = "daylight" },
    -- Every frame's colors (Colors.lua).
    colors = { health = "classGradient", mirrorGradient = true, healthColor = { 0.35, 0.75, 0.35 }, backBrightness = 0.4,
               power = "gradient", powerColor = { 0.3, 0.5, 0.95 }, name = "white",
               threat = "health", threatColor = { 0.92, 0.2, 0.18 }, threatWarn = { 1.0, 0.55, 0.12 },
               healColor = { 0.55, 0.95, 0.6 }, absorbColor = { 0.85, 0.92, 1.0 }, absorbStyle = "stripes",
               overshield = true, overshieldReverse = false, overshieldPaint = "shield",
               overshieldColor = { 0.85, 0.92, 1.0 }, overshieldStyle = "shield",
               dotTint = { 0, 0, 0, 0.45 },
               dispelMagic = { 0.25, 0.55, 0.95 }, dispelCurse = { 0.62, 0.3, 0.9 },
               dispelDisease = { 0.7, 0.5, 0.18 }, dispelPoison = { 0.3, 0.7, 0.25 },
               dead = { 0.42, 0.42, 0.44 }, offline = { 0.42, 0.42, 0.44 }, tapped = { 0.42, 0.42, 0.44 },
               hostile = { 0.85, 0.22, 0.20 }, neutral = { 0.95, 0.78, 0.25 }, friendly = { 0.30, 0.78, 0.32 },
               backMode = "dim", backColor = { 0.14, 0.14, 0.14 },
               -- How solid the empty part of every health and power bar is
               -- (Style.BAR_BACK_ALPHA is the classic value). Lower values also thin
               -- the frame's dark inside so the world shows through (UF.ApplyBack).
               backAlpha = 0.8 },
}

-- Each frame's own bar textures and fonts, set on its page (UF.MEDIA): health
-- and power bars (fill and background), and name / health / power text. Cast
-- bars, swing timer and combo points have their own. "general" means
-- General > Appearance.
ns.MEDIA_FRAMES = { "player", "target", "targettarget", "pet", "focus", "party", "raid", "partyPet" }
local G = "general"
for _, k in ipairs(ns.MEDIA_FRAMES) do
    ns.DEFAULTS[k].media = { health = G, healthBack = G, power = G, powerBack = G, nameFont = G, healthFont = G, powerFont = G }
end
-- The target's threat % tag. "general" uses the frame's health font.
ns.DEFAULTS.target.media.threatFont = G
for _, k in ipairs({ "playerCastbar", "targetCastbar", "focusCastbar", "partyCastbar", "swing" }) do
    ns.DEFAULTS[k].media = { bar = G, barBack = G, font = G }
end
ns.DEFAULTS.combo.media = { bar = G, barBack = G }
-- A bar detached on its own (swing.bars.<hand>.detach) is a separate piece
-- with its own mover and these settings.
ns.SWING_BARS = { "main", "off", "ranged" }
ns.DEFAULTS.swing.bars = {}
for _, k in ipairs(ns.SWING_BARS) do
    ns.DEFAULTS.swing.bars[k] = { detach = false, visibility = "swinging", width = 204, height = 14, textSize = 12, showName = true,
                                  showTime = true, showIcon = false, slant = false, reverseFill = false }
end

-- Each frame's own look on top of the shared one, set on its page: bar colors
-- ("global" means the Colors page) and its border, corners and shadow (own =
-- false uses General > Appearance). Raid tiles' border starts at half a
-- frame's, matching their General value.
ns.LOOK_FRAMES = { "player", "target", "targettarget", "pet", "focus", "party", "raid" }
for _, k in ipairs(ns.LOOK_FRAMES) do
    local d = ns.DEFAULTS[k]
    d.colorHealth, d.colorHealthCustom = "global", { 0.35, 0.75, 0.35 }
    if d.powerHeight then d.colorPower, d.colorPowerCustom = "global", { 0.3, 0.5, 0.95 } end
    d.shell = { own = false, borderPx = k == "raid" and 4 or 8, cornerPx = 6, shadowPx = 4 }
end

-- The personal display's own look. Same shape, but "player" and "general" both
-- use the player frame's until it's given its own (Personal.lua).
do
    local d = ns.DEFAULTS.personal
    d.colorHealth, d.colorHealthCustom = "player", { 0.35, 0.75, 0.35 }
    d.colorPower, d.colorPowerCustom = "player", { 0.3, 0.5, 0.95 }
    d.shell = { own = false, borderPx = 8, cornerPx = 6, shadowPx = 4 }
    d.media = { health = G, healthBack = G, power = G, powerBack = G, healthFont = G, powerFont = G }
    -- angle: the cut as a share of its height. 0 uses the shared Slant angle.
    d.angle = 0
    -- The numbers on the bars, using the player frame's keys. Size 0 fits its bar.
    d.showPercent, d.healthText, d.percentSign, d.hideFullHealth = false, "percent", false, false
    d.healthTextPos, d.healthTextSize = "center", 0
    d.showPowerText, d.powerFormat, d.hideFullPower = false, "value", false
    d.powerTextPos, d.powerTextSize = "center", 0
end

-- The name tab's own look and placement (Daylight style; UF.TabLook, UF.PlaceTab).
-- own = false: half the frame's border, the frame's corners, General's shadow.
-- slant "frame" follows the frame's angled end. at = outer (past the portrait)
-- | middle | inner (clear of the angled end), nudged by x/y (up).
-- width = fit (the name) | full | fixed (widthPx). align positions the name.
ns.TAB_FRAMES = { "player", "target", "focus", "party", "pet" }
for _, k in ipairs(ns.TAB_FRAMES) do
    ns.DEFAULTS[k].tab = { own = false, borderPx = 4, cornerPx = 6, shadowPx = 4, slant = "frame",
                           at = "outer", x = 0, y = 0, width = "fit", widthPx = 90, align = "center" }
end

-- The two styles (UF.StyleOf): Daylight (the frame, its name tab, power inside)
-- or Ribbon (a slim bar with name and health number floating above and the
-- power as a thin line underneath). style = "global" follows look.style. Each
-- style keeps its own heights in sizes. The live keys (height...) hold the
-- shown style's values and sizesFor says which (ns.SwapSizes), so sliders,
-- samples and Design mode grips can keep reading and writing them directly.
-- ribbonGap: space between the bar and its power line.
ns.RIBBON_FRAMES = { "player", "target", "focus", "party" }
ns.SIZE_KEYS = { "height", "powerHeight", "tabHeight", "spacing" }
local RIBBON_SIZES = {
    player = { height = 24, powerHeight = 5, tabHeight = 16 },
    target = { height = 24, powerHeight = 5, tabHeight = 16 },
    focus = { height = 20, powerHeight = 4, tabHeight = 14 },
    party = { height = 20, powerHeight = 4, tabHeight = 14, spacing = 48 },
}
for _, k in ipairs(ns.RIBBON_FRAMES) do
    local d = ns.DEFAULTS[k]
    local day = {}
    for _, key in ipairs(ns.SIZE_KEYS) do day[key] = d[key] end
    d.style, d.sizesFor, d.ribbonGap = "global", "daylight", 2
    d.sizes = { daylight = day, ribbon = RIBBON_SIZES[k] }
end

-- Raid setups by size (Raid.lua; the Raid 10, Raid 20 and Raid 40 pages).
-- 11 to 20 players use raid20 / raid20Text and 21 to 40 use raid40 / raid40Text,
-- built like the 10-player raid setup, unless follow is on (the default), in
-- which case raid's is used. The own setup starts as a copy of raid the first
-- time follow is turned off. Every size shares raid's switches, fade, textures
-- and fonts (RAID_SHARED), set on the Raid 10 page.
ns.RAID_SIZES = { 20, 40 }
ns.RAID_SHARED = { enabled = true, showInParty = true, fade = true, media = true }
local function deep(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep(x) end
    return t
end
for _, n in ipairs(ns.RAID_SIZES) do
    local t = deep(ns.DEFAULTS.raid)
    t.follow, t.own = true, false
    t.ownSpot = false   -- its own spot and unlock handle (Raid.PlaceHolder)
    ns.DEFAULTS["raid" .. n] = t
    ns.DEFAULTS["raid" .. n .. "Text"] = deep(ns.DEFAULTS.raidText)
end

-- The focus's target: set up like the target of target (a small frame, power
-- bar off), angled the focus's way.
do
    ns.DEFAULTS.focustarget = deep(ns.DEFAULTS.targettarget)
    ns.DEFAULTS.focustargetText = deep(ns.DEFAULTS.targettargetText)
    for _, list in ipairs({ ns.MEDIA_FRAMES, ns.LOOK_FRAMES }) do
        list[#list + 1] = "focustarget"
    end
end

-- Enemy flag carriers (Arena.lua), which the game exposes as arena units in a
-- battleground. One setup for all of them, built like the focus frame (its
-- look, texts and sizes), stacked spacing apart.
do
    local t = deep(ns.DEFAULTS.focus)
    t.spacing, t.showThreat, t.showLeader = 30, false, false
    ns.DEFAULTS.arena = t
    ns.DEFAULTS.arenaText = deep(ns.DEFAULTS.focusText)
    for _, list in ipairs({ ns.MEDIA_FRAMES, ns.LOOK_FRAMES, ns.TAB_FRAMES, ns.RIBBON_FRAMES }) do
        list[#list + 1] = "arena"
    end
end
