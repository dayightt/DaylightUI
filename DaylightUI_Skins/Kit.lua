-- Kit: the building blocks every skin uses. A skin strips one of the game's
-- windows of its art and dresses it in the Daylight UI look: dark panels, our
-- font, flat controls, our close button, chevrons and scroll bars, and light
-- text where the game prints dark text on parchment.
--
-- Every shell drawn here comes from one of the Kit.LOOK entries and is
-- remembered, so changing a look (or calling Kit.SetLook) restyles every window.
-- Kit.Auto walks a window and skins standard parts by their shape, so most
-- skins are just Kit.Window + Kit.Auto plus whatever art is unique to them.
--
-- The windows stay the game's. Nothing here replaces a function, moves a window
-- or writes fields on it (state lives in weak tables). Game art is only hidden
-- by alpha, so the game's own updates can't bring it back.

local _, ns = ...
local DUI = DaylightUI
local Style = DUI.Style

local Kit = {}
ns.Kit = Kit

Kit.TEXT = Style.INK.TEXT -- body text on dark panels
-- Controls get a warm outline at rest and the accent under the mouse. Selected,
-- focused or current items are picked out in the accent too.
Kit.CONTROL_BORDER = { 0.24, 0.21, 0.16 }
Kit.SELECTED = { 0.72, 0.7, 0.66 }
-- Follows the accent picked in the options, read at paint time. Quest and
-- section titles use it too, like list sections elsewhere.
Kit.HEADER = { 0.72, 0.7, 0.66 }
local function followAccent()
    local r, g, b = Style.Accent()
    Kit.SELECTED[1], Kit.SELECTED[2], Kit.SELECTED[3] = r, g, b
    Kit.HEADER[1], Kit.HEADER[2], Kit.HEADER[3] = r, g, b
end
DUI.On("StyleChanged", followAccent)
DUI.On("Login", followAccent)
Kit.DIM = Style.INK.LABEL -- secondary text
Kit.INSET_SHADE = 0.3                -- how much an inset darkens the panel
-- Art keys a game window is usually made of.
Kit.ART = { "NineSlice", "Bg", "Background", "TopTileStreaks", "PortraitContainer", "TitleBg",
            "Portrait", "portrait", "BorderFrame" }
-- Same, as suffixes on the window's global name (older windows).
Kit.NAMED_ART = { "Bg", "Portrait", "TitleBg", "TopTileStreaks", "BtnCornerLeft", "BtnCornerRight",
                  "ButtonBottomBorder", "InsetBg" }

local done = {} -- operation -> weak set of objects already done
-- Every dressing goes through here first. Forbidden frames are never touched:
-- touching one raises an error pcall can't catch, which used to stop all skins
-- at login.
local function once(op, obj)
    if type(obj) == "table" and obj.IsForbidden and obj:IsForbidden() then return false end
    local set = done[op]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        done[op] = set
    end
    if set[obj] then return false end
    set[obj] = true
    return true
end

local function isTable(x) return type(x) == "table" end
local function kind(x) return isTable(x) and type(x.GetObjectType) == "function" and x:GetObjectType() or nil end
Kit.Kind = kind

-- ---------------------------------------------------------------------
-- Profiling (/dui skins profile)
-- ---------------------------------------------------------------------

Kit.Profiling = false
local spent = {}
function Kit.Spent(what, ms) spent[what] = (spent[what] or 0) + ms end
function Kit.TakeSpent()
    local out = spent
    spent = {}
    return out
end

-- ---------------------------------------------------------------------
-- Looks
-- ---------------------------------------------------------------------

