-- Bag slot strip above the window (the tool row's bag button, or the showSlots
-- setting): equipped bags, the profession bag slot and, when the game has a
-- keyring, a key that shows or hides it (Slots.key). Drag a bag out or drop one
-- in with the game's own PickupBagFromSlot / PutItemInBag (Swap.lua empties a
-- full bag first). Hovering a bag shows its tooltip and highlights its slots
-- (empty ones too) in the accent, dimming the rest. Bank.lua reuses these pieces.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L
local Style = DUI.Style

local Slots = {}
ns.Slots = Slots

Slots.GAP = 4                -- gap above the window
Slots.APART = 8              -- extra space before the profession bag slot
Slots.EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
Slots.DIM = 0.2              -- alpha of other bags' slots while one bag is hovered
Slots.KEY_ICON = "Interface\\Icons\\INV_Misc_Key_03"
Slots.KEY_OFF = 0.45         -- key alpha while the keyring is hidden

local function invSlot(bag)
    local fn = C_Container and C_Container.ContainerIDToInventoryID
    if type(fn) ~= "function" then return nil end
    local ok, slot = pcall(fn, bag)
    return ok and type(slot) == "number" and slot or nil
end

-- Strip pieces, shared with the bank

-- While a bag is hovered, light its slots (from slots, a window's list) in the
-- accent and dim the rest. bag = nil restores everything.
function Slots.Light(slots, bag)
    for _, s in ipairs(slots) do
        local mine = bag ~= nil and s.bag == bag
        ns.Items.Fader(s.button):SetAlpha((bag == nil or mine) and 1 or Slots.DIM)
        ns.Items.Light(s.button, mine)
    end
end

-- A bag's icon (nil = empty slot) with its quality on the edge.
function Slots.Paint(b, tex, quality)
    b.icon:SetTexture(tex or Slots.EMPTY_ICON)
    local color = tex and ns.Items.QualityColor(quality) or ns.Items.EMPTY
    -- Colors are shared tables (Items.QualityColor), so compare by reference.
    if b.color == color then return end
    b.color = color
    Style.SetShellColors(b.shell, color, color)
end

-- The strip: a shell over the window's top-left corner.
function Slots.NewStrip(window)
    local strip = CreateFrame("Frame", nil, window)
    strip:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 0, Slots.GAP)
    Style.Shell(strip)
    strip.slots = {}
    return strip
end

-- One bag button in the item slot look. o: pick(), put() (item dropped on it),
-- tip(self) fills GameTooltip, lit() returns the bag to light, slots() returns
-- the window's slots.
function Slots.NewButton(strip, o)
    local b = CreateFrame("Button", nil, strip)
    b.shell = ns.Items.Frame(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    Style.CropIcon(b.icon)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1, 1, 1, 0.12)
    hl:SetAllPoints(b.icon)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function()
        if CursorHasItem and CursorHasItem() then o.put() else o.pick() end
    end)
    b:SetScript("OnDragStart", o.pick)
    b:SetScript("OnReceiveDrag", o.put)
    b:SetScript("OnEnter", function(self)
        GameTooltip:Hide()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        o.tip(self)
        GameTooltip:Show()
        Slots.Light(o.slots(), o.lit())
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        Slots.Light(o.slots(), nil)
    end)
    return b
end

-- Lays the buttons out in a row at the window's icon size and spacing
-- (b.apart adds a little room before that button).
function Slots.LayoutStrip(strip, size, gap)
    local E = ns.Window.EDGE
    local x = E
    for i, b in ipairs(strip.slots) do
        if not b:IsShown() then
            -- not in the row (the key, without a keyring)
        else
        if i > 1 and b.apart then x = x + Slots.APART end
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", strip, "TOPLEFT", x, -E)
        ns.Items.FitRing(b, b.shell)
        local T = ns.Items.Inset(b)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", T, -T)
        b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -T, T)
        x = x + size + gap
        end
    end
    strip:SetSize(math.max(1, x - gap + E), E * 2 + size)
end

-- The player's bag strip

