-- A meter row: rank, spec or class icon, then a gradient bar with the name and
-- amount. The thin outline (row.box) wraps the bar alone; your own row's is lit
-- in the accent.
--
-- Rank and icon only use plain values (row index, specIconID, classFilename).
-- Name and amount may be secret and go straight into their text.

local _, ns = ...
local DUI = DaylightUI
local Style, Pixel = DUI.Style, DUI.Pixel

local Rows = {}
ns.Rows = Rows

Rows.BORDER = 1               -- the row's outline, physical px
Rows.GAP = 3                  -- between the rank, the icon and the bar
Rows.RANK_DIGITS = "40"       -- the rank column is as wide as this
Rows.CUT = 0.45               -- the fill's angled edge, as a share of the bar's height
Rows.MINE_BAND = 0.45         -- how much of the accent your row's outline takes

local function isSecret(v) return issecretvalue ~= nil and issecretvalue(v) end

-- A class's own icon (the unit frames' art), or nil.
local CLASS_ICON = {}
for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    CLASS_ICON[c] = DUI.MEDIA .. "class\\" .. string.lower(c) .. ".tga"
end
Rows.CLASS_ICON = CLASS_ICON

function Rows.New(parent, textSize, font)
    local row = CreateFrame("Frame", nil, parent)
    row.box = CreateFrame("Frame", nil, row)
    Style.Shell(row.box, { borderPx = Rows.BORDER, noBevel = true, noBackground = true })
    local bar = Style.Bar(row, nil, ns.MEDIA.bars.meter)
    row.bar = bar
    row.rank = Style.Text(row, Style.SIZE.tiny, "RIGHT", ns.MEDIA.fonts.meter)
    Style.InkText(row.rank, "LABEL")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:Hide()
    row.name = Style.Text(bar, textSize, "LEFT", font or ns.MEDIA.fonts.meter)
    row.amount = Style.Text(bar, textSize, "RIGHT", font or ns.MEDIA.fonts.meter)
    row.amount:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    row.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
    row.name:SetPoint("RIGHT", row.amount, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    row.amount:SetWordWrap(false)
    return row
end

-- Lays the row's pieces out for its height (call after sizing it): the
-- rank column (cfg.rank), the icon square (cfg.icons ~= "none"), the bar.
function Rows.Layout(row, cfg)
    local h = row:GetHeight()
    local T = Pixel.Px(row, Rows.BORDER)
    local x = T
    local rankOn = cfg.rank ~= false
    row.rank:SetShown(rankOn)
    row.rank:ClearAllPoints()
    if rankOn then
        local w = math.ceil(Style.SIZE.tiny * 0.62 * #Rows.RANK_DIGITS) + 2
        row.rank:SetPoint("LEFT", row, "LEFT", x, 0)
        row.rank:SetWidth(w)
        x = x + w + Rows.GAP
    end
    row.iconOn = cfg.icons ~= "none"
    row.icon:ClearAllPoints()
    if row.iconOn then
        local s = math.max(1, h - 2 * T)
        row.icon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.icon:SetSize(s, s)
        x = x + s + Rows.GAP
    else
        row.icon:Hide()
    end
    row.barX = x
    row.box:ClearAllPoints()
    row.box:SetPoint("TOPLEFT", row, "TOPLEFT", x - T, 0)
    row.box:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", x, -T)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -T, T)
    Style.AngleFill(row.bar, "right", math.max(1, math.floor((h - 2 * T) * Rows.CUT + 0.5)))
    Style.LayoutShell(Style.GetShell(row.box))
end

-- How solid the empty track and the outline are (0: the fill alone).
function Rows.Track(row, a)
    a = type(a) == "number" and a or 1
    row.track = a
    local back = Style.BarBack(row.bar)
    if back then back:SetAlpha(a) end
    local s = Style.GetShell(row.box)
    if s then
        s.opts.noBorder = a <= 0 and not row.mine
        s.opts.borderAlpha = a < 1 and a * (DUI.DB.General().borderAlpha or 1) or nil
        s.opts.shadowAlpha = 0
    end
end

-- The row's icon: the player's spec, else their class's, else none (a mob
-- keeps the empty square, so names still line up).
function Rows.SetIcon(row, src, cfg)
    if not row.iconOn then return end
    local spec, class = src.specIconID, src.classFilename
    -- The game keeps the spec icon secret (out of a fight too): a secret one
    -- goes straight to the texture, which takes it, every time.
    if cfg.icons ~= "class" and isSecret(spec) then
        row.iconFile = nil
        row.icon:SetTexture(spec)
        Style.CropIcon(row.icon)
        row.icon:Show()
        return
    end
    local file
    if cfg.icons ~= "class" and type(spec) == "number" and spec > 0 then
        file = spec
    elseif type(class) == "string" and not isSecret(class) then
        file = CLASS_ICON[class]
    end
    if file ~= row.iconFile then
        row.iconFile = file
        if file then
            row.icon:SetTexture(file)
            if type(file) == "number" then Style.CropIcon(row.icon) else row.icon:SetTexCoord(0, 1, 0, 1) end
        end
    end
    row.icon:SetShown(file ~= nil)
end

-- Your own row: its outline lit in the accent (eased by the shell), else
-- back to the warm border.
function Rows.SetMine(row, on)
    on = on == true
    if row.mine == on then return end
    row.mine = on
    local s = Style.GetShell(row.box)
    if not s then return end
    if on then
        s.opts.noBorder = false
        Style.LightShell(s, Rows.MINE_BAND)
    else
        s.opts.noBorder = (row.track or 1) <= 0
        Style.SetShellColors(s, nil, nil)
    end
end
