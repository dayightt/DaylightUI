-- Copying chat text. Chat windows don't allow selecting text, so the current
-- tab's newest lines open in a window that looks like the chat (same colors,
-- font, size, links as plain words) where you can select and Ctrl+C.
-- Opened from a small Copy link shown while hovering the chat, or /dui copy.
-- Lines are only read (History.Read), never changed.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Copy = {}
ns.Copy = Copy

Copy.LINES = 300 -- newest lines shown
Copy.SIZE = { 560, 360 }

-- Plain readable text: no color codes or icons, links as their words, "||" -> "|".
function Copy.Plain(text)
    local out = string.gsub(text, "||", "\001")
    out = string.gsub(out, "|c%x%x%x%x%x%x%x%x", "")
    out = string.gsub(out, "|r", "")
    out = string.gsub(out, "|H.-|h(.-)|h", "%1")
    out = string.gsub(out, "|T.-|t", "")
    out = string.gsub(out, "|A.-|a", "")
    out = string.gsub(out, "|K.-|k", "?")
    out = string.gsub(out, "\001", "|")
    return out
end

-- Keeps the line's color codes and wraps it in its base (channel) color. Links
-- become their words but keep their color, icons are dropped. A missing or
-- non-number base color leaves the line as is.
function Copy.Colored(text, r, g, b)
    local out = string.gsub(text, "||", "\001")
    out = string.gsub(out, "|H.-|h(.-)|h", "%1")
    out = string.gsub(out, "|T.-|t", "")
    out = string.gsub(out, "|A.-|a", "")
    out = string.gsub(out, "|K.-|k", "?")
    out = string.gsub(out, "\001", "||")
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        local function c(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
        out = string.format("|cff%02x%02x%02x%s|r", c(r), c(g), c(b), out)
    end
    return out
end

-- A window's newest lines, one per line, in the chat's colors.
function Copy.Text(cf)
    local out = {}
    for _, l in ipairs(ns.History.Read(cf, Copy.LINES)) do
        out[#out + 1] = Copy.Colored(l[1], l[2], l[3], l[4])
    end
    return table.concat(out, "\n")
end

local box, button, cfg
local near = false -- the Copy link is showing (mouse over the chat)

-- Defaults that are true get stripped from saved data at logout, so only an
-- explicit false means off.
local function wanted()
    if not cfg then return false end
    if cfg.copyButton == false then return false end
    return true
end

-- A scrolling multi-line edit box holding the text.
local function buildBox()
    local W = DUI.Widgets
    box = CreateFrame("Frame", "DaylightUIChatCopy", UIParent)
    DUI.Movers.FollowScale(box)
    box:SetSize(Copy.SIZE[1], Copy.SIZE[2])
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    box:SetFrameStrata("DIALOG")
    box:SetToplevel(true)
    box:EnableMouse(true)
    Style.Shell(box)
    box.title = Style.Text(box, Style.SIZE.small, "LEFT")   -- a hint, not a title
    box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12)
    box.title:SetText(L["Select text, then Ctrl+C to copy. Ctrl+A selects all. Escape closes."])
    local Win = DUI.Win
    local function close() DUI.Motion.Vanish(box) end
    box.close = W.Close(box, close)
    box.close:SetPoint("TOPRIGHT", box, "TOPRIGHT", Win.CLOSE_X, Win.CloseY(true))
    -- Escape closes this box alone, before any window under it, even after
    -- a click elsewhere took the text box's focus away.
    Win.Keys(box, function(key)
        if key == "ESCAPE" then close(); return true end
    end)
    box:HookScript("OnShow", function() Win.KeysOn(box, true) end)
    box:HookScript("OnHide", function() Win.KeysOn(box, false) end)
    -- Follow the newest lines. The text can't change while open, so this never
    -- yanks the view away from the reader.
    local area = W.TextArea(box, { width = Copy.SIZE[1] - 28, step = 40, follow = true,
        onEscape = close })
    area:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -40)
    area:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -14, 14)
    box.area, box.edit = area, area.edit
    box:Hide()
    DUI.Motion.Window(box, 6)
end

-- Opens with a chat window's text (the selected tab by default).
function Copy.Show(cf)
    cf = cf or ns.Chat.Selected()
    if type(cf) ~= "table" then return end
    if not box then buildBox() end
    -- Same font, size and outline as the chat (Box.Font).
    if type(box.edit.SetFont) == "function" then
        box.edit:SetFont(Style.FontFile(ns.MEDIA.font), ns.Chat.TextSize(),
            (cfg and cfg.outline) and "OUTLINE" or "")
        box.edit:SetShadowOffset(1, -1)
        box.edit:SetShadowColor(0, 0, 0, 0.9)
    end
    box.text = Copy.Text(cf)
    box.area.Lock(box.text) -- read-only: typing just restores the text
    box:Show()
    box:Raise()
    box.edit:SetText(box.text)
    box.edit:SetFocus()
    -- Cursor at the end too, since the box keeps the cursor in view.
    box.edit:SetCursorPosition(#box.text)
    -- Start at the newest lines, like the chat.
    box.area:SetVerticalScroll(box.area:GetVerticalScrollRange())
end

-- The Copy link at the right end of the tab row. It lives on our panel, never
-- on a chat window, and fades in while the mouse is over the chat.
function Copy.Build(parent)
    if button then return end
    button = DUI.Widgets.Link(parent)
    button:SetFrameLevel(parent:GetFrameLevel() + 10)
    button.SetLabel(L["Copy"])
    button:SetScript("OnClick", function() Copy.Show() end)
    button:SetAlpha(0)
    button:Hide()
end

function Copy.Button() return button end

-- Right end of the tab row, inside the panel's inset.
function Copy.Place(parent, inset, row)
    if not button then return end
    button:ClearAllPoints()
    button:SetPoint("RIGHT", parent, "TOPRIGHT", -inset, -(inset + row / 2))
end

function Copy.Apply(c)
    cfg = c
    if button and not wanted() then near = false; button:SetAlpha(0); button:Hide() end
end

function Copy.SetNear(on)
    if not button then return end
    on = on and wanted() and true or false
    if on == near then return end
    near = on
    if on then button:Show() end
    local M = DUI.Motion
    M.Tween(button, button:GetAlpha(), on and 1 or 0, M.FAST, function(a) button:SetAlpha(a) end,
        function() if not near then button:Hide() end end)
end

DUI.RegisterCommand("copy", function() Copy.Show() end, L["/dui copy - chat text to select and copy"])
