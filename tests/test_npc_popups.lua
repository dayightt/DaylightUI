local stub = require("stub")

-- Pop-up keys (Npc/Popups.lua): Enter says yes on the game's yes/no boxes,
-- through a secure button bound only while one shows, out of combat.

local boxes = {}
local function world()
    for i = 1, 4 do
        local d = CreateFrame("Frame", "StaticPopup" .. i, UIParent)
        d.ButtonContainer = { Button1 = CreateFrame("Button", nil, d) }
        d:Hide()
        boxes[i] = d
    end
    _G.StaticPopupDialogs = {
        PARTY_INVITE = { button1 = "Accept", button2 = "Decline" },
        DEATH = { button1 = "Release Spirit" },
        DELETE_ITEM = { button1 = "Yes" },
        RENAME = { button1 = "Okay", hasEditBox = true },
        SAYS_ENTER = { button1 = "Okay", enterClicksFirstButton = true },
        BIND_ITEM = { button1 = "Okay" },
        CONFIRM_LOOT_ROLL = { button1 = "Okay" },
        CONFIRM_TALENT_WIPE = { button1 = "Accept" },
        COD_ACCEPT = { button1 = "Accept" },
        QUEST_ACCEPT = { button1 = "Accept", hasEditBox = true },
        CONFIRM_BINDER = { button1 = "Accept", button2 = "Cancel", timeout = 0, hideOnEscape = 1 },
    }
end

local function load()
    stub.Load({ before = world })
    stub.RunTimers()
    return stub.npc.Popups
end

local function show(i, which)
    boxes[i].which = which
    boxes[i]:Show()
    stub.RunTimers()
end

local function bound() return stub.overrides.ENTER end

T.test("pop-up keys: Enter says yes on an invite, and is the chat key again after", function()
    local P = load()
    T.isnil(bound(), "no box: Enter is the game's")
    show(1, "PARTY_INVITE")
    local o = bound()
    T.truthy(o, "bound while the invite shows")
    T.eq(o.click, P.NAME)
    T.eq(P.button:GetAttribute("type"), "click")
    T.eq(P.button:GetAttribute("clickbutton"), boxes[1].ButtonContainer.Button1, "presses the box's first button")
    boxes[1]:Hide()
    stub.RunTimers()
    T.isnil(bound(), "box gone: Enter opens chat again")
end)

T.test("pop-up keys: only the boxes on its yes list: never binding, Need, a paid reset, cash on delivery", function()
    load()
    for _, which in ipairs({ "DEATH", "DELETE_ITEM", "RENAME", "SAYS_ENTER", "UNKNOWN",
                             "BIND_ITEM", "CONFIRM_LOOT_ROLL", "CONFIRM_TALENT_WIPE", "COD_ACCEPT", "QUEST_ACCEPT" }) do
        show(1, which)
        T.isnil(bound(), which)
        boxes[1]:Hide()
        stub.RunTimers()
    end
    show(1, "DEATH")
    show(2, "PARTY_INVITE")
    T.eq(stub.npc.Popups.button:GetAttribute("clickbutton"), boxes[2].ButtonContainer.Button1, "the next box that wants it")
    boxes[1]:Hide(); boxes[2]:Hide()
end)

T.test("pop-up keys: a fight lets Enter go, and the switch turns it off", function()
    local P = load()
    show(1, "PARTY_INVITE")
    T.truthy(bound())
    stub.EnterCombat()
    T.isnil(bound(), "cleared as the fight starts")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(bound(), "back after it")
    DaylightUI:Set("NPC", "popupKeys", false)
    stub.RunTimers()
    T.isnil(bound(), "switched off")
    T.isnil(P.bound)
end)

local function asked() return stub.overrides.SPACE end

T.test("pop-up keys: the innkeeper's home question takes Space too, and the game's yes runs", function()
    local P = load()
    show(1, "CONFIRM_BINDER")
    T.truthy(bound(), "Enter says yes")
    local o = asked()
    T.truthy(o, "and so does Space: you just asked for it")
    T.eq(o.click, P.NAME)
    T.eq(P.button:GetAttribute("clickbutton"), boxes[1].ButtonContainer.Button1)
    boxes[1]:Hide()
    stub.RunTimers()
    T.isnil(asked(), "box gone: Space jumps again")
end)

T.test("pop-up keys: Space never answers a box that came to you: a jump must not take an invite", function()
    load()
    show(1, "PARTY_INVITE")
    T.truthy(bound())
    T.isnil(asked(), "Space stays the jump key")
    boxes[1].which = "CONFIRM_BINDER"
    _G.StaticPopup_Show("CONFIRM_BINDER")
    stub.npc.Popups.Update()
    T.truthy(asked(), "the same box filled again with the home question")
    boxes[1].which = "PARTY_INVITE"
    stub.npc.Popups.Update()
    T.isnil(asked(), "and back")
    boxes[1]:Hide()
end)

T.test("pop-up keys: Space follows the accept key: Enter only leaves Space alone", function()
    load()
    DaylightUI:Set("NPC", "acceptKey", "enter")
    show(1, "CONFIRM_BINDER")
    T.truthy(bound())
    T.isnil(asked())
    boxes[1]:Hide()
    stub.RunTimers()
    DaylightUI:Set("NPC", "acceptKey", "both")
    show(1, "CONFIRM_BINDER")
    T.truthy(asked())
    boxes[1]:Hide()
end)

T.test("pop-up keys: a fight lets Space go too", function()
    load()
    show(1, "CONFIRM_BINDER")
    stub.EnterCombat()
    T.isnil(asked())
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(asked())
    boxes[1]:Hide()
end)

T.test("pop-up keys: the talk window, still up behind the box, lets the key through", function()
    local P = load()
    show(1, "CONFIRM_BINDER")
    T.eq(P.Holds("SPACE"), true)
    T.eq(P.Holds("ENTER"), true)
    T.eq(P.Holds("ESCAPE"), false)
    boxes[1]:Hide()
    stub.RunTimers()
    T.eq(P.Holds("SPACE"), false, "no box: the window's Space again")
    T.eq(P.Holds("ENTER"), false)
end)
