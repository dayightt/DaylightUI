-- /dui sweep party | raid: steps through a set of looks for the party or raid
-- frames in test mode, one per click, each labeled, so a look can be checked
-- quickly. Each step is applied over the stock settings without touching the
-- player's own (Group.sweep). Close, combat or a reload restores them.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Sweep = {}
ns.Sweep = Sweep

local function with(base, extra)
    local t = {}
    for k, v in pairs(base or {}) do t[k] = v end
    for k, v in pairs(extra or {}) do
        -- Nested tables (the aura groups) are merged so a step that changes one
        -- group keeps the rest. Lists such as colors are replaced.
        if type(v) == "table" and type(t[k]) == "table" and #v == 0 then t[k] = with(t[k], v) else t[k] = v end
    end
    return t
end

local function healer(kind) return DUI.Profiles.PRESETS.Healer.UnitFrames[kind] end
local function healerText(kind) return healer(kind .. "Text") end

Sweep.STEPS = {
    party = {
        { label = L["DPS / Tank (as it comes)"], set = {} },
        { label = L["Healer"], set = healer("party"), text = healerText("party") },
        { label = L["Healer, angled end"], set = with(healer("party"), { slant = true }), text = healerText("party") },
        -- The portrait is as wide as the tile is tall, so widen the tile to leave room for a bar.
        { label = L["Healer, class portrait, 120 wide"], set = with(healer("party"), { portrait = "class", width = 120 }),
          text = healerText("party") },
        { label = L["Tiny bars: 100 x 20, portrait, angle, tab"], set = { width = 100, height = 20, portrait = "class", slant = true } },
        { label = L["Big bars: 240 x 60, 3D portrait, power text, buffs over"], set = { width = 240, height = 60, portrait = "3d",
          showPowerText = true, auras = { buffs = { spot = "above" } } } },
        { label = L["Name on the bar, angle, 170 x 34"], set = { width = 170, height = 34, nameOnBar = true, slant = true } },
        { label = L["Grid of 2: 80 x 40, fill upward"], set = { perLine = 2, width = 80, height = 40, fillVertical = true,
          portrait = "none", nameOnBar = true, hideSelf = false } },
        { label = L["Across, you shown, by role, icons in corners"], set = { direction = "rows", hideSelf = false,
          sortBy = "role", portrait = "none", showName = false } },
    },
    raid = {
        { label = L["DPS / Tank (as it comes)"], set = {} },
        { label = L["Healer"], set = healer("raid"), text = healerText("raid") },
        { label = L["Tiny: 40 x 20, angle, power, full highlight"], set = { width = 40, height = 20, slant = true,
          showPower = true, showDispel = true, dispelHighlight = "both" } },
        { label = L["Tall: 80 x 64, fill upward, buffs outside right"], set = { width = 80, height = 64, fillVertical = true,
          auras = { buffs = { show = true, spot = "outright" } } } },
    },
}

local function group(kind) return kind == "raid" and ns.Raid.group or ns.Party.group end

local function panel()
    if Sweep.frame then return Sweep.frame end
    local W, Style = DUI.Widgets, DUI.Style
    local f = CreateFrame("Frame", "DaylightUISweep", UIParent)
    f:SetSize(440, 64)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    Style.Shell(f)
    f.label = Style.Text(f, 13, "CENTER")
    f.label:SetPoint("TOP", f, "TOP", 0, -10)
    local function button(text, x, fn)
        local b = W.Button(f, text, 22)
        b:SetWidth(120)
        b:SetPoint("BOTTOM", f, "BOTTOM", x, 8)
        b:SetScript("OnClick", fn)
        return b
    end
    f.prev = button(L["Previous"], -130, function() Sweep.Step(-1) end)
    f.next = button(NEXT or L["Next"], 0, function() Sweep.Step(1) end)
    f.close = button(CLOSE or L["Close"], 130, function() Sweep.Stop() end)
    f:Hide()
    Sweep.frame = f
    return f
end

function Sweep.Apply()
    local d = ns.module and ns.module.db
    if not d or not Sweep.kind then return end
    local list = Sweep.STEPS[Sweep.kind]
    local step = list[Sweep.index]
    -- Apply over the stock look, not the player's. On the Healer profile the
    -- "DPS / Tank" step would otherwise look the same as the Healer one.
    local cfg = with(ns.DEFAULTS[Sweep.kind], step.set)
    local text = with(ns.DEFAULTS[Sweep.kind .. "Text"], step.text)
    local g = group(Sweep.kind)
    local cur = { cfg = cfg, text = text }
    g.sweep = cur
    DUI.AfterCombat(function()
    -- Stopped or moved on while this waited for combat to end.
        if g.sweep ~= cur then return end
        g:Layout(cfg, cur.text, d.range)
        g:ShowPreview(true)
    end, "sweep")
    Sweep.frame.label:SetText(string.format(Sweep.kind == "raid" and L["Raid %d/%d: %s"] or L["Party %d/%d: %s"],
        Sweep.index, #list, step.label))
end

function Sweep.Start(kind)
    if InCombatLockdown() then
        DUI.Print(L["The sweep can't start in combat."])
        return
    end
    if Sweep.kind then Sweep.Stop(true) end
    -- Enable test mode first, then set the kind. Turning test mode off fires
    -- TestModeChanged, which would stop a sweep that already started.
    if DUI.testMode and DUI.testRaid ~= (kind == "raid") then DUI.SetTestMode(false) end
    DUI.testRaid = kind == "raid"
    if not DUI.testMode and not DUI.SetTestMode(true) then return end
    Sweep.kind, Sweep.index = kind, 1
    panel():Show()
    Sweep.Apply()
end

function Sweep.Step(d)
    if not Sweep.kind then return end
    local n = #Sweep.STEPS[Sweep.kind]
    Sweep.index = ((Sweep.index - 1 + d) % n) + 1
    Sweep.Apply()
end

-- fromTest: test mode ended on its own (combat or /dui test), so leave it.
function Sweep.Stop(fromTest)
    if not Sweep.kind then return end
    group(Sweep.kind).sweep = nil
    Sweep.kind = nil
    if Sweep.frame then Sweep.frame:Hide() end
    if not fromTest and DUI.testMode then DUI.SetTestMode(false) end
    if ns.module then ns.Refresh(ns.module) end
end

DUI.On("TestModeChanged", function(on)
    if not on and Sweep.kind then Sweep.Stop(true) end
end)

DUI.RegisterCommand("sweep", function(rest)
    local kind = string.lower(rest or "")
    if kind ~= "party" and kind ~= "raid" then
        DUI.Print(L["/dui sweep party, or /dui sweep raid"])
        return
    end
    Sweep.Start(kind)
end, L["/dui sweep party|raid - step through sample looks for the party or raid frames, to check them"])
