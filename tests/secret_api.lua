-- Which values the client makes secret, read from the game's own API docs
-- (tests/blizzard/api/*Documentation.lua, fetched by tools/fetch_blizzard.py).
-- The fake game wraps every such function it fakes. While the condition holds,
-- its returns come back as stub.Secret values (a table's fields do, except the
-- ones the docs mark NeverSecret), so code that compares, adds or concatenates
-- them fails in the tests the way it fails in game.
local Blizz = require("blizzard")
-- nested[struct][field] = { struct = name, list = true? }: a returned table's
-- fields that hold other structures (C_DamageMeter's sources and their spells),
-- so the fake game turns their fields secret by their own flags.
local M = { functions = {}, count = 0, nested = {} }

-- Maps a doc flag to when it applies (the game's names, from the RestrictedActions
-- and SecretPredicates docs). "restricted" is combat or any addon restriction except
-- chat. "identity" is a PvP match or a restricted map (an enemy player's class and
-- name in a battleground). "chat" is chat lockdown. Flags that depend on the input
-- already being secret (curves, formatters, secret keys) need no rule, since the
-- input carries it.
M.WHEN = {
    SecretReturns = "always",   -- seen in game: UnitHealth("target") is secret out of combat
    SecretWhenInCombat = "combat",
    SecretWhenUnitStatsRestricted = "restricted",
    SecretWhenUnitAuraRestricted = "restricted",
    SecretWhenCooldownsRestricted = "restricted",
    SecretWhenUnitPowerRestricted = "restricted",
    SecretWhenUnitPowerMaxRestricted = "restricted",
    SecretWhenUnitHealthMaxRestricted = "restricted",
    SecretWhenUnitSpellCastRestricted = "spellcast",   -- only for units other than the player and pet
    SecretWhenUnitThreatValuesRestricted = "threatValues",   -- stub.ThreatSecret, vs a boss
    SecretWhenUnitThreatStateRestricted = "threatState",     -- stub.ThreatSecret, not for your group
    SecretWhenUnitPossessionRestricted = "restricted",
    SecretWhenLossOfControlInfoRestricted = "restricted",
    SecretWhenTotemSlotSecret = "restricted",
    SecretWhenEncounterEvent = "restricted",
    SecretWhenUnitIdentityRestricted = "identity",
    SecretWhenUnitNameIdentityRestricted = "identity",
    SecretWhenUnitComparisonRestricted = "identity",
    SecretInActivePvPMatch = "identity",
    SecretInChatMessagingLockdown = "chat",
}

-- Event-level flags that only events carry. SecretPayloads is read as "while the
-- client is restricted", like SecretReturns on a function. That's an assumption,
-- since the docs say no more.
M.EVENT_WHEN = {
    SecretWhenAurasRestricted = "restricted",
    SecretPayloads = "restricted",
}
-- Flags on one payload argument: only that argument goes secret.
M.FIELD_SECRET = { SecretValue = true, ConditionalSecret = true }

-- events["UNIT_AURA"] = { when = "restricted", plain = { [i] = true } for
--   NeverSecret arguments, only = { [i] = true } when only some arguments
--   go secret (field-level flags) }
M.events = {}
M.eventCount = 0

-- functions["C_UnitAuras.GetAuraDataByIndex"] = { when = "restricted",
--   keep = { [field] = true } for a returned table's NeverSecret fields,
--   plain = { [i] = true } for returns marked NeverSecret }
function M.Load()
    local structs, pending = {}, {}
    local docs = {}
    function docs:AddDocumentationTable(t)
        for _, s in ipairs(t.Tables or {}) do
            local keep, nested = {}, {}
            for _, f in ipairs(s.Fields or {}) do
                if f.NeverSecret then keep[f.Name] = true end
                -- A field holding another structure (or a list of them) has its
                -- own fields go secret by that structure's flags.
                if f.Type == "table" and f.InnerType then
                    nested[f.Name] = { struct = f.InnerType, list = true }
                elseif type(f.Type) == "string" then
                    nested[f.Name] = { struct = f.Type }
                end
            end
            structs[s.Name] = keep
            M.nested[s.Name] = nested
        end
        for _, e in ipairs(t.Events or {}) do
            local when
            for flag, w in pairs(M.WHEN) do if e[flag] then when = w end end
            for flag, w in pairs(M.EVENT_WHEN) do if e[flag] then when = w end end
            local plain, only = {}, nil
            for i, a in ipairs(e.Payload or {}) do
                if a.NeverSecret then plain[i] = true end
                for flag in pairs(M.FIELD_SECRET) do
                    if a[flag] then only = only or {}; only[i] = true end
                end
            end
            if (when or only) and e.LiteralName then
                M.events[e.LiteralName] = { when = when or "restricted", plain = plain, only = (not when) and only or nil }
                M.eventCount = M.eventCount + 1
            end
        end
        for _, fn in ipairs(t.Functions or {}) do
            local when
            for flag, w in pairs(M.WHEN) do if fn[flag] then when = w end end
            if when and not fn.ReturnsNeverSecret then
                local ns = fn.Namespace or t.Namespace
                local name = (ns and ns ~= "") and (ns .. "." .. fn.Name) or fn.Name
                pending[#pending + 1] = { name = name, when = when, fn = fn }
            end
        end
    end
    local env = setmetatable({ APIDocumentation = docs }, { __index = function() return Blizz.INERT end })
    for file in Blizz.List("", "api/") do
        local chunk = loadfile(Blizz.DIR .. "api/" .. file)
        if chunk then setfenv(chunk, env); pcall(chunk) end
    end
    for _, p in ipairs(pending) do
        local plain, keep, struct = {}, nil, nil
        for i, r in ipairs(p.fn.Returns or {}) do
            if r.NeverSecret then plain[i] = true end
            if structs[r.Type] then keep, struct = structs[r.Type], r.Type end
        end
        M.functions[p.name] = { when = p.when, keep = keep or {}, plain = plain, struct = struct }
        M.count = M.count + 1
    end
    -- Only nested fields whose type is a known structure count.
    for name, nested in pairs(M.nested) do
        for field, n in pairs(nested) do
            if not structs[n.struct] then nested[field] = nil end
        end
        if next(nested) == nil then M.nested[name] = nil end
    end
    M.structs = structs
    return M.count
end

return M
