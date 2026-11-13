-- Party frames. A secure group header creates, sorts and places the buttons
-- (Group.lua). Each is a smaller version of the player frame: name tab,
-- portrait ring, angled end, power bar, and the aura groups from AuraGroups.lua
-- placed like the raid tiles'. Settings decide which pieces show, so the same
-- buttons work as bars or as square tiles (the Healer setup). You can be one of
-- them (hideSelf off). They hide in a raid, where the raid frames show everyone
-- (and in a party too, when "Use raid frames in a party" is on).

local _, ns = ...
local DUI = DaylightUI

local Party = {}
ns.Party = Party

Party.SPEC = {
    group = "party", power = true, slant = "right", tab = true, marker = true, portrait = true,
    range = true, groupThreat = true, role = true, cornerIcons = true, pets = true, ribbon = true,
}

local function db() return ns.module and ns.module.db end

-- Number of buttons: four without you, five with you. "Show when alone" keeps
-- your own frame up while you're not in a group.
function Party.ShowsSolo(cfg) return type(cfg) == "table" and cfg.showSolo == true end

function Party.Count(cfg) return cfg.hideSelf == true and 4 or 5 end

-- The holder's default y (TOPLEFT on UIParent's LEFT), chosen so the first
-- frame's center sits at 160 whatever its height, where party1 used to be,
-- leaving room for Ribbon's name row above it (Group:Pads).
function Party.DefaultY(cfg)
    local up = Party.group and Party.group:Pads(cfg) or 0
    return 160 + cfg.height / 2 + up
end

-- The members test mode shows, after you when you're shown.
Party.SAMPLES = {
    { name = "Kaladin", class = "WARRIOR", health = 79, healthValue = 2900, power = 35, powerToken = "RAGE",
      portraitClass = "WARRIOR", level = 20, leader = true, threat = "aggro", pvp = true, role = "TANK" },
    { name = "Lift", class = "PRIEST", health = 100, healthValue = 1900, power = 85, powerValue = 2040, powerToken = "MANA",
      portraitClass = "PRIEST", level = 20, heals = 10, role = "HEALER", dispel = "Magic" },
    { name = "Shallan", class = "WARLOCK", health = 54, healthValue = 1600, power = 40, powerValue = 1040, powerToken = "MANA",
      portraitClass = "WARLOCK", level = 19, marker = 3, role = "DAMAGER", target = true },
    { name = "Jasnah", class = "MAGE", health = 88, healthValue = 1700, power = 72, powerValue = 1800, powerToken = "MANA",
      portraitClass = "MAGE", level = 20, absorbs = 15, role = "DAMAGER" },
}

-- You as a sample, with your own name and class.
Party.YOU = { health = 92, healthValue = 2400, power = 64, powerValue = 1600, powerToken = "MANA", level = 20, role = "HEALER", you = true }

function Party.You() return ns.UF.You("party", Party.YOU, "PRIEST") end

