local stub = require("stub")

-- In a raid of 10 as its leader (or assist, or neither).
local function login(rank, opts)
    opts = opts or {}
    return stub.Load({ module = true, before = function()
        stub.units.player = { name = "Me", class = "PRIEST", isPlayer = true,
                              leader = rank == "leader", assist = rank == "assist" }
        stub.SetGroup(rank ~= "alone", opts.party ~= true, opts.party and 5 or 10)
    end })
end

local function sweep(L)
    local d = L.driver
    for _ = 1, 40 do
        local f = d:GetScript("OnUpdate")
        if not f then return end
        f(d, 0.02)
    end
end

T.test("leader drawer: only the leader and a raid's assists get the tab", function()
    local _, ns = login("leader")
    T.truthy(ns.Leader.tab:IsShown(), "the leader")
    T.falsy(ns.Leader.card:IsShown(), "closed to start with")
    _, ns = login("assist")
    T.truthy(ns.Leader.tab and ns.Leader.tab:IsShown(), "an assist")
    _, ns = login("member")
    T.falsy(ns.Leader.tab and ns.Leader.tab:IsShown(), "a member gets nothing")
    _, ns = login("alone")
    T.falsy(ns.Leader.tab and ns.Leader.tab:IsShown(), "alone: nothing")
end)

T.test("leader drawer: in a party, for the leader", function()
    local _, ns = login("leader", { party = true })
    T.truthy(ns.Leader.tab:IsShown())
    _, ns = login("assist", { party = true })
    T.falsy(ns.Leader.tab and ns.Leader.tab:IsShown(), "a party has no assists")
end)

T.test("leader drawer: the tab hugs the screen's left edge, the card opens toward the middle", function()
    local DUI, ns = login("leader")
    local L = ns.Leader
    local p, rel, rp, x = L.tab:GetPoint(1)
    T.eq(p, "LEFT"); T.eq(rel, UIParent); T.eq(rp, "LEFT"); T.eq(x, 0)
    T.eq(L.Side(L.tab), "right")
    local cp, crel, crp = L.card:GetPoint(1)
    T.eq(crel, L.tab)
    T.truthy(cp:find("LEFT$") and crp:find("RIGHT$"), "the card on the tab's right")
    T.truthy(DUI.Movers.Get(L.MOVER), "it has an unlock handle")
end)

T.test("leader drawer: Shift-drag moves the tab and keeps the spot; a plain drag or a fight doesn't", function()
    local DUI, ns = login("leader")
    local L, tab = ns.Leader, ns.Leader.tab
    _G.GameTooltip = _G.GameTooltip or CreateFrame("GameTooltip", "GameTooltip", UIParent)
    local start, stop = tab:GetScript("OnDragStart"), tab:GetScript("OnDragStop")
    _G.IsShiftKeyDown = function() return false end
    start(tab)
    T.falsy(tab.__moving, "no Shift: no move")
    _G.IsShiftKeyDown = function() return true end
    stub.EnterCombat()
    start(tab)
    T.falsy(tab.__moving, "not in a fight")
    stub.LeaveCombat()
    start(tab)
    T.truthy(tab.__moving, "Shift: it moves")
    -- Where the cursor carried it (the fake game lays nothing out).
    local r = tab:GetEffectiveScale() / UIParent:GetEffectiveScale()
    tab.__center = { (UIParent:GetWidth() / 2 + 200) / r, (UIParent:GetHeight() / 2 + 100) / r }
    stop(tab)
    _G.IsShiftKeyDown = nil
    T.falsy(tab.__moving)
    local saved = DUI.DB.Positions()[L.MOVER]
    T.truthy(saved, "the spot is kept")
    T.near(saved[1], 200, 1); T.near(saved[2], 100, 1)
    T.eq(L.Side(tab), "left", "right of the middle: the card opens left")
    local _, crel, crp = L.card:GetPoint(1)
    T.eq(crel, tab)
    T.truthy(crp:find("LEFT$"), "and hangs off its left")
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
end)

