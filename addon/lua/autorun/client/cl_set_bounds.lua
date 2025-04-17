local convar_Debug = CreateClientConVar("rtx_bounds_debug", "0", true, false, "Enable debug")
local convar_Interval = CreateClientConVar("rtx_bounds_interval", "1", true, false, "Update interval in seconds", 0.5, 10)

-- Caching mechanism
local enableCaching = CreateClientConVar("rtx_bounds_caching", "1", true, false, "Enable caching for entity bounds updates")
local cachedEntitiesByClass = {}
local cachedEntitiesByPattern = {}
local cachedLightUpdaters = {}
local patternToClassMap = {}

-- Entity limits and distances
local entityTypeLimits = {
    ["prop_physics"] = 300,  -- Only set bounds for 100 physics props
    ["npc_.*"] = 50,  -- Limit for all NPCs
}

-- Entities we're setting bounds for
local specialEntitiesBounds = {
    ["hdri_cube_editor"] = 32768,
    ["sky_camera"] = 32768,
    ["prop_door_rotating"] = 512,
    ["prop_physics"] = 768,
    ["gmod_lamp"] = 768,
    ["gmod_light"] = 768,
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
        print("[Set Bounds] Set render bounds for " 
            .. ent:GetClass() 
            .. (ent.lightType and (" (" .. ent.lightType .. ")") or "")
            .. " to", size)
    end
    
    return size
end

-- HDRI and light bounds setup (on entity creation)
hook.Add("OnEntityCreated", "RTXRenderer_SetEntityBounds", function(ent)
    if not IsValid(ent) then return end
    local class = ent:GetClass()

    -- Handle light updaters separately (always processed, caching helps lookup)
    if class == "rtx_lightupdater" then
        if enableCaching:GetBool() then
            table.insert(cachedLightUpdaters, ent)
        end
        -- Initial bounds setting (can still happen here)
        timer.Simple(0.2, function()
            if IsValid(ent) then
                SetProperLightBounds(ent)
            end
        end)
        return -- Stop processing for light updaters here
    end

    -- Check for exact class match
    local size = specialEntitiesBounds[class]
    if size then
        if enableCaching:GetBool() then
            if not cachedEntitiesByClass[class] then cachedEntitiesByClass[class] = {} end
            table.insert(cachedEntitiesByClass[class], ent)
        end
        -- Apply initial bounds
        timer.Simple(0.1, function()
             if IsValid(ent) then
                 local boundsMin = Vector(-size, -size, -size)
                 local boundsMax = Vector(size, size, size)
                 ent:SetRenderBounds(boundsMin, boundsMax)
                 
                 if convar_Debug:GetBool() then
                     print("[Set Bounds] Set render bounds for " .. ent:GetClass() .. " to " .. size)
                 end
             end
         end)
        return
    end

    -- Check for regex pattern match
    for pattern, pSize in pairs(regexPatterns) do
        if string.match(class, pattern) then
            if enableCaching:GetBool() then
                if not cachedEntitiesByPattern[pattern] then cachedEntitiesByPattern[pattern] = {} end
                table.insert(cachedEntitiesByPattern[pattern], ent)
                patternToClassMap[class] = pattern
            end
            -- Apply initial bounds for regex matches too
             timer.Simple(0.1, function()
                 if IsValid(ent) then
                     local boundsMin = Vector(-pSize, -pSize, -pSize)
                     local boundsMax = Vector(pSize, pSize, pSize)
                     ent:SetRenderBounds(boundsMin, boundsMax)
                     
                     if convar_Debug:GetBool() then
                         print("[Set Bounds] Set render bounds for " .. ent:GetClass() .. " to " .. pSize)
                     end
                 end
             end)
            return
        end
    end
end)

local function InitializeCaches()
    if not enableCaching:GetBool() then
        print("[Set Bounds] Caching disabled.")
        return
    end

    print("[Set Bounds] Initializing entity caches...")
    -- Clear existing caches
    cachedEntitiesByClass = {}
    cachedEntitiesByPattern = {}
    cachedLightUpdaters = {}
    patternToClassMap = {}

    -- Populate caches
    local allEnts = ents.GetAll()
    for _, ent in ipairs(allEnts) do
        if IsValid(ent) then
            local class = ent:GetClass()

            -- Light updaters
            if class == "rtx_lightupdater" then
                table.insert(cachedLightUpdaters, ent)
                goto continue_loop -- Skip other checks for this entity
            end

            -- Exact matches
            if specialEntitiesBounds[class] then
                 if not cachedEntitiesByClass[class] then cachedEntitiesByClass[class] = {} end
                 table.insert(cachedEntitiesByClass[class], ent)
                 goto continue_loop -- Skip pattern check if exact match found
            end

            -- Pattern matches
            for pattern, _ in pairs(regexPatterns) do
                if string.match(class, pattern) then
                    if not cachedEntitiesByPattern[pattern] then cachedEntitiesByPattern[pattern] = {} end
                    table.insert(cachedEntitiesByPattern[pattern], ent)
                    patternToClassMap[class] = pattern -- Store pattern mapping
                    break -- Stop checking patterns for this entity
                end
            end
        end
        ::continue_loop::
    end
    print("[Set Bounds] Caches initialized.")
end

local function CleanupInvalidCachedEntities()
    if not enableCaching:GetBool() then return end

    local function cleanupList(list)
        local validCount = 0
        for i = #list, 1, -1 do
            if IsValid(list[i]) then
                validCount = validCount + 1
            else
                table.remove(list, i)
            end
        end
        return validCount > 0
    end

    -- Cleanup light updaters
    cleanupList(cachedLightUpdaters)

    -- Cleanup exact class matches
    for class, list in pairs(cachedEntitiesByClass) do
        if not cleanupList(list) then
            cachedEntitiesByClass[class] = nil
        end
    end

    -- Cleanup pattern matches
    for pattern, list in pairs(cachedEntitiesByPattern) do
        if not cleanupList(list) then
            cachedEntitiesByPattern[pattern] = nil
        end
    end
end

local function GetEntityLimit(class)
    -- Direct match
    if entityTypeLimits[class] then
        return entityTypeLimits[class]
    end
    
    -- Pattern match
    for pattern, limit in pairs(entityTypeLimits) do
        if string.match(class, pattern) then
            return limit
        end
    end
    
    return 0
end

local function ClearRenderBounds(ent)
    if IsValid(ent) then
        -- Set to minimal bounds to essentially "disable" the extended render bounds
        local minBounds = Vector(-1, -1, -1)
        local maxBounds = Vector(1, 1, 1)
        ent:SetRenderBounds(minBounds, maxBounds)
        
        if convar_Debug:GetBool() then
            print("[Set Bounds] Cleared render bounds for " .. ent:GetClass())
        end
    end
end

-- Process all existing light updaters - uses cache if enabled
local function UpdateAllLightBounds()
    local updaters = enableCaching:GetBool() and cachedLightUpdaters or ents.FindByClass("rtx_lightupdater")
    local countsByType = {}

    for _, ent in ipairs(updaters) do
        if IsValid(ent) then
            local size = SetProperLightBounds(ent)
            local lightType = ent.lightType or "unknown"
            countsByType[lightType] = (countsByType[lightType] or 0) + 1
        end
    end

    -- Log summary
    if convar_Debug:GetBool() then
        local source = enableCaching:GetBool() and "cache" or "ents.FindByClass"
        print("[Set Bounds] Updated bounds for " .. #updaters .. " light updaters (from " .. source .. "):")
        for lightType, count in pairs(countsByType) do
            print("  - " .. lightType .. ": " .. count)
        end
    end
end

-- Updated function using caches
local function UpdateAllSpecialEntitiesBounds()
    local totalCount = 0
    local countsByClass = {}
    local processedCounts = {}
    local playerPos = LocalPlayer():GetPos()
    local shouldHaveBounds = {}

    local useCache = enableCaching:GetBool()

    for entityClass, size in pairs(specialEntitiesBounds) do
        local limit = GetEntityLimit(entityClass)
        if limit <= 0 then goto continue_exact end

        local entities
        if useCache then
            entities = cachedEntitiesByClass[entityClass]
            if not entities or #entities == 0 then goto continue_exact end
        else
            entities = ents.FindByClass(entityClass)
        end

        processedCounts[entityClass] = 0
        shouldHaveBounds[entityClass] = {}
        local sortedEntities = {}

        for _, ent in ipairs(entities) do
            if IsValid(ent) then
                table.insert(sortedEntities, {
                    entity = ent,
                    distance = ent:GetPos():DistToSqr(playerPos)
                })
            end
        end

        if #sortedEntities == 0 then goto continue_exact end

        table.sort(sortedEntities, function(a, b) return a.distance < b.distance end)

        -- Process up to the limit
        for i = 1, math.min(limit, #sortedEntities) do
            local ent = sortedEntities[i].entity
            local boundsMin = Vector(-size, -size, -size)
            local boundsMax = Vector(size, size, size)
            ent:SetRenderBounds(boundsMin, boundsMax)
            shouldHaveBounds[entityClass][ent:EntIndex()] = true
            totalCount = totalCount + 1
            processedCounts[entityClass] = processedCounts[entityClass] + 1
        end

        -- Clear bounds for entities beyond the limit
        for i = limit + 1, #sortedEntities do
            ClearRenderBounds(sortedEntities[i].entity)
        end

        countsByClass[entityClass] = processedCounts[entityClass]

        ::continue_exact::
    end

    -- *** Process Regex Pattern Matches ***
    for pattern, size in pairs(regexPatterns) do
         local limit = GetEntityLimit(pattern)
         if limit <= 0 then goto continue_pattern end

         local entities
         if useCache then
             entities = cachedEntitiesByPattern[pattern]
             if not entities or #entities == 0 then goto continue_pattern end
         else
             -- Fallback: Need to find entities matching the pattern manually if cache disabled
             entities = {}
             for _, ent in ipairs(ents.GetAll()) do
                 if IsValid(ent) and string.match(ent:GetClass(), pattern) then
                     table.insert(entities, ent)
                 end
             end
             if #entities == 0 then goto continue_pattern end
         end

         processedCounts[pattern] = 0
         shouldHaveBounds[pattern] = {}
         local sortedEntities = {}

         for _, ent in ipairs(entities) do
             if IsValid(ent) then
                 table.insert(sortedEntities, {
                     entity = ent,
                     distance = ent:GetPos():DistToSqr(playerPos)
                 })
             end
         end

         if #sortedEntities == 0 then goto continue_pattern end

         table.sort(sortedEntities, function(a, b) return a.distance < b.distance end)

         -- Process up to the limit
         for i = 1, math.min(limit, #sortedEntities) do
             local ent = sortedEntities[i].entity
             local boundsMin = Vector(-size, -size, -size)
             local boundsMax = Vector(size, size, size)
             ent:SetRenderBounds(boundsMin, boundsMax)
             shouldHaveBounds[pattern][ent:EntIndex()] = true
             totalCount = totalCount + 1
             processedCounts[pattern] = processedCounts[pattern] + 1
         end

         -- Clear bounds beyond the limit
         for i = limit + 1, #sortedEntities do
             ClearRenderBounds(sortedEntities[i].entity)
         end

         countsByClass[pattern] = processedCounts[pattern]

         ::continue_pattern::
    end

    -- Store the current state for next refresh comparison
    _G.RTXRenderer_LastBoundsState = shouldHaveBounds
    
    -- Final Debug Output (if enabled)
    if convar_Debug:GetBool() and totalCount > 0 then
        local source = useCache and "cache" or "entity iteration"
        print("[Set Bounds] Updated bounds for " .. totalCount .. " special entities (from " .. source .. "):")
        for classOrPattern, count in pairs(countsByClass) do
            if count > 0 then
                local limit = GetEntityLimit(classOrPattern) or "∞"
                print("  - " .. classOrPattern .. ": " .. count .. " / " .. limit)
            end
        end
    end
end

-- Function to count and display entities by type
local function CountSpecialEntities()
    local counts = {}
    local totalCount = 0
    
    -- Count entities with exact class matches
    for entityClass, _ in pairs(specialEntitiesBounds) do
        local entities = ents.FindByClass(entityClass)
        counts[entityClass] = #entities
        totalCount = totalCount + #entities
    end
    
    -- Count entities matching regex patterns
    local countedByRegex = {}
    local allEntities = ents.GetAll()
    
    for _, ent in ipairs(allEntities) do
        if IsValid(ent) then
            local class = ent:GetClass()
            
            -- Skip entities already counted by exact match
            if not specialEntitiesBounds[class] and not countedByRegex[ent:EntIndex()] then
                for pattern, _ in pairs(regexPatterns) do
                    if string.match(class, pattern) then
                        counts[pattern] = (counts[pattern] or 0) + 1
                        countedByRegex[ent:EntIndex()] = true
                        totalCount = totalCount + 1
                        break
                    end
                end
            end
        end
    end
    
    -- Count light updaters separately
    local lightUpdaters = ents.FindByClass("rtx_lightupdater")
    counts["rtx_lightupdater"] = #lightUpdaters
    totalCount = totalCount + #lightUpdaters
    
    -- Sort and display results
    local sortedClasses = {}
    for class, count in pairs(counts) do
        table.insert(sortedClasses, {class = class, count = count})
    end
    
    table.sort(sortedClasses, function(a, b)
        return a.count > b.count
    end)
    
    print("=== RTX Special Entities Count ===")
    print("Total special entities: " .. totalCount)
    
    for _, info in ipairs(sortedClasses) do
        local class = info.class
        local count = info.count
        local limit = GetEntityLimit(class) or "∞"
        
        if class == "rtx_lightupdater" then
            print(string.format("%-30s %4d (always processed)", class, count))
        else
            print(string.format("%-30s %4d / %s", class, count, limit))
        end
    end
    print("=================================")
    
    return counts, totalCount
end

-- Periodic update timer
local lastUpdateTime = 0
local cleanupCounter = 0
local cleanupInterval = 10
local updateInterval = convar_Interval:GetFloat()

hook.Add("Think", "RTXRenderer_PeriodicUpdate", function()
    local currentTime = CurTime()
    if currentTime < lastUpdateTime + updateInterval then return end
    lastUpdateTime = currentTime

    UpdateAllLightBounds()
    UpdateAllSpecialEntitiesBounds()

    -- Periodic cache cleanup
    if enableCaching:GetBool() then
        cleanupCounter = cleanupCounter + 1
        if cleanupCounter >= cleanupInterval then
            cleanupCounter = 0
            timer.Simple(0, CleanupInvalidCachedEntities)
        end
    end
end)

-- Run after map load and periodically
hook.Add("InitPostEntity", "RTXRenderer_InitBounds", function()
    -- Wait for entities to be created
    timer.Simple(2, function()
        print("[Set Bounds] Running initial bounds update...")
        InitializeCaches()
        UpdateAllLightBounds()
        UpdateAllSpecialEntitiesBounds()
        
        -- Update interval when convar changes
        cvars.AddChangeCallback("rtx_bounds_interval", function(_, _, newValue)
            updateInterval = tonumber(newValue)
            print("[Set Bounds] Update interval changed to:", updateInterval)
        end)
    end)
end)

-- Add console commands
concommand.Add("rtx_update_bounds", function()
    print("[Set Bounds] Entity counts before updating bounds:")
    CountSpecialEntities()
    
    print("[Set Bounds] Manually updating all render bounds...")
    UpdateAllLightBounds()
    UpdateAllSpecialEntitiesBounds()
end)

concommand.Add("rtx_list_entities", function()
    CountSpecialEntities()
end)

concommand.Add("rtx_reinit_bounds_cache", function()
    print("[Set Bounds] Re-initializing entity caches...")
    InitializeCaches()
    print("[Set Bounds] Caches re-initialized. Running update...")
    UpdateAllLightBounds()
    UpdateAllSpecialEntitiesBounds()
end)

print("[Set Bounds] Bounds system initialized.")