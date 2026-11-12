local stub = require("stub")

-- The buff categories' logic (ported with the buff bars): loaded with the
-- core and logged in, as the client does.
local function loadBL(opts)
    stub.Load({ buffs = true, before = opts and opts.before })
    return stub.buffs
end

local function entry(name, extra)
    local e = { kind = "aura", name = name, sourceUnit = "player" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

T.test("override beats every other source", function()
    local BL = loadBL()
    BL.DB.overrides["Arcane Intellect"] = "warrior"
    T.eq(BL.Classify.Resolve(entry("Arcane Intellect")), "warrior")
    BL.DB.overrides["Sharpened"] = "consumable"
    T.eq(BL.Classify.Resolve({ kind = "weapon", name = "Sharpened" }), "consumable")
end)

T.test("weapon kind lands in weapon unless overridden", function()
    local BL = loadBL()
    T.eq(BL.Classify.Resolve({ kind = "weapon", name = "Weapon Enchant" }), "weapon")
    T.eq(BL.Classify.Resolve({ kind = "weapon", name = "Arcane Intellect" }), "weapon")
end)

T.test("seed table: exact then pattern", function()
    local BL = loadBL()
    T.eq(BL.Classify.Resolve(entry("Power Word: Fortitude")), "priest")
    T.eq(BL.Classify.Resolve(entry("Elixir of Nothing Known")), "consumable")
end)

T.test("caster class is learned from a group source and persists", function()
    local BL = loadBL()
    stub.SetUnits({ player = { name = "Me", class = "HUNTER" }, party1 = { name = "Bob", class = "PRIEST" } })
    local fired = 0
    BL.On("OVERRIDES_CHANGED", function() fired = fired + 1 end)
    T.eq(BL.Classify.Resolve(entry("Mystery Ward", { sourceUnit = "party1" })), "priest")
    T.eq(BL.DB.learned["Mystery Ward"], "priest")
    T.eq(fired, 1)
    T.eq(BL.Classify.Resolve(entry("Mystery Ward", { sourceUnit = "party1" })), "priest")
    T.eq(fired, 1, "no re-fire when unchanged")
    -- caster gone: learned entry carries it
    T.eq(BL.Classify.Resolve(entry("Mystery Ward", { sourceUnit = nil })), "priest")
    T.eq(BL.Classify.Resolve(entry("Mystery Ward", { sourceUnit = "party7" })), "priest")
end)

T.test("player and pet sources never teach a class", function()
    local BL = loadBL()
    stub.SetUnits({ player = { name = "Me", class = "HUNTER" }, pet = { name = "Cat", class = "HUNTER" } })
    T.eq(BL.Classify.Resolve(entry("Unknown Self Buff", { sourceUnit = "player" })), "other")
    T.isnil(BL.DB.learned["Unknown Self Buff"])
    T.eq(BL.Classify.Resolve(entry("Unknown Pet Buff", { sourceUnit = "pet" })), "other")
    T.isnil(BL.DB.learned["Unknown Pet Buff"])
end)

T.test("unknown source class does not learn", function()
    local BL = loadBL()
    stub.SetUnits({ player = { name = "Me", class = "HUNTER" }, party1 = { name = "Npc" } })
    T.eq(BL.Classify.Resolve(entry("Odd Buff", { sourceUnit = "party1" })), "other")
    T.isnil(BL.DB.learned["Odd Buff"])
end)

T.test("secret name or source degrade to other without error", function()
    local BL = loadBL()
    stub.SetUnits({ player = { name = "Me", class = "HUNTER" }, party1 = { name = "Bob", class = "PRIEST" } })
    T.noerror(function()
        T.eq(BL.Classify.Resolve(entry(stub.MakeSecret("Arcane Intellect"))), "other")
        T.eq(BL.Classify.Resolve(entry(nil)), "other")
        T.eq(BL.Classify.Resolve(entry("Weird", { sourceUnit = stub.MakeSecret("party1") })), "other")
    end)
    T.eq(T.count(BL.DB.learned), 0)
end)

T.test("a deleted category collapses to other", function()
    local BL = loadBL()
    BL.DB.overrides["Food"] = "custom-9"
    T.eq(BL.Classify.Resolve(entry("Food")), "other")
    BL.Categories.Delete("mage")
    T.eq(BL.Classify.Resolve(entry("Arcane Intellect")), "other")
end)

T.test("Assign writes the override, logs history newest first, trims to the cap", function()
    local BL = loadBL()
    stub.SetTime(1700000100)
    local fired = 0
    BL.On("OVERRIDES_CHANGED", function() fired = fired + 1 end)
    BL.Classify.Assign("Arcane Intellect", "warrior", "bar")
    T.eq(BL.DB.overrides["Arcane Intellect"], "warrior")
    T.eq(BL.Classify.GetOverride("Arcane Intellect"), "warrior")
    local h = BL.Classify.History()
    T.deq(h[1], { buffName = "Arcane Intellect", from = "mage", to = "warrior", time = 1700000100, source = "bar" })
    BL.Classify.Assign("Arcane Intellect", "priest")
    T.eq(BL.Classify.History()[1].from, "warrior")
    T.eq(BL.Classify.History()[1].to, "priest")
    T.eq(#BL.Classify.History(), 2)
    T.eq(fired, 2)
    for i = 1, BL.Classify.HISTORY_MAX + 10 do BL.Classify.Assign("Buff " .. i, "other") end
    T.eq(#BL.Classify.History(), BL.Classify.HISTORY_MAX)
    T.eq(BL.Classify.History()[1].buffName, "Buff " .. (BL.Classify.HISTORY_MAX + 10))
    T.falsy(BL.Classify.Assign("X", "not-a-category"))
    T.falsy(BL.Classify.Assign(nil, "other"))
end)

T.test("ClearHistory", function()
    local BL = loadBL()
    BL.Classify.Assign("Food", "other")
    BL.Classify.ClearHistory()
    T.eq(#BL.Classify.History(), 0)
end)
