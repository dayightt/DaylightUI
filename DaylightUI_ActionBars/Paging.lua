-- Bar 1's page, i.e. which 12 action slots it shows. The game pages its own bar 1
-- from Lua on events; ours uses a state driver built from macro conditions in the
-- game's order (override bar, vehicle, possess, temporary shapeshift, a page picked
-- by hand, then forms and stances). Each change is also written to the game's hidden
-- bar 1, so a keybind (which presses its hidden button) casts what our button shows.

local _, ns = ...
local DUI = DaylightUI

local Paging = {}
ns.Paging = Paging

-- The special pages when the game can't tell us (confirmed in game). Older addons
-- use 12 and 14, which are wrong here.
Paging.FALLBACK = { override = 33, vehicle = 31, temp = 32 }

local function index(fn, fallback)
    if type(fn) ~= "function" then return fallback end
    local ok, v = pcall(fn)
    if ok and type(v) == "number" and v > 0 then return v end
    return fallback
end

-- A druid's forms by spell, and the bonus bar each one is (Bear and Dire Bear are
-- one form). The client's bonus bar goes stale on a powershift ("/cast !Cat Form"
-- left the caster bar up in Cat Form; the FormBars addon pages by form for the same
-- reason), so a druid's bars page by the form itself ([form:N], N = its place on the
-- stance bar). Travel and Aquatic have no bar of their own (page 1).
-- A priest's Shadowform sits on the stance bar but gives no bonus bar at all,
-- so it pages by its form the same way, as form 1.
Paging.FORM_BONUS = { [768] = 1, [5487] = 3, [9634] = 3, [24858] = 4, [15473] = 1 }
Paging.FORM_CLASSES = { DRUID = true, PRIEST = true }

-- For a druid or priest: bonus bar -> "form:N" (or "form:N/M"), from the current
-- stance bar. nil for any other class, or one who knows none of the forms (then
-- the bonus bar is used, as before).
function Paging.FormConds()
    if not Paging.FORM_CLASSES[Paging.Class()] then return nil end
    if type(GetNumShapeshiftForms) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then return nil end
    local out, any = {}, false
    for i = 1, GetNumShapeshiftForms() or 0 do
        local ok, _, _, _, sid = pcall(GetShapeshiftFormInfo, i)
        local bonus = ok and type(sid) == "number" and not (issecretvalue and issecretvalue(sid))
            and Paging.FORM_BONUS[sid] or nil
        -- Shadowform is a priest's only form, so it is that one whatever spell id
        -- this server gives it.
        if ok and not bonus and Paging.Class() == "PRIEST" then bonus = 1 end
        if bonus then
            out[bonus] = out[bonus] and (out[bonus] .. "/" .. i) or ("form:" .. i)
            any = true
        end
    end
    return any and out or nil
end

-- A rule's "bonusbar:N" (1-4, the forms) as this character's condition: a druid's
-- form, or nil when the druid doesn't have that form.
function Paging.Bonus(cond, forms)
    if not forms then return cond end
    local n = tonumber(string.match(cond, "bonusbar:(%d)"))
    if not n or n > 4 then return cond end
    local form = forms[n]
    return form and (string.gsub(cond, "bonusbar:%d", form)) or nil
end

