-- Chat in the Daylight UI look, on top of the game's own chat windows. They still
-- do all the work (sending, receiving, links, whispers, the dock); only their art
-- is cleared and ours drawn alongside:
-- * A framed panel in the bottom-left corner mirroring the info panel (its size
--   by default) holding the docked chat and its tabs. The game sometimes moves
--   the main window again; the watcher puts it back.
-- * The edit box over the tab row, shown only while typing (the game's "IM" style).
-- * A panel of its own behind each window pulled out of the dock.
-- * Restyled tabs: the game's art removed and its labels made transparent, our
--   W.Tab laid over each, with a faint line under the row.
-- * Chat text in our font; the size is still the game's setting.
-- * The menu, channel, voice and social side buttons hidden (their slash
--   commands still work).
-- * After a while with nothing new (10 seconds by default) the docked chat fades
--   with its tabs and panel; a new line, hovering or typing brings it back. Uses
--   the windows' alpha, which the game leaves alone (no fields touched).
-- * Panel background on or off, with its opacity.
-- * Resizing by dragging the bottom-right corner.
-- * Floating (Chat hides: Always, or in combat): the panel and tabs fade away and
--   the lines stay over the world (the game fades each after two minutes).
--   Hovering the spot or typing brings the panel back.
-- * Whispers in their own tab per person (the game's whisperMode), and every
--   message kind's color (the game's ChangeChatColor).
--
-- The chat windows feed secure code (whispers, the reply target), so nothing here
-- writes a field on them, replaces their functions, or reparents their parts.
-- Their art is cleared (the game never sets it again, only tints and fades it),
-- buttons are hidden when they show, and a light watcher runs a few times a
-- second to restyle new windows, keep the main one in place and follow the
-- selected tab. Short tags and the line fade use the game's redraw callback
-- (Tags.lua, Feel.lua), web links a message filter (Links.lua). The only hook on
-- the windows is the Daylight chat box's read-only AddMessage hook (Box.lua):
-- with chat style "Daylight" (the default) its own list and tabs replace them.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Chat = {}
ns.Chat = Chat

Chat.EDGE = 12 -- from the screen's bottom-left corner, like the info panel from its corner
Chat.PAD = 8 -- inset inside the panel's border
Chat.INFO_PAD = 5 -- the info panel's inset (Chat.Size matches its body)
Chat.GAP = 4 -- gap between the panel and the input strip under it (as the info panel)
Chat.TAB_ROOM = 24 -- space above the chat for its tabs (and the edit box)
Chat.FLOAT_PAD = 4 -- panel margin around an undocked window
Chat.WATCH = 0.25 -- watcher interval, seconds
Chat.TAB_PAD = 6 -- padding each side of a tab label
Chat.TAB_TEXT = Style.SIZE.body -- tab label size before settings load (tabSize after)
Chat.GRIP = 16 -- resize grip size
Chat.MIN = { 250, 100 } -- resize limits (same range as the Width and Height sliders)
Chat.MAX = { 1000, 600 }
Chat.AWAKE = 1.5 -- floating: seconds the panel stays after the mouse leaves
Chat.INPUT = { borderPx = 2, flat = true, noBevel = true, bgAlpha = 0.9 } -- edit box backdrop, solid over the tabs
Chat.TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
                 "HighlightLeft", "HighlightMiddle", "HighlightRight" }
Chat.EDIT_ART = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" } -- named after the box
Chat.EDIT_KEYS = { "focusLeft", "focusRight", "focusMid" }
Chat.BUTTONS = { "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
                 "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton", "TextToSpeechButtonFrame" }

local cfg
local dressed = setmetatable({}, { __mode = "k" }) -- chat frame -> true
local hidden = setmetatable({}, { __mode = "k" }) -- button kept hidden -> true
local panels = setmetatable({}, { __mode = "k" }) -- undocked chat frame -> our panel
local holder, panel, area -- the corner panel and the chat's spot inside it
local tabRow, rule -- our tab label layer (on the dock) and the line under the tabs

local function kind(obj)
    return type(obj) == "table" and obj.GetObjectType and obj:GetObjectType() or nil
end

-- Art is cleared rather than hidden: the game shows, tints and fades these again,
-- but never resets the texture.
local function clear(tex)
    if kind(tex) == "Texture" then tex:SetTexture(nil) end
end

local function keepHidden(f)
    if type(f) ~= "table" or hidden[f] or not f.HookScript then return end
    hidden[f] = true
    f:Hide()
    f:HookScript("OnShow", function(self) self:Hide() end)
end

-- Sets our font on a FontString or chat frame, keeping the game's size, and only
-- touches what differs. On a chat frame every font or shadow call rebuilds all its
-- lines and their links, so setting it repeatedly would swallow link clicks.
local function font(obj, size, flags)
    if type(obj) ~= "table" or not obj.GetFont then return end
    local file, current, currentFlags = obj:GetFont()
    size = size or current
    flags = flags or ""
    if type(size) ~= "number" then return end
    local want = Style.FontFile(ns.MEDIA.font)
    if file ~= want or size ~= current or (currentFlags or "") ~= flags then obj:SetFont(want, size, flags) end
    if obj.SetShadowOffset and obj.GetShadowOffset then
        local x, y = obj:GetShadowOffset()
        if x ~= 1 or y ~= -1 then obj:SetShadowOffset(1, -1) end
        local r, g, b, a = obj:GetShadowColor()
        if r ~= 0 or g ~= 0 or b ~= 0 or type(a) ~= "number" or math.abs(a - 0.9) > 0.01 then
            obj:SetShadowColor(0, 0, 0, 0.9)
        end
    end
end

-- The chat text size in use: ours if set, else the main window's (the game's).
-- That way the Text size slider and tab menu show a real size, never the 0 saved
-- for "use the game's".
function Chat.TextSize()
    if cfg and (cfg.textSize or 0) > 0 then return cfg.textSize end
    local cf = _G.ChatFrame1
    local size = type(cf) == "table" and cf.GetFont and select(2, cf:GetFont())
    return type(size) == "number" and math.floor(size + 0.5) or 14
end

-- Tab label size (tabSize). In Classic it's also set on the game's labels under
-- ours so they line up.
function Chat.TabText()
    return cfg and type(cfg.tabSize) == "number" and cfg.tabSize or Chat.TAB_TEXT
end

-- Sets one of our tab labels to that size. A changed size refits on the next layout.
function Chat.SizeTab(b)
    local size = Chat.TabText()
    if b.size == size then return end
    b.size = size
    Style.SetTextSize(b.text, size)
end

-- Second panel text size: its own with sideTextSizeOwn, else Chat.TextSize.
function Chat.SideTextSize()
    if cfg and cfg.sideTextSizeOwn == true and type(cfg.sideTextSize) == "number" then return cfg.sideTextSize end
    return Chat.TextSize()
end

