-- Scans source for nil comparisons on values that may be secret. The client
-- throws on `== nil` / `~= nil` (and on truthiness) against a secret value,
-- and plain Lua can't be made to reproduce that through the stub, so this
-- checks the source text directly instead of exercising it at runtime.

local function readLines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end

T.test("CastBar.lua has no bare nil comparisons", function()
    local path = "DaylightUI_UnitFrames/CastBar.lua"
    local lines = readLines(path)
    for i, line in ipairs(lines) do
        if string.find(line, "== nil", 1, true) or string.find(line, "~= nil", 1, true) then
            error(string.format("%s:%d: bare nil comparison: %s", path, i, line))
        end
    end
end)

-- The fake game's automatic secrets (tests/secret_api.lua): every faked
-- function the API docs mark secret returns secrets while its condition holds.
local stub = require("stub")

T.test("the game's API docs are here: the fake game knows which values are secret", function()
    stub.Load()
    local n = 0
    for _ in pairs(stub.secretApi or {}) do n = n + 1 end
    T.truthy(n > 100, "no secret list: run py tools/fetch_blizzard.py (it fetches tests/blizzard/api/)")
end)

-- Seen in game: UnitHealth ("SecretReturns") is secret out of combat too.
-- UnitHealthMax is secret only under restrictions.
T.test("health is secret always; max health only in combat and in a battleground", function()
    stub.Load()
    stub.units = { player = { name = "Me", class = "PRIEST", health = 50, maxHealth = 100 } }
    T.truthy(issecretvalue(UnitHealth("player")), "out of combat")
    T.falsy(issecretvalue(UnitHealthMax("player")))
    stub.EnterCombat()
    T.truthy(issecretvalue(UnitHealthMax("player")), "in combat")
    stub.LeaveCombat()
    T.falsy(issecretvalue(UnitHealthMax("player")))
    stub.SetRestriction("PvPMatch", true)
    T.truthy(issecretvalue(UnitHealthMax("player")), "in a battleground, between fights")
end)

T.test("in a battleground an enemy player's class is secret, yours isn't", function()
    stub.Load()
    stub.units = { player = { name = "Me", class = "PRIEST" },
                   target = { name = "Them", class = "ROGUE", isPlayer = true, reaction = 2 } }
    stub.SetRestriction("PvPMatch", true)
    T.falsy(issecretvalue((UnitClass("player"))))
    T.truthy(issecretvalue((select(2, UnitClass("target")))))
end)

T.test("an aura's fields are secret in combat", function()
    stub.Load()
    stub.SetAuras("player", "HELPFUL", { { name = "Shield", spellId = 17, auraInstanceID = 5 } })
    stub.EnterCombat()
    local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
    T.truthy(type(a) == "table", "the table itself is plain")
    T.truthy(issecretvalue(a.name) and issecretvalue(a.spellId))
end)

