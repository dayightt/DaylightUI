-- /dui taint lists which of the game's own values DaylightUI has tainted.
-- The client remembers who wrote each value. When the game's code reads a
-- value written by addon code, it runs tainted, which later shows up as
-- blocked actions and secret-value errors in combat. This finds the taint at
-- its source, before a fight does. It reads keys only, never values, since a
-- value may be secret.

local _, DUI = ...
local L = DUI.L
local Taint = {}
DUI.Taint = Taint

local OURS = "^DaylightUI"
-- Names every addon writes into the game's tables on purpose.
local EXPECTED = { "^SLASH_", "^BINDING_", "DAYLIGHTUI", "^DaylightUI", "^DUI" }
-- Game tables (not frames) worth checking.
Taint.TABLES = { "ChatTypeInfo", "UISpecialFrames", "StaticPopupDialogs", "EventRegistry", "ObjectiveTrackerManager" }
-- Fields of those tables a module writes on purpose, { [table] = { [key] = true } }.
-- The quest tracker empties three of ObjectiveTrackerManager's.
Taint.KNOWN = {}

local function expected(key)
    if type(key) ~= "string" then return true end
    for _, p in ipairs(EXPECTED) do if key:find(p) then return true end end
    return false
end

local function ourMark(t, k)
    local ok, secure, by = pcall(issecurevariable, t, k)
    if ok and not secure and type(by) == "string" and by:find(OURS) then return by end
end

local function scan(label, t, out)
    local known = Taint.KNOWN[label] or {}
    pcall(function()
        for k in pairs(t) do
            if not expected(k) and not known[k] then
                local by = ourMark(t, k)
                if by then out[#out + 1] = label .. "." .. k .. "  (" .. by .. ")" end
            end
        end
    end)
end

-- A game frame: its global name is the game's, or the game wrote at least one
-- of its fields. Our own frames (even built from game templates) are tainted
-- all over as expected, so they're skipped.
local function gameFrame(f)
    if f.IsForbidden and f:IsForbidden() then return false end
    local name = f.GetName and f:GetName()
    if type(name) == "string" then
        if name:find(OURS) then return false end
        if issecurevariable(name) then return true end
    end
    for k in pairs(f) do
        if type(k) == "string" and issecurevariable(f, k) then return true end
    end
    return false
end

-- Client-made buttons and containers inside our frames (buff buttons, bag
-- slots, plate aura containers) carry the client's fields and pass gameFrame,
-- but no game code reads ours on them. Walk up to the nearest named frame or
-- anonymous frame of ours. A frame the game named (one we borrow into our
-- holders) still counts as the game's.
local function insideOurs(f)
    local own = f.GetName and f:GetName()
    if type(own) == "string" and issecurevariable(own) then return false end
    local p = f.GetParent and f:GetParent()
    while p do
        if p.IsForbidden and p:IsForbidden() then return false end
        local name = p.GetName and p:GetName()
        if type(name) == "string" then
            if name:find(OURS) then return true end
            if issecurevariable(name) then return false end
        elseif not gameFrame(p) then
            return true
        end
        p = p.GetParent and p:GetParent()
    end
    return false
end

-- A frame's display name. Some game frames return a secret debug name (aura
-- buttons), which can't be a table key or concatenated, so use the plain name
-- or "?".
local function plainName(f, method)
    if type(f[method]) ~= "function" then return nil end
    local v = f[method](f)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return type(v) == "string" and v or nil
end

local function frameLabel(f)
    return plainName(f, "GetDebugName") or plainName(f, "GetName") or "?"
end

function Taint.Scan()
    local out = {}
    if type(issecurevariable) ~= "function" then return out, "this client has no issecurevariable" end
    for k in pairs(_G) do
        if not expected(k) then
            local ok, secure, by = pcall(issecurevariable, k)
            if ok and not secure and type(by) == "string" and by:find(OURS) then
                out[#out + 1] = k .. "  (" .. by .. ")"
            end
        end
    end
    local f = EnumerateFrames()
    while f do
        local ok, game = pcall(gameFrame, f)
        if ok and game then
            local ok2, ours = pcall(insideOurs, f)
            game = not (ok2 and ours)
        end
        if ok and game then
            scan(frameLabel(f), f, out)
        end
        f = EnumerateFrames(f)
    end
    for _, name in ipairs(Taint.TABLES) do
        if type(_G[name]) == "table" then scan(name, _G[name], out) end
    end
    table.sort(out)
    return out
end

function Taint.Report(quiet)
    local out, err = Taint.Scan()
    if err then DUI.Print(string.format(L["Taint: %s"], err)); return end
    if #out == 0 then
        if not quiet then DUI.Print(L["Taint: nothing of the game's is marked by DaylightUI."]) end
        return
    end
    DUI.Print(string.format(quiet and L["Taint: %d of the game's values are marked by DaylightUI (/dui taint for the list)."]
        or L["Taint: %d of the game's values are marked by DaylightUI:"], #out))
    if quiet then return end
    for i = 1, math.min(#out, 30) do DUI.Print("  " .. out[i]) end
    if #out > 30 then DUI.Print("  " .. string.format(L["... and %d more"], #out - 30)) end
end

DUI.RegisterCommand("taint", function() Taint.Report(false) end,
    L["/dui taint - the game's values DaylightUI has marked (for tracking down blocked actions)"])

-- With the taint log on (/console taintLog 1), check once after login or a
-- reload so taint shows up before a fight turns it into an error.
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
    if not (isLogin or isReload) then return end
    if type(GetCVar) ~= "function" or (tonumber(GetCVar("taintLog")) or 0) == 0 then return end
    C_Timer.After(5, function() DUI.SafeCall(Taint.Report, true) end)
end)