-- Half the normal border width (but not below the heavy look's minimum), for
-- small things like tab icons.

-- Style.Shell options per kind of thing. window matches the info panel's shell.
Kit.LOOK = {
    window = { window = "Skins" }, -- background follows Style.WindowBack
    control = { borderPx = 2, flat = true, noBevel = true, bgAlpha = 0.9 },    -- buttons, dropdowns, checkboxes
    input = { borderPx = 2, flat = true, noBevel = true, bgAlpha = 0.6 },      -- edit and search boxes
    tab = { borderPx = 2, flat = true, noBevel = true, bgAlpha = 0.85 },
    row = { borderPx = 2, flat = true, noBevel = true, bgAlpha = 0.35 },       -- list rows and headers
    outline = { borderPx = 3, flat = true, noBevel = true, noBackground = true },  -- items and slots
    icon = { borderPx = 4, flat = true, noBevel = true, noBackground = true }, -- heavy outline over the icon's edge
    bar = { borderPx = 2, flat = true, noBevel = true, bgAlpha = 0.6 },        -- progress and status bars
}
-- Icon tabs: how far the icon is cropped (the game draws a frame into it), and
-- the outline color while not selected.
Kit.SIDE_TAB_CROP = 0.1
Kit.TAB_BORDER = Style.NEUTRAL -- neutral, visible on any background
-- Scroll bar look, shared with W.Scroll.
Kit.SCROLL = DUI.Widgets.SCROLL

local shellLook = setmetatable({}, { __mode = "k" })    -- shell -> { look, extra }

local function lookOpts(look, extra)
    local o = {}
    for k, v in pairs(Kit.LOOK[look] or {}) do o[k] = v end
    if extra then for k, v in pairs(extra) do o[k] = v end end
    return o
end

-- Draws a shell of the given look on frame, with extra options on top.
-- Flat looks are drawn "lite": four edges and a background on the frame itself.
-- The full shell (corners, shadow, band, bevel, ~40 textures and two frames) is
-- kept for windows. Using it on every button, row and item made some windows
-- slow to open.
Kit.LITE = { control = true, input = true, tab = true, row = true, outline = true, icon = true, bar = true }
local liteOf = setmetatable({}, { __mode = "k" }) -- frame -> its lite shell
local lites = setmetatable({}, { __mode = "k" })

local function liteColor(s)
    local c = s.opts.borderColor or Style.BORDER
    local a = c[4] or DUI:Get("general", "borderAlpha") or 1
    -- Gradient accent on a selected outline: top and bottom sweep across the
    -- pair, the sides take its two ends.
    local g1, g2 = Style.AccentPair()
    if c == Kit.SELECTED and g1 and CreateColor and s.edges[1].SetGradient then
        local from, to = CreateColor(g1[1], g1[2], g1[3], a), CreateColor(g2[1], g2[2], g2[3], a)
        for i, e in ipairs(s.edges) do
            e:SetColorTexture(1, 1, 1, 1)
            if i <= 2 then
                e:SetGradient("HORIZONTAL", from, to)
            else
                local end_ = i == 3 and g1 or g2
                e:SetVertexColor(end_[1], end_[2], end_[3], a)
            end
        end
        return
    end
    for _, e in ipairs(s.edges) do
        e:SetColorTexture(c[1], c[2], c[3], a)
        e:SetVertexColor(1, 1, 1, 1) -- clear any leftover gradient
    end
end

-- When the accent changes, the StyleChanged handler below redraws selected
-- outlines (liteLayout also paints the color).

local function liteLayout(s)
    local o = s.opts
    local T = DUI.Pixel.Px(s.host, o.borderPx or 2)
    local top, bottom, left, right = s.edges[1], s.edges[2], s.edges[3], s.edges[4]
    top:SetHeight(T)
    bottom:SetHeight(T)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", s.host, "TOPLEFT", 0, -T)
    left:SetPoint("BOTTOMLEFT", s.host, "BOTTOMLEFT", 0, T)
    left:SetWidth(T)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", s.host, "TOPRIGHT", 0, -T)
    right:SetPoint("BOTTOMRIGHT", s.host, "BOTTOMRIGHT", 0, T)
    right:SetWidth(T)
    liteColor(s)
    if o.noBackground then
        s.bg:Hide()
    else
        local b = Style.BACKGROUND
        s.bg:SetColorTexture(b[1], b[2], b[3], o.bgAlpha or Style.BACKGROUND_ALPHA)
        s.bg:ClearAllPoints()
        s.bg:SetPoint("TOPLEFT", s.host, "TOPLEFT", T, -T)
        s.bg:SetPoint("BOTTOMRIGHT", s.host, "BOTTOMRIGHT", -T, T)
        s.bg:Show()
    end
end

local function liteShell(frame, opts)
    local s = { lite = true, host = frame, opts = opts, edges = {} }
    for i = 1, 4 do s.edges[i] = frame:CreateTexture(nil, "BORDER", nil, 7) end
    s.edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    s.edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    s.edges[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    s.edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    s.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    liteOf[frame] = s
    lites[s] = true
    liteLayout(s)
    return s
end

function Kit.Shell(frame, look, extra)
    if isTable(frame) and frame.IsForbidden and frame:IsForbidden() then return end
    local opts = lookOpts(look, extra)
    local s
    if Kit.LITE[look] then
        s = liteOf[frame]
        if s then s.opts = opts; liteLayout(s) else s = liteShell(frame, opts) end
    else
        s = Style.Shell(frame, opts)
    end
    shellLook[s] = { look = look, extra = extra }
    return s
end

-- A shell's outline color (nil = its look's default). Only redrawn when it
-- actually changes.
local function sameColor(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

function Kit.Paint(s, border)
    if not s then return end
    if s.lite then
        if sameColor(s.opts.borderColor, border) then return end
        s.opts.borderColor = border
        liteColor(s)
    else
        Style.SetShellColors(s, border, nil)
    end
end

-- Redraws every shell from its look, keeping highlight colors. Call after
-- changing Kit.LOOK.
function Kit.Restyle()
    for s, spec in pairs(shellLook) do
        local o = lookOpts(spec.look, spec.extra)
        o.borderColor, o.bandColor = s.opts.borderColor, s.opts.bandColor
        s.opts = o
        if s.lite then liteLayout(s) else Style.LayoutShell(s) end
    end
end

-- Changes one look everywhere, e.g. Kit.SetLook("window", "bgAlpha", 0.7).
function Kit.SetLook(look, key, value)
    Kit.LOOK[look] = Kit.LOOK[look] or {}
    Kit.LOOK[look][key] = value
    Kit.Restyle()
end

-- A border around something that fills its own frame (an icon, a slot, a bar's
-- fill), where a shell on the frame itself would be hidden behind it. Builds a
-- frame pad px larger on every side, below the target, and draws the shell
-- there. With over, it's drawn above the target's edge instead (pad 0 then
-- covers the edge exactly). target can be a frame or a region. Returns the shell.
function Kit.Outline(target, pad, look, over, extra)
    local parent = (kind(target) == "Texture" or kind(target) == "FontString") and target:GetParent() or target
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
    holder:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
    -- Below the target so its own art shows, or above its edge.
    local level = parent:GetFrameLevel()
    holder:SetFrameLevel(over and level + 2 or math.max(0, level - 1))
    holder:EnableMouse(false)
    return Kit.Shell(holder, look or "outline", extra)
end

-- ---------------------------------------------------------------------
-- Art and text
-- ---------------------------------------------------------------------

-- Hides a game region for good. Alpha, not Hide: the game may set its texture
-- again but won't bring it back into view.
function Kit.Hide(region)
    if isTable(region) and region.SetAlpha then region:SetAlpha(0) end
end

-- For textures the game keeps re-showing (hover art, glows it fades in): puts a
-- fully transparent mask on them, which survives anything the game does later.
-- No hooks on their methods: hooking a texture on a secure item button (a bag
-- slot's background) makes the game's own calls fail. A texture takes at most
-- 3 masks, so one with no room left is only faded with Kit.Hide. One mask per
-- frame, shared by its textures.
Kit.ERASE = DUI.MEDIA .. "mask-none.png"
local erasers = setmetatable({}, { __mode = "k" }) -- frame -> its transparent mask
local erased = setmetatable({}, { __mode = "k" }) -- texture -> the mask on it
function Kit.Erase(region)
    if kind(region) ~= "Texture" then return end
    region:SetAlpha(0)
    if erased[region] then return end
    local owner = region.GetParent and region:GetParent()
    if not isTable(owner) or not owner.CreateMaskTexture then return end
    if owner.IsForbidden and owner:IsForbidden() then return end
    local mask = erasers[owner]
    if not mask then
        mask = owner:CreateMaskTexture()
        mask:SetTexture(Kit.ERASE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(owner)
        erasers[owner] = mask
    end
    if pcall(region.AddMaskTexture, region, mask) then erased[region] = mask end
end

-- For tests and /dui skins dump.
function Kit.Erased(region) return erased[region] ~= nil end

-- Hides every texture a game frame owns, plus its usual art keys.
-- keep: textures to leave alone.
function Kit.Strip(frame, keep)
    if not isTable(frame) or not frame.GetRegions then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    keep = keep or {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if kind(r) == "Texture" and not keep[r] then r:SetAlpha(0) end
    end
    for _, key in ipairs(Kit.ART) do
        local r = frame[key]
        if isTable(r) and not keep[r] then Kit.Hide(r) end
    end
    local name = frame.GetName and frame:GetName()
    if type(name) == "string" then
        for _, suffix in ipairs(Kit.NAMED_ART) do
            local r = _G[name .. suffix]
            if isTable(r) and not keep[r] then Kit.Hide(r) end
        end
    end
end

-- Hides only a frame's backdrop (the nine BackdropTemplate pieces) and keeps
-- the rest, like an addon's icons. ClearBackdrop reuses the same pieces, so they
-- stay hidden. A frame that gets its first backdrop later is handled the next
-- time its skin runs.
Kit.BACKDROP = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                 "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
function Kit.Backdrop(frame)
    if not isTable(frame) then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    for _, key in ipairs(Kit.BACKDROP) do
        if kind(frame[key]) == "Texture" then frame[key]:SetAlpha(0) end
    end
end

-- Sets our font on a font string or edit box, keeping its size unless given.
-- color is an optional { r, g, b }. Setting a font makes the game re-layout the
-- text and lists call this on every update, so it's skipped unless the font or
-- size changed. Skinned windows follow the window text font setting.
local fonted = setmetatable({}, { __mode = "k" })     -- font string -> the font it was given
local fontedSize = setmetatable({}, { __mode = "k" }) -- font string -> the size asked for
local SLOT = { slot = Style.WINDOW_SLOT }
local EDIT = { slot = Style.WINDOW_SLOT, outline = "" }
function Kit.Font(fs, size, color)
    local k = kind(fs)
    if k ~= "FontString" and k ~= "EditBox" then return end
    local file = Style.FontFile(Style.WINDOW_SLOT)
    if fonted[fs] ~= file or fontedSize[fs] ~= size then
        fonted[fs], fontedSize[fs] = file, size
        Style.DressText(fs, size, k == "EditBox" and EDIT or SLOT)
    end
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
end

-- Puts our font back on text another addon re-fonts on refresh (RestedXP, the
-- dungeon journal). Keeps the size and is cheap when nothing changed.
function Kit.Refont(fs)
    if kind(fs) ~= "FontString" then return end
    local ok, file, size = pcall(fs.GetFont, fs)
    if ok and file == Style.FontFile(Style.WINDOW_SLOT) then return end
    Style.DressText(fs, ok and type(size) == "number" and size or nil, SLOT)
end

-- Some game text has its dark color baked in as an escape code (|cff000000
-- quest names in gossip), which SetTextColor can't override. Those dark runs
-- are rewritten to our text color. Links and quality colors aren't dark, so
-- they're left alone. Secret strings are never touched.
Kit.DARK_RUN = 0.3 -- runs this dark or darker get rewritten
local function hex(c)
    local function b(v) return math.floor(v * 255 + 0.5) end
    return string.format("%02x%02x%02x", b(c[1]), b(c[2]), b(c[3]))
end

local function darkRun(h)
    local r, g, b = tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16)
    return (0.3 * r + 0.59 * g + 0.11 * b) / 255 <= Kit.DARK_RUN
end

-- Our text color as an escape code, rebuilt only when Kit.TEXT changes.
local lightCode, lightOf
local function lightRun(h)
    if darkRun(h) then return lightCode end
end

function Kit.LightRuns(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text, 0 end
    if not string.find(text, "|c", 1, true) then return text, 0 end
    local c = Kit.TEXT
    if lightOf ~= c then lightOf, lightCode = c, "|cff" .. hex(c) end
    return string.gsub(text, "|c[fF][fF](%x%x%x%x%x%x)", lightRun)
end

local lit = setmetatable({}, { __mode = "k" }) -- font string -> the color it's kept in
-- Dropdown labels only get colored (no shadow, no run rewrite), since the
-- game's menu code sets their text.
local colourOnly = setmetatable({}, { __mode = "k" })

local function relightRuns(fs)
    local text = fs:GetText()
    local new, n = Kit.LightRuns(text)
    if n > 0 and new ~= text then fs:SetText(new) end
end

-- Makes dark-on-parchment text light for dark panels: sets its color and
-- rewrites dark color runs in the string. Never hooks the text itself: hooking
-- a font string the game sets from protected code makes that call fail with
-- "attempt to call a nil value". Instead the text is relit on later passes:
-- when the window is shown, when list rows are filled (Kit.EachRow), and from
-- post-hooks on the game's fill functions where a skin needs them (Packs/NPC.lua).
function Kit.Light(fs, color)
    if kind(fs) ~= "FontString" then return end
    local c = color or Kit.TEXT
    local owner = fs.GetParent and fs:GetParent()
    if kind(owner) == "DropdownButton" then colourOnly[fs] = true end
    fs:SetTextColor(c[1], c[2], c[3])
    if colourOnly[fs] then return end
    if lit[fs] == nil then Style.DressShadow(fs) end
    lit[fs] = c
    relightRuns(fs)
end

-- Relights a font string that was made light before. Others are left alone.
function Kit.Relight(fs)
    local c = lit[fs]
    if c then Kit.Light(fs, c) end
end

-- Work a list row part needs redone each time the game refills the row (a
-- collapse arrow, a bar's fill texture). Run by Kit.RelightIn, never by hooking
-- the game's methods.
local refits = setmetatable({}, { __mode = "k" })    -- frame -> fn
function Kit.OnRefill(frame, fn)
    if isTable(frame) then refits[frame] = fn end
end

-- Relights every previously lit font string in a frame and its children (up to
-- depth), e.g. a row the game just refilled. Also runs its Kit.OnRefill work.
function Kit.RelightIn(frame, depth)
    if not isTable(frame) or not frame.GetRegions then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local refit = refits[frame]
    if refit then DUI.SafeCall(refit) end
    for _, r in ipairs({ frame:GetRegions() }) do
        local c = lit[r]
        if c then Kit.Light(r, c) end
    end
    if (depth or 0) > 0 and frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do Kit.RelightIn(child, depth - 1) end
    end
end

-- Maps the game's own text colors to ours on every window Kit.Auto visits:
-- NORMAL_FONT_COLOR yellow becomes tan, disabled gray becomes our dim, dark
-- parchment ink becomes soft white. Other colors (white, quality, red/green,
-- class) carry meaning and stay. Checked on every pass so recolored text is
-- caught. Secret colors are skipped.
Kit.GAME_INK = {
    { 1, 0.82, 0, Style.INK.LABEL },
    { 0.5, 0.5, 0.5, Style.INK.OFF },
}
Kit.GAME_INK_NEAR = 0.03 -- how close a color must be to match
local function near(a, b) return math.abs(a - b) <= Kit.GAME_INK_NEAR end
local function inkOf(r, g, b)
    for _, c in ipairs(Kit.GAME_INK) do
        if near(r, c[1]) and near(g, c[2]) and near(b, c[3]) then return c[4] end
    end
    if (0.3 * r + 0.59 * g + 0.11 * b) <= Kit.DARK_RUN then return Kit.TEXT end
end

-- Text still in the ink it was given is skipped. If the game recolored it,
-- the color won't match and it's inked again.
local inked = setmetatable({}, { __mode = "k" }) -- font string -> the ink it was given
function Kit.InkGameText(frame)
    if not isTable(frame) or not frame.GetRegions then return end
    if frame.GetNumRegions and frame:GetNumRegions() == 0 then return end
    for _, fs in ipairs({ frame:GetRegions() }) do
        if kind(fs) == "FontString" and not lit[fs] and not colourOnly[fs] then
            local r, g, b = fs:GetTextColor()
            if type(r) == "number" and not (issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b))) then
                local was = inked[fs]
                if not (was and near(r, was[1]) and near(g, was[2]) and near(b, was[3])) then
                    local ink = inkOf(r, g, b)
                    if ink then
                        fs:SetTextColor(ink[1], ink[2], ink[3])
                        if ink == Kit.TEXT then Style.DressShadow(fs) end
                        inked[fs] = ink
                    end
                end
            end
        end
    end
end

-- Makes every font string in a frame (and its children, up to depth) light.
-- shownOnly skips hidden frames, for repeat passes.
function Kit.LightAll(frame, color, depth, shownOnly)
    if not isTable(frame) or not frame.GetRegions then return end
    if shownOnly and frame.IsShown and not frame:IsShown() then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if kind(r) == "FontString" then Kit.Light(r, color) end
    end
    if (depth or 0) > 0 and frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do Kit.LightAll(c, color, depth - 1, shownOnly) end
    end
end

-- ---------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------

local function titleOf(frame)
    local name = frame.GetName and frame:GetName()
    -- Fallback: a header on the top edge, either a dialog's
    -- (DialogFrameWithHeaderTemplate, `Text`) or the achievements' (`Title`).
    -- Its text is moved down into the title row too.
    local h = isTable(frame.Header) and frame.Header or nil
    local header = h and ((kind(h.Text) == "FontString" and h.Text) or (kind(h.Title) == "FontString" and h.Title)) or nil
    return (isTable(frame.TitleContainer) and frame.TitleContainer.TitleText)
        or (type(name) == "string" and _G[name .. "TitleText"]) or frame.TitleText or header
end

-- Puts the title on the left of the title row, like our own window headers.
-- Anchored by its top so a larger font grows downward, never into the accent
-- line. A long title stops short of the close button instead of running under it.
Kit.TITLE_X = 16 -- matches Win.EDGE
Kit.TITLE_TOP = 6 -- title top, just below the accent line
Kit.TITLE_RIGHT = 40 -- room for the close button (and a maximize beside it)
local function leftTitle(frame, title)
    if kind(title) ~= "FontString" then return end
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", Kit.TITLE_X, -Kit.TITLE_TOP)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Kit.TITLE_RIGHT, -Kit.TITLE_TOP)
    title:SetJustifyH("LEFT")
    if title.SetWordWrap then title:SetWordWrap(false) end
end
-- For a title that isn't on the window itself, e.g. one laid over the whole
-- group finder window by its page.
Kit.Title = leftTitle

-- The thin accent line along the window's top. Repainted when the accent changes.
local topLines = setmetatable({}, { __mode = "k" })   -- window -> its line
local function paintTopLine(line) Style.PaintAccent(line, 0.7) end
local function topLine(frame)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetHeight(DUI.Win and DUI.Win.LINE or 2)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -2)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -2)
    topLines[frame] = line
    paintTopLine(line)
end
function Kit.TopLineOf(frame) return topLines[frame] end

-- Dresses a game window: strips its art, adds the window look behind it, sets
-- the title font, our close button, and a darker inset. opts:
--   noBackground  border only (map windows)
--   keep          keys of the window's own textures to leave (a dialog's warning icon)
--   ownFade       the game animates its alpha in itself (alert frames); a fade
--                 of ours on top would leave it stuck at 0
function Kit.Window(frame, opts)
    if not isTable(frame) or not once("window", frame) then return end
    opts = opts or {}
    local keep = {}
    for _, key in ipairs(opts.keep or {}) do
        if isTable(frame[key]) then keep[frame[key]] = true end
    end
    Kit.Strip(frame, keep)
    -- quiet: no script on the shell's frame (see Kit.Button).
    local extra = (opts.noBackground or opts.quiet) and { noBackground = opts.noBackground, quiet = opts.quiet } or nil
    Kit.Shell(frame, "window", extra)
    local title = titleOf(frame)
    Kit.Font(title, Style.SIZE.title)
    Kit.Light(title, Style.INK.VALUE)
    if not opts.noBackground then
        leftTitle(frame, title)
        topLine(frame)
    end
    -- Windows that change their title text get it relit on open.
    if kind(title) == "FontString" and frame.HookScript then
        frame:HookScript("OnShow", function() Kit.Relight(title) end)
    end
    local name = frame.GetName and frame:GetName()
    -- Look up the X by name only if it's not a text button: the guild log's
    -- "Close" button uses the X's name. The walk below finds the real X.
    local named = type(name) == "string" and _G[name .. "CloseButton"]
    if isTable(named) and kind(named.Left) == "Texture" then named = nil end
    Kit.Close(frame.CloseButton or named)
    if isTable(frame.TitleContainer) then Kit.Close(frame.TitleContainer.CloseButton) end
    Kit.Close(frame.ClosePanelButton)
    local inset = frame.Inset or (type(name) == "string" and _G[name .. "Inset"])
    if inset then Kit.Inset(inset) end
    -- Fade in on open (out of combat; hiding stays the game's). Not for map
    -- windows, which are just our border around the game's map.
    if not opts.noBackground and DUI.Motion and frame.HookScript then
        if not opts.ownFade then
            frame:HookScript("OnShow", function(self) DUI.Motion.FadeIn(self) end)
        end
        -- Closing leaves a fading copy of the window behind (Motion.Ghost).
        if not (type(name) == "string" and Kit.GHOST[name]) then
            frame:HookScript("OnHide", function(self) DUI.Motion.Ghost(self, Kit.GhostDress) end)
        end
    end
end

-- Dresses a ghost copy: background on the ghost, border and shadow on a frame
-- above it that Motion.Ghost fades out faster. Returns that frame.
function Kit.GhostDress(g)
    Kit.Shell(g, "window", { noBorder = true, shadowAlpha = 0, noBevel = true })
    local edge = CreateFrame("Frame", nil, g)
    edge:SetAllPoints(g)
    edge:EnableMouse(false)
    Kit.Shell(edge, "window", { noBackground = true })
    return edge
end

-- Window names that skip the closing ghost. Add one here if it looks wrong.
Kit.GHOST = {}

-- A panel inside or beside a window (side panel, set list): art stripped,
-- window look.
function Kit.Panel(frame)
    if not isTable(frame) or not frame.CreateTexture or not once("panel", frame) then return end
    Kit.Strip(frame)
    Kit.Shell(frame, "window")
end

-- An inset panel: art stripped, a shade darker than the window.
local shades = setmetatable({}, { __mode = "k" })
local shadeOf = setmetatable({}, { __mode = "k" }) -- inset -> its shade
function Kit.ShadeOf(frame) return shadeOf[frame] end

-- Where an inset's shade is drawn. Usually the inset itself, since it sits under
-- its contents. Some insets sit above their list as a border only (the guild
-- window's, at levels 100 and 200), and a shade there would darken the whole
-- list. Those get a child frame at the parent's level instead (a child, because
-- Kit.Strip on the parent would fade a sibling out).
local function shadeHost(frame)
    local parent = frame.GetParent and frame:GetParent()
    if not isTable(parent) or not parent.GetFrameLevel then return frame end
    local level, under = frame:GetFrameLevel(), parent:GetFrameLevel()
    if type(level) ~= "number" or type(under) ~= "number" or level <= under + 1 then return frame end
    local host = CreateFrame("Frame", nil, parent)
    host:SetFrameLevel(under)
    host:SetAllPoints(frame)
    return host
end

function Kit.Inset(frame)
    if not isTable(frame) or not frame.CreateTexture or not once("inset", frame) then return end
    Kit.Strip(frame)
    local host = shadeHost(frame)
    local shade = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    shade:SetColorTexture(0, 0, 0, Kit.INSET_SHADE)
    shade:SetAllPoints(frame)
    shades[shade] = true
    shadeOf[frame] = shade
end

-- ---------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------

local BUTTON_ART = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }
local CHECKED_ART = { "GetCheckedTexture", "GetDisabledCheckedTexture" }

-- checked: also hide the checked art (tabs; checkboxes keep their tick).
local function hideButtonArt(btn, checked)
    for _, get in ipairs(BUTTON_ART) do
        if btn[get] then Kit.Hide(btn[get](btn)) end
    end
    if checked then
        for _, get in ipairs(CHECKED_ART) do
            if btn[get] then Kit.Hide(btn[get](btn)) end
        end
    end
end

-- Close button: game art hidden (old named pieces too), our X on top.
function Kit.Close(btn)
    if not isTable(btn) or not btn.CreateTexture or not once("close", btn) then return end
    hideButtonArt(btn)
    Kit.Strip(btn)
    DUI.Widgets.DressClose(btn)
end

-- Our chevron on a control. It points down by default; see Kit.ROTATION.
Kit.ROTATION = { down = 0, up = math.pi, right = math.pi / 2, left = -math.pi / 2 }
local function chevron(parent, rotation, size)
    local c = parent:CreateTexture(nil, "OVERLAY")
    c:SetTexture(DUI.MEDIA .. "ui-chevron.png")
    c:SetSize(size or 10, size or 10)
    local d = Kit.TEXT
    c:SetVertexColor(d[1], d[2], d[3], 1)
    if rotation and rotation ~= 0 then c:SetRotation(rotation) end
    return c
end

-- The shared control look, same as W.Button: a quiet warm outline at rest, an
-- accent trace around it on hover (W.Trace), a darker fill while pressed,
-- dimmer while disabled. Controls whose outline isn't their own edges (an
-- outline around an icon) light up in the accent instead. A resting accent
-- outline was too loud.
Kit.HOVER_LIGHTEN = 0.4 -- how much lighter a row's outline gets on hover
Kit.DISABLED_BORDER = { 0.14, 0.13, 0.11 }
Kit.PRESSED = 0.55 -- fill brightness while pressed
local looks = setmetatable({}, { __mode = "k" }) -- control -> { shell, hover }

