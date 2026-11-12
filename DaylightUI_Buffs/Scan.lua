-- Scan: /dui buffs scan walks the group's buffs and reports the ones the addon
-- has no category for, with the caster's class as a suggestion; /dui buffs auras
-- dumps the player's own auras raw for troubleshooting.

local _, BL = ...
local L = DaylightUI.L

local Scan = {}
BL.Scan = Scan

local function groupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    return units
end

local function isRecognised(name)
    if BL.DB.overrides[name] then return true end
    if BL.Data.Lookup(name) or BL.Data.Shared(name) then return true end
    if BL.DB.learned[name] then return true end
    return false
end

-- Returns a list of { unit, name, buffName, sourceClass }, one per distinct
-- unrecognized buff name; nil when the client refuses to show group auras.
function Scan.Group()
    local report, seen = {}, {}
    local unreadable = false
    for _, unit in ipairs(groupUnits()) do
        if UnitExists(unit) then
            for index = 1, BL.Auras.MAX do
                -- The client raises rather than returning secrets in combat.
                local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
                if not ok then
                    unreadable = true
                    break
                end
                if data == nil then break end
                local plain = BL.PlainTable(data)
                if not plain then
                    unreadable = true
                    break
                end
                local name = BL.Plain(plain.name)
                if type(name) == "string" and not seen[name] and not isRecognised(name) then
                    seen[name] = true
                    local source = BL.Plain(plain.sourceUnit)
                    local sourceClass = type(source) == "string" and BL.ClassToken(source) or nil
                    report[#report + 1] = {
                        unit = unit,
                        name = BL.Plain(UnitName(unit)),
                        buffName = name,
                        sourceClass = sourceClass,
                    }
                end
            end
        end
    end
    if unreadable and #report == 0 then return nil end
    return report
end

function Scan.PrintGroup()
    local report = Scan.Group()
    if report == nil then
        BL.Print(L["Group auras are not readable right now (restricted by the client). Try again out of combat."])
        return
    end
    if #report == 0 then
        BL.Print(L["No unrecognized buffs on the group."])
        return
    end
    BL.Print(#report == 1 and L["1 unrecognized buff on the group:"]
        or string.format(L["%d unrecognized buffs on the group:"], #report))
    for _, r in ipairs(report) do
        local on = tostring(r.name or r.unit)
        if r.sourceClass then
            BL.Print(string.format(L["  %s (on %s) - caster is a %s"], r.buffName, on, r.sourceClass))
        else
            BL.Print(string.format(L["  %s (on %s)"], r.buffName, on))
        end
    end
end

local function describe(e)
    local left = e.timed and BL.FormatTime(e.expirationTime - BL.Clock()) or "no timer"
    return string.format("  [%d] %s  id=%s  %s  %s  src=%s  x%d",
        e.index, tostring(e.name), tostring(e.spellId), tostring(e.dispelName or "-"), left,
        tostring(e.sourceUnit or "-"), e.applications or 0)
end

function Scan.PrintPlayer()
    local buffs = BL.Auras.Collect("HELPFUL")
    local debuffs = BL.Auras.Collect("HARMFUL")
    BL.Print(string.format("%d buffs:", #buffs))
    for _, e in ipairs(buffs) do BL.Print(describe(e)) end
    BL.Print(string.format("%d debuffs:", #debuffs))
    for _, e in ipairs(debuffs) do BL.Print(describe(e)) end
    local weapons = BL.Auras.CollectWeapons()
    if #weapons > 0 then
        BL.Print(string.format("%d weapon enchants:", #weapons))
        for _, e in ipairs(weapons) do
            BL.Print(string.format("  slot %d %s %s", e.slot, tostring(e.name), BL.FormatTime(e.expirationTime - BL.Clock())))
        end
    end
end
