-- The Professions key (whatever is bound to TOGGLEPROFESSIONBOOK, K by default) opens
-- the last used profession in this window instead of the game's overview, which
-- never shows.
--
-- Addon code can't open a profession itself: OpenTradeSkill needs a hardware event
-- (ADDON_ACTION_BLOCKED when called from an update). So the key casts the profession
-- spell instead, through an override binding (SetOverrideBindingClick, never the
-- player's saved binds; it goes away on /reload or when the window is turned off) that
-- clicks a secure button set to that spell. Keys are re-read from the game's binding on
-- UPDATE_BINDINGS, so a rebound key follows and an unbound one takes nothing.
--
-- Pressed while the window is open, it closes it, like the game's toggle. This works
-- in combat too, since the binding was set beforehand; only changes wait for combat to
-- end. The button's spell can't be cleared in combat, so a press there always casts
-- (presumably the spell closes an open trade skill, not yet confirmed in game). After
-- an out-of-combat press the spell is set back right away in PostClick, so combat
-- never starts with a key that casts nothing.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

local Key = {}
ns.Key = Key

Key.NAME = "DaylightUICraftKey"
Key.BINDING = "TOGGLEPROFESSIONBOOK"

-- The spell the key casts: the last used profession, else the first with a crafting
-- window. nil when there's none, so the key stays the game's.
function Key.Spell()
    local tabs = ns.Data.Tabs()
    if #tabs == 0 then return nil end
    local char = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    local want = char and char.craftLast
    for _, t in ipairs(tabs) do if t.skillLine == want then return t.spellID end end
    return tabs[1].spellID
end

local function make()
    local ok, b = pcall(CreateFrame, "Button", Key.NAME, UIParent, "SecureActionButtonTemplate")
    if not ok or type(b) ~= "table" then return nil end
    -- Act on key down only. A binding sends both down and up, and PreClick ran on both, so
    -- the up closed what the down had just opened. useOnKeyDown makes the secure code act
    -- on that same press.
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)
    b:Hide()
    -- Window open: the key closes it and casts nothing.
    b:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        local W = ns.Window
        if W and W.frame and DUI.Win.IsOpen(W.frame) then
            self:SetAttribute("type", nil)
            W.Close()
        else
            self:SetAttribute("type", self.spell and "spell" or nil)
        end
    end)
    b:SetScript("PostClick", function(self)
        if not InCombatLockdown() then self:SetAttribute("type", self.spell and "spell" or nil) end
    end)
    return b
end

-- The binding's keys as one string, to detect changes.
local function keysNow()
    if type(GetBindingKey) ~= "function" then return "" end
    local out = {}
    for _, key in ipairs({ GetBindingKey(Key.BINDING) }) do
        if type(key) == "string" and key ~= "" then out[#out + 1] = key end
    end
    return table.concat(out, " ")
end

-- Out of combat (changes during combat wait), bind the keys to the button and set the
-- spell. Nothing to do if the spell and keys are unchanged.
function Key.Apply()
    if InCombatLockdown() then
        DUI.AfterCombat(Key.Apply, "craft:key")
        return
    end
    Key.button = Key.button or make()
    local b = Key.button
    if not b then return end
    Key.owner = Key.owner or CreateFrame("Frame")
    local spell = Key.Spell()
    local keys = spell and keysNow() or ""
    b.spell = spell
    b:SetAttribute("type", spell and "spell" or nil)
    b:SetAttribute("spell", spell)
    if Key.bound and Key.bound.spell == spell and Key.bound.keys == keys then return end
    Key.bound = { spell = spell, keys = keys }
    ClearOverrideBindings(Key.owner)
    if not spell then return end
    for key in keys:gmatch("%S+") do SetOverrideBindingClick(Key.owner, false, key, Key.NAME, "LeftButton") end
end

function Key.Init()
    if Key.ready then return end
    Key.ready = true
    DUI.RegisterEvent("UPDATE_BINDINGS", function() Key.Apply() end)
    DUI.RegisterEvent("SKILL_LINES_CHANGED", function() Key.Apply() end)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function() Key.Apply() end)
    Key.Apply()
end
