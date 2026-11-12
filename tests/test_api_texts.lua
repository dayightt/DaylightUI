local stub = require("stub")

-- DaylightUI.API 1.3: plugins add their own unit frame texts (me.AddText),
-- picked like Daylight UI's own (Texts.lua: Texts.AddKind).

local function load(before)
    local DUI, ns = stub.Load({ module = true, login = false })
    if before then before(DUI) end
    stub.FireEvent("PLAYER_LOGIN")
    stub.RunTimers()
    return DUI, ns
end

local function useText(DUI, kind)
    DUI:Set("UnitFrames", "player.texts.t1.show", true)
    DUI:Set("UnitFrames", "player.texts.t1.kind", kind)
    stub.RunTimers()
end

local function slot(ns) return ns.frames.player.extraTexts and ns.frames.player.extraTexts[1] end

T.test("api texts: a plugin's text is in the pickers after Daylight UI's", function()
    local DUI, ns = load(function(DUI)
        DUI.API.For("Neon").AddText("shards", { label = "Soul shards", on = { "power" }, text = function() return "3" end })
    end)
    local T2 = ns.Texts
    T.eq(T2.LABELS["Neon:shards"], "Soul shards")
    T.eq(T2.KINDS[#T2.KINDS], "Neon:shards", "after Daylight UI's own")
    T.eq(T2.MORE_LABELS["Neon:shards"], "Soul shards", "as a second or third part too")
end)

T.test("api texts: set on the player frame, it writes its text on its updates", function()
    local n = 0
    local DUI, ns = load(function(DUI)
        DUI.API.For("Neon").AddText("count", { label = "Count", on = { "identity" },
            text = function(unit) n = n + 1; return "n" .. n, 1, 0, 0 end })
    end)
    useText(DUI, "Neon:count")
    ns.UF.UpdateIdentity(ns.frames.player)
    local fs = slot(ns)
    T.truthy(fs and fs:IsShown(), "the slot shows")
    T.truthy(string.find(stub.Text(fs) or "", "^n%d"), tostring(stub.Text(fs)))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api texts: redrawn on its game event, for that unit only", function()
    local calls = {}
    local DUI, ns = load(function(DUI)
        DUI.API.For("Neon").AddText("aura", { label = "Aura", events = { "UNIT_AURA" },
            text = function(unit) calls[#calls + 1] = unit; return "x" end })
    end)
    useText(DUI, "Neon:aura")
    local before = #calls
    stub.FireEvent("UNIT_AURA", "player")
    T.eq(#calls, before + 1)
    T.eq(calls[#calls], "player")
    stub.FireEvent("UNIT_AURA", "party4")
    T.eq(#calls, before + 1, "nobody shows party4")
end)

T.test("api texts: a secret answer is handed on whole, a broken one names the plugin", function()
    local secret = stub.Secret("12")
    local DUI, ns = load(function(DUI)
        DUI.API.For("Neon").AddText("sec", { label = "Secret", on = { "identity" }, text = function() return secret end })
        DUI.API.For("Broken").AddText("bad", { label = "Bad", on = { "identity" }, text = function() error("text bug") end })
    end)
    useText(DUI, "Neon:sec")
    ns.UF.UpdateIdentity(ns.frames.player)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    useText(DUI, "Broken:bad")
    ns.UF.UpdateIdentity(ns.frames.player)
    T.truthy(string.find(tostring(stub.errors[1]), "Broken", 1, true), tostring(stub.errors[1]))
end)

T.test("api texts: the preview shows its sample", function()
    local DUI, ns = load(function(DUI)
        DUI.API.For("Neon").AddText("s", { label = "S", on = { "identity" }, sample = "SAMPLE", text = function() return "real" end })
    end)
    useText(DUI, "Neon:s")
    local f = ns.frames.player
    ns.Texts.ShowSample(f, { name = "X", level = 60 })
    T.eq(stub.Text(slot(ns)), "SAMPLE")
end)

T.test("api texts: a saved text of a plugin that's gone shows nothing, no error", function()
    local DUI, ns = load()
    useText(DUI, "Gone:x")
    ns.UF.UpdateIdentity(ns.frames.player)
    local fs = slot(ns)
    T.truthy(not fs or not fs:IsShown() or (stub.Text(fs) or "") == "")
    DUI.OptionsPanel.Show("UnitFrames.player")
    stub.RunTimers()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("api texts: bad asks are refused", function()
    local DUI = load()
    local me = DUI.API.For("Neon")
    T.eq(me.AddText(nil, { label = "x", text = function() end }), false)
    T.eq(me.AddText("k", { text = function() end }), false, "no label")
    T.eq(me.AddText("k", { label = "x" }), false, "no text function")
end)

T.test("api texts: a game event redraws without building lists (raids send these fast)", function()
    local DUI, ns = load(function(DUI)
        DUI.API.For("Neon").AddText("aura", { label = "Aura", events = { "UNIT_AURA" }, text = function() return "x" end })
    end)
    useText(DUI, "Neon:aura")
    local walks = 0
    local frames = DUI.API.Frames
    DUI.API.Frames = function(...) walks = walks + 1; return frames(...) end
    for _ = 1, 50 do stub.FireEvent("UNIT_AURA", "player") end
    DUI.API.Frames = frames
    T.eq(walks, 0)
end)
