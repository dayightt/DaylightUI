-- Swing timers: one bar per hand you swing with (main hand, off hand, ranged),
-- styled like the cast bar. Attached, they hang from the bottom of the player
-- frame's column the same way the cast bar does (borders overlapping, the
-- frame's angled end continued down the same line, text 3px in from each end):
-- under the cast bar while it shows, under the frame itself otherwise.
-- Detached, they sit on their own mover.
--
-- There's no combat log to read. The client reports when you swing and how
-- long the swing takes (PLAYER_SWING), and whether your target is in reach
-- (C_SwingTimer). A bar fills over the swing and empties when it lands. Out of
-- reach it dims and its time turns red. While a next-swing attack is queued
-- (Heroic Strike, Cleave, Maul) the melee bars switch color and show its name.
--
-- Hunters can turn on a line on the ranged bar where Auto Shot's wind-up
-- starts (moving past it delays the shot). Moving there, the bar reads "Stop
-- moving" and stays full until the shot. The ranged bar's name can also be
-- replaced by the target's distance (Melee, Dead zone, 20 yd...). Both are off
-- by default.
--
-- A client without the swing API gets no bars and registers nothing.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local ST = {}
ns.Swing = ST

ST.OUT_OF_RANGE_ALPHA = 0.4  -- a bar while your target is out of its reach
ST.TEXT_TICK = 0.05          -- how often the time left is rewritten
-- A landed swing's bar stays (empty) this long before it goes, so the next
-- swing, reported a moment later, doesn't make it blink off and on.
ST.GRACE = 0.1
-- Ranged: Auto Shot winds up before the next shot is reported, so the bar
-- waits longer before it goes.
ST.RANGED_GRACE = 0.8
ST.TEXT_SHARE = 0.9          -- text height as a share of the bar inside the border
ST.SLIDE = 0.2               -- seconds to slide out from under the player frame, or back
ST.RISE = 6                  -- a bar on its own: px it rises into place as it fades in
-- A bar detached on its own (swing.bars.<hand>.detach) is a separate piece on
-- its own mover. The rest stay together on the holder.
ST.MOVERS = { main = "unitframes.swingMain", off = "unitframes.swingOff", ranged = "unitframes.swingRanged" }
ST.POD_NAMES = { main = "DaylightUISwingMainHand", off = "DaylightUISwingOffHand", ranged = "DaylightUISwingRanged" }
ST.COLORS = {
    main = { 0.80, 0.68, 0.46 },     -- a warm sand, next to the cast bar's gold
    off = { 0.62, 0.56, 0.46 },      -- the same, quieter
    ranged = { 0.50, 0.66, 0.52 },   -- a soft green
}
ST.QUEUED = { 0.86, 0.44, 0.32 }     -- the melee bars while a next-swing attack waits
ST.OUT_OF_RANGE_TEXT = { 1, 0.32, 0.28 }
-- Next-swing attacks by class (every rank has the same name).
ST.QUEUE_SPELLS = { WARRIOR = { 78, 845 }, DRUID = { 6807 } }
-- Test mode: how far along each bar is, and its time left.
ST.SAMPLE = { main = { 0.62, "1.4" }, off = { 0.3, "1.9" }, ranged = { 0.8, "0.6" } }
ST.SAMPLE_BAND = 30                 -- test mode's range readout, in yards

