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
    stub.popup = nil
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.isnil(stub.popup, "no second reload asked")
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

T.test("installer draft: Seed shows the target profile's look but never undoes a pick", function()
    local DUI = login()
    local D = DUI.InstallerDraft
    local made = DUI.Profiles.AddPreset("Healer")
    local pd = DaylightUIDB.profileData
    pd.Healer.general.font = "poppins"
    pd.Healer.general.accent = "class"
    local font, accent = DUI:Get("general", "font"), DUI:Get("general", "accent")
    D.Begin()
    D.Track("general", "font")
    D.Track("general", "accent")
    D.Set("general", "accent", "gradient")
    D.Seed(made)
    T.eq(DUI:Get("general", "font"), "poppins", "Healer's font shown")
    T.eq(DUI:Get("general", "accent"), "gradient", "the pick kept")
    D.Seed(nil)
    T.eq(DUI:Get("general", "font"), font, "seeded back when the target changes")
    D.Seed(made)
    D.Commit(made)
    T.eq(pd.Healer.general.font, "poppins")
    T.eq(pd.Healer.general.accent, "gradient")
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

T.test("installer pages: every option the tour offers exists in the options", function()
    local DUI = login({ module = true, bags = true, chat = true, infopanel = true, tooltip = true, qol = true, nameplates = true, quests = true })
    local P = DUI.InstallerPages
    for _, page in ipairs(P.TOUR) do
        for _, g in ipairs(page.groups or {}) do
            for _, r in ipairs(P.Refs(g)) do
                T.truthy(P.Find(r[1], r[2]), page.id .. ": " .. r[1] .. " " .. r[2])
            end
        end
    end
    for _, k in ipairs(P.Keys(P.Quick())) do T.truthy(P.Find(k[1], k[2]), "quick: " .. k[1] .. " " .. k[2]) end
    T.truthy(P.Find("UnitFrames", "player.portrait"), "portraits")
    T.eq(P.Where("appearance"), "General > Appearance")
    T.eq(P.Module("Bags").addon, "DaylightUI_Bags")
end)

T.test("installer pages: a group needs its module", function()
    local DUI = login()
    local P = DUI.InstallerPages
    local bags
    for _, g in ipairs(P.Get("everyday").groups) do
        if g.needs == "Bags" and g.cards then bags = g end
    end
    T.falsy(P.GroupAvailable(bags), "no bag module loaded")
    local accent = P.Get("look").groups[1]
    T.truthy(P.GroupAvailable(accent), "the core's own options always are")
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

T.test("installer cards: a module tile switches through its item; not installed has no switch", function()
    local DUI = login()
    local Cards = DUI.InstallerCards
    local on = true
    local mod = DUI.InstallerPages.MODULES[1]
    local tile
    tile = Cards.Tile(UIParent, mod, 260, function() return on end, function(v) on = v; tile.Refresh() end, true)
    tile.row.control:Click()
    T.eq(on, false, "switched off")
    local missing = Cards.Tile(UIParent, mod, 260, function() return false end, function() end, false)
    T.isnil(missing.row)
    T.truthy(string.find(missing.name:GetText(), "not installed", 1, true))
end)

T.test("installer cards: a clash card picks ours or theirs", function()
    local DUI = login()
    local v
    local card = DUI.InstallerCards.Clash(UIParent, DUI.InstallerPages.CLASHES[3], 500,
        function() return v end, function(x) v = x end)
    T.truthy(card.ours.active, "ours first")
    press(card.theirs)
    T.eq(v, "theirs"); T.truthy(card.theirs.active); T.falsy(card.ours.active)
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
    T.truthy(string.find(DUI.Installer.pages.welcome.greeting:GetText(), "Tester", 1, true), "greets by name")
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

T.test("installer: Quick setup, Damage / Tank: the standard layout, set up, and a Reload button", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    T.eq(DUI.Installer.flow.page, "finish")
    T.eq(#saved.layouts, 0, "nothing written before Finish")
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank")
    T.truthy(layoutNamed("DaylightUI - DPS/Tank"), "the layout written")
    T.eq(saved.activeLayout, 3, "and in use")
    T.eq(DUI.Installer.State(), "installed")
    T.eq(DaylightUIDB.installerSeen, DUI.Installer.VERSION)
    stub.RunTimers()
    local b = DUI.InstallerUI.ReloadButton()
    T.truthy(b and b:IsShown(), "the Reload button")
    T.eq(b:GetAttribute("macrotext"), "/reload")
    T.falsy(stub.reloaded, "never ReloadUI from our own code")
    for _, c in ipairs(DUI.Installer.pages.finish.checks) do T.truthy(c:IsShown(), "every line ticked") end
end)

T.test("installer: Quick setup, Healer: the healer profile and its own layout", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.healer)
    press(DUI.Installer.pages.finish.finish)
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
    for _, key in ipairs({ "dps", "healer" }) do
        local DUI = login({ module = true, infopanel = true })
        T.eq(DUI:Get("InfoPanel", "meter.enabled"), false, "folded before the guide too")
        stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
        press(DUI.Installer.pages.welcome.cards.quick[key])
        press(DUI.Installer.pages.finish.finish)
        local name = DUI.Profiles.Chosen("character")
        T.eq(DaylightUIDB.profileData[name].modules.InfoPanel.meter.enabled, false, key .. ": folded")
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
    local b = DUI.Installer.pages.welcome.cards.quick.leveling
    T.truthy(b, "an Immersive Preset button in Quick setup")
    T.noerror(function() b:GetScript("OnEnter")(b); b:GetScript("OnLeave")(b) end, "its hover text")
    press(b)
    T.eq(DUI.Installer.flow.page, "questhelp", "the quests loaded: the quest helper's question first")
    DUI.Installer.Next()
    press(DUI.Installer.pages.finish.finish)
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

T.test("installer: the role page offers DPS / Tank, Healer and Immersive Preset, three to a row", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    DUI.Installer.Start("tour")
    DUI.Installer.Go("role")
    local picker = DUI.Installer.pages.role.pickers.character
    T.truthy(picker.cards["Immersive Preset"], "an Immersive Preset card")
    T.noerror(function() picker.cards["Immersive Preset"]:GetScript("OnClick")(picker.cards["Immersive Preset"]) end)
    T.eq(DUI.Installer.flow.roles.character, "Immersive Preset")
    T.noerror(function() DUI.InstallerCards.Draw.role(picker.cards["Immersive Preset"], "Immersive Preset", 100, 60) end)
end)

T.test("installer: renaming a profile renames its layout, presets kept first in the save", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.healer)
    press(DUI.Installer.pages.finish.finish)
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
    press(DUI.Installer.pages.welcome.cards.quick.healer)
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "Healer")
    closeGuide()
    DUI.RunCommand("install")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank", "on the DPS/Tank profile")
    local _, index = layoutNamed("DaylightUI - DPS/Tank")
    T.eq(C_EditMode.GetLayouts().activeLayout, index, "its layout in use")
    T.truthy(layoutNamed("DaylightUI - Healer"), "the Healer one left as it was")
end)

T.test("installer: the welcome offers a profile they have only when there is one", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.isnil(DUI.Installer.pages.welcome.cards.mine, "only DPS/Tank, which has its own card: nothing to pick")
    closeGuide()
    DUI.Profiles.Create("Mine", nil, DUI.DB.DEFAULT)
    DUI.Installer.Show()
    T.truthy(DUI.Installer.pages.welcome.cards.mine, "offered now")
    -- The one this character is on when it's saved (the new bars' world
    -- starts from settings older than profiles), else the only one there.
    T.eq(DUI.Installer.flow.profile, DUI.DB.Saved("DPS/Tank") and "DPS/Tank" or "Mine", "picked")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank", "Quick setup still works with a profile around")
end)

T.test("installer: Use a setup I have puts the character on it, as it is", function()
    local DUI = login()
    local made = DUI.Profiles.Create("Mine", nil, DUI.DB.DEFAULT)
    DaylightUIDB.profileData[made].general.accent = "class"
    DUI.Installer.Show()
    DUI.Installer.flow.profile = "Mine"                -- picked in the dropdown
    press(DUI.Installer.pages.welcome.cards.mine.use)
    T.eq(DUI.Installer.flow.path, "existing")
    press(DUI.Installer.pages.finish.finish)
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
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank")
    T.eq(DaylightUIDB.profileData["DPS/Tank"].general.accent, "class", "left as it was")
end)

T.test("installer: another character on the account can use the first one's setup", function()
    local DUI = login()
    DUI.Installer.Install()                            -- the first character
    DUI:Set("general", "accent", "class")              -- and a change of its own
    stub.popup = nil
    saved.activeLayout = 1                             -- a new character: on the game's own layout
    DUI.DB.Root().characters = nil
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "asked, though the layout exists")
    T.eq(DUI.Installer.flow.mode, "new")
    -- DPS/Tank is the first one's profile: its card puts this one on it.
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank")
    T.eq(DaylightUIDB.profileData["DPS/Tank"].general.accent, "class", "as the first one left it")
    T.eq(saved.activeLayout, 3, "ours active for this character")
    T.isnil(stub.popup, "no popup: the guide has its own Reload")
end)

