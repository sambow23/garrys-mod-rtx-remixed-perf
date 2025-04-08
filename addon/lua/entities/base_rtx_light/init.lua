AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

cleanup.Register("rtx_lights")

if SERVER then
    util.AddNetworkString("RTXLight_UpdateProperty")
end

function ENT:Initialize()
    self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    
    self:SetMaterial("models/debug/debugwhite")
    self:DrawShadow(false)
    self:SetNoDraw(true)
    
    -- Set properties from initial values if they exist
    if self.InitialProperties then
        self:SetLightType(self.InitialProperties.lightType or 0)
        self:SetLightBrightness(self.InitialProperties.brightness)
        self:SetLightSize(self.InitialProperties.size)
        self:SetLightR(self.InitialProperties.r)
        self:SetLightG(self.InitialProperties.g)
        self:SetLightB(self.InitialProperties.b)
        
        -- Type-specific properties
        self:SetRectWidth(self.InitialProperties.rectWidth or 100)
        self:SetRectHeight(self.InitialProperties.rectHeight or 100)
        self:SetAngularDiameter(self.InitialProperties.angularDiameter or 0.5)

        -- Light shaping properties
        self:SetShapingEnabled(self.InitialProperties.shapingEnabled or true)
        -- FIX: Fixed the reference from 'this' to 'self' and added parentheses for proper evaluation
        self:SetConeAngle(self.InitialProperties.coneAngle or (self:GetLightType() ~= 0 and 120 or 180))
        self:SetConeSoftness(self.InitialProperties.coneSoftness or 0.2)
    else
        -- Default values
        self:SetLightType(0) -- Sphere by default
        self:SetLightBrightness(100)
        self:SetLightSize(200)
        self:SetLightR(255)
        self:SetLightG(255)
        self:SetLightB(255)
        self:SetRectWidth(100)
        self:SetRectHeight(100)
        self:SetAngularDiameter(0.5)

        -- Default light shaping
        self:SetShapingEnabled(true)
        self:SetConeAngle(120)
        self:SetConeSoftness(0.2)
    end
    
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end
end

-- Handle property updates from clients
if SERVER then
    net.Receive("RTXLight_UpdateProperty", function(len, ply)
        local ent = net.ReadEntity()
        if not IsValid(ent) or ent:GetClass() ~= "base_rtx_light" then return end
        if not hook.Run("CanTool", ply, { Entity = ent }, "rtx_light") then return end
        
        local property = net.ReadString()
        
        if property == "brightness" then
            ent:SetLightBrightness(net.ReadFloat())
        elseif property == "size" then
            ent:SetLightSize(net.ReadFloat())
        elseif property == "color" then
            ent:SetLightR(net.ReadUInt(8))
            ent:SetLightG(net.ReadUInt(8))
            ent:SetLightB(net.ReadUInt(8))
        elseif property == "lightType" then
            ent:SetLightType(net.ReadUInt(8))
        elseif property == "rectWidth" then
            ent:SetRectWidth(net.ReadFloat())
        elseif property == "rectHeight" then
            ent:SetRectHeight(net.ReadFloat())
        elseif property == "angularDiameter" then
            ent:SetAngularDiameter(net.ReadFloat())
        elseif property == "shapingEnabled" then
            ent:SetShapingEnabled(net.ReadBool())
        elseif property == "coneAngle" then
            ent:SetConeAngle(net.ReadFloat())
        elseif property == "coneSoftness" then
            ent:SetConeSoftness(net.ReadFloat())
        end
    end)
end

function ENT:PreEntityRemove()  -- Additional cleanup hook
    self:OnRemove()
end