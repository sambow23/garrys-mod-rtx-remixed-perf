include("shared.lua")

local activeLights = {}
local lastUpdate = 0
local UPDATE_INTERVAL = 0.016 -- ~60fps
local activeRTXLights = {}

ENT.rtxEntityID = nil

local function IsValidLightHandle(handle)
    return handle ~= nil 
        and type(handle) == "userdata" 
        and pcall(function() return handle ~= NULL end)  -- Safe check for nil/NULL
end

local function ValidateEntityExists(entityID)
    local ent = Entity(entityID)
    return IsValid(ent) and ent:GetClass() == "base_rtx_light"
end

function ENT:Initialize()
    self:SetNoDraw(true)
    self:DrawShadow(false)
    
    -- Register this light in our tracking table
    activeRTXLights[self:EntIndex()] = self
    
    -- Delay light creation to ensure networked values are received
    timer.Simple(0.1, function()
        if IsValid(self) then
            self:CreateRTXLight()
        end
    end)
end

function ENT:CreateRTXLight()
    -- Ensure we have a unique entity ID
    if not self.rtxEntityID then
        self.rtxEntityID = self:EntIndex() + (CurTime() * 1000000) -- Create unique ID
    end

    -- Clean up any existing light for this entity
    if IsValidLightHandle(self.rtxLightHandle) then
        pcall(function() 
            DestroyRTXLight(self.rtxLightHandle)
        end)
        self.rtxLightHandle = nil
    end

    -- Get shared properties
    local pos = self:GetPos()
    local brightness = self:GetLightBrightness()
    local r = self:GetLightR()
    local g = self:GetLightG()
    local b = self:GetLightB()
    local lightType = self:GetLightType()

    -- Get light shaping properties
    local shapingEnabled = self:GetShapingEnabled()
    local coneAngle = self:GetConeAngle()
    local coneSoftness = self:GetConeSoftness()

    -- Create the appropriate light type
    local success, handle = false, nil

    if lightType == 0 then -- Sphere Light
        local size = self:GetLightSize()
        success, handle = pcall(function()
            return CreateRTXSphereLight(
                pos.x, pos.y, pos.z,
                size,
                brightness,
                r, g, b,
                self.rtxEntityID,
                shapingEnabled,      -- Enable light shaping
                0, 0, 1,             -- Default direction
                coneAngle,
                coneSoftness
            )
        end)
    elseif lightType == 1 then -- Rect Light
        local width = self:GetRectWidth()
        local height = self:GetRectHeight()
        
        -- Get forward vector for direction
        local ang = self:GetAngles()
        local dir = ang:Forward()
        
        success, handle = pcall(function()
            return CreateRTXRectLight(
                pos.x, pos.y, pos.z,
                width, height,
                brightness,
                r, g, b,
                self.rtxEntityID,
                dir.x, dir.y, dir.z,  -- Use entity's forward vector
                1, 0, 0,              -- Default X axis
                0, 1, 0,              -- Default Y axis
                shapingEnabled,
                coneAngle,
                coneSoftness
            )
        end)
    elseif lightType == 2 then -- Disk Light
        local size = self:GetLightSize()
        
        -- Get forward vector for direction
        local ang = self:GetAngles()
        local dir = ang:Forward()
        
        success, handle = pcall(function()
            return CreateRTXDiskLight(
                pos.x, pos.y, pos.z,
                size, size,            -- Using same value for both radii
                brightness,
                r, g, b,
                self.rtxEntityID,
                dir.x, dir.y, dir.z,   -- Use entity's forward vector
                1, 0, 0,               -- Default X axis
                0, 1, 0,               -- Default Y axis
                shapingEnabled,
                coneAngle,
                coneSoftness
            )
        end)
    elseif lightType == 3 then -- Distant Light
        local angularDiameter = self:GetAngularDiameter()
        local ang = self:GetAngles()
        local dir = ang:Forward()
        
        success, handle = pcall(function()
            return CreateRTXDistantLight(
                dir.x, dir.y, dir.z,  -- Use entity's forward vector
                angularDiameter,
                brightness,
                r, g, b,
                self.rtxEntityID
            )
        end)
    end

    if success and IsValidLightHandle(handle) then
        self.rtxLightHandle = handle
        self.lastUpdatePos = pos
        self.lastUpdateTime = CurTime()
    else
        print("[RTX Light] Failed to create light: ", tostring(handle), "\n")
    end
