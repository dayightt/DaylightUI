-- The setup guide. A welcome with three ways in: Quick setup (everything on
-- with sensible defaults, plus one "how do you play?" question and the
-- Questing page when the quest tracker is on), a short tour of every part of
-- DaylightUI, or an existing profile. Finish saves it all and offers one
-- reload.
--
-- It shows shortly after login on a character that isn't set up yet (no
-- answer saved; Edit Mode plays no part), and once per account per
-- Installer.VERSION on characters that are, to show the guide off.
-- EditMode.lua calls Installer.Needed() once the game has its layouts.
-- /dui install and the Setup guide button on General > Home reopen it.
-- Closing it (X or Escape) undoes everything it previewed, and a character
-- not set up yet is asked again at next login.
--
-- Choices preview live but stay a draft until Finish (InstallerDraft.lua).
-- The tour's content is data (InstallerPages.lua), drawn by
-- InstallerSteps.lua inside the window (InstallerUI.lua).
--
-- Saved: each character's answer in DB.Character().install ("installed", or
-- "skipped" from the old installer's "Not now"), and the account's showcase
-- in DB.Root().installerSeen.

local _, DUI = ...
local EditMode = DUI.EditMode
local L = DUI.L

local Installer = {}
DUI.Installer = Installer

Installer.VERSION = 2 -- bump to show a new guide to already set-up characters once
Installer.EXISTING = "existing"
Installer.CHECK_STEP = 0.3     -- seconds between the Finish checklist's lines
Installer.TEXT = {
    intro = L["DaylightUI replaces your frames, bars, bags, chat and more with a soft, minimal look. Let's set this character up."],
    showcase = L["DaylightUI has a new setup guide. Take the tour to see everything it can do, or keep your setup as it is."],
}
Installer.CHECKLIST = { L["Profile saved"], L["Layout placed"], L["Modules updated"], L["All set"] }
-- Shown under Finish. Each is a sentence with a hole for the command (drawn highlighted).
Installer.TIPS = {
    { "/dui", L["%s opens the settings."] },
    { "/dui unlock", L["%s lets you move frames; right-click a handle to put one back."] },
    { "/dui install", L["Run this guide again from General > Home, or with %s."] },
}
Installer.ROLE_TEXT = {
    ["DPS/Tank"] = L["Party on the left, you and your target low in the middle."],
    Healer = L["Your party and raid as square tiles under you, dispels easy to spot."],
    ["Immersive Preset"] = L["Calm for questing: bars and your frame fade after a fight. All shown in dungeons."],
}
-- The ready-made setups the welcome and the role page offer, in order.
Installer.READY = { "DPS/Tank", "Healer", "Immersive Preset" }

local dismissed = false -- closed this session, not asked again until next login
local held -- a reload prompt waiting for the guide to close

-- Who gets asked

function Installer.State() return DUI.DB.Character().install end
function Installer.Mark(state) DUI.DB.Character().install = state end

-- Profiles offered by "Use a setup I have": all of them, DPS/Tank first, but
-- only once there's one besides DPS/Tank (otherwise Quick setup covers it).
function Installer.ExistingProfiles()
    local names = DUI.Profiles.Names()
    if #names == 0 or (#names == 1 and names[1] == DUI.DB.DEFAULT) then return {} end
    return names
end

-- Whether this account hasn't seen this version of the guide yet.
function Installer.ShowcaseDue()
    return (tonumber(DUI.DB.Root().installerSeen) or 0) < Installer.VERSION
end

function Installer.MarkSeen() DUI.DB.Root().installerSeen = Installer.VERSION end

