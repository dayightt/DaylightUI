-- Runs the game's own UI code (tests/blizzard/, fetched by tools/fetch_blizzard.py)
-- inside the fake game. Game code sees the fake game's globals first, then the
-- small FAKES below. Any other name reads as INERT, a stand-in that answers every
-- call with nil and every field with itself. Each such name is noted in
-- Blizz.inert, so a test can see what the game's code reached for that the fake
-- game doesn't model.
local Blizz = { DIR = "tests/blizzard/", inert = {}, FAKES = {} }

local INERT
INERT = setmetatable({}, {
    __index = function() return INERT end,
    __call = function() return nil end,
    __tostring = function() return "<inert>" end,
})
Blizz.INERT = INERT

local stub
function Blizz.Bind(s) stub = s end

function Blizz.Have(file)
    local f = io.open(Blizz.DIR .. file, "r")
    if f then f:close(); return true end
    return false
end

function Blizz.List(prefix, sub)
    local names = {}
    local f = io.open(Blizz.DIR .. (sub or "") .. "FILES.txt", "r")
    if f then
        for line in f:lines() do
            if line ~= "" and string.sub(line, 1, #prefix) == prefix then names[#names + 1] = line end
        end
        f:close()
    end
    local i = 0
    return function() i = i + 1; return names[i] end
end

-- Small fakes for names the game's button code needs to be real (numbers, mixin
-- builders), or that the old hand-made stub recorded for tests.
local F = Blizz.FAKES
F.CreateFromMixins = function(...) return Mixin({}, ...) end
F.NUM_ACTIONBAR_PAGES = 6
F.NUM_OVERRIDE_BUTTONS = 6
F.tInvert = function(t) local r = {}; for k, v in pairs(t) do r[v] = k end; return r end
F.issecure = function() return (stub.inSecure or 0) > 0 end
F.securecallfunction = function(fn, ...) return fn(...) end
F.assertsafe = function() end
F.RunNextFrame = function(fn) C_Timer.After(0, fn) end
F.IsModifiedClick = function() return false end
F.GetCVar = function() return "0" end
F.GetCVarBitfield = function() return false end
F.PickupAction = function(slot) stub.pickedAction = slot end
F.PlaceAction = function(slot) stub.placedAction = slot end
F.CallbackRegistryMixin = {
    SetUndefinedEventsAllowed = function() end,
    OnLoad = function() end,
    RegisterCallback = function() end,
    UnregisterCallback = function() end,
    TriggerEvent = function() end,
}
F.QuickKeybindButtonTemplateMixin = {
    QuickKeybindButtonOnLoad = function() end,
    QuickKeybindButtonOnEnter = function() end,
    QuickKeybindButtonOnLeave = function() end,
    QuickKeybindButtonOnShow = function() end,
    QuickKeybindButtonOnHide = function() end,
    QuickKeybindButtonSetTooltip = function() end,
    -- The client only binds the click while Quick Keybind mode is on.
    QuickKeybindButtonOnClick = function(self, button)
        if self.__quickMode then stub.quickClicks[#stub.quickClicks + 1] = { self, button } end
    end,
    DoModeChange = function(self, on) self.__quickMode = on end,
}
-- The popup half of the game's FlyoutButtonMixin (Blizzard_Flyout/Flyout.lua), line for
-- line; its arrow art is left out. The action button template mixes it in, and
-- the button's UpdateFlyout (on an attribute change, or the game's own UpdateAction)
-- is the only thing that hands it SpellFlyout: a secure click on a flyout slot
-- opens SpellFlyout only when HasPopup() says so (SpellFlyoutMixin:Toggle ends in
-- TogglePopup).
local noop = function() end
F.FlyoutButtonMixin = {
    OnLoad = noop, OnHide = noop, OnEnter = noop, OnLeave = noop, OnMouseDown = noop, OnMouseUp = noop,
    OnDragStart = noop, UpdateArrowShown = noop, UpdateArrowPosition = noop, UpdateArrowRotation = noop,
    OnPopupToggled = noop,
    SetPopup = function(self, popup)
        if popup == self.popup then return end
        self.popup = popup
        self:UpdateArrowShown()
    end,
    ClearPopup = function(self)
        if not self.popup then return end
        self:ClosePopup()
        self.popup = nil
        self:UpdateArrowShown()
    end,
    GetPopup = function(self) return self.popup end,
    HasPopup = function(self) return self.popup ~= nil end,
    GetPopupDirection = function(self) return self.popupDirection or "DOWN" end,
    SetPopupDirection = function(self, d)
        if self.popupDirection == d then return end
        self.popupDirection = d
        self:UpdateArrowPosition()
        self:UpdateArrowRotation()
    end,
    IsPopupOpen = function(self)
        local popup = self.popup
        return popup and popup:IsAttachedToButton(self)
    end,
    TogglePopup = function(self)
        if self:IsPopupOpen() then
            self.popup:DetatchFromButton()
        elseif self:HasPopup() then
            self.popup:AttachToButton(self)
        end
        self:OnPopupToggled()
    end,
    ClosePopup = function(self)
        if self:IsPopupOpen() then self:TogglePopup() end
    end,
}
-- The game's SpellFlyout as a popup: which button it is open on. Its other
-- methods (Hide on a drag, ...) do nothing.
F.SpellFlyout = setmetatable({
    AttachToButton = function(self, b) self.attached = b end,
    DetatchFromButton = function(self) self.attached = nil end,
    IsAttachedToButton = function(self, b) return self.attached == b end,
    Hide = function(self) self.attached = nil end,
}, { __index = function() return INERT end })

