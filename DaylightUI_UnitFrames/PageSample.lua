-- Live samples for the options window's frame pages. Options/SampleStrip.lua
-- shows one above the settings on the Player, Target, Focus, Target of Target,
-- Pet, Party and Raid pages. Each is that page's own frame (one party member,
-- one raid tile), made by the same builder as the real ones, filled with a
-- sample unit and laid out from the current settings on every Refresh. They're
-- plain non-secure frames, so combat doesn't matter, and nothing here touches
-- the real frames. Parts() reports where each part of the frame is and which
-- of the page's settings a click on it opens.
--
-- A sample has s.frame (its box), s.Refresh(width, maxHeight) returning the
-- height used, s.Parts() returning { { region, label, keys, scale }, ... } for
-- the parts showing now, and s.missing: parts showing with none of their
-- settings on the page (the tests keep it empty).

local _, ns = ...
local DUI = DaylightUI
local UF, Pixel, Auras = ns.UF, DUI.Pixel, ns.Auras

local PageSample = {}
ns.PageSample = PageSample

PageSample.PAD = 6           -- room kept around the frame (crown, ring shadow)
PageSample.OFF_ALPHA = 0.35  -- a frame turned off (its Show) is drawn faded
PageSample.PARTY_COUNT = 1   -- party members drawn: one, carrying every piece (two made Design mode confusing)

local function db() return ns.module and ns.module.db end

-- Parts: where each one is on a sample frame, and its settings

local function at(field) return function(f) return f[field] end end
local function status(icon) return function(f) return f.status and f.status.icons[icon] end end

