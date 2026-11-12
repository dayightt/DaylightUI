-- Private auras are boss debuffs addon code can never read. The client draws
-- them itself on an anchor we lend it (C_UnitAuras.AddPrivateAuraAnchor), one
-- anchor per aura index. Container mode needs a handshake only Blizzard's
-- frames can do, so this uses single-icon mode. Blizzard's raid, party and
-- debuff frames normally carry these anchors; we hide those, so ours must.
--
-- A set is a row of plain slot frames that the caller positions. Anchors can
-- only be added and removed out of combat, so PA.Want records what the set
-- should show and the change lands now or when the fight ends. Nothing here
-- reads an aura.

local _, DUI = ...
local Style = DUI.Style

local PA = {}
DUI.PrivateAuras = PA

-- A stand-in icon for samples (test mode, the options previews).
PA.SAMPLE_ICON = "Interface\\Icons\\Spell_Shadow_DeathPact"
-- The client's debuff red, softened, around the sample.
PA.SAMPLE_EDGE = { 0.62, 0.12, 0.12 }

function PA.Available()
    return type(C_UnitAuras) == "table" and type(C_UnitAuras.AddPrivateAuraAnchor) == "function"
        and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function"
end

-- `count` slots on parent. opts.cooldown shows the swipe (default on),
-- opts.numbers shows the client's countdown on it.
function PA.New(parent, count, opts)
    local set = { slots = {}, ids = {}, opts = opts or {} }
    set.key = "privateauras:" .. tostring(set)
    for i = 1, count do
        local f = CreateFrame("Frame", nil, parent)
        f:SetSize(1, 1)
        f:EnableMouse(false)
        set.slots[i] = f
    end
    return set
end

local function args(set, slot, index, unit, size)
    local o = set.opts
    return {
        unitToken = unit,
        auraIndex = index,
        parent = slot,
        showCooldownFrame = o.cooldown ~= false,
        showCooldownEdge = false,
        showCountdownNumbers = o.numbers == true,
        showDispelIcon = false,
        isContainer = false,
        iconInfo = {
            iconAnchor = { point = "CENTER", relativeTo = slot, relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
            iconWidth = size,
            iconHeight = size,
        },
    }
end

-- Releases every anchor the set holds. Returns false if the client kept one;
-- it stays listed and is released later.
function PA.Release(set)
    local all = true
    for i, id in pairs(set.ids) do
        if pcall(C_UnitAuras.RemovePrivateAuraAnchor, id) then set.ids[i] = nil else all = false end
    end
    set.unit, set.size = nil, nil
    return all
end

-- The client refused a change. Try again once its restrictions lift.
local function later(set)
    if DUI.Restricted() then
        DUI.AfterRestrictions(function() PA.Apply(set) end, set.key .. ":held")
    end
end

-- Syncs the client's anchors with what the set wants. Out of combat only
-- (PA.Want queues it). A refused change is retried when restrictions lift, and
-- an old anchor the client won't release blocks a new one from stacking on it.
function PA.Apply(set)
    if not PA.Available() then return end
    local unit, size = set.wantUnit, set.wantSize
    if type(unit) ~= "string" or type(size) ~= "number" or size <= 0 then unit, size = nil, nil end
    if set.unit == unit and set.size == size and (unit == nil) == (next(set.ids) == nil) then return end
    if not PA.Release(set) then return later(set) end
    if not unit then return end
    for i, slot in ipairs(set.slots) do
        local ok, id = pcall(C_UnitAuras.AddPrivateAuraAnchor, args(set, slot, i, unit, size))
        if not ok then
            PA.Release(set)
            return later(set)
        end
        if type(id) == "number" then set.ids[i] = id end
    end
    set.unit, set.size = unit, size
end

-- What the set should show: unit's private auras at size (nil unit shows
-- none). Slots resize now, anchors now or after combat.
function PA.Want(set, unit, size)
    if not set then return end
    if type(size) == "number" and size > 0 then
        for _, slot in ipairs(set.slots) do slot:SetSize(size, size) end
    end
    set.wantUnit, set.wantSize = unit, size
    DUI.AfterCombat(function() PA.Apply(set) end, set.key)
end

-- How many anchors the set holds now.
function PA.Count(set)
    local n = 0
    for _ in pairs(set and set.ids or {}) do n = n + 1 end
    return n
end

-- A sample icon in each of the first n slots (0 hides them) to show where a
-- boss debuff would appear. Samples never touch the client's anchors.
function PA.ShowSample(set, n)
    if not set then return end
    for i, slot in ipairs(set.slots) do
        local s = slot.sample
        if i <= (n or 0) then
            if not s then
                s = CreateFrame("Frame", nil, slot)
                s:SetAllPoints(slot)
                s.edge = s:CreateTexture(nil, "BACKGROUND")
                s.edge:SetAllPoints(s)
                s.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
                local c = PA.SAMPLE_EDGE
                s.edge:SetVertexColor(Style.Soften(c[1], c[2], c[3]))
                s.icon = s:CreateTexture(nil, "ARTWORK")
                s.icon:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
                s.icon:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
                s.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                s.icon:SetTexture(PA.SAMPLE_ICON)
                slot.sample = s
            end
            s:Show()
        elseif s then
            s:Hide()
        end
    end
end
