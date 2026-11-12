-- The scrolling combat text (CombatText/): the game's messages, drawn by Daylight UI.
-- GetCurrentEventInfo is SecretReturns, so everything it hands over is secret.

local stub = require("stub")

local function load(cvars, opts)
    cvars = cvars or { enableFloatingCombatText = "1" }
    _G.GetCVar = function(k) return cvars[k] end
    -- The client fires CVAR_UPDATE on every change (the game's CVarCallbackRegistry listens to it).
    _G.SetCVar = function(k, v)
        cvars[k] = tostring(v)
        stub.FireEvent("CVAR_UPDATE", k, tostring(v))
    end
    _G.C_CVar = _G.C_CVar or {}
    _G.C_CVar.GetCVarDefault = function() return "1" end
    stub.combatTextUnit, stub.CombatTextInfo = nil, nil
    stub.FontRule = true
    _G.COMBAT_TEXT_ABSORB, _G.COMBAT_TEXT_BLOCK, _G.COMBAT_TEXT_RESIST = "Absorb", "Block", "Resist"
    _G.COMBAT_TEXT_DODGE, _G.ABSORB_TRAILER, _G.BLOCK_TRAILER, _G.RESIST_TRAILER = "Dodge", "(%d absorbed)", "(%d blocked)", "(%d resisted)"
    _G.AURA_END, _G.COMBAT_TEXT_HONOR_GAINED = "<%s> fades", "+%s Honor"
    local DUI = stub.Load(opts)
    local function send(mt, data, a3, a4)
        -- The client sends nothing while its own switch is off (seen in game).
        if cvars.enableFloatingCombatText ~= "1" then return end
        stub.CombatTextInfo = { data, a3, a4 }
        stub.FireEvent("COMBAT_TEXT_UPDATE", mt)
    end
    return DUI, send, cvars
end

local function done()
    _G.GetCVar, _G.SetCVar, _G.CombatText, stub.FontRule, stub.CombatTextInfo = nil, nil, nil, nil, nil
    if _G.C_CVar then _G.C_CVar.GetCVarDefault = nil end
end

local function live(DUI, id) return DUI.CombatText.Stage().streams[id].live end

-- Runs the stage's frames.
local function run(DUI, seconds)
    local root = DUI.CombatText.Stage().root
    for _ = 1, math.floor(seconds * 30) do
        stub.Advance(1 / 30)
        local fn = root:GetScript("OnUpdate")
        if fn then fn(root, 1 / 30) end
    end
end

T.test("combat text: takes over from the game's own text and asks for the player's messages", function()
    load()
    T.eq(stub.combatTextUnit, "player", "the feed is told who to report")
    _G.CombatText = CreateFrame("Frame")
    _G.CombatText:Show()
    stub.FireEvent("ADDON_LOADED", "Blizzard_CombatText")
    T.falsy(_G.CombatText:IsShown(), "the game's frame stays hidden")
    done()
end)

T.test("combat text: a secret hit draws, with nothing compared or added", function()
    local DUI, send = load()
    send("DAMAGE", 1234)
    send("SPELL_DAMAGE_CRIT", 900)
    send("HEAL", "Friend", 500)
    send("HEAL_CRIT", "Friend", 700)
    send("PERIODIC_HEAL", "Friend", 80)
    send("ABSORB", 10, 40)
    send("BLOCK")
    send("RESIST", 10, 5)
    send("ABSORB_ADDED", "Friend", 90)
    send("DODGE")
    T.eq(#live(DUI, "hits"), 6)
    T.eq(#live(DUI, "heals"), 4)
    done()
end)

T.test("combat text: every message the game names goes through, secret, without an error", function()
    local DUI, send = load()
    for _, id in ipairs(DUI.CombatText.KIND_ORDER) do DUI.CombatText.Set("kinds." .. id .. ".on", true) end
    for mt in pairs(DUI.CombatText.MESSAGES) do
        if mt ~= "ENTERING_COMBAT" and mt ~= "LEAVING_COMBAT" then send(mt, 12, 3, 1) end
    end
    send("SPELL_AURA_START", "Renew")
    send("SOMETHING_NEW")
    T.truthy(#live(DUI, "hits") > 0)
    done()
end)

T.test("combat text: a message switched off shows nothing; a partial resist still reads as damage", function()
    local DUI, send = load()
    send("SPELL_AURA_START", "Renew")
    T.eq(#live(DUI, "notes"), 0, "buffs are off by default: calm")
    DUI.CombatText.Set("kinds.reduce.on", false)
    send("BLOCK")
    T.eq(#live(DUI, "hits"), 0, "a full block: nothing")
    send("BLOCK", 30, 12)
    T.eq(#live(DUI, "hits"), 1, "a partial block: the damage")
    done()
end)

T.test("combat text: a message goes to the stream it was given", function()
    local DUI, send = load()
    DUI.CombatText.Set("kinds.heal.stream", "notes")
    send("HEAL", "Friend", 500)
    T.eq(#live(DUI, "notes"), 1)
    T.eq(#live(DUI, "heals"), 0)
    done()
end)

T.test("combat text: a spell hit takes its school's color, whichever event comes first", function()
    local DUI, send = load()
    local frost = DUI.CombatText.SCHOOLS[16]
    send("SPELL_DAMAGE", 100)
    stub.FireEvent("UNIT_COMBAT", "player", "WOUND", "", stub.Secret(100), 16)
    local line = live(DUI, "hits")[1]
    T.eq(line.fs.__textColor and line.fs.__textColor[1] or frost[1], frost[1])
    stub.Advance(0.2)
    stub.FireEvent("UNIT_COMBAT", "player", "WOUND", "", stub.Secret(100), 4)
    send("SPELL_DAMAGE", 100)
    T.eq(#live(DUI, "hits"), 2)
    done()
end)

T.test("combat text: lines never overlap, a fast one catching a slow crit included", function()
    local DUI, send = load()
    send("SPELL_DAMAGE_CRIT", 900)
    run(DUI, 0.16)
    send("DAMAGE", 100)
    run(DUI, 0.16)
    send("DAMAGE", 100)
    run(DUI, 0.5)
    local lines = live(DUI, "hits")
    T.eq(#lines, 3)
    local CT = DUI.CombatText
    local function y(l)
        local _, _, _, _, py = l.frame:GetPoint(1)
        return py
    end
    for i = 1, #lines - 1 do
        local a, b = lines[i], lines[i + 1]
        T.truthy(y(a) - y(b) >= (a.room + b.room) / 2 + CT.GAP - 3, "line " .. i .. " stays clear of the next")
    end
    done()
end)

T.test("combat text: too many at once, the oldest leaves early; nothing runs when it's over", function()
    local DUI, send = load()
    DUI.CombatText.Set("streams.hits.lines", 3)
    for _ = 1, 20 do send("DAMAGE", 5) end
    T.truthy(#live(DUI, "hits") <= 6, "a flood never piles up")
    run(DUI, 3)
    T.eq(#live(DUI, "hits"), 0)
    T.isnil(DUI.CombatText.Stage().root:GetScript("OnUpdate"), "the driver stops: nothing per frame while idle")
    done()
end)

T.test("combat text: a line's frames are reused", function()
    local DUI, send = load()
    send("DAMAGE", 5)
    local first = live(DUI, "hits")[1]
    run(DUI, 3)
    send("DAMAGE", 5)
    T.truthy(live(DUI, "hits")[1] == first)
    done()
end)

T.test("combat text: the game's switch, off at first, is turned on: its feed needs it", function()
    -- The game's switch starts off ("default 0"), and its feed is silent while it's off.
    local DUI, send, cvars = load({ enableFloatingCombatText = "0" })
    T.eq(cvars.enableFloatingCombatText, "1")
    send("DAMAGE", 5)
    T.eq(#live(DUI, "hits"), 1)
    DUI.CombatText.Set("enabled", false)
    T.eq(#live(DUI, "hits"), 0)
    send("DAMAGE", 5)
    T.eq(#live(DUI, "hits"), 0)
    DUI.CombatText.Set("enabled", true)
    send("DAMAGE", 5)
    T.eq(#live(DUI, "hits"), 1)
    done()
end)

T.test("combat text: the game's switch turned off later is turned back on, so the text never goes silent", function()
    -- Players saw no combat text at all: the game's own options, another addon or
    -- a settings sync turned the switch off after login.
    local DUI, send, cvars = load()
    cvars.enableFloatingCombatText = "0"
    stub.FireEvent("CVAR_UPDATE", "enableFloatingCombatText", "0")
    T.eq(cvars.enableFloatingCombatText, "1", "turned back on")
    send("DAMAGE", 5)
    T.eq(#live(DUI, "hits"), 1, "the hit shows")
    DUI.CombatText.Set("enabled", false)
    cvars.enableFloatingCombatText = "0"
    stub.FireEvent("CVAR_UPDATE", "enableFloatingCombatText", "0")
    T.eq(cvars.enableFloatingCombatText, "0", "left alone while Daylight UI's text is off")
    done()
end)

T.test("combat text: something that keeps turning the game's switch off doesn't start a loop", function()
    local DUI, _, cvars = load()
    local writes = 0
    local set = _G.SetCVar
    _G.SetCVar = function(k, v) writes = writes + 1; set(k, v) end
    for _ = 1, 20 do
        cvars.enableFloatingCombatText = "0"
        stub.FireEvent("CVAR_UPDATE", "enableFloatingCombatText", "0")
    end
    T.eq(writes, DUI.CombatText.SWITCH_TRIES, "gives up after a few")
    done()
end)

T.test("combat text: a refused switch costs nothing", function()
    local DUI = load({ enableFloatingCombatText = "0" })
    _G.SetCVar = function() error("refused") end
    stub.FireEvent("CVAR_UPDATE", "enableFloatingCombatText", "0")
    DUI.CombatText.Set("enabled", false)
    DUI.CombatText.Set("enabled", true)
    T.truthy(DUI.CombatText.Live())
    done()
end)

T.test("combat text: motion off, lines show at once and stay put", function()
    local DUI, send = load()
    DUI:Set("general", "motion", false)
    send("DAMAGE_CRIT", 5)
    local line = live(DUI, "hits")[1]
    T.eq(line.frame:GetAlpha(), 1, "no fade in")
    T.eq(line.motion, "stack")
    done()
end)

T.test("combat text: a preset is its values, shown by the one they match", function()
    local DUI = load()
    local CT = DUI.CombatText
    T.eq(CT.Preset(), "daylight", "the default is a preset")
    for _, name in ipairs(CT.PRESET_ORDER) do
        CT.SetPreset(name)
        T.eq(CT.Preset(), name)
    end
    CT.Set("streams.hits.size", 41)
    T.eq(CT.Preset(), "custom")
    done()
end)

T.test("combat text: every stream has a mover and the page is there", function()
    local DUI = load()
    local CT = DUI.CombatText
    for _, id in ipairs(CT.STREAM_ORDER) do T.truthy(CT.Stage().streams[id].anchor) end
    local page = DUI.Options.GetPage("combattext")
    T.truthy(page and page.sample, "a live preview")
    for _, g in ipairs(page.groups) do
        T.truthy(g.reveal == nil, "no picker: every row of " .. g.label .. " is on the page")
        for _, item in ipairs(g.items) do
            if item.disabled then T.falsy(item.disabled(function() end), item.label .. " can be clicked") end
        end
    end
    local get = function(k) return DUI:Get("general", k) end
    local n = 0
    for _, g in ipairs(page.groups) do
        for _, item in ipairs(g.items) do
            if item.key then
                n = n + 1
                T.truthy(get(item.key) ~= nil, "a default for " .. item.key)
            end
        end
    end
    T.truthy(n >= 45, "a real set of options")
    done()
end)

T.test("combat text: the preview runs the real path and stops when hidden", function()
    local DUI = load()
    local CT = DUI.CombatText
    local parent = CreateFrame("Frame")
    local s = CT.Sample(parent)
    T.truthy(s.Refresh(600, 300) > 0)
    for n = 1, #CT.DEMO do CT.DemoStep(s.stage, n) end
    T.truthy(#s.stage.streams.hits.live > 0)
    s.frame:Hide()
    s.frame:GetScript("OnHide")(s.frame)
    T.eq(#s.stage.streams.hits.live, 0)
    done()
end)

T.test("combat text: no low health warning once you're dead", function()
    local dead = false
    _G.UnitIsDeadOrGhost = function() return dead end
    local hadCurves = _G.C_CurveUtil
    _G.C_CurveUtil = { CreateCurve = function() return { AddPoint = function() end } end }
    local DUI = load()
    local warn = DUI.CombatText.Warn()
    stub.FireEvent("UNIT_HEALTH", "player")
    T.truthy(warn.health:IsShown(), "alive: it can show")
    dead = true
    stub.FireEvent("PLAYER_DEAD")
    T.falsy(warn.health:IsShown(), "dead: gone")
    T.falsy(warn.mana:IsShown())
    dead = false
    stub.FireEvent("PLAYER_ALIVE")
    T.truthy(warn.health:IsShown(), "back")
    _G.UnitIsDeadOrGhost, _G.C_CurveUtil = nil, hadCurves
    done()
end)

T.test("combat text: a setting's change repaints nothing else, and the preview's lines take a new size at once", function()
    local DUI = load()
    local CT = DUI.CombatText
    local painted = 0
    DUI.On("RepaintCore", function() painted = painted + 1 end)
    CT.Set("streams.hits.size", 30)
    stub.RunTimers()
    T.eq(painted, 0, "dragging a slider here never repaints the whole UI")

    local s = CT.Sample(CreateFrame("Frame"))
    s.Refresh(600, 300)
    local line = CT.DemoStep(s.stage, 1)
    local before = line.fs:GetFont() and select(2, line.fs:GetFont())
    CT.Set("streams.hits.size", 40)
    s.Refresh(600, 300)
    T.truthy(select(2, line.fs:GetFont()) > before, "the line on screen grew")
    done()
end)

T.test("combat text: a slider dragged on this page writes quietly and saves on release", function()
    local DUI = load()
    local Options = DUI.Options
    DUI.OptionsPanel.Show("combattext")
    local page = Options.GetPage("combattext")
    local item
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do
            if it.key == "sct.streams.hits.size" then item = it end
        end
    end
    local sets = 0
    DUI.On("SettingChanged", function() sets = sets + 1 end)
    T.eq(Options.Preview(page, item, 33), true, "the preview path")
    T.eq(sets, 0, "no setting change per step")
    T.eq(DUI:Get("general", "sct.streams.hits.size"), 33, "the quiet write")
    done()
end)

T.test("combat text: a page switch shows its new state the moment it's clicked", function()
    local DUI = load()
    DUI.OptionsPanel.Show("combattext")
    local found
    local function walk(f)
        if type(f) ~= "table" or found then return end
        if f.item and f.item.key == "sct.streams.hits.on" then found = f; return end
        for _, c in ipairs({ f:GetChildren() }) do walk(c) end
    end
    walk(UIParent)
    T.truthy(found, "the left stream's row")
    local switch = found.control
    T.eq(switch.on, true, "starts on")
    switch:Click()
    T.eq(DUI:Get("general", "sct.streams.hits.on"), false, "saved off")
    T.eq(switch.on, false, "drawn off, no style repaint needed")
    switch:Click()
    T.eq(DUI:Get("general", "sct.streams.hits.on"), true, "a second click turns it back on")
    T.eq(switch.on, true, "drawn on")
    done()
end)
