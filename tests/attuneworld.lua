-- A fake Attune (Attune.lua, 16001-34), only what its skin reads. Attune_Frame
-- makes its AceGUI-style window with the bronze PortraitFrameTemplate
-- "AttuneBronzeChrome" over it. Attune_Select draws a chain on "Attune_GraphRoot",
-- each step through Attune_CreateNode: a BackdropTemplate button
-- "Attune_Node_<id>" colored by its state (its own colors), its icon, title and
-- type texts by name, and a Line3 into its top from the step before, lit by draw
-- sublevel (2 done, 1 ready, 0 not).
local stub = require("stub")

local AW = {}

-- Its backdrop colors, as Attune_SetNodeTone and the goal nodes set them.
AW.COLORS = {
    done = { 0.373, 0.729, 0.275, 0.3 }, next = { 0.851, 0.608, 0.0, 0.3 }, locked = { 0.1, 0.1, 0.1, 0.5 },
    goal = { 0.557, 0.055, 0.075, 0.7 }, goalDone = { 0.055, 0.306, 0.576, 0.7 }, spacer = { 0, 0, 0, 0 },
}

-- A chain: id, state, the step it follows, the line's level, its words.
AW.CHAIN = {
    { id = "1", state = "done", title = "The Key to Karazhan", kind = "|cffffd100Quest|r|c60808080 in Shadowfang Keep|r" },
    { id = "2", state = "done", from = "1", level = 2, title = "Arcane Sceptre", kind = "|cffffd100Item|r|c60808080 in Scholomance|r" },
    { id = "3", state = "next", from = "2", level = 1, title = "Return to Khadgar", kind = "|cffffd100Turn In|r" },
    { id = "4", state = "locked", from = "3", level = 0, title = "Into the Tower", kind = "|cffffd100Kill|r" },
    { id = "5", state = "goal", from = "4", level = 0, title = "Not attuned" },
}

local function backdrop(f)
    for _, k in ipairs({ "TopLeftCorner", "TopEdge", "Center" }) do f[k] = f[k] or f:CreateTexture() end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function(self, r, g, b, a) self.__bd = { r, g, b, a or 1 } end
    f.GetBackdropColor = function(self) local c = self.__bd or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
    f.SetBackdropBorderColor = function() end
end

function AW.Install()
    stub.installedAddOns.Attune, stub.loadedAddOns.Attune = true, true
    AW.states = {}
    function _G.Attune_CreateNode(step, parent, x, y)
        local name = "Attune_Node_" .. step.id
        local node = _G[name] or CreateFrame("Button", name, parent)
        node:SetParent(parent)
        node:SetSize(170, 48)
        node:ClearAllPoints()
        node:SetPoint("TOP", parent, "TOP", x, -y)
        backdrop(node)
        local state = AW.states[step.id] or step.state
        node:SetBackdropColor(unpack(AW.COLORS[state]))
        local icon = _G["Attune_Icon_" .. step.id] or CreateFrame("Button", "Attune_Icon_" .. step.id, node)
        icon:SetSize(32, 32)
        icon:SetPoint("TOPLEFT", node, "TOPLEFT", 8, -8)
        -- The client's SetNormalTexture makes the button's texture, and the fake keeps one.
        icon.__normal = icon.__normal or icon:CreateTexture()
        icon.__normal:SetAllPoints(icon)
        icon.__normal:SetTexture("Interface\\Icons\\INV_Misc_Key_07")
        icon.__high = icon.__high or icon:CreateTexture()
        icon.GetNormalTexture = function(self) return self.__normal end
        icon.GetHighlightTexture = function(self) return self.__high end
        local title = _G["Attune_Title_" .. step.id] or node:CreateFontString("Attune_Title_" .. step.id)
        title:SetPoint("TOPLEFT", node, "TOPLEFT", 44, step.kind and -8 or -16)
        title:SetSize(120, 16)
        title:SetJustifyH("LEFT")
        title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        title:SetText(step.title)
        if step.kind then
            local kind = _G["Attune_Type_" .. step.id] or node:CreateFontString("Attune_Type_" .. step.id)
            kind:SetPoint("TOPLEFT", node, "TOPLEFT", 44, -24)
            kind:SetSize(120, 16)
            kind:SetJustifyH("LEFT")
            kind:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            kind:SetText(step.kind)
            kind:Show()
        end
        if step.from then
            local lname = "Attune_Line3_" .. step.id .. "_" .. step.from
            local line = _G[lname] or node:CreateLine(lname)
            line:SetColorTexture(0.851, 0.608, 0, 1)
            line:SetDrawLayer("ARTWORK", step.level)
            line:SetThickness(6)
            line:SetStartPoint("TOP", node, 0, 30)
            line:SetEndPoint("TOP", node, 0, -2)
            line:Show()
        end
        node:Show()
    end
    function _G.Attune_Select(attuneId)
        local root = _G.Attune_GraphRoot or CreateFrame("Frame", "Attune_GraphRoot", AW.host or UIParent)
        root:SetSize(1, 1)
        root:ClearAllPoints()
        root:SetPoint("TOP", AW.host or UIParent, "TOP", 0, -90)
        root:Show()
        for i, step in ipairs(AW.CHAIN) do _G.Attune_CreateNode(step, root, 0, (i - 1) * 78) end
    end
    function _G.Attune_Frame()
        local host = CreateFrame("Frame", "AttuneFrame", UIParent)
        host:SetSize(1010, 550)
        host:SetPoint("CENTER")
        AW.host = host
        local chrome = CreateFrame("Frame", "AttuneBronzeChrome", host)
        chrome:SetAllPoints(host)
        chrome.NineSlice = CreateFrame("Frame", nil, chrome)
        chrome.Bg = chrome:CreateTexture()
        chrome.TitleContainer = CreateFrame("Frame", nil, chrome)
        chrome.TitleContainer.TitleText = chrome.TitleContainer:CreateFontString()
        chrome.TitleContainer.TitleText:SetText("Attune")
        chrome.CloseButton = CreateFrame("Button", nil, chrome)
        chrome.CloseButton:SetSize(24, 24)
        chrome.CloseButton:SetPoint("TOPRIGHT")
    end
end

function AW.Remove()
    for _, k in ipairs({ "Attune_CreateNode", "Attune_Select", "Attune_Frame", "Attune_GraphRoot", "AttuneBronzeChrome" }) do
        _G[k] = nil
    end
end

return AW
