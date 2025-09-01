include("shared.lua")

-- Optional queue include to throttle RemixLight operations
if file.Exists("remixlua/cl/remixapi/cl_remix_light_queue.lua", "LUA") then
    include("remixlua/cl/remixapi/cl_remix_light_queue.lua")
end

local function vec_to_table(v) return { x = v.x, y = v.y, z = v.z } end

function ENT:Draw()
    self:DrawModel()
end

local function ensure_light(ent)
    -- Add defensive checks to prevent multiple creation attempts
    if not IsValid(ent) then return end
    if ent.LightId then return end  -- Already has a light
    if ent.LightCreateQueued then return end  -- Already trying to create
    if not RemixLight then return end  -- API not available
    
    local pos = ent:GetPos() + Vector(0,0,10)
    local ang = ent:GetAngles()
    local dir = ang:Forward()
    local lt = ent:GetNWString("rtx_light_type", "sphere")
    local col = ent:GetNWVector("rtx_light_col", Vector(15,15,15))
    local radius = ent:GetNWFloat("rtx_light_radius", 20)
    local volScale = ent:GetNWFloat("rtx_light_volumetric", 1.0)

    local base = {
        -- Use decimal CRC to avoid nil from base-16 conversion; ensures unique, stable hash per entity
        hash = tonumber(util.CRC("ent_light_" .. ent:EntIndex())) or 1,
        radiance = { x = col.x, y = col.y, z = col.z },
    }

    -- Mark as queued before attempting creation
    ent.LightCreateQueued = true

    local createdId = nil
    if lt == "sphere" then
        local sphere = {
            position = vec_to_table(pos),
            radius = radius,
            volumetricRadianceScale = volScale,
        }
        local shapingEnabled = ent:GetNWBool("rtx_light_shape_enabled", false)
        if shapingEnabled then
            sphere.shaping = { direction = { x = dir.x, y = dir.y, z = dir.z }, coneAngleDegrees = ent:GetNWFloat("rtx_light_shape_cone", 90), coneSoftness = ent:GetNWFloat("rtx_light_shape_softness", 0.1), focusExponent = ent:GetNWFloat("rtx_light_shape_focus", 1.0) }
        end
        if RemixLightQueue and RemixLightQueue.CreateSphere then
            createdId = RemixLightQueue.CreateSphere(base, sphere, ent:EntIndex())
        elseif RemixLight.CreateSphere then
            createdId = RemixLight.CreateSphere(base, sphere, ent:EntIndex())
        end
    elseif lt == "cylinder" then
        local cyl = {
            position = vec_to_table(pos),
            radius = radius,
            axis = { x = ang:Up().x, y = ang:Up().y, z = ang:Up().z },
            axisLength = ent:GetNWFloat("rtx_light_axis_len", radius*2),
            volumetricRadianceScale = volScale,
        }
        if RemixLightQueue and RemixLightQueue.CreateCylinder then
            createdId = RemixLightQueue.CreateCylinder(base, cyl, ent:EntIndex())
        elseif RemixLight.CreateCylinder then
            createdId = RemixLight.CreateCylinder(base, cyl, ent:EntIndex())
        end
    elseif lt == "disk" then
        local disk = {
            position = vec_to_table(pos),
            xAxis = { x = ang:Right().x, y = ang:Right().y, z = ang:Right().z }, xRadius = ent:GetNWFloat("rtx_light_xradius", radius),
            yAxis = { x = ang:Up().x, y = ang:Up().y, z = ang:Up().z }, yRadius = ent:GetNWFloat("rtx_light_yradius", radius),
            direction = { x = dir.x, y = dir.y, z = dir.z },
            volumetricRadianceScale = volScale,
        }
        if RemixLightQueue and RemixLightQueue.CreateDisk then
            createdId = RemixLightQueue.CreateDisk(base, disk, ent:EntIndex())
        elseif RemixLight.CreateDisk then
            createdId = RemixLight.CreateDisk(base, disk, ent:EntIndex())
        end
    elseif lt == "rect" then
        local rect = {
            position = vec_to_table(pos),
            xAxis = { x = ang:Right().x, y = ang:Right().y, z = ang:Right().z }, xSize = ent:GetNWFloat("rtx_light_xsize", radius*2),
            yAxis = { x = ang:Up().x, y = ang:Up().y, z = ang:Up().z }, ySize = ent:GetNWFloat("rtx_light_ysize", radius*2),
            direction = { x = dir.x, y = dir.y, z = dir.z },
            volumetricRadianceScale = volScale,
        }
        if RemixLightQueue and RemixLightQueue.CreateRect then
            createdId = RemixLightQueue.CreateRect(base, rect, ent:EntIndex())
        elseif RemixLight.CreateRect then
            createdId = RemixLight.CreateRect(base, rect, ent:EntIndex())
        end
    elseif lt == "distant" then
        local distant = { direction = { x = dir.x, y = dir.y, z = dir.z }, angularDiameterDegrees = ent:GetNWFloat("rtx_light_distant_angle", 0.5), volumetricRadianceScale = volScale }
        if RemixLightQueue and RemixLightQueue.CreateDistant then
            createdId = RemixLightQueue.CreateDistant(base, distant, ent:EntIndex())
        elseif RemixLight.CreateDistant then
            createdId = RemixLight.CreateDistant(base, distant, ent:EntIndex())
        end
    elseif lt == "dome" then
        local tex = ent:GetNWString("rtx_light_dome_tex", "")
        local dome = { colorTexture = (tex ~= "" and tex or nil) }
        if RemixLightQueue and RemixLightQueue.CreateDome then
            createdId = RemixLightQueue.CreateDome(base, dome, ent:EntIndex())
        elseif RemixLight.CreateDome then
            createdId = RemixLight.CreateDome(base, dome, ent:EntIndex())
        end
    end

    ent.LightId = createdId
    ent.LightCreateQueued = nil