-- Auto Shot's wind-up: the last 0.5 s of a shot at the bow's own printed speed,
-- scaled by haste like the reload (this shot's length over that speed). Moving
-- inside it delays the shot until you stand still. Your stop reaches the
-- server a ping + 0.1 s later (measured on Forever by AppelSwingsForever), so
-- the line sits that much earlier.
ST.WINDUP = 0.5
ST.WINDUP_LAG = 0.10
ST.WINDUP_MAX_SHARE = 0.9           -- a slowed fast bow still leaves room to move
ST.PING_FALLBACK = 0.12             -- seconds, until the game reports latency
ST.LINE_W = 2                       -- the wind-up line's width, px
ST.LINE_ALPHA = 0.85
-- How often the range readout is checked while the ranged bar shows.
ST.RANGE_TICK = 0.2
-- Distance bands to the target, nearest first: items whose use range the game
-- checks (LibRangeCheck-3.0's classic tables; AppelSwingsForever confirmed
-- these work on Forever). Melee range and whether Auto Shot reaches come from
-- the swing timer API itself.
ST.RANGE_ITEMS = {
    { yd = 10, items = { 17626, 10699, 17689 } },
    { yd = 15, items = { 4559 } },
    { yd = 20, items = { 10645, 1191, 4388 } },
    { yd = 25, items = { 13289 } },
    { yd = 30, items = { 7734, 17202, 835, 2091 } },
    { yd = 35, items = { 18904, 1399, 1402 } },
}
-- Auto Shot's minimum range is 8 yd, so a band closer than that where it
-- can't reach is the dead zone.
ST.DEAD_ZONE_YD = 15

function ST.Supported()
    return type(C_SwingTimer) == "table" and Enum and Enum.PlayerSwingType ~= nil
end

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The hands, top to bottom. speed: which of UnitAttackSpeed's returns belongs
-- to this hand. setting: the option that shows it. mover: its own piece's key
-- with "Move each bar on its own" (the main hand uses the holder's).
local function rowDefs()
    local T = Enum.PlayerSwingType
    return {
        { type = T.MainHand, key = "main", label = SWING_TIMER_MAIN_HAND or DUI.L["Main Hand"], melee = true, speed = 1, slot = 16,
          setting = "mainHand" },
        { type = T.OffHand, key = "off", label = SWING_TIMER_OFF_HAND or DUI.L["Off Hand"], melee = true, speed = 2, slot = 17,
          setting = "offHand" },
        { type = T.Ranged, key = "ranged", label = SWING_TIMER_RANGED or DUI.L["Ranged"], speed = 3, slot = 18, setting = "ranged" },
    }
end

-- A hand's speed, or nil when the client won't say (secret) or doesn't have it.
-- Ranged uses its own call where the client has one.
local function speedOf(def)
    local raw
    if def.speed == 3 and type(UnitRangedDamage) == "function" then
        local ok, s = pcall(UnitRangedDamage, "player")
        if ok then raw = s end
    end
    if type(raw) == "nil" then raw = (select(def.speed, UnitAttackSpeed("player"))) end
    return raw, plain(raw)
end

-- Whether a weapon is in that slot. An empty slot, a shield or a relic (a
-- druid's idol in the ranged slot) doesn't count. nil when the client won't say.
local function weaponInSlot(slot)
    if type(GetInventoryItemLink) ~= "function" or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    if not ok or (issecretvalue and issecretvalue(link)) then return nil end
    if type(link) == "nil" then return false end
    local okI, _, _, _, _, _, class = pcall(C_Item.GetItemInfoInstant, link)
    class = okI and plain(class) or nil
    if type(class) ~= "number" then return nil end
    return class == (Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2)
end

-- Whether you have something to swing in that hand. Checked by slot, since the
-- speeds are secret in every fight (and a speed always comes back, weapon or
-- not). Only when the slot can't be read does a hidden speed count as yes,
-- since a spare bar beats a shot that never shows.
local function hasWeapon(def)
    if def.speed == 1 then return true end
    local inSlot = weaponInSlot(def.slot)
    if type(inSlot) ~= "nil" then return inSlot end
    local raw, s = speedOf(def)
    if type(raw) ~= "nil" and s == nil then return true end
    return type(s) == "number" and s > 0
end

-- Whether you shoot with Auto Shot (a hunter). Other classes' bows and guns are
-- a separate cast, and a wand has no wind-up.
local function shootsAutoShot()
    local _, class = UnitClass("player")
    return plain(class) == "HUNTER"
end

-- Your world latency, as a round trip in seconds.
local function ping()
    if type(GetNetStats) ~= "function" then return ST.PING_FALLBACK end
    local ok, _, _, _, world = pcall(GetNetStats)
    world = ok and plain(world) or nil
    if type(world) == "number" and world > 0 and world < 2000 then return world / 1000 end
    return ST.PING_FALLBACK
end

-- The ranged weapon's printed speed (its tooltip's Speed line), read once per
-- weapon. nil while the game hasn't loaded it, which means a flat wind-up.
local bowSpeed, bowLink
local function readBowSpeed()
    local link = type(GetInventoryItemLink) == "function" and plain(GetInventoryItemLink("player", 18)) or nil
    if link == bowLink and bowSpeed then return bowSpeed end
    bowLink, bowSpeed = link, nil
    if not (link and C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", 18)
    if not (ok and type(data) == "table" and type(data.lines) == "table") then return nil end
    local word = SPEED or "Speed"
    for _, line in ipairs(data.lines) do
        local t = plain(line.rightText)
        if type(t) == "string" then
            t = t:gsub(",", ".")
            local i = t:find(word, 1, true)
            local n = i and tonumber(t:match("(%d+%.?%d*)", i))
            if n and n > 0.5 and n < 10 then
                bowSpeed = n
                return n
            end
        end
    end
    return nil
end

-- How long before the end of a shot of `dur` seconds you must stand still.
function ST.Windup(dur)
    local base = ST.WINDUP
    local speed = readBowSpeed()
    if speed and dur and dur > 0 then base = base * dur / speed end
    local block = base + ping() + ST.WINDUP_LAG
    if dur and dur > 0 then block = math.min(block, dur * ST.WINDUP_MAX_SHARE) end
    return block
end

-- Rows

ST.PAIR_KEYS = { main = "SWING_MAIN", off = "SWING_OFF", ranged = "SWING_RANGED" }

local function setColor(row)
    local queued = row.def.melee and row.holder.queued
    -- The Gradients page's pairs (Fill style): your class's with Class color,
    -- else one per hand. A queued attack (Heroic Strike, Cleave...) has its own.
    if ST.PAIR and DUI.Gradients then
        local key = ST.PAIR_KEYS[row.def.key]
        if queued then key = "SWING_QUEUED"
        elseif ST.PAIR_CLASS then key = DUI.Gradients.KeyFor("player") end
        Style.SetBarGradient(row.bar, false)
        DUI.Gradients.Paint(row.bar, key)
        return
    end
    -- The Daylight gradient (Fill style). A queued attack keeps its own color.
    if ST.GRADIENT and not queued then
        Style.SetBarGradient(row.bar, true)
        return
    end
    Style.SetBarGradient(row.bar, false)
    local c = queued and ST.QUEUED or ST.COLORS[row.def.key]
    Style.SetBarColor(row.bar, c[1], c[2], c[3])
end

-- The bar's name and time, and their colors. Priority: "Stop moving", then a
-- queued attack's name, then the target's distance, else the hand. Out of
-- reach it's red, but "Stop moving" keeps its warning color.
local L = DUI.L
local function paintText(row)
    local h = row.holder
    local band = row.band
    local text, ink = row.def.label, nil
    if row.stopWarn then
        text, ink = L["Stop moving"], "WARN"
    elseif row.def.melee and h.queued then
        text = h.queued
    elseif band == "melee" then
        text = L["Melee"]
    elseif band == "dead" then
        text, ink = L["Dead zone"], "WARN"
    elseif band == "max" then
        text = L["Max range"]
    elseif band == "far" then
        text = L["Out of range"]
    elseif type(band) == "number" then
        text, ink = string.format(L["%d yd"], band), "pop"
    end
    row.label:SetText(text)
    local out = row.outOfRange and not h.test
    local c = out and ST.OUT_OF_RANGE_TEXT or Style.INK.VALUE
    if ink and (not out or row.stopWarn) then
        Style.InkText(row.label, ink)
    else
        row.label:SetTextColor(c[1], c[2], c[3])
    end
    row.time:SetTextColor(c[1], c[2], c[3])
end

local function setLabel(row) paintText(row) end

-- Turns "Stop moving" on or off (only painted when it changes).
local function setStopWarn(row, on)
    on = on and true or nil
    if row.stopWarn == on then return end
    row.stopWarn = on
    paintText(row)
end

-- The wind-up line at `share` of the bar from where it fills (nil hides it).
-- It eases in and out instead of popping.
local function placeLine(row, share)
    local line = row.windLine
    if not line then return end
    -- Stored so a bar laid out later (shown, slid, resized) can place it again.
    row.lineShare = share
    if not share then
        if line.on then
            line.on = nil
            DUI.Motion.Fade(line, line:GetAlpha(), 0, DUI.Motion.FAST)
        end
        return
    end
    -- Every bar spans the holder, inside its border.
    local w = (row.alone and row.pod or row.holder):GetWidth() - 2 * Pixel.Px(row, ST.BorderOf(row.holder))
    if type(w) ~= "number" or w <= 0 then return end
    local x = math.max(0, math.min(w * share, w - (row.endCut or 0) - ST.LINE_W))
    if row.bar:GetReverseFill() then x = w - x - ST.LINE_W end
    x = Pixel.Snap(row, x)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", row.bar, "TOPLEFT", x, 0)
    line:SetPoint("BOTTOMLEFT", row.bar, "BOTTOMLEFT", x, 0)
    if not line.on then
        line.on = true
        line:Show()
        DUI.Motion.Fade(line, 0, ST.LINE_ALPHA, DUI.Motion.FAST)
    end
end

-- Whether the stop cue applies to this row: the setting, on a hunter's ranged bar.
local function cueOn(row)
    local h = row.holder
    return row.windLine ~= nil and h.cfg ~= nil and h.cfg.stopCue == true and (h.test or shootsAutoShot())
end

local function idle(row)
    row.start, row.dur, row.graceUntil, row.held, row.block = nil, nil, nil, nil, nil
    row:SetScript("OnUpdate", nil)
    row.bar:SetValue(0)
    row.time:SetText("")
    -- The wind-up line stays. The next shot moves it, so it never blinks.
    setStopWarn(row, false)
end

local onUpdate
local function onUpdate_(row, dt)
    local now = GetTime()
    local h = row.holder
    -- Delayed by moving during the wind-up: full, "Stop moving", until you
    -- stand still. The shot then comes one wind-up later.
    if row.held then
        if h.moving then return end
        row.held = nil
        setStopWarn(row, false)
        row.graceUntil = now + (row.block or 0) + ST.RANGED_GRACE
        return
    end
    -- Landed: empty, and hidden once the grace period ends with no new swing.
    if row.graceUntil then
        if now < row.graceUntil then return end
        idle(row)
        if h.cfg and h.cfg.visibility == "swinging" then ST.Restack(h) else ST.UpdateShown(h) end
        return
    end
    local left = row.start + row.dur - now
    -- Moving inside the wind-up: say so, and hold the bar full at the end.
    if row.block then setStopWarn(row, h.moving and left <= row.block) end
    if left <= 0 and row.block and h.moving then
        row.held = true
        row.bar:SetValue(1)
        row.time:SetText("")
        return
    end
    if left <= 0 then
        idle(row)
        row.graceUntil = now + (row.def.melee and ST.GRACE or ST.RANGED_GRACE)
        row:SetScript("OnUpdate", onUpdate)
        return
    end
    row.bar:SetValue((row.dur - left) / row.dur)
    row.tick = (row.tick or 0) + dt
    if row.tick >= ST.TEXT_TICK then
        row.tick = 0
        row.time:SetFormattedText("%.1f", left)
    end
end

onUpdate = onUpdate_

local function start(row, dur)
    if type(dur) ~= "number" or dur <= 0 or dur ~= dur then return end
    row.start, row.dur, row.tick, row.graceUntil, row.held = GetTime(), dur, 0, nil, nil
    row.bar:SetValue(0)
    row.time:SetFormattedText("%.1f", dur)
    if cueOn(row) then
        row.block = ST.Windup(dur)
        placeLine(row, 1 - row.block / dur)
    else
        row.block = nil
        placeLine(row, nil)
    end
    setStopWarn(row, false)
    row:SetScript("OnUpdate", onUpdate)
end

-- ease: the target just stepped in or out of reach, so the dim eases FAST. A
-- setting change or test mode sets it instantly.
local function applyRange(row, ease)
    local out = row.outOfRange and not row.holder.test
    local goal, M = out and ST.OUT_OF_RANGE_ALPHA or 1, DUI.Motion
    row.rangeKey = row.rangeKey or {}
    if ease and row:IsShown() then
        M.Tween(row.rangeKey, row:GetAlpha(), goal, M.FAST, function(a) row:SetAlpha(a) end)
    else
        M.Tween(row.rangeKey, 0, 0, 0)   -- ends a dim in progress
        row:SetAlpha(goal)
    end
    paintText(row)
end

local function setOutOfRange(row, out)
    out = out and true or false
    if row.outOfRange == out then return end
    row.outOfRange = out
    applyRange(row, true)
end

-- The weapon's picture in that hand's slot.
local function setIcon(row)
    row.icon:SetTexture(GetInventoryItemTexture("player", row.def.slot))
end

-- The swing bars' border in px: their own (swing.shell), else General's.
local function borderOf(h)
    local own = ns.UF.OwnShell(h and h.cfg)
    return own and tonumber(own.borderPx) or DUI.DB.General().borderPx
end
ST.BorderOf = borderOf

local function createRow(holder, def)
    local row = CreateFrame("Frame", nil, holder)
    row.holder, row.def = holder, def
    Style.Shell(row)
    Style.Slant(row, nil, 0)
    row.bar = Style.Bar(row, nil, ns.UF.MEDIA.swing.bar)
    Style.Clip(row, row.bar:GetStatusBarTexture(), "inner")
    Style.Clip(row, Style.BarBack(row.bar), "inner")
    local overlay = CreateFrame("Frame", nil, row)
    overlay:SetAllPoints(row)
    overlay:SetFrameLevel(row.bar:GetFrameLevel() + 3)
    row.icon = overlay:CreateTexture(nil, "ARTWORK")
    Style.CropIcon(row.icon)
    row.icon:Hide()
    row.label = Style.Text(overlay, 10, "LEFT", ns.UF.MEDIA.swing.font)
    row.time = Style.Text(overlay, 10, "RIGHT", ns.UF.MEDIA.swing.font)
    if not def.melee then
        -- The wind-up line, over the fill and under the text.
        row.windLine = overlay:CreateTexture(nil, "ARTWORK", nil, -1)
        row.windLine:SetWidth(ST.LINE_W)
        local c = Style.INK.TEXT
        row.windLine:SetColorTexture(c[1], c[2], c[3], 1)
        row.windLine:SetAlpha(0)
        row.windLine:Hide()
        -- The range readout's poll is a child, so it only runs while the bar shows.
        row.ranger = CreateFrame("Frame", nil, row)
    end
    setColor(row)
    setLabel(row)
    idle(row)
    row:Hide()
    return row
end

-- The holder

-- Which rows show: the setting is on and you have a weapon for it (in test
-- mode, whatever the settings allow).
local function usable(h, row)
    local cfg = h.cfg
    if not cfg then return false end
    if row.def.setting and not cfg[row.def.setting] then return false end
    return h.test or hasWeapon(row.def)
end

-- A bar's own settings when detached on its own (swing.bars.<hand>), else the
-- group's.
local function rowCfg(h, row)
    local bars = row.alone and h.cfg.bars
    return type(bars) == "table" and type(bars[row.def.key]) == "table" and bars[row.def.key] or h.cfg
end

local function live(row) return row.start ~= nil or row.graceUntil ~= nil end

-- While swinging (the default), a bar only shows while its swing runs and the
-- stack closes up between swings. keep: the bars are sliding back under the
-- frame (or into their box), so the visible ones stay up until they get there.
-- A bar on its own follows its own When to show.
local function wanted(h, row, keep)
    if not usable(h, row) then return false end
    if keep and row:IsShown() then return true end
    if h.test then return true end
    local vis = rowCfg(h, row).visibility
    if row.alone then
        if vis == "always" or live(row) then return true end
        return vis == "combat" and UnitAffectingCombat("player") == true
    end
    if vis == "swinging" then return live(row) end
    return true
end

-- Whether the group (every bar not on its own) is on: while swinging, while one
-- of its swings runs; in combat, then or while fighting; or always. In test
-- mode, while it has a bar to show.
local function wantShown(h)
    local cfg = h.cfg
    if not (cfg and h.enabled) then return false end
    local any, running = false, false
    for _, row in ipairs(h.rows) do
        if not row.alone and usable(h, row) then
            any = true
            if live(row) then running = true end
        end
    end
    if not any then return false end
    if h.test or cfg.visibility == "always" then return true end
    if cfg.visibility == "swinging" then return running end
    return running or UnitAffectingCombat("player") == true
end

-- A bar on its own: its piece rises into place as it fades in and sinks away
-- as it fades out, reversing from wherever it is.
local function podTo(row, on)
    local pod, sl = row.pod, row.pop
    if on then
        if not pod:IsShown() then
            sl:Jump(0)
            pod:Show()
        end
        sl:To(1)
    elseif pod:IsShown() then
        if pod:IsVisible() then sl:To(0) else pod:Hide() end
    end
end

-- Shown while on (see wantShown). Hung under the frame, the group slides out
-- and back instead of popping; detached, it slides out of its own box. Each
-- bar on its own comes and goes by itself.
function ST.UpdateShown(h)
    if not h then return end
    for _, row in ipairs(h.rows) do
        if row.alone then podTo(row, h.enabled and h.cfg ~= nil and wanted(h, row) or false) end
    end
    if wantShown(h) then
        -- Sliding back under: bring it out again from where it is.
        if h:IsShown() and h.slide.goal == 0 then h.slide:To(1) end
        h:Show()
    elseif h:IsShown() and (h.column or h.together or h.fan) and h:IsVisible() then
        h.slide:To(0)
    else
        h:Hide()
    end
end

-- The client only reports reach for hands that were asked about, and other
-- code can switch that off, so ask again on every change.
local function checkRange(h)
    for _, row in ipairs(h.rows) do
        local on = h.enabled and usable(h, row) or false
        pcall(C_SwingTimer.EnableRangeCheck, row.def.type, on)
        if on then
            local ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, row.def.type)
            setOutOfRange(row, ok and plain(inRange) == false)
        else
            setOutOfRange(row, false)
        end
    end
end

-- The next-swing attacks for your class, { id, name } each. Read once the class
-- and every name are known (retried until then).
local queueList
function ST.QueueList()
    if queueList then return queueList end
    local list, whole = {}, true
    local _, class = UnitClass("player")
    class = plain(class)
    if type(class) ~= "string" then return list end
    for _, id in ipairs(ST.QUEUE_SPELLS[class] or {}) do
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if type(name) == "string" and plain(name) then
            list[#list + 1] = { id = id, name = name }
        else
            whole = false
        end
    end
    if whole then queueList = list end
    return list
end

-- The next-swing attack queued now (Heroic Strike, Cleave, Maul): its spell ID
-- and name, or nil. Used by the swing bar's color and the power bar's cost
-- shade (UF.QueuedSwingSpell).
function ST.Queued()
    if not (C_Spell and C_Spell.IsCurrentSpell) then return nil end
    for _, q in ipairs(ST.QueueList()) do
        local ok, on = pcall(C_Spell.IsCurrentSpell, q.name)
        if ok and plain(on) == true then return q.id, q.name end
    end
    return nil
end

local function queuedAttack(h)
    if not (h.cfg and h.cfg.queue) then return nil end
    local _, name = ST.Queued()
    return name
end

function ST.UpdateQueue(h)
    local q = queuedAttack(h)
    if q == h.queued then return end
    h.queued = q
    for _, row in ipairs(h.rows) do
        setColor(row)
        setLabel(row)
    end
end

-- How far your target is: "melee", "dead" (too close to shoot), a number of
-- yards (within), "max" (only Auto Shot reaches), "far", or nil when the game
-- won't say (no enemy targeted, or the answers are secret).
local function itemInRange(id)
    if not (C_Item and C_Item.IsItemInRange) then return nil end
    local ok, r = pcall(C_Item.IsItemInRange, id, "target")
    if not ok then return nil end
    r = plain(r)
    if r == true or r == 1 then return true end
    if r == false or r == 0 then return false end
    return nil
end

local function swingReach(swingType)
    local ok, r = pcall(C_SwingTimer.IsTargetWithinSwingRange, swingType)
    if not ok then return nil end
    r = plain(r)
    if type(r) == "boolean" then return r end
    return nil
end

function ST.RangeBand()
    if plain(UnitExists("target")) ~= true then return nil end
    if type(UnitCanAttack) == "function" and plain(UnitCanAttack("player", "target")) ~= true then return nil end
    if type(UnitIsDeadOrGhost) == "function" and plain(UnitIsDeadOrGhost("target")) == true then return nil end
    local T = Enum.PlayerSwingType
    if swingReach(T.MainHand) == true then return "melee" end
    local shoots = swingReach(T.Ranged)
    local known = shoots ~= nil
    for _, rung in ipairs(ST.RANGE_ITEMS) do
        local yes = false
        for _, id in ipairs(rung.items) do
            local r = itemInRange(id)
            if r ~= nil then known = true end
            if r == true then yes = true break end
        end
        if yes then
            if shoots == false and rung.yd <= ST.DEAD_ZONE_YD then return "dead" end
            return rung.yd
        end
    end
    if shoots == true then return "max" end
    return known and "far" or nil
end

local function pollRange(ranger, dt)
    ranger.tick = (ranger.tick or 0) + dt
    if ranger.tick < ST.RANGE_TICK then return end
    ranger.tick = 0
    local row = ranger:GetParent()
    local band = ST.RangeBand()
    if band ~= row.band then
        row.band = band
        paintText(row)
    end
end

-- The range readout runs while it's turned on (in test mode, a sample).
function ST.UpdateRangeText(h)
    local on = h.cfg ~= nil and h.cfg.rangeText == true and h.enabled
    for _, row in ipairs(h.rows) do
        if row.ranger then
            if h.test then
                row.ranger:SetScript("OnUpdate", nil)
                row.band = on and ST.SAMPLE_BAND or nil
            elseif on then
                -- Ask fresh on the next frame (not the sample's).
                if row.ranger:GetScript("OnUpdate") ~= pollRange then row.band = nil end
                row.ranger.tick = ST.RANGE_TICK
                row.ranger:SetScript("OnUpdate", pollRange)
            else
                row.ranger:SetScript("OnUpdate", nil)
                row.band = nil
            end
            paintText(row)
        end
    end
end

-- Whether you're moving (the client's events keep it updated after this).
local function readMoving()
    if type(GetUnitSpeed) ~= "function" then return false end
    local ok, sp = pcall(GetUnitSpeed, "player")
    sp = ok and plain(sp) or nil
    return type(sp) == "number" and sp > 0
end

local function onEvent(h, event, ...)
    if event == "PLAYER_SWING" then
        local dur, swingType = ...
        local row = h.byType[swingType]
        if row and h.enabled and not h.test and usable(h, row) then
            local was = row.start or row.graceUntil
            -- In combat the length can be secret, so use the hand's speed, else
            -- the last one seen, to keep the bar going.
            local d = plain(dur)
            if type(d) ~= "number" or d <= 0 then
                local _, sp = speedOf(row.def)
                d = sp
                if type(d) ~= "number" or d <= 0 then d = row.lastDur end
            end
            row.lastDur = d or row.lastDur
            start(row, d)
            if not was and h.cfg.visibility == "swinging" then ST.Restack(h) else ST.UpdateShown(h) end
        end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local swingType, inRange, checks = ...
        local row = h.byType[swingType]
        if row then setOutOfRange(row, plain(checks) == true and plain(inRange) == false) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        checkRange(h)
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        ST.UpdateQueue(h)
    elseif event == "PLAYER_STARTED_MOVING" then
        h.moving = true
    elseif event == "PLAYER_STOPPED_MOVING" then
        h.moving = false
    elseif event == "WEAPON_SLOT_CHANGED" or event == "UNIT_ATTACK_SPEED" or event == "PLAYER_ENTERING_WORLD" then
        -- A weapon changed, so its row may appear or disappear.
        for _, row in ipairs(h.rows) do setIcon(row) end
        if event == "PLAYER_ENTERING_WORLD" then h.moving = readMoving() end
        ST.Restack(h)
    else
        ST.UpdateShown(h)
    end
end

local EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_TARGET_CHANGED", "WEAPON_SLOT_CHANGED",
                 "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_IN_COMBAT_CHANGED",
                 "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" }

function ST.Create()
    if not ST.Supported() then return nil end
    local h = CreateFrame("Frame", "DaylightUISwingTimer", UIParent)
    h:SetSize(1, 1)
    h.rows, h.byType, h.pods = {}, {}, {}
    h.moving = readMoving()
    -- The rows stand on this. It moves while the bars slide out of their own
    -- box (detached together), otherwise it's the holder's own box.
    h.inner = CreateFrame("Frame", nil, h)
    h.inner:SetAllPoints(h)
    for _, def in ipairs(rowDefs()) do
        local row = createRow(h, def)
        h.rows[#h.rows + 1] = row
        h.byType[def.type] = row
        -- Detached on its own: its own piece, which comes and goes by itself.
        local pod = CreateFrame("Frame", ST.POD_NAMES[def.key], UIParent)
        pod:SetSize(1, 1)
        pod:Hide()
        h.pods[def.key] = pod
        row.pod = pod
        row.pop = DUI.Motion.Slider(function(sl)
            if not row.alone then return end
            pod:SetAlpha(sl.p)
            ST.PlaceAlone(row)
        end, { parent = pod, dur = DUI.Motion.NORMAL,
            done = function(sl) if sl.p == 0 then pod:Hide() end end })
    end
    for _, e in ipairs(EVENTS) do pcall(h.RegisterEvent, h, e) end
    pcall(h.RegisterUnitEvent, h, "UNIT_ATTACK_SPEED", "player")
    if #ST.QueueList() > 0 then pcall(h.RegisterEvent, h, "ACTIONBAR_UPDATE_STATE") end
    h:SetScript("OnEvent", onEvent)
    -- Hung under the player frame, the bars slide out from under it (or from
    -- under the cast bar) and back. Once back under they hide, and the bars
    -- kept up while leaving are restacked. While the cast bar also slides,
    -- each of its steps already re-hangs these bars.
    h.slide = DUI.Motion.Slider(function(sl)
        if h.together then return ST.Unroll(h) end
        if h.fan then return ST.Fan(h) end
        local cb = h.castbar
        if sl.t and cb and cb.column and cb:IsVisible() and cb.slide:Moving() then return end
        ST.Hang(h)
    end, { parent = h, dur = ST.SLIDE,
        done = function(sl)
            if sl.p == 0 then
                h:Hide()
                ST.Restack(h)
            end
        end })
    h:HookScript("OnShow", function(self)
        if (self.column and self.column.f:IsVisible()) or self.together or self.fan then
            self.slide:Jump(0)
            self.slide:To(1)
        end
    end)
    h:HookScript("OnHide", function(self) self.slide:Jump(1) end)
    h:Hide()
    return h
end

-- A bar on its own in its piece: below its spot by whatever is left of its
-- rise (see podTo).
local function placeAlone(row)
    local y = -(1 - row.pop.p) * ST.RISE
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row.pod, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", row.pod, "TOPRIGHT", 0, y)
end
ST.PlaceAlone = placeAlone

-- The group's visible rows stacked top to bottom, borders overlapping like the
-- cast bar's under the player frame, with the holder sized to them. A bar
-- detached on its own sits in its own piece instead.
function ST.Restack(h)
    if not (h and h.cfg) then return end
    local T = Pixel.Px(h, borderOf(h))
    local height = h.rowHeight or 12
    local cfg = h.cfg
    local step = height - T
    local up = false
    if not h.attached and not h.fan then
        local gap = Pixel.Px(h, cfg.spacing or 0)
        step = gap > 0 and (height + gap) or (height - T)
        up = cfg.growUp == true
    end
    -- Leaving (the last swing is over): the visible bars stay as they are while
    -- they slide back under the frame or into their box.
    local keep = (h.column ~= nil or h.together or h.fan) and h:IsVisible() and not wantShown(h)
    local n, m = 0, 0
    local shown = {}
    for _, row in ipairs(h.rows) do
        if row.alone then
            local on = usable(h, row)
            row:SetShown(on)
            row:SetHeight(row.rowHeight or height)
            Style.Seams(row, false, false)
            placeAlone(row)
            if not on and row.start then idle(row) end
        else
            local show = wanted(h, row, keep)
            row:SetShown(show)
            if usable(h, row) then m = m + 1 end
            if show then
                row:ClearAllPoints()
                if h.fan then
                    -- Fanning out under the cast bar: each centered, with its
                    -- width set by ST.Place (wider further down).
                    row:SetPoint("TOP", h.inner, "TOP", 0, -n * step)
                elseif up then
                    row:SetPoint("BOTTOMLEFT", h.inner, "BOTTOMLEFT", 0, n * step)
                    row:SetPoint("BOTTOMRIGHT", h.inner, "BOTTOMRIGHT", 0, n * step)
                else
                    row:SetPoint("TOPLEFT", h.inner, "TOPLEFT", 0, -n * step)
                    row:SetPoint("TOPRIGHT", h.inner, "TOPRIGHT", 0, -n * step)
                end
                row:SetHeight(height)
                n = n + 1
                shown[#shown + 1] = row
            elseif row.start then
                idle(row)
            end
        end
    end
    -- Rows whose borders overlap don't cast shadows on each other, since one
    -- may draw under the other and its shadow would lie over that border.
    local touching = step == height - T
    for i, row in ipairs(shown) do
        local before, after = touching and i > 1, touching and i < #shown
        if up then Style.Seams(row, after, before) else Style.Seams(row, before, after) end
    end
    -- Detached, the box is as tall as every bar that could show, so it (and the
    -- mover saved by its center) doesn't jump between swings.
    if not h.attached and not h.fan then n = m end
    h:SetHeight(math.max(1, n * height + math.max(0, n - 1) * (step - height)))
    ST.Place(h)
    checkRange(h)
    ST.UpdateShown(h)
end

-- A detached bar's angled end and fill (its own height and settings).
local function shapeRow(h, row, rc, height, T, angle)
    local cut = rc.slant and Pixel.Snap(row, height * angle) or 0
    Style.Slant(row, cut > 0 and "right" or nil, cut)
    Style.AngleFill(row.bar, (cut > 0 and not rc.reverseFill) and "right" or nil, cut * (height - 2 * T) / height)
    row.endCut = cut
end

-- Detached together, the bars slide out of their own box and back. A clip
-- around the holder whose sliding edge is the box's own (its top, or its
-- bottom when they stack upward), slightly wider on the other sides for
-- shadows. It only cuts while sliding, so a shadow at rest stays whole.
function ST.BoxClip(h)
    local clip = h.boxClip
    if not clip then
        clip = CreateFrame("Frame", nil, UIParent)
        h.boxClip = clip
    end
    local M = ns.CastBar.CLIP_MARGIN
    local up = h.cfg and h.cfg.growUp == true
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", h, "TOPLEFT", -M, up and M or 0)
    clip:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", M, up and 0 or -M)
    return clip
end

-- Detached together: the rows' stand is pulled up into the box (or down when
-- they stack upward) by whatever is left of the slide.
function ST.Unroll(h)
    local p = h.slide.p
    local off = (1 - p) * h:GetHeight()
    if h.cfg and h.cfg.growUp == true then off = -off end
    h.inner:ClearAllPoints()
    h.inner:SetPoint("TOPLEFT", h, "TOPLEFT", 0, off)
    h.inner:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, off)
    local clip = h.boxClip
    local cut = p < 1
    if clip and clip.cut ~= cut then
        clip.cut = cut
        clip:SetClipsChildren(cut)
    end
end

-- Attached: hung under the last piece of the player frame's column (the cast
-- bar while it hangs there and shows, else the frame), borders overlapping,
-- each bar's angled end measured from the frame's top corner so the frame, the
-- cast bar and every swing bar share one line. Otherwise a plain straight
-- stack. A bar on its own is shaped by its own settings.
function ST.Place(h)
    if not (h and h.cfg) then return end
    local g = DUI.DB.General()
    local T = Pixel.Px(h, borderOf(h))
    local cb = h.castbar
    local f = h.attached and cb and cb.under or nil
    local height = h.rowHeight or 12
    local angle = h.docked and ns.Personal.Angle() or ns.UF.SLANT
    for _, row in ipairs(h.rows) do
        if row.alone then
            shapeRow(h, row, row.cfg or h.cfg, row.rowHeight or height, Pixel.Px(row, borderOf(h)), ns.UF.SLANT)
        end
    end
    if h.fan then
        -- Under the cast bar between the frames: in a clip whose top is the
        -- cast bar's bottom, so the bars fold out from under it.
        h.column = nil
        local clip = ST.FanClip(h, cb)
        if h:GetParent() ~= clip then h:SetParent(clip) end
        h.clipUnder = nil
        ST.FanShape(h)
        ST.Fan(h)
    elseif f then
        -- In a separate clip inside the cast bar's, so it slides out from under
        -- the frame (and from under the cast bar while that shows). With the
        -- cast bar detached, its clip still starts under the frame.
        if not cb.column then ns.CastBar.Clip(cb, f, ns.CastBar.Lift(f, Pixel.Px(f, g.borderPx))) end
        local clip = ST.Clip(h, cb.clip or UIParent)
        if h:GetParent() ~= clip then h:SetParent(clip) end
        h.clipUnder = nil
        -- base: where the frame's column ends (in Ribbon, its power line, as
        -- deep as the cast bar's top would hang from it).
        -- tuck: how far it overlaps the bottom of what it hangs from.
        local fH, onLine = f:GetHeight(), (f.foot or 0) > 0 and f.line ~= nil
        local base = fH - ns.CastBar.Lift(f, T) + T
        h.column = { f = f, fH = fH, T = T, height = height, base = base,
                     under = onLine and f.line or f, tuck = onLine and (T - base + fH + f.foot) or T }
        h:SetWidth(f:GetWidth())
        ST.Hang(h)
    else
        h.column = nil
        local parent = h.together and ST.BoxClip(h) or UIParent
        if h:GetParent() ~= parent then h:SetParent(parent) end
        for _, row in ipairs(h.rows) do
            if not row.alone then shapeRow(h, row, h.cfg, height, T, angle) end
        end
        ST.PlaceTimes(h)
        if h.docked then ns.Personal.Dock() end
    end
    for _, row in ipairs(h.rows) do
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.bar, "LEFT", ns.CastBar.PAD + (row.iconLead or 0) + (h.fan and row.endCut or 0), 0)
    end
