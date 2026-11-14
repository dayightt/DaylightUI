-- Bag options pages, as data. The Categories page draws its group list as a
-- custom item: rename, reorder, edit a custom group's search, delete any group
-- except Other and Empty, plus a row to add one or restore a deleted built-in.

local _, ns = ...
local DUI = DaylightUI
local L = DUI.L

local function off(get) return get("enabled") ~= true end
local backRows = DaylightUI.Options.BackAlphaRows("windowAlpha", "Bags", off, "1.6.2")
-- Bank look rows only apply while the bank follows the bags (bank.ownLook off).
local function sameAsBags(get) return get("bank.ownLook") ~= true end
-- Bank and alts (Viewer.lua): which rows show while it's off, and its own look rows.
local function viewerOff(get) return get("enabled") ~= true or get("viewer.enabled") ~= true end
local function viewerSame(get) return get("viewer.ownLook") ~= true end
local function motionOff() return DUI:Get("general", "motion") == false end
local function UI() return DUI.Widgets end
local function colors() return DUI.Widgets.COLORS end

local LINE = 30

function ns.RefreshOptions()
    local panel = DUI.OptionsPanel
    if panel and panel.IsShown and panel.IsShown() then panel.Refresh() end
end

-- One-line prompt with a text box (rename, search).
local function prompt(text, initial, onAccept) DUI.Widgets.Prompt(text, initial, onAccept) end

local function tooltip(b, title, desc)
    b:HookScript("OnEnter", function() UI().Tooltip(b, title, desc) end)
    b:HookScript("OnLeave", function() UI().HideTooltip() end)
end

-- Group list

local function buildLine(list)
    local W, C = UI(), colors()
    local Cat = ns.Categories
    local line = CreateFrame("Frame", nil, list)
    line:SetHeight(LINE)
    line.name = CreateFrame("Button", nil, line)
    line.name:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.name:SetSize(200, LINE - 6)
    line.name.text = W.Font(line.name, W.BODY, DUI.Style.SIZE.body, C.text)
    line.name.text:SetPoint("LEFT", line.name, "LEFT", 0, 0)
    line.name.text:SetPoint("RIGHT", line.name, "RIGHT", 0, 0)
    line.name:SetScript("OnClick", function()
        local g = Cat.Get(line.key)
        if g then prompt(string.format(L["Rename %s:"], g.name), g.name, function(v) Cat.Rename(line.key, v) end) end
    end)
    tooltip(line.name, L["Name"], L["Click to rename."])
    line.search = CreateFrame("Button", nil, line)
    line.search:SetPoint("LEFT", line.name, "RIGHT", 8, 0)
    line.search:SetSize(130, LINE - 6)
    line.search.text = W.Font(line.search, W.BODY, DUI.Style.SIZE.small, C.dim)
    line.search.text:SetPoint("LEFT", line.search, "LEFT", 0, 0)
    line.search.text:SetPoint("RIGHT", line.search, "RIGHT", 0, 0)
    line.search:SetScript("OnClick", function()
        local g = Cat.Get(line.key)
        if g and g.custom then
            prompt(string.format(L["Search for %s (e.g. potion, q>rare, a name):"], g.name), g.search,
                function(v) Cat.SetSearch(line.key, v) end, { empty = true })
        end
    end)
    tooltip(line.search, SEARCH or L["Search"], L["What this group takes. Click to change."])
    -- Right to left: delete (two clicks, not for Other or Empty), down, up.
    local del = W.DeleteButton(line)
    del:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    del.text = W.Font(line, W.BODY, DUI.Style.SIZE.small, C.warn, "RIGHT")
    del.text:SetPoint("RIGHT", del, "LEFT", -4, 0)
    local token = 0
    function del.Arm(on)
        del.armed = on
        del.text:SetText(on and L["Delete?"] or "")
        W.Tint(del.icon, on and C.warn or C.dim)
    end
    del:SetScript("OnClick", function()
        if not del.armed then
            del.Arm(true)
            token = token + 1
            local mine = token
            C_Timer.After(3, function() if token == mine then del.Arm(false) end end)
            return
        end
        token = token + 1
        del.Arm(false)
        Cat.Delete(line.key)
    end)
    del:SetScript("OnLeave", function() W.Tint(del.icon, del.armed and C.warn or C.dim) end)
    line.delete = del
    line.move = W.MoveButtons(line)
    line.move:SetPoint("RIGHT", del, "LEFT", -64, 0)   -- leave room for "Delete?"
    line.up, line.down = line.move.up, line.move.down
    -- The group's color: a swatch, and a link to go back to the default once one is set.
    line.swatch = W.Swatch(line, {},
        function() local r, g, b = Cat.Color(line.key); return r and { r, g, b } or nil end,
        function(c) Cat.SetColor(line.key, c) end)
    line.swatch:SetSize(36, 20)
    line.swatch:SetPoint("RIGHT", line.move, "LEFT", -12, 0)
    tooltip(line.swatch, L["Group color"], L["The color of this group's heading and its name in menus. Click to change."])
    line.reset = W.Link(line)
    line.reset.SetLabel(L["Reset"])
    line.reset:SetPoint("RIGHT", line.swatch, "LEFT", -8, 0)
    line.reset:SetScript("OnClick", function() Cat.ResetColor(line.key) end)
    line.down:SetScript("OnClick", function() Cat.Move(line.key, 1) end)
    line.up:SetScript("OnClick", function() Cat.Move(line.key, -1) end)
    tooltip(line.up, L["Move up"], L["Where this group sits in the bag."])
    tooltip(line.down, L["Move down"], L["Where this group sits in the bag."])
    return line
