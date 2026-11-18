local stub = require("stub")

-- These tests establish Lua ownership, refusal, and comparison invariants.
-- The stub cannot establish whether WoW's renderer actually paints pixels.
local function setup()
    stub.Load()
    stub.RunTimers()
    local DUI = DaylightUI
    local world = CreateFrame("Frame", nil, UIParent)
    world:SetScale(0.7)
    local plate = CreateFrame("Frame", nil, world)
    plate:SetAlpha(0.2)
    plate:SetScale(0.5)
    plate:SetFrameLevel(4)
    plate:SetFrameStrata("WORLD")
    local lookup = { nameplate1 = plate }
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit) return lookup[unit] end }
    _G.C_NamePlateManager = { IsNamePlateUnitBehindCamera = function() return false end }
    local messages, timeouts = {}, {}
    DUI.Print = function(text) messages[#messages + 1] = text end
    C_Timer.After = function(seconds, fn) timeouts[#timeouts + 1] = { seconds = seconds, fn = fn } end
    local mutations = 0
    for _, method in ipairs({ "SetParent", "ClearAllPoints", "SetPoint", "SetSize", "SetScale", "SetAlpha",
        "SetFrameLevel", "SetFrameStrata", "Show", "Hide", "SetScript", "HookScript", "EnableMouse",
        "SetIgnoreParentAlpha", "SetIgnoreParentScale" }) do
        plate[method] = function() mutations = mutations + 1; error("native plate mutation") end
    end
    local s = { DUI = DUI, P = DUI.PlateRenderProbe, plate = plate, world = world, lookup = lookup,
        messages = messages, timeouts = timeouts, mutations = function() return mutations end }
    function s.command(rest) DUI.RunCommand("platerender " .. (rest or "")) end
    function s.text() return table.concat(messages, "\n") end
    function s.probe() return _G.DaylightUIPlateRenderProbe end
    function s.lastTimeout() return timeouts[#timeouts].fn end
    return s
end

local function off(s)
    local f = s.probe()
    T.truthy(f)
    T.eq(f:GetParent(), UIParent, "only our probe returns to UIParent")
    T.falsy(f:IsShown())
    T.eq(f:GetNumPoints(), 0)
    T.eq(s.mutations(), 0)
    T.falsy(s.P.Active(), "capture may resume only after cleanup")
end

T.test("platerender: idle registration creates no probe, ticker, or native changes", function()
    local s = setup()
    -- Measure the probe alone; the separate capture observer intentionally
    -- starts a ticker when this test announces an active nameplate.
    s.DUI.PlateCapture.Watch("off")
    local count = #stub.tickers
    stub.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    stub.RunTickers()
    T.isnil(s.probe())
    T.falsy(s.P.Active())
    T.eq(#stub.tickers, count)
    T.eq(#s.timeouts, 0)
    T.eq(s.mutations(), 0)
    T.falsy(DaylightUI.LISTED_COMMANDS.platerender, "not in normal help")
    s.DUI.RunCommand("all")
    T.falsy(s.text():find("platerender", 1, true), "not in expanded help either")
end)

T.test("platerender: same plain square, anchor, level, alpha, scale and size across all phases", function()
    local s = setup()
    local create, createdParent = CreateFrame
    _G.CreateFrame = function(kind, name, parent, ...)
        if name == "DaylightUIPlateRenderProbe" then createdParent = parent end
        return create(kind, name, parent, ...)
    end
    s.command()
    _G.CreateFrame = create
    T.truthy(s.P.Active(), "capture can detect an active probe")
    local f = s.probe()
    T.eq(createdParent, UIParent, "created away from native ancestry")
    for phase = 1, 3 do
        if phase > 1 then s.command() end
        T.eq(s.probe(), f)
        T.eq(f:GetParent(), phase == 1 and s.plate or UIParent)
        T.eq(f:GetFrameStrata(), phase == 3 and "TOOLTIP" or "MEDIUM")
        T.eq(f:GetFrameLevel(), 100)
        T.eq(f:GetWidth(), 18); T.eq(f:GetHeight(), 18)
        T.eq(f:GetEffectiveAlpha(), 1)
        T.eq(f:GetEffectiveScale(), UIParent:GetEffectiveScale())
        T.truthy(f:IsIgnoringParentAlpha()); T.truthy(f:IsIgnoringParentScale())
        local point, relative, relativePoint, x, y = f:GetPoint()
        T.eq(point, "CENTER"); T.eq(relative, s.plate); T.eq(relativePoint, "CENTER")
        T.eq(x, 0); T.eq(y, 0)
        T.truthy(f:IsShown())
        T.eq(select("#", f:GetRegions()), 1, "one plain texture")
        T.deq(({ f:GetRegions() })[1].__color, { 1, 0, 1, 1 })
        T.isnil(f.__scripts.OnUpdate, "only an active ticker checks association")
        T.isnil(f.__shell, "no shell or animation")
    end
    T.truthy(s.text():find("Record whether", 1, true))
    T.truthy(s.text():find("does not detect rendered pixels", 1, true))
    T.falsy(s.text():find("on screen", 1, true))
    T.truthy(s.text():find("effectiveAlpha=1.000", 1, true))
    T.truthy(s.text():find("refusals=0 errors=0", 1, true))
    s.command("off")
    off(s)
end)

T.test("platerender: no plate, combat and noncombat restriction refuse before frame creation", function()
    local s = setup()
    s.lookup.nameplate1 = nil
    s.command()
    T.isnil(s.probe())
    T.truthy(s.text():find("no active native plate", 1, true))
    s.lookup.nameplate1 = s.plate
    stub.EnterCombat()
    s.command()
    T.isnil(s.probe())
    stub.LeaveCombat()
    stub.SetRestriction("Encounter", true)
    s.command()
    T.isnil(s.probe())
    stub.SetRestriction("Encounter", false)
    s.command()
    T.truthy(s.probe())
    s.command("off")
end)

T.test("platerender: combat invalidates without mutations and cleans when restrictions end", function()
    local s = setup()
    s.command()
    local f = s.probe()
    local hide, parent, touched = f.Hide, f.SetParent, 0
    f.Hide = function(self) T.falsy(DaylightUI.Restricted()); touched = touched + 1; hide(self) end
    f.SetParent = function(self, p) T.falsy(DaylightUI.Restricted()); touched = touched + 1; parent(self, p) end
    stub.EnterCombat()
    T.eq(touched, 0, "no attempted protected changes in combat")
    T.truthy(s.text():find("Cleanup pending", 1, true))
    s.command("off")
    T.eq(touched, 0)
    stub.LeaveCombat()
    off(s)
    T.eq(touched, 2)
    s.command("status")
    T.truthy(s.text():find("off: parent=UIParent", 1, true))
end)

T.test("platerender: noncombat restriction also invalidates and defers cleanup", function()
    local s = setup()
    s.command()
    stub.SetRestriction("Encounter", true)
    T.eq(s.probe():GetParent(), s.plate)
    T.truthy(s.text():find("Comparison invalidated", 1, true))
    stub.SetRestriction("Encounter", false)
    off(s)
end)

T.test("platerender: selected removal aborts, unrelated removal does not", function()
    local s = setup()
    s.command()
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    T.eq(s.probe():GetParent(), s.plate)
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
    off(s)
    T.truthy(s.text():find("selected plate was removed", 1, true))
end)

T.test("platerender: association watcher and phase advance reject a stale binding", function()
    local s = setup()
    s.command()
    s.lookup.nameplate1 = CreateFrame("Frame", nil, UIParent)
    stub.RunTickers()
    off(s)
    T.truthy(s.text():find("association changed", 1, true))
    s.lookup.nameplate1 = s.plate
    s.command()
    s.lookup.nameplate1 = nil
    s.command()
    off(s)
end)

T.test("platerender: timeout cleans, and an old timeout cannot cancel a newer run", function()
    local s = setup()
    s.command()
    local old = s.lastTimeout()
    T.eq(s.timeouts[#s.timeouts].seconds, 90)
    s.command("off")
    s.command()
    old()
    T.eq(s.probe():GetParent(), s.plate)
    s.lastTimeout()()
    off(s)
    T.truthy(s.text():find("Timed out", 1, true))
end)

T.test("platerender: setter error restores UIParent and exposes only an error count", function()
    local s = setup()
    s.command()
    s.command() -- UIParent / MEDIUM
    s.probe().SetFrameStrata = function() error("private name or GUID must not be printed") end
    s.command() -- TOOLTIP setter fails
    off(s)
    T.truthy(s.text():find("operation failed", 1, true))
    T.truthy(s.text():find("errors=1", 1, true))
    T.falsy(s.text():find("private name", 1, true))
end)

T.test("platerender: unsupported frame API refuses and restores UIParent", function()
    local s = setup()
    s.command()
    s.command()
    s.probe().SetFrameStrata = false
    s.command()
    off(s)
    T.truthy(s.text():find("refusals=1", 1, true))
end)

T.test("platerender: later phases perform only parent and strata mutations", function()
    local s = setup()
    s.command()
    local f, mutations = s.probe(), {}
    for _, method in ipairs({ "SetParent", "ClearAllPoints", "SetPoint", "SetSize", "SetScale", "SetAlpha",
        "SetFrameLevel", "SetFrameStrata", "Show", "Hide", "SetIgnoreParentAlpha", "SetIgnoreParentScale" }) do
        local original = f[method]
        f[method] = function(self, ...)
            mutations[#mutations + 1] = method
            return original(self, ...)
        end
    end
    s.command()
    T.deq(mutations, { "SetParent" })
    s.command()
    T.deq(mutations, { "SetParent", "SetFrameStrata" })
    s.command("off")
    off(s)
end)

T.test("platerender: target native plate is preferred and its stable token is tracked", function()
    local s = setup()
    local second = CreateFrame("Frame", nil, UIParent)
    s.lookup.nameplate2, s.lookup.target = second, second
    s.command()
    T.eq(s.probe():GetParent(), second)
    s.lookup.target = s.plate -- targeting changes do not move the selected binding
    s.command()
    local _, relative = s.probe():GetPoint()
    T.eq(relative, second)
    stub.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate2")
    off(s)
end)

T.test("platerender: hidden or behind-camera candidates are skipped and later loss invalidates", function()
    local s = setup()
    local second = CreateFrame("Frame", nil, UIParent)
    s.lookup.nameplate2 = second
    C_NamePlateManager.IsNamePlateUnitBehindCamera = function(unit) return unit == "nameplate1" end
    s.command()
    T.eq(s.probe():GetParent(), second)
    second:Hide()
    stub.RunTickers()
    off(s)
    T.truthy(s.text():find("no longer reads visible", 1, true))
end)

T.test("platerender: missing or secret camera API refuses instead of using an uncalibrated candidate", function()
    local s = setup()
    C_NamePlateManager.IsNamePlateUnitBehindCamera = nil
    s.command()
    T.isnil(s.probe())
    C_NamePlateManager.IsNamePlateUnitBehindCamera = function() return stub.Secret(false) end
    T.noerror(function() s.command() end)
    T.isnil(s.probe())
    T.truthy(s.text():find("camera APIs are unavailable", 1, true))
end)

T.test("platerender: secret anchor offsets invalidate without interpretation", function()
    local s = setup()
    s.command()
    s.probe().__secretAnchoring = true
    T.noerror(function() s.command() end)
    off(s)
    T.truthy(s.text():find("common anchor is unreadable", 1, true))
end)

T.test("platerender: secret readback invalidates without formatting secret values", function()
    local s = setup()
    s.command()
    s.probe().GetEffectiveScale = function() return stub.Secret(0.8) end
    T.noerror(function() s.command() end)
    off(s)
    T.truthy(s.text():find("invariant was not readable", 1, true))
end)

T.test("platerender: forbidden ancestry refuses before creation and pending cleanup never mutates it", function()
    local s = setup()
    s.world.__forbidden = true
    s.command()
    T.isnil(s.probe())
    s.world.__forbidden = false
    s.command()
    local f = s.probe()
    local hide, parent, touched = f.Hide, f.SetParent, 0
    f.Hide = function(self) touched = touched + 1; hide(self) end
    f.SetParent = function(self, p) touched = touched + 1; parent(self, p) end
    s.world.__forbidden = true
    s.command("off")
    T.eq(touched, 0)
    T.truthy(s.text():find("Cleanup pending", 1, true))
    s.world.__forbidden = false
    s.command("off")
    off(s)
    T.eq(touched, 2)
end)

T.test("platerender: a silently rejected invariant aborts instead of claiming a valid comparison", function()
    local s = setup()
    s.command()
    s.probe().SetFrameStrata = function() end
    s.command() -- phase 2 still MEDIUM
    s.command() -- phase 3 cannot become TOOLTIP
    off(s)
    T.truthy(s.text():find("did not match", 1, true))
    T.falsy(s.text():find("phase 3/3", 1, true))
end)

T.test("platerender: world transition invalidates the comparison", function()
    local s = setup()
    s.command()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    off(s)
    T.truthy(s.text():find("world transition", 1, true))
end)

T.test("platerender: cleanup remains pending when Hide or ClearAllPoints silently fails", function()
    for _, method in ipairs({ "Hide", "ClearAllPoints" }) do
        local s = setup()
        s.command()
        local f = s.probe()
        local original = f[method]
        f[method] = function() end
        s.command("off")
        T.truthy(s.text():find("Cleanup pending", 1, true))
        T.falsy(s.text():find("Probe off.", 1, true), "no unsupported success claim")
        f[method] = original
        s.command("off")
        off(s)
    end
end)

T.test("platerender: retry after a texture setup error reuses the one plain texture", function()
    local s = setup()
    local create = CreateFrame
    _G.CreateFrame = function(kind, name, parent, ...)
        local f = create(kind, name, parent, ...)
        if name == "DaylightUIPlateRenderProbe" then
            local createTexture = f.CreateTexture
            f.CreateTexture = function(self, ...)
                local texture = createTexture(self, ...)
                local color = texture.SetColorTexture
                texture.SetColorTexture = function(self, ...)
                    self.SetColorTexture = color
                    error("one failed texture setup")
                end
                return texture
            end
        end
        return f
    end
    s.command()
    _G.CreateFrame = create
    off(s)
    s.command()
    T.eq(select("#", s.probe():GetRegions()), 1)
    T.truthy(s.probe():IsShown())
    s.command("off")
    off(s)
end)
