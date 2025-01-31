include("shared.lua")

local activeLights = {}
local lastUpdate = 0
local UPDATE_INTERVAL = 0.016 -- ~60fps
local activeRTXLights = {}

ENT.rtxEntityID = nil

local function HSVToRGB(h, s, v)
    local h_sector = h / 60
    local h_int = math.floor(h_sector)
    local f = h_sector - h_int
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))

    if h_int == 0 then return v * 255, t * 255, p * 255
    elseif h_int == 1 then return q * 255, v * 255, p * 255
    elseif h_int == 2 then return p * 255, v * 255, t * 255
    elseif h_int == 3 then return p * 255, q * 255, v * 255
    elseif h_int == 4 then return t * 255, p * 255, v * 255
    else return v * 255, p * 255, q * 255
    end
end

local function IsValidLightHandle(handle)
    return handle ~= nil 
        and type(handle) == "userdata" 
        and pcall(function() return handle ~= NULL end)  -- Safe check for nil/NULL
end

function ValidateEntityExists(entityID)
    -- Convert back to entity index from the generated ID
    local entIndex = entityID % 1000000  -- Extract the original entity index
    local ent = Entity(entIndex)
    
    -- Debug output
    print(string.format("[RTX Light Validator] Validating - Generated ID: %d, Entity Index: %d", 
        entityID, 
        entIndex))
    
    -- Basic validity check
    if not IsValid(ent) then 
        print(string.format("[RTX Light Validator] Entity %d is not valid", entIndex))
        return false 
    end
    
    if ent:GetClass() ~= "base_rtx_light" then 
        print(string.format("[RTX Light Validator] Entity %d is not a light (%s)", 
            entIndex, 
            ent:GetClass()))
        return false 
    end
    
    -- Verify the entity matches our generated ID
    if ent.rtxEntityID and ent.rtxEntityID ~= entityID then
        print(string.format("[RTX Light Validator] Entity ID mismatch - Expected: %d, Got: %d", 
            entityID, 
            ent.rtxEntityID))
        return false
    end
    
    return true
end

-- Register the validator with a delay to ensure module is loaded
timer.Simple(1, function()
    if RegisterRTXLightEntityValidator then
        RegisterRTXLightEntityValidator(ValidateEntityExists)
        print("[RTX Light] Registered entity validator")
    else
        print("[RTX Light] Warning: Could not register entity validator")
    end
end)

function ENT:AnimateColor()
    if not self.IsAnimating then return end
    
    self.AnimationHue = (self.AnimationHue + 1) % 360
    local r, g, b = HSVToRGB(self.AnimationHue, 1, 1)
    
    -- Update networked values
    net.Start("RTXLight_UpdateProperty")
        net.WriteEntity(self)
        net.WriteString("color")
        net.WriteUInt(r, 8)
        net.WriteUInt(g, 8)
        net.WriteUInt(b, 8)
    net.SendToServer()
    
    -- Force immediate local update
    if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
        self:Think()
        self.lastUpdatePos = nil
    end
end

function ENT:Initialize()
    self:SetNoDraw(true)
    self:DrawShadow(false)
    
    self.creationTime = CurTime()
    activeRTXLights[self:EntIndex()] = self
    
    -- Increase delay for light creation
    timer.Simple(0.25, function()
        if IsValid(self) then
            self:CreateRTXLight()
        end
    end)
    self.IsAnimating = false
    self.AnimationHue = 0
end

