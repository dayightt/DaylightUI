-- Collections pack: collections, achievements, the dungeon journal and the
-- dressing room. Each is Engine.Window plus whatever is unique to it.

local _, ns = ...
local DUI = DaylightUI
local Engine = ns.Engine
local Style = DUI.Style


-- Journal lists (mounts, pets, wardrobe sets): the gray bar behind each row
-- (PetList-ButtonBackground) and the selection art are hidden and the row drawn
-- as a line, keeping its icon and text. The hidden selection art still tells us
-- which row is picked; the game picks after the click.
local journalHooked = setmetatable({}, { __mode = "k" })
local function journalRow(row)
    if type(row) ~= "table" or not row.CreateTexture then return end
    local Kit = ns.Kit
    local back = row.background or row.Background
    local sel = row.selectedTexture or row.SelectedTexture
    if Kit.Kind(back) ~= "Texture" or Kit.Kind(sel) ~= "Texture" then return end
    Kit.Hide(back)
    Kit.Hide(sel)
    Kit.Hide(row.HighlightTexture)
    Kit.Row(row, "art", sel, false)
    if not journalHooked[row] then
        journalHooked[row] = true
        row:HookScript("OnMouseUp", Kit.RepaintSoon)
    end
end

Engine.Window({ key = "collections", pack = "collections", addon = "Blizzard_Collections", frame = "CollectionsJournal", watch = true,
    auto = { lines = true, each = function(f)
        if f.ForEachFrame and type(f.ScrollTarget) == "table" then ns.Kit.EachRow(f, journalRow, "journal") end
    end } })
Engine.Window({ key = "achievements", pack = "collections", addon = "Blizzard_AchievementUI", frame = "AchievementFrame", watch = true })
-- The dungeon journal's pages are colored for parchment. Opening or closing a
-- section header recolors it, so relight after.
local headersHooked = false
Engine.Window({ key = "journal", pack = "collections", addon = "Blizzard_EncounterJournal", frame = "EncounterJournal",
    watch = true, light = true,
    after = function(Kit)
        if headersHooked or type(EncounterJournal_UpdateButtonState) ~= "function" then return end
        headersHooked = true
        hooksecurefunc("EncounterJournal_UpdateButtonState", function(btn)
            if type(btn) ~= "table" then return end
            Kit.Relight(btn.title)
            Kit.Relight(btn.expandedIcon)
        end)
    end })
-- ---------------------------------------------------------------------
-- The dressing room (DressUpFrames.xml / DressUpModelFrameMixin.lua) and the
-- small one beside the auction house. The race backdrop behind the model stays
-- for immersion.
-- ---------------------------------------------------------------------

local function qualityColor(quality)
    if type(quality) ~= "number" then return nil end
    local getColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if type(getColor) ~= "function" then return nil end
    local r, g, b = getColor(quality)
    if type(r) ~= "number" then return nil end
    return { r, g, b }
end

-- Model zoom and rotate buttons, same as the character window.
local function modelControls(Kit, scene)
    local controls = type(scene) == "table" and scene.ControlFrame
    if type(controls) ~= "table" then return end
    for _, key in ipairs({ "zoomInButton", "zoomOutButton", "rotateLeftButton", "rotateRightButton", "resetButton" }) do
        Kit.IconButton(controls[key])
    end
end

-- Bottom buttons sit inside the border with the same gap as our footers
-- (Footer.GAP in Windows/Parts.lua).
local FOOTER_INSET, FOOTER_GAP = 6, 8

-- An item list slot (DressUpCustomSetSlotFrameTemplate): icon outlined in the
-- item's quality (the game's ring hidden), name in our font. SetDetails colors
-- the name by quality, so that color is kept and used for the outline.
-- Uncollected items are dimmed, and slots that can't be worn say so.
local dressedSlots = setmetatable({}, { __mode = "k" })
local function paintSlot(Kit, slot)
    local INK = Style.INK
    local name = slot.Name
    local state = slot.slotState
    local border, ink
    local item = slot.item
    local quality = type(item) == "table" and type(item.GetItemQuality) == "function" and item:GetItemQuality() or nil
    if slot.transmogID == nil then
        -- Empty slot ("(Head)"): the game's gray, dimmed.
        border, ink = Kit.EMPTY_ITEM_BORDER, INK.OFF
    elseif state ~= nil and state == CUSTOM_SET_SLOT_STATE_ERROR then
        border, ink = INK.BAD, INK.BAD
    elseif (state ~= nil and state == CUSTOM_SET_SLOT_STATE_UNCOLLECTED) or slot.isHiddenVisual then
        border, ink = Kit.EMPTY_ITEM_BORDER, INK.OFF
    elseif item == nil then
        -- An illusion (no item of its own): the game's yellow becomes ours.
        border, ink = Kit.EMPTY_ITEM_BORDER, INK.TEXT
    elseif type(quality) == "number" and quality <= 1 then
        -- Poor and common have no color worth showing (white and gray), so
        -- they get row text and a quiet outline, as in the bags.
        border, ink = Kit.EMPTY_ITEM_BORDER, quality == 1 and INK.TEXT or INK.OFF
    elseif type(name) == "table" and name.GetTextColor then
        local r, g, b = name:GetTextColor()
        if type(r) == "number" and not (issecretvalue and issecretvalue(r)) then border = { r, g, b } end
    end
    if ink and type(name) == "table" and name.SetTextColor then name:SetTextColor(ink[1], ink[2], ink[3]) end
    Kit.Paint(Kit.ShellOf(slot), border or Kit.EMPTY_ITEM_BORDER)
end