end

-- Fanning out under the cast bar between the frames (CB.Middle): the clip the
-- bars fold out of, its top along the cast bar's bottom border, wide enough
-- for the widest bar's shadow.
function ST.FanClip(h, cb)
    local clip = h.fanClip
    if not clip then
        clip = CreateFrame("Frame", nil, UIParent)
        clip:SetClipsChildren(true)
        h.fanClip = clip
    end
    clip:SetFrameStrata(cb:GetFrameStrata())
    clip:SetFrameLevel(math.max(0, cb:GetFrameLevel() - 1))
    local cT = Pixel.Px(cb, Style.BorderPx(cb))
    local top = cT * cb:GetEffectiveScale() / clip:GetEffectiveScale()
    local M = 4 * ns.CastBar.CLIP_MARGIN
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", -M, top)
    clip:SetPoint("TOPRIGHT", cb, "BOTTOMRIGHT", M, top)
    clip:SetHeight(1000)
    return clip
end

-- Each bar under the cast bar continues its angled ends downward, both leaning
-- under at the cast bar's angle (h.fanRate), so each bar is wider than the one
-- above and the stack reads as one shape.
function ST.FanShape(h)
    local cb = h.castbar
    local T = Pixel.Px(h, borderOf(h))
    local cT = Pixel.Px(cb, Style.BorderPx(cb))
    local r = cb.fanRate or 0
    local W = cb:GetWidth()
    if type(W) ~= "number" or W <= 0 then W = h.cfg.width end
    h:SetWidth(W)
    local height = h.rowHeight or 12
    local step = height - T
    local cut = r * height
    local n = 0
    for _, row in ipairs(h.rows) do
        if row:IsShown() and not row.alone then
            -- Its top border overlaps the one above, so the line there is the
            -- cast bar's bottom width plus the angle down to it on each side.
            local depth = n * step - cT
            row:SetWidth(W + 2 * r * depth + 2 * cut)
            Style.Slant(row, cut > 0 and "both" or nil, cut, nil, "both")
            Style.AngleFill(row.bar, cut > 0 and "right" or nil, r * (height - 2 * T), true)
            row.endCut = cut
            n = n + 1
        end
    end
    ST.PlaceTimes(h)