-- "[bonusbar:1] 7; [bonusbar:2] 8; ..." with each condition through Paging.Bonus.
local function bonusRule(rule, forms)
    local parts = {}
    for cond, rest in string.gmatch(rule, "%[([^%]]+)%]([^;]*)") do
        local c = Paging.Bonus(cond, forms)
        if c then parts[#parts + 1] = "[" .. c .. "] " .. string.match(rest, "^%s*(.-)%s*$") end
    end
    return table.concat(parts, "; ")
end

-- The rule's clauses, in order; each returns a clause or nil. Form N is page 6 + N
-- for every class (confirmed in game). Custom paging can add clauses.
Paging.CLAUSES = {
    function() return "[overridebar] " .. index(GetOverrideBarIndex, Paging.FALLBACK.override) end,
    function() return "[vehicleui] " .. index(GetVehicleBarIndex, Paging.FALLBACK.vehicle) end,
    function() return "[possessbar] " .. index(GetVehicleBarIndex, Paging.FALLBACK.vehicle) end,
    function() return "[shapeshift] " .. index(GetTempShapeshiftBarIndex, Paging.FALLBACK.temp) end,
    function() return Paging.HeldRule() end,
    function() return Paging.PageRule("[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6", "p") end,
    function()
        local forms = Paging.FormConds()
        local rule = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11"
        if forms then
            -- Cat (7) before Bear (9), since Cat's place on the stance bar may come after.
            rule = bonusRule(rule, forms)
        end
        return Paging.PageRule(rule, "f")
    end,
}

-- Bar 1's own page changes (pages picked by hand, forms and stances), or page 1 under
-- each of them with bars.main.autoPage off. The game still writes its hidden bar 1's
-- page on each change, so each one stays its own state ("1:f1") and the snippet
-- writes page 1 back onto the twin.
function Paging.PageRule(rule, tag)
    local cfg = ns.Shape and ns.Shape.Config("main")
    if type(cfg) ~= "table" or cfg.autoPage ~= false then return rule end
    local n = 0
    return (rule:gsub("%] %d+", function() n = n + 1; return "] 1:" .. tag .. n end))
end

-- Bar 1's held-modifier pages (bars.main.paging.shift/ctrl/alt). The game writes its
-- hidden bar 1's page on every form or page change, even while a modifier is held.
-- So each held page carries a tag for the form or page under it ("13:f1"), the state
-- changes along with it, and the snippet writes the held page back onto the twin.
-- That way the key always casts what the button shows.
local TAGS = {}
for n = 2, 6 do TAGS[#TAGS + 1] = { "bar:" .. n, "p" .. n } end
for n = 1, 5 do TAGS[#TAGS + 1] = { "bonusbar:" .. n, "f" .. n } end
function Paging.HeldRule()
    local picks = ns.Shape and ns.Shape.Config("main").paging
    if type(picks) ~= "table" then return nil end
    local forms = Paging.FormConds()
    local parts = {}
    for _, state in ipairs(Paging.STATES) do
        local page = tonumber(picks[state.id])
        if state.held and page and page >= 1 and page <= Paging.PAGES and page ~= 1 then
            local mod = state.cond:sub(2, -2)
            for _, tag in ipairs(TAGS) do
                local cond = Paging.Bonus(tag[1], forms)
                if cond then parts[#parts + 1] = "[" .. mod .. "," .. cond .. "] " .. page .. ":" .. tag[2] end
            end
            parts[#parts + 1] = state.cond .. " " .. page
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "; ")
end

function Paging.Rule()
    local parts = {}
    for _, clause in ipairs(Paging.CLAUSES) do
        local c = clause()
        if c then parts[#parts + 1] = c end
    end
    parts[#parts + 1] = "1"
    return table.concat(parts, "; ")
end

-- The holder's snippet: writes the page onto itself, its buttons and the game's
-- hidden twin bar, whose buttons read their slot from its "actionpage" when a key
-- presses them (SecureActionButtonMixin:CalculateAction), so the key casts what our
-- button shows. Never CallMethod in a snippet; it would leave secure code.
Paging.ON_STATE = [[
    local page = tonumber(string.match(newstate or "", "^%d+")) or 1
    -- A powershift's form held (Paging.HOLD): while the game says caster
    -- form (the cancel half, until the server confirms the new form), the
    -- form's page stays up; any form at all ends the hold.
    local hold = self:GetAttribute("dui-hold")
    if hold then
        if GetShapeshiftForm() == 0 then
            page = hold
        else
            self:SetAttribute("dui-hold", nil)
            self:SetAttribute("state-hold", nil)
        end
    end
    self:SetAttribute("actionpage", page)
    self:ChildUpdate("page", page)
    local twin = self:GetFrameRef("game-twin")
    if twin then twin:SetAttribute("actionpage", page) end
    -- Bar 1's: on each of the game's hidden buttons too, which read their
    -- own page before their bar's, so the game's own (stale) bar 1 write
    -- can't change what a key casts.
    for i = 1, 12 do
        local b = self:GetFrameRef("game-btn" .. i)
        if not b then break end
        b:SetAttribute("actionpage", page)
    end
]]

-- Each bar 1 button: its slot on the new page.
Paging.CHILD = [[
    self:SetAttribute("action", self:GetAttribute("dui-index") + ((tonumber(message) or 1) - 1) * 12)
]]

local holder

-- ---------------------------------------------------------------------
-- Powershifting. After "/cast !Cat Form" the game reports caster form until the
-- server confirms Cat Form (a second or more), so bar 1 showed the caster bar that
-- long. The game can't tell ahead of time and an addon can't see the key press (it
-- goes to the game's hidden button). So a druid adds "/click DaylightUICat" (or
-- Bear, Moonkin) to the top of the shift macro, like the FormBars addon does. The
-- click (the game's secure "attribute" action) arms bar 1 with that form's page, the
-- drop to caster that follows shows that page, and the form coming back (or any
-- other form) ends it. A click whose shift never happened is released a moment
-- later, out of combat.
-- ---------------------------------------------------------------------

Paging.HOLD = { { name = "DaylightUICat", bonus = 1 }, { name = "DaylightUIBear", bonus = 3 },
                { name = "DaylightUIMoonkin", bonus = 4 } }
Paging.HOLD_FOR = 3          -- seconds an unused click stays armed (out of combat)

Paging.ON_HOLD = [[
    local page = tonumber(newstate)
    if page then self:SetAttribute("dui-hold", page) end
]]

-- The page a form's button arms bar 1 with: the form's own page, or nothing with
-- "Change with forms and stances" off (the bar stays on page 1 anyway).
function Paging.HoldPage(bonus)
    local cfg = ns.Shape and ns.Shape.Config("main")
    if type(cfg) == "table" and cfg.autoPage == false then return nil end
    return 6 + bonus
end

-- Releases the hold when no shift followed the click, and rewrites the page through
-- the snippet so a hold left showing in caster form goes back.
function Paging.LetGo()
    if not holder or not holder:GetAttribute("dui-hold") then return end
    holder:SetAttribute("dui-hold", nil)
    holder:SetAttribute("state-hold", nil)
    holder:SetAttribute("state-page", holder:GetAttribute("state-page"))
end

local holdButtons = {}
local function makeHoldButtons(h)
    if #holdButtons > 0 or Paging.Class() ~= "DRUID" then return end
    for _, def in ipairs(Paging.HOLD) do
        local b = CreateFrame("Button", def.name, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "attribute")
        b:SetAttribute("attribute-frame", h)
        b:SetAttribute("attribute-name", "state-hold")
        b:HookScript("OnClick", function()
            C_Timer.After(Paging.HOLD_FOR, function() DUI.AfterCombat(Paging.LetGo, "paging:letgo") end)
        end)
        holdButtons[#holdButtons + 1] = { button = b, bonus = def.bonus }
    end
end

local function holdPages()
    for _, hb in ipairs(holdButtons) do hb.button:SetAttribute("attribute-value", Paging.HoldPage(hb.bonus)) end
end

-- At file load, out of combat: the snippets, the driver, and the rule rebuilt once
-- the game knows its page numbers for sure.
function Paging.Setup(h, buttons)
    holder = h
    h:SetAttribute("_onstate-hold", Paging.ON_HOLD)
    makeHoldButtons(h)
    if type(MainActionBar) == "table" then h:SetFrameRef("game-twin", MainActionBar) end
    for i = 1, 12 do
        local b = _G["ActionButton" .. i]
        if type(b) == "table" then h:SetFrameRef("game-btn" .. i, b) end
    end
    h:SetAttribute("_onstate-page", Paging.ON_STATE)
    for _, btn in ipairs(buttons) do btn:SetAttribute("_childupdate-page", Paging.CHILD) end
    Paging.Apply()
    -- The class may not be known yet at file load; then the buttons are made here.
    local function again() DUI.AfterCombat(function() makeHoldButtons(h); Paging.Apply() end, "paging:rule") end
    DUI.RegisterEvent("PLAYER_LOGIN", again)
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", again)
    -- A form learned or lost shifts a druid's form numbers.
    DUI.RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function()
        DUI.AfterCombat(function()
            Paging.Apply()
            if ns.Bars then
                for _, def in ipairs(ns.Bars.DEFS) do
                    local h = ns.Bars.holders[def.key]
                    if def.page and not def.paged and h then DUI.SafeCall(Paging.ApplyBar, def, h) end
                end
            end
        end, "paging:forms")
    end)
end

local lastRule
function Paging.Apply()
    if not holder then return end
    holdPages()
    local rule = Paging.Rule()
    if rule == lastRule then return end
    lastRule = rule
    RegisterStateDriver(holder, "page", rule)
end

-- ---------------------------------------------------------------------
-- Bars 2-8: a page of the player's choosing per stance, form or held modifier
-- (bars.<key>.paging.<state> = a page, 0 = no change). Bar 1 only takes the held
-- modifiers (Paging.HeldRule): its forms already page it, and the game writes its
-- hidden bar 1's page itself on every form change (ActionBarController_UpdateAll).
-- The game never writes bars 2-8's page (a fixed attribute in
-- MultiActionBars.xml), so ours holds.
-- ---------------------------------------------------------------------

-- In the order they're checked: a held modifier beats a form, Prowl comes before Cat
-- Form. On Forever every class's form N is bonus bar N (bar 1's rule).
-- class = only that class has it.
Paging.STATES = {
    { id = "shift", held = true, cond = "[mod:shift]", name = "Shift", when = "while you hold Shift" },
    { id = "ctrl", held = true, cond = "[mod:ctrl]", name = "Ctrl", when = "while you hold Ctrl" },
    { id = "alt", held = true, cond = "[mod:alt]", name = "Alt", when = "while you hold Alt" },
    { id = "prowl", class = "DRUID", cond = "[bonusbar:1,stealth]", name = "Prowl", when = "while you prowl" },
    { id = "cat", class = "DRUID", cond = "[bonusbar:1]", name = "Cat Form", when = "in Cat Form" },
    { id = "bear", class = "DRUID", cond = "[bonusbar:3]", name = "Bear Form", when = "in Bear Form" },
    { id = "stealth", class = "ROGUE", cond = "[bonusbar:1]", name = "Stealth", when = "in Stealth" },
    { id = "battle", class = "WARRIOR", cond = "[bonusbar:1]", name = "Battle Stance", when = "in Battle Stance" },
    { id = "defensive", class = "WARRIOR", cond = "[bonusbar:2]", name = "Defensive Stance", when = "in Defensive Stance" },
    { id = "berserker", class = "WARRIOR", cond = "[bonusbar:3]", name = "Berserker Stance", when = "in Berserker Stance" },
    { id = "shadowform", class = "PRIEST", cond = "[bonusbar:1]", name = "Shadowform", when = "in Shadowform" },
}

-- The number of pages (12 slots each); 0 = no change.
Paging.PAGES = 15

function Paging.Class()
    local _, class = UnitClass("player")
    return class
end

-- Whether the player has this state (a class state only for that class).
function Paging.Has(state)
    return state.class == nil or state.class == Paging.Class()
end

-- A bar's rule, or nil when nothing is picked (the bar keeps its page).
function Paging.BarRule(def)
    local picks = ns.Shape.Config(def.key).paging
    if type(picks) ~= "table" then return nil end
    local forms = Paging.FormConds()
    local parts = {}
    for _, state in ipairs(Paging.STATES) do
        local page = tonumber(picks[state.id])
        local cond = Paging.Has(state) and Paging.Bonus(state.cond:sub(2, -2), forms)
        if page and page >= 1 and page <= Paging.PAGES and page ~= def.page and cond then
            parts[#parts + 1] = "[" .. cond .. "] " .. page
        end
    end
    if #parts == 0 then return nil end
    parts[#parts + 1] = tostring(def.page)
    return table.concat(parts, "; ")
end

-- At build: the same snippets as bar 1, onto the bar's own twin.
function Paging.SetupBar(def, h, buttons)
    local twin = def.twin and _G[def.twin]
    if type(twin) == "table" then h:SetFrameRef("game-twin", twin) end
    h:SetAttribute("_onstate-page", Paging.ON_STATE)
    for _, btn in ipairs(buttons) do btn:SetAttribute("_childupdate-page", Paging.CHILD) end
    Paging.ApplyBar(def, h)
end

-- Applies the bar's rule as a driver, or removes the driver and restores its own
-- page. Does nothing when unchanged since last time (Bars.Relayout runs on every
-- bar setting). Out of combat only.
local rules = {}
function Paging.ApplyBar(def, h)
    if not h:GetAttribute("_onstate-page") then return end
    local rule = Paging.BarRule(def) or false
    if rules[h] == rule then return end
    rules[h] = rule
    if rule then
        RegisterStateDriver(h, "page", rule)
    else
        UnregisterStateDriver(h, "page")
        h:SetAttribute("state-page", def.page)
    end
end