function ENT:CreateRTXLight()
    -- Create a more stable entity ID that persists
    if not self.rtxEntityID then
        -- Use entity index as base and add a timestamp component
        local baseIndex = self:EntIndex()
        local timeComponent = math.floor(CurTime()) % 1000
        self.rtxEntityID = (timeComponent * 1000000) + baseIndex
    end

    print(string.format("[RTX Light] Creating light for entity %d with generated ID %d", 
        self:EntIndex(), 
        self.rtxEntityID))

    -- Clean up existing light
    if self.rtxLightHandle then
        pcall(function() 
            DestroyRTXLight(self.rtxLightHandle)
        end)
        self.rtxLightHandle = nil
    end

    local pos = self:GetPos()
    local size = self:GetLightSize()
    local brightness = self:GetLightBrightness()
    local r = self:GetLightR()
    local g = self:GetLightG()
    local b = self:GetLightB()

    -- Create new light with entity ID
    local success, handle = pcall(function()
        return CreateRTXLight(
            pos.x, 
            pos.y, 
            pos.z,
            size,
            brightness,
            r,
            g,
            b,
            self.rtxEntityID
        )
    end)

    if success and IsValidLightHandle(handle) then
        self.rtxLightHandle = handle
        self.lastUpdatePos = pos
        self.lastUpdateTime = CurTime()
        
        -- Store in active lights table
        activeRTXLights[self:EntIndex()] = self
        
        print(string.format("[RTX Light] Successfully created light handle %s for entity %d (ID: %d)", 
            tostring(handle), 
            self:EntIndex(),
            self.rtxEntityID))
    else
        ErrorNoHalt(string.format("[RTX Light] Failed to create light: %s\n", tostring(handle)))
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
            local brightness = self:GetLightBrightness() / 100  -- Convert percentage to 0-1
            local size = self:GetLightSize() / 10  -- Scale down size
            local r = self:GetLightR()
            local g = self:GetLightG()
            local b = self:GetLightB()

            -- Protected call for update
            local success, err = pcall(function()
                local updateSuccess, newHandle = UpdateRTXLight(
                    self.rtxLightHandle,
                    pos.x, pos.y, pos.z,
                    size,
                    brightness,
                    r, g, b
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
    if self.AnimationTimer then
        timer.Remove("RTXLight_ColorAnim_" .. self:EntIndex())
        self.AnimationTimer = nil
    end
end

-- Add a hook to handle map cleanup
hook.Add("PreCleanupMap", "RTXLight_PreCleanup", function()
    print("[RTX Light] Pre-cleanup map, destroying all lights...")
    for entIndex, ent in pairs(activeRTXLights) do
        if IsValid(ent) and ent.rtxLightHandle then
            pcall(function()
                DestroyRTXLight(ent.rtxLightHandle)
            end)
            ent.rtxLightHandle = nil
            ent.rtxEntityID = nil  -- Clear the ID so it gets regenerated
        end
    end
    table.Empty(activeRTXLights)
end)

-- Add emergency cleanup
hook.Add("Shutdown", "RTXLight_Emergency", function()
    print("[RTX Light] Emergency cleanup on shutdown")
    for entIndex, ent in pairs(activeRTXLights) do
        if IsValid(ent) and ent.rtxLightHandle then
            pcall(function()
                DestroyRTXLight(ent.rtxLightHandle)
            end)
        end
    end
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
    frame:SetSize(300, 400)
    frame:SetTitle("RTX Light Properties")
    frame:MakePopup()
    frame:Center()
    
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    
    -- Brightness Slider
    local brightnessSlider = scroll:Add("DNumSlider")
    brightnessSlider:Dock(TOP)
    brightnessSlider:SetText("Brightness")
    brightnessSlider:SetMin(1)
    brightnessSlider:SetMax(1000)
    brightnessSlider:SetDecimals(0)
    brightnessSlider:SetValue(self:GetLightBrightness())
    brightnessSlider.OnValueChanged = function(_, value)
        -- Send to server
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("brightness")
            net.WriteFloat(value)
        net.SendToServer()
        
        -- Force immediate local update
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            local pos = self:GetPos()
            local size = self:GetLightSize() / 10
            local brightness = value / 100
            local r = self:GetLightR()
            local g = self:GetLightG()
            local b = self:GetLightB()
            
            -- Call UpdateRTXLight directly, without pcall
            self:Think()  -- Use the existing Think function's update logic
            self.lastUpdatePos = nil  -- Force an update
        end
    end
    
    -- Size Slider
    local sizeSlider = scroll:Add("DNumSlider")
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
        
        -- Force immediate local update
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()  -- Use the existing Think function's update logic
            self.lastUpdatePos = nil  -- Force an update
        end
    end
    
    -- Color Mixer
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
        
        -- Force immediate local update
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:Think()  -- Use the existing Think function's update logic
            self.lastUpdatePos = nil  -- Force an update
        end
    end

    local animateButton = scroll:Add("DButton")
    animateButton:Dock(TOP)
    animateButton:DockMargin(0, 10, 0, 0)
    animateButton:SetTall(30)
    animateButton:SetText(self.IsAnimating and "Stop Color Animation" or "Start Color Animation")
    
    local animSpeedSlider = scroll:Add("DNumSlider")
    animSpeedSlider:Dock(TOP)
    animSpeedSlider:SetText("Animation Speed")
    animSpeedSlider:SetMin(25)
    animSpeedSlider:SetMax(100)
    animSpeedSlider:SetDecimals(1)
    animSpeedSlider:SetValue(1)
    animSpeedSlider:SetEnabled(self.IsAnimating)
    
    local function UpdateAnimation()
        if self.IsAnimating then
            if not self.AnimationTimer then
                self.AnimationTimer = timer.Create("RTXLight_ColorAnim_" .. self:EntIndex(), 0.05, 0, function()
                    if IsValid(self) then
                        self:AnimateColor()
                    end
                end)
            end
        else
            if self.AnimationTimer then
                timer.Remove("RTXLight_ColorAnim_" .. self:EntIndex())
                self.AnimationTimer = nil
            end
        end
        
        animateButton:SetText(self.IsAnimating and "Stop Color Animation" or "Start Color Animation")
        animSpeedSlider:SetEnabled(self.IsAnimating)
    end
    
    animateButton.DoClick = function()
        self.IsAnimating = not self.IsAnimating
        UpdateAnimation()
    end
    
    animSpeedSlider.OnValueChanged = function(_, value)
        if self.AnimationTimer then
            timer.Adjust("RTXLight_ColorAnim_" .. self:EntIndex(), 0.1 / value, 0)
        end
    end
    
    -- Add cleanup for animation when closing the menu
    frame.OnRemove = function()
        if self.AnimationTimer then
            timer.Remove("RTXLight_ColorAnim_" .. self:EntIndex())
            self.AnimationTimer = nil
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
timer.Create("RTXLightValidation", 10, 0, function()
    if not ValidateInProgress then
        ValidateInProgress = true
        local entitiesToValidate = {}
        
        -- Collect entities first
        for entIndex, ent in pairs(activeRTXLights) do
            if IsValid(ent) then
                table.insert(entitiesToValidate, ent)
            else
                activeRTXLights[entIndex] = nil
            end
        end
        
        -- Process in batches
        local batchSize = 5
        local currentBatch = 1
        
        timer.Create("RTXLightValidationBatch", 0.1, math.ceil(#entitiesToValidate / batchSize), function()
            local start = (currentBatch - 1) * batchSize + 1
            local finish = math.min(start + batchSize - 1, #entitiesToValidate)
            
            for i = start, finish do
                local ent = entitiesToValidate[i]
                if IsValid(ent) and not ent.rtxLightHandle and ent.CreateRTXLight then
                    ent:CreateRTXLight()
                end
            end
            
            currentBatch = currentBatch + 1
            if currentBatch > math.ceil(#entitiesToValidate / batchSize) then
                ValidateInProgress = false
            end
        end)
    end
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