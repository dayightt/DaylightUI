-- The action bars. Each bar is an entry in Bars.DEFS of some kind in Bars.KINDS,
-- which says how its buttons are made and shown. This file builds a holder per bar,
-- lays out its buttons from the settings, places it and drives its visibility.
-- Changes apply right away (or after combat) without a reload.
--
-- Built while the files load, before combat lockdown comes back, so a /reload in a
-- fight builds the same way as a login. Bars.Enable lays everything out again at
-- login once the profile is known.

local _, ns = ...
local DUI = DaylightUI

local Bars = {}
ns.Bars = Bars

-- The bars, in options order. Keys match the old engine's so settings and positions
-- carry over. page = fixed page of action slots (bar 1 follows Paging.lua),
-- command = the game's keybind command prefix, twin = the hidden game bar whose
-- buttons our keybinds press, up = rows stack upward like the game's bottom bars.
Bars.DEFS = {
    { key = "main", num = 1, label = "Action Bar 1", kind = "action", page = 1, paged = true, up = true,
      command = "ACTIONBUTTON", twin = "MainActionBar", twinPrefix = "ActionButton" },
    { key = "bar2", num = 2, label = "Action Bar 2", kind = "action", page = 6, up = true,
      command = "MULTIACTIONBAR1BUTTON", twin = "MultiBarBottomLeft", twinPrefix = "MultiBarBottomLeftButton" },
    { key = "left", num = 3, label = "Action Bar 3", kind = "action", page = 5, up = true,
      command = "MULTIACTIONBAR2BUTTON", twin = "MultiBarBottomRight", twinPrefix = "MultiBarBottomRightButton" },
    { key = "right", num = 4, label = "Action Bar 4", kind = "action", page = 3, up = true,
      command = "MULTIACTIONBAR3BUTTON", twin = "MultiBarRight", twinPrefix = "MultiBarRightButton" },
    { key = "bar5", num = 5, label = "Action Bar 5", kind = "action", page = 4,
      command = "MULTIACTIONBAR4BUTTON", twin = "MultiBarLeft", twinPrefix = "MultiBarLeftButton" },
    { key = "bar6", num = 6, label = "Action Bar 6", kind = "action", page = 13,
      command = "MULTIACTIONBAR5BUTTON", twin = "MultiBar5", twinPrefix = "MultiBar5Button" },
    { key = "bar7", num = 7, label = "Action Bar 7", kind = "action", page = 14,
      command = "MULTIACTIONBAR6BUTTON", twin = "MultiBar6", twinPrefix = "MultiBar6Button" },
    { key = "bar8", num = 8, label = "Action Bar 8", kind = "action", page = 15,
      command = "MULTIACTIONBAR7BUTTON", twin = "MultiBar7", twinPrefix = "MultiBar7Button" },
    { key = "stance",  label = "Stance Bar",  kind = "stance" },
    { key = "pet",     label = "Pet Bar",     kind = "pet" },
    { key = "possess", label = "Possess Bar", kind = "possess" },
    { key = "totem",   label = "Totem Bar",   kind = "totem", moverKey = "actionbars.totembar" },
}

-- The kinds of bar.
Bars.KINDS = { action = ns.Buttons.KIND, stance = ns.Small.KINDS.stance, pet = ns.Small.KINDS.pet,
               possess = ns.Small.KINDS.possess, totem = ns.Totems.KIND }

-- Each "Show" choice as the tail of a state driver rule.
Bars.SHOW = { always = "show", combat = "[combat] show; hide", nocombat = "[combat] hide; show", hidden = "hide" }

-- The "Show" choices each kind offers, in order.
local WHEN = { "always", "combat", "nocombat", "hidden" }
local function choices(always)
    return { order = WHEN, values = { always = always, combat = "In combat", nocombat = "Out of combat", hidden = "Hidden" } }
end
Bars.CHOICES = {
    action = choices("Always"),
    stance = choices("When you have forms"),
    pet = choices("With a pet"),
    totem = choices("When you have totems"),
    possess = { order = { "always", "hidden" }, values = { always = "While possessing", hidden = "Hidden" } },
}

Bars.holders, Bars.buttons = {}, {}

-- DaylightUIBar1..8 for the action bars, DaylightUIStanceBar and so on.
function Bars.HolderName(def)
    if def.num then return "DaylightUIBar" .. def.num end
    return "DaylightUI" .. (string.gsub(def.label, " ", ""))
