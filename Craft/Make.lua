-- Crafting footer on the recipe side: Create (main button) on the left, then the
-- amount (- / number / +), and Create all on the right. Calls
-- C_TradeSkillUI.CraftRecipe(id, n) directly, which addon code is allowed to do,
-- the same way the game's CreateInternal does.
--
-- While crafting, the footer becomes a progress row: "Making 2 of 5", a bar that fills
-- with each cast, and Stop. The player's own casts stay plain under every restriction
-- (SecretWhenUnitSpellCastRestricted). Only the game's code can stop a cast
-- (SpellStopCasting is protected and the secure "stop" action only cancels targeting),
-- so Stop is the kit's secure "/stopcasting" button laid over this one (Win.Caster),
-- out of combat. Each finished craft runs a light across its list row.
--
-- An enchant (isEnchantingRecipe) with no item picked is cast once with CraftEnchant
-- and no target, and the game asks the player to click the item. With an item picked
-- ("Enchant on", on the recipe side) it goes straight onto it as many times as asked,
-- so leveling on one pair of bracers is one press. The game's "replace this enchant?"
-- prompt is shown the first time; after that the existing enchant is one the player
-- just applied, so it's answered automatically.

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft
local L = DUI.L
local Style = DUI.Style
local Win = DUI.Win

local Make = {}
ns.Make = Make

Make.FOOT = 52       -- footer height under the recipe
Make.NUM_W = 40      -- amount box width
Make.STEP_W = 24     -- - and + buttons
Make.TARGETS = 12    -- items remembered as enchant targets, per character
Make.GAP = 2         -- s a run can pause between two enchants before it counts as done
Make.laid = {}       -- item GUID -> the enchant applied to it this session

local function TS() return type(C_TradeSkillUI) == "table" and C_TradeSkillUI or nil end
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
local function call(name, ...)
    local ts = TS()
    local fn = ts and ts[name]
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    return ok and a or nil
end

-- Labels, using the game's strings first.
local function verb(r)
    if r.enchant then return CREATE_PROFESSION_ENCHANT or L["Enchant"] end
    return r.verb or CREATE_PROFESSION or L["Create"]
end

local function allWords(n, enchant)
    local fmt = PROFESSIONS_CREATE_ALL_FORMAT or "%s [%d]"
    local word = enchant and PROFESSIONS_ENCHANT_ALL or PROFESSIONS_CREATE_ALL
    return string.format(fmt, word or (enchant and L["Enchant all"]) or L["Create all"], n)
end

-- Enchant target item

-- Items the player picked, most recent first (saved per character).
local function recents()
    local char = DUI.DB and DUI.DB.Character and DUI.DB.Character()
    if not char then return {} end
    if type(char.craftTargets) ~= "table" then char.craftTargets = {} end
    return char.craftTargets
end

local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok and not secret(v) then return v end
    return nil
end

-- What the enchant can go on, from the game's enchant slot list.
function Make.Targets(r)
    local out = {}
    local guids = call("GetEnchantItems", r.id)
    if type(guids) ~= "table" or not C_Item then return out end
    for _, guid in ipairs(guids) do
        local loc = not secret(guid) and plain(C_Item.GetItemLocation, guid)
        if loc then
            out[#out + 1] = { guid = guid, loc = loc, name = plain(C_Item.GetItemName, loc) or "",
                icon = plain(C_Item.GetItemIcon, loc), quality = plain(C_Item.GetItemQuality, loc) }
        end
    end
    return out
end

-- The item this enchant goes on (nil: none picked, so the game asks for a click on gear
-- or a trade item), and what it can go on.
function Make.TargetFor(r)
    if not (r and r.enchant) then return nil, {} end
    local list, byGuid = Make.Targets(r), {}
    for _, t in ipairs(list) do byGuid[t.guid] = t end
    for _, guid in ipairs(recents()) do
        if byGuid[guid] then return byGuid[guid], list end
    end
    return nil, list
end

function Make.SetTarget(guid)
    local kept = recents()
    for i = #kept, 1, -1 do
        if kept[i] == guid then table.remove(kept, i) end
    end
    table.insert(kept, 1, guid)
    kept[Make.TARGETS + 1] = nil
end

