include("shared.lua")

local activeRTXLights = {}

ENT.rtxEntityID = nil
ENT.rtxLightHandle = nil
ENT.lastPos = nil

function ENT:Initialize()
    self:SetNoDraw(true)
    self:DrawShadow(false)
    
    -- Generate stable entity ID
    self.rtxEntityID = self:EntIndex()
    self:CreateRTXLight()
end

function ENT:CreateRTXLight()
    -- Clean up existing light if it exists
    if self.rtxLightHandle then
        DestroyRTXLight(self.rtxLightHandle)
        self.rtxLightHandle = nil
    end

    local pos = self:GetPos()
    local handle = CreateRTXLight(
        pos.x, 
        pos.y, 
        pos.z,
        self:GetLightSize(),
        self:GetLightBrightness(),
        self:GetLightR(),
        self:GetLightG(),
        self:GetLightB(),
        self.rtxEntityID
    )

    if handle then
        self.rtxLightHandle = handle
        self.lastPos = pos
        activeRTXLights[self:EntIndex()] = self
    end
end

function ENT:UpdateLight()
    if not self.rtxLightHandle then return end

    local pos = self:GetPos()
    if self.lastPos and pos:DistToSqr(self.lastPos) < 0.01 then return end

    -- Destroy and recreate the light with new properties
    self:CreateRTXLight()
end

function ENT:Think()
    if IsValid(self) then
        self:UpdateLight()
    end
end

function ENT:OnRemove()
    if self.rtxLightHandle then
        DestroyRTXLight(self.rtxLightHandle)
        self.rtxLightHandle = nil
    end
    activeRTXLights[self:EntIndex()] = nil
end

-- Undo handler
hook.Add("EntityRemoved", "RTXLight_Cleanup", function(ent)
    if IsValid(ent) and ent:GetClass() == "base_rtx_light" then
        if ent.rtxLightHandle then
            DestroyRTXLight(ent.rtxLightHandle)
            ent.rtxLightHandle = nil
        end
        activeRTXLights[ent:EntIndex()] = nil
    end
end)
hook.Add("ShutDown", "RTXLight_Emergency", function()
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
        activeRTXLights[ent:EntIndex()] = nil
        
        if ent.rtxLightHandle then
            pcall(function()
                DestroyRTXLight(ent.rtxLightHandle)
            end)
            ent.rtxLightHandle = nil
        end
    end
end)

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
        net.Start("RTXLight_UpdateProperty")
            net.WriteEntity(self)
            net.WriteString("brightness")
            net.WriteFloat(value)
        net.SendToServer()
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:UpdateLight()
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
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:UpdateLight()
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
        
        if IsValid(self) and IsValidLightHandle(self.rtxLightHandle) then
            self:UpdateLight()
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