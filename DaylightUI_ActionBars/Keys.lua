-- Keybinds on our bars. Your keybinds stay on the game's commands and press the
-- game's hidden buttons, which cast the same slot ours shows (Paging copies bar 1's
-- page onto them). That keeps cast on key down, hold to keep casting and the
-- vehicle bar working as the game does. This file shows the key on our buttons and
-- gives them the pressed look while a key is down.

local _, ns = ...
local DUI = DaylightUI

local Keys = {}
ns.Keys = Keys

Keys.POLL = 0.1              -- how often a held key is rechecked (in case of a missed "up")

local function buttons() return ns.Buttons.All() end

-- Copies the game's keybind text onto each button. The skin's label shows it
-- (shortened, and blank for the game's range dot when unbound).
function Keys.UpdateText()
    for _, btn in ipairs(buttons()) do
        local hk = btn.HotKey
        if type(hk) == "table" then
            -- The game's template hides this text itself when it thinks there's
            -- no key. Our buttons never get that update, so show it.
            hk:Show()
            local key = GetBindingKey(btn.commandName)
            if type(key) == "string" then
                hk:SetText(GetBindingText(key, true))
            else
                hk:SetText(RANGE_INDICATOR or "●")
            end
            if ns.Skin and ns.Skin.UpdateKey then ns.Skin.UpdateKey(btn) end
        end
    end
end

-- Our button standing in for a game bar's button. barName is the game's bar
-- (MainActionBar for bar 1), id the button's number.
function Keys.ButtonFor(barName, id)
    for _, def in ipairs(ns.Bars.DEFS) do
        if def.twin == barName then
            local list = ns.Bars.buttons[def.key]
            return list and list[id]
        end
    end
end

local down = {}
local pollIn = 0

-- The poll runs on the keys frame's OnUpdate only while a key is down.
local function polling()
    local f = Keys.frame
    if not f then return end
    local on = type(next(down)) ~= "nil"
    if on == (type(f:GetScript("OnUpdate")) == "function") then return end
    if on then pollIn = Keys.POLL end
    f:SetScript("OnUpdate", on and Keys.OnUpdate or nil)
end

-- Our buttons are always skinned, so the pressed look is the skin's.
function Keys.SetDown(btn, on)
    on = on == true
    down[btn] = on or nil
    ns.Skin.SetKeyDown(btn, on)
    polling()
end

-- Is any key bound to this command still held? Takes the keys as the game returns
-- them, so no table per poll.
local function anyHeld(...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if type(key) == "string" then
            local base = string.match(key, "([^%-]+)$") or key
            if IsKeyDown(base) then return true end
        end
    end
    return false
end
local function held(cmd) return anyHeld(GetBindingKey(cmd)) end

-- Clears a missed "up" (the key was released over something that took it).
function Keys.OnUpdate(_, dt) Keys.Poll(dt) end
function Keys.Poll(dt)
    pollIn = pollIn - (dt or 0)
    if pollIn > 0 then return end
    pollIn = Keys.POLL
    for btn in pairs(down) do
        if not held(btn.commandName) then Keys.SetDown(btn, false) end
    end
end

function Keys.Owner()
    if not Keys.owner then Keys.owner = CreateFrame("Frame", "DaylightUIBarKeys", UIParent) end
    return Keys.owner
end

-- A key pressing the hidden twin of a flyout slot would open the flyout on a button
-- nobody sees, so those keys click our button instead. Rebuilt out of combat only,
-- since override bindings are protected.
function Keys.UpdateFlyouts()
    local owner = Keys.Owner()
    ClearOverrideBindings(owner)
    for _, btn in ipairs(buttons()) do
        local slot = ns.Buttons.SlotOf(btn)
        if slot and GetActionInfo(slot) == "flyout" then
            for _, key in ipairs({ GetBindingKey(btn.commandName) }) do
                SetOverrideBindingClick(owner, false, key, btn:GetName(), "LeftButton")
            end
        end
    end
end

-- Which way a bar's flyouts open: up from a bar in the lower half, down in the upper.
-- A vertical bar opens toward the middle.
function Keys.Direction(def)
    local x, y = ns.Bars.holders[def.key]:GetCenter()
    if type(x) ~= "number" then return "UP" end
    if ns.Bars.Config(def).vertical then return x < UIParent:GetWidth() / 2 and "RIGHT" or "LEFT" end
    return y < UIParent:GetHeight() / 2 and "UP" or "DOWN"
end

function Keys.UpdateDirections()
    for _, def in ipairs(ns.Bars.DEFS) do
        if def.kind == "action" then
            local dir = Keys.Direction(def)
            for _, btn in ipairs(ns.Bars.buttons[def.key]) do btn:SetAttribute("flyoutDirection", dir) end
        end
    end
end

-- The game's key handlers: bar 1's take the button number, the others take the game
-- bar's name and the number.
local function hookPresses()
    for _, h in ipairs({ { "ActionButtonDown", true }, { "ActionButtonUp", false } }) do
        if type(_G[h[1]]) == "function" then
            hooksecurefunc(h[1], function(id)
                local b = Keys.ButtonFor("MainActionBar", id)
                if b then Keys.SetDown(b, h[2]) end
            end)
        end
    end
    for _, h in ipairs({ { "MultiActionButtonDown", true }, { "MultiActionButtonUp", false } }) do
        if type(_G[h[1]]) == "function" then
            hooksecurefunc(h[1], function(barName, id)
                local b = Keys.ButtonFor(barName, id)
                if b then Keys.SetDown(b, h[2]) end
            end)
        end
    end
end

-- Which key casts what, by spell name. The Cooldown Manager icons ask; a piece's
-- spell can be a different rank than the one on the bar, so never by id. Built on
-- first use and dropped on Keys.EVENTS. The first bar with a key wins.
local castKeys
local function plain(v) return not (issecretvalue and issecretvalue(v)) end

local function nameIn(slot)
    local what, id = GetActionInfo(slot)
    if not (plain(what) and plain(id)) then return false end
    if what == "item" then
        local get = type(C_Item) == "table" and C_Item.GetItemNameByID
        return type(get) == "function" and get(id) or nil
    end
    local sid = ns.Buttons.SpellOf(slot)
    if type(sid) == "nil" then return nil end
    if not plain(sid) then return false end
    return C_Spell.GetSpellName(sid)
end

-- Returns the map, and true when a secret cut it short (then it isn't cached).
local function buildCastKeys()
    local out = {}
    for _, btn in ipairs(buttons()) do
        local key = btn.commandName and GetBindingKey(btn.commandName)
        local slot = type(key) == "string" and ns.Buttons.SlotOf(btn)
        if slot then
            local name = nameIn(slot)
            if name == false or not plain(name) then return out, true end
            if type(name) == "string" and not out[name] then out[name] = GetBindingText(key, true) end
        end
    end
    return out, false
end

-- The game's controller bars hold their own slots: 3 pages of 4 bars of 8 buttons,
-- and the top bar's 4 face buttons (interact, jump...) take none, so a page is 28
-- slots (ActionBindingUtil.lua). The triggers held pick a bar, and Bindings.xml's
-- numbers pick the button: D-pad left, up, right, down, then face left, up, right,
-- down.
Keys.PAD_PAGES, Keys.PAD_PAGE_SLOTS, Keys.PAD_BAR, Keys.PAD_RESERVED = 3, 28, 8, 4
Keys.PAD_BUTTONS = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" }
Keys.PAD_HOLD = { [1] = { "PADLTRIGGER" }, [2] = { "PADRTRIGGER" }, [3] = { "PADLTRIGGER", "PADRTRIGGER" } }

-- A controller key drawn the way the controller in use draws it: the game's own
-- glyph for its label style (InputIconTexture.lua: letters on an Xbox pad, shapes on
-- a PlayStation one, so a PS5 shows its cross and L2), flat and as tall as the text.
-- Falls back to the game's words when it has no glyph. Only reads the game's tables.
function Keys.PadGlyph(key)
    local U, V, S = InputIconTextureSetUtility, InputDeviceIconVariant, InputIconTextureState
    if type(U) == "table" and type(U.GetActiveInputIconButtonTextures) == "function" and type(S) == "table" then
        local ok, set = pcall(U.GetActiveInputIconButtonTextures, key, type(V) == "table" and V.NoShadow or nil)
        local atlas = ok and type(set) == "table" and set[S.Normal]
        if type(atlas) == "string" and atlas ~= "" then return "|A:" .. atlas .. ":0:0|a" end
    end
    return GetBindingText(key, true)
end

-- What presses the slot at this offset in the controller's storage: "LT+A" (each part
-- as its glyph, Keys.PadGlyph), with the page in front past the first ("2: LT+A").
function Keys.PadKey(offset)
    local page = math.floor(offset / Keys.PAD_PAGE_SLOTS)
    local at = offset % Keys.PAD_PAGE_SLOTS
    if at >= Keys.PAD_RESERVED then at = at + Keys.PAD_RESERVED end
    local bar = math.floor(at / Keys.PAD_BAR)
    local index = at % Keys.PAD_BAR + 1
    local key = GetBindingKey("GAMEPADACTIONBUTTON" .. index) or Keys.PAD_BUTTONS[index]
    local parts = {}
    for _, hold in ipairs(Keys.PAD_HOLD[bar] or {}) do parts[#parts + 1] = Keys.PadGlyph(hold) end
    parts[#parts + 1] = Keys.PadGlyph(key)
    local text = table.concat(parts, "+")
    return page > 0 and ((page + 1) .. ": " .. text) or text
end

-- The controller's bars by name, lowest page first.
local function buildPadKeys()
    local out = {}
    if type(C_GamepadUI) ~= "table" then return out, false end
    local first = C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()
    if type(first) ~= "number" then return out, false end
    for offset = 0, Keys.PAD_PAGES * Keys.PAD_PAGE_SLOTS - 1 do
        local name = nameIn(first + offset)
        if name == false or not plain(name) then return out, true end
        if type(name) == "string" and not out[name] then out[name] = Keys.PadKey(offset) end
    end
    return out, false
end

-- The key that casts this spell or item name, as the game writes it, or nil.
function Keys.CastKey(name)
    if type(name) ~= "string" or not plain(name) then return nil end
    local map = castKeys
    if not map then
        local partial
        if DUI.Pad.On() then map, partial = buildPadKeys() else map, partial = buildCastKeys() end
        if not partial then castKeys = map end
    end
    return map[name]
end

-- The text follows the bindings. The flyout keys follow the bindings and whatever is
-- in each slot (a drag, a page change).
Keys.EVENTS = { "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BONUS_ACTIONBAR",
                "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR" }

-- Rebuild the flyout keys once on the next frame, however many events came. A bar
-- swap sends up to 120 ACTIONBAR_SLOT_CHANGED, and each one used to rebuild them all.
local flyoutsQueued = false
local function flyoutsSoon()
    flyoutsQueued = false
    DUI.AfterCombat(Keys.UpdateFlyouts, "keys:flyouts")
end
local function flyoutsTimer()
    DUI.SafeCall(flyoutsSoon)
    -- Whatever changed, the Cooldown Manager icons show the new keys.
    if ns.Cooldowns and ns.Cooldowns.RepaintKeys then DUI.SafeCall(ns.Cooldowns.RepaintKeys) end
end

function Keys.OnEvent(event)
    if event == "UPDATE_BINDINGS" or event == "PLAYER_ENTERING_WORLD" then Keys.UpdateText() end
    castKeys = nil
    if flyoutsQueued then return end
    flyoutsQueued = true
    C_Timer.After(0, flyoutsTimer)
end

-- Quick Keybind mode: our buttons show the game's binding highlight, a click binds
-- (the mixin's own handler, for mouse buttons) instead of casting, and it's all
-- undone when the mode closes.
Keys.quick = false
local strata = {}
function Keys.QuickMode(on)
    Keys.quick = on == true
    -- The game's extra action frame is wider than its art and sits over a bar
    -- placed under it, eating the mouse. Lift our bars above it while the mode
    -- is open.
    for key, holder in pairs(ns.Bars.holders) do
        if Keys.quick then
            strata[key] = strata[key] or holder:GetFrameStrata()
            holder:SetFrameStrata("HIGH")
        elseif strata[key] then
            holder:SetFrameStrata(strata[key])
            strata[key] = nil
        end
    end
    for _, btn in ipairs(buttons()) do
        if btn.DoModeChange then btn:DoModeChange(Keys.quick) end
        if Keys.quick then btn:SetAttribute("type", nil) else btn:SetAttribute("type", "action") end
    end
end

-- The Action Bars page's Bind keys button opens the game's Quick Keybind mode the
-- same way its Settings button does, with our options window out of the way. Its
-- Okay lands on the game's Settings, like the game's own: closing that panel from
-- our code would run its commits under our taint. Opened from our code, its OnShow
-- can't taint the game's buttons, since their SetShowGrid only writes when
-- issecure().
function Keys.OpenQuick()
    local q = _G.QuickKeybindFrame
    if InCombatLockdown() or type(q) ~= "table" or not q.Show then return false end
    local Panel = DUI.OptionsPanel
    if Panel and Panel.IsShown() then Panel.Toggle() end
    q:Show()
    return true
end

-- /kb does the same. In a fight it opens once the fight ends. Left alone when another
-- addon already owns /kb.
function Keys.Typed()
    if InCombatLockdown() then DUI.Print(DUI.L["Bind keys opens after combat."]) end
    DUI.AfterCombat(Keys.OpenQuick, "keys:open")
end
function Keys.SlashTaken(cmd)
    if type(hash_SlashCmdList) == "table" and hash_SlashCmdList[string.upper(cmd)] then return true end
    for key in pairs(SlashCmdList) do
        for i = 1, 9 do
            local s = _G["SLASH_" .. key .. i]
            if type(s) ~= "string" then break end
            if string.lower(s) == cmd then return true end
        end
    end
    return false
end
DUI.RegisterEvent("PLAYER_LOGIN", function()
    if not Keys.frame or SlashCmdList.DAYLIGHTUIKB or Keys.SlashTaken("/kb") then return end
    SLASH_DAYLIGHTUIKB1 = "/kb"
    SlashCmdList.DAYLIGHTUIKB = Keys.Typed
end)

-- Runs once at build.
function Keys.Wire()
    if Keys.frame then return end
    local f = CreateFrame("Frame")
    Keys.frame = f
    hookPresses()
    for _, e in ipairs(Keys.EVENTS) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, event) DUI.SafeCall(Keys.OnEvent, event) end)
    DUI.On("PadChanged", function() Keys.OnEvent("PadChanged") end)
    -- A different controller in use (a PS5 pad after an Xbox one) means new glyphs.
    -- The game's own glyph set follows the same events (InputDeviceIconSetManager).
    for _, e in ipairs({ "GAME_PAD_CONNECTED", "GAME_PAD_ACTIVE_CHANGED" }) do
        pcall(DUI.RegisterEvent, e, function() Keys.OnEvent("PadChanged") end)
    end
    polling()
    Keys.UpdateText()
    -- On its own, so an unreadable slot can't stop the rest of Wire.
    DUI.SafeCall(DUI.AfterCombat, Keys.UpdateFlyouts, "keys:flyouts")
    -- Directions once the bars are placed (next frame, when the game knows where
    -- they are), and after a move in unlock mode.
    local function directions()
        C_Timer.After(0, function() DUI.AfterCombat(Keys.UpdateDirections, "keys:directions") end)
    end
    DUI.On("ActionBarLaidOut", directions)
    DUI.On("UnlockChanged", function(unlocked) if not unlocked then directions() end end)
    directions()
    for _, btn in ipairs(buttons()) do
        btn:HookScript("OnClick", function(self, button)
            if Keys.quick and self.QuickKeybindButtonOnClick then self:QuickKeybindButtonOnClick(button) end
        end)
    end
    local q = _G.QuickKeybindFrame
    if type(q) == "table" and q.HookScript then
        q:HookScript("OnShow", function() DUI.AfterCombat(function() Keys.QuickMode(true) end, "keys:quick") end)
        q:HookScript("OnHide", function() DUI.AfterCombat(function() Keys.QuickMode(false) end, "keys:quick") end)
    end
end
