-- DaylightUIDB with defaults merged in, dotted-path access, profiles, and
-- stripping of default values at logout so only real changes are saved.

local _, DUI = ...

local DB = {}
DUI.DB = DB

DB.VERSION = 2

DB.CJK_LOCALES = { koKR = true, zhCN = true, zhTW = true }
function DB.NonLatinClient()
    return type(GetLocale) == "function" and DB.CJK_LOCALES[GetLocale()] == true
end
-- The single check everything uses: the setting only applies on those clients.
function DB.UseLocalFont()
    return DB.NonLatinClient() and DB.General().localFont == true
end

DB.GENERAL_DEFAULTS = {
    font = "expressway",
    localFont = false, -- Korean/Chinese clients only: use the game's font instead of ours
    gameText = false, -- also apply that font to the game's own text (GameFonts.lua)
    barTexture = "daylight", -- every bar's fill: ours, or "lsm:<name>" from shared media
    barBack = "daylight", -- the empty part behind every bar's fill, same format
    windowFont = "general", -- text in our windows (and skinned game ones); "general" = the font above
    windowBar = "general", -- bars in our windows (W.Bar); "general" = barTexture
    windowBack = "general", -- their empty part; "general" = barBack
    accent = "classGradient",
    lastNames = { -- first and last names, one switch per element
        player = true, target = true, targettarget = true, focus = true, focustarget = true, pet = true,
        party = true, raid = true, nameplates = true, tooltip = true, character = true, inspect = true,
        threat = false, -- the threat meter's rows are narrow
    },
    rpNames = true, -- Total RP 3 roleplay names instead of the game's (DUI.UnitName)
    accentColor = { 0.412, 0.365, 0.667 }, -- the accent when set to a custom color
    fontScale = 1,
    scale = 1, -- every DaylightUI frame and window (Movers.Scale, Win.Scale)
    frameScales = {}, -- [mover key] = one piece's own size, set with the wheel in unlock mode
    softness = 0.15,
    brightness = 0.95,
    borderAlpha = 1,
    shadowAlpha = 0.35,
    windowAlpha = 0.85, -- every window's background, ours and skinned game ones (Shell opts.window)
    borderPx = 8,
    heavyBorder = true,
    gradientBorder = false, -- window borders sweep along a gradient accent (Daylight's or the class's)
    cornerPx = 6,
    shadowPx = 4,
    gridSnap = true,
    magnet = true, -- unlock mode: frames snap to other frames' edges and centers (Movers.Magnet)
    hidePTRButton = false, -- beta/PTR only: hide Blizzard's Issue Reporter bug button
    smoothBars = true,
    motion = true, -- windows glide in, spells ping, numbers count up. Off snaps everything
    sounds = true, -- soft UI sounds instead of the game's (Sound.lua). Off = the game's everywhere
    soundKinds = { -- per kind: "soft" (ours) | "game" (the game's) | "none" (Sound.KINDS)
        windows = "soft", clicks = "soft", toggles = "soft", snaps = "soft", confirms = "soft",
    },
    fadeIn = true, -- the UI fades in on login and /reload
    fadeOpenWorldOnly = false, -- nothing fades in dungeons, raids, battlegrounds and arenas (Fade.Aside)
    textOutline = "OUTLINE", -- text outline: "OUTLINE", "THICKOUTLINE" or "" (none)
    textShadow = true, -- a small soft drop shadow under text
    numbers = "short", -- health and power number style: short | exact | full | upto (Health.NUMBERS)
    damage = { -- the game's damage numbers (DamageText.lua): font and how they burst off the target
        font = "auto", -- "auto" = the font above when gameText is on, else the game's; or any font key
        size = 1, -- size (the game's WorldTextScale_v2; 1 = Forever's default)
        spread = 0, -- how far they fly sideways (0 = straight up, Forever's default)
        height = 1, -- how far from the target they start (Forever's default)
        sctFont = "auto", -- the scrolling combat text over you; "auto" = the font above
    },
    gradients = { -- gradient pairs (Gradients.lua): colors.<KEY>.lo/hi only where changed
        off = false, -- every pair, the gradient accent and the Daylight bar sweep paint one flat color (Gradients.Flat)
        orientation = "HORIZONTAL",
        invert = false,
        palette = "daylight", -- a whole set of pairs (Gradients.RegisterPalette); your colors sit on top
        colors = {},
    },
}

local moduleDefaults = {}

function DB.MergeDefaults(dest, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dest[k]) ~= "table" then dest[k] = {} end
            DB.MergeDefaults(dest[k], v)
        elseif dest[k] == nil then
            dest[k] = v
        end
    end
    return dest
end

function DB.StripDefaults(t, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(t[k]) == "table" then
                DB.StripDefaults(t[k], v)
                if next(t[k]) == nil then t[k] = nil end
            end
        elseif t[k] == v then
            t[k] = nil
        end
    end
end

-- Paths are our own strings ("player.fade") read many times a second (the
-- fade ticker reads every area's), so each is split once and cached.
local split = {}
local function partsOf(path)
    local parts = split[path]
    if not parts then
        parts = {}
        for key in string.gmatch(path, "[^%.]+") do parts[#parts + 1] = key end
        split[path] = parts
    end
    return parts
end

function DB.GetPath(t, path)
    local parts = partsOf(path)
    for i = 1, #parts do
        if type(t) ~= "table" then return nil end
        t = t[parts[i]]
    end
    return t
end

function DB.SetPath(t, path, value)
    local parts = partsOf(path)
    for i = 1, #parts - 1 do
        local k = parts[i]
        if type(t[k]) ~= "table" then t[k] = {} end
        t = t[k]
    end
    t[parts[#parts]] = value
end

-- Profiles. Every setting lives in a profile (profileData[name]: general,
-- modules, positions). Each character uses one, or one per talent set with
-- dual spec, falling back to the standard "DPS/Tank" (or the first one left
-- if that's gone). With no profiles at all (nothing installed yet) the game
-- runs on an unsaved DPS/Tank that isn't listed, is dropped at logout, and
-- becomes real through the setup guide. Edits go into the active profile.
-- The rest of the saved table is account-wide: which profile each character
-- uses, and the installer's answers (characters).

DB.DEFAULT = "DPS/Tank"
-- The standard profile's old name, from before it and its DPS/Tank copy
-- were merged.
DB.OLD_DEFAULT = "Default"

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end
DB.Copy = copy

-- This character's first name and realm as "First-Realm", the key every
-- character used before last names were added (DaylightMogul still uses it).
-- Nil while the game doesn't know the name yet (it says "Unknown" early in
-- loading). GetRealmName is stable at every point.
function DB.ShortKey()
    local name = UnitName and UnitName("player")
    if type(name) ~= "string" or name == "" or name == (UNKNOWNOBJECT or "Unknown") then return nil end
    local realm = GetRealmName and GetRealmName() or ""
    return name .. "-" .. tostring(realm)
end

-- This character's last name (UnitFullName's second value on this client),
-- or nil before it's available (early in loading) or if there is none.
local function lastName()
    if type(UnitFullName) ~= "function" then return nil end
    local first, last = UnitFullName("player")
    if issecretvalue and (issecretvalue(first) or issecretvalue(last)) then return nil end
    if type(first) ~= "string" or type(last) ~= "string" or last == "" then return nil end
    return first, last
end

-- This character as "First Last-Realm". Two characters can share a first
-- name, and when they shared one entry each saw the other's bags. A
-- character with no last name keeps "First-Realm". Once known it's fixed for
-- the session, so a moment where the last name can't be read never moves the
-- character to another entry.
function DB.CharKey()
    local short = DB.ShortKey()
    if not short then return nil end
    if DB.fullKey and DB.fullKeyOf == short then return DB.fullKey end
    local first, last = lastName()
    if not first then return short end
    DB.fullKeyOf = short
    DB.fullKey = first .. " " .. last .. short:sub(#first + 1)
    if DB.loggedIn then DB.AdoptOldKeys() end
    return DB.fullKey
end

-- Parts of an old shared entry that belong to one character (bags, bank,
-- gold, mail name, mailbox ledger) rather than settings both can start from.
DB.OWN_KEYS = { inventory = true, money = true, mailName = true, ledger = true, class = true }

-- Folds keys this character was saved under before into its one entry.
-- "First-Last" (UnitFullName's, mistaken for a realm before 0.1.14): all of
-- it, then dropped. "First-Realm" (the old key), once: every setting it has
-- that this entry doesn't (copied, since another character with the same
-- first name may need it too), plus its bags and gold only when they're this
-- character's (matching mail name, else same class); those are then removed.
function DB.AdoptOldKeys()
    local key, short = DB.CharKey(), DB.ShortKey()
    local first, last = lastName()
    if not key or not first then return end
    local chars = DB.Root().characters
    local c = DB.Character()
    local old = first .. "-" .. last
    if old ~= key and old ~= short and type(chars[old]) == "table" then
        for k, v in pairs(chars[old]) do
            if c[k] == nil then c[k] = v end
        end
        chars[old] = nil
    end
    local s = chars[short]
    if key == short or c.fromShort or type(s) ~= "table" then return end
    c.fromShort = true
    local inv = type(s.inventory) == "table" and s.inventory or nil
    local theirClass = s.class or (inv and inv.class)
    local _, myClass = UnitClass and UnitClass("player")
    local mine
    if type(s.mailName) == "string" then
        mine = s.mailName == first .. " " .. last
    else
        mine = theirClass == nil or theirClass == myClass
    end
    for k, v in pairs(s) do
        if c[k] == nil and (mine or not DB.OWN_KEYS[k]) then c[k] = copy(v) end
    end
    if mine then
        for k in pairs(DB.OWN_KEYS) do s[k] = nil end
    end
end

-- A character's entry: { install, profile, specProfiles = { [1], [2] }, padProfile, lastSpec }.
-- This character's "First-Realm" key (DaylightMogul's) finds its own entry.
function DB.Character(key)
    local root = DB.Root()
    if type(root.characters) ~= "table" then root.characters = {} end
    local chars = root.characters
    if key ~= nil and key == DB.ShortKey() then key = nil end
    key = key or DB.CharKey()
    -- Name not known yet: a scratch entry that's never saved.
    if not key then
        DB.scratch = DB.scratch or {}
        return DB.scratch
    end
    if type(chars[key]) ~= "table" then chars[key] = { install = chars[key] } end
    return chars[key]
end

-- Whether this character has a second talent set.
function DB.DualSpec()
    if type(GetNumSpecGroups) ~= "function" then return false end
    local ok, n = pcall(GetNumSpecGroups)
    return ok and type(n) == "number" and n > 1
end

-- The active talent set (1 or 2). Before login the game may not know yet, so
-- the one this character last played on stands in.
function DB.SpecGroup()
    if DB.specKnown and C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        local ok, g = pcall(C_SpecializationInfo.GetActiveSpecGroup)
        if ok and (g == 1 or g == 2) then return g end
    end
    local chars = DB.sv and DB.sv.characters
    local key = DB.CharKey()
    local c = key and type(chars) == "table" and chars[key]
    return (type(c) == "table" and c.lastSpec == 2) and 2 or 1
end

-- Whether the game's controller UI is on. Readable while the addon loads,
-- before Blizzard_Gamepad is (which DUI.Pad.On() needs). The game's own
-- InputUtil.IsGamepadUIEnabled checks the same thing.
function DB.PadUI()
    local S, E = C_InputInterfaceStyle, Enum and Enum.InputDeviceInterfaceType
    if type(S) ~= "table" or type(S.GetCurrentStyle) ~= "function" or type(E) ~= "table" or E.Gamepad == nil then
        return false
    end
    local ok, style = pcall(S.GetCurrentStyle)
    return ok and style == E.Gamepad
end

-- The profile this character should be on for a talent set (the active one
-- when not given): the controller profile while the controller UI is on, else
-- that set's profile with dual spec, else the character's, else the standard
-- one. A profile that no longer exists counts as unset.
function DB.Pick(spec)
    local sv = DB.sv
    local key = DB.CharKey()
    local c = key and type(sv.characters) == "table" and sv.characters[key]
    if type(c) ~= "table" then return DB.Fallback() end
    local function real(n) return type(n) == "string" and type(sv.profileData[n]) == "table" and n or nil end
    local name
    if DB.PadUI() then name = real(c.padProfile) end
    if not name and DB.DualSpec() and type(c.specProfiles) == "table" then name = real(c.specProfiles[spec or DB.SpecGroup()]) end
    return name or real(c.profile) or DB.Fallback()
end

-- Whether a profile is saved (not the stand-in used before any install).
function DB.Saved(name)
    local p = DB.sv and DB.sv.profileData[name]
    return type(p) == "table" and not p.unsaved
end

-- The profile used when a character has none: the standard one, else the
-- first one left (A to Z), else the standard name (point() creates it unsaved).
function DB.Fallback()
    local pd = DB.sv and DB.sv.profileData
    if type(pd) ~= "table" or type(pd[DB.DEFAULT]) == "table" then return DB.DEFAULT end
    local first
    for n, p in pairs(pd) do
        if type(n) == "string" and type(p) == "table" and not p.unsaved
                and (not first or string.lower(n) < string.lower(first)) then
            first = n
        end
    end
    return first or DB.DEFAULT
end

-- Gradients became standard in 0.5.2: every profile moves its plain class,
-- power type and flat fills to the gradient versions, once. A "custom"
-- one-color pick is a deliberate choice and stays.
local GRADIENT_SWAPS = {
    { "UnitFrames", "colors.health", "class", "classGradient" },
    { "UnitFrames", "colors.power", "type", "gradient" },
    { "UnitFrames", "casts.pairGradient", false, true },
    { "UnitFrames", "swing.pairGradient", false, true },
    { "Nameplates", "healthColor", "class", "classGradient" },
    { "Nameplates", "nameColor", "class", "classGradient" },
    { "Nameplates", "friendly.healthColor", "class", "classGradient" },
    { "Nameplates", "friendly.nameColor", "class", "classGradient" },
    { "Nameplates", "castFill", "plain", "pair" },
    { "InfoPanel", "meter.gradient", false, true },
}
function DB.GradientsOn(modules)
    if type(modules) ~= "table" then return end
    for _, s in ipairs(GRADIENT_SWAPS) do
        local m = modules[s[1]]
        if type(m) == "table" and DB.GetPath(m, s[2]) == s[3] then DB.SetPath(m, s[2], s[4]) end
    end
end

-- Panel backgrounds now follow General's window opacity (each has a
-- "Separate ... background opacity" switch, `<key>Own`). A profile whose panel
-- already differed keeps its own value so nothing changes. Saved values only
-- (0.85 was everyone's old default and General's). The meters' and threat
-- meter's own windows now use the panel's.
DB.BACKS = { { "Chat", "panelAlpha" }, { "InfoPanel", "panelAlpha" }, { "Quests", "boxAlpha" },
             { "Buffs", "settings.backgroundAlpha" }, { "Buffs", "settings.debuff.backgroundAlpha" } }
-- Every background with a "Separate ... background opacity" switch. General's
-- Apply turns them all off (Options.ApplyWindowAlpha). Add new ones here.
DB.ALL_BACKS = { { "InfoPanel", "databar.alpha" }, { "InfoPanel", "map.alpha" },
                 { "InfoPanel", "meter.alpha" }, { "QoL", "lootFeedAlpha" },
                 { "Chat", "sideAlpha" } }
for _, b in ipairs(DB.BACKS) do DB.ALL_BACKS[#DB.ALL_BACKS + 1] = b end
for _, scope in ipairs({ "Bags", "Character", "NPC", "Book", "Inspect", "Professions", "GroupFinder",
                         "Mailbox", "Social", "Legacy", "Skins" }) do
    DB.ALL_BACKS[#DB.ALL_BACKS + 1] = { scope, "windowAlpha" }
end
function DB.OwnBacks(p)
    if type(p.modules) ~= "table" then return end
    local g = type(p.general) == "table" and tonumber(p.general.windowAlpha) or 0.85
    for _, b in ipairs(DB.BACKS) do
        local m = p.modules[b[1]]
        local v = type(m) == "table" and tonumber(DB.GetPath(m, b[2])) or 0.85
        if v ~= g then
            if type(m) ~= "table" then m = {}; p.modules[b[1]] = m end
            DB.SetPath(m, b[2] .. "Own", true)
        end
    end
    local ip = p.modules.InfoPanel
    if type(ip) == "table" then
        for _, k in ipairs({ "meter", "meter2", "threat" }) do
            if type(ip[k]) == "table" then ip[k].bgAlpha = nil end
        end
    end
end

-- Action bars 5 to 8 now start hidden, but used to show. Older profiles keep
-- showing the ones they showed: each is saved as "always" and listed, and the
-- action bars hide the listed ones that are empty once, at first login on it
-- (DaylightUI_ActionBars/Bars.lua).
DB.BARS_5_TO_8 = { "bar5", "bar6", "bar7", "bar8" }
function DB.KeepBars5to8(p)
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.modules.ActionBars) ~= "table" then p.modules.ActionBars = {} end
    local ab = p.modules.ActionBars
    if type(ab.bars) ~= "table" then ab.bars = {} end
    local list
    for _, key in ipairs(DB.BARS_5_TO_8) do
        if type(ab.bars[key]) ~= "table" then ab.bars[key] = {} end
        local v = ab.bars[key].visible
        if v == nil or v == "always" then
            ab.bars[key].visible = "always"
            list = list or {}
            list[key] = true
        end
    end
    ab.checkEmptyBars = list
end

-- Default and DPS/Tank used to be two copies of the standard setup; now
-- DPS/Tank is the one. If Default is alone it becomes DPS/Tank (along with
-- every character that chose it). If both exist, Default stays as its own
-- profile only for characters that chose it by name, else it's removed. Runs once.
local function mergeDefault(sv)
    if sv.oneStandard then return end
    sv.oneStandard = true
    local pd, old = sv.profileData, DB.OLD_DEFAULT
    if type(pd[old]) ~= "table" then return end
    local chars = type(sv.characters) == "table" and sv.characters or {}
    local alone = type(pd[DB.DEFAULT]) ~= "table"
    local used = false
    local function on(n) return n == old end
    for _, c in pairs(chars) do
        if type(c) == "table" then
            if on(c.profile) or (type(c.specProfiles) == "table" and (on(c.specProfiles[1]) or on(c.specProfiles[2]))) then
                used = true
            end
            if alone then
                if on(c.profile) then c.profile = DB.DEFAULT end
                if type(c.specProfiles) == "table" then
                    for i = 1, 2 do
                        if on(c.specProfiles[i]) then c.specProfiles[i] = DB.DEFAULT end
                    end
                end
                if type(c.installDraft) == "table" and on(c.installDraft.profile) then c.installDraft.profile = DB.DEFAULT end
            end
        end
    end
    if alone then
        pd[DB.DEFAULT], pd[old] = pd[old], nil
    elseif not used then
        pd[old] = nil
    end
end

-- Settings from before profiles (version 1) become the standard profile.
-- Profiles saved back then (snapshots) become their own profiles, taking what
-- snapshots left out (learned as you play) from the standard one.
local function migrate(sv)
    if type(sv.profileData) ~= "table" then sv.profileData = {} end
    local pd = sv.profileData
    mergeDefault(sv)
    sv.charProbeLog = nil -- an old debug log, removed
    sv.plateLog = nil -- the old nameplate recorder's log, removed
    -- Only pre-profile settings make the standard profile here. A new install has
    -- none until the setup guide (point() provides a stand-in).
    local legacy = type(sv.general) == "table" or type(sv.modules) == "table" or type(sv.positions) == "table"
    if legacy and type(pd[DB.DEFAULT]) ~= "table" then
        pd[DB.DEFAULT] = {
            general = type(sv.general) == "table" and sv.general or {},
            modules = type(sv.modules) == "table" and sv.modules or {},
            positions = type(sv.positions) == "table" and sv.positions or {},
        }
    end
    sv.general, sv.modules, sv.positions = nil, nil, nil
    if type(sv.profiles) == "table" then
        local skip = DUI.Profiles and DUI.Profiles.SKIP or {}
        local std = pd[DB.DEFAULT]
        local from = type(std) == "table" and type(std.modules) == "table" and std.modules or {}
        for name, snap in pairs(sv.profiles) do
            if type(name) == "string" and type(snap) == "table" and pd[name] == nil then
                local p = { general = copy(snap.general) or {}, modules = copy(snap.modules) or {},
                            positions = copy(snap.positions) or {}, pendingLayout = snap.layout }
                for mod, paths in pairs(skip) do
                    if type(from[mod]) == "table" then
                        if type(p.modules[mod]) ~= "table" then p.modules[mod] = {} end
                        for path in pairs(paths) do DB.SetPath(p.modules[mod], path, copy(DB.GetPath(from[mod], path))) end
                    end
                end
                pd[name] = p
            end
        end
        sv.profiles = nil
    end
    for _, p in pairs(pd) do
        if type(p) == "table" and not p.gradients1 then
            p.gradients1 = true
            DB.GradientsOn(p.modules)
        end
        if type(p) == "table" and not p.hiddenBars1 then
            p.hiddenBars1 = true
            DB.KeepBars5to8(p)
        end
        if type(p) == "table" and not p.backs1 then
            p.backs1 = true
            DB.OwnBacks(p)
        end
        if type(p) == "table" and not p.localFont1 then
            p.localFont1 = true
            if DB.NonLatinClient() then
                if type(p.general) ~= "table" then p.general = {} end
                p.general.localFont = true
            end
        end
    end
    if type(sv.characters) ~= "table" then sv.characters = {} end
    for key, v in pairs(sv.characters) do
        if type(v) ~= "table" then sv.characters[key] = { install = v } end
        if string.find(key, "^Unknown%-") then sv.characters[key] = nil end
    end
end

-- The buff bars' Scale sliders are gone; a bar's size beyond its icons is now
-- set with the unlock wheel (general.frameScales). A saved Scale moves there
-- so nothing changes size. Profiles not in use migrate when next filled.
function DB.BuffScales(p)
    local buffs = p.modules.Buffs
    local s = type(buffs) == "table" and buffs.settings
    if type(s) ~= "table" then return end
    local function move(t, key)
        local v = tonumber(t.scale)
        t.scale = nil
        if not v or v == 1 then return end
        if type(p.general.frameScales) ~= "table" then p.general.frameScales = {} end
        local scales = p.general.frameScales
        scales[key] = (tonumber(scales[key]) or 1) * v
    end
    move(s, "buffs.buff")
    if type(s.debuff) == "table" then move(s.debuff, "buffs.debuff") end
end

-- Makes sure a profile's tables exist with every default filled in.
local function fill(p)
    -- Old fade settings migrate first, since the defaults would wipe chat's old
    -- idle switch (on a profile not used since, or copied or exported).
    if DUI.FadeUpgrade then DUI.FadeUpgrade.Run(p) end
    if type(p.general) ~= "table" then p.general = {} end
    if type(p.positions) ~= "table" then p.positions = {} end
    if type(p.modules) ~= "table" then p.modules = {} end
    DB.BuffScales(p)
    DB.MergeDefaults(p.general, DB.GENERAL_DEFAULTS)
    for name, defaults in pairs(moduleDefaults) do
        if type(p.modules[name]) ~= "table" then p.modules[name] = {} end
        DB.MergeDefaults(p.modules[name], defaults)
    end
    return p
end
DB.Fill = fill

-- Where every new standard setup starts on top of the defaults: the info
-- panel closed (its tab opens the meter) and the chat floating (only its
-- lines show). The account's first profile and every ready-made one built
-- clean (Profiles.ReadyData) use it.
function DB.StandardStart()
    return { InfoPanel = { meter = { enabled = false } },
             Chat = { hides = "always" } }
end

-- Points every module at the active profile.
local function point()
    local pd = DB.sv.profileData
    if type(pd[DB.activeName]) ~= "table" then DB.activeName = DB.Fallback() end
    if type(pd[DB.activeName]) ~= "table" then
        -- The account's first profile. Whatever the setup guide saves comes from this.
        pd[DB.activeName] = { gradients1 = true, localFont1 = true, hiddenBars1 = true, backs1 = true, unsaved = true,
                              general = { localFont = DB.NonLatinClient() or nil },
                              modules = DB.StandardStart() }
    end
    local p = fill(pd[DB.activeName])
    for name in pairs(moduleDefaults) do
        local mod = DUI:GetModule(name)
        if mod then mod.db = p.modules[name] end
    end
end
-- Also called after the active profile is refilled in place (Profiles.Replace),
-- since its module tables are new and modules must point at them.
DB.Repoint = point

-- (Re)builds the saved table. Safe to call again: the client may replace
-- DaylightUIDB after files run, so Root() re-checks identity on every access.
function DB.Init()
    if type(_G.DaylightUIDB) ~= "table" then
        _G.DaylightUIDB = {}
        DB.made = _G.DaylightUIDB
    end
    local sv = _G.DaylightUIDB
    -- Nothing from an earlier session: a table created here, or one saved before
    -- the DB had versions.
    DB.fresh = sv == DB.made or sv.version == nil
    DB.sv = sv
    migrate(sv)
    sv.version = DB.VERSION
    DB.activeName = DB.Pick()
    point()
end

-- At login, before any module is built. The game knows the talent set now,
-- so pick the profile again. True if that changed it.
function DB.OnLogin()
    DB.Root()
    DB.specKnown = true
    DB.loggedIn = true
    DB.AdoptOldKeys()
    -- A setup guide cut short by a crash or reload gets its preview undone
    -- (InstallerDraft.lua) before anything is built from the settings.
    if DUI.InstallerDraft and DB.CharKey() then DUI.InstallerDraft.RestoreSaved() end
    if DB.CharKey() then DB.Character().lastSpec = DB.SpecGroup() end
    local name = DB.Pick()
    if name ~= DB.activeName then
        DB.activeName = name
        point()
        return true
    end
end

function DB.Root()
    if DB.sv == nil or DB.sv ~= _G.DaylightUIDB then DB.Init() end
    return DB.sv
end

-- The active profile: its name, and its tables.
function DB.ActiveName()
    DB.Root()
    return DB.activeName
end

function DB.Active()
    local sv = DB.Root()
    if type(sv.profileData[DB.activeName]) ~= "table" then point() end
    return sv.profileData[DB.activeName]
end

function DB.General() return DB.Active().general end
function DB.Positions() return DB.Active().positions end
-- Running on the unsaved stand-in (the setup guide was never finished). Every
-- change is dropped at logout, so the options and unlock mode say so.
function DB.Unsaved() return DB.Active().unsaved == true end

-- Settings plugins added to our modules (DaylightUI.API's AddDefaults), as
-- module -> key -> plugin name. Kept in saved data so a disabled plugin keeps
-- its values and tools/settings_check.lua knows about them.
function DB.PluginKeys()
    local sv = DB.Root()
    if type(sv.pluginKeys) ~= "table" then sv.pluginKeys = {} end
    return sv.pluginKeys
end

function DB.Module(name, defaults)
    moduleDefaults[name] = defaults
    local mods = DB.Active().modules
    if type(mods[name]) ~= "table" then mods[name] = {} end
    DB.MergeDefaults(mods[name], defaults)
    return mods[name]
end

-- Upgrades modules register for a profile's saved data (fn(profileData)).
-- Each module runs its own on the active profile as it loads, and
-- Profiles.Create runs all of them on a new profile copied from another,
-- which may be older than them.
DB.UPGRADES = {}
function DB.RegisterUpgrade(fn) DB.UPGRADES[#DB.UPGRADES + 1] = fn end
function DB.RunUpgrades(p)
    for _, fn in ipairs(DB.UPGRADES) do DUI.SafeCall(fn, p) end
end

-- Only what differs from the defaults is saved, in every profile. The unsaved
-- stand-in isn't saved at all.
function DB.OnLogout()
    local sv = _G.DaylightUIDB
    if type(sv) ~= "table" or type(sv.profileData) ~= "table" then return end
    for name, p in pairs(sv.profileData) do
        if type(p) == "table" and p.unsaved then
            sv.profileData[name] = nil
        elseif type(p) == "table" then
            if type(p.general) == "table" then DB.StripDefaults(p.general, DB.GENERAL_DEFAULTS) end
            for name, defaults in pairs(moduleDefaults) do
                local t = type(p.modules) == "table" and p.modules[name]
                if type(t) == "table" then DB.StripDefaults(t, defaults) end
            end
        end
    end
end
