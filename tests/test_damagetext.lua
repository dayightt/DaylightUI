-- Damage numbers (DamageText.lua): the game's own numbers' font and motion
-- settings, the bundled display fonts, and the page's live sample.

local stub = require("stub")

-- The game's settings: defaults as the client knows them, with writes counted.
local function fakeCVars(defaults)
    local cvars, writes = {}, {}
    for k, v in pairs(defaults) do cvars[k] = v end
    _G.GetCVar = function(k) return cvars[k] end
    _G.SetCVar = function(k, v) cvars[k] = tostring(v); writes[#writes + 1] = k end
    _G.C_CVar = _G.C_CVar or {}
    _G.C_CVar.GetCVarDefault = function(k) return defaults[k] end
    return cvars, writes
end

-- What Forever has, checked in game: no WorldText* motion, only the _v2 names. The
-- size is WorldTextScale_v2 (found in a player's Config.wtf).
local DEFAULTS = {
    WorldTextScale_v2 = "1",
    floatingCombatTextCombatDamageDirectionalScale_v2 = "0", floatingCombatTextCombatDamageDirectionalOffset_v2 = "1",
    floatingCombatTextCombatDamage_v2 = "1", floatingCombatTextCombatHealing_v2 = "1",
    floatingCombatTextPetMeleeDamage_v2 = "1", floatingCombatTextPetSpellDamage_v2 = "1",
}
local SPREAD, START = "floatingCombatTextCombatDamageDirectionalScale_v2", "floatingCombatTextCombatDamageDirectionalOffset_v2"

local function clear()
    _G.GetCVar, _G.SetCVar, _G.DAMAGE_TEXT_FONT, _G.STANDARD_TEXT_FONT = nil, nil, nil, nil
    if _G.C_CVar then _G.C_CVar.GetCVarDefault = nil end
end

T.test("damage numbers: every bundled font is there and is TrueType", function()
    local DUI = stub.Load()
    local n = 0
    for _, key in ipairs(DUI.Style.FONT_ORDER) do
        local f = DUI.Style.FONTS[key]
        T.truthy(f, key)
        if f.file and f.file:find(DUI.MEDIA, 1, true) == 1 then
            local path = ("Media/" .. f.file:sub(#DUI.MEDIA + 1)):gsub("\\", "/")
            local h = io.open(path, "rb")
            T.truthy(h, "missing " .. path)
            local head = h:read(4)
            h:close()
            T.eq(head, "\0\1\0\0", path .. " must be TrueType (an OTTO font is silently refused)")
            n = n + 1
        end
    end
    T.truthy(n >= 56, "our 8 and the 48 display fonts")
    for _, key in ipairs(DUI.Style.FONT_PICKS) do T.truthy(DUI.Style.FONTS[key], key) end
end)

T.test("damage numbers: their own font, with or without game text", function()
    _G.STANDARD_TEXT_FONT, _G.DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF"
    local DUI = stub.Load()
    T.eq(DUI:Get("general", "damage.font"), "auto")
    T.eq(DAMAGE_TEXT_FONT, DUI.Style.FONTS.expressway.file, "untouched: the Appearance font, game text off")

    DUI:Set("general", "damage.font", "bangers")
    stub.RunTimers()
    T.eq(DAMAGE_TEXT_FONT, DUI.Style.FONTS.bangers.file, "picked without game text")
    T.eq(STANDARD_TEXT_FONT, "Fonts\\FRIZQT__.TTF", "the rest of the game's text stays")

    DUI:Set("general", "damage.font", "game")
    stub.RunTimers()
    T.eq(DAMAGE_TEXT_FONT, "Fonts\\FRIZQT__.TTF", "the game's own back")

    DUI:Set("general", "damage.font", "auto")
    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    stub.RunTimers()
    T.eq(DAMAGE_TEXT_FONT, DUI.Style.FONTS.fira.file, "auto follows game text")
    DUI:Set("general", "damage.font", "fredoka")
    stub.RunTimers()
    T.eq(DAMAGE_TEXT_FONT, DUI.Style.FONTS.fredoka.file, "its own beats game text")
    DUI:Set("general", "gameText", false)
    DUI:Set("general", "damage.font", "auto")
    stub.RunTimers()
    T.eq(DAMAGE_TEXT_FONT, DUI.Style.FONTS.fira.file, "auto: the Appearance font without game text")
    DUI:Set("general", "font", "game")
    stub.RunTimers()
    T.eq(DAMAGE_TEXT_FONT, "Fonts\\FRIZQT__.TTF", "Appearance on Game font: the client's font")
    clear()
end)

T.test("damage numbers: an untouched player keeps their own game settings", function()
    local cvars, writes = fakeCVars(DEFAULTS)
    cvars[SPREAD] = "2"   -- set by the player in the game's console
    local DUI = stub.Load()
    stub.RunTimers()
    T.eq(#writes, 0, "nothing written at login")
    T.eq(DUI.DamageText.Preset(), "game")
    clear()
end)

T.test("damage numbers: a preset writes the game's spread settings, after combat", function()
    local cvars, writes = fakeCVars(DEFAULTS)
    local DUI = stub.Load()
    local DT = DUI.DamageText
    stub.EnterCombat()
    DT.SetPreset("punchy")
    stub.RunTimers()
    T.eq(#writes, 0, "waits for the fight to end")
    stub.LeaveCombat()
    stub.RunTimers()
    T.near(tonumber(cvars[SPREAD]), 3, 0.001, "flung out to the sides")
    T.near(tonumber(cvars[START]), 1.5, 0.001)
    T.eq(DT.Preset(), "punchy")
    T.eq(DUI.DB.Root().damageTextSet, true)

    DUI:Set("general", "damage.spread", 2.5)
    stub.RunTimers()
    T.eq(DT.Preset(), "custom", "a slider makes it custom")
    T.near(tonumber(cvars[SPREAD]), 2.5, 0.001)

    DT.SetPreset("game")
    stub.RunTimers()
    T.near(tonumber(cvars[SPREAD]), 0, 0.001, "straight up again, the game's own")
    T.near(tonumber(cvars[START]), 1, 0.001)
    T.isnil(DUI.DB.Root().damageTextSet, "and we stop writing")
    clear()
end)

T.test("damage numbers: the size slider writes the game's text scale, and a preset leaves it", function()
    local cvars = fakeCVars(DEFAULTS)
    local DUI = stub.Load()
    local DT = DUI.DamageText
    T.eq(DT.Has("size"), true)
    stub.EnterCombat()
    DUI:Set("general", "damage.size", 1.6)
    stub.RunTimers()
    T.eq(cvars.WorldTextScale_v2, "1", "waits for the fight to end")
    stub.LeaveCombat()
    stub.RunTimers()
    T.near(tonumber(cvars.WorldTextScale_v2), 1.6, 0.001, "bigger numbers")
    T.eq(DT.Preset(), "game", "size isn't part of a preset")

    DT.SetPreset("punchy")
    stub.RunTimers()
    T.near(tonumber(cvars.WorldTextScale_v2), 1.6, 0.001, "a preset keeps the size")
    T.near(DUI:Get("general", "damage.size"), 1.6, 0.001)

    local s = DT.Sample(UIParent)
    s.Refresh(400, 300)
    local step = s.frame:GetScript("OnUpdate")
    step(s.frame, 0.6)
    local size
    for _, r in ipairs({ s.frame:GetRegions() }) do
        if r:GetObjectType() == "FontString" and r:IsShown() then size = select(2, r:GetFont()) end
    end
    T.eq(size, math.floor(DT.SAMPLE_SIZE * 1.6 + 0.5), "the sample grows too")
    s.frame:Hide()
    clear()
end)

T.test("damage numbers: a client without the spread settings shows no motion rows and writes nothing", function()
    local d = {}
    for k, v in pairs(DEFAULTS) do d[k] = v end
    d[SPREAD], d[START], d.floatingCombatTextPetMeleeDamage_v2, d.floatingCombatTextPetSpellDamage_v2 = nil, nil, nil, nil
    local _, writes = fakeCVars(d)
    local DUI = stub.Load()
    local DT = DUI.DamageText
    T.falsy(DT.Has("spread"))
    DT.SetPreset("soft")
    stub.RunTimers()
    T.eq(#writes, 0, "no write to a missing setting")
    T.isnil(DT.Shown("pet"), "no pet switch")
    T.eq(DT.Shown("damage"), true)

    local page = DUI.Options.GetPage("damage")
    local get = function(k) return DUI:Get("general", k) end
    local seen = 0
    for _, g in ipairs(page.groups) do
        for _, item in ipairs(g.items) do
            if item.key == "damage.spread" or item.label == "Preset" then
                T.eq(item.hidden(get), true, item.label .. " hidden")
                seen = seen + 1
            end
        end
    end
    T.eq(seen, 2)
    clear()
end)

T.test("damage numbers: the show switches are the game's own", function()
    local cvars = fakeCVars(DEFAULTS)
    local DUI = stub.Load()
    local DT = DUI.DamageText
    local fired
    DUI.On("SettingChanged", function(scope, path) if path == "damage.show.pet" then fired = true end end)
    T.eq(DT.Shown("pet"), true)
    DT.SetShown("pet", false)
    T.eq(cvars.floatingCombatTextPetMeleeDamage_v2, "0")
    T.eq(cvars.floatingCombatTextPetSpellDamage_v2, "0", "both pet switches")
    T.eq(DT.Shown("pet"), false)
    T.truthy(fired, "the window hears of it")
    T.eq(DT.ShownDefault("pet"), true)
    clear()
end)

T.test("damage numbers: the combat text font goes on the game's font object at once", function()
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    local f = { face = "Fonts\\FRIZQT__.TTF", size = 120, flags = "FILTER, FIXEDHEIGHT" }
    function f:GetFont() return self.face, self.size, self.flags end
    function f:SetFont(a, b, c) self.face, self.size, self.flags = a, b, c end
    _G.CombatTextFont = f
    _G.GetFonts = function() return { "CombatTextFont" } end
    local DUI = stub.Load()
    T.eq(f.face, DUI.Style.FONTS.expressway.file, "untouched: the Appearance font")
    T.eq(f.flags, "", "no fixed height on our face")

    DUI:Set("general", "damage.sctFont", "bangers")
    stub.RunTimers()
    T.eq(f.face, DUI.Style.FONTS.bangers.file, "its own pick, game text off")
    T.eq(f.flags, "", "no fixed height on our face")

    DUI:Set("general", "damage.sctFont", "auto")
    DUI:Set("general", "damage.font", "fredoka")
    stub.RunTimers()
    T.eq(f.face, DUI.Style.FONT, "auto is the Appearance font, not the damage numbers'")

    DUI:Set("general", "font", "fira")
    DUI:Set("general", "gameText", true)
    DUI:Set("general", "damage.sctFont", "bangers")
    stub.RunTimers()
    T.eq(f.face, DUI.Style.FONTS.bangers.file, "its own beats game text")

    DUI:Set("general", "gameText", false)
    DUI:Set("general", "damage.sctFont", "auto")
    DUI:Set("general", "damage.font", "auto")
    stub.RunTimers()
    T.eq(f.face, DUI.Style.FONTS.fira.file, "auto: the Appearance font without game text")
    T.eq(f.flags, "", "no fixed height on our face")
    _G.STANDARD_TEXT_FONT, _G.GetFonts, _G.CombatTextFont = nil, nil, nil
end)

T.test("damage numbers: the last chosen font goes on while loading, before the talent set's profile is picked", function()
    _G.STANDARD_TEXT_FONT, _G.DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF", "Fonts\\skurri.ttf"
    local DUI = stub.Load()
    DUI:Set("general", "damage.font", "bangers")
    stub.RunTimers()
    local bangers = DUI.Style.FONTS.bangers.file
    T.eq(DUI.DB.Root().damageFont, bangers, "kept account-wide")

    -- Next login: the saved table comes back, and the profile in use at load has no damage font.
    local saved = _G.DaylightUIDB
    for _, p in pairs(saved.profileData) do if type(p.general) == "table" then p.general.damage = nil end end
    _G.DAMAGE_TEXT_FONT = "Fonts\\skurri.ttf"
    stub.Load{ login = false, before = function() _G.DaylightUIDB = saved end }
    T.eq(DAMAGE_TEXT_FONT, bangers, "set at load, before PLAYER_LOGIN")
    clear()
end)

T.test("damage numbers: a display font keeps the options window's body readable", function()
    local DUI = stub.Load()
    DUI:Set("general", "font", "glitch")
    stub.RunTimers()
    T.eq(DUI.OptionsTheme.BodyFont("enUS"), DUI.Style.FONTS.expressway.file)
    DUI:Set("general", "font", "fredoka")
    stub.RunTimers()
    T.eq(DUI.OptionsTheme.BodyFont("enUS"), DUI.Style.FONTS.fredoka.file, "a readable one is used")
end)

T.test("damage numbers: the sample pops numbers in the picked font and recycles them", function()
    local DUI = stub.Load()
    DUI:Set("general", "damage.font", "luckiest")
    stub.RunTimers()
    local s = DUI.DamageText.Sample(UIParent)
    T.eq(s.Refresh(400, 300), DUI.DamageText.SAMPLE_HEIGHT)
    local step = s.frame:GetScript("OnUpdate")
    T.truthy(step, "runs from the start: a sample made inside an open page gets no OnShow")
    for _ = 1, 200 do step(s.frame, 0.05) end   -- 10 seconds
    local texts, shown = 0, 0
    for _, r in ipairs({ s.frame:GetRegions() }) do
        if r:GetObjectType() == "FontString" then
            texts = texts + 1
            if r:IsShown() then
                shown = shown + 1
                T.eq(r:GetFont(), DUI.Style.FONTS.luckiest.file)
            end
        end
    end
    T.truthy(shown > 0, "numbers on screen")
    T.truthy(texts <= 8, "pooled, not one text per number (" .. texts .. ")")
    T.eq(#s.Parts(), 1)
    s.frame:Hide()
    for _, r in ipairs({ s.frame:GetRegions() }) do
        if r:GetObjectType() == "FontString" then T.falsy(r:IsShown(), "hidden numbers put away") end
    end
end)
