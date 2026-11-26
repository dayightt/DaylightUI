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
    localFont = false, -- Korean/Chinese clients only: use the game's font instead of Daylight UI's
    gameText = false, -- also apply that font to the game's own text (GameFonts.lua)
    barTexture = "daylight", -- every bar's fill: Daylight UI's, or "lsm:<name>" from shared media
    barBack = "daylight", -- the empty part behind every bar's fill, same format
    windowFont = "general", -- text in Daylight UI's windows (and skinned game ones); "general" = the font above
    windowBar = "general", -- bars in Daylight UI's windows (W.Bar); "general" = barTexture
    windowBack = "general", -- their empty part; "general" = barBack
    accent = "classGradient",
    lastNames = { -- first and last names, one switch per element
        player = true, target = true, targettarget = true, focus = true, focustarget = true, pet = true, partyTarget = true,
        party = true, raid = true, nameplates = true, tooltip = true, character = true, inspect = true,
        threat = false, -- the threat meter's rows are narrow
    },
    rpNames = true, -- Total RP 3 roleplay names instead of the game's (DUI.UnitName)
    accentColor = { 0.412, 0.365, 0.667 }, -- the accent when set to a custom color
    accentGradient = { -- the accent when set to a custom gradient: the first `count` colors, left to right
        count = 3,
        c1 = { 0.200, 0.820, 0.760 }, c2 = { 0.560, 0.420, 0.950 }, c3 = { 1.000, 0.450, 0.600 },
        c4 = { 1.000, 0.760, 0.330 }, c5 = { 0.960, 0.930, 0.820 },
    },
    fontScale = 1,
    scale = 1, -- every DaylightUI frame and window (Movers.Scale, Win.Scale)
    frameScales = {}, -- [mover key] = one piece's own size, set with the wheel in unlock mode
    softness = 0.15,
    brightness = 0.95,
    borderAlpha = 1,
    shadowAlpha = 0.35,
    windowAlpha = 0.85, -- every window's background, Daylight UI's and skinned game ones (Shell opts.window)
    windowTint = "daylight", -- their color: "daylight" (the look's own), "class" (a dark class tint), "custom"
    windowTintColor = { 0.078, 0.078, 0.090 }, -- the color when windowTint is "custom"
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
    buttonGlow = "circle", -- the main buttons' animated glow: "none" or a W.GLOW_STYLES key
    portraitFlare = true, -- the ring of embers round a window's icon as it opens (Win.PlayGlow). Needs motion
    sounds = true, -- soft UI sounds instead of the game's (Sound.lua). Off = the game's everywhere
    soundKinds = { -- per kind: "soft" (Daylight UI's) | "game" (the game's) | "none" (Sound.KINDS)
        windows = "soft", clicks = "soft", toggles = "soft", snaps = "soft", confirms = "soft",
    },
    fadeIn = true, -- the UI fades in on login and /reload
    fadeOpenWorldOnly = false, -- nothing fades in dungeons, raids, battlegrounds and arenas (Fade.Aside)
    fadeOnFlight = false, -- the whole UI fades while on a flight path (Fade.CheckFlight)
    fadeAllWas = {}, -- each part's Visible pick from before the Fade page's "only when something changes" switch went on
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

-- Paths are the addon's own strings ("player.fade") read many times a second (the
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

-- This character's last name (UnitFullName's second value on this client),
-- or nil before it's available (early in loading) or if there is none.
local function lastName()
    if type(UnitFullName) ~= "function" then return nil end
    local first, last = UnitFullName("player")
    if DUI.IsSecret(first) or DUI.IsSecret(last) then return nil end
    if type(first) ~= "string" or type(last) ~= "string" or last == "" then return nil end
    return first, last
end

-- A realm name without spaces or dashes, the way GetNormalizedRealmName gives it.
local function squash(realm)
    return (string.gsub(string.lower(tostring(realm)), "[%s%-']", ""))
end

