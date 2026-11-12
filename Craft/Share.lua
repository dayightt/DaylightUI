-- Sharing the open profession: Shift-click its icon or name in the header (Craft.WhoTip
-- says so) to put its link in the open chat box, like the game's profession book does.
-- With no chat box open nothing happens, because opening one from addon code (OpenChat)
-- taints its edit box.
-- Anyone with Daylight UI who clicks the link gets the small view window (View.lua).

local _, DUI = ...
DUI.Craft = DUI.Craft or {}
local ns = DUI.Craft

local Share = {}
ns.Share = Share

local function ts(name)
    local fn = type(C_TradeSkillUI) == "table" and C_TradeSkillUI[name]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function isLink(v)
    return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" and v or nil
end

-- The open profession's link, or its spell's if the game gives no list link.
function Share.Link()
    local link = isLink(ts("GetTradeSkillListLink"))
    if link then return link end
    local prof = ns.Data.Profession()
    if not (prof and C_Spell and type(C_Spell.GetSpellTradeSkillLink) == "function") then return nil end
    for _, tab in ipairs(ns.Window.tabs or {}) do
        if tab.skillLine == prof.id and tab.spellID then
            local ok, v = pcall(C_Spell.GetSpellTradeSkillLink, tab.spellID)
            return ok and isLink(v) or nil
        end
    end
    return nil
end

-- Insert into the open chat box (or macro); true when something took it.
function Share.Insert()
    local link = Share.Link()
    if not link then return false end
    local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    return type(insert) == "function" and insert(link) == true
end