end

function Bars.MoverKey(def) return def.moverKey or ("actionbars." .. def.key) end
function Bars.Config(def) return ns.Shape.Config(def.key) end

-- Default spot for a bar that was never moved, matching the old engine's default
-- given the current bar shapes.
function Bars.DefaultAnchor(def)
    local d = ns.Shape.Defaults()[def.key]
    return { d.point, "UIParent", d.rel or d.point, d.x, d.y }
end

-- Column and row (0-based) of button i of n. Fills across first, or down first for
-- a vertical bar.
function Bars.Grid(i, n, cfg)
    n = math.max(n, 1)
    local rows = math.max(1, math.min(cfg.rows or 1, n))
    local across = math.ceil(n / rows)
    local col, row = (i - 1) % across, math.floor((i - 1) / across)
    if cfg.vertical then col, row = row, col end
    return col, row
end

-- The corner a bar's first button sits in: its "Start corner" setting, else bars 1-4
-- fill from the bottom left like the game's bottom bars (rows stack upward) and the
-- rest, and any vertical bar, from the top left.
Bars.CORNERS = { topleft = true, topright = true, bottomleft = true, bottomright = true }
function Bars.Corner(def, cfg)
    cfg = cfg or Bars.Config(def)
    if Bars.CORNERS[cfg.corner] then return cfg.corner end
    return (def.up and not cfg.vertical) and "bottomleft" or "topleft"
end

-- Lays out one bar from its settings: holder size, button positions and scale. Size
-- is a percent of the button's own width, like Edit Mode's icon size. Buttons past
-- the count are hidden. Out of combat only.
function Bars.LayoutBar(def)
    local holder, list = Bars.holders[def.key], Bars.buttons[def.key]
    local kind, cfg = Bars.KINDS[def.kind], Bars.Config(def)
    if kind.Layout then
        kind.Layout(def, holder, cfg)
    else
        local n = kind.Count(def, cfg)
        local base = kind.Base(def)
        local s = cfg.size / 100
        local w, h = ns.Shape.Extent(cfg, n, base)
        holder:SetSize(math.max(w, 1), math.max(h, 1))
        local step = base + cfg.pad / s          -- in the buttons' own scale
        local corner = Bars.Corner(def, cfg)
        local point = string.upper(corner)
        local dx = string.find(corner, "right", 1, true) and -step or step
        local dy = string.find(corner, "bottom", 1, true) and step or -step
        for i, btn in ipairs(list) do
            local own = ns.Buttons.IsOwn(btn)
            if i <= n then
                local col, row = Bars.Grid(i, n, cfg)
                if not own and btn:GetParent() ~= holder then btn:SetParent(holder) end
                btn:SetScale(s)
                btn:ClearAllPoints()
                btn:SetPoint(point, holder, point, col * dx, row * dy)
                if own then
                    btn:SetAttribute("statehidden", nil)
                    btn:Show()
                end
            elseif own then
                btn:SetAttribute("statehidden", true)
                btn:Hide()
            else
                -- A game-owned button (stance, pet, possess). Nothing is shown,
                -- hidden or written on it from here: the parked frame keeps it out
                -- of sight. The game reads its "statehidden" on every stance swap,
                -- and a value written by an addon keeps that taint, so the rest of
                -- the game's pass (showing bars 2-8) got blocked in a fight.
                if btn:GetParent() ~= ns.Park.Frame() then btn:SetParent(ns.Park.Frame()) end
            end
        end
    end
    DUI.Fire("ActionBarLaidOut", def.key)
end

-- The visibility rule for a bar: its kind's clauses, then its Show setting.
function Bars.Rule(def)
    -- In gamepad mode the game's controller bars replace every bar, so ours hide
    -- the same way the game's own do.
    if DUI.Pad.On() then return "hide" end
    local cfg = Bars.Config(def)
    return Bars.KINDS[def.kind].Rule(def) .. (Bars.SHOW[cfg.visible] or Bars.SHOW.always)
end

function Bars.ApplyVisibility(def)
    RegisterStateDriver(Bars.holders[def.key], "visibility", Bars.Rule(def))
end

