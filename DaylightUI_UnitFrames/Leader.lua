-- The leader drawer: the tools the game's raid manager gives a group leader
-- (it's hidden along with the raid frames, see Blizzard.lua), restyled. A small
-- tab with a crown hugs the left screen edge (it has its own unlock handle,
-- and Shift-drag moves it anywhere). Clicking it sweeps a card out toward the
-- middle of the screen, like the minimap's addon drawer
-- (InfoPanel/Drawer.lua): ready check, role check, a pull timer, target
-- markers and world markers. The leader and raid assists see it while the
-- party or raid frames are up. With `leader.show` a party's tank, or anyone in
-- a party, sees it too: every member may mark, but ready check and pull stay
-- with the leader.
--
-- The markers are secure buttons (SecureActionButtonTemplate) so they work in
-- combat. That makes the card protected: it only sweeps and moves out of
-- combat, and combat starting mid-sweep finishes it instantly
-- (PLAYER_REGEN_DISABLED still allows that). In combat the tab's click shows
-- or hides the card from a secure snippet (Leader.TOGGLE), so a closed card
-- rests at its full size. Ready check, role check and the pull timer are game
-- calls that are blocked in combat and under the client's restrictions, so
-- they're plain buttons that dim then (the game's manager calls the same
-- functions from plain buttons).

local _, ns = ...
local DUI = DaylightUI
local Style, Motion, W = DUI.Style, DUI.Motion, DUI.Widgets
local L = DUI.L

local Leader = {}
ns.Leader = Leader

