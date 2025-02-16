CreateConVar( "rtx_lightupdater_count", 4096,  FCVAR_ARCHIVE )
CreateConVar( "rtx_lightupdater_show", 0,  FCVAR_ARCHIVE )
CreateConVar( "rtx_lightupdater_slowupdate", 1,  FCVAR_ARCHIVE )
AddCSLuaFile()

ENT.Type            = "anim"
ENT.PrintName       = "lightupdatermanager"
ENT.Author          = "Xenthio"
ENT.Information     = "update lights as fast as possible"
ENT.Category        = "RTX"

ENT.Spawnable       = false
ENT.AdminSpawnable  = false

local LIGHT_TYPES = {
    POINT = "light",
    SPOT = "light_spot",
    DYNAMIC = "light_dynamic",
    ENVIRONMENT = "light_environment"
}

-- Separate regular lights from environment lights
local REGULAR_LIGHT_TYPES = {
    [LIGHT_TYPES.POINT] = true,
    [LIGHT_TYPES.SPOT] = true,
    [LIGHT_TYPES.DYNAMIC] = true
}

function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

function TableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function ENT:Initialize() 
    if (GetConVar( "mat_fullbright" ):GetBool()) then return end
    print("[RTX Fixes] - Lightupdater Initialised.") 
    self:SetModel("models/hunter/blocks/cube025x025x025.mdl") 
    
    -- Use consistent render mode and opacity
    self:SetRenderMode(2)  // RENDERMODE_TRANSALPHA
    self:SetColor(Color(255, 255, 255, 1))
    
    -- Get all lights from the map using NikNaks
    self.regularLights = {}
    self.environmentLights = {}
    
    if NikNaks and NikNaks.CurrentMap then
        -- Find and categorize all lights
        local allLights = {}
        for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light")) do
            light.lightType = LIGHT_TYPES.POINT
            table.insert(allLights, light)
        end
        for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light_spot")) do
            light.lightType = LIGHT_TYPES.SPOT
            table.insert(allLights, light)
        end
        for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light_dynamic")) do
            light.lightType = LIGHT_TYPES.DYNAMIC
            table.insert(allLights, light)
        end
        for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light_environment")) do
            light.lightType = LIGHT_TYPES.ENVIRONMENT
            table.insert(self.environmentLights, light)
        end

        -- Regular lights get shuffled, environment lights don't
        self.regularLights = allLights
    end

    -- Create updaters for regular lights
    self.regularUpdaters = {}
    local maxRegularUpdaters = math.min(GetConVar("rtx_lightupdater_count"):GetInt(), #self.regularLights)
    
    for i = 1, maxRegularUpdaters do
        local light = self.regularLights[i]
        if light then
            local updater = ents.CreateClientside("rtx_lightupdater")
            updater.lightInfo = light
            updater.lightType = light.lightType
            updater.lightIndex = i
            updater.lightOrigin = light.origin
            updater:Spawn()
            self.regularUpdaters[i] = updater
            print(string.format("[RTX Fixes] Created Regular Light Updater %d for %s at %s", 
                i, light.lightType, tostring(light.origin)))
        end
    end

    -- Create updaters for environment lights (always create these)
    self.environmentUpdaters = {}
    for i, light in ipairs(self.environmentLights) do
        local updater = ents.CreateClientside("rtx_lightupdater")
        updater.lightInfo = light
        updater.lightType = LIGHT_TYPES.ENVIRONMENT
        updater.lightIndex = i
        updater.lightOrigin = light.origin
        updater:Spawn()
        self.environmentUpdaters[i] = updater
        print(string.format("[RTX Fixes] Created Environment Light Updater %d at %s", 
            i, tostring(light.origin)))
    end

    self.shouldslowupdate = false
    self.doshuffle = true
    MovetoPositions(self)
end

function MovetoPositions(self)  
    if not self.regularUpdaters and not self.environmentUpdaters then
        self:Remove() 
        return
    end
    
    -- Handle regular lights (these get shuffled)
    if self.doshuffle then
        self.regularLights = shuffle(self.regularLights)
    end
    
    -- Update regular light updaters
    for i, updater in pairs(self.regularUpdaters) do
        if self.regularLights[i] == nil or GetConVar("mat_fullbright"):GetBool() then
            self.shouldslowupdate = true
            table.remove(self.regularUpdaters, i)
            updater:Remove() 
        else
            updater:SetPos(self.regularLights[i].origin) 
            updater:SetRenderMode(2) 
            updater:SetColor(Color(255,255,255,1))
            
            if GetConVar("rtx_lightupdater_show"):GetBool() then
                updater:SetRenderMode(0) 
            end
        end
    end

    -- Update environment light updaters (these stay fixed)
    for i, updater in pairs(self.environmentUpdaters) do
        if GetConVar("mat_fullbright"):GetBool() then
            updater:Remove()
        else
            updater:SetPos(self.environmentLights[i].origin)
            updater:SetRenderMode(2)
            updater:SetColor(Color(255,255,255,1))
            
            if GetConVar("rtx_lightupdater_show"):GetBool() then
                updater:SetRenderMode(0)
            end
        end
    end
end

function ENT:Think()
    if GetConVar("rtx_lightupdater_slowupdate"):GetBool() and self.shouldslowupdate then
        self:NextThink(CurTime() + 10)
        self:SetNextClientThink(CurTime() + 10)
    end
    MovetoPositions(self)
end

function ENT:OnRemove() 
end