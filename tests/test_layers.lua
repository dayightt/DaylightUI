local stub = require("stub")

-- Layers: each frame's parts in one list, top first (a part draws over every
-- part below it) and, standing on its own, a part's layer. Untouched parts keep
-- the level their own code gives them.

local function login()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Daylight", isPlayer = true, class = "WARRIOR", health = 50, maxHealth = 50 }
    end })
    stub.RunTimers()
    return DUI, ns
end

local function set(key, v)
    DaylightUI:Set("UnitFrames", key, v)
    stub.RunTimers()
end

local function freeTarget()
    local DUI, ns = login()
    set("target.powerAt", "free")
    set("target.portraitAt", "free")
    return DUI, ns, ns.frames.target
end

-- Saves the list with key just over (or under) another part, or on top.
local function place(ns, unit, key, other, under)
    local stack = {}
    for _, k in ipairs(ns.Layers.Stack(unit)) do if k ~= key then stack[#stack + 1] = k end end
    local at = 1
    for i, k in ipairs(stack) do if k == other then at = under and i + 1 or i end end
    table.insert(stack, at, key)
    ns.Layers.Save(unit, stack, nil, false)
    stub.RunTimers()
end

local function findItem(page, match)
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items or {}) do if match(it) then return it end end
        for _, sub in ipairs(g.groups or {}) do
            for _, it in ipairs(sub.items or {}) do if match(it) then return it end end
        end
    end
end

T.test("layers: untouched parts keep their levels, and the list ranks them as they draw", function()
    local _, ns, f = freeTarget()
    local L, base = ns.Layers, f:GetFrameLevel()
    T.eq(f.freePower:GetFrameLevel(), base + ns.UF.PIECE_LIFT, "power where it always was")
    T.eq(f.portraitHolder:GetFrameLevel(), base + ns.UF.PIECE_LIFT + ns.UF.PORTRAIT_LIFT)
    T.truthy(L.OrderOf("target", "portrait") > L.OrderOf("target", "power"), "the portrait ranks over the power bar")
    T.truthy(L.OrderOf("target", "power") > L.OrderOf("target", "health"))
    T.truthy(L.Untouched("target"))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: a part higher in the list draws over another, and Reset layers puts it back", function()
    local _, ns, f = freeTarget()
    local L, was = ns.Layers, f.freePower:GetFrameLevel()
    place(ns, "target", "power", "portrait")
    T.truthy(L.LowOf(f.freePower) > L.TopOf(f.portraitHolder), "power over the whole portrait")
    L.Reset("target")
    stub.RunTimers()
    T.eq(f.freePower:GetFrameLevel(), was, "back where its own code had it")
end)

T.test("layers: moving the portrait leaves the level, crown and PvP icons over it", function()
    local _, ns, f = freeTarget()
    local L, icons = ns.Layers, f.status.icons
    place(ns, "target", "portrait", "health", true)
    for _, k in ipairs({ "level", "leader", "pvp" }) do
        T.truthy(icons[k]:GetParent():GetFrameLevel() > L.TopOf(f.portraitHolder), k .. " stays over it")
    end
    T.eq(f.status.levelText:GetParent(), icons.level:GetParent(), "the level's number goes with its badge")
end)

T.test("layers: moving the power bar leaves its text where it is", function()
    local _, ns, f = freeTarget()
    place(ns, "target", "power")
    T.truthy(f.powerText:GetParent():GetFrameLevel() < f.freePower:GetFrameLevel(), "the text didn't go up with it")
end)

T.test("layers: a raid marker gets a frame of its own, and reset puts it back", function()
    local _, ns, f = freeTarget()
    local home = f.marker:GetParent()
    place(ns, "target", "marker")
    local c = f.marker:GetParent()
    T.truthy(c ~= home)
    T.truthy(c:GetFrameLevel() > ns.Layers.TopOf(f.health), "over the bar")
    ns.Layers.Reset("target")
    stub.RunTimers()
    T.eq(f.marker:GetParent(), home, "back in its own frame")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: buffs and debuffs are layered on their own", function()
    local _, ns = freeTarget()
    place(ns, "target", "debuffs", "buffs")
    T.truthy(ns.auras.debuffs:GetFrameLevel() > ns.Layers.TopOf(ns.auras.buffs), "debuffs over buffs")
end)