end

-- Folded out by the slide: tucked up under the cast bar by what's left of it.
function ST.Fan(h)
    local cb = h.castbar
    if not (h.fan and cb) then return end
    local cT = Pixel.Px(cb, Style.BorderPx(cb))
    h:ClearAllPoints()
    h:SetPoint("TOP", cb, "BOTTOM", 0, cT + (1 - h.slide.p) * h:GetHeight())
end

-- The inner clip, inside the cast bar's (outer). As big as that one, except
-- while the bars slide out from under the cast bar or back, when its top is the
-- cast bar's bottom (see ST.Hang).
function ST.Clip(h, outer)
    local clip = h.clip
    if not clip then
        clip = CreateFrame("Frame", nil, outer)
        clip:SetClipsChildren(true)
        h.clip = clip
    end
    if clip:GetParent() ~= outer then clip:SetParent(outer) end
    clip:SetFrameStrata(outer:GetFrameStrata())
    clip:SetFrameLevel(outer:GetFrameLevel())
    return clip
end

-- Sliding out from under the cast bar or back, the bars are cut off at its
-- bottom edge (where their top border meets it). Drawing one level under isn't
-- enough, since each bar's pieces (fill, text, corner caps) sit on the same
-- levels as the cast bar's and could draw over it.
local function clipUnder(h, cb, under, tuck)
    if h.clipUnder == under then return end
    h.clipUnder = under
    local clip = h.clip
    local outer = clip:GetParent()
    clip:ClearAllPoints()
    if under then
        local top = tuck * h:GetEffectiveScale() / clip:GetEffectiveScale()
        clip:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", -ns.CastBar.CLIP_MARGIN, top)
        clip:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT")
    else
        clip:SetAllPoints(outer)
    end
