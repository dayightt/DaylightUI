-- Named talent builds per character and talent set, plus copying and pasting
-- the game's loadout string.
--
-- Loading a build only stages ranks, one at a time through Spend, top row
-- first. Nothing is learned until Apply, and Undo drops it all. Applied points
-- can't be refunded on Forever (only a trainer resets them), so a build that
-- lacks a talent you already learned is refused. Ranks you can't afford yet
-- are left for later, so a leveling build fills in as you level.
--
-- Saved in DB.Character().talentBuilds[group] = { { name, ranks = { [nodeID] = ranks } } }.

local _, DUI = ...
DUI.Book = DUI.Book or {}   -- the book window's own namespace
local ns = DUI.Book
local L = DUI.L
local Style = DUI.Style

local Builds = {}
ns.Builds = Builds

Builds.MAX = 20        -- builds kept per set
Builds.SAY = 4         -- seconds the result line stays up
Builds.STEPS = 200     -- safety cap on ranks staged per load

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

-- Builds saved for the talent set on screen.
function Builds.List(group)
    local char = DUI.DB.Character()
    if type(char) ~= "table" then return {} end
    char.talentBuilds = type(char.talentBuilds) == "table" and char.talentBuilds or {}
    group = group or ns.Spend.Group()
    char.talentBuilds[group] = type(char.talentBuilds[group]) == "table" and char.talentBuilds[group] or {}
    return char.talentBuilds[group]
end

local function read() return ns.TalentData.Read(ns.Spend.Config()) end

