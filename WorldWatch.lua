-- Tools for the bug where nameplates and speech bubbles stop drawing until a
-- /reload. Every Lua read looks normal while it happens, so these look at the
-- drawing instead.
--
-- /dui worldtest puts five squares on screen, each hung on a different layer:
-- UIParent, UIParent in the WORLD strata, a new frame on WorldFrame, the same
-- in the WORLD strata, and a texture on WorldFrame itself. A screenshot then
-- shows which layers still draw. It also hides UIParent for a moment and takes
-- a second screenshot: plates that come back while the rest of the UI is
-- hidden point at something of the UI that is on screen, plates still missing
-- point at state that lasts until a reload.
--
-- The recorder runs all session at one look a second: long frames (stalls,
-- graphics resets), the frame rate dropping to the background cap and back
-- (the game unfocused on another monitor), and every few minutes Lua memory
-- and font objects. Its lines go into every plate report.
-- Chat output stays in English: it's read by whoever works on the bug.

local _, DUI = ...
local L = DUI.L
local R = DUI.PlateReport

local W = {}
R.Watch = W

W.TICK = 1          -- seconds between looks
W.STALL = 2         -- a look this late or later means the game stood still
W.SAMPLE = 300      -- seconds between memory and font samples
W.SAMPLES = 12      -- samples kept (an hour)
W.FRAMES_AFTER = 60 -- seconds after login the first frame count is taken

local function clock() return type(GetTime) == "function" and GetTime() or 0 end

local function ago(at, now)
    if not at then return "never" end
    local s = math.max(0, math.floor(now - at + 0.5))
    return string.format("-%d:%02d", math.floor(s / 60), s % 60)
end

local function note(what)
    if R and R.Note then R.Note(what) end
end

------------------------------------------------------------------------------
-- The recorder
------------------------------------------------------------------------------

W.stalls = { count = 0, longest = 0 }
W.capped = { count = 0, now = false }
W.restarts = 0
W.samples = {}

local function luaMB() return collectgarbage("count") / 1024 end

local function fontCount()
    if type(GetFonts) ~= "function" then return nil end
    local list = GetFonts()
    return type(list) == "table" and #list or nil
end

-- Every frame the client has, ours and everyone's. A walk of all of them, so
-- it runs once a minute after login and when a report is built, never on a timer.
function W.FrameCount()
    if type(EnumerateFrames) ~= "function" then return nil end
    local n, f = 0, EnumerateFrames()
    while f do
        n = n + 1
        f = EnumerateFrames(f)
    end
    return n
end

