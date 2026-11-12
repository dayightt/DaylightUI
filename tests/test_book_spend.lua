local stub = require("stub")
local BW = require("bookworld")

-- Spending talent points on the talents page (Book/Spend.lua, Talents.lua,
-- Arrows.lua): the game's own staging calls and rules (bookworld plays the game's
-- side), the arrow fill and wake, Apply and Undo, and the talent sets.

local function load(spec)
    spec = spec or {}
    stub.Load({ before = function()
        BW.world(spec)()
        DaylightUIDB = { profileData = { ["DPS/Tank"] = { modules = { Book = { enabled = true } } } } }
    end })
    return stub.book
end

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

local function openTalents(ns)
    BW.Open(BW.TALENTS)
    frame(30)
    return ns.Window.frame.pages.talents
end

local function tileOf(page, name)
    for _, box in ipairs(page.trees) do
        for _, b in ipairs(box.tiles) do
            if b:IsShown() and b.node and b.node.name == name then return b, box end
        end
    end
end

local function arrowFrom(page, name)
    local _, box = tileOf(page, name)
    for _, a in ipairs(box.links) do if a.from.name == name then return a end end
end

local function apply(page) return page.actions.buttons[1] end
local function undo(page) return page.actions.buttons[2] end

T.test("book spend: a click buys a rank through the game (green until applied)", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    T.truthy(apply(page).spec.off, "nothing to apply yet")
    T.truthy(undo(page).spec.off)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    T.deq(BW.Calls("PurchaseRank")[1], { BW.CONFIG, 105938 })
    frame(2)
    local b = tileOf(page, "Booming Voice")
    T.eq(b.rank:GetText(), "1/5")
    T.truthy(b.node.staged, "green: not applied yet")
    T.rgb({ b.arc[1]:GetVertexColor() }, ns.Talents.STAGED)
    T.eq(page.foot.left:GetText(), "2")
    T.eq(apply(page).spec.off, false, "Apply wakes up")
    T.eq(undo(page).spec.off, false)
end)

T.test("book spend: the ring is a clock of the ranks; a point sweeps the next slice in, a take-back unwinds it", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    local b = tileOf(page, "Booming Voice")
    T.eq(b.arcAt, 0)
    T.falsy(b.arc[1]:IsShown(), "no ranks: no light")
    b:Click("LeftButton")
    frame(2)
    T.truthy(b.sweeping, "the slice sweeps in")
    T.truthy(b.tip:IsShown(), "behind a bright tip")
    T.truthy(b.arcAt > 0 and b.arcAt < 0.2)
    frame(20)
    T.falsy(b.sweeping)
    T.near(b.arcAt, 0.2)
    T.falsy(b.tip:IsShown())
    T.eq(b.swept, 1)
    T.truthy(b.arc[1]:IsShown(), "lit from the top's middle")
    T.truthy(b.arc[2]:IsShown(), "a fifth turns the first corner")
    T.falsy(b.arc[3]:IsShown(), "but not the second")
    b:Click("RightButton")
    frame(2)
    T.truthy(b.sweeping, "taken back: it unwinds")
    frame(20)
    T.eq(b.arcAt, 0)
    T.falsy(b.arc[1]:IsShown())
    -- A full ring lights all five pieces.
    for _ = 1, 3 do b:Click("LeftButton") ; frame(20) end
    T.near(b.arcAt, 0.6)
    T.truthy(b.arc[3]:IsShown(), "three fifths reach the bottom")
end)

T.test("book spend: Apply's gold light rolls down the tree, turning each learned talent gold as it passes", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(20)
    apply(page):Click()
    stub.Advance(BW.COMMIT_DELAY)
    frame(2)
    local b, box = tileOf(page, "Booming Voice")
    T.falsy(b.node.staged, "the server said yes")
    T.truthy(box.wave:IsShown(), "the band rolls down")
    T.rgb({ b.arc[1]:GetVertexColor() }, ns.Talents.STAGED, "still green until the light reaches it")
    T.falsy(b.shone)
    frame(30)
    T.eq(b.shone, 1)
    T.falsy(box.wave:IsShown())
    T.isnil(ns.Talents.wave)
    T.falsy(ns.Talents.Staged(b.node))
end)