-- Back to clicking: drop a picked item this enchant can't go on.
function Make.ClearTarget(r)
    local kept = recents()
    for _, t in ipairs(Make.Targets(r)) do
        for i = #kept, 1, -1 do
            if kept[i] == t.guid then table.remove(kept, i) end
        end
    end
end

-- The game asks about replacing the current enchant. If it's one applied this session,
-- or the same enchant again, answer yes, or a spam run would stop at every cast.
-- Anything else is the player's call; the footer steps aside for the prompt ("No" just
-- closes it) and the run comes back with its first cast.
function Make.OnReplace(popup, yes, existing, replacement)
    local s = Make.state
    if not (s and s.guid) or secret(existing) or secret(replacement) then return end
    s.putting = replacement
    if existing == replacement or Make.laid[s.guid] == existing then
        if C_Item and type(C_Item[yes]) == "function" then C_Item[yes]() end
        local function hide() if StaticPopup_Hide then StaticPopup_Hide(popup) end end
        hide()
        C_Timer.After(0, hide)   -- in case the game's own handler runs after this one
        return
    end
    Make.asked, Make.state = s, nil
    if Make.row and Make.row:IsShown() then Make.ShowProgress(false) end
end

-- Amount

function Make.Most()
    local r = Make.recipe
    return r and math.max(1, r.count) or 1
end

function Make.SetAmount(v, typing)
    local box = Make.box
    Make.amount = math.max(1, math.min(Make.Most(), math.floor(tonumber(v) or 1)))
    if not box then return end
    if not typing then box.num:SetText(tostring(Make.amount)) end
    box.less.SetOff(Make.amount <= 1)
    box.more.SetOff(Make.amount >= Make.Most())
end

local function amountBox(foot)
    local W = DUI.Widgets
    local box = CreateFrame("Frame", nil, foot.frame)
    box:SetSize(Make.STEP_W * 2 + Make.NUM_W + 8, 24)
    box:EnableMouseWheel(true)
    box.less = W.Button(box, "-", 24)
    box.less:SetWidth(Make.STEP_W)
    box.less:SetPoint("LEFT", box, "LEFT", 0, 0)
    box.num = W.Input(box, { height = 24, size = Style.SIZE.body, justify = "CENTER", numeric = true, maxLetters = 4,
        onChange = function(text, user) if user then Make.SetAmount(text, true) end end })
    box.num:SetWidth(Make.NUM_W)
    box.num:SetPoint("LEFT", box.less, "RIGHT", 4, 0)
    W.PadSkip(box.num)   -- controllers step with - and +, no typing
    box.more = W.Button(box, "+", 24)
    box.more:SetWidth(Make.STEP_W)
    box.more:SetPoint("LEFT", box.num, "RIGHT", 4, 0)
    local function step(d) Make.SetAmount((Make.amount or 1) + d) end
    box.less:SetScript("OnClick", function() step(-1) end)
    box.more:SetScript("OnClick", function() step(1) end)
    box:SetScript("OnMouseWheel", function(_, d) step(d > 0 and 1 or -1) end)
    box.num:SetScript("OnMouseWheel", function(_, d) step(d > 0 and 1 or -1) end)
    box.num:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Make.Create() end)
    box.num:HookScript("OnEditFocusLost", function(self) self:SetText(tostring(Make.amount or 1)) end)
    return box
end

-- Crafting and the progress row

function Make.Busy() return Make.state ~= nil end

