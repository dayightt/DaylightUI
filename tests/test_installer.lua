local stub = require("stub")
local ABW = require("abworld")

-- The game's saved layouts (tests/abworld.lua), fresh with every login.
local saved
-- tests/test_installer_new.lua runs every test again with the new action bars.
local function world() saved = ABW.world() end
local layoutNamed = ABW.layoutNamed

-- A login with the action bars (they give Edit Mode a part, so the layouts
-- event reaches the installer). opts as stub.Load's; opts.before runs after
-- the world is built. One talent set, no spec, unless a test says so.
local function login(opts)
    opts = opts or {}
    opts.actionbars = true
    local before = opts.before
    opts.before = function()
        world()
        _G.GetNumSpecGroups = function() return opts.specGroups or 1 end
        _G.C_SpecializationInfo = nil
        _G.GetSpecialization, _G.GetSpecializationRole = nil, nil
        _G.UnitGroupRolesAssigned = function() return "NONE" end   -- another test file may have left its own
        if before then before() end
    end
    return stub.Load(opts)
end

-- The next session: the saved settings and the game's layouts as they were.
local function reload(opts)
    local db = DaylightUIDB
    ABW.carry = saved
    opts = opts or {}
    local before = opts.before
    opts.before = function()
        _G.DaylightUIDB = db
        if before then before() end
    end
    return login(opts)
end

local function press(b) b:GetScript("OnClick")(b, "LeftButton") end
-- The opening: a click picks a card, the big button under the cards starts it.
local function choose(DUI, key) DUI.Installer.pages.welcome.Pick(key) end
local function go(DUI) press(DUI.Installer.pages.welcome.go) end
local function card(DUI, key)
    for _, c in ipairs(DUI.Installer.pages.welcome.cards) do if c.key == key then return c end end
end

-- Lets every tween and lift run to its end.
local function settle(DUI)
    for _ = 1, 120 do
        stub.Advance(0.05)
        for _, d in ipairs({ DUI.Motion.Driver(), DUI.Win.Feel.Driver() }) do
            local tick = d and d:GetScript("OnUpdate")
            if tick then tick(d, 0.05) end
        end
    end
    stub.RunTimers()
end

local function question(n, over)
    local q = { part = "Test", ask = "Which?", what = "A thing.", step = 2, total = 5, nextText = "Next", current = "b", choices = {} }
    for i = 1, n do
        local k = string.char(96 + i)
        q.choices[i] = { key = k, name = "Choice " .. k, line = "Line " .. k,
            picture = function(parent, w) local f = CreateFrame("Frame", nil, parent); f:SetSize(w, 100); return f end,
            closed = function(parent) local f = CreateFrame("Frame", nil, parent); f:SetSize(14, 150); return f end }
    end
    for k, v in pairs(over or {}) do q[k] = v end
    return q
end

local function plainText(fs) return (fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
-- A summary line on the finish page as drawn: "name: value", or its sentence.
local function lineText(l)
    local value = l.value:GetText() or ""
    if l.name:IsShown() then return (l.name:GetText() or "") .. ": " .. value end
    return value
end
-- The player closing the guide fades it out first (Motion.Vanish); the
-- fade's end (its OnFinished) stands in for the time passing.
local function fadeDone()
    local m = DaylightUIInstaller.__duiMotion
    local g = m and m.vanish
    local fn = g and g:GetScript("OnFinished")
    if fn then fn(g) end
end
local function closeGuide() press(DaylightUIInstaller.close); fadeDone() end
local function escapeGuide() DaylightUIInstaller:GetScript("OnKeyDown")(DaylightUIInstaller, "ESCAPE"); fadeDone() end

T.test("installer: the shared test world takes our layout", function()
    local DUI = login()
    DUI.Installer.Install()
    T.truthy(layoutNamed("DaylightUI - DPS/Tank"), "written into the shared world")
    T.eq(saved.activeLayout, 3, "and made active")
end)

T.test("installer: a reload keeps the saved settings and the game's layouts", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    T.truthy(layoutNamed("DaylightUI - DPS/Tank"), "the layout still there")
    T.eq(DUI.DB.ActiveName(), "DPS/Tank", "the character on the profile it chose")
end)

-- Players got "Reload to put it in place?" right after the setup guide's own
-- reload. The bundled layout (EditModeBase.lua) keeps the extra and
-- leave-vehicle buttons at the game's spots, which the addon moves, so a
-- layout copied from it unchanged looked out of date at the next login.
T.test("installer: a layout set up from the bundled one is up to date, so no second reload is asked", function()
    local function bundled()
        Enum.EditModeSystem.ExtraAbilities = 5
        C_EditMode.ConvertStringToLayoutInfo = function(s)
            if s ~= DaylightUI.EditMode.BASE then return nil end
            local systems = {}
            for i = 1, 4 do systems[i] = { system = 0, systemIndex = i, settings = {}, anchorInfo = { point = "BOTTOM" } } end
            for _, sys in ipairs({ 5, 9 }) do
                systems[#systems + 1] = { system = sys, settings = {}, isInDefaultPosition = true,
                    anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = -4 } }
            end
            return { layoutName = "bigboy", layoutType = 1, systems = systems }
        end
    end
    local DUI = login({ before = bundled })
    DUI.Installer.Install()
    T.truthy(DUI.EditMode.UpToDate(), "nothing left out of date: " .. table.concat(DUI.EditMode.Stale() or {}, ", "))
    DUI = reload({ before = bundled })
    stub.Dismiss()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.isnil(stub.Asked(), "no second reload asked")
end)

