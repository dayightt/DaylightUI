-- Commands: /dui buffs ..., and /bl for the same when the standalone
-- BuffLedger isn't loaded (it owns /bl then).

local _, BL = ...
local DUI = DaylightUI
local L = DUI.L

local HELP = {
    L["/dui buffs - open the Buffs & Debuffs options"],
    L["/dui buffs categories - open the Categories page"],
    L["/dui buffs toggle <category> - show or hide one category"],
    L["/dui buffs scan - list buffs on your group that aren't recognized"],
    L["/dui buffs auras - dump your buffs and debuffs as the client reports them"],
    L["/dui buffs test [0-1 | N% | off] - preview a sample of every known buff"],
    L["/dui buffs debug - what each bar is doing"],
}

local function printHelp()
    BL.Print(L["Buffs & Debuffs commands:"])
    for _, line in ipairs(HELP) do BL.Print("  " .. line) end
end

-- "40%", "0.4" or "40" all mean 40 percent; "off" or "0" stops.
function BL.ParseFraction(arg)
    if arg == nil or arg == "" then return BL.PREVIEW_SHARE end
    if arg == "off" or arg == "0" then return nil end
    local pct = string.match(arg, "^(%d+)%%$")
    if pct then return math.max(0, math.min(1, tonumber(pct) / 100)) end
    local n = tonumber(arg)
    if n then
        if n > 1 then n = n / 100 end
        return math.max(0, math.min(1, n))
    end
    return BL.PREVIEW_SHARE
end

local function openOptions(page)
    local panel = DUI.OptionsPanel
    if panel then panel.Show(BL.MODULE .. "." .. (page or "buffs")) end
end

local handlers = {}

handlers.help = printHelp
handlers.options = function() openOptions("buffs") end
handlers.categories = function() openOptions("categories") end

handlers.toggle = function(arg)
    if arg == "" then
        BL.Print(L["Usage: /dui buffs toggle <category name>"])
        return
    end
    local id = BL.Categories.FindByName(arg)
    if not id then
        BL.Print(string.format(L["No category called '%s'."], arg))
        return
    end
    local cat = BL.Categories.Get(id)
    BL.Categories.SetHidden(id, not cat.hidden)
    BL.Print(string.format(cat.hidden and L["%s hidden."] or L["%s shown."], BL.Categories.Label(id)))
end

handlers.scan = function() BL.Scan.PrintGroup() end
handlers.auras = function() BL.Scan.PrintPlayer() end

handlers.test = function(arg)
    local fraction = BL.ParseFraction(arg)
    -- The plain command shows a bar's worth; a share asked for shows that many.
    local max = (arg == nil or arg == "") and BL.PREVIEW_MAX or nil
    BL.Preview.Set(fraction, max)
    if fraction and max then
        BL.Print(string.format(L["Preview on: %d sample buffs. /dui buffs test off to stop; /dui buffs test 100%% for all."], max))
    elseif fraction then
        BL.Print(string.format(L["Preview on: %d%% of known buffs. /dui buffs test off to stop."], math.floor(fraction * 100 + 0.5)))
    else
        BL.Print(L["Preview off."])
    end
end

handlers.debug = function()
    if BL.Bar and BL.Bar.PrintStatus then BL.Bar:PrintStatus() end
    if BL.DebuffBar and BL.DebuffBar.PrintStatus then BL.DebuffBar:PrintStatus() end
end

function BL.RunCommand(msg)
    msg = strtrim(msg or "")
    local cmd, rest = string.match(msg, "^(%S+)%s*(.-)$")
    cmd = cmd and string.lower(cmd) or ""
    if cmd == "" then
        handlers.options()
        return
    end
    local handler = handlers[cmd]
    if handler then
        handler(rest or "")
    else
        BL.Print(string.format(L["Unknown command '%s'."], cmd))
        printHelp()
    end
end

DUI.RegisterCommand("buffs", BL.RunCommand, L["/dui buffs - buff and debuff bars (/dui buffs help for more)"])

-- By login every addon has loaded, so a standalone BuffLedger has its /bl.
DUI.On("Login", function()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BuffLedger") then return end
    if SlashCmdList.BUFFLEDGER then return end
    SLASH_DAYLIGHTUIBUFFS1 = "/bl"
    SlashCmdList.DAYLIGHTUIBUFFS = BL.RunCommand
end)
