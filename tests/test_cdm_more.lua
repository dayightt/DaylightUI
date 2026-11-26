local stub = require("stub")
local LW = require("cdmlayoutworld")
local H = require("helpers")
local loadWorld, realFacts, plainAuras = LW.loadWorld, LW.realFacts, LW.plainAuras
local data, empty, filled, box = LW.data, LW.empty, LW.filled, LW.box
local profileWorld, oldLayout, oldSet, oldBlock = LW.profileWorld, LW.oldLayout, LW.oldSet, LW.oldBlock
local inBlock, parked, boopy, nightzFile = LW.inBlock, LW.parked, LW.boopy, LW.nightzFile
local nightz, fakeViewer, fakeRegistry, rowsWorld = LW.nightz, LW.fakeViewer, LW.fakeRegistry, LW.rowsWorld
local layoutFrame, pieceFrame, changeSpecTo, eased = LW.layoutFrame, LW.pieceFrame, LW.changeSpecTo, LW.eased
local garbageMadeBy, visibleMenuRowOf = H.garbageMadeBy, H.visibleMenuRowOf


-- A pass asks every piece's root about 25 times, on every aura shown or hidden.






-- A druid's stack of bars growing up from above the target frame: with the bottom
-- bar down, the rest stayed where they were and left its room empty under them.

-- Shield Block first in the group, one spell hooked on its left, three on its
-- right, Grow from Middle. With Shield Block down, its two neighbors touch with
-- no gap between them.

-- A player's warrior: Rend bar, Battle Shout bar on it, Charge on that, Thunder
-- Clap beside Charge. With Charge and Battle Shout hidden, Thunder Clap sat
-- centered on a flat line, on top of the bars.


-- A group hung out both sides of its first piece slid right when only the left
-- side's spells were up: only the right-hand run was measured.

-- A player's druid: two rows started from the right end (the first spell has the
-- second row under it and the first row on its left). With Grow from Middle only
-- the column through the first spell was centered, so changing form added and
-- dropped icons at one end and left the rows off the middle.

