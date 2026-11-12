local stub = require("stub")

local CFG = { debuffSize = 30, debuffs = true, debuffFilter = "all", maxDebuffs = 8, maxOtherDebuffs = 4,
              buffSize = 18, buffs = true, maxBuffs = 6 }

local function setup(opts)
    local _, ns = stub.Load({ module = true, login = false, before = opts and opts.before })
    local target = CreateFrame("Frame", "FakeTarget", UIParent)
    target:SetSize(220, 48)
    target.spec = { slant = "left" }   -- like the real target: its angled end inward, on the left
    local set = ns.Auras.Create(target, "left")
    return set, ns, target
end

local function copy(t, over)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

T.test("debuffs and buffs live in separate containers on the target", function()
    local set = setup()
    T.eq(set.debuffs.__unit, "target")
    T.eq(set.buffs.__unit, "target")
    T.eq(table.concat(set.debuffs.__groupOrder, ","), "mine,rest,cure", "split: no all-in-one group")
    T.eq(set.debuffs.__groups.mine.filter, "HARMFUL|PLAYER")
    T.eq(set.debuffs.__groups.cure.filter, "HARMFUL|!PLAYER|RAID_PLAYER_DISPELLABLE")
    T.eq(set.debuffs.__groups.rest.filter, "HARMFUL|!PLAYER|!RAID_PLAYER_DISPELLABLE")
    T.eq(set.debuffs.__groups.mine.layout.layoutIndex, 1, "yours first")
    T.eq(set.debuffs.__groups.cure.layout.layoutIndex, 2, "then the ones you can dispel")
    T.eq(set.debuffs.__groups.rest.layout.layoutIndex, 3, "then the rest")
    T.eq(table.concat(set.buffs.__groupOrder, ","), "buffs")
    T.eq(set.buffs.__groups.buffs.filter, "HELPFUL")
end)

T.test("both rows grow toward the inner end; debuffs then up, buffs then down", function()
    local set = setup()
    T.eq(set.debuffs.__anchorPoint, "BOTTOMRIGHT")
    T.eq(set.debuffs.__growth[1], AnchorUtil.FlowDirection.Left)
    T.eq(set.debuffs.__growth[2], AnchorUtil.FlowDirection.Up)
    T.eq(set.buffs.__anchorPoint, "TOPRIGHT")
    T.eq(set.buffs.__growth[1], AnchorUtil.FlowDirection.Left)
    T.eq(set.buffs.__growth[2], AnchorUtil.FlowDirection.Down)
end)

T.test("settings pick the debuff filter and set both counts", function()
    local set, ns = setup()
    local g = set.debuffs.__groups
    ns.Auras.Apply(set, CFG)
    T.eq(g.mine.max, 8); T.eq(g.cure.max, 4); T.eq(g.rest.max, 4)
    T.isnil(g.others, "split: no whole-lot group")
    T.eq(set.buffs.__groups.buffs.max, 6, "buffs capped")
    ns.Auras.Apply(set, copy(CFG, { debuffFilter = "mine" }))
    T.eq(g.mine.max, 8); T.eq(g.cure.max, 0); T.eq(g.rest.max, 0)
    ns.Auras.Apply(set, copy(CFG, { debuffs = false, buffs = false }))
    T.eq(g.mine.max, 0); T.eq(g.cure.max, 0); T.eq(g.rest.max, 0)
    T.eq(set.buffs.__groups.buffs.max, 0)
end)

T.test("spacing settings reach each group's layout", function()
    local set, ns = setup()
    ns.Auras.Apply(set, copy(CFG, { debuffSpacing = 7, buffSpacing = 0 }))
    T.eq(set.debuffs.__groups.mine.layout.elementSpacing, 7)
    T.eq(set.debuffs.__groups.mine.layout.lineSpacing, 11)
    T.eq(set.buffs.__groups.buffs.layout.elementSpacing, 0)
end)

