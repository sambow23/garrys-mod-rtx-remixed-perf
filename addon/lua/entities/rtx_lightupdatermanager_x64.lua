-- CreateConVar( "rtx_lightupdater_count", 4096,  FCVAR_ARCHIVE )
-- CreateConVar( "rtx_lightupdater_show", 0,  FCVAR_ARCHIVE )
-- CreateConVar( "rtx_lightupdater_slowupdate", 1,  FCVAR_ARCHIVE )
-- AddCSLuaFile()

-- ENT.Type            = "anim"
-- ENT.PrintName       = "lightupdatermanager_x64"
-- ENT.Author          = "Xenthio and CR"
-- ENT.Information     = "update lights as fast as possible"
-- ENT.Category        = "RTX"

-- ENT.Spawnable       = false
-- ENT.AdminSpawnable  = false

-- CreateConVar("rtx_lightupdater_debug", "0", FCVAR_ARCHIVE, "Show debug information for light updaters")

-- local LIGHT_TYPES = {
--     POINT = "light",
--     SPOT = "light_spot",
--     DYNAMIC = "light_dynamic",
--     ENVIRONMENT = "light_environment",
--     DIRECTIONAL = "light_directional"
-- }

-- -- Separate regular lights from environment lights
-- local REGULAR_LIGHT_TYPES = {
--     [LIGHT_TYPES.POINT] = true,
--     [LIGHT_TYPES.SPOT] = true,
--     [LIGHT_TYPES.DYNAMIC] = true,
--     [LIGHT_TYPES.DIRECTIONAL] = true
-- }

-- -- Caches
-- local RTXMath = RTXMath -- Cache the reference
-- local Vector = Vector
-- local IsValid = IsValid

-- function shuffle(tbl)
--     for i = #tbl, 2, -1 do
--         local j = math.random(i)
--         tbl[i], tbl[j] = tbl[j], tbl[i]
--     end
--     return tbl
-- end

-- function TableConcat(t1,t2)
--     for i=1,#t2 do
--         t1[#t1+1] = t2[i]
--     end
--     return t1
-- end

-- function ENT:CreateUpdaters()
--     -- Create updaters for regular lights
--     self.regularUpdaters = {}
    
--     -- Create an updater for every regular light
--     for i, light in ipairs(self.regularLights) do
--         local updater = ents.CreateClientside("rtx_lightupdater")
--         updater.lightInfo = light
--         updater.lightType = light.lightType
--         updater.lightIndex = i
--         updater.lightOrigin = light.origin
--         updater:Spawn()
--         self.regularUpdaters[i] = updater
--     end

--     -- Create updaters for environment lights
--     self.environmentUpdaters = {}
--     for i, light in ipairs(self.environmentLights) do
--         local updater = ents.CreateClientside("rtx_lightupdater")
--         updater.lightInfo = light
--         updater.lightType = LIGHT_TYPES.ENVIRONMENT
--         updater.lightIndex = i
--         updater.lightOrigin = light.origin
--         updater:Spawn()
--         self.environmentUpdaters[i] = updater
--     end
    
--     -- Print debug info
--     print(string.format("[RTX Remix Fixes 2 - Lights] Created %d regular light updaters and %d environment light updaters",
--         #self.regularUpdaters,
--         #self.environmentUpdaters))
-- end

-- function ENT:Initialize() 
--     if (GetConVar("mat_fullbright"):GetBool()) then return end
--     self:SetModel("models/hunter/blocks/cube025x025x025.mdl") 
    
--     self:SetRenderMode(2)
--     self:SetColor(Color(255, 255, 255, 1))
    
--     -- Get all lights from the map using NikNaks
--     self.regularLights = {}
--     self.environmentLights = {}
    
--     if NikNaks and NikNaks.CurrentMap then
--         -- Find and categorize all lights without distance culling
--         -- Point lights
--         for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light")) do
--             light.lightType = LIGHT_TYPES.POINT
--             table.insert(self.regularLights, light)
--         end
        
--         -- Spot lights
--         for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light_spot")) do
--             light.lightType = LIGHT_TYPES.SPOT
--             table.insert(self.regularLights, light)
--         end
        
--         -- Dynamic lights
--         for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light_dynamic")) do
--             light.lightType = LIGHT_TYPES.DYNAMIC
--             table.insert(self.regularLights, light)
--         end

--         for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light_directional")) do
--             light.lightType = LIGHT_TYPES.DIRECTIONAL
--             table.insert(self.regularLights, light)
--         end
        
--         -- Environment lights
--         for _, light in ipairs(NikNaks.CurrentMap:FindByClass("light_environment")) do
--             light.lightType = LIGHT_TYPES.ENVIRONMENT
--             table.insert(self.environmentLights, light)
--         end
--     end

--     -- Create updaters with no limit
--     self:CreateUpdaters()

--     if GetConVar("rtx_lightupdater_debug"):GetBool() then
--         print("[RTX Remix Fixes 2 - Lights] Light counts by type:")
--         local counts = {}
--         for _, light in ipairs(self.regularLights) do
--             counts[light.lightType] = (counts[light.lightType] or 0) + 1
--         end
--         counts[LIGHT_TYPES.ENVIRONMENT] = #self.environmentLights
        
--         for type, count in pairs(counts) do
--             print(string.format("  %s: %d", type, count))
--         end
--     end
-- end

-- function MovetoPositions(self)  
--     if not self.regularUpdaters and not self.environmentUpdaters then
--         self:Remove() 
--         return
--     end
    
--     -- Handle regular lights (these get shuffled)
--     if self.doshuffle then
--         self.regularLights = shuffle(self.regularLights)
--     end
    
--     -- Update regular light updaters
--     for i, updater in pairs(self.regularUpdaters) do
--         if self.regularLights[i] == nil or GetConVar("mat_fullbright"):GetBool() then
--             self.shouldslowupdate = true
--             table.remove(self.regularUpdaters, i)
--             updater:Remove() 
--         else
--             updater:SetPos(self.regularLights[i].origin) 
--             updater:SetRenderMode(2) 
--             updater:SetColor(Color(255,255,255,1))
            
--             if GetConVar("rtx_lightupdater_show"):GetBool() then
--                 updater:SetRenderMode(0) 
--             end
--         end
--     end

--     -- Update environment light updaters (these stay fixed)
--     for i, updater in pairs(self.environmentUpdaters) do
--         if GetConVar("mat_fullbright"):GetBool() then
--             updater:Remove()
--         else
--             updater:SetPos(self.environmentLights[i].origin)
--             updater:SetRenderMode(2)
--             updater:SetColor(Color(255,255,255,1))
            
--             if GetConVar("rtx_lightupdater_show"):GetBool() then
--                 updater:SetRenderMode(0)
--             end
--         end
--     end
-- end

-- function ENT:Think()
--     if GetConVar("rtx_lightupdater_slowupdate"):GetBool() and self.shouldslowupdate then
--         self:NextThink(CurTime() + 10)
--         self:SetNextClientThink(CurTime() + 10)
--     end
--     MovetoPositions(self)
-- end

-- function ENT:OnRemove() 
-- end