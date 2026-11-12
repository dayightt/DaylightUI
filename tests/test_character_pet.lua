-- The character window's Pet page: a hunter's pet or a warlock's demon.
local stub = require("stub")
local CW = require("charworld")

local HUNTER_PET = { name = "Fang", level = 58, family = "Wolf", hunter = true, loyalty = "Loyalty Level 3",
                     xp = 1200, xpNeed = 5000, mood = 3, damage = 125, rate = 1 }
local DEMON = { name = "Grubnak", level = 60, family = "Imp" }

local function load(spec)
    local world = CW.world(spec)
    stub.Load({ character = true, before = world })
    return stub.character
end

local function open(ns)
    ToggleCharacter("PaperDollFrame")
    ns.Follow.Tick()
end

local function tab(ns, id)
    for _, b in ipairs(ns.window.tabs) do if b.id == id then return b end end
end

local function openPet(ns)
    open(ns)
    tab(ns, "pet"):Click()
    return ns.window.pages.pet
end

local function rowOf(rows, id)
    for _, r in ipairs(rows) do if r.id == id then return r end end
end

T.test("pet page: no tab without a pet", function()
    local ns = load({ class = "WARRIOR" })
    open(ns)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(tab(ns, "pet"):IsShown(), false)
    T.eq(tab(ns, "character"):IsShown(), true)
end)

T.test("pet page: a hunter's pet and a warlock's demon each get the tab", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    open(ns)
    T.eq(tab(ns, "pet"):IsShown(), true)
    local wl = load({ class = "WARLOCK", pet = DEMON })
    open(wl)
    T.eq(tab(wl, "pet"):IsShown(), true)
end)

T.test("pet page: the tab sits right after Character", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    open(ns)
    local _, rel = tab(ns, "character"):GetPoint(1)
    T.eq(rel, tab(ns, "pet"), "Character hangs left of Pet")
end)

T.test("pet page: a hunter's pet shows its name, level, family, loyalty, XP and mood", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local page = openPet(ns)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(ns.window.current, "pet")
    T.eq(page.name:GetText(), "Fang")
    local sub = page.sub:GetText()
    T.truthy(sub:find("58", 1, true), sub)
    T.truthy(sub:find("Wolf", 1, true), sub)
    T.truthy(sub:find("Loyalty Level 3", 1, true), sub)
    T.eq(page.xp:IsShown(), true)
    T.eq(select(2, page.xp:GetMinMaxValues()), 5000)
    T.eq(page.foot.mood:IsShown(), true)
    T.eq(page.foot.face.__atlas, "UI-PetHappiness")
    T.truthy(page.foot.moodText:GetText():find("Happy", 1, true))
    T.truthy(page.foot.moodText:GetText():find("125%", 1, true))
    T.truthy(page.foot.xpText:GetText():find("1,200", 1, true), page.foot.xpText:GetText())
end)

T.test("pet page: an unhappy pet's face and color", function()
    local pet = {}
    for k, v in pairs(HUNTER_PET) do pet[k] = v end
    pet.mood, pet.damage = 1, 75
    local ns = load({ class = "HUNTER", pet = pet })
    local page = openPet(ns)
    T.eq(page.foot.face.__atlas, "UI-PetMad")
    T.truthy(page.foot.moodText:GetText():find("Unhappy", 1, true))
end)

T.test("pet page: a pet at the top level shows no XP bar", function()
    local pet = {}
    for k, v in pairs(HUNTER_PET) do pet[k] = v end
    pet.xp, pet.xpNeed = 0, 0
    local ns = load({ class = "HUNTER", pet = pet })
    local page = openPet(ns)
    T.eq(page.xp:IsShown(), false)
    T.eq(page.foot.xpText:GetText(), "")
end)

T.test("pet page: a warlock's demon has no mood, loyalty or XP", function()
    local ns = load({ class = "WARLOCK", pet = DEMON })
    local page = openPet(ns)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(page.name:GetText(), "Grubnak")
    T.truthy(page.sub:GetText():find("Imp", 1, true))
    T.falsy(page.sub:GetText():find("(", 1, true), "no loyalty")
    T.eq(page.xp:IsShown(), false)
    T.eq(page.foot.mood:IsShown(), false)
end)

T.test("pet page: the game's pet rows, read for the pet; zero spell power left out", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local S = ns.Stats
    local rows = S.Read("pet")
    T.eq(rowOf(rows, "pet_dmg").values[1], 80)
    T.eq(rowOf(rows, "pet_ap").values[1], 430, "base plus buffs")
    T.eq(rowOf(rows, "pet_armor").values[1], 2100)
    T.eq(rowOf(rows, "pet_health").values[1], 3200)
    T.near(rowOf(rows, "pet_speed").values[1], 110, 1e-6)
    T.eq(rowOf(rows, "pet_hit").values[1], 6.5, "the owner's 4.5 plus its own 2, as the game adds them")
    T.isnil(rowOf(rows, "pet_sp"), "the game hides it at 0")
    T.isnil(rowOf(rows, "pet_haste"), "the game hides it at 0")
    T.eq(rowOf(S.Read("petResist"), "pet_res_fire").values[1], 5)
    T.eq(rowOf(rows, "pet_dmg").unit, "pet")
end)

T.test("pet page: the pet's attack speed has its own row, as yours does", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local was = _G.UnitAttackSpeed
    _G.UnitAttackSpeed = function(u) if u == "pet" then return 2.0 end return 2.6, 0 end
    local row = rowOf(ns.Stats.Read("pet"), "pet_atkspeed")
    _G.UnitAttackSpeed = was
    T.truthy(row, "a pet attack speed row")
    T.eq(row.values[1], 2.0)
    T.eq(ns.Stats.Text(row), "2.00 s")
end)

