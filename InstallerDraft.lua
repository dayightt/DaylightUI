-- The setup guide's draft. Every pick previews live (written into the active
-- profile, like the options window does) and the draft remembers each
-- setting's previous value. Closing the guide restores everything, and Finish
-- moves the picks into whichever profile the character ends up on. A copy of
-- the originals is saved in the character's entry (installDraft), so a crash
-- or reload partway through is undone at next login (DB.OnLogin calls
-- Draft.RestoreSaved before modules build).

local _, DUI = ...

local Draft = {}
DUI.InstallerDraft = Draft

-- Saved variables can't hold nil, so an original nil is stored as this.
Draft.NIL = "__DaylightUI_nil__"

local state

local function key(scope, path) return scope .. "\t" .. path end
local function split(k) return string.match(k, "^(.-)\t(.+)$") end

local copy = DUI.DB.Copy

-- One scope's settings ("general" or a module name) in a profile's saved
-- tables, created if missing.
local function scopeIn(p, scope)
    if scope == "general" then
        if type(p.general) ~= "table" then p.general = {} end
        return p.general
    end
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.modules[scope]) ~= "table" then p.modules[scope] = {} end
    return p.modules[scope]
end

function Draft.Begin()
    state = { profile = DUI.DB.ActiveName(), tracked = {}, originals = {}, picked = {}, seeded = {}, reload = false }
    DUI.DB.Character().installDraft = nil
end

function Draft.Active() return state ~= nil end
function Draft.Profile() return state and state.profile end

-- A setting the guide shows. Seed and Commit go over every tracked one.
function Draft.Track(scope, path)
    if state then state.tracked[key(scope, path)] = true end
end

-- Saves a key's value from before the draft first changed it, once (and
-- mirrors it into the saved entry).
local function remember(k, scope, path)
    if state.originals[k] ~= nil then return end
    local v = DUI:Get(scope, path)
    if v == nil then v = Draft.NIL else v = copy(v) end
    state.originals[k] = v
    local c = DUI.DB.Character()
    if type(c.installDraft) ~= "table" then c.installDraft = { profile = state.profile, values = {} } end
    c.installDraft.values[k] = copy(v)
end

local function original(k)
    local v = state.originals[k]
    if v == Draft.NIL then return nil end
    return copy(v)
end

-- A player's pick: previewed live and never overwritten by seeding.
-- needsReload: the option only takes effect after a reload.
function Draft.Set(scope, path, value, needsReload)
    if not state then return DUI:Set(scope, path, value) end
    local k = key(scope, path)
    state.tracked[k] = true
    remember(k, scope, path)
    state.picked[k] = true
    state.seeded[k] = nil
    if needsReload then state.reload = true end
    return DUI:Set(scope, path, copy(value))
end

-- Undoes a pick. The setting goes back to its pre-draft value, and seeding
-- may show the setup's value again.
function Draft.Unpick(scope, path)
    if not state then return end
    local k = key(scope, path)
    if not state.picked[k] then return end
    state.picked[k] = nil
    DUI:Set(scope, path, original(k))
end

function Draft.Picked(scope, path) return state ~= nil and state.picked[key(scope, path)] == true end
function Draft.NeedsReload() return state ~= nil and state.reload == true end

-- Shows another profile's values for every tracked key the player hasn't
-- picked. name is the profile the character will end up on. Nil, the active
-- profile, or one that doesn't exist yet restores seeded keys.
function Draft.Seed(name)
    if not state then return end
    local pd = DUI.DB.Root().profileData
    local from
    if name ~= nil and name ~= state.profile and type(pd[name]) == "table" then from = DUI.DB.Fill(pd[name]) end
    for k in pairs(state.tracked) do
        if not state.picked[k] then
            local scope, path = split(k)
            if from then
                local v = DUI.DB.GetPath(scopeIn(from, scope), path)
                if v ~= nil then
                    remember(k, scope, path)
                    state.seeded[k] = true
                    DUI:Set(scope, path, copy(v))
                end
            elseif state.seeded[k] then
                state.seeded[k] = nil
                DUI:Set(scope, path, original(k))
            end
        end
    end
end

-- Restores every changed key in the active profile, either live (repainting
-- as it goes) or straight into the saved tables of a profile about to be left.
local function putBack(live)
    local p = DUI.DB.Root().profileData[state.profile]
    for k in pairs(state.originals) do
        local scope, path = split(k)
        if live then
            DUI:Set(scope, path, original(k))
        elseif type(p) == "table" then
            DUI.DB.SetPath(scopeIn(p, scope), path, original(k))
        end
    end
end

local function clear()
    state = nil
    DUI.DB.Character().installDraft = nil
end

-- Closing the guide restores everything, on screen too.
function Draft.Revert()
    if not state then return end
    putBack(true)
    clear()
end

-- Finish moves the picks into target (which must exist by now). For another
-- profile, every tracked key's value is copied into it and the active profile
-- gets its originals back, not live since the reload that follows leaves it.
function Draft.Commit(target)
    if not state then return end
    if target ~= state.profile then
        Draft.CopyInto(DUI.DB.Root().profileData[target])
        putBack(false)
    end
    clear()
end

-- Copies every tracked key's current value into a profile's table (used when
-- Finish rebuilds a profile that replaces another).
function Draft.CopyInto(p)
    if not state or type(p) ~= "table" then return end
    DUI.DB.Fill(p)
    for k in pairs(state.tracked) do
        local scope, path = split(k)
        local v = DUI:Get(scope, path)
        if v ~= nil then DUI.DB.SetPath(scopeIn(p, scope), path, copy(v)) end
    end
end

-- At login, before modules build: a draft left by a crash or reload partway
-- through is restored into the profile it changed.
function Draft.RestoreSaved()
    local c = DUI.DB.Character()
    local d = c.installDraft
    if type(d) ~= "table" then return end
    c.installDraft = nil
    local p = type(d.profile) == "string" and DUI.DB.Root().profileData[d.profile]
    if type(p) ~= "table" or type(d.values) ~= "table" then return end
    for k, v in pairs(d.values) do
        local scope, path = split(k)
        if scope then
            if v == Draft.NIL then v = nil end
            DUI.DB.SetPath(scopeIn(p, scope), path, copy(v))
        end
    end
end
