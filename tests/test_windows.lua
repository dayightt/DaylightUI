local stub = require("stub")

-- The window kit: Frame.lua, Follow.lua, Parts.lua and Keys.lua.

local function settle(Win)
    for _ = 1, 60 do
        local d = Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end

T.test("windows: a window builds its page ahead, fills it on show, lifts it in on open", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ name = "DaylightUITestWindow", w = 300, h = 200, portrait = true })
    local built, filled = 0, {}
    local piece
    Win.AddPage(f, "a", {
        Build = function(page) built = built + 1; piece = CreateFrame("Frame", nil, page); piece:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0) end,
        Fill = function(_, x) filled[#filled + 1] = x end,
    })
    Win.Build(f, "a")
    T.eq(built, 1)
    Win.ShowPage(f, "a", "first")
    T.deq(filled, { "first" })
    Win.Open(f)
    T.eq(f:IsShown(), true)
    T.eq(piece:GetAlpha(), 0, "the page's pieces wait for the header")
    settle(Win)
    T.eq(piece:GetAlpha(), 1); T.eq(f:GetAlpha(), 1)
    Win.ShowPage(f, "a", "again")
    T.eq(built, 1, "built once")
    T.eq(piece:GetAlpha(), 0, "a refill lifts in again")
    settle(Win)
    Win.Close(f)
    T.eq(Win.IsOpen(f), false)
    settle(Win)
    T.eq(f:IsShown(), false)
end)

T.test("windows: a page asking for another size glides to it", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ w = 300, h = 200 })
    Win.AddPage(f, "a", { Build = function() end })
    Win.AddPage(f, "wide", { Build = function() end, w = 500 })
    Win.ShowPage(f, "a"); Win.Open(f); settle(Win)
    Win.ShowPage(f, "wide")
    T.truthy(f:GetWidth() < 500, "not a jump")
    settle(Win)
    T.eq(f:GetWidth(), 500)
end)

