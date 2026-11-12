-- Applies the registered skins. Each skin names its pack (so a whole group can
-- be turned off), the load-on-demand addon its window comes from if any, and an
-- apply function that does the work with the Kit. A skin runs once, as soon as
-- its window exists, and only out of combat in case the window is protected.
--
-- To add one, call Engine.Register({ key = "...", pack = "npc", addon = "Blizzard_X",
-- apply = function(Kit) ... end }) from a file under Packs/ and list it in the .toc.
-- Skins for other addons go in Packs/Addons/<Name>.lua with thirdParty = true,
-- pack "addons" and a switch registered through Engine.AddonSwitch.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local Engine = {}
ns.Engine = Engine

Engine.skins = {}            -- in registration order

local started, cfg = false, nil

function Engine.Register(def)
    assert(type(def.key) == "string" and type(def.apply) == "function", "a skin needs a key and an apply function")
    Engine.skins[#Engine.skins + 1] = def
    if started then Engine.Try(def) end
end

local function loaded(addon)
    if not addon then return true end
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) or false
end

function Engine.Wanted(def)
    if cfg == nil or cfg.packs[def.pack] == false or def.broken then return false end
    -- Third-party skins also have their own switch in the options.
    if def.switch and cfg.addonSkins and cfg.addonSkins[def.switch] == false then return false end
    return true
end

-- Third-party addons change their frames between versions, so a broken skin is
-- expected rather than fatal. It's reported once in chat, disabled, and that addon
-- is left alone. Hooks a skin sets on the addon should go through Engine.Safe(def, fn).
local told = {}
function Engine.Broke(def, err)
    if not def.thirdParty then
        geterrorhandler()(err)
        return
    end
    def.broken = true
    local addon = def.addon or def.label or def.key
    if told[addon] then return end
    told[addon] = true
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and def.addon and C_AddOns.GetAddOnMetadata(def.addon, "Version")
    DUI.Print(string.format(L["Daylight UI couldn't skin %s %s: it's left as it is."], tostring(def.label or addon), tostring(version or "")))
    -- Print the actual error when the dev addon is loaded.
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("DaylightUI_Dev") then geterrorhandler()(err) end
end

function Engine.Safe(def, fn)
    return function(...)
        if def.broken or not Engine.Wanted(def) then return end
        local ok, err = pcall(fn, ...)
        if not ok then Engine.Broke(def, err) end
    end
end

-- Applies a skin if it's enabled, not applied yet, and its addon is loaded.
-- A skin whose window doesn't exist yet returns false from apply and is
-- retried whenever another addon loads.
function Engine.Try(def)
    if def.done or not Engine.Wanted(def) or not loaded(def.addon) then return end
    if def.skip and def.skip() then return end -- replaced by one of our own windows, e.g. the NPC window
    def.done = true
    DUI.AfterCombat(function()
        local ok, result = pcall(def.apply, ns.Kit, def)
        if not ok then
            Engine.Broke(def, result)
        elseif result == false then
            def.done = false
        end
    end, "skins:" .. def.key)
end

