-- Hover breakdown. Resting the mouse on a meter row opens a small panel
-- next to the meter showing that player's spells (and targets, for damage
-- done) in the current mode.
--
-- The game looks up a player by GUID, but in combat other players' GUIDs
-- are secret and it won't accept a secret one. Meter.GuidOf finds a plain
-- GUID where it can (yours, or a class + spec map taken out of combat);
-- anyone else waits until combat ends. Combat amounts are secret too, so
-- they go straight into bars and text, and shares and targets are only
-- computed from plain values.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style, Pixel = DUI.Style, DUI.Pixel

local Breakdown = {}
ns.Breakdown = Breakdown

Breakdown.WIDTH = 240
Breakdown.ROWS = 8            -- max spells
Breakdown.TARGETS = 3         -- max targets
Breakdown.ROW = 16
Breakdown.GAP = 6             -- gap to the meter
Breakdown.PAD = 6
Breakdown.WAIT = DUI.L["Available after combat"]
Breakdown.ROW_CFG = { rank = false, icons = "spec" }   -- icon slot shows the spell icon
Breakdown.TARGET_CFG = { rank = false, icons = "none" }

-- Test mode spells per mode. Amounts are fractions of the player's total.
Breakdown.SAMPLE = {
    damage = { { "Lashing Strike", 0.34 }, { "Shardblade", 0.24 }, { "Stormlight Surge", 0.17 },
               { "Windrunner Dive", 0.12 }, { "Melee", 0.08 }, { "Spren Bond", 0.05 } },
    healing = { { "Regrowth Surge", 0.41 }, { "Stormlight Mend", 0.27 }, { "Progression", 0.18 },
                { "Tension Ward", 0.09 }, { "Soulcast Salve", 0.05 } },
    taken = { { "Chasmfiend Bite", 0.38 }, { "Thunderclast Slam", 0.26 }, { "Parshendi Rhythm", 0.19 },
              { "Axehound Maul", 0.11 }, { "Falling Rock", 0.06 } },
    other = { { "Lashing Strike", 0.5 }, { "Shardblade", 0.3 }, { "Melee", 0.2 } },
}
Breakdown.SAMPLE.dps = Breakdown.SAMPLE.damage
Breakdown.SAMPLE.hps = Breakdown.SAMPLE.healing
Breakdown.SAMPLE.absorbs = Breakdown.SAMPLE.healing
Breakdown.SAMPLE_TARGETS = { { "Chasmfiend", 0.52 }, { "Axehound", 0.31 }, { "Whitespine", 0.17 } }

