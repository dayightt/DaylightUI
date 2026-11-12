-- The game's own UI code (tests/blizzard/, py tools/fetch_blizzard.py) runs inside
-- the fake game, so the routes the game takes on the addon's frames are tested
-- before a player meets them.
local stub = require("stub")
local Blizz = require("blizzard")

T.test("game code: the fetched files are here", function()
    T.truthy(Blizz.Have("ActionButton.lua"),
        "tests/blizzard/ActionButton.lua is missing: run `py tools/fetch_blizzard.py` once on this PC")
end)

T.test("game code: ActionButton.lua loads and defines the button mixins", function()
    stub.Reset()
    Blizz.Load("ActionButton.lua")
    for _, m in ipairs({ "BaseActionButtonMixin", "ActionBarActionButtonMixin",
                         "ActionBarActionButtonDerivedMixin", "ActionBarButtonMixin" }) do
        T.eq(type(_G[m]), "table", m)
    end
end)

T.test("game code: a name the fake game lacks reads as a harmless stand-in, and is noted", function()
    stub.Reset()
    Blizz.LoadString("GameCodeProbeResult = NotInTheFakeGame.Anything(1)", "probe")
    T.isnil(GameCodeProbeResult)
    T.truthy(Blizz.inert.NotInTheFakeGame, "noted in Blizz.inert")
    _G.GameCodeProbeResult = nil
end)

local ABW = require("abworld")

-- opts.before runs after the fake world is made, before the files load.
local function login(opts)
    opts = opts or {}
    return stub.Load({ actionbars = true, before = function()
        ABW.newWorld(opts)
        if opts.before then opts.before() end
    end })
end

-- Cooldowns, charges and a loss-of-control on the first slots, so the game's
-- cooldown code has work to do.
local SLOTS = {
    [1] = { texture = "t1", spellID = 1, cooldown = true },
    [2] = { texture = "t2", spellID = 2, charges = true },
    [3] = { texture = "t3", spellID = 3, cooldown = true, loc = true },
}

local function ourButtons()
    local list = {}
    for _, key in pairs(stub.actionbars.Bars.buttons) do
        for _, b in pairs(key) do list[#list + 1] = b end
    end
    return list
end

-- Calls every script the game's template put on each of the addon's buttons, and
-- collects every failure into one message naming the button and the handler. Not
-- OnClick (SecureActionButtonTemplate's own) or OnEvent (the addon's buttons are
-- off the game's events list, so the game never sends them events).
local SKIP = { OnClick = true, OnEvent = true }
local function sweep(label)
    local fails = {}
    for _, b in ipairs(ourButtons()) do
        for script in pairs(stub.BUTTON_SCRIPTS) do
            local fn = b:GetScript(script)
            if fn and not SKIP[script] then
                local ok, err
                if script == "OnAttributeChanged" then
                    ok, err = pcall(fn, b, "action", b:GetAttribute("action"))
                else
                    ok, err = pcall(fn, b)
                end
                if not ok then fails[#fails + 1] = string.format("%s %s: %s", tostring(b.__name), script, tostring(err)) end
            end
        end
    end
    if #fails > 0 then error(label .. ": the game's code failed on our buttons\n  " .. table.concat(fails, "\n  "), 2) end
end

T.test("game code: the sweep can see the error (a plain game-template button fails in combat)", function()
    login()
    stub.ActionSlots(SLOTS)
    stub.secretTimes = true
    T.errors(function()
        local b = CreateFrame("CheckButton", "PlainGameTemplateButton", UIParent, "ActionBarButtonTemplate")
        b:SetAttribute("action", 1)
    end, "the game's own Update on a tainted button must hit the SetCooldown check")
    stub.secretTimes = false
end)

T.test("game code: every handler on every one of our buttons, in combat, with secret times", function()
    login()
    stub.ActionSlots(SLOTS)
    stub.secretCooldownErrors = 0
    stub.combat = true
    T.noerror(function() sweep("in combat") end)
    stub.combat = false
    T.eq(stub.secretCooldownErrors, 0, "no SetCooldown refused")
    for _, e in ipairs(stub.errors) do T.falsy(string.find(e, "BLOCKED", 1, true), e) end
end)

T.test("game code: the same sweep out of combat", function()
    login()
    stub.ActionSlots(SLOTS)
    T.noerror(function() sweep("out of combat") end)
end)

T.test("game code: the fake game knows the client's real widget methods, and only those", function()
    stub.Reset()
    local f = CreateFrame("Frame")
    T.eq(type(f.SetPoint), "function", "a real method")
    T.eq(type(f.SetBackdropColour), "nil", "not a client method: nil, as in game")
    T.eq(type(f.Icon), "nil", "a sub-frame that isn't there reads nil, as in game")
end)
