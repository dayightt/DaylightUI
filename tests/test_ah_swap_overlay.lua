local AHW = require("ahworld")
local stub = require("stub")

-- The game's AuctionHouseFrame keeps listening while it's parked under
-- Daylight UI's window, so a post from that window that the game warns about
-- runs the game's own answer on the hidden frame. Handing that frame back to
-- the player must not leave its click-blocking overlay behind.

local LINEN = 2589

-- The game's frame with its dialog overlay as the game drives it
-- (wow-ui-source, forever, Blizzard_AuctionHouseFrame.xml/.lua): OnLoad
-- registers AUCTION_HOUSE_POST_WARNING and _POST_ERROR for good;
-- ShowPostConfirmationDialog shows DialogOverlay (a Button at frameLevel 1000
-- over everything below the title) and then the pop-up, whose OnHide hides
-- the overlay again; OnHide hides it too and closes the AH.
local popupUp
local function gameAH(showsPopup)
    _G.StaticPopup_Visible = function(which) return popupUp == which end
    local world = CreateFrame("Frame")
    world:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    world:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    world:SetScript("OnEvent", function(_, event, kind)
        if kind ~= AHW.AUCTIONEER then return end
        local f = rawget(_G, "AuctionHouseFrame")
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            if not f then
                f = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
                f:SetSize(800, 538)
                f.CloseButton = CreateFrame("Button", nil, f)
                f.DialogOverlay = CreateFrame("Button", nil, f)
                f.DialogOverlay:SetFrameLevel(1000)
                f.DialogOverlay:Hide()
                function f:SetDialogOverlayShown(shown) self.DialogOverlay:SetShown(shown) end
                f:RegisterEvent("AUCTION_HOUSE_POST_WARNING")
                f:RegisterEvent("AUCTION_HOUSE_POST_ERROR")
                f:SetScript("OnEvent", function(self, e)
                    self:SetDialogOverlayShown(true)
                    if showsPopup then popupUp = e end
                end)
                f:Hide()
                f:SetScript("OnHide", function(self)
                    self:SetDialogOverlayShown(false)
                    C_AuctionHouse.CloseAuctionHouse()
                end)
                stub.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI")
            end
            f:Show()
        elseif f then
            f:Hide()
        end
    end)
end

local function load(showsPopup)
    popupUp = nil
    local _, A = AHW.Load({
        commodities = { [LINEN] = true },
        auctions = { { itemID = LINEN, name = "Linen Cloth", count = 200, buyout = 200 * 10 } },
        bags = { [0] = { { itemID = LINEN, stackCount = 20, name = "Linen Cloth" } } },
        postWarning = { [LINEN] = true },
    }, {
        before = function()
            _G.AuctionHouseFrame = nil
            gameAH(showsPopup)
        end,
    })
    return A
end

local function frame(n)
    for _ = 1, n or 1 do
        AHW.Frame()
        DaylightUI.Win.Followers.Tick()
    end
end
local function game() return rawget(_G, "AuctionHouseFrame") end
local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

-- Post from Daylight UI's window at a price the game warns about, then
-- confirm it there: the game's overlay went up on the hidden frame.
local function warnedPost(A)
    AHW.Open()
    frame()
    T.truthy(A.Window.IsOpen())
    local ok, why
    stub.Key(function() ok, why = A.Post.Send("2589", 5, 1, 24) end)
    T.deq({ ok, why }, { false, "confirm" })
    stub.Key(function() A.Post.Confirm() end)
    AHW.Settle()
    T.truthy(game().DialogOverlay:IsShown(), "the game answered the warning on its hidden frame")
end

T.test("ah swap: the game's window comes back clickable after a warned post", function()
    local A = load(false)
    warnedPost(A)
    click(A.Window.frame.swap)
    frame(3)
    T.eq(game():GetParent(), UIParent)
    T.truthy(game():IsShown())
    T.falsy(game().DialogOverlay:IsShown(), "no invisible overlay left over the game's window")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("ah swap: the overlay stays while the game's own pop-up still asks", function()
    local A = load(true)
    warnedPost(A)
    click(A.Window.frame.swap)
    frame(3)
    T.truthy(game().DialogOverlay:IsShown(), "the game's pop-up takes it off when answered")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)