-- Per-addon switches for third-party skins, shown only while that addon is
-- installed. spec: key (stored as addonSkins.<key>), label, desc, and either
-- addon (an addon name) or present() for libraries embedded in other addons.
Engine.ADDON_SWITCHES = {}
function Engine.AddonSwitch(spec)
    Engine.ADDON_SWITCHES[#Engine.ADDON_SWITCHES + 1] = spec
    ns.DEFAULTS.addonSkins[spec.key] = true -- on by default
end

function Engine.Installed(spec)
    if spec.present then return spec.present() == true end
    local api = C_AddOns
    return api ~= nil and api.DoesAddOnExist ~= nil and api.DoesAddOnExist(spec.addon) == true
end

-- Lets plugins register skins for other addons and reuse the Kit.
DUI.Skins = DUI.Skins or {}
DUI.Skins.Kit = function() return ns.Kit end
function DUI.Skins.Register(def)
    if def.thirdParty == nil then def.thirdParty = true end
    def.pack = def.pack or "addons"
    return Engine.Register(def)
end
DUI.Skins.Safe = Engine.Safe

-- Resolves "Name.Key.Key" from the globals, or ".Key.Key" relative to base.
function Engine.Find(path, base)
    if type(path) == "table" then return path end
    if type(path) ~= "string" then return nil end
    local obj
    if string.sub(path, 1, 1) == "." then obj = base; path = string.sub(path, 2) end
    for part in string.gmatch(path, "[^%.]+") do
        if obj == nil then obj = _G[part] elseif type(obj) == "table" then obj = obj[part] else return nil end
    end
    return obj
end

-- /dui skins profile (toggle): reports the time skins spend in the first few
-- frames after a window opens, and how many borders get laid out.
Engine.PROFILE_FRAMES = 6
local profiler = CreateFrame("Frame")
Engine.profiler = profiler
profiler:Hide()
local left, frameNo = 0, 0
profiler:SetScript("OnUpdate", function(self, dt)
    local Kit = ns.Kit
    local s = Kit.TakeSpent()
    local layouts = DUI.Style.TakeLayoutCount and DUI.Style.TakeLayoutCount() or 0
    frameNo = frameNo + 1
    local total, parts = 0, {}
    for what, ms in pairs(s) do
        total = total + ms
        parts[#parts + 1] = string.format("%s %.1f", what, ms)
    end
    DUI.Print(string.format("frame %d took %.0fms: skins %.1fms%s, borders laid out %d",
        frameNo, dt * 1000, total, #parts > 0 and (" [" .. table.concat(parts, ", ") .. "]") or "", layouts))
    left = left - 1
    if left <= 0 then self:Hide() end
end)

function Engine.ProfileWatch()
    left, frameNo = Engine.PROFILE_FRAMES, 0
    ns.Kit.TakeSpent()
    if DUI.Style.TakeLayoutCount then DUI.Style.TakeLayoutCount() end
    profiler:Show()
end

-- Windows hooked for profiling, watched for a few frames after they open.
local profileHooked = setmetatable({}, { __mode = "k" })
function Engine.ProfileHook(f)
    if type(f) ~= "table" or not f.HookScript or profileHooked[f] then return end
    profileHooked[f] = true
    f:HookScript("OnShow", function() if ns.Kit.Profiling then Engine.ProfileWatch() end end)
end

-- Skins a whole window from a declarative def:
--   key, pack, addon      as Engine.Register (thirdParty, switch, label too)
--   frame                 the window, by name or path
--   window                options for Kit.Window, or false to skin only its
--                         parts (e.g. a character tab)
--   strip, hide           paths (relative to the window) of art to strip or hide
--   light                 depth to which dark parchment text is made light
--   auto                  options for Kit.Auto, or false; skip by path
--   watch                 rerun over the shown parts whenever one of the
--                         window's pages is shown, for windows that build lazily
--   after(Kit, f, again)  custom work; again() reruns the pass next frame
-- With again set, only shown parts are visited (hidden pages get theirs when
-- shown). onPage: see Kit.Auto.
local function applyWindow(def, Kit, f, again, onPage)
    local function each(list, fn)
        for _, path in ipairs(list or {}) do
            local obj = Engine.Find(path, f)
            if obj then fn(obj) end
        end
    end
    each(def.strip, Kit.Strip)
    each(def.hide, Kit.Hide)
    if def.auto ~= false then
        -- Built once per window and pass kind, then cached once every part
        -- to skip has been found.
        def.opts = def.opts or {}
        local slot = again and "again" or "first"
        local opts = def.opts[slot]
        if not opts then
            opts = {}
            for k, v in pairs(def.auto or {}) do opts[k] = v end
            local skip, found, wanted = {}, 0, 0
            each(opts.skip, function(obj)
                skip[obj] = true
                found = found + 1
            end)
            for _ in ipairs(opts.skip or {}) do wanted = wanted + 1 end
            opts.skip = skip
            opts.shownOnly = again
            opts.onPage = onPage
            if found == wanted then def.opts[slot] = opts end
        end
        Kit.Auto(f, opts)
    end
    if def.light then Kit.LightAll(f, nil, def.light == true and 8 or def.light, again) end
    if def.after then def.after(Kit, f, def.again) end
end

-- Every window that has a skin, enabled or not, so profiling can compare.
Engine.WINDOWS = {}

-- Hooks every such window that exists, for profiling.
function Engine.ProfileHookAll()
    for _, path in ipairs(Engine.WINDOWS) do Engine.ProfileHook(Engine.Find(path)) end
end

function Engine.Window(def)
    Engine.WINDOWS[#Engine.WINDOWS + 1] = def.frame
    local reg
    reg = { key = def.key, pack = def.pack, addon = def.addon, skip = def.skip,
        thirdParty = def.thirdParty, switch = def.switch, label = def.label, apply = function(Kit)
        local f = Engine.Find(def.frame)
        if type(f) ~= "table" or not f.GetObjectType then return false end
        -- Forbidden frames (e.g. the layering notice) can't be touched at all.
        if f.IsForbidden and f:IsForbidden() then return false end
        Engine.ProfileHook(f)
        if def.window ~= false then Kit.Window(f, def.window) end
        -- Windows build parts later (pages, tabs, lists), so the shown parts
        -- are revisited each time the window, or a watched page, is shown.
        -- This hook runs after the game's own, so new parts get skinned in the
        -- same frame and are never seen undressed. Never in combat, at most
        -- once per frame. A second request in the same frame (e.g. the
        -- spellbook filling its pages right after opening) schedules one more
        -- pass next frame, but only if Kit.Shape says something changed.
        local ranThisFrame, askedAgain, shape = false, false, nil
        local function again(ifChanged)
            if InCombatLockdown and InCombatLockdown() then return end
            if ranThisFrame then
                askedAgain = true
                return
            end
            if ifChanged == true and shape and shape == Kit.Shape(f) then return end
            ranThisFrame = true
            C_Timer.After(0, function()
                ranThisFrame = false
                if askedAgain then
                    askedAgain = false
                    again(true)
                end
            end)
            local t0 = Kit.Profiling and debugprofilestop()
            if def.thirdParty then
                -- The skin's own hooks use Engine.Safe(def), so a failure in
                -- either place disables both.
                if reg.broken or def.broken then return end
                local ok, err = pcall(applyWindow, def, Kit, f, true, nil)
                if not ok then Engine.Broke(reg, err); def.broken = true end
            else
                DUI.SafeCall(applyWindow, def, Kit, f, true, nil)
            end
            -- A page shown usually means a tab was picked. Repaint the selection
            -- now and next frame, since the game updates tabs after the page.
            Kit.RepaintSoon()
            -- A walk spread over several frames isn't finished, so no shape yet.
            shape = not Kit.Walking(f) and Kit.Shape(f) or nil
            if t0 then Kit.Spent("window " .. def.key, debugprofilestop() - t0) end
        end
        def.again = again
        applyWindow(def, Kit, f, false, def.watch and again or nil)
        -- On open: run now and once more next frame, to catch whatever the
        -- game fills in right after.
        f:HookScript("OnShow", function()
            again()
            again()
        end)
    end }
    Engine.Register(reg)
    return reg
end

function Engine.Start(c)
    cfg = c
    if started then return end
    started = true
    for _, def in ipairs(Engine.skins) do Engine.Try(def) end
    DUI.RegisterEvent("ADDON_LOADED", function(_, name)
        if ns.Kit.Profiling then Engine.ProfileHookAll() end
        -- Skins for this addon, plus any still waiting for their window.
        for _, def in ipairs(Engine.skins) do
            if def.addon == name or not def.done then Engine.Try(def) end
        end
    end)
end

-- /dui skins dump Frame.Key [depth]: lists a game window's keyed pieces,
-- children and regions with types, names, atlases and visibility. Useful for
-- writing a new skin.
local function describe(obj, keys)
    local t = obj.GetObjectType and obj:GetObjectType() or "?"
    local name = obj.GetName and obj:GetName()
    local bits = { (keys[obj] and ("." .. keys[obj]) or "") .. " " .. t }
    if type(name) == "string" then bits[#bits + 1] = name end
    if obj.GetAtlas then
        local a = obj:GetAtlas()
        if type(a) == "string" then bits[#bits + 1] = "atlas=" .. a end
    end
    if obj.GetText then
        local ok, text = pcall(obj.GetText, obj)
        if ok and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            bits[#bits + 1] = '"' .. string.sub(text, 1, 24) .. '"'
        end
    end
    if obj.IsShown and not obj:IsShown() then bits[#bits + 1] = "(hidden)" end
    return table.concat(bits, " ")
end

function Engine.Dump(obj, depth, indent)
    indent = indent or ""
    local keys = {}
    for k, v in pairs(obj) do
        if type(k) == "string" and type(v) == "table" and v.GetObjectType then keys[v] = k end
    end
    if obj.GetRegions then
        for _, r in ipairs({ obj:GetRegions() }) do DUI.Print(indent .. "  " .. describe(r, keys)) end
    end
    if obj.GetChildren then
        for _, c in ipairs({ obj:GetChildren() }) do
            local forbidden = c.IsForbidden and c:IsForbidden()
            DUI.Print(indent .. "  " .. (forbidden and "(forbidden)" or describe(c, keys)))
            if not forbidden and depth > 1 then Engine.Dump(c, depth - 1, indent .. "  ") end
        end
    end
end

-- Printable path: the frame's name, or its parent's path plus its key.
local function pathOf(obj, depth)
    local name = obj.GetName and obj:GetName()
    if type(name) == "string" then return name end
    local parent = obj.GetParent and obj:GetParent()
    if not parent or (depth or 0) > 8 then return "?" end
    for k, v in pairs(parent) do
        if v == obj and type(k) == "string" then return pathOf(parent, (depth or 0) + 1) .. "." .. k end
    end
    return pathOf(parent, (depth or 0) + 1) .. ".?"
end

-- /dui skins find <text>: paths of frames showing that text, for windows
-- without a known name.
local function findText(text)
    local want = string.lower(text)
    local found = 0
    local f = EnumerateFrames and EnumerateFrames()
    while f and found < 12 do
        if not (f.IsForbidden and f:IsForbidden()) and f.IsVisible and f:IsVisible() and f.GetRegions then
            for _, r in ipairs({ f:GetRegions() }) do
                local ok, s = pcall(function() return r.GetText and r:GetText() end)
                if ok and type(s) == "string" and not (issecretvalue and issecretvalue(s))
                    and string.find(string.lower(s), want, 1, true) then
                    found = found + 1
                    DUI.Print(pathOf(f) .. ': "' .. string.sub(s, 1, 40) .. '"')
                    break
                end
            end
        end
        f = EnumerateFrames(f)
    end
    if found == 0 then DUI.Print(string.format(L["skins find: nothing on screen shows %s"], text)) end
end

DUI.RegisterCommand("skins", function(rest)
    if string.match(rest or "", "^profile") then
        ns.Kit.Profiling = not ns.Kit.Profiling
        -- Windows with their skin off are timed too, for comparison.
        if ns.Kit.Profiling then Engine.ProfileHookAll() end
        DUI.Print(ns.Kit.Profiling and L["skins profile on: open a window to see what the skins spend"] or L["skins profile off"])
        return
    end
    local text = string.match(rest or "", "^find%s+(.+)$")
    if text then findText(text); return end
    local path, depth = string.match(rest or "", "^dump%s+(%S+)%s*(%d*)")
    if not path then
        DUI.Print(L["skins dump <Frame or Frame.Key> [depth]: lists what a window is made of."])
        DUI.Print(L["skins find <text>: which frames on screen show that text."])
        DUI.Print(L["skins profile: what the skins spend when a window opens (toggles)."])
        return
    end
    local obj
    for part in string.gmatch(path, "[^%.]+") do
        obj = (obj == nil) and _G[part] or (type(obj) == "table" and obj[part] or nil)
    end
    if type(obj) ~= "table" or not obj.GetObjectType then
        DUI.Print(string.format(L["skins dump: no frame %s"], path))
        return
    end
    DUI.Print(path .. ": " .. describe(obj, {}))
    Engine.Dump(obj, tonumber(depth) or 1)
end, L["skins dump <Frame> [depth]: what a game window is made of"])

-- Applies skins for a pack that was just switched on. Switching one off
-- needs a reload since the original art isn't restored.
function Engine.Refresh(c)
    cfg = c
    for _, def in ipairs(Engine.skins) do Engine.Try(def) end
end
