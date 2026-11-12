-- Profiles. Every setting lives in a profile (stored by DB.lua). Each
-- character uses one, or one per talent set with dual spec, and changes on
-- every page go into the active profile. This file handles creating,
-- renaming and deleting profiles, choosing this character's, switching when
-- talents change, and sharing a profile as text.
--
-- A profile holds the general settings, every module's settings, frame
-- positions from unlock mode, and has its own Edit Mode layout (EditMode.lua).
-- When shared it leaves out what's learned as you play (the buff bar's history
-- and spell names) and window positions tied to one screen (bags, bank,
-- spellbook, inspect window, world map).
--
-- As text it's "!DUI1_" followed by the profile packed by the game itself
-- (CBOR, compressed, then Base64 via C_EncodingUtil), so reading one back never
-- runs any code. Switching profiles takes a reload, which applies everything.

local _, DUI = ...
local Style, EditMode = DUI.Style, DUI.EditMode
local SIZE = DUI.Style.SIZE -- the text size scale
local L = DUI.L

local Profiles = {}
DUI.Profiles = Profiles

Profiles.PREFIX = "!DUI1_"
Profiles.VERSION = 1
Profiles.MAX_NAME = 32
Profiles.SWITCH_DELAY = 1 -- seconds between writing the layout and the reload, so the game can save it
-- Per module: what a shared profile leaves out (learned as you play, or tied to one screen).
Profiles.SKIP = {
    Buffs = { history = true, spells = true, learned = true },
    Bags = { position = true, ["bank.position"] = true, ["viewer.position"] = true },
    Character = { folded = true }, -- old profiles' stat folds, per character, until each logs in (Stats.Folds)
    Book = { spot = true },
    Inspect = { spot = true },
    Skins = { mapSpot = true, windowSpots = true },
}

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do
        if type(x) ~= "function" then out[k] = copy(x) end
    end
    return out
end

local function refresh()
    if DUI.OptionsPanel and DUI.OptionsPanel.Refresh then DUI.OptionsPanel.Refresh() end
end

local function data() return DUI.DB.Root().profileData end

-- A profile to share: its settings, only what differs from the defaults

function Profiles.Snapshot(name)
    local DB = DUI.DB
    name = name or DB.ActiveName()
    local src = DB.Fill(data()[name])
    local p = { v = Profiles.VERSION, general = copy(src.general), modules = {}, positions = copy(src.positions) }
    DB.StripDefaults(p.general, DB.GENERAL_DEFAULTS)
    for mod, t in pairs(src.modules) do
        if type(t) == "table" then
            local c = copy(t)
            for k in pairs(Profiles.SKIP[mod] or {}) do DB.SetPath(c, k, nil) end
            local m = DUI:GetModule(mod)
            if m and m.defaults then DB.StripDefaults(c, m.defaults) end
            p.modules[mod] = c
        end
    end
    p.layout = EditMode.Export(name) or src.pendingLayout
    return p
end

-- As text

local function codec()
    local E = C_EncodingUtil
    if type(E) == "table" and E.SerializeCBOR and E.DeserializeCBOR and E.CompressString
        and E.DecompressString and E.EncodeBase64 and E.DecodeBase64 then
        return E
    end
end

