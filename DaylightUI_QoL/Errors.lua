-- Quiet error messages: the red "Not enough rage", "Spell is not ready yet",
-- "Out of range", "You have no target" spam stays off the screen (and its
-- voice line quiet). The useful ones (bags full, can't loot, interrupted,
-- inventory, quests, line of sight) still show.
--
-- UIErrorsFrame skips every message type in BLACK_LISTED_MESSAGE_TYPES. Types
-- are added there through DUI.ClaimMessageType, which only removes what it added.
-- No hook and no per-message work: the lookup is by type id, so the (possibly
-- secret) text is never read and it works in every language.
--
-- With errorSound on, a quieted error plays a soft sound instead of the voice
-- line, at most once per Errors.GAP so mashing a key stays calm.

local _, ns = ...
local DUI = DaylightUI

local Errors = {}
ns.Errors = Errors
ns.features[#ns.features + 1] = Errors

-- The game's message types we quiet, by the client's LE_GAME_ERR_<name>
-- constants. A name this client doesn't have is skipped.
Errors.TYPES = {
    -- Not enough of a resource
    "OUT_OF_MANA", "OUT_OF_RAGE", "OUT_OF_ENERGY", "OUT_OF_FOCUS", "OUT_OF_HEALTH",
    "OUT_OF_COMBO_POINTS", "SPELL_FAILED_NO_COMBO_POINTS", "OUT_OF_POWER_DISPLAY",
    "OUT_OF_RUNES", "OUT_OF_RUNIC_POWER", "OUT_OF_HOLY_POWER", "OUT_OF_SOUL_SHARDS",
    "OUT_OF_CHI", "OUT_OF_PAIN", "OUT_OF_ARCANE_CHARGES", "OUT_OF_LUNAR_POWER",
    "OUT_OF_INSANITY", "OUT_OF_FURY", "OUT_OF_MAELSTROM", "OUT_OF_ESSENCE",
    -- Not ready yet
    "ABILITY_COOLDOWN", "SPELL_COOLDOWN", "ITEM_COOLDOWN", "SPELL_FAILED_NOT_READY",
    "SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_ANOTHER_IN_PROGRESS",
    "SPELL_FAILED_CASTER_AURASTATE", "SPELL_FAILED_TARGET_AURASTATE",
    -- Range, facing, moving
    "OUT_OF_RANGE", "SPELL_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE", "SPELL_FAILED_TOO_CLOSE",
    "BADATTACKPOS", "BADATTACKFACING", "SPELL_FAILED_UNIT_NOT_INFRONT",
    "SPELL_FAILED_NOT_INFRONT", "SPELL_FAILED_NOT_BEHIND", "SPELL_FAILED_MOVING",
    -- No target, or the wrong one
    "GENERIC_NO_TARGET", "GENERIC_NO_VALID_TARGETS", "NO_ATTACK_TARGET", "INVALID_ATTACK_TARGET",
    "SPELL_FAILED_BAD_TARGETS", "SPELL_FAILED_BAD_IMPLICIT_TARGETS", "SPELL_FAILED_TARGETS_DEAD",
    "SPELL_FAILED_TARGET_FRIENDLY", "SPELL_FAILED_TARGET_ENEMY",
}

Errors.GAP = 0.4   -- seconds between ticks while a key is mashed
Errors.OWNER = "quiet"

local mod, listening, lastTick

local function wanted() return mod and mod.db and mod.db.quietErrors == true end

local function onError(_, errorType)
    if issecretvalue and issecretvalue(errorType) then return end
    -- Only the types we hide (not the game's own quiet one), and as the game
    -- does, no sound while it holds its messages back.
    if DUI.MessageTypeOwner(errorType) ~= Errors.OWNER then return end
    if not (mod.db and mod.db.errorSound == true) or DUI.GameMessagesSuppressed() then return end
    local now = GetTime()
    if lastTick and now - lastTick < Errors.GAP then return end
    lastTick = now
    DUI.Sound.Play("nope")
end

local function apply()
    local claim = wanted()
    for _, name in ipairs(Errors.TYPES) do
        local id = _G["LE_GAME_ERR_" .. name]
        if claim then DUI.ClaimMessageType(id, Errors.OWNER) else DUI.ReleaseMessageType(id, Errors.OWNER) end
    end
end

function Errors.Enable(m)
    mod = m
    -- Always listening (the shared event frame has no unregister); nothing
    -- is ours while quiet errors is off, so nothing plays then.
    if not listening then
        listening = true
        DUI.RegisterEvent("UI_ERROR_MESSAGE", onError)
    end
    apply()
end

function Errors.Refresh(m)
    mod = m
    apply()
end