T.test("book spend: a point spent and a point taken back sound different", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    local heard = {}
    _G.PlaySoundFile = function(file) heard[#heard + 1] = file end
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    stub.Advance(0.2)
    tileOf(page, "Booming Voice"):Click("RightButton")
    frame(2)
    _G.PlaySoundFile = nil
    local F = DaylightUI.Sound.FILES
    T.eq(heard[1], F.spend)
    T.eq(heard[#heard], F.refund)
end)

T.test("book spend: Apply's chime plays once the server says yes, never on a no", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    local heard = {}
    _G.PlaySoundFile = function(file) heard[#heard + 1] = file end
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    BW.state.commitFails = true
    apply(page):Click()
    stub.Advance(BW.COMMIT_DELAY)
    frame(2)
    local function apples()
        local n = 0
        for _, f in ipairs(heard) do if f == DaylightUI.Sound.FILES.apply then n = n + 1 end end
        return n
    end
    T.eq(apples(), 0, "refused: silent")
    BW.state.commitFails = false
    apply(page):Click()
    T.eq(apples(), 0, "not before the answer")
    stub.Advance(BW.COMMIT_DELAY)
    frame(2)
    T.eq(apples(), 1)
    _G.PlaySoundFile = nil
end)

T.test("book spend: Apply's light rolls when the server answers inside the call", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    BW.state.commitInstant = true
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(20)
    apply(page):Click()
    frame(2)
    local _, box = tileOf(page, "Booming Voice")
    T.falsy(ns.Spend.committing, "the answer was taken")
    T.truthy(box.wave:IsShown(), "the band rolls down")
end)

T.test("book spend: Apply's light rolls when the answer names the active config", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    BW.state.activeConfig = BW.CONFIG + 1000
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(20)
    apply(page):Click()
    stub.Advance(BW.COMMIT_DELAY)
    frame(2)
    local _, box = tileOf(page, "Booming Voice")
    T.falsy(ns.Spend.committing, "the answer was taken")
    T.truthy(box.wave:IsShown(), "the band rolls down")
end)

T.test("book spend: a staged talent is green and Apply's light rolls when the game's active rank counts staged points", function()
    local ns = load({ tree = { left = 3 } })
    BW.state.activeFollows = true
    local page = openTalents(ns)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(20)
    local b = tileOf(page, "Booming Voice")
    T.truthy(b.node.staged, "the game's GetStagedChanges lists it")
    apply(page):Click()
    stub.Advance(BW.COMMIT_DELAY)
    frame(2)
    local _, box = tileOf(page, "Booming Voice")
    T.truthy(box.wave:IsShown(), "the band rolls down")
end)

T.test("book spend: a refused click shakes and calls nothing", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    local b = tileOf(page, "Mortal Strike")
    local x = select(4, b:GetPoint(1))
    b:Click("LeftButton")
    T.eq(#BW.Calls("PurchaseRank"), 0, "a locked talent: the game isn't asked")
    frame(3)
    T.truthy(select(4, b:GetPoint(1)) ~= x, "the small shake")
    frame(20)
    T.eq(select(4, b:GetPoint(1)), x, "back in its place")
    -- No points left: refused before the game is asked (its CanAfford).
    BW.tree.left = 0
    stub.FireEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", BW.TREE)
    frame(2)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    T.eq(#BW.Calls("PurchaseRank"), 0, "no points: nothing bought")
end)

T.test("book spend: right-click takes back a green point; an applied one stays", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    tileOf(page, "Booming Voice"):Click("RightButton")
    T.deq(BW.Calls("RefundRank")[1], { BW.CONFIG, 105938, false })
    frame(2)
    T.eq(tileOf(page, "Booming Voice").rank:GetText(), "0/5")
    T.eq(page.foot.left:GetText(), "3")
    -- Cruelty's 2 points are applied, and Forever refuses taking them back.
    tileOf(page, "Cruelty"):Click("RightButton")
    T.eq(#BW.Calls("RefundRank"), 1, "the game isn't asked")
    T.eq(tileOf(page, "Cruelty").rank:GetText(), "2/5")
end)

T.test("book spend: Undo is the game's RollbackConfig", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    undo(page):Click()
    T.deq(BW.Calls("RollbackConfig")[1], { BW.CONFIG })
    frame(10)   -- the points left count back up
    T.eq(tileOf(page, "Booming Voice").rank:GetText(), "0/5")
    T.eq(page.foot.left:GetText(), "3")
    T.truthy(undo(page).spec.off, "nothing left to undo")
end)

T.test("book spend: Apply sends them (CommitConfig(nil)); learned talents shine once the server says yes", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    apply(page):Click()
    T.eq(#BW.Calls("CommitConfig"), 1)
    T.isnil(BW.Calls("CommitConfig")[1][1], "the game's own Apply on Forever: no loadout")
    -- While it's on its way the game refuses more (IsCommitInProgress).
    tileOf(page, "Booming Voice"):Click("LeftButton")
    T.eq(#BW.Calls("PurchaseRank"), 1, "no buying mid-Apply")
    T.truthy(apply(page).spec.off)
    stub.Advance(BW.COMMIT_DELAY)
    frame(30)
    local b = tileOf(page, "Booming Voice")
    T.falsy(b.node.staged, "applied: gold now")
    T.eq(b.shone, 1, "the shine ran over it")
    T.falsy(tileOf(page, "Cruelty").shone, "only what was just learned")
    T.truthy(apply(page).spec.off)
end)

T.test("book spend: a failed Apply keeps the green points and shines nothing", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    BW.state.commitFails = true
    apply(page):Click()
    stub.Advance(BW.COMMIT_DELAY)
    frame(2)
    local b = tileOf(page, "Booming Voice")
    T.truthy(b.node.staged)
    T.falsy(b.shone)
    T.eq(apply(page).spec.off, false, "try again")
end)

T.test("book spend: in combat Apply is grayed with the game's reason", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    stub.EnterCombat()
    frame(2)
    T.truthy(apply(page).spec.off)
    T.eq(page.actions.why, "You can't do that while in combat.")
    apply(page):Click()
    T.eq(#BW.Calls("CommitConfig"), 0)
    stub.LeaveCombat()
    frame(2)
    T.eq(apply(page).spec.off, false)
end)

T.test("book spend: a talent's last rank fills its arrow, then wakes the talent it opens; Undo drains it", function()
    -- 25 in Fury: Death Wish (row 4) can be learned, and Flurry's row (5) is
    -- reached but waits on Death Wish's arrow.
    local nodes = BW.WarriorNodes()
    local ranks = { [105938] = 5, [105939] = 5, [105937] = 5, [105934] = 3, [105931] = 5, [105932] = 2 }
    for _, n in ipairs(nodes) do if n.group == BW.FURY then n.rank = ranks[n.id] end end
    local ns = load({ tree = { nodes = nodes, left = 5 } })
    local page = openTalents(ns)
    local a = arrowFrom(page, "Death Wish")
    T.eq(a.state, "off")
    local flurry = tileOf(page, "Flurry")
    tileOf(page, "Death Wish"):Click("LeftButton")
    frame(2)
    T.falsy(a.running, "Death Wish's ring closes first")
    frame(13)
    T.truthy(a.running, "then light runs down from Death Wish")
    frame(6)
    T.truthy(a.head.__vertex[2] > DaylightUI.Book.Arrows.OFF[2] + 0.1, "the light reaches the head")
    T.falsy(flurry.woke, "Flurry waits for the light")
    frame(30)
    T.eq(a.state, "staged", "green: not applied yet")
    T.falsy(a.lit[1]:IsShown())
    T.eq(flurry.woke, 1, "Flurry pops awake once the light lands")
    undo(page):Click()
    frame(2)
    T.truthy(a.running, "Undo drains it")
    frame(30)
    T.eq(a.state, "off")
end)

T.test("book spend: a full arrow glows and a spark runs down it to a bloom on its head", function()
    local nodes = BW.WarriorNodes()
    local ranks = { [105938] = 5, [105939] = 5, [105937] = 5, [105934] = 3, [105931] = 5, [105932] = 2 }
    for _, n in ipairs(nodes) do if n.group == BW.FURY then n.rank = ranks[n.id] end end
    local ns = load({ tree = { nodes = nodes, left = 5 } })
    local page = openTalents(ns)
    local A = DaylightUI.Book.Arrows
    local a = arrowFrom(page, "Death Wish")
    T.falsy(a.halo[1]:IsShown(), "dark while the talent isn't full")
    tileOf(page, "Death Wish"):Click("LeftButton")
    frame(30)
    T.eq(a.state, "staged")
    T.truthy(a.halo[1]:IsShown(), "the light stays along it")
    local d = A.Driver(a.parent)
    T.truthy(d and d:IsShown(), "the driver runs while an arrow glows")
    stub.RunOnUpdate(d, 0.2)
    T.truthy(a.motes[1]:IsShown(), "a spark leaves as the fill lands")
    local _, _, _, _, y1 = a.motes[1]:GetPoint()
    stub.RunOnUpdate(d, 0.15)
    local _, _, _, _, y2 = a.motes[1]:GetPoint()
    T.truthy(y2 < y1, "it runs down")
    local bloomed
    for _ = 1, 20 do stub.RunOnUpdate(d, 0.03); bloomed = bloomed or a.bloom:IsShown() end
    T.truthy(bloomed, "it blooms on the head")
    stub.RunOnUpdate(d, A.REST / 2)
    T.falsy(a.motes[1]:IsShown(), "then rests")
    undo(page):Click()
    frame(30)
    T.falsy(a.halo[1]:IsShown(), "Undo puts the light out")
end)

T.test("book spend: a newly reached row wakes left to right", function()
    -- 9 in Fury: one more opens row 2 (Piercing Howl col 1, Blood Craze col 2).
    local nodes = BW.WarriorNodes()
    for _, n in ipairs(nodes) do
        if n.id == 105938 then n.rank = 5 end   -- Booming Voice 5
        if n.id == 105939 then n.rank = 4 end   -- Cruelty 4
    end
    local ns = load({ tree = { nodes = nodes, left = 3 } })
    local page = openTalents(ns)
    T.falsy(tileOf(page, "Piercing Howl").node.available)
    local woke, wake = {}, ns.Talents.Wake
    ns.Talents.Wake = function(b, delay) woke[#woke + 1] = { b.node.name, delay or 0 }; return wake(b, delay) end
    tileOf(page, "Cruelty"):Click("LeftButton")
    frame(2)
    ns.Talents.Wake = wake
    T.eq(#woke, 2)
    T.eq(woke[1][1], "Piercing Howl")
    T.eq(woke[2][1], "Blood Craze")
    T.truthy(woke[2][2] > woke[1][2], "left to right")
    T.eq(tileOf(page, "Blood Craze").woke, 1)
end)

T.test("book spend: Shift-click links the talent, buys nothing", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    _G.IsModifiedClick = function(what) return what == "CHATLINK" end
    tileOf(page, "Booming Voice"):Click("LeftButton")
    _G.IsModifiedClick = nil
    T.eq(#BW.Calls("PurchaseRank"), 0)
    T.truthy(BW.Calls("InsertLink")[1][1]:find("Booming Voice", 1, true))
end)

T.test("book spend: the tooltip says what a click does, in the game's words", function()
    local ns = load({ tree = { left = 3 }, before = function()
        local tip = CreateFrame("Frame", "GameTooltip", UIParent)
        _G.GameTooltip = tip
        function tip:SetOwner(o) self.__owner, self.__lines = o, {} end
        function tip:IsOwned(o) return self.__owner == o end
        function tip:AddLine(t) self.__lines[#self.__lines + 1] = t end
        function tip:AddDoubleLine(t) self.__lines[#self.__lines + 1] = t end
    end })
    _G.TALENT_BUTTON_TOOLTIP_PURCHASE_INSTRUCTIONS = "Click to learn"
    _G.TALENT_BUTTON_TOOLTIP_REFUND_INSTRUCTIONS = "Right-click to unlearn"
    local page = openTalents(ns)
    local function says(name, text)
        local b = tileOf(page, name)
        b:GetScript("OnEnter")(b)
        for _, l in ipairs(GameTooltip.__lines) do if tostring(l):find(text, 1, true) then return true end end
        return false
    end
    T.truthy(says("Booming Voice", "Click to learn"))
    T.falsy(says("Mortal Strike", "Click to learn"), "locked: no hint")
    tileOf(page, "Booming Voice"):Click("LeftButton")
    frame(2)
    T.truthy(says("Booming Voice", "Right-click to unlearn"))
    T.falsy(says("Cruelty", "Right-click"), "applied points: no take-back on Forever")
    _G.TALENT_BUTTON_TOOLTIP_PURCHASE_INSTRUCTIONS, _G.TALENT_BUTTON_TOOLTIP_REFUND_INSTRUCTIONS = nil, nil
end)

T.test("book spend: one talent set: Secondary is there but locked", function()
    local ns = load({ tree = { left = 3 } })
    local page = openTalents(ns)
    T.truthy(page.sets[2].off)
    page.sets[2]:Click()
    T.isnil(ns.Talents.group, "nothing to look at")
    T.truthy(page.sets[1].line:IsShown(), "Primary shown")
end)

T.test("book spend: dual spec: the other set shows locked with Activate, the switch is the game's", function()
    local tree2 = { left = 4, blank = true }
    local ns = load({ tree = { left = 3 }, dual = true, tree2 = tree2 })
    local page = openTalents(ns)
    T.falsy(page.sets[2].off)
    page.sets[2]:Click()
    frame(2)
    T.eq(ns.Talents.data.configID, BW.CONFIG2)
    T.eq(tileOf(page, "Cruelty").rank:GetText(), "0/5", "the second set's own tree")
    T.eq(page.foot.left:GetText(), "4")
    tileOf(page, "Booming Voice"):Click("LeftButton")
    T.eq(#BW.Calls("PurchaseRank"), 0, "a set not in use is locked (the game's IsLocked)")
    T.falsy(page.actions.buttons[2]:IsShown(), "only Activate")
    local heard = {}
    _G.PlaySoundFile = function(file) heard[#heard + 1] = file end
    page.actions.buttons[1]:Click()
    T.deq(BW.Calls("SetActiveSpecGroup")[1], { 2 })
    stub.Advance(BW.SWITCH_DELAY)
    frame(2)
    local n = 0
    for _, f in ipairs(heard) do if f == DaylightUI.Sound.FILES.apply then n = n + 1 end end
    _G.PlaySoundFile = nil
    T.eq(n, 1, "the switch's chime")
    T.isnil(ns.Talents.group, "the shown set is now the one in use")
    T.eq(ns.Talents.data.configID, BW.CONFIG2)
    T.truthy(page.sets[2].dot:IsShown(), "the dot marks the set in use")
end)

T.test("book spend: a second set never used: a calm note and Activate", function()
    local ns = load({ tree = { left = 3 }, dual = "new" })
    local page = openTalents(ns)
    page.sets[2]:Click()
    frame(2)
    T.truthy(page.note:IsShown())
    T.truthy(page.actions.frame:IsShown())
    page.actions.buttons[1]:Click()
    T.deq(BW.Calls("SetActiveSpecGroup")[1], { 2 })
end)

T.test("book spend: the window opens on the set in use again", function()
    local ns = load({ tree = { left = 3 }, dual = true })
    local page = openTalents(ns)
    page.sets[2]:Click()
    frame(2)
    BW.Escape()
    frame(20)
    BW.Open(BW.TALENTS)
    frame(30)
    T.isnil(ns.Talents.group)
    T.eq(ns.Talents.data.configID, BW.CONFIG)
end)
