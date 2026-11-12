local stub = require("stub")

-- The game's own pop-ups: a proxy handle each, held at the moved spot.

local function load()
    local DUI = stub.Load({ before = function()
        -- In the game's bottom column, which lays it out from protected code.
        local bottom = CreateFrame("Frame", "BottomManagedFrameContainer", UIParent)
        local f = CreateFrame("Frame", "GroupLootContainer", UIParent)
        f.isManagedFrame, f.layoutParent = true, bottom
    end })
    stub.RunTimers()
    return DUI
end

T.test("game frames: one that exists gets a proxy mover; one that doesn't is skipped", function()
    local DUI = load()
    local e = DUI.Movers.Get("game.GroupLootContainer")
    T.truthy(e and e.proxy)
    T.isnil(DUI.Movers.Get("game.TicketStatusFrame"), "not on this client")
end)

T.test("game frames: untouched until moved, then held there when the game places it", function()
    local DUI = load()
    local f = _G.GroupLootContainer
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
    T.eq((f:GetPoint(1)), "TOPLEFT", "the game's own spot kept")
    DUI.DB.Positions()["game.GroupLootContainer"] = { 50, 60 }
    DUI.Movers.Get("game.GroupLootContainer").onMoved("game.GroupLootContainer")
    local p, rel, _, x, y = f:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(x, 50); T.eq(y, 60)
    T.eq(f:GetParent(), UIParent, "out of the game's column, so its layouts skip it")
    -- No hook on its SetPoint. The game's column calls that from protected code,
    -- and with a hook on it the call fails ("attempt to call a nil value").
    T.isnil(rawget(f, "SetPoint"), "no hook on its SetPoint")
    -- Shown, the game takes it back into its column and lays it out.
    f:Hide()
    f:SetParent(BottomManagedFrameContainer)
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
    f:Show()
    stub.RunTimers()
    T.eq((f:GetPoint(1)), "CENTER", "put back the frame after the game places it")
    T.eq(f:GetParent(), UIParent)
    DUI.Movers.Reset("game.GroupLootContainer")
    f:Hide(); f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10); f:Show()
    stub.RunTimers()
    T.eq((f:GetPoint(1)), "TOPLEFT", "after a reset, the game's spot again")
end)

T.test("game frames: a reset while it's out puts it back in the game's column, where the game had it", function()
    local DUI = load()
    local f = _G.GroupLootContainer
    f:SetParent(BottomManagedFrameContainer)
    f:ClearAllPoints(); f:SetPoint("BOTTOM", BottomManagedFrameContainer, "TOP", 0, 12)
    f:Show()
    DUI.DB.Positions()["game.GroupLootContainer"] = { 50, 60 }
    DUI.Movers.Get("game.GroupLootContainer").onMoved("game.GroupLootContainer")
    T.eq(f:GetParent(), UIParent)
    DUI.Movers.Reset("game.GroupLootContainer")
    T.eq(f:GetParent(), BottomManagedFrameContainer, "back in the game's column")
    local p, rel, rp, x, y = f:GetPoint(1)
    T.eq(p, "BOTTOM"); T.eq(rel, BottomManagedFrameContainer); T.eq(rp, "TOP"); T.eq(x, 0); T.eq(y, 12)
    T.eq(f:GetNumPoints(), 1)
end)

T.test("game frames: a reset puts a frame outside the column back on its own spot", function()
    local DUI = stub.Load({ before = function()
        local e = CreateFrame("Frame", "UIErrorsFrame", UIParent)
        e:SetPoint("TOP", UIParent, "TOP", 0, -122)
    end })
    stub.RunTimers()
    DUI.DB.Positions()["game.UIErrorsFrame"] = { 0, 200 }
    DUI.Movers.Get("game.UIErrorsFrame").onMoved("game.UIErrorsFrame")
    T.eq((UIErrorsFrame:GetPoint(1)), "CENTER")
    DUI.Movers.Reset("game.UIErrorsFrame")
    local p, rel, rp, x, y = UIErrorsFrame:GetPoint(1)
    T.eq(p, "TOP"); T.eq(rel, UIParent); T.eq(rp, "TOP"); T.eq(x, 0); T.eq(y, -122)
end)

T.test("game frames: a damaged saved spot is ignored, the frame keeps the game's", function()
    local DUI = load()
    local f = _G.GroupLootContainer
    f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
    DUI.DB.Positions()["game.GroupLootContainer"] = { "x", 0 / 0 }
    T.truthy(pcall(DUI.Movers.Get("game.GroupLootContainer").onMoved, "game.GroupLootContainer"))
    T.eq((f:GetPoint(1)), "TOPLEFT", "untouched")
end)