-- Save the current points, staged ones included, replacing any build with
-- the same name. Returns nil when no points are spent.
function Builds.Save(name)
    name = type(name) == "string" and string.match(name, "^%s*(.-)%s*$") or ""
    if name == "" then return nil end
    local data = read()
    if not data then return nil end
    local ranks, any = {}, false
    for id, node in pairs(data.byID) do
        if node.rank > 0 then ranks[id] = node.rank; any = true end
    end
    if not any then return nil end
    local list = Builds.List()
    local build = { name = name, ranks = ranks }
    for i, b in ipairs(list) do
        if b.name == name then list[i] = build; return build end
    end
    if #list >= Builds.MAX then return nil end
    list[#list + 1] = build
    return build
end

function Builds.Delete(i)
    local list = Builds.List()
    if list[i] then table.remove(list, i) return true end
    return false
end

-- Returns why the build can't be loaded, or nil. data is an optional
-- TalentData read to reuse.
function Builds.Conflict(build, data)
    if InCombatLockdown() then return ERR_NOT_IN_COMBAT or L["Not in combat."] end
    if ns.Spend.committing then return L["Wait for the talents being applied."] end
    if ns.Spend.Locked() then return L["Activate this set first."] end
    data = data or read()
    if not data then return L["Talents aren't available yet."] end
    local ranks = type(build) == "table" and type(build.ranks) == "table" and build.ranks or {}
    for id, node in pairs(data.byID) do
        if node.active > (ranks[id] or 0) then
            return L["You've already learned talents this build doesn't have. A trainer can reset them."]
        end
    end
end

-- Pick the next rank to stage in the order tiers unlock: row, then tree,
-- then column.
local function nextRank(data, ranks)
    local best
    for ti, t in ipairs(data.trees) do
        for _, node in ipairs(t.nodes) do
            local want = ranks[node.id] or 0
            if node.rank < want and ns.Spend.CanBuy(node, data) then
                local key = node.row * 10000 + ti * 100 + node.col
                if not best or key < best.key then best = { node = node, key = key } end
            end
        end
    end
    return best and best.node
end

local function missing(data, ranks)
    local n = 0
    for id, want in pairs(ranks) do
        local node = data.byID[id]
        n = n + math.max(want - (node and node.rank or 0), 0)
    end
    return n
end

-- Stage a build, given as a list index or a build table. Returns the number
-- staged and a reason: why it failed, or how many points are left over.
function Builds.Load(build)
    if type(build) == "number" then build = Builds.List()[build] end
    if type(build) ~= "table" then return 0 end
    local data = read()
    local why = Builds.Conflict(build, data)
    if why then return 0, why end
    -- Clear any staged ranks first. Learned ones stay (Conflict checked them).
    if ns.Spend.HasChanges() then ns.Spend.Undo(); data = read() end
    local ranks, staged = build.ranks, 0
    -- After each rank, refresh only the build's nodes and the point pool
    -- instead of re-reading the whole tree.
    for _ = 1, Builds.STEPS do
        local node = data and nextRank(data, ranks)
        if not (node and ns.Spend.Buy(node, data)) then break end
        staged = staged + 1
        ns.TalentData.Refresh(data, ranks)
    end
    if ns.Talents then ns.Talents.Soon() end
    local short = data and missing(data, ranks) or 0
    if short > 0 then return staged, string.format(L["%d |4point:points; left for later."], short) end
    return staged
end

-- Prefer the client's GenerateImportString, fall back to our encoder.
function Builds.Copy()
    local configID = ns.Spend.Config()
    if not configID then return nil end
    local C = type(C_Traits) == "table" and C_Traits or nil
    local text = C and call(C.GenerateImportString, configID)
    if type(text) == "string" and text ~= "" then return text end
    return ns.LoadoutString.Encode(configID)
end

-- Stage a pasted loadout string. Same returns as Builds.Load.
function Builds.Paste(text)
    local got, err = ns.LoadoutString.Decode(text, ns.Spend.Config())
    if not got then return 0, err end
    return Builds.Load({ name = "", ranks = got.ranks })
end

-- ---------------------------------------------------------------------
-- UI: Builds button and menu, a small input box, and a result line
-- ---------------------------------------------------------------------

function Builds.Say(text, bad)
    local page = Builds.page
    if not page then return end
    local fs = page.buildSay
    fs:SetText(text or "")
    local c = bad and DUI.Tips.WARN or DUI.Tips.TEXT
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetShown(text ~= nil)
    local token = {}
    Builds.sayToken = token
    C_Timer.After(Builds.SAY, function() if Builds.sayToken == token then fs:Hide() end end)
end

local function report(staged, reason)
    if staged > 0 then
        local text = string.format(L["%d |4point:points; ready: Apply to learn them."], staged)
        if reason then text = text .. "  " .. reason end
        Builds.Say(text)
    else
        Builds.Say(reason or L["Nothing to change."], reason ~= nil)
    end
end

local function makeBox(page)
    local W = DUI.Widgets
    local box = CreateFrame("Frame", nil, page)
    box:SetSize(360, 112)
    box:SetPoint("TOP", page, "TOP", 0, -40)
    box:SetFrameLevel(page:GetFrameLevel() + 40)
    box:EnableMouse(true)
    Style.Shell(box, {})
    box.title = Style.Text(box, Style.SIZE.head, "LEFT")
    box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    local edit = W.Input(box, { height = 24 })
    edit:SetWidth(336)
    edit:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -32)
    edit:SetScript("OnEscapePressed", function() Builds.CloseBox() end)
    edit:SetScript("OnEnterPressed", function() Builds.Confirm() end)
    box.edit = edit
    box.note = Style.Text(box, Style.SIZE.small, "LEFT")
    box.note:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -6)
    box.note:SetWidth(336)
    box.ok = W.Button(box, OKAY or L["OK"], 22)
    box.ok:SetWidth(80)
    box.ok:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 10)
    box.ok:SetScript("OnClick", function() Builds.Confirm() end)
    box.cancel = W.Button(box, CANCEL or L["Cancel"], 22)
    box.cancel:SetWidth(80)
    box.cancel:SetPoint("RIGHT", box.ok, "LEFT", -6, 0)
    box.cancel:SetScript("OnClick", function() Builds.CloseBox() end)
    box:Hide()
    return box
end