-- The realm this character was saved under before. With the same name saved on
-- more than one realm, the game's normalized realm name picks one, then the
-- character's class; still unsure gives nil. Found ones are kept for the session.
local foundRealm = {}
local function savedRealm(name)
    if foundRealm[name] then return foundRealm[name] end
    local sv = _G.DaylightUIDB
    local chars = type(sv) == "table" and type(sv.characters) == "table" and sv.characters or nil
    if not chars then return nil end
    local found = {}
    for key, c in pairs(chars) do
        local who, r = string.match(tostring(key), "^(.-)%-(.+)$")
        if who == name and r then found[#found + 1] = { realm = r, c = c } end
    end
    if #found > 1 then
        local normal = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName()
        if type(normal) == "string" and normal ~= "" then
            local keep = {}
            for _, f in ipairs(found) do
                if squash(f.realm) == squash(normal) then keep[#keep + 1] = f end
            end
            if #keep > 0 then found = keep end
        end
    end
    -- An entry saved with another class is someone else of the same name.
    local myClass
    if type(UnitClass) == "function" then myClass = select(2, UnitClass("player")) end
    if type(myClass) == "string" and not DUI.IsSecret(myClass) then
        local same, unknown = {}, {}
        for _, f in ipairs(found) do
            local c = type(f.c) == "table" and f.c or {}
            local inv = type(c.inventory) == "table" and c.inventory or {}
            local theirs = c.class or inv.class
            if theirs == myClass then same[#same + 1] = f
            elseif theirs == nil then unknown[#unknown + 1] = f end
        end
        found = #same > 0 and same or unknown
    end
    if #found ~= 1 then return nil end
    foundRealm[name] = found[1].realm
    return found[1].realm
end

-- The realm name. On some logins the game hands back an empty realm name for a
-- whole session (seen in game); keyed on that, the character started over with
-- nothing saved. Then the realm it was saved under before stands in.
local function realmOf(first)
    if type(GetRealmName) ~= "function" then return "" end
    local realm = GetRealmName()
    if type(realm) ~= "string" then return "" end
    if realm ~= "" then return realm end
    local f, last = lastName()
    return (f and savedRealm(f .. " " .. last)) or savedRealm(first) or ""
end

-- This character's first name and realm as "First-Realm", the key every
-- character used before last names were added (DaylightMogul still uses it).
-- Nil while the game doesn't know the name yet (it says "Unknown" early in
-- loading).
function DB.ShortKey()
    local name = UnitName and UnitName("player")
    if type(name) ~= "string" or name == "" or name == (UNKNOWNOBJECT or "Unknown") then return nil end
    return name .. "-" .. realmOf(name)
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

-- Which profile a character is on.
DB.PICK_KEYS = { profile = true, specProfiles = true, padProfile = true }

-- Folds keys this character was saved under before into its one entry.
-- "First-Last" (UnitFullName's, mistaken for a realm before 0.1.14): all of
-- it, then dropped. "First-Realm" (the old key), once: every setting it has
-- that this entry doesn't (copied, since another character with the same
-- first name may need it too), plus its bags and gold only when they're this
-- character's (matching mail name, else same class); those are then removed.
function DB.AdoptOldKeys()
    local key, short = DB.CharKey(), DB.ShortKey()
    if not key then return end
    local c = DB.Character()
    local chars = DB.Root().characters
    -- An entry saved while the game gave no realm name ("First Last-"): this
    -- entry's own values win, the rest comes along. Its profile choice stays
    -- behind: it was made while the character looked reset, and this entry
    -- having none means it was on the standard profile.
    local bare = string.match(key, "^(.-%-)")
    if bare and bare ~= key and type(chars[bare]) == "table" then
        for k, v in pairs(chars[bare]) do
            if c[k] == nil and not DB.PICK_KEYS[k] then c[k] = v end
        end
        chars[bare] = nil
    end
    -- The GUID stays the same whatever the name or realm read as, so it finds the
    -- character's entry when the key no longer does (a realm renamed or misread).
    -- A new entry gives way to the one the character was set up under.
    local guid = UnitGUID and UnitGUID("player")
    if guid ~= nil and not DUI.IsSecret(guid) and type(guid) == "string" then
        for k, other in pairs(chars) do
            if k ~= key and type(other) == "table" and other.guid == guid then
                local into, from = c, other
                if c.install == nil and other.install ~= nil then
                    chars[key] = other
                    into, from, c = other, c, other
                end
                for f, v in pairs(from) do
                    if into[f] == nil then into[f] = v end
                end
                chars[k] = nil
            end
        end
        c.guid = guid
    end
    local first, last = lastName()
    if not first then return end
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
    -- Profiles chosen per talent set are only made with two sets, and a character
    -- never loses its second, so they count even while the game still says one
    -- (early at login): the character's own choice would win, then the talents
    -- would ask to switch on every login.
    local perSet = type(c.specProfiles) == "table" and next(c.specProfiles) ~= nil
    if not name and (DB.DualSpec() or perSet) and type(c.specProfiles) == "table" then
        name = real(c.specProfiles[spec or DB.SpecGroup()])
    end
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
-- The border, shadow and background settings a window or panel can have of
-- its own (Style.LookOf), under General's names.
DB.LOOK_KEYS = { "heavyBorder", "gradientBorder", "borderPx", "cornerPx", "borderAlpha",
                 "shadowPx", "shadowAlpha", "windowAlpha", "windowTint", "windowTintColor" }

-- Every section with a "Use Daylight UI global style" switch ({ scope, path of
-- its look table }). General's Apply turns them all back on
-- (Options.ApplyGlobalStyle). Add new ones here. Meter windows the player
-- makes are handled by the meters themselves.
DB.WINDOW_SCOPES = { "Bags", "Character", "NPC", "Book", "Inspect", "Professions", "GroupFinder",
                     "Mailbox", "Social", "Legacy", "Skins", "AuctionHouse" }
DB.LOOKS = { { "Chat", "frameStyle" }, { "InfoPanel", "frameStyle" }, { "InfoPanel", "map.frameStyle" },
             { "InfoPanel", "databar.frameStyle" }, { "InfoPanel", "meter.frameStyle" }, { "InfoPanel", "threat.frameStyle" },
             { "Quests", "frameStyle" }, { "Tooltip", "frameStyle" }, { "Buffs", "settings.frameStyle" },
             { "Buffs", "settings.debuff.frameStyle" }, { "QoL", "lootFeedFrame" }, { "QoL", "flightFrame" } }
for _, scope in ipairs(DB.WINDOW_SCOPES) do DB.LOOKS[#DB.LOOKS + 1] = { scope, "frameStyle" } end
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

-- Each section's old look settings (a "Separate ... background opacity"
-- switch, a border switch, its own border thickness or style) move into its
-- look table, with its global style off, so nothing a player set changes.
-- The rest of the section's look starts from the profile's own General values,
-- as it showed them before, except what the section has by design (its
-- default differs from General's: the data bar's missing border). Saved
-- values only; the old keys go. Runs on every profile as it's filled, and
-- does nothing once the old keys are gone.
local function num(v, d) if type(v) == "number" then return v end return d end
local function designed(scope, path, k)
    local d = moduleDefaults[scope] and DB.GetPath(moduleDefaults[scope], path)
    return type(d) == "table" and d[k] ~= nil and type(d[k]) ~= "table" and d[k] ~= DB.GENERAL_DEFAULTS[k]
end
local function ownLook(p, m, scope, path, values)
    local look = DB.GetPath(m, path)
    if type(look) ~= "table" then look = {}; DB.SetPath(m, path, look) end
    if look.global ~= false then
        look.global = false
        local g = type(p.general) == "table" and p.general or {}
        for _, k in ipairs(DB.LOOK_KEYS) do
            if look[k] == nil and g[k] ~= nil and not designed(scope, path, k) then look[k] = copy(g[k]) end
        end
    end
    for k, v in pairs(values or {}) do look[k] = v end
end
local function clear(m, ...)
    for i = 1, select("#", ...) do DB.SetPath(m, (select(i, ...)), nil) end
end

-- A box with an opacity switch (own, alpha) and maybe a border switch.
local function boxLook(p, m, scope, path, own, alpha, border)
    local vals, mine = {}, false
    if DB.GetPath(m, own) == true then vals.windowAlpha, mine = num(DB.GetPath(m, alpha), 0.85), true end
    if border and DB.GetPath(m, border) == false then vals.borderAlpha, mine = 0, true end
    if mine then ownLook(p, m, scope, path, vals) end
    clear(m, own, alpha)
    if border then clear(m, border) end
end

local function chatLook(p, chat)
    local vals, mine = {}, chat.sideAlphaOwn == true
    if chat.panelAlphaOwn == true then vals.windowAlpha, mine = num(chat.panelAlpha, 0.85), true end
    if chat.border == "flat" then
        vals.heavyBorder, vals.borderPx, mine = false, num(chat.borderSize, 1), true
    elseif chat.border == "none" then
        vals.borderAlpha, mine = 0, true
    elseif chat.border == "daylight" and chat.style == "classic" then
        mine = true
    end
    if chat.borderColor ~= nil and chat.borderColor ~= "shell" then mine = true end
    if mine then ownLook(p, chat, "Chat", "frameStyle", vals) end
    clear(chat, "panelAlphaOwn", "panelAlpha", "border", "borderSize")
end

local function infoPanelLook(p, ip)
    -- The minimap box once shared the panel's look (the info panel's map box
    -- upgrade, done here when it hasn't run yet).
    if not p.mapBox1 then
        p.mapBox1 = true
        local map = type(ip.map) == "table" and ip.map or {}
        for from, to in pairs({ panelAlphaOwn = "alphaOwn", panelAlpha = "alpha", panelBorder = "border" }) do
            if ip[from] ~= nil and map[to] == nil then map[to] = ip[from] end
        end
        if next(map) ~= nil then ip.map = map end
    end
    -- A meter's own window used to take the panel's opacity.
    local panelOwn = ip.panelAlphaOwn == true and num(ip.panelAlpha, 0.85) or nil
    local function meter(path)
        local w = DB.GetPath(ip, path)
        if type(w) ~= "table" then return end
        if panelOwn and w.alphaOwn ~= true then w.alphaOwn, w.alpha = true, panelOwn end
        boxLook(p, ip, "InfoPanel", path .. ".frameStyle", path .. ".alphaOwn", path .. ".alpha", path .. ".border")
    end
    meter("meter")
    meter("threat")
    if type(ip.meters) == "table" and type(ip.meters.windows) == "table" then
        for id in pairs(ip.meters.windows) do meter("meters.windows." .. tostring(id)) end
    end
    boxLook(p, ip, "InfoPanel", "frameStyle", "panelAlphaOwn", "panelAlpha", "panelBorder")
    if type(ip.map) == "table" then boxLook(p, ip, "InfoPanel", "map.frameStyle", "map.alphaOwn", "map.alpha", "map.border") end
    local bar = type(ip.databar) == "table" and ip.databar
    if bar then
        local ba = num(bar.borderAlpha, nil)
        boxLook(p, ip, "InfoPanel", "databar.frameStyle", "databar.alphaOwn", "databar.alpha")
        if ba and ba ~= 0 then ownLook(p, ip, "InfoPanel", "databar.frameStyle", { borderAlpha = ba }) end
        bar.borderAlpha = nil
    end
end

-- Tooltips had their own look switched on from the start; it was only saved
-- when switched off (then they followed General) or changed.
local function tooltipLook(p, tip)
    local g = type(p.general) == "table" and p.general or {}
    if tip.bgAlphaOwn == false then
        ownLook(p, tip, "Tooltip", "frameStyle", { windowAlpha = num(g.windowAlpha, 0.85) })
    elseif tip.bgAlpha ~= nil or tip.borderPx ~= nil then
        local px = num(tip.borderPx, 8)
        ownLook(p, tip, "Tooltip", "frameStyle", { windowAlpha = num(tip.bgAlpha, 0.92),
            borderPx = math.max(1, px), borderAlpha = px <= 0 and 0 or nil })
    end
    clear(tip, "bgAlphaOwn", "bgAlpha", "borderPx", "richAlpha")
end

function DB.SectionLooks(p)
    local mods = p.modules
    if type(mods) ~= "table" then return end
    local function mod(name) return type(mods[name]) == "table" and mods[name] or nil end
    for _, scope in ipairs(DB.WINDOW_SCOPES) do
        local m = mod(scope)
        if m then boxLook(p, m, scope, "frameStyle", "windowAlphaOwn", "windowAlpha") end
    end
    if mod("Chat") then chatLook(p, mods.Chat) end
    if mod("InfoPanel") then infoPanelLook(p, mods.InfoPanel) end
    local q = mod("Quests")
    if q then boxLook(p, q, "Quests", "frameStyle", "boxAlphaOwn", "boxAlpha", "boxBorder") end
    if mod("Tooltip") then tooltipLook(p, mods.Tooltip) end
    local buffs = mod("Buffs")
    if buffs and type(buffs.settings) == "table" then
        boxLook(p, buffs, "Buffs", "settings.frameStyle", "settings.backgroundAlphaOwn", "settings.backgroundAlpha")
        if type(buffs.settings.debuff) == "table" then
            boxLook(p, buffs, "Buffs", "settings.debuff.frameStyle", "settings.debuff.backgroundAlphaOwn", "settings.debuff.backgroundAlpha")
        end
    end
    local qol = mod("QoL")
    if qol then
        for _, part in ipairs({ "lootFeed", "flight" }) do
            local color = qol[part .. "BorderColor"]
            if color ~= nil and color ~= "normal" then ownLook(p, qol, "QoL", part .. "Frame") end
            boxLook(p, qol, "QoL", part .. "Frame", part .. "AlphaOwn", part .. "Alpha", part .. "Border")
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
-- The short chat tags start from the player's language for new profiles (Chat's tagLetters
-- default is "native"). A profile that existed before keeps the English letters it has always
-- had, set once here, so nobody wakes up to new letters in party and raid chat (P becoming G...).
-- A profile still on the old default has no value saved for it (only changes are saved).
function DB.KeepEnglishTags(p)
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.modules.Chat) ~= "table" then p.modules.Chat = {} end
    if p.modules.Chat.tagLetters == nil then p.modules.Chat.tagLetters = "english" end
end

-- Rich became the tooltips' default. A profile from before keeps the Simple
-- look it had, unless it already picked Rich.
function DB.KeepSimpleTips(p)
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.modules.Tooltip) ~= "table" then p.modules.Tooltip = {} end
    if p.modules.Tooltip.style == nil then p.modules.Tooltip.style = "simple" end
