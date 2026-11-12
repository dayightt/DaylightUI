-- The last moments before a death, read from C_DeathRecap by the death's
-- recap ID (never secret). Each hit or heal, its timing, source, amount and
-- the health left after it, ending on the killing blow.
--
-- The game lists events newest first. They are reversed here so they read
-- in order. A recap that is still secret waits for the fight to end.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local DeathLog = {}
ns.DeathLog = DeathLog

DeathLog.MAX = 12             -- events kept, the most recent

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Every field read below. If any is secret, wait.
local FIELDS = { "event", "timestamp", "spellId", "spellName", "sourceName", "hideCaster", "amount", "overkill", "currentHP" }

local function spellOf(e)
    local name, icon = e.spellName, nil
    local id = e.spellId
    if type(id) == "number" and C_Spell then
        if C_Spell.GetSpellTexture then
            local ok, tex = pcall(C_Spell.GetSpellTexture, id)
            if ok then icon = tex end
        end
        if type(name) == "nil" and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok then name = n end
        end
    end
    local event = type(e.event) == "string" and e.event or ""
    if event == "SWING_DAMAGE" or type(name) ~= "string" or name == "" then name = L["Melee"] end
    return name, icon
end

-- Returns the events oldest first plus max health, or nil and a reason.
function DeathLog.Read(recapID)
    if type(recapID) ~= "number" or isSecret(recapID) or recapID <= 0 then return nil end
    local R = C_DeathRecap
    if not (R and R.GetRecapEvents) then return nil end
    if R.HasRecapEvents then
        local ok, has = pcall(R.HasRecapEvents, recapID)
        if ok and (isSecret(has) or has ~= true) then return nil end
    end
    local ok, events = pcall(R.GetRecapEvents, recapID)
    if not ok or type(events) ~= "table" or #events == 0 then return nil end
    local okM, maxHealth = pcall(R.GetRecapMaxHealth or error, recapID)
    if not okM or isSecret(maxHealth) or type(maxHealth) ~= "number" then maxHealth = nil end
    for _, e in ipairs(events) do
        if type(e) ~= "table" then return nil end
        for _, k in ipairs(FIELDS) do
            if isSecret(e[k]) then return nil, ns.Breakdown.WAIT end
        end
    end
    local last = 0
    for _, e in ipairs(events) do
        if type(e.timestamp) == "number" and e.timestamp > last then last = e.timestamp end
    end
    local out = {}
    local first = math.min(#events, DeathLog.MAX)
    for i = first, 1, -1 do
        local e = events[i]
        local spell, icon = spellOf(e)
        local event = type(e.event) == "string" and e.event or ""
        local hp
        if maxHealth and maxHealth > 0 and type(e.currentHP) == "number" then
            hp = math.max(0, math.min(1, e.currentHP / maxHealth))
        end
        local overkill = type(e.overkill) == "number" and e.overkill > 0 and e.overkill or nil
        out[#out + 1] = {
            ago = type(e.timestamp) == "number" and (last - e.timestamp) or 0,
            spell = spell, icon = icon,
            source = type(e.sourceName) == "string" and not e.hideCaster and e.sourceName or nil,
            amount = type(e.amount) == "number" and e.amount or 0,
            heal = event:find("_HEAL", 1, true) ~= nil,
            hp = hp, overkill = overkill, killing = i == 1,
        }
    end
    return { events = out, maxHealth = maxHealth }
end