local function paintLook(btn)
    local l = looks[btn]
    if not l then return end
    local off = btn.IsEnabled and not btn:IsEnabled()
    local border
    if off then
        border = Kit.DISABLED_BORDER
    elseif l.hover and not l.trace then
        border = Kit.SELECTED
    else
        border = Kit.CONTROL_BORDER
    end
    Kit.Paint(l.shell, border)
    if l.trace then l.trace.To(l.hover and not off) end
    local bg = l.shell and l.shell.bg
    if bg and bg.SetVertexColor then
        local k = (l.down and not off) and Kit.PRESSED or 1
        bg:SetVertexColor(k, k, k, 1)
    end
end

-- A soft wash over a hovered button, inside its border. Lives on the HIGHLIGHT
-- layer so it shows by itself. area: the frame to cover when it isn't the button
-- (a row whose hover comes from a button inside it).
Kit.HOVER_WASH = 0.08

function Kit.HoverWash(btn, area)
    if not (btn.CreateTexture and btn.GetObjectType and btn:GetObjectType() == "Button") then return nil end
    area = area or btn
    local wash = btn:CreateTexture(nil, "HIGHLIGHT")
    wash:SetColorTexture(1, 1, 1, Kit.HOVER_WASH)
    local T = DUI.Pixel.Px(area, 2)
    wash:SetPoint("TOPLEFT", area, "TOPLEFT", T, -T)
    wash:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -T, T)
    return wash
end

-- A text button's look, kept here and never stored on the game's button.
local buttonOf = setmetatable({}, { __mode = "k" })
function Kit.ButtonOf(btn) return buttonOf[btn] end

-- A dressed control's hover trace, or nil if it lights up in the accent instead.
function Kit.TraceOf(btn)
    if buttonOf[btn] then return buttonOf[btn].trace end
    return looks[btn] and looks[btn].trace
end

-- Hooks enter/leave on a game button. Some buttons get their scripts reset each
-- time they're shown (the game menu's pooled buttons: AddButton clears them
-- before Show), dropping our hooks, so they're re-added on show if missing.
local function hoverHooks(btn, enter, leave)
    local mine = {}
    local function wire()
        for script, fn in pairs({ OnEnter = enter, OnLeave = leave }) do
            if btn:GetScript(script) ~= mine[script] or mine[script] == nil then
                btn:HookScript(script, fn)
                mine[script] = btn:GetScript(script)
            end
        end
    end
    wire()
    btn:HookScript("OnShow", wire)
end

local function look(btn, shell)
    if looks[btn] then return looks[btn].shell end
    local l = { shell = shell or Kit.Shell(btn, "control") }
    looks[btn] = l
    l.wash = Kit.HoverWash(btn)
    -- The trace only fits when the outline is the button's own edges.
    local s = l.shell
    if s and s.lite and s.host == btn and DUI.Widgets and DUI.Widgets.Trace then
        l.trace = DUI.Widgets.Trace(btn, 0, DUI.Pixel.Px(btn, s.opts.borderPx or 2), "OVERLAY")
        btn:HookScript("OnHide", function() l.hover, l.down = false, false; l.trace.Snap(0); paintLook(btn) end)
    end
    hoverHooks(btn, function() l.hover = true; paintLook(btn) end,
        function() l.hover, l.down = false, false; paintLook(btn) end)
    btn:HookScript("OnMouseDown", function() l.down = true; paintLook(btn) end)
    btn:HookScript("OnMouseUp", function() l.down = false; paintLook(btn) end)
    if btn.IsEnabled then
        btn:HookScript("OnEnable", function() paintLook(btn) end)
        btn:HookScript("OnDisable", function() paintLook(btn) end)
    end
    paintLook(btn)
    return l.shell
end

local THREE_PART = { "Left", "Middle", "Right", "Center", "Mid", "LeftSeparator", "RightSeparator" }

-- A text button: the game's three-piece art removed, our button look (same as
-- W.Button), and the game's own label in our font. State lives in our table
-- (Kit.ButtonOf), never on the button; its scripts are hooked, not replaced.
-- A disabled button swaps its font object (SetDisabledFontObject), so ours is
-- put back.

-- Quiet controls: the same looks with no hooks that the game's own code can
-- set off. Showing, hiding, resizing or enabling a frame runs the scripts of
-- the pieces inside it within the game's call, ahead of the frame's own
-- OnShow, and addon code there taints whatever the game does next. A confirm
-- box is where that hurts: with the controller UI on, the game stores the
-- box's focus actions in its OnShow, and a tainted Cancel was then blocked.
-- So a quiet control only hooks the mouse entering and leaving it. Its
-- pressed, grayed-out and focused looks are read each frame while its box is
-- shown, from the box's own OnShow and OnHide hooks, which run after the
-- game's.
local quietOf = setmetatable({}, { __mode = "k" }) -- host -> { control -> refresh }
local quietShown = {}                              -- host -> true while shown
local quietPoller = CreateFrame("Frame")
quietPoller:Hide()
Kit.quietPoller = quietPoller
quietPoller:SetScript("OnUpdate", function()
    for host in pairs(quietShown) do
        for _, refresh in pairs(quietOf[host]) do refresh(false) end
    end
end)

local function quietHost(host)
    if quietOf[host] then return quietOf[host] end
    local list = {}
    quietOf[host] = list
    host:HookScript("OnShow", function()
        quietShown[host] = true
        quietPoller:Show()
        for _, refresh in pairs(list) do refresh(false) end
    end)
    host:HookScript("OnHide", function()
        quietShown[host] = nil
        if next(quietShown) == nil then quietPoller:Hide() end
        for _, refresh in pairs(list) do refresh(true) end
    end)
    if host:IsVisible() then quietShown[host] = true; quietPoller:Show() end
    return list
end

-- host: the frame that shows and hides it (a confirm box). Given, the button
-- is dressed quietly.
function Kit.Button(btn, host)
    if not isTable(btn) or not btn.CreateTexture or not once("button", btn) then return end
    hideButtonArt(btn)
    for _, key in ipairs(THREE_PART) do Kit.Hide(btn[key]) end
    local name = btn.GetName and btn:GetName()
    if type(name) == "string" then
        for _, key in ipairs(THREE_PART) do Kit.Hide(_G[name .. key]) end
    end
    local W = DUI.Widgets
    local fs = btn.GetFontString and btn:GetFontString()
    if kind(fs) ~= "FontString" then fs = nil end
    local s = W.ButtonLook(btn, {}, fs, host ~= nil)
    buttonOf[btn] = s
    if host then
        local ink = W.BUTTON.text
        local function words()
            if not fs then return end
            Style.DressText(fs, Style.SIZE.body)
            fs:SetTextColor(ink[1], ink[2], ink[3])
        end
        words()
        btn:HookScript("OnEnter", function() s.Hover(true) end)
        btn:HookScript("OnLeave", function() s.Hover(false) end)
        quietHost(host)[btn] = function(gone)
            if gone then s.Rest(); return end
            local off = (btn.IsEnabled and not btn:IsEnabled()) or nil
            local down = (not off and btn:GetButtonState() == "PUSHED") or false
            if off == s.off and down == (s.down or false) then return end
            -- A disabled button takes its disabled font object, so ours goes back.
            if off ~= s.off then words() end
            s.off, s.down = off, down
            s.Paint()
            s.Light(not off and btn:IsMouseOver() == true)
        end
        quietHost(host)[btn](false)
        return
    end
    local ink = W.BUTTON.text
    local function words()
        if not fs then return end
        Style.DressText(fs, Style.SIZE.body)
        fs:SetTextColor(ink[1], ink[2], ink[3])
    end
    local function state()
        s.off = (btn.IsEnabled and not btn:IsEnabled()) or nil
        words()
        s.Paint()
        s.Light(not s.off and btn:IsMouseOver() == true)
    end
    hoverHooks(btn, function() s.Hover(true) end, function() s.Hover(false) end)
    btn:HookScript("OnMouseDown", function() if not s.off then s.down = true; s.Paint() end end)
    btn:HookScript("OnMouseUp", function() s.down = false; s.Paint() end)
    if btn.IsEnabled then
        btn:HookScript("OnEnable", state)
        btn:HookScript("OnDisable", state)
    end
    state()
