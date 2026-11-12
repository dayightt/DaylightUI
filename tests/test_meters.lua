local stub = require("stub")

-- The meters: the windows, their rows, header, fights, the threat views, the
-- hover tip, the breakdown window, the death log, the summary and the Meters
-- options page.

-- ---------------------------------------------------------------------
-- The fake game's damage meter (stub.DamageMeter), as the client has it
-- ---------------------------------------------------------------------

T.test("fake game: the damage meter's types are the game's", function()
    stub.Load({ infopanel = true })
    T.eq(Enum.DamageMeterType.DamageDone, 0)
    T.eq(Enum.DamageMeterType.Dps, 1)
    T.eq(Enum.DamageMeterType.HealingDone, 2)
    T.eq(Enum.DamageMeterType.Absorbs, 4)
    T.eq(Enum.DamageMeterType.Deaths, 9)
    T.eq(Enum.DamageMeterType.EnemyDamageTaken, 10)
    T.eq(Enum.DamageMeterSessionType.Overall, 0)
    T.eq(Enum.DamageMeterSessionType.Current, 1)
    T.eq(Enum.DamageMeterSessionType.Expired, 2)
end)

T.test("fake game: each meter type answers its own list, the session its total and length", function()
    stub.Load({ infopanel = true })
    local E = Enum.DamageMeterType
    stub.meter.sources = {
        [E.DamageDone] = { { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 300, amountPerSecond = 30 },
                           { name = "Shallan", classFilename = "MAGE", totalAmount = 100, amountPerSecond = 10 } },
        [E.HealingDone] = { { name = "Navani", classFilename = "PRIEST", totalAmount = 50, amountPerSecond = 5 } },
    }
    stub.meter.durations = { [Enum.DamageMeterSessionType.Current] = 94 }
    local s = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, E.DamageDone)
    T.eq(#s.combatSources, 2)
    T.eq(s.totalAmount, 400, "the session's total is its sources'")
    T.eq(s.maxAmount, 300)
    T.eq(s.durationSeconds, 94)
    local h = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, E.HealingDone)
    T.eq(h.combatSources[1].name, "Navani")
    T.eq(C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current), 94)
    T.eq(#C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, E.Interrupts).combatSources, 0,
        "a type with no list has nobody")
end)

T.test("fake game: in a fight a session's amounts and names are secret, its class and spec plain", function()
    stub.Load({ infopanel = true })
    stub.meter.sources = { { name = "Kaladin", sourceGUID = "Player-2", classFilename = "WARRIOR", specIconID = 132355,
                             isLocalPlayer = false, deathRecapID = 7, totalAmount = 300, amountPerSecond = 30 } }
    stub.EnterCombat()
    local s = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    local src = s.combatSources[1]
    T.truthy(issecretvalue(s.totalAmount), "the session's total")
    T.truthy(issecretvalue(src.totalAmount), "a source's amount")
    T.truthy(issecretvalue(src.amountPerSecond))
    T.truthy(issecretvalue(src.name), "a source's name")
    T.truthy(issecretvalue(src.sourceGUID), "a source's GUID")
    T.falsy(issecretvalue(src.classFilename), "the class stays plain (NeverSecret)")
    T.truthy(issecretvalue(src.specIconID), "the spec icon too (seen in game, though its docs say never)")
    T.falsy(issecretvalue(src.isLocalPlayer))
    T.falsy(issecretvalue(src.deathRecapID))
    T.eq(src.classFilename, "WARRIOR")
end)

T.test("fake game: a source's spells and the fights list", function()
    stub.Load({ infopanel = true })
    stub.meter.spells = { { spellID = 1, totalAmount = 70, amountPerSecond = 7,
                            combatSpellDetails = { unitName = "Sadeas", unitClassFilename = "", amount = 70 } } }
    stub.meter.fights = { { sessionID = 1, name = "Sadeas", durationSeconds = 94 } }
    local src = C_DamageMeter.GetCombatSessionSourceFromType(Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.DamageDone, "Player-1")
    T.eq(src.combatSpells[1].spellID, 1)
    T.eq(src.totalAmount, 70)
    T.eq(stub.meter.askedSource[3], "Player-1")
    T.eq(C_DamageMeter.GetAvailableCombatSessions()[1].name, "Sadeas")
    stub.EnterCombat()
    local s = C_DamageMeter.GetCombatSessionSourceFromType(Enum.DamageMeterSessionType.Current,
        Enum.DamageMeterType.DamageDone, "Player-1")
    T.truthy(issecretvalue(s.combatSpells[1].totalAmount), "a spell's amount in a fight")
    T.truthy(issecretvalue(s.combatSpells[1].combatSpellDetails.unitName), "the unit on the other end")
    T.falsy(issecretvalue(s.combatSpells[1].combatSpellDetails.unitClassFilename), "its class (NeverSecret)")
end)