local function paint(b)
    local inv = invSlot(b.bag)
    local tex = inv and GetInventoryItemTexture and GetInventoryItemTexture("player", inv)
    Slots.Paint(b, tex, tex and GetInventoryItemQuality and GetInventoryItemQuality("player", inv))
end

local function slotButton(strip, bag, profession)
    local function put()
        local inv = invSlot(bag)
        if ns.Swap.Try(bag, inv) then return end
        if inv and PutItemInBag then PutItemInBag(inv) end
    end
    local function pick()
        local inv = invSlot(bag)
        if inv and PickupBagFromSlot then PickupBagFromSlot(inv) end
    end
    local b = Slots.NewButton(strip, { pick = pick, put = put, slots = function() return ns.Bags.Slots() end,
        lit = function() return bag end,
        tip = function()
            local inv = invSlot(bag)
            if not (inv and GameTooltip:SetInventoryItem("player", inv)) then
                GameTooltip:SetText((profession and EQUIP_CONTAINER_REAGENT or EQUIP_CONTAINER) or L["Bag"], 1, 1, 1)
            end
        end })
    b.bag, b.apart = bag, profession
    return b
end

-- Keyring key. Click shows or hides the keyring section (showKeyring setting);
-- dropping a key on it puts it on the keyring like the game's own button does
-- (PutKeyInKeyRing). Dimmed while hidden.
local function keyOn() return ns.Setting("showKeyring") == true end

local function putKey()
    if CursorHasItem and CursorHasItem() and PutKeyInKeyRing then PutKeyInKeyRing() end
end

local function keyButton(strip)
    local b = Slots.NewButton(strip, {
        pick = function() DUI:Set("Bags", "showKeyring", not keyOn()) end,
        put = putKey,
        slots = function() return ns.Bags.Slots() end,
        lit = function() return keyOn() and KEYRING_CONTAINER or nil end,
        tip = function()
            local Tips = DUI.Tips
            Tips.Clear()
            Tips.Title(KEYRING or L["Keyring"])
            Tips.Hint(keyOn() and L["Click to hide it in your bag."] or L["Click to show it in your bag."])
            Tips.Flush(GameTooltip)
        end })
    b.apart, b.keyring = true, true
    b.icon:SetTexture(Slots.KEY_ICON)
    return b
end

-- Lit while the keyring shows, dimmed (eased) while hidden.
function Slots.PaintKey(instant)
    local b = Slots.key
    if not b then return end
    local on = keyOn()
    b.icon:SetDesaturated(not on)
    local to = on and 1 or Slots.KEY_OFF
    if b.keyAlpha == to then return end
    if instant or b.keyAlpha == nil then b.icon:SetAlpha(to)
    else DUI.Motion.Fade(b.icon, b.keyAlpha, to, DUI.Motion.FAST) end
    b.keyAlpha = to
end

function Slots.Create(window)
    local strip = Slots.NewStrip(window)
    local n = ns.Bags.NumBags()
    for bag = 1, n + ns.Bags.NumProfession() do
        strip.slots[#strip.slots + 1] = slotButton(strip, bag, bag > n)
    end
    Slots.key = keyButton(strip)
    strip.slots[#strip.slots + 1] = Slots.key
    strip:SetScript("OnShow", Slots.Refresh)
    -- Once per burst (BAG_UPDATE_DELAYED, not every BAG_UPDATE). OnShow catches up.
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }) do
        DUI.RegisterEvent(e, Slots.Refresh)
    end
    Slots.strip = strip
    Slots.Layout()
    Slots.Apply()
end

function Slots.Layout()
    if not Slots.strip then return end
    Slots.key:SetShown(ns.Bags.GameKeyring())
    Slots.PaintKey()
    Slots.LayoutStrip(Slots.strip, ns.Setting("iconSize") or 35, ns.Setting("spacing") or 2)
end

function Slots.Refresh()
    local strip = Slots.strip
    if not strip or not strip:IsVisible() then return end   -- IsShown is true for a closed window's strip too
    for _, b in ipairs(strip.slots) do paint(b) end
end

function Slots.Apply()
    if Slots.strip then Slots.strip:SetShown(ns.Setting("showSlots") == true) end
end