end

-- A dropdown (filter, set, status): the input look with a hover highlight, our
-- chevron, and its label in our font at the game's size. One with no label (just
-- an arrow) becomes a small square button outlined in the accent.
local function hoverOutline(frame, s)
    frame:HookScript("OnEnter", function() Kit.Paint(s, Kit.ROW_HOVER) end)
    frame:HookScript("OnLeave", function() Kit.Paint(s, nil) end)
end

function Kit.Dropdown(dd)
    if not isTable(dd) or not dd.CreateTexture or not once("dropdown", dd) then return end
    local label = dd.Text or (dd.GetFontString and dd:GetFontString())
    -- Keep a real icon; drop art that's only the game's arrow.
    local keep = {}
    if kind(dd.Icon) == "Texture" then
        local atlas = dd.Icon.GetAtlas and dd.Icon:GetAtlas()
        if not (type(atlas) == "string" and string.find(string.lower(atlas), "dropdown", 1, true)) then
            keep[dd.Icon] = true
        end
    end
    Kit.Strip(dd, keep)
    hideButtonArt(dd)
    for _, key in ipairs({ "Background", "Arrow", "Left", "Middle", "Right", "Texture" }) do Kit.Hide(dd[key]) end
    local name = dd.GetName and dd:GetName()
    if type(name) == "string" then
        for _, suffix in ipairs({ "Left", "Middle", "Right" }) do Kit.Hide(_G[name .. suffix]) end
    end
    local w = dd.GetWidth and dd:GetWidth()
    local iconOnly = kind(label) ~= "FontString" or (type(w) == "number" and not (issecretvalue and issecretvalue(w)) and w > 0 and w <= 36)
    -- Arrow only: small square button in the accent. With a label: the
    -- quieter input look.
    if iconOnly then look(dd) else hoverOutline(dd, Kit.Shell(dd, "input")) end
    local c = chevron(dd, Kit.ROTATION.down)
    if iconOnly then
        c:SetPoint("CENTER", dd, "CENTER", 0, 0)
    else
        c:SetPoint("RIGHT", dd, "RIGHT", -8, 0)
        Kit.Font(label)
        colourOnly[label] = true
        Kit.Light(label)
    end
end

-- A list's collapse button (statistics sub-headers): control look with our
-- chevron, down while open and right while closed. Open/closed is read from the
-- game's own art, which it swaps only when refilling the row (RefreshIcon from
-- Initialize). So the arrow is updated then, via Kit.OnRefill, and on every pass
-- over the list. The game's art itself is erased for good.
local collapsePoint = setmetatable({}, { __mode = "k" })   -- button -> fn
function Kit.CollapseButton(btn)
    if not isTable(btn) or not btn.CreateTexture then return end
    if not once("collapse", btn) then
        if collapsePoint[btn] then collapsePoint[btn]() end
        return
    end
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    hideButtonArt(btn)
    Kit.Erase(normal)
    look(btn)
    local c = chevron(btn, Kit.ROTATION.down, 8)
    c:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local function point()
        local atlas = kind(normal) == "Texture" and normal.GetAtlas and normal:GetAtlas()
        local closed = type(atlas) == "string" and (string.find(string.lower(atlas), "closed", 1, true)
            or string.find(string.lower(atlas), "plus", 1, true))
        c:SetRotation(closed and Kit.ROTATION.right or Kit.ROTATION.down)
    end
    collapsePoint[btn] = point
    Kit.OnRefill(btn, point)
    point()
end

