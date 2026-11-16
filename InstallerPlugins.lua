-- Plugins' own setup guides, the way ElvUI plugins have theirs. Once Daylight
-- UI is set up on a character, every plugin guide the player hasn't been
-- through yet shows in the setup guide's window, one plugin after another,
-- then the tour is offered. A plugin adds one with me.AddInstaller (API.md);
-- raising its version shows it again to characters that already saw it.
--
-- Settings rows on these pages are a draft like the main guide's: closing
-- the window puts them back. Buttons act at once. Closing a plugin's guide
-- counts as seen, so it never asks again at every login; me.ShowInstaller
-- and General > Plugins open it again.
--
-- Saved: the version each plugin's guide was seen at, in
-- DB.Character().pluginGuides (DB.Root() for a guide with account = true).

local _, DUI = ...
local L = DUI.L

local PI = {}
DUI.InstallerPlugins = PI

PI.list, PI.order = {}, {}
PI.LOGIN_DELAY = 1 -- after login, before the tour asks (Tour.ASK_DELAY)

local run -- the guides showing now

local function seenIn(e)
    local t = e.account and DUI.DB.Root() or DUI.DB.Character()
    if type(t.pluginGuides) ~= "table" then t.pluginGuides = {} end
    return t.pluginGuides
end

function PI.Seen(e) return (tonumber(seenIn(e)[e.plugin]) or 0) >= e.version end
function PI.MarkSeen(e) seenIn(e)[e.plugin] = e.version end