-- The client's namespaces (C_ActionBar, Enum, ...) as the game's code sees them:
-- what the fake game models, then a noted stand-in for the rest.
local spaces = setmetatable({}, { __mode = "k" })
local function space(name, t)
    local p = spaces[t]
    if not p then
        p = setmetatable({}, {
            __index = function(_, k)
                local v = t[k]
                if v ~= nil then return v end
                Blizz.inert[name .. "." .. tostring(k)] = true
                return INERT
            end,
            __newindex = t,
        })
        spaces[t] = p
    end
    return p
end

-- Game files write their globals (mixins, functions) into _G, like the client.
local env = setmetatable({}, {
    __index = function(_, k)
        local v = _G[k]
        if type(v) == "table" and (k == "Enum" or string.find(k, "^C_")) then return space(k, v) end
        if v ~= nil then return v end
        v = F[k]
        if v ~= nil then return v end
        Blizz.inert[k] = true
        return INERT
    end,
    __newindex = function(_, k, v) rawset(_G, k, v) end,
})

local function run(chunk, err)
    if not chunk then error(err, 3) end
    setfenv(chunk, env)
    chunk()
end

function Blizz.Load(file)
    if not Blizz.Have(file) then
        error("tests/blizzard/" .. file .. " is missing: run `py tools/fetch_blizzard.py` once on this PC", 2)
    end
    run(loadfile(Blizz.DIR .. file))
end

function Blizz.LoadString(src, name) run(loadstring(src, name)) end

-- The fake game's own watcher frames (stub.Reset makes some of them) get the real
-- mixin's methods they don't model yet, so the game's button code finds them.
-- Methods the stub already models stay as they are.
function Blizz.FillFrames()
    for _, p in ipairs({
        { "ActionBarButtonEventsFrame", "ActionBarButtonEventsFrameMixin" },
        { "ActionBarButtonUpdateFrame", "ActionBarButtonUpdateFrameMixin" },
        { "ActionBarButtonRangeCheckFrame", "ActionBarButtonRangeCheckFrameMixin" },
        { "ActionBarButtonUsableWatcherFrame", "ActionBarButtonUsableWatcherFrameMixin" },
        { "ActionBarActionEventsFrame", "ActionBarActionEventsFrameMixin" },
    }) do
        local f, mixin = _G[p[1]], rawget(_G, p[2])
        if f == nil then
            f = CreateFrame("Frame", p[1])
            f.frames = {}
        end
        if rawget(f, "frames") == nil then f.frames = {} end
        if type(mixin) == "table" then
            for k, v in pairs(mixin) do
                if rawget(f, k) == nil then f[k] = v end
            end
        end
    end
end

return Blizz
