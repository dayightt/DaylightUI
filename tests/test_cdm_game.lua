local stub = require("stub")
local CW = require("cdmworld")

-- The Cooldown Manager against the game's own code. The viewers and items here
-- are Blizzard's (tests/cdmworld.lua), a warrior's rows from the game's data, so
-- these tests see the game's real rules where tests/test_cdm.lua has hand-made
-- viewers. Each case runs for a piece placed as an icon and as a bar.

local SHOUT, REND, BLOCK, RAGE, RAGE_BUFF, CLAP, WALL = 6673, 772, 2565, 2687, 29131, 6343, 871
local ESSENTIAL, UTILITY, BUFFS = 0, 1, 2

local function world(opts)
    opts = opts or {}
    stub.neverSecretAuras = {}
    local DUI = stub.Load({ actionbars = true, before = function()
        stub.SetUnits({ player = { name = "Me", class = "WARRIOR", friend = true },
                        target = { name = "Boar", reaction = 2 } })
        CW.Install({ with = SHOUT, known = opts.known or { SHOUT, REND, BLOCK, RAGE, CLAP, WALL },
                     showAll = opts.hidden ~= true, shown = opts.shown, bars = opts.bars })
    end })
    stub.RunTimers()
    DUI.DB.General().motion = false
    local AB = stub.actionbars
    return DUI, AB, AB.CdmData, AB.CdmRows, AB.CdmEffects
end

local function pass(AB) AB.CdmData.Changed(); AB.CdmRows.Refresh(); stub.RunTimers() end
local function pieceFrame(id) return _G["DaylightUICdmPiece1_" .. id] end
local function held(item, id)
    local _, rel = item:GetPoint(1)
    return rel == pieceFrame(id)
end

