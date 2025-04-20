-- disabled for now, api lights have documented instability issues

-- local COOLDOWN_TIME = 0.1

-- TOOL.Category = "Lighting"
-- TOOL.Name = "Remix API Light"
-- TOOL.Command = nil
-- TOOL.ConfigName = ""

-- TOOL.ClientConVar = {
--     ["brightness"] = "100",
--     ["size"] = "200",
--     ["r"] = "255",
--     ["g"] = "255",
--     ["b"] = "255",
--     ["update_rate"] = "60",
--     ["light_type"] = "0",  -- 0 = Sphere, 1 = Rect, 2 = Disk, 3 = Distant
--     ["angular_diameter"] = "0.5", -- For distant lights
--     ["rect_width"] = "100",       -- For rect lights
--     ["rect_height"] = "100"       -- For rect lights
-- }

-- function TOOL:LeftClick(trace)
--     if CLIENT then return true end

--     -- Validate trace
--     if not trace or not trace.Hit then return false end
--     if not trace.HitPos then return false end

--     local ply = self:GetOwner()
--     if not IsValid(ply) then return false end

--     -- Add cooldown to prevent rapid spawning
--     if not self.LastSpawn then self.LastSpawn = 0 end
--     if CurTime() - self.LastSpawn < 0.5 then return false end
--     self.LastSpawn = CurTime()

--     local pos = trace.HitPos
    
--     -- Get and clamp tool settings
--     local lightType = math.Clamp(self:GetClientNumber("light_type", 0), 0, 3)
--     local brightness = math.Clamp(self:GetClientNumber("brightness", 100), 1, 1000)
--     local size = math.Clamp(self:GetClientNumber("size", 200), 1, 1000)
--     local r = math.Clamp(self:GetClientNumber("r", 255), 0, 255)
--     local g = math.Clamp(self:GetClientNumber("g", 255), 0, 255)
--     local b = math.Clamp(self:GetClientNumber("b", 255), 0, 255)
    
--     -- Type-specific properties
--     local rectWidth = math.Clamp(self:GetClientNumber("rect_width", 100), 1, 1000)
--     local rectHeight = math.Clamp(self:GetClientNumber("rect_height", 100), 1, 1000)
--     local angularDiameter = math.Clamp(self:GetClientNumber("angular_diameter", 0.5), 0.1, 10)

--     -- Create entity without effects
--     local ent = ents.Create("base_rtx_light")
--     if not IsValid(ent) then return false end

--     ent:SetPos(pos)
--     ent:SetAngles(angle_zero)
    
--     -- Set initial properties
--     ent.InitialProperties = {
--         lightType = lightType,
--         brightness = brightness,
--         size = size,
--         r = r,
--         g = g,
--         b = b,
--         rectWidth = rectWidth,
--         rectHeight = rectHeight,
--         angularDiameter = angularDiameter
--     }
    
--     ent:Spawn()
--     ent:Activate()

--     -- Create undo without network messages
--     undo.Create("RTX Light")
--         undo.AddEntity(ent)
--         undo.SetPlayer(ply)
--         undo.SetCustomUndoText("Undone RTX Light")
--     undo.Finish()

--     -- Add to cleanup
--     cleanup.Add(ply, "rtx_lights", ent)

--     return true
-- end

-- function TOOL:RightClick(trace)
--     if CLIENT then return true end
    
--     if IsValid(trace.Entity) and trace.Entity:GetClass() == "base_rtx_light" then
--         trace.Entity:Remove()
--         return true
--     end
    
--     return false
-- end

-- function TOOL:Reload(trace)
--     if not IsValid(trace.Entity) or trace.Entity:GetClass() ~= "base_rtx_light" then return false end
    
--     if CLIENT then return true end

--     local ply = self:GetOwner()
--     if not IsValid(ply) then return false end

--     ply:ConCommand("rtx_light_brightness " .. trace.Entity:GetLightBrightness())
--     ply:ConCommand("rtx_light_size " .. trace.Entity:GetLightSize())
--     ply:ConCommand("rtx_light_r " .. trace.Entity:GetLightR())
--     ply:ConCommand("rtx_light_g " .. trace.Entity:GetLightG())
--     ply:ConCommand("rtx_light_b " .. trace.Entity:GetLightB())

--     return true
-- end

-- if CLIENT then
--     language.Add("tool.rtx_light.name", "RTX Light")
--     language.Add("tool.rtx_light.desc", "Create RTX Remix API lights")
--     language.Add("tool.rtx_light.0", "Left click to create a light. Right click to remove. Reload to copy settings.")