-- An edit or search box: three-piece art removed, our text box look.
local inputOf = setmetatable({}, { __mode = "k" })   -- box -> its look
Kit.INPUT_ROOM = 6 -- px between the box edge and its text
-- host: dressed quietly, as Kit.Button.
function Kit.EditBox(eb, host)
    if kind(eb) ~= "EditBox" or not once("editbox", eb) then return end
    for _, key in ipairs(THREE_PART) do Kit.Hide(eb[key]) end
    local name = eb.GetName and eb:GetName()
    if type(name) == "string" then
        for _, key in ipairs(THREE_PART) do Kit.Hide(_G[name .. key]) end
    end
    Kit.Hide(eb.NineSlice)
    if kind(eb.Background) == "Texture" then Kit.Hide(eb.Background) end -- a search box's own fill sits over our look
    -- Same look as W.Input: a rounded dark box whose outline eases toward the
    -- accent, halfway on hover and fully while typing. If the text starts right
    -- at the edge (the game's art used to reach past it), the room is added
    -- outside.
    local left = eb.GetTextInsets and eb:GetTextInsets()
    local pad = (type(left) == "number" and left < Kit.INPUT_ROOM) and (Kit.INPUT_ROOM - left) or 0
    local s = DUI.Widgets.InputLook(eb, {}, pad)
    inputOf[eb] = s
    eb:HookScript("OnEnter", s.Ease)
    eb:HookScript("OnLeave", s.Ease)
    if host then
        local focused = false
        quietHost(host)[eb] = function(gone)
            if gone then focused = false; s.Rest(); return end
            local now = eb:HasFocus() == true
            if now ~= focused then
                focused = now
                s.Ease()
            end
        end
    else
        eb:HookScript("OnEditFocusGained", s.Ease)
        eb:HookScript("OnEditFocusLost", s.Ease)
        eb:HookScript("OnHide", s.Rest)
    end
    Kit.Font(eb, nil)
    local faint = Style.INK.OFF
    if kind(eb.searchIcon) == "Texture" then eb.searchIcon:SetVertexColor(faint[1], faint[2], faint[3]) end
    if kind(eb.Instructions) == "FontString" then Kit.Font(eb.Instructions, nil, faint) end
    -- Search box clear button.
    if isTable(eb.clearButton) then Kit.Close(eb.clearButton) end
end
function Kit.InputOf(eb) return inputOf[eb] end

-- A page button (a merchant's Prev/Next): small square button with our chevron
-- and its label beside it. dir is "left" or "right". Returns the chevron.
function Kit.PageButton(btn, dir)
    if not isTable(btn) or not btn.CreateTexture or not once("page", btn) then return end
    hideButtonArt(btn)
    Kit.Strip(btn)
    look(btn)
    local c = chevron(btn, Kit.ROTATION[dir] or Kit.ROTATION.right)
    c:SetPoint("CENTER", btn, "CENTER", 0, 0)
    for _, r in ipairs({ btn:GetRegions() }) do
        if kind(r) == "FontString" then
            Kit.Font(r, Style.SIZE.small)
            Kit.Light(r)
        end
    end
    return c
end

-- A bare button for slim bars (the world map's top row): no box, just our
-- chevron, dim at rest and lit with a soft wash on hover, like the close
-- button next to it. dir is a Kit.ROTATION key, down by default.
function Kit.BareButton(btn, dir)
    if not isTable(btn) or not btn.CreateTexture or not once("bare", btn) then return end
    hideButtonArt(btn)
    Kit.Strip(btn)
    local c = chevron(btn, Kit.ROTATION[dir or "down"])
    c:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local d = Kit.DIM
    c:SetVertexColor(d[1], d[2], d[3], 1)
    Kit.HoverWash(btn)
    btn:HookScript("OnEnter", function() c:SetVertexColor(Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3], 1) end)
    btn:HookScript("OnLeave", function() c:SetVertexColor(d[1], d[2], d[3], 1) end)
    return c
end

-- The game's "filters changed" badge (UIResetButtonTemplate, a red circle with
-- a yellow X that resets filters) becomes a small accent X. The game still
-- shows and hides it.
Kit.BADGE_SIZE = 9
function Kit.ResetBadge(btn)
    if not isTable(btn) or not btn.CreateTexture or not once("badge", btn) then return end
    hideButtonArt(btn)
    local x = btn:CreateTexture(nil, "OVERLAY")
    x:SetTexture(DUI.MEDIA .. "ui-close.png")
    x:SetSize(Kit.BADGE_SIZE, Kit.BADGE_SIZE)
    x:SetPoint("CENTER", btn, "CENTER", 0, 0)
    -- Accent at rest, a third of the way to white on hover.
    local function paint(over)
        local s, t = Kit.SELECTED, over and 0.35 or 0
        x:SetVertexColor(s[1] + (1 - s[1]) * t, s[2] + (1 - s[2]) * t, s[3] + (1 - s[3]) * t, 1)
    end
    paint(false)
    btn:HookScript("OnEnter", function() paint(true) end)
    btn:HookScript("OnLeave", function() paint(false) end)
    btn:HookScript("OnShow", function() paint(false) end)
end

-- A checkbox becomes our on/off switch (same look as W.Switch): the box and tick
-- are hidden and a pill takes their place, the knob sliding over and the pill
-- taking the accent when checked. The game's clicks, sound and scripts stay.
-- SetChecked fires no event, so the switch is repainted on click, on show and
-- enable/disable, and by a light poll (Kit.CHECK_POLL) while a skinned checkbox
-- is visible. The classic checkbox sits in the middle of a bigger frame (its art
-- has a margin), the minimal one fills its frame. The pill is at most as wide as
-- the frame, centered on it.
Kit.CHECK_POLL = 0.1 -- seconds between polls of visible checkboxes
Kit.CHECK_ROOM = 4 -- px the pill is narrower than the box, leaving room for the label
Kit.CHECK_MIN = 18 -- smallest pill width
local switchOf = setmetatable({}, { __mode = "k" }) -- checkbox -> its switch look
local inSight = {} -- checkbox -> true while shown
local poller = CreateFrame("Frame")
poller:Hide()
Kit.checkPoller = poller

local function paintCheck(cb)
    local s = switchOf[cb]
    if not s then return end
    local off = (cb.IsEnabled and not cb:IsEnabled()) or nil
    local on = cb:GetChecked() and true or false
    if s.on == on and s.off == off then return end
    s.off = off
    s.SetOn(on)
end

local since = 0
poller:SetScript("OnUpdate", function(_, dt)
    since = since + dt
    if since < Kit.CHECK_POLL then return end
    since = 0
    for cb in pairs(inSight) do paintCheck(cb) end
end)

function Kit.Check(cb)
    if not isTable(cb) or not cb.CreateTexture or not once("check", cb) then return end
    hideButtonArt(cb, true)
    local w = cb:GetWidth()
    if type(w) ~= "number" or (issecretvalue and issecretvalue(w)) or w <= 0 then w = DUI.Widgets.SWITCH_W end
    local s = DUI.Widgets.SwitchLook(cb, {}, math.max(Kit.CHECK_MIN, math.min(DUI.Widgets.SWITCH_W, w - Kit.CHECK_ROOM)))
    switchOf[cb] = s
    -- A child frame that's shown and hidden along with the checkbox.
    local eye = CreateFrame("Frame", nil, cb)
    eye:SetSize(1, 1)
    eye:SetPoint("CENTER", cb, "CENTER", 0, 0)
    eye:EnableMouse(false)
    eye:SetScript("OnShow", function()
        inSight[cb] = true
        poller:Show()
        paintCheck(cb)
    end)
    eye:SetScript("OnHide", function()
        inSight[cb] = nil
        if next(inSight) == nil then poller:Hide() end
    end)
    if cb:IsVisible() then inSight[cb] = true; poller:Show() end
    cb:HookScript("PostClick", function() paintCheck(cb) end)
    if cb.IsEnabled then
        cb:HookScript("OnEnable", function() paintCheck(cb) end)
        cb:HookScript("OnDisable", function() paintCheck(cb) end)
    end
    s.off = (cb.IsEnabled and not cb:IsEnabled()) or nil
    s.SetOn(cb:GetChecked() and true or false)
    local label = cb.Label or cb.Text or cb.text
    if not isTable(label) then
        local name = cb.GetName and cb:GetName()
        label = type(name) == "string" and _G[name .. "Text"] or nil
    end
    Kit.Font(label, Style.SIZE.body)
    Kit.Light(label)
end
function Kit.SwitchOf(cb) return switchOf[cb] end

-- A small icon button (a model's zoom and rotate): art removed, icon in our text
-- color, control outline around it at pad px. file: an icon to draw for buttons
-- whose only picture is their art (a bag's sort button).
function Kit.IconButton(btn, pad, file)
    if not isTable(btn) or not btn.CreateTexture or not once("iconbutton", btn) then return end
    local icon = btn.Icon or btn.icon or btn.ActionIcon
    if file then
        Kit.Strip(btn)
        icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(file)
        Style.CropIcon(icon)
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
    end
    hideButtonArt(btn, true)
    if kind(icon) ~= "Texture" then return end
    if icon.SetDesaturated then icon:SetDesaturated(true) end
    icon:SetVertexColor(Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3])
    look(btn, Kit.Outline(icon, pad or 4, "control"))
end

-- A button whose picture is the point (loot roll dice, coin, pass): keeps the
-- picture in color, pressed art too, inset pad px inside a control box with the
-- hover trace. The game's hover glow is removed since the trace replaces it.
function Kit.ArtButton(btn, pad)
    if not isTable(btn) or not btn.CreateTexture or not once("artbutton", btn) then return end
    if btn.GetHighlightTexture then Kit.Hide(btn:GetHighlightTexture()) end
    local P = DUI.Pixel.Px(btn, pad or 3)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        local t = btn[get] and btn[get](btn)
        if kind(t) == "Texture" then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", btn, "TOPLEFT", P, -P)
            t:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -P, P)
        end
    end
    look(btn)
end

-- ---------------------------------------------------------------------
-- Rows and tabs
-- ---------------------------------------------------------------------

-- A list row (a trainer's skills): box art removed, row look instead, lighter on
-- hover and accent when selected. selected is either the game's selection
-- texture (hidden, but its shown state still tells us) or a function of the row.
-- keep: textures to leave, like its icon. Text keeps the game's colors (a
-- trainer's tell you what you can learn). Call again when the list reuses it.
Kit.ROW_HOVER = { 0.4, 0.4, 0.43 }
Kit.ROW_BORDER = Style.NEUTRAL -- visible, like the tabs' outline
local rows = setmetatable({}, { __mode = "k" }) -- row -> { shell, hover, selected }
local selectable = setmetatable({}, { __mode = "k" }) -- rows that can show a selection
Kit.ROW_SELECTED_FILL = 0.18 -- selected row's fill, in its outline color
Kit.ROW_PICK = 0.16 -- picked wash on a line row (same as Parts.PickLine)
Kit.ROW_PRESS = 0.3 -- seconds after a press during which a pick counts as the player's

-- Selected row color: the accent, or the class color when the accent is the
-- default warm gray (too close to a row's own outline to see). The class color
-- table is rebuilt only when the color changes.
local classSelected
local function rowSelectedColor()
    local g = DUI.DB.General()
    if g.accent ~= "daylight" then return Kit.SELECTED end
    local _, token = UnitClass("player")
    local r, gr, b = Style.RawClassColor(token)
    if not r then return Kit.SELECTED end
    local k = classSelected
    if not (k and k[1] == r and k[2] == gr and k[3] == b) then
        k = { r, gr, b }
        classSelected = k
    end
    return k
end

-- Hover color for a row outline, cached per color (outline colors are shared
-- tables and never changed in place).
local hoverOf = setmetatable({}, { __mode = "k" })
local function rowHover(n)
    local h = hoverOf[n]
    if not h then
        h = { Style.Lighten(n[1], n[2], n[3], Kit.HOVER_LIGHTEN) }
        hoverOf[n] = h
    end
    return h
end

-- A line row (Kit.Row with shell false) gets the accent wash when picked. It
-- only animates when the player picks: scrolling reuses rows, and a fading wash
-- would flicker across them.
local function paintLine(r, on)
    on = on and true or false
    if on then Style.PaintAccent(r.fill, Kit.ROW_PICK) end
    if on == r.on then return end
    r.on = on
    local M = DUI.Motion
    if r.pressed and GetTime() - r.pressed < Kit.ROW_PRESS then
        M.Fade(r.fill, on and 0 or 1, on and 1 or 0, M.FAST)
    else
        r.fill:SetAlpha(on and 1 or 0)
    end
end

local function paintRow(row)
    local r = rows[row]
    local border
    local sel = r.selected
    if type(sel) == "function" then sel = sel(row) else sel = isTable(sel) and sel:IsShown() end
    if r.line then return paintLine(r, sel) end
    local selColor = sel and rowSelectedColor()
    if r.fill then
        if sel then
            r.fill:SetColorTexture(selColor[1], selColor[2], selColor[3], Kit.ROW_SELECTED_FILL)
            r.fill:Show()
        else
            r.fill:Hide()
        end
    end
    if sel then
        border = selColor
    elseif r.hover then
        local n = r.normal
        border = n and rowHover(n) or Kit.ROW_HOVER
    else
        border = r.normal
    end
    Kit.Paint(r.shell, border)
end

-- over: the button that takes the mouse when the row doesn't (a loot row's item
-- button spans the row). Defaults to the row.
-- shell false: draw the row as a plain line like our own lists (no box, a hover
-- wash, accent wash when picked). Better for long lists where a box on every
-- row makes them all look the same (NeedRoll).
function Kit.RowOf(row) return rows[row] end
function Kit.Row(row, keep, selected, shell, over)
    if not isTable(row) or not row.CreateTexture then return end
    local r = rows[row]
    if not r then
        if keep == "art" then
            -- Only the button and three-piece art; icons (a +/-) stay.
            for _, key in ipairs({ "Left", "Middle", "Right", "Center", "Mid", "LeftPiece", "RightPiece", "CenterPiece" }) do
                Kit.Hide(row[key])
            end
        else
            Kit.Strip(row, keep)
        end
        hideButtonArt(row, true)
        local line = shell == false
        r = { line = line, normal = Kit.ROW_BORDER, shell = not line and (shell or Kit.Shell(row, "row")) or nil }
        over = isTable(over) and over.HookScript and over or row
        r.wash = Kit.HoverWash(over, row)
        r.fill = row:CreateTexture(nil, "BACKGROUND", nil, 7)
        if line then
            r.fill:SetColorTexture(1, 1, 1, 1)
            r.fill:SetAllPoints(row)
            r.fill:SetAlpha(0)
            r.on = false
            over:HookScript("OnMouseDown", function() r.pressed = GetTime() end)
        else
            local T = DUI.Pixel.Px(row, 2)
            r.fill:SetPoint("TOPLEFT", row, "TOPLEFT", T, -T)
            r.fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -T, T)
            r.fill:Hide()
        end
        rows[row] = r
        over:HookScript("OnEnter", function() r.hover = true; paintRow(row) end)
        over:HookScript("OnLeave", function() r.hover = false; paintRow(row) end)
    end
    if selected ~= r.selected and selected ~= nil then
        r.selected = selected
        selectable[row] = true
    end
    paintRow(row)
end

-- Selection (the game's selection art shown, a tab checked) is read at paint
-- time, never followed by hooking the game's methods. Each window repaints its
-- rows wherever the game changes it: clicks, the window or a page shown, the
-- game's own update functions and events (Kit.RepaintSoon / Kit.RepaintRow).
function Kit.RepaintRow(row)
    if rows[row] then paintRow(row) end
end

function Kit.RepaintRows()
    for row in pairs(selectable) do paintRow(row) end
end

-- Now and once more next frame, since the game often sets the selection just
-- after (page shown first, its tab checked next).
local repaintPending = false
local function repaintSoon()
    Kit.RepaintRows()
    if repaintPending or not (C_Timer and C_Timer.After) then return end
    repaintPending = true
    C_Timer.After(0, function()
        repaintPending = false
        Kit.RepaintRows()
    end)
end
Kit.RepaintSoon = repaintSoon

-- A window shows all its tabs at once, so only the first one asks.
local function repaintShown()
    if not repaintPending then repaintSoon() end
end

local function tabSelected(tab)
    if tab.GetChecked then
        local on = tab:GetChecked()
        if on ~= nil then return on == true or on == 1 end
    end
    if tab.isSelected ~= nil then return tab.isSelected == true end
    local parent = tab.GetParent and tab:GetParent()
    local sel = parent and parent.selectedTab
    return type(sel) == "number" and tab.GetID and sel == tab:GetID() or false
end

-- The tab's (hidden) selection art. Whether it's shown says if the tab is selected.
local function selectionArt(tab)
    for _, key in ipairs({ "SelectedTexture", "selectedTexture", "Selected" }) do
        local s = tab[key]
        if kind(s) == "Texture" then return s end
    end
end

-- Crops an icon inward from each side (0-0.5) and keeps it cropped when the game
-- resets its texture, atlas or coords. For icons with a frame drawn in, and
-- round portraits (0.15 fills the square). Not for icons cut from a sheet.
local crops = setmetatable({}, { __mode = "k" }) -- texture -> inset

function Kit.KeepCrop(tex, inset)
    if kind(tex) ~= "Texture" then return end
    local first = crops[tex] == nil
    crops[tex] = inset
    local guard = false
    local function apply()
        if guard then return end
        guard = true
        local i = crops[tex]
        tex:SetTexCoord(i, 1 - i, i, 1 - i)
        guard = false
    end
    apply()
    if first then
        for _, m in ipairs({ "SetTexCoord", "SetTexture", "SetAtlas" }) do
            if tex[m] then hooksecurefunc(tex, m, apply) end
        end
    end
end

-- An icon tab (down a window's side or in a row): art removed except the icon,
-- which loses its mask to become square and is cropped by crop (0-0.5). The icon
-- look goes over its edge, covering any frame drawn into it, and the selected
-- tab is outlined in the accent. The selected tint and hover wash sit inside
-- that outline (the tab frame is wider than its icon). whole: put the tab look
-- on the tab's own frame instead, for tabs flush against the window edge where
-- an outline around just the icon would float (the friends window).
function Kit.SideTab(tab, isSelected, crop, whole)
    if not isTable(tab) or not tab.CreateTexture or not once("sidetab", tab) then return end
    local name = tab.GetName and tab:GetName()
    local icon = tab.Icon or tab.icon or (type(name) == "string" and (_G[name .. "Icon"] or _G[name .. "IconTexture"]))
    if kind(icon) ~= "Texture" then return end
    if isTable(tab.Mask) and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, tab.Mask) end
    if crop then Kit.KeepCrop(icon, crop) end
    local shell = whole and Kit.Shell(tab, "tab") or Kit.Outline(icon, 0, "icon", true)
    Kit.Row(tab, { [icon] = true }, isSelected or selectionArt(tab) or tabSelected, shell)
    if not whole then
        for _, tex in ipairs({ rows[tab].fill, rows[tab].wash }) do
            if kind(tex) == "Texture" then
                tex:ClearAllPoints()
                tex:SetAllPoints(icon)
            end
        end
    end
    rows[tab].normal = Kit.TAB_BORDER
    paintRow(tab)
    -- On click, or when shown (window opening, a tab the game adds).
    tab:HookScript("OnMouseUp", repaintSoon)
    tab:HookScript("OnShow", repaintShown)
end

-- A text tab, same look as W.Tab: words only, tan at rest, light on hover,
-- accent with an underline growing in when selected, dim when disabled. Works
-- with both old and new tab functions. A tab without words (an icon) keeps a
-- box with the line along its bottom.
local tabs = setmetatable({}, { __mode = "k" }) -- tab -> its look
Kit.TAB_UNDER = 4 -- gap between the text and the underline

local function paintTab(tab, selected, animate)
    local t = tabs[tab]
    if not t then return end
    selected = selected == true
    if t.Pick then
        -- The game swaps the font object as the tab is enabled and disabled.
        Style.DressText(t.text, Style.SIZE.body)
        t.off = (not selected and tab.IsEnabled and not tab:IsEnabled()) or nil
        t.Pick(selected, animate)
        return
    end
    t.picked = selected or nil
    if selected then
        local c = Kit.SELECTED
        t.line:SetColorTexture(c[1], c[2], c[3], 1)
        t.line:Show()
    else
        t.line:Hide()
    end
end

-- Only a pick by the player (the tab under the mouse) animates its underline.
local function picked(tab, on)
    paintTab(tab, on, on and tab.IsMouseOver and tab:IsMouseOver() == true)
end

local tabsHooked = false
local function hookTabs()
    if tabsHooked then return end
    tabsHooked = true
    if type(PanelTemplates_SelectTab) == "function" then
        hooksecurefunc("PanelTemplates_SelectTab", function(tab) picked(tab, true) end)
    end
    if type(PanelTemplates_DeselectTab) == "function" then
        hooksecurefunc("PanelTemplates_DeselectTab", function(tab) picked(tab, false) end)
    end
end

local TAB_ART = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
                  "LeftHighlight", "MiddleHighlight", "RightHighlight", "LeftDisabled", "MiddleDisabled", "RightDisabled",
                  "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" }

-- isSelected(tab): optional, for tabs that track selection their own way
-- (Ace3's tab.selected).
function Kit.Tab(tab, isSelected)
    if not isTable(tab) or not tab.CreateTexture or not once("tab", tab) then return end
    hookTabs()
    hideButtonArt(tab)
    -- Only the tab's own art; anything else on it (an icon) stays.
    local name = tab.GetName and tab:GetName()
    for _, key in ipairs(TAB_ART) do
        Kit.Hide(tab[key])
        if type(name) == "string" then Kit.Hide(_G[name .. key]) end
    end
    local label = tab.Text or (tab.GetFontString and tab:GetFontString())
        or (type(name) == "string" and _G[name .. "Text"]) or nil
    local icon = isTable(tab.Icon) or isTable(tab.icon)
    if kind(label) == "FontString" and not icon then
        local t = DUI.Widgets.TabLook(tab, {}, label, { under = Kit.TAB_UNDER })
        tabs[tab] = t
        tab:HookScript("OnEnter", function() t.Paint(true) end)
        tab:HookScript("OnLeave", function() t.Paint(false) end)
    else
        Kit.Shell(tab, "tab")
        local line = tab:CreateTexture(nil, "OVERLAY")
        line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 3, 3)
        line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, 3)
        line:SetHeight(2)
        line:Hide()
        tabs[tab] = { line = line }
        Kit.Font(label, Style.SIZE.body, Kit.TEXT)
    end
    -- Newer tab systems (TabSystemButtonArtMixin:SetTabSelected) set
    -- tab.isSelected and disable the selected tab, so OnEnable/OnDisable tell
    -- us when it changes. Old tabs (PanelTemplates_EnableTab) do the same.
    -- No hooks on the game's methods.
    local function selectedNow()
        if isSelected then return isSelected(tab) == true end
        local selected = tab.isSelected
        if selected == nil and tab.GetID and tab.GetParent then
            local parent = tab:GetParent()
            local sel = parent and parent.selectedTab
            if type(sel) == "number" then selected = sel == tab:GetID() end
        end
        if selected == nil then selected = tabs[tab].picked end
        return selected == true
    end
    local function repaint() picked(tab, selectedNow()) end
    if kind(tab) == "Button" or kind(tab) == "CheckButton" then
        tab:HookScript("OnEnable", repaint)
        tab:HookScript("OnDisable", repaint)
        if type(tab.SetTabSelected) == "function" then
            tab:HookScript("OnShow", repaint)
            tab:HookScript("OnClick", repaint)
        end
    end
    paintTab(tab, selectedNow())