end

function ENT:Think()
    -- Ensure we have a light, but be defensive about it
    if not self.LightId and not self.LightCreateQueued then
        ensure_light(self)
    end
    
    -- Only update if we have a valid light ID and the API is available
    if not self.LightId or not RemixLight then return end
    
    local pos = self:GetNWVector("rtx_light_pos", self:GetPos())
    local col = self:GetNWVector("rtx_light_col", Vector(15,15,15))
    local radius = self:GetNWFloat("rtx_light_radius", 20)
    local shapingEnabled = self:GetNWBool("rtx_light_shape_enabled", false)
    local cone = self:GetNWFloat("rtx_light_shape_cone", 90)
    local softness = self:GetNWFloat("rtx_light_shape_softness", 0.1)
    local focus = self:GetNWFloat("rtx_light_shape_focus", 1.0)
    local ang = self:GetAngles()
    local dir = ang:Forward()
    local volScale = self:GetNWFloat("rtx_light_volumetric", 1.0)

    if true then  -- Simplified check since we already validated above
        local base = {
            hash = tonumber(util.CRC("ent_light_" .. self:EntIndex())) or 1,
            radiance = { x = col.x, y = col.y, z = col.z },
        }
        local lt = self:GetNWString("rtx_light_type", "sphere")
        if lt == "sphere" and (RemixLight.UpdateSphere or (RemixLightQueue and RemixLightQueue.UpdateSphere)) then
            local sphere = {
                position = vec_to_table(pos),
                radius = radius,
                volumetricRadianceScale = volScale,
            }
            if shapingEnabled then
                sphere.shaping = { direction = { x = dir.x, y = dir.y, z = dir.z }, coneAngleDegrees = cone, coneSoftness = softness, focusExponent = focus }
            end
            if RemixLightQueue and RemixLightQueue.UpdateSphere then
                RemixLightQueue.UpdateSphere(base, sphere, self.LightId)
            else
                RemixLight.UpdateSphere(base, sphere, self.LightId)
            end
        elseif lt == "cylinder" and (RemixLight.UpdateCylinder or (RemixLightQueue and RemixLightQueue.UpdateCylinder)) then
            local cyl = {
                position = vec_to_table(pos),
                radius = radius,
                axis = { x = ang:Up().x, y = ang:Up().y, z = ang:Up().z },
                axisLength = self:GetNWFloat("rtx_light_axis_len", radius*2),
                volumetricRadianceScale = volScale,
            }
            if RemixLightQueue and RemixLightQueue.UpdateCylinder then
                RemixLightQueue.UpdateCylinder(base, cyl, self.LightId)
            else
                RemixLight.UpdateCylinder(base, cyl, self.LightId)
            end
        elseif lt == "disk" and (RemixLight.UpdateDisk or (RemixLightQueue and RemixLightQueue.UpdateDisk)) then
            local disk = {
                position = vec_to_table(pos),
                xAxis = { x = ang:Right().x, y = ang:Right().y, z = ang:Right().z }, xRadius = self:GetNWFloat("rtx_light_xradius", radius),
                yAxis = { x = ang:Up().x, y = ang:Up().y, z = ang:Up().z }, yRadius = self:GetNWFloat("rtx_light_yradius", radius),
                direction = { x = dir.x, y = dir.y, z = dir.z },
                volumetricRadianceScale = volScale,
            }
            if RemixLightQueue and RemixLightQueue.UpdateDisk then
                RemixLightQueue.UpdateDisk(base, disk, self.LightId)
            else
                RemixLight.UpdateDisk(base, disk, self.LightId)
            end
        elseif lt == "rect" and (RemixLight.UpdateRect or (RemixLightQueue and RemixLightQueue.UpdateRect)) then
            local rect = {
                position = vec_to_table(pos),
                xAxis = { x = ang:Right().x, y = ang:Right().y, z = ang:Right().z }, xSize = self:GetNWFloat("rtx_light_xsize", radius*2),
                yAxis = { x = ang:Up().x, y = ang:Up().y, z = ang:Up().z }, ySize = self:GetNWFloat("rtx_light_ysize", radius*2),
                direction = { x = dir.x, y = dir.y, z = dir.z },
                volumetricRadianceScale = volScale,
            }
            if RemixLightQueue and RemixLightQueue.UpdateRect then
                RemixLightQueue.UpdateRect(base, rect, self.LightId)
            else
                RemixLight.UpdateRect(base, rect, self.LightId)
            end
        elseif lt == "distant" and (RemixLight.UpdateDistant or (RemixLightQueue and RemixLightQueue.UpdateDistant)) then
            local distant = { direction = { x = dir.x, y = dir.y, z = dir.z }, angularDiameterDegrees = self:GetNWFloat("rtx_light_distant_angle", 0.5), volumetricRadianceScale = volScale }
            if RemixLightQueue and RemixLightQueue.UpdateDistant then
                RemixLightQueue.UpdateDistant(base, distant, self.LightId)
            else
                RemixLight.UpdateDistant(base, distant, self.LightId)
            end
        elseif lt == "dome" and (RemixLight.UpdateDome or (RemixLightQueue and RemixLightQueue.UpdateDome)) then
            local tex = self:GetNWString("rtx_light_dome_tex", "")
            local dome = { colorTexture = (tex ~= "" and tex or nil) }
            if RemixLightQueue and RemixLightQueue.UpdateDome then
                RemixLightQueue.UpdateDome(base, dome, self.LightId)
            else
                RemixLight.UpdateDome(base, dome, self.LightId)
            end
        end
    end
