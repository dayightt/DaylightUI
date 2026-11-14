-- Namespace, output, client events, internal callbacks, the after-combat
-- queue and the /dui command. The module registry and settings access are
-- further down.

local ADDON_NAME, DUI = ...
local L = DUI.L -- Locales/Locales.lua, loaded first
_G.DaylightUI = DUI

DUI.ADDON_NAME = ADDON_NAME

-- What the core files define. If one is missing at login (an update caught
-- halfway) a single line is printed. tests/test_guards.lua keeps this in sync.
DUI.CORE_PARTS = { "DB", "Pixel", "Style", "Tips", "GameFonts", "DamageText", "Motion", "Sound", "Pad", "Media", "Health", "Threat", "Interrupt", "Spots", "Dots", "PrivateAuras", "Taint", "BugReport", "Gradients", "Movers",
    "GameMovers", "PTRButton", "QuestieAside", "PrettyAside", "OpenMap", "CombatText", "Fade", "FadeUpgrade", "EditMode", "Options", "OptionsTheme", "Widgets", "SampleStrip",
    "OptionsNav", "OptionsResults", "OptionsPanel", "Installer", "InstallerDraft", "InstallerPages", "InstallerCards",
    "InstallerUI", "InstallerSteps", "Profiles", "Alts", "Plugins", "APIReport", "Donators", "Notes", "TestBox", "Win", "Tour" }
DUI.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"
DUI.MEDIA = "Interface\\AddOns\\DaylightUI\\Media\\"

-- Text colored letter by letter along the logo's sweep: blue, purple, pink,
-- orange (same stops as Style.GRADIENT_FILE). Per letter rather than per
-- byte, so other alphabets (zone names) stay intact.
local SWEEP = { { 30, 144, 255 }, { 162, 94, 199 }, { 230, 90, 114 }, { 255, 154, 31 } }

