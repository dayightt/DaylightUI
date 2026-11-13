local stub = require("stub")

local DEFAULTS = { size = 10, on = true, mode = "a", nested = { w = 5 } }

local function errorsFor(DUI, items) return DUI.Options.Validate(items, DEFAULTS) end

T.test("a valid table has no errors", function()
    local DUI = stub.Load()
    local errs = errorsFor(DUI, {
        { type = "toggle", key = "on", label = "On", desc = "Turns it on." },
        { type = "slider", key = "size", label = "Size", min = 1, max = 20, step = 1, unit = "px" },
        { type = "slider", key = "nested.w", label = "W", min = 0, max = 9, disabled = function() return false end },
        { type = "dropdown", key = "mode", label = "Mode", values = { a = "A", b = "B" } },
        { type = "button", label = "Go", text = function() return "Go" end, func = function() end, confirm = true },
        { type = "text", label = function() return "words" end },
    })
    T.eq(#errs, 0, table.concat(errs, "; "))
end)

T.test("problems are reported with their location", function()
    local DUI = stub.Load()
    local errs = errorsFor(DUI, {
        { type = "wat" },
        { type = "toggle", key = "on" },
        { type = "toggle", label = "No key" },
        { type = "toggle", key = "missing", label = "M" },
        { type = "toggle", key = "size", label = "Wrong type" },
        { type = "slider", key = "size", label = "Range", min = 11, max = 20 },
        { type = "slider", key = "size", label = "Step", min = 1, max = 20, step = 0 },
        { type = "slider", key = "size", label = "Unit", min = 1, max = 20, unit = "cm" },
        { type = "dropdown", key = "mode", label = "D", values = { b = "B" } },
        { type = "button", label = "B" },
        { type = "toggle", key = "on", label = "X", disabled = true },
        { type = "toggle", key = "on", label = function() end },
    })
    T.eq(#errs, 12, table.concat(errs, "; "))
    T.truthy(string.find(errs[1], "options[1]", 1, true))
    T.truthy(string.find(errs[7], "bad step", 1, true))
    T.truthy(string.find(errs[8], "unknown unit", 1, true))
end)

T.test("the core's pages are registered first, valid and in order (the character, NPC, book and inspect windows are part of the core)", function()
    local DUI = stub.Load()
    local ids = {}
    for id, page in DUI.Options.Pages() do
        ids[#ids + 1] = id
        T.eq(#DUI.Options.ValidatePage(page), 0, id)
    end
    T.eq(table.concat(ids, ","), "home,appearance,fade,damage,combattext,gradients,layout,profiles,donators,Character.window,NPC.window,windows,patchnotes")
    T.eq(DUI.Options.Sections()[1].label, "General")
    T.falsy(stub.ChatContains("Options ("))
end)

T.test("our windows and the skins are pages under Extras, not sections of their own", function()
    local DUI = stub.Load{ skins = true, qol = true }
    local ids, sections = {}, {}
    for _, s in ipairs(DUI.Options.Sections()) do
        sections[#sections + 1] = s.id
        if s.id == "QoL" then for _, p in ipairs(s.pages) do ids[#ids + 1] = p.id end end
    end
    T.eq(table.concat(ids, ","), "QoL.qol,QoL.loot,Character.window,NPC.window,windows,Skins.skins")
    for _, id in ipairs(sections) do
        T.truthy(id ~= "Skins" and id ~= "Character" and id ~= "NPC" and id ~= "Book" and id ~= "Inspect", id)
    end
    T.eq(DUI.Options.GetPage("Skins.skins").scope, "Skins", "settings stay the module's")
end)

T.test("the smaller windows share one More windows page, a card each, every row its own window's setting", function()
    local DUI = stub.Load()
    local O, page = DUI.Options, DUI.Options.GetPage("windows")
    local cards = {}
    for _, g in ipairs(page.groups) do cards[#cards + 1] = g.label end
    T.eq(table.concat(cards, ","), "Spellbook & talents,Inspect,Professions,Group Finder,Mailbox,Social,Legacy")
    local function row(card, label)
        for _, g in ipairs(page.groups) do
            if g.label == card then
                for _, item in ipairs(g.items) do if item.label == label then return item end end
            end
        end
    end
    local scale = row("Mailbox", "Window scale")
    O.Set(page, scale, 1.2)
    T.eq(DUI:Get("Mailbox", "scale"), 1.2, "writes the mailbox's own")
    T.eq(DUI:Get("Social", "scale"), 1, "and no other window's")
    T.falsy(O.IsDefault(page, scale))
    O.ResetItem(page, scale)
    T.eq(DUI:Get("Mailbox", "scale"), 1, "reset to its default")
    T.truthy(row("Spellbook & talents", "Show lower spell ranks"), "a window's own extras come along")
    T.eq(#O.ValidatePage(page), 0)
end)

T.test("a module gets its own section of pages after the core's", function()
    local DUI = stub.Load()
    DUI:RegisterModule("Demo", { label = "Demo Things", defaults = DEFAULTS, options = { pages = {
        { id = "main", label = "Main", groups = { { label = "Card", items = { { type = "toggle", key = "on", label = "On" } } } } },
        { id = "more", label = "More", groups = { { label = "Card", items = { { type = "slider", key = "size", label = "S", min = 1, max = 20 } } } } },
    } } })
    local ids = {}
    for id in DUI.Options.Pages() do ids[#ids + 1] = id end
    T.eq(table.concat(ids, ","), "home,appearance,fade,damage,combattext,gradients,layout,profiles,donators,Demo.main,Demo.more,Character.window,NPC.window,windows,patchnotes")
    local s = DUI.Options.Sections()[2]
    T.eq(s.label, "Demo Things")
    T.eq(DUI.Options.GetPage("Demo.more").scope, "Demo")
    T.falsy(stub.ChatContains("Options ("))
end)

T.test("a hidden page isn't listed or opened, and comes back when it applies again", function()
    local DUI = stub.Load()
    DUI:RegisterModule("Demo", { label = "Demo", defaults = DEFAULTS, options = { pages = {
        { id = "main", label = "Main", groups = { { label = "Card", items = { { type = "toggle", key = "on", label = "On" } } } } },
        { id = "more", label = "More", hidden = function(get) return get("on") == true end,
          groups = { { label = "Card", items = { { type = "slider", key = "size", label = "S", min = 1, max = 20 } } } } },
    } } })
    local function listed()
        local ids = {}
        for id in DUI.Options.Pages() do ids[#ids + 1] = id end
        return table.concat(ids, ",")
    end
    DUI:Set("Demo", "on", false)
    T.truthy(listed():find("Demo.more", 1, true))
    DUI:Set("Demo", "on", true)
    T.falsy(listed():find("Demo.more", 1, true), "not listed")
    T.falsy(DUI.Options.GetPage("Demo.more"), "can't be opened")
    T.eq(DUI.Options.Sections()[2].label, "Demo", "the section keeps its fields")
    DUI:Set("Demo", "on", false)
    T.truthy(DUI.Options.GetPage("Demo.more"))
    T.falsy(stub.ChatContains("Options ("))
end)

T.test("a reload item asks (the core's own reload prompt) only when its value actually changes", function()
    local DUI = stub.Load()
    DUI:RegisterModule("Demo", { label = "Demo", defaults = DEFAULTS, options = { pages = {
        { id = "main", label = "Main", groups = { { label = "Card", items = {
            { type = "toggle", key = "on", label = "On", reload = true },
            { type = "toggle", key = "size", label = "Plain" },   -- no reload flag
        } } } },
    } } })
    local page = DUI.Options.GetPage("Demo.main")
    local reloadItem, plainItem = page.groups[1].items[1], page.groups[1].items[2]
    stub.popup = nil
    DUI.Options.Set(page, reloadItem, false)
    T.eq(stub.popup.which, "DAYLIGHTUI_RELOAD", "changed: asks to reload")
    stub.popup = nil
    DUI.Options.Set(page, reloadItem, false)
    T.isnil(stub.popup, "unchanged: no second ask")
    DUI.Options.Set(page, plainItem, false)
    T.isnil(stub.popup, "no reload flag: never asks")
end)

T.test("a restart item tells the player once, with only an Okay to click through", function()
    local DUI = stub.Load()
    DUI:RegisterModule("Demo", { label = "Demo", defaults = DEFAULTS, options = { pages = {
        { id = "main", label = "Main", groups = { { label = "Card", items = {
            { type = "toggle", key = "on", label = "On", restart = "Restart to see it." },
        } } } },
    } } })
    local page = DUI.Options.GetPage("Demo.main")
    local item = page.groups[1].items[1]
    stub.popup = nil
    DUI.Options.Set(page, item, false)
    T.eq(stub.popup and stub.popup.which, "DAYLIGHTUI_RESTART", "changed: says a restart is needed")
    T.eq(stub.popup.text, "Restart to see it.")
    local dialog = StaticPopupDialogs.DAYLIGHTUI_RESTART
    T.truthy(dialog.button1, "an Okay button")
    T.isnil(dialog.button2, "nothing else to click")
    T.falsy(dialog.hideOnEscape, "Escape doesn't skip it")
    stub.popup = nil
    DUI.Options.Set(page, item, false)
    T.isnil(stub.popup, "unchanged: no second notice")
end)

T.test("the damage numbers font says a restart is needed", function()
    local DUI = stub.Load()
    local page = DUI.Options.GetPage("damage")
    local item
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do if it.key == "damage.font" then item = it end end
    end
    T.truthy(item and item.restart, "the Font row")
    stub.popup = nil
    DUI.Options.Set(page, item, "bangers")
    T.eq(stub.popup and stub.popup.which, "DAYLIGHTUI_RESTART")
end)

T.test("an invalid module page is reported in chat", function()
    local DUI = stub.Load()
    DUI:RegisterModule("Bad", { defaults = {}, options = { pages = {
        { id = "p", label = "P", groups = { { label = "C", items = { { type = "toggle", key = "x", label = "X" } } } } },
    } } })
    T.truthy(stub.ChatContains("Options (Bad.p)"))
end)

T.test("every unit frames page is valid", function()
    local DUI = stub.Load({ module = true })
    local n = 0
    for id, page in DUI.Options.Pages() do
        T.eq(#DUI.Options.ValidatePage(page), 0, id)
        if page.section == "UnitFrames" then n = n + 1 end
    end
    T.eq(n, 17, "no Healer Frames page, no Target Auras page; Click-casting is one; Raid 10, 20 and 40; the Personal Display; PvP Frames; Focus Target")
    T.falsy(stub.ChatContains("Options ("))
end)

T.test("defaults, resets and dependencies", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.castbars")
    local items = page.groups[1].items
    local by = {}
    for _, item in ipairs(items) do by[item.key] = item end
    local attach, width = by["playerCastbar.at"], by["playerCastbar.width"]
    T.truthy(O.IsDefault(page, attach))
    T.truthy(O.IsDisabled(page, width), "width is off while attached")
    T.eq(attach.key, "playerCastbar.at")
    O.Set(page, attach, "free")
    T.falsy(O.IsDefault(page, attach))
    T.falsy(O.IsDisabled(page, width))
    O.ResetItem(page, attach)
    T.eq(DUI:Get("UnitFrames", "playerCastbar.at"), "below")
    O.Set(page, attach, "free")
    O.Set(page, width, 300)
    O.ResetPage(page)
    T.eq(DUI:Get("UnitFrames", "playerCastbar.at"), "below")
    T.eq(DUI:Get("UnitFrames", "playerCastbar.width"), 285)
end)

T.test("no Healer Frames page; the party and raid pages are never grayed out", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    T.isnil(O.GetPage("UnitFrames.healer"))
    for _, id in ipairs({ "UnitFrames.party", "UnitFrames.raid" }) do
        local page = O.GetPage(id)
        T.eq(#O.ValidatePage(page), 0, id)
        for _, g in ipairs(page.groups) do T.truthy(g.label ~= "Healer frames are on", id) end
    end
end)

T.test("the target's aura cards sit on the Target page's Auras tab", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    T.isnil(O.GetPage("UnitFrames.auras"), "no page of their own")
    local groups = O.GetPage("UnitFrames.target").groups
    local by = {}
    for _, g in ipairs(groups) do by[g.label] = g end
    T.eq(by["Extra text 1"].tab, "Text", "the extra text cards (Add piece) with the text")
    T.eq(by.Debuffs.tab, "Auras")
    T.eq(by.Buffs.tab, "Auras")
    T.eq(by.Debuffs.items[1].key, "targetAuras.debuffs")
    T.eq(by.Buffs.items[1].key, "targetAuras.buffs")
    -- Each card carries where its row sits, so Design mode's card filter shows it.
    local keys = {}
    for _, g in ipairs({ by.Debuffs, by.Buffs }) do
        for _, it in ipairs(g.items) do if it.key then keys[it.key] = it end end
    end
    for _, k in ipairs({ "debuffSpot", "debuffGrow", "debuffX", "debuffY", "buffSpot", "buffGrow", "buffX", "buffY" }) do
        T.truthy(keys["targetAuras." .. k], k)
    end
    T.eq(#O.ValidatePage(O.GetPage("UnitFrames.target")), 0)
end)

T.test("frame pages carry a live sample; other pages don't", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    for _, id in ipairs({ "player", "target", "focus", "targettarget", "pet", "party", "raid" }) do
        T.eq(type(O.GetPage("UnitFrames." .. id).sample), "function", id)
    end
    for _, id in ipairs({ "UnitFrames.colors", "UnitFrames.castbars", "appearance" }) do
        T.isnil(O.GetPage(id).sample, id)
    end
end)

T.test("search matches labels, descriptions and card titles", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    T.eq(O.CountMatches(O.GetPage("UnitFrames.target"), "debuffs from others"), 1)
    T.eq(O.CountMatches(O.GetPage("appearance"), "gray"), 1, "softness description")
    T.eq(O.CountMatches(O.GetPage("home"), "pick a page"), 0, "text never matches")
end)

-- ---------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------

local function open(id)
    local DUI = stub.Load({ module = true })
    DUI.OptionsPanel.Show(id)
    return DUI, DUI.OptionsPanel.PageFrame()
end

local function rowFor(pf, key)
    for _, card in ipairs(pf.cards) do
        for _, row in ipairs(card.rows) do
            if row.item.key == key then return row end
        end
    end
end

T.test("every page opens", function()
    local DUI = stub.Load({ module = true })
    for id in DUI.Options.Pages() do
        DUI.OptionsPanel.Show(id)
        T.eq(DUI.OptionsPanel.Current(), id)
        T.truthy(DUI.OptionsPanel.PageFrame():IsShown(), id)
    end
    T.eq(#stub.errors, 0)
end)

T.test("a switch flips its setting, and so does clicking its row", function()
    local DUI, pf = open("UnitFrames.target")
    local row = rowFor(pf, "target.showMarker")
    row.control:Click()
    T.eq(DUI:Get("UnitFrames", "target.showMarker"), false)
    T.truthy(row.reset:IsShown(), "changed, so the reset arrow shows")
    row:GetScript("OnMouseUp")(row, "LeftButton")
    T.eq(DUI:Get("UnitFrames", "target.showMarker"), true)
    T.falsy(row.reset:IsShown())
end)

T.test("sliders snap, show units and take typed values", function()
    local DUI, pf = open("appearance")
    local row = rowFor(pf, "softness")
    local s, box = row.control.slider, row.control.box
    s:GetScript("OnValueChanged")(s, 0.333, true)
    T.eq(DUI:Get("general", "softness"), 0.35)
    T.eq(box:GetText(), "35%")
    box:SetText("60 %")
    box:GetScript("OnEnterPressed")(box)
    T.eq(DUI:Get("general", "softness"), 0.6)
    box:SetText("500")
    box:GetScript("OnEnterPressed")(box)
    T.eq(DUI:Get("general", "softness"), 0.8, "clamped to the range")
    local W = DUI.Widgets
    T.eq(W.FormatValue({ unit = "px" }, 4), "4 px")
    T.eq(W.FormatValue({ unit = "x" }, 1.25), "1.25x")
end)

T.test("W.Slider: the same slider on any frame, through get and set", function()
    local DUI = open("appearance")
    local W = DUI.Widgets
    local value, disabled, previews = 70, false, {}
    local f = W.Slider(UIParent, { min = 40, max = 95, step = 5, width = 200,
        get = function() return value end, set = function(v) value = v end,
        preview = function(v) previews[#previews + 1] = v; return false end,
        disabled = function() return disabled end })
    f.Refresh()
    T.eq(f.box:GetText(), "70")
    T.eq(f:GetWidth(), 200)
    local s = f.slider
    s:GetScript("OnValueChanged")(s, 61, true)
    T.eq(value, 60, "snapped to the step, written through set")
    T.eq(f.box:GetText(), "60")
    f.box:SetText("500")
    f.box:GetScript("OnEnterPressed")(f.box)
    T.eq(value, 95, "typed, clamped to the range")
    disabled = true
    s:GetScript("OnValueChanged")(s, 45, true)
    T.eq(value, 95, "disabled: no write")
    local pct = W.Slider(UIParent, { min = 0, max = 1, step = 0.05, unit = "%", get = function() return 0.5 end, set = function(v) value = v end })
    pct.box:SetText("35%")
    pct.box:GetScript("OnEnterPressed")(pct.box)
    T.eq(value, 0.35, "a % slider takes \"35%\" as 0.35")
end)

T.test("dropdowns pick from their list", function()
    local DUI, pf = open("UnitFrames.target")
    local row = rowFor(pf, "targetAuras.debuffFilter")
    local others = rowFor(pf, "targetAuras.maxOtherDebuffs")
    T.falsy(others.disabled)
    row.control:Click()
    T.eq(DUI.Widgets.menuOwner, row.control)
    local first = DUI.Widgets.MenuRow(1)
    T.eq(first.text:GetText(), "Only mine")
    T.falsy(first.check:IsShown())
    T.truthy(DUI.Widgets.MenuRow(2).check:IsShown(), "the current choice is ticked")
    first:Click()
    T.isnil(DUI.Widgets.menuOwner, "picking closes the list")
    T.eq(DUI:Get("UnitFrames", "targetAuras.debuffFilter"), "mine")
    T.eq(row.control.text:GetText(), "Only mine")
    T.truthy(others.disabled, "others only count when showing others")
    T.eq(others:GetAlpha(), 0.35)
end)

T.test("disabled rows ignore input", function()
    local DUI, pf = open("UnitFrames.castbars")
    local width = rowFor(pf, "playerCastbar.width")
    T.truthy(width.disabled)
    local s = width.control.slider
    s:GetScript("OnValueChanged")(s, 400, true)
    T.eq(DUI:Get("UnitFrames", "playerCastbar.width"), 285)
end)

-- The profiles page calls W.Confirm again on every refresh of its delete buttons.
-- Each call used to hook one more OnHide and wrap Paint once more.
T.test("W.Confirm asked again on the same button wires it once, with the new words and act", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local b = W.Button(UIParent, "", 24)
    local acted = {}
    W.Confirm(b, "First", function() acted[#acted + 1] = 1 end)
    local hooks = 0
    for _ in pairs(rawget(b, "__hookParts") or {}) do hooks = hooks + 1 end
    for _ = 1, 5 do W.Confirm(b, "Second", function() acted[#acted + 1] = 2 end) end
    local now = 0
    for _ in pairs(rawget(b, "__hookParts") or {}) do now = now + 1 end
    T.eq(now, hooks, "one OnHide hook, however often it's asked")
    T.eq(b.text:GetText(), "Second", "the new words")
    local texts = 0
    local set = b.text.SetText
    b.text.SetText = function(fs, ...) texts = texts + 1; return set(fs, ...) end
    b.Paint()
    T.eq(texts, 1, "one paint, not a chain of them")
    b.text.SetText = set
    b:Click()
    T.eq(b.text:GetText(), "Click again")
    stub.Advance(1)   -- past W.CONFIRM_GAP: a real second click, not a double-click
    b:Click()
    T.deq(acted, { 2 }, "the new act, once")
    b:Click()
    b:Hide()
    T.eq(b.text:GetText(), "Second", "hidden: back to plain")
end)

T.test("resets that can't be undone take two clicks", function()
    local DUI, pf = open("UnitFrames.player")
    DUI:Set("UnitFrames", "player.width", 300)
    local b = DUI.OptionsPanel.ResetButton()
    T.truthy(b:IsShown())
    b:Click()
    T.eq(DUI:Get("UnitFrames", "player.width"), 300, "one click only arms it")
    T.eq(b.text:GetText(), "Click again")
    stub.RunTimers()
    T.eq(b.text:GetText(), "Reset page", "disarms after a moment")
    b:Click()
    stub.Advance(1)   -- past W.CONFIRM_GAP: a real second click, not a double-click
    b:Click()
    T.eq(DUI:Get("UnitFrames", "player.width"), 187)
    T.falsy(rowFor(pf, "player.width").reset:IsShown())
end)

T.test("unlocking from the options window hides it and shows the Lock button; locking brings it back", function()
    local DUI = open("layout")
    local P = DUI.OptionsPanel
    local pf = P.PageFrame()
    local row = pf.cards[1].rows[2]
    T.eq(row.control.text:GetText(), "Unlock")
    row.control:Click()
    T.truthy(DUI.Movers.unlocked)
    T.falsy(P.IsShown(), "unlocking hides the window")
    T.truthy(DUI.Movers.LockButton():IsShown(), "the Lock button shows instead")
    DUI.Movers.LockButton():Click()
    T.falsy(DUI.Movers.unlocked)
    T.truthy(P.IsShown(), "locking brings the window back")
    T.eq(P.Current(), "layout", "on the page it was left on")
end)

T.test("locking again puts the window back on the scroll spot you left, too", function()
    local DUI = open("UnitFrames.target")
    local P = DUI.OptionsPanel
    local scroll = P.PageFrame():GetParent()
    scroll:SetVerticalScroll(42)
    DUI.Movers.Unlock()
    DUI.Movers.Lock()
    T.eq(P.Current(), "UnitFrames.target")
    T.eq(P.PageFrame():GetParent():GetVerticalScroll(), 42)
end)

T.test("opening the window yourself while still unlocked cancels the reopen", function()
    local DUI = open("UnitFrames.target")
    local P = DUI.OptionsPanel
    DUI.Movers.Unlock()
    T.falsy(P.IsShown())
    P.Show("appearance")
    T.truthy(P.IsShown())
    P.Show("layout")
    DUI.Movers.Lock()
    T.eq(P.Current(), "layout", "locking doesn't jump back to the old page")
end)

T.test("/dui unlock with no options open just shows the Lock button", function()
    local DUI = stub.Load({ module = true })
    DUI.Movers.Unlock()
    T.falsy(DUI.OptionsPanel.IsShown())
    T.truthy(DUI.Movers.LockButton():IsShown())
    DUI.Movers.Lock()
    T.falsy(DUI.OptionsPanel.IsShown(), "still closed: it was never open")
end)

T.test("picking a custom accent opens the color picker, and the color picked is the accent", function()
    local DUI = stub.Load()
    local shown
    _G.ColorPickerFrame = { SetupColorPickerAndShow = function(_, info) shown = info end,
                            GetColorRGB = function() return 0.2, 0.6, 0.9 end }
    local page = DUI.Options.GetPage("appearance")
    local accent, swatch
    for _, group in ipairs(page.groups) do
        for _, item in ipairs(group.items) do
            if item.key == "accent" then accent = item end
            if item.key == "accentColor" then swatch = item end
        end
    end
    T.truthy(swatch, "a custom color swatch")
    T.truthy(swatch.disabled(function(k) return DUI:Get("general", k) end), "grayed out until custom is picked")
    DUI:Set("general", "accent", "custom")
    accent.onPick("custom")
    T.truthy(shown, "the color picker opens")
    shown.swatchFunc()
    stub.RunTimers()
    local r, g, b = DUI.Style.Accent()
    T.near(r, 0.2, 1e-6); T.near(g, 0.6, 1e-6); T.near(b, 0.9, 1e-6, "the picked color is the accent")
    T.falsy(swatch.disabled(function(k) return DUI:Get("general", k) end), "the swatch usable now")
end)

T.test("the local font toggle is only shown on Korean and Chinese clients", function()
    local real = _G.GetLocale
    local DUI = stub.Load()
    local O = DUI.Options
    local page = O.GetPage("appearance")
    local item
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do if it.key == "localFont" then item = it end end
    end
    T.truthy(item, "item exists")
    _G.GetLocale = function() return "enUS" end
    T.truthy(O.IsHidden(page, item))
    _G.GetLocale = function() return "koKR" end
    T.falsy(O.IsHidden(page, item))
    _G.GetLocale = real
end)

T.test("a dropdown's name too long for its box shows whole in a tooltip", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local page = { id = "test.longpick", scope = "general" }
    local parent = CreateFrame("Frame", nil, UIParent)
    local long = "A very long choice that does not fit the box"
    local drop = W.CompactRow(parent, page, { type = "dropdown", label = "Pick",
        get = function() return "a" end, set = function() end,
        values = { a = long }, order = { "a" } }, 206)
    drop.Refresh()
    local lines, saved = {}, rawget(_G, "GameTooltip")
    _G.GameTooltip = {
        SetOwner = function() end, Show = function() end, Hide = function() end,
        AddLine = function(_, text) lines[#lines + 1] = text end,
    }
    local b = drop.control
    b.text.IsTruncated = function() return true end
    b:GetScript("OnEnter")(b)
    _G.GameTooltip = saved
    T.eq(#lines, 1, "the name alone, no empty line")
    T.eq(lines[1], long)
end)

T.test("compact rows read and write their item, label above or beside", function()
    local DUI = stub.Load()
    local W = DUI.Widgets
    local page = { id = "test.compact", scope = "general" }
    local store = { size = 20, on = false, pick = "a", col = { 1, 0, 0 } }
    local function item(key, t)
        t.get = function() return store[key] end
        t.set = function(v) store[key] = v end
        return t
    end
    local parent = CreateFrame("Frame", nil, UIParent)
    local slider = W.CompactRow(parent, page, item("size", { type = "slider", label = "Size", min = 10, max = 40, step = 1 }), 206)
    local toggle = W.CompactRow(parent, page, item("on", { type = "toggle", label = "On" }), 206)
    local drop = W.CompactRow(parent, page, item("pick", { type = "dropdown", label = "Pick",
        values = { a = "A", b = "B" }, order = { "a", "b" } }), 206)
    local color = W.CompactRow(parent, page, item("col", { type = "color", label = "Colour" }), 206)
    T.eq(slider.height, W.COMPACT_STACKED); T.eq(drop.height, W.COMPACT_STACKED)
    T.eq(toggle.height, W.COMPACT_INLINE); T.eq(color.height, W.COMPACT_INLINE)
    T.eq(slider.control:GetWidth(), 206, "stacked controls take the full width")
    T.eq(drop.control:GetWidth(), 206)
    T.eq(slider.label:GetText(), "Size")
    slider.Refresh(); toggle.Refresh(); drop.Refresh(); color.Refresh()
    T.eq(drop.control.text:GetText(), "A")
    toggle.control:Click()
    T.eq(store.on, true, "toggle writes")
    drop.control:Click()
    W.MenuRow(2):Click()
    T.eq(store.pick, "b", "dropdown writes")
    local box = slider.control.box
    box:SetText("30")
    box:GetScript("OnEnterPressed")(box)
    T.eq(store.size, 30, "slider writes")
    local off = item("on", { type = "toggle", label = "Off", disabled = function() return true end })
    local dis = W.CompactRow(parent, page, off, 206)
    dis.Refresh()
    T.truthy(dis.disabled); T.eq(dis:GetAlpha(), 0.35)
    dis.control:Click()
    T.eq(store.on, true, "a disabled row ignores clicks")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("a page finds a setting's card and row, and knows how far down each sits", function()
    local _, pf = open("UnitFrames.target")
    local card, row = pf.Find("target.fade.mode")
    T.truthy(card and row)
    T.eq(row.item.key, "target.fade.mode")
    T.eq(pf.cards[1].offsetY, 0, "the first card at the top")
    T.truthy(card.offsetX > 0 or card.offsetY > 0, "the fade card beside it or further down")
    T.truthy(row.offsetY >= card.top, "rows start under the card's title")
    T.isnil(pf.Find("nope.nothing"))
end)

T.test("flashed rows light up, then fade out; a new flash ends the last", function()
    local DUI, pf = open("UnitFrames.target")
    local W = DUI.Widgets
    local _, row = pf.Find("target.width")
    W.Flash({ row })
    T.truthy(row.flash:IsShown())
    stub.RunOnUpdate(W.FlashDriver(), W.FLASH_HOLD / 2)
    -- The fade rides in the tint: in game a gradient ignores SetAlpha.
    local function a() return select(4, row.flash:GetVertexColor()) end
    T.eq(a(), W.FLASH_ALPHA, "held at full first")
    stub.RunOnUpdate(W.FlashDriver(), W.FLASH_TIME / 2)
    T.truthy(row.flash:IsShown(), "still fading")
    T.truthy(a() < W.FLASH_ALPHA, "fading")
    stub.RunOnUpdate(W.FlashDriver(), W.FLASH_TIME)
    T.falsy(row.flash:IsShown(), "gone")
    local _, other = pf.Find("target.height")
    W.Flash({ row })
    W.Flash({ other })
    T.falsy(row.flash:IsShown(), "the last flash ended")
    T.truthy(other.flash:IsShown())
    W.Flash({})
    T.falsy(other.flash:IsShown(), "nothing to flash: the last one still ends")
end)

T.test("options: the effects switches can be found, and dim with Motion effects off", function()
    local DUI = stub.Load({ actionbars = true, bags = true, infopanel = true })
    local O = DUI.Options
    local function find(label)
        for _, hit in ipairs(O.Search(label)) do
            if hit.item.label == label then return hit end
        end
    end
    local effects = { "Ping when ready", "Count gold changes", "XP gain effects" }
    T.truthy(find("Motion effects"), "Motion effects is searchable")
    for _, label in ipairs(effects) do
        local hit = find(label)
        T.truthy(hit, label .. " is searchable")
        T.eq(O.Get(hit.page, hit.item), true, label .. " on by default")
        T.falsy(O.IsDisabled(hit.page, hit.item), label .. " usable")
    end
    DUI:Set("general", "motion", false)
    for _, label in ipairs(effects) do
        local hit = find(label)
        T.eq(O.IsDisabled(hit.page, hit.item), true, label .. " dims without Motion effects")
    end
end)

T.test("a Show X switch that needs a reload asks for it (invert + reload)", function()
    local DUI = stub.Load({ chat = true })
    local O = DUI.Options
    local page, item
    for _, p in O.Pages() do
        for _, g in ipairs(p.groups) do
            for _, it in ipairs(g.items) do
                if p.scope == "Chat" and it.key == "hideButtons" then page, item = p, it end
            end
        end
    end
    T.truthy(item and item.invert and item.reload, "Chat's side buttons switch")
    local asked = 0
    DUI.EditMode.AskReload = function() asked = asked + 1 end
    O.Set(page, item, not O.Get(page, item))
    T.eq(asked, 1, "flipping it asks for a reload")
    O.Set(page, item, O.Get(page, item))
    T.eq(asked, 1, "setting the same value again doesn't")
end)

T.test("a Hide setting reads Show X (invert): on means you see it, the saved value unchanged", function()
    local DUI = stub.Load({ module = true })
    local O = DUI.Options
    local page = O.GetPage("UnitFrames.party")
    local item
    for _, g in ipairs(page.groups) do
        for _, it in ipairs(g.items) do if it.key == "party.hideSelf" then item = it end end
    end
    T.eq(item.label, "Show yourself")
    local saved = DUI:Get("UnitFrames", "party.hideSelf")
    T.eq(O.Get(page, item), not saved, "shown flipped")
    T.eq(O.Default(page, item), not saved)
    T.truthy(O.IsDefault(page, item))
    O.Set(page, item, saved)
    T.eq(DUI:Get("UnitFrames", "party.hideSelf"), not saved, "the switch writes the flip")
    T.falsy(O.IsDefault(page, item))
    O.ResetItem(page, item)
    T.eq(DUI:Get("UnitFrames", "party.hideSelf"), saved, "reset")
    -- No switch label starts with Hide any more.
    for _, p in O.Pages() do
        for _, g in ipairs(p.groups) do
            for _, it in ipairs(g.items) do
                if it.type == "toggle" and type(it.label) == "string" then
                    T.falsy(it.label:find("^Hide "), p.id .. ": " .. it.label)
                end
            end
        end
    end
end)

-- Every row a player can change or press has hover text saying what it does.
-- Text and custom rows explain themselves.
T.test("every setting and button has a description", function()
    local DUI = stub.Load({ module = true, actionbars = true, buffs = true, bags = true, nameplates = true, tooltip = true,
                            qol = true, chat = true, infopanel = true, skins = true, quests = true })
    local O = DUI.Options
    local missing, seen = {}, {}
    for _, page in O.Pages() do
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items) do
                if not seen[it] and it.type ~= "text" and it.type ~= "custom" and (type(it.desc) ~= "string" or it.desc == "") then
                    seen[it] = true
                    missing[#missing + 1] = page.id .. " · " .. tostring(g.label) .. " · " .. tostring(O.Label(it))
                end
            end
        end
    end
    T.eq(#missing, 0, "no description:\n" .. table.concat(missing, "\n"))
end)

T.test("options: a row added since the version you count from says NEW; search finds them", function()
    local DUI = stub.Load()
    local O = DUI.Options
    DaylightUIDB.newSince = "1.5.0"
    T.truthy(O.IsNew({ since = "1.5.1" }))
    T.falsy(O.IsNew({ since = "1.5.0" }), "not newer")
    T.falsy(O.IsNew({}), "an untagged row never is")
    DaylightUIDB.newSince = "none"
    T.falsy(O.IsNew({ since = "1.5.1" }), "Nothing: no tags")
    DaylightUIDB.newSince = "1.0"
    local any = false
    for _, hit in ipairs(O.Search("new")) do
        if hit.item.since then any = true end
    end
    T.truthy(any, "searching new lists the tagged rows")
end)

T.test("options: the NEW tag sits after the label's words, clear of the reset arrow", function()
    local DUI = stub.Load({ module = true })
    DaylightUIDB.newSince = "1.0"
    local W = DUI.Widgets
    local row = W.Row(CreateFrame("Frame"), { id = "x" },
        { label = "x" }, { type = "toggle", key = "x", label = "Rarity colors", since = "1.5.1" })
    T.truthy(row.newTag and row.newTag:IsShown(), "tagged")
    local _, at, _, x = row.newTag:GetPoint(1)
    T.eq(at, row.label, "on the label")
    local p = select(1, row.newTag:GetPoint(1))
    T.eq(p, "LEFT")
    T.eq(select(3, row.newTag:GetPoint(1)), "LEFT", "from the label's left, not past its frame")
    T.eq(x, row.label:GetStringWidth() + 6, "right after the words")
    for i = 1, row.label:GetNumPoints() do
        local pt, _, _, ox = row.label:GetPoint(i)
        if pt == "RIGHT" then
            T.truthy(ox <= -(W.LABEL_GAP + row.newTag:GetStringWidth() + 6), "the label leaves room for the tag")
        end
    end
end)

T.test("options: an update counts from the version you came from, a new character from nothing", function()
    local DUI = stub.Load()
    local O = DUI.Options
    DaylightUIDB.lastVersion = "1.0"
    local v = DUI.VERSION
    DUI.VERSION = "1.5.1"
    O.NoteVersion()
    T.eq(DaylightUIDB.newSince, "1.0")
    T.eq(DaylightUIDB.lastVersion, "1.5.1")
    O.NoteVersion()
    T.eq(DaylightUIDB.newSince, "1.0", "the same version: unchanged")
    DUI.VERSION = v
end)