T.test("pet page: its stats pane opens as yours: all by default; by class, General stays open", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local page = openPet(ns)
    local G = page.stats.groups
    T.truthy(G.pet.rows[1] and G.pet.rows[1]:IsShown(), "General open")
    T.eq(G.petResist.head.state:GetText(), "", "Resistances open too")
    T.isnil(page.stats.groups.attributes, "none of your own groups")
    DaylightUI:Set("Character", "statsOpen", "auto")
    ns.Window.Refresh(true)
    T.eq(G.pet.head.state:GetText(), "", "General still open")
    T.eq(G.petResist.head.state:GetText(), "+", "Resistances folded, as yours")
end)

T.test("pet page: in combat the secret stats draw without errors; hidden rows stay hidden", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local page = openPet(ns)
    CW.state.secret = true
    stub.EnterCombat()
    local rows = ns.Stats.Read("pet")
    T.isnil(rowOf(rows, "pet_sp"), "the last plain answer holds")
    T.eq(rowOf(rows, "pet_ap").stale, true)
    ns.Window.Refresh(true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.truthy(page:IsShown())
end)

T.test("pet page: a stat's tooltip is the game's own, asked for the pet", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local page = openPet(ns)
    local asked
    _G.PaperDollFrame_SetDamage = function(frame, unit) asked = unit; frame.tooltip = "Damage" end
    _G.PaperDollStatTooltip = function() end
    local r = page.stats.groups.pet.rows[3]
    T.eq(r.row.id, "pet_dmg")
    ns.CharacterPage.StatTip(r)
    T.eq(asked, "pet")
end)

-- The game's damage row (Camelot PaperDollFrame.lua) sets no tooltip text. Its hover
-- function writes the tooltip, attack speed first.
T.test("pet page: the damage tooltip is the game's hover one, with the pet's attack speed", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local page = openPet(ns)
    local spoke
    _G.PaperDollStatTooltip = function() end
    _G.PaperDollFrame_SetDamage = function(frame, unit)
        frame.attackSpeed, frame.damage, frame.unit = 2, "40 - 52", unit
        frame.tooltipLabel = nil
        frame.onEnterFunc = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Main Hand")
            spoke = string.format("%.2F", self.attackSpeed)
            GameTooltip:AddDoubleLine("Attack speed (seconds):", spoke)
            GameTooltip:AddDoubleLine("Damage:", self.damage)
            GameTooltip:Show()
        end
    end
    local r = page.stats.groups.pet.rows[3]
    T.eq(r.row.id, "pet_dmg")
    ns.CharacterPage.StatTip(r)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(spoke, "2.00", "the game's hover tooltip, with the attack speed")
end)

T.test("pet page: dismissing the pet leaves for the Character page and hides the tab", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    openPet(ns)
    CW.SetPet(nil)
    stub.FireEvent("UNIT_PET", "player")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    T.eq(tab(ns, "pet"):IsShown(), false)
    T.eq(ns.window.current, "character")
end)

T.test("pet page: summoning one while the window is open brings the tab", function()
    local ns = load({ class = "WARLOCK" })
    open(ns)
    T.eq(tab(ns, "pet"):IsShown(), false)
    CW.SetPet(DEMON)
    stub.FireEvent("UNIT_PET", "player")
    T.eq(tab(ns, "pet"):IsShown(), true)
end)

T.test("pet page: the pet's model is the game's pet scene, hidden until loaded", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    openPet(ns)
    local M = ns.PetModel
    CW.PetScene(M.scene)
    CW.state.petLoaded = false
    M.SetUp()
    T.deq(CW.Calls("petScene"), { 718 })
    T.deq(CW.Calls("petModel"), { "pet" })
    T.eq(CW.state.petActor.tag, "pet")
    T.eq(M.scene:GetAlpha(), 0)
    CW.state.petLoaded = true
    M.OnUpdate(nil, 0.1)
    T.eq(M.waiting, false)
    T.truthy(M.scene ~= ns.Model.scene, "its own scene, not yours")
end)

T.test("pet page: the pet's model turns with a drag, as yours", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    openPet(ns)
    local M = ns.PetModel
    CW.PetScene(M.scene)
    M.SetUp()
    M.OnUpdate(nil, 0.1)
    stub.cursorPos = { 100, 0 }
    M.StartDrag()
    stub.cursorPos = { 110, 0 }
    M.OnUpdate(nil, 0.016)
    T.near(CW.state.petActor.yaw, 10 * M.TURN, 1e-6)
end)

T.test("pet page: the pet's events never touch your model on the Character page", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    open(ns)
    local before = #CW.Calls("setUpScene")
    stub.FireEvent("UNIT_MODEL_CHANGED", "pet")
    T.eq(#CW.Calls("setUpScene"), before)
    stub.FireEvent("UNIT_MODEL_CHANGED", "player")
    T.eq(#CW.Calls("setUpScene"), before + 1, "yours still does")
end)

T.test("pet page: where everything goes", function()
    local ns = load({ class = "HUNTER", pet = HUNTER_PET })
    local R = ns.PetPage.Rects(834, 482)
    T.deq(R.stats, { x = 618, y = -12, w = 200, h = 422 }, "the same spot as yours")
    T.eq(R.model.x, 16)
    T.eq(R.model.x + R.model.w + ns.PetPage.GAP, R.stats.x)
    T.eq(R.model.y - R.model.h - ns.PetPage.XP_GAP, R.xp.y, "the XP bar under the model")
    T.eq(R.footer.y, -438)
end)
