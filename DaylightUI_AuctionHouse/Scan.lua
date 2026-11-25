-- Scan: the full scan, only when the player asks (the header's Full scan,
-- or "Scan now" on the first-visit card).
--
--   ns.Scan.Full() -> true | false, why   -- why is a sentence for the player
--   ns.Scan.Progress() -> done, total     -- rows of the running scan; nil when none
--   ns.On("ScanStarted", function(rkey) end)        -- a scan started (any way)
--   ns.Scan.Now() -> stage, done, total, left, share, unique   -- for the scan band; nil when none
--   ns.On("ScanEnded", function(ok, sentence, total, info) end)   -- the done or stopped line (when done: total rows,
--                                                                   info = { priced, skipped, fresh })
--
-- Every key the scan saw is recorded once (ns.Store.Record), each suffixed
-- item also under its plain itemID key (the cheapest of its suffixes, all
-- of them counted), SLICE keys a frame; then the ruleset's full-scan time,
-- one "PricesChanged" (payload: the ruleset key) and "ScanEnded" for the band. With no
-- ruleset key nothing is asked and nothing stored. The cooldown runs from
-- the moment the list was asked of the game (Store.MarkAsked), not from the
-- end of a save: a scan closed or timed out part way still started the
-- game's cooldown, and a second ask inside it would only time out.

local _, ns = ...
local L = ns.L

local Scan = {}
ns.Scan = Scan

Scan.FULL_COOLDOWN = 900   -- seconds between full scans per ruleset, from the ask (a guess: the client documents none)
Scan.READ_SHARE = 0.9      -- of the bar: reading; saving is the rest, so full means done

local running = false   -- from asking for the list until the last key is saved
local saving            -- while the keys are saved: how many rows the list had
local savedShare = 0    -- how much of the keys is saved (0 to 1)
local reached = 0       -- the furthest the bar has been (it never runs back)
local savingUnique = 0  -- different items the list held, kept for the saving stage

function Scan.Running()
    return running
end

-- How far the running scan is: rows read of the list (0, 0 until the game
-- answers), then the whole list while its keys are saved. Nil when none.
function Scan.Progress()
    if not running then return nil end
    if saving then return saving, saving end
    local done, total = ns.Replicate.Progress()
    return done or 0, total or 0
end

-- How far the bar is while the list is read (0 to READ_SHARE). Items the game
-- had to load weigh as much as the rows: `waiting` still out of `peak` at most.
function Scan.Share(read, total, waiting, peak)
    if total <= 0 then return 0 end
    local p = math.min(1, read / total)
    if peak > 0 then p = (p + 1 - math.min(1, waiting / peak)) / 2 end
    return p * Scan.READ_SHARE
end

-- The running scan for the band: its stage ("asking", "reading", "loading",
-- "saving"), rows done of total, items the game is still loading, how far
-- the bar is (0 to 1, never back) and how many different items it found.
-- Nil when none.
function Scan.Now()
    if not running then return nil end
    if saving then
        reached = math.max(reached, Scan.READ_SHARE + (1 - Scan.READ_SHARE) * savedShare)
        return "saving", saving, saving, 0, reached, savingUnique
    end
    local read, total, waiting, peak, unique = ns.Replicate.Progress()
    unique = unique or 0
    savingUnique = unique
    read, total, waiting, peak = read or 0, total or 0, waiting or 0, peak or 0
    reached = math.max(reached, Scan.Share(read, total, waiting, peak))
    local stage = total <= 0 and "asking" or (waiting > 0 and "loading" or "reading")
    return stage, read, total, waiting, reached, unique
end

-- The sentence for a scan that stopped before saving anything.
local function stopText(reason)
    if reason == "closed" then
        return L["Full scan stopped: the Auction House was closed. Nothing was kept."]
    elseif reason == "timeout" then
        -- the usual cause: a second ask inside the game's cooldown gets no answer
        return string.format(L["Full scan stopped: the Auction House didn't answer. The game allows one full scan every %d minutes."],
            math.floor(Scan.FULL_COOLDOWN / 60))
    elseif reason == "empty" then
        return string.format(L["Full scan stopped: the Auction House sent back no auctions. The game allows one full scan every %d minutes."],
            math.floor(Scan.FULL_COOLDOWN / 60))
    elseif reason == "ruleset" then
        return L["Full scan stopped: the ruleset changed."]
    end
    return L["Full scan stopped: something went wrong. Try again in a moment."]
end

-- Once per scan: a scan already ended (an error after its last line) says nothing more.
local function stopped(reason)
    if not running then return end
    running, saving = false, nil
    local text = stopText(reason)
    ns.Fire("ScanEnded", false, text)
end

