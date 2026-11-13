-- What's on each page of the setup guide. Each builder makes a page frame,
-- laid out top to bottom at the width the window gives it, with a Refresh()
-- the guide calls whenever the page shows. Welcome and finish come first,
-- then the option pages (look, frames, everyday, quality of life), then the
-- modules and role pages.

local _, DUI = ...
local W = DUI.Widgets
local SIZE = DUI.Style.SIZE -- the text size scale
local C = W.COLORS
local Cards = DUI.InstallerCards
local L = DUI.L
local T = DUI.Options.Text -- page data and option items are in English and translated where drawn

local Steps = {}
DUI.InstallerSteps = Steps

local builders = {}
Steps.builders = builders

-- Whether a page (an InstallerPages entry) can be built.
function Steps.Has(def)
    return builders[def.id] ~= nil or (def.groups ~= nil and builders.groups ~= nil)
        or (def.bundle ~= nil and builders.bundle ~= nil)
end

-- Builds a page by id, hidden until the window shows it.
function Steps.Build(id, parent, width)
    local def = DUI.InstallerPages.Get(id)
    local make = builders[id] or (def and def.groups and builders.groups) or (def and def.bundle and builders.bundle)
    local page = make(parent, width, def)
    page:Hide()
    return page
end

-- A page laid out top to bottom. page.Add(frame, height, gap) places the next
-- thing under the last, as wide as the page.
local function stack(parent, width)
    local page = CreateFrame("Frame", nil, parent)
    page:SetWidth(width)
    page:SetHeight(1)
    local y = 0
    function page.Add(f, h, gap)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
        f:SetWidth(width)
        f:SetHeight(h)
        y = y + h + (gap or 12)
        page:SetHeight(y)
    end
    return page
end

-- A group title over what follows.
local function heading(page, text)
    local f = CreateFrame("Frame", nil, page)
    f.text = W.Title(f, SIZE.head, C.text)
    f.text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
    f.text:SetText(T(text))
    page.Add(f, 22, 8)
    return f
end

-- One or more lines of wrapping text.
local function para(page, text, size, color, h)
    local f = CreateFrame("Frame", nil, page)
    f.text = W.Font(f, W.BODY, size or SIZE.small, color or C.dim)
    f.text:SetWordWrap(true)
    f.text:SetJustifyV("TOP")
    f.text:SetAllPoints(f)
    f.text:SetText(T(text or ""))
    page.Add(f, h or 18, 8)
    return f
end

-- Welcome

