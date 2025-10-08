include("shared.lua")

-- Optional queue include to throttle RemixLight operations
if file.Exists("remixlua/cl/remixapi/cl_remix_light_queue.lua", "LUA") then
    include("remixlua/cl/remixapi/cl_remix_light_queue.lua")
end

local cv_visualize = CreateClientConVar("remix_rt_light_visualize", "1", true, false, "Show HUD visualization for RTX lights")
local cv_vis_range = CreateClientConVar("remix_rt_light_visualize_range", "2048", true, false, "Max distance to show light visualization")
local cv_vis_always = CreateClientConVar("remix_rt_light_visualize_always", "0", true, false, "Always show visualization, even when not looking at lights")
local cv_vis_scale = CreateClientConVar("remix_rt_light_visualize_scale", "1.0", true, false, "Scale factor for visualization size (0.1 to 10.0)")
local cv_vis_fill_opacity = CreateClientConVar("remix_rt_light_visualize_fill_opacity", "30", true, false, "Fill opacity for shape visualization (0-255)")

local function vec_to_table(v) return { x = v.x, y = v.y, z = v.z } end

-- Helper function to draw thick lines
local function DrawThickLine(x1, y1, x2, y2, thickness, r, g, b, a)
    surface.SetDrawColor(r, g, b, a)
    for i = 0, thickness - 1 do
        local offset = i - math.floor(thickness / 2)
        surface.DrawLine(x1 + offset, y1, x2 + offset, y2)
        surface.DrawLine(x1, y1 + offset, x2, y2 + offset)
    end
end

-- Helper function to draw filled polygon from world space points (both sides)
local function DrawFilledWorldPoly(worldPoints, r, g, b, a)
    local screenVerts = {}
    for _, wp in ipairs(worldPoints) do
        local sp = wp:ToScreen()
        if not sp.visible then return end -- Skip if any vertex is not visible
        table.insert(screenVerts, { x = sp.x, y = sp.y })
    end
    
    surface.SetDrawColor(r, g, b, a)
    draw.NoTexture()
    
    -- Draw front face
    surface.DrawPoly(screenVerts)
    
    -- Draw back face (reversed winding order)
    local reversedVerts = {}
    for i = #screenVerts, 1, -1 do
        table.insert(reversedVerts, screenVerts[i])
    end
    surface.DrawPoly(reversedVerts)
end

-- Color scheme for different light types
local lightColors = {
    sphere = Color(255, 200, 100),
    rect = Color(100, 200, 255),
    disk = Color(255, 100, 200),
    cylinder = Color(200, 100, 255),
    distant = Color(255, 255, 100),
    dome = Color(100, 255, 200),
}

local lightIcons = {
    sphere = "●",
    rect = "▭",
    disk = "◯",
    cylinder = "▯",
    distant = "☀",
    dome = "⬒",
}

function ENT:Draw()
    self:DrawModel()
end