T.test("leader drawer: switched off, the tab fades away; back on, it fades in", function()
    local DUI, ns = login("leader")
    DUI:Set("UnitFrames", "leader.enabled", false)
    T.truthy(ns.Leader.tab.leaving, "fading away")
    stub.RunTimers()
    T.falsy(ns.Leader.tab:IsShown())
    DUI:Set("UnitFrames", "leader.enabled", true)
    T.truthy(ns.Leader.tab:IsShown())
end)

T.test("leader drawer: a click sweeps the card open, a second closes it", function()
    local _, ns = login("leader")
    local L = ns.Leader
    L.tab:Click()
    T.truthy(L.card:IsShown())
    T.truthy(L.driver:GetScript("OnUpdate"), "it sweeps")
    sweep(L)
    T.near(L.card:GetWidth(), L.WIDTH, 0.5, "open all the way")
    L.tab:Click()
    sweep(L)
    T.falsy(L.card:IsShown(), "closed")
end)

T.test("leader drawer: the buttons call the game's ready check, role check and countdown", function()
    local _, ns = login("leader")
    local L = ns.Leader
    L.Open()
    stub.groupCalls = {}
    L.readyButtons[1].button:Click()
    L.readyButtons[2].button:Click()
    L.pullButtons[2].button:Click()
    L.pullButtons[#L.pullButtons].button:Click()
    T.eq(table.concat(stub.groupCalls, " "), "DoReadyCheck() InitiateRolePoll() DoCountdown(10) DoCountdown(0)")
    T.eq(L.sent.seconds, 0, "the last one we sent")
end)

T.test("leader drawer: markers are secure buttons with our icons, skull first", function()
    local DUI, ns = login("leader")
    local t1, w1 = _G.DaylightUILeaderTarget1, _G.DaylightUILeaderWorld1
    T.eq(t1:GetAttribute("macrotext"), "/tm 8", "skull first")
    T.eq(t1.icon:GetTexture(), DUI.MEDIA .. "marker-8.png")
    T.eq(_G.DaylightUILeaderTargetClear:GetAttribute("macrotext"), "/tm 0")
    T.eq(w1:GetAttribute("type"), "worldmarker")
    T.eq(w1:GetAttribute("marker"), 8)
    T.eq(w1:GetAttribute("action1"), "set")
    T.eq(w1:GetAttribute("action2"), "clear", "right-click takes it away")
    T.eq(_G.DaylightUILeaderWorld2:GetAttribute("marker"), 4, "the game's order: cross next")
    T.eq(_G.DaylightUILeaderWorld2.icon:GetTexture(), DUI.MEDIA .. "marker-7.png", "wearing the cross")
    T.eq(_G.DaylightUILeaderWorld3.icon:GetTexture(), DUI.MEDIA .. "marker-6.png", "world 1 is the square")
    T.eq(_G.DaylightUILeaderWorldClear:GetAttribute("action"), "clear")
    T.isnil(_G.DaylightUILeaderWorldClear:GetAttribute("marker"), "every world marker")
    T.truthy(t1:IsProtected())
end)

T.test("leader drawer: in a fight the game's calls dim, the markers stay open", function()
    local _, ns = login("leader")
    local L = ns.Leader
    L.Open()
    sweep(L)
    stub.EnterCombat()
    T.truthy(L.readyButtons[1].button.off, "ready check dims")
    T.truthy(L.pullButtons[1].button.off, "pull dims")
    T.truthy(L.card:IsShown(), "stays open")
    stub.LeaveCombat()
    T.falsy(L.readyButtons[1].button.off)
end)

T.test("leader drawer: the tab opens and closes it in a fight, the markers ready at once", function()
    local _, ns = login("leader")
    local L = ns.Leader
    L.Open()
    sweep(L)
    L.Close()
    sweep(L)
    T.falsy(L.card:IsShown(), "closed before the fight")
    stub.EnterCombat()
    L.tab:Click()
    T.truthy(L.open, "open")
    T.truthy(L.card:IsShown())
    T.eq(L.card:GetWidth(), L.WIDTH, "its full width: nothing can sweep in a fight")
    T.eq(L.card:GetAlpha(), 1)
    T.truthy(_G.DaylightUILeaderTarget1:IsVisible(), "markers to click")
    T.eq(_G.DaylightUILeaderTarget1:GetParent():GetAlpha(), 1, "the rows are in place")
    L.tab:Click()
    T.falsy(L.open, "closed")
    T.falsy(L.card:IsShown())
    L.tab:Click()
    stub.LeaveCombat()
    T.truthy(L.open, "still open after the fight")
    L.tab:Click()
    sweep(L)
    T.falsy(L.card:IsShown(), "out of combat it sweeps closed as ever")
end)

T.test("leader drawer: never opened before the fight, it still opens whole", function()
    local _, ns = login("leader")
    local L = ns.Leader
    stub.EnterCombat()
    L.tab:Click()
    T.truthy(L.card:IsShown())
    T.eq(L.card:GetWidth(), L.WIDTH)
    T.truthy(_G.DaylightUILeaderWorld1:IsVisible())
    stub.LeaveCombat()
end)

T.test("leader drawer: opened by hand and closed in a fight, the tab goes after it", function()
    local DUI, ns = login("member", { party = true })
    DUI:Set("general", "motion", false)
    DUI.RunCommand("leader")
    local L = ns.Leader
    stub.EnterCombat()
    L.tab:Click()
    T.falsy(L.open)
    T.truthy(L.tab:IsShown(), "protected: it waits")
    stub.LeaveCombat()
    stub.RunTimers()
    T.falsy(L.tab:IsShown(), "gone once the fight ends")
end)

T.test("leader drawer: a fight starting mid-sweep finishes it at once", function()
    local _, ns = login("leader")
    local L = ns.Leader
    stub.secure = true
    L.Open()
    L.driver:GetScript("OnUpdate")(L.driver, 0.02)
    stub.EnterCombat()
    T.isnil(L.driver:GetScript("OnUpdate"), "nothing left moving")
    T.near(L.card:GetWidth(), L.WIDTH, 0.5)
    T.eq(#stub.errors, 0, table.concat(stub.errors, "\n"))
    stub.LeaveCombat()
    stub.secure = false
end)

T.test("leader drawer: role check isn't for a battleground", function()
    local _, ns = login("leader")
    stub.inBattleground = true
    ns.Leader.Refresh()
    T.truthy(ns.Leader.readyButtons[2].button.off)
    T.falsy(ns.Leader.readyButtons[1].button.off, "ready check still works")
    stub.inBattleground = nil
end)

-- ---------------------------------------------------------------------
-- The pull timer
-- ---------------------------------------------------------------------

-- The game's TimerTracker with a player countdown running in its frame.
local function gameTimer()
    local t = CreateFrame("Frame", "TimerTrackerTimer1", UIParent)
    t.type, t.isFree = Enum.StartTimerType.PlayerCountdown, false
    _G.TimerTracker = { timerList = { t } }
    return t
end

local function run(P, seconds)
    local d = P.frame
    for _ = 1, math.floor(seconds / 0.05) do
        stub.Advance(0.05)
        for _, c in ipairs({ d:GetChildren() }) do
            local f = c:GetScript("OnUpdate")
            if f then f(c, 0.05) end
        end
    end
end

T.test("pull timer: a countdown shows ours, the game's frame goes see-through", function()
    local _, ns = login("member")
    local P, t = ns.Pull, gameTimer()
    stub.FireEvent("START_PLAYER_COUNTDOWN", "Player-1", 10, 10, true, "Lead")
    T.truthy(P.frame:IsShown())
    T.truthy(P.Running())
    T.eq(t:GetAlpha(), 0, "the game's bar and numbers hidden")
    run(P, 7.5)
    T.eq(tostring(P.num:GetText()), "3", "three left")
    T.eq(P.num:GetTextColor(), (DaylightUI.Style.Accent()), "the last three in the accent")
    run(P, 3)
    T.falsy(P.Running(), "done")
    T.eq(t:GetAlpha(), 1, "the game's frame back for its next timer")
end)

T.test("pull timer: cancel hides it", function()
    local _, ns = login("member")
    local P, t = ns.Pull, gameTimer()
    stub.FireEvent("START_PLAYER_COUNTDOWN", "Player-1", 10, 10, true, "Lead")
    stub.FireEvent("CANCEL_PLAYER_COUNTDOWN", "Player-1", true, "Lead")
    T.falsy(P.Running())
    T.eq(t:GetAlpha(), 1)
end)

T.test("pull timer: secret seconds leave the game's own, unless we sent it", function()
    local _, ns = login("leader")
    local P, t = ns.Pull, gameTimer()
    stub.FireEvent("START_PLAYER_COUNTDOWN", stub.Secret("Player-1"), stub.Secret(10), stub.Secret(10), true, stub.Secret("Lead"))
    T.falsy(P.Running(), "someone else's: the game's shows")
    T.eq(t:GetAlpha(), 1)
    ns.Leader.Open()
    ns.Leader.pullButtons[3].button:Click()      -- 15
    stub.FireEvent("START_PLAYER_COUNTDOWN", stub.Secret("Player-1"), stub.Secret(15), stub.Secret(15), true, stub.Secret("Me"))
    T.truthy(P.Running(), "ours: we know it")
    T.eq(t:GetAlpha(), 0)
end)

T.test("pull timer: switched off, the game's own shows", function()
    local DUI, ns = login("member")
    local t = gameTimer()
    DUI:Set("UnitFrames", "pull.enabled", false)
    stub.FireEvent("START_PLAYER_COUNTDOWN", "Player-1", 10, 10, true, "Lead")
    T.falsy(ns.Pull.Running())
    T.eq(t:GetAlpha(), 1)
    T.truthy(DUI.Movers.Get("unitframes.pull"), "it has an unlock handle")
end)

-- ---------------------------------------------------------------------
-- Ready check answers on the tiles
-- ---------------------------------------------------------------------

local function raidTile(ns, unit, data)
    local b = CreateFrame("Button", "DaylightUIRaidHeaderUnitButton3", ns.Raid.header)
    b:SetAttribute("unit", unit)
    stub.units[unit] = data
    ns.Raid.header.initialConfigFunction(ns.Raid.header, b:GetName())
    return b
end

T.test("ready check: each tile shows its answer, no answer turns to not ready, then they go", function()
    local DUI, ns = login("leader")
    DUI:Set("general", "motion", false)
    local b = raidTile(ns, "raid2", { name = "Adolin", isPlayer = true, class = "WARRIOR", ready = "waiting" })
    T.falsy(b.readyIcon:IsShown(), "nothing before a check")
    stub.FireEvent("READY_CHECK", "Me", 35)
    T.truthy(b.readyIcon:IsShown())
    T.eq(b.readyIcon:GetTexture(), DUI.MEDIA .. "status-waiting.png")
    stub.units.raid2.ready = "ready"
    stub.FireEvent("READY_CHECK_CONFIRM", "raid2", true)
    stub.RunTimers()
    T.eq(b.readyIcon:GetTexture(), DUI.MEDIA .. "status-ready.png")
    local c = DUI.Style.INK.GOOD
    T.eq(select(2, b.readyIcon:GetVertexColor()), c[2], "in the good color")
    stub.units.raid2.ready = "waiting"
    stub.FireEvent("READY_CHECK_FINISHED", false)
    T.eq(b.readyIcon:GetTexture(), DUI.MEDIA .. "status-notready.png", "no answer at the end = not ready")
    stub.RunTimers()
    T.falsy(b.readyIcon:IsShown(), "gone a few seconds later")
end)

T.test("ready check: the icon eases away on a tile faded by a secret range answer", function()
    local DUI, ns = login("leader")
    DUI:Set("general", "motion", true)
    local b = raidTile(ns, "raid2", { name = "Adolin", isPlayer = true, class = "WARRIOR", ready = "waiting",
        party = true, inRange = stub.Secret(false) })
    ns.UF.UpdateRange(b)
    T.truthy(issecretvalue(b.readyIcon:GetAlpha()), "the tile's range fade makes its icons' alpha secret")
    stub.FireEvent("READY_CHECK", "Me", 35)
    stub.units.raid2.ready = "ready"
    stub.FireEvent("READY_CHECK_CONFIRM", "raid2", true)
    stub.FireEvent("READY_CHECK_FINISHED", false)
    stub.errors = {}
    stub.RunTimers()
    local d = DUI.Motion.Driver()
    for _ = 1, 60 do
        if not (d and d:GetScript("OnUpdate")) then break end
        stub.RunOnUpdate(d, 1 / 60)
    end
    T.eq(#stub.errors, 0, stub.errors[1])
    T.falsy(b.readyIcon:IsShown(), "gone after the check")
end)

T.test("ready check: placed on its spot, size from the settings, switchable", function()
    local DUI, ns = login("leader")
    local b = raidTile(ns, "raid2", { name = "Adolin", isPlayer = true, class = "WARRIOR", ready = "ready" })
    T.near(b.readyIcon:GetWidth(), 14, 0.01)
    local _, rel = b.readyIcon:GetPoint(1)
    T.eq(rel, b.health, "on the bar's right edge")
    DUI:Set("UnitFrames", "raid.readySize", 20)
    T.near(b.readyIcon:GetWidth(), 20, 0.01)
    stub.FireEvent("READY_CHECK", "Me", 35)
    T.truthy(b.readyIcon:IsShown())
    DUI:Set("UnitFrames", "raid.showReady", false)
    T.falsy(b.readyIcon:IsShown(), "off: nothing")
end)

T.test("ready check: the Raid page's preview tile shows one", function()
    local _, ns = login("leader")
    local s = ns.Raid.FullSample()
    T.eq(s.ready, "ready")
end)

-- ---------------------------------------------------------------------
-- Practice: test mode with no group (/dui leader)
-- ---------------------------------------------------------------------

T.test("practice: /dui leader test opens the drawer on the sample raid and plays a ready check, then a pull", function()
    local DUI, ns = login("alone")
    DUI:Set("general", "motion", false)
    stub.groupCalls = {}
    DUI.RunCommand("leader test")
    stub.RunTimers()
    local L = ns.Leader
    T.truthy(DUI.testMode, "test mode on")
    T.truthy(L.tab:IsShown(), "the tab beside the sample raid")
    T.truthy(L.open, "the drawer open")
    T.truthy(ns.Raid.group.preview[1]:IsShown(), "beside the sample raid")
    T.truthy(ns.Pull.Running(), "then a pull")
    T.eq(#stub.groupCalls, 0, "nothing asked of the game")
    DUI.SetTestMode(false)
end)

T.test("practice: the drawer's buttons play samples, role check dims", function()
    local DUI, ns = login("alone")
    DUI:Set("general", "motion", false)
    DUI.SetTestSolo({ "raid" })
    stub.RunTimers()
    local L = ns.Leader
    L.Open()
    stub.groupCalls = {}
    L.readyButtons[1].button:Click()
    L.pullButtons[2].button:Click()
    T.eq(#stub.groupCalls, 0, "practice asks the game nothing")
    local waiting = 0
    for _, b in ipairs(ns.Raid.group.preview) do
        if b:IsShown() and b.readyIcon:IsShown() then waiting = waiting + 1 end
    end
    T.truthy(waiting > 0, "a ? on each sample tile")
    stub.RunTimers()
    T.falsy(ns.Raid.group.preview[1].readyIcon:IsShown(), "and gone after the check")
    T.truthy(ns.Pull.Running(), "a sample pull")
    T.truthy(L.readyButtons[2].button.off, "no role check to practice")
    L.pullButtons[#L.pullButtons].button:Click()
    T.falsy(ns.Pull.Running(), "Cancel stops it")
end)

T.test("practice: in a group /dui leader test says so and changes nothing", function()
    local DUI = login("leader")
    DUI.RunCommand("leader test")
    T.falsy(DUI.testMode)
end)

T.test("practice: /dui leader test party uses the sample party", function()
    local DUI, ns = login("alone")
    DUI:Set("general", "motion", false)
    DUI.RunCommand("leader test party")
    stub.RunTimers()
    T.truthy(ns.Leader.tab:IsShown())
    T.truthy(ns.Leader.open)
end)

-- ---------------------------------------------------------------------
-- /dui leader: open it by hand
-- ---------------------------------------------------------------------

T.test("/dui leader opens and closes the drawer for a leader", function()
    local DUI, ns = login("leader")
    DUI:Set("general", "motion", false)
    DUI.RunCommand("leader")
    T.truthy(ns.Leader.open)
    DUI.RunCommand("leader")
    T.falsy(ns.Leader.open)
    T.truthy(ns.Leader.tab:IsShown(), "a leader keeps the tab")
end)

T.test("/dui leader: a party member gets the markers; the tab goes when closed", function()
    local DUI, ns = login("member", { party = true })
    DUI:Set("general", "motion", false)
    T.falsy(ns.Leader.tab and ns.Leader.tab:IsShown(), "no tab of its own")
    DUI.RunCommand("leader")
    local L = ns.Leader
    T.truthy(L.tab:IsShown())
    T.truthy(L.open)
    T.truthy(L.readyButtons[1].button.off, "ready check is the leader's")
    T.truthy(L.pullButtons[1].button.off, "so is the pull")
    T.truthy(_G.DaylightUILeaderTarget1:IsVisible(), "markers to click")
    DUI.RunCommand("leader")
    T.falsy(L.tab:IsShown(), "closed: the tab goes")
end)

-- A party member, not the leader, with a role.
local function member(role, opts)
    opts = opts or {}
    return stub.Load({ module = true, before = function()
        stub.units.player = { name = "Me", class = "WARRIOR", isPlayer = true, role = role }
        stub.SetGroup(true, opts.raid == true, opts.raid and 10 or 5)
    end })
end

T.test("a party's tank gets the markers without leading; a raid's doesn't", function()
    local DUI, ns = member("TANK")
    local L = ns.Leader
    T.truthy(L.tab and L.tab:IsShown(), "the tank has the tab")
    DUI:Set("general", "motion", false)
    L.Open()
    T.truthy(L.open)
    T.truthy(_G.DaylightUILeaderTarget1:IsVisible(), "markers to click")
    T.truthy(L.readyButtons[1].button.off, "ready check is still the leader's")
    T.truthy(L.pullButtons[1].button.off, "so is the pull")
    L.Close(true)
    T.truthy(L.tab:IsShown(), "closed: the tab stays, unlike /dui leader's")

    _, ns = member("TANK", { raid = true })
    T.falsy(ns.Leader.tab and ns.Leader.tab:IsShown(), "the game lets only a raid's leader and assists mark")
    _, ns = member("HEALER")
    T.falsy(ns.Leader.tab and ns.Leader.tab:IsShown(), "a healer who doesn't lead gets nothing")
end)

T.test("the tab follows your role, keeps it while the role is secret", function()
    local DUI, ns = member("DAMAGER")
    local L = ns.Leader
    T.falsy(L.tab and L.tab:IsShown(), "damage: no tab")
    stub.units.player.role = "TANK"
    stub.FireEvent("PLAYER_ROLES_ASSIGNED")
    stub.RunTimers()
    T.truthy(L.tab and L.tab:IsShown(), "picked tank: the tab comes")
    stub.units.player.role = stub.Secret("TANK")
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    stub.RunTimers()
    T.truthy(L.tab:IsShown(), "a secret role (a restricted map) keeps the last plain one")
    DUI:Set("general", "motion", false)
    stub.units.player.role = "DAMAGER"
    stub.FireEvent("PLAYER_ROLES_ASSIGNED")
    stub.RunTimers()
    T.falsy(L.tab:IsShown(), "back to damage: the tab goes")
end)

T.test("Show leader tools: leading only, or anyone in a party", function()
    local DUI, ns = member("TANK")
    local L = ns.Leader
    DUI:Set("general", "motion", false)
    DUI:Set("UnitFrames", "leader.show", "lead")
    T.falsy(L.tab:IsShown(), "only while you lead")
    DUI:Set("UnitFrames", "leader.show", "party")
    T.truthy(L.tab:IsShown(), "in a party")
    DUI, ns = member("HEALER")
    DUI:Set("UnitFrames", "leader.show", "party")
    T.truthy(ns.Leader.tab and ns.Leader.tab:IsShown(), "any role")
    DUI, ns = member("HEALER", { raid = true })
    DUI:Set("UnitFrames", "leader.show", "party")
    T.falsy(ns.Leader.tab and ns.Leader.tab:IsShown(), "not a raid member without assist")
end)

T.test("/dui leader: a raid member can't, alone it points to the test", function()
    local DUI, ns = login("member")
    DUI.RunCommand("leader")
    T.falsy(ns.Leader.open)
    _, ns = login("alone")
    DaylightUI.RunCommand("leader")
    T.falsy(ns.Leader.open)
    T.falsy(DaylightUI.testMode)
end)

T.test("ready check: a tile answering ready shines; everyone ready ripples a light across them", function()
    local DUI, ns = login("leader")
    local b = raidTile(ns, "raid2", { name = "Adolin", isPlayer = true, class = "WARRIOR", ready = "waiting" })
    b:Show()
    stub.FireEvent("READY_CHECK", "Me", 35)
    local h = b.moments and b.moments.body
    T.falsy(h and h.light:IsShown(), "waiting: nothing")
    stub.units.raid2.ready = "ready"
    stub.FireEvent("READY_CHECK_CONFIRM", "raid2", true)
    stub.RunTimers()
    h = b.moments and b.moments.body
    T.truthy(h and h.light:IsShown(), "answering ready shines")
    local c = DUI.Style.INK.GOOD
    T.near(select(2, h.light:GetVertexColor()), c[2], 0.001, "in the good color")
    T.truthy(ns.Moments.EveryoneReady(), "the only tile shown is ready")
    stub.FireEvent("READY_CHECK_FINISHED", false)
    local r, g = DUI.Style.Accent()
    T.near(select(2, h.light:GetVertexColor()), g, 0.001, "everyone ready: the accent runs across")
end)

T.test("ready check: an answer that lands as it ends gets the ripple alone, not cut off by its own light", function()
    local DUI, ns = login("leader")
    local b = raidTile(ns, "raid2", { name = "Adolin", isPlayer = true, class = "WARRIOR", ready = "waiting" })
    b:Show()
    stub.FireEvent("READY_CHECK", "Me", 35)
    stub.units.raid2.ready = "ready"
    local real, lit = ns.Moments.Ready, 0
    ns.Moments.Ready = function(...) lit = lit + 1; return real(...) end
    stub.FireEvent("READY_CHECK_FINISHED", false)
    ns.Moments.Ready = real
    T.eq(lit, 0, "no single light the ripple would restart")
    local h = b.moments and b.moments.body
    local _, g = DUI.Style.Accent()
    T.truthy(h and h.light:IsShown(), "the ripple runs")
    T.near(select(2, h.light:GetVertexColor()), g, 0.001)
    T.eq(b.readyStatus, "ready", "the answer still shows")
end)