-- Event payloads (the docs' event flags): addon handlers get them as secrets
-- while the condition holds; the client still routes unit events by the real unit.
T.test("event payloads go secret for addon handlers: UNIT_AURA under restrictions, whispers in chat lockdown", function()
    local DUI = stub.Load()
    local got = {}
    DUI.RegisterEvent("UNIT_AURA", function(_, unit, info) got.unit, got.info = unit, info end)
    DUI.RegisterEvent("CHAT_MSG_WHISPER", function(_, text) got.text = text end)
    DUI.RegisterEvent("UNIT_SPELLCAST_START", function(_, unit, guid, id, bar) got.bar, got.id = bar, id end)
    stub.FireEvent("UNIT_AURA", "target", { isFullUpdate = true })
    T.eq(got.unit, "target", "plain out of combat")
    stub.EnterCombat()
    stub.FireEvent("UNIT_AURA", "target", { isFullUpdate = true })
    T.truthy(issecretvalue(got.unit), "the unit token in combat")
    T.truthy(type(got.info) == "table" and issecretvalue(got.info.isFullUpdate), "updateInfo's fields in combat")
    stub.FireEvent("UNIT_SPELLCAST_START", "target", "Cast-1", 133, 7)
    T.truthy(issecretvalue(got.id), "a cast's spell id in combat")
    T.eq(got.bar, 7, "castBarID is NeverSecret")
    stub.FireEvent("CHAT_MSG_WHISPER", "hi")
    T.eq(got.text, "hi", "chat is plain outside chat lockdown")
    stub.SetRestriction("Chat", true)
    stub.FireEvent("CHAT_MSG_WHISPER", "hi")
    T.truthy(issecretvalue(got.text), "chat lockdown")
    -- Handlers written in tests/ (the game's own code) still get plain values.
    local f, seen = CreateFrame("Frame"), nil
    f:RegisterEvent("UNIT_AURA")
    f:SetScript("OnEvent", function(_, _, unit) seen = unit end)
    stub.FireEvent("UNIT_AURA", "player", {})
    T.eq(seen, "player")
end)

-- Flags a value taken from a secret-returning function (local a = UnitHealth(u))
-- that is then truth-tested or compared in the same function without an
-- issecretvalue / isSecret / Plain() check first. type() is no check, since a
-- secret number's type is still "number". Plain Lua can't fail on these at
-- runtime, so the source is scanned. UnitClass and UnitName on "player" are
-- never secret and aren't tracked. Exceptions need a reason:
local SECRET_SCAN_ALLOW = {
    ['DaylightUI_UnitFrames/UnitFrames.lua|shown = class == "DRUID"'] =
        "the druid mana bar is on the player frame only (f.druidMana); your own class is never secret",
}

local function ourLuaFiles()
    local files = {}
    local p = io.popen('git ls-files "*.lua"')
    for f in p:lines() do
        if not (f:find("^tests/") or f:find("^tools/") or f:find("Libs/")) then files[#files + 1] = f end
    end
    p:close()
    return files
end

T.test("no value from a secret API is truth-tested or compared without a secret check (every file)", function()
    local SecretAPI = require("secret_api")
    if not next(SecretAPI.functions) then SecretAPI.Load() end
    local api = SecretAPI.functions
    local function esc(s) return (s:gsub("%p", "%%%0")) end
    local found, tracked = {}, 0
    for _, path in ipairs(ourLuaFiles()) do
        local n, live = 0, {}
        for line in io.lines(path) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            if code:find("^function") or code:find("^local function") then live = {} end
            local names, call, arg = code:match("^%s*local%s+([%w_,%s]+)=%s*([%w_%.]+)%(%s*([^,%)]*)")
            if names and api[call] and not (api[call].when == "identity" and arg:match('^"player"$')) then
                for name in names:gmatch("[%w_]+") do
                    if name ~= "_" then live[name] = n; tracked = tracked + 1 end
                end
            end
            for name, from in pairs(live) do
                local e = esc(name)
                if code:find("issecretvalue%(%s*" .. e .. "%s*%)") or code:find("isSecret%(%s*" .. e .. "%s*%)")
                    or code:find("Plain%(%s*" .. e) then
                    live[name] = nil
                elseif n > from and (code:find("if%s+not%s+" .. e .. "%f[^%w_]") or code:find("if%s+" .. e .. "%s+then")
                    or code:find("elseif%s+" .. e .. "%s+then") or code:find("[^%w_%.]" .. e .. "%s*[=~]=")
                    or code:find("[=~]=%s*" .. e .. "%f[^%w_]") or code:find("[^%w_%.]" .. e .. "%s+and%f[^%w_]")
                    or code:find("[^%w_%.]" .. e .. "%s+or%f[^%w_]") or code:find("[^%w_%.]" .. e .. "%s*[<>]")) then
                    local key = path .. "|" .. code:gsub("^%s+", ""):gsub("%s+$", "")
                    if not SECRET_SCAN_ALLOW[key] then
                        found[#found + 1] = string.format("%s:%d: %s (from line %d)", path, n, code:gsub("^%s+", ""), from)
                    end
                end
            end
        end
    end
    T.truthy(tracked > 20, "the scan went hollow (" .. tracked .. " values tracked): is tests/blizzard/api/ there?")
    T.eq(#found, 0, "\n  " .. table.concat(found, "\n  "))
end)

-- In the client a secret string's type() is still "string", so a type check
-- doesn't protect it and any compare errors ("attempt to compare local 'text'
-- (a secret string value ...)"). The stub's secrets are tables, where `x ~= ""`
-- just reads true, so this scans the source. The secret check must come before
-- the value's first compare on its line.
T.test("a secret check comes before the value is compared on the same line (every file)", function()
    local found = {}
    for _, path in ipairs(ourLuaFiles()) do
        local n = 0
        for line in io.lines(path) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            local from = 1
            while true do
                local s, e, name = code:find("issecretvalue%(%s*([%w_%.]+)%s*%)", from)
                if not s then break end
                local before, x = code:sub(1, s - 1), name:gsub("%p", "%%%0")
                if before:find("[^%w_%.]" .. x .. "%s*[=~<>]") or before:find("[=~<>]=?%s*" .. x .. "%f[^%w_]") then
                    found[#found + 1] = string.format("%s:%d: %s", path, n, (code:gsub("^%s+", "")))
                end
                from = e + 1
            end
        end
    end
    T.eq(#found, 0, "\n  " .. table.concat(found, "\n  "))
end)

T.test("UnitFrames.lua guards every nil comparison with isSecret(", function()
    local path = "DaylightUI_UnitFrames/UnitFrames.lua"
    local lines = readLines(path)
    for i, line in ipairs(lines) do
        if string.find(line, "== nil", 1, true) or string.find(line, "~= nil", 1, true) then
            if not string.find(line, "isSecret(", 1, true) then
                error(string.format("%s:%d: unguarded nil comparison: %s", path, i, line))
            end
        end
    end
end)

-- SecretWhenUnitSpellCastRestricted (game docs): cast info is secret only
-- when the unit isn't the player or their pet. The handler is built as if it
-- were in an addon file, so the fake game hands it the payload it would get.
T.test("your own casts stay plain under restrictions, a mob's go secret", function()
    local stub = require("stub")
    stub.Load{}
    local got = {}
    local handler = loadstring("local got = ... return function(_, _, unit, guid, id) got[#got + 1] = { unit, guid, id } end",
        "@DaylightUI/CastProbe.lua")(got)
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    f:SetScript("OnEvent", handler)
    stub.EnterCombat()
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
    stub.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-2", 133)
    stub.LeaveCombat()
    T.eq(got[1][3], 172, "the player's spell id is plain")
    T.falsy(issecretvalue(got[1][2]), "the player's cast GUID is plain")
    T.truthy(issecretvalue(got[2][3]), "a mob's spell id is secret")
end)

T.test("UnitGUID and spell descriptions come from the fake world", function()
    local stub = require("stub")
    stub.Load{ before = function()
        stub.units.target = { name = "Kobold", reaction = 2, guid = "Creature-1" }
        stub.spells = { [172] = { name = "Corruption", desc = "Corrupts the target, causing 40 Shadow damage over 12 sec." } }
    end }
    T.eq(UnitGUID("target"), "Creature-1")
    T.eq(C_Spell.GetSpellName(172), "Corruption")
    T.eq(C_Spell.GetSpellDescription(172), "Corrupts the target, causing 40 Shadow damage over 12 sec.")
end)

-- `type(x) == "string" and x ~= "" and not issecretvalue(x)` compares the
-- secret before the check (this happened in Tooltip.lua's PaintSpell). The
-- fake game's secrets are tables, so only a scan catches the order: on a line
-- that checks issecretvalue(x), nothing before the check may compare or test x.
T.test("a secret check comes before any compare of the same value on its line (every file)", function()
    local found = {}
    for _, path in ipairs(ourLuaFiles()) do
        local n = 0
        for line in io.lines(path) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            for name in code:gmatch("issecretvalue%(%s*([%w_]+)%s*%)") do
                local at = code:find("issecretvalue%(%s*" .. name .. "%s*%)")
                local before = code:sub(1, at - 1)
                local e = name:gsub("%p", "%%%0")
                if before:find("%f[%w_]" .. e .. "%s*[=~<>]=?%s*[^=]") or before:find("[=~]=%s*" .. e .. "%f[^%w_]")
                    or before:find("%f[%w_]" .. e .. ":find") or before:find("#" .. e .. "%f[^%w_]") then
                    found[#found + 1] = string.format("%s:%d: %s", path, n, (code:gsub("^%s+", "")))
                end
            end
        end
    end
    T.eq(#found, 0, "\n  " .. table.concat(found, "\n  "))
end)