-- mode is "save" (ask for a name), "copy" (show the string selected) or "paste".
function Builds.OpenBox(mode)
    local page = Builds.page
    if not page then return end
    page.buildBox = page.buildBox or makeBox(page)
    local box = page.buildBox
    box.mode = mode
    box.note:SetText("")
    local tc = DUI.Tips.TEXT
    box.note:SetTextColor(tc[1], tc[2], tc[3], 1)
    if mode == "save" then
        box.title:SetText(L["Save these talents as"])
        box.edit:SetText(string.format(L["Build %d"], #Builds.List() + 1))
    elseif mode == "copy" then
        box.title:SetText(L["Talent string: press Ctrl+C to copy"])
        box.edit:SetText(Builds.Copy() or "")
    else
        box.title:SetText(L["Paste a talent string"])
        box.edit:SetText("")
    end
    box.ok:SetShown(mode ~= "copy")
    box.cancel.text:SetText(mode == "copy" and (CLOSE or L["Close"]) or (CANCEL or L["Cancel"]))
    local opening = not DUI.Motion.Shown(box)
    box:Show()
    if opening then DUI.Motion.Appear(box, 6) end
    box.edit:SetFocus()
    box.edit:HighlightText()
end

function Builds.CloseBox()
    local box = Builds.page and Builds.page.buildBox
    if box then box.edit:ClearFocus(); DUI.Motion.Vanish(box) end
end

function Builds.Confirm()
    local box = Builds.page and Builds.page.buildBox
    if not (box and DUI.Motion.Shown(box)) then return end
    local text = box.edit:GetText() or ""
    local warn = DUI.Tips.WARN
    if box.mode == "save" then
        if Builds.Save(text) then
            Builds.CloseBox()
            Builds.Say(string.format(L["Saved %s."], text))
        else
            box.note:SetText(#Builds.List() >= Builds.MAX and L["That's as many builds as a set keeps: delete one first."]
                or L["Spend some points first, and give it a name."])
            box.note:SetTextColor(warn[1], warn[2], warn[3], 1)
        end
    elseif box.mode == "paste" then
        local staged, reason = Builds.Paste(text)
        if staged > 0 then
            Builds.CloseBox()
            report(staged, reason)
        else
            box.note:SetText(reason or L["Nothing to change."])
            box.note:SetTextColor(warn[1], warn[2], warn[3], 1)
        end
    else
        Builds.CloseBox()
    end
end

function Builds.Menu(owner)
    local W = DUI.Widgets
    local list = Builds.List()
    local keys, values = {}, {}
    for i, b in ipairs(list) do
        keys[#keys + 1] = i
        values[i] = b.name
    end
    local function add(k, text) keys[#keys + 1] = k; values[k] = text end
    add("save", L["Save these talents..."])
    add("copy", L["Copy talent string"])
    add("paste", L["Paste talent string..."])
    if #list > 0 then add("delete", L["Delete a build..."]) end
    W.OpenMenu(owner, keys, values, nil, function(k)
        if type(k) == "number" then
            report(Builds.Load(k))
        elseif k == "delete" then
            local dk, dv = {}, {}
            for i, b in ipairs(list) do dk[i] = i; dv[i] = string.format(L["Delete %s"], b.name) end
            W.OpenMenu(owner, dk, dv, nil, function(i)
                local name = list[i] and list[i].name
                if Builds.Delete(i) then Builds.Say(string.format(L["Deleted %s."], name)) end
            end, 200)
        else
            Builds.OpenBox(k)
        end
    end, 200)
end

function Builds.Build(page)
    Builds.page = page
    local W = DUI.Widgets
    local b = W.Button(page, L["Builds"], 24)
    b:SetWidth(72)
    b:SetPoint("RIGHT", page.search, "LEFT", -8, 0)
    b:SetScript("OnClick", function(self) Builds.Menu(self) end)
    b:HookScript("OnEnter", function(self)
        W.Tooltip(self, L["Builds"], L["Keep these talents under a name and put them back later, or copy and paste a talent string."])
    end)
    b:HookScript("OnLeave", function() W.HideTooltip() end)
    page.builds = b
    page.buildSay = Style.Text(page, Style.SIZE.small, "CENTER")
    page.buildSay:SetPoint("BOTTOM", page, "BOTTOM", 0, 46)   -- just over the footer's line
    page.buildSay:Hide()
    page:HookScript("OnHide", function() Builds.CloseBox() end)
end