-- False (and why) when the guide can't be taken.
function PI.Add(plugin, spec)
    if type(spec) ~= "table" or type(spec.pages) ~= "table" or #spec.pages == 0 then
        return false, "a guide needs pages"
    end
    local P = DUI.InstallerPages
    local pages = {}
    for i, def in ipairs(spec.pages) do
        if type(def) ~= "table" or type(def.title) ~= "string" or not P.HasContent(def) then
            return false, string.format("page %d needs a title, and groups, text, image, buttons or build", i)
        end
        local copy = {}
        for k, v in pairs(def) do copy[k] = v end
        copy.plugin, copy.id = plugin, nil
        pages[i] = copy
    end
    local p = DUI.Plugins and DUI.Plugins.list[plugin]
    local e = PI.list[plugin]
    if not e then
        e = { plugin = plugin }
        PI.list[plugin] = e
        PI.order[#PI.order + 1] = plugin
    end
    e.title = type(spec.title) == "string" and spec.title or (p and p.title) or plugin
    e.version = type(spec.version) == "number" and spec.version or 1
    e.account = spec.account == true
    e.pages, e.onFinish, e.reload = pages, spec.onFinish, spec.reload == true
    return true
end

-- The pages that can show now (a page of settings needs their module loaded).
local function pagesOf(e)
    local out = {}
    for _, def in ipairs(e.pages) do
        if DUI.InstallerPages.Available(def) then out[#out + 1] = def end
    end
    return out
end

function PI.Has(plugin)
    local e = PI.list[plugin]
    return e ~= nil and #pagesOf(e) > 0
end

-- Every guide not seen yet at its version, in the order they were added.
function PI.Due()
    local out = {}
    for _, name in ipairs(PI.order) do
        local e = PI.list[name]
        if not PI.Seen(e) and #pagesOf(e) > 0 then out[#out + 1] = e end
    end
    return out
end

function PI.Running() return run ~= nil end

local function begin(e)
    local D = DUI.InstallerDraft
    run.entry, run.defs, run.pages, run.visited, run.page = e, pagesOf(e), {}, {}, nil
    D.Begin()
    for _, k in ipairs(DUI.InstallerPages.Keys(run.defs)) do D.Track(k[1], k[2]) end
    PI.Go(1)
end

-- Shows the given guides one after another. False when the window is busy.
function PI.Start(list)
    if not list or #list == 0 then return false end
    if InCombatLockdown() then
        DUI.AfterCombat(function() PI.Start(list) end, "plugin guides")
        return true
    end
    local UI = DUI.InstallerUI
    if UI.IsShown() then return false end
    run = { queue = list, at = 0, reload = false }
    UI.Open({
        close = PI.OnClosed,
        next = PI.Next,
        back = PI.Back,
        again = function() if run and run.page then PI.Go(run.page) end end,
    })
    PI.NextGuide()
    return true
end

-- The guides due on a set-up character. True when they show.
function PI.ShowDue()
    local I = DUI.Installer
    if I.State() ~= "installed" or I.ShowcaseDue() then return false end
    return PI.Start(PI.Due())
end

function PI.Show(plugin)
    local e = PI.list[plugin]
    if not (e and #pagesOf(e) > 0) then return false end
    return PI.Start({ e })
end

function PI.NextGuide()
    run.at = run.at + 1
    local e = run.queue[run.at]
    if e then begin(e) else PI.Done() end
end

function PI.Go(i)
    if not run then return end
    local UI, P = DUI.InstallerUI, DUI.InstallerPages
    local defs = run.defs
    i = math.max(1, math.min(#defs, i))
    local dir = (run.page and i < run.page) and -1 or 1
    run.page = i
    run.visited[i] = true
    local rail = #defs > 1
    local page = run.pages[i]
    if not page then
        page = DUI.InstallerSteps.BuildDef(defs[i], UI.Body(), UI.ContentWidth(rail))
        run.pages[i] = page
    end
    local def = defs[i]
    local opts = {
        dir = dir, veil = true, rail = rail, over = run.entry.title,
        title = def.title, desc = def.desc, later = P.Later(def), back = i > 1,
        next = i == #defs and L["Finish"] or (NEXT or L["Next"]),
    }
    if rail then opts.step, opts.total = i, #defs end
    UI.SetPage(page, opts)
    if page.Refresh then page.Refresh() end
    if rail then
        local steps = {}
        for n, d in ipairs(defs) do steps[n] = { id = n, label = d.title } end
        UI.SetRail(steps, i, run.visited, PI.Go)
    end
    UI.Spotlight(def.spotlight)
end

function PI.Back()
    if run and run.page and run.page > 1 then PI.Go(run.page - 1) end
end

-- Next, or Finish on the last page: the picks stay in the profile in use, the
-- plugin's onFinish runs (true back from it asks for a reload), on to the next.
function PI.Next()
    if not run then return end
    if run.page < #run.defs then return PI.Go(run.page + 1) end
    if InCombatLockdown() then
        DUI.AfterCombat(PI.Next, "plugin guides")
        return
    end
    local e, D = run.entry, DUI.InstallerDraft
    if D.NeedsReload() or e.reload then run.reload = true end
    if D.Active() then D.Commit(DUI.DB.ActiveName()) end
    if type(e.onFinish) == "function" then
        local again
        DUI.SafeCallAs(e.title, function() again = e.onFinish() end)
        if again == true then run.reload = true end
    end
    PI.MarkSeen(e)
    PI.NextGuide()
end

-- Every guide done: one reload for all of them if any needs it, else the tour.
local function wrapUp(reload)
    DUI.InstallerUI.Spotlight(nil)
    if reload then
        DUI.Widgets.Ask({ key = "pluginGuides", reload = true,
            text = L["Your plugins are set up. Reload to put everything in place?"] })
    elseif DUI.Tour then
        DUI.Tour.Offer()
    end
end

function PI.Done()
    local reload = run.reload
    run = nil
    DUI.InstallerUI.QuietHide()
    wrapUp(reload)
end

-- X or Escape: this guide's picks go back and it counts as seen; the rest
-- wait for the next login.
function PI.OnClosed()
    if not run then return end
    local reload, e = run.reload, run.entry
    run = nil
    if DUI.InstallerDraft.Active() then DUI.InstallerDraft.Revert() end
    if e then PI.MarkSeen(e) end
    wrapUp(reload)
end

DUI.RegisterEvent("PLAYER_LOGIN", function()
    C_Timer.After(PI.LOGIN_DELAY, PI.ShowDue)
end)
