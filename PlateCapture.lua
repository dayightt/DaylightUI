-- Local, bounded snapshots for nameplate investigations. Native frame flags
-- cannot establish whether pixels were drawn. No repair, native setter, hook,
-- unit name, GUID, chat text, location, hardware, or addon inventory is collected.
local _, DUI = ...
local L = DUI.L
local P = {}
DUI.PlateCapture = P
BINDING_NAME_DAYLIGHTUI_PLATECAPTURE = L["Capture missing nameplates"]

local LIMIT, HISTORY, EVENTS, DETAILS, RECORDS = 40, 60, 24, 6, 3
local MAX = 100000000
local REASONS = { owned_detached = true, owned_hidden = true, owned_invisible = true, owned_alpha_zero = true }
local GATES = { ready = true, restricted = true, loading = true, cinematic = true, movie = true,
    ui_hidden = true, ui_faded = true, unknown = true, plate_test = true, render_probe = true }
local EVENT_LABELS = { plate_added = true, plate_removed = true, combat_started = true, combat_ended = true,
    loading_started = true, world_entered = true, loading_ended = true, zone_changed = true,
    cinematic_started = true, cinematic_ended = true, movie_started = true, movie_ended = true,
    restriction_changed = true, ui_changed = true, display_changed = true, watch_on = true, watch_off = true }
EVENT_LABELS.action_blocked, EVENT_LABELS.action_forbidden, EVENT_LABELS.cursor_changed, EVENT_LABELS.modifier_changed = true, true, true, true
for _, label in ipairs({ "shift_down", "shift_up", "ctrl_down", "ctrl_up", "alt_down", "alt_up", "actionbar_grid_shown", "actionbar_grid_hidden" }) do
    EVENT_LABELS[label] = true
end
local FRAME_BOOL = { "shown", "visible", "rectValid" }
local FRAME_NUM = { "alpha", "effectiveAlpha", "scale", "level", "strata" }
local OWN_BOOL = { "expected", "owned", "nativeShown", "nativeVisible", "oursShown", "oursVisible",
    "attached", "barShown", "nameShown", "badgeShown", "minion", "nameOnly" }
local OWN_NUM = { "nativeAlpha", "nativeScale", "oursAlpha", "oursScale", "width", "height" }
local SAMPLE_BOOL = { "uiShown", "uiVisible", "nameplatesOn", "detailsTruncated", "incomplete" }
local SAMPLE_NUM = { "elapsed", "native", "owned", "bubbles", "bubblesVisible", "uiAlpha",
    "showAll", "showEnemies", "showFriendlyPlayers", "showFriendlyNpcs", "buffers", "failed", "unknown" }
local BUFFER_NUM = { "tracked", "requested", "requestedUnknown", "requests", "skipped", "enabled",
    "bufferUnknown", "flattened", "flattenUnknown", "effectiveFlattened", "effectiveUnknown", "unknown", "errors" }
local STRATA = { WORLD = 1, BACKGROUND = 2, LOW = 3, MEDIUM = 4, HIGH = 5,
    DIALOG = 6, FULLSCREEN = 7, FULLSCREEN_DIALOG = 8, TOOLTIP = 9 }
local rings, events, streaks, active = {}, {}, {}, {}
local ticker, cachedRoot, saved, pendingUI
local started, graceUntil = nil, 0
local loading, cinematic, movie, autoSaved, reminder = false, false, false, false, false
local uiKey, uiGeneration, reportGeneration = {}, 0, 0

local function secret(v) return DUI.IsSecret(v) end
local function tab(v) return not secret(v) and type(v) == "table" end
local function numeric(v)
    return not secret(v) and type(v) == "number" and v == v and v >= 0 and v <= MAX
end
local function fields(source, bools, nums)
    local out = {}
    if not tab(source) then return out end
    for _, key in ipairs(bools or {}) do
        local v = rawget(source, key)
        if not secret(v) and type(v) == "boolean" then out[key] = v end
    end
    for _, key in ipairs(nums or {}) do
        local v = rawget(source, key)
        if numeric(v) then out[key] = v end
    end
    return out