-- A chat window's text: the game's size unless textSize is set (0 = the game's),
-- plus an outline if enabled.
function Chat.Font(cf)
    local size = cfg and (cfg.textSize or 0) > 0 and cfg.textSize or nil
    font(cf, size, (cfg and cfg.outline) and "OUTLINE" or "")
end

-- The edit box text and its "Say:" header use the same size and outline as the
-- lines. Each one's original size is remembered here (nothing written on the
-- game's boxes), so a text size of 0 restores it.
local ownSize = {}
-- With inputSizeOwn the box uses its own size instead.
function Chat.InputSize()
    if cfg and cfg.inputSizeOwn == true and type(cfg.inputSize) == "number" then return cfg.inputSize end
    return cfg and (cfg.textSize or 0) > 0 and cfg.textSize or nil
end

local function inputFont(obj)
    if type(obj) ~= "table" or not obj.GetFont then return end
    if not ownSize[obj] then ownSize[obj] = select(2, obj:GetFont()) end
    local size = Chat.InputSize() or ownSize[obj]
    font(obj, size, (cfg and cfg.outline) and "OUTLINE" or "")
end

local INPUT_TEXTS = { "header", "headerSuffix", "languageHeader" }
local function fontInput(eb)
    inputFont(eb)
    for _, key in ipairs(INPUT_TEXTS) do inputFont(eb[key]) end
end

-- The chat windows, in one list rebuilt on every call (the watcher asks a few
-- times a second). Read it, don't keep it.
local frameList = {}
function Chat.Frames()
    local out, n = frameList, 0
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        if type(cf) == "table" then
            n = n + 1
            out[n] = cf
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

-- ---------------------------------------------------------------------
-- Dressing a window
-- Restyling a window

local function dressTab(tab)
    if type(tab) ~= "table" then return end
    for _, key in ipairs(Chat.TAB_ART) do clear(tab[key]) end
    clear(tab.glow) -- the game's unread flash; ours pulses instead (Feel.Alert)
    local text = tab.Text or (tab.GetFontString and tab:GetFontString())
    font(text, Chat.TabText())
end

local function dressInput(eb)
    if type(eb) ~= "table" or not eb.GetName then return end
    local name = eb:GetName()
    for _, key in ipairs(Chat.EDIT_ART) do clear(_G[name .. key]) end
    for _, key in ipairs(Chat.EDIT_KEYS) do clear(eb[key]) end
    -- Our edit box backdrop, on a frame of our own under the box's text.
    local back = CreateFrame("Frame", nil, eb)
    back:SetAllPoints(eb)
    back:SetFrameLevel(math.max(0, eb:GetFrameLevel() - 1))
    local look = {} -- one per box, since its outline is recolored by channel
    for k, v in pairs(Chat.INPUT) do look[k] = v end
    Style.Shell(back, look)
    ns.Feel.InputBack(eb, back)
    fontInput(eb)
end

-- A window pulled out of the dock gets its own panel (the corner panel covers the
-- dock). It's ours, attached to the window so it follows it. Its border matches
-- the corner panel (Chat.DressPanels), with the margin grown by the border width:
-- the heavy frame inside a plain FLOAT_PAD margin covered the window's bottom lines.
local function placeFloat(p, cf)
    local pad = Pixel.Px(p, Style.BorderPx(p)) + Chat.FLOAT_PAD
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", cf, "TOPLEFT", -pad, pad + Chat.TAB_ROOM)
    p:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", pad, -pad)
end

local function panelFor(cf)
    local p = CreateFrame("Frame", nil, cf)
    p:SetFrameStrata("BACKGROUND")
    Style.Shell(p, { flat = true, borderPx = 1 })
    placeFloat(p, cf)
    return p
end

-- ---------------------------------------------------------------------
-- Panel borders (border, borderSize, borderColor): one look for the corner panel,
-- the second panel and every undocked window. Same choices and colors as the
-- action bars' border settings.
-- ---------------------------------------------------------------------

local looked = setmetatable({}, { __mode = "k" }) -- chat panel shell -> true

-- "auto" follows the chat style: the full Daylight frame for the Daylight box, a
-- thin line for Classic.
function Chat.BorderStyle()
    local b = cfg and cfg.border or "auto"
    if b == "auto" then return ns.Box.On() and "daylight" or "flat" end
    return b
end

local function lookOf(back)
    local b = Chat.BorderStyle()
    if b == "daylight" then return { bgAlpha = back } end
    if b == "none" then return { flat = true, borderPx = 1, noBorder = true, bgAlpha = back } end
    return { flat = true, borderPx = cfg and cfg.borderSize or 1, bgAlpha = back }
end

-- A chat panel's resting border color, or nil for the shell's own (Default).
function Chat.BorderRest(s)
    if not (s and looked[s] and cfg) then return nil end
    local m = cfg.borderColor
    if m == "accent" then
        return { Style.Accent() }
    elseif m == "class" then
        local _, token = UnitClass("player")
        local r, g, b = Style.ClassColor(token)
        return r and { r, g, b } or nil
    elseif m == "custom" and type(cfg.borderCustom) == "table" then
        return cfg.borderCustom
    end
    return nil
end

-- Resting colors: the accent lights it (a gradient accent sweeps the outline). A
-- picked color goes on the outline, and on the Daylight frame a darker one on its
-- band. Any other shell (the edit box's) goes back to its own colors.
Chat.BAND_K = 0.7
function Chat.PaintBorder(s)
    if not s then return end
    local heavy = Style.IsHeavy(s)
    if looked[s] and cfg and cfg.borderColor == "accent" then
        Style.LightShell(s, heavy and Chat.BAND_K or nil)
        return
    end
    local c = Chat.BorderRest(s)
    local k = Chat.BAND_K
    Style.SetShellColors(s, c, (c and heavy) and { c[1] * k, c[2] * k, c[3] * k } or nil)
end

-- Second panel background: its own opacity, or the corner panel's.
function Chat.SideBack()
    if not cfg then return Style.BackAlpha() end
    if cfg.sideAlphaOwn == true and type(cfg.sideAlpha) == "number" then return cfg.sideAlpha end
    return Style.BackAlpha(cfg.panelAlphaOwn, cfg.panelAlpha)
end

local function dressShell(p, back)
    local s = Style.Shell(p, lookOf(back))
    if not s then return end
    looked[s] = true
    Chat.PaintBorder(s)
end

-- Applies the border settings to every chat panel (on a setting or style change,
-- a chat style switch, or a window pulled out of the dock).
function Chat.DressPanels()
    if not (panel and cfg) then return end
    local back = Style.BackAlpha(cfg.panelAlphaOwn, cfg.panelAlpha)
    dressShell(panel, back)
    for cf, p in pairs(panels) do
        dressShell(p, back)
        placeFloat(p, cf)
    end
    local side = ns.Box.side and ns.Box.side.panel
    if side then dressShell(side, Chat.SideBack()) end
end

-- The panel a window is in: its own if undocked, else the corner panel (link
-- tooltips sit on its top edge).
function Chat.PanelOf(cf)
    if cf ~= nil and cf == ns.Box.side.frame then return ns.Box.side.panel end
    local p = panels[cf]
    if p and not cf.isDocked then return p end
    return panel
end

-- Reapplies our font to a window's tab and edit box (after a font change).
-- font() only sets what differs.
local function fontParts(cf)
    local name = cf:GetName()
    local tab = _G[name .. "Tab"]
    if type(tab) == "table" then font(tab.Text or (tab.GetFontString and tab:GetFontString()), Chat.TabText()) end
    local eb = _G[name .. "EditBox"] or cf.editBox
    if type(eb) == "table" then fontInput(eb) end
end

function Chat.Dress(cf)
    if dressed[cf] then return end
    dressed[cf] = true
    local name = cf:GetName()
    for _, suffix in ipairs(CHAT_FRAME_TEXTURES or {}) do clear(_G[name .. suffix]) end
    Chat.Font(cf)
    dressTab(_G[name .. "Tab"])
    dressInput(_G[name .. "EditBox"] or cf.editBox)
    -- Every window's edit box, whisper tabs included (reused ones are skipped there).
    ns.Recall.Watch(_G[name .. "EditBox"] or cf.editBox)
    ns.Tell.Watch(_G[name .. "EditBox"] or cf.editBox)
    if cfg and cfg.hideButtons then keepHidden(cf.buttonFrame) end
    -- Move the game's scroll bar out of the way. The wheel still scrolls (Shift for a
    -- page, Ctrl for the ends). Its jump-to-bottom arrow loses its art and sits under
    -- our "New messages" pill (Feel.Pill).
    keepHidden(cf.ScrollBar)
    ns.Feel.DressJump(cf.ScrollToBottomButton)
    ns.Feel.WatchLines(cf)
    if cf ~= _G.ChatFrame1 then
        local p = panelFor(cf)
        panels[cf] = p
        if cfg then
            dressShell(p, Style.BackAlpha(cfg.panelAlphaOwn, cfg.panelAlpha))
            placeFloat(p, cf)
        end
    end
    Chat.LineTime(cf)
end

-- ---------------------------------------------------------------------
-- The corner panel
-- The corner panel

-- The chat's size inside the panel. When set to match and the info panel exists,
-- it's the info panel's size with its meter out (body height; meter width, gap
-- and minimap across). Otherwise our own settings.
function Chat.Size()
    local body = _G.DaylightUIInfoPanelBody
    if cfg.matchInfo and type(body) == "table" and (body:GetHeight() or 0) > 0 then
        local inset = Pixel.Px(body, Style.BorderPx(body)) + Chat.INFO_PAD
        local inner = body:GetHeight() - 2 * inset
        local meter = DUI:Get("InfoPanel", "meter.width") or 0
        local mapOn = DUI:Get("InfoPanel", "map.enabled")
        local w = meter + (mapOn and (inner + inset) or 0)
        return w, inner
    end
    return cfg.width, cfg.height
end

-- Panel height (chat plus padding) from the settings. The whisper conversation
-- uses the same height (Convo.lua).
function Chat.PanelHeight()
    if not cfg then return 0 end
    local _, h = Chat.Size()
    return 2 * (Chat.inset or 0) + (h or 0)
end

-- Where the edit box goes. Each chat style keeps its own choice (Daylight types
-- inside its bottom by default, Classic over the tabs).
function Chat.InputAt()
    if not cfg then return "top" end
    if ns.Box.On() then return cfg.boxInputAt or "bottom" end
    return cfg.inputAt or "top"
end

local function buildPanel()
    holder = CreateFrame("Frame", "DaylightUIChat", UIParent)
    holder:SetFrameStrata("BACKGROUND")
    holder:SetSize(1, 1)
    panel = CreateFrame("Frame", "DaylightUIChatPanel", holder)
    -- A calm box: thin warm border, no heavy frame, so the chat reads as text on a
    -- soft dark card.
    Style.Shell(panel, { flat = true, borderPx = 1 })
    area = CreateFrame("Frame", nil, panel)
    -- Our tab labels are parented to the dock, so they fade and float with it.
    local host = _G.GeneralDockManager or holder
    tabRow = CreateFrame("Frame", nil, host)
    tabRow:SetAllPoints(host)
    tabRow:SetFrameLevel(host:GetFrameLevel() + 10)
    rule = panel:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    DUI.Movers.Register(holder, "chat", "Chat",
        function() return { "BOTTOMLEFT", nil, "BOTTOMLEFT", Chat.EDGE, DUI.Movers.Above(Chat.EDGE) } end,
        { scale = function(s) Chat.ScaleTo(s) end, bottom = true })
    Chat.BuildGrip()
    -- The login fade-in outlines the chat even with its background off (its panel
    -- border is traced while it shows).
    DUI.Fade.RevealAlso(function() if not panel:IsShown() then return holder end end)
end

-- The Scale slider (and the wheel over the chat's unlock handle) scales our panel
-- and the game's docked windows with their tab row together, so the text grows
-- with the box. Undocked windows keep the game's scale: the game saves their
-- position in the window's own units relative to the screen
-- (FCF_SavePositionAndDimensions), so a scaled one would creep every reload.
-- Not while the game is dragging one (MOVING_CHATFRAME).
Chat.scale = 1
local function near(a, b) return math.abs((a or 1) - b) < 0.001 end
local function scaleGame()
    local s = Chat.scale
    local dock = _G.GeneralDockManager
    if type(dock) == "table" and not near(dock:GetScale(), s) then dock:SetScale(s) end
    for _, cf in ipairs(Chat.Frames()) do
        local want = (cf == _G.ChatFrame1 or cf.isDocked) and s or 1
        -- The combat log while it's shown in the second panel uses that panel's scale.
        if cf == _G.ChatFrame2 and ns.Tabs.logSide then want = Chat.sideScale or 1 end
        if not near(cf:GetScale(), want) and _G.MOVING_CHATFRAME ~= cf then cf:SetScale(want) end
    end
end

function Chat.ScaleTo(s)
    Chat.scale = s
    if holder and not near(holder:GetScale(), s) then holder:SetScale(s) end
    scaleGame()
end

-- ---------------------------------------------------------------------
-- Resizing by the corner
-- ---------------------------------------------------------------------

-- Panel sizes (panelH and the strip under it) around the chat's size.
local function edges()
    local inset = Chat.inset or 0
    local inputH = cfg and Chat.InputAt() == "below" and (Chat.GAP + Chat.TAB_ROOM) or 0
    return 2 * inset, 2 * inset + inputH
end

-- The game's own resize grip in a panel's bottom-right corner, shown while
-- hovering the chat. Dragging resizes the panel live (the chat is anchored to
-- it); on release the chat's new size goes to spec.done.
-- spec: holder (what gets resized), parent, panel, name, edges() = space around
-- the chat, sizing(on), done(width, height), bounds() -> minW, minH, maxW, maxH
-- (defaults to Chat.MIN/MAX).
-- The grip art points down-right; other corners get it mirrored.
Chat.GRIP_COORDS = { BOTTOMRIGHT = { 0, 1, 0, 1 }, BOTTOMLEFT = { 1, 0, 0, 1 },
    TOPRIGHT = { 0, 1, 1, 0 }, TOPLEFT = { 1, 0, 1, 0 } }
local GRIP_SIGN = { BOTTOMRIGHT = { -1, 1 }, BOTTOMLEFT = { 1, 1 }, TOPRIGHT = { -1, -1 }, TOPLEFT = { 1, -1 } }

-- Moves the grip to the corner it resizes from (a whisper box can use any corner).
function Chat.GripCorner(grip, corner)
    if grip.corner == corner then return end
    grip.corner = corner
    local s = GRIP_SIGN[corner]
    grip:ClearAllPoints()
    grip:SetPoint(corner, grip.panel, corner, 2 * s[1], 2 * s[2])
    local c = Chat.GRIP_COORDS[corner]
    for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetHighlightTexture(), grip:GetPushedTexture() }) do
        if tex then tex:SetTexCoord(c[1], c[2], c[3], c[4]) end
    end