T.test("layers: the options preview draws the same order", function()
    local _, ns = freeTarget()
    place(ns, "target", "health", "portrait")
    local s = ns.PageSample.New("target", UIParent)
    s.Refresh(400, 200)
    local f = s.f
    T.truthy(f.health:GetFrameLevel() > ns.Layers.TopOf(f.portrait), "the preview stacks the bar over the portrait")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: a part on its own takes a layer, Same as frame follows the frame", function()
    local _, ns, f = freeTarget()
    set("target.parts.power.layer", "HIGH")
    T.eq(f.freePower:GetFrameStrata(), "HIGH")
    set("target.parts.power.layer", nil)
    T.eq(f.freePower:GetFrameStrata(), f:GetFrameStrata(), "with the frame again")
end)

T.test("layers: Bring forward and Send back step past what a part overlaps", function()
    local _, ns, f = freeTarget()
    local L = ns.Layers
    local stack = L.Step("target", "power", { f.portraitHolder }, true)
    T.truthy(stack, "a step up")
    L.Save("target", stack, "power", false)
    stub.RunTimers()
    T.eq(L.OrderOf("target", "power"), L.OrderOf("target", "portrait") + 1, "just over the portrait")
    T.truthy(L.LowOf(f.freePower) > L.TopOf(f.portraitHolder), "over the portrait and its ring")
    stack = L.Step("target", "power", { f.portraitHolder }, false)
    L.Save("target", stack, "power", false)
    stub.RunTimers()
    T.eq(L.OrderOf("target", "power"), L.OrderOf("target", "portrait") - 1, "just under it")
    T.truthy(L.TopOf(f.freePower) < L.LowOf(f.portraitHolder), "under it again")
    local none, why = L.Step("target", "power", {}, true)
    T.isnil(none)
    T.eq(why, "top")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: stepping past aura rows doesn't look inside the game's containers", function()
    local _, ns, f = freeTarget()
    local rows = ns.auras.debuffs
    local btn = CreateFrame("Button", nil, rows)
    btn:SetFrameLevel(rows:GetFrameLevel() + 40)
    btn.__shown = stub.Secret(true)
    T.eq(ns.Layers.TopOf(rows), rows:GetFrameLevel() + 2, "its buttons counted, not looked into")
    ns.Layers.Step("target", "power", { rows, f.portraitHolder }, true)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: each covered frame's page has a Layers card that validates", function()
    local DUI = login()
    for _, id in ipairs({ "player", "target", "focus", "pet" }) do
        local page = DUI.Options.GetPage("UnitFrames." .. id)
        local found
        for _, g in ipairs(page.groups) do
            if g.label == "Layers" then found = g end
            for _, sub in ipairs(g.groups or {}) do if sub.label == "Layers" then found = sub end end
        end
        T.truthy(found, id .. " has Layers")
        T.eq(#DUI.Options.ValidatePage(page), 0, id)
    end
end)

T.test("layers: Reset layers puts every part back", function()
    local _, ns, f = freeTarget()
    local was = f.freePower:GetFrameLevel()
    T.truthy(ns.Layers.Untouched("target"))
    place(ns, "target", "power")
    set("target.parts.power.layer", "HIGH")
    T.falsy(ns.Layers.Untouched("target"))
    ns.Layers.Reset("target")
    stub.RunTimers()
    T.eq(f.freePower:GetFrameLevel(), was)
    T.eq(f.freePower:GetFrameStrata(), f:GetFrameStrata())
    T.truthy(ns.Layers.Untouched("target"))
end)

T.test("layers: the target page has a Layers tab", function()
    local DUI = login()
    local P = DUI.OptionsPanel
    P.Show("UnitFrames.target")
    local tabs = P.PageFrame().tabs
    T.eq(tabs[#tabs], "Layers")
    P.Show("UnitFrames.party")
    tabs = P.PageFrame().tabs
    T.truthy(tabs[#tabs] ~= "Layers", "not on party")
end)

T.test("layers: a level change leaves the game's aura buttons alone", function()
    local _, ns = freeTarget()
    local rows = ns.auras.buffs
    local btn = CreateFrame("Button", nil, rows)
    local edge = CreateFrame("Frame", nil, btn)
    btn:SetFrameLevel(rows:GetFrameLevel() + 1)
    edge:SetFrameLevel(btn:GetFrameLevel() + 3)
    local was = rows:GetFrameLevel()
    place(ns, "target", "buffs")
    T.truthy(rows:GetFrameLevel() > was, "the row moved")
    T.isnil(btn.levelOffset, "nothing noted inside the container")
    T.isnil(edge.levelOffset)
end)

T.test("layers: an extra text is in the list only while it's added, and a move steps over it", function()
    local _, ns = login()
    local L = ns.Layers
    local function shown(key)
        for _, k in ipairs(L.Shown("target")) do if k == key then return true end end
        return false
    end
    T.falsy(shown("text1"), "not listed while unused")
    -- Put the unused text between two parts: a move skips it.
    local stack = {}
    for _, k in ipairs(L.Stack("target")) do if k ~= "text1" and k ~= "buffs" then stack[#stack + 1] = k end end
    for i, k in ipairs(stack) do
        if k == "debuffs" then table.insert(stack, i, "buffs"); table.insert(stack, i + 1, "text1"); break end
    end
    L.Save("target", stack, nil, false)
    stub.RunTimers()
    T.truthy(L.Move("target", "debuffs", true))
    local after = L.Stack("target")
    local at = {}
    for i, k in ipairs(after) do at[k] = i end
    T.truthy(at.debuffs < at.buffs, "debuffs went over the buffs, past the unused text")
    set("target.texts.t1.show", true)
    T.truthy(shown("text1"), "listed once added")
end)

T.test("layers: the frame's border moves with its health bar", function()
    local DUI, ns, f = freeTarget()
    local shell = DUI.Style.GetShell(f)
    local gap = shell:GetFrameLevel() - f.health:GetFrameLevel()
    place(ns, "target", "health")
    T.eq(shell:GetFrameLevel(), f.health:GetFrameLevel() + gap, "same gap under the bar")
    ns.Layers.Reset("target")
    stub.RunTimers()
    T.eq(shell:GetFrameLevel() - f.health:GetFrameLevel(), gap, "back")
end)

T.test("layers: incoming heals, absorbs and the overshield stay over the health bar wherever it moves", function()
    for _, unit in ipairs({ "player", "target" }) do
        local _, ns = freeTarget()
        local f = ns.frames[unit]
        local bars = { heals = f.heals, healWedge = f.heals.wedge, absorbs = f.absorbs,
                       absorbWedge = f.absorbs.wedge, overshield = f.overshield }
        local gaps = {}
        for what, b in pairs(bars) do gaps[what] = b:GetFrameLevel() - f.health:GetFrameLevel() end
        place(ns, unit, "health")
        for what, b in pairs(bars) do
            T.eq(b:GetFrameLevel() - f.health:GetFrameLevel(), gaps[what], unit .. " " .. what .. " keeps its gap")
        end
        ns.Layers.Reset(unit)
        stub.RunTimers()
        for what, b in pairs(bars) do
            T.eq(b:GetFrameLevel() - f.health:GetFrameLevel(), gaps[what], unit .. " " .. what .. " back")
        end
    end
end)

-- A hunter's pet: the live frame's happiness square is ns.happiness, and its
-- "On the frame" stripe draws over the health bar.
local function hunterPet()
    local DUI, ns = stub.Load({ module = true, before = function()
        stub.units.player = { name = "Hunts", isPlayer = true, class = "HUNTER" }
        _G.HasPetUI = function() return true, true end
        _G.C_PetInfo = {
            GetPetHappiness = function() return 2, 125, 1 end,
            GetPetFoodTypes = function() return { "Meat" } end,
        }
    end })
    stub.RunTimers()
    return DUI, ns, ns.frames.pet
end

T.test("layers: the live pet's happiness square moves with its place in the list", function()
    local _, ns, f = hunterPet()
    local h = ns.happiness
    T.truthy(h and h.pet == f, "the live square")
    place(ns, "pet", "happiness")
    T.truthy(h:GetFrameLevel() > ns.Layers.TopOf(f.health), "on top of the list, over the health bar")
    place(ns, "pet", "happiness", "health", true)
    T.truthy(h:GetFrameLevel() < f.health:GetFrameLevel(), "under the health bar")
end)

T.test("layers: the pet's happiness stripe stays over its health bar wherever the bar moves", function()
    local DUI, ns, f = hunterPet()
    DUI:Set("UnitFrames", "pet.happinessLook", "frame")
    stub.RunTimers()
    local band = ns.happiness.band
    T.truthy(band and band:IsShown(), "the stripe shows")
    local gap = band:GetFrameLevel() - f.health:GetFrameLevel()
    T.truthy(gap > 0, "over the bar to start")
    place(ns, "pet", "health")
    T.eq(band:GetFrameLevel() - f.health:GetFrameLevel(), gap, "keeps its gap over the bar")
end)

T.test("layers: the preview's stand-in aura rows take their place", function()
    local _, ns = freeTarget()
    place(ns, "target", "buffs")
    local s = ns.PageSample.New("target", UIParent)
    s.Refresh(400, 200)
    local h = ns.Auras.HolderFor(s.f.sampleAuras.buffs)
    T.truthy(h, "a holder")
    T.eq(h:GetFrameLevel(), s.f.sampleAuras.buffs:GetFrameLevel(), "the sample icons sit with their row")
    T.truthy(h:GetFrameLevel() > ns.Layers.TopOf(s.f.health), "over the bar")
end)

T.test("layers: a portrait under the bar takes its ring and icons under too", function()
    local _, ns = login()
    local f = ns.frames.target
    place(ns, "target", "health", "portrait")
    local top = ns.Layers.TopOf(f.portrait)
    for _, g in ipairs({ f.socket, f.status, f.dotSkull }) do
        if g then top = math.max(top, ns.Layers.TopOf(g)) end
    end
    T.truthy(ns.Layers.LowOf(f.health) > top, "the whole portrait under the whole bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: the list holds every part once, and the page shows it as one list", function()
    local DUI, ns = login()
    local stack, seen = ns.Layers.Stack("target"), {}
    T.eq(#stack, #ns.Layers.PARTS.target)
    for _, k in ipairs(stack) do
        T.falsy(seen[k], k .. " once")
        seen[k] = true
    end
    local page = DUI.Options.GetPage("UnitFrames.target")
    T.truthy(findItem(page, function(it) return it.type == "custom" and it.label == "Draw order" end), "the list")
    T.isnil(findItem(page, function(it) return it.type == "slider" and type(it.key) == "string" and it.key:find("%.parts%.") end), "no sliders")
    T.truthy(findItem(page, function(it) return it.key == "target.parts.power.layer" end), "the power bar's layer")
end)

T.test("layers: the swing timer is one of the player's parts", function()
    local _, ns = login()
    local part = ns.Layers.Find("player", "swing")
    T.truthy(part, "listed")
    T.truthy(part.ownLayer, "its own page keeps its layer")
end)

T.test("layers: a saved list drops unknown parts and puts missing ones where they draw", function()
    local _, ns = login()
    local L = ns.Layers
    local default = L.Stack("target")
    local stack = {}
    for _, k in ipairs(default) do if k ~= "crest" then stack[#stack + 1] = k end end
    stack[#stack + 1] = "gone"
    set("target.parts.order", stack)
    T.eq(table.concat(L.Stack("target"), ","), table.concat(default, ","))
end)

T.test("layers: an old Order slider value is ignored", function()
    local _, ns, f = freeTarget()
    local was = f.freePower:GetFrameLevel()
    set("target.parts.power", { order = 19 })
    T.truthy(ns.Layers.Untouched("target"))
    T.eq(f.freePower:GetFrameLevel(), was)
    place(ns, "target", "debuffs", "buffs")
    T.isnil(ns.Layers.Saved("target", "power"), "the next save drops it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: moving a part back to its place leaves the frame untouched", function()
    local _, ns = login()
    local L = ns.Layers
    T.truthy(L.Move("target", "power", true))
    stub.RunTimers()
    T.falsy(L.Untouched("target"), "moved")
    T.truthy(L.Move("target", "power", false))
    stub.RunTimers()
    T.truthy(L.Untouched("target"), "back in place")
    T.isnil(L.Move("target", L.Stack("target")[1], true) or nil, "the top part can't go up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: the options list moves a part with its up button", function()
    local DUI, ns = login()
    local page = DUI.Options.GetPage("UnitFrames.target")
    local item = findItem(page, function(it) return it.label == "Draw order" end)
    local row = CreateFrame("Frame", nil, UIParent)
    item.build(row)
    item.update(row)
    local shown = ns.Layers.Shown("target")
    T.eq(row.count, #shown)
    T.falsy(row.lines[1].move.up.enabled, "the top line can't go up")
    T.falsy(row.lines[#shown].move.down.enabled, "the bottom line can't go down")
    local second = row.lines[2]
    T.eq(second.key, shown[2])
    second.move.up:GetScript("OnClick")(second.move.up)
    stub.RunTimers()
    T.eq(ns.Layers.Stack("target")[1], shown[2], "it went to the top")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("layers: Bring forward and Send back gray out with the reason, and say nothing in chat", function()
    local DUI, ns, f = freeTarget()
    local M = DUI.Movers
    local key = ns.PowerBar.KeyFor("target")
    M.Unlock()
    local overlapping = {}
    M.Overlapping = function() return overlapping end
    M.OpenEditor(key)
    local editor = M.Editor()
    T.truthy(editor.forward.off, "nothing over it: forward is off")
    T.truthy(editor.back.off, "nothing under it: back is off")
    T.eq(editor.forward.why, DUI.L["Already over everything it overlaps"])
    local lines = {}
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:AddLine(t) lines[#lines + 1] = tostring(t) end
    function tip:AddDoubleLine(l, r) lines[#lines + 1] = tostring(l) .. " " .. tostring(r) end
    editor.forward:GetScript("OnEnter")(editor.forward)
    _G.GameTooltip = nil
    T.truthy(table.concat(lines, "\n"):find(DUI.L["Already over everything it overlaps"], 1, true), "the reason in its tooltip")
    local chat = #stub.chat
    T.falsy(M.StepLayer(key, true))
    T.eq(#stub.chat, chat, "no chat line")
    overlapping[1] = f.portraitHolder.key
    M.RefreshEditor()
    T.falsy(editor.forward.off, "the portrait over it: forward is on")
    T.isnil(editor.forward.why)
    T.truthy(M.StepLayer(key, true))
    stub.RunTimers()
    T.eq(ns.Layers.OrderOf("target", "power"), ns.Layers.OrderOf("target", "portrait") + 1, "stepped over it")
    T.truthy(editor.forward.off, "and now it's over everything it overlaps")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- How two parts draw against each other: 1 (a over b), -1 (b over a), or nil
-- when nothing decides it (two frames on one level, a frame beside a text).
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local DRAW = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local REGION = { Texture = true, FontString = true, Line = true }
local function drawKey(x)
    if not REGION[x:GetObjectType()] then return { STRATA[x:GetFrameStrata() or "MEDIUM"] or 3, x:GetFrameLevel() } end
    local p = x:GetParent()
    local layer, sub = x:GetDrawLayer()
    return { STRATA[p:GetFrameStrata() or "MEDIUM"] or 3, p:GetFrameLevel(), DRAW[layer] or 3, sub or 0, region = true }
end
local function over(a, b)
    for i = 1, 2 do if a[i] ~= b[i] then return a[i] > b[i] and 1 or -1 end end
    if not (a.region and b.region) then return nil end
    for i = 3, 4 do if a[i] ~= b[i] then return a[i] > b[i] and 1 or -1 end end
    return nil
end
local function drawKeys(ns, unit)
    local f, out = ns.frames[unit], {}
    for _, part in ipairs(ns.Layers.PARTS[unit]) do
        local got = part.get(f)
        local x = type(got) == "table" and (got.GetObjectType and got or got[1]) or nil
        if x then out[part.key] = drawKey(x) end
    end
    return out
end

T.test("layers: moving one part leaves every other pair drawing the same way round", function()
    local _, ns = login()
    local L = ns.Layers
    for _, unit in ipairs({ "player", "target" }) do
        set(unit .. ".powerAt", "free")
        set(unit .. ".portraitAt", "free")
    end
    set("playerCastbar.at", "free")
    set("targetCastbar.at", "free")
    for _, unit in ipairs({ "player", "target" }) do
        local was = drawKeys(ns, unit)
        T.truthy(was.portrait and was.power and was.castbar, unit .. " has its free pieces")
        for _, key in ipairs(L.Stack(unit)) do
            T.truthy(L.Move(unit, key, true) or L.Move(unit, key, false), unit .. " moves " .. key)
            stub.RunTimers()
            T.falsy(L.Untouched(unit), unit .. " set")
            local now, moved = drawKeys(ns, unit), {}
            for a, ka in pairs(was) do
                for b, kb in pairs(was) do
                    local before = a < b and a ~= key and b ~= key and over(ka, kb)
                    if before and now[a] and now[b] and over(now[a], now[b]) ~= before then
                        moved[#moved + 1] = (before == 1 and a .. " over " .. b) or (b .. " over " .. a)
                    end
                end
            end
            table.sort(moved)
            T.eq(#moved, 0, unit .. ", moving " .. key .. ": no longer draws " .. table.concat(moved, ", "))
            L.Reset(unit)
            stub.RunTimers()
        end
    end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