T.test("installer: a set-up character sees the guide once per account, with Keep my setup first", function()
    local DUI = login()
    DUI.Installer.Install()
    DaylightUIDB.installerSeen = nil                   -- set up before this guide existed
    DUI = reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.truthy(DaylightUIInstaller:IsShown(), "shown off")
    T.eq(DUI.Installer.flow.mode, "showcase")
    local keep = DUI.Installer.pages.welcome.cards.mine
    T.truthy(keep and keep.selected, "Keep my setup, picked")
    T.eq(keep.tag.text:GetText(), "In use")
    T.eq(DUI.Installer.flow.profile, "DPS/Tank", "the profile in use")
    press(keep.use)
    press(DUI.Installer.pages.finish.finish)
    stub.RunTimers()
    T.truthy(DUI.Installer.pages.finish.done:IsShown(), "nothing to reload: Done")
    local b = DUI.InstallerUI.ReloadButton()
    T.falsy(b and b:IsShown())
    press(DUI.Installer.pages.finish.done)
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
    stub.popup = nil
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "no guide")
    T.eq(saved.activeLayout, 3, "its layout back in use")
    T.eq(stub.popup, "DAYLIGHTUI_RELOAD", "asks for the reload")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    T.falsy(DaylightUIInstaller and DaylightUIInstaller:IsShown(), "nor on entering the world")
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
    stub.popup = nil
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")       -- a loading screen
    stub.FireEvent("PLAYER_ENTERING_WORLD")
    stub.RunTimers()
    T.eq(saved.activeLayout, mine, "still on its own layout")
    T.isnil(stub.popup, "no reload asked")
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
    stub.popup = nil
    DUI.EditMode.AutoSave("updated")
    T.eq(saved.activeLayout, mine, "still on its own layout")
    T.isnil(stub.popup, "no reload asked")
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

T.test("installer: when the layout can't be placed, Finish says why and changes nothing", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    EditModeManagerFrame:Show()                        -- Edit Mode open: the game won't take a layout
    press(DUI.Installer.pages.finish.finish)
    T.truthy(string.find(DUI.Installer.pages.finish.status:GetText() or "", "Edit Mode is open", 1, true), "says why")
    T.isnil(DUI.Installer.State(), "not set up")
    T.eq(#saved.layouts, 0)
    EditModeManagerFrame:Hide()
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Installer.State(), "installed", "tried again")
end)

