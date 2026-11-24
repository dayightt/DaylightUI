-- The Auction House options, as data: their own section in the options window.
-- With DaylightMogul loaded every page is hidden: Mogul owns the Auction House then.

local _, ns = ...

local lookRows = DaylightUI.Options.LookRows("frameStyle", nil)

ns.DEFAULTS = {
    -- Daylight UI's Auction House window instead of the game's; switched from either window.
    enabled = true,
    scale = 1,
    openOn = "buy",           -- buy, sell, auctions, or last (the tab left open last time)
    frameStyle = DaylightUI.Style.LookDefaults(), -- borders, shadows and background, or General's (Style.LookOf)
    askHigh = true,           -- a buy over askAbove of the usual price asks once more
    askAbove = 1.5,
    dealBelow = 0.7,          -- a price at or under this share of the usual one shows as a deal
    -- Copper under the cheapest when Sell fills a price (gear rounds to whole silver).
    -- 0 posts at the same price: undercutting by a copper only drags the price down.
    undercut = 0,
    undercutPct = 0,          -- a share under the cheapest instead (0 = the copper above)
    chatPosts = false,        -- a chat line for each post
    undercutAhead = 0,        -- My auctions: this many cheaper ones from others still count as fine
    hours = 24,               -- auction length, also Sell's last pick (2, 8 or 24)
    bagClick = "both",        -- which click on a bag item puts it on Sell: right, alt or both
    tooltip = true,
    tooltipUsual = false,     -- the usual price repeats the auction line on most items
    tooltipAge = true,
    tooltipStack = true,
    keepDays = 60,            -- an item not seen for this many days is forgotten at login
}

local function mogul() return DaylightUI.ahMogul == true end

local function askOff(get) return get("askHigh") ~= true end
local function tipOff(get) return get("tooltip") ~= true end

local function forget(field)
    if ns.BuyPage and ns.BuyPage.Forget then ns.BuyPage.Forget(field) end
end

local function forgetPrices()
    local rkey = ns.Ruleset and ns.Ruleset.Key()
    if not rkey then return end
    ns.Store.Clear(rkey)
    ns.Fire("PricesChanged", rkey)
end