end

function ENT:OnNetworkVarChanged(name, old, new)
    if IsValid(self) and self.rtxLightHandle then
        self:CreateRTXLight() -- Recreate light with new properties
    end
end

function ENT:Think()
    if not self.nextUpdate then self.nextUpdate = 0 end
    if CurTime() < self.nextUpdate then return end
    
    -- Only update if we have a valid light
    if self.rtxLightHandle then
        -- Use our custom validation instead of IsValid
        if not IsValidLightHandle(self.rtxLightHandle) then
            self.rtxLightHandle = nil
            self:CreateRTXLight()
            return
        end

        local pos = self:GetPos()
        
        -- Check if we actually need to update
        if not self.lastUpdatePos or pos:DistToSqr(self.lastUpdatePos) > 1 then
            local brightness = self:GetLightBrightness()
            local r = self:GetLightR()
            local g = self:GetLightG()
            local b = self:GetLightB()
            local lightType = self:GetLightType()
            
            -- Get shaping properties
            local shapingEnabled = self:GetShapingEnabled()
            local coneAngle = self:GetConeAngle()
            local coneSoftness = self:GetConeSoftness()

            -- Protected call for update based on light type
            local success, err = false, nil

            if lightType == 0 then -- Sphere Light
                local size = self:GetLightSize()
                success, err = pcall(function()
                    local updateSuccess, newHandle = UpdateRTXLight(
                        self.rtxLightHandle,
                        0, -- Light type (0 = sphere)
                        pos.x, pos.y, pos.z,
                        size,
                        brightness,
                        r, g, b,
                        shapingEnabled,
                        0, 0, 1, -- Default direction vector
                        coneAngle,
                        coneSoftness
                    )

                    if updateSuccess then
                        -- Update handle if it changed after recreation
                        if newHandle and IsValidLightHandle(newHandle) and newHandle ~= self.rtxLightHandle then
                            self.rtxLightHandle = newHandle
                        end
                        self.lastUpdatePos = pos
                        self.lastUpdateTime = CurTime()
                    else
                        -- If update failed, try to recreate light
                        self:CreateRTXLight()
                    end
                end)
            elseif lightType == 1 then -- Rect Light
                local width = self:GetRectWidth()
                local height = self:GetRectHeight()
                
                -- Get forward vector for direction
                local ang = self:GetAngles()
                local dir = ang:Forward()
                
                success, err = pcall(function()
                    local updateSuccess, newHandle = UpdateRTXLight(
                        self.rtxLightHandle,
                        1, -- Light type (1 = rect)
                        pos.x, pos.y, pos.z,
                        width, height,
                        brightness,
                        r, g, b,
                        dir.x, dir.y, dir.z, -- Direction
                        shapingEnabled,
                        coneAngle,
                        coneSoftness
                    )

                    if updateSuccess then
                        if newHandle and IsValidLightHandle(newHandle) and newHandle ~= self.rtxLightHandle then
                            self.rtxLightHandle = newHandle
                        end
                        self.lastUpdatePos = pos
                        self.lastUpdateTime = CurTime()
                    else
                        self:CreateRTXLight()
                    end
                end)
            elseif lightType == 2 then -- Disk Light
                local size = self:GetLightSize()
                
                -- Get forward vector for direction
                local ang = self:GetAngles()
                local dir = ang:Forward()
                
                success, err = pcall(function()
                    local updateSuccess, newHandle = UpdateRTXLight(
                        self.rtxLightHandle,
                        2, -- Light type (2 = disk)
                        pos.x, pos.y, pos.z,
                        size, size, -- Using same value for both radii
                        brightness,
                        r, g, b,
                        dir.x, dir.y, dir.z, -- Direction
                        shapingEnabled,
                        coneAngle,
                        coneSoftness
                    )

                    if updateSuccess then
                        if newHandle and IsValidLightHandle(newHandle) and newHandle ~= self.rtxLightHandle then
                            self.rtxLightHandle = newHandle
                        end
                        self.lastUpdatePos = pos
                        self.lastUpdateTime = CurTime()
                    else
                        self:CreateRTXLight()
                    end
                end)
            elseif lightType == 3 then -- Distant Light
                local direction = self:GetAngles():Forward()
                local angularDiameter = self:GetAngularDiameter()
                success, err = pcall(function()
                    local updateSuccess, newHandle = UpdateRTXLight(
                        self.rtxLightHandle,
                        3, -- Light type (3 = distant)
                        direction.x, direction.y, direction.z,
                        angularDiameter,
                        brightness,
                        r, g, b
                    )

                    if updateSuccess then
                        if newHandle and IsValidLightHandle(newHandle) and newHandle ~= self.rtxLightHandle then
                            self.rtxLightHandle = newHandle
                        end
                        self.lastUpdatePos = pos
                        self.lastUpdateTime = CurTime()
                    else
                        self:CreateRTXLight()
                    end
                end)
            end

            if not success then
                print("[RTX Light] Update failed: ", err)
                self.rtxLightHandle = nil
                self:CreateRTXLight()
            end
        end
    else
        -- Try to recreate light if it's missing
        self:CreateRTXLight()
    end
    
    self.nextUpdate = CurTime() + UPDATE_INTERVAL
