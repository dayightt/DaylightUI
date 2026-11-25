-- Data texts: a thin strip of short texts (gold, durability, bag space,
-- friends online...) under the minimap. Each one is a label and a number,
-- with a tooltip on hover and a window on click. All texts live in
-- DataTexts.TEXTS and redraw on game events. Only fps, clock and coords
-- poll, and only while slotted. The strip is parented to the panel so it
-- fades with it; the panel grows by DataTexts.Room.

local _, ns = ...
local DUI = DaylightUI
local isSecret = DUI.IsSecret
local L = DUI.L
local Style, Pixel = DUI.Style, DUI.Pixel

local DT = {}
ns.DataTexts = DT

DT.MAX = 5                    -- max slots (the count option allows 3-5)
DT.PAD_Y = 6                  -- strip height beyond the text size
DT.MIN_GAP = 8                -- min space between texts before labels drop
DT.POLL = 0.5                 -- seconds between redraws for texts with no event
DT.LABEL = DUI.Style.INK.LABEL
DT.VALUE = DUI.Tips.VALUE
DT.WARN = DUI.Tips.WARN           -- running low (worn gear, few bag slots)
DT.BAD = DUI.Tips.BAD             -- nearly out (gear about to break, bags full)
DT.GOOD = DUI.Tips.GOOD
DT.HINT = DUI.Tips.HINT           -- tooltip "Click: ..." lines
DT.SEP = { 0.72, 0.70, 0.66, 0.28 }   -- divider between two texts
DT.TIP_LINES = 20             -- longest list in a tooltip (friends, guild, characters)
DT.TIP_GAP = 4                -- gap between strip and tooltip
DT.ICON_UP = 2                -- icon size above the text size
DT.ICON_GAP = 5
DT.GAIN = DUI.Style.INK.MONEY  -- color while gold counts up

-- Slots the durability text checks, with the character window's names.
DT.GEAR = { { 1, HEADSLOT or L["Head"] }, { 3, SHOULDERSLOT or L["Shoulders"] }, { 5, CHESTSLOT or L["Chest"] }, { 6, WAISTSLOT or L["Waist"] }, { 7, LEGSSLOT or L["Legs"] },
            { 8, FEETSLOT or L["Feet"] }, { 9, WRISTSLOT or L["Wrists"] }, { 10, HANDSSLOT or L["Hands"] }, { 16, MAINHANDSLOT or L["Main hand"] }, { 17, SECONDARYHANDSLOT or L["Off hand"] },
            { 18, RANGEDSLOT or L["Ranged"] } }
DT.BAGS = { 0, 1, 2, 3, 4 }
-- Thresholds where durability (percent) and free bag slots turn amber, then red.
DT.GEAR_WARN, DT.GEAR_BAD = DUI.Tips.WEAR_WARN, DUI.Tips.WEAR_BAD
DT.BAGS_WARN, DT.BAGS_BAD = 4, 0
DT.AMMO_WARN, DT.AMMO_BAD = 200, 50

-- Test mode values, picked so every warning color shows at once.
DT.SAMPLE = { money = 1234567, durability = 18, bagsFree = 3, bagsTotal = 80, friends = 4, guild = 17,
              fps = 120, ms = 38, xp = 64, x = 45.2, y = 61.8, ammo = 140 }

local function sample()
    return DUI.testMode == true and DUI.TestPartShown("datatexts")
end
DT.Sample = sample

DUI.RegisterTestPart("datatexts", "Data texts", 92, function()
    local db = ns.module and ns.module.db
    return db ~= nil and (db.data.enabled == true or db.databar.enabled == true)
end)

-- ---------------------------------------------------------------------
-- Text pieces
-- ---------------------------------------------------------------------

local function hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
end
local function word(s) return hex(DT.LABEL) .. s .. "|r" end
-- The color a slot's number is drawn in, read at draw time. "accent" (the
-- default) follows the accent, and with a gradient accent the slot's `spot`,
-- how far along the strip it sits. A dark class accent on the dark strip is
-- hard to read, so the strip can take white, the class color or one color.
function DT.Ink(s)
    local kind = s and s.ink
    if kind == "white" then
        local c = DUI.Style.INK.VALUE
        return c[1], c[2], c[3]
    elseif kind == "class" then
        local _, token = UnitClass("player")
        return DUI.Style.ClassTextColor(token)
    elseif kind == "custom" and type(s.inkCustom) == "table" then
        local c = s.inkCustom
        return c[1] or 1, c[2] or 1, c[3] or 1
    end
    return DUI.Style.AccentAt(s and s.spot)
end

local cur   -- the slot being drawn
local function value(s, c) return hex(c or { DT.Ink(cur) }) .. s .. "|r" end
DT.Word, DT.Value = word, value   -- used by Broker.lua

local function thousands(n) return DUI.Thousands(math.floor(n)) end

local function coin(kind) return DUI.CoinIcon(kind) end

-- Whole gold only. Silver or copper only show when under one gold.
function DT.ShortMoney(copper)
    copper = (type(copper) == "number" and copper > 0) and math.floor(copper) or 0
    local gold = math.floor(copper / 10000)
    if gold > 0 then return thousands(gold) .. coin("gold") end
    local silver = math.floor(copper / 100) % 100
    if silver > 0 then return silver .. coin("silver") end
    return (copper % 100) .. coin("copper")
end

-- Calls a game function if it exists. Returns nothing on error.
local function pass(ok, ...) if ok then return ... end end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return pass(pcall(fn, ...))
end

local function api(space, name)
    local t = _G[space]
    return type(t) == "table" and t[name] or nil
end

-- nil for secret values (chat lockdown can hide names). Secrets can't be
-- compared or cut, so those lines are skipped.
local function known(v)
    if isSecret(v) then return nil end
    return v
end
local function num(v) v = known(v) return type(v) == "number" and v or 0 end

-- ---------------------------------------------------------------------
-- Readers (all of these stay plain in combat)
-- ---------------------------------------------------------------------

function DT.ReadMoney()
    if sample() then return DT.SAMPLE.money end
    return num(call(_G.GetMoney))
end

