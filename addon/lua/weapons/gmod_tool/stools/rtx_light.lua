local COOLDOWN_TIME = 0.1

TOOL.Category = "Lighting"
TOOL.Name = "Remix API Light"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    ["brightness"] = "100",
    ["size"] = "200",
    ["r"] = "255",
    ["g"] = "255",
    ["b"] = "255",
    ["update_rate"] = "60"
}

function TOOL:LeftClick(trace)
    if CLIENT then return true end

    -- Validate trace
    if not trace or not trace.Hit then return false end
    if not trace.HitPos then return false end

    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    -- Add cooldown to prevent rapid spawning
    if not self.LastSpawn then self.LastSpawn = 0 end
    if CurTime() - self.LastSpawn < 0.5 then return false end
    self.LastSpawn = CurTime()

    local pos = trace.HitPos
    
    -- Get and clamp tool settings
    local brightness = math.Clamp(self:GetClientNumber("brightness", 100), 1, 1000)
    local size = math.Clamp(self:GetClientNumber("size", 200), 1, 1000)
    local r = math.Clamp(self:GetClientNumber("r", 255), 0, 255)
    local g = math.Clamp(self:GetClientNumber("g", 255), 0, 255)
    local b = math.Clamp(self:GetClientNumber("b", 255), 0, 255)

    -- Create entity without effects
    local ent = ents.Create("base_rtx_light")
    if not IsValid(ent) then return false end

    ent:SetPos(pos)
    ent:SetAngles(angle_zero)
    
    -- Set initial properties
    ent.InitialProperties = {
        brightness = brightness,
        size = size,
        r = r,
        g = g,
        b = b
    }
    
    ent:Spawn()
    ent:Activate()

    -- Create undo without network messages
    undo.Create("RTX Light")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
        undo.SetCustomUndoText("Undone RTX Light")
    undo.Finish()

    -- Add to cleanup
    cleanup.Add(ply, "rtx_lights", ent)

    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    
    if IsValid(trace.Entity) and trace.Entity:GetClass() == "base_rtx_light" then
        trace.Entity:Remove()
        return true
    end
    
    return false
end

function TOOL:Reload(trace)
    if not IsValid(trace.Entity) or trace.Entity:GetClass() ~= "base_rtx_light" then return false end
    
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    ply:ConCommand("rtx_light_brightness " .. trace.Entity:GetLightBrightness())
    ply:ConCommand("rtx_light_size " .. trace.Entity:GetLightSize())
    ply:ConCommand("rtx_light_r " .. trace.Entity:GetLightR())
    ply:ConCommand("rtx_light_g " .. trace.Entity:GetLightG())
    ply:ConCommand("rtx_light_b " .. trace.Entity:GetLightB())

    return true
end

if CLIENT then
    language.Add("tool.rtx_light.name", "RTX Light")
    language.Add("tool.rtx_light.desc", "Create RTX Remix API lights")
    language.Add("tool.rtx_light.0", "Left click to create a light. Right click to remove. Reload to copy settings.")

    function TOOL.BuildCPanel(panel)
        panel:NumSlider("Brightness", "rtx_light_brightness", 1, 1000, 0)
        panel:NumSlider("Size", "rtx_light_size", 1, 1000, 0)
        panel:ColorPicker("Light Color", "rtx_light_r", "rtx_light_g", "rtx_light_b")
    end
end

-- Disable default tool effects
function TOOL:DrawToolScreen() return false end
function TOOL:DoEffect() return false end