end

local function chatBounds() return Chat.MIN[1], Chat.MIN[2], Chat.MAX[1], Chat.MAX[2] end

function Chat.MakeGrip(spec)
    local box = spec.holder
    local bounds = spec.bounds or chatBounds
    box:SetResizable(true)
    local grip = CreateFrame("Button", spec.name, spec.parent)
    grip:SetSize(Chat.GRIP, Chat.GRIP)
    grip.panel = spec.panel
    grip:SetFrameStrata(spec.strata or "MEDIUM") -- above the chat lines (LOW)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    Chat.GripCorner(grip, "BOTTOMRIGHT")
    grip:SetAlpha(0)
    grip:SetScript("OnMouseDown", function()
        if spec.allowed and not spec.allowed() then return end
        local w, h = spec.edges()
        local a, b, c, d = bounds()
        box:SetResizeBounds(a + w, b + h, c + w, d + h)
        grip.sizing = true
        spec.sizing(true)
        ns.Feel.Sizing(true, spec.panel)
        box:StartSizing(grip.corner)
    end)
    grip:SetScript("OnMouseUp", function()
        if not grip.sizing then return end
        grip.sizing = nil
        box:StopMovingOrSizing()
        spec.sizing(false)
        ns.Feel.Sizing(false, spec.panel)
        local w, h = spec.edges()
        local a, b, c, d = bounds()
        spec.done(math.max(a, math.min(c, math.floor(box:GetWidth() - w + 0.5))),
            math.max(b, math.min(d, math.floor(box:GetHeight() - h + 0.5))))
    end)
    return grip
