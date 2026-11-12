-- A fake LossOfControlFrame (the game's Blizzard_FrameXML/LossOfControlFrame), only
-- what its skin touches: the pieces of its XML by their keys, and SetUpDisplay's
-- writes to them. Hidden until an effect lands, as in the XML; the frame's own logic
-- isn't copied.
local stub = require("stub")

local LW = {}

function LW.Install()
    local f = CreateFrame("Frame", "LossOfControlFrame", UIParent)
    f:SetSize(256, 58)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("MEDIUM")
    f:Hide()
    f.blackBg = f:CreateTexture()
    f.RedLineTop = f:CreateTexture()
    f.RedLineBottom = f:CreateTexture()
    f.Icon = f:CreateTexture()
    f.AbilityName = f:CreateFontString()
    f.Cooldown = CreateFrame("Cooldown", nil, f)
    f.TimeLeft = CreateFrame("Frame", nil, f)
    f.TimeLeft.NumberText = f.TimeLeft:CreateFontString()
    f.TimeLeft.SecondsText = f.TimeLeft:CreateFontString()
    _G.LOSS_OF_CONTROL_DISPLAY_STUN = "Stunned"
    Enum.StatusBarFillStyle = { Standard = 0, StandardNoRangeFill = 1, Center = 2, Reverse = 3 }
    _G.Constants = _G.Constants or {}
    _G.Constants.LossOfControlConsts = { LOSS_OF_CONTROL_ACTIVE_INDEX = 1 }
    LW.effect = nil
    _G.C_LossOfControl = {
        GetActiveLossOfControlData = function(i) return i == 1 and LW.effect and LW.effect.data or nil end,
        GetActiveLossOfControlDuration = function(unit, i)
            return unit == "player" and i == 1 and LW.effect and LW.effect.duration or nil
        end,
    }
    return f
end

-- An effect lands: fills the game's frame as SetUpDisplay does and shows it.
-- time nil means no timer line, and duration nil means nothing for the client's bar.
function LW.Land(f, text, icon, time, displayType, duration)
    -- Under restrictions every field except priority and displayType is secret (the game's docs).
    local secret = type(text) == "table"
    local s = function(v) return secret and stub.Secret(v) or v end
    LW.effect = { data = { displayType = displayType or 2, priority = 5, locType = s("STUN"), spellID = s(853), displayText = text,
                           iconTexture = icon, startTime = s(100), timeRemaining = s(3), duration = s(4), lockoutSchool = s(0) },
                  duration = duration }
    f.AbilityName:SetText(text)
    f.Icon:SetTexture(icon)
    f.TimeLeft:SetShown(time ~= nil)
    if time ~= nil then f.TimeLeft.NumberText:SetText(time) end
    f:Show()
end

return LW
