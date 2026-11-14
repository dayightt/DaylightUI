-- Click-casting: cast a spell on a unit by clicking its frame (any mouse
-- button, with Shift, Ctrl or Alt). Bindings are per character, one list per
-- talent set (DB.Character().clickCast[1|2]), edited by the spellbook binder
-- (ClickBinder.lua) and the options page (Unit Frames > Click-casting).
-- Nothing is bound until the player binds something, so left-click targets
-- and right-click opens the menu as usual.
--
-- Each binding is a pair of secure attributes on every addon frame
-- (`shift-type2 = "spell"`, `shift-spell2 = <spell>`), read by the game's
-- SecureUnitButton click handler. Attributes can only be written out of
-- combat. A button a group header creates mid-fight gets them from the header,
-- which copies its `_initialAttribute-<name>` attributes onto each new button
-- in secure code (SecureGroupHeaders.lua, SetupUnitButtonConfiguration).
-- When Clique is loaded it handles click-casting and this steps aside.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local CC = {}
ns.ClickCast = CC

-- The mouse buttons a binding can use and their attribute suffixes
-- (SecureButton_GetButtonSuffix).
CC.BUTTONS = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
CC.SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3", Button4 = "4", Button5 = "5" }
CC.BUTTON_TEXT = { LeftButton = L["Left click"], RightButton = L["Right click"], MiddleButton = L["Middle click"],
                   Button4 = L["Button 4"], Button5 = L["Button 5"] }
-- Modifiers in the order the game builds its prefix ("alt-ctrl-shift-",
-- SecureButton_GetModifierPrefix).
CC.MODS = { "alt", "ctrl", "shift" }
CC.MOD_TEXT = { alt = L["Alt"], ctrl = L["Ctrl"], shift = L["Shift"] }

CC.applied = {}       -- attribute -> value, as currently set on every frame
local EMPTY = {}

-- Clicks

local function held(fn) return type(fn) == "function" and fn() and true or false end