end

-- Proc Alerts came after these profiles were made: they start off, and the
-- welcome offers them with a preview. One already switched on stays on.
function DB.ProcsOff(p)
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.modules.Procs) ~= "table" then p.modules.Procs = {} end
    if p.modules.Procs.enabled == nil then p.modules.Procs.enabled = false end
end

-- Nameplates used to sit 14 px above the game's spot, which left names floating
-- well over heads. New profiles start lower; one from before keeps the height
-- it had, so nobody's plates move under them.
function DB.KeepPlateHeight(p)
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.modules.Nameplates) ~= "table" then p.modules.Nameplates = {} end
    if p.modules.Nameplates.offsetY == nil then p.modules.Nameplates.offsetY = 14 end
end

-- Bar ends became one setting per end. Where one switch covered both ends,
-- the saved choice is split so each end looks as it did: the data bar's
-- angled (now its left end) gives its right end the same, and the loot
-- feed's lootFeedSlant / lootFeedSlantSide become lootFeedLeft / lootFeedRight.
function DB.SplitBarEnds(p)
    local mods = type(p.modules) == "table" and p.modules or nil
    local info = mods and type(mods.InfoPanel) == "table" and mods.InfoPanel or nil
    local bar = info and type(info.databar) == "table" and info.databar or nil
    if bar and bar.angled == false and bar.angledRight == nil then bar.angledRight = false end
    local qol = mods and type(mods.QoL) == "table" and mods.QoL or nil
    if qol and (qol.lootFeedSlant ~= nil or qol.lootFeedSlantSide ~= nil) then
        local on, side = qol.lootFeedSlant ~= false, qol.lootFeedSlantSide
        if not on or side == "right" then qol.lootFeedLeft = false end
        if not on or side == "left" then qol.lootFeedRight = false end
        qol.lootFeedSlant, qol.lootFeedSlantSide = nil, nil
    end