function DUI.GradientText(text)
    local chars, out = {}, {}
    for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = c end
    local n = #chars
    for i = 1, n do
        local t = n > 1 and (i - 1) / (n - 1) * (#SWEEP - 1) or 0
        local k = math.min(math.floor(t) + 1, #SWEEP - 1)
        local f, a, b = t - (k - 1), SWEEP[k], SWEEP[k + 1]
        out[i] = string.format("|cff%02x%02x%02x%s", a[1] + (b[1] - a[1]) * f + 0.5,
            a[2] + (b[2] - a[2]) * f + 0.5, a[3] + (b[3] - a[3]) * f + 0.5, chars[i])
    end
    return table.concat(out) .. "|r"
end

-- Aura-style time left in whole units, the largest that fits ("55s", "3m").
-- Shared by the buff bar and totem timers. Nothing under a second, like the
-- aura buttons' own text (Style.DURATION_STEPS), since "0s" reads as ended.
function DUI.FormatTime(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 1 then return "" end
    if seconds < 60 then return string.format("%ds", math.floor(seconds)) end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    if seconds < 86400 then return string.format("%dh", math.floor(seconds / 3600)) end
    return string.format("%dd", math.floor(seconds / 86400))
end

-- A clock in minutes and seconds (178 -> "2:58"), seconds floored. Returns ""
-- for nil, a secret or a negative number. Round first if you want rounding.
function DUI.FormatClock(seconds)
    if type(seconds) ~= "number" or (issecretvalue and issecretvalue(seconds)) or seconds < 0 then return "" end
    seconds = math.floor(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- A whole number with the client's thousands separator (1234567 -> "1,234,567").
local function thousands(n)
    local fn = FormatLargeNumber or BreakUpLargeNumbers
    if type(fn) == "function" then
        local ok, s = pcall(fn, n)
        if ok and type(s) == "string" then return s end
    end
    local s, k = tostring(n), 0
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
end
DUI.Thousands = thousands

-- An inline coin as tall as the text. The gap before it comes from the art
-- (texture coords -4..60 of the 64 px file, which moves the coin's own
-- transparent edge to the left), never from an x offset. The client draws an
-- offset but leaves it out of the text's width, so right-aligned money (the
-- bag footer) had its last coin hanging past the edge.
function DUI.CoinIcon(kind)
    return "|T" .. DUI.MEDIA .. "coin-" .. kind .. ".png:0:0:0:0:64:64:-4:60:0:64|t"
end
local function coinPart(n, kind) return n .. DUI.CoinIcon(kind) end

-- The game's colorblind mode: its setting, or the old global some clients still set.
local function colorblind()
    if ENABLE_COLORBLIND_MODE == "1" then return true end
    if type(C_CVar) == "table" and type(C_CVar.GetCVarBool) == "function" then
        local ok, on = pcall(C_CVar.GetCVarBool, "colorblindMode")
        return ok and on == true
    end
    return false
end

-- Money in copper with our own inline coins, laid out like the game's
-- GetMoneyString(amount, true): "1,234g 5s 6c", zero parts left out, just
-- copper for zero. Nil, negative or non-numbers count as 0. With the game's
-- colorblind mode on, the game's own text version is used instead. A secret
-- amount can't be split into coins (that's math), so it returns empty text.
function DUI.MoneyString(amount)
    if issecretvalue and issecretvalue(amount) then return "" end
    amount = (type(amount) == "number" and amount > 0) and math.floor(amount) or 0
    if colorblind() and type(GetMoneyString) == "function" then
        local ok, s = pcall(GetMoneyString, amount, true)
        if ok and type(s) == "string" then return s end
    end
    local gold, silver, copper = math.floor(amount / 10000), math.floor(amount / 100) % 100, amount % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = coinPart(thousands(gold), "gold") end
    if silver > 0 then parts[#parts + 1] = coinPart(silver, "silver") end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = coinPart(copper, "copper") end
    return table.concat(parts, " ")
end

local PRINT_LABEL =DUI.GradientText("DaylightUI") .. ":"

function DUI.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PRINT_LABEL .. " " .. tostring(msg))
end

-- Another addon replaces the same part of the UI. Say so once so the player
-- knows to turn one of them off. what: "frames", "action bars"...
local warnedAbout = {}

function DUI.WarnIfLoaded(addon, label, what)
    if warnedAbout[addon] then return end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) then
        warnedAbout[addon] = true
        DUI.Print(string.format(L["%s is also loaded. Both replace the same %s; disable one of them."], label, L[what]))
    end
end

-- A unit's name for our frames. With the Last names setting on, a player shows
-- first and last name ("Bone Money"; on this client the second name value is
-- a surname, not a realm). A secret name (in combat, in some places) can't be
-- concatenated, so it's returned as the first name alone, as the game gives it.
-- Each element has its own switch (general.lastNames.<element>). element is
-- passed for nameplates and tooltips, otherwise derived from the unit token
-- (party1 -> "party", raid7 -> "raid", boss2 -> "boss").
-- Total RP 3 (totalRP3 3.5.4, Core/Player.lua): a player with a roleplay
-- profile (not the default one, whose id ends in "*") shows the name from it,
-- first or first and last by the same switch. Only through its public calls,
-- each in a pcall, and a secret name never reaches it. Its Player objects
-- hold no state, so one per character is cached.
local rpPlayers = {}
local function plainString(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "string" and v ~= "" and v or nil
end
local function roleplayName(unit, full)
    local TRP = AddOn_TotalRP3
    if type(TRP) ~= "table" or type(TRP.Player) ~= "table" or type(TRP3_NameUtil) ~= "table" or type(TRP3_API) ~= "table" then return nil end
    if DUI.DB.General().rpNames == false then return nil end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or isPlayer ~= true then return nil end
    local okI, id = pcall(TRP3_NameUtil.GetQualifiedName, unit)
    id = okI and plainString(id) or nil
    if not id then return nil end
    local ok, name = pcall(function()
        local reg, prof = TRP3_API.register, TRP3_API.profile
        local player = rpPlayers[id]
        if not player then
            local me = TRP.Player.GetCurrentUser and TRP.Player.GetCurrentUser()
            if not (me and me.GetCharacterID and me:GetCharacterID() == id) and not (reg and reg.isUnitIDKnown(id)) then return nil end
            player = TRP.Player.CreateFromCharacterID(id)
            rpPlayers[id] = player
        end
        if prof and prof.isDefaultProfile(player:GetProfileID()) then return nil end
        if full then return player:GetRoleplayingName() end
        return player:GetFirstName() or player:GetRoleplayingName()
    end)
    return ok and plainString(name) or nil
end

-- New data from Total RP 3 (someone's profile arrived, you switched yours).
-- Frames are told at most once a second (NamesChanged), not per message.
local namesSoon = false
function DUI.RoleplayNamesChanged()
    if namesSoon then return end
    namesSoon = true
    C_Timer.After(1, function()
        namesSoon = false
        DUI.Fire("NamesChanged")
    end)
end

function DUI.UnitName(unit, element)
    if type(UnitFullName) ~= "function" then return UnitName(unit) end
    local first, last = UnitFullName(unit)
    element = element or (type(unit) == "string" and unit:match("^(%a+)%d*$")) or unit
    local on = DUI.DB.General().lastNames
    local full = type(on) == "table" and on[element] == true
    if plainString(first) then
        local rp = roleplayName(unit, full)
        if rp then return rp end
    end
    if not full or type(last) ~= "string" then return first end
    if issecretvalue and (issecretvalue(first) or issecretvalue(last)) then return first end
    if type(first) ~= "string" or last == "" then return first end
    return first .. " " .. last
end

-- How hard a unit is for you, as { r, g, b }, the way the game's own target
-- frame does it: the server's answer for the unit
-- (C_PlayerInfo.GetContentDifficultyCreatureForPlayer, then
-- GetDifficultyColor). GetCreatureDifficultyColor(level) is retail's level
-- math (it grays out anything past the quest trivial range, so a level 42
-- saw a green 36 as gray) and is only used for samples with no unit. Nil
-- when neither answers.
function DUI.LevelColor(unit, level)
    if type(unit) == "string" and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer
        and type(GetDifficultyColor) == "function" then
        local ok, d = pcall(C_PlayerInfo.GetContentDifficultyCreatureForPlayer, unit)
        if ok and type(d) == "number" and not (issecretvalue and issecretvalue(d)) then
            local okC, c = pcall(GetDifficultyColor, d)
            if okC and type(c) == "table" then return c end
        end
    end
    if type(level) ~= "number" or (issecretvalue and issecretvalue(level))
        or type(GetCreatureDifficultyColor) ~= "function" then return nil end
    local ok, c = pcall(GetCreatureDifficultyColor, level)
    if ok and type(c) == "table" then return c end
    return nil
end

-- A piece of gear's item level (weapons and armor, not shirts or tabards).
-- Nil for anything else, or when not loaded yet. Shared by the tooltip and
-- the bags. Secret-safe: a secret answer counts as no answer.
DUI.LEVEL_CLASSES = { [2] = true, [4] = true }
DUI.NO_LEVEL = { [""] = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BODY = true, INVTYPE_TABARD = true }
local function plainValue(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
function DUI.ItemLevel(link)
    if (type(link) ~= "string" and type(link) ~= "number") or not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local ok, _, _, _, equip, _, class = pcall(C_Item.GetItemInfoInstant, link)
    equip, class = ok and plainValue(equip) or nil, ok and plainValue(class) or nil
    if not DUI.LEVEL_CLASSES[class] or type(equip) ~= "string" or DUI.NO_LEVEL[equip] then return nil end
    local level
    if C_Item.GetDetailedItemLevelInfo then
        local okL, v = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if okL then level = plainValue(v) end
    end
    if type(level) ~= "number" and C_Item.GetItemInfo then
        local okI, _, _, _, v = pcall(C_Item.GetItemInfo, link)
        if okI then level = plainValue(v) end
    end
    if type(level) == "number" and level > 0 then return level end
    return nil
end

-- Runs fn; an error goes to the client's error handler instead of stopping
-- the caller. The stack is appended to the message, since a plain pcall
-- loses it and every report would point here. A secret message is passed on
-- as is (tostring on one may error). The stack itself may come back secret
-- once a secret was touched, and is dropped then so the report stays plain
-- and each error keeps its own count.
local function isSecretValue(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function withStack(err)
    if isSecretValue(err) then return err end
    if type(debugstack) == "function" then
        local stack = debugstack(2)
        if not isSecretValue(stack) then return tostring(err) .. "\n" .. stack end
    end
    return tostring(err)
end

-- One report per error, not a flood. The same message (its first line: file,
-- line and text) is reported the 1st, 10th, 100th and 1000th time in a
-- session, repeats with their count. A player hitting one in a battleground
-- sees it once, and BugSack still learns how often it happened.
local seen = {}
local REPORT_AT = { [1] = true, [10] = true, [100] = true, [1000] = true }

-- The session's errors for /dui bug, the latest last: one entry per message
-- (its first line) with its count and the stack it last came with. The oldest
-- drop off past ERROR_LOG_MAX.
DUI.ERROR_LOG_MAX = 20
local errorLog, errorIndex = {}, {}
local function remember(key, n, stack)
    local entry = errorIndex[key]
    if entry then
        for i = 1, #errorLog do
            if errorLog[i] == entry then table.remove(errorLog, i); break end
        end
    else
        entry = { text = key }
        errorIndex[key] = entry
    end
    entry.count, entry.stack, entry.at = n, stack, time()
    errorLog[#errorLog + 1] = entry
    if #errorLog > DUI.ERROR_LOG_MAX then errorIndex[table.remove(errorLog, 1).text] = nil end
end
function DUI.Errors() return errorLog end

local function report(ok, err, label)
    if not ok then
        -- A secret report can't be read for its first line, so those share one count
        -- and pass through unchanged.
        if isSecretValue(err) then
            local n = (seen["<secret>"] or 0) + 1
            seen["<secret>"] = n
            if REPORT_AT[n] then geterrorhandler()(err) end
            return ok
        end
        local text = tostring(err)
        -- Prefix a plugin's name so players report it to the right author.
        if label then text = label .. ": " .. text end
        local key = string.match(text, "^[^\n]*")
        local n = (seen[key] or 0) + 1
        seen[key] = n
        remember(key, n, string.sub(text, #key + 2))
        if REPORT_AT[n] then
            geterrorhandler()(n == 1 and text or ("(seen " .. n .. " times) " .. text))
        end
    end
    return ok
end

function DUI.SafeCall(fn, ...)
    return report(xpcall(fn, withStack, ...))
end

-- SafeCall with the report prefixed by label (a plugin's name).
function DUI.SafeCallAs(label, fn, ...)
    local ok, err = xpcall(fn, withStack, ...)
    return report(ok, err, label)
end

-- Calls a module's own function (OnEnable, OnSettingChanged, OnStyleChanged).
-- Errors from a plugin's module (DUI.RegisterPlugin) carry the plugin's name.
local function moduleCall(mod, fn, ...)
    if mod.pluginTitle then return DUI.SafeCallAs(mod.pluginTitle, fn, ...) end
    return DUI.SafeCall(fn, ...)
end

-- Client events: one hidden frame, handlers called with (event, ...).

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}
local lastHandlers = {} -- event -> handlers that run after all the others

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    for i = 1, #list do DUI.SafeCall(list[i], event, ...) end
    local tail = lastHandlers[event]
    if tail then
        for i = 1, #tail do DUI.SafeCall(tail[i], event, ...) end
    end
end)

-- Runs the handlers of a client event the client won't send for a change
-- made from code (UIParent:SetScale fires no UI_SCALE_CHANGED).
function DUI.RunEvent(event, ...)
    if eventHandlers[event] then eventFrame:GetScript("OnEvent")(eventFrame, event, ...) end
end

-- last: run after every other handler of the event, whenever those were
-- registered (the logout strip, so the others still see full settings).
function DUI.RegisterEvent(event, fn, last)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    if last then
        local tail = lastHandlers[event] or {}
        lastHandlers[event] = tail
        tail[#tail + 1] = fn
    else
        list[#list + 1] = fn
    end
end

-- Internal callbacks between core files and modules.

local callbacks = {}

function DUI.On(name, fn)
    local list = callbacks[name]
    if not list then list = {}; callbacks[name] = list end
    list[#list + 1] = fn
end

function DUI.Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do DUI.SafeCall(list[i], ...) end
end

-- Messages in the middle of the screen. The game's error frame
-- (UIErrorsMixin:TryDisplayMessage) skips every message type listed in its
-- global BLACK_LISTED_MESSAGE_TYPES, voice line included. Several of our
-- features hide types this way (QoL's quiet errors and error text, Quests'
-- progress lines). Each registers a claim here, so dropping one claim never
-- brings back a line another feature still draws. The game's own entries
-- are never written. A fallback claim loses to any other: the error text
-- claims every type and draws the ones nobody else wants. No hooks, and
-- nothing is read but the type id.

local claims = {} -- [type id] = { [owner] = "main" | "fallback" }
local written = {} -- [type id] = true for entries we wrote on the game's list
local listed -- the list `written` refers to

local function messageList()
    local t = _G.BLACK_LISTED_MESSAGE_TYPES
    if type(t) ~= "table" then return nil end
    if t ~= listed then listed, written = t, {} end
    return t
end

local function syncMessageType(id)
    local t = messageList()
    if not t then return end
    if claims[id] then
        if t[id] ~= true then
            t[id] = true
            written[id] = true
        end
    elseif written[id] then
        -- Removed rather than set to false: a value we wrote would make the game's
        -- handler run tainted for that message.
        t[id] = nil
        written[id] = nil
    end
end

local function plainId(id)
    return type(id) == "number" and not (issecretvalue and issecretvalue(id))
end

function DUI.ClaimMessageType(id, owner, fallback)
    if not plainId(id) then return end
    claims[id] = claims[id] or {}
    claims[id][owner] = fallback and "fallback" or "main"
    syncMessageType(id)
end

function DUI.ReleaseMessageType(id, owner)
    local c = plainId(id) and claims[id]
    if not c or not c[owner] then return end
    c[owner] = nil
    if not next(c) then claims[id] = nil end
    syncMessageType(id)
end

-- Who shows a type instead of the game's frame: "game" when the game hides it
-- itself, else a main claim, else the fallback. Nil means the game shows it.
function DUI.MessageTypeOwner(id)
    if not plainId(id) then return nil end
    local t = messageList()
    if t and t[id] == true and not written[id] then return "game" end
    local c = claims[id]
    if not c then return nil end
    local fallback
    for owner, kind in pairs(c) do
        if kind == "main" then return owner end
        fallback = owner
    end
    return fallback
end

-- The game briefly holds its messages back (UIErrorsMixin:GetMessagesSuppressed),
-- sound too, so whoever draws in its place does the same.
function DUI.GameMessagesSuppressed()
    local f = _G.UIErrorsFrame
    return type(f) == "table" and type(f.GetMessagesSuppressed) == "function" and f:GetMessagesSuppressed() == true
end

-- Plays the sound the game would play with a message (a voice line or a kit).
function DUI.PlayGameMessageSound(id)
    if not plainId(id) or type(GetGameMessageInfo) ~= "function" then return end
    local ok, _, kit, voice = pcall(GetGameMessageInfo, id)
    if not ok then return end
    if type(voice) == "number" and C_Sound and type(C_Sound.PlayVocalErrorSound) == "function" then
        pcall(C_Sound.PlayVocalErrorSound, voice)
    elseif type(kit) == "number" and type(PlaySound) == "function" then
        pcall(PlaySound, kit)
    end
end

-- One of our red error lines ("can't track more"). The error text draws it
-- when on, otherwise the game's frame does.
function DUI.ShowError(text)
    if type(DUI.errorText) == "function" and DUI.errorText(text) then return end
    local f = _G.UIErrorsFrame
    if type(f) == "table" and type(f.AddExternalErrorMessage) == "function" then f:AddExternalErrorMessage(text) end
end

-- The game's error frame is part of its base UI and loads before us. If a
-- client ever loads it later, apply the claims then.
DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= "Blizzard_UIErrorsFrame" then return end
    for id in pairs(claims) do syncMessageType(id) end
end)

-- After-combat queue. Protected work (anchoring, sizing, scale, attributes,
-- showing or hiding secure frames) goes through here. Out of combat it runs
-- now; in combat it waits for PLAYER_REGEN_ENABLED. A key makes a later call
-- replace an earlier queued one while keeping its place in the queue.

local queue, queuedIndex = {}, {}

function DUI.AfterCombat(fn, key)
    if not InCombatLockdown() then
        fn()
        return true
    end
    if key and queuedIndex[key] then
        queue[queuedIndex[key]] = fn
    else
        queue[#queue + 1] = fn
        if key then queuedIndex[key] = #queue end
    end
    return false
end

DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local pending = queue
    queue, queuedIndex = {}, {}
    for i = 1, #pending do DUI.SafeCall(pending[i]) end
end)

-- After-restrictions queue. In combat and under the client's addon
-- restrictions (boss encounter, keystone, PvP match, restricted map, even
-- between fights) auras are secret, and the client refuses any addon call on
-- an aura button it created or anything we made on it ("bad self"). Restyling
-- those goes through here: it runs now when nothing is restricted, otherwise
-- waits until every restriction lifts. Keys work as in AfterCombat. Chat
-- lockdown doesn't count.

local R, RS = Enum and Enum.AddOnRestrictionType, Enum and Enum.AddOnRestrictionState
local RA = C_RestrictedActions
local active = {} -- [restriction type] = true, from the event's payload
local held, heldIndex = {}, {}

local function restrictedNow()
    for _ in pairs(active) do return true end
    return false
end

function DUI.Restricted()
    return InCombatLockdown() or restrictedNow()
end

function DUI.AfterRestrictions(fn, key)
    if not DUI.Restricted() then
        fn()
        return true
    end
    if key and heldIndex[key] then
        held[heldIndex[key]] = fn
    else
        held[#held + 1] = fn
        if key then heldIndex[key] = #held end
    end
    return false
end

local function releaseHeld()
    if DUI.Restricted() or #held == 0 then return end
    local pending = held
    held, heldIndex = {}, {}
    for i = 1, #pending do DUI.SafeCall(pending[i]) end
end

-- Reads the client's state outside the restriction event (inside it the
-- client always answers false, so the event's payload is used there).
local function readRestrictions()
    if not (R and RA and RA.IsAddOnRestrictionActive) then return end
    for name, t in pairs(R) do
        if name ~= "Chat" then active[t] = RA.IsAddOnRestrictionActive(t) == true or nil end
    end
end

if R and RS and RA and RA.IsAddOnRestrictionActive then
    DUI.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, t, state)
        if t == R.Chat then return end
        active[t] = (state ~= RS.Inactive) or nil
        releaseHeld()
    end)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function() readRestrictions(); releaseHeld() end)
    -- A /reload in a battleground: modules build at PLAYER_LOGIN, before
    -- PLAYER_ENTERING_WORLD, so this must already be known (registered before them).
    DUI.RegisterEvent("PLAYER_LOGIN", readRestrictions)
end
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", releaseHeld)

-- /dui. Each part of the suite registers its own subcommands.

local commands, commandOrder = {}, {}

-- A typo prints only what a player needs. `/dui all` prints every command
-- (previews, diagnostics, dev tools). All of them run either way.
DUI.LISTED_COMMANDS = { [""] = true, unlock = true, test = true, leader = true }

function DUI.RegisterCommand(name, fn, help)
    commands[name] = { fn = fn, help = help }
    commandOrder[#commandOrder + 1] = name
end

-- Whether /dui <name> is taken (a plugin's word must not override a built-in one).
function DUI.HasCommand(name)
    return commands[string.lower(tostring(name))] ~= nil
end

local function printHelp(all)
    DUI.Print(L["Commands:"])
    for _, name in ipairs(commandOrder) do
        local help = commands[name].help
        if help and (all or DUI.LISTED_COMMANDS[name]) then DUI.Print("  " .. help) end
    end
    if not all then DUI.Print("  " .. L["/dui all - every command"]) end
end

function DUI.RunCommand(msg)
    local cmd, rest = string.match(msg or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    local entry = commands[cmd]
    if entry then
        entry.fn(rest)
        return
    end
    printHelp(cmd == "all")
end

SLASH_DAYLIGHTUI1 = "/dui"
SlashCmdList.DAYLIGHTUI = DUI.RunCommand

-- Reload shortcuts. Leave /rl alone if another addon already owns it.
if not (type(hash_SlashCmdList) == "table" and hash_SlashCmdList["/RL"]) then
    SLASH_DAYLIGHTUIRELOAD1 = "/rl"
    SLASH_DAYLIGHTUIRELOAD2 = "/reloadui"
    SlashCmdList.DAYLIGHTUIRELOAD = function() ReloadUI() end
end

-- Modules. A module registers at file load and is enabled at PLAYER_LOGIN
-- (or right away if it registers later) with its settings table.

local modules, moduleOrder = {}, {}

function DUI:RegisterModule(name, def)
    assert(type(name) == "string" and name ~= "", "module name required")
    assert(not modules[name], "module already registered: " .. name)
    def.name = name
    modules[name] = def
    moduleOrder[#moduleOrder + 1] = name
    if DUI.loggedIn then DUI.EnableModule(def) end
    return def
end

function DUI:GetModule(name) return modules[name] end

-- DaylightMogul's warehouse panel docks beside our bank window (its
-- Bridge/Bank.lua). Returns the frame while the Bags module is on and has
-- built it, else nil. Safe to call any time, never errors.
function DUI.BankWindow()
    local ok, f = pcall(function()
        local m = modules.Bags
        local bank = m and m.enabled and type(m.ns) == "table" and m.ns.Bank
        return type(bank) == "table" and bank.window or nil
    end)
    if ok and type(f) == "table" then return f end
    return nil
end

function DUI.Modules()
    local i = 0
    return function()
        i = i + 1
        local name = moduleOrder[i]
        if name then return name, modules[name] end
    end
end

-- A file missing from a module (an update caught halfway) would make every
-- call into it fail hundreds of times. Each module lists the parts its files
-- define, and with one missing it prints one line in chat and stays off.
function DUI.MissingParts(tbl, parts)
    local missing = {}
    for _, p in ipairs(parts or {}) do
        if tbl[p] == nil then missing[#missing + 1] = p end
    end
    return missing
end

local function restartLine(label, missing)
    DUI.Print(string.format(L["%s is missing %s: /reload, or restart the game if it stays."],
        label, table.concat(missing, ", ")))
end

function DUI.EnableModule(mod)
    if mod.enabled then return end
    if mod.ns and mod.parts then
        local missing = DUI.MissingParts(mod.ns, mod.parts)
        if #missing > 0 then return restartLine(mod.label or mod.name, missing) end
    end
    -- A plugin's module (def.plugin, Plugins.lua) stays off while its plugin
    -- does, and its pages go in the plugin's own section.
    if mod.plugin ~= nil and DUI.Plugins and not DUI.Plugins.Adopt(mod) then return end
    -- Settings plugins asked to add to this module (DaylightUI.API's AddDefaults).
    if DUI.APIReport and DUI.APIReport.ApplyDefaults then DUI.APIReport.ApplyDefaults(mod) end
    mod.db = DUI.DB.Module(mod.name, mod.defaults or {})
    mod.enabled = true
    if mod.options and DUI.Options then DUI.Options.RegisterModule(mod) end
    if mod.OnEnable then moduleCall(mod, mod.OnEnable, mod, mod.db) end
end

-- Settings access. scope is "general" or a module name; path is dotted.

local function scopeTable(scope)
    if scope == "general" then return DUI.DB.General() end
    local mod = modules[scope]
    if not (mod and mod.enabled) then return nil end
    DUI.DB.Root()
    return mod.db
end

function DUI:Get(scope, path)
    local t = scopeTable(scope)
    return t and DUI.DB.GetPath(t, path)
end

-- Repaints the core first ("RepaintCore": pixel math, then shells and fonts,
-- in file load order), then every module, then any other listeners. At most
-- once a frame, since dragging a slider changes the style on every step and
-- each repaint touches every frame.
local stylePending = false
function DUI.NotifyStyleChanged()
    if stylePending then return end
    stylePending = true
    C_Timer.After(0, function()
        stylePending = false
        DUI.RepaintStyle()
    end)
end

function DUI.RepaintStyle()
    DUI.AfterCombat(function()
        DUI.Fire("RepaintCore")
        for _, mod in DUI.Modules() do
            if mod.enabled and mod.OnStyleChanged then moduleCall(mod, mod.OnStyleChanged, mod) end
        end
        DUI.Fire("StyleChanged")
    end, "style")
end

-- General settings that don't trigger a repaint. Combat text reads its own on
-- every line, and repainting every frame per slider step lags badly. Anything
-- waiting on the repaint (the options window) handles it itself.
function DUI.NoRepaint(path) return path:sub(1, 4) == "sct." end

function DUI:Set(scope, path, value)
    local t = scopeTable(scope)
    if not t then return false end
    DUI.DB.SetPath(t, path, value)
    if scope == "general" then
        if not DUI.NoRepaint(path) then DUI.NotifyStyleChanged() end
    else
        local mod = modules[scope]
        if mod.OnSettingChanged then
            DUI.AfterCombat(function() moduleCall(mod, mod.OnSettingChanged, mod, path, value) end,
                "setting:" .. scope .. ":" .. path)
        end
    end
    DUI.Fire("SettingChanged", scope, path, value)
    return true
end

-- Test mode: modules show their frames with sample data while it's on.
-- Showing frames without their units is protected, so it only starts out of
-- combat, and combat ends it.

DUI.testMode = false

function DUI.SetTestMode(on)
    on = on and true or false
    if on == DUI.testMode then return true end
    if on and InCombatLockdown() then
        DUI.Print(L["Can't preview frames during combat."])
        return false
    end
    DUI.testMode = on
    DUI.Fire("TestModeChanged", on)
    return true
end

DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if DUI.testMode then DUI.SetTestMode(false) end
end)

-- "/dui test raid" shows the sample group as a 40-player raid, even where
-- the raid tiles stand in for the party.
DUI.RegisterCommand("test", function(rest)
    local raid = string.lower(rest or "") == "raid"
    if DUI.testMode and raid ~= (DUI.testRaid == true) then
        DUI.SetTestMode(false) -- switching samples: off, then on again
    end
    DUI.testRaid = raid
    DUI.SetTestMode(not DUI.testMode)
end, L["/dui test - preview every frame with sample units (/dui test raid: with a raid of forty)"])

-- Lifecycle

DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == ADDON_NAME then
        DUI.DB.Init()
        -- Before any module builds its text.
        DUI.Style.PickFont()
    end
end)

-- Pass Total RP 3 updates on to the frames (DUI.RoleplayNamesChanged, used by DUI.UnitName).
DUI.RegisterEvent("PLAYER_LOGIN", function()
    if type(TRP3_API) ~= "table" or type(TRP3_API.RegisterCallback) ~= "function" or type(TRP3_Addon) ~= "table" then return end
    local events = TRP3_Addon.Events or {}
    for _, e in ipairs({ "REGISTER_DATA_UPDATED", "REGISTER_PROFILES_LOADED", "REGISTER_PROFILE_DELETED" }) do
        if events[e] then pcall(TRP3_API.RegisterCallback, TRP3_Addon, events[e], DUI.RoleplayNamesChanged) end
    end
end)

DUI.RegisterEvent("PLAYER_LOGIN", function()
    -- The talent set is known now, so pick its profile before anything is built.
    if DUI.DB.OnLogin() then DUI.Style.PickFont() end
    -- Migrate old fade settings before any module merges its defaults.
    if DUI.FadeUpgrade then DUI.SafeCall(DUI.FadeUpgrade.Run, DUI.DB.Active()) end
    local missing = DUI.MissingParts(DUI, DUI.CORE_PARTS)
    if #missing > 0 then restartLine("DaylightUI", missing) end
    DUI.loggedIn = true
    -- Each separately, so one failing can't keep the rest from starting.
    for _, mod in DUI.Modules() do DUI.SafeCall(DUI.EnableModule, mod) end
    DUI.Fire("Login")
    DUI.Print(string.format(L["version %s loaded. Type %s for options."], DUI.VERSION, DUI.GradientText("/dui")))
end)

-- Last, so every other logout handler (chat history...) still sees full settings.
DUI.RegisterEvent("PLAYER_LOGOUT", function() DUI.DB.OnLogout() end, true)

-- Update check. Addons can't reach the internet, so, like DBM and Details,
-- copies tell each other their version over hidden addon messages (guild and
-- group). On seeing a newer one, say so once per session.

local PREFIX = "DaylightUI"
local toldUpdate = false
local lastSent = {}

-- "0.5.3" -> { 0, 5, 3 }; nil for "dev" or anything else odd.
local function parseVersion(v)
    if type(v) ~= "string" or not v:match("^%d+[%.%d]*$") then return nil end
    local parts = {}
    for n in v:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
    return parts
end

-- True when version a is newer than version b.
function DUI.IsNewerVersion(a, b)
    local pa, pb = parseVersion(a), parseVersion(b)
    if not pa or not pb then return false end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

-- At most once a minute per channel so a busy roster doesn't spam.
local function sendVersion(channel)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local now = GetTime and GetTime() or 0
    if lastSent[channel] and now - lastSent[channel] < 60 then return end
    lastSent[channel] = now
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. DUI.VERSION, channel)
end

local function groupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function announce()
    if IsInGuild and IsInGuild() then sendVersion("GUILD") end
    local channel = groupChannel()
    if channel then sendVersion(channel) end
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    -- The guild roster isn't ready right at login.
    C_Timer.After(10, announce)
end)

DUI.RegisterEvent("GROUP_ROSTER_UPDATE", function()
    local channel = groupChannel()
    if channel then sendVersion(channel) end
end)

-- Channels a reply can go back on. A whisper or custom channel would need a
-- target the event doesn't provide.
local ANSWER_ON = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

DUI.RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(channel)) then return end
    local theirs = msg:match("^V:(.+)$")
    if not theirs then return end
    if DUI.IsNewerVersion(theirs, DUI.VERSION) then
        if not toldUpdate then
            toldUpdate = true
            DUI.Print(DUI.Win.Parts.Hex(DUI.Style.INK.WARN) .. string.format(L["has an update! Please update (version %s is out)."], theirs) .. "|r")
        end
    elseif DUI.IsNewerVersion(DUI.VERSION, theirs) and type(channel) == "string" and ANSWER_ON[channel] then
        -- They're behind, so reply and they learn about ours too.
        sendVersion(channel)
    end
end)

-- When the game blocks something DaylightUI tried ("Interface action failed
-- because of an AddOn"), report what, once per thing per session, so it can
-- be found and fixed.
local reportedBlock, reportedStack = {}, false
local function blocked(_, addon, fn)
    if type(addon) ~= "string" or string.sub(addon, 1, 10) ~= "DaylightUI" then return end
    local key = tostring(fn)
    if reportedBlock[key] then return end
    reportedBlock[key] = true
    remember(string.format("the game blocked %s (%s)", key, addon), 1)
    DUI.Print(string.format(L["the game blocked %s (%s). Please report this."], key, addon))
    -- Where it came from, for the first one only (the rest share the cause), and
    -- only with the dev addon loaded. Players get one line, not a wall of stack
    -- traces (Skins/Engine.lua's Broke does the same).
    local dev = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DaylightUI_Dev")
    if dev and not reportedStack and type(debugstack) == "function" then
        reportedStack = true
        DUI.Print(string.format(L["combat lockdown: %s. Called from:\n%s"], tostring(InCombatLockdown and InCombatLockdown()),
            tostring(debugstack(2, 8, 0))))
    end
end
DUI.RegisterEvent("ADDON_ACTION_BLOCKED", blocked)
DUI.RegisterEvent("ADDON_ACTION_FORBIDDEN", blocked)

-- The Quests module used to be able to hide the game's own quest areas on
-- the maps (the removed mapQuests.gameQuests, which set questPOI to 0 and
-- saved the player's value in DB.Root().questPOIWas), so restore it at login.
-- Its map marks and remembered quest givers were removed at the same time,
-- and their per-character lists (`DROPPED_QUEST_KEYS`) are cleared from every
-- character.
local DROPPED_QUEST_KEYS = { "questGiversSeen", "questPinsHidden", "questMarksHidden" }
DUI.RegisterEvent("PLAYER_LOGIN", function()
    local root = DUI.DB.Root()
    if type(root.characters) == "table" then
        for _, c in pairs(root.characters) do
            if type(c) == "table" then
                for _, k in ipairs(DROPPED_QUEST_KEYS) do c[k] = nil end
            end
        end
    end
    if root.questPOIWas == nil then return end
    if type(SetCVar) == "function" then SetCVar("questPOI", root.questPOIWas) end
    root.questPOIWas = nil
end)
