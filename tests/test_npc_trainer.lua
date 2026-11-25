local stub = require("stub")
local NW = require("npcworld")

-- The trainer page of the NPC window (Npc/Train.lua). Class and profession
-- trainers show as one more page of the talk window.

local function load(spec)
    spec = spec or {}
    stub.Load({ before = NW.world(spec), qol = spec.qol })
    local ns = stub.npc
    return ns.Window, ns
end

local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end
local function settle() frame(30) end

local function page(N) return N.frame.pages.train end
-- The lines on the page, in reading order: { name, sub, value, dim }.
local function lines(N)
    local out = {}
    for _, p in ipairs(page(N).pieces or {}) do
        if p.lineSpec then out[#out + 1] = p end
    end
    return out
end
local function names(N)
    local out = {}
    for _, l in ipairs(lines(N)) do out[#out + 1] = l.name:GetText() end
    return out
end
local function line(N, name)
    for _, l in ipairs(lines(N)) do if l.name:GetText() == name then return l end end
end
local function sections(N)
    local out = {}
    for _, p in ipairs(page(N).pieces or {}) do
        if p.text and not p.lineSpec and p.isSection then out[#out + 1] = p.text:GetText() end
    end
    return out
end

T.test("trainer: talking to a trainer opens our page and the trainer stays open (the game's visible check passes)", function()
    local N = load()
    NW.Trainer()
    frame()
    T.eq(#NW.Calls("CloseTrainer"), 0, "the game ends a trainer whose window isn't visible")
    T.eq(N.state.mode, "trainer")
    T.eq(N.frame.current, "train")
    T.eq(N.frame:IsShown(), true)
    T.eq(N.frame:GetWidth(), 440)
    T.eq(N.frame.money:IsShown(), true, "your money in the header")
end)

T.test("trainer: the game's window is held aside, never clipped, every time, and leaves no ghost", function()
    local N = load()
    NW.Trainer()
    frame()
    local aside = DaylightUI.Win.Followers.aside
    T.eq(ClassTrainerFrame:GetParent(), aside, "parked the moment it loaded, before its first show")
    T.isnil(stub.ClipAncestor(ClassTrainerFrame), "never under a clipping frame")
    T.eq(ClassTrainerFrame:IsVisible(), true, "the game still counts it visible")
    T.eq(#NW.Calls("CloseTrainer"), 0, "so its bootstrap never closes the trainer")
    settle()
    local p, rel, _, x, y = N.frame:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, UIParent); T.eq(x, 16 / N.frame:GetScale()); T.eq(y, -116 / N.frame:GetScale())
    N.Goodbye()
    frame(); settle()
    T.eq(N.frame:IsShown(), false)
    local closes = #NW.Calls("CloseTrainer")   -- ours, then the game's own OnHide again
    NW.Trainer()
    frame()
    T.eq(#NW.Calls("CloseTrainer"), closes, "the second visit stays open too")
    T.eq(N.frame:IsShown(), true)
end)

T.test("trainer: Learn now first, Coming up by level, dimmed; every kind listed (the game's filters on)", function()
    local N = load()
    NW.Trainer()
    frame()
    T.eq(NW.state.trainer.filter.used, true, "known spells listed too")
    T.deq(names(N), { "Frostbolt", "Blizzard", "Evocation", "Fire Ward", "Remove Lesser Curse", "Fireball", "Scorch", "Counterspell" })
    T.deq(sections(N), { "LEARN NOW · 5", "LEVEL 22", "LEVEL 24" })
    T.eq(line(N, "Frostbolt").sub:GetText(), "Rank 4")
    T.eq(line(N, "Frostbolt").lineSpec.dim, nil)
    T.eq(line(N, "Fireball").lineSpec.dim, true)
    T.falsy(line(N, "Fireball").icon:IsDesaturated(), "a spell for later keeps its colors, not grayscale")
    T.eq(line(N, "Fireball").icon:GetAlpha(), 1)
    T.truthy(page(N).known:GetText():find("2"), "two already known")
end)

T.test("trainer: a click only picks a line (spells cost real gold); Train learns the picked one", function()
    local N = load()
    NW.Trainer()
    frame()
    local foot = page(N).foot
    T.eq(#NW.Calls("BuyTrainerService"), 0, "opening never spends")
    line(N, "Blizzard"):Click()
    T.eq(#NW.Calls("BuyTrainerService"), 0, "a click never spends")
    T.eq(line(N, "Blizzard").pick:IsShown(), true, "highlighted")
    T.truthy(foot.buttons[1].text:GetText():find("Train"), "the main button")
    T.truthy(foot.buttons[1].text:GetText():find("1"), "says what it costs")
    line(N, "Frostbolt"):Click()
    T.eq(line(N, "Blizzard").pick:IsShown(), false, "one pick at a time")
    local heard = {}
    _G.PlaySoundFile = function(file) heard[#heard + 1] = file end
    foot:Press(1)
    T.deq(NW.Calls("BuyTrainerService"), { { 1, "Frostbolt" } })
    local n = 0
    for _, f in ipairs(heard) do if f == DaylightUI.Sound.FILES.done then n = n + 1 end end
    _G.PlaySoundFile = nil
    T.eq(n, 1, "the chime")
    frame(3)
    T.eq(line(N, "Frostbolt"), nil, "learned: off the list")
    T.eq(line(N, "Blizzard").pick:IsShown(), true, "the pick moves on to the next, as the game's trainer")
    T.eq(#NW.Calls("BuyTrainerService"), 1, "and nothing more is spent by itself")
    line(N, "Fireball"):Click()
    T.eq(line(N, "Fireball").pick:IsShown(), false, "Coming up lines can't be picked")
end)

-- Ranks share a name: picking one rank lights only that line, and Train learns that rank.
T.test("trainer: two ranks of one spell: the pick is the rank you clicked", function()
    local N = load()
    NW.state.money = 100000
    NW.Trainer({ services = {
        { name = "Frostbolt", sub = "Rank 3", kind = "available", level = 18, cost = 5000 },
        { name = "Frostbolt", sub = "Rank 4", kind = "available", level = 20, cost = 9000 },
    } })
    frame()
    local l = lines(N)
    T.eq(#l, 2)
    l[2]:Click()
    T.eq(l[1].pick:IsShown(), false, "the other rank stays unpicked")
    T.eq(l[2].pick:IsShown(), true)
    page(N).foot:Press(1)
    T.deq(NW.Calls("BuyTrainerService"), { { 2, "Frostbolt" } })
end)

T.test("trainer: a recipe's name wears its item's quality; plain white ones stay warm", function()
    local N = load()
    NW.state.money = 100000
    NW.Trainer({ services = NW.Recipes(), type = 2, rank = 100 })
    frame()
    local r, g, b = DaylightUI.Win.Parts.QualityColor(2)
    T.rgb(line(N, "Woolen Bag").name.__textColor, { r, g, b }, "uncommon green")
    T.rgb(line(N, "Gray Woolen Shirt").name.__textColor, DaylightUI.Style.INK.VALUE, "no link: warm as before")
end)

T.test("trainer: too dear is soft red and learns nothing", function()
    local N = load()
    NW.state.money = 8000
    NW.Trainer()
    frame()
    local l = line(N, "Frostbolt")
    local r, g = unpack(l.value.__textColor)
    T.truthy(r > g, "its cost in soft red")
    l:Click()
    T.eq(page(N).foot.buttons[1].spec.off, true, "Train is off for it")
    page(N).foot:Press(1)
    T.eq(#NW.Calls("BuyTrainerService"), 0)
    local fr, fg = unpack(line(N, "Remove Lesser Curse").value.__textColor)
    T.rgb({ fr, fg, select(3, unpack(line(N, "Remove Lesser Curse").value.__textColor)) }, DaylightUI.Style.INK.MONEY, "this one fits: gold, not red")
end)

T.test("trainer: Train all learns what you can afford, one after another, and says what it costs", function()
    local N = load()
    NW.state.money = 30000
    NW.Trainer()
    frame()
    local foot = page(N).foot
    T.truthy(foot.buttons[2].text:GetText():find("Train all"), "beside Train")
    foot:Press(2)
    T.eq(foot.buttons[2].text:GetText(), "Click again to train all", "the first click only asks")
    T.eq(#NW.Calls("BuyTrainerService"), 0, "nothing spent yet")
    foot:Press(2)
    T.eq(#NW.Calls("BuyTrainerService"), 0, "a double-click's second half doesn't count")
    stub.Advance(0.3)
    foot:Press(2)
    for _ = 1, 10 do stub.Advance(0.25); frame(2) end
    local bought = {}
    for _, c in ipairs(NW.Calls("BuyTrainerService")) do bought[#bought + 1] = c[2] end
    T.deq(bought, { "Frostbolt", "Blizzard", "Evocation" }, "in order, until the money runs out")
    T.eq(NW.state.money, 1000)
    T.eq(foot.buttons[2].spec.off, true, "nothing left you can afford")
end)

T.test("trainer: Train all asks a second click, and forgets it after a moment", function()
    local N = load()
    NW.state.money = 30000
    NW.Trainer()
    frame()
    local foot = page(N).foot
    foot:Press(2)
    T.eq(foot.buttons[2].text:GetText(), "Click again to train all")
    stub.Advance(DaylightUI.Widgets.CONFIRM + 0.1); frame(2)
    T.truthy(foot.buttons[2].text:GetText():find("Train all ·"), "back to its cost")
    foot:Press(2)
    T.eq(#NW.Calls("BuyTrainerService"), 0, "asks again, spends nothing")
end)

T.test("trainer: Train all learns a spell's next rank too, once the one before it is learned", function()
    local N = load()
    NW.state.money = 30000
    NW.Trainer({ services = {
        { name = "Frostbolt", sub = "Rank 4", kind = "available", level = 20, cost = 1000 },
        { name = "Frostbolt", sub = "Rank 5", kind = "unavailable", level = 20, cost = 2000, needs = "Frostbolt Rank 4" },
    } })
    frame()
    page(N).foot:Press(2)
    stub.Advance(0.3)
    page(N).foot:Press(2)
    for _ = 1, 10 do stub.Advance(0.25); frame(2) end
    local bought = {}
    for _, c in ipairs(NW.Calls("BuyTrainerService")) do bought[#bought + 1] = c[2] end
    T.deq(bought, { "Frostbolt", "Frostbolt" }, "rank 4, then rank 5")
    T.eq(NW.state.money, 27000)
end)

T.test("trainer: no key ever spends money (Space/Enter training everything could wipe out your gold); Escape says goodbye", function()
    local N = load()
    NW.Trainer()
    frame()
    T.eq(N.OnKey("1"), false, "your bar's 1, not a purchase")
    T.eq(N.OnKey("SPACE"), true, "Space is swallowed while talking (never a jump), but does nothing")
    T.eq(N.OnKey("ENTER"), false, "Enter goes on to the game (chat)")
    stub.Advance(1); frame(3)
    T.eq(#NW.Calls("BuyTrainerService"), 0)
    T.eq(page(N).foot.buttons[1].text:GetText():find("Space"), nil, "no key shown on Train all")
    T.eq(N.OnKey("ESCAPE"), true)
    T.truthy(#NW.Calls("CloseTrainer") >= 1)
    frame(); settle()
    T.eq(N.frame:IsShown(), false)
end)

T.test("trainer: gossip into the trainer is one window: no close, it glides wider", function()
    local N = load()
    NW.Gossip({ text = "The arcane rewards patience.", options = { { name = "I would like to train.", icon = 1 } } })
    frame(); settle()
    N.rows[1]:Click()
    NW.CloseGossip(true)
    frame()
    T.eq(N.frame:IsShown(), true, "held")
    NW.Trainer()
    frame()
    T.eq(N.state.mode, "trainer")
    T.eq(DaylightUI.Win.IsOpen(N.frame), true, "never closed in between")
    settle()
    T.eq(N.frame:GetWidth(), 440)
end)

T.test("trainer: walking away: the game hides its window (its own OnHide tells the server); ours closes", function()
    local N = load()
    NW.Trainer()
    frame()
    HideUIPanel(ClassTrainerFrame)
    frame(); settle()
    T.eq(#NW.Calls("CloseTrainer"), 1)
    T.eq(N.frame:IsShown(), false)
end)

T.test("trainer: a profession trainer: the skill bar, the next rank, recipes by the skill they need", function()
    local N = load()
    NW.Trainer({ services = NW.Recipes(), rank = 118, maxRank = 150, type = 2 })
    frame()
    T.eq(page(N).skill:IsShown(), true)
    T.eq(page(N).skill.text:GetText(), "Tailoring")
    T.eq(page(N).skill.value:GetText(), "118 / 150")
    T.deq(names(N), { "Gray Woolen Shirt", "Woolen Bag", "Expert Tailoring", "Heavy Woolen Gloves", "Small Silk Pack" })
    T.deq(sections(N), { "LEARN NOW · 2", "NEEDS SKILL 125", "NEEDS SKILL 135" })
end)

T.test("trainer: each recipe says the level its item is for and the skill it needs, as the game's trainer does", function()
    local N = load()
    local list = NW.Recipes()
    list[3].useLevel = 10                                  -- Woolen Bag, loaded
    list[4].link = "|cnIQ2:|Hitem:4310::::::::20:::::::::|h[Heavy Woolen Gloves]|h|r"   -- not loaded yet
    NW.Trainer({ services = list, rank = 118, maxRank = 150, type = 2 })
    frame()
    T.eq(line(N, "Woolen Bag").sub:GetText(), "Level 10 · Skill 80")
    T.eq(line(N, "Gray Woolen Shirt").sub:GetText(), "Skill 100", "no item: the skill alone")
    T.eq(line(N, "Expert Tailoring").sub:GetText(), "Level 20 · Skill 125", "the trainer's own level requirement")
    T.eq(line(N, "Heavy Woolen Gloves").sub:GetText(), "Skill 125")
    -- The item arrives: the page reads it again.
    list[4].useLevel = 21
    stub.FireEvent("GET_ITEM_INFO_RECEIVED", 4310, true)
    frame(2)
    T.eq(line(N, "Heavy Woolen Gloves").sub:GetText(), "Level 21 · Skill 125")
end)

T.test("trainer: a class trainer's lines keep their rank alone", function()
    local N = load()
    NW.Trainer()
    frame()
    T.eq(line(N, "Frostbolt").sub:GetText(), "Rank 4")
end)

T.test("trainer: a new profession asks a second click and is never in Train all; no free slot refuses it", function()
    local N = load()
    local svc = { { name = "Apprentice Tailoring", kind = "available", level = 5, cost = 100, profession = true },
                  { name = "Gray Woolen Shirt", kind = "available", cost = 500 } }
    NW.Trainer({ services = svc, type = 2 })
    frame()
    page(N).foot:Press(2)
    stub.Advance(0.3)
    page(N).foot:Press(2)
    for _ = 1, 4 do stub.Advance(0.25); frame(2) end
    T.deq(NW.Calls("BuyTrainerService"), { { 2, "Gray Woolen Shirt" } }, "Train all leaves the profession alone")
    local l = line(N, "Apprentice Tailoring")
    l:Click()
    page(N).foot:Press(1)
    T.eq(#NW.Calls("BuyTrainerService"), 1, "the first Train only asks")
    T.truthy(l.sub:GetText():find("again"))
    T.eq(page(N).foot.buttons[1].text:GetText(), "Click again to train")
    page(N).foot:Press(1)
    T.eq(#NW.Calls("BuyTrainerService"), 2)
    -- Both slots used: refused, in red.
    NW.state.professions = { 1, 2 }
    NW.Trainer({ services = { { name = "Apprentice Mining", kind = "available", cost = 100, profession = true } }, type = 2 })
    frame()
    line(N, "Apprentice Mining"):Click()
    T.eq(page(N).foot.buttons[1].spec.off, true)
    page(N).foot:Press(1); page(N).foot:Press(1)
    T.eq(#NW.Calls("BuyTrainerService"), 2)
end)

T.test("trainer: Beast Training (no NPC) stays the game's window", function()
    local N = load()
    NW.Trainer({ type = 3 })
    frame()
    T.eq(N.frame:IsShown(), false)
    T.eq(ClassTrainerFrame:GetParent(), UIParent, "lent back")
    T.eq(#NW.Calls("CloseTrainer"), 0)
    HideUIPanel(ClassTrainerFrame)
    frame(2)
    T.eq(ClassTrainerFrame:GetParent(), DaylightUI.Win.Followers.aside, "held aside again once closed")
end)

-- The game fills its window as it shows, while it still sits shrunk under the
-- aside holder, where text measures far too wide. Lent back, it must be sized
-- again: seen in game, the filter button ran off across the screen and names
-- beside a TP cost were cut to nothing until the first click.
T.test("trainer: Beast Training's filter button and names fit on the first open", function()
    load()
    for _ = 1, 2 do
        NW.Trainer({ type = 3 })
        frame()
        T.eq(ClassTrainerFrame:GetParent(), UIParent, "lent back")
        local drop = ClassTrainerFrame.FilterDropdown
        T.eq(drop:GetWidth(), #"Filter" * 7 + 60, "the filter button fits its word")
        for _, row in ipairs(ClassTrainerFrame.ScrollBox.rows) do
            T.eq(row.name:GetWidth(), #row.name:GetText() * 7, row.name:GetText() .. " keeps its name")
        end
        HideUIPanel(ClassTrainerFrame)
        frame(2)
        T.eq(ClassTrainerFrame:GetParent(), DaylightUI.Win.Followers.aside, "held aside again once closed")
    end
end)

-- The game's trainer window has no skin of its own while Daylight UI's trainer
-- page replaces it, but Beast Training still shows the game's window.
T.test("trainer: Beast Training's game window wears the Daylight UI look, a class trainer's stays bare", function()
    stub.Load({ before = NW.world({}), skins = true })
    local Kit = stub.skins.Kit
    NW.Trainer()
    frame(2)
    T.isnil(Kit.ShellOf(ClassTrainerFrame), "a class trainer's window is replaced, not skinned")
    CloseTrainer()
    frame(2)
    NW.Trainer({ type = 3 })
    frame(2)
    T.eq(ClassTrainerFrame:GetParent(), UIParent, "lent back")
    T.truthy(Kit.ShellOf(ClassTrainerFrame), "skinned for Beast Training")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("trainer: the sample talk's trainer line opens a sample page and learns nothing for real", function()
    local N = load()
    N.Sample()
    settle()
    local row
    for _, r in ipairs(N.rows) do if r.text:GetText() == "I'd like to train." then row = r end end
    row:Click()
    settle()
    T.eq(N.state.mode, "trainer")
    T.eq(N.frame:GetWidth(), 440)
    lines(N)[1]:Click()
    page(N).foot:Press(1)
    page(N).foot:Press(2)
    for _ = 1, 6 do stub.Advance(0.25); frame(2) end
    T.eq(#NW.state.calls, 0)
end)

T.test("trainer: trainers switched off: the game's trainer stays the game's", function()
    stub.Load({ before = function()
        NW.world()()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { NPC = { trainer = false } } } } }
    end })
    NW.Trainer()
    frame()
    T.eq(ClassTrainerFrame:GetParent(), UIParent)
    T.eq(stub.npc.Window.frame:IsShown(), false)
end)

T.test("trainer: in combat the page still learns by mouse; nothing protected is touched", function()
    local N = load()
    NW.Trainer()
    frame()
    stub.EnterCombat()
    T.noerror(function() line(N, "Frostbolt"):Click(); page(N).foot:Press(1); frame(3) end)
    T.eq(#NW.Calls("BuyTrainerService"), 1)
    stub.LeaveCombat()
end)

-- The game's own trainer (Blizzard_TrainerUI.lua), behavior by behavior.

-- ClassTrainer_SelectNearestLearnableSkill on show: Train works without a click first.
-- The selection stays on its spot as the list shifts, so after a purchase the next
-- line is picked. Nothing is ever bought without a press.
T.test("trainer game: opening picks the first line you can learn; after training the pick moves on", function()
    local N = load()
    NW.Trainer()
    frame()
    local foot = page(N).foot
    T.eq(line(N, "Frostbolt").pick:IsShown(), true, "the first learnable line")
    T.eq(foot.buttons[1].spec.off, false, "Train works at once")
    T.truthy(foot.buttons[1].text:GetText():find(DaylightUI.MoneyString(9000), 1, true), "and says the cost")
    T.eq(#NW.Calls("BuyTrainerService"), 0, "nothing spent")
    line(N, "Evocation"):Click()
    foot:Press(1)
    frame(3)
    T.deq(NW.Calls("BuyTrainerService"), { { 3, "Evocation" } })
    T.eq(line(N, "Fire Ward").pick:IsShown(), true, "the line that took its spot")
    line(N, "Remove Lesser Curse"):Click()
    stub.FireEvent("TRAINER_UPDATE")
    frame(3)
    T.eq(line(N, "Remove Lesser Curse").pick:IsShown(), true, "a line you picked yourself stays picked over a refill")
    T.eq(#NW.Calls("BuyTrainerService"), 1, "still nothing more spent")
end)

T.test("trainer game: nothing to learn: nothing picked, Train off", function()
    local N = load()
    NW.Trainer({ services = { { name = "Fireball", sub = "Rank 5", kind = "unavailable", level = 22, cost = 12000 } } })
    frame()
    T.eq(page(N).foot.buttons[1].spec.off, true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- ClassTrainerFrame_InitServiceButton lists GetTrainerServiceAbilityReq too, red while unmet.
T.test("trainer game: a spell that needs another first says which", function()
    local N = load()
    local list = NW.Spells()
    list[#list + 1] = { name = "Frostbolt", sub = "Rank 5", kind = "unavailable", level = 20, cost = 11000, needs = "Frostbolt Rank 4" }
    NW.Trainer({ services = list })
    frame()
    local rank5
    for _, l in ipairs(lines(N)) do if l.lineSpec.service.sub == "Rank 5" and l.lineSpec.service.name == "Frostbolt" then rank5 = l end end
    T.truthy(rank5, "listed")
    local sub = rank5.sub:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.truthy(sub:find("Rank 5", 1, true), "its rank: " .. sub)
    T.truthy(sub:find("Frostbolt Rank 4", 1, true), "and what it needs first: " .. sub)
    T.eq(line(N, "Blizzard").sub:GetText(), "Rank 1", "a line that needs nothing keeps its rank alone")
end)

-- TRADESKILL_RANK_WITH_MODIFIER: a racial or gear bonus shows beside the rank.
T.test("trainer game: the skill bar shows a bonus to the skill", function()
    local N = load()
    NW.Trainer({ services = NW.Recipes(), rank = 118, maxRank = 150, modifier = 15, type = 2 })
    frame()
    T.eq(page(N).skill.value:GetText(), "118 (+15) / 150")
end)
