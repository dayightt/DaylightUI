-- Classify: decides which category a buff belongs to. Priority, first hit
-- wins: the player's own reassignment; weapon enchants; the built-in seeds
-- (Data.lua); the caster's class when the client says who cast it (and that
-- is remembered, so it still applies after the caster leaves); for a name
-- several seeds share in this language, the player's own class when it is
-- one of them; anything learned earlier; Other.

local _, BL = ...

local Classify = {}
BL.Classify = Classify

Classify.HISTORY_MAX = 200

local OTHER = "other"

local function plainName(entry)
    local name = BL.Plain(entry and entry.name)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- The class of whoever cast this, when it is a group member (not the
-- player or a pet: those cast consumables and self-buffs too, which says
-- nothing about the buff).
local function casterClass(entry)
    local unit = BL.Plain(entry.sourceUnit)
    if type(unit) ~= "string" then return nil end
    if unit == "player" or unit == "vehicle" or string.find(unit, "pet") then return nil end
    local token = BL.ClassToken(unit)
    if token and BL.Categories.Exists(token) then return token end
    return nil
end

function Classify.Resolve(entry)
    local Categories = BL.Categories
    local name = plainName(entry)

    if name and BL.DB.overrides[name] then
        return Categories.Resolve(BL.DB.overrides[name])
    end
    if entry and entry.kind == "weapon" then
        return Categories.Resolve("weapon")
    end
    if not name then return OTHER end

    local seeded = BL.Data.Lookup(name)
    if seeded then return Categories.Resolve(seeded) end

    local learned = casterClass(entry)
    if learned then
        if BL.DB.learned[name] ~= learned then
            BL.DB.learned[name] = learned
            BL.Fire("OVERRIDES_CHANGED")
        end
        return learned
    end
    local shared = BL.Data.Shared(name)
    local mine = shared and BL.ClassToken("player")
    if mine and shared[mine] then
        return Categories.Resolve(mine)
    end
    if BL.DB.learned[name] then
        return Categories.Resolve(BL.DB.learned[name])
    end
    return OTHER
end

function Classify.GetOverride(name)
    if type(name) ~= "string" then return nil end
    return BL.DB.overrides[name]
end

function Classify.Assign(name, categoryId, source)
    if type(name) ~= "string" or name == "" then return false end
    if not BL.Categories.Exists(categoryId) then return false end
    local from = Classify.Resolve({ kind = "aura", name = name })
    BL.DB.overrides[name] = categoryId
    table.insert(BL.DB.history, 1, {
        buffName = name, from = from, to = categoryId, time = BL.Now(), source = source,
    })
    while #BL.DB.history > Classify.HISTORY_MAX do
        table.remove(BL.DB.history)
    end
    BL.Fire("OVERRIDES_CHANGED")
    return true
end

function Classify.History()
    return BL.DB.history
end

function Classify.ClearHistory()
    wipe(BL.DB.history)
    BL.Fire("OVERRIDES_CHANGED")
end