local frame, owner, rows, targetRows
local isSecret = function(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Modes for damage dealt, which have targets.
local DEALT = { damage = true, dps = true }

-- ---------------------------------------------------------------------
-- What to show
-- ---------------------------------------------------------------------

-- The game's data for this source in the meter's mode and fight, or nil
-- and a reason.
local function sourceData(src, meter)
    local mode = meter.Mode()
    if mode.key == "deaths" then return nil end
    local guid, creature = ns.Meter.GuidOf(src)
    if guid == nil and creature == nil then return nil, Breakdown.WAIT end
    local E = Enum and Enum.DamageMeterType
    local kind = E and E[mode.type]
    if kind == nil or not C_DamageMeter then return nil end
    local ok, data
    if meter.fight then
        ok, data = pcall(C_DamageMeter.GetCombatSessionSourceFromID or error, meter.fight, kind, guid, creature)
    else
        ok, data = pcall(C_DamageMeter.GetCombatSessionSourceFromType or error, meter.SessionType(), kind, guid, creature)
    end
    if not ok or type(data) ~= "table" or type(data.combatSpells) ~= "table" then return nil end
    return data
end

-- A player's spells as { { name, icon, amount }, ... }, biggest first, or
-- nil and a reason. meter defaults to the panel's meter.
function Breakdown.Spells(src, meter)
    meter = meter or ns.Meter
    local mode = meter.Mode()
    if mode.key == "deaths" then return Breakdown.DeathHits(src) end
    if meter.Sample() then
        local list = Breakdown.SAMPLE[mode.key] or Breakdown.SAMPLE.other
        local out = {}
        for i, s in ipairs(list) do out[i] = { name = s[1], amount = math.floor((src.totalAmount or 0) * s[2]) } end
        return out
    end
    local data, why = sourceData(src, meter)
    if not data then return nil, why end
    local out = {}
    for _, s in ipairs(data.combatSpells) do
        local id, name, icon = s.spellID, nil, nil
        if type(id) ~= "nil" and C_Spell then
            -- GetSpellName accepts a secret id; GetSpellTexture doesn't.
            if C_Spell.GetSpellName then
                local okN, n = pcall(C_Spell.GetSpellName, id)
                if okN then name = n end
            end
            if not isSecret(id) and C_Spell.GetSpellTexture then
                local okI, tex = pcall(C_Spell.GetSpellTexture, id)
                if okI then icon = tex end
            end
        end
        if type(name) == "nil" then name = s.creatureName end
        if type(name) == "nil" then name = DUI.L["Melee"] end
        local amount = s.totalAmount
        if type(amount) == "nil" then amount = 0 end
        out[#out + 1] = { name = name, icon = icon, amount = amount, rate = s.amountPerSecond, id = id, overkill = s.overkillAmount,
                          avoidable = s.isAvoidable, deadly = s.isDeadly }
    end
    return out
end

-- A death's last hits, killing blow first, or nil and a reason.
function Breakdown.DeathHits(src)
    local log, why = ns.DeathLog.Read(src and src.deathRecapID)
    if not log then return nil, why end
    local out = {}
    for i = #log.events, 1, -1 do
        local e = log.events[i]
        out[#out + 1] = { name = e.spell, icon = e.icon, amount = e.amount, heal = e.heal, death = true }
    end
    return out
end

-- Damage per target, merged by name, biggest first, or nil and a reason.
-- Merging compares names, so this only works out of combat.
function Breakdown.Targets(src, meter)
    meter = meter or ns.Meter
    if meter.Sample() then
        local out = {}
        for i, t in ipairs(Breakdown.SAMPLE_TARGETS) do
            out[i] = { name = t[1], amount = math.floor((src.totalAmount or 0) * t[2]) }
        end
        return out
    end
    local data, why = sourceData(src, meter)
    if not data then return nil, why end
    local byName, out = {}, {}
    for _, s in ipairs(data.combatSpells) do
        local d = s.combatSpellDetails
        if type(d) == "table" then
            local name, amount = d.unitName, d.amount
            if type(amount) == "nil" then amount = s.totalAmount end
            if isSecret(name) or isSecret(amount) then return nil, Breakdown.WAIT end
            if type(name) == "string" and name ~= "" and type(amount) == "number" then
                local t = byName[name]
                if not t then
                    t = { name = name, class = d.unitClassFilename, amount = 0 }
                    byName[name] = t
                    out[#out + 1] = t
                end
                t.amount = t.amount + amount
            end
        end
    end
    table.sort(out, function(a, b) return a.amount > b.amount end)
    return out
end

-- ---------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------

local function newRow(list, i, cfg)
    local r = ns.Rows.New(frame, Style.SIZE.tiny)
    r.layoutCfg = cfg
    list[i] = r
    return r
end

local function build()
    frame = CreateFrame("Frame", "DaylightUIMeterBreakdown", UIParent)
    DUI.Movers.FollowScale(frame)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    Style.Shell(frame)
    Breakdown.name = Style.Text(frame, Style.SIZE.small, "LEFT")
    Breakdown.name:SetWordWrap(false)
    Breakdown.total = Style.Text(frame, Style.SIZE.small, "RIGHT")
    Breakdown.sub = Style.Text(frame, Style.SIZE.tiny, "LEFT")
    Breakdown.sub:SetWordWrap(false)
    Breakdown.targetsHead = Style.Text(frame, Style.SIZE.tiny, "LEFT")
    Breakdown.hint = Style.Text(frame, Style.SIZE.tiny, "LEFT")
    Breakdown.hint:SetWordWrap(false)
    rows, targetRows = {}, {}
    Breakdown.rows, Breakdown.targetRows = rows, targetRows
    frame:Hide()
end

-- Left of the meter, or right of it when there's no room on the left.
local function place(bar)
    frame:ClearAllPoints()
    local inset = (ns.Panel.inset or 0) + Breakdown.GAP
    local left = bar:GetLeft()
    if type(left) == "number" and left * bar:GetEffectiveScale() / UIParent:GetEffectiveScale() < Breakdown.WIDTH + inset then
        frame:SetPoint("TOPLEFT", bar, "TOPRIGHT", inset, 0)
    else
        frame:SetPoint("TOPRIGHT", bar, "TOPLEFT", -inset, 0)
    end
end

-- Remembers the last layout. If nothing structural changed, a refresh only
-- updates numbers, names and colors.
local laid = { icons = {} }
local function sameLayout(key, spells, count)
    if laid.key ~= key then return false end
    for i = 1, count do
        if laid.icons[i] ~= (spells[i].icon ~= nil) then return false end
    end
    return true
end

local function hintText()
    local a = DUI.Win.Parts.Hex({ Style.Accent() })
    local t = DUI.Win.Parts.Hex(Style.INK.TEXT)
    return string.format(L["%sClick|r%s: details  ·  |r%sShift-click|r%s: report|r"], a, t, a, t)
end

function Breakdown.Show(bar)
    if not frame then build() end
    owner = bar
    laid.key = nil
    place(bar)
    Breakdown.Refresh()
end

-- Total of a list, or nil if any amount is secret.
local function plainTotal(list)
    local total = 0
    for i = 1, list and #list or 0 do
        local a = list[i].amount
        if type(a) ~= "number" or isSecret(a) then return nil end
        total = total + a
    end
    return total > 0 and total or nil
end

local function fillRow(row, s, top, total, paint)
    row.bar:SetMinMaxValues(0, top)
    row.bar:SetValue(s.amount)
    paint(row.bar)
    row.name:SetText(s.name)
    local amount = ns.Meter.Short(s.amount)
    if total and not isSecret(s.amount) then
        row.amount:SetText(string.format("%s  %d%%", amount, math.floor(s.amount / total * 100 + 0.5)))
    else
        row.amount:SetText(amount)
    end
end

function Breakdown.Refresh()
    if not (frame and owner) then return end
    local src = owner.src
    if not (owner:IsShown() and src) then return Breakdown.Hide() end
    local meter = owner.meter or ns.Meter
    local spells, reason = Breakdown.Spells(src, meter)
    if not spells and not reason then return Breakdown.Hide() end
    local targets
    if spells and DEALT[meter.Mode().key] then targets = Breakdown.Targets(src, meter) end
    local T = Pixel.Px(frame, Style.BorderPx(frame))
    local pad = Breakdown.PAD
    local scale = meter.TextScale()
    local rowH = math.floor(Breakdown.ROW * scale + 0.5)
    local count = spells and math.min(#spells, Breakdown.ROWS) or 0
    local tcount = targets and math.min(#targets, Breakdown.TARGETS) or 0
    local key = table.concat({ T, scale, count, tcount, reason or "" }, ":")
    local layout = not sameLayout(key, spells, count)
    local line = math.floor(Style.SIZE.small * scale + 4)
    local tiny = math.floor(Style.SIZE.tiny * scale + 4)
    local y = T + pad + line + tiny + 4
    if layout then
        laid.key = key
        for _, fs in ipairs({ Breakdown.name, Breakdown.total }) do Style.SetTextSize(fs, Style.SIZE.small * scale) end
        for _, fs in ipairs({ Breakdown.sub, Breakdown.targetsHead, Breakdown.hint }) do Style.SetTextSize(fs, Style.SIZE.tiny * scale) end
        Breakdown.total:ClearAllPoints()
        Breakdown.total:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(T + pad), -(T + pad))
        Breakdown.name:ClearAllPoints()
        Breakdown.name:SetPoint("TOPLEFT", frame, "TOPLEFT", T + pad, -(T + pad))
        Breakdown.name:SetPoint("RIGHT", Breakdown.total, "LEFT", -6, 0)
        Breakdown.sub:ClearAllPoints()
        Breakdown.sub:SetPoint("TOPLEFT", frame, "TOPLEFT", T + pad, -(T + pad + line))
        Breakdown.sub:SetPoint("RIGHT", frame, "RIGHT", -(T + pad), 0)
    end
    -- Colors are read every draw so style changes show up.
    local r, g, b = Style.ClassTextColor(src.classFilename)
    Breakdown.name:SetTextColor(r, g, b)
    Breakdown.name:SetText(owner.name:GetText())
    local st = src.totalAmount
    if type(st) == "nil" then st = 0 end
    Breakdown.total:SetText(ns.Meter.Short(st))
    Style.InkText(Breakdown.total, "pop")
    Breakdown.sub:SetText(string.format(L["%s · %s"], string.upper(L[meter.Mode().name]), (meter.FightTitle())))
    Style.InkText(Breakdown.sub, "LABEL")
    local paint = function(bar) meter.Paint(bar, src) end
    local top = 1
    if count > 0 then top = spells[1].amount end   -- not `and/or`, the amount may be secret
    local total = plainTotal(spells)
    -- Death recaps show amounts but no shares, since heals and hits don't sum.
    if count > 0 and spells[1].death then
        total = nil
        for i = 2, count do
            local a = spells[i].amount
            if type(a) == "number" and a > top then top = a end
        end
    end
    local function lay(row, at)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", T + pad, -at)
        row:SetPoint("RIGHT", frame, "RIGHT", -(T + pad), 0)
        row:SetHeight(rowH)
        Style.SetTextSize(row.name, Style.SIZE.tiny * scale)
        Style.SetTextSize(row.amount, Style.SIZE.tiny * scale)
        ns.Rows.Track(row, 0.5)
        ns.Rows.Layout(row, row.layoutCfg)
    end
    for i = 1, math.max(count, #rows) do
        local row = rows[i] or (i <= count and newRow(rows, i, Breakdown.ROW_CFG))
        if row then
            local s = i <= count and spells[i]
            if layout then
                row:SetShown(s and true or false)
                if s then
                    lay(row, y + (i - 1) * (rowH + 2))
                    laid.icons[i] = s.icon ~= nil
                end
            end
            if s then
                row.icon:SetShown(s.icon ~= nil)
                if s.icon then
                    row.icon:SetTexture(s.icon)
                    Style.CropIcon(row.icon)
                end
                fillRow(row, s, top, total, paint)
            end
        end
    end
    if reason then
        -- Nothing to list, so show the reason in the first row.
        local row = rows[1] or newRow(rows, 1, Breakdown.TARGET_CFG)
        if layout then
            row:Show()
            lay(row, y)
            row.icon:Hide()
        end
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)
        row.name:SetText(reason)
        row.amount:SetText("")
    end
    local bottom = y + (reason and 1 or count) * (rowH + 2)
    -- Targets (damage done, out of combat only).
    Breakdown.targetsHead:SetShown(tcount > 0)
    if tcount > 0 then
        if layout then
            Breakdown.targetsHead:ClearAllPoints()
            Breakdown.targetsHead:SetPoint("TOPLEFT", frame, "TOPLEFT", T + pad, -(bottom + 4))
        end
        Breakdown.targetsHead:SetText(string.upper(L["Targets"]))
        Style.InkText(Breakdown.targetsHead, "pop")
        bottom = bottom + tiny + 6
    end
    local ttop = 1
    if tcount > 0 then ttop = targets[1].amount end
    local ttotal = plainTotal(targets)
    for i = 1, math.max(tcount, #targetRows) do
        local row = targetRows[i] or (i <= tcount and newRow(targetRows, i, Breakdown.TARGET_CFG))
        if row then
            local t = i <= tcount and targets[i]
            if layout then
                row:SetShown(t and true or false)
                if t then lay(row, bottom + (i - 1) * (rowH + 2)) end
            end
            if t then fillRow(row, t, ttop, ttotal, paint) end
        end
    end
    bottom = bottom + tcount * (rowH + 2)
    if layout then
        Breakdown.hint:ClearAllPoints()
        Breakdown.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", T + pad, -(bottom + 2))
    end
    Breakdown.hint:SetText(hintText())
    Breakdown.hint:Show()
    if layout then
        frame:SetSize(Breakdown.WIDTH, bottom + 2 + tiny + pad + T)
        Style.LayoutShell(Style.GetShell(frame))
        -- Fades in. Moving between rows keeps it up, and a fade-out in
        -- progress reverses from its current alpha.
        DUI.Motion.AlphaTo(frame, 1, DUI.Motion.FAST)
    end
end

-- Fades out and hides when the mouse leaves the meter.
function Breakdown.Hide()
    owner = nil
    laid.key = nil
    if frame then DUI.Motion.AlphaTo(frame, 0, DUI.Motion.FAST, true) end
end

function Breakdown.Frame() return frame end
