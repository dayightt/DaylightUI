local stub = require("stub")

-- The every-option sweeps for the frame styles: each option row of the four
-- frames that wear a style, set to each of its values with the frames laid out
-- after each. Each one grows with every unit frame option, so they run with the
-- other slow sweeps (--par --all). What each style draws is in test_ribbon.

local function login(before) return stub.Load({ module = true, before = before }) end

local function ribbon(DUI, ns, on)
    ns.SetStyle("look.style", on == false and "daylight" or "ribbon")
    stub.RunTimers()
end

local function addStyle(ns, key, def)
    def.label, def.desc = def.label or key, def.desc or key
    ns.STYLES[key] = def
    ns.STYLE_ORDER[#ns.STYLE_ORDER + 1] = key
end

local function backdrop(DUI, ns, style)
    if not ns.STYLES.card then addStyle(ns, "card", { backdrop = true }) end
    ns.SetStyle("look.style", style or "card")
    stub.RunTimers()
end

-- Every option row of the four frames that wear Ribbon, set to each of its
-- values while Ribbon is on, with the frames laid out after each, raises no
-- error. The rows' own tests check what each does. This checks they still
-- work on the new shape.
local function everyOption(DUI, ns)
    local O = DUI.Options
    local tried = 0
    for _, id in ipairs(ns.STYLE_FRAMES) do
        local page = O.GetPage("UnitFrames." .. id)
        for _, g in ipairs(page.groups) do
            for _, it in ipairs(g.items or {}) do
                if it.key and O.VALUE[it.type] and it.type ~= "color" and it.type ~= "gradient" and it.key ~= id .. ".style" then
                    local before = O.Get(page, it)
                    local values = {}
                    if it.type == "toggle" then
                        values = { true, false }
                    elseif it.type == "slider" then
                        values = { it.min, it.max }
                    elseif it.type == "dropdown" then
                        local vals, order = it.values, it.order
                        if it.choices then vals, order = it.choices() end
                        order = order or {}
                        if #order == 0 then for k in pairs(vals or {}) do order[#order + 1] = k end end
                        values = order
                        -- Every font and bar texture takes the same path, and each pick repaints
                        -- the whole UI, so General's, the next, the last and a display font stand
                        -- in for them all.
                        if string.match(it.key, "%.media%.") and #order > 4 then
                            values = { order[1], order[2], order[#order] }
                            for _, k in ipairs(order) do
                                local f = DUI.Style.FONTS[k]
                                if f and f.display then values[#values + 1] = k; break end
                            end
                        end
                    end
                    for _, v in ipairs(values) do
                        local ok, err = pcall(O.Set, page, it, v)
                        T.truthy(ok, id .. " " .. it.key .. " = " .. tostring(v) .. ": " .. tostring(err))
                        ok, err = pcall(stub.RunTimers)
                        T.truthy(ok, id .. " " .. it.key .. " = " .. tostring(v) .. " (layout): " .. tostring(err))
                        tried = tried + 1
                    end
                    pcall(O.Set, page, it, before)
                    stub.RunTimers()
                end
            end
        end
    end
    T.truthy(tried > 200, "it went through the rows: " .. tried)
end

T.test("Ribbon: every option of the player, target, focus and party pages works", function()
    local DUI, ns = login()
    ribbon(DUI, ns)
    everyOption(DUI, ns)
    T.eq(ns.frames.player.style, "ribbon", "still Ribbon at the end")
end)

T.test("a backdrop style: every option of the player, target, focus and party pages works", function()
    local DUI, ns = login()
    backdrop(DUI, ns)
    everyOption(DUI, ns)
    T.eq(ns.frames.player.style, "card", "still the backdrop style at the end")
end)
