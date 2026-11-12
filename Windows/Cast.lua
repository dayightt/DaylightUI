-- Secure cast buttons for window rows that cast a spell (spellbook spells,
-- Find Minerals in the profession window). The windows themselves must open in
-- combat, so they hold nothing secure. Instead each caster is one secure button
-- on UIParent, one strata above its window, positioned over the hovered row out
-- of combat. It is placed by coordinates, never anchored to the row. Since it
-- steals the mouse, it forwards hover, drag and clicks back through the spec.
--
--   local c = Win.Caster({ name = "DaylightUIBookCast", above = function() return frame end,
--                          enter = fn(row), leave = fn(row), drag = fn(row), post = fn(row, button) })
--   c.Over(row, { type1 = "spell", spell = id })   -- from the row's OnEnter
--   c.Hide()                                         -- when the window closes
--
-- It hides on PLAYER_REGEN_DISABLED, while that is still allowed. An invisible
-- secure button left up through a fight would cast on any click there. In
-- combat, clicking a row casts nothing.
--
-- In a scrolled list the button covers only the visible part of the row, and
-- it hides when the list scrolls or refills (Win.CastersOff, from Parts.Stack).
-- Otherwise a half-hidden row's button could sit over the search box.
--
-- A drag keeps the button shown until it ends. Hiding it mid-drag drops the
-- release, so the spell stays on the cursor and needs a second click.

local _, DUI = ...
local Win = DUI.Win

Win.CAST_KEYS = { "type1", "spell", "macrotext1", "type2", "macrotext2" }
Win.CAST_STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

local function above(frame)
    local strata = frame and frame:GetFrameStrata()
    for i, s in ipairs(Win.CAST_STRATA) do
        if s == strata then return Win.CAST_STRATA[math.min(i + 1, #Win.CAST_STRATA)] end
    end
    return "DIALOG"
end

-- The nearest ScrollFrame above the row, if any.
local function scrollOf(row)
    local p = row:GetParent()
    while p do
        if p.GetObjectType and p:GetObjectType() == "ScrollFrame" then return p end
        p = p:GetParent()
    end
end

-- Left, bottom, right, top in UIParent units, or nil if not laid out yet.
local function rectOf(frame)
    local left, bottom, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if type(left) ~= "number" or type(bottom) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * k, bottom * k, (left + w) * k, (bottom + h) * k
end

-- Hide every caster over this scroll frame's rows. Called when the list
-- scrolls or refills.
function Win.CastersOff(sf)
    local list = sf and sf.casters
    if not list then return end
    for c in pairs(list) do
        if c.sf == sf then c.Hide() end
    end
end

function Win.Caster(spec)
    local c = {}

    local function make()
        local ok, b = pcall(CreateFrame, "Button", spec.name, UIParent, "SecureActionButtonTemplate")
        if not ok or type(b) ~= "table" then return nil end
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetAttribute("useOnKeyDown", false)   -- nil follows the key-down CVar, which would ignore our Up clicks
        b:RegisterForDrag("LeftButton")
        b:Hide()
        b:SetScript("OnEnter", function(self) if self.row and spec.enter then spec.enter(self.row) end end)
        b:SetScript("OnLeave", function(self)
            -- Out of combat, Hide tells the row it lost the mouse. In combat
            -- the button can't hide, so tell the row directly.
            if not InCombatLockdown() then c.Hide(); return end
            if self.row and spec.leave then spec.leave(self.row) end
        end)
        b:SetScript("OnDragStart", function(self)
            if not (self.row and spec.drag) then return end
            self.dragging = true
            spec.drag(self.row)
        end)
        b:SetScript("OnDragStop", function(self)
            self.dragging = nil
            if not self.row and not InCombatLockdown() then self:Hide() end
        end)
        -- Modified clicks (links etc.) are handled after the secure click.
        b:SetScript("PostClick", function(self, button)
            if self.row and spec.post then spec.post(self.row, button) end
        end)
        return b
    end

    -- Put the button over row with these attributes. nil attrs means the
    -- row casts nothing. Does nothing in combat.
    function c.Over(row, attrs)
        if InCombatLockdown() then return nil end
        if c.button and c.button.dragging then return nil end
        if not attrs then c.Hide(); return nil end
        if not c.button then c.button = make() end
        local b = c.button
        if not b then return nil end
        local left, bottom, right, top = rectOf(row)
        if not left then return nil end
        -- Clip to the visible part of the list. Fully hidden row, no button.
        local sf = scrollOf(row)
        local sl, sb, sr, st
        if sf then sl, sb, sr, st = rectOf(sf) end
        if sl then
            left, bottom = math.max(left, sl), math.max(bottom, sb)
            right, top = math.min(right, sr), math.min(top, st)
            if right <= left or top <= bottom then c.Hide(); return nil end
        end
        if c.sf and c.sf ~= sf and c.sf.casters then c.sf.casters[c] = nil end
        c.sf = sf
        if sf then
            sf.casters = sf.casters or {}
            sf.casters[c] = true
        end
        for _, key in ipairs(Win.CAST_KEYS) do b:SetAttribute(key, attrs[key]) end
        b.row = row
        b:SetFrameStrata(above(spec.above and spec.above()))
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        b:SetSize(right - left, top - bottom)
        b:Show()
        return b
    end

    -- `entering` comes from PLAYER_REGEN_DISABLED, the last moment Hide is
    -- allowed even though InCombatLockdown may already return true. The row
    -- gets exactly one leave call here, which clears its highlight and tooltip.
    function c.Hide(entering)
        local b = c.button
        if not b then return end
        local row = b.row
        b.row = nil
        if entering then b.dragging = nil end
        if not b.dragging and (entering or not InCombatLockdown()) then b:Hide() end
        if row and spec.leave then spec.leave(row) end
    end

    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() c.Hide(true) end)
    return c
end
