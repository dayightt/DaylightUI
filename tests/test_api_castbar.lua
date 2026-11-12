local stub = require("stub")

-- DaylightUI.API 1.3: cast bars are frames plugins paint ("castbar" kind), with named
-- pieces, Paint after every one of Daylight UI's paints of the bar, and claimed
-- pieces left to the plugin (CastBar.lua: CB.Painted).

local function setup()
    local _, ns = stub.Load({ module = true, login = false })
    local h = ns.CastBar.Create("player")
    ns.CastBar.Layout(h, ns.DEFAULTS.playerCastbar)
    ns.CastBar.cfg.fill = "daylight"
    return h, ns, DaylightUI.API
end

local function cast(spellID, ni)
    stub.units.player = { cast = { name = "Frostbolt", texture = 135846, spellID = spellID or 116,
        notInterruptible = ni == nil and false or ni, duration = stub.Duration(1.5) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "player")
end

T.test("api castbar: cast bars are frames with named pieces", function()
    local h, _, API = setup()
    local seen
    for f, unit in API.Frames("castbar") do if f == h then seen = unit end end
    T.eq(seen, "player")
    local p = API.Parts(h)
    T.truthy(p, "parts")
    T.eq(p.fill, h.bar:GetStatusBarTexture())
    T.eq(p.bar, h.bar)
    T.eq(p.back, DaylightUI.Style.BarBack(h.bar))
    T.eq(p.name, h.text)
    T.eq(p.time, h.time)
    T.eq(p.icon, h.icon)
end)

T.test("api castbar: a painter runs after every cast, channel and interrupt", function()
    local h, _, API = setup()
    local calls = {}
    API.For("Neon").Paint("castbar", function(f, parts, info) calls[#calls + 1] = info or false end)
    local start = #calls
    cast(116)
    T.eq(#calls, start + 1)
    local info = calls[#calls]
    T.eq(info.unit, "player"); T.eq(info.spellID, 116); T.eq(info.channel, false)
    stub.units.player = { channel = { name = "Mind Flay", notInterruptible = false, duration = stub.Duration(2) } }
    stub.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    T.eq(calls[#calls].channel, true)
    local before = #calls
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    T.eq(#calls, before + 1, "the interrupt's red is painted over too")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api castbar: a claimed fill keeps the plugin's texture, cast after cast", function()
    local h, _, API = setup()
    API.For("Neon").Paint("castbar", function(f, parts) parts.fill:SetTexture("Interface\\AddOns\\Neon\\rainbow") end,
        { owns = { "fill" } })
    for i = 1, 3 do
        cast(100 + i)
        local fill = h.bar:GetStatusBarTexture()
        T.eq(fill.__texture, "Interface\\AddOns\\Neon\\rainbow", "cast " .. i)
        T.eq(fill.__vertex[1], 1); T.eq(fill.__vertex[2], 1); T.eq(fill.__vertex[3], 1)
    end
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    T.eq(h.bar:GetStatusBarTexture().__vertex[1], 1, "nor the interrupt's red")
end)

T.test("api castbar: a broken painter is named once a message and the bar still works", function()
    local h, _, API = setup()
    API.For("Broken").Paint("castbar", function() error("neon bug") end)
    for i = 1, 3 do cast(i) end
    T.truthy(h:IsShown(), "the bar still shows")
    T.eq(h.text.__text, "Frostbolt")
    T.truthy(#stub.errors >= 1)
    T.truthy(string.find(tostring(stub.errors[1]), "Broken", 1, true))
    local same = 0
    for _, e in ipairs(stub.errors) do if string.find(tostring(e), "neon bug", 1, true) then same = same + 1 end end
    T.eq(same, 1, "the same error reported once, not each cast")
end)

T.test("api castbar: giving the fill back paints Daylight UI's look at once", function()
    local h, ns, API = setup()
    cast(116)
    local handle = API.For("Neon").Paint("castbar", function(f, parts) parts.fill:SetVertexColor(1, 0, 1, 1) end,
        { owns = { "fill" } })
    T.eq(h.bar:GetStatusBarTexture().__vertex[2], 0, "the plugin's color")
    ns.CastBar.cfg.fill = "plain"
    API.Off(handle)
    local c = ns.CastBar.cfg.cast
    local v = h.bar:GetStatusBarTexture().__vertex
    T.eq(v[1], c[1]); T.eq(v[2], c[2]); T.eq(v[3], c[3])
end)

T.test("api castbar: a target's cast with a secret flag in a restricted fight", function()
    local _, ns = stub.Load({ module = true, login = false })
    local h = ns.CastBar.Create("target")
    ns.CastBar.Layout(h, ns.DEFAULTS.playerCastbar)
    local got
    DaylightUI.API.For("Neon").Paint("castbar", function(f, parts, info) if info then got = info end end)
    stub.EnterCombat()
    stub.SetRestriction("PvPMatch", true)
    local flag = stub.Secret(true)
    stub.units.target = { cast = { name = "Fear", notInterruptible = flag, duration = stub.Duration(1.5) } }
    stub.FireEvent("UNIT_SPELLCAST_START", "target")
    T.truthy(got, "painted")
    T.eq(got.notInterruptible, flag, "the flag handed on as it came")
    stub.SetRestriction("PvPMatch", false)
    stub.LeaveCombat()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api castbar: letting the fill go puts the bar's own texture back", function()
    local h, ns, API = setup()
    ns.CastBar.cfg.fill = "plain"
    cast(116)
    local handle = API.For("Neon").Paint("castbar", function(f, parts) parts.fill:SetTexture("Interface\\AddOns\\Neon\\rainbow") end,
        { owns = { "fill" } })
    T.eq(h.bar:GetStatusBarTexture().__texture, "Interface\\AddOns\\Neon\\rainbow")
    API.Off(handle)
    local now = h.bar:GetStatusBarTexture().__texture
    T.truthy(type(now) == "string" and not string.find(now, "Neon", 1, true), "Daylight UI's texture again: " .. tostring(now))
end)

T.test("api castbar: a claimed fill still warns of a cast you can't interrupt, and says when it's an interrupt", function()
    local h, ns, API = setup()
    local last
    API.For("Neon").Paint("castbar", function(f, parts, info) last = info end, { owns = { "fill" } })
    cast(116, true)
    T.truthy(h.lockTex and h.lockTex:IsShown(), "the warning lies over the plugin's fill")
    stub.units.player = {}
    stub.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    T.eq(last.interrupted, true, "the plugin is told")
end)