end

-- Each bar's time, clear of its angled end.
function ST.PlaceTimes(h)
    for _, row in ipairs(h.rows) do
        row.time:ClearAllPoints()
        row.time:SetPoint("RIGHT", row.bar, "RIGHT", -(ns.CastBar.PAD + (row.endCut or 0)), 0)
        if row.lineShare then placeLine(row, row.lineShare) end
    end
end

-- Hung in the column: under the cast bar wherever it currently is (it slides
-- too), else the frame, tucked up by what's left of this slide. Each bar's
-- angled end continues the frame's edge wherever the bars are. Once settled it
-- hangs from the piece above, so it follows that piece.
function ST.Hang(h)
    local c = h.column
    if not c then return end
    local f, T, height = c.f, c.T, c.height
    local cb = h.castbar
    local cbOn = cb:IsShown() and cb.enabled and cb.column ~= nil
    local above, base, tuck = c.under or f, c.base or c.fH, c.tuck or T
    if cbOn then above, base, tuck = cb, math.max(base, ns.CastBar.Depth(cb)), T end
    local p = h.slide.p
    -- From the frame's top down to where this top border's outer edge meets the
    -- piece above (measured like the cast bar's bottom).
    local depth = base - h:GetHeight() * (1 - p)
    h:ClearAllPoints()
    if p == 1 and not (cbOn and cb.slide.p ~= 1) then
        h:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, tuck)
    else
        h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(depth - T))
    end
    -- Above what it hangs from, so its straight top border covers the rounded
    -- tip of the angle above (and below the portrait). While it slides out from
    -- under the cast bar it goes under that instead, cut off at its bottom
    -- (see clipUnder).
    if h.clip and h:GetParent() == h.clip then clipUnder(h, cb, p < 1 and cbOn, tuck) end
    if p < 1 and cbOn then
        h:SetFrameLevel(math.max(0, cb:GetFrameLevel() - 1))
    else
        h:SetFrameLevel(math.max(f:GetFrameLevel(), above:GetFrameLevel()) + 1)
    end
    local n = 0
    for _, row in ipairs(h.rows) do
        if row:IsShown() and not row.alone then
            n = n + 1
            local total = math.max(1, depth - T + n * (height - T) + T)
            local cut = (f.cut or 0) * total / c.fH
            local side = cut > 0 and "right" or nil
            -- One reused shape table per bar, since this runs every frame of a slide.
            local ref = row.slantRef or {}
            row.slantRef, ref.frame, ref.height = ref, f, total
            Style.Slant(row, side, cut, ref)
            Style.AngleFill(row.bar, side, cut * (height - 2 * T) / total)
            -- Each bar further down cuts further in, so its time stays clear of
            -- its own angled end, like the cast bar's.
            row.endCut = cut
        end
    end
    ST.PlaceTimes(h)