-- Battle.net toasts hang off the game's ChatAlertFrame by a corner
-- (AlertContainerMixin, justification LEFT unless the chat's buttons are on the
-- right), never from its center. Once moved it takes a toast's size, so the toast
-- fills the handle, and its handle starts where a toast will show.
local function toastWorld(justify)
    local DUI = stub.Load({ before = function()
        local f = CreateFrame("Frame", "ChatAlertFrame", UIParent)
        f:SetSize(30, 10)
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 300)
        f.__center = { 55, 305 }
        f.GetJustification = function() return justify or "LEFT" end
    end })
    stub.RunTimers()
    return DUI, _G.ChatAlertFrame, DUI.Movers.Get("game.ChatAlertFrame")
end

T.test("battle.net logins: a handle standing where the toast shows, and the frame untouched until moved", function()
    local _, f, e = toastWorld()
    T.truthy(e and e.proxy, "a proxy handle")
    T.eq(e.label, "Battle.net Logins")
    T.eq((f:GetPoint(1)), "BOTTOMLEFT", "untouched")
    T.eq(f:GetWidth(), 30)
    local x, y = e.home()
    T.eq(x, 55 - UIParent:GetWidth() / 2 + 110, "its left edge on the frame's: the toast grows right from there")
    T.eq(y, 305 - UIParent:GetHeight() / 2 + 20, "and up from its bottom")
end)

T.test("battle.net logins: with the chat's buttons on the right the toast hangs from the right edge", function()
    local _, _, e = toastWorld("RIGHT")
    T.eq((e.home()), 55 - UIParent:GetWidth() / 2 - 110)
end)

T.test("battle.net logins: moved, it's a toast's size on the spot; a reset gives back the game's size and spot", function()
    local DUI, f, e = toastWorld()
    DUI.DB.Positions()["game.ChatAlertFrame"] = { 300, -100 }
    e.onMoved("game.ChatAlertFrame")
    local p, rel, _, x, y = f:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, UIParent); T.eq(x, 300); T.eq(y, -100)
    T.eq(f:GetWidth(), 250); T.eq(f:GetHeight(), 50)
    DUI.Movers.Reset("game.ChatAlertFrame")
    T.eq((f:GetPoint(1)), "BOTTOMLEFT")
    T.eq(f:GetWidth(), 30); T.eq(f:GetHeight(), 10)
end)

-- The loot window is an Edit Mode piece on this client, and addon code never moves
-- it because that taints it. Its spot goes into this profile's Edit Mode layout when
-- unlock mode ends, and the game places it there after the reload.
local function lootWorld(opts)
    opts = opts or {}
    local layouts = {}
    local DUI = stub.Load({ before = function()
        Enum.EditModeSystem = { ActionBar = 0, LootFrame = 10, LossOfControl = 28 }
        Enum.EditModeLossOfControlSetting = { Size = 0 }
        Enum.EditModeLayoutType = { Preset = 0, Account = 1 }
        _G.CopyTable = function(t)
            local c = {}
            for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
            return c
        end
        local function loot(x)
            return { system = 10, isInDefaultPosition = x == nil, settings = {},
                     anchorInfo = { point = "LEFT", relativeTo = "UIParent", relativePoint = "LEFT", offsetX = x or 16, offsetY = 116 } }
        end
        -- The game's Modern preset: the middle of the screen.
        local function cc()
            return { system = 28, isInDefaultPosition = true, settings = {},
                     anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 } }
        end
        _G.EditModePresetLayoutManager = { GetCopyOfPresetLayouts = function()
            return { { layoutIndex = 1, layoutType = 0, layoutName = "Modern", systems = { loot(), cc() } } }
        end }
        layouts.list = { { layoutType = 1, layoutName = opts.layoutName or "DaylightUI - DPS/Tank", systems = { loot(opts.movedInEditMode), cc() } } }
        layouts.active = 2
        _G.C_EditMode = {
            GetLayouts = function() return { layouts = CopyTable(layouts.list), activeLayout = layouts.active } end,
            SaveLayouts = function(info)
                layouts.list = {}
                for _, l in ipairs(info.layouts) do if l.layoutType ~= 0 then layouts.list[#layouts.list + 1] = l end end
                layouts.saves = (layouts.saves or 0) + 1
            end,
            SetActiveLayout = function(i) layouts.active = i end,
        }
        _G.EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
        EditModeManagerFrame.accountSettings = {}
        EditModeManagerFrame:Hide()
        _G.GetCVarBool = function(name) return opts.underMouse == true and name == "lootUnderMouse" end
        -- A player who has seen the setup guide (it holds reload prompts while open).
        DaylightUIDB = { installerSeen = 1e9 }
        local f = CreateFrame("Frame", "LootFrame", UIParent)
        f:SetSize(260, 400)
        f:SetPoint("LEFT", UIParent, "LEFT", 16, 116)
        f:Hide()
        local c = CreateFrame("Frame", "LossOfControlFrame", UIParent)
        c:SetSize(256, 58)
        c:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        c:Hide()
        -- The game's EditModeSystemMixin.
        c.editSize = opts.ccSize or 100
        c.GetSettingValue = function(self, setting)
            return setting == Enum.EditModeLossOfControlSetting.Size and self.editSize or 0
        end
    end })
    stub.RunTimers()
    return DUI, layouts