function Make.Start(r, n)
    if not r or n < 1 or Make.state then return end
    local target = Make.TargetFor(r)
    Make.state = { id = r.id, total = n, done = 0, enchant = r.enchant, guid = target and target.guid }
    Make.asked = nil
    -- Craft first: hiding the pressed button before the call gets it blocked ("the game
    -- blocked UNKNOWN()").
    if r.enchant then
        call("CraftEnchant", r.id, n, nil, target and target.loc)
    else
        call("CraftRecipe", r.id, n)
    end
    if Make.state then Make.ShowProgress(true) end   -- nil: the game's replace prompt came up during the call
end

function Make.Create()
    local r = Make.recipe
    if not r or r.count < 1 then return end
    Make.Start(r, (r.enchant and not Make.TargetFor(r)) and 1 or (Make.amount or 1))
end

function Make.CreateAll()
    local r = Make.recipe
    if not r or r.count < 2 or (r.enchant and not Make.TargetFor(r)) then return end
    Make.Start(r, r.count)
end

local function progressText()
    local s = Make.state
    local row = Make.row
    if not (s and row) then return end
    local pop = Win.Parts.Hex({ Style.Pop() })
    row.text:SetText(string.format(L["Making %s of %s"], pop .. math.min(s.done + 1, s.total) .. "|r", pop .. s.total .. "|r"))
end

-- The bar follows the current cast (UnitCastingInfo start and end, in ms).
local function drive(row)
    local s = Make.state
    if not (s and s.from and s.to) then return end
    local now = GetTime() * 1000
    row.bar:SetValue(math.max(s.from, math.min(s.to, now)))
end

function Make.ShowProgress(on)
    local foot, row = Make.foot, Make.row
    if not (foot and row) then return end
    local M = DUI.Motion
    if on then
        progressText()
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)
        DUI.Widgets.BarAccent(row.bar)
        row:Show()
        foot.frame:Hide()
        if Make.box then Make.box:Hide() end
        if M then M.Fade(row, 0, 1, M.FAST) end
        local s = Make.state
        if s and ns.Window then ns.Window.Tell("CraftStarted", s.id, s.total) end
    else
        row:SetScript("OnUpdate", nil)
        row:Hide()
        if Make.caster then Make.caster.Hide() end
        foot.frame:Show()
        if M then M.Fade(foot.frame, 0, 1, M.FAST) end
        if Make.recipe then Make.Paint(Make.recipe) end
    end
end

function Make.Finish()
    local s = Make.state
    if not s then return end
    Make.state = nil
    if ns.Window then ns.Window.Tell("CraftStopped", s.id, s.done, s.total) end
    Make.ShowProgress(false)
end

-- Cast events for the player's own crafts (plain, see the top of the file).
function Make.OnCast(event, unit, _, spellID)
    if secret(unit) or unit ~= "player" or secret(spellID) then return end
    local asked = Make.asked
    if asked and not Make.state and event == "UNIT_SPELLCAST_START" and spellID == asked.id then
        Make.state, Make.asked = asked, nil   -- said yes to the game's prompt
        Make.ShowProgress(true)
    end
    local s = Make.state
    if not s or spellID ~= s.id then return end
    local row = Make.row
    if event == "UNIT_SPELLCAST_START" then
        s.casting = true
        local _, _, _, from, to = UnitCastingInfo("player")
        if issecretvalue and (issecretvalue(from) or issecretvalue(to)) then from, to = nil, nil end
        if type(from) == "number" and type(to) == "number" and to > from then
            s.from, s.to = from, to
            row.bar:SetMinMaxValues(from, to)
            row:SetScript("OnUpdate", drive)
        end
        progressText()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        s.done = s.done + 1
        s.casting = false
        if s.guid and s.putting then Make.laid[s.guid] = s.putting end
        local line = ns.List.lines and ns.List.lines[s.id]
        if line and line:IsVisible() then Win.Parts.Shine(line) end
        if ns.Window then ns.Window.Tell("CraftMade", s.id, s.done, s.total) end
        if s.done >= s.total then return Make.Finish() end
        row:SetScript("OnUpdate", nil)
        progressText()
        if s.enchant then   -- the game can stop early without saying so; bring the footer back
            local done = s.done
            C_Timer.After(Make.GAP, function()
                if Make.state == s and s.done == done and not s.casting then Make.Finish() end
            end)
        end
    else   -- FAILED, INTERRUPTED: the rest won't happen
        Make.Finish()
    end
end