end

-- Corner panel: on release, keep the size as Width and Height (no longer matching
-- the info panel) and save where it now sits.
function Chat.BuildGrip()
    Chat.grip = Chat.MakeGrip({ holder = holder, parent = holder, panel = panel, name = "DaylightUIChatGrip",
        edges = edges,
        sizing = function(on) Chat.sizing = on or nil end,
        done = function(width, height)
            DUI.Movers.Save("chat")
            DUI:Set("Chat", "matchInfo", false)
            DUI:Set("Chat", "width", width)
            DUI:Set("Chat", "height", height)
        end })
end

-- Fades in while hovering the chat (or while it's being dragged).
local function updateGrip(grip, over, sizing)
    if not grip then return end
    -- Locked from the chat header's padlock: no grip at all.
    local want = (over or sizing) and not (cfg and cfg.locked) and true or false
    if grip:IsMouseEnabled() == (cfg and cfg.locked or false) then
        grip:EnableMouse(not (cfg and cfg.locked))
    end
    if want == (grip.wanted or false) then return end
    grip.wanted = want
    local M = DUI.Motion
    M.Tween(grip, grip:GetAlpha(), want and 1 or 0, M.FAST, function(a) grip:SetAlpha(a) end)
end

-- Keeps the main chat window in its spot in the panel and the edit box over the
-- tab row. The game resets them at times (layout loading, chat style changes),
-- so put them back whenever they've moved.
local function anchoredTo(f, rel, n)
    if f:GetNumPoints() ~= n then return false end
    local _, r = f:GetPoint(1)
    return r == rel
end

-- Where each edit box was last placed, tracked here rather than written on the
-- game's edit boxes (taint there breaks whisper replies in instances). The IM chat
-- style types in each tab's own box, so the main window's and every docked one go
-- in the same spot. An undocked window gets its box back under itself, where the
-- game's template puts it.
local ebAt = {}
local inputMouse = {} -- each box's mouse state as last set (Chat.Input)

local function placeInput(eb, at, rel, force)
    -- Daylight chat box: the game's edit box goes over its footer field.
    local field = at == "bottom" and ns.Box.On() and ns.Box.HasFooter() and ns.Box.Field()
    if field then
        if not force and anchoredTo(eb, field, 2) and ebAt[eb] == "field" then return end
        ebAt[eb] = "field"
        eb:ClearAllPoints()
        eb:SetPoint("TOPLEFT", field, "TOPLEFT", 0, 0)
        eb:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 0, 0)
        return
    end
    if not force and anchoredTo(eb, rel, 2) and ebAt[eb] == at then return end
    local where = at == "top" and "TOP" or "BOTTOM"
    local inset = at == "below" and 0 or (Chat.inset or 0)
    local y = where == "TOP" and -inset or inset
    ebAt[eb] = at
    eb:ClearAllPoints()
    eb:SetPoint(where .. "LEFT", rel, where .. "LEFT", inset, y)
    eb:SetPoint(where .. "RIGHT", rel, where .. "RIGHT", -inset, y)
    eb:SetHeight(Chat.TAB_ROOM)
end

local function giveBack(eb, cf)
    ebAt[eb] = nil
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -5, -2)
    eb:SetPoint("RIGHT", type(cf.ScrollBar) == "table" and cf.ScrollBar or cf, "RIGHT", 8, 0)
    inputMouse[eb] = nil
    eb:SetAlpha(1)
    eb:EnableMouse(true)
end

function Chat.Hold(force)
    local cf = _G.ChatFrame1
    if not (area and type(cf) == "table") then return end
    -- Chat windows are clamped away from the screen edge (room for the side buttons,
    -- which are hidden). Ours sits in the corner panel, itself kept on screen, so the
    -- clamp would push the window across it.
    if cf.IsClampedToScreen and cf:IsClampedToScreen() then cf:SetClampedToScreen(false) end
    if not anchoredTo(cf, area, 2) then
        cf:ClearAllPoints()
        cf:SetPoint("TOPLEFT", area, "TOPLEFT")
        cf:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
    end
    -- Over the tabs, along the panel's bottom, or in the strip reserved under the
    -- whole block ("below").
    local at = Chat.InputAt()
    local rel = at == "below" and holder or panel
    for _, w in ipairs(Chat.Frames()) do
        local eb = _G[w:GetName() .. "EditBox"] or w.editBox
        if type(eb) == "table" then
            if w == cf or w.isDocked then placeInput(eb, at, rel, force)
            elseif ebAt[eb] then giveBack(eb, w) end
        end
    end
end

-- Sizes the panel and the chat's spot in it (under the tab row) from the settings.
function Chat.Layout()
    if not (holder and cfg) then return end
    local T = Pixel.Px(panel, Style.BorderPx(panel))
    local inset = T + Chat.PAD
    Chat.inset = inset
    local width, height = Chat.Size()
    local panelH = 2 * inset + height
    -- Edit box below the panel: a strip reserved for it at the very bottom.
    local inputH = Chat.InputAt() == "below" and (Chat.GAP + Chat.TAB_ROOM) or 0
    if not Chat.sizing then holder:SetSize(2 * inset + width, panelH + inputH) end
    -- Background on or off and its opacity (the border follows it).
    panel:SetShown(cfg.panelShown)
    local s = Style.GetShell(panel)
    local back = Style.BackAlpha(cfg.panelAlphaOwn, cfg.panelAlpha)
    if s then s.opts.bgAlpha = back end
    for _, p in pairs(panels) do
        p:SetAlpha((cfg.panelShown and 1 or 0) * Chat.float)
        local ps = Style.GetShell(p)
        if ps then
            ps.opts.bgAlpha = back
            Style.LayoutShell(ps)
        end
    end
    -- Anchored to all four sides of the holder, so dragging the resize grip resizes it
    -- (and the chat in it) live.
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", holder, "TOPLEFT")
    panel:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, inputH)
    Style.LayoutShell(Style.GetShell(panel))
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -(inset + Chat.TAB_ROOM))
    area:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -inset, inset)
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", panel, "TOPLEFT", inset, -(inset + Chat.TAB_ROOM))
    rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -inset, -(inset + Chat.TAB_ROOM))
    ns.Copy.Place(panel, inset, Chat.TAB_ROOM)
    ns.Tiles.Place(panel, inset, Chat.TAB_ROOM)
    ns.Box.Layout()
    -- Put it back in the new spot.
    if type(_G.ChatFrame1) == "table" then _G.ChatFrame1:ClearAllPoints() end
    Chat.Hold(true)
end

-- ---------------------------------------------------------------------
-- The watcher
-- ---------------------------------------------------------------------

local function selectedTab()
    if type(FCFDock_GetSelectedWindow) ~= "function" or not GENERAL_CHAT_DOCK then return nil end
    local ok, win = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
    if not ok or type(win) ~= "table" or not win.GetName then return nil end
    return _G[win:GetName() .. "Tab"]
end

