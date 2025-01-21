ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "RTX Light"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.Category = "RTX"

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "LightBrightness")
    self:NetworkVar("Float", 1, "LightSize")
    self:NetworkVar("Int", 0, "LightR")
    self:NetworkVar("Int", 1, "LightG")
    self:NetworkVar("Int", 2, "LightB")

    if SERVER then
        self:NetworkVarNotify("LightBrightness", self.OnVarChanged)
        self:NetworkVarNotify("LightSize", self.OnVarChanged)
        self:NetworkVarNotify("LightR", self.OnVarChanged)
        self:NetworkVarNotify("LightG", self.OnVarChanged)
        self:NetworkVarNotify("LightB", self.OnVarChanged)
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