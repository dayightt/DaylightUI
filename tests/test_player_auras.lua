local stub = require("stub")

-- The player frame's own buffs and debuffs. They use the target's rows and
-- are off until switched on.

local function login(before) return stub.Load({ module = true, before = before }) end

local function shown(h)
    local n = 0
    for _, b in ipairs(h and h.pool or {}) do if b:IsShown() then n = n + 1 end end
    return (h and h:IsShown()) and n or 0
end

T.test("the player's rows are off by default, above the frame, buffs from the left, debuffs from the right", function()
    local DUI, ns = login()
    local d = ns.DEFAULTS.playerAuras
    T.eq(d.debuffs, false); T.eq(d.buffs, false)
    T.eq(d.debuffSpot, "above"); T.eq(d.buffSpot, "above")
    T.eq(d.debuffGrow, "left"); T.eq(d.buffGrow, "right")
    T.isnil(ns.playerAuras, "no containers until a row is switched on: nobody pays for them")
    T.isnil(_G.DaylightUIPlayerDebuffs)
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    local set = ns.playerAuras
    T.truthy(set, "made when switched on")
    T.eq(set.debuffs.__groups.all.max, 0, "the debuffs stay off")
    T.truthy(set.buffs.__groups.buffs.max > 0)
    DUI:Set("UnitFrames", "playerAuras.buffs", false)
    T.eq(set.buffs.__groups.buffs.max, 0, "off again: nothing shows")
end)

T.test("the player's containers watch you: every debuff in one group, every buff", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    local set = ns.playerAuras
    T.eq(set.debuffs.__unit, "player"); T.eq(set.buffs.__unit, "player")
    T.eq(table.concat(set.debuffs.__groupOrder, ","), "all")
    T.eq(set.debuffs.__groups.all.filter, "HARMFUL")
    T.eq(set.buffs.__groups.buffs.filter, "HELPFUL")
    T.eq(_G.DaylightUIPlayerDebuffs, set.debuffs)
    T.eq(_G.DaylightUIPlayerBuffs, set.buffs)
    T.eq(_G.DaylightUITargetDebuffs, ns.auras.debuffs, "the target keeps its own")
end)

T.test("switched on, the settings reach the player's containers", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    local set = ns.playerAuras
    T.truthy(set.debuffs.__groups.all.max > 0, "debuffs show")
    T.truthy(set.buffs.__groups.buffs.max > 0, "buffs show")
    DUI:Set("UnitFrames", "playerAuras.maxDebuffs", 2)
    T.eq(set.debuffs.__groups.all.max, 2)
end)

T.test("the player's and the target's icon sizes are their own", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    DUI:Set("UnitFrames", "playerAuras.debuffSize", 40)
    DUI:Set("UnitFrames", "playerAuras.buffSpacing", 9)
    T.eq(ns.playerAuras.debuffs.__groups.all.layout.elementWidth, 40)
    T.eq(ns.playerAuras.buffs.__groups.buffs.layout.elementSpacing, 9)
    local t = DUI:Get("UnitFrames", "targetAuras")
    T.eq(ns.auras.debuffs.__groups.mine.layout.elementWidth, t.debuffSize, "the target's debuffs keep their size")
    T.eq(ns.auras.buffs.__groups.buffs.layout.elementSpacing, t.buffSpacing, "and its buffs their gap")
    DUI:Set("UnitFrames", "targetAuras.debuffSize", 20)
    T.eq(ns.playerAuras.debuffs.__groups.all.layout.elementWidth, 40, "and the other way round")
    -- Real buttons take their own container's size.
    local real = ns.playerAuras.debuffs.__groups.all.button
    if real then T.eq(real:GetWidth(), 40) end
end)