-- Sample member i, in the order the header would sort them: by role (tank,
-- healer, damage), then party order within a role.
function Party.SampleFor(i, cfg)
    local withYou = cfg ~= nil and cfg.hideSelf ~= true
    if cfg and cfg.sortBy == "role" then
        local list, at, rank = {}, {}, ns.Raid.ROLE_RANK
        if withYou then list[1] = Party.You() end
        for _, s in ipairs(Party.SAMPLES) do list[#list + 1] = s end
        for k, s in ipairs(list) do at[s] = k end
        table.sort(list, function(a, b)
            local ra, rb = rank[a.role], rank[b.role]
            if ra ~= rb then return ra < rb end
            return at[a] < at[b]
        end)
        return list[i]
    end
    if withYou and i == 1 then return Party.You() end
    return Party.SAMPLES[withYou and i - 1 or i]
end

-- The Party page's single preview member. Every piece that can show is on
-- (crown, role, marker, dispel, PvP, ready check), but no aggro ring.
function Party.FullSample()
    local s = {}
    for k, v in pairs(Party.SAMPLES[1]) do s[k] = v end
    s.threat, s.marker, s.dispel, s.target, s.ready = nil, 8, "Magic", true, "ready"
    return s
end

-- Sample buttons (test mode, the Party page preview) carry the aura groups on
-- stand-ins, placed and filled from the settings. Their pets too (PartyPets.lua).
-- A real button gets its pet once pets are turned on.
function Party.DressSample(b)
    if b.preview then
        b.sampleSet = ns.AuraGroups.PlainSet(b)
        ns.PartyPets.DressSample(b)
        ns.PartyCasts.Make(b)
    end
end

function Party.ShowSample(b, i, cfg)
    local box, n = ns.AuraGroups.Box(b, cfg), not b.fullSample and i or nil
    ns.AuraGroups.ShowSample(b.sampleSet, b, cfg.auras, box, n)
    ns.Indicators.ShowSample(b.sampleSet, b, cfg.indicators, box, n)
    ns.PartyPets.ShowSample(b)
    -- The healer is casting, so the page's preview shows every piece.
    ns.PartyCasts.ShowSample(b, b.fullSample or b.test == Party.SAMPLES[2])
end

function Party.HideSample(b)
    ns.AuraGroups.HideSample(b.sampleSet)
    ns.Indicators.HideSample(b.sampleSet)
    ns.PartyPets.HideSample(b)
    ns.PartyCasts.HideSample(b)
end

Party.group = ns.Group.New({
    key = "party", name = "DaylightUIParty", spec = Party.SPEC, maxCount = 5,
    auraGroups = true,
    attrs = { showRaid = false, showParty = true, showPlayer = false, showSolo = false },
    config = function()
        local d = db()
        if not d then return nil end
        return d.party, d.partyText, d
    end,
    count = Party.Count,
    previewCount = Party.Count,
    -- When alone, the party frames show you if "Show when alone" is on. The
    -- header's showSolo shows the player regardless of showPlayer.
    visibility = function(cfg)
        local d = db()
        if d and ns.Raid.InParty(d.raid) then return "hide" end
        local alone = Party.ShowsSolo(cfg) and "show" or "hide"
        return ns.Group.IN_RAID .. " hide; " .. ns.Group.IN_PARTY .. " show; " .. alone
    end,
    solo = function(cfg) return Party.ShowsSolo(cfg) end,
    hideInTest = function() return DUI.testRaid == true end,
    hideHeaderInTest = true,
    sampleFor = Party.SampleFor,
    fullSample = function() return Party.FullSample() end,
    sampleUnit = function(i) return "party" .. i end,
    dress = function(b) Party.DressSample(b) end,
    showSample = function(b, i, cfg) Party.ShowSample(b, i, cfg) end,
    hideSample = function(b) Party.HideSample(b) end,
    layoutButton = function(b)
        ns.PartyPets.Layout(b)
        ns.PartyCasts.Layout(b)
    end,
})
Party.buttons = Party.group.buttons

function Party.Create()
    local holder = Party.group:Create()
    Party.holder, Party.header = holder, Party.group.header
    return holder
end

function Party.CreatePreview()
    Party.group:CreatePreview()
    Party.preview = Party.group.preview
end

local function preview(on)
    local d = db()
    if not d then return end
    -- Alpha and samples now (allowed in combat), the layout afterwards.
    Party.group:ApplyTestAlpha()
    Party.group:ShowPreview(on and Party.group:IsOn(d.party))
    DUI.AfterCombat(function() Party.group:Layout(d.party, d.partyText, d.range) end, "party:preview")
end
DUI.On("TestModeChanged", preview)

DUI.RegisterTestPart("party", "Party", 60, function()
    local d = db()
    return d ~= nil and Party.group:IsOn(d.party) == true
end)
DUI.On("TestPartChanged", function(key) if key == "party" then preview(DUI.testMode) end end)
