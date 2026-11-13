local stub = require("stub")
local PW = require("craftworld")

-- The profession window (Craft/).

local function load(spec)
    stub.Load({ before = PW.world(spec) })
    return stub.craft
end

-- One frame of the world: timers, the follower's look, the moves.
local function frame(n)
    for _ = 1, n or 1 do
        stub.RunTimers()
        DaylightUI.Win.Followers.Tick()
        local d = DaylightUI.Win.Feel.Driver()
        if d then stub.RunOnUpdate(d, 1 / 30) end
        local m = DaylightUI.Motion.Driver()
        if m then stub.RunOnUpdate(m, 1 / 30) end
    end
end

local function open(ns, skillLine)
    PW.Open(skillLine or 197)
    frame(20)
    return ns.Window.frame
end

local function page(ns) return ns.Window.frame.pages.recipes end

-- The pieces a stack holds on show, of one kind (lines, heads, tiles).
local function shown(stack, field)
    local out = {}
    for _, b in ipairs(stack.used) do
        if b:IsShown() and b[field] then out[#out + 1] = b end
    end
    return out
end

local function names(ns)
    local out = {}
    for _, b in ipairs(shown(page(ns).list.stack, "lineSpec")) do out[#out + 1] = b.name:GetText() end
    return table.concat(out, ", ")
end

local function heads(ns)
    local out = {}
    for _, b in ipairs(shown(page(ns).list.stack, "isSection")) do out[#out + 1] = b.text:GetText() end
    return table.concat(out, ", ")
end

T.test("craft: on by default", function()
    stub.Load({ before = function() PW.world({})(); DaylightUIDB = nil end })
    T.eq(DaylightUI.craftOwnWindow, true)
    T.truthy(stub.craft.Window.frame, "built")
end)

T.test("craft: switched off, the game's window stays the game's", function()
    local ns = load({ enabled = false })
    T.eq(DaylightUI.craftOwnWindow, false)
    T.isnil(ns.Window.frame, "nothing built")
    PW.Open(197)
    frame(5)
    T.eq(ProfessionsFrame:GetParent(), UIParent, "not parked")
    T.truthy(ProfessionsFrame:IsVisible(), "the game's own window shows")
end)

T.test("craft: ours opens in the game's place for the open profession", function()
    local ns = load()
    T.eq(DaylightUI.craftOwnWindow, true)
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f), "ours open")
    T.eq(ProfessionsFrame:GetParent(), DaylightUI.Win.Followers.veil, "the game's frame is under the veil")
    T.truthy(ProfessionsFrame:IsShown(), "the game's frame still counts as shown")
    T.eq(f.title:GetText(), "Tailoring")
    T.eq(f.sub:GetText(), "Skill 148 / 225")
    local lo, hi = f.skill:GetMinMaxValues()
    T.eq(hi, 225, "the skill bar's range")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- From a player's report: ItemTree's "View in ItemTree" button (on UIParent,
-- pinned inside ProfessionsFrame's top right and shown while that IsShown) floated
-- alone where the veiled game window sat.
T.test("craft: the game's parked window sits just above ours, so another addon's button pinned to it stands on ours", function()
    local ns = load()
    local f = open(ns)
    local g = ProfessionsFrame
    local _, rel, rp, x, y = g:GetPoint(1)
    T.eq(rel, f, "pinned to ours")
    T.eq(rp, "TOPRIGHT"); T.eq(x, 0)
    T.near(y, ns.Window.LIFT * UIParent:GetEffectiveScale() / g:GetEffectiveScale(), 0.01, "just above ours")
    local _, frel = f:GetPoint(1)
    T.truthy(frel ~= g, "ours isn't hung from it (a loop)")
    T.falsy(DaylightUI.Win.Followers.Away(ns.Window.follow, "craft"), "not taken for another addon's")
    -- The game places its window again (another panel opened), and it's pinned back.
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 400, -100)
    frame(1)
    local _, rel2 = g:GetPoint(1)
    T.eq(rel2, f, "pinned again")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- From a player's report: "the game blocked ProfessionsFrame:ClearAllPoints() ...
-- combat lockdown: true", from Craft.Pin each frame of a fight. The game's window is
-- protected, so nobody places it in a fight.
T.test("craft: in a fight the game's parked window is left where it is, pinned again after", function()
    local ns = load()
    local f = open(ns)
    local g = ProfessionsFrame
    g.__protected = true
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 400, -100)
    stub.secure = true
    stub.EnterCombat()
    frame(2)
    local _, rel = g:GetPoint(1)
    T.eq(rel, UIParent, "not touched in the fight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    stub.LeaveCombat()
    frame(1)
    local _, rel2 = g:GetPoint(1)
    T.eq(rel2, f, "pinned once the fight is over")
    stub.secure = nil
end)

T.test("craft: a tab for each profession with a crafting window, the open one picked", function()
    local ns = load()
    local f = open(ns)
    T.eq(#f.tabs, 2, "Tailoring and Cooking; Herbalism has no crafting window")
    T.eq(f.tabs[1].text:GetText(), "Tailoring")
    T.eq(f.tabs[2].text:GetText(), "Cooking")
    T.eq(f.tab, 197, "the open profession's tab picked")
end)

T.test("craft: learned recipes under their categories, in the game's order", function()
    local ns = load()
    open(ns)
    T.eq(heads(ns), "MATERIALS, CLOTH ARMOR")
    T.eq(names(ns), "Bolt of Silk Cloth, Bolt of Linen Cloth, Azure Silk Hood, Brown Linen Shirt", "Red Woolen Bag isn't learned")
end)

T.test("craft: a recipe's name in its difficulty color, the count you can make in the accent", function()
    local ns = load()
    open(ns)
    local L = ns.List.lines
    T.rgb({ L[101].name:GetTextColor() }, ns.Data.Color(0))
    T.rgb({ L[104].name:GetTextColor() }, DaylightUI.Style.INK.OFF, "trivial: dimmed warm, not the game's gray")
    T.eq(L[101].value:GetText(), "1", "5 silk bolts / 2, 3 thread / 2")
    T.rgb({ L[101].value:GetTextColor() }, { DaylightUI.Style.Accent() })
    T.eq(L[103].value:GetText(), "", "nothing to make: no number")
    T.eq(L[101].sub:GetText(), "2 Bolt of Silk Cloth, 2 Fine Thread", "the materials under the name")
end)

T.test("craft: Rarity colors: the chip turns names to what they make's rarity and back, and is remembered", function()
    local ns = load()
    open(ns)
    local pane = page(ns).list
    local Parts = DaylightUI.Win.Parts
    T.eq(pane.rarity.on, nil, "off by default: the skill-up colors")
    T.rgb({ ns.List.lines[101].name:GetTextColor() }, ns.Data.Color(0))
    pane.rarity:Click()
    frame(20)
    T.eq(pane.rarity.on, true, "lit")
    T.eq(DaylightUI:Get("Professions", "rarityNames"), true, "kept in the settings")
    T.rgb({ ns.List.lines[101].name:GetTextColor() }, { Parts.QualityColor(2) }, "an uncommon item's green")
    T.rgb({ ns.List.lines[104].name:GetTextColor() }, { Parts.QualityColor(1) }, "a trivial recipe isn't dimmed now")
    T.eq(ns.Data.SkillsUp(ns.List.data.byID[104]), false, "the Skill-ups chip still knows")
    pane.rarity:Click()
    frame(20)
    T.eq(pane.rarity.on, nil)
    T.rgb({ ns.List.lines[101].name:GetTextColor() }, ns.Data.Color(0), "and back")
end)

T.test("craft: Rarity colors: what makes no item stays white, the options switch moves the chip", function()
    local ns = load()
    T.rgb(ns.Data.NameColor({ id = 999999, difficulty = 0 }, true), DaylightUI.Style.INK.TITLE)
    open(ns)
    DaylightUI:Set("Professions", "rarityNames", true)
    frame(20)
    T.eq(page(ns).list.rarity.on, true)
    T.rgb({ ns.List.lines[101].name:GetTextColor() }, { DaylightUI.Win.Parts.QualityColor(2) })
end)

T.test("craft: the first recipe is picked and shown on the right", function()
    local ns = load()
    open(ns)
    T.eq(ns.Window.Picked(), 102, "the first line")
    T.truthy(ns.List.lines[102].pick:IsShown(), "lit")
    local right = page(ns).recipe.stack
    local top = shown(right, "lineSpec")[1]
    T.eq(top.name:GetText(), "Bolt of Silk Cloth")
    T.eq(top.sub:GetText(), "Usually a skill point")
    T.eq(top.value:GetText(), "You can make 2")
    local tiles = shown(right, "spec")
    T.eq(tiles[1].name:GetText(), "Silk Cloth")
    T.eq(tiles[1].sub:GetText(), "8 / 4")
    T.rgb({ tiles[1].sub:GetTextColor() }, DaylightUI.Style.INK.GOOD)
end)

T.test("craft: a click picks another recipe; short materials in the bad color", function()
    local ns = load()
    open(ns)
    ns.List.lines[104]:Click()
    frame(10)
    T.eq(ns.Window.Picked(), 104)
    T.truthy(ns.List.lines[104].pick:IsShown())
    T.falsy(ns.List.lines[102].pick:IsShown(), "the old one goes out")
    local right = page(ns).recipe.stack
    T.eq(shown(right, "lineSpec")[1].value:GetText(), "Missing materials")
    local tile = shown(right, "spec")[1]
    T.eq(tile.sub:GetText(), "1 / 2")
    T.rgb({ tile.sub:GetTextColor() }, DaylightUI.Style.INK.BAD)
end)

T.test("craft: what a recipe requires, met or not", function()
    local ns = load()
    open(ns, 185)
    local texts = {}
    for _, b in ipairs(page(ns).recipe.stack.used) do
        if b:IsShown() and b.text and not b.isSection and not b.lineSpec then texts[#texts + 1] = b.text:GetText() end
    end
    local all = table.concat(texts, "\n")
    T.truthy(all:find("Cooking Fire", 1, true), all)
end)

T.test("craft: the chips and the search filter the list", function()
    local ns = load()
    open(ns)
    local list = page(ns).list
    list.skill:Click()
    T.eq(names(ns), "Bolt of Silk Cloth, Azure Silk Hood", "Skill-ups: the gray ones go")
    list.skill:Click()
    list.mats:Click()
    T.eq(names(ns), "Bolt of Silk Cloth, Azure Silk Hood", "Have materials")
    list.mats:Click()
    list.search:SetText("linen")
    ns.List.Search("linen")
    T.eq(names(ns), "Bolt of Linen Cloth, Brown Linen Shirt")
    ns.List.Search("nothing like it")
    T.truthy(list.note:IsShown())
    T.eq(list.note:GetText(), "No recipes match.")
    ns.List.Search("")
    T.falsy(list.note:IsShown())
end)

T.test("craft: a heading folds its recipes, remembered per character", function()
    local ns = load()
    open(ns)
    local head = shown(page(ns).list.stack, "isSection")[1]
    head:Click()
    T.eq(heads(ns), "MATERIALS, CLOTH ARMOR")
    T.eq(names(ns), "Azure Silk Hood, Brown Linen Shirt")
    T.eq(DaylightUI.DB.Character().craftFolds["Tailoring:Materials"], true)
    T.eq(shown(page(ns).list.stack, "isSection")[1].state:GetText(), "+")
end)

T.test("craft: a tab opens that profession in the game, ours follows", function()
    local ns = load()
    local f = open(ns)
    f.tabs[2]:Click()
    T.eq(PW.Calls("OpenTradeSkill")[1][1], 185)
    frame(20)
    T.truthy(DaylightUI.Win.IsOpen(f), "still open")
    T.eq(f.title:GetText(), "Cooking")
    T.eq(names(ns), "Charred Wolf Meat")
    T.eq(f.tab, 185)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: a tab switch lifts in only the recipes, the search and chips stay still (no flash)", function()
    local ns = load()
    local f = open(ns)
    frame(40)
    local pane = page(ns).list
    f.tabs[2]:Click()
    local still, lifted = 1, 1
    for _ = 1, 40 do
        frame(1)
        for _, p in ipairs({ pane.search, pane.skill, pane.mats }) do still = math.min(still, p:GetAlpha()) end
        local row = pane.pieces and pane.pieces[1]
        if row then lifted = math.min(lifted, row:GetAlpha()) end
    end
    T.eq(f.title:GetText(), "Cooking")
    T.eq(still, 1, "the search and chips never fade")
    T.truthy(lifted < 1, "the new recipes lift in")
    T.eq(pane.pieces[1]:GetAlpha(), 1, "and land")
end)

T.test("craft: bags change, the counts follow and the pick stays", function()
    local ns = load()
    open(ns)
    ns.List.lines[104]:Click()
    PW.SetBag(2589, 6)
    frame(3)
    T.eq(ns.List.lines[104].value:GetText(), "3")
    T.eq(ns.Window.Picked(), 104)
    T.eq(shown(page(ns).recipe.stack, "lineSpec")[1].value:GetText(), "You can make 3")
end)

T.test("craft: a skill point moves the header", function()
    local ns = load()
    local f = open(ns)
    PW.SkillUp()
    frame(3)
    T.eq(f.sub:GetText(), "Skill 149 / 225")
end)

-- The game's window (Professions.GetProfessionInfo) reads the child line first and
-- the base only when there is none. The addon used to show the base's number instead.
T.test("craft: the header shows the skill the game's own window shows (child line first)", function()
    local ns = load()
    PW.state.profs[1].childRank = 160
    local f = open(ns)
    T.eq(f.sub:GetText(), "Skill 160 / 225")
    T.eq(select(2, f.skill:GetMinMaxValues()), 225)
end)

-- A skill point that only fires SKILL_LINES_CHANGED (no list update after it).
T.test("craft: a skill point with no list update still moves the header", function()
    local ns = load()
    local f = open(ns)
    PW.state.profs[1].rank = PW.state.profs[1].rank + 1
    stub.FireEvent("SKILL_LINES_CHANGED")
    frame(3)
    T.eq(f.sub:GetText(), "Skill 149 / 225")
end)

-- TradeSkillMaster (Core/UI/CraftingUI/Core.lua) clears the game's OnHide and hides
-- its window to show its own, with the profession staying open.
T.test("craft: an addon hiding the game's window with its OnHide cleared keeps the profession open", function()
    local ns = load()
    local f = open(ns)
    ProfessionsFrame:SetScript("OnHide", nil)
    HideUIPanel(ProfessionsFrame)
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "ours stepped aside")
    T.eq(#PW.Calls("CloseTradeSkill"), 0)
end)

T.test("craft: the game closes, ours closes; our X closes the game's", function()
    local ns = load()
    local f = open(ns)
    PW.Close()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f))
    T.eq(#PW.Calls("CloseTradeSkill"), 1, "the game's OnHide closed the trade skill")
    open(ns)
    f.close:Click()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f))
    T.falsy(ProfessionsFrame:IsShown(), "the game's frame hidden too")
    T.eq(#PW.Calls("CloseTradeSkill"), 2)
end)

T.test("craft: the Professions key casts the profession used last (a key our code may press: OpenTradeSkill needs one)", function()
    stub.Load({ before = function() PW.world({})(); stub.bindings.TOGGLEPROFESSIONBOOK = { "K" } end })
    local ns = stub.craft
    local f = open(ns, 185)
    PW.Close()
    frame(20)
    local o = stub.overrides.K
    T.truthy(o, "K taken over for now")
    T.eq(o.click, "DaylightUICraftKey")
    local b = _G.DaylightUICraftKey
    T.deq(b.__clicks, { "AnyDown" }, "the key's press only: the up closed it again (seen in game)")
    T.eq(b:GetAttribute("useOnKeyDown"), true)
    T.eq(b:GetAttribute("type"), "spell")
    T.eq(b:GetAttribute("spell"), 2550, "Cooking's spell: used last")
    stub.Key(function() b:Click() end)
    PW.Open(185)   -- the game, as the spell is cast
    frame(20)
    T.truthy(DaylightUI.Win.IsOpen(f))
    T.eq(f.title:GetText(), "Cooking")
    stub.Key(function() b:Click() end)
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f), "pressed again: it closes")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: a rebound Professions key follows; it stays ours in a fight", function()
    stub.Load({ before = function() PW.world({})(); stub.bindings.TOGGLEPROFESSIONBOOK = { "K" } end })
    local ns = stub.craft
    frame(3)
    T.truthy(stub.overrides.K)
    stub.bindings.TOGGLEPROFESSIONBOOK = { "P", "SHIFT-K" }
    stub.FireEvent("UPDATE_BINDINGS")
    T.isnil(stub.overrides.K, "the old key given back")
    T.eq(stub.overrides.P.click, "DaylightUICraftKey")
    T.eq(stub.overrides["SHIFT-K"].click, "DaylightUICraftKey")
    stub.EnterCombat()
    T.eq(stub.overrides.P.click, "DaylightUICraftKey", "kept through the fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(stub.overrides.P, "still after it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: the game's overview (the micro menu) opens ours with no profession; a tab click opens one", function()
    local ns = load()
    PW.Load()
    frame(3)
    PW.Overview()
    frame(20)
    local f = ns.Window.frame
    T.truthy(DaylightUI.Win.IsOpen(f), "ours, never the game's overview")
    T.eq(ProfessionsFrame:GetParent(), DaylightUI.Win.Followers.veil)
    T.eq(f.title:GetText(), "Professions")
    T.falsy(f.skill:IsShown())
    T.eq(page(ns).list.note:GetText(), "Pick a profession above.")
    T.eq(#PW.Calls("OpenTradeSkill"), 0, "nothing opened by our code alone")
    f.tabs[1]:Click()
    frame(20)
    T.eq(f.title:GetText(), "Tailoring")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The drop-down's rows while it's open.
local function menuRows()
    local W, out = DaylightUI.Widgets, {}
    for n = 1, 20 do
        local r = W.MenuRow(n)
        if r and r:IsVisible() then out[#out + 1] = r end
    end
    return out
end

T.test("craft: right-click the profession's name: Unlearn, the game's own confirm box", function()
    local ns = load()
    local f = open(ns)
    T.falsy(f.unlearn, "no link in the header any more")
    f.who:GetScript("OnClick")(f.who, "RightButton")
    local rows = menuRows()
    T.eq(#rows, 1)
    rows[1]:GetScript("OnClick")(rows[1], "LeftButton")
    T.eq(stub.popup.which, "UNLEARN_SKILL")
    T.eq(stub.popup.text, "Tailoring")
    T.eq(stub.popup.data, 197)
    f.tabs[2]:Click()
    frame(20)
    stub.popup = nil
    f.who:GetScript("OnClick")(f.who, "RightButton")
    T.eq(#menuRows(), 0, "Cooking is secondary: no menu")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: the spell row has no Unlearn link: the X beside the name does that", function()
    local ns = load()
    open(ns)
    T.falsy(ns.Spells.row.unlearn)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: the spell icons stop at the row's end", function()
    local profs = PW.Sample()
    for i = 1, 6 do
        profs[#profs + 1] = { name = "Prof" .. i, skillLine = 900 + i, icon = 136249, spellID = 9000 + i, rank = 10, max = 75, recipes = {} }
    end
    local ns = load({ profs = profs })
    open(ns)
    local row = ns.Spells.row
    local last = 0
    for i, b in ipairs(row.icons) do if b:IsShown() then last = i end end
    local right = last * (ns.Spells.ICON + ns.Spells.GAP) - ns.Spells.GAP
    local room = ns.List.W - 2 * DaylightUI.Win.Parts.EDGE   -- the row's width, since the fake game doesn't lay out two-sided anchors
    T.truthy(right <= room, "icons end at " .. right .. ", room " .. room)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: only gathering professions: the list doesn't say you have none", function()
    local profs = PW.Sample()
    profs[1].craftingUI = false
    profs[3] = nil
    local ns = load({ profs = profs })
    ns.Window.Open(true)
    frame(20)
    T.falsy(page(ns).list.note:GetText() == DaylightUI.L["No professions yet."])
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: an Unlearn link at a primary profession's skill line, in red words, saying what it does", function()
    local ns = load()
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner = o end
    function tip:GetOwner() return self.__owner end
    function tip:IsOwned(o) return self.__owner == o end
    tip.__lines = {}
    function tip:AddLine(t) self.__lines[#self.__lines + 1] = t end
    local f = open(ns)
    T.truthy(f.drop:IsShown())
    T.eq(select(2, f.drop:GetPoint(1)), f.skill, "right after the skill bar")
    T.eq(f.drop.text:GetText(), "Unlearn", "says what it does, not a bare X")
    local bad = DaylightUI.Style.INK.BAD
    T.rgb({ f.drop.text:GetTextColor() }, bad, "red: it drops a profession")
    f.drop:GetScript("OnEnter")(f.drop)
    local all = table.concat(tip.__lines, " | ")
    T.truthy(all:find("Unlearn Tailoring", 1, true), all)
    T.truthy(all:find("learn it again", 1, true), "the tooltip says what it costs: " .. all)
    f.drop:GetScript("OnLeave")(f.drop)
    f.drop:Click()
    T.eq(stub.popup.which, "UNLEARN_SKILL", "the game's own box still asks")
    T.eq(stub.popup.text, "Tailoring")
    T.eq(stub.popup.data, 197)
    f.tabs[2]:Click()
    frame(20)
    T.falsy(f.drop:IsShown(), "Cooking is secondary: no Unlearn")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: the spells under the list say what they are", function()
    local ns = load()
    open(ns)
    frame(20)
    local row = ns.Spells.row
    T.eq(row.label:GetText(), "Abilities")
    local first = row.icons[1]
    T.truthy(first and first:IsShown(), "an icon shows")
    local _, _, _, x = first:GetPoint(1)
    T.truthy(x >= ns.Spells.Lead() and ns.Spells.Lead() > 0, "the icons start after the label")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: Unlearn still shows when the tabs crowd the header", function()
    local profs = PW.Sample()
    for i = 1, 12 do
        profs[#profs + 1] = { name = "Profession" .. i, skillLine = 900 + i, icon = 136249, spellID = 9000 + i, rank = 10, max = 75, recipes = {} }
    end
    local ns = load({ profs = profs })
    local f = open(ns)
    frame(20)
    T.truthy(f.drop:IsShown(), "unlearn stays reachable")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: six professions: the skill bar stops short of the tabs", function()
    local profs = PW.Sample()
    for i, name in ipairs({ "Leatherworking", "First Aid", "Fishing", "Poisons" }) do
        profs[#profs + 1] = { name = name, skillLine = 900 + i, icon = 136249, spellID = 9000 + i, rank = 10, max = 75, recipes = {} }
    end
    local ns = load({ profs = profs })
    local f = open(ns)
    T.truthy(#f.tabs >= 6, "a tab each")
    local tabs = 40
    for _, b in ipairs(f.tabs) do tabs = tabs + b:GetWidth() + DaylightUI.Win.TAB_GAP end
    local W = DaylightUI.Win
    local barEnd = W.EDGE + W.PORTRAIT + 12 + f.skillX + f.skill:GetWidth()
    T.truthy(f.skill:GetWidth() < ns.Window.BAR_W, "the bar gave up some width")
    T.truthy(not f.skill:IsShown() or barEnd + 10 <= f:GetWidth() - tabs, "bar ends " .. barEnd .. ", tabs start " .. (f:GetWidth() - tabs))
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: ours in a fight: opens, switches tabs, our X closes the game's", function()
    local ns = load()
    PW.Load()
    frame(3)
    stub.EnterCombat()
    T.eq(ProfessionsFrame:GetParent(), DaylightUI.Win.Followers.veil, "the game's stays parked")
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f), "ours opened in the fight")
    f.tabs[2]:Click()
    frame(20)
    T.eq(f.title:GetText(), "Cooking", "a tab works in the fight")
    f.close:Click()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(f))
    T.falsy(ProfessionsFrame:IsShown(), "the trade skill closed, the game's frame with it")
    local before = #PW.Calls("SetUIPanelAttribute")
    stub.LeaveCombat()
    stub.RunTimers()
    T.truthy(#PW.Calls("SetUIPanelAttribute") > before, "the panel width written after the fight")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: motion off, everything still opens", function()
    stub.Load({ before = function()
        PW.world({})()
        DaylightUIDB.profileData["DPS/Tank"].general = { motion = false }
    end })
    local ns = stub.craft
    local f = open(ns)
    T.truthy(DaylightUI.Win.IsOpen(f))
    T.eq(f:GetAlpha(), 1)
end)

T.test("craft: someone's linked recipes open the small window; your own profession after takes over", function()
    local ns = load()
    PW.Load()
    frame(3)
    PW.state.linked, PW.state.linkedName, PW.state.linkedSkill = true, "Barry Maannalaow", 81
    PW.Open(197)
    frame(10)
    local view = ns.View.frame
    T.truthy(view and DaylightUI.Win.IsOpen(view), "the small window opens")
    T.truthy(view:GetWidth() < ns.Window.W / 2 + 1, "smaller than your own")
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame), "yours stays shut")
    T.eq(ProfessionsFrame:GetParent(), DaylightUI.Win.Followers.veil, "the game's window stays parked")
    T.eq(view.title:GetText(), "Tailoring")
    T.truthy(string.find(view.sub:GetText(), "Barry Maannalaow", 1, true), "whose it is")
    T.truthy(string.find(view.sub:GetText(), "81", 1, true), "their skill, not yours")
    T.truthy(next(ns.View.lines) ~= nil, "their recipes")
    PW.state.linked = false
    PW.state.linkedSkill = nil
    PW.Open(185)
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(view), "the small window goes")
    T.truthy(DaylightUI.Win.IsOpen(ns.Window.frame), "yours opens")
    T.eq(ns.Window.frame.title:GetText(), "Cooking")
    T.truthy(ProfessionsFrame:IsShown())
    T.eq(#PW.Calls("CloseTradeSkill"), 0, "the trade skill never closed")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- The game's frame shows on TRADE_SKILL_SHOW and someone's list comes after it. The
-- game itself waits for that (ProfessionsMixin:OnEvent, IsDataSourceChanging).
T.test("craft: a link whose list comes in after the frame shows still opens the small window", function()
    local ns = load()
    PW.Load()
    frame(3)
    PW.LinkOpens(true)
    frame(5)
    T.eq(ProfessionsFrame:GetParent(), DaylightUI.Win.Followers.veil, "waiting, not given to the game")
    PW.LinkArrives(197, "Brat Mage")
    frame(10)
    T.truthy(ns.View.frame and DaylightUI.Win.IsOpen(ns.View.frame), "the small window opens")
    T.eq(ProfessionsFrame:GetParent(), DaylightUI.Win.Followers.veil, "the game's stays parked")
    T.eq(ns.View.frame.title:GetText(), "Tailoring")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: a link that looked like nothing at first is taken back from the game", function()
    local ns = load()
    PW.Load()
    frame(3)
    PW.LinkOpens(false)
    frame(5)
    PW.LinkArrives(197, "Brat Mage")
    frame(10)
    T.truthy(ns.View.frame and DaylightUI.Win.IsOpen(ns.View.frame), "the small window opens")
    T.eq(ProfessionsFrame:GetParent(), DaylightUI.Win.Followers.veil, "taken back")
    T.truthy(ProfessionsFrame:IsShown(), "still open underneath")
    T.eq(#PW.Calls("CloseTradeSkill"), 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: the small window offers nothing to make, and its X closes the game's window too", function()
    local ns = load()
    PW.Load()
    frame(3)
    PW.state.linked, PW.state.linkedName = true, "Barry"
    PW.Open(197)
    frame(10)
    T.falsy(ns.View.page.make, "no Create button")
    ns.View.frame.onClose()
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(ns.View.frame))
    T.falsy(ProfessionsFrame:IsShown(), "the trade skill's window goes with it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: a link clicked with your own window open swaps to the small window", function()
    local ns = load()
    PW.Load()
    frame(3)
    PW.Open(185)
    frame(10)
    T.truthy(DaylightUI.Win.IsOpen(ns.Window.frame))
    PW.state.linked, PW.state.linkedName = true, "Barry"
    PW.Open(197)
    frame(20)
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame), "yours goes")
    T.truthy(DaylightUI.Win.IsOpen(ns.View.frame), "theirs opens")
    T.eq(ns.View.frame.title:GetText(), "Tailoring")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: a guild member's recipes are the small window; the whole guild's list stays the game's", function()
    local ns = load()
    PW.Load()
    frame(3)
    PW.state.guildMember = true
    PW.Open(197)
    frame(10)
    T.truthy(DaylightUI.Win.IsOpen(ns.View.frame), "one member's")
    PW.Close()
    frame(10)
    PW.state.guildMember, PW.state.guild = false, true
    PW.Open(197)
    frame(10)
    T.falsy(ns.View.frame and DaylightUI.Win.IsOpen(ns.View.frame), "the guild's")
    T.falsy(DaylightUI.Win.IsOpen(ns.Window.frame))
    T.eq(ProfessionsFrame:GetParent(), UIParent, "its crafters list is the game's")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("craft: the Slot chip shows one slot at a time through the game's filter; another profession starts on all", function()
    local ns = load()
    local f = open(ns)
    local list = page(ns).list
    T.truthy(list.slot:IsShown(), "Tailoring makes gear")
    ns.List.PickSlot(2)
    frame(3)
    T.eq(names(ns), "Brown Linen Shirt", "Chest only")
    T.eq(list.slot.text:GetText(), "Chest")
    T.truthy(list.slot.on, "lit while it filters")
    local last = PW.Calls("SetInventorySlotFilter")
    T.deq(last[#last], { 2, true, true }, "the game's one-slot filter")
    ns.List.PickSlot(3)
    frame(3)
    T.eq(names(ns), "Bolt of Silk Cloth, Bolt of Linen Cloth", "Created Items: what isn't gear")
    ns.List.PickSlot(nil)
    frame(3)
    T.eq(names(ns), "Bolt of Silk Cloth, Bolt of Linen Cloth, Azure Silk Hood, Brown Linen Shirt")
    T.eq(list.slot.text:GetText(), "Slot")
    ns.List.PickSlot(1)
    f.tabs[2]:Click()
    frame(20)
    T.falsy(list.slot:IsShown(), "Cooking has no slots")
    T.isnil(ns.List.slot, "the filter's gone")
    T.truthy(#PW.Calls("ClearInventorySlotFilter") >= 2)
    T.eq(names(ns), "Charred Wolf Meat")
end)

-- ---------------------------------------------------------------------
-- Making things (Make.lua)
-- ---------------------------------------------------------------------

local function footer(ns) return ns.Make.foot end

T.test("craft: the footer: Create, the amount, Create all [n]", function()
    local ns = load()
    open(ns)
    local foot = footer(ns)
    T.eq(foot.buttons[1].text:GetText(), CREATE_PROFESSION or "Create")
    T.falsy(foot.buttons[1].off, "2 bolts of silk can be made")
    T.eq(foot.buttons[2].text:GetText(), "Create all [2]")
    T.truthy(ns.Make.box:IsShown())
    T.eq(ns.Make.box.num:GetText(), "1")
    ns.Make.box.more:Click()
    ns.Make.box.more:Click()
    T.eq(ns.Make.amount, 2, "never more than you can make")
    T.truthy(ns.Make.box.more.off)
    ns.List.lines[104]:Click()
    frame(5)
    T.eq(ns.Make.amount, 1, "a new recipe starts at one")
    T.truthy(foot.buttons[1].off, "nothing to make it with")
    T.truthy(foot.buttons[2].off)
end)

T.test("craft: on a controller, as the game's crafting footer: X makes the amount, X held makes all, Y shares, the menu buttons filter and search", function()
    local ns = load()
    local f = open(ns)
    local function entry(key, at)
        for _, e in ipairs(f.padKeys) do
            if e.key == key and (not e.when or e.when(at)) then return e end
        end
    end
    local x = entry("X")
    T.eq(x.label(), CREATE_PROFESSION or "Create")
    T.eq(x.hold.label(), "Create all [2]")
    x.hold.run()
    T.deq(PW.Calls("CraftRecipe")[1], { 102, 2 })
    T.isnil(entry("X"), "nothing more while it's making")
    local row = ns.List.lines[102]
    T.eq(entry("Y", row).label, CONTEXT_ACTION_LABEL_MORE_ACTIONS or "More", "a recipe's more actions")
    T.isnil(entry("Y", nil), "not off a recipe")
    local box, focused = ns.List.pane.search, false
    box.SetFocus = function() focused = true end   -- the fake game keeps no focus
    entry("MENU_LEFT", nil).run()
    T.truthy(focused, "the search box")
    T.isnil(entry("MENU_LEFT", ns.List.pane.search), "not while on it")
end)

T.test("craft: Create makes the amount; the footer shows the progress, then comes back", function()
    local ns = load()
    open(ns)
    ns.Make.SetAmount(2)
    footer(ns).buttons[1]:Click()
    T.deq(PW.Calls("CraftRecipe")[1], { 102, 2 })
    local row = ns.Make.row
    T.truthy(row:IsShown(), "the progress row")
    T.falsy(footer(ns).frame:IsShown())
    T.truthy(stub.Text(row.text):find("1", 1, true))
    PW.Cast()
    frame(2)
    T.truthy(row:IsShown(), "one to go")
    T.truthy(stub.Text(row.text):find("2", 1, true), stub.Text(row.text))
    PW.Cast()
    frame(5)
    T.falsy(row:IsShown(), "done")
    T.truthy(footer(ns).frame:IsShown())
    T.eq(ns.List.lines[102].value:GetText(), "", "the silk is used up")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

-- In game, hiding the footer before the call blocked the craft.
T.test("craft: the craft starts while the pressed button is still there", function()
    for _, i in ipairs({ 1, 2 }) do
        local ns = load()
        open(ns)
        PW.Press(footer(ns).buttons[i])
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
        T.truthy(ns.Make.row:IsShown(), "the progress row comes after it")
    end
end)

T.test("craft: Create all makes every one; a failed cast ends it", function()
    local ns = load()
    open(ns)
    footer(ns).buttons[2]:Click()
    T.deq(PW.Calls("CraftRecipe")[1], { 102, 2 })
    PW.Cast(false)
    frame(3)
    T.falsy(ns.Make.row:IsShown(), "back to the footer")
    T.falsy(ns.Make.Busy())
end)

T.test("craft: Stop is the secure /stopcasting over our button, out of combat", function()
    local ns = load()
    open(ns)
    footer(ns).buttons[1]:Click()
    local stop = ns.Make.row.stop
    stop.GetLeft = function() return 600 end
    stop.GetBottom = function() return 100 end
    stop:GetScript("OnEnter")(stop)
    local b = ns.Make.caster.button
    T.truthy(b and b:IsShown())
    T.eq(b:GetParent(), UIParent, "never the window's child")
    T.eq(b:GetAttribute("type1"), "macro")
    T.eq(b:GetAttribute("macrotext1"), "/stopcasting")
    stub.FireEvent("UPDATE_TRADESKILL_CAST_STOPPED", false)
    frame(3)
    T.falsy(ns.Make.row:IsShown(), "stopped: the footer again")
end)

T.test("craft: an enchant is made once, with no amount", function()
    local profs = PW.Sample()
    profs[1].recipes[2].enchant = true
    local ns = load({ profs = profs })
    open(ns)
    T.falsy(ns.Make.box:IsShown())
    T.falsy(footer(ns).buttons[2] and footer(ns).buttons[2]:IsShown(), "no Create all")
    footer(ns).buttons[1]:Click()
    T.eq(PW.Calls("CraftEnchant")[1][1], 102)
    T.eq(PW.Calls("CraftEnchant")[1][2], 1)
    T.truthy(ns.Make.row:IsShown(), "waiting for the item to enchant")
    -- The item never picked (right-click, Escape): the game says the cast was
    -- canceled and no cast event ever comes.
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED", true)
    frame(3)
    T.falsy(ns.Make.row:IsShown(), "canceled: the footer again, not stuck on Making 1 of 1")
    T.falsy(ns.Make.Busy())
end)

local function enchanter(items)
    local profs = PW.Sample()
    profs[1].recipes[2].enchant = true
    local ns = load({ profs = profs })
    PW.EnchantItems(items)
    PW.SetBag(4306, 20)
    open(ns)
    return ns
end

T.test("craft: an enchant lists what it can go on, and with nothing picked still asks for the click", function()
    local bracers = { guid = "Item-1", name = "Worn Bracers" }
    local ns = enchanter({ bracers })
    T.truthy(page(ns).recipe.target, "asks for an item")
    T.falsy(ns.Make.box:IsShown(), "no amount yet")
    footer(ns).buttons[1]:Click()
    T.eq(PW.Calls("CraftEnchant")[1][3], nil, "no item: the game's own click")
end)

T.test("craft: an enchant the game lists no item for stays as it was", function()
    local ns = enchanter({})
    T.falsy(page(ns).recipe.target)
end)

T.test("craft: a picked item is enchanted with no click, and remembered", function()
    local bracers = { guid = "Item-1", name = "Worn Bracers" }
    local ns = enchanter({ bracers })
    ns.Make.SetTarget("Item-1")
    ns.Recipe.Fill(page(ns).recipe, ns.Make.recipe, true)
    T.truthy(ns.Make.box:IsShown(), "the amount")
    T.truthy(footer(ns).buttons[2]:IsShown(), "Enchant all")
    ns.Make.SetAmount(2)
    footer(ns).buttons[1]:Click()
    local c = PW.Calls("CraftEnchant")[1]
    T.eq(c[2], 2)
    T.eq(c[3], bracers)
    T.truthy(ns.Make.row:IsShown())
    PW.Cast()
    T.truthy(ns.Make.Busy(), "one to go")
    PW.Cast()
    frame(3)
    T.falsy(ns.Make.Busy(), "both done")
    T.eq(DaylightUI.DB.Character().craftTargets[1], "Item-1")
end)

T.test("craft: the game's replace question stays for someone else's enchant, then spamming answers it", function()
    local bracers = { guid = "Item-1", name = "Worn Bracers", enchant = "Enchant Bracer - Stamina" }
    local ns = enchanter({ bracers })
    ns.Make.SetTarget("Item-1")
    ns.Recipe.Fill(page(ns).recipe, ns.Make.recipe, true)
    ns.Make.SetAmount(2)
    footer(ns).buttons[1]:Click()
    T.eq(#PW.Calls("ReplaceTradeskillEnchant"), 0, "the first answer is the player's")
    frame(3)
    T.falsy(ns.Make.row:IsShown(), "the footer steps aside: No tells nobody")
    -- Yes: the game's button.
    C_Item.ReplaceTradeskillEnchant()
    PW.Cast()
    T.truthy(ns.Make.Busy(), "the run came back")
    T.eq(#PW.Calls("ReplaceTradeskillEnchant"), 2, "the same enchant again: answered for you")
    T.eq(PW.Calls("StaticPopup_Hide")[1][1], "REPLACE_TRADESKILL_ENCHANT")
    PW.Cast()
    frame(3)
    T.falsy(ns.Make.Busy())
end)

T.test("craft: a picked item can be cleared, back to the game's click", function()
    local ns = enchanter({ { guid = "Item-1", name = "Worn Bracers" } })
    ns.Make.SetTarget("Item-1")
    ns.Recipe.Fill(page(ns).recipe, ns.Make.recipe, true)
    T.truthy(ns.Make.TargetFor(ns.Make.recipe), "picked")
    ns.Make.ClearTarget(ns.Make.recipe)
    ns.Recipe.Fill(page(ns).recipe, ns.Make.recipe, true)
    T.falsy(ns.Make.TargetFor(ns.Make.recipe), "cleared")
    T.falsy(ns.Make.box:IsShown(), "one at a time again")
    footer(ns).buttons[1]:Click()
    local c = PW.Calls("CraftEnchant")[1]
    T.eq(c[2], 1)
    T.eq(c[3], nil, "no item: the game's click, on anything, a trade's item too")
end)

T.test("craft: a run the game stops short gives the footer back", function()
    local ns = enchanter({ { guid = "Item-1", name = "Worn Bracers" } })
    ns.Make.SetTarget("Item-1")
    ns.Recipe.Fill(page(ns).recipe, ns.Make.recipe, true)
    ns.Make.SetAmount(2)
    footer(ns).buttons[1]:Click()
    PW.Cast()
    T.truthy(ns.Make.Busy())
    stub.Advance(ns.Make.GAP + 0.1)
    frame(3)
    T.falsy(ns.Make.Busy())
end)

T.test("craft: another spell canceled before a craft's first cast leaves its progress row", function()
    local ns = load()
    open(ns)
    footer(ns).buttons[2]:Click()
    -- A targeting spell canceled (right-click) before the craft's cast started.
    -- Only an enchant waits on a pick like that.
    stub.FireEvent("CURRENT_SPELL_CAST_CHANGED", true)
    frame(3)
    T.truthy(ns.Make.row:IsShown(), "still making")
    T.truthy(ns.Make.Busy())
    PW.Cast(); PW.Cast()
    frame(3)
    T.falsy(ns.Make.row:IsShown(), "both made: the footer again")
end)

T.test("craft: a skill point: the bar glides, +1 floats up, a recipe's color eases to its next", function()
    local ns = load()
    local f = open(ns)
    local before = { ns.List.lines[101].name:GetTextColor() }
    PW.state.profs[1].recipes[1].difficulty = 1   -- the hood, orange to yellow
    PW.SkillUp()
    frame(2)
    T.eq(f.plus:GetText(), "+1")
    T.truthy(f.plus:GetAlpha() > 0, "floating")
    T.rgb({ f.plus:GetTextColor() }, DaylightUI.Style.INK.GOOD)
    local mid = { ns.List.lines[101].name:GetTextColor() }
    T.truthy(mid[2] ~= before[2] or mid[1] ~= before[1], "on its way")
    frame(60)
    T.rgb({ ns.List.lines[101].name:GetTextColor() }, ns.Data.Color(1), "yellow now")
    T.eq(f.plus:GetAlpha(), 0, "gone")
    local _, hi = f.skill:GetMinMaxValues()
    T.near(f.skill:GetValue(), 149, 0.01)
end)

T.test("craft: every profession's spells under the list, dragged to a bar", function()
    local ns = load()
    open(ns)
    local icons = {}
    for _, b in ipairs(ns.Spells.row.icons) do if b:IsShown() then icons[#icons + 1] = b end end
    T.truthy(ns.Spells.row:IsShown())
    T.eq(#icons, 4, "Tailoring, Herbalism, Find Herbs, Cooking (the passive left out)")
    T.eq(icons[3].spell.name, "Find Herbs")
    T.eq(icons[3].icon:GetTexture(), 133939)
    icons[3]:GetScript("OnDragStart")(icons[3])
    T.eq(PW.Calls("PickupSpellBookItem")[1][1], 22, "its spellbook slot")
    T.eq(#ns.Spells.Pieces(), 4, "they lift in with the list")
end)

T.test("craft: the corner grip resizes the window: the list a share wider, the recipe the rest", function()
    local ns = load()
    ns.Window.SaveSpot(600, 700)
    local f = open(ns)
    local W = ns.Window
    local p = page(ns)
    T.near(p.list:GetWidth(), ns.List.W, 0.5, "the list its own width at first")
    local filled, fill = 0, ns.Recipe.Fill
    ns.Recipe.Fill = function(...) filled = filled + 1; return fill(...) end
    -- The grip's own resize, as a drag 200 px right ends.
    local grip = f.grip
    f.GetLeft = function(self) local _, _, _, x = self:GetPoint(1); return x end
    f.GetTop = function(self) return select(5, self:GetPoint(1)) end
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
    local e = f:GetEffectiveScale()
    stub.cursorPos = { (100 + W.W) * e, (700 - W.H) * e }
    grip:GetScript("OnMouseDown")(grip, "LeftButton")
    stub.cursorPos = { (100 + W.W + 200) * e, (700 - W.H) * e }
    grip:GetScript("OnMouseUp")(grip, "LeftButton")
    T.near(f:GetWidth(), W.W + 200, 0.5, "200 wider")
    T.near(p.list:GetWidth(), ns.List.W + math.floor(200 * W.LIST_SHARE), 0.5, "the list takes its share")
    T.truthy(filled > 0, "the recipe laid out again (the fake game has no layout to measure)")
    T.near(ns.module.db.sizes.all[1], W.W + 200, 0.5, "saved")
    ns.Recipe.Fill = fill
end)

-- DaylightMogul (the same author's AH addon) has a profession window of its own.
-- While its API 1.3 says Craft.Owns(), Daylight UI's steps aside (not built, no
-- key), the Skins leave the game's frame alone (Mogul parks it), and the options
-- page says so. With Mogul absent, older or broken, everything works as before.
local function mogul(version, owns)
    return { API = { version = version, Craft = { Owns = owns } } }
end

-- The chat around a share. The game's InsertLink only returns true when a box (or a
-- macro) took the link.
local function fakeChat(boxOpen)
    local chat = { inserted = {}, sent = {} }
    local was = { _G.ChatFrameUtil, _G.C_ChatInfo, _G.GetChannelList, _G.IsInGuild }
    _G.ChatFrameUtil = { InsertLink = function(link)
        if not boxOpen then return false end
        chat.inserted[#chat.inserted + 1] = link
        return true
    end }
    _G.C_ChatInfo = { SendChatMessage = function(msg, kind, _, target)
        chat.sent[#chat.sent + 1] = { msg, kind, target }
    end, InChatMessagingLockdown = function() return chat.locked == true end }
    _G.GetChannelList = function() return 1, "General", false, 2, "Trade", true, 5, "Crafters", false end
    _G.IsInGuild = function() return true end
    function chat.Done()
        _G.ChatFrameUtil, _G.C_ChatInfo, _G.GetChannelList, _G.IsInGuild = was[1], was[2], was[3], was[4]
        DaylightUI.Widgets.CloseMenu()
    end
    return chat
end

local function pickMenu(text)
    for _, r in ipairs(menuRows()) do
        if r.text and r.text:GetText() == text then r:Click(); return true end
    end
    return false
end

local function menuTexts()
    local out = {}
    for _, r in ipairs(menuRows()) do out[#out + 1] = r.text and r.text:GetText() or "" end
    return table.concat(out, ", ")
end

-- Shift-click on the profession's icon or name puts its link in the open chat box,
-- the way the game's own book does. A plain click only drags.
local function shiftClick(f, shift)
    local was = _G.IsModifiedClick
    _G.IsModifiedClick = function(k) return shift and k == "CHATLINK" end
    f.who:GetScript("OnClick")(f.who, "LeftButton")
    _G.IsModifiedClick = was
end

T.test("craft: Shift-click on a recipe, an enchant too, puts the recipe's link in the open chat box", function()
    local profs = PW.Sample()
    profs[1].recipes[2].enchant = true
    local ns = load({ profs = profs })
    open(ns)
    local chat = fakeChat(true)
    local was = _G.IsModifiedClick
    _G.IsModifiedClick = function(k) return k == "CHATLINK" end
    for _, b in ipairs(shown(page(ns).list.stack, "lineSpec")) do
        local r = b.lineSpec.recipe
        if r and r.id == 102 then b.lineSpec.onClick(b) end
    end
    _G.IsModifiedClick = was
    chat.Done()
    T.truthy(chat.inserted[1] and chat.inserted[1]:find("Henchant:102", 1, true), "the enchant's link")
end)

T.test("craft: Shift-click on the profession's name puts its link in the open chat box", function()
    local ns = load()
    local f = open(ns)
    T.falsy(f.share, "no share icon in the header")
    local chat = fakeChat(true)
    shiftClick(f, false)
    T.eq(#chat.inserted, 0, "a plain click links nothing")
    shiftClick(f, true)
    T.truthy(chat.inserted[1] and chat.inserted[1]:find("[Tailoring]", 1, true))
    T.eq(#chat.sent, 0)
    T.eq(#menuRows(), 0)
    chat.Done()
end)

T.test("craft: Shift-click with no chat box open posts nothing and asks nothing", function()
    local ns = load()
    local f = open(ns)
    local chat = fakeChat(false)
    shiftClick(f, true)
    T.eq(#chat.sent, 0)
    T.eq(#menuRows(), 0)
    chat.Done()
end)

T.test("craft: hovering the profession's name says Shift-click links it", function()
    local ns = load()
    local tip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
    _G.GameTooltip = tip
    function tip:SetOwner(o) self.__owner = o end
    function tip:GetOwner() return self.__owner end
    function tip:IsOwned(o) return self.__owner == o end
    tip.__lines = {}
    function tip:AddLine(t) self.__lines[#self.__lines + 1] = t end
    local f = open(ns)
    f.who:GetScript("OnEnter")(f.who)
    T.truthy(GameTooltip:IsShown())
    local all = tip.__lines
    T.truthy(table.concat(all, " | "):find("Shift-click", 1, true), table.concat(all, " | "))
    f.who:GetScript("OnLeave")(f.who)
    T.falsy(GameTooltip:IsShown())
end)

T.test("craft: mogul_owns_professions_no_window", function()
    stub.Load({ before = function()
        PW.world({})()
        stub.bindings.TOGGLEPROFESSIONBOOK = { "K" }
        _G.DaylightMogul = mogul({ 1, 3 }, function() return true end)
    end })
    local ns = stub.craft
    T.eq(DaylightUI.craftOwnWindow, false, "ours isn't the window")
    T.eq(DaylightUI.craftMogul, true, "Mogul's is")
    T.isnil(ns.Window.frame, "nothing built")
    PW.Open(185)
    frame(20)
    T.eq(ProfessionsFrame:GetParent(), UIParent, "the game's frame is left to Mogul, not parked by us")
    T.isnil(stub.overrides.K, "the Professions key is left to Mogul")
    T.isnil(_G.DaylightUICraftKey, "no key button of ours")
    local note
    for _, item in ipairs(ns.OPTIONS.pages[1].groups[1].items) do
        if item.type == "text" then note = item end
    end
    T.truthy(note, "the options page has a note")
    T.eq(note.label, "DaylightMogul's profession window is in use.")
    T.eq(note.hidden(function() end), false, "shown while Mogul owns it")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    _G.DaylightMogul = nil
end)

T.test("craft: an absent, older, unsure or broken DaylightMogul leaves ours as it is", function()
    local cases = {
        { nil, "absent" },
        { mogul({ 1, 2 }, function() return true end), "API 1.2: no Craft yet" },
        { mogul({ 1, 3 }, function() return false end), "says it doesn't own it" },
        { mogul({ 1, 3 }, function() error("boom") end), "Owns errors" },
        { mogul({ 1, 3 }, nil), "no Owns" },
        { mogul("junk", function() return true end), "a junk version" },
        { { API = "junk" }, "a junk API" },
    }
    for _, c in ipairs(cases) do
        stub.Load({ before = function() PW.world({})(); _G.DaylightMogul = c[1] end })
        T.eq(DaylightUI.craftOwnWindow, true, c[2])
        T.falsy(DaylightUI.craftMogul, c[2])
        T.truthy(stub.craft.Window.frame, c[2] .. ": ours built")
        for _, item in ipairs(stub.craft.OPTIONS.pages[1].groups[1].items) do
            if item.type == "text" then T.eq(item.hidden(function() end), true, c[2] .. ": no note") end
        end
        T.eq(#stub.errors, 0, tostring(stub.errors[1]))
    end
    _G.DaylightMogul = nil
end)

T.test("craftworld_cooldowns", function()
    local p = PW.Sample()
    p[1].recipes[2].cooldown = 3600
    load({ profs = p })
    PW.Open(197)
    local get = C_TradeSkillUI.GetRecipeCooldown
    T.isnil((get(102)), "no cooldown before a cast")
    C_TradeSkillUI.CraftRecipe(102, 1)
    PW.Cast()
    local cd, isDay, charges, max = get(102)
    T.eq(cd, 3600)
    T.eq(isDay, false)
    T.eq(charges, 0)
    T.eq(max, 0)
    T.isnil((get(101)), "a recipe with no cooldown stays free")
    PW.Cooldown(102, nil)
    T.isnil((get(102)), "cleared by hand")
end)

-- Skill-up chance: the client only says a recipe's color; the ranges are the game's
-- own data (Craft/SkillUps.lua), shown only while they agree with that color.
T.test("craft: each row shows its skill-up chance; gray and unknown ones none", function()
    local ns = load()
    ns.SkillUps[102] = 125 * 1000 + 175   -- Bolt of Silk Cloth: yellow 125, green 150, gray 175
    open(ns)
    local function chance(id)
        local b = ns.List.lines[id]
        return b.chance and b.chance:IsShown() and b.chance:GetText() or nil
    end
    T.eq(chance(101), "100%", "orange always gives a point")
    T.eq(chance(102), "54%", "yellow at 148: (175 - 148) / (175 - 125)")
    T.rgb({ ns.List.lines[102].chance:GetTextColor() }, { DaylightUI.Style.Accent() }, "a number that pops")
    T.isnil(chance(103), "gray: none")
    ns.SkillUps[102] = 160 * 1000 + 200   -- this range says orange at 148, the client says yellow
    ns.List.Soon()
    frame(2)
    T.isnil(chance(102), "a range that disagrees with the client's color shows nothing")
end)

T.test("craft: the picked recipe shows its range as a bar, your skill marked, and the chance", function()
    local ns = load()
    ns.SkillUps[102] = 125 * 1000 + 175
    open(ns)
    ns.Window.Pick(102)
    frame(10)
    local b = page(ns).recipe.stack.pools.range and page(ns).recipe.stack.pools.range[1]
    T.truthy(b and b:IsShown(), "the range piece")
    T.truthy(string.find(b.you:GetText(), "148", 1, true), "You: 148")
    T.truthy(string.find(b.odds:GetText(), "54%", 1, true), "the chance")
    local shown = 0
    for _, bar in ipairs(b.parts) do if bar:IsShown() then shown = shown + 1 end end
    T.eq(shown, 4, "orange, yellow, green and gray")
    T.eq(b.marks[1]:GetText(), "125"); T.eq(b.marks[2]:GetText(), "150"); T.eq(b.marks[3]:GetText(), "175")
    T.rgb({ b.marks[2]:GetTextColor() }, ns.Data.Color(ns.Data.EASY), "green's number in green")
    local tick = select(4, b.tick:GetPoint(1))
    local yellowAt = select(4, b.parts[2]:GetPoint(1))
    local greenAt = select(4, b.parts[3]:GetPoint(1))
    T.truthy(tick > yellowAt and tick < greenAt, "the marker sits in yellow")
    ns.Window.Pick(103)
    frame(10)
    T.falsy(b:IsShown(), "no range known: no bar")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