end

local function lootEntry(layouts) return layouts.list[1].systems[1] end
local function ccEntry(layouts) return layouts.list[1].systems[2] end

T.test("loot window: a handle that never moves the frame; locking writes the spot into our layout and asks for a reload", function()
    local DUI, layouts = lootWorld()
    local e = DUI.Movers.Get("game.LootFrame")
    T.truthy(e and e.proxy, "a proxy handle")
    T.isnil(rawget(LootFrame, "SetPoint"), "no hook on its SetPoint")
    DUI.Movers.Unlock()
    DUI.Movers.Lock()
    T.isnil(layouts.saves, "nothing moved: nothing written")
    T.isnil(stub.popup and stub.popup.which, "and no reload asked")

    DUI.Movers.Unlock()
    DUI.DB.Positions()["game.LootFrame"] = { -300, 120 }
    e.onMoved("game.LootFrame")
    T.eq((LootFrame:GetPoint(1)), "LEFT", "the frame itself stays where the game put it")
    DUI.Movers.Lock()
    T.eq(layouts.saves, 1, "written once, on lock")
    local a = lootEntry(layouts).anchorInfo
    T.eq(a.point, "CENTER"); T.eq(a.relativeTo, "UIParent"); T.eq(a.relativePoint, "CENTER")
    T.eq(a.offsetX, -300); T.eq(a.offsetY, 120)
    T.eq(lootEntry(layouts).isInDefaultPosition, false)
    T.eq(stub.popup and stub.popup.which, "DAYLIGHTUI_RELOAD", "asks for the reload that puts it there")
    T.eq((LootFrame:GetPoint(1)), "LEFT", "still never moved by us")
end)

T.test("loot window: a reset puts the game's own spot back in the layout", function()
    local DUI, layouts = lootWorld({ movedInEditMode = 400 })
    DUI.Movers.Unlock()
    DUI.Movers.Reset("game.LootFrame")
    DUI.Movers.Lock()
    T.eq(layouts.saves, 1)
    local entry = lootEntry(layouts)
    T.eq(entry.isInDefaultPosition, true)
    T.eq(entry.anchorInfo.point, "LEFT"); T.eq(entry.anchorInfo.offsetX, 16, "the preset's spot")
end)

T.test("loot window: on another Edit Mode layout, nothing is written; chat says where to move it", function()
    local DUI, layouts = lootWorld({ layoutName = "My Layout" })
    DUI.Movers.Unlock()
    DUI.DB.Positions()["game.LootFrame"] = { -300, 120 }
    DUI.Movers.Get("game.LootFrame").onMoved("game.LootFrame")
    DUI.Movers.Lock()
    T.isnil(layouts.saves, "the player's own layout is left alone")
    T.eq(layouts.list[1].layoutName, "My Layout")
    T.truthy(stub.ChatContains("Edit Mode"), "told to move it in the game's Edit Mode")
end)

T.test("loot window: no handle while the game opens loot at the mouse", function()
    local DUI = lootWorld({ underMouse = true })
    local e = DUI.Movers.Get("game.LootFrame")
    T.truthy(e and e.active, "has an in-use check")
    T.falsy(e.active(), "the game's 'open loot window at mouse' decides the spot")
end)