local function sample()
    local list = W.samples
    list[#list + 1] = { at = clock(), mb = luaMB(), fonts = fontCount() }
    if #list > W.SAMPLES then table.remove(list, 1) end
end

-- The background cap only counts when it is on and lower than the normal cap,
-- else a low frame rate can't be told from an unfocused game.
local function backgroundCap()
    if not R or R.CVar("useMaxFPSBk") ~= "1" then return nil end
    local bk = tonumber(R.CVar("maxFPSBk") or "")
    if not bk or bk <= 0 then return nil end
    local fg = R.CVar("useMaxFPS") == "1" and tonumber(R.CVar("maxFPS") or "") or 0
    if fg > 0 and fg <= bk + 5 then return nil end
    return bk
end

local loading, last, nextSample = false, nil, nil

function W.Tick()
    local now = clock()
    if last and not loading then
        local gap = now - last
        if gap >= W.STALL then
            local s = W.stalls
            s.count, s.at = s.count + 1, now
            if gap > s.longest then s.longest = gap end
            note(string.format("game stood still %.1f s", gap))
        end
    end
    last = now
    if type(GetFramerate) == "function" then
        local fps, cap = GetFramerate(), backgroundCap()
        if type(fps) == "number" and cap then
            local c = W.capped
            local at = fps <= cap + 1
            if at ~= c.now then
                c.now = at
                if at then
                    c.count, c.at = c.count + 1, now
                    note(string.format("frame rate down to the background cap (%.0f fps)", fps))
                else
                    note(string.format("frame rate back (%.0f fps)", fps))
                end
            end
        end
    end
    if not nextSample or now >= nextSample then
        nextSample = now + W.SAMPLE
        sample()
    end
end

DUI.RegisterEvent("LOADING_SCREEN_ENABLED", function() loading = true end)
DUI.RegisterEvent("LOADING_SCREEN_DISABLED", function() loading, last = false, clock() end)
DUI.RegisterEvent("GX_RESTARTED", function()
    W.restarts, W.restartAt = W.restarts + 1, clock()
    note("graphics restarted")
end)
DUI.RegisterEvent("PLAYER_LOGIN", function()
    W.loginMB, W.loginFonts = luaMB(), fontCount()
    C_Timer.NewTicker(W.TICK, W.Tick)
    C_Timer.After(W.FRAMES_AFTER, function() W.loginFrames = W.FrameCount() end)
end)

local function from(a, b, fmt)
    if not a or not b then return "?" end
    return string.format(fmt .. " -> " .. fmt, a, b)
end

function W.Lines()
    local now, s, c = clock(), W.stalls, W.capped
    local cap = backgroundCap()
    local capText = cap and string.format("%d times (now %s, last %s)", c.count, c.now and "at it" or "not",
        ago(c.at, now)) or "can't tell (no background cap set)"
    local mbs = {}
    for _, x in ipairs(W.samples) do mbs[#mbs + 1] = string.format("%.0f", x.mb) end
    local newest = W.samples[#W.samples]
    return {
        string.format("Session: game stood still %d times (longest %.1f s, last %s), background frame cap %s, "
            .. "graphics restarts %d (last %s)", s.count, s.longest, ago(s.at, now), capText, W.restarts,
            ago(W.restartAt, now)),
        string.format("Growth since login: Lua memory %s MB, fonts %s, frames %s; memory every %d min: %s",
            from(W.loginMB, luaMB(), "%.0f"), from(W.loginFonts, fontCount(), "%d"),
            from(W.loginFrames, W.FrameCount(), "%d"), W.SAMPLE / 60,
            #mbs > 0 and table.concat(mbs, " ") or "none yet"),
        newest and newest.fonts and W.loginFonts and newest.fonts ~= W.loginFonts
            and string.format("Fonts at the last sample: %d", newest.fonts) or nil,
    }
end

-- Every plate report (platefix, with the Nameplates module on or off) is built
-- from R.World, so the recorder's lines ride along with it.
if R and R.World then
    local world = R.World
    function R.World(...)
        local out = world(...)
        for _, line in ipairs(W.Lines()) do out[#out + 1] = line end
        return out
    end
end

------------------------------------------------------------------------------
-- /dui worldtest
------------------------------------------------------------------------------

W.SQUARE = 36
W.GAP = 28
W.TOP = 150         -- the squares' distance from the top of the screen
W.SHOT_AT = 1       -- seconds in: first screenshot, everything on
W.HIDE_AT = 2       -- UIParent hidden
W.SHOT2_AT = 3.5    -- second screenshot, UIParent still hidden
W.SHOW_AT = 5       -- UIParent back, squares gone, report up
W.HIDE_CHILDREN = 12 -- names listed of WorldFrame's other shown children

W.LAYERS = {
    { label = "1 UI", parent = "ui" },
    { label = "2 UI WORLD", parent = "ui", strata = "WORLD" },
    { label = "3 WorldFrame", parent = "world" },
    { label = "4 WorldFrame WORLD", parent = "world", strata = "WORLD" },
    { label = "5 WorldFrame texture", parent = "worldtex" },
}

local made
local function scaleOf(f)
    local s = f:GetEffectiveScale()
    return type(s) == "number" and s > 0 and s or 1
end

-- Built once and kept. The squares show and go at once on purpose: a fade
-- would make the screenshot depend on when it was taken.
local function build()
    if made then return made end
    made = { squares = {}, labels = {} }
    local strip = CreateFrame("Frame", nil, UIParent)
    strip:SetFrameStrata("HIGH")
    strip:SetAllPoints(UIParent)
    made.strip = strip
    local ink = DUI.Style.INK.VALUE
    for i, layer in ipairs(W.LAYERS) do
        local parent = layer.parent == "ui" and UIParent or WorldFrame
        local k = scaleOf(UIParent) / scaleOf(parent)
        local x = (i - (#W.LAYERS + 1) / 2) * (W.SQUARE + W.GAP) * k
        local square, tex
        if layer.parent == "worldtex" then
            tex = WorldFrame:CreateTexture(nil, "OVERLAY")
            square = tex
        else
            square = CreateFrame("Frame", nil, parent)
            if layer.strata then square:SetFrameStrata(layer.strata) end
            tex = square:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(square)
        end
        tex:SetColorTexture(ink[1], ink[2], ink[3], 1)
        square:SetSize(W.SQUARE * k, W.SQUARE * k)
        square:SetPoint("TOP", parent, "TOP", x, -W.TOP * k)
        square:Hide()
        made.squares[i] = square
        -- The label sits on UIParent, so an empty spot still says what was meant to be there.
        local fs = DUI.Style.Text(strip, DUI.Style.SIZE.small, "CENTER")
        fs:SetPoint("TOP", UIParent, "TOP", (i - (#W.LAYERS + 1) / 2) * (W.SQUARE + W.GAP), -W.TOP - W.SQUARE - 6)
        DUI.Style.InkText(fs, "LABEL")
        fs:SetText(L[layer.label])
        made.labels[i] = fs
    end
    strip:Hide()
    return made
end

local function showSquares(on)
    local m = build()
    for _, sq in ipairs(m.squares) do sq:SetShown(on) end
    m.strip:SetShown(on)
end

local function ask(f, method) return R.Asked(f, method) end

-- One line per frame of how it would draw.
function W.FrameLine(name, f)
    if type(f) ~= "table" then return name .. ": missing" end
    local kids, shown = 0, 0
    local list = { f:GetChildren() }
    kids = #list
    for _, c in ipairs(list) do
        if ask(c, "IsShown") == "true" then shown = shown + 1 end
    end
    return string.format("%s: shown %s, visible %s, alpha %s, effective %s, scale %s, strata %s, level %s, "
        .. "clips %s, flattens %s, buffer %s, rect valid %s at %s, children %d (%d shown)", name, ask(f, "IsShown"),
        ask(f, "IsVisible"), ask(f, "GetAlpha"), ask(f, "GetEffectiveAlpha"), ask(f, "GetScale"),
        ask(f, "GetFrameStrata"), ask(f, "GetFrameLevel"), ask(f, "DoesClipChildren"),
        ask(f, "GetFlattensRenderLayers"), ask(f, "IsFrameBuffer"), ask(f, "IsRectValid"), R.Where(f), kids, shown)
end

-- WorldFrame's shown children that aren't nameplates: anything else hung there
-- (another addon's, or ours by mistake) is a suspect.
function W.WorldChildren()
    if type(WorldFrame) ~= "table" then return "WorldFrame children: missing" end
    local plates, others, more = 0, {}, 0
    -- R.Asked reads each answer guarded: a plate may refuse a read.
    for _, c in ipairs({ WorldFrame:GetChildren() }) do
        local name = ask(c, "GetName")
        if name == "nil" or name == "?" or name == "secret" then name = nil end
        if name and name:find("^NamePlate%d") then
            plates = plates + 1
        elseif ask(c, "IsShown") == "true" then
            if #others < W.HIDE_CHILDREN then others[#others + 1] = name or "(no name)" else more = more + 1 end
        end
    end
    return string.format("WorldFrame children: plates %d, other shown: %s%s", plates,
        #others > 0 and table.concat(others, ", ") or "none", more > 0 and string.format(" +%d more", more) or "")
end

local function readouts(title, out)
    out[#out + 1] = title
    out[#out + 1] = "  " .. W.FrameLine("WorldFrame", WorldFrame)
    out[#out + 1] = "  " .. W.FrameLine("UIParent", UIParent)
    out[#out + 1] = "  " .. W.WorldChildren()
    local seen = {}
    for i, sq in ipairs(made.squares) do
        seen[#seen + 1] = string.format("%d %s/%s at %s", i, ask(sq, "IsVisible"), ask(sq, "GetEffectiveAlpha"),
            R.Where(sq))
    end
    out[#out + 1] = "  Squares visible/alpha: " .. table.concat(seen, ", ")
end

local shots = 0
DUI.RegisterEvent("SCREENSHOT_SUCCEEDED", function() shots = shots + 1 end)

local function shoot()
    if type(Screenshot) == "function" then DUI.SafeCall(Screenshot) end
end

local running
local function showUI()
    if UIParent:IsShown() then return end
    if InCombatLockdown() then
        DUI.AfterCombat(function() UIParent:Show() end, "worldtest")
    else
        UIParent:Show()
    end
end

function W.Run()
    if running then return "worldtest: already running, hold still a moment." end
    if InCombatLockdown() then return "worldtest: leave combat first, then /dui worldtest again." end
    if type(WorldFrame) ~= "table" then return "worldtest: this client has no WorldFrame." end
    running = true
    local out, shotsBefore = {}, shots
    out[1] = "Daylight UI worldtest"
    showSquares(true)
    local marked, refused = 0, 0
    if R and R.Mark then marked, refused = R.Mark() end
    -- Each step starts the next, so they can never run out of order.
    local function finish()
        showUI()
        showSquares(false)
        running = nil
        out[#out + 1] = string.format("Plates marked %d (refused %d), screenshots saved %d", marked or 0,
            refused or 0, shots - shotsBefore)
        if R and R.World then
            for _, line in ipairs(R.World()) do out[#out + 1] = line end
        end
        if R and R.LogLines then
            out[#out + 1] = "What happened before:"
            for _, line in ipairs(R.LogLines()) do out[#out + 1] = line end
        end
        local text = R and R.Printable and R.Printable(table.concat(out, "\n"), R.REPORT_MAX) or table.concat(out, "\n")
        W.lastReport = text
        if DUI.Profiles and DUI.Profiles.ShowText then
            DUI.Profiles.ShowText(L["worldtest"], L["Copy this and send it with the two screenshots"], text)
        end
        DUI.Print(L["worldtest: done. Send the text in the box and the two newest screenshots (Screenshots folder), then /reload."])
    end
    C_Timer.After(W.SHOT_AT, function()
        readouts("With the UI shown:", out)
        shoot()
        C_Timer.After(W.HIDE_AT - W.SHOT_AT, function()
            if InCombatLockdown() then
                out[#out + 1] = "UIParent not hidden: a fight started."
                return finish()
            end
            UIParent:Hide()
            C_Timer.After(W.SHOT2_AT - W.HIDE_AT, function()
                readouts("With UIParent hidden:", out)
                shoot()
                C_Timer.After(W.SHOW_AT - W.SHOT2_AT, finish)
            end)
        end)
    end)
    return "worldtest: hold still for 5 seconds. Five squares go up, the UI hides for a moment, and two screenshots are taken."
end

DUI.RegisterCommand("worldtest", function() DUI.Print(W.Run()) end,
    function() return L["/dui worldtest - run while nameplates are invisible, and send us the box and the two screenshots"] end)