-- The corner panel (for the copy button), its holder, the chat's spot in it, and
-- the window its selected tab shows (the Daylight chat box's list when that's on).
function Chat.Panel() return panel end
function Chat.Holder() return holder end
function Chat.Area() return area end
function Chat.Selected()
    if ns.Box.On() and ns.Box.Frame() then return ns.Box.Frame() end
    if type(FCFDock_GetSelectedWindow) ~= "function" or not GENERAL_CHAT_DOCK then return _G.ChatFrame1 end
    return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or _G.ChatFrame1
end

-- One pass over the chat windows: restyle new ones, register the short tags
-- redraw callback once each, keep the main one in the panel, show each undocked
-- one's panel, and place the line under the selected tab.
function Chat.Pass()
    Chat.Hold()
    scaleGame()
    local daylight = ns.Box.On()
    for _, cf in ipairs(Chat.Frames()) do
        Chat.Dress(cf)
        if not daylight then ns.Tags.Watch(cf) end
        local p = panels[cf]
        if p then p:SetShown(not cf.isDocked) end
    end
    ns.Box.Pass()
    Chat.Tabs()
    ns.Feel.Pill()
    ns.ChatMenu.Pass()
end

-- ---------------------------------------------------------------------
-- Tabs: ours over the game's
-- ---------------------------------------------------------------------

-- Each docked tab gets one of our W.Tab buttons laid over it. The game's label is
-- made transparent (alpha only, never its text, since the game sizes the tab from
-- it) and ours shows the same words: tan at rest, light on hover, the accent and
-- its underline once selected. Ours take no clicks, so the game's tab underneath
-- still selects, drags and opens its menu, and the game's 0.2 resting alpha on
-- its tabs no longer dims them.
local labels = setmetatable({}, { __mode = "k" }) -- game tab -> ours

local function labelFor(tab)
    local b = labels[tab]
    if b then return b end
    -- Its own underline stays hidden; one shared line glides between selected tabs
    -- (Feel.Glide).
    b = DUI.Widgets.Tab(tabRow, "", { size = Chat.TabText(), paintLine = function(t) t:SetAlpha(0) end })
    b:EnableMouse(false)
    b:SetAllPoints(tab)
    -- Our label stays inside the tab and is truncated like the game's: whisper tabs
    -- get a fixed width when the row is full (FCFDock_UpdateTabs).
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", b, "LEFT", Chat.TAB_PAD, 1)
    b.text:SetPoint("RIGHT", b, "RIGHT", -Chat.TAB_PAD, 1)
    b.text:SetWordWrap(false)
    labels[tab] = b
    if tab.HookScript then
        tab:HookScript("OnEnter", function() b.hover = true; b.Paint(true) end)
        tab:HookScript("OnLeave", function() b.hover = nil; b.Paint(false) end)
    end
    return b
end

-- The game's whisper (non-static) tabs scroll inside the dock's scroll frame,
-- which clips the ones out of view. Ours for them sit on a clip frame over it, so
-- they're clipped the same way.
local clip
local function layerFor(cf)
    if cf == _G.ChatFrame1 or cf.isStaticDocked then return tabRow end
    local sf = _G.GeneralDockManager and _G.GeneralDockManager.scrollFrame
    if type(sf) ~= "table" then return tabRow end
    if not clip then
        clip = CreateFrame("Frame", nil, tabRow)
        clip:SetClipsChildren(true)
        clip:SetAllPoints(sf)
    end
    return clip
end

local function words(tab) return tab.Text or (tab.GetFontString and tab:GetFontString()) end

-- The game puts its first tabs on the dock's bottom but centers the scrolling
-- ones in the dock's scroll frame, a few pixels higher (FCFDock_UpdateTabs). Ours
-- follow each tab horizontally but all sit on the row's bottom, so labels and the
-- underline line up. Left alone while the row isn't laid out yet.
local function standOnRow(b, tab)
    local rowB, tabB = tabRow:GetBottom(), tab:GetBottom()
    if issecretvalue and (issecretvalue(rowB) or issecretvalue(tabB)) then return end
    if type(rowB) ~= "number" or type(tabB) ~= "number" then return end
    local dy = rowB - tabB
    if math.abs(dy - (b.dy or 0)) < 0.01 then return end
    b.dy = dy
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, dy)
    b:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, dy)
end

function Chat.Tabs()
    if not tabRow then return end
    -- The Daylight chat box has its own tabs (Box.lua).
    if ns.Box.On() then
        for _, b in pairs(labels) do b:Hide() end
        return
    end
    local picked = selectedTab()
    for _, cf in ipairs(Chat.Frames()) do
        local tab = _G[cf:GetName() .. "Tab"]
        if type(tab) == "table" and tab.IsShown then
            local text = words(tab)
            local b = labels[tab]
            if (cf == _G.ChatFrame1 or cf.isDocked) and tab:IsShown() then
                b = labelFor(tab)
                Chat.SizeTab(b)
                local layer = layerFor(cf)
                if b:GetParent() ~= layer then b:SetParent(layer) end
                standOnRow(b, tab)
                if type(text) == "table" then
                    -- Only written when the label changes, not every watcher tick. A whisper tab's
                    -- name may be secret: SetText accepts it, so it's always written, never compared.
                    local t = text:GetText()
                    if issecretvalue and issecretvalue(t) then
                        b.words = nil
                        b.text:SetText(t)
                    elseif t ~= b.words or b.words == nil then
                        b.words = t
                        b.text:SetText(t)
                    end
                    if text:GetAlpha() ~= 0 then text:SetAlpha(0) end
                end
                b:Show()
                local on = tab == picked
                if (b.picked == true) ~= on then
                    b.Pick(on, true)
                    if on then ns.Feel.Glide(b) end
                end
                ns.Feel.Alert(tab, cf, b)
            else
                if b then b:Hide() end
                if type(text) == "table" and text:GetAlpha() ~= 1 then text:SetAlpha(1) end
            end
        end
    end
end

function Chat.Label(tab) return labels[tab] end
function Chat.Labels() return labels end

-- ---------------------------------------------------------------------
-- Fading when idle
-- ---------------------------------------------------------------------

local lastActive = 0
local sideActive = 0 -- the second panel's idle clock, when it has its own setting
-- The mouse only wakes the panel it's over, even while the second panel follows
-- the chat: hovering the main chat never lights the loot panel.
local mainMouse, sideMouse = 0, 0

function Chat.Wake() lastActive = GetTime() end
function Chat.WakeSide() sideActive = GetTime() end

-- When each panel hides: the chat's hides, and the second panel's own sideHides
-- ("chat" means same as the main chat, sharing its clock, mouse and floating).
local function sideOwn()
    return cfg ~= nil and type(cfg.sideHides) == "string" and cfg.sideHides ~= "chat"
end
Chat.SideOwnHides = sideOwn

function Chat.HidesOf(isSide)
    if not cfg then return nil end
    if isSide and sideOwn() then return cfg.sideHides end
    return cfg.hides
end

local function secret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- Would the selected tab show this line? A window only shows a kind of line while
-- it's registered for that event (that tab's chat settings). Every window gets
-- channel lines, then keeps the ones for channels it lists, by zone number or
-- name, as the game matches them. An unreadable (secret) channel line counts as shown.
function Chat.ShowsMain(event, ...)
    if ns.Box.On() then return ns.Box.Shows(ns.Box.main, event, ...) end
    local cf = Chat.Selected()
    if type(cf) ~= "table" or type(cf.IsEventRegistered) ~= "function" then return true end
    if not cf:IsEventRegistered(event) then return false end
    if event ~= "CHAT_MSG_CHANNEL" and event ~= "CHAT_MSG_COMMUNITIES_CHANNEL" then return true end
    local zone, _, base = select(7, ...)
    if secret(zone) or secret(base) then return true end
    local names, zones = cf.channelList, cf.zoneChannelList
    if type(names) ~= "table" then return false end
    local baseUpper = type(base) == "string" and base:upper()
    for i, name in pairs(names) do
        if type(zone) == "number" and zone > 0 and type(zones) == "table" and zones[i] == zone then return true end
        if baseUpper and type(name) == "string" and name:upper() == baseUpper then return true end
    end
    return false
