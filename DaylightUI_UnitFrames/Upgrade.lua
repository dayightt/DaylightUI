-- Upgrades for saved unit frame settings, one profile at a time. Runs on the
-- active profile when the module loads (ns.Build), and from the core on a new
-- profile copied from another (DB.RunUpgrades), so old settings never land
-- unconverted. Each step runs once per profile (uf.groupFrames holds the last
-- one done) and handles full and sparse tables alike, since a saved profile
-- only keeps what differs from the defaults.

local _, ns = ...
local DUI = DaylightUI

ns.UPGRADE_STEPS = {}

-- A read-only view of t with defaults filling the gaps. t may be nil.
function ns.WithDefaults(t, defaults)
    return setmetatable({}, { __index = function(_, k)
        local v = nil
        if type(t) == "table" then v = t[k] end
        if v == nil then return defaults[k] end
        return v
    end })
end

-- The frames' scale relative to UIParent's (general.scale).
function ns.ScaleOf(general) return tonumber(general and general.scale) or 1 end

-- Moves a saved spot (a CENTER offset from UIParent's CENTER, in UIParent
-- units, as Movers stores it) so a box of the new size keeps the old box's
-- top-left corner. r is the frame's scale relative to UIParent's.
function ns.KeepTopLeft(pos, oldW, oldH, newW, newH, r)
    return { pos[1] + (newW - oldW) * r / 2, pos[2] - (newH - oldH) * r / 2 }
end