-- The modifiers held now, in binding format: "", "shift", "alt-ctrl"...
function CC.Mods()
    local out = {}
    if held(IsAltKeyDown) then out[#out + 1] = "alt" end
    if held(IsControlKeyDown) then out[#out + 1] = "ctrl" end
    if held(IsShiftKeyDown) then out[#out + 1] = "shift" end
    return table.concat(out, "-")
end

-- e.g. "Shift + Right click", "Left click".
function CC.Describe(mods, button)
    local parts = {}
    for m in string.gmatch(mods or "", "[^%-]+") do parts[#parts + 1] = CC.MOD_TEXT[m] or m end
    parts[#parts + 1] = CC.BUTTON_TEXT[button] or tostring(button)
    return table.concat(parts, " + ")
end

local function validMods(mods)
    if type(mods) ~= "string" then return false end
    if mods == "" then return true end
    local seen, last = {}, 0
    for m in string.gmatch(mods, "[^%-]+") do
        local at
        for i, known in ipairs(CC.MODS) do if known == m then at = i end end
        if not at or seen[m] or at < last then return false end
        seen[m], last = true, at
    end
    return true
end

local function valid(b)
    return type(b) == "table" and CC.SUFFIX[b.button] ~= nil and validMods(b.mods)
        and type(b.spell) == "number"
end

-- The bindings (this character, one list per talent set)

-- With Clique loaded, Clique handles click-casting and nothing is written here.
-- The Forever port of Clique loads as CliqueForever.
CC.CLIQUE = { "Clique", "CliqueForever" }
function CC.Stepped()
    if not (C_AddOns ~= nil and type(C_AddOns.IsAddOnLoaded) == "function") then return false end
    for _, name in ipairs(CC.CLIQUE) do
        if C_AddOns.IsAddOnLoaded(name) == true then return true end
    end
    return false
end

-- The talent set's list (the active one when not given). Read-only while
-- nothing is bound, so the saved file only gets the table once it's used.
function CC.List(group)
    local all = DUI.DB.Character().clickCast
    local list = type(all) == "table" and all[group or DUI.DB.SpecGroup()]
    return type(list) == "table" and list or EMPTY
end

local function writable()
    local c = DUI.DB.Character()
    if type(c.clickCast) ~= "table" then c.clickCast = {} end
    local g = DUI.DB.SpecGroup()
    if type(c.clickCast[g]) ~= "table" then c.clickCast[g] = {} end
    return c.clickCast[g]
end

-- The binding on a click: index, binding.
function CC.Find(mods, button)
    for i, b in ipairs(CC.List()) do
        if valid(b) and b.mods == mods and b.button == button then return i, b end
    end
end

-- The clicks a spell is bound to, as text ("Shift + Right click").
function CC.ClicksFor(spell)
    local out = {}
    for _, b in ipairs(CC.List()) do
        if valid(b) and b.spell == spell then out[#out + 1] = CC.Describe(b.mods, b.button) end
    end
    return out
end

-- Whether this spell at this rank is the highest rank known. If so it's cast
-- by plain name and follows new ranks, otherwise by name and rank.
function CC.IsTopRank(spell, name)
    if not (C_Spell and type(C_Spell.GetSpellInfo) == "function") or type(name) ~= "string" then return true end
    local ok, top = pcall(C_Spell.GetSpellInfo, name)
    if not ok or type(top) ~= "table" or type(top.spellID) ~= "number" then return true end
    return top.spellID == spell
end

-- Binds a click to a spell, replacing whatever that click had.
function CC.Bind(mods, button, spell, name, rank)
    if not (CC.SUFFIX[button] and validMods(mods) and type(spell) == "number") then return false end
    local list = writable()
    local entry = { mods = mods, button = button, spell = spell, name = name, rank = rank ~= "" and rank or nil,
                    byName = CC.IsTopRank(spell, name) or nil }
    local i = CC.Find(mods, button)
    if i then list[i] = entry else list[#list + 1] = entry end
    CC.Changed()
    return true
end

-- The binder's click. The same click on the same spell again unbinds it.
-- Returns "bound" or "removed".
function CC.Toggle(mods, button, spell, name, rank)
    local i, b = CC.Find(mods, button)
    if i and b.spell == spell then
        CC.Unbind(i)
        return "removed"
    end
    CC.Bind(mods, button, spell, name, rank)
    return "bound"
end

function CC.Unbind(i)
    local list = CC.List()
    if list[i] == nil then return end
    table.remove(list, i)
    CC.Changed()
end

-- Moves binding i to another click, replacing any binding already there.
function CC.Rebind(i, mods, button)
    local list = CC.List()
    local b = list[i]
    if not (valid(b) and CC.SUFFIX[button] and validMods(mods)) then return false end
    if b.mods == mods and b.button == button then return true end
    local other = CC.Find(mods, button)
    b.mods, b.button = mods, button
    if other then table.remove(list, other) end
    CC.Changed()
    return true
end

function CC.Clear()
    local c = DUI.DB.Character()
    if type(c.clickCast) == "table" then c.clickCast[DUI.DB.SpecGroup()] = nil end
    CC.Changed()
end

-- A spell the character doesn't currently know (other talent set, unlearned).
function CC.Known(spell)
    if type(IsPlayerSpell) == "function" then return IsPlayerSpell(spell) == true end
    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then return C_SpellBook.IsSpellKnown(spell) == true end
    return true
end

-- Mouseover casting: the game's own setting (Options > Combat), which aims
-- action bar spells at whoever the mouse is over. Stored by the game, not in
-- addon settings, so its page and this one always agree.

CC.MOUSEOVER_CVAR = "enableMouseoverCast"
CC.MOUSEOVER_CLICK = "MOUSEOVERCAST"
CC.MOUSEOVER_KEYS = { "NONE", "ALT", "CTRL", "SHIFT" }

-- Whether this client has the setting (the game's own check, from its Combat.lua).
function CC.MouseoverSupported()
    if type(IsMouseoverCastSupported) == "function" and not IsMouseoverCastSupported() then return false end
    return type(GetCVar) == "function" and GetCVar(CC.MOUSEOVER_CVAR) ~= nil
end

function CC.MouseoverOn()
    return type(GetCVarBool) == "function" and GetCVarBool(CC.MOUSEOVER_CVAR) == true
end

-- Not in addon settings, so tell the window to update the row.
local function mouseoverChanged(key, v)
    DUI.Fire("SettingChanged", "UnitFrames", "clickcast." .. key, v)
end

function CC.SetMouseover(on)
    DUI.AfterCombat(function()
        pcall(SetCVar, CC.MOUSEOVER_CVAR, on and "1" or "0")
        mouseoverChanged("mouseover", on == true)
    end, "clickcast:mouseover")
end

-- "NONE" means always, otherwise the key to hold.
function CC.MouseoverKey()
    local k = type(GetModifiedClick) == "function" and GetModifiedClick(CC.MOUSEOVER_CLICK)
    return type(k) == "string" and k or "NONE"
end

-- Same as the game's own row (ModifiedClickSettingMixin): set, then save.
function CC.SetMouseoverKey(key)
    DUI.AfterCombat(function()
        pcall(SetModifiedClick, CC.MOUSEOVER_CLICK, key)
        pcall(SaveBindings, GetCurrentBindingSet())
        mouseoverChanged("mouseoverKey", key)
    end, "clickcast:mouseoverKey")
end

-- Mouse buttons with a key binding (e.g. Button 4 on an action bar slot).
-- Over a unit frame, a mouse button is that frame's click, so the key binding
-- never runs and mouseover casting can't reach the player under the mouse.
-- Each such click not used by a click-cast binding instead presses what the
-- key binding presses (`/click` on the action button). The action button aims
-- it at the hovered unit itself when mouseover casting is on
-- (`checkmouseovercast`, SecureButton_GetModifiedUnit), or at the target when
-- it's off. Left and right click stay target and menu.

CC.FORWARD = { "MiddleButton", "Button4", "Button5" }
CC.FORWARD_KEY = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
-- The game's bar binding commands and the buttons they press, by the game's
-- names. ActionBars presses the same ones (Bars.lua `twinPrefix`).
CC.BAR_BUTTONS = {
    ACTIONBUTTON = "ActionButton",
    MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
    MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
    MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
    MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
    MULTIACTIONBAR5BUTTON = "MultiBar5Button",
    MULTIACTIONBAR6BUTTON = "MultiBar6Button",
    MULTIACTIONBAR7BUTTON = "MultiBar7Button",
}
-- Every modifier combination in binding format ("", "alt", ..., "alt-ctrl-shift").
local MOD_SETS = { "" }
for _, m in ipairs(CC.MODS) do
    for i = 1, #MOD_SETS do
        local s = MOD_SETS[i]
        MOD_SETS[#MOD_SETS + 1] = s == "" and m or (s .. "-" .. m)
    end
end
CC.MOD_SETS = MOD_SETS

-- What a key binding's command presses, as a macro line. nil when it isn't a
-- button (movement, a menu...), which a frame's click can't stand in for.
function CC.ClickFor(command)
    if type(command) ~= "string" then return nil end
    local frame, button = command:match("^CLICK ([^:]+):(.+)$")
    if frame then return "/click " .. frame .. " " .. button end
    local bar, n = command:match("^(.-BUTTON)(%d+)$")
    local prefix = bar and CC.BAR_BUTTONS[bar]
    if prefix then return "/click " .. prefix .. n end
end

-- The forwarded clicks' attributes: { { key, value }, ... }. A key binding
-- with no modifiers also runs with modifiers held that have no binding of
-- their own (that's how the self-cast key works), so it's written for every
-- modifier ("*"). A modified one bound to something else blocks it
-- (ATTRIBUTE_NOOP). A modified click-cast binding wins by its exact prefix.
function CC.Forwards(list)
    local out = {}
    if type(GetBindingAction) ~= "function" then return out end
    local taken = {}
    for _, b in ipairs(list) do
        if valid(b) then taken[b.mods .. "|" .. b.button] = true end
    end
    local noop = ATTRIBUTE_NOOP or ""
    for _, button in ipairs(CC.FORWARD) do
        local suffix, key = CC.SUFFIX[button], CC.FORWARD_KEY[button]
        local plain = CC.ClickFor(GetBindingAction(key))
        if plain then
            out[#out + 1] = { "*type" .. suffix, "macro" }
            out[#out + 1] = { "*macrotext" .. suffix, plain }
        end
        for i = 2, #MOD_SETS do
            local mods = MOD_SETS[i]
            if not taken[mods .. "|" .. button] then
                local action = GetBindingAction(mods:upper() .. "-" .. key)
                local text = CC.ClickFor(action)
                if text then
                    out[#out + 1] = { mods .. "-type" .. suffix, "macro" }
                    out[#out + 1] = { mods .. "-macrotext" .. suffix, text }
                elseif plain and type(action) == "string" and action ~= "" then
                    out[#out + 1] = { mods .. "-type" .. suffix, noop }
                end
            end
        end
    end
    return out
end

-- Onto the frames

local function spellName(b)
    local n = C_Spell and type(C_Spell.GetSpellName) == "function" and C_Spell.GetSpellName(b.spell)
    if type(n) == "string" and n ~= "" then return n end
    return type(b.name) == "string" and b.name or nil
end

-- The attributes a list produces, in order: { { key, value }, ... }.
function CC.Attributes(list)
    local out = {}
    for _, b in ipairs(list) do
        if valid(b) then
            local prefix = b.mods ~= "" and (b.mods .. "-") or ""
            local suffix = CC.SUFFIX[b.button]
            -- By name, never by id. A cast by id isn't aimed at the clicked
            -- unit (a lower-rank Power Word: Shield landed on the caster), so a
            -- lower rank is cast as "Name(Rank 2)".
            local name = spellName(b)
            local value = name and (b.byName and name
                or (type(b.rank) == "string" and name .. "(" .. b.rank .. ")") or name) or b.spell
            out[#out + 1] = { prefix .. "type" .. suffix, "spell" }
            out[#out + 1] = { prefix .. "spell" .. suffix, value }
        end
    end
    for _, a in ipairs(CC.Forwards(list)) do out[#out + 1] = a end
    return out
end

-- Every frame a click can land on: the single frames and every group button a
-- header has made.
function CC.EachFrame(fn)
    for _, f in pairs(ns.frames or EMPTY) do fn(f) end
    if ns.Group then
        for _, b in ns.Group.Buttons() do
            fn(b)
            if b.pet then fn(b.pet) end   -- a party member's pet (PartyPets.lua)
        end
        for _, g in ipairs(ns.Group.all) do
            for _, b in ipairs(g.bare) do fn(b) end   -- made ahead, not set up yet
        end
    end
end

local function headers(fn)
    for _, g in ipairs(ns.Group and ns.Group.all or EMPTY) do
        if g.header then fn(g.header) end
        for _, h in ipairs(g.headers or EMPTY) do fn(h) end
    end
end

-- Moves one frame from what it had (old) to what it should have (new).
local function write(f, old, new)
    for k in pairs(old) do
        if new[k] == nil then f:SetAttribute(k, nil) end
    end
    for k, v in pairs(new) do
        if f:GetAttribute(k) ~= v then f:SetAttribute(k, v) end
    end
end

-- Applies to every frame and header now. Protected, out of combat only. A
-- header re-lays its buttons on any attribute change unless `_ignore` is set
-- (SecureGroupHeader_OnAttributeChanged), and these don't affect the layout.
function CC.ApplyNow()
    local attrs = CC.Stepped() and EMPTY or CC.Attributes(CC.List())
    local new, names = {}, {}
    for _, a in ipairs(attrs) do
        new[a[1]] = a[2]
        names[#names + 1] = a[1]
    end
    local old = CC.applied
    CC.EachFrame(function(f) write(f, old, new) end)
    local list = #names > 0 and table.concat(names, ",") or nil
    headers(function(h)
        if h:GetAttribute("_initialAttributeNames") == list and list == nil then return end
        local ignore = h:GetAttribute("_ignore")
        h:SetAttribute("_ignore", true)
        for k in pairs(old) do
            if new[k] == nil then h:SetAttribute("_initialAttribute-" .. k, nil) end
        end
        for k, v in pairs(new) do h:SetAttribute("_initialAttribute-" .. k, v) end
        h:SetAttribute("_initialAttributeNames", list)
        h:SetAttribute("_ignore", ignore)
    end)
    CC.applied = new
end

function CC.Apply()
    DUI.AfterCombat(CC.ApplyNow, "clickcast:apply")
end

-- A group button just created gets what every frame has. Out of combat only;
-- in combat its header already copied them, and all frames get redone once
-- the fight ends.
function CC.Dress(b)
    if CC.Stepped() then return end
    if InCombatLockdown() then
        CC.Apply()
    else
        write(b, EMPTY, CC.applied)
    end
end

-- The bindings changed: apply to the frames after combat and redraw the page.
function CC.Changed()
    if ns.module then CC.Apply() end
    DUI.Fire("ClickCastChanged")
    local panel = DUI.OptionsPanel
    if panel and type(panel.IsShown) == "function" and panel.IsShown() and type(panel.Refresh) == "function" then
        panel.Refresh()
    end
end

-- Once the frames are built (Units.lua). A talent set swap brings the other
-- list, a spell's name can arrive late (SPELLS_CHANGED), and key bindings can
-- move a forwarded mouse button (UPDATE_BINDINGS). Frames are only rewritten
-- when something actually changed.
local started
function CC.Start()
    CC.ApplyNow()
    if started then return end
    started = true
    for _, e in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED", "UPDATE_BINDINGS" }) do
        DUI.RegisterEvent(e, function()
            local want = CC.Stepped() and EMPTY or CC.Attributes(CC.List())
            local same = 0
            for _, a in ipairs(want) do
                if CC.applied[a[1]] == a[2] then same = same + 1 end
            end
            local had = 0
            for _ in pairs(CC.applied) do had = had + 1 end
            if same ~= #want or had ~= #want then CC.Apply() end
        end)
    end
end