-- The last line: items priced, and those skipped because the game never
-- loaded them (whole sentences: one and many read differently). `show` dresses
-- each number (the band's accent); default the plain number.
function Scan.DoneText(priced, skipped, show)
    show = show or ns.Thousands
    local p, s = show(priced), show(skipped)
    if skipped == 0 then
        if priced == 1 then return string.format(L["Full scan done: %s item priced."], p) end
        return string.format(L["Full scan done: %s items priced."], p)
    end
    if priced == 1 then
        if skipped == 1 then
            return string.format(L["Full scan done: %s item priced, %s skipped (the game hadn't loaded it; scan again later)."], p, s)
        end
        return string.format(L["Full scan done: %s item priced, %s skipped (the game hadn't loaded them; scan again later)."], p, s)
    end
    if skipped == 1 then
        return string.format(L["Full scan done: %s items priced, %s skipped (the game hadn't loaded it; scan again later)."], p, s)
    end
    return string.format(L["Full scan done: %s items priced, %s skipped (the game hadn't loaded them; scan again later)."], p, s)
end

-- Saves SLICE records a frame; the rows are whole by now, so the AH closing
-- meanwhile doesn't matter. By design, a /reload (or an error) during these
-- few frames keeps the keys already saved (the full scan time is written
-- last): what was saved is true. Rows read under another ruleset are thrown
-- away whole. Every frame of it runs guarded: an error anywhere (the first
-- lines included) is reported and ends the scan, so a later one isn't
-- refused as "already running" forever.
local function save(rkey, rows, skipped, total)
    local list, bases, at, known
    local i, priced = 1, 0
    local step
    local function guarded()
        if not ns.SafeCall(step) then stopped("error") end
    end
    saving = math.max(tonumber(total) or 0, #rows)
    step = function()
        if not list then
            if ns.Ruleset.Key() ~= rkey then return stopped("ruleset") end
            list, bases = ns.Rows.Records(rows)
            at = ns.Game.Now()
            known = ns.Store.Count(rkey)
        end
        local last, stop = math.min(i + ns.Game.SLICE - 1, #list), ns.Game.Deadline()
        while i <= last do
            local r = list[i]
            local ok = ns.Store.Record(rkey, r.key, r.unit, r.qty, at)
            if ok and bases[r.key] == r then priced = priced + 1 end
            i = i + 1
            if ns.Game.Late(stop) then break end
        end
        savedShare = (i - 1) / math.max(1, #list)
        if i <= #list then return C_Timer.After(0, guarded) end
        ns.Store.MarkFullScan(rkey, at)
        local total = saving
        running, saving = false, nil
        local missed = tonumber(skipped) or 0
        local text = Scan.DoneText(priced, missed)
        ns.Fire("PricesChanged", rkey)
        ns.Fire("ScanEnded", true, text, total,
            { priced = priced, skipped = missed, fresh = math.max(0, ns.Store.Count(rkey) - known) })
    end
    guarded()
end

-- Starts a full scan. False and a sentence when it can't: the AH is closed,
-- the ruleset isn't known (nothing would be stored), one is running, or the
-- last one was under FULL_COOLDOWN ago.
function Scan.Full()
    if not ns.AH.IsOpen() then return false, L["Open the Auction House first."] end
    local rkey = ns.Ruleset.Key()
    if not rkey then return false, L["The game hasn't said which Auction House this is yet. Try again in a moment."] end
    if running or ns.Replicate.Running() then return false, L["A full scan is already running."] end
    -- the later of the last ask and the last finished scan
    local last, asked = ns.Store.FullScanAt(rkey), ns.Store.AskedAt(rkey)
    if type(asked) == "number" and (type(last) ~= "number" or asked > last) then last = asked end
    if type(last) == "number" then
        local ago = ns.Game.Now() - last
        -- a clock that went back (ago < 0) doesn't hold scans up
        if ago >= 0 and ago < Scan.FULL_COOLDOWN then
            local minutes = math.max(1, math.ceil((Scan.FULL_COOLDOWN - ago) / 60))
            return false, string.format(L["Full scan again in %d min."], minutes)
        end
    end
    running, savedShare, reached, savingUnique = true, 0, 0, 0
    -- A start that fails at once (onDone runs inside Start) is answered by
    -- the return value, not also by a chat line.
    local starting, failedAtOnce = true, nil
    local started, why = ns.Replicate.Start(function(rows, reason, skipped, total)
        if starting then
            failedAtOnce = reason
            running = false
            return
        end
        if not rows then return stopped(reason) end
        save(rkey, rows, skipped, total)
    end, function()
        ns.Store.MarkAsked(rkey, ns.Game.Now())
    end)
    starting = false
    if started then
        ns.Fire("ScanStarted", rkey)
        return true
    end
    running = false
    if why == "busy" then return false, L["A full scan is already running."] end
    return false, stopText(failedAtOnce or why)
end