T.test("installer: with controller mode on, Finish explains and writes nothing", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    Enum.InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
    local first = EditModePresetLayoutManager.presetLayoutInfo[1]
    first.interfaceStyle = 1
    press(DUI.Installer.pages.finish.finish)
    first.interfaceStyle = nil
    T.truthy(string.find(DUI.Installer.pages.finish.status:GetText() or "", "Controller mode", 1, true), "says why")
    T.eq(#saved.layouts, 0)
    T.isnil(DUI.Installer.State())
end)

T.test("installer: in combat the guide steps aside, and Finish waits for the end of it", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    stub.EnterCombat()
    T.falsy(DaylightUIInstaller:IsShown(), "out of the way")
    T.truthy(DUI.Installer.flow, "not closed")
    DUI.Installer.Finish()
    T.isnil(DUI.Installer.State(), "waits")
    stub.LeaveCombat()
    T.eq(DUI.Installer.State(), "installed", "finished after combat")
    T.truthy(DaylightUIInstaller:IsShown(), "back")
    T.eq(DUI.Installer.flow.page, "finish")
end)

T.test("installer: reload prompts wait while the guide is open", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.popup = nil
    DUI.EditMode.AskReload("something changed")
    T.isnil(stub.popup, "held")
    closeGuide()
    T.eq(stub.popup, "DAYLIGHTUI_RELOAD", "shown once the guide closes")
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

-- The game draws a text stretched over a row of no height as nothing, so
-- every row a page stacks gets the height it asks for.
T.test("installer: the welcome's rows have the height they ask for", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local page = DUI.Installer.pages.welcome
    T.eq(page.greeting:GetParent():GetHeight(), 26, "the greeting's row")
    T.eq(page.cards.quick:GetParent():GetHeight(), 178, "the cards' row")
end)

T.test("installer tour: Look previews live, and closing puts it back", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("look")
    local accent = DUI.Installer.pages.look.pickers["general.accent"]
    press(accent.cards.class)
    T.eq(DUI:Get("general", "accent"), "class", "shown straight away")
    T.truthy(accent.cards.class.selected)
    closeGuide()
    T.eq(DUI:Get("general", "accent"), "classGradient", "put back")
end)

-- Typing into an edit box, as the player does.
local function typeIn(box, text)
    box:SetText(text)
    box:GetScript("OnTextChanged")(box, true)
end

-- (The profile in use left as it was when the picks go elsewhere: the
-- "installer draft: Commit moves the picks" test.)
T.test("installer tour: Look's picks are saved as the character's own profile; DPS/Tank left as it was", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local font = DUI:Get("general", "font")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("look")
    local page = DUI.Installer.pages.look
    press(page.pickers["general.font"].cards.poppins)
    local heavy = DUI:Get("general", "heavyBorder")
    page.rows["general.heavyBorder"].control:Click()
    T.eq(DUI:Get("general", "heavyBorder"), not heavy, "the switch flipped")
    DUI.Installer.Go("finish")
    local finish = DUI.Installer.pages.finish
    local said = false
    for _, l in ipairs(finish.lines) do
        if l:IsShown() and string.find(lineText(l), "Poppins", 1, true) then said = true end
    end
    T.truthy(said, "the summary names the pick")
    T.truthy(finish.saveAs:IsShown(), "a name to save it as")
    T.eq(finish.saveAs:GetText(), "Tester", "the character's name to start")
    T.truthy(string.find(finish.shared:GetText() or "", "new profile", 1, true), "says it's a new one")
    press(finish.finish)
    local pd = DaylightUIDB.profileData
    T.eq(pd.Tester.general.font, "poppins")
    T.eq(pd.Tester.general.heavyBorder, not heavy)
    T.eq(DUI.Profiles.Chosen("character"), "Tester", "the character on it")
    T.truthy(layoutNamed("DaylightUI - Tester"), "with a layout of its own")
    T.eq(pd["DPS/Tank"].general.font, font, "DPS/Tank as it was")
    T.eq(pd["DPS/Tank"].general.heavyBorder, heavy)
end)

T.test("installer tour: typing a profile's name saves into it, and says when other characters share it", function()
    local DUI = login()
    DUI.DB.Root().characters["Alt-Realm"] = { profile = "DPS/Tank" }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("look")
    press(DUI.Installer.pages.look.pickers["general.font"].cards.poppins)
    DUI.Installer.Go("finish")
    local finish = DUI.Installer.pages.finish
    typeIn(finish.saveAs, "dps/tank")
    T.truthy(string.find(finish.shared:GetText() or "", "shared with Alt", 1, true), "warned")
    press(finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "DPS/Tank", "on the one named, whatever the case")
    T.eq(DaylightUIDB.profileData["DPS/Tank"].general.font, "poppins", "the pick in it")
    T.isnil(DaylightUIDB.profileData.Tester, "no profile of its own")
end)

T.test("installer tour: a new name makes that profile; an empty one stops Finish", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("finish")
    local finish = DUI.Installer.pages.finish
    typeIn(finish.saveAs, "  ")
    press(finish.finish)
    T.falsy(DUI.Installer.flow.finished, "not finished")
    T.truthy(string.find(finish.status:GetText() or "", "name", 1, true), "says why")
    typeIn(finish.saveAs, "Raid Night")
    press(finish.finish)
    T.truthy(DUI.Installer.flow.finished)
    T.eq(DUI.Profiles.Chosen("character"), "Raid Night")
    T.isnil(DaylightUIDB.profileData.Tester)
end)

T.test("installer tour: the frames page shows your frame and a target in the window, not on the screen", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("frames")
    T.falsy(DUI.testMode, "no sample frames on the screen")
    local spot = DUI.InstallerUI.Spots()[1]
    T.falsy(spot and spot:IsShown(), "no spotlight")
    local samples = DUI.Installer.pages.frames.samples
    T.truthy(samples, "samples in the window")
    local you, them = samples.frames.player, samples.frames.target
    T.truthy(you and them, "your frame and a target")
    T.eq(you:GetParent(), samples, "inside the window")
    T.falsy(you:IsMouseEnabled(), "only to look at")
    T.truthy(you.test and them.test, "filled with samples")
    T.eq(them.test.name, "Sadeas", "the test mode's target")
end)

T.test("installer tour: the frames page's samples stay pinned at the top while its options scroll", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("frames")
    local page = DUI.Installer.pages.frames
    local pin = page.pinned
    T.truthy(pin, "a pinned part")
    T.eq(page.samples:GetParent(), pin, "the samples in it")
    T.eq(pin:GetParent(), DaylightUIInstaller, "on the window, not in the scrolling page")
    T.truthy(pin:IsShown())
    local _, _, _, _, pinY = pin:GetPoint(1)
    local _, _, _, _, scrollY = DaylightUIInstaller.scroll:GetPoint(1)
    T.truthy(scrollY <= pinY - pin:GetHeight(), "the options scroll under it")
    DUI.Installer.Go("look")
    T.falsy(pin:IsShown(), "gone on another page")
    local _, _, _, _, lookY = DaylightUIInstaller.scroll:GetPoint(1)
    T.eq(lookY, pinY, "the scrolling part back up top")
end)

T.test("installer tour: the window's samples show each pick on the frames page", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("frames")
    local page = DUI.Installer.pages.frames
    local you, them = page.samples.frames.player, page.samples.frames.target
    press(page.pickers.portraits.cards["3d"])
    T.eq(DUI:Get("UnitFrames", "player.portrait"), "3d", "one portrait choice sets every frame")
    T.eq(DUI:Get("UnitFrames", "target.portrait"), "3d")
    T.eq(you.portraitMode, "3d", "the sample shows it")
    T.truthy(you.portrait:IsShown())
    press(page.pickers.portraits.cards.none)
    T.falsy(you.portrait:IsShown(), "no portrait: the ring goes")
    T.falsy(them.portrait:IsShown())
    press(page.pickers["UnitFrames.colors.health"].cards.class)
    local red = them.health.__barColor
    press(page.pickers["UnitFrames.colors.health"].cards.gradient)
    local now = them.health.__barColor
    T.truthy(red and now and (red[1] ~= now[1] or red[2] ~= now[2] or red[3] ~= now[3]), "the health color repainted")
end)

-- Seen in game: the player had its own "Daylight" saved, so
-- picking Ribbon here changed the target but not the player.
T.test("installer tour: the Frame style cards restyle every frame, a frame's own pick too, and closing puts it back", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    DUI:Set("UnitFrames", "player.style", "daylight")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("frames")
    local page = DUI.Installer.pages.frames
    press(page.pickers["UnitFrames.look.style"].cards.ribbon)
    stub.RunTimers()
    T.eq(DUI:Get("UnitFrames", "player.style"), "global", "the player follows the pick")
    T.truthy(page.samples.frames.player.ribbon, "the player sample wears Ribbon")
    T.truthy(page.samples.frames.target.ribbon, "the target sample too")
    T.truthy(page.pickers["UnitFrames.look.style"].cards.ribbon.selected, "the Ribbon card picked")
    closeGuide()
    T.eq(DUI:Get("UnitFrames", "player.style"), "daylight", "its own pick put back")
    T.eq(DUI:Get("UnitFrames", "look.style"), "daylight")
end)

T.test("installer tour: closing on the frames page puts every preview back and leaves nothing on the screen", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("frames")
    local before = DUI:Get("UnitFrames", "player.portrait")
    press(DUI.Installer.pages.frames.pickers.portraits.cards["3d"])
    closeGuide()
    T.falsy(DUI.testMode, "samples off")
    T.eq(DUI:Get("UnitFrames", "player.portrait"), before, "put back")
    local spot = DUI.InstallerUI.Spots()[1]
    T.falsy(spot and spot:IsShown(), "no spotlight left behind")
end)

-- With the quest tracker loaded, Quick setup asks one question between
-- the setup's button and Finish: the quest helper or not. Yes picks
-- its settings through the draft into the setup's profile (the arrow only
-- with QuestieDB on); no, or closing the guide, puts them back.
T.test("installer: Quick setup asks about the quest helper before Finish; yes goes into the setup's profile", function()
    local DUI = login({ quests = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.eq(DUI:Get("Quests", "nav.arrow"), false, "off by default")
    press(DUI.Installer.pages.welcome.cards.quick.healer)
    T.eq(DUI.Installer.flow.page, "questhelp")
    local ids = {}
    for _, s in ipairs(DUI.Installer.Steps()) do ids[#ids + 1] = s.id end
    T.eq(table.concat(ids, ","), "welcome,questhelp,finish", "only the quick pages")
    local page = DUI.Installer.pages.questhelp
    T.truthy(page.picker.cards.no.selected, "no until asked")
    T.truthy(page.hint and page.hint:IsShown(), "says QuestieDB is needed")
    press(page.picker.cards.yes)
    T.truthy(page.picker.cards.yes.selected)
    for _, s in ipairs(DUI.InstallerPages.Get("questhelp").bundle.set) do
        if not s.addon then T.eq(DUI:Get(s[1], s[2]), s[3], "previewed: " .. s[2]) end
    end
    T.eq(DUI:Get("Quests", "nav.arrow"), false, "no arrow without QuestieDB")
    DUI.Installer.Next()
    T.eq(DUI.Installer.flow.page, "finish")
    local said = false
    for _, l in ipairs(DUI.Installer.pages.finish.lines) do
        if l:IsShown() and string.find(string.lower(lineText(l)), "the quest helper", 1, true) then said = true end
    end
    T.truthy(said, "the summary says so")
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "Healer")
    local q = DaylightUIDB.profileData.Healer.modules.Quests
    T.eq(q.nav.marker, true, "in the Healer profile")
    T.falsy(q.nav.arrow, "the arrow left out")
end)

T.test("installer: with QuestieDB on, the quest helper's yes takes the arrow too", function()
    local DUI = login({ quests = true })
    stub.loadedAddOns.QuestieDB = true
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    local page = DUI.Installer.pages.questhelp
    T.falsy(page.hint, "nothing missing to say")
    press(page.picker.cards.yes)
    T.eq(DUI:Get("Quests", "nav.arrow"), true)
end)

T.test("installer: the quest helper's no, or closing the guide, puts its settings back", function()
    local DUI = login({ quests = true })
    stub.loadedAddOns.QuestieDB = true
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local arrow = DUI:Get("Quests", "nav.arrow")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    local page = DUI.Installer.pages.questhelp
    press(page.picker.cards.yes)
    T.eq(DUI:Get("Quests", "nav.arrow"), true)
    press(page.picker.cards.no)
    T.eq(DUI:Get("Quests", "nav.arrow"), arrow, "no: back")
    T.falsy(DUI.InstallerDraft.Picked("Quests", "nav.arrow"))
    press(page.picker.cards.yes)
    closeGuide()
    T.eq(DUI:Get("Quests", "nav.arrow"), arrow, "closed: back")
end)

T.test("installer: without the quest tracker, Quick setup goes straight to Finish", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    T.eq(DUI.Installer.flow.page, "finish")
    T.falsy(DUI.InstallerDraft.Active(), "no draft to keep")
end)

T.test("installer tour: Questing comes after Everyday when the quest tracker is loaded", function()
    local DUI = login({ quests = true, bags = true })
    local ids = {}
    for _, def in ipairs(DUI.InstallerPages.Tour()) do ids[#ids + 1] = def.id end
    T.eq(table.concat(ids, ","), "modules,role,look,bars,calm,everyday,questing")
end)

T.test("installer tour: pages for modules that aren't loaded are left out", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    T.truthy(DUI.Installer.HasStep("look"), "the core's own look")
    T.falsy(DUI.Installer.HasStep("frames"), "no unit frames loaded")
    T.falsy(DUI.Installer.HasStep("everyday"))
    T.falsy(DUI.Installer.HasStep("qol"))
end)

T.test("installer tour: Everyday shows the bag view as pictures; quality of life says what each helper does", function()
    local DUI = login({ bags = true, qol = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("everyday")
    press(DUI.Installer.pages.everyday.pickers["Bags.view"].cards.grid)
    T.eq(DUI:Get("Bags", "view"), "grid")
    DUI.Installer.Go("qol")
    local _, item = DUI.InstallerPages.Find("QoL", "fastLoot")
    T.truthy(DUI.Installer.pages.qol.rows["QoL.fastLoot"], "a row")
    T.eq(DUI.Installer.pages.qol.notes["QoL.fastLoot"]:GetText(), item.desc, "its help printed under it")
end)

T.test("installer tour: What's included lists every module; a switch applies to this character only, at Finish", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_ActionBars = true, DaylightUI_Bags = true }
    stub.loadedAddOns = { DaylightUI_ActionBars = true, DaylightUI_Bags = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    T.eq(DUI.Installer.flow.page, "modules", "the tour starts here")
    local page = DUI.Installer.pages.modules
    T.eq(T.count(page.tiles), #DUI.InstallerPages.MODULES, "every module")
    T.truthy(page.tiles.DaylightUI_Bags.row, "installed: a switch")
    T.isnil(page.tiles.DaylightUI_Chat.row, "not installed: none")
    page.tiles.DaylightUI_Bags.row.control:Click()
    T.eq(DUI.Installer.flow.modules.DaylightUI_Bags, false)
    T.isnil(stub.addonState.DaylightUI_Bags, "nothing until Finish")
    DUI.Installer.Go("finish")
    press(DUI.Installer.pages.finish.finish)
    T.eq(stub.addonState.DaylightUI_Bags[UnitGUID("player")], false, "off for this character only")
    T.isnil(stub.addonState.DaylightUI_ActionBars, "the rest left alone")
    stub.RunTimers()
    T.truthy(DUI.InstallerUI.ReloadButton():IsShown(), "a reload to apply it")
end)

T.test("installer tour: a clash starts on ours; keeping theirs switches ours off and leaves theirs on", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.loadedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    local clash = DUI.Installer.pages.modules.clashes.Baganator
    T.truthy(clash, "Baganator named")
    T.truthy(clash.ours.active, "ours first")
    press(clash.theirs)
    T.eq(DUI.Installer.flow.modules.DaylightUI_Bags, false, "our bags off with it")
    DUI.Installer.Go("finish")
    press(DUI.Installer.pages.finish.finish)
    T.eq(stub.addonState.DaylightUI_Bags[UnitGUID("player")], false, "ours off")
    T.isnil(stub.addonState.Baganator, "theirs left on")
end)

T.test("installer: Quick setup turns a clashing addon off, and says so first", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.loadedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    local said = false
    for _, l in ipairs(DUI.Installer.pages.finish.lines) do
        if l:IsShown() and string.find(lineText(l), "Baganator", 1, true) then said = true end
    end
    T.truthy(said, "the summary names it")
    press(DUI.Installer.pages.finish.finish)
    T.eq(stub.addonState.Baganator[UnitGUID("player")], false)
end)

T.test("installer tour: the role page recommends from the game's role; a pick shows that profile's look", function()
    local DUI = login({ before = function()
        _G.GetSpecialization = function() return 1 end
        _G.GetSpecializationRole = function() return "HEALER" end
    end })
    DUI.Profiles.AddPreset("Healer")
    DaylightUIDB.profileData.Healer.general.accent = "class"
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    T.eq(DUI.Installer.flow.roles.character, "Healer", "the recommended role picked first")
    T.eq(DUI:Get("general", "accent"), "class", "Healer's look shown")
    DUI.Installer.Go("role")
    local picker = DUI.Installer.pages.role.pickers.character
    T.eq(picker.cards.Healer.tag.text:GetText(), "Recommended for you")
    press(picker.cards["DPS/Tank"])
    T.eq(DUI.Installer.flow.roles.character, "DPS/Tank")
    T.eq(DUI:Get("general", "accent"), "classGradient", "back to the look in use")
    closeGuide()
    T.eq(DUI:Get("general", "accent"), "classGradient")
end)

T.test("installer tour: with dual spec, each talent set gets its own pick", function()
    local DUI = login({ specGroups = 2 })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("role")
    local pickers = DUI.Installer.pages.role.pickers
    T.truthy(pickers[1] and pickers[2], "a row per talent set")
    press(pickers[2].cards.Healer)
    DUI.Installer.Go("finish")
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen(1), "Tester", "the set in use: saved as named")
    T.eq(DUI.Profiles.Chosen(2), "Healer")
end)

T.test("installer tour: with dual spec, both sets on the same layout share the named profile", function()
    local DUI = login({ specGroups = 2 })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("finish")
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen(1), "Tester")
    T.eq(DUI.Profiles.Chosen(2), "Tester")
end)

T.test("installer tour: a set-up character's own profile is a card, picked and in use", function()
    local DUI = login()
    local made = DUI.Profiles.Create("Mine", nil, DUI.DB.DEFAULT)
    DUI.Installer.Install(DUI.Installer.EXISTING, made)
    stub.RunTimers()
    DaylightUIDB.installerSeen = nil
    DUI = reload()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    T.eq(DUI.Installer.flow.mode, "showcase")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("role")
    local picker = DUI.Installer.pages.role.pickers.character
    T.truthy(picker.cards.Mine, "its own card")
    T.truthy(picker.cards.Mine.selected, "picked")
    T.eq(picker.cards.Mine.tag.text:GetText(), "In use")
    T.eq(picker.cards.Mine.label:GetText(), "Keep Mine")
    DUI.Installer.Go("finish")
    T.eq(DUI.Installer.pages.finish.saveAs:GetText(), "Mine", "saved back into it")
end)

T.test("installer: Quick setup has no name to save as", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    T.falsy(DUI.Installer.pages.finish.saveAs:IsShown())
end)

T.test("installer tour: with every module loaded, every page appears", function()
    local DUI = login({ module = true, bags = true, chat = true, infopanel = true, tooltip = true, qol = true })
    local ids = {}
    for _, def in ipairs(DUI.InstallerPages.Tour()) do ids[#ids + 1] = def.id end
    T.eq(table.concat(ids, ","), "modules,role,look,frames,bars,calm,everyday,questing,qol")
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

T.test("installer tour: switching a module's tile off leaves its clashing addon on", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.loadedAddOns = { DaylightUI_Bags = true, Baganator = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    local page = DUI.Installer.pages.modules
    page.tiles.DaylightUI_Bags.row.control:Click()
    T.truthy(page.clashes.Baganator.theirs.active, "the card follows the tile")
    DUI.Installer.Go("finish")
    press(DUI.Installer.pages.finish.finish)
    T.eq(stub.addonState.DaylightUI_Bags[UnitGUID("player")], false, "ours off")
    T.isnil(stub.addonState.Baganator, "theirs left on: some bags stay")
end)

T.test("installer tour: a module with two clashing addons answers both together", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_InfoPanel = true, EllesmereUIMinimap = true, EllesmereUIDamageMeters = true }
    stub.loadedAddOns = { DaylightUI_InfoPanel = true, EllesmereUIMinimap = true, EllesmereUIDamageMeters = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    local clashes = DUI.Installer.pages.modules.clashes
    press(clashes.EllesmereUIMinimap.theirs)
    T.truthy(clashes.EllesmereUIDamageMeters.theirs.active, "the other card follows")
    DUI.Installer.Go("finish")
    press(DUI.Installer.pages.finish.finish)
    T.eq(stub.addonState.DaylightUI_InfoPanel[UnitGUID("player")], false, "ours off")
    T.isnil(stub.addonState.EllesmereUIDamageMeters, "their damage meter left on")
    press(clashes.EllesmereUIDamageMeters.ours)
    T.truthy(clashes.EllesmereUIMinimap.ours.active, "and back together")
end)

T.test("installer: Quick setup leaves a clashing addon alone when our module isn't installed", function()
    local DUI = login()
    stub.installedAddOns = { Baganator = true }
    stub.loadedAddOns = { Baganator = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    press(DUI.Installer.pages.finish.finish)
    T.isnil(stub.addonState.Baganator, "nothing to replace it with")
end)

T.test("installer: closing during the Finish checklist leaves no Reload button on screen", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_Bags = true }
    stub.loadedAddOns = { DaylightUI_Bags = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    press(DUI.Installer.pages.finish.finish)
    closeGuide()
    stub.RunTimers()
    T.falsy(DaylightUIInstaller:IsShown(), "closed")
    local b = DUI.InstallerUI.ReloadButton()
    T.truthy(b == nil or not b:IsShown(), "no button left floating")
end)

T.test("installer tour: the Custom accent swatch and the bar strips repaint on a pick", function()
    local DUI = login()
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("look")
    local page = DUI.Installer.pages.look
    local swatch = page.pickers["general.accent"].cards.custom.swatch
    -- What the color picker's callback does with the player's color.
    DUI.InstallerDraft.Set("general", "accentColor", { 0.1, 0.2, 0.3 })
    local r, g, b = swatch:GetVertexColor()
    T.near(r, 0.1); T.near(g, 0.2); T.near(b, 0.3)
    DUI.InstallerDraft.Set("general", "accent", "custom")
    local tex = page.pickers["general.barTexture"]
    for _, c in pairs(tex.cards) do
        local sr, sg, sb = c.strip:GetVertexColor()
        T.near(sr, 0.1, nil, c.key); T.near(sg, 0.2); T.near(sb, 0.3)
    end
    closeGuide()
end)

T.test("installer tour: the health cards follow a bar texture picked after they were drawn", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("frames")
    local health = DUI.Installer.pages.frames.pickers["UnitFrames.colors.health"]
    DUI.Style.BarFile = function() return "Interface\\other-bar" end
    DUI.Installer.Go("look")
    DUI.Installer.Go("frames")
    T.eq(health.cards.class.bar.fill:GetTexture(), "Interface\\other-bar", "redrawn on show")
    closeGuide()
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
        press(DUI.Installer.pages.welcome.cards.tour)
        for _, s in ipairs(DUI.Installer.Steps()) do DUI.Installer.Go(s.id) end
        closeGuide()
    end
    tour()
    local first, look = n, DUI.Installer.pages.look
    T.truthy(first > 0, "the tour's pages listen")
    tour()
    tour()
    DUI.On = on
    T.eq(n, first, "none added by running it again")
    T.eq(DUI.Installer.pages.look, look, "the same page reused")
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

T.test("installer: a checklist cut short by closing doesn't tick on in the next run", function()
    local DUI = login()
    stub.installedAddOns = { DaylightUI_Bags = true }
    stub.loadedAddOns = { DaylightUI_Bags = true }
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    press(DUI.Installer.pages.finish.finish)
    closeGuide()
    DUI.Installer.Show()
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    local finish = DUI.Installer.pages.finish
    stub.RunTimers()
    T.truthy(finish.finish:IsShown(), "Finish to press again")
    for _, c in ipairs(finish.checks) do T.falsy(c:IsShown(), "no line ticked") end
    T.isnil(finish.ended)
end)

T.test("installer tour: the ring color is one choice for every frame, each card a ring in that color", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("frames")
    local page = DUI.Installer.pages.frames
    local picker = page.pickers.portraitRing
    T.truthy(picker, "a Ring color choice")
    local light, dark, class = picker.cards.light, picker.cards.dark, picker.cards.class
    T.truthy(class.selected, "the class gradient to start with")
    T.isnil(light.portraitArt.band.__gradient, "a gray ring")
    T.eq(dark.portraitArt.band.__gradient[1], "VERTICAL", "the dark ring lit at the top")
    T.truthy(class.portraitArt.band.__gradient, "a class gradient ring")
    local accentBand = picker.cards.accent.portraitArt.band
    DUI:Set("general", "accent", "gradient")
    picker.cards.accent.redraw()
    T.truthy(accentBand.__gradient, "a gradient accent's ring")
    DUI:Set("general", "accent", "custom")
    DUI:Set("general", "accentColor", { 0.2, 0.7, 0.4 })
    picker.cards.accent.redraw()
    T.rgb(accentBand.__vertex, { 0.2, 0.7, 0.4 }, "a one-color accent's ring")
    T.isnil(accentBand.__gradient, "its gradient cleared")
    T.truthy(picker.cards.daylight.portraitArt.band.__gradient, "a Daylight gradient ring")
    press(light)
    for _, u in ipairs({ "player", "target", "focus" }) do
        T.eq(DUI:Get("UnitFrames", u .. ".portraitRing"), "light", u)
    end
    T.isnil(page.samples.frames.player.portrait.ring.__gradient, "the sample shows it")
    closeGuide()
    T.eq(DUI:Get("UnitFrames", "player.portraitRing"), "class", "put back on close")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
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
    local card = DUI.Installer.pages.welcome.packs.TestPack
    T.truthy(card, "a card for the pack")
    T.truthy(card.buttons["Test UI"] and card.buttons["Test UI Healer"], "a button per profile")
    local b = card.buttons["Test UI"]
    T.noerror(function() b:GetScript("OnEnter")(b); b:GetScript("OnLeave")(b) end, "its hover text")
    press(b)
    T.eq(DUI.Installer.flow.page, "finish")
    T.truthy(string.find(DUI.Installer.Summary()[1].text, "Test UI", 1, true), "named as the pack names it")
    press(DUI.Installer.pages.finish.finish)
    T.eq(DUI.Profiles.Chosen("character"), "Test UI")
    T.eq(DaylightUIDB.profileData["Test UI"].general.borderPx, 3, "the pack's settings")
    T.truthy(layoutNamed("DaylightUI - Test UI"), "its own layout")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("installer tour: a pack's profiles are role cards, credited, drawn by their role; picked, the character's own profile starts from it", function()
    local DUI = login()
    DUI.RegisterPack("TestPack", { label = "Test UI", author = "Someone",
        profiles = { { name = "Test UI Healer", data = { general = { borderPx = 3 } }, role = "Healer" } } })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    local I = DUI.Installer
    I.Start("tour")
    I.Go("role")
    local picker = I.pages.role.pickers.character
    local c = picker.cards["Test UI Healer"]
    T.truthy(c, "a card")
    T.eq(I.RoleCardLabel("Test UI Healer"), "Test UI Healer", "its own name, not Keep ...")
    T.eq(I.RoleTag("Test UI Healer"), "by Someone")
    T.eq(I.RoleShape("Test UI Healer"), "Healer", "the drawing its role says")
    c:GetScript("OnClick")(c)
    T.eq(I.flow.roles.character, "Test UI Healer")
    I.Go("finish")
    local name = I.SaveAs()
    T.truthy(name and name ~= "Test UI Healer", "saved under the character's own name")
    press(I.pages.finish.finish)
    T.eq(DaylightUIDB.profileData[name].general.borderPx, 3, "made from the pack's profile")
    T.isnil(DaylightUIDB.profileData["Test UI Healer"], "the pack's own left unmade")
end)

T.test("installer: a pack's extras set up other addons at Finish, only loaded ones, each with its switch", function()
    for _, keep in ipairs({ true, false }) do
        local DUI = login()
        stub.loadedAddOns.Details = true
        local ran = 0
        DUI.RegisterPack("X", { label = "X UI", profiles = { { name = "X UI", data = {} } },
            extras = { { addon = "Details", label = "Details!", apply = function() ran = ran + 1 end },
                       { addon = "BigWigs", apply = function() error("not loaded: never run") end } } })
        stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
        press(DUI.Installer.pages.welcome.packs.X.buttons["X UI"])
        local fin = DUI.Installer.pages.finish
        T.eq(#DUI.Installer.Extras(), 1, "only the loaded one")
        local r = fin.extras[1]
        T.truthy(r:IsShown())
        T.truthy(string.find(stub.Text(r.text), "Details!", 1, true), "says which addon")
        T.truthy(string.find(stub.Text(r.text), "X UI", 1, true), "and whose setup")
        T.truthy(r.switch.on, "on to start with")
        if not keep then
            press(r.switch)
            T.falsy(r.switch.on, "switched off")
        end
        press(fin.finish)
        T.eq(ran, keep and 1 or 0, keep and "run" or "left alone")
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
end)

T.test("installer tour: with Questie on, the modules page asks which quest tracker", function()
    local profile = { trackerEnabled = true }
    local DUI = login({ quests = true, before = function()
        stub.installedAddOns.Questie, stub.loadedAddOns.Questie = true, true
        _G.Questie = { API = { isReady = true }, db = { profile = profile } }
    end })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    local card = DUI.Installer.pages.modules.clashes.Questie
    T.truthy(card, "Questie's card")
    T.truthy(card.ours.active, "ours first")
    press(card.theirs)
    T.eq(DUI:Get("Quests", "tracker"), false, "Questie's tracker picked")
    T.eq(DUI.DB.Root().questieAsked, true, "not asked again after the guide")
    T.truthy(card.theirs.active)
    _G.Questie = nil
end)

T.test("installer tour: without Questie no tracker question", function()
    local DUI = login({ quests = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    T.isnil(DUI.Installer.pages.modules.clashes.Questie)
end)

-- An account whose DPS/Tank was changed (here: raid tiles from the old
-- healer frames) and a character that has a profile of its own name already.
local function changedStandard(DUI)
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.quick.dps)
    press(DUI.Installer.pages.finish.finish)
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
    I.Go("role")
    local c = I.pages.role.pickers.character.cards[key]
    c:GetScript("OnClick")(c)
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
    I.Go("finish")
    local name = I.SaveAs()
    press(I.pages.finish.finish)
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
    I.Go("finish")
    local name = I.SaveAs()
    press(I.pages.finish.finish)
    closeGuide()
    T.eq(raidOf(name).width, 60, "made as Healer")
    -- Again, picking DPS / Tank this time, and one look pick on the way.
    I = tourPick(DUI, "DPS/Tank")
    DUI.InstallerDraft.Set("general", "accent", "daylight")
    I.Go("finish")
    T.eq(I.SaveAs(), name, "saved under the same name")
    T.truthy(string.find(I.SaveNote() or "", "DPS / Tank", 1, true), "the note says what it's rebuilt from")
    press(I.pages.finish.finish)
    T.isnil(raidOf(name).width, "rebuilt as DPS / Tank: no healer tiles")
    T.eq(DaylightUIDB.profileData[name].general.accent, "daylight", "with the pick made on the way")
    T.truthy(I.flow.reload, "reloads into it")
    closeGuide()
    -- Keep: as it is.
    DaylightUIDB.profileData[name].modules.UnitFrames.raid = { width = 50 }
    I = tourPick(DUI, name)
    I.Go("finish")
    press(I.pages.finish.finish)
    T.eq(raidOf(name).width, 50, "kept")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The things players see first (bars, plates, fading), as presets of a few
-- settings each.
T.test("installer summary: a Show X switch (invert) says on when you see it", function()
    local DUI = login({ module = true })
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.InstallerDraft.Set("ActionBars", "hideEmpty", false)
    DUI.Installer.Go("finish")
    local said = {}
    for _, l in ipairs(DUI.Installer.pages.finish.lines) do
        if l:IsShown() then said[#said + 1] = lineText(l) end
    end
    local all = table.concat(said, " | ")
    T.truthy(all:find("Show empty buttons (on)", 1, true), all)
    DUI.InstallerDraft.Revert()
end)

T.test("installer calm page: a preset shows picked with the Unit Frames off", function()
    local DUI = login({})
    T.falsy(DUI.InstallerPages.Loaded("UnitFrames"), "no unit frames here")
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("calm")
    press(DUI.Installer.pages.calm.pickers["Out of a fight"].cards.calm)
    T.eq(DUI:Get("ActionBars", "bars.main.fade.mode"), "ooc")
    local group
    for _, def in ipairs(DUI.InstallerPages.Tour()) do
        if def.id == "calm" then
            for _, g in ipairs(def.groups) do if g.presets then group = g end end
        end
    end
    local p = DUI.InstallerPages.PresetOn(group)
    T.eq(p and p.id, "calm", "the Calm card is the picked one")
    DUI.InstallerDraft.Revert()
end)

T.test("installer tour: the bars, plates and calm pages pick their presets through the draft", function()
    local DUI = login({ nameplates = true, module = true })
    local ids = {}
    for _, def in ipairs(DUI.InstallerPages.Tour()) do ids[#ids + 1] = def.id end
    T.truthy(table.concat(ids, ","):find("bars,plates,calm", 1, true), table.concat(ids, ","))
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    press(DUI.Installer.pages.welcome.cards.tour)
    DUI.Installer.Go("bars")
    local bars = DUI.Installer.pages.bars.pickers["Bars on screen"]
    press(bars.cards.one)
    T.eq(DUI:Get("ActionBars", "bars.bar2.visible"), "hidden", "one row: bar 2 hidden")
    T.eq(DUI:Get("ActionBars", "bars.left.visible"), "hidden")
    DUI.Installer.Go("plates")
    press(DUI.Installer.pages.plates.pickers.Size.cards.large)
    T.eq(DUI:Get("Nameplates", "scale"), 1.2); T.eq(DUI:Get("Nameplates", "height"), 20)
    DUI.Installer.Go("calm")
    press(DUI.Installer.pages.calm.pickers["Out of a fight"].cards.float)
    T.eq(DUI:Get("UnitFrames", "player.fade.mode"), "float")
    T.eq(DUI:Get("ActionBars", "bars.main.fade.mode"), "float")
    DUI.Installer.Go("finish")
    local said = {}
    for _, l in ipairs(DUI.Installer.pages.finish.lines) do
        if l:IsShown() then said[#said + 1] = lineText(l) end
    end
    local all = table.concat(said, " | ")
    T.truthy(all:find("One row", 1, true), "the summary names the preset: " .. all)
    T.truthy(all:find("Large", 1, true), all)
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
