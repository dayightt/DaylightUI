local stub = require("stub")

-- Pings. Blizzard_PingUI loads on Forever since it runs the mainline UI. With the
-- ping key held, the client asks the frame under the cursor that has the
-- "ping-receiver" attribute for its GetTargetInfo. The game's unit frames get
-- both from PingableUnitFrameTemplate, and these frames inherit it too.

local UNITS = { "player", "target", "targettarget", "pet", "focus" }

local function guids()
    _G.UnitGUID = function(u)
        local x = stub.units[u]
        if x then return "Player-1-" .. tostring(x.name) end
    end
end

T.test("every unit frame of ours is a ping receiver that pings its own unit", function()
    local _, ns = stub.Load({ module = true })
    guids()
    stub.units.target = { name = "Hogger", health = 5, maxHealth = 10 }
    stub.units.focus = { name = "Jaina", isPlayer = true, health = 5, maxHealth = 10 }
    for _, unit in ipairs(UNITS) do
        local f = ns.frames[unit]
        T.truthy(f, unit)
        T.eq(f:GetAttribute("ping-receiver"), true, unit .. " takes pings")
        T.eq(f:GetIsPingable(), true, unit)
        T.eq(f:GetAllowRadialWheel(), true, unit .. ": the ping wheel too")
    end
    T.eq(ns.frames.target:GetTargetInfo().guid, "Player-1-Hogger")
    T.eq(ns.frames.focus:GetTargetInfo().guid, "Player-1-Jaina")
end)

-- The game's mixin reads `self.unit or self:GetAttribute("unit")`. These frames
-- keep their unit in `unitToken`, so the ping follows the secure attribute.
-- oUF renamed its `.unit` for the same reason.
T.test("our frames have no .unit of their own for the ping code to read", function()
    local _, ns = stub.Load({ module = true })
    for _, unit in ipairs(UNITS) do
        T.isnil(rawget(ns.frames[unit], "unit"), unit)
        T.eq(ns.frames[unit].unitToken, unit)
    end
end)

-- Party and raid buttons are made by the secure headers (in combat too),
-- from the header's "template" attribute, so the template carries it.
T.test("party and raid buttons the headers make are ping receivers that follow the roster", function()
    local _, ns = stub.Load({ module = true })
    guids()
    local headers = { ns.Party.header, ns.Raid.header }
    for _, gh in ipairs(ns.Raid.group.headers) do headers[#headers + 1] = gh end
    T.truthy(#headers > 2, "the per-group headers too")
    for _, h in ipairs(headers) do
        T.truthy(string.find(h:GetAttribute("template"), "PingableUnitFrameTemplate", 1, true), h:GetName())
        T.truthy(string.find(h:GetAttribute("template"), "SecureUnitButtonTemplate", 1, true), h:GetName())
    end
    stub.units.party1 = { name = "Lift", isPlayer = true, class = "PRIEST", health = 5, maxHealth = 10 }
    stub.units.party2 = { name = "Brann", isPlayer = true, class = "WARRIOR", health = 5, maxHealth = 10 }
    local h = ns.Party.header
    local b = CreateFrame("Button", "DaylightUIPartyHeaderUnitButton1", h, h:GetAttribute("template"))
    b:SetAttribute("unit", "party1")
    h.initialConfigFunction(h, b:GetName())
    T.eq(b:GetAttribute("ping-receiver"), true)
    T.eq(b:GetTargetInfo().guid, "Player-1-Lift")
    -- The roster changes mid-fight: the header hands the button another unit.
    stub.EnterCombat()
    stub.inSecure = (stub.inSecure or 0) + 1   -- the header's own secure code
    b:SetAttribute("unit", "party2")
    stub.inSecure = stub.inSecure - 1
    T.eq(b:GetTargetInfo().guid, "Player-1-Brann", "the ping follows the new member")
    stub.LeaveCombat()
end)
