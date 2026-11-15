-- The game's own spellbook and talents window, in the Daylight UI look, for players
-- who pick it over Daylight UI's (Win.Swap), and for the times Daylight UI's lends
-- it out (an inspected tree, the spec tab). Never walked while Daylight UI's covers it.

local _, ns = ...
local Engine = ns.Engine

local function covered()
    local B = DaylightUI.Book and DaylightUI.Book.Window
    return type(B) == "table" and type(B.Covers) == "function" and B.Covers() == true
end

-- The glow behind each of the spellbook's category headers ("General") and
-- behind each spell, which the game fades in under the mouse: kept hidden.
local function hideBackplates(Kit, frame, depth)
    if type(frame) ~= "table" or not frame.GetChildren or depth > 10 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    Kit.Erase(frame.Backplate)
    for _, c in ipairs({ frame:GetChildren() }) do hideBackplates(Kit, c, depth + 1) end
end

-- The talent trees keep their spec art. The frame drawn round and between them
-- (the band along the top, the gold inner frame, the dividers, the unspent
-- points' box, each tree header's divider and box) goes, so the trees sit on
-- the Daylight UI window.
local function talentHeaders(Kit, frame, depth)
    if type(frame) ~= "table" or not frame.GetChildren or depth > 6 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    if frame.MainRing and frame.TextBackground then
        Kit.Hide(frame.TextBackground)
        Kit.Hide(frame.Divider)
    end
    for _, c in ipairs({ frame:GetChildren() }) do talentHeaders(Kit, c, depth + 1) end
end

local pagingHooked = setmetatable({}, { __mode = "k" })

-- The spellbook's parchment goes (its text made light); the talent trees and
-- specialization tiles keep their art, which is what they show.
Engine.Window({ key = "playerspells", pack = "system", addon = "Blizzard_PlayerSpells", frame = "PlayerSpellsFrame",
    watch = true, skip = covered,
    hide = { ".SpellBookFrame.BookBGLeft", ".SpellBookFrame.BookBGRight", ".SpellBookFrame.BookBGHalved",
             ".SpellBookFrame.TopBar", ".SpellBookFrame.BookCornerFlipbook",
             ".SpecFrame.BlackBG", ".SpecFrame.Background",
             ".TalentsFrame.Background", ".TalentsFrame.BackgroundBorder",
             ".TalentsFrame.DividerHorizontalLeft", ".TalentsFrame.DividerHorizontalRight",
             ".TalentsFrame.DividerVerticalLeft", ".TalentsFrame.DividerVerticalRight",
             ".TalentsFrame.ClassCurrencyDisplay.Border" },
    after = function(Kit, f, again)
        local book = f.SpellBookFrame
        if type(book) == "table" then
            Kit.LightAll(book, nil, 10, true)
            hideBackplates(Kit, book, 0)
            -- Turning a page or picking a category shows spells the book may
            -- have only just made, so they're gone over again. The book says
            -- when its shown spells change, so no hook on its methods.
            if again and not pagingHooked[book] then
                pagingHooked[book] = true
                local reg = _G.EventRegistry
                if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
                    reg:RegisterCallback("PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged", again, pagingHooked)
                end
                local paged = book.PagedSpellsFrame
                local controls = type(paged) == "table" and paged.PagingControls
                if type(controls) == "table" then
                    for _, key in ipairs({ "PrevPageButton", "NextPageButton" }) do
                        if type(controls[key]) == "table" and controls[key].HookScript then controls[key]:HookScript("OnClick", again) end
                    end
                end
                if type(paged) == "table" and paged.HookScript then paged:HookScript("OnMouseWheel", again) end
            end
        end
        talentHeaders(Kit, f.TalentsFrame, 0)
    end })
