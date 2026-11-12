-- Restyles the game's own damage numbers (the ones that pop off what you hit).
-- None are drawn by the addon: on Forever the combat log is closed, so the
-- game's are the only numbers that show just your hits. The font goes in
-- DAMAGE_TEXT_FONT (see GameFonts.lua), which the client reads once at login,
-- so a change shows after a game restart.
-- Motion: Forever has no WorldText* motion settings, only the directional ones
-- below. At a spread of 0 (the client default) numbers go straight up; above
-- 0 they burst out sideways from the target. Size is WorldTextScale_v2; the
-- plain WorldTextScale doesn't exist on Forever.

local _, DUI = ...
local L = DUI.L

local DT = {}
DUI.DamageText = DT

-- Our setting (damage.<key>) -> the game's CVar, and the client's own default.
DT.CVARS = {
    size = "WorldTextScale_v2",
    spread = "floatingCombatTextCombatDamageDirectionalScale_v2",
    height = "floatingCombatTextCombatDamageDirectionalOffset_v2",
}
DT.GAME = { size = 1, spread = 0, height = 1 } -- Forever's defaults, for when the client can't say
DT.ORDER = { "size", "spread", "height" }

-- A preset is just these values. Size isn't part of it (a preset keeps it). The Preset dropdown shows whichever one matches.
DT.PRESETS = {
    game = { spread = 0, height = 1 },
    soft = { spread = 1, height = 1 },
    punchy = { spread = 3, height = 1.5 },
    clean = { spread = 0.6, height = 0.5 },
}
DT.PRESET_ORDER = { "game", "soft", "punchy", "clean" }

-- The game's switches for which numbers show (stored by the game, not by us).
DT.SHOW = {
    damage = { "floatingCombatTextCombatDamage_v2" },
    healing = { "floatingCombatTextCombatHealing_v2" },
    pet = { "floatingCombatTextPetMeleeDamage_v2", "floatingCombatTextPetSpellDamage_v2" },
}

local function cvar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, name)
    return ok and tonumber(v) or nil
end

local function cvarDefault(name)
    local fn = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, name)
    return ok and tonumber(v) or nil
end

-- The client's own value for damage.<key>.
function DT.Default(key)
    return cvarDefault(DT.CVARS[key]) or DT.GAME[key]
end

-- Whether this client has the game setting behind damage.<key>.
function DT.Has(key)
    local name = DT.CVARS[key]
    return name ~= nil and cvar(name) ~= nil
end

local function value(key)
    local v = DUI:Get("general", "damage." .. key)
    return type(v) == "number" and v or DT.GAME[key]
end

-- The preset the current values match, or "custom".
function DT.Preset()
    for _, name in ipairs(DT.PRESET_ORDER) do
        local same = true
        for key, v in pairs(DT.PRESETS[name]) do
            if math.abs(value(key) - v) > 0.001 then same = false break end
        end
        if same then return name end
    end
    return "custom"
end

function DT.SetPreset(name)
    local p = DT.PRESETS[name]
    if not p then return end
    for key, v in pairs(p) do DUI:Set("general", "damage." .. key, v) end
end

local function anyChanged()
    for _, key in ipairs(DT.ORDER) do
        if math.abs(value(key) - DT.Default(key)) > 0.001 then return true end
    end
    return false
end

-- Writes the game's CVars from our settings. A player who never changed
-- anything keeps their own game settings. Once we've written them (a DB.Root
-- flag), going back to the game's preset restores the client defaults.
function DT.Apply()
    local root = DUI.DB.Root()
    if not anyChanged() and root.damageTextSet ~= true then return end
    DUI.AfterCombat(function()
        if type(SetCVar) ~= "function" then return end
        for _, key in ipairs(DT.ORDER) do
            local name = DT.CVARS[key]
            local now, want = cvar(name), value(key)
            if now ~= nil and math.abs(now - want) > 0.0001 then
                pcall(SetCVar, name, string.format("%.2f", want))
            end
        end
        root.damageTextSet = anyChanged() or nil
    end, "damagetext")
end

-- One of the game's show switches: on, off, or nil if this client lacks it.
function DT.Shown(what)
    local v = cvar(DT.SHOW[what][1])
    if v == nil then return nil end
    return v ~= 0
end

function DT.SetShown(what, on)
    if type(SetCVar) ~= "function" then return end
    for _, name in ipairs(DT.SHOW[what]) do
        if cvar(name) ~= nil then pcall(SetCVar, name, on and "1" or "0") end
    end
    -- Stored by the game, not our settings, so tell the window to slide the switch.
    DUI.Fire("SettingChanged", "general", "damage.show." .. what, on)
end

