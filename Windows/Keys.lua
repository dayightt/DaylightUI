-- Keyboard shortcuts for windows, DialogueKey style. While a window is open it
-- takes the keys its handler claims (1-9, Enter, Space, Escape) and passes every
-- other key to the game, so the player can still move and cast.
--
-- SetPropagateKeyboardInput is restricted in combat, so during a fight every key
-- goes to the game. A window first opened in combat picks up its keys afterwards.
--
--   Win.Keys(frame, function(key) return handled end)

local _, DUI = ...

local Win = DUI.Win

local KEYS = {}
Win.KeysOf = KEYS

-- 1-9 from the number row or the numpad.
function KEYS.Number(key)
    local n = type(key) == "string" and (key:match("^(%d)$") or key:match("^NUMPAD(%d)$"))
    n = tonumber(n)
    if n and n >= 1 and n <= 9 then return n end
end

local function propagate(f, on)
    if InCombatLockdown() then return end
    pcall(f.SetPropagateKeyboardInput, f, on)
end

local apply

function Win.Keys(f, handler)
    local k = CreateFrame("Frame", nil, f)
    k:SetAllPoints(f)
    k:EnableKeyboard(false)
    propagate(k, true)
    k:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local used = handler(key) == true
        propagate(self, not used)
    end)
    -- Go back to passing keys right away, so combat starting mid-press
    -- can't leave the game's keys stuck on this frame.
    k:SetScript("OnKeyUp", function(self) propagate(self, true) end)
    k:SetScript("OnHide", function(self) propagate(self, true) end)
    k:RegisterEvent("PLAYER_REGEN_DISABLED")
    k:SetScript("OnEvent", function(self)
        pcall(self.SetPropagateKeyboardInput, self, true)
        -- Too late to change propagation, so drop the keyboard for the fight
        -- instead of swallowing the game's keys.
        if self:IsKeyboardEnabled() and not self:GetPropagateKeyboardInput() then
            self:EnableKeyboard(false)
            DUI.AfterCombat(function() apply(self) end, self)
        end
    end)
    f.keys = k
    return k
end

-- A frame doesn't propagate keys until told to, and can't be told in combat.
-- Enabling the keyboard before that would swallow movement and spells, so the
-- keyboard is only turned on once propagation is set, after combat if needed.
apply = function(k)
    if not k.wanted then k:EnableKeyboard(false); return end
    propagate(k, true)
    if k:GetPropagateKeyboardInput() then
        k:EnableKeyboard(true)
    else
        k:EnableKeyboard(false)
        DUI.AfterCombat(function() apply(k) end, k)
    end
end

function Win.KeysOn(f, on)
    local k = f.keys
    if not k then return end
    k.wanted = on and true or false
    apply(k)
end
