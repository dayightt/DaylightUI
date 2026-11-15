-- The game's own Lfg window, in the Daylight UI look, for players who pick it over
-- Daylight UI's (Win.Swap). Never walked while Daylight UI's window covers it.

local _, ns = ...
local Engine = ns.Engine

-- One window with three pages drawn over it, each a framed window of its own (list
-- yourself, browse groups, who's around). The pages' frames go so they sit on the
-- shell. Category buttons keep their pictures, on the row outline.
local function page(Kit, p)
    if type(p) ~= "table" or not p.GetRegions then return end
    Kit.Strip(p)
    Kit.Hide(p.NineSlice)
    Kit.Strip(p.PortraitContainer)
    Kit.Inset(p.Inset)
    Kit.Strip(p.RolesSection)
    Kit.Strip(p.DividerFrame)
    -- Backgrounds the game sets again as you pick a category: kept hidden.
    if type(p.Inset) == "table" then Kit.Erase(p.Inset.CustomBG) end
    Kit.Erase(p.Bg)
    Kit.Erase(p.BackgroundArt)
    -- Each page has its own title (the page covers the window), placed in the
    -- title row like every window's.
    local title = type(p.TitleContainer) == "table" and p.TitleContainer.TitleText
    Kit.Font(title, DaylightUI.Style.SIZE.title)
    Kit.Light(title)
    Kit.Title(p, title)
end

local function categoryButton(Kit, b)
    if type(b) ~= "table" or not b.CreateTexture then return end
    Kit.Hide(b.Cover)
    local keep = {}
    if Kit.Kind(b.Icon) == "Texture" then keep[b.Icon] = true end
    Kit.Row(b, keep)
    Kit.Font(b.Label)
end

local function covered()
    local L = DaylightUI.Lfg and DaylightUI.Lfg.Window
    return type(L) == "table" and type(L.Covers) == "function" and L.Covers() == true
end

Engine.Window({ key = "groupfinder", pack = "social", frame = "LFGParentFrame", watch = true, skip = covered,
    after = function(Kit, f)
        for _, key in ipairs({ "ListingTab", "BrowsingTab", "WhoListingTab" }) do
            Kit.SideTab(f[key], nil, Kit.SIDE_TAB_CROP)
        end
        for _, name in ipairs({ "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame" }) do
            page(Kit, _G[name])
        end
        local listing = _G.LFGListingFrame
        local view = type(listing) == "table" and listing.CategoryView
        local selection = type(view) == "table" and view.CategorySelection
        if type(selection) == "table" and type(selection.CategoryButtons) == "table" then
            for _, b in ipairs(selection.CategoryButtons) do categoryButton(Kit, b) end
        end
    end })