T.test("cc alert: an unlock handle that never moves the frame; locking writes the spot and asks for the reload", function()
    local DUI, layouts = lootWorld()
    local e = DUI.Movers.Get("game.LossOfControlFrame")
    T.truthy(e and e.proxy, "a proxy handle")
    DUI.Movers.Unlock()
    DUI.DB.Positions()["game.LossOfControlFrame"] = { 40, -200 }
    e.onMoved("game.LossOfControlFrame")
    DUI.Movers.Lock()
    T.eq(layouts.saves, 1, "written once, on lock")
    local a = ccEntry(layouts).anchorInfo
    T.eq(a.point, "CENTER"); T.eq(a.offsetX, 40); T.eq(a.offsetY, -200)
    T.eq(ccEntry(layouts).isInDefaultPosition, false)
    T.eq(stub.popup and stub.popup.which, "DAYLIGHTUI_RELOAD")
    local p, _, _, x = LossOfControlFrame:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(x, 0, "never moved by us")
end)

T.test("cc alert: a reset puts the game's own spot back", function()
    local DUI, layouts = lootWorld()
    DUI.DB.Positions()["game.LossOfControlFrame"] = { 40, -200 }
    DUI.Movers.Unlock()
    DUI.Movers.Get("game.LossOfControlFrame").onMoved("game.LossOfControlFrame")
    DUI.Movers.Lock()
    DUI.Movers.Unlock()
    DUI.Movers.Reset("game.LossOfControlFrame")
    DUI.Movers.Lock()
    T.eq(ccEntry(layouts).isInDefaultPosition, true)
    T.eq(ccEntry(layouts).anchorInfo.offsetX, 0, "the preset's spot")
end)

T.test("cc alert: on a layout of the player's own, chat names the alert, not the loot window", function()
    local DUI, layouts = lootWorld({ layoutName = "My Layout" })
    DUI.Movers.Unlock()
    DUI.DB.Positions()["game.LossOfControlFrame"] = { 40, -200 }
    DUI.Movers.Get("game.LossOfControlFrame").onMoved("game.LossOfControlFrame")
    DUI.Movers.Lock()
    T.isnil(layouts.saves)
    T.truthy(stub.ChatContains("crowd control alert"))
    T.falsy(stub.ChatContains("loot window"))
end)

T.test("cc alert: moved with the loot window, one write and one reload question", function()
    local DUI, layouts = lootWorld()
    DUI.Movers.Unlock()
    DUI.DB.Positions()["game.LootFrame"] = { -300, 120 }
    DUI.DB.Positions()["game.LossOfControlFrame"] = { 40, -200 }
    DUI.Movers.Get("game.LootFrame").onMoved("game.LootFrame")
    DUI.Movers.Get("game.LossOfControlFrame").onMoved("game.LossOfControlFrame")
    DUI.Movers.Lock()
    T.eq(layouts.saves, 1)
    T.eq(lootEntry(layouts).anchorInfo.offsetX, -300)
    T.eq(ccEntry(layouts).anchorInfo.offsetX, 40)
end)

T.test("cc alert: its Edit Mode size stays, the master Scale goes on top, and survives the game setting it again", function()
    local DUI = lootWorld({ ccSize = 150 })
    LossOfControlFrame:SetScale(1.5)     -- the game's UpdateSystemSettingSize
    DUI.Movers.ApplyAll()
    T.near(LossOfControlFrame:GetScale(), 1.5, 1e-6, "at Scale 1, the player's own size kept")
    DUI.DB.General().scale = 0.8
    DUI.Movers.ApplyAll()
    T.near(LossOfControlFrame:GetScale(), 1.2, 1e-6)
    LossOfControlFrame:SetScale(1.5)     -- the game applies its layout again
    stub.FireEvent("EDIT_MODE_LAYOUTS_UPDATED")
    stub.RunTimers()
    T.near(LossOfControlFrame:GetScale(), 1.2, 1e-6)
end)

