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

-- ---------------------------------------------------------------------
-- A private copy of the game's side for one test world (tests/cdmworld.lua).
-- Files loaded through it write their globals into game.G instead of _G, so a
-- file's local state never outlives its world and the game's own helpers
-- (TableUtil, Pools, ...) don't replace the fake game's for every other test.
-- Game code reads game.G first, then what every game file sees (the fake game's
-- globals, FAKES, a noted stand-in).
-- ---------------------------------------------------------------------

local chunks = {}
local function compiled(file)
    local chunk = chunks[file]
    if not chunk then
        if not Blizz.Have(file) then
            error("tests/blizzard/" .. file .. " is missing: run `py tools/fetch_blizzard.py` once on this PC", 3)
        end
        local err
        chunk, err = loadfile(Blizz.DIR .. file)
        if not chunk then error(err, 3) end
        chunks[file] = chunk
    end
    return chunk
end

-- The game's own code is untainted: it may read secrets and touch protected
-- frames in a fight. stub.inGame counts how deep in it the test is; entering
-- from outside runs game.enter (a world shows its values plain), leaving runs
-- game.leave (it hides again what addon code may not read).
local current
local function asGame(game, fn, ...)
    local outer = (stub.inGame or 0) == 0
    stub.inGame = (stub.inGame or 0) + 1
    stub.inSecure = (stub.inSecure or 0) + 1
    if outer then
        current = game
        if game.enter then game.enter() end
    end
    -- Blizz.trace = true adds the game code's own stack to an error.
    local n, r = (function(...) return select("#", ...), { ... } end)(
        xpcall(fn, Blizz.trace and debug.traceback or function(e) return e end, ...))
    if outer then
        if game.leave then game.leave() end
        current = nil
    end
    stub.inGame = stub.inGame - 1
    stub.inSecure = stub.inSecure - 1
    if not r[1] then error(r[2], 0) end
    return unpack(r, 2, n)
end

-- Addon code that the game's code reaches (a hook on one of its methods, a
-- HookScript, a callback) runs tainted again for as long as it lasts.
function Blizz.Tainted(fn, ...)
    local game, depth, secure = current, stub.inGame or 0, stub.inSecure or 0
    if depth == 0 then return fn(...) end
    if game and game.leave then game.leave() end
    stub.inGame, stub.inSecure, current = 0, secure - depth, nil
    local n, r = (function(...) return select("#", ...), { ... } end)(pcall(fn, ...))
    stub.inGame, stub.inSecure, current = depth, secure, game
    if game and game.enter then game.enter() end
    if not r[1] then error(r[2], 0) end
    return unpack(r, 2, n)
end