T.test("fake game: a death recap answers its events and max health", function()
    stub.Load({ infopanel = true })
    stub.meter.recaps = { [7] = { maxHealth = 1000, events = {
        { event = "SPELL_DAMAGE", timestamp = 10.5, spellId = 1, spellName = "Fireball", sourceName = "Sadeas",
          amount = 400, overkill = 120, currentHP = 0 },
        { event = "SWING_DAMAGE", timestamp = 9, amount = 300, currentHP = 400 },
    } } }
    T.truthy(C_DeathRecap.HasRecapEvents(7))
    T.falsy(C_DeathRecap.HasRecapEvents(8))
    T.eq(#C_DeathRecap.GetRecapEvents(7), 2)
    T.eq(C_DeathRecap.GetRecapEvents(7)[1].overkill, 120, "newest first: the killing blow")
    T.eq(C_DeathRecap.GetRecapMaxHealth(7), 1000)
end)

-- ---------------------------------------------------------------------
-- Windows: the list, each window's settings, its framed window
-- ---------------------------------------------------------------------

local PW = require("panelworld")
local login = PW.login

local function W() return stub.infopanel.Windows end
local function F() return stub.infopanel.MeterFrame end
local function host(id) return F().hosts[id] end
local function rows(id) return PW.bars(host(id).area) end
-- Runs every tween to its end (a window's fade in or out).
local function tweens() stub.RunOnUpdate(DaylightUI.Motion.Driver(), 1) end

T.test("windows: the panel's meter and the threat meter are always listed, first, and can't be removed", function()
    local DUI = login()
    local list = W().List()
    T.eq(#list, 2)
    T.eq(list[1].id, "main"); T.eq(list[1].kind, "meter"); T.eq(list[1].path, "meter")
    T.eq(list[2].id, "threat"); T.eq(list[2].kind, "threat"); T.eq(list[2].path, "threat")
    T.eq(list[1].cfg, DUI:Get("InfoPanel", "meter"), "its live settings")
    T.falsy(W().Remove("main"))
    T.falsy(W().Remove("threat"))
    T.eq(#W().List(), 2)
end)

T.test("windows: a new window from a preset gets its own settings and a framed window you move in unlock mode", function()
    local DUI = login()
    local id = W().Add("healing")
    T.eq(id, "w1")
    stub.RunTimers()
    T.eq(DUI:Get("InfoPanel", "meters.windows.w1.mode"), "healing")
    T.eq(DUI:Get("InfoPanel", "meters.windows.w1.rowHeight"), 22, "the template's look")
    T.eq(W().List()[3].id, "w1")
    local h = host("w1")
    T.truthy(h, "a window made for it")
    T.eq(h.frame:GetName(), "DaylightUIMeterWindow_w1")
    T.truthy(h.frame:IsShown())
    T.truthy(DUI.Style.GetShell(h.body), "framed like the panel (inside the frame the fade owns)")
    local mover = DUI.Movers.Get("infopanel.meter.w1")
    T.truthy(mover, "it moves in unlock mode")
    T.falsy(mover.suspended)
    stub.meter.sources = { { name = "Navani", classFilename = "PRIEST", totalAmount = 900 } }
    h.view.Draw()
    T.eq(stub.meter.asked[2], Enum.DamageMeterType.HealingDone, "asks for healing")
    T.truthy(rows("w1")[1]:IsShown())
    T.eq(rows("w1")[1].meter, h.view, "its rows know their meter")
    stub.infopanel.Meter.Draw()
    T.eq(stub.meter.asked[2], Enum.DamageMeterType.DamageDone, "the panel's still shows damage")
    -- Its own size and bars.
    DUI:Set("InfoPanel", "meters.windows.w1.width", 250)
    DUI:Set("InfoPanel", "meters.windows.w1.rowHeight", 15)
    stub.RunTimers()
    T.truthy(h.frame:GetWidth() > 250, "the window wraps the meter")
    T.eq(rows("w1")[1]:GetHeight(), 15)
    T.eq(PW.bars(stub.infopanel.Panel.meterArea)[1]:GetHeight(), 18, "the panel's meter's bars unchanged")
    DUI:Set("InfoPanel", "panelAlphaOwn", true)
    DUI:Set("InfoPanel", "panelAlpha", 0.4)
    stub.RunTimers()
    T.eq(DUI.Style.GetShell(h.body).opts.bgAlpha, 0.4, "its window takes the panel's background")
end)

T.test("windows: the eleventh window is refused", function()
    login()
    for i = 1, W().MAX do T.eq(W().Add("damage"), "w" .. i) end
    T.isnil(W().Add("damage"))
    T.eq(#W().Own(), W().MAX)
end)

T.test("windows: deleting a window fades it, suspends its handle and drops its settings", function()
    local DUI = login()
    W().Add("damage")
    local id = W().Add("healing")
    stub.RunTimers()
    local h = host(id)
    T.truthy(h.frame:IsShown())
    T.eq(h.body:GetAlpha(), 0, "it eases in")
    tweens()
    T.eq(h.body:GetAlpha(), 1)
    T.truthy(W().Remove(id))
    stub.RunTimers()
    T.truthy(h.frame:IsShown(), "it fades, not snaps")
    tweens()
    T.falsy(h.frame:IsShown(), "gone once faded")
    T.truthy(DUI.Movers.Get("infopanel.meter." .. id).suspended, "no handle left behind")
    T.isnil(DUI:Get("InfoPanel", "meters.windows." .. id))
    T.eq(#W().Own(), 1)
    -- A new window never reuses a removed one's id, since its spot was saved under it.
    T.eq(W().Add("damage"), "w3")
end)

T.test("windows: renaming and reordering keep each window's settings", function()
    local DUI = login()
    local a, b = W().Add("damage"), W().Add("healing")
    T.eq(W().Name(W().Get(nil, a)), DUI.L["Damage"], "named for its preset")
    T.truthy(W().Rename(a, "  Raid DPS "))
    T.eq(W().Name(W().Get(nil, a)), "Raid DPS")
    T.truthy(W().Move(b, -1))
    T.eq(W().Own()[1].id, b)
    T.eq(W().Own()[2].cfg.name, "Raid DPS")
    T.falsy(W().Move(b, -1), "already first")
    T.eq(DUI:Get("InfoPanel", "meters.windows." .. b .. ".mode"), "healing")
end)

T.test("windows: an old second meter becomes window 2 with its own look; one never touched upgrades to nothing", function()
    login()
    local p = { modules = { InfoPanel = { meter = { inGroup = true },
        meter2 = { enabled = true, mode = "taken", rowHeight = 18 } } },
        positions = { ["infopanel.meter2"] = { 10, 20 } }, general = { frameScales = { ["infopanel.meter2"] = 1.2 } } }
    W().Upgrade(p)
    local ip = p.modules.InfoPanel
    T.isnil(ip.meter2)
    local w = ip.meters.windows.w2
    T.eq(w.kind, "meter"); T.eq(w.mode, "taken"); T.eq(w.rowHeight, 18); T.truthy(w.enabled)
    T.truthy(w.inGroup, "it followed the first meter's group rule")
    T.eq(ip.meters.order[1], "w2")
    T.eq(ip.meters.next, 3)
    T.deq(p.positions["infopanel.meter.w2"], { 10, 20 }, "its spot goes with it")
    T.isnil(p.positions["infopanel.meter2"])
    T.eq(p.general.frameScales["infopanel.meter.w2"], 1.2, "and its own size")
    T.truthy(p.meters1)
    W().Upgrade(p)
    T.eq(#ip.meters.order, 1, "once")
    local q = { modules = { InfoPanel = { meter = {} } } }
    W().Upgrade(q)
    T.isnil(q.modules.InfoPanel.meters, "never touched: no window")
end)

T.test("windows: a changed but switched-off second meter upgrades to a switched-off window 2", function()
    login()
    local p = { modules = { InfoPanel = { meter2 = { width = 300 } } } }
    W().Upgrade(p)
    local w = p.modules.InfoPanel.meters.windows.w2
    T.eq(w.enabled, false)
    T.eq(w.mode, "healing", "the old second meter's mode")
    T.eq(w.width, 300)
end)

T.test("windows: the profile's settings refilled in place make its windows", function()
    local DUI = login()
    W().Add("damage")
    stub.RunTimers()
    T.truthy(host("w1").frame:IsShown())
    local mod = DUI:GetModule("InfoPanel")
    mod.db.meters = { order = { "w5" }, next = 6, windows = { w5 = { kind = "meter", mode = "deaths" } } }
    stub.infopanel.Refresh(mod)
    tweens()
    T.falsy(host("w1").frame:IsShown(), "the old profile's window goes")
    T.truthy(host("w5").frame:IsShown(), "the new one's comes")
    T.eq(DUI:Get("InfoPanel", "meters.windows.w5.rowHeight"), 22, "filled from its template")
end)

T.test("windows: a hidden window never draws", function()
    local DUI = login()
    W().Add("damage")
    DUI:Set("InfoPanel", "meters.windows.w1.inGroup", true)
    stub.RunTimers()
    local h = host("w1")
    T.falsy(h.frame:IsShown(), "solo: away")
    local asked, get = 0, C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType = function(...) asked = asked + 1; return get(...) end
    stub.EnterCombat()
    h.view.Tick(true)
    T.eq(asked, 0, "a hidden window reads nothing")
    C_DamageMeter.GetCombatSessionFromType = get
    stub.LeaveCombat()
end)

T.test("windows: a new window's settings are stripped against its template at logout and filled back at login", function()
    local DUI = login()
    W().Add("healing")
    DUI:Set("InfoPanel", "meters.windows.w1.rowHeight", 30)
    W().StripAll()
    local w = DUI:GetModule("InfoPanel").db.meters.windows.w1
    T.eq(w.rowHeight, 30, "a change kept")
    T.isnil(w.width, "the template's own value dropped")
    T.eq(w.kind, "meter", "its kind always kept")
    W().Fill(DUI:GetModule("InfoPanel").db)
    T.eq(w.width, 207, "filled back")
end)

T.test("windows: each window waits for a group, combat or an instance by its own rules", function()
    local DUI = login()
    W().Add("healing")
    local P = "meters.windows.w1."
    stub.RunTimers()
    local f = host("w1").frame
    DUI:Set("InfoPanel", P .. "inGroup", true)
    stub.RunTimers(); tweens()
    T.falsy(f:IsShown(), "solo: away")
    stub.inGroup = true
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.truthy(f:IsShown(), "in a group: back")
    DUI:Set("InfoPanel", P .. "inCombat", true)
    stub.RunTimers(); tweens()
    T.falsy(f:IsShown())
    stub.EnterCombat()
    T.truthy(f:IsShown(), "in a group and in combat")
    stub.LeaveCombat()
    tweens()
    T.falsy(f:IsShown())
    DUI:Set("InfoPanel", P .. "inGroup", false)
    DUI:Set("InfoPanel", P .. "inCombat", false)
    DUI:Set("InfoPanel", P .. "inInstance", true)
    stub.RunTimers(); tweens()
    T.falsy(f:IsShown(), "outside: away")
    local was = _G.IsInInstance
    _G.IsInInstance = function() return true, "party" end
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    T.truthy(f:IsShown(), "in an instance: back")
    _G.IsInInstance = was
    -- The panel's meter folded away by its tab doesn't take it along.
    DUI:Set("InfoPanel", P .. "inInstance", false)
    DUI:Set("InfoPanel", "meter.enabled", false)
    stub.RunTimers()
    T.truthy(f:IsShown())
    DUI:Set("InfoPanel", P .. "enabled", false)
    stub.RunTimers(); tweens()
    T.falsy(f:IsShown(), "switched off")
end)

T.test("windows: unlocked, a window resizes from its corner into its own settings", function()
    local DUI = login()
    W().Add("healing")
    stub.RunTimers()
    local h = host("w1")
    T.falsy(h.grip:IsShown(), "locked: no grip")
    DUI.Movers.Unlock()
    T.truthy(h.grip:IsShown(), "unlocked: a grip in the corner")
    local edge = h.frame:GetWidth() - DUI:Get("InfoPanel", "meters.windows.w1.width")
    local save, saved = DUI.Movers.Save, nil
    DUI.Movers.Save = function(key, ...) saved = key; return save(key, ...) end
    h.grip:GetScript("OnMouseDown")(h.grip)
    h.frame:SetSize(240 + edge, 150 + edge)
    h.grip:GetScript("OnMouseUp")(h.grip)
    DUI.Movers.Save = save
    T.eq(saved, "infopanel.meter.w1", "its own place kept")
    T.eq(DUI:Get("InfoPanel", "meters.windows.w1.width"), 240)
    T.eq(DUI:Get("InfoPanel", "meters.windows.w1.height"), 150)
    T.eq(DUI:Get("InfoPanel", "meter.width"), 207, "the panel's meter's size untouched")
    DUI.Movers.Lock()
    T.falsy(h.grip:IsShown())
end)

T.test("windows: each new one starts bottom-right, left of the ones before it still at their first spot", function()
    local DUI = login()
    local P = stub.infopanel.Panel
    W().Add("damage")
    stub.RunTimers()
    local home = F().Home("w1")
    T.eq(home[1], "BOTTOMRIGHT"); T.eq(home[4], -P.EDGE)
    DUI:Set("InfoPanel", "meter.detached", true)
    stub.RunTimers()
    local first = -P.EDGE - P.meterFrame:GetWidth() - F().GAP
    T.eq(F().Home("w1")[4], first, "beside the panel meter's own window")
    W().Add("healing")
    stub.RunTimers()
    T.eq(F().Home("w2")[4], first - host("w1").frame:GetWidth() - F().GAP, "left of the one before")
    DUI.DB.Positions()["infopanel.meter.w1"] = { 100, 100 }
    T.eq(F().Home("w2")[4], first, "that one moved away: its place is free")
end)

T.test("windows: the breakdown reads a window's own mode and fight", function()
    local DUI = login()
    local B = stub.infopanel.Breakdown
    W().Add("healing")
    stub.RunTimers()
    local M2 = host("w1").view
    stub.meter.spells = { { spellID = 1, totalAmount = 40 } }
    stub.meter.sources = { { name = "Navani", classFilename = "PRIEST", totalAmount = 40, sourceGUID = "Player-2" } }
    M2.Draw()
    B.Spells(rows("w1")[1].src, M2)
    T.eq(stub.meter.askedSource[2], Enum.DamageMeterType.HealingDone, "the window's mode")
    M2.fight = 7
    B.Spells(rows("w1")[1].src, M2)
    T.eq(stub.meter.askedSource[1], "id"); T.eq(stub.meter.askedSource[2], 7, "and its picked fight")
    DUI.SetTestMode(true)
    local spells = B.Spells({ name = "Navani", totalAmount = 1000 }, M2)
    T.eq(spells[1].name, B.SAMPLE.healing[1][1], "its own sample, by its own mode")
end)

T.test("windows: a reset clears every fight and every window's pick", function()
    local DUI = login()
    W().Add("healing")
    stub.RunTimers()
    local M2, M = host("w1").view, stub.infopanel.Meter
    DUI:Set("InfoPanel", "meters.windows.w1.session", "overall")
    M.fight, M2.fight = 3, 4
    M.ResetAll()
    T.truthy(stub.meter.reset)
    T.isnil(M.fight); T.isnil(M2.fight)
    T.eq(DUI:Get("InfoPanel", "meters.windows.w1.session"), "current")
end)

T.test("windows: test mode shows their samples, with one box for them all", function()
    local DUI = login()
    W().Add("healing")
    DUI:Set("InfoPanel", "meters.windows.w1.inGroup", true)
    stub.RunTimers(); tweens()
    local h = host("w1")
    T.falsy(h.frame:IsShown())
    DUI.SetTestMode(true)
    T.truthy(h.frame:IsShown(), "test mode brings it out")
    h.view.Draw()
    T.eq(rows("w1")[1].bar:GetValue(), stub.infopanel.Meter.SampleFor("healing")[1].totalAmount, "the healing sample")
    DUI.SetTestPartShown("meters", false)
    tweens()
    T.falsy(h.frame:IsShown(), "its box unticked: as it would be, solo")
    T.falsy(h.view.Sample())
    T.truthy(stub.infopanel.Meter.Sample(), "the panel's meter keeps its sample")
end)

T.test("windows: they fade with the panel", function()
    local DUI = login()
    local P, Fd = stub.infopanel.Panel, DaylightUI.Fade
    W().Add("healing")
    DUI:Set("InfoPanel", "fade.mode", "always")
    DUI:Set("InfoPanel", "fade.alpha", 0.25)
    stub.RunTimers()
    stub.Advance(10)
    Fd.Step()
    for _ = 1, 120 do stub.RunOnUpdate(Fd.driver, 1 / 60) end
    T.near(P.holder:GetAlpha(), 0.25, 1e-6)
    T.near(host("w1").frame:GetAlpha(), 0.25, 1e-6, "its window fades along")
end)

T.test("windows: secret amounts and names in a fight go straight through", function()
    login()
    W().Add("healing")
    stub.RunTimers()
    stub.EnterCombat()
    stub.meter.sources = { { name = "Navani", classFilename = "PRIEST", totalAmount = 900, amountPerSecond = 90 } }
    host("w1").view.Draw()
    T.truthy(rows("w1")[1]:IsShown())
    stub.LeaveCombat()
end)

-- ---------------------------------------------------------------------
-- The rows: rank, icon, total / rate / share, you pinned, empty text
-- ---------------------------------------------------------------------

local function mainRows() return PW.bars(stub.infopanel.Panel.meterArea) end
-- A meter's rows that fit its area, in order.
local function fitting(m)
    local out = {}
    for _, r in ipairs(m.rows) do if r.fits and r:IsShown() then out[#out + 1] = r end end
    return out
end
local function raid(n, me)
    local list = {}
    for i = 1, n do
        list[i] = { name = "P" .. i, classFilename = "MAGE", totalAmount = 1000 - i, amountPerSecond = 100 - i,
                    isLocalPlayer = i == me, sourceGUID = "Player-" .. (100 + i) }
    end
    return list
end

T.test("meters: a row shows its rank, the player's spec icon, the name and \"total (rate, share)\"", function()
    login()
    local M = stub.infopanel.Meter
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", specIconID = 132355,
                             totalAmount = 2640, amountPerSecond = 330 },
                           { name = "Shallan", classFilename = "MAGE", specIconID = 135932,
                             totalAmount = 2400, amountPerSecond = 300 } }
    stub.meter.total = 14667
    M.Draw()
    local r = mainRows()[1]
    T.eq(stub.Text(r.rank), "1")
    T.eq(stub.Plain(r.icon:GetTexture()), 132355, "the spec's icon")
    T.truthy(r.icon:IsShown())
    T.eq(stub.Text(r.name), "Kaladin")
    T.eq(stub.Text(r.amount), "330 (2.6K, 18%)")
    T.eq(stub.Text(mainRows()[2].rank), "2")
end)

T.test("meters: total, rate and share each switch off; rate only in modes that have one", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 2640, amountPerSecond = 330 } }
    stub.meter.total = 14667
    local function text() M.Draw(); return stub.Text(mainRows()[1].amount) end
    DUI:Set("InfoPanel", "meter.showRate", false); stub.RunTimers()
    T.eq(text(), "2.6K (18%)")
    DUI:Set("InfoPanel", "meter.showRate", true)
    DUI:Set("InfoPanel", "meter.showShare", false); stub.RunTimers()
    T.eq(text(), "330 (2.6K)")
    DUI:Set("InfoPanel", "meter.showShare", true)
    DUI:Set("InfoPanel", "meter.showTotal", false); stub.RunTimers()
    T.eq(text(), "330 (18%)")
    DUI:Set("InfoPanel", "meter.showRate", false)
    DUI:Set("InfoPanel", "meter.showShare", false); stub.RunTimers()
    T.eq(text(), "2.6K", "nothing picked: the total still shows")
    DUI:Set("InfoPanel", "meter.showTotal", true)
    DUI:Set("InfoPanel", "meter.showRate", true)
    DUI:Set("InfoPanel", "meter.showShare", true)
    DUI:Set("InfoPanel", "meter.mode", "interrupts"); stub.RunTimers()
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 7 } }
    stub.meter.total = 28
    T.eq(text(), "7 (25%)", "a count has no rate")
end)

T.test("meters: the icon is the class's when there's no spec, none for a mob, and can be switched off", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 10 },
                           { name = "Chasmfiend", classFilename = "", totalAmount = 5 } }
    M.Draw()
    T.eq(mainRows()[1].icon:GetTexture(), DUI.MEDIA .. "class\\warrior.tga")
    T.falsy(mainRows()[2].icon:IsShown(), "a mob: no icon, its name still lines up")
    DUI:Set("InfoPanel", "meter.icons", "class")
    stub.meter.sources[1].specIconID = 132355
    stub.RunTimers(); M.Draw()
    T.eq(mainRows()[1].icon:GetTexture(), DUI.MEDIA .. "class\\warrior.tga", "class icons asked for")
    DUI:Set("InfoPanel", "meter.icons", "none"); stub.RunTimers(); M.Draw()
    T.falsy(mainRows()[1].icon:IsShown())
    DUI:Set("InfoPanel", "meter.rank", false); stub.RunTimers(); M.Draw()
    T.falsy(mainRows()[1].rank:IsShown())
end)