end
local function enum(v, allowed, fallback)
    return not secret(v) and type(v) == "string" and allowed[v] and v or fallback
end
local function version(v)
    return not secret(v) and type(v) == "string" and #v <= 24 and v:match("^%d+%.%d+%.%d+$") and v or "unknown"
end
local function elapsed()
    local ok, now = pcall(GetTime)
    if not ok or not numeric(now) then return 0 end
    if not started then started = now end
    return math.max(0, math.min(MAX, now - started))
end
local function sanitizeSample(source, detail)
    local out = fields(source, SAMPLE_BOOL, SAMPLE_NUM)
    out.gate = enum(tab(source) and rawget(source, "gate"), GATES, "unknown")
    if not detail then return out end
    out.ui = fields(tab(source) and rawget(source, "ui"), FRAME_BOOL, FRAME_NUM)
    out.buffer = fields(tab(source) and rawget(source, "buffer"), { "noFrameBuffers" }, BUFFER_NUM)
    out.plates = {}
    local plates = tab(source) and rawget(source, "plates")
    if tab(plates) then
        for i = 1, DETAILS do
            local p = rawget(plates, i)
            if tab(p) then
                local row = fields(p, nil, { "slot" })
                row.native = fields(rawget(p, "native"), FRAME_BOOL, FRAME_NUM)
                row.ours = fields(rawget(p, "ours"), OWN_BOOL, OWN_NUM)
                row.reason = enum(rawget(p, "reason"), REASONS)
                out.plates[#out.plates + 1] = row
            end
        end
    end
    return out
end
local function sanitizeRecord(source)
    if not tab(source) or secret(rawget(source, "schema")) or rawget(source, "schema") ~= 1 then return nil end
    local out = { schema = 1, version = version(rawget(source, "version")),
        kind = enum(rawget(source, "kind"), { structural = true, manual = true }, "manual"),
        reason = enum(rawget(source, "reason"), REASONS), current = sanitizeSample(rawget(source, "current"), true),
        history = {}, events = {} }
    local build = rawget(source, "clientBuild")
    if numeric(build) then out.clientBuild = build end
    local history = rawget(source, "history")
    if tab(history) then
        for i = 1, HISTORY do
            local item = rawget(history, i)
            if tab(item) then out.history[#out.history + 1] = sanitizeSample(item, false) end
        end
    end
    local recent = rawget(source, "events")
    if tab(recent) then
        for i = 1, EVENTS do
            local e = rawget(recent, i)
            if tab(e) then
                local label, at = enum(rawget(e, "what"), EVENT_LABELS), rawget(e, "elapsed")
                if label and numeric(at) then out.events[#out.events + 1] = { what = label, elapsed = at } end
            end
        end
    end
    return out
end
local function storage()
    if not DUI.DB or type(DUI.DB.Root) ~= "function" then return nil end
    local ok, root = pcall(DUI.DB.Root)
    if not ok or not tab(root) then return nil end
    if cachedRoot ~= root then
        local old = rawget(root, "plateCapture")
        local watch
        if tab(old) then watch = rawget(old, "watch") end
        saved = { schema = 1, watch = secret(watch) or watch ~= false, records = {} }
        local records = tab(old) and rawget(old, "records")
        if tab(records) then
            for i = 1, RECORDS do
                local clean = sanitizeRecord(rawget(records, i))
                if clean then saved.records[#saved.records + 1] = clean end
            end
        end
        root.plateCapture, cachedRoot = saved, root
    end
    return saved
end
local function keep(list, item, max)
    list[#list + 1] = item
    if #list > max then table.remove(list, 1) end
end
local function note(label)
    local s = storage()
    if s and s.watch then keep(events, { elapsed = elapsed(), what = label }, EVENTS) end
end
local function stopTicker()
    if ticker then pcall(ticker.Cancel, ticker); ticker = nil end
end
local function manager()
    local mod = DUI:GetModule("Nameplates")
    return mod and mod.enabled == true and mod.ns and mod.ns.Manager, mod and mod.enabled == true or false
end
local function call(stats, fn, ...)
    if type(fn) ~= "function" then stats.unknown = stats.unknown + 1; return nil end
    local ok, value = pcall(fn, ...)
    if not ok then stats.failed = stats.failed + 1; return nil end
    if secret(value) then stats.unknown = stats.unknown + 1; return nil end
    return value
end
local function read(stats, f, method)
    local ok, value = pcall(function() return f[method](f) end)
    if not ok then stats.failed = stats.failed + 1; return nil end
    if secret(value) then stats.unknown = stats.unknown + 1; return nil end
    return value
end
local function frameState(stats, f)
    local out = {}
    if not f then stats.unknown = stats.unknown + 1; return out end
    if read(stats, f, "IsForbidden") ~= false then stats.unknown = stats.unknown + 1; return out end
    for key, method in pairs({ shown = "IsShown", visible = "IsVisible", rectValid = "IsRectValid" }) do
        local v = read(stats, f, method)
        if type(v) == "boolean" then out[key] = v else stats.unknown = stats.unknown + 1 end
    end
    for key, method in pairs({ alpha = "GetAlpha", effectiveAlpha = "GetEffectiveAlpha", scale = "GetEffectiveScale", level = "GetFrameLevel" }) do
        local v = read(stats, f, method)
        if numeric(v) then out[key] = v else stats.unknown = stats.unknown + 1 end
    end
    local strata = read(stats, f, "GetFrameStrata")
    if type(strata) == "string" then out.strata = STRATA[strata] end
    if not out.strata then stats.unknown = stats.unknown + 1 end
    return out
end
local function gate(stats)
    local restricted = call(stats, DUI.Restricted)
    if restricted == true then return "restricted" end
    if restricted ~= false then return "unknown" end
    if loading or elapsed() < graceUntil then return "loading" end
    if cinematic then return "cinematic" end
    if movie then return "movie" end
    local shown, visible = read(stats, UIParent, "IsShown"), read(stats, UIParent, "IsVisible")
    local alpha = read(stats, UIParent, "GetEffectiveAlpha")
    if shown == false or visible == false then return "ui_hidden", shown, visible, alpha end
    if shown ~= true or visible ~= true or not numeric(alpha) then return "unknown", shown, visible, alpha end
    if alpha < 0.99 then return "ui_faded", shown, visible, alpha end
    local m = manager()
    if m and (m.testHidden == true or m.fixStep ~= nil) then return "plate_test", shown, visible, alpha end
    local r = DUI.PlateReport
    if r and type(r.FixActive) == "function" and call(stats, r.FixActive) ~= false then return "plate_test", shown, visible, alpha end
    local probe = DUI.PlateRenderProbe
    if probe and type(probe.Active) == "function" and call(stats, probe.Active) ~= false then return "render_probe", shown, visible, alpha end
    return "ready", shown, visible, alpha
end
local function flag(stats, key)
    local v = call(stats, GetCVar, key)
    if v == "1" or v == 1 then return 1 end
    if v == "0" or v == 0 then return 0 end
    stats.unknown = stats.unknown + 1
end
local function collect(details, preferred)
    local stats = { failed = 0, unknown = 0 }
    local state, shown, visible, alpha = gate(stats)
    local m, enabled = manager()
    local out = { elapsed = elapsed(), gate = state, uiShown = shown, uiVisible = visible,
        uiAlpha = numeric(alpha) and alpha or nil, nameplatesOn = enabled, plates = {} }
    local bindings = {}
    if state == "ready" then
        local buffers = call(stats, DUI.Fade and DUI.Fade.WholeCount)
        if numeric(buffers) then out.buffers = buffers else stats.unknown = stats.unknown + 1 end
        out.showAll = flag(stats, "nameplateShowAll")
        out.showEnemies = flag(stats, "nameplateShowEnemies")
        out.showFriendlyPlayers = flag(stats, "nameplateShowFriendlyPlayers")
        out.showFriendlyNpcs = flag(stats, "nameplateShowFriendlyNpcs")
        if details then out.ui = frameState(stats, UIParent) end
        local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        if type(get) == "function" then
            out.native, out.owned = 0, m and type(m.CaptureState) == "function" and 0 or nil
            local order, first = {}, preferred and tonumber(preferred:match("^nameplate(%d+)$"))
            if first then order[1] = first end
            for i = 1, LIMIT do if i ~= first then order[#order + 1] = i end end
            for _, i in ipairs(order) do
                local unit = "nameplate" .. i
                local before = stats.failed + stats.unknown
                local np = call(stats, get, unit)
                if np ~= nil and (type(np) == "table" or type(np) == "userdata") then
                    out.native = out.native + 1
                    local owned
                    if m and type(m.CaptureState) == "function" then owned = call(stats, m.CaptureState, unit, np) end
                    local identity = tab(owned) and rawget(owned, "identity")
                    if secret(identity) or (type(identity) ~= "table" and type(identity) ~= "userdata") then identity = nil end
                    local primitive = fields(owned, OWN_BOOL, OWN_NUM)
                    if primitive.owned == true and out.owned ~= nil then out.owned = out.owned + 1
                    elseif primitive.owned == nil and enabled then out.owned = nil end
                    bindings[unit] = { native = np, owned = identity,
                        reason = tab(owned) and enum(rawget(owned, "reason"), REASONS),
                        expected = primitive.expected == true }
                    if details and #out.plates < DETAILS then
                        out.plates[#out.plates + 1] = { slot = i, native = frameState(stats, np),
                            ours = primitive, reason = bindings[unit].reason }
                    end
                elseif np ~= nil or stats.failed + stats.unknown ~= before then
                    if np ~= nil then stats.unknown = stats.unknown + 1 end
                    out.native, out.owned = nil, nil
                    break
                end
            end
            out.detailsTruncated = details and out.native ~= nil and out.native > DETAILS or false
        else stats.unknown = stats.unknown + 1 end
        local bubbles = call(stats, C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles)
        if tab(bubbles) then
            out.bubbles, out.bubblesVisible = 0, 0
            for i = 1, 100 do
                local b = rawget(bubbles, i)
                if secret(b) then out.bubbles, out.bubblesVisible = nil, nil; stats.unknown = stats.unknown + 1; break end
                if b == nil then break end
                if type(b) ~= "table" and type(b) ~= "userdata" then
                    out.bubbles, out.bubblesVisible = nil, nil; stats.unknown = stats.unknown + 1; break
                end
                out.bubbles = out.bubbles + 1
                local v = read(stats, b, "IsVisible")
                if v == true then
                    if out.bubblesVisible ~= nil then out.bubblesVisible = out.bubblesVisible + 1 end
                elseif v ~= false then out.bubblesVisible = nil; stats.unknown = stats.unknown + 1 end
            end
            local extra = rawget(bubbles, 101)
            if secret(extra) or extra ~= nil then out.bubbles, out.bubblesVisible = nil, nil; stats.unknown = stats.unknown + 1 end
        end
        if details then
            local audit = call(stats, DUI.Fade and DUI.Fade.BufferAudit)
            out.buffer = fields(audit, { "noFrameBuffers" }, BUFFER_NUM)
        end
    end
    out.failed, out.unknown = stats.failed, stats.unknown
    out.incomplete = state ~= "ready" or stats.failed > 0 or stats.unknown > 0
    return sanitizeSample(out, details), bindings
end

local function value(v)
    if type(v) == "boolean" then return v and "1" or "0" end
    if numeric(v) then return string.format("%.3f", v):gsub("%.?0+$", "") end
    return "?"
end
local function line(label, source, keys)
    local parts = { label }
    for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. value(source and source[key]) end
    return table.concat(parts, " ")
end
function P.Format(record)
    local r = sanitizeRecord(record)
    if not r then return nil end
    local out = { "Daylight UI plate capture v1 schema=1 version=" .. r.version .. " clientBuild=" .. value(r.clientBuild),
        "Capture=" .. (r.kind == "structural" and "automatic structural observation" or "user requested")
            .. " reason=" .. (r.reason or "manual"),
        "Frame flags do not prove pixels rendered. Unknown values are ?. No names, locations, chat, hardware or addon lists collected.",
        "Native count means current nameplate1..40 associations; detail is limited to six plates, with the triggering slot first.",
        "Saved locally; persistence across /reload or logout does not guarantee survival of a client crash.",
        "Current gate=" .. r.current.gate,
        line("Current", r.current, SAMPLE_NUM), line("Flags", r.current, SAMPLE_BOOL),
        line("UI", r.current.ui, FRAME_BOOL), line("UI", r.current.ui, FRAME_NUM),
        line("Buffers", r.current.buffer, BUFFER_NUM), line("Buffers", r.current.buffer, { "noFrameBuffers" }) }
    for _, p in ipairs(r.current.plates) do
        out[#out + 1] = "Plate slot=" .. value(p.slot) .. " reason=" .. (p.reason or "none_or_unknown")
        out[#out + 1] = line(" Native", p.native, FRAME_BOOL)
        out[#out + 1] = line(" Native", p.native, FRAME_NUM)
        out[#out + 1] = line(" Owned", p.ours, OWN_BOOL)
        out[#out + 1] = line(" Owned", p.ours, OWN_NUM)
    end
    out[#out + 1] = "Recent samples: elapsed native owned bubbles uiAlpha buffers gate (seconds since login/reload)"
    for _, s in ipairs(r.history) do
        out[#out + 1] = table.concat({ value(s.elapsed), value(s.native), value(s.owned), value(s.bubbles), value(s.uiAlpha), value(s.buffers), s.gate }, " ")
    end
    out[#out + 1] = "Recent allowlisted events: elapsed event"
    for _, e in ipairs(r.events) do out[#out + 1] = value(e.elapsed) .. " " .. e.what end
    local text = table.concat(out, "\n")
    return #text <= 12000 and text or text:sub(1, 11950) .. "\nReport truncated at fixed size limit."
end

local maybeShow, uiRetry
local function available(entry)
    if entry.generation ~= reportGeneration then return false end
    local s = storage()
    if not s or (entry.auto and not s.watch) then return false end
    for _, record in ipairs(s.records) do if record == entry.record then return true end end
    return false
end
local function queueUI(kind, record)
    local text = P.Format(record) -- freeze the exact copy before any UI opens
    if not text then return end
    pendingUI = { kind = kind, text = text, record = record, generation = reportGeneration, auto = kind == "prompt" }
    DUI.AfterRestrictions(function() maybeShow() end, uiKey)
end
maybeShow = function()
    if not pendingUI then return end
    if not available(pendingUI) then pendingUI = nil; return end
    local quiet = gate({ failed = 0, unknown = 0 })
    local anotherPrompt = pendingUI.kind == "prompt" and DUI.Widgets.Asking and DUI.Widgets.Asking()
    if quiet ~= "ready" or anotherPrompt then
        -- Only a pending local notice/copy request retries. No native plates
        -- are sampled here, and there is no idle ticker or native UI hook.
        if not uiRetry then
            uiRetry = true
            C_Timer.After(2, function() uiRetry = nil; maybeShow() end)
        end
        return
    end
    local nextUI = pendingUI
    pendingUI = nil
    if nextUI.kind == "prompt" then
        DUI.Widgets.Ask({ key = "plateCapture", title = L["Nameplate report"],
            text = L["Possible nameplate display problem detected; a local report was saved. Frame flags cannot prove whether nameplates were drawn."],
            yes = L["Copy report"], no = L["Not now"],
            onYes = function()
                if not available(nextUI) then return end
                nextUI.kind = "show"
                pendingUI = nextUI
                DUI.AfterRestrictions(function() maybeShow() end, uiKey)
            end })
    else
        DUI.Profiles.ShowText(L["Nameplate report"], L["Ctrl+C to copy. This report stays local unless you choose to share it."], nextUI.text)
    end
end
local function retryUI()
    uiGeneration = uiGeneration + 1
    local generation = uiGeneration
    C_Timer.After(5, function() if generation == uiGeneration then maybeShow() end end)
end
local function freeze(kind, reason, current)
    local s = storage()
    if not s then return nil end
    local build
    if type(GetBuildInfo) == "function" then
        local ok, _, v = pcall(GetBuildInfo)
        if ok and not secret(v) then
            if type(v) == "string" and #v <= 9 and v:match("^%d+$") then v = tonumber(v) end
            if numeric(v) then build = v end
        end
    end
    local record = sanitizeRecord({ schema = 1, version = DUI.VERSION, clientBuild = build, kind = kind, reason = reason,
        current = current, history = rings, events = events })
    table.insert(s.records, 1, record)
    while #s.records > RECORDS do table.remove(s.records) end
    return record
end
function P.Capture()
    local current = collect(true)
    local record = freeze("manual", nil, current)
    if record then queueUI("show", record)
    else DUI.Print(L["The local nameplate report could not be saved."]) end
    return record
end
function P.Report(rest)
    local s = storage()
    if not s then return end
    if rest == "clear" then
        s.records = {}; pendingUI = nil; reportGeneration = reportGeneration + 1
        DUI.Print(L["Saved nameplate reports cleared."])
        return
    end
    local index = (rest == "" or rest == nil) and 1 or tonumber(rest)
    if index ~= 1 and index ~= 2 and index ~= 3 then DUI.Print(L["Use /dui platereport, /dui platereport 1, 2 or 3, or /dui platereport clear."]); return end
    local record = s.records[index]
    if sanitizeRecord(record) then queueUI("show", record) else DUI.Print(L["No saved nameplate report in that slot."]) end
end
function P.Tick()
    local s = storage()
    if not s or not s.watch then stopTicker(); streaks = {}; return end
    local current, bindings = collect(false)
    keep(rings, current, HISTORY)
    if current.gate ~= "ready" then streaks = {}; maybeShow(); return end
    if current.native == nil then streaks = {}; maybeShow(); return end
    active = {}
    for unit in pairs(bindings) do active[unit] = true end
    if not next(active) then stopTicker() end
    local nextStreaks, trigger = {}, nil
    for unit, b in pairs(bindings) do
        if b.expected and b.reason and b.owned then
            local old = streaks[unit]
            local n = old and old.native == b.native and old.owned == b.owned and old.reason == b.reason and old.count + 1 or 1
            nextStreaks[unit] = { native = b.native, owned = b.owned, reason = b.reason, count = math.min(n, 3) }
            if n >= 3 then trigger = trigger or { reason = b.reason, unit = unit } end
        end
    end
    streaks = nextStreaks
    if trigger and not autoSaved then
        local record = freeze("structural", trigger.reason, collect(true, trigger.unit))
        if record then autoSaved = true; queueUI("prompt", record) end
    end
    maybeShow()
end
local function startTicker()
    local s = storage()
    if s and s.watch and next(active) and not ticker then ticker = C_Timer.NewTicker(1, function() DUI.SafeCall(P.Tick) end) end
end
local function scan()
    local s = storage()
    if not s or not s.watch then stopTicker(); return end
    local current, bindings = collect(false)
    if current.gate == "ready" and current.native ~= nil then
        active = {}; for unit in pairs(bindings) do active[unit] = true end
    end
    if next(active) then startTicker() else stopTicker() end
end
function P.Watch(rest)
    local s = storage()
    if not s then return end
    if rest == "on" or rest == "off" then
        s.watch = rest == "on"; streaks = {}; note(s.watch and "watch_on" or "watch_off")
        if s.watch then scan() else
            stopTicker()
            rings, events = {}, {}
            if pendingUI and pendingUI.auto then pendingUI = nil end
        end
    elseif rest ~= "" and rest ~= "status" then
        DUI.Print(L["Use /dui platewatch on, /dui platewatch off, or /dui platewatch status."]); return
    end
    DUI.Print(s.watch and L["Local nameplate watch is on. Pixel-only failures still need a manual capture."]
        or L["Local nameplate watch is off. Manual capture remains available."])
end
local function token(unit)
    if secret(unit) or type(unit) ~= "string" then return nil end
    local i = tonumber(unit:match("^nameplate(%d+)$"))
    return i and i >= 1 and i <= LIMIT and unit == "nameplate" .. i and unit or nil
end
DUI.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
    note("plate_added"); local key = token(unit)
    if key then streaks[key] = nil; active[key] = true; startTicker() else streaks = {} end
end)
DUI.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    note("plate_removed"); local key = token(unit)
    if key then streaks[key] = nil; active[key] = nil else streaks = {} end
    if not next(active) then stopTicker() end
end)
local monitored = { PLAYER_REGEN_DISABLED = "combat_started", PLAYER_REGEN_ENABLED = "combat_ended",
    LOADING_SCREEN_ENABLED = "loading_started", PLAYER_ENTERING_WORLD = "world_entered",
    LOADING_SCREEN_DISABLED = "loading_ended", ZONE_CHANGED_NEW_AREA = "zone_changed",
    CINEMATIC_START = "cinematic_started", CINEMATIC_STOP = "cinematic_ended",
    PLAY_MOVIE = "movie_started", STOP_MOVIE = "movie_ended", ADDON_RESTRICTION_STATE_CHANGED = "restriction_changed",
    UI_SCALE_CHANGED = "ui_changed", DISPLAY_SIZE_CHANGED = "display_changed", ADDON_ACTION_BLOCKED = "action_blocked",
    ADDON_ACTION_FORBIDDEN = "action_forbidden", CURSOR_CHANGED = "cursor_changed",
    ACTIONBAR_SHOWGRID = "actionbar_grid_shown", ACTIONBAR_HIDEGRID = "actionbar_grid_hidden" }
for event, label in pairs(monitored) do
    DUI.RegisterEvent(event, function()
        note(label); streaks = {}
        if event == "LOADING_SCREEN_ENABLED" then loading = true end
        if event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then
            loading = false; graceUntil = elapsed() + 5; retryUI()
        end
        if event == "CINEMATIC_START" then cinematic = true end
        if event == "CINEMATIC_STOP" then cinematic = false end
        if event == "PLAY_MOVIE" then movie = true end
        if event == "STOP_MOVIE" then movie = false end
        DUI.AfterRestrictions(function() maybeShow() end, uiKey)
    end)
end
local modifierNames = { LSHIFT = "shift", RSHIFT = "shift", LCTRL = "ctrl", RCTRL = "ctrl", LALT = "alt", RALT = "alt" }
DUI.RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key, state)
    streaks = {}
    if secret(key) or secret(state) or type(key) ~= "string" then return end
    local name = modifierNames[key]
    if name and (state == 1 or state == 0) then note(name .. (state == 1 and "_down" or "_up"))
    else note("modifier_changed") end
end)
DUI.On("UIAlpha", function() streaks = {}; maybeShow() end)
DUI.On("AfkScreenHidden", function() maybeShow() end)
DUI.On("Login", function()
    local s = storage(); graceUntil = elapsed() + 5
    if s and #s.records > 0 and not reminder then
        reminder = true
        DUI.Print(L["A saved local nameplate report is available: /dui platereport."])
    end
    C_Timer.After(5, function() scan(); maybeShow() end)
end)
DUI.RegisterCommand("platecapture", function() P.Capture() end)
DUI.RegisterCommand("platereport", P.Report)
DUI.RegisterCommand("platewatch", P.Watch)