end

-- Or the tab selected on the second panel.
function Chat.Shows(event, ...)
    return Chat.ShowsMain(event, ...) or (ns.Box.On() and ns.Box.Shows(ns.Box.side, event, ...))
end

-- A new line only wakes the chat if it lands in the tab you're looking at; lines
-- for another tab, or a kind this tab hides, don't. The idle clock only runs with
-- idle fade on. When off, lines aren't checked at all (turning it on restarts the
-- clock, Chat.Build).
local function idleFadeOn(isSide) return Chat.HidesOf(isSide) == "fightsIdle" end

-- A line wakes the main chat when its tab shows it (and the second panel while
-- that one follows the chat), and a second panel with its own setting when its
-- own tab does.
local function heard(gains, event, ...)
    if not cfg or (gains and cfg.ignoreGains) then return end
    local own = sideOwn()
    local mainSees = idleFadeOn() and (own and Chat.ShowsMain(event, ...) or (not own and Chat.Shows(event, ...)))
    if mainSees then Chat.Wake() end
    if own and idleFadeOn(true) and ns.Box.SideOn() and ns.Box.Shows(ns.Box.side, event, ...) then Chat.WakeSide() end
end
Chat.WAKE_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_SYSTEM" }
for _, e in ipairs(Chat.WAKE_EVENTS) do
    DUI.RegisterEvent(e, function(event, ...) heard(false, event, ...) end)
end

-- Loot, money, XP, reputation and skill-ups are a steady trickle while grinding,
-- so they only wake it with "ignore loot and combat gains" off.
Chat.GAIN_EVENTS = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_CURRENCY", "CHAT_MSG_SKILL",
    "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE" }
for _, e in ipairs(Chat.GAIN_EVENTS) do
    DUI.RegisterEvent(e, function(event, ...) heard(true, event, ...) end)
end

-- What fades: the corner panel, the tab row and the docked windows (undocked ones
-- stay as they are). The edit box has its own rule (Chat.Input). The second panel
-- is its own fade area ("Chat.side") so it can follow its own setting.
local fadeList = {} -- one table, refilled, since the fade asks often
local function fading()
    local out = fadeList
    out[1] = holder
    local n = 1
    -- Daylight chat box: its lines and tabs are in the holder, and the game's windows
    -- stay hidden (Box.lua) rather than faded back in.
    if ns.Box.On() then
        for i = #out, n + 1, -1 do out[i] = nil end
        return out
    end
    if _G.GeneralDockManager then n = 2; out[2] = _G.GeneralDockManager end
    for _, cf in ipairs(Chat.Frames()) do
        if cf == _G.ChatFrame1 or cf.isDocked then n = n + 1; out[n] = cf end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

local sideList = {}
local function sideFading()
    sideList[1] = ns.Box.SideOn() and ns.Box.side.holder or nil
    return sideList
end