-- HUD Paint visualization
hook.Add("HUDPaint", "RemixRTLight_Visualize", function()
    if not cv_visualize:GetBool() then return end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local eyePos = ply:EyePos()
    local eyeAng = ply:EyeAngles()
    local maxRange = cv_vis_range:GetFloat()
    local alwaysShow = cv_vis_always:GetBool()
    local vizScale = math.Clamp(cv_vis_scale:GetFloat(), 0.1, 10.0)
    local fillOpacity = math.Clamp(cv_vis_fill_opacity:GetInt(), 0, 255)
    local lineThickness = 2
    
    for _, ent in ipairs(ents.FindByClass("remix_rt_light")) do
        if not IsValid(ent) then continue end
        
        local pos = ent:GetPos()
        local dist = eyePos:Distance(pos)
        
        -- Range check
        if dist > maxRange then continue end
        
        -- Check if looking towards the light (unless always show is enabled)
        if not alwaysShow then
            local toLight = (pos - eyePos):GetNormalized()
            local dot = eyeAng:Forward():Dot(toLight)
            if dot < 0.3 then continue end -- ~70 degree FOV
        end
        
        local screenPos = pos:ToScreen()
        if not screenPos.visible then continue end
        
        local x, y = screenPos.x, screenPos.y
        local lt = ent:GetNWString("rtx_light_type", "sphere")
        local col = lightColors[lt] or Color(255, 255, 255)
        local radius = ent:GetNWFloat("rtx_light_radius", 20)
        local brightness = ent:GetNWFloat("rtx_light_brightness", 1)
        
        -- Alpha fade based on distance
        local alpha = math.Clamp(255 * (1 - dist / maxRange), 50, 255)
        col.a = alpha
        
        -- Draw icon/symbol
        local icon = lightIcons[lt] or "●"
        draw.SimpleText(icon, "DermaLarge", x, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        -- Draw light type label
        local label = string.upper(lt)
        draw.SimpleText(label, "DermaDefault", x, y + 20, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        
        -- Draw properties
        local info = string.format("R:%.0f B:%.1f", radius, brightness)
        draw.SimpleText(info, "DermaDefaultBold", x, y + 35, Color(255, 255, 255, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        
        -- Draw direction indicator for directional lights
        if lt == "distant" or lt == "rect" or lt == "disk" then
            local ang = ent:GetAngles()
            local dir = ang:Forward()
            local endPos = pos + dir * (radius * 2 * vizScale)
            local endScreen = endPos:ToScreen()
            
            if endScreen.visible then
                DrawThickLine(x, y, endScreen.x, endScreen.y, lineThickness, col.r, col.g, col.b, alpha * 0.8)
                
                -- Draw arrow head
                local arrowLen = 10 * vizScale
                local lineVec = Vector(endScreen.x - x, endScreen.y - y, 0):GetNormalized()
                local perpVec = Vector(-lineVec.y, lineVec.x, 0)
                
                local tip = { x = endScreen.x, y = endScreen.y }
                local left = { x = endScreen.x - lineVec.x * arrowLen + perpVec.x * arrowLen * 0.5, y = endScreen.y - lineVec.y * arrowLen + perpVec.y * arrowLen * 0.5 }
                local right = { x = endScreen.x - lineVec.x * arrowLen - perpVec.x * arrowLen * 0.5, y = endScreen.y - lineVec.y * arrowLen - perpVec.y * arrowLen * 0.5 }
                
                DrawThickLine(tip.x, tip.y, left.x, left.y, lineThickness, col.r, col.g, col.b, alpha * 0.8)
                DrawThickLine(tip.x, tip.y, right.x, right.y, lineThickness, col.r, col.g, col.b, alpha * 0.8)
            end
        end
        
        -- Draw shaping cone indicator for sphere lights
        if lt == "sphere" and ent:GetNWBool("rtx_light_shape_enabled", false) then
            local coneAngle = ent:GetNWFloat("rtx_light_shape_cone", 90)
            local ang = ent:GetAngles()
            local dir = ang:Forward()
            
            -- Draw cone outline
            local coneLen = radius * 1.5 * vizScale
            local coneEnd = pos + dir * coneLen
            local coneRadius = math.tan(math.rad(coneAngle / 2)) * coneLen
            
            -- Draw cone lines with thick lines
            local up = ang:Up() * coneRadius
            local right = ang:Right() * coneRadius
            
            for i = 0, 7 do
                local angle = (i / 8) * math.pi * 2
                local offset = up * math.cos(angle) + right * math.sin(angle)
                local edgePos = coneEnd + offset
                local edgeScreen = edgePos:ToScreen()
                
                if edgeScreen.visible then
                    DrawThickLine(x, y, edgeScreen.x, edgeScreen.y, lineThickness, col.r, col.g, col.b, alpha * 0.5)
                end
            end
            
            -- Draw cone angle text
            draw.SimpleText(string.format("∠%.0f°", coneAngle), "DermaDefault", x, y + 50, Color(255, 200, 100, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
        
        -- Draw 3D shape visualizations for physical dimensions
        local ang = ent:GetAngles()
        
        if lt == "rect" then
            local xsize = ent:GetNWFloat("rtx_light_xsize", 40) * vizScale
            local ysize = ent:GetNWFloat("rtx_light_ysize", 40) * vizScale
            
            -- Calculate rectangle corners in world space
            local right = ang:Right()
            local up = ang:Up()
            local halfX = xsize / 2
            local halfY = ysize / 2
            
            local corners = {
                pos + right * halfX + up * halfY,      -- Top-right
                pos + right * halfX - up * halfY,      -- Bottom-right
                pos - right * halfX - up * halfY,      -- Bottom-left
                pos - right * halfX + up * halfY,      -- Top-left
            }
            
            -- Draw filled rectangle
            if fillOpacity > 0 then
                DrawFilledWorldPoly(corners, col.r, col.g, col.b, fillOpacity * (alpha / 255))
            end
            
            -- Draw rectangle outline with thick lines
            for i = 1, 4 do
                local next_i = (i % 4) + 1
                local c1 = corners[i]:ToScreen()
                local c2 = corners[next_i]:ToScreen()
                if c1.visible and c2.visible then
                    DrawThickLine(c1.x, c1.y, c2.x, c2.y, lineThickness, col.r, col.g, col.b, alpha * 0.9)
                end
            end
            
            draw.SimpleText(string.format("%.0f×%.0f", xsize / vizScale, ysize / vizScale), "DermaDefault", x, y + 50, Color(200, 200, 255, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            
        elseif lt == "disk" then
            local xrad = ent:GetNWFloat("rtx_light_xradius", 20) * vizScale
            local yrad = ent:GetNWFloat("rtx_light_yradius", 20) * vizScale
            
            -- Draw ellipse outline (24 segments)
            local right = ang:Right()
            local up = ang:Up()
            local segments = 24
            
            -- Build ellipse points for fill
            if fillOpacity > 0 then
                local ellipsePoints = {}
                for i = 0, segments - 1 do
                    local angle = (i / segments) * math.pi * 2
                    local p = pos + right * (math.cos(angle) * xrad) + up * (math.sin(angle) * yrad)
                    table.insert(ellipsePoints, p)
                end
                DrawFilledWorldPoly(ellipsePoints, col.r, col.g, col.b, fillOpacity * (alpha / 255))
            end
            
            -- Draw outline with thick lines
            for i = 0, segments - 1 do
                local angle1 = (i / segments) * math.pi * 2
                local angle2 = ((i + 1) / segments) * math.pi * 2
                
                local p1 = pos + right * (math.cos(angle1) * xrad) + up * (math.sin(angle1) * yrad)
                local p2 = pos + right * (math.cos(angle2) * xrad) + up * (math.sin(angle2) * yrad)
                
                local s1 = p1:ToScreen()
                local s2 = p2:ToScreen()
                
                if s1.visible and s2.visible then
                    DrawThickLine(s1.x, s1.y, s2.x, s2.y, lineThickness, col.r, col.g, col.b, alpha * 0.9)
                end
            end
            
            draw.SimpleText(string.format("R:%.0f,%.0f", xrad / vizScale, yrad / vizScale), "DermaDefault", x, y + 50, Color(255, 200, 255, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            
        elseif lt == "cylinder" then
            local axisLen = ent:GetNWFloat("rtx_light_axis_len", 40) * vizScale
            local cylRadius = radius * vizScale
            
            -- Draw cylinder outline
            local up = ang:Up()
            local right = ang:Right()
            local forward = ang:Forward()
            
            local topCenter = pos + up * (axisLen / 2)
            local bottomCenter = pos - up * (axisLen / 2)
            
            -- Draw top and bottom circles (12 segments each)
            local segments = 12
            
            -- Build circle points for filling
            if fillOpacity > 0 then
                local topPoints = {}
                local bottomPoints = {}
                for i = 0, segments - 1 do
                    local angle = (i / segments) * math.pi * 2
                    local offset = right * (math.cos(angle) * cylRadius) + forward * (math.sin(angle) * cylRadius)
                    table.insert(topPoints, topCenter + offset)
                    table.insert(bottomPoints, bottomCenter + offset)
                end
                DrawFilledWorldPoly(topPoints, col.r, col.g, col.b, fillOpacity * (alpha / 255))
                DrawFilledWorldPoly(bottomPoints, col.r, col.g, col.b, fillOpacity * (alpha / 255))
            end
            
            -- Draw circles outline with thick lines
            for i = 0, segments - 1 do
                local angle1 = (i / segments) * math.pi * 2
                local angle2 = ((i + 1) / segments) * math.pi * 2
                
                local offset1 = right * (math.cos(angle1) * cylRadius) + forward * (math.sin(angle1) * cylRadius)
                local offset2 = right * (math.cos(angle2) * cylRadius) + forward * (math.sin(angle2) * cylRadius)
                
                -- Top circle
                local top1 = (topCenter + offset1):ToScreen()
                local top2 = (topCenter + offset2):ToScreen()
                if top1.visible and top2.visible then
                    DrawThickLine(top1.x, top1.y, top2.x, top2.y, lineThickness, col.r, col.g, col.b, alpha * 0.9)
                end
                
                -- Bottom circle
                local bot1 = (bottomCenter + offset1):ToScreen()
                local bot2 = (bottomCenter + offset2):ToScreen()
                if bot1.visible and bot2.visible then
                    DrawThickLine(bot1.x, bot1.y, bot2.x, bot2.y, lineThickness, col.r, col.g, col.b, alpha * 0.9)
                end
                
                -- Connecting lines (draw 4 vertical lines)
                if i % 3 == 0 then
                    if top1.visible and bot1.visible then
                        DrawThickLine(top1.x, top1.y, bot1.x, bot1.y, lineThickness, col.r, col.g, col.b, alpha * 0.7)
                    end
                end
            end
            
            draw.SimpleText(string.format("L:%.0f R:%.0f", axisLen / vizScale, cylRadius / vizScale), "DermaDefault", x, y + 50, Color(200, 150, 255, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            
        elseif lt == "sphere" then
            -- Draw a circle representing the sphere radius
            -- Billboard effect: always face the camera
            local sphereRadius = radius * vizScale
            
            -- Calculate billboard vectors (perpendicular to camera view direction)
            local toCamera = (eyePos - pos):GetNormalized()
            local worldUp = Vector(0, 0, 1)
            
            -- If looking straight up/down, use a different reference vector
            if math.abs(toCamera.z) > 0.99 then
                worldUp = Vector(1, 0, 0)
            end
            
            -- Create perpendicular vectors for the circle plane
            local right = toCamera:Cross(worldUp):GetNormalized()
            local up = right:Cross(toCamera):GetNormalized()
            
            local segments = 20
            
            -- Build circle points for fill
            if fillOpacity > 0 then
                local circlePoints = {}
                for i = 0, segments - 1 do
                    local angle = (i / segments) * math.pi * 2
                    local p = pos + right * (math.cos(angle) * sphereRadius) + up * (math.sin(angle) * sphereRadius)
                    table.insert(circlePoints, p)
                end
                DrawFilledWorldPoly(circlePoints, col.r, col.g, col.b, fillOpacity * (alpha / 255) * 0.5)
            end
            
            -- Draw circle outline with thick lines
            for i = 0, segments - 1 do
                local angle1 = (i / segments) * math.pi * 2
                local angle2 = ((i + 1) / segments) * math.pi * 2
                
                local p1 = pos + right * (math.cos(angle1) * sphereRadius) + up * (math.sin(angle1) * sphereRadius)
                local p2 = pos + right * (math.cos(angle2) * sphereRadius) + up * (math.sin(angle2) * sphereRadius)
                
                local s1 = p1:ToScreen()
                local s2 = p2:ToScreen()
                
                if s1.visible and s2.visible then
                    DrawThickLine(s1.x, s1.y, s2.x, s2.y, lineThickness, col.r, col.g, col.b, alpha * 0.7)
                end
            end
            
        elseif lt == "distant" then
            local angDiam = ent:GetNWFloat("rtx_light_distant_angle", 0.5)
            draw.SimpleText(string.format("∅%.2f°", angDiam), "DermaDefault", x, y + 50, Color(255, 255, 150, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
end)

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
        end
        -- Note: If mixer.ValueChanged doesn't exist, we rely on the other control callbacks
        -- The entity already has the correct initial values, so we don't force an update

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
        -- Don't call applyRealtime() here - entity already has correct values
        -- Callbacks will handle updates when user changes controls
        typeCombo.OnSelect = function(panel, index, value, data)
            -- data contains the actual light type string (sphere, rect, disk, etc.)
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
    if RemixLight and RemixLight.DestroyLightsForEntity then
        RemixLight.DestroyLightsForEntity(self:EntIndex())
    end
end

-- Console commands for visualization control
concommand.Add("remix_rt_light_vis_toggle", function()
    local newVal = not cv_visualize:GetBool()
    cv_visualize:SetBool(newVal)
    print("[Remix RT Light] Visualization " .. (newVal and "enabled" or "disabled"))
end, nil, "Toggle RTX light visualization overlay")

concommand.Add("remix_rt_light_vis_range", function(ply, cmd, args)
    if #args < 1 then
        print("[Remix RT Light] Current range: " .. cv_vis_range:GetFloat())
        print("Usage: remix_rt_light_vis_range <distance>")
        return
    end
    local range = tonumber(args[1])
    if range then
        cv_vis_range:SetFloat(range)
        print("[Remix RT Light] Visualization range set to " .. range)
    end
end, nil, "Set visualization range for RTX lights")

concommand.Add("remix_rt_light_vis_scale", function(ply, cmd, args)
    if #args < 1 then
        print("[Remix RT Light] Current scale: " .. cv_vis_scale:GetFloat())
        print("Usage: remix_rt_light_vis_scale <scale> (0.1 to 10.0)")
        return
    end
    local scale = tonumber(args[1])
    if scale then
        scale = math.Clamp(scale, 0.1, 10.0)
        cv_vis_scale:SetFloat(scale)
        print("[Remix RT Light] Visualization scale set to " .. scale)
    end
end, nil, "Set visualization scale for RTX lights (0.1 to 10.0)")

concommand.Add("remix_rt_light_vis_fill", function(ply, cmd, args)
    if #args < 1 then
        print("[Remix RT Light] Current fill opacity: " .. cv_vis_fill_opacity:GetInt())
        print("Usage: remix_rt_light_vis_fill <opacity> (0 to 255)")
        print("Recommended: 30-50 for subtle fill, 0 to disable")
        return
    end
    local opacity = tonumber(args[1])
    if opacity then
        opacity = math.Clamp(math.floor(opacity), 0, 255)
        cv_vis_fill_opacity:SetInt(opacity)
        print("[Remix RT Light] Fill opacity set to " .. opacity)
    end
end, nil, "Set fill opacity for RTX light visualization (0-255)")

-- Add to tool menu if available
hook.Add("PopulateToolMenu", "RemixRTLight_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "RTX Remix", "RTX_Remix_Light_Viz", "Light Visualization", "", "", function(panel)
        panel:ClearControls()
        
        panel:Help("HUD-based visualization for RTX Remix lights")
        panel:Help("Works with fixed-function rendering")
        
        panel:CheckBox("Enable Visualization", "remix_rt_light_visualize")
        panel:CheckBox("Always Show (360°)", "remix_rt_light_visualize_always")
        panel:NumSlider("Visualization Range", "remix_rt_light_visualize_range", 512, 8192, 0)
        panel:NumSlider("Visualization Scale", "remix_rt_light_visualize_scale", 0.1, 10.0, 2)
        panel:NumSlider("Fill Opacity", "remix_rt_light_visualize_fill_opacity", 0, 255, 0)
        
        panel:Help("")
        panel:Help("Adjust scale to match Remix's actual light rendering")
        panel:Help("Fill opacity: 30-50 recommended, 0 to disable fill")
        panel:Help("(Text size is not affected, only spatial elements)")
        
        panel:Help("")
        panel:Help("Color Legend:")
        panel:Help("🟡 Sphere | 🔵 Rect | 🟣 Disk")
        panel:Help("🟣 Cylinder | 🟡 Distant | 🟢 Dome")
        
        local btnReset = panel:Button("Reset to Defaults")
        btnReset.DoClick = function()
            RunConsoleCommand("remix_rt_light_visualize", "1")
            RunConsoleCommand("remix_rt_light_visualize_range", "2048")
            RunConsoleCommand("remix_rt_light_visualize_always", "0")
            RunConsoleCommand("remix_rt_light_visualize_scale", "1.0")
            RunConsoleCommand("remix_rt_light_visualize_fill_opacity", "30")
        end
    end)
end)