-- Whether a bar can show at all: not set to Hidden, has buttons, and passes its
-- kind's check (no stance bar without forms). A kind that lays out a game bar
-- (the totem bar) has no buttons of ours, so its check alone decides. Bars that
-- fail get no unlock handle.
function Bars.InUse(def)
    local list, kind = Bars.buttons[def.key], Bars.KINDS[def.kind]
    if Bars.Config(def).visible == "hidden" then return false end
    if kind.Layout then return kind.InUse ~= nil and kind.InUse(def) == true end
    return type(list) == "table" and #list > 0 and (not kind.InUse or kind.InUse(def))
end

-- Re-lays every bar from the settings and puts each holder back on its spot.
-- A bar that was never moved follows the others' shapes. Out of combat only.
function Bars.Relayout()
    for _, def in ipairs(Bars.DEFS) do
        Bars.LayoutBar(def)
        Bars.ApplyVisibility(def)
        if def.page and not def.paged then DUI.SafeCall(ns.Paging.ApplyBar, def, Bars.holders[def.key]) end
        if def.key == "main" then DUI.SafeCall(ns.Paging.Apply) end
        DUI.Movers.Apply(Bars.MoverKey(def))
        DUI.Movers.Recheck(Bars.MoverKey(def))
    end
end

-- The holders, for the fades.
function Bars.Frames()
    local out = {}
    for _, def in ipairs(Bars.DEFS) do out[#out + 1] = { key = def.key, frame = Bars.holders[def.key] } end
    return out
end

-- The bars, bag bar, micro menu and totem timers all fade through the fade engine.
local function wanted(frame)
    if GetCursorInfo() then return true end   -- dragging a spell needs somewhere to drop it
    local flyout = SpellFlyout
    return flyout ~= nil and flyout:IsShown() and flyout:GetParent() ~= nil
        and flyout:GetParent():GetParent() == frame
end

-- Each area's frame list is one reused table, since the fade engine asks often.
local NONE = {}
function Bars.RegisterFades(db)
    for _, bar in ipairs(Bars.Frames()) do
        local frame = bar.frame
        if frame then
            local list = { frame }
            DUI.Fade.Register{ key = "ActionBars." .. bar.key, scope = "ActionBars", path = "bars." .. bar.key .. ".fade",
                page = "ActionBars.barlayout", frames = function() return list end, whole = true,
                wake = function() return wanted(frame) end }
        end
    end
    for _, key in ipairs({ "bagBar", "microMenu" }) do
        local list = {}
        DUI.Fade.Register{ key = "ActionBars." .. key, scope = "ActionBars", path = key .. "Fade", page = "ActionBars.bars",
            frames = function()
                list[1] = ns.Hide.FadeFrame(db, key)
                return list
            end }
    end
    -- The Cooldown Manager layout.
    if ns.CdmRows then
        DUI.Fade.Register{ key = "ActionBars.cdm", scope = "ActionBars", path = "cdmFade",
            page = "ActionBars.cdm.layout", frames = ns.CdmRows.FadeFrames, paint = ns.CdmRows.PaintFade }
    end
    local totems = {}
    -- The totem timers (the game's TotemFrame, placed by Totems.lua).
    DUI.Fade.Register{ key = "ActionBars.totemTimers", scope = "ActionBars", path = "totemTimersFade",
        page = "ActionBars.barlayout",
        frames = function()
            local tf = _G.TotemFrame
            if not (type(tf) == "table" and ns.Totems.TimersOn()) then return NONE end
            totems[1] = tf
            return totems
        end }
end

-- "Reset bar positions": every bar back to its default spot, old saved spots included.
function Bars.ResetPositions()
    local pos = DUI.DB.Positions()
    for _, def in ipairs(Bars.DEFS) do
        pos[Bars.OLD_PREFIX .. def.key] = nil
        DUI.Movers.Reset(Bars.MoverKey(def))
    end
end

-- Background panels, one frame behind each holder's buttons, made on first use.
-- Bars whose panels touch or overlap (bars 1 and 2 stacked) share one panel around
-- the whole group, owned by the first in Bars.DEFS order. Two separate panels drew
-- their edges across each other.
Bars.backs = {}

local function hideBack(def)
    local f = Bars.backs[def.key]
    if f then f:Hide() end
end

-- One bar's panel, around its own holder, or over `rect` (screen pixels l, r, b, t)
-- when it holds a group.
function Bars.PaintBack(def, rect)
    local L, holder = ns.Skin.LookFor(def.key), Bars.holders[def.key]
    local f = Bars.backs[def.key]
    if not L.back then
        if f then f:Hide() end
        return
    end
    if not f then
        f = CreateFrame("Frame", nil, holder)
        f:SetFrameStrata("BACKGROUND")
        f:EnableMouse(false)
        f.opts = {}
        Bars.backs[def.key] = f
    end
    local pad, c = L.backPad, L.backColor
    local left, top, right, bottom = -pad, pad, pad, -pad
    local x, y = holder:GetCenter()
    if rect and x then
        -- The group's edges, converted into the holder's units.
        local s = holder:GetEffectiveScale()
        local w, h = holder:GetSize()
        left, right = rect.l / s - (x - w / 2), rect.r / s - (x + w / 2)
        top, bottom = rect.t / s - (y + h / 2), rect.b / s - (y - h / 2)
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", holder, "TOPLEFT", left, top)
    f:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", right, bottom)
    f.opts.bgColor = { c[1], c[2], c[3] }
    f.opts.bgAlpha = c[4] or 1
    -- Border off means a plain panel with no outline, gap or shadow. A dark rim
    -- still read as a border.
    f.opts.noBorder = not L.backBorder
    f.opts.borderPx = (not L.backBorder) and 0 or nil
    f.opts.shadowAlpha = (not L.backBorder) and 0 or nil
    f.opts.noBevel = true
    f.shell = DUI.Style.Shell(f, f.opts)
    f:Show()
end

-- Groups rects (each l, r, b, t) that touch or overlap, with a pixel of slack for
-- rounding. A group joins through any member. Each group lists its indexes in order.
function Bars.BackGroups(rects)
    local up = {}
    for i = 1, #rects do up[i] = i end
    local function root(i)
        while up[i] ~= i do i = up[i] end
        return i
    end
    for i = 1, #rects do
        for j = i + 1, #rects do
            local a, b = rects[i], rects[j]
            if a.l <= b.r + 1 and b.l <= a.r + 1 and a.b <= b.t + 1 and b.b <= a.t + 1 then
                local ri, rj = root(i), root(j)
                if ri ~= rj then up[math.max(ri, rj)] = math.min(ri, rj) end
            end
        end
    end
    local groups, at = {}, {}
    for i = 1, #rects do
        local r = root(i)
        if not at[r] then
            at[r] = #groups + 1
            groups[at[r]] = {}
        end
        table.insert(groups[at[r]], i)
    end
    return groups
end

-- Paints every bar's panel, drawing bars that meet as one.
function Bars.PaintBacks()
    local rects = {}
    for _, def in ipairs(Bars.DEFS) do
        local L, holder = ns.Skin.LookFor(def.key), Bars.holders[def.key]
        local x, y = holder:GetCenter()
        -- An unused bar (totem bar on a non-shaman, stance bar with no forms) is
        -- an empty holder its driver still shows. No panel for it.
        if not L.back or not holder:IsShown() or not Bars.InUse(def) then
            hideBack(def)
        elseif not x then
            Bars.PaintBack(def)          -- not placed yet, so just around itself
        else
            local s, pad = holder:GetEffectiveScale(), L.backPad
            local w, h = holder:GetSize()
            rects[#rects + 1] = { def = def,
                l = (x - w / 2 - pad) * s, r = (x + w / 2 + pad) * s,
                b = (y - h / 2 - pad) * s, t = (y + h / 2 + pad) * s }
        end
    end
    for _, group in ipairs(Bars.BackGroups(rects)) do
        local u = rects[group[1]]
        local rect = { l = u.l, r = u.r, b = u.b, t = u.t }
        for i = 2, #group do
            local o = rects[group[i]]
            rect.l, rect.r = math.min(rect.l, o.l), math.max(rect.r, o.r)
            rect.b, rect.t = math.min(rect.b, o.b), math.max(rect.t, o.t)
            hideBack(o.def)
        end
        Bars.PaintBack(u.def, #group > 1 and rect or nil)
    end
end

-- Repaints the panels on the next frame after a bar moves, shows, hides or is laid
-- out, when its spot has settled. Many calls collapse into one pass.
function Bars.PaintBacksSoon()
    if Bars.backsQueued then return end
    Bars.backsQueued = true
    C_Timer.After(0, function()
        Bars.backsQueued = nil
        DUI.SafeCall(Bars.PaintBacks)
    end)
end

function Bars.SkinAll()
    DUI.SafeCall(Bars.PaintBacks)
    for _, def in ipairs(Bars.DEFS) do
        for _, b in ipairs(Bars.buttons[def.key]) do
            if def.kind == "action" then ns.Skin.SetOwn(b) end
            if def.kind == "pet" then ns.Skin.SetPet(b) end
            ns.Skin.SetBar(b, def.key)
            ns.Skin.Apply(b)
        end
    end
    ns.Park.SkinLeave()
    ns.PadSkin.Apply()
end

-- Applies the look and fade settings live (everything but bar shapes).
function Bars.Refresh(mod)
    local db = mod.db
    DUI.SafeCall(Bars.RegisterFades, db)
    DUI.SafeCall(ns.Hide.Apply, db)
    DUI.AfterCombat(function()
        ns.Skin.hideEmpty = db.hideEmpty
        ns.Skin.Configure(db)
        DUI.SafeCall(Bars.SkinAll)
        DUI.SafeCall(ns.Totems.Apply)    -- totem timers' spot and look
        ns.Buttons.PaintAll()
        local Report = DUI.APIReport
        if Report.Wants("FrameStyled") then
            for _, btn in ipairs(ns.Buttons.All()) do Report.Styled("actionbutton", btn, false) end
        end
        DUI.SafeCall(ns.Keys.UpdateText)     -- after the skin, which shortens and blanks the text
        if ns.Cooldowns.enabled then DUI.SafeCall(ns.Cooldowns.Refresh) end
    end, "bars:refresh")
end

-- Bars 5-8 that an older profile still shows (DB.KeepBars5to8 lists them). Once the
-- game has sent the actions, each listed bar still on "Always" with nothing on it
-- hides, and the list is cleared, so this runs once per profile. A bar shown again
-- later stays shown. Returns true when one was hidden.
local function hasAction(slot)
    local v = HasAction and HasAction(slot)
    if v == nil and C_ActionBar and C_ActionBar.HasAction then v = C_ActionBar.HasAction(slot) end
    return v == true
end

local function used(def)
    local first = (def.page - 1) * 12
    for slot = first + 1, first + 12 do
        if hasAction(slot) then return true end
    end
    return false
end

function Bars.HideEmptyOld(db)
    local list = db.checkEmptyBars
    if type(list) ~= "table" then return false end
    -- None of the 180 slots is filled yet, so the actions haven't arrived. Try later.
    local any = false
    for slot = 1, 180 do
        if hasAction(slot) then any = true break end
    end
    if not any then return false end
    db.checkEmptyBars = nil
    local hid = false
    for _, def in ipairs(Bars.DEFS) do
        local cfg = list[def.key] and def.page and type(db.bars) == "table" and db.bars[def.key]
        if type(cfg) == "table" and cfg.visible == "always" and not used(def) then
            cfg.visible = "hidden"
            hid = true
        end
    end
    return hid
end

-- A setting changed (called after combat). Shape settings re-lay the bars, anything
-- else is just the look.
function Bars.SettingChanged(mod, path)
    -- A bar's Show picked by hand: HideEmptyOld must leave it alone.
    local picked = type(path) == "string" and string.match(path, "^bars%.([^%.]+)%.visible$")
    if picked and type(mod.db.checkEmptyBars) == "table" then mod.db.checkEmptyBars[picked] = nil end
    if type(path) == "string" and string.match(path, "^bars%.") then Bars.Relayout() end
    Bars.Refresh(mod)
end

-- Extra Abilities (the big extra button) moves off the bars to our spot, but only
-- while it's still at the game's default. A spot picked in Edit Mode is left alone.
local function extraEntry(layout)
    local sys = Enum.EditModeSystem and Enum.EditModeSystem.ExtraAbilities
    return sys ~= nil and DUI.EditMode.FindSystem(layout, sys, nil) or nil
end

function Bars.FillExtra(layout)
    local entry = extraEntry(layout)
    if not (entry and entry.isInDefaultPosition) then return end
    local d = ns.Shape.Defaults().extra
    DUI.EditMode.Anchor(entry, d.point, d.rel or d.point, d.x, d.y)
end

-- False while the saved layout still has it at the game's default.
function Bars.ExtraCurrent(layout)
    local entry = extraEntry(layout)
    return not (entry and entry.isInDefaultPosition)
end

function Bars.Enable(mod)
    ns.UpgradeBars(DUI.DB.Active())      -- the login profile may differ from the one at load
    ns.module, ns.db = mod, mod.db
    ns.Migrate(mod.db)
    DUI.WarnIfLoaded("EllesmereUIActionBars", "EllesmereUI Action Bars", "action bars")
    ns.Skin.Wire()
    if mod.db.cooldowns then DUI.SafeCall(ns.Cooldowns.Apply) end
    -- An Edit Mode part with nothing to write. The core only maintains its Edit Mode
    -- layout (new-character setup, per-profile layouts) while some part is
    -- registered, and with the info panel off there would be none.
    DUI.EditMode.Add("actionbars", function() end)
    DUI.EditMode.Add("extra", Bars.FillExtra, Bars.ExtraCurrent)
    DUI.EditMode.Add("totem", ns.Totems.FillLayout, ns.Totems.LayoutCurrent)
    DUI.EditMode.Add("leave", ns.Park.FillLayout, ns.Park.LayoutCurrent)
    DUI.SafeCall(ns.Hide.Movers, mod.db)     -- bag bar and micro menu in unlock mode
    -- Skin the bag bar and micro menu now, and again on entering the world for any
    -- button the game made since.
    local function skinMenus()
        if mod.db.skinMenus then
            DUI.AfterCombat(function() DUI.SafeCall(ns.Menus.Apply) end, "bars:menus")
        end
    end
    skinMenus()
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        DUI.SafeCall(Bars.HideEmptyOld, mod.db)   -- before the relayout below shows the result
        DUI.SafeCall(ns.Hide.Apply, mod.db)
        skinMenus()
        DUI.AfterCombat(Bars.Relayout, "bars:relayout")
    end)
    -- Convert this profile's moved bars once each, the frame after the game has
    -- placed its own bars.
    local function convert()
        C_Timer.After(0, function()
            DUI.SafeCall(function()
                if Bars.Convert() then DUI.AfterCombat(Bars.Relayout, "bars:relayout") end
            end)
        end)
    end
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", convert)
    pcall(DUI.RegisterEvent, "EDIT_MODE_LAYOUTS_UPDATED", convert)
    DUI.On("PadChanged", function() DUI.AfterCombat(Bars.Relayout, "bars:relayout") end)
    DUI.AfterCombat(Bars.Relayout, "bars:relayout")
    Bars.Refresh(mod)
end

-- ---------------------------------------------------------------------
-- Converting old positions. A bar moved under the old engine saved the center of
-- the game's bar frame, which can sit off its buttons (bar 3's frame is sized for
-- one long row). So the first time a profile loads with these bars while the
-- character is on that profile's own Edit Mode layout, each moved bar takes the
-- middle of the game's hidden buttons as its spot. The old value is kept as
-- "actionbars.old.<bar>", which also marks the bar as done. Bars never moved have
-- no spot to convert, and the small bars and totem bar mean the same spot in both.
-- ---------------------------------------------------------------------

Bars.OLD_PREFIX = "actionbars.old."

-- The middle of some buttons on screen as a CENTER offset from UIParent's CENTER,
-- the same thing a mover saves. nil while none of them has a position.
function Bars.Span(buttons)
    local left, right, bottom, top
    for _, btn in ipairs(buttons) do
        local l, r, b, t = btn:GetLeft(), btn:GetRight(), btn:GetBottom(), btn:GetTop()
        if type(l) == "number" and type(r) == "number" and type(b) == "number" and type(t) == "number" then
            local s = btn:GetEffectiveScale() / UIParent:GetEffectiveScale()
            l, r, b, t = l * s, r * s, b * s, t * s
            left = left and math.min(left, l) or l
            right = right and math.max(right, r) or r
            bottom = bottom and math.min(bottom, b) or b
            top = top and math.max(top, t) or t
        end
    end
    if not left then return nil end
    return (left + right) / 2 - UIParent:GetWidth() / 2, (bottom + top) / 2 - UIParent:GetHeight() / 2
end

-- A bar's hidden game buttons (its twins), up to its button count.
function Bars.GameButtons(def)
    local out = {}
    if not def.twinPrefix then return out end
    for i = 1, Bars.KINDS[def.kind].Count(def, Bars.Config(def)) do
        local b = _G[def.twinPrefix .. i]
        if type(b) == "table" then out[#out + 1] = b end
    end
    return out
end

-- Converts this profile's moved bars, once each. Returns true when a spot changed.
function Bars.Convert()
    if not (DUI.EditMode and DUI.EditMode.IsActive()) then return false end
    local pos = DUI.DB.Positions()
    local changed = false
    for _, def in ipairs(Bars.DEFS) do
        local key, old = Bars.MoverKey(def), Bars.OLD_PREFIX .. def.key
        if def.twinPrefix and type(pos[key]) == "table" and type(pos[old]) ~= "table" then
            local x, y = Bars.Span(Bars.GameButtons(def))
            if x then
                pos[old] = pos[key]
                pos[key] = { DUI.Pixel.Snap(UIParent, x), DUI.Pixel.Snap(UIParent, y) }
                changed = true
            end
        end
    end
    return changed
end

local function makeHolder(def)
    local h = CreateFrame("Frame", Bars.HolderName(def), UIParent, "SecureHandlerStateTemplate")
    h:SetSize(1, 1)
    return h
end

-- Runs as the files load: builds, lays out, shows and places every bar using the
-- profile known at that point.
function Bars.Build()
    DUI.SafeCall(ns.UpgradeBars, DUI.DB.Active())
    ns.db = DUI.DB.Module("ActionBars", ns.DEFAULTS)
    for _, def in ipairs(Bars.DEFS) do
        local holder = makeHolder(def)
        Bars.holders[def.key] = holder
        Bars.buttons[def.key] = Bars.KINDS[def.kind].Setup(def, holder) or {}
    end
    for _, def in ipairs(Bars.DEFS) do
        Bars.LayoutBar(def)
        Bars.ApplyVisibility(def)
        DUI.Movers.Register(Bars.holders[def.key], Bars.MoverKey(def), def.label,
            function() return Bars.DefaultAnchor(def) end,
            { active = function() return Bars.InUse(def) end, bottom = true })   -- keep clear of a data bar
        Bars.holders[def.key]:HookScript("OnShow", Bars.PaintBacksSoon)
        Bars.holders[def.key]:HookScript("OnHide", Bars.PaintBacksSoon)
    end
    -- Panels that meet are drawn as one, so repaint when any bar changes.
    DUI.On("ActionBarLaidOut", Bars.PaintBacksSoon)
    DUI.On("MoverApplied", function(key)
        if string.find(key, "^actionbars%.") then Bars.PaintBacksSoon() end
    end)
    -- Until here a failure leaves the game's bars untouched and the old ones run.
    -- Once those are put away nothing may stop the rest, so each part below runs
    -- on its own.
    ns.Park.Apply()
    Bars.built = true
    DUI.SafeCall(ns.Park.LeaveButton, Bars.holders.main)
    DUI.SafeCall(ns.Paging.Setup, Bars.holders.main, Bars.buttons.main)
    for _, def in ipairs(Bars.DEFS) do
        if def.page and not def.paged then
            DUI.SafeCall(ns.Paging.SetupBar, def, Bars.holders[def.key], Bars.buttons[def.key])
        end
    end
    DUI.SafeCall(ns.Buttons.Wire)
    DUI.SafeCall(ns.Keys.Wire)
    DUI.SafeCall(ns.Buttons.PaintAll)
    DUI.ActionBarButtons = function(key) return Bars.buttons[key] end
    -- Some kinds have their own events (a form learned). Re-lay those bars after combat.
    for _, def in ipairs(Bars.DEFS) do
        for _, event in ipairs(Bars.KINDS[def.kind].Events or {}) do
            pcall(DUI.RegisterEvent, event, function()
                DUI.AfterCombat(function()
                    Bars.LayoutBar(def)
                    Bars.ApplyVisibility(def)
                end, "bars:kind:" .. def.key)
            end)
        end
    end
    DUI.Fire("ActionBarsBuilt")
    Bars.TellManaRise()
end

-- ManaRise (another addon that fills spells you can't afford yet) finds the game's
-- bars on its own. Ours are registered through its ManaRise_RegisterBarAddon call,
-- now if it's loaded or else when it loads. Once per session.
function Bars.TellManaRise()
    if Bars.toldManaRise then return end
    local register = _G.ManaRise_RegisterBarAddon
    if type(register) ~= "function" then return end
    Bars.toldManaRise = true
    pcall(register, { name = "Daylight UI", buttons = function() return ns.Buttons.All() end })
end
DUI.RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "ManaRise" and Bars.built then Bars.TellManaRise() end
end)

Bars.Build()