end

function ENT:OnRemove()
    -- Remove from tracking
    activeRTXLights[self:EntIndex()] = nil

    if self.rtxLightHandle then
        pcall(function()
            DestroyRTXLight(self.rtxLightHandle)
        end)
        self.rtxLightHandle = nil
    end
end

-- Add a hook to handle map cleanup
hook.Add("PreCleanupMap", "RTXLight_PreCleanupMap", function()
    for entIndex, ent in pairs(activeRTXLights) do
        if IsValid(ent) and ent.rtxLightHandle then
            pcall(function()
                DestroyRTXLight(ent.rtxLightHandle)
            end)
            ent.rtxLightHandle = nil
        end
    end
    table.Empty(activeRTXLights)
end)

net.Receive("RTXLight_Cleanup", function()
    local ent = net.ReadEntity()
    if IsValid(ent) then
        -- Remove from tracking table
        activeLights[ent:EntIndex()] = nil
        
        -- Cleanup RTX light
        if ent.rtxLightHandle then
            pcall(function()
                DestroyRTXLight(ent.rtxLightHandle)
            end)
            ent.rtxLightHandle = nil
        end
    end
end)

-- Simple property menu
function ENT:OpenPropertyMenu()
    if IsValid(self.PropertyPanel) then
        self.PropertyPanel:Remove()
    end

    local frame = vgui.Create("DFrame")
    frame:SetSize(300, 650)  -- Made taller to accommodate new controls
    frame:SetTitle("RTX Light Properties")
    frame:MakePopup()
    frame:Center()
    
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    
    -- Light Type Selector
    local lightTypeLabel = scroll:Add("DLabel")
    lightTypeLabel:Dock(TOP)
    lightTypeLabel:SetText("Light Type")
    lightTypeLabel:SetDark(true)
    lightTypeLabel:DockMargin(5, 5, 5, 0)
    
    local lightTypeCombo = scroll:Add("DComboBox")
    lightTypeCombo:Dock(TOP)
    lightTypeCombo:DockMargin(5, 0, 5, 10)
    lightTypeCombo:AddChoice("Sphere Light", 0)
    lightTypeCombo:AddChoice("Rectangle Light", 1)
    lightTypeCombo:AddChoice("Disk Light", 2)
    lightTypeCombo:AddChoice("Distant Light", 3)
    lightTypeCombo:ChooseOptionID(self:GetLightType() + 1)
    
    -- Common properties
    local brightnessSlider = scroll:Add("DNumSlider")
    brightnessSlider:Dock(TOP)
    brightnessSlider:SetText("Brightness")
    brightnessSlider:SetMin(1)
    brightnessSlider:SetMax(1000)
    brightnessSlider:SetDecimals(0)
    brightnessSlider:SetValue(self:GetLightBrightness())
    brightnessSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("brightness")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    -- Light type specific controls
    local lightType = self:GetLightType()
    
    -- Sphere Light panel
    local spherePanel = vgui.Create("DPanel", scroll)
    spherePanel:Dock(TOP)
    spherePanel:SetTall(50)
    spherePanel:DockMargin(5, 5, 5, 5)
    spherePanel:SetPaintBackground(false)
    spherePanel:SetVisible(lightType == 0)
    
    local sizeSlider = spherePanel:Add("DNumSlider")
    sizeSlider:Dock(TOP)
    sizeSlider:SetText("Size")
    sizeSlider:SetMin(1)
    sizeSlider:SetMax(1000)
    sizeSlider:SetDecimals(0)
    sizeSlider:SetValue(self:GetLightSize())
    sizeSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("size")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    -- Rectangle Light panel
    local rectPanel = vgui.Create("DPanel", scroll)
    rectPanel:Dock(TOP)
    rectPanel:SetTall(100)
    rectPanel:DockMargin(5, 5, 5, 5)
    rectPanel:SetPaintBackground(false)
    rectPanel:SetVisible(lightType == 1)
    
    local widthSlider = rectPanel:Add("DNumSlider")
    widthSlider:Dock(TOP)
    widthSlider:SetText("Width")
    widthSlider:SetMin(1)
    widthSlider:SetMax(1000)
    widthSlider:SetDecimals(0)
    widthSlider:SetValue(self:GetRectWidth())
    widthSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("rectWidth")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    local heightSlider = rectPanel:Add("DNumSlider")
    heightSlider:Dock(TOP)
    heightSlider:SetText("Height")
    heightSlider:SetMin(1)
    heightSlider:SetMax(1000)
    heightSlider:SetDecimals(0)
    heightSlider:SetValue(self:GetRectHeight())
    heightSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("rectHeight")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    -- Disk Light panel
    local diskPanel = vgui.Create("DPanel", scroll)
    diskPanel:Dock(TOP)
    diskPanel:SetTall(50)
    diskPanel:DockMargin(5, 5, 5, 5)
    diskPanel:SetPaintBackground(false)
    diskPanel:SetVisible(lightType == 2)
    
    local diskSizeSlider = diskPanel:Add("DNumSlider")
    diskSizeSlider:Dock(TOP)
    diskSizeSlider:SetText("Radius")
    diskSizeSlider:SetMin(1)
    diskSizeSlider:SetMax(1000)
    diskSizeSlider:SetDecimals(0)
    diskSizeSlider:SetValue(self:GetLightSize())
    diskSizeSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("size")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    -- Distant Light panel
    local distantPanel = vgui.Create("DPanel", scroll)
    distantPanel:Dock(TOP)
    distantPanel:SetTall(50)
    distantPanel:DockMargin(5, 5, 5, 5)
    distantPanel:SetPaintBackground(false)
    distantPanel:SetVisible(lightType == 3)
    
    local angularSlider = distantPanel:Add("DNumSlider")
    angularSlider:Dock(TOP)
    angularSlider:SetText("Angular Diameter")
    angularSlider:SetMin(0.1)
    angularSlider:SetMax(10)
    angularSlider:SetDecimals(1)
    angularSlider:SetValue(self:GetAngularDiameter())
    angularSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("angularDiameter")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    -- Light shaping controls - new section
    local shapingLabel = scroll:Add("DLabel")
    shapingLabel:Dock(TOP)
    shapingLabel:SetText("Light Shaping")
    shapingLabel:SetDark(true)
    shapingLabel:DockMargin(5, 15, 5, 0)
    
    local shapingPanel = vgui.Create("DPanel", scroll)
    shapingPanel:Dock(TOP)
    shapingPanel:SetTall(120)
    shapingPanel:DockMargin(5, 5, 5, 5)
    shapingPanel:SetPaintBackground(false)
    
    local shapingCheckbox = shapingPanel:Add("DCheckBoxLabel")
    shapingCheckbox:Dock(TOP)
    shapingCheckbox:SetText("Enable Light Shaping")
    shapingCheckbox:SetValue(self:GetShapingEnabled())
    shapingCheckbox:DockMargin(0, 5, 0, 10)
    shapingCheckbox.OnChange = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("shapingEnabled")
            net.WriteBool(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    local coneAngleSlider = shapingPanel:Add("DNumSlider")
    coneAngleSlider:Dock(TOP)
    coneAngleSlider:SetText("Cone Angle")
    coneAngleSlider:SetMin(1)
    coneAngleSlider:SetMax(180)
    coneAngleSlider:SetDecimals(0)
    coneAngleSlider:SetValue(self:GetConeAngle())
    coneAngleSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("coneAngle")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    local coneSoftnessSlider = shapingPanel:Add("DNumSlider")
    coneSoftnessSlider:Dock(TOP)
    coneSoftnessSlider:SetText("Cone Softness")
    coneSoftnessSlider:SetMin(0)
    coneSoftnessSlider:SetMax(1)
    coneSoftnessSlider:SetDecimals(2)
    coneSoftnessSlider:SetValue(self:GetConeSoftness())
    coneSoftnessSlider.OnValueChanged = function(_, value)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("coneSoftness")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    -- Color Mixer
    local colorLabel = scroll:Add("DLabel")
    colorLabel:Dock(TOP)
    colorLabel:SetText("Light Color")
    colorLabel:SetDark(true)
    colorLabel:DockMargin(5, 15, 5, 0)
    
    local colorMixer = scroll:Add("DColorMixer")
    colorMixer:Dock(TOP)
    colorMixer:SetTall(200)
    colorMixer:SetPalette(false)
    colorMixer:SetAlphaBar(false)
    colorMixer:SetColor(Color(self:GetLightR(), self:GetLightG(), self:GetLightB()))
    colorMixer.ValueChanged = function(_, color)
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("color")
            net.WriteUInt(color.r, 8)
            net.WriteUInt(color.g, 8)
            net.WriteUInt(color.b, 8)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    -- Light type visibility control
    lightTypeCombo.OnSelect = function(_, _, _, data)
        spherePanel:SetVisible(data == 0)
        rectPanel:SetVisible(data == 1)
        diskPanel:SetVisible(data == 2)
        distantPanel:SetVisible(data == 3)
        
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("lightType")
            net.WriteUInt(data, 8)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()
            self.lastUpdatePos = nil
        end
    end
    
    self.PropertyPanel = frame
end

properties.Add("rtx_light_properties", {
    MenuLabel = "Edit RTX Light",
    Order = 1,
    MenuIcon = "icon16/lightbulb.png",
    
    Filter = function(self, ent, ply)
        return IsValid(ent) and ent:GetClass() == "base_rtx_light"
    end,
    
    Action = function(self, ent)
        ent:OpenPropertyMenu()
    end
})

hook.Add("PreRender", "RTXLightFrameSync", function()
    RTXBeginFrame()
    
    -- Update all active lights
    for entIndex, light in pairs(activeLights) do
        if IsValid(light) then
            light:Think()
        else
            activeLights[entIndex] = nil
        end
    end
end)

hook.Add("PostRender", "RTXLightFrameSync", function()
    RTXEndFrame()
end)

hook.Add("ShutDown", "CleanupRTXLights", function()
    for _, ent in pairs(activeLights) do
        if IsValid(ent) then
            ent:OnRemove()
        end
    end
    table.Empty(activeLights)
end)

hook.Add("PreCleanupMap", "CleanupRTXLights", function()
    for _, ent in pairs(activeLights) do
        if IsValid(ent) then
            ent:OnRemove()
        end
    end
    table.Empty(activeLights)
end)

timer.Simple(0, function()
    if RegisterRTXLightEntityValidator then
        RegisterRTXLightEntityValidator(ValidateEntityExists)
    end
end)

timer.Create("RTXLightStateValidation", 5, 0, function()
    if DrawRTXLights then  -- Check if module is loaded
        DrawRTXLights()  -- This will trigger ValidateState
    end
end)

hook.Add("ShutDown", "RTXLight_Cleanup", function()
    for entIndex, ent in pairs(activeRTXLights) do
        if IsValid(ent) and ent.rtxLightHandle then
            pcall(function()
                DestroyRTXLight(ent.rtxLightHandle)
            end)
            ent.rtxLightHandle = nil
        end
    end
    table.Empty(activeRTXLights)
end)

-- Add validation timer with error handling
timer.Create("RTXLightValidation", 5, 0, function()
    pcall(function()
        -- Clean up any invalid entries in tracking table
        for entIndex, ent in pairs(activeRTXLights) do
            if not IsValid(ent) or not ent.rtxLightHandle then
                activeRTXLights[entIndex] = nil
            end
        end

        -- Check for lights that need recreation
        for _, ent in ipairs(ents.FindByClass("base_rtx_light")) do
            if IsValid(ent) then
                if not ent.rtxLightHandle and ent.CreateRTXLight then
                    ent:CreateRTXLight()
                end
            end
        end
    end)
end)

-- Add entity removal hook for more reliable cleanup
hook.Add("EntityRemoved", "RTXLight_EntityCleanup", function(ent)
    if ent:GetClass() == "base_rtx_light" then
        -- Ensure cleanup happens even if OnRemove doesn't fire
        if ent.rtxLightHandle then
            pcall(function()
                DestroyRTXLight(ent.rtxLightHandle)
            end)
            ent.rtxLightHandle = nil
        end
        activeRTXLights[ent:EntIndex()] = nil
    end
end)