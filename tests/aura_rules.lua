-- Whether the client's aura container would show an aura in a group: the game's
-- rule, copied from Blizzard_AuraContainerUtil.lua (CanApplyIdentityCandidateFilters
-- and DoesAuraPassCandidateFilters), only the parts the addon's groups use. The fake
-- container only records groups, so a test that needs to know what really shows
-- asks here.
--
-- group: what AddAuraGroup got, { filter, opts }.
-- aura: { spellId, harmful, duration, mine, cc, canApply, fromPlayer, neverSecret, boss,
-- nameplateOnly, secret }. secret: its data is secret (an enemy's in a fight or
-- under restrictions), so a candidate filter that reads it rejects the aura, as
-- EllesmereUI saw in battlegrounds; filter strings are judged by the client.
-- unit: { canAssist, groupMember } (groupMember: you, your group, or their pets:
-- UnitIsPlayerControlledOrGroupMember, which the game's own comment says means
-- "the active player / any group members (or their pets)", never an enemy player).

local function identityAllowed(unit, aura)
    if aura.neverSecret then return true end
    if not aura.harmful and unit.groupMember then return true end
    if aura.harmful and unit.canAssist then return false end
    if not aura.harmful and not unit.canAssist then return false end
    return true
end

local function passesString(filter, aura)
    local wants = {}
    for word in filter:gmatch("[^|]+") do wants[word] = true end
    if wants.HARMFUL and not aura.harmful then return false end
    if wants.HELPFUL and aura.harmful then return false end
    if wants.PLAYER and not aura.mine then return false end
    if wants["!PLAYER"] and aura.mine then return false end
    if wants["!CROWD_CONTROL"] and aura.cc then return false end
    if aura.nameplateOnly and not wants.INCLUDE_NAME_PLATE_ONLY then return false end
    return true
end

return function(group, unit, aura)
    if not passesString(group.filter, aura) then return false end
    local cand = group.opts and group.opts.candidateFilters
    if not cand then return true end
    if identityAllowed(unit, aura) then
        if cand.excludeSpellIDs and cand.excludeSpellIDs[aura.spellId] then return false end
        if cand.includeSpellIDs and not cand.includeSpellIDs[aura.spellId] then return false end
    elseif cand.includeSpellIDs then
        -- "Testing exact spell IDs isn't permitted on this unit."
        return false
    end
    if aura.secret and (cand.canApplyAura ~= nil or cand.isFromPlayerOrPlayerPet ~= nil or cand.isBossAura ~= nil
                        or cand.maxDuration) then
        return false
    end
    if cand.canApplyAura ~= nil and (aura.canApply == true) ~= cand.canApplyAura then return false end
    if cand.isFromPlayerOrPlayerPet ~= nil and (aura.fromPlayer == true) ~= cand.isFromPlayerOrPlayerPet then return false end
    if cand.isBossAura ~= nil and (aura.boss == true) ~= cand.isBossAura then return false end
    if cand.maxDuration and (aura.duration > cand.maxDuration or aura.duration == 0) then return false end
    return true
end