-- The name: its tab (a tile's own when its name sits outside it), or the text
-- itself when it sits on the bar (or on Ribbon's row, which it shares with the
-- health number).
local function nameRegion(f)
    if f.tab and f.tab:IsShown() and not f.ribbon then return f.tab end
    if f.nameTag and f.nameTagOn then return f.nameTag end
    return f.nameText
end

-- The health text, unless it's drawn as the large number, and vice versa.
local function healthText(f) if not f.bigNumber then return f.percentText end end
local function bigNumber(f) if f.bigNumber then return f.percentText end end

-- The role icon with the portrait's set, or in a corner.
local function roleRegion(f)
    local icon = f.status and f.status.icons.role
    if icon and icon:IsVisible() then return icon end
    return f.roleIcon
end

-- The sample icons a holder (Auras.HolderFor) shows now.
local function shownIcons(h)
    local out = {}
    if h and h:IsVisible() then
        for _, btn in ipairs(h.pool or {}) do
            if btn:IsShown() then out[#out + 1] = btn end
        end
    end
    return out
end

-- A frame's parts in draw order. Where parts overlap, the later one gets the
-- click. keys: its settings on the frame's own page, with "%s" standing for the
-- page's id ("%s.width" is "target.width"; text sizes live under "<id>Text").
-- Keys the page lacks are skipped. move: the settings a Design mode drag writes
-- (spot, nudge x and y; home = true means no spot, a single place it's nudged
-- from). size: the ones a grip writes (w and h, or s).
PageSample.PARTS = {
    { label = "Health bar", at = at("health"), keys = { "%s.width", "%s.height", "%s.strata", "%s.dotTint", "%s.dotSkull" },
      size = { w = "%s.width", h = "%s.height" } },
    -- The power bar's height grip thickens both it and the frame (link), so it
    -- grows down toward the grip and the health bar keeps its size. Its width
    -- is the frame's. Ribbon's line is under the frame, so it grows on its own
    -- (linkIf).
    { label = "Power bar", at = at("power"), keys = { "%s.showPower", "%s.powerHeight", "%s.powerAt", "%s.powerWidth", "%s.powerSlant", "%s.ribbonGap", "%s.regenSweep" },
      size = { w = "%s.width", h = "%s.powerHeight", link = { h = "%s.height" } },
      linkIf = function(f) return not f.ribbon end },
    { label = "Portrait", at = at("portrait"), keys = { "%s.portrait", "%s.portraitRing", "%s.portraitDragon", "%s.portraitDragonColor", "%s.portraitScale" } },
    -- On the bar the name moves to a spot. In its tab, the tab slides along the
    -- frame's top (tabMove, UF.TabDots). On Ribbon's row it doesn't move.
    { label = "Name", at = nameRegion, keys = { "%s.showName", "%s.namePos", "%s.nameOnBar", "%sText.name", "%s.tabHeight", "%s.nameTag",
                                               "%s.tab.at", "%s.tab.x", "%s.tab.y", "%s.tab.width", "%s.tab.own" },
      move = { spot = "%s.namePos", x = "%s.nameX", y = "%s.nameY" },
      tabMove = { spot = "%s.tab.at", x = "%s.tab.x", y = "%s.tab.y", dots = function(f) return UF.TabDots(f) end },
      moveIf = function(f) return f.nameOnBar == true or not (f.tab and f.tab:IsShown()) end,
      tabIf = function(f) return f.nameOnBar ~= true and f.tab ~= nil and f.tab:IsShown() and not f.ribbon end },
    { label = "Health text", at = healthText, keys = { "%s.showPercent", "%s.healthText", "%sText.percent", "%s.healthTextX", "%s.healthTextY" },
      move = { home = true, x = "%s.healthTextX", y = "%s.healthTextY" } },
    { label = "Large health number", at = bigNumber, keys = { "%s.bigNumber", "%sText.big", "%s.healthTextX", "%s.healthTextY" },
      move = { home = true, x = "%s.healthTextX", y = "%s.healthTextY" } },
    { label = "Power text", at = at("powerText"), keys = { "%s.showPowerText", "%s.powerFormat", "%s.powerPercentSign", "%s.hideFullPower", "%sText.power", "%s.powerTextX", "%s.powerTextY" },
      move = { home = true, x = "%s.powerTextX", y = "%s.powerTextY" } },
    { label = "Raid marker", at = at("marker"), keys = { "%s.showMarker", "%s.markerSize", "%s.markerPos" },
      move = { spot = "%s.markerPos", x = "%s.markerX", y = "%s.markerY" }, size = { s = "%s.markerSize" } },
    { label = "Elite crest", at = at("crest"), keys = { "%s.showClassification" } },
    { label = "Level", at = status("level"), keys = { "%s.showLevel", "%s.levelPos" },
      move = { spot = "%s.levelPos", x = "%s.levelX", y = "%s.levelY" } },
    -- With the name or portrait. A party button's moves to a spot (UF.IconSpot).
    { label = "Leader crown", at = status("leader"), keys = { "%s.showLeader", "%s.leaderSize", "%s.leaderPos" },
      move = { spot = "%s.leaderPos", x = "%s.leaderX", y = "%s.leaderY" } },
    { label = "Leader crown", at = at("leaderIcon"), keys = { "%s.showLeader", "%s.leaderPos", "%s.leaderPx" },
      move = { spot = "%s.leaderPos", x = "%s.leaderX", y = "%s.leaderY" }, size = { s = "%s.leaderPx" } },
    { label = "PvP flag", at = status("pvp"), keys = { "%s.showPvP", "%s.pvpSize" } },
    { label = "Resting", at = status("rest"), keys = { "%s.showResting", "%s.restSize" } },
    { label = "Role icon", at = roleRegion, keys = { "%s.showRole", "%s.rolePos", "%s.roleSize" },
      move = { spot = "%s.rolePos", x = "%s.roleX", y = "%s.roleY" }, size = { s = "%s.roleSize" } },
    -- Only the pet page's sample has one (f.happiness). Hidden while the
    -- switch is off, so it drops out of Design mode with it.
    { label = "Pet happiness", at = function(f) return f.happiness end,
      keys = { "%s.happiness", "%s.happinessLook", "%s.happinessSpot", "%s.happinessSize", "%s.happinessX", "%s.happinessY" },
      move = { spot = "%s.happinessSpot", x = "%s.happinessX", y = "%s.happinessY" },
      size = { s = "%s.happinessSize" } },
}

-- Extra texts (Add piece, Texts.lua): one part per slot, on every frame page
-- that has them.
for i, key in ipairs(ns.TEXT_SLOTS) do
    local p = "%s.texts." .. key .. "."
    PageSample.PARTS[#PageSample.PARTS + 1] = {
        label = "Extra text " .. i,
        at = function(f) return f.extraTexts and f.extraTexts[i] end,
        keys = { p .. "kind", p .. "kind2", p .. "kind3", p .. "sep", p .. "spot", p .. "size" },
        move = { spot = p .. "spot", x = p .. "x", y = p .. "y" }, size = { s = p .. "size" } }
end

-- The target's and player's own auras (a stand-in set, Auras.PlainSet, on
-- f.sampleAuras). In Design mode they move and resize like any piece.
-- prefix: the frame's aura settings.
local function auraRow(prefix, kind)
    local p = prefix .. "." .. kind
    return { label = kind == "debuff" and "Debuffs" or "Buffs",
             at = function(f) return f.sampleAuras and shownIcons(Auras.HolderFor(f.sampleAuras[kind .. "s"])) end,
             keys = { p .. "s", p .. "Size", p .. "Spot", p .. "TimeSize", p .. "CountSize" },
             move = { spot = p .. "Spot", x = p .. "X", y = p .. "Y" }, size = { s = p .. "Size" } }
end
-- Page id -> its aura settings and inner end (the side the rows grow toward).
PageSample.AURA_SETS = { target = { key = "targetAuras", side = "left" }, player = { key = "playerAuras", side = "right" } }
PageSample.AURA_PARTS = {}
for id, a in pairs(PageSample.AURA_SETS) do
    PageSample.AURA_PARTS[id] = { auraRow(a.key, "debuff"), auraRow(a.key, "buff") }
end

-- A party member's or raid tile's own extras: its aura groups (stand-ins,
-- AuraGroups.PlainSet) and the sample dispel icon. "%s" is the page's id.
local function groupSet(key) return function(b) return b.sampleSet and b.sampleSet[key] end end
local function groupKeys(key)
    local p = "%s.auras." .. key .. "."
    return { p .. "show", p .. "spot", p .. "size", p .. "max" }
end
local function groupMove(key)
    local p = "%s.auras." .. key .. "."
    return { spot = p .. "spot", x = p .. "x", y = p .. "y" }
end
PageSample.GROUP_PARTS = {
    { label = "Debuffs", at = groupSet("debuffs"), keys = groupKeys("debuffs"), move = groupMove("debuffs"),
      size = { s = "%s.auras.debuffs.size" } },
    { label = "Crowd control", at = groupSet("cc"), keys = groupKeys("cc"), move = groupMove("cc"),
      size = { s = "%s.auras.cc.size" } },
    { label = "Buffs", at = groupSet("buffs"), keys = groupKeys("buffs"), move = groupMove("buffs"),
      size = { s = "%s.auras.buffs.size" } },
    { label = "Dispellable debuff", at = at("sampleDispel"), keys = { "%s.showDispel", "%s.dispelSize", "%s.dispelPos" },
      move = { spot = "%s.dispelPos", x = "%s.dispelX", y = "%s.dispelY" }, size = { s = "%s.dispelSize" } },
    { label = "Ready check", at = at("readyIcon"), keys = { "%s.showReady", "%s.readyPos", "%s.readySize" },
      move = { spot = "%s.readyPos", x = "%s.readyX", y = "%s.readyY" }, size = { s = "%s.readySize" } },
}
-- Extra aura groups (Add piece): their stand-ins, debuffs or buffs.
for i, key in ipairs(ns.AURA_SLOTS) do
    local p = "%s.auras." .. key .. "."
    PageSample.GROUP_PARTS[#PageSample.GROUP_PARTS + 1] = {
        label = "Extra aura group " .. i,
        at = function(b)
            local slot = b.sampleSet and b.sampleSet.extra and b.sampleSet.extra[key]
            if not slot then return nil end
            local out = {}
            if slot.debuffs then out[#out + 1] = slot.debuffs end
            if slot.buffs then out[#out + 1] = slot.buffs end
            return out
        end,
        keys = { p .. "what", p .. "spot", p .. "size", p .. "max" },
        move = { spot = p .. "spot", x = p .. "x", y = p .. "y" }, size = { s = p .. "size" } }
end
-- Heal indicators (Indicators.lua). Each square moves on its own, the size is
-- shared by the set.
for i, slot in ipairs(ns.Indicators.SLOTS) do
    local p = "%s.indicators." .. slot .. "."
    PageSample.GROUP_PARTS[#PageSample.GROUP_PARTS + 1] = {
        label = "Heal indicator " .. i,
        at = function(b)
            local c = b.sampleSet and b.sampleSet.ind and b.sampleSet.ind[i]
            return c and c:IsShown() and c or nil
        end,
        keys = { "%s.indicators.show", p .. "spell", p .. "spot", "%s.indicators.size" },
        move = { spot = p .. "spot", x = p .. "x", y = p .. "y" }, size = { s = "%s.indicators.size" } }
end
PageSample.RAID_PARTS = PageSample.GROUP_PARTS
PageSample.PARTY_PARTS = {}
for _, part in ipairs(PageSample.GROUP_PARTS) do
    PageSample.PARTY_PARTS[#PageSample.PARTY_PARTS + 1] = part
end
-- A party member's pet (PartyPets.lua), on the page's sample while pets are on.
PageSample.PARTY_PARTS[#PageSample.PARTY_PARTS + 1] = {
    label = "Party pet",
    at = function(b) return b.pet and b.pet:IsShown() and b.pet or nil end,
    keys = { "partyPet.enabled", "partyPet.spot", "partyPet.x", "partyPet.y", "partyPet.width", "partyPet.height" },
    move = { spot = "partyPet.spot", x = "partyPet.x", y = "partyPet.y", dots = function(b) return ns.PartyPets.Dots(b) end },
    size = { w = "partyPet.width", h = "partyPet.height" } }

-- The keys on a unit frames page. A page doesn't change once registered.
local pageKeys = {}
local function keysOn(id)
    if pageKeys[id] then return pageKeys[id] end
    local page = DUI.Options.GetPage("UnitFrames." .. id)
    local set = {}
    for _, group in ipairs(page and page.groups or {}) do
        for _, item in ipairs(group.items) do
            if item.key then set[item.key] = item end
        end
    end
    if page then pageKeys[id] = set end
    return set
end

-- Adds a part's spots to out: each of its regions showing now, with whichever
-- of its settings the page has. A part showing with none of them goes into
-- missing instead. scale: the frame's, for sizing spots over text.
local function fmt(pattern, id) return pattern and (string.gsub(pattern, "%%s", id)) end

-- How a part moves in Design mode: its spot and nudge keys (those the page
-- has), the dots it can drop on (owner px, top left, y down), and
-- drop(x, y) -> spot, x, y. cfg: the frame's settings (for the room
-- AuraGroups.Box leaves).
-- m: the part's move, or another of its moves (the name tab's). m.dots(owner)
-- supplies its own dots instead of the Spots ones. m.home: no spot, and its
-- single dot is where region would sit with no nudge.
local function homeDot(region, owner, xKey, yKey)
    local cx, cy = region:GetCenter()
    local left, top = owner:GetLeft(), owner:GetTop()
    -- Not laid out yet, but the drop's own measuring still places it correctly.
    if type(cx) ~= "number" or type(left) ~= "number" then return { spot = "home", x = 0, y = 0 } end
    local k = region:GetEffectiveScale() / owner:GetEffectiveScale()
    local function now(key)
        return key and tonumber(DUI:Get("UnitFrames", ns.Raid.MapKey(key))) or 0
    end
    return { spot = "home", x = cx * k - left - now(xKey), y = top - cy * k + now(yKey) }
end

local function moveOf(part, owner, id, have, cfg, region, m)
    m = m or part.move
    if not (m and cfg) then return nil end
    local xKey, yKey = fmt(m.x, id), fmt(m.y, id)
    xKey, yKey = xKey and have[xKey] and xKey or nil, yKey and have[yKey] and yKey or nil
    local spotKey, dots
    if m.home then
        local dot = (xKey or yKey) and homeDot(region, owner, xKey, yKey)
        if not dot then return nil end
        dots = { dot }
    else
        spotKey = fmt(m.spot, id)
        if not (spotKey and have[spotKey]) then return nil end
        dots = m.dots and m.dots(owner) or ns.Spots.Dots(ns.AuraGroups.Box(owner, cfg))
    end
    return { spotKey = spotKey, xKey = xKey, yKey = yKey, owner = owner, dots = dots,
             drop = function(x, y) return ns.Spots.Drop(dots, x, y) end }
end

-- How a part resizes: { keys = { w, h } or { s }, min, max, step, now,
-- resize = Spots.Resize, link }. Limits come from the page's own sliders. With
-- one size (s) they're plain numbers, with w and h they're tables like keys.
-- link[kind] = { key, now, min, max }: a setting that changes by the same amount.
local function sizeOf(part, id, have, owner)
    local z = part.size
    if not z then return nil end
    local out = { keys = {}, min = {}, max = {}, step = {}, now = {}, resize = ns.Spots.Resize }
    local any
    for _, k in ipairs({ "w", "h", "s" }) do
        local key = fmt(z[k], id)
        local item = key and have[key]
        if type(item) == "table" then
            out.keys[k], out.min[k], out.max[k], out.step[k] = key, item.min, item.max, item.step or 1
            out.now[k] = DUI:Get("UnitFrames", ns.Raid.MapKey(key))
            any = true
        end
    end
    if not any then return nil end
    local linked = z.link and (not part.linkIf or part.linkIf(owner))
    for k, pattern in pairs(linked and z.link or {}) do
        local key = fmt(pattern, id)
        local item = have[key]
        if type(item) == "table" and out.keys[k] then
            out.link = out.link or {}
            out.link[k] = { key = key, now = DUI:Get("UnitFrames", ns.Raid.MapKey(key)), min = item.min, max = item.max }
        end
    end
    if out.keys.s then out.min, out.max, out.step = out.min.s, out.max.s, out.step.s end
    return out
end

local function collect(out, missing, part, owner, id, scale, cfg)
    local found = part.at(owner)
    if found == nil then return end
    if found.GetObjectType then found = { found } end
    local regions = {}
    for _, r in ipairs(found) do
        if r:IsVisible() then regions[#regions + 1] = r end
    end
    if #regions == 0 then return end
    local have, keys = keysOn(id), {}
    for _, pattern in ipairs(part.keys) do
        local key = (string.gsub(pattern, "%%s", id))
        if have[key] then keys[#keys + 1] = key end
    end
    if #keys == 0 then
        missing[#missing + 1] = part.label
        return
    end
    for _, r in ipairs(regions) do
        local move
        if part.tabMove and part.tabIf(owner) then
            move = moveOf(part, owner, id, have, cfg, r, part.tabMove)
        elseif not part.moveIf or part.moveIf(owner) then
            move = moveOf(part, owner, id, have, cfg, r)
        end
        out[#out + 1] = { region = r, label = part.label, keys = keys, scale = scale,
                          move = move, size = sizeOf(part, id, have, owner) }
    end
end

-- Add piece (Options/SampleStrip.lua's menu in Design mode)

local function indexOf(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
end

-- s.Adds() returns keys, values for the menu. s.Add(key) returns the new part's
-- label (so the strip selects it), or nil when every slot is in use.
-- auras: the frame has extra aura group slots (party, raid).
local function addable(s, id, auras)
    if not ns.Texts.FRAMES[id] then return end
    local L = DUI.L
    function s.Adds()
        local keys, values = {}, {}
        for _, kind in ipairs(ns.Texts.KINDS) do
            local k = "text:" .. kind
            keys[#keys + 1], values[k] = k, string.format(L["Text: %s"], L[ns.Texts.LABELS[kind]])
        end
        if auras then
            keys[#keys + 1], values["auras:debuffs"] = "auras:debuffs", L["Aura group: debuffs"]
            keys[#keys + 1], values["auras:buffs"] = "auras:buffs", L["Aura group: buffs"]
        end
        return keys, values
    end
    function s.Add(choice)
        local sub, what = string.match(tostring(choice), "^(%a+):(%a+)$")
        if sub == "text" then
            local key = ns.Texts.Add(ns.Raid.PageFrame(id), what)
            if key then return "Extra text " .. indexOf(ns.TEXT_SLOTS, key) end
            DUI.Print(L["All four extra texts are in use: remove one first."])
        elseif sub == "auras" and auras then
            local key = ns.Texts.AddAuras(ns.Raid.PageFrame(id), what)
            if key then return "Extra aura group " .. indexOf(ns.AURA_SLOTS, key) end
            DUI.Print(L["All four extra aura groups are in use: remove one first."])
        end
    end
end

-- Drawing

local function specOf(unit)
    if unit == "arena" then return ns.Arena.Spec(1) end
    for _, spec in ipairs(ns.SPECS) do
        if spec.unit == unit then return spec end
    end
end

-- Who the sample is: you on your own frame, test mode's units elsewhere.
local function sampleUnit(id)
    if id == "player" then return ns.Sample.You() end
    if id == "arena" then return ns.Arena.SAMPLES[1] end
    return ns.Test.SampleFor(id)
end

-- The name tab's height above the frame's top, when it shows.
local function tabUp(f)
    if f.tab and f.tab:IsShown() then return f.tabHeight or UF.TAB_HEIGHT end
    return 0
end

-- How far a frame's own parts reach past it, in its own units: the portrait
-- ring past the outer end (and above and below when taller than the frame),
-- the name tab and its crest above the top, and Ribbon's power line below.
local function reach(f)
    local up, down = tabUp(f), f.foot or 0
    local p = f.portrait
    if p and p:IsShown() then
        local R, H, y = p:GetWidth() / 2, f:GetHeight(), f.portraitY or 0
        up, down = math.max(up, R + y - H / 2), math.max(down, R - y - H / 2)
    end
    if f.crest and f.crest:IsShown() then up = math.max(up, tabUp(f) + UF.CREST_SIZE / 2) end
    return ns.Sample.Reach(f), up, down
end

-- How far the pet happiness indicator sticks out past the frame, in the
-- frame's units: left, right, up, down. Nothing until it has been drawn.
local function happinessPast(h, f)
    if not (h and h:IsShown() and h.GetRect and f.GetRect) then return 0, 0, 0, 0 end
    local okH, hl, hb, hw, hh = pcall(h.GetRect, h)
    local okF, fl, fb, fw, fh = pcall(f.GetRect, f)
    if not (okH and okF and type(hl) == "number" and type(fl) == "number" and type(hw) == "number") then
        return 0, 0, 0, 0
    end
    return math.max(0, fl - hl), math.max(0, hl + hw - fl - fw),
           math.max(0, hb + hh - fb - fh), math.max(0, fb - hb)
end

-- Fits target (w by h, in its own units, with parts reaching past its outer
-- end, on the right when outerRight, and above and below) into width by at
-- most maxH. Shrinks to fit, never grows, centered in box. box gets the width
-- and the height used, which is returned.
-- back: how far parts reach past the inner end (the party's debuffs outside
-- it). grow: the maximum upscale (for the raid's tiny tiles).
local function fit(box, target, w, h, out, outerRight, up, down, width, maxH, back, grow)
    local pad = PageSample.PAD
    back = back or 0
    local cw, ch = w + out + back + 2 * pad, h + up + down + 2 * pad
    local scale = math.min(grow or 1, width / cw, maxH / ch)
    target:SetScale(scale)
    target:ClearAllPoints()
    local x = (out - back) / 2
    target:SetPoint("CENTER", box, "CENTER", outerRight and -x or x, (down - up) / 2)
    local used = math.min(maxH, math.ceil(ch * scale))
    box:SetSize(width, used)
    return used
end

local function refreshSingle(s, width, maxH)
    local d = db()
    if not d then return 0 end
    ns.Sample.UseSettings(d)
    local f = s.f
    local cfg, text = ns.ConfigFor(d, f.spec)
    f.iconStyle, f.classIcons = d.portraits.icons, d.portraits.classIcons
    f:SetScale(1)
    f:SetSize(2 * Pixel.Snap(f, cfg.width / 2), 2 * Pixel.Snap(f, cfg.height / 2))
    UF.Layout(f, cfg, text, true)
    f.test = sampleUnit(s.id)
    UF.ShowSample(f)
    if f.happiness then
        ns.Happiness.Layout(f.happiness, cfg)
        ns.Happiness.ShowSample(f.happiness)
    end
    f:SetAlpha(cfg.enabled == false and PageSample.OFF_ALPHA or 1)
    local out, up, down = reach(f)
    local back, left, right, hup, hdown = 0, happinessPast(f.happiness, f)
    if f.spec.slant == "left" then
        out, back = math.max(out, right), left
    else
        out, back = math.max(out, left), right
    end
    up, down = math.max(up, hup), math.max(down, hdown)
    if s.auras then
        -- The frame's auras, from its page's own settings.
        local a = d[PageSample.AURA_SETS[s.id].key]
        if s.id == "target" then s.auras.aboveLift, s.auras.buffDrop = ns.TargetAuraRoom(d) end
        Auras.Apply(s.auras, a)
        local top, bottom = Auras.Place(s.auras, f, cfg)
        Auras.ShowSample(s.auras, f, a, ns.Test.AURAS)
        up = math.max(up, tabUp(f) + top)
        down = math.max(down, bottom)
    end
    return fit(s.frame, f, f:GetWidth(), f:GetHeight(), out, f.spec.slant == "left", up, down, width, maxH, back,
               s.Zoom())
end

-- The strip's Zoom slider: how much larger than in game a page's preview is
-- drawn (available room can still shrink it). Each page keeps its own for the
-- session. Every page except the raid's starts at in-game size.
PageSample.ZOOM_MIN, PageSample.ZOOM_MAX, PageSample.ZOOM_STEP = 1, 4, 0.5
PageSample.zoom = {}   -- page id -> its zoom

local function zoomable(s)
    function s.Zoom() return PageSample.zoom[s.id] or 1 end
    function s.SetZoom(v)
        v = tonumber(v) or 1
        PageSample.zoom[s.id] = math.max(PageSample.ZOOM_MIN, math.min(PageSample.ZOOM_MAX, v))
    end
    s.zoomRange = { min = PageSample.ZOOM_MIN, max = PageSample.ZOOM_MAX, step = PageSample.ZOOM_STEP }
end

local function newSingle(id, parent)
    local s = { id = id, missing = {} }
    s.frame = CreateFrame("Frame", nil, parent)
    zoomable(s)
    local f = CreateFrame("Button", nil, s.frame)
    UF.Build(f, specOf(id))
    f:EnableMouse(false)   -- display only, the strip's hotspots take the clicks
    s.f = f
    -- The real pet frame's indicator is a different widget. This one is only
    -- the preview, so Design mode's hotspot gets the click, not a tooltip.
    if id == "pet" then
        f.happiness = ns.Happiness.Create(f)
        f.happiness:EnableMouse(false)
    end
    -- The target's and player's auras use stand-ins, since the client's
    -- containers only ever show a real unit's auras.
    local auraSet = PageSample.AURA_SETS[id]
    if auraSet then
        s.auras = Auras.PlainSet(f, auraSet.side)
        f.sampleAuras = s.auras
    end
    function s.Refresh(width, maxH) return refreshSingle(s, width, maxH) end
    -- Registered with the API as a preview. The strip keeps it permanently, so nothing reports it gone.
    DUI.APIReport.Made("unit", f, id, true)
    addable(s, id)
    function s.Parts()
        local out, missing = {}, {}
        local scale = f:GetScale()
        local cfg = db() and ns.ConfigFor(db(), f.spec)
        for _, part in ipairs(PageSample.PARTS) do collect(out, missing, part, f, id, scale, cfg) end
        for _, part in ipairs(PageSample.AURA_PARTS[id] or {}) do
            collect(out, missing, part, f, id, scale, cfg)
        end
        s.missing = missing
        return out
    end
    return s
end

local function refreshParty(s, width, maxH)
    local d = db()
    if not d then return 0 end
    ns.Sample.UseSettings(d)
    local cfg, text = d.party, d.partyText
    local g = ns.Party.group
    local first = s.members[1]
    s.holder:SetScale(1)
    local w = 2 * Pixel.Snap(first, cfg.width / 2)
    local h = 2 * Pixel.Snap(first, cfg.height / 2)
    g:LayoutSamples(s.members, s.holder, cfg, text, w, h)
    g:FillSamples(s.members, #s.members, cfg)
    for _, b in ipairs(s.members) do b:SetAlpha(cfg.enabled == false and PageSample.OFF_ALPHA or 1) end
    local fw, fh = ns.Group.Footprint(cfg, #s.members, g:PreviewRows(cfg), w, h)
    s.holder:SetSize(fw, fh)
    local out, up, down = reach(first)
    local gUp, gDown, gLeft, gRight = PageSample.GroupReach(cfg, first)
    return fit(s.frame, s.holder, fw, fh, math.max(out, gLeft), first.spec.slant == "left", math.max(up, gUp),
               math.max(down, gDown), width, maxH, gRight, s.Zoom())
end

local function newParty(parent)
    local s = { id = "party", members = {}, missing = {} }
    s.frame = CreateFrame("Frame", nil, parent)
    zoomable(s)
    s.holder = CreateFrame("Frame", nil, s.frame)
    for i = 1, PageSample.PARTY_COUNT do
        local b = ns.Party.group:NewSampleButton(s.holder, i, ns.Party.DressSample)
        b.fullSample = true   -- every piece shows, so each can be dragged
        b:EnableMouse(false)   -- display only, the strip's hotspots take the clicks
        s.members[i] = b
    end
    function s.Refresh(width, maxH) return refreshParty(s, width, maxH) end
    addable(s, "party", true)
    function s.Parts()
        local out, missing = {}, {}
        local scale = s.holder:GetScale()
        for _, b in ipairs(s.members) do
            if b:IsShown() then
                local cfg = db() and db().party
                for _, part in ipairs(PageSample.PARTS) do collect(out, missing, part, b, "party", scale, cfg) end
                for _, part in ipairs(PageSample.PARTY_PARTS) do collect(out, missing, part, b, "party", scale, cfg) end
            end
        end
        s.missing = missing
        return out
    end
    return s
end

-- The raid: a few tiles in one line

PageSample.RAID_COUNT = 1   -- raid tiles drawn: one, carrying every piece
PageSample.RAID_ZOOM = 3    -- raid tiles are small, so start this much bigger (the strip's Zoom slider)
PageSample.zoom.raid = PageSample.RAID_ZOOM

-- How far a party member's or tile's aura groups, icons and name reach past
-- it: up, down, left, right, in its own units. Only outside spots reach out,
-- past the name tab and portrait ring where present.
function PageSample.GroupReach(cfg, b)
    local up, down, left, right = 0, 0, 0, 0
    local box = ns.AuraGroups.Box(b, cfg)
    local list = {}
    for _, def in ipairs(ns.AuraGroups.DEFS) do
        list[#list + 1] = { b.sampleSet and b.sampleSet[def.key], type(cfg.auras) == "table" and cfg.auras[def.key] }
    end
    for _, key in ipairs(ns.AURA_SLOTS) do
        local slot = b.sampleSet and b.sampleSet.extra and b.sampleSet.extra[key]
        local g = type(cfg.auras) == "table" and cfg.auras[key]
        if slot then
            list[#list + 1] = { slot.debuffs, g }
            list[#list + 1] = { slot.buffs, g }
        end
    end
    for _, e in ipairs(list) do
        local c, g = e[1], e[2]
        if c and c:IsShown() and type(g) == "table" then
            local w, h, gap = c:GetWidth(), c:GetHeight(), ns.Spots.GAP
            local x, y = tonumber(g.x) or 0, tonumber(g.y) or 0
            local s = g.spot or ""
            if s == "above" or s:find("^outtop") then up = math.max(up, h + gap + box.above + y) end
            if s == "below" or s:find("^outbottom") then down = math.max(down, h + gap + box.below - y) end
            if s:find("^out.*left$") then left = math.max(left, w + gap + box.outL - x) end
            if s:find("^out.*right$") then right = math.max(right, w + gap + box.outR + x) end
        end
    end
    -- Marker, crown, role and dispel icons at an outside spot, shown or not,
    -- since AuraGroups.Corners reserves them.
    for _, k in ipairs(ns.AuraGroups.CORNER_ICONS) do
        local s, size = cfg[k[2]], (tonumber(cfg[k[3]]) or 0) + ns.Spots.GAP
        if cfg[k[1]] ~= false and type(s) == "string" then
            if s == "above" or s:find("^outtop") then up = math.max(up, size) end
            if s == "below" or s:find("^outbottom") then down = math.max(down, size) end
            if s:find("^out.*left$") then left = math.max(left, size) end
            if s:find("^out.*right$") then right = math.max(right, size) end
        end
    end
    -- A party member's pet (PartyPets.lua).
    local pu, pd, pl, pr = ns.PartyPets.Reach(b)
    up, down, left, right = math.max(up, pu), math.max(down, pd), math.max(left, pl), math.max(right, pr)
    local pos = cfg.namePos
    if type(pos) == "string" and pos:find("^out") and cfg.showName ~= false then
        local ok, w = pcall(b.nameText.GetStringWidth, b.nameText)
        w = (ok and type(w) == "number" and w or 40) + 4
        if pos:find("left$") then left = math.max(left, w) else right = math.max(right, w) end
    end
    return up, down, left, right
end

local function refreshRaid(s, width, maxH)
    local d = db()
    if not d then return 0 end
    ns.Sample.UseSettings(d)
    -- The size its page edits (Raid.lua's setups by raid size).
    local cfg, text = ns.Raid.Config(d, s.size)
    -- One line across regardless of the raid's own direction, since the strip
    -- is wide and short.
    local line = setmetatable({ direction = "rows", perLine = #s.members, sortBy = "group" }, { __index = cfg })
    local g = ns.Raid.group
    local first = s.members[1]
    s.holder:SetScale(1)
    local w = 2 * Pixel.Snap(first, cfg.width / 2)
    local h = 2 * Pixel.Snap(first, cfg.height / 2)
    g:LayoutSamples(s.members, s.holder, line, text, w, h)
    g:FillSamples(s.members, #s.members, cfg)
    for _, b in ipairs(s.members) do b:SetAlpha(d.raid.enabled == false and PageSample.OFF_ALPHA or 1) end
    local fw, fh = ns.Group.Footprint(line, #s.members, true, w, h)
    s.holder:SetSize(fw, fh)
    local up, down, left, right = PageSample.GroupReach(cfg, first)
    return fit(s.frame, s.holder, fw, fh, left, false, up, down, width, maxH, right, s.Zoom())
end

local function newRaid(parent, size)
    local s = { id = "raid", size = size or 10, members = {}, missing = {} }
    s.frame = CreateFrame("Frame", nil, parent)
    s.holder = CreateFrame("Frame", nil, s.frame)
    zoomable(s)
    for i = 1, PageSample.RAID_COUNT do
        local b = ns.Raid.group:NewSampleButton(s.holder, i, ns.Raid.DressSample)
        b.fullSample = true   -- every piece shows, so each can be dragged
        b:EnableMouse(false)   -- display only, the strip's hotspots take the clicks
        s.members[i] = b
    end
    function s.Refresh(width, maxH) return refreshRaid(s, width, maxH) end
    addable(s, "raid", true)
    -- A size that follows 10 can't be changed here, so there's nothing to drag or add.
    local adds = s.Adds
    function s.Adds()
        if ns.Raid.Locked(s.size) then return {}, {} end
        return adds()
    end
    function s.Parts()
        local out, missing = {}, {}
        if ns.Raid.Locked(s.size) then
            s.missing = missing
            return out
        end
        local scale = s.holder:GetScale()
        for _, b in ipairs(s.members) do
            if b:IsShown() then
                local cfg = db() and (ns.Raid.Config(db(), s.size))
                for _, part in ipairs(PageSample.PARTS) do collect(out, missing, part, b, "raid", scale, cfg) end
                for _, part in ipairs(PageSample.RAID_PARTS) do collect(out, missing, part, b, "raid", scale, cfg) end
            end
        end
        s.missing = missing
        return out
    end
    return s
end

-- The live sample for a unit frames page ("player", "target", ..., "party",
-- "raid") on parent. size is a raid page's size (10, 20 or 40).
function PageSample.New(id, parent, size)
    if id == "party" then return newParty(parent) end
    if id == "raid" then return newRaid(parent, size) end
    return newSingle(id, parent)
end