T.test("windows: a follower parks the game's window, then says when it shows and hides", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local game = CreateFrame("Frame", "TestGameWindow", UIParent)
    game:Hide()
    local seen = {}
    local def = Win.Follow({ key = "test", frames = { talk = function() return game end },
        changed = function(kind, on) seen[#seen + 1] = kind .. ":" .. tostring(on) end })
    T.eq(game:GetParent(), Win.Followers.hidden)
    T.eq(Win.Followers.Parked(def, "talk"), true)
    game:Show()
    Win.Followers.Tick()
    T.deq(seen, { "talk:true" })
    T.eq(game:IsVisible(), false, "out of sight")
    game:Hide()
    Win.Followers.Tick()
    T.deq(seen, { "talk:true", "talk:false" })
end)

T.test("windows: a game window shown before it could be parked stays the game's", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local game = CreateFrame("Frame", nil, UIParent)
    game:Show()
    local seen = 0
    local def = Win.Follow({ key = "early", frames = { talk = function() return game end }, changed = function() seen = seen + 1 end })
    Win.Followers.Tick()
    T.eq(Win.Followers.Parked(def, "talk"), false); T.eq(seen, 0)
    game:Hide()
    Win.Followers.Tick()
    T.eq(Win.Followers.Parked(def, "talk"), true, "parked once it closed")
end)

local function noPanelManager()
    _G.UIPanelWindows, _G.SetUIPanelAttribute, _G.GetUIPanelWidth, _G.ShowUIPanel = nil, nil, nil, nil
end

-- Every layout attribute on a game window, the ones Daylight UI wrote.
local function taintedLayout(f)
    local out = {}
    for k in pairs(f.__attrs) do
        if string.find(k, "^UIPanelLayout%-") and not issecurevariable(f.__attrs, k) then out[#out + 1] = k end
    end
    table.sort(out)
    return table.concat(out, ", ")
end

T.test("windows: a parked window handed back for a fight gets the game's own width back, and is parked again after", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    stub.PanelManager({ TestPanelWindow = { area = "center" } })   -- no width of its own, so the frame's width is used
    local game = CreateFrame("Frame", "TestPanelWindow", UIParent)
    game:SetWidth(338)
    game:Hide()
    local def = Win.Follow({ key = "fight", frames = { w = function() return game end }, aside = { w = true }, width = function() return 300 end })
    T.eq(game:GetParent(), Win.Followers.aside)
    T.eq(game:GetWidth(), 320, "ours, plus the gap")
    T.eq(Win.Followers.Unpark(def, "w"), true)
    T.eq(game:GetParent(), UIParent)
    T.eq(game:GetWidth(), 338, "the game's own again")
    stub.EnterCombat()
    Win.Followers.Tick()
    T.eq(game:GetParent(), UIParent, "not in the fight")
    stub.LeaveCombat()
    Win.Followers.Tick()
    T.eq(game:GetParent(), Win.Followers.aside, "parked again after it")
    T.eq(game:GetWidth(), 320)
    ShowUIPanel(game)
    T.eq(Win.Followers.Unpark(def, "w"), false, "a shown one stays")
    T.eq(taintedLayout(game), "", "no layout attribute written by Daylight UI")
    T.eq(GetUIPanelWidth(game), 320, "the game places the next window by it")
    noPanelManager()
end)

T.test("windows: a game window with a layout width of its own keeps its size", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    stub.PanelManager({ TestWidePanel = { area = "left", width = 605 } })
    local game = CreateFrame("Frame", "TestWidePanel", UIParent)
    game:SetWidth(590)
    game:Hide()
    Win.Follow({ key = "wide", frames = { w = function() return game end }, width = function() return 700 end })
    T.eq(game:GetParent(), Win.Followers.hidden)
    T.eq(game:GetWidth(), 590, "the game reads its layout width, not the frame")
    noPanelManager()
end)

T.test("windows: a covered game window opened by a key in a fight still lets the game close the spellbook", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    stub.secure = true
    stub.PanelManager({ TestSocialFrame = { area = "left", pushable = 0 }, TestBookFrame = { area = "left", pushable = 0 } })
    local social = CreateFrame("Frame", "TestSocialFrame", UIParent)
    social:SetWidth(338)
    social:Hide()
    local book = CreateFrame("Frame", "TestBookFrame", UIParent)
    book:Hide()
    -- The spellbook's OnHide hides the action bar grids, protected buttons.
    local grid = CreateFrame("Button", "TestBarButton1", UIParent)
    grid.__protected = true
    book:SetScript("OnHide", function() grid:SetShown(false) end)
    Win.Follow({ key = "panel", frames = { social = function() return social end }, width = function() return 600 end })
    T.eq(social:GetParent(), Win.Followers.hidden)
    ShowUIPanel(book)
    stub.EnterCombat()
    local ok, err = pcall(ShowUIPanel, social)
    T.truthy(ok, tostring(err))
    T.eq(book:IsShown(), false, "the game moved the book aside")
    T.eq(grid:IsShown(), false, "and its OnHide ran untainted")
    T.eq(GetUIPanelWidth(social), 620, "the next window still opens beside Daylight UI's")
    stub.LeaveCombat()
    noPanelManager()
end)


T.test("windows: no game window is ever parked under a clipping frame", function()
    local DUI = stub.Load()
    local F = DUI.Win.Followers
    T.isnil(F.veil, "the clipping veil is gone")
    for _, home in ipairs({ F.hidden, F.aside }) do
        T.eq(home:DoesClipChildren(), false)
        T.isnil(stub.ClipAncestor(home))
    end
end)

T.test("windows: the aside holder keeps a game window shown and visible without clipping it", function()
    local DUI = stub.Load()
    local F = DUI.Win.Followers
    T.eq(F.aside:GetParent(), UIParent)
    T.eq(F.aside:IsShown(), true)
    T.eq(F.aside:GetAlpha(), 0)
    T.eq(F.aside:GetScale(), F.ASIDE_SCALE)
    T.eq(F.ASIDE_SCALE, 0.001)
    T.eq(F.aside:DoesClipChildren(), false)
    T.eq(F.hidden:DoesClipChildren(), false)
    local game = CreateFrame("Frame", "TestAsideWindow", UIParent)
    game:Hide()
    local def = DUI.Win.Follow({ key = "aside", frames = { w = function() return game end }, aside = { w = true } })
    T.eq(game:GetParent(), F.aside)
    stub.PlacePanel(game)
    game:Show()
    F.Tick()
    T.eq(F.Shown(def, "w"), true)
    T.eq(game:IsVisible(), true, "the game still counts it visible")
    T.isnil(stub.ClipAncestor(game), "never under a clipping frame")
    T.eq(game:GetScale(), 1, "its own scale is never touched")
    T.eq(F.Away(def, "w"), false, "the holder's scale is not another addon's takeover")
end)

T.test("windows: Home reads the game's spot from its anchor, whatever its parent's scale", function()
    local DUI = stub.Load()
    local F = DUI.Win.Followers
    UIParent:SetSize(1000, 800)
    local g = CreateFrame("Frame", nil, F.aside)
    g:SetSize(400, 300)
    g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    local x, y = F.Home(g)
    T.eq(x, 16); T.eq(y, -116)
    g:ClearAllPoints(); g:SetPoint("TOP", UIParent, "TOP", 0, -116)
    x, y = F.Home(g)
    T.eq(x, 300, "centered: 500 less half its width"); T.eq(y, -116)
    g:SetScale(0.5)
    g:ClearAllPoints(); g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 32, -232)
    x, y = F.Home(g)
    T.eq(x, 16, "offsets are in the frame's own scale"); T.eq(y, -116)
    local other = CreateFrame("Frame", nil, UIParent)
    g:ClearAllPoints(); g:SetPoint("TOPRIGHT", other, "TOPRIGHT", 0, 0)
    T.isnil(F.Home(g), "pinned to another frame: no spot to read")
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetScale(2)
    T.eq(F.PlaceOn(f, g), false)
    g:SetScale(1); g:ClearAllPoints(); g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    T.eq(F.PlaceOn(f, g), true)
    local p, rel, rp, fx, fy = f:GetPoint(1)
    T.eq(p, "TOPLEFT"); T.eq(rel, UIParent); T.eq(rp, "TOPLEFT"); T.eq(fx, 8); T.eq(fy, -58)
end)

T.test("windows: an aside window lent to the game and taken back", function()
    local DUI = stub.Load()
    local F = DUI.Win.Followers
    local game = CreateFrame("Frame", "TestAsideLend", UIParent)
    game:Hide()
    local hides = 0
    game:SetScript("OnHide", function() hides = hides + 1 end)
    local def = DUI.Win.Follow({ key = "asidelend", frames = { w = function() return game end }, aside = { w = true } })
    game:Show(); F.Tick()
    T.eq(F.Lend(def, "w"), true)
    T.eq(game:GetParent(), UIParent)
    T.eq(game:GetEffectiveScale(), UIParent:GetEffectiveScale(), "full size again")
    T.eq(F.Reclaim(def, "w"), true)
    T.eq(game:GetParent(), F.aside)
    T.eq(hides, 0, "taking it back never hid it")
end)
T.test("windows: header tabs: the picked one lit, a click picks and tells, the title stops short of them", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ name = "DaylightUITabWindow", w = 400, h = 300 })
    local picked = {}
    Win.Tabs(f, { { id = "a", text = "Alpha" }, { id = "b", text = "Beta" } }, function(id) picked[#picked + 1] = id end)
    T.eq(#f.tabs, 2)
    T.eq(f.tabs[1].id, "a"); T.eq(f.tabs[2].id, "b")
    T.eq(select(2, f.tabs[2]:GetPoint(1)), f.close, "the last tab sits left of the X")
    T.eq(select(2, f.tabs[1]:GetPoint(1)), f.tabs[2])
    Win.PickTab(f, "a")
    T.eq(f.tab, "a"); T.eq(f.tabs[1].line:IsShown(), true); T.eq(f.tabs[2].line:IsShown(), false)
    T.deq(picked, {}, "PickTab doesn't tell")
    f.tabs[2]:Click()
    T.deq(picked, { "b" })
    T.eq(f.tab, "b"); T.eq(f.tabs[2].line:IsShown(), true); T.eq(f.tabs[1].line:IsShown(), false)
    f.tabs[2]:Click()
    T.deq(picked, { "b" }, "the picked tab again does nothing")
    local x
    for i = 1, f.title:GetNumPoints() do
        local p, _, _, px = f.title:GetPoint(i)
        if p == "RIGHT" then x = px end
    end
    T.truthy(x and x < -40, "the title's right end moved in past the tabs")
end)

T.test("windows: tabs refit their labels on show and on a style change, so a wide font never overlaps them", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ name = "DaylightUIWideTabWindow", w = 400, h = 300 })
    Win.Tabs(f, { { id = "a", text = "Spellbook" }, { id = "b", text = "Talents" } }, function() end)
    local narrow = f.tabs[1]:GetWidth()
    -- A wider font than the one measured when the tabs were made.
    stub.measure = function(fs) return #(fs:GetText() or "") * 12, 13 end
    f:Show()
    T.eq(f.tabs[1]:GetWidth(), 9 * 12 + 4, "shown: measured again in the font it draws with")
    T.truthy(f.tabs[1]:GetWidth() > narrow)
    stub.measure = function(fs) return #(fs:GetText() or "") * 14, 13 end
    Win.Repaint(f)
    T.eq(f.tabs[2]:GetWidth(), 7 * 14 + 4, "a style change refits them too")
    stub.measure = nil
    f:Hide()
end)

T.test("windows: a header icon sits left of the X; tabs and the title start left of it", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ name = "DaylightUIIconWindow", w = 400, h = 300 })
    local clicked = 0
    local b = Win.HeaderIcon(f, "ui-options.png", "Options", function() clicked = clicked + 1 end)
    T.eq(select(2, b:GetPoint(1)), f.close, "left of the X")
    b:GetScript("OnClick")(b, "LeftButton")
    T.eq(clicked, 1)
    local function titleRight()
        for i = 1, f.title:GetNumPoints() do
            local p, _, _, px = f.title:GetPoint(i)
            if p == "RIGHT" then return px end
        end
    end
    T.truthy(titleRight() < -40, "no tabs: the title stops short of the icon")
    Win.Tabs(f, { { id = "a", text = "Alpha" } }, function() end)
    T.eq(select(2, f.tabs[1]:GetPoint(1)), b, "the tabs start left of the icon")
end)