ns.OPTIONS = { pages = {
    { id = "window", label = "Window",
      desc = "Buy, sell and your auctions in one window, with prices remembered from your searches.",
      hidden = mogul,
      groups = {
        { label = "Window", items = {
            { type = "toggle", key = "enabled", label = "Daylight UI style Auction House window",
              desc = "Talking to an auctioneer shows Daylight UI's window. Turn it off to use the game's own window, for addons that build on it. Each window also has a button to switch to the other." },
            { type = "dropdown", key = "openOn", label = "Auction House opens on",
              values = { buy = "Buy", sell = "Sell", auctions = "My auctions", last = "The tab you left open" },
              order = { "buy", "sell", "auctions", "last" },
              desc = "Which tab shows when you talk to an auctioneer. Pick Sell if you mostly come to post, or the tab you left open to carry on where you were." },
            { type = "slider", key = "scale", label = "Auction House scale", min = 0.7, max = 1.3, step = 0.05, unit = "x",
              desc = "How big the window is. Ctrl and the mouse wheel over the window changes it too." },
        } },
        { label = "Borders and background", items = lookRows },
    } },
    { id = "trade", label = "Buying and selling",
      desc = "How Buy warns you about prices and how Sell prices your items.",
      hidden = mogul,
      groups = {
        { label = "Buying", items = {
            { type = "toggle", key = "askHigh", label = "Ask before paying over the usual price",
              desc = "A buy priced well above what the item usually costs asks you once more before it goes through. When off, every buy goes through on the second click." },
            { type = "slider", key = "askAbove", label = "Ask above", min = 1.1, max = 5, step = 0.1, unit = "%",
              disabled = askOff,
              desc = "How far over the usual price a buy has to be before it asks. At 150%, an item that usually costs 10 gold asks above 15 gold. Prices over it show in orange either way." },
            { type = "slider", key = "dealBelow", label = "Deal price", min = 0.3, max = 0.95, step = 0.05, unit = "%",
              desc = "Prices at or under this much of the usual price show in green as a deal." },
            { type = "button", label = "Clear recent searches", text = "Clear", confirm = true,
              desc = "Empties the Recent list on the Buy tab.",
              func = function() forget("recent") end },
            { type = "button", label = "Clear favorites", text = "Clear", confirm = true,
              desc = "Empties the Favorites list on the Buy tab. Right-click an item in the results to add it again.",
              func = function() forget("favorites") end },
        } },
        { label = "Selling", items = {
            { type = "slider", key = "undercut", label = "Undercut by", min = 0, max = 100, step = 1, unit = "c",
              disabled = function(get) return (get("undercutPct") or 0) > 0 end,
              desc = "How far under the cheapest one up Sell puts your price, in copper. Gear and recipes go a whole silver under, as the game only takes them in silver." },
            { type = "slider", key = "undercutPct", label = "Undercut by percent", min = 0, max = 0.2, step = 0.01, unit = "%",
              desc = "Goes a share under the cheapest instead, like 5% under. At 0% Sell uses the copper above." },
            { type = "dropdown", key = "hours", label = "Auction length",
              values = { [2] = "2 hours", [8] = "8 hours", [24] = "24 hours" }, order = { 2, 8, 24 },
              desc = "How long a new auction stays up. Picking another length on the Sell tab changes this too. Longer auctions cost a bigger deposit." },
            { type = "dropdown", key = "bagClick", label = "Sell from your bags with",
              values = { both = "Right-click or Alt-click", right = "Right-click", alt = "Alt-click" },
              order = { "both", "right", "alt" },
              desc = "Which click on an item in your bags puts it on the Sell tab while the Auction House is open. Works with Daylight UI's bags." },
            { type = "toggle", key = "chatPosts", label = "A chat line for each post",
              desc = "Each auction you post from Sell is written in chat with its price, so you can look back at what you put up." },
        } },
        { label = "My auctions", items = {
            { type = "slider", key = "undercutAhead", label = "Leave it up with this many cheaper", min = 0, max = 50, step = 1,
              desc = "My auctions marks yours as undercut only when more than this many items from others are cheaper than yours. At 0, one cheaper item is enough. A few cheap ones often sell out by themselves." },
        } },
    } },
    { id = "prices", label = "Prices",
      desc = "Auction prices on item tooltips, and how long they're remembered.",
      hidden = mogul,
      groups = {
        { label = "Tooltip", items = {
            { type = "toggle", key = "tooltip", label = "Auction prices on item tooltips",
              desc = "Every item tooltip shows what the cheapest one cost the last time you saw it at the Auction House. Items you've never seen there show nothing." },
            { type = "toggle", key = "tooltipUsual", label = "Usual price on item tooltips", disabled = tipOff,
              desc = "Adds what the item has usually cost over the last two weeks, under its auction price." },
            { type = "toggle", key = "tooltipAge", label = "How old the auction price is", disabled = tipOff,
              desc = "Adds when the price was seen, like \"Seen 2 h ago\", so you know how fresh it is." },
            { type = "toggle", key = "tooltipStack", label = "Shift for the whole stack", disabled = tipOff,
              desc = "Holding Shift over a stack in your bags prices the whole stack instead of one." },
        } },
        { label = "Price memory", items = {
            { type = "slider", key = "keepDays", label = "Days to keep an unseen price", min = 7, max = 120, step = 1,
              desc = "An item you haven't seen at the Auction House for this many days is forgotten when you log in, so old prices don't hang around." },
            { type = "button", label = "Forget every price", text = "Forget", confirm = true,
              desc = "Forgets every remembered price on this realm. Searches and a full scan fill them in again.",
              func = forgetPrices },
        } },
    } },
} }