T.test("cdm game: the viewers are the game's own, one item per known row the layout shows", function()
    world({ hidden = true, known = { SHOUT, REND, RAGE } })
    T.truthy(CW.Item(CW.ID(REND, ESSENTIAL)), "Rend's cooldown icon")
    T.truthy(CW.Item(CW.ID(RAGE, UTILITY)), "Bloodrage's")
    T.isnil(CW.Item(CW.ID(BLOCK, UTILITY)), "a spell not learned gets none")
    -- Every buff is hidden by default on WoW: Forever, so the game makes no item
    -- for one until the layout shows it.
    T.isnil(CW.Item(CW.ID(REND, BUFFS)), "a buff the game hides by default gets none")
    world({ hidden = true, known = { SHOUT, REND, RAGE }, shown = { CW.ID(REND, BUFFS) } })
    local item, viewer = CW.Item(CW.ID(REND, BUFFS))
    T.truthy(item, "switched on in the layout, it has one")
    T.eq(viewer, _G.BuffIconCooldownViewer)
    T.eq(item:GetWidth(), 40, "the buff icon template's size")
    T.eq(CW.Item(CW.ID(REND, ESSENTIAL)):GetWidth(), 50, "the Essential one's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's buff item is active only while its aura is up. A row hides its
-- inactive items unless Edit Mode's "Hide when inactive" is off, and then it
-- shows them all the time: only isActive says whether the buff is up.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: a buff item goes active and inactive, hidden or shown while down (" .. shape .. ")", function()
    local id
    local DUI, AB, D, R, Fx = world({ bars = shape == "bar" and { 199613 } or nil })
    id = CW.ID(WALL, BUFFS)
    local viewer = shape == "bar" and "BuffBarCooldownViewer" or "BuffIconCooldownViewer"
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    -- Shield Wall has a cooldown too, so left unset it shows both and Daylight UI
    -- draws it. Picked "Buff only", the game's buff item is the drawer.
    set.pieces[id].track = "buff"
    pass(AB)
    local item, v = CW.Item(id)
    T.eq(v, _G[viewer], "the game's " .. shape .. " row holds it")
    T.eq(R.DrawnBy(id), "game", "drawn by the game's item")
    T.falsy(item.isActive, "down: not active")
    T.falsy(item:IsShown(), "and hidden, the row hides inactive items")
    CW.Aura("player", WALL); stub.RunTimers()
    T.truthy(item.isActive, "the buff lands: active")
    T.truthy(item:IsShown(), "and shown")
    T.truthy(held(item, id), "in Daylight UI's piece")
    T.eq(item:GetAlpha(), 1)
    CW.Unaura("player", WALL); stub.RunTimers()
    T.falsy(item.isActive, "it ends: inactive")
    T.falsy(item:IsShown(), "and hidden again")
    -- Edit Mode's "Hide when inactive" off, which lays the row out again.
    CW.Setting(viewer, "HideWhenInactive", 0); stub.RunTimers()
    T.truthy(D.SetSpellValue(set, id, "missingGlow", true))
    pass(AB)
    item = CW.Item(id)
    T.truthy(item:IsShown(), "the row shows inactive items now")
    T.falsy(item.isActive, "shown, and still not active")
    T.truthy(held(item, id), "claimed back after the game's layout pass")
    stub.EnterCombat(); stub.RunTimers()
    T.truthy(Fx.GlowShown(item), "down in a fight: the missing glow, off the item's own word")
    CW.Aura("player", WALL); stub.RunTimers()
    T.truthy(item.isActive)
    T.falsy(Fx.GlowShown(item), "up in a fight, with no cast of yours: the glow goes")
    CW.Unaura("player", WALL); stub.RunTimers()
    T.truthy(item:IsShown(), "down again, still shown")
    T.truthy(Fx.GlowShown(item), "and glowing")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- A cooldown icon shows its spell's aura while it's up and marks that with
-- wasSetFromAura (Rend on your target). Held as it is, or out of sight under
-- Daylight UI's bar, the mark is the word on whether the debuff is up.
T.test("cdm game: a cooldown icon marks its aura and lets it go, as an icon and under a bar", function()
    local DUI, AB, D, R, Fx = world()
    local id = CW.ID(REND, ESSENTIAL)
    local set = D.Current()
    D.AddPiece(set, id, "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, id, "upGlow", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, id, "bar") end
        pass(AB)
        local item = CW.Item(id)
        local lit = shape == "bar" and AB.CdmBars.AuraFrame(id) or item
        T.eq(R.DrawnBy(id), shape == "bar" and "aura bar" or "game", shape .. ": who draws it")
        T.falsy(item.wasSetFromAura, shape .. ": no debuff, no mark")
        T.falsy(Fx.GlowShown(lit), shape .. ": no glow")
        stub.EnterCombat()
        CW.Aura("target", REND, { harmful = true, duration = 9 }); stub.RunTimers()
        T.truthy(item.wasSetFromAura, shape .. ": the debuff lands, the icon marks it")
        T.truthy(issecretvalue(item.auraInstanceID), shape .. ": which aura it is stays secret in a fight")
        T.truthy(Fx.GlowShown(lit), shape .. ": Buff up glows")
        CW.Unaura("target", REND); stub.RunTimers()
        T.falsy(item.wasSetFromAura, shape .. ": it ends, the mark goes")
        T.falsy(Fx.GlowShown(lit), shape .. ": and the glow")
        stub.LeaveCombat()
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game lays a row out again whenever its settings, Edit Mode or a full aura
-- update say so: every item goes back to the pool (hidden, its points cleared,
-- its cooldown forgotten) and is taken out again, not always for the same spell.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: the game's layout pass lets held items go and Daylight UI claims them back (" .. shape .. ")", function()
    local DUI, AB, D, R = world({ bars = shape == "bar" and { 199656, 199613 } or nil })
    local ids = shape == "bar" and { CW.ID(REND, BUFFS) } or { CW.ID(REND, ESSENTIAL) }
    local viewer = shape == "bar" and "BuffBarCooldownViewer" or "EssentialCooldownViewer"
    local set = D.Current()
    D.AddPiece(set, ids[1], shape, 0, 0)
    CW.Setting(viewer, "HideWhenInactive", 0)
    pass(AB)
    local first = CW.Item(ids[1])
    T.eq(R.DrawnBy(ids[1]), "game")
    T.truthy(held(first, ids[1]), "held in its piece")
    local laid = 0
    hooksecurefunc(_G[viewer], "RefreshLayout", function() laid = laid + 1 end)
    for _, why in ipairs({ "a full aura update", "its settings changing", "a full aura update in a fight" }) do
        if why == "a full aura update in a fight" then stub.EnterCombat() end
        local before = laid
        if why == "its settings changing" then
            CW.Run(function() EventRegistry:TriggerEvent("CooldownViewerSettings.OnDataChanged") end)
            CW.Layout(viewer)
        else
            stub.FireEvent("UNIT_AURA", "player", { isFullUpdate = true })
        end
        T.truthy(laid > before, why .. ": the game laid the row out")
        local item = CW.Item(ids[1])
        T.truthy(item, why .. ": the spell has an item again")
        stub.RunTimers()
        item = CW.Item(ids[1])
        T.truthy(held(item, ids[1]), why .. ": claimed back into its piece")
        T.truthy(R.Owns(item), why .. ": and owned")
        for _, name in ipairs(CW.NAMES) do
            for other in _G[name].itemFramePool:EnumerateActive() do
                if other ~= item then
                    T.falsy(held(other, ids[1]), why .. ": no other item is left in that piece")
                end
            end
        end
    end
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- The game makes its items click-through, with a tooltip only while Edit Mode's
-- "Show tooltips" is on (CooldownViewerItemMixin:SetTooltipsShown). An item Daylight
-- UI holds, or hides and shows again, keeps that.
T.test("cdm game: a held game item takes no clicks and shows its tooltip by Show tooltips", function()
    local DUI, AB, D, R = world()
    local id = CW.ID(REND, ESSENTIAL)
    local set = D.Current()
    D.AddPiece(set, id, "icon", 0, 0)
    pass(AB)
    local item = CW.Item(id)
    T.eq(R.DrawnBy(id), "game")
    T.truthy(held(item, id), "held in its piece")
    T.eq(item:IsMouseClickEnabled(), false, "held: a click goes through to the world")
    T.eq(item:IsMouseMotionEnabled(), true, "Show tooltips on: the hover shows the tooltip")
    CW.Setting("EssentialCooldownViewer", "ShowTooltips", 0); stub.RunTimers()
    item = CW.Item(id)
    T.eq(item:IsMouseClickEnabled(), false)
    T.eq(item:IsMouseMotionEnabled(), false, "Show tooltips off: no tooltip")
    -- Hidden on cooldown, then shown again when ready.
    set.pieces[id].onCd = "hide"
    pass(AB)
    CW.Cooldown(REND, 5); stub.RunTimers()
    T.eq(item:GetAlpha(), 0, "on cooldown: hidden")
    T.eq(item:IsMouseMotionEnabled(), false, "no tooltip over the gap")
    CW.Setting("EssentialCooldownViewer", "ShowTooltips", 1); stub.RunTimers()
    item = CW.Item(id)
    CW.Cooldown(REND, nil); stub.RunTimers()
    T.eq(item:GetAlpha(), 1, "ready: shown")
    T.eq(item:IsMouseClickEnabled(), false, "shown again: still click-through")
    T.eq(item:IsMouseMotionEnabled(), true, "and its tooltip back")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The viewers keep which item shows which aura in a table the client refuses
-- to tainted code. A layout pass run by an addon dies on it and leaves the
-- viewer broken, which is why Daylight UI never calls the game's Cooldown
-- Manager code.
T.test("cdm game: a layout pass run from addon code dies on the game's secure aura table", function()
    local DUI, AB, D = world()
    local id = CW.ID(REND, ESSENTIAL)
    D.AddPiece(D.Current(), id, "icon", 0, 0)
    pass(AB)
    CW.Aura("target", REND, { harmful = true })
    local ok, err = pcall(function() _G.EssentialCooldownViewer:RefreshLayout() end)
    T.falsy(ok, "refused")
    T.truthy(string.find(tostring(err), "cannot be accessed while tainted", 1, true), tostring(err))
    T.eq(#stub.errors, 0, "and nothing of Daylight UI's ran it: " .. tostring(stub.errors[1]))
end)

-- Hide (Buff up), a buff sound and Glow to recast work on the game's item where
-- it is: no option moves a spell to another drawer.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: Hide (Buff up), a buff sound and Glow to recast on a held game item (" .. shape .. ")", function()
    local DUI, AB, D, R, Fx = world({ bars = shape == "bar" and { 199656 } or nil })
    -- As an icon, Rend's cooldown icon (it marks the debuff). As a bar, Rend's
    -- buff entry moved to Tracked Bars (it is active while the debuff is up).
    local id = shape == "bar" and CW.ID(REND, BUFFS) or CW.ID(REND, ESSENTIAL)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    pass(AB)
    local got = {}
    local alert = DUI.Sound.Alert
    DUI.Sound.Alert = function(key) got[#got + 1] = key; alert(key) end
    local function item() return CW.Item(id) end
    T.eq(R.DrawnBy(id), "game", "left unset, the game's item")
    for _, o in ipairs({ { "hideActive", true }, { "upGlow", true }, { "clipGlow", true },
        { "buffSound", "dui:done" }, { "buffEndSound", "dui:done" } }) do
        T.truthy(D.SetSpellValue(set, id, o[1], o[2]))
        pass(AB)
        T.eq(R.DrawnBy(id), "game", o[1] .. " leaves it the game's")
        T.isnil(AB.CdmAuras.Frame(id), o[1] .. " makes no holder of Daylight UI's")
    end
    T.isnil(set.pieces[id].track, "and nothing was picked for the player")
    D.SetSpellValue(set, id, "upGlow", false)
    D.SetSpellValue(set, id, "clipGlow", false)
    D.SetSpellValue(set, id, "buffEndSound", "none")
    pass(AB)
    -- Hide (Buff up), in a fight, with no cast of yours.
    stub.EnterCombat(); stub.RunTimers()
    stub.Advance(5)
    local heard = #got
    CW.Aura("target", REND, { harmful = true, duration = 9 }); stub.RunTimers()
    T.eq(item():GetAlpha(), 0, "hidden while the debuff is up")
    T.eq(#got, heard + 1, "and its sound played as it landed")
    CW.Unaura("target", REND); stub.RunTimers()
    if shape == "icon" then T.eq(item():GetAlpha(), 1, "back as it ends") end
    -- Glow to recast, timed from your own cast (Rend lasts 9 s by the game's data).
    D.SetSpellValue(set, id, "hideActive", false)
    D.SetSpellValue(set, id, "clipGlow", true)
    pass(AB)
    T.eq(R.DrawnBy(id), "game", "still the game's")
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", REND)
    CW.Aura("target", REND, { harmful = true, duration = 9 }); stub.RunTimers()
    T.falsy(Fx.GlowShown(item()), "9 s left, no glow yet")
    stub.Advance(7); stub.RunTimers()
    T.falsy(Fx.GlowShown(item()), "2 s left: a cast now would still clip it")
    -- Rend is instant, so the next cast lands when the global cooldown lets it.
    -- Another spell at 8 s keeps you busy until after the debuff has run out.
    stub.Advance(1)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", CLAP); stub.RunTimers(); stub.RunTimers()
    T.truthy(Fx.GlowShown(item()), "glows when a cast would land as it ends")
    CW.Unaura("target", REND); stub.RunTimers()
    T.falsy(Fx.GlowShown(item()), "gone once the game's item says it ended")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- The game's icon shows any aura of yours whose spell is the row's own, or one
-- of its linked spells, unless the row is flagged HideAura
-- (CooldownViewerItemDataMixin:GetAssociatedAuraSpellPriority, CanUseAuraForDisplay).
-- Bloodrage's own spell puts no aura on you, its buff is a linked spell, and the
-- icon still shows it. CdmAuras.Follows must say what the icon really does, for
-- every class's cooldown rows. Rows whose spell makes a totem, trap or summon are
-- left out: their auras aren't cast by you, and whether the client counts them as
-- yours isn't something the fake game knows.
T.test("cdm game: Follows says what the game's cooldown icon shows, for every class's rows", function()
    local count = {}
    for _, r in ipairs(CW.Catalogue()) do count[r.set] = (count[r.set] or 0) + 1 end
    local wrong, checked = {}, 0
    for set, n in pairs(count) do
        if n >= 20 then
            local known = {}
            for _, r in ipairs(CW.Catalogue()) do
                if r.set == set then known[#known + 1] = r.spell end
            end
            stub.neverSecretAuras = {}
            stub.Load({ actionbars = true, before = function()
                stub.SetUnits({ player = { name = "Me", class = "WARRIOR", friend = true },
                                target = { name = "Boar", reaction = 2 } })
                CW.Install({ set = set, known = known, showAll = true })
            end })
            stub.RunTimers()
            local A = stub.actionbars.CdmAuras
            for id, r in pairs(CW.rows) do
                local item = (r.category == ESSENTIAL or r.category == UTILITY) and not r.summons and CW.Item(id)
                if item then
                    local auras = {}
                    if r.aura then auras[#auras + 1] = r.spell end
                    for _, sid in ipairs(r.linkAuras) do auras[#auras + 1] = sid end
                    local lights = false
                    for _, sid in ipairs(auras) do
                        for _, unit in ipairs({ "player", "target" }) do
                            CW.Aura(unit, sid, { harmful = unit == "target" })
                            lights = lights or item.wasSetFromAura == true
                            CW.Unaura(unit, sid)
                        end
                    end
                    checked = checked + 1
                    if A.Follows(id) ~= lights then
                        wrong[#wrong + 1] = r.name .. " (" .. id .. "): the icon " .. (lights and "shows" or "never shows")
                            .. " an aura, Follows says " .. tostring(A.Follows(id))
                    end
                end
            end
            T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        end
    end
    table.sort(wrong)
    T.truthy(checked > 100, "rows checked: " .. checked)
    T.eq(#wrong, 0, #wrong .. " of " .. checked .. " rows: " .. table.concat(wrong, "; "))
end)

-- Picked "Cooldown", Bloodrage shows its cooldown and nothing else. The game's own
-- icon shows the buff's time first, so it can't be the drawer for that pick.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: a Cooldown pick isn't left to a game icon that shows the buff (" .. shape .. ")", function()
    local DUI, AB, D, R = world()
    local id = CW.ID(RAGE, UTILITY)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    set.pieces[id].track = "cooldown"
    pass(AB)
    CW.Cooldown(RAGE, 60)
    CW.Aura("player", RAGE_BUFF, { duration = 10 }); stub.RunTimers()
    local item = CW.Item(id)
    T.truthy(item.wasSetFromAura, "the game's icon is showing the buff")
    T.eq(R.DrawnBy(id), shape == "bar" and "cooldown bar" or "own icon", "so Daylight UI draws the cooldown alone")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- Left unset, Bloodrage stays the game's icon, and since that icon marks the buff
-- itself, its Buff up options work without the game having a buff item for it
-- (hidden by default, so there is none until the layout shows it).
T.test("cdm game: a cooldown icon that shows a linked buff answers for it, as an icon and under a bar", function()
    local DUI, AB, D, R, Fx = world({ hidden = true })
    local id = CW.ID(RAGE, UTILITY)
    T.isnil(CW.Item(CW.ID(RAGE, BUFFS)), "the game has no buff item for it")
    local set = D.Current()
    D.AddPiece(set, id, "icon", 0, 0)
    T.truthy(D.SetSpellValue(set, id, "upGlow", true))
    for _, shape in ipairs({ "icon", "bar" }) do
        if shape == "bar" then D.SetShape(set, id, "bar") end
        pass(AB)
        local item = CW.Item(id)
        local lit = shape == "bar" and AB.CdmBars.AuraFrame(id) or item
        T.truthy(lit, shape .. ": something shows the buff")
        T.truthy(R.Tracked(id) ~= false, shape .. ": its state is known")
        stub.EnterCombat()
        CW.Aura("player", RAGE_BUFF, { duration = 10 }); stub.RunTimers()
        T.truthy(Fx.GlowShown(lit), shape .. ": the buff lands in a fight, Buff up glows")
        CW.Unaura("player", RAGE_BUFF); stub.RunTimers()
        T.falsy(Fx.GlowShown(lit), shape .. ": it ends, the glow goes")
        stub.LeaveCombat()
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A layout saved before Bloodrage's icon was known to show its buff read the
-- spell as a plain cooldown. As an icon that was the game's own icon, and it
-- still is. As a bar it was a cooldown bar, and it stays one: the old reading is
-- written down as the player's pick, once.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: an older layout keeps what Bloodrage showed (" .. shape .. ")", function()
    local DUI, AB, D, R = world()
    local id = CW.ID(RAGE, UTILITY)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    set.tracksKept = nil
    pass(AB)
    T.truthy(set.tracksKept, "looked at once")
    if shape == "bar" then
        T.eq(set.pieces[id].track, "cooldown", "the cooldown bar it was: kept as its pick")
        T.eq(R.DrawnBy(id), "cooldown bar")
    else
        T.isnil(set.pieces[id].track, "the game's icon then and now: left alone")
        T.eq(R.DrawnBy(id), "game")
    end
    -- A layout made after that takes the new reading.
    local rend = CW.ID(REND, ESSENTIAL)
    D.AddPiece(set, rend, shape, 60, 0)
    pass(AB)
    T.isnil(set.pieces[rend].track)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- An update from 1.9.6 must leave a layout looking as it did. These cases come
-- from running 1.9.6's Cooldown Manager and today's side by side on the game's
-- own items: an unset piece with a Hide, a sound or Glow to recast on it, or a
-- cooldown 1.9.6 remembered for a spell that has none, drew something today's
-- rules don't, unless the old reading is written down as the player's pick.
local MS, CHARGE = 12294, 100

-- A layout from before: its pieces placed, nothing looked at yet.
local function oldLayout(D, pieces)
    local set = D.Current()
    for i, p in ipairs(pieces) do
        D.AddPiece(set, p.id, p.shape or "icon", (i - 1) * 60, 0)
        for k, v in pairs(p.opts or {}) do set.pieces[p.id][k] = v end
    end
    set.tracksKept = nil
    return set
end

-- Rend's debuff as a bar. 1.9.6 drew an option on it (Hide, a buff sound, Glow to
-- recast) or a remembered cooldown with Daylight UI's bar showing the debuff and,
-- while it's down, a cooldown bar under it (a full one: Rend has no cooldown).
-- Beside it, an icon whose game icon shows its own aura looked the same either way.
-- Which warrior spell that is moves with the game's data (Thunder Clap's icon
-- stopped showing its debuff in a hotfix), so it's picked from the catalogue.
local function showsOwnAura()
    local set = CW.SetWith(REND)
    for _, r in ipairs(CW.Catalogue()) do
        if r.set == set and r.category == ESSENTIAL and r.aura and r.spell ~= REND and r.flags % 2 == 0 then
            return r.spell
        end
    end
end

for _, case in ipairs({ { "hideActive", true }, { "buffSound", "dui:done" }, { "buffEndSound", "dui:done" },
                         { "clipGlow", true }, { "remembered cooldown" } }) do
T.test("cdm game: an older Rend bar with " .. case[1] .. " keeps the cooldown bar under its debuff", function()
    local other = showsOwnAura()
    T.truthy(other ~= nil, "a warrior cooldown whose icon shows its own aura")
    local DUI, AB, D, R = world({ known = { SHOUT, REND, BLOCK, RAGE, CLAP, WALL, other } })
    local icon, bar, beside = CW.ID(REND, ESSENTIAL), CW.ID(REND, BUFFS), CW.ID(other, ESSENTIAL)
    local opts = case[2] ~= nil and { [case[1]] = case[2] } or nil
    if not opts then DUI.DB.Character().cdmCooldowns = { [REND] = true } end
    local set = oldLayout(D, { { id = icon, shape = "bar", opts = opts }, { id = beside, shape = "icon", opts = opts } })
    pass(AB)
    T.eq(set.pieces[icon].track, "both", "the old reading is kept as its pick")
    T.eq(R.DrawnBy(icon), "aura and cooldown bar", "the debuff's bar over a cooldown bar, as before")
    T.isnil(set.pieces[beside].track, "an icon looked the same either way: left alone")
    T.truthy(bar ~= nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- Bloodrage and Last Stand as icons. With a buff sound or Glow to recast on it,
-- 1.9.6 moved the spell to Daylight UI's own icon showing its cooldown alone.
-- Today the game's icon would draw it, which shows the buff's time first.
for _, case in ipairs({ { "buffSound", "dui:done" }, { "buffEndSound", "dui:done" }, { "clipGlow", true } }) do
T.test("cdm game: an older Bloodrage icon with " .. case[1] .. " keeps showing its cooldown alone", function()
    local DUI, AB, D, R = world({ known = { SHOUT, REND, BLOCK, RAGE, CLAP, WALL, 12975 } })
    local rage, stand = CW.ID(RAGE, UTILITY), CW.ID(12975, UTILITY)
    local set = oldLayout(D, { { id = rage, opts = { [case[1]] = case[2] } }, { id = stand, opts = { [case[1]] = case[2] } },
                               { id = CW.ID(REND, ESSENTIAL), opts = { [case[1]] = case[2] } } })
    pass(AB)
    for _, id in ipairs({ rage, stand }) do
        T.eq(set.pieces[id].track, "cooldown", "kept as a Cooldown pick")
        T.eq(R.DrawnBy(id), "own icon", "drawn by Daylight UI's cooldown icon, as before")
    end
    T.isnil(set.pieces[CW.ID(REND, ESSENTIAL)].track, "Rend's icon shows the same either way: left alone")
    T.eq(R.DrawnBy(CW.ID(REND, ESSENTIAL)), "game")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- A layout belongs to every character of the class that uses it, and the first
-- one to log in may not know every spell in it (a lower alt, other talents). A
-- piece it doesn't know is looked at once a character that knows it plays.
T.test("cdm game: an old piece the first character doesn't know is kept once one that knows it logs in", function()
    local DUI, AB, D, R = world({ known = { SHOUT, REND, CLAP, WALL } })
    local rage = CW.ID(RAGE, UTILITY)
    local set = oldLayout(D, { { id = rage, shape = "bar" }, { id = CW.ID(REND, ESSENTIAL), shape = "bar" } })
    pass(AB)
    T.truthy(set.tracksKept, "looked at")
    T.isnil(set.pieces[rage].track, "Bloodrage isn't known here: nothing to read yet")
    local saved = set
    -- Another warrior, who knows Bloodrage, opens the same layout.
    DUI, AB, D, R = world()
    set = D.Current()
    for k in pairs(set) do set[k] = nil end
    for k, v in pairs(saved) do set[k] = v end
    D.Changed()
    pass(AB)
    T.eq(set.pieces[rage].track, "cooldown", "the cooldown bar it was, kept now")
    T.eq(R.DrawnBy(rage), "cooldown bar")
    -- A piece placed after the update is never read the old way.
    local stand = CW.ID(12975, UTILITY)
    D.AddPiece(set, stand, "bar", 120, 0)
    pass(AB)
    T.isnil(set.pieces[stand].track, "Last Stand, placed now: today's reading")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A cooldown 1.9.6 remembered for a spell was kept per character, and the layout
-- is shared by the class: another warrior's memory counts as well, whoever logs
-- in first.
T.test("cdm game: an older layout reads the cooldowns every character of the class remembered", function()
    local DUI, AB, D, R = world()
    local chars = DUI.DB.Root().characters
    chars["Other - Realm"] = { class = "WARRIOR", cdmCooldowns = { [REND] = true } }
    chars["Mage - Realm"] = { class = "MAGE", cdmCooldowns = { [CLAP] = true } }
    local rend, clap = CW.ID(REND, ESSENTIAL), CW.ID(CLAP, ESSENTIAL)
    local set = oldLayout(D, { { id = rend, shape = "bar" } })
    pass(AB)
    T.eq(set.pieces[rend].track, "both", "another warrior's remembered cooldown: kept")
    T.eq(R.DrawnBy(rend), "aura and cooldown bar")
    T.truthy(clap ~= nil)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- A world of another class: its rows from the game's data, its spells known.
local function classWorld(class, with, known, hidden)
    stub.neverSecretAuras = {}
    local DUI = stub.Load({ actionbars = true, before = function()
        stub.SetUnits({ player = { name = "Me", class = class, friend = true },
                        target = { name = "Boar", reaction = 2 } })
        for _, id in ipairs(known) do stub.knownSpells[id] = true end
        CW.Install({ with = with, known = known, showAll = not hidden })
    end })
    stub.RunTimers()
    DUI.DB.General().motion = false
    local AB = stub.actionbars
    return DUI, AB, AB.CdmData, AB.CdmRows, AB.CdmEffects
end

-- A paladin's Aura piece stands for every aura, each of which has its own buff
-- item in the game. Whichever aura is up, the piece is up: the item of the one
-- that isn't up mustn't answer for it. Devotion Aura's own piece watches Devotion
-- alone.
local DEVOTION, RETRIBUTION = 465, 7294
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: a paladin's Aura piece is up while any one aura is (" .. shape .. ")", function()
    local DUI, AB, D, R, Fx = classWorld("PALADIN", DEVOTION, { DEVOTION, RETRIBUTION })
    local set = D.Current()
    D.AddPiece(set, "aura", shape, 0, 0)
    set.pieces.aura.missingGlow = true
    pass(AB)
    local function holder()
        return shape == "bar" and AB.CdmBars.AuraFrame("aura") or AB.CdmAuras.Frame("aura")
    end
    T.truthy(Fx.GlowShown(holder()), "no aura up: the missing glow")
    for _, aura in ipairs({ DEVOTION, RETRIBUTION }) do
        for _, fight in ipairs({ false, true }) do
            if fight then stub.EnterCombat() end
            CW.Aura("player", aura); stub.RunTimers()
            T.truthy(R.Tracked("aura"), aura .. ": the game's items tell")
            T.falsy(Fx.GlowShown(holder()), aura .. " up" .. (fight and " in a fight" or "") .. ": no glow")
            CW.Unaura("player", aura); stub.RunTimers()
            T.truthy(Fx.GlowShown(holder()), aura .. " gone" .. (fight and " in a fight" or "") .. ": the glow again")
            if fight then stub.LeaveCombat() end
        end
    end
    local ids = AB.CdmAuras.SpellIDs(CW.ID(DEVOTION, BUFFS))
    T.truthy(ids[DEVOTION], "Devotion Aura's own piece watches Devotion")
    T.isnil(ids[RETRIBUTION], "and not Retribution Aura")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- The Blessing piece is the same kind of piece: any long Blessing on you counts,
-- each has its own buff item, and the first item found mustn't answer for all of
-- them (only Blessing of Might used to count).
local MIGHT, KINGS, WISDOM = 19740, 20217, 19742
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: a paladin's Blessing piece is up while any one Blessing is (" .. shape .. ")", function()
    local DUI, AB, D, R, Fx = classWorld("PALADIN", MIGHT, { MIGHT, KINGS, WISDOM })
    local set = D.Current()
    D.AddPiece(set, "blessing", shape, 0, 0)
    set.pieces.blessing.missingGlow = true
    pass(AB)
    local function holder()
        return shape == "bar" and AB.CdmBars.AuraFrame("blessing") or AB.CdmAuras.Frame("blessing")
    end
    T.truthy(Fx.GlowShown(holder()), "no Blessing up: the missing glow")
    for _, b in ipairs({ MIGHT, KINGS, WISDOM }) do
        for _, fight in ipairs({ false, true }) do
            if fight then stub.EnterCombat() end
            CW.Aura("player", b, { duration = 300 }); stub.RunTimers()
            T.falsy(Fx.GlowShown(holder()), b .. " up" .. (fight and " in a fight" or "") .. ": no glow")
            CW.Unaura("player", b); stub.RunTimers()
            T.truthy(Fx.GlowShown(holder()), b .. " gone" .. (fight and " in a fight" or "") .. ": the glow again")
            if fight then stub.LeaveCombat() end
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- Touch of Weakness's buff row links the debuff it leaves on whoever hits you
-- (2943 and up), and the game's item, finding nothing on you, looks on your
-- target and goes active for that debuff. The buff is on you: once it's used up
-- it's missing, whatever your target carries.
local TOUCH, TOUCH_DEBUFF = 2652, 2943
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: Touch of Weakness reads missing once used up, its debuff on your target (" .. shape .. ")", function()
    local DUI, AB, D, R, Fx = classWorld("PRIEST", TOUCH, { TOUCH })
    local id = CW.ID(TOUCH, BUFFS)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    set.pieces[id].missingGlow = true
    pass(AB)
    local function lit() return shape == "bar" and AB.CdmBars.AuraFrame(id) or CW.Item(id) end
    CW.Aura("player", TOUCH); stub.RunTimers()
    T.falsy(Fx.GlowShown(lit()), "the buff is up: no glow")
    stub.EnterCombat()
    CW.Unaura("player", TOUCH)
    CW.Aura("target", TOUCH_DEBUFF, { harmful = true, duration = 120 }); stub.RunTimers()
    T.truthy(CW.Item(id).isActive, "the game's item went active for the debuff on your target")
    T.truthy(Fx.GlowShown(lit()), "used up: missing, so it glows")
    CW.Aura("player", TOUCH); stub.RunTimers()
    T.falsy(Fx.GlowShown(lit()), "cast again: up")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- New candidate filters make the client hand each button its aura again (a full
-- rebuild), which replays the slide-in. SPELLS_CHANGED comes often, so the filters
-- go out again only when a spell's ids really changed.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: SPELLS_CHANGED with the same spells leaves the aura containers alone (" .. shape .. ")", function()
    local DUI, AB, D, R = world()
    local set = D.Current()
    -- Battle Shout is a buff others cast too, so Daylight UI's own holder draws it.
    local shout = CW.ID(SHOUT, BUFFS)
    D.AddPiece(set, shout, shape, 60, 0)
    pass(AB)
    local h = shape == "bar" and AB.CdmBars.AuraFrame(shout) or AB.CdmAuras.Frame(shout)
    T.truthy(h and h.containers and h.containers[1], "Battle Shout has a container of Daylight UI's")
    local c = h.containers[1].c
    local n = c.__candidateSets or 0
    stub.FireEvent("SPELLS_CHANGED"); stub.RunTimers()
    T.eq(c.__candidateSets or 0, n, "same spells: no new filters")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- The game's buff icon is the word on a buff. A row set to show only in combat has
-- no icon to ask until a fight starts, but out of one auras read plainly, so the
-- buff can be told all the time: its options work and the card keeps offering them.
-- A row that's hidden for good, or a buff the game's layout still hides, has no icon
-- in a fight either. Those stay drawn and nothing more, in town too, since an option
-- that works in town and not in a fight reads as broken.
local THORNS = 467
local PACK = 17007   -- Leader of the Pack: on no group list, so only the game's icon can tell it
local NO_ICON = {
    { "its row only shows in combat", true, function() CW.Setting("BuffIconCooldownViewer", "VisibleSetting", Enum.CooldownViewerVisibleSetting.InCombat) end },
    { "its row is hidden", false, function() CW.Setting("BuffIconCooldownViewer", "VisibleSetting", Enum.CooldownViewerVisibleSetting.Hidden) end },
    { "the game's layout hides the buff", false, nil, true },
}
for _, case in ipairs(NO_ICON) do
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: a buff with no game icon to ask right now, " .. case[1] .. " (" .. shape .. ")", function()
    local DUI, AB, D, R, Fx = classWorld("DRUID", PACK, { PACK }, case[4])
    local id = CW.ID(PACK, BUFFS)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    set.pieces[id].missing, set.pieces[id].missingGlow = true, true
    pass(AB)
    if case[3] then
        -- Leader of the Pack is hidden by default. Daylight UI switched it on in the game's
        -- layout at login, and remembers that it did.
        DUI.DB.Character().cdmSwitched = { [id] = BUFFS }
        case[3](); stub.RunTimers()
        T.falsy(BuffIconCooldownViewer:IsShown(), "the game's row is out of sight")
    end
    local function holder()
        return shape == "bar" and AB.CdmBars.AuraFrame(id) or AB.CdmAuras.Frame(id)
    end
    if not case[2] then
        T.eq(R.Tracked(id), false, "nothing can tell in a fight: the card leaves the rows out")
        T.falsy(Fx.GlowShown(holder()), "and no glow in town either")
        CW.Aura("player", PACK, { duration = 600 }); stub.RunTimers()
        T.eq(R.Tracked(id), false, "the same while it's up")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        return
    end
    T.truthy(R.Tracked(id), "the card offers Hide, the glows and the sounds")
    T.truthy(Fx.GlowShown(holder()), "not up: the missing glow")
    CW.Aura("player", PACK, { duration = 600 }); stub.RunTimers()
    T.truthy(R.Tracked(id), "still offered while it's up")
    T.falsy(Fx.GlowShown(holder()), "up: no glow")
    CW.Unaura("player", PACK); stub.RunTimers()
    T.truthy(R.Tracked(id), "and after it dropped")
    T.truthy(Fx.GlowShown(holder()), "gone: the glow again")
    -- In a fight the game's row is back, and its icon answers again.
    stub.EnterCombat(); stub.FireEvent("PLAYER_IN_COMBAT_CHANGED", true); stub.RunTimers()
    T.truthy(BuffIconCooldownViewer:IsShown(), "the game's row shows in a fight")
    -- There the game's icon draws it again, a stand-in while it's down.
    local function lit()
        return holder(), CW.Item(id), AB.CdmOwn.PlaceholderFrame(id, shape)
    end
    local function glows()
        for _, f in ipairs({ lit() }) do
            if f and f:IsShown() and Fx.GlowShown(f) then return true end
        end
        return false
    end
    T.truthy(glows(), "missing in a fight: the glow")
    CW.Aura("player", PACK, { duration = 600 }); stub.RunTimers()
    T.falsy(glows(), "up in a fight: no glow")
    CW.Unaura("player", PACK); stub.RunTimers()
    T.truthy(glows(), "dropped in a fight: the glow again")
    stub.LeaveCombat(); stub.FireEvent("PLAYER_IN_COMBAT_CHANGED", false); stub.RunTimers()
    T.falsy(BuffIconCooldownViewer:IsShown(), "the row goes again after the fight")
    T.truthy(R.Tracked(id), "still offered")
    T.truthy(Fx.GlowShown(holder()), "and the glow stays")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end
end

-- A spell placed a moment ago has its card drawn before a pass has looked at it.
-- Once the pass finds nothing can tell its buff, the card is drawn again, so it
-- shows the same rows now as when the spell is picked again later.
T.test("cdm game: the card is drawn again once a just-placed buff has been looked at", function()
    local DUI, AB, D, R = classWorld("DRUID", PACK, { PACK }, true)
    local id = CW.ID(PACK, BUFFS)
    local Ed, Card = AB.CdmEditor, AB.CdmCard
    Ed.Open(1); stub.RunTimers()
    D.AddPiece(D.Current(), id, "icon", 0, 0)
    D.Changed()
    Ed.Select(id)
    T.truthy(Card.Shown(), "its card is up")
    T.isnil(R.Tracked(id), "no pass has looked at it yet")
    local draws, draw = 0, Card.Draw
    Card.Draw = function(...) draws = draws + 1; return draw(...) end
    R.Refresh(); stub.RunTimers()
    T.eq(R.Tracked(id), false, "the pass found nothing to ask")
    T.truthy(draws > 0, "and the card was drawn again")
    local n = draws
    R.Refresh(); stub.RunTimers()
    T.eq(draws, n, "not again while nothing changed")
    Card.Draw = draw
    Ed.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm game: a set glow color shows the row's reset arrow, and the arrow puts it back on the accent", function()
    local DUI, AB, D = classWorld("DRUID", THORNS, { THORNS }, true)
    local id = CW.ID(THORNS, BUFFS)
    local Ed, Card, O = AB.CdmEditor, AB.CdmCard, DUI.Options
    Ed.Open(1); stub.RunTimers()
    D.AddPiece(D.Current(), id, "icon", 0, 0)
    D.Changed()
    Ed.Select(id)
    local item, row
    for _, rows in pairs(Card.ROWS) do
        for _, r in ipairs(rows) do
            if r.item and r.item.key == "cdm.card.readyGlowColor" then item, row = r.item, r.frame end
        end
    end
    T.truthy(item, "the ready glow color row")
    T.truthy(row and row.reset, "the card row has a reset arrow")
    T.truthy(O.IsDefault({}, item), "unset")
    row.Refresh(); stub.RunTimers()
    T.falsy(row.reset:IsShown(), "unset: no arrow")
    item.set({ 0, 1, 0 })
    row.Refresh(); stub.RunTimers()
    T.falsy(O.IsDefault({}, item), "set")
    T.truthy(row.reset:IsShown(), "set: the arrow shows")
    row.reset:GetScript("OnClick")(row.reset)
    stub.RunTimers()
    T.isnil(D.Current().pieces[id].readyGlowColor, "the arrow clears it")
    local r, g, b = DUI.Style.Accent()
    T.rgb(item.get(), { r, g, b }, "so the row shows the accent")
    T.truthy(O.IsDefault({}, item))
    Ed.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- With nothing to tell the buff, the card says why its up and missing options are
-- gone. Without a word, a buff row hidden in Edit Mode looked like options that had
-- vanished in an update.
for _, case in ipairs({ { "its row is hidden", "Tracked Buffs row is set to Hidden" },
                        { "the game's layout hides the buff", "makes no icon for this buff" } }) do
T.test("cdm game: the card says why a buff has no up or missing options, " .. case[1], function()
    local DUI, AB, D, R = classWorld("DRUID", PACK, { PACK }, case[1] ~= "its row is hidden")
    if case[1] == "its row is hidden" then
        CW.Setting("BuffIconCooldownViewer", "VisibleSetting", Enum.CooldownViewerVisibleSetting.Hidden); stub.RunTimers()
    end
    local id = CW.ID(PACK, BUFFS)
    local Ed, Card = AB.CdmEditor, AB.CdmCard
    Ed.Open(1); stub.RunTimers()
    D.AddPiece(D.Current(), id, "icon", 0, 0)
    D.Changed()
    Ed.Select(id)
    R.Refresh(); stub.RunTimers()
    T.eq(R.Tracked(id), false)
    Card.SetTab("show")
    local note
    for _, r in ipairs(Card.ROWS.show) do if r.box == "note" then note = r.frame end end
    T.truthy(note and note:IsShown(), "the note is on the Behavior tab")
    local text = note.text:GetText() or ""
    T.truthy(text:find(case[2], 1, true), text)
    Ed.Close()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- The game's item finds an aura only by the spell ids its row lists. Some rows
-- stop at rank 1: Sap's lists none of the debuffs its higher ranks leave, and
-- Touch of Weakness's lists the debuff on your attacker but not the buff's own
-- higher ranks. With such a rank learned the item stays dark while the aura is up,
-- so its "down" is no answer and Daylight UI draws the aura itself.
local SAP, SAP_2 = 6770, 2070
local TOUCH_3 = 19262
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: Sap from a rank the game's row doesn't list shows on the sapped target (" .. shape .. ")", function()
    stub.knownSpells = {}
    local DUI, AB, D, R = classWorld("ROGUE", SAP, { SAP, SAP_2 })
    local id = CW.ID(SAP, BUFFS)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    pass(AB)
    stub.EnterCombat()
    CW.Aura("target", SAP_2, { harmful = true, duration = 35 }); stub.RunTimers()
    T.falsy(CW.Item(id).isActive, "the game's item never sees rank 2's debuff")
    T.eq(R.DrawnBy(id), shape == "bar" and "aura bar" or "aura icon", "so Daylight UI draws it")
    T.truthy(pieceFrame(id):IsShown(), "and its piece is on screen")
    local h = shape == "bar" and AB.CdmBars.AuraFrame(id) or AB.CdmAuras.Frame(id)
    T.truthy(h.ids[SAP_2], "watching rank 2's debuff")
    local onTarget = false
    for _, k in ipairs(h.containers) do
        if k.unit == "target" and string.find(k.filter, "HARMFUL", 1, true) then onTarget = true end
    end
    T.truthy(onTarget, "among your debuffs on the target")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm game: Touch of Weakness from a rank the game's row doesn't list isn't called missing (" .. shape .. ")", function()
    stub.knownSpells = {}
    local DUI, AB, D, R, Fx = classWorld("PRIEST", TOUCH, { TOUCH, 19261, TOUCH_3 })
    local id = CW.ID(TOUCH, BUFFS)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    set.pieces[id].missingGlow = true
    pass(AB)
    CW.Aura("player", TOUCH_3, { duration = 600 }); stub.RunTimers()
    stub.EnterCombat(); stub.RunTimers()
    T.falsy(CW.Item(id).isActive, "the game's item never sees rank 3's buff")
    T.eq(R.DrawnBy(id), shape == "bar" and "aura bar" or "aura icon", "so Daylight UI draws it")
    local h = shape == "bar" and AB.CdmBars.AuraFrame(id) or AB.CdmAuras.Frame(id)
    T.truthy(h.ids[TOUCH_3], "watching rank 3's buff")
    T.falsy(Fx.GlowShown(h), "the buff is up: no missing glow from the item's silence")
    T.eq(R.Tracked(id), false, "nothing can tell in a fight, so the card leaves the state rows out")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("cdm game: a row that lists every rank you know keeps the game's item as its word (" .. shape .. ")", function()
    stub.knownSpells = {}
    local DUI, AB, D, R = classWorld("ROGUE", SAP, { SAP })
    local id = CW.ID(SAP, BUFFS)
    D.AddPiece(D.Current(), id, shape, 0, 0)
    pass(AB)
    T.falsy(AB.CdmAuras.GameBlind(id), "rank 1 alone is on the row")
    CW.Aura("target", SAP, { harmful = true, duration = 25 }); stub.RunTimers()
    T.truthy(CW.Item(id).isActive, "the game's item sees it")
    T.truthy(R.Tracked(id), "and answers for it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- A player's warrior: Battle Shout set to Buff only, Buff up Hide, Buff missing
-- Show with its glow, every stance on, hooked right of another spell in a group
-- shown only in a fight, with Slide over on. While a shout is on you it stays out
-- of sight, in a fight too (auras secret), yours or another warrior's: the game's
-- own item only ever lights for yours, so with someone else's up it read as
-- missing and showed, glowing.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: Battle Shout set to show only while missing stays hidden while any shout is up (" .. shape .. ")", function()
    local DUI, AB, D, R, Fx = world({ known = { SHOUT, 5242, 6192, 11549, 11550, 11551, 25289, REND, CLAP } })
    local shout, rend = CW.ID(SHOUT, BUFFS), CW.ID(REND, ESSENTIAL)
    local set = D.Current()
    D.AddPiece(set, rend, "icon", 0, 0)
    D.AddPiece(set, shout, shape, 0, 0)
    T.truthy(D.Hook(set, shout, rend, "right", "center"))
    local p = set.pieces[shout]
    p.track, p.hideActive, p.missing, p.missingGlow = "buff", true, true, true
    T.truthy(D.SetChainValue(set, rend, "combat", true))
    T.truthy(D.SetChainValue(set, rend, "collapse", true))
    pass(AB)
    local function holder()
        return shape == "bar" and AB.CdmBars.AuraFrame(shout) or AB.CdmAuras.Frame(shout)
    end
    -- The fake container doesn't match auras itself. As the client's does, it shows
    -- its button for any caster's shout on you (HELPFUL, no PLAYER), in a fight too.
    local function button()
        local h = holder()
        for _, k in ipairs(h.containers) do
            if k.unit == "player" and k.filter == "HELPFUL" then return k.c.__groups.a.button, k.c end
        end
    end
    local function shoutOn(from)
        CW.Aura("player", 25289, { duration = 120, sourceUnit = from })
        stub.AuraVisible((button()), true); stub.RunTimers()
    end
    local function shoutOff()
        CW.Unaura("player", 25289)
        stub.AuraVisible((button()), false); stub.RunTimers()
    end
    -- What a player sees of it: the client's button, the icon kept in its spot,
    -- the glow.
    local function seen()
        local h = holder()
        local out = {}
        local btn, c = button()
        if btn.__auraShown and c:GetAlpha() > 0 then out[#out + 1] = "button" end
        if h.underBox and h.underBox:IsShown() and (h.underAlpha or 1) > 0 then out[#out + 1] = "icon" end
        if Fx.GlowShown(h) then out[#out + 1] = "glow" end
        return #out == 0 and "hidden" or table.concat(out, "+")
    end
    -- A bar keeps an empty bar in its spot, under the glow.
    local missing = shape == "bar" and "glow" or "icon+glow"
    shoutOn()
    T.eq(R.DrawnBy(shout), shape == "bar" and "aura bar" or "aura icon", "drawn by Daylight UI's holder")
    T.truthy(R.Tracked(shout), "the card offers Buff up and Buff missing")
    T.eq(seen(), "hidden", "your shout, out of a fight: hidden")
    stub.EnterCombat(); stub.FireEvent("PLAYER_REGEN_DISABLED"); stub.RunTimers()
    T.eq(seen(), "hidden", "a fight starts: hidden")
    shoutOff(); shoutOn()
    T.eq(seen(), "hidden", "shouted again over it: hidden")
    stub.FireEvent("UPDATE_SHAPESHIFT_FORM"); stub.RunTimers()
    T.eq(seen(), "hidden", "a stance swap: hidden")
    shoutOff()
    T.eq(seen(), missing, "ran out: shown, glowing")
    -- Another warrior's shout takes the place of yours.
    shoutOn("party1")
    T.falsy(CW.Item(shout).isActive, "the game's item never lights for someone else's")
    T.eq(seen(), "hidden", "another warrior's shout in a fight: hidden")
    shoutOff()
    T.eq(seen(), missing, "theirs ran out: shown, glowing")
    shoutOn("party1")
    stub.LeaveCombat(); stub.FireEvent("PLAYER_REGEN_ENABLED"); stub.RunTimers()
    T.eq(seen(), "hidden", "theirs as the fight ends: hidden")
    shoutOff()
    T.eq(seen(), missing, "theirs gone out of a fight: shown")
    shoutOn("party1")
    T.eq(seen(), "hidden", "theirs out of a fight: hidden")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end

-- A group buff (Thorns) is drawn by Daylight UI's holder, which shows anyone's
-- copy. With no game icon at all (its row hidden in Edit Mode) the holder's own
-- button still tells whether it's up, in a fight too.
for _, shape in ipairs({ "icon", "bar" }) do
T.test("cdm game: a group buff with its row hidden is still told by its own button (" .. shape .. ")", function()
    local DUI, AB, D, R, Fx = classWorld("DRUID", THORNS, { THORNS })
    local id = CW.ID(THORNS, BUFFS)
    local set = D.Current()
    D.AddPiece(set, id, shape, 0, 0)
    set.pieces[id].missing, set.pieces[id].missingGlow = true, true
    CW.Setting("BuffIconCooldownViewer", "VisibleSetting", Enum.CooldownViewerVisibleSetting.Hidden)
    pass(AB)
    local h = shape == "bar" and AB.CdmBars.AuraFrame(id) or AB.CdmAuras.Frame(id)
    local btn = h.containers[1].c.__groups.a.button
    T.truthy(R.Tracked(id), "the card offers its up and missing rows")
    T.truthy(Fx.GlowShown(h), "not up: the missing glow")
    stub.EnterCombat(); stub.RunTimers()
    CW.Aura("player", THORNS, { duration = 600, sourceUnit = "party1" })
    stub.AuraVisible(btn, true); stub.RunTimers()
    T.falsy(Fx.GlowShown(h), "a friend's Thorns in a fight: up, no glow")
    CW.Unaura("player", THORNS)
    stub.AuraVisible(btn, false); stub.RunTimers()
    T.truthy(Fx.GlowShown(h), "gone in a fight: the glow again")
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
end