T.test("rows setting caps how many icons show", function()
    local set, ns, target = setup()
    -- 220 wide, 30px icons + 3px gap: 6 per row once placed.
    local cfg = copy(CFG, { debuffSpacing = 3, debuffRows = 1, maxDebuffs = 8, maxOtherDebuffs = 4 })
    ns.Auras.Apply(set, cfg)
    ns.Auras.Place(set, target)
    local per = math.floor((set.debuffRow + 3) / (30 + 3))
    T.eq(set.debuffs.__groups.mine.max, math.min(8, per))
    local g = set.debuffs.__groups
    T.eq(g.mine.max + g.cure.max + g.rest.max, math.min(16, per), "one row in all")
    ns.Auras.Apply(set, copy(cfg, { debuffRows = 6 }))
    T.eq(g.mine.max, 8); T.eq(g.cure.max, 4); T.eq(g.rest.max, 4)
    -- Two rows, short of room: the rest keep their 4 (an enemy's row as before), and
    -- the ones you can dispel take what's left.
    ns.Auras.Apply(set, copy(cfg, { debuffRows = 2 }))
    T.eq(g.mine.max, math.min(8, 2 * per)); T.eq(g.rest.max, math.min(4, 2 * per - g.mine.max))
    T.eq(g.cure.max, math.max(0, math.min(4, 2 * per - 12)))
    ns.Auras.Apply(set, copy(CFG, { buffRows = 1, maxBuffs = 12 }))
    T.eq(set.buffs.__groups.buffs.max, math.min(12, math.floor((set.buffRow + 3) / (18 + 3))))
end)

T.test("debuffs are bigger than buffs", function()
    local set, ns = setup()
    ns.Auras.Apply(set, CFG)
    local dl, bl = set.debuffs.__groups.mine.layout, set.buffs.__groups.buffs.layout
    T.eq(dl.elementWidth, 30)
    T.eq(dl.elementHeight, math.floor(30 * ns.Auras.ASPECT + 0.5))
    T.eq(bl.elementWidth, 18)
    local btn = set.buffs.__groups.buffs.button
    T.eq(btn.__time.__font[1], DaylightUI.Style.FONT, "timers use the font")
end)

T.test("icons crop their art instead of squashing it", function()
    local set = setup()
    local l, r, top, bottom = unpack(set.debuffs.__groups.mine.button.__icon.__texCoord)
    T.near(r - l, 0.84)
    T.truthy(bottom - top < 0.84, "vertical crop")
end)

T.test("buttons show the time on the top edge, a soft inner shadow and no sweep", function()
    local set = setup()
    local btn = set.debuffs.__groups.mine.button
    T.truthy(btn.__time, "duration text wired")
    local p, rel, rp = btn.__time:GetPoint(1)
    T.eq(p, "CENTER"); T.eq(rel, btn); T.eq(rp, "TOP")
    T.truthy(btn.__cooldown)
    T.truthy(btn.__count)
    local shade
    for _, c2 in ipairs(stub.Children(btn)) do
        if c2.__texture == DaylightUI.MEDIA .. "inner-shadow.png" then shade = c2 end
    end
    T.truthy(shade, "inner shadow over the icon")
    T.rgb(shade.__vertex, { 0, 0, 0 }, "tinted black")
end)

T.test("debuffs get a wine border, buffs keep the black one", function()
    local set, ns = setup()
    local debuffShell = DaylightUI.Style.GetShell(set.debuffs.__groups.mine.button)
    local buffShell = DaylightUI.Style.GetShell(set.buffs.__groups.buffs.button)
    local edge = set.debuffs.__groups.mine.button.__dispel.tex
    T.rgb(edge.__vertex, ns.Auras.DEBUFF_BORDER, "debuff edge starts wine")
    T.rgb(buffShell.border.TOP.__vertex, DaylightUI.Style.BORDER, "buff border")
end)

T.test("debuffs sit above the name tab across the frame; buffs under the frame", function()
    local set, ns, target = setup()
    ns.Auras.Apply(set, CFG)
    target.tab = CreateFrame("Frame", nil, target)
    target.tab:SetWidth(80)
    target.ringInset = 20
    ns.Auras.Place(set, target)
    local p, rel, rp, x, y = set.debuffs:GetPoint(1)
    T.eq(p, "BOTTOMRIGHT"); T.eq(rel, target); T.eq(rp, "TOPRIGHT")
    T.eq(x, -ns.UF.TAB_INSET, "from the tab's outer end"); T.eq(y, ns.Spots.GAP + target.tab:GetHeight(), "over the tab")
    T.eq(set.debuffs.__lineSize, 220 - ns.UF.TAB_INSET, "as wide as the frame")
    local bp, brel, brp, bx, by = set.buffs:GetPoint(1)
    T.eq(bp, "TOPRIGHT"); T.eq(brel, target); T.eq(brp, "BOTTOMRIGHT")
    T.eq(bx, -20, "clear of the portrait ring")
    T.truthy(by < 0, "under the frame, with room for the time")
    T.eq(set.buffs.__lineSize, 220 - 20)
end)

T.test("without a tab, debuffs start at the frame's outer end; buffs drop below combo points", function()
    local set, ns, target = setup()
    ns.Auras.Apply(set, CFG)
    ns.Auras.Place(set, target)
    local _, rel, rp = set.debuffs:GetPoint(1)
    T.eq(rel, target); T.eq(rp, "TOPRIGHT")
    local _, _, _, _, y1 = set.buffs:GetPoint(1)
    set.buffDrop = 12
    ns.Auras.Place(set, target)
    local _, _, _, _, y2 = set.buffs:GetPoint(1)
    T.eq(y2, y1 - 12)
end)

T.test("a missing sort constant turns groups off with a message, not an error", function()
    local _, ns = stub.Load({ module = true, login = false })
    local saved = AuraContainerSortDirection
    AuraContainerSortDirection = nil
    local ok = pcall(ns.Auras.Create, CreateFrame("Frame", nil, UIParent), "left")
    AuraContainerSortDirection = saved
    T.truthy(ok)
    T.truthy(stub.ChatContains("Aura group"))
end)

T.test("a client without aura containers turns target auras off with a message", function()
    local set, ns = setup({ before = function() stub.noAuraContainer = true end })
    T.isnil(set)
    T.truthy(stub.ChatContains("no aura container"))
    ns.Auras.Apply(nil, CFG)
    ns.Auras.Place(nil, UIParent)
end)

T.test("an aura button stays light: the client builds ten a group, seen or not", function()
    local set = setup()
    local function pieces(b)
        local n = #{ b:GetRegions() }
        for _, c in ipairs({ b:GetChildren() }) do
            n = n + #{ c:GetRegions() }
            for _, d in ipairs({ c:GetChildren() }) do n = n + #{ d:GetRegions() } end
        end
        return n
    end
    local buff, debuff = pieces(set.buffs.__groups.buffs.button), pieces(set.debuffs.__groups.mine.button)
    T.truthy(buff <= 30, "a buff button: " .. buff .. " pieces")
    T.truthy(debuff <= 16, "a debuff button: " .. debuff .. " pieces")
end)

T.test("every aura button gets a tooltip anchor, so the client shows its tooltip", function()
    local set, ns = setup()
    T.eq(set.debuffs.__groups.mine.button.__tooltipAnchor, ns.Auras.TOOLTIP_ANCHOR)
    T.eq(set.debuffs.__groups.cure.button.__tooltipAnchor, ns.Auras.TOOLTIP_ANCHOR)
    T.eq(set.buffs.__groups.buffs.button.__tooltipAnchor, ns.Auras.TOOLTIP_ANCHOR)
end)

T.test("debuff edges are tinted by dispel type; buffs have none", function()
    local set, ns = setup()
    local d = set.debuffs.__groups.mine.button.__dispel
    T.truthy(d, "debuffs get a dispel edge")
    T.eq(d.opts.style, Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset, "the client's style value, not a string")
    T.truthy(d.opts.showWithoutDispelType)
    for _, name in ipairs(ns.Auras.DISPEL_KEYS) do
        local c = d.opts.customDispelColorMap[name]
        T.truthy(c and c.r, name .. " as a color object")
        T.truthy(d.opts.customDispelAssetMap[name].asset, name .. " asset")
    end
    local h = set.buffs.__groups.buffs.button.__dispel
    T.eq(#set.buffs.__groups.buffs.button.__dispels, 1, "buffs: no edge, only the purge halo")
    T.falsy(h.opts.showWhenHarmful); T.truthy(h.opts.showWhenHelpful)
    T.eq(h.opts.stealableFilter, Enum.CustomAuraButtonDispelTypeStealableFilter.Stealable, "only on a buff you can purge")
    T.eq(h.tex.__texture, DaylightUI.Style.AURA_HALO)
    T.truthy(h.opts.customDispelColorMap.Magic.r, "in its dispel color")
    local shell = DaylightUI.Style.GetShell(set.debuffs.__groups.mine.button)
    T.isnil(shell.border.TOP, "no shell border over the dispel edge")
    local bshell = DaylightUI.Style.GetShell(set.buffs.__groups.buffs.button)
    T.truthy(bshell.border.TOP.__vertex[4] > 0, "buffs keep theirs")
end)

-- The game's color objects are heavy (a copy of ColorMixin each), so the thousands
-- of aura buttons made at login share one set per look.
T.test("aura buttons share their dispel colors; a softness change makes a new set", function()
    local set = setup()
    local g = set.debuffs.__groups
    local a, b = g.mine.buttons[1].__dispel.opts, g.rest.buttons[2].__dispel.opts
    T.truthy(a.customDispelColorMap == b.customDispelColorMap, "one color set for every edge")
    T.truthy(a.customDispelAssetMap == b.customDispelAssetMap, "one asset set too")
    local halo = g.cure.buttons[1].__dispels[2].opts
    T.truthy(halo.customDispelColorMap == g.cure.buttons[3].__dispels[2].opts.customDispelColorMap, "halos share theirs")
    T.truthy(halo.customDispelColorMap ~= a.customDispelColorMap, "a halo's set is its own")
    T.truthy(halo.customDispelAssetMap.None == halo.customDispelAssetMap.Magic, "a halo with no type takes Magic's")
    local Style = DaylightUI.Style
    local before = a.customDispelColorMap.Magic.r
    DaylightUI:Set("general", "softness", 0.1)
    local btn = CreateFrame("Button", nil, UIParent)
    btn.AddDispelTypeTexture = g.mine.buttons[1].AddDispelTypeTexture
    Style.DispelEdge(btn, btn:CreateTexture(), function() return { 0.2, 0.6, 1 } end)
    local c = btn.__dispel.opts.customDispelColorMap
    T.truthy(c ~= a.customDispelColorMap, "other colors: a new set")
    T.eq(a.customDispelColorMap.Magic.r, before, "the old set is never written into")
end)

T.test("only the debuffs you can dispel get the soft halo, in their dispel color", function()
    local set = setup()
    local g = set.debuffs.__groups
    local cure = g.cure.button.__dispels
    T.eq(#cure, 2, "the edge, then the halo")
    local h = cure[2]
    T.eq(h.tex.__texture, DaylightUI.Style.AURA_HALO)
    T.truthy(h.opts.showWhenHarmful); T.falsy(h.opts.showWhenHelpful)
    T.falsy(h.opts.showWithoutDispelType, "a debuff with no type has nothing to dispel")
    T.isnil(h.opts.stealableFilter)
    T.truthy(h.opts.customDispelColorMap.Curse.r, "in its dispel color")
    for _, key in ipairs({ "mine", "rest" }) do
        T.eq(#g[key].button.__dispels, 1, key .. ": the edge only")
    end
end)

T.test("a client that refuses the split keeps every other debuff in one group", function()
    local set, ns = setup({ before = function()
        stub.refuseAuraFilters = { ["HARMFUL|!PLAYER|!RAID_PLAYER_DISPELLABLE"] = true }
    end })
    stub.refuseAuraFilters = nil
    T.falsy(ns.Auras.Splits(set.debuffs))
    ns.Auras.Apply(set, CFG)
    local g = set.debuffs.__groups
    T.eq(g.mine.max, 8); T.eq(g.others.max, 4, "today's row")
    T.eq(g.cure.max, 0, "no halo group alone, or dispellable ones would show twice")
end)

T.test("if our own colors are refused, the client's colors are used", function()
    local set, ns = setup()
    local btn = CreateFrame("Button", nil, UIParent)
    local calls = {}
    function btn:AddDispelTypeTexture(tex, opts)
        calls[#calls + 1] = opts.style
        if opts.style == Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset then error("refused") end
    end
    T.eq(ns.Auras.RegisterDispelEdge(btn, btn:CreateTexture()), "client")
    T.eq(#calls, 2)
end)

T.test("debuffs below the frame: they grow down under it, and the buffs go up over it", function()
    local set, ns, target = setup()
    ns.Auras.Apply(set, copy(CFG, { debuffSpot = "below", buffSpot = "above" }))
    ns.Auras.Place(set, target)
    T.eq(set.debuffs.__anchorPoint, "TOPRIGHT")
    T.eq(set.debuffs.__growth[2], AnchorUtil.FlowDirection.Down)
    local p, rel, rp = set.debuffs:GetPoint(1)
    T.eq(p, "TOPRIGHT"); T.eq(rel, target); T.eq(rp, "BOTTOMRIGHT", "under the frame")
    T.eq(set.buffs.__anchorPoint, "BOTTOMRIGHT")
    T.eq(set.buffs.__growth[2], AnchorUtil.FlowDirection.Up)
    local bp, _, brp = set.buffs:GetPoint(1)
    T.eq(bp, "BOTTOMRIGHT"); T.eq(brp, "TOPRIGHT", "the buffs over it")
    ns.Auras.Apply(set, CFG)
    ns.Auras.Place(set, target)
    T.eq(set.debuffs.__anchorPoint, "BOTTOMRIGHT", "back above")
end)

T.test("both on one side: buffs nearest, debuffs past every row the buffs could fill", function()
    for _, at in ipairs({ "above", "below" }) do
        local set, ns, target = setup()
        ns.Auras.Apply(set, copy(CFG, { debuffSpot = at, buffSpot = at }))
        ns.Auras.Place(set, target)
        local _, drel, _, _, dy = set.debuffs:GetPoint(1)
        local _, brel, _, _, by = set.buffs:GetPoint(1)
        T.truthy(drel ~= set.buffs and brel ~= set.debuffs, "never anchored to each other")
        local room = ns.Auras.Height(set, "buff")
        T.truthy(room > 0)
        T.truthy(math.abs(by - dy) >= room, at .. ": the debuffs clear the buffs' rows")
        T.truthy(math.abs(dy) > math.abs(by), at .. ": buffs nearest the frame")
    end
end)

T.test("Place says how far the rows reach above and below", function()
    local set, ns, target = setup()
    ns.Auras.Apply(set, CFG)
    local top, bottom = ns.Auras.Place(set, target)
    T.truthy(top > ns.Auras.Height(set, "debuff"), "debuffs above: their rows and the gaps")
    T.truthy(bottom > 0, "buffs below")
    ns.Auras.Apply(set, copy(CFG, { debuffSpot = "below", buffSpot = "below" }))
    top, bottom = ns.Auras.Place(set, target)
    T.eq(top, 0, "nothing above")
    T.truthy(bottom > ns.Auras.Height(set, "debuff"), "both rows below")
end)

T.test("stand-ins take the same layout and samples, and never resize the real buttons", function()
    local _, ns = stub.Load({ module = true })
    local real = ns.auras.debuffs.__groups.mine.button
    local w = real:GetWidth()
    T.truthy(w > 0, "the real target's buttons are sized at login")
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(220, 48)
    local set = ns.Auras.PlainSet(f, "left")
    T.eq(set.debuffs:GetObjectType(), "Frame", "a plain frame, not a container")
    T.eq(set.side, "left")
    local big = copy(CFG, { debuffSize = w + 14 })
    ns.Auras.Apply(set, big)
    T.eq(real:GetWidth(), w, "the real buttons keep their size")
    local top = ns.Auras.Place(set, f)
    T.truthy(top > 0)
    ns.Auras.ShowSample(set, f, big, ns.Test.AURAS)
    local h = ns.Auras.HolderFor(set.debuffs)
    T.eq(h:GetParent(), f, "drawn on the frame")
    T.truthy(h:IsShown() and h.pool[1]:IsShown())
    T.eq(h.pool[1]:GetWidth(), w + 14, "at the sample's own size")
end)


T.test("the rows' time and stack count sizes reach new and made icons, one row's never the other's", function()
    local set, ns = setup()
    local dbtn, bbtn = set.debuffs.__groups.mine.button, set.buffs.__groups.buffs.button
    T.eq(bbtn.__time.__font[2], ns.Auras.TIME_SIZE.buff, "without a setting, today's size")
    ns.Auras.Apply(set, copy(CFG, { buffTimeSize = 15, buffCountSize = 14, debuffTimeSize = 11 }))
    T.eq(bbtn.__time.__font[2], 15)
    T.eq(bbtn.__count.__font[2], 14)
    T.eq(dbtn.__time.__font[2], 11)
    T.eq(dbtn.__count.__font[2], ns.Auras.COUNT_SIZE, "a row without its own keeps the kind's")

    local f = CreateFrame("Frame", "FakeNew", UIParent)
    f:SetSize(220, 48)
    f.spec = { slant = "left" }
    local cfg = copy(CFG, { buffTimeSize = 15, buffCountSize = 14 })
    local made = ns.Auras.Create(f, "left", "target", cfg)
    local b = made.buffs.__groups.buffs.button
    T.eq(b.__time.__font[2], 15, "a button the client builds later is born at the size")
    T.eq(b.__count.__font[2], 14)
end)

T.test("a bigger time under the frame moves the row down by its own room", function()
    local set, ns, target = setup()
    ns.Auras.Apply(set, CFG)
    ns.Auras.Place(set, target)
    local _, _, _, _, y = set.buffs:GetPoint(1)
    local h = ns.Auras.Height(set, "buff")
    ns.Auras.Apply(set, copy(CFG, { buffTimeSize = 19 }))
    ns.Auras.Place(set, target)
    local _, _, _, _, y2 = set.buffs:GetPoint(1)
    T.near(y2, y - 6, 0.01, "10 more points, 0.6 of it hangs over the top edge")
    T.near(ns.Auras.Height(set, "buff"), h + 6, 0.01)
end)

T.test("a stand-in's samples take the text sizes, and icons already made follow a change", function()
    local _, ns = stub.Load({ module = true })
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(220, 48)
    local set = ns.Auras.PlainSet(f, "left")
    ns.Auras.Apply(set, CFG)
    ns.Auras.Place(set, f)
    ns.Auras.ShowSample(set, f, CFG, ns.Test.AURAS)
    local b = ns.Auras.HolderFor(set.buffs).pool[1]
    T.eq(b.time.__font[2], ns.Auras.TIME_SIZE.buff)
    local big = copy(CFG, { buffTimeSize = 16, buffCountSize = 13 })
    ns.Auras.Apply(set, big)
    ns.Auras.ShowSample(set, f, big, ns.Test.AURAS)
    T.eq(b.time.__font[2], 16)
    T.eq(b.count.__font[2], 13)
end)

-- Golden test: where the target's debuffs and buffs sat before they were placed by
-- Spots. A profile saved with the old keys is loaded, so the upgrade runs on it.
local function round(v) return math.floor(v * 10 + 0.5) / 10 end

-- Where it sits from the frame: a row hung off the name tab's top right corner is
-- moved into the frame's terms (the tab hangs off its top right).
local function goldenWhere(c, f)
    local p, rel, rp, x, y = c:GetPoint(1)
    if rel == f.tab and rp == "TOPRIGHT" then
        local _, _, _, tx, ty = f.tab:GetPoint(1)
        rel, x, y = f, x + tx, y + ty + f.tab:GetHeight()
    end
    local fd = AnchorUtil.FlowDirection
    local names = { [fd.Left] = "Left", [fd.Right] = "Right", [fd.Up] = "Up", [fd.Down] = "Down" }
    return { p, rel == f and "frame" or (rel == f.tab and "tab" or "other"), rp, round(x), round(y),
             c.__anchorPoint, names[c.__growth[1]], names[c.__growth[2]], round(c.__lineSize) }
end

local GOLDEN = {
    ["debuffs above, buffs below: debuffs"] = { "BOTTOMRIGHT", "frame", "TOPRIGHT", -26.5, 18.3, "BOTTOMRIGHT", "Left", "Up", 159.8 },
    ["debuffs above, buffs below: buffs"] = { "TOPRIGHT", "frame", "BOTTOMRIGHT", -18.5, -7.4, "TOPRIGHT", "Left", "Down", 167.8 },
    ["debuffs above, buffs above: debuffs"] = { "BOTTOMRIGHT", "frame", "TOPRIGHT", -26.5, 42.7, "BOTTOMRIGHT", "Left", "Up", 159.8 },
    ["debuffs above, buffs above: buffs"] = { "BOTTOMRIGHT", "frame", "TOPRIGHT", -26.5, 18.3, "BOTTOMRIGHT", "Left", "Up", 159.8 },
    ["debuffs below, buffs below: debuffs"] = { "TOPRIGHT", "frame", "BOTTOMRIGHT", -18.5, -33.6, "TOPRIGHT", "Left", "Down", 167.8 },
    ["debuffs below, buffs below: buffs"] = { "TOPRIGHT", "frame", "BOTTOMRIGHT", -18.5, -7.4, "TOPRIGHT", "Left", "Down", 167.8 },
    ["debuffs below, buffs above: debuffs"] = { "TOPRIGHT", "frame", "BOTTOMRIGHT", -18.5, -9.2, "TOPRIGHT", "Left", "Down", 167.8 },
    ["debuffs below, buffs above: buffs"] = { "BOTTOMRIGHT", "frame", "TOPRIGHT", -26.5, 18.3, "BOTTOMRIGHT", "Left", "Up", 159.8 },
}

-- Points, growth and line exact; x and y within a pixel.
local function goldenSame(got, want, label)
    for i = 1, 9 do
        if i == 4 or i == 5 then T.near(got[i], want[i], 1, label .. "." .. i)
        else T.eq(got[i], want[i], label .. "." .. i) end
    end
end

T.test("golden: the target's debuffs and buffs stay where they were", function()
    local dump = os.getenv("GOLDEN_DUMP")
    for _, d in ipairs({ "above", "below" }) do
        for _, b in ipairs({ "below", "above" }) do
            local _, ns = stub.Load({ module = true, before = function()
                DaylightUIDB = { version = 2, profileData = { Default = { general = {}, positions = {},
                    modules = { UnitFrames = { groupFrames = 9, targetAuras = { debuffsAt = d, buffsAt = b } } } } } }
            end })
            stub.RunTimers()
            local f = ns.frames.target
            for _, which in ipairs({ "debuffs", "buffs" }) do
                local label = "debuffs " .. d .. ", buffs " .. b .. ": " .. which
                local got = goldenWhere(ns.auras[which], f)
                if dump then
                    local parts = {}
                    for i = 1, 9 do
                        local v = got[i]
                        parts[i] = type(v) == "string" and string.format("%q", v) or tostring(v)
                    end
                    print(string.format('    [%q] = { %s },', label, table.concat(parts, ", ")))
                elseif GOLDEN[label] then
                    goldenSame(got, GOLDEN[label], label)
                end
            end
        end
    end
end)

T.test("upgrade 10: the target's above/below become spots, growing toward the inner end", function()
    local _, ns = stub.Load({ module = true, login = false })
    local step = ns.UPGRADE_STEPS[10]
    local uf = { targetAuras = { debuffsAt = "below", buffsAt = "above", debuffSize = 22 } }
    step(uf)
    local t = uf.targetAuras
    T.isnil(t.debuffsAt); T.isnil(t.buffsAt)
    T.eq(t.debuffSpot, "below"); T.eq(t.buffSpot, "above")
    T.eq(t.debuffSize, 22, "the rest stays")
    uf = { targetAuras = { debuffsAt = "above" } }
    step(uf)
    T.eq(uf.targetAuras.debuffSpot, "above"); T.isnil(uf.targetAuras.buffSpot, "unsaved: the default")
    uf = {}
    step(uf)
    T.isnil(uf.targetAuras)
    local d = ns.DEFAULTS.targetAuras
    T.eq(d.debuffSpot, "above"); T.eq(d.debuffGrow, "left"); T.eq(d.buffSpot, "below"); T.eq(d.buffGrow, "left")
    T.isnil(d.debuffsAt); T.isnil(d.buffsAt)
end)

T.test("target auras at an inside spot on the angled end stay out of the cut; the nudge moves them", function()
    local DUI, ns = stub.Load({ module = true })
    local f = ns.frames.target
    DUI:Set("UnitFrames", "targetAuras.debuffSpot", "bottomleft")
    DUI:Set("UnitFrames", "targetAuras.debuffGrow", "right")
    stub.RunTimers()
    T.eq(f.spec.slant, "left", "the target's angled end is its left")
    T.truthy(f.cut > 0)
    local box = ns.AuraGroups.Box(f, DUI:Get("UnitFrames", "target"))
    local p, rel, rp, x, y = ns.auras.debuffs:GetPoint(1)
    T.eq(p, "BOTTOMLEFT"); T.eq(rel, f); T.eq(rp, "BOTTOMLEFT")
    T.eq(x, box.padX + f.cut, "in from the cut")
    T.eq(y, box.padY + box.bottomInset, "clear of the power bar")
    T.truthy(ns.auras.debuffs.__lineSize <= f:GetWidth() - 2 * box.padX - f.cut, "the row fits inside")
    DUI:Set("UnitFrames", "targetAuras.debuffX", 4)
    DUI:Set("UnitFrames", "targetAuras.debuffY", 2)
    stub.RunTimers()
    local _, _, _, x2, y2 = ns.auras.debuffs:GetPoint(1)
    T.eq(x2, x + 4); T.eq(y2, y + 2)
    DUI:Set("UnitFrames", "targetAuras.buffSpot", "outright")
    stub.RunTimers()
    T.truthy(select(4, ns.auras.buffs:GetPoint(1)) > f.ringReach, "beside the outer end: past the portrait ring")
end)