-- Converts a default spot (a point on UIParent's same point, x/y in the
-- frame's own units) to Movers' saved format, for a W x H box at scale r.
function ns.SpotCentre(point, x, y, W, H, r)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = x * r, y * r
    if point:find("LEFT") then cx = -uw / 2 + (x + W / 2) * r
    elseif point:find("RIGHT") then cx = uw / 2 + (x - W / 2) * r end
    if point:find("TOP") then cy = uh / 2 + (y - H / 2) * r
    elseif point:find("BOTTOM") then cy = -uh / 2 + (y + H / 2) * r end
    return { cx, cy }
end

-- 1: the corner crown's pixel size has its own key (leaderPx). leaderSize is
-- now only the tab crown's scale (player, target, focus, party).
ns.UPGRADE_STEPS[1] = function(uf)
    for _, key in ipairs({ "raid", "healer", "healerParty" }) do
        local t = uf[key]
        if type(t) == "table" and type(t.leaderSize) == "number" then
            t.leaderPx, t.leaderSize = t.leaderSize, nil
        end
    end
end

-- 2: the party is now one holder instead of four frames hung off the first.
-- A saved spot (the first frame's center) moves to the holder's center so the
-- first frame stays on the same pixel.
ns.UPGRADE_STEPS[2] = function(uf, pos, general)
    local at = pos["unitframes.party"]
    if type(at) ~= "table" then return end
    local party = ns.WithDefaults(uf.party, ns.DEFAULTS.party)
    local count = ns.Party.Count(party)
    local w, h = ns.Group.Footprint(party, count, party.direction == "rows")
    pos["unitframes.party"] = ns.KeepTopLeft(at, party.width, party.height, w, h, ns.ScaleOf(general))
end

-- 3: the party buff spots "below"/"above" used to mean under the debuffs / over
-- the frame. Those words now mean inside the frame, as on tiles.
ns.UPGRADE_STEPS[3] = function(uf)
    local party = uf.party
    if type(party) ~= "table" then return end
    if party.buffsAt == "below" then party.buffsAt = "under"
    elseif party.buffsAt == "above" then party.buffsAt = "over" end
end


-- What a tile look carries over to the party: the settings both have.
ns.SHARED_TILE_KEYS = { "width", "height", "spacing", "groupSpacing", "perLine", "sortBy", "showName",
    "showPercent", "healthText", "healthTextX", "healthTextY", "percentSign", "hideFullHealth", "showPower",
    "powerHeight", "showMarker", "markerSize", "markerPos", "showLeader", "leaderPos", "leaderPx",
    "leaderHideInCombat", "showRole", "rolePos", "roleSize", "roleHideDamage", "roleHideInCombat",
    "predictHeals", "predictAbsorbs", "showThreat", "showDispel", "dispelSize", "dispelHighlight",
    "dispelGlow", "dispelAlpha", "dispelOnlyMine", "dispelPos", "fade", "fillVertical", "nameAlign",
    "nameX", "nameY", "showBuffs", "buffFilter", "buffsAt", "buffSize", "maxBuffs", "buffSpacing",
    "buffRows", "nameColor", "nameCustom" }

-- Plus the party pieces a tile doesn't have.
ns.TILE_PIECES = { portrait = "none", nameOnBar = true, slant = false, showDebuffs = false,
                   showLevel = false, showPvP = false, bigNumber = false }

local copy = DUI.DB.Copy

-- The raid tiles' buff defaults before they became an aura group (step 7).
-- Step 4 reads a raid look over these, as it did when it shipped.
local OLD_RAID_BUFFS = { showBuffs = false, buffFilter = "mine", buffsAt = "below", buffSize = 14, maxBuffs = 4,
                         buffSpacing = 2, buffRows = 1 }
local function oldRaidDefaults()
    local t = {}
    for k, v in pairs(ns.DEFAULTS.raid) do t[k] = v end
    for k, v in pairs(OLD_RAID_BUFFS) do t[k] = v end
    return t
end

-- A tile look (src read over its defaults) converted to party settings.
function ns.TileLook(src, defaults)
    local view, out = ns.WithDefaults(src, defaults), {}
    for _, k in ipairs(ns.SHARED_TILE_KEYS) do
        local v = view[k]
        if v ~= nil then out[k] = copy(v) end
    end
    for k, v in pairs(ns.TILE_PIECES) do out[k] = v end
    -- With a single group, "Group, then role" is just role.
    if out.sortBy == "grouprole" then out.sortBy = "role" end
    return out
end

local function ensure(t, k)
    if type(t[k]) ~= "table" then t[k] = {} end
    return t[k]
end

-- 4: "Use raid frames in a party" was removed. A party that ran as raid tiles
-- becomes party buttons with the same look in the same spot. Healer frames
-- take priority (step 5, which also keeps the first healer layout,
-- raid.underPlayer, as is). "auto" was also removed from the raid's direction:
-- the raid only shows in a raid, where auto meant columns.
ns.UPGRADE_STEPS[4] = function(uf, pos, general)
    local raid = ensure(uf, "raid")
    if raid.underPlayer ~= nil then return end
    local wasOn = raid.inParty == true and raid.enabled ~= false and uf.healerFrames ~= true
    local inPartyDir = raid.direction == "auto" and "rows" or raid.direction
    raid.inParty = nil
    if raid.direction == "auto" then raid.direction = "columns" end
    if not wasOn then return end
    local party = ensure(uf, "party")
    for k, v in pairs(ns.TileLook(raid, oldRaidDefaults())) do party[k] = v end
    party.direction = inPartyDir or "columns"
    party.hideSelf = raid.hideSelf == true
    -- The tiles showed in a party regardless of the party frames' own switch.
    party.enabled = true
    -- No default for it: the tiles' own value, or General's (nil).
    party.fade = copy(raid.fade)
    local rt = ns.WithDefaults(uf.raidText, ns.DEFAULTS.raidText)
    local pt = ensure(uf, "partyText")
    pt.name, pt.percent = rt.name, rt.percent
    -- In a party the tiles held the same spot the party's holder does now.
    if type(pos["unitframes.raid"]) == "table" then
        pos["unitframes.party"] = { pos["unitframes.raid"][1], pos["unitframes.raid"][2] }
    else
        -- Never moved: use the raid's default spot (top left) for the party's footprint.
        local view = ns.WithDefaults(party, ns.DEFAULTS.party)
        local w, h = ns.Group.Footprint(view, ns.Party.Count(view), view.direction == "rows")
        pos["unitframes.party"] = ns.SpotCentre("TOPLEFT", 20, -220, w, h, ns.ScaleOf(general))
    end
end

-- The old healer frame defaults, so a profile saved with them (holding only
-- what differed) can be read back in full.
ns.OLD_HEALER = {
    healer = { enabled = true, width = 60, height = 56, spacing = 4, groupSpacing = 4,
               direction = "auto", perLine = 5, sortBy = "group", groups = 8, showName = true, showPercent = true,
               healthText = "missing", healthTextX = 0, healthTextY = 0, slant = false, showPower = true,
               powerHeight = 4, showMarker = true, predictHeals = true, predictAbsorbs = true, showThreat = true,
               showDispel = true, dispelSize = 14, dispelHighlight = "none", dispelAlpha = 0.3, dispelOnlyMine = true,
               showLeader = true, dispelPos = "topright", rolePos = "bottomleft", roleSize = 11,
               markerPos = "bottomright", markerSize = 11, leaderPos = "topleft", leaderPx = 11,
               roleHideDamage = false, roleHideInCombat = false, leaderHideInCombat = false,
               percentSign = false, fillVertical = false, showRole = true, hideSelf = false, nameAlign = "center",
               nameX = 0, nameY = 0, showBuffs = true, buffFilter = "mine", buffsAt = "below", buffSize = 14,
               maxBuffs = 4, buffSpacing = 2, buffRows = 1, hideFullHealth = false },
    healerText = { name = 11, percent = 10, cast = 9, big = 12 },
    healerPartyText = { name = 11, percent = 10, cast = 9, big = 12 },
}
ns.OLD_HEALER.healerParty = ns.OLD_HEALER.healer   -- the same defaults

local function view(uf, key) return ns.WithDefaults(uf[key], ns.OLD_HEALER[key]) end

-- Tile settings the healer tiles had no default for. Unset, they used
-- General's out-of-combat opacity and the global name color, so party and raid
-- take the tiles' value or none, never their own old one.
local NO_DEFAULT = { "fade", "nameColor", "nameCustom" }

-- 5: healer frames were removed. Their party tiles become the party's settings
-- and their raid tiles the raid's, each in its own spot (in Movers' terms, so
-- the first tile lands where it was). Then every old key is removed. Older
-- healer layouts are brought up to the last one first.
ns.UPGRADE_STEPS[5] = function(uf, pos, general)
    local raid = ensure(uf, "raid")
    -- The first layout: raid tiles under the player, set on the raid itself.
    if raid.underPlayer ~= nil then
        raid.underPlayer = nil
        uf.healerFrames = true
        local healer = ensure(uf, "healer")
        for _, k in ipairs({ "direction", "width", "height", "spacing", "groupSpacing", "showPercent",
                             "healthText", "showPower", "powerHeight", "showDispel", "dispelSize" }) do
            if raid[k] ~= nil then healer[k] = raid[k] end
            raid[k] = nil
        end
        raid.direction = "columns"
        if type(uf.raidText) == "table" and uf.raidText.name then
            ensure(uf, "healerText").name, uf.raidText.name = uf.raidText.name, nil
        end
        if pos["unitframes.raid"] then
            pos["unitframes.healer"], pos["unitframes.raid"] = pos["unitframes.raid"], nil
        end
        if type(uf.pet) == "table" then uf.pet.beside = nil end
    end
    -- One set of tiles for both party and raid, before they were split.
    if type(uf.healerParty) ~= "table" or not uf.healerParty.split then
        local hp, ht = ensure(uf, "healerParty"), ensure(uf, "healerPartyText")
        for k, v in pairs(type(uf.healer) == "table" and uf.healer or {}) do hp[k] = copy(v) end
        for k, v in pairs(type(uf.healerText) == "table" and uf.healerText or {}) do ht[k] = v end
    end
    if uf.healerFrames == true then
        local r = ns.ScaleOf(general)
        local hp, hr = view(uf, "healerParty"), view(uf, "healer")
        local hpt, hrt = view(uf, "healerPartyText"), view(uf, "healerText")
        local ln = type(general.lastNames) == "table" and general.lastNames or nil
        -- The party. With the party tiles off, the party frames showed as they
        -- were, so those stay.
        if hp.enabled ~= false then
            local oldRows = hp.direction ~= "columns"   -- auto meant a row in a party
            local ow, oh = ns.Group.Footprint(hp, 5, oldRows)
            local party = ensure(uf, "party")
            for k, v in pairs(ns.TileLook(uf.healerParty, ns.OLD_HEALER.healerParty)) do party[k] = v end
            party.direction = oldRows and "rows" or "columns"
            party.hideSelf = hp.hideSelf == true
            -- The tiles showed in a party regardless of the party frames' own switch.
            party.enabled = true
            for _, k in ipairs(NO_DEFAULT) do party[k] = copy(hp[k]) end
            local pt = ensure(uf, "partyText")
            pt.name, pt.percent, pt.big = hpt.name, hpt.percent, hpt.big
            local nw, nh = ns.Group.Footprint(party, ns.Party.Count(party), party.direction == "rows")
            local at = pos["unitframes.healerParty"] or ns.SpotCentre("BOTTOM", 0, 140, ow, oh, r)
            pos["unitframes.party"] = ns.KeepTopLeft(at, ow, oh, nw, nh, r)
            -- First and last names: use the tiles' switch.
            if ln then
                local v = ln.healerParty
                if v == nil then v = true end
                ln.party = v
            end
        end
        -- The raid.
        for k in pairs(ns.OLD_HEALER.healer) do raid[k] = copy(hr[k]) end
        for _, k in ipairs(NO_DEFAULT) do raid[k] = copy(hr[k]) end
        if raid.direction == "auto" then raid.direction = "columns" end
        local rt = ensure(uf, "raidText")
        rt.name, rt.percent, rt.big = hrt.name, hrt.percent, hrt.big
        if pos["unitframes.healer"] then
            pos["unitframes.raid"] = { pos["unitframes.healer"][1], pos["unitframes.healer"][2] }
        else
            local rw, rh = ns.Group.Footprint(raid, 40, raid.direction == "rows")
            pos["unitframes.raid"] = ns.SpotCentre("BOTTOM", 0, 140, rw, rh, r)
        end
        if ln then
            local v = ln.healer
            if v == nil then v = true end
            ln.raid = v
        end
    end
    uf.healerFrames, uf.healer, uf.healerText, uf.healerParty, uf.healerPartyText = nil, nil, nil, nil, nil
    raid.inParty = nil
    pos["unitframes.healer"], pos["unitframes.healerParty"] = nil, nil
    if type(general.lastNames) == "table" then
        general.lastNames.healer, general.lastNames.healerParty = nil, nil
    end
end

-- 6: combo points' "Gradient" switch became a color choice (Color). A profile
-- that had it on picks "gradient".
ns.UPGRADE_STEPS[6] = function(uf)
    local combo = uf.combo
    if type(combo) ~= "table" then return end
    if combo.gradient == true and combo.colorMode == nil then combo.colorMode = "gradient" end
    combo.gradient = nil
end

-- 7: raid tile buffs became an aura group (AuraGroups.lua). The old keys move
-- into raid.auras.buffs with each old spot renamed, so a tile's buffs stay
-- where they were.
ns.UPGRADE_STEPS[7] = function(uf)
    local raid = uf.raid
    if type(raid) ~= "table" then return end
    local AT = { below = { "bottomleft", "right" }, above = { "topleft", "right" }, left = { "outleft", "left" },
                 right = { "outright", "right" }, top = { "above", "right" }, bottom = { "below", "right" } }
    local MOVE = { showBuffs = "show", buffFilter = "which", buffSize = "size", maxBuffs = "max",
                   buffSpacing = "spacing", buffRows = "rows" }
    local b = {}
    for old, new in pairs(MOVE) do
        if raid[old] ~= nil then b[new] = raid[old] end
        raid[old] = nil
    end
    local at = AT[raid.buffsAt]
    if at then b.spot, b.grow = at[1], at[2] end
    raid.buffsAt = nil
    if next(b) == nil then return end
    if type(raid.auras) ~= "table" then raid.auras = {} end
    if type(raid.auras.buffs) ~= "table" then raid.auras.buffs = {} end
    for k, v in pairs(b) do raid.auras.buffs[k] = v end
end

-- 8: the cast bars' attach switch became a position (at). Detached becomes
-- "free" (its own mover), attached becomes each bar's default spot.
ns.UPGRADE_STEPS[8] = function(uf)
    for _, key in ipairs({ "playerCastbar", "targetCastbar", "focusCastbar" }) do
        local c = uf[key]
        if type(c) == "table" then
            if c.attach == false and c.at == nil then c.at = "free" end
            c.attach = nil
        end
    end
end

-- 9: party debuffs and buffs became aura groups (AuraGroups.lua). The old keys
-- move into party.auras with each old spot renamed, so they stay where they
-- were. Uses its own numbers, never the live defaults.
ns.UPGRADE_STEPS[9] = function(uf)
    local party = uf.party
    if type(party) ~= "table" then return end
    local DEBUFF = { showDebuffs = "show", debuffFilter = "which", debuffSize = "size", maxDebuffs = "max",
                     debuffSpacing = "spacing", debuffRows = "rows", debuffX = "x", debuffY = "y" }
    local BUFF = { showBuffs = "show", buffFilter = "which", buffSize = "size", maxBuffs = "max",
                   buffSpacing = "spacing", buffRows = "rows" }
    local DEBUFF_AT = { under = { "below", "left" }, over = { "above", "left" }, inBottom = { "bottomright", "left" },
                        inTop = { "topright", "left" }, left = { "outleft", "left" }, right = { "outright", "right" } }
    local BUFF_AT = { row = { "below", "right" }, under = { "below", "right" }, over = { "above", "right" },
                      below = { "bottomleft", "right" }, above = { "topleft", "right" }, left = { "outleft", "left" },
                      right = { "outright", "right" }, top = { "above", "right" }, bottom = { "below", "right" } }
    -- The old party defaults, for keys a profile never saved.
    local function old(k, default)
        local v = party[k]
        if v == nil then return default end
        return v
    end
    local d, b = {}, {}
    local at = DEBUFF_AT[party.debuffsAt]
    if at then d.spot, d.grow = at[1], at[2] end
    at = BUFF_AT[party.buffsAt]
    if at then b.spot, b.grow = at[1], at[2] end
    -- Buffs under the debuffs had their own line, offset by the debuff rows,
    -- the gap and the room for the numbers on top of each.
    if party.buffsAt == "under" and old("showDebuffs", true) == true and old("debuffsAt", "under") == "under" then
        local size, gap = old("debuffSize", 18), old("debuffSpacing", 2)
        local max = math.max(1, old("maxDebuffs", 4))
        local per = math.max(1, math.ceil(max / math.max(1, old("debuffRows", 1))))
        local rows = math.ceil(max / per)
        local h = rows * math.floor(size * 0.88 + 0.5) + (rows - 1) * (gap + 4)
        b.y = math.floor(old("debuffY", 0) - h - 11 + 0.5)
    end
    for oldKey, new in pairs(DEBUFF) do
        if party[oldKey] ~= nil then d[new] = party[oldKey] end
        party[oldKey] = nil
    end
    for oldKey, new in pairs(BUFF) do
        if party[oldKey] ~= nil then b[new] = party[oldKey] end
        party[oldKey] = nil
    end
    party.debuffsAt, party.buffsAt = nil, nil
    for key, t in pairs({ debuffs = d, buffs = b }) do
        if next(t) ~= nil then
            if type(party.auras) ~= "table" then party.auras = {} end
            if type(party.auras[key]) ~= "table" then party.auras[key] = {} end
            for k, v in pairs(t) do party.auras[key][k] = v end
        end
    end
end

-- 10: the target's debuffs and buffs sit at a spot (Spots.lua) instead of just
-- above or below. Each old side maps to the spot of the same name.
ns.UPGRADE_STEPS[10] = function(uf)
    local t = uf.targetAuras
    if type(t) ~= "table" then return end
    local SIDE = { above = "above", below = "below" }
    if SIDE[t.debuffsAt] then t.debuffSpot = SIDE[t.debuffsAt] end
    if SIDE[t.buffsAt] then t.buffSpot = SIDE[t.buffsAt] end
    t.debuffsAt, t.buffsAt = nil, nil
end

-- 11: the cast bars' and swing timers' three fill switches (Class color stays)
-- became one Fill style (fill). Priority: the Gradients page's pair, then the
-- Daylight gradient, else the plain colors.
ns.UPGRADE_STEPS[11] = function(uf)
    for _, key in ipairs({ "casts", "swing" }) do
        local c = uf[key]
        if type(c) == "table" then
            if c.pairGradient == false then
                c.fill = c.gradient == true and "daylight" or "plain"
            end
            c.gradient, c.pairGradient = nil, nil
        end
    end
end

-- 12: the Daylight gradient switch for your health bar (Colors page) became a
-- choice in the player page's Health bar color, where it always won.
ns.UPGRADE_STEPS[12] = function(uf)
    local c = uf.colors
    if type(c) ~= "table" then return end
    if c.playerDaylight == true then
        if type(uf.player) ~= "table" then uf.player = {} end
        uf.player.colorHealth = "daylight"
    end
    c.playerDaylight = nil
end

-- 13: one home each for name length and cast text size. "Shorten long names"
-- (Colors page) was removed, and each frame without its own limit takes the
-- shared one. The shared cast text size was removed, and each bar without its
-- own size takes it (unchanged it was 12, now each bar's default). A profile
-- read over the defaults has 12 (or the old default 0) for "none".
ns.UPGRADE_STEPS[13] = function(uf)
    local c = uf.colors
    if type(c) == "table" then
        if c.nameLimit == true then
            local n = tonumber(c.nameLimitLen) or 12
            for _, key in ipairs({ "player", "target", "targettarget", "pet", "focus", "party", "raid", "raid20", "raid40" }) do
                -- A raid size without its own setup follows Raid 10's.
                if type(uf[key]) == "table" or not key:find("^raid%d") then
                    if type(uf[key]) ~= "table" then uf[key] = {} end
                    local own = uf[key].nameLimitLen
                    if own == nil or own == 0 then uf[key].nameLimitLen = n end
                end
            end
        end
        c.nameLimit, c.nameLimitLen = nil, nil
    end
    local text = uf.text
    local size = type(text) == "table" and tonumber(text.cast) or nil
    for _, key in ipairs({ "playerCastbar", "targetCastbar", "focusCastbar", "swing" }) do
        local bar = uf[key]
        local own = type(bar) == "table" and bar.textSize or nil
        if own == 0 or (size and (own == nil or own == 12)) then
            if type(uf[key]) ~= "table" then uf[key] = {} end
            uf[key].textSize = size or 12
        end
    end
    if type(text) == "table" then text.cast = nil end
end

-- 14: a target or focus cast bar above or below its frame now matches the
-- frame's width (fitFrame). A player who set a custom width keeps it.
ns.UPGRADE_STEPS[14] = function(uf)
    for _, key in ipairs({ "targetCastbar", "focusCastbar" }) do
        local bar = uf[key]
        if type(bar) == "table" and bar.width ~= nil and bar.fitFrame == nil then bar.fitFrame = false end
    end
end

-- 15: swing.height no longer counts the border, which now goes around the bar.
-- A height set above the new default loses the 8 the border took on a 4K
-- screen, so the bar looks the same there and stops being eaten on smaller
-- screens. A new profile already holds the default and is left alone.
ns.UPGRADE_STEPS[15] = function(uf)
    local swing = uf.swing
    if type(swing) == "table" and type(swing.height) == "number" and swing.height > 14 then
        swing.height = math.max(14, swing.height - 8)
    end
end

-- 16: the single power bar switch for all frames (look.showPower) was replaced
-- by each frame's own Power bar switch. A profile that had it off turns each
-- frame's off, so no bar comes back.
ns.UPGRADE_STEPS[16] = function(uf)
    local look = uf.look
    if type(look) ~= "table" or type(look.showPower) == "nil" then return end
    if look.showPower == false then
        for _, key in ipairs({ "player", "target", "focus", "pet", "party", "partyPet", "raid", "raid20", "raid40" }) do
            if type(uf[key]) ~= "table" then uf[key] = {} end
            uf[key].showPower = false
        end
    end
    look.showPower = nil
end

-- 17: each cast bar sets its spell name and time on its own. The shared
-- Spell name switch and Timer pick, and each bar's one text size and color,
-- are copied to both texts of every bar so nothing looks different.
ns.UPGRADE_STEPS[17] = function(uf)
    local casts = type(uf.casts) == "table" and uf.casts or {}
    for _, key in ipairs({ "playerCastbar", "targetCastbar", "focusCastbar", "partyCastbar" }) do
        local bar = type(uf[key]) == "table" and uf[key] or nil
        local size = bar and tonumber(bar.textSize)
        local color = bar and type(bar.textColor) == "table" and bar.textColor or nil
        local spell, time = {}, {}
        if size then spell.size, time.size = size, size end
        if color then
            spell.color = { color[1], color[2], color[3] }
            time.color = { color[1], color[2], color[3] }
        end
        if casts.showName == false then spell.show = false end
        if casts.timer == "none" then time.show = false elseif casts.timer == "total" then time.format = "total" end
        if next(spell) or next(time) then
            if not bar then bar = {}; uf[key] = bar end
            if next(spell) then bar.spell = spell end
            if next(time) then bar.time = time end
        end
        if bar then bar.textSize, bar.textColor = nil, nil end
    end
    casts.showName, casts.timer = nil, nil
end

-- p: a profile's data { modules = {...}, positions = {...}, general = {...} }.
function ns.UpgradeGroupFrames(p)
    if type(p) ~= "table" then return end
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.positions) ~= "table" then p.positions = {} end
    if type(p.general) ~= "table" then p.general = {} end
    local uf = p.modules.UnitFrames
    if type(uf) ~= "table" then
        uf = {}
        p.modules.UnitFrames = uf
    end
    for i = (tonumber(uf.groupFrames) or 0) + 1, #ns.UPGRADE_STEPS do
        ns.UPGRADE_STEPS[i](uf, p.positions, p.general)
        uf.groupFrames = i
    end
end

DUI.DB.RegisterUpgrade(ns.UpgradeGroupFrames)
