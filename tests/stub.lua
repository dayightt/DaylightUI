-- A small fake of the client API that DaylightUI's non-UI files touch, so
-- they run under plain LuaJIT. Tests arrange client state through this table.

local stub = {}

-- ---------------------------------------------------------------------
-- Secret values: a wrapper that errors on any use, including comparisons
-- (== nil / ~= nil) and truthiness tests, which the client also treats as
-- errors. Plain Lua can't trap == nil / ~= nil against nil through a
-- metatable (they never invoke __eq), so this stub can't reproduce that
-- particular error; tests/test_secrets.lua scans the source for those
-- comparisons instead of exercising them at runtime.
-- ---------------------------------------------------------------------

local SecretMT = {}
local function secretError() error("attempt to use a secret value", 2) end
for _, m in ipairs({ "__index", "__newindex", "__concat", "__len", "__lt", "__le", "__add",
                     "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__call" }) do
    SecretMT[m] = secretError
end
SecretMT.__tostring = function() return "<secret>" end
-- Joining with .. is allowed in the client (since 12.0.0): it gives a secret string.
SecretMT.__concat = function(a, b)
    local function plain(v) return (type(v) == "table" and rawget(v, "__secret")) and rawget(v, "__value") or v end
    return stub.Secret(tostring(plain(a)) .. tostring(plain(b)))
end

local function isSecret(v) return type(v) == "table" and rawget(v, "__secret") == true end
_G.issecretvalue = isSecret
_G.debugprofilestop = function() return os.clock() * 1000 end

function stub.Secret(v) return setmetatable({ __secret = true, __value = v }, SecretMT) end
-- For asserts only: the value inside a secret (a plain value comes back as is).
-- Addon code can't do this in game, but a test checking what was drawn can.
function stub.Plain(v) if isSecret(v) then return rawget(v, "__value") end return v end
-- For asserts only: the text a FontString shows, secret or not.
function stub.Text(fs) return fs.__plainText end

-- ---------------------------------------------------------------------
-- Output and errors
-- ---------------------------------------------------------------------