-- A greeting under the banner, a line about DaylightUI, and three cards that
-- each act on click. For a character not set up yet: Quick setup, Let me
-- choose, Use a setup I have (when there is one). For one already set up:
-- Keep my setup (selected), Let me choose, Quick setup. Built once per setup
-- shape (Installer.lua's key for it) and reused; the picks live on the
-- running flow (Installer.flow), set by Reset.
builders.welcome = function(parent, width)
    local I = DUI.Installer
    local flow = I.flow
    local page = stack(parent, width)
    page.cards = {}

    local greet = CreateFrame("Frame", nil, page)
    greet.text = W.Title(greet, SIZE.title, C.text, "CENTER")
    greet.text:SetAllPoints(greet)
    page.greeting = greet.text
    page.Add(greet, 26, 6)

    local intro = CreateFrame("Frame", nil, page)
    intro.text = W.Font(intro, W.BODY, SIZE.body, C.dim, "CENTER")
    intro.text:SetWordWrap(true)
    intro.text:SetAllPoints(intro)
    intro.text:SetText(flow.mode == "showcase" and I.TEXT.showcase or I.TEXT.intro)
    page.Add(intro, 36, 16)

    local showcase = flow.mode == "showcase"
    local hasMine = showcase or #I.ExistingProfiles() > 0
    local n = hasMine and 3 or 2
    local cw = (width - (n - 1) * Cards.GAP) / n
    local row = CreateFrame("Frame", nil, page)
    local list = {}

    local function card(title, text)
        local c = Cards.Card(row)
        c.title = W.Title(c.inner, SIZE.head, C.text)
        c.title:SetPoint("TOPLEFT", c.inner, "TOPLEFT", 14, -16)
        c.title:SetText(title)
        c.text = Cards.Text(c, text)
        c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -8)
        c.text:SetPoint("RIGHT", c.inner, "RIGHT", -14, 0)
        list[#list + 1] = c
        return c
    end

    -- One button per ready-made setup, stacked from the bottom up (the last one
    -- lowest), each explaining itself on hover.
    local function quick()
        local c = card(L["Quick setup"], L["Everything on, with DaylightUI picks. How do you play?"])
        local below
        for _, it in ipairs({ { "leveling", L["Immersive Preset"], "Immersive Preset" }, { "healer", L["Healer"], "Healer" },
                              { "dps", L["Damage / Tank"], "DPS/Tank" } }) do
            local b = W.Button(c.inner, it[2], 26)
            if below then
                b:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 6)
                b:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, 6)
            else
                b:SetPoint("BOTTOMLEFT", c.inner, "BOTTOMLEFT", 14, 14)
                b:SetPoint("BOTTOMRIGHT", c.inner, "BOTTOMRIGHT", -14, 14)
            end
            b:SetScript("OnClick", function() I.Start("quick", it[3]) end)
            b:HookScript("OnEnter", function() W.Tooltip(b, it[2], I.ROLE_TEXT[it[3]]) end)
            b:HookScript("OnLeave", W.HideTooltip)
            c[it[1]] = b
            below = b
        end
        page.cards.quick = c
    end

    local function tour()
        local c = card(L["Let me choose"], L["A two-minute tour of everything DaylightUI does, picking as you go. Nothing is saved until you finish."])
        c:SetScript("OnClick", function() I.Start("tour") end)
        page.cards.tour = c
    end

    -- A profile they already have. "keep" offers every profile with the active
    -- one selected; otherwise every one except DPS/Tank.
    local function mine(keep)
        local names = keep and DUI.Profiles.Names() or I.ExistingProfiles()
        if #names == 0 then return end
        page.names = names
        local c = card(keep and L["Keep my setup"] or L["Use a setup I have"],
            keep and L["Stay on your profile as it is, or pick another."] or L["Put this character on a profile you already have, as it is."])
        c.use = W.Button(c.inner, keep and L["Keep it"] or L["Use this"], 28)
        c.use:SetPoint("BOTTOMLEFT", c.inner, "BOTTOMLEFT", 14, 14)
        c.use:SetPoint("BOTTOMRIGHT", c.inner, "BOTTOMRIGHT", -14, 14)
        c.use:SetScript("OnClick", function() I.Start(keep and "keep" or "existing", I.flow and I.flow.profile) end)
        local item = { type = "dropdown", label = "Profile", desc = "A profile from the Profiles page, used as it is.",
            choices = function()
                local values = {}
                for _, name in ipairs(names) do values[name] = name end
                return values, names
            end,
            get = function() return I.flow and I.flow.profile end,
            set = function(v) if I.flow then I.flow.profile = v end end }
        c.pick = W.CompactRow(c.inner, {}, item, cw - 28)
        c.pick:SetPoint("BOTTOMLEFT", c.use, "TOPLEFT", 0, 8)
        if keep then
            c.SetSelected(true)
            c.SetTag(L["In use"])
        end
        page.cards.mine = c
    end

    if showcase then
        mine(true); tour(); quick()
    else
        quick(); tour()
        if hasMine then mine(false) end
    end
    for i, c in ipairs(list) do
        c:SetSize(cw, 178)
        c:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (cw + Cards.GAP), 0)
    end
    page.Add(row, 178, 8)

    -- One card per profile pack (Profiles.RegisterPack), three per row, with its
    -- author and a button per profile that works like a Quick setup.
    local P = DUI.Profiles
    local packs = {}
    for _, id in ipairs(P.PACK_ORDER) do
        local entries = P.PackProfiles(P.PACKS[id])
        if #entries > 0 then packs[#packs + 1] = { pack = P.PACKS[id], entries = entries } end
    end
    page.packs = {}
    if #packs > 0 then
        heading(page, "Profile packs")
        local cols = math.min(#packs, 3)
        local pw = (width - (cols - 1) * Cards.GAP) / cols
        for first = 1, #packs, cols do
            local line = CreateFrame("Frame", nil, page)
            local most = 0
            for i = first, math.min(first + cols - 1, #packs) do most = math.max(most, #packs[i].entries) end
            local ch = math.max(178, 92 + most * 32)
            for i = first, math.min(first + cols - 1, #packs) do
                local pack, entries = packs[i].pack, packs[i].entries
                local c = Cards.Card(line)
                c.title = W.Title(c.inner, SIZE.head, C.text)
                c.title:SetPoint("TOPLEFT", c.inner, "TOPLEFT", 14, -16)
                c.title:SetPoint("RIGHT", c.inner, "RIGHT", -14, 0)
                c.title:SetText(pack.label)
                local by = pack.author and string.format(L["By %s."], pack.author)
                c.text = Cards.Text(c, by and pack.desc and (by .. " " .. pack.desc) or by or pack.desc or "")
                c.text:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -8)
                c.text:SetPoint("RIGHT", c.inner, "RIGHT", -14, 0)
                c.buttons = {}
                local below
                for k = #entries, 1, -1 do
                    local e = entries[k]
                    local b = W.Button(c.inner, e.name, 26)
                    if below then
                        b:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 6)
                        b:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, 6)
                    else
                        b:SetPoint("BOTTOMLEFT", c.inner, "BOTTOMLEFT", 14, 14)
                        b:SetPoint("BOTTOMRIGHT", c.inner, "BOTTOMRIGHT", -14, 14)
                    end
                    b:SetScript("OnClick", function() I.Start("quick", e.name) end)
                    if e.sub then
                        b:HookScript("OnEnter", function() W.Tooltip(b, e.name, e.sub) end)
                        b:HookScript("OnLeave", W.HideTooltip)
                    end
                    c.buttons[e.name] = b
                    below = b
                end
                c:SetSize(pw, ch)
                c:SetPoint("TOPLEFT", line, "TOPLEFT", (i - first) * (pw + Cards.GAP), 0)
                page.packs[pack.id] = c
            end
            page.Add(line, ch, 12)
        end
    end

    -- A new run of the guide starts its profile pick on the active profile.
    function page.Reset()
        local names = page.names
        if not (names and I.flow) then return end
        I.flow.profile = names[1]
        for _, name in ipairs(names) do
            if name == DUI.DB.ActiveName() then I.flow.profile = name end
        end
        page.cards.mine.pick.Refresh()
    end
    page.Reset()

    function page.Refresh()
        page.greeting:SetText(I.GreetingText())
        if page.cards.mine then page.cards.mine.pick.Refresh() end
    end
    return page
