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
        self:SetLightBrightness(self.InitialProperties.brightness)
        self:SetLightSize(self.InitialProperties.size)
        self:SetLightR(self.InitialProperties.r)
        self:SetLightG(self.InitialProperties.g)
        self:SetLightB(self.InitialProperties.b)
    else
        -- Default values
        self:SetLightBrightness(100)
        self:SetLightSize(200)
        self:SetLightR(255)
        self:SetLightG(255)
        self:SetLightB(255)
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
        end
    end)
end

function ENT:PreEntityRemove()  -- Additional cleanup hook
    self:OnRemove()
end