end

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
        if type(p) == "table" and not p.tagLetters1 then
            p.tagLetters1 = true
            DB.KeepEnglishTags(p)
        end
        if type(p) == "table" and not p.tipStyle1 then
            p.tipStyle1 = true
            DB.KeepSimpleTips(p)
        end
        if type(p) == "table" and not p.procsOff1 then
            p.procsOff1 = true
            DB.ProcsOff(p)
        end
        if type(p) == "table" and not p.plateLow1 then
            p.plateLow1 = true
            DB.KeepPlateHeight(p)
        end
        if type(p) == "table" and not p.barEnds1 then
            p.barEnds1 = true
            DB.SplitBarEnds(p)
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

-- The window bar background row once saved into windowTint, the window
-- background color. A texture name found there goes back where it belongs.
local TINTS = { daylight = true, class = true, custom = true }
function DB.WindowBackFix(p)
    local g = type(p.general) == "table" and p.general
    local v = g and g.windowTint
    if type(v) ~= "string" or TINTS[v] then return end
    if g.windowBack == nil then g.windowBack = v end
    g.windowTint = nil
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
    DB.WindowBackFix(p)
    DB.SectionLooks(p)
    DB.MergeDefaults(p.general, DB.GENERAL_DEFAULTS)
    for name, defaults in pairs(moduleDefaults) do
        if type(p.modules[name]) ~= "table" then p.modules[name] = {} end
        DB.MergeDefaults(p.modules[name], defaults)
    end
    return p