T.test("installer: an import into the profile in use swaps its Edit Mode layout in place", function()
    local DUI = login({ before = function()
        C_EditMode.ConvertStringToLayoutInfo = function(s)
            if s ~= "theirs" then return nil end
            local systems = {}
            for i = 1, 4 do systems[i] = { system = 0, systemIndex = i, settings = {}, anchorInfo = { offsetX = 77 } } end
            return { layoutName = "Their layout", layoutType = 1, systems = systems }
        end
    end })
    DUI.Installer.Install()
    local count = #saved.layouts
    local P = DUI.Profiles
    local shared = P.Snapshot()
    shared.layout = "theirs"
    P.ImportInto(shared, { [P.LAYOUT] = true })
    T.eq(#saved.layouts, count, "no layout added")
    local l = layoutNamed("DaylightUI - DPS/Tank")
    T.truthy(l, "kept under the profile's name")
    T.eq(l.systems[1].anchorInfo.offsetX, 77, "their layout in it")
    T.eq(saved.activeLayout, 3, "and in use")
end)

T.test("installer: the old debug log is cleared from the saved settings", function()
    login({ before = function() _G.DaylightUIDB = { guideDebug = { "--- session" } } end })
    T.isnil(DaylightUIDB.guideDebug)
    T.isnil(DaylightUI.InstallerUI.DebugNote, "no logger left")
end)

T.test("stub: addons switched on or off per character", function()
    login()
    stub.loadedAddOns.Baganator = true
    local me = UnitGUID("player")
    T.eq(C_AddOns.GetAddOnEnableState("Baganator", me), 2, "loaded: on")
    C_AddOns.DisableAddOn("Baganator", "Tester")
    T.eq(C_AddOns.GetAddOnEnableState("Baganator", me), 2, "a name names no character: still on")
    C_AddOns.DisableAddOn("Baganator", me)
    T.eq(C_AddOns.GetAddOnEnableState("Baganator", me), 0, "off for this character, by its GUID")
    T.eq(stub.addonState.Baganator[me], false)
end)

T.test("installer draft: a pick shows straight away and Revert puts it back", function()
    local DUI = login()
    local D = DUI.InstallerDraft
    local before = DUI:Get("general", "accent")
    D.Begin()
    D.Set("general", "accent", "gradient")
    T.eq(DUI:Get("general", "accent"), "gradient", "previewed live")
    T.eq(DUI.DB.Character().installDraft.values["general\taccent"], before, "the original kept in case of a crash")
    T.truthy(D.Picked("general", "accent"))
    D.Revert()
    T.eq(DUI:Get("general", "accent"), before, "back as it was")
    T.isnil(DUI.DB.Character().installDraft, "nothing left over")
    T.falsy(D.Active())
end)

T.test("installer draft: a color and a setting that wasn't there come back exactly", function()
    local DUI = login()
    local D = DUI.InstallerDraft
    local color = DUI:Get("general", "accentColor")
    local r, g, b = color[1], color[2], color[3]
    D.Begin()
    D.Set("general", "accentColor", { 1, 0, 0 })
    D.Set("general", "installerTest.deep", 5)
    T.eq(DUI:Get("general", "installerTest.deep"), 5)
    D.Revert()
    T.deq(DUI:Get("general", "accentColor"), { r, g, b }, "the color as it was")
    T.isnil(DUI:Get("general", "installerTest.deep"), "gone again")
end)

T.test("installer draft: Commit moves the picks into another profile and leaves the one in use as it was", function()
    local DUI = login()
    local D = DUI.InstallerDraft
    local before = DUI:Get("general", "accent")
    local made = DUI.Profiles.AddPreset("Healer")
    D.Begin()
    D.Track("general", "font")
    D.Set("general", "accent", "class", true)
    T.truthy(D.NeedsReload(), "a reload-only pick is remembered")
    D.Commit(made)
    local pd = DaylightUIDB.profileData
    T.eq(pd.Healer.general.accent, "class", "the pick went into Healer")
    T.eq(pd[DUI.DB.DEFAULT].general.accent, before, "Default back as it was")
    T.isnil(DUI.DB.Character().installDraft)
    T.falsy(D.Active())
end)

T.test("installer draft: Commit into the profile in use keeps the picks", function()
    local DUI = login()
    local D = DUI.InstallerDraft
    D.Begin()
    D.Set("general", "accent", "class")
    D.Commit(DUI.DB.ActiveName())
    T.eq(DUI:Get("general", "accent"), "class")
    T.eq(DaylightUIDB.profileData[DUI.DB.DEFAULT].general.accent, "class")
end)

T.test("installer draft: Seed shows a saved profile's look but never undoes a pick", function()
    local DUI = login()
    local D = DUI.InstallerDraft
    local made = DUI.Profiles.Create("Mine", nil, DUI.DB.DEFAULT)
    local pd = DaylightUIDB.profileData
    pd[made].general.font = "poppins"
    pd[made].general.accent = "class"
    local font, accent = DUI:Get("general", "font"), DUI:Get("general", "accent")
    D.Begin()
    D.Track("general", "font")
    D.Track("general", "accent")
    D.Set("general", "accent", "gradient")
    D.Seed(made)
    T.eq(DUI:Get("general", "font"), "poppins", "its font shown")
    T.eq(DUI:Get("general", "accent"), "gradient", "the pick kept")
    D.Seed(nil)
    T.eq(DUI:Get("general", "font"), font, "seeded back when the target changes")
    D.Seed(made)
    D.Commit(made)
    T.eq(pd[made].general.font, "poppins")
    T.eq(pd[made].general.accent, "gradient")
    T.eq(pd[DUI.DB.DEFAULT].general.font, font, "Default untouched")
    T.eq(pd[DUI.DB.DEFAULT].general.accent, accent)
end)

T.test("installer draft: a preview left by a crash is undone at the next login", function()
    local DUI = login()
    local before = DUI:Get("general", "accent")
    DUI.InstallerDraft.Begin()
    DUI.InstallerDraft.Set("general", "accent", "class")
    DUI = reload()                 -- the game saved what it had, as a crash or /reload does
    T.eq(DUI:Get("general", "accent"), before, "back as it was")
    T.isnil(DUI.DB.Character().installDraft)
end)

T.test("installer questions: every one writes a setting the options have, with a value that setting takes", function()
    local DUI = login({ module = true, bags = true, chat = true, infopanel = true, tooltip = true, qol = true, nameplates = true, quests = true,
                        procs = true, actionbars = true })
    local P = DUI.InstallerPages
    local n = 0
    for _, part in ipairs(P.PARTS) do
        for _, q in ipairs(part.questions) do
            n = n + 1
            T.truthy(type(q.ask) == "string" and type(q.what) == "string" and type(q.short) == "string", q.id .. " has its words")
            if q.option then
                local _, item = P.Find(q.option[1], q.option[2])
                T.truthy(item, q.id .. ": an options row")
                local values = item.values or (item.choices and item.choices())
                for _, v in ipairs(q.only) do
                    if type(v) ~= "boolean" then T.truthy(values and values[v], q.id .. ": takes " .. tostring(v)) end
                end
            end
            for _, pr in ipairs(q.presets or {}) do
                for _, st in ipairs(pr.set) do T.truthy(P.Find(st[1], st[2]), q.id .. ": " .. st[2]) end
            end
            for _, st in ipairs(q.bundle and q.bundle.set or {}) do T.truthy(P.Find(st[1], st[2]), q.id .. ": " .. st[2]) end
            if q.look then
                local spec = DUI.InstallerLooks.KINDS[q.look]
                T.truthy(spec, q.id .. ": a look")
                T.truthy(P.Find(spec.ref[1], spec.ref[2]), q.id .. ": an options row for " .. spec.ref[2])
            end
        end
    end
    T.eq(n, 16)
    for _, k in ipairs(P.Keys(P.Questions("quick"))) do T.truthy(P.Find(k[1], k[2]), "quick: " .. k[1] .. " " .. k[2]) end
    T.eq(P.Where("appearance"), "General > Appearance")
    T.eq(P.Module("Bags").addon, "DaylightUI_Bags")
end)

T.test("installer pages: a question needs its module", function()
    local DUI = login()
    local P = DUI.InstallerPages
    T.falsy(P.Asks(P.Question("bags")), "no bag module loaded")
    T.truthy(P.Asks(P.Question("accent")), "the core's own options always are")
    T.falsy(P.Loaded("Bags")); T.truthy(P.Loaded("general"))
end)

T.test("installer pages: a clash shows only when the other addon is loaded", function()
    local DUI = login()
    T.eq(#DUI.InstallerPages.Clashes(), 0)
    stub.loadedAddOns.Baganator = true
    local list = DUI.InstallerPages.Clashes()
    T.eq(#list, 1); T.eq(list[1].module, "Bags")
end)

T.test("installer cards: a picker shows the current choice and picks another", function()
    local DUI = login()
    local value = "b"
    local picker = DUI.InstallerCards.Picker(UIParent, { keys = { "a", "b", "c" }, width = 300, cols = 3, height = 60,
        label = function(k) return string.upper(k) end,
        get = function() return value end, set = function(k) value = k end })
    T.truthy(picker.cards.b.selected, "the current one")
    T.falsy(picker.cards.a.selected)
    T.eq(picker.cards.a.label:GetText(), "A")
    press(picker.cards.c)
    T.eq(value, "c")
    T.truthy(picker.cards.c.selected); T.falsy(picker.cards.b.selected)
    T.eq(picker.height, 60, "one row")
end)

T.test("installer cards: a tag takes the tick's corner", function()
    local DUI = login()
    local c = DUI.InstallerCards.Card(UIParent)
    c.SetSelected(true)
    T.truthy(c.tick:IsShown(), "picked: a tick")
    c.SetTag("In use")
    T.truthy(c.tag:IsShown()); T.falsy(c.tick:IsShown(), "the tag instead")
    T.eq(c.tag.text:GetText(), "In use")
    c.SetTag(nil)
    T.truthy(c.tick:IsShown())
end)

T.test("installer cards: every drawing builds", function()
    local DUI = login()
    local Cards = DUI.InstallerCards
    local c = Cards.Card(UIParent)
    for _, k in ipairs({ "DPS/Tank", "Healer" }) do T.noerror(function() Cards.Draw.role(c, k, 100, 60) end, k) end
    for _, k in ipairs({ "class", "classGradient", "gradient", "custom", "dark" }) do
        T.noerror(function() Cards.Draw.health(c, k, 100, 20) end, k)
    end
    for _, k in ipairs(DUI.Style.ACCENT_ORDER) do T.noerror(function() Cards.Draw.swatch(c, k, 100, 30) end, k) end
    for _, k in ipairs(DUI.Style.FONT_ORDER) do T.noerror(function() Cards.Draw.font(c, k, 100, 30) end, k) end
    T.noerror(function() Cards.Draw.texture(c, "daylight", 100, 20) end, "texture")
    T.noerror(function() Cards.Draw.bagview(c, "categories", 100, 40) end, "categories")
    T.noerror(function() Cards.Draw.bagview(c, "grid", 100, 40) end, "grid")
    for _, k in ipairs(DUI.Motion.KICKS) do
        local kc = Cards.Card(UIParent)
        kc:SetSize(120, 50)
        T.noerror(function() Cards.Draw.kick(kc, k, 100, 12) end, k)
        T.noerror(function() kc:GetScript("OnEnter")(kc) end, k .. ": hovered")
        T.truthy(kc.kick:IsShown() and kc.kick.style == k, k .. " plays on the card as the mouse comes onto it")
    end
    -- The question pages' pictures, at the widths the page asks for.
    local P = Cards.Picture
    local function built(f, w, what)
        T.truthy(type(f) == "table" and f.GetWidth, what .. ": a frame")
        if w then T.near(f:GetWidth(), w, 1, what .. ": as wide as asked") end
    end
    for _, w in ipairs({ 300, 210 }) do
        built(P.screen(UIParent, { role = "Healer", fight = true }, w), w, "screen")
        built(P.Sky(UIParent, w), w, "sky")
        for _, k in ipairs(DUI.Style.ACCENT_ORDER) do built(P.accent(UIParent, k, w), math.min(w, 250), "accent " .. k) end
        for _, k in ipairs(DUI.Style.FONT_PICKS) do built(P.font(UIParent, k, w), w, "font " .. k) end
        for _, k in ipairs({ "small", "medium", "large" }) do built(P.plate(UIParent, { size = k }, w), w, "plate " .. k) end
        for _, k in ipairs({ "categories", "grid", "list" }) do built(P.bags(UIParent, k, w), 196, "bags " .. k) end
        for _, k in ipairs({ "yes", "no" }) do built(P.quest(UIParent, k, w), w, "quest " .. k) end
        built(P.addon(UIParent, "Plater", w), w, "addon")
    end
    for _, k in ipairs(DUI.Style.ACCENT_ORDER) do built(P.accentBar(UIParent, k), 14, "accent bar " .. k) end
    for _, k in ipairs(DUI.Style.FONT_PICKS) do built(P.fontMini(UIParent, k), nil, "font sample " .. k) end
    T.eq(P.plate(UIParent, { size = "large" }, 250).plate:GetWidth(), math.floor(190 * 1.2 + 0.5), "a large plate")
    T.eq(P.plate(UIParent, { size = "small" }, 250).plate:GetWidth(), math.floor(150 * 0.85 + 0.5), "a small plate")
    local off = P.plate(UIParent, { percent = false, debuffs = false }, 250).plate
    T.falsy(off.percent:IsShown(), "no number"); for _, b in ipairs(off.debuffs) do T.falsy(b:IsShown(), "no debuffs") end
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer window: a tour page has the rail, header and footer; Escape closes it", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    local closed = 0
    UI.Open({ close = function() closed = closed + 1 end })
    local page = CreateFrame("Frame", nil, UI.Body())
    UI.SetPage(page, { rail = true, step = 2, total = 6, title = "Look", desc = "Colours.", later = "appearance",
                       back = true, next = "Next" })
    T.truthy(DaylightUIInstaller:IsShown())
    T.truthy(DaylightUIInstaller.rail:IsShown()); T.falsy(DaylightUIInstaller.banner:IsShown())
    T.eq(DaylightUIInstaller.header.step:GetText(), "Step 2 of 6")
    T.eq(DaylightUIInstaller.header.title:GetText(), "Look")
    T.eq(DaylightUIInstaller.later.text:GetText(), "Change it later: /dui > General > Appearance")
    T.truthy(DaylightUIInstaller.back:IsShown()); T.truthy(DaylightUIInstaller.next:IsShown())
    T.falsy(UI.Veil():IsShown(), "a page asked without a veil has none")
    escapeGuide()
    T.falsy(DaylightUIInstaller:IsShown(), "Escape closes it")
    T.eq(closed, 1, "the guide hears about it")
end)

-- Entering the world, the game closes every window Escape would
-- (CloseAllWindows), at the moment the guide opens for a new character.
T.test("installer: the game closing every window on entering the world leaves the guide open", function()
    local DUI = login()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.truthy(DaylightUIInstaller:IsShown(), "asked")
    for _, n in ipairs(UISpecialFrames) do if _G[n] then _G[n]:Hide() end end
    T.truthy(DaylightUIInstaller:IsShown(), "still open")
    T.truthy(DUI.Installer.flow)
    DaylightUIInstaller:GetScript("OnKeyDown")(DaylightUIInstaller, "A")
    T.truthy(DaylightUIInstaller:IsShown(), "other keys go on to the game")
    escapeGuide()
    T.falsy(DaylightUIInstaller:IsShown(), "the player's Escape closes it")
    T.falsy(DUI.Installer.Needed(), "closed for this session")
end)

T.test("installer window: the welcome fills the window over a veil; hiding it itself isn't closing", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    local closed = 0
    UI.Open({ close = function() closed = closed + 1 end })
    UI.SetPage(CreateFrame("Frame", nil, UI.Body()), { full = true, veil = true })
    T.falsy(DaylightUIInstaller.rail:IsShown()); T.truthy(DaylightUIInstaller.banner:IsShown())
    T.falsy(DaylightUIInstaller.footer:IsShown()); T.falsy(DaylightUIInstaller.header:IsShown())
    T.truthy(UI.Veil():IsShown())
    UI.QuietHide()
    T.eq(closed, 0, "not closed by the player")
    T.falsy(UI.Veil():IsShown())
end)

T.test("installer window: the player closing it fades it and its veil out; it hiding itself is instant", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    local closed = 0
    UI.Open({ close = function() closed = closed + 1 end })
    UI.SetPage(CreateFrame("Frame", nil, UI.Body()), { full = true, veil = true })
    press(DaylightUIInstaller.close)
    T.truthy(DaylightUIInstaller:IsShown(), "still on screen while it fades")
    T.truthy(UI.IsShown(), "and still counts as open: its steps wait for the fade")
    T.eq(closed, 0, "the close comes when the fade ends")
    T.truthy(DaylightUIInstaller.__duiMotion.vanish:IsPlaying())
    T.truthy(UI.Veil().fadeOut:IsPlaying(), "the veil fades with it")
    fadeDone()
    T.falsy(DaylightUIInstaller:IsShown())
    T.eq(closed, 1)
    T.falsy(UI.Veil():IsShown())
    -- Opened again: the veil is back at full.
    UI.Open({ close = function() closed = closed + 1 end })
    UI.SetPage(CreateFrame("Frame", nil, UI.Body()), { full = true, veil = true })
    T.falsy(UI.Veil().fadeOut:IsPlaying())
    -- The guide hiding itself: gone at once, no fade.
    UI.QuietHide()
    T.falsy(DaylightUIInstaller:IsShown())
    T.eq(closed, 1, "not closed by the player")
end)

T.test("installer window: steps aside in combat and comes back after", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    local closed, again = 0, 0
    UI.Open({ close = function() closed = closed + 1 end, again = function() again = again + 1 end })
    UI.SetPage(CreateFrame("Frame", nil, UI.Body()), { rail = true, title = "Look" })
    stub.EnterCombat()
    T.falsy(DaylightUIInstaller:IsShown(), "out of the way")
    T.eq(closed, 0)
    stub.LeaveCombat()
    T.truthy(DaylightUIInstaller:IsShown(), "back")
    T.eq(again, 1, "the guide puts its page back")
end)

T.test("installer window: the rail ticks off done steps and jumps only to visited ones", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    UI.Open({})
    local picked
    local steps = { { id = "welcome", label = "Welcome" }, { id = "look", label = "Look" }, { id = "finish", label = "Finish" } }
    UI.SetRail(steps, 2, { welcome = true, look = true }, function(id) picked = id end)
    local items = DaylightUIInstaller.rail.items
    T.truthy(items[1].tick:IsShown(), "done"); T.falsy(items[2].tick:IsShown(), "on show")
    T.eq(items[2].text:GetText(), "Look")
    press(items[1])
    T.eq(picked, "welcome")
    picked = nil
    press(items[3])
    T.isnil(picked, "not visited yet")
end)

T.test("installer window: the spotlight hangs from real frames; the Reload button is a secure /reload", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    UI.Open({})
    CreateFrame("Frame", "TestSpotFrame", UIParent)
    UI.Spotlight({ "TestSpotFrame", "NoSuchFrame" })
    local spots = UI.Spots()
    T.truthy(spots[1] and spots[1]:IsShown(), "around the real frame")
    T.eq(select(2, spots[1]:GetPoint(1)), TestSpotFrame, "hung from it")
    T.isnil(spots[2], "a frame that isn't there gets none")
    UI.Spotlight(nil)
    T.falsy(spots[1]:IsShown())
    local slot = CreateFrame("Frame", nil, UIParent)
    T.truthy(UI.ShowReload(slot))
    local b = UI.ReloadButton()
    T.eq(b:GetAttribute("type"), "macro"); T.eq(b:GetAttribute("macrotext"), "/reload")
    T.truthy(b:IsProtected(), "a secure button: the game lets it reload")
    stub.EnterCombat()
    T.falsy(b:IsShown(), "hidden as combat starts")
    T.falsy(UI.ShowReload(slot), "never shown in combat")
    stub.LeaveCombat()
end)

T.test("installer: a new character gets the guide; X closes it until the next login", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "asked")
    T.eq(DUI.Installer.flow.mode, "new")
    T.eq(DUI.Installer.flow.page, "welcome")
    T.truthy(string.find(DUI.Installer.pages.welcome.title.text:GetText(), "Tester", 1, true), "greets by name")
    closeGuide()
    T.falsy(DaylightUIInstaller:IsShown())
    T.isnil(DUI.Installer.flow)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")         -- a loading screen
    T.falsy(DaylightUIInstaller:IsShown(), "not again this session")
    T.isnil(DUI.Installer.State(), "no answer saved")
    T.eq(#saved.layouts, 0, "nothing written")
    DUI.RunCommand("install")
    T.truthy(DaylightUIInstaller:IsShown(), "/dui install brings it back")
    closeGuide()
    reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "asked again at the next login")
end)

-- A player who skipped the guide and then changed something has set the
-- character up their own way: the guide stops asking, and the next login puts
-- the profile's Edit Mode layout in place with one reload.
T.test("installer: a change made after closing the guide counts as set up", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    closeGuide()
    T.isnil(DUI.Installer.State())
    DUI:Set("general", "softness", 0.5)
    T.eq(DUI.Installer.State(), "installed", "set up from the first change")
    T.eq(#saved.layouts, 0, "nothing written mid-session")
    reload()
    stub.RunTimers()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "the guide doesn't ask again")
    T.truthy(layoutNamed("DaylightUI - DPS/Tank"), "the profile's layout went in")
    T.eq(stub.Asked(), "reload", "one reload asked for it")
    T.eq(DaylightUI:Get("general", "softness"), 0.5, "the change was kept")
end)

-- A new character's intro cinematic hides the whole UI; when the UI comes
-- back the game closes every window (UIParent_OnShow: CloseAllWindows).
-- Neither is the player closing the guide.
T.test("installer: the UI hidden for a cinematic and back doesn't close the guide", function()
    local DUI = login({ before = function()
        UIParent:SetScript("OnShow", function()
            for _, n in ipairs(UISpecialFrames) do if _G[n] then _G[n]:Hide() end end
        end)
    end })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "asked")
    UIParent:Hide()
    DaylightUIInstaller:GetScript("OnHide")(DaylightUIInstaller)   -- the client: hidden with its parent
    T.truthy(DUI.Installer.flow, "not closed while the UI is hidden")
    UIParent:Show()
    T.truthy(DaylightUIInstaller:IsShown(), "back with the UI")
    T.truthy(DUI.Installer.flow, "still the same guide")
    T.truthy(DUI.Installer.Needed(), "not counted as closed this session")
    closeGuide()
    T.falsy(DaylightUIInstaller:IsShown(), "the player can still close it")
    T.falsy(DUI.Installer.Needed())
end)

T.test("installer: asked on entering the world when the layouts event came too early", function()
    login()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.truthy(DaylightUIInstaller:IsShown(), "asked")
end)

-- No action bars (no Edit Mode part), no layouts event, nothing on
-- entering the world: a new character still gets the guide.
T.test("installer: a new character gets the guide a moment after login, Edit Mode or not", function()
    local DUI = stub.Load({ before = world })
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "not before the moment")
    stub.RunTimers()
    T.truthy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "asked")
    T.eq(DUI.Installer.flow.mode, "new")
