-- Soft UI sounds. Quiet "shh" sounds (Media/sounds/shh-*.ogg, made by
-- tools/make_sounds.py) replace the game's for windows, menus and toggles,
-- and a low "nope" replaces the error voice lines QoL quiets (Errors.lua).
-- One master switch (general.sounds), then one choice per kind (Sound.KINDS).
-- The game plays UI sounds by kit (PlaySound). A post-hook on that global
-- (hooksecurefunc keeps it secure) plays ours for the kits in Sound.REPLACE,
-- and the files those kits play are muted with MuteSoundFile, as the whisper
-- sound does. A mute lasts until the game restarts, so it's redone at every
-- login, and an account flag tracks which mutes are ours so only those are
-- ever lifted. Ours play on the sound effects channel, so the game's volume
-- and mute settings apply.

local _, DUI = ...

local Sound = {}
DUI.Sound = Sound

-- A changed sound needs a new file name. The game caches sounds until it
-- restarts, so /reload would keep playing the old file.
local DIR = "Interface\\AddOns\\DaylightUI\\Media\\sounds\\shh-"
Sound.FILES = { open = DIR .. "open.ogg", close = DIR .. "close.ogg", toggle = DIR .. "toggle.ogg",
                click = DIR .. "click.ogg", snap = DIR .. "snap.ogg", nope = DIR .. "nope.ogg",
                quest = DIR .. "quest3.ogg", apply = DIR .. "apply.ogg", done = DIR .. "done.ogg",
                campfire = DIR .. "campfire.ogg", flare = DIR .. "flare.ogg", -- QoL Campfire.lua: the crackle loop and the flare
                splash = DIR .. "splash.ogg", -- QoL Fishing.lua: a fish bites
                spend = DIR .. "spend.ogg", refund = DIR .. "refund.ogg", gone = DIR .. "gone.ogg" }
Sound.GAP = 0.1 -- min seconds between the same sound (a window and its game kit are heard once)

-- Each sound's kind. One choice per kind (general.soundKinds.<kind>): "soft"
-- (ours, the game's muted), "game" (the game's own, unmuted, and ours play the
-- matching kit in Sound.GAME_KIT) or "none" (muted, nothing plays). A sound
-- with no kind (nope has QoL's own switch, quest the tracker's) follows only
-- the master switch.
-- apply: something big went through (talents, a talent set). done: something
-- small (a spell learned, a letter sent). gone: a W.Confirm went through.
-- spend, refund: a talent point spent or taken back.
Sound.KINDS = { open = "windows", close = "windows", click = "clicks", toggle = "toggles", snap = "snaps",
                spend = "clicks", refund = "clicks", apply = "confirms", done = "confirms", gone = "confirms" }
-- The game's kit for each of ours under "game" (none for snap or confirms, which stay ours or none).
Sound.GAME_KIT = { open = "IG_CHARACTER_INFO_OPEN", close = "IG_CHARACTER_INFO_CLOSE",
                   click = "IG_MAINMENU_OPTION", toggle = "IG_MAINMENU_OPTION_CHECKBOX_ON",
                   spend = "IG_MAINMENU_OPTION", refund = "IG_MAINMENU_OPTION" }

