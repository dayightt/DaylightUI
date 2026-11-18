-- Raid pets: one block of tiles for the raid's pets, after the last raid group.
-- Off by default (raid.showPets, one switch for every raid size).
--
-- The game's pet header (SecureGroupPetHeaderTemplate) lists the pets and keeps
-- them clickable in combat, built by the group engine (Group.lua) like the raid.
-- The tiles wear the raid's settings for the size shown, so they match the raid
-- tiles and share its mover scale, test part and fade. "Show groups up to"
-- filters them by their owner's group, and "Sort frames by" orders them by their
-- owner's class or name; the pet header can't sort by assigned role, so the
-- role sorts (and Group) keep them by their owner's group. Tiles stay the
-- friendly green, so pets read apart from players, with the owner's name in a
-- small line under the pet's (<Owner>).
--
-- The block has no mover of its own. Its holder hangs off the raid header's far
-- edge, which the header sizes to the members shown, so the pets follow a
-- small raid instead of the room kept for eight groups.

local _, ns = ...
local DUI = DaylightUI
local UF = ns.UF
local Raid = ns.Raid

local RP = {}
ns.RaidPets = RP

-- A raid tile (Raid.SPEC) without the parts a pet never has.
RP.SPEC = {}
for k, v in pairs(Raid.SPEC) do RP.SPEC[k] = v end
RP.SPEC.role, RP.SPEC.leaderIcon, RP.SPEC.groupThreat = nil, nil, nil

-- The pet header's sorting for each "Sort frames by": class and name by the
-- owner's; anything else by the owner's group.
local G = ns.Group
RP.SORT_ATTRS = {
    class = G.SORT_ATTRS.class,
    name = G.SORT_ATTRS.name,
    default = { groupBy = "GROUP", groupingOrder = "1,2,3,4,5,6,7,8", sortMethod = "INDEX" },
}

RP.SAMPLES = {
    { name = "Wolf", owner = "Rock", powerToken = "FOCUS" }, { name = "Imp", owner = "Jasnah", powerToken = "ENERGY" },
    { name = "Voidwalker", owner = "Shallan", powerToken = "ENERGY" }, { name = "Cat", owner = "Teft", powerToken = "FOCUS" },
    { name = "Felhunter", owner = "Navani", powerToken = "ENERGY" }, { name = "Boar", owner = "Sigzil", powerToken = "FOCUS" },
}
RP.OWNER_SIZE = DUI.Style.SIZE.tiny   -- the owner line under the pet's name

local function db() return ns.module and ns.module.db end

-- The pets show: raid frames on and their switch on.
function RP.IsOn()
    local d = db()
    return d ~= nil and d.raid.enabled == true and d.raid.showPets == true
end

