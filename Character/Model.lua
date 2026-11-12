-- The center model: ModelScene 595 with the player actor, set up by the game's
-- helper on every open. That helper doesn't track gear changes, so slots are
-- re-dressed one at a time after. Hidden until loaded so an undressed body
-- never flashes in. Drag to turn, with a soft glow behind and a shadow below.
--
-- ns.Model is you (Character page). ns.PetModel is your pet (Pet page), set up
-- like PaperDollFrame_SetPet does.

local _, DUI = ...
DUI.Char = DUI.Char or {}   -- the character window's own namespace
local ns = DUI.Char

-- Pet scene to use when the game names none.
local PET_SCENE = 1156

-- The actor holding you in a scene set up by SetUpCharacterSheetScene. In a
-- form with its own look (Ghost Wolf, druid forms) the game uses the form's
-- actor instead, by the same test as here. The plain player actor then never
-- loads, and waiting on it delayed the model for the full wait.
function DUI.PlayerActor(scene)
    if type(scene) ~= "table" or type(scene.GetPlayerActor) ~= "function" then return nil end
    local form = type(GetShapeshiftFormID) == "function" and GetShapeshiftFormID() or nil
    if issecretvalue and issecretvalue(form) then form = nil end
    local forms = rawget(_G, "ANIMAL_FORMS")
    local tag = form and type(forms) == "table" and type(forms[form]) == "table" and forms[form].actorTag
    local info = C_PlayerInfo
    if tag and type(info) == "table" and type(info.GetDisplayID) == "function" then
        local display = info.GetDisplayID()
        local native = type(info.GetNativeDisplayID) == "function" and info.GetNativeDisplayID() or nil
        local raceNative = type(info.IsDisplayRaceNative) ~= "function" or info.IsDisplayRaceNative() == true
        local mirror = type(info.IsMirrorImage) == "function" and info.IsMirrorImage() == true
        if display ~= 0 and display ~= native and raceNative and not mirror and not UnitOnTaxi("player") then
            local a = scene:GetPlayerActor(tag)
            if a then return a end
        end
    end
    return scene:GetPlayerActor()
end