-- Game sound files we mute, each with every kit that plays it. A muted file
-- goes silent for all of them, so each one plays ours instead. Kits are by
-- SOUNDKIT name, or by number for the few without a name. Sources: wago.tools
-- SoundKitEntry and the forever branch's SoundKitConstants.
-- Left out: the checkbox file (567407, shared by 100+ kits, many not UI) and
-- the page turn (shared with dozens of unnamed kits).
Sound.GAME = {
    { file = 567507, ours = "open", kits = {   -- character info open
        "HOUSING_BLUEPRINTS_EXPORT_OPEN", "HOUSING_BULLETIN_BOARD_OPEN", "HOUSING_CHARTER_OPEN",
        "HOUSING_CORNERSTONE_FOR_SALE_OPEN", "HOUSING_CORNERSTONE_OWNED_OPEN",
        "HOUSING_CREATE_NEIGHBORHOOD_CHARTER_OPEN", "HOUSING_CREATE_NEIGHBORHOOD_GUILD_OPEN",
        "HOUSING_DASHBOARD_OPEN", "HOUSING_HOUSE_FINDER_OPEN", "HOUSING_MARKET_TOPUP_FLOW_PANEL_OPEN",
        "HOUSING_PLACED_DECOR_LIST_OPEN", "IG_CHARACTER_INFO_OPEN", "UI_70_CHALLENGE_MODE_SOCKET_PAGE_OPEN",
        "UI_9_0_CRAFTING_CLOSE_REAGENT_WINDOW", "UI_CLASS_TALENT_OPEN_WINDOW", "UI_EXPANSION_LANDING_PAGE_OPEN",
        "UI_GARRISON_9_0_OPEN_LANDING_PAGE", "UI_GARRISON_ARCHITECT_TABLE_OPEN", "UI_GARRISON_COMMAND_TABLE_OPEN",
        "UI_GARRISON_MONUMENTS_OPEN", "UI_GARRISON_SHIPMENTS_WINDOW_OPEN", "UI_MAJOR_FACTION_RENOWN_OPEN_WINDOW",
        "UI_ORDERHALL_TALENT_WINDOW_OPEN", "UI_PLAYER_CHOICE_GENERIC_SHOW_POWERS", "UI_PROFESSIONS_WINDOW_OPEN", 679,
        232464, 293906, 301856, 329518, 336981, 371620, 372142,
    } },
    { file = 567433, ours = "close", kits = {   -- character info close
        "HOUSING_BLUEPRINTS_IMPORT_CLOSE", "HOUSING_BULLETIN_BOARD_CLOSE", "HOUSING_CHARTER_CLOSE",
        "HOUSING_CORNERSTONE_FOR_SALE_CLOSE", "HOUSING_CORNERSTONE_OWNED_CLOSE",
        "HOUSING_CREATE_NEIGHBORHOOD_CHARTER_CLOSE", "HOUSING_CREATE_NEIGHBORHOOD_GUILD_CLOSE",
        "HOUSING_DASHBOARD_CLOSE", "HOUSING_HOUSE_FINDER_CLOSE", "HOUSING_PLACED_DECOR_LIST_CLOSE",
        "HOUSING_SETTINGS_SAVE_BUTTON", "IG_CHARACTER_INFO_CLOSE", "UI_70_CHALLENGE_MODE_SOCKET_PAGE_CLOSE",
        "UI_9_0_CRAFTING_CLICK_OPTIONAL_REAGENT_SLOT", "UI_CLASS_TALENT_CLOSE_WINDOW",
        "UI_COVENANT_SANCTUM_TAB_CLICK", "UI_EXPANSION_LANDING_PAGE_CLOSE", "UI_GARRISON_9_0_CLOSE_LANDING_PAGE",
        "UI_GARRISON_ARCHITECT_TABLE_CLOSE", "UI_GARRISON_COMMAND_TABLE_CLOSE",
        "UI_GARRISON_COMMAND_TABLE_MISSION_CLOSE", "UI_GARRISON_MONUMENTS_CLOSE",
        "UI_GARRISON_SHIPMENTS_WINDOW_CLOSE", "UI_MAJOR_FACTION_RENOWN_CLOSE_WINDOW",
        "UI_ORDERHALL_TALENT_WINDOW_CLOSE", "UI_PLAYER_CHOICE_GENERIC_HIDE_POWERS", "UI_PROFESSIONS_WINDOW_CLOSE",
        "UI_PVP_HONOR_PRESTIGE_WINDOW_CLOSE", 680, 301857, 329523, 334651, 371622, 372143,
    } },
    { file = 567440, ours = "open", kits = {   -- spellbook open
        "IG_ABILITY_OPEN", "IG_SPELLBOOK_OPEN", 603, 754, 3190, 3371, 4734, 21966, 21968, 338622,
    } },
    { file = 567496, ours = "close", kits = {   -- spellbook close
        "IG_ABILITY_CLOSE", "IG_SPELLBOOK_CLOSE", 604, 3191, 3372, 4735, 21967, 282446, 334761, 336326,
    } },
    { file = 567461, ours = "open", kits = {   -- backpack open
        "IG_BACKPACK_OPEN", "UI_CONTAINER_ITEM_OPEN", 117, 616, 685, 859,
    } },
    { file = 567512, ours = "close", kits = {   -- backpack close
        "IG_BACKPACK_CLOSE", 617, 686, 860,
    } },
    { file = 567504, ours = "open", kits = {   -- quest log open
        "IG_QUEST_LIST_OPEN", "IG_QUEST_LOG_OPEN", "PHOTO_SHARING_PREVIEW_OPEN",
        "UI_72_BUILDING_CONTRIBUTION_TABLE_OPEN", "UI_COVENANT_ANIMA_DIVERSION_OPEN", "UI_JOURNEYS_OPEN_LORE_BOOK",
        620, 170823, 231366, 239463,
    } },
    { file = 567508, ours = "close", kits = {   -- quest log close
        "IG_QUEST_CANCEL", "IG_QUEST_LIST_CLOSE", "IG_QUEST_LIST_SELECT", "IG_QUEST_LOG_CLOSE",
        "PHOTO_SHARING_PREVIEW_CLOSE", "UI_72_BUILDINGS_CONTRIBUTION_TABLE_CLOSE",
        "UI_COVENANT_ANIMA_DIVERSION_CLOSE", "UI_JOURNEYS_CLOSE_LORE_BOOK", 621,
    } },
    { file = 567490, ours = "open", kits = {   -- game menu open
        "IG_MAINMENU_OPEN", 88, 682, 882,
    } },
    { file = 567464, ours = "close", kits = {   -- game menu close
        "IG_MAINMENU_CLOSE", 89, 683,
    } },
    { file = 567481, ours = "click", kits = {   -- game menu option
        "BEHAVIORAL_NOTIFICATION_TY", "IG_CHAT_EMOTE_BUTTON", "IG_MAINMENU_CONTINUE", "IG_MAINMENU_LOGOUT",
        "IG_MAINMENU_OPTION", "IG_MAINMENU_QUIT", "UI_72_BUILDINGS_CONTRIBUTE_POWER_MENU_CLICK",
        "UI_COVENANT_CHOICE_CLICK_BACK_BUTTON", "UI_IG_STORE_CANCEL_BUTTON", 624, 15962, 272320, 305149, 347845,
    } },
    { file = 567422, ours = "click", kits = {   -- character tab
        "HOUSING_HOUSE_FINDER_PLOT_SELECT", "IG_CHARACTER_INFO_TAB", "UI_CLASS_TALENT_TAB", "UI_GARRISON_NAV_TABS",
        "UI_PLAYER_CHOICE_GENERIC_POWER", "UI_TOYBOX_TABS", 681, 43785, 301864, 305112, 313849, 316468, 325714,
        325721, 330007,
    } },
}