-- Is the game's edit box being typed in? HasFocus (and IsShown) return a secret
-- once the box holds one, e.g. a whisper sender's name in a dungeon fight becomes
-- its tell target. Then use the game's own record of the active box instead
-- (ChatFrameUtil's active window, set on focus gained and cleared on focus lost),
-- which is a plain frame.
local function focused(eb)
    local has = eb.HasFocus and eb:HasFocus()
    if not secret(has) then return has and true or false end
    local util = _G.ChatFrameUtil
    local active = type(util) == "table" and type(util.GetActiveWindow) == "function" and util.GetActiveWindow()
    return active == eb
end
Chat.Focused = focused

local function typing()
    for eb in pairs(ebAt) do
        local shown = eb:IsShown()
        if (secret(shown) or shown) and focused(eb) then return true end
    end
    return false
end
Chat.Typing = typing

-- Typing anywhere in the chat: its edit box, or a reply on the whisper card (which
-- is parented to the panel, so a fade would take it away mid-word).
local function writing() return typing() or ns.Convo.Typing() end

-- ---------------------------------------------------------------------
-- How long lines stay
-- ---------------------------------------------------------------------

-- Floating, each line fades lineTime seconds after it arrived (instead of the
-- game's 120), so a new line never brings old ones back. With the panel shown
-- every line stays, like the game's chat; only the panel's own fade hides them.
-- Hovering the chat shows every line; on leave they all stay lineTime longer,
-- then fade (the game's own approach, as with gamepad focus).
-- SetTimeVisible, SetFading and ResetAllFadeTimes are the game's "secure
-- elevation barriers" for addons (ScrollingMessageFrameSecureMixin): they run as
-- if untainted and leave no taint on the window.
-- Each panel is handled separately, so the second can float while the main one doesn't.
local showingAll, showingSide = false, false

local function isSideBox(cf) return cf ~= nil and cf == ns.Box.side.frame end

function Chat.LineTime(cf)
    if not cfg or type(cf.SetTimeVisible) ~= "function" then return end
    local t = cfg.lineTime or 8
    if cf:GetTimeVisible() ~= t then cf:SetTimeVisible(t) end
    if isSideBox(cf) then
        if showingSide then cf:SetFading(false) end
    elseif showingAll then cf:SetFading(false) end
end

local function showLines(cf, all)
    if all then ns.Feel.Reveal(cf) end
    cf:SetFading(not all)
    if not all then cf:ResetAllFadeTimes() end
end

-- all: show every line of the main chat; sideAll: the second panel's (nil = same).
function Chat.Lines(all, sideAll)
    all = all and true or false
    if sideAll == nil then sideAll = all end
    sideAll = sideAll and true or false
    if all ~= showingAll then
        showingAll = all
        for cf in pairs(dressed) do
            if type(cf.SetFading) == "function" then showLines(cf, all) end
        end
        for _, P in ipairs(ns.Box.Panes()) do
            if P.frame and not isSideBox(P.frame) then showLines(P.frame, all) end
        end
    end
    if sideAll ~= showingSide then
        showingSide = sideAll
        local box = ns.Box.side.frame
        if box then showLines(box, sideAll) end
    end
end

-- ---------------------------------------------------------------------
-- Floating
-- ---------------------------------------------------------------------

-- Floating (Chat hides: Always, combat with any setting but Never, or sitting at a
-- campfire with QoL's "Float the chat at the campfire", Chat.camp): the panel, the
-- tab row and undocked windows' panels fade away and only the lines stay over the
-- world, each fading after lineTime (Chat.Lines). Hovering the spot brings the
-- panel back for as long, plus Chat.AWAKE. Typing doesn't: only the edit box
-- shows, and no old lines come back.
Chat.float = 1 -- 1: panel shown, 0: floated away
Chat.sideFloat = 1 -- same for the second panel
Chat.awakeUntil = 0
Chat.sideAwakeUntil = 0

-- The main panel stays visible this long, floating or not (isSide: the second one).
function Chat.StayAwake(seconds, isSide)
    local key = isSide and "sideAwakeUntil" or "awakeUntil"
    Chat[key] = math.max(Chat[key], GetTime() + seconds)
end

-- isSide: the second panel, by its own setting.
function Chat.FloatWanted(isSide)
    if not cfg then return false end
    local hides = Chat.HidesOf(isSide)
    return hides == "always" or (Chat.fight == true and (hides == "fights" or hides == "fightsIdle"))
        or Chat.camp == true
end

-- The panel's own alpha and each undocked window's panel (ours). The tab row goes
-- through the fade engine's paint (Chat.PaintFaded), since it owns that frame's alpha.
local function paintFloat(k)
    Chat.float = k
    if panel then panel:SetAlpha(k) end
    local back = cfg and cfg.panelShown and 1 or 0
    for _, p in pairs(panels) do p:SetAlpha(back * k) end
    DUI.Fade.Hold("Chat.chat", false) -- repaint the tab row now
end

local function paintSideFloat(k)
    Chat.sideFloat = k
    local second = ns.Box.side.panel
    if second then second:SetAlpha(k) end
end

function Chat.PaintFaded(f, a)
    if f == _G.GeneralDockManager then a = a * Chat.float end
    f:SetAlpha(a)
end

-- Eased. Ours always, the game's tab row only out of combat, where it snaps since
-- nothing of the game's fades in combat. Coming back it takes its time along with
-- the lines (Feel.Reveal). In combat it's quick, but the Daylight box's panel and
-- tabs are ours, so they still ease.
local function floatTo(key, from, goal, snap, paint)
    local M = DUI.Motion
    local dur = goal == 1 and M.SLOW or M.NORMAL
    if snap then dur = 0
    elseif Chat.fight or InCombatLockdown() then dur = ns.Box.On() and M.FAST or 0 end
    M.Tween(key, from, goal, dur, paint)
end

-- over: mouse on the main chat (or its holder); sideOver: on the second panel.
-- Each only holds its own panel, even while the second one follows the chat (one
-- chat for lines and typing, not for the mouse).
local floatGoal, sideGoal = 1, 1
function Chat.UpdateFloat(over, snap, sideOver)
    if not panel then return end
    local now = GetTime()
    if over or Chat.sizing then Chat.awakeUntil = now + Chat.AWAKE end
    if sideOver or Chat.sideSizing then Chat.sideAwakeUntil = now + Chat.AWAKE end
    local goal = (not Chat.FloatWanted() or now < Chat.awakeUntil) and 1 or 0
    if goal ~= floatGoal then
        floatGoal = goal
        floatTo("chatFloat", Chat.float, goal, snap, paintFloat)
    end
    local sGoal = (not Chat.FloatWanted(true) or now < Chat.sideAwakeUntil) and 1 or 0
    if sGoal ~= sideGoal then
        sideGoal = sGoal
        floatTo("chatSideFloat", Chat.sideFloat, sGoal, snap, paintSideFloat)
    end
end

-- The fade itself belongs to the fade engine ("Chat.chat"). This handles the Copy
-- button, the resize grip, floating and the idle clock; hovering or typing counts
-- as activity.
function Chat.UpdateFade()
    if not (cfg and holder) then return end
    -- (While turning the camera the cursor is hidden, so it isn't over anything.)
    local looking = type(IsMouselooking) == "function" and IsMouselooking()
    local over = holder:IsMouseOver() and not looking
    local sideOver = ns.Box.SideOver() and not looking
    -- (always present in the Daylight chat box, beside the tabs)
    ns.Copy.SetNear(over and not ns.Box.On() and Chat.float > 0.5)
    updateGrip(Chat.grip, over, Chat.sizing)
    updateGrip(ns.Box.side.grip, sideOver, Chat.sideSizing)
    updateGrip(ns.Convo.Grip(), ns.Convo.Over(), ns.Convo.sizing)
    -- A hovered tile or an open conversation (parented to the panel) also hold the
    -- panel. In combat only the mouse and a reply being typed do.
    Chat.UpdateFloat(over or ns.Tiles.Over() or ns.Convo.Typing()
        or (ns.Convo.Key() ~= nil and not Chat.fight), nil, sideOver)
    ns.Tiles.Update(over)
    Chat.Lines(over or not Chat.FloatWanted(), sideOver or not Chat.FloatWanted(true))
    if writing() then Chat.Wake() end
    if sideOwn() then
        if over then Chat.Wake() end
        if sideOver then Chat.WakeSide() end
    else
        local now = GetTime()
        if over then mainMouse = now end
        if sideOver then sideMouse = now end
    end
end

-- A second panel with its own setting runs its own clock.
local function idle(isSide)
    local since = (isSide and sideOwn()) and sideActive or lastActive
    if not sideOwn() then since = math.max(since, isSide and sideMouse or mainMouse) end
    return GetTime() - since >= (cfg.idleAfter or 10)
end

-- Typing shows it. With idle fade on, so does a new line for the idle time, and
-- once idle it fades right away (below any other fade).
local function register()
    DUI.Fade.Register{ key = "Chat.chat", scope = "Chat", path = "fade", page = "Chat.chat",
        float = false, -- no float setting: "Chat hides" floats it its own way
        frames = fading,
        paint = Chat.PaintFaded,
        wake = function()
            if writing() then return true end
            return idleFadeOn() and not idle()
        end,
        cap = function()
            if idleFadeOn() and idle() then return 0 end
        end }
    -- The second panel: same opacity, its own setting (Chat.HidesOf).
    DUI.Fade.Register{ key = "Chat.side", scope = "Chat", path = "fade", page = "Chat.chat",
        float = false,
        frames = sideFading,
        wake = function()
            if not sideOwn() and writing() then return true end
            return idleFadeOn(true) and not idle(true)
        end,
        cap = function()
            if idleFadeOn(true) and idle(true) then return 0 end
        end }
end

-- The edit box sits over the tab row: visible and clickable only while typing,
-- otherwise invisible and letting clicks through to the tabs. The game keeps it
-- shown in its classic chat style (and doesn't always honor the typing-only one),
-- so this relies on neither. Applies to every box in our spot (each docked tab
-- has its own). Alpha is checked every frame (the game sets an idle box to 0.35),
-- mouse only on a change. It eases in and out (FAST) out of combat and snaps in
-- combat, where nothing of the game's fades. Its outline takes the channel color.
local inputAlpha = {} -- each box's eased alpha
function Chat.Input(dt)
    local M = DUI.Motion
    local step = (dt and M.On() and not (Chat.fight or InCombatLockdown())) and dt / M.FAST or 1
    local any, box = false, nil
    for eb in pairs(ebAt) do
        local typing = focused(eb)
        any = any or typing
        if typing then box = eb end
        local goal = typing and 1 or 0
        local a = inputAlpha[eb] or goal
        if a < goal then a = math.min(goal, a + step) elseif a > goal then a = math.max(goal, a - step) end
        inputAlpha[eb] = a
        local shown = eb:GetAlpha()
        if secret(shown) or shown ~= a then eb:SetAlpha(a) end
        if inputMouse[eb] ~= typing then
            inputMouse[eb] = typing
            eb:EnableMouse(typing)
        end
        ns.Feel.InputColor(eb, typing)
    end
    if ns.Box.On() then ns.Box.Typing(any) end
    Chat.PadTyping(box)
end

-- A controller: the game gives the chat the D-pad through its own chat frame
-- (the radial's Chat, or Enter), with its own buttons: A sends, X opens the
-- channels, Y the tab's settings, LB and RB step the tabs. Those hints are drawn
-- on the game's chat frame, which is parked out of sight here, so they show
-- over the typing box instead. With the Daylight chat box the tabs are Daylight
-- UI's own, so LB, RB and Y act on those.
local padHost, padBox

local function padTabs()
    local Box = ns.Box
    local out, at = {}, nil
    local tabs = Box.Tabs()
    for i = 1, #tabs do
        local b = Box.main.buttons[i]
        if b and b:IsShown() and Box.PaneOf(tabs[i]) == Box.main then
            out[#out + 1] = b
            if i == Box.Picked() then at = #out end
        end
    end
    return out, at
end

local function padHints()
    local Pad = DUI.Pad
    local K = Pad.GameKey
    return {
        { { K("GAMEPAD_FACE_BOTTOM", "PAD1") }, ACTION_LABEL_SEND or DUI.L["Send"] },
        { { Pad.KeyOf("X") }, ACTION_LABEL_CHAT_CHANNELS or DUI.L["Channels"] },
        { { Pad.KeyOf("Y") }, ACTION_LABEL_TAB_SETTINGS or DUI.L["Tab settings"] },
        { { K("GAMEPAD_SHOULDER_LEFT", "PADLSHOULDER"), K("GAMEPAD_SHOULDER_RIGHT", "PADRSHOULDER") }, DUI.L["Tabs"] },
        { { K("GAMEPAD_FACE_RIGHT", "PAD2") }, FRAME_ACTION_BACK or DUI.L["Back"] },
    }
end

local function padTabMenu()
    local Box = ns.Box
    local i = Box.Picked()
    local b = Box.main.buttons[i]
    if b then ns.Tabs.OpenMenu(b, i) end
end

-- eb: the typing box with the focus, or nil.
function Chat.PadTyping(eb)
    local Pad = DUI.Pad
    if not (Pad and Pad.On()) then eb = nil end
    if eb == padBox then return end
    padBox = eb
    if not padHost then
        padHost = CreateFrame("Frame", nil, UIParent)
        padHost.padHintsAbove, padHost.padNoDefaults, padHost.padHints = true, true, padHints
        Chat.padHost = padHost
    end
    if not eb then return Pad.Release(padHost) end
    padHost:ClearAllPoints()
    padHost:SetAllPoints(eb)
    local own = ns.Box.On()
    padHost.padKeys = own and { { key = "Y", label = ACTION_LABEL_TAB_SETTINGS or DUI.L["Tab settings"], run = padTabMenu } } or {}
    padHost.padTabs = own and padTabs or function() return {} end
    Pad.Take(padHost)
end

function Chat.Step(dt)
    Chat.Input(dt)
    ns.Feel.Step(dt)
    ns.Box.GlowStep()
end

-- Repaints our tab colors and the faint line under the tab row (style change:
-- accent, text colors).
local function paintTabs()
    for _, b in pairs(labels) do b.Paint(false); if b.picked then b.Pick(true) end end
    if rule then rule:SetColorTexture(1, 1, 1, 0.06) end
    ns.Box.Repaint()
    ns.Feel.Repaint()
end

-- ---------------------------------------------------------------------
-- The game's own settings behind ours
-- ---------------------------------------------------------------------

-- Class-colored names, timestamps and the typing-only ("IM") edit box are game
-- settings; only set when ours differs.
local function setCVar(name, value)
    if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return end
    local ok, current = pcall(GetCVar, name)
    if ok and current == value then return end
    pcall(SetCVar, name, value)
end

function Chat.ApplySettings()
    if not cfg then return end
    setCVar("chatClassColorOverride", cfg.classColors and "0" or "1")
    if cfg.timestamps and cfg.timestamps ~= "game" then setCVar("showTimestamps", cfg.timestamps) end
    -- The edit box sits over the tab row, so it's only up while typing. Chat.Input
    -- fades it; never Hide() the game's box, its OnHide would run under our taint.
    setCVar("chatStyle", "im")
    -- Whispers: each person in their own docked tab (flashing on new ones) plus the
    -- main tab, or only the main tab. The Daylight chat box shows whispers itself,
    -- so inline only.
    setCVar("whisperMode", (cfg.whisperTabs == false or ns.Box.On()) and "inline" or "popout_and_inline")
end

-- A message kind's color (the Message colors card): the game's own, read from
-- ChatTypeInfo and changed with ChangeChatColor like its chat settings. The game
-- saves it.
function Chat.ColorOf(chatType)
    local info = type(ChatTypeInfo) == "table" and ChatTypeInfo[chatType]
    if type(info) ~= "table" or type(info.r) ~= "number" then return { 1, 1, 1 } end
    return { info.r, info.g, info.b }
end

function Chat.SetColor(chatType, c)
    if type(ChangeChatColor) ~= "function" or type(c) ~= "table" then return end
    ChangeChatColor(chatType, c[1], c[2], c[3])
end

-- ---------------------------------------------------------------------
-- Build and refresh
-- ---------------------------------------------------------------------

local built = false

function Chat.Build(mod)
    cfg = mod.db
    if built then return Chat.Refresh(mod) end
    built = true
    buildPanel()
    ns.Feel.Build({ holder = holder, panel = panel, area = area, tabRow = tabRow, rule = rule })
    register()
    ns.Copy.Build(panel)
    if cfg.hideButtons then
        for _, name in ipairs(Chat.BUTTONS) do keepHidden(_G[name]) end
    end
    local watcher = CreateFrame("Frame")
    local wait = 0
    Chat.Wake()
    Chat.WakeSide()
    watcher:SetScript("OnUpdate", function(_, dt)
        Chat.Step(dt)
        wait = wait + dt
        if wait < Chat.WATCH then return end
        wait = 0
        Chat.Pass()
        Chat.UpdateFade()
    end)
    for _, e in ipairs({ "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS" }) do
        DUI.RegisterEvent(e, Chat.Pass)
    end
    -- "Float during fights" floats it in combat (at once, since the game's tab row
    -- never fades in combat); leaving combat brings the panel back.
    DUI.RegisterEvent("PLAYER_REGEN_DISABLED", function() Chat.fight = true; Chat.UpdateFloat() end)
    DUI.RegisterEvent("PLAYER_REGEN_ENABLED", function() Chat.fight = nil; Chat.UpdateFloat() end)
    -- The campfire (QoL) floats it while you sit; combat wakes it at once.
    DUI.On("Campfire", function(on, snap) Chat.camp = on or nil; Chat.UpdateFloat(nil, snap) end)
    -- The info panel is laid out after us at login and whenever its settings change,
    -- so match it again then.
    DUI.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        Chat.Layout()
        Chat.Pass()
    end)
    DUI.On("SettingChanged", function(scope, path)
        if scope == "InfoPanel" then Chat.Layout() end
        -- Idle fade just turned on (even mid-fight, before Chat.Refresh): start its clock
        -- now, since lines weren't counted while it was off.
        if scope == "Chat" and path == "hides" then Chat.Wake() end
        if scope == "Chat" and path == "sideHides" then Chat.WakeSide() end
    end)
    DUI.On("StyleChanged", function() Chat.Refresh(mod) end)
    Chat.Refresh(mod)
end

function Chat.Refresh(mod)
    cfg = mod.db
    ns.Box.Apply(cfg)
    Chat.DressPanels()
    paintTabs()
    Chat.Layout()
    for cf in pairs(dressed) do
        Chat.Font(cf)
        fontParts(cf)
        Chat.LineTime(cf)
    end
    Chat.ApplySettings()
    ns.Links.Apply(cfg)
    ns.Kinds.Listen()
    ns.Extras.Apply(cfg)
    ns.Copy.Apply(cfg)
    ns.Tags.Apply(cfg)
    ns.Filter.Paint()
    ns.LinkTips.Apply(cfg)
    ns.Whisper.Apply(cfg)
    ns.Recall.Apply(cfg)
    Chat.Pass()
    -- A setting changed (from the options, over the chat): show it so the change is visible.
    Chat.Wake()
    Chat.WakeSide()
    Chat.UpdateFade()
end