local function make(kind)
    local Model = {}
    Model.kind = kind

    Model.TURN = 0.012      -- radians per pixel dragged
    Model.SETTLE = 0.88     -- fraction of spin speed kept each frame after release
    Model.STOP = 0.0005
    Model.WAIT = 2          -- seconds to wait for the model before showing it anyway
    -- Camera distance as a fraction of the game's, before the width pull-back.
    -- The pet keeps the game's framing.
    Model.ZOOM = kind == "pet" and 1 or 0.43
    Model.ROOM = 1.6        -- max zoom-out with the wheel, relative to the start
    Model.FILL = 0.8        -- tall models (night elf, tauren) back off until they fill this much of the height. 0.92 touched both edges
    Model.GLOW = DUI.MEDIA .. "char-glow.png"
    Model.GLOW_ALPHA = 0.3
    Model.GLOW_W, Model.GLOW_H = 1.0, 0.95   -- glow size relative to the model
    Model.GLOW_UP = 0.04                     -- glow center offset up, as a fraction of height
    Model.SHADOW_ALPHA = 0.6
    Model.SHADOW_W, Model.SHADOW_H = 0.5, 26
    Model.FEET = 0.12                        -- shadow center, as a fraction of height from the bottom

    function Model.Actor()
        if kind == "pet" then return Model.actor end
        return DUI.PlayerActor(Model.scene)
    end

    function Model.StartDrag()
        Model.dragging = true
        Model.lastX = GetCursorPosition()
    end

    function Model.StopDrag() Model.dragging = false end

    function Model.Build(parent)
        local holder = CreateFrame("Frame", nil, parent)
        Model.holder = holder
        holder.glow = holder:CreateTexture(nil, "BACKGROUND")
        holder.glow:SetTexture(Model.GLOW)
        holder.shadow = holder:CreateTexture(nil, "BORDER")
        holder.shadow:SetTexture(Model.GLOW)
        holder.shadow:SetVertexColor(0, 0, 0, Model.SHADOW_ALPHA)
        holder:SetScript("OnSizeChanged", Model.Place)
        local ok, scene = pcall(CreateFrame, "ModelScene", nil, holder, "ModelSceneMixinTemplate")
        if ok and scene then
            scene:SetAllPoints(holder)
            scene:EnableMouse(true)
            -- HookScript so the template's own scripts keep running.
            scene:HookScript("OnMouseDown", function(_, button) if button == "LeftButton" then Model.StartDrag() end end)
            scene:HookScript("OnMouseUp", function() Model.StopDrag() end)
            scene:HookScript("OnHide", function() Model.StopDrag() end)
            scene:HookScript("OnMouseWheel", function() Model.SaveZoom() end)
            scene:HookScript("OnUpdate", Model.OnUpdate)
            Model.scene = scene
        end
        Model.Paint()
        return holder
    end

    function Model.Place()
        local h = Model.holder
        if not h then return end
        local w, ht = h:GetWidth() or 0, h:GetHeight() or 0
        h.glow:ClearAllPoints()
        h.glow:SetPoint("CENTER", h, "CENTER", 0, ht * Model.GLOW_UP)
        h.glow:SetSize(w * Model.GLOW_W, ht * Model.GLOW_H)
        h.shadow:ClearAllPoints()
        h.shadow:SetPoint("CENTER", h, "BOTTOM", 0, ht * Model.FEET)
        h.shadow:SetSize(w * Model.SHADOW_W, Model.SHADOW_H)
    end

    function Model.Paint()
        if not Model.holder then return end
        local on = ns.Setting("glow") ~= false
        Model.holder.glow:SetShown(on)
        if on then ns.Colors.Glow(Model.holder.glow, Model.GLOW_ALPHA) end
    end

    -- Sets up your pet like the game's pet sheet. False if the scene or actor is missing.
    local function setUpPet(scene)
        local id = C_PetInfo and type(C_PetInfo.GetPetUIModelSceneID) == "function" and C_PetInfo.GetPetUIModelSceneID()
        if type(id) ~= "number" or id == 0 then id = PET_SCENE end
        if type(scene.TransitionToModelSceneID) ~= "function" or type(scene.GetActorByTag) ~= "function" then return false end
        if type(scene.ReleaseAllActors) == "function" then scene:ReleaseAllActors() end
        scene:TransitionToModelSceneID(id, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
        local a = scene:GetActorByTag("pet")
        Model.actor = a
        if type(a) ~= "table" or type(a.SetModelByUnitCreatureDisplayID) ~= "function" then return false end
        a:SetModelByUnitCreatureDisplayID("pet")
        return true
    end

    -- Runs the game's setup on every open and stays hidden until the actor
    -- loads. rise is how far the window lifts in as it shows, so the model
    -- can follow (Model.Ride).
    function Model.SetUp(rise)
        local scene = Model.scene
        if not scene then return end
        if kind ~= "pet" and not (type(ModelSceneUtil) == "table" and type(ModelSceneUtil.SetUpCharacterSheetScene) == "function") then return end
        Model.speed, Model.dragging = 0, false
        scene:SetAlpha(0)
        Model.Offset(0)
        if kind == "pet" then
            local ok, done = pcall(setUpPet, scene)
            if not (ok and done) then Model.actor = nil end
        else
            pcall(ModelSceneUtil.SetUpCharacterSheetScene, scene)
        end
        Model.waited, Model.waiting = 0, true
        Model.ride = { t = 0, rise = rise or 0 }
        Model.base = nil   -- setup resets the camera, so re-read its distance once loaded
    end

    function Model.Dress(slot)
        local a = Model.Actor()
        if a and type(a.DressPlayerSlot) == "function" and type(slot) == "number" then pcall(a.DressPlayerSlot, a, slot) end
    end

    -- Frames closer than the game does, starting from the distance it set. The
    -- base is kept per setup so re-framing never compounds. The camera frames by
    -- width (a box 2.6x wider drew the model 2.6x bigger), so the spread pulls
    -- it back by the same amount. Limits leave room to zoom out to Model.ROOM.
    -- Tall models back off until they fit (Model.FitDistance). The last zoom is
    -- saved per character as a fraction of the start.
    local function camera()
        local s = Model.scene
        local cam = s and type(s.GetActiveCamera) == "function" and s:GetActiveCamera()
        if type(cam) ~= "table" or type(cam.GetZoomDistance) ~= "function" or type(cam.SetZoomDistance) ~= "function" then return end
        return cam
    end

    -- Camera distance at which the whole model fills Model.FILL of the box's
    -- height, from its bounding box, scale and the camera's field of view. Nil
    -- if unknown. The game uses one distance for every race, so tall races
    -- overflowed the closer start.
    function Model.FitDistance(boxW, boxH)
        local s, a = Model.scene, Model.Actor()
        if not (s and a) or boxW <= 0 or boxH <= 0 then return end
        if type(a.GetActiveBoundingBox) ~= "function" or type(s.GetCameraFieldOfView) ~= "function" then return end
        -- The docs say two vectors, but in game it returns six numbers
        -- (min x, y, z, max x, y, z). Handle both.
        local box = { pcall(a.GetActiveBoundingBox, a) }
        if not box[1] then return end
        local bottom, top
        if type(box[2]) == "table" and type(box[3]) == "table" then
            bottom, top = box[2].z, box[3].z
        else
            bottom, top = box[4], box[7]
        end
        if type(bottom) ~= "number" or type(top) ~= "number" then return end
        local scale = 1
        if type(a.GetScale) == "function" then
            local okS, v = pcall(a.GetScale, a)
            if okS and type(v) == "number" and v > 0 then scale = v end
        end
        local okF, fov = pcall(s.GetCameraFieldOfView, s)
        if not (okF and type(fov) == "number" and fov > 0 and fov < math.pi) then return end
        local tall = (top - bottom) * scale
        if tall <= 0 then return end
        return tall * boxW / (Model.FILL * 2 * math.tan(fov / 2) * boxH)
    end

    -- Saved zoom per character, as a fraction of the start.
    local function saved()
        local c = DUI.DB and DUI.DB.Character and DUI.DB.Character()
        local v = type(c) == "table" and c.modelZoom and c.modelZoom[kind]
        return type(v) == "number" and v > 0 and v or nil
    end

    function Model.SaveZoom()
        local cam = camera()
        if not (cam and Model.start) or Model.waiting then return end
        local ok, d = pcall(cam.GetZoomDistance, cam)
        local c = DUI.DB and DUI.DB.Character and DUI.DB.Character()
        if not (ok and type(d) == "number" and type(c) == "table") then return end
        c.modelZoom = type(c.modelZoom) == "table" and c.modelZoom or {}
        c.modelZoom[kind] = d / Model.start
    end

    function Model.Zoom()
        local h = Model.holder
        local cam = camera()
        if not cam then return end
        if not Model.base then
            local ok, d = pcall(cam.GetZoomDistance, cam)
            if not ok or type(d) ~= "number" then return end
            Model.base = d
        end
        local w = h and h:GetWidth() or 0
        local boxW = w + 2 * (Model.spread or 0)
        local wide = w > 0 and boxW / w or 1
        local want = Model.base * Model.ZOOM * wide
        local fit = Model.FitDistance(boxW, h and h:GetHeight() or 0)
        if fit and fit > want then want = fit end
        Model.start = want
        local function limit(get, set, keep)
            if type(cam[get]) ~= "function" or type(cam[set]) ~= "function" then return end
            local ok, v = pcall(cam[get], cam)
            if ok and type(v) == "number" and keep(v) then pcall(cam[set], cam, keep(v)) end
        end
        limit("GetMinZoomDistance", "SetMinZoomDistance", function(min) return min > want and want or nil end)
        limit("GetMaxZoomDistance", "SetMaxZoomDistance", function(max)
            local room = want * Model.ROOM
            return max < room and room or nil
        end)
        -- Restore the saved zoom, clamped to the camera's limits.
        local d, keep = want, saved()
        if keep then
            d = want * keep
            local okMin, min = pcall(cam.GetMinZoomDistance, cam)
            local okMax, max = pcall(cam.GetMaxZoomDistance, cam)
            if okMin and type(min) == "number" and d < min then d = min end
            if okMax and type(max) == "number" and d > max then d = max end
        end
        pcall(cam.SetZoomDistance, cam, d)
        if type(cam.SnapAllInterpolatedValues) == "function" then pcall(cam.SnapAllInterpolatedValues, cam) end
    end

    -- Offsets the scene by y px. A 3D model doesn't follow the window's lift
    -- animation, so it's moved by hand. 0 puts it back.
    -- The scene also extends Model.spread px on each side, under the slot
    -- columns, so wide models (shields, weapons) aren't clipped. The camera
    -- stays centered.
    function Model.Offset(y)
        local s, h = Model.scene, Model.holder
        local spread = Model.spread or 0
        if not (s and h) or (Model.offset == y and Model.placedSpread == spread) then return end
        Model.offset, Model.placedSpread = y, spread
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", h, "TOPLEFT", -spread, y)
        s:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", spread, y)
    end

    function Model.Spread(px)
        Model.spread = px
        Model.Offset(Model.offset or 0)
        if Model.base then Model.Zoom() end
    end

    -- Matches the window's lift over Motion.NORMAL. Returns the offset at time t
    -- and an alpha, which is only used when the model loaded too late to ride
    -- the window's fade.
    function Model.Ride(t, rise)
        local p = math.min(1, math.max(0, t / DUI.Motion.NORMAL))
        local e = 1 - (1 - p) * (1 - p)
        return -(rise or 0) * (1 - e), e
    end

    local function riding(elapsed)
        local r = Model.ride
        if not r then return end
        r.t = r.t + (elapsed or 0)
        if Model.waiting then return end
        if not (DUI.Motion and DUI.Motion.On()) then
            Model.ride = nil
            Model.Offset(0)
            Model.scene:SetAlpha(1)
            return
        end
        -- Loaded after the window stopped moving, so just fade in place.
        if r.late == nil then
            r.late = r.t > DUI.Motion.NORMAL
            if r.late then r.t, r.rise = 0, 0 end
        end
        local y, e = Model.Ride(r.t, r.rise)
        Model.Offset(y)
        -- Loaded in time, so the window's own fade carries it.
        local a = r.late and e or 1
        Model.scene:SetAlpha(a)
        if e >= 1 then Model.ride = nil end
    end

    function Model.OnUpdate(_, elapsed)
        if Model.waiting then
            Model.waited = Model.waited + (elapsed or 0)
            local a = Model.Actor()
            if (a and a.IsLoaded and a:IsLoaded()) or Model.waited >= Model.WAIT then
                Model.waiting = false
                Model.Zoom()
            end
        end
        riding(elapsed)
        local a = Model.Actor()
        if not (a and a.SetYaw and a.GetYaw) then return end
        if Model.dragging then
            local x = GetCursorPosition()
            Model.speed = (x - (Model.lastX or x)) * Model.TURN
            Model.lastX = x
        elseif DUI.Motion and DUI.Motion.On() then
            Model.speed = (Model.speed or 0) * Model.SETTLE
            if math.abs(Model.speed) < Model.STOP then Model.speed = 0 end
        else
            Model.speed = 0
        end
        if Model.speed ~= 0 then a:SetYaw(a:GetYaw() + Model.speed) end
    end

    return Model
end

local Model = make("player")
ns.Model = Model
ns.PetModel = make("pet")