end
function Kit.TabOf(tab) return tabs[tab] end

-- ---------------------------------------------------------------------
-- Scroll bars, bars, items
-- ---------------------------------------------------------------------

-- Scroll bars like W.Scroll: a faint track line and a pill thumb that brightens
-- on hover. Arrows are hidden but still clickable. Handles old (named) and new
-- (Track/Thumb) bars.
local function tint(tex, c) tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end

-- Turns an old bar's thumb texture into our pill. Call again for addons that
-- reset their thumb art on refresh (RestedXP).
function Kit.ScrollThumb(bar, thumb)
    if not isTable(bar) then return end
    local name = bar.GetName and bar:GetName()
    thumb = thumb or bar.ThumbTexture or (type(name) == "string" and _G[name .. "ThumbTexture"])
        or (bar.GetThumbTexture and bar:GetThumbTexture())
    if kind(thumb) ~= "Texture" then return end
    local S = Kit.SCROLL
    thumb:SetTexture(DUI.MEDIA .. "ui-pill.png")
    thumb:SetTexCoord(0, 1, 0, 1)
    thumb:SetWidth(S.width)
    thumb:SetAlpha(1)
    tint(thumb, S.thumb)
end

function Kit.ScrollBar(bar)
    if not isTable(bar) or not bar.GetRegions or not once("scroll", bar) then return end
    local S = Kit.SCROLL
    local name = bar.GetName and bar:GetName()
    name = type(name) == "string" and name or nil
    local track = isTable(bar.Track) and bar.Track or nil
    local thumb = (track and track.Thumb) or bar.Thumb or bar.ThumbTexture or (name and _G[name .. "ThumbTexture"])
    Kit.Strip(bar)
    if track then Kit.Strip(track) end
    local host = track or bar
    local W = DUI.Widgets
    local line = (W and W.Round) and W.Round(host, "BACKGROUND") or host:CreateTexture(nil, "BACKGROUND")
    if not (W and W.Round) then line:SetColorTexture(1, 1, 1, 1) end
    line:SetWidth(S.width)
    line:SetPoint("TOP", host, "TOP", 0, 0)
    line:SetPoint("BOTTOM", host, "BOTTOM", 0, 0)
    tint(line, S.track)
    if kind(thumb) == "Texture" then
        -- Old bars: the thumb is a texture on the bar itself.
        Kit.ScrollThumb(bar, thumb)
    elseif isTable(thumb) and thumb.CreateTexture then
        Kit.Strip(thumb)
        hideButtonArt(thumb)
        for _, key in ipairs({ "Begin", "Middle", "End" }) do Kit.Hide(thumb[key]) end
        local pill = thumb:CreateTexture(nil, "ARTWORK")
        pill:SetTexture(DUI.MEDIA .. "ui-pill.png")
        pill:SetWidth(S.width)
        pill:SetPoint("TOP", thumb, "TOP", 0, 0)
        pill:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
        tint(pill, S.thumb)
        thumb:HookScript("OnEnter", function() tint(pill, S.thumbHover) end)
        thumb:HookScript("OnLeave", function() tint(pill, S.thumb) end)
    end
    for _, key in ipairs({ "Back", "Forward", "ScrollUpButton", "ScrollDownButton", "UpButton", "DownButton" }) do
        local b = bar[key] or (name and _G[name .. key])
        if isTable(b) and b.GetRegions then
            hideButtonArt(b)
            Kit.Strip(b)
            for _, k in ipairs({ "Texture", "Overlay" }) do Kit.Hide(b[k]) end
        end
    end
end

-- A texture-drawn progress bar (reputation): art removed, the fill in our bar
-- texture keeping the game's color, and the bar look around the track. The game
-- still sizes bar.Fill. It also resets the fill art when refilling the row
-- (SetFillTextureByColorType from Initialize), so ours goes back on via
-- Kit.OnRefill and on every pass over the list.
function Kit.ProgressBar(bar)
    if not isTable(bar) or not bar.CreateTexture then return end
    local fill = bar.Fill
    if kind(fill) ~= "Texture" then return end
    if not once("progress", bar) then
        Style.TrackBar(fill)
        return
    end
    Kit.Strip(bar, { [fill] = true })
    if isTable(bar.Mask) and fill.RemoveMaskTexture then pcall(fill.RemoveMaskTexture, fill, bar.Mask) end
    Style.TrackBar(fill)
    Kit.OnRefill(bar, function() Style.TrackBar(fill) end)
    -- Track: the bar's width, the fill's height.
    local holder = CreateFrame("Frame", nil, bar)
    holder:SetPoint("LEFT", bar, "LEFT", -2, 0)
    holder:SetPoint("RIGHT", bar, "RIGHT", 2, 0)
    local h = fill:GetHeight()
    holder:SetHeight(((type(h) == "number" and h > 0) and h or 15) + 4)
    holder:SetFrameLevel(bar:GetFrameLevel())
    holder:EnableMouse(false)
    Kit.Shell(holder, "bar")
    Kit.Font(bar.Text, Style.SIZE.small)
end