--     function TOOL.BuildCPanel(panel)
--         -- Light type selection
--         local lightTypeCombo = panel:ComboBox("Light Type", "rtx_light_light_type")
--         lightTypeCombo:AddChoice("Sphere Light", 0)
--         lightTypeCombo:AddChoice("Rectangle Light", 1)
--         lightTypeCombo:AddChoice("Disk Light", 2) 
--         lightTypeCombo:AddChoice("Distant Light", 3)
        
--         -- Common properties
--         panel:NumSlider("Brightness", "rtx_light_brightness", 1, 1000, 0)
--         panel:ColorPicker("Light Color", "rtx_light_r", "rtx_light_g", "rtx_light_b")
        
--         -- Type-specific properties
--         local lightType = GetConVarNumber("rtx_light_light_type") or 0
        
--         -- Create panel for sphere lights
--         local spherePanel = vgui.Create("DPanel", panel)
--         spherePanel:SetSize(panel:GetWide(), 50)
--         spherePanel:Dock(TOP)
--         spherePanel:DockMargin(0, 5, 0, 5)
--         spherePanel:SetPaintBackground(false)
--         spherePanel:SetVisible(lightType == 0)
        
--         local sphereSize = spherePanel:Add("DNumSlider")
--         sphereSize:Dock(TOP)
--         sphereSize:SetText("Sphere Size")
--         sphereSize:SetMin(1)
--         sphereSize:SetMax(1000)
--         sphereSize:SetDecimals(0)
--         sphereSize:SetConVar("rtx_light_size")
        
--         -- Create panel for rectangular lights
--         local rectPanel = vgui.Create("DPanel", panel)
--         rectPanel:SetSize(panel:GetWide(), 100)
--         rectPanel:Dock(TOP)
--         rectPanel:DockMargin(0, 5, 0, 5)
--         rectPanel:SetPaintBackground(false)
--         rectPanel:SetVisible(lightType == 1)
        
--         local rectWidth = rectPanel:Add("DNumSlider")
--         rectWidth:Dock(TOP)
--         rectWidth:SetText("Width")
--         rectWidth:SetMin(1)
--         rectWidth:SetMax(1000)
--         rectWidth:SetDecimals(0)
--         rectWidth:SetConVar("rtx_light_rect_width")
        
--         local rectHeight = rectPanel:Add("DNumSlider")
--         rectHeight:Dock(TOP)
--         rectHeight:SetText("Height")
--         rectHeight:SetMin(1)
--         rectHeight:SetMax(1000)
--         rectHeight:SetDecimals(0)
--         rectHeight:SetConVar("rtx_light_rect_height")
        
--         -- Create panel for disk lights
--         local diskPanel = vgui.Create("DPanel", panel)
--         diskPanel:SetSize(panel:GetWide(), 100)
--         diskPanel:Dock(TOP)
--         diskPanel:DockMargin(0, 5, 0, 5)
--         diskPanel:SetPaintBackground(false)
--         diskPanel:SetVisible(lightType == 2)
        
--         local diskRadius = diskPanel:Add("DNumSlider")
--         diskRadius:Dock(TOP)
--         diskRadius:SetText("Radius")
--         diskRadius:SetMin(1)
--         diskRadius:SetMax(1000)
--         diskRadius:SetDecimals(0)
--         diskRadius:SetConVar("rtx_light_size")
        
--         -- Create panel for distant lights
--         local distantPanel = vgui.Create("DPanel", panel)
--         distantPanel:SetSize(panel:GetWide(), 50)
--         distantPanel:Dock(TOP)
--         distantPanel:DockMargin(0, 5, 0, 5)
--         distantPanel:SetPaintBackground(false)
--         distantPanel:SetVisible(lightType == 3)
        
--         local angularDiameter = distantPanel:Add("DNumSlider")
--         angularDiameter:Dock(TOP)
--         angularDiameter:SetText("Angular Diameter")
--         angularDiameter:SetMin(0.1)
--         angularDiameter:SetMax(10)
--         angularDiameter:SetDecimals(1)
--         angularDiameter:SetConVar("rtx_light_angular_diameter")
        
--         -- Hook up visibility changes
--         lightTypeCombo.OnSelect = function(self, index, value, data)
--             spherePanel:SetVisible(data == 0)
--             rectPanel:SetVisible(data == 1)
--             diskPanel:SetVisible(data == 2)
--             distantPanel:SetVisible(data == 3)
--         end
--     end
-- end

-- -- Disable default tool effects
-- function TOOL:DrawToolScreen() return false end
-- function TOOL:DoEffect() return false end