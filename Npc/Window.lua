-- NPC window: one talk window for everything an NPC opens, built on the window kit.
-- GossipFrame and QuestFrame are parked out of sight (Win.Follow) but still decide when
-- the talk opens and ends. Pages are built from the game's latest event, since the
-- parked panels never run their OnShow.
--
-- Hand-off: picking a quest from gossip makes the game close the gossip and open the
-- quest a moment later (GOSSIP_CLOSED with interactionIsContinuing). The window holds
-- for up to Npc.HANDOFF s with the header still and the page dimmed, then either the
-- next page lifts in or it closes softly. Vendor (Shop.lua) and trainer (Train.lua) are
-- one more entry in FRAMES plus their own page. In the immersive look the talk pages
-- show in the scene instead (Scene.lua, Npc.FrameFor).

local _, DUI = ...
DUI.Npc = DUI.Npc or {}
local ns = DUI.Npc
local L = DUI.L

local Npc = {}
ns.Window = Npc

Npc.NAME = "DaylightUINpc"
Npc.W, Npc.H = 400, 540
Npc.HANDOFF = 0.6
Npc.ANSWER_WAIT = 3  -- s before a page already answered can answer again if the server hasn't replied
Npc.REWARD_WAIT = 0.5 -- s a reward page with no choices waits before hand-in (choices can arrive just after)
Npc.WATCH_STEP = 0.1 -- s between checks while a quest page is new
Npc.WATCH_FOR = 5    -- s a new quest page keeps checking
Npc.ANSWERED = 1     -- s: pages another feature answered (QoL's auto accept) aren't shown
Npc.FOOT = 52        -- footer height under the page
Npc.TITLE_SIZE = DUI.Style.SIZE.title
Npc.COIN = DUI.MEDIA .. "coin-gold.png"   -- marks the reward that sells for the most
Npc.SAID_GAP = 12    -- extra px between the NPC's text and the quests or choices below
Npc.BUSY = { 0.95 * 0.85, 0.72 * 0.85, 0.32 * 0.85 }   -- quest in progress: INK.WARN, softened

Npc.FRAMES = {
    gossip = function() return _G.GossipFrame end,
    quest = function() return _G.QuestFrame end,
    merchant = function() return _G.MerchantFrame end,   -- vendor page (Shop.lua); `vendor` setting
    trainer = function() return _G.ClassTrainerFrame end, -- trainer page (Train.lua); `trainer` setting
}
-- Which game window each page belongs to, and which page shows it.
Npc.KIND = { gossip = "gossip", greeting = "quest", detail = "quest", progress = "quest", reward = "quest", merchant = "merchant", trainer = "trainer" }
Npc.PAGE = { merchant = "shop", trainer = "train" }
-- Game windows parked under the kit's veil instead of the hidden frame, because they're
-- checked with IsVisible on open. The trainer closes itself otherwise. Other addons
-- hook the vendor's OnShow and read IsVisible, and its own OnShow/OnHide handle bags
-- and the filter (Shop.lua).
Npc.VEIL = { trainer = true, merchant = true }
Npc.TRAINER_REFRESH = { TRAINER_UPDATE = true, TRAINER_SERVICE_INFO_NAME_UPDATE = true, PLAYER_MONEY = true }
Npc.EVENTS = { QUEST_GREETING = "greeting", QUEST_DETAIL = "detail", QUEST_PROGRESS = "progress", QUEST_COMPLETE = "reward" }

local Win = DUI.Win
local Parts = Win.Parts

function ns.Setting(key) return ns.module and ns.module.db and ns.module.db[key] end

local function now() return type(GetTime) == "function" and GetTime() or 0 end

-- Talk pages go to the immersive scene when it's on; vendor and trainer always use the
-- window.
function Npc.FrameFor(mode)
    if Npc.scene and ns.Setting("look") == "immersive" and not Npc.PAGE[mode] then return Npc.scene end
    return Npc.frame
end
-- The one showing now (the window when neither is).
local function cur() return Npc.open or Npc.frame end

-- Pages other features answered automatically (QoL's auto accept, turn-in, skip
-- gossip) never flash up.

local answered = {}
function DUI.TalkAnswered(event) answered[event] = now() end
local function wasAnswered(event)
    local t = answered[event]
    return t ~= nil and now() - t < Npc.ANSWERED
end

-- State

local S = { mode = nil, data = nil, choice = nil, confirm = false, holdUntil = 0, sentUntil = 0, rewardAt = 0, closed = {}, aside = {}, last = {} }
Npc.state = S

local function gameShown(kind)
    local get = Npc.frames and Npc.frames[kind]
    local f = get and get()
    return type(f) == "table" and f:IsShown() == true and Npc.follow ~= nil and Win.Followers.Parked(Npc.follow, kind)
        and not Win.Followers.Away(Npc.follow, kind)   -- another addon took it over
end

local function anyShown()
    for kind in pairs(Npc.frames or {}) do if gameShown(kind) then return true end end
    return false
end

-- Actions, always through the game's functions, never its frames.

local function hold() S.holdUntil = now() + Npc.HANDOFF end

-- One answer per page. The old page stays up until the next arrives, and a press
-- faster than the server must not answer a talk that has moved on. This uses
-- Npc.ANSWER_WAIT rather than Npc.HANDOFF because a page can take longer than HANDOFF,
-- and mashing Space once sent CompleteQuest twice. If the server never replies, the
-- lock frees after the wait.
local function firstPress()
    if now() < S.sentUntil then return false end
    S.sentUntil = now() + Npc.ANSWER_WAIT
    return true
end

function Npc.Goodbye()
    if S.sample then return Npc.Close() end
    if S.mode == "merchant" then
        if type(CloseMerchant) == "function" then CloseMerchant() end
    elseif S.mode == "trainer" then
        if type(CloseTrainer) == "function" then CloseTrainer() end
    elseif S.mode == "gossip" then
        if C_GossipInfo and C_GossipInfo.CloseGossip then C_GossipInfo.CloseGossip() end
    elseif S.mode then
        if type(CloseQuest) == "function" then CloseQuest() end
    end
    Npc.Close()
end

local function pickQuest(q)
    if S.sample then return Npc.Show(q.kind == "active" and "reward" or "detail", Npc.SampleQuest(q.kind == "active")) end
    -- A row from the previous page: the NPC moved on before the window did.
    if S.mode ~= "gossip" and not q.index then return end
    if not firstPress() then return end
    hold()
    if S.mode == "gossip" then
        if q.kind == "active" then C_GossipInfo.SelectActiveQuest(q.questID) else C_GossipInfo.SelectAvailableQuest(q.questID) end
    else
        if q.kind == "active" then SelectActiveQuest(q.index) else SelectAvailableQuest(q.index) end
    end
end

local function pickOption(o)
    if S.sample then
        if o.shop then
            ns.Shop.StartSample()
            return Npc.Show("merchant", {}, true)
        end
        if o.trainer then
            ns.Train.StartSample()
            return Npc.Show("trainer", {}, true)
        end
        return Npc.Close()
    end
    if not firstPress() then return end
    hold()
    C_GossipInfo.SelectOptionByIndex(o.orderIndex)
end

function Npc.Accept()
    local d = S.data
    if not d then return end
    if S.sample then return Npc.Close() end
    if d.pvp and type(StaticPopup_Show) == "function" then
        StaticPopup_Show("CONFIRM_ACCEPT_PVP_QUEST")   -- the game's own confirmation; yes accepts
        return
    end
    if not firstPress() then return end
    if d.auto and type(AcknowledgeAutoAcceptQuest) == "function" then AcknowledgeAutoAcceptQuest() else AcceptQuest() end
end

function Npc.Continue()
    local d = S.data
    if not (d and d.completable) or not firstPress() then return end
    CompleteQuest()
end

-- i = the tile's position in the list; the pick is stored as the game's index for
-- GetQuestReward, so a refill can't move it to another item.
function Npc.Pick(i)
    local d = S.data
    if not (d and d.choices and d.choices[i]) then return end
    S.choice = d.choices[i].index or i
    S.confirm = false
    if Npc.tiles then
        for j, b in ipairs(Npc.tiles) do Parts.PaintPick(b, j == i, j == i) end
    end
    Npc.PaintFooter()
    Npc.Aim()
end

-- Count choices at press time, like QuestRewardCompleteButton_OnClick: a list read
-- earlier can be short. A sample only has its own.
local function choiceCount()
    local shown = S.data and S.data.choices and #S.data.choices or 0
    local n = not S.sample and type(GetNumQuestChoices) == "function" and GetNumQuestChoices()
    return type(n) == "number" and math.max(n, shown) or shown
end
local function needsChoice() return choiceCount() > 1 end

-- No reward picked: show the game's "you must choose" (its button does the same), keep
-- the window open and nudge the main button. Late choices still come in.
function Npc.AskChoice()
    if type(QuestChooseRewardError) == "function" then QuestChooseRewardError() end
    local f = cur()
    local b = f and f.pages.talk and f.pages.talk.foot.buttons[1]
    if b and DUI.Motion then DUI.Motion.Bump(b, 0.96) end
    if choiceCount() > #(S.data.choices or {}) then Npc.Refill() end
end

-- On a first visit the page arrives before its choices. GetNumQuestChoices reports 0
-- until they load, the rewards are blank, and GetQuestReward(0) then fails server-side
-- ("you must choose", "You don't meet the requirements for that quest") AND closes the
-- window. No event says "there are none", so a blank page waits for confirmation: the
-- quest log right away (plain quests never wait), the log's answer once it loads the
-- quest (requested on page open, at most Npc.WATCH_FOR), or a short wait for quests not
-- in the log. If the log knows of choices the page doesn't have, answering can only fail.
function Npc.RewardsPending()
    if S.sample or S.mode ~= "reward" or choiceCount() > 0 then return false end
    local D, id = ns.Data, S.data and S.data.questID
    local known = D.LogChoices(id)
    if known then return known > 0 end
    return now() < (D.InLog(id) and S.loadUntil or S.rewardAt)
end

function Npc.Complete()
    local d = S.data
    if not d then return end
    if needsChoice() and not S.choice then return Npc.AskChoice() end
    if Npc.RewardsPending() then return end
    if (d.cost or 0) > 0 and not S.confirm then   -- costs money: confirm first (the game's own prompt reads its own frame)
        S.confirm = true
        Npc.PaintFooter()
        return
    end
    if S.sample then return Npc.Close() end
    if not firstPress() then return end
    local only = choiceCount() == 1 and (d.choices and d.choices[1] and d.choices[1].index or 1)
    GetQuestReward(S.choice or only or 0)
end

-- The page

local function tooltipFor(it)
    return function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        if S.sample then
            GameTooltip:SetText(it.name or "")
        elseif it.currency then
            if GameTooltip.SetQuestCurrency then GameTooltip:SetQuestCurrency(it.kind, it.index) end
        elseif GameTooltip.SetQuestItem then
            GameTooltip:SetQuestItem(it.kind, it.index, false)
            if type(GameTooltip_ShowCompareItem) == "function" then GameTooltip_ShowCompareItem(GameTooltip) end
        end
        GameTooltip:Show()
        b.UpdateTooltip = tooltipFor(it)   -- the game's tooltip timer calls this, so Shift compares mid-hover
    end
end

-- best: what the best-selling choice sells for (Data.BestSale); its tile gets the coin.
local function tilesFor(list, choosing, best)
    local out = {}
    for i, it in ipairs(list) do
        local sub = it.count and it.count > 1 and string.format(L["%d of them"], it.count) or nil
        -- Unusable (same flag QuestInfo.lua reads): the vendor's soft red.
        local bad = it.usable == false
        local name = it.loading and (RETRIEVING_ITEM_INFO or L["Loading..."]) or it.name
        out[i] = { name = name, texture = it.texture, count = it.count, quality = it.quality,
            sub = sub, subColor = bad and ns.Shop.BAD or nil,
            nameColor = bad and ns.Shop.BAD or it.loading and DUI.Style.INK.LABEL or nil,
            tint = bad and ns.Shop.BAD_ICON or nil, picked = choosing and S.choice == (it.index or i),
            mark = best and ns.Data.SaleOf(it) == best and Npc.COIN or nil,
            tooltip = tooltipFor(it), link = not S.sample and function() return GetQuestItemLink(it.kind, it.index) end or nil,
            onClick = choosing and function() Npc.Pick(i) end or nil,
            onDouble = choosing and function() Npc.Pick(i); Npc.Complete() end or nil }
    end
    return out
end

-- Quest marker beside a quest line: custom art for quests the player has (white, tinted:
-- gold ? when ready, amber ring in progress), the game's ! for offered ones.
local function questIcon(q)
    if q.kind == "active" then
        if q.complete then return DUI.MEDIA .. "quest-ready.png", nil, ns.Data.YELLOW end
        return DUI.MEDIA .. "quest-progress.png", nil, Npc.BUSY
    end
    return nil, "QuestNormal"
end

local function keyFor(n)
    if ns.Setting("keys") == false or DUI.Pad.On() then return nil end
    return n <= 9 and tostring(n) or ""   -- past 9, blank space only so rows line up
end

local function questRows(s, quests, n, air)
    for _, q in ipairs(quests) do
        n = n + 1
        local icon, atlas, iconColor = questIcon(q)
        local color = q.kind == "active" and not q.complete and Npc.BUSY or ns.Data.QuestColor(q.questID, q.level, q.trivial)
        local text = q.title or ""
        if q.level and q.level > 0 then
            local lc = ns.Data.QuestColor(q.questID, q.level, q.trivial) or DUI.Style.INK.LABEL
            text = text .. "  " .. Parts.Hex(lc) .. q.level .. "|r"
        end
        if air > 0 then s:Gap(air) end
        Npc.rows[n] = s:Row({ text = text, color = color, icon = icon, atlas = atlas, iconColor = iconColor, key = keyFor(n),
            onClick = function() pickQuest(q) end })
    end
    return n
end

function Npc.Fill(page)
    local d, s = S.data, page.stack
    s:Begin()
    Npc.rows, Npc.tiles = {}, nil
    local said
    local roomy = page.win == Npc.scene
    local say = roomy and { size = ns.Scene.SAY, spacing = ns.Scene.SPACING } or nil
    local air = roomy and ns.Scene.AIR or 0
    if S.mode == "gossip" or S.mode == "greeting" then
        said = s:Text(d.text, say)
        local choices = d.options and #d.options > 0
        if #d.quests > 0 or choices then s:Gap(Npc.SAID_GAP) end
        local n = 0
        if #d.quests > 0 then
            s:Section(L["Quests"])
            n = questRows(s, d.quests, n, air)
        end
        if choices then
            if #d.quests > 0 then s:Gap(6) end
            for _, o in ipairs(d.options) do
                n = n + 1
                if air > 0 then s:Gap(air) end
                Npc.rows[n] = s:Row({ text = o.name, icon = o.icon, key = keyFor(n), onClick = function() pickOption(o) end,
                    onEnter = o.spellID and function(b)
                        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                        GameTooltip:SetSpellByID(o.spellID)
                        GameTooltip:Show()
                    end or nil,
                    onLeave = o.spellID and function() GameTooltip:Hide() end or nil })
            end
        end
    else
        s:Text(d.title, { size = Npc.TITLE_SIZE, color = d.color })
        said = s:Text(d.text, say)
        if S.mode == "detail" and d.objective ~= "" then
            s:Section(L["Objectives"])
            s:Text(d.objective)
        end
        if S.mode == "progress" then
            if #d.required > 0 then
                s:Section(L["Required"])
                s:Items(tilesFor(d.required, false))
            end
            if (d.cost or 0) > 0 then s:Money(d.cost) end
        else
            local choosing = S.mode == "reward"
            if #d.choices > 0 or #d.rewards > 0 or d.money > 0 or d.xp > 0 then
                s:Section(choosing and #d.choices > 1 and L["Choose your reward"] or L["Rewards"])
            end
            if #d.choices > 0 then
                if not choosing and #d.choices > 1 then s:Text(L["You'll choose one of these:"], { size = DUI.Style.SIZE.small, color = Parts.DIM }) end
                local best, waiting = ns.Data.BestSale(d.choices)
                d.salePending = waiting
                Npc.tiles = s:Items(tilesFor(d.choices, choosing, best))
                if not choosing then Npc.tiles = nil end
            end
            if #d.rewards > 0 then
                if #d.choices > 0 then s:Text(L["You'll also get:"], { size = DUI.Style.SIZE.small, color = Parts.DIM }) end
                s:Items(tilesFor(d.rewards, false))
            end
            s:Money(d.money, d.xp)
        end
    end
    page.pieces = s:End()
    Npc.PaintFooter()
    if roomy and said then ns.Scene.Type(said.text, d.text) end
    Npc.said = said
end

local function acceptKeyName()
    local k = ns.Setting("acceptKey")
    if ns.Setting("keys") == false or DUI.Pad.On() then return nil end
    if k == "enter" then return L["Enter"] end
    return L["Space"]
end
local function escName() if ns.Setting("keys") ~= false and not DUI.Pad.On() then return L["Esc"] end end

-- Footer buttons for this page, left to right, main one first (Parts.Footer).
function Npc.Buttons()
    local m, d = S.mode, S.data
    local ok, esc = acceptKeyName(), escName()
    if m == "gossip" or m == "greeting" then
        return { { text = L["Goodbye"], key = esc, onClick = Npc.Goodbye } }
    elseif m == "detail" then
        if d.auto then return { { text = OKAY or L["Okay"], primary = true, key = ok, onClick = Npc.Accept } } end
        return { { text = L["Accept"], primary = true, key = ok, onClick = Npc.Accept },
                 { text = L["Decline"], tone = "no", key = esc, onClick = Npc.Goodbye } }
    elseif m == "progress" then
        return { { text = CONTINUE or L["Continue"], primary = true, off = not d.completable, key = ok, onClick = Npc.Continue },
                 { text = L["Goodbye"], key = esc, onClick = Npc.Goodbye } }
    elseif m == "reward" then
        local pending = Npc.RewardsPending()
        local off = pending or (needsChoice() and not S.choice)
        local text = pending and (RETRIEVING_ITEM_INFO or L["Loading..."]) or off and L["Choose a reward"] or L["Complete"]
        S.pendingShown = pending
        if S.confirm and (d.cost or 0) > 0 and DUI.MoneyString then text = string.format(L["Pay %s"], DUI.MoneyString(d.cost)) end
        return { { text = text, primary = true, off = off, key = ok, onClick = Npc.Complete },
                 { text = L["Later"], key = esc, onClick = Npc.Goodbye } }
    end
    return {}
end

function Npc.PaintFooter()
    local f = cur()
    local page = f and f.pages.talk
    if page and page.foot then page.foot:Set(Npc.Buttons()) end
end

-- Where a controller starts on this page: the first answer, a reward still to choose,
-- otherwise the main button.
function Npc.Aim()
    local m, f = S.mode, cur()
    local page = f and f.pages.talk
    if not (page and page.foot) then return end
    local main = page.foot.buttons[1]
    if m == "gossip" or m == "greeting" then
        DUI.Pad.Settle(Npc.rows[1] or main)
    elseif m == "reward" and needsChoice() and not S.choice then
        DUI.Pad.Settle(Npc.tiles and Npc.tiles[1] or main)
    elseif m == "detail" or m == "progress" or m == "reward" then
        DUI.Pad.Settle(main)
    end
end

local function build(page)
    page.stack = Parts.Stack(page, { top = 12, bottom = Npc.FOOT })
    page.foot = Parts.Footer(page)
end
Npc.TALK = { Build = build, Fill = Npc.Fill, pieces = function(page) return page.pieces or {} end }
-- The immersive scene's version: same page with more room (Scene.lua).
Npc.SCENE_TALK = { Fill = Npc.Fill, pieces = Npc.TALK.pieces, Build = function(page)
    page.stack = Parts.Stack(page, { top = ns.Scene.TOP, bottom = Npc.FOOT, side = ns.Scene.SIDE })
    page.foot = Parts.Footer(page, { equal = true, edge = ns.Scene.SIDE })   -- Accept and Decline share the width
end }

-- Keys (DialogueKey style)

function Npc.OnKey(key)
    if not Win.IsOpen(cur()) or ns.Setting("keys") == false then return false end
    if ns.Popups.Holds(key) then return false end   -- the popup in front answers it
    -- Space is always taken while talking, even with nothing to do (Continue not ready
    -- yet), so it never makes the character jump.
    local function space(used) return used or key == "SPACE" end
    -- Shop and trainer: keys never spend money. A 1 meant for an action bar must never buy,
    -- and Space/Enter on Train all could empty the purse.
    if S.mode == "merchant" or S.mode == "trainer" then
        if key == "ESCAPE" then
            if ns.Shop.AskOpen() then ns.Shop.AskClose() else Npc.Goodbye() end   -- quantity box first
            return true
        end
        return space(false)
    end
    local n = Win.KeysOf.Number(key)
    if n then
        if S.mode == "reward" and S.data.choices[n] then Npc.Pick(n); return true end
        local row = Npc.rows and Npc.rows[n]
        if row and row:IsShown() then row:Click(); return true end
        return false
    end
    local want = ns.Setting("acceptKey") or "space"
    if (key == "ENTER" and want ~= "space") or (key == "SPACE" and want ~= "enter") then
        if ns.Scene.Typing() then ns.Scene.Finish(); return true end   -- first press finishes typing the text
        local page = cur().pages.talk
        if S.mode == "gossip" or S.mode == "greeting" then
            local row = Npc.rows and Npc.rows[1]
            if row then row:Click(); return true end
            return space(false)
        end
        if S.mode == "reward" and needsChoice() and not S.choice then
            Npc.AskChoice()
            return true
        end
        return space(page.foot:Press(1))
    end
    if key == "ESCAPE" then
        Npc.Goodbye()
        return true
    end
    return space(false)
end

-- Open, switch, close

-- The game's quest window shows this when no NPC gives the quest.
local BOOK = "Interface\\QuestFrame\\UI-QuestLog-BookIcon"

local function header(f)
    local name = DUI.UnitName("npc")
    local r, g, b = DUI.Style.ReactionColor(type(UnitReaction) == "function" and UnitReaction("npc", "player") or nil)
    local zone = (type(GetSubZoneText) == "function" and GetSubZoneText()) or ""
    if zone == "" and type(GetZoneText) == "function" then zone = GetZoneText() or "" end
    Win.SetTitle(f, name or "", { r, g, b }, zone)
    Win.SetPortrait(f, "npc", BOOK)
end

-- Dragged position (header, Win.Drag), saved per profile in the module's `spot`
-- (Win.Spot: Npc.spot, created in Npc.Build).
local function spot() return Npc.spot and Npc.spot.Get() end

-- The dragged position, else anchored where the game window it replaces would be (the
-- left panel spot).
local function place(f, kind)
    local s = spot()
    if s then
        if f.placedOn == "spot" then return end
        f.placedOn = "spot"
        return Win.PlaceTop(f, s[1], s[2])
    end
    local get = Npc.frames and Npc.frames[kind]
    local g = get and get()
    if f.placedOn == g then return end
    f.placedOn = g
    f:ClearAllPoints()
    if type(g) == "table" then f:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0) else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
end

-- Show a page. Opens the window if closed (header first, then page), otherwise the
-- page lifts in under the header.
function Npc.Show(mode, data, sample)
    local f = Npc.FrameFor(mode)
    local other = f == Npc.scene and Npc.frame or Npc.scene
    if other and Win.IsOpen(other) then   -- scene to shop or back: one leaves, the other comes in
        Win.KeysOn(other, false)
        Win.Close(other)
        if other == Npc.scene then ns.Scene.Left() end
    end
    Npc.open = f
    local opening = not Win.IsOpen(f)
    if sample ~= nil then S.sample = sample elseif opening then S.sample = false end
    S.mode, S.data, S.choice, S.confirm = mode, data, nil, false
    S.holdUntil, S.sentUntil = 0, 0
    S.rewardAt = now() + Npc.REWARD_WAIT
    S.loadUntil = now() + Npc.WATCH_FOR
    if mode == "reward" and not S.sample then ns.Data.LoadQuest(data.questID) end
    Npc.Watch()
    if mode == "reward" and data.choices and #data.choices == 1 then S.choice = data.choices[1].index or 1 end
    if f == Npc.scene then ns.Scene.Place() else place(f, Npc.KIND[mode]) end
    if opening and not S.sample then header(f) end
    local shop = mode == "merchant"
    if shop and (opening or Npc.lastMode ~= "merchant") then
        ns.Shop.Opened()
        ns.Shop.RollMoney(true)
    end
    if mode == "trainer" and (opening or Npc.lastMode ~= "trainer") then
        ns.Train.Opened()
        ns.Shop.RollMoney(true)
    end
    if f.money then
        f.money:SetShown(shop or mode == "trainer")
        f.wallet:SetShown(shop)
    end
    Npc.lastMode = mode
    Win.ShowPage(f, Npc.PAGE[mode] or "talk")
    if f == Npc.scene then ns.Scene.Fit(f.pages.talk) end
    if opening then
        if f == Npc.scene then Win.Feel.Slide(f, ns.Scene.SLIDE) end   -- closed: place it immediately
        Win.Open(f)
        Win.KeysOn(f, ns.Setting("keys") ~= false)
        if f == Npc.scene then
            Win.Feel.Slide(f, 0)   -- then glide in from the right
            ns.Scene.Entered()
        end
    end
    if f == Npc.scene then ns.Scene.Hold(f.pages.talk, Npc.said) end
    Npc.Aim()
    DUI.Pad.Refresh(f)
end

function Npc.Close()
    local f = Npc.frame
    if not f then return end
    S.mode, S.data = nil, nil
    for _, w in ipairs({ f, Npc.scene }) do
        Win.KeysOn(w, false)
        Win.Close(w)
    end
    if Npc.scene then ns.Scene.Left() end
    Npc.open = nil
end

-- Sample talk (/dui npc): the window without an NPC.

local SAMPLE_ICON = 134400
function Npc.SampleQuest(ready)
    local boots = { kind = "choice", index = 1, name = L["Walking Boots"], texture = SAMPLE_ICON, quality = 2, sell = 120 }
    local band = { kind = "choice", index = 2, name = L["Herbalist's Band"], texture = SAMPLE_ICON, quality = 2, sell = 340 }
    local blade = { kind = "choice", index = 3, name = L["Mine Clearer's Blade"], texture = SAMPLE_ICON, quality = 1, sell = 90 }
    return { mode = ready and "reward" or "detail", title = L["Kobold Candles"], color = ns.Data.YELLOW,
        text = ready and L["Eight candles, and hardly a dent in them! Here, pick something for your trouble."]
            or L["The kobolds in the mine carry candles on their heads to see in the dark. Bring me eight of them and I'll make it worth your while."],
        objective = L["Bring 8 Large Candles to William Pestle in Goldshire."],
        choices = { boots, band, blade }, rewards = {}, money = 80, xp = 450, cost = 0 }
end

function Npc.Sample()
    if not Npc.frame then return end
    local f = Npc.FrameFor("gossip")
    if f == Npc.frame then
        f.placedOn = nil
        place(f, nil)
    end
    Win.SetTitle(f, L["William Pestle"], { DUI.Style.ReactionColor(5) }, L["Goldshire"])
    Win.SetPortrait(f, nil)
    Npc.Show("gossip", { text = L["Ah, a fresh face. Goldshire isn't what it was, with kobolds in every mine. Still, a man has to keep his shop."],
        quests = { { kind = "available", title = L["Kobold Candles"], level = 6, sample = true },
                   { kind = "active", complete = true, title = L["Gather Rot Blossoms"], level = 7, sample = true } },
        options = { { name = L["Let me browse your goods."], icon = 132060, orderIndex = 0, shop = true },
                    { name = L["I'd like to train."], icon = 132058, orderIndex = 1, trainer = true } } }, true)
end

-- Read the game's page and show it one frame after the event, so another feature's
-- auto-answer runs first and the game's window is up.
local pending
local function apply()
    pending = nil
    local want = S.want
    if not want or not gameShown(Npc.KIND[want.mode]) then return end
    if wasAnswered(want.event) then S.want = nil; return end   -- answered after the event fired
    S.want = nil
    local D = ns.Data
    local m = want.mode
    local data = (m == "merchant" or m == "trainer") and {} or m == "gossip" and D.Gossip() or m == "greeting" and D.Greeting() or D.Quest(m)
    Npc.Show(m, data)
end

function Npc.Want(mode, event)
    if wasAnswered(event) then return end
    S.want = { mode = mode, event = event }
    S.last[Npc.KIND[mode]] = mode
    if not pending then
        pending = true
        C_Timer.After(0, apply)
    end
end

function Npc.OnEvent(_, event, ...)
    if event == "GOSSIP_SHOW" then
        S.closed.gossip = false
        Npc.Want("gossip", event)
    elseif event == "GOSSIP_CLOSED" then
        S.closed.gossip = true
        if (...) == true then hold() end
    elseif Npc.EVENTS[event] then
        S.closed.quest = false
        Npc.Want(Npc.EVENTS[event], event)
    elseif event == "QUEST_FINISHED" then
        S.closed.quest = true
    elseif event == "MERCHANT_SHOW" then
        S.closed.merchant = false
        if Npc.frames and Npc.frames.merchant then Npc.Want("merchant", event) end
    elseif event == "MERCHANT_CLOSED" then
        S.closed.merchant = true
    elseif event == "TRAINER_SHOW" then
        S.closed.trainer = false
        if not (Npc.frames and Npc.frames.trainer) then return end
        -- Beast Training (a hunter spell, no NPC) keeps the game's window.
        local T = Enum and Enum.TrainerType
        if T and C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType() == T.Pet then
            if not Win.Followers.Lend(Npc.follow, "trainer") then
                DUI.AfterCombat(function() Win.Followers.Lend(Npc.follow, "trainer") end, "npc:lendTrainer")
            end
            return
        end
        Npc.Want("trainer", event)
    elseif event == "TRAINER_CLOSED" then
        S.closed.trainer = true
        ns.Train.Closed()
    elseif S.mode == "trainer" and Npc.TRAINER_REFRESH[event] then
        if event == "PLAYER_MONEY" then ns.Shop.RollMoney() else ns.Train.Updated() end
        if not Npc.trainSoon then
            Npc.trainSoon = true
            C_Timer.After(0, function() Npc.trainSoon = false; ns.Train.Refresh() end)
        end
    elseif S.mode == "merchant" then
        -- Money, bags, durability or stock changed: refresh shelf and footer, once per frame.
        if event == "PLAYER_MONEY" then ns.Shop.RollMoney() end
        if event == "BAG_UPDATE_DELAYED" then ns.Shop.BagsChanged() end
        if not Npc.shopSoon then
            Npc.shopSoon = true
            C_Timer.After(0, function() Npc.shopSoon = false; ns.Shop.Refresh() end)
        end
    elseif event == "QUEST_ITEM_UPDATE" or event == "QUEST_LOG_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" then
        -- Late item names or prices, or a quest that became ready: re-read in place, once per
        -- frame with scroll kept (like Shop.Refresh). The pick is a game index, so it holds.
        -- GET_ITEM_INFO_RECEIVED fires on every hover, so it only counts while a price is pending.
        local again = event == "QUEST_ITEM_UPDATE" or (event == "QUEST_LOG_UPDATE" and S.mode == "gossip")
            or (event == "GET_ITEM_INFO_RECEIVED" and S.data and S.data.salePending)
        if S.mode and Win.IsOpen(cur()) and again and not Npc.talkSoon then
            Npc.talkSoon = true
            C_Timer.After(0, Npc.Refill)
        end
    end
end

-- A quest page isn't a snapshot. For its first seconds it polls the game so rewards
-- that arrive without QUEST_ITEM_UPDATE still show, and the footer's waiting text
-- clears when the wait does. It only counts and stops with the page, so an open
-- window costs nothing afterwards.
function Npc.Watch()
    local token = {}
    Npc.watching = nil
    if S.sample or not (S.mode == "reward" or S.mode == "detail") then return end
    Npc.watching = token
    local stop = now() + Npc.WATCH_FOR
    local function look()
        if Npc.watching ~= token then return end
        if not S.data or not Win.IsOpen(cur()) then Npc.watching = nil; return end
        if ns.Data.QuestMoved(S.data) then Npc.Refill() end
        local pending = Npc.RewardsPending()
        if pending ~= (S.pendingShown or false) then Npc.PaintFooter() end
        if now() >= stop and not pending then Npc.watching = nil; return end   -- a blank page keeps polling
        C_Timer.After(Npc.WATCH_STEP, look)
    end
    C_Timer.After(Npc.WATCH_STEP, look)
end

-- Re-read the talk page in place (late item names, a quest that became ready), keeping
-- the scroll position.
function Npc.Refill()
    Npc.talkSoon = false
    local f = cur()
    local page = f and f.pages.talk
    if not (S.mode and S.data and page and Win.IsOpen(f)) or Npc.PAGE[S.mode] then return end
    local D = ns.Data
    local choice = S.choice
    S.data = S.mode == "gossip" and D.Gossip() or S.mode == "greeting" and D.Greeting() or D.Quest(S.mode)
    S.choice = choice
    local at = page.stack:Scrolled()
    Npc.Fill(page)
    page.stack:ScrollTo(at)
    if f == Npc.scene then
        ns.Scene.Fit(page)
        ns.Scene.Hold(page, Npc.said)
    end
end

-- While parked, the game's quest panels never run OnShow (QuestInfo_Display), so
-- QuestFrame's own QUEST_ITEM_UPDATE handler would index QuestInfo.lua's still-nil
-- template. It's kept off that event while parked, and this window repaints from its
-- own handler instead.
function Npc.Parked(kind, f, on)
    if kind ~= "quest" then return end
    if on then f:UnregisterEvent("QUEST_ITEM_UPDATE") else f:RegisterEvent("QUEST_ITEM_UPDATE") end
end

-- A game window closed. If the game hid it without the server ending the talk (Escape,
-- another window taking its place), end the talk here: parked frames never run OnHide,
-- which is what calls CloseGossip/CloseQuest.
function Npc.Changed(kind, shown, away)
    if shown then
        -- Another addon handed it back mid-talk: take over again.
        if S.aside[kind] then
            S.aside[kind] = nil
            Npc.Want(S.last[kind] or kind, "aside")
        end
        return
    end
    if away then
        -- Another addon took the game's window: the talk continues there.
        S.aside[kind] = true
        if S.mode and Npc.KIND[S.mode] == kind then Npc.Close() end
        return
    end
    S.aside[kind] = nil
    -- The veiled vendor and trainer still run their own OnHide, which already told the server.
    if kind == "merchant" then S.closed.merchant = true end
    if kind == "trainer" then S.closed.trainer = true; ns.Train.Closed() end
    if not S.closed[kind] then
        S.closed[kind] = true
        if kind == "gossip" then
            if C_GossipInfo and C_GossipInfo.CloseGossip then C_GossipInfo.CloseGossip() end
        elseif type(CloseQuest) == "function" then
            CloseQuest()
        end
    end
    if anyShown() or not Win.IsOpen(cur()) then return end
    local wait = S.holdUntil - now()
    if wait <= 0 or Npc.OtherWindow() then return Npc.Close() end
    Win.Dim(cur(), true)   -- next page is on its way
    C_Timer.After(wait, function()
        if not anyShown() and S.want == nil and now() >= S.holdUntil - 0.01 then Npc.Close() end
    end)
end

-- Another game window took the left panel spot (a flight master, say): no hold, close now.
function Npc.OtherWindow()
    if type(GetUIPanel) ~= "function" then return false end
    local ok, p = pcall(GetUIPanel, "left")
    if not ok or type(p) ~= "table" then return false end
    for _, get in pairs(Npc.frames or Npc.FRAMES) do if get() == p then return false end end
    return true
end

Npc.LISTEN = { "GOSSIP_SHOW", "GOSSIP_CLOSED", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_FINISHED", "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE",
    "MERCHANT_FILTER_ITEM_UPDATE", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "GET_ITEM_INFO_RECEIVED",
    "CURRENCY_DISPLAY_UPDATE",
    "TRAINER_SHOW", "TRAINER_CLOSED", "TRAINER_UPDATE", "TRAINER_SERVICE_INFO_NAME_UPDATE" }

-- Created size of a page: talk uses Npc.W, trainer and shop their own widths.
function Npc.Base(id)
    if id == "train" and ns.Train then return ns.Train.W, Npc.H end
    if id == "shop" and ns.Shop then return ns.Shop.W, Npc.H end
    return Npc.W, Npc.H
end

-- A page's size: what its resize grip set (Win.Resizable), else the created size.
function Npc.PageSize(id)
    if Npc.sizer then return Npc.sizer.Size(id) end
    return Npc.Base(id)
end

-- Lay out the visible page for the grip's size. Live while dragging (rows stretch),
-- then a full refill at the end with the scroll kept.
function Npc.Resized(_, _, live)
    local f = Npc.frame
    if not (f and Win.IsOpen(f)) then return end
    local page = f.pages[f.current]
    local def = f.defs[f.current]
    if not (page and page.stack) then return end
    if live then page.stack:Stretch(); return end
    local at = page.stack:Scrolled()
    if def and def.Fill then def.Fill(page) end
    page.stack:ScrollTo(at)
end

-- Dragged by the header: just saved, nothing to refill.
function Npc.SaveSpot(x, y)
    Npc.spot.Save(x, y)
    if Npc.frame then Npc.frame.placedOn = "spot" end
end

-- Right-click on the header (or /dui reset): back to the game's spot.
function Npc.ResetSpot() return Npc.spot and Npc.spot.Reset() end

function Npc.Apply()
    local f = Npc.frame
    if not f then return end
    f:SetScale(Win.Scale(ns.Setting("scale")))
    if spot() and Win.IsOpen(f) then f.placedOn = nil; place(f) end   -- new UI scale keeps the dragged spot
    Win.Repaint(f)
    if Npc.follow then Win.Followers.WriteWidth(Npc.follow) end
    if Win.IsOpen(f) and f.pages.talk then Npc.Fill(f.pages.talk) end
    local sc = Npc.scene
    if sc then
        sc:SetScale(Win.Scale(ns.Setting("scale")))
        Win.Repaint(sc)
        if Win.IsOpen(sc) then
            ns.Scene.Place()
            Win.Feel.Size(sc, sc.spec.w, sc.spec.h)   -- new UI scale: fit to the screen again
            Npc.Fill(sc.pages.talk)
        end
    end
end

-- Controller: the same buttons the game's windows offer (MerchantFrame,
-- Blizzard_TrainerUI, QuestFrame's footers).

Npc.SPELLBOOK_BUTTON = { "SpellbookMicroButton", "PlayerSpellsMicroButton" }

local function shopItem(b) return S.mode == "merchant" and b and type(b.spec) == "table" and b.spec.shopItem or nil end

local function isChoice(b)
    for _, t in ipairs(Npc.tiles or {}) do if t == b then return true end end
    return false
end

local function spellbookButton()
    for _, name in ipairs(Npc.SPELLBOOK_BUTTON) do if _G[name] then return name end end
end

-- What A does on the current stop.
function Npc.PadSelect(b)
    local it = shopItem(b)
    if it then return it.buyback and (BUYBACK or L["Buy back"]) or CONTEXT_ACTION_LABEL_BUY or L["Buy"] end
    if S.mode == "trainer" and b and type(b.lineSpec) == "table" and b.lineSpec.service then return TRAIN or L["Train"] end
    if S.mode == "reward" and isChoice(b) then return CONTEXT_ACTION_LABEL_CHOOSE_REWARD or L["Choose reward"] end
    if b and type(b.spec) == "table" and type(b.spec.text) == "string" and b.text then return b.spec.text end
    return nil
end

function Npc.PadKeys()
    return {
        { key = "X", label = CONTEXT_ACTION_LABEL_MULTI_BUY or L["Buy a stack"],
          when = function(b) return ns.Shop.CanStack(shopItem(b)) end,
          run = function(b) ns.Shop.Ask(shopItem(b), b) end },
        { key = "X", label = CONTEXT_ACTION_LABEL_INSPECT or L["Inspect"],
          when = function(b)
              local it = shopItem(b)
              return it ~= nil and not it.buyback and it.link ~= nil and C_Item and C_Item.IsDressableItemByID
                  and C_Item.IsDressableItemByID(it.link) == true
          end,
          run = function(b) DressUpLink(shopItem(b).link) end },
        { key = "Y", label = RADIAL_LABEL_SPELLBOOK or L["Spellbook"], click = spellbookButton(),
          when = function() return S.mode == "trainer" end },
    }
end

local function padSetup(f)
    f.padSelect = Npc.PadSelect
    f.padKeys = Npc.PadKeys()
end

function Npc.Build(mod)
    ns.module = mod
    if Npc.frame then return Npc.frame end
    local f = Win.New({ name = Npc.NAME, back = "NPC", w = Npc.W, h = Npc.H, portrait = true })
    Npc.frame = f
    f.onClose = Npc.Goodbye
    Npc.spot = Win.Spot(f, function() return ns.module and ns.module.db end,
        function(w) w.placedOn = nil; place(w, Npc.KIND[S.mode]) end)
    Win.WheelScale(f, function() return ns.Setting("scale") end, function(v) DUI:Set("NPC", "scale", v) end)
    Win.Drag(f, { save = Npc.SaveSpot, reset = Npc.ResetSpot })
    DUI.Movers.onResetAll[#DUI.Movers.onResetAll + 1] = Npc.ResetSpot   -- /dui reset
    -- Not dragged: it hangs from the game's panel spot, so a grip drag ends on that anchor.
    -- Dragged: the grip keeps and saves its new top.
    Npc.sizer = Win.Resizable(f, { db = function() return ns.module and ns.module.db end, base = Npc.Base,
        place = function(w)
            if spot() then
                local x, y = Win.TopOf(w)
                if x then Win.PlaceTop(w, x, y); Npc.SaveSpot(x, y) end
                return
            end
            w.placedOn = nil; place(w, Npc.KIND[S.mode])
        end,
        resized = Npc.Resized, follow = function() return Npc.follow end })
    Win.AddPage(f, "talk", Npc.TALK)
    Win.Build(f, "talk")
    Npc.scene = ns.Scene.Build(Npc.SCENE_TALK)   -- the immersive look's own window (Scene.lua)
    padSetup(f)
    padSetup(Npc.scene)
    -- Game windows this one replaces. Vendor and trainer only with their settings on (read
    -- at login), and the vendor never while DaylightMogul's is in use (DUI.vendorMogul,
    -- Module.lua).
    Npc.frames = {}
    for kind, get in pairs(Npc.FRAMES) do
        if (kind ~= "merchant" or (ns.Setting("vendor") ~= false and not DUI.vendorMogul))
            and (kind ~= "trainer" or ns.Setting("trainer") ~= false) then
            Npc.frames[kind] = get
        end
    end
    DUI.npcOwnVendor = Npc.frames.merchant ~= nil
    DUI.npcOwnTrainer = Npc.frames.trainer ~= nil
    if Npc.frames.trainer then
        Win.AddPage(f, "train", { Build = ns.Train.Build, Fill = ns.Train.Fill, w = ns.Train.W,
            pieces = function(page) return page.pieces or {} end })
        Win.Build(f, "train")
    end
    if Npc.frames.merchant then
        Win.AddPage(f, "shop", { Build = ns.Shop.Build, Fill = ns.Shop.Fill, w = ns.Shop.W,
            pieces = function(page) return page.pieces or {} end })
        Win.Build(f, "shop")
    end
    -- Player's money in the header while the shop is open.
    f.money = DUI.Style.Text(f, DUI.Style.SIZE.body, "RIGHT")
    f.money:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
    f.money:Hide()
    -- Plus what the player holds of the shelf's other costs (tokens, items), left of it.
    f.wallet = DUI.Style.Text(f, DUI.Style.SIZE.body, "RIGHT")
    f.wallet:SetPoint("RIGHT", f.money, "LEFT", -12, 0)
    f.wallet:Hide()
    Win.Keys(f, Npc.OnKey)
    local ev = CreateFrame("Frame")
    for _, e in ipairs(Npc.LISTEN) do pcall(ev.RegisterEvent, ev, e) end
    ev:SetScript("OnEvent", Npc.OnEvent)
    Npc.events = ev
    Npc.follow = Win.Follow({ key = "npc", frames = Npc.frames, veil = Npc.VEIL, changed = Npc.Changed, onPark = Npc.Parked,
        width = function() return (Npc.PageSize(f.current or "talk")) * Win.Scale(ns.Setting("scale")) end })
    Npc.Apply()
    return f
end

DUI.RegisterCommand("npc", function()
    if Npc.frame then Npc.Sample() else DUI.Print(L["The NPC window is switched off (/dui > Talk)."]) end
end, L["/dui npc - try the NPC window with a sample talk"])
