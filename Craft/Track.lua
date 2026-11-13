-- Tracked recipes. Tracking is the game's own (C_TradeSkillUI.SetRecipeTracked, the
-- same list its profession window's Track checkbox keeps), and the game shows it in
-- its objective tracker. Daylight UI's quest tracker takes that tracker's place, so
-- while it does, this small panel shows each tracked recipe and what it still needs,
-- have / need from the bags. A click on a recipe's name opens it; a right-click
-- stops tracking it.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L
local Style = DUI.Style

local Track = {}
ns.Track = Track

Track.W = 230
Track.PAD = 10
Track.HEAD = 20        -- a recipe's name row
Track.LINE = 16        -- one material
Track.GAP = 6          -- between recipes
Track.MOVER = "craft.track"
Track.DEFAULT = { "LEFT", nil, "LEFT", 40, 160 }
Track.EVENTS = { "TRACKED_RECIPE_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED" }

local function TS() return type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil end

local function call(name, ...)
    local ts = TS()
    local fn = ts and ts[name]
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    return ok and a or nil
end

-- The game's tracker is gone while the quest tracker has taken over: only then is
-- this panel needed.
function Track.Needed() return DUI.questsOwnTracker == true end

-- Tracked recipe ids (recrafts aren't a thing on Forever).
function Track.IDs()
    local out = {}
    local ids = call("GetRecipesTracked", false)
    for _, id in ipairs(type(ids) == "table" and ids or {}) do
        if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then out[#out + 1] = id end
    end
    return out
end

function Track.Is(id) return call("IsRecipeTracked", id, false) == true end

function Track.Set(id, on)
    call("SetRecipeTracked", id, on and true or false, false)
    Track.Soon()
end

-- Name and materials of a tracked recipe, read whether or not its profession is open.
function Track.Read(id)
    local s = call("GetRecipeSchematic", id, false)
    local name = type(s) == "table" and type(s.name) == "string" and s.name or nil
    if not name then
        local info = call("GetRecipeInfo", id)
        name = type(info) == "table" and type(info.name) == "string" and info.name or ""
    end
    return { id = id, name = name, mats = ns.Data.Materials(id) }
end

-- Building

local holder

local function headTip(b)
    local Tips = DUI.Tips
    if not (GameTooltip and Tips) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    Tips.Clear()
    Tips.Title(b.recipe and b.recipe.name or "")
    Tips.Hint(L["Click: open the recipe"])
    Tips.Hint(L["Right-click: stop tracking"])
    Tips.Flush(GameTooltip)
    GameTooltip:Show()
end

local function matTip(b)
    if not (GameTooltip and b.itemID) then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if type(GameTooltip.SetItemByID) == "function" then GameTooltip:SetItemByID(b.itemID) end
    GameTooltip:Show()
end

local function hideTip(b)
    if GameTooltip and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
end

local function makeHead()
    local b = CreateFrame("Button", nil, holder)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.text = Style.Text(b, Style.SIZE.body, "LEFT")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
        Style.InkText(self.text, "pop")
        headTip(self)
    end)
    b:SetScript("OnLeave", function(self)
        Style.InkText(self.text, "VALUE")
        hideTip(self)
    end)
    b:SetScript("OnClick", function(self, button)
        local r = self.recipe
        if not r then return end
        if DUI.Sound then DUI.Sound.Play("click") end
        if button == "RightButton" then
            DUI.Widgets.OpenMenu(self, { "untrack" }, { untrack = PROFESSIONS_UNTRACK_RECIPE or L["Untrack"] }, nil,
                function() Track.Set(r.id, false) end, nil, { atCursor = true })
        else
            call("OpenRecipe", r.id)
        end
    end)
    return b
end

local function makeMat()
    local b = CreateFrame("Frame", nil, holder)
    b:EnableMouse(true)
    b.count = Style.Text(b, Style.SIZE.small, "LEFT")
    b.count:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.name = Style.Text(b, Style.SIZE.small, "LEFT")
    b.name:SetPoint("LEFT", b.count, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.name:SetWordWrap(false)
    b:SetScript("OnEnter", matTip)
    b:SetScript("OnLeave", hideTip)
    return b
end

local function build()
    if holder then return holder end
    holder = CreateFrame("Frame", "DaylightUICraftTrack", UIParent)
    holder:SetSize(Track.W, 40)
    holder:SetFrameStrata("LOW")
    holder:Hide()
    Style.Shell(holder)
    holder.heads, holder.mats = {}, {}
    Track.holder = holder
    DUI.Movers.Register(holder, Track.MOVER, "Tracked recipes", Track.DEFAULT)
    return holder
end

-- Filling

local function take(pool, make, i)
    local b = pool[i]
    if not b then b = make(); pool[i] = b end
    b:Show()
    return b
end

-- Draws the list. Each count eases in when it changes (a bag filling up), and the
-- whole panel fades in as the first recipe is tracked and out after the last.
Track.counts = {}

function Track.Fill()
    local ids = Track.IDs()
    local want = Track.Needed() and #ids > 0
    if not want then
        if holder and holder:IsShown() and not holder.leaving then
            holder.leaving = true
            local M = DUI.Motion
            M.Tween(holder, holder:GetAlpha(), 0, M.NORMAL, function(a) holder:SetAlpha(a) end, function()
                if holder.leaving then holder:Hide(); holder.leaving = nil end
            end)
        end
        return
    end
    build()
    local INK = Style.INK
    local y, nh, nm = Track.PAD, 0, 0
    local w = Track.W - 2 * Track.PAD
    local seen = {}
    for i, id in ipairs(ids) do
        local r = Track.Read(id)
        if i > 1 then y = y + Track.GAP end
        nh = nh + 1
        local head = take(holder.heads, makeHead, nh)
        head.recipe = r
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", holder, "TOPLEFT", Track.PAD, -y)
        head:SetSize(w, Track.HEAD)
        head.text:SetText(r.name)
        Style.InkText(head.text, head:IsMouseOver() and "pop" or "VALUE")
        y = y + Track.HEAD
        for _, m in ipairs(r.mats) do
            nm = nm + 1
            local b = take(holder.mats, makeMat, nm)
            b.itemID = m.itemID
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", holder, "TOPLEFT", Track.PAD + 8, -y)
            b:SetSize(w - 8, Track.LINE)
            local text = string.format(L["%d / %d"], m.have, m.need)
            b.count:SetText(text)
            Style.InkText(b.count, m.have >= m.need and "GOOD" or "pop")
            b.name:SetText(m.name or (RETRIEVING_ITEM_INFO or L["Loading..."]))
            Style.InkText(b.name, m.have >= m.need and "LABEL" or "TEXT")
            local key = id .. ":" .. m.itemID
            seen[key] = text
            if Track.counts[key] and Track.counts[key] ~= text and DUI.Motion then
                DUI.Motion.Fade(b.count, 0.3, 1, DUI.Motion.FAST)
            end
            y = y + Track.LINE
        end
    end
    Track.counts = seen
    for i = nh + 1, #holder.heads do holder.heads[i]:Hide() end
    for i = nm + 1, #holder.mats do holder.mats[i]:Hide() end
    holder:SetHeight(y + Track.PAD)
    if not holder:IsShown() or holder.leaving then
        local from = holder.leaving and holder:GetAlpha() or 0
        holder.leaving = nil
        holder:SetAlpha(from)
        holder:Show()
        local M = DUI.Motion
        M.Tween(holder, from, 1, M.NORMAL, function(a) holder:SetAlpha(a) end)
    end
end

-- Events come in bursts (a craft touches the bags many times): one read the next
-- frame covers them.
function Track.Soon()
    if Track.pending then return end
    Track.pending = true
    C_Timer.After(0, function()
        Track.pending = nil
        Track.Fill()
    end)
end

-- Started at login whatever the profession window: tracking is the game's, and a
-- tracked recipe needs showing out in the world too.
function Track.Init()
    if Track.started then return end
    Track.started = true
    for _, e in ipairs(Track.EVENTS) do DUI.RegisterEvent(e, function() Track.Soon() end) end
    Track.Fill()
end
