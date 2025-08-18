AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    print("[remix_rt_light] Initialize (server)")
    self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end

    self.LightId = nil
    self.NextUpdate = 0
    -- Default parameters; can be overridden via net message
    self:SetNWVector("rtx_light_col", Vector(15, 15, 15))
    self:SetNWFloat("rtx_light_radius", 20)
    self:SetNWFloat("rtx_light_brightness", 1)
    self:SetNWFloat("rtx_light_volumetric", 1)
    -- Shaping defaults
    self:SetNWBool("rtx_light_shape_enabled", false)
    self:SetNWFloat("rtx_light_shape_cone", 90)
    self:SetNWFloat("rtx_light_shape_softness", 0.1)
    self:SetNWFloat("rtx_light_shape_focus", 1.0)
    -- Direction expressed as yaw/pitch
    self:SetNWFloat("rtx_light_dir_yaw", 0)
    self:SetNWFloat("rtx_light_dir_pitch", -90)
    -- Rect/Disk sizes
    self:SetNWFloat("rtx_light_xsize", 40)
    self:SetNWFloat("rtx_light_ysize", 40)
    self:SetNWFloat("rtx_light_xradius", 20)
    self:SetNWFloat("rtx_light_yradius", 20)
    -- Cylinder axis length
    self:SetNWFloat("rtx_light_axis_len", 40)
    -- Distant angular diameter
    self:SetNWFloat("rtx_light_distant_angle", 0.5)
    -- Dome texture
    self:SetNWString("rtx_light_dome_tex", "")
end

function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr.Hit then return end
    local classname = ClassName or "remix_rt_light"
    local ent = ents.Create(classname)
    if not IsValid(ent) then return end
    ent:SetPos(tr.HitPos + tr.HitNormal * 16)
    ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ent:Spawn()
    ent:Activate()
    return ent
end

local function vec_to_table(v) return { x = v.x, y = v.y, z = v.z } end

function ENT:CreateRemixLight()
    if not RemixLight then return end
    local pos = self:GetPos() + Vector(0,0,10)
    local base = {
        -- Use decimal CRC to avoid nil from base-16 conversion; ensures unique, stable hash per entity
        hash = tonumber(util.CRC("ent_light_" .. self:EntIndex())) or 1,
        radiance = { x = 15, y = 15, z = 15 },
    }
    local sphere = {
        position = vec_to_table(pos),
        radius = 20,
        shaping = {
            direction = { x = 0, y = 0, z = -1 },
            coneAngleDegrees = 90,
            coneSoftness = 0.1,
            focusExponent = 1.0,
        },
        volumetricRadianceScale = 1.0,
    }
    self.LightId = RemixLight.CreateSphere(base, sphere, self:EntIndex())
end

function ENT:Think()
    if not self.LightId then
        self:CreateRemixLight()
        self.NextUpdate = CurTime() + 0.1
        self:NextThink(CurTime())
        return true
    end

    if CurTime() >= self.NextUpdate then
        -- Server only updates pose. Client will issue the Update using NW values
        self:SetNWVector("rtx_light_pos", self:GetPos())
        self.NextUpdate = CurTime() + 0.1
    end

    self:NextThink(CurTime())
    return true
end


