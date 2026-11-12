local stub = require("stub")

-- The buff categories' logic (ported with the buff bars): loaded with the
-- core and logged in, as the client does.
local function loadBL(opts)
    stub.Load({ buffs = true, before = opts and opts.before })
    return stub.buffs
end

T.test("every seed and pattern points at a shipped category id; English names are unique", function()
    local BL = loadBL()
    local valid = {}
    for _, def in ipairs(BL.Categories.DEFAULTS) do valid[def.id] = true end
    local n, ids, seen = 0, 0, {}
    for cat, list in pairs(BL.SEED_SPELLS) do
        T.truthy(valid[cat], "SEED_SPELLS." .. tostring(cat))
        for _, seed in ipairs(list) do
            T.eq(type(seed[1]), "string", "a seed starts with its English name")
            T.isnil(seen[seed[1]], "one seed per English name: " .. tostring(seed[1]))
            seen[seed[1]] = cat
            for i = 2, #seed do
                T.eq(type(seed[i]), "number", seed[1] .. " id " .. i)
                ids = ids + 1
            end
            n = n + 1
        end
    end
    T.truthy(n > 200, "seed table is substantial: " .. n)
    T.truthy(ids > n * 0.8, "nearly every seed has a spell id: " .. ids .. " for " .. n)
    for i, entry in ipairs(BL.SEED_PATTERNS) do
        T.eq(type(entry[1]), "string", "pattern " .. i)
        T.truthy(valid[entry[2]], "pattern " .. i .. " -> " .. tostring(entry[2]))
    end
end)

T.test("Lookup: exact match beats patterns, patterns catch families, unknown is nil", function()
    local BL = loadBL()
    T.eq(BL.Data.Lookup("Arcane Intellect"), "mage")
    T.eq(BL.Data.Lookup("Power Word: Fortitude"), "priest")
    T.eq(BL.Data.Lookup("Rallying Cry of the Dragonslayer"), "world")
    T.eq(BL.Data.Lookup("Elixir of the Mongoose"), "consumable")
    T.eq(BL.Data.Lookup("Elixir of Something New"), "consumable", "pattern")
    T.eq(BL.Data.Lookup("Flask of Whatever"), "consumable", "pattern")
    T.eq(BL.Data.Lookup("Sayge's Dark Fortune of Damage"), "world", "pattern")
    T.eq(BL.Data.Lookup("Dense Sharpening Stone"), "weapon", "pattern")
    T.eq(BL.Data.Lookup("Brilliant Wizard Oil"), "weapon", "pattern")
    T.isnil(BL.Data.Lookup("Totally Unknown Buff"))
    T.isnil(BL.Data.Lookup(nil))
    T.isnil(BL.Data.Lookup(42))
end)

T.test("Lookup: an explicit seed wins over a pattern that would also match", function()
    local BL = loadBL()
    -- " Oil$" says weapon; Shadow Oil is seeded as a consumable.
    T.eq(BL.Data.Lookup("Shadow Oil"), "consumable")
end)

-- The client names the seeds' spell ids in its own language (C_Spell.GetSpellName).
local function speak(BL, names)
    local old = C_Spell.GetSpellName
    C_Spell.GetSpellName = function(id) return names[id] end
    BL.Data.Forget()
    return function() C_Spell.GetSpellName = old; BL.Data.Forget() end
end

T.test("Lookup: another language's buff names find their category through the spell ids", function()
    local BL = loadBL()
    local done = speak(BL, { [1243] = "Machtwort: Seelenst\195\164rke", [1459] = "Arkane Intelligenz" })
    T.eq(BL.Data.Lookup("Machtwort: Seelenst\195\164rke"), "priest")
    T.eq(BL.Data.Lookup("Arkane Intelligenz"), "mage")
    T.eq(BL.Data.Lookup("Power Word: Fortitude"), "priest", "the English name still works")
    T.eq(BL.Classify.Resolve({ kind = "aura", name = "Arkane Intelligenz", sourceUnit = "player" }), "mage")
    BL.DB.spells[1459] = "Arkane Intelligenz"
    BL.Fire("SPELLS_CHANGED")
    T.truthy(BL.Spells.Sets().byCategory.mage[1459], "the bar's mage group takes the id")
    done()
end)

T.test("a name two seeds share in this language: the caster's class, else the player's own", function()
    local BL = loadBL()
    local done = speak(BL, { [1784] = "Qianxing", [5215] = "Qianxing" })  -- zhCN Stealth and Prowl
    T.isnil(BL.Data.Lookup("Qianxing"), "no seed claims it")
    local cands = BL.Data.Shared("Qianxing")
    T.truthy(cands and cands.rogue and cands.druid, "both are candidates")
    local function resolve(source)
        return BL.Classify.Resolve({ kind = "aura", name = "Qianxing", sourceUnit = source })
    end
    stub.SetUnits({ player = { name = "Me", class = "ROGUE" } })
    T.eq(resolve("player"), "rogue")
    stub.SetUnits({ player = { name = "Me", class = "DRUID" } })
    T.eq(resolve("player"), "druid")
    stub.SetUnits({ player = { name = "Me", class = "WARRIOR" } })
    T.eq(resolve("player"), "other", "neither class, nothing else known")
    stub.SetUnits({ player = { name = "Me", class = "WARRIOR" }, party1 = { name = "Leaf", class = "DRUID" } })
    T.eq(resolve("party1"), "druid", "a group member's cast says which it is")
    done()
end)
