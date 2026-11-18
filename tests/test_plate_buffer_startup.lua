local stub = require("stub")

-- Compile the same one-line build selection the packager changes. Restore both
-- the loader and its cache even if loading fails; other suites use the control.
local function loadVariant(block, opts)
    local original = loadfile
    local create = CreateFrame
    stub.ForgetCompiled()
    loadfile = function(path, ...)
        if path ~= "Fade.lua" then return original(path, ...) end
        local fh = assert(io.open(path, "rb"))
        local source = fh:read("*a")
        fh:close()
        local changed
        source, changed = source:gsub("local EXPERIMENT_NO_FRAMEBUFFERS = false",
            "local EXPERIMENT_NO_FRAMEBUFFERS = " .. tostring(block), 1)
        assert(changed == 1, "missing experiment build selection")
        return loadstring(source, "@Fade.lua")
    end
    local result = { pcall(stub.Load, opts) }
    loadfile = original
    CreateFrame = create
    stub.ForgetCompiled()
    if not result[1] then error(result[2]) end
    return result[2], result[3]
end

-- These flags model only getter/setter bookkeeping, not native drawing. Track
-- every new root, including the unit frames, secure bars and AuraContainers.
local function instrument(opts)
    local state = { frames = {}, bufferCalls = 0, flatCalls = 0, flatLog = {} }
    opts = opts or {}
    opts.before = function()
        local create = CreateFrame
        state.create = function(...)
            local f = create(...)
            local id = #state.frames + 1
            f.auditBuffer, f.auditFlat = false, false
            function f:SetIsFrameBuffer(on)
                state.bufferCalls = state.bufferCalls + 1
                self.auditBuffer = on
            end
            function f:SetFlattensRenderLayers(on)
                state.flatCalls = state.flatCalls + 1
                state.flatLog[#state.flatLog + 1] = id .. ":" .. tostring(on)
                self.auditFlat = on
            end
            function f:IsFrameBuffer() return self.auditBuffer end
            function f:GetFlattensRenderLayers() return self.auditFlat end
            function f:GetEffectivelyFlattensRenderLayers() return self.auditEffective or self.auditFlat end
            state.frames[#state.frames + 1] = f
            return f
        end
        CreateFrame = state.create
    end
    return opts, state
end

local function settle(F)
    F.Step()
    for _ = 1, 120 do stub.RunOnUpdate(F.driver, 1 / 60) end
end

T.test("startup buffer experiment: blocks first login and keeps control flattening and alpha", function()
    local controlOpts, controlState = instrument({ module = true, actionbars = true, buffs = true, intro = true })
    local control = loadVariant(false, controlOpts)
    local baseline = control.Fade.BufferAudit()
    T.truthy(controlState.bufferCalls > 0, "control exercises real setter calls")
    T.eq(baseline.skipped, 0)
    local flat, alpha = {}, {}
    for i, f in ipairs(controlState.frames) do flat[i], alpha[i] = f.auditFlat, f:GetAlpha() end

    local opts, state = instrument({ module = true, actionbars = true, buffs = true, intro = true })
    local DUI = loadVariant(true, opts)
    local audit = DUI.Fade.BufferAudit()
    T.eq(state.bufferCalls, 0, "gate is active before the first registration")
    T.truthy(audit.skipped > 0)
    T.eq(audit.requests, audit.skipped)
    T.eq(audit.requested, baseline.requested)
    T.eq(audit.tracked, baseline.tracked)
    T.eq(state.flatCalls, controlState.flatCalls, "flatten call sequence retained")
    T.deq(state.flatLog, controlState.flatLog, "same ordered flatten calls")
    T.eq(#state.frames, #controlState.frames)
    for i, f in ipairs(state.frames) do
        T.eq(f.auditFlat, flat[i], "same explicit flatten flag")
        T.eq(f:GetAlpha(), alpha[i], "same alpha")
    end
    T.eq(audit.enabled, 0)
    T.eq(audit.unknown, 0)
    T.eq(DUI.Fade.WholeCount(), 0, "report native state rather than requested cache")
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("startup buffer experiment: queued requests, range, arrivals and UI fade cannot bypass gate", function()
    local opts, state = instrument()
    local DUI = loadVariant(true, opts)
    local F = DUI.Fade
    local first = state.create("Frame", nil, UIParent)
    local incoming = state.create("Frame", nil, UIParent)
    local frames = { first }
    DUI.DB.General().bufferTest = { mode = "always", alpha = 0.3, delay = 0, mouseover = false }
    F.Register({ key = "bufferTest", scope = "general", path = "bufferTest", whole = true,
        frames = function() return frames end })
    settle(F)
    T.eq(first:GetAlpha(), 0.3)
    stub.EnterCombat()
    F.Whole(incoming, "range", true)
    frames[1] = incoming
    F.Step()
    stub.LeaveCombat()
    settle(F)
    T.eq(first.auditFlat, false, "departed root releases its request")
    T.eq(incoming.auditFlat, true, "range and arrival retain flattening")
    F.SetUIAlpha(0.5)
    T.eq(incoming.auditFlat, false)
    F.SetUIAlpha(1)
    T.eq(incoming.auditFlat, true)
    F.Whole(incoming, "range", false)
    T.eq(incoming.auditFlat, true, "area still owns its request")
    local newest = state.create("Frame", nil, UIParent)
    F.Whole(newest, "late", true)
    T.eq(newest.auditFlat, true)
    T.eq(state.bufferCalls, 0)
    local audit = F.BufferAudit()
    T.eq(audit.requests, audit.skipped)
    T.truthy(audit.skipped > 3)
    T.eq(audit.enabled, 0)
    T.eq(audit.unknown, 0)
    T.eq(#stub.errors, 0, tostring(stub.errors[1]))
end)

T.test("startup buffer audit: native, explicit and effective state are independent and read only", function()
    local opts, state = instrument()
    local DUI = loadVariant(true, opts)
    local F = DUI.Fade
    local f = state.create("Frame", nil, UIParent)
    F.Whole(f, "test", true)
    -- Simulate native/external state; the experiment does not turn existing
    -- buffers off, and effective flattening need not equal the explicit flag.
    f.auditBuffer, f.auditFlat, f.auditEffective = true, false, true
    local calls, flats = state.bufferCalls, state.flatCalls
    local audit = F.BufferAudit()
    T.eq(audit.enabled, 1)
    T.eq(audit.flattened, 0)
    T.eq(audit.effectiveFlattened, 1)
    T.eq(F.WholeCount(), 1)
    local printed = {}
    DUI.Print = function(msg) printed[#printed + 1] = msg end
    DUI.RunCommand("platebufferstatus")
    T.eq(#printed, 2)
    T.truthy(printed[1]:find("startup buffer block=on", 1, true))
    T.truthy(printed[2]:find("native buffers=1 unknown=0", 1, true))
    T.falsy(DUI.LISTED_COMMANDS.platebufferstatus)
    T.eq(state.bufferCalls, calls)
    T.eq(state.flatCalls, flats)
end)

T.test("startup buffer audit: refused, missing and secret getters remain unknown", function()
    local opts, state = instrument()
    local DUI = loadVariant(true, opts)
    local F = DUI.Fade
    local f = state.create("Frame", nil, UIParent)
    F.Whole(f, "test", true)
    function f:IsFrameBuffer() error("private details must not be retained") end
    function f:GetFlattensRenderLayers() return stub.Secret(true) end
    f.GetEffectivelyFlattensRenderLayers = false
    local audit = F.BufferAudit()
    T.eq(audit.bufferUnknown, 1)
    T.eq(audit.flattenUnknown, 1)
    T.eq(audit.effectiveUnknown, 1)
    T.eq(audit.unknown, 1)
    T.eq(audit.errors, 2)
    T.isnil(F.WholeCount(), "unreadable native state cannot be reported as zero")
    for _, value in pairs(audit) do T.falsy(type(value) == "string", "no names or private error text") end
end)

T.test("buffer recorder: both builds read only native buffer flags and preserve unknown totals", function()
    for _, block in ipairs({ false, true }) do
        local opts, state = instrument()
        local DUI = loadVariant(block, opts)
        local F = DUI.Fade
        local f, g = state.create("Frame", nil, UIParent), state.create("Frame", nil, UIParent)
        F.Whole(f, "requested", true)
        F.Whole(g, "unrequested", false)
        local reads, flatReads = 0, 0
        function f:IsFrameBuffer() reads = reads + 1; return self.auditBuffer end
        function g:IsFrameBuffer() reads = reads + 1; return self.auditBuffer end
        local function forbiddenRead()
            flatReads = flatReads + 1
            error("recorder must not run the full flatten audit")
        end
        f.GetFlattensRenderLayers, g.GetFlattensRenderLayers = forbiddenRead, forbiddenRead
        f.GetEffectivelyFlattensRenderLayers, g.GetEffectivelyFlattensRenderLayers = forbiddenRead, forbiddenRead
        -- The native state may differ from requests in either build.
        f.auditBuffer, g.auditBuffer = false, false
        T.eq(F.WholeCount(), 0, "ignore requested-state cache")
        T.eq(reads, 2, "one buffer getter per tracked root")
        g.auditBuffer = true
        T.eq(F.WholeCount(), 1, "include an externally enabled root")
        T.eq(reads, 4)
        f.auditBuffer = stub.Secret(false)
        T.isnil(F.WholeCount(), "secret native state is unknown in both builds")
        T.eq(reads, 6, "unknown does not stop reading other roots")
        function f:IsFrameBuffer() error("refused") end
        T.isnil(F.WholeCount(), "refused native state is unknown in both builds")
        T.eq(flatReads, 0, "no flatten getters in the recurring recorder path")
    end
end)