-- General Scale (Movers.Scale) reaches the game's pop-ups, which scale by their own
-- kind. The frames themselves hang from UIParent, not from the handle's frame
-- (GroupLootFrame1-4 in the XML, alerts from a pool made on UIParent), so scaling
-- the container alone would leave them full size.
local function popupWorld(scale)
    local DUI = stub.Load({ before = function()
        DaylightUIDB = { installerSeen = 1e9 }
        local bottom = CreateFrame("Frame", "BottomManagedFrameContainer", UIParent)
        local c = CreateFrame("Frame", "GroupLootContainer", UIParent)
        c.isManagedFrame, c.layoutParent = true, bottom
        for i = 1, 4 do CreateFrame("Frame", "GroupLootFrame" .. i, UIParent) end
        CreateFrame("Frame", "AlertFrame", UIParent)
        CreateFrame("Frame", "ChatAlertFrame", UIParent)
        CreateFrame("Frame", "UIErrorsFrame", UIParent)
        -- AlertFrames.lua: every toast comes through here (Battle.net's too).
        _G.AlertFrame_ShowNewAlert = function(f) f:Show() end
    end })
    stub.RunTimers()
    if scale then
        DUI.DB.General().scale = scale
        DUI.Fire("StyleChanged")
        stub.RunTimers()
    end
    return DUI
end

T.test("game frames: General Scale reaches the roll popups and their container", function()
    popupWorld(0.8)
    for i = 1, 4 do T.near(_G["GroupLootFrame" .. i]:GetScale(), 0.8, 1e-6, "roll " .. i) end
    T.near(GroupLootContainer:GetScale(), 0.8, 1e-6, "the stack's spacing comes with it")
end)

T.test("game frames: General Scale reaches every toast as it shows, not the anchor", function()
    popupWorld(0.8)
    local toast = CreateFrame("Frame", nil, UIParent)
    AlertFrame_ShowNewAlert(toast)
    T.near(toast:GetScale(), 0.8, 1e-6, "a loot won toast")
    T.near(AlertFrame:GetScale(), 1, 1e-6, "the anchor only holds the spot")
end)

T.test("game frames: a Battle.net toast follows its own handle's size", function()
    local DUI = popupWorld(0.8)
    DUI.Movers.SetPieceScale("game.ChatAlertFrame", 1.5)
    local toast = CreateFrame("Frame", nil, UIParent)
    toast.GetAlertContainer = function() return ChatAlertFrame end
    AlertFrame_ShowNewAlert(toast)
    T.near(toast:GetScale(), 1.2, 1e-6)
end)

T.test("game frames: at Scale 1 and never sized, nothing of the game's is written", function()
    popupWorld()
    local wrote = 0
    local real = GroupLootFrame1.SetScale
    GroupLootFrame1.SetScale = function(self, s) wrote = wrote + 1; real(self, s) end
    DaylightUI.Fire("StyleChanged")
    stub.RunTimers()
    T.eq(wrote, 0)
end)

T.test("game frames: a moved popup keeps its spot when the scale changes", function()
    local DUI = popupWorld()
    DUI.DB.Positions()["game.GroupLootContainer"] = { 80, 100 }
    DUI.Movers.Get("game.GroupLootContainer").onMoved("game.GroupLootContainer")
    DUI.DB.General().scale = 0.5
    DUI.Fire("StyleChanged")
    stub.RunTimers()
    local _, _, _, x, y = GroupLootContainer:GetPoint(1)
    T.near(x, 160, 1e-6, "in the frame's own units, so the same place on screen")
    T.near(y, 200, 1e-6)
end)

T.test("game frames: the wheel sizes a popup, a right-click puts it back on the master", function()
    local DUI = popupWorld(0.8)
    T.truthy(DUI.Movers.Scalable("game.GroupLootContainer"))
    DUI.Movers.SetPieceScale("game.GroupLootContainer", 1.5)
    T.near(GroupLootFrame2:GetScale(), 1.2, 1e-6, "master times its own")
    DUI.Movers.Reset("game.GroupLootContainer")
    T.near(GroupLootFrame2:GetScale(), 0.8, 1e-6)
end)

T.test("game frames: a handle is the size its popup draws at", function()
    local DUI = popupWorld(0.5)
    DUI.Movers.Unlock()
    local h = DUI.Movers.Handle("game.GroupLootContainer")
    T.near(h:GetWidth(), 140, 1e-6, "280 at half size")
    T.near(h:GetHeight(), 50, 1e-6)
    DUI.Movers.Lock()
end)

T.test("game frames: a scale change in a fight waits for its end", function()
    local DUI = popupWorld()
    stub.EnterCombat()
    DUI.DB.General().scale = 0.8
    DUI.Movers.ApplyAll()
    T.near(GroupLootFrame1:GetScale(), 1, 1e-6, "not in the fight")
    stub.LeaveCombat()
    stub.RunTimers()
    T.near(GroupLootFrame1:GetScale(), 0.8, 1e-6)
end)

T.test("loot window: follows General Scale, the Edit Mode spot left to the game", function()
    local DUI = lootWorld()
    local before = { LootFrame:GetPoint(1) }
    DUI.DB.General().scale = 0.8
    DUI.Fire("StyleChanged")
    stub.RunTimers()
    T.near(LootFrame:GetScale(), 0.8, 1e-6)
    local p, _, _, x = LootFrame:GetPoint(1)
    T.eq(p, before[1], "never moved by our code: that taints it")
    T.eq(x, before[4])
end)