Leader.TAB = { 16, 44 }      -- the tab's width and height
Leader.CROWN = 12            -- the crown on it
Leader.SPACE = 6             -- gap between the tab and the card
Leader.MOVER = "unitframes.leader"
-- Hugs the left screen edge, halfway up (screen clamping keeps it flush).
Leader.HOME = { "LEFT", nil, "LEFT", 0, 0 }
Leader.WIDTH = 256           -- the card's width when open
Leader.PAD = 12              -- padding inside the card
Leader.GAP = 6               -- gap between buttons
Leader.SECTION_GAP = 12      -- gap between sections
Leader.TITLE_GAP = 6         -- gap from a section's title to its buttons
Leader.BUTTON_H = 24
Leader.MARK = 22             -- a marker square
Leader.MARK_GAP = 4
Leader.CLEAR_GAP = 8         -- the clear square sits a little further off
Leader.BORDER = 2
Leader.PULLS = { 5, 10, 15 } -- the pull timer's seconds
-- The rows ripple in like the map drawer's icons: the first this long after
-- the card, each next one this much later, rising this far.
Leader.LEAD, Leader.STAGGER, Leader.RISE = 0.03, 0.03, 4
-- Both marker rows run skull first, like the game's manager. Target markers
-- use their own number. World marker n uses target icon WORLD_ICON[n]
-- (1 square, 2 triangle, 3 diamond, 4 cross, 5 star, 6 circle, 7 moon,
-- 8 skull; the game's WORLD_RAID_MARKER_ORDER).
Leader.TARGET_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
Leader.WORLD_ORDER = { 8, 4, 1, 7, 2, 3, 6, 5 }
Leader.WORLD_ICON = { 6, 4, 3, 7, 1, 2, 5, 8 }
Leader.ICON = DUI.MEDIA .. "marker-%d.png"
Leader.CLEAR_ICON = DUI.MEDIA .. "marker-clear.png"

local tab, card, clip, inner, driver
local sections = {}          -- the card's rows, top first
local shown = {}             -- the rows currently on the card (layoutCard)
local anim = { t = 0 }

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function plainFlag(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not isSecret(v) and v == true
end

-- Any plain truthy answer (not nil, not false).
local function plainSome(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    return ok and not isSecret(v) and v ~= nil and v ~= false
end

local function ease(p)
    if p <= 0 then return 0 end
    if p >= 1 then return 1 end
    return 1 - (1 - p) ^ 3
end

-- Who and where

-- "leader", "assist" (in a raid), or nil.
function Leader.Rank()
    if not IsInGroup() then return nil end
    if plainFlag(UnitIsGroupLeader, "player") then return "leader" end
    if IsInRaid() and plainFlag(UnitIsGroupAssistant, "player") then return "assist" end
    return nil
end

-- Test mode with the raid or party samples showing. The tab shows beside them
-- as it would for a raid leader.
local function testing()
    return DUI.testMode == true and (DUI.TestPartShown("raid") or DUI.TestPartShown("party"))
end

-- The group frames shown now, or nil (then the game's own raid manager is
-- there, or there's no group).
function Leader.Holder(db)
    db = db or Leader.db
    if not db then return nil end
    local raid, party = ns.Raid.holder, ns.Party.holder
    if testing() then
        if DUI.TestPartShown("raid") and db.raid.enabled then return raid end
        return db.party.enabled and party or nil
    end
    if IsInRaid() or ns.Raid.InParty(db.raid) then return db.raid.enabled and raid or nil end
    return db.party.enabled and party or nil
end

-- Who may use it at all: anyone in a party (the game lets every member mark),
-- or a raid's leader and assists.
function Leader.MayOpen()
    if not IsInGroup() then return false end
    return not IsInRaid() or Leader.Rank() ~= nil
end

-- Whether you're this group's tank: the role you picked, else your spec's. The
-- role reads as secret on a restricted map, so the last plain answer is kept
-- and the tab doesn't vanish as you zone into a dungeon.
function Leader.Tanking()
    local ok, role = pcall(UnitGroupRolesAssigned, "player")
    if not ok or isSecret(role) then return Leader.tanking == true end
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = DUI.Installer.Role() end
    Leader.tanking = role == "TANK"
    return Leader.tanking
end

-- The Show leader tools setting, for someone who isn't leading.
local function shownToMember(db)
    if not Leader.MayOpen() then return false end
    local show = db.leader.show
    if show == "party" then return true end
    return show == "tank" and Leader.Tanking()
end

function Leader.Wanted(db)
    db = db or Leader.db
    if not (db and db.leader and db.leader.enabled) then return false end
    if not Leader.Holder(db) then return false end
    return testing() or Leader.Rank() ~= nil or (Leader.asked == true and Leader.MayOpen()) or shownToMember(db)
end

-- Where the card opens from the tab, toward the screen's middle. side is
-- "right" when the tab is left of the middle, else "left". down is true when
-- it's above the middle (the card hangs from its top), otherwise the card
-- rises from its bottom, so it stays on screen.
function Leader.Side(frame)
    local x, y
    if frame then x, y = frame:GetCenter() end
    if type(x) ~= "number" then return "right", true end
    local r = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local side = x * r <= UIParent:GetWidth() / 2 and "right" or "left"
    return side, y * r >= UIParent:GetHeight() / 2
end

-- The card's sweep

local function stagger()
    return Leader.STAGGER
end

-- A row at its point in the sweep: e = 0 (gone) to 1 (in place).
local function setRise(sec, e)
    sec:SetAlpha(e)
    local rise = Leader.RISE * (1 - e)
    if sec.rise == rise then return end
    sec.rise = rise
    sec:ClearAllPoints()
    sec:SetPoint("TOPLEFT", inner, "TOPLEFT", Leader.PAD, -sec.y - rise)
end

-- A hidden card at its full size. A click in combat can only show it, nothing
-- can resize it then. The next sweep starts from zero anyway.
local function rest()
    card:SetWidth(Leader.WIDTH)
    card:SetAlpha(1)
    for _, sec in ipairs(shown) do setRise(sec, 1) end
end

function Leader.Paint()
    if not card then return end
    local t, open, n = anim.t, Leader.open, #shown
    local w, alpha
    if open then
        w = Leader.WIDTH * ease(t / Motion.NORMAL)
        alpha = ease(t / Motion.FAST)
    else
        w = Leader.WIDTH * (1 - ease(t / Motion.CLOSE))
        alpha = 1 - ease((t - (Motion.CLOSE - Motion.FAST)) / Motion.FAST)
    end
    card:SetWidth(math.max(1, w))
    card:SetAlpha(alpha)
    for k, sec in ipairs(shown) do
        local e
        if open then
            e = ease((t - Leader.LEAD - (k - 1) * stagger()) / Motion.NORMAL)
        else
            e = 1 - ease((t - (n - k) * stagger() / 2) / Motion.FAST)
        end
        setRise(sec, e)
    end
end

local function length()
    if not Leader.open then return Motion.CLOSE end
    return Leader.LEAD + math.max(0, #shown - 1) * stagger() + Motion.NORMAL
end

-- Opened manually and closed again: the tab goes too, unless it's yours anyway.
function Leader.Unask()
    if Leader.open or not Leader.asked then return end
    Leader.asked = nil
    DUI.AfterCombat(Leader.Place, "leader:place")
end

local function finish()
    driver:SetScript("OnUpdate", nil)
    anim.t = length()
    Leader.Paint()
    card:SetShown(Leader.open == true)
    if not Leader.open then rest() end
    Leader.Unask()
end

local function tick(_, dt)
    -- PLAYER_REGEN_DISABLED already finished it. Nothing moves in combat.
    if InCombatLockdown() then return driver:SetScript("OnUpdate", nil) end
    anim.t = anim.t + dt
    if anim.t >= length() then return finish() end
    Leader.Paint()
end

local function paintTab()
    if not tab then return end
    local lit = Leader.open or tab:IsMouseOver()
    if lit then
        tab.crown:SetVertexColor(Style.Accent())
    else
        local c = Style.INK.LABEL
        tab.crown:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

local function start(open)
    local was = card:IsShown() and driver:GetScript("OnUpdate") ~= nil
    local share = math.min(1, math.max(0, (card:GetWidth() or 0) / Leader.WIDTH))
    Leader.open = open
    if was then
        -- Reversed partway, so continue from the card's current width.
        anim.t = open and Motion.NORMAL * (1 - (1 - share) ^ (1 / 3)) or Motion.CLOSE * (1 - share ^ (1 / 3))
    else
        anim.t = 0
    end
    card:Show()
    paintTab()
    if not Motion.On() then return finish() end
    Leader.Paint()
    driver:SetScript("OnUpdate", tick)
end

-- Out of combat only, since the card holds secure buttons.
function Leader.Open()
    if not card or Leader.open or InCombatLockdown() then return end
    Leader.Refresh()
    start(true)
end

function Leader.Close(now)
    if not card or not Leader.open or InCombatLockdown() then return end
    start(false)
    if now then finish() end
end

function Leader.Toggle()
    if Leader.open then Leader.Close() else Leader.Open() end
end

function Leader.IsOpen() return Leader.open == true end

-- What's on it

local function title(sec, text)
    sec.title = Style.Text(sec, Style.SIZE.small, "LEFT")
    sec.title:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, 0)
    sec.title:SetText(string.upper(text))
    Style.InkText(sec.title, "pop")
    return Style.SIZE.small + Leader.TITLE_GAP
end

local function newSection(text)
    local sec = CreateFrame("Frame", nil, inner)
    sec:SetWidth(Leader.WIDTH - 2 * Leader.PAD)
    sec.top = text and title(sec, text) or 0
    sections[#sections + 1] = sec
    return sec
end

-- A row of plain buttons sharing the row's width.
local function buttonRow(sec, list)
    local n, w = #list, sec:GetWidth()
    local bw = (w - (n - 1) * Leader.GAP) / n
    for i, it in ipairs(list) do
        local b = W.Button(sec, it.text, Leader.BUTTON_H)
        b:SetWidth(bw)
        b:SetPoint("TOPLEFT", sec, "TOPLEFT", (i - 1) * (bw + Leader.GAP), -sec.top)
        b:SetScript("OnClick", it.click)
        if it.tip then
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                DUI.Tips.Clear()
                DUI.Tips.Title(it.text)
                DUI.Tips.Text(it.tip)
                DUI.Tips.Flush(GameTooltip)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        it.button = b
    end
    sec:SetHeight(sec.top + Leader.BUTTON_H)
end

local function markTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    DUI.Tips.Clear()
    DUI.Tips.Title(self.tipTitle)
    for _, h in ipairs(self.tipHints) do DUI.Tips.Hint(h) end
    DUI.Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function markButton(sec, name, icon, x)
    local b = CreateFrame("Button", name, sec, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetSize(Leader.MARK, Leader.MARK)
    b:SetPoint("TOPLEFT", sec, "TOPLEFT", x, -sec.top)
    Style.Shell(b, { borderPx = Leader.BORDER, noBevel = true })
    local T = DUI.Pixel.Px(b, Leader.BORDER)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(icon)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", T, -T)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -T, T)
    b:SetScript("OnEnter", markTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("OnMouseDown", function(self) Motion.Bump(self.icon, 0.88) end)
    return b
end

local function markerName(i)
    return _G["RAID_TARGET_" .. i] or tostring(i)
end

local function markerRow(sec, prefix, order, iconOf, setup, clearSetup)
    local x = 0
    for k, n in ipairs(order) do
        local b = markButton(sec, prefix .. k, Leader.ICON:format(iconOf(n)), x)
        setup(b, n)
        x = x + Leader.MARK + Leader.MARK_GAP
    end
    local c = markButton(sec, prefix .. "Clear", Leader.CLEAR_ICON, x - Leader.MARK_GAP + Leader.CLEAR_GAP)
    clearSetup(c)
    sec:SetHeight(sec.top + Leader.MARK)
end

-- The tab's click in combat, in the restricted environment. "fight" is our own
-- flag (set on combat events), not the snippet's PlayerInCombat, which reads
-- UnitAffectingCombat. That can differ from the lockdown the tab's own OnClick
-- checks, and both would toggle.
Leader.TOGGLE = [[
    if self:GetAttribute("fight") then
        local card = self:GetFrameRef("card")
        if card:IsShown() then card:Hide() else card:Show() end
    end
]]

local function build()
    tab = CreateFrame("Button", "DaylightUILeaderTab", UIParent, "SecureHandlerStateTemplate")
    tab:SetSize(Leader.TAB[1], Leader.TAB[2])
    tab:SetFrameStrata("LOW")
    Style.Shell(tab, { borderPx = Leader.BORDER })
    tab.crown = tab:CreateTexture(nil, "OVERLAY")
    tab.crown:SetTexture(DUI.MEDIA .. ns.UF.STATUS.leader.file)
    tab.crown:SetSize(Leader.CROWN, Leader.CROWN)
    tab.crown:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab:RegisterForDrag("LeftButton")
    -- Shift-drag moves it (out of combat only, since the card is protected).
    -- It stays where it's dropped, as in unlock mode.
    tab:SetScript("OnDragStart", function(self)
        if InCombatLockdown() or not IsShiftKeyDown() then return end
        self.moving = true
        GameTooltip:Hide()
        Leader.Close()
        self:StartMoving()
    end)
    tab:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = nil
        self:StopMovingOrSizing()
        -- The click from releasing the drag isn't a real click.
        self.dropped = GetTime()
        DUI.Movers.Save(Leader.MOVER, true)
    end)
    tab:SetScript("OnClick", function(self)
        if self.dropped == GetTime() then return end
        Motion.Bump(self.crown, 0.85)
        DUI.Sound.Play("click")
        if InCombatLockdown() then
            -- The snippet already did it, so just update our own flag.
            Leader.open = card:IsShown()
            return paintTab()
        end
        Leader.Toggle()
    end)
    tab:SetScript("OnEnter", function(self)
        paintTab()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        DUI.Tips.Clear()
        DUI.Tips.Title(L["Leader tools"])
        DUI.Tips.Hint(Leader.open and L["Click: close"] or L["Click: open"])
        if not InCombatLockdown() then DUI.Tips.Hint(L["Shift-drag: move"]) end
        DUI.Tips.Flush(GameTooltip)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function()
        paintTab()
        GameTooltip:Hide()
    end)
    tab:Hide()

    card = CreateFrame("Frame", "DaylightUILeaderCard", tab)
    card:SetFrameLevel(tab:GetFrameLevel() + 2)
    Style.Shell(card, { window = true })
    card:Hide()
    clip = CreateFrame("Frame", nil, card)
    clip:SetAllPoints(card)
    clip:SetClipsChildren(true)
    inner = CreateFrame("Frame", nil, clip)
    inner:SetWidth(Leader.WIDTH)
    driver = CreateFrame("Frame", nil, card)
    tab:SetFrameRef("card", card)
    SecureHandlerWrapScript(tab, "OnClick", tab, Leader.TOGGLE)

    local ready = newSection(L["Ready"])
    Leader.readyButtons = {
        { text = READY_CHECK or L["Ready check"], click = function() Leader.ReadyCheck() end },
        { text = ROLE_POLL or L["Role check"], click = function() InitiateRolePoll() end,
          tip = L["Asks everyone to pick tank, healer or damage."] },
    }
    buttonRow(ready, Leader.readyButtons)

    local pull = newSection(L["Pull timer"])
    Leader.pullButtons = {}
    for _, s in ipairs(Leader.PULLS) do
        Leader.pullButtons[#Leader.pullButtons + 1] = {
            text = tostring(s),
            click = function() Leader.Countdown(s) end,
            tip = string.format(L["Counts down %d seconds for the whole group."], s),
        }
    end
    Leader.pullButtons[#Leader.pullButtons + 1] = { text = CANCEL or L["Cancel"], click = function() Leader.Countdown(0) end }
    buttonRow(pull, Leader.pullButtons)

    local target = newSection(L["Target markers"])
    markerRow(target, "DaylightUILeaderTarget", Leader.TARGET_ORDER, function(n) return n end,
        function(b, n)
            -- Same as the marker bar, which works in game: the marker's own command.
            b:SetAttribute("type", "macro")
            b:SetAttribute("macrotext", "/tm " .. n)
            b.tipTitle = markerName(n)
            b.tipHints = { L["Click: mark your target"] }
        end,
        function(c)
            c:SetAttribute("type", "macro")
            c:SetAttribute("macrotext", "/tm 0")
            c.tipTitle = L["Clear marker"]
            c.tipHints = { L["Click: take your target's marker off"] }
        end)

    local world = newSection(L["World markers"])
    markerRow(world, "DaylightUILeaderWorld", Leader.WORLD_ORDER, function(n) return Leader.WORLD_ICON[n] end,
        function(b, n)
            -- The game's own secure action (worldmarker in SecureTemplates.lua).
            b:SetAttribute("type", "worldmarker")
            b:SetAttribute("marker", n)
            b:SetAttribute("action1", "set")
            b:SetAttribute("action2", "clear")
            b.tipTitle = markerName(Leader.WORLD_ICON[n])
            b.tipHints = { L["Click: place it on the ground"], L["Right-click: take it away"] }
        end,
        function(c)
            c:SetAttribute("type", "worldmarker")
            c:SetAttribute("action", "clear")
            c.tipTitle = L["Clear world markers"]
            c.tipHints = { L["Click: take every world marker away"] }
        end)

    Leader.tab, Leader.card, Leader.driver = tab, card, driver
    -- Its handle shows while the tools are on and the group frames are up.
    DUI.Movers.Register(tab, Leader.MOVER, "Leader Tools", Leader.HOME, {
        active = function()
            local db = Leader.db
            return db ~= nil and db.leader.enabled == true and Leader.Holder(db) ~= nil
        end,
    })
end

-- Lays the rows down the card and sizes it. Out of combat only.
local function layoutCard()
    local y = Leader.PAD
    wipe(shown)
    for _, sec in ipairs(sections) do
        sec.y = y
        sec.rise = nil
        y = y + sec:GetHeight() + Leader.SECTION_GAP
        shown[#shown + 1] = sec
    end
    local h = y - Leader.SECTION_GAP + Leader.PAD
    inner:SetHeight(h)
    card:SetHeight(h)
end

-- The game's countdown, remembered so the pull timer recognizes our own. In
-- practice mode (test mode, no group) the pull timer runs on its own.
function Leader.Countdown(seconds)
    if Leader.Practicing() then return ns.Pull.Start(seconds) end
    if not C_PartyInfo then return end
    Leader.sent = { at = GetTime(), seconds = seconds }
    C_PartyInfo.DoCountdown(seconds)
end

function Leader.ReadyCheck()
    if Leader.Practicing() then return Leader.PracticeReady() end
    if C_PartyInfo then C_PartyInfo.DoReadyCheck() end
end

-- Practice: test mode's sample group, with no group of your own. Ready check
-- and the pull timer run on the samples instead of asking the game, which has
-- no group to ask. /dui leader runs both.

Leader.PRACTICE_ANSWERS = 3  -- sample answers trickle in over this many seconds
Leader.PRACTICE_END = 4      -- when the sample check ends
Leader.PRACTICE_PULL = 5     -- /dui leader: the pull starts this long after the check
Leader.PRACTICE_SECONDS = 10

local practice = 0           -- each practice run's number; a newer run or test mode ending stops the old one

function Leader.Practicing()
    return DUI.testMode == true and not IsInGroup()
end

local function sampleTiles()
    local list = {}
    for _, g in ipairs({ ns.Raid.group, ns.Party.group }) do
        for _, b in ipairs(g and g.preview or {}) do
            if b:IsShown() and type(b.test) == "table" then list[#list + 1] = b end
        end
    end
    return list
end

-- A ready check on the sample tiles: everyone starts "waiting", then most answer
-- ready, some not, and a few never do (not ready once it ends). They clear
-- READY_HOLD seconds later, like a real check.
function Leader.PracticeReady()
    practice = practice + 1
    local mine, tiles = practice, sampleTiles()
    local function set(b, status)
        if mine ~= practice or not DUI.testMode or type(b.test) ~= "table" then return end
        b.test.ready = status
        ns.UF.UpdateReady(b, b.test, true)
    end
    for _, b in ipairs(tiles) do
        set(b, "waiting")
        local roll = math.random()
        if roll > 0.125 then
            local answer = roll > 0.25 and "ready" or "notready"
            C_Timer.After(0.3 + math.random() * Leader.PRACTICE_ANSWERS, function() set(b, answer) end)
        end
    end
    C_Timer.After(Leader.PRACTICE_END, function()
        local all = true
        for _, b in ipairs(tiles) do
            if type(b.test) == "table" and b.test.ready == "waiting" then set(b, "notready") end
            if type(b.test) ~= "table" or b.test.ready ~= "ready" then all = false end
        end
        if all and mine == practice and DUI.testMode then ns.Moments.AllReady(tiles) end
    end)
    C_Timer.After(Leader.PRACTICE_END + ns.UF.READY_HOLD, function()
        for _, b in ipairs(tiles) do set(b, nil) end
    end)
end

-- /dui leader test [party]: the sample raid (or party) with the drawer open, a
-- ready check, then a pull.
function Leader.Practice(kind)
    if IsInGroup() then
        DUI.Print(L["You're in a group: the leader tools work for real. Leave the group to practice with sample members."])
        return
    end
    if not DUI.SetTestSolo({ kind == "party" and "party" or "raid" }) then return end
    -- Test mode lays the samples out after its combat check, so wait a frame.
    C_Timer.After(0, function()
        if not Leader.Practicing() then return end
        Leader.Open()
        Leader.PracticeReady()
        local mine = practice
        C_Timer.After(Leader.PRACTICE_PULL, function()
            if mine == practice and Leader.Practicing() then ns.Pull.Start(Leader.PRACTICE_SECONDS) end
        end)
    end)
end

-- /dui leader: opens or closes the drawer, for whoever may use it now.
function Leader.Command()
    if InCombatLockdown() then
        DUI.Print(L["The leader tools open after the fight."])
        return
    end
    if Leader.open then return Leader.Close() end
    local db = Leader.db
    if not (db and db.leader and db.leader.enabled) then
        DUI.Print(L["The leader tools are off: Unit Frames > Raid > Leader tools."])
        return
    end
    if not testing() then
        if not IsInGroup() then
            DUI.Print(L["Join a group to use the leader tools, or try them with /dui leader test."])
            return
        end
        if not Leader.MayOpen() then
            DUI.Print(L["In a raid, only the leader and assists can use the leader tools."])
            return
        end
    end
    if not Leader.Holder(db) then
        DUI.Print(L["The leader tools sit beside Daylight UI's party or raid frames, which are off."])
        return
    end
    Leader.asked = true
    if not tab then build() end
    Leader.Place()
    Leader.Open()
end

DUI.RegisterCommand("leader", function(rest)
    local word, kind = string.match(string.lower(rest or ""), "^(%S*)%s*(%S*)")
    if word == "test" then return Leader.Practice(kind) end
    Leader.Command()
end, L["/dui leader - open or close the leader tools; /dui leader test (or test party) tries them with sample members"])

-- What can be pressed now. The game's calls wait out combat and the client's
-- restrictions. Role check isn't for a finder group or a battleground (the
-- game's manager has the same rule).
function Leader.Refresh()
    if not card then return end
    -- A party member who opened it manually only gets the markers.
    local blocked = DUI.Restricted() or not (Leader.Rank() ~= nil or Leader.Practicing())
    for _, it in ipairs(Leader.readyButtons) do it.button.SetOff(blocked) end
    for _, it in ipairs(Leader.pullButtons) do it.button.SetOff(blocked) end
    -- UnitInBattleground returns the player's slot number, or nil.
    local noPoll = plainFlag(HasLFGRestrictions) or plainSome(UnitInBattleground, "player")
    -- Practice has no group to ask.
    Leader.readyButtons[2].button.SetOff(blocked or noPoll or Leader.Practicing())
    paintTab()
end

-- Shows or hides the tab (its position comes from its mover) and points the
-- card toward the screen's middle. Out of combat only.
function Leader.Place()
    if not tab then return end
    local db = Leader.db
    if not Leader.Wanted(db) then
        if driver then driver:SetScript("OnUpdate", nil) end
        local function gone()
            Leader.open = false
            card:Hide()
            rest()
            tab:Hide()
        end
        if not tab:IsShown() or not Motion.On() then return gone() end
        -- Fades away along with the card, then hides out of combat.
        tab.leaving = true
        Motion.Fade(tab, tab:GetAlpha(), 0, Motion.FAST)
        C_Timer.After(Motion.FAST, function()
            if tab.leaving and not InCombatLockdown() then gone() end
        end)
        return
    end
    tab.leaving = nil
    local side, down = Leader.Side(tab)
    Leader.side = side
    local v = down and "TOP" or "BOTTOM"
    card:ClearAllPoints()
    inner:ClearAllPoints()
    if side == "right" then
        card:SetPoint(v .. "LEFT", tab, v .. "RIGHT", Leader.SPACE, 0)
        inner:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
    else
        card:SetPoint(v .. "RIGHT", tab, v .. "LEFT", -Leader.SPACE, 0)
        inner:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
    end
    Style.LayoutShell(Style.GetShell(tab))
    layoutCard()
    Style.LayoutShell(Style.GetShell(card))
    if not tab:IsShown() or tab:GetAlpha() < 1 then
        local from = tab:IsShown() and tab:GetAlpha() or 0
        tab:SetAlpha(from)
        tab:Show()
        Motion.Fade(tab, from, 1, Motion.NORMAL)
    end
    if Leader.open then
        anim.t = length()
        Leader.Paint()
    elseif not card:IsShown() then
        rest()
    end
    Leader.Refresh()
end

function Leader.Apply(db)
    Leader.db = db
    DUI.AfterCombat(function()
        -- Created once the tools are on, so unlock mode has its handle.
        if not tab and db.leader.enabled then build() end
        Leader.Place()
        DUI.Movers.Recheck(Leader.MOVER)
    end, "leader:place")
end

local function replace()
    if Leader.db then Leader.Apply(Leader.db) end
end

-- A filling raid sends dozens of roster updates at once, so place once on the
-- next frame (Units.lua's later() does the same for the tiles).
local replaceDue = false
local function replaceSoon()
    if replaceDue then return end
    replaceDue = true
    C_Timer.After(0, function()
        replaceDue = false
        replace()
    end)
end

-- Combat finishes a sweep instantly (protected changes are still allowed during
-- this event), then the game's calls dim.
DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if driver and driver:GetScript("OnUpdate") then finish() end
    if tab then tab:SetAttribute("fight", true) end
    Leader.Refresh()
end)
DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if tab then tab:SetAttribute("fight", nil) end
    Leader.Unask()
    Leader.Refresh()
end)
DUI.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function() Leader.Refresh() end)
DUI.RegisterEvent("PARTY_LEADER_CHANGED", replaceSoon)
DUI.RegisterEvent("GROUP_ROSTER_UPDATE", replaceSoon)
DUI.RegisterEvent("PLAYER_ROLES_ASSIGNED", replaceSoon)
DUI.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", replaceSoon)
DUI.RegisterEvent("PLAYER_ENTERING_WORLD", replace)
DUI.On("MoverApplied", function(key)
    if key == "unitframes.raid" or key == "unitframes.party" or key == Leader.MOVER then replace() end
end)
DUI.On("TestModeChanged", function(on)
    if not on then practice = practice + 1 end
    replace()
end)
DUI.On("StyleChanged", function()
    if not card then return end
    for _, sec in ipairs(sections) do
        if sec.title then Style.InkText(sec.title, "pop") end
    end
    paintTab()
end)