end

-- Sized and placed from the settings: hung under the player frame's column
-- (see ST.Place), or on its own mover.
function ST.Layout(h, cfg, castbar)
    if not h then return end
    local g = DUI.DB.General()
    h.cfg, h.enabled = cfg, cfg.enabled
    local c = cfg.colors
    if type(c) == "table" then
        ST.COLORS.main, ST.COLORS.off, ST.COLORS.ranged = c.main, c.off, c.ranged
        ST.QUEUED = c.queued
    end
    ST.GRADIENT = cfg.fill == "daylight"
    ST.PAIR = cfg.fill == "pair"
    ST.PAIR_CLASS = cfg.classColor == true
    -- Or your class color for every hand (a queued attack keeps its own).
    if cfg.classColor then
        local _, token = UnitClass("player")
        local mine = { Style.ClassColor(token) }
        ST.COLORS.main, ST.COLORS.off, ST.COLORS.ranged = mine, mine, mine
    end
    -- Hung under the player frame (under the cast bar while it hangs there) it
    -- takes the frame's size, otherwise its own. Detaching the cast bar leaves
    -- the swing bars hung. It can also go under the personal display (its
    -- page's switch, placed by Personal.Dock).
    h.docked = ns.Personal.Docks("swing")
    -- With the cast bar between the frames (and shown), they fan out under it.
    local fan = not h.docked and cfg.attach and castbar ~= nil and castbar.middle == true and castbar.enabled == true
    local hung = not h.docked and not fan and cfg.attach and castbar ~= nil and castbar.under ~= nil
    local fanKey = fan and ns.frames and ns.frames.player and ns.frames.player.moverKey
    h:SetScale(DUI.Movers.Scale((h.docked and ns.Personal.KEY) or (hung and castbar.under.moverKey) or fanKey or "unitframes.swing"))
    -- Its own border, corners and shadow on every bar (swing.shell), else General's.
    local own = ns.UF.OwnShell(cfg)
    for _, row in ipairs(h.rows) do ns.UF.WriteShell(Style.GetShell(row), own) end
    local T = Pixel.Px(h, borderOf(h))
    -- The height is the bar's own and the border goes around it, like the free
    -- power bar. A height that included the border left nothing on smaller
    -- screens, where the same 8 px are twice as thick in UI units.
    h.rowHeight = 2 * Pixel.Snap(h, cfg.height / 2) + 2 * T
    h.castbar = castbar
    h.attached = hung
    h.fan = fan or nil
    -- Detached as a group, the bars slide out of their own box.
    h.together = not hung and not h.docked and not fan
    if not h.together then
        h.inner:ClearAllPoints()
        h.inner:SetAllPoints(h)
        if h.boxClip then h.boxClip.cut = false; h.boxClip:SetClipsChildren(false) end
    end
    if not h.attached and not h.fan then h:SetWidth(2 * Pixel.Snap(h, (h.docked and ns.Personal.frame:GetWidth() or cfg.width) / 2)) end
    -- The column changes when a cast starts or ends, so re-hang then.
    if castbar and not h.hooked then
        h.hooked = true
        castbar:HookScript("OnShow", function() ST.Place(h) end)
        castbar:HookScript("OnHide", function() ST.Place(h) end)
        -- And follow it as it slides.
        castbar.moved = function() ST.Hang(h) end
    end
    -- Each bar detached on its own (not while docked) gets its own piece, mover
    -- and settings (swing.bars.<hand>).
    local bars = type(cfg.bars) == "table" and cfg.bars or {}
    local grouped = false
    for _, row in ipairs(h.rows) do
        local key = row.def.key
        local own = type(bars[key]) == "table" and bars[key] or nil
        local alone = own ~= nil and own.detach == true and not h.docked
        if row.alone and not alone then
            -- Back in the group: its piece goes away and the row returns.
            row.pop:Jump(0)
            row.pod:Hide()
            row.pod:SetAlpha(1)
        end
        row.alone, row.cfg = alone or nil, alone and own or nil
        local parent = alone and row.pod or h
        if row:GetParent() ~= parent then row:SetParent(parent) end
        local on = cfg.enabled and (not row.def.setting or cfg[row.def.setting]) and true or false
        if not alone and on then grouped = true end
        local mover = ST.MOVERS[key]
        if alone then
            row.pod:SetScale(DUI.Movers.Scale(mover))
            local rT = Pixel.Px(row.pod, borderOf(h))
            row.rowHeight = 2 * Pixel.Snap(row.pod, own.height / 2) + 2 * rT
            row.pod:SetSize(2 * Pixel.Snap(row.pod, own.width / 2), row.rowHeight)
        else
            row.rowHeight = h.rowHeight
        end
        DUI.Movers.Suspend(mover, not (alone and on))
    end
    DUI.Movers.Suspend("unitframes.swing", h.attached or h.docked or h.fan or not grouped)
    for _, row in ipairs(h.rows) do
        local rc = row.cfg or cfg
        local rT = row.alone and Pixel.Px(row.pod, borderOf(h)) or T
        local inner = (row.rowHeight or h.rowHeight) - 2 * rT
        -- Its own Text size. Hung under the cast bar, no taller than a row allows.
        local size = rc.textSize or 12
        local hungRow = (h.attached or h.fan) and not row.alone
        if hungRow then size = math.max(6, math.min(size, math.floor(inner * ST.TEXT_SHARE + 0.5))) end
        local iconSize = (not hungRow and rc.showIcon) and inner or 0
        row.iconLead = iconSize
        row.bar:SetReverseFill(not hungRow and rc.reverseFill == true)
        row.icon:ClearAllPoints()
        if iconSize > 0 then
            row.icon:SetSize(iconSize, iconSize)
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", rT, -rT)
            setIcon(row)
            row.icon:Show()
        else
            row.icon:Hide()
        end
        row.bar:ClearAllPoints()
        row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", rT, -rT)
        row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -rT, rT)
        Style.SetTextSize(row.label, size)
        Style.SetTextSize(row.time, size)
        -- Each bar's own name and time switches apply when attached too, but
        -- the group's Show names and time left still turns all of them off.
        local own = type(cfg.bars) == "table" and cfg.bars[row.def.key] or nil
        local ownName = not (own and own.showName == false)
        local ownTime = not (own and own.showTime == false)
        if row.alone then
            row.label:SetShown(ownName)
            row.time:SetShown(ownTime)
        else
            row.label:SetShown(cfg.showText and ownName)
            row.time:SetShown(cfg.showText and ownTime)
        end
        setColor(row)
        setLabel(row)
        if not cueOn(row) then placeLine(row, nil) end
        Style.LayoutShell(Style.GetShell(row))
    end
    if not cfg.enabled then
        for _, row in ipairs(h.rows) do idle(row) end
    end
    ST.UpdateQueue(h)
    ST.UpdateRangeText(h)
    ST.Restack(h)
end

-- Test mode: frozen bars partway through a sample swing.
function ST.ShowSample(h)
    if not h then return end
    h.test = true
    ST.Restack(h)
    ST.UpdateRangeText(h)
    for _, row in ipairs(h.rows) do
        local s = ST.SAMPLE[row.def.key]
        row:SetScript("OnUpdate", nil)
        row.start, row.held, row.block = nil, nil, nil
        setStopWarn(row, false)
        row.bar:SetValue(s[1])
        row.time:SetText(s[2])
        applyRange(row)
        -- The wind-up line where a 3 s shot's would be.
        placeLine(row, cueOn(row) and 1 - ST.Windup(3) / 3 or nil)
    end
    ST.UpdateShown(h)
end

function ST.HideSample(h)
    if not (h and h.test) then return end
    h.test = nil
    for _, row in ipairs(h.rows) do
        idle(row)
        applyRange(row)
        if not cueOn(row) then placeLine(row, nil) end
    end
    ST.UpdateRangeText(h)
    ST.Restack(h)
end