local function itemSlots(Kit, panel)
    if type(panel) ~= "table" or not panel.GetChildren then return end
    for _, slot in ipairs({ panel:GetChildren() }) do
        if type(slot.Name) == "table" and type(slot.IconBorder) == "table" then
            if not dressedSlots[slot] then
                dressedSlots[slot] = true
                Kit.Item(slot)
                Kit.Font(slot.Name, Style.SIZE.body)
                -- Refresh hides every slot, fills it, then shows it, so
                -- repaint on show.
                slot:HookScript("OnShow", function(self) paintSlot(Kit, self) end)
            end
            paintSlot(Kit, slot)
        end
    end
end

-- A row in a set's list (DressUpFrameTransmogSetButtonTemplate): row look,
-- accent on picked rows (the game's SelectedTexture still tells us which), icon
-- outlined in quality (red if you can't wear it), slot name in tan.
local function setRow(Kit, row)
    if type(row) ~= "table" or not row.CreateTexture then return end
    Kit.Item(row)
    Kit.Hide(row.BackgroundTexture)
    Kit.Hide(row.HighlightTexture)
    Kit.Hide(row.SelectedTexture)
    Kit.Row(row, "art", row.SelectedTexture)
    Kit.Font(row.ItemName, Style.SIZE.body)
    Kit.Font(row.ItemSlot, Style.SIZE.small, Style.INK.LABEL)
    local data = row.elementData
    local border
    if type(data) == "table" then
        border = data.itemUsable == false and Style.INK.BAD or qualityColor(data.itemQuality)
    end
    Kit.Paint(Kit.ShellOf(row), border or Kit.EMPTY_ITEM_BORDER)
end

-- A set's list: its rows, plus the set name as the panel heading. Clicking a
-- row picks it and drops another in the same slot, so all are repainted. Uses
-- OnMouseUp because the game resets the row's OnClick each time it fills it.
local function setList(Kit, panel)
    if type(panel) ~= "table" then return end
    Kit.Font(panel.SetName, Style.SIZE.head)
    local box = panel.ScrollBox
    if type(box) ~= "table" then return end
    Kit.EachRow(box, function(row)
        setRow(Kit, row)
        if row.HookScript and not dressedSlots[row] then
            dressedSlots[row] = true
            row:HookScript("OnMouseUp", Kit.RepaintSoon)
        end
    end, "dressup")
end

Engine.Window({ key = "dressup", pack = "collections", frame = "DressUpFrame", watch = true,
    auto = { skip = { ".MaximizeMinimizeFrame", ".ToggleCustomSetDetailsButton" } },
    after = function(Kit, f)
        Kit.Panel(f.CustomSetDetailsPanel)
        Kit.Panel(f.SetSelectionPanel)
        modelControls(Kit, f.ModelScene)
        -- The set dropdown's Save button (the walk skips dropdown internals).
        local dropdown = f.CustomSetDropdown
        if type(dropdown) == "table" then Kit.Button(dropdown.SaveButton) end
        -- The game butts the bottom buttons against each other and the edge.
        -- Move them inside the border with a gap, like our footers.
        local close, reset, link = _G.DressUpFrameCancelButton, f.ResetButton, f.LinkButton
        if type(close) == "table" and type(reset) == "table" and not dressedSlots[close] then
            dressedSlots[close] = true
            local P = DUI.Pixel.Px(f, FOOTER_INSET)
            close:ClearAllPoints()
            close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -P, P)
            reset:ClearAllPoints()
            reset:SetPoint("RIGHT", close, "LEFT", -DUI.Pixel.Px(f, FOOTER_GAP), 0)
            if type(link) == "table" then
                link:ClearAllPoints()
                link:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P, P)
            end
        end
        -- Maximize/minimize as bare chevrons next to the X, like the world map.
        local mm = f.MaximizeMinimizeFrame
        if type(mm) == "table" then
            Kit.BareButton(mm.MinimizeButton, "down")
            Kit.BareButton(mm.MaximizeButton, "up")
        end
        local panel = f.CustomSetDetailsPanel
        -- The item list's toggle becomes a page arrow pointing the way the list
        -- goes, like the stats pane arrow on the character window.
        local toggle = f.ToggleCustomSetDetailsButton
        local arrow = type(toggle) == "table" and Kit.PageButton(toggle, "right")
        if arrow and type(panel) == "table" and panel.HookScript then
            local function point()
                arrow:SetRotation(panel:IsShown() and Kit.ROTATION.left or Kit.ROTATION.right)
            end
            panel:HookScript("OnShow", point)
            panel:HookScript("OnHide", point)
            point()
        end
        if type(panel) == "table" and panel.HookScript and not dressedSlots[panel] then
            dressedSlots[panel] = true
            -- The game fills it just before its OnShow runs.
            panel:HookScript("OnShow", function() itemSlots(Kit, panel) end)
            -- Trying on an item refills the list next frame (MarkDirty),
            -- possibly with a newly created slot.
            local scene = f.ModelScene
            if type(scene) == "table" and scene.HookScript then
                scene:HookScript("OnDressModel", function()
                    C_Timer.After(0, function()
                        C_Timer.After(0, function() itemSlots(Kit, panel) end)
                    end)
                end)
            end
        end
        itemSlots(Kit, panel)
        setList(Kit, f.SetSelectionPanel)
    end })

-- The small dressing room beside the auction house: window look, race
-- backdrop kept.
Engine.Window({ key = "sidedressup", pack = "collections", frame = "SideDressUpFrame", watch = true,
    window = { keep = { "BGTopLeft", "BGBottomLeft" } },
    after = function(Kit, f)
        modelControls(Kit, f.ModelScene)
    end })