-- [kit name or number] = { ours = a Sound.FILES name, files = { fileDataID, ... } }.
Sound.REPLACE = {}
for _, g in ipairs(Sound.GAME) do
    for _, kit in ipairs(g.kits) do
        local r = Sound.REPLACE[kit]
        if not r then r = { ours = g.ours, files = {} }; Sound.REPLACE[kit] = r end
        r.files[#r.files + 1] = g.file
    end
end

local last = {}
local byKit = {}
local mutedNow = {} -- [fileDataID] = true when muted by us this session

function Sound.On()
    local g = DUI.DB and DUI.DB.General and DUI.DB.General()
    return not (g and g.sounds == false)
end

-- "soft" | "game" | "none" for one of ours. Master switch off means "game".
function Sound.Mode(name)
    if not Sound.On() then return "game" end
    local kind = Sound.KINDS[name]
    if not kind then return "soft" end
    local g = DUI.DB and DUI.DB.General and DUI.DB.General()
    local mode = g and type(g.soundKinds) == "table" and g.soundKinds[kind]
    if mode == "game" or mode == "none" then return mode end
    return "soft"
end

-- The same sound plays at most once per GAP, whoever played it first.
local function fresh(name)
    local now = GetTime()
    if last[name] and now - last[name] < Sound.GAP then return false end
    last[name] = now
    return true
end

function Sound.Play(name)
    local file = Sound.FILES[name]
    if not file then return end
    local mode = Sound.Mode(name)
    if mode == "none" then return end
    if mode == "game" then
        -- Our windows and buttons play the game's matching kit, but only while the
        -- master switch is on. Off means we stay out of it entirely.
        local kit = Sound.On() and type(SOUNDKIT) == "table" and SOUNDKIT[Sound.GAME_KIT[name]]
        if type(kit) == "number" and type(PlaySound) == "function" and fresh(name) then
            pcall(PlaySound, kit)
        end
        return
    end
    if type(PlaySoundFile) ~= "function" or not fresh(name) then return end
    pcall(PlaySoundFile, file, "SFX")
end

-- The game's own sound for a moment its window had that ours took over (a
-- repair's anvil, the quill). The game code that plays it never runs behind
-- our window. name is its SOUNDKIT name. kind is a Sound.KINDS kind whose
-- "none" silences it (nil means it always plays, like bag sorting). Called
-- every frame, it still plays at most once per GAP.
function Sound.Kit(name, kind)
    local kit = type(SOUNDKIT) == "table" and SOUNDKIT[name]
    if type(kit) ~= "number" or type(PlaySound) ~= "function" then return end
    if kind and Sound.On() then
        local g = DUI.DB and DUI.DB.General and DUI.DB.General()
        if g and type(g.soundKinds) == "table" and g.soundKinds[kind] == "none" then return end
    end
    if fresh("kit:" .. name) then pcall(PlaySound, kit) end
end

-- Plays one of ours on repeat. Each copy fades in and out so a copy every
-- `every` seconds blends into one continuous sound. Returns nil when it
-- wouldn't play (Soft UI sounds off). Stop it with Sound.StopLoop(loop, fade).
function Sound.Loop(name, every)
    local file = Sound.FILES[name]
    if not file or Sound.Mode(name) ~= "soft" or type(PlaySoundFile) ~= "function" then return nil end
    local loop = { handles = {} }
    local function again()
        if loop.stopped or Sound.Mode(name) ~= "soft" then return end -- stopped, or sounds turned off
        local ok, _, handle = pcall(PlaySoundFile, file, "SFX")
        if ok and handle then
            local h = loop.handles
            h[#h + 1] = handle
            if #h > 2 then table.remove(h, 1) end -- only the last two can still be playing
        end
        C_Timer.After(every, again)
    end
    again()
    return loop
end

-- Alert sounds: what a player picks for a moment in a fight (the Cooldown
-- Manager's per-spell sounds). Saved as a string: "none", "dui:<Sound.FILES
-- name>", "file:<file id>", "kit:<sound kit>" (the game's Cooldown Manager
-- list) or "lsm:<name>" (shared media). These aren't UI sounds, so
-- general.sounds doesn't apply. Files play on Master so a low effects slider
-- or a busy fight (which drops effects first) can't swallow them. Kits play
-- the way the game's Cooldown Manager plays them (playKit), because
-- PlaySound(kit, "Master") was silent for them in game.
Sound.ALERT_CHANNEL = "Master"
Sound.ALERT_SUBTYPE = "Gameplay SFX"    -- CooldownViewer.lua TriggerAlertEvent
Sound.ALERT_KIT_CHANNEL = "SFX" -- fallback, the channel kits are known to work on (Chat Whisper)
-- Short, sharp "it's ready" sounds from the game, listed first. Proc is what
-- the game plays when a proc lights up (SpellActivationOverlay.lua). These are
-- file ids, not kits, because a kit carries its own volume (Proc's kit 23287
-- is 0.025 and was silent in game, Full charge's is 0.25) while a file plays
-- at full volume. From Forever's SoundKit tables (build 1.60.1.70790).
Sound.ALERT_PUNCHY = { { 568016, "Proc" }, { 1489541, "Full charge" }, { 567458, "Alarm" }, { 567397, "Raid warning" },
                       { 567394, "Boss warning" }, { 567409, "Ready check" }, { 567416, "Ping" }, { 1489459, "Rank up" } }
Sound.ALERT_OWN = { { "quest", "Chime" }, { "done", "Soft bell" }, { "apply", "Swell" }, { "snap", "Snap" } }
-- The game's sound categories, clearest for combat first. "Short" is left
-- out: it names 26 kits this client doesn't have (no SoundKit row in build
-- 1.60.1.70790, while every other category has all of them), and those
-- played nothing. Recheck that before adding it back.
Sound.ALERT_CATEGORIES = { "Instruments", "Impacts", "War3", "War2", "Devices", "Animals" }

-- Built each time the list opens since shared media arrives as addons load.
-- Returns values, order, titles (headings for W.OpenMenu).
function Sound.AlertChoices()
    local values, order, titles = { none = "None" }, { "none" }, {}
    local function add(key, text)
        values[key] = text
        order[#order + 1] = key
    end
    local function head(key, text)
        add("head:" .. key, text)
        titles["head:" .. key] = true
    end
    head("punchy", "Punchy")
    for _, s in ipairs(Sound.ALERT_PUNCHY) do add("file:" .. s[1], s[2]) end
    head("own", "Daylight UI")
    for _, s in ipairs(Sound.ALERT_OWN) do add("dui:" .. s[1], s[2]) end
    -- The game's own list, read live: CooldownViewerSoundData lives in its
    -- Cooldown Manager addon and is the same list its settings offer.
    local data, cats = _G.CooldownViewerSoundData, type(Enum) == "table" and Enum.CooldownViewerSoundCategory
    if type(data) == "table" and type(cats) == "table" then
        for _, name in ipairs(Sound.ALERT_CATEGORIES) do
            local list = data[cats[name]]
            if type(list) == "table" then
                head(name, _G["COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_" .. string.upper(name)] or name)
                for _, s in ipairs(list) do
                    if type(s.soundKitID) == "number" then add("kit:" .. s.soundKitID, s.text or tostring(s.soundKitID)) end
                end
            end
        end
    end
    local Media = DUI.Media
    if Media then
        local names, keys = Media.List("sound")
        if #keys > 0 then
            head("shared", "Shared media")
            for _, key in ipairs(keys) do add(key, names[key]) end
        end
    end
    return values, order, titles
end

function Sound.IsAlert(key)
    if key == "none" then return true end
    if type(key) ~= "string" then return false end
    return string.find(key, "^dui:.") ~= nil or string.find(key, "^kit:%d+$") ~= nil or string.find(key, "^file:%d+$") ~= nil or string.find(key, "^lsm:.") ~= nil
end

-- The game's own call for its kits (CooldownViewerAlert_PlaySoundAlert).
local function playKit(kit)
    local S = C_Sound
    if type(S) == "table" and type(S.PlaySoundWithOptions) == "function" then
        local played, handle = S.PlaySoundWithOptions({ soundKitID = kit, uiSoundSubType = Sound.ALERT_SUBTYPE })
        if played then return handle end
    end
    if type(PlaySound) == "function" then
        local _, handle = PlaySound(kit, Sound.ALERT_KIT_CHANNEL)
        return handle
    end
end

-- SafeCall rather than pcall so a refused sound still reaches BugSack.
local function shown(fn, ...)
    local handle
    local args = { ... }
    DUI.SafeCall(function() handle = fn(unpack(args)) end)
    return handle
end

local function playFile(file)
    if type(PlaySoundFile) ~= "function" then return end
    local _, handle = PlaySoundFile(file, Sound.ALERT_CHANNEL)
    return handle
end

-- Returns the sound's handle (Sound.AlertSample stops it), or nil if nothing played.
function Sound.Alert(key)
    if type(key) ~= "string" then return end
    local kind, what = string.match(key, "^(%a+):(.+)$")
    if kind == "kit" then return shown(playKit, tonumber(what)) end
    if kind == "file" then return shown(playFile, tonumber(what)) end
    local file
    if kind == "dui" then
        file = Sound.FILES[what]
    elseif kind == "lsm" then
        local lsm = DUI.Media and DUI.Media.Lib()
        if lsm then
            local ok, path = pcall(lsm.Fetch, lsm, "sound", what, true)
            file = ok and path or nil
        end
    end
    -- Shared media holds both file paths and kit numbers (1 is its silent entry).
    if type(file) == "number" then
        if file ~= 1 then return shown(playKit, file) end
    elseif file then
        return shown(playFile, file)
    end
end

-- Previewing a sound in the list. Only the newest request plays and it cuts
-- off the previous one, so long sounds can't pile up. A pick waits PICK_WAIT
-- (letting the menu's own click play first), and hovering a row waits
-- HOVER_WAIT so sweeping the mouse down the list stays quiet until it rests.
Sound.PICK_WAIT, Sound.HOVER_WAIT = 0.25, 0.15
local sampleAsk, samplePlaying = 0, nil
function Sound.AlertSample(key, wait)
    sampleAsk = sampleAsk + 1
    local ask = sampleAsk
    C_Timer.After(wait or Sound.PICK_WAIT, function()
        if ask ~= sampleAsk then return end
        if samplePlaying and type(StopSound) == "function" then pcall(StopSound, samplePlaying) end
        samplePlaying = Sound.Alert(key)
    end)
end

-- A list row under the mouse. Headings and None have nothing to preview.
function Sound.AlertHover(key)
    if key ~= "none" and Sound.IsAlert(key) then Sound.AlertSample(key, Sound.HOVER_WAIT) end
end

-- Stops a loop. Copies still playing fade out over `fade` seconds.
function Sound.StopLoop(loop, fade)
    if type(loop) ~= "table" or loop.stopped then return end
    loop.stopped = true
    if type(StopSound) ~= "function" then return end
    for _, h in ipairs(loop.handles) do pcall(StopSound, h, math.floor((fade or 0) * 1000)) end
end

-- Mutes every replaced kit's files unless its kind is set to the game's own,
-- and unmutes the rest, right away. Only files we muted are ever unmuted,
-- never one another addon muted. The account's uiSoundsMuted ({ [file id] =
-- true }) carries ours over a /reload, since a mute lasts until the game
-- restarts. Older versions saved just true, so in that case every replaced
-- file counts as ours this one time.
function Sound.ApplyMutes()
    local root = DUI.DB.Root()
    local saved = root.uiSoundsMuted
    local old = saved == true
    if type(saved) ~= "table" then saved = {} end
    local want = {}
    for _, r in pairs(Sound.REPLACE) do
        local muted = Sound.Mode(r.ours) ~= "game"
        for _, id in ipairs(r.files) do want[id] = want[id] or muted end
    end
    for id, muted in pairs(want) do
        if muted then
            if not mutedNow[id] and type(MuteSoundFile) == "function" then
                pcall(MuteSoundFile, id)
                mutedNow[id] = true
            end
            saved[id] = true
        elseif mutedNow[id] or saved[id] or old then
            if type(UnmuteSoundFile) == "function" then pcall(UnmuteSoundFile, id) end
            mutedNow[id] = nil
            saved[id] = nil
        end
    end
    -- Lift our mutes on kits no longer replaced (an update dropped them).
    for id in pairs(saved) do
        if want[id] == nil then
            if type(UnmuteSoundFile) == "function" then pcall(UnmuteSoundFile, id) end
            mutedNow[id] = nil
            saved[id] = nil
        end
    end
    root.uiSoundsMuted = next(saved) and saved or nil
end

-- The game played a replaced kit. Under "soft" play ours; otherwise just note
-- it so ours right after isn't heard twice. Never PlaySound from here: under
-- "game" ours plays a kit, which would land back in this hook.
local function onPlaySound(kit)
    if type(kit) ~= "number" then return end
    local r = byKit[kit]
    if not r then return end
    if Sound.Mode(r.ours) == "soft" then Sound.Play(r.ours) else fresh(r.ours) end
end

function Sound.Enable()
    if Sound.enabled then return end
    Sound.enabled = true
    if type(SOUNDKIT) == "table" then
        for name, r in pairs(Sound.REPLACE) do
            local id = type(name) == "number" and name or SOUNDKIT[name]
            if type(id) == "number" then byKit[id] = r end
        end
    end
    if type(PlaySound) == "function" then hooksecurefunc("PlaySound", onPlaySound) end
    Sound.ApplyMutes()
end

DUI.On("Login", Sound.Enable)
-- Plays a kind's choice once, shortly after picking it (after the menu's own click).
Sound.SAMPLE = { windows = "open", clicks = "click", toggles = "toggle", snaps = "snap", confirms = "apply" }
function Sound.Sample(kind)
    local name = Sound.SAMPLE[kind]
    if not name then return end
    C_Timer.After(0.25, function() last[name] = nil; Sound.Play(name) end)
end

DUI.On("SettingChanged", function(scope, path)
    if scope ~= "general" or type(path) ~= "string" then return end
    if path == "sounds" or path:find("^soundKinds") then Sound.ApplyMutes() end
end)