end

local function updateLine(line, key, order, i)
    local g = ns.Categories.Get(key)
    line.key = key
    line.name.text:SetText(g.name .. (g.custom and "  " .. DUI.Win.Parts.Hex(DUI.Style.INK.LABEL) .. L["custom"] .. "|r" or ""))
    line.search.text:SetText(g.custom and (g.search or L["Only what you move here"]) or "")
    line.search:EnableMouse(g.custom == true)
    local colored = key ~= "recent"
    line.swatch:SetShown(colored)
    line.swatch.Refresh()
    line.reset:SetShown(colored and ns.Categories.HasOwnColor(key))
    line.delete.SetUsable(ns.Categories.CanDelete(key))
    line.up.SetUsable(i > 1)
    line.down.SetUsable(i < #order)
    if line.shownKey ~= key then line.delete.Arm(false) end
    line.shownKey = key
end

local groupList = {
    type = "custom", label = "Groups",
    build = function(row)
        row.lines = {}
        row.list = CreateFrame("Frame", nil, row)
        row.list:SetPoint("TOPLEFT", row, "TOPLEFT", UI().PAD, -4)
        row.list:SetPoint("TOPRIGHT", row, "TOPRIGHT", -UI().PAD, -4)
    end,
    update = function(row)
        local order = ns.Categories.Order()
        for i, key in ipairs(order) do
            local line = row.lines[i]
            if not line then
                line = buildLine(row.list)
                row.lines[i] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row.list, "TOPLEFT", 0, -(i - 1) * LINE)
            line:SetPoint("TOPRIGHT", row.list, "TOPRIGHT", 0, -(i - 1) * LINE)
            updateLine(line, key, order, i)
            UI().Stripe(line, i % 2 == 0)
            line:Show()
        end
        for i = #order + 1, #row.lines do row.lines[i]:Hide() end
        row.count = #order
        row.list:SetHeight(math.max(1, #order * LINE))
    end,
    height = function(row) return (row.count or #ns.Categories.Order()) * LINE + 8 end,
}

-- New custom group: just a name. It sits in the bag waiting for items, and its
-- line above takes a search.
local addGroup = {
    type = "custom", label = "Add a group",
    build = function(row)
        local W = UI()
        local go = W.Button(row, L["Add a group"], 26)
        go:SetWidth(140)
        go:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
        row.add = go
        go:SetScript("OnClick", function()
            prompt(L["A name for the new group:"], "", function(name) ns.Categories.AddCustom(name) end)
        end)
        local clear = W.Button(row, L["Clear moved items"], 26)
        clear:SetWidth(170)
        clear:SetPoint("LEFT", go, "RIGHT", 10, 0)
        clear:SetScript("OnClick", function() ns.Categories.ClearPins() end)
        tooltip(clear, L["Clear moved items"], L["Every item you dragged onto a group, or moved with Alt-right-click, goes back to its own group."])
        local back = W.Button(row, L["Bring back a group"], 26)
        back:SetWidth(170)
        back:SetPoint("LEFT", clear, "RIGHT", 10, 0)
        row.back = back
        back:SetScript("OnClick", function()
            local Cat = ns.Categories
            local keys, values = Cat.Removed(), {}
            for _, k in ipairs(keys) do values[k] = Cat.ColorText(k, Cat.BY_KEY[k].name) end
            W.OpenMenu(back, keys, values, nil, function(k) Cat.Restore(k) end)
        end)
        tooltip(back, L["Bring back a group"], L["A group you deleted comes back, with its items."])
    end,
    update = function(row)
        if row.back then row.back.SetOff(#ns.Categories.Removed() == 0) end
    end,
    height = function() return 42 end,
}

-- Export and import custom groups as text (Categories.lua sharing), using the
-- profiles' copy/paste box.
local shareGroups = {
    type = "custom", label = "Share your groups",
    build = function(row)
        local W = UI()
        local P = DUI.Profiles
        local out = W.Button(row, L["Export groups"], 26)
        out:SetWidth(140)
        out:SetPoint("LEFT", row, "LEFT", W.PAD, 0)
        row.out = out
        out:SetScript("OnClick", function()
            local text = ns.Categories.Export()
            if not text then return end
            P.ShowText(L["Export bag groups"], L["Your own groups: their names, searches and the items you moved to them. Ctrl+C to copy, then share it."],
                P.Wrap(text))
        end)
        tooltip(out, L["Export groups"], L["Your own groups as text to copy: paste it on another character, or give it to a friend."])
        local inn = W.Button(row, L["Import groups"], 26)
        row.inn = inn
        inn:SetWidth(140)
        inn:SetPoint("LEFT", out, "RIGHT", 10, 0)
        inn:SetScript("OnClick", function()
            local typed, lost
            local box = P.ShowPaste({
                title = L["Import bag groups"],
                hint = L["Paste bag groups (Ctrl+V), from Daylight UI or Baganator. A group with the same name as one of yours is updated; the others are added."],
                read = function(text)
                    local list, why = ns.Categories.ReadShared(ns.Categories.Unwrapped(text, typed))
                    if not list then return nil, why end
                    local names = {}
                    for _, g in ipairs(list) do
                        if g.name then names[#names + 1] = g.name end
                    end
                    local said
                    if #names == 0 then
                        said = L["Only items moved to Baganator's own categories: they go to the same groups here."]
                    else
                        local more = #names > 5 and string.format(L[", and %d more"], #names - 5) or ""
                        said = string.format(L["%d groups: %s%s."], #names, table.concat(names, ", ", 1, math.min(5, #names)), more)
                    end
                    if list.notes and #list.notes > 0 then
                        said = said .. " " .. L["Some Baganator rules have no match here. Chat lists them after you import."]
                    end
                    if lost and list.baganator then
                        said = said .. " " .. L["Editing the text here took out its spaces, so paste it again to keep them."]
                    end
                    return list, said
                end,
                go = function(list)
                    local n, moved = ns.Categories.ImportShared(list)
                    for _, line in ipairs(ns.Categories.ImportLines(n, moved, list.notes)) do DUI.Print(line) end
                end,
            })
            -- The box takes spaces out of long pasted text, and Unwrapped puts them
            -- back from the paste. Once the wrapped text is edited they're gone.
            local edit = type(box) == "table" and box.edit
            local check = edit and edit:GetScript("OnTextChanged")
            if check then
                edit:SetScript("OnTextChanged", function(self, user)
                    if user then
                        local now = self:GetText()
                        if ns.Categories.Unwrapped(now, typed) ~= typed then
                            lost = type(typed) == "string" and string.find(typed, "%s") ~= nil
                                and not string.find(now, " ", 1, true)
                            typed = now
                        end
                    end
                    check(self, user)
                end)
            end
        end)
        tooltip(inn, L["Import groups"], L["Bag groups someone shared, or your Baganator categories, added to yours."])
    end,
    update = function(row)
        if row.out then row.out.SetOff(ns.Categories.ShareTable() == nil) end
    end,
    height = function() return 42 end,
}

-- The Soul Shard rows are for warlocks only.
local function notWarlock() return not ns.Junk.IsWarlock() end

ns.OPTIONS = { pages = {
    { id = "bags", label = "Bags",
      desc = "All your bags in one window, profession bag and keyring included. It opens the same way the game's bags do.",
      groups = {
        { label = "Bag", items = {
            { type = "toggle", key = "enabled", label = "Replace the game's bags", reload = true,
              desc = "When off, the game's own bag windows are used." },
            { type = "toggle", key = "moneyRoll", label = "Count gold changes",
              disabled = function(get) return off(get) or motionOff() end,
              desc = "The gold at the bottom of the bag counts up or down to its new amount. Needs Motion effects (General > Appearance)." },
            { type = "slider", key = "shardsKeep", label = "Keep at most this many Soul Shards", min = 0, max = 40, step = 1, disabled = off, hidden = notWarlock,
              desc = "Carry more and the bag shows a Delete extra shards button above your money. It deletes nothing until you click it twice. At 0 it never shows." },
            { type = "slider", key = "shardsKeepRaid", label = "Keep at most this many Soul Shards in a raid", min = 0, max = 40, step = 1, disabled = off, hidden = notWarlock,
              desc = "The same, while you're in a raid, where you may want more on hand. At 0 it never shows in a raid." },
        } },
        { label = "Layout", items = {
            { type = "dropdown", key = "view", label = "Arrange items", disabled = off,
              values = { categories = "Shelf (grouped by kind)", grid = "Grid (bag by bag)", list = "List (a row per item)" }, order = { "categories", "grid", "list" },
              desc = "Shelf groups your items by kind, with a heading for each group. Grid is one even grid, bag by bag. List shows a row per item under the same groups, with its kind, level, count and price; click a column to sort. You can also switch with the button next to the search box. In the grid, Alt-right-click an item to keep it in its slot when you clean up." },
            { type = "slider", key = "columns", label = "Columns", min = 6, max = 20, step = 1, disabled = off,
              desc = "How many slots fit in each row of the bag. More columns make it wider and shorter." },
            { type = "slider", key = "iconSize", label = "Slot size", min = 24, max = 48, step = 1, unit = "px", disabled = off,
              desc = "How big each item slot is in the bag." },
            { type = "slider", key = "spacing", label = "Spacing", min = 0, max = 16, step = 1, unit = "px", disabled = off,
              desc = "Gap between slots." },
            { type = "slider", key = "scale", label = "Scale", min = 0.5, max = 1.5, step = 0.05, unit = "x", disabled = off,
              desc = "The whole bag window, slots, text and buttons together." },
            backRows[1], backRows[2],
            { type = "toggle", key = "autoStack", label = "Stack items when the bag opens", disabled = off,
              desc = "Opening your bag fills up part stacks of the same item (15 and 5 Linen Cloth become 20), so no slot is wasted. Not in combat, or while you trade or have the mailbox or auction house open." },
            { type = "toggle", key = "reagentMerged", label = "Mix profession bag with other bags", disabled = off,
              desc = "Profession bag slots follow your other bags' slots. When off, they get their own section below a thin line." },
            { type = "toggle", key = "showKeyring", label = "Show keyring", disabled = off,
              desc = "Your keyring's slots, in their own section at the end of the bag. When off, keys stay on the keyring, out of sight. The key on the bag slots bar does the same." },
            { type = "dropdown", key = "emptySlots", label = "Empty slots", disabled = off,
              values = { all = "Every empty slot", grouped = "One tile with the count" }, order = { "all", "grouped" },
              desc = "One tile: each section shows a single empty slot with the free count on it. Drop an item on it to put it there." },
        } },
        { label = "Item icons", desc = "What each item's icon shows.", items = {
            { type = "toggle", key = "greyPoor", label = "Dim gray (junk) items", disabled = off,
              desc = "Gray-quality items are grayed out and faded, so junk stands out at a glance." },
            { type = "toggle", key = "redUnusable", label = "Tint items you can't use red", disabled = off,
              desc = "Items your class, level or skills can't use yet, or that you already know, get a red icon, as at a vendor." },
            { type = "toggle", key = "showBind", label = "Show BoE / BoU", disabled = off,
              desc = "A small BoE (binds when equipped) or BoU (binds when used) in the top left corner, until the item is bound to you." },
            { type = "toggle", key = "showSet", label = "Mark equipment set items", disabled = off,
              desc = "A small dot in the top right corner on items that are part of one of your equipment sets." },
            { type = "toggle", key = "showLevel", label = "Show item level", disabled = off,
              desc = "The item level of weapons and armor in the bottom left corner." },
            { type = "toggle", key = "showJunk", label = "Show a gold coin on junk", disabled = off,
              desc = "Shows the game's small gold coin on gray items, like the default bags." },
            { type = "toggle", key = "markCheapJunk", label = "Mark the cheapest junk", disabled = off,
              desc = "A small dot on the bottom left corner of the gray item worth the least, so when your bag is full you know what to throw away. Its tooltip says what it sells for." },
        } },
        { label = "Vendors", items = {
            { type = "toggle", key = "sellJunk", label = "Sell junk automatically", disabled = off,
              desc = "Opening a vendor sells everything in the Junk group: gray items, and anything you've moved to Junk yourself. Chat shows how much you got." },
            { type = "toggle", key = "autoRepair", label = "Repair automatically", disabled = off,
              desc = "Opening a vendor that repairs fixes all your gear, and chat shows the cost. Not in combat." },
            { type = "toggle", key = "repairGuild", label = "Use guild money first",
              disabled = function(get) return get("enabled") ~= true or get("autoRepair") ~= true end,
              desc = "Pays for repairs from the guild bank when your guild allows it. Otherwise you pay." },
        } },
        { label = "Footer", items = {
            { type = "toggle", key = "showCurrency", label = "Show tracked currencies", disabled = off,
              desc = "The currencies you're tracking (as the game's own backpack list shows them), with their icon and count, beside your money." },
        } },
    } },
    { id = "bags_bank", label = "Bank",
      desc = "The bank in the same look as your bags. Groups and moved items are shared with your bags.",
      groups = {
        { label = "Layout", items = {
            -- First, since most of this page follows the Bags page and hides while it's on.
            { type = "toggle", label = "Same look as your bags", disabled = off,
              desc = "Slot size, spacing, scale, how items are arranged, empty slots and item icon marks follow your Bags page. Turn it off to set them for the bank alone: their rows show below.",
              get = function() return DaylightUI:Get("Bags", "bank.ownLook") ~= true end,
              set = function(v) DaylightUI:Set("Bags", "bank.ownLook", not v) end,
              default = function() return true end },
            { type = "slider", key = "bank.columns", label = "Bank columns", min = 6, max = 24, step = 1, disabled = off,
              desc = "Slots per row in the bank. It holds more than your bags, so it's wider by default." },
            { type = "slider", key = "bank.iconSize", label = "Bank slot size", min = 24, max = 48, step = 1, unit = "px",
              disabled = off, hidden = sameAsBags, desc = "How big each item slot is in the bank." },
            { type = "slider", key = "bank.spacing", label = "Bank spacing", min = 0, max = 16, step = 1, unit = "px",
              disabled = off, hidden = sameAsBags, desc = "Gap between slots." },
            { type = "slider", key = "bank.scale", label = "Bank scale", min = 0.5, max = 1.5, step = 0.05, unit = "x",
              disabled = off, hidden = sameAsBags, desc = "The whole bank window, slots, text and buttons together." },
            { type = "dropdown", key = "bank.view", label = "Arrange bank items", disabled = off, hidden = sameAsBags,
              values = { categories = "Shelf (grouped by kind)", grid = "Grid (tab by tab)" }, order = { "categories", "grid" },
              desc = "Shelf groups the bank by kind. Grid shows it tab by tab. You can also switch with the button next to the search box." },
            { type = "dropdown", key = "bank.emptySlots", label = "Bank empty slots", disabled = off, hidden = sameAsBags,
              values = { all = "Every empty slot", grouped = "One tile with the count" }, order = { "all", "grouped" },
              desc = "One tile: each section of the bank shows a single empty slot with the free count on it. Drop an item on it to put it there." },
        } },
        { label = "Item icons", desc = "What each item's icon shows in the bank.", items = {
            { type = "toggle", key = "bank.greyPoor", label = "Dim gray (junk) items in the bank", disabled = off, hidden = sameAsBags,
              desc = "Gray-quality items in the bank are grayed out and faded, so junk stands out at a glance." },
            { type = "toggle", key = "bank.redUnusable", label = "Tint items you can't use red in the bank", disabled = off, hidden = sameAsBags,
              desc = "Bank items your class, level or skills can't use yet, or that you already know, get a red icon, as at a vendor." },
            { type = "toggle", key = "bank.showBind", label = "Show BoE / BoU in the bank", disabled = off, hidden = sameAsBags,
              desc = "A small BoE (binds when equipped) or BoU (binds when used) in the top left corner of bank items, until the item is bound to you." },
            { type = "toggle", key = "bank.showSet", label = "Mark equipment set items in the bank", disabled = off, hidden = sameAsBags,
              desc = "A small dot in the top right corner on bank items that are part of one of your equipment sets." },
            { type = "toggle", key = "bank.showLevel", label = "Show item level in the bank", disabled = off, hidden = sameAsBags,
              desc = "The item level of weapons and armor in the bank, in the bottom left corner." },
            { type = "toggle", key = "bank.showJunk", label = "Show a gold coin on junk in the bank", disabled = off, hidden = sameAsBags,
              desc = "Shows the game's small gold coin on gray items in the bank, like the default bags." },
        } },
    } },
    { id = "bags_viewer", label = "Bank and alts",
      desc = "Your bank from anywhere, and your other characters' bags and banks.",
      groups = {
        { label = "Bank and alts", items = {
            { type = "toggle", key = "viewer.enabled", label = "Bank and alts window", disabled = off,
              desc = "Each character's bags are saved when you log out, and its bank each time you visit a banker. See them anywhere: right-click the bag icon at the top of your bags, or /dui bank. When off, Alts leaves that menu and nothing new is saved." },
        } },
        { label = "Layout", items = {
            { type = "toggle", label = "Same look as your bags", disabled = viewerOff,
              desc = "Slot size, spacing, scale, how items are arranged, empty slots and item icon marks follow your Bags page. Turn it off to set them for Bank and alts alone: their rows show below.",
              get = function() return DaylightUI:Get("Bags", "viewer.ownLook") ~= true end,
              set = function(v) DaylightUI:Set("Bags", "viewer.ownLook", not v) end,
              default = function() return true end },
            { type = "slider", key = "viewer.columns", label = "Bank and alts columns", min = 6, max = 24, step = 1, disabled = viewerOff,
              desc = "Slots per row in the Bank and alts window." },
            { type = "slider", key = "viewer.iconSize", label = "Bank and alts slot size", min = 24, max = 48, step = 1, unit = "px",
              disabled = viewerOff, hidden = viewerSame, desc = "How big each item slot is in the Bank and alts window." },
            { type = "slider", key = "viewer.spacing", label = "Bank and alts spacing", min = 0, max = 16, step = 1, unit = "px",
              disabled = viewerOff, hidden = viewerSame, desc = "Gap between slots." },
            { type = "slider", key = "viewer.scale", label = "Bank and alts scale", min = 0.5, max = 1.5, step = 0.05, unit = "x",
              disabled = viewerOff, hidden = viewerSame, desc = "The whole Bank and alts window, slots, text and buttons together." },
            { type = "dropdown", key = "viewer.view", label = "Arrange Bank and alts items", disabled = viewerOff, hidden = viewerSame,
              values = { categories = "Shelf (grouped by kind)", grid = "Grid (bag by bag)" }, order = { "categories", "grid" },
              desc = "Shelf groups items by kind. Grid shows them bag by bag. You can also switch with the button next to the search box." },
            { type = "dropdown", key = "viewer.emptySlots", label = "Bank and alts empty slots", disabled = viewerOff, hidden = viewerSame,
              values = { all = "Every empty slot", grouped = "One tile with the count" }, order = { "all", "grouped" },
              desc = "One tile: each section shows a single empty slot with the free count on it." },
        } },
        { label = "Item icons", desc = "What each item's icon shows in the Bank and alts window.", items = {
            { type = "toggle", key = "viewer.greyPoor", label = "Dim gray (junk) items in Bank and alts", disabled = viewerOff, hidden = viewerSame,
              desc = "Gray-quality items are grayed out and faded, so junk stands out at a glance." },
            { type = "toggle", key = "viewer.showBind", label = "Show BoE / BoU in Bank and alts", disabled = viewerOff, hidden = viewerSame,
              desc = "A small BoE (binds when equipped) or BoU (binds when used) in the top left corner, until the item is bound." },
            { type = "toggle", key = "viewer.showLevel", label = "Show item level in Bank and alts", disabled = viewerOff, hidden = viewerSame,
              desc = "The item level of weapons and armor in the bottom left corner." },
        } },
    } },
    { id = "bags_categories", label = "Categories",
      desc = "Items sorted into groups by type. To move an item to another group, drag it onto that group's heading or Alt-right-click it. Click a heading to collapse it; right-click Recent to clear it. Alt-right-click also locks an item so it's never sold or disenchanted.",
      groups = {
        { label = "In categories", items = {
            { type = "toggle", key = "combineStacks", label = "Combine stacks", disabled = off,
              desc = "With items in categories, stacks of the same item show as one, with the total. They show apart while you trade or have the mailbox or auction house open, so you can Shift-click one to split it." },
            { type = "toggle", key = "stackShards", label = "Stack Soul Shards", disabled = off,
              desc = "With items in categories, your Soul Shards show as one, with how many you have, though each still takes its own slot." },
            { type = "slider", key = "recentMinutes", label = "Keep new items in Recent (minutes)", min = 1, max = 60, step = 1, disabled = off,
              desc = "How long a new item stays in Recent before it goes to its own group. Right-click Recent to clear it sooner." },
        } },
        { label = "Groups", desc = "Listed in bag order. An item that fits several groups goes to the most specific one (a gray weapon goes to Junk). Your own groups are checked first.", items = {
            groupList,
        } },
        { label = "Your own groups", desc = "A new group starts empty. Hold Shift while dragging an item to see your empty groups in the bag, and drop it on one's name. Or click the search beside it here to fill it by itself.", items = {
            addGroup,
            shareGroups,
            { type = "toggle", key = "emptyGroups", label = "Show empty groups", disabled = off,
              desc = "Your groups with nothing in them always show in the bag. When off, they show only while you hold Shift with an item on the cursor." },
        } },
    } },
} }