T.test("windows: the stack lays blocks top to bottom, two item tiles a line, all reused", function()
    local DUI = stub.Load()
    local Win, Parts = DUI.Win, DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 500)
    local s = Parts.Stack(page)
    local function fill()
        s:Begin()
        s:Text("Hello there.")
        s:Section("Rewards")
        s:Row({ text = "A row", key = "1", onClick = function() end })
        s:Items({ { name = "A" }, { name = "B" }, { name = "C" } })
        s:Money(1234, 450)
        return s:End()
    end
    local pieces = fill()
    T.eq(#pieces, 7)
    local y1 = select(5, pieces[1]:GetPoint(1))
    local y4 = select(5, pieces[4]:GetPoint(1))
    T.truthy(y4 < y1, "lower down")
    T.eq(select(5, pieces[4]:GetPoint(1)), select(5, pieces[5]:GetPoint(1)), "two tiles on one line")
    local first = pieces[3]
    T.truthy(select(4, first.key:GetPoint(1)) < select(4, first.icon:GetPoint(1)), "the key hint sits before the icon")
    pieces = fill()
    T.eq(pieces[3], first, "the row reused")
    s:Begin(); s:End()
    T.eq(first:IsShown(), false, "unused blocks hidden")
end)

-- The quality outline is a 1 px ring with a dark well between it and the icon,
-- so a tile whose icon hasn't loaded yet never shows as a solid white square.
-- An item the game hasn't loaded yet isn't outlined white.
T.test("windows: an item tile with no icon yet shows a dark well, not a white square", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 500)
    local s = Parts.Stack(page)
    s:Begin()
    s:Items({ { name = "Water", quality = 1 }, { name = "Not read yet" } })
    local pieces = s:End()
    local known, unknown = pieces[1], pieces[2]
    T.truthy(known.well, "a well under the icon")
    local r, g, b = known.well:GetVertexColor()
    T.truthy(r < 0.2 and g < 0.2 and b < 0.2, "the well is dark")
    T.eq(known.well:GetDrawLayer(), "ARTWORK")
    T.truthy(select(2, known.well:GetDrawLayer()) > select(2, known.edge:GetDrawLayer()), "over the outline")
    T.eq(known.icon:GetDrawLayer(), "OVERLAY", "under the icon")
    r = unknown.edge:GetVertexColor()
    T.truthy(r < 0.6, "an unread item's outline is neutral, not white")
end)

T.test("windows: a row click picks it with a click sound; a disabled footer button does nothing", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    local s = Parts.Stack(page)
    local picked = 0
    s:Begin()
    local row = s:Row({ text = "Pick me", onClick = function() picked = picked + 1 end })
    s:End()
    row:Click()
    T.eq(picked, 1)
    local foot = Parts.Footer(page)
    local accepted = 0
    foot:Set({ { text = "Accept", primary = true, off = true, onClick = function() accepted = accepted + 1 end } })
    T.eq(foot:Press(1), false); T.eq(accepted, 0)
    foot:Set({ { text = "Accept", primary = true, onClick = function() accepted = accepted + 1 end } })
    T.eq(foot:Press(1), true); T.eq(accepted, 1)
    -- onRightClick: a right-click does that, never onClick (a button without one ignores it)
    local right = 0
    foot:Set({ { text = "Queue 3", onClick = function() accepted = accepted + 1 end, onRightClick = function() right = right + 1 end } })
    foot.buttons[1]:GetScript("OnClick")(foot.buttons[1], "RightButton")
    T.eq(right, 1); T.eq(accepted, 1)
    foot:Set({ { text = "Accept", onClick = function() accepted = accepted + 1 end } })
    foot.buttons[1]:GetScript("OnClick")(foot.buttons[1], "RightButton")
    T.eq(accepted, 1, "no onRightClick: a right-click does nothing")
    -- Same order as the game: main button on the left, leave on the right.
    foot:Set({ { text = "Accept", primary = true }, { text = "Decline", tone = "no" } })
    local p, rel = foot.buttons[1]:GetPoint(1)
    T.eq(p, "LEFT"); T.eq(rel, foot.frame)
    p, rel = foot.buttons[2]:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, foot.frame)
    foot:Set({ { text = "Train", primary = true }, { text = "Train all" }, { text = "Goodbye" } })
    p, rel = foot.buttons[2]:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, foot.buttons[3], "Train all beside Goodbye")
    p, rel = foot.buttons[3]:GetPoint(1)
    T.eq(p, "RIGHT"); T.eq(rel, foot.frame, "Goodbye in the right corner")
    -- Long words in a wide font never run the buttons into each other. The row
    -- shares its space the way a narrow page does (seen on a trainer).
    page:SetSize(400, 300)
    foot.frame:SetWidth(400 - 2 * Parts.EDGE)
    foot:Set({ { text = "Train - 45 silver coins", primary = true },
               { text = "Train all - 5 gold 32 silver 80 copper" }, { text = "Goodbye  Esc" } })
    local total = 0
    for i = 1, 3 do total = total + foot.buttons[i]:GetWidth() end
    T.truthy(total + 2 * 8 <= foot.frame:GetWidth() + 0.5, "the three fit the row: " .. total)
end)

T.test("windows: Parts.Tone gives any button the footer's main and refusal look", function()
    local DUI = stub.Load()
    local Parts, W = DUI.Win.Parts, DUI.Widgets
    local page = CreateFrame("Frame", nil, UIParent)
    local b = W.Button(page, "Scan now", 24)
    Parts.Tone(b, "main")
    T.eq(b.main, true)
    T.rgb({ b.text:GetTextColor() }, Parts.YES)
    Parts.Tone(b, "no")
    T.eq(b.main, false)
    T.rgb({ b.text:GetTextColor() }, Parts.NO)
    Parts.Tone(b, nil)
    T.rgb({ b.text:GetTextColor() }, W.BUTTON.text)
    -- the footer paints its buttons the same way
    local foot = Parts.Footer(page)
    foot:Set({ { text = "Accept", primary = true }, { text = "Decline", tone = "no" } })
    T.eq(foot.buttons[1].main, true)
    T.rgb({ foot.buttons[1].text:GetTextColor() }, Parts.YES)
    T.rgb({ foot.buttons[2].text:GetTextColor() }, Parts.NO)
end)