-- A status bar: our fill texture (the game's color, or color), frame art
-- stripped, bar look.
function Kit.StatusBar(bar, color)
    if kind(bar) ~= "StatusBar" or not once("statusbar", bar) then return end
    local fill = bar:GetStatusBarTexture()
    Kit.Strip(bar, isTable(fill) and { [fill] = true } or nil)
    bar:SetStatusBarTexture(Style.BarFile())
    Style.TrackBar(bar)
    fill = bar:GetStatusBarTexture()
    if isTable(fill) then fill:SetAlpha(1) end
    if color then bar:SetStatusBarColor(color[1], color[2], color[3]) end
    Kit.Shell(bar, "bar")
    for _, key in ipairs({ "Text", "text", "Label", "rankText" }) do
        if kind(bar[key]) == "FontString" then Kit.Font(bar[key]) end
    end
end

-- Every item gets an outline in its quality color, white included. The game's
-- IconBorder is hidden and ours follows it. Empty slots get a dim outline so
-- they still read as slots.
Kit.EMPTY_ITEM_BORDER = { 0.28, 0.28, 0.3 }
local slots = setmetatable({}, { __mode = "k" }) -- item button -> its shell

-- Recolors an item's outline from the game's border. Call it after the game
-- updates the button when nothing there is hooked.
local function iconOf(btn)
    local name = btn.GetName and btn:GetName()
    return btn.icon or btn.Icon or (type(name) == "string" and _G[name .. "IconTexture"])
end

function Kit.SlotQuality(btn)
    local s = slots[btn]
    if not s then return end
    local border = btn.IconBorder
    local color = Kit.EMPTY_ITEM_BORDER
    if kind(border) == "Texture" and border:IsShown() then
        local r, g, b = border:GetVertexColor()
        if type(r) == "number" and not (issecretvalue and issecretvalue(r)) then
            -- The game updates a button 3-4 times per pass, so skip when the
            -- color hasn't changed (and allocate nothing).
            local cur = s.lite and s.opts.borderColor
            if cur and cur[1] == r and cur[2] == g and cur[3] == b and cur[4] == nil then return end
            color = { r, g, b }
        end
    end
    Kit.Paint(s, color)
end

-- Wide item buttons (quest rewards: icon plus name panel) are outlined around
-- the icon, square ones around themselves.
local function wide(btn)
    local w, h = btn:GetWidth(), btn:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or h <= 0 then return false end
    if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return false end
    return w > h * 1.6
end

-- The game sets the item border through these globals (ItemButtonTemplate.lua:
-- SetItemButtonQuality calls the other two, and so does the mixin method). We
-- post-hook them and act only on our buttons. Never hook the border texture
-- itself: it sits on secure item buttons. Buttons whose border the game sets by
-- hand (character slots, loot rolls) are recolored by their own skin.
local followingBorders = false
local function followBorders()
    if followingBorders then return end
    followingBorders = true
    local function repaint(btn) if slots[btn] then Kit.SlotQuality(btn) end end
    for _, fn in ipairs({ "SetItemButtonBorder", "SetItemButtonBorderVertexColor", "SetItemButtonQuality" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, repaint) end
    end
end

local function qualityOutline(btn)
    local icon = iconOf(btn)
    local target = (kind(icon) == "Texture" and wide(btn)) and icon or btn
    -- Outside the item by the border's own width, so all of it shows.
    local pad = DUI.Pixel.Px(btn, Kit.LOOK.outline.borderPx)
    slots[btn] = Kit.Outline(target, pad, "outline")
    Kit.Hide(btn.IconBorder)
    followBorders()
    Kit.SlotQuality(btn)
end

-- An item button (merchant goods, mail attachments, bag slots): icon cropped on
-- a black square, slot art removed (including a bag slot's background, which
-- the game re-shows), quality outline.
function Kit.Item(btn)
    if not isTable(btn) or not btn.CreateTexture or slots[btn] or not once("item", btn) then return end
    local icon = iconOf(btn)
    if btn.GetNormalTexture then Kit.Hide(btn:GetNormalTexture()) end
    if kind(btn.ItemSlotBackground) == "Texture" then Kit.Erase(btn.ItemSlotBackground) end
    local back = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetColorTexture(0, 0, 0, 1)
    if kind(icon) == "Texture" and wide(btn) then back:SetAllPoints(icon) else back:SetAllPoints(btn) end
    if kind(icon) == "Texture" then Style.CropIcon(icon) end
    for _, key in ipairs({ "NameFrame", "Border" }) do Kit.Hide(btn[key]) end
    -- The quest item border is drawn at the default item size, so make it
    -- follow the button's actual size.
    local quest = btn.IconQuestTexture
    if kind(quest) == "Texture" and not wide(btn) then
        quest:ClearAllPoints()
        quest:SetAllPoints(btn)
    end
    local name = btn.GetName and btn:GetName()
    if type(name) == "string" then Kit.Hide(_G[name .. "NameFrame"]) end
    qualityOutline(btn)
end

-- Small item icons in plain list cells (the auction house name column: Icon plus
-- a thick gray IconBorder atlas with no quality color). The icon is cropped, the
-- square erased for good (the game resets its alpha on sold items), and the
-- character window's item edge (DUI.Char.Slots.Edge) drawn around it, thinner
-- for the small size, colored from rowData.itemKey. Runs on every row the walk
-- reaches, skinned or not, so refilled rows get recolored.
Kit.ROW_ICON_EDGE = 2
local rowEdges = setmetatable({}, { __mode = "k" }) -- cell -> its edge
local function rowIconColor(cell)
    local data = cell.rowData
    local ah = C_AuctionHouse
    if not isTable(data) or not isTable(data.itemKey) or not (ah and ah.GetItemKeyInfo) then return nil end
    local ok, info = pcall(ah.GetItemKeyInfo, data.itemKey)
    if not ok or not isTable(info) or type(info.quality) ~= "number" then return nil end
    local getColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if type(getColor) ~= "function" then return nil end
    local r, g, b = getColor(info.quality)
    if type(r) ~= "number" then return nil end
    return r, g, b
end

function Kit.RowIcons(row)
    if not isTable(row) or not row.GetChildren then return end
    for _, cell in ipairs({ row:GetChildren() }) do
        if kind(cell) == "Frame" and kind(cell.Icon) == "Texture" and kind(cell.IconBorder) == "Texture" then
            local edge = rowEdges[cell]
            local slots = DUI.Char and DUI.Char.Slots
            if not edge and slots and slots.Edge and once("rowicon", cell) then
                Style.CropIcon(cell.Icon)
                Kit.Erase(cell.IconBorder)
                local back = cell:CreateTexture(nil, "BACKGROUND", nil, -8)
                back:SetAllPoints(cell.Icon)
                back:SetColorTexture(0, 0, 0, 1)
                edge = slots.Edge(cell.Icon, Kit.ROW_ICON_EDGE)
                rowEdges[cell] = edge
            end
            if edge then
                local r, g, b = rowIconColor(cell)
                if not r then r, g, b = unpack(slots.EMPTY_EDGE) end
                edge:SetVertexColor(r, g, b)
                -- Rows with no item hide the icon; sold ones dim it.
                edge.frame:SetShown(cell.Icon:IsShown())
                edge.frame:SetAlpha(cell.Icon:GetAlpha())
            end
        end
    end
end

-- An equipment slot: frame art removed, icon cropped on a dark square, quality
-- outline.
function Kit.Slot(slot)
    if not isTable(slot) or not slot.CreateTexture or not once("slot", slot) then return end
    local name = slot.GetName and slot:GetName()
    Kit.Strip(slot.BorderFrame)
    if isTable(slot.BorderFrame) and slot.BorderFrame.Hide then slot.BorderFrame:Hide() end
    -- The game recolors (and re-shows) the slot art on every update, so it's
    -- hidden outright rather than faded.
    local normal = (type(name) == "string" and _G[name .. "NormalTexture"]) or (slot.GetNormalTexture and slot:GetNormalTexture())
    if isTable(normal) and normal.Hide then normal:Hide() end
    for _, r in ipairs({ slot:GetRegions() }) do
        -- Slots built without the frame child have their ring as an atlas.
        local atlas = kind(r) == "Texture" and r.GetAtlas and r:GetAtlas()
        if type(atlas) == "string" and string.find(atlas, "GearSlot", 1, true) then r:SetAlpha(0) end
    end
    local icon = iconOf(slot)
    if kind(icon) == "Texture" then Style.CropIcon(icon) end
    -- Some slots hide their border by hand on show (the ammo slot), so recolor
    -- after the game's OnShow.
    if slot.HookScript then slot:HookScript("OnShow", function(self) Kit.SlotQuality(self) end) end
    -- Already outlined by Kit.Auto; the slot art still needs removing.
    if slots[slot] then return end
    local back = slot:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetColorTexture(0, 0, 0, 0.6)
    back:SetAllPoints(slot)
    qualityOutline(slot)
end

-- ---------------------------------------------------------------------
-- Lists and panes
-- ---------------------------------------------------------------------

-- Styles a scrolling list's rows as they're created and reused: fn(row) runs
-- now for each row, after every list update, and once more next frame (the game
-- fills some rows after its update). The first fn given is the default; others
-- can be added under their own key (a skin's rows after the template's), and
-- reusing a key replaces it. Driven by the list's own callbacks (ScrollBox.lua:
-- OnUpdate after each update, OnInitializedFrame per row), never by hooking its
-- methods. The game invokes those via securecallfunction, so nothing of ours
-- runs inside its update. A freshly filled row is relit right away (Kit.RelightIn
-- to this depth), since its text was colored for parchment.
Kit.ROW_LIGHT_DEPTH = 4
local rowJobs = setmetatable({}, { __mode = "k" }) -- box -> { order = { keys }, fns = { key -> fn } }

local function listEvent(name)
    local mixin = _G.ScrollBoxListMixin
    return isTable(mixin) and isTable(mixin.Event) and mixin.Event[name] or nil
end

function Kit.EachRow(box, fn, key)
    if not isTable(box) or not box.ForEachFrame then return end
    local function each(f)
        local t0 = Kit.Profiling and debugprofilestop()
        pcall(box.ForEachFrame, box, function(row) DUI.SafeCall(f, row) end)
        if t0 then Kit.Spent("rows", debugprofilestop() - t0) end
    end
    each(fn)
    local jobs = rowJobs[box]
    if not jobs then
        jobs = { order = {}, fns = {} }
        rowJobs[box] = jobs
        key = key or "first"
        local onUpdate, onInit = listEvent("OnUpdate"), listEvent("OnInitializedFrame")
        if type(box.RegisterCallback) == "function" and onUpdate then
            -- Lists update many times while a window opens, so rows are
            -- processed once, next frame.
            local pending = false
            box:RegisterCallback(onUpdate, function()
                if pending or not (C_Timer and C_Timer.After) then return end
                pending = true
                C_Timer.After(0, function()
                    pending = false
                    for _, k in ipairs(jobs.order) do each(jobs.fns[k]) end
                end)
            end, jobs)
            if onInit then
                box:RegisterCallback(onInit, function(_, row) Kit.RelightIn(row, Kit.ROW_LIGHT_DEPTH) end, jobs)
            end
        end
    end
    if key then
        if not jobs.fns[key] then jobs.order[#jobs.order + 1] = key end
        jobs.fns[key] = fn
    end
end

-- A row in the character window's lists (reputation, skills, statistics...):
-- headers get the row look with their +/- recolored, entries a flat highlight
-- (the game still sets its color and strength), bars our bar look, and our font.
local highlit = setmetatable({}, { __mode = "k" })

function Kit.ListRow(row)
    if not isTable(row) or not row.CreateTexture then return end
    local content = row.Content
    if isTable(content) and content.GetChildren then
        local hl = content.BackgroundHighlight
        if isTable(hl) and not highlit[hl] and type(hl.TextureRegions) == "table" then
            highlit[hl] = true
            for _, r in ipairs(hl.TextureRegions) do r:SetColorTexture(1, 1, 1, 1) end
        end
        for _, child in ipairs({ content:GetChildren() }) do
            if kind(child.Fill) == "Texture" then Kit.ProgressBar(child) end
        end
        Kit.Font(content.Name, Style.SIZE.body)
        Kit.Font(content.Value, Style.SIZE.body)
        Kit.Font(content.Count, Style.SIZE.body)
        Kit.CollapseButton(row.ToggleCollapseButton)
    elseif kind(row.StateIcon) == "Texture" then
        Kit.Row(row, { [row.StateIcon] = true })
        if row.StateIcon.SetDesaturated then row.StateIcon:SetDesaturated(true) end
        row.StateIcon:SetVertexColor(Kit.TEXT[1], Kit.TEXT[2], Kit.TEXT[3])
        Kit.Font(row.Name, Style.SIZE.body)
    end
end

-- The character window's detail pane next to a list: art removed, title and
-- subtitle in our font, the rest via Kit.Auto. skip: parts to leave as they are.
function Kit.SidePane(pane, skip)
    if not isTable(pane) or not pane.GetRegions then return end
    Kit.Strip(pane)
    Kit.Hide(pane.Divider)
    Kit.Font(pane.Title, Style.SIZE.head)
    Kit.Light(pane.Title)
    Kit.Font(pane.Subtitle, Style.SIZE.small)
    Kit.Auto(pane, { skip = skip })
end

-- ---------------------------------------------------------------------
-- Kit.Auto: skins every standard part of a window by its shape
-- ---------------------------------------------------------------------

Kit.AUTO_DEPTH = 10

local function threePart(f)
    if kind(f.Left) == "Texture" and kind(f.Right) == "Texture"
        and (kind(f.Middle) == "Texture" or kind(f.Center) == "Texture" or kind(f.Mid) == "Texture") then
        return true
    end
    local name = f.GetName and f:GetName()
    return type(name) == "string" and kind(_G[name .. "Left"]) == "Texture" and kind(_G[name .. "Right"]) == "Texture"
        and (kind(_G[name .. "Middle"]) == "Texture" or kind(_G[name .. "Mid"]) == "Texture")
end

-- Whether a button shows an icon (keyed or named). Never true for checkboxes
-- or text buttons.
local function hasIcon(f)
    if isTable(f.Icon) or isTable(f.icon) or isTable(f.IconTexture) then return true end
    local name = f.GetName and f:GetName()
    return type(name) == "string" and (isTable(_G[name .. "IconTexture"]) or isTable(_G[name .. "Icon"]))
end

-- A button with a label and a single art texture (a dialog's "Save"): wider
-- than tall, no icon.
local function textButton(f)
    if not f.GetFontString or not f.GetNormalTexture then return false end
    if hasIcon(f) then return false end
    local fs = f:GetFontString()
    local tex = f:GetNormalTexture()
    if kind(fs) ~= "FontString" or kind(tex) ~= "Texture" then return false end
    local w, h = f:GetWidth(), f:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then return false end
    if h <= 0 or w < h * 2 then return false end
    -- The texture has to be the button's art (full width), not an icon next
    -- to the label (a coin by an amount).
    local tw = tex:GetWidth()
    if type(tw) == "number" and not (issecretvalue and issecretvalue(tw)) and tw > 0 and tw < w * 0.6 then return false end
    return true
end

local function small(f)
    local w = f.GetWidth and f:GetWidth()
    return type(w) ~= "number" or (issecretvalue and issecretvalue(w)) or w <= 40
end

-- A frame's children keyed by their names on the parent. Building this walks
-- every field (game frames carry dozens of methods), so it's cached until the
-- parent's children change.
local keyCache = setmetatable({}, { __mode = "k" }) -- parent -> { n, keys }
local function keysOf(parent, n)
    n = n or select("#", parent:GetChildren())
    local c = keyCache[parent]
    if c and c.n == n then return c.keys end
    local keys = {}
    for k, v in pairs(parent) do
        if type(k) == "string" and isTable(v) and v.GetObjectType then keys[v] = k end
    end
    keyCache[parent] = { n = n, keys = keys }
    return keys
end

-- Parts already dressed (or skipped on purpose) aren't visited again, nor their
-- contents. Plain container frames aren't parts: they're walked through again
-- but not re-checked.
local handled = setmetatable({}, { __mode = "k" })
local checked = setmetatable({}, { __mode = "k" })
local pageHooked = setmetatable({}, { __mode = "k" })
Kit.PAGE_DEPTH = 4 -- how deep a window's pages are watched for being shown

-- Whether a check button's art is a checkbox rather than a favorite star or
-- other toggle. Uses the atlas when it has one.
local function checkboxArt(f)
    local tex = f.GetNormalTexture and f:GetNormalTexture()
    local atlas = kind(tex) == "Texture" and tex.GetAtlas and tex:GetAtlas()
    if type(atlas) ~= "string" or atlas == "" then return true end
    return string.find(string.lower(atlas), "check", 1, true) ~= nil
end

-- Handles one part. Returns true when it was a control (skinned, not descended
-- into, or skipped on purpose). opts.lines: draw this window's list rows as lines.
local function lineShell(opts)
    if opts.lines then return false end
end

local function part(f, key, opts, isRow)
    local t = kind(f)
    -- controlsOnly: for windows whose parts are too custom for the rest
    -- (professions). Only close buttons, scroll bars, dropdowns and edit boxes.
    if opts.controlsOnly then
        local name = f.GetName and f:GetName()
        name = type(name) == "string" and name or ""
        if (key == "CloseButton" or key == "ClosePanelButton" or string.find(name, "CloseButton$")) and not threePart(f) then
            Kit.Close(f); return true
        end
        if isTable(f.Track) and (isTable(f.Back) or isTable(f.Forward)) then Kit.ScrollBar(f); return true end
        local dropKey = type(key) == "string" and (string.find(key, "Dropdown", 1, true) or string.find(key, "DropDown", 1, true))
        if t == "DropdownButton" or (t == "Button" and dropKey) then Kit.Dropdown(f); return true end
        if t == "EditBox" then
            if threePart(f) or isTable(f.searchIcon) then Kit.EditBox(f) end
            return true
        end
        return false
    end
    -- Money frames (gold, silver, copper): left as the game draws them.
    if key == "GoldButton" or key == "SilverButton" or key == "CopperButton"
        or isTable(f.GoldButton) or isTable(f.CopperButton) then
        return true
    end
    -- Bars with their own frame, flare or animated fill (a profession's skill
    -- bar) are left entirely alone.
    if kind(f.Fill) == "Texture" and isTable(f.Mask) and (isTable(f.Border) or isTable(f.Flare)) then
        return true
    end
    local name = f.GetName and f:GetName()
    name = type(name) == "string" and name or ""
    -- A three-piece text button named like a close button (the guild log's
    -- "Close") is a button, not an X.
    if (key == "CloseButton" or key == "ClosePanelButton" or string.find(name, "CloseButton$")) and not threePart(f) then
        Kit.Close(f); return true
    end
    if (isTable(f.Track) and (isTable(f.Back) or isTable(f.Forward)))
        or ((t == "Slider" or t == "EventFrame" or t == "Frame") and (isTable(f.ScrollUpButton) or kind(_G[name .. "ScrollUpButton"]) == "Button")) then
        Kit.ScrollBar(f); return true
    end
    if (t == "Button" or t == "CheckButton" or t == "DropdownButton") and (kind(f.LeftActive) == "Texture" or kind(f.MiddleActive) == "Texture") then
        Kit.Tab(f); return true
    end
    -- A list header with a +/- (the group finder's "Groups") is a row; the
    -- +/- stays.
    if isRow and (kind(f.CollapseIcon) == "Texture" or kind(f.ExpandIcon) == "Texture") then
        local keep = {}
        if kind(f.CollapseIcon) == "Texture" then keep[f.CollapseIcon] = true end
        if kind(f.ExpandIcon) == "Texture" then keep[f.ExpandIcon] = true end
        Kit.Row(f, keep, nil, lineShell(opts))
        return true
    end
    if (t == "Button" or t == "DropdownButton") and threePart(f) then
        -- Inside a list, a three-piece header is a row, not a button.
        if isRow then Kit.Row(f, "art", nil, lineShell(opts)) else Kit.Button(f) end
        return true
    end
    if key == "DecrementButton" or key == "DecrementAllButton" then Kit.PageButton(f, "left"); return true end
    if key == "IncrementButton" or key == "IncrementAllButton" then Kit.PageButton(f, "right"); return true end
    if key == "MaximizeButton" then Kit.PageButton(f, "up"); return true end
    if key == "MinimizeButton" then Kit.PageButton(f, "down"); return true end
    local dropKey = type(key) == "string" and (string.find(key, "Dropdown", 1, true) or string.find(key, "DropDown", 1, true))
    if t == "DropdownButton" or (t == "Button" and dropKey)
        or (t == "Button" and kind(f.Arrow) == "Texture" and isTable(f.Text) and kind(f.Background) == "Texture") then
        Kit.Dropdown(f); return true
    end
    if t == "EditBox" then
        if threePart(f) or isTable(f.searchIcon) then Kit.EditBox(f) end
        return true
    end
    if key == "PrevPageButton" or key == "PrevPage" then Kit.PageButton(f, "left"); return true end
    if key == "NextPageButton" or key == "NextPage" then Kit.PageButton(f, "right"); return true end
    if kind(f.IconBorder) == "Texture" and kind(iconOf(f)) == "Texture" then
        if not (done.rowicon and done.rowicon[f]) then Kit.Item(f) end
        return true
    end
    if t == "CheckButton" and not hasIcon(f) and small(f) and f.GetCheckedTexture and checkboxArt(f) then
        Kit.Check(f); return true
    end
    if key == "ToggleCollapseButton" then Kit.CollapseButton(f); return true end
    -- A small square button with an icon in its own framed art (search,
    -- refresh) gets the icon button look. One without art of its own (a red
    -- "unlearn" X) keeps its colors.
    if t == "Button" and kind(f.Icon) == "Texture" and f.GetNormalTexture then
        local normal = f:GetNormalTexture()
        local w, h = f:GetWidth(), f:GetHeight()
        if kind(normal) == "Texture" and normal ~= f.Icon and type(w) == "number" and type(h) == "number"
            and not (issecretvalue and (issecretvalue(w) or issecretvalue(h)))
            and w > 0 and w <= 44 and math.abs(w - h) <= 4 then
            Kit.IconButton(f); return true
        end
    end
    if t == "Button" and textButton(f) then Kit.Button(f); return true end
    if kind(f.Fill) == "Texture" and isTable(f.Mask) then Kit.ProgressBar(f); return true end
    if t == "StatusBar" and opts.bars then Kit.StatusBar(f); return true end
    return false
end

-- Skins every standard part under root: close buttons, scroll bars, dropdowns,
-- edit and search boxes, page buttons, tabs, buttons, checkboxes, item buttons,
-- progress and status bars. Hides NineSlice frame art along the way, darkens
-- insets, and does the same for the rows of every scrolling list it finds as
-- they're created. Safe to run again; each part is done once.
-- opts:
--   skip         set of frames to leave alone, including their children
--   bars         also skin status bars (off by default; many windows draw their own)
--   rows         false to leave list rows alone
--   controlsOnly only close buttons, scroll bars, dropdowns and edit boxes
--   shownOnly    only visit shown frames (repeat passes)
--   onPage       called when one of the window's pages or panels is shown
--   each         called on every non-control frame visited, to dress an
--                addon's own pieces in the same walk
--   depth        max depth, for windows deeper than Kit.AUTO_DEPTH
--   lines        draw list rows as lines rather than boxes
-- Big windows (professions: thousands of frames) are walked a few hundred frames
-- per frame so opening them doesn't stall; small ones finish at once. Walks
-- pause in combat and resume after.
Kit.AUTO_BUDGET = 300 -- frames visited per rendered frame
local walking = setmetatable({}, { __mode = "k" }) -- root -> its walk, while running
local walks = {}
local walker = CreateFrame("Frame")
walker:Hide()
walker:SetScript("OnUpdate", function(self)
    if InCombatLockdown and InCombatLockdown() then return end
    for i = #walks, 1, -1 do
        local w = walks[i]
        local t0 = Kit.Profiling and debugprofilestop()
        local ok, err = coroutine.resume(w.co)
        if t0 then Kit.Spent("walk", debugprofilestop() - t0) end
        if not ok then
            geterrorhandler()(err)
            walking[w.root] = nil
            table.remove(walks, i)
        elseif coroutine.status(w.co) == "dead" then
            table.remove(walks, i)
        end
    end
    if #walks == 0 then self:Hide() end
end)
Kit.walker = walker

function Kit.Auto(root, opts)
    if not isTable(root) or not root.GetChildren or walking[root] then return end
    opts = opts or {}
    local skip = opts.skip or {}
    local co
    local count = 0
    -- canYield is false inside list rows: the list calls us from the game's own
    -- code, and a walk can't pause across that.
    local function visit(f, depth, key, isRoot, isRow, canYield)
        -- Rows skinned as a whole aren't descended into; their icon cells first.
        if isRow then Kit.RowIcons(f) end
        if not isTable(f) or skip[f] or handled[f] then return end
        if f.IsForbidden and f:IsForbidden() then return end
        if opts.shownOnly and not isRoot and f.IsShown and not f:IsShown() then return end
        if canYield then
            count = count + 1
            if count >= Kit.AUTO_BUDGET and coroutine.running() == co then
                count = 0
                coroutine.yield()
            end
        end
        if not isRoot and not checked[f] then
            if part(f, key, opts, isRow) then
                handled[f] = true
                return
            end
            checked[f] = true
        end
        -- List rows aren't pages: a row shown on every scroll step would
        -- trigger a full pass over the window.
        if opts.onPage and canYield and not isRow and not isRoot and depth <= Kit.PAGE_DEPTH and not pageHooked[f] and f.HookScript
            and select("#", f:GetChildren()) > 0 then
            pageHooked[f] = true
            f:HookScript("OnShow", opts.onPage)
        end
        if isTable(f.NineSlice) then Kit.Hide(f.NineSlice) end
        Kit.InkGameText(f)
        if not isRoot and (key == "Inset" or key == "InsetFrame") then Kit.Inset(f) end
        if opts.each then opts.each(f) end
        if opts.rows ~= false and f.ForEachFrame and isTable(f.ScrollTarget) then
            Kit.EachRow(f, function(row) visit(row, depth + 1, nil, false, true, false) end)
        end
        if depth >= (opts.depth or Kit.AUTO_DEPTH) or not f.GetChildren then return end
        if f.GetNumChildren and f:GetNumChildren() == 0 then return end
        local children = { f:GetChildren() }
        if #children == 0 then return end
        local keys = keysOf(f, #children)
        for _, c in ipairs(children) do
            if not (f.ScrollTarget == c) then visit(c, depth + 1, keys[c], false, false, canYield) end
        end
    end
    co = coroutine.create(function()
        visit(root, 0, nil, true, false, true)
        walking[root] = nil
    end)
    walking[root] = co
    local t0 = Kit.Profiling and debugprofilestop()
    local ok, err = coroutine.resume(co)
    if t0 then Kit.Spent("walk", debugprofilestop() - t0) end
    if not ok then
        walking[root] = nil
        geterrorhandler()(err)
    elseif coroutine.status(co) ~= "dead" then
        walks[#walks + 1] = { co = co, root = root }
        walker:Show()
    end
end

-- Whether a walk over this window is still in progress.
function Kit.Walking(root) return walking[root] ~= nil end

-- A fingerprint of what's shown in a window (frames, children, text, as deep as
-- Kit.Auto goes). Same number means nothing new to dress. Counts only: reads no
-- text and builds no tables for leaf frames.
local function shapeOf(f, depth, h)
    if f.IsForbidden and f:IsForbidden() then return h end
    if depth > 0 and f.IsShown and not f:IsShown() then return h end
    local nr = f.GetNumRegions and f:GetNumRegions() or 0
    local nc = f.GetNumChildren and f:GetNumChildren() or 0
    h = (h * 31 + nr * 7 + nc + 1) % 2147483647
    if nc == 0 or depth >= Kit.AUTO_DEPTH then return h end
    for _, c in ipairs({ f:GetChildren() }) do h = shapeOf(c, depth + 1, h) end
    return h
end
function Kit.Shape(root)
    if not isTable(root) or not root.GetChildren then return nil end
    return shapeOf(root, 0, 0)
end

-- ---------------------------------------------------------------------

-- The border the Kit drew for a control, row, tab or slot (on the frame or on
-- an outline around it).
function Kit.ShellOf(obj)
    return slots[obj] or (rows[obj] and rows[obj].shell) or (looks[obj] and looks[obj].shell)
        or liteOf[obj] or Style.GetShell(obj)
end

-- The core has already re-laid out the shells. What's left is our own colors
-- (the accent may have changed) and insets, each only when its color changed.
DUI.On("StyleChanged", function()
    -- Lite shells are ours to re-layout (UI scale, border alpha).
    for s in pairs(lites) do liteLayout(s) end
    for shade in pairs(shades) do shade:SetColorTexture(0, 0, 0, Kit.INSET_SHADE) end
    for btn in pairs(looks) do paintLook(btn) end
    for row in pairs(rows) do paintRow(row) end
    for btn in pairs(slots) do Kit.SlotQuality(btn) end
    -- Selected tabs' underline and text, and the windows' top line.
    for tab, t in pairs(tabs) do
        if t.picked then paintTab(tab, true) end
    end
    for _, line in pairs(topLines) do paintTopLine(line) end
end)
