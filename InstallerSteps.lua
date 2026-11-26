-- What's on each page of the setup guide. Each builder makes a page frame,
-- laid out top to bottom at the width the window gives it, with a Refresh()
-- the guide calls whenever the page shows. Welcome and finish come first,
-- then the option pages (look, frames, everyday, quality of life), then the
-- modules and role pages.

local _, DUI = ...
local W = DUI.Widgets
local Style = DUI.Style
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
-- A plugin's page may hold its own content instead of settings.
local function ownContent(def)
    return def.text ~= nil or def.image ~= nil or def.buttons ~= nil or def.build ~= nil
end

function Steps.Has(def)
    return builders[def.id] ~= nil or ((def.groups ~= nil or ownContent(def)) and builders.groups ~= nil)
end

-- Builds a page by id, hidden until the window shows it.
function Steps.Build(id, parent, width)
    return Steps.BuildDef(DUI.InstallerPages.Get(id) or { id = id }, parent, width)
end

-- Builds a page from its definition (plugins' own guides have no id in the tour).
function Steps.BuildDef(def, parent, width)
    local make = builders[def.id] or builders.groups
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
    f.text = W.Font(f, W.TITLE, SIZE.head, C.text)
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

-- The opening: the sunrise, a greeting, "How do you play?" and a row of
-- equal cards: the three ready-made setups and Make it mine, with "Keep my
-- setup" first for a set-up character (or "Use a setup I have" when the
-- account has other profiles) and a card per profile pack after Make it mine.
-- A click only picks a card; the big button under them starts it. The page
-- owns the whole window (UI.SetPage's bare), so its spots are the window's.
-- Built once per setup shape (Installer.lua's key for it) and reused; the
-- picks live on the running flow (Installer.flow), set by Reset.
Steps.SHOW = {
    plaque = 186, title = 228, ask = 272, cards = 300, left = 24, gap = 12, cardH = 200,
    acts = 516, hint = 530, line = 573, goW = 300, goH = 48, menuW = 170, menuH = 32, menuGap = 14,
    -- By how many cards there are: width, picture height, title and line sizes.
    sizes = { [4] = { 204, 104, SIZE.head, SIZE.small }, [5] = { 161, 82, 14, 11 }, [6] = { 132, 66, 14, 11, true } },
    most = 6,
    -- The opening's pieces rise in after the sunrise (seconds).
    at = 1.2, step = 0.1, cardsAt = 1.45, hintAt = 1.9, lift = 10,
}

-- The cards the opening shows, in order: { key, title, line, state }.
local function openingCards()
    local I, P = DUI.Installer, DUI.Profiles
    local flow = I.flow
    local list = {}
    local showcase = flow.mode == "showcase"
    if showcase or #I.ExistingProfiles() > 0 then
        local name = DUI.DB.ActiveName()
        list[#list + 1] = { key = "keep", title = showcase and L["Keep my setup"] or L["Use a setup I have"],
            line = showcase and L["Stay on the profile you have now, as it is."]
                or L["Put this character on a profile you already have, as it is."],
            state = { role = I.RoleShape(showcase and name or (I.ExistingProfiles()[1] or name)), fight = true } }
    end
    list[#list + 1] = { key = "DPS/Tank", title = L["Damage / Tank"], line = L["Frames by your character, party down the side."],
        state = { role = "DPS/Tank", fight = true } }
    list[#list + 1] = { key = "Healer", title = L["Healer"], line = L["Party and raid tiles front and center for click-healing."],
        state = { role = "Healer", fight = true } }
    list[#list + 1] = { key = "Immersive Preset", title = L["Immersive"],
        line = L["Everything fades until you need it. The world comes first."],
        state = { role = "Immersive Preset", fight = false } }
    list[#list + 1] = { key = "mine", title = L["Make it mine"], line = L["Pick your own look, one easy choice at a time."],
        state = { role = "blueprint" } }
    local packs = {}
    for _, id in ipairs(P.PACK_ORDER) do
        local entries = P.PackProfiles(P.PACKS[id])
        if #entries > 0 then packs[#packs + 1] = { pack = P.PACKS[id], entries = entries } end
    end
    if #list + #packs > Steps.SHOW.most then
        list[#list + 1] = { key = "packs", title = L["Profile packs"],
            line = L["Ready-made setups from other authors."], state = { role = "DPS/Tank", fight = true }, packs = packs }
    else
        for _, p in ipairs(packs) do
            local by = p.pack.author and string.format(L["By %s."], p.pack.author)
            list[#list + 1] = { key = "pack:" .. p.pack.id, title = p.pack.label,
                line = by and p.pack.desc and (by .. " " .. p.pack.desc) or by or p.pack.desc or "",
                state = { role = I.RoleShape(p.entries[1].name), fight = true }, packs = { p }, pack = p.pack }
        end
    end
    return list
end

builders.welcome = function(parent)
    local I = DUI.Installer
    local Chrome, Screen, Feel, M = DUI.InstallerChrome, DUI.InstallerScreen, DUI.Win.Feel, DUI.Motion
    local S = Steps.SHOW
    local UI = DUI.InstallerUI
    local page = CreateFrame("Frame", nil, parent)
    page:SetSize(UI.SHOW_W, UI.SHOW_H)
    local showcase = I.flow.mode == "showcase"

    -- The plaque sits on the banner's lower edge, so it goes above the banner.
    page.plaque = Chrome.Plaque(page)
    page.plaque:SetPoint("TOP", page, "TOP", 0, -S.plaque)
    Chrome.OverBanner(page.plaque)
    page.plaque.Set(Chrome.Spaced(L["First light"]))
    page.title = Chrome.Title(page)
    page.title:SetPoint("TOP", page, "TOP", 0, -S.title)
    page.ask = W.Font(page, W.BODY, SIZE.small, Style.INK.LABEL, "CENTER")
    page.ask:SetPoint("TOP", page, "TOP", 0, -S.ask)
    page.ask:SetText(Chrome.Spaced(L["How do you play?"]))

    local defs = openingCards()
    local size = S.sizes[math.max(4, math.min(#defs, 6))]
    local cw, ph = size[1], size[2]
    page.cards = {}
    page.packs = {}
    page.defs = {}
    for i, d in ipairs(defs) do
        local c = Cards.Show(page, cw, S.cardH, ph, { titleSize = size[3], lineSize = size[4], noLine = size[5] })
        c.key = d.key
        c:SetPoint("TOPLEFT", page, "TOPLEFT", S.left + (i - 1) * (cw + S.gap), -S.cards)
        c.title:SetText(d.title)
        c.line:SetText(d.line)
        if size[5] then c.tooltip = { d.title, d.line } end
        local screen = Screen.New(c.picture, cw - 2 * (1 + Cards.SHOW_INSET))
        screen:SetPoint("CENTER", c.picture, "CENTER", 0, 0)
        screen.Set(d.state, true)
        c.screen = screen
        c:SetScript("OnClick", function() page.Pick(d.key, true) end)
        if d.pack then page.packs[d.pack.id] = c end
        page.cards[i] = c
        page.defs[d.key] = d
    end

    page.hint = W.Font(page, W.BODY, SIZE.small, Style.INK.LABEL, "CENTER")
    page.hint:SetPoint("TOP", page, "TOP", 0, -S.hint)
    page.hint:SetText(L["Pick one to start. Everything can be changed later."])
    page.go = W.HeroButton(page, L["Play now"], S.goH)
    page.go:SetWidth(S.goW)
    page.go.SetLabel(L["Play now"])
    page.go:Hide()
    page.goLine = W.Font(page, W.BODY, SIZE.small, Style.INK.LABEL, "CENTER")
    page.goLine:SetPoint("TOP", page, "TOP", 0, -S.line)
    page.goLine:Hide()
    page.profile = W.MenuButton(page, "", S.menuH)
    page.profile:SetWidth(S.menuW)
    page.profile:Hide()

    -- The profiles the menu button offers for the picked card: { names, label(name) }.
    local function menuFor(key)
        local d = page.defs[key]
        if key == "keep" then
            local names = showcase and DUI.Profiles.Names() or I.ExistingProfiles()
            -- A character on the stand-in (nothing saved yet) still sees its profile's name.
            if #names == 0 then names = { DUI.DB.ActiveName() } end
            return names, function(n) return n end
        elseif d and d.packs then
            local names, labels = {}, {}
            for _, p in ipairs(d.packs) do
                for _, e in ipairs(p.entries) do
                    names[#names + 1] = e.name
                    labels[e.name] = key == "packs" and string.format(L["%s, by %s"], e.name, p.pack.author or p.pack.label)
                        or e.name
                end
            end
            return names, function(n) return labels[n] or n end
        end
    end

    local function fitWidth(b)
        local text = b.text:GetText()
        b.SetLabel(text, S.menuW)
        b:SetWidth(S.menuW)
    end

    page.profile:SetScript("OnClick", function(b)
        local names, label = menuFor(page.picked)
        if not names then return end
        local values = {}
        for _, n in ipairs(names) do values[n] = label(n) end
        W.OpenMenu(b, names, values, I.flow and I.flow.profile, function(v)
            if I.flow then I.flow.profile = v end
            b.SetLabel(label(v), S.menuW)
            fitWidth(b)
        end, S.menuW)
    end)

    -- The button row for the picked card: its words, its line and, for a
    -- profile pick, the menu beside it (the pair centered).
    local function acts(animate)
        local key = page.picked
        page.hint:SetShown(key == nil)
        if not key then
            page.go:Hide(); page.goLine:Hide(); page.profile:Hide()
            return
        end
        local d = page.defs[key]
        local words, line
        if key == "mine" then
            words, line = L["Let's go"], L["The guide walks you through it, one easy choice at a time. About 2 minutes."]
        elseif key == "keep" then
            words = showcase and L["Keep it"] or L["Use this"]
            line = L["Nothing changes. Pick another profile from the list to move this character onto it."]
        elseif d and d.pack then
            words = L["Play now"]
            line = d.pack.author and string.format(L["By %s. One reload and you're in."], d.pack.author)
                or L["One reload and you're in."]
        else
            words, line = L["Play now"], L["One reload and you're in."]
        end
        -- The keep card always names its profile; a pack's list only when it has a choice.
        local names, label = menuFor(key)
        local menu = names ~= nil and (key == "keep" or #names > 1)
        if names and I.flow then
            local keep = false
            for _, n in ipairs(names) do if n == I.flow.profile then keep = true end end
            if not keep then
                I.flow.profile = names[1]
                for _, n in ipairs(names) do if n == DUI.DB.ActiveName() then I.flow.profile = n end end
            end
            page.profile.SetLabel(label(I.flow.profile), S.menuW)
            fitWidth(page.profile)
        end
        local first = not page.go:IsShown()
        page.go.SetLabel(words)
        page.go:SetWidth(S.goW)
        page.go:ClearAllPoints()
        page.profile:ClearAllPoints()
        if menu then
            local total = S.menuW + S.menuGap + S.goW
            local left = (UI.SHOW_W - total) / 2
            page.profile:SetPoint("TOPLEFT", page, "TOPLEFT", left, -(S.acts + (S.goH - S.menuH) / 2))
            page.go:SetPoint("TOPLEFT", page, "TOPLEFT", left + S.menuW + S.menuGap, -S.acts)
        else
            page.go:SetPoint("TOP", page, "TOP", 0, -S.acts)
        end
        page.goLine:SetText(line)
        local wasMenu = page.profile:IsShown()
        page.profile:SetShown(menu)
        page.go:Show()
        page.goLine:Show()
        if animate and first then
            Feel.Piece(page.go, 0, M.SLOW, S.lift)
            Feel.Piece(page.goLine, S.step, M.SLOW, S.lift)
            if menu then Feel.Piece(page.profile, 0, M.SLOW, S.lift) end
        elseif animate then
            M.Fade(page.goLine, 0, 1, M.FAST)
            if menu and not wasMenu then Feel.Piece(page.profile, 0, M.NORMAL, 0) end
        end
    end

    -- Picks a card (nothing is written: the button starts it).
    function page.Pick(key, animate)
        local was = page.picked
        page.picked = key
        for _, c in ipairs(page.cards) do
            c.SetPicked(c.key == key, animate and key ~= was)
            c.SetDim(key ~= nil and c.key ~= key, animate)
        end
        if animate and key ~= was and DUI.Sound then DUI.Sound.Play("toggle") end
        acts(animate)
    end

    page.go:SetScript("OnClick", function()
        local key, flow = page.picked, I.flow
        if not (key and flow) then return end
        if key == "mine" then
            I.Start("tour")
        elseif key == "keep" then
            I.Start(showcase and "keep" or "existing", flow.profile)
        elseif page.defs[key] and page.defs[key].packs then
            I.Start("quick", flow.profile)
        else
            I.Start("quick", key)
        end
    end)

    function page.Refresh()
        local Installer = DUI.Installer
        local r, g, b = Style.Accent()
        page.title.Set(Installer.GreetingText({ r, g, b }))
        page.title.Paint()
        page.plaque.Paint()
        local rec = Installer.Recommended()
        for _, c in ipairs(page.cards) do
            if c.key == "keep" and showcase then
                c.SetTag(L["In use"])
            elseif c.key == rec then
                c.SetTag(L["Suggested for you"])
            else
                c.SetTag(nil)
            end
        end
    end

    -- A new run starts with nothing picked, or with "Keep my setup" for a set-up character.
    function page.Reset()
        if I.flow then I.flow.profile = nil end
        page.go:Hide()
        page.Pick(showcase and "keep" or nil, false)
    end

    -- After the sunrise: the plaque, the title, the question, the cards one by
    -- one, then the hint (or the button, when something is picked already).
    function page.Play()
        local slow = M.SLOW
        Feel.Piece(page.plaque, S.at, slow, S.lift / 2)
        Feel.Piece(page.title, S.at + S.step, slow, S.lift)
        Feel.Piece(page.ask, S.at + 2 * S.step, slow, S.lift / 2)
        for i, c in ipairs(page.cards) do Feel.Piece(c, S.cardsAt + (i - 1) * S.step, slow, S.lift) end
        local last = S.cardsAt + #page.cards * S.step
        if page.picked then
            if page.profile:IsShown() then Feel.Piece(page.profile, last, slow, S.lift) end
            Feel.Piece(page.go, last, slow, S.lift)
            Feel.Piece(page.goLine, last + S.step, slow, S.lift)
        else
            Feel.Piece(page.hint, S.hintAt, slow, S.lift / 2)
        end
    end

    page.Reset()
    page.Refresh()
    return page
end

-- Finish

-- The Finish page: arriving here saved everything (Installer.ToFinish), so it
-- shows the after: the sunrise, "All set", your screen with your picks, a tag
-- per pick that was made, and one button that reloads into it. When saving
-- couldn't run it says why, its button tries again and Back returns to the
-- last question. The page owns the whole window, so its spots are the window's.
Steps.FINISH = {
    plaque = 166, title = 208, screen = { x = 285, y = 258, w = 330, h = 186 }, tags = 462, tagSide = 60, tagGap = 6,
    tagRowGap = 6, go = 508, goW = 300, goH = 48, line = 565,
    tagPad = 10, tagH = 24, tagSlant = 7, tagWordGap = 8,
    -- The pieces rise in after the sunrise (seconds).
    at = 1.2, step = 0.1, screenAt = 1.45, tagsAt = 1.5, tagStep = 0.08, goAt = 2.1, lineAt = 2.2, lift = 10,
    -- The game's list of account layouts full: the two lines saying so, the list
    -- (a section, then rows 40 apart), the hint under it and the button lower.
    full = { say = 250, sayGap = 18, list = 290, x = 230, w = 440, h = 224, rowGap = 2, edge = 3,
        hintGap = 6, go = 548, sayW = 640 },
}

-- A tag: a small spaced label and the pick after it, in a slanted pill.
local function finishTag(parent)
    local F = Steps.FINISH
    local t = W.Tag(parent)
    t:SetHeight(F.tagH)
    t.text:Hide()
    Style.Slant(t, "both", F.tagSlant, nil, "left")
    t.label = W.Font(t, W.BODY, SIZE.tiny, Style.INK.LABEL)
    t.label:SetPoint("LEFT", t, "LEFT", F.tagPad, 0)
    t.value = W.Font(t, W.BODY, SIZE.small, Style.INK.TEXT)
    t.value:SetPoint("LEFT", t.label, "RIGHT", F.tagWordGap, 0)
    function t.Say(label, value)
        t.label:SetText(DUI.InstallerChrome.Spaced(label or ""))
        t.value:SetText(value or "")
        local a, b = t.label:GetStringWidth(), t.value:GetStringWidth()
        a = type(a) == "number" and a or 40
        b = type(b) == "number" and b or 60
        t:SetWidth(math.ceil(a + F.tagWordGap + b + 2 * F.tagPad))
    end
    return t
end

builders.finish = function(parent)
    local I, M, Feel = DUI.Installer, DUI.Motion, DUI.Win.Feel
    local Chrome, UI, F = DUI.InstallerChrome, DUI.InstallerUI, Steps.FINISH
    local page = CreateFrame("Frame", nil, parent)
    page:SetSize(UI.SHOW_W, UI.SHOW_H)

    page.plaque = Chrome.Plaque(page)
    page.plaque:SetPoint("TOP", page, "TOP", 0, -F.plaque)
    Chrome.OverBanner(page.plaque)
    page.title = Chrome.Title(page)
    page.title:SetPoint("TOP", page, "TOP", 0, -F.title)

    -- Your screen, in a frame's edge with the picked card's two-color glow.
    local S = F.screen
    page.holder = CreateFrame("Frame", nil, page)
    page.holder:SetPoint("TOPLEFT", page, "TOPLEFT", S.x, -S.y)
    page.holder:SetSize(S.w, S.h)
    for i, spec in ipairs({ { 5, Style.BORDER }, { 4, Style.BAND }, { 1, Style.BORDER } }) do
        local e = page.holder:CreateTexture(nil, "BACKGROUND", nil, i - 8)
        e:SetTexture("Interface\\Buttons\\WHITE8X8")
        e:SetPoint("TOPLEFT", page.holder, "TOPLEFT", -spec[1], spec[1])
        e:SetPoint("BOTTOMRIGHT", page.holder, "BOTTOMRIGHT", spec[1], -spec[1])
        e:SetVertexColor(spec[2][1], spec[2][2], spec[2][3], 1)
    end
    page.screen = DUI.InstallerScreen.New(page.holder, S.w)
    page.screen:SetPoint("TOPLEFT", page.holder, "TOPLEFT", 0, 0)

    page.tags = {}
    page.tagRow = CreateFrame("Frame", nil, page)
    page.tagRow:SetPoint("TOPLEFT", page, "TOPLEFT", F.tagSide, -F.tags)
    page.tagRow:SetSize(UI.SHOW_W - 2 * F.tagSide, F.tagH)

    page.go = W.HeroButton(page, L["Reload and play"], F.goH)
    page.go:SetWidth(F.goW)
    page.go:SetPoint("TOP", page, "TOP", 0, -F.go)
    page.line = W.Font(page, W.BODY, SIZE.small, Style.INK.LABEL, "CENTER")
    page.line:SetPoint("TOP", page, "TOP", 0, -F.line)
    page.line:SetWidth(UI.SHOW_W - 2 * F.tagSide)
    page.back = W.Button(page, BACK or L["Back"], DUI.InstallerDuel.FOOT.backH)
    page.back:SetWidth(DUI.InstallerDuel.FOOT.backW)
    local row = UI.SHOW_H - DUI.InstallerDuel.FOOT.bottom - DUI.InstallerDuel.FOOT.height / 2
    page.back:SetPoint("LEFT", page, "TOPLEFT", DUI.InstallerDuel.FOOT.side, -row)
    page.back:SetScript("OnClick", function() I.Back() end)

    -- When the game has no room for another account layout: the list of them,
    -- each but the one in use with an X, in place of your screen.
    local FL = F.full
    local Parts = DUI.Win.Parts
    page.say = W.Font(page, W.BODY, SIZE.body, Style.INK.WARN, "CENTER")
    page.say:SetPoint("TOP", page, "TOP", 0, -FL.say)
    page.say:SetWidth(FL.sayW)
    page.say2 = W.Font(page, W.BODY, SIZE.body, Style.INK.TEXT, "CENTER")
    page.say2:SetPoint("TOP", page, "TOP", 0, -(FL.say + FL.sayGap))
    page.say2:SetWidth(FL.sayW)
    page.full = CreateFrame("Frame", nil, page)
    page.full:SetPoint("TOPLEFT", page, "TOPLEFT", FL.x, -FL.list)
    page.full:SetSize(FL.w, FL.h)
    page.layouts = Parts.Stack(page.full, { top = 0, bottom = 0, side = 0 })
    page.hint = W.Font(page.full, W.BODY, SIZE.small, Style.INK.LABEL, "LEFT")
    page.hint:SetPoint("TOPLEFT", page.full, "BOTTOMLEFT", 0, -FL.hintGap)
    page.hint:SetText(L["A layout is only deleted when you click its X twice."])
    page.layoutRows = {}
    for _, piece in ipairs({ page.say, page.say2, page.full }) do piece:Hide() end

    local function deleteLayout(index)
        local ok, why = DUI.EditMode.DeleteLayout(index)
        page.deleteWhy = not ok and why or nil
        page.Refresh()
    end

    -- A Stack line as a layout row. It has no icon: its edge becomes the accent
    -- mark on Daylight UI's leftovers, and the X sits at its end.
    local function dressRow(b, l)
        b.layoutName, b.leftover = l.name, l.leftover
        b.icon:SetTexture(nil)
        b.edge:SetSize(FL.edge, Parts.LINE)
        if l.leftover then
            local r, g, bl = Style.Accent()
            b.edge:SetVertexColor(r, g, bl, 1)
        end
        b.edge:SetShown(l.leftover == true)
        if not b.del then
            b.del = W.DeleteButton(b)
            b.del:SetPoint("RIGHT", b, "RIGHT", -8, 0)
            -- W.Confirm writes its "Click again" here, left of the X.
            b.del.text = W.Font(b, W.BODY, SIZE.small, Style.INK.WARN, "RIGHT")
            b.del.text:SetPoint("RIGHT", b.del, "LEFT", -8, 0)
        end
        b.del:SetShown(not l.active)
        b.del.text:SetShown(not l.active)
        W.Confirm(b.del, "", function() deleteLayout(l.index) end, L["Click again to delete"])
    end

    -- The list, and the two lines over it for where it stands. Returns
    -- whether there's room for the layout now.
    local function fillLayouts()
        local E = DUI.EditMode
        local list = E.AccountLayouts()
        local max = E.MaxLayouts() or #list
        local full = #list >= max
        local s = page.layouts
        s:Begin()
        s:Section(L["Account layouts"], { value = Parts.Hex(full and Style.INK.WARN or Style.INK.GOOD)
            .. string.format("%d / %d", #list, max) .. "|r" })
        page.layoutRows = {}
        for i, l in ipairs(list) do
            if i > 1 then s:Gap(FL.rowGap) end
            local sub, subColor
            if l.active then
                sub = L["In use on this character"]
            elseif l.leftover then
                sub, subColor = L["Daylight UI's, no profile uses it"], { Style.Accent() }
            elseif l.profile then
                sub = string.format(L["Daylight UI's, profile %s"], l.profile)
            else
                sub = L["Your own"]
            end
            local b = s:Line({ text = l.name, color = Style.INK.TEXT, sub = sub, subColor = subColor, id = l.name })
            W.Stripe(b, i % 2 == 1)
            dressRow(b, l)
            page.layoutRows[#page.layoutRows + 1] = b
        end
        s:End()
        if page.deleteWhy then
            page.say:SetText(string.format(L["Couldn't delete it: %s."], page.deleteWhy))
            W.TextColor(page.say, Style.INK.WARN)
        elseif full then
            page.say:SetText(string.format(L["The game allows %d account layouts, and all %d are taken."], max, max))
            W.TextColor(page.say, Style.INK.WARN)
        else
            page.say:SetText(L["There's room for the layout now."])
            W.TextColor(page.say, Style.INK.GOOD)
        end
        page.say2:SetText(full and L["Delete one here, then press Try again."] or L["Press Try again to finish."])
    end

    -- The tags, centered in rows that wrap inside the page's sides.
    local function layTags(list)
        for i, spec in ipairs(list) do
            local t = page.tags[i]
            if not t then t = finishTag(page.tagRow); page.tags[i] = t end
            t.Say(spec.label, spec.value)
            t:Show()
        end
        for i = #list + 1, #page.tags do page.tags[i]:Hide() end
        local room = UI.SHOW_W - 2 * F.tagSide
        local rows, cur, w = {}, {}, 0
        for i = 1, #list do
            local t = page.tags[i]
            local tw = t:GetWidth()
            if #cur > 0 and w + F.tagGap + tw > room then
                rows[#rows + 1] = { list = cur, w = w }
                cur, w = {}, 0
            end
            w = w + (#cur > 0 and F.tagGap or 0) + tw
            cur[#cur + 1] = t
        end
        if #cur > 0 then rows[#rows + 1] = { list = cur, w = w } end
        for r, rowSpec in ipairs(rows) do
            local x = (room - rowSpec.w) / 2
            for _, t in ipairs(rowSpec.list) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", page.tagRow, "TOPLEFT", x, -(r - 1) * (F.tagH + F.tagRowGap))
                x = x + t:GetWidth() + F.tagGap
            end
        end
    end

    -- Where the secure reload button lies over the page's one button, once it has landed.
    local function reloadOver()
        local flow = I.flow
        if not (flow and flow.finished and flow.reload and page:IsVisible()) then return end
        if not UI.ShowReload(page.go) then page.fallback = true end
    end

    page.go:SetScript("OnClick", function()
        local flow = I.flow
        if not flow then return end
        if not flow.finished then
            page.deleteWhy = nil
            I.Finish()
            page.Refresh()
            if flow.finished then reloadOver() end
        elseif flow.reload then
            -- The secure button takes the click; this runs only when it couldn't show.
            I.ReloadPopup()
        else
            I.Done()
        end
    end)

    -- The words, button and tags for where Finish stands: saved and a reload
    -- to go, saved with nothing to reload, or couldn't save.
    function page.Refresh()
        local flow = I.flow
        if not flow then return end
        local r, g, b = Style.Accent()
        page.plaque.Paint()
        page.title.Paint()
        page.plaque.Set(Chrome.Spaced(L["All set"]))
        local name = UnitName("player") or ""
        local who = string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5), name)
        if flow.finished then
            page.title.Set(string.format(L["Your UI is ready, %s"], who))
            page.back:Hide()
            if flow.reload then
                page.go.SetLabel(L["Reload and play"])
                page.line:SetText(L["One reload puts everything in place."])
            else
                page.go.SetLabel(DONE or L["Done"])
                page.line:SetText(L["Everything is already in place."])
            end
            W.TextColor(page.line, Style.INK.LABEL)
        else
            UI.HideReload()
            page.title.Set(L["Almost there"])
            page.go.SetLabel(L["Try again"])
            page.line:SetText(flow.status or "")
            W.TextColor(page.line, Style.INK.WARN)
            page.back:Show()
        end
        -- No room for the layout: the list of layouts takes the screen's place.
        local full = flow.full == true and not flow.finished
        if full then fillLayouts() end
        for _, piece in ipairs({ page.say, page.say2, page.full }) do piece:SetShown(full) end
        for _, piece in ipairs({ page.holder, page.tagRow, page.line }) do piece:SetShown(not full) end
        page.go:ClearAllPoints()
        page.go:SetPoint("TOP", page, "TOP", 0, -(full and FL.go or F.go))
        page.go:SetWidth(F.goW)
        if flow.screen then page.screen.Set(flow.screen, true) end
        layTags(flow.tags or {})
    end

    -- After the sunrise: the plaque, the title, your screen, the tags one by
    -- one, the button, its line. The reload button goes over the button once
    -- it has landed.
    function page.Play()
        local slow = M.SLOW
        UI.HideReload()
        W.GlowAround(page.holder, true, { frame = page.holder, style = "breathe",
            lo = Style.GRADIENT_SHAPE[1], hi = Style.GRADIENT_SHAPE[2] })
        Feel.Piece(page.plaque, F.at, slow, F.lift / 2)
        Feel.Piece(page.title, F.at + F.step, slow, F.lift)
        Feel.Piece(page.holder, F.screenAt, slow, F.lift)
        for i, t in ipairs(page.tags) do
            if t:IsShown() then Feel.Piece(t, F.tagsAt + (i - 1) * F.tagStep, slow, F.lift / 2) end
        end
        Feel.Piece(page.go, F.goAt, slow, F.lift)
        Feel.Piece(page.line, F.lineAt, slow, F.lift / 2)
        if page.full:IsShown() then
            Feel.Piece(page.say, F.screenAt, slow, F.lift / 2)
            Feel.Piece(page.say2, F.screenAt, slow, F.lift / 2)
            Feel.Piece(page.full, F.screenAt + F.step, slow, F.lift)
        end
        if page.back:IsShown() then Feel.Piece(page.back, F.goAt, slow, 0) end
        local wait = M.On() and (F.goAt + slow) or 0
        C_Timer.After(wait, reloadOver)
    end
    page:HookScript("OnHide", function() W.GlowAround(page.holder, false) end)
    -- A font picked on the way reaches the tags' words a moment after they're
    -- laid out: lay them out again once it has.
    DUI.On("StyleChanged", function()
        if page:IsVisible() and I.flow then layTags(I.flow.tags or {}) end
    end)

    function page.Reset() page.fallback = nil end
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
            -- A key of another module comes as { module, key }.
            for _, key in ipairs(spec.along or {}) do
                if type(key) == "table" then
                    if DUI:GetModule(key[1]) then DUI.InstallerDraft.Set(key[1], key[2], k) end
                else
                    DUI.InstallerDraft.Set(spec.scope, key, k)
                end
            end
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

-- Two looks of one thing side by side, a card each (InstallerLooks.lua).
local function looks(page, group, width, refreshers)
    local Looks = DUI.InstallerLooks
    local kind = group.look
    local picker = Looks.Picker(page, kind, {
        width = width,
        get = function() return Looks.Current(kind) end,
        set = function(k) Looks.Apply(kind, k, DUI.InstallerDraft.Set) end,
    })
    page.Add(picker, picker.height, 12)
    refreshers[#refreshers + 1] = picker.Refresh
    page.pickers[kind] = picker
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

-- A plugin's own content, above any settings: a paragraph (text), a picture
-- (image, imageHeight, imageCoords), a row of buttons that act at once
-- (buttons = { { text, onClick, main, done } }) and anything it draws itself
-- (build(holder, width) returns the height it used; holder.Refresh, when set,
-- runs each time the page shows).
Steps.IMAGE_H = 140
Steps.BUTTON_H = 28
local function ownParts(page, def, width, refreshers)
    local who = def.plugin or L["an addon"]
    if type(def.text) == "string" and def.text ~= "" then
        local m = W.Font(page, W.BODY, SIZE.body, C.text)
        m:SetWordWrap(true)
        m:SetAlpha(0)
        m:SetWidth(width)
        m:SetText(T(def.text))
        local h = m:GetStringHeight()
        if type(h) ~= "number" or h <= 0 then h = 18 end
        page.text = para(page, def.text, SIZE.body, C.text, math.ceil(h) + 4)
    end
    if def.image ~= nil then
        local f = CreateFrame("Frame", nil, page)
        DUI.Style.Shell(f, { noBackground = true })
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints(f)
        f.tex:SetTexture(def.image)
        local c = def.imageCoords
        if type(c) == "table" and #c == 4 then f.tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
        local h = type(def.imageHeight) == "number" and def.imageHeight > 0 and def.imageHeight or Steps.IMAGE_H
        page.Add(f, h, 14)
        page.image = f
    end
    if type(def.buttons) == "table" and #def.buttons > 0 then
        local row = CreateFrame("Frame", nil, page)
        page.Add(row, Steps.BUTTON_H, 14)
        row.buttons = {}
        local left = row
        for i, spec in ipairs(def.buttons) do
            if type(spec) == "table" and type(spec.text) == "string" then
                local b = W.Button(row, T(spec.text), Steps.BUTTON_H)
                b.FitWidth(110)
                if left == row then
                    b:SetPoint("LEFT", row, "LEFT", 0, 0)
                else
                    b:SetPoint("LEFT", left, "RIGHT", 8, 0)
                end
                if spec.main then b.SetActive(true) end
                b:SetScript("OnClick", function()
                    if type(spec.onClick) ~= "function" then return end
                    local said
                    local ok = DUI.SafeCallAs(who, function() said = spec.onClick() end)
                    said = type(said) == "string" and said or spec.done
                    if ok and type(said) == "string" then
                        row.status:SetText(T(said))
                        DUI.Motion.Fade(row.status, 0, 1, DUI.Motion.FAST)
                    end
                end)
                row.buttons[i] = b
                left = b
            end
        end
        -- What the last click did, after the buttons ("Chat set up").
        row.status = W.Font(row, W.BODY, SIZE.small, C.text)
        DUI.Style.InkText(row.status, "GOOD")
        row.status:SetPoint("LEFT", left, left == row and "LEFT" or "RIGHT", 12, 0)
        page.buttons = row
    end
    if type(def.build) == "function" then
        local holder = CreateFrame("Frame", nil, page)
        holder:SetSize(width, 1)
        local h
        DUI.SafeCallAs(who, function() h = def.build(holder, width) end)
        if type(h) ~= "number" or h <= 0 then h = holder:GetHeight() end
        page.Add(holder, math.max(1, h), 14)
        if type(holder.Refresh) == "function" then
            refreshers[#refreshers + 1] = function() DUI.SafeCallAs(who, holder.Refresh) end
        end
        page.holder = holder
    end
end

-- A page of groups (InstallerPages.TOUR): each group's heading, then its
-- samples, picture cards, portrait choice or rows. Groups whose module isn't
-- loaded are left out.
builders.groups = function(parent, width, def)
    local P = DUI.InstallerPages
    local page = stack(parent, width)
    page.rows, page.pickers, page.notes = {}, {}, {}
    local refreshers = {}
    ownParts(page, def, width, refreshers)
    for _, g in ipairs(def.groups or {}) do
        if P.GroupAvailable(g) then
            if g.label and g.label ~= "" then heading(page, g.label) end
            if g.samples then samples(page, width, refreshers) end
            if g.cards then cards(page, g, width, refreshers) end
            if g.presets then presets(page, g, width, refreshers) end
            if g.portraits then portraits(page, g, width, refreshers) end
            if g.look then looks(page, g, width, refreshers) end
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

-- A question on the "this or that" page (InstallerDuel): its words, its
-- choices with their pictures, and what Next, Back, a pick and Finish now do.
-- q is an Installer.Questions() entry; step and total count the steps after
-- the opening.

-- The layout question's longer lines.
Steps.ROLE_LINES = {
    ["DPS/Tank"] = "Your frames by your character, your party down the side.",
    Healer = "Party and raid tiles front and center, made for click-healing.",
    ["Immersive Preset"] = "Everything fades until you need it. The world comes first.",
}

-- The small screen's state for a layout: the three in a fight, Immersive out of one.
local function layoutState(name)
    local shape = DUI.Installer.RoleShape(name)
    return { role = shape, fight = shape ~= "Immersive Preset", calm = "shown" }
end

-- A picture maker for the duel page: function(parent, width) -> frame.
local function screenPicture(state)
    return function(parent, width) return Cards.Picture.screen(parent, state, width) end
end

local function choicesFor(q)
    local I, P, Pic = DUI.Installer, DUI.InstallerPages, Cards.Picture
    local flow = I.flow
    local out = {}
    local role = flow and flow.roles[I.CurrentSlot()] or "DPS/Tank"
    local base = layoutState(role)
    local function add(key, name, line, picture, closed)
        local c = { key = key, name = name, line = line, picture = picture, closed = closed }
        if q.new and q.new[key] then c.tag = L["New"] end
        if flow and flow.start and flow.start[q.id] == key and q.id ~= "role" and not q.clash and not q.extra then
            c.tag = c.tag or L["Daylight's pick"]
        end
        -- Another addon doing a part's job: Daylight UI's own is the pick it suggests.
        if q.clash and key == "ours" then c.tag = L["Daylight's pick"] end
        out[#out + 1] = c
        return c
    end
    if q.role then
        for _, name in ipairs(I.RoleChoices()) do
            local line = Steps.ROLE_LINES[name] and L[Steps.ROLE_LINES[name]] or I.RoleSub(name)
            local c = add(name, name == "DPS/Tank" and L["Damage / Tank"] or name == "Immersive Preset" and L["Immersive"]
                or I.RoleCardLabel(name), line, screenPicture(layoutState(name)),
                function(parent) return Pic.screen(parent, layoutState(name), 56) end)
            c.tag = I.RoleTag(name) ~= L["Recommended for you"] and I.RoleTag(name) or nil
        end
    elseif q.clash then
        local c = q.clash
        local ours
        if c.module == "Nameplates" then
            ours = function(parent, w) return Pic.plate(parent, {}, w) end
        elseif c.module == "Bags" then
            ours = function(parent, w) return Pic.bags(parent, "categories", w) end
        elseif c.module == "ActionBars" then
            ours = screenPicture({ role = base.role, bars = "two", fight = true })
        else
            ours = function(parent, w) return Pic.addon(parent, L["Daylight UI"], w) end
        end
        if q.questie then
            -- Both stay on: only the tracker is one or the other.
            add("ours", L["Daylight UI"], L["Daylight UI's tracker. Questie keeps its map and quest data."], ours)
            add("theirs", c.label, L["Questie's own tracker. Both addons stay on."],
                function(parent, w) return Pic.addon(parent, c.label, w) end)
        else
            add("ours", L["Daylight UI"], string.format(L["%s is switched off for this character when you finish."], c.label), ours)
            add("theirs", c.label, string.format(L["Daylight UI leaves %s alone and skips their questions."], L[c.what]),
                function(parent, w) return Pic.addon(parent, c.label, w) end)
        end
    elseif q.extra then
        local name = q.extra.extra.label or q.extra.extra.addon
        local function pic(parent, w) return Pic.addon(parent, name, w) end
        add("yes", YES or L["Yes"], nil, pic)
        add("no", L["No, leave it"], nil, pic)
    elseif q.bundle then
        add("yes", L[q.bundle.yes[1]], L[q.bundle.yes[2]], function(parent, w) return Pic.quest(parent, "yes", w) end)
        add("no", L[q.bundle.no[1]], L[q.bundle.no[2]], function(parent, w) return Pic.quest(parent, "no", w) end)
    elseif q.option then
        local _, item = P.Find(q.option[1], q.option[2])
        local values = item and item.values
        if item and item.choices then values = item.choices() end
        for _, k in ipairs(q.only) do
            local label = q.labels and q.labels[k] or (type(values) == "table" and values[k]) or tostring(k)
            local line = q.subs and q.subs[k]
            local picture, closed
            if q.draw == "accent" then
                picture = function(parent, w) return Pic.accent(parent, k, w) end
                closed = function(parent) return Pic.accentBar(parent, k) end
            elseif q.draw == "font" then
                picture = function(parent, w) return Pic.font(parent, k, w) end
                closed = function(parent) return Pic.fontMini(parent, k) end
            elseif q.draw == "plate" then
                local opts = {}
                opts[q.plate] = k
                picture = function(parent, w) return Pic.plate(parent, opts, w) end
            elseif q.draw == "bags" then
                picture = function(parent, w) return Pic.bags(parent, k, w) end
            end
            local c = add(k, T(label), line and L[line] or nil, picture, closed)
            if q.draw == "font" then c.nameFont = Cards.FontFile(k) end
        end
    elseif q.presets then
        for _, p in ipairs(q.presets) do
            local picture
            if q.draw == "plate" then
                picture = function(parent, w) return Pic.plate(parent, { size = p.id }, w) end
            elseif q.screen then
                local state = { role = base.role, fight = base.fight, calm = "shown" }
                state[q.screen] = p.id
                if q.screen == "calm" then state.fight = false else state.fight = true end
                picture = screenPicture(state)
            end
            add(p.id, T(p.label), p.sub and T(p.sub) or nil, picture)
        end
    elseif q.look then
        local spec = DUI.InstallerLooks.KINDS[q.look]
        for _, k in ipairs(spec.keys) do
            local label = q.labels and q.labels[k] or k
            add(k, L[label], q.subs and q.subs[k] and L[q.subs[k]] or nil, nil)
        end
    end
    return out
end
Steps.Choices = choicesFor

-- A look drawn once across both columns (the looks' own preview box), its
-- own names and lines hidden (the question page draws those). Each look is
-- handed back to be placed on its column: the unit frames at the mock-up's
-- size, the crowd of names on the sky the plate pictures use.
Steps.SPAN = { portraitLook = { width = 278 }, tooltipStyle = { width = 210 }, plateClassIcon = { sky = 300 },
    spellCosts = { width = 240 } }
local function spanFor(q)
    local Looks = DUI.InstallerLooks
    return function(parent, width)
        local spec = Looks.KINDS[q.look]
        local how = Steps.SPAN[q.look] or {}
        local box
        DUI.SafeCall(function() box = spec.box(parent) end)
        if not box then return nil end
        if box.Refresh then box.Refresh(how.sky and 2 * (how.sky + 32) or width) end
        local spots = {}
        for _, k in ipairs(spec.keys) do
            local art = box.frames and box.frames[k] or (box.cards and box.cards[k] and box.cards[k].wrap)
            if art and how.width then
                local w = art:GetWidth()
                if type(w) == "number" and w > 0 then art:SetScale(how.width / w) end
            end
            if art and how.sky then
                local sky = Cards.Picture.Sky(box, how.sky)
                sky:SetFrameLevel(math.max(1, art:GetFrameLevel() - 1))
                art:ClearAllPoints()
                art:SetPoint("CENTER", sky, "CENTER", 0, 0)
                art = sky
            end
            spots[k] = art
            if box.names and box.names[k] then box.names[k]:Hide() end
            if box.lines and box.lines[k] then box.lines[k]:Hide() end
        end
        return box, spots
    end
end

function Steps.Question(q, step, total)
    local I = DUI.Installer
    local flow = I.flow
    local current = I.Answer(q)
    local out = {
        id = q.id .. ":" .. tostring(flow and I.RoleShape(flow.roles[I.CurrentSlot()]) or ""),
        part = q.part and T(q.part) or "", ask = q.ask and T(q.ask) or "", what = q.what and T(q.what) or "",
        first = step == 1, step = step, total = total,
        nextText = step >= total and L["Finish"] or (NEXT or L["Next"]),
        current = current, choices = choicesFor(q),
        pictureWidth = q.width,
        next = I.Next, back = I.Back,
        finish = function() I.SettleAll(); I.ToFinish() end,
    }
    if q.questie then
        out.ask = L["Which quest tracker do you want?"]
        out.what = L["Questie is on too, and has a quest tracker of its own."]
    elseif q.clash then
        out.ask = string.format(L["Who draws your %s?"], L[q.clash.what])
        out.what = string.format(L["%s is switched on too, and only one addon can draw %s."], q.clash.label, L[q.clash.what])
    elseif q.extra then
        local name = q.extra.extra.label or q.extra.extra.addon
        out.ask = string.format(L["Set up %s to match?"], name)
        out.what = string.format(L["This pack can set up %s to go with its profile."], name)
    end
    if q.look then out.span = spanFor(q) end
    if q.role then out.warn = I.SaveNoteWarning() end
    out.pick = function(key)
        I.Pick(q, key)
        -- The layout and the other addons change what follows: show the count and note again.
        if q.role or q.clash then
            local page = I.pages and I.pages.duel
            if page and I.flow and I.flow.page == "q:" .. q.id then
                local steps = I.Steps()
                local at = 1
                for n, s in ipairs(steps) do if s.id == I.flow.page then at = n end end
                page.Set(Steps.Question(q, at - 1, #steps - 2))
            end
        end
    end
    -- Out of a fight: hovering a choice plays a fight on its screen.
    if q.id == "calm" then
        out.hover = function(choice, on)
            local page = I.pages and I.pages.duel
            for _, c in ipairs(page and page.choices or {}) do
                if c.spec == choice then
                    for _, child in ipairs({ c.content:GetChildren() }) do
                        if child.Set and child.pieces then child.Set({ fight = on }) end
                    end
                end
            end
        end
    end
    return out
end