-- A small XML reader for the game's template files: elements, attributes and
-- nesting. Comments and text are dropped.
local function readXML(file)
    local f = io.open(Blizz.DIR .. file, "r")
    if not f then
        error("tests/blizzard/" .. file .. " is missing: run `py tools/fetch_blizzard.py` once on this PC", 3)
    end
    local src = f:read("*a")
    f:close()
    src = string.gsub(src, "<!%-%-.-%-%->", "")
    local root = { tag = "", attr = {}, kids = {} }
    local stack = { root }
    for close, tag, attrs, selfClose in string.gmatch(src, "<(/?)([%w_:]+)(.-)(/?)>") do
        if close == "/" then
            stack[#stack] = nil
        else
            local node = { tag = tag, attr = {}, kids = {} }
            for k, v in string.gmatch(attrs, "([%w_:]+)%s*=%s*\"(.-)\"") do node.attr[k] = v end
            local top = stack[#stack]
            top.kids[#top.kids + 1] = node
            if selfClose ~= "/" then stack[#stack + 1] = node end
        end
    end
    return root
end

local function kid(node, tag)
    for _, k in ipairs(node.kids) do if k.tag == tag then return k end end
end

local REGION_MAKERS = { Texture = "CreateTexture", MaskTexture = "CreateMaskTexture", FontString = "CreateFontString" }

function Blizz.Game()
    local G = {}
    local genv = setmetatable({}, {
        __index = function(_, k)
            local v = G[k]
            if v ~= nil then return v end
            return env[k]
        end,
        __newindex = function(_, k, v) G[k] = v end,
    })
    local game = { G = G, env = genv, templates = {} }

    -- Runs a game file with the arguments the client hands an addon's files
    -- (its name and its private table).
    function game.Load(file, ...)
        local chunk = compiled(file)
        setfenv(chunk, genv)
        return asGame(game, chunk, ...)
    end
    function game.Run(fn, ...) return asGame(game, fn, ...) end

    -- A namespace as the game's code sees it: its own entries first, then the
    -- fake game's, then a noted stand-in.
    function game.Space(name, own)
        G[name] = setmetatable(own, { __index = function(_, k)
            local t = rawget(_G, name)
            local v = type(t) == "table" and t[k] or nil
            if v ~= nil then return v end
            Blizz.inert[name .. "." .. tostring(k)] = true
            return INERT
        end })
        return own
    end

    -- A handler the game's code sets runs as the game's code whoever fires it.
    local function gameScripts(f)
        if rawget(f, "__gameMade") then return end
        f.__gameMade = true
        local set = f.SetScript
        function f:SetScript(h, fn)
            if type(fn) ~= "function" then return set(self, h, fn) end
            return set(self, h, function(...) return asGame(game, fn, ...) end)
        end
    end
    game.Own = gameScripts

    local function lookup(path)
        local v = genv
        for part in string.gmatch(path, "[^%.]+") do v = v[part] end
        return v
    end

    local function relative(region, key)
        local v = region
        for part in string.gmatch(key, "[^%.]+") do
            if part == "$parent" then v = v:GetParent() else v = v[part] end
        end
        return v
    end

    local function place(node, region, parent)
        if node.attr.setAllPoints == "true" then region:SetAllPoints(parent) end
        local size = kid(node, "Size")
        if size then
            if size.attr.x then region:SetWidth(tonumber(size.attr.x)) end
            if size.attr.y then region:SetHeight(tonumber(size.attr.y)) end
        end
        local anchors = kid(node, "Anchors")
        for _, a in ipairs(anchors and anchors.kids or {}) do
            local to = parent
            if a.attr.relativeKey then to = relative(region, a.attr.relativeKey)
            elseif a.attr.relativeTo then to = lookup(a.attr.relativeTo) end
            region:SetPoint(a.attr.point, to, a.attr.relativePoint or a.attr.point,
                tonumber(a.attr.x) or 0, tonumber(a.attr.y) or 0)
        end
    end

    local apply
    local function build(f, template)
        local node = game.templates[template]
        if node then
            apply(node, f)
        else
            local made = stub.TEMPLATES[template]
            if made then made(f) else Blizz.inert["template " .. template] = true end
        end
    end

    apply = function(node, f)
        gameScripts(f)
        local first = not rawget(f, "__building")
        f.__building = true
        for t in string.gmatch(node.attr.inherits or "", "[^,%s]+") do build(f, t) end
        for name in string.gmatch(node.attr.mixin or "", "[^,%s]+") do
            local mixin = G[name]
            if type(mixin) == "table" then
                for k, v in pairs(mixin) do f[k] = v end
            else
                Blizz.inert["mixin " .. name] = true
            end
        end
        if node.attr.hidden == "true" then f.__shown = false end
        if node.attr.frameLevel then f:SetFrameLevel(tonumber(node.attr.frameLevel)) end
        if node.attr.reverse == "true" and f.SetReverse then f:SetReverse(true) end
        place(node, f, f:GetParent())
        for _, kv in ipairs((kid(node, "KeyValues") or { kids = {} }).kids) do
            local v, kind = kv.attr.value, kv.attr.type
            if kind == "number" then v = tonumber(v)
            elseif kind == "boolean" then v = v == "true"
            elseif kind == "global" then v = lookup(v) end
            f[kv.attr.key] = v
        end
        for _, layer in ipairs((kid(node, "Layers") or { kids = {} }).kids) do
            for _, r in ipairs(layer.kids) do
                local make = REGION_MAKERS[r.tag]
                if make then
                    local region = f[make](f, nil, layer.attr.level)
                    if r.attr.parentKey then f[r.attr.parentKey] = region end
                    if r.attr.alpha then region:SetAlpha(tonumber(r.attr.alpha)) end
                    place(r, region, f)
                end
            end
        end
        local bar = kid(node, "BarTexture")
        if bar and f.SetStatusBarTexture then
            local tex = f:CreateTexture()
            f:SetStatusBarTexture(tex)
            if bar.attr.parentKey then f[bar.attr.parentKey] = tex end
        end
        for _, c in ipairs((kid(node, "Frames") or { kids = {} }).kids) do
            local child = CreateFrame(c.tag, nil, f)
            if c.attr.parentKey then f[c.attr.parentKey] = child end
            apply(c, child)
        end
        for _, g in ipairs((kid(node, "Animations") or { kids = {} }).kids) do
            local group = f:CreateAnimationGroup()
            if g.attr.parentKey then f[g.attr.parentKey] = group end
            for _, a in ipairs(g.kids) do
                local anim = group:CreateAnimation(a.tag)
                if a.attr.parentKey then group[a.attr.parentKey] = anim end
            end
        end
        -- <OnShow method="OnShow"/> calls self:OnShow(...). The method is looked up
        -- when the script runs, so a method replaced later is the one called.
        for _, s in ipairs((kid(node, "Scripts") or { kids = {} }).kids) do
            local method, fn = s.attr.method, s.attr["function"]
            if method then
                f:SetScript(s.tag, function(self, ...) return self[method](self, ...) end)
            elseif fn then
                f:SetScript(s.tag, function(...) return lookup(fn)(...) end)
            end
        end
        -- The client runs OnLoad once, when the whole frame is built (its
        -- templates, its own parts and its children).
        if first then
            f.__building = nil
            if game.made then game.made(f, node.attr.name) end
            local onLoad = f:GetScript("OnLoad")
            if onLoad then onLoad(f) end
        end
    end

    -- Reads one of the game's XML files: its virtual frames become templates
    -- CreateFrame knows, the others are made at once, in the file's order.
    function game.UI(file)
        for _, node in ipairs(kid(readXML(file), "Ui").kids) do
            local name = node.attr.name
            if node.attr.virtual == "true" then
                game.templates[name] = node
                stub.TEMPLATES[name] = function(f) apply(node, f) end
            elseif name then
                asGame(game, function()
                    local parent = node.attr.parent and lookup(node.attr.parent) or nil
                    local f = CreateFrame(node.tag, name, parent)
                    apply(node, f)
                    -- A frame that starts out visible gets its OnShow once it's loaded.
                    local onShow = f:GetScript("OnShow")
                    if onShow and f:IsVisible() then onShow(f) end
                end)
            end
        end
    end

    return game
end

return Blizz
