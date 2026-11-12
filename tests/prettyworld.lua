-- A fake PrettyTooltip (v1.3.8), only what its skin and Daylight UI's stepping aside
-- touch. Everything in the real one is private (its namespace has no global). What
-- shows is a host frame on UIParent holding one panel (Panel/Layout.lua getPanel,
-- createPanel), with its pieces as plain fields on the frame. drawChrome paints
-- each piece on every render, its accent times .36 on the left and right edges (the
-- two ends of a dual school), and finishPanel ends a render with SetHeight, then
-- Show. Alpha 0 on a piece doesn't survive that paint, since its colors carry an
-- alpha, so a render here puts it back.
local PW = {}

PW.EDGE = 0.36   -- drawChrome's edgeStrength on the left and right edges

local function piece(panel, layer)
    local t = panel:CreateTexture(nil, layer or "BORDER")
    t:SetVertexColor(1, 1, 1, 1)
    return t
end

function PW.Install(stub, db)
    stub.installedAddOns.PrettyTooltip = true
    stub.loadedAddOns.PrettyTooltip = true
    _G.PrettyTooltipDB = db or {}
end

function PW.Uninstall(stub)
    stub.installedAddOns.PrettyTooltip, stub.loadedAddOns.PrettyTooltip = nil, nil
    _G.PrettyTooltipDB = nil
end

-- Layout.lua getPanel: made the first time a tooltip's data comes.
function PW.NewPanel()
    local host = CreateFrame("Frame", nil, UIParent)
    local panel = CreateFrame("Frame", nil, host)
    panel.host = host
    panel:SetFrameLevel(5)
    panel.halo, panel.background, panel.glow = piece(panel, "BACKGROUND"), piece(panel, "BACKGROUND"), piece(panel, "BACKGROUND")
    panel.header, panel.icon, panel.iconBorder = piece(panel), piece(panel, "OVERLAY"), piece(panel, "OVERLAY")
    panel.shades, panel.edges = {}, {}
    for i = 1, 4 do
        panel.shades[i] = piece(panel)
        panel.edges[i] = piece(panel, "OVERLAY")
    end
    panel:Hide()
    return panel
end

-- Layout.lua drawChrome and finishPanel. color is its accent, right is a dual
-- school's other end, and opts holds tag (the comparison label), close (a clicked
-- item's X) and native (the game's border on a frame of its own).
function PW.Render(panel, color, right, opts)
    opts = opts or {}
    local r = right or color
    for _, key in ipairs({ "halo", "background", "glow", "header" }) do panel[key]:SetAlpha(1) end
    for i = 1, 4 do
        panel.edges[i]:SetAlpha(1)
        panel.shades[i]:SetAlpha(1)
    end
    for i, edge in ipairs(panel.edges) do edge:SetVertexColor(0.1, 0.1, 0.1, 0.95) end
    panel.edges[3]:SetVertexColor(color[1] * PW.EDGE, color[2] * PW.EDGE, color[3] * PW.EDGE, 0.95)
    panel.edges[4]:SetVertexColor(r[1] * PW.EDGE, r[2] * PW.EDGE, r[3] * PW.EDGE, 0.95)
    panel.iconBorder:SetVertexColor(color[1], color[2], color[3], 0.85)
    if opts.native and panel.nativeBorder == nil then
        panel.nativeBorder = CreateFrame("Frame", nil, panel)
    end
    if opts.close and not panel.close then
        local close = CreateFrame("Button", nil, panel)
        close.lines = { close:CreateTexture(), close:CreateTexture() }
        panel.close = close
    end
    if opts.tag and not panel.equipped then
        local tag = CreateFrame("Frame", nil, panel)
        tag.border, tag.fill = tag:CreateTexture(), tag:CreateTexture()
        tag.text = tag:CreateFontString(nil, "OVERLAY")
        panel.equipped = tag
    end
    panel:SetHeight(120)
    panel:Show()
end

return PW