T.test("over the frame the rows sit side by side: buffs from the left end, debuffs from the right", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    local set, f = ns.playerAuras, ns.frames.player
    local p, rel, rp = set.debuffs:GetPoint(1)
    T.eq(rel, f)
    T.truthy(p:find("^BOTTOM") and rp:find("^TOP"), "over the frame")
    T.eq(set.debuffs.__growth[1], AnchorUtil.FlowDirection.Left, "debuffs run left from the right end")
    T.eq(set.buffs.__growth[1], AnchorUtil.FlowDirection.Right, "buffs run right from the left end")
    T.eq(set.debuffs.__growth[2], AnchorUtil.FlowDirection.Up)
    T.truthy(p:find("RIGHT$"), "debuffs at the right end")
    local bp, _, _, _, by = set.buffs:GetPoint(1)
    local _, _, _, _, dy = set.debuffs:GetPoint(1)
    T.truthy(bp:find("LEFT$"), "buffs at the left end")
    T.near(dy, by, 0.01, "side by side, not stacked")
    T.truthy(set.buffs:GetWidth() + set.debuffs:GetWidth() < f:GetWidth(), "each in its own part of the line")
end)

-- A player's report: buffs turned to grow left and debuffs right put the
-- debuffs high over the frame, past every row the buffs could fill, though
-- the two rows start at opposite ends and never meet.
T.test("swapped ends, the rows still share the line: debuffs from the left end, buffs from the right", function()
    local DUI, ns = login()
    for k, v in pairs({ debuffs = true, buffs = true, debuffGrow = "right", buffGrow = "left",
                        debuffRows = 3, debuffPerRow = 5, maxDebuffs = 15,
                        buffRows = 2, buffPerRow = 5, maxBuffs = 8, buffSize = 16 }) do
        DUI:Set("UnitFrames", "playerAuras." .. k, v)
    end
    for _, set in ipairs({ ns.playerAuras, ns.auras }) do
        if set == ns.auras then
            for k, v in pairs({ debuffGrow = "right", buffGrow = "left", buffSpot = "above", debuffSpot = "above" }) do
                DUI:Set("UnitFrames", "targetAuras." .. k, v)
            end
        end
        local dp, _, _, _, dy = set.debuffs:GetPoint(1)
        local bp, _, _, _, by = set.buffs:GetPoint(1)
        T.truthy(dp:find("LEFT$"), "debuffs at the left end")
        T.truthy(bp:find("RIGHT$"), "buffs at the right end")
        T.near(dy, by, 0.01, "side by side, not stacked")
    end
end)

T.test("nothing pushes the player's rows: they sit where they're placed", function()
    local DUI, ns = login(function()
        stub.units.player = { name = "Stabby", isPlayer = true, class = "ROGUE", powerToken = "ENERGY" }
    end)
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    DUI:Set("UnitFrames", "playerAuras.buffSpot", "below")
    local set = ns.playerAuras
    local _, _, _, _, y = set.buffs:GetPoint(1)
    DUI:Set("UnitFrames", "swing.enabled", false)
    DUI:Set("UnitFrames", "playerCastbar.at", "free")
    DUI:Set("UnitFrames", "combo.anchor", "player")
    DUI:Set("UnitFrames", "combo.side", "below")
    local _, _, _, _, after = set.buffs:GetPoint(1)
    T.eq(after, y, "the cast bar, swing timers and pips move nothing")
    DUI:Set("UnitFrames", "playerAuras.buffY", 11)
    local _, _, _, _, nudged = set.buffs:GetPoint(1)
    T.eq(nudged, y + 11, "only the nudge does")
    T.eq(ns.auras.aboveLift, 0, "the target's rows stay put")
end)