local function progressRow(pane, foot)
    local W = DUI.Widgets
    local row = CreateFrame("Frame", nil, pane)
    row:SetAllPoints(foot.frame)
    row:Hide()
    row.text = Style.Text(row, Style.SIZE.body, "LEFT")
    row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
    Style.InkText(row.text, "TEXT")
    row.stop = W.Button(row, STOP or L["Stop"], 28)
    row.stop.FitWidth(80)
    row.stop:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.bar = W.Bar(row)
    row.bar:SetPoint("LEFT", row, "LEFT", 130, 0)
    row.bar:SetPoint("RIGHT", row.stop, "LEFT", -12, 0)
    -- Stop: the secure /stopcasting over this button (see the top of the file).
    row.stop:HookScript("OnEnter", function(self)
        if Make.caster then Make.caster.Over(self, { type1 = "macro", macrotext1 = "/stopcasting" }) end
    end)
    Make.caster = Win.Caster({ name = "DaylightUICraftStop",
        above = function() return ns.Window and ns.Window.frame end,
        enter = function(b) b.Hover(true) end,
        leave = function(b) b.Hover(false) end,
        post = function() if DUI.Sound then DUI.Sound.Play("click") end end })
    return row
end

-- Footer

function Make.Build(pane)
    local foot = Win.Parts.Footer(pane)
    Make.foot = foot
    Make.row = progressRow(pane, foot)
    pane:HookScript("OnHide", function() if Make.caster then Make.caster.Hide() end end)
    -- Player casts only, filtered by the client; a raid's casts would wake this constantly.
    local casts = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        casts:RegisterUnitEvent(e, "player")
    end
    casts:SetScript("OnEvent", function(_, event, ...) Make.OnCast(event, ...) end)
    DUI.RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED", function() Make.Finish() end)
    -- An enchant waiting for its item: canceling there (right-click, Escape) fires only
    -- this event, never a cast event. Another spell canceled before the recipe's first
    -- cast isn't the craft's.
    DUI.RegisterEvent("CURRENT_SPELL_CAST_CHANGED", function(_, canceled)
        if secret(canceled) or canceled ~= true then return end
        if Make.state and Make.state.enchant and not Make.state.from then Make.Finish() end
    end)
    DUI.RegisterEvent("TRADE_SKILL_CLOSE", function() Make.Finish() end)
    DUI.RegisterEvent("REPLACE_TRADESKILL_ENCHANT", function(_, existing, replacement)
        Make.OnReplace("REPLACE_TRADESKILL_ENCHANT", "ReplaceTradeskillEnchant", existing, replacement)
    end)
    DUI.RegisterEvent("REPLACE_ENCHANT", function(_, existing, replacement)
        Make.OnReplace("REPLACE_ENCHANT", "ReplaceEnchant", existing, replacement)
    end)
end

-- Controller, like the game's crafting footer (Blizzard_ProfessionsFrame.lua
-- SetUpGamepadCraftingPageFooter): X crafts the set amount, X held crafts all (tap or
-- hold, Pad.HOLD). The amount steps with - and +; its box is skipped on a controller.
function Make.PadKeys(f)
    local function can(n)
        local r = Make.recipe
        return r ~= nil and not Make.state and r.count >= n
    end
    f.padKeys = f.padKeys or {}
    table.insert(f.padKeys, { key = "X", label = function() return Make.recipe and verb(Make.recipe) or L["Create"] end,
        run = function() Make.Create() end, when = function() return can(1) end,
        hold = { label = function() return allWords(Make.recipe.count, Make.recipe.enchant) end,
                 run = function() Make.CreateAll() end,
                 when = function() return can(2) and not (Make.recipe.enchant and not Make.TargetFor(Make.recipe)) end } })
end

-- The footer for recipe r (nil: none selected). A new recipe starts at one.
function Make.Paint(r)
    local foot = Make.foot
    if not foot then return end
    if r ~= Make.recipe and not (r and Make.recipe and r.id == Make.recipe.id) then Make.amount = 1 end
    Make.recipe = r
    if Make.state then return end
    if not r then
        foot:Set({})
        if Make.box then Make.box:Hide() end
        return
    end
    local many = not r.enchant or Make.TargetFor(r) ~= nil
    local list = { { text = verb(r), primary = true, off = r.count < 1, onClick = Make.Create } }
    if many then
        list[2] = { text = allWords(r.count, r.enchant), off = r.count < 2, onClick = Make.CreateAll }
    end
    foot:Set(list)
    Make.box = Make.box or amountBox(foot)
    Make.box:SetShown(many)
    Make.box:ClearAllPoints()
    Make.box:SetPoint("LEFT", foot.buttons[1], "RIGHT", 12, 0)
    Make.SetAmount(Make.amount or 1)
end
