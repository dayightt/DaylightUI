local stub = require("stub")

-- The tour (Tour.lua): "Take a tour?" after the setup guide's reload, then
-- one stop at a time, one part lit, the rest dim; Home's "Take the tour"
-- runs it again.

local function load(opts)
    opts = opts or {}
    local DUI = stub.Load({ infopanel = opts.infopanel, buffs = opts.buffs, bags = opts.bags, before = opts.before })
    DUI.DB.Root().tourDone = nil
    -- set up already: the guide doesn't open itself at login
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    return DUI
end

local function press(b) b:GetScript("OnClick")(b, "LeftButton") end
local function ids(list)
    local out = {}
    for _, d in ipairs(list) do out[#out + 1] = d.id end
    return table.concat(out, " ")
end
-- Every waiting timer (a step's settle, the card's fade) runs at once.
local function settle() stub.RunTimers() end

T.test("tour: the stops are in order, each only with its module", function()
    local DUI = load()
    T.eq(ids(DUI.Tour.List()), "unlock options")
    DUI = load({ infopanel = true, buffs = true, bags = true })
    T.eq(ids(DUI.Tour.List()), "meter datatexts buffs bags unlock options")
end)

T.test("tour: a folded meter slides out for its stop and folds again after", function()
    local DUI = load({ infopanel = true })
    T.eq(DUI:Get("InfoPanel", "meter.enabled"), false, "new setups start folded")
    DUI.Tour.Start()
    settle()
    T.eq(DUI.Tour.StepId(), "meter")
    T.eq(DUI:Get("InfoPanel", "meter.enabled"), true, "out for the look")
    T.truthy(string.find(DUI.Tour.card.text:GetText(), "folded", 1, true), "the card says how to open it")
    press(DUI.Tour.card.next)
    settle()
    T.eq(DUI:Get("InfoPanel", "meter.enabled"), false, "folded again")
end)

T.test("tour: a fight on the meter's stop folds it again", function()
    local DUI = load({ infopanel = true })
    DUI.Tour.Start()
    settle()
    stub.EnterCombat()
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(DUI:Get("InfoPanel", "meter.enabled"), false)
end)

T.test("tour: the setup guide finishing asks once, after the reload", function()
    local DUI = load()
    T.eq(DUI.Tour.AskShown(), false, "nothing asked before the guide")
    DUI.DB.Character().tourOffer = true   -- as Installer.Finish leaves it
    DUI.Tour.Offer()
    T.eq(DUI.Tour.AskShown(), true, "asked")
    press(DaylightUITourAsk.no)
    T.eq(DUI.DB.Character().tourOffer, nil, "answered")
    T.eq(DUI.DB.Root().tourDone, true, "not asked on the next character")
    T.eq(DUI.Tour.Running(), false)
    DUI.DB.Character().tourOffer = true
    DUI.Tour.Offer()
    T.eq(DUI.Tour.AskShown(), false, "the account said no already")
end)

T.test("tour: Show me around starts it; a fight asks again after", function()
    local DUI = load()
    DUI.DB.Character().tourOffer = true
    stub.EnterCombat()
    DUI.Tour.Offer()
    T.eq(DUI.Tour.AskShown(), false, "never in a fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.eq(DUI.Tour.AskShown(), true, "after it")
    press(DaylightUITourAsk.yes)
    settle()
    T.eq(DUI.Tour.Running(), true)
    T.eq(DUI.Tour.StepId(), "unlock")
end)

T.test("tour: each stop shows its part and puts it back as it leaves", function()
    local DUI = load({ infopanel = true, buffs = true })
    T.eq(DUI.Tour.Start(), true)
    settle()
    T.eq(DUI.Tour.StepId(), "meter")
    T.eq(DUI.testMode, true, "the meter's sample")
    T.eq(DUI.TestPartShown("meter"), true)
    T.eq(DUI.TestPartShown("buffs"), false, "only the meter's")
    press(DUI.Tour.card.next)
    settle()
    T.eq(DUI.Tour.StepId(), "datatexts")
    T.eq(DUI.testMode, false, "the sample went with its stop")
    press(DUI.Tour.card.next)
    settle()
    T.eq(DUI.Tour.StepId(), "buffs")
    T.eq(DUI.TestPartShown("buffs"), true)
    press(DUI.Tour.card.next)
    settle()
    T.eq(DUI.Tour.StepId(), "unlock")
    T.eq(DUI.Movers.unlocked, true, "every handle out")
    T.truthy(DUI.Movers.LockButton():IsShown(), "its lock button up")
    press(DUI.Tour.card.back)
    settle()
    T.eq(DUI.Tour.StepId(), "buffs")
    T.eq(DUI.Movers.unlocked, false, "locked again going back")
    press(DUI.Tour.card.next); settle()
    press(DUI.Tour.card.next); settle()
    T.eq(DUI.Tour.StepId(), "options")
    T.eq(DUI.Movers.unlocked, false)
    T.eq(DUI.OptionsPanel.IsShown(), true, "the options open on Home")
    press(DUI.Tour.card.next)
    T.eq(DUI.Tour.Running(), false, "Done ends it")
    T.eq(DUI.DB.Root().tourDone, true)
    T.eq(DUI.OptionsPanel.IsShown(), false, "the options it opened close with it")
end)

T.test("tour: a waiting stop (the bags) lights its part once the player opens it", function()
    local DUI = load()
    local win = CreateFrame("Frame", nil, UIParent)
    win:SetSize(200, 100)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    win:Hide()
    -- the fake game lays nothing out: its edges by hand
    win.GetLeft = function() return 100 end
    win.GetBottom = function() return 100 end
    win.GetRight = function() return 300 end
    win.GetTop = function() return 200 end
    DUI.Tour.Add("testwait", { order = 1, title = "Bags", wait = true,
        text = function() return win:IsShown() and "Open now." or "Press B to open them." end,
        part = function() return win end })
    DUI.Tour.Start()
    settle()
    T.eq(DUI.Tour.StepId(), "testwait")
    T.eq(DUI.Tour.Lit(), nil, "nothing lit while it's shut")
    T.eq(DUI.Tour.card.text:GetText(), "Press B to open them.")
    win:Show()
    DaylightUITour:GetScript("OnUpdate")(DaylightUITour, 1)
    T.eq(DUI.Tour.Lit(), win, "lit once it's up")
    T.eq(DUI.Tour.card.text:GetText(), "Open now.", "and the card moves on to it")
end)

T.test("tour: a fight ends it and puts everything back", function()
    local DUI = load()
    DUI.Tour.Start()
    settle()
    T.eq(DUI.Movers.unlocked, true)
    stub.EnterCombat()
    T.eq(DUI.Tour.Running(), false)
    T.eq(DUI.Movers.unlocked, false)
    T.eq(DaylightUITour:IsMouseEnabled(), false, "the screen handed back")
    stub.LeaveCombat()
    T.eq(DUI.Tour.Start(), true, "it can run again")
end)

T.test("tour: Escape skips it and says where to find it again", function()
    local DUI = load()
    DUI.Tour.Start()
    settle()
    T.eq(DUI.Tour.OnKey("ESCAPE"), true)
    T.eq(DUI.Tour.Running(), false)
    T.eq(DUI.Movers.unlocked, false)
    T.truthy(string.find(DUI.Tour.toast.text:GetText(), "Take the tour", 1, true))
    T.eq(DUI.Tour.OnKey("ESCAPE"), false, "Escape goes on to the game after")
end)

T.test("tour: skipping on the options' stop closes them too", function()
    local DUI = load()
    DUI.Tour.Start()
    settle()
    press(DUI.Tour.card.next)
    settle()
    T.eq(DUI.Tour.StepId(), "options")
    T.eq(DUI.OptionsPanel.IsShown(), true)
    DUI.Tour.OnKey("ESCAPE")
    T.eq(DUI.OptionsPanel.IsShown(), false)
end)

T.test("tour: never over the setup guide or in a fight", function()
    local DUI = load()
    stub.EnterCombat()
    T.eq(DUI.Tour.Start(), false)
    stub.LeaveCombat()
    DUI.Installer.Show()
    T.eq(DUI.Tour.Start(), false)
end)

T.test("tour: Home's Take the tour closes the options and starts it", function()
    local DUI = load()
    DUI.OptionsPanel.Show("home")
    local item
    for _, g in ipairs(DUI.Options.GetPage("home").groups) do
        for _, it in ipairs(g.items or {}) do if it.label == "Take the tour" then item = it end end
    end
    T.truthy(item, "the row is on Home")
    item.func()
    settle()
    T.eq(DUI.Tour.Running(), true)
    T.eq(DUI.Tour.StepId(), "unlock")
end)

T.test("tour: the card goes beside the light, or in the middle of a window too big for that", function()
    local DUI = load()
    local x, top = DUI.Tour.CardSpot({ l = 100, b = 500, r = 300, t = 700 }, 320, 200, 1920, 1080)
    T.eq(x, 300 + DUI.Tour.GAP); T.eq(top, 700)
    x, top = DUI.Tour.CardSpot({ l = 20, b = 20, r = 1900, t = 1060 }, 320, 200, 1920, 1080)
    T.eq(x, (20 + 1900 - 320) / 2); T.eq(top, (20 + 1060 + 200) / 2)
end)