end
DB.Fill = fill

-- Where every new standard setup starts on top of the defaults: the info
-- panel closed (its tab opens the meter), the chat floating (only its
-- lines show), the micro menu in the bottom-right corner and the bars moving
-- in Flow (BarFx.HOMES). The account's first profile and every ready-made one
-- built clean (Profiles.ReadyData) use it.
function DB.StandardStart()
    local t = { InfoPanel = { meter = { enabled = false } },
                Chat = { hides = "always" },
                ActionBars = { microMenu = "shown", microMenuCorner = true } }
    if DUI.BarFx then DUI.BarFx.StartIn(t, DUI.BarFx.ASK_STYLE) end
    return t
end

-- Points every module at the active profile.
local function point()
    local pd = DB.sv.profileData
    if type(pd[DB.activeName]) ~= "table" then DB.activeName = DB.Fallback() end
    if type(pd[DB.activeName]) ~= "table" then
        -- The account's first profile. Whatever the setup guide saves comes from this.
        pd[DB.activeName] = { gradients1 = true, localFont1 = true, hiddenBars1 = true, backs1 = true, tagLetters1 = true, tipStyle1 = true, procsOff1 = true, plateLow1 = true, unsaved = true,
                              general = {},
                              modules = DB.StandardStart() }
        pd[DB.activeName].general.localFont = DB.NonLatinClient() or nil
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
    if DB.CharKey() then
        local c = DB.Character()
        c.lastSpec = DB.SpecGroup()
        -- Removed from the lists by hand (DUI.Alts.Forget), and here after all.
        c.forgotten = nil
    end
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

-- A player who likes the look as it is may never finish the setup guide, so
-- the first thing they change or move turns the stand-in into a real profile.
-- The guide's own preview doesn't count: it is undone when the guide closes.
function DB.Keep()
    if not DB.loggedIn then return end
    local p = DB.Active()
    if not p.unsaved then return end
    local D = DUI.InstallerDraft
    if D and D.Active and D.Active() then return end
    p.unsaved = nil
    DUI.Fire("ProfileKept")
end

-- Settings plugins added to Daylight UI's modules (DaylightUI.API's AddDefaults), as
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
