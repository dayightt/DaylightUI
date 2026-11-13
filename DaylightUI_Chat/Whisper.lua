-- Whisper sound: one of the addon's own (Breath by default, or Dewdrop, Hello,
-- Warm bell, Wood pop from Media/whisper-*.ogg), the game's, or none.
-- It plays from a separate event frame, at most once every few seconds, because
-- the game's message filters skip any line with a secret part, and every
-- Battle.net whisper's sender is secret. The game's own sound file is muted while
-- ours or none is picked. A file mute lasts until the game restarts, so it's
-- reapplied at every login, and an account-wide flag records that the mute is
-- ours so we never lift someone else's. The guild chat sound (none by default)
-- picks from the same sounds and listens the same way.

local _, ns = ...
local DUI = DaylightUI

local Whisper = {}
ns.Whisper = Whisper

-- Sound files by setting value. "soft" is Breath; the key predates the others.
local MEDIA = "Interface\\AddOns\\DaylightUI\\Media\\whisper-"
Whisper.SOUNDS = { soft = MEDIA .. "breath.ogg", dewdrop = MEDIA .. "dewdrop.ogg",
                   hello = MEDIA .. "hello.ogg", bell = MEDIA .. "bell.ogg", pop = MEDIA .. "pop.ogg" }
Whisper.GAME_FILE = 567421 -- file the game's whisper sound (SOUNDKIT.TELL_MESSAGE) plays
Whisper.COOLDOWN = 5 -- minimum seconds between two sounds
Whisper.EVENTS = { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }
Whisper.GUILD_EVENTS = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" }

local choice = "soft"
local last = -math.huge
local mutedNow = false -- muted by us during this game session
local guildChoice = "none"
local guildLast = -math.huge

-- The current sound, ours or the game's (for the Play button).
function Whisper.Play()
    local file = Whisper.SOUNDS[choice]
    if file then
        if type(PlaySoundFile) == "function" then PlaySoundFile(file, "SFX") end
    elseif choice == "game" and type(PlaySound) == "function" and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        PlaySound(SOUNDKIT.TELL_MESSAGE, "SFX")
    end
end

function Whisper.OnWhisper()
    if not Whisper.SOUNDS[choice] then return end
    local now = GetTime()
    if now - last < Whisper.COOLDOWN then return end
    last = now
    Whisper.Play()
end

-- The guild chat sound, for its Play button.
function Whisper.PlayGuild()
    local file = Whisper.SOUNDS[guildChoice]
    if file and type(PlaySoundFile) == "function" then PlaySoundFile(file, "SFX") end
end

-- Your own lines are skipped by their GUID (arg12). A secret GUID can't be
-- compared, so that line just plays.
function Whisper.OnGuild(_, _, _, _, _, _, _, _, _, _, _, _, guid)
    if not Whisper.SOUNDS[guildChoice] then return end
    if type(guid) == "string" and not issecretvalue(guid) then
        local mine = UnitGUID("player")
        if type(mine) == "string" and not issecretvalue(mine) and guid == mine then return end
    end
    local now = GetTime()
    if now - guildLast < Whisper.COOLDOWN then return end
    guildLast = now
    Whisper.PlayGuild()
end

local function applyMute()
    local root = DUI.DB.Root()
    if choice ~= "game" then
        if not mutedNow and type(MuteSoundFile) == "function" then
            MuteSoundFile(Whisper.GAME_FILE)
            mutedNow = true
            root.tellMuted = true
        end
    elseif mutedNow or root.tellMuted then
        if type(UnmuteSoundFile) == "function" then UnmuteSoundFile(Whisper.GAME_FILE) end
        mutedNow = false
        root.tellMuted = nil
    end
end

function Whisper.Apply(cfg)
    local was, guildWas = choice, guildChoice
    choice = cfg.whisperSound or "soft"
    guildChoice = cfg.guildSound or "none"
    applyMute()
    if not Whisper.registered then
        Whisper.registered = true
        for _, e in ipairs(Whisper.EVENTS) do DUI.RegisterEvent(e, Whisper.OnWhisper) end
        for _, e in ipairs(Whisper.GUILD_EVENTS) do DUI.RegisterEvent(e, Whisper.OnGuild) end
        return
    end
    -- Just picked in the options: play it once.
    if choice ~= was and Whisper.SOUNDS[choice] then Whisper.Play() end
    if guildChoice ~= guildWas and Whisper.SOUNDS[guildChoice] then Whisper.PlayGuild() end
end