function RP.SampleFor(i)
    local s = RP.SAMPLES[(i - 1) % #RP.SAMPLES + 1]
    local hp = 100 - ((i * 29) % 50)
    return { name = s.name, owner = s.owner, reaction = 5, health = hp, healthValue = hp * 20, power = 70,
             powerValue = 70, powerToken = s.powerToken }
end

-- The owner of a group pet's unit: raidpet3 -> raid3, partypet2 -> party2, pet -> player.
function RP.OwnerOf(unit)
    if type(unit) ~= "string" then return nil end
    if unit == "pet" then return "player" end
    local kind, n = unit:match("^(%a+)pet(%d+)$")
    if kind == "raid" or kind == "party" then return kind .. n end
end

-- The owner line under a pet tile's name: <Owner>, from the owner's unit (a
-- sample's from its sample), or <Unknown> when the owner can't be found. The
-- name can be secret, so it only goes to SetFormattedText.
function RP.PaintOwner(b)
    local fs = b.ownerText
    if not fs then return end
    local name
    if b.test then
        name = b.test.owner
    else
        local owner = RP.OwnerOf(b.unitToken)
        if owner and UnitExists(owner) then name = DUI.UnitName(owner, "raid") end
    end
    if type(name) == "nil" then name = DUI.L["Unknown"] end
    fs:SetFormattedText("<%s>", name)
    fs:Show()
end

-- Gives a pet tile (real or sample) its owner line, under its name.
local function dressOwner(b)
    local fs = DUI.Style.Text(b.nameText:GetParent(), RP.OWNER_SIZE, "CENTER")
    fs:SetPoint("TOP", b.nameText, "BOTTOM", 0, -1)
    DUI.Style.InkText(fs, "LABEL")
    fs:Hide()
    b.ownerText = fs
    if not b.preview then
        b:HookScript("OnAttributeChanged", function(self, name)
            if name == "unit" then RP.PaintOwner(self) end
        end)
    end
end

RP.group = ns.Group.New({
    key = "raidPet", name = "DaylightUIRaidPet", spec = RP.SPEC, maxCount = Raid.GROUPS * Raid.PER_GROUP,
    template = "SecureGroupPetHeaderTemplate", home = "raid", apiKind = "partypet", sortAttrs = RP.SORT_ATTRS,
    auraGroups = true,
    attrs = { showRaid = true, showParty = false, showPlayer = true, showSolo = false,
              useOwnerUnit = false, filterOnPet = false },
    config = function()
        local d = db()
        if not d then return nil end
        local key = Raid.laidKey or Raid.KeyFor(d, Raid.ShownSize())
        if type(d[key]) ~= "table" then key = "raid" end
        return d[key], d[key .. "Text"], d
    end,
    isOn = function() return RP.IsOn() end,
    -- The holder only carries the tiles (no handle), so one line is room enough.
    count = function() return Raid.PER_GROUP end,
    previewCount = function() return #RP.SAMPLES end,
    previewMax = #RP.SAMPLES,
    hideInTest = function() return not RP.IsOn() end,
    wantsPreview = function() return RP.IsOn() end,
    visibility = function()
        local G = ns.Group
        return G.IN_RAID .. (Raid.InParty(db().raid) and G.IN_PARTY or "") .. " show; hide"
    end,
    dress = dressOwner,
    layoutButton = function(b) RP.PaintOwner(b) end,   -- also its first paint, once it has a unit
    showSample = function(b) RP.PaintOwner(b) end,
    hideSample = function(b) if b.ownerText then b.ownerText:Hide() end end,
    sampleFor = function(i) return RP.SampleFor(i) end,
    sampleUnit = function(i) return "raidpet" .. i end,
})
RP.buttons = RP.group.buttons

function RP.Create()
    local holder = RP.group:Create()
    RP.holder, RP.header = holder, RP.group.header
    RP.group:CreatePreview()
    return holder
end

-- What the block hangs off: the raid header (sized to its members), the last
-- shown group's header with "Group, then role", or the raid holder while test
-- mode shows the sample raid.
local function anchorOf(cfg)
    local g = Raid.group
    if g:Previewing() then return Raid.holder, true end
    if g:Split(cfg) then return g.headers[ns.Group.GroupsShown(cfg, #g.headers)] or Raid.holder, false end
    return g.header, false
end

-- Puts the block past the raid's far edge, groupSpacing away: beside the last
-- column, or under the last row. Protected, out of combat only.
function RP.Place(cfg)
    local holder = RP.holder
    local to, isHolder = anchorOf(cfg)
    if not (holder and to) then return end
    local G = ns.Group
    local corner = G.Corner(cfg)
    local up, left, gap = cfg.growUp == true, cfg.growLeft == true, cfg.groupSpacing
    holder:ClearAllPoints()
    if G.Direction(cfg) == "rows" then
        local v = up and "TOP" or "BOTTOM"
        holder:SetPoint(corner, to, v .. (left and "RIGHT" or "LEFT"), 0, up and gap or -gap)
    else
        -- Beside a header, the block's own reach above (or below) its tiles
        -- would push them off the raid's line, so it's taken back.
        local dy = 0
        if not isHolder then dy = up and -(holder.padDown or 0) or (holder.padUp or 0) end
        local v = up and "BOTTOM" or "TOP"
        holder:SetPoint(corner, to, v .. (left and "LEFT" or "RIGHT"), left and -gap or gap, dy)
    end
end

-- Lays the block out with the raid. Protected, use DUI.AfterCombat.
function RP.Layout(cfg, text, range)
    local d = db()
    if not (d and RP.holder) then return end
    local inParty = Raid.InParty(d.raid)
    RP.header:SetAttribute("showParty", inParty)
    RP.group:Layout(cfg, text, range)
    RP.holder:SetFrameStrata(ns.StrataOf(d.raid))
    RP.Place(cfg)
end

-- A pet came or went, or the roster moved owners around: every owner line again.
local function paintAll()
    for _, b in ipairs(RP.buttons) do RP.PaintOwner(b) end
end
DUI.RegisterEvent("GROUP_ROSTER_UPDATE", paintAll)
DUI.RegisterEvent("UNIT_PET", paintAll)
DUI.RegisterEvent("UNIT_NAME_UPDATE", paintAll)