-- Two shown boxes that cover each other. Boxes that only touch don't.
local function overlaps(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y - a.h < b.y and b.y - b.h < a.y
end

local function noOverlap(L, shown, why)
    local ids = {}
    for id in pairs(shown) do ids[#ids + 1] = id end
    table.sort(ids)
    for i = 1, #ids do
        for j = i + 1, #ids do
            T.falsy(overlaps(L[ids[i]], L[ids[j]]),
                why .. ": " .. ids[i] .. " and " .. ids[j] .. " on top of each other")
        end
    end
end

-- Four icons snapped into a 2x2: 1 top-left (first), 2 top-right, 3 bottom-left,
-- 4 bottom-right. hooks = { { id, parent, side } }.
local function grid(D, hooks, grow)
    local set = empty()
    D.AddPiece(set, 1, "icon", 0, 0)
    for _, h in ipairs(hooks) do
        D.AddPiece(set, h[1], "icon", 0, 0)
        T.truthy(D.Hook(set, h[1], h[2], h[3], "center"))
    end
    if grow then D.SetChainValue(set, 1, "grow", grow) end
    local F = D.Layout(set)
    T.deq({ F[1].x, F[1].y, F[2].x, F[2].y, F[3].x, F[3].y, F[4].x, F[4].y },
        { 0, 0, 40, 0, 0, -40, 40, -40 }, "a 2x2")
    return set, F
end

local ROWS = { { 2, 1, "right" }, { 3, 1, "down" }, { 4, 3, "right" } }

-- A player's 2x2 with Slide over: the first spell gave up its spot, and the second
-- row rose into the first, one spell on top of another.



-- Every way to snap a 2x2 with its first piece top-left, every grow, every set of
-- pieces down: no two shown pieces cover each other.

-- The same 2x2 as bars, which are wide and flat, so a row closing along the wrong
-- axis shows up on them too.




























-- The real layout









-- A pass runs under DUI.SafeCall. One that broke partway used to leave the last
-- pass's item list half-filled (it's the same table), so the show rules
-- (Rows.Away) later missed items they were meant to hide.




-- The layout page and look

-- Shim for tests written with blocks: "block" i is the i-th chain made here
-- (icons in a row, bars in a column, each at 0, -(i-1)*48).
local shim = setmetatable({}, { __mode = "k" })
local function addBlock(D, set, kind)
    local t = shim[set] or {}
    shim[set] = t
    t[#t + 1] = { kind = kind, ids = {} }
    return #t
end
local function place(D, set, id, i, pos)
    local t = shim[set]
    for _, b in ipairs(t) do
        for n = #b.ids, 1, -1 do if b.ids[n] == id then table.remove(b.ids, n) end end
    end
    local b = t[i]
    pos = math.max(1, math.min(pos or #b.ids + 1, #b.ids + 1))
    table.insert(b.ids, pos, id)
    for _, x in ipairs(b.ids) do D.AddPiece(set, x, b.kind, 0, -(i - 1) * 48) end
    for n = 2, #b.ids do D.Hook(set, b.ids[n], b.ids[n - 1], b.kind == "bar" and "down" or "right", "start") end
end
-- Block i's chain settings and look.
local function chainOf(set, i)
    return stub.actionbars.CdmData.Chain(set, shim[set][i].ids[1])
end
local function lookOf(set, i) return chainOf(set, i).look end
local function unplace(D, set, id)
    for _, b in ipairs(shim[set] or {}) do
        for n = #b.ids, 1, -1 do if b.ids[n] == id then table.remove(b.ids, n) end end
    end
    D.RemovePiece(set, id)
end
local function frameOf(id) return _G["DaylightUICdmPiece1_" .. id] end
-- The layout page and look, continued

-- The dev tools' /dui cdm probes (DaylightUI_Dev/CdmProbe.lua), loaded on top.
local function devCdm(DUI, words)
    local ns = {}
    assert(loadfile("DaylightUI_Dev/CdmProbe.lua"))("DaylightUI_Dev", ns)
    DUI.RunCommand("cdm " .. words)
    return ns.CdmProbe
end

-- The rows world as the old editor tests had it (no editor, so E is nil).
local function editorWorld(buffIcons)
    local DUI, AB, ess, bars, icons = rowsWorld(buffIcons)
    return DUI, AB, nil, AB.CdmData, ess, bars, icons
end







-- No hooks on the game's RefreshLayout, OnAcquireItemFrame or the items'
-- SetPoint. Every time the game lays its items out again comes from an event, a
-- script or an EventRegistry callback, and the re-claim pass right after puts
-- them back.

-- The game lays its items out inside the event (a new target's full aura
-- update), so a timer would come after the frame is drawn and the icon would
-- flicker to the game's spot and back. This frame's own OnUpdate runs after the
-- events and before drawing.

-- In a fight isFullUpdate reads secret on every UNIT_AURA. A raid boss's target
-- sends several a second, so each one must not cost a whole layout pass.




-- Per-spell effects

-- Block 1 (icons): 11, 12. Block 2 (bars): 21. 13 and 22 unplaced. The game's
-- alert manager is faked, and each icon's swipe is recorded.
local function fxWorld()
    local ess, bars
    local DUI = loadWorld({ actionbars = true, before = function()
        _, ess = fakeViewer("EssentialCooldownViewer", { 11, 12, 13 })
        _, bars = fakeViewer("BuffBarCooldownViewer", { 21, 22 })
        -- The game's alert manager keeps the alert and fires the glow event.
        -- The addon reads HasAlert and nothing hooks it.
        local up = {}
        _G.ActionButtonSpellAlertManager = {
            ShowAlert = function(_, b)
                up[b] = true
                stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1); stub.RunTimers()
            end,
            HideAlert = function(_, b)
                up[b] = nil
                stub.FireEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 1); stub.RunTimers()
            end,
            HasAlert = function(_, b) return up[b] == true end,
        }
    end })
    stub.RunTimers()
    for _, item in ipairs(ess) do
        item.Cooldown.SetDrawSwipe = function(self, on) self.__swipe = on end
    end
    local AB = stub.actionbars
    local D = AB.CdmData
    local set = D.Current()
    addBlock(D, set, "icon"); addBlock(D, set, "bar")
    place(D, set, 11, 1); place(D, set, 12, 1); place(D, set, 21, 2)
    AB.CdmRows.Refresh(); stub.RunTimers()
    return DUI, AB, set, ess, bars
end

-- A glow piece's color: the solid end of its fade, else its plain color.
local function glowRGB(t)
    local gr = t.__gradient
    if gr then
        local c = (gr[2].a or 0) > (gr[3].a or 0) and gr[2] or gr[3]
        return { c.r, c.g, c.b }
    end
    local v = t.__vertex
    return v and { v[1], v[2], v[3] } or {}
end

-- Tests write settings straight into the set, so they tell the layout it changed
-- as Data's setters do.
local function pass(AB) AB.CdmData.Changed(); AB.CdmRows.Refresh(); stub.RunTimers() end







-- Spell 100 + cooldownID behind each icon. cds / charges are what the game reports.
local function withCooldowns(ess)
    local cds, charges = {}, {}
    _G.C_Spell = _G.C_Spell or {}
    C_Spell.GetSpellCooldown = function(sid) return cds[sid] end
    C_Spell.GetSpellCharges = function(sid) return charges[sid] end
    for _, item in ipairs(ess) do item.cooldownInfo = { spellID = 100 + item.cooldownID } end
    return cds, charges
end

-- Cooldown events are handled once, the frame after a burst.
local function cdEvent() stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers() end







-- A player only wanted to see them while on cooldown.


-- Searing Totem has no cooldown, so When ready Hide hid it for good. The game's
-- icon times the totem, so a totem that's down counts as its cooldown.

-- From a priest using Grow from Middle: cooldowns set to hide while ready kept
-- their spot, so the group never re-centered.

-- A druid with every form's spells in one group growing from its middle: the ones
-- left out of the form gave up nothing, so the rest sat off to one side.

-- "Not usable: Hide" (which replaced the old "Show when usable") kept its spot,
-- leaving Grow from Middle off-center.

-- Set to hide while ready, every spell showed while wanding.





-- Reactive spells like Riposte or Overpower should pop up when usable.

-- A rogue's Kick shown only when off cooldown and with the energy for it.

-- Cat spells only in Cat Form, bear spells only in Bear Form, and warrior stances
-- and rogue stealth the same way.

-- A stance is no buff, so only this wash says which one you're in.

-- Arcane Shot with every Visibility on Show vanished with no target (not
-- usable, out of range), on and off cooldown.

-- Hooked spells went missing in play for a hunter, and players have no dev
-- tools, so /dui cdm report saves one line per placed spell.

-- Overpower looked ready all the time, and "Only when usable" sitting under
-- "When ready" was confusing.




-- What the sound alerts played: the keys handed to Sound.Alert, in order.
local function listenAlerts(DUI)
    local got = {}
    local alert = DUI.Sound.Alert
    DUI.Sound.Alert = function(key) got[#got + 1] = key; alert(key) end
    return got
end



-- Wanding set off other spells' sounds. In a fight a cooldown only says that it
-- runs (isActive); its start and length are secret.













-- The game's category lists (Essential 0, Utility 1, TrackedBuff 2,
-- TrackedBar 3): known ids, and all ids including unlearned ones.
local function withCategories(known, all)
    _G.Enum.CooldownViewerCategory = { Essential = 0, Utility = 1, TrackedBuff = 2, TrackedBar = 3, HiddenActive = -1, HiddenPassive = -2 }
    _G.C_CooldownViewer = {
        GetCooldownViewerCategorySet = function(cat, allow)
            if cat < 0 then error("bad argument #1 to '?' (Usage: local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category [, allowUnlearned]))", 2) end
            return (allow and all or known)[cat] or {}
        end,
    }
end
local function noCategories()
    _G.C_CooldownViewer, _G.Enum.CooldownViewerCategory = nil, nil
end


-- In combat the spell list isn't kept (ids may be secret), so a layout pass
-- reads it once and hands it to every piece.

-- A pass runs on every aura change in a fight. A piece's block comes from its saved
-- settings alone, so making it again each pass was most of the pass's garbage.

-- The game's info call makes a new table each time; passes in a fight asked it
-- thousands of times a minute, so each id is read once until spells change.


-- Aura spells the game doesn't display, with the game's aura container in a holder.
local function auraWorld(selfAura, buffIcons)
    local DUI, AB, E, D, ess, bars, icons = editorWorld(buffIcons)
    withCategories({ [2] = { 41, 42, 43 } }, { [2] = { 41, 42, 43 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = selfAura, linkedSpellIDs = id == 42 and { 900 } or nil }
    end
    C_Spell.GetSpellName = function(sid) return (sid == 141 or sid == 142 or sid == 900) and "Rend" or ("Spell" .. sid) end
    C_Spell.GetSpellTexture = function() return 1234 end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 41, 1, 1)
    return DUI, AB, E, D, set, ess, bars, icons
end

-- selfAura false doesn't mean "on the target": Battle Shout says false because
-- it reaches the party. The game looks on you, then your target, whatever it says
-- (scanUnits in CooldownViewerItemData.lua), and so does the addon.


-- The client writes the stacks into the count text as it takes it, so a text
-- with no font yet errored and the icon never showed its stacks.




-- Block options: "Hide out of combat" and "Show missing buffs".




-- The game's own aura item only looks on you for HELPFUL|PLAYER
-- (GetTargetAurasFilterString in CooldownViewerItemData.lua, since you're a
-- friend), so it never sees a debuff a spell puts on you, such as Arcane Blast's
-- stack (400573). The addon draws it from your debuffs; the game's item stays
-- out of sight and is never asked.

-- A mage pulling with Arcane Blast stacks still up from the last fight: that cast
-- was left to a read of the debuff, but the fight it started hid the debuff first,
-- so the count stayed one short for the whole chain (a player on 1.8.4: 2 on the
-- bar, 3 on the game's debuff). Counted once the fight hides it, icon and bar.

-- A shaman's Lightning Shield (Buff up Hide, Buff missing Show) never came back
-- when its charges ran out in a fight (a player on 1.8.4): the aura can't be read
-- there, and nothing but the cast says it's up. The game's own cooldown icon of it
-- holds the aura it shows and lets it go the moment the aura ends, fights too
-- (CooldownViewerItemData.lua ClearAuraInstanceInfo), so that says down.

-- The game lists a rogue's Venom by its buff (1310703), which nobody learns: the
-- talent that procs it is 1329328. So the game calls it unknown even with the
-- talent, and the tray said "Not known right now" (a player on 1.8.4). Known
-- through the talent, it's drawn by ours, as an icon and as a bar.

-- The game's buff icon of Bestial Wrath looks on you and your target only, so it
-- never lights up for the buff on your pet. Ours draws it, as an icon and as a bar.

-- The game's buff icon only finds buffs you cast (HELPFUL|PLAYER), so another
-- warrior's Battle Shout on you never lit it. Ours watches any caster's. A DoT
-- each caster keeps their own of (Rend) stays the game's: only yours counts there.

-- Summon Hawk's hawk is no aura the game's item could find. Ours draws it from
-- your casts, as an icon and as a bar.

-- The same stack as a bar: drawn by ours too, with its time running down the bar.






-- The game's own buff item, hidden while up, kept its spot, so a group growing
-- from its middle sat off-center. This applies to every track type.

-- Demon Skin, from a card saved before Visibility existed (Buff up: Hide, Keep
-- its spot off, Glow on), showed a glow around a hidden button.

-- A druid's Omen of Clarity (Buff only, "Glow on proc" on) never glowed while
-- Clearcasting was up, because WoW Forever fires no proc alerts. Buff up's Glow
-- lights it while the buff is up.


-- Recast glow: a damage over time spell cast again early loses the ticks it had
-- left, so it glows once the next cast would land just as it runs out. Timed from
-- your own casts and the length in the game's data, so it works in a fight where
-- the aura can't be read, with or without an item of the game's for the debuff.

-- Hide (Buff up) on the pieces Daylight UI draws itself. The client's button is
-- never asked to hide. Its container goes see-through instead, so it can't show
-- in a fight however the aura is read.

-- A Paladin's Kings with Show keybind on: the key stayed on screen over the
-- hidden buff.

-- Sap (hidden by default in the game's own Cooldown Manager) placed as a bar showed
-- nothing on a sapped mob. It's your debuff on the target, cast out of a fight.



-- Berserking set to Both, Fade on cooldown, Buff up Show: the buff starts the
-- cooldown, and the icon showed faded the whole time the buff was up.

-- Hidden while its buff was up, the addon's cooldown icon kept its spot in a
-- group growing from its middle.
T.test("cdm hide up: Cooldown and buff hidden while up gives its spot up, back when it drops", function()
    local DUI, AB, E, D = editorWorld()
    plainAuras()
    DUI.DB.General().motion = false
    withCategories({ [2] = { 41, 42 } }, { [2] = { 41, 42 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    _G.GetSpellBaseCooldown = function(sid) return (sid == 141 or sid == 142) and 15000 or 0 end
    local set = D.Current()
    addBlock(D, set, "icon"); place(D, set, 41, 1, 1); place(D, set, 42, 1, 2)
    T.truthy(D.SetChainValue(set, 41, "grow", "center"))
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    local full = D.Layout(set)
    local alone = D.Layout(set, { [42] = true })
    stub.auras.player = { HELPFUL = {} }
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown icon")
    local f2 = pieceFrame(D.CurrentIndex(), 42)
    T.truthy(f2 and f2:IsShown(), "the other spell is placed")
    T.eq(f2.goalX, full[42].x, "down: both in their spots")
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(AB.CdmOwn.Frame(41):GetAlpha(), 0, "up: hidden")
    T.eq(f2.goalX, alone[42].x, "up and hidden: the other one comes to the middle")
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(AB.CdmOwn.Frame(41):GetAlpha(), 1, "down: back")
    T.eq(f2.goalX, full[42].x, "down: back in its spot")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm hide up: a custom spell's aura bar hides while up", function()
    local DUI, AB, E, D, set = auraWorld(false)
    plainAuras()
    DUI.DB.General().motion = false
    local p = set.pieces[41]
    p.shape = "bar"
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    stub.auras.player = { HELPFUL = { { spellId = 141 } } }
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "aura bar")
    local h = AB.CdmBars.AuraFrame(41)
    T.eq(h.containers[1].c:GetAlpha(), 0, "the buff's bar can't show")
    T.eq(h:GetAlpha(), 0, "up: the whole bar hidden")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Who draws a spell follows from the spell and the What it shows pick alone. Hide
-- (Buff up), the buff glows, the buff sounds and Glow to recast once moved the
-- game's item to Daylight UI's holder, so a spell changed drawer as an option was
-- switched. They work on the game's own item now: a cooldown icon that shows its
-- aura says so with wasSetFromAura, a buff bar with isActive.
T.test("cdm drawer: no buff option moves a spell off the game's item, and each works on it (icon and bar)", function()
    local DUI, AB, set, ess, bars = fxWorld()
    local D, R, Fx = AB.CdmData, AB.CdmRows, AB.CdmEffects
    DUI.DB.General().motion = false
    withCategories({ [0] = { 11 }, [3] = { 21 } }, { [0] = { 11 }, [3] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    C_Spell.GetSpellInfo = function() return { castTime = 2000 } end
    AB.CdmSpells.FACTS[111], AB.CdmSpells.FACTS[121] = { cd = 6, lasts = 18 }, { lasts = 18 }
    AB.CdmOwn.Forget()
    local got = listenAlerts(DUI)
    for _, case in ipairs({ { 11, ess[1], "icon" }, { 21, bars[1], "bar" } }) do
        local id, item, shape = case[1], case[2], case[3]
        local function up(on)
            if shape == "bar" then item:SetIsActive(on) else item:SetAura(on) end
            stub.RunTimers()
        end
        up(true)
        pass(AB)
        T.eq(R.DrawnBy(id), "game", shape .. ": left unset, the game's item")
        for _, o in ipairs({ { "hideActive", true }, { "upGlow", true }, { "clipGlow", true },
            { "buffSound", "dui:done" }, { "buffEndSound", "dui:done" } }) do
            T.truthy(D.SetSpellValue(set, id, o[1], o[2]))
            pass(AB)
            T.eq(R.DrawnBy(id), "game", shape .. ": " .. o[1] .. " leaves it the game's")
            T.isnil(AB.CdmAuras.Frame(id), shape .. ": " .. o[1] .. " makes no holder of ours")
        end
        T.isnil(set.pieces[id].track, shape .. ": and nothing was picked for the player")
        D.SetSpellValue(set, id, "upGlow", false)
        D.SetSpellValue(set, id, "clipGlow", false)
        D.SetSpellValue(set, id, "buffEndSound", "none")
        -- Hide (Buff up), in a fight, with no cast of yours.
        stub.EnterCombat()
        up(false)
        if shape == "icon" then T.eq(item:GetAlpha(), 1, "icon: down, the icon shows its cooldown") end
        stub.Advance(5)
        local heard = #got
        up(true)
        T.eq(item:GetAlpha(), 0, shape .. ": hidden while its buff is up")
        T.eq(#got, heard + 1, shape .. ": and the buff's sound played as it landed")
        up(false)
        if shape == "icon" then T.eq(item:GetAlpha(), 1, "icon: back as it ends") end
        -- Glow to recast, timed from your own cast.
        D.SetSpellValue(set, id, "hideActive", false)
        D.SetSpellValue(set, id, "clipGlow", true)
        pass(AB)
        T.eq(R.DrawnBy(id), "game", shape .. ": still the game's")
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. shape, 100 + id)
        up(true)
        T.falsy(Fx.GlowShown(item), shape .. ": 18 s left, no glow yet")
        stub.Advance(15.5); stub.RunTimers()
        T.falsy(Fx.GlowShown(item), shape .. ": a cast now would still clip it")
        stub.Advance(0.6); stub.RunTimers(); stub.RunTimers()
        T.truthy(Fx.GlowShown(item), shape .. ": glows when a cast would land as it ends")
        up(false)
        T.falsy(Fx.GlowShown(item), shape .. ": gone once the game's item says it ended")
        stub.LeaveCombat()
    end
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm own icons: a spell the game files as a buff but with a real cooldown gets our cooldown icon, its buff over it", function()
    local DUI, AB, E, D = editorWorld()
    withCategories({ [2] = { 41, 42 } }, { [2] = { 41, 42 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    _G.GetSpellBaseCooldown = function(sid) return sid == 141 and 15000 or 0 end
    local set = D.Current()
    addBlock(D, set, "icon"); place(D, set, 41, 1, 1); place(D, set, 42, 1, 2)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local own = AB.CdmOwn.Frame(41)
    T.truthy(own and own:IsShown(), "Charge-like: own cooldown icon")
    T.eq(AB.CdmRows.DrawnBy(41), "aura and cooldown icon")
    local h = AB.CdmAuras.Frame(41)
    T.truthy(h and h:IsShown(), "the buff's holder")
    T.eq(h:GetParent(), own, "over our icon")
    T.truthy(h:GetFrameLevel() > own.Cooldown:GetFrameLevel(), "above its cooldown swipe")
    T.falsy(h.under:IsShown(), "no dim underlay: the cooldown icon shows while the buff is down")
    -- Track: Cooldown shows the icon alone.
    D.SetSpellValue(set, 41, "track", "cooldown")
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy(41), "own icon")
    T.falsy(h:IsShown(), "the holder put away")
    T.isnil(AB.CdmOwn.Frame(42), "Rend-like: still an aura")
    T.truthy(AB.CdmAuras.Frame(42), "aura holder")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: ready glow goes off when the game hides the cooldown, follows isActive when it doesn't", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true
    cds[111] = { duration = 0, isOnGCD = false }
    pass(AB)
    T.truthy(Fx.GlowShown(ess[1]), "ready: glow")
    stub.combat = true
    cds[111] = { duration = stub.Secret(6), isOnGCD = stub.Secret(false), isActive = stub.Secret(true) }
    cdEvent()
    T.falsy(Fx.GlowShown(ess[1]), "unknown: no stale glow")
    cds[111] = { duration = stub.Secret(6), isOnGCD = false, isActive = true }
    cdEvent()
    T.falsy(Fx.GlowShown(ess[1]), "on cooldown by isActive")
    cds[111] = { duration = stub.Secret(0), isOnGCD = false, isActive = false }
    cdEvent()
    T.truthy(Fx.GlowShown(ess[1]), "ready by isActive")
    if T.dev then
        devCdm(DUI, "cdprobe")
        T.truthy(stub.ChatContains("111: duration secret"), "cdprobe: the held spell")
    end
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Redundant work (the sweep).

T.test("cdm effects: a cast's burst of cooldown and charge events refreshes each held item once", function()
    local DUI, AB, set, ess = fxWorld()
    withCooldowns(ess)
    local Fx, Own = AB.CdmEffects, AB.CdmOwn
    local refreshed, own = 0, 0
    local realR, realO = Fx.Refresh, Own.UpdateAll
    Fx.Refresh = function(...) refreshed = refreshed + 1; return realR(...) end
    Own.UpdateAll = function(...) own = own + 1; return realO(...) end
    cdEvent()
    local per = refreshed
    T.truthy(per > 0, "held items refreshed")
    refreshed, own = 0, 0
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.FireEvent("SPELL_UPDATE_CHARGES")
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.FireEvent("SPELL_UPDATE_CHARGES")
    stub.RunTimers()
    Fx.Refresh, Own.UpdateAll = realR, realO
    T.eq(refreshed, per, "four events: one pass")
    T.eq(own, 1, "our own icons once too")
end)

T.test("cdm effects: an unchanged glow or gray isn't painted again on every cooldown event", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true
    set.pieces[12].desat = "grey"
    cds[111] = { duration = 0, isOnGCD = false }
    cds[112] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.truthy(Fx.GlowShown(ess[1]), "ready: glow")
    local icon = AB.Cooldowns.IconOf(ess[2])
    T.truthy(icon:IsDesaturated(), "on cooldown: gray")
    local paints, greys = 0, 0
    local realP = DUI.Style.AccentPair
    DUI.Style.AccentPair = function(...) paints = paints + 1; return realP(...) end
    local realD = icon.SetDesaturated
    icon.SetDesaturated = function(...) greys = greys + 1; return realD(...) end
    for _ = 1, 5 do cdEvent() end
    T.eq(paints, 0, "the lit glow isn't painted again")
    T.eq(greys, 0, "the gray isn't written again")
    DUI.Fire("StyleChanged")                    -- the accent may have changed
    cdEvent()
    T.truthy(paints > 0, "a style change paints the glow again")
    icon.SetDesaturated = realD
    icon:SetDesaturated(false)                  -- the game sets its own
    T.truthy(icon:IsDesaturated(), "ours still goes back on after the game's")
    cds[112] = { duration = 0, isOnGCD = false }
    cdEvent()
    T.falsy(icon:IsDesaturated(), "ready: colored")
    DUI.Style.AccentPair = realP
end)

-- Earlier versions drew four flat 2 px lines, which read as a border rather than
-- a glow, then hand-made lights that read as a blob. Now it's the game's own proc
-- glow, recolored, easing in and out.
T.test("cdm effects: the glow is the game's proc ring, turning, recolored, easing in and out", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    local Fx = AB.CdmEffects
    set.pieces[11].readyGlow = true
    cds[111] = { duration = 0 }
    pass(AB)
    local g = Fx.GlowFrame(ess[1])
    T.truthy(g and g:IsShown(), "lit")
    T.eq(g.tex.__atlas or g.tex:GetAtlas(), Fx.GLOW_ATLAS, "the game's proc loop art")
    T.truthy(g.tex:IsDesaturated(), "grayed, so our color tints it true")
    T.truthy(g.anim:IsPlaying(), "turning")
    T.eq(g:GetParent(), ess[1], "a frame of ours on the item, not the game's alert")
    T.eq(g:GetAlpha(), 0, "eases in from nothing")
    local drv = Fx.glowDriver
    stub.RunOnUpdate(drv, 0.05)
    local mid = g:GetAlpha()
    T.truthy(mid > 0 and mid < 1, "partway in")
    stub.RunOnUpdate(drv, 0.2)
    T.near(g:GetAlpha(), 1, 0.001, "fully in, FAST")
    T.isnil(drv.__scripts.OnUpdate, "nothing runs of ours once it's in: the ring turns by itself")
    -- Off: eases out, then hides and stops.
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    T.falsy(Fx.GlowShown(ess[1]))
    T.truthy(g:IsShown(), "still fading")
    stub.RunOnUpdate(drv, 0.1)
    T.truthy(g:GetAlpha() > 0 and g:GetAlpha() < 1, "partway out")
    stub.RunOnUpdate(drv, 0.3)
    T.falsy(g:IsShown(), "gone")
    T.falsy(g.anim:IsPlaying(), "stopped")
    T.isnil(drv.__scripts.OnUpdate, "the driver stops with nothing lit")
    -- Motion off: the fade snaps, but the ring still turns (a stopped flipbook shows its whole sheet).
    DUI.DB.General().motion = false
    cds[111] = { duration = 0 }
    cdEvent()
    stub.RunOnUpdate(drv, 0.01)
    T.eq(g:GetAlpha(), 1, "at once")
    T.truthy(g.anim:IsPlaying())
    DUI.DB.General().motion = nil
end)

-- The ring is square art: stretched over a long bar its corners smeared into a
-- blob across the whole bar (seen in game on a seal bar).
T.test("cdm effects: a bar's glow keeps square ends and stretches only the ring's straight middle", function()
    local DUI, AB = fxWorld()
    local Fx = AB.CdmEffects
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(200, 20)
    Fx.SetGlow(bar, true, { 1, 0, 1 })
    local g = Fx.GlowFrame(bar)
    local P = g.parts
    local gh = 20 + 2 * 20 * Fx.GLOW_PAD
    T.truthy(g.wide, "split for a wide item")
    T.truthy(P.left.clip:IsShown() and P.right.clip:IsShown(), "both ends drawn")
    T.near(P.left.holder:GetWidth(), gh, 0.01, "the left end is the whole ring, square")
    T.near(P.left.holder:GetHeight(), gh, 0.01)
    T.near(P.left.clip:GetWidth(), gh / 2, 0.01, "cut in half")
    T.near(P.right.holder:GetWidth(), gh, 0.01, "the right end too")
    T.near(P.mid.holder:GetWidth(), (200 + 2 * 20 * Fx.GLOW_PAD - gh) / Fx.GLOW_MID, 0.01,
        "the middle shows only the ring's straight edge")
    for _, key in ipairs({ "left", "mid", "right" }) do
        T.truthy(P[key].clip:DoesClipChildren(), key .. " is clipped")
        T.deq({ P[key].tex:GetVertexColor() }, { 1, 0, 1, 1 }, key .. " in the picked color")
    end
    -- A square icon keeps the one whole ring.
    local icon = CreateFrame("Frame", nil, UIParent)
    icon:SetSize(36, 36)
    Fx.SetGlow(icon, true)
    local gi = Fx.GlowFrame(icon)
    T.falsy(gi.wide)
    T.falsy(gi.parts.left.clip:IsShown(), "no ends on an icon")
    T.eq(select(2, gi.parts.mid.holder:GetPoint(1)), gi, "the whole ring over it")
end)

T.test("cdm layout: an aura shown or hidden re-places without reading the known spells or rebuilding the tree", function()
    local DUI, AB, E, D, ess = editorWorld()
    withCategories({ [0] = { 11, 12, 14 } }, { [0] = { 11, 12, 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.GetSpellCooldownDuration = function() return {} end
    C_Spell.GetSpellTexture = function() return 1234 end
    local set = D.Current()
    addBlock(D, set, "icon")
    place(D, set, 11, 1, 1); place(D, set, 14, 1, 2)
    AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(AB.CdmOwn.Frame(14) and AB.CdmOwn.Frame(14):IsShown(), "our own icon for 14")
    local reads = 0
    local CV = _G.C_CooldownViewer
    local realC = CV.GetCooldownViewerCategorySet
    CV.GetCooldownViewerCategorySet = function(...) reads = reads + 1; return realC(...) end
    local index = D.Index(set)
    for _ = 1, 5 do
        ess[1]:Hide(); stub.RunTimers()
        ess[1]:Show(); stub.RunTimers()
    end
    T.eq(reads, 0, "known spells kept")
    T.truthy(D.Index(set) == index, "the tree kept")
    T.truthy(AB.CdmOwn.Frame(14):IsShown(), "still placed")
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.truthy(reads > 0, "a spell learned: read again")
    place(D, set, 12, 1, 3); AB.CdmRows.Refresh(); stub.RunTimers()
    T.truthy(D.Index(set) ~= index, "the layout written: the tree again")
    T.eq(ess[2]:GetParent() and select(2, ess[2]:GetPoint(1)), frameOf(12), "the new one placed")
    CV.GetCooldownViewerCategorySet = realC
end)

-- Any spell in a bar block (CdmBars) gets the addon's own bars for what the game
-- only draws as icons. Essential 11, 12; Tracked Buffs 31 (yours), 32; Tracked Bars 21.
local function barsWorld()
    local ess, icons, bars
    local DUI = loadWorld({ actionbars = true, before = function()
        fakeRegistry()
        _, ess = fakeViewer("EssentialCooldownViewer", { 11, 12 })
        _, icons = fakeViewer("BuffIconCooldownViewer", { 31, 32 })
        _, bars = fakeViewer("BuffBarCooldownViewer", { 21 })
    end })
    stub.RunTimers()
    _G.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = id == 31 or nil }
    end }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C_Spell.GetSpellTexture = function() return 1234 end
    local w = { cds = {}, durs = {}, charges = {}, chargeDurs = {} }
    C_Spell.GetSpellCooldown = function(sid) return w.cds[sid] end
    C_Spell.GetSpellCharges = function(sid) return w.charges[sid] end
    C_Spell.GetSpellCooldownDuration = function(sid, ignoreGCD) w.ignoreGCD = ignoreGCD; return w.durs[sid] end
    C_Spell.GetSpellChargeDuration = function(sid) return w.chargeDurs[sid] end
    local AB = stub.actionbars
    local set = AB.CdmData.Current()
    addBlock(AB.CdmData, set, "bar")
    return DUI, AB, set, w, ess, icons, bars
end

-- A warrior's Charge placed as an icon never showed. The game files it under
-- Tracked Buffs (it tracks the stun) and hides its buff icon until a stun lands,
-- while the editor offers it as a cooldown.
T.test("cdm rows: a cooldown the game files as a buff is ours, not the game's hidden buff icon", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [2] = { 31, 32 } }, { [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = function(sid) return sid == 131 and 15000 or 0 end
    icons[1]:SetIsActive(false)                               -- no stun up, so the game hides it
    D.AddPiece(set, 31, "icon", 0, 0)
    D.AddPiece(set, 32, "icon", 0, -48)
    R.Refresh(); stub.RunTimers()
    local own = AB.CdmOwn.Frame(31)
    T.truthy(own and own:IsShown(), "our cooldown icon")
    T.eq(own:GetParent(), frameOf(31), "in its piece")
    T.truthy(frameOf(31):IsShown(), "its piece takes its spot")
    T.eq(icons[1]:GetAlpha(), 0, "the game's buff icon out of sight")
    icons[1]:SetIsActive(true)                               -- a stun lands, and it's still the addon's
    R.Refresh(); stub.RunTimers()
    T.eq(icons[1]:GetAlpha(), 0, "the game's buff icon stays out of sight")
    T.truthy(own:IsShown())
    T.isnil(AB.CdmOwn.Frame(32), "a real buff (no cooldown) stays the game's")
    T.eq(icons[2]:GetAlpha(), 1)
    -- As a bar it's a cooldown bar, not an aura bar that hides with the stun.
    icons[1]:SetIsActive(false)
    D.SetShape(set, 31, "bar")
    R.Refresh(); stub.RunTimers()
    T.truthy(frameOf(31):IsShown(), "the bar piece shows with the stun down")
    T.eq(R.DrawnBy(31), "aura and cooldown bar", "the stun's bar over the cooldown")
    D.SetSpellValue(set, 31, "track", "cooldown")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "cooldown bar", "Track: Cooldown")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Power Word: Shield as a bar never drained by the shield left. The game files it
-- under Tracked Bars, and the game's own bar (kept there) only knows its time.
T.test("cdm rows: a shield the game shows as a bar is our aura bar while it fills by the shield", function()
    local DUI, AB, set, w, ess, icons, bars = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [3] = { 21 } }, { [3] = { 21 } })
    -- Power Word: Shield, rank 1 (CdmSpells' families mark it as a shield).
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = id == 21 and 17 or 100 + id } end
    D.AddPiece(set, 21, "bar", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(21), "aura bar", "ours, filled by the shield")
    T.eq(bars[1]:GetAlpha(), 0, "the game's bar out of sight")
    local h = AB.CdmBars.AuraFrame(21)
    T.truthy(h.isShield and h.shield:IsShown(), "our shield bar")
    -- The empty part in the fill's own color, dimmed, read as one color. It's dark now.
    local parts = h.parts[h.containers[1].c.__groups.a.button]
    local r, g, b = parts.backTex:GetVertexColor()
    local c = DUI.Style.BACKGROUND
    T.eq(r, c[1]); T.eq(g, c[2]); T.eq(b, c[3])
    -- By time: the game's own bar does that.
    D.SetSpellValue(set, 21, "fillBy", "time")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(21), "game")
    T.eq(bars[1]:GetAlpha(), 1)
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- UNIT_SPELLCAST_SUCCEEDED's unit is secret for anyone else's cast under
-- restrictions (SecretWhenUnitSpellCastRestricted), so a handler hearing every
-- unit's casts compares a secret (`unit ~= "player"`) on each one in a raid. The
-- fake game's secrets can't fail a compare with a string, so this checks who
-- listens: only the player's own casts.
T.test("nothing of ours hears everyone's casts: your own only (the shield bars, the profession window)", function()
    barsWorld()
    local broad = {}
    for _, f in ipairs(stub.frames) do
        local fn = f.__events and f.__events.UNIT_SPELLCAST_SUCCEEDED and not f.__unitEvents.UNIT_SPELLCAST_SUCCEEDED
            and f.__scripts.OnEvent
        local src = fn and debug.getinfo(fn, "S").source or ""
        if fn and not string.find(src, "^@%.?/?tests[/\\]") and not string.find(src, "blizzard", 1, true) then
            broad[#broad + 1] = src
        end
    end
    T.eq(#broad, 0, "every unit's casts heard by " .. tostring(broad[1]))
end)

-- A priest's Power Word: Shield is a cooldown in the game's data (its Essential
-- id, with its aura). As a bar it's the shield's bar over its cooldown, and it
-- still fills by the shield left.
T.test("cdm rows: Hide (Buff missing) shows a shield's bar only while there is a shield", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 11 and 17 or 100 + id, selfAura = true, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 17 and 4000 or 0 end
    D.AddPiece(set, 11, "bar", 0, 0)
    T.truthy(D.SetSpellValue(set, 11, "missing", true))
    T.truthy(D.SetSpellValue(set, 11, "hideMissing", true))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura bar")
    T.eq(D.PieceBlock(set, 11).always, false, "Keep its spot gives way")
    local h = AB.CdmBars.AuraFrame(11)
    local s = h.shield
    T.eq(h.under:GetAlpha(), 0, "no empty bar while it's down")
    T.eq(s:GetParent(), h.shieldClip, "the shield bar in the gate's clip")
    T.eq(h.shieldGate:GetValue(), 0, "closed with no shield")
    -- Off: the empty bar keeps its spot again.
    D.SetSpellValue(set, 11, "hideMissing", false)
    R.Refresh(); stub.RunTimers()
    T.eq(s:GetParent(), h, "back out of the clip")
    T.eq(h.under:GetAlpha(), 1, "kept in its spot")
    D.SetSpellValue(set, 11, "hideMissing", true)
    R.Refresh(); stub.RunTimers()
    stub.units.player = stub.units.player or {}
    stub.units.player.absorbs = stub.Secret(250)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 592)
    T.eq(rawget(h.shieldGate:GetValue(), "__value"), 250, "open while the shield is up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A warrior's Flurry (the game's Tracked Buffs, no cooldown) placed as a bar,
-- Buff only, Buff missing: Hide, glow on proc, never showed while Flurry was up.
T.test("cdm rows: a game buff icon placed as a bar with Hide (Buff missing) shows while the buff is up", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [2] = { 31, 32 } }, { [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, linkedSpellIDs = { 200 + id } }
    end
    D.AddPiece(set, 32, "bar", 0, 0)
    T.truthy(D.SetSpellValue(set, 32, "hideMissing", true))
    T.truthy(D.SetSpellValue(set, 32, "glow", true))
    stub.auras.player = { HELPFUL = { { spellId = 232 } } }
    icons[2]:SetIsActive(true)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(32), "aura bar")
    T.truthy(frameOf(32):IsShown(), "its piece shows while up")
    local h = AB.CdmBars.AuraFrame(32)
    T.truthy(h and h:IsVisible(), "our bar is visible")
    local btn = h.containers[1].c.__groups.a.button
    T.truthy(btn and btn:IsVisible(), "the buff's bar is visible")
    T.eq(btn:GetEffectiveAlpha(), 1, "and not see-through")
    -- Down out of a fight (the piece slides over), then it procs mid-fight.
    stub.auras.player = { HELPFUL = {} }
    icons[2]:SetIsActive(false)
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    stub.EnterCombat(); stub.RunTimers()
    stub.auras.player = { HELPFUL = { { spellId = 232 } } }
    icons[2]:SetIsActive(true)
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = false, addedAuras = {} }); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    T.truthy(frameOf(32):IsShown(), "its piece shows when it procs in a fight")
    btn = h.containers[1].c.__groups.a.button
    T.truthy(btn and btn:IsVisible(), "the buff's bar is visible in the fight")
    T.eq(btn:GetEffectiveAlpha(), 1, "and not see-through in the fight")
    stub.LeaveCombat(); stub.RunTimers()
    -- The game's Tracked Buffs window hidden (Edit Mode Visibility: Hidden, or In
    -- combat while out of one) stops hearing UNIT_AURA (its OnHide in
    -- CooldownViewer.lua), so its item stays hidden with the buff up. Daylight UI
    -- draws the spell from what it reads itself.
    icons[2]:SetIsActive(false)
    icons[2]:GetParent():Hide(); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(32), "aura bar", "ours, not the hidden window's item")
    T.truthy(frameOf(32):IsShown(), "its piece shows with the game's window hidden")
    btn = h.containers[1].c.__groups.a.button
    T.truthy(btn and btn:IsVisible(), "the buff's bar is visible with the game's window hidden")
    -- A spell the game would hold in its own hidden window is drawn by the addon too.
    D.AddPiece(set, 31, "icon", 0, -48)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "aura icon", "drawn by Daylight UI, not the hidden window")
    T.eq(icons[1]:GetAlpha(), 1, "the hidden window's item let go")
    -- With the window back, its items report again.
    icons[2]:GetParent():Show(); icons[2]:SetIsActive(true); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "game", "the game's own icon again")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A shaman's Flurry buff ID is only in the game's overrideTooltipSpellID (no
-- linkedSpellIDs). The game's own item matches it there
-- (GetAssociatedAuraSpellPriority in CooldownViewerItemData), so the addon must too.
T.test("cdm rows: a game buff whose aura is only its overrideTooltipSpellID shows while up", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [2] = { 31, 32 } }, { [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, overrideTooltipSpellID = 200 + id, linkedSpellIDs = {} }
    end
    D.AddPiece(set, 32, "bar", 0, 0)
    T.truthy(D.SetSpellValue(set, 32, "hideMissing", true))
    icons[2]:GetParent():Hide(); stub.RunTimers()
    stub.auras.player = { HELPFUL = { { spellId = 232 } } }
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(32), "aura bar")
    T.truthy(frameOf(32):IsShown(), "its piece shows while the buff is up")
    T.truthy(AB.CdmAuras.SpellIDs(32)[232], "the tooltip spell is one of its auras")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: a shield the game files as a cooldown fills by the shield left over its cooldown", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 11 and 17 or 100 + id, selfAura = true, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 17 and 4000 or 0 end
    D.AddPiece(set, 11, "bar", 0, 0)
    R.Refresh(); stub.RunTimers()
    -- With no shield up the bar used to be the cooldown, full (ready) and white.
    -- A shield's bar has no cooldown under it: empty, in its spot.
    T.eq(R.DrawnBy(11), "aura bar")
    local h = AB.CdmBars.AuraFrame(11)
    local s = h.shield
    T.truthy(h.isShield and s:IsShown(), "our shield bar")
    T.falsy(h.cooldownUnder, "no cooldown under it")
    T.eq(h.Bar:GetValue(), 0, "empty with no shield")
    T.eq(h.under:GetAlpha(), 1, "kept in its spot")
    T.truthy(frameOf(11):IsShown())
    local k = h.containers[1].c
    local btn = k.__groups.a.button
    local parts = h.parts[btn]
    T.eq(parts.bar:GetStatusBarTexture():GetAlpha(), 0, "the client's time fill gives way")
    T.truthy(s:GetFrameLevel() > k:GetFrameLevel(), "ours over the client's bar")
    T.eq(parts.bar:GetAlpha(), 0, "the client's whole time bar gives way")
    T.eq(s:GetAlpha(), 1, "ours is there, empty, with no shield")
    -- You cast it with no word from the client's button. The amount right after
    -- is the full value, and the hits after drain it.
    stub.units.player = stub.units.player or {}
    stub.units.player.absorbs = stub.Secret(250)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 592)
    local _, full = s:GetMinMaxValues()
    T.eq(rawget(full, "__value"), 250, "full at the cast")
    T.eq(rawget(s.gate:GetValue(), "__value"), 250, "the amount's gate open")
    stub.Advance(1)
    stub.units.player.absorbs = stub.Secret(100)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(s:GetValue(), "__value"), 100, "drained without the button")
    _, full = s:GetMinMaxValues()
    T.eq(rawget(full, "__value"), 250, "the full stays")
    stub.Advance(1)
    -- It lands, then soaks: the bar drains and its full value is kept.
    stub.AuraVisible(btn, false)
    stub.units.player = stub.units.player or {}
    stub.units.player.absorbs = stub.Secret(300)
    stub.AuraVisible(btn, true)
    T.eq(s:GetAlpha(), 1, "shown while the shield is up")
    local _, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 300)
    stub.Advance(1)
    stub.units.player.absorbs = stub.Secret(120)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(s:GetValue(), "__value"), 120, "drained")
    -- It used to flash on a target change. With an enemy target it's still yours,
    -- and the client's button is left alone.
    local n = k.__refreshes or 0
    stub.units.target = { friend = false }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(k.__refreshes or 0, n, "no rebuild for an enemy target")
    -- The client rebuilding its button (gone and straight back) keeps the full value.
    stub.Advance(1)
    stub.AuraVisible(btn, false); stub.AuraVisible(btn, true)
    stub.units.player.absorbs = stub.Secret(90)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    _, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 300, "a blink isn't a new shield")
    T.eq(rawget(s:GetValue(), "__value"), 90)
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A prot warrior's Shield Block only showed while its buff was up. The game files
-- it as a buff. When the addon can't tell it has a cooldown (no base cooldown
-- answer), the player picks Track on the card.
T.test("cdm rows: Track picks what a buff spell shows (buff only, cooldown, both)", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [2] = { 31 }, [0] = { 33 } }, { [2] = { 31 }, [0] = { 33 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = nil                 -- no answer, so it can't tell
    icons[1]:SetIsActive(false)                               -- the buff is down, so the game hides it
    D.AddPiece(set, 31, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "unset and unknown: buff only")
    T.isnil(Own.Track(33, nil), "a cooldown-family spell has no Track")
    T.falsy(frameOf(31):IsShown(), "buff only: gone while the buff is down")
    T.falsy(D.SetSpellValue(set, 31, "track", "sometimes"), "a bad value is refused")
    T.truthy(D.SetSpellValue(set, 31, "track", "both"))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "aura and cooldown icon")
    T.truthy(frameOf(31):IsShown(), "both: in its spot with the buff down")
    T.eq(icons[1]:GetAlpha(), 0, "the game's buff icon out of sight")
    icons[1]:SetIsActive(true)                               -- the buff lands, and it's still the addon's
    R.Refresh(); stub.RunTimers()
    T.eq(icons[1]:GetAlpha(), 0)
    T.eq(R.DrawnBy(31), "aura and cooldown icon")
    D.SetSpellValue(set, 31, "track", "buff")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(31), "game", "buff only: the game's icon again")
    T.eq(icons[1]:GetAlpha(), 1)
    T.falsy(AB.CdmOwn.Frame(31):IsShown(), "our icon put away")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A layout saved while options still decided what an unset spell showed. A cooldown
-- whose icon never shows its buff turned into Cooldown and buff once Hide (Buff up)
-- or a buff glow was set, and a buff once seen on a cooldown counted as having one.
-- Neither rule exists any more, so what each such spell showed is written down as
-- its pick, once, and the screen stays as it was.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm drawer: an older layout keeps what its unset spells showed (" .. shape .. ")", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    stub.SetUnits({ player = { class = "WARRIOR" } })
    set = D.Current()
    AB.CdmSpells.WARRIOR = { { 111, cd = true, aura = true }, { 112, cd = true, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 11, 12 }, [2] = { 31, 32 } }, { [0] = { 11, 12 }, [2] = { 31, 32 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = true, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function(sid) return (sid == 111 or sid == 112) and 60000 or 0 end
    Own.Forget()
    -- Buff 131 was once seen on a cooldown (a wand shot does that to every spell).
    DUI.DB.Character().cdmCooldowns = { [131] = true }
    D.AddPiece(set, 11, shape, 0, 0)
    D.AddPiece(set, 31, shape, 0, -48)
    D.AddPiece(set, 32, shape, 0, -96)
    set.pieces[11].missingGlow = true
    set.tracksKept = nil
    pass(AB)
    local both = shape == "bar" and "aura and cooldown bar" or "aura and cooldown icon"
    T.eq(set.pieces[11].track, "both", "the glow had made it Cooldown and buff: kept as its pick")
    T.eq(R.DrawnBy(11), both, "and drawn as it was")
    T.eq(set.pieces[31].track, "both", "the cooldown once seen: kept as its pick")
    T.eq(R.DrawnBy(31), both)
    T.isnil(set.pieces[32].track, "a spell the old rules read the same way is left alone")
    T.truthy(set.tracksKept, "done once")
    -- From here on an option changes nothing about who draws a spell.
    D.AddPiece(set, 12, shape, 48, 0)
    pass(AB)
    local was = R.DrawnBy(12)
    T.truthy(D.SetSpellValue(set, 12, "missingGlow", true))
    pass(AB)
    T.isnil(set.pieces[12].track, "nothing picked for a spell set up now")
    T.eq(R.DrawnBy(12), was, "and the glow leaves its drawer alone")
    DUI.DB.Character().cdmCooldowns = nil
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- Whether a spell has a cooldown comes from the game's data, never from watching one
-- run. A wand shot puts every spell on a cooldown that isn't flagged as the global
-- one, and a buff seen on it once turned into Cooldown and buff for good.
T.test("cdm facts: a cooldown seen running never changes what a spell shows or who draws it", function()
    local DUI, AB, set, w, ess, icons = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = nil
    icons[1]:SetIsActive(false)
    D.AddPiece(set, 31, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "no cooldown in the game's data: buff only")
    T.eq(R.DrawnBy(31), "game")
    w.cds[131] = { duration = 5, isOnGCD = false }
    cdEvent()
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(31, set.pieces[31]), "buff", "a cooldown seen running teaches nothing")
    T.eq(R.DrawnBy(31), "game", "and the game's buff icon still draws it")
    T.isnil(DUI.DB.Character().cdmCooldowns, "nothing is remembered about it")
    -- The data is the word: with a cooldown there, it's Cooldown and buff from the start.
    AB.CdmSpells.FACTS[131] = { cd = 15 }
    Own.Forget()
    pass(AB)
    T.eq(Own.Track(31, set.pieces[31]), "both", "a cooldown in the game's data")
    T.eq(R.DrawnBy(31), "aura and cooldown icon")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's own Cooldown Manager switched off (Options, CVar cooldownViewerEnabled)
-- or a viewer set to Hidden: the game hides its viewers and every item in them
-- (the addon only anchors them). The addon's icons draw those spells then, and
-- hand them back to the game's items when it shows again.
T.test("cdm rows: a hidden game viewer hands its spells to our own icons", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    _G.GetSpellBaseCooldown = nil
    D.AddPiece(set, 11, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "game")
    EssentialCooldownViewer:Hide()
    stub.RunTimers()
    T.eq(R.DrawnBy(11), "own icon", "the game's viewer hidden: ours draws it")
    T.truthy(Own.Frame(11) and Own.Frame(11):IsVisible(), "and it shows")
    T.falsy(R.Owns(ess[1]), "the hidden item let go")
    EssentialCooldownViewer:Show()
    stub.RunTimers()
    T.eq(R.DrawnBy(11), "game", "shown again: the game's item")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Rend and Thunder Clap: the game files them as cooldowns, and its Essential icon
-- already shows the aura, then the cooldown. Left unset, that stays the game's when
-- the spell has a real cooldown. With none (Moonfire and Rend, where Moonfire sat
-- as a cooldown icon in game) it's the addon's aura icon, shown only while up. A
-- pick of Cooldown or Buff only is the addon's to draw.
T.test("cdm facts: a cooldown-family spell with an aura takes Cooldown or Buff only picks; one without has no Track", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, hasAura = id == 11, selfAura = false }
    end
    _G.GetSpellBaseCooldown = nil
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 12, "icon", 0, -48)
    R.Refresh(); stub.RunTimers()
    -- Unset, it stays the game's icon, shown all the time as the game shows it
    -- (Rend), with its debuff while up.
    T.eq(R.DrawnBy(11), "game", "unset, no cooldown: still the game's icon")
    T.eq(ess[1]:GetAlpha(), 1, "shown, as in the game")
    T.eq(Own.Track(11, set.pieces[11]), "both", "its aura while up, else ready")
    set.pieces[11].track = "buff"
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura icon", "Buff only picked: shown only while up")
    set.pieces[11].track = nil
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "game", "unset with a real cooldown: the game's icon (aura, then cooldown)")
    T.eq(ess[1]:GetAlpha(), 1)
    _G.GetSpellBaseCooldown = nil
    T.isnil(Own.Track(12, set.pieces[12]), "no aura: nothing to pick")
    D.SetSpellValue(set, 11, "track", "cooldown")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "own icon", "Cooldown: ours")
    T.eq(ess[1]:GetAlpha(), 0, "the game's icon out of sight")
    D.SetSpellValue(set, 11, "track", "buff")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura icon", "Buff only: the aura's holder")
    D.SetSpellValue(set, 11, "track", "both")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "game", "Both: the game's icon already does it")
    T.eq(ess[1]:GetAlpha(), 1)
    D.SetSpellValue(set, 12, "track", "cooldown")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(12), "game", "a pick on a spell with no aura changes nothing")
    D.SetShape(set, 11, "bar")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura and cooldown bar", "Both by hand as a bar: the cooldown under the aura")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm effects: our own icons and cooldown bars follow On cooldown, While ready and the glows", function()
    local DUI, AB, set, w = barsWorld()
    local D, R, Fx = AB.CdmData, AB.CdmRows, AB.CdmEffects
    withCategories({ [0] = { 14 } }, { [0] = { 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    D.AddPiece(set, 14, "icon", 0, 0)             -- the game draws no item for it, so it's the addon's icon
    D.AddPiece(set, 11, "bar", 0, -48)            -- an Essential icon as a bar is the addon's cooldown bar
    set.pieces[14].onReady = "hide"
    set.pieces[11].onReady = "hide"
    set.pieces[11].readyGlow = true
    w.cds[114] = { duration = 0 }
    w.cds[111] = { duration = 0 }
    R.Refresh(); stub.RunTimers()
    local own, bar = AB.CdmOwn.Frame(14), AB.CdmBars.CooldownFrame(11)
    T.truthy(own and own:IsShown() and bar and bar:IsShown())
    T.eq(own:GetAlpha(), 0, "own icon ready: hidden")
    T.eq(bar:GetAlpha(), 0, "own bar ready: hidden")
    T.truthy(Fx.GlowShown(bar), "the ready glow reaches our bar")
    local mouse = own:IsMouseEnabled()
    w.cds[114] = { duration = 8, isOnGCD = false, isActive = true }
    w.cds[111] = { duration = 8, isOnGCD = false, isActive = true }
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers(); eased(DUI)
    T.eq(own:GetAlpha(), 1, "own icon on cooldown: shown")
    T.eq(bar:GetAlpha(), 1, "own bar on cooldown: shown")
    T.eq(own:IsMouseEnabled(), mouse, "the mouse is left as it was on our own frames")
    R.Refresh(); stub.RunTimers()
    T.eq(own:GetAlpha(), 1, "a layout pass keeps it")
    w.cds[114] = { duration = 0 }
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers(); eased(DUI)
    T.eq(own:GetAlpha(), 0, "ready again: hidden")
    D.RemovePiece(set, 14); R.Refresh(); stub.RunTimers()
    T.falsy(own:IsShown(), "let go")
    T.isnil(Fx.ButtonOf(own), "and its effects cleared")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A priest wanding: every shot puts every spell on a cooldown the length of the
-- wand's speed, not flagged as the global one. Each cooldown hidden while ready
-- came up on every shot, the bars filling with the shot's lockout.
for _, fight in ipairs({ false, true }) do
T.test("cdm effects: a wand shot doesn't bring up our icons and cooldown bars (" .. (fight and "in a fight" or "out of one") .. ")", function()
    local DUI, AB, set, w = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [0] = { 14 } }, { [0] = { 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    C_Spell.IsAutoRepeatSpell = function(id) return id == 5019 end
    _G.UnitRangedDamage = function() return 1.5 end
    D.AddPiece(set, 14, "icon", 0, 0)
    D.AddPiece(set, 11, "bar", 0, -48)
    set.pieces[14].onReady = "hide"
    set.pieces[11].onReady = "hide"
    w.cds[114] = { duration = 0, isActive = false }
    w.cds[111] = { duration = 0, isActive = false }
    stub.Advance(10)
    R.Refresh(); stub.RunTimers(); eased(DUI)
    local own, bar = AB.CdmOwn.Frame(14), AB.CdmBars.CooldownFrame(11)
    T.eq(own:GetAlpha(), 0, "icon ready: hidden")
    T.eq(bar:GetAlpha(), 0, "bar ready: hidden")
    if fight then
        stub.combat = true
        stub.FireEvent("PLAYER_REGEN_DISABLED"); stub.RunTimers()
    end
    local function value(v) return fight and stub.Secret(v) or v end
    for shot = 1, 3 do
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "shot" .. shot, 5019)
        local lock = { startTime = value(GetTime()), duration = value(1.5), isActive = true }
        w.cds[114], w.cds[111] = lock, lock
        w.durs[114], w.durs[111] = stub.Duration(value(1.5)), stub.Duration(value(1.5))
        bar.Bar.__timer = nil
        stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers(); eased(DUI)
        T.eq(own:GetAlpha(), 0, "shot " .. shot .. ": the icon stays hidden")
        T.eq(bar:GetAlpha(), 0, "shot " .. shot .. ": the bar stays hidden")
        T.isnil(bar.Bar.__timer, "shot " .. shot .. ": the bar isn't timed by the shot")
        T.eq(bar.Bar:GetValue(), 1, "shot " .. shot .. ": full, ready")
        stub.Advance(1.5)
        w.cds[114] = { duration = value(0), isActive = false }
        w.cds[111] = { duration = value(0), isActive = false }
        w.durs[114], w.durs[111] = nil, nil
        stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers(); eased(DUI)
    end
    -- A real cooldown cast between shots still shows.
    local base = _G.GetSpellBaseCooldown
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 8000 or 0 end
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "shot4", 5019)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 111)
    w.cds[111] = { startTime = value(GetTime()), duration = value(8), isActive = true }
    w.durs[111] = stub.Duration(value(8))
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers(); eased(DUI)
    T.eq(bar:GetAlpha(), 1, "cast between shots: its real cooldown shows")
    T.truthy(bar.Bar.__timer, "and fills the bar")
    stub.combat = false
    AB.Ping.lockUntil, AB.Ping.shotAt = 0, nil
    C_Spell.IsAutoRepeatSpell, _G.UnitRangedDamage, _G.GetSpellBaseCooldown = nil, nil, base
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

T.test("cdm effects: our own icon eases in and out of Only when usable (FAST)", function()
    local DUI, AB, set, w = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    withCategories({ [0] = { 14 } }, { [0] = { 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local can = {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, false end
    D.AddPiece(set, 14, "icon", 0, 0)
    set.pieces[14].onUnusable = "hide"
    w.cds[114] = { duration = 0 }
    R.Refresh(); stub.RunTimers()
    local own = AB.CdmOwn.Frame(14)
    stub.RunOnUpdate(DUI.Motion.Driver(), 1)
    T.eq(own:GetAlpha(), 0, "not castable: gone")
    can[114] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST / 2)
    local a = own:GetAlpha()
    T.truthy(a > 0 and a < 1, "on its way in: " .. tostring(a))
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST)
    T.eq(own:GetAlpha(), 1, "in")
    set.pieces[14].onUnusable = nil
    can[114] = false
    R.Refresh(); stub.RunTimers()
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST / 2)
    local r = own.Icon:GetVertexColor()
    T.truthy(r > 0.4 and r < 1, "the dim eases in: " .. tostring(r))
    stub.RunOnUpdate(DUI.Motion.Driver(), DUI.Motion.FAST)
    T.eq((own.Icon:GetVertexColor()), 0.4, "dim")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's rogue: a cooldown bar's time sat in the middle of the bar, over the
-- spell's name, while a buff bar's time sat at its right end. The game's cooldown
-- template covers its parent (setAllPoints), so the time box has to drop that
-- left corner before it's pinned to the right end, or its numbers center on the bar.
local function onlyRight(t, w, why)
    T.truthy(t:GetNumPoints() > 0, why .. ": placed")
    for i = 1, t:GetNumPoints() do
        local p = t:GetPoint(i)
        T.truthy(p == "TOPRIGHT" or p == "BOTTOMRIGHT" or p == "RIGHT", why .. ": no " .. tostring(p) .. " point")
    end
    T.eq(t:GetWidth(), w, why .. ": the time box's width")
end
T.test("cdm bars: a cooldown bar's time sits at its right end, icon and face alike", function()
    local DUI, AB, set, w = barsWorld()
    -- The client's countdown text, lent here: the fake game has none.
    local make = CreateFrame
    CreateFrame = function(kind, ...)
        local fr = make(kind, ...)
        if kind == "Cooldown" then
            local fs = fr:CreateFontString(nil, "OVERLAY")
            fs:SetPoint("CENTER", fr, "CENTER", 0, 0)
            function fr:GetCountdownFontString() return fs end
        end
        return fr
    end
    place(AB.CdmData, set, 11, 1)
    pass(AB)
    local f = AB.CdmBars.CooldownFrame(11)
    onlyRight(f.Timer, AB.CdmBars.TIME_W, "cooldown bar")
    local fs = f.Timer:GetCountdownFontString()
    T.eq(fs:GetNumPoints(), 1); T.eq((fs:GetPoint(1)), "RIGHT", "the numbers end at the right, as a buff bar's time")
    -- A bar face (Arcane Blast's stack, Summon Hawk) times its aura the same way.
    local h = CreateFrame("Frame", nil, UIParent)
    h.Bar = CreateFrame("StatusBar", nil, h)
    local face = AB.CdmBars.MakeFace(h)
    CreateFrame = make
    onlyRight(face.Timer, AB.CdmBars.TIME_W, "bar face")
    T.eq((face.Timer:GetCountdownFontString():GetPoint(1)), "RIGHT", "bar face: numbers at the right")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: an Essential cooldown in a bar block is our bar, filled by the client", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    -- Its time uses the client's countdown numbers, as M:SS.
    local make = CreateFrame
    CreateFrame = function(kind, ...)
        local fr = make(kind, ...)
        if kind == "Cooldown" then function fr:SetCountdownFormatter(x) self.__formatter = x end end
        return fr
    end
    place(D, set, 11, 1)
    pass(AB)
    CreateFrame = make
    T.truthy(AB.CdmBars.CooldownFrame(11).Timer.__formatter == DUI.Style.ClockFormatter(), "countdown as M:SS")
    T.falsy(R.Owns(ess[1]), "the game's icon isn't claimed")
    T.eq(ess[1]:GetAlpha(), 0, "and out of sight")
    T.eq(R.DrawnBy(11), "cooldown bar")
    local f = AB.CdmBars.CooldownFrame(11)
    T.truthy(f and f:IsShown())
    T.eq(f:GetParent(), frameOf(11))
    T.truthy(R.Owns(f)); T.eq(R.BlockOf(f).kind, "bar")
    T.eq(f:GetWidth(), 220); T.eq(f:GetHeight(), 18, "the block's bar size")
    T.eq(f.Icon:GetWidth(), 18, "a square icon")
    T.truthy(AB.Cooldowns.Parts(f) and AB.Cooldowns.Parts(f).slot, "dressed like the game's bars")
    T.eq(f.Bar.Name:GetText(), "Spell111")
    T.eq(f.Bar:GetValue(), 1, "ready: full")
    -- On cooldown the client fills it from the duration object, ignoring the GCD.
    local d = stub.Duration(stub.Secret(30))
    w.cds[111] = { isActive = true }
    w.durs[111] = d
    cdEvent()
    T.truthy(f.Bar.__timer and f.Bar.__timer[1] == d, "the cooldown's duration object")
    T.eq(f.Bar.__timer[3], Enum.StatusBarTimerDirection.ElapsedTime, "fills up as it comes back")
    T.eq(w.ignoreGCD, true)
    -- The global cooldown alone: full, no timer.
    f.Bar.__timer = nil
    w.cds[111] = { isActive = true, isOnGCD = true }
    cdEvent()
    T.isnil(f.Bar.__timer); T.eq(f.Bar:GetValue(), 1)
    -- Charges (charge lines on): the bar holds the charges (a secret count drawn
    -- by the client), and the recharging piece sits one charge wide off its edge.
    local cd2 = stub.Duration(stub.Secret(8))
    f.Bar.__timer = nil
    f.Bar:SetWidth(180)                         -- its laid-out width, since the fake game doesn't solve anchors
    w.charges[111] = { maxCharges = 3, currentCharges = stub.Secret(1), isActive = true }
    w.chargeDurs[111] = cd2
    cdEvent()
    T.isnil(f.Bar.__timer, "the bar itself holds the charges")
    T.eq(select(2, f.Bar:GetMinMaxValues()), 3)
    T.truthy(f.next and f.next:IsShown() and f.next.__timer and f.next.__timer[1] == cd2, "the recharge piece")
    T.near(f.next:GetWidth(), 60, 0.01, "one charge wide")
    T.eq(select(2, f.next:GetPoint(1)), f.Bar:GetStatusBarTexture(), "off the fill's edge")
    T.truthy(f.lines[1]:IsShown() and f.lines[2]:IsShown(), "two lines for three charges")
    -- Charge lines off: the next charge's recharge spans the whole bar, as before.
    set.pieces[11].chargeLines = false
    pass(AB); cdEvent()
    T.truthy(f.Bar.__timer and f.Bar.__timer[1] == cd2, "the recharge")
    T.falsy(f.next:IsShown()); T.falsy(f.lines[1]:IsShown())
    -- Out of the block, the addon's bar hides and the game's icon comes back.
    D.SetSwitch("on", false)
    unplace(D, set, 11)
    pass(AB)
    T.falsy(f:IsShown())
    T.eq(ess[1]:GetAlpha(), 1)
    T.isnil(R.DrawnBy(11))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: a tracked buff in a bar block is the client's aura bar over an empty bar of ours", function()
    local DUI, AB, set, w, _, icons = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    place(D, set, 31, 1)
    pass(AB)
    T.eq(icons[1]:GetAlpha(), 0, "the game's icon out of sight")
    T.eq(R.DrawnBy(31), "aura bar")
    local h = AB.CdmBars.AuraFrame(31)
    T.truthy(h and h:IsShown())
    T.eq(h:GetParent(), frameOf(31))
    T.eq(h.Bar:GetValue(), 0, "our bar is the empty one")
    T.eq(h.Bar.Name:GetText(), "Spell131")
    T.eq(#h.containers, 1)
    local k = h.containers[1]
    T.eq(k.unit, "player"); T.eq(k.c.__groups.a.filter, "HELPFUL")
    T.truthy(k.c.__groups.a.opts.candidateFilters.includeSpellIDs[131])
    local btn = k.c.__groups.a.button
    T.truthy(btn.__bar, "a bar the client fills")
    T.eq(btn.__barOpts.direction, Enum.StatusBarTimerDirection.RemainingTime, "emptying as the aura runs out")
    T.truthy(btn.__time and btn.__icon and btn.__count, "time, icon and stacks the client draws")
    T.eq(btn.__timeOpts.textFormatter, DUI.Style.ClockFormatter(), "the time as M:SS")
    T.eq(btn:GetWidth(), 220); T.eq(btn:GetHeight(), 18, "the button is the bar's size")
    -- A wider block in a PvP match: the button waits until the match ends.
    stub.SetRestriction("PvPMatch", true)
    lookOf(set, 1).width = 300
    pass(AB)
    T.eq(h:GetWidth(), 300, "our holder at once")
    T.eq(btn:GetWidth(), 220, "the client's button not touched")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.SetRestriction("PvPMatch", false)
    stub.RunTimers()
    T.eq(btn:GetWidth(), 300, "after the match")
    -- The aura down (the game hid its icon) gets no slot in a collapsing block.
    -- "Show missing buffs" keeps the empty bar, pulsing when asked.
    icons[1]:SetIsActive(false); stub.RunTimers()
    T.falsy(h:IsShown(), "collapsed")
    chainOf(set, 1).always = true
    set.pieces[31].inactiveFlash = true
    pass(AB)
    T.truthy(h:IsShown(), "always show")
    T.truthy(AB.CdmEffects.Flashing(h), "pulses while down")
    icons[1]:SetIsActive(true); stub.RunTimers()
    T.falsy(AB.CdmEffects.Flashing(h), "up again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The client makes a group's buttons and runs initializeFrame the moment the group
-- is added, and the buttons lock once that returns while auras are secret. So a
-- bar first shown in a fight or a dungeon has to be the block's size from the start.
T.test("cdm bars: an aura bar first made under restrictions is the block's size at once", function()
    local DUI, AB, set = barsWorld()
    local D = AB.CdmData
    place(D, set, 31, 1)
    lookOf(set, 1).width = 300
    stub.SetRestriction("PvPMatch", true)
    pass(AB)
    local h = AB.CdmBars.AuraFrame(31)
    T.truthy(h and h.containers[1], "built")
    local btn = h.containers[1].c.__groups.a.button
    T.eq(btn:GetWidth(), 300, "the block's width, not the starting size")
    T.eq(btn:GetHeight(), h:GetHeight(), "and its height")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.SetRestriction("PvPMatch", false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm auras: an aura icon first made under restrictions is the block's size at once", function()
    local DUI, AB, E, D, set = auraWorld(false)
    lookOf(set, 1).size = 44
    stub.SetRestriction("PvPMatch", true)
    AB.CdmRows.Refresh(); stub.RunTimers()
    local h = AB.CdmAuras.Frame(41)
    T.truthy(h and h.containers[1], "built")
    local btn = h.containers[1].c.__groups.a.button
    T.eq(btn:GetWidth(), 44, "the block's size, not the starting one")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.SetRestriction("PvPMatch", false)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: the aura bar takes the block's look and the spell's own color", function()
    local DUI, AB, set = barsWorld()
    local D = AB.CdmData
    place(D, set, 32, 1)
    set.pieces[32].barMode = "solid"
    set.pieces[32].barColor = { 1, 0, 0 }
    pass(AB)
    local h = AB.CdmBars.AuraFrame(32)
    T.eq(#h.containers, 2, "not said whose: both")
    local btn = h.containers[1].c.__groups.a.button
    local parts = h.parts[btn]
    T.deq(parts.bar.__barColor, { 1, 0, 0, 1 }, "the spell's fill color on the client's bar")
    T.eq(parts.icon:GetAlpha(), 1)
    lookOf(set, 1).icon = false
    pass(AB)
    T.eq(parts.icon:GetAlpha(), 0, "icon off")
    T.truthy(select(4, parts.bar:GetPoint(1)) < 18, "the bar starts at the left")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm text: a bar's own name and time size and color, over its group's text size", function()
    local DUI, AB, set = barsWorld()
    local D, Card, INK = AB.CdmData, AB.CdmCard, DUI.Style.INK
    place(D, set, 31, 1)
    pass(AB)
    local h = AB.CdmBars.AuraFrame(31)
    local parts = h.parts[h.containers[1].c.__groups.a.button]
    T.eq(select(2, parts.time:GetFont()), 11, "unset: the group's text size")
    T.rgb({ h.Bar.Name:GetTextColor() }, INK.VALUE, "and white")
    T.eq(Card.Fallback("nameSize", set, 31), 11, "the card shows the group's")
    T.truthy(D.SetLook(set, 31, "nameSize", 15))
    T.truthy(D.SetLook(set, 31, "nameColor", { 0, 1, 0 }))
    T.truthy(D.SetLook(set, 31, "timeSize", 9))
    T.truthy(D.SetLook(set, 31, "timeColor", { 1, 0, 1 }))
    T.falsy(D.SetLook(set, 31, "timeSize", "big"), "a size is a number")
    pass(AB)
    T.eq(select(2, h.Bar.Name:GetFont()), 15, "name size")
    T.rgb({ h.Bar.Name:GetTextColor() }, { 0, 1, 0 }, "name color")
    T.eq(select(2, parts.time:GetFont()), 9, "time size on the client's time")
    T.rgb({ parts.time:GetTextColor() }, { 1, 0, 1 }, "time color")
    T.eq(select(2, parts.name:GetFont()), 15, "the button's own name too")
    T.truthy(D.SetLook(set, 31, "timeSize", 11))
    T.isnil(set.pieces[31].look.timeSize, "the group's size again: unset")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: spells the game doesn't display become our bars in a bar block", function()
    local DUI, AB, set = barsWorld()
    withCategories({ [0] = { 14 }, [2] = { 41 } }, { [0] = { 14 }, [2] = { 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, selfAura = false } end
    local D, R = AB.CdmData, AB.CdmRows
    place(D, set, 14, 1); place(D, set, 41, 1)
    pass(AB)
    T.eq(R.DrawnBy(14), "cooldown bar"); T.eq(R.DrawnBy(41), "aura bar")
    T.truthy(AB.CdmBars.CooldownFrame(14):IsShown())
    local h = AB.CdmBars.AuraFrame(41)
    T.truthy(h:IsShown())
    T.eq(h.containers[2].unit, "target"); T.eq(h.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
    -- A new target: the bar's container follows it, as the icons' do.
    local n = h.containers[2].c.__refreshes or 0
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(h.containers[2].c.__refreshes, n + 1)
    T.isnil(AB.CdmOwn.PlaceholderFrame(14, "bar"), "a real bar, not the empty stand-in")
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Rend (its Essential cooldown id) placed as a bar sat full forever. The game's
-- Essential icon shows the spell's aura while it's up
-- (CheckCacheCooldownValuesFromAura, unless the HideAura flag is set) and the
-- cooldown otherwise. The addon's bar does the same.
T.test("cdm bars: a cooldown with an aura in a bar block follows the aura, its cooldown under it", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    -- 11: Rend (a debuff on the target, no cooldown). 12: Thunder Clap (a debuff
    -- and a real cooldown).
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 112 and 6000 or 0 end
    place(D, set, 11, 1); place(D, set, 12, 1)
    pass(AB)
    T.eq(R.DrawnBy(11), "aura bar", "Rend: the debuff's bar")
    local h = AB.CdmBars.AuraFrame(11)
    T.truthy(h and h:IsShown())
    T.eq(#h.containers, 2, "you (never matches a debuff), then the target")
    T.eq(h.containers[2].unit, "target"); T.eq(h.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
    T.truthy(h.containers[2].c.__groups.a.opts.candidateFilters.includeSpellIDs[111])
    T.eq(h.Bar:GetValue(), 0, "empty while the debuff is down")
    T.isnil(AB.CdmBars.CooldownFrame(11), "no cooldown bar")
    T.eq(ess[1]:GetAlpha(), 0, "the game's icon out of sight")
    -- Thunder Clap: the debuff while it's up, with the cooldown under it.
    T.eq(R.DrawnBy(12), "aura and cooldown bar")
    local t = AB.CdmBars.AuraFrame(12)
    T.truthy(t and t:IsShown() and t.Timer, "a cooldown under the aura")
    T.eq(t.Bar:GetValue(), 1, "ready: full")
    T.falsy(t.Icon.Icon:IsDesaturated(), "the icon in color: it's a cooldown too")
    local d = stub.Duration(stub.Secret(6))
    w.cds[112] = { isActive = true }
    w.durs[112] = d
    cdEvent()
    T.truthy(t.Bar.__timer and t.Bar.__timer[1] == d, "the cooldown fills our bar")
    local k = t.containers[2].c
    T.truthy(k:GetFrameLevel() > t.Timer:GetFrameLevel(), "the client's aura bar over the cooldown")
    local btn = k.__groups.a.button
    local back = t.parts[btn].back
    T.truthy(back and back:GetAlpha() == 1, "and it hides the cooldown under it while the aura is up")
    -- On a priest's Power Word: Shield, the empty part over the cooldown was the
    -- bar texture in pure white, with a white fill on it.
    local bt = t.parts[btn].backTex
    local r, g, b = bt:GetVertexColor()
    local c = DUI.Style.BACKGROUND
    T.eq(bt:GetAlpha(), 1)
    T.eq(r, c[1]); T.eq(g, c[2]); T.eq(b, c[3])
    -- When the game is told not to show the aura (HideAura), it's a cooldown bar.
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true, flags = id == 12 and 1 or 0 }
    end
    pass(AB)
    T.eq(R.DrawnBy(12), "cooldown bar")
    T.falsy(t:IsShown(), "the aura bar gone")
    T.eq(R.DrawnBy(11), "aura bar")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Shield Block and Holy Shield hold charges, but the game's Essential icon shows
-- their buff with no count. Its cooldown items only draw spell charges, never an
-- aura's applications (CooldownViewer.lua). The addon draws them: its own
-- cooldown icon with the client's aura button over it, which draws the stacks.
T.test("cdm: Shield Block and Holy Shield in the cooldown row show their charges (ours, not the game's icon)", function()
    local DUI, AB, set, w, ess = barsWorld()
    local D, R = AB.CdmData, AB.CdmRows
    stub.SetUnits({ player = { class = "WARRIOR" } })
    set = D.Current()
    AB.CdmSpells.WARRIOR = { { 2565, cd = true, aura = true }, { 20925, 20927, 20928, cd = true, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [1] = { 11, 12 } }, { [1] = { 11, 12 } })
    -- 11: a cooldown with a buff and no charges (stays the game's icon).
    -- 12: Shield Block, as the game files it: a Utility cooldown with no aura of
    -- its own, its buff only in the addon's spell list (a quiet aura, Cooldown
    -- only when left unset).
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 12 and 2565 or 100 + id, selfAura = true, hasAura = id ~= 12 }
    end
    _G.GetSpellBaseCooldown = function() return 5000 end
    -- The charges come from the game's spell data.
    AB.CdmSpells.FACTS[2565] = { cd = 5, on = "self", lasts = 7, charges = 2 }
    AB.CdmSpells.FACTS[20928] = { cd = 10, on = "self", lasts = 10, charges = 4 }
    AB.CdmOwn.Forget()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 12, "icon", 48, 0)
    pass(AB)
    T.eq(R.DrawnBy(11), "game", "no charges: the game's icon as before")
    T.eq(AB.CdmOwn.Track(12, set.pieces[12]), "both", "its buff while up, then the cooldown")
    T.eq(R.DrawnBy(12), "aura and cooldown icon", "Shield Block: ours")
    T.eq(ess[2]:GetAlpha(), 0, "the game's icon out of sight")
    local h = AB.CdmAuras.Frame(12)
    local btn = h and h.containers[1].c.__groups.a.button
    T.truthy(btn and btn.__count, "the client draws the charges left")
    -- On cast it moved oddly: the buff dropped in over the same spell's icon.
    -- Over the addon's icon it only fades in.
    T.eq(btn.cdmSlideKey, "fade", "no drop over the cooldown icon")
    -- Then it went down 2px and back up: going on cooldown the icon dips (shrinks
    -- and springs back) and the buff's button, its size locked, rode along. The
    -- buff now sits on the icon's spot instead.
    local own = AB.CdmOwn.Frame(12)
    local _, rel = h:GetPoint(1)
    T.eq(rel, own:GetParent(), "on the spot, not the dipping icon")
    T.eq(h:GetWidth(), own:GetWidth(), "the icon's size at rest")
    -- Holy Shield, any rank.
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 12 and 20928 or 100 + id, selfAura = true, hasAura = id ~= 12 }
    end
    AB.CdmOwn.Forget()
    pass(AB)
    T.eq(R.DrawnBy(12), "aura and cooldown icon", "Holy Shield: ours")
    -- Picked Cooldown only: the game's icon never shows this buff, so it is that.
    set.pieces[12].track = "cooldown"
    pass(AB)
    T.eq(R.DrawnBy(12), "game", "Cooldown only: no buff to count, the game's own icon")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game files Slice and Dice as a cooldown with no aura, and it has no real
-- cooldown, so its icon showed nothing at all.
T.test("cdm: a filed cooldown with no real cooldown and a buff the game hides is its buff (Slice and Dice)", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    stub.SetUnits({ player = { class = "ROGUE" } })
    set = D.Current()
    AB.CdmSpells.ROGUE = { { 111, 1110, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 11 } }, { [0] = { 11 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = true, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    Own.Forget()
    D.AddPiece(set, 11, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(11, set.pieces[11]), "both", "its buff while up, else ready")
    T.eq(R.DrawnBy(11), "aura and cooldown icon", "ours: the game's icon never shows this buff")
    for _, r in ipairs(Card.ROWS.show) do
        if r.item and r.item.key == "cdm.card.track" then
            T.truthy(r.show(set, 11, set.pieces[11]), "What it shows is on its card")
        end
    end
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Searing Totem summons a totem and puts no buff on you, and has no cooldown, so
-- its piece showed nothing. It now shows the totem's time while it stands, timed
-- from its totem slot. Which totem is in the slot comes from your own casts, since
-- the slot's spell is secret in a fight.
-- The time a totem piece runs on: the icon's cooldown, or the bar's timer.
local function totemTime(AB, id, shape)
    if shape == "bar" then
        local b = AB.CdmBars.CooldownFrame(id)
        return b and b.Timer.__duration
    end
    return AB.CdmOwn.Frame(id).Cooldown.__duration
end

T.test("cdm: a totem with no buff shows the totem's time while it stands (Searing Totem), icon and bar", function()
    for _, shape in ipairs({ "icon", "bar" }) do
        local DUI, AB, set = barsWorld()
        local D, R, Own, Fx = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmEffects
        stub.SetUnits({ player = { class = "SHAMAN" } })
        set = D.Current()
        AB.CdmSpells.SHAMAN = { { 3599, 6363, 6364, aura = true }, { 8190, 10585, aura = true } }
        AB.CdmCustom.Forget()
        withCategories({ [0] = { 11 } }, { [0] = { 11 } })
        _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
            return { spellID = 6364, selfAura = false, hasAura = false }
        end
        _G.GetSpellBaseCooldown = function() return 0 end
        local n = 0
        -- Slot 1 (fire), in a fight so its spell is secret: the cast says which totem.
        local function drop(sid)
            stub.combat = true
            stub.totems[1] = sid and { spell = sid, duration = { sid = sid } } or nil
            if sid then
                n = n + 1
                stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. n, sid)
            end
            stub.FireEvent("PLAYER_TOTEM_UPDATE", 1); stub.RunTimers()
            stub.combat = false
        end
        Own.Forget()
        D.AddPiece(set, 11, shape, 0, 0)
        R.Refresh(); stub.RunTimers()
        T.eq(Own.Track(11, set.pieces[11]), "totem", shape .. ": Totem unless picked otherwise")
        T.eq(R.DrawnBy(11), "totem " .. shape, shape .. ": Daylight UI's, timed from the totem")
        T.isnil(totemTime(AB, 11, shape), shape .. ": no totem, no time")
        drop(6364)
        T.eq(totemTime(AB, 11, shape), stub.totems[1].duration, shape .. ": dropped, the totem's time")
        -- Magma Totem takes the fire slot.
        drop(10585)
        T.isnil(totemTime(AB, 11, shape), shape .. ": another fire totem, not Searing's time")
        -- Searing again, then right-clicked away.
        drop(6364)
        T.eq(totemTime(AB, 11, shape), stub.totems[1].duration, shape .. ": dropped again")
        drop(nil)
        T.isnil(totemTime(AB, 11, shape), shape .. ": destroyed, no time")
        if shape == "icon" then
            local icon = Own.Frame(11)
            T.eq(Fx.OnCooldown(icon), false, "no totem: ready (When ready Hide hides it)")
            drop(6364)
            T.eq(Fx.OnCooldown(icon), true, "dropped: counts as on cooldown")
            drop(nil)
            -- Cooldown picked: the game's own icon.
            T.truthy(D.SetSpellValue(set, 11, "track", "cooldown"))
            R.Refresh(); stub.RunTimers()
            T.isnil(Own.Track(11, set.pieces[11]), "Cooldown: the game's icon")
            T.eq(R.DrawnBy(11), "game", "Cooldown: drawn by the game")
            -- A pick saved before, when it looked like a buff, reads as Totem.
            set.pieces[11].track = "both"
            R.Refresh(); stub.RunTimers()
            T.eq(Own.Track(11, set.pieces[11]), "totem", "an old Both pick: Totem")
        end
        _G.GetSpellBaseCooldown = nil
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

-- Searing Totem from Daylight UI's own spell list (key s3599) read as a buff and
-- stayed empty: the totem check came after the own list's early return.
T.test("cdm: Searing Totem from Daylight UI's own spell list shows the totem's time", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    stub.SetUnits({ player = { class = "SHAMAN" } })
    set = D.Current()
    AB.CdmSpells.SHAMAN = { { 3599, 6363, 6364, aura = true } }
    stub.knownSpells[6364] = true
    AB.CdmCustom.Forget()
    Own.Forget()
    D.AddPiece(set, "s3599", "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track("s3599", set.pieces["s3599"]), "totem", "Totem, not a buff")
    T.eq(R.DrawnBy("s3599"), "totem icon")
    stub.totems[1] = { spell = 6364, duration = { sid = 6364 } }
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-s", 6364)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 1); stub.RunTimers()
    T.eq(Own.Frame("s3599").Cooldown.__duration, stub.totems[1].duration, "the totem's time")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Grounding and Earthbind stay up 45 s on a 15 s cooldown, and Stoneclaw and Mana
-- Tide end before their cooldown does, so a totem with a cooldown shows the cooldown.
T.test("cdm: a totem with a cooldown keeps showing its cooldown (Grounding Totem)", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    stub.SetUnits({ player = { class = "SHAMAN" } })
    set = D.Current()
    AB.CdmSpells.SHAMAN = { { 8177, cd = true, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 14 } }, { [0] = { 14 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
        return { spellID = 8177, selfAura = false, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 15000 end
    Own.Forget()
    D.AddPiece(set, 14, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.isnil(AB.CdmCustom.Totem(8177), "not timed from its slot")
    T.falsy(tostring(R.DrawnBy(14)):find("totem"), "its cooldown, not the totem's time: " .. tostring(R.DrawnBy(14)))
    T.falsy(Own.Track(14, set.pieces[14]) == "totem" or Own.Track(14, set.pieces[14]) == "both")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Tremor, Healing Stream, the Cleansing totems and Sentry put no buff on you: their
-- card offers Totem or Cooldown, not Buff only or the out-of-range line.
T.test("cdm card: a totem with no buff offers Totem or Cooldown (Tremor Totem)", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    stub.SetUnits({ player = { class = "SHAMAN" } })
    set = D.Current()
    AB.CdmSpells.SHAMAN = { { 8143, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 15 } }, { [0] = { 15 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
        return { spellID = 8143, selfAura = false, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    Own.Forget()
    D.AddPiece(set, 15, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(15, set.pieces[15]), "totem")
    local shown = {}
    for _, r in ipairs(Card.ROWS.show) do
        if r.item and r.item.key and r.show then shown[r.item.key] = r.show(set, 15, set.pieces[15]) and true or false end
    end
    T.truthy(shown["cdm.card.totemTrack"], "Totem or Cooldown")
    T.falsy(shown["cdm.card.buffTotemTrack"], "no Totem and buff")
    T.falsy(shown["cdm.card.track"], "no Buff only")
    for _, r in ipairs(Card.ROWS.show) do
        if r.head == DUI.L["Buff up"] or r.head == DUI.L["Buff missing"] then
            T.falsy(r.show(set, 15, set.pieces[15]), r.head .. ": no buff to show")
        end
    end
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Windfury Totem's buff is only on you in range of the totem. Its piece shows the
-- totem's time, grayed and dimmed, with the buff's own button over it in full color
-- while you have it, and the time over both.
T.test("cdm: a totem with a buff shows the totem's time, dimmed out of range of its buff (Windfury Totem)", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card, A = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard, AB.CdmAuras
    stub.SetUnits({ player = { class = "SHAMAN" } })
    set = D.Current()
    AB.CdmSpells.SHAMAN = { { 8512, 10613, 10614, aura = true }, { 3599, 6363, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 12 } }, { [0] = { 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
        return { spellID = 10614, selfAura = true, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    local function cast(sid) stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. sid, sid) end
    local function totemUpdate() stub.FireEvent("PLAYER_TOTEM_UPDATE", 4); stub.RunTimers() end
    Own.Forget()
    D.AddPiece(set, 12, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    -- Buff not taught yet: Totem and buff all the same, never dimmed.
    T.eq(Own.Track(12, set.pieces[12]), "both", "buff not known yet: Totem and buff")
    T.eq(R.DrawnBy(12), "totem and buff icon")
    T.falsy(Own.Frame(12).totemBuff, "nothing to cover it yet: no dim")
    -- A cast taught it (CdmOwn.LearnAura): the Windfury Totem aura, 8515.
    DUI.DB.Character().cdmAuraIDs = { [8512] = { [8515] = true } }
    Own.Forget()
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(12, set.pieces[12]), "both", "buff known: Totem and buff")
    T.eq(R.DrawnBy(12), "totem and buff icon")
    local icon = Own.Frame(12)
    T.truthy(icon.totem and icon.totemBuff)
    local holder = A.Frame(12)
    T.truthy(holder and holder:IsShown(), "the buff's button over the icon")
    T.truthy(A.SpellIDs(12)[8515], "it watches the taught aura")
    T.isnil(icon.Cooldown.__duration, "no totem: no time")
    T.eq(icon.Icon:GetAlpha(), 1, "no totem: full")
    -- Dropped: the totem's time, the icon dimmed under the buff's button, the time on top.
    stub.totems[4] = { spell = 10614, duration = {} }
    cast(10614); totemUpdate()
    T.eq(icon.Cooldown.__duration, stub.totems[4].duration, "dropped: the totem's time")
    T.eq(icon.Icon:GetAlpha(), Own.TOTEM_DIM, "dimmed: shows when the buff isn't covering it")
    T.truthy(icon.Cooldown:GetFrameLevel() > holder:GetFrameLevel(), "the time over the buff's button")
    -- Gone: full again.
    stub.totems[4] = nil
    totemUpdate()
    T.eq(icon.Icon:GetAlpha(), 1)
    -- The card offers Totem and buff, and the header says so.
    local shown
    for _, r in ipairs(Card.ROWS.show) do
        if r.item and r.item.key == "cdm.card.buffTotemTrack" then shown = r.show(set, 12, set.pieces[12]) end
        if r.item and r.item.key == "cdm.card.track" then
            T.falsy(r.show(set, 12, set.pieces[12]), "not the plain buff dropdown")
        end
    end
    T.truthy(shown, "What it shows: Totem and buff")
    -- Buff only: the game's aura alone. Cooldown: the game's icon.
    T.truthy(D.SetSpellValue(set, 12, "track", "buff"))
    T.eq(Own.Track(12, set.pieces[12]), "buff")
    T.truthy(D.SetSpellValue(set, 12, "track", "cooldown"))
    T.eq(Own.Track(12, set.pieces[12]), "cooldown")
    _G.GetSpellBaseCooldown = nil
    DUI.DB.Character().cdmAuraIDs = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Eureka! (a Gnome racial) gives a buff the game doesn't flag, so its card had no
-- What it shows choice.
T.test("cdm card: Eureka! can pick its buff", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    withCategories({ [0] = { 21 } }, { [0] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
        return { spellID = 1259812, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 120000 end
    Own.Forget()
    D.AddPiece(set, 21, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    local shown
    for _, r in ipairs(Card.ROWS.show) do
        if r.item and r.item.key == "cdm.card.track" then shown = r.show(set, 21, set.pieces[21]) end
    end
    T.truthy(shown, "What it shows is on its card")
    T.truthy(D.SetSpellValue(set, 21, "track", "buff"))
    T.eq(Own.Track(21, set.pieces[21]), "buff")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Bloodrage (filed by the game as a cooldown with no aura to show) had no
-- What it shows, Buff up or Buff missing rows, while Rend had them.
T.test("cdm card: a cooldown whose buff the game doesn't show has the buff rows (Bloodrage)", function()
    local DUI, AB, set, _, ess, icons = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "WARRIOR" } })
    set = D.Current()     -- the class is part of whose settings these are
    AB.CdmSpells.WARRIOR = { { 111, 1110, cd = true, aura = true }, { 112, cd = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    -- The game's buff icon 31 is the same spell's buff, under its other rank's id.
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 31 and 1110 or 100 + id, selfAura = true, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 60000 end
    Own.Forget()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 12, "icon", 48, 0)
    R.Refresh(); stub.RunTimers()
    local function row(key)
        for _, r in ipairs(Card.ROWS.show) do if r.item and r.item.key == key then return r end end
    end
    local function shows(id, key) return row(key).show(set, id, set.pieces[id]) end
    for _, key in ipairs({ "cdm.card.track", "cdm.card.buffUp", "cdm.card.missingGlow" }) do
        T.truthy(shows(11, key), key .. ": a cooldown with a buff")
    end
    T.truthy(shows(12, "cdm.card.track"), "a cooldown with no buff known can still pick")
    for _, key in ipairs({ "cdm.card.buffUp", "cdm.card.missingGlow" }) do
        T.falsy(shows(12, key), key .. ": a cooldown with none, left as a cooldown")
    end
    T.eq(Own.Track(11, set.pieces[11]), "cooldown", "left alone, what it always showed")
    T.isnil(Own.Track(12, set.pieces[12]), "left alone, a plain cooldown")
    T.eq(R.DrawnBy(11), "game", "left alone, the game's icon")
    -- Picked: its buff over its cooldown, watched for every rank.
    T.truthy(D.SetSpellValue(set, 11, "track", "both"))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura and cooldown icon")
    local ids = {}
    for k, v in pairs(AB.CdmAuras.Frame(11).containers[1].c.__groups.a.opts.candidateFilters.includeSpellIDs) do
        ids[v == true and k or v] = true
    end
    T.truthy(ids[111] and ids[1110], "every rank in the list")
    -- Only the buff.
    D.SetSpellValue(set, 11, "track", "buff")
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "aura icon")
    -- Unset again, a Buff row changes nothing about who draws it: it stays the
    -- game's cooldown icon, and the game's buff icon of the same spell says when
    -- the buff is up.
    set.pieces[11].track = nil
    icons[1]:SetIsActive(false)
    T.truthy(D.SetSpellValue(set, 11, "hideActive", true))
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(11, set.pieces[11]), "cooldown", "an option never changes what it shows")
    T.eq(R.DrawnBy(11), "game", "nor who draws it")
    T.eq(R.Tracked(11), true, "the game's buff icon answers for it")
    T.eq(ess[1]:GetAlpha(), 1, "buff down: the cooldown icon shows")
    stub.EnterCombat()
    icons[1]:SetIsActive(true); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 0, "Hide (Buff up): hidden while the buff is up, in a fight")
    icons[1]:SetIsActive(false); stub.RunTimers()
    T.eq(ess[1]:GetAlpha(), 1, "back as it ends")
    stub.LeaveCombat()
    D.SetSpellValue(set, 11, "hideActive", false)
    T.truthy(D.SetSpellValue(set, 11, "missingGlow", true))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(11), "game", "Glow (Buff missing) too")
    T.truthy(AB.CdmEffects.GlowShown(ess[1]), "the cooldown icon glows while the buff is missing")
    -- The game's own flag counts as well: it has an aura, flagged not to show it.
    D.SetSpellValue(set, 11, "missingGlow", false)
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 300 + id, selfAura = true, hasAura = id == 12, flags = 1 }
    end
    Own.Forget()
    T.truthy(shows(12, "cdm.card.track"), "hasAura with the HideAura flag")
    T.isnil(Own.Track(11, set.pieces[11]), "no aura by either word")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The spell ids a holder's first container watches.
local function watched(AB, id, shape)
    local h = shape == "bar" and AB.CdmBars.AuraFrame(id) or AB.CdmAuras.Frame(id)
    local out = {}
    local c = h and h.containers[1]
    for k, v in pairs(c and c.c.__groups.a.opts.candidateFilters.includeSpellIDs or {}) do
        out[v == true and k or v] = true
    end
    return out
end

-- Every spell can pick Cooldown, Buff only or Both, even one with no buff anyone
-- listed: its buff is watched by its own id until a cast teaches the real one.
T.test("cdm track: a cooldown with no buff known can still be set to its buff or both, icon and bar", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own, Card = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmCard
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 60000 end
    Own.Forget()
    D.AddPiece(set, 12, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(12), "game", "left alone, the game's cooldown icon")
    T.isnil(Own.Track(12, set.pieces[12]))
    T.truthy(D.SetSpellValue(set, 12, "track", "cooldown"))
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy(12), "game", "Cooldown is what it was: still the game's")
    for _, shape in ipairs({ "icon", "bar" }) do
        D.SetShape(set, 12, shape)
        T.truthy(D.SetSpellValue(set, 12, "track", "buff"))
        R.Refresh(); stub.RunTimers()
        T.eq(R.DrawnBy(12), shape == "bar" and "aura bar" or "aura icon", shape .. ": Buff only")
        T.truthy(watched(AB, 12, shape)[112], shape .. ": watched by its own id")
        T.truthy(D.SetSpellValue(set, 12, "track", "both"))
        R.Refresh(); stub.RunTimers()
        T.eq(R.DrawnBy(12), shape == "bar" and "aura and cooldown bar" or "aura and cooldown icon", shape .. ": Both")
    end
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Nothing lists every spell's buff, and a buff's id can differ from its spell's.
-- A cast where auras can be read finds it by id, else by the spell's name, and
-- keeps it per character.
T.test("cdm track: a placed spell's buff is learned from a cast, by name when its id differs", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    withCategories({ [0] = { 11, 12 } }, { [0] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = false }
    end
    _G.GetSpellBaseCooldown = function() return 60000 end
    Own.Forget()
    D.AddPiece(set, 12, "bar", 0, 0)
    R.Refresh(); stub.RunTimers()
    stub.SetUnits({ player = {}, target = { exists = true } })
    -- Your debuff on the target, under another id but the spell's name.
    stub.SetAuras("target", "HARMFUL", { { name = "Spell112", spellId = 9112, sourceUnit = "player", isFromPlayerOrPlayerPet = true } })
    -- Not placed: nothing learned.
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-0", 111); stub.RunTimers()
    T.isnil(Own.AuraOf(111), "a spell not placed")
    -- In a fight auras can't be read: nothing learned.
    stub.SetRestriction("PvPMatch", true)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 112); stub.RunTimers()
    T.isnil(Own.AuraOf(112), "auras secret: nothing read")
    stub.SetRestriction("PvPMatch", false)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 112); stub.RunTimers()
    T.truthy(Own.AuraOf(112) and Own.AuraOf(112)[9112], "found by name")
    T.truthy(DUI.DB.Character().cdmAuraIDs[112][9112], "kept for this character")
    -- What was seen only widens what a buff button watches. It never changes what
    -- the spell shows or who draws it.
    T.falsy(Own.QuietAura(12), "the game's data still knows no buff for it")
    T.isnil(Own.Track(12, set.pieces[12]), "left alone it stays a plain cooldown")
    for _, shape in ipairs({ "bar", "icon" }) do
        D.SetShape(set, 12, shape)
        T.truthy(D.SetSpellValue(set, 12, "track", "both"))
        R.Refresh(); stub.RunTimers()
        T.eq(R.DrawnBy(12), shape == "bar" and "aura and cooldown bar" or "aura and cooldown icon", shape .. ": Both")
        local ids = watched(AB, 12, shape)
        T.truthy(ids[9112] and ids[112], shape .. ": the learned id watched as well as its own")
    end
    -- Someone else's debuff of that name teaches nothing.
    D.AddPiece(set, 11, "icon", 0, -48)
    stub.SetAuras("target", "HARMFUL", { { name = "Spell111", spellId = 9111, sourceUnit = "party1", isFromPlayerOrPlayerPet = false } })
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 111); stub.RunTimers()
    T.isnil(Own.AuraOf(111), "not yours")
    -- A buff on you under the cast's own id.
    stub.SetAuras("player", "HELPFUL", { { name = "Spell111", spellId = 111 } })
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 111); stub.RunTimers()
    T.truthy(Own.AuraOf(111) and Own.AuraOf(111)[111], "found by id")
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Strength of Earth Totem puts up Strength of Earth: no id and no name in common,
-- so its buff was never learned and the piece never got Totem and buff.
T.test("cdm track: a totem's buff is learned by its name without the word Totem", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    stub.SetUnits({ player = { class = "SHAMAN" } })
    set = D.Current()
    AB.CdmSpells.SHAMAN = { { 8075, 8160, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 13 } }, { [0] = { 13 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
        return { spellID = 8075, selfAura = true, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    local realName = C_Spell.GetSpellName
    C_Spell.GetSpellName = function(id)
        if id == 8075 or id == 8160 then return "Strength of Earth Totem" end
        return realName(id)
    end
    Own.Forget()
    D.AddPiece(set, 13, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track(13, set.pieces[13]), "both", "Totem and buff before its buff is known")
    stub.SetAuras("player", "HELPFUL", { { name = "Strength of Earth", spellId = 8076 } })
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-soe", 8075); stub.RunTimers()
    T.truthy(Own.AuraOf(8075) and Own.AuraOf(8075)[8076], "found as Strength of Earth")
    T.truthy(AB.CdmCustom.TotemBuffKnown(8075), "now it dims out of range")
    C_Spell.GetSpellName = realName
    _G.GetSpellBaseCooldown = nil
    DUI.DB.Character().cdmAuraIDs = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A totem first dropped in a fight: auras can't be read there, so its buff is
-- looked up as the fight ends while the totem still stands, and the piece dims
-- out of range from then on, that same totem included.
T.test("cdm track: a totem dropped in a fight learns its buff when the fight ends", function()
    local DUI, AB, set = barsWorld()
    local D, R, Own = AB.CdmData, AB.CdmRows, AB.CdmOwn
    stub.SetUnits({ player = { class = "SHAMAN" } })
    set = D.Current()
    AB.CdmSpells.SHAMAN = { { 8075, 8160, aura = true }, { 8071, aura = true } }
    AB.CdmCustom.Forget()
    withCategories({ [0] = { 13 } }, { [0] = { 13 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function()
        return { spellID = 8075, selfAura = true, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    local realName = C_Spell.GetSpellName
    C_Spell.GetSpellName = function(id)
        if id == 8075 or id == 8160 then return "Strength of Earth Totem" end
        return realName(id)
    end
    Own.Forget()
    D.AddPiece(set, 13, "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    stub.SetAuras("player", "HELPFUL", { { name = "Strength of Earth", spellId = 8076 } })
    -- Dropped in a fight, then the totem gone before it ends: nothing learned.
    stub.EnterCombat()
    stub.totems[2] = { spell = 8075, duration = {} }
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8075)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 2); stub.RunTimers()
    T.isnil(Own.AuraOf(8075), "in a fight: not read")
    stub.totems[2] = nil
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 2)
    stub.LeaveCombat(); stub.RunTimers()
    T.isnil(Own.AuraOf(8075), "gone by the end of the fight: nothing to read")
    -- Dropped in a fight and still standing when it ends: learned then.
    stub.EnterCombat()
    stub.totems[2] = { spell = 8075, duration = {} }
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 8075)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 2); stub.RunTimers()
    T.isnil(Own.AuraOf(8075), "still in the fight")
    T.falsy(Own.Frame(13).totemBuff, "no dim yet")
    stub.LeaveCombat(); stub.RunTimers()
    T.truthy(Own.AuraOf(8075) and Own.AuraOf(8075)[8076], "learned as the fight ended")
    T.truthy(Own.Frame(13).totemBuff, "and the piece dims out of range from now on")
    T.eq(Own.Frame(13).Icon:GetAlpha(), Own.TOTEM_DIM, "this same totem included")
    C_Spell.GetSpellName = realName
    _G.GetSpellBaseCooldown = nil
    DUI.DB.Character().cdmAuraIDs = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Rend as a bar with Background color "Solid color" black: the empty bar stayed light gray.
T.test("cdm bars: an aura bar's empty part takes the background color (the spell's or its group's)", function()
    local DUI, AB, set = barsWorld()
    local D, CD = AB.CdmData, AB.Cooldowns
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function() return 0 end
    place(D, set, 11, 1)
    D.SetSpellValue(set, 11, "backMode", "solid")
    D.SetSpellValue(set, 11, "backColor", { 0.1, 0.2, 0.3, 0.9 })
    pass(AB)
    local h = AB.CdmBars.AuraFrame(11)
    T.eq(h.Bar:GetValue(), 0, "empty: the background is what shows")
    local p = CD.Parts(h)
    T.truthy(p and p.back, "the bar's backdrop")
    T.rgb({ p.back:GetVertexColor() }, { 0.1, 0.2, 0.3 }, "the spell's own")
    T.near(select(4, p.back:GetVertexColor()), 0.9)
    -- "Same as its group" uses the group's color (Look tab, Whole group).
    D.SetSpellValue(set, 11, "backMode", "block")
    D.SetLook(set, 11, "back", "solid", true)
    D.SetLook(set, 11, "backColor", { 0.5, 0, 0, 1 }, true)
    pass(AB)
    T.rgb({ p.back:GetVertexColor() }, { 0.5, 0, 0 }, "the group's")
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The on-screen editor (CdmEditor)

-- The rows world with the editor open on talent set 1.
local function edWorld()
    local DUI, AB, ess, bars = rowsWorld()
    withCategories({ [0] = { 11, 12, 13 }, [3] = { 21, 22 } }, { [0] = { 11, 12, 13, 14 }, [3] = { 21, 22 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local names = {}
    _G.C_Spell.GetSpellName = function(sid) return names[sid] or ("Spell " .. sid) end
    -- The addon's own spell list starts empty; tests that need it fill it (customTray).
    for k in pairs(AB.CdmSpells) do AB.CdmSpells[k] = {} end
    AB.CdmCustom.Forget()
    local Ed = AB.CdmEditor
    T.truthy(Ed.Open(), "opens out of combat")
    return DUI, AB, Ed, AB.CdmData, ess, bars
end

T.test("cdm card: the glow Style row plays each style on the spell in the editor, then rests", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card, Fx = D.Current(), AB.CdmCard, AB.CdmEffects
    D.AddChain(set, { 11 }, "icon", 0, 0)
    Ed.Changed()
    Ed.Select(11)
    local style
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == "cdm.card.glowStyle" then style = r.item end end
    T.truthy(style and style.hover, "the row previews on hover")
    local f = Ed.PreviewOf(11)
    style.hover("twinkle")
    local host = Fx.PreviewHost(f)
    T.truthy(host.glowDriver:IsShown(), "the lights run on the spell's preview")
    T.eq(host.glowStyle, "twinkle")
    style.hover("ring")
    T.truthy(Fx.GlowShown(f), "the ring for Ring")
    for _ = 1, 5 do stub.RunOnUpdate(DUI.Motion.Driver(), 0.1) end
    T.falsy(host.glowDriver:IsShown(), "the lights give way to it")
    stub.RunTimers(Fx.PREVIEW_HOLD + 0.1)
    T.falsy(Fx.GlowShown(f), "a preview rests after a moment")
end)

-- A player's paladin: checking Reverse on the swipe showed in game but not on the
-- spell in the editor. Every Look row the card offers has to show on the preview.
local function lookRow(Card, key)
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == key then return r.item end end
end
T.test("cdm card: the editor's preview follows every Look row, icon and bar", function()
    -- The client's countdown text and its switch, lent here: the fake game has neither.
    local make = CreateFrame
    CreateFrame = function(kind, ...)
        local fr = make(kind, ...)
        if kind == "Cooldown" then
            local fs = fr:CreateFontString(nil, "OVERLAY")
            function fr:GetCountdownFontString() return fs end
            function fr:SetHideCountdownNumbers(v) self.__noNumbers = v == true end
        end
        return fr
    end
    local DUI, AB, Ed, D = edWorld()
    local set, Card = D.Current(), AB.CdmCard
    D.AddChain(set, { 11 }, "icon", 0, 0)
    D.AddChain(set, { 12 }, "bar", 0, -200)
    Ed.Changed()
    Ed.Select(11)
    local f = Ed.PreviewOf(11)
    T.falsy(f.cd:GetReverse(), "not reversed yet")
    lookRow(Card, "cdm.card.reverse").set(true)
    T.truthy(f.cd:GetReverse(), "Reverse shows on the preview")
    lookRow(Card, "cdm.card.noSwipe").set(true)
    T.falsy(f.cd:GetDrawSwipe(), "Hide on cooldown takes the swipe off")
    lookRow(Card, "cdm.card.noSwipe").set(false)
    T.truthy(f.cd:GetDrawSwipe(), "and back")
    lookRow(Card, "cdm.card.cdNumbers").set(false)
    T.truthy(f.cd.__noNumbers, "cooldown numbers off")
    lookRow(Card, "cdm.card.cdNumbers").set(true)
    T.falsy(f.cd.__noNumbers, "and on")
    lookRow(Card, "cdm.card.cdSize").set(21)
    local fs = f.cd:GetCountdownFontString()
    T.eq(select(2, fs:GetFont()), 21, "their size")
    lookRow(Card, "cdm.card.cdColor").set({ 0.1, 0.2, 0.3 })
    T.near((fs:GetTextColor()), 0.1, 0.001, "their color")
    -- Almost ready: the sample's numbers turn for its last seconds.
    lookRow(Card, "cdm.card.low").set(true)
    lookRow(Card, "cdm.card.lowAt").set(10)
    lookRow(Card, "cdm.card.lowColor").set({ 0.9, 0.1, 0.1 })
    local sawLow
    for _ = 1, 400 do
        stub.Advance(0.1); stub.RunTickers()
        if math.abs((fs:GetTextColor()) - 0.9) < 0.001 then sawLow = true; break end
    end
    T.truthy(sawLow, "the almost ready color shows on the sample")
    -- The bar's fill and background, its own and its group's.
    Ed.Select(12)
    local b = Ed.PreviewOf(12)
    lookRow(Card, "cdm.card.barMode").set("solid")
    lookRow(Card, "cdm.card.barColor").set({ 0.2, 0.6, 0.4 })
    local c = b.bar.__barColor
    T.truthy(c and math.abs(c[1] - 0.2) < 0.001 and math.abs(c[2] - 0.6) < 0.001, "the spell's own fill color")
    lookRow(Card, "cdm.card.backMode").set("solid")
    lookRow(Card, "cdm.card.backColor").set({ 0.5, 0.1, 0.7, 0.8 })
    local back = DUI.Style.BarBack(b.bar)
    local r, g, bl = back:GetVertexColor()
    T.near(r, 0.5, 0.001, "the spell's own background"); T.near(bl, 0.7, 0.001)
    CreateFrame = make
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: Move back and Move forward trade places with the spell beside it", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card = D.Current(), AB.CdmCard
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    Ed.Changed()
    local function row(key)
        for _, r in ipairs(Card.ROWS.chain) do if r.item and r.item.key == key then return r end end
    end
    local back, fwd = row("cdm.card.back"), row("cdm.card.forward")
    Ed.Select(11)
    Card.SetTab("chain")
    T.truthy(back.show(set, 11, set.pieces[11]), "both always there, side by side")
    T.truthy(back.item.disabled(), "the first can't go back: grayed")
    T.falsy(fwd.item.disabled())
    local b = back.frame
    T.truthy(b:IsShown() and fwd.frame:IsShown(), "on the Group tab")
    T.falsy(b:IsEnabled(), "grayed button")
    T.eq(select(5, fwd.frame:GetPoint(1)), select(5, b:GetPoint(1)), "one line")
    fwd.item.func()
    T.eq(D.Root(set, 13), 12, "11 moved forward: 12 leads")
    T.eq(set.pieces[11].parent, 12)
    T.eq(Ed.Selected(), 11, "still picked, to keep moving it")
    fwd.item.func()
    T.eq(set.pieces[11].parent, 13, "last now")
    T.truthy(fwd.item.disabled(), "nothing after it")
    back.item.func()
    T.eq(set.pieces[11].parent, 12, "back one")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: Form or stance lists the class's own forms, each a switch on by default", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card = D.Current(), AB.CdmCard
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "DRUID"
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Select(11)
    local rows = {}
    for _, r in ipairs(Card.ROWS.show) do if r.item then rows[r.item.key] = r end end
    local p = set.pieces[11]
    local cat, battle = rows["cdm.card.hideInCat"], rows["cdm.card.hideInBattle"]
    T.truthy(cat and cat.show(set, 11, p), "a druid: Cat Form")
    T.falsy(battle.show(set, 11, p), "no warrior stances for a druid")
    T.eq(cat.item.get(), true, "on by default: shown in it")
    cat.item.set(false)
    T.eq(set.pieces[11].hideInCat, true, "off: left out of Cat Form")
    cat.item.set(true)
    T.isnil(set.pieces[11].hideInCat, "back on: nothing saved")
    stub.units.player.class = "PRIEST"
    T.falsy(cat.show(set, 11, p), "a class with no forms: no rows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's Evasion and Sprint bars never showed: both stealth switches were
-- off, saved while they were cooldowns, and once they showed their buff the
-- card hid the rows that still hid them.
T.test("cdm card: Form or stance shows on a buff too, so what hides it can be undone", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card = D.Current(), AB.CdmCard
    stub.units.player = stub.units.player or { name = "Tester" }
    stub.units.player.class = "ROGUE"
    D.AddPiece(set, 11, "bar", 0, 0)
    local p = set.pieces[11]
    p.track, p.hideInStealth, p.hideInUnstealthed = "buff", true, true
    Ed.Select(11)
    T.eq(AB.CdmOwn.Track(11, p), "buff", "the piece shows its buff")
    local rows, head = {}, nil
    for _, r in ipairs(Card.ROWS.show) do
        if r.item then rows[r.item.key] = r end
        if r.head == DUI.L["Form or stance"] then head = r end
    end
    T.truthy(head.show(set, 11, p), "the heading")
    local out, stealth = rows["cdm.card.hideInUnstealthed"], rows["cdm.card.hideInStealth"]
    T.truthy(out.show(set, 11, p) and stealth.show(set, 11, p), "both stealth switches, to turn back on")
    T.eq(stealth.item.get(), false, "it reads off, as saved")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: each moment has its sound row, and its list opens with headings and plays a pick", function()
    local DUI, AB, Ed, D = edWorld()
    local set, Card, W = D.Current(), AB.CdmCard, DUI.Widgets
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Select(11)
    local rows = {}
    for _, r in ipairs(Card.ROWS.show) do
        if r.item then rows[r.item.key] = r end
    end
    local p = set.pieces[11]
    T.truthy(rows["cdm.card.readySound"].show(set, 11, p), "a cooldown: When ready has a sound")
    T.truthy(rows["cdm.card.usableSound"].show(set, 11, p), "Usable or proc too")
    T.falsy(rows["cdm.card.buffSound"].show(set, 11, p), "no buff, no buff sound")
    local item = rows["cdm.card.readySound"].item
    T.eq(item.get(), "none", "silent until picked")
    local row = CreateFrame("Frame", nil, UIParent)
    W.dropdown(row, { id = "cdm.card", scope = "ActionBars" }, item)
    row.control:Click()
    T.eq(W.menuOwner, row.control, "the list opens")
    W.CloseMenu()
    local heard = {}
    local alert = DUI.Sound.Alert
    DUI.Sound.Alert = function(key) heard[#heard + 1] = key; alert(key) end
    item.set("dui:quest")
    item.onPick("dui:quest")
    stub.RunTimers(1)
    T.eq(p.readySound, "dui:quest", "saved on the piece")
    T.eq(item.get(), "dui:quest")
    T.deq(heard, { "dui:quest" }, "heard once as it's picked")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: the sound list plays a row the mouse rests on, and the pick, through its real rows", function()
    local DUI, AB, Ed, D = edWorld()
    local set, W = D.Current(), DUI.Widgets
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Select(11)
    DUI.Sound.ALERT_PUNCHY = {}   -- the addon's own sounds in the rows W.MenuRow shows, without scrolling
    local item
    for _, r in ipairs(AB.CdmCard.ROWS.show) do
        if r.item and r.item.key == "cdm.card.readySound" then item = r.item end
    end
    local row = CreateFrame("Frame", nil, UIParent)
    W.dropdown(row, { id = "cdm.card", scope = "ActionBars" }, item)
    local played, stopped = {}, {}
    _G.PlaySoundFile = function(file) played[#played + 1] = file; return true, #played end
    _G.StopSound = function(h) stopped[#stopped + 1] = h end
    local function hover(key)
        local menuRow = visibleMenuRowOf(W, key)
        menuRow:GetScript("OnEnter")(menuRow)
    end
    local FILES = DUI.Sound.FILES
    row.control:Click()
    hover("none"); stub.RunTimers()
    hover("head:own"); stub.RunTimers()
    T.eq(#played, 0, "None and a heading have nothing to hear")
    hover("dui:quest")
    hover("dui:done")
    hover("dui:apply")
    stub.RunTimers()
    T.deq(played, { FILES.apply }, "a sweeping mouse: only where it rests")
    hover("dui:done"); stub.RunTimers()
    T.deq(played, { FILES.apply, FILES.done })
    T.deq(stopped, { 1 }, "the last one is cut off")
    T.isnil(set.pieces[11].readySound, "hovering saves nothing")
    visibleMenuRowOf(W, "dui:quest"):Click()
    stub.RunTimers()
    T.eq(set.pieces[11].readySound, "dui:quest", "a real click saves it")
    T.eq(played[#played], FILES.quest, "and plays it")
    _G.StopSound = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: open hides the live layout behind previews; Done brings it back", function()
    local DUI, AB, Ed, D, ess = edWorld()
    D.AddChain(D.Current(), { 11, 12 }, "icon", 0, 0)
    Ed.Changed(); stub.RunTimers()
    T.truthy(_G.DaylightUICdmEditor:IsShown())
    T.eq(ess[1]:GetAlpha(), 0, "the game's item steps aside")
    T.truthy(AB.CdmRows.editing)
    Ed.Close(); stub.RunTimers()
    T.falsy(_G.DaylightUICdmEditor:IsShown())
    T.eq(ess[1]:GetAlpha(), 1, "back")
    stub.EnterCombat()
    T.falsy(Ed.Open(), "not in combat")
    stub.LeaveCombat()
    Ed.Open()
    stub.EnterCombat()
    T.falsy(Ed.IsOpen(), "a fight closes it")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm switched off: the game's Cooldown Manager and its /cdm are left alone", function()
    local gameOpened = false
    loadWorld({ actionbars = true, login = false, before = function()
        fakeRegistry()
        fakeViewer("EssentialCooldownViewer", { 11, 12 })
        _G.SLASH_COOLDOWNVIEWER1 = "/cdm"
        _G.SlashCmdList.COOLDOWNVIEWER = function() gameOpened = true end
    end })
    local mods = DaylightUIDB.profileData[DaylightUI.DB.DEFAULT].modules
    mods.ActionBars = mods.ActionBars or {}
    mods.ActionBars.cooldowns = false
    stub.FireEvent("PLAYER_LOGIN")
    local AB = stub.actionbars
    T.falsy(AB.Cooldowns.enabled, "never started")
    SlashCmdList.COOLDOWNVIEWER("")
    T.truthy(gameOpened, "/cdm is still the game's")
    T.falsy(AB.CdmEditor.Open(), "the editor stays shut")
    T.truthy(stub.ChatContains("switch it on"), "and says why")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a bar preview follows its Show name and Name position", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddPiece(set, 21, "bar", 0, 0)
    Ed.Changed(); stub.RunTimers()
    local f
    for _, c in ipairs(stub.Children(Ed.Overlay())) do if c.id == 21 then f = c end end
    T.truthy(f, "the preview piece")
    T.eq(select(1, f.name:GetPoint(1)), "LEFT", "left by default")
    T.eq(f.name:GetAlpha(), 1)
    T.truthy(D.SetSpellValue(set, 21, "nameAlign", "center"))
    Ed.Changed(); stub.RunTimers()
    T.eq(select(1, f.name:GetPoint(1)), "CENTER", "centred")
    T.eq(f.name:GetJustifyH(), "CENTER")
    T.truthy(D.SetSpellValue(set, 21, "nameAlign", "left"))
    T.truthy(D.SetSpellValue(set, 21, "showName", false))
    Ed.Changed(); stub.RunTimers()
    T.eq(select(1, f.name:GetPoint(1)), "LEFT", "back on the left")
    T.eq(f.name:GetAlpha(), 0, "hidden")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the tray lists every spell once, placed ones marked, other talents on a switch", function()
    local DUI, AB, Ed, D = edWorld()
    D.AddPiece(D.Current(), 12, "icon", 0, 0)
    local ids, placed = {}, {}
    for _, e in ipairs(Ed.Spells()) do ids[#ids + 1] = e.id; placed[e.id] = e.placed end
    T.deq(ids, { 11, 12, 13, 21, 22, "mainhand", "offhand" })
    T.truthy(placed[12]); T.falsy(placed[11])
    Ed.SetShowUnlearned(true)
    local last = Ed.Spells()[8]
    T.eq(last.id, 14); T.truthy(last.unlearned)
    Ed.SetQuery("spell 113")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's cooldown list also holds items with no spell (CooldownViewerItemData.lua):
-- an equipment slot (trinkets) or a spell category (potions, healthstones).
T.test("cdm editor: a trinket slot or potion cooldown shows its item's or the game's name and icon", function()
    local DUI, AB, Ed, D = edWorld()
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        if id == 12 then return { equipSlot = 13, linkedSpellIDs = {} } end
        if id == 13 then return { spellCategoryID = 30, linkedSpellIDs = {} } end
        return { spellID = 100 + id }
    end
    local oldID, oldItem = _G.GetInventoryItemID, _G.C_Item
    _G.GetInventoryItemID = function(_, slot) return slot == 13 and 5000 or nil end
    _G.C_Item = setmetatable({ GetItemNameByID = function(item) return item == 5000 and "Lucky Charm" or nil end },
        { __index = oldItem })
    T.eq(Ed.SpellName(12), "Lucky Charm")
    T.eq(Ed.SpellTexture(12), "tex:13", "the equipped item's icon")
    T.truthy(Ed.SpellName(13), "a potion has a name")
    T.eq(Ed.SpellTexture(13), "Interface/ICONS/INV_POTION_54", "the game's potion icon")
    local names = {}
    for _, e in ipairs(Ed.Spells()) do names[e.id] = e.name end
    T.eq(names[12], "Lucky Charm"); T.truthy(names[13] ~= "", "listed with a name")
    -- Empty trinket slots used to show as "?" on every character.
    _G.GetInventoryItemID = function() return nil end
    local listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.falsy(listed[12], "an empty trinket slot isn't in the tray")
    T.truthy(listed[13], "a potion has no slot: still listed")
    D.AddPiece(D.Current(), 12, "icon", 0, 0)
    listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.truthy(listed[12], "a placed one stays, so it can be removed")
    _G.GetInventoryItemID, _G.C_Item = oldID, oldItem
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Three "Unknown spell" cooldowns with "?" icons showed in the tray. The game names
-- an entry by its tooltip override, then its override, then its base spell
-- (GetSpellID in CooldownViewerItemData.lua). One with no name and no icon is nothing to pick.
T.test("cdm editor: a cooldown named by its override spell; one with no name or icon isn't in the tray", function()
    local DUI, AB, Ed, D = edWorld()
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        if id == 11 then return { spellID = 999, overrideSpellID = 111, linkedSpellIDs = {} } end
        if id == 12 then return { spellID = 998, linkedSpellIDs = {} } end
        if id == 13 then return { spellID = 997, overrideTooltipSpellID = 113, overrideSpellID = 996, linkedSpellIDs = {} } end
        return { spellID = 100 + id }
    end
    local old = _G.C_Spell
    local gone = { [999] = true, [998] = true, [997] = true, [996] = true }
    _G.C_Spell = setmetatable({
        GetSpellName = function(sid) if not gone[sid] then return old.GetSpellName(sid) end end,
        GetSpellTexture = function(sid) if not gone[sid] then return old.GetSpellTexture(sid) end end,
    }, { __index = old })
    T.eq(Ed.SpellName(11), old.GetSpellName(111), "the override spell's name")
    T.eq(Ed.SpellTexture(11), old.GetSpellTexture(111), "and its icon")
    T.eq(Ed.SpellName(13), old.GetSpellName(113), "the tooltip override first, as the game")
    local listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.truthy(listed[11]); T.truthy(listed[13])
    T.falsy(listed[12], "no name, no icon: not in the tray")
    D.AddPiece(D.Current(), 12, "icon", 0, 0)
    listed = {}
    for _, e in ipairs(Ed.Spells()) do listed[e.id] = true end
    T.truthy(listed[12], "a placed one stays, so it can be removed")
    _G.C_Spell = old
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: click a tray spell, pick a shape: it lands free and picked; a placed one is picked", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Choose(21)
    T.eq(Ed.Pending().kind, "bar", "the game's shape known")
    Ed.Pick("icon")
    local p = D.Current().pieces[21]
    T.eq(p.shape, "icon"); T.truthy(p.x and p.y)
    T.eq(Ed.Selected(), 21)
    T.isnil(Ed.Pending())
    Ed.Choose(11); Ed.Pick("bar")
    local b11, b21 = D.Layout(D.Current())[11], D.Layout(D.Current())[21]
    T.truthy(b11.x >= b21.x + b21.w or b11.y - b11.h >= b21.y or b21.y - b21.h >= b11.y, "a free spot, not on top")
    Ed.Choose(21)
    T.isnil(Ed.Pending(), "placed: no chooser")
    T.eq(Ed.Selected(), 21)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: + on a side, then a spell: it hangs off that side", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Choose(11); Ed.Pick("icon")
    Ed.SetAttach(11, "down")
    T.deq(Ed.Attach(), { id = 11, side = "down" })
    Ed.Choose(21); Ed.Pick("bar")
    local p = D.Current().pieces[21]
    T.eq(p.parent, 11); T.eq(p.side, "down"); T.eq(p.align, "start")
    T.isnil(Ed.Attach())
    Ed.SetAttach(11, "right"); Ed.Choose(12); Ed.Pick("icon")
    T.eq(D.Current().pieces[12].align, "center", "beside, same shape: centered")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: drag moves a chain, drops near a side to hook, drags off to unhook", function()
    local DUI, AB, Ed, D = edWorld()
    DUI:Set("general", "gridSnap", false)    -- the grid has its own test
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    D.AddPiece(set, 13, "icon", 300, 0)
    Ed.Changed()
    -- A press that doesn't move is a click.
    Ed.StartDrag(11, 10, -10); Ed.DragTo(11, -11); Ed.Drop()
    T.eq(Ed.Selected(), 11); T.eq(set.pieces[11].x, 0)
    -- The chain moves with its first piece.
    Ed.StartDrag(11, 10, -10); Ed.DragTo(110, -60); Ed.Drop()
    T.eq(set.pieces[11].x, 100); T.eq(set.pieces[11].y, -50)
    T.eq(D.Layout(set)[12].x, 140, "12 came along")
    -- 13 dropped right beside 12 stays free: only a + makes a group.
    Ed.StartDrag(13, 300, 0); Ed.DragTo(184, -50); Ed.Drop()
    T.isnil(set.pieces[13].parent, "never joined by a drag")
    -- 12 dragged: the whole group moves, still a group, 12 picked.
    local before = set.pieces[11].y
    Ed.StartDrag(12, 150, -60); Ed.DragTo(150, -360); Ed.Drop()
    T.eq(set.pieces[12].parent, 11, "never split by a drag")
    T.eq(set.pieces[11].y, before - 300)
    T.eq(Ed.Selected(), 12)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a tray spell dragged up asks its shape and lands centered where it was dropped", function()
    local DUI, AB, Ed, D = edWorld()
    DUI:Set("general", "gridSnap", false)    -- the grid has its own test
    Ed.StartTrayDrag(11, 0, -400); Ed.DragTo(50, 100); Ed.Drop(false)
    T.eq(Ed.Pending().id, 11)
    Ed.Pick("icon")
    local p = D.Current().pieces[11]
    T.eq(p.x, 32); T.eq(p.y, 118)
    Ed.StartTrayDrag(12, 0, -400); Ed.DragTo(0, -300); Ed.Drop(true)
    T.isnil(Ed.Pending(), "dropped back on the tray: called off")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A piece dropped under the tray could never be picked again, because the tray
-- sat over it and didn't move.
T.test("cdm editor: the tray drags out of the way, stays on screen, keeps its spot; a moving piece sees through it", function()
    local DUI, AB, Ed, D = edWorld()
    local tray = Ed.Tray()
    local function at() local _, _, _, x, y = tray:GetPoint(1); return { x, y } end
    T.deq(at(), { 0, Ed.TRAY_EDGE }, "first at the bottom")
    Ed.StartTrayMove(0, -520); Ed.MoveTray(100, -100); Ed.EndTrayMove()
    T.deq(at(), { 100, Ed.TRAY_EDGE + 420 })
    Ed.MoveTray(900, 900)
    T.deq(at(), { 100, Ed.TRAY_EDGE + 420 }, "let go: a move does nothing")
    -- Kept whole on the screen.
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    Ed.StartTrayMove(0, 0); Ed.MoveTray(5000, 5000); Ed.EndTrayMove()
    T.deq(at(), { (sw - tray:GetWidth()) / 2, sh - tray:GetHeight() })
    Ed.StartTrayMove(0, 0); Ed.MoveTray(-9000, -9000); Ed.EndTrayMove()
    T.deq(at(), { -(sw - tray:GetWidth()) / 2, 0 })
    -- Remembered for the next open.
    Ed.StartTrayMove(0, 0); Ed.MoveTray(-200, 300); Ed.EndTrayMove()
    local keep = at()
    Ed.Close(); Ed.Open()
    T.deq(at(), keep)
    T.deq(DUI.DB.Root().cdmTray, { x = keep[1], y = keep[2] })
    -- A piece on the move: the tray, title and banner turn see-through.
    D.AddPiece(D.Current(), 11, "icon", 0, 0)
    Ed.Changed()
    Ed.StartDrag(11, 10, -10); Ed.DragTo(60, -400)
    T.eq(tray:GetAlpha(), Ed.FADED)
    Ed.Drop()
    T.eq(tray:GetAlpha(), 1)
    -- A tray spell carried up keeps the tray solid (dropping back calls it off).
    Ed.StartTrayDrag(12, 0, -400); Ed.DragTo(0, -300)
    T.eq(tray:GetAlpha(), 1)
    Ed.Drop(true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: Delete removes the picked piece, Escape steps back then closes", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Choose(11); Ed.Pick("icon")
    local key = _G.DaylightUICdmEditor:GetScript("OnKeyDown")
    key(_G.DaylightUICdmEditor, "DELETE")
    T.isnil(D.Current().pieces[11]); T.isnil(Ed.Selected())
    Ed.Choose(12)
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.isnil(Ed.Pending()); T.truthy(Ed.IsOpen(), "first the chooser")
    Ed.Choose(12); Ed.Pick("icon"); Ed.SetAttach(12, "up")
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.isnil(Ed.Attach()); T.truthy(Ed.IsOpen(), "then the waiting +")
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.isnil(Ed.Selected()); T.truthy(Ed.IsOpen(), "then the picked piece (its card)")
    key(_G.DaylightUICdmEditor, "ESCAPE")
    T.falsy(Ed.IsOpen(), "then Done")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: the card's setters check, clamp, and drop a value that's the same as what it falls back to", function()
    local D = data()
    local set = filled(D)
    D.AddPiece(set, 21, "bar", 0, -100)
    -- an icon's own size is the piece's size, and setting the chain's size removes it
    T.truthy(D.SetLook(set, 12, "size", 100))
    T.eq(set.pieces[12].size, 64, "clamped")
    T.eq(D.Layout(set)[12].w, 64)
    T.truthy(D.SetLook(set, 12, "size", 36))
    T.isnil(set.pieces[12].size, "same as the chain: gone")
    -- for the whole chain, every piece's own value of that key goes
    D.SetLook(set, 13, "size", 20)
    T.truthy(D.SetLook(set, 11, "size", 30, true))
    T.eq(set.chains[11].look.size, 30); T.isnil(set.pieces[13].size)
    T.eq(D.Layout(set)[13].w, 30)
    -- a switch off stays off
    T.truthy(D.SetLook(set, 21, "time", false))
    T.eq(set.pieces[21].look.time, false)
    T.falsy(D.SetLook(set, 21, "time", "yes"), "not a switch value")
    T.falsy(D.SetLook(set, 21, "nope", 1))
    -- spacing: every piece's own gaps go
    set.pieces[12].gap = 9
    T.truthy(D.SetChainValue(set, 11, "spacing", 10))
    T.isnil(set.pieces[12].gap)
    T.eq(D.Layout(set)[12].x, 40, "30 + 10")
    T.truthy(D.SetChainValue(set, 12, "spacing", 4))
    T.isnil(set.chains[11].spacing, "the default: gone")
    T.falsy(D.SetChainValue(set, 11, "grow", "sideways"))
    -- a hooked piece's line-up and gap (a free one has none)
    T.truthy(D.SetHookValue(set, 12, "gap", 12))
    T.eq(set.pieces[12].gap, 12)
    T.truthy(D.SetHookValue(set, 12, "align", "end"))
    T.falsy(D.SetHookValue(set, 11, "gap", 2), "not hooked")
    -- spell options: the piece's shape decides, and defaults are dropped
    T.falsy(D.SetSpellValue(set, 11, "showName", false), "bars only")
    T.truthy(D.SetSpellValue(set, 21, "showName", false))
    T.eq(set.pieces[21].showName, false)
    T.truthy(D.SetSpellValue(set, 11, "onCd", "fade"))
    T.truthy(D.SetSpellValue(set, 11, "cdAlpha", 5))
    T.eq(set.pieces[11].cdAlpha, 1)
    T.truthy(D.SetSpellValue(set, 11, "onCd", "show"))
    T.isnil(set.pieces[11].onCd)
    T.truthy(D.SetShape(set, 11, "bar"))
    T.eq(set.pieces[11].shape, "bar")
    T.falsy(D.SetShape(set, 11, "round"))
end)

T.test("cdm editor: a picked piece gets the card beside its chain; its rows write the piece", function()
    local DUI, AB, Ed, D = edWorld()
    local Card = AB.CdmCard
    Ed.Choose(11); Ed.Pick("icon")
    T.truthy(Card.Shown(), "picked on add: the card is up")
    -- every tab draws for an icon and a bar
    for _, shape in ipairs({ "icon", "bar" }) do
        D.SetShape(D.Current(), 11, shape); Ed.Changed()
        for _, t in ipairs(Card.TABS) do Card.SetTab(t) end
    end
    Card.SetTab("look")
    -- the rows' items read and write the picked piece
    local function item(t, key)
        for _, r in ipairs(Card.ROWS[t]) do if r.item and r.item.key == key then return r.item end end
    end
    item("look", "cdm.card.width").set(300)
    T.eq(D.Current().pieces[11].look.width, 300)
    T.eq(item("look", "cdm.card.width").get(), 300)
    item("chain", "cdm.card.chain.combat").set(true)
    T.eq(D.Current().chains[11].combat, true)
    item("show", "cdm.card.readyGlow").set(true)
    T.eq(D.Current().pieces[11].readyGlow, true)
    -- a drag puts it away, a click on nothing too
    Ed.StartDrag(11, 0, 0); Ed.DragTo(50, 0)
    T.falsy(Card.Shown(), "away while dragging")
    Ed.Drop()
    T.truthy(Card.Shown(), "back after the drop")
    Ed.Select(nil)
    T.falsy(Card.Shown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the grid shows while it's open, a free drop lands on it, a magnet snap wins", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, 13, "icon", 300, -5)
    Ed.Changed()
    T.truthy(DUI.DB.General().gridSnap, "on by default")
    T.truthy(DUI.Movers.Grid():IsShown(), "the unlock grid, behind the pieces")
    -- dropped free: its corner on the nearest grid line
    Ed.StartDrag(11, 10, -10); Ed.DragTo(110, -60); Ed.Drop()
    T.eq(set.pieces[11].x, 96); T.eq(set.pieces[11].y, -48)
    -- the magnet lined its top up with 13's, so that axis stays and the other snaps to the grid
    Ed.StartDrag(11, 110, -60); Ed.DragTo(214, -20); Ed.Drop()
    T.eq(set.pieces[11].y, -5, "13's top, off the grid")
    T.eq(set.pieces[11].x, 208)
    -- a tray drop lands on the grid too
    Ed.StartTrayDrag(12, 0, -400); Ed.DragTo(50, 100); Ed.Drop(false); Ed.Pick("icon")
    T.eq(set.pieces[12].x, 32); T.eq(set.pieces[12].y, 112)
    -- the pill's switches are unlock mode's
    local snap, mag = Ed.SnapButtons()
    T.truthy(snap.active); T.truthy(mag.active)
    snap:Click()
    T.falsy(DUI.DB.General().gridSnap)
    T.falsy(snap.active)
    T.falsy(DUI.Movers.Grid():IsShown(), "off: no grid")
    Ed.StartDrag(11, 0, 0); Ed.DragTo(-101, 3); Ed.Drop()
    T.eq(set.pieces[11].x, 107, "grid off: where it was let go")
    mag:Click()
    T.falsy(DUI.DB.General().magnet)
    snap:Click()
    T.truthy(DUI.Movers.Grid():IsShown())
    Ed.Close()
    T.falsy(DUI.Movers.Grid():IsShown(), "gone with the editor")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the top bar holds every button once the talent set's label is in", function()
    local DUI, AB, Ed, D = edWorld()
    local pill = Ed.Pill()
    local snap, mag = Ed.SnapButtons()
    -- edges 14, title, 14, then the buttons 8 apart
    local wide, n = 14 + 14 + 14, 0
    for _, r in ipairs({ pill:GetRegions() }) do
        if r.GetText and r:GetText() == "Cooldown layout" then wide = wide + r:GetStringWidth() end
    end
    for _, b in ipairs({ pill:GetChildren() }) do
        if b:IsShown() and b:GetObjectType() == "Button" then wide = wide + b:GetWidth(); n = n + 1 end
    end
    wide = wide + (n - 1) * 8
    T.eq(n, 8, "talent set, import, export, reset, live preview, two snaps, done")
    T.truthy(pill:GetWidth() >= wide, "bar " .. pill:GetWidth() .. " vs what it holds " .. wide)
    T.truthy(snap:GetWidth() > 0 and mag:GetWidth() > 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: arrow keys nudge the picked chain (Shift: a grid step); the card's Position row too", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    Ed.Changed()
    local o = _G.DaylightUICdmEditor
    local key = o:GetScript("OnKeyDown")
    key(o, "RIGHT")
    T.eq(set.pieces[11].x, 0, "nothing picked: the key isn't ours")
    Ed.Select(12)
    key(o, "RIGHT"); key(o, "UP")
    T.eq(set.pieces[11].x, 1, "the hooked piece moves its whole chain")
    T.eq(set.pieces[11].y, 1)
    key(o, "LEFT"); key(o, "DOWN")
    T.eq(set.pieces[11].x, 0); T.eq(set.pieces[11].y, 0)
    _G.IsShiftKeyDown = function() return true end
    key(o, "RIGHT")
    _G.IsShiftKeyDown = nil
    T.eq(set.pieces[11].x, 16, "Shift: one grid step")
    T.eq(set.pieces[12].parent, 11, "still hooked")
    -- the card's Chain tab: nudges and X/Y
    local Card = AB.CdmCard
    Card.SetTab("chain")
    local pos = Card.Position()
    T.truthy(pos:IsShown())
    pos.right:Click(); pos.up:Click()
    T.eq(set.pieces[11].x, 17); T.eq(set.pieces[11].y, 1)
    -- X and Y are the whole group's middle, as unlock mode's are a frame's.
    -- Two 36 px icons 4 apart are 76 wide and 36 high.
    T.eq(pos.x:GetText(), "55"); T.eq(pos.y:GetText(), "-17")
    pos.x:SetText("0"); pos.y:SetText("0")
    pos.x:GetScript("OnEnterPressed")(pos.x)
    T.eq(set.pieces[11].x, -38, "0 = centered on the screen"); T.eq(set.pieces[11].y, 18)
    T.eq(pos.x:GetText(), "0"); T.eq(pos.y:GetText(), "0")
    pos.x:SetText("abc")
    pos.x:GetScript("OnEnterPressed")(pos.x)
    T.eq(set.pieces[11].x, -38, "not a number: unchanged")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a piece dragged past a group follows the cursor, no hopping line to line", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    D.AddPiece(set, 14, "icon", -60, 60)
    Ed.Changed()
    local fx, fy = -60, 60
    Ed.StartDrag(14, 0, 0)
    local worst, off, last = 0, 0, nil
    for x = 0, 240 do               -- along the top of the group
        Ed.DragTo(x, 0)
        local px = set.pieces[14].x
        if last then worst = math.max(worst, math.abs(px - last)) end
        if px ~= fx + x then off = off + 1 end
        last = px
    end
    Ed.Drop()
    T.truthy(worst <= 4, "biggest jump for 1 px of mouse: " .. worst)
    T.truthy(off <= 120, "steps pulled off the cursor, of 240: " .. off)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a waiting + puts the card away and grows the tray, then both come back", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11 }, "icon", 0, 0)
    Ed.Changed()
    local Card = AB.CdmCard
    local function settle()
        local d = DUI.Motion.Driver()
        local tick = d and d:GetScript("OnUpdate")
        if tick then tick(d, 1) end
    end
    Ed.Select(11)
    T.truthy(Card.Shown(), "picked: the card")
    local w0, h0 = Ed.Tray():GetWidth(), Ed.Tray():GetHeight()
    Ed.SetAttach(11, "right"); settle()
    T.falsy(Card.Shown(), "the + waits: the card is away")
    local grown = Ed.CELL_BIG - Ed.CELL
    T.eq(Ed.Tray():GetWidth(), w0 + Ed.TRAY_COLS * grown)
    T.truthy(Ed.Tray():GetHeight() > h0, "taller too")
    T.deq({ Ed.TrayCell(1):GetSize() }, { Ed.CELL_BIG, Ed.CELL_BIG }, "bigger spells to hit")
    -- Esc: back as it was, the same piece picked.
    Ed.SetAttach(nil); settle()
    T.truthy(Card.Shown(), "called off: the card again")
    T.eq(Card.Frame():GetAlpha(), 1)
    T.eq(Ed.Tray():GetWidth(), w0); T.eq(Ed.Tray():GetHeight(), h0)
    -- A spell picked: it joins, the tray settles, the card is the new one's.
    Ed.SetAttach(11, "right"); settle()
    Ed.Choose(12); Ed.Pick("icon"); settle()
    T.eq(set.pieces[12].parent, 11)
    T.eq(Ed.Selected(), 12)
    T.truthy(Card.Shown()); T.eq(Card.Frame():GetAlpha(), 1)
    T.eq(Ed.Tray():GetWidth(), w0)
    -- Closed mid-wait: it opens at its normal size.
    Ed.SetAttach(12, "right"); settle()
    Ed.Close(); Ed.Open()
    T.eq(Ed.Tray():GetWidth(), w0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: X and Y of three in a row are the exact middle of the center one", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", -100, 50)
    Ed.Changed()
    Ed.Select(13)
    local b = D.Layout(set)[12]
    local x, y = Ed.Spot()
    T.eq(x, b.x + b.w / 2); T.eq(y, b.y - b.h / 2)
    Ed.MoveTo(0, 0)
    b = D.Layout(set)[12]
    T.eq(b.x + b.w / 2, 0, "0 puts the center spell on the screen's middle")
    T.eq(b.y - b.h / 2, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a waiting + asks right on the tray, where you're about to look", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    Ed.Changed()
    local o = _G.DaylightUICdmEditor
    local banner = Ed.Banner()
    local function settle()
        local d = DUI.Motion.Driver()
        local tick = d and d:GetScript("OnUpdate")
        if tick then tick(d, 1) end
    end
    Ed.Select(11)
    Ed.SetAttach(11, "left"); settle()
    T.truthy(banner:IsShown())
    local p1, to, p2 = banner:GetPoint(1)
    T.eq(to, Ed.Tray(), "on the tray, not up by the title")
    T.eq(p1, "BOTTOM"); T.eq(p2, "TOP")
    T.eq(banner:GetAlpha(), 1)
    T.truthy(string.find(banner.text:GetText(), "|cff%x%x%x%x%x%xSpell %d+|r"), "the spell's name stands out")
    -- The tray dragged while it asks: the question goes along.
    Ed.StartTrayMove(0, 0); Ed.MoveTray(50, 60); Ed.EndTrayMove()
    T.eq(select(2, banner:GetPoint(1)), Ed.Tray())
    T.eq(select(2, banner.text:GetFont()), DUI.Style.SIZE.body)
    -- A tray dragged to the top of the screen: it asks under it.
    DUI.DB.Root().cdmTray = { x = 0, y = 9999 }
    Ed.Draw(); settle()
    p1, to, p2 = banner:GetPoint(1)
    T.eq(p1, "TOP"); T.eq(p2, "BOTTOM")
    DUI.DB.Root().cdmTray = nil
    -- Answered: it fades away, and the normal hints are back up top.
    Ed.SetAttach(nil); settle()
    T.falsy(banner:IsShown(), "a picked piece needs no words")
    Ed.Select(nil); settle()
    T.truthy(banner:IsShown())
    T.eq(banner:GetAlpha(), 1)
    p1, to = banner:GetPoint(1)
    T.eq(p1, "TOP"); T.truthy(to ~= Ed.Tray(), "under the title")
    T.eq(select(2, banner.text:GetFont()), DUI.Style.SIZE.small)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: a + is the only way into a group, and it takes spells already placed", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    D.AddPiece(set, 13, "icon", 300, 0)
    Ed.Changed()
    -- Dropped from the tray right beside a piece: free too.
    Ed.StartTrayDrag(14, 0, -400); Ed.DragTo(100, -18); Ed.Drop(false); Ed.Pick("icon")
    T.isnil(set.pieces[14].parent, "a tray drop never joins")
    -- A placed spell picked in the tray goes to the waiting +.
    Ed.SetAttach(12, "right")
    Ed.Choose(13)
    T.eq(set.pieces[13].parent, 12); T.eq(set.pieces[13].side, "right")
    T.eq(Ed.Selected(), 13); T.isnil(Ed.Attach())
    -- So does a piece clicked on the screen.
    Ed.SetAttach(11, "down")
    Ed.StartDrag(14, 5, 5); Ed.Drop()
    T.eq(set.pieces[14].parent, 11); T.eq(set.pieces[14].side, "down")
    -- It can't go onto itself or what hangs off it: then it's only picked.
    Ed.SetAttach(13, "right")
    Ed.StartDrag(11, 5, 5); Ed.Drop()
    T.isnil(set.pieces[11].parent, "stays first")
    T.eq(Ed.Selected(), 11); T.isnil(Ed.Attach())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: MoveChain puts a chain's first piece at a spot, whole numbers only", function()
    local D = data()
    local set = filled(D)
    T.truthy(D.MoveChain(set, 12, 10.4, -20.6))
    T.eq(set.pieces[11].x, 10); T.eq(set.pieces[11].y, -21)
    T.isnil(set.pieces[12].x, "a hooked piece keeps no spot")
    T.falsy(D.MoveChain(set, 11, 0 / 0, 0))
    T.falsy(D.MoveChain(set, 11, "1", 0))
    T.falsy(D.MoveChain(set, 99, 0, 0))
end)

T.test("cdm card: the Look tab's Whole group colors every bar's background; a spell's own wins", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "bar", 0, 0)
    Ed.Select(11)
    local Card = AB.CdmCard
    local function item(t, key)
        for _, r in ipairs(Card.ROWS[t]) do if r.item and r.item.key == key then return r.item, r end end
    end
    local mode, row = item("look", "cdm.card.chain.back")
    T.truthy(mode, "a group background row on the Look tab")
    T.eq(mode.get(), "dark")
    local colour, crow = item("look", "cdm.card.chain.backColor")
    T.falsy(crow.show(set, 11, set.pieces[11]), "no color row until Solid")
    mode.set("solid")
    T.truthy(crow.show(set, 11, set.pieces[11]))
    T.eq(#colour.get(), 4, "shows a color before one is set")
    colour.set({ 1, 0, 0, 0.5 })
    T.eq(set.chains[11].look.back, "solid")
    T.eq(set.chains[11].look.backColor[1], 1)
    -- both bars take it through "Same as its group"
    local CD = AB.Cooldowns
    for _, id in ipairs({ 11, 12 }) do
        local m, c = CD.BackOf(set.pieces[id], D.PieceBlock(set, id))
        T.eq(m, "solid"); T.eq(c[4], 0.5)
    end
    -- a spell's own background wins over the group's
    T.truthy(D.SetSpellValue(set, 12, "backMode", "gradient"))
    T.eq((CD.BackOf(set.pieces[12], D.PieceBlock(set, 12))), "gradient")
    -- back to dark: the bars' dim fill color again
    mode.set("dark")
    T.isnil(set.chains[11].look.back, "the default isn't kept")
    T.isnil((CD.BackOf(set.pieces[11], D.PieceBlock(set, 11))))
    T.falsy(D.SetLook(set, 11, "back", "plaid", true))
    T.falsy(D.SetLook(set, 11, "backColor", { "red" }, true))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Slice and Dice (Buff only) with Glow when usable and Glow on proc never glowed.
-- Buff only has nothing to be usable off, and WoW Forever fires no proc alerts,
-- so those rows can't do anything.
T.test("cdm card: Usable rows only for a cooldown, and no proc glow row (Forever has no procs)", function()
    local DUI, AB, Ed, D = edWorld()
    withCategories({ [0] = { 11 }, [2] = { 12 } }, { [0] = { 11 }, [2] = { 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, hasAura = id == 11 }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    AB.CdmOwn.Forget()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local function row(key)
        for _, r in ipairs(AB.CdmCard.ROWS.show) do if r.item and r.item.key == key then return r end end
    end
    T.isnil(row("cdm.card.glow"), "no proc glow row")
    T.isnil(row("cdm.card.glowColor"), "no proc glow color row")
    set.pieces[12].usableGlow = true
    for _, key in ipairs({ "cdm.card.usableGlow", "cdm.card.usableGlowColor", "cdm.card.usableSound" }) do
        local r = row(key)
        Ed.Select(12)
        T.falsy(r.show(set, 12, set.pieces[12]), key .. ": Buff only has nothing to be usable off")
        set.pieces[11].usableGlow = true
        Ed.Select(11)
        T.truthy(r.show(set, 11, set.pieces[11]), key .. ": a cooldown does")
    end
    for _, r in ipairs(AB.CdmCard.ROWS.show) do
        if r.head == DUI.L["Usable"] then
            T.falsy(r.show(set, 12, set.pieces[12]), "the heading goes with its rows")
            T.truthy(r.show(set, 11, set.pieces[11]))
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Hide and Keep its spot were two switches for one choice, which was confusing.
T.test("cdm card: Buff up and Buff missing each have one Visibility; Buff missing's is Buff only's", function()
    local DUI, AB, Ed, D = edWorld()
    withCategories({ [0] = { 11 }, [2] = { 12 } }, { [0] = { 11 }, [2] = { 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, hasAura = id == 11 }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    AB.CdmOwn.Forget()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local function item(key)
        for _, r in ipairs(AB.CdmCard.ROWS.show) do if r.item and r.item.key == key then return r.item, r end end
    end
    local up, upRow = item("cdm.card.buffUp")
    local down, downRow = item("cdm.card.buffDown")
    local track = item("cdm.card.track")
    local _, glow = item("cdm.card.missingGlow")
    T.isnil(item("cdm.card.hideActive")); T.isnil(item("cdm.card.hideMissing")); T.isnil(item("cdm.card.missing"))
    local function on(r, id) return r.show(set, id, set.pieces[id]) end
    local q = set.pieces[12]
    -- A buff is gone while it's down unless asked otherwise, as before.
    Ed.Select(12)
    T.eq(up.get(), "show"); T.eq(down.get(), "hide")
    T.truthy(on(downRow, 12)); T.falsy(on(glow, 12), "nothing shows, so nothing to glow")
    for _, key in ipairs({ "cdm.card.readyGlow", "cdm.card.onCd", "cdm.card.desat" }) do
        local _, r = item(key)
        T.falsy(on(r, 12), key .. ": Buff only has no cooldown to act on")
        T.truthy(on(r, 11), key .. ": Cooldown and buff does")
    end
    down.set("show")
    T.eq(down.get(), "show")
    T.eq(q.missing, true); T.falsy(q.hideMissing)
    T.eq(D.PieceBlock(set, 12).always, true, "the grayed icon")
    T.eq(AB.CdmOwn.Track(12, q), "buff"); T.truthy(on(glow, 12))
    down.set("hide")
    T.eq(q.hideMissing, true); T.falsy(q.missing)
    T.eq(D.PieceBlock(set, 12).always, false)
    up.set("hide")
    T.eq(q.hideActive, true); T.eq(up.get(), "hide")
    up.set("show")
    T.falsy(q.hideActive)
    -- A saved Keep its spot and Hide together: Hide won, and still does.
    q.missing, q.hideMissing = true, true
    T.eq(down.get(), "hide")
    -- A glow saved with no Keep its spot: it shows, so the card says so.
    q.missing, q.hideMissing, q.missingGlow = nil, nil, true
    T.eq(down.get(), "show"); T.truthy(on(glow, 12))
    q.hideMissing = true
    T.eq(down.get(), "hide"); T.falsy(on(glow, 12))
    q.missingGlow = nil
    q.missing, q.hideMissing = nil, nil
    -- Cooldown and buff: its cooldown shows while the buff is down, so there's nothing to pick.
    local c = set.pieces[11]
    Ed.Select(11)
    T.eq(AB.CdmOwn.Track(11, c), "both")
    T.falsy(on(downRow, 11)); T.truthy(on(upRow, 11)); T.truthy(on(glow, 11))
    -- Buff only can, and Show holds Buff only by itself.
    track.set("buff")
    T.truthy(on(downRow, 11))
    down.set("hide")
    c.track = nil
    T.eq(AB.CdmOwn.Track(11, c), "buff", "Hide alone holds it")
    down.set("show")
    T.eq(AB.CdmOwn.Track(11, c), "buff", "Show pins it")
    track.set("both")
    T.falsy(c.missing); T.falsy(c.hideMissing)
    _G.GetSpellBaseCooldown = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: When ready on the Show tab for cooldowns only, with Fade to when it fades", function()
    local DUI, AB, Ed, D = edWorld()
    withCategories({ [0] = { 11 }, [2] = { 12 } }, { [0] = { 11 }, [2] = { 12 } })
    AB.CdmOwn.Forget()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local Card = AB.CdmCard
    local function item(key)
        for _, r in ipairs(Card.ROWS.show) do if r.item and r.item.key == key then return r.item, r end end
    end
    local ready, row = item("cdm.card.onReady")
    local _, fadeRow = item("cdm.card.cdAlpha")
    T.truthy(row.show(set, 11, set.pieces[11]), "a cooldown: shown")
    T.falsy(row.show(set, 12, set.pieces[12]), "a buff: not shown (it's always ready)")
    Ed.Select(11)
    T.eq(ready.get(), "show")
    T.falsy(fadeRow.show(set, 11, set.pieces[11]))
    ready.set("fade")
    T.eq(set.pieces[11].onReady, "fade")
    T.truthy(fadeRow.show(set, 11, set.pieces[11]), "Fade to for a fading ready spell")
    ready.set("show")
    T.isnil(set.pieces[11].onReady, "the default isn't kept")
    T.falsy(D.SetSpellValue(set, 11, "onReady", "blink"))
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: stays put while its own sliders change the chain (bar width)", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11 }, "bar", -700, 0)   -- room on its right for the card, with the bar at 400 too
    Ed.Select(11)
    local Card = AB.CdmCard
    T.truthy(Card.Shown())
    local function pos() local _, _, _, x, y = Card.Frame():GetPoint(1); return x, y end
    local function settle()
        stub.RunOnUpdate(Card.Frame(), 0.1)
        local d = DUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 1) end
    end
    settle()
    local x0 = pos()
    local width
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == "cdm.card.chain.width" then width = r.item end end
    width.set(150); settle()
    T.eq((pos()), x0, "narrower: stays")
    width.set(225); settle()
    T.eq((pos()), x0, "a little wider, the + buttons still clear: stays")
    -- grown under the card, it moves clear, but not while the mouse holds one of its sliders
    local old = _G.IsMouseButtonDown
    local held = true
    _G.IsMouseButtonDown = function() return held end
    Card.Frame().IsMouseOver = function() return true end
    width.set(400); settle()
    T.eq((pos()), x0, "held: still")
    held = false; settle(); settle()
    T.truthy(pos() > x0, "let go: clear of the bar")
    _G.IsMouseButtonDown = old
    -- the chain itself moving takes the card along
    local x1 = pos()
    set.pieces[11].x = -750; Ed.Changed(); settle()
    T.truthy(pos() < x1, "follows the chain")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: an icon's Size slider stays grabbable: its row never hides on a redraw, and held, the card never moves", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", -700, 0)
    Ed.Select(11)
    local Card = AB.CdmCard
    local function pos() local _, _, _, x, y = Card.Frame():GetPoint(1); return x, y end
    local function settle()
        stub.RunOnUpdate(Card.Frame(), 0.1)
        local d = DUI.Motion.Driver()
        if d then stub.RunOnUpdate(d, 1) end
    end
    local size, row
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == "cdm.card.size" then size, row = r.item, r end end
    T.truthy(size, "the icon's Size row")
    -- Every step redraws the card, and the slider's row must never hide: in game a
    -- slider hidden mid-drag lets go of the mouse.
    local hid = 0
    row.frame:HookScript("OnHide", function() hid = hid + 1 end)
    size.set(50); settle()
    T.eq(hid, 0, "the Size row stays shown through a redraw")
    T.truthy(row.frame:IsShown())
    for _, grow in ipairs({ "start", "center", "end" }) do
        D.SetChainValue(set, 11, "grow", grow); Ed.Changed(); settle()
        local x0, y0 = pos()
        local old = _G.IsMouseButtonDown
        local held = true
        _G.IsMouseButtonDown = function() return held end
        Card.Frame().IsMouseOver = function() return true end
        for v = 40, 120, 8 do
            size.set(v); settle()
            local x, y = pos()
            T.eq(x, x0, grow .. ": held at " .. v .. ": stays under the mouse")
            T.eq(y, y0, grow .. ": held at " .. v .. ": not up or down either")
        end
        held = false; settle(); settle()
        _G.IsMouseButtonDown = old
        Card.Frame().IsMouseOver = nil
        size.set(40); settle(); settle()
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: its X only closes it; Remove from layout at the bottom takes the spell out", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    Ed.Select(12)
    local Card = AB.CdmCard
    local f = Card.Frame()
    T.truthy(Card.Shown())
    f.close:Click()
    T.falsy(Card.Shown(), "closed")
    T.isnil(Ed.Selected())
    T.truthy(set.pieces[12], "the spell stays")
    Ed.Select(12)
    T.truthy(f.remove:IsShown())
    f.remove:Click()
    T.isnil(set.pieces[12], "removed")
    T.truthy(set.pieces[11], "the rest stays")
    T.falsy(Card.Shown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the top bar's Reset empties the layout after Click again; Import opens the paste box", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12 }, "icon", 0, 0)
    local reset = Ed.PillButton("reset")
    reset:Click()
    T.truthy(D.Current().pieces[11], "the first click only asks")
    stub.Advance(1)
    reset:Click()
    T.isnil(next(D.Current().pieces), "empty")
    local opened
    DUI.Profiles.ShowPaste = function(spec) opened = spec end
    Ed.PillButton("import"):Click()
    T.truthy(opened and opened.read, "the paste box")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player clicked the talent set button to use another layout; it only showed
-- the other talent set, and closing the editor went back to the old one.
T.test("cdm editor: the talent set button picks a layout for either talent set, kept after closing", function()
    local DUI, AB, Ed, D = edWorld()
    local first, other = D.NewProfile("First"), D.NewProfile("Second")
    D.Assign(1, first)
    local got
    local W = DUI.Widgets
    local was = W.OpenMenu
    W.OpenMenu = function(owner, keys, values, current, onPick, width, opts)
        got = { keys = keys, values = values, pick = onPick, opts = opts }
    end
    Ed.PillButton("set"):Click()
    W.OpenMenu = was
    T.truthy(got, "a menu opens")
    T.truthy(got.opts.titles.set1 and got.opts.titles.set2, "a heading per talent set")
    T.truthy(got.values["2:" .. other], "the class's layouts under each")
    T.truthy(got.opts.checked("1:" .. first), "the one in use is ticked")
    T.falsy(got.opts.checked("2:" .. other))
    got.pick("2:" .. other)
    T.eq(D.Use(2), other, "talent set 2 uses it")
    T.eq(Ed.Group(), 2, "and the editor shows it")
    Ed.Close()
    T.eq(D.Use(2), other, "still picked after closing")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the picked spell's group gets an outline round all of it; a lone spell none", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    D.AddChain(set, { 21 }, "icon", 0, -100)
    Ed.Select(12)
    local g = Ed.GroupOutline()
    T.truthy(g:IsShown(), "shown round the group")
    local pad = Ed.GROUP_PAD
    T.near(g:GetWidth(), 3 * 36 + 2 * 4 + 2 * pad, 0.6, "all three spells inside")
    T.near(g:GetHeight(), 36 + 2 * pad, 0.6)
    local d = DUI.Motion.Driver()
    Ed.Select(21)
    if d then stub.RunOnUpdate(d, 1) end
    T.falsy(g:IsShown(), "a lone spell: no group outline")
    -- The colors flow round a lit outline only while the editor is open.
    T.truthy(Ed.Flowing(), "turning while a spell is picked")
    Ed.Close()
    T.falsy(Ed.Flowing(), "the editor shut: nothing runs")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: the Group tab removes the whole group, after Click again", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    D.AddChain(set, { 11, 12, 13 }, "icon", 0, 0)
    D.AddChain(set, { 21 }, "icon", 0, -100)
    Ed.Select(12)
    local Card = AB.CdmCard
    local f = Card.Frame()
    T.truthy(f.remove:IsShown()); T.falsy(f.removeGroup:IsShown())
    Card.SetTab("chain")
    T.falsy(f.remove:IsShown(), "the spell's button gives way")
    T.truthy(f.removeGroup:IsShown())
    f.removeGroup:Click()
    T.truthy(set.pieces[11], "the first click only asks")
    T.eq(f.removeGroup.text:GetText(), DUI.L["Click again"])
    stub.Advance(1)
    f.removeGroup:Click()
    T.isnil(set.pieces[11]); T.isnil(set.pieces[12]); T.isnil(set.pieces[13])
    T.isnil(set.chains[11])
    T.truthy(set.pieces[21], "other groups stay")
    T.isnil(Ed.Selected())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: a taller tab (Group) moves it up so it stays on screen", function()
    local DUI, AB, Ed, D = edWorld()
    local set = D.Current()
    local sh = UIParent:GetHeight() / 2
    D.AddChain(set, { 11 }, "bar", -300, -sh + 60)
    Ed.Select(11)
    local Card = AB.CdmCard
    Card.SetTab("show")
    Card.SetTab("chain")
    local d = DUI.Motion.Driver()
    if d then stub.RunOnUpdate(d, 1) end
    local f = Card.Frame()
    local _, _, _, _, y = f:GetPoint(1)
    T.truthy(y - f:GetHeight() >= -sh + 8, "its bottom on screen")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm options: each talent set picks a profile; New, Copy, Rename and Delete act on the one in use", function()
    local DUI, AB, Ed, D = edWorld()
    Ed.Close()
    stub.units.player = stub.units.player or { isPlayer = true, name = "Tester" }
    stub.units.player.class = "WARRIOR"
    local items = {}
    for _, g in ipairs(DUI.Options.GetPage("cdm.layout").groups) do
        for _, it in ipairs(g.items) do items[it.key or it.label] = it end
    end
    local get = function(k) return DUI:Get("ActionBars", k) end
    T.falsy(items["Edit layout"].disabled(get), "on by default")
    -- The name box answers at once here.
    local answer
    DUI.Widgets.Prompt = function(_, _, onAccept) onAccept(answer) end
    for _, k in ipairs({ "cdm.copy", "cdm.rename", "cdm.delete" }) do
        T.truthy(items[k].disabled(get), k .. ": no profile yet")
    end
    answer = "Tank"
    items["cdm.new"].func()
    local tank = D.Use(DUI.DB.SpecGroup())
    T.eq(D.Profile(tank).name, "Tank")
    D.AddChain(D.Get(1), { 11, 12 }, "icon", 10, 20)
    answer = "Tank copy"
    items["cdm.copy"].func()
    local copy = D.Use(1)
    T.truthy(copy ~= tank, "the copy is in use now")
    T.eq(D.Get(1).pieces[12].parent, 11)
    local values, order = items["cdm.use2"].choices()
    T.eq(values.none, DUI.L["None"])
    T.eq(#order, 3, "None and both profiles")
    items["cdm.use2"].set(tank)
    T.eq(D.Use(2), tank)
    T.eq(items["cdm.use2"].get(), tank)
    answer = "Prot"
    items["cdm.rename"].func()
    T.eq(D.Profile(copy).name, "Prot")
    items["cdm.delete"].func()
    T.isnil(D.Profile(copy))
    T.eq(items["cdm.use1"].get(), "none")
    T.eq(D.Use(2), tank, "the other set keeps its own")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The addon's own spell list (CdmSpells, made by tools/make_cdm_spells.py)

T.test("cdm spells: every class has families of ids, no id twice in a class, group buffs name their class", function()
    loadWorld({ actionbars = true })
    local S = stub.actionbars.CdmSpells
    T.truthy(type(S) == "table", "the list loads")
    for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        local list = S[token]
        T.truthy(type(list) == "table" and #list > 10, token .. " has spells")
        local seen = {}
        for _, f in ipairs(list) do
            T.truthy(#f >= 1, token .. ": a family has ids")
            T.truthy(f.cd or f.aura, token .. ": every family has a cooldown or a duration")
            for _, id in ipairs(f) do
                T.truthy(type(id) == "number" and id > 0, token .. ": a spell id")
                T.isnil(seen[id], token .. ": id " .. tostring(id) .. " in one family only")
                seen[id] = true
            end
        end
    end
    T.truthy(#S.GROUP >= 8, "group buffs")
    for _, f in ipairs(S.GROUP) do T.truthy(type(f.class) == "string" and #f >= 1, "a group buff names its class") end
    local shout
    for _, f in ipairs(S.WARRIOR) do if f[1] == 6673 then shout = f end end
    T.truthy(shout and shout.aura, "Battle Shout puts up a buff")
    T.eq(#shout, 7, "every rank of it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm data: our own spell keys sit beside the game's ids: layout, order, track, copy", function()
    local _, D = profileWorld()
    local set = empty()
    D.AddPiece(set, 11, "icon", 0, 0)
    D.AddPiece(set, "s6673", "bar", 0, -48)
    D.AddPiece(set, "s2687", "icon", 100, 0)
    T.truthy(D.Hook(set, "s2687", 11, "right"))
    local L = D.Layout(set)
    T.deq(box(L["s2687"]), { 40, 0, 36, 36 }, "hung off a game id")
    T.deq(box(L["s6673"]), { 0, -48, 220, 18 })
    T.deq(D.Index(set).roots, { 11, "s6673" }, "numbers first, then ours")
    local keys = { "s9", 30, "s10", 4 }
    table.sort(keys, D.ByKey)
    T.deq(keys, { 4, 30, "s10", "s9" })
    T.truthy(D.SetTrack(set, "s2687", "aura"))
    T.eq(set.pieces["s2687"].track, "aura")
    T.falsy(D.SetTrack(set, 11, "aura"), "a game id has no track")
    T.truthy(D.SetTrack(set, "s2687", "both"))
    T.falsy(D.SetTrack(set, "s2687", "buff"), "a bad value")
    D.SetTrack(set, "s2687", "aura")
    T.falsy(D.SetTrack(set, "s1", "aura"), "not placed")
    local to = D.Profile(D.CopyProfile(D.NewProfile("Mine", nil, set))).set
    T.eq(to.pieces["s2687"].track, "aura", "copied with the rest")
    T.eq(to.pieces["s2687"].parent, 11)
end)

-- A warrior with Battle Shout (two of three ranks), Bloodrage (cooldown and
-- buff) and Sweeping Strikes (not learned), and Fortitude from a priest.
local function customWorld(class)
    loadWorld({ actionbars = true })
    stub.SetUnits({ player = { class = class or "WARRIOR" } })
    local AB = stub.actionbars
    AB.CdmSpells.WARRIOR = {
        { 6673, 5242, 6192, aura = true },
        { 2687, cd = true, aura = true },
        { 12292, cd = true },
    }
    AB.CdmSpells.GROUP = { { 1243, 1244, class = "PRIEST" } }
    stub.knownSpells = { [6673] = true, [5242] = true, [2687] = true }
    AB.CdmCustom.Forget()
    return AB, AB.CdmCustom, AB.CdmData
end

-- Poised is a passive: the passive never shows as a buff, its buff is 1328826.
T.test("cdm custom: a passive with a buff of its own is offered and watched by the buff's id", function()
    local AB, C = customWorld("ROGUE")
    AB.CdmSpells.ROGUE = { { 1328825, aura = true, passive = true }, { 6770, 2070, 11297, aura = true } }
    stub.knownSpells = { [1328825] = true, [6770] = true }
    C.Forget()
    local listed = {}
    for _, e in ipairs(C.Tray()) do listed[e.id] = e end
    T.truthy(listed.s1328825, "Poised is in the tray")
    T.truthy(listed.s1328825.aura, "as a buff")
    T.truthy(listed.s6770, "Sap too")
    T.truthy(C.Ranks("s1328825")[1328826], "watched by its buff's id")
    T.eq(C.Track("s1328825"), "aura", "Buff only: a passive has no cooldown")
end)

T.test("cdm custom: a passive whose buff id isn't known is left out", function()
    local AB, C = customWorld("DRUID")
    AB.CdmSpells.DRUID = { { 1328829, aura = true, passive = true } }
    stub.knownSpells = { [1328829] = true }
    C.Forget()
    T.eq(C.Family("s1328829") and C.Family("s1328829").user, true, "only as a spell added by ID")
    for _, e in ipairs(C.Tray()) do T.truthy(e.id ~= "s1328829", "not in the tray") end
    for _, e in ipairs(C.Unlearned()) do T.truthy(e.id ~= "s1328829", "nor under other talents") end
end)

-- Arcane Blast's casts only do damage. Its stack is another spell (400573), a
-- debuff on the mage, watched on you among buffs and debuffs, never on the target.
T.test("cdm custom: a spell whose debuff lands on you is watched among your debuffs, by the debuff's id", function()
    local AB, C = customWorld("MAGE")
    AB.CdmSpells.MAGE = { { 400574, 1239696, aura = true }, { 116, 205, aura = true } }
    stub.knownSpells = { [400574] = true, [116] = true }
    C.Forget()
    T.deq(C.Ranks("s400574"), { [400574] = true, [1239696] = true, [400573] = true }, "the ranks and the stack's own id")
    T.truthy(C.SelfDebuff("s400574")); T.truthy(C.SelfOnly("s400574"))
    T.falsy(C.SelfDebuff("s116"), "Frostbolt's is on the target")
    T.eq(C.SpellOf("s400574"), 400574, "the stack's id is never the spell shown")
    T.eq(C.KeyOfAuraSpell(400573), nil, "nor a rank of it")
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s400574")
    -- The client's container showed nothing for it in game, so the addon draws it.
    T.eq(#h.containers, 0, "no client container")
    T.truthy(h.face, "our own icon")
    T.truthy(h.ids[400573], "read by the stack's id")
    -- Its text isn't loaded and never read, yet it's still 18 s and 4 stacks from the game's data.
    C_Spell.GetSpellDescription = function() return nil end
    AB.CdmAuras.Track(h)
    for i = 1, 6 do stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c" .. i, 1239696) end
    stub.RunTimers()
    T.eq(h.selfStacks, 4, "4 at most")
    T.truthy(h.endsAt and math.abs(h.endsAt - GetTime() - 18) < 0.01, "18 s from the first cast")
    stub.Advance(18 + AB.CdmAuras.SELF_LATE + 0.1); stub.RunTimers()
    T.eq(h.up, false, "then gone")
    local f = CreateFrame("Frame", nil, UIParent)
    f.size = 30
    AB.CdmAuras.Setup(f, "s116")
    T.eq(f.containers[2].unit, "target"); T.eq(f.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
end)

-- The game takes the stack off a moment after its 18 s, so a cast landing in that
-- moment adds to the old stack in game. Starting a fresh 18 s there left the icon
-- out of step with the debuff from then on.
T.test("cdm custom: a cast just after the stack's 18 s adds to it, as the game does", function()
    local AB, C = customWorld("MAGE")
    AB.CdmSpells.MAGE = { { 400574, 1239696, aura = true } }
    stub.knownSpells = { [400574] = true }
    C.Forget()
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s400574")
    AB.CdmAuras.Track(h)
    stub.combat = true
    local first = GetTime()
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 400574); stub.RunTimers()
    stub.Advance(16.5)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 400574); stub.RunTimers()
    T.eq(h.selfStacks, 2)
    stub.Advance(1.8); stub.RunTimers()
    T.eq(h.face.alphaTo, 1, "18.3 s in it's still on you in game, so still shown")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", 400574); stub.RunTimers()
    T.eq(h.selfStacks, 3, "added to the old stack")
    T.truthy(math.abs(h.endsAt - first - 18) < 0.01, "its end stays 18 s from the first cast")
    stub.Advance(1.2); stub.RunTimers()
    T.eq(h.face.alphaTo, 0, "then gone")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c4", 400574); stub.RunTimers()
    T.eq(h.selfStacks, 1, "the next cast starts it over")
    T.truthy(math.abs(h.endsAt - GetTime() - 18) < 0.01, "with a fresh 18 s")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A trap is an object on the ground. The freeze or burn on whatever walks in is
-- another spell (Freezing Trap's 3355, 14308, 14309), and laying the trap down puts
-- nothing up yet, so a cast in a fight must not say it's up.
T.test("cdm custom: a trap watches its debuff's own ids, and laying it down isn't the debuff", function()
    local AB, C = customWorld("HUNTER")
    AB.CdmSpells.HUNTER = { { 1499, 14310, 14311, cd = true, aura = true }, { 3044, cd = true, aura = true } }
    stub.knownSpells = { [14311] = true, [3044] = true }
    C.Forget()
    T.truthy(C.Trap("s1499")); T.falsy(C.Trap("s3044"))
    local ranks = C.Ranks("s1499")
    for _, sid in ipairs({ 3355, 14308, 14309 }) do T.truthy(ranks[sid], "the freeze of each rank: " .. sid) end
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s1499")
    AB.CdmAuras.Track(h)
    T.eq(h.containers[2].unit, "target"); T.eq(h.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
    T.truthy(h.containers[2].c.__groups.a.opts.candidateFilters.includeSpellIDs[14309], "the top rank's freeze on your target")
    h.wantsUp = true
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "t1", 14311); stub.RunTimers()
    T.falsy(h.up, "the trap is down, nothing frozen yet")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A target carries one Sunder Armor whoever put it there, so another warrior's
-- counts. Each caster's Rend is their own, so another's doesn't.
T.test("cdm auras: a one-copy debuff counts whoever cast it, a DoT only yours", function()
    local AB, C = customWorld("WARRIOR")
    plainAuras()
    stub.SetUnits({ player = { class = "WARRIOR" }, target = { name = "Boar", enemy = true } })
    AB.CdmSpells.WARRIOR = { { 7386, 7405, aura = true }, { 772, 6546, aura = true } }
    stub.knownSpells = { [7386] = true, [772] = true }
    C.Forget()
    T.truthy(AB.CdmAuras.GameBlind("s7386"), "the game's icon can't see another's Sunder")
    T.falsy(AB.CdmAuras.GameBlind("s772"), "Rend stays the game's")
    stub.auras.target = { HARMFUL = {
        { spellId = 7405, duration = 30, expirationTime = GetTime() + 20, sourceUnit = "party1", isFromPlayerOrPlayerPet = false },
        { spellId = 6546, duration = 21, expirationTime = GetTime() + 12, sourceUnit = "party1", isFromPlayerOrPlayerPet = false },
    } }
    -- Aura bars (CdmBars) set up through the same CdmAuras.Setup.
    local function holder(id)
        local h = CreateFrame("Frame", nil, UIParent)
        h.size = 30
        AB.CdmAuras.Setup(h, id)
        return h
    end
    local sunder, rend = holder("s7386"), holder("s772")
    local function targetFilter(h)
        for _, k in ipairs(h.containers or {}) do if k.unit == "target" then return k.c.__groups.a.filter end end
    end
    T.eq(targetFilter(sunder), "HARMFUL", "Sunder watched from any caster")
    T.eq(targetFilter(rend), "HARMFUL|PLAYER", "Rend only yours")
    T.truthy(AB.CdmAuras.IsUp(sunder), "another warrior's Sunder counts")
    T.falsy(AB.CdmAuras.IsUp(rend), "another warrior's Rend doesn't")
    stub.auras.target = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Bestial Wrath's buff is on your pet, where nothing looked: the game's own item
-- only scans you and your target. Watched on the pet as well as on you.
T.test("cdm custom: a buff that lands on your pet is watched on your pet", function()
    local AB, C = customWorld("HUNTER")
    plainAuras()
    stub.SetUnits({ player = { class = "HUNTER" }, pet = { name = "Fang" } })
    AB.CdmSpells.HUNTER = { { 19574, cd = true, aura = true }, { 3045, cd = true, aura = true } }
    stub.knownSpells = { [19574] = true, [3045] = true }
    C.Forget()
    T.truthy(C.OnPet("s19574")); T.falsy(C.OnPet("s3045"))
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s19574")
    AB.CdmAuras.Track(h)
    local seen = {}
    for _, k in ipairs(h.containers) do seen[k.unit .. " " .. k.c.__groups.a.filter] = true end
    T.truthy(seen["player HELPFUL"], "you")
    T.truthy(seen["pet HELPFUL"], "your pet")
    local f = CreateFrame("Frame", nil, UIParent)
    f.size = 30
    AB.CdmAuras.Setup(f, "s3045")
    for _, k in ipairs(f.containers) do T.truthy(k.unit ~= "pet", "Rapid Fire stays on you") end
    -- Read on the pet where auras are plain.
    h.wantsUp = true
    stub.auras.pet = { HELPFUL = { { spellId = 19574, duration = 18, expirationTime = GetTime() + 18,
        sourceUnit = "player", isFromPlayerOrPlayerPet = true } } }
    stub.FireEvent("UNIT_AURA", "pet", { isFullUpdate = true }); stub.RunTimers()
    T.eq(h.up, true, "up on the pet")
    -- A cast is no word on the buff: only the read is.
    stub.auras.pet = {}
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "bw", 19574)
    stub.FireEvent("UNIT_AURA", "pet", { isFullUpdate = true }); stub.RunTimers()
    T.eq(h.up, false, "gone from the pet, whatever you cast")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Summon Hawk calls a hawk for 18 s, two at most (the game's data), and puts no
-- aura up. Each cast is one more hawk; the newest one's time shows, with how many are out.
T.test("cdm custom: Summon Hawk shows each hawk's 18 s and how many are out", function()
    for _, shape in ipairs({ "icon" }) do
        local AB, C = customWorld("HUNTER")
        AB.CdmSpells.HUNTER = { { 1293241, 1293525, cd = true, aura = true } }
        stub.knownSpells = { [1293525] = true }
        C.Forget()
        local h = CreateFrame("Frame", nil, UIParent)
        h.size = 30
        AB.CdmAuras.Setup(h, "s1293241")
        AB.CdmAuras.Track(h)
        T.eq(#h.containers, 0, shape .. ": no aura to watch")
        T.truthy(h.face, shape .. ": drawn by ours")
        T.falsy(h.up)
        stub.combat = true
        local first = GetTime()
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "h1", 1293525); stub.RunTimers()
        T.eq(h.up, true, shape .. ": a hawk")
        T.truthy(math.abs(h.endsAt - first - 18) < 0.01, shape .. ": for 18 s")
        stub.Advance(5)
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "h2", 1293525); stub.RunTimers()
        T.eq(h.selfStacks, 2, shape .. ": two hawks")
        stub.Advance(5)
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "h3", 1293525); stub.RunTimers()
        T.eq(h.selfStacks, 2, shape .. ": still two, the first one left")
        T.truthy(math.abs(h.endsAt - GetTime() - 18) < 0.01, shape .. ": the newest hawk's 18 s")
        stub.Advance(13.1); stub.RunTimers()
        T.eq(h.selfStacks, 1, shape .. ": the second hawk's time ran out (cast 5 s in)")
        T.eq(h.face.alphaTo, 1, shape .. ": one still out")
        stub.Advance(5); stub.RunTimers()
        T.eq(h.up, false, shape .. ": all gone")
        T.eq(h.face.alphaTo, 0, shape .. ": out of sight")
        stub.combat = false
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

-- Weakened Soul (6788), added by its ID. The client's containers showed nothing
-- for it in game (as for Arcane Blast's stack), so it's drawn by the addon: read
-- by id where auras are plain, else counted from your own Power Word: Shield.
T.test("cdm custom: Weakened Soul is drawn by ours, from your read debuff or your shield on you", function()
    local AB, C = customWorld("PRIEST")
    C.Forget()
    T.truthy(C.IsAdded("s6788"))
    local h = AB.CdmAuras.Acquire("s6788", UIParent, false, 30)
    T.truthy(h.face, "drawn by ours, no container")
    T.eq(#(h.containers or {}), 0)
    -- Out of a fight it's read by its id.
    stub.auras.player = { HARMFUL = { { spellId = 6788, duration = 15, expirationTime = GetTime() + 15,
        sourceUnit = "player", isHarmful = true, isFromPlayerOrPlayerPet = true } } }
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
    T.eq(AB.CdmAuras.IsUp(h), true, "read on you")
    stub.auras.player = {}
    stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
    T.eq(AB.CdmAuras.IsUp(h), false, "gone")
    -- In a fight: your shield on yourself puts it up for 15 s.
    stub.combat = true
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pws-1", 10901); stub.RunTimers()
    T.eq(h.up, true, "your shield on you: up")
    T.truthy(h.endsAt and math.abs(h.endsAt - GetTime() - 15) < 0.01, "for 15 s")
    stub.Advance(16.2); stub.RunTimers()
    T.eq(AB.CdmAuras.IsUp(h), false, "15 s later: gone")
    -- A shield on a friend puts it on them, not you.
    stub.SetUnits({ player = { class = "PRIEST" }, target = { friend = true } })
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pws-2", 10901); stub.RunTimers()
    T.falsy(h.up, "your shield on a friend: not on you")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's Cooldown Manager has a Weakened Soul row of its own (Tracked Buffs,
-- spell 6788, on no class list). Its item looks for HELPFUL|PLAYER on you, so it
-- lit up without a time in game. Placed by that row, it's drawn by ours, the same
-- way as when it's added by its ID, icon and bar.
T.test("cdm self debuff: the game's Weakened Soul row is drawn by ours with its time, icon and bar", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31 })
    stub.SetUnits({ player = { class = "PRIEST" } })
    AB.CdmSpells.PRIEST = {}
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31 } }, { [2] = { 31 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 31 and 6788 or 100 + id, selfAura = true }
    end
    unplace(D, set, 41)
    place(D, set, 31, 1, 1)
    icons[1]:SetIsActive(true)   -- the game's item lights up, but has no time
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 31, "bar") end
        AB.CdmRows.Refresh(); stub.RunTimers()
        local h = AB.CdmAuras.Frame(31)
        if shape == "bar" then h = AB.CdmBars.AuraFrame(31) end
        T.truthy(h and h.face, shape .. ": drawn by ours")
        T.eq(icons[1]:GetAlpha(), 0, shape .. ": the game's item out of sight")
        -- Out of a fight it's read on you, with its time.
        stub.auras.player = { HARMFUL = { { spellId = 6788, duration = 15, expirationTime = GetTime() + 15,
            sourceUnit = "player", isHarmful = true, isFromPlayerOrPlayerPet = true } } }
        stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(h.face.alphaTo, 1, shape .. ": shown")
        T.truthy(h.face.shownEnd, shape .. ": its time")
        stub.auras.player = {}
        stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true }); stub.RunTimers()
        T.eq(h.face.alphaTo, 0, shape .. ": gone")
        -- In a fight, your shield on you puts it up for 15 s.
        stub.combat = true
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pws-" .. shape, 10901); stub.RunTimers()
        T.eq(h.face.alphaTo, 1, shape .. ": your shield on you: up")
        T.truthy(h.face.shownEnd and math.abs(h.face.shownEnd - GetTime() - 15) < 0.01, shape .. ": for 15 s")
        stub.Advance(16.2); stub.RunTimers()
        T.eq(h.face.alphaTo, 0, shape .. ": 15 s later: gone")
        stub.combat = false
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Forbearance (25771), added by its ID: a debuff on you. Watched among your debuffs too.
T.test("cdm custom: a spell added by its ID is watched among your own debuffs too", function()
    local AB, C = customWorld("PRIEST")
    C.Forget()
    T.truthy(C.IsAdded("s25771"))
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s25771")
    local seen = {}
    for _, k in ipairs(h.containers) do seen[k.unit .. " " .. k.c.__groups.a.filter] = true end
    T.truthy(seen["player HELPFUL"], "your buffs")
    T.truthy(seen["player HARMFUL|PLAYER"], "your debuffs: an added debuff")
    T.truthy(seen["target HARMFUL|PLAYER"], "your target's, from you")
end)

-- An added debuff on you. The client's
-- containers refuse to pick a debuff on you (or any friend) by spell id unless
-- the spell is never secret (AuraContainerUtil.CanApplyIdentityCandidateFilters,
-- tests/aura_rules.lua), so the debuff group goes by what's left: yours, and no
-- longer than it lasts. Forbearance is on no class list and lasts a minute: its
-- length has to come from the game's data, or a shorter guess hides it.
T.test("cdm custom: a debuff on you really shows in its container (never picked by spell id)", function()
    local shows = require("aura_rules")
    local AB, C = customWorld("PRIEST")
    realFacts()
    local you = { canAssist = true, groupMember = true }
    local function debuffGroup(h)
        for _, k in ipairs(h.containers) do
            local g = k.c.__groups.a
            if k.unit == "player" and g.filter:find("HARMFUL") then return g end
        end
    end
    local h = CreateFrame("Frame", nil, UIParent)
    h.size = 30
    AB.CdmAuras.Setup(h, "s25771")
    local g = debuffGroup(h)
    T.truthy(g, "a debuff group on you")
    T.truthy(shows(g, you, { spellId = 25771, harmful = true, mine = true, duration = 60 }),
        "yours shows, for its whole minute")
    T.falsy(shows(g, you, { spellId = 115, harmful = true, mine = false, duration = 60 }),
        "a mob's debuff on you doesn't")
    T.falsy(shows(g, you, { spellId = 2096, harmful = true, mine = true, duration = 120 }),
        "a longer one of yours doesn't")
    -- A spell the client calls never secret may still go by its id.
    stub.neverSecretAuras = { [25771] = true }
    local n = CreateFrame("Frame", nil, UIParent)
    n.size = 30
    AB.CdmAuras.Setup(n, "s25771")
    local ng = debuffGroup(n)
    T.truthy(shows(ng, you, { spellId = 25771, harmful = true, mine = true, duration = 15, neverSecret = true }))
    T.falsy(shows(ng, you, { spellId = 2096, harmful = true, mine = true, duration = 15, neverSecret = true }),
        "by its id: nothing else")
    stub.neverSecretAuras = {}
end)

T.test("cdm custom: our keys, the highest known rank, every rank, the track", function()
    local AB, C, D = customWorld()
    T.truthy(C.Is("s6673")); T.falsy(C.Is(6673)); T.falsy(C.Is("6673")); T.falsy(C.Is("s"))
    T.eq(C.SpellOf("s6673"), 5242, "the highest rank you know")
    T.deq(C.Ranks("s6673"), { [6673] = true, [5242] = true, [6192] = true }, "every rank, known or not")
    T.isnil(C.Entry("s12292"), "not learned: nothing to draw")
    T.eq(C.SpellOf("s12292"), 12292, "rank 1 for its look")
    T.truthy(C.Entry("s1243") and C.Entry("s1243").aura, "a group buff counts as known, a buff")
    T.truthy(C.SelfOnly("s1243")); T.falsy(C.SelfOnly("s6673"))
    T.falsy(C.Entry("s2687").aura, "a spell with both: its cooldown first")
    T.truthy(C.CanTrack("s2687")); T.truthy(C.CanTrack("s6673"), "a buff of yours can pick too")
    T.falsy(C.CanTrack("s1243"), "a group buff: no cooldown of yours")
    local set = D.Current()
    D.AddPiece(set, "s2687", "icon", 0, 0)
    T.truthy(D.SetTrack(set, "s2687", "aura"))
    T.truthy(C.Entry("s2687").aura, "the piece's pick")
    D.AddPiece(set, "s6673", "icon", 40, 0)
    T.eq(C.Track("s6673"), "aura", "left alone, a buff")
    D.SetTrack(set, "s6673", "cooldown")
    T.eq(C.Track("s6673"), "cooldown", "the player's pick")
    D.SetTrack(set, "s6673", "aura")
    T.truthy(C.IsAdded("s1953"), "not in the list: a spell added by its ID")
    T.isnil(C.Entry("s1953"), "another class's spell (Blink), not known: nothing to draw")
    -- Mana Spring (5677) added by its ID read as a cooldown. It's on no class's
    -- list, so it's someone else's buff on you.
    T.truthy(C.IsAdded("s5677"))
    T.truthy(C.Entry("s5677") and C.Entry("s5677").aura, "someone else's buff: drawn, a buff")
    T.eq(C.Track("s5677"), "aura")
    T.falsy(C.CanTrack("s5677"), "no cooldown of yours to pick")
    D.AddPiece(set, "s5677", "icon", 80, 0)
    D.SetTrack(set, "s5677", "cooldown")
    T.eq(C.Track("s5677"), "aura", "a cooldown pick it can't do is ignored")
    T.eq(AB.CdmOwn.Track("s5677") ~= nil and "x" or AB.CdmOwn.BuffOnly("s5677", set.pieces["s5677"]) and "buff", "buff", "the card's Buff options")
    D.RemovePiece(set, "s5677")
    T.isnil(C.Entry(11), "a game id")
    local tray = {}
    for _, e in ipairs(C.Tray()) do tray[#tray + 1] = e.id end
    T.deq(tray, { "s6673", "s2687", "mainhand", "offhand", "s1243" }, "learned ones, the weapons, then group buffs")
    T.eq(C.Unlearned()[1].id, "s12292")
    stub.knownSpells[6192] = true
    stub.FireEvent("SPELLS_CHANGED")
    T.eq(C.SpellOf("s6673"), 6192, "a new rank learned")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: another class gets its own list; no class read yet is survived", function()
    local AB, C = customWorld("PRIEST")
    T.falsy(C.Family("s6673").ids[2], "a warrior spell isn't a priest's family (one spell, as if added by ID)")
    T.truthy(C.Family("s1243"), "the group buffs are everyone's")
    stub.SetUnits({})
    C.Forget()
    T.falsy(C.Family("s6673").ids[2])
    T.truthy(C.Entry("s1243"), "group buffs still work")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a paladin's Seal shows any seal, on you only, a buff", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = {
        { 20375, 20915, aura = true },          -- Command
        { 20154, 20287, aura = true },          -- Righteousness
        { 21082, 20162, aura = true },          -- Crusader
        { 19740, 19834, aura = true },          -- Blessing of Might: not a seal
    }
    stub.knownSpells = { [21082] = true, [20154] = true, [20287] = true }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C.Forget()
    T.truthy(C.Is("seal"))
    T.deq(C.Ranks("seal"), { [20375] = true, [20915] = true, [20154] = true, [21084] = true, [20287] = true,
        [21082] = true, [20162] = true }, "every rank of every seal, nothing else")
    T.eq(C.SpellOf("seal"), 20287, "Righteousness' rank is its stand-in look")
    T.truthy(C.SelfOnly("seal"), "seals are on you")
    T.falsy(C.CanTrack("seal")); T.eq(C.Track("seal"), "aura")
    T.truthy(C.Entry("seal") and C.Entry("seal").aura)
    T.eq((C.Look("seal")), "Seal", "one word: which seal is up can't be read in a fight")
    T.eq(select(2, C.Look("seal")), "Interface/Icons/Spell_Holy_SealOfVengeance", "an icon of its own, not one seal's")
    T.eq(C.Tray()[1].id, "seal", "first in the tray")
    T.truthy(C.Family("s20154"), "each seal stays on its own too")
    T.eq((C.Look("s20154")), "Spell20287")
    stub.knownSpells = {}
    C.Forget()
    T.isnil(C.Entry("seal"), "no seal known: nothing to draw")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("seal"), "only paladins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a paladin's Aura shows any aura, on you only, a buff, so a missing one can glow", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = { { 20154, 20287, aura = true } }
    stub.knownSpells = { [465] = true, [10290] = true, [20154] = true }
    C.Forget()
    T.truthy(C.Is("aura"))
    local r = C.Ranks("aura")
    T.truthy(r[465] and r[10293] and r[7294] and r[19746] and r[19891] and r[20218], "every rank of every aura")
    T.falsy(r[20154], "not a seal")
    T.truthy(C.SelfOnly("aura")); T.eq(C.Track("aura"), "aura")
    T.truthy(C.Entry("aura") and C.Entry("aura").aura)
    T.eq((C.Look("aura")), "Aura")
    T.eq(select(2, C.Look("aura")), "Interface/Icons/Spell_Holy_AuraMastery", "an icon of its own, not one aura's")
    local tray = {}
    for i, e in ipairs(C.Tray()) do tray[e.id] = i end
    T.eq(tray.seal, 1); T.eq(tray.aura, 2, "beside the Seal")
    stub.knownSpells = {}
    C.Forget()
    T.isnil(C.Entry("aura"), "no aura known: nothing to draw")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("aura"), "only paladins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a paladin's Blessing shows any of their long blessings on you, whoever cast it", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = {
        { 19740, 19834, aura = true },          -- Blessing of Might
        { 20217, aura = true },                 -- Blessing of Kings
        { 25782, 25916, aura = true },          -- Greater Blessing of Might
        { 1022, 5599, cd = true, aura = true }, -- Blessing of Protection: not a long one
        { 20154, 20287, aura = true },          -- Seal of Righteousness
    }
    stub.knownSpells = { [19740] = true, [20154] = true }
    C.Forget()
    T.truthy(C.Is("blessing"))
    T.deq(C.Ranks("blessing"), { [19740] = true, [19834] = true, [20217] = true, [25782] = true, [25916] = true },
        "every long blessing, nothing else")
    T.truthy(C.SelfOnly("blessing"), "on you, whoever cast it")
    T.eq(C.Track("blessing"), "aura"); T.falsy(C.CanTrack("blessing"))
    T.truthy(C.Entry("blessing") and C.Entry("blessing").aura)
    T.eq((C.Look("blessing")), "Blessing")
    local tex = C_Spell.GetSpellTexture
    C_Spell.GetSpellTexture = function(id) if id == 19740 then return 135906 end end
    T.eq(select(2, C.Look("blessing")), 135906, "Blessing of Might's own icon")
    C_Spell.GetSpellTexture = tex
    local tray = {}
    for i, e in ipairs(C.Tray()) do tray[e.id] = i end
    T.eq(tray.seal, 1); T.eq(tray.blessing, 2, "after the Seal (no aura known here)")
    T.eq(C.KeyOfSpell(19834), "s19740", "a blessing's own piece wins a lookup by id")
    T.eq(C.KeyOfSpell(20287), "s20154", "a seal's too")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("blessing"), "only paladins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a hunter's or warlock's Pet piece, known with the spell that calls one, watching no aura", function()
    local AB, C = customWorld("HUNTER")
    AB.CdmSpells.HUNTER = {}
    stub.knownSpells = { [883] = true }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C.Forget()
    T.truthy(C.Is("pet")); T.truthy(C.IsPet("pet"))
    T.truthy(C.Entry("pet") and C.Entry("pet").aura, "a buff-like piece")
    T.eq(C.SpellOf("pet"), 883, "Call Pet")
    T.eq((C.Look("pet")), "Pet")
    T.deq(C.Ranks("pet"), {}, "no aura to look for")
    T.eq(C.Tray()[1].id, "pet")
    stub.knownSpells = {}
    C.Forget()
    T.isnil(C.Entry("pet"), "no pet yet: nothing to draw")
    local AW, CW = customWorld("WARLOCK")
    AW.CdmSpells.WARLOCK = {}
    stub.knownSpells = { [688] = true }
    CW.Forget()
    T.eq(CW.SpellOf("pet"), 688, "Summon Imp")
    local _, W = customWorld("WARRIOR")
    T.isnil(W.Family("pet"), "only hunters and warlocks")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A paladin's Seal of Righteousness is 21084, a rank the generated list
-- (talentsforever.com) lacks. It read "not known" and the Seal piece never showed.
T.test("cdm custom: Seal of Righteousness known as 21084 counts, for itself and the Seal", function()
    local AB, C = customWorld("PALADIN")
    AB.CdmSpells.PALADIN = {
        { 20154, 20287, 20288, aura = true },   -- Righteousness, as the data has it
        { 20375, aura = true },                 -- Command
    }
    stub.knownSpells = { [21084] = true }
    C.Forget()
    T.eq(C.SpellOf("s20154"), 21084, "the rank you know")
    T.truthy(C.Ranks("s20154")[21084], "its buff is watched too")
    T.truthy(C.Entry("s20154"), "known: drawn")
    T.truthy(C.Entry("seal"), "the Seal shows")
    T.truthy(C.Ranks("seal")[21084])
    stub.knownSpells = { [21084] = true, [20287] = true }
    C.Forget()
    T.eq(C.SpellOf("s20154"), 20287, "a higher rank still wins")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The rows world with the addon's own spell list for a warrior.
local function customRows()
    local DUI, AB = rowsWorld()
    stub.SetUnits({ player = { class = "WARRIOR" } })
    AB.CdmSpells.WARRIOR = { { 6673, 5242, 6192, aura = true }, { 2687, cd = true, aura = true } }
    AB.CdmSpells.GROUP = { { 1243, 1244, class = "PRIEST" } }
    stub.knownSpells = { [6673] = true, [5242] = true, [2687] = true }
    C_Spell.GetSpellName = function(sid) return "Spell" .. sid end
    C_Spell.GetSpellTexture = function(sid) return 5000 + sid end
    AB.CdmCustom.Forget()
    return DUI, AB, AB.CdmData, AB.CdmData.Current()
end
local function refresh(AB) AB.CdmRows.Refresh(); stub.RunTimers() end

T.test("cdm custom: the Pet piece shows while your pet is out and glows when it isn't, as an icon and as a bar", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "HUNTER" } })
    AB.CdmSpells.HUNTER = {}
    stub.knownSpells = { [883] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "pet", "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, "pet", "missingGlow", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        T.truthy(D.SetShape(set, "pet", shape) or shape == "icon")
        stub.SetUnits({ player = { class = "HUNTER" } })
        AB.CdmAuras.PetChanged()
        refresh(AB)
        local h = shape == "bar" and AB.CdmBars.AuraFrame("pet") or AB.CdmAuras.Frame("pet")
        T.truthy(h and h:IsShown(), shape .. ": drawn")
        T.eq(#(h.containers or {}), 0, shape .. ": no aura container")
        T.truthy(h.face, shape .. ": drawn by the addon")
        T.eq(h.up, false, shape .. ": no pet")
        T.eq(h.face:GetAlpha(), 0)
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": glows while missing")
        stub.SetUnits({ player = { class = "HUNTER" }, pet = {} })
        stub.FireEvent("UNIT_PET", "player"); stub.RunTimers()
        T.eq(h.up, true, shape .. ": pet out")
        T.eq(h.face:GetAlpha(), 1)
        T.falsy(AB.CdmEffects.GlowShown(h), shape .. ": no glow")
        stub.SetUnits({ player = { class = "HUNTER" }, pet = { dead = true } })
        stub.FireEvent("UNIT_HEALTH", "pet"); stub.RunTimers()
        T.eq(h.up, false, shape .. ": a dead pet is no pet")
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": glows again")
        -- In a fight too: whether a pet is out is never secret.
        stub.SetUnits({ player = { class = "HUNTER" }, pet = {} })
        stub.EnterCombat()
        stub.FireEvent("UNIT_PET", "player"); stub.RunTimers()
        T.eq(h.up, true, shape .. ": called in a fight")
        stub.LeaveCombat()
    end
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: the weapon enchant pieces are offered to every class and watch no aura", function()
    local AB, C = customWorld("WARRIOR")
    AB.CdmSpells.WARRIOR = {}
    C.Forget()
    for _, key in ipairs({ "mainhand", "offhand" }) do
        T.truthy(C.Is(key)); T.truthy(C.Weapon(key))
        T.truthy(C.Entry(key) and C.Entry(key).aura, key .. ": a buff-like piece, always there")
        T.isnil(C.SpellOf(key), key .. ": no spell behind it")
        T.deq(C.Ranks(key), {}, key .. ": no aura to look for")
        T.falsy(C.CanTrack(key), key .. ": nothing else to pick")
    end
    T.eq((C.Look("mainhand")), "Main-hand enchant")
    T.eq(select(2, C.Look("offhand")), "tex:17", "no enchant: the weapon's own icon")
    stub.SetWeaponEnchants({ { slot = 0, timeLeft = 60000, enchantIconID = 4321 } })
    T.eq(select(2, C.Look("mainhand")), 4321, "the enchant's icon while it's on")
    local tray = {}
    for _, e in ipairs(C.Tray()) do tray[e.id] = true end
    T.truthy(tray.mainhand and tray.offhand, "in the tray")
    for _, e in ipairs(C.Unlearned()) do T.truthy(e.id ~= "mainhand" and e.id ~= "offhand") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a weapon enchant piece shows its time and charges and glows when it's gone, as an icon and as a bar", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    D.AddPiece(set, "mainhand", "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, "mainhand", "missingGlow", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        T.truthy(D.SetShape(set, "mainhand", shape) or shape == "icon")
        stub.SetWeaponEnchants({})
        AB.CdmAuras.WeaponsChanged()
        refresh(AB)
        local h = shape == "bar" and AB.CdmBars.AuraFrame("mainhand") or AB.CdmAuras.Frame("mainhand")
        T.truthy(h and h:IsShown(), shape .. ": drawn")
        T.eq(#(h.containers or {}), 0, shape .. ": no aura container")
        T.truthy(h.face, shape .. ": drawn by the addon")
        T.eq(h.up, false, shape .. ": no enchant")
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": glows while missing")
        T.truthy(AB.CdmRows.Tracked("mainhand") ~= false, shape .. ": the card keeps its buff rows")
        -- A poison goes on: 30 minutes, 40 charges.
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 1800000, charges = 40, enchantIconID = 4321, enchantID = 7 } })
        stub.FireEvent("WEAPON_ENCHANT_CHANGED"); stub.RunTimers()
        T.eq(h.up, true, shape .. ": enchanted")
        T.eq(h.face:GetAlpha(), 1)
        T.falsy(AB.CdmEffects.GlowShown(h), shape .. ": no glow")
        T.eq(h.auraLasts, 1800, shape .. ": its full length")
        T.eq(stub.Text(h.face.count), "40", shape .. ": its charges")
        T.eq(h.face.shownIcon, 4321, shape .. ": the enchant's icon")
        -- A hit uses a charge, in a fight too: the client answers plainly there.
        stub.EnterCombat()
        stub.Advance(60)
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 1740000, charges = 39, enchantIconID = 4321, enchantID = 7 } })
        stub.FireEvent("UNIT_INVENTORY_CHANGED", "player"); stub.RunTimers()
        T.eq(stub.Text(h.face.count), "39", shape .. ": a charge used")
        T.eq(h.auraLasts, 1800, shape .. ": still the same enchant")
        -- Put on again early: a fresh full length.
        stub.SetWeaponEnchants({ { slot = 0, timeLeft = 1800000, charges = 40, enchantIconID = 4321, enchantID = 7 } })
        stub.FireEvent("WEAPON_ENCHANT_CHANGED"); stub.RunTimers()
        T.eq(h.auraLasts, 1800, shape .. ": the new one's length")
        -- It wears off.
        stub.SetWeaponEnchants({})
        stub.FireEvent("WEAPON_ENCHANT_CHANGED"); stub.RunTimers()
        T.eq(h.up, false, shape .. ": worn off in a fight")
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": glows again")
        stub.LeaveCombat()
    end
    -- The off-hand piece reads its own weapon only.
    D.AddPiece(set, "offhand", "icon", 0, 100)
    stub.SetWeaponEnchants({ { slot = 0, timeLeft = 60000 } })
    AB.CdmAuras.WeaponsChanged()
    refresh(AB)
    T.eq(AB.CdmAuras.Frame("offhand").up, false, "the main hand's enchant isn't the off hand's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a spell of ours as an icon is our cooldown icon, timed by the rank you know", function()
    local DUI, AB, D, set = customRows()
    local asked
    C_Spell.GetSpellCooldownDuration = function(sid) asked = sid; return {} end
    D.AddPiece(set, "s2687", "icon", 0, 0)
    refresh(AB)
    local f = AB.CdmOwn.Frame("s2687")
    T.truthy(f and f:IsShown(), "our icon")
    T.eq(f:GetParent(), pieceFrame(1, "s2687"), "in its piece")
    T.eq(f.cooldownInfo.spellID, 2687, "the effects read it")
    T.eq(asked, 2687, "timed by the client")
    T.eq(AB.CdmRows.DrawnBy("s2687"), "own icon")
    if T.dev then devCdm(DUI, "why") end
    -- Unlearned (a talent swap): nothing drawn and nothing breaks, back when learned.
    stub.knownSpells = {}
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.falsy(f:IsShown(), "not known: hidden")
    stub.knownSpells = { [2687] = true }
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.truthy(f:IsShown(), "learned again")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a buff of ours watches every rank on you, then your target; a group buff only you", function()
    local DUI, AB, D, set = customRows()
    D.AddPiece(set, "s6673", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("s6673")
    T.truthy(h and h:IsShown(), "the game's aura display in a holder of ours")
    T.eq(#h.containers, 2)
    T.eq(h.containers[1].unit, "player"); T.eq(h.containers[1].c.__groups.a.filter, "HELPFUL")
    T.eq(h.containers[2].unit, "target"); T.eq(h.containers[2].c.__groups.a.filter, "HARMFUL|PLAYER")
    T.deq(h.containers[1].c.__groups.a.opts.candidateFilters.includeSpellIDs,
        { [6673] = true, [5242] = true, [6192] = true }, "every rank")
    T.truthy(pieceFrame(1, "s6673"):IsShown(), "keeps its spot while the buff is down")
    T.eq(AB.CdmRows.DrawnBy("s6673"), "aura icon")
    D.SetShape(set, "s6673", "bar")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("s6673"), "aura bar")
    T.truthy(AB.CdmBars.AuraFrame("s6673"):IsShown())
    D.AddPiece(set, "s1243", "icon", 0, -48)
    refresh(AB)
    T.eq(#AB.CdmAuras.Frame("s1243").containers, 1, "a group buff: on you only")
    -- Bloodrage switched to its buff.
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.SetTrack(set, "s2687", "aura")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("s2687"), "aura icon")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A priest's Renew and Inner Fire with Grow from Middle: buffs Daylight UI draws
-- itself kept their spot when they dropped, so the group never closed up or
-- re-centered.
T.test("cdm custom: a buff of ours that's down slides out of its group; one we can't tell keeps its spot", function()
    local DUI, AB, D, set = customRows()
    plainAuras()
    DUI.DB.General().motion = false
    D.AddPiece(set, "s6673", "icon", 0, 0)
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.Hook(set, "s2687", "s6673", "right")
    T.truthy(D.SetChainValue(set, "s6673", "grow", "center"))
    local full = D.Layout(set)
    local w = full["s6673"].w
    local gap = full["s2687"].x - w
    stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
    refresh(AB)
    local h = AB.CdmAuras.Frame("s6673")
    local f, f2 = pieceFrame(1, "s6673"), pieceFrame(1, "s2687")
    T.eq(f2.goalX, full["s2687"].x, "both up: each in its spot")
    -- The buff drops and the other one moves to the group's middle.
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, (w + gap) / 2, "down: the rest closes up round the middle")
    T.truthy(f:IsShown() and h:IsShown(), "still listening for the buff")
    -- In a fight it can land without your cast (a proc, or someone else's).
    stub.combat = true
    stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "it landed in the fight: back in its spot")
    T.eq(f.goalX, 0)
    stub.auras.player = { HELPFUL = {} }
    stub.combat = false
    -- Keep its spot never slides.
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, (w + gap) / 2, "it dropped: closed up again")
    T.truthy(D.SetSpellValue(set, "s6673", "missing", true))
    refresh(AB)
    T.eq(f2.goalX, full["s2687"].x, "Keep its spot")
    T.truthy(D.SetSpellValue(set, "s6673", "missing", false))
    -- Slide over off: every spell keeps its place.
    T.truthy(D.SetChainValue(set, "s6673", "collapse", false))
    refresh(AB)
    T.eq(f2.goalX, full["s2687"].x, "Slide over off")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A mage's Missile Barrage hung above Arcane Blast: while its buff was down it
-- waited, still listening, right on top of Arcane Blast, so a proc in a fight came
-- up there and the two icons sat on each other. Hung left, the same.
T.test("cdm custom: a buff that slid out waits beside its spot, never on top of the piece it hangs from", function()
    local DUI, AB, D, set = customRows()
    DUI.DB.General().motion = false
    D.AddPiece(set, "s6673", "icon", 0, 0)
    for _, case in ipairs({ { "up", "icon" }, { "left", "icon" }, { "down", "icon" }, { "right", "icon" },
        { "up", "bar" }, { "left", "bar" } }) do
        local side, shape = case[1], case[2]
        set.pieces["s2687"] = nil
        D.AddPiece(set, "s2687", shape, 0, -96)
        T.truthy(D.Hook(set, "s2687", "s6673", side))
        D.SetTrack(set, "s2687", "aura")
        stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
        refresh(AB)
        T.eq(AB.CdmRows.DrawnBy("s2687"), "aura " .. shape)
        side = side .. " " .. shape
        local parent, f = pieceFrame(1, "s6673"), pieceFrame(1, "s2687")
        T.truthy(f:IsShown(), side .. ": still listening while down")
        local pw, ph = parent:GetSize()
        local w, h = f:GetSize()
        local px, py, x, y = parent.goalX, parent.goalY, f.goalX, f.goalY
        local apart = x >= px + pw or x + w <= px or y - h >= py or y <= py - ph
        T.truthy(apart, side .. ": waits clear of the piece it hangs from ("
            .. x .. "," .. y .. " vs " .. px .. "," .. py .. ")")
    end
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A druid's Mark of the Wild and Thorns with Grow from Middle, Buff up Hide and
-- Buff missing Show (a reminder of what's missing): the one that was up hid but
-- kept its spot, so the missing one sat off to the side instead of in the middle.
T.test("cdm custom: a buff hidden while up (Buff up Hide) gives its spot up, even with Buff missing Show", function()
    local DUI, AB, D, set = customRows()
    plainAuras()
    DUI.DB.General().motion = false
    D.AddPiece(set, "s6673", "icon", 0, 0)
    D.AddPiece(set, "s2687", "icon", 0, -96)
    D.Hook(set, "s2687", "s6673", "right")
    T.truthy(D.SetChainValue(set, "s6673", "grow", "center"))
    for _, id in ipairs({ "s6673", "s2687" }) do
        T.truthy(D.SetSpellValue(set, id, "missing", true))
        T.truthy(D.SetSpellValue(set, id, "hideActive", true))
    end
    local full = D.Layout(set)
    local w = full["s6673"].w
    local gap = full["s2687"].x - w
    stub.auras.player = { HELPFUL = {} }
    refresh(AB)
    local f2 = pieceFrame(1, "s2687")
    T.eq(f2.goalX, full["s2687"].x, "both missing: each shows in its spot")
    -- The first lands, hidden while up, so its spot goes and the missing one centers.
    stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, (w + gap) / 2, "up and hidden: the missing one comes to the middle")
    -- It drops again: back in its spot, both showing.
    stub.auras.player = { HELPFUL = {} }
    AB.CdmAuras.AuraChanged(); stub.RunTimers()
    T.eq(f2.goalX, full["s2687"].x, "missing again: back in its spot")
    -- Slide over off: every spell keeps its place.
    stub.auras.player = { HELPFUL = { { spellId = 6673 } } }
    T.truthy(D.SetChainValue(set, "s6673", "collapse", false))
    refresh(AB)
    T.eq(f2.goalX, full["s2687"].x, "Slide over off")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: the Seal placed as an icon and a bar watches every seal on you, named Seal", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 20375, 20915, aura = true }, { 20154, 20287, aura = true } }
    stub.knownSpells = { [20154] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "seal", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("seal")
    T.truthy(h and h:IsShown())
    T.eq(#h.containers, 1, "on you only")
    T.deq(h.containers[1].c.__groups.a.opts.candidateFilters.includeSpellIDs,
        { [20375] = true, [20915] = true, [20154] = true, [21084] = true, [20287] = true })
    T.eq(AB.CdmRows.DrawnBy("seal"), "aura icon")
    -- The empty slot ("Show missing buffs") used to wear Righteousness' icon.
    T.eq(h.under:GetTexture(), "Interface/Icons/Spell_Holy_SealOfVengeance", "the empty slot wears the Seal's own icon")
    D.SetShape(set, "seal", "bar")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("seal"), "aura bar")
    T.eq(AB.CdmBars.AuraFrame("seal").Bar.Name:GetText(), "Seal")
    T.eq(AB.CdmBars.AuraFrame("seal").Icon.Icon:GetTexture(), "Interface/Icons/Spell_Holy_SealOfVengeance")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: the Blessing wears Blessing of Might's own icon as an icon and a bar, a known file when the client has none", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 19740, 19834, aura = true }, { 20217, aura = true } }
    stub.knownSpells = { [19740] = true }
    AB.CdmCustom.Forget()
    local tex = C_Spell.GetSpellTexture
    local icon = 135906   -- what the client hands back for rank 1, read when drawn
    C_Spell.GetSpellTexture = function(id) if id == 19740 then return icon end end
    D.AddPiece(set, "blessing", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("blessing")
    T.truthy(h and h:IsShown())
    T.eq(AB.CdmRows.DrawnBy("blessing"), "aura icon")
    T.eq(h.under:GetTexture(), icon, "the empty slot wears the spell's own icon")
    D.SetShape(set, "blessing", "bar")
    refresh(AB)
    T.eq(AB.CdmRows.DrawnBy("blessing"), "aura bar")
    T.eq(AB.CdmBars.AuraFrame("blessing").Bar.Name:GetText(), "Blessing")
    T.eq(AB.CdmBars.AuraFrame("blessing").Icon.Icon:GetTexture(), icon)
    -- The client doesn't know the spell yet: a file it ships.
    C_Spell.GetSpellTexture = function() return nil end
    T.eq(select(2, AB.CdmCustom.Look("blessing")), "Interface/Icons/Spell_Holy_FistOfJustice")
    C_Spell.GetSpellTexture = tex
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The client rebuilds every button of its aura containers on a fight's end, the
-- unit's flags changing and entering the world (FullAuraRefreshEvents in
-- Blizzard_CustomAuraContainer.lua): each is let go and handed its aura again, which
-- plays its shown animation. A buff up all along slid in again as if it had landed.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm custom: a buff already up doesn't slide in again when the client rebuilds its buttons (" .. shape .. ")", function()
    local DUI, AB, D, set = customRows()
    plainAuras()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 20375, 20915, aura = true } }
    stub.knownSpells = { [20375] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "seal", shape, 0, 0)
    stub.SetAuras("player", "HELPFUL", { { spellId = 20375, name = "Seal of Command" } })
    refresh(AB)
    stub.FireEvent("UNIT_AURA", "player", {}); stub.RunTimers()
    local h = shape == "bar" and AB.CdmBars.AuraFrame("seal") or AB.CdmAuras.Frame("seal")
    local btn = (h.buttons and h.buttons[1]) or (h.parts and next(h.parts))
    T.truthy(btn and btn.cdmSlide, "its button has the slide")
    T.eq(btn.cdmSlideKey, "slide")
    for _, ev in ipairs({ { "PLAYER_REGEN_ENABLED" }, { "PLAYER_ENTERING_WORLD" }, { "UNIT_FLAGS", "player" } }) do
        stub.FireEvent(ev[1], ev[2])
        T.truthy(btn.cdmSlideHeld, ev[1] .. ": still for the rebuild")
        -- The client's rebuild, on its next update: let go, then shown again.
        stub.AuraVisible(btn, false); stub.AuraVisible(btn, true)
        stub.RunTimers()
        T.falsy(btn.cdmSlideHeld, ev[1] .. ": tuned back after it")
        T.eq(btn.cdmSlideKey, "slide", ev[1] .. ": a buff landing later still slides in")
    end
    -- In a fight the buttons are locked: stilled there, they'd stay still all fight.
    stub.EnterCombat()
    stub.FireEvent("UNIT_FLAGS", "player")
    T.falsy(btn.cdmSlideHeld, "left alone in a fight")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(btn.cdmSlideKey, "slide")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- The Seal as an icon with "Glow when not active" on, no seal up, and no glow:
-- the aura holders never said whether the buff was down.
T.test("cdm custom: Glow when not active lights our aura icon and bar while the buff is down", function()
    local DUI, AB, D, set = customRows()
    plainAuras()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 20375, 20915, aura = true }, { 20154, 20287, aura = true } }
    stub.knownSpells = { [20154] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "seal", "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, "seal", "missing", true))
    T.truthy(D.SetSpellValue(set, "seal", "missingGlow", true))
    stub.SetAuras("player", "HELPFUL", {})
    refresh(AB)
    local Fx, h = AB.CdmEffects, AB.CdmAuras.Frame("seal")
    T.truthy(Fx.GlowShown(h), "no seal: glows")
    -- With white picked, the glow stayed the accent color.
    T.truthy(D.SetSpellValue(set, "seal", "missingGlowColor", { 1, 1, 1 }))
    refresh(AB)
    local gf = Fx.GlowFrame(h)
    T.deq(glowRGB(gf.tex), { 1, 1, 1 }, "in the picked white")
    T.isnil(gf.tex.__gradient, "no accent gradient left on it")
    stub.SetAuras("player", "HELPFUL", { { spellId = 20375, name = "Seal of Command" } })
    stub.FireEvent("UNIT_AURA", "player", {}); stub.RunTimers()
    T.falsy(Fx.GlowShown(h), "a seal up: no glow")
    local btn = h.buttons and h.buttons[1]
    T.truthy(btn and btn.cdmSlide, "its button slides in as the aura lands")
    T.eq(btn.cdmSlideOn, true)
    T.eq(btn.cdmSlideKey, "slide", "a buff-only icon still drops in")
    -- In a fight the lookups come back empty, so the last answer holds.
    stub.EnterCombat()
    stub.FireEvent("UNIT_AURA", "player", {}); refresh(AB)
    T.falsy(Fx.GlowShown(h), "not a false alarm mid-fight")
    stub.LeaveCombat()
    stub.SetAuras("player", "HELPFUL", {})
    stub.FireEvent("PLAYER_REGEN_ENABLED"); stub.RunTimers()
    T.truthy(Fx.GlowShown(h), "fell off: glows once readable")
    -- The same as a bar.
    D.SetShape(set, "seal", "bar")
    refresh(AB)
    T.truthy(Fx.GlowShown(AB.CdmBars.AuraFrame("seal")), "the bar glows too")
    -- Off: no glow.
    D.SetSpellValue(set, "seal", "missingGlow", false)
    refresh(AB)
    T.falsy(Fx.GlowShown(AB.CdmBars.AuraFrame("seal")))
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Seal of Fury as a bar with "Show missing buffs" off still showed its empty bar
-- while the seal was down. Addon code can't tell in a fight whether the buff is
-- up, so the client's own button carries the bar's whole look (background,
-- borders, name), and the addon's bar under it only shows with "Show missing
-- buffs" on.
T.test("cdm custom: Show missing buffs off draws nothing of ours while the buff is down", function()
    local DUI, AB, D, set = customRows()
    D.AddPiece(set, "s6673", "bar", 0, 0)
    D.AddPiece(set, "s1243", "icon", 0, -48)
    D.SetSpellValue(set, "s6673", "missing", false)
    D.SetSpellValue(set, "s1243", "missing", false)
    refresh(AB)
    local h = AB.CdmBars.AuraFrame("s6673")
    T.truthy(h:IsShown(), "it keeps its spot")
    T.eq(h.under:GetAlpha(), 0, "no empty bar")
    T.eq(h.over:GetAlpha(), 0, "no name over nothing")
    local btn = h.containers[1].c.__groups.a.button
    local parts = h.parts[btn]
    T.eq(parts.slot:GetAlpha(), 1, "the client's button wears the bar's border")
    T.eq(parts.iconBox:GetAlpha(), 1, "and the icon's")
    T.eq(parts.backTex:GetAlpha(), 1, "and its background")
    T.eq(parts.name:GetAlpha(), 1); T.eq(parts.name:GetText(), "Spell5242", "and its name")
    T.truthy(h.containers[1].c:GetFrameLevel() > h.Bar:GetFrameLevel(), "the client's bar over our empty one")
    local icon = AB.CdmAuras.Frame("s1243")
    T.truthy(icon:IsShown(), "the icon keeps its spot")
    T.falsy(icon.under:IsShown(), "no grayed icon")
    -- On: the empty bar and grayed icon while down, with the button's own extras off.
    D.SetSpellValue(set, "s6673", "missing", true)
    D.SetSpellValue(set, "s1243", "missing", true)
    refresh(AB)
    T.eq(h.under:GetAlpha(), 1); T.eq(h.over:GetAlpha(), 1)
    T.eq(parts.slot:GetAlpha(), 0); T.eq(parts.iconBox:GetAlpha(), 0)
    T.eq(parts.name:GetAlpha(), 0); T.eq(parts.backTex:GetAlpha(), 0)
    T.truthy(icon.under:IsShown(), "the grayed icon")
    -- Switched off in a boss fight: both wait until it's over, together.
    stub.SetRestriction("Encounter", true)
    D.SetSpellValue(set, "s6673", "missing", false)
    refresh(AB)
    T.eq(h.under:GetAlpha(), 1, "not yet: the button can't change now")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.SetRestriction("Encounter", false)
    stub.RunTimers()
    T.eq(h.under:GetAlpha(), 0); T.eq(parts.slot:GetAlpha(), 1)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a shield's icon shows the shield left in place of its time", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PRIEST", absorbs = 0 } })
    AB.CdmSpells.PRIEST = { { 17, 592, aura = true } }
    stub.knownSpells = { [592] = true }
    AB.CdmCustom.Forget()
    D.AddPiece(set, "s17", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("s17")
    T.truthy(h and h.amount and h.amount:IsShown(), "the amount, on by default")
    T.eq(rawget(h.amount:GetValue(), "__value"), 0, "no shield: its gate closed")
    local btn = h.containers[1].c.__groups.a.button
    local cd = h.parts[btn].cd
    T.truthy(h.amountOn)
    -- It lands, then soaks, in a fight: drawn but never read.
    stub.EnterCombat()
    stub.units.player.absorbs = stub.Secret(480)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(h.amount.text:GetText(), "__value"), "480")
    T.eq(rawget(h.amount:GetValue(), "__value"), 480, "its gate open")
    stub.units.player.absorbs = stub.Secret(200)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    T.eq(rawget(h.amount.text:GetText(), "__value"), "200")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.LeaveCombat()
    -- Off shows the time again; on, it gives way (the client's cooldown, after restrictions).
    function cd:SetHideCountdownNumbers(v) self.__hideNumbers = v end
    D.SetSpellValue(set, "s17", "shieldAmount", false)
    refresh(AB)
    T.falsy(h.amount:IsShown(), "no amount")
    T.eq(cd.__hideNumbers, false, "the time is back")
    D.SetSpellValue(set, "s17", "shieldAmount", true)
    refresh(AB)
    T.truthy(h.amount:IsShown())
    T.eq(cd.__hideNumbers, true, "the time gives way")
    -- Hide duration swipe turns the client's swipe off and keeps its time.
    function cd:SetDrawSwipe(v) self.__swipe = v end
    T.truthy(D.SetSpellValue(set, "s17", "noDurationSwipe", true))
    refresh(AB)
    T.eq(cd.__swipe, false, "no swipe")
    D.SetSpellValue(set, "s17", "noDurationSwipe", false)
    refresh(AB)
    T.eq(cd.__swipe, true, "the swipe back")
    -- Reverse swipe reaches the client's swipe too (after restrictions).
    function cd:SetReverse(v) self.__reverse = v end
    T.truthy(D.SetSpellValue(set, "s17", "reverse", true))
    refresh(AB)
    T.eq(cd.__reverse, true, "reversed")
    D.SetSpellValue(set, "s17", "reverse", false)
    refresh(AB)
    T.eq(cd.__reverse, false, "not reversed")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a shield's bar fills by the shield left, its full when it lands", function()
    local DUI, AB, D, set = customRows()
    stub.SetUnits({ player = { class = "PRIEST", absorbs = 0 } })
    AB.CdmSpells.PRIEST = { { 17, 592, aura = true }, { 139, aura = true } }
    stub.knownSpells = { [592] = true, [139] = true }
    AB.CdmCustom.Forget()
    T.truthy(AB.CdmBars.IsShield("s17"), "Power Word: Shield, any rank")
    T.falsy(AB.CdmBars.IsShield("s139"), "Renew isn't one")
    D.AddPiece(set, "s17", "bar", 0, 0)
    refresh(AB)
    local h = AB.CdmBars.AuraFrame("s17")
    local s = h.shield
    T.truthy(s and s:IsShown(), "our shield bar")
    local btn = h.containers[1].c.__groups.a.button
    local parts = h.parts[btn]
    T.eq(parts.bar:GetStatusBarTexture():GetAlpha(), 0, "the client's time fill gives way")
    T.eq(parts.time:GetAlpha(), 0, "and its time")
    -- It lands: the amount is its full value, and the hits after drain it.
    stub.AuraVisible(btn, false)
    stub.units.player.absorbs = stub.Secret(480)
    stub.EnterCombat()
    stub.AuraVisible(btn, true)
    local lo, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 480, "full at the amount it landed with")
    T.eq(rawget(s.text:GetText(), "__value"), "480")
    stub.Advance(1)
    stub.units.player.absorbs = stub.Secret(200)
    stub.FireEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    lo, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 480, "the full stays")
    T.eq(rawget(s:GetValue(), "__value"), 200, "drained")
    T.eq(rawget(s.text:GetText(), "__value"), "200")
    T.eq(stub.lockErrors, 0, tostring(next(stub.lockSites)))
    stub.LeaveCombat()
    -- A friendly target: its shield (from any caster), full from what it has now.
    T.eq(#h.containers, 1, "one container, its unit following the target")
    T.eq(h.containers[1].unit, "player")
    T.eq(h.containers[1].c.__groups.a.filter, "HELPFUL")
    stub.units.target = { friend = true, absorbs = stub.Secret(900) }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(h.containers[1].unit, "target")
    T.eq(h.containers[1].c.__unit, "target")
    lo, hi = s:GetMinMaxValues()
    T.eq(rawget(hi, "__value"), 900, "the target's shield is the full")
    T.eq(rawget(s.text:GetText(), "__value"), "900")
    -- An enemy target: back to yours.
    stub.units.target = { friend = false, absorbs = stub.Secret(50) }
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    T.eq(h.containers[1].c.__unit, "player")
    T.eq(rawget(s.text:GetText(), "__value"), "200")
    T.eq(s.text:GetAlpha(), 1, "the amount shows")
    -- Show shield amount off: the bar alone.
    D.SetSpellValue(set, "s17", "shieldAmount", false)
    refresh(AB)
    T.eq(s.text:GetAlpha(), 0, "no amount")
    T.truthy(s:IsShown(), "the bar stays")
    D.SetSpellValue(set, "s17", "shieldAmount", true)
    refresh(AB)
    T.eq(s.text:GetAlpha(), 1)
    -- By time instead: the client's bar again.
    D.SetSpellValue(set, "s17", "fillBy", "time")
    refresh(AB)
    T.falsy(s:IsShown(), "no shield bar")
    T.eq(parts.bar:GetStatusBarTexture():GetAlpha(), 1)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a buff of ours placed in a fight gets its containers once the fight ends", function()
    local DUI, AB, D, set = customRows()
    stub.EnterCombat()
    D.AddPiece(set, "s6673", "icon", 0, 0)
    refresh(AB)
    local h = AB.CdmAuras.Frame("s6673")
    T.eq(#h.containers, 0, "none made in combat")
    stub.LeaveCombat(); stub.RunTimers()
    T.eq(#h.containers, 2, "made once it ends")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm custom: a boss fight with our pieces up raises no errors", function()
    local DUI, AB, D, set = customRows()
    C_Spell.GetSpellCooldownDuration = function() return {} end
    D.AddPiece(set, "s2687", "icon", 0, 0)
    D.AddPiece(set, "s6673", "bar", 0, -48)
    D.AddPiece(set, "s1243", "icon", 0, -96)
    refresh(AB)
    stub.SetRestriction("Encounter", true)
    stub.EnterCombat()
    stub.FireEvent("SPELL_UPDATE_COOLDOWN")
    stub.FireEvent("UNIT_AURA", "player")
    stub.FireEvent("PLAYER_TARGET_CHANGED")
    refresh(AB)
    T.truthy(AB.CdmOwn.Frame("s2687"):IsShown())
    stub.LeaveCombat()
    stub.SetRestriction("Encounter", false)
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- edWorld's game spells are 11-14 (spell ids 111-114) and bars 21-22.
local function customTray(AB, families, known)
    stub.SetUnits({ player = { class = "WARRIOR" } })
    AB.CdmSpells.WARRIOR = families
    AB.CdmSpells.GROUP = { { 1243, class = "PRIEST" } }
    stub.knownSpells = known
    AB.CdmCustom.Forget()
end
local function trayIds(Ed)
    local ids = {}
    for _, e in ipairs(Ed.Spells()) do ids[#ids + 1] = e.id end
    return ids
end

-- The Seal (on you only, like a group buff) was hidden behind the Group buffs switch.
T.test("cdm editor: a paladin's Seal is in the tray with Group buffs off", function()
    local DUI, AB, Ed, D = edWorld()
    stub.SetUnits({ player = { class = "PALADIN" } })
    AB.CdmSpells.PALADIN = { { 20154, 20287, aura = true } }
    AB.CdmSpells.GROUP = { { 1243, class = "PRIEST" } }
    stub.knownSpells = { [21084] = true }
    AB.CdmCustom.Forget()
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "seal", "s20154", "mainhand", "offhand" }, "the Seal first of ours, no group buff")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: the tray adds our class spells and group buffs, once each, after the game's", function()
    local DUI, AB, Ed, D = edWorld()
    -- 111 is the game's spell 11 (same name), so it's listed once, as the game's.
    customTray(AB, { { 111, aura = true }, { 2687, cd = true }, { 12292, cd = true } },
        { [111] = true, [2687] = true })
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "s2687", "mainhand", "offhand" }, "group buffs off by default")
    Ed.SetShowGroup(true)
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "s2687", "mainhand", "offhand", "s1243" })
    Ed.SetShowUnlearned(true)
    T.deq(trayIds(Ed), { 11, 12, 13, 21, 22, "s2687", "mainhand", "offhand", "s1243", 14, "s12292" })
    Ed.SetShowUnlearned(false)
    Ed.SetShowGroup(false)
    -- A group buff already placed stays listed (as known) with the switch off.
    D.AddPiece(D.Current(), "s1243", "icon", 300, 0)
    local e
    for _, x in ipairs(Ed.Spells()) do if x.id == "s1243" then e = x end end
    T.truthy(e and e.placed and not e.unlearned, "placed: still listed, not as unknown")
    D.RemovePiece(D.Current(), "s1243")
    Ed.Choose("s2687")
    T.eq(Ed.Pending().kind, "icon")
    Ed.Pick("bar")
    T.eq(D.Current().pieces["s2687"].shape, "bar")
    T.eq(Ed.Selected(), "s2687")
    -- A layout copied from another class: a key this class has no spell for.
    AB.CdmSpells.MAGE = { { 1953, cd = true } }   -- Blink
    AB.CdmCustom.Forget()
    D.AddPiece(D.Current(), "s1953", "icon", 200, 0)
    local last = Ed.Spells()[#Ed.Spells()]
    T.eq(last.id, "s1953"); T.truthy(last.unlearned, "listed as not known")
    Ed.Changed(); stub.RunTimers()
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: a spell of ours with a cooldown and a buff picks which one it shows", function()
    local DUI, AB, Ed, D = edWorld()
    customTray(AB, { { 2687, cd = true, aura = true }, { 6673, aura = true } }, { [2687] = true, [6673] = true })
    Ed.Choose("s2687"); Ed.Pick("icon"); stub.RunTimers()
    local row
    for _, r in ipairs(AB.CdmCard.ROWS.show) do
        if r.item and r.item.key == "cdm.card.ownTrack" then row = r end
    end
    T.truthy(row, "a Track row on the Show tab")
    local set = D.Current()
    T.truthy(row.show(set, "s2687", set.pieces["s2687"]), "shown for a spell with both")
    T.eq(row.item.get(), "cooldown")
    row.item.set("aura"); stub.RunTimers()
    T.eq(set.pieces["s2687"].track, "aura")
    T.eq(AB.CdmRows.DrawnBy("s2687"), "aura icon", "the live layout follows")
    Ed.Choose("s6673"); Ed.Pick("icon")
    T.truthy(row.show(set, "s6673", set.pieces["s6673"]), "a buff can pick too")
    row.item.set("both"); stub.RunTimers()
    T.eq(AB.CdmRows.DrawnBy("s6673"), "aura and cooldown icon", "Both: its buff over its cooldown")
    D.AddPiece(set, 11, "icon", 0, -100)
    T.falsy(row.show(set, 11, set.pieces[11]), "the game's spells have their own pick")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm card: every look setting is on Look (the spell's, then the whole group's); Group is placement and behavior", function()
    local DUI, AB, Ed, D = edWorld()
    local Card = AB.CdmCard
    local function keys(t)
        local out = {}
        for _, r in ipairs(Card.ROWS[t]) do if r.item then out[r.item.key] = true end end
        return out
    end
    local look, group = keys("look"), keys("chain")
    for _, k in ipairs({ "size", "width", "height", "color", "back", "backColor", "backGradient", "icon", "text", "time" }) do
        T.truthy(look["cdm.card.chain." .. k], "Look has the group's " .. k)
        T.isnil(group["cdm.card.chain." .. k], "Group doesn't have " .. k)
    end
    for _, k in ipairs({ "cdm.card.chain.tether", "cdm.card.chain.spacing", "cdm.card.chain.grow", "cdm.card.chain.combat",
                         "cdm.card.chain.collapse", "cdm.card.alignAcross", "cdm.card.alignDown", "cdm.card.gap", "cdm.card.unhook" }) do
        T.truthy(group[k], "Group has " .. k)
        T.isnil(look[k], "Look doesn't have " .. k)
    end
    -- One spell alone: the group's sizes would only repeat its own.
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    local size
    for _, r in ipairs(Card.ROWS.look) do if r.item and r.item.key == "cdm.card.chain.size" then size = r end end
    T.falsy(size.show(set, 11, set.pieces[11]), "alone: no group icon size")
    D.AddPiece(set, 12, "icon", 40, 0)
    T.truthy(D.Hook(set, 12, 11, "right"))
    T.truthy(size.show(set, 11, set.pieces[11]), "two: the group's icon size")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm rows: an icon shows the key that casts it, once asked, and follows the binding", function()
    local DUI, AB, ess = rowsWorld()
    local D, R, CD = AB.CdmData, AB.CdmRows, AB.Cooldowns
    local set = D.Current()
    D.AddChain(set, { 11, 13 }, "icon", 0, 0)
    stub.slots[2] = { texture = "t", spellID = 1011 }
    -- The bar holds another rank: the same name still finds the key.
    AB.CdmOwn.Look = function(id) if id == 11 then return "Slam", "t" end end
    C_Spell.GetSpellName = function(id) return id == 1011 and "Slam" or nil end
    stub.bindings["ACTIONBUTTON2"] = { "Q" }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()
    R.Refresh(); stub.RunTimers()
    local l = CD.KeyLabel(ess[1])
    T.falsy(l and l:IsShown(), "off by default")

    DUI:Set("ActionBars", "cdmKeybinds", true)
    R.Refresh(); stub.RunTimers()
    l = CD.KeyLabel(ess[1])
    T.truthy(l and l:IsShown(), "on: the label shows")
    T.eq(l.text:GetText(), "Q")
    T.falsy(CD.KeyLabel(ess[3]) and CD.KeyLabel(ess[3]):IsShown(), "a spell on no bar shows none")

    stub.bindings["ACTIONBUTTON2"] = { "E" }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()
    T.eq(l.text:GetText(), "E", "a new binding shows without a layout pass")

    -- A druid's form change: the bar's page lands on the button a moment after the
    -- form event, through its state driver, with no event of its own. The key
    -- moves with it.
    local btn = AB.Buttons.All()[2]
    T.eq(AB.Buttons.SlotOf(btn), 2)
    stub.slots[2] = { texture = "t", spellID = 1013 }
    stub.slots[74] = { texture = "t", spellID = 1011 }
    stub.bindings["ACTIONBUTTON2"] = nil
    stub.bindings["ACTIONBUTTON3"] = { "R" }
    AB.Keys.OnEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    AB.Buttons.All()[3]:SetAttribute("action", 74)
    stub.RunTimers()
    T.eq(l.text:GetText(), "R", "the key follows the page the button got after the form event")
    stub.bindings["ACTIONBUTTON3"] = nil
    stub.bindings["ACTIONBUTTON2"] = { "E" }
    AB.Buttons.All()[3]:SetAttribute("action", 3)
    stub.slots[2] = { texture = "t", spellID = 1011 }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()

    D.SetLook(set, 11, "keyShown", false)
    D.Changed(); R.Refresh(); stub.RunTimers()
    T.falsy(l:IsShown(), "the spell's own switch beats the page's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A player's /cdm stayed empty except for the grid. A bar piece's preview set
-- text on its key label, which has no font until an icon styles it, so the client
-- refused and the draw stopped before the banner and the tray.
T.test("cdm editor: a bar in the layout draws, with the tray and no key label", function()
    local DUI, AB, Ed, D = edWorld()
    stub.FontRule = true
    local ok, err = pcall(function()
        D.AddPiece(Ed.Set(), 21, "bar", 0, 0)
        Ed.Changed()
    end)
    stub.FontRule = nil
    T.truthy(ok, tostring(err))
    T.truthy(Ed.Tray():GetHeight() > 0, "the tray got its size")

    D.AddPiece(Ed.Set(), 11, "icon", 100, 0)
    DUI:Set("ActionBars", "cdmKeybinds", true)
    AB.CdmOwn.Look = function() return "Slam", "t" end
    stub.slots[2] = { texture = "t", spellID = 1011 }
    _G.C_Spell.GetSpellName = function() return "Slam" end
    stub.bindings["ACTIONBUTTON2"] = { "Q" }
    AB.Keys.OnEvent("UPDATE_BINDINGS"); stub.RunTimers()
    Ed.Changed()
    D.SetShape(Ed.Set(), 11, "bar")
    Ed.Changed()
    local kids = Ed.PreviewOf(11)
    T.falsy(kids.key:IsShown(), "an icon turned bar drops its key")
    Ed.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Add by ID (the tray's button, like EllesmereUI's Custom Spell ID / Item ID): a
-- spell the tray has is that one, any other spell is "s<id>", and an item with a
-- use is "i<id>", timed by the item's own cooldown. The fake game has no items,
-- so this test lends C_Item and C_Container the calls and takes them back.
-- The menu used to show two blank rows.
T.test("cdm editor: the tray's hint sits clear of the Add by ID button", function()
    local DUI, AB, Ed = edWorld()
    local hint, byID = Ed.TrayHint(), Ed.PillButton("byID")
    T.eq(stub.Text(hint), DUI.L["Click or drag a spell."])
    local found
    for i = 1, hint:GetNumPoints() do
        local p, rel, rp, x = hint:GetPoint(i)
        if p == "LEFT" then found = (rel == byID and rp == "RIGHT" and x > 0) end
    end
    T.truthy(found, "its left edge starts past the button, so a wide font wraps it instead of covering it")
end)

T.test("cdm editor: the Add by ID menu names its two rows", function()
    local DUI, AB, Ed = edWorld()
    local W = DUI.Widgets
    local owner = CreateFrame("Button", nil, UIParent)
    owner:SetSize(80, 20)
    Ed.OpenAddMenu(owner)
    T.eq(W.MenuRow(1).text:GetText(), DUI.L["Spell ID"])
    T.eq(W.MenuRow(2).text:GetText(), DUI.L["Item ID"])
    W.CloseMenu()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm editor: add a spell or an item by its ID; an item times its own cooldown", function()
    local DUI, AB, Ed, D = edWorld()
    customTray(AB, { { 6673, 5242, 6192, aura = true } }, { [6673] = true, [9999] = true })
    local C = AB.CdmCustom
    local ITEMS = {
        [5512] = { spell = 6262, name = "Healthstone", icon = "hs", cached = true, count = 1, used = true },
        [7001] = { spell = 7002, name = "Trinket", icon = "tr", cached = true, count = 1 },
        [2589] = { name = "Linen Cloth", icon = "cloth", cached = true },
        [9000] = { spell = 9001, name = "Slow Item", icon = "slow", cached = false },
    }
    local cd = { start = 0, dur = 0 }
    local saved = { spell = C_Item.GetItemSpell, inst = C_Item.GetItemInfoInstant, name = C_Item.GetItemNameByID,
        cached = C_Item.IsItemDataCachedByID, load = C_Item.RequestLoadItemDataByID, usable = C_Item.IsUsableItem,
        consumable = C_Item.IsConsumableItem, stack = C_Item.GetItemMaxStackSizeByID, count = C_Item.GetItemCount,
        container = _G.C_Container }
    C_Item.GetItemSpell = function(id) local it = ITEMS[id]; if it and it.cached and it.spell then return "Use", it.spell end end
    C_Item.GetItemInfoInstant = function(id) local it = ITEMS[id]; if it then return id, "", "", "", it.icon end end
    C_Item.GetItemNameByID = function(id) local it = ITEMS[id]; return it and it.cached and it.name or nil end
    C_Item.IsItemDataCachedByID = function(id) return ITEMS[id] ~= nil and ITEMS[id].cached == true end
    local asked = {}
    C_Item.RequestLoadItemDataByID = function(id) asked[id] = true end
    C_Item.IsUsableItem = function(id) local it = ITEMS[id]; return (it and (it.count or 0) > 0) or false, false end
    C_Item.IsConsumableItem = function(id) return ITEMS[id] ~= nil and ITEMS[id].used == true end
    C_Item.GetItemMaxStackSizeByID = function(id) return ITEMS[id] and (ITEMS[id].used and 20 or 1) end
    C_Item.GetItemCount = function(id) return ITEMS[id] and ITEMS[id].count or 0 end
    _G.C_Container = { GetItemCooldown = function() return cd.start, cd.dur, 1 end }
    local ok, err = pcall(function()
        -- The keys.
        T.truthy(C.Is("i5512")); T.eq(C.ItemOf("i5512"), 5512); T.isnil(C.ItemOf("s5512")); T.isnil(C.ItemOf(11))
        -- Spells: wrong ones say why, and one the tray lists is that one.
        T.deq({ Ed.KeyForID("spell", "abc") }, { nil, "number" })
        _G.C_Spell.GetSpellName = function(sid)
            if sid == 777 then return nil end
            if sid == 6673 or sid == 5242 or sid == 6192 then return "Battle Shout" end
            return "Spell " .. sid
        end
        T.deq({ Ed.KeyForID("spell", "777") }, { nil, "spell" })
        T.eq(Ed.KeyForID("spell", "6192"), "s6673", "a rank of the list's family: that family")
        T.eq(Ed.KeyForID("spell", " 111 "), 11, "the game's piece (same name) wins")
        T.eq(Ed.KeyForID("spell", "9999"), "s9999", "anything else: a spell of its own")
        T.truthy(C.IsAdded("s9999")); T.falsy(C.IsAdded("s6673"))
        T.truthy(C.CanTrack("s9999"), "cooldown or buff: the card's What it shows picks")
        T.eq(C.Track("s9999"), "aura", "no real cooldown: its buff")
        T.truthy(C.Entry("s9999"), "known: drawn")
        AB.CdmSpells.MAGE = { { 1953, cd = true } }   -- Blink
        C.Forget()
        T.isnil(C.Entry("s1953"), "another class's spell, not known: nothing to draw")
        T.truthy(C.Entry("s8888"), "on no class's list: someone else's buff on you, drawn")
        T.eq(C.Track("s8888"), "aura")
        -- Items.
        T.deq({ Ed.KeyForID("item", "1") }, { nil, "item" })
        T.deq({ Ed.KeyForID("item", "2589") }, { nil, "use" }, "nothing to use, nothing to time")
        T.deq({ Ed.KeyForID("item", "9000") }, { nil, "wait" }, "not loaded yet")
        T.truthy(asked[9000], "asked to load")
        T.eq(Ed.KeyForID("item", "5512"), "i5512")
        T.deq({ C.Look("i5512") }, { "Healthstone", "hs" })
        T.eq(C.SpellOf("i5512"), 6262, "its use spell, for its buff")
        T.truthy(C.Entry("i5512"), "an item is always drawn")
        T.eq(C.Track("i5512"), "cooldown")
        -- Its cooldown is plain, with the global cooldown left out.
        T.falsy((C.ItemCooldown("i5512")), "ready")
        cd.start, cd.dur = GetTime(), 1
        T.falsy((C.ItemCooldown("i5512")), "a global cooldown isn't one")
        cd.start, cd.dur = GetTime() - 10, 120
        local on, d = C.ItemCooldown("i5512")
        T.truthy(on); T.truthy(d, "a duration object for the swipe and bar")
        -- Placed: the icon wears the item's cooldown, and the effects read it too.
        Ed.Choose("i5512"); Ed.Pick("icon")
        T.truthy(D.Current().pieces["i5512"], "placed")
        local e
        for _, x in ipairs(Ed.Spells()) do if x.id == "i5512" then e = x end end
        T.truthy(e and e.placed and not e.unlearned, "in the tray while placed")
        Ed.Close()
        AB.CdmRows.Refresh(); stub.RunTimers()
        local f = AB.CdmOwn.Frame("i5512")
        T.truthy(f and f:IsShown(), "our icon draws it")
        T.truthy(AB.CdmEffects.OnCooldown(f), "the effects see the item's cooldown")
        T.eq(f.ChargeCount.Current:GetText(), "1", "how many you carry")
        ITEMS[5512].count = 3
        stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
        T.eq(f.ChargeCount.Current:GetText(), "3", "follows the bags")
        ITEMS[5512].count = 0
        stub.FireEvent("BAG_UPDATE_DELAYED"); stub.RunTimers()
        T.eq(f.ChargeCount.Current:GetText(), "0", "out: 0, as the game's buttons say")
        T.isnil(C.ItemCount("i7001"), "a trinket that isn't used up: no count")
        T.isnil(C.ItemCount("s9999"), "a spell: no count")
        T.deq({ C.ItemUsable("i5512") }, { false, false }, "none left: not usable (grays)")
    end)
    C_Item.GetItemSpell, C_Item.GetItemInfoInstant, C_Item.GetItemNameByID = saved.spell, saved.inst, saved.name
    C_Item.IsItemDataCachedByID, C_Item.RequestLoadItemDataByID, C_Item.IsUsableItem = saved.cached, saved.load, saved.usable
    C_Item.IsConsumableItem, C_Item.GetItemMaxStackSizeByID, C_Item.GetItemCount = saved.consumable, saved.stack, saved.count
    _G.C_Container = saved.container
    stub.knownSpells = {}
    T.truthy(ok, tostring(err))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm api: pieces are frames plugins find by spell, with ready and cooldown events", function()
    local DUI, AB, set, ess = fxWorld()
    local cds = withCooldowns(ess)
    cds[111] = { duration = 0 }
    pass(AB)
    local API = DUI.API
    local f = API.GetCooldownPiece(111)
    T.eq(f, pieceFrame(1, 11), "the piece's own frame")
    local info = API.CooldownPieceInfo(f)
    T.eq(info.key, "11"); T.eq(info.spellID, 111); T.eq(info.shape, "icon")
    local listed = {}
    for frame, key in API.Frames("cdmpiece") do listed[key] = frame end
    T.eq(listed["11"], f); T.truthy(listed["12"]); T.truthy(listed["21"])
    T.truthy(API.Attach(f), "a holder to draw on")
    T.eq(API.Glow(f, true, 0, 1, 0), true, "a glow of the plugin's")
    local log = {}
    API.On("CooldownStarted", function(sid, key) log[#log + 1] = "start:" .. tostring(sid) .. ":" .. tostring(key) end)
    API.On("CooldownReady", function(sid, key) log[#log + 1] = "ready:" .. tostring(sid) .. ":" .. tostring(key) end)
    cds[111] = { duration = 8, isOnGCD = false }
    pass(AB)
    T.eq(log[1], "start:111:11")
    ess[1].Cooldown:GetScript("OnCooldownDone")(ess[1].Cooldown)
    T.eq(log[2], "ready:111:11")
    local gone
    API.On("FrameRemoved", function(kind, frame, key) if kind == "cdmpiece" then gone = key end end)
    unplace(AB.CdmData, set, 12)
    pass(AB)
    T.eq(gone, "12", "an unplaced piece is gone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm api: a piece's state, its buff, usable and proc moments, and one watcher per spell (icon and bar)", function()
    local DUI, AB, set, ess, bars = fxWorld()
    DUI.DB.General().motion = false
    withCategories({ [0] = { 11 }, [3] = { 21 } }, { [0] = { 11 }, [3] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = 100 + id, selfAura = false, hasAura = true }
    end
    _G.GetSpellBaseCooldown = function(sid) return sid == 111 and 6000 or 0 end
    C_Spell.GetSpellInfo = function() return { castTime = 2000 } end
    AB.CdmSpells.FACTS[111], AB.CdmSpells.FACTS[121] = { cd = 6, lasts = 18 }, { lasts = 18 }
    AB.CdmOwn.Forget()
    local cds = withCooldowns(ess)
    cds[111] = { duration = 0 }
    local can = {}
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, false end
    pass(AB)
    local API = DUI.API
    T.eq(API.major, 1); T.truthy(API.minor >= 14, "the CDM state calls are 1.14")
    local log = {}
    local function heard(what) for _, l in ipairs(log) do if l == what then return true end end return false end
    for _, ev in ipairs({ "CooldownBuffUp", "CooldownBuffDown", "CooldownUsable", "CooldownProc" }) do
        T.truthy(API.On(ev, function(sid, key, on)
            log[#log + 1] = ev .. ":" .. tostring(sid) .. ":" .. tostring(key) .. (on ~= nil and (":" .. tostring(on)) or "")
        end), ev .. " is an event")
    end

    local s = API.CooldownState(111)
    T.eq(s.key, "11"); T.eq(s.spellID, 111); T.eq(s.shape, "icon")
    T.eq(s.ready, true, "off cooldown"); T.eq(s.onCooldown, false)
    T.eq(s.usable, false, "not castable yet"); T.eq(s.proc, false)
    T.eq(API.CooldownState(API.GetCooldownPiece(111)).key, "11", "by its frame too")
    T.isnil(API.CooldownState(999), "a spell with no piece")
    T.isnil(API.CooldownState({}), "a frame that isn't a piece")

    -- Usable: the condition coming true, off cooldown.
    can[111] = true
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    T.truthy(heard("CooldownUsable:111:11"), "usable")
    T.eq(API.CooldownState(111).usable, true)

    -- A proc: the game's spell alert on the item.
    ActionButtonSpellAlertManager:ShowAlert(ess[1])
    T.truthy(heard("CooldownProc:111:11:true"), "a proc")
    T.eq(API.CooldownState(111).proc, true)
    ActionButtonSpellAlertManager:HideAlert(ess[1])
    T.truthy(heard("CooldownProc:111:11:false"), "and its end")

    -- Buff up and down, as the game's own item says: icon and bar.
    for _, case in ipairs({ { 111, "11", ess[1], "icon" }, { 121, "21", bars[1], "bar" } }) do
        local sid, key, item, shape = case[1], case[2], case[3], case[4]
        local function up(on)
            if shape == "bar" then item:SetIsActive(on) else item:SetAura(on) end
            stub.RunTimers()
        end
        up(false); pass(AB)
        up(true); pass(AB)
        T.truthy(heard("CooldownBuffUp:" .. sid .. ":" .. key), shape .. ": buff up")
        T.eq(API.CooldownState(sid).buffUp, true, shape .. ": state says up")
        T.eq(API.CooldownState(sid).shape, shape)
        up(false); pass(AB)
        T.truthy(heard("CooldownBuffDown:" .. sid .. ":" .. key), shape .. ": buff down")
        if shape == "icon" then
            T.eq(API.CooldownState(sid).buffUp, false, "icon: state says down, its cooldown still showing")
        else
            T.isnil(API.CooldownState(sid), "bar: a buff bar hides while down, so there's no piece to ask")
        end
    end

    -- Should the usable answer go secret, the state says it can't tell (nil), never a secret.
    stub.EnterCombat()
    C_Spell.IsSpellUsable = function() return stub.Secret(true), stub.Secret(false) end
    stub.FireEvent("SPELL_UPDATE_USABLE"); stub.RunTimers()
    for k, v in pairs(API.CooldownState(111)) do
        T.falsy(DUI.IsSecret(v), k .. " is never secret")
    end
    T.isnil(API.CooldownState(111).usable, "can't tell")
    stub.LeaveCombat()
    C_Spell.IsSpellUsable = function(sid) return can[sid] == true, false end

    -- One watcher, by any rank of the spell.
    local Custom = AB.CdmCustom
    local keyOf = Custom.KeyOfSpell
    Custom.KeyOfSpell = function(sid) if sid == 111 or sid == 311 then return "s111" end return keyOf(sid) end
    local me = API.For("CdmWatcher")
    local seen = {}
    local handle = me.WatchCooldown(311, {
        started = function(sid, key) seen[#seen + 1] = "started:" .. sid .. ":" .. key end,
        ready = function(sid, key) seen[#seen + 1] = "ready:" .. sid .. ":" .. key end,
        changed = function(state) seen[#seen + 1] = "changed:" .. tostring(state and state.ready) end,
    })
    T.truthy(handle, "a handle")
    T.eq(seen[1], "changed:true", "the state at once")
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    T.eq(seen[2], "started:111:11", "started, watched by another rank")
    T.eq(seen[3], "changed:false")
    ess[1].Cooldown:GetScript("OnCooldownDone")(ess[1].Cooldown)
    T.eq(seen[4], "ready:111:11")
    API.Off(handle)
    local n = #seen
    cds[111] = { duration = 8, isOnGCD = false }
    cdEvent()
    T.eq(#seen, n, "off stops every handler")
    T.isnil(me.WatchCooldown(311, { nope = print }), "an unknown handler name")
    T.isnil(me.WatchCooldown(311, {}), "no handlers")
    T.isnil(me.WatchCooldown(nil, { ready = print }), "nothing to watch")
    Custom.KeyOfSpell = keyOf

    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm api: the editor opens for a plugin out of combat only", function()
    local DUI, AB = fxWorld()
    local API = DUI.API
    T.eq(API.OpenCooldownEditor(), true, "opens")
    T.truthy(AB.CdmEditor.IsOpen())
    AB.CdmEditor.Close()
    stub.EnterCombat()
    T.eq(API.OpenCooldownEditor(), false, "not in a fight")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The first-time tour (CdmGuide.lua) runs on the main tour's card over the editor.
local function edges(f, l, b, r, t)
    f.GetLeft = function() return l end
    f.GetBottom = function() return b end
    f.GetRight = function() return r end
    f.GetTop = function() return t end
end
local function tick() DaylightUITour:GetScript("OnUpdate")(DaylightUITour, 1) end

T.test("cdm tour: the first open walks through adding a spell and making a group", function()
    local DUI, AB, Ed, D = edWorld()
    local G = AB.CdmGuide
    DUI:Set("general", "motion", false)   -- the card lands at once, no glide
    edges(Ed.Tray(), 400, 16, 1000, 140)
    stub.RunTimers()
    T.eq(G.Running(), true, "it comes with the first open")
    T.eq(DUI.Tour.StepId(), "add")
    T.eq(DUI.Tour.Lit(), Ed.Tray(), "the tray lit")
    T.eq(DaylightUITour:IsMouseEnabled(), false, "the mouse reaches the editor, so each step can be tried")
    T.eq(DUI.Tour.panes[1].__color[4], DUI.Tour.DIM, "the same dim as the main tour")
    T.eq(DUI.Tour.card.skip.text:GetText(), "Skip tour", "worded like the main tour")
    Ed.Choose(11)
    edges(Ed.Chooser(), 500, 300, 740, 396)
    tick()
    T.eq(DUI.Tour.Lit(), Ed.Chooser(), "the light follows to the Icon or Bar question")
    Ed.Pick("icon")
    edges(Ed.PreviewOf(11), 900, 500, 940, 540)
    edges(AB.CdmCard.Frame(), 960, 200, 1340, 700)
    tick(); stub.RunTimers()
    T.eq(DUI.Tour.StepId(), "group", "a spell placed: on to groups")
    T.eq(DUI.Tour.Lit(), Ed.PreviewOf(11), "the new spell lit")
    local _, _, _, x, top = DUI.Tour.card:GetPoint(1)
    local h = DUI.Tour.card:GetHeight()
    local clear = x + DUI.Tour.W <= 960 or x >= 1340 or top <= 200 or top - h >= 700
    T.truthy(clear, "the tour's card keeps clear of the spell's card")
    Ed.SetAttach(11, "right"); Ed.Choose(12); Ed.Pick("icon")
    tick(); stub.RunTimers()
    T.eq(DUI.Tour.StepId(), "card", "a spell hooked on: on to the card")
    DUI.Tour.Next(); stub.RunTimers()
    T.eq(DUI.Tour.StepId(), "top")
    DUI.Tour.Next()
    T.eq(G.Running(), false, "Done ends it")
    T.eq(DUI.DB.Root().cdmGuideSeen, true)
    Ed.Close(); Ed.Open(); stub.RunTimers()
    T.eq(G.Running(), false, "once per account")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm tour: closing the editor ends it; /cdm tour brings it back; a layout skips it", function()
    local DUI, AB, Ed, D = edWorld()
    local G = AB.CdmGuide
    stub.RunTimers()
    T.eq(G.Running(), true)
    Ed.Close()
    T.eq(G.Running(), false, "gone with the editor")
    T.eq(DaylightUITour:IsMouseEnabled(), false)
    SlashCmdList.DAYLIGHTUICDM("tour"); stub.RunTimers()
    T.eq(Ed.IsOpen(), true, "/cdm tour opens the editor")
    T.eq(G.Running(), true, "with the tour")
    DUI.Tour.OnKey("ESCAPE")
    T.eq(G.Running(), false, "Escape skips it")
    T.truthy(string.find(DUI.Tour.toast.text:GetText(), "/cdm tour", 1, true), "and says how to see it again")
    T.eq(Ed.IsOpen(), true, "the editor stays")
    Ed.Close()
    DUI.DB.Root().cdmGuideSeen = nil
    -- a class, so the layout is saved as a profile
    stub.units.player = stub.units.player or { isPlayer = true, name = "Tester" }
    stub.units.player.class = "WARRIOR"
    D.Ensure(D.CurrentIndex())
    D.AddPiece(D.Current(), 11, "icon", 0, 0)
    Ed.Open(); stub.RunTimers()
    T.eq(G.Running(), false, "a player with a layout already knows the way")
    T.eq(DUI.DB.Root().cdmGuideSeen, true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm tour: a fight ends it with the editor", function()
    local DUI, AB, Ed = edWorld()
    stub.RunTimers()
    T.eq(AB.CdmGuide.Running(), true)
    stub.EnterCombat()
    T.eq(AB.CdmGuide.Running(), false)
    T.eq(Ed.IsOpen(), false)
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: a bar in the layout wears the Cooldown Manager's bar animation, a game bar outside it doesn't", function()
    local DUI, AB, set, ess, bars = fxWorld()
    local Fx = DUI.BarFx
    T.eq(Fx.StyleOf(bars[1].Bar), "flow", "a new setup starts it in Flow")
    DUI:Set("ActionBars", "cdmBarFx.style", "none")
    T.isnil(Fx.StyleOf(bars[1].Bar), "None stills it")
    DUI:Set("ActionBars", "cdmBarFx.style", "flow")
    T.eq(Fx.StyleOf(bars[1].Bar), "flow", "the game's bar in a bar block")
    T.isnil(Fx.StyleOf(bars[2].Bar), "a game bar outside the blocks keeps the game's look")
    -- A cooldown laid out as a bar is drawn by a bar of Daylight UI's own.
    set.pieces[11].shape = "bar"
    pass(AB)
    local own = AB.CdmBars.CooldownFrame(11)
    T.truthy(own, "drawn as a cooldown bar")
    T.eq(Fx.StyleOf(own.Bar), "flow", "a cooldown bar too, icon or bar alike")
    DUI:Set("ActionBars", "cdmBarFx.style", "tide")
    T.eq(Fx.StyleOf(own.Bar), "tide", "a new pick reaches it")
    unplace(AB.CdmData, set, 21)
    pass(AB)
    T.isnil(Fx.StyleOf(bars[1].Bar), "taken out of the layout: back to the game's look")
end)

T.test("cdm bars: each bar can have its own animation, unset follows the shared one", function()
    local DUI, AB, set, ess, bars = fxWorld()
    local Fx, Data = DUI.BarFx, AB.CdmData
    set.pieces[11].shape = "bar"
    pass(AB)
    local own = AB.CdmBars.CooldownFrame(11)
    T.eq(Fx.StyleOf(own.Bar), "flow", "unset: the shared pick")
    T.truthy(Data.SetSpellValue(set, 11, "fxStyle", "tide"), "a bar takes its own style")
    Fx.Refresh()
    T.eq(Fx.StyleOf(own.Bar), "tide", "its own pick wins")
    T.eq(Fx.StyleOf(bars[1].Bar), "flow", "the other bars keep the shared one")
    T.truthy(Data.SetSpellValue(set, 11, "fxStyle", "none"))
    Fx.Refresh()
    T.isnil(Fx.StyleOf(own.Bar), "None stills just this bar")
    T.truthy(Data.SetSpellValue(set, 11, "fxStyle", "group"))
    T.isnil(set.pieces[11].fxStyle, "back to the shared one saves nothing")
    Fx.Refresh()
    T.eq(Fx.StyleOf(own.Bar), "flow")
    T.eq(Data.SetSpellValue(set, 11, "fxStyle", "sparkles"), false, "an unknown style is refused")
    T.eq(Data.SetSpellValue(set, 21, "fxSpeed", 2), set.pieces[21].shape == "bar", "bars only")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- One piece per totem element (fire, earth, water, air): it shows whichever totem
-- stands in its slot, then a cooldown totem's cooldown, and hides with nothing to show.
local function elementWorld()
    local DUI, AB, set, w = barsWorld()
    stub.SetUnits({ player = { class = "SHAMAN" } })
    set = AB.CdmData.Current()
    AB.CdmSpells.SHAMAN = {
        { 2484, cd = true, aura = true },       -- Earthbind
        { 8071, 8154, aura = true },            -- Stoneskin
        { 8512, 10613, aura = true },           -- Windfury
        { 3599, 6363, aura = true },            -- Searing
    }
    stub.knownSpells = { [2484] = true, [8071] = true, [8154] = true, [8512] = true, [10613] = true,
        [3599] = true, [6363] = true }
    C_Spell.GetSpellTexture = function(sid) return "tex" .. tostring(sid) end
    AB.CdmCustom.Forget()
    AB.CdmOwn.Forget()
    return DUI, AB, set, w
end

local elementCasts = 0
local function dropTotem(slot, sid, combat)
    if combat then stub.combat = true end
    stub.totems[slot] = sid and { spell = sid, duration = { sid = sid } } or nil
    if sid then
        elementCasts = elementCasts + 1
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "element-" .. elementCasts, sid)
    end
    stub.FireEvent("PLAYER_TOTEM_UPDATE", slot); stub.RunTimers()
    if combat then stub.combat = false end
end

T.test("cdm custom: a shaman gets a piece per totem element, with the element's name and icon", function()
    local AB, C = customWorld("SHAMAN")
    AB.CdmSpells.SHAMAN = {
        { 2484, cd = true, aura = true },       -- Earthbind
        { 8071, 8154, aura = true },            -- Stoneskin
        { 3599, aura = true },                  -- Searing
    }
    stub.knownSpells = { [2484] = true, [8071] = true, [3599] = true }
    C.Forget()
    for _, k in ipairs({ "fire", "earth", "water", "air" }) do T.truthy(C.Is(k), k) end
    T.eq((C.Look("earth")), "Earth totem")
    T.eq(select(2, C.Look("earth")), C.TOTEM_ELEMENTS.earth.icon, "the element's icon, not one totem's")
    T.eq(C.TOTEM_ELEMENTS.air.icon, "Interface/Icons/INV_Elemental_Primal_Air")
    T.eq(AB.CdmEditor.SpellTexture("earth"), C.TOTEM_ELEMENTS.earth.icon, "the editor shows the element")
    local tray = {}
    for _, e in ipairs(C.Tray()) do tray[e.id] = true end
    T.truthy(tray.earth, "earth in the tray"); T.truthy(tray.fire, "fire in the tray")
    T.falsy(tray.water, "no water totem known: not offered")
    local r = C.Ranks("earth")
    T.truthy(r[2484] and r[8071] and r[8154], "every earth totem, cooldown totems too")
    T.falsy(r[3599], "not a fire totem")
    T.falsy(C.CanTrack("earth"), "no What it shows")
    T.eq(C.KeyOfSpell(8071), "s8071", "each totem keeps its own piece")
    T.eq(select(2, C.Totem(8154)), "s8071")
    T.isnil(C.Totem(2484), "a cooldown totem stays off the timed list")
    T.eq(C.SlotOf(2484), 2); T.eq(C.SlotOf(8154), 2); T.eq(C.SlotOf(3599), 1)
    local _, W = customWorld("PALADIN")
    T.isnil(W.Family("earth"), "only shamans")
    stub.knownSpells = {}
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: an element piece follows the totem in its slot (Stoneskin, then Earthbind)", function()
    local DUI, AB, set = elementWorld()
    local D, R, Own, Fx, C = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmEffects, AB.CdmCustom
    D.AddPiece(set, "earth", "icon", 0, 0)
    D.AddPiece(set, "s8071", "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(Own.Track("earth", set.pieces.earth), "both", "Totem and buff")
    T.eq(R.DrawnBy("earth"), "totem and buff icon")
    local icon = Own.Frame("earth")
    T.eq(icon.Icon:GetTexture(), C.TOTEM_ELEMENTS.earth.icon, "nothing yet: the element's icon")
    T.isnil(icon.Cooldown.__duration)
    T.truthy(Fx.Gone(icon), "empty slot: hidden")
    dropTotem(2, 8154)
    T.eq(icon.Icon:GetTexture(), "tex8154", "Stoneskin's icon, its standing rank")
    T.eq(icon.Cooldown.__duration, stub.totems[2].duration, "Stoneskin's time")
    T.falsy(Fx.Gone(icon), "shown")
    local r, g, b = DUI.Style.Accent()
    local tint = icon.Cooldown.__swipeColor
    T.truthy(tint and tint[1] == r and tint[2] == g and tint[3] == b, "totem time: the accent swipe")
    T.eq(Own.Frame("s8071").Cooldown.__duration, stub.totems[2].duration, "Stoneskin's own piece too")
    dropTotem(2, 2484)
    T.eq(icon.Icon:GetTexture(), "tex2484", "Earthbind took the slot")
    T.eq(icon.Cooldown.__duration, stub.totems[2].duration, "Earthbind's time")
    T.isnil(Own.Frame("s8071").Cooldown.__duration, "Stoneskin's piece: not Earthbind's time")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: an element piece dims under a known totem buff and grays per Gray out (Windfury)", function()
    local DUI, AB, set = elementWorld()
    local D, R, Own, A = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmAuras
    DUI.DB.Character().cdmAuraIDs = { [8512] = { [8515] = true } }
    D.AddPiece(set, "air", "icon", 0, 0)
    D.AddPiece(set, "fire", "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.truthy(A.SpellIDs("air")[8515], "watches the taught buff")
    dropTotem(4, 10613)
    local icon = Own.Frame("air")
    T.truthy(A.Frame("air") and A.Frame("air"):IsShown(), "the buff's button over the icon")
    T.eq(icon.Icon:GetAlpha(), Own.TOTEM_DIM, "dimmed while you lack the buff")
    T.falsy(icon.Icon:IsDesaturated(), "Gray out unset: in color")
    T.truthy(D.SetSpellValue(set, "air", "desat", "grey"))
    R.Refresh(); stub.RunTimers()
    T.truthy(icon.Icon:IsDesaturated(), "Gray out: grayed while it stands")
    dropTotem(1, 6363)
    T.eq(Own.Frame("fire").Icon:GetAlpha(), 1, "a totem with no buff: just its time")
    T.eq(Own.Frame("fire").Cooldown.__duration, stub.totems[1].duration)
    DUI.DB.Character().cdmAuraIDs = nil
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: an element piece shows a cooldown totem's cooldown after it ends, then hides", function()
    local DUI, AB, set, w = elementWorld()
    local D, R, Own, Fx = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmEffects
    D.AddPiece(set, "earth", "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    local icon = Own.Frame("earth")
    w.cds[2484] = { isActive = true, isOnGCD = false, duration = 15 }
    w.durs[2484] = { cd = 2484 }
    dropTotem(2, 2484)
    T.falsy(icon.Icon:IsDesaturated(), "standing: in color")
    dropTotem(2, nil)
    T.eq(icon.Icon:GetTexture(), "tex2484", "Earthbind's icon")
    T.eq(icon.Cooldown.__duration, w.durs[2484], "its cooldown")
    T.truthy(icon.Icon:IsDesaturated(), "grayed on cooldown")
    T.deq(icon.Cooldown.__swipeColor, AB.Skin.SWIPE, "the skin's cooldown swipe, not the accent")
    T.falsy(Fx.Gone(icon), "shown while it cools down")
    w.cds[2484] = { isActive = false, isOnGCD = false, duration = 0 }
    stub.FireEvent("SPELL_UPDATE_COOLDOWN"); stub.RunTimers()
    T.truthy(Fx.Gone(icon), "ready and no totem: hidden")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: an empty element piece hides, and shows its element in test mode", function()
    local DUI, AB, set = elementWorld()
    local D, R, Own, Fx, C = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmEffects, AB.CdmCustom
    stub.knownSpells[5394] = true
    AB.CdmSpells.SHAMAN[#AB.CdmSpells.SHAMAN + 1] = { 5394, aura = true }   -- Healing Stream
    C.Forget()
    D.AddPiece(set, "water", "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    local icon = Own.Frame("water")
    T.truthy(Fx.Gone(icon), "nothing cast: hidden")
    T.eq(icon:GetAlpha(), 0)
    DUI.SetTestMode(true); stub.RunTimers()
    T.falsy(Fx.Gone(icon), "test mode: shown")
    T.eq(icon.Icon:GetTexture(), C.TOTEM_ELEMENTS.water.icon, "with the element's icon")
    DUI.SetTestMode(false); stub.RunTimers()
    T.truthy(Fx.Gone(icon), "test mode off: hidden again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: an element piece follows a totem dropped in a fight by its cast", function()
    local DUI, AB, set = elementWorld()
    local D, R, Own, Fx = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmEffects
    D.AddPiece(set, "earth", "icon", 0, 0)
    R.Refresh(); stub.RunTimers()
    dropTotem(2, 8154, true)
    local icon = Own.Frame("earth")
    T.eq(icon.Icon:GetTexture(), "tex8154", "the cast says which totem")
    T.eq(icon.Cooldown.__duration, stub.totems[2].duration)
    T.falsy(Fx.Gone(icon))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm: an element piece as a bar runs on the totem's time", function()
    local DUI, AB, set = elementWorld()
    local D, R = AB.CdmData, AB.CdmRows
    D.AddPiece(set, "earth", "bar", 0, 0)
    R.Refresh(); stub.RunTimers()
    T.eq(R.DrawnBy("earth"), "totem bar")
    local bar = AB.CdmBars.CooldownFrame("earth")
    T.isnil(bar.Timer.__duration, "nothing yet")
    dropTotem(2, 8071)
    T.eq(bar.Timer.__duration, stub.totems[2].duration, "the totem's time")
    T.eq(bar.Icon.Icon:GetTexture(), "tex8071", "the totem's icon")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
T.test("cdm: a slot update in a fight keeps the totems your casts placed", function()
    local DUI, AB, set = elementWorld()
    local D, R, Own, Fx = AB.CdmData, AB.CdmRows, AB.CdmOwn, AB.CdmEffects
    D.AddPiece(set, "fire", "icon", 0, 0)
    D.AddPiece(set, "earth", "icon", 40, 0)
    D.AddPiece(set, "s8071", "icon", 80, 0)
    R.Refresh(); stub.RunTimers()
    dropTotem(2, 8154)
    dropTotem(1, 6363)
    stub.Advance(5); stub.RunTimers()
    -- In a fight Searing runs out, and the game updates the earth slot as well.
    stub.combat = true
    stub.totems[1] = nil
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 1)
    stub.FireEvent("PLAYER_TOTEM_UPDATE", 2)
    stub.RunTimers()
    T.truthy(Fx.Gone(Own.Frame("fire")), "fire gone")
    T.falsy(Fx.Gone(Own.Frame("earth")), "earth still up")
    T.eq(Own.Frame("earth").Icon:GetTexture(), "tex8154", "still Stoneskin")
    T.eq(Own.Frame("s8071").Cooldown.__duration, stub.totems[2].duration, "Stoneskin's own piece keeps its time")
    stub.combat = false
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's own spell data (CdmSpells.FACTS, made by tools/make_cdm_facts.py)

-- The spell list's aura flag was read from tooltip text: "interrupting for 2 sec"
-- made Earth Shock a spell with a debuff, and Stealth, whose tooltip names no time,
-- one without a buff.
T.test("cdm facts: an interrupt's lockout is no debuff, and a buff the tooltip never timed is one", function()
    local AB, C = customWorld("SHAMAN")
    AB.CdmSpells.SHAMAN = { { 8042, 8044, cd = true, aura = true }, { 8050, 8052, cd = true, aura = true },
        { 8071, 8154, aura = true } }
    AB.CdmSpells.ROGUE = { { 1766, 1767, cd = true, aura = true }, { 1784, 1785, cd = true } }
    stub.knownSpells = { [8042] = true, [8050] = true, [8071] = true }
    realFacts()
    T.falsy(C.Family("s8042").aura, "Earth Shock: its 2 sec is the interrupt")
    T.isnil(C.KeyOfAuraSpell(8042), "so the game's Earth Shock icon gets no buff invented for it")
    T.truthy(C.Family("s8050").aura, "Flame Shock burns")
    T.truthy(C.Family("s8071").aura, "a totem's buff isn't in the spell's own data: the list's word stands")
    T.eq(C.Track("s8042"), "cooldown")
    stub.SetUnits({ player = { class = "ROGUE" } })
    stub.knownSpells = { [1766] = true, [1784] = true }
    C.Forget()
    T.falsy(C.Family("s1766").aura, "Kick")
    T.truthy(C.Family("s1784").aura, "Stealth")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The shocks, Prayer of Mending, Charge, Kick: a third of the game's Cooldown
-- Manager spells keep their cooldown on a group of spells, not on the spell.
T.test("cdm facts: a cooldown shared by a group of spells counts before any cast teaches it", function()
    local AB = customWorld("SHAMAN")
    local Own = AB.CdmOwn
    realFacts()
    local had = _G.GetSpellBaseCooldown
    _G.GetSpellBaseCooldown = nil
    T.truthy(Own.HasCooldown(8042), "the game's call missing: Earth Shock")
    _G.GetSpellBaseCooldown = function() return 0, 1500 end
    T.truthy(Own.HasCooldown(8050), "the call says none: Flame Shock")
    T.truthy(Own.HasCooldown(401859), "Prayer of Mending")
    T.falsy(Own.HasCooldown(772), "Rend has none")
    T.falsy(Own.HasCooldown(99999999), "a spell the data doesn't know")
    _G.GetSpellBaseCooldown = function() return 30000 end
    T.truthy(Own.HasCooldown(99999999), "the call's own answer still counts")
    _G.GetSpellBaseCooldown = had
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Prayer of Mending's buff is another spell than its cast (401877, not 401859) and
-- sits on the friend you cast it on. Watched by the cast's ids on you and among your
-- target's debuffs, nothing ever showed.
T.test("cdm facts: Prayer of Mending is watched by its buff's own ids on your friendly target, icon and bar", function()
    local DUI, AB, E, D = editorWorld()
    plainAuras()
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "PRIEST" }, target = { name = "Friend", friend = true } })
    AB.CdmSpells.PRIEST = { { 401859, 1240826, 1240827, cd = true, aura = true }, { 589, 594, aura = true } }
    stub.knownSpells = { [401859] = true, [589] = true }
    realFacts()
    local C = AB.CdmCustom
    T.truthy(C.Ranks("s401859")[401877], "the buff's id, not only the cast's")
    T.truthy(C.Friend("s401859"))
    T.falsy(C.Friend("s589"), "Shadow Word: Pain is a debuff")
    local set = D.Current()
    D.AddPiece(set, "s401859", "icon", 0, 0)
    set.pieces["s401859"].track = "aura"
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, "s401859", "bar") end
        stub.units.target = { name = "Friend", friend = true }
        AB.CdmRows.Refresh(); stub.RunTimers()
        local h = shape == "bar" and AB.CdmBars.AuraFrame("s401859") or AB.CdmAuras.Frame("s401859")
        T.truthy(h, shape .. ": drawn by ours")
        T.eq(#h.containers, 1, shape .. ": one container")
        T.eq(h.containers[1].unit, "target", shape .. ": on your friendly target")
        T.eq(h.containers[1].c.__groups.a.filter, "HELPFUL|PLAYER", shape .. ": your own cast")
        stub.auras.target = { HELPFUL = { { spellId = 401877, duration = 30, expirationTime = GetTime() + 30,
            applications = 5, sourceUnit = "player", isFromPlayerOrPlayerPet = true } } }
        T.eq(AB.CdmAuras.IsUp(h), true, shape .. ": found by the buff's id")
        stub.auras.target = nil
        stub.units.target = { name = "Mob" }
        stub.FireEvent("PLAYER_TARGET_CHANGED"); stub.RunTimers()
        T.eq(h.containers[1].unit, "player", shape .. ": an enemy target: watched on you")
        stub.units.target = { name = "Friend", friend = true }
        stub.FireEvent("PLAYER_TARGET_CHANGED"); stub.RunTimers()
        T.eq(h.containers[1].unit, "target", shape .. ": a friend again")
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Buff state comes from the game's own item, never from a guess.

-- A row set to show its inactive icons (Edit Mode's "Hide when inactive" off) keeps
-- a buff's item on screen while the buff is down, so "is it shown" says nothing.
T.test("cdm state: the game's buff item says up or down by its active state, shown or not (icon and bar)", function()
    local DUI, AB, E, D, ess, bars, icons = editorWorld({ 41 })
    DUI.DB.General().motion = false
    withCategories({ [2] = { 41 }, [3] = { 21 } }, { [2] = { 41 }, [3] = { 21 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id } end
    local set = D.Current()
    for _, case in ipairs({ { 41, icons[1], "icon" }, { 21, bars[1], "bar" } }) do
        local id, item, shape = case[1], case[2], case[3]
        item:SetHideWhenInactive(false)
        D.AddPiece(set, id, shape, shape == "bar" and 100 or 0, 0)
        T.truthy(D.SetSpellValue(set, id, "missingGlow", true))
        AB.CdmRows.Refresh(); stub.RunTimers()
        T.eq(AB.CdmRows.DrawnBy(id), "game", shape .. ": the game's own item")
        T.falsy(AB.CdmEffects.GlowShown(item), shape .. ": up, no glow")
        stub.EnterCombat()
        -- No pass asked for here: the item's own change is heard.
        item:SetIsActive(false); stub.RunTimers()
        T.truthy(item:IsShown(), shape .. ": the row still shows it")
        T.truthy(AB.CdmEffects.GlowShown(item), shape .. ": down in a fight, it glows")
        item:SetIsActive(true); stub.RunTimers()
        T.falsy(AB.CdmEffects.GlowShown(item), shape .. ": up again, the glow goes")
        stub.LeaveCombat()
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's cooldown icon shows a spell's debuff while it's up (Rend) and marks it
-- with wasSetFromAura. Held as it is, or out of sight under Daylight UI's bar, that is
-- the word on whether the debuff is up.
T.test("cdm state: the game's cooldown icon says when its aura is up, as an icon and under a bar", function()
    local DUI, AB, E, D, ess = editorWorld()
    DUI.DB.General().motion = false
    withCategories({ [1] = { 11, 12 } }, { [1] = { 11, 12 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return { spellID = 100 + id, hasAura = true } end
    _G.GetSpellBaseCooldown = function() return 0 end
    C_Spell.GetSpellTexture = function() return 1234 end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, 11, "upGlow", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 11, "bar") end
        AB.CdmRows.Refresh(); stub.RunTimers()
        local lit = shape == "bar" and AB.CdmBars.AuraFrame(11) or ess[1]
        T.eq(AB.CdmRows.DrawnBy(11), shape == "bar" and "aura bar" or "game", shape .. ": who draws it")
        T.falsy(AB.CdmEffects.GlowShown(lit), shape .. ": down, no glow")
        stub.EnterCombat()
        -- Auras can't be read in the fight, and nothing was cast: only the icon knows.
        ess[1]:SetAura(true); stub.RunTimers()
        T.truthy(AB.CdmEffects.GlowShown(lit), shape .. ": the debuff landed, it glows")
        ess[1]:SetAura(false); stub.RunTimers()
        T.falsy(AB.CdmEffects.GlowShown(lit), shape .. ": it ended, the glow goes")
        stub.LeaveCombat()
    end
    _G.GetSpellBaseCooldown = nil
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A spell placed by its cooldown has another id than the game's buff entry of the
-- same spell. The buff's item is still the word, and a "down" from it is final: a
-- buff the item doesn't count (someone else's) isn't read behind its back.
T.test("cdm state: a piece finds the game's buff item of its spell, and its down is final (icon and bar)", function()
    local DUI, AB, E, D, ess, bars, icons = editorWorld({ 41 })
    DUI.DB.General().motion = false
    withCategories({ [1] = { 11, 12 }, [2] = { 41 } }, { [1] = { 11, 12 }, [2] = { 41 } })
    -- Cooldown 11 and buff 41 are the same spell, 111.
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = (id == 41) and 111 or (100 + id) }
    end
    C_Spell.GetSpellTexture = function() return 1234 end
    C_Spell.GetSpellCooldownDuration = function() return nil end
    local set = D.Current()
    D.AddPiece(set, 11, "icon", 0, 0)
    set.pieces[11].track = "buff"
    T.truthy(D.SetSpellValue(set, 11, "missingGlow", true))
    T.truthy(D.SetSpellValue(set, 11, "missing", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 11, "bar") end
        icons[1]:SetIsActive(true)
        AB.CdmRows.Refresh(); stub.RunTimers()
        local h = shape == "bar" and AB.CdmBars.AuraFrame(11) or AB.CdmAuras.Frame(11)
        T.truthy(h, shape .. ": drawn by ours")
        T.eq(h.up, true, shape .. ": the game's buff item says up")
        -- Still readable on you by its id, but the game's item says down.
        stub.auras.player = { HELPFUL = { { spellId = 111, duration = 600, expirationTime = GetTime() + 600 } } }
        icons[1]:SetIsActive(false); stub.RunTimers()
        T.eq(h.up, false, shape .. ": down by the item, nothing else asked")
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": the missing glow lights")
        stub.EnterCombat()
        icons[1]:SetIsActive(true); stub.RunTimers()
        T.eq(h.up, true, shape .. ": up in a fight, with no cast of yours")
        T.falsy(AB.CdmEffects.GlowShown(h), shape .. ": the glow goes")
        stub.LeaveCombat()
        stub.auras.player = nil
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A buff the game has no item for and hides in fights: nothing can say whether it's
-- up, so it's drawn while it's up and nothing more. Its glows, Hide and sounds stay
-- off everywhere (a glow that works in town and not in a fight reads as a bug), and
-- the card leaves those rows out.
T.test("cdm state: a buff nothing can tell about is drawn and nothing more, its state rows left out (icon and bar)", function()
    local DUI, AB, E, D, set = auraWorld(false)
    DUI.DB.General().motion = false
    T.truthy(D.SetSpellValue(set, 41, "missingGlow", true))
    T.truthy(D.SetSpellValue(set, 41, "missing", true))
    T.truthy(D.SetSpellValue(set, 41, "hideActive", true))
    local function row(key)
        for _, r in ipairs(AB.CdmCard.ROWS.show) do if r.item and r.item.key == key then return r end end
    end
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 41, "bar") end
        -- Down, and readable out of a fight: still not asked.
        stub.auras.player = { HELPFUL = {} }
        AB.CdmRows.Refresh(); stub.RunTimers()
        local h = shape == "bar" and AB.CdmBars.AuraFrame(41) or AB.CdmAuras.Frame(41)
        T.truthy(h and h:IsShown(), shape .. ": drawn")
        T.eq(AB.CdmRows.Tracked(41), false, shape .. ": nothing tells its state")
        T.isnil(h.up, shape .. ": no answer rather than a guessed one")
        T.falsy(AB.CdmEffects.GlowShown(h), shape .. ": no missing glow out of a fight")
        T.falsy(h.hideUp, shape .. ": its button isn't hidden, it's all there is to see")
        stub.EnterCombat()
        stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "c-" .. shape, 141); stub.RunTimers()
        T.isnil(h.up, shape .. ": your cast says nothing about it")
        T.falsy(AB.CdmEffects.GlowShown(h), shape .. ": nor a glow in one")
        stub.LeaveCombat()
        for _, key in ipairs({ "cdm.card.buffUp", "cdm.card.upGlow", "cdm.card.buffSound",
            "cdm.card.buffEndSound", "cdm.card.missingGlow" }) do
            T.falsy(row(key).show(set, 41, set.pieces[41]), shape .. ": " .. key .. " left out of the card")
        end
        T.truthy(row("cdm.card.buffDown").show(set, 41, set.pieces[41]), shape .. ": Show or Hide while missing stays")
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- Battle Shout is a buff another warrior can put on you, which the game's item doesn't
-- count. Its holder's own button is the word for anyone's (test_cdm_game), and the
-- game's item saying yours is up still counts, so the reminder to cast it keeps
-- working in a fight.
T.test("cdm state: a buff others can cast too takes the game's item for your own (icon and bar)", function()
    local DUI, AB, E, D, set, _, _, icons = auraWorld(false, { 31, 41 })
    DUI.DB.General().motion = false
    stub.SetUnits({ player = { class = "WARRIOR" } })
    AB.CdmSpells.WARRIOR = { { 6673, 5242, aura = true } }
    stub.knownSpells = { [6673] = true }
    AB.CdmCustom.Forget()
    withCategories({ [2] = { 31, 41 } }, { [2] = { 31, 41 } })
    _G.C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id)
        return { spellID = id == 31 and 6673 or 100 + id }
    end
    place(D, set, 31, 1, 1)
    T.truthy(D.SetSpellValue(set, 31, "missingGlow", true))
    T.truthy(D.SetSpellValue(set, 31, "missing", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, 31, "bar") end
        icons[1]:SetIsActive(false)
        AB.CdmRows.Refresh(); stub.RunTimers()
        local h = shape == "bar" and AB.CdmBars.AuraFrame(31) or AB.CdmAuras.Frame(31)
        T.truthy(h, shape .. ": drawn by ours")
        T.eq(AB.CdmRows.Tracked(31), true, shape .. ": the game's item answers for yours")
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": yours is down, it glows")
        stub.EnterCombat()
        icons[1]:SetIsActive(true); stub.RunTimers()
        T.eq(h.up, true, shape .. ": cast in the fight: up")
        T.falsy(AB.CdmEffects.GlowShown(h), shape .. ": the glow goes")
        icons[1]:SetIsActive(false); stub.RunTimers()
        T.truthy(AB.CdmEffects.GlowShown(h), shape .. ": it ran out in the fight: glowing again")
        stub.LeaveCombat()
    end
    noCategories()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm bars: a custom gradient fill, the spell's own or its group's; only a bar takes one", function()
    local DUI, AB, set = fxWorld()
    local D, CD, S = AB.CdmData, AB.Cooldowns, DUI.Style
    local stops = { count = 3, c1 = { 1, 0, 0 }, c2 = { 0, 1, 0 }, c3 = { 0, 0, 1 } }
    T.eq(D.SetSpellValue(set, 11, "barStops", stops), false, "an icon has no fill")
    set.pieces[11].shape = "bar"
    T.eq(D.SetSpellValue(set, 11, "barStops", { count = 3, c1 = { 1, 0, 0 }, c2 = { 0, 1, 0 } }), false, "a counted color missing")
    T.eq(D.SetSpellValue(set, 11, "barStops", { count = "3" }), false)
    T.eq(D.SetSpellValue(set, 11, "barStops", stops), true)
    T.eq(set.pieces[11].barStops.count, 3)
    T.truthy(set.pieces[11].barStops ~= stops, "a copy")
    T.eq(D.SetSpellValue(set, 11, "barMode", "customGradient"), true)

    local bar = S.Bar(UIParent)
    local fill = bar:GetStatusBarTexture()
    CD.ColourBase({}, bar, {}, "class", set.pieces[11])
    T.eq(#S.FillStops(fill), 3, "the spell's own colors")
    CD.ColourBase({}, bar, {}, "customGradient", { barMode = "block" },
        { count = 4, c1 = { 1, 0, 0 }, c2 = { 0, 1, 0 }, c3 = { 0, 0, 1 }, c4 = { 1, 1, 0 } })
    T.eq(#S.FillStops(fill), 4, "the group's")
    CD.ColourBase({}, bar, {}, "customGradient", { barMode = "solid", barColor = { 1, 0, 0 } })
    T.isnil(S.FillStops(fill), "a spell's own solid color wins")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