T.test("the Player page has the same Debuffs and Buffs cards, on the player's keys", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    local by = {}
    for _, g in ipairs(O.GetPage("UnitFrames.player").groups) do by[g.label] = g end
    T.eq(by.Debuffs.tab, "Auras"); T.eq(by.Buffs.tab, "Auras")
    T.eq(by.Debuffs.items[1].key, "playerAuras.debuffs")
    T.eq(by.Buffs.items[1].key, "playerAuras.buffs")
    local keys = {}
    for _, g in ipairs({ by.Debuffs, by.Buffs }) do
        for _, it in ipairs(g.items) do if it.key then keys[it.key] = it end end
    end
    for _, k in ipairs({ "debuffSize", "maxDebuffs", "debuffSpacing", "debuffRows", "debuffSpot", "debuffGrow",
                         "debuffX", "debuffY", "buffSize", "maxBuffs", "buffSpacing", "buffRows", "buffSpot",
                         "buffGrow", "buffX", "buffY" }) do
        T.truthy(keys["playerAuras." .. k], k)
    end
    local filter = keys["playerAuras.debuffFilter"]
    T.isnil(filter.values.mine, "no mine/others on yourself: all or the ones you can dispel")
    T.truthy(filter.values.dispel)
    T.isnil(keys["playerAuras.buffFilter"], "purging your own buffs means nothing")
    T.isnil(keys["playerAuras.maxOtherDebuffs"])
    T.eq(#O.ValidatePage(O.GetPage("UnitFrames.player")), 0)
    -- The target's cards are untouched.
    local tbuffs
    for _, g in ipairs(O.GetPage("UnitFrames.target").groups) do if g.label == "Buffs" then tbuffs = g end end
    T.eq(tbuffs.items[1].key, "targetAuras.buffs")
end)

T.test("the Player page preview shows the rows once on, and they move in Design mode", function()
    local DUI, ns = login()
    local box = CreateFrame("Frame", nil, UIParent)
    local s = ns.PageSample.New("player", box)
    s.Refresh(600, 160)
    local by = {}
    for _, p in ipairs(s.Parts()) do by[p.label] = by[p.label] or p end
    T.isnil(by["Debuffs"], "off: nothing to show")
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    s.Refresh(600, 160)
    by = {}
    for _, p in ipairs(s.Parts()) do by[p.label] = by[p.label] or p end
    T.eq(#s.missing, 0, table.concat(s.missing, ", "))
    T.eq(by["Debuffs"].move.spotKey, "playerAuras.debuffSpot")
    T.eq(by["Debuffs"].move.owner.spec.unit, "player")
    T.eq(by["Debuffs"].size.keys.s, "playerAuras.debuffSize")
    T.eq(by["Buffs"].move.xKey, "playerAuras.buffX")
end)

T.test("test mode shows sample rows on the player frame only when switched on", function()
    local DUI, ns = login()
    DUI.SetTestMode(true)
    T.isnil(ns.playerAuras, "off: no samples, no set")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    DUI.SetTestMode(false)
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    DUI.SetTestMode(true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    local set = ns.playerAuras
    local dh, bh = ns.Auras.HolderFor(set.debuffs), ns.Auras.HolderFor(set.buffs)
    T.truthy(shown(dh) > 0, "sample debuffs")
    T.truthy(shown(bh) > 0, "sample buffs")
    T.eq(dh.pool[1]:GetWidth(), DUI:Get("UnitFrames", "playerAuras.debuffSize"))
    T.eq(set.debuffs:GetAlpha(), 0, "the real ones out of the way")
    DUI.SetTestMode(false)
    T.eq(shown(dh), 0)
    T.eq(set.debuffs:GetAlpha(), 1, "the real ones back")
end)

T.test("the player's rows wait out a fight and restrictions", function()
    local DUI, ns = login()
    stub.EnterCombat()
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    T.isnil(ns.playerAuras, "made after the fight")
    stub.LeaveCombat()
    T.truthy(ns.playerAuras.debuffs.__groups.all.max > 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A row in the page's preview sits where it sits in game, so a nudge that
-- looks right in the preview lands there.
T.test("the preview's rows sit where the game's do", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "playerAuras.buffs", true)
    DUI:Set("UnitFrames", "playerAuras.buffSpot", "below")
    DUI:Set("UnitFrames", "playerAuras.buffY", 11)
    local s = ns.PageSample.New("player", UIParent)
    s.Refresh(600, 160)
    local _, _, _, _, liveY = ns.playerAuras.buffs:GetPoint(1)
    local _, _, _, _, sampleY = ns.Auras.HolderFor(s.f.sampleAuras.buffs):GetPoint(1)
    T.eq(sampleY, liveY)
end)

-- The preview has no power bar of its own to put on the screen, so with the
-- power bar on its own the preview's frame is all health, as the game's is.
T.test("with the power bar on its own, the preview's frame is all health", function()
    local DUI, ns = login()
    for _, unit in ipairs({ "player", "target", "focus" }) do
        DUI:Set("UnitFrames", unit .. ".powerAt", "free")
        local s = ns.PageSample.New(unit, UIParent)
        s.Refresh(600, 160)
        local f = s.f
        T.falsy(f.power:IsShown(), unit .. ": no power bar inside")
        T.falsy(f.separator:IsShown(), unit)
        local hp, rel = f.health:GetPoint(2)
        T.eq(hp, "BOTTOMRIGHT", unit); T.eq(rel, f, unit .. ": health to the bottom")
        DUI:Set("UnitFrames", unit .. ".powerAt", "inside")
        s.Refresh(600, 160)
        T.truthy(f.power:IsShown(), unit .. ": back inside")
    end
end)

T.test("the target's preview keeps the room its cast bar takes in game", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "targetCastbar.at", "below")
    local s = ns.PageSample.New("target", UIParent)
    s.Refresh(600, 160)
    T.truthy(ns.auras.buffDrop > 0)
    T.eq(s.f.sampleAuras.buffDrop, ns.auras.buffDrop)
    DUI:Set("UnitFrames", "targetCastbar.at", "above")
    s.Refresh(600, 160)
    T.truthy(ns.auras.aboveLift > 0)
    T.eq(s.f.sampleAuras.aboveLift, ns.auras.aboveLift)
end)

T.test("the target's buff filter picks one group, each added the first time it's picked", function()
    local DUI, ns = login()
    local b = ns.auras.buffs
    T.eq(b.__groups.buffs.filter, "HELPFUL")
    T.isnil(b.__groups.purge, "nothing paid for a filter nobody picked")
    DUI:Set("UnitFrames", "targetAuras.buffFilter", "purge")
    T.eq(b.__groups.purge.filter, "HELPFUL|RAID_PLAYER_DISPELLABLE")
    T.truthy(b.__groups.purge.max > 0)
    T.eq(b.__groups.buffs.max, 0, "only the picked one shows")
    DUI:Set("UnitFrames", "targetAuras.buffFilter", "mine")
    T.eq(b.__groups.mine.filter, "HELPFUL|PLAYER")
    T.eq(b.__groups.purge.max, 0)
    T.truthy(b.__groups.mine.max > 0)
end)

T.test("the player's debuffs can show only the ones you can dispel", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    local d = ns.playerAuras.debuffs
    T.isnil(d.__groups.dispel)
    DUI:Set("UnitFrames", "playerAuras.debuffFilter", "dispel")
    T.eq(d.__groups.dispel.filter, "HARMFUL|RAID_PLAYER_DISPELLABLE")
    T.eq(d.__groups.all.max, 0)
    T.truthy(d.__groups.dispel.max > 0)
end)

T.test("the target's time numbers, sweep and tooltips follow their switches, built in from the start", function()
    local DUI, ns = login(function()
        DaylightUIDB = { modules = { UnitFrames = { targetAuras = { buffSwipe = true, buffTips = false } } } }
    end)
    local btn = ns.auras.buffs.__groups.buffs.button
    T.truthy(btn, "the client built the buttons")
    T.eq(btn:IsMouseEnabled(), false, "built with tooltips off: the mouse goes through")
    DUI:Set("UnitFrames", "targetAuras.buffTips", true)
    T.eq(btn:IsMouseEnabled(), true, "on again")
    local debuff = ns.auras.debuffs.__groups.mine.button
    T.eq(debuff:IsMouseEnabled(), true, "the debuffs keep theirs")
end)

T.test("the focus's rows are off until switched on, then only your debuffs, in containers of their own", function()
    local DUI, ns = login()
    T.isnil(ns.focusAuras, "nobody pays for them until they're on")
    DUI:Set("UnitFrames", "focusAuras.debuffs", true)
    local set = ns.focusAuras
    T.truthy(set)
    T.eq(set.debuffs.__unit, "focus"); T.eq(set.buffs.__unit, "focus")
    T.eq(_G.DaylightUIFocusDebuffs, set.debuffs)
    T.truthy(_G.DaylightUITargetDebuffs ~= set.debuffs, "the target keeps its own")
    T.truthy(set.debuffs.__groups.mine.max > 0)
    T.eq(set.debuffs.__groups.rest.max, 0, "others' debuffs wait for Mine first, then others")
    DUI:Set("UnitFrames", "focusAuras.debuffFilter", "all")
    T.truthy(set.debuffs.__groups.rest.max > 0)
    T.eq(set.buffs.__groups.buffs.max, 0, "the buffs stay off")
end)

T.test("the Focus page has its Debuffs and Buffs cards, and they pass the page check", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    local by = {}
    for _, g in ipairs(O.GetPage("UnitFrames.focus").groups) do by[g.label] = g end
    T.eq(by.Debuffs.items[1].key, "focusAuras.debuffs")
    T.eq(by.Buffs.items[1].key, "focusAuras.buffs")
    T.eq(#O.ValidatePage(O.GetPage("UnitFrames.focus")), 0)
end)

T.test("the pet's rows are off until switched on, then every debuff on it, in containers of their own", function()
    local DUI, ns = login()
    T.isnil(ns.petAuras, "nobody pays for them until they're on")
    DUI:Set("UnitFrames", "petAuras.debuffs", true)
    local set = ns.petAuras
    T.truthy(set)
    T.eq(set.debuffs.__unit, "pet"); T.eq(set.buffs.__unit, "pet")
    T.eq(_G.DaylightUIPetDebuffs, set.debuffs)
    T.truthy(_G.DaylightUIPlayerDebuffs ~= set.debuffs, "the player keeps its own")
    T.truthy(set.debuffs.__groups.all.max > 0)
    T.eq(set.buffs.__groups.buffs.max, 0, "the buffs stay off")
    DUI:Set("UnitFrames", "petAuras.buffs", true)
    T.truthy(set.buffs.__groups.buffs.max > 0)
    DUI:Set("UnitFrames", "petAuras.buffFilter", "mine")
    T.eq(set.buffs.__groups.buffs.max, 0)
    T.truthy(set.buffs.__groups.mine.max > 0, "only the buffs you put on it")
    T.eq(set.buffs.__groups.mine.filter, "HELPFUL|PLAYER")
end)

T.test("the Pet page has its Debuffs and Buffs cards, and they pass the page check", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    local by = {}
    for _, g in ipairs(O.GetPage("UnitFrames.pet").groups) do by[g.label] = g end
    T.eq(by.Debuffs.items[1].key, "petAuras.debuffs")
    T.eq(by.Buffs.items[1].key, "petAuras.buffs")
    T.eq(#O.ValidatePage(O.GetPage("UnitFrames.pet")), 0)
end)

T.test("upgrade step 19: a profile from before 1.8.0 keeps its aura rows where they were", function()
    local _, ns = login()
    local p = { modules = { UnitFrames = { groupFrames = 18, targetAuras = { buffSpot = "below" },
                                           playerAuras = { debuffGrow = "center" } } } }
    ns.UpgradeGroupFrames(p)
    local uf = p.modules.UnitFrames
    T.eq(uf.groupFrames, #ns.UPGRADE_STEPS)
    local t = uf.targetAuras
    T.eq(t.buffSpot, "below"); T.eq(t.buffGrow, "left", "the target's buffs under the frame, from the outer end")
    T.eq(t.debuffRows, 3); T.eq(t.buffRows, 2)
    T.eq(uf.playerAuras.debuffGrow, "center", "a direction the player picked stays")
    T.eq(uf.personal.auras.debuffGrow, "center"); T.eq(uf.personal.auras.buffGrow, "center")
    T.isnil(uf.focusAuras, "the focus rows came after: they keep the new layout")
    -- Run again: nothing more happens.
    t.buffGrow = "right"
    ns.UpgradeGroupFrames(p)
    T.eq(t.buffGrow, "right", "once only")
end)

T.test("upgrade step 19: a brand new profile gets the new rows", function()
    local _, ns = login()
    local p = {}
    ns.UpgradeGroupFrames(p)
    local uf = p.modules.UnitFrames
    T.eq(uf.groupFrames, #ns.UPGRADE_STEPS)
    T.isnil(uf.targetAuras, "nothing written: the defaults apply")
    T.isnil(uf.playerAuras); T.isnil(uf.personal)
end)

T.test("upgrade step 19: a player from 1.8.1 finds the target's buffs under the frame again", function()
    -- The move check's saved player, who changed nothing, taken back to 1.8.1:
    -- the same saved data, with the unit frames' upgrade counter where 1.8.1
    -- left it (step 19 came in 1.8.2; the snapshot may be newer).
    local Check, data = require("release_check"), require("release_data")
    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = copy(x) end
        return out
    end
    local saved = copy(data.saved)
    local uf = saved.profileData["DPS/Tank"].modules.UnitFrames
    T.truthy(uf.groupFrames >= 19, "the snapshot is from 1.8.2 or later")
    uf.groupFrames = 18
    local DUI = Check.Load(saved)
    T.eq(DUI:Get("UnitFrames", "targetAuras.buffSpot"), "below")
    T.eq(DUI:Get("UnitFrames", "targetAuras.buffGrow"), "left")
    T.eq(DUI.DB.Active().modules.UnitFrames.groupFrames, #DUI:GetModule("UnitFrames").ns.UPGRADE_STEPS)
    -- A player from 1.8.2 already had the step: their rows stay as they were.
    DUI = Check.Load(data.saved)
    T.eq(DUI:Get("UnitFrames", "targetAuras.buffSpot"), "above")
end)

T.test("upgrade step 19: buffs a player put above the frame long ago stay above", function()
    local _, ns = login()
    -- Before spots, "above" was a pick (the default was under the frame); step 10
    -- turns it into today's default spot in the same run.
    local p = { modules = { UnitFrames = { groupFrames = 9, targetAuras = { buffsAt = "above" } } } }
    ns.UpgradeGroupFrames(p)
    local t = p.modules.UnitFrames.targetAuras
    T.eq(t.buffSpot, "above", "their own pick")
    T.eq(t.buffGrow, "left", "the rest goes back as it was")
end)

T.test("icons per row: a set number shapes the row and caps it by rows; 0 fits the frame", function()
    local DUI, ns = login()
    DUI:Set("UnitFrames", "playerAuras.debuffs", true)
    local set = ns.playerAuras
    local fits = set.debuffRow
    DUI:Set("UnitFrames", "playerAuras.debuffPerRow", 3)
    local d = ns.DEFAULTS.playerAuras
    T.eq(set.debuffRow, 3 * (d.debuffSize + d.debuffSpacing) - d.debuffSpacing)
    T.eq(set.counts.debuff[1], 3 * d.debuffRows, "rows times icons per row")
    DUI:Set("UnitFrames", "playerAuras.debuffPerRow", 0)
    T.eq(set.debuffRow, fits, "back to the frame's width")
end)