T.test("windows: a shared footer lays out again when its row changes width", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 300)
    local foot = Parts.Footer(page, { equal = true })
    foot.frame:SetWidth(120)   -- laid out while the panel was still narrow
    foot:Set({ { text = "Show on map", primary = true }, { text = "Untrack" }, { text = "Share" }, { text = "Abandon" } })
    local was = foot.buttons[3]:GetWidth()
    foot.frame:SetWidth(360)
    local onSize = foot.frame:GetScript("OnSizeChanged")
    T.truthy(onSize, "the footer follows its width")
    onSize(foot.frame, 360, 28)
    T.truthy(foot.buttons[3]:GetWidth() > was, "the buttons take the new room")
    T.truthy(foot.buttons[3].text:GetWidth() > was, "and so does their text")
end)

T.test("windows: the main action's glow circles while shown and rests when off", function()
    local DUI = stub.Load()
    local Parts, W = DUI.Win.Parts, DUI.Widgets
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 300)
    local foot = Parts.Footer(page)
    foot.frame:SetWidth(360)
    foot:Set({ { text = "Accept", primary = true }, { text = "Decline", tone = "no" } })
    local main, other = foot.buttons[1], foot.buttons[2]
    T.truthy(main.glowDriver and main.glowDriver:IsVisible(), "the main button glows")
    T.eq(other.glowDriver, nil, "a plain button makes no glow")
    -- The lights move round the band and stay on it.
    local light = main.glowDots[1]
    local _, _, _, x0, y0 = light:GetPoint(1)
    main.glowDriver.__scripts.OnUpdate(main.glowDriver, W.GLOW.lap / 3)
    local _, _, _, x1, y1 = light:GetPoint(1)
    T.truthy(x0 ~= x1 or y0 ~= y1, "the light moved")
    T.truthy(x1 >= 0 and x1 <= main:GetWidth() and y1 <= 0 and y1 >= -main:GetHeight(), "the light is on the button")
    T.truthy(main.glowStrips[1]:IsShown(), "a tail follows the light")
    -- Every style draws, its lights on the button all the way round.
    for _, style in ipairs(W.GLOW_STYLE_ORDER) do
        DUI:Set("general", "buttonGlow", style)
        main.RefreshGlow()
        T.eq(main.glowStyle, style)
        local lit = 0
        for _ = 1, 24 do
            main.glowDriver.__scripts.OnUpdate(main.glowDriver, W.GLOW_LAP[style] / 24)
            for _, d in ipairs(main.glowDots) do
                if d:IsShown() then
                    lit = lit + 1
                    local _, _, _, x, y = d:GetPoint(1)
                    T.truthy(x >= 0 and x <= main:GetWidth() and y <= 0 and y >= -main:GetHeight(), style .. ": on the button")
                end
            end
        end
        T.truthy(lit > 0, style .. ": something lights")
    end
    -- Off: nothing glows.
    DUI:Set("general", "buttonGlow", "none")
    main.RefreshGlow()
    T.eq(main.glowDriver:IsShown(), false, "Off stops it")
    DUI:Set("general", "buttonGlow", "circle")
    main.RefreshGlow()
    -- Hover hands over to the trace: the glow fades out.
    main.GlowHover(true)
    for _ = 1, 5 do
        local f = EnumerateFrames()
        while f do
            if f:IsVisible() then stub.RunOnUpdate(f, 0.1) end
            f = EnumerateFrames(f)
        end
    end
    T.eq(main.glowFade, 0)
    main.GlowHover(false)
    -- Off (nothing to accept yet): it rests, and comes back with the button.
    foot:Set({ { text = "Accept", primary = true, off = true }, { text = "Decline", tone = "no" } })
    T.eq(main.glowDriver:IsShown(), false, "an off button doesn't glow")
    foot:Set({ { text = "Accept", primary = true }, { text = "Decline", tone = "no" } })
    T.eq(main.glowDriver:IsShown(), true)
    -- A button that stops being the main one stops glowing.
    foot:Set({ { text = "Goodbye" } })
    T.eq(main.glowDriver:IsShown(), false)
    -- Motion switched off: no glow.
    foot:Set({ { text = "Accept", primary = true } })
    DUI:Set("general", "motion", false)
    main.RefreshGlow()
    T.eq(main.glowDriver:IsShown(), false, "motion off snaps everything still")
end)