end

-- Context menu for tweaking light parameters
function ENT:PopulateToolMenu(panel)
    -- Not used; using context menu hook below
end

properties.Add("remix_rt_light_edit", {
    MenuLabel = "Edit Remix Light", Order = 0, MenuIcon = "icon16/lightbulb.png",
    Filter = function(self, ent, ply)
        return IsValid(ent) and ent:GetClass() == "remix_rt_light" and ply:IsAdmin() ~= false
    end,
    Action = function(self, ent)
        self:OpenEditor(ent)
    end,
    OpenEditor = function(self, ent)
        if not IsValid(ent) then return end
        local frame = vgui.Create("DFrame")
        frame:SetTitle("Remix Light")
        frame:SetSize(math.min(ScrW()*0.35, 420), math.min(ScrH()*0.7, 520))
        frame:SetSizable(true)
        frame:Center()
        frame:MakePopup()

        local body = vgui.Create("DScrollPanel", frame)
        body:Dock(FILL)
        body:DockMargin(0, 0, 0, 40)

        local typeCombo = vgui.Create("DComboBox", body)
        typeCombo:Dock(TOP)
        typeCombo:DockMargin(10, 10, 10, 5)
        local lt_init = ent:GetNWString("rtx_light_type", "sphere")
        typeCombo:AddChoice("SPHERE", "sphere")
        typeCombo:AddChoice("RECT", "rect")
        typeCombo:AddChoice("DISK", "disk")
        typeCombo:AddChoice("CYLINDER", "cylinder")
        typeCombo:AddChoice("DISTANT", "distant")
        typeCombo:AddChoice("DOME", "dome")
        -- Ensure internal selected ID/data is set so refreshVisibility reads the correct type
        if typeCombo.ChooseOption then
            typeCombo:ChooseOption(string.upper(lt_init))
        else
            typeCombo:SetValue(string.upper(lt_init))
        end

        local radius = vgui.Create("DNumSlider", body)
        radius:Dock(TOP)
        radius:DockMargin(10, 5, 10, 5)
        radius:SetText("Radius")
        radius:SetMin(1)
        radius:SetMax(200)
        radius:SetDecimals(0)
        radius:SetValue(ent:GetNWFloat("rtx_light_radius", 20))

        local vol = vgui.Create("DNumSlider", body)
        vol:Dock(TOP)
        vol:DockMargin(10, 5, 10, 5)
        vol:SetText("Volumetrics Scale")
        vol:SetMin(0)
        vol:SetMax(5)
        vol:SetDecimals(2)
        vol:SetValue(ent:GetNWFloat("rtx_light_volumetric", 1))

        local mixer = vgui.Create("DColorMixer", body)
        mixer:Dock(TOP)
        mixer:DockMargin(10, 5, 10, 10)
        mixer:SetTall(140)
        mixer:SetAlphaBar(false)
        mixer:SetPalette(false)
        mixer:SetWangs(true)
        local c = ent:GetNWVector("rtx_light_col", Vector(15,15,15))
        mixer:SetColor(Color(c.x*12, c.y*12, c.z*12))

        local brightness = vgui.Create("DNumSlider", body)
        brightness:Dock(TOP)
        brightness:DockMargin(10, 5, 10, 5)
        brightness:SetText("Brightness")
        brightness:SetMin(0)
        brightness:SetMax(10)
        brightness:SetDecimals(2)
        brightness:SetValue(ent:GetNWFloat("rtx_light_brightness", 1))

        -- Sphere shaping
        local shapeToggle = vgui.Create("DCheckBoxLabel", body)
        shapeToggle:Dock(TOP)
        shapeToggle:DockMargin(10, 5, 10, 5)
        shapeToggle:SetText("Enable Light Shaping")
        shapeToggle:SetValue(ent:GetNWBool("rtx_light_shape_enabled", false) and 1 or 0)

        local cone = vgui.Create("DNumSlider", body)
        cone:Dock(TOP)
        cone:DockMargin(10, 5, 10, 5)
        cone:SetText("Cone Angle (deg)")
        cone:SetMin(0)
        cone:SetMax(180)
        cone:SetDecimals(0)
        cone:SetValue(ent:GetNWFloat("rtx_light_shape_cone", 90))

        local soft = vgui.Create("DNumSlider", body)
        soft:Dock(TOP)
        soft:DockMargin(10, 5, 10, 5)
        soft:SetText("Cone Softness")
        soft:SetMin(0)
        soft:SetMax(1)
        soft:SetDecimals(2)
        soft:SetValue(ent:GetNWFloat("rtx_light_shape_softness", 0.1))

        local focus = vgui.Create("DNumSlider", body)
        focus:Dock(TOP)
        focus:DockMargin(10, 5, 10, 5)
        focus:SetText("Focus Exponent")
        focus:SetMin(0)
        focus:SetMax(10)
        focus:SetDecimals(2)
        focus:SetValue(ent:GetNWFloat("rtx_light_shape_focus", 1.0))

        -- direction is taken from the entity's rotation; no manual yaw/pitch here

        -- Per-type extra controls
        local xsize = vgui.Create("DNumSlider", body)
        xsize:Dock(TOP)
        xsize:DockMargin(10, 5, 10, 5)
        xsize:SetText("Rect X Size")
        xsize:SetMin(1)
        xsize:SetMax(400)
        xsize:SetDecimals(0)
        xsize:SetValue(ent:GetNWFloat("rtx_light_xsize", 40))

        local ysize = vgui.Create("DNumSlider", body)
        ysize:Dock(TOP)
        ysize:DockMargin(10, 5, 10, 5)
        ysize:SetText("Rect Y Size")
        ysize:SetMin(1)
        ysize:SetMax(400)
        ysize:SetDecimals(0)
        ysize:SetValue(ent:GetNWFloat("rtx_light_ysize", 40))

        local xradius = vgui.Create("DNumSlider", body)
        xradius:Dock(TOP)
        xradius:DockMargin(10, 5, 10, 5)
        xradius:SetText("Disk X Radius")
        xradius:SetMin(1)
        xradius:SetMax(200)
        xradius:SetDecimals(0)
        xradius:SetValue(ent:GetNWFloat("rtx_light_xradius", 20))

        local yradius = vgui.Create("DNumSlider", body)
        yradius:Dock(TOP)
        yradius:DockMargin(10, 5, 10, 5)
        yradius:SetText("Disk Y Radius")
        yradius:SetMin(1)
        yradius:SetMax(200)
        yradius:SetDecimals(0)
        yradius:SetValue(ent:GetNWFloat("rtx_light_yradius", 20))

        local axislen = vgui.Create("DNumSlider", body)
        axislen:Dock(TOP)
        axislen:DockMargin(10, 5, 10, 5)
        axislen:SetText("Cylinder Axis Length")
        axislen:SetMin(1)
        axislen:SetMax(400)
        axislen:SetDecimals(0)
        axislen:SetValue(ent:GetNWFloat("rtx_light_axis_len", 40))

        local distantang = vgui.Create("DNumSlider", body)
        distantang:Dock(TOP)
        distantang:DockMargin(10, 5, 10, 5)
        distantang:SetText("Distant Angular Diameter")
        distantang:SetMin(0)
        distantang:SetMax(10)
        distantang:SetDecimals(2)
        distantang:SetValue(ent:GetNWFloat("rtx_light_distant_angle", 0.5))

        local dometex = vgui.Create("DTextEntry", body)
        dometex:Dock(TOP)
        dometex:DockMargin(10, 5, 10, 5)
        dometex:SetPlaceholderText("Dome Texture Path")
        dometex:SetValue(ent:GetNWString("rtx_light_dome_tex", ""))

        -- Realtime apply as user adjusts controls
        -- Throttled server apply helper
        local function sendApplyThrottled()
            if not IsValid(ent) then return end
            local id = ent:EntIndex()
            local timerName = "remix_rt_light_apply_" .. tostring(id)
            timer.Create(timerName, 0.15, 1, function()
                if not IsValid(ent) then return end
                if not net then return end
                net.Start("remix_rt_light_apply")
                net.WriteEntity(ent)
                -- Build a compact table of values
                local t = {
                    rtx_light_type = (function()
                        local sid = typeCombo:GetSelectedID()
                        return (sid and typeCombo:GetOptionData(sid)) or ent:GetNWString("rtx_light_type", "sphere")
                    end)(),
                    rtx_light_radius = math.Clamp(math.floor(radius:GetValue()), 1, 200),
                    rtx_light_brightness = brightness:GetValue(),
                    rtx_light_volumetric = vol:GetValue(),
                    rtx_light_shape_enabled = shapeToggle:GetChecked() and true or false,
                    rtx_light_shape_cone = cone:GetValue(),
                    rtx_light_shape_softness = soft:GetValue(),
                    rtx_light_shape_focus = focus:GetValue(),
                    rtx_light_xsize = xsize:GetValue(),
                    rtx_light_ysize = ysize:GetValue(),
                    rtx_light_xradius = xradius:GetValue(),
                    rtx_light_yradius = yradius:GetValue(),
                    rtx_light_axis_len = axislen:GetValue(),
                    rtx_light_distant_angle = distantang:GetValue(),
                    rtx_light_dome_tex = dometex:GetValue(),
                }
                local col = mixer:GetColor()
                local scale = math.max(0.0, brightness:GetValue())
                local vec = Vector((col.r/12)*scale, (col.g/12)*scale, (col.b/12)*scale)
                t.rtx_light_col = { x = vec.x, y = vec.y, z = vec.z }
                net.WriteTable(t)
                net.SendToServer()
            end)
        end

        local function applyRealtime()
            local col = mixer:GetColor()
            ent:SetNWFloat("rtx_light_radius", math.Clamp(math.floor(radius:GetValue()), 1, 200))
            ent:SetNWFloat("rtx_light_brightness", brightness:GetValue())
            ent:SetNWFloat("rtx_light_volumetric", vol:GetValue())
            ent:SetNWBool("rtx_light_shape_enabled", shapeToggle:GetChecked())
            ent:SetNWFloat("rtx_light_shape_cone", cone:GetValue())
            ent:SetNWFloat("rtx_light_shape_softness", soft:GetValue())
            ent:SetNWFloat("rtx_light_shape_focus", focus:GetValue())
            ent:SetNWFloat("rtx_light_xsize", xsize:GetValue())
            ent:SetNWFloat("rtx_light_ysize", ysize:GetValue())
            ent:SetNWFloat("rtx_light_xradius", xradius:GetValue())
            ent:SetNWFloat("rtx_light_yradius", yradius:GetValue())
            ent:SetNWFloat("rtx_light_axis_len", axislen:GetValue())
            ent:SetNWFloat("rtx_light_distant_angle", distantang:GetValue())
            ent:SetNWString("rtx_light_dome_tex", dometex:GetValue())
            local scale = math.max(0.0, brightness:GetValue())
            ent:SetNWVector("rtx_light_col", Vector((col.r/12)*scale, (col.g/12)*scale, (col.b/12)*scale))
            local sid = typeCombo:GetSelectedID()
            local sel = (sid and typeCombo:GetOptionData(sid)) or ent:GetNWString("rtx_light_type", "sphere")
            ent:SetNWString("rtx_light_type", sel)
            -- send authoritative apply to server
            sendApplyThrottled()
        end

        radius.OnValueChanged = function(_, _val)
            applyRealtime()
        end

        if mixer.ValueChanged then
            function mixer:ValueChanged(_col)
                applyRealtime()
            end
        else
            timer.Simple(0, function()
                if IsValid(frame) and IsValid(ent) then
                    applyRealtime()
                end
            end)
        end

        brightness.OnValueChanged = function(_, _val)
            applyRealtime()
        end

        shapeToggle.OnChange = function(_, _val) applyRealtime() end
        vol.OnValueChanged = function(_, _val) applyRealtime() end
        cone.OnValueChanged = function(_, _val) applyRealtime() end
        soft.OnValueChanged = function(_, _val) applyRealtime() end
        focus.OnValueChanged = function(_, _val) applyRealtime() end
        xsize.OnValueChanged = function(_, _val) applyRealtime() end
        ysize.OnValueChanged = function(_, _val) applyRealtime() end
        xradius.OnValueChanged = function(_, _val) applyRealtime() end
        yradius.OnValueChanged = function(_, _val) applyRealtime() end
        axislen.OnValueChanged = function(_, _val) applyRealtime() end
        distantang.OnValueChanged = function(_, _val) applyRealtime() end
        dometex.OnChange = function() applyRealtime() end

        -- Show only relevant controls per light type
        local function refreshVisibility()
            local selectedId = typeCombo:GetSelectedID()
            local lt = (selectedId and typeCombo:GetOptionData(selectedId)) or ent:GetNWString("rtx_light_type", "sphere")
            -- hide all optional controls first
            shapeToggle:SetVisible(false)
            cone:SetVisible(false)
            soft:SetVisible(false)
            focus:SetVisible(false)
            xsize:SetVisible(false)
            ysize:SetVisible(false)
            xradius:SetVisible(false)
            yradius:SetVisible(false)
            axislen:SetVisible(false)
            distantang:SetVisible(false)
            dometex:SetVisible(false)
            -- Always show common
            radius:SetVisible(true)
            brightness:SetVisible(true)
            mixer:SetVisible(true)
            vol:SetVisible(true)
            if lt == "sphere" then
                shapeToggle:SetVisible(true)
                cone:SetVisible(true)
                soft:SetVisible(true)
                focus:SetVisible(true)
            elseif lt == "rect" then
                xsize:SetVisible(true)
                ysize:SetVisible(true)
            elseif lt == "disk" then
                xradius:SetVisible(true)
                yradius:SetVisible(true)
            elseif lt == "cylinder" then
                axislen:SetVisible(true)
            elseif lt == "distant" then
                distantang:SetVisible(true)
            elseif lt == "dome" then
                dometex:SetVisible(true)
            end
        end
        refreshVisibility()
        -- One-time initial apply to sync UI state without forcing defaults
        applyRealtime()
        typeCombo.OnSelect = function()
            applyRealtime()
            refreshVisibility()
        end

        local close = vgui.Create("DButton", frame)
        close:Dock(BOTTOM)
        close:DockMargin(10, 5, 10, 10)
        close:SetText("Close")
        close.DoClick = function()
            frame:Close()
        end
    end
})

function ENT:OnRemove()
    -- Defensive cleanup - ensure we properly destroy the light
    if self.LightId then
        local destroyed = false
        
        -- Try the queue first (which now does synchronous destroy)
        if RemixLightQueue and RemixLightQueue.DestroyLight then
            destroyed = RemixLightQueue.DestroyLight(self.LightId)
        end
        
        -- Fallback to direct API if queue failed
        if not destroyed and RemixLight and RemixLight.DestroyLight then
            RemixLight.DestroyLight(self.LightId)
        end
        
        self.LightId = nil
    end
    
    -- Also try to clean up by entity ID as a fallback
    -- This catches cases where the light was created but LightId wasn't set properly
    if RemixLight and RemixLight.DestroyLightsForEntity then
        RemixLight.DestroyLightsForEntity(self:EntIndex())
    end
    
    -- Clear any pending creation flag
    self.LightCreateQueued = nil
end