-- Already set up (on its profile's layout) or answered the old installer, so
-- the welcome offers to keep the current setup first.
function Installer.Showcase()
    return EditMode.IsActive() or Installer.State() == "skipped"
end

-- Whether to show the guide now. A character not set up yet: always (unless
-- closed this session). One set up, or that said "Not now" to the old
-- installer: once per account per version. One set up but on another layout
-- (the game's own, or ours deleted) is put back by EditMode.lua instead of
-- being asked again.
function Installer.Needed()
    if dismissed then return false end
    if EditMode.IsActive() then
        Installer.Mark("installed")
        return Installer.ShowcaseDue()
    end
    local state = Installer.State()
    if state == "skipped" then return Installer.ShowcaseDue() end
    return state ~= "installed"
end

-- A character with no saved answer is asked shortly after login, without
-- waiting for Edit Mode: those checks need one of our parts loaded and the
-- game's layouts ready, and a new character may have neither. A set-up
-- character waits for the layouts (EditMode.lua), since until then it can't
-- tell whether it's on ours.
Installer.LOGIN_DELAY = 1
DUI.RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(Installer.LOGIN_DELAY, function()
        if Installer.State() == nil and Installer.Needed() then Installer.Show() end
    end)
end)

-- Roles, talent sets, greetings

-- A usable game value, or nil when the call fails or the value is secret.
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- The role the game says this character plays ("HEALER", "TANK", "DAMAGER"),
-- or nil with no spec yet or when the game won't say.
function Installer.Role()
    local spec = plain(GetSpecialization)
    if spec then
        local role = plain(GetSpecializationRole, spec)
        if role == "HEALER" or role == "TANK" or role == "DAMAGER" then return role end
    end
    local role = plain(UnitGroupRolesAssigned, "player")
    if role == "HEALER" or role == "TANK" or role == "DAMAGER" then return role end
    return nil
end

-- The ready-made profile to recommend, or nil without a role.
function Installer.Recommended()
    local role = Installer.Role()
    if role == "HEALER" then return "Healer" end
    if role then return "DPS/Tank" end
    return nil
end

function Installer.CanHeal()
    local _, token = UnitClass("player")
    return token ~= nil and DUI.InstallerPages.HEALERS[token] == true
end

-- Shown on the role page when the game gives no role but the class can heal.
function Installer.HealHint()
    if not Installer.Recommended() and Installer.CanHeal() then
        return L["Your class can heal; pick Healer if you do."]
    end
end

function Installer.Greeting(hour)
    hour = tonumber(hour) or 12
    if hour >= 5 and hour < 12 then return L["Good morning, %s"] end
    if hour >= 12 and hour < 18 then return L["Good afternoon, %s"] end
    return L["Good evening, %s"]
end

-- "Good evening, First Last" with the name in class color. The last name is
-- left off when the client doesn't provide one (or hides it).
function Installer.GreetingText()
    local name = UnitName("player") or ""
    if type(UnitFullName) == "function" then
        local first, last = UnitFullName("player")
        local secret = issecretvalue and (issecretvalue(first) or issecretvalue(last))
        if not secret and type(first) == "string" and type(last) == "string" and last ~= "" then
            name = first .. " " .. last
        end
    end
    local _, token = UnitClass("player")
    local r, g, b = DUI.Style.RawClassColor(token)
    if r then
        name = string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5), name)
    end
    local hour = date and tonumber(date("%H"))
    return string.format(Installer.Greeting(hour), name)
end

-- The talent sets a choice is made for: both with dual spec, otherwise the
-- character's single choice.
function Installer.Slots()
    if DUI.DB.DualSpec() then return { 1, 2 } end
    return { "character" }
end

function Installer.CurrentSlot() return DUI.Profiles.CurrentSlot() end

function Installer.SlotLabel(slot)
    if slot == Installer.CurrentSlot() then return string.format(L["Talent set %s (in use)"], tostring(slot)) end
    return string.format(L["Talent set %s"], tostring(slot))
end

-- How a profile is labeled in the summary and on the role page's cards.
function Installer.RoleLabel(name)
    if name == "DPS/Tank" then return L["DPS / Tank"] end
    if name == "Healer" or name == "Immersive Preset" then return L[name] end -- the ready-made ones, saved under their English names
    return tostring(name)
end

-- A pack's profile (Profiles.RegisterPack) uses the name its pack gives it.
function Installer.RoleCardLabel(name)
    if Installer.ROLE_TEXT[name] or DUI.Profiles.PackOf(name) then return Installer.RoleLabel(name) end
    return string.format(L["Keep %s"], tostring(name))
end

function Installer.RoleSub(name)
    if Installer.ROLE_TEXT[name] then return Installer.ROLE_TEXT[name] end
    local entry = DUI.Profiles.PackOf(name)
    if entry then return entry.sub or entry.pack.desc or entry.pack.label end
    return L["Stay on this profile, as it is."]
end

-- Author credit for a pack profile's card tag ("by <author>"), or nil.
function Installer.PackCredit(name)
    local entry = DUI.Profiles.PackOf(name)
    local pack = entry and entry.pack
    if not pack then return nil end
    return string.format(L["by %s"], pack.author or pack.label)
end

-- Counts a setup's settings (nested tables key by key) that differ from the
-- defaults, and how many of those t matches. Settings equal to their default
-- say nothing about the setup, so they're skipped. Plain ifs are used because
-- "t and t[k] or nil" would turn a false setting into nil.
local function tally(t, values, defaults)
    local total, same = 0, 0
    for k, v in pairs(values) do
        local mine, default
        if type(t) == "table" then mine = t[k] end
        if type(defaults) == "table" then default = defaults[k] end
        if type(v) == "table" then
            local n, s = tally(mine, v, default)
            total, same = total + n, same + s
        elseif default ~= v then
            total = total + 1
            if mine == v then same = same + 1 end
        end
    end
    return total, same
end

-- How much of a ready-made setup (its settings that differ from defaults,
-- Profiles.PRESETS[key]) a profile's data contains, from 0 to 1. Plain
-- DPS/Tank scores 0, a fresh copy of the setup 1, and a slightly tweaked
-- copy stays near 1.
function Installer.PresetShare(p, key)
    local preset = DUI.Profiles.PRESETS[key]
    if type(p) ~= "table" or type(preset) ~= "table" then return 0 end
    local total, same = 0, 0
    for name, values in pairs(preset) do
        local mod = DUI:GetModule(name)
        local mine = type(p.modules) == "table" and p.modules[name] or nil
        local n, s = tally(mine, values, mod and mod.defaults)
        total, same = total + n, same + s
    end
    if total == 0 then return 0 end
    return same / total
end