T.test("windows: keys are ours only out of combat, and every other key goes on", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({})
    local got = {}
    local k = Win.Keys(f, function(key) got[#got + 1] = key; return key == "1" end)
    Win.KeysOn(f, true)
    local down = k:GetScript("OnKeyDown")
    down(k, "1")
    T.eq(k.__propagate, false, "the 1 is ours")
    k:GetScript("OnKeyUp")(k, "1")
    T.eq(k.__propagate, true, "back to passing keys on")
    down(k, "W")
    T.eq(k.__propagate, true, "W goes on to the game")
    stub.EnterCombat()
    down(k, "1")
    T.eq(#got, 2, "in combat the keys are the game's")
    T.eq(Win.KeysOf.Number("NUMPAD3"), 3); T.isnil(Win.KeysOf.Number("0"))
end)

-- A frame doesn't pass keys on until told to, and that can't be changed in combat.
-- A window first opened in combat must not take the keyboard, or it swallows
-- movement and spells.
T.test("windows: keys first turned on in a fight never swallow the game's keys", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({})
    stub.EnterCombat()
    local k = Win.Keys(f, function(key) return key == "1" end)
    Win.KeysOn(f, true)
    T.truthy(not (k:IsKeyboardEnabled() and not k:GetPropagateKeyboardInput()),
        "a key frame that can't pass keys on doesn't take the keyboard")
    stub.LeaveCombat()
    T.eq(k:IsKeyboardEnabled(), true, "after the fight the keys are on")
    T.eq(k:GetPropagateKeyboardInput(), true, "and every other key goes on to the game")
    -- Opened and closed within one fight, it stays off.
    Win.KeysOn(f, false)
    stub.EnterCombat()
    Win.KeysOn(f, true); Win.KeysOn(f, false)
    stub.LeaveCombat()
    T.eq(k:IsKeyboardEnabled(), false, "closed again before the fight ended: keys stay off")
    -- Combat starting mid-press, too late to pass keys on again, so it lets go.
    Win.KeysOn(f, true)
    k:GetScript("OnKeyDown")(k, "1")
    stub.EnterCombat()
    T.truthy(not (k:IsKeyboardEnabled() and not k:GetPropagateKeyboardInput()),
        "held back as the fight started: the keyboard goes back to the game")
    stub.LeaveCombat()
    T.eq(k:IsKeyboardEnabled() and k:GetPropagateKeyboardInput(), true, "and the keys come back after it")
end)

-- Text color: a warm base, with the accent on section heads, the picked tab and
-- key hints. Follows an accent change.
T.test("windows: section heads, picked tab and key hints pop in the accent; the rest is warm", function()
    local DUI = stub.Load()
    local Win, Parts, INK = DUI.Win, DUI.Win.Parts, DUI.Style.INK
    DUI:Set("general", "accentColor", { 0.2, 0.6, 0.9 })
    DUI:Set("general", "accent", "custom")
    stub.RunTimers()
    local page = CreateFrame("Frame", nil, UIParent)
    page:SetSize(400, 500)
    local s = Parts.Stack(page)
    s:Begin()
    s:Section("Rewards")
    s:Row({ text = "A row", key = "1" })
    local pieces = s:End()
    T.rgb({ pieces[1].text:GetTextColor() }, { 0.2, 0.6, 0.9 }, "section head")
    T.rgb({ pieces[2].text:GetTextColor() }, INK.TEXT, "row text")
    T.rgb({ pieces[2].key:GetTextColor() }, { 0.2, 0.6, 0.9 }, "key hint")
    local f = Win.New({ name = "DaylightUIInkWindow", w = 400, h = 300 })
    Win.Tabs(f, { { id = "a", text = "Alpha" }, { id = "b", text = "Beta" } }, function() end)
    Win.PickTab(f, "a")
    T.rgb({ f.tabs[1].text:GetTextColor() }, { 0.2, 0.6, 0.9 }, "picked tab")
    T.rgb({ f.tabs[2].text:GetTextColor() }, INK.LABEL, "tab not picked")
    DUI:Set("general", "accentColor", { 0.9, 0.3, 0.2 })
    stub.RunTimers()
    T.rgb({ pieces[1].text:GetTextColor() }, { 0.9, 0.3, 0.2 }, "section head follows the accent")
    Win.Repaint(f)   -- what Book and Npc call on a style change
    T.rgb({ f.tabs[1].text:GetTextColor() }, { 0.9, 0.3, 0.2 }, "picked tab follows the accent")
end)

T.test("windows: the portrait's ring is the warm band, and the accent flare plays once on open", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ w = 300, h = 200, portrait = true })
    local r, g, b = f.portraitRim:GetVertexColor()
    T.deq({ r, g, b }, { DUI.Style.BAND[1], DUI.Style.BAND[2], DUI.Style.BAND[3] }, "never the art's raw white")
    Win.AddPage(f, "a", { Build = function() end })
    Win.ShowPage(f, "a"); Win.Open(f)
    local glow = f.portraitGlow
    T.eq(glow.halo:GetTexture(), DUI.MEDIA .. "cursor-ring-glow.png", "a round halo, not the game's square flipbooks")
    T.eq(glow.halo:GetWidth(), glow.halo:GetHeight(), "as wide as it is tall")
    T.eq(glow:IsShown(), true)
    T.eq(glow.wave, nil, "no ring spreading out: the halo and the embers only")
    T.eq(glow.halo:GetAlpha(), DUI.Win.GLOW_HALO_ALPHA, "the halo sits on the rim")
    -- Embers fly out and circle the rim: always the same distance from the
    -- portrait's centre as the others on their lap, never in a square.
    T.eq(#glow.embers, DUI.Win.EMBERS, "a ring of embers")
    local function spot(e)
        local _, _, _, x, y = e:GetPoint(1)
        return x, y, math.sqrt(x * x + y * y)
    end
    local x1, y1 = spot(glow.embers[1])
    stub.RunOnUpdate(DUI.Motion.Driver(), 0.3)
    local x2, y2 = spot(glow.embers[1])
    T.truthy(x1 ~= x2 or y1 ~= y2, "they circle")
    local lo, hi = 1e9, 0
    for _, e in ipairs(glow.embers) do
        local _, _, r = spot(e)
        lo, hi = math.min(lo, r), math.max(hi, r)
        T.truthy(e:GetAlpha() > 0, "lit")
    end
    T.truthy(hi - lo < 10, "all about one distance out: a circle, not a square")
    T.truthy(lo > DUI.Win.PORTRAIT / 2, "outside the portrait")
    settle(Win)
    T.eq(glow:IsShown(), false, "once, then gone: never a standing alert")
    T.eq(glow.halo:GetAlpha(), 0)
    for _, e in ipairs(glow.embers) do T.eq(e:GetAlpha(), 0, "embers out") end
    Win.Close(f); settle(Win)
    DUI.DB.General().portraitFlare = false
    Win.Open(f)
    T.eq(glow:IsShown(), false, "its own switch off: no flare, the rest of the motion stays")
    DUI.DB.General().portraitFlare = true
    DUI.DB.General().motion = false
    Win.Open(f)
    T.eq(glow:IsShown(), false, "motion off: no flare")
end)

-- Win.Room: windows placed by their TOPLEFT on UIParent. The fake game has no
-- layout, so each reads its left/top back from its anchor.
local function roomWindow(Win, x, w)
    local f = Win.New({ w = w, h = 300 })
    Win.AddPage(f, "a", { Build = function() end })
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -100)
    f.GetLeft = function(self) local _, _, _, px = self:GetPoint(1); return px end
    f.GetTop = function(self) local _, _, _, _, py = self:GetPoint(1); return 800 + py end
    f.GetHeight = function() return 300 end
    Win.ShowPage(f, "a")
    return f
end
local function leftOf(f) local _, _, _, x = f:GetPoint(1); return x end

T.test("windows: a window opening over another makes it glide aside, and back once it closes", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    UIParent.GetWidth = function() return 1600 end
    local a = roomWindow(Win, 100, 400)
    local b = roomWindow(Win, 200, 400)
    Win.Open(a); settle(Win)
    T.eq(leftOf(a), 100, "alone: home")
    Win.Open(b)
    T.truthy(leftOf(a) < 600, "glides, not a jump")
    settle(Win)
    T.near(leftOf(a), 200 + 400 + Win.Room.GAP, 0.01, "beside the new one")
    T.eq(leftOf(b), 200, "the new one keeps its spot")
    Win.Close(b); settle(Win)
    T.eq(leftOf(a), 100, "home again")
    Win.Open(b); settle(Win)
    Win.Close(a); settle(Win)
    Win.Open(a); settle(Win)
    T.eq(leftOf(a), 100, "reopened at home, newest")
    T.truthy(leftOf(b) >= 500, "the other one moved for it")
    UIParent.GetWidth = nil
end)

T.test("windows: with no room either side, the pushed window goes as far as the screen lets it", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    UIParent.GetWidth = function() return 1000 end
    local a = roomWindow(Win, 300, 400)
    local b = roomWindow(Win, 100, 700)
    Win.Open(a); Win.Open(b); settle(Win)
    T.near(leftOf(a), 1000 - Win.Room.EDGE - 400, 0.01, "against the right edge, more room there")
    UIParent.GetWidth = nil
end)

T.test("windows: in a fight a protected window stays put, the rest still make room", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    UIParent.GetWidth = function() return 1600 end
    local a = roomWindow(Win, 100, 400)
    local b = roomWindow(Win, 200, 400)
    a.IsProtected = function() return true end
    Win.Open(a); settle(Win)
    stub.combat = true
    Win.Open(b); settle(Win)
    T.eq(leftOf(a), 100, "locked in combat")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    settle(Win)
    T.near(leftOf(a), 608, 0.01, "laid out once the fight ends")
    UIParent.GetWidth = nil
end)

-- The caster button stayed where the hovered row was. Scrolling moved the list
-- under it so a click cast the old spell, a refill gave the row another spell,
-- and a half-hidden row's caster covered the search box above the list.
T.test("windows: a row's caster covers only what the list shows and goes as the list scrolls or refills", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ w = 300, h = 300 })
    local s
    Win.AddPage(f, "a", { Build = function(page) s = Win.Parts.Stack(page) end })
    Win.ShowPage(f, "a"); Win.Open(f); settle(Win)
    local sf = s.scroll
    sf.GetLeft = function() return 100 end
    sf.GetBottom = function() return 100 end
    sf:SetSize(200, 200)
    local function fill()
        s:Begin()
        local row = s:Piece("row", function(p) return CreateFrame("Button", nil, p) end, 400)   -- a list taller than its view
        s:End()
        return row
    end
    local row = fill()
    row.GetLeft = function() return 100 end
    row.GetBottom = function() return 280 end   -- its top 20 px above the list
    row:SetSize(200, 40)
    local c = Win.Caster({ name = "DaylightUITestCast" })
    local b = c.Over(row, { type1 = "spell", spell = 1 })
    T.truthy(b and b:IsShown())
    T.eq(b:GetAttribute("useOnKeyDown"), false, "it hears only releases: the game must act on those, whatever the key-down setting")
    T.eq(b:GetHeight(), 20, "only the part the list shows")
    -- Entirely outside the list, no button.
    row.GetBottom = function() return 320 end
    T.falsy(c.Over(row, { type1 = "spell", spell = 1 }))
    T.falsy(b:IsShown())
    -- The list scrolls under it.
    row.GetBottom = function() return 200 end
    c.Over(row, { type1 = "spell", spell = 1 })
    T.truthy(b:IsShown())
    s.bar.To(10)
    T.falsy(b:IsShown(), "the wheel moves the list: the button goes")
    -- A refill hands the row another spell.
    c.Over(row, { type1 = "spell", spell = 1 })
    T.truthy(b:IsShown())
    fill()
    T.falsy(b:IsShown(), "a refill: the button goes")