-- Lowest durability percent (nil if nothing wears) and the per-slot list.
function DT.ReadDurability()
    if sample() then return DT.SAMPLE.durability, {} end
    local low, list = nil, {}
    for _, g in ipairs(DT.GEAR) do
        local cur, max = call(_G.GetInventoryItemDurability, g[1])
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            local pct = math.floor(cur / max * 100 + 0.5)
            list[#list + 1] = { name = g[2], pct = pct }
            if not low or pct < low then low = pct end
        end
    end
    return low, list
end

-- Free and total slots, not counting profession bags, plus a per-bag list.
function DT.ReadBags()
    if sample() then return DT.SAMPLE.bagsFree, DT.SAMPLE.bagsTotal, {} end
    local free, total, list = 0, 0, {}
    local slotsOf = api("C_Container", "GetContainerNumSlots")
    local freeOf = api("C_Container", "GetContainerNumFreeSlots")
    local nameOf = api("C_Container", "GetBagName")
    for _, bag in ipairs(DT.BAGS) do
        local n = num(call(slotsOf, bag))
        if n > 0 then
            local f, family = call(freeOf, bag)
            f = num(f)
            local plain = type(family) ~= "number" or family == 0
            if plain then free, total = free + f, total + n end
            local name = call(nameOf, bag)
            list[#list + 1] = { name = type(name) == "string" and name or (bag == 0 and L["Backpack"] or string.format(L["Bag %d"], bag)),
                                free = f, total = n, plain = plain }
        end
    end
    return free, total, list
end

-- Online friends, character and Battle.net combined.
function DT.ReadFriends()
    if sample() then return DT.SAMPLE.friends end
    local wow = num(call(api("C_FriendList", "GetNumOnlineFriends")))
    local _, bnet = call(_G.BNGetNumFriends)
    return wow + num(bnet)
end

-- Guild members online, or nil when not in a guild.
function DT.ReadGuild()
    if sample() then return DT.SAMPLE.guild end
    if call(_G.IsInGuild) ~= true then return nil end
    local _, online = call(_G.GetNumGuildMembers)
    return num(online)
end

function DT.ReadSystem()
    if sample() then return DT.SAMPLE.fps, DT.SAMPLE.ms end
    local fps = num(call(_G.GetFramerate))
    local _, _, home, world = call(_G.GetNetStats)
    return math.floor(fps + 0.5), math.max(num(home), num(world))
end

-- Returns hour, minute, second from server time (always 24-hour) or the local
-- clock. The server only gives hours and minutes; its seconds match the local
-- ones, so those are used for both. The minimap clock uses this too.
function DT.ReadClock(useServer)
    local s = tonumber(date("%S"))
    if useServer and type(GetGameTime) == "function" then
        local h, m = GetGameTime()
        return h, m, s
    end
    return tonumber(date("%H")), tonumber(date("%M")), s
end

-- Follows the minimap clock's server/local setting.
local function clock()
    local c = DUI:Get("InfoPanel", "map.clock") or {}
    local h, m, s = DT.ReadClock(c.useServer)
    return h, m, c.twentyFour ~= false, c.seconds and s or nil
end

-- Seconds are shown only when s is given.
function DT.FormatClock(h, m, twentyFour, s)
    if type(h) ~= "number" or type(m) ~= "number" then return "" end
    local sec = type(s) == "number" and string.format(":%02d", s) or ""
    if twentyFour then return string.format("%02d:%02d%s", h, m, sec) end
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d%s %s", h12, m, sec, h >= 12 and (TIMEMANAGER_PM or "PM") or (TIMEMANAGER_AM or "AM"))
end

-- Percent through the level, or nil at the level cap.
function DT.ReadXP()
    if sample() then return DT.SAMPLE.xp end
    if call(_G.IsPlayerAtEffectiveMaxLevel) == true then return nil end
    local cur, max = num(call(_G.UnitXP, "player")), num(call(_G.UnitXPMax, "player"))
    if max <= 0 then return nil end
    return math.floor(cur / max * 100)
end

function DT.ReadLocation()
    if sample() then return L["Elwynn Forest"] end
    local zone = call(_G.GetMinimapZoneText)
    return type(zone) == "string" and zone ~= "" and zone or "-"
end

function DT.ReadCoords()
    if sample() then return DT.SAMPLE.x, DT.SAMPLE.y end
    local Map = ns.Minimap
    if Map and Map.ReadCoords then return Map.ReadCoords() end
end

-- ---------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------

local Tips = DUI.Tips
local tipTitle, gap, hint, person = Tips.Title, Tips.Gap, Tips.Hint, Tips.Person
-- rc is the value color, light by default.
local function line(left, right, rc) Tips.Line(left, right, rc or DT.VALUE) end

function DT.FlushTip() Tips.Flush(GameTooltip) end
-- A name's class color as a table, nil for an unknown class (the row keeps its own color).
local function classColor(token)
    if not Style.RawClassColor(token) then return nil end
    return { Style.ClassTextColor(token) }
end
-- Class token from a localized class name. The friends list only gives the name.
function DT.ClassToken(name)
    if type(name) ~= "string" then return nil end
    for _, list in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(list) == "table" then
            for token, n in pairs(list) do
                if n == name then return token end
            end
        end
    end
end
local function colored(text, c) return c and (hex(c) .. text .. "|r") or text end

local function gearColor(pct)
    if pct <= DT.GEAR_BAD then return DT.BAD end
    if pct <= DT.GEAR_WARN then return DT.WARN end
end
-- Tooltip color for one item's durability.
DT.GearShade = DUI.Tips.Wear
local function ammoColor(n)
    if n <= DT.AMMO_BAD then return DT.BAD end
    if n <= DT.AMMO_WARN then return DT.WARN end
end

local function bagsColor(free)
    if free <= DT.BAGS_BAD then return DT.BAD end
    if free <= DT.BAGS_WARN then return DT.WARN end
end

-- Your faction when the gold tooltip is limited to it, else nil for all
-- characters. Useful for players with characters on both sides.
function DT.GoldFaction()
    if DUI:Get("InfoPanel", "data.goldChars") ~= "faction" then return nil end
    local mine = call(_G.UnitFactionGroup, "player")
    return type(mine) == "string" and mine or nil
end

-- Gold of every character on this ruleset, richest first. A character's
-- faction is only known once it has logged in with this version.
function DT.Characters()
    local chars = DUI.DB.Root().characters
    local out = {}
    if type(chars) ~= "table" then return out end
    local faction = DT.GoldFaction()
    for key, c in pairs(chars) do
        if type(c) == "table" and type(c.money) == "number" and (not faction or c.faction == faction)
            and DUI.Alts.Reachable(key) then
            out[#out + 1] = { key = key, money = c.money, class = c.class }
        end
    end
    table.sort(out, function(a, b)
        if a.money ~= b.money then return a.money > b.money end
        return a.key < b.key
    end)
    return out
end

-- Saves this character's gold for the other characters' tooltips.
function DT.SaveMoney()
    if sample() then return end
    local money = call(_G.GetMoney)
    if type(money) ~= "number" then return end
    DT.startMoney = DT.startMoney or money
    local c = DUI.DB.Character()
    c.money = money
    local _, class = call(_G.UnitClass, "player")
    if type(class) == "string" then c.class = class end
    local faction = call(_G.UnitFactionGroup, "player")
    if type(faction) == "string" then c.faction = faction end
end

local function goldTip()
    tipTitle(L["Gold"])
    local money = DT.ReadMoney()
    line(L["This character"], DUI.MoneyString(money))
    local start = DT.startMoney
    if type(start) == "number" and not sample() and money ~= start then
        local d = money - start
        line(d > 0 and L["Earned this session"] or L["Spent this session"], DUI.MoneyString(math.abs(d)))
    end
    local list = DT.Characters()
    if #list > 1 then
        gap()
        local total = 0
        for i, c in ipairs(list) do
            total = total + c.money
            if i <= DT.TIP_LINES then
                local name = c.key:match("^(.-)%-") or c.key
                line(colored(name, classColor(c.class)), DUI.MoneyString(c.money))
            end
        end
        line(DT.GoldFaction() and L["All characters of this faction"] or L["All characters"], DUI.MoneyString(total))
    end
    gap()
    hint(L["Click: bags"])
    if #DUI.Alts.List() > 0 then hint(L["Right-click: remove a character"]) end
end

-- In combat, Daylight UI's own character window can still open. If it's
-- turned off, the click waits until combat ends.
local function charInFight()
    local F = DUI.Char and DUI.Char.Follow
    return F ~= nil and F.Ready()
end
local function durabilityTip()
    tipTitle(L["Durability"])
    local low, list = DT.ReadDurability()
    if sample() then
        line(L["Chest"], "18%", DT.GearShade(18))
        line(L["Hands"], "64%", DT.GearShade(64))
    elseif #list == 0 then
        hint(L["Nothing worn that wears down."])
    end
    for _, g in ipairs(list) do line(g.name, g.pct .. "%", DT.GearShade(g.pct)) end
    gap()
    hint((InCombatLockdown() and not charInFight()) and L["Click: character window (after combat)"] or L["Click: character window"])
    return low
end

local function bagsTip()
    tipTitle(L["Bags"])
    local free, total, list = DT.ReadBags()
    for _, b in ipairs(list) do
        line(b.plain and b.name or string.format(L["%s (profession)"], b.name), string.format(L["%d / %d free"], b.free, b.total))
    end
    line(L["Free"], free .. " / " .. total, bagsColor(free))
    gap()
    hint(L["Click: bags"])
end

-- Battle.net friends first, then the character friends list.
local function friendsTip()
    local shown = 0
    local more = 0
    local function add(left, right, c)
        if shown < DT.TIP_LINES then
            shown = shown + 1
            person(left, right, c)
        else
            more = more + 1
        end
    end
    tipTitle(string.format(L["Friends online: %d"], DT.ReadFriends()))
    if sample() then
        add("Ellie", L["Elwynn Forest"], classColor("MAGE"))
        add("Thorn", L["Stormwind City"], classColor("WARRIOR"))
        return
    end
    local total = num(call(_G.BNGetNumFriends))
    local info = api("C_BattleNet", "GetFriendAccountInfo")
    for i = 1, total do
        local a = call(info, i)
        local game = type(a) == "table" and a.gameAccountInfo
        if type(game) == "table" and known(game.isOnline) == true and type(known(a.accountName)) == "string" then
            local who, char = a.accountName, known(game.characterName)
            if type(char) == "string" and char ~= "" then who = who .. " (" .. char .. ")" end
            local where = known(game.areaName)
            if type(where) ~= "string" then where = known(game.richPresence) end
            add(who, type(where) == "string" and where or nil, classColor(known(game.classFilename)))
        end
    end
    local n = num(call(api("C_FriendList", "GetNumFriends")))
    local byIndex = api("C_FriendList", "GetFriendInfoByIndex")
    for i = 1, n do
        local f = call(byIndex, i)
        if type(f) == "table" and known(f.connected) == true and type(known(f.name)) == "string" then
            local area = known(f.area)
            add(f.name .. (type(known(f.level)) == "number" and (" " .. f.level) or ""),
                type(area) == "string" and area or nil, classColor(DT.ClassToken(known(f.className))))
        end
    end
    if more > 0 then hint(string.format(L["and %d more"], more)) end
    if shown == 0 then hint(L["Nobody online right now."]) end
end

local function guildTip()
    if not sample() and call(_G.IsInGuild) ~= true then
        tipTitle(L["Guild"])
        hint(L["You're not in a guild."])
        return
    end
    local name = call(_G.GetGuildInfo, "player")
    tipTitle(string.format(L["%s: %d online"], type(name) == "string" and name or L["Guild"], num(DT.ReadGuild())))
    if sample() then
        person("Bram 60", L["Ironforge"], { 0.67, 0.83, 0.45 })
        return
    end
    -- Request a fresh roster (the game throttles these), but not on a redraw:
    -- the roster event is what triggers the redraw.
    if not DT.redrawing then call(api("C_GuildInfo", "GuildRoster")) end
    local total = num(call(_G.GetNumGuildMembers))
    local shown, more = 0, 0
    for i = 1, total do
        local who, _, _, level, _, zone, _, _, online, _, class = call(_G.GetGuildRosterInfo, i)
        who, level, zone, online, class = known(who), known(level), known(zone), known(online), known(class)
        if online == true and type(who) == "string" then
            if shown < DT.TIP_LINES then
                shown = shown + 1
                local short = who:match("^(.-)%-") or who
                person(short .. (type(level) == "number" and (" " .. level) or ""),
                    type(zone) == "string" and zone or nil, classColor(class))
            else
                more = more + 1
            end
        end
    end
    if more > 0 then hint(string.format(L["and %d more"], more)) end
end

-- With the game's controller UI on, a game window opened from addon code goes
-- on the controller's window list carrying Daylight UI's taint. The game then
-- refuses its own SetPreferredGamepadInteractTarget every time the soft target
-- changes (walking past NPCs), and the controller misbehaves until a reload. So
-- on a controller the game's windows open only through the game's own buttons,
-- clicked by a secure button over the text (DT.WindowOver); a game without
-- that button gets no click there.
local function padUI() return DUI.Pad ~= nil and DUI.Pad.On() == true end

local function socialHint(guild)
    gap()
    local fight = InCombatLockdown()
    if not padUI() or DT.OpenClick("social") then
        hint(fight and L["Click: friends (after combat)"] or L["Click: friends"])
    end
    if guild then hint(fight and L["Right-click: guild (after combat)"] or L["Right-click: guild"]) end
end

-- ---------------------------------------------------------------------
-- Clicks. The character and social windows refuse to open from addon code
-- in combat, so those wait.
-- ---------------------------------------------------------------------

-- Close Daylight UI's bag directly instead of calling ToggleAllBags. From addon code,
-- ToggleAllBags taints the game's record of who opened the bags, and calls
-- that read it afterwards get blocked.
local function openBags()
    local bag = _G.DaylightUIBag
    if type(bag) == "table" and bag:IsShown() then DUI.Motion.Vanish(bag)
    elseif not padUI() then call(_G.ToggleAllBags) end
end
-- Right-click removes a deleted character from the gold list.
local function goldClick(button, slot)
    if button == "RightButton" and #DUI.Alts.List() > 0 then return DUI.Alts.Menu(slot) end
    openBags()
end
local function openCharacter()
    if InCombatLockdown() then
        if charInFight() then DUI.Char.Follow.ToggleInFight() end
        return
    end
    if not padUI() then call(_G.ToggleCharacter, "PaperDollFrame") end
end
local function openFriends()
    if InCombatLockdown() or padUI() then return end
    call(_G.ToggleFriendsFrame)
end
-- The game's clock window (alarm and stopwatch). Its own minimap clock sits in
-- the hidden minimap cluster, so Daylight UI's clocks take its click: open the
-- window, or turn a ringing alarm off. Out of a fight that click is the game
-- button's own (DT.WindowOver); in one, the window isn't protected, so it is
-- opened from here, except on a controller.
local function alarmRinging()
    local ringing = _G.TimeManager_IsAlarmFiring
    return type(ringing) == "function" and ringing() == true
end

function DT.ClockClick()
    if padUI() then return end
    if alarmRinging() then
        DUI.Sound.Play("toggle")
        DUI.SafeCall(_G.TimeManager_TurnOffAlarm)
    elseif type(_G.ToggleTimeManager) == "function" then
        DUI.SafeCall(_G.ToggleTimeManager)
    end
end

function DT.ClockHint()
    if padUI() and (InCombatLockdown() or not DT.OpenClick("clock")) then return end
    gap()
    hint(alarmRinging() and L["Click: turn the alarm off"] or L["Click: alarm and stopwatch"])
end

local function openMap()
    if InCombatLockdown() then return end
    call(api("C_Map", "OpenWorldMap"))
end

-- ---------------------------------------------------------------------
-- Combat state. InCombatLockdown is still false during PLAYER_REGEN_DISABLED,
-- so the events are trusted. Before the first event (a /reload mid-fight)
-- fall back to InCombatLockdown.
-- ---------------------------------------------------------------------

function DT.SetFight(on)
    if on == DT.fight then return end
    DT.fight = on
    local now = GetTime()
    if on then
        DT.fightStart = now
    elseif DT.fightStart then
        DT.lastFight = now - DT.fightStart
        DT.fightStart = nil
    end
end
function DT.InFight()
    if sample() then return false end
    if DT.fight == nil then return InCombatLockdown() == true end
    return DT.fight
end
local function fightEvent(event) DT.SetFight(event == "PLAYER_REGEN_DISABLED") end

-- 83 seconds as "1:23".
function DT.Duration(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- ---------------------------------------------------------------------
-- Volume. Plain CVars, safe to change in combat. Wheel adjusts the chosen
-- channel, click mutes everything, right-click picks the channel.
-- ---------------------------------------------------------------------

DT.CHANNELS = {
    master = { cvar = "Sound_MasterVolume", enable = "Sound_EnableAllSound", name = L["Master"] },
    sfx = { cvar = "Sound_SFXVolume", enable = "Sound_EnableSFX", name = L["Effects"] },
    music = { cvar = "Sound_MusicVolume", enable = "Sound_EnableMusic", name = L["Music"] },
    ambience = { cvar = "Sound_AmbienceVolume", enable = "Sound_EnableAmbience", name = L["Ambience"] },
    dialog = { cvar = "Sound_DialogVolume", enable = "Sound_EnableDialog", name = L["Dialog"] },
}
DT.CHANNEL_ORDER = { "master", "sfx", "music", "ambience", "dialog" }
DT.VOLUME_STEP = 0.05   -- one wheel notch

local function getCVar(name) return call(api("C_CVar", "GetCVar"), name) or call(_G.GetCVar, name) end
local function setCVar(name, v)
    local set = api("C_CVar", "SetCVar") or _G.SetCVar
    call(set, name, v)
end

-- Falls back to master if the saved channel doesn't exist.
function DT.Channel()
    local db = ns.module and ns.module.db
    local k = db and db.data and db.data.volumeChannel
    return DT.CHANNELS[k] and k or "master"
end
-- 0 to 1. A missing CVar reads as full, same as the game.
function DT.Volume(key)
    if sample() then return key == "music" and 0.3 or 0.8 end
    local v = tonumber(getCVar(DT.CHANNELS[key].cvar))
    return v and math.max(0, math.min(1, v)) or 1
end
function DT.SoundOn(key)
    if sample() then return true end
    return getCVar(DT.CHANNELS[key].enable) ~= "0"
end
-- Rounded to a wheel step. CVAR_UPDATE triggers the redraw.
function DT.SetVolume(key, v)
    v = math.max(0, math.min(1, math.floor(v / DT.VOLUME_STEP + 0.5) * DT.VOLUME_STEP))
    setCVar(DT.CHANNELS[key].cvar, string.format("%.2f", v))
end
function DT.ToggleMute()
    setCVar(DT.CHANNELS.master.enable, DT.SoundOn("master") and "0" or "1")
end

-- "Muted" when all sound is off, "Off" for this channel, else a percent.
local function volumeValue(key)
    if not DT.SoundOn("master") then return L["Muted"], DT.WARN end
    if not DT.SoundOn(key) then return L["Off"], DT.WARN end
    return math.floor(DT.Volume(key) * 100 + 0.5) .. "%"
end

local function volumeTip()
    tipTitle(L["Volume"])
    local picked = DT.Channel()
    for _, key in ipairs(DT.CHANNEL_ORDER) do
        local name = DT.CHANNELS[key].name
        local v, c = volumeValue(key)
        if key == picked then name = colored(name, { Style.Accent() }) end
        line(name, v, c)
    end
    gap()
    hint(DT.SoundOn("master") and L["Click: mute all sound"] or L["Click: sound back on"])
    hint(L["Right-click: pick a channel"])
    hint(L["Wheel: louder or quieter"])
end

-- Redraw one text on every strip, for setting changes with no game event.
DT.strips = {}
function DT.Redraw(key)
    for _, S in ipairs(DT.strips) do S.Update(false, { [key] = true }) end
end

local function volumeClick(button, slot)
    if button ~= "RightButton" then return DT.ToggleMute() end
    DUI.Widgets.OpenMenu(slot, DT.CHANNEL_ORDER, (function()
        local names = {}
        for k, ch in pairs(DT.CHANNELS) do names[k] = ch.name end
        return names
    end)(), DT.Channel(), function(key)
        DUI:Set("InfoPanel", "data.volumeChannel", key)
        DT.Redraw("volume")
    end)
end

-- ---------------------------------------------------------------------
-- Item level, equipped and best available including bags. Plain in combat.
-- ---------------------------------------------------------------------

function DT.ReadItemLevel()
    if sample() then return 62, 64 end
    local overall, equipped = call(_G.GetAverageItemLevel)
    overall, equipped = known(overall), known(equipped)
    if type(equipped) ~= "number" then equipped = overall end
    if type(equipped) ~= "number" then return nil end
    return math.floor(equipped), type(overall) == "number" and math.floor(overall) or nil
end

-- ---------------------------------------------------------------------
-- Time played. Requested once, then counted forward locally. Chat frames
-- print every TIME_PLAYED_MSG, so they're unregistered while it asks and
-- re-registered after the answer (or after PLAYED_WAIT seconds). A manual
-- /played still prints normally.
-- ---------------------------------------------------------------------

DT.PLAYED_WAIT = 10
DT.sessionStart = GetTime()

local muted = {}
local function unmute()
    for i = #muted, 1, -1 do
        DUI.SafeCall(muted[i].RegisterEvent, muted[i], "TIME_PLAYED_MSG")
        muted[i] = nil
    end
end

function DT.OnPlayed(total, level)
    if type(total) ~= "number" or type(level) ~= "number" then return end
    DT.played = { total = total, level = level, at = GetTime() }
    DT.playedAsked = nil
    if #muted > 0 then C_Timer.After(0, unmute) end   -- after every listener has seen this answer
end

function DT.AskPlayed()
    if DT.played or type(_G.RequestTimePlayed) ~= "function" then return end
    local now = GetTime()
    if DT.playedAsked and now - DT.playedAsked < 60 then return end
    DT.playedAsked = now
    for i = 1, (tonumber(_G.NUM_CHAT_WINDOWS) or 10) do
        local f = _G["ChatFrame" .. i]
        if type(f) == "table" and f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG") then
            f:UnregisterEvent("TIME_PLAYED_MSG")
            muted[#muted + 1] = f
        end
    end
    call(_G.RequestTimePlayed)
    C_Timer.After(DT.PLAYED_WAIT, unmute)
end

-- Total and level time in seconds, or nil until the game answers.
function DT.ReadPlayed()
    if sample() then return 1234567, 45678 end
    local p = DT.played
    if not p then return nil end
    local d = GetTime() - p.at
    return p.total + d, p.level + d
end

-- 1234567 seconds as "14d 6h", 45678 as "12h 41m", 300 as "5m".
function DT.Long(sec)
    local m = math.floor(math.max(0, sec) / 60)
    local h = math.floor(m / 60)
    if h >= 24 then return string.format(L["%dd %dh"], math.floor(h / 24), h % 24) end
    if h > 0 then return string.format(L["%dh %dm"], h, m % 60) end
    return string.format(L["%dm"], m)
end

-- ---------------------------------------------------------------------
-- Professions. The strip shows the primaries. Click opens the last one used,
-- right-click picks one (only professions with a crafting window).
-- OpenTradeSkill from a click works in combat.
-- ---------------------------------------------------------------------

function DT.ReadProfessions()
    if sample() then
        return { { name = L["Tailoring"], rank = 245, max = 300, primary = true },
                 { name = L["Enchanting"], rank = 230, max = 300, primary = true },
                 { name = L["Cooking"], rank = 150, max = 225 } }
    end
    local out = {}
    if type(_G.GetProfessions) ~= "function" or type(_G.GetProfessionInfo) ~= "function" then return out end
    local list = { call(_G.GetProfessions) }
    for i = 1, 7 do
        local idx = list[i]
        if idx then
            local name, _, rank, max, _, _, skillLine = call(_G.GetProfessionInfo, idx)
            if type(name) == "string" then
                out[#out + 1] = { name = name, rank = num(rank), max = num(max), primary = i <= 2, skillLine = num(skillLine) }
            end
        end
    end
    -- In the order the player dragged the profession window's tabs into.
    local Data = DUI.Craft and DUI.Craft.Data
    if Data and Data.Ordered then DUI.SafeCall(Data.Ordered, out) end
    return out
end

local function craftTabs()
    local Data = DUI.Craft and DUI.Craft.Data
    return Data and Data.Tabs and (pass(pcall(Data.Tabs)) or {}) or {}
end
local function openProfession(skillLine)
    call(api("C_TradeSkillUI", "OpenTradeSkill"), skillLine)
end
local function professionsClick(button, slot)
    local tabs = craftTabs()
    if #tabs == 0 then return end
    if button == "RightButton" then
        local keys, names = {}, {}
        for _, t in ipairs(tabs) do
            keys[#keys + 1] = t.skillLine
            names[t.skillLine] = t.name
        end
        local char = DUI.DB.Character()
        DUI.Widgets.OpenMenu(slot, keys, names, char and char.craftLast, openProfession)
        return
    end
    local char = DUI.DB.Character()
    local want = char and char.craftLast
    for _, t in ipairs(tabs) do
        if t.skillLine == want then return openProfession(want) end
    end
    openProfession(tabs[1].skillLine)
end

-- ---------------------------------------------------------------------
-- Hearthstone location and cooldown. Using an item is protected, so clicks
-- go through a secure button placed over the slot (out of combat only).
-- ---------------------------------------------------------------------

DT.HEARTH = 6948

function DT.ReadHearth()
    if sample() then return L["Goldshire"], 754, true end
    local home = call(_G.GetBindLocation)
    home = type(known(home)) == "string" and home or nil
    local start, dur = call(api("C_Container", "GetItemCooldown"), DT.HEARTH)
    start, dur = num(start), num(dur)
    -- ignore the global cooldown (1.5 s max), which the item also reports
    local left = (dur > 1.5 and start > 0) and math.max(0, start + dur - GetTime()) or 0
    local have = num(call(api("C_Item", "GetItemCount") or _G.GetItemCount, DT.HEARTH)) > 0
    return home, left, have
end

local caster
local function hearthCaster()
    if caster or not (DUI.Win and DUI.Win.Caster) then return caster end
    caster = DUI.Win.Caster({ name = "DaylightUIDataHearth",
        above = function() return caster and caster.over end,
        enter = function(slot) if slot.enter then slot.enter(slot) end end,
        leave = function(slot) if slot.leave then slot.leave(slot) end end })
    return caster
end
-- Places the secure button on mouseover. Skipped in combat or without a
-- Hearthstone in the bags.
function DT.HearthOver(slot)
    local _, _, have = DT.ReadHearth()
    if not have or sample() then return end
    local c = hearthCaster()
    if not c or (c.button and c.button.row == slot and c.button:IsShown()) then return end
    c.over = slot
    c.Over(slot, { type1 = "macro", macrotext1 = "/use item:" .. DT.HEARTH })
end

-- The guild window only ever opens through a secure /click on the guild micro
-- button, never ToggleGuildFrame from addon code. Loading Blizzard_Communities
-- that way pulls in Blizzard_GuildControlUI tainted (its OnLoad calls the
-- protected C_Discord.IsUserOAuthed), and even once loaded, a toggle runs the
-- window's OnShow tainted, so the guild settings' event handler is blocked for
-- the rest of the session. The guild text uses left-click; the social text
-- only right-click, its left-click still opens friends.
DT.GUILD_CLICK = "/click GuildMicroButton"
local guildCaster
function DT.GuildOver(slot)
    if sample() or not (DUI.Win and DUI.Win.Caster) then return end
    if not guildCaster then
        guildCaster = DUI.Win.Caster({ name = "DaylightUIDataGuild",
            above = function() return guildCaster and guildCaster.over end,
            enter = function(s) if s.enter then s.enter(s) end end,
            leave = function(s) if s.leave then s.leave(s) end end,
            post = function(s, button)
                if s.key == "social" and button ~= "RightButton" and not guildCaster.friends then openFriends() end
            end })
    end
    local c = guildCaster
    if c.button and c.button.row == slot and c.button:IsShown() then return end
    c.over = slot
    if slot.key == "social" then
        -- A left-click is friends, through the game's own button when it has one.
        local friends = DT.OpenClick("social")
        c.friends = friends ~= nil
        c.Over(slot, { type1 = friends and "macro" or nil, macrotext1 = friends,
                       type2 = "macro", macrotext2 = DT.GUILD_CLICK })
    else
        c.Over(slot, { type1 = "macro", macrotext1 = DT.GUILD_CLICK })
    end
end

-- The game's own button behind each window a text opens. A secure /click on it
-- runs the game's code as the player's own press, so the window opens untainted.
-- A hidden button still takes the click (the chat hides the quick join one,
-- which opens friends while it has no toast up).
DT.OPENS = { character = "CharacterMicroButton", bags = "MainMenuBarBackpackButton", social = "QuickJoinToastButton",
             clock = "TimeManagerClockButton" }
-- The /click for a window, or nil when the game didn't make its button.
function DT.OpenClick(kind)
    local name = DT.OPENS[kind]
    if not name or type(_G[name]) ~= "table" then return nil end
    return "/click " .. name
end
local windowCaster
-- Lays that secure button over a text that opens one of the game's windows, on
-- mouseover and out of combat only. In a fight the text's own click still runs:
-- Daylight UI's character window opens, Daylight UI's bag closes.
function DT.WindowOver(slot)
    local t = DT.TEXTS[slot.key]
    local macro = t and DT.OpenClick(t.opens)
    if not macro or sample() or not (DUI.Win and DUI.Win.Caster) then return end
    if not windowCaster then
        windowCaster = DUI.Win.Caster({ name = "DaylightUIDataWindow",
            above = function() return windowCaster and windowCaster.over end,
            enter = function(s) if s.enter then s.enter(s) end end,
            leave = function(s) if s.leave then s.leave(s) end end,
            -- A right-click the text keeps for itself (a menu) goes to its own click.
            post = function(s, button)
                if button == "RightButton" and windowCaster.ownRight then s:GetScript("OnClick")(s, button) end
            end })
    end
    local c = windowCaster
    if c.button and c.button.row == slot and c.button:IsShown() then return end
    local ownRight = slot.pick ~= nil or (t.right ~= nil and t.right() == true)
    c.over, c.ownRight = slot, ownRight
    c.Over(slot, { type1 = "macro", macrotext1 = macro,
                   type2 = (not ownRight) and "macro" or nil, macrotext2 = (not ownRight) and macro or nil })
end

-- ---------------------------------------------------------------------
-- Combat stats, read through the character window's stat rows so the
-- numbers match. They go secret in combat and under restrictions, so the
-- last plain value stays shown until then.
-- ---------------------------------------------------------------------

DT.statLast = {}
local STAT_EVENTS = { "UNIT_STATS", "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "COMBAT_RATING_UPDATE",
    "SPELL_POWER_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP" }

-- The class's main stat group (attack, ranged or spell), as the sheet picks it.
function DT.StatGroup()
    local S = DUI.Char and DUI.Char.Stats
    local _, class = UnitClass("player")
    local g = S and S.CLASS_OPEN[class or ""] or "attack"
    return g == "defense" and "attack" or g
end

-- A stat's text, or the last plain one while it's secret.
function DT.ReadStat(group, id)
    local S = DUI.Char and DUI.Char.Stats
    if not S then return nil end
    for _, def in ipairs(S.ROWS[group] or {}) do
        if def.id == id then
            local ok, row = pcall(S.Row, def)
            if ok and row and not row.secret and not row.stale and row.values then
                DT.statLast[group .. id] = S.Text(row)
            end
            return DT.statLast[group .. id]
        end
    end
end

-- Movement speed as a percent of BASE_MOVEMENT_SPEED (7 yd/s). Current
-- speed while moving, else run, swim or fly speed. Secret in combat, so the
-- last plain value is kept.
DT.speedLast = nil
local function plainNumber(v)
    return type(v) == "number" and not isSecret(v) and v or nil
end
function DT.ReadSpeed()
    local now, run, fly, swim = call(GetUnitSpeed, "player")
    now, run, fly, swim = plainNumber(now), plainNumber(run), plainNumber(fly), plainNumber(swim)
    if not run then return DT.speedLast end
    local base = BASE_MOVEMENT_SPEED or 7
    local function pct(v) return v and math.floor(v / base * 100 + 0.5) or nil end
    local going = now and now > 0 and now
        or (call(IsFlying) and fly) or (call(IsSwimming) and swim) or run
    DT.speedLast = { now = pct(going), run = pct(run), fly = pct(fly), swim = pct(swim) }
    return DT.speedLast
end

local CRIT = { attack = "crit", ranged = "rcrit", spell = "scrit" }
-- The player's choice from the right-click menu (a melee paladin wants
-- attack crit), else the class default.
DT.CRIT_KINDS = { "auto", "attack", "ranged", "spell" }
function DT.CritGroup()
    local db = ns.module and ns.module.db
    local k = db and db.data and db.data.critKind
    return CRIT[k or ""] and k or DT.StatGroup()
end
-- Attack power exists only in the attack and ranged groups. Uses the
-- player's choice, else ranged for ranged classes, else attack.
local AP = { attack = "ap", ranged = "rap" }
DT.AP_KINDS = { "auto", "attack", "ranged" }
function DT.APGroup()
    local db = ns.module and ns.module.db
    local k = db and db.data and db.data.apKind
    if AP[k or ""] then return k end
    return DT.StatGroup() == "ranged" and "ranged" or "attack"
end

local function statText(label, v)
    local shown = value(v or "-")
    return word(label .. " ") .. shown, shown
end
local function statTip(title, rows)
    tipTitle(title)
    for _, r in ipairs(rows) do
        local v = DT.ReadStat(r[2], r[3])
        if v then line(r[1], v) end
    end
    if DT.InFight() then gap() hint(L["Numbers from before the fight."]) end
    gap()
    hint(InCombatLockdown() and not charInFight() and L["Click: character window (after combat)"] or L["Click: character window"])
end

DT.SHARD = 6265
function DT.ReadShards()
    local fn = api("C_Item", "GetItemCount") or _G.GetItemCount
    return num(call(fn, DT.SHARD))
end

function DT.SoulBagOn() return DUI:Get("InfoPanel", "data.soulBag") == true end

-- Soul bags' slots and free slots (the game's bag family bit 4), 0, 0 with none.
DT.SOUL_BAG = 4
function DT.ReadSoulBag()
    local slotsOf = api("C_Container", "GetContainerNumSlots")
    local freeOf = api("C_Container", "GetContainerNumFreeSlots")
    local total, free = 0, 0
    for _, bag in ipairs(DT.BAGS) do
        if bag ~= 0 then
            local n = num(call(slotsOf, bag))
            local f, family = call(freeOf, bag)
            if n > 0 and type(family) == "number" and family % (DT.SOUL_BAG * 2) >= DT.SOUL_BAG then
                total, free = total + n, free + num(f)
            end
        end
    end
    return total, free
end

-- Equipped ammo count and name, or nil if you don't use ammo. An empty slot
-- reports a count of 1, so check its icon instead. The count includes all
-- ammo in your bags. Keep this cheap: it runs on every shot.
function DT.ReadAmmo()
    if sample() then return DT.SAMPLE.ammo end
    local Gear = DUI.Char and DUI.Char.Gear
    if not (Gear and Gear.UsesAmmo()) then return nil end
    local id = Gear.SlotId("Ammo")
    if not (id and call(_G.GetInventoryItemTexture, "player", id)) then return 0 end
    local name
    local item = call(_G.GetInventoryItemID, "player", id)
    local info = api("C_Item", "GetItemInfo") or _G.GetItemInfo
    if item and info then name = call(info, item) end
    return num(call(_G.GetInventoryItemCount, "player", id)), type(name) == "string" and name or nil
end

-- ---------------------------------------------------------------------
-- Equipment set: the one you're wearing, and a menu to put another on. The
-- game won't swap gear in a fight, so a set picked then goes on when it
-- ends (the character window's Sets.Equip waits for it).
-- ---------------------------------------------------------------------

DT.SET_SAMPLE = { { id = 1, name = L["Questing"], icon = 132644, lost = 0 },
                  { id = 2, name = L["Dungeon"], icon = 132627, worn = true, lost = 0 } }

-- Every set as { id, name, icon, worn, lost }, and the one you're wearing.
-- Two sets can both be fully on (one holds the other's items), so the last
-- one put on wins, else the first.
function DT.ReadSets()
    if sample() then return DT.SET_SAMPLE, DT.SET_SAMPLE[2] end
    local out, worn = {}, nil
    local C = _G.C_EquipmentSet
    if type(C) ~= "table" then return out end
    local ids = call(C.GetEquipmentSetIDs)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        local name, icon, _, on, _, _, _, lost = call(C.GetEquipmentSetInfo, id)
        if type(known(name)) == "string" then
            local s = { id = id, name = name, icon = known(icon), worn = on == true, lost = num(lost) }
            out[#out + 1] = s
            if s.worn and (not worn or id == DT.lastSet) then worn = s end
        end
    end
    return out, worn
end

-- The set picked in a fight, still waiting for it to end.
function DT.WaitingSet(sets)
    if not DT.setWaiting then return nil end
    for _, s in ipairs(sets) do
        if s.id == DT.setWaiting and not s.worn then return s end
    end
end

-- The set's own icon in front of its name, cropped like every icon of ours.
function DT.SetIcon(icon)
    if icon == nil then return "" end
    local c = Style.ICON_CROP
    local function px(v) return math.floor(v * 64 + 0.5) end
    return string.format("|T%s:0:0:0:0:64:64:%d:%d:%d:%d|t ", tostring(icon), px(c[1]), px(c[2]), px(c[3]), px(c[4]))
end

-- Puts a set on, or once the fight ends. Picking the worn one in a fight
-- calls off the one waiting.
function DT.WearSet(id, worn)
    local Sets = DUI.Char and DUI.Char.Sets
    if not (Sets and Sets.Equip) then return end
    local fight = InCombatLockdown()
    if worn and not (fight and DT.setWaiting) then return end
    DT.setWaiting = fight and not worn and id or nil
    if not fight then DT.lastSet = id end
    DUI.SafeCall(Sets.Equip, id)
    DT.Redraw("equipset")
end

local function setsEvent(event, ok, id)
    if event == "EQUIPMENT_SWAP_FINISHED" and ok == true and type(id) == "number" then DT.lastSet = id end
    if event == "PLAYER_REGEN_ENABLED" then DT.setWaiting = nil end
end

local function setsTip()
    tipTitle(L["Equipment sets"])
    local sets = DT.ReadSets()
    if #sets == 0 then
        hint(L["No equipment sets yet."])
        hint(L["Make one in the character window."])
        return
    end
    local Sets = DUI.Char and DUI.Char.Sets
    for _, s in ipairs(sets) do
        local name, status, c = DT.SetIcon(s.icon) .. s.name, L["Ready"], nil
        if s.worn then
            name, status, c = DT.SetIcon(s.icon) .. colored(s.name, { Style.Accent() }), L["Wearing it"], DT.GOOD
        elseif s.id == DT.setWaiting then
            status, c = L["After combat"], DT.WARN
        elseif s.lost > 0 then
            status, c = Sets and Sets.Status and Sets.Status(false, s.lost) or status, DT.WARN
        end
        line(name, status, c)
    end
    gap()
    hint(InCombatLockdown() and L["Click: pick a set (after combat)"] or L["Click: pick a set"])
end

local function setsClick(_, slot)
    if sample() then return end
    local sets, worn = DT.ReadSets()
    if #sets == 0 then return end
    local waiting = DT.WaitingSet(sets)
    local fight = InCombatLockdown()
    local keys, values = {}, {}
    for _, s in ipairs(sets) do
        local k = tostring(s.id)
        keys[#keys + 1] = k
        values[k] = DT.SetIcon(s.icon) .. s.name
        if fight and not s.worn then values[k] = values[k] .. word("  ·  " .. L["After combat"]) end
    end
    local current = waiting or worn
    DUI.Widgets.OpenMenu(slot, keys, values, current and tostring(current.id) or nil, function(k)
        local id = tonumber(k)
        DT.WearSet(id, worn ~= nil and worn.id == id)
    end)
end

-- ---------------------------------------------------------------------
-- The texts
-- ---------------------------------------------------------------------

-- Each text's name shows in the slot menus, and its events trigger a redraw (poll
-- means the ticker redraws it instead). text() returns the long version and the
-- short one without the label.
DT.TEXTS = {
    gold = { name = "Gold", events = { "PLAYER_MONEY" },
        text = function()
            local s = value(DT.ShortMoney(DT.ReadMoney()))
            return s, s
        end,
        ownIcon = true,   -- the text already ends in a coin icon
        tip = goldTip, click = goldClick, opens = "bags",
        right = function() return #DUI.Alts.List() > 0 end },
    durability = { name = "Durability", events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
        count = function() return DT.ReadDurability() end,
        text = function(n)
            local low = n or DT.ReadDurability()
            local v = low and value(low .. "%", gearColor(low)) or value("-")
            return word(L["Gear"] .. " ") .. v, v
        end,
        tip = durabilityTip, click = openCharacter, opens = "character" },
    bags = { name = "Bag space", events = { "BAG_UPDATE_DELAYED" },
        count = function() return DT.ReadBags() end,
        text = function(n)
            local free = n or DT.ReadBags()
            local v = value(tostring(free), bagsColor(free))
            return word(L["Bags"] .. " ") .. v, v
        end,
        tip = bagsTip, click = openBags, opens = "bags" },
    social = { name = "Friends and guild",
        events = { "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED",
                   "BN_DISCONNECTED", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
        text = function()
            local f, g = value(tostring(DT.ReadFriends())), DT.ReadGuild()
            if not g then return word(L["Friends"] .. " ") .. f, f end
            g = value(tostring(g))
            return word(L["Friends"] .. " ") .. f .. word("  " .. L["Guild"] .. " ") .. g, f .. word(" · ") .. g
        end,
        tip = function()
            friendsTip()
            local inGuild = sample() or call(_G.IsInGuild) == true
            if inGuild then
                gap()
                guildTip()
            end
            socialHint(inGuild)
        end,
        click = function(button)
            if button ~= "RightButton" then openFriends() end
        end,
        over = function(slot) DT.GuildOver(slot) end },
    friends = { name = "Friends", events = { "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
                                             "BN_CONNECTED", "BN_DISCONNECTED" },
        count = function() return DT.ReadFriends() end,
        text = function(n)
            local v = value(tostring(n or DT.ReadFriends()))
            return word(L["Friends"] .. " ") .. v, v
        end,
        tip = function() friendsTip(); socialHint(false) end, click = openFriends, opens = "social" },
    guild = { name = "Guild", events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
        count = function() return DT.ReadGuild() end,
        text = function(n)
            local g = n or DT.ReadGuild()
            local v = value(g and tostring(g) or "-")
            return word(L["Guild"] .. " ") .. v, v
        end,
        tip = function()
            guildTip()
            gap()
            hint(InCombatLockdown() and L["Click: guild (after combat)"] or L["Click: guild"])
        end,
        over = function(slot) DT.GuildOver(slot) end },
    system = { name = "Framerate and latency", poll = true,
        text = function()
            local fps, ms = DT.ReadSystem()
            return value(tostring(fps)) .. word(" fps  ") .. value(tostring(ms)) .. word(" ms"),
                value(tostring(fps)) .. word(" fps · ") .. value(tostring(ms)) .. word(" ms")
        end,
        tip = function()
            tipTitle(L["Performance"])
            local fps, ms = DT.ReadSystem()
            local _, _, home, world = call(_G.GetNetStats)
            line(L["Framerate"], fps .. " fps")
            line(L["Latency (home)"], num(home) .. " ms")
            line(L["Latency (world)"], num(world) .. " ms")
            if not home then line(L["Latency"], ms .. " ms") end
        end },
    time = { name = "Time", poll = true,
        text = function()
            local s = value(DT.FormatClock(clock()))
            return s, s
        end,
        tip = function()
            local _, _, twentyFour, sec = clock()
            tipTitle(L["Time"])
            line(L["Local"], DT.FormatClock(tonumber(date("%H")), tonumber(date("%M")), twentyFour, sec))
            if type(GetGameTime) == "function" then
                local h, m = GetGameTime()
                line(L["Server"], DT.FormatClock(h, m, twentyFour, sec))
            end
            DT.ClockHint()
        end,
        click = function() DT.ClockClick() end, opens = "clock" },
    xp = { name = "Experience", events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION" },
        text = function()
            local pct = DT.ReadXP()
            if not pct then
                local v = value(tostring(num(call(_G.UnitLevel, "player"))))
                return word(L["Level"] .. " ") .. v, v
            end
            local v = value(pct .. "%")
            return word(L["XP"] .. " ") .. v, v
        end,
        tip = function()
            tipTitle(L["Experience"])
            local pct = DT.ReadXP()
            if not pct then hint(L["At the level cap."]) return end
            local cur, max = num(call(_G.UnitXP, "player")), num(call(_G.UnitXPMax, "player"))
            if sample() then cur, max = 768, 1200 end
            line(L["This level"], thousands(cur) .. " / " .. thousands(max) .. " (" .. pct .. "%)")
            line(L["To go"], thousands(math.max(0, max - cur)))
            local rested = call(_G.GetXPExhaustion)
            if type(rested) == "number" and rested > 0 then line(L["Rested"], thousands(rested)) end
        end },
    location = { name = "Location", events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" },
        text = function()
            local s = value(DT.ReadLocation(), DUI.Style.INK.VALUE)
            return s, s
        end,
        tip = function()
            local zone, sub = call(_G.GetZoneText), call(_G.GetSubZoneText)
            tipTitle(type(zone) == "string" and zone ~= "" and zone or L["Location"])
            if type(sub) == "string" and sub ~= "" then hint(sub) end
            gap()
            hint(InCombatLockdown() and L["Click: world map (after combat)"] or L["Click: world map"])
        end,
        click = openMap },
    coords = { name = "Coordinates", poll = true,
        text = function()
            local x, y = DT.ReadCoords()
            local s = value(x and string.format("%.1f, %.1f", x, y) or "-")
            return s, s
        end,
        tip = function()
            tipTitle(L["Coordinates"])
            local zone = call(_G.GetMinimapZoneText)
            if type(zone) == "string" then hint(zone) end
            gap()
            hint(InCombatLockdown() and L["Click: world map (after combat)"] or L["Click: world map"])
        end,
        click = openMap },
    combat = { name = "Combat", events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }, onEvent = fightEvent,
        text = function()
            local s = DT.InFight() and value(L["In combat"], DT.BAD) or value(L["Out of combat"], DT.GOOD)
            return s, s
        end,
        tip = function()
            tipTitle(L["Combat"])
            local on = DT.InFight()
            line(L["Now"], on and L["In combat"] or L["Out of combat"], on and DT.BAD or DT.GOOD)
            if on and DT.fightStart then line(L["This fight"], DT.Duration(GetTime() - DT.fightStart)) end
            if DT.lastFight then line(L["Last fight"], DT.Duration(DT.lastFight)) end
        end },
    volume = { name = "Volume", events = { "CVAR_UPDATE" },
        text = function()
            local key = DT.Channel()
            local v = value(volumeValue(key))
            local ch = word(DT.CHANNELS[key].name .. " ")
            return word((key == "master" and L["Volume"] or DT.CHANNELS[key].name) .. " ") .. v,
                key == "master" and v or ch .. v
        end,
        tip = volumeTip, click = volumeClick,
        wheel = function(delta)
            local key = DT.Channel()
            DT.SetVolume(key, DT.Volume(key) + (delta > 0 and DT.VOLUME_STEP or -DT.VOLUME_STEP))
        end },
    ilvl = { name = "Item level", events = { "PLAYER_AVG_ITEM_LEVEL_UPDATE", "PLAYER_EQUIPMENT_CHANGED" },
        text = function()
            local lvl = DT.ReadItemLevel()
            local v = value(lvl and tostring(lvl) or "-")
            return word(L["Item level"] .. " ") .. v, v
        end,
        tip = function()
            tipTitle(L["Item level"])
            local lvl, best = DT.ReadItemLevel()
            line(L["Equipped"], lvl and tostring(lvl) or "-")
            if best and lvl and best > lvl then line(L["Best in your bags"], tostring(best), DT.GOOD) end
            gap()
            hint(InCombatLockdown() and not charInFight() and L["Click: character window (after combat)"] or L["Click: character window"])
        end,
        click = openCharacter, opens = "character" },
    played = { name = "Time played", events = { "TIME_PLAYED_MSG" }, poll = true,
        onEvent = function(_, total, level) DT.OnPlayed(total, level) end,
        text = function()
            local total = DT.ReadPlayed()
            if not total then DT.AskPlayed() end
            local v = value(total and DT.Long(total) or "-")
            return word(L["Played"] .. " ") .. v, v
        end,
        tip = function()
            tipTitle(L["Time played"])
            local total, level = DT.ReadPlayed()
            line(L["Total"], total and DT.Long(total) or "-")
            if level then line(L["This level"], DT.Long(level)) end
            line(L["This session"], DT.Long(GetTime() - DT.sessionStart))
        end },
    professions = { name = "Professions", events = { "SKILL_LINES_CHANGED" },
        text = function()
            local long, short = {}, {}
            for _, p in ipairs(DT.ReadProfessions()) do
                if p.primary then
                    local v = value(tostring(p.rank or 0))
                    long[#long + 1] = word(p.name .. " ") .. v
                    short[#short + 1] = v
                end
            end
            if #long == 0 then
                local v = value("-")
                return word(L["Professions"] .. " ") .. v, v
            end
            return table.concat(long, "  "), table.concat(short, word(" · "))
        end,
        tip = function()
            tipTitle(L["Professions"])
            local list = DT.ReadProfessions()
            if #list == 0 then hint(L["No professions yet."]) return end
            for _, p in ipairs(list) do
                line(p.name, (p.rank or 0) .. " / " .. (p.max or 0), p.max and p.rank == p.max and DT.GOOD or nil)
            end
            if sample() or #craftTabs() > 0 then
                gap()
                hint(L["Click: open"])
                hint(L["Right-click: pick a profession"])
            end
        end,
        click = professionsClick },
    crit = { name = "Critical strike", events = STAT_EVENTS,
        text = function()
            local g = DT.CritGroup()
            return statText(L["Crit"], DT.ReadStat(g, CRIT[g]))
        end,
        tip = function()
            local g = DT.CritGroup()
            local rows = { { L["Attack"], "attack", "crit" }, { L["Ranged"], "ranged", "rcrit" },
                { L["Spell"], "spell", "scrit" } }
            for _, r in ipairs(rows) do
                if r[2] == g then r[1] = colored(r[1], { Style.Accent() }) end
            end
            statTip(L["Critical strike"], rows)
            hint(L["Right-click: pick which crit"])
        end,
        opens = "character", right = function() return true end,
        click = function(button, slot)
            if button ~= "RightButton" then return openCharacter() end
            local db = ns.module and ns.module.db
            local picked = db and db.data and db.data.critKind or "auto"
            DUI.Widgets.OpenMenu(slot, DT.CRIT_KINDS, { auto = L["For your class"], attack = L["Attack"],
                ranged = L["Ranged"], spell = L["Spell"] }, picked, function(key)
                DUI:Set("InfoPanel", "data.critKind", key)
                DT.Redraw("crit")
            end)
        end },
    ap = { name = "Attack power", events = STAT_EVENTS,
        text = function()
            local g = DT.APGroup()
            return statText(L["AP"], DT.ReadStat(g, AP[g]))
        end,
        tip = function()
            local g = DT.APGroup()
            local rows = { { L["Attack"], "attack", "ap" }, { L["Ranged"], "ranged", "rap" } }
            for _, r in ipairs(rows) do
                if r[2] == g then r[1] = colored(r[1], { Style.Accent() }) end
            end
            statTip(L["Attack power"], rows)
            hint(L["Right-click: pick which attack power"])
        end,
        opens = "character", right = function() return true end,
        click = function(button, slot)
            if button ~= "RightButton" then return openCharacter() end
            local db = ns.module and ns.module.db
            local picked = db and db.data and db.data.apKind or "auto"
            DUI.Widgets.OpenMenu(slot, DT.AP_KINDS, { auto = L["For your class"], attack = L["Attack"],
                ranged = L["Ranged"] }, picked, function(key)
                DUI:Set("InfoPanel", "data.apKind", key)
                DT.Redraw("ap")
            end)
        end },
    sp = { name = "Spell power", events = STAT_EVENTS,
        text = function() return statText(L["SP"], DT.ReadStat("spell", "sp")) end,
        tip = function()
            statTip(L["Spell power"], { { L["Spell power"], "spell", "sp" }, { L["Healing"], "spell", "heal" } })
        end,
        click = openCharacter, opens = "character" },
    hit = { name = "Chance to hit", events = STAT_EVENTS,
        text = function() return statText(L["Hit"], DT.ReadStat("attack", "hit")) end,
        tip = function() statTip(L["Chance to hit"], { { L["Chance to hit"], "attack", "hit" } }) end,
        click = openCharacter, opens = "character" },
    shards = { name = "Soul Shards", events = { "BAG_UPDATE_DELAYED" },
        count = function() return DT.ReadShards() end,
        text = function(n)
            local v = value(tostring(n or DT.ReadShards()))
            local slots = DT.SoulBagOn() and DT.ReadSoulBag() or 0
            if slots > 0 then v = v .. word(" / ") .. value(tostring(slots)) end
            return word(L["Shards"] .. " ") .. v, v
        end,
        tip = function()
            tipTitle(L["Soul Shards"])
            line(L["In your bags"], tostring(DT.ReadShards()), { Style.Accent() })
            local slots, free = 0, 0
            if DT.SoulBagOn() then slots, free = DT.ReadSoulBag() end
            if slots > 0 then
                line(L["Soul bag slots"], tostring(slots))
                line(L["Free slots"], tostring(free), { Style.Accent() })
            end
            gap()
            hint(L["Click: bags"])
        end,
        click = function() openBags() end, opens = "bags" },
    ammo = { name = "Ammo", events = { "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" },
        unitEvents = { "UNIT_INVENTORY_CHANGED" },   -- each shot
        count = function() return DT.ReadAmmo() end,
        text = function(n)
            n = n or DT.ReadAmmo()
            local v = n and value(tostring(n), ammoColor(n)) or value("-")
            return word(L["Ammo"] .. " ") .. v, v
        end,
        tip = function()
            local n, name = DT.ReadAmmo()
            tipTitle(L["Ammo"])
            if not n then
                line(L["Ammo"], "-")
            else
                if name then line(L["Loaded"], name) end
                line(L["In your bags"], tostring(n), ammoColor(n))
            end
            gap()
            hint(InCombatLockdown() and not charInFight() and L["Click: character window (after combat)"] or L["Click: character window"])
        end,
        click = openCharacter, opens = "character" },
    speed = { name = "Movement speed", poll = true,
        text = function()
            local sp = DT.ReadSpeed()
            local v = value(sp and (sp.now .. "%") or "-")
            return word(L["Speed"] .. " ") .. v, v
        end,
        tip = function()
            local sp = DT.ReadSpeed()
            tipTitle(L["Movement speed"])
            if not sp then
                line(L["Speed"], "-")
            else
                line(L["On land"], sp.run .. "%")
                if sp.swim then line(L["Swimming"], sp.swim .. "%") end
                if sp.fly and sp.fly > 0 then line(L["Flying"], sp.fly .. "%") end
            end
            gap()
            hint(InCombatLockdown() and not charInFight() and L["Click: character window (after combat)"] or L["Click: character window"])
        end,
        click = openCharacter, opens = "character" },
    hearth = { name = "Hearthstone", poll = true,
        text = function()
            local home, left = DT.ReadHearth()
            local where = home or L["Hearthstone"]
            if left > 0 then
                local v = value(DT.Duration(left), DT.WARN)
                return word(where .. " ") .. v, v
            end
            local v = value(where)
            return v, v
        end,
        tip = function()
            local home, left, have = DT.ReadHearth()
            tipTitle(L["Hearthstone"])
            line(L["Home"], home or "-")
            line(L["Cooldown"], left > 0 and DT.Duration(left) or L["Ready"], left > 0 and DT.WARN or DT.GOOD)
            gap()
            if not have then hint(L["No Hearthstone in your bags."]) return end
            hint(InCombatLockdown() and L["Click: use (after combat)"] or L["Click: use"])
        end,
        over = DT.HearthOver },
    equipset = { name = "Equipment set",
        events = { "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" },
        onEvent = setsEvent,
        ownIcon = true,   -- the text starts with the set's own icon
        text = function()
            local sets, worn = DT.ReadSets()
            local waiting = DT.WaitingSet(sets)
            local s = waiting or worn
            -- A set waiting for the fight to end shows at once, in the warning color.
            if not s then
                local none = value(L["No set"], DT.LABEL)
                return none, none
            end
            local v = DT.SetIcon(s.icon) .. value(s.name, waiting and DT.WARN or nil)
            return word(L["Set"] .. " ") .. v, v
        end,
        tip = setsTip, click = setsClick },
}
DT.ORDER = { "gold", "durability", "bags", "social", "friends", "guild", "system", "time", "xp", "location", "coords",
             "combat", "volume", "ilvl", "played", "professions", "hearth",
             "crit", "ap", "sp", "hit", "shards", "ammo", "speed", "equipset" }
DT.NAMES = {}
for key, t in pairs(DT.TEXTS) do DT.NAMES[key] = t.name end

-- ---------------------------------------------------------------------
-- The strip
-- ---------------------------------------------------------------------

function DT.Height(size) return math.floor((size or 10) + DT.PAD_Y + 0.5) end

-- Extra panel height for the strip and its gap, 0 when off. With any = true,
-- returns the height it would take if on.
function DT.Room(db, any)
    local d = db and db.data
    if type(d) ~= "table" or (d.enabled ~= true and not any) then return 0 end
    return ns.Panel.PAD + DT.Height(d.textSize)
end

-- Text keys of the slots in use, in order.
function DT.Keys(d)
    local out = {}
    local n = math.max(1, math.min(DT.MAX, math.floor(num(d.count))))
    for i = 1, n do
        local k = d["slot" .. i]
        if DT.TEXTS[k] then out[#out + 1] = k end
    end
    return out
end

-- What a strip listens for: its texts and their events. The same answer
-- means its events are already registered.
function DT.EventsKey(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local t = DT.TEXTS[k]
        parts[#parts + 1] = k .. "=" .. tostring(t) .. ":" .. table.concat(t.events or {}, ",")
            .. "/" .. table.concat(t.unitEvents or {}, ",")
    end
    return table.concat(parts, ";")
end

-- Draws a slot's text with its accent spot. n overrides the number for
-- texts that count up.
local function drawText(s, t, n)
    cur = s
    local ok, long, short = pcall(t.text, n)
    cur = nil
    return ok, long, short
end

-- Gold counts from the shown amount to the new one, tinted gold while it
-- rises. Update has already laid out the strip for the final value, so each
-- step only rewrites this slot. First read, test mode and motion off skip it.
local function settle(s)
    if not s.rollText then return end
    s.rollText = nil
    if s.textW then s.text:SetWidth(s.textW) end
    s.text:SetText(s.isShort and s.short or s.long)
end

local function stopCount(s)
    DUI.Motion.Tween(s, 0, 0)   -- stop any count in progress
    settle(s)
end

function DT.CountGold(s, changed)
    local now = DT.ReadMoney()
    local from = s.rollShown
    if sample() or from == nil or not DUI.Motion.On() then
        stopCount(s)
        s.rollShown = not sample() and now or nil
        return
    end
    if not changed then
        if not s.rollText then s.rollShown = now end   -- copper only, nothing to count
        return
    end
    local up = now > from
    s.text:SetWidth(0)   -- unconstrained while counting, a falling amount is wider than its end
    DUI.Motion.Tween(s, from, now, DUI.Motion.SLOW, function(v)
        v = math.floor(v + 0.5)
        s.rollShown = v
        cur = s
        s.rollText = value(DT.ShortMoney(v), up and DT.GAIN or nil)
        cur = nil
        s.text:SetText(s.rollText)
    end, function() settle(s) end)
end

-- Bags, durability and online counts animate the same way. Each step is
-- drawn by the text itself so its warning color follows the number.
-- Jumps straight there on first read, in test mode, with no number, or
-- with motion off.
function DT.CountNumber(s, t, changed, now)
    now = type(now) == "number" and now or nil
    local from = s.rollShown
    if sample() or now == nil or type(from) ~= "number" or not DUI.Motion.On() then
        stopCount(s)
        s.rollShown = not sample() and now or nil
        return
    end
    if not changed or from == now then
        if not s.rollText then s.rollShown = now end
        return
    end
    s.text:SetWidth(0)
    DUI.Motion.Tween(s, from, now, DUI.Motion.NORMAL, function(v)
        v = math.floor(v + 0.5)
        s.rollShown = v
        local okText, long, short = drawText(s, t, v)
        if okText and type(long) == "string" then
            s.rollText = s.isShort and (type(short) == "string" and short or long) or long
            s.text:SetText(s.rollText)
        end
    end, function() settle(s) end)
end

-- Builds a strip of texts into S. DT is the panel's strip; DataBar.lua makes
-- more. opts.tip(slot) places the tooltip, opts.hover(slot, on) reports
-- mouseover, opts.spot(t) maps a position on the strip to the accent.
function DT.New(S, opts)
    opts = opts or {}
    local cfg, area
    local slots, seps = {}, {}
    S.slots = slots             -- exposed for tests

    function S.Attach(parent, c) area, cfg = parent, c end

    local function onEnter(self)
        if opts.hover and not DT.redrawing then opts.hover(self, true) end
        local t = DT.TEXTS[self.key]
        -- Texts with their own hover handling (some broker objects) use it.
        if t and t.enter then
            self.hover = true
            DUI.SafeCall(t.enter, self)
            return
        end
        if not (t and t.tip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        if opts.tip then
            opts.tip(self)
        else
            -- Below the strip, right-aligned since the panel is top right.
            -- The game keeps it on screen.
            GameTooltip:SetPoint("TOPRIGHT", area, "BOTTOMRIGHT", 0, -DT.TIP_GAP)
        end
        Tips.Clear()
        DUI.SafeCall(t.tip)
        DT.FlushTip()
        GameTooltip:Show()
        self.hover = true
        if not DT.redrawing then
            if t.over then DUI.SafeCall(t.over, self) elseif t.opens then DUI.SafeCall(DT.WindowOver, self) end
        end
    end

    local function onLeave(self)
        if opts.hover then opts.hover(self, false) end
        self.hover = false
        local t = DT.TEXTS[self.key]
        if t and t.leave then DUI.SafeCall(t.leave, self) end
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end

    local function onClick(self, button)
        -- A plugin's panel picks a slot's text this way, as ElvUI's panels do.
        if opts.pick and button == "RightButton" and IsShiftKeyDown() then return opts.pick(self) end
        local t = DT.TEXTS[self.key]
        if t and t.click then DUI.SafeCall(t.click, button, self) end
    end

    local function slot(i)
        local s = slots[i]
        if s then return s end
        s = CreateFrame("Button", nil, area)
        s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        s.__duiOwnTooltipSpot = true   -- tells the Tooltip module not to move it
        s.text = Style.Text(s, cfg.textSize, "CENTER", ns.MEDIA.font)
        s.text:SetPoint("CENTER", s, "CENTER", 0, 0)
        if s.text.SetWordWrap then s.text:SetWordWrap(false) end
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetPoint("RIGHT", s.text, "LEFT", -DT.ICON_GAP, 0)
        s.icon:Hide()
        s.iconW = 0
        s:SetScript("OnEnter", onEnter)
        s:SetScript("OnLeave", onLeave)
        s:SetScript("OnClick", onClick)
        s.enter, s.leave = onEnter, onLeave   -- for a secure button laid over it (hearth)
        s.pick = opts.pick   -- a plugin panel's Shift+right-click picks the slot's text
        -- Only texts with a wheel handler (volume) take the mouse wheel.
        s:SetScript("OnMouseWheel", function(self, delta)
            local t = DT.TEXTS[self.key]
            if t and t.wheel then DUI.SafeCall(t.wheel, delta, self) end
        end)
        slots[i] = s
        return s
    end

    local function sep(i)
        local t = seps[i]
        if t then return t end
        t = area:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(DT.SEP[1], DT.SEP[2], DT.SEP[3], DT.SEP[4])
        seps[i] = t
        return t
    end

    -- Spreads the texts across the strip, splitting the spare room evenly,
    -- with a divider between each pair. With glide, slots that move slide
    -- over instead of jumping.
    -- A text measured with each digit as wide as the widest one: most fonts
    -- draw a 1 narrower, so a framerate going 58 to 61 changed its width and
    -- slid every text after it a pixel back and forth. Now a slot only moves
    -- when the number gains or loses a digit. Icons keep their own numbers.
    local widest = {}
    local function wideDigit(fs)
        local font, size = fs:GetFont()
        local key = tostring(font) .. ":" .. tostring(size)
        if widest[key] then return widest[key] end
        local best, bw = "0", -1
        for d = 0, 9 do
            fs:SetText(tostring(d))
            local w = fs:GetStringWidth() or 0
            if type(w) == "number" and w > bw then best, bw = tostring(d), w end
        end
        widest[key] = best
        return best
    end
    local function steadyWidth(fs, text)
        text = text or ""
        local digit = wideDigit(fs)
        local icons = {}
        local wide = text:gsub("|[TA].-|[ta]", function(icon)
            icons[#icons + 1] = icon
            return ""
        end):gsub("(|c%x%x%x%x%x%x%x%x)", function(code)
            icons[#icons + 1] = code
            return ""
        end):gsub("%d", digit)
        local n = 0
        wide = wide:gsub("", function() n = n + 1; return icons[n] end)
        fs:SetText(wide)
        local w = fs:GetStringWidth() or 0
        fs:SetText(text)
        return w
    end

    function S.Layout(glide)
        if not (area and S.keys) then return end
        local n = #S.keys
        local W = area:GetWidth()
        if n == 0 then
            for _, s in ipairs(slots) do s:Hide() end
            for _, t in ipairs(seps) do t:Hide() end
            return
        end
        if type(W) ~= "number" or W <= 0 then return end
        -- Measure both versions, then drop labels one at a time (biggest
        -- saving first) until everything fits.
        local function measure(s, short)
            return steadyWidth(s.text, short and s.short or s.long)
        end
        local words = cfg.labels == true
        local sum = 0
        for i = 1, n do
            local s = slots[i]
            s.wShort = measure(s, true)
            s.wLong = words and measure(s, false) or s.wShort
            s.isShort = not words
            s.w = s.wLong + s.iconW
            sum = sum + s.w
        end
        while sum + (n - 1) * DT.MIN_GAP > W do
            local best, gain = nil, 0
            for i = 1, n do
                local s = slots[i]
                if not s.isShort and s.wLong - s.wShort > gain then best, gain = s, s.wLong - s.wShort end
            end
            if not best then break end
            best.isShort, best.w = true, best.wShort + best.iconW
            sum = sum - gain
        end
        local short = false
        for i = 1, n do
            local s = slots[i]
            s.text:SetText(s.rollText or (s.isShort and s.short or s.long))
            if s.isShort and words then short = true end
        end
        S.short = short
        local gap = math.max(0, (W - sum) / n)
        local h = area:GetHeight()
        local x = 0
        local lineH = math.max(1, math.floor(h * 0.55 + 0.5))
        local px = Pixel.Px(area, 1)
        -- Truncate only if it still doesn't fit with every label dropped.
        local cap = sum > W and W / n or math.huge
        for i = 1, n do
            local s = slots[i]
            if glide and s.x and s.x ~= x and s:IsShown() then DUI.Motion.Glide(s, s.x - x, 0, DUI.Motion.FAST) end
            s.x = x
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", area, "TOPLEFT", x, 0)
            s:SetSize(math.max(1, s.w + gap), h)
            s.textW = math.max(1, math.min(s.w + 1, cap) - s.iconW)
            s.text:SetWidth(s.rollText and 0 or s.textW)
            s:Show()
            x = x + s.w + gap
            local t = sep(i)
            if i < n then
                if glide and t.x and t.x ~= x and t:IsShown() then DUI.Motion.Glide(t, t.x - x, 0, DUI.Motion.FAST) end
                t.x = x
                t:ClearAllPoints()
                t:SetPoint("CENTER", area, "LEFT", x, 0)
                t:SetSize(px, lineH)
                t:Show()
            else
                t:Hide()
            end
        end
        for i = n + 1, #slots do slots[i]:Hide() end
        for i = n, #seps do seps[i]:Hide() end
    end

    -- True if the new text has the same width as at the last layout (fps
    -- ticking 59 to 61), so nothing needs to move.
    local function sameWidth(s)
        if not (s.wLong and s.wShort) then return false end
        local fs = s.text
        local ws = steadyWidth(fs, s.short)
        local wl = ws
        if cfg.labels == true then wl = steadyWidth(fs, s.long) end
        fs:SetText(s.isShort and s.short or s.long)
        return math.abs(ws - s.wShort) < 0.5 and math.abs(wl - s.wLong) < 0.5
    end

    -- Redraws texts (only polled ones if onlyPolled). Re-lays out the strip
    -- only when a width changed.
    function S.Update(onlyPolled, onlyKeys)
        if not (area and S.keys and area:IsShown()) then return end
        local moved, gold, goldMoved = false, nil, false
        local counted
        for i, key in ipairs(S.keys) do
            local t = DT.TEXTS[key]
            if (not onlyPolled or t.poll) and (not onlyKeys or onlyKeys[key]) then
                local s = slots[i]
                -- Read the number once and reuse it; reading bags walks every slot.
                local n
                if t.count then
                    local okCount, v = pcall(t.count)
                    n = okCount and type(v) == "number" and v or nil
                end
                local ok, long, short = drawText(s, t, n)
                if ok and type(long) == "string" then
                    short = type(short) == "string" and short or long
                    if long ~= s.long or short ~= s.short then
                        s.long, s.short = long, short
                        s.text:SetText(s.isShort and short or long)
                        -- Lay out for gold's final value (rare, event-driven).
                        if key == "gold" then goldMoved, moved = true, true end
                        if t.count then
                            counted = counted or {}
                            counted[s] = { t, n }
                        end
                        if not moved and not sameWidth(s) then moved = true end
                    end
                    if key == "gold" then gold = s end
                end
                -- Refresh an open tooltip too.
                if s.hover and GameTooltip:IsOwned(s) then
                    DT.redrawing = true
                    onEnter(s)
                    DT.redrawing = false
                end
            end
        end
        if moved then S.Layout(true) end
        if gold then DT.CountGold(gold, goldMoved) end
        if counted then for s, c in pairs(counted) do DT.CountNumber(s, c[1], true, c[2]) end end
    end

    -- Only events for slotted texts are registered.
    local events = CreateFrame("Frame")
    local byEvent = {}
    events:SetScript("OnEvent", function(_, event, ...)
        local keys = byEvent[event]
        if not keys then return end
        -- Texts with their own state (combat, time played) update it first.
        for key in pairs(keys) do
            local t = DT.TEXTS[key]
            if t.onEvent then t.onEvent(event, ...) end
        end
        S.Update(false, keys)
    end)
    DT.strips[#DT.strips + 1] = S

    local ticker
    local function poll(on)
        if not on then
            if ticker then ticker:Cancel() end
            ticker = nil
            return
        end
        if ticker then return end
        ticker = C_Timer.NewTicker(DT.POLL, function() S.Update(true) end)
    end

    -- Icon plus text are centered together in the slot.
    local function dressIcon(s, t)
        local on = cfg.icons == true and not t.ownIcon and (not t.iconOf or t.iconOf() ~= nil)
        local px = cfg.textSize + DT.ICON_UP
        s.iconW = on and px + DT.ICON_GAP or 0
        s.text:ClearAllPoints()
        s.text:SetPoint("CENTER", s, "CENTER", s.iconW / 2, 0)
        s.icon:SetShown(on)
        if not on then return end
        s.icon:SetSize(px, px)
        -- Broker icons keep their colors; built-in icons take the accent.
        if t.iconOf then
            local file, coords, tint = t.iconOf()
            s.icon:SetTexture(file)
            if type(coords) == "table" then s.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else s.icon:SetTexCoord(0, 1, 0, 1) end
            s.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
            return
        end
        s.icon:SetTexCoord(0, 1, 0, 1)
        s.icon:SetTexture(DUI.MEDIA .. "ui-data-" .. s.key .. ".png")
        s.icon:SetVertexColor(DT.Ink(s))
    end

    -- Called after the panel lays out. Sets up texts, size, events and ticker.
    function S.Apply(c)
        cfg = c
        if not area then return end
        local on = c.enabled == true and area:IsShown()
        -- A style repaint calls this too, with the same texts. Their events
        -- and the guild roster request only change with the texts themselves.
        local keys = on and DT.Keys(c) or nil
        local wired = on and DT.EventsKey(keys) or false
        local rewire = wired ~= S.wired
        S.wired = wired
        if rewire then
            events:UnregisterAllEvents()
            for k in pairs(byEvent) do byEvent[k] = nil end
        end
        if not on then
            S.keys = nil
            poll(false)
            for _, s in ipairs(slots) do s:Hide() end
            for _, t in ipairs(seps) do t:Hide() end
            return
        end
        for _, t in ipairs(seps) do t.x = nil end
        S.keys = keys
        local polled = false
        local guild = false
        for i, key in ipairs(keys) do
            local s = slot(i)
            s.key = key
            s.spot = #keys > 1 and (i - 1) / (#keys - 1) or nil   -- spread evenly along the accent
            if opts.spot then s.spot = opts.spot(s.spot or 0.5) end
            s.ink, s.inkCustom = c.numberColor, c.numberCustom
            s.long, s.short = nil, nil
            s.wLong, s.wShort = nil, nil   -- re-measure
            stopCount(s)
            s.rollShown = nil
            s.x = nil   -- fresh layout, no glide
            Style.SetTextSize(s.text, c.textSize)
            local t = DT.TEXTS[key]
            dressIcon(s, t)
            s:EnableMouseWheel(t.wheel ~= nil)
            if t.poll then polled = true end
            if key == "social" or key == "guild" then guild = true end
            if rewire then
                for _, e in ipairs(t.events or {}) do
                    byEvent[e] = byEvent[e] or {}
                    byEvent[e][key] = true
                    pcall(events.RegisterEvent, events, e)
                end
                for _, e in ipairs(t.unitEvents or {}) do   -- player only
                    byEvent[e] = byEvent[e] or {}
                    byEvent[e][key] = true
                    pcall(events.RegisterUnitEvent, events, e, "player")
                end
            end
        end
        poll(polled)
        -- The guild online count arrives with the roster.
        if rewire and guild and call(_G.IsInGuild) == true then call(api("C_GuildInfo", "GuildRoster")) end
        -- Slots were reset above, so this also lays out the strip.
        S.Update()
    end
    return S
end

DT.New(DT)

function DT.Build(parent, mod)
    DT.Attach(parent, mod.db.data)
    -- Save gold even when the gold text isn't shown, so the tooltip has
    -- every character once it is.
    DUI.RegisterEvent("PLAYER_MONEY", DT.SaveMoney)
    if ns.Broker then
        ns.Broker.Watch()
        ns.Broker.TakePlugins()
        ns.Broker.TakePanels()
    end
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if ns.Broker then ns.Broker.Watch() end
        DT.SaveMoney()
        DT.Update()
    end)
    DT.SaveMoney()
end
