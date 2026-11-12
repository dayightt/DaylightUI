-- The Click-casting options page (Unit Frames > Click-casting). Explains how to
-- bind from the spellbook, holds the binding mode switch, and lists this
-- character's bindings for the active talent set. A binding's click can be
-- changed (click its pill, then click again with the new click) or removed.
-- Bindings are stored per character (ClickCast.lua), not in the settings, so
-- the list is a custom item that redraws when they change.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local CC, B = ns.ClickCast, ns.ClickBinder

local LINE = 32
local function UI() return DUI.Widgets end

local function bookName()
    local key = B.BookKey()
    return key and string.format(L["your spellbook (%s)"], key) or L["your spellbook"]
end

local function status()
    if CC.Stepped() then
        return L["Clique is on, so Clique does the click-casting and these bindings wait. "
            .. "Clique keeps working on every DaylightUI unit frame."]
    end
    local text
    if B.on then
        text = string.format(L["Binding is on: open %s and click a spell with the mouse button you want, "
            .. "holding Shift, Ctrl or Alt if you like. Closing the spellbook switches it off."], bookName())
    else
        text = string.format(L["Press Bind in spellbook (or open %s and switch on Click-cast at its top), then "
            .. "click a spell with the mouse button you want (hold Shift, Ctrl or Alt for more). That click on any "
            .. "of your unit frames then casts it on that unit. Close the spellbook when you're done: this page "
            .. "comes back. Left-click still targets and right-click opens the menu unless you bind them."],
            bookName())
    end
    if DUI.DB.DualSpec() then
        text = text .. " " .. string.format(L["These are for talent set %s; each talent set keeps its own."],
            tostring(DUI.DB.SpecGroup()))
    end
    return text
end

-- A binding's line: icon, spell, its click (a pill to change it), remove

local function showClick(line)
    local pill = line.click
    if pill.capturing then
        pill.text:SetText(L["Click here with the new click"])
        pill.SetActive(true)
    else
        pill.text:SetText(line.desc or "")
        pill.SetActive(false)
    end
end

local function buildLine(parent)
    local W = UI()
    local C = W.COLORS
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(LINE)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(22, 22)
    line.icon:SetPoint("LEFT", line, "LEFT", 2, 0)
    DUI.Style.CropIcon(line.icon)
    line.name = W.Font(line, W.BODY, 13, C.text, "LEFT")
    line.name:SetPoint("LEFT", line.icon, "RIGHT", 10, 0)
    line.rank = W.Font(line, W.BODY, 12, DUI.Style.INK.LABEL, "LEFT")
    line.rank:SetPoint("LEFT", line.name, "RIGHT", 8, 0)
    line.delete = W.DeleteButton(line)
    line.delete:SetPoint("RIGHT", line, "RIGHT", -2, 0)
    line.delete:SetScript("OnClick", function() CC.Unbind(line.index) end)
    line.delete:HookScript("OnEnter", function(self) W.Tooltip(self, L["Remove"], L["Removes this binding."]) end)
    line.delete:HookScript("OnLeave", W.HideTooltip)
    local pill = W.Button(line, "", 22)
    pill:SetWidth(210)
    pill:SetPoint("RIGHT", line.delete, "LEFT", -8, 0)
    pill:RegisterForClicks("AnyUp")
    pill:SetScript("OnClick", function(self, button)
        if self.capturing then
            self.capturing = nil
            if CC.Rebind(line.index, CC.Mods(), button) and DUI.Sound then DUI.Sound.Play("snap") end
            showClick(line)
        else
            self.capturing = true
            showClick(line)
        end
    end)
    pill:HookScript("OnEnter", function(self)
        W.Tooltip(self, L["Change the click"], L["Click this, then click it again with the mouse button and Shift, "
            .. "Ctrl or Alt you want instead. Moving the mouse away cancels."])
    end)
    pill:HookScript("OnLeave", function(self)
        W.HideTooltip()
        if self.capturing then
            self.capturing = nil
            showClick(line)
        end
    end)
    line.click = pill
    return line
end

