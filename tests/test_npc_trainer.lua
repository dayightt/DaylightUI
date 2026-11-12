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

T.test("trainer: the game's window is out of sight under the veil, every time, and leaves no ghost", function()
    local N = load()
    NW.Trainer()
    frame()
    local veil = DaylightUI.Win.Followers.veil
    T.eq(ClassTrainerFrame:GetParent(), veil, "parked the moment it loaded, before its first show")
    T.eq(veil:IsShown(), true)
    T.eq(veil:GetAlpha(), 0)
    T.eq(ClassTrainerFrame:IsVisible(), true, "the game still counts it visible")
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
    T.eq(foot.buttons[1].spec.off, true, "nothing picked: Train is off")
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
    T.eq(foot.buttons[1].spec.off, true, "the pick is gone with it: no second spend")
    line(N, "Fireball"):Click()
    T.eq(page(N).foot.buttons[1].spec.off, true, "Coming up lines can't be picked")
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
    T.eq(ClassTrainerFrame:GetParent(), DaylightUI.Win.Followers.veil, "veiled again once closed")
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