stub.chat, stub.errors = {}, {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) stub.chat[#stub.chat + 1] = msg end }
_G.geterrorhandler = function() return function(err) stub.errors[#stub.errors + 1] = tostring(err) end end

function stub.ChatContains(text)
    for _, m in ipairs(stub.chat) do
        if string.find(m, text, 1, true) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------

local frames, named = {}, {}
local frameIndex = setmetatable({}, { __mode = "k" })
stub.frames = frames
-- Lookups kept up to date as widgets are made, re-parented and registered, so
-- nothing has to scan every widget. kids[parent] = { [child] = true } and
-- byEvent[event] = { list (made order, sorted when dirty), set }.
local kids, byEvent = {}, {}
local function adopt(w, p)
    local old = rawget(w, "__parent")
    if old ~= nil and kids[old] then kids[old][w] = nil end
    if p ~= nil then
        local s = kids[p]
        if not s then s = {}; kids[p] = s end
        s[w] = true
    end
end
local function listen(w, e)
    local b = byEvent[e]
    if not b then b = { list = {}, set = {} }; byEvent[e] = b end
    if not b.set[w] then b.set[w] = true; b.list[#b.list + 1] = w; b.dirty = true end
end
local Widget = {}
-- For local tools that add to the fake game (the mouse, the keyboard).
stub.Widget = Widget
-- One shared no-op for every unmodelled method. A new closure per call cost
-- a fifth of the heavy tests' run time.
local NOOP = function() end
-- Unmodelled methods are a no-op when the real client has a method of that name
-- (tests/widget_api.lua, from the game's API docs) and nil otherwise, as in game.
-- Before that list loads (stub.realMethods nil), every capitalized name is a no-op.
stub.unknownMethods = {}
-- Locked objects, which the client refuses to addon code with "bad self".
-- A forbidden object (__forbidden) is always locked. While auras are secret
-- (stub.AurasRestricted: combat, or a restriction such as a PvP match, even
-- between fights), an aura button the client made and everything made on it
-- (__inAura) lock once its initializeFrame has run (__auraLock), and so does a
-- texture handed to AddDispelTypeTexture (__handed). The game's CreateFrame in
-- Blizzard_AuraContainerFrameProviders.lua adds DenyTaintedAccessWhenAurasAreSecret
-- right after init. Only addon code is refused; tests and the game's code may look.
-- This runs on every method call, so the cheap per-object checks come first.
local function isLocked(t)
    if rawget(t, "__forbidden") then return true end
    local ab = rawget(t, "__inAura")
    if not rawget(t, "__handed") then
        if ab == nil or rawget(ab, "__auraLock") ~= true then return false end
    -- Handed over inside an aura button's initializeFrame: the game applies
    -- its access restrictions after init returns (AuraContainerCustomFrameProviderMixin:CreateFrame).
    elseif ab ~= nil and rawget(ab, "__auraLock") ~= true then
        return false
    end
    return stub.AurasRestricted()
end
-- Does a key start with a capital (a client method name)? Asked on every method
-- call, so the answer is cached per key. A pattern call here kept LuaJIT from
-- compiling the sweeps and doubled their time.
local CAPITAL = setmetatable({}, { __index = function(t, k)
    local b = type(k) == "string" and string.byte(k, 1)
    local v = b and b >= 65 and b <= 90 or false
    t[k] = v
    return v
end })
local function fromAddon(level)
    local info = debug.getinfo(level + 1, "S")
    local src = info and info.source or ""
    return string.sub(src, 1, 1) == "@" and not string.find(src, "^@%.?/?tests[/\\]")
end
stub.lockErrors, stub.lockSites = 0, {}
local function badSelf(k)
    return function()
        stub.lockErrors = stub.lockErrors + 1
        local level, info = 2, debug.getinfo(2, "Sl")
        while info and info.what == "C" do   -- through pcall to the caller
            level = level + 1
            info = debug.getinfo(level, "Sl")
        end
        local site = (info and (info.short_src .. ":" .. info.currentline) or "?") .. " " .. k
        stub.lockSites[site] = (stub.lockSites[site] or 0) + 1
        error("calling '" .. k .. "' on bad self (Attempt to access forbidden object from code tainted by an AddOn)", 2)
    end
end
-- A secret argument passed from addon code to a method the docs say refuses one
-- (stub.refusesSecrets, from tests/widget_api.lua) errors as in game. The caller
-- is only inspected when a secret is actually passed.
stub.secretArgErrors = 0
local guarded = {}
local function guardSecrets(k, m)
    local byM = guarded[k]
    if not byM then byM = setmetatable({}, { __mode = "k" }); guarded[k] = byM end
    local g = byM[m]
    if not g then
        g = function(self, ...)
            for i = 1, select("#", ...) do
                if isSecret((select(i, ...))) and fromAddon(1) then
                    stub.secretArgErrors = stub.secretArgErrors + 1
                    error(string.format("bad argument #%d to '%s' (Secret values are only allowed during untainted execution for this argument.)", i, k), 2)
                end
            end
            return m(self, ...)
        end
        byM[m] = g
    end
    return g
end
local function method(k, m)
    local refuses = stub.refusesSecrets
    if refuses and refuses[k] then return guardSecrets(k, m) end
    return m
end
local WidgetMT = {
    __index = function(t, k)
        local cap = CAPITAL[k]
        if cap and k ~= "IsForbidden" and isLocked(t) and fromAddon(2) then
            return badSelf(k)
        end
        local m = Widget[k]
        if m ~= nil then return method(k, m) end
        if cap then
            local real = stub.realMethods
            if real == nil or real[k] then return method(k, NOOP) end
            stub.unknownMethods[k] = true
        end
    end,
}

local function new(objType, name, parent, template)
    local w = setmetatable({
        __type = objType, __name = name, __parent = parent, __template = template,
        __shown = true, __events = {}, __unitEvents = {}, __scripts = {}, __attrs = {},
        __points = {}, __scale = 1, __level = parent and ((parent.__level or 0) + 1) or 0,
    }, WidgetMT)
    if type(parent) == "table" then w.__inAura = rawget(parent, "__inAura") end
    adopt(w, parent)
    frames[#frames + 1] = w
    frameIndex[w] = #frames
    if name then _G[name] = w; named[#named + 1] = name end
    return w
end
stub.NewWidget = new

-- Taint, as /dui taint reports it. stub.Mark(t, key, addon) marks a field (a
-- global when t is nil) as written by that addon. Anything else reads as the
-- game's own.
stub.marks = setmetatable({}, { __mode = "k" })
function stub.Mark(t, key, addon)
    t = t or _G
    stub.marks[t] = stub.marks[t] or {}
    stub.marks[t][key] = addon
end
_G.issecurevariable = function(t, k)
    if k == nil then t, k = _G, t end
    local by = stub.marks[t] and stub.marks[t][k]
    if by then return false, by end
    return true, nil
end
_G.EnumerateFrames = function(prev)
    local i = prev and frameIndex[prev] or 0
    return frames[i + 1]
end

-- A parent's children in creation order. Scanning all ~30000 widgets per call
-- used to be a big part of the sweeps' time.
local function byAge(a, b) return frameIndex[a] < frameIndex[b] end
function stub.Children(parent, keep)
    local out = {}
    for w in pairs(kids[parent] or {}) do
        local i = frameIndex[w]
        if i and frames[i] == w and w.__parent == parent and (keep == nil or keep(w)) then out[#out + 1] = w end
    end
    table.sort(out, byAge)
    return out
end
-- A Line is a region too (SimpleLine: frame:GetRegions returns the lines made on it).
local REGIONS = { Texture = true, FontString = true, MaskTexture = true, Line = true }
local function isRegion(w) return REGIONS[w.__type] == true end
local function isFrame(w) return not REGIONS[w.__type] end
function Widget:GetNumRegions() return select("#", Widget.GetRegions(self)) end
function Widget:GetRegions() return unpack(stub.Children(self, isRegion)) end
function Widget:GetChildren() return unpack(stub.Children(self, isFrame)) end
function Widget:GetNumChildren() return select("#", self:GetChildren()) end

function Widget:GetObjectType() return self.__type end
function Widget:IsObjectType(t) return self.__type == t or (t == "Button" and self.__type == "CheckButton") end
function Widget:GetName() return self.__name end
function Widget:GetParent() return self.__parent end
-- Secure mode (stub.secure, used by the action bar tests). A protected frame
-- refuses changes in combat the way the client blocks them, unless secure code
-- makes them (a state driver or a snippet, stub.inSecure) or the handlers of the
-- combat-start event do (PLAYER_REGEN_DISABLED fires just before the lockdown,
-- stub.enteringCombat).
-- As in the client, a frame holding a protected frame anywhere under it is
-- protected too. Seen in game: a secure button inside the bag blocked the bag's
-- own close in a fight, and the minimap's SetParent was blocked the same way.
local function protectedTree(w)
    if rawget(w, "__protected") then return true end
    local s = kids[w]
    if s then for c in pairs(s) do if protectedTree(c) then return true end end end
    return false
end
stub.ProtectedTree = protectedTree
local function guard(self, what)
    if stub.secure and stub.combat and not stub.enteringCombat and (stub.inSecure or 0) == 0 and protectedTree(self) then
        error("ADDON_ACTION_BLOCKED: " .. what .. " on " .. tostring(self.__name or self.__type), 3)
    end
end
function Widget:SetParent(p)
    guard(self, "SetParent")
    adopt(self, p)
    self.__parent = p
    if type(p) == "table" and rawget(p, "__inAura") then self.__inAura = p.__inAura end
end
-- Like the client, OnShow and OnHide run when a frame's visibility changes,
-- whether from its own Show/Hide while its parents are shown or from a parent
-- showing or hiding (every shown frame under it, all the way down).
local function parentsShown(self)
    local p = rawget(self, "__parent")
    while p do
        if not rawget(p, "__shown") then return false end
        p = rawget(p, "__parent")
    end
    return true
end
local function cascade(self, script)
    local s = kids[self]
    if not s then return end
    for w in pairs(s) do
        if rawget(w, "__shown") then
            local scripts = rawget(w, "__scripts")
            local fn = scripts and scripts[script]
            if fn then fn(w) end
            cascade(w, script)
        end
    end
end
function Widget:Show()
    guard(self, "Show")
    -- As in the client, a tooltip's Show resets its alpha to 1 whether it was
    -- already shown or not. In game this undid a mute and a fade-in set from OnShow.
    if self.__type == "GameTooltip" then self.__alpha = 1 end
    local was = self.__shown
    self.__shown = true
    if not was and parentsShown(self) then
        if self.__scripts.OnShow then self.__scripts.OnShow(self) end
        cascade(self, "OnShow")
    end
end
function Widget:Hide()
    guard(self, "Hide")
    local was = self.__shown
    self.__shown = false
    if was and parentsShown(self) then
        if self.__scripts.OnHide then self.__scripts.OnHide(self) end
        cascade(self, "OnHide")
    end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.__shown end
-- Visible: shown, and every parent shown (UIParent always is).
function Widget:IsVisible()
    local f = self
    while f do
        if not f.__shown then return false end
        f = f.__parent
    end
    return true
end
function Widget:IsProtected() return protectedTree(self) end
function Widget:IsForbidden() return self.__forbidden == true end
-- A frame inside a client aura button has secret aspects (its shown state is
-- secret), so the client refuses a show or hide handler on it, even while the
-- button is being created. The game's error: "Frame:SetScript(): Cannot assign
-- script handler for 'onshow' (blocked by secret aspects)".
local SECRET_ASPECT_SCRIPTS = { OnShow = "onshow", OnHide = "onhide" }
local function refuseSecretAspect(self, h)
    if rawget(self, "__inAura") and SECRET_ASPECT_SCRIPTS[h] and rawget(self, "__type") ~= "AnimationGroup" then
        error(string.format("Frame:SetScript(): Cannot assign script handler for '%s' (blocked by secret aspects)",
            SECRET_ASPECT_SCRIPTS[h]), 3)
    end
end
function Widget:SetScript(h, fn) refuseSecretAspect(self, h); self.__scripts[h] = fn end
function Widget:GetScript(h) return self.__scripts[h] end
function Widget:HookScript(h, fn)
    -- The game: "Usage: local success = self:HookScript(scriptTypeName, script [, bindingType])"
    if type(fn) ~= "function" then
        error("bad argument #3 to '?' (Usage: local success = self:HookScript(scriptTypeName, script [, bindingType]))", 2)
    end
    local prev = self.__scripts[h]
    local both = function(...) if prev then prev(...) end fn(...) end
    -- Kept on the frame. A weak table here would keep every world alive, since
    -- LuaJIT's weak keys aren't ephemerons and fn reaches the frame.
    local parts = rawget(self, "__hookParts") or {}
    rawset(self, "__hookParts", parts)
    parts[both] = { prev, fn }
    self.__scripts[h] = both
end
function Widget:RegisterEvent(e) self.__events[e] = true; listen(self, e) end
function Widget:RegisterUnitEvent(e, ...)
    if stub.unknownEvents[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
    self.__events[e] = true
    listen(self, e)
    self.__unitEvents[e] = { ... }
end
function Widget:UnregisterEvent(e) self.__events[e] = nil; self.__unitEvents[e] = nil end
function Widget:UnregisterAllEvents() self.__events = {}; self.__unitEvents = {} end
function Widget:IsEventRegistered(e) return self.__events[e] == true end
function Widget:SetIgnoreParentAlpha(on) self.__ignoreParentAlpha = on and true or false end
function Widget:IsIgnoringParentAlpha() return self.__ignoreParentAlpha == true end
function Widget:SetSize(w, h) guard(self, "SetSize"); self.__w, self.__h = w, h end
function Widget:SetWidth(w) guard(self, "SetWidth"); self.__w = w end
function Widget:SetHeight(h) guard(self, "SetHeight"); self.__h = h end
function Widget:GetWidth() return self.__w or 0 end
function Widget:GetHeight() return self.__h or 0 end
-- A resizable frame's limits as set. The client returns 0s before any are set.
function Widget:SetResizeBounds(a, b, c, d) self.__bounds = { a, b, c, d } end
function Widget:GetResizeBounds()
    local r = self.__bounds or {}
    return r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0
end
function Widget:GetSize() return self.__w or 0, self.__h or 0 end
function Widget:ClearAllPoints() guard(self, "ClearAllPoints"); self.__points = {} end
-- The client refuses to anchor a frame to an aura container that has aura
-- groups, unless the frame opts out of untrusted layout scripts (or is such
-- a container itself, already carrying the same aspect).
local function checkAnchor(self, rel)
    if type(rel) == "table" and rawget(rel, "__untrusted") and not rawget(self, "__untrusted")
        and not (self.__template and string.find(self.__template, "DisableUntrustedLayoutScriptsTemplate", 1, true)) then
        error("Frame:SetPoint(): Anchoring disallowed as dependent object would inherit forbidden aspects: UntrustedLayoutScriptExecution")
    end
    -- A protected frame can't hang off a region (a text or texture), even
    -- through frames in between: "Cannot anchor protected frames to regions".
    -- Seen in game with the bank's buy button laid over a button anchored to a text.
    if rawget(self, "__protected") then
        local seen, walk = {}, nil
        walk = function(r)
            if type(r) ~= "table" or seen[r] then return end
            seen[r] = true
            if isRegion(r) then
                error("Action[SetPoint] failed because[Cannot anchor protected frames to regions]: attempted from: "
                    .. tostring(self.__name or self.__type), 4)
            end
            for _, pt in ipairs(rawget(r, "__points") or {}) do
                local to = pt[2]
                if type(to) == "table" then walk(to) end
            end
        end
        walk(rel)
    end
end
function Widget:SetPoint(...)
    guard(self, "SetPoint")
    checkAnchor(self, select(2, ...))
    -- As in game: setting a point the frame already has replaces it in place.
    local point = ...
    for i, p in ipairs(self.__points) do
        if p[1] == point then self.__points[i] = { ... }; return end
    end
    self.__points[#self.__points + 1] = { ... }
end
function Widget:SetAllPoints(rel)
    guard(self, "SetAllPoints")
    checkAnchor(self, rel)
    self.__points = { { "ALL", rel or self.__parent } }
end
function Widget:GetNumPoints() return #self.__points end
-- GetPoint is "SecretWhenAnchoringSecret" in the API docs. Once a text shows a
-- secret value its anchoring is secret and the offsets come back secret. This
-- caused a player's error: arithmetic on a secret number when nudging health text.
function Widget:GetPoint(i)
    local p = self.__points[i or 1]
    if not p then return end
    if self.__secretAnchoring then
        return p[1], p[2], p[3], stub.Secret(p[4] or 0), stub.Secret(p[5] or 0)
    end
    return unpack(p, 1, 5)
end
function Widget:GetCenter() if self.__center then return self.__center[1], self.__center[2] end end
function Widget:SetScale(s) guard(self, "SetScale"); self.__scale = s end
function Widget:GetScale() return self.__scale end
-- A frame set to ignore its parent's scale has only its own, as in the client.
function Widget:SetIgnoreParentScale(v) self.__ignoreScale = v and true or false end
function Widget:IsIgnoringParentScale() return self.__ignoreScale == true end
function Widget:GetEffectiveScale()
    if rawget(self, "__ignoreScale") then return self.__scale end
    local p = self.__parent
    return self.__scale * (p and p:GetEffectiveScale() or 1)
end
function Widget:SetID(id) self.__id = id end
function Widget:GetID() return self.__id or 0 end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:SetFrameStrata(s) self.__strata = s end
-- A frame without its own strata takes its parent's, like the client.
function Widget:GetFrameStrata()
    local strata = rawget(self, "__strata")
    if strata then return strata end
    local p = rawget(self, "__parent")
    if p and p.GetFrameStrata then return p:GetFrameStrata() end
    return nil
end
function Widget:GetFrameLevel() return self.__level end
-- In secure mode an attribute change runs what the client would run: the frame's
-- _onstate-<name> snippet for a "state-<name>" attribute, and its OnAttributeChanged.
function Widget:SetAttribute(k, v)
    guard(self, "SetAttribute")
    self.__attrs[k] = v
    -- The game runs OnAttributeChanged on every SetAttribute; the state
    -- snippets only run in the secure world (stub.secure).
    if stub.secure then
        local state = type(k) == "string" and string.match(k, "^state%-(.+)$")
        local code = state and self.__attrs["_onstate-" .. state]
        if type(code) == "string" then stub.RunSnippet(self, code, { stateid = state, newstate = v }) end
    end
    local fn = self.__scripts.OnAttributeChanged
    if fn then fn(self, k, v) end
end
-- Same, without OnAttributeChanged or a state snippet. The frame's own handler
-- never runs, so a game button's Update doesn't run under addon taint.
function Widget:SetAttributeNoHandler(k, v)
    guard(self, "SetAttributeNoHandler")
    self.__attrs[k] = v
end
-- With three arguments (prefix, name, suffix) this looks the attribute up the way
-- the secure templates read a click's "type" or "spell" (SecureButton_GetModifiedAttribute):
-- the exact name, then "*" for the modifiers, then "*" for the button, then both,
-- then the bare name.
function Widget:GetAttribute(k, name, suffix)
    if name == nil then return self.__attrs[k] end
    local a = self.__attrs
    local v = a[k .. name .. suffix]
    if v == nil then v = a["*" .. name .. suffix] end
    if v == nil then v = a[k .. name .. "*"] end
    if v == nil then v = a["*" .. name .. "*"] end
    if v == nil then v = a[name] end
    return v
end
function Widget:StartMoving() self.__moving = true end
function Widget:SetClampedToScreen(v) self.__clamped = v and true or false end
function Widget:IsClampedToScreen() return self.__clamped == true end
function Widget:StopMovingOrSizing() self.__moving = false end
function Widget:CreateTexture(name, layer, _, sublevel)
    local t = new("Texture", name, self)
    t.__layer, t.__sublevel = layer, sublevel
    return t
end
function Widget:SetDrawLayer(layer, sublevel) self.__layer, self.__sublevel = layer, sublevel end
function Widget:GetDrawLayer() return self.__layer or "ARTWORK", self.__sublevel or 0 end
function Widget:CreateFontString(name, layer)
    local t = new("FontString", name, self)
    t.__layer = layer
    return t
end
-- Line (SimpleLineAPIDocumentation): its two ends, each a point on a region.
function Widget:CreateLine(name, layer, _, sublevel)
    local t = new("Line", name, self)
    t.__layer, t.__sublevel = layer, sublevel
    return t
end
function Widget:SetStartPoint(point, rel, x, y) self.__start = { point, rel, x or 0, y or 0 } end
function Widget:SetEndPoint(point, rel, x, y) self.__end = { point, rel, x or 0, y or 0 } end
function Widget:GetStartPoint() local p = self.__start or {} return p[1], p[2], p[3], p[4] end
function Widget:GetEndPoint() local p = self.__end or {} return p[1], p[2], p[3], p[4] end
function Widget:SetThickness(n) self.__thickness = n end
function Widget:GetThickness() return self.__thickness or 1 end
-- Texture
-- One picture at a time: an atlas replaces a color texture and the reverse.
function Widget:SetAtlas(a) self.__atlas = a; self.__color = nil end
function Widget:SetTexCoord(...) self.__texCoord = { ... } end
function Widget:GetTexCoord() return unpack(self.__texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
-- Takes a secret cell, as in game; a missing one (plain or secret) errors.
function Widget:SetSpriteSheetCell(cell, rows, cols)
    local v = isSecret(cell) and rawget(cell, "__value") or cell
    if type(v) ~= "number" then error("SetSpriteSheetCell: bad cell", 2) end
    self.__cell, self.__sheet = cell, { rows, cols }
end
function Widget:SetBlendMode(m) self.__blend = m end
function Widget:GetBlendMode() return self.__blend or "BLEND" end
function Widget:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a }; self.__atlas = nil end
-- Like the client, a plain vertex color sets every corner, so a gradient set
-- before it is gone.
-- A texture has one alpha. SetVertexColor's 4th value and SetAlpha write the
-- same number, so the later call wins: a light "switched off" with a clear vertex
-- color and then SetAlpha(1) is fully on (this made nameplate cast bars white in
-- game). Tests opt in with stub.AlphaRule since older tests read SetAlpha's own value.
function Widget:SetVertexColor(r, g, b, a)
    self.__vertex = { r, g, b, a }; self.__gradient = nil
    self.__vertexAlpha = stub.AlphaRule and rawget(self, "__type") == "Texture" and a or nil
end
function Widget:GetVertexColor() local v = self.__vertex or {}; return v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1 end
function Widget:SetRotation(r) self.__rotation = r end
function Widget:SetDesaturated(v) self.__desaturated = v and true or false end
function Widget:SetDesaturation(v) self.__desaturation = v; self.__desaturated = v ~= 0 end
function Widget:GetDesaturation() return self.__desaturation or (self.__desaturated and 1 or 0) end
function Widget:IsDesaturated() return self.__desaturated == true end
function Widget:SetGradient(o, a, b) self.__gradient = { o, a, b } end
function Widget:SetVertexColorFromBoolean(v, t, f) self.__vertexFromBoolean = { v, t, f } end
-- FontString
function Widget:SetFont(path, size, flags) self.__font = { path, size, flags } end
function Widget:GetFont() local f = self.__font; if f then return f[1], f[2], f[3] end end
-- Like the client, an edit box's text change runs its OnTextChanged.
function Widget:SetText(t)
    -- The client refuses text on a FontString with no font yet. Tests opt in with
    -- stub.FontRule because not every fake text sets one.
    if stub.FontRule and rawget(self, "__type") == "FontString" and not self.__font and t ~= nil then
        error("FontString:SetText(): Font not set", 2)
    end
    self.__text = t
    self.__plainText = stub.Plain(t)
    self.__secretAnchoring = isSecret(t) or nil
    local fn = self.__scripts and self.__scripts.OnTextChanged
    if fn then fn(self, false) end
end
function Widget:SetAlpha(a) self.__alpha = a; self.__vertexAlpha = nil; self.__secretAlpha = nil end
-- Like the client, the alpha it picks really lands (true -> t, false -> f).
function Widget:SetAlphaFromBoolean(v, t, f)
    self.__alphaFromBoolean = { v, t, f }
    if stub.Plain(v) then self:SetAlpha(t or 1) else self:SetAlpha(f or 0) end
    self.__secretAlpha = isSecret(v) or nil
end
function Widget:SetTooltipAnchorPoint(a, x, y) self.__tooltipAnchor = a end
-- The client keeps a list; __dispel is the first, __dispels all of them.
function Widget:AddDispelTypeTexture(tex, opts)
    if type(tex) == "table" then tex.__handed = true end
    self.__dispels = self.__dispels or {}
    self.__dispels[#self.__dispels + 1] = { tex = tex, opts = opts }
    self.__dispel = self.__dispel or self.__dispels[1]
end
function Widget:SetHitRectInsets(l, r, t, b) self.__hitRect = { l, r, t, b } end
function Widget:RegisterForClicks(...) self.__clicks = { ... } end
function Widget:RegisterForDrag(...) self.__drag = { ... } end
function Widget:SetUnit(u) self.__modelUnit = u end
function Widget:SetCamDistanceScale(s) self.__camScale = s end
-- Like the client, once a frame's alpha came from a secret (SetAlphaFromBoolean
-- with a secret flag), its GetAlpha and that of every region under it read
-- secret. Seen in game with a ready check icon on a range-faded party tile.
function Widget:GetAlpha()
    local va = self.__vertexAlpha      -- the alpha of the vertex color set last is the texture's alpha
    local a = va
    if a == nil then a = self.__alpha or 1 end
    local f = self
    while f do
        if rawget(f, "__secretAlpha") then return stub.Secret(a) end
        f = rawget(f, "__parent")
    end
    return a
end
-- Its own alpha times every parent's.
function Widget:GetEffectiveAlpha()
    local a, f = 1, self
    while f do a = a * (f.__alpha or 1); f = f.__parent end
    return a
end
function Widget:SetVertexOffset(i, x, y)
    self.__vertexOffsets = self.__vertexOffsets or {}
    self.__vertexOffsets[i] = { x, y }
end
-- Animation groups record whether they're playing and whether one holds an
-- Alpha animation (__alpha). The client can leave a frame at an alpha
-- animation's start value, so a test can check none runs where a tween owns it.
function Widget:CreateAnimationGroup()
    local g = new("AnimationGroup", nil, self)
    function g:CreateAnimation(kind)
        if kind == "Alpha" then g.__alpha = true end
        return new("Animation", nil, self)
    end
    -- OnPlay as it starts, OnStop when a playing group is stopped, as the
    -- client's AnimationGroup scripts. A looping group plays until stopped.
    function g:Play()
        self.__playing = true
        local fn = self.__scripts.OnPlay
        if fn then fn(self) end
    end
    function g:Stop()
        local was = self.__playing
        self.__playing = false
        local fn = self.__scripts.OnStop
        if was and fn then fn(self, true) end
    end
    function g:IsPlaying() return self.__playing == true end
    function g:SetLooping(kind) self.__looping = kind end
    return g
end
-- As the client's Button:Click: PreClick, OnClick, PostClick, in order. A test's
-- click counts as the player's, so it is a hardware event while its scripts run.
function Widget:Click(button)
    button = button or "LeftButton"
    stub.hardware = (stub.hardware or 0) + 1
    for _, name in ipairs({ "PreClick", "OnClick", "PostClick" }) do
        local fn = self.__scripts[name]
        if fn then
            local ok, err = pcall(fn, self, button, false)
            if not ok then stub.hardware = stub.hardware - 1; error(err, 0) end
        end
    end
    stub.hardware = stub.hardware - 1
end

-- Runs fn inside a player key press or click (a slash command typed, a key
-- binding), the hardware event some calls need.
function stub.Key(fn, ...)
    stub.hardware = (stub.hardware or 0) + 1
    local ok, err = pcall(fn, ...)
    stub.hardware = stub.hardware - 1
    if not ok then error(err, 0) end
end

-- A call the client allows addon code only during a hardware event (a click or
-- key). Anywhere else (OnUpdate, an event, a timer) it's refused with
-- ADDON_ACTION_BLOCKED "UNKNOWN()" and doesn't run. Seen in game with
-- C_TradeSkillUI.OpenTradeSkill called from a timer. Returns true when the call may run.
function stub.HardwareOnly(what)
    if (stub.hardware or 0) > 0 or (stub.inSecure or 0) > 0 then return true end
    stub.errors[#stub.errors + 1] = "ADDON_ACTION_BLOCKED: " .. what .. " (no hardware event)"
    return false
end
-- Buttons are enabled unless disabled, and run OnEnable/OnDisable on a change.
function Widget:IsEnabled() return self.__disabled ~= true end
function Widget:SetEnabled(on)
    local was = self:IsEnabled()
    self.__disabled = not on
    local fn = was ~= (on and true or false) and self.__scripts and self.__scripts[on and "OnEnable" or "OnDisable"]
    if fn then fn(self) end
end
function Widget:Enable() self:SetEnabled(true) end
function Widget:Disable() self:SetEnabled(false) end
-- "NORMAL" or "PUSHED", as the game's buttons report it.
function Widget:SetButtonState(s) self.__state = s end
function Widget:GetButtonState() return self.__state or "NORMAL" end
function Widget:GetText() return self.__text end
-- An edit box takes one line unless made multi-line. Enter in a one-line box
-- adds no line break and only fires OnEnterPressed, as in game.
function Widget:SetMultiLine(on) self.__multiLine = on and true or false end
function Widget:IsMultiLine() return self.__multiLine == true end
function Widget:SetJustifyH(j) self.__justifyH = j end
function Widget:GetJustifyH() return self.__justifyH or "CENTER" end
function Widget:SetFormattedText(fmt, ...)
    local args = { ... }
    for i = 1, select("#", ...) do args[i] = stub.Plain(args[i]) end
    self.__plainText = string.format(fmt, unpack(args, 1, select("#", ...)))
    for i = 1, select("#", ...) do
        if isSecret((select(i, ...))) then
            self.__text = { secretFormat = fmt }; self.__secretAnchoring = true; return
        end
    end
    self.__text = string.format(fmt, ...)
    self.__secretAnchoring = nil
end
-- A SimpleHTML takes a tag first ("P", "H1"...) and keeps a color per tag.
function Widget:SetTextColor(r, g, b, a, x)
    if type(r) == "string" then
        self.__tagColor = self.__tagColor or {}
        self.__tagColor[r] = { g, b, a, x }
        return
    end
    self.__textColor = { r, g, b, a }
end
-- A check button keeps its checked state (SetChecked fires no script).
function Widget:SetChecked(on) self.__checked = on == true end
function Widget:GetChecked() return self.__checked == true end
-- A text showing a secret reads its color back as secret too. Seen in game on a
-- spell tooltip during the global cooldown.
function Widget:GetTextColor()
    local c = self.__textColor or { 1, 1, 1, 1 }
    local r, g, b, a = c[1], c[2], c[3], c[4] or 1
    if isSecret(self.__text) then return stub.Secret(r), stub.Secret(g), stub.Secret(b), stub.Secret(a) end
    return r, g, b, a
end
function Widget:SetShadowOffset(x, y) self.__shadowOffset = { x, y } end
function Widget:SetShadowColor(r, g, b, a) self.__shadowColor = { r, g, b, a } end
-- StatusBar
function Widget:SetStatusBarTexture(p) self.__barTexture = p end
function Widget:GetStatusBarTexture()
    self.__fill = self.__fill or new("Texture", nil, self)
    return self.__fill
end
function Widget:SetMinMaxValues(lo, hi) self.__min, self.__max = lo, hi end
function Widget:SetValue(v, interp) self.__value = v; self.__interp = interp end
function Widget:GetMinMaxValues() return self.__min, self.__max end
function Widget:GetValue() return self.__value end
function Widget:SetStatusBarColor(r, g, b, a) self.__barColor = { r, g, b, a } end
-- Buttons take the mouse from the start, other frames once asked. On a protected
-- frame this is a protected change.
function Widget:EnableMouse(on) guard(self, "EnableMouse"); self.__mouse = on and true or false end
-- Whether a key a frame gets also goes on to the game is restricted in a fight
-- (HasRestrictions in the frame API docs), so addon code can't change it in combat.
function Widget:EnableKeyboard(on) guard(self, "EnableKeyboard"); self.__keyboard = on and true or false end
function Widget:IsKeyboardEnabled() return self.__keyboard == true end
function Widget:SetPropagateKeyboardInput(on)
    if stub.combat and (stub.inSecure or 0) == 0 then
        error("ADDON_ACTION_BLOCKED: SetPropagateKeyboardInput in combat", 2)
    end
    self.__propagate = on and true or false
end
function Widget:GetPropagateKeyboardInput() return self.__propagate == true end
function Widget:IsMouseEnabled()
    if self.__mouse ~= nil then return self.__mouse end
    return self.__type == "Button" or self.__type == "CheckButton"
end
function Widget:EnableMouseWheel(on) self.__wheel = on and true or false end
function Widget:IsMouseWheelEnabled() return self.__wheel == true end
function Widget:SetHyperlinksEnabled(on) self.__links = on and true or false end
function Widget:GetHyperlinksEnabled() return self.__links == true end
-- ScrollFrame
function Widget:SetVerticalScroll(v) self.__vScroll = v end
function Widget:GetVerticalScroll() return self.__vScroll or 0 end
function Widget:SetScrollChild(c) self.__scrollChild = c; adopt(c, self); c.__parent = self end
function Widget:GetScrollChild() return self.__scrollChild end
function Widget:SetTimerDuration(d, interp, dir) self.__timer = { d, interp, dir } end
function Widget:SetReverseFill(v) self.__reverse = v end
function Widget:GetReverseFill() return self.__reverse end
-- A Cooldown's sweep: whether it's drawn and which way. The game defaults to
-- drawn, not reversed.
function Widget:SetDrawSwipe(v) self.__drawSwipe = v == true end
function Widget:GetDrawSwipe() if self.__drawSwipe == nil then return true end return self.__drawSwipe end
function Widget:SetReverse(v) self.__cdReverse = v == true end
function Widget:GetReverse() return self.__cdReverse == true end
function Widget:SetClipsChildren(v) self.__clips = v == true end
function Widget:DoesClipChildren() return self.__clips == true end
function Widget:SetOrientation(v) self.__orientation = v end
function Widget:GetOrientation() return self.__orientation or "HORIZONTAL" end
-- Masks
function Widget:CreateMaskTexture() return new("MaskTexture", nil, self) end
function Widget:AddMaskTexture(m)
    self.__masks = self.__masks or {}
    if #self.__masks >= 3 then error("Texture already has the maximum number of mask textures (3)") end
    self.__masks[#self.__masks + 1] = m
end
function Widget:RemoveMaskTexture(m)
    for i, x in ipairs(self.__masks or {}) do
        if x == m then table.remove(self.__masks, i) return end
    end
end
function Widget:SetTexture(p, wrapH, wrapV) self.__texture = p; self.__wrap = wrapH; self.__atlas = nil; return true end
function Widget:GetTexture() return self.__texture end
-- The client knows a file by its id, so a texture set by path reads back the id
-- when the file has one. Tests list them in stub.fileIDs (lowercase, backslashes,
-- no extension).
stub.fileIDs = {}
function Widget:GetTextureFileID()
    local t = self.__texture
    if type(t) == "number" then return t end
    if type(t) ~= "string" then return nil end
    return stub.fileIDs[(t:lower():gsub("/", "\\"):gsub("%.%w+$", ""))]
end
-- The client refuses secret times in SetCooldown from tainted code (ActionButton.lua),
-- and any code on an addon frame is tainted. Frames the game owns (__game) aren't checked.
function Widget:SetCooldown(start, duration, modRate)
    if isSecret(start) or isSecret(duration) or isSecret(modRate) then
        local owner = self.__parent
        if not (owner and owner.__game) then
            stub.secretCooldownErrors = (stub.secretCooldownErrors or 0) + 1
            error("bad argument #1 to 'SetCooldown' (Usage: self:SetCooldown(start, duration [, modRate]). "
                .. "Secret values are only allowed during untainted execution for this argument.)", 2)
        end
    end
    self.__cooldown = { start, duration, modRate }
end
-- A Cooldown fed a duration object, which the client then runs by itself.
function Widget:SetCooldownFromDurationObject(d, clearIfZero) self.__duration = d end
function Widget:GetDebugName() return self.__name or ("<" .. tostring(self.__type) .. ">") end
-- Measuring text errors on a secret, as in the client.
-- stub.measure(fs) returns width, height from real font metrics when a tool sets
-- it (tools/snap.lua for screenshots). Tests use 7 px per letter and no height.
function Widget:GetStringWidth()
    if isSecret(self.__text) then error("attempt to measure secret text") end
    if type(self.__text) ~= "string" then return 0 end
    if stub.measure then return (stub.measure(self)) end
    -- Color codes take no room.
    local shown = self.__text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #shown * 7
end
function Widget:GetUnboundedStringWidth()
    if stub.measure and type(self.__text) == "string" then return (stub.measure(self, true)) end
end
function Widget:GetStringHeight()
    if stub.measure and type(self.__text) == "string" then return select(2, stub.measure(self)) end
end

-- The client's custom aura container. It records groups and, like the game
-- (Blizzard_CustomAuraContainer.lua AddAuraGroup, CreateFrameBatch), builds a
-- batch of AURA_BATCH buttons the moment a group is added and runs initializeFrame
-- on each. The group's first button is g.button. The batch size matches
-- CustomAuraContainerConstants.FrameCreationBatchSize as counted in game.
stub.AURA_BATCH = 10
local newAuraButton
local function newAuraContainer(name, parent, template)
    if stub.noAuraContainer then error("Unknown frame type 'AuraContainer'") end
    local c = new("AuraContainer", name, parent, template)
    c.__groups, c.__groupOrder = {}, {}
    function c:SetUnit(u) self.__unit = u end
    function c:UpdateAllAuras() self.__refreshes = (self.__refreshes or 0) + 1 end
    function c:AddAuraGroup(key, filter, opts)
        if stub.refuseAuraFilters and stub.refuseAuraFilters[filter] then error("Invalid aura filter: " .. filter) end
        assert(not self.__groups[key], "duplicate group " .. key)
        local g = { filter = filter, opts = opts, max = opts and opts.maxFrameCount, layout = opts and opts.layout }
        self.__groups[key] = g
        self.__groupOrder[#self.__groupOrder + 1] = key
        self.__untrusted = true
        if opts and opts.initializeFrame then
            g.buttons = {}
            for i = 1, stub.AURA_BATCH do g.buttons[i] = newAuraButton(self, opts.initializeFrame) end
            g.button = g.buttons[1]
        end
    end
    -- Weapon enchants drawn by the container itself (Blizzard_AuraContainerEnchantments.lua).
    -- A slot is added once (a second add asserts), switched on and off, never
    -- removed. The client fills it from C_PaperDollInfo.GetTemporaryEnchantmentInfo,
    -- in combat too.
    c.__enchants = {}
    local function validSlot(slot)
        assert(slot == 0 or slot == 1 or slot == 2, "itemEnchantmentSlot must be a valid AuraContainerItemEnchantmentSlot.")
    end
    function c:AddItemEnchantment(slot, opts)
        validSlot(slot)
        assert(not self.__enchants[slot], "item enchantment already exists with this slot.")
        assert(opts == nil or opts.hidePermanent == nil or type(opts.hidePermanent) == "boolean", "hidePermanent must be a boolean or nil.")
        local e = { opts = opts, enabled = true }
        self.__enchants[slot] = e
        self.__untrusted = true
        if opts and opts.initializeFrame then e.button = newAuraButton(self, opts.initializeFrame) end
        return e.button
    end
    function c:SetItemEnchantmentEnabled(slot, on)
        validSlot(slot)
        assert(type(on) == "boolean", "enabled must be a boolean.")
        assert(self.__enchants[slot], "item enchantment was not found with this slot.")
        self.__enchants[slot].enabled = on
    end
    function c:SetItemEnchantmentLayout(l)
        assert(l == nil or l.placement == nil or l.placement == 0 or l.placement == 1, "placement must be a valid CustomAuraContainerItemEnchantmentPlacement.")
        self.__enchantLayout = l
    end
    function c:SetItemEnchantmentSortMethod(method, dir)
        assert(method == 0 or method == 1, "sortMethod must be a valid AuraContainerItemEnchantmentSortMethod.")
        assert(dir == 0 or dir == 1, "sortDirection must be a valid AuraContainerSortDirection.")
        self.__enchantSort = { method, dir }
    end
    function c:SetAuraGroupMaxFrameCount(key, n) assert(self.__groups[key], key); self.__groups[key].max = n end
    function c:SetAuraGroupLayout(key, l) assert(self.__groups[key], key); self.__groups[key].layout = l end
    function c:SetFlowLayoutAnchorPoint(p) self.__anchorPoint = p end
    function c:SetFlowLayoutGrowthDirection(h, v) self.__growth = { h, v } end
    function c:SetFlowLayoutMaximumLineSize(n) self.__lineSize = n end
    return c
end

-- The client giving a button its aura or taking it away, as in
-- CustomAuraButtonPrivateMixin:ApplyVisibility (Blizzard_CustomAuraButton.lua).
-- Shown for an aura, its shown animations play when it comes up and stop when it
-- has none. This is the client's own code, so it runs in fights and under
-- restrictions too.
function stub.AuraVisible(btn, on)
    local was = btn.__auraShown == true
    btn.__auraShown = on and true or false
    -- The client's own SetShown is never refused, unlike an addon's on a locked
    -- button. OnShow/OnHide run on what's shown inside it.
    local wasShown = rawget(btn, "__shown")
    rawset(btn, "__shown", on and true or false)
    if (on and true or false) ~= (wasShown and true or false) and parentsShown(btn) then
        cascade(btn, on and "OnShow" or "OnHide")
    end
    for _, g in ipairs(btn.__shownAnims or {}) do
        if on and not was then g:Play() elseif not on then g:Stop() end
    end
end

-- A button the client makes for a group or a weapon slot. Its initializeFrame
-- runs once, then it's locked like the game's (see isLocked).
function newAuraButton(c, initializeFrame)
    local btn = new("Button", nil, c)
    -- Every piece handed to the button must be the right type and live inside it
    -- (AuraContainerUtil.ValidateInboundScriptObject), so a bar parented elsewhere errors.
    local function inbound(owner, obj, kind)
        if type(obj) ~= "table" or obj.__type ~= kind then
            error(string.format("bad object '%s' in function call (expected object type '%s', got '%s')",
                tostring(obj), kind, type(obj) == "table" and tostring(obj.__type) or type(obj)), 3)
        end
        local p = obj.__parent
        while p and p ~= owner do p = p.__parent end
        if p ~= owner then
            error(string.format("bad object '%s' in function call (must be the owner or a direct or indirect descendant of owner)",
                obj:GetDebugName()), 3)
        end
    end
    function btn:SetIcon(t) inbound(self, t, "Texture"); self.__icon = t end
    function btn:SetDurationCooldown(cd) inbound(self, cd, "Cooldown"); self.__cooldown = cd end
    function btn:SetApplicationCount(fs) inbound(self, fs, "FontString"); self.__count = fs end
    function btn:SetDurationText(fs, opts) inbound(self, fs, "FontString"); self.__time, self.__timeOpts = fs, opts end
    function btn:SetDurationBar(bar, opts) inbound(self, bar, "StatusBar"); self.__bar, self.__barOpts = bar, opts end
    -- Played by the client as the button comes up for a new aura. Kept in __shownAnims.
    function btn:AddAuraShownAnimation(g)
        inbound(self, g, "AnimationGroup")
        self.__shownAnims = self.__shownAnims or {}
        table.insert(self.__shownAnims, g)
    end
    -- From AuraButtonSharedMixin (Blizzard_AuraButton.lua), part of the game's template.
    function btn:SetCancelAuraButtons(b) self.__cancelButtons = b end
    btn.__inAura = btn
    initializeFrame(btn)
    btn.__auraLock = true
    return btn
end

-- The combat text feed. GetCurrentEventInfo is SecretReturns; a test sets the
-- message with stub.CombatTextInfo = { data, arg3, arg4 }.
_G.C_CombatText = {
    SetActiveUnit = function(u) stub.combatTextUnit = u end,
    GetActiveUnit = function() return stub.combatTextUnit end,
    GetCurrentEventInfo = function()
        local info = stub.CombatTextInfo or { 12 }
        local function hide(v) if v ~= nil then return stub.Secret(v) end end
        return hide(info[1]), hide(info[2]), hide(info[3])
    end,
}

-- A ScrollingMessageFrame. The game's ScrollingMessageFrameMixin is Lua
-- (Blizzard_SharedXML/ScrollingMessageFrame.lua) and not in the API docs, so its
-- methods are copied here as the game has them. Messages are stored oldest first
-- (GetMessageInfo(1) is the oldest) and scrolled by line count. AddMessage while
-- scrolled up keeps the view, and ScrollToBottom/ScrollToTop reset the fade.
-- Lines fade after 120 s like ChatFrameMixin. f.lines: { text, r, g, b, timestamp }.
function stub.MessageFrame(f)
    f.lines, f.scrollOffset, f.maxLines = {}, 0, 120
    f.timeVisibleSecs, f.shouldFadeAfterInactivity, f.fadeResets = 120, true, 0
    f.onDisplayRefreshedCallbacks = {}
    -- The shown lines, newest at the bottom, as the mixin's RefreshDisplay builds
    -- them: each font string gets its message's text, color and entry, then the
    -- redraw callbacks run.
    f.visibleLines = {}
    function f:FakeRefresh()
        local size = (self.font and self.font[2]) or 14
        local n, shown = #self.lines, 0
        local room = math.max(1, math.floor(((self:GetHeight() or 0) > 0 and self:GetHeight() or 200) / (size + 3)))
        for i = 1, room do
            local l = self.lines[n - self.scrollOffset - i + 1]
            local fs = self.visibleLines[i]
            if l then
                if not fs then
                    fs = self:CreateFontString()
                    self.visibleLines[i] = fs
                end
                fs:SetFont(self.font and self.font[1] or "GameFont", size, self.font and self.font[3] or "")
                fs:ClearAllPoints()
                fs:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, (i - 1) * (size + 3))
                fs:SetPoint("RIGHT", self, "RIGHT")
                fs:SetJustifyH("LEFT")
                fs:SetWordWrap(false)
                fs:SetText(l[1])
                fs:SetTextColor(l[2] or 1, l[3] or 1, l[4] or 1)
                fs.messageInfo = { message = l[1], timestamp = l.timestamp, extraData = l.extra }
                fs:SetAlpha(1)
                fs:Show()
                shown = i
            elseif fs then
                fs:Hide()
                fs.messageInfo = nil
            end
        end
        for i = room + 1, #self.visibleLines do self.visibleLines[i]:Hide() end
        for _, fn in ipairs(self.onDisplayRefreshedCallbacks) do fn(self) end
        return shown
    end
    function f:AddMessage(msg, r, g, b, ...)
        local n = select("#", ...)
        local extra = n > 0 and { ... } or nil
        if extra then extra.n = n end
        table.insert(self.lines, { msg, r, g, b, timestamp = GetTime(), extra = extra })
        while #self.lines > self.maxLines do table.remove(self.lines, 1) end
        if self.scrollOffset ~= 0 then self:ScrollUp() end
    end
    -- The predicate gets each entry unpacked like the mixin's UnpackageEntry:
    -- message, r, g, b, then whatever else AddMessage was given.
    function f:RemoveMessagesByPredicate(pred)
        local keep = {}
        for _, l in ipairs(self.lines) do
            local x = l.extra
            local gone
            if x then gone = pred(l[1], l[2], l[3], l[4], unpack(x, 1, x.n)) else gone = pred(l[1], l[2], l[3], l[4]) end
            if not gone then keep[#keep + 1] = l end
        end
        self.lines = keep
    end
    function f:GetNumMessages() return #self.lines end
    function f:GetMessageInfo(i)
        local l = self.lines[i]
        if l then return l[1], l[2], l[3], l[4] end
    end
    function f:Clear() self.lines = {}; self.scrollOffset = 0 end
    function f:GetMaxScrollRange() return math.max(#self.lines - 1, 0) end
    function f:SetScrollOffset(o)
        o = math.max(0, math.min(o, self:GetMaxScrollRange()))
        if o == self.scrollOffset then return end
        self.scrollOffset = o
        if self.onScrollChangedCallback then self.onScrollChangedCallback(self, o) end
    end
    function f:SetOnScrollChangedCallback(fn) self.onScrollChangedCallback = fn end
    -- Like CalculateNumVisibleLines, with one fixed line spacing.
    function f:GetNumVisibleLines() return math.ceil((self:GetHeight() or 0) / 14) + 1 end
    function f:GetScrollOffset() return self.scrollOffset end
    function f:ScrollByAmount(n) self:SetScrollOffset(self.scrollOffset + n) end
    function f:ScrollUp() self:ScrollByAmount(1) end
    function f:ScrollDown() self:ScrollByAmount(-1) end
    function f:PageUp() self:ScrollByAmount(5) end
    function f:PageDown() self:ScrollByAmount(-5) end
    function f:ScrollToTop() self:SetScrollOffset(self:GetMaxScrollRange()); self:ResetAllFadeTimes() end
    function f:ScrollToBottom() self:SetScrollOffset(0); self:ResetAllFadeTimes() end
    function f:AtTop() return self.scrollOffset == self:GetMaxScrollRange() end
    function f:AtBottom() return self.scrollOffset == 0 end
    function f:SetMaxLines(n) self.maxLines = n end
    function f:GetMaxLines() return self.maxLines end
    function f:SetFading(on) self.shouldFadeAfterInactivity = not not on end
    function f:GetFading() return self.shouldFadeAfterInactivity end
    function f:SetTimeVisible(t) self.timeVisibleSecs = t end
    function f:GetTimeVisible() return self.timeVisibleSecs end
    function f:SetFadeDuration(t) self.fadeDurationSecs = t end
    function f:GetFadeDuration() return self.fadeDurationSecs end
    function f:ResetAllFadeTimes() self.fadeResets = self.fadeResets + 1 end
    function f:SetInsertMode(m) self.insertMode = m end
    function f:SetTextCopyable(on) self.textIsCopyable = not not on end
    function f:IsTextCopyable() return self.textIsCopyable == true end
    function f:SetIndentedWordWrap(on) self.indentedWordWrap = on end
    function f:SetFont(file, size, flags) self.font = { file, size, flags } end
    function f:GetFont() local t = self.font or {}; return t[1], t[2], t[3] end
    function f:SetJustifyH(j) self.justifyH = j end
    function f:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
    function f:SetShadowColor(...) self.shadowColor = { ... } end
    function f:AddOnDisplayRefreshedCallback(fn) table.insert(self.onDisplayRefreshedCallbacks, fn) end
    return f
end

-- The client's CreateFont(name) returns a Font object (font, size, color, justify,
-- shadow), global by its name. It has no frame, so it never shows up in EnumerateFrames.
_G.CreateFont = function(name)
    local f = setmetatable({ __type = "Font", __name = name, __shown = true, __events = {}, __unitEvents = {},
        __scripts = {}, __attrs = {}, __points = {}, __scale = 1, __level = 0 }, WidgetMT)
    if name then _G[name] = f end
    return f
end

_G.CreateFrame = function(objType, name, parent, template)
    if objType == "AuraContainer" then return newAuraContainer(name, parent, template) end
    if objType == "ScrollingMessageFrame" then return stub.MessageFrame(new("Frame", name, parent, template)) end
    local f = new(objType, name, parent, template)
    if template and string.find(template, "Secure", 1, true) then f.__protected = true end
    if template then
        for t in string.gmatch(template, "[^,%s]+") do
            local build = stub.TEMPLATES[t]
            if build then build(f) end
        end
    end
    return f
end

-- ---------------------------------------------------------------------
-- Events, scripts, timers
-- ---------------------------------------------------------------------

-- Payload secrets (tests/secret_api.lua, from the game's event docs). While an
-- event's condition holds, addon handlers get its payload as secrets, e.g.
-- UNIT_AURA's unit and updateInfo while auras are restricted, or CHAT_MSG_* in
-- chat lockdown. The client still filters RegisterUnitEvent by the real unit.
-- Handlers written in tests/ (the game's own code, test frames) get the plain
-- payload, since untainted code may use secrets.
local addonHandler = setmetatable({}, { __mode = "k" })
local function isAddonHandler(fn)
    local v = addonHandler[fn]
    if v == nil then
        local info = debug.getinfo(fn, "S")
        local src = info and info.source or ""
        v = string.sub(src, 1, 1) == "@" and not string.find(src, "^@%.?/?tests[/\\]")
        addonHandler[fn] = v
    end
    return v
end
stub.IsAddonHandler = isAddonHandler

-- When the game's code shows, hides, resizes or enables a frame, the scripts
-- of the pieces inside it run inside that call, before the frame's own
-- OnShow (seen in game: a confirm box's buttons and their size changes ran
-- before its OnShow, where the controller code stores the box's actions). An
-- addon's script there leaves the rest of the game's call tainted. Lists each
-- "piece.script" under frame (not frame itself) where addon code would run.
stub.INSIDE_SCRIPTS = { "OnShow", "OnHide", "OnSizeChanged", "OnEnable", "OnDisable",
    "OnMouseDown", "OnMouseUp", "OnEditFocusGained", "OnEditFocusLost", "OnTextChanged" }
function stub.AddonScriptsInside(frame)
    local found = {}
    local function handlers(f, fn, out)
        local parts = rawget(f, "__hookParts")
        local pair = parts and parts[fn]
        if pair then
            if pair[1] then handlers(f, pair[1], out) end
            handlers(f, pair[2], out)
        elseif fn then
            out[#out + 1] = fn
        end
        return out
    end
    local function walk(f, path)
        for i, child in ipairs({ f:GetChildren() }) do
            local name = path .. "." .. (child:GetName() or tostring(i))
            for _, script in ipairs(stub.INSIDE_SCRIPTS) do
                for _, fn in ipairs(handlers(child, child:GetScript(script), {})) do
                    if isAddonHandler(fn) then
                        local info = debug.getinfo(fn, "S")
                        found[#found + 1] = name .. "." .. script .. " (" .. info.short_src .. ":" .. info.linedefined .. ")"
                    end
                end
            end
            walk(child, name)
        end
    end
    walk(frame, frame:GetName() or "frame")
    return found
end

-- The two halves of a HookScript chain, so each gets its own payload.
local function callHandler(fn, secretArgs, nargs, f, event, ...)
    local hooks = rawget(f, "__hookParts")
    local parts = hooks and hooks[fn]
    if parts then
        if parts[1] then callHandler(parts[1], secretArgs, nargs, f, event, ...) end
        return callHandler(parts[2], secretArgs, nargs, f, event, ...)
    end
    if secretArgs and isAddonHandler(fn) then return fn(f, event, unpack(secretArgs, 1, nargs)) end
    return fn(f, event, ...)
end
function stub.FireEvent(event, ...)
    local unit = ...
    local nargs, secretArgs = 0, nil
    local spec = stub.secretEvents and stub.secretEvents[event]
    if spec and stub.PayloadSecret(spec, unit) then nargs, secretArgs = stub.SecretPayload(spec, ...) end
    local b = byEvent[event]
    if not b then return end
    local list = b.list
    if b.dirty then
        -- Creation order, as a scan of every widget would find them. Widgets
        -- from an earlier world (stub.Reset) drop out.
        local keep = {}
        for _, f in ipairs(list) do
            local i = frameIndex[f]
            if i and frames[i] == f then keep[#keep + 1] = f else b.set[f] = nil end
        end
        table.sort(keep, byAge)
        list, b.list, b.dirty = keep, keep, false
    end
    for i = 1, #list do
        local f = list[i]
        if f.__events[event] and f.__scripts.OnEvent then
            local filter = f.__unitEvents[event]
            local pass = true
            if filter and #filter > 0 then
                pass = false
                for _, u in ipairs(filter) do if u == unit then pass = true end end
            end
            if pass then
                if secretArgs then callHandler(f.__scripts.OnEvent, secretArgs, nargs, f, event, ...)
                else f.__scripts.OnEvent(f, event, ...) end
            end
        end
    end
end

function stub.RunOnUpdate(frame, dt)
    local fn = frame.__scripts.OnUpdate
    if fn then fn(frame, dt) end
end

local timers = {}
_G.tinsert = table.insert
local function timerAfter(_, fn) timers[#timers + 1] = fn end
-- Tickers don't run on their own; stub.RunTickers() fires each once.
-- Each keeps its interval so tests/test_lag.lua can check none is faster than the fade's.
stub.tickers = {}
local function newTicker(interval, fn)
    local t = { fn = fn, interval = interval, Cancel = function(self) self.cancelled = true end }
    stub.tickers[#stub.tickers + 1] = t
    return t
end
-- stub.Reset restores these, since a test world may swap them (abworld's ticker).
function stub.ResetTimers()
    _G.C_Timer = type(_G.C_Timer) == "table" and _G.C_Timer or {}
    C_Timer.After, C_Timer.NewTicker = timerAfter, newTicker
end
stub.ResetTimers()
function stub.RunTickers()
    for _, t in ipairs(stub.tickers) do if not t.cancelled then t.fn() end end
end
-- Runs a window's fade-out (Motion.Vanish) to the end, leaving it hidden.
function stub.FinishFade(f)
    local owner = stub.feelOwner or rawget(_G, "DaylightUI")   -- DaylightMogul sets stub.feelOwner to its own copy of the window kit
    local Win = owner and owner.Win
    if f and Win and Win.Feel then Win.Feel.Settle(f) end   -- the window kit's moves (Windows/Feel.lua)
    local g = f and f.__duiMotion and f.__duiMotion.vanish
    if g and g:IsPlaying() then
        g.__playing = false
        local fn = g:GetScript("OnFinished")
        if fn then fn(g) end
    end
end
function stub.RunTimers()
    for _ = 1, 10 do
        if #timers == 0 then return end
        local pending = timers
        timers = {}
        for _, fn in ipairs(pending) do fn() end
    end
end

_G.InCombatLockdown = function() return stub.combat end
-- What the cursor holds: stub.cursor = { "spell", id } or nil.
_G.GetCursorInfo = function() local c = stub.cursor; if c then return c[1], c[2] end end
_G.ClearCursor = function() stub.cursor = nil end
-- Like the client, PLAYER_REGEN_DISABLED fires just before the lockdown, so its
-- handlers may still change protected frames (the setup guide hides its secure
-- Reload button there).
function stub.EnterCombat()
    stub.combat, stub.enteringCombat = true, true
    -- [group] and [group:...] keep their state until the fight ends, while unit
    -- tokens follow the roster. Seen in game.
    stub.frozenGroup = {}
    for c, v in pairs(stub.conditions) do
        if c == "group" or string.sub(c, 1, 6) == "group:" then stub.frozenGroup[c] = v end
    end
    stub.FireEvent("PLAYER_REGEN_DISABLED")
    stub.enteringCombat = false
    stub.SetRestriction("Combat", true)
end
function stub.LeaveCombat()
    stub.combat, stub.frozenGroup = false, nil
    stub.SetRestriction("Combat", false)
    stub.RunDrivers()
    stub.FireEvent("PLAYER_REGEN_ENABLED")
end

-- ---------------------------------------------------------------------
-- Screen
-- ---------------------------------------------------------------------

function stub.SetScreen(physW, physH, uiScale)
    stub.physW, stub.physH, stub.uiScale = physW, physH, uiScale
    local ui = _G.UIParent
    if ui then
        ui.__scale = uiScale
        ui.__w = physW / physH * 768 / uiScale
        ui.__h = 768 / uiScale
    end
end
_G.GetPhysicalScreenSize = function() return stub.physW, stub.physH end

-- ---------------------------------------------------------------------
-- Units. stub.units[token] = { name, class, isPlayer, reaction, tapped,
-- health, maxHealth, pct, power, maxPower, powerToken, classification,
-- raidTarget, cast = { name, texture, notInterruptible, duration },
-- channel = { ... } }
-- ---------------------------------------------------------------------

local function U(u) return stub.units[u] end
_G.UnitExists = function(u) return U(u) ~= nil end
_G.UnitGUID = function(u) local x = U(u); return x and x.guid end
-- minion = true marks an enemy pet or totem (the game's "minion" plates).
_G.UnitIsMinion = function(u) local x = U(u); return x ~= nil and x.minion == true end
_G.UnitName = function(u)
    local x = U(u)
    if x then return x.name end
    if u == "player" then return stub.playerName end
end
stub.playerName = "Tester"
-- In this client the second value is a last name (units[u].lastName), not a realm.
_G.UnitFullName = function(u)
    local x = U(u)
    if x then return x.name, x.lastName end
    if u == "player" then return stub.playerName end
end
-- classHidden = true makes the class a secret, as for enemy players in a battleground.
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6,
    SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
_G.UnitClassBase = function(u)
    local x = U(u)
    if not (x and x.class) then return end
    local id = CLASS_IDS[x.class] or 1
    if x.classHidden then return stub.Secret(x.class), stub.Secret(id) end
    return x.class, id
end
_G.UnitClass = function(u)
    local token, id = UnitClassBase(u)
    if token ~= nil then return token, token, id end
end
_G.UnitIsPlayer = function(u) local x = U(u); if not x then return false end return x.isPlayer end
-- units[u].guid. The player has one even without a unit table, as with its name.
_G.UnitGUID = function(u)
    local x = U(u)
    if x then return x.guid or (u == "player" and stub.PLAYER_GUID or nil) end
    if u == "player" then return stub.PLAYER_GUID end
end
stub.PLAYER_GUID = "Player-1-0000TEST"
-- Per the game's docs, both take a secret GUID (AllowedWhenTainted) and a secret
-- one hands back secrets. The token is secret under identity restrictions
-- (SecretWhenUnitIdentityRestricted).
local function unitByGUID(g)
    for token, x in pairs(stub.units) do
        if type(x) == "table" and x.guid ~= nil and x.guid == g then return token, x end
    end
end
_G.UnitTokenFromGUID = function(g)
    if isSecret(g) then return nil end
    return (unitByGUID(g))
end
-- localizedClass, englishClass, localizedRace, englishRace, sex, name, realm.
_G.GetPlayerInfoByGUID = function(g)
    local secret = isSecret(g)
    local _, x = unitByGUID(secret and rawget(g, "__value") or g)
    if not (x and x.isPlayer ~= false and x.class) then return end
    local function v(a) return secret and stub.Secret(a) or a end
    return v(x.class), v(x.class), v("Human"), v("Human"), v(2), v(x.name or ""), v("")
end
_G.UnitReaction = function(u) local x = U(u); return x and x.reaction end
-- Whether the player can attack a unit: its own `attackable` flag, else an
-- unfriendly reaction (1-4), else a unit marked enemy.
_G.UnitCanAttack = function(_, u)
    local x = U(u)
    if not x then return false end
    if x.attackable ~= nil then return x.attackable == true end
    if type(x.reaction) == "number" then return x.reaction <= 4 end
    return x.enemy == true
end
_G.UnitIsTapDenied = function(u) local x = U(u); return x and x.tapped or false end
_G.UnitHealth = function(u) local x = U(u); return x and x.health or 0 end
-- In the client `unit` can't be nil here (UnitExists accepts nil, this doesn't).
_G.UnitHealthMax = function(u)
    if u == nil then error("bad argument #1 to 'UnitHealthMax' (Usage: local result = UnitHealthMax(unit))", 2) end
    local x = U(u)
    return x and x.maxHealth or 1
end
_G.UnitHealthMissing = function(u)
    local x = U(u)
    if not x then return 0 end
    return stub.Plain(x.maxHealth or 1) - stub.Plain(x.health or 0)
end
_G.UnitHealthPercent = function(u, _, curve)
    stub.lastCurve = curve
    local x = U(u)
    return x and x.pct or 0
end
_G.UnitPower = function(u, kind)
    local x = U(u)
    if kind == 0 then return x and x.mana or 0 end
    return x and x.power or 0
end
_G.UnitPowerMax = function(u, kind)
    local x = U(u)
    if kind == 0 then return x and x.maxMana or 1 end
    return x and x.maxPower or 1
end
_G.UnitPowerType = function(u) local x = U(u); return x and x.powerType or 0, x and x.powerToken or "MANA" end
_G.UnitClassification = function(u) local x = U(u); return x and x.classification or "normal" end
_G.UnitIsBossMob = function(u) local x = U(u); return x ~= nil and x.boss == true end
_G.GetRaidTargetIndex = function(u) local x = U(u); return x and x.raidTarget end
_G.GetComboPoints = function() return stub.comboPoints or 0 end
_G.UnitCastingInfo = function(u)
    local x = U(u); local c = x and x.cast
    if not c then return end   -- no cast: the client returns nothing at all, not a nil
    return c.name, c.name, c.texture, c.from or 0, c.to or 0, c.tradeSkill or false, 1, c.notInterruptible, c.spellID or 1
end
-- The client's own duration objects (C_DurationUtil.CreateDuration): a span on
-- GetTime's clock, plain when an addon made it. When handed over secret (copied
-- by a secret-returning call, such as UnitCastingDuration for another unit in a
-- boss fight), its getters return secrets. A text can still show them, and the
-- object never does math on a secret itself.
_G.C_DurationUtil = {
    CreateDuration = function()
        local d = { s = 0, e = 0 }
        local function read(self)
            local s, e = rawget(self, "s"), rawget(self, "e")
            return stub.Plain(s), stub.Plain(e), isSecret(s) or isSecret(e)
        end
        local function answer(v, secret) if secret then return stub.Secret(v) end return v end
        function d:SetTimeSpan(s, e) self.s, self.e = s, e end
        function d:SetTimeFromStart(s, len) self.s, self.e = s, stub.Plain(s) + stub.Plain(len) end
        function d:GetStartTime() local s, _, sec = read(self) return answer(s, sec) end
        function d:GetEndTime() local _, e, sec = read(self) return answer(e, sec) end
        function d:GetTotalDuration() local s, e, sec = read(self) return answer(e - s, sec) end
        function d:GetElapsedDuration() local s, _, sec = read(self) return answer(math.max(0, GetTime() - s), sec) end
        function d:GetRemainingDuration() local _, e, sec = read(self) return answer(math.max(0, e - GetTime()), sec) end
        return d
    end,
}
_G.UnitChannelInfo = function(u)
    local x = U(u); local c = x and x.channel
    if not c then return end   -- no cast: the client returns nothing at all, not a nil
    return c.name, c.name, c.texture, 0, 0, false, c.notInterruptible, 1
end
_G.UnitCastingDuration = function(u) local x = U(u); return x and x.cast and x.cast.duration end
_G.UnitChannelDuration = function(u) local x = U(u); return x and x.channel and x.channel.duration end
function stub.Duration(remaining) return { GetRemainingDuration = function() return remaining end } end

-- ---------------------------------------------------------------------
-- Constants and small globals
-- ---------------------------------------------------------------------

_G.CurveConstants = { ScaleTo100 = "ScaleTo100" }
_G.Enum = {
    StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 },
    StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
    CustomAuraButtonDispelTypeTextureStyle = { Border = 0, BorderWithIcon = 1, CustomAsset = 2, PreserveAsset = 3 },
    CustomAuraButtonDispelTypeStealableFilter = { Stealable = 0, NotStealable = 1 },
}
_G.AuraContainerSortMethod = { Default = 0, ExpirationOnly = 5 }
_G.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
-- Blizzard_AuraContainerShared.lua
_G.AuraContainerItemEnchantmentSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }
_G.AuraContainerItemEnchantmentSortMethod = { Slot = 0, Duration = 1 }
_G.CustomAuraContainerItemEnchantmentPlacement = { BeforeAuraGroups = 0, AfterAuraGroups = 1 }
_G.AnchorUtil = { FlowDirection = { Left = 0, Right = 1, Up = 2, Down = 3 } }
-- The client's number formatter. It just keeps the rules it was given.
_G.C_StringUtil = { CreateNumericRuleFormatter = function()
    return { SetBreakpoints = function(self, steps) self.steps = steps end }
end }
Enum.NumericRuleFormatRounding = { Down = 0, Up = 1, Nearest = 2 }
-- Addon restrictions (RestrictedActionsDocumentation.lua): combat, a boss
-- encounter, a keystone, a PvP match, a restricted map, chat lockdown.
-- stub.SetRestriction("PvPMatch", true) enters one and fires
-- ADDON_RESTRICTION_STATE_CHANGED. Like the client, IsAddOnRestrictionActive
-- answers false while that event is being dispatched.
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }
stub.restrictions = {}
_G.C_RestrictedActions = {
    IsAddOnRestrictionActive = function(t)
        return not stub.inRestrictionDispatch and stub.restrictions[t] == true
    end,
    GetAddOnRestrictionState = function(t)
        if stub.inRestrictionDispatch then return Enum.AddOnRestrictionState.Inactive end
        return stub.restrictions[t] and Enum.AddOnRestrictionState.Active or Enum.AddOnRestrictionState.Inactive
    end,
}
-- kind is "party", "raid", "pvp", "arena", "scenario", or nil for the open world.
-- This only sets it. The game announces it with PLAYER_ENTERING_WORLD (a loading
-- screen) or ZONE_CHANGED_NEW_AREA, which a test fires itself.
function stub.SetInstance(kind) stub.instance = kind end

function stub.SetRestriction(name, on)
    local t = assert(Enum.AddOnRestrictionType[name], name)
    if (stub.restrictions[t] == true) == (on and true or false) then return end
    stub.restrictions[t] = on and true or nil
    local S = Enum.AddOnRestrictionState
    stub.inRestrictionDispatch = true
    local ok, err = pcall(stub.FireEvent, "ADDON_RESTRICTION_STATE_CHANGED", t, on and S.Activating or S.Inactive)
    stub.inRestrictionDispatch = false
    if not ok then error(err, 0) end
end
-- Auras are secret (and aura buttons locked) in combat and under any restriction
-- except chat lockdown.
function stub.AurasRestricted()
    if stub.combat then return true end
    for t in pairs(stub.restrictions) do
        if t ~= Enum.AddOnRestrictionType.Chat then return true end
    end
    return false
end
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- The client's thousands separator: 1200 -> "1,200". It accepts a secret
-- (AllowedWhenTainted) and returns a secret string.
-- Below 1000 a fraction keeps two decimals ("335.27") unless `natural` is true.
-- The game's old Lua version did this, and the client's docs keep the switch.
_G.BreakUpLargeNumbers = function(v, natural)
    if isSecret(v) then return stub.Secret(BreakUpLargeNumbers(rawget(v, "__value"), natural)) end
    if not natural and v < 1000 and v ~= math.floor(v) then
        return string.format("%.2f", math.floor(v * 100) / 100)
    end
    local s = tostring(math.floor(v))
    local n
    repeat s, n = s:gsub("^(%-?%d+)(%d%d%d)", "%1,%2") until n == 0
    return s
end

-- The client's shortener accepts secret values, and so does this fake.
-- With break points from CreateAbbreviateConfig it follows them like the client:
-- the first tier the value reaches, cut to its divisors.
-- A config refuses a tier at 0 or below (RequiresRestrictedAbbreviationBreakpoints,
-- seen in game). Break points handed straight to the shortener (`breakpointData`)
-- have no such rule, so a tier at 0 works there.
_G.CreateAbbreviateConfig = function(tiers)
    for _, b in ipairs(tiers) do
        if b.breakpoint <= 0 then error("CreateAbbreviateConfig: invalid breakpoint", 2) end
    end
    return { tiers = tiers }
end
_G.AbbreviateNumbers = function(v, options)
    -- A secret in, a secret string out.
    if isSecret(v) then return stub.Secret(AbbreviateNumbers(rawget(v, "__value"), options)) end
    local tiers = options and (options.config and options.config.tiers or options.breakpointData)
    if tiers then
        for _, b in ipairs(tiers) do
            if v >= b.breakpoint then
                local n = math.floor(v / b.significandDivisor) / b.fractionDivisor
                local s = n == math.floor(n) and string.format("%d", n) or tostring(n)
                return s .. b.abbreviation
            end
        end
        return tostring(v)     -- no tier reached: the client returns the number as is
    end
    if v >= 1000 then return string.format("%.1fK", v / 1000) end
    return tostring(v)
end
_G.RAID_CLASS_COLORS = {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, PRIEST = { r = 1, g = 1, b = 1 },
}
-- Accepts a secret class (AllowedWhenTainted), and the color then comes back as
-- secret numbers.
_G.C_ClassColor = { GetClassColor = function(name)
    local v = isSecret(name) and rawget(name, "__value") or name
    local c = RAID_CLASS_COLORS[v]
    if not c then return nil end
    if isSecret(name) then return { r = stub.Secret(c.r), g = stub.Secret(c.g), b = stub.Secret(c.b) } end
    return { r = c.r, g = c.g, b = c.b }
end }
_G.PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 }, ENERGY = { r = 1, g = 1, b = 0 } }
-- Macro conditions, parsed like the client: "[a,b][c] value; ...; default".
-- Brackets side by side mean "or", commas inside one mean "and", and "no" in
-- front negates a condition. Conditions come from stub.conditions, except
-- [group], which is frozen at the start of a fight (stub.EnterCombat).
-- "@unit,exists" asks the unit.
local function conditionValue(c)
    if stub.frozenGroup and (c == "group" or string.sub(c, 1, 6) == "group:") then return stub.frozenGroup[c] end
    return stub.conditions[c]
end
local function condition(c)
    if c == "" then return true end
    -- "form:1/3" matches any of them, as the client reads a slash.
    local name, list = string.match(c, "^(%a+):(.+/.+)$")
    if name then
        for one in string.gmatch(list, "[^/]+") do
            if condition(name .. ":" .. one) then return true end
        end
        return false
    end
    local v = conditionValue(c)
    if v == nil and string.sub(c, 1, 2) == "no" then return not conditionValue(string.sub(c, 3)) end
    return v == true
end
_G.SecureCmdOptionParse = function(rule)
    for clause in string.gmatch(rule .. ";", "([^;]*);") do
        clause = clause:match("^%s*(.-)%s*$")
        if clause ~= "" then
            local pass, value = true, clause
            if string.sub(clause, 1, 1) == "[" then
                pass = false
                value = string.gsub(clause, "%b[]", function(group)
                    local all, unit = true, nil
                    for c in string.gmatch(string.sub(group, 2, -2) .. ",", "([^,]*),") do
                        c = c:match("^%s*(.-)%s*$")
                        if string.sub(c, 1, 1) == "@" then
                            unit = string.sub(c, 2)
                        elseif c == "exists" and unit then
                            if not UnitExists(unit) then all = false end
                        elseif not condition(c) then
                            all = false
                        end
                    end
                    if all then pass = true end
                    return ""
                end)
                value = value:match("^%s*(.-)%s*$")
            end
            if pass then return value end
        end
    end
end

local function blockedInCombat(what)
    if stub.secure and stub.combat and not stub.enteringCombat and (stub.inSecure or 0) == 0 then
        error("ADDON_ACTION_BLOCKED: " .. what, 3)
    end
end

-- State drivers record their rule. In secure mode they also run, now and whenever
-- stub.SetConditions changes the conditions. "visibility" shows or hides the frame;
-- any other state sets "state-<name>", which runs the frame's _onstate-<name> snippet.
_G.RegisterStateDriver = function(f, state, cond)
    blockedInCombat("RegisterStateDriver")
    f.__stateDriver = f.__stateDriver or {}
    f.__stateDriver[state] = cond
    if stub.secure then
        stub.drivers[f] = true
        stub.RunDriver(f, state)
    end
end
_G.UnregisterStateDriver = function(f, state)
    blockedInCombat("UnregisterStateDriver")
    if f.__stateDriver then f.__stateDriver[state] = nil end
end

function stub.RunDriver(f, state)
    local rule = f.__stateDriver and f.__stateDriver[state]
    if not rule then return end
    local value = SecureCmdOptionParse(rule)
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(function()
        if state == "visibility" then
            if value == "show" then f:Show() elseif value == "hide" then f:Hide() end
        else
            f:SetAttribute("state-" .. state, value)
        end
    end)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 0) end
end

function stub.RunDrivers()
    for f in pairs(stub.drivers) do
        for state in pairs(f.__stateDriver or {}) do stub.RunDriver(f, state) end
    end
end

function stub.SetConditions(t)
    stub.conditions = t or {}
    stub.RunDrivers()
end

-- Snippets run as real Lua in a small restricted environment. self is a handle
-- with a few methods (no CallMethod), plus the snippet's arguments and a short
-- list of globals. Anything else errors, so a call the client wouldn't allow
-- fails the test.
stub.RESTRICTED_GLOBALS = { tonumber = tonumber, tostring = tostring, type = type, math = math,
                            string = string, format = string.format, select = select }
-- RestrictedEnvironment.lua gives snippets GetShapeshiftForm directly: the form
-- you're in by its place on the stance bar, 0 for none ([form:N] here).
stub.RESTRICTED_GLOBALS.GetShapeshiftForm = function()
    for k, on in pairs(stub.conditions or {}) do
        local n = on and string.match(k, "^form:(%d+)$")
        if n then return tonumber(n) end
    end
    return 0
end
-- A click on a SecureActionButtonTemplate button with type "attribute" (a macro's
-- /click), done the way SECURE_ACTIONS.attribute does it in SecureTemplates.lua.
-- The name and value go onto attribute-frame (else the button itself) in the
-- secure world, then the button's OnClick scripts and hooks run.
function stub.SecureClick(b, button)
    button = button or "LeftButton"
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(function()
        if b:GetAttribute("type") == "attribute" then
            local frame = b:GetAttribute("attribute-frame") or b
            local name = b:GetAttribute("attribute-name")
            local value = b:GetAttribute("attribute-value")
            if name then frame:SetAttribute(name, value) end
        end
    end)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 0) end
    local fn = b:GetScript("OnClick")
    if fn then fn(b, button, false) end
end
local SNIPPET_ARGS = { self = true, newstate = true, stateid = true, message = true, scriptid = true, name = true, value = true,
                       delta = true, button = true, down = true }
local HANDLE_METHODS = { "SetAttribute", "GetAttribute", "Show", "Hide", "IsShown", "GetID", "GetName", "EnableMouse",
                         "ClearAllPoints", "SetWidth", "SetHeight" }
local handle
-- As in RestrictedFrames.lua, a handle only reaches protected frames in a fight
-- (GetHandleFrame: "Invalid frame handle"), so a snippet can't read or change an
-- addon frame that isn't secure.
local function handleFrame(f)
    if stub.combat and not protectedTree(f) then error("restricted: Invalid frame handle", 3) end
    return f
end
-- HANDLE:SetPoint. The frame it hangs on must be a handle (protected), "$parent",
-- "$screen" or nil.
local function handlePoint(f, point, rel, relPoint, x, y)
    if type(relPoint) == "number" then relPoint, x, y = nil, relPoint, x end
    relPoint = relPoint or point
    local real
    if type(rel) == "table" and rawget(rel, "__frame") then
        real = rel.__frame
        assert(protectedTree(real), "restricted: Invalid relative frame handle")
    elseif rel == "$parent" then
        real = f.__parent
    elseif rel == nil or rel == "$screen" then
        real = nil
    else
        error("restricted: Invalid relative frame id '" .. tostring(rel) .. "'", 3)
    end
    f:SetPoint(point, real, relPoint, tonumber(x) or 0, tonumber(y) or 0)
end
handle = function(f)
    local h = { __frame = f }
    for _, m in ipairs(HANDLE_METHODS) do h[m] = function(_, ...) local fr = handleFrame(f); return fr[m](fr, ...) end end
    h.SetPoint = function(_, ...) handlePoint(handleFrame(f), ...) end
    h.GetFrameRef = function(_, label)
        local ref = f.__attrs["frameref-" .. label]
        return ref and handle(ref)
    end
    -- Override bindings owned by this frame (priority only, like the game's).
    h.SetBindingClick = function(_, priority, key, target, button)
        if type(target) == "table" and rawget(target, "__frame") then target = target.__frame:GetName() end
        assert(type(target) == "string", "restricted: Invalid click target name")
        SetOverrideBindingClick(handleFrame(f), priority, key, target, button)
    end
    h.ClearBinding = function(_, key) SetOverrideBinding(handleFrame(f), true, key, nil) end
    h.ClearBindings = function() ClearOverrideBindings(handleFrame(f)) end
    -- The frame's own snippet (an attribute), run in its own environment.
    h.RunAttribute = function(_, attr)
        local code = handleFrame(f).__attrs[attr]
        assert(type(code) == "string", "restricted: Invalid snippet body")
        stub.RunSnippet(f, code)
    end
    -- A frame method run insecure (CallMethod_inner in RestrictedFrames.lua uses forceinsecure).
    h.CallMethod = function(_, method, ...)
        local fn = f[method]
        assert(type(fn) == "function", "Invalid method '" .. tostring(method) .. "'")
        local keep = stub.inSecure
        stub.inSecure = 0
        local ok, err = pcall(fn, f, ...)
        stub.inSecure = keep
        if not ok then error(err, 0) end
    end
    h.ChildUpdate = function(_, id, message)
        for _, child in ipairs(stub.Children(f)) do
            local code = child.__attrs["_childupdate-" .. tostring(id)] or child.__attrs["_childupdate"]
            if type(code) == "string" then stub.RunSnippet(child, code, { scriptid = id, message = message }) end
        end
    end
    return setmetatable(h, { __index = function(_, k)
        error("restricted: a frame handle has no " .. tostring(k), 2)
    end })
end
function stub.RunSnippet(f, code, args)
    local env = setmetatable({}, { __index = function(_, k)
        if SNIPPET_ARGS[k] then return nil end
        local v = stub.RESTRICTED_GLOBALS[k]
        if v == nil then error("restricted: " .. tostring(k) .. " isn't allowed in a snippet", 2) end
        return v
    end })
    env.self = handle(f)
    for k, v in pairs(args or {}) do env[k] = v end
    local chunk = assert(loadstring(code, "snippet"))
    setfenv(chunk, env)
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(chunk)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 0) end
end

local Blizz = require("blizzard")
Blizz.Bind(stub)

-- The game's action button template (ActionBarButtonTemplate), built from the
-- game's own code (tests/blizzard/ActionButton.lua): the parts its XML lists,
-- its mixins and scripts in the XML's order, then its OnLoad. Whatever the
-- game's code does on these buttons (a hover, a show, a page change, a drag)
-- really runs here instead of a hand-made copy.
local BUTTON_TEXTURES = { "icon", "IconMask", "SlotBackground", "SlotArt", "Flash", "Border", "NewActionTexture",
                          "SpellHighlightTexture", "LevelLinkLockIcon", "QuickKeybindHighlightTexture" }
local BUTTON_FRAMES = { "AutoCastOverlay", "TextOverlayContainer", "InterruptDisplay", "SpellCastAnimFrame",
                        "TargetReticleAnimFrame" }
-- Parts and flags the game's code only creates when needed (`if not self.X`).
-- They read nil on these buttons rather than as the stub's no-op method.
local BUTTON_LAZY = { ProfessionQualityOverlayFrame = true, TypeIconOverlayFrame = true,
                      AssistedCombatRotationFrame = true, UpdateTooltip = true, HasPopup = true }
local ButtonMT = { __index = function(t, k)
    if BUTTON_LAZY[k] then return nil end
    return WidgetMT.__index(t, k)
end }
-- ActionButtonTemplate.xml's scripts. A template's own scripts beat inherited ones.
local BUTTON_SCRIPTS = {
    OnEnter = "ActionBarButtonMixin_OnEnter",
    OnLeave = "ActionBarButtonMixin_OnLeave",
    OnDragStart = "ActionBarButtonMixin_OnDragStart",
    OnAttributeChanged = "ActionBarActionButtonDerivedMixin_OnAttributeChanged",
    OnEvent = "ActionBarActionButtonDerivedMixin_OnEvent",
    OnClick = "ActionBarActionButtonDerivedMixin_OnClick",
    OnReceiveDrag = "ActionBarActionButtonDerivedMixin_OnReceiveDrag",
    OnDragStop = "ActionBarActionButtonDerivedMixin_OnDragStop",
    OnShow = "ActionBarActionButtonDerivedMixin_OnShow",
    OnHide = "ActionBarActionButtonDerivedMixin_OnHide",
}
stub.BUTTON_SCRIPTS = BUTTON_SCRIPTS

-- The game's code on an addon's button runs tainted, even when a state driver's
-- secure snippet set it off, because it reads the methods and fields addon code
-- put there. A page change in combat showed this in taint.log.
local function asTainted(fn)
    return function(self, ...)
        if self.__game then return fn(self, ...) end
        local keep = stub.inSecure
        stub.inSecure = 0
        local ok, err = pcall(fn, self, ...)
        stub.inSecure = keep
        if not ok then error(err, 0) end
    end
end

local function actionButton(b, onLoad)
    if not stub.gameButtonsLoaded then
        Blizz.Load("ActionButton.lua")
        Blizz.FillFrames()
        stub.gameButtonsLoaded = true
    end
    setmetatable(b, ButtonMT)
    b.__protected = true
    for _, k in ipairs(BUTTON_TEXTURES) do b[k] = b:CreateTexture() end
    b.Flash:Hide()
    b.Name, b.HotKey, b.Count = b:CreateFontString(), b:CreateFontString(), b:CreateFontString()
    for _, k in ipairs(BUTTON_FRAMES) do b[k] = CreateFrame("Frame", nil, b) end
    function b.AutoCastOverlay:ShowAutoCastEnabled(on) self.__autoCast = on end    -- AutoCastOverlayMixin's
    b.SpellHighlightAnim = b:CreateAnimationGroup()     -- the XML's animation
    for _, k in ipairs({ "cooldown", "chargeCooldown", "lossOfControlCooldown" }) do
        local cd = CreateFrame("Cooldown", nil, b)
        function cd:SetCooldownFromDurationObject(d) self.__duration = d end
        function cd:Clear() self.__duration = nil end
        b[k] = cd
    end
    local tex = {}
    for _, k in ipairs({ "Normal", "Highlight", "Pushed", "Checked" }) do
        tex[k] = b:CreateTexture()
        b["Get" .. k .. "Texture"] = function() return tex[k] end
        b[k .. "Texture"] = tex[k]      -- the XML's parentKeys, which the game's code reads
    end
    -- The XML's size and anchors (Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml):
    -- 45 x 45. The icon (no anchors) and the slot art fill it, the name sits at
    -- the bottom, the hotkey top right, the count bottom right, and the text
    -- layer covers all of it.
    b.__w, b.__h = 45, 45
    for _, k in ipairs({ "icon", "SlotBackground", "SlotArt" }) do b[k].__points = { { "ALL", b } } end
    b.IconMask.__points = { { "CENTER", b.icon, "CENTER", 0, 0 } }
    b.Name.__w, b.Name.__h, b.Name.__points = 36, 10, { { "BOTTOM", b, "BOTTOM", 0, 2 } }
    b.HotKey.__w, b.HotKey.__h, b.HotKey.__points = 32, 10, { { "TOPRIGHT", b, "TOPRIGHT", -5, -5 } }
    b.HotKey.__justifyH, b.Count.__justifyH = "RIGHT", "RIGHT"
    b.Count.__points = { { "BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 5 } }
    b.TextOverlayContainer.__points = { { "ALL", b } }
    b.AutoCastOverlay.__w, b.AutoCastOverlay.__h = 45, 45
    b.AutoCastOverlay.__points = { { "CENTER", b, "CENTER", 0, 0 } }
    for _, k in ipairs({ "cooldown", "chargeCooldown", "lossOfControlCooldown" }) do b[k].__points = { { "ALL", b } } end
    function b:SetChecked(on) self.__checked = on == true end
    function b:GetChecked() return self.__checked == true end
    function b:SetButtonState(s) self.__state = s end
    function b:GetButtonState() return self.__state or "NORMAL" end
    -- From a game file the tests don't fetch (the ping mixin). It writes a protected
    -- attribute, so a tainted call in combat is blocked.
    function b:UpdatePingAttributes() self:SetAttribute("ping-receiver", nil) end
    -- The client's CalculateAction: the slot from the "action" attribute.
    function b:CalculateAction() return tonumber(self.__attrs.action) or 1 end
    Mixin(b, Blizz.FAKES.QuickKeybindButtonTemplateMixin, BaseActionButtonMixin,
          ActionBarActionButtonDerivedMixin, ActionBarButtonMixin)
    for script, method in pairs(BUTTON_SCRIPTS) do b:SetScript(script, asTainted(b[method])) end
    asTainted(onLoad or b.ActionBarButtonMixin_OnLoad)(b)
end

-- The game's unit frame ping mixin, line for line (Blizzard_SharedXML/PingableType.lua).
-- The ping system asks the frame under the cursor that has "ping-receiver" for
-- these (Blizzard_PingManager.lua).
local PingableTypeMixin = {
    UpdatePingAttributes = function() end,
    GetIsPingable = function() return true end,
    GetAllowRadialWheel = function() return true end,
    GetTargetInfo = function() return {} end,
}
local PingableType_UnitFrameMixin = {}
for k, v in pairs(PingableTypeMixin) do PingableType_UnitFrameMixin[k] = v end
function PingableType_UnitFrameMixin:GetTargetInfo()
    return { guid = UnitGUID(self.unit or self:GetAttribute("unit")) }
end

-- Templates the client would build. Tests add their own (abworld.lua).
local BASE_TEMPLATES = {
    -- PingAttributes.xml: the mixin plus the XML attribute ping-receiver = true.
    PingableUnitFrameTemplate = function(f)
        for k, v in pairs(PingableType_UnitFrameMixin) do f[k] = v end
        f.__attrs["ping-receiver"] = true
    end,
    ActionBarButtonTemplate = actionButton,
    SecureHandlerBaseTemplate = function(f) f.__protected = true end,
    -- SecureHandlers.lua: OnClick runs the frame's "_onclick" snippet (self,
    -- button, down), then the client's PostClick runs the addon's script.
    SecureHandlerClickTemplate = function(f)
        f.__protected = true
        f.__scripts.OnClick = function(self, button, down)
            local code = self.__attrs._onclick
            if type(code) == "string" then stub.RunSnippet(self, code, { button = button, down = down == true }) end
        end
    end,
    -- OnMouseWheel runs "_onmousewheel" (self, delta).
    SecureHandlerMouseWheelTemplate = function(f)
        f.__protected = true
        f.__scripts.OnMouseWheel = function(self, delta)
            local code = self.__attrs._onmousewheel
            if type(code) == "string" then stub.RunSnippet(self, code, { delta = delta }) end
        end
    end,
    SecureHandlerStateTemplate = function(f)
        f.__protected = true
        function f:SetFrameRef(label, ref) self.__attrs["frameref-" .. label] = ref end
        function f:Execute(code) stub.RunSnippet(self, code) end
    end,
}

-- Key bindings: stub.bindings[command] = { key, ... }. Override bindings are kept
-- by key in stub.overrides and are protected in combat, like the client.
_G.GetBindingKey = function(cmd)
    local keys = stub.bindings[cmd]
    if keys then return unpack(keys) end
end
-- The command bound to a key ("BUTTON4", "SHIFT-BUTTON4"), or "" when none.
_G.GetBindingAction = function(key)
    for cmd, keys in pairs(stub.bindings) do
        for _, k in ipairs(keys) do if k == key then return cmd end end
    end
    return ""
end
_G.GetBindingText = function(key) return key end
_G.GetCurrentBindingSet = function() return 1 end
_G.SaveBindings = function() end
_G.SetOverrideBindingClick = function(owner, _, key, name, button)
    blockedInCombat("SetOverrideBindingClick")
    stub.overrides[key] = { owner = owner, click = name, button = button }
end
_G.SetOverrideBinding = function(owner, _, key, cmd)
    blockedInCombat("SetOverrideBinding")
    if cmd == nil then   -- nil clears this owner's binding on the key
        local o = stub.overrides[key]
        if o and o.owner == owner then stub.overrides[key] = nil end
        return
    end
    stub.overrides[key] = { owner = owner, command = cmd }
end
-- A key press by the player. Its override binding goes first, as in the client
-- (a click binding clicks the named button as a hardware event, with its secure
-- part untainted). Otherwise the command's own function from stub.commands runs.
function stub.PressKey(key)
    local o = stub.overrides[key]
    if o and o.click then
        local b = _G[o.click]
        assert(type(b) == "table", "no button " .. tostring(o.click))
        b:Click(o.button or "LeftButton")
        return
    end
    local cmd = (o and o.command) or GetBindingAction(key)
    local fn = stub.commands and stub.commands[cmd]
    if fn then stub.Key(fn) end
end
_G.ClearOverrideBindings = function(owner)
    blockedInCombat("ClearOverrideBindings")
    for k, v in pairs(stub.overrides) do if v.owner == owner then stub.overrides[k] = nil end end
end
_G.IsKeyDown = function(k) return stub.keysDown[k] == true end
-- The game's unit watch is an attribute on its protected manager
-- (SecureStateDriver.lua), so it's blocked in combat like any protected change.
-- With asState the manager only sets "state-unitexists" (true/false, only on a
-- change) instead of showing and hiding the frame. Registering runs one check at
-- once, as the game does; stub.UnitWatch() stands in for the manager's later
-- checks (every 0.2 s and on unit events).
stub.unitWatchers = setmetatable({}, { __mode = "k" })
function stub.RunUnitWatch(f)
    local unit = f:GetAttribute("unit")
    local exists = type(unit) == "string" and (UnitExists(unit) or UnitIsVisible(unit)) and true or false
    stub.inSecure = (stub.inSecure or 0) + 1
    local ok, err = pcall(function()
        if f.__unitWatch == "state" then
            if f:GetAttribute("state-unitexists") ~= exists then f:SetAttribute("state-unitexists", exists) end
        elseif exists then
            f:Show(); f:SetAttribute("statehidden", nil)
        else
            f:Hide(); f:SetAttribute("statehidden", true)
        end
    end)
    stub.inSecure = stub.inSecure - 1
    if not ok then error(err, 0) end
end
function stub.UnitWatch()
    for f in pairs(stub.unitWatchers) do
        if f.__unitWatch then stub.RunUnitWatch(f) end
    end
end
_G.RegisterUnitWatch = function(f, asState)
    blockedInCombat("RegisterUnitWatch")
    f.__unitWatch = asState and "state" or true
    stub.unitWatchers[f] = true
    if asState then stub.RunUnitWatch(f) end
end
_G.UnregisterUnitWatch = function(f) blockedInCombat("UnregisterUnitWatch"); f.__unitWatch = false end
-- From SecureHandlers.lua: a frame ref for a header's snippets, and running a
-- snippet on a header now. Both are protected changes, so out of combat only.
_G.SecureHandlerSetFrameRef = function(frame, label, ref)
    blockedInCombat("SecureHandlerSetFrameRef")
    assert(type(frame) == "table" and frame.__protected, "SecureHandlerSetFrameRef: a secure header")
    frame.__attrs["frameref-" .. label] = ref
end
_G.SecureHandlerExecute = function(frame, body)
    blockedInCombat("SecureHandlerExecute")
    assert(type(frame) == "table" and frame.__protected, "SecureHandlerExecute: a secure header")
    stub.RunSnippet(frame, body)
end
-- SecureHandlers.lua: a header's snippet runs before the frame's own script, in
-- the restricted environment (self is a handle). OnAttributeChanged skips names
-- starting with "_" (Wrapped_Attribute). Wrapping is a protected change.
_G.SecureHandlerWrapScript = function(frame, script, header, preBody)
    blockedInCombat("SecureHandlerWrapScript")
    assert(type(header) == "table" and header.__protected, "SecureHandlerWrapScript: a secure header")
    local old = frame.__scripts[script]
    frame.__scripts[script] = function(self, ...)
        if script == "OnAttributeChanged" then
            local name, value = ...
            if type(preBody) == "string" and not tostring(name):match("^_") then
                stub.RunSnippet(self, preBody, { name = name, value = value })
            end
        elseif type(preBody) == "string" then
            stub.RunSnippet(self, preBody)
        end
        if old then return old(self, ...) end
    end
end
_G.C_AddOns = {
    -- An addon's .toc fields (stub.addonMeta[addon][field], e.g. a plugin's Title
    -- or Author). "test" for anything else.
    GetAddOnMetadata = function(n, f)
        local m = stub.addonMeta[n]
        if m then return m[f] end
        return "test"
    end,
    IsAddOnLoaded = function(n) return stub.loadedAddOns[n] == true end,
    LoadAddOn = function() end,
    DoesAddOnExist = function(n) return stub.installedAddOns[n] == true end,
    -- Switched on or off by name for one character ("*" for every character), as
    -- the AddOns list keeps it; otherwise on when loaded. The character is its
    -- GUID: the game's own AddOns list passes GetAddonCharacter(), which is
    -- UnitGUID("player"), and nothing else.
    -- A character's name matches no character. Switching by name changed nothing
    -- for a player (keeping Baganator left Daylight UI's bags on), so here it
    -- changes nothing and reads every character's state. That part is a guess
    -- from the report.
    EnableAddOn = function(n, who)
        if who ~= nil and who ~= UnitGUID("player") then return end
        stub.addonState[n] = stub.addonState[n] or {}
        stub.addonState[n][who or "*"] = true
    end,
    DisableAddOn = function(n, who)
        if who ~= nil and who ~= UnitGUID("player") then return end
        stub.addonState[n] = stub.addonState[n] or {}
        stub.addonState[n][who or "*"] = false
    end,
    GetAddOnEnableState = function(n, who)
        if who ~= nil and who ~= UnitGUID("player") then who = nil end
        local s = stub.addonState[n]
        local on = s and s[who or "*"]
        if on == nil and s then on = s["*"] end
        if on == nil then on = stub.loadedAddOns[n] == true end
        return on and 2 or 0
    end,
}
_G.SetPortraitTexture = function(tex, unit) tex.__portraitUnit = unit end
_G.UnitIsUnit = function(a, b)
    local x, y = U(a), U(b)
    return a == b or (x ~= nil and x == y)
end
_G.UnitInParty = function(u) local x = U(u); return x ~= nil and x.party == true end
_G.UnitInRaid = function(u) local x = U(u); if x and x.raid then return 1 end return nil end
_G.UnitIsFriend = function(_, u) local x = U(u); if x then return x.friend == true end return false end
-- Within the game's sight range. A unit's visible = false says it isn't.
_G.UnitIsVisible = function(u)
    local x = U(u)
    if x then return x.visible ~= false end
    return u == "player"
end
_G.UnitInRange = function(u)
    local x = U(u)
    if x and x.inRange ~= nil then return x.inRange, true end
    return false, false
end
-- Spells the player knows (stub.knownSpells[id] = true) and each unit's answer
-- to a spell's range check: x.spellRange (true/false/secret). nil means the check
-- is invalid, which is what the game answers for strangers and enemies.
stub.knownSpells = {}
_G.C_SpellBook = _G.C_SpellBook or {}
C_SpellBook.IsSpellKnown = function(id) return stub.knownSpells[id] == true end
_G.C_Spell = _G.C_Spell or {}
-- stub.spells[id] = { name, desc } is what C_Spell says about a spell.
C_Spell.GetSpellDescription = function(id) local s = stub.spells and stub.spells[id]; return s and s.desc or "" end
-- stub.spells[id].rank is the game's rank text ("Rank 3"), nil for a spell with no ranks.
C_Spell.GetSpellSubtext = function(id) local s = stub.spells and stub.spells[id]; return s and s.rank end
C_Spell.PickupSpell = function(id) stub.cursor = { "spell", id } end
C_Spell.IsSpellInRange = function(id, u)
    local x = U(u)
    if not stub.knownSpells[id] or not x then return nil end
    return x.spellRange
end
_G.UnitIsPVP = function(u) local x = U(u); return x ~= nil and x.pvp == true end
_G.UnitFactionGroup = function(u) local x = U(u); if x then return x.faction end end
_G.UnitIsGroupLeader = function(u)
    local x = U(u)
    if x and isSecret(x.leader) then return x.leader end
    return x ~= nil and x.leader == true
end
_G.UnitLevel = function(u) local x = U(u); return x and x.level end
_G.UnitGroupRolesAssigned = function(u) local x = U(u); return (x and x.role) or "NONE" end
-- Texture coords for each role's circle on the client's own sheet. The numbers
-- don't matter here, only that a known role returns some.
local ROLE_COORDS = { TANK = { 0, 0.25, 0, 0.25 }, HEALER = { 0.25, 0.5, 0, 0.25 }, DAMAGE = { 0.5, 0.75, 0, 0.25 } }
_G.GetTexCoordsForRoleSmallCircle = function(role) return unpack(ROLE_COORDS[role] or ROLE_COORDS.DAMAGE) end
_G.IsResting = function() return stub.resting == true end
_G.IsInGroup = function() return stub.inGroup == true end
_G.UnitIsGroupAssistant = function(u)
    local x = U(u)
    if x and isSecret(x.assist) then return x.assist end
    return x ~= nil and x.assist == true
end
_G.IsEveryoneAssistant = function() return stub.everyoneAssist == true end
-- A ready check answer: a unit's own ready = "ready" | "notready" | "waiting".
_G.GetReadyCheckStatus = function(u) local x = U(u); return x and x.ready end
_G.HasLFGRestrictions = function() return stub.lfgGroup == true end
_G.UnitInBattleground = function(u) if u == "player" and stub.inBattleground then return 1 end end
-- Group calls the game marks HasRestrictions do nothing for addon code in a fight
-- or under the client's restrictions. Each call that ran is logged in
-- stub.groupCalls as "Name(args)".
stub.groupCalls = {}
local function groupCall(name, run)
    return function(...)
        if stub.combat or next(stub.restrictions or {}) then
            stub.errors[#stub.errors + 1] = "ADDON_ACTION_BLOCKED: " .. name
            return false
        end
        local args = {}
        for i = 1, select("#", ...) do args[i] = tostring((select(i, ...))) end
        stub.groupCalls[#stub.groupCalls + 1] = name .. "(" .. table.concat(args, ",") .. ")"
        if run then run(...) end
        return true
    end
end
_G.C_PartyInfo = _G.C_PartyInfo or {}
C_PartyInfo.DoReadyCheck = groupCall("DoReadyCheck")
C_PartyInfo.DoCountdown = groupCall("DoCountdown")
C_PartyInfo.SetEveryoneIsAssistant = groupCall("SetEveryoneIsAssistant", function(on) stub.everyoneAssist = on == true end)
_G.InitiateRolePoll = groupCall("InitiateRolePoll")
_G.IsMounted = function() return stub.mounted == true end
-- The camera distance in yards (GetCameraZoom, undocumented but in the game's C
-- API), the player's race and shapeshift form (nil = none). Tests set
-- stub.cameraZoom, stub.race and stub.formID.
_G.GetCameraZoom = function() return stub.cameraZoom or 15 end
_G.UnitRace = function(u)
    if u ~= "player" then return nil end
    local race = stub.race or "Human"
    return race, race, 1
end
_G.GetShapeshiftFormID = function() return stub.formID end
-- The camera's own calls. The zoom keys and mouse wheel run MoveViewIn/OutStart
-- (Blizzard_FrameXML/Bindings_Camelot.xml).
for _, n in ipairs({ "CameraZoomIn", "CameraZoomOut", "MoveViewInStart", "MoveViewOutStart", "SetView", "ResetView" }) do
    _G[n] = function() end
end
-- How hard a unit is, both of the game's ways (DifficultyUtil.lua and TargetFrame.lua).
-- The target frame asks the server (C_PlayerInfo.GetContentDifficultyCreatureForPlayer,
-- Enum.RelativeContentDifficulty 0 trivial .. 4 impossible) and paints
-- GetDifficultyColor of the answer. Here the server answers a unit's `.difficulty`,
-- else classic's con colors by level: red 5 over you, orange 3, yellow 2 under,
-- grey past classic's grey level. That last part is a guess at the server, which
-- showed green for a level 36 mob to a level 42 player.
-- GetCreatureDifficultyColor(level) uses retail's level math: grey past
-- UnitQuestTrivialLevelRange (stub.trivialRange, 5, where that 36 went grey).
_G.QuestDifficultyColors = {
    trivial = { r = 0.5, g = 0.5, b = 0.5 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
    difficult = { r = 1, g = 0.82, b = 0 }, verydifficult = { r = 1, g = 0.5, b = 0.25 },
    impossible = { r = 1, g = 0.1, b = 0.1 },
}
stub.trivialRange = 5
local DIFFICULTY_KEYS = { [0] = "trivial", "standard", "difficult", "verydifficult", "impossible" }
_G.GetDifficultyColor = function(d) return QuestDifficultyColors[DIFFICULTY_KEYS[d] or "difficult"] end
_G.UnitQuestTrivialLevelRange = function() return stub.trivialRange end
local function playerLevel() return UnitLevel("player") or 60 end
_G.GetCreatureDifficultyColor = function(level)
    local diff = level - playerLevel()
    if diff >= 5 then return QuestDifficultyColors.impossible end
    if diff >= 3 then return QuestDifficultyColors.verydifficult end
    if diff >= -4 then return QuestDifficultyColors.difficult end
    if -diff <= stub.trivialRange then return QuestDifficultyColors.standard end
    return QuestDifficultyColors.trivial
end
local function classicGrey(p)
    if p <= 5 then return 0 elseif p <= 39 then return p - math.floor(p / 10) - 5 end
    return p - math.floor(p / 5) - 1
end
_G.C_PlayerInfo = _G.C_PlayerInfo or {}
C_PlayerInfo.GetContentDifficultyCreatureForPlayer = function(unit)
    if issecretvalue and issecretvalue(unit) then error("bad argument: secret unit token", 2) end
    local x = U(unit)
    if x and x.difficulty then return x.difficulty end
    local level, p = UnitLevel(unit), playerLevel()
    if type(level) ~= "number" or level < 1 then return 4 end
    local diff = level - p
    if diff >= 5 then return 4 elseif diff >= 3 then return 3 elseif diff >= -2 then return 2 end
    if level > classicGrey(p) then return 1 end
    return 0
end
_G.UnitAffectingCombat = function(u) local x = U(u); return x ~= nil and x.combat == true end
-- Threat. A mob's list: stub.units[mob].threatList = { [unit] = { status,
-- scaled, raw, value } } (tanking is status 2 or 3). Without a list, the short
-- form applies: the mob's own .threat is your status on it, and a unit's .threat
-- with no mob is its highest on anything.
local function threatEntry(u, mob)
    local m = U(mob)
    return m and type(m.threatList) == "table" and m.threatList[u] or nil
end
_G.UnitIsAFK = function(u) local x = U(u); return x ~= nil and x.afk == true end   -- secret in chat lockdown, per the docs
_G.UnitIsDND = function(u) local x = U(u); return x ~= nil and x.dnd == true end   -- same
-- The raid roster by index: a unit "raidN" whose subgroup is its group (name, rank, subgroup, ...).
_G.GetRaidRosterInfo = function(i)
    local x = U("raid" .. tostring(i))
    if not x then return nil end
    return x.name, 0, x.subgroup or 1
end
_G.GetGuildInfo = function(u) local x = U(u); return x and x.guild end
_G.UnitThreatSituation = function(u, mob)
    local x = U(u)
    if not mob then return x and x.threat end
    local e = threatEntry(u, mob)
    if e then return e.status end
    local m = U(mob)
    if m and u == "player" then return m.threat end
end
_G.UnitDetailedThreatSituation = function(u, mob)
    local e = threatEntry(u, mob)
    if e then return e.status >= 2, e.status, e.scaled, e.raw, e.value end
    local x = U(mob)
    if x and x.threat ~= nil and (u == "player" or not x.threatList) then return x.threat >= 2, x.threat end
end
_G.C_Secrets = _G.C_Secrets or {}
C_Secrets.ShouldUnitThreatValuesBeSecret = function(u, mob) return stub.ThreatSecret("threatValues", u, mob) end
C_Secrets.ShouldUnitThreatStateBeSecret = function(u, mob) return stub.ThreatSecret("threatState", u, mob) end
_G.UnitGetIncomingHeals = function(u) local x = U(u); return x and x.incoming end
_G.UnitGetTotalAbsorbs = function(u) local x = U(u); return x and x.absorbs end
_G.UnitIsDead = function(u) local x = U(u); if x then return x.dead == true end return false end
-- The engine keeps a plate on a corpse you can loot (the loot sparkle and the
-- interact icon need one). The game's plate then shows only its widgets
-- (UpdateWidgetsOnlyMode in Blizzard_NamePlateUnitFrame, read at SetUnit).
_G.UnitNameplateShowsWidgetsOnly = function(u) local x = U(u); return x ~= nil and x.widgetsOnly == true end
_G.UnitIsGhost = function(u) local x = U(u); if x then return x.ghost == true end return false end
_G.UnitIsConnected = function(u) local x = U(u); if x and x.offline ~= nil then return not x.offline end return true end
-- Reset takes every hook off again, newest first. A hook left on a global kept
-- that whole loaded world alive (75 MB per Load, all walked by the garbage
-- collector) and ran for every world before it.
local hooks = {}
_G.hooksecurefunc = function(tbl, name, fn)
    if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
    local orig = tbl[name]
    local hook = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
    hooks[#hooks + 1] = { tbl = tbl, name = name, raw = rawget(tbl, name), hook = hook }
    tbl[name] = hook
end
local function unhookAll()
    for i = #hooks, 1, -1 do
        local h = hooks[i]
        -- A test that swapped in its own function after the hook keeps it.
        if rawget(h.tbl, h.name) == h.hook then rawset(h.tbl, h.name, h.raw) end
        hooks[i] = nil
    end
end

-- ---------------------------------------------------------------------
-- Buffs: the player's auras, weapon enchants, time, and the small client
-- helpers the buff bars use.
-- ---------------------------------------------------------------------

local wallClock, upClock = 1700000000, 1000.0
function stub.SetTime(wall, up)
    wallClock = wall or wallClock
    upClock = up or upClock
end
function stub.Advance(seconds)
    wallClock = wallClock + seconds
    upClock = upClock + seconds
end
_G.time = function() return wallClock end
_G.GetTime = function() return upClock end
_G.date = function(fmt, t) return os.date(fmt, t or wallClock) end
-- The server's clock, set apart from wallClock (the local clock) so tests can
-- tell them apart.
_G.GetGameTime = function() return (stub.gameTime or {})[1] or 0, (stub.gameTime or {})[2] or 0 end
function stub.SetGameTime(h, m) stub.gameTime = { h, m } end
_G.strtrim = function(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
_G.Mixin = function(obj, ...)
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do obj[k] = v end
    end
    return obj
end
_G.IsInRaid = function() return stub.inRaid == true end
-- Players in the group, you included (0 when alone), as set by stub.SetGroup.
_G.GetNumGroupMembers = function() return stub.groupSize or 0 end
function stub.SetGroup(inGroup, inRaid, count)
    stub.inGroup = inGroup and true or false
    stub.inRaid = inRaid and true or false
    stub.groupSize = count
end
function stub.SetUnits(units) stub.units = units end
stub.MakeSecret = stub.Secret
_G.GetCursorPosition = function() return stub.cursorPos[1], stub.cursorPos[2] end

-- Chat bubbles: a plain list of frames handed out by stub.SetBubbles. Mark one
-- forbidden with __forbidden = true, as in an instance.
_G.C_ChatBubbles = { GetAllChatBubbles = function() return stub.bubbles or {} end }
function stub.SetBubbles(list) stub.bubbles = list end

-- stub.SetAuras("player", "HELPFUL", { { name=, icon=, spellId=, expirationTime=, ... }, ... }).
-- Each read hands out a fresh copy, as the client does.
function stub.SetAuras(unit, filter, list)
    stub.auras[unit] = stub.auras[unit] or {}
    stub.auras[unit][filter] = list
end
stub.privateAnchors, stub.privateAnchorSeq = {}, 0
_G.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        if stub.auraReadsThrow then error("Auras cannot be accessed when secret while tainted") end
        local list = stub.auras[unit] and stub.auras[unit][filter]
        local a = list and list[index]
        if not a then return nil end
        local out = {}
        for k, v in pairs(a) do out[k] = v end
        if out.auraInstanceID == nil then out.auraInstanceID = index end
        if out.applications == nil then out.applications = 0 end
        if out.duration == nil then out.duration = 0 end
        if out.expirationTime == nil then out.expirationTime = 0 end
        return out
    end,
    -- The first aura on the unit with that spell id (helpful, then harmful), or
    -- nil. While auras are secret it quietly returns nothing, like the client
    -- (RequiresNonSecretAura).
    GetUnitAuraBySpellID = function(unit, spellID)
        if stub.AurasRestricted() then return nil end
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            local list = stub.auras[unit] and stub.auras[unit][filter]
            for _, a in ipairs(list or {}) do
                if a.spellId == spellID then
                    local out = {}
                    for k, v in pairs(a) do out[k] = v end
                    return out
                end
            end
        end
        return nil
    end,
    -- Private auras (boss debuffs): the client draws them on a frame the addon
    -- lends it. Checked against AddPrivateAuraAnchorArgs and PrivateAuraIconInfo
    -- (UnitConstantsDocumentation). Added and removed out of combat only.
    -- Container mode needs the game's own secure handshake, so it's refused.
    AddPrivateAuraAnchor = function(a)
        if stub.combat then error("AddPrivateAuraAnchor: not in combat (addon code)") end
        if type(a) ~= "table" then error("bad argument #1 to 'AddPrivateAuraAnchor' (table expected)") end
        if type(a.unitToken) ~= "string" then error("AddPrivateAuraAnchor: unitToken must be a string") end
        if type(a.auraIndex) ~= "number" then error("AddPrivateAuraAnchor: auraIndex must be a number") end
        if type(a.parent) ~= "table" or type(a.parent.GetObjectType) ~= "function" then
            error("AddPrivateAuraAnchor: parent must be a frame")
        end
        if a.isContainer == true then error("AddPrivateAuraAnchor: container anchors are the game's own") end
        local info = a.iconInfo
        if info ~= nil then
            if type(info) ~= "table" or type(info.iconAnchor) ~= "table" or type(info.iconWidth) ~= "number"
               or type(info.iconHeight) ~= "number" then
                error("AddPrivateAuraAnchor: iconInfo needs iconAnchor, iconWidth, iconHeight")
            end
            if type(info.iconAnchor.point) ~= "string" or type(info.iconAnchor.relativeTo) ~= "table" then
                error("AddPrivateAuraAnchor: iconAnchor needs point and relativeTo")
            end
        end
        stub.privateAnchorSeq = stub.privateAnchorSeq + 1
        stub.privateAnchors[stub.privateAnchorSeq] = a
        return stub.privateAnchorSeq
    end,
    RemovePrivateAuraAnchor = function(id)
        if stub.combat then error("RemovePrivateAuraAnchor: not in combat (addon code)") end
        if type(id) ~= "number" then error("bad argument #1 to 'RemovePrivateAuraAnchor' (number expected)") end
        stub.privateAnchors[id] = nil
    end,
    AuraIsPrivate = function() return false end,
}
-- The private aura anchors held now, { args, ... }, for unit (all if nil).
function stub.PrivateAnchors(unit)
    local out = {}
    for _, a in pairs(stub.privateAnchors) do
        if unit == nil or a.unitToken == unit then out[#out + 1] = a end
    end
    return out
end
-- The client's own answer to "are auras secret now?" (SecretPredicateAPI): yes in
-- combat and under any restriction except chat lockdown.
_G.C_Secrets = _G.C_Secrets or {}
C_Secrets.ShouldAurasBeSecret = function() return stub.AurasRestricted() end
-- A spell's aura secrecy (SecretWrapperConstants). Only the ids a test lists in
-- stub.neverSecretAuras are never secret, the rest are contextual. The client's
-- aura containers only let a debuff on a friend be picked by spell id when it's
-- never secret (AuraContainerUtil.CanApplyIdentityCandidateFilters, copied in
-- tests/aura_rules.lua).
_G.Enum.SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 }
stub.neverSecretAuras = {}
C_Secrets.GetSpellAuraSecrecy = function(sid)
    if issecretvalue and issecretvalue(sid) then error("GetSpellAuraSecrecy: secret argument") end
    return stub.neverSecretAuras[sid] and Enum.SecrecyLevel.NeverSecret or Enum.SecrecyLevel.ContextuallySecret
end
_G.Enum.StartTimerType = { PvPBeginTimer = 0, ChallengeModeCountdown = 1, PlayerCountdown = 2, PlunderstormCountdown = 3 }
_G.Enum.WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }
_G.Enum.PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 }
function stub.SetWeaponEnchants(list) stub.weaponEnchants = list or {} end
_G.C_Item = {
    -- The item onto the cursor, as the game's PickupItem does.
    PickupItem = function(item) stub.cursor = { "item", item } end,
    GetWeaponEnchantInfo = function(slotID)
        local out = {}
        for _, e in ipairs(stub.weaponEnchants) do
            if e.slot == slotID then
                out[#out + 1] = { hasEnchant = true, timeLeft = e.timeLeft, charges = e.charges or 0,
                    enchantType = e.enchantType or 2, enchantIconID = e.enchantIconID, enchantID = e.enchantID or 19 }
            end
        end
        return out
    end,
}
-- The one temporary enchant on an inventory slot, or nothing: oils, stones,
-- poisons (enchantType Temporary, 2). WoW Forever's shaman imbues (Imbue, 3)
-- aren't included. The aura container's weapon slots read this
-- (Blizzard_AuraContainerEnchantments.lua). An entry with `temporary = true` is
-- included whatever its enchantType: on Forever, rogue poisons show both in the
-- container's slot and as a non-Temporary enchant in GetWeaponEnchantInfo, so
-- they were seen twice in game.
local INV_TO_WEAPON = { [16] = 0, [17] = 1, [18] = 2 }
-- The coin icon for an amount (C_CurrencyInfo.GetCoinIcon; this client has no
-- global GetCoinIcon): gold from 1 gold, silver from 1 silver, else copper.
stub.COIN_ICONS = { gold = 133784, silver = 133786, copper = 133788 }
_G.C_CurrencyInfo = _G.C_CurrencyInfo or {}
C_CurrencyInfo.GetCoinIcon = function(amount)
    assert(type(amount) == "number", "bad argument #1 to 'GetCoinIcon'")
    if amount >= 10000 then return stub.COIN_ICONS.gold end
    if amount >= 100 then return stub.COIN_ICONS.silver end
    return stub.COIN_ICONS.copper
end
_G.C_PaperDollInfo = _G.C_PaperDollInfo or {}
C_PaperDollInfo.GetTemporaryEnchantmentInfo = function(inv)
    for _, e in ipairs(stub.weaponEnchants or {}) do
        if e.slot == INV_TO_WEAPON[inv] and (e.temporary or (e.enchantType or 2) == 2) then
            return { enchantID = e.enchantID or 19, hasExpirationTime = true, remainingTimeMs = e.timeLeft,
                chargesRemaining = e.charges or 0 }
        end
    end
end
_G.GetInventoryItemTexture = function(_, slot) return "tex:" .. tostring(slot) end

-- ---------------------------------------------------------------------
-- Reset and load
-- ---------------------------------------------------------------------

-- The game's range and usable watchers. Each runs the game's own button code on
-- every frame it holds (ActionBarButtonRangeCheckFrameMixin).
local function watcher(name, range)
    local w = CreateFrame("Frame", name)
    w.actions = {}
    function w:RegisterFrame(a, f)
        self.actions[a] = self.actions[a] or {}
        if self.actions[a][f] then return end
        self.actions[a][f] = f
        if range then C_ActionBar.EnableActionRangeCheck(a, true) end
    end
    function w:UnregisterFrame(a, f)
        if not (self.actions[a] and self.actions[a][f]) then return end
        self.actions[a][f] = nil
        if range then C_ActionBar.EnableActionRangeCheck(a, false) end
    end
    _G[name] = w
end

-- The game's action slot API (HasAction ... C_SpellActivationOverlay). Worlds call
-- it again to replace the simpler versions world() sets.
function stub.ActionSlots(slots)
    -- Action slots: stub.slots[slot] = { texture, count, text, usable (false:
    -- can't be used now), noMana, current, autorepeat, attack, equipped,
    -- cooldown, gcd (the cooldown is only the GCD), charges, loc, locReplaces,
    -- inRange, flyout, spellID, macro, item }. In combat, counts and cooldown
    -- times come back secret and isOnGCD is missing, as in the client.
    -- stub.spellCooldowns[spellID] = "gcd" or "real" for C_Spell.
    stub.slots = slots or { [2] = { texture = "tex2", spellID = 2 }, [3] = { texture = "tex3", spellID = 3 } }
    stub.overlay, stub.rangeChecks, stub.macroSpells, stub.spellCooldowns = {}, {}, {}, {}
    local function S(slot) return stub.slots[slot] end
    -- stub.secretTimes makes them secret even outside lockdown, as when a /reload
    -- in a fight loads the files before combat lockdown comes back.
    local function secret(v) if stub.combat or stub.secretTimes then return stub.Secret(v) end return v end
    local function duration(slot, kind) return { slot = slot, kind = kind } end
    _G.HasAction = function(slot) return S(slot) ~= nil end
    _G.GetActionTexture = function(slot) local s = S(slot); return s and s.texture end
    _G.GetActionText = function(slot) local s = S(slot); return s and s.text end
    _G.IsCurrentAction = function(slot) local s = S(slot); return s ~= nil and s.current == true end
    _G.IsAutoRepeatAction = function(slot) local s = S(slot); return s ~= nil and s.autorepeat == true end
    _G.IsAttackAction = function(slot) local s = S(slot); return s ~= nil and s.attack == true end
    _G.IsEquippedAction = function(slot) local s = S(slot); return s ~= nil and s.equipped == true end
    _G.IsUsableAction = function(slot)
        local s = S(slot)
        if not s then return false, false end
        return s.usable ~= false and not s.noMana, s.noMana == true
    end
    _G.IsActionInRange = function(slot) local s = S(slot); if s then return s.inRange end end
    _G.GetActionInfo = function(slot)
        local s = S(slot)
        if not s then return nil end
        if s.flyout then return "flyout", s.flyout end
        if s.macro then return "macro", s.macro end
        if s.item then return "item", s.item end
        return "spell", s.spellID
    end
    _G.GetMacroSpell = function(i) return stub.macroSpells[i] end
    -- The game's PlaceAction: what the cursor holds goes into the slot and what
    -- the slot held goes onto the cursor.
    _G.PlaceAction = function(slot)
        local held, old = stub.cursor, stub.slots[slot]
        if not held then return end
        if held[1] == "spell" then
            stub.slots[slot] = { texture = "tex" .. held[2], spellID = held[2] }
        elseif held[1] == "item" then
            stub.slots[slot] = { texture = "tex" .. held[2], item = held[2] }
        else
            stub.slots[slot] = nil
        end
        stub.cursor = old and old.spellID and { "spell", old.spellID } or nil
    end
    _G.C_ActionBar = {
    -- The game's button Update calls these, not the old globals.
        HasAction = HasAction,
        GetActionTexture = GetActionTexture,
        IsAttackAction = IsAttackAction,
        IsCurrentAction = IsCurrentAction,
        IsAutoRepeatAction = IsAutoRepeatAction,
        GetActionDisplayCount = function(slot)
            local s = S(slot)
            if s and s.count then return secret(tostring(s.count)) end
            return ""
        end,
        GetActionCooldown = function(slot)
            local s = S(slot)
            return { isActive = s ~= nil and s.cooldown == true, isEnabled = true, startTime = secret(100), duration = secret(10),
                     isOnGCD = (not stub.combat and s ~= nil and s.gcd == true) or nil }
        end,
        GetActionCooldownDuration = function(slot) return duration(slot, "cooldown") end,
        GetActionCharges = function(slot)
            local s = S(slot)
            return { isActive = s ~= nil and s.charges == true, currentCharges = secret(1), maxCharges = secret(2) }
        end,
        GetActionChargeDuration = function(slot) return duration(slot, "charges") end,
        GetActionLossOfControlCooldownInfo = function(slot)
            local s = S(slot)
            return { isActive = s ~= nil and s.loc == true, shouldReplaceNormalCooldown = s ~= nil and s.locReplaces == true,
                     startTime = secret(1) }
        end,
        GetActionLossOfControlCooldownDuration = function(slot) return duration(slot, "loc") end,
        EnableActionRangeCheck = function(slot, on) stub.rangeChecks[slot] = on end,
    }
    -- A GCD gives a plain isOnGCD = true. A real cooldown leaves it out.
    _G.C_Spell = _G.C_Spell or {}
    C_Spell.GetSpellCooldown = function(id)
        local k = stub.spellCooldowns[id]
        return { isActive = k ~= nil, isOnGCD = (k == "gcd") or nil, isEnabled = true,
                 startTime = secret(100), duration = secret(10) }
    end
    _G.C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return stub.overlay[id] == true end }
end

-- Globals Reset clears (the addon under test and its saved variables). Another addon that copies this file changes the list.
stub.RESET_GLOBALS = { "DaylightUIDB", "DaylightUI", "SLASH_DAYLIGHTUI1" }
-- stub.feelOwner is the table whose .Win.Feel FinishFade settles (nil = DaylightUI).
stub.feelOwner = nil
-- loadFiles(dir, files, addonName, ns, after) loads an addon's files like the client (defined below).

function stub.Reset()
    unhookAll()
    for _, n in ipairs(named) do _G[n] = nil end
    for i = #frames, 1, -1 do frames[i] = nil end
    kids, byEvent = {}, {}
    for i = #named, 1, -1 do named[i] = nil end
    for i = #timers, 1, -1 do timers[i] = nil end
    stub.tickers = {}
    stub.ResetTimers()
    stub.chat, stub.errors = {}, {}
    stub.units, stub.loadedAddOns, stub.unknownEvents = {}, {}, {}
    stub.spells = {}
    stub.installedAddOns = {}
    stub.addonMeta = {}
    stub.addonState = {}
    stub.combat, stub.noAuraContainer = false, false
    stub.privateAnchors, stub.privateAnchorSeq = {}, 0
    stub.refuseAuraFilters = nil
    stub.restrictions, stub.inRestrictionDispatch = {}, false
    stub.lockErrors, stub.lockSites = 0, {}
    stub.secure, stub.inSecure = false, 0
    stub.conditions, stub.drivers, stub.frozenGroup = {}, {}, nil
    stub.TEMPLATES = {}
    for k, v in pairs(BASE_TEMPLATES) do stub.TEMPLATES[k] = v end
    stub.bindings, stub.overrides, stub.keysDown = {}, {}, {}
    -- The game's action button parts: its two event frames, the key handlers
    -- Bindings.xml calls (the addon hooks them), and the page indexes.
    stub.quickClicks, stub.forms = {}, 0
    stub.secretTimes, stub.gameButtonsLoaded = false, false
    _G.ActionBarButtonEventsFrame = new("Frame", "ActionBarButtonEventsFrame")
    ActionBarButtonEventsFrame.frames = {}
    ActionBarButtonEventsFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    _G.ActionBarActionEventsFrame = new("Frame", "ActionBarActionEventsFrame")
    ActionBarActionEventsFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    watcher("ActionBarButtonRangeCheckFrame", true)
    watcher("ActionBarButtonUsableWatcherFrame", false)
    _G.ActionButtonDown = function() end
    _G.ActionButtonUp = function() end
    _G.MultiActionButtonDown = function() end
    _G.MultiActionButtonUp = function() end
    _G.GetNumShapeshiftForms = function() return stub.forms or 0 end
    _G.GetOverrideBarIndex = function() return 33 end
    _G.GetVehicleBarIndex = function() return 31 end
    _G.GetTempShapeshiftBarIndex = function() return 32 end
    stub.ActionSlots({})
    stub.reloaded = nil
    _G.ReloadUI = function() stub.reloaded = true end
    stub.inGroup, stub.inRaid, stub.groupSize = false, false, nil
    -- Where the player is (stub.SetInstance). nil = the open world.
    stub.instance = nil
    _G.IsInInstance = function() local k = stub.instance or "none"; return k ~= "none", k end
    stub.auras, stub.weaponEnchants, stub.auraReadsThrow = {}, {}, false
    stub.cursorPos = { 0, 0 }
    stub.SetTime(1700000000, 1000.0)
    _G.GetTime = function() return upClock end   -- a test may have swapped it for its own
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(which, text, _, data) stub.popup = { which = which, text = text, data = data } end
    for _, name in ipairs(stub.RESET_GLOBALS) do _G[name] = nil end   -- the addon's own saved variables and globals
    _G.SlashCmdList, _G.UISpecialFrames = {}, {}
    _G.EditModeManagerFrame = nil
    _G.GameMenuFrame = nil
    -- The game's rule (UIParentPanelManager.lua) checks CheckProtectedFunctionsAllowed,
    -- so from addon code in combat it does nothing. The game's own code may.
    _G.HideUIPanel = function(f)
        if stub.combat and (stub.inSecure or 0) == 0 then return end
        if type(f) == "table" and f.Hide then f:Hide() end
    end
    _G.UIParent = new("Frame", "UIParent")
    stub.SetScreen(1920, 1080, 1)
    for _, n in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame" }) do
        local f = new("Frame", n, _G.UIParent)
        f.__protected = true
        f:RegisterEvent("UNIT_HEALTH")
    end
    for _, n in ipairs({ "PlayerCastingBarFrame", "PetCastingBarFrame" }) do
        local f = new("StatusBar", n, _G.UIParent)
        function f:SetUnit(u) self.__castUnit = u; self.__setUnitCalled = true end
        f:RegisterEvent("UNIT_SPELLCAST_START")
    end
    -- The swing timer API: speeds and the target's reach set by hand, the spells
    -- queued for the next swing, and the game's own swing bars.
    stub.swing = { speeds = { 2.6, 0, 0 }, inRange = {}, checks = {}, current = {},
                   names = { [78] = "Heroic Strike", [845] = "Cleave", [6807] = "Maul" } }
    _G.C_SwingTimer = {
        EnableRangeCheck = function(t, on) stub.swing.checks[t] = on end,
        IsTargetWithinSwingRange = function(t) return stub.swing.inRange[t] end,
    }
    _G.UnitAttackSpeed = function() local s = stub.swing.speeds; return s[1], s[2], s[3] end
    _G.C_Spell = _G.C_Spell or {}
    C_Spell.GetSpellName = function(id)
        return stub.swing.names[id] or (stub.spells and stub.spells[id] and stub.spells[id].name)
    end
    C_Spell.IsCurrentSpell = function(name) return stub.swing.current[name] == true end
    C_Spell.GetSpellPowerCost = function(id) return stub.spellCosts and stub.spellCosts[id] end
    for _, n in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
        new("Frame", n, _G.UIParent)
    end
    stub.marks = setmetatable({}, { __mode = "k" })
    if stub.realMethods == nil then
        local WidgetAPI = require("widget_api")
        if WidgetAPI.Load() > 0 then
            stub.realMethods = WidgetAPI.names
            -- SetCooldown keeps its own model since the game's cooldowns may take secrets.
            WidgetAPI.refusesSecrets.SetCooldown = nil
            stub.refusesSecrets = WidgetAPI.refusesSecrets
        end
    end
    stub.DamageMeter()
    stub.WrapSecrets()
end

-- The game's damage meter (C_DamageMeter) and death recap (C_DeathRecap), as
-- their docs describe them (tests/blizzard/api/DamageMeter*Documentation,
-- DeathRecapDocumentation). The recap's event fields follow Blizzard_DeathRecap:
-- newest first, the killing blow first. A test fills stub.meter:
--   sources   a list for every type, or [Enum.DamageMeterType.X] = list
--             each; fightSources[sessionID] the same for an earlier fight
--   fights    GetAvailableCombatSessions' list, oldest first
--   durations [sessionType] = seconds
--   spells    a source's combatSpells; recaps[id] = { events, maxHealth }
--   gone      a sessionID the game no longer has
-- and reads asked / askedSource / reset. Getters the docs mark SecretWhenInCombat
-- return secrets in a fight (stub.WrapSecrets), down into each source and spell
-- by their own NeverSecret flags.
function stub.DamageMeter()
    Enum.DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5,
                             Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 }
    Enum.DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 }
    -- A new list of fights is an event the game sends (when a session starts or
    -- a reset clears them), so setting stub.meter.fights fires it.
    local data = {}
    stub.meter = setmetatable({}, {
        __index = data,
        __newindex = function(_, k, v)
            data[k] = v
            if k == "fights" and stub.FireEvent then
                pcall(stub.FireEvent, "DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 0)
            end
        end,
    })
    -- One list for every type (its first entry is a source), or one per type,
    -- keyed by the type's value. Dps is 1, so key 1 holds a list.
    local function listFor(sources, kind)
        if type(sources) ~= "table" then return {} end
        local first = sources[1]
        if type(first) == "table" and next(first) ~= nil and first[1] == nil then return sources end
        return sources[kind] or sources.all or {}
    end
    -- A fresh copy each call, as the game hands out new tables.
    local function session(list, duration)
        local out, total, top = {}, 0, 0
        for i, s in ipairs(list) do
            local c = {}
            for k, v in pairs(s) do c[k] = v end
            -- Seen in game: secret even out of a fight, though the docs
            -- mark it NeverSecret.
            if type(c.specIconID) == "number" and not stub.plainSecrets then c.specIconID = stub.Secret(c.specIconID) end
            out[i] = c
            local a = type(s.totalAmount) == "number" and s.totalAmount or 0
            total = total + a
            if a > top then top = a end
        end
        return { combatSources = out, totalAmount = stub.meter.total or total, maxAmount = top,
                 durationSeconds = duration }
    end
    local function spells()
        local out, total, top = {}, 0, 0
        for i, s in ipairs(stub.meter.spells or {}) do
            local c = {}
            for k, v in pairs(s) do c[k] = v end
            out[i] = c
            local a = type(s.totalAmount) == "number" and s.totalAmount or 0
            total = total + a
            if a > top then top = a end
        end
        return { combatSpells = out, totalAmount = total, maxAmount = top }
    end
    _G.C_DamageMeter = {
        IsDamageMeterAvailable = function() return true, "" end,
        GetCombatSessionFromType = function(sessionType, kind)
            stub.meter.asked = { sessionType, kind }
            local d = stub.meter.durations and stub.meter.durations[sessionType]
            return session(listFor(stub.meter.sources, kind), d)
        end,
        GetCombatSessionFromID = function(id, kind)
            stub.meter.asked = { "id", id, kind }
            if id == stub.meter.gone then return nil end
            local per = stub.meter.fightSources and stub.meter.fightSources[id]
            local duration
            for _, f in ipairs(stub.meter.fights or {}) do
                if f.sessionID == id then duration = f.durationSeconds end
            end
            return session(listFor(per or stub.meter.sources, kind), duration)
        end,
        GetCombatSessionSourceFromType = function(sessionType, kind, guid, creature)
            stub.meter.askedSource = { sessionType, kind, guid, creature }
            return spells()
        end,
        GetCombatSessionSourceFromID = function(id, kind, guid, creature)
            stub.meter.askedSource = { "id", id, kind, guid }
            return spells()
        end,
        -- Oldest first, as the game lists them.
        GetAvailableCombatSessions = function() return stub.meter.fights or {} end,
        GetSessionDurationSeconds = function(sessionType)
            return stub.meter.durations and stub.meter.durations[sessionType]
        end,
        ResetAllCombatSessions = function() stub.meter.reset = true end,
    }
    local function recap(id) return stub.meter.recaps and stub.meter.recaps[id] end
    _G.C_DeathRecap = {
        HasRecapEvents = function(id) return recap(id) ~= nil end,
        GetRecapEvents = function(id) local r = recap(id); return r and r.events or {} end,
        GetRecapMaxHealth = function(id) local r = recap(id); return r and r.maxHealth or 0 end,
        GetRecapLink = function() return "" end,
    }
end

-- Every faked client function the game's docs mark secret (tests/secret_api.lua)
-- returns secrets while its condition holds: "restricted" in combat or under any
-- restriction except chat, "identity" in a PvP match or restricted map,
-- "combat", "chat". stub.plainSecrets = true turns it off for one test.
local secretWrapped = setmetatable({}, { __mode = "k" })
-- Identity: only an enemy unit's (stub.units[unit].enemy, or a hostile reaction),
-- since the client hides enemy players' class and name in a match.
local function secretWhen(when, unit, mob)
    if stub.plainSecrets then return false end
    if when == "always" then return true end
    local R = Enum.AddOnRestrictionType
    if when == "combat" then return stub.combat == true end
    if when == "chat" then return stub.restrictions[R.Chat] == true end
    if when == "threatValues" or when == "threatState" then return stub.ThreatSecret(when, unit, mob) end
    if when == "identity" then
        if not (stub.restrictions[R.PvPMatch] or stub.restrictions[R.Map]) then return false end
        local u = type(unit) == "string" and stub.units[unit]
        return type(u) == "table" and (u.enemy == true or (type(u.reaction) == "number" and u.reaction <= 3))
    end
    -- SecretWhenUnitSpellCastRestricted (game docs): only when the unit isn't
    -- the player or their pet.
    if when == "spellcast" then
        if unit == "player" or unit == "pet" then return false end
        return stub.AurasRestricted()
    end
    return stub.AurasRestricted()
end
-- Threat. Under restrictions (combat or any addon restriction) the numbers
-- (UnitDetailedThreatSituation, UnitThreatPercentageOfLead) are secret against a
-- boss (stub.units[mob].boss). The state (UnitThreatSituation) stays plain for
-- you, your pet and your group. C_Secrets' predicates answer the same.
local GROUP_TOKEN = { player = true, pet = true }
local function groupToken(u)
    return type(u) == "string" and (GROUP_TOKEN[u] or u:match("^party%d$") or u:match("^raid%d+$") or u:match("^partypet%d$")) and true or false
end
function stub.ThreatSecret(when, unit, mob)
    if stub.plainSecrets or not stub.AurasRestricted() then return false end
    if when == "threatValues" then
        local m = type(mob) == "string" and stub.units[mob]
        return type(m) == "table" and m.boss == true
    end
    return not groupToken(unit)
end
local secretValue
-- A field holding another of the docs' structures (a session's sources, a
-- source's spells) has its own fields go secret by that structure's flags.
local function secretNested(x, n)
    local keep = stub.secretStructs and stub.secretStructs[n.struct] or {}
    if not n.list then return secretValue(x, keep, n.struct) end
    local out = {}
    for i, e in pairs(x) do out[i] = type(e) == "table" and secretValue(e, keep, n.struct) or e end
    return out
end
secretValue = function(v, keep, struct)
    if v == nil or isSecret(v) then return v end
    if type(v) ~= "table" then return stub.Secret(v) end
    if getmetatable(v) == WidgetMT then return v end
    local nested = struct and stub.secretNested and stub.secretNested[struct]
    local out = {}
    -- Data fields go secret; methods (a duration object's) stay callable.
    for k, x in pairs(v) do
        local n = nested and nested[k]
        if n and type(x) == "table" then
            out[k] = secretNested(x, n)
        elseif keep[k] or type(x) == "table" or type(x) == "function" then
            out[k] = x   -- a plain false stays false, so no and/or here
        else
            out[k] = stub.Secret(x)
        end
    end
    return setmetatable(out, getmetatable(v))
end
local function packed(...) return select("#", ...), { ... } end
-- An event's payload (stub.FireEvent). Identity events (UNIT_DIED, PARTY_KILL)
-- carry GUIDs rather than a unit to ask about, so any PvP match or restricted map counts.
function stub.PayloadSecret(spec, unit)
    if spec.when == "identity" then
        if stub.plainSecrets then return false end
        local R = Enum.AddOnRestrictionType
        return (stub.restrictions[R.PvPMatch] or stub.restrictions[R.Map]) == true
    end
    return secretWhen(spec.when, unit)
end
local NO_KEEP = {}
function stub.SecretPayload(spec, ...)
    local n, out = packed(...)
    for i = 1, n do
        if not spec.plain[i] and (not spec.only or spec.only[i]) then out[i] = secretValue(out[i], NO_KEEP) end
    end
    return n, out
end
local function secretAll(info, n, out)
    for i = 1, n do
        if not info.plain[i] then out[i] = secretValue(out[i], info.keep, info.struct) end
    end
    return unpack(out, 1, n)
end
function stub.WrapSecrets()
    if stub.secretApi == nil then
        local SecretAPI = require("secret_api")
        stub.secretApi = SecretAPI.Load() > 0 and SecretAPI.functions or false
        stub.secretEvents = stub.secretApi and SecretAPI.events or nil
        stub.secretNested, stub.secretStructs = SecretAPI.nested, SecretAPI.structs
    end
    if not stub.secretApi then return end
    for name, info in pairs(stub.secretApi) do
        local ns, fname = string.match(name, "^(.-)%.?([^%.]+)$")
        local owner = (ns ~= "" and _G[ns]) or (ns == "" and _G) or nil
        local orig = type(owner) == "table" and rawget(owner, fname)
        if type(orig) == "function" and not secretWrapped[orig] then
            local wrapped = function(...)
                if secretWhen(info.when, ...) then return secretAll(info, packed(orig(...))) end
                return orig(...)
            end
            secretWrapped[wrapped] = true
            owner[fname] = wrapped
        end
    end
end

stub.CORE_FILES = { "Locales/Locales.lua", "Locales/ruRU.lua", "Locales/zhCN.lua", "Locales/koKR.lua", "Locales/frFR.lua", "Locales/esES.lua", "Locales/deDE.lua", "Core.lua", "DB.lua", "Pixel.lua", "Style.lua", "Tips.lua", "GameFonts.lua", "DamageText.lua", "Motion.lua", "Sound.lua", "Pad.lua", "Media.lua", "Health.lua", "Threat.lua", "Spots.lua", "Dots.lua", "DotsDraw.lua", "PrivateAuras.lua", "Taint.lua", "Gradients.lua", "Movers.lua", "Fade.lua", "FadeUpgrade.lua", "EditMode.lua", "EditModeBase.lua", "GameMovers.lua", "PTRButton.lua", "QuestieAside.lua", "PrettyAside.lua", "OpenMap.lua", "CombatText/Kinds.lua", "CombatText/Lines.lua", "CombatText/Feed.lua", "CombatText/Page.lua", "Options/Registry.lua", "Options/Theme.lua",
                    "Options/Widgets.lua", "Options/SampleStrip.lua", "Options/Nav.lua", "Options/Results.lua", "Options/Panel.lua", "GameMenu.lua", "Installer.lua", "InstallerDraft.lua", "InstallerPages.lua", "InstallerCards.lua", "InstallerUI.lua", "InstallerSteps.lua", "Profiles.lua", "Alts.lua", "Plugins.lua", "API.lua", "Donators.lua", "PatchNotes.lua", "PatchNotesUI.lua", "TestBox.lua", "Windows/Feel.lua", "Windows/Frame.lua", "Windows/Room.lua", "Windows/Follow.lua", "Windows/Parts.lua", "Windows/Keys.lua", "Windows/Cast.lua", "Tour.lua" }
stub.BUFFS_FILES = { "Core.lua", "Categories.lua", "Data.lua", "Classify.lua", "Auras.lua", "Spells.lua", "Layout.lua",
                     "Scan.lua", "Preview.lua", "Widgets.lua", "Bar.lua", "Feel.lua", "DebuffBar.lua", "Private.lua", "PreviewBar.lua", "Reminder.lua", "EdgeEditor.lua", "Commands.lua",
                     "Options.lua", "Module.lua" }
stub.QUESTS_FILES = { "Blizzard.lua", "Defaults.lua", "Data.lua", "Layout.lua", "Look.lua", "Rows.lua", "Animate.lua",
                      "Items.lua", "Clicks.lua", "Details.lua", "Journal.lua", "Scroll.lua", "Tracker.lua", "Progress.lua", "Nav.lua", "Spots.lua", "Route.lua", "Arrow.lua", "QuestieBridge.lua", "Voice.lua", "Choice.lua", "GiverTips.lua", "Options.lua", "Module.lua" }
stub.CHARACTER_FILES = { "Defaults.lua", "Colors.lua", "Gear.lua", "Stats.lua", "StatText.lua", "Window.lua", "Follow.lua", "Slots.lua",
                         "Model.lua", "Pages/Character.lua", "Pages/Pet.lua", "Menus.lua", "List.lua", "Pages/Reputation.lua",
                         "Pages/Skills.lua", "Pages/PvP.lua", "Pages/Statistics.lua", "Pages/Currency.lua",
                         "Options.lua", "Module.lua" }
stub.NPC_FILES = { "Defaults.lua", "Data.lua", "Shop.lua", "Train.lua", "Window.lua", "Scene.lua", "Popups.lua", "Options.lua", "Module.lua" }
stub.BOOK_FILES = { "Defaults.lua", "TalentData.lua", "Arrows.lua", "Spend.lua", "Talents.lua", "LoadoutString.lua", "Builds.lua", "SpellData.lua", "Cast.lua", "Spells.lua", "Training.lua", "Fight.lua", "Window.lua", "Options.lua", "Module.lua" }
stub.INSPECT_FILES = { "Defaults.lua", "Model.lua", "Gear.lua", "Talents.lua", "Window.lua", "Options.lua", "Module.lua" }
stub.CRAFT_FILES = { "Defaults.lua", "Data.lua", "Share.lua", "Spells.lua", "List.lua", "Recipe.lua", "Make.lua", "View.lua", "Key.lua", "Window.lua", "Options.lua", "Module.lua" }
stub.LFG_FILES = { "Defaults.lua", "Data.lua", "Rows.lua", "Browse.lua", "Listing.lua", "Who.lua", "Window.lua", "Options.lua", "Module.lua" }
stub.MAIL_FILES = { "Defaults.lua", "Ledger.lua", "Inbox.lua", "Send.lua", "LedgerPage.lua", "Window.lua", "Options.lua", "Module.lua" }
stub.SOCIAL_FILES = { "Defaults.lua", "Data.lua", "Friends.lua", "Allies.lua", "Requests.lua", "Raid.lua", "Window.lua", "Options.lua", "Module.lua" }
stub.LEGACY_FILES = { "Defaults.lua", "Data.lua", "Progress.lua", "Challenges.lua", "Trees.lua", "Window.lua", "Options.lua", "Module.lua" }
stub.MODULE_DIR = "DaylightUI_UnitFrames/"
stub.ACTIONBARS_FILES = { "Defaults.lua", "Shape.lua", "Skin.lua", "Hide.lua", "Menus.lua", "Totems.lua", "Park.lua", "Paging.lua", "Buttons.lua", "Ping.lua", "RankUp.lua", "Keys.lua", "Small.lua", "PadSkin.lua", "Bars.lua",
                          "Cooldowns.lua", "BuffBars.lua", "CdmData.lua", "CdmSpells.lua", "CdmCustom.lua", "CdmEffects.lua", "CdmRows.lua", "CdmOwn.lua",
                          "CdmAuras.lua", "CdmBars.lua", "CdmEditor.lua", "CdmCard.lua", "CdmImport.lua", "Diag.lua", "Options.lua", "Module.lua" }
stub.MODULE_FILES = { "Defaults.lua", "UnitFrames.lua", "Colors.lua", "CastBar.lua", "Swing.lua", "HealSpells.lua", "Auras.lua", "AuraGroups.lua", "Indicators.lua", "Texts.lua", "Looks.lua", "Combo.lua", "Happiness.lua", "Blizzard.lua",
                      "GroupParts.lua", "GroupPrivate.lua", "Group.lua", "Raid.lua", "PartyPets.lua", "PartyCasts.lua", "Party.lua", "Arena.lua", "Leader.lua", "Pull.lua", "ClickCast.lua", "ClickBinder.lua", "ClickCastPage.lua", "PowerBar.lua", "DruidBars.lua", "Personal.lua", "Arrive.lua", "Moments.lua", "Upgrade.lua", "Units.lua", "TestMode.lua", "Sample.lua", "PageSample.lua", "Sweep.lua", "Options.lua", "Module.lua" }

-- Each file is read and compiled once per run (false = not on disk). Every Load
-- runs the compiled chunk again, which gives fresh locals as a reload does.
local compiled = {}
-- Makes the next Load read every file again. test_hygiene watches loadfile, and in
-- a one-process run an earlier file has already compiled them.
function stub.ForgetCompiled()
    for k in pairs(compiled) do compiled[k] = nil end
end
local function loadFiles(dir, files, addonName, ns, after)
    for _, file in ipairs(files) do
        local path = dir .. file
        local chunk = compiled[path]
        if chunk == nil then
            local fh = io.open(path)
            chunk = false
            if fh then
                fh:close()
                local err
                chunk, err = loadfile(path)
                if not chunk then error(err) end
            end
            compiled[path] = chunk
        end
        if chunk then chunk(addonName, ns) end
        if after then after(file) end
    end
end
-- Another addon's tests load their own files the same way (DaylightMogul).
stub.LoadFiles = loadFiles

stub.SKINS_FILES = { "Defaults.lua", "Kit.lua", "Engine.lua", "Packs/NPC.lua", "Packs/Character.lua", "Packs/Spells.lua", "Packs/Social.lua", "Packs/Collections.lua", "Packs/System.lua", "Packs/Breath.lua", "Packs/LossOfControl.lua", "Packs/Addons/Ace3.lua", "Packs/Addons/Questie.lua", "Packs/Addons/RXPGuides.lua", "Packs/Addons/ForeverDungeonJournal.lua", "Packs/Addons/NeedRoll.lua", "Packs/Addons/DBM.lua", "Packs/Addons/BigWigs.lua", "Packs/Addons/Attune.lua", "Packs/Addons/OPie.lua", "Packs/Addons/PrettyTooltip.lua", "Packs/Addons/Bagnon.lua", "Packs/Addons/Baganator.lua", "MapMove.lua", "MapRevealData.lua", "MapReveal.lua", "MapPinsData.lua", "MapPins.lua", "WindowScale.lua", "WindowMove.lua", "Options.lua", "Module.lua" }

-- Loads the core (and optionally the unit frames module) into fresh namespaces
-- the way the client does, then fires the load events.
function stub.Load(opts)
    opts = opts or {}
    stub.Reset()
    if opts.before then opts.before() end
    local DUI, UF = {}, nil
    -- opts.locale(L) is a test's own language, put on DUI.L right after
    -- Locales.lua makes it and before any file reads it (tests/test_locale.lua).
    loadFiles("", stub.CORE_FILES, "DaylightUI", DUI, opts.locale and function(file)
        if file == "Locales/Locales.lua" then opts.locale(DUI.L) end
    end)
    loadFiles("Character/", stub.CHARACTER_FILES, "DaylightUI", DUI)   -- the character window, part of the core
    stub.character = DUI.Char
    loadFiles("Npc/", stub.NPC_FILES, "DaylightUI", DUI)   -- the NPC window, part of the core
    stub.npc = DUI.Npc
    loadFiles("Book/", stub.BOOK_FILES, "DaylightUI", DUI)   -- the spellbook and talents window, part of the core
    stub.book = DUI.Book
    loadFiles("Inspect/", stub.INSPECT_FILES, "DaylightUI", DUI)   -- the inspect window, part of the core
    stub.inspect = DUI.Inspect
    loadFiles("Craft/", stub.CRAFT_FILES, "DaylightUI", DUI)   -- the profession window, part of the core
    stub.craft = DUI.Craft
    loadFiles("Lfg/", stub.LFG_FILES, "DaylightUI", DUI)   -- the group finder window, part of the core
    stub.lfg = DUI.Lfg
    loadFiles("Mail/", stub.MAIL_FILES, "DaylightUI", DUI)   -- the mailbox, part of the core
    stub.mail = DUI.Mail
    loadFiles("Social/", stub.SOCIAL_FILES, "DaylightUI", DUI)   -- the social window, part of the core
    stub.social = DUI.Social
    loadFiles("Legacy/", stub.LEGACY_FILES, "DaylightUI", DUI)   -- the Legacy window, part of the core
    stub.legacy = DUI.Legacy
    stub.FireEvent("ADDON_LOADED", "DaylightUI")
    if opts.module then
        UF = {}
        loadFiles(stub.MODULE_DIR, stub.MODULE_FILES, "DaylightUI_UnitFrames", UF)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_UnitFrames")
    end
    if opts.actionbars then
        local AB = {}
        loadFiles("DaylightUI_ActionBars/", stub.ACTIONBARS_FILES, "DaylightUI_ActionBars", AB)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_ActionBars")
        UF = UF or AB
        stub.actionbars = AB
    end
    if opts.buffs then
        local BL = {}
        loadFiles("DaylightUI_Buffs/", stub.BUFFS_FILES, "DaylightUI_Buffs", BL)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_Buffs")
        stub.buffs = BL
    end
    if opts.skins then
        local SK = {}
        loadFiles("DaylightUI_Skins/", stub.SKINS_FILES, "DaylightUI_Skins", SK)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_Skins")
        stub.skins = SK
    end
    if opts.bags then
        local BG = {}
        loadFiles("DaylightUI_Bags/", { "Defaults.lua", "Saved.lua", "Items.lua", "Plugins.lua", "Search.lua", "Categories.lua", "Junk.lua", "Repair.lua", "Bags.lua", "Layout.lua", "Stack.lua", "Keep.lua", "Swap.lua", "Window.lua", "Disenchant.lua", "Guard.lua", "Prep.lua", "Slots.lua", "Bank.lua", "Viewer.lua",
                                        "Currency.lua", "MoneyRoll.lua",
                                        "OpenClose.lua", "Options.lua", "Module.lua" }, "DaylightUI_Bags", BG)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_Bags")
        stub.bags = BG
    end
    if opts.nameplates then
        local NP = {}
        loadFiles("DaylightUI_Nameplates/", { "Defaults.lua", "Body.lua", "Plate.lua", "Minion.lua", "Cast.lua", "Combo.lua", "Power.lua", "Auras.lua", "Manager.lua", "PlateLog.lua", "Options.lua", "Sample.lua", "Module.lua" },
            "DaylightUI_Nameplates", NP)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_Nameplates")
        stub.nameplates = NP
    end
    if opts.tooltip then
        local TT = {}
        loadFiles("DaylightUI_Tooltip/", { "Defaults.lua", "Tooltip.lua", "Options.lua", "Module.lua" }, "DaylightUI_Tooltip", TT)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_Tooltip")
        stub.tooltip = TT
    end
    if opts.qol then
        local Q = {}
        loadFiles("DaylightUI_QoL/", { "Defaults.lua", "Delete.lua", "Loot.lua", "Trainer.lua", "Quests.lua", "Gossip.lua", "Cinematics.lua", "Tutorials.lua", "AfkFacts.lua", "Afk.lua", "Camera.lua", "Sparkles.lua", "Glow.lua", "Tracking.lua", "Errors.lua", "ErrorText.lua", "Flight.lua", "LootFeed.lua", "LevelUp.lua", "ZoneTitle.lua", "RepBanner.lua", "Campfire.lua", "Fishing.lua", "CursorRing.lua", "Options.lua", "Module.lua" }, "DaylightUI_QoL", Q)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_QoL")
        stub.qol = Q
    end
    if opts.chat then
        local CH = {}
        loadFiles("DaylightUI_Chat/", { "Defaults.lua", "Tags.lua", "Chat.lua", "Feel.lua", "History.lua", "Copy.lua", "Bubbles.lua", "Links.lua", "LinkTips.lua", "Whisper.lua", "Recall.lua", "Kinds.lua", "Box.lua", "ChatMenu.lua", "Extras.lua", "Tabs.lua", "Filter.lua", "Talk.lua", "Thread.lua", "Convo.lua", "Tiles.lua", "Hub.lua", "Tell.lua", "Options.lua", "Module.lua" }, "DaylightUI_Chat", CH)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_Chat")
        stub.chatModule = CH
    end
    if opts.infopanel then
        local IP = {}
        loadFiles("DaylightUI_InfoPanel/", { "Defaults.lua", "Panel.lua", "XPBar.lua", "XPGain.lua", "Rows.lua", "MeterHeader.lua", "Meter.lua", "ThreatView.lua", "ThreatMeter.lua", "DeathLog.lua", "Breakdown.lua", "BreakdownWindow.lua", "Summary.lua", "MeterWindows.lua", "MeterFrame.lua", "Report.lua", "Minimap.lua", "Drawer.lua", "DataTexts.lua", "DataBar.lua", "Broker.lua", "Tracker.lua",
                                             "MeterOptions.lua", "Options.lua", "Module.lua" }, "DaylightUI_InfoPanel", IP)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_InfoPanel")
        stub.infopanel = IP
    end
    if opts.quests then
        local QT = {}
        stub.loadedAddOns["DaylightUI_Quests"] = true
        loadFiles("DaylightUI_Quests/", stub.QUESTS_FILES, "DaylightUI_Quests", QT)
        stub.FireEvent("ADDON_LOADED", "DaylightUI_Quests")
        stub.quests = QT
    end
    if opts.login ~= false then
        stub.FireEvent("PLAYER_LOGIN")
        -- No PLAYER_ENTERING_WORLD here, so end the fade engine's login phase and
        -- let areas behave as in play (opts.intro keeps it for intro tests).
        if DUI.Fade and not opts.intro then DUI.Fade.SkipIntro() end
    end
    return DUI, UF
end

stub.Reset()
return stub