end

-- Finish

-- What Finish will do (a card with a line per part, each with Change), a
-- note when the profile is shared, a status line for anything in the way,
-- then Finish, Reload or Done with ticks appearing below it, and a card of
-- useful commands at the bottom.
Steps.FINISH_ROW = 30 -- one line of the summary card
Steps.FINISH_NAMES = 0.34 -- share of the card's width for the names column
Steps.FINISH_W = 260 -- width of Finish, Reload and Done, centered
Steps.FINISH_H = 40
Steps.TIP_ROW = 20 -- one line of the Good to know card

-- "just the quest tracker" -> "Just the quest tracker", since a value starts its column.
local function capital(text)
    return (string.gsub(text, "^%l", string.upper))
end

builders.finish = function(parent, width)
    local I = DUI.Installer
    local M = DUI.Motion
    local page = CreateFrame("Frame", nil, parent)
    page:SetWidth(width)
    page:SetHeight(1)
    local inner = width - 2 * W.PAD
    local namesW = math.floor(inner * Steps.FINISH_NAMES)

    -- What Finish does: a card with a line per part, its name (tan), its value
    -- (white) and Change. A part with no name is a sentence.
    page.card = W.Card(page, nil, { label = L["Your setup"], items = {} })
    page.card:SetWidth(width)
    page.lines = {}
    local function line(i)
        local l = page.lines[i]
        if l then return l end
        l = CreateFrame("Frame", nil, page.card)
        l:SetSize(width, Steps.FINISH_ROW)
        l.line = l:CreateTexture(nil, "BORDER") -- W.Row's divider between lines
        l.line:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
        l.line:SetHeight(1)
        l.line:SetPoint("TOPLEFT", l, "TOPLEFT", W.PAD, 0)
        l.line:SetPoint("TOPRIGHT", l, "TOPRIGHT", -W.PAD, 0)
        l.change = W.Link(l) -- accent and growing underline on hover
        l.change.SetLabel(L["Change"])
        l.change:SetPoint("RIGHT", l, "RIGHT", -W.PAD, 0)
        l.name = W.Font(l, W.BODY, SIZE.body, C.dim)
        l.name:SetPoint("LEFT", l, "LEFT", W.PAD, 0)
        l.name:SetWidth(namesW - 8)
        l.value = W.Font(l, W.BODY, SIZE.body, C.value)
        page.lines[i] = l
        return l
    end

    -- Another addon a pack sets up (Installer.Extras): a switch that's on until
    -- the player turns it off, still shown after Finish.
    page.extras = {}
    local function extraRow(i)
        local r = page.extras[i]
        if r then return r end
        r = CreateFrame("Frame", nil, page)
        r:SetSize(width, 24)
        r.switch = W.Switch(r)
        r.switch:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.text = W.Font(r, W.BODY, SIZE.body, C.text)
        r.text:SetPoint("LEFT", r.switch, "RIGHT", 10, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.switch:SetScript("OnClick", function()
            if not r.key or (I.flow and I.flow.finished) then return end
            I.SetExtra(r.key, not I.ExtraOn(r.key))
            r.switch.SetOn(I.ExtraOn(r.key))
        end)
        page.extras[i] = r
        return r
    end

    local function wrapped(size, color, justify)
        local fs = W.Font(page, W.BODY, size, color, justify)
        fs:SetWordWrap(true)
        fs:SetJustifyV("TOP")
        fs:SetWidth(width)
        return fs
    end
    page.shared = wrapped(SIZE.small, C.dim)
    -- The tour's "Save your setup as" (Installer.SaveAs), with a note below
    -- saying where it goes.
    page.saveLabel = W.Font(page, W.BODY, SIZE.small, C.dim)
    page.saveLabel:SetText(L["Save your setup as"])
    local box = W.Input(page, { height = 28, maxLetters = DUI.Profiles.MAX_NAME,
        onChange = function(text, userInput)
            if not (userInput and I.flow) then return end
            I.flow.saveAs = text
            page.Refresh()
        end })
    box:SetWidth(width)
    page.saveAs = box
    page.status = wrapped(SIZE.body, C.warn, "CENTER")
    page.status:SetText("")

    -- Finish's ticks in a row under the button. Their space is reserved from the
    -- start so nothing moves when they appear.
    page.tickRow = CreateFrame("Frame", nil, page)
    page.tickRow:SetSize(width, 22)
    page.checks = {}
    for i, text in ipairs(I.CHECKLIST) do
        local c = CreateFrame("Frame", nil, page.tickRow)
        c:SetHeight(22)
        c.icon = W.Icon(c, "ui-check.png", 12, C.dim)
        c.icon:SetPoint("LEFT", c, "LEFT", 0, 0)
        c.text = W.Font(c, W.BODY, SIZE.small, C.text)
        c.text:SetPoint("LEFT", c, "LEFT", 18, 0)
        c.text:SetText(text)
        c:Hide()
        page.checks[i] = c
    end
    -- Centered as a row, however wide the language makes them.
    local function placeTicks()
        local widths, total, gap = {}, 0, 22
        for i, c in ipairs(page.checks) do
            local w = c.text:GetStringWidth()
            if type(w) ~= "number" or w <= 0 then w = 90 end
            widths[i] = 18 + math.ceil(w)
            total = total + widths[i] + (i > 1 and gap or 0)
        end
        local x = math.floor((width - total) / 2)
        for i, c in ipairs(page.checks) do
            c:SetWidth(widths[i])
            c:ClearAllPoints()
            c:SetPoint("LEFT", page.tickRow, "LEFT", x, 0)
            x = x + widths[i] + gap
        end
    end

    local function bigButton(text, onClick)
        local b = W.Button(page, text, Steps.FINISH_H)
        b:SetWidth(Steps.FINISH_W)
        b.SetActive(true)
        b:SetScript("OnClick", onClick)
        return b
    end
    page.finish = bigButton(L["Finish"], function() I.Finish() end)
    page.done = bigButton(DONE or L["Done"], function() I.Done() end)
    page.done:Hide()
    page.fallback = bigButton(L["Reload"], function() I.ReloadPopup() end)
    page.fallback:Hide()
    -- Where the secure Reload button goes (InstallerUI.ShowReload).
    page.slot = CreateFrame("Frame", nil, page)
    page.slot:SetSize(Steps.FINISH_W, Steps.FINISH_H)

    -- Good to know: a card of commands, each highlighted in the accent.
    page.tipCard = W.Card(page, nil, { label = L["Good to know"], items = {} })
    page.tipCard:SetWidth(width)
    page.tips = {}
    for i in ipairs(I.TIPS) do
        local fs = W.Font(page.tipCard, W.BODY, SIZE.small, C.text)
        fs:SetPoint("RIGHT", page.tipCard, "RIGHT", -W.PAD, 0)
        page.tips[i] = fs
    end
    local function paintTips()
        page.tipCard.Layout()
        local top = page.tipCard.top or 34
        local lit = DUI.Win.Parts.Hex({ DUI.Style.Accent() })
        for i, tip in ipairs(I.TIPS) do
            local fs = page.tips[i]
            fs:SetPoint("TOPLEFT", page.tipCard, "TOPLEFT", W.PAD, -(top + 2 + (i - 1) * Steps.TIP_ROW))
            fs:SetText(string.format(tip[2], lit .. tip[1] .. "|r"))
        end
        local h = top + #I.TIPS * Steps.TIP_ROW + 8
        page.tipCard:SetHeight(h)
        return h
    end

    function page.Refresh()
        local flow = I.flow
        local finished = flow and flow.finished
        local y = 0
        local function put(f, h, gap)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -y)
            y = y + h + (gap or 6)
        end
        local items = flow and I.Summary() or {}
        page.card.Layout()
        local top = page.card.top or 34
        for i, s in ipairs(items) do
            local l = line(i)
            local named = s.label ~= nil and s.value ~= nil
            l.name:SetShown(named)
            l.value:ClearAllPoints()
            l.value:SetPoint("RIGHT", l.change, "LEFT", -8, 0)
            if named then
                l.name:SetText(s.label)
                l.value:SetText(capital(s.value))
                W.TextColor(l.value, C.value)
                l.value:SetPoint("LEFT", l, "LEFT", W.PAD + namesW, 0)
            else
                l.value:SetText(s.text)
                W.TextColor(l.value, C.text)
                l.value:SetPoint("LEFT", l, "LEFT", W.PAD, 0)
            end
            l.change:SetShown(s.page ~= nil and not finished)
            l.change:SetScript("OnClick", function() I.Go(s.page) end)
            l.line:SetShown(i > 1)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", page.card, "TOPLEFT", 0, -(top + (i - 1) * Steps.FINISH_ROW))
            l:Show()
        end
        for i = #items + 1, #page.lines do page.lines[i]:Hide() end
        local cardH = top + #items * Steps.FINISH_ROW + 8
        page.card:SetHeight(cardH)
        put(page.card, cardH, 14)
        local extras = flow and I.Extras() or {}
        for i, x in ipairs(extras) do
            local r = extraRow(i)
            r.key = x.key
            r.text:SetText(string.format(L["Set up %s the way %s has it"], x.extra.label, x.extra.pack.label))
            r.switch.off = finished == true
            r.switch.SetOn(I.ExtraOn(x.key))
            r:Show()
            put(r, 24, 4)
        end
        for i = #extras + 1, #page.extras do page.extras[i]:Hide() end
        if #extras > 0 then y = y + 10 end
        local name = flow and I.SaveAs()
        page.saveLabel:SetShown(name ~= nil)
        page.saveAs:SetShown(name ~= nil)
        if name then
            -- Not while typing, or the cursor would jump.
            if not page.saveAs:HasFocus() then page.saveAs:SetText(name) end
            page.saveAs:EnableMouse(not finished)
            if finished then page.saveAs:ClearFocus() end
            put(page.saveLabel, 16, 4)
            put(page.saveAs, 28, 6)
        end
        local note = flow and I.SaveNote()
        page.shared:SetText(note or "")
        page.shared:SetShown(note ~= nil)
        if note then put(page.shared, 32, 8) end
        y = y + 6
        local status = page.status:GetText()
        page.status:SetShown(type(status) == "string" and status ~= "")
        if page.status:IsShown() then put(page.status, 32, 8) end
        for _, b in ipairs({ page.slot, page.finish, page.done, page.fallback }) do
            b:ClearAllPoints()
            b:SetPoint("TOP", page, "TOPLEFT", width / 2, -y)
        end
        y = y + Steps.FINISH_H + 10
        placeTicks()
        put(page.tickRow, 22, 18)
        local tipH = paintTips()
        put(page.tipCard, tipH, 0)
        page:SetHeight(y)
    end

    function page.Status(text)
        page.status:SetText(text or "")
        page.Refresh()
    end

    -- After Finish runs, ticks appear one at a time (giving the game a moment to
    -- save the layout), then Reload, or Done when no reload is needed.
    function page.RunChecklist(reload)
        page.finish:Hide()
        for _, c in ipairs(page.checks) do c:Hide() end
        page.run = (page.run or 0) + 1
        local run = page.run
        local i = 0
        local function step()
            if page.run ~= run then return end -- the page was reset for a new run
            i = i + 1
            local c = page.checks[i]
            if c then
                c:Show()
                W.TintAccent(c.icon)
                M.Fade(c, 0, 1, M.FAST)
                C_Timer.After(I.CHECK_STEP, step)
            else
                page.ShowEnd(reload)
            end
        end
        page.Refresh()
        C_Timer.After(I.CHECK_STEP, step)
    end

    -- The end of the checklist, and again whenever the page shows after it.
    function page.ShowEnd(reload)
        page.ended = reload
        page.finish:Hide()
        page.Refresh()
        if reload then
            page.done:Hide()
            if not DUI.InstallerUI.ShowReload(page.slot) then page.fallback:Show() end
        else
            page.done:Show()
        end
    end

    -- A new run of the guide (pages are reused since frames can't be freed). Go
    -- back to before Finish and stop a checklist that's still ticking.
    function page.Reset()
        page.run = (page.run or 0) + 1
        page.ended = nil
        page.status:SetText("")
        for _, c in ipairs(page.checks) do c:Hide() end
        page.saveAs:ClearFocus()
        page.done:Hide()
        page.fallback:Hide()
        page.finish:Show()
        page.Refresh()
    end

    page.Refresh()
    return page
end

-- Option pages: look, frames, everyday, quality of life

-- An option's item for the guide, with the same label, help, values and
-- rules, but read and written through the draft so it previews live and can
-- be undone. An option that needs a reload tells the draft instead of asking
-- for one. Returns the page and item to draw with, plus the original item,
-- or nil when the option doesn't exist.
function Steps.Proxy(scope, key, overrides)
    local page, item = DUI.InstallerPages.Find(scope, key)
    if not item then return nil end
    local p = { scope = page.scope, defaults = page.defaults }
    local it = {}
    for k, v in pairs(item) do it[k] = v end
    it.reload, it.onPick = nil, nil
    it.get = function() return DUI:Get(scope, key) end
    it.set = function(v) DUI.InstallerDraft.Set(scope, key, v, item.reload == true) end
    it.default = function() return DUI.DB.GetPath(page.defaults or {}, key) end
    for k, v in pairs(overrides or {}) do it[k] = v end
    return p, it, item
end

-- A row's help is as tall as its lines (at least two), measured on a hidden
-- text the way Parts.Stack:Text does.
Steps.NOTE_H = 30
local function noteHeight(page, text)
    local m = page.measure
    if not m then
        m = W.Font(page, W.BODY, SIZE.small, C.dim)
        m:SetWordWrap(true)
        m:SetAlpha(0)
        page.measure = m
    end
    m:SetWidth(page:GetWidth() - 2 * W.PAD)
    m:SetText(T(text))
    local h = m:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then return Steps.NOTE_H end
    return math.max(Steps.NOTE_H, math.ceil(h) + 4)
end

-- Options as rows (the options window's own), each with its help printed
-- below when the group asks for notes.
local function rows(page, group, refreshers)
    for _, r in ipairs(group.rows) do
        local p, it = Steps.Proxy(r[1], r[2], r.label and { label = r.label } or nil)
        if p and r.choice then
            -- An on/off option shown as a choice of two: { off's name, on's }.
            local get, set, default = it.get, it.set, it.default
            local function name(v) return v == true and "on" or "off" end
            it.type, it.order = "dropdown", { "off", "on" }
            it.values = { off = r.choice[1], on = r.choice[2] }
            it.get = function() return name(get()) end
            it.set = function(v) set(v == "on") end
            it.default = function() return name(default()) end
        end
        if p then
            local id = r[1] .. "." .. r[2]
            local row = W.Row(page, p, group, it)
            row.line:Hide()
            page.Add(row, W.ROW_HEIGHT, 0)
            row.Refresh()
            refreshers[#refreshers + 1] = row.Refresh
            page.rows[id] = row
            if group.notes and it.desc then
                local note = para(page, it.desc, SIZE.small, C.dim, noteHeight(page, it.desc))
                note.text:ClearAllPoints()
                note.text:SetPoint("TOPLEFT", note, "TOPLEFT", W.PAD, 0)
                note.text:SetPoint("BOTTOMRIGHT", note, "BOTTOMRIGHT", -W.PAD, 0)
                page.notes[id] = note.text
            end
        end
    end
end

-- One option as picture cards. Picking "custom" on an option with a colorKey
-- opens the color picker for that color, through the draft.
local function cards(page, group, width, refreshers)
    local spec = group.cards
    local p, it = Steps.Proxy(spec.scope, spec.key)
    if not p then return end
    local values, keys
    if it.choices then
        values, keys = it.choices()
    else
        values, keys = it.values, it.order
    end
    keys = keys or W.SortedKeys(values)
    if spec.only then
        local there = {}
        for _, k in ipairs(keys) do there[k] = true end
        keys = {}
        for _, k in ipairs(spec.only) do
            if there[k] then keys[#keys + 1] = k end
        end
    end
    if spec.max and #keys > spec.max then
        local first = {}
        for i = 1, spec.max do first[i] = keys[i] end
        keys = first
    end
    local picker = Cards.Picker(page, {
        keys = keys, width = width, cols = spec.cols, height = spec.height,
        label = function(k) return T(values[k]) end,
        get = it.get,
        set = function(k)
            -- Keys that follow this one ("global"), so a pick here applies to all.
            for _, key in ipairs(spec.follow or {}) do
                local v = DUI:Get(spec.scope, key)
                if v ~= nil and v ~= "global" then DUI.InstallerDraft.Set(spec.scope, key, "global") end
            end
            it.set(k)
            if k == "custom" and spec.colorKey then
                W.PickCustom(DUI:Get(spec.scope, spec.colorKey), function(rgb)
                    DUI.InstallerDraft.Set(spec.scope, spec.colorKey, rgb)
                end)
            end
        end,
        draw = spec.draw and Cards.Draw[spec.draw] or nil,
    })
    -- Each card's tooltip is the option's own help, as in the options window.
    for _, k in ipairs(keys) do picker.cards[k].tooltip = { T(values[k]), T(it.desc) } end
    page.Add(picker, picker.height, 12)
    refreshers[#refreshers + 1] = picker.Refresh
    page.pickers[spec.scope .. "." .. spec.key] = picker
    if spec.more then rows(page, { rows = { { spec.scope, spec.key, label = spec.more } } }, refreshers) end
end

-- A presets group: one card per preset, setting each of its values through
-- the draft. The card whose settings all match is shown as picked.
local function presets(page, group, width, refreshers)
    local P = DUI.InstallerPages
    local keys, by = {}, {}
    for _, p in ipairs(group.presets) do keys[#keys + 1] = p.id; by[p.id] = p end
    local picker = Cards.Picker(page, {
        keys = keys, width = width, cols = group.cols or 3, height = group.height or 84,
        label = function(k) return T(by[k].label) end,
        sub = (group.presets[1].sub ~= nil) and function(k) return T(by[k].sub or "") end or nil,
        get = function() local p = P.PresetOn(group) return p and p.id end,
        set = function(k)
            for _, s in ipairs(by[k].set) do
                if P.Find(s[1], s[2]) then DUI.InstallerDraft.Set(s[1], s[2], s[3]) end
            end
        end,
        draw = group.draw and Cards.Draw[group.draw] or nil,
    })
    page.Add(picker, picker.height, 12)
    refreshers[#refreshers + 1] = picker.Refresh
    page.pickers[group.label] = picker
end

-- One portrait choice (the portrait itself, or another of its settings given
-- by the group's key) for every frame that has one.
local function portraits(page, group, width, refreshers)
    local P = DUI.InstallerPages
    local name = P.PortraitKey(group)
    local _, item = P.Find("UnitFrames", "player." .. name)
    if not item then return end
    local picker = Cards.Picker(page, {
        keys = item.order, width = width, cols = group.cols or 4, height = group.height or 44,
        label = function(k) return T(item.values[k]) end,
        get = function() return DUI:Get("UnitFrames", "player." .. name) end,
        set = function(k)
            for _, u in ipairs(P.PORTRAIT_UNITS) do
                local key = u .. "." .. name
                if DUI:Get("UnitFrames", key) ~= nil then DUI.InstallerDraft.Set("UnitFrames", key, k) end
            end
        end,
        draw = group.draw and Cards.Draw[group.draw] or nil,
    })
    if group.draw then
        for _, k in ipairs(item.order) do picker.cards[k].tooltip = { T(item.values[k]), T(item.desc) } end
    end
    page.Add(picker, picker.height, 12)
    refreshers[#refreshers + 1] = picker.Refresh
    page.pickers[group.portraits == true and "portraits" or name] = picker
end

-- Your frame and a target, drawn by the unit frames module on a panel pinned
-- above the page (InstallerUI.SetPage puts it on the window so it stays in
-- view while the options below scroll), redrawn on every pick.
Steps.SAMPLES_H = 108
local function samples(page, width, refreshers)
    local mod = DUI:GetModule("UnitFrames")
    if not (mod and mod.Samples) then return end
    local stage = CreateFrame("Frame", nil, page)
    stage.bg = W.Round(stage, "BACKGROUND")
    stage.bg:SetAllPoints(stage)
    W.Tint(stage.bg, C.card)
    stage:SetSize(width, Steps.SAMPLES_H)
    stage:Hide()
    page.pinned = stage
    local box = mod.Samples(mod, stage)
    box:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, 0)
    box:SetSize(width, Steps.SAMPLES_H)
    box.Refresh()
    refreshers[#refreshers + 1] = box.Refresh
    page.samples = box
end

-- A page of groups (InstallerPages.TOUR): each group's heading, then its
-- samples, picture cards, portrait choice or rows. Groups whose module isn't
-- loaded are left out.
builders.groups = function(parent, width, def)
    local P = DUI.InstallerPages
    local page = stack(parent, width)
    page.rows, page.pickers, page.notes = {}, {}, {}
    local refreshers = {}
    for _, g in ipairs(def.groups) do
        if P.GroupAvailable(g) then
            if g.label and g.label ~= "" then heading(page, g.label) end
            if g.samples then samples(page, width, refreshers) end
            if g.cards then cards(page, g, width, refreshers) end
            if g.presets then presets(page, g, width, refreshers) end
            if g.portraits then portraits(page, g, width, refreshers) end
            if g.rows then rows(page, g, refreshers) end
        end
    end
    function page.Refresh()
        for _, fn in ipairs(refreshers) do fn() end
    end
    -- A setting changed while the page shows (a switch flipped, the accent
    -- repainting the cards), so refresh everything.
    DUI.On("SettingChanged", function()
        if page:IsShown() then page.Refresh() end
    end)
    return page
end

-- A bundle's yes or no as two cards (like the role page), with a line under
-- them when the addon its settings need isn't loaded.
builders.bundle = function(parent, width, def)
    local I = DUI.Installer
    local b = def.bundle
    local page = stack(parent, width)
    local picker = Cards.Picker(page, {
        keys = { "yes", "no" }, width = width, cols = 2, height = 84,
        label = function(k) return T(b[k][1]) end,
        sub = function(k) return T(b[k][2]) end,
        get = function() return I.Bundle(def) end,
        set = function(k) I.PickBundle(def, k) end,
    })
    page.Add(picker, picker.height, 14)
    page.picker = picker
    if b.needsAddon and not DUI.InstallerPages.AddonOn(b.needsAddon) then
        page.hint = para(page, b.hint, SIZE.small, C.dim)
    end
    function page.Refresh() picker.Refresh() end
    return page
end

-- What's included, and Your role

-- Every module as a tile with its switch, two per row, with any clash with
-- another addon above them. Changes here apply at the reload.
builders.modules = function(parent, width)
    local I, P = DUI.Installer, DUI.InstallerPages
    local page = stack(parent, width)
    page.tiles, page.clashes = {}, {}
    for _, c in ipairs(P.Clashes()) do
        local card = Cards.Clash(page, c, width,
            function() return I.flow and I.flow.clashes[c.addon] or "ours" end,
            function(v) I.PickClash(c, v) end)
        page.Add(card, Cards.CLASH_H, 10)
        page.clashes[c.addon] = card
    end
    -- With Questie on, pick which quest tracker to use (Quests' Choice.lua asks
    -- the same outside the guide). Both addons stay on.
    local quests = DUI:GetModule("Quests")
    local choice = quests and quests.enabled and quests.ns and quests.ns.Choice
    if choice and quests.ns.Bridge.Loaded() then
        local card = Cards.Clash(page, { label = "Questie", what = "quest tracker" }, width,
            function() return DUI:Get("Quests", "tracker") == false and "theirs" or "ours" end,
            function(v) choice.Pick(v == "theirs" and "questie" or "ours") end)
        page.Add(card, Cards.CLASH_H, 10)
        page.clashes.Questie = card
    end
    local cols = 2
    local tw = (width - Cards.GAP) / cols
    local grid = CreateFrame("Frame", nil, page)
    for i, mod in ipairs(P.MODULES) do
        local tile
        tile = Cards.Tile(grid, mod, tw,
            function() return I.flow ~= nil and I.flow.modules[mod.addon] == true end,
            function(v)
                I.SetModule(mod, v)
                tile.Refresh()
            end,
            P.AddonInstalled(mod.addon))
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        tile:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (tw + Cards.GAP), -row * (Cards.TILE_H + Cards.GAP))
        page.tiles[mod.addon] = tile
    end
    local rowsOf = math.ceil(#P.MODULES / cols)
    local h = rowsOf * Cards.TILE_H + (rowsOf - 1) * Cards.GAP
    grid:SetHeight(h)
    page.Add(grid, h, 12)
    para(page, L["Switching a part on or off applies when you reload, at the end."], SIZE.small, C.faint)
    function page.Refresh()
        for _, t in pairs(page.tiles) do t.Refresh() end
        for _, c in pairs(page.clashes) do c.Refresh() end
    end
    return page
end

-- The layouts as cards, each with a drawing of where frames sit, and with
-- dual spec a row per talent set. "Recommended for you" only when the game
-- reports a role, "In use" on the character's current profile.
builders.role = function(parent, width)
    local I = DUI.Installer
    local page = stack(parent, width)
    page.pickers = {}
    local keys = I.RoleChoices()
    local slots = I.Slots()
    for _, slot in ipairs(slots) do
        if #slots > 1 then heading(page, I.SlotLabel(slot)) end
        local picker = Cards.Picker(page, {
            keys = keys, width = width, cols = math.min(#keys, 3), height = #slots > 1 and 130 or 170,
            label = I.RoleCardLabel,
            sub = I.RoleSub,
            get = function() return I.flow and I.flow.roles[slot] end,
            set = function(k) I.PickRole(slot, k) end,
            draw = function(card, k, w, h) Cards.Draw.role(card, I.RoleShape(k), w, h) end,
            tag = I.RoleTag,
        })
        page.Add(picker, picker.height, 14)
        page.pickers[slot] = picker
    end
    local hint = I.HealHint()
    if hint then page.hint = para(page, hint, SIZE.small, C.dim) end
    function page.Refresh()
        for _, p in pairs(page.pickers) do p.Refresh() end
    end
    return page
end