end)

T.test("installer: a set-up character isn't asked at login before the game has its layouts", function()
    local DUI = login()
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    reload()
    stub.RunTimers()
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown())
end)

T.test("installer: Quick setup, Damage / Tank: arriving on Finish sets it up, and its one button reloads", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.eq(#saved.layouts, 0, "nothing written before")
    choose(DUI, "DPS/Tank"); go(DUI)
    T.eq(DUI.Installer.flow.page, "finish")
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank")
    T.truthy(layoutNamed("DaylightUI - DPS/Tank"), "the layout written")
    T.eq(saved.activeLayout, 3, "and in use")
    T.eq(DUI.Installer.State(), "installed")
    T.eq(DaylightUIDB.installerSeen, DUI.Installer.VERSION)
    local page = DUI.Installer.pages.finish
    T.eq(page.go.text:GetText(), "Reload and play")
    T.eq(page.tags[1].value:GetText(), "Damage / Tank")
    stub.RunTimers()
    local b = DUI.InstallerUI.ReloadButton()
    T.truthy(b and b:IsShown(), "the reload button, over the page's one button")
    T.eq(b:GetAttribute("macrotext"), "/reload")
    T.eq(b.text:GetText(), "Reload and play")
    T.falsy(stub.reloaded, "never ReloadUI from addon code")
end)

T.test("installer: Quick setup, Healer: the healer profile and its own layout", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "Healer"); go(DUI)
    local h = DaylightUIDB.profileData.Healer
    T.truthy(h, "the Healer profile")
    -- What makes it the Healer one comes from the setup itself, whatever
    -- settings that is; its spots are fitted to the screen, so only checked
    -- to be there.
    T.eq(DUI.Installer.PresetShare(h, "Healer"), 1, "every setting of the Healer setup")
    for key in pairs(DUI.Profiles.PRESET_POSITIONS.Healer or {}) do
        T.truthy(h.positions[key], "a spot of its own for " .. key)
    end
    T.eq(DUI.Installer.RoleShape("Healer"), "Healer")
    T.eq(DUI.Profiles.Chosen("character"), "Healer")
    T.truthy(layoutNamed("DaylightUI - Healer"), "its own layout")
end)

-- The first profile on an account starts with the info panel closed (a
-- click on the panel's tab opens the meter), whichever setup made it.
T.test("installer: the first profile starts with the info panel's meter closed", function()
    for _, key in ipairs({ "DPS/Tank", "Healer" }) do
        local DUI = login({ module = true, infopanel = true })
        T.eq(DUI:Get("InfoPanel", "meter.enabled"), false, "folded before the guide too")
        stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
        choose(DUI, key); go(DUI)
        local name = DUI.Profiles.Chosen("character")
        T.eq(DaylightUIDB.profileData[name].modules.InfoPanel.meter.enabled, false, key .. ": folded")
    end
end)

-- The account's first profile is the DPS/Tank a quick setup keeps, so it has to
-- carry the micro menu in the corner like the ready-made card says.
T.test("installer: DPS/Tank and Healer start with the micro menu shown in the corner", function()
    for _, key in ipairs({ "DPS/Tank", "Healer" }) do
        local DUI = login({ module = true, actionbars = true })
        stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
        choose(DUI, key); go(DUI)
        local ab = DaylightUIDB.profileData[DUI.Profiles.Chosen("character")].modules.ActionBars
        T.eq(ab.microMenu, "shown", key .. ": shown")
        T.eq(ab.microMenuCorner, true, key .. ": in the corner")
    end
end)

T.test("installer: Quick setup, Immersive Preset: a new character gets the calm profile, its own layout, fades that step aside in dungeons", function()
    local function xp()
        _G.UnitXP = function() return 300 end
        _G.UnitXPMax = function() return 1200 end
        _G.GetXPExhaustion = function() return 400 end
    end
    local mods = { module = true, infopanel = true, quests = true, chat = true, before = xp }
    local DUI = login(mods)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local c = card(DUI, "Immersive Preset")
    T.truthy(c, "an Immersive Preset card")
    T.noerror(function() c:GetScript("OnEnter")(c); c:GetScript("OnLeave")(c) end, "its hover")
    choose(DUI, "Immersive Preset"); go(DUI)
    T.eq(DUI.Installer.flow.page, "q:quest", "the quests loaded: the quest helper's question first")
    DUI.Installer.Next()
    local p = DaylightUIDB.profileData["Immersive Preset"]
    T.truthy(p, "the Immersive Preset profile")
    T.eq(DUI.Installer.PresetShare(p, "Immersive Preset"), 1, "every setting of the Immersive Preset setup")
    T.eq(p.general.fadeOpenWorldOnly, true, "fades only in the open world")
    T.eq(DUI.Installer.RoleShape("Immersive Preset"), "Immersive Preset")
    T.eq(DUI.Profiles.Chosen("character"), "Immersive Preset")
    T.truthy(layoutNamed("DaylightUI - Immersive Preset"), "its own layout")
    local std = DaylightUIDB.profileData[DUI.DB.DEFAULT]
    T.truthy(type(std) ~= "table" or std.general.fadeOpenWorldOnly ~= true, "DPS/Tank keeps fading everywhere")
    -- The reload Finish asks for: on Immersive Preset now.
    DUI = reload(mods)
    T.eq(DUI.DB.ActiveName(), "Immersive Preset")
    T.eq(DUI:Get("general", "fadeOpenWorldOnly"), true)
    T.eq(DUI:Get("ActionBars", "bars.main.fade.mode"), "ooc")
    T.eq(DUI:Get("UnitFrames", "player.fade.mode"), "float")
    T.eq(DUI:Get("UnitFrames", "player.fade.delay"), 2)
    T.eq(DUI:Get("InfoPanel", "meter.enabled"), false, "the meter starts folded: one click on the tab brings it out")
    T.isnil(DUI:Get("InfoPanel", "meter.inGroup") == true and true or nil, "not hidden solo")
    T.eq(DUI:Get("InfoPanel", "map.size"), 204)
    T.eq(DUI:Get("Quests", "fade.mode"), "combat", "the quest tracker dims in a fight")
    T.eq(DUI:Get("InfoPanel", "fade.alpha"), 0.5)
    T.eq(DUI:Get("Chat", "hides"), "always", "the chat floats (the standard start)")
    -- Out in the world the bars fade a while after login; in a dungeon they show.
    local F = DUI.Fade
    F.SkipIntro()
    stub.Advance(10)
    F.Step()
    local _, goal, faded = F.State("ActionBars.main")
    T.eq(goal, faded, "the main bar fades in the open world")
    stub.SetInstance("party")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    local _, inside, _, opacity = F.State("ActionBars.main")
    T.eq(inside, opacity, "shown in a dungeon")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer: the game stays dimmed behind every step, welcome to finish", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    DUI.Installer.Start("tour")
    for _, id in ipairs({ "welcome", "modules", "role", "finish" }) do
        DUI.Installer.Go(id)
        T.truthy(DUI.InstallerUI.Veil():IsShown(), id .. ": the veil stays")
    end
end)


T.test("installer: renaming a profile renames its layout, presets kept first in the save", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "Healer"); go(DUI)
    closeGuide()
    local _, before = layoutNamed("DaylightUI - Healer")
    T.eq(DUI.EditMode.RenameLayout("Healer", "Mine"), true)
    local _, index = layoutNamed("DaylightUI - Mine")
    T.eq(index, before, "same spot")
    T.isnil(layoutNamed("DaylightUI - Healer"), "the old name gone")
    T.eq(C_EditMode.GetLayouts().activeLayout, index, "still the active one")
end)