end)

-- Scrolling or a refill took the caster away from under the mouse. The row's
-- OnLeave had already run when the caster covered it, and the caster's OnLeave
-- found no row, so the spellbook row kept its hover light and tooltip. Hiding
-- the caster now fires leave once for its row.
T.test("windows: a caster taken away under the mouse says leave to its row, once", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local left = {}
    local c = Win.Caster({ name = "DaylightUITestCastLeave",
        enter = function() end, leave = function(row) left[#left + 1] = row end })
    local row = CreateFrame("Button", nil, UIParent)
    row.GetLeft = function() return 100 end
    row.GetBottom = function() return 100 end
    row:SetSize(200, 20)
    local b = c.Over(row, { type1 = "spell", spell = 1 })
    b:GetScript("OnEnter")(b)
    c.Hide()   -- as Win.CastersOff does when the wheel moves the list
    T.falsy(b:IsShown())
    T.eq(#left, 1, "the row hears it leave")
    T.eq(left[1], row)
    -- Its own OnLeave runs once, not again from the hide.
    c.Over(row, { type1 = "spell", spell = 1 })
    b:GetScript("OnEnter")(b)
    b:GetScript("OnLeave")(b)
    T.eq(#left, 2, "a plain leave says it once")
    T.falsy(b:IsShown())
    c.Hide()
    T.eq(#left, 2, "already gone: nothing more")
end)

-- A spell dragged off a spellbook row stayed on the cursor at release and took a
-- second click to land. The mouse left the caster, its OnLeave hid it, and a drag
-- whose button is hidden hands nothing to the action bar. Now the button stays
-- until the drag ends while the row's light and tooltip go at once.
T.test("windows: a caster stays shown while its spell is dragged away", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local left, dragged = {}, {}
    local c = Win.Caster({ name = "DaylightUITestCastDrag",
        enter = function() end, leave = function(row) left[#left + 1] = row end,
        drag = function(row) dragged[#dragged + 1] = row end })
    local row = CreateFrame("Button", nil, UIParent)
    row.GetLeft = function() return 100 end
    row.GetBottom = function() return 100 end
    row:SetSize(200, 20)
    local other = CreateFrame("Button", nil, UIParent)
    other.GetLeft = function() return 100 end
    other.GetBottom = function() return 200 end
    other:SetSize(200, 20)
    local b = c.Over(row, { type1 = "spell", spell = 1 })
    b:GetScript("OnEnter")(b)
    b:GetScript("OnDragStart")(b)
    T.eq(dragged[1], row, "the row's drag runs")
    b:GetScript("OnLeave")(b)
    T.truthy(b:IsShown(), "the drag still needs its button")
    T.eq(#left, 1, "the row lets go of its light and tooltip")
    -- Passing over another spell, the button stays where the drag began.
    T.falsy(c.Over(other, { type1 = "spell", spell = 2 }))
    T.eq(b:GetAttribute("spell"), 1)
    -- A refill or the wheel mid-drag leaves it too.
    c.Hide()
    T.truthy(b:IsShown())
    -- Hiding the drag's own button inside OnDragStop stopped the client drawing
    -- nameplates and anything else on WorldFrame (seen in game, every second
    -- drop onto the world). It goes a moment after the drop instead.
    b:GetScript("OnDragStop")(b)
    T.truthy(b:IsShown(), "not hidden during the drop itself")
    stub.RunTimers()
    T.falsy(b:IsShown(), "released: the button goes")
    T.eq(#left, 1, "and the row gets no duplicate calls")
    -- A new hover before then keeps it.
    b = c.Over(row, { type1 = "spell", spell = 1 })
    b:GetScript("OnDragStart")(b)
    b:GetScript("OnLeave")(b)
    b:GetScript("OnDragStop")(b)
    T.truthy(c.Over(row, { type1 = "spell", spell = 1 }))
    stub.RunTimers()
    T.truthy(b:IsShown(), "hovered again: it stays")
    c.Hide()
    -- Released back on the row, it stays, ready to click.
    b = c.Over(row, { type1 = "spell", spell = 1 })
    b:GetScript("OnDragStart")(b)
    b:GetScript("OnDragStop")(b)
    T.truthy(b:IsShown(), "still over its row")
    c.Hide()
    -- Combat starting mid-drag still hides it, so nothing secure stays up.
    b = c.Over(row, { type1 = "spell", spell = 1 })
    b:GetScript("OnDragStart")(b)
    c.Hide(true)
    T.falsy(b:IsShown(), "a fight: the button goes")
    T.truthy(c.Over(row, { type1 = "spell", spell = 1 }), "and the next hover has it back")
end)

-- The client's rule behind vanishing nameplates, as the fake game knows it.
T.test("windows: the fake game refuses a frame hiding itself in its own drag stop", function()
    stub.Load()
    local b = CreateFrame("Button", nil, UIParent)
    b:SetScript("OnDragStop", function(self) self:Hide() end)
    T.errors(function() b:GetScript("OnDragStop")(b) end, "inside its own OnDragStop")
    local holder = CreateFrame("Frame", nil, UIParent)
    local c = CreateFrame("Button", nil, holder)
    c:SetScript("OnDragStop", function() holder:Hide() end)
    T.noerror(function() c:GetScript("OnDragStop")(c) end, "its parent may go")
    local fn = c:GetScript("OnDragStop")
    c:SetScript("OnDragStop", fn)
    T.eq(c:GetScript("OnDragStop"), fn, "read back and set again, it is the same script")
end)

-- A window dragged or resized aside used to leave the windows it had pushed
-- where they were, or cover them. Only a page change laid them out again.
T.test("windows: a drag or a resize let go makes room again", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ w = 300, h = 300 })
    Win.AddPage(f, "a", { Build = function() end })
    Win.ShowPage(f, "a"); Win.Open(f); settle(Win)
    f.GetLeft = function() return 100 end
    f.GetTop = function() return 800 end
    local changed = {}
    local real = Win.Room.Changed
    Win.Room.Changed = function(w) changed[#changed + 1] = w; return real(w) end
    Win.Drag(f, { save = function() end })
    stub.cursorPos = { 200, 800 - 5 }
    f:GetScript("OnDragStart")(f)
    f:GetScript("OnDragStop")(f)
    T.eq(changed[1], f, "after a drag")
    Win.Grip(f, { set = function() end })
    f.grip:GetScript("OnMouseDown")(f.grip, "LeftButton")
    stub.cursorPos = { 220, 780 }
    f.grip:GetScript("OnMouseUp")(f.grip, "LeftButton")
    T.eq(changed[2], f, "after a resize")
    Win.Room.Changed = real
end)

-- Win.Spot (keeps a dragged position) and Win.Shut (closing also hides a hovered
-- row's tooltip), checked for every window that uses them.
T.test("windows: Win.Spot keeps a snapped spot, forgets it and puts the window back (after a fight when protected)", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ w = 300, h = 300 })
    Win.AddPage(f, "a", { Build = function() end })
    local db, placed = {}, 0
    local S = Win.Spot(f, function() return db end, function() placed = placed + 1 end)
    T.falsy(S.Get())
    S.Save(100.3, 500.6)
    T.deq(S.Get(), { DUI.Pixel.Snap(UIParent, 100.3), DUI.Pixel.Snap(UIParent, 500.6) })
    db.spot = { "x", 2 }
    T.falsy(S.Get(), "a broken spot reads as none")
    db.spot = { 1, 2 }
    S.Reset()
    T.falsy(db.spot)
    T.eq(placed, 0, "closed: placed as it next opens")
    Win.ShowPage(f, "a"); Win.Open(f); settle(Win)
    S.Save(10, 20); S.Reset()
    T.eq(placed, 1, "open: back now")
    f.IsProtected = function() return true end
    S.Save(10, 20)
    stub.combat = true
    S.Reset()
    T.eq(placed, 1, "protected in a fight: waits")
    stub.combat = false
    stub.FireEvent("PLAYER_REGEN_ENABLED")
    T.eq(placed, 2, "after the fight")
    T.falsy(S.Reset(), "nothing saved: nothing to do")
    S.Save(1, 2)
    T.truthy(S.Reset())
end)

T.test("windows: Win.Shut closes the window and the tooltip of a row under the mouse, not anyone else's", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner = o end
    function tip:GetOwner() return self.__owner end
    local f = Win.New({ w = 300, h = 300 })
    Win.AddPage(f, "a", { Build = function(page) f.row = CreateFrame("Button", nil, page) end })
    Win.ShowPage(f, "a"); Win.Open(f); settle(Win)
    tip:SetOwner(f.row); tip:Show()
    Win.Shut(f)
    T.falsy(tip:IsShown(), "the row's tooltip goes")
    T.falsy(Win.IsOpen(f))
    settle(Win)
    Win.Open(f); settle(Win)
    local other = CreateFrame("Frame", nil, UIParent)
    tip:SetOwner(other); tip:Show()
    Win.Shut(f)
    T.truthy(tip:IsShown(), "someone else's stays")
end)

-- What the game's Escape does once no dialog or menu of the game's took it:
-- CloseAllWindows hides every shown UISpecialFrames frame (CloseSpecialWindows,
-- UIParentPanelManager.lua), and says whether it found one: the game menu
-- opens only when nothing closed. Losing control (PLAYER_CONTROL_LOST) runs
-- the same CloseAllWindows.
local function gameEscape()
    local hid = false
    for _, n in ipairs(UISpecialFrames) do
        local fr = _G[n]
        if fr and fr:IsShown() then fr:Hide(); hid = true end
    end
    return hid
end

T.test("windows: the game's Escape and losing control close a window of the kit in a fight too, once", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ name = "DaylightUITestEscape" })
    local closed = 0
    f.onClose = function() closed = closed + 1; Win.Close(f) end
    -- Like the standalone windows: their keys take Escape out of a fight.
    Win.Keys(f, function(key) if key == "ESCAPE" then f.close:Click(); return true end end)
    Win.AddPage(f, "a", { Build = function() end })
    Win.ShowPage(f, "a")
    T.eq(gameEscape(), false, "nothing of it before it opens")
    Win.Open(f); Win.KeysOn(f, true); settle(Win)
    stub.EnterCombat()
    -- In a fight the window's keys are off, so the key goes to the game.
    T.eq(gameEscape(), true, "the game's Escape finds it, so the game menu stays shut")
    T.eq(closed, 1, "closed through its own close")
    T.eq(Win.IsOpen(f), false)
    settle(Win)
    T.eq(f:IsShown(), false)
    T.eq(gameEscape(), false, "nothing of it left")
    stub.LeaveCombat()
    -- Opened again, it can be closed again.
    Win.Open(f); settle(Win)
    T.eq(gameEscape(), true, "Escape works the second time too")
    T.eq(closed, 2)
    settle(Win)
    -- Closed by its X: Escape mid-fade or after finds nothing, closes nothing twice.
    Win.Open(f); settle(Win)
    f.close:Click()
    T.eq(closed, 3)
    T.eq(gameEscape(), false, "fading out after its X: Escape is the game menu's again")
    settle(Win)
    T.eq(gameEscape(), false)
    T.eq(closed, 3, "nothing closed twice")
end)

T.test("windows: a window that follows a game window leaves Escape to that game window", function()
    local DUI = stub.Load()
    local Win = DUI.Win
    local f = Win.New({ name = "DaylightUITestFollows", escape = false })
    Win.AddPage(f, "a", { Build = function() end })
    Win.ShowPage(f, "a"); Win.Open(f); settle(Win)
    T.eq(gameEscape(), false, "the game's own window closes, and this one with it")
    T.eq(Win.IsOpen(f), true)
end)

-- The menu above a window of the kit: the window and a button on it.
local function menuOverWindow(DUI)
    local Win, W = DUI.Win, DUI.Widgets
    local f = Win.New({ name = "DaylightUITestMenuHost" })
    Win.AddPage(f, "a", { Build = function(page) f.pick = W.Button(page, "Pick", 24) end })
    Win.ShowPage(f, "a"); Win.Open(f); settle(Win)
    local picked = {}
    W.OpenMenu(f.pick, { "a", "b" }, { a = "A", b = "B" }, nil, function(k) picked[#picked + 1] = k end)
    return f, picked
end

-- The frame holding the open menu's keys (Win.Keys), found from its first row.
local function menuKeys(W)
    local c = W.MenuRow(1)
    while c and not c.keys do c = c:GetParent() end
    return c and c.keys
end

T.test("windows: Escape closes an open menu first, and the window under it stays", function()
    local DUI = stub.Load()
    local W, Win = DUI.Widgets, DUI.Win
    local f, picked = menuOverWindow(DUI)
    T.truthy(W.menuOwner, "the menu is open")
    local k = menuKeys(W)
    T.truthy(k, "the open menu listens for Escape")
    if not k then return end
    T.eq(k:IsKeyboardEnabled(), true, "its keys are on while it's open")
    k:GetScript("OnKeyDown")(k, "ESCAPE")
    T.eq(k.__propagate, false, "Escape is the menu's, the game never sees it")
    T.falsy(W.menuOwner, "the menu closes")
    T.eq(Win.IsOpen(f), true, "the window under it stays")
    T.deq(picked, {}, "nothing picked")
    -- Any other key goes on to the game (moving, casting).
    W.OpenMenu(f.pick, { "a" }, { a = "A" }, nil, function() end)
    k = menuKeys(W)
    k:GetScript("OnKeyDown")(k, "W")
    T.eq(k.__propagate, true)
    T.truthy(W.menuOwner, "still open")
    -- In a fight the keys are the game's: its Escape still closes the menu.
    stub.EnterCombat()
    T.eq(gameEscape(), true)
    T.falsy(W.menuOwner, "closed by the game's Escape in a fight")
    T.eq(Win.IsOpen(f), false, "in a fight the window goes with it: only the game's own list could go one at a time")
    stub.LeaveCombat()
    settle(Win)
    Win.Open(f); settle(Win)
    W.OpenMenu(f.pick, { "a" }, { a = "A" }, nil, function() end)
    W.CloseMenu()
    T.eq(gameEscape(), true, "the window is still there for the next Escape")
    T.eq(gameEscape(), false, "and the closed menu left nothing behind")
end)

T.test("windows: a menu closes when what opened it goes away, like the game's", function()
    local DUI = stub.Load()
    local W, Win = DUI.Widgets, DUI.Win
    local f = menuOverWindow(DUI)
    local menuFrame = W.MenuRow(1)
    while menuFrame:GetParent() and menuFrame:GetParent() ~= UIParent do menuFrame = menuFrame:GetParent() end
    stub.RunOnUpdate(menuFrame, 0.016)
    T.truthy(W.menuOwner, "open while its owner shows")
    Win.Close(f); settle(Win)
    T.eq(f:IsShown(), false)
    stub.RunOnUpdate(menuFrame, 0.016)
    T.falsy(W.menuOwner, "its window closed, the menu with it")
    T.eq(menuFrame:IsShown(), false, "and the screen-wide catcher no longer takes clicks")
    -- Opened at the cursor from a row: the row going away closes it too.
    Win.Open(f); settle(Win)
    W.OpenMenu(f.pick, { "a" }, { a = "A" }, nil, function() end, nil, { atCursor = true })
    stub.RunOnUpdate(menuFrame, 0.016)
    T.truthy(W.menuOwner)
    f.pick:Hide()
    stub.RunOnUpdate(menuFrame, 0.016)
    T.falsy(W.menuOwner, "a cursor menu goes with the row that opened it")
end)

-- The game's tooltip calls its owner's UpdateTooltip every 0.2 s while it's
-- up. An item hover of ours draws the whole tooltip again only when that
-- shows something new: Shift pressed or let go (the compare), or the item's
-- data arriving (TOOLTIP_DATA_UPDATE). Drawing it on every tick made hovering
-- the Auction House's list stutter, five heavy redraws a second.
T.test("windows: an item hover redraws its tooltip only when Shift or the item's data changes", function()
    local DUI = stub.Load()
    local Parts = DUI.Win.Parts
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner = o end
    function tip:GetOwner() return self.__owner end
    function tip:IsOwned(o) return self.__owner == o end
    local shift = false
    local wasTU, wasMod = _G.TooltipUtil, _G.IsModifiedClick
    _G.TooltipUtil = nil
    _G.IsModifiedClick = function(k) return shift and (k == "COMPAREITEMS" or k == nil) end
    local draws = 0
    local b = CreateFrame("Button", nil, UIParent)
    local show = Parts.ItemTip(function(self)
        draws = draws + 1
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:Show()
    end)
    show(b)
    T.eq(draws, 1, "drawn on enter")
    for _ = 1, 25 do b:UpdateTooltip() end   -- five seconds of the game's ticks
    T.eq(draws, 1, "resting on a row draws nothing again")
    shift = true
    b:UpdateTooltip()
    T.eq(draws, 2, "Shift pressed mid-hover redraws for the compare")
    b:UpdateTooltip()
    T.eq(draws, 2, "held Shift doesn't keep redrawing")
    shift = false
    b:UpdateTooltip()
    T.eq(draws, 3, "letting go of Shift redraws")
    stub.FireEvent("TOOLTIP_DATA_UPDATE", 7)
    b:UpdateTooltip()
    T.eq(draws, 4, "the item's data arriving fills the tooltip in")
    b:UpdateTooltip()
    T.eq(draws, 4)
    local live = CreateFrame("Button", nil, UIParent)
    local liveDraws = 0
    Parts.ItemTip(function(self) liveDraws = liveDraws + 1; tip:SetOwner(self); tip:Show() end, nil, true)(live)
    live:UpdateTooltip(); live:UpdateTooltip()
    T.eq(liveDraws, 3, "a live tooltip (a cooldown counting down) redraws on every tick")
    _G.TooltipUtil, _G.IsModifiedClick = wasTU, wasMod
end)