function DT.ShownDefault(what)
    local d = cvarDefault(DT.SHOW[what][1])
    return d ~= nil and d ~= 0
end

-- The font file the numbers use (or will use after the next login).
function DT.FontFile()
    return DUI.GameFonts.DamageWanted() or DUI.GameFonts.ClientFont()
end

DUI.On("Login", DT.Apply)
DUI.On("SettingChanged", function(scope, path)
    if scope ~= "general" or type(path) ~= "string" then return end
    local key = path:match("^damage%.(%w+)$")
    if key and DT.CVARS[key] then DT.Apply() end
end)

-- Live sample for the options page: a dummy with numbers popping off it in the
-- chosen font and speed. Our own font strings, only moved and faded, never
-- scaled (setting a new text size every frame is expensive). Two sizes per look.

DT.SAMPLE_HEIGHT = 120
DT.SAMPLE_EVERY = 0.5     -- seconds between numbers
DT.SAMPLE_SIZE = 18       -- a normal hit's text size at Size 1x

function DT.Sample(parent)
    local s = {}
    local f = CreateFrame("Frame", nil, parent)
    s.frame = f

    local dummy = CreateFrame("Frame", nil, f)
    dummy:SetSize(130, 24)
    DUI.Style.Shell(dummy, {})
    local name = DUI.Style.Text(dummy, 12, "CENTER")
    name:SetPoint("CENTER")
    name:SetText(L["Training Dummy"])
    DUI.Style.InkText(name, "LABEL")

    local live, spare = {}, {}
    local clock, n = 0, 0
    local look = {}

    -- Font, sizes and motion from the settings, read once per change.
    function s.Look()
        look.file = DT.FontFile()
        look.size = math.floor(DT.SAMPLE_SIZE * value("size") + 0.5)
        look.crit = math.floor(DT.SAMPLE_SIZE * value("size") * 1.4 + 0.5)
        look.gravity = 140 -- a soft arc: up about 45 px, then easing down
        look.life = 1.1
        look.rise = 110
        look.side = 45 * value("spread") -- px per second sideways. 0 = straight up, like the game
        look.start = 2 + 8 * value("height")
    end

    local function spawn()
        n = n + 1
        local crit = n % 4 == 0
        local fs = table.remove(spare) or f:CreateFontString(nil, "OVERLAY")
        local size = crit and look.crit or look.size
        if fs.file ~= look.file or fs.size ~= size then
            fs:SetFont(look.file, size, "OUTLINE")
            fs.file, fs.size = look.file, size
        end
        local amount = crit and math.random(1800, 3200) or math.random(300, 1200)
        fs:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or tostring(amount))
        if crit then fs:SetTextColor(1, 0.86, 0.35) else DUI.Style.InkText(fs, "VALUE") end
        fs:SetAlpha(1)
        fs:Show()
        fs.t = 0
        -- Alternate sides, like the game's directional numbers.
        fs.vx = (n % 2 == 0 and 1 or -1) * look.side * (0.7 + 0.6 * math.random())
        fs.x0 = (math.random() * 2 - 1) * 6
        fs.vy = look.rise + (crit and 30 or 0)
        live[#live + 1] = fs
    end

    local function step(_, dt)
        clock = clock + dt
        if clock >= DT.SAMPLE_EVERY then
            clock = 0
            spawn()
        end
        for i = #live, 1, -1 do
            local fs = live[i]
            fs.t = fs.t + dt
            local t = fs.t
            if t >= look.life then
                fs:Hide()
                table.remove(live, i)
                spare[#spare + 1] = fs
            else
                local y = fs.vy * t - 0.5 * look.gravity * t * t
                fs:ClearAllPoints()
                fs:SetPoint("BOTTOM", dummy, "TOP", fs.x0 + fs.vx * t, look.start + math.max(y, -20))
                local left = 1 - t / look.life
                fs:SetAlpha(left < 0.4 and left / 0.4 or 1)
            end
        end
    end

    -- OnUpdate only runs while visible, so no OnShow is needed (a frame created
    -- inside an already open page never gets one).
    f:SetScript("OnUpdate", step)
    f:SetScript("OnShow", s.Look)
    f:SetScript("OnHide", function()
        for i = #live, 1, -1 do
            live[i]:Hide()
            spare[#spare + 1] = live[i]
            live[i] = nil
        end
    end)

    function s.Refresh(width, maxHeight)
        s.Look()
        local h = math.min(DT.SAMPLE_HEIGHT, maxHeight or DT.SAMPLE_HEIGHT)
        f:SetSize(width, h)
        dummy:ClearAllPoints()
        dummy:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
        return h
    end

    function s.Parts()
        return { { region = dummy, label = L["Damage numbers"], keys = { "damage.font" } } }
    end

    s.Look()
    return s
end