-- Packs any table into text starting with prefix (a profile, a bag's groups):
-- CBOR, compressed, Base64. Returns the text, or nil and a reason.
function Profiles.Pack(t, prefix)
    local E = codec()
    if not E then return nil, L["this game client can't pack profiles"] end
    local ok, s = pcall(E.SerializeCBOR, t)
    if ok then ok, s = pcall(E.CompressString, s) end
    if ok then ok, s = pcall(E.EncodeBase64, s) end
    if not ok or type(s) ~= "string" then return nil, L["the profile couldn't be packed"] end
    return prefix .. s
end

-- Pack's table back from text (spaces and line breaks ignored), or nil and a
-- reason: "empty", "prefix" (wrong prefix), "client" or "damaged".
function Profiles.Unpack(text, prefix)
    if type(text) ~= "string" then return nil, "empty" end
    text = string.gsub(text, "%s", "")
    if text == "" then return nil, "empty" end
    if string.sub(text, 1, #prefix) ~= prefix then return nil, "prefix" end
    local E = codec()
    if not E then return nil, "client" end
    local ok, v = pcall(E.DecodeBase64, string.sub(text, #prefix + 1))
    if ok then ok, v = pcall(E.DecompressString, v) end
    if ok then ok, v = pcall(E.DeserializeCBOR, v) end
    if not ok or type(v) ~= "table" then return nil, "damaged" end
    return v
end

function Profiles.Encode(p)
    return Profiles.Pack(p, Profiles.PREFIX)
end

-- A profile from text, or nil and a reason.
function Profiles.Decode(text)
    local v, why = Profiles.Unpack(text, Profiles.PREFIX)
    if not v then
        local said = { empty = L["nothing pasted"], prefix = L["that isn't a DaylightUI profile"],
                       client = L["this game client can't read profiles"],
                       damaged = L["the profile is damaged (was all of it copied?)"] }
        return nil, said[why]
    end
    return Profiles.Check(v)
end

-- Validates a shared profile table the way Decode does (a pack may hand one
-- over directly). Returns the profile, or nil and a reason.
function Profiles.Check(v)
    if type(v) ~= "table" then return nil, L["the profile is damaged"] end
    if type(v.v) ~= "number" or v.v > Profiles.VERSION then
        return nil, L["it's from a newer DaylightUI; update to import it"]
    end
    for _, key in ipairs({ "general", "modules", "positions" }) do
        if v[key] ~= nil and type(v[key]) ~= "table" then return nil, L["the profile is damaged"] end
    end
    -- A damaged position would leave its frame unplaced at every login, so drop it.
    for key, pos in pairs(v.positions or {}) do
        if not DUI.Movers.Valid(pos) then v.positions[key] = nil end
    end
    return v
end

-- A one-line summary of what a profile holds.
function Profiles.Summary(p)
    local names = {}
    for name in pairs(p.modules or {}) do
        local mod = DUI:GetModule(name)
        names[#names + 1] = L[mod and (mod.label or mod.name) or name]
    end
    table.sort(names)
    local parts = {}
    if p.general and next(p.general) then parts[#parts + 1] = L["appearance"] end
    if #names > 0 then parts[#parts + 1] = table.concat(names, ", ") end
    if p.positions and next(p.positions) then parts[#parts + 1] = L["frame positions"] end
    if type(p.layout) == "string" then parts[#parts + 1] = L["the Edit Mode layout"] end
    if #parts == 0 then return L["Nothing but the defaults."] end
    return string.format(L["Settings for %s."], table.concat(parts, "; "))
end

-- The profiles

-- Every saved profile's name, the standard one (DPS/Tank) first if present,
-- then A to Z. Empty until the setup guide has created one.
function Profiles.Names()
    local out = {}
    for name, p in pairs(data()) do
        if name ~= DUI.DB.DEFAULT and type(p) == "table" and not p.unsaved then out[#out + 1] = name end
    end
    table.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)
    if DUI.DB.Saved(DUI.DB.DEFAULT) then table.insert(out, 1, DUI.DB.DEFAULT) end
    return out
end

function Profiles.Current() return DUI.DB.ActiveName() end

-- A valid name for a new (or renamed) profile: the name tidied, or nil and a
-- reason. `except` is the profile being renamed, whose own name (any case) is allowed.
function Profiles.CheckName(name, except)
    name = type(name) == "string" and strtrim(name) or ""
    if name == "" then return nil, L["give it a name"] end
    if #name > Profiles.MAX_NAME then return nil, L["that name is too long"] end
    for n, p in pairs(data()) do
        if n ~= except and string.lower(n) == string.lower(name) and not (type(p) == "table" and p.unsaved) then
            return nil, string.format(L["there's a profile called %s already"], n)
        end
    end
    return name
end

-- A new profile: a copy of the active one (including its layout) or of
-- another (from), or built from a shared one (with what sharing leaves out
-- taken from the active one). Returns its name, or nil and a reason.
function Profiles.Create(name, shared, from)
    local why
    name, why = Profiles.CheckName(name)
    if not name then return nil, why end
    data()[name] = Profiles.Build(shared, from)
    return name
end

-- A shared setting of the wrong kind for its default (a word where a number
-- goes, from a hand-edited or damaged string) would error in every module
-- that reads it, so it's dropped and the default fills in. Keys with no
-- default (lists, positions, learned data) are kept. Runs after the
-- upgrades, which may still convert an old kind to the current one.
local function dropWrongKinds(t, defaults)
    for k, v in pairs(t) do
        local d = defaults[k]
        if d ~= nil then
            if type(v) ~= type(d) then
                t[k] = nil
            elseif type(d) == "table" then
                dropWrongKinds(v, d)
            end
        end
    end
end

-- A profile table built the way Create builds one, not saved anywhere yet.
-- keep is the profile that what sharing leaves out comes from (the active one
-- when not given).
function Profiles.Build(shared, from, keep)
    local DB = DUI.DB
    local current = DB.Active()
    local p
    if shared then
        p = { general = copy(shared.general) or {}, modules = copy(shared.modules) or {},
              positions = copy(shared.positions) or {}, pendingLayout = shared.layout }
        local mine = keep or current
        for mod, paths in pairs(Profiles.SKIP) do
            local from = mine.modules[mod]
            if type(from) == "table" then
                if type(p.modules[mod]) ~= "table" then p.modules[mod] = {} end
                for path in pairs(paths) do DB.SetPath(p.modules[mod], path, copy(DB.GetPath(from, path))) end
            end
        end
    else
        local src = from and DB.Fill(data()[from]) or current
        p = { general = copy(src.general), modules = copy(src.modules), positions = copy(src.positions),
              pendingLayout = EditMode.Export(from) or src.pendingLayout }
    end
    -- Created now, so it's already past the one-time gradient swap (DB.lua).
    -- Without this the next load would turn its plain "class" picks into
    -- gradients. Same for bars 5-8 (its hidden ones would show again) and the
    -- local font (a Korean or Chinese client's "off" would turn back on).
    p.gradients1 = true
    p.hiddenBars1 = true
    p.localFont1 = true
    p.backs1 = true
    -- A shared or blank profile picks up this client's font now, like a brand
    -- new profile does (DB.lua). A copy keeps the pick of the one it copies.
    if shared and DB.NonLatinClient() and p.general.localFont == nil then p.general.localFont = true end
    -- Copied from a profile that may be older than a module's upgrades, so upgrade it now.
    DB.RunUpgrades(p)
    if shared then
        dropWrongKinds(p.general, DB.GENERAL_DEFAULTS)
        for mod, t in pairs(p.modules) do
            local m = DUI:GetModule(mod)
            if type(t) == "table" and m and type(m.defaults) == "table" then dropWrongKinds(t, m.defaults) end
        end
    end
    return DB.Fill(p)
end

-- The characters ("Name-Realm") whose choices name a profile.
function Profiles.UsersOf(name)
    local out = {}
    for key, c in pairs(DUI.DB.Root().characters) do
        if type(c) == "table" and (c.profile == name or c.padProfile == name or (type(c.specProfiles) == "table"
                and (c.specProfiles[1] == name or c.specProfiles[2] == name))) then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end

-- Changes every character's choice of one profile to another (nil = unset).
local function reassign(from, to)
    for _, c in pairs(DUI.DB.Root().characters) do
        if type(c) == "table" then
            if c.profile == from then c.profile = to end
            if c.padProfile == from then c.padProfile = to end
            if type(c.specProfiles) == "table" then
                for i = 1, 2 do
                    if c.specProfiles[i] == from then c.specProfiles[i] = to end
                end
            end
        end
    end
end

-- Returns true, or false and a reason. The standard profile keeps its name.
function Profiles.Rename(old, new)
    local DB = DUI.DB
    if old == DB.DEFAULT then return false, string.format(L["%s keeps its name"], DB.DEFAULT) end
    if type(data()[old]) ~= "table" then return false, string.format(L["there's no profile called %s"], tostring(old)) end
    local why
    new, why = Profiles.CheckName(new, old)
    if not new then return false, why end
    if new == old then return true end
    local p = data()[old]
    -- Its layout is renamed too. If the game won't rename it now, a copy is kept
    -- to create the new one from.
    local ok = EditMode.RenameLayout(old, new)
    if not ok and not p.pendingLayout then p.pendingLayout = EditMode.Export(old) end
    data()[new], data()[old] = p, nil
    reassign(old, new)
    if DB.activeName == old then DB.activeName = new end
    return true
end

-- Returns true, or false and a reason. Not the active profile (switch first).
-- Characters that chose it fall back to their other choice, else the
-- standard one, else the first one left. Its Edit Mode layout stays (Edit
-- Mode can delete it).
function Profiles.Delete(name)
    local DB = DUI.DB
    if name == DB.ActiveName() then return false, L["it's the one in use; switch to another first"] end
    if type(data()[name]) ~= "table" then return false, string.format(L["there's no profile called %s"], tostring(name)) end
    data()[name] = nil
    reassign(name, nil)
    return true
end

-- This character's choice, and switching

-- The profile chosen for "character", talent set 1 or 2 (with dual spec, a
-- set with none chosen uses the character's), or "pad" (used while the
-- game's controller UI is on; Profiles.NONE when there's none).
Profiles.NONE = "none"
function Profiles.Chosen(slot)
    local c = DUI.DB.Character()
    local DB = DUI.DB
    if slot == "pad" then
        return type(c.padProfile) == "string" and data()[c.padProfile] and c.padProfile or Profiles.NONE
    end
    if slot == 1 or slot == 2 then
        local n = type(c.specProfiles) == "table" and c.specProfiles[slot]
        if type(n) == "string" and data()[n] then return n end
    end
    if type(c.profile) == "string" and data()[c.profile] then return c.profile end
    return DB.Fallback()
end

-- Quietly sets the profile for "character", talent set 1 or 2, or "pad"
-- (Profiles.NONE or nil means none).
function Profiles.Assign(slot, name)
    local c = DUI.DB.Character()
    if slot == "pad" then
        c.padProfile = name ~= Profiles.NONE and name or nil
    elseif slot == 1 or slot == 2 then
        if type(c.specProfiles) ~= "table" then c.specProfiles = {} end
        c.specProfiles[slot] = name
    else
        c.profile = name
    end
end

-- Chooses a profile for "character" or talent set 1 or 2, and asks to reload
-- if that changes which profile this character should be on now.
function Profiles.Choose(slot, name)
    Profiles.Assign(slot, name)
    refresh()
    Profiles.CheckSwitch()
end

-- The talent set a choice is made for: the active one with dual spec.
function Profiles.CurrentSlot()
    return DUI.DB.DualSpec() and DUI.DB.SpecGroup() or "character"
end

-- Ready-made profiles: the standard one with a few settings changed

Profiles.PRESETS = {
    -- The standard profile itself (DB.DEFAULT), always present, with the standard
    -- Edit Mode layout "DaylightUI - DPS/Tank" and the micro menu in the
    -- bottom-right corner.
    ["DPS/Tank"] = {
        ActionBars = { microMenu = "shown", microMenuCorner = true },
        UnitFrames = {},
    },
    -- A starting point for healers, built only from ordinary Party and Raid
    -- settings (anything here can be set by hand on those pages): the group as
    -- square tiles in a row under you, you included, with missing health shown and
    -- dispels easy to see, and a raid as the same tiles in columns. Micro menu
    -- as in DPS/Tank.
    Healer = {
        ActionBars = { microMenu = "shown", microMenuCorner = true },
        UnitFrames = {
            party = { width = 60, height = 56, spacing = 4, groupSpacing = 4, direction = "rows", perLine = 5,
                      hideSelf = false, portrait = "none", nameOnBar = true, slant = false,
                      showLevel = false, showPvP = false, bigNumber = false, showPercent = true,
                      healthText = "missing", powerHeight = 4, markerSize = 11, showDispel = true, dispelSize = 14,
                      auras = { debuffs = { show = false }, buffs = { spot = "bottomleft", grow = "right" } },
                      indicators = { show = true } },
            partyText = { name = 11, percent = 10, big = 12 },
            raid = { width = 60, height = 56, spacing = 4, groupSpacing = 4, direction = "columns", perLine = 5,
                     showPercent = true, healthText = "missing", powerHeight = 4, dispelSize = 14,
                     auras = { buffs = { show = true } }, indicators = { show = true } },
            raidText = { name = 11 },
        },
    },
    -- Calm for questing without hiding anything: the main bars dim a while after
    -- a fight, bars 3 and 4 wait for the mouse (not a target), the other side
    -- bars and your own frames float (hidden out of combat, back in combat or
    -- when something changes), and the info panel and quest tracker dim in
    -- combat. The meter only shows in a group, the minimap is slightly smaller,
    -- and NPC talk is immersive. Its General part (PRESET_GENERAL) shows
    -- everything inside dungeons, raids, battlegrounds and arenas.
    ["Immersive Preset"] = {
        ActionBars = {
            bars = {
                main = { fade = { mode = "ooc", alpha = 0.2, delay = 2 } },
                bar2 = { fade = { mode = "ooc", alpha = 0.2, delay = 2 } },
                stance = { fade = { mode = "ooc", alpha = 0.2, delay = 2 } },
                pet = { fade = { mode = "ooc", delay = 2 } },
                left = { fade = { mode = "always", target = false, delay = 2 } },
                right = { fade = { mode = "always", target = false, delay = 2 } },
                bar5 = { fade = { mode = "float", delay = 2 } },
                bar6 = { fade = { mode = "float", delay = 2 } },
                bar7 = { fade = { mode = "float", delay = 2 } },
                bar8 = { fade = { mode = "float", delay = 2 } },
                possess = { fade = { mode = "float", delay = 2 } },
                totem = { fade = { mode = "float", delay = 2 } },
            },
        },
        UnitFrames = {
            player = { fade = { mode = "float", delay = 2 } },
            pet = { fade = { mode = "float", delay = 2 } },
            party = { fade = { mode = "float", delay = 2 } },
            raid = { fade = { mode = "float", delay = 2 } },
            personal = { fade = { mode = "float", delay = 2 } },
            target = { fade = { delay = 2 } },
            targettarget = { fade = { delay = 2 } },
            focus = { fade = { delay = 2 } },
        },
        Buffs = {
            settings = { fade = { mode = "float", delay = 2 }, debuff = { fade = { mode = "float" } } },
        },
        InfoPanel = {
            fade = { mode = "combat", alpha = 0.5, delay = 1.5 },
            threat = { fade = { mode = "float" } },
            meter = { enabled = false }, -- folded; one click on the panel's tab brings it out
            map = { size = 204 },
            xp = { showPercent = true },
        },
        Quests = { fade = { mode = "combat", alpha = 0.5, delay = 1.5 } },
        NPC = { look = "immersive" }, -- talking to NPCs: the card beside them, camera over your shoulder
    },
}
-- A ready-made profile's General settings (PRESETS holds its modules').
Profiles.PRESET_GENERAL = {
    ["Immersive Preset"] = { fadeOpenWorldOnly = true },
}
-- Where its frames start (unlock mode's center offsets from the middle of the
-- screen); each can be moved freely after that. The healer layout as set up
-- in game: player and target on either side of a full raid, level with its
-- top rows, the pet past the player, target of target under the target, and
-- party and raid centered below (they never show at the same time).
Profiles.PRESET_POSITIONS = {
    Healer = {
        ["unitframes.player"] = { -351.8, -143.9 }, ["unitframes.target"] = { 351.8, -143.9 },
        ["unitframes.pet"] = { -576.3, -143.9 }, ["unitframes.targettarget"] = { 304.5, -208.5 },
        ["unitframes.party"] = { 0, -253 }, ["unitframes.raid"] = { 0, -253 },
    },
}
-- The UIParent size those were set up on (2560x1600 at a raised UI scale). On
-- a smaller screen the chat and tracker, pinned to the corners at their own
-- size, take up more of it, so the spots there are pulled in with the width
-- and keep their height above the bottom (over the chat and action bars).
Profiles.PRESET_SCREEN = { 1705.6, 1066 }
-- Once pulled in, the player row no longer fits beside a full raid (8
-- columns, 508 wide), so it goes above it, all lifted together: the first key
-- no lower than "rise" above the raid's center (a full raid's half height,
-- 148, plus how far the row reaches below that key, 76 down to the bottom of
-- the target of target, plus a gap).
Profiles.PRESET_OVER = {
    Healer = { under = "unitframes.raid", rise = 228,
               keys = { "unitframes.player", "unitframes.target", "unitframes.pet", "unitframes.targettarget" } },
}

-- screen: the UIParent size the spots were set up on (a pack's own; ours when
-- not given).
local function fitToScreen(key, at, screen)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local refW, refH = (screen or Profiles.PRESET_SCREEN)[1], (screen or Profiles.PRESET_SCREEN)[2]
    -- The game returns sizes slightly off; treat the screen it was made on as equal.
    local narrower = w < refW - 1
    local function fit(v)
        local x, y = v[1], v[2]
        if narrower then x = x * w / refW end
        if h < refH then y = y + (refH - h) / 2 end
        local out = copy(v)
        out[1], out[2] = x, y
        return out
    end
    local out = {}
    for k, v in pairs(at) do out[k] = fit(v) end
    local over = Profiles.PRESET_OVER[key]
    local first = over and out[over.keys[1]]
    if narrower and first and out[over.under] then
        local lift = out[over.under][2] + over.rise - first[2]
        if lift > 0 then
            for _, k in ipairs(over.keys) do
                if out[k] then out[k][2] = out[k][2] + lift end
            end
        end
    end
    return out
end

local function merge(into, from)
    for k, v in pairs(from) do
        if type(v) == "table" then
            if type(into[k]) ~= "table" then into[k] = {} end
            merge(into[k], v)
        else
            into[k] = v
        end
    end
end

-- Creates a ready-made profile, built clean (Profiles.ReadyData) and named
-- after it. If it already exists, that one is used as is (and the unsaved
-- stand-in is saved from now on). Returns its name, or nil and a reason. as
-- creates it under that name instead (the setup guide's own copy of one not
-- created yet, which leaves the ready-made one uncreated).
function Profiles.AddPreset(key, as)
    local entry = Profiles.PackOf(key)
    if entry then return Profiles.AddPackProfile(entry, as) end
    if not Profiles.PRESETS[key] then return nil, string.format(L["there's no ready-made profile called %s"], tostring(key)) end
    local have = data()[as or key]
    if type(have) == "table" then
        have.unsaved = nil
        return as or key
    end
    local name, why = Profiles.CheckName(as or key)
    if not name then return nil, why end
    data()[name] = Profiles.ReadyData(key)
    return name
end

-- Profile packs: ready-made profiles that another addon provides

-- Another addon (a pack, like ElvUI's UI packs) can provide profiles made with
-- DaylightUI, as share strings (/dui export) or tables, through
-- DaylightUI.RegisterPack. They're offered alongside ours in the setup guide
-- and on the Profiles page, created only when picked (Profiles.AddPreset) and
-- used as is after that, like Healer. Reading a pack runs no code. Its extras
-- (setting up other addons) are its own code, run on the setup guide's Finish
-- unless the player turns them off.
--
-- DaylightUI.RegisterPack("MyPack", {
--     label = "My UI", author = "Me", version = "1.2", website = "...",
--     desc = "One line on what it is.",
--     screen = { 1920, 1080 },     -- UIParent size it was made on; positions are pulled in on smaller screens
--     updates = "offer",           -- "never" (default): once created, a profile belongs to the player
--     profiles = { { name = "My UI Healer", text = "!DUI1_...", sub = "One line.", role = "Healer" } },
--     extras = { { addon = "Details", label = "Details!", apply = function() ... end } },
-- })

Profiles.PACKS, Profiles.PACK_ORDER = {}, {}
Profiles.PACK_ROLES = { ["DPS/Tank"] = true, Healer = true, ["Immersive Preset"] = true } -- the drawings a pack profile can use
local packOf = {} -- pack profile name, lowercased -> its entry

-- A mistake by a pack author: raise an error naming the call, pointing at their file.
local function packError(text) error("DaylightUI.RegisterPack: " .. text, 3) end

local function str(v) return type(v) == "string" and v ~= "" and v or nil end

-- Called as DaylightUI.RegisterPack(id, spec) or
-- DaylightUI:RegisterPack(id, spec), like RegisterModule.
function Profiles.RegisterPack(id, spec, extra)
    if id == DUI then id, spec = spec, extra end
    if not str(id) then packError("the pack needs an id (a string)") end
    if Profiles.PACKS[id] then packError(string.format("there's a pack called %s already", id)) end
    if type(spec) ~= "table" or type(spec.profiles) ~= "table" or #spec.profiles == 0 then
        packError("the pack needs profiles = { { name = ..., text = ... } }")
    end
    local screen = spec.screen
    if not (type(screen) == "table" and type(screen[1]) == "number" and type(screen[2]) == "number"
            and screen[1] > 0 and screen[2] > 0) then
        screen = nil
    end
    local pack = { id = id, label = str(spec.label) or id, author = str(spec.author), website = str(spec.website),
                   desc = str(spec.desc), version = spec.version, screen = screen and { screen[1], screen[2] },
                   updates = spec.updates == "offer" and "offer" or "never", profiles = {}, extras = {} }
    if pack.version ~= nil and type(pack.version) ~= "string" and type(pack.version) ~= "number" then
        packError("version is a string or a number")
    end
    for _, e in ipairs(spec.profiles) do
        local name = type(e) == "table" and type(e.name) == "string" and strtrim(e.name) or ""
        if name == "" then packError("each profile needs a name") end
        if #name > Profiles.MAX_NAME then
            packError(string.format("%s is longer than %d letters", name, Profiles.MAX_NAME))
        end
        if not (str(e.text) or type(e.data) == "table") then
            packError(string.format("%s needs text (a share string from /dui export) or data", name))
        end
        local low = string.lower(name)
        for ours in pairs(Profiles.PRESETS) do
            if string.lower(ours) == low then packError(string.format("%s is one of DaylightUI's own", name)) end
        end
        if packOf[low] then
            -- Two packs that both include it: the player's setup, not a mistake.
            DUI.Print(string.format(L["%s: %s comes with %s already, so it's left out."], pack.label, name,
                packOf[low].pack.label))
        else
            local entry = { name = name, text = str(e.text), data = e.data, sub = str(e.sub), pack = pack,
                            role = Profiles.PACK_ROLES[e.role] and e.role or nil }
            pack.profiles[#pack.profiles + 1] = entry
            packOf[low] = entry
        end
    end
    for _, x in ipairs(type(spec.extras) == "table" and spec.extras or {}) do
        if type(x) ~= "table" or not str(x.addon) or type(x.apply) ~= "function" then
            packError("each extra needs addon (its folder name) and apply (a function)")
        end
        pack.extras[#pack.extras + 1] = { addon = x.addon, label = str(x.label) or x.addon, apply = x.apply, pack = pack }
    end
    Profiles.PACKS[id] = pack
    Profiles.PACK_ORDER[#Profiles.PACK_ORDER + 1] = id
    DUI.Fire("PacksChanged", id)
    return pack
end
DUI.RegisterPack = Profiles.RegisterPack

-- A pack profile's entry by name (any case), or nil.
function Profiles.PackOf(name)
    return type(name) == "string" and packOf[string.lower(name)] or nil
end

-- A pack profile's settings, read once. Returns the profile, or nil and a
-- reason. One that can't be read says so in chat once, naming the pack.
function Profiles.PackProfile(entry)
    if entry.decoded then return entry.decoded end
    if entry.bad then return nil, entry.bad end
    local p, why
    if entry.text then
        p, why = Profiles.Decode(entry.text)
    else
        local t = copy(entry.data)
        if t.v == nil then t.v = Profiles.VERSION end
        p, why = Profiles.Check(t)
    end
    if not p then
        entry.bad = why
        DUI.Print(string.format(L["%s: %s can't be read (%s), so it's left out."], entry.pack.label, entry.name, tostring(why)))
        return nil, why
    end
    entry.decoded = p
    return p
end

-- A pack's readable profiles, in its order.
function Profiles.PackProfiles(pack)
    local out = {}
    for _, e in ipairs(pack.profiles) do
        if Profiles.PackProfile(e) then out[#out + 1] = e end
    end
    return out
end

-- Every readable pack profile, pack by pack.
function Profiles.PackNames()
    local out = {}
    for _, id in ipairs(Profiles.PACK_ORDER) do
        for _, e in ipairs(Profiles.PackProfiles(Profiles.PACKS[id])) do out[#out + 1] = e.name end
    end
    return out
end

-- Whether name is a ready-made profile, ours or a pack's.
function Profiles.IsReady(name)
    return Profiles.PRESETS[name] ~= nil or Profiles.PackOf(name) ~= nil
end

-- Every ready-made profile's name: ours, then the packs'.
function Profiles.ReadyNames()
    local out = {}
    for name in pairs(Profiles.PRESETS) do out[#out + 1] = name end
    table.sort(out)
    for _, name in ipairs(Profiles.PackNames()) do out[#out + 1] = name end
    return out
end

-- The positions a pack profile brings, fitted to this screen when the pack
-- says which one it was made on.
local function packPositions(entry, p)
    local at = p.positions or {}
    if entry.pack.screen then return fitToScreen(nil, at, entry.pack.screen) end
    return copy(at)
end

-- A ready-made profile's table (ours or a pack's), not saved anywhere yet.
-- Always built clean from the defaults plus its own settings and positions,
-- never copied from the saved DPS/Tank (a player may have changed that, and
-- every new character would get those changes under a card that shows the
-- standard layout). Returns nil and a reason on failure.
function Profiles.ReadyData(key)
    local entry = Profiles.PackOf(key)
    if entry then
        local p, why = Profiles.PackProfile(entry)
        if not p then return nil, why end
        local t = Profiles.Build(p)
        t.positions = packPositions(entry, p)
        t.fromPack = { id = entry.pack.id, name = entry.name, version = entry.pack.version }
        return t
    end
    local preset = Profiles.PRESETS[key]
    if not preset then return nil, string.format(L["there's no ready-made profile called %s"], tostring(key)) end
    local t = Profiles.Build({ general = {}, modules = DUI.DB.StandardStart(), positions = {},
                               layout = EditMode.Export(DUI.DB.DEFAULT) })
    merge(t.modules, preset)
    if Profiles.PRESET_GENERAL[key] then merge(t.general, Profiles.PRESET_GENERAL[key]) end
    local at = Profiles.PRESET_POSITIONS[key]
    if at then
        for k, v in pairs(fitToScreen(key, at)) do t.positions[k] = v end
    end
    return t
end

-- Replaces a saved profile's contents in place (the active profile is this
-- very table, and the caller reloads into it). Its module tables are new, so
-- modules are pointed at them and a change made before that reload (prompt
-- answered with Later) isn't lost.
function Profiles.Replace(name, new)
    local t = data()[name]
    if type(t) ~= "table" then return end
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(new) do t[k] = v end
    if name == DUI.DB.ActiveName() then DUI.DB.Repoint() end
end

-- Creates a pack's profile, like AddPreset does for ours (under its name, or
-- `as`; an existing one is used as is). Returns its name, or nil and a reason.
function Profiles.AddPackProfile(entry, as)
    local name = as or entry.name
    local have = data()[name]
    if type(have) == "table" then
        have.unsaved = nil
        return name
    end
    local why
    name, why = Profiles.CheckName(name)
    if not name then return nil, why end
    local t
    t, why = Profiles.ReadyData(entry.name)
    if not t then return nil, why end
    data()[name] = t
    return name
end

-- The pack entry a saved profile can be updated to, when its pack offers
-- updates and has a different version than the one it was made from.
function Profiles.PackUpdate(name)
    local t = data()[name]
    local from = type(t) == "table" and t.fromPack
    if type(from) ~= "table" then return nil end
    local entry = Profiles.PackOf(from.name)
    local pack = entry and entry.pack
    if not (pack and pack.id == from.id and pack.updates == "offer") then return nil end
    if pack.version == nil or pack.version == from.version then return nil end
    if not Profiles.PackProfile(entry) then return nil end
    return entry
end

-- Updates a profile made from a pack to the pack's version. Its settings and
-- frame positions become the pack's (the player's changes to them are lost),
-- what sharing leaves out stays, and its Edit Mode layout is kept. The active
-- profile asks to reload. Returns true, or false and a reason.
function Profiles.UpdateFromPack(name)
    local entry = Profiles.PackUpdate(name)
    if not entry then return false, L["there's nothing newer to bring in"] end
    local p = Profiles.PackProfile(entry)
    local t = data()[name]
    local new = Profiles.Build(p, nil, DUI.DB.Fill(t))
    new.positions = packPositions(entry, p)
    new.pendingLayout = t.pendingLayout
    new.fromPack = { id = entry.pack.id, name = entry.name, version = entry.pack.version }
    -- In place, since the active profile is this very table.
    Profiles.Replace(name, new)
    if name == DUI.DB.ActiveName() then Profiles.AskReload() end
    return true
end

-- Bringing action bar positions into a new profile

-- Whether "name" (the active profile when not given) has moved a bar in unlock
-- mode, which is worth offering to a ready-made profile that would otherwise
-- start from DPS/Tank (DaylightUI_ActionBars/Layout.lua stores them as
-- "actionbars.<key>" in the profile's positions).
function Profiles.HasBarPositions(name)
    local p = data()[name or DUI.DB.ActiveName()]
    if type(p) ~= "table" then return false end
    for k in pairs(DUI.DB.Fill(p).positions) do
        if string.match(k, "^actionbars%.") then return true end
    end
    return false
end

-- Copies every "actionbars.*" position from one profile to another,
-- overwriting only those and leaving the rest of "to" as is. A bar's spot and
-- the old bars' spot the new action bars kept for it ("actionbars.old.<bar>",
-- DaylightUI_ActionBars/Bars.lua) travel together; copying one without the
-- other drops the other's.
function Profiles.CopyActionBarPositions(from, to)
    local src, dst = data()[from], data()[to]
    if type(src) ~= "table" or type(dst) ~= "table" then return end
    DUI.DB.Fill(src)
    DUI.DB.Fill(dst)
    for k, v in pairs(src.positions) do
        if string.match(k, "^actionbars%.") then dst.positions[k] = copy(v) end
    end
    for k in pairs(src.positions) do
        local bar = string.match(k, "^actionbars%.([^%.]+)$")
        if bar and src.positions["actionbars.old." .. bar] == nil then dst.positions["actionbars.old." .. bar] = nil end
    end
end

-- Adds a ready-made profile (Profiles.AddPreset). It always starts from the
-- standard setup, so a character on its own profile would lose that profile's
-- action bar arrangement. When there's one to bring along, ask first (Accept
-- copies it). Returns right away like Profiles.AddPreset; the question, if
-- any, follows after.
function Profiles.AddPresetOffering(key)
    local isNew = type(data()[key]) ~= "table"
    local from = Profiles.Current()
    local made, why = Profiles.AddPreset(key)
    if made and isNew and from ~= DUI.DB.DEFAULT and Profiles.HasBarPositions(from) then
        StaticPopupDialogs.DAYLIGHTUI_PROFILE_BARS = StaticPopupDialogs.DAYLIGHTUI_PROFILE_BARS or {
            text = "%s", button1 = YES or L["Yes"], button2 = NO or L["No"],
            OnAccept = function(_, d) Profiles.CopyActionBarPositions(d.from, d.to) end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("DAYLIGHTUI_PROFILE_BARS",
            string.format(L["Copy %s's action bar positions into %s too?"], from, made), nil, { from = from, to = made })
    end
    return made, why
end

-- If this character should be on another profile now (its choice or talents
-- changed), asks to reload into it. "Later" leaves it for the next reload or
-- login, which picks it anyway.
function Profiles.CheckSwitch(text)
    local want = DUI.DB.Pick()
    if want == DUI.DB.ActiveName() then return end
    StaticPopupDialogs.DAYLIGHTUI_PROFILE = StaticPopupDialogs.DAYLIGHTUI_PROFILE or {
        text = "%s", button1 = RELOADUI or L["Reload"], button2 = LATER or L["Later"],
        OnAccept = function(_, name) Profiles.SwitchNow(name, true) end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("DAYLIGHTUI_PROFILE", string.format(text or L["Switch to the profile %s?"], want)
        .. " " .. L["It takes a reload."], nil, want)
end

-- ReloadUI is blocked unless a click calls it directly, so anything that had
-- to wait (the layout save, combat) ends with this button instead.
function Profiles.AskReload()
    local I = DUI.Installer
    if I and I.HoldReload and I.HoldReload(Profiles.AskReload) then return end
    StaticPopupDialogs.DAYLIGHTUI_PROFILE_RELOAD = StaticPopupDialogs.DAYLIGHTUI_PROFILE_RELOAD or {
        text = L["The profile is ready. Reload to use it."], button1 = RELOADUI or L["Reload"],
        button2 = LATER or L["Later"], OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("DAYLIGHTUI_PROFILE_RELOAD")
end

-- Installs the profile's Edit Mode layout, then reloads, and the reload picks
-- the profile itself (DB.Pick). A layout that can't be set now is set after
-- the reload instead (EditMode.lua). `clicked` means this was called straight
-- from one of the game's own popup buttons, so an instant reload is allowed
-- (the game blocks it from our buttons and from timers). It reloads in that
-- click with the layout just written (the game keeps it over a reload, and if
-- it didn't, the load check puts it in place). Otherwise a Reload button is
-- shown.
function Profiles.SwitchNow(name, clicked)
    if InCombatLockdown() then
        DUI.Print(L["Switching profile after combat."])
        DUI.AfterCombat(function() Profiles.SwitchNow(name) end, "profile switch")
        return
    end
    -- The controller UI keeps its own Edit Mode layouts, and installing ours then
    -- crashes the game (EditMode.GamepadMode), so just reload.
    if DUI.DB.PadUI() then
        if clicked then ReloadUI() return end
        C_Timer.After(0, Profiles.AskReload)
        return
    end
    local ok, why = EditMode.UseProfile(name)
    if not ok then DUI.Print(string.format(L["The profile's Edit Mode layout will be set after the reload (%s)."], tostring(why))) end
    if clicked then ReloadUI() return end
    C_Timer.After(ok and Profiles.SWITCH_DELAY or 0, Profiles.AskReload)
end

-- Talents swapped: switch to the new set's profile if it's different.
function Profiles.OnTalentsChanged()
    DUI.DB.AdoptOldKeys()
    DUI.DB.Character().lastSpec = DUI.DB.SpecGroup()
    Profiles.CheckSwitch(L["These talents use the profile %s. Switch to it?"])
end

pcall(DUI.RegisterEvent, "ACTIVE_TALENT_GROUP_CHANGED", function() Profiles.OnTalentsChanged() end)

-- The game's controller UI was turned on or off (Settings > Gameplay >
-- Gamepad): switch to or from its controller profile if that's different.
function Profiles.OnPadChanged()
    Profiles.CheckSwitch(DUI.DB.PadUI() and L["Controller mode uses the profile %s. Switch to it?"]
        or L["Without the controller, this character uses the profile %s. Switch to it?"])
end

pcall(DUI.RegisterEvent, "INPUT_DEVICE_INTERFACE_TRANSITION", function() Profiles.OnPadChanged() end)

-- In case the game didn't know the talent set at login, run the same check
-- once in the world.
local entered = false
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if entered then return end
    entered = true
    Profiles.OnTalentsChanged()
end)

-- A one-line question with a text box (a new profile's name, a rename)

function Profiles.Prompt(text, initial, onAccept) DUI.Widgets.Prompt(text, initial, onAccept) end

-- fail is the whole sentence, with a hole for the reason ("Couldn't rename it: %s.").
local function said(ok, why, fail)
    if ok then return true end
    DUI.Print(string.format(fail, tostring(why)))
    return false
end

function Profiles.AskNew()
    Profiles.Prompt(string.format(L["A name for the new profile (a copy of %s):"], Profiles.Current()), "", function(name)
        local made, why = Profiles.Create(name)
        if said(made, why, L["Couldn't make it: %s."]) then
            DUI.Print(string.format(L["Made the profile %s. Choose it for this character to use it."], made))
            refresh()
        end
    end)
end

function Profiles.AskRename(old)
    Profiles.Prompt(string.format(L["Rename the profile %s to:"], old), old, function(name)
        if name == old then return end
        local ok, why = Profiles.Rename(old, name)
        if said(ok, why, L["Couldn't rename it: %s."]) then refresh() end
    end)
end

-- The share window: a profile to copy, or a place to paste one

Profiles.BOX = { 520, 320 }
Profiles.WRAP = 64 -- characters per line in the window (a profile has no spaces to wrap at)

local box

-- A profile's text split into lines so it fits the box. Reading ignores spaces
-- and line breaks, so copying it this way still works.
function Profiles.Wrap(s)
    s = string.gsub(s or "", "%s", "")
    local out = {}
    for i = 1, #s, Profiles.WRAP do out[#out + 1] = string.sub(s, i, i + Profiles.WRAP - 1) end
    return table.concat(out, "\n")
end

local function buildBox()
    local W = DUI.Widgets
    local C = W.COLORS
    box = CreateFrame("Frame", "DaylightUIProfileBox", UIParent)
    DUI.Movers.FollowScale(box)
    box:SetSize(Profiles.BOX[1], Profiles.BOX[2])
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    -- Above the options window, which is itself a dialog (and comes to the front
    -- when clicked).
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetToplevel(true)
    box:EnableMouse(true)
    Style.Shell(box)
    -- The window kit's title row: title, X, accent line.
    local Win = DUI.Win
    local E = Win.EDGE
    Win.Header(box, { compact = true, onClose = function() DUI.Motion.Vanish(box) end })
    box.x = box.close -- the header's X (box.close is the footer's Close)
    box.hint = W.Font(box, W.BODY, SIZE.small, C.dim, "LEFT")
    box.hint:SetPoint("TOPLEFT", box, "TOPLEFT", E, -Win.COMPACT - 4)
    box.hint:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    -- The scrolling text.
    local area = W.TextArea(box, { width = Profiles.BOX[1] - 2 * E, onEscape = function() DUI.Motion.Vanish(box) end })
    area:SetPoint("TOPLEFT", box.hint, "BOTTOMLEFT", 0, -14)
    area:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    area:SetPoint("BOTTOM", box, "BOTTOM", 0, 70)
    box.area, box.edit = area, area.edit
    box.status = W.Font(box, W.BODY, SIZE.small, C.dim, "LEFT")
    box.status:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", E, 46)
    box.status:SetPoint("RIGHT", box, "RIGHT", -E, 0)
    box.close = W.Button(box, CLOSE or L["Close"], 26)
    box.close:SetWidth(100)
    box.close:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -E, 12)
    box.close:SetScript("OnClick", function() DUI.Motion.Vanish(box) end)
    box.go = W.Button(box, L["Import"], 26)
    box.go:SetWidth(120)
    box.go.SetActive(true)
    box.go:SetPoint("RIGHT", box.close, "LEFT", -8, 0)
    -- The name an imported profile is saved under.
    local name = W.Input(box, { hint = L["Name this profile"] })
    name:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", E, 12)
    name:SetPoint("RIGHT", box.go, "LEFT", -8, 0)
    name:SetScript("OnEscapePressed", function(self) self:ClearFocus(); DUI.Motion.Vanish(box) end)
    box.name = name
    box:Hide()
    -- Glides in, fades out (Escape too).
    DUI.Motion.Window(box, 6)
end

local function showBox(title, hint)
    if not box then buildBox() end
    DUI.Win.Repaint(box) -- the accent line in the current accent
    box.title:SetText(title)
    box.hint:SetText(hint)
    box.status:SetText("")
    box.edit:SetScript("OnTextChanged", nil)
    box:Show()
    box:Raise()
    return box
end

function Profiles.ShowExport()
    local text, why = Profiles.Encode(Profiles.Snapshot())
    local b = showBox(L["Export profile"], string.format(L["The profile %s: its settings, frame positions and Edit Mode layout. "
        .. "Ctrl+C to copy, then share it."], Profiles.Current()))
    b.go:Hide()
    b.name:Hide()
    text = text and Profiles.Wrap(text)
    b.edit:SetText(text or "")
    b.status:SetText(text and "" or string.format(L["Couldn't export: %s."], tostring(why)))
    -- Typing can't change it: restore the profile text, selected.
    if text then b.area.Lock(text, true) end
    b.edit:SetFocus()
    b.edit:HighlightText()
end

-- The same box for any text to copy out (a report to send in), selected and
-- read-only.
function Profiles.ShowText(title, hint, text)
    local b = showBox(title, hint)
    b.go:Hide()
    b.name:Hide()
    b.edit:SetText(text)
    b.area.Lock(text, true)
    b.edit:SetFocus()
    b.edit:HighlightText()
end

local currentSlot = Profiles.CurrentSlot

function Profiles.ShowImport()
    local b = showBox(L["Import profile"], L["Paste a DaylightUI profile (Ctrl+V) and name it. It becomes a new profile, "
        .. "chosen for this character (these talents, with dual spec); yours stay as they are."])
    b.go:Show()
    b.go.text:SetText(L["Import"]) -- ShowPaste may have changed its label
    b.name:Show()
    b.name:SetText("")
    b.edit:SetText("")
    local pending
    local function named() return strtrim(b.name:GetText() or "") end
    local function ready() b.go:SetAlpha((pending and named() ~= "") and 1 or 0.4) end
    local function check(_, user)
        -- Pasted as one long line: shown in lines so it fits the box.
        local now = b.edit:GetText()
        if user and #now > Profiles.WRAP and not string.find(now, "\n", 1, true) then
            b.edit:SetText(Profiles.Wrap(now))
            return
        end
        local p, why = Profiles.Decode(b.edit:GetText())
        pending = p
        local W = DUI.Widgets
        if p then
            b.status:SetText(Profiles.Summary(p))
            W.TextColor(b.status, W.COLORS.text)
        else
            b.status:SetText(b.edit:GetText() == "" and "" or string.format(L["Can't import: %s."], why))
            W.TextColor(b.status, W.COLORS.warn)
        end
        ready()
    end
    b.edit:SetScript("OnTextChanged", check)
    b.name:SetScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        ready()
    end)
    local function warn(text)
        b.status:SetText(text)
        DUI.Widgets.TextColor(b.status, DUI.Widgets.COLORS.warn)
    end
    local function go()
        if not pending then return end
        if named() == "" then
            warn(L["Give it a name first."])
            b.name:SetFocus()
            return
        end
        local made, why = Profiles.Create(named(), pending)
        if not made then
            warn(string.format(L["Can't import: %s."], tostring(why)))
            return
        end
        b:Hide()
        DUI.Print(string.format(L["Imported the profile %s."], made))
        Profiles.Choose(currentSlot(), made)
    end
    b.go:SetScript("OnClick", go)
    b.name:SetScript("OnEnterPressed", go)
    check()
    b.edit:SetFocus()
end

-- The same box for any other text to paste in (the Cooldown Manager's layout
-- strings). spec = { title, hint, read = fn(text) -> what, summary | nil, why;
-- button = fn(what) -> its label; go = fn(what) -> nil | why }. There's no
-- name to give, and it closes once go accepts.
function Profiles.ShowPaste(spec)
    local b = showBox(spec.title, spec.hint)
    local W = DUI.Widgets
    b.go:Show()
    b.name:Hide()
    b.edit:SetText("")
    local pending
    local function label(what)
        b.go.text:SetText(spec.button and spec.button(what) or L["Import"])
    end
    local function check(_, user)
        local now = b.edit:GetText()
        if user and #now > Profiles.WRAP and not string.find(now, "\n", 1, true) then
            b.edit:SetText(Profiles.Wrap(now))
            return
        end
        local what, said = spec.read(now)
        pending = what
        if what then
            b.status:SetText(said or "")
            W.TextColor(b.status, W.COLORS.text)
        else
            b.status:SetText(now == "" and "" or string.format(L["Can't import: %s."], tostring(said)))
            W.TextColor(b.status, W.COLORS.warn)
        end
        label(what)
        b.go:SetAlpha(what and 1 or 0.4)
    end
    b.edit:SetScript("OnTextChanged", check)
    b.go:SetScript("OnClick", function()
        if not pending then return end
        local why = spec.go(pending)
        if why then
            b.status:SetText(string.format(L["Can't import: %s."], tostring(why)))
            W.TextColor(b.status, W.COLORS.warn)
            return
        end
        DUI.Motion.Vanish(b)
    end)
    check()
    b.edit:SetFocus()
    return b
end

-- The Profiles page

local LINE = 34

local function choices()
    local values, keys = {}, Profiles.Names()
    for _, n in ipairs(keys) do values[n] = n end
    return values, keys
end

local function chooser(slot, label, desc, hidden)
    return { type = "dropdown", label = label, desc = desc, choices = choices, hidden = hidden,
             get = function() return Profiles.Chosen(slot) end,
             set = function(v) Profiles.Choose(slot, v) end }
end

local function dual() return DUI.DB.DualSpec() end
local function single() return not DUI.DB.DualSpec() end

-- The profiles, each with Rename and Delete. "New" copies the active one.
local list = {
    type = "custom", label = "Profiles",
    build = function(row)
        local W = DUI.Widgets
        local C = W.COLORS
        row.new = W.Button(row, L["New profile"], 26)
        row.new:SetWidth(140)
        row.new:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8)
        row.new:SetScript("OnClick", function() Profiles.AskNew() end)
        row.newHint = W.Font(row, W.BODY, SIZE.small, C.dim, "LEFT")
        row.newHint:SetPoint("LEFT", row.new, "RIGHT", 12, 0)
        row.newHint:SetText(L["A copy of the one in use, layout and all."])
        row.lines = {}
    end,
    update = function(row)
        local W = DUI.Widgets
        local C = W.COLORS
        local names = Profiles.Names()
        local current = Profiles.Current()
        for i, n in ipairs(names) do
            local line = row.lines[i]
            if not line then
                line = CreateFrame("Frame", nil, row)
                line:SetHeight(LINE)
                line.label = W.Font(line, W.BODY, SIZE.body, C.text, "LEFT")
                line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
                line.tag = W.Font(line, W.BODY, SIZE.small, C.dim, "LEFT")
                line.tag:SetPoint("LEFT", line.label, "RIGHT", 8, 0)
                line.delete = W.Button(line, DELETE or L["Delete"], 24)
                line.delete:SetWidth(90)
                line.delete:SetPoint("RIGHT", line, "RIGHT", 0, 0)
                line.rename = W.Button(line, L["Rename"], 24)
                line.rename:SetWidth(90)
                line.rename:SetPoint("RIGHT", line.delete, "LEFT", -8, 0)
                row.lines[i] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -(44 + (i - 1) * LINE))
            line:SetPoint("RIGHT", row, "RIGHT", -W.PAD, 0)
            line.label:SetText(n)
            local users = #Profiles.UsersOf(n)
            local tag = n == current and L["in use"] or ""
            if users > 0 then
                local who = string.format(users == 1 and L["%d character"] or L["%d characters"], users)
                tag = tag ~= "" and string.format(L["%s, %s"], tag, who) or who
            end
            line.tag:SetText(tag ~= "" and ("(" .. tag .. ")") or "")
            line.rename:SetShown(n ~= DUI.DB.DEFAULT)
            line.delete:SetShown(n ~= current)
            line.rename:SetScript("OnClick", function() Profiles.AskRename(n) end)
            -- Deleting loses it, so it takes a second click.
            W.Confirm(line.delete, DELETE or L["Delete"], function()
                local ok, why = Profiles.Delete(n)
                if said(ok, why, L["Couldn't delete it: %s."]) then refresh() end
            end)
            line:Show()
        end
        for i = #names + 1, #row.lines do row.lines[i]:Hide() end
        row.count = #names
    end,
    height = function(row) return 44 + (row.count or #Profiles.Names()) * LINE + 6 end,
}

-- A pack's card: its author, then an Add button per profile (and Update when
-- the pack offers updates and has a newer one than the profile was made from).
local function packGroup(pack)
    local by = pack.author and string.format(L["By %s."], pack.author) or nil
    local desc = by and pack.desc and (by .. " " .. pack.desc) or by or pack.desc
    local items = {}
    for _, e in ipairs(Profiles.PackProfiles(pack)) do
        items[#items + 1] = { type = "button", label = e.name, text = "Add",
            desc = (e.sub and (e.sub .. " ") or "") .. "Made the first time you add it; after that, the one you have is used as it is. Choose it above to use it.",
            hidden = function() return type(data()[e.name]) == "table" and Profiles.PackUpdate(e.name) ~= nil end,
            func = function()
                local made, why = Profiles.AddPresetOffering(e.name)
                if said(made, why, L["Couldn't add it: %s."]) then
                    DUI.Print(string.format(L["The profile %s is ready. Choose it for this character (or a talent set) to use it."], made))
                    refresh()
                end
            end }
        if pack.updates == "offer" then
            items[#items + 1] = { type = "button", label = e.name, text = "Update", confirm = true,
                desc = "Brings in the pack's newer version of this profile: its settings and frame positions replace yours. Your Edit Mode layout stays as it is.",
                hidden = function() return Profiles.PackUpdate(e.name) == nil end,
                func = function()
                    local ok, why = Profiles.UpdateFromPack(e.name)
                    if said(ok, why, L["Couldn't update it: %s."]) then
                        DUI.Print(string.format(L["%s now has %s's newest settings."], e.name, pack.label))
                        refresh()
                    end
                end }
        end
    end
    if #items == 0 then return nil end
    return { label = pack.label, desc = desc, items = items }
end

local function profileGroups(base)
    local groups = {}
    for _, g in ipairs(base) do
        groups[#groups + 1] = g
        if g.label == "Ready-made" then
            for _, id in ipairs(Profiles.PACK_ORDER) do
                groups[#groups + 1] = packGroup(Profiles.PACKS[id])
            end
        end
    end
    return groups
end

local PAGE_GROUPS -- the page's own cards, with the packs' placed among them
local profilesPage = DUI.Options.RegisterPage({
    id = "profiles", section = "core", label = "Profiles", scope = "general", defaults = DUI.DB.GENERAL_DEFAULTS,
    desc = "Each character uses a profile (one per talent set, with dual spec). Everything on every page changes the profile in use.",
    groups = {
        { label = "This character", items = {
            { type = "text", label = function() return string.format(L["In use: %s"], Profiles.Current()) end },
            chooser("character", "Profile", "The profile this character uses. Changing it asks to reload.", dual),
            chooser(1, "Primary talents", "The profile for your first talent set. Changing it asks to reload.", single),
            chooser(2, "Secondary talents", "The profile for your second talent set; swapping talents asks to switch.", single),
            { type = "dropdown", label = "Controller mode", since = "1.7.0",
              desc = "The profile this character uses while the game's controller UI is on (Settings > Gameplay > Gamepad). Turning it on or off asks to switch. None: the same profile as without it.",
              choices = function()
                  local values, keys = choices()
                  values[Profiles.NONE] = NONE or L["None"]
                  table.insert(keys, 1, Profiles.NONE)
                  return values, keys
              end,
              get = function() return Profiles.Chosen("pad") end,
              set = function(v) Profiles.Choose("pad", v) end },
        } },
        { label = "Profiles", desc = "Kept for every character on this account, each with its own Edit Mode layout.",
          items = { list } },
        { label = "Ready-made", desc = "Built from DPS/Tank (the standard profile) the first time you add one; after that, the one you have is used as it is.", items = {
            { type = "button", label = "Healer", text = "Add",
              desc = "DPS/Tank with your party and raid as square tiles under you (you included, missing health on them, dispels easy to see), and your frame and your target's raised a little. Everything it sets is on the Party and Raid pages; move any of them in unlock mode. Choose it above to use it. "
                  .. "If the profile you're on has moved action bars, offers to bring them along.",
              func = function()
                  local made, why = Profiles.AddPresetOffering("Healer")
                  if said(made, why, L["Couldn't add it: %s."]) then
                      DUI.Print(string.format(L["The profile %s is ready. Choose it for this character (or a talent set) to use it."], made))
                      refresh()
                  end
              end },
            { type = "button", label = "Immersive Preset", text = "Add",
              desc = "DPS/Tank made calm for questing: your action bars and your own frame fade a while after a fight (back under the mouse, in a fight or when you're hurt), the damage meter starts folded (one click on the panel's tab brings it out), the minimap is a little smaller and the XP bar shows its percent. Nothing fades in dungeons, raids, battlegrounds or arenas (General > Appearance, Fade only in the open world). Choose it above to use it. "
                  .. "If the profile you're on has moved action bars, offers to bring them along.",
              func = function()
                  local made, why = Profiles.AddPresetOffering("Immersive Preset")
                  if said(made, why, L["Couldn't add it: %s."]) then
                      DUI.Print(string.format(L["The profile %s is ready. Choose it for this character (or a talent set) to use it."], made))
                      refresh()
                  end
              end },
        } },
        { label = "Share", desc = "Settings, frame positions and the Edit Mode layout; not what's learned as you play.", items = {
            { type = "button", label = "Export", text = "Export",
              desc = "The profile in use as text to copy and share.", func = function() Profiles.ShowExport() end },
            { type = "button", label = "Import", text = "Import",
              desc = "Paste someone's profile. It becomes a new profile; yours stay as they are.",
              func = function() Profiles.ShowImport() end },
        } },
    },
})
-- A card per pack under Ready-made. Packs register as their addons load,
-- before the window first draws the page (like the Gradients page's late pairs).
PAGE_GROUPS = profilesPage.groups
DUI.On("PacksChanged", function() profilesPage.groups = profileGroups(PAGE_GROUPS) end)

DUI.RegisterCommand("export", function() Profiles.ShowExport() end, L["/dui export - the profile in use as text to share"])
DUI.RegisterCommand("import", function() Profiles.ShowImport() end, L["/dui import - add a shared DaylightUI profile"])
