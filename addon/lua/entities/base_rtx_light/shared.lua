ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "RTX Light"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.Category = "RTX"

function ENT:SetupDataTables()
    -- Existing networked vars
    self:NetworkVar("Float", 0, "LightBrightness")
    self:NetworkVar("Float", 1, "LightSize")
    self:NetworkVar("Int", 0, "LightR")
    self:NetworkVar("Int", 1, "LightG")
    self:NetworkVar("Int", 2, "LightB")
    self:NetworkVar("Int", 3, "LightType")  -- 0 = Sphere, 1 = Rect, 2 = Disk, 3 = Distant
    self:NetworkVar("Float", 2, "RectWidth")
    self:NetworkVar("Float", 3, "RectHeight")
    self:NetworkVar("Float", 4, "AngularDiameter")
    
    -- Light shaping properties
    self:NetworkVar("Bool", 0, "ShapingEnabled")
    self:NetworkVar("Float", 5, "ConeAngle")
    self:NetworkVar("Float", 6, "ConeSoftness")
    
    -- Add rotation control properties
    self:NetworkVar("Angle", 0, "LightRotation")  -- Store rotation as Angle

    if SERVER then
        -- Existing notify hooks
        self:NetworkVarNotify("LightBrightness", self.OnVarChanged)
        self:NetworkVarNotify("LightSize", self.OnVarChanged)
        self:NetworkVarNotify("LightR", self.OnVarChanged)
        self:NetworkVarNotify("LightG", self.OnVarChanged)
        self:NetworkVarNotify("LightB", self.OnVarChanged)
        self:NetworkVarNotify("LightType", self.OnVarChanged)
        self:NetworkVarNotify("RectWidth", self.OnVarChanged)
        self:NetworkVarNotify("RectHeight", self.OnVarChanged)
        self:NetworkVarNotify("AngularDiameter", self.OnVarChanged)
        
        -- New notify hooks
        self:NetworkVarNotify("ShapingEnabled", self.OnVarChanged)
        self:NetworkVarNotify("ConeAngle", self.OnVarChanged)
        self:NetworkVarNotify("ConeSoftness", self.OnVarChanged)
        self:NetworkVarNotify("LightRotation", self.OnVarChanged)
    end
end

function ENT:OnVarChanged(name, old, new)
    -- Handle property changes
    if CLIENT and self.rtxLightHandle then
        -- Force an immediate update when properties change
        self.lastUpdatePos = nil  -- This will force the Think function to update
        self:Think()  -- Call Think immediately to apply changes
    end
end