T.test("installer: picking Healer, then DPS / Tank, moves the character over and keeps both layouts", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "Healer"); go(DUI)
    T.eq(DUI.Profiles.Chosen("character"), "Healer")
    closeGuide()
    DUI.RunCommand("install")
    choose(DUI, "DPS/Tank"); go(DUI)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank", "on the DPS/Tank profile")
    local _, index = layoutNamed("DaylightUI - DPS/Tank")
    T.eq(C_EditMode.GetLayouts().activeLayout, index, "its layout in use")
    T.truthy(layoutNamed("DaylightUI - Healer"), "the Healer one left as it was")
end)

T.test("installer: the welcome offers a profile they have only when there is one", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.isnil(card(DUI, "keep"), "only DPS/Tank, which has its own card: nothing to pick")
    closeGuide()
    DUI.Profiles.Create("Mine", nil, DUI.DB.DEFAULT)
    DUI.Installer.Show()
    T.truthy(card(DUI, "keep"), "offered now")
    choose(DUI, "keep")
    -- The one this character is on when it's saved (the new bars' world
    -- starts from settings older than profiles), else the only one there.
    T.eq(DUI.Installer.flow.profile, DUI.DB.Saved("DPS/Tank") and "DPS/Tank" or "Mine", "picked")
    choose(DUI, "DPS/Tank"); go(DUI)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank", "Quick setup still works with a profile around")
end)

T.test("installer: Use a setup I have puts the character on it, as it is", function()
    local DUI = login()
    local made = DUI.Profiles.Create("Mine", nil, DUI.DB.DEFAULT)
    DaylightUIDB.profileData[made].general.accent = "class"
    DUI.Installer.Show()
    DUI.Installer.flow.profile = "Mine"                -- picked in the list
    choose(DUI, "keep"); go(DUI)
    T.eq(DUI.Installer.flow.path, "existing")
    T.eq(DUI.Profiles.Chosen("character"), "Mine")
    T.eq(DaylightUIDB.profileData.Mine.general.accent, "class", "left as it was")
    T.isnil(DaylightUIDB.profileData.Healer, "no ready-made profile made")
    T.truthy(layoutNamed("DaylightUI - Mine"), "its layout")
    stub.RunTimers()
    T.truthy(DUI.InstallerUI.ReloadButton():IsShown())
end)

T.test("installer: Use a setup I have offers DPS/Tank too, once there's another profile", function()
    local DUI = login()
    DUI.Profiles.AddPreset("DPS/Tank")                 -- installed before
    DUI.Profiles.Create("Healer", nil, DUI.DB.DEFAULT)
    DaylightUIDB.profileData[DUI.DB.DEFAULT].general.accent = "class"
    DUI.Installer.Show()
    local names = DUI.Installer.ExistingProfiles()
    T.eq(names[1], "DPS/Tank", "listed, first")
    T.eq(names[2], "Healer")
    DUI.Installer.Start("existing", "DPS/Tank")
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank")
    T.eq(DaylightUIDB.profileData["DPS/Tank"].general.accent, "class", "left as it was")
end)

T.test("installer: another character on the account can use the first one's setup", function()
    local DUI = login()
    DUI.Installer.Install()                            -- the first character
    DUI:Set("general", "accent", "class")              -- and a change of its own
    stub.Dismiss()
    saved.activeLayout = 1                             -- a new character: on the game's own layout
    DUI.DB.Root().characters = nil
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "asked, though the layout exists")
    T.eq(DUI.Installer.flow.mode, "new")
    -- DPS/Tank is the first one's profile: its card puts this one on it.
    choose(DUI, "DPS/Tank"); go(DUI)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank")
    T.eq(DaylightUIDB.profileData["DPS/Tank"].general.accent, "class", "as the first one left it")
    T.eq(saved.activeLayout, 3, "ours active for this character")
    T.isnil(stub.Asked(), "no popup: the guide has its own Reload")
end)

T.test("installer: a set-up character sees the guide once per account, with Keep my setup first", function()
    local DUI = login()
    DUI.Installer.Install()
    DaylightUIDB.installerSeen = nil                   -- set up before this guide existed
    DUI = reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "shown off")
    T.eq(DUI.Installer.flow.mode, "showcase")
    local keep = card(DUI, "keep")
    T.truthy(keep and keep.picked, "Keep my setup, picked")
    T.eq(keep.tagFrame.text:GetText(), "In use")
    T.eq(DUI.Installer.flow.profile, "DPS/Tank", "the profile in use")
    go(DUI)
    stub.RunTimers()
    T.eq(DUI.Installer.pages.finish.go.text:GetText(), "Done", "nothing to reload: Done")
    local b = DUI.InstallerUI.ReloadButton()
    T.falsy(b and b:IsShown())
    press(DUI.Installer.pages.finish.go)
    T.falsy(DaylightUIInstaller:IsShown())
    reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "once per account")
end)

T.test("installer: a character that said Not now to the old installer sees it once; X counts as seen", function()
    local DUI = login()
    DUI.Installer.Mark("skipped")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.truthy(DaylightUIInstaller:IsShown(), "shown off once")
    T.eq(DUI.Installer.flow.mode, "showcase")
    closeGuide()
    T.eq(DaylightUIDB.installerSeen, DUI.Installer.VERSION, "seen")
    reload()
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "not again")
end)

T.test("installer: a character already on our layout isn't asked again once it's seen the guide", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI.DB.Root().characters = nil                     -- from before the installer
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.falsy(_G.DaylightUIInstaller and DaylightUIInstaller:IsShown(), "not asked")
    T.eq(DUI.Installer.State(), "installed")
end)

-- Set up, then on the game's own layout (picked in Edit Mode, or the
-- game's per-character active layout never moved): not a new character.
T.test("installer: a set-up character on the game's layout is put back on its own, not asked again", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    saved.activeLayout = 1
    stub.Dismiss()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "no guide")
    T.eq(saved.activeLayout, 3, "its layout back in use")
    T.eq(stub.Asked(), "reload", "asks for the reload")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "nor on entering the world")
end)

-- The controller UI keeps the character on the game's Gamepad preset. Putting
-- a keyboard-and-mouse layout in under it can crash the game, so nothing is
-- written or asked until the controller UI is off again.
T.test("installer: a set-up character in controller mode is left on the game's layout", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
    _G.C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
    saved.activeLayout = 2
    stub.Dismiss()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local active, asked = saved.activeLayout, stub.Asked()
    _G.C_InputInterfaceStyle = nil
    T.eq(active, 2, "still on the game's layout")
    T.falsy(asked, "no reload asked")
end)

T.test("installer: a set-up character whose layout was deleted gets it back, not the guide", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    saved.layouts, saved.activeLayout = {}, 1           -- the layout deleted in Edit Mode
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "no guide")
    T.truthy(layoutNamed("DaylightUI - DPS/Tank"), "written again")
    T.eq(saved.activeLayout, 3, "and in use")
    DUI.RunCommand("install")
    T.truthy(DaylightUIInstaller:IsShown(), "/dui install still opens it")
end)

-- From player reports: set up, then on an Edit Mode layout they made
-- themselves, and switched back to Daylight UI's after a relog or a loading
-- screen (a boat, a dungeon). Their pick stays, even with ours deleted.
local function ownLayout()
    local mine = CopyTable(layoutNamed("DaylightUI - DPS/Tank"))
    mine.layoutName = "I"
    table.insert(saved.layouts, mine)
    saved.activeLayout = #saved.layouts + 2
    return saved.activeLayout
end

T.test("installer: a set-up character on a layout of its own keeps it through logins and loading screens", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    local mine = ownLayout()
    DUI = reload()
    stub.Dismiss()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")       -- a loading screen
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(saved.activeLayout, mine, "still on its own layout")
    T.isnil(stub.Asked(), "no reload asked")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "no guide")
end)

T.test("installer: a layout of its own with Daylight UI's deleted doesn't bring Daylight UI's back", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    ownLayout()
    table.remove(saved.layouts, 1)                      -- Daylight UI's deleted in Edit Mode
    saved.activeLayout = 3
    DUI = reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.isnil(layoutNamed("DaylightUI - DPS/Tank"), "not written again")
    T.eq(saved.activeLayout, 3, "still on its own layout")
end)

T.test("installer: a part out of date never moves a character off a layout of its own", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    local mine = ownLayout()
    DUI = reload()
    DUI.EditMode.Add("stale", function() end, function() return false end)
    stub.Dismiss()
    DUI.EditMode.AutoSave("updated")
    T.eq(saved.activeLayout, mine, "still on its own layout")
    T.isnil(stub.Asked(), "no reload asked")
end)

-- Seen in game: "updated its layout" on every dungeon or zeppelin, then again after
-- each reload. The game fires its layouts event on loading screens too, when the
-- active layout can read wrong for a moment, so only the session's first one checks.
T.test("installer: a loading screen's layouts event never asks for a reload", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    stub.Dismiss()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")             -- the login's
    stub.RunTimers()
    T.isnil(stub.Asked(), "up to date at login")
    DUI.EditMode.Add("glitch", function() end, function() return false end)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")             -- a loading screen's
    stub.RunTimers()
    T.isnil(stub.Asked(), "no reload asked")
end)

-- Seen in game on 1.9.2 still: the login's layouts event came while the game had no
-- active layout yet, so the check slipped to the first boat or dungeon.
T.test("installer: a login whose layouts came late never asks on a loading screen", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    stub.Dismiss()
    local active = saved.activeLayout
    saved.activeLayout = 0
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")             -- the login's, nothing active yet
    saved.activeLayout = active
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)  -- a boat's loading screen
    DUI.EditMode.Add("glitch", function() end, function() return false end)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.isnil(stub.Asked(), "no reload asked")
end)

-- Seen in game on 2.2.5 still, after a zeppelin or boat: on a loading screen the
-- game sends its layouts event before PLAYER_ENTERING_WORLD, so a login whose
-- layouts came late still had its check waiting when that event came.
T.test("installer: a loading screen's layouts event before entering the world never asks", function()
    local DUI = login()
    DUI.Installer.Install()
    DUI = reload()
    stub.Dismiss()
    local active = saved.activeLayout
    saved.activeLayout = 0
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")             -- the login's, nothing active yet
    saved.activeLayout = active
    stub.FireEvent("PLAYER_LEAVING_WORLD")                 -- the zeppelin's loading screen starts
    DUI.EditMode.Add("glitch", function() end, function() return false end)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")             -- before entering the world
    stub.FireEvent("PLAYER_ENTERING_WORLD", false, false)
    stub.RunTimers()
    T.isnil(stub.Asked(), "no reload asked")
end)

T.test("installer: Healer again leaves an edited Healer profile alone", function()
    local DUI = login()
    DUI.Installer.Install("Healer")
    DaylightUIDB.profileData.Healer.positions["unitframes.player"] = { 10, 20 }
    DUI.Installer.Install("Healer")
    T.eq(DaylightUIDB.profileData.Healer.positions["unitframes.player"][1], 10, "the edit kept")
    DUI.Installer.Install(DUI.Installer.EXISTING, "Healer")
    T.eq(DaylightUIDB.profileData.Healer.positions["unitframes.player"][1], 10, "picked from the list too")
    T.eq(DUI.Profiles.Chosen("character"), "Healer")
end)