local function updateLine(line, i, b)
    line.index = i
    local icon = C_Spell and type(C_Spell.GetSpellTexture) == "function" and C_Spell.GetSpellTexture(b.spell)
    line.icon:SetTexture(icon or 134400)   -- the question mark
    local name = C_Spell and type(C_Spell.GetSpellName) == "function" and C_Spell.GetSpellName(b.spell)
    line.name:SetText(type(name) == "string" and name or b.name or string.format(L["Spell %s"], tostring(b.spell)))
    local known = CC.Known(b.spell)
    local rank = (not b.byName and b.rank) or nil
    line.rank:SetText(not known and L["not known now"] or rank or "")
    line:SetAlpha(known and 1 or 0.5)
    if line.shown ~= i .. ":" .. tostring(b.spell) then line.click.capturing = nil end
    line.shown = i .. ":" .. tostring(b.spell)
    line.desc = CC.Describe(b.mods, b.button)
    showClick(line)
end

local bindingList = {
    type = "custom", label = "Bindings",
    build = function(row)
        local W = UI()
        row.lines = {}
        row.list = CreateFrame("Frame", nil, row)
        row.list:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -4)
        row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -W.PAD, -4)
        row.empty = W.Font(row, W.BODY, 13, DUI.Style.INK.LABEL, "LEFT")
        row.empty:SetPoint("TOPLEFT", row, "TOPLEFT", W.PAD, -8)
        row.empty:SetText(L["No spells bound yet."])
    end,
    update = function(row)
        local n = 0
        for i, b in ipairs(CC.List()) do
            if type(b) == "table" and type(b.spell) == "number" and CC.SUFFIX[b.button] then
                n = n + 1
                local line = row.lines[n]
                if not line then
                    line = buildLine(row.list)
                    row.lines[n] = line
                end
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(n - 1) * LINE)
                line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(n - 1) * LINE)
                updateLine(line, i, b)
                UI().Stripe(line, n % 2 == 0)
                line:Show()
            end
        end
        for i = n + 1, #row.lines do row.lines[i]:Hide() end
        row.count = n
        row.list:SetHeight(math.max(1, n * LINE))
        row.empty:SetShown(n == 0)
    end,
    height = function(row)
        local n = row.count or #CC.List()
        return n > 0 and n * LINE + 8 or 30
    end,
}

local KEY_NAMES = { NONE = "Always", ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift" }

local page = { id = "clickcast", label = "Click-casting",
    desc = "Cast spells by clicking your unit frames, or by hovering them and pressing your usual keys.",
    groups = {
        { label = "Mouseover casting", wide = true, items = {
            { type = "toggle", label = "Mouseover casting",
              desc = "Rest the mouse on a frame and press a spell on your action bars: it goes to that player, with no click and no change of target. Works on anyone the mouse is on, in the world too, and with mouse buttons bound to your bars. This is the game's own setting.",
              hidden = function() return not CC.MouseoverSupported() end,
              get = CC.MouseoverOn, set = CC.SetMouseover },
            { type = "dropdown", label = "Mouseover key", values = KEY_NAMES, order = CC.MOUSEOVER_KEYS,
              desc = "Always, or only while you hold this key.",
              hidden = function() return not CC.MouseoverSupported() end,
              disabled = function() return not CC.MouseoverOn() end,
              get = CC.MouseoverKey, set = CC.SetMouseoverKey },
        } },
        { label = "Spellbook binder", wide = true, items = {
            { type = "text", label = status },
            { type = "button", label = "Binding mode",
              text = function() return B.on and L["Stop binding"] or L["Bind in spellbook"] end,
              desc = "Opens your spellbook with Click-cast switched on: click a spell with the mouse button you want. Close the spellbook when you're done and this page comes back.",
              hidden = function() return CC.Stepped() end,
              -- Out of combat a secure button on top opens the book (B.Opener).
              -- This click is the fallback for combat: turn on, open it yourself.
              built = function(b, row)
                  b:HookScript("OnEnter", function() B.Opener(b, row) end)
              end,
              func = function() B.SetMode(not B.on) end },
            { type = "button", label = "Remove every binding", text = "Remove all", confirm = true,
              desc = "Removes all of this character's bindings for the talent set in use.",
              disabled = function() return #CC.List() == 0 end,
              func = function() CC.Clear() end },
        } },
        { label = "Your bindings", desc = "This character's, for the talent set in use. Covers your player, target, target of target, pet, focus, party and raid frames.",
          items = { bindingList } },
    } }

ns.ClickCastPage = page