-- The drawing for a profile: a ready-made one's own (a pack's uses the role
-- it declares), else Healer or Immersive Preset when it still has at least
-- half of that setup's settings (for a pack not created yet, its own settings).
function Installer.RoleShape(name)
    if Installer.ROLE_TEXT[name] then return name end
    local P = DUI.Profiles
    local entry = P.PackOf(name)
    if entry and entry.role then return entry.role end
    local p = DUI.DB.Root().profileData[name]
    if type(p) ~= "table" and entry then p = P.PackProfile(entry) end
    for _, key in ipairs({ "Healer", "Immersive Preset" }) do
        if Installer.PresetShare(p, key) >= 0.5 then return key end
    end
    return "DPS/Tank"
end

function Installer.RoleTag(name)
    local flow = Installer.flow
    if flow and flow.inUse and name == flow.inUse then return L["In use"] end
    if name == Installer.Recommended() then return L["Recommended for you"] end
    return Installer.PackCredit(name)
end

-- The role page's cards: the ready-made profiles (ours, then packs'), plus,
-- for an already set-up character, the profiles it uses if they're others.
function Installer.RoleChoices()
    local out, have = {}, {}
    for i, key in ipairs(Installer.READY) do
        out[i], have[key] = key, true
    end
    for _, name in ipairs(DUI.Profiles.PackNames()) do
        out[#out + 1], have[name] = name, true
    end
    local flow = Installer.flow
    if flow and flow.inUse then
        for _, slot in ipairs(Installer.Slots()) do
            local name = DUI.Profiles.Chosen(slot)
            if not have[name] then
                have[name] = true
                out[#out + 1] = name
            end
        end
    end
    return out
end

-- The tour's first pick for a talent set: what a set-up character uses, else
-- the recommended layout, else DPS / Tank.
function Installer.DefaultRole(slot)
    local flow = Installer.flow
    if flow and flow.inUse then return DUI.Profiles.Chosen(slot) end
    return Installer.Recommended() or "DPS/Tank"
end

-- The profile this character will be on (for the active talent set).
function Installer.Target()
    local flow = Installer.flow
    return flow and flow.roles[Installer.CurrentSlot()]
end

-- The flow

-- Tour pages for the chosen way in: all of them for the tour, the few marked
-- quick for Quick setup, none for a profile used as is.
function Installer.TourPages()
    local flow, P = Installer.flow, DUI.InstallerPages
    if flow and flow.path == "tour" then return P.Tour() end
    if flow and flow.path == "quick" then return P.Quick() end
    return {}
end

-- The pages for the chosen way in, in order: { { id, label } }.
function Installer.Steps()
    local flow = Installer.flow
    local out = { { id = "welcome", label = L["Welcome"] } }
    if flow and (flow.path == "tour" or flow.path == "quick") then
        for _, def in ipairs(Installer.TourPages()) do out[#out + 1] = { id = def.id, label = def.title } end
    end
    if flow and flow.path then out[#out + 1] = { id = "finish", label = L["Finish"] } end
    return out
end

function Installer.HasStep(id)
    for _, s in ipairs(Installer.Steps()) do
        if s.id == id then return true end
    end
    return false
end

function Installer.Show()
    if InCombatLockdown() then
        DUI.AfterCombat(Installer.Show, "installer show")
        return
    end
    local UI = DUI.InstallerUI
    if UI.IsShown() then return end
    local showcase = Installer.Showcase()
    local setUp = showcase or Installer.State() == "installed"
    Installer.flow = {
        mode = showcase and "showcase" or "new",
        inUse = setUp and DUI.DB.ActiveName() or nil,
        roles = {}, modules = {}, clashes = {}, visited = { welcome = true },
    }
    Installer.pages = {}
    UI.Open({
        close = Installer.OnClosed,
        next = Installer.Next,
        back = Installer.Back,
        again = function() if Installer.flow then Installer.Go(Installer.flow.page) end end,
    })
    Installer.Go("welcome")
end

-- Nothing is saved until the guide is finished (DB.Unsaved). The options
-- window and unlock mode show a button with this tooltip that opens the guide.
function Installer.UnsavedTip(owner)
    DUI.Widgets.Tooltip(owner, L["Changes aren't saved yet"],
        L["This character hasn't finished the setup guide, so what you change or move is lost when you log out. Finish the guide first, then make your changes."])
end
function Installer.OpenToSave()
    if DUI.Movers.unlocked then DUI.Movers.Lock() end
    local P = DUI.OptionsPanel
    if P and P.IsShown() then DUI.Motion.Vanish(P.Frame()) end
    Installer.Show()
end

-- One of the welcome's ways in: "quick" (arg is "DPS/Tank", "Healer" or
-- "Immersive Preset"), "tour", or "existing" / "keep" (arg is a profile name).
function Installer.Start(path, arg)
    local flow = Installer.flow
    if not flow then return end
    local P, D = DUI.InstallerPages, DUI.InstallerDraft
    if D.Active() then D.Revert() end
    flow.path, flow.finished, flow.saveAs = path, nil, nil
    flow.roles, flow.modules, flow.clashes, flow.extras, flow.bundles = {}, {}, {}, {}, {}
    Installer.pages.finish = nil
    for _, m in ipairs(P.MODULES) do
        if P.AddonInstalled(m.addon) then flow.modules[m.addon] = path == "quick" or P.AddonOn(m.addon) end
    end
    if path == "quick" or path == "tour" then
        for _, c in ipairs(P.Clashes()) do Installer.PickClash(c, "ours") end
    end
    if path == "quick" then
        for _, slot in ipairs(Installer.Slots()) do flow.roles[slot] = arg end
        -- Its few tour pages pick through the draft too, showing the setup's own
        -- values until the player picks.
        local quick = P.Quick()
        if #quick > 0 then
            D.Begin()
            for _, k in ipairs(P.Keys(quick)) do D.Track(k[1], k[2]) end
            D.Seed(Installer.Target())
            for _, def in ipairs(quick) do
                for _, s in ipairs(def.bundle and def.bundle.always or {}) do D.Set(s[1], s[2], s[3]) end
            end
        end
    elseif path == "tour" then
        for _, slot in ipairs(Installer.Slots()) do flow.roles[slot] = Installer.DefaultRole(slot) end
        D.Begin()
        for _, k in ipairs(P.Keys()) do D.Track(k[1], k[2]) end
        D.Seed(Installer.Target())
    else
        flow.roles[Installer.CurrentSlot()] = arg
    end
    Installer.Go(Installer.Steps()[2].id)
end

function Installer.PickRole(slot, name)
    local flow = Installer.flow
    if not flow then return end
    flow.roles[slot] = name
    if slot == Installer.CurrentSlot() then DUI.InstallerDraft.Seed(name) end
end

-- A bundle page's answer (InstallerPages). "yes" picks every setting in its
-- set, "no" (the default until answered) leaves them as the setup has them.
-- Its `always` settings are picked at Start regardless.
function Installer.Bundle(def)
    local flow = Installer.flow
    return flow and flow.bundles and flow.bundles[def.id] or "no"
end

function Installer.PickBundle(def, answer)
    local flow = Installer.flow
    if not (flow and flow.bundles) then return end
    local D = DUI.InstallerDraft
    flow.bundles[def.id] = answer
    for _, s in ipairs(def.bundle.set) do
        local can = s.addon == nil or DUI.InstallerPages.AddonOn(s.addon)
        if answer == "yes" and can then D.Set(s[1], s[2], s[3]) else D.Unpick(s[1], s[2]) end
    end
    if answer ~= "yes" then D.Seed(Installer.Target()) end
end

-- A module's switch. Sets our module on or off and answers every clashing
-- addon the same way (on = ours, off = theirs), so the cards never disagree
-- with the tile.
function Installer.SetModule(mod, on)
    local flow = Installer.flow
    if not (flow and mod) then return end
    flow.modules[mod.addon] = on
    for _, c in ipairs(DUI.InstallerPages.Clashes()) do
        if c.module == mod.name then flow.clashes[c.addon] = on and "ours" or "theirs" end
    end
    local page = Installer.pages and Installer.pages.modules
    if page and page.Refresh then page.Refresh() end
end

-- A clash's answer. "ours" turns our module on (and the other addon off at
-- Finish), "theirs" turns ours off. Sibling clashes follow.
function Installer.PickClash(clash, v)
    local flow = Installer.flow
    if not flow then return end
    local mod = DUI.InstallerPages.Module(clash.module)
    if mod and DUI.InstallerPages.AddonInstalled(mod.addon) then
        Installer.SetModule(mod, v == "ours")
        return
    end
    flow.clashes[clash.addon] = v
    local page = Installer.pages and Installer.pages.modules
    if page and page.Refresh then page.Refresh() end
end

-- Whether Finish turns this clash's other addon off: only when answered
-- "ours" and our module for it ends up installed and on, so a player is never
-- left with neither.
function Installer.ClashTakesOver(clash)
    local flow, P = Installer.flow, DUI.InstallerPages
    if not flow or flow.clashes[clash.addon] ~= "ours" then return false end
    local mod = P.Module(clash.module)
    if not (mod and P.AddonInstalled(mod.addon)) then return false end
    local want = flow.modules[mod.addon]
    if want == nil then want = P.AddonOn(mod.addon) end
    return want == true
end

-- Pages are built once per session and reused (frames can't be freed and a
-- page's listeners can't be removed), keyed by what they were built for: the
-- width, plus for the welcome and role pages the setup they show (way in,
-- profiles, talent sets). When a new run reuses a page, its Reset() restores
-- its own state.
local built = {}

local function shape(id)
    local P = DUI.Profiles
    if id == "welcome" then
        local flow = Installer.flow
        local showcase = flow.mode == "showcase"
        return table.concat({ flow.mode, tostring(Installer.Recommended() or ""),
            table.concat(showcase and P.Names() or Installer.ExistingProfiles(), ","),
            table.concat(P.PackNames(), ",") }, "|")
    elseif id == "role" then
        local keys, shapes = Installer.RoleChoices(), {}
        for i, k in ipairs(keys) do shapes[i] = Installer.RoleShape(k) end
        return table.concat({ table.concat(keys, ","), table.concat(shapes, ","),
            table.concat(Installer.Slots(), ","), tostring(Installer.CurrentSlot()),
            tostring(Installer.HealHint() or "") }, "|")
    end
    return ""
end

local function pageFor(id, width)
    local key = id .. "@" .. width .. "@" .. shape(id)
    local page = built[key]
    if not page then
        page = DUI.InstallerSteps.Build(id, DUI.InstallerUI.Body(), width)
        built[key] = page
    elseif page.Reset then
        page.Reset()
    end
    return page
end

function Installer.Go(id)
    local flow = Installer.flow
    if not flow then return end
    if flow.finished then id = "finish" end
    local UI, P = DUI.InstallerUI, DUI.InstallerPages
    local steps = Installer.Steps()
    local i = 1
    for n, s in ipairs(steps) do
        if s.id == id then i = n end
    end
    id = steps[i].id
    local dir = (flow.index and i < flow.index) and -1 or 1
    local def = P.Get(id)
    flow.page, flow.index = id, i
    flow.visited[id] = true
    local tour = flow.path == "tour"
    local page = Installer.pages[id]
    if not page then
        page = pageFor(id, UI.ContentWidth(id ~= "welcome" and tour))
        Installer.pages[id] = page
    end
    -- The game stays dimmed behind every step so the guide is the focus.
    local opts = { dir = dir, veil = true }
    if id == "welcome" then
        opts.full = true
    elseif id == "finish" then
        opts.rail = tour
        opts.title, opts.desc = Installer.FinishWords()
        opts.back = not flow.finished
    else
        -- Quick setup's one or two pages skip the step list.
        opts.rail = tour
        if tour then opts.step, opts.total = i - 1, #steps - 2 end
        opts.title, opts.desc = def.title, def.desc
        opts.later = P.Later(def)
        opts.back = true
        opts.next = i == #steps - 1 and L["Review"] or (NEXT or L["Next"])
    end
    UI.SetPage(page, opts)
    if page.Refresh then page.Refresh() end
    if id == "finish" and page.ended ~= nil then page.ShowEnd(page.ended) end
    if opts.rail then UI.SetRail(steps, i, flow.visited, Installer.Go) end
    UI.Spotlight(def and def.spotlight or nil)
end

-- The finish page's header, before Finish and after it has run.
function Installer.FinishWords()
    if Installer.flow and Installer.flow.finished then
        return L["All set"], L["Everything's in place."]
    end
    return L["Ready when you are"], L["Here's what Finish will do. Nothing has been saved yet."]
end

function Installer.Next()
    local flow = Installer.flow
    if not flow then return end
    local steps = Installer.Steps()
    local s = steps[(flow.index or 1) + 1]
    if s then Installer.Go(s.id) end
end

function Installer.Back()
    local flow = Installer.flow
    if not flow then return end
    local steps = Installer.Steps()
    local s = steps[(flow.index or 2) - 1]
    if s then Installer.Go(s.id) end
end

-- The summary

-- An option's name and current value, e.g. "Accent color (Class color)".
local function describe(scope, key, label)
    local _, item = DUI.InstallerPages.Find(scope, key)
    if not item then return nil end
    local v = DUI:Get(scope, key)
    local text
    if item.type == "toggle" then
        if item.invert then v = v ~= true end -- "Show X": on means you see it
        text = v == true and L["on"] or L["off"]
    elseif item.type == "dropdown" then
        local values = item.values
        if item.choices then values = item.choices() end
        text = type(values) == "table" and DUI.Options.Text(values[v]) or nil
    elseif type(v) == "number" then
        text = tostring(math.floor(v * 100 + 0.5) / 100)
    end
    label = label or DUI.Options.Label(item) or key
    if text then return string.format(L["%s (%s)"], label, tostring(text)) end
    return label
end

-- The player's own picks on one tour page, described.
local function picksOn(def)
    local P, D = DUI.InstallerPages, DUI.InstallerDraft
    local out = {}
    if def.bundle then out[#out + 1] = L[def.bundle.summary[Installer.Bundle(def)]] end
    for _, g in ipairs(def.groups or {}) do
        if P.GroupAvailable(g) and g.presets then
            local picked = false
            for _, r in ipairs(P.Refs(g)) do picked = picked or D.Picked(r[1], r[2]) end
            local p = picked and P.PresetOn(g)
            if p then out[#out + 1] = string.format(L["%s (%s)"], DUI.Options.Text(g.label), DUI.Options.Text(p.label)) end
        elseif P.GroupAvailable(g) then
            local key = g.portraits and "player." .. P.PortraitKey(g)
            if key and D.Picked("UnitFrames", key) then
                out[#out + 1] = describe("UnitFrames", key, g.portraits == true and L["Portraits"] or nil)
            end
            for _, r in ipairs(P.Refs(g)) do
                if D.Picked(r[1], r[2]) then out[#out + 1] = describe(r[1], r[2]) end
            end
        end
    end
    return out
end

local function joinNames(list, most)
    if #list <= most then return table.concat(list, ", ") end
    local first = {}
    for i = 1, most do first[i] = list[i] end
    return string.format(L["%s and %d more"], table.concat(first, ", "), #list - most)
end

-- What Finish will do, one line per part: { text, label, value, page }. Either
-- a whole sentence, or a name and its value; page is the step to change it
-- on, if any.
function Installer.Summary()
    local flow = Installer.flow
    local P = DUI.InstallerPages
    local out = {}
    local slots = Installer.Slots()
    local rolePage = Installer.HasStep("role") and "role" or "welcome"
    for _, slot in ipairs(slots) do
        local name = flow.roles[slot]
        if name then
            local text = string.format(L["Layout and profile: %s"], Installer.RoleLabel(name))
            local label = L["Layout and profile"]
            if #slots > 1 then
                text = string.format(L["%s: %s"], Installer.SlotLabel(slot), text)
                label = Installer.SlotLabel(slot)
            end
            out[#out + 1] = { text = text, label = label, value = Installer.RoleLabel(name), page = rolePage }
        end
    end
    if flow.path == "quick" then out[#out + 1] = { text = L["Everything switched on, with Daylight UI's own look."] } end
    if flow.path == "existing" or flow.path == "keep" then
        out[#out + 1] = { text = L["The profile is used as it is; nothing in it changes."] }
    end
    local on, off, others = {}, {}, {}
    for _, m in ipairs(P.MODULES) do
        local want = flow.modules[m.addon]
        if want ~= nil and want ~= P.AddonOn(m.addon) then
            if want then on[#on + 1] = L[m.label] else off[#off + 1] = L[m.label] end
        end
    end
    for _, c in ipairs(P.Clashes()) do
        if Installer.ClashTakesOver(c) then others[#others + 1] = c.label end
    end
    local modPage = Installer.HasStep("modules") and "modules" or nil
    local function add(fmt, label, names, page)
        out[#out + 1] = { text = string.format(fmt, names), label = label, value = names, page = page }
    end
    if #on > 0 then add(L["Switches on: %s"], L["Switches on"], joinNames(on, 4), modPage) end
    if #off > 0 then add(L["Switches off: %s"], L["Switches off"], joinNames(off, 4), modPage) end
    if #others > 0 then
        add(L["Turns off, as DaylightUI does their job: %s"], L["Turns off"], joinNames(others, 3), modPage)
    end
    if flow.path == "tour" or flow.path == "quick" then
        for _, def in ipairs(Installer.TourPages()) do
            local picks = picksOn(def)
            if #picks > 0 then
                local names = joinNames(picks, 3)
                out[#out + 1] = { text = string.format(L["%s: %s"], L[def.title], names), label = L[def.title], value = names, page = def.id }
            end
        end
    end
    return out
end

-- A profile (or ready-made one) matching name case-insensitively. Returns its
-- real name, or nil.
local function named(name)
    local low = string.lower(name)
    for n in pairs(DUI.DB.Root().profileData) do
        if string.lower(n) == low then return n end
    end
    for _, n in ipairs(DUI.Profiles.ReadyNames()) do
        if string.lower(n) == low then return n end
    end
end

-- The tour's "Save your setup as": what the player typed, else the
-- character's name when the picked layout is a ready-made one (so the picks
-- don't change a profile other characters may share), else the picked
-- profile's own name. Nil outside the tour.
function Installer.SaveAs()
    local flow = Installer.flow
    if not (flow and flow.path == "tour") then return nil end
    if flow.saveAs then return flow.saveAs end
    local target = Installer.Target()
    if target and not DUI.Profiles.IsReady(target) then return target end
    local me = UnitName("player")
    return type(me) == "string" and me ~= "" and me or target
end

-- Whether Finish rebuilds the saved profile `have` from the picked layout:
-- true when the picked card is a different layout ("Keep" leaves it as is).
local function rebuilds(have, picked)
    return picked ~= nil and have ~= picked and type(DUI.DB.Root().profileData[have]) == "table"
end

-- Under the tour's name box: where the picks go and who else that affects.
function Installer.SaveNote()
    local name = Installer.SaveAs()
    name = name and strtrim(name)
    if not name or name == "" then return nil end
    local have = named(name)
    local picked = Installer.Target()
    if not have then
        return string.format(L["A new profile, made from %s with your picks."], Installer.RoleLabel(picked))
    end
    local me, others = DUI.DB.CharKey(), {}
    for _, key in ipairs(DUI.Profiles.UsersOf(have)) do
        if key ~= me then others[#others + 1] = string.match(key, "^([^%-]+)") or key end
    end
    if rebuilds(have, picked) then
        if #others == 0 then
            return string.format(L["%s is made again from %s, with your picks."], Installer.RoleLabel(have),
                Installer.RoleLabel(picked))
        end
        return string.format(L["%s is shared with %s; it's made again from %s for them too."], Installer.RoleLabel(have),
            table.concat(others, ", "), Installer.RoleLabel(picked))
    end
    if #others == 0 then return string.format(L["Your picks are saved into %s."], Installer.RoleLabel(have)) end
    return string.format(L["%s is shared with %s; the picks here change it for them too."], Installer.RoleLabel(have),
        table.concat(others, ", "))
end

-- Finish

-- A choice's profile, created first if it's a ready-made one that doesn't
-- exist yet. Returns its name, or nil and a reason.
local function resolve(name)
    if not name then return nil, L["pick a layout first"] end
    if DUI.Profiles.IsReady(name) then return DUI.Profiles.AddPreset(name) end
    if type(DUI.DB.Root().profileData[name]) == "table" then return name end
    return nil, string.format(L["there's no profile called %s"], tostring(name))
end

-- The picked layout as an unsaved profile table: a ready-made one built clean
-- (never the saved copy, which may have been edited), else a copy of the
-- picked profile. Returns nil and a reason on failure.
local function fromPick(picked)
    local P = DUI.Profiles
    if P.IsReady(picked) then return P.ReadyData(picked) end
    local from, why = resolve(picked)
    if not from then return nil, why end
    return P.Build(nil, from)
end

-- The tour's profile: the one named in "Save your setup as" if it exists (any
-- case). If a different layout was picked, it's rebuilt from that layout
-- (returned third, for Finish to swap in with the picks). Otherwise a new
-- profile with that name, made from the picked layout. Returns its name, or
-- nil and a reason.
local function saveAs(picked)
    local name = strtrim(Installer.SaveAs() or "")
    if name == "" then return nil, L["give your setup a name"] end
    local have = named(name)
    local why
    if have and rebuilds(have, picked) then
        local fresh
        fresh, why = fromPick(picked)
        if not fresh then return nil, why end
        return have, nil, fresh
    end
    if have then return resolve(have) end
    name, why = DUI.Profiles.CheckName(name)
    if not name then return nil, why end
    if not picked then return nil, L["pick a layout first"] end
    local fresh
    fresh, why = fromPick(picked)
    if not fresh then return nil, why end
    DUI.DB.Root().profileData[name] = fresh
    return name
end

-- Installs the profile's Edit Mode layout (the standard one for DPS / Tank,
-- the profile's own for the rest). Returns ok, whether it wrote anything, and
-- a reason on failure.
local function placeLayout(target)
    if target == DUI.DB.ActiveName() and EditMode.IsActive(target) then return true, false end
    local ok, why
    if target == "DPS/Tank" then
        ok, why = EditMode.Install(nil, target)
    else
        ok, why = EditMode.UseProfile(target)
    end
    if not ok then return false, false, why end
    return true, true
end

-- Other addons a picked pack profile's pack sets up (its extras), only the
-- loaded ones, as { key, extra }. Quick setup and the tour only; a profile
-- used as is changes nothing.
function Installer.Extras()
    local flow = Installer.flow
    local out, seen = {}, {}
    if not (flow and (flow.path == "quick" or flow.path == "tour")) then return out end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    for _, slot in ipairs(Installer.Slots()) do
        local entry = DUI.Profiles.PackOf(flow.roles[slot])
        local pack = entry and entry.pack
        if pack and not seen[pack.id] then
            seen[pack.id] = true
            for i, x in ipairs(pack.extras) do
                if loaded and loaded(x.addon) then out[#out + 1] = { key = pack.id .. ":" .. i, extra = x } end
            end
        end
    end
    return out
end

-- An extra is on until the player turns it off.
function Installer.ExtraOn(key)
    local flow = Installer.flow
    return flow ~= nil and (flow.extras or {})[key] ~= false
end

function Installer.SetExtra(key, on)
    local flow = Installer.flow
    if flow and flow.extras then flow.extras[key] = on == true end
end

-- Runs the extras left on, each separately so one failing doesn't stop the
-- rest. True if any ran; the other addons pick up their settings on reload.
local function applyExtras()
    local ran = false
    for _, x in ipairs(Installer.Extras()) do
        if Installer.ExtraOn(x.key) then
            DUI.SafeCall(x.extra.apply)
            ran = true
        end
    end
    return ran
end

-- Turns modules (and clashing addons) on or off for this character where
-- something changed. True if anything did.
local function applyModules(flow)
    local api = C_AddOns
    if not (api and api.EnableAddOn and api.DisableAddOn) then return false end
    local P = DUI.InstallerPages
    local me = P.Character()
    if not me then return false end
    local changed = false
    for _, m in ipairs(P.MODULES) do
        local want = flow.modules[m.addon]
        if want ~= nil and want ~= P.AddonOn(m.addon) then
            if want then api.EnableAddOn(m.addon, me) else api.DisableAddOn(m.addon, me) end
            changed = true
        end
    end
    for _, c in ipairs(P.Clashes()) do
        if Installer.ClashTakesOver(c) and P.AddonOn(c.addon) then
            api.DisableAddOn(c.addon, me)
            changed = true
        end
    end
    return changed
end

function Installer.Finish()
    local flow = Installer.flow
    if not flow or flow.finished or not flow.path then return end
    local page = Installer.pages.finish
    local function say(text) if page and page.Status then page.Status(text) end end
    if InCombatLockdown() then
        say(L["You're in combat; this finishes as soon as it ends."])
        DUI.AfterCombat(Installer.Finish, "installer")
        return
    end
    if EditMode.GamepadMode() then
        say(L["Controller mode is on. Turn it off (Options > Controller), press Finish, then turn it back on."])
        return
    end
    local P, D = DUI.Profiles, DUI.InstallerDraft
    local active = DUI.DB.ActiveName()
    local slot = Installer.CurrentSlot()
    local target, why, fresh
    if flow.path == "tour" then
        target, why, fresh = saveAs(flow.roles[slot])
    else
        target, why = resolve(flow.roles[slot])
    end
    if not target then
        say(string.format(L["Couldn't finish: %s."], tostring(why)))
        return
    end
    -- Rebuilt: the picks on screen go in first (the active profile may be this
    -- very one), then it replaces the old one.
    if fresh then
        D.CopyInto(fresh)
        P.Replace(target, fresh)
    end
    local ok, written, err = placeLayout(target)
    if not ok then
        say(string.format(L["Couldn't place the layout: %s. Then press Finish again."], tostring(err)))
        return
    end
    say(nil)
    local reload = written or fresh ~= nil or target ~= active or D.NeedsReload()
    if D.Active() then D.Commit(target) end
    for _, s in ipairs(Installer.Slots()) do
        local name = flow.roles[s]
        -- A talent set on the same pick as the active one goes where that one went.
        if s == slot or (name ~= nil and name == flow.roles[slot]) then
            name = target
        elseif name then
            name = resolve(name)
        end
        if name then P.Assign(s, name) end
    end
    if applyModules(flow) then reload = true end
    if applyExtras() then reload = true end
    -- Plugins' pages that set up something of their own (another addon).
    for _, def in ipairs(Installer.TourPages()) do
        if type(def.onFinish) == "function" then
            DUI.SafeCallAs(def.plugin or L["an addon"], def.onFinish)
            reload = true
        end
    end
    Installer.Mark("installed")
    Installer.MarkSeen()
    -- After the reload (or the guide closing without one), ask "Take a tour?" (Tour.lua).
    DUI.DB.Character().tourOffer = true
    flow.finished, flow.reload = true, reload
    DUI.InstallerUI.Spotlight(nil)
    local title, desc = Installer.FinishWords()
    DUI.InstallerUI.Retitle(title, desc, false)
    if page and page.RunChecklist then page.RunChecklist(reload) end
end

-- When the secure Reload button can't be shown (in combat, or the client
-- refuses), fall back to the game's popup like the old installer.
function Installer.ReloadPopup()
    DUI.InstallerUI.QuietHide()
    Installer.flow = nil
    Installer.ReleaseHeld(true)
    EditMode.AskReload(L["DaylightUI is set up on this character. Reload to put it in place?"])
end

-- Finished with nothing to reload.
function Installer.Done()
    DUI.InstallerUI.QuietHide()
    Installer.flow = nil
    Installer.ReleaseHeld()
    if DUI.Tour then DUI.Tour.Offer() end
end

-- The player closed the guide (X or Escape), so undo every preview.
function Installer.OnClosed()
    local flow = Installer.flow
    Installer.flow = nil
    if DUI.InstallerDraft.Active() then DUI.InstallerDraft.Revert() end
    if flow and flow.testMode then DUI.SetTestMode(false) end
    if flow and (flow.mode == "showcase" or flow.finished) then Installer.MarkSeen() end
    if flow and not flow.finished then dismissed = true end
    Installer.ReleaseHeld()
end

-- While the guide is open, other reload prompts (EditMode.AskReload,
-- Profiles.AskReload) wait: Finish reloads anyway, and closing the guide
-- shows them then. fn shows the prompt; returns true when it's held.
function Installer.HoldReload(fn)
    if not (DUI.InstallerUI and DUI.InstallerUI.IsShown()) then return false end
    held = fn
    return true
end

function Installer.ReleaseHeld(drop)
    local fn = held
    held = nil
    if fn and not drop then fn() end
end

-- Without the window

-- For scripts and tests. preset is a ready-made profile ("DPS/Tank" by
-- default, "Healer" or "Immersive Preset"), or Installer.EXISTING with
-- existing naming a profile to use as is. Ends with the reload popup.
function Installer.Install(preset, existing)
    if InCombatLockdown() then
        DUI.Print(L["Can't install in combat; it'll wait until you're out."])
        DUI.AfterCombat(function() Installer.Install(preset, existing) end, "installer")
        return
    end
    if EditMode.GamepadMode() then
        DUI.Print(L["Can't install while controller mode is on: turn it off (Options > Controller), /dui install, then turn it back on."])
        return
    end
    if DUI.InstallerUI.IsShown() then
        if DUI.InstallerDraft.Active() then DUI.InstallerDraft.Revert() end
        DUI.InstallerUI.QuietHide()
        Installer.flow = nil
    end
    local P = DUI.Profiles
    if preset == Installer.EXISTING then
        local found = false
        for _, name in ipairs(Installer.ExistingProfiles()) do
            if name == existing then found = true end
        end
        if not found then
            DUI.Print(L["Couldn't install: pick a profile first."])
            return
        end
        P.Assign(P.CurrentSlot(), existing)
        Installer.Mark("installed")
        Installer.MarkSeen()
        P.SwitchNow(existing)
        return
    end
    preset = preset or "DPS/Tank"
    local made, why = P.AddPreset(preset)
    if not made then
        DUI.Print(string.format(L["Couldn't install: %s."], tostring(why)))
        return
    end
    P.Assign(P.CurrentSlot(), made)
    local ok
    if preset == "DPS/Tank" then
        ok, why = EditMode.Install(nil, made)
    else
        ok, why = EditMode.UseProfile(made)
    end
    if not ok then
        DUI.Print(string.format(L["Couldn't install: %s. Then /dui install again."], tostring(why)))
        return
    end
    Installer.Mark("installed")
    Installer.MarkSeen()
    DUI.DB.Character().tourOffer = true
    EditMode.AskReload(L["DaylightUI is set up on this character. Reload to put it in place?"])
end

DUI.RegisterCommand("install", function() Installer.Show() end,
    L["/dui install - the setup guide: set this character up, or take the tour again"])