T.test("installer: when the layout can't be placed, Finish says why, changes nothing, and Try again works", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    EditModeManagerFrame:Show()                        -- Edit Mode open: the game won't take a layout
    choose(DUI, "DPS/Tank"); go(DUI)
    local page = DUI.Installer.pages.finish
    T.truthy(string.find(page.line:GetText() or "", "Edit Mode is open", 1, true), "says why")
    T.eq(page.title.text:GetText(), "Almost there")
    T.isnil(DUI.Installer.State(), "not set up")
    T.eq(#saved.layouts, 0)
    EditModeManagerFrame:Hide()
    press(page.go)
    T.eq(page.go.text:GetText(), "Reload and play")
    T.eq(DUI.Installer.State(), "installed", "Try again")
end)

-- A guide whose Finish ran into the game's limit of 5 account layouts: two of
-- Daylight UI's left by profiles gone, the standard one, and two of the
-- player's own, one of them in use on this character.
local function fullList(DUI)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    Constants = Constants or {}
    Constants.EditModeConsts = { EditModeMaxLayoutsPerType = 5 }
    DaylightUIDB.profileData = DaylightUIDB.profileData or {}
    DaylightUIDB.profileData["DPS/Tank"] = DaylightUIDB.profileData["DPS/Tank"] or {}
    saved.layouts = {
        { layoutName = "DaylightUI - Old Raid", layoutType = 1, systems = {} },
        { layoutName = "DaylightUI - DPS/Tank", layoutType = 1, systems = {} },
        { layoutName = "Arena", layoutType = 1, systems = {} },
        { layoutName = "Questing", layoutType = 1, systems = {} },
        { layoutName = "DaylightUI - Tank 2", layoutType = 1, systems = {} },
    }
    saved.activeLayout = 5   -- Arena (the two presets come first)
    choose(DUI, "Healer"); go(DUI)
    return DUI.Installer.pages.finish
end
local function rowNamed(page, name)
    for _, r in ipairs(page.layoutRows or {}) do
        if r:IsShown() and r.layoutName == name then return r end
    end
end
local function twice(b)
    b:GetScript("OnClick")(b, "LeftButton")
    stub.now = (stub.now or 0) + 0.5   -- past the double-click guard (abworld's clock)
    b:GetScript("OnClick")(b, "LeftButton")
end

T.test("installer finish: a full layout list shows every account layout and whose it is", function()
    local DUI = login()
    local page = fullList(DUI)
    T.falsy(DUI.Installer.flow.finished)
    T.truthy(page.full and page.full:IsShown(), "the list in place of the picture")
    T.falsy(page.holder:IsShown(), "the picture makes room")
    T.truthy(string.find(page.say:GetText() or "", "all 5 are taken", 1, true), page.say:GetText())
    local shown = 0
    for _, r in ipairs(page.layoutRows) do if r:IsShown() then shown = shown + 1 end end
    T.eq(shown, 5, "one row per account layout")
    T.truthy(string.find(rowNamed(page, "DaylightUI - Old Raid").sub:GetText(), "no profile uses it", 1, true))
    T.truthy(rowNamed(page, "DaylightUI - Old Raid").leftover, "a leftover gets the accent edge")
    T.truthy(string.find(rowNamed(page, "DaylightUI - DPS/Tank").sub:GetText(), "DPS/Tank", 1, true), "whose profile")
    T.falsy(rowNamed(page, "DaylightUI - DPS/Tank").leftover)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    Constants.EditModeConsts = nil
end)

T.test("installer finish: deleting a leftover layout frees a slot and Try again finishes", function()
    local DUI = login()
    local page = fullList(DUI)
    local row = rowNamed(page, "DaylightUI - Old Raid")
    row.del:GetScript("OnClick")(row.del, "LeftButton")
    T.truthy(layoutNamed("DaylightUI - Old Raid"), "one click only asks")
    stub.now = (stub.now or 0) + 0.5
    row.del:GetScript("OnClick")(row.del, "LeftButton")
    T.isnil(layoutNamed("DaylightUI - Old Raid"), "the second click deletes it")
    T.eq(saved.deleted, 3, "the game is told which one went")
    local _, arena = layoutNamed("Arena")
    T.eq(saved.activeLayout, arena, "the character stays on its layout")
    T.isnil(rowNamed(page, "DaylightUI - Old Raid"), "gone from the list")
    press(page.go)
    T.truthy(DUI.Installer.flow.finished, "Try again finishes")
    local _, healer = layoutNamed("DaylightUI - Healer")
    T.eq(saved.activeLayout, healer, "on its new layout")
    T.falsy(page.full:IsShown(), "the list leaves once it's done")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    Constants.EditModeConsts = nil
end)

T.test("installer finish: the layout in use shows but can't be deleted", function()
    local DUI = login()
    local page = fullList(DUI)
    local row = rowNamed(page, "Arena")
    T.truthy(row, "listed")
    T.falsy(row.del and row.del:IsShown(), "no delete button")
    T.truthy(string.find(row.sub:GetText(), "In use", 1, true), row.sub:GetText())
    local _, index = layoutNamed("Arena")
    local ok = DUI.EditMode.DeleteLayout(index)
    T.falsy(ok, "refused even when asked directly")
    T.truthy(layoutNamed("Arena"))
    Constants.EditModeConsts = nil
end)

T.test("installer finish: nothing is deleted in a fight or with the controller UI on", function()
    local DUI = login()
    local page = fullList(DUI)
    local row = rowNamed(page, "DaylightUI - Tank 2")
    stub.combat = true
    twice(row.del)
    stub.combat = false
    T.truthy(layoutNamed("DaylightUI - Tank 2"), "kept in a fight")
    T.truthy(string.find(page.say:GetText() or "", "combat", 1, true), "says why: " .. tostring(page.say:GetText()))
    local was = DUI.EditMode.GamepadMode
    DUI.EditMode.GamepadMode = function() return true end
    twice(rowNamed(page, "DaylightUI - Tank 2").del)
    DUI.EditMode.GamepadMode = was
    T.truthy(layoutNamed("DaylightUI - Tank 2"), "kept with the controller UI on")
    T.eq(#saved.layouts, 5)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    Constants.EditModeConsts = nil
end)

T.test("installer: renaming a profile while its layout can't be renamed doesn't leave a second layout", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "Healer"); go(DUI)
    closeGuide()
    T.eq(#saved.layouts, 1)
    EditModeManagerFrame:Show()                        -- Edit Mode open: the layout can't be renamed now
    T.truthy(DUI.Profiles.Rename("Healer", "Mine"))
    EditModeManagerFrame:Hide()
    reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.eq(#saved.layouts, 1, "the old layout renamed, not a new one made beside it")
    local _, index = layoutNamed("DaylightUI - Mine")
    T.truthy(index, "named for the new profile")
    T.isnil(layoutNamed("DaylightUI - Healer"), "the old name gone")
    T.eq(saved.activeLayout, index, "and in use")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer finish: when it can't finish it says why, Try again works, and Back returns", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local pad = true
    local was = DUI.EditMode.GamepadMode
    DUI.EditMode.GamepadMode = function() return pad end
    choose(DUI, "mine"); go(DUI)
    DUI.Installer.ToFinish()
    local page = DUI.Installer.pages.finish
    T.falsy(DUI.Installer.flow.finished)
    T.truthy(string.find(page.line:GetText(), "Controller mode", 1, true))
    T.eq(page.go.text:GetText(), "Try again"); T.truthy(page.back:IsShown())
    T.eq(#saved.layouts, 0)
    T.isnil(DUI.Installer.State())
    stub.RunTimers()
    T.falsy(DUI.InstallerUI.ReloadButton() and DUI.InstallerUI.ReloadButton():IsShown())
    press(page.back)
    T.truthy(string.find(DUI.Installer.flow.page, "^q:"), "back on the last question")
    DUI.Installer.ToFinish()
    pad = false
    press(page.go)
    T.truthy(DUI.Installer.flow.finished); T.falsy(page.back:IsShown())
    T.eq(page.go.text:GetText(), "Reload and play")
    DUI.EditMode.GamepadMode = was
end)

T.test("installer finish: a fight never shows the reload button, and Finish waits for its end", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank")
    stub.EnterCombat()
    T.falsy(DaylightUIInstaller:IsShown(), "out of the way")
    T.truthy(DUI.Installer.flow, "not closed")
    go(DUI)
    T.isnil(DUI.Installer.State(), "waits")
    T.falsy(DUI.Installer.flow.finished, "waits for the fight to end")
    local b = DUI.InstallerUI.ReloadButton()
    T.falsy(b and b:IsShown())
    stub.LeaveCombat(); stub.RunTimers()
    T.truthy(DUI.Installer.flow.finished)
    T.eq(DUI.Installer.State(), "installed", "finished after combat")
    T.truthy(DaylightUIInstaller:IsShown(), "back")
    T.eq(DUI.Installer.flow.page, "finish")
    b = DUI.InstallerUI.ReloadButton()
    T.truthy(b and b:IsShown(), "the reload button once the fight is over")
end)

T.test("installer: reload prompts wait while the guide is open", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.Dismiss()
    DUI.EditMode.AskReload("something changed")
    T.isnil(stub.Asked(), "held")
    closeGuide()
    T.eq(stub.Asked(), "reload", "shown once the guide closes")
end)

T.test("installer: how close a profile is to a ready-made setup, whatever its settings", function()
    local DUI = login({ module = true })
    local I = DUI.Installer
    DUI.Profiles.PRESETS.Probe = { UnitFrames = { a = 1, b = false, deep = { c = 3, d = 4 } } }
    T.eq(I.PresetShare({ modules = { UnitFrames = { a = 1, b = false, deep = { c = 3, d = 4 } } } }, "Probe"), 1,
        "all of it (a setting turned off counts too)")
    T.eq(I.PresetShare({ modules = { UnitFrames = { a = 1, b = true, deep = { c = 3, d = 9 } } } }, "Probe"), 0.5, "half")
    T.eq(I.PresetShare({ modules = {} }, "Probe"), 0, "none")
    T.eq(I.PresetShare({ modules = {} }, "DPS/Tank"), 0, "a setup with nothing of its own")
    DUI.Profiles.PRESETS.Probe = nil
    DUI.Profiles.AddPreset("Healer")
    DUI.Profiles.Create("Copy", nil, "Healer")
    T.eq(I.RoleShape("Copy"), "Healer", "a copy of the Healer setup draws as one")
    DUI.Profiles.Create("Plain", nil, DUI.DB.DEFAULT)
    T.eq(I.PresetShare(DaylightUIDB.profileData.Plain, "Healer"), 0, "Default's own values don't count")
    T.eq(I.RoleShape("Plain"), "DPS/Tank")
end)

T.test("installer: the greeting uses the first and last name", function()
    local DUI = login()
    local I = DUI.Installer
    local real = _G.UnitFullName
    _G.UnitFullName = function() return "Bone", "Money" end
    T.truthy(I.GreetingText():find("Bone Money", 1, true), "first and last name")
    _G.UnitFullName = function() return "Bone", "" end
    T.falsy(I.GreetingText():find("Bone ", 1, true), "no last name, no trailing space")
    _G.UnitFullName = real
end)

T.test("installer: greetings by the hour, and a role only when the game says one", function()
    local DUI = login()
    local I = DUI.Installer
    T.eq(I.Greeting(8), "Good morning, %s"); T.eq(I.Greeting(14), "Good afternoon, %s"); T.eq(I.Greeting(22), "Good evening, %s")
    T.isnil(I.Recommended(), "no spec, no role")
    _G.GetSpecialization = function() return 2 end
    _G.GetSpecializationRole = function() return "HEALER" end
    T.eq(I.Recommended(), "Healer")
    _G.GetSpecializationRole = function() return "TANK" end
    T.eq(I.Recommended(), "DPS/Tank")
end)


-- Typing into an edit box, as the player does.
local function typeIn(box, text)
    box:SetText(text)
    box:GetScript("OnTextChanged")(box, true)
end



-- With the quest tracker loaded, Quick setup asks one question between
-- the setup's button and Finish: the quest helper or not. Yes picks
-- its settings through the draft into the setup's profile (the arrow only
-- with QuestieDB on); no, or closing the guide, puts them back.
T.test("installer: Quick setup asks about the quest helper before Finish; yes goes into the setup's profile", function()
    local DUI = login({ quests = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.eq(DUI:Get("Quests", "nav.arrow"), false, "off by default")
    choose(DUI, "Healer"); go(DUI)
    T.eq(DUI.Installer.flow.page, "q:quest")
    local ids = {}
    for _, s in ipairs(DUI.Installer.Steps()) do ids[#ids + 1] = s.id end
    T.eq(table.concat(ids, ","), "welcome,q:quest,finish", "only the quick question")
    local duel = DUI.Installer.pages.duel
    T.eq(duel.picked, "no", "what's in use: the marker is off")
    T.eq(plainText(duel.stepText), "Step 1 of 1"); T.eq(duel.next.text:GetText(), "Finish")
    press(duel.choices[1])
    T.eq(duel.picked, "yes")
    for _, s in ipairs(DUI.InstallerPages.Question("quest").bundle.set) do
        if not s.addon then T.eq(DUI:Get(s[1], s[2]), s[3], "previewed: " .. s[2]) end
    end
    T.eq(DUI:Get("Quests", "nav.arrow"), false, "no arrow without QuestieDB")
    press(duel.next)
    T.eq(DUI.Installer.flow.page, "finish")
    T.eq(DUI.Profiles.Chosen("character"), "Healer")
    local q = DaylightUIDB.profileData.Healer.modules.Quests
    T.eq(q.nav.marker, true, "in the Healer profile")
    T.falsy(q.nav.arrow, "the arrow left out")
end)

T.test("installer: with QuestieDB on, the quest helper's yes takes the arrow too", function()
    local DUI = login({ quests = true })
    stub.loadedAddOns.QuestieDB = true
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank"); go(DUI)
    press(DUI.Installer.pages.duel.choices[1])
    T.eq(DUI:Get("Quests", "nav.arrow"), true)
end)

T.test("installer: the quest helper's no, or closing the guide, puts its settings back", function()
    local DUI = login({ quests = true })
    stub.loadedAddOns.QuestieDB = true
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local arrow = DUI:Get("Quests", "nav.arrow")
    choose(DUI, "DPS/Tank"); go(DUI)
    local duel = DUI.Installer.pages.duel
    press(duel.choices[1])
    T.eq(DUI:Get("Quests", "nav.arrow"), true)
    press(duel.choices[2])
    T.eq(DUI:Get("Quests", "nav.arrow"), arrow, "no: back")
    T.falsy(DUI.InstallerDraft.Picked("Quests", "nav.arrow"))
    press(duel.choices[1])
    closeGuide()
    T.eq(DUI:Get("Quests", "nav.arrow"), arrow, "closed: back")
end)

T.test("installer: without the quest tracker, Quick setup goes straight to Finish", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank"); go(DUI)
    T.eq(DUI.Installer.flow.page, "finish")
    T.falsy(DUI.InstallerDraft.Active(), "no draft to keep")
end)






T.test("installer: Quick setup asks about a clashing addon, and Daylight UI's pick turns it off", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.loadedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank"); go(DUI)
    T.eq(DUI.Installer.flow.page, "q:clash:Baganator", "asked first")
    local duel = DUI.Installer.pages.duel
    T.eq(duel.picked, "ours", "Daylight UI lit")
    T.isnil(DUI.Installer.flow.clashes.Baganator, "nothing answered before it is passed")
    press(duel.next)
    T.eq(DUI.Installer.flow.page, "finish")
    T.eq(stub.addonState.Baganator[UnitGUID("player")], false)
end)



T.test("installer tour: with dual spec, both sets on the same layout share the named profile", function()
    local DUI = login({ specGroups = 2 })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    DUI.Installer.ToFinish()
    T.eq(DUI.Profiles.Chosen(1), "Tester")
    T.eq(DUI.Profiles.Chosen(2), "Tester")
end)


T.test("installer: General > Home runs the guide again", function()
    local DUI = login()
    local found
    for _, g in ipairs(DUI.Options.GetPage("home").groups) do
        for _, item in ipairs(g.items) do
            if item.label == "Setup guide" then found = item end
        end
    end
    T.truthy(found, "the button")
    found.func()
    T.truthy(DaylightUIInstaller:IsShown())
end)



T.test("installer: Quick setup leaves a clashing addon alone when our module isn't installed", function()
    local DUI = login()
    stub.installedAddOns = { Baganator = true }
    stub.loadedAddOns = { Baganator = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank"); go(DUI)
    T.isnil(stub.addonState.Baganator, "nothing to replace it with")
end)

T.test("installer: closing during the Finish checklist leaves no Reload button on screen", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_Bags = true }
    stub.loadedAddOns = { DaylightUI_Bags = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank"); go(DUI)
    closeGuide()
    stub.RunTimers()
    T.falsy(DaylightUIInstaller:IsShown(), "closed")
    local b = DUI.InstallerUI.ReloadButton()
    T.truthy(b == nil or not b:IsShown(), "no button left floating")
end)



T.test("installer: running the guide again builds no new listeners", function()
    local DUI = login()
    local on = DUI.On
    local n = 0
    DUI.On = function(name, fn)
        if name == "SettingChanged" then n = n + 1 end
        return on(name, fn)
    end
    local function tour()
        DUI.Installer.Show()
        choose(DUI, "mine"); go(DUI)
        for _, s in ipairs(DUI.Installer.Steps()) do DUI.Installer.Go(s.id) end
        closeGuide()
    end
    tour()
    local first = n
    tour()
    tour()
    DUI.On = on
    T.eq(n, first, "none added by running it again")
end)

T.test("installer: hiding the Reload button lets go of the page it was laid over", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    UI.Open({})
    local slot = CreateFrame("Frame", nil, UIParent)
    T.truthy(UI.ShowReload(slot))
    local b = UI.ReloadButton()
    T.truthy(b:GetNumPoints() > 0, "laid over the slot")
    UI.HideReload()
    T.falsy(b:IsShown())
    T.eq(b:GetNumPoints(), 0, "no anchor left on our frame")
    T.truthy(UI.ShowReload(slot))
    stub.EnterCombat()
    T.falsy(b:IsShown(), "hidden as combat starts")
    stub.LeaveCombat()
    T.eq(b:GetNumPoints(), 0, "and let go once it may be touched")
end)

-- ---------------------------------------------------------------------
-- Profile packs (Profiles.RegisterPack) in the guide
-- ---------------------------------------------------------------------

T.test("installer: a profile pack gets a welcome card; its button sets the character up on that profile, with its own layout", function()
    local DUI = login()
    DUI.RegisterPack("TestPack", { label = "Test UI", author = "Someone",
        profiles = { { name = "Test UI", data = { general = { borderPx = 3 } }, sub = "One line." },
                     { name = "Test UI Healer", data = {}, role = "Healer" } } })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local page = DUI.Installer.pages.welcome
    T.truthy(page.packs.TestPack, "a card for the pack")
    page.Pick("pack:TestPack")
    T.truthy(page.profile:IsShown(), "its profiles in the list beside the button")
    DUI.Installer.flow.profile = "Test UI"
    go(DUI)
    T.eq(DUI.Installer.flow.page, "finish")
    T.truthy(string.find(DUI.Installer.Summary()[1].text, "Test UI", 1, true), "named as the pack names it")
    T.eq(DUI.Profiles.Chosen("character"), "Test UI")
    T.eq(DaylightUIDB.profileData["Test UI"].general.borderPx, 3, "the pack's settings")
    T.truthy(layoutNamed("DaylightUI - Test UI"), "its own layout")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)



T.test("installer: with Questie on, a question asks which quest tracker", function()
    local profile = { trackerEnabled = true }
    local DUI = login({ quests = true, before = function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { API = { isReady = true }, db = { profile = profile } }
    end })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    local I = DUI.Installer
    local q = I.QuestionById("clash:Questie")
    T.truthy(q, "Questie's question")
    T.eq(I.Answer(q), "ours", "ours first")
    I.Pick(q, "theirs")
    T.eq(DUI:Get("Quests", "tracker"), false, "Questie's tracker picked")
    T.eq(DUI.DB.Root().questieAsked, true, "not asked again after the guide")
    T.eq(I.Answer(q), "theirs")
    _G.Questie = nil
end)


-- An account whose DPS/Tank was changed (here: raid tiles from the old
-- healer frames) and a character that has a profile of its own name already.
local function changedStandard(DUI)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank"); go(DUI)
    closeGuide()
    local mods = DaylightUIDB.profileData["DPS/Tank"].modules
    mods.UnitFrames = mods.UnitFrames or {}
    local uf = mods.UnitFrames
    uf.raid = uf.raid or {}
    uf.raid.width, uf.raid.fillVertical = 60, true
    DaylightUIDB.profileData["DPS/Tank"].positions["unitframes.raid"] = { 0, -312 }
end
local function tourPick(DUI, key)
    local I = DUI.Installer
    if not DaylightUIInstaller:IsShown() then DUI.RunCommand("install") end
    I.Start("tour")
    I.Pick(I.QuestionById("role"), key)
    return I
end
local function raidOf(name)
    local p = DaylightUIDB.profileData[name]
    local uf = p and p.modules and p.modules.UnitFrames
    return uf and uf.raid or {}, p and p.positions or {}
end

T.test("installer tour: a ready-made card is the layout its picture shows, whatever the account's DPS/Tank became", function()
    local DUI = login()
    changedStandard(DUI)
    local I = tourPick(DUI, "DPS/Tank")
    local name = I.SaveAs()
    I.ToFinish()
    local raid, pos = raidOf(name)
    T.isnil(raid.width, "the standard tiles, not the changed DPS/Tank's")
    T.isnil(raid.fillVertical)
    T.isnil(pos["unitframes.raid"], "the raid in its standard spot")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer tour: picking a layout rebuilds the character's own profile from it; Keep leaves it", function()
    local DUI = login()
    changedStandard(DUI)
    local I = tourPick(DUI, "Healer")
    local name = I.SaveAs()
    I.ToFinish()
    closeGuide()
    T.eq(raidOf(name).width, 60, "made as Healer")
    -- Again, picking DPS / Tank this time, and one look pick on the way.
    I = tourPick(DUI, "DPS/Tank")
    DUI.InstallerDraft.Set("general", "accent", "daylight")
    T.eq(I.SaveAs(), name, "saved under the same name")
    T.truthy(string.find(I.SaveNote() or "", "DPS / Tank", 1, true), "the note says what it's rebuilt from")
    I.ToFinish()
    T.isnil(raidOf(name).width, "rebuilt as DPS / Tank: no healer tiles")
    T.eq(DaylightUIDB.profileData[name].general.accent, "daylight", "with the pick made on the way")
    T.truthy(I.flow.reload, "reloads into it")
    closeGuide()
    -- Keep: as it is.
    DaylightUIDB.profileData[name].modules.UnitFrames.raid = { width = 50 }
    I = tourPick(DUI, name)
    I.ToFinish()
    T.eq(raidOf(name).width, 50, "kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)



T.test("installer tour: a Finish that can't place the layout leaves no new profile behind", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local I = tourPick(DUI, "Healer")
    local name = I.SaveAs()
    EditModeManagerFrame:Show()                        -- Edit Mode open: the game won't take a layout
    I.ToFinish()
    T.falsy(I.flow.finished)
    T.isnil(DaylightUIDB.profileData[name], "the profile Make it mine would save into isn't made")
    T.isnil(DaylightUIDB.profileData.Healer, "nor the ready-made it was built from")
    EditModeManagerFrame:Hide()
    I.Finish()
    T.truthy(I.flow.finished, "Try again finishes")
    T.truthy(DaylightUIDB.profileData[name], "and saves it")
    T.truthy(layoutNamed("DaylightUI - " .. name), "with its layout")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer questions: the bars, plates and calm questions pick their presets through the draft", function()
    local DUI = login({ nameplates = true, module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    local I = DUI.Installer
    I.Pick(I.QuestionById("bars"), "one")
    T.eq(DUI:Get("ActionBars", "bars.bar2.visible"), "hidden", "one row: bar 2 hidden")
    T.eq(DUI:Get("ActionBars", "bars.left.visible"), "hidden")
    I.Pick(I.QuestionById("plateSize"), "large")
    T.eq(DUI:Get("Nameplates", "scale"), 1.2); T.eq(DUI:Get("Nameplates", "height"), 20)
    I.Pick(I.QuestionById("calm"), "float")
    T.eq(DUI:Get("UnitFrames", "player.fade.mode"), "float")
    T.eq(DUI:Get("ActionBars", "bars.main.fade.mode"), "float")
    T.eq(I.Answer(I.QuestionById("calm")), "float")
    -- X puts it all back (every pick is a draft).
    DUI.InstallerDraft.Revert()
    T.eq(DUI:Get("ActionBars", "bars.bar2.visible"), "always")
    T.eq(DUI:Get("Nameplates", "scale"), 1)
end)

T.test("installer: a plugin's page comes after Daylight UI's own, and its onFinish runs on Finish", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local me = DUI.API.For("Guide")
    local finished = 0
    T.eq(me.AddSetupStep({ id = "look", title = "Guide's look", desc = "Pick a size.",
        groups = { { label = "Size", rows = { { "general", "scale" } } } },
        onFinish = function() finished = finished + 1 end }), true)
    T.eq(me.AddSetupStep({ id = "bad" }), false, "a step needs a title and groups")
    DUI.Installer.Start("tour")
    local ids = {}
    for _, def in ipairs(DUI.Installer.Steps()) do ids[#ids + 1] = def.id end
    local at, last = nil, #ids
    for i, id in ipairs(ids) do if id == "Guide:look" then at = i end end
    T.truthy(at, "listed")
    T.eq(ids[last], "finish")
    T.eq(at, last - 1, "after Daylight UI's own pages, before Finish")
    DUI.Installer.Go("Guide:look")
    T.truthy(DUI.Installer.pages["Guide:look"], "its page is built")
    DUI.Installer.Go("finish")
    DUI.Installer.Finish()
    T.eq(finished, 1)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer: a plugin step can show its own text and buttons instead of settings", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local me = DUI.API.For("Guide")
    local clicked = 0
    T.eq(me.AddSetupStep({ id = "chat", title = "Chat", text = "Set up the chat the way Guide likes it.",
        buttons = { { text = "Set up chat", onClick = function() clicked = clicked + 1 return "Chat set up" end } } }), true)
    DUI.Installer.Start("tour")
    DUI.Installer.Go("Guide:chat")
    local page = DUI.Installer.pages["Guide:chat"]
    T.truthy(page.text and page.buttons, "text and buttons drawn")
    press(page.buttons.buttons[1])
    T.eq(clicked, 1)
    T.eq(page.buttons.status:GetText(), "Chat set up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer: a plugin's own guide shows after Daylight UI's, once per version", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local PI = DUI.InstallerPlugins
    local me = DUI.API.For("Guide")
    local finished, drawn = 0, nil
    T.eq(me.AddInstaller({ pages = {} }), false, "a guide needs pages")
    T.eq(me.AddInstaller({ title = "Guide", pages = {
        { title = "Welcome", text = "Thanks for using Guide." },
        { title = "Size", groups = { { label = "Size", rows = { { "general", "scale" } } } } },
        { title = "Yours", build = function(holder, width) drawn = width return 40 end },
    }, onFinish = function() finished = finished + 1 end }), true)
    T.eq(PI.ShowDue(), false, "not before Daylight UI is set up")
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    DUI.InstallerUI.QuietHide()   -- the main guide, up since login
    T.eq(PI.ShowDue(), true)
    T.truthy(DUI.InstallerUI.IsShown())
    PI.Next()
    local before = DUI:Get("general", "scale")
    DUI.InstallerDraft.Set("general", "scale", 0.9)
    PI.Next()
    T.truthy(drawn and drawn > 0, "its own drawing got the page's width")
    PI.Next()   -- Finish
    T.eq(finished, 1)
    T.eq(DUI:Get("general", "scale"), 0.9, "the pick stays")
    T.falsy(DUI.InstallerUI.IsShown(), "closed after the last guide")
    T.eq(#PI.Due(), 0, "seen")
    T.truthy(before ~= nil)
    -- A new version shows it again; X puts its picks back and counts as seen.
    me.AddInstaller({ title = "Guide", version = 2, pages = {
        { title = "Size", groups = { { label = "Size", rows = { { "general", "scale" } } } } } } })
    T.eq(#PI.Due(), 1)
    T.eq(PI.ShowDue(), true)
    DUI.InstallerDraft.Set("general", "scale", 0.8)
    closeGuide()
    T.eq(DUI:Get("general", "scale"), 0.9, "put back")
    T.eq(#PI.Due(), 0)
    T.eq(me.ShowInstaller(), true, "opened again on request")
    closeGuide()
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer: finishing Daylight UI's guide without a reload goes on to the plugins' guides", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    DUI.API.For("Guide").AddInstaller({ pages = { { title = "Welcome", text = "Hi." } } })
    DUI.Installer.Mark("installed")
    DUI.Installer.MarkSeen()
    DUI.Installer.Done()
    T.truthy(DUI.InstallerPlugins.Running(), "the plugin's guide shows")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer screen: pieces sit where the mock-up puts them, as shares of its width", function()
    local DUI = login()
    local f = DUI.InstallerScreen.New(UIParent, 200)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
    f.Set({ role = "DPS/Tank", bars = "two", calm = "shown", cast = "below", portrait = "socket", fight = true }, true)
    T.eq(f:GetHeight(), 112.5)
    -- The fake game doesn't lay frames out: read each piece's spot off its anchor to the picture.
    local function at(piece)
        local point, rel, relPoint, x, y = piece:GetPoint(1)
        T.eq(point, "TOPLEFT"); T.eq(rel, f); T.eq(relPoint, "TOPLEFT")
        return x, -y
    end
    local x, y = at(f.pieces.you)
    T.near(x, 52, 0.5, "your frame 26% in"); T.near(y, 72, 0.5, "and 36% down")
    T.near(f.pieces.you:GetWidth(), 36, 0.5)
    x, y = at(f.pieces.chat)
    T.near(x, 4, 0.5); T.near(y, 82.5, 0.5); T.near(f.pieces.chat:GetWidth(), 46, 0.5)
    T.truthy(f.pieces.party:IsShown()); T.falsy(f.pieces.tiles:IsShown())
    T.truthy(f.pieces.row2:IsShown()); T.falsy(f.pieces.side:IsShown())
    f.Set({ role = "Healer" }, true)
    T.truthy(f.pieces.tiles:IsShown()); T.falsy(f.pieces.party:IsShown())
    x, y = at(f.pieces.you); T.near(y, 66, 0.5, "the healer's frame 33% down")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer screen: out of a fight the target goes and Calm fades your frame and bars", function()
    local DUI = login()
    local f = DUI.InstallerScreen.New(UIParent, 200)
    f.Set({ role = "DPS/Tank", bars = "sides", calm = "calm", cast = "below", portrait = "socket", fight = false }, true)
    T.eq(f.pieces.target:GetAlpha(), 0); T.eq(f.pieces.cast:GetAlpha(), 0)
    T.near(f.pieces.you:GetAlpha(), 0.2, 0.001); T.near(f.pieces.row1:GetAlpha(), 0.2, 0.001)
    T.near(f.pieces.side:GetAlpha(), 0.1, 0.001); T.eq(f.pieces.tracker:GetAlpha(), 1)
    f.Set({ calm = "float" }, true)
    T.near(f.pieces.tracker:GetAlpha(), 0.04, 0.001)
    f.Set({ fight = true }, true)
    T.eq(f.pieces.you:GetAlpha(), 1); T.eq(f.pieces.target:GetAlpha(), 1)
    f.Set({ role = "blueprint" }, true)
    T.truthy(f.plan:IsShown()); T.falsy(f.sky:IsShown()); T.falsy(f.pieces.cast:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer window: a bare page owns the whole window, with the banner at the height it asks for", function()
    local DUI = login()
    local UI = DUI.InstallerUI
    UI.Open({ width = UI.SHOW_W, height = UI.SHOW_H, lit = true })
    local page = CreateFrame("Frame", nil, UI.Body()); page:SetSize(900, 625)
    UI.SetPage(page, { bare = true, still = true, veil = true, banner = { height = 190, crop = { 0.286, 0.750 }, shift = 27 } })
    local f = UI.Frame()
    T.falsy(f.rail:IsShown()); T.falsy(f.header:IsShown()); T.falsy(f.footer:IsShown())
    T.falsy(f.scroll.bar:IsShown(), "no scroll bar")
    -- Corner to corner (the fake game keeps anchors, it doesn't size frames from them).
    for i = 1, f.scroll:GetNumPoints() do
        local _, rel, _, x, y = f.scroll:GetPoint(i)
        T.eq(rel, f); T.eq(x or 0, 0); T.eq(y or 0, 0)
    end
    T.truthy(f.scroll:GetNumPoints() >= 1)
    T.truthy(f.banner:IsShown()); T.eq(f.banner:GetHeight(), 190)
    T.near(f.banner.sunrise:GetWidth(), 819, 1, "the art 819 wide")
    local _, _, _, x = f.banner.sunrise:GetPoint(1); T.eq(x, 27)
    UI.SetPage(page, { bare = true, still = true })
    T.falsy(f.banner:IsShown(), "no banner asked for")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer opening: four equal cards, nothing happens until one is picked and the button pressed", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local page = DUI.Installer.pages.welcome
    T.eq(#page.cards, 4)
    for _, c in ipairs(page.cards) do T.eq(c:GetWidth(), 204); T.eq(c:GetHeight(), 200) end
    T.eq(page.cards[4].key, "mine")
    local _, _, _, x1 = page.cards[1]:GetPoint(1)
    local _, _, _, x2 = page.cards[2]:GetPoint(1)
    T.eq(x1, 24); T.eq(x2 - x1, 216, "12 between cards")
    T.falsy(page.go:IsShown(), "no button before a pick"); T.truthy(page.hint:IsShown())
    choose(DUI, "Healer")
    T.truthy(page.go:IsShown()); T.eq(page.go.text:GetText(), "Play now")
    T.eq(DUI.Installer.flow.path, nil, "a pick alone starts nothing")
    T.near(page.cards[1]:GetAlpha(), 0.78, 0.001, "the others dim")
    choose(DUI, "mine")
    T.eq(page.go.text:GetText(), "Let's go")
    go(DUI)
    T.eq(DUI.Installer.flow.path, "tour")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer opening: a set-up character gets a fifth card, lit, and Keep it changes nothing", function()
    local DUI = login()
    DUI.Installer.Install()
    DaylightUIDB.installerSeen = nil
    DUI = reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local page = DUI.Installer.pages.welcome
    T.eq(#page.cards, 5); T.eq(page.cards[1].key, "keep"); T.eq(page.picked, "keep")
    T.eq(page.cards[1]:GetWidth(), 161)
    T.truthy(page.go:IsShown()); T.eq(page.go.text:GetText(), "Keep it")
    local before = DUI.DB.ActiveName()
    go(DUI)
    T.eq(DUI.Installer.flow.path, "keep"); T.eq(DUI.DB.ActiveName(), before)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer opening: a profile pack gets its own card after Make it mine, and its button is a Quick setup", function()
    local DUI = login()
    DUI.RegisterPack("TestPack", { label = "Test UI", author = "Someone",
        profiles = { { name = "Test UI", data = {} } } })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local page = DUI.Installer.pages.welcome
    T.eq(#page.cards, 5); T.eq(page.cards[5]:GetWidth(), 161)
    T.truthy(string.find(page.cards[5].key, "^pack:"))
    page.Pick(page.cards[5].key)
    T.falsy(page.profile:IsShown(), "one profile: no list")
    go(DUI)
    T.eq(DUI.Installer.flow.path, "quick")
    T.eq(DUI.Installer.Target(), "Test UI")
end)

T.test("installer opening: with motion off every piece is there at once", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    DUI:Set("general", "motion", false)                -- the guide's draft holds it
    DUI.Installer.Go("welcome")
    local page = DUI.Installer.pages.welcome
    for _, c in ipairs(page.cards) do T.eq(c:GetAlpha(), 1) end
    T.eq(page.title:GetAlpha(), 1); T.eq(page.plaque:GetAlpha(), 1); T.eq(page.hint:GetAlpha(), 1)
end)


T.test("installer question: three choices split the area in three, the one in use is lit, and Next works untouched", function()
    local DUI = login()
    local Duel = DUI.InstallerDuel
    local picked, went
    local page = Duel.New(UIParent)
    page.Set(question(3, { pick = function(k) picked = k end, next = function() went = true end }))
    T.eq(#page.choices, 3); T.eq(#page.lines, 2)
    T.eq(page.picked, "b")
    T.near(page.choices[2].wash:GetAlpha(), 0.3, 0.001); T.near(page.choices[1].wash:GetAlpha(), 0.07, 0.001)
    -- Each column is a third of the area, and its words are centered on it.
    local _, rel, _, x = page.choices[2]:GetPoint(1)
    T.eq(rel, page.area); T.near(x, 292, 0.01); T.near(page.choices[2]:GetWidth(), 292, 0.01)
    local point, holder, relPoint = page.choices[1].content:GetPoint(1)
    T.eq(point, "CENTER"); T.eq(holder, page.choices[1]); T.eq(relPoint, "CENTER")
    T.eq(page.ask:GetText(), "Which?"); T.eq(plainText(page.stepText), "Step 2 of 5")
    settle(DUI)
    T.near(page.bar:GetWidth(), 260 * 2 / 5, 1)
    press(page.next); T.truthy(went, "Next needs no pick"); T.isnil(picked)
    press(page.choices[1]); T.eq(picked, "a"); T.eq(page.picked, "a")
    settle(DUI)
    T.near(page.choices[1].wash:GetAlpha(), 0.3, 0.05)
    T.truthy(page.choices[1].tick:IsShown()); T.falsy(page.choices[2].tick:IsShown())
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer question: when what's in use is none of the choices nothing is lit, and Next still works", function()
    local DUI = login()
    local went
    local page = DUI.InstallerDuel.New(UIParent)
    local q = question(4, { next = function() went = true end })
    q.current = nil
    page.Set(q)
    T.eq(#page.choices, 4, "four still split"); T.isnil(page.picked)
    for _, c in ipairs(page.choices) do T.near(c.wash:GetAlpha(), 0.07, 0.001) end
    T.truthy(string.find(page.hint:GetText(), "your setup keeps what it has", 1, true))
    press(page.next); T.truthy(went)
    q.warn = "Tester is made again from Healer, with your picks."
    page.Set(q)
    T.eq(page.hint:GetText(), q.warn)
    q.warn, q.first, q.current = nil, true, "a"
    page.Set(q)
    T.eq(page.hint:GetText(), "Click the one you like, then press Next. Not sure? Just press Next: it keeps the one that's lit.")
end)

T.test("installer question: ten choices fan out, the picked one open until the mouse opens another", function()
    local DUI = login()
    local page = DUI.InstallerDuel.New(UIParent)
    page.Set(question(10, { current = "a" }))
    settle(DUI)
    -- A strip's share of the fan: its width less the 2-wide edge every strip after the first has.
    local function share(i) return page.choices[i]:GetWidth() - (i > 1 and 2 or 0) end
    T.near(share(1) / share(2), 5.5, 0.1)
    page.choices[4]:GetScript("OnEnter")(page.choices[4]); settle(DUI)
    T.near(share(4) / share(1), 5.5, 0.1, "the one under the mouse opens instead")
    T.near(page.choices[4].content:GetAlpha(), 1, 0.01); T.near(page.choices[4].mini:GetAlpha(), 0, 0.01)
    page.choices[4]:GetScript("OnLeave")(page.choices[4]); settle(DUI)
    T.near(share(1) / share(4), 5.5, 0.1, "and the picked one opens again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer question: with motion off nothing waits hidden", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    DUI:Set("general", "motion", false)
    local page = DUI.InstallerDuel.New(UIParent)
    page.Set(question(2)); page.Play()
    T.eq(page.ask:GetAlpha(), 1); T.eq(page.choices[2]:GetAlpha(), 1)
end)

local EVERY = { module = true, nameplates = true, tooltip = true, bags = true, quests = true }
-- Every part loaded (the bag window needs the game's container calls, which
-- this test world doesn't fill in: answered with nothing).
local function every(extra)
    local o = { before = function()
        _G.C_Container = _G.C_Container or setmetatable({}, { __index = function() return function() end end })
    end }
    for k, v in pairs(EVERY) do o[k] = v end
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

T.test("installer: Make it mine walks fifteen questions, each with its pick lit, and Next alone gets to the end", function()
    local DUI = login(every())
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    local I = DUI.Installer
    T.eq(I.flow.page, "q:role")
    local duel = I.pages.duel
    T.eq(plainText(duel.stepText), "Step 1 of 15")
    local unlit = {}
    for i = 1, 15 do
        if duel.picked == nil then unlit[#unlit + 1] = I.flow.page end
        T.eq(duel.next.text:GetText(), i == 15 and "Finish" or "Next")
        press(duel.next)
    end
    T.eq(table.concat(unlit, ","), "", "every question has its pick lit")
    T.eq(I.flow.page, "finish")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer: a pick shows on the real UI at once, Back keeps it, and X puts everything back", function()
    local DUI = login(every())
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local was = DUI:Get("general", "font")
    choose(DUI, "mine"); go(DUI)
    local I = DUI.Installer
    I.Go("q:font")
    press(I.pages.duel.choices[8])
    T.eq(DUI:Get("general", "font"), "russo")
    I.Back(); I.Next()
    T.eq(I.flow.page, "q:font"); T.eq(I.pages.duel.picked, "russo")
    closeGuide()
    T.eq(DUI:Get("general", "font"), was)
    T.truthy(DUI.Installer.State() ~= "installed")
end)

T.test("installer: with nameplates off its four questions are left out and the count follows", function()
    local DUI = login(every({ nameplates = false }))
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    for _, q in ipairs(DUI.Installer.Questions()) do T.truthy(q.part ~= "Nameplates", q.id) end
    T.eq(#DUI.Installer.Questions(), 11)
    T.eq(plainText(DUI.Installer.pages.duel.stepText), "Step 1 of 11")
end)

T.test("installer: another addon drawing nameplates is asked about right after the layout, in both paths, and nothing is switched off unasked", function()
    local function start(key)
        local DUI = login(every())
        stub.installedAddOns.DaylightUI_Nameplates, stub.installedAddOns.Plater, stub.loadedAddOns.Plater = true, true, true
        stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
        choose(DUI, key); go(DUI)
        return DUI
    end
    local DUI = start("mine")
    local I = DUI.Installer
    T.eq(I.Questions()[1].id, "role"); T.truthy(I.Questions()[2].clash, "the clash is the second question")
    T.eq(I.Questions()[2].part, "Other addons")
    T.falsy(I.ClashTakesOver(I.Questions()[2].clash), "not answered before it is asked")
    I.Pick(I.Questions()[2], "theirs")
    for _, q in ipairs(I.Questions()) do T.truthy(q.part ~= "Nameplates", "nameplate questions are gone") end
    closeGuide()
    DUI = start("DPS/Tank")
    T.truthy(DUI.Installer.Questions()[1].clash, "Quick setup asks too")
    T.eq(DUI.Installer.flow.page, "q:clash:Plater")
end)

T.test("installer draft: a ready-made layout that isn't saved yet still shows its own values", function()
    local DUI = login(every())
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    local I = DUI.Installer
    T.isnil(DaylightUIDB.profileData["Immersive Preset"], "not saved")
    I.Pick(I.Questions()[1], "Immersive Preset")
    local fade = DUI.DB.GetPath(DUI.Profiles.ReadyData("Immersive Preset").modules.ActionBars, "bars.main.fade.mode")
    T.truthy(fade ~= nil and fade ~= DUI:GetModule("ActionBars").defaults.bars.main.fade.mode, "Immersive has its own fade")
    T.eq(DUI:Get("ActionBars", "bars.main.fade.mode"), fade, "Immersive's own fade shows at once")
    T.isnil(I.Answer(I.QuestionById("calm")), "none of the three: nothing lit")
    while I.flow.page ~= "finish" do press(I.pages.duel.next) end
    local saved = DaylightUIDB.profileData[DUI.Profiles.Chosen("character")]
    T.eq(DUI.DB.GetPath(saved.modules.ActionBars, "bars.main.fade.mode"), fade, "and pressing only Next keeps it")
end)

T.test("installer: a character whose name is already someone's profile saves beside it, never over it", function()
    local DUI = login({ before = function()
        DaylightUIDB = { installerSeen = 1e9, profileData = { Tester = { general = { font = "lato" }, positions = {}, modules = {} } },
                         characters = { ["Tester-Other"] = { profile = "Tester", install = "installed" } } }
    end })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    T.eq(DUI.Installer.SaveAs(), "Tester 2")
    DUI.Installer.ToFinish()
    T.eq(DaylightUIDB.profileData.Tester.general.font, "lato", "the other character's profile is untouched")
    T.eq(DUI.Profiles.Chosen("character"), "Tester 2")
end)

T.test("installer: a pack's extras are asked before saving, on by default", function()
    local DUI = login()
    stub.loadedAddOns.Details = true
    local ran = 0
    DUI.RegisterPack("X", { label = "X UI", profiles = { { name = "X UI", data = {} } },
        extras = { { addon = "Details", label = "Details!", apply = function() ran = ran + 1 end },
                   { addon = "BigWigs", apply = function() error("not loaded: never run") end } } })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "pack:X"); go(DUI)
    local I = DUI.Installer
    local qs = I.Questions()
    local q = qs[#qs]
    T.truthy(q.extra, "the last question is the extra"); T.eq(#qs, 1, "only the loaded addon's")
    T.eq(I.Answer(q), "yes")
    T.eq(I.pages.duel.ask:GetText(), "Set up Details! to match?")
    I.Pick(q, "no")
    T.falsy(I.ExtraOn(q.extra.key))
    I.Pick(q, "yes")
    press(I.pages.duel.next)
    T.eq(ran, 1, "run at Finish")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer: a fight on a question hides the guide and brings it back on the same one", function()
    local DUI = login(every())
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    DUI.Installer.Go("q:bars")
    press(DUI.Installer.pages.duel.choices[3])
    stub.EnterCombat(); T.falsy(DUI.InstallerUI.IsShown())
    stub.LeaveCombat(); T.truthy(DUI.InstallerUI.IsShown()); T.eq(DUI.Installer.flow.page, "q:bars")
    T.eq(DUI.Installer.pages.duel.picked, "sides", "the same pick lit")
end)

T.test("installer: Quick setup asks only the quest helper, then finishes", function()
    local DUI = login(every())
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "DPS/Tank"); go(DUI)
    T.eq(DUI.Installer.flow.page, "q:quest")
    T.eq(DUI.Installer.pages.duel.next.text:GetText(), "Finish")
end)

T.test("installer: Make it mine puts every talent set on the one layout picked", function()
    local DUI = login(every({ specGroups = 2 }))
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    local I = DUI.Installer
    I.Pick(I.QuestionById("role"), "Healer")
    for _, slot in ipairs(I.Slots()) do T.eq(I.flow.roles[slot], "Healer", tostring(slot)) end
end)

T.test("installer finish: the tags name the layout and only what was changed", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    choose(DUI, "mine"); go(DUI)
    local I = DUI.Installer
    T.eq(I.Tags()[2].label, "Everything else")
    I.Pick(I.QuestionById("font"), "russo")
    local tags = I.Tags()
    T.eq(tags[1].label, "Layout"); T.eq(tags[2].label, "Font"); T.eq(tags[2].value, "Russo One"); T.eq(#tags, 2)
    I.ToFinish()
    local page = I.pages.finish
    T.eq(page.tags[2].value:GetText(), "Russo One")
    T.eq(page.title.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "Your UI is ready, Tester")
end)