T.test("meters: a boss fight draws secret rows with no share and no errors", function()
    login()
    local M = stub.infopanel.Meter
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", specIconID = 132355,
                             totalAmount = 2640, amountPerSecond = 330 } }
    stub.SetRestriction("Encounter", true)
    stub.EnterCombat()
    T.noerror(function() M.Draw() end)
    local r = mainRows()[1]
    T.truthy(r:IsShown())
    T.eq(stub.Text(r.amount), "330 (2.6K)", "no share: the numbers are secret")
    T.eq(stub.Text(r.name), "Kaladin", "the secret name drawn whole")
    T.eq(stub.Plain(r.icon:GetTexture()), 132355, "the spec's icon, secret, straight to the texture")
    stub.LeaveCombat()
    stub.SetRestriction("Encounter", false)
end)

T.test("meters: you are pinned in the last row with your rank when scrolled out of view", function()
    login()
    local M = stub.infopanel.Meter
    stub.meter.sources = raid(30, 24)
    M.Draw()
    local fit = fitting(M)
    T.truthy(#fit < 24, "you'd be out of view")
    local last = fit[#fit]
    T.eq(stub.Text(last.rank), "24")
    T.eq(stub.Text(last.name), "P24")
    T.truthy(last.mine, "outlined as yours")
    T.falsy(fit[1].mine)
    -- Scrolled down to you: you're in your own place and nothing is pinned.
    for _ = 1, 30 do stub.infopanel.Panel.meterArea:GetScript("OnMouseWheel")(stub.infopanel.Panel.meterArea, -1) end
    local seen = 0
    for _, r in ipairs(fitting(M)) do if stub.Text(r.name) == "P24" then seen = seen + 1 end end
    T.eq(seen, 1, "once")
end)

T.test("meters: \"always show me\" off leaves you scrolled away", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    DUI:Set("InfoPanel", "meter.showMe", false); stub.RunTimers()
    stub.meter.sources = raid(30, 24)
    M.Draw()
    local fit = fitting(M)
    T.eq(stub.Text(fit[#fit].rank), tostring(#fit))
end)

T.test("meters: the three new modes ask the game for Dps, Hps and Absorbs", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    T.eq(#M.MODES, 11, "every type the game keeps")
    for key, kind in pairs({ dps = "Dps", hps = "Hps", absorbs = "Absorbs" }) do
        DUI:Set("InfoPanel", "meter.mode", key); stub.RunTimers()
        M.Draw()
        T.eq(stub.meter.asked[2], Enum.DamageMeterType[kind], key)
    end
end)

T.test("meters: with no fights it says so; a mode with nobody in it says that", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    M.Draw()
    T.truthy(M.empty:IsShown())
    T.eq(stub.Text(M.empty), "No fights yet.")
    DUI.Style.InkText(M.empty, "LABEL")
    stub.meter.fights = { { sessionID = 1, name = "Sadeas", durationSeconds = 30 } }
    DUI:Set("InfoPanel", "meter.mode", "dispels"); stub.RunTimers()
    M.Draw()
    T.eq(stub.Text(M.empty), "No dispels yet.")
    stub.meter.sources = raid(3)
    M.Draw()
    T.falsy(M.empty:IsShown(), "rows: the words go")
end)

T.test("meters: rows that change places glide there out of combat; in a fight they draw in place", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    local a = { name = "A", classFilename = "MAGE", totalAmount = 200 }
    local b = { name = "B", classFilename = "ROGUE", totalAmount = 100 }
    stub.meter.sources = { a, b }
    M.Draw()
    local r1 = mainRows()[1]
    local _, _, _, _, y0 = r1:GetPoint(1)
    stub.meter.sources = { { name = "B", classFilename = "ROGUE", totalAmount = 300 }, { name = "A", classFilename = "MAGE", totalAmount = 200 } }
    M.Draw()
    local _, _, _, _, y1 = r1:GetPoint(1)
    T.truthy(y1 < y0, "B's row starts where B was (lower), gliding up")
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    local _, _, _, _, y2 = r1:GetPoint(1)
    T.eq(y2, y0, "and lands in the first place")
    stub.EnterCombat()
    stub.meter.sources = { { name = "A", classFilename = "MAGE", totalAmount = 400 }, { name = "B", classFilename = "ROGUE", totalAmount = 300 } }
    M.Draw()
    local _, _, _, _, y3 = r1:GetPoint(1)
    T.eq(y3, y0, "in a fight: in place at once")
    stub.LeaveCombat()
end)

-- ---------------------------------------------------------------------
-- Windows: edge cases
-- ---------------------------------------------------------------------

T.test("windows: a window coming out at the pull shows the fight's rows at once, not the last fight's", function()
    local DUI = login()
    W().Add("damage")
    DUI:Set("InfoPanel", "meters.windows.w1.inCombat", true)
    stub.RunTimers(); tweens()
    local h = host("w1")
    T.falsy(h.frame:IsShown())
    stub.meter.sources = { { name = "Old", classFilename = "MAGE", totalAmount = 5 } }
    h.view.Draw()
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 900 } }
    stub.EnterCombat()
    T.truthy(h.frame:IsShown())
    T.eq(stub.Text(rows("w1")[1].name), "Kaladin", "drawn as it shows, before any tick")
    stub.LeaveCombat()
end)

T.test("windows: an old second meter on deaths, taken or interrupts keeps that name", function()
    login()
    for _, mode in ipairs({ "deaths", "taken", "interrupts" }) do
        local p = { modules = { InfoPanel = { meter2 = { enabled = true, mode = mode } } } }
        W().Upgrade(p)
        local w = p.modules.InfoPanel.meters.windows.w2
        T.eq(w.preset, mode)
        T.eq(W().Name({ id = "w2", kind = "meter", cfg = w }), DaylightUI.L[W().PRESET[mode].label])
    end
end)

T.test("windows: an old second meter never replaces a window already called w2", function()
    login()
    local mine = { kind = "meter", mode = "dispels" }
    local p = { modules = { InfoPanel = { meter2 = { enabled = true, mode = "taken" },
        meters = { order = { "w1", "w2" }, next = 3, windows = { w1 = { kind = "meter" }, w2 = mine } } } },
        positions = { ["infopanel.meter2"] = { 1, 2 }, ["infopanel.meter.w2"] = { 5, 6 } } }
    W().Upgrade(p)
    local m = p.modules.InfoPanel.meters
    T.eq(m.windows.w2, mine, "the player's own w2 kept")
    T.eq(m.windows.w3.mode, "taken", "the old second meter takes the next id")
    T.eq(m.order[1], "w3")
    T.eq(m.next, 4)
    T.deq(p.positions["infopanel.meter.w2"], { 5, 6 })
    T.deq(p.positions["infopanel.meter.w3"], { 1, 2 })
end)

T.test("windows: a damaged window's settings are mended at login; one bad window never stops the others", function()
    local DUI = login()
    W().Add("damage")
    W().Add("healing")
    local db = DUI:GetModule("InfoPanel").db
    db.meters.windows.w1.width = "wide"
    db.meters.windows.w1.barCustom = 7
    W().Fill(db)
    T.eq(db.meters.windows.w1.width, 207, "a value of the wrong kind goes back to the template's")
    T.eq(type(db.meters.windows.w1.barCustom), "table")
    local layout = F().Layout
    F().Layout = function(d, h, e)
        if e.id == "w1" then error("boom") end
        return layout(d, h, e)
    end
    T.noerror(function() F().Sync(DUI:GetModule("InfoPanel")) end)
    F().Layout = layout
    T.truthy(host("w2").frame:IsShown(), "the next window is still laid out")
end)

T.test("windows: a removed window leaves no spot or size behind; a rename names its handle", function()
    local DUI = login()
    W().Add("damage")
    stub.RunTimers()
    DUI.DB.Positions()["infopanel.meter.w1"] = { 10, 10 }
    DUI.DB.General().frameScales = DUI.DB.General().frameScales or {}
    DUI.DB.General().frameScales["infopanel.meter.w1"] = 1.3
    W().Rename("w1", "Raid DPS")
    stub.RunTimers()
    T.eq(DUI.Movers.Get("infopanel.meter.w1").label, "Raid DPS")
    W().Remove("w1")
    T.isnil(DUI.DB.Positions()["infopanel.meter.w1"])
    T.isnil(DUI.DB.General().frameScales["infopanel.meter.w1"])
end)

-- ---------------------------------------------------------------------
-- The header: mode, fight, clock, total, and the buttons
-- ---------------------------------------------------------------------

local function header() return stub.infopanel.Meter.header end
local function hover(on)
    local area = stub.infopanel.Panel.meterArea
    area.IsMouseOver = function() return on end
    if on then area:GetScript("OnEnter")(area) end
    if area:GetScript("OnUpdate") then stub.RunOnUpdate(area, 0.01) end
    tweens()
end

T.test("meter header: shows the mode, the fight and how long it ran", function()
    local DUI = login()
    local M, h = stub.infopanel.Meter, header()
    stub.meter.fights = { { sessionID = 1, name = "Sadeas", durationSeconds = 94 } }
    stub.meter.durations = { [Enum.DamageMeterSessionType.Current] = 94, [Enum.DamageMeterSessionType.Overall] = 400 }
    M.Draw()
    T.truthy(h:IsShown())
    T.eq(stub.Text(h.mode), "DAMAGE")
    T.eq(stub.Text(h.fight), "Sadeas")
    T.eq(stub.Text(h.timer), "1:34")
    T.eq(h.icon:GetTexture(), M.ICON("damage"))
    T.rgb({ h.icon:GetVertexColor() }, { DUI.Style.Accent() }, "the mode's icon in the accent")
    DUI:Set("InfoPanel", "meter.session", "overall"); stub.RunTimers()
    M.Draw()
    T.eq(stub.Text(h.fight), DUI.L["Overall"])
    T.eq(stub.Text(h.timer), "6:40")
    DUI:Set("InfoPanel", "meter.mode", "healing"); stub.RunTimers()
    M.Draw()
    T.eq(stub.Text(h.mode), "HEALING")
    T.eq(h.icon:GetTexture(), M.ICON("healing"))
end)

T.test("meter header: always sits above the rows; hover gives the rows its room and comes over them with the mouse", function()
    local DUI = login()
    local M, h = stub.infopanel.Meter, header()
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 10 } }
    M.Draw()
    local _, _, _, _, y = M.rows[1]:GetPoint(1)
    T.eq(y, -h:GetHeight(), "the first row under the header")
    DUI:Set("InfoPanel", "meter.header", "hover"); stub.RunTimers()
    M.Draw()
    _, _, _, _, y = M.rows[1]:GetPoint(1)
    T.eq(y, 0, "the rows take the top")
    T.falsy(h:IsShown(), "away until the mouse comes")
    hover(true)
    T.truthy(h:IsShown())
    T.eq(h:GetAlpha(), 1)
    T.truthy(h.back:IsShown(), "on a band over the top row")
    hover(false)
    T.falsy(h:IsShown())
end)

T.test("meter header: the buttons fade in with the mouse, the clock gives way", function()
    login()
    local h = header()
    T.falsy(h.tools:IsShown())
    T.eq(h.info:GetAlpha(), 1)
    hover(true)
    T.truthy(h.tools:IsShown())
    T.eq(h.tools:GetAlpha(), 1)
    T.eq(h.info:GetAlpha(), 0)
    hover(false)
    T.falsy(h.tools:IsShown())
    T.eq(h.info:GetAlpha(), 1)
end)

T.test("meter header: the buttons open the fights, the modes, the report, reset, a new window and the options", function()
    local DUI = login()
    local M, h = stub.infopanel.Meter, header()
    hover(true)
    local b = h.buttons
    T.eq(b.fight.icon:GetTexture(), DUI.MEDIA .. "ui-meter-fight.png", "our own icon")
    stub.meter.fights = { { sessionID = 1, name = "Hogger", durationSeconds = 42 },
                          { sessionID = 2, name = "Van Cleef", durationSeconds = 125 } }
    b.fight:GetScript("OnClick")(b.fight)
    T.eq(DUI.Widgets.menuOwner, b.fight)
    local rows = PW.menuRows()
    T.eq(#rows, 3, "overall, current, and the one before")
    rows[3]:GetScript("OnClick")(rows[3])
    T.eq(M.fight, 1)
    b.mode:GetScript("OnClick")(b.mode)
    rows = PW.menuRows()
    T.eq(stub.Text(rows[1].text):upper(), DUI.L["Damage"]:upper(), "every mode under its group's heading")
    T.eq(stub.Text(rows[2].text), DUI.L["Damage done"])
    T.eq(stub.Text(rows[5].text):upper(), DUI.L["Healing"]:upper())
    rows[1]:GetScript("OnClick")(rows[1])
    T.eq(DUI:Get("InfoPanel", "meter.mode"), "damage", "a heading picks nothing")
    b.mode:GetScript("OnClick")(b.mode)
    T.isnil(DUI.Widgets.menuOwner, "a second click closes it")
    b.report:GetScript("OnClick")(b.report)
    T.truthy(stub.infopanel.Report.frame:IsShown())
    b.reset:GetScript("OnClick")(b.reset)
    T.eq(stub.popup, "DAYLIGHTUI_METER_RESET", "asks first")
    b.new:GetScript("OnClick")(b.new)
    rows = PW.menuRows()
    T.eq(#rows, #stub.infopanel.Windows.PRESETS)
    rows[2]:GetScript("OnClick")(rows[2])
    T.eq(stub.infopanel.Windows.Own()[1].cfg.mode, "healing", "a new healing window")
    b.options:GetScript("OnClick")(b.options)
    T.truthy(DUI.OptionsPanel.IsShown())
    T.eq(DUI.OptionsPanel.Current(), "InfoPanel.meter")
end)

T.test("meter header: the group's total shows when switched on, secret in a fight too", function()
    local DUI = login()
    local M, h = stub.infopanel.Meter, header()
    stub.meter.sources = { { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 2640 } }
    M.Draw()
    T.falsy(h.total:IsShown(), "off by default")
    DUI:Set("InfoPanel", "meter.headerTotal", true); stub.RunTimers()
    M.Draw()
    T.truthy(h.total:IsShown())
    T.eq(stub.Text(h.total), "2.6K")
    T.rgb({ h.total:GetTextColor() }, { DUI.Style.Accent() }, "a number that matters pops")
    stub.EnterCombat()
    T.noerror(function() M.Draw() end)
    T.eq(stub.Text(h.total), "2.6K")
    stub.LeaveCombat()
end)

-- ---------------------------------------------------------------------
-- Fights: every fight, one pick for every window, back to the current
-- ---------------------------------------------------------------------

local function fights(n)
    local list = {}
    for i = 1, n do list[i] = { sessionID = i, name = "Fight " .. i, durationSeconds = 10 * i } end
    stub.meter.fights = list
end

T.test("fights: the menu lists every fight the game keeps, newest first", function()
    login()
    local M = stub.infopanel.Meter
    fights(12)
    local choices = M.FightChoices()
    T.eq(#choices, 13, "overall, current, and the eleven before it")
    T.eq(choices[2].text, "Current: Fight 12")
    T.eq(choices[3].fight, 11)
    T.eq(choices[13].fight, 1, "the oldest last")
end)

T.test("fights: an earlier fight picked in one window shows in every window on Current, not in one on Overall", function()
    local DUI = login()
    fights(3)
    local a = W().Add("healing")
    local b = W().Add("taken")
    DUI:Set("InfoPanel", "meters.windows." .. b .. ".session", "overall")
    stub.RunTimers()
    local M, A, B = stub.infopanel.Meter, host(a).view, host(b).view
    local pick
    for _, c in ipairs(M.FightChoices()) do if c.fight == 2 then pick = c end end
    M.PickFight(pick)
    T.eq(M.fight, 2)
    T.eq(A.fight, 2, "the other window on Current shows it too")
    T.isnil(B.fight, "the one on Overall stays there")
    A.PickFight(A.FightChoices()[2])   -- Current again, in another window
    T.isnil(M.fight, "and back for all of them")
    T.isnil(A.fight)
end)

T.test("fights: a pull takes every window back to its own Current or Overall", function()
    local DUI = login()
    fights(3)
    local a = W().Add("healing")
    stub.RunTimers()
    local M, A = stub.infopanel.Meter, host(a).view
    M.fight, A.fight = 1, 2
    stub.EnterCombat()
    T.isnil(M.fight); T.isnil(A.fight)
    stub.LeaveCombat()
    DUI:Set("InfoPanel", "meters.backToCurrent", false)
    M.fight = 1
    stub.EnterCombat()
    T.eq(M.fight, 1, "switched off: the pick stays")
    stub.LeaveCombat()
end)

T.test("fights: with \"same fight\" off, each window keeps its own pick", function()
    local DUI = login()
    fights(3)
    local a = W().Add("healing")
    stub.RunTimers()
    DUI:Set("InfoPanel", "meters.sameFight", false)
    local M, A = stub.infopanel.Meter, host(a).view
    local pick
    for _, c in ipairs(M.FightChoices()) do if c.fight == 2 then pick = c end end
    M.PickFight(pick)
    T.eq(M.fight, 2)
    T.isnil(A.fight)
end)

-- ---------------------------------------------------------------------
-- The threat meter's look (ThreatView.lua)
-- ---------------------------------------------------------------------

local function threatParty(boss, me)
    stub.SetGroup(true)
    stub.units.player = { name = "Navani", isPlayer = true, class = "PRIEST" }
    stub.units.party1 = { name = "Kaladin", isPlayer = true, class = "WARRIOR", role = "TANK" }
    stub.units.party2 = { name = "Shallan", isPlayer = true, class = "MAGE" }
    stub.units.target = { name = "Sadeas", isPlayer = false, reaction = 2, boss = boss, threatList = {
        party1 = { status = 3, scaled = 100, raw = 100, value = 10000 },
        player = me or { status = 1, scaled = 84, raw = 92, value = 9200 },
        party2 = { status = 0, scaled = 50, raw = 65, value = 6500 },
    } }
end
local function threatOut()
    local TM = stub.infopanel.ThreatMeter
    stub.EnterCombat()
    stub.RunOnUpdate(TM.slider.driver, 1)
    TM.Draw()
    return TM, TM.view
end
local function shownRows(v)
    local out = {}
    for _, r in ipairs(v.rows) do if r:IsShown() then out[#out + 1] = r end end
    return out
end

T.test("threat look: the header shows the mob and your percent, colored by how close you are", function()
    local DUI = login()
    threatParty()
    local TM, v = threatOut()
    T.eq(stub.Text(v.mob), "Sadeas")
    T.rgb({ v.mob:GetTextColor() }, DUI.Style.INK.TEXT, "the mob's name: soft white, not a loud pop")
    T.eq(stub.Text(v.yours), "84%")
    T.rgb({ v.yours:GetTextColor() }, DUI.Style.INK.WARN, "close to pulling: amber")
    local _, size = v.yours:GetFont()
    T.eq(size, DUI.Style.SIZE.head, "the number a glance needs, big")
    T.eq(v.icon:GetTexture(), stub.infopanel.Meter.ICON("threat"))
    stub.units.target.threatList.player = { status = 3, scaled = 100, raw = 120, value = 12000 }
    TM.Draw()
    T.rgb({ v.yours:GetTextColor() }, DUI.Style.INK.BAD, "on you: red")
    stub.units.target.threatList.player = { status = 0, scaled = 20, raw = 30, value = 2000 }
    TM.Draw()
    T.rgb({ v.yours:GetTextColor() }, DUI.Style.INK.GOOD, "safe: green")
    stub.LeaveCombat(); stub.SetGroup(false)
end)

T.test("threat look: slim rows, a tank mark, your row outlined in the accent and its percent popping", function()
    local DUI = login()
    threatParty()
    local _, v = threatOut()
    local rows = shownRows(v)
    T.eq(#rows, 3)
    T.eq(rows[1]:GetHeight(), 16, "slimmer rows")
    T.truthy(rows[1].icon:IsShown(), "the tank's mark")
    T.eq(rows[1].icon:GetTexture(), stub.infopanel.Meter.ICON("tank"))
    T.falsy(rows[3].icon:IsShown(), "no mark for the others")
    T.truthy(rows[2].mine, "your row")
    T.rgb({ rows[2].amount:GetTextColor() }, { DUI.Style.Accent() }, "your percent pops")
    T.rgb({ rows[3].amount:GetTextColor() }, DUI.Style.INK.VALUE)
    T.eq(DUI.Style.GetShell(rows[1].box).opts.borderPx, 1, "a thin outline, not the old thick one")
    stub.LeaveCombat(); stub.SetGroup(false)
end)

T.test("threat look: the pull line is one crisp line with a notch, and glides when it moves", function()
    local DUI = login()
    threatParty()
    local TM, v = threatOut()
    T.truthy(v.line:IsShown())
    T.truthy(v.notch:IsShown(), "a notch on top")
    T.truthy(v.glow:IsShown(), "a soft glow behind it")
    T.rgb(v.line.__color, DUI:Get("InfoPanel", "threat.pullColor"))
    local x0 = select(4, v.line:GetPoint(1))
    -- The tank's threat rises, so the pull point moves right.
    stub.units.target.threatList.party1 = { status = 3, scaled = 100, raw = 100, value = 12000 }
    TM.Draw()
    local x1 = select(4, v.line:GetPoint(1))
    T.near(x1, x0, 1e-6, "it starts where it was")
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    local x2 = select(4, v.line:GetPoint(1))
    T.truthy(x2 ~= x0, "and glides to the new spot")
    stub.LeaveCombat(); stub.SetGroup(false)
end)

T.test("threat look: on a boss your percent still takes your standing's color (the status stays plain), no line", function()
    local DUI = login()
    threatParty(true)
    stub.SetRestriction("Encounter", true)
    local _, v = threatOut()
    T.rgb({ v.yours:GetTextColor() }, DUI.Style.INK.WARN, "status 1: close")
    T.falsy(v.line:IsShown())
    T.falsy(v.notch:IsShown())
    stub.LeaveCombat(); stub.SetGroup(false)
    stub.SetRestriction("Encounter", false)
end)

T.test("threat look: bars can take their threat level's color", function()
    local DUI = login()
    DUI:Set("InfoPanel", "threat.barColor", "threat")
    DUI:Set("InfoPanel", "threat.gradient", false)
    stub.RunTimers()
    threatParty()
    local _, v = threatOut()
    local rows = shownRows(v)
    local function fill(r) return r.bar.__barColor end
    local function near(c, ink) return math.abs(c[1] - ink[1]) < 0.15 and math.abs(c[2] - ink[2]) < 0.15 end
    T.truthy(near(fill(rows[1]), DUI.Style.INK.BAD), "the tank holding it: red")
    T.truthy(near(fill(rows[2]), DUI.Style.INK.WARN), "you, close: amber")
    T.truthy(near(fill(rows[3]), DUI.Style.INK.GOOD), "far below: green")
    stub.LeaveCombat(); stub.SetGroup(false)
end)

-- ---------------------------------------------------------------------
-- Threat windows of the player's own
-- ---------------------------------------------------------------------

T.test("threat windows: a new threat window shows its rows in a fight in a group, never solo", function()
    local DUI = login()
    local id = W().Add("threat")
    stub.RunTimers(); tweens()
    local h = host(id)
    T.truthy(h, "a window made for it")
    T.eq(h.kind, "threat")
    T.falsy(h.frame:IsShown(), "out of a fight: away")
    stub.EnterCombat()
    tweens()
    T.falsy(h.frame:IsShown(), "solo in a fight: still away (it's always on you)")
    stub.LeaveCombat()
    threatParty()
    stub.EnterCombat()
    tweens()
    T.truthy(h.frame:IsShown(), "in a group in a fight")
    stub.RunTickers()
    local shown = shownRows(h.view)
    T.eq(#shown, 3)
    T.eq(stub.Text(shown[1].name), "Kaladin")
    T.eq(stub.Text(h.view.mob), "Sadeas")
    stub.LeaveCombat()
    tweens()
    T.falsy(h.frame:IsShown(), "and away after")
    stub.SetGroup(false)
end)

T.test("threat windows: it can follow your focus, or your target's target when you target a friend", function()
    local DUI = login()
    local id = W().Add("threat")
    threatParty()
    local mob = stub.units.target
    stub.units.focus = mob
    stub.units.target = { name = "Kaladin", isPlayer = true, class = "WARRIOR", reaction = 5 }
    stub.units.targettarget = mob
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".unit", "focus")
    stub.RunTimers()
    stub.EnterCombat(); tweens()
    local h = host(id)
    h.Draw()
    T.eq(stub.Text(h.view.mob), "Sadeas", "the focus's list")
    T.eq(#shownRows(h.view), 3)
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".unit", "smart")
    stub.RunTimers()
    h.Draw()
    T.eq(stub.Text(h.view.mob), "Sadeas", "your friendly target's target")
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".unit", "target")
    stub.RunTimers()
    h.Draw()
    T.eq(#shownRows(h.view), 0, "your target is a friend: nothing to show")
    stub.LeaveCombat(); stub.SetGroup(false)
end)

T.test("threat windows: they fade with the threat meter's fade, not the panel's", function()
    local DUI = login()
    local id = W().Add("threat")
    DUI:Set("InfoPanel", "threat.fade.mode", "always")
    DUI:Set("InfoPanel", "threat.fade.alpha", 0.3)
    stub.RunTimers()
    threatParty()
    stub.EnterCombat(); tweens()
    local Fd = DaylightUI.Fade
    stub.Advance(10)
    Fd.Step()
    for _ = 1, 120 do stub.RunOnUpdate(Fd.driver, 1 / 60) end
    T.near(host(id).frame:GetAlpha(), 0.3, 1e-6)
    stub.LeaveCombat(); stub.SetGroup(false)
end)

T.test("threat windows: test mode and unlock mode show their sample", function()
    local DUI = login()
    local id = W().Add("threat")
    stub.RunTimers(); tweens()
    local h = host(id)
    T.falsy(h.frame:IsShown())
    DUI.SetTestMode(true)
    tweens()
    T.truthy(h.frame:IsShown())
    h.Draw()
    T.eq(stub.Text(h.view.mob), stub.infopanel.ThreatMeter.SAMPLE_TARGET)
    DUI.SetTestMode(false)
    DUI.Movers.Unlock()
    stub.RunTimers(); tweens()
    T.truthy(h.frame:IsShown(), "unlocked: out to be placed")
    DUI.Movers.Lock()
end)

T.test("threat windows: unlocked, the corner grip sets the width and as many rows as fit", function()
    local DUI = login()
    local id = W().Add("threat")
    DUI.Movers.Unlock()
    stub.RunTimers(); tweens()
    local h = host(id)
    T.truthy(h.grip:IsShown())
    h.grip:GetScript("OnMouseDown")(h.grip)
    h.frame:SetSize(230, 400)
    h.grip:GetScript("OnMouseUp")(h.grip)
    T.truthy(DUI:Get("InfoPanel", "meters.windows." .. id .. ".width") > 200)
    T.eq(DUI:Get("InfoPanel", "meters.windows." .. id .. ".rows"), 10, "as many as fit, up to ten")
    DUI.Movers.Lock()
end)

-- ---------------------------------------------------------------------
-- Hovering a player: their spells, targets, and what a click does
-- ---------------------------------------------------------------------

local function hoverRow(i)
    local M, area = stub.infopanel.Meter, stub.infopanel.Panel.meterArea
    local bar = M.rows[i]
    function bar:IsMouseOver() return true end
    area.IsMouseOver = function() return true end
    area:GetScript("OnEnter")(area)
    area:GetScript("OnUpdate")(area)
    return bar
end
local function tipRows()
    local B, out = stub.infopanel.Breakdown, {}
    for _, r in ipairs(B.rows or {}) do if r:IsShown() then out[#out + 1] = r end end
    return out
end

T.test("meter tip: hovering a row shows the player's total, top spells with icons and shares, and a hint", function()
    login()
    local M, B = stub.infopanel.Meter, stub.infopanel.Breakdown
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 1000, amountPerSecond = 100,
                             sourceGUID = "Player-2" } }
    stub.meter.spells = { { spellID = 1, totalAmount = 750 }, { spellID = 2, totalAmount = 250 } }
    M.Draw()
    hoverRow(1)
    T.truthy(B.Frame():IsShown())
    T.eq(stub.Text(B.total), "1K")
    local rows = tipRows()
    T.eq(stub.Text(rows[1].name), "Fireball")
    T.eq(stub.Text(rows[1].amount), "750  75%")
    T.eq(rows[1].icon:GetTexture(), 1001)
    T.truthy(B.hint:IsShown())
    T.truthy(stub.Text(B.hint):find(DaylightUI.L["Click"], 1, true), "says what a click does")
end)

T.test("meter tip: damage done out of combat adds the top three targets", function()
    login()
    local M, B = stub.infopanel.Meter, stub.infopanel.Breakdown
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 1000, sourceGUID = "Player-2" } }
    stub.meter.spells = {
        { spellID = 1, totalAmount = 500, combatSpellDetails = { unitName = "Sadeas", amount = 500 } },
        { spellID = 2, totalAmount = 300, combatSpellDetails = { unitName = "Axehound", amount = 300 } },
        { spellID = 1, totalAmount = 120, combatSpellDetails = { unitName = "Axehound", amount = 120 } },
        { spellID = 2, totalAmount = 50, combatSpellDetails = { unitName = "Whitespine", amount = 50 } },
        { spellID = 2, totalAmount = 30, combatSpellDetails = { unitName = "Thunderclast", amount = 30 } },
    }
    local targets = B.Targets(stub.meter.sources[1], M)
    T.eq(#targets, 4)
    T.eq(targets[1].name, "Sadeas"); T.eq(targets[1].amount, 500)
    T.eq(targets[2].name, "Axehound"); T.eq(targets[2].amount, 420, "merged by name")
    M.Draw()
    hoverRow(1)
    T.truthy(B.targetsHead:IsShown(), "a Targets heading")
    local shown = 0
    for _, r in ipairs(B.targetRows) do if r:IsShown() then shown = shown + 1 end end
    T.eq(shown, 3, "the top three")
    stub.EnterCombat()
    local none, why = B.Targets(stub.meter.sources[1], M)
    T.isnil(none, "in a fight the names can't be merged")
    stub.LeaveCombat()
end)

T.test("meter tip: in a fight a group member's spells come from the snapped map; two of the same class and spec wait", function()
    login()
    local M, B = stub.infopanel.Meter, stub.infopanel.Breakdown
    stub.SetGroup(true)
    stub.meter.sources = {
        { name = "Sigzil", classFilename = "MAGE", specIconID = 135932, totalAmount = 1000, sourceGUID = "Player-2" },
        { name = "Kaladin", classFilename = "WARRIOR", specIconID = 132355, totalAmount = 900, sourceGUID = "Player-3" },
        { name = "Teft", classFilename = "WARRIOR", specIconID = 132355, totalAmount = 800, sourceGUID = "Player-4" },
    }
    M.Draw()   -- out of combat: the map is snapped
    stub.EnterCombat()
    local live = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    T.truthy(issecretvalue(live.combatSources[1].sourceGUID), "the fight hides their GUIDs")
    local guid = M.GuidOf(live.combatSources[1])
    T.eq(guid, "Player-2", "the only mage: from the map")
    T.isnil(M.GuidOf(live.combatSources[2]), "two warriors of one spec: can't tell them apart")
    local spells, why = B.Spells(live.combatSources[2], M)
    T.isnil(spells); T.eq(why, B.WAIT)
    B.Spells(live.combatSources[1], M)
    T.eq(stub.meter.askedSource[3], "Player-2")
    stub.LeaveCombat()
    stub.SetGroup(false)
end)

T.test("meter tip: Shift-click reports that player's spells", function()
    local DUI = login()
    local M, R = stub.infopanel.Meter, stub.infopanel.Report
    stub.meter.sources = { { name = "Sigzil", classFilename = "MAGE", totalAmount = 1000, sourceGUID = "Player-2" } }
    stub.meter.spells = { { spellID = 1, totalAmount = 750 }, { spellID = 2, totalAmount = 250 } }
    M.Draw()
    local bar = hoverRow(1)
    _G.IsShiftKeyDown = function() return true end
    bar:GetScript("OnMouseUp")(bar, "LeftButton")
    _G.IsShiftKeyDown = nil
    T.truthy(R.frame:IsShown())
    T.eq(R.who, M.rows[1].src)
    local lines = R.Lines(M, 5, R.who)
    T.truthy(lines[1]:find("Sigzil", 1, true), "the header names the player")
    T.truthy(lines[2]:find("Fireball", 1, true), "then their spells")
    T.truthy(lines[2]:find("75%", 1, true))
end)

-- ---------------------------------------------------------------------
-- Rows, header and threat view: edge cases
-- ---------------------------------------------------------------------

T.test("meters: DPS and HPS fill their bars by the rate they're ranked by", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    DUI:Set("InfoPanel", "meter.mode", "dps"); stub.RunTimers()
    stub.meter.sources = { { name = "A", classFilename = "MAGE", totalAmount = 1000, amountPerSecond = 200 },
                           { name = "B", classFilename = "ROGUE", totalAmount = 3000, amountPerSecond = 100 } }
    M.Draw()
    local _, max = M.rows[2].bar:GetMinMaxValues()
    T.eq(max, 200, "the top rate is the bars' top")
    T.eq(M.rows[2].bar:GetValue(), 100, "half the top rate: half a bar, though its total is bigger")
end)

T.test("meters: your row's outline follows an accent change", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    stub.meter.sources = { { name = "Me", classFilename = "MAGE", totalAmount = 10, isLocalPlayer = true } }
    M.Draw()
    T.truthy(M.rows[1].mine)
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.9, 0.3 })
    stub.RunTimers()
    M.Draw()
    local c = DUI.Style.GetShell(M.rows[1].box).opts.borderColor
    T.near(c[1], 0.2, 0.02, "the new accent")
    T.near(c[2], 0.9, 0.02)
end)

T.test("meters: the fight list is read when it changes, not on every redraw in a fight", function()
    login()
    local M = stub.infopanel.Meter
    stub.meter.fights = { { sessionID = 1, name = "Sadeas", durationSeconds = 30 } }
    local reads, get = 0, C_DamageMeter.GetAvailableCombatSessions
    C_DamageMeter.GetAvailableCombatSessions = function() reads = reads + 1; return get() end
    stub.FireEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 1)
    stub.EnterCombat()
    for _ = 1, 8 do M.Draw() end
    T.truthy(reads <= 1, "once, not every redraw: " .. reads)
    stub.meter.fights[2] = { sessionID = 2, name = "Chasmfiend", durationSeconds = 5 }
    stub.FireEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 2)
    M.Draw()
    T.eq(stub.Text(M.header.fight), "Chasmfiend", "a new fight is read again")
    C_DamageMeter.GetAvailableCombatSessions = get
    stub.LeaveCombat()
end)

T.test("threat look: a pull line hidden mid-glide stays put, and the next one snaps into place", function()
    local DUI = login()
    threatParty()
    local TM, v = threatOut()
    stub.units.target.threatList.party1 = { status = 3, scaled = 100, raw = 100, value = 12000 }
    TM.Draw()   -- gliding now
    DUI:Set("InfoPanel", "threat.pullLine", false); stub.RunTimers()
    TM.Draw()
    T.falsy(v.line:IsShown())
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.isnil(v.lineX, "the glide stopped with it")
    DUI:Set("InfoPanel", "threat.pullLine", true); stub.RunTimers()
    TM.Draw()
    local x = select(4, v.line:GetPoint(1))
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.near(select(4, v.line:GetPoint(1)), x, 1e-6, "shown again: straight to its spot")
    stub.LeaveCombat(); stub.SetGroup(false)
end)

-- ---------------------------------------------------------------------
-- The breakdown window (a click on a player)
-- ---------------------------------------------------------------------

local function BW() return stub.infopanel.BreakdownWindow end
local function bwRows(page)
    local t, out = BW().tables[page], {}
    for i = 1, #t.rows do
        local b = t.shown[i]
        if b then out[#out + 1] = b end
    end
    table.sort(out, function(a, b) return a.index < b.index end)
    return out
end
local function raidSpells()
    stub.meter.sources = {
        { name = "Sigzil", classFilename = "MAGE", totalAmount = 1000, amountPerSecond = 100, sourceGUID = "Player-2" },
        { name = "Kaladin", classFilename = "WARRIOR", totalAmount = 600, amountPerSecond = 60, sourceGUID = "Player-3" },
    }
    stub.meter.spells = {
        { spellID = 2, totalAmount = 250, amountPerSecond = 25, overkillAmount = 40,
          combatSpellDetails = { unitName = "Axehound", amount = 250 } },
        { spellID = 1, totalAmount = 750, amountPerSecond = 75, overkillAmount = 0,
          combatSpellDetails = { unitName = "Sadeas", amount = 750 } },
    }
end
local function clickRow(i)
    local M = stub.infopanel.Meter
    local row = M.rows[i]
    row:GetScript("OnMouseUp")(row, "LeftButton")
    tweens()
end

T.test("breakdown window: a click on a row opens it on that player's spells, biggest first, with a column sort", function()
    local DUI = login()
    raidSpells()
    stub.infopanel.Meter.Draw()
    clickRow(1)
    local f = BW().frame
    T.truthy(f:IsShown())
    T.eq(stub.Text(f.title), "Sigzil")
    T.eq(f.tab, "spells")
    T.eq(stub.meter.askedSource[3], "Player-2")
    local rows = bwRows("spells")
    T.eq(#rows, 2)
    T.eq(stub.Text(rows[1].name), "Fireball", "the biggest first")
    T.eq(stub.Text(rows[1].amount), "750")
    T.eq(stub.Text(rows[1].rate), "75")
    T.eq(stub.Text(rows[1].share), "75%")
    T.eq(rows[1].icon:GetTexture(), 1001)
    T.eq(stub.Text(rows[2].extra), "40", "overkill, for damage")
    -- A click on the Spell column sorts by name, again flips it.
    local head = BW().tables.spells.head
    head.cells.name:GetScript("OnClick")(head.cells.name)
    T.eq(stub.Text(bwRows("spells")[1].name), "Fire Blast", "A to Z")
    head.cells.name:GetScript("OnClick")(head.cells.name)
    T.eq(stub.Text(bwRows("spells")[1].name), "Fireball", "Z to A")
end)

T.test("breakdown window: the players down its side; picking another shows theirs", function()
    login()
    raidSpells()
    stub.infopanel.Meter.Draw()
    clickRow(1)
    local side = BW().side
    T.eq(#side.rows, 2)
    local function row(i) return side.shown[i] end
    T.eq(stub.Text(row(1).name), "Sigzil")
    T.truthy(row(1).pick:IsShown(), "picked: the accent wash")
    row(2):GetScript("OnClick")(row(2), "LeftButton")
    T.eq(stub.Text(BW().frame.title), "Kaladin")
    T.eq(stub.meter.askedSource[3], "Player-3")
    T.truthy(row(2).pick:IsShown())
    T.falsy(row(1).pick:IsShown())
end)

T.test("breakdown window: the targets tab merges the units hit by name", function()
    login()
    raidSpells()
    stub.meter.spells[3] = { spellID = 1, totalAmount = 100, combatSpellDetails = { unitName = "Sadeas", amount = 100 } }
    stub.infopanel.Meter.Draw()
    clickRow(1)
    local f = BW().frame
    BW().Show("targets")
    T.eq(f.tab, "targets")
    local rows = bwRows("targets")
    T.eq(#rows, 2)
    T.eq(stub.Text(rows[1].name), "Sadeas")
    T.eq(stub.Text(rows[1].amount), "850")
end)

T.test("breakdown window: open across a fight, it keeps the player picked before it and never errors", function()
    login()
    stub.SetGroup(true)
    raidSpells()
    local M = stub.infopanel.Meter
    M.Draw()
    clickRow(2)
    stub.EnterCombat()
    T.noerror(function() M.Draw(); BW().Refill(true) end)
    T.truthy(BW().frame:IsShown())
    T.eq(stub.meter.askedSource[3], "Player-3", "their GUID was read while it was plain")
    T.eq(#bwRows("spells"), 2)
    -- Someone the meter can't tell apart, picked in the fight, and why it waits.
    local live = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    stub.meter.sources[3] = { name = "Teft", classFilename = "WARRIOR", totalAmount = 500, sourceGUID = "Player-4" }
    BW().Pick(live.combatSources[1])
    T.truthy(BW().waits.spells:IsShown() or #bwRows("spells") > 0)
    stub.LeaveCombat()
    stub.SetGroup(false)
end)

T.test("breakdown window: it closes when its meter window is deleted, and with its X", function()
    local DUI = login()
    raidSpells()
    local id = W().Add("damage")
    stub.RunTimers(); tweens()
    local view = host(id).view
    view.Draw()
    view.RowClick(view.rows[1], "LeftButton")
    tweens()
    T.truthy(BW().frame:IsShown())
    W().Remove(id)
    stub.RunTimers(); tweens()
    T.falsy(DUI.Win.IsOpen(BW().frame), "its meter went: it goes too")
    clickRow(1)
    T.truthy(DUI.Win.IsOpen(BW().frame))
    BW().frame.close:Click()
    tweens()
    T.falsy(DUI.Win.IsOpen(BW().frame))
end)

-- ---------------------------------------------------------------------
-- The death log (DeathLog.lua)
-- ---------------------------------------------------------------------

local function recap()
    -- As the game gives it: newest first, killing blow first.
    stub.meter.recaps = { [7] = { maxHealth = 1000, events = {
        { event = "SPELL_DAMAGE", timestamp = 100.0, spellId = 1, spellName = "Fireball", sourceName = "Sadeas",
          amount = 400, overkill = 120, currentHP = 0 },
        { event = "SPELL_HEAL", timestamp = 99.2, spellId = 2, spellName = "Fire Blast", sourceName = "Navani",
          amount = 150, currentHP = 280 },
        { event = "SWING_DAMAGE", timestamp = 97.6, amount = 300, sourceName = "Axehound", currentHP = 130 },
    } } }
end

T.test("death log: the recap's last hits oldest first, heals marked, the killing blow with its overkill", function()
    login()
    recap()
    local log = stub.infopanel.DeathLog.Read(7)
    T.eq(#log.events, 3)
    local first, last = log.events[1], log.events[3]
    T.eq(first.source, "Axehound"); T.near(first.ago, 2.4, 1e-6, "seconds before the death")
    T.eq(first.spell, DaylightUI.L["Melee"], "a swing is a melee hit")
    T.truthy(log.events[2].heal, "a heal")
    T.eq(log.events[2].spell, "Fire Blast")
    T.near(log.events[2].hp, 0.28, 1e-6, "health after it")
    T.truthy(last.killing)
    T.eq(last.overkill, 120)
    T.eq(last.amount, 400)
    T.eq(last.icon, 1001)
    T.isnil(stub.infopanel.DeathLog.Read(8), "no recap: nothing")
end)

T.test("death log: a recap still secret waits for the fight's end", function()
    login()
    recap()
    stub.meter.recaps[7].events[1].amount = stub.Secret(400)
    local log, why = stub.infopanel.DeathLog.Read(7)
    T.isnil(log)
    T.eq(why, stub.infopanel.Breakdown.WAIT)
end)

T.test("death log: the breakdown window's Death tab lists the last hits, the killing blow lit", function()
    local DUI = login()
    recap()
    DUI:Set("InfoPanel", "meter.mode", "deaths"); stub.RunTimers()
    stub.meter.sources = { { name = "Teft", classFilename = "WARRIOR", deathRecapID = 7, deathTimeSeconds = 83,
                             sourceGUID = "Player-4" } }
    local M = stub.infopanel.Meter
    M.Draw()
    clickRow(1)
    local f = BW().frame
    T.eq(f.tab, "death", "a death opens on its log")
    local rows = bwRows("death")
    T.eq(#rows, 3)
    T.eq(stub.Text(rows[1].time), "-2.4s")
    T.eq(stub.Text(rows[3].amount), "-400")
    T.rgb({ rows[3].amount:GetTextColor() }, DUI.Style.INK.DAMAGE, "damage in its soft red")
    T.eq(stub.Text(rows[2].amount), "+150")
    T.rgb({ rows[2].amount:GetTextColor() }, DUI.Style.INK.GOOD, "a heal in green")
    T.truthy(stub.Text(rows[3].extra):find("120", 1, true), "the overkill")
    T.near(rows[2].hp:GetValue(), 0.28, 1e-6, "health after it")
end)

T.test("death log: hovering a death shows its last hits, the killing blow first", function()
    local DUI = login()
    recap()
    DUI:Set("InfoPanel", "meter.mode", "deaths"); stub.RunTimers()
    stub.meter.sources = { { name = "Teft", classFilename = "WARRIOR", deathRecapID = 7, deathTimeSeconds = 83 } }
    local M, B = stub.infopanel.Meter, stub.infopanel.Breakdown
    M.Draw()
    hoverRow(1)
    T.truthy(B.Frame():IsShown())
    local rows = tipRows()
    T.eq(stub.Text(rows[1].name), "Fireball", "the killing blow first")
    T.eq(stub.Text(rows[1].amount), "400")
end)

-- ---------------------------------------------------------------------
-- Summary windows (Summary.lua)
-- ---------------------------------------------------------------------

local function summaryWorld()
    local E = Enum.DamageMeterType
    local function p(name, class, guid, amount, rate)
        return { name = name, classFilename = class, sourceGUID = guid, totalAmount = amount, amountPerSecond = rate }
    end
    stub.meter.sources = {
        [E.DamageDone] = { p("Sigzil", "MAGE", "Player-2", 1000, 100), p("Kaladin", "WARRIOR", "Player-3", 800, 80) },
        [E.Dps] = { p("Sigzil", "MAGE", "Player-2", 1000, 100), p("Kaladin", "WARRIOR", "Player-3", 800, 80) },
        [E.HealingDone] = { p("Navani", "PRIEST", "Player-5", 1500, 150), p("Kaladin", "WARRIOR", "Player-3", 50, 5) },
        [E.Hps] = { p("Navani", "PRIEST", "Player-5", 1500, 150) },
        [E.Interrupts] = { p("Kaladin", "WARRIOR", "Player-3", 4) },
        [E.Dispels] = { p("Navani", "PRIEST", "Player-5", 3) },
        [E.Deaths] = { p("Sigzil", "MAGE", "Player-2", 0) },
    }
end
local function summaryRows(h)
    local t, out = h.view.table, {}
    for i = 1, #t.rows do if t.shown[i] then out[#out + 1] = t.shown[i] end end
    table.sort(out, function(a, b) return a.index < b.index end)
    return out
end

T.test("summary: one row per player with damage, DPS, healing, HPS, interrupts, dispels and deaths", function()
    login()
    summaryWorld()
    local id = W().Add("summary")
    stub.RunTimers(); tweens()
    local h = host(id)
    T.eq(h.kind, "summary")
    T.truthy(h.frame:IsShown())
    h.view.Draw()
    local rows = summaryRows(h)
    T.eq(#rows, 3, "everyone in any list, once")
    T.eq(stub.Text(rows[1].cells.name), "Sigzil", "most damage first")
    T.eq(stub.Text(rows[1].cells.damage), "1K")
    T.eq(stub.Text(rows[1].cells.dps), "100")
    T.eq(stub.Text(rows[1].cells.deaths), "1")
    local kal = rows[2]
    T.eq(stub.Text(kal.cells.name), "Kaladin")
    T.eq(stub.Text(kal.cells.interrupts), "4")
    T.eq(stub.Text(kal.cells.healing), "50")
    T.eq(stub.Text(rows[3].cells.dispels), "3")
    T.eq(stub.Text(rows[3].cells.damage), "", "nothing in a column: blank")
end)

T.test("summary: a column click sorts by it, again flips it", function()
    local DUI = login()
    summaryWorld()
    local id = W().Add("summary")
    stub.RunTimers(); tweens()
    local h = host(id)
    h.view.Draw()
    local head = h.view.table.head
    head.cells.healing:GetScript("OnClick")(head.cells.healing)
    T.eq(stub.Text(summaryRows(h)[1].cells.name), "Kaladin", "least healing first")
    head.cells.healing:GetScript("OnClick")(head.cells.healing)
    T.eq(stub.Text(summaryRows(h)[1].cells.name), "Navani", "most healing first")
    T.eq(DUI:Get("InfoPanel", "meters.windows." .. id .. ".sort"), "healing", "kept")
end)

T.test("summary: in a fight it keeps the last fight and says it updates when it ends", function()
    login()
    summaryWorld()
    local id = W().Add("summary")
    stub.RunTimers(); tweens()
    local h = host(id)
    h.view.Draw()
    stub.EnterCombat()
    T.noerror(function() h.view.Draw() end)
    T.eq(#summaryRows(h), 3, "the last fight's rows stay")
    T.truthy(h.view.note:IsShown())
    T.eq(stub.Text(h.view.note), DaylightUI.L["Fight on: updates when it ends."])
    stub.LeaveCombat()
    h.view.Draw()
    T.falsy(h.view.note:IsShown())
end)

T.test("summary: columns switch off", function()
    local DUI = login()
    summaryWorld()
    local id = W().Add("summary")
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".columns.dps", false)
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".columns.hps", false)
    stub.RunTimers(); tweens()
    local h = host(id)
    h.view.Draw()
    local cols = h.view.table.head.cells
    T.isnil(cols.dps); T.isnil(cols.hps)
    T.truthy(cols.healing)
end)

T.test("summary: a click on a player opens their breakdown", function()
    login()
    summaryWorld()
    local id = W().Add("summary")
    stub.RunTimers(); tweens()
    local h = host(id)
    h.view.Draw()
    local r = summaryRows(h)[2]
    r:GetScript("OnClick")(r, "LeftButton")
    tweens()
    T.truthy(BW().frame:IsShown())
    T.eq(stub.Text(BW().frame.title), "Kaladin")
end)

-- ---------------------------------------------------------------------
-- Threat windows and the breakdown: edge cases
-- ---------------------------------------------------------------------

T.test("breakdown window: an error in it never stops the meter drawing", function()
    login()
    raidSpells()
    local M = stub.infopanel.Meter
    local changed = BW().Changed
    BW().Changed = function() error("boom") end
    T.noerror(function() M.Draw() end)
    BW().Changed = changed
end)

T.test("breakdown window: a player picked in a fight is found again after it, by the GUID the meter knew", function()
    login()
    stub.SetGroup(true)
    raidSpells()
    stub.meter.sources[1].specIconID = 135932
    stub.meter.sources[2].specIconID = 132355
    local M = stub.infopanel.Meter
    M.Draw()   -- the map: Sigzil the only mage
    stub.EnterCombat()
    local live = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    BW().Open(M, live.combatSources[1])
    tweens()
    stub.LeaveCombat()
    BW().Refill(true)
    T.eq(stub.Text(BW().frame.title), "Sigzil", "the plain name again")
    T.truthy(BW().side.shown[1].pick:IsShown(), "and picked in the list")
    stub.SetGroup(false)
end)

T.test("meter tip: the who's-who map keeps every list's players, and a roster change starts it over", function()
    login()
    local M = stub.infopanel.Meter
    M.SnapGuids({ { sourceGUID = "Player-2", classFilename = "MAGE", specIconID = 1 } })
    M.SnapGuids({ { sourceGUID = "Player-5", classFilename = "PRIEST", specIconID = 2 } })
    T.eq(M.guids["MAGE:1"], "Player-2", "the damage meter's mage stays")
    T.eq(M.guids["PRIEST:2"], "Player-5", "beside the healing window's priest")
    M.SnapGuids({ { sourceGUID = "Creature-9", classFilename = "", specIconID = 0 } }, "enemy")
    T.isnil(M.guids[":0"], "enemies never go in")
    stub.FireEvent("GROUP_ROSTER_UPDATE")
    T.isnil(M.guids["MAGE:1"], "a new group: who's who again")
end)

T.test("meter tip: a mob's breakdown in a fight goes by its plain creature id", function()
    login()
    local M = stub.infopanel.Meter
    local guid, creature = M.GuidOf({ sourceGUID = stub.Secret("Creature-0-1"), sourceCreatureID = 4321 })
    T.isnil(guid)
    T.eq(creature, 4321)
end)

T.test("breakdown window: a refill skipped by its pace comes a moment later", function()
    login()
    raidSpells()
    stub.infopanel.Meter.Draw()
    clickRow(1)
    local n, fill = 0, BW().tables.spells.SetRows
    BW().tables.spells.SetRows = function(...) n = n + 1; return fill(...) end
    BW().Refill()
    BW().Refill()
    local before = n
    stub.Advance(1)
    stub.RunTimers()
    T.truthy(n > before, "the skipped one runs after the wait")
    BW().tables.spells.SetRows = fill
end)

T.test("breakdown window: switched to deaths with no death, it says so rather than going blank", function()
    local DUI = login()
    raidSpells()
    stub.infopanel.Meter.Draw()
    clickRow(1)
    DUI:Set("InfoPanel", "meter.mode", "deaths"); stub.RunTimers()
    BW().Refill(true)
    BW().Show("spells")
    T.truthy(BW().waits.spells:IsShown())
    T.truthy(stub.Text(BW().waits.spells) ~= "", "a reason")
end)

-- ---------------------------------------------------------------------
-- The Meters options page (MeterOptions.lua)
-- ---------------------------------------------------------------------

local function MO() return stub.infopanel.MeterOptions end
local function metersPage() return DaylightUI.Options.GetPage("InfoPanel.meter") end
local function row(key)
    for _, g in ipairs(metersPage().groups) do
        for _, item in ipairs(g.items) do
            if item.key == key then return item, g end
        end
    end
end
local function get(key) return DaylightUI.Options.Getter(metersPage())(key) end

T.test("meter options: one Meters page; the second meter's and threat meter's pages are gone", function()
    login()
    local ids = {}
    for _, s in ipairs(DaylightUI.Options.Sections()) do
        if s.id == "InfoPanel" then for _, p in ipairs(s.pages) do ids[p.id] = true end end
    end
    T.truthy(ids["InfoPanel.meter"])
    T.isnil(ids["InfoPanel.meter2"])
    T.isnil(ids["InfoPanel.threat"])
    T.eq(metersPage().label, "Meters")
    T.eq(DaylightUI.Movers.OptionsOf("infopanel.threat"), "InfoPanel.meter", "the threat meter's handle opens it")
    T.eq(stub.infopanel.ThreatMeter.PAGE, "InfoPanel.meter")
end)

T.test("meter options: every row checks out (defaults, kinds, descriptions)", function()
    login()
    local errors = DaylightUI.Options.ValidatePage(metersPage())
    T.eq(#errors, 0, table.concat(errors, "; "))
end)

T.test("meter options: Settings for picks a window, and every row reads and writes that window's settings", function()
    local DUI = login()
    local id = W().Add("healing")
    stub.RunTimers()
    local page = metersPage()
    T.eq(page.mapKey("win.rowHeight"), "meter.rowHeight", "the panel's meter at first")
    MO().Pick(id)
    T.eq(page.mapKey("win.rowHeight"), "meters.windows." .. id .. ".rowHeight")
    local item = row("win.rowHeight")
    DUI.Options.Set(page, item, 24)
    T.eq(DUI:Get("InfoPanel", "meters.windows." .. id .. ".rowHeight"), 24)
    T.eq(DUI:Get("InfoPanel", "meter.rowHeight"), 18, "the panel's meter untouched")
    T.eq(DUI.Options.Get(page, row("win.mode")), "healing")
    MO().Pick("threat")
    T.eq(page.mapKey("win.rowHeight"), "threat.rowHeight")
end)

T.test("meter options: threat rows show only for a threat window, meter rows only for meters", function()
    login()
    local function hidden(key) local it = row(key); return it.hidden ~= nil and it.hidden(get) == true end
    MO().Pick("main")
    T.truthy(hidden("win.pullLine"))
    T.falsy(hidden("win.mode"))
    T.falsy(hidden("meter.detached"), "the panel's own: its separate window")
    MO().Pick("threat")
    T.falsy(hidden("win.pullLine"))
    T.truthy(hidden("win.mode"))
    T.truthy(hidden("meter.detached"))
    T.falsy(hidden("win.at"), "the threat meter's spot beside the meter")
    local id = W().Add("threat")
    MO().Pick(id)
    T.truthy(hidden("win.at"), "a threat window of your own is always its own window")
    T.falsy(hidden("win.unit"), "but it can follow your focus")
end)

T.test("meter options: Reset page puts the picked window back, never writing another kind's settings into it", function()
    local DUI = login()
    local id = W().Add("healing")
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".rowHeight", 30)
    MO().Pick(id)
    DUI.Options.ResetPage(metersPage())
    T.eq(DUI:Get("InfoPanel", "meters.windows." .. id .. ".rowHeight"), 22)
    T.isnil(rawget(DUI:Get("InfoPanel", "meters.windows." .. id), "pullLine"), "no threat settings in a meter window")
end)

T.test("meter options: a window's options button opens the page with it picked", function()
    local DUI = login()
    local id = W().Add("damage")
    stub.RunTimers(); tweens()
    local h = host(id)
    h.view.header.buttons.options:GetScript("OnClick")(h.view.header.buttons.options)
    T.truthy(DUI.OptionsPanel.IsShown())
    T.eq(DUI.OptionsPanel.Current(), "InfoPanel.meter")
    T.eq(MO().picked, id)
end)

T.test("meter options: search finds a window's rows", function()
    login()
    local hits = DaylightUI.Options.Search("Always show yourself")
    local found = false
    for _, h in ipairs(hits) do if h.page.id == "InfoPanel.meter" then found = true end end
    T.truthy(found)
end)

T.test("meter options: deleting the picked window picks the panel's meter", function()
    login()
    local id = W().Add("damage")
    MO().Pick(id)
    W().Remove(id)
    T.eq(MO().picked, "main")
end)

T.test("meter options: the window list lists every window and makes new ones", function()
    local DUI = login()
    W().Add("healing")
    DUI.OptionsPanel.Show("InfoPanel.meter")
    local list = MO().list
    T.truthy(list, "the list is built")
    MO().UpdateList(list)
    T.eq(list.count, 3, "the panel's meter, the threat meter, your healing window")
    MO().New("threat")
    MO().UpdateList(list)
    T.eq(list.count, 4)
    T.eq(MO().picked, W().Own()[2].id, "a new window is the one being set")
end)

-- ---------------------------------------------------------------------
-- More edge cases
-- ---------------------------------------------------------------------

T.test("final: a player who died twice opens on the death clicked, not their first", function()
    local DUI = login()
    recap()
    stub.meter.recaps[8] = { maxHealth = 1000, events = {
        { event = "SPELL_DAMAGE", timestamp = 50, spellId = 2, spellName = "Fire Blast", sourceName = "Axehound", amount = 900, overkill = 10, currentHP = 0 },
    } }
    DUI:Set("InfoPanel", "meter.mode", "deaths"); stub.RunTimers()
    stub.meter.sources = { { name = "Teft", classFilename = "WARRIOR", deathRecapID = 7, deathTimeSeconds = 30, sourceGUID = "Player-4" },
                           { name = "Teft", classFilename = "WARRIOR", deathRecapID = 8, deathTimeSeconds = 90, sourceGUID = "Player-4" } }
    local M = stub.infopanel.Meter
    M.Draw()
    clickRow(2)
    BW().Refill(true)
    local rows = bwRows("death")
    T.eq(#rows, 1, "the second death's log")
    T.truthy(BW().side.shown[2].pick:IsShown(), "and that death picked in the list")
    T.falsy(BW().side.shown[1].pick:IsShown())
end)

T.test("final: a summary window's grip keeps its width within the summary's own bounds", function()
    local DUI = login()
    local id = W().Add("summary")
    DUI.Movers.Unlock()
    stub.RunTimers(); tweens()
    local h = host(id)
    local minW = h.frame:GetResizeBounds()
    T.truthy(minW >= 330, "never narrower than its columns: " .. tostring(minW))
    h.grip:GetScript("OnMouseDown")(h.grip)
    h.frame:SetSize(560, 300)
    h.grip:GetScript("OnMouseUp")(h.grip)
    T.truthy(DUI:Get("InfoPanel", "meters.windows." .. id .. ".width") > 500, "wider than a meter may be")
    DUI.Movers.Lock()
end)

T.test("final: a summary window takes its bar height and text size", function()
    local DUI = login()
    summaryWorld()
    local id = W().Add("summary")
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".rowHeight", 26)
    DUI:Set("InfoPanel", "meters.windows." .. id .. ".textSize", 15)
    stub.RunTimers(); tweens()
    local h = host(id)
    h.view.Draw()
    local r = summaryRows(h)[1]
    T.eq(h.view.table:RowHeight(1), 26)
    local _, size = r.cells.name:GetFont()
    T.eq(size, 15)
end)

T.test("final: deleting a window puts away the report open for it", function()
    local DUI = login()
    local id = W().Add("damage")
    stub.RunTimers(); tweens()
    local h = host(id)
    h.view.header.buttons.report:GetScript("OnClick")(h.view.header.buttons.report)
    local R = stub.infopanel.Report
    T.truthy(R.frame:IsShown())
    W().Remove(id)
    stub.RunTimers(); tweens()
    T.falsy(DUI.Motion.Shown(R.frame), "the report goes with it")
end)

T.test("final: the killing blow lights up once, not on every refill", function()
    local DUI = login()
    recap()
    DUI:Set("InfoPanel", "meter.mode", "deaths"); stub.RunTimers()
    stub.meter.sources = { { name = "Teft", classFilename = "WARRIOR", deathRecapID = 7, deathTimeSeconds = 83, sourceGUID = "Player-4" } }
    stub.infopanel.Meter.Draw()
    local shines, shine = 0, DUI.Win.Parts.Shine
    DUI.Win.Parts.Shine = function(...) shines = shines + 1; return shine(...) end
    clickRow(1)
    for _ = 1, 4 do BW().Refill(true) end
    DUI.Win.Parts.Shine = shine
    T.eq(shines, 1)
end)

T.test("final: a window id that comes back as another kind gets a host of its kind", function()
    local DUI = login()
    W().Add("damage")
    stub.RunTimers(); tweens()
    local oldView, oldBody = host("w1").view, host("w1").body
    local mod = DUI:GetModule("InfoPanel")
    mod.db.meters = { order = { "w1" }, next = 2, windows = { w1 = { kind = "summary" } } }
    T.noerror(function() stub.infopanel.Refresh(mod) end)
    tweens()
    T.eq(host("w1").kind, "summary")
    T.truthy(oldView.dead, "the old meter never draws again")
    T.falsy(oldBody:IsShown(), "and its insides are away")
    T.truthy(host("w1").view.table, "a summary inside the same window")
    T.truthy(host("w1").frame:IsShown())
end)

T.test("final: a summary that can't read who's who out of a fight says why, not that a fight is on", function()
    login()
    summaryWorld()
    local id = W().Add("summary")
    stub.RunTimers(); tweens()
    local h = host(id)
    local E = Enum.DamageMeterType
    stub.meter.sources[E.DamageDone][1].sourceGUID = stub.Secret("Player-2")
    h.view.Draw()
    T.truthy(h.view.note:IsShown())
    T.eq(stub.Text(h.view.note), stub.infopanel.Summary.HIDDEN)
end)

-- ---------------------------------------------------------------------
-- Sounds
-- ---------------------------------------------------------------------

local function listen(DUI)
    local heard, play = {}, DUI.Sound.Play
    DUI.Sound.Play = function(n) heard[#heard + 1] = n; return play(n) end
    return heard, function() DUI.Sound.Play = play end
end

T.test("sounds: the breakdown window opens and closes with the soft window sounds", function()
    local DUI = login()
    raidSpells()
    stub.infopanel.Meter.Draw()
    local heard, stop = listen(DUI)
    clickRow(1)
    T.eq(heard[1], "open")
    BW().frame.close:Click()
    stop()
    local closed = false
    for _, n in ipairs(heard) do if n == "close" then closed = true end end
    T.truthy(closed)
end)

T.test("sounds: a new meter window opens with the window sound; deleting one plays the done sound", function()
    local DUI = login()
    local heard, stop = listen(DUI)
    local b = stub.infopanel.Meter.header.buttons.new
    b:GetScript("OnClick")(b)
    local rows = PW.menuRows()
    rows[2]:GetScript("OnClick")(rows[2])
    T.eq(heard[#heard], "open", "a new window: the open sound")
    DUI.OptionsPanel.Show("InfoPanel.meter")
    local list = MO().list
    MO().UpdateList(list)
    local line = list.lines[3]
    line.delete:GetScript("OnClick")(line.delete)
    line.delete:GetScript("OnClick")(line.delete)
    stop()
    T.eq(heard[#heard], "gone", "deleted: the sound an \"Are you sure?\" makes")
    T.eq(#W().Own(), 0)
end)

-- ---------------------------------------------------------------------
-- Seen in game: the spec icon is secret even out of a fight, and the
-- game's own per-second number is wrong out of one (6234 damage: 0.0015)
-- ---------------------------------------------------------------------

T.test("game rules: a source's spec icon is secret out of a fight; the meter draws and still tells players apart", function()
    login()
    local M = stub.infopanel.Meter
    stub.SetGroup(true)
    stub.meter.sources = { { name = "Raging Daylight", classFilename = "WARRIOR", specIconID = 132355, isLocalPlayer = true,
                             totalAmount = 6234, amountPerSecond = 0.001488, sourceGUID = "Player-7055-002EE08B" },
                           { name = "Sigzil", classFilename = "MAGE", specIconID = 135932, totalAmount = 900,
                             sourceGUID = "Player-2" } }
    local s = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    T.truthy(issecretvalue(s.combatSources[1].specIconID), "secret, out of a fight too")
    T.noerror(function() M.Draw() end)
    T.eq(stub.Plain(M.rows[1].icon:GetTexture()), 132355, "the secret icon goes straight to the texture")
    stub.EnterCombat()
    local live = C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    T.eq(M.GuidOf(live.combatSources[2]), "Player-2", "the only mage, told apart by class")
    stub.LeaveCombat()
    stub.SetGroup(false)
end)

T.test("game rules: per second is the total over the fight's length when the numbers are plain", function()
    local DUI = login()
    local M = stub.infopanel.Meter
    DUI:Set("InfoPanel", "meter.showShare", false); stub.RunTimers()
    stub.meter.durations = { [Enum.DamageMeterSessionType.Current] = 60 }
    stub.meter.sources = { { name = "Raging Daylight", classFilename = "WARRIOR", totalAmount = 6234, amountPerSecond = 0.001488 } }
    M.Draw()
    T.eq(stub.Text(M.rows[1].amount), "103 (6.2K)")
end)
