local convar_Debug = CreateClientConVar("rtx_bounds_debug", "0", true, false, "Enable debug")

local specialEntitiesBounds = {
    ["hdri_cube_editor"] = 32768,
    ["sky_camera"] = 32768,
    ["prop_door_rotating"] = 512,
    ["prop_physics"] = 768,
    ["gmod_lamp"] = 768,
    ["gmod_light"] = 768,
    -- Add more entities with their custom sizes as needed
}

local regexPatterns = {
    ["^npc_.*$"] = 768,  -- All NPCs
}

-- Render Bounds stuff
local function MatchEntityClassToPattern(class)
    for pattern, size in pairs(regexPatterns) do
        if string.match(class, pattern) then
            return size
        end
    end
    return nil
end

local function SetProperLightBounds(ent)
    if not IsValid(ent) then return end
    
    local size = 256 -- Default for regular lights
    
    -- Check for specific light types
    if ent.lightType == "light_environment" then
        size = 32768 -- Environment lights need much larger bounds
    end
    
    local boundsMin = Vector(-size, -size, -size)
    local boundsMax = Vector(size, size, size)
    ent:SetRenderBounds(boundsMin, boundsMax)
    
    if convar_Debug:GetBool() then
        print("[Static Render] Set render bounds for " 
            .. ent:GetClass() 
            .. (ent.lightType and (" (" .. ent.lightType .. ")") or "")
            .. " to", size)
    end
    
    return size
end

-- HDRI and light bounds setup (on entity creation)
hook.Add("OnEntityCreated", "RTXRenderer_SetEntityBounds", function(ent)
    if not IsValid(ent) then return end
    
    -- For RTX light updaters, use special handling
    if ent:GetClass() == "rtx_lightupdater" then
        timer.Simple(0.2, function()
            if IsValid(ent) then
                SetProperLightBounds(ent)
            end
        end)
        return
    end
    
    -- First check for exact class matches
    local size = specialEntitiesBounds[ent:GetClass()]
    
    -- If no exact match, try regex patterns
    if not size then
        size = MatchEntityClassToPattern(ent:GetClass())
    end
    
    -- If we found a matching size, set the bounds
    if size then
        timer.Simple(0.1, function()
            if IsValid(ent) then
                local boundsMin = Vector(-size, -size, -size)
                local boundsMax = Vector(size, size, size)
                ent:SetRenderBounds(boundsMin, boundsMax)
                
                if convar_Debug:GetBool() then
                    print("[Static Render] Set render bounds for " .. ent:GetClass() .. " to " .. size)
                end
            end
        end)
    end
end)

-- Process all existing light updaters
local function UpdateAllLightBounds()
    local updaters = ents.FindByClass("rtx_lightupdater")
    local countsByType = {}
    
    for _, ent in ipairs(updaters) do
        local size = SetProperLightBounds(ent)
        local lightType = ent.lightType or "unknown"
        
        countsByType[lightType] = (countsByType[lightType] or 0) + 1
    end
    
    -- Log summary
    if convar_Debug:GetBool() then
        print("[Static Render] Updated bounds for " .. #updaters .. " light updaters:")
        for lightType, count in pairs(countsByType) do
            print("  - " .. lightType .. ": " .. count)
        end
    end
end

local function UpdateAllSpecialEntitiesBounds()
    local totalCount = 0
    local countsByClass = {}
    
    -- Process exact class matches
    for entityClass, size in pairs(specialEntitiesBounds) do
        local entities = ents.FindByClass(entityClass)
        for _, ent in ipairs(entities) do
            if IsValid(ent) then
                local boundsMin = Vector(-size, -size, -size)
                local boundsMax = Vector(size, size, size)
                ent:SetRenderBounds(boundsMin, boundsMax)
                totalCount = totalCount + 1
                countsByClass[entityClass] = (countsByClass[entityClass] or 0) + 1
            end
        end
    end
    
    -- Process regex pattern matches (need to go through all entities)
    local allEntities = ents.GetAll()
    for _, ent in ipairs(allEntities) do
        if IsValid(ent) then
            local class = ent:GetClass()
            
            -- Skip entities already processed by exact class match
            if not specialEntitiesBounds[class] then
                local size = MatchEntityClassToPattern(class)
                if size then
                    local boundsMin = Vector(-size, -size, -size)
                    local boundsMax = Vector(size, size, size)
                    ent:SetRenderBounds(boundsMin, boundsMax)
                    totalCount = totalCount + 1
                    countsByClass[class] = (countsByClass[class] or 0) + 1
                end
            end
        end
    end
    
    -- Log summary
    if convar_Debug:GetBool() and totalCount > 0 then
        print("[Static Render] Updated bounds for " .. totalCount .. " special entities in total")
        for class, count in pairs(countsByClass) do
            if count > 0 then
                print("  - " .. class .. ": " .. count)
            end
        end
    end
end

-- Run after map load and periodically
hook.Add("InitPostEntity", "RTXRenderer_InitBounds", function()
    -- Wait for entities to be created
    timer.Simple(2, function()
        print("[Static Render] Running initial bounds update...")
        UpdateAllLightBounds()
        UpdateAllSpecialEntitiesBounds()
        
        -- Set up periodic check
        timer.Create("RTXRenderer_BoundsRefresh", 30, 0, function()
            if convar_Debug:GetBool() then
                print("[Static Render] Running periodic bounds refresh...")
            end
            UpdateAllLightBounds()
            UpdateAllSpecialEntitiesBounds()
        end)
    end)
end)

-- Add console command to manually update bounds
concommand.Add("rtx_update_bounds", function()
    print("[Static Render] Manually updating all render bounds...")
    UpdateAllLightBounds()
    UpdateAllSpecialEntitiesBounds()
end)