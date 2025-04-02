-- MAJOR THANK YOU to the creator of NikNaks, a lot of this would not be possible without it.
-- This addon is pretty heavy but it's the best compromise between performance and visual quality we have until better solutions arrive.

if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

-- ConVars (defined early so they're available to all systems)
local cv_enabled = CreateClientConVar("rtx_fr_enabled", "1", true, false, "Enable large render bounds for all entities")
local cv_bounds_size = CreateClientConVar("rtx_fr_bounds_size", "256", true, false, "Size of render bounds")
local cv_rtx_updater_distance = CreateClientConVar("rtx_fr_rtx_distance", "256", true, false, "Maximum render distance for regular RTX light updaters")
local cv_environment_light_distance = CreateClientConVar("rtx_fr_environment_light_distance", "32768", true, false, "Maximum render distance for environment light updaters")
local cv_debug = CreateClientConVar("rtx_fr_debug_messages", "0", true, false, "Enable debug messages for RTX view frustum optimization")
local cv_use_pvs = CreateClientConVar("rtx_fr_use_pvs", "1", true, false, "Use Potentially Visible Set for render bounds optimization")
local cv_pvs_update_interval = CreateClientConVar("rtx_fr_pvs_update_interval", "5", true, false, "How often to update the PVS data when the player isnt moving (seconds)")
local cv_pvs_hud = CreateClientConVar("rtx_fr_pvs_hud", "0", true, false, "Show HUD information about PVS optimization")
local cv_static_props_pvs = CreateClientConVar("rtx_fr_static_props_pvs", "1", true, false, "Use PVS for static prop optimization")
local cv_props_enabled = CreateClientConVar("rtx_fr_props_enabled", "1", true, false, "Enable render bounds modification for props")

-- Create a centralized state manager to track all resources
RTXFrustumState = RTXFrustumState or {
    -- System state
    active = false,           -- Is the system currently active
    initialized = false,      -- Has the system been initialized
    processingUpdate = false, -- Is an update in progress
    asyncPVSPending = false,  -- pendign async updates
    
    -- Entity tracking with strong references to prevent GC issues
    entitiesToReset = {},     -- Entities that need proper reset on toggle/change
    originalBounds = {},      -- Store original bounds for complete restoration
    
    -- Resource management
    managedHooks = {},        -- All hooks we've created
    managedTimers = {},       -- All timers we've created
    
    -- Performance-critical caches (weak tables)
    entitiesInPVS = {},       -- Current entities in PVS
    rtxUpdaters = {},         -- Current RTX updaters
    
    -- Statistics tracking
    stats = {
        entitiesInPVS = 0,
        totalEntities = 0,
        staticPropsInPVS = 0,
        staticPropsTotal = 0,
        pvsLeafCount = 0,
        totalLeafCount = 0,
        frameTime = 0,
        frameTimeAvg = 0,
        frameTimeHistory = {},
        updateTime = 0
    },
    
    -- Static prop management
    staticProps = {},         -- Track all created clientside static props
    
    -- Original settings to restore
    originalSettings = {
        staticPropSetting = 1 -- Original r_drawstaticprops value
    }
}

RTXFrustumState.alwaysVisibleEntities = {}

-- Initialize weak tables for performance-critical caches
setmetatable(RTXFrustumState.entitiesInPVS, {__mode = "k"})
setmetatable(RTXFrustumState.rtxUpdaters, {__mode = "k"})

-- ==========================================================================
-- CORE STATE MANAGEMENT FUNCTIONS
-- ==========================================================================

function RTXFrustumState:RegisterEntity(ent, originalMins, originalMaxs)
    if not IsValid(ent) then return end
    
    -- Store original bounds for later reset
    self.originalBounds[ent] = {
        mins = originalMins or ent:GetRenderBounds(),
        maxs = originalMaxs or ent:GetRenderBoundMaxs() 
    }
    
    -- Add to reset list with strong reference
    self.entitiesToReset[ent] = true
end

function RTXFrustumState:AddHook(event, name, func)
    -- Remove existing hook if present
    hook.Remove(event, name)
    
    -- Add the new hook
    hook.Add(event, name, func)
    
    -- Track it
    self.managedHooks[event .. "." .. name] = true
end

function RTXFrustumState:AddTimer(name, delay, repetitions, func)
    -- Remove existing timer if present
    if timer.Exists(name) then
        timer.Remove(name)
    end
    
    -- Create the timer
    timer.Create(name, delay, repetitions, func)
    
    -- Track it
    self.managedTimers[name] = true
end

function RTXFrustumState:Clear()
    -- Clear entity tracking while preserving tables
    for k in pairs(self.entitiesToReset) do self.entitiesToReset[k] = nil end
    for k in pairs(self.originalBounds) do self.originalBounds[k] = nil end
    for k in pairs(self.entitiesInPVS) do self.entitiesInPVS[k] = nil end
    for k in pairs(self.rtxUpdaters) do self.rtxUpdaters[k] = nil end
    
    -- Reset stats
    self.stats = {
        entitiesInPVS = 0,
        totalEntities = 0,
        staticPropsInPVS = 0,
        staticPropsTotal = 0,
        pvsLeafCount = 0,
        totalLeafCount = 0,
        frameTime = 0,
        frameTimeAvg = 0,
        frameTimeHistory = {},
        updateTime = 0
    }
    
    -- System state
    self.processingUpdate = false
end

function RTXFrustumState:RemoveAllStaticProps()
    local count = 0
    for prop, _ in pairs(self.staticProps) do
        if IsValid(prop) then
            prop:Remove()
            count = count + 1
        end
    end
    
    -- Clear the table completely
    self.staticProps = {}
    
    -- Reset stats
    self.stats.staticPropsInPVS = 0
    self.stats.staticPropsTotal = 0
    
    return count
end

function RTXFrustumState:RemoveAllHooks()
    local count = 0
    for hookID in pairs(self.managedHooks) do
        local event, name = string.match(hookID, "([^.]+)%.(.+)")
        if event and name then
            hook.Remove(event, name)
            count = count + 1
        end
    end
    
    -- Clear the tracking table
    self.managedHooks = {}
    
    return count
end

function RTXFrustumState:RemoveAllTimers()
    local count = 0
    for timerName in pairs(self.managedTimers) do
        if timer.Exists(timerName) then
            timer.Remove(timerName)
            count = count + 1
        end
    end
    
    -- Clear the tracking table
    self.managedTimers = {}
    
    return count
end

function RTXFrustumState:ResetAllEntityBounds()
    local count = 0
    for ent in pairs(self.entitiesToReset) do
        if IsValid(ent) and self.originalBounds[ent] then
            -- Reset to original bounds
            local bounds = self.originalBounds[ent]
            ent:SetRenderBounds(bounds.mins, bounds.maxs)
            count = count + 1
        end
    end
    
    return count
end

function RTXFrustumState:DeactivateSystem()
    -- Mark system as inactive immediately to prevent new operations
    self.active = false
    
    -- Remove all hooks and timers first
    local hooksRemoved = self:RemoveAllHooks()
    local timersRemoved = self:RemoveAllTimers()

    -- Cancel any async PVS processing
    if EntityManager and EntityManager.TerminateAsyncProcessing then
        EntityManager.TerminateAsyncProcessing()
    end
    
    -- Reset all entity bounds
    local entitiesReset = self:ResetAllEntityBounds()
    
    -- Remove static props
    local propsRemoved = self:RemoveAllStaticProps()
    
    -- Restore original settings
    if self.originalSettings.staticPropSetting then
        RunConsoleCommand("r_drawstaticprops", tostring(self.originalSettings.staticPropSetting))
    end
    
    -- Clear all state
    self:Clear()
    
    -- Force immediate garbage collection
    collectgarbage("collect")
    
    return {
        hooksRemoved = hooksRemoved,
        timersRemoved = timersRemoved,
        entitiesReset = entitiesReset,
        propsRemoved = propsRemoved
    }
end

function RTXFrustumState:ActivateSystem()
    -- Store original settings
    self.originalSettings.staticPropSetting = GetConVar("r_drawstaticprops"):GetInt()
    
    -- Initialize all subsystems
    self.PVSManager:Initialize()
    self.EntityManager:Initialize()
    self.LightManager:Initialize()
    self.StaticPropManager:Initialize()
    
    -- Mark system as active
    self.active = true
    self.initialized = true
    
    -- Initial processing
    self.LightManager:ScanForLights()
    
    -- If PVS is enabled, do an initial PVS update
    if cv_use_pvs:GetBool() then
        self.PVSManager:RequestUpdate(true)
    else
        -- Otherwise just process all entities
        self.EntityManager:ProcessAllEntities(false)
    end
    
    -- Create static props
    self.StaticPropManager:CreateAll()
end

-- ==========================================================================
-- PVS MANAGEMENT SYSTEM
-- ==========================================================================
RTXFrustumState.PVSManager = {
    current = nil,            -- Current PVS data
    lastUpdateTime = 0,       -- Last update timestamp
    updateInProgress = false, -- Update status flag
    lastPlayerPos = Vector(0,0,0),
    moveThreshold = 128,      -- Units player must move to trigger update
    leafPositions = {},       -- Cached leaf positions for the current PVS
    updateInterval = 5        -- Default update interval in seconds
}

function RTXFrustumState.PVSManager:Initialize()
    self.lastUpdateTime = 0
    self.updateInProgress = false
    self.lastPlayerPos = Vector(0,0,0)
    self.moveThreshold = 128
    self.updateInterval = cv_pvs_update_interval:GetFloat()
    self.leafPositions = {}
    return true
end

function RTXFrustumState.PVSManager:RequestUpdate(force)
    if not cv_use_pvs:GetBool() or not RTXFrustumState.active then return false end
    if self.updateInProgress and not force then return false end
    
    local currentTime = CurTime()
    
    -- Check if update is needed
    if not force and currentTime - self.lastUpdateTime < self.updateInterval then 
        return false 
    end
    
    -- Start update process
    self.updateInProgress = true
    local startTime = SysTime()
    
    -- Get player position
    local player = LocalPlayer()
    if not IsValid(player) then 
        self.updateInProgress = false
        return false 
    end
    
    local playerPos = player:GetPos()
    self.lastPlayerPos = playerPos
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Force View Frustum] PVS update from position: %.1f, %.1f, %.1f", 
            playerPos.x, playerPos.y, playerPos.z))
    end
    
    -- Check if we can use async PVS processing (best performance)
    if EntityManager and EntityManager.RequestAsyncPVSUpdate then
        -- Request async PVS processing
        EntityManager.RequestAsyncPVSUpdate(playerPos)
        
        if cv_debug:GetBool() then
            print("[RTX Force View Frustum] Requested async PVS update")
        end
        
        -- For force updates, we'll still do immediate processing for this frame
        -- For regular updates, we can exit early and let async processing complete
        if not force then
            self.updateInProgress = false
            return true
        end
    end
    
    -- Generate PVS data from NikNaks
    local pvs = NikNaks.CurrentMap:PVSForOrigin(playerPos)
    if not pvs then
        self.updateInProgress = false
        if cv_debug:GetBool() then
            print("[RTX Force View Frustum] Failed to generate PVS - NikNaks returned nil")
        end
        return false
    end
    
    -- Store the new PVS
    self.current = pvs
    
    -- Process leaf data
    self.leafPositions = {}
    local leafs = pvs:GetLeafs()
    
    for _, leaf in pairs(leafs) do
        if leaf then
            local mins = leaf.mins or leaf:OBBMins()
            local maxs = leaf.maxs or leaf:OBBMaxs()
            
            if mins and maxs then
                local center = Vector(
                    (mins.x + maxs.x) * 0.5,
                    (mins.y + maxs.y) * 0.5,
                    (mins.z + maxs.z) * 0.5
                )
                table.insert(self.leafPositions, center)
            end
        end
    end
    
    -- Update statistics
    RTXFrustumState.stats.pvsLeafCount = #self.leafPositions
    RTXFrustumState.stats.totalLeafCount = table.Count(NikNaks.CurrentMap:GetLeafs())
    
    -- Push leafs to optimized system if available
    if EntityManager and EntityManager.SetPVSLeafData_Optimized then
        local success = EntityManager.SetPVSLeafData_Optimized(self.leafPositions, playerPos)
        if cv_debug:GetBool() and success then
            print("[RTX Force View Frustum] PVS data optimized storage initialized")
        end
    end
    
    -- Trigger entity batch processing using unified system
    RTXFrustumState.EntityManager:ProcessAllEntities(false)
    
    -- Trigger static props update if enabled
    if cv_static_props_pvs:GetBool() then
        timer.Simple(0.1, function() 
            RTXFrustumState.StaticPropManager:UpdateAllProps()
        end)
    end
    
    self.lastUpdateTime = currentTime
    self.updateInProgress = false
    RTXFrustumState.stats.updateTime = SysTime() - startTime
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Force View Frustum] PVS update complete: %d leafs in %.2f ms", 
            #self.leafPositions, RTXFrustumState.stats.updateTime * 1000))
    end
    
    return true
end

function RTXFrustumState.PVSManager:ShouldUpdateForMovement()
    if not cv_use_pvs:GetBool() or not RTXFrustumState.active then return false end
    if self.updateInProgress then return false end
    
    local player = LocalPlayer()
    if not IsValid(player) then return false end
    
    local currentPos = player:GetPos()
    local moveDistance = currentPos:Distance(self.lastPlayerPos)
    
    return moveDistance > self.moveThreshold
end

function RTXFrustumState.PVSManager:IsInPVS(pos)
    if not self.current then return true end -- Default to visible if no PVS data
    
    if EntityManager and EntityManager.TestPositionInPVS_Optimized then
        return EntityManager.TestPositionInPVS_Optimized(pos)
    end
end

-- ==========================================================================
-- ENTITY MANAGEMENT SYSTEM
-- ==========================================================================
RTXFrustumState.EntityManager = {
    processingInProgress = false,
    entityBatches = {},
    currentBatchIndex = 0,
    batchSize = 250,
    priorityEntities = {},  -- High-priority entities processed first
    adaptiveBatchSizing = true,
    frameTimeHistory = {},
    maxProcessTimeMs = 8,     -- Maximum ms per frame to spend on processing
    highPriorityCount = 0,
    
    -- Cache entity type classifications
    entityTypeCache = {}
}

function RTXFrustumState.EntityManager:Initialize()
    self.processingInProgress = false
    self.entityBatches = {}
    self.currentBatchIndex = 0
    self.batchSize = 250
    self.priorityEntities = {}
    self.entityTypeCache = {}
    
    -- Create a weak reference table for entity type cache
    setmetatable(self.entityTypeCache, {__mode = "k"})
    
    return true
end

function RTXFrustumState.EntityManager:CreatePrioritizedBatches(entities)
    -- Get player position for distance calculations
    local playerPos = IsValid(LocalPlayer()) and LocalPlayer():GetPos() or Vector(0,0,0)
    
    -- Create prioritized groups
    local highPriority = {} -- RTX lights, special entities, nearby entities
    local normalPriority = {} -- Regular entities in potential view
    local lowPriority = {} -- Far away entities
    
    -- Sort entities into priority buckets
    for _, ent in ipairs(entities) do
        if not IsValid(ent) then continue end
        
        local entPos = ent:GetPos()
        local className = ent:GetClass()
        local distance = entPos:Distance(playerPos)
        
        -- High priority entities (RTX lights, nearby entities)
        if RTXFrustumState.rtxUpdaters[ent] or 
           RTXFrustumState.LightManager:IsSpecialEntity(className) or
           RTXFrustumState.LightManager:HasSpecialBounds(className) or
           distance < 1024 then
            table.insert(highPriority, ent)
        
        -- Normal priority (within reasonable distance)
        elseif distance < 5000 then
            table.insert(normalPriority, ent)
            
        -- Low priority (far away)
        else
            table.insert(lowPriority, ent)
        end
    end
    
    -- Combine the batches in priority order
    local result = {}
    for _, group in ipairs({highPriority, normalPriority, lowPriority}) do
        -- Split each priority group into batches
        for i = 1, #group, self.batchSize do
            local endIdx = math.min(i + self.batchSize - 1, #group)
            local batch = {}
            
            for j = i, endIdx do
                table.insert(batch, group[j])
            end
            
            table.insert(result, {
                entities = batch,
                priority = group == highPriority and "high" or (group == normalPriority and "normal" or "low")
            })
        end
    end
    
    -- Save high priority count for progress reporting
    self.highPriorityCount = #highPriority
    
    return result
end

function RTXFrustumState.EntityManager:ProcessEntitiesStandard(entities, forceOriginal)
    RTXFrustumState.stats.entitiesInPVS = 0
    RTXFrustumState.stats.totalEntities = #entities
    
    -- Process each entity individually
    for _, ent in ipairs(entities) do
        if IsValid(ent) then
            self:ProcessEntity(ent, forceOriginal)
            
            -- Track statistics
            if RTXFrustumState.entitiesInPVS[ent] then
                RTXFrustumState.stats.entitiesInPVS = RTXFrustumState.stats.entitiesInPVS + 1
            end
        end
    end
end

function RTXFrustumState.EntityManager:ProcessAllEntities(forceOriginal)
    if self.processingInProgress and not forceOriginal then return false end
    
    -- Start timer for performance tracking
    local startTime = SysTime()
    self.processingInProgress = true
    
    -- First handle special entities and RTX updaters separately
    -- These need special handling that's not suited for batching
    for ent in pairs(RTXFrustumState.rtxUpdaters) do
        if IsValid(ent) then
            if forceOriginal then
                RTXFrustumState.LightManager:ResetLightBounds(ent)
            else
                RTXFrustumState.LightManager:ApplyLightBounds(ent)
            end
        end
    end
    
    -- Handle special entities with custom bounds
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            local className = ent:GetClass()
            if RTXFrustumState.LightManager:HasSpecialBounds(className) then
                if forceOriginal then
                    self:ResetEntityBounds(ent)
                else
                    local specialBounds = RTXFrustumState.LightManager:GetSpecialBounds(className)
                    self:ApplySpecialEntityBounds(ent, specialBounds)
                end
            end
        end
    end
    
    -- If we want to force original bounds for everything, do it directly
    if forceOriginal then
        for ent in pairs(RTXFrustumState.entitiesToReset) do
            if IsValid(ent) then
                self:ResetEntityBounds(ent)
            end
        end
        
        self.processingInProgress = false
        return true
    end
    
    -- Process regular entities in batches using the native implementation
    if EntityManager and EntityManager.BatchProcessEntities then
        -- Get all entities and their positions
        local entities = {}
        local positions = {}
        local regularEntities = {}
        
        -- Get all entities that should be processed with Batch Mode
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and self:ShouldModifyEntityBounds(ent) and 
               not RTXFrustumState.rtxUpdaters[ent] and
               not RTXFrustumState.LightManager:HasSpecialBounds(ent:GetClass()) then
                
                table.insert(entities, ent)
                table.insert(positions, ent:GetPos())
                table.insert(regularEntities, ent)
            end
        end
        
        -- Store original bounds for all entities
        for _, ent in ipairs(entities) do
            self:StoreOriginalBounds(ent)
        end
        
        -- Get the bounds size from ConVar
        local boundsSize = cv_bounds_size:GetFloat()
        local mins = Vector(-boundsSize, -boundsSize, -boundsSize)
        local maxs = Vector(boundsSize, boundsSize, boundsSize)
        
        -- Use 5ms max processing time per frame for smooth performance
        local maxProcessingTimeMs = 5
        
        -- Start batch processing
        if #entities > 0 then
            local success = EntityManager.BatchProcessEntities(entities, positions, mins, maxs, maxProcessingTimeMs)
            
            if success then
                -- Set up batch processing callback
                self.batchProcessingTimer = self.batchProcessingTimer or "RTX_BatchProcessingTimer"
                
                RTXFrustumState:AddTimer(self.batchProcessingTimer, 0, 0, function()
                    if not RTXFrustumState.active then return end
                    
                    -- Process the next batch
                    local results, visibleCount, isDone = EntityManager.ProcessNextEntityBatch(250, cv_debug:GetBool())
                    
                    -- Update PVS statistics
                    RTXFrustumState.stats.entitiesInPVS = visibleCount
                    RTXFrustumState.stats.totalEntities = #entities
                    
                    -- Clear the timer if we're done
                    if isDone then
                        if timer.Exists(self.batchProcessingTimer) then
                            timer.Remove(self.batchProcessingTimer)
                        end
                        
                        self.processingInProgress = false
                        
                        -- Final timing
                        local endTime = SysTime()
                        local totalTime = (endTime - startTime) * 1000
                        
                        if cv_debug:GetBool() then
                            print(string.format("[RTX Force View Frustum] Batch processing complete: %d entities, %d in PVS (%.2f ms)",
                                #entities, visibleCount, totalTime))
                        end
                    end
                end)
            else
                -- If batch processing failed, fallback to standard mode
                self:ProcessEntitiesStandard(regularEntities, forceOriginal)
                self.processingInProgress = false
            end
        else
            -- No entities to process
            self.processingInProgress = false
        end
    else
        -- Fallback to standard processing if native batch mode not available
        local allEntities = ents.GetAll()
        self:ProcessEntitiesStandard(allEntities, forceOriginal)
        self.processingInProgress = false
    end
    
    return true
end

function RTXFrustumState.EntityManager:ProcessNextBatch(forceOriginal)
    if not self.processingInProgress then return false end
    if self.currentBatchIndex > #self.entityBatches then
        self.processingInProgress = false
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Force View Frustum] Entity processing complete: %d batches", 
                #self.entityBatches))
        end
        
        return true
    end
    
    local startTime = SysTime()
    local currentBatch = self.entityBatches[self.currentBatchIndex]
    local batchEntities = currentBatch.entities
    local batchPriority = currentBatch.priority
    
    -- Process all entities in this batch
    for _, ent in ipairs(batchEntities) do
        if IsValid(ent) then
            self:ProcessEntity(ent, forceOriginal)
        end
    end
    
    -- Measure processing time and adjust batch size if needed
    local processingTime = (SysTime() - startTime) * 1000 -- ms
    table.insert(self.frameTimeHistory, processingTime)
    if #self.frameTimeHistory > 5 then table.remove(self.frameTimeHistory, 1) end
    
    -- Adaptive batch sizing
    if self.adaptiveBatchSizing then
        -- Calculate average processing time
        local avgTime = 0
        for _, time in ipairs(self.frameTimeHistory) do
            avgTime = avgTime + time
        end
        avgTime = avgTime / #self.frameTimeHistory
        
        -- Adapt batch size based on performance
        if avgTime < self.maxProcessTimeMs * 0.5 then
            -- Processing is very fast, increase batch size
            self.batchSize = math.min(self.batchSize * 1.5, 1000)
            -- Schedule next batch immediately
            self.currentBatchIndex = self.currentBatchIndex + 1
            self:ProcessNextBatch(forceOriginal)
        elseif avgTime > self.maxProcessTimeMs then
            -- Too slow, reduce batch size for future batches
            self.batchSize = math.max(self.batchSize * 0.75, 50)
            -- Schedule next batch with a delay
            self.currentBatchIndex = self.currentBatchIndex + 1
            RTXFrustumState:AddTimer("RTX_ProcessNextBatch", 0.02, 1, function()
                self:ProcessNextBatch(forceOriginal)
            end)
        else
            -- Good performance, continue with current batch size
            self.currentBatchIndex = self.currentBatchIndex + 1
            RTXFrustumState:AddTimer("RTX_ProcessNextBatch", 0.01, 1, function()
                self:ProcessNextBatch(forceOriginal)
            end)
        end
    else
        -- Non-adaptive: just move to the next batch
        self.currentBatchIndex = self.currentBatchIndex + 1
        RTXFrustumState:AddTimer("RTX_ProcessNextBatch", 0.01, 1, function()
            self:ProcessNextBatch(forceOriginal)
        end)
    end
    
    return true
end

function RTXFrustumState.EntityManager:InitializeSpecialEntity(ent)
    if not IsValid(ent) then return false end
    
    local className = ent:GetClass()
    
    -- Check if this is a special entity with custom bounds
    local specialBounds = RTXFrustumState.LightManager:GetSpecialBounds(className)
    if specialBounds then
        -- Force store original bounds
        self:StoreOriginalBounds(ent)
        
        -- Apply special entity bounds
        self:ApplySpecialEntityBounds(ent, specialBounds)
        
        -- Force entity to be visible
        ent:SetNoDraw(false)
        
        -- If this is an always-visible entity, mark it in our special list
        if RTXFrustumState.LightManager:IsAlwaysVisibleEntity(className) then
            RTXFrustumState.alwaysVisibleEntities[ent] = true
            -- Also ensure it's always in PVS
            RTXFrustumState.entitiesInPVS[ent] = true
            
            if cv_debug:GetBool() then
                print(string.format("[RTX Force View Frustum] Added %s to always-visible entities", className))
            end
        end
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Force View Frustum] Initialized special entity: %s", className))
        end
        
        return true
    end
    
    return false
end

function RTXFrustumState.EntityManager:ProcessEntity(ent, forceOriginal)
    if not IsValid(ent) then return false end
    
    -- Get entity class name
    local className = ent:GetClass()
    
    -- First check if this is an RTX updater or special entity
    if RTXFrustumState.rtxUpdaters[ent] then
        -- Let the light manager handle it
        if forceOriginal then
            -- Restore original bounds
            RTXFrustumState.LightManager:ResetLightBounds(ent)
        else
            -- Apply RTX light bounds
            RTXFrustumState.LightManager:ApplyLightBounds(ent)
        end
        return true
    end
    
    -- Check if this is a special entity with custom bounds
    local specialBounds = RTXFrustumState.LightManager:GetSpecialBounds(className)
    if specialBounds then
        if forceOriginal then
            -- Restore original bounds
            self:ResetEntityBounds(ent)
        else
            -- Apply special entity bounds
            self:ApplySpecialEntityBounds(ent, specialBounds)
        end
        return true
    end
    
    -- Regular entity - check if we should modify it
    if not self:ShouldModifyEntityBounds(ent) then
        return false
    end
    
    -- Determine if entity is in PVS (if PVS is enabled)
    local isInPVS = true
    
    if cv_use_pvs:GetBool() and not forceOriginal then
        -- Use the optimized single-entity check if available
        if EntityManager and EntityManager.ProcessEntityPVS_Optimized then
            isInPVS = EntityManager.ProcessEntityPVS_Optimized(ent)
        else
            -- Fallback to direct position check
            local entPos = ent:GetPos()
            
            -- First check player distance as a quick acceptance test
            local playerPos = LocalPlayer():GetPos()
            if entPos:DistToSqr(playerPos) < (2048 * 2048) then
                isInPVS = true
            else
                -- Test against PVS
                isInPVS = RTXFrustumState.PVSManager:IsInPVS(entPos)
            end
        end
        
        -- Update PVS tracking
        if isInPVS then
            RTXFrustumState.entitiesInPVS[ent] = true
        else
            RTXFrustumState.entitiesInPVS[ent] = nil
        end
    end
    
    -- Apply appropriate bounds
    if forceOriginal or (cv_use_pvs:GetBool() and not isInPVS) then
        -- Reset to original bounds
        self:ResetEntityBounds(ent)
    else
        -- Apply expanded bounds
        self:ApplyExpandedBounds(ent)
    end
    
    return true
end

function RTXFrustumState.EntityManager:ShouldModifyEntityBounds(ent)
    if not IsValid(ent) then return false end
    
    -- Check entity type cache first
    if self.entityTypeCache[ent] ~= nil then
        return self.entityTypeCache[ent]
    end
    
    local className = ent:GetClass()
    local model = ent:GetModel()
    
    -- Check if this is an RTX updater
    if RTXFrustumState.rtxUpdaters[ent] or 
       RTXFrustumState.LightManager:IsSpecialEntity(className) or 
       (model and RTXFrustumState.LightManager.RTX_UPDATER_MODELS[model]) then
        self.entityTypeCache[ent] = true
        return true
    end
    
    -- Check if this is a prop and prop handling is enabled
    if className:find("prop_") and cv_props_enabled:GetBool() then
        self.entityTypeCache[ent] = true
        return true
    end
    
    -- Check if this is a special entity with custom bounds
    if RTXFrustumState.LightManager:HasSpecialBounds(className) then
        self.entityTypeCache[ent] = true
        return true
    end
    
    -- Default: don't modify this entity's bounds
    self.entityTypeCache[ent] = false
    return false
end

function RTXFrustumState.EntityManager:StoreOriginalBounds(ent)
    if not IsValid(ent) or RTXFrustumState.originalBounds[ent] then return false end
    
    local mins, maxs = ent:GetRenderBounds()
    RTXFrustumState:RegisterEntity(ent, mins, maxs)
    return true
end

function RTXFrustumState.EntityManager:ResetEntityBounds(ent)
    if not IsValid(ent) then return false end
    
    if RTXFrustumState.originalBounds[ent] then
        local bounds = RTXFrustumState.originalBounds[ent]
        ent:SetRenderBounds(bounds.mins, bounds.maxs)
        return true
    end
    
    return false
end

function RTXFrustumState.EntityManager:ApplyExpandedBounds(ent)
    if not IsValid(ent) then return false end
    
    -- Store original bounds if we haven't already
    self:StoreOriginalBounds(ent)
    
    -- Apply expanded bounds using the cached vectors
    local boundsSize = cv_bounds_size:GetFloat()
    local mins = Vector(-boundsSize, -boundsSize, -boundsSize)
    local maxs = Vector(boundsSize, boundsSize, boundsSize)
    
    ent:SetRenderBounds(mins, maxs)
    return true
end

function RTXFrustumState.EntityManager:ApplySpecialEntityBounds(ent, specialBounds)
    if not IsValid(ent) then return false end
    
    -- Store original bounds if we haven't already
    self:StoreOriginalBounds(ent)
    
    local size = specialBounds.size
    local className = ent:GetClass()
    
    -- For doors, use special calculation
    if className == "prop_door_rotating" and EntityManager and EntityManager.CalculateSpecialEntityBounds then
        EntityManager.CalculateSpecialEntityBounds(ent, size)
    else
        -- Regular special entities
        local bounds = Vector(size, size, size)
        ent:SetRenderBounds(-bounds, bounds)
    end
    
    -- Debug output if enabled
    if cv_debug:GetBool() then
        local patternText = specialBounds.isPattern and " (via pattern)" or ""
        print(string.format("[RTX Force View Frustum] Special entity bounds applied (%s): %d%s", 
            className, size, patternText))
    end
    
    return true
end

-- ==========================================================================
-- LIGHT MANAGEMENT SYSTEM
-- ==========================================================================
RTXFrustumState.LightManager = {
    detectionPhases = {1, 3, 7},  -- Seconds after map load for scans
    currentPhase = 0,
    isScanning = false,
    
    -- RTX Light Updater model list
    RTX_UPDATER_MODELS = {
        ["models/hunter/plates/plate.mdl"] = true,
        ["models/hunter/blocks/cube025x025x025.mdl"] = true
    },
    
    -- Special entities that receive special handling
    SPECIAL_ENTITIES = {
        ["rtx_lightupdater"] = true,
        ["rtx_lightupdatermanager"] = true
    },
    
    LIGHT_TYPES = {
        POINT = "light",
        SPOT = "light_spot",
        DYNAMIC = "light_dynamic",
        ENVIRONMENT = "light_environment",
        DIRECTIONAL = "light_directional"
    },
    
    -- Special entities with custom bounds
    SPECIAL_ENTITY_BOUNDS = {
        ["prop_door_rotating"] = {
            size = 512,
            description = "Door entities",
            isPattern = false,
        },
    
        ["func_door_rotating"] = {
            size = 512,
            description = "func_ entities",
            isPattern = false,
        },

        ["gmod_lamp"] = {
            size = 512,
            description = "Lamps",
            isPattern = false,
        },
    
        ["^npc_%w+"] = {
            size = 512,
            description = "All npc_ entities",
            isPattern = true,
        },
    
        ["hdri_cube_editor"] = {
            size = 512,
            description = "HDRI Editor",
            isPattern = false,
        }
    },
    
    -- Pattern cache
    patternCache = {}
}

function RTXFrustumState.LightManager:Initialize()
    -- Initialize pattern cache
    self.patternCache = {}
    
    -- Create a weak reference table for the pattern cache
    setmetatable(self.patternCache, {__mode = "kv"})
    
    -- Initialize scan phase
    self.currentPhase = 0
    self.isScanning = false
    
    -- Regular lights get REGULAR_LIGHT_TYPES
    self.REGULAR_LIGHT_TYPES = {
        [self.LIGHT_TYPES.POINT] = true,
        [self.LIGHT_TYPES.SPOT] = true,
        [self.LIGHT_TYPES.DYNAMIC] = true,
        [self.LIGHT_TYPES.DIRECTIONAL] = true
    }
    
    return true
end

function RTXFrustumState.LightManager:IsAlwaysVisibleEntity(className)
    -- List of entity classes that should always be visible
    local alwaysVisibleClasses = {
        ["hdri_cube_editor"] = true,
        -- Add other entity classes that should never be hidden
    }
    
    return alwaysVisibleClasses[className] or false
end

function RTXFrustumState.LightManager:ScanForLights()
    if not RTXFrustumState.active then return 0 end
    
    -- Mark that we're scanning
    self.isScanning = true
    self.currentPhase = 1
    
    -- Initial immediate scan
    local initialLights = self:DetectLights()
    
    -- Schedule additional scans with increasing delays
    for i, delay in ipairs(self.detectionPhases) do
        RTXFrustumState:AddTimer("RTX_LightDetection_Phase" .. i, delay, 1, function()
            self:DetectLights(i + 1)
            
            -- If this is the last scheduled scan, mark scanning as complete
            if i == #self.detectionPhases then
                self.isScanning = false
            end
        end)
    end
    
    return initialLights
end

function RTXFrustumState.LightManager:DetectLights(phase)
    local startTime = SysTime()
    local newLightsFound = 0
    local totalEntities = 0
    phase = phase or 0
    
    -- Check ALL entities on the map
    for _, ent in ipairs(ents.GetAll()) do
        totalEntities = totalEntities + 1
        
        if IsValid(ent) and not RTXFrustumState.rtxUpdaters[ent] then
            local className = ent:GetClass()
            local model = ent:GetModel()
            
            -- Check if it's a light entity we missed
            if self.SPECIAL_ENTITIES[className] or 
               (model and self.RTX_UPDATER_MODELS[model]) or
               string.find(className or "", "light") or
               ent.lightType then
                
                -- Set up the light entity
                self:SetupLightEntity(ent)
                newLightsFound = newLightsFound + 1
            end
        end
    end
    
    local endTime = SysTime()
    
    if cv_debug:GetBool() or newLightsFound > 0 then
        print(string.format("[RTX Force View Frustum] Light scan phase %d: Found %d new lights out of %d entities (%.2f ms)",
            phase, newLightsFound, totalEntities, (endTime - startTime) * 1000))
    end
    
    return newLightsFound
end

function RTXFrustumState.LightManager:SetupLightEntity(ent)
    if not IsValid(ent) then return false end
    
    -- Store original bounds first
    RTXFrustumState.EntityManager:StoreOriginalBounds(ent)
    
    -- Add to our cache
    RTXFrustumState.rtxUpdaters[ent] = true
    
    -- Apply appropriate bounds based on light type
    self:ApplyLightBounds(ent)
    
    -- Force visibility settings
    ent:DisableMatrix("RenderMultiply")
    ent:SetNoDraw(false)
    
    return true
end

function RTXFrustumState.LightManager:ApplyLightBounds(ent)
    if not IsValid(ent) then return false end
    
    if ent.lightType == self.LIGHT_TYPES.ENVIRONMENT then
        -- Use environment light distance for environment lights
        local envSize = cv_environment_light_distance:GetFloat()
        local envBounds = Vector(envSize, envSize, envSize)
        ent:SetRenderBounds(-envBounds, envBounds)
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Force View Frustum] Environment light bounds: %d", envSize))
        end
    else
        -- Use regular light distance for all other lights
        local rtxDistance = cv_rtx_updater_distance:GetFloat()
        local rtxBounds = Vector(rtxDistance, rtxDistance, rtxDistance)
        ent:SetRenderBounds(-rtxBounds, rtxBounds)
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Force View Frustum] Regular light bounds (%s): %d", 
                ent.lightType or "unknown", rtxDistance))
        end
    end
    
    return true
end

function RTXFrustumState.LightManager:ResetLightBounds(ent)
    if not IsValid(ent) then return false end
    
    -- Reset to original bounds if we have them
    return RTXFrustumState.EntityManager:ResetEntityBounds(ent)
end

function RTXFrustumState.LightManager:IsSpecialEntity(className)
    return self.SPECIAL_ENTITIES[className] or false
end

function RTXFrustumState.LightManager:HasSpecialBounds(className)
    -- First try direct lookup (fastest)
    if self.SPECIAL_ENTITY_BOUNDS[className] then
        return true
    end
    
    -- Check cache for previous pattern match
    if self.patternCache[className] then
        return true
    end
    
    -- Try pattern matching
    for pattern, boundsInfo in pairs(self.SPECIAL_ENTITY_BOUNDS) do
        if boundsInfo.isPattern and string.match(className, pattern) then
            -- Cache the result for future lookups
            self.patternCache[className] = boundsInfo
            return true
        end
    end
    
    -- No match found
    return false
end

function RTXFrustumState.LightManager:GetSpecialBounds(className)
    -- First try direct lookup (fastest)
    local directMatch = self.SPECIAL_ENTITY_BOUNDS[className]
    if directMatch then
        return directMatch
    end
    
    -- Check cache for previous pattern match
    if self.patternCache[className] then
        return self.patternCache[className]
    end
    
    -- Try pattern matching
    for pattern, boundsInfo in pairs(self.SPECIAL_ENTITY_BOUNDS) do
        if boundsInfo.isPattern and string.match(className, pattern) then
            -- Cache the result for future lookups
            self.patternCache[className] = boundsInfo
            return boundsInfo
        end
    end
    
    -- No match found
    return nil
end

function RTXFrustumState.LightManager:AddSpecialEntityBounds(class, size, description, isPattern)
    if not class or not size then return false end
    
    self.SPECIAL_ENTITY_BOUNDS[class] = {
        size = size,
        description = description or class,
        isPattern = isPattern or false
    }
    
    -- Clear pattern cache to ensure new patterns are recognized
    self.patternCache = {}
    setmetatable(self.patternCache, {__mode = "kv"})
    
    -- Update existing entities of this class if the optimization is enabled
    if RTXFrustumState.active and cv_enabled:GetBool() then
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) then
                RTXFrustumState.EntityManager:ProcessEntity(ent, false)
            end
        end
    end
    
    return true
end

-- ==========================================================================
-- STATIC PROP MANAGER
-- ==========================================================================
RTXFrustumState.StaticPropManager = {
    batchSize = 50,         -- How many props to process in a batch
    maxDistance = 16384,    -- Maximum distance to create props
    inProgress = false,     -- Is creation/update in progress
    currentBatch = 0,       -- Current batch being processed
    totalBatches = 0,       -- Total number of batches
    propData = {}           -- Cached prop data from NikNaks
}

function RTXFrustumState.StaticPropManager:Initialize()
    self.inProgress = false
    self.currentBatch = 0
    self.totalBatches = 0
    self.propData = {}
    
    return true
end

function RTXFrustumState.StaticPropManager:CreateAll()
    -- Clean up existing props
    RTXFrustumState:RemoveAllStaticProps()
    
    -- Skip if disabled or dependencies missing
    if not (cv_enabled:GetBool() and NikNaks and NikNaks.CurrentMap) then 
        return false
    end
    
    -- Store original ConVar value
    RTXFrustumState.originalSettings.staticPropSetting = GetConVar("r_drawstaticprops"):GetInt()
    
    -- Get prop data from NikNaks
    local props = NikNaks.CurrentMap:GetStaticProps()
    self.propData = props
    
    local totalProps = #props
    self.totalBatches = math.ceil(totalProps / self.batchSize)
    self.currentBatch = 1
    self.inProgress = true
    
    -- Start batch processing
    self:ProcessCreationBatch(1)
    
    return true
end

function RTXFrustumState.StaticPropManager:ProcessCreationBatch(batchNum)
    if not self.inProgress then return false end
    
    local props = self.propData
    local startIndex = (batchNum - 1) * self.batchSize + 1
    local endIndex = math.min(batchNum * self.batchSize, #props)
    
    local playerPos = LocalPlayer():GetPos()
    local maxDistSqr = self.maxDistance * self.maxDistance
    local propsCreated = 0
    
    for i = startIndex, endIndex do
        local propData = props[i]
        if propData then
            local propPos = propData:GetPos()
            if propPos:DistToSqr(playerPos) <= maxDistSqr then
                -- Stagger individual prop creation to reduce stuttering
                timer.Simple((i - startIndex) * 0.01, function()
                    local prop = ClientsideModel(propData:GetModel())
                    if IsValid(prop) then
                        prop:SetPos(propPos)
                        prop:SetAngles(propData:GetAngles())
                        
                        -- Check if in PVS and set bounds accordingly
                        local inPVS = not cv_static_props_pvs:GetBool() or 
                                     (RTXFrustumState.PVSManager.current and RTXFrustumState.PVSManager:IsInPVS(propPos))
                        
                        self:UpdatePropBounds(prop, inPVS)
                        
                        prop:SetColor(propData:GetColor())
                        prop:SetSkin(propData:GetSkin())
                        local scale = propData:GetScale()
                        if scale != 1 then
                            prop:SetModelScale(scale)
                        end
                        
                        -- Register with state tracker
                        RTXFrustumState.staticProps[prop] = {
                            pos = propPos,
                            inPVS = inPVS
                        }
                        
                        propsCreated = propsCreated + 1
                    end
                end)
            end
        end
    end
    
    -- Process next batch if there are more
    if batchNum < self.totalBatches then
        RTXFrustumState:AddTimer("RTX_ProcessStaticPropBatch" .. batchNum, 0.5, 1, function() 
            self:ProcessCreationBatch(batchNum + 1) 
        end)
    else
        self.inProgress = false
        
        -- Update statistics
        RTXFrustumState.stats.staticPropsTotal = 0
        RTXFrustumState.stats.staticPropsInPVS = 0
        
        for prop, data in pairs(RTXFrustumState.staticProps) do
            if IsValid(prop) then
                RTXFrustumState.stats.staticPropsTotal = RTXFrustumState.stats.staticPropsTotal + 1
                if data.inPVS then
                    RTXFrustumState.stats.staticPropsInPVS = RTXFrustumState.stats.staticPropsInPVS + 1
                end
            end
        end
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Force View Frustum] Created %d static props", 
                RTXFrustumState.stats.staticPropsTotal))
        end
    end
    
    return true
end

function RTXFrustumState.StaticPropManager:UpdatePropBounds(prop, inPVS)
    if not IsValid(prop) then return false end
    
    local boundsSize = cv_bounds_size:GetFloat()
    
    if inPVS then
        -- In PVS: use large bounds for RTX lighting
        local bounds = Vector(boundsSize, boundsSize, boundsSize)
        prop:SetRenderBounds(-bounds, bounds)
        prop:SetNoDraw(false)
    else
        -- Out of PVS: use small bounds for performance
        local smallBounds = Vector(1, 1, 1)
        prop:SetRenderBounds(-smallBounds, smallBounds)
        -- Alternative: prop:SetNoDraw(true) for maximum performance
    end
    
    return true
end

function RTXFrustumState.StaticPropManager:UpdateAllProps()
    if not RTXFrustumState.active or not cv_static_props_pvs:GetBool() then return false end
    
    -- Exit early if no static props
    local propCount = table.Count(RTXFrustumState.staticProps)
    if propCount == 0 then 
        RTXFrustumState.stats.staticPropsInPVS = 0
        RTXFrustumState.stats.staticPropsTotal = 0
        return false
    end
    
    -- Create arrays for batch processing
    local propEntities = {}
    local propPositions = {}
    
    for prop, data in pairs(RTXFrustumState.staticProps) do
        if IsValid(prop) then
            table.insert(propEntities, prop)
            table.insert(propPositions, data.pos)
        end
    end
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Force View Frustum] Processing %d static props for PVS", #propEntities))
    end
    
    -- Get player position for distance checks
    local playerPos = LocalPlayer():GetPos()
    local closeDistanceSqr = 2048 * 2048 -- More generous distance threshold
    local updateCount = 0
    local inPVSCount = 0
    
    -- Use BatchTestPVSVisibility_Native if available for better performance
    if EntityManager and EntityManager.BatchTestPVSVisibility_Native and #propEntities > 0 then
        -- Get current PVS leaf positions
        local leafPositions = {}
        if RTXFrustumState.PVSManager.leafPositions then
            leafPositions = RTXFrustumState.PVSManager.leafPositions
        end
        
        -- Process close props first for immediate visual feedback
        for i, prop in ipairs(propEntities) do
            local pos = propPositions[i]
            -- Auto-include props very close to player 
            if pos:DistToSqr(playerPos) < closeDistanceSqr then
                if IsValid(prop) and RTXFrustumState.staticProps[prop] then
                    if not RTXFrustumState.staticProps[prop].inPVS then
                        self:UpdatePropBounds(prop, true)
                        RTXFrustumState.staticProps[prop].inPVS = true
                        updateCount = updateCount + 1
                    end
                    inPVSCount = inPVSCount + 1
                end
                
                -- Mark as already processed
                propEntities[i] = nil
                propPositions[i] = nil
            end
        end
        
        -- Compact arrays
        local compactEntities = {}
        local compactPositions = {}
        for i, prop in ipairs(propEntities) do
            if prop then
                table.insert(compactEntities, prop)
                table.insert(compactPositions, propPositions[i])
            end
        end
        
        -- Do batch PVS testing for remaining props
        if #compactPositions > 0 then
            local results, visibleCount = EntityManager.BatchTestPVSVisibility_Native(compactPositions, leafPositions)
            
            -- Apply the results
            for i, isInPVS in ipairs(results) do
                local prop = compactEntities[i]
                if IsValid(prop) and RTXFrustumState.staticProps[prop] then
                    if isInPVS then inPVSCount = inPVSCount + 1 end
                    
                    if isInPVS ~= RTXFrustumState.staticProps[prop].inPVS then
                        self:UpdatePropBounds(prop, isInPVS)
                        RTXFrustumState.staticProps[prop].inPVS = isInPVS
                        updateCount = updateCount + 1
                    end
                end
            end
        end
    else
        -- Fallback to the original Lua implementation if module fails
        for i, prop in ipairs(propEntities) do
            local pos = propPositions[i]
            -- First check distance - anything close to player is automatically in PVS
            local inPVS = pos:DistToSqr(playerPos) < closeDistanceSqr
            
            -- If not close, try using PVS system
            if not inPVS and RTXFrustumState.PVSManager.current then
                inPVS = RTXFrustumState.PVSManager:IsInPVS(pos)
            end
            
            if IsValid(prop) and RTXFrustumState.staticProps[prop] then
                if inPVS then inPVSCount = inPVSCount + 1 end
                
                if inPVS ~= RTXFrustumState.staticProps[prop].inPVS then
                    self:UpdatePropBounds(prop, inPVS)
                    RTXFrustumState.staticProps[prop].inPVS = inPVS
                    updateCount = updateCount + 1
                end
            end
        end
    end
    
    -- Update statistics
    RTXFrustumState.stats.staticPropsTotal = #propEntities
    RTXFrustumState.stats.staticPropsInPVS = inPVSCount
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Force View Frustum] Static prop PVS update complete: %d props, %d in PVS, %d changed",
            RTXFrustumState.stats.staticPropsTotal,
            RTXFrustumState.stats.staticPropsInPVS,
            updateCount))
    end
    
    return true
end

-- ==========================================================================
-- UTILITY FUNCTIONS
-- ==========================================================================
-- Cache variables and settings
local boundsSize = cv_bounds_size:GetFloat()
local mins = Vector(-boundsSize, -boundsSize, -boundsSize)
local maxs = Vector(boundsSize, boundsSize, boundsSize)
local lastTrackedPosition = Vector(0,0,0)
local positionUpdateThreshold = 128  -- Units player must move to trigger update
local DEBOUNCE_TIME = 0.1
local boundsUpdateTimer = "FR_BoundsUpdate"

-- Map presets storage
local MAP_PRESETS = {}

-- Presets for quality settings
local PRESETS = {
    ["Very Low"] = { entity = 64, light = 256, environment = 32768 },
    ["Low"] = { entity = 256, light = 512, environment = 32768 },
    ["Medium"] = { entity = 512, light = 767, environment = 32768 },
    ["High"] = { entity = 2048, light = 1024, environment = 32768 },
    ["Very High"] = { entity = 4096, light = 2048, environment = 65536 }
}

-- Helper function for safe function calls
function SafeCall(funcName, func, ...)
    if not func then
        if cv_debug:GetBool() then
            print("[RTX Force View Frustum] Error: Function '" .. funcName .. "' not available")
        end
        return nil
    end
    
    local success, result = pcall(func, ...)
    if not success then
        if cv_debug:GetBool() then
            print("[RTX Force View Frustum] Error in '" .. funcName .. "': " .. tostring(result))
        end
        return nil
    end
    
    return result
end

-- Save/load functions for map presets
local function SaveMapPresets()
    file.Write("rtx_frustum_map_presets.json", util.TableToJSON(MAP_PRESETS))
end

local function LoadMapPresets()
    if file.Exists("rtx_frustum_map_presets.json", "DATA") then
        MAP_PRESETS = util.JSONToTable(file.Read("rtx_frustum_map_presets.json", "DATA")) or {}
    end
end

local function ApplyPreset(presetName)
    -- If this is a map name and we have a custom preset for it
    if type(MAP_PRESETS[presetName]) == "table" and MAP_PRESETS[presetName].type == "custom" then
        local customSettings = MAP_PRESETS[presetName]
        RunConsoleCommand("rtx_fr_bounds_size", tostring(customSettings.entity))
        RunConsoleCommand("rtx_fr_rtx_distance", tostring(customSettings.light))
        RunConsoleCommand("rtx_fr_environment_light_distance", tostring(customSettings.environment))
        return
    end
    
    -- Default to "Low" if no preset specified
    presetName = presetName or "Low"
    
    local preset = PRESETS[presetName]
    if not preset then return end
    
    RunConsoleCommand("rtx_fr_bounds_size", tostring(preset.entity))
    RunConsoleCommand("rtx_fr_rtx_distance", tostring(preset.light))
    RunConsoleCommand("rtx_fr_environment_light_distance", tostring(preset.environment))
end

function UpdateBoundsVectors(size)
    boundsSize = size
    mins = Vector(-size, -size, -size)
    maxs = Vector(size, size, size)
end

function ResetAndUpdateBounds(preserveOriginals)
    -- Stop any ongoing processing
    RTXFrustumState.processingUpdate = true
    
    -- Cancel any pending update timers
    RTXFrustumState:RemoveAllTimers()
    
    -- First restore all original bounds to prevent leaks
    RTXFrustumState:ResetAllEntityBounds()
    
    -- Clear caches while preserving tables
    if not preserveOriginals then
        for k in pairs(RTXFrustumState.originalBounds) do RTXFrustumState.originalBounds[k] = nil end
        for k in pairs(RTXFrustumState.entitiesToReset) do RTXFrustumState.entitiesToReset[k] = nil end
    end
    for k in pairs(RTXFrustumState.entitiesInPVS) do RTXFrustumState.entitiesInPVS[k] = nil end
    
    -- Update cached vectors for new bounds size
    boundsSize = cv_bounds_size:GetFloat()
    mins = Vector(-boundsSize, -boundsSize, -boundsSize)
    maxs = Vector(boundsSize, boundsSize, boundsSize)
    
    -- Reset PVS data
    RTXFrustumState.PVSManager.current = nil
    RTXFrustumState.PVSManager.lastUpdateTime = 0
    RTXFrustumState.PVSManager.updateInProgress = false
    
    -- If system is active, update all bounds
    if RTXFrustumState.active then
        -- Process all entities with the new bounds
        RTXFrustumState.EntityManager:ProcessAllEntities(false)
        
        -- Recreate static props if needed
        RTXFrustumState.StaticPropManager:CreateAll()
    end
    
    -- Allow processing again
    RTXFrustumState.processingUpdate = false
    
    if cv_debug:GetBool() then
        print("[RTX Force View Frustum] Reset and updated all entity bounds with new settings")
    end
end

-- ==========================================================================
-- HOOK SYSTEM
-- ==========================================================================

-- Hook: Initialize
RTXFrustumState:AddHook("Initialize", "LoadRTXFrustumMapPresets", LoadMapPresets)

-- Hook: InitPostEntity
RTXFrustumState:AddHook("InitPostEntity", "ApplyMapRTXPreset", function()
    timer.Simple(1, function()
        local currentMap = game.GetMap()
        if MAP_PRESETS[currentMap] then
            -- Check if it's a custom preset (table) or predefined (string)
            if type(MAP_PRESETS[currentMap]) == "table" and MAP_PRESETS[currentMap].type == "custom" then
                local customSettings = MAP_PRESETS[currentMap]
                RunConsoleCommand("rtx_fr_bounds_size", tostring(customSettings.entity))
                RunConsoleCommand("rtx_fr_rtx_distance", tostring(customSettings.light))
                RunConsoleCommand("rtx_fr_environment_light_distance", tostring(customSettings.environment))
            else
                -- It's a predefined preset
                ApplyPreset(MAP_PRESETS[currentMap])
            end
        else
            -- Default to Low preset for maps without configuration
            ApplyPreset("Low")
        end
    end)
end)

-- Hook: OnEntityCreated
RTXFrustumState:AddHook("OnEntityCreated", "SetLargeRenderBounds", function(ent)
    if not RTXFrustumState.active or not IsValid(ent) then return end
    
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        
        local className = ent:GetClass()
        
        -- First check if this is a special entity, and handle immediately
        if RTXFrustumState.LightManager:HasSpecialBounds(className) then
            RTXFrustumState.EntityManager:InitializeSpecialEntity(ent)
            
            -- Force immediate visibility
            ent:SetNoDraw(false)
            
            -- Mark as in PVS
            RTXFrustumState.entitiesInPVS[ent] = true
            
            -- Add to type cache
            RTXFrustumState.EntityManager.entityTypeCache[ent] = true
            
            if cv_debug:GetBool() then
                print(string.format("[RTX Force View Frustum] Special entity initialized early: %s", className))
            end
            
            return
        end
        
        -- Check if this is an RTX light
        if RTXFrustumState.LightManager.SPECIAL_ENTITIES[className] or
           (ent:GetModel() and RTXFrustumState.LightManager.RTX_UPDATER_MODELS[ent:GetModel()]) or
           string.find(className or "", "light") or
           ent.lightType then
            
            RTXFrustumState.LightManager:SetupLightEntity(ent)
            RTXFrustumState.EntityManager.entityTypeCache[ent] = true
        else
            -- Regular entity processing
            RTXFrustumState.EntityManager:ProcessEntity(ent, not cv_enabled:GetBool())
        end
    end)
end)

-- Hook: InitPostEntity - Initial setup
RTXFrustumState:AddHook("InitPostEntity", "InitialBoundsSetup", function()
    timer.Simple(1, function()
        RTXFrustumState:ActivateSystem()
    end)
end)

-- Hook: Think - PVS movement tracking
RTXFrustumState:AddHook("Think", "RTX_PVS_MovementTracking", function()
    if not RTXFrustumState.active then return end
    
    -- If we're using async processing, check its status
    if EntityManager and EntityManager.IsAsyncPVSComplete and 
       cv_use_pvs:GetBool() and EntityManager.IsAsyncProcessingInProgress then
        
        -- Check if async processing has completed
        if EntityManager.IsAsyncPVSComplete() and RTXFrustumState.asyncPVSPending then
            -- Process entities with the newly updated PVS data
            RTXFrustumState.EntityManager:ProcessAllEntities(false)
            
            -- Update static props if enabled
            if cv_static_props_pvs:GetBool() then
                RTXFrustumState.StaticPropManager:UpdateAllProps()
            end
            
            -- Reset pending flag
            RTXFrustumState.asyncPVSPending = false
            
            if cv_debug:GetBool() then
                print("[RTX Force View Frustum] Async PVS update completed")
            end
        end
    end
    
    -- Check if player moved enough to update PVS
    if RTXFrustumState.PVSManager:ShouldUpdateForMovement() then
        if cv_debug:GetBool() then
            local moveDistance = LocalPlayer():GetPos():Distance(RTXFrustumState.PVSManager.lastPlayerPos)
            print(string.format("[RTX Force View Frustum] Player moved %.1f units - forcing PVS update", moveDistance))
        end
        
        -- Request a fresh PVS update
        RTXFrustumState.PVSManager:RequestUpdate(true)
        
        -- Mark that we have a pending async update
        if EntityManager and EntityManager.IsAsyncProcessingInProgress then
            RTXFrustumState.asyncPVSPending = true
        end
        
        -- Force immediate update of static props when player moves significantly
        if cv_static_props_pvs:GetBool() then
            timer.Simple(0.05, function() 
                RTXFrustumState.StaticPropManager:UpdateAllProps()
            end)
        end
    end
    
    -- Regular interval PVS updates
    local currentTime = CurTime()
    local updateInterval = cv_pvs_update_interval:GetFloat()
    
    if RTXFrustumState.active and cv_use_pvs:GetBool() and 
       (currentTime - RTXFrustumState.PVSManager.lastUpdateTime > updateInterval) then
        RTXFrustumState.PVSManager:RequestUpdate(false)
        
        -- Mark that we have a pending async update
        if EntityManager and EntityManager.IsAsyncProcessingInProgress then
            RTXFrustumState.asyncPVSPending = true
        end
    end
end)

-- Hook: OnReloaded - Map cleanup/reload handler
RTXFrustumState:AddHook("OnReloaded", "RefreshStaticProps", function()
    -- Clear bounds cache
    for k in pairs(RTXFrustumState.originalBounds) do RTXFrustumState.originalBounds[k] = nil end
    for k in pairs(RTXFrustumState.entitiesToReset) do RTXFrustumState.entitiesToReset[k] = nil end
    
    -- Reset PVS cache
    RTXFrustumState.PVSManager.current = nil
    RTXFrustumState.PVSManager.lastUpdateTime = 0
    
    -- Remove existing static props
    RTXFrustumState:RemoveAllStaticProps()
    
    -- Recreate if enabled
    if cv_enabled:GetBool() then
        timer.Simple(1, function() 
            RTXFrustumState.StaticPropManager:CreateAll()
        end)
    end
end)

-- Hook: OnMapChange
RTXFrustumState:AddHook("OnMapChange", "ClearRTXPVSCache", function()
    RTXFrustumState.PVSManager.current = nil
    RTXFrustumState.PVSManager.lastUpdateTime = 0
end)

-- Hook: Think - Frame time tracking
RTXFrustumState:AddHook("Think", "RTXPVSFrameTimeTracker", function()
    if cv_pvs_hud:GetBool() then
        local frameTime = FrameTime() * 1000 -- Convert to ms
        
        -- Track in history for moving average
        table.insert(RTXFrustumState.stats.frameTimeHistory, frameTime)
        if #RTXFrustumState.stats.frameTimeHistory > 60 then -- Keep last 60 frames
            table.remove(RTXFrustumState.stats.frameTimeHistory, 1)
        end
        
        -- Calculate average
        local sum = 0
        for _, time in ipairs(RTXFrustumState.stats.frameTimeHistory) do
            sum = sum + time
        end
        RTXFrustumState.stats.frameTimeAvg = sum / #RTXFrustumState.stats.frameTimeHistory
        
        RTXFrustumState.stats.frameTime = frameTime
    end
end)

-- Hook: HUDPaint - Debug HUD
RTXFrustumState:AddHook("HUDPaint", "RTXPVSDebugHUD", function()
    if not cv_pvs_hud:GetBool() then return end
    
    local player = LocalPlayer()
    if not IsValid(player) then return end
    
    local textColor = Color(255, 255, 255, 220)
    local bgColor = Color(0, 0, 0, 150)
    local headerColor = Color(100, 200, 255, 220)
    local goodColor = Color(100, 255, 100, 220)
    local badColor = Color(255, 100, 100, 220)
    
    -- Get current leaf if available
    local currentLeaf = "Unknown"
    if NikNaks and NikNaks.CurrentMap then
        local leaf = NikNaks.CurrentMap:PointInLeaf(0, player:GetPos())
        if leaf then
            currentLeaf = leaf:GetIndex()
        end
    end
    
    -- Create info text
    local infoLines = {
        {text = "PVS Statistics", color = headerColor},
        {text = "PVS: " .. (cv_use_pvs:GetBool() and "Enabled" or "Disabled"), 
         color = cv_use_pvs:GetBool() and goodColor or badColor},
        {text = string.format("Entities in PVS: %d / %d (%.1f%%)", 
            RTXFrustumState.stats.entitiesInPVS, RTXFrustumState.stats.totalEntities, 
            RTXFrustumState.stats.totalEntities > 0 and (RTXFrustumState.stats.entitiesInPVS / RTXFrustumState.stats.totalEntities * 100) or 0)},
        {text = string.format("Leafs in PVS: %d / %d (%.1f%%)", 
            RTXFrustumState.stats.pvsLeafCount, RTXFrustumState.stats.totalLeafCount,
            RTXFrustumState.stats.totalLeafCount > 0 and (RTXFrustumState.stats.pvsLeafCount / RTXFrustumState.stats.totalLeafCount * 100) or 0)},
        {text = string.format("Current leaf: %s", currentLeaf)},
        {text = string.format("Frame time: %.2f ms (avg: %.2f ms)", RTXFrustumState.stats.frameTime, RTXFrustumState.stats.frameTimeAvg),
         color = RTXFrustumState.stats.frameTimeAvg < 16.67 and goodColor or badColor}, -- 60fps threshold
        {text = string.format("PVS update time: %.2f ms", RTXFrustumState.stats.updateTime * 1000)},
        {text = string.format("Last update: %.1f sec ago", CurTime() - RTXFrustumState.PVSManager.lastUpdateTime)},
        {text = string.format("Static Props in PVS: %d / %d (%.1f%%)", 
            RTXFrustumState.stats.staticPropsInPVS, RTXFrustumState.stats.staticPropsTotal, 
            RTXFrustumState.stats.staticPropsTotal > 0 and (RTXFrustumState.stats.staticPropsInPVS / RTXFrustumState.stats.staticPropsTotal * 100) or 0),
         color = cv_static_props_pvs:GetBool() and textColor or Color(150, 150, 150, 220)},
        {text = string.format("Position: %.1f, %.1f, %.1f", 
            player:GetPos().x, player:GetPos().y, player:GetPos().z)}
    }
    
    -- Calculate panel size
    local margin = 10
    local lineHeight = 20
    local panelWidth = 350
    local panelHeight = (#infoLines * lineHeight) + (margin * 2)
    
    -- Draw background
    draw.RoundedBox(4, 10, 10, panelWidth, panelHeight, bgColor)
    
    -- Draw text
    for i, line in ipairs(infoLines) do
        draw.SimpleText(
            line.text, 
            "DermaDefault", 
            20, 
            10 + margin + ((i-1) * lineHeight), 
            line.color or textColor, 
            TEXT_ALIGN_LEFT, 
            TEXT_ALIGN_CENTER
        )
    end
end)

-- Hook: EntityRemoved - Entity cleanup
RTXFrustumState:AddHook("EntityRemoved", "CleanupRTXCache", function(ent)
    if not IsValid(ent) then return end
    
    RTXFrustumState.rtxUpdaters[ent] = nil
    RTXFrustumState.originalBounds[ent] = nil
    RTXFrustumState.entitiesToReset[ent] = nil
    RTXFrustumState.entitiesInPVS[ent] = nil
    RTXFrustumState.EntityManager.entityTypeCache[ent] = nil
end)

-- ==========================================================================
-- CONSOLE COMMANDS
-- ==========================================================================

-- Debug command
concommand.Add("rtx_fr_debug", function()
    print("\nRTX Force View Frustum Debug:")
    print("Enabled:", cv_enabled:GetBool())
    print("Bounds Size:", cv_bounds_size:GetFloat())
    print("RTX Updater Distance:", cv_rtx_updater_distance:GetFloat())
    print("Static Props Count:", table.Count(RTXFrustumState.staticProps))
    print("Stored Original Bounds:", table.Count(RTXFrustumState.originalBounds))
    print("RTX Updaters (Cached):", table.Count(RTXFrustumState.rtxUpdaters))
    
    -- Special entities debug info
    print("\nSpecial Entity Classes:")
    for class, data in pairs(RTXFrustumState.LightManager.SPECIAL_ENTITY_BOUNDS) do
        print(string.format("  %s: %d units (%s)", 
            class, 
            data.size, 
            data.description))
    end
end)

-- ConCommand to refresh all entities' bounds
concommand.Add("rtx_fr_refresh", function()
    ResetAndUpdateBounds(true)
    print("Refreshed render bounds for all entities" .. (RTXFrustumState.active and " with large bounds" or " with original bounds"))
end)

-- ConCommand to reset everything and restore original entity bounds
concommand.Add("rtx_fr_reset_bounds", function()
    print("[RTX Force View Frustum] Performing complete bounds reset...")
    
    -- First restore original bounds for everything
    RTXFrustumState.EntityManager:ProcessAllEntities(true)
    
    -- Clear all tracking
    for k in pairs(RTXFrustumState.entitiesInPVS) do RTXFrustumState.entitiesInPVS[k] = nil end
    RTXFrustumState.PVSManager.current = nil
    RTXFrustumState.PVSManager.lastUpdateTime = 0
    
    -- Then if enabled, reapply based on current settings
    if RTXFrustumState.active then
        -- Update PVS if using PVS optimization
        if cv_use_pvs:GetBool() then
            RTXFrustumState.PVSManager:RequestUpdate(true)
        else
            -- Apply new bounds
            RTXFrustumState.EntityManager:ProcessAllEntities(false)
        end
    end
    
    print("[RTX Force View Frustum] Bounds reset complete")
end)

concommand.Add("rtx_fr_update_entity", function(ply, cmd, args)
    local className = args[1]
    if not className then
        print("[RTX Force View Frustum] Usage: rtx_fr_update_entity <entity_class>")
        return
    end
    
    local count = 0
    for _, ent in ipairs(ents.FindByClass(className)) do
        if IsValid(ent) then
            -- Force initialize the entity
            if RTXFrustumState.LightManager:HasSpecialBounds(className) then
                RTXFrustumState.EntityManager:InitializeSpecialEntity(ent)
            else
                RTXFrustumState.EntityManager:ProcessEntity(ent, false)
            end
            
            -- Force visibility
            ent:SetNoDraw(false)
            RTXFrustumState.entitiesInPVS[ent] = true
            
            count = count + 1
        end
    end
    
    print(string.format("[RTX Force View Frustum] Updated %d entities of class %s", count, className))
end)

-- Force a complete system reset
concommand.Add("rtx_fr_full_reset", function()
    print("[RTX Force View Frustum] Performing full system reset...")
    
    -- Deactivate the system completely
    local result = RTXFrustumState:DeactivateSystem()
    
    -- Force garbage collection
    collectgarbage("collect")
    
    -- If the system was previously enabled, re-enable it
    local wasEnabled = cv_enabled:GetBool()
    if wasEnabled then
        timer.Simple(0.5, function()
            -- Re-activate the system with fresh state
            RTXFrustumState:ActivateSystem()
            
            print("[RTX Force View Frustum] System re-initialized after full reset")
        end)
    end
    
    print(string.format("[RTX Force View Frustum] Full reset complete: %d entities reset, %d props removed", 
        result.entitiesReset, result.propsRemoved))
end)

-- ConCommand to detect memory leaks
concommand.Add("rtx_fr_memory_check", function()
    print("[RTX Force View Frustum] Memory usage report:")
    print("RTXFrustumState.originalBounds:", table.Count(RTXFrustumState.originalBounds))
    print("RTXFrustumState.entitiesToReset:", table.Count(RTXFrustumState.entitiesToReset))
    print("RTXFrustumState.rtxUpdaters:", table.Count(RTXFrustumState.rtxUpdaters))
    print("RTXFrustumState.entitiesInPVS:", table.Count(RTXFrustumState.entitiesInPVS))
    print("RTXFrustumState.staticProps:", table.Count(RTXFrustumState.staticProps))
    print("RTXFrustumState.managedHooks:", table.Count(RTXFrustumState.managedHooks))
    print("RTXFrustumState.managedTimers:", table.Count(RTXFrustumState.managedTimers))
    
    print("\nMemory inspection:")
    for k, v in pairs(_G) do
        if type(v) == "table" and k:find("rtx") then
            print(k, "=>", table.Count(v), "entries")
        end
    end
    
    -- Force collection
    collectgarbage("collect")
end)

-- ==========================================================================
-- CONVAR CALLBACKS
-- ==========================================================================

-- ConVar change callbacks
cvars.AddChangeCallback("rtx_fr_static_props_pvs", function(_, _, new)
    local enabled = tobool(new)
    
    -- If toggling static prop PVS, update all static props
    if RTXFrustumState.active then
        if enabled then
            print("[RTX Force View Frustum] Static prop PVS optimization enabled")
            -- Update props with current PVS data
            RTXFrustumState.StaticPropManager:UpdateAllProps()
        else
            print("[RTX Force View Frustum] Static prop PVS optimization disabled, using large bounds for all props")
            
            -- Set all props to use large bounds
            for prop, data in pairs(RTXFrustumState.staticProps) do
                if IsValid(prop) then
                    RTXFrustumState.StaticPropManager:UpdatePropBounds(prop, true)
                    data.inPVS = true
                end
            end
        end
    end
end)

cvars.AddChangeCallback("rtx_fr_use_pvs", function(_, _, new)
    local enabled = tobool(new)
    
    -- If disabling PVS, reset all entities to large bounds
    if not enabled and RTXFrustumState.active then
        print("[RTX Force View Frustum] PVS optimization disabled, resetting all entities to large bounds")
        
        -- Clear PVS tracking
        for k in pairs(RTXFrustumState.entitiesInPVS) do RTXFrustumState.entitiesInPVS[k] = nil end
        RTXFrustumState.PVSManager.current = nil
        
        -- Reset all entities to use large bounds
        RTXFrustumState.EntityManager:ProcessAllEntities(false)
    elseif enabled and RTXFrustumState.active then
        -- If enabling PVS, immediately update the PVS
        print("[RTX Force View Frustum] PVS optimization enabled, updating bounds based on PVS")
        RTXFrustumState.PVSManager:RequestUpdate(true)
    end
end)

cvars.AddChangeCallback("rtx_fr_enabled", function(_, oldValue, newValue)
    local oldEnabled = tobool(oldValue)
    local newEnabled = tobool(newValue)
    
    print(string.format("[RTX Force View Frustum] Enabled state changing: %s -> %s", 
        tostring(oldEnabled), tostring(newEnabled)))
    
    if newEnabled and not RTXFrustumState.active then
        -- System being enabled
        RTXFrustumState:ActivateSystem()
        
        print("[RTX Force View Frustum] System activated")
    elseif not newEnabled and RTXFrustumState.active then
        -- System being disabled
        local result = RTXFrustumState:DeactivateSystem()
        
        print(string.format("[RTX Force View Frustum] Deactivation complete: %d entities reset, %d hooks removed, %d timers removed, %d props removed", 
            result.entitiesReset, result.hooksRemoved, result.timersRemoved, result.propsRemoved))
    end
end)

cvars.AddChangeCallback("rtx_fr_bounds_size", function(_, _, new)
    -- Use debounce timer to avoid multiple rapid updates
    RTXFrustumState:AddTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        ResetAndUpdateBounds(true)  -- Preserve original bounds when only changing size
    end)
end)

cvars.AddChangeCallback("rtx_fr_rtx_distance", function(_, _, new)
    if not RTXFrustumState.active then return end
    
    RTXFrustumState:AddTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        -- Update light entities only
        for ent in pairs(RTXFrustumState.rtxUpdaters) do
            if IsValid(ent) and ent.lightType ~= RTXFrustumState.LightManager.LIGHT_TYPES.ENVIRONMENT then
                RTXFrustumState.LightManager:ApplyLightBounds(ent)
            end
        end
    end)
end)

cvars.AddChangeCallback("rtx_fr_environment_light_distance", function(_, _, new)
    if not RTXFrustumState.active then return end
    
    RTXFrustumState:AddTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        -- Update environment lights only
        for ent in pairs(RTXFrustumState.rtxUpdaters) do
            if IsValid(ent) and ent.lightType == RTXFrustumState.LightManager.LIGHT_TYPES.ENVIRONMENT then
                RTXFrustumState.LightManager:ApplyLightBounds(ent)
            end
        end
    end)
end)

-- ==========================================================================
-- GUI SETTINGS PANEL
-- ==========================================================================
function CreateSettingsPanel(panel)
    -- Clear the panel first
    panel:ClearControls()
    
    -- Main header and toggle
    panel:CheckBox("Enable Forced View Frustrum", "rtx_fr_enabled")
    panel:ControlHelp("Enables forced render bounds for entities")
    
    -- Static Bounds Settings section
    local boundsCategory = vgui.Create("DCollapsibleCategory", panel)
    boundsCategory:SetLabel("Forced Bounds Settings")
    boundsCategory:SetExpanded(true)
    boundsCategory:Dock(TOP)
    boundsCategory:DockMargin(0, 5, 0, 0)
    boundsCategory:SetPaintBackground(true)
    
    -- Use a DScrollPanel to contain everything with proper scrolling
    local scrollPanel = vgui.Create("DScrollPanel", boundsCategory)
    scrollPanel:Dock(FILL)
    
    -- Create the main panel that will hold our content
    local boundsPanel = vgui.Create("DPanel", scrollPanel)
    boundsPanel:Dock(TOP)
    boundsPanel:DockPadding(5, 5, 5, 5)
    boundsPanel:SetPaintBackground(false)
    boundsPanel:SetTall(650)
    boundsCategory:SetContents(scrollPanel)
    
    -- Presets dropdown
    local presetLabel = vgui.Create("DLabel", boundsPanel)
    presetLabel:SetText("Presets")
    presetLabel:SetTextColor(Color(0, 0, 0))
    presetLabel:Dock(TOP)
    presetLabel:DockMargin(0, 0, 0, 2)
    
    local presetCombo = vgui.Create("DComboBox", boundsPanel)
    presetCombo:Dock(TOP)
    presetCombo:DockMargin(0, 0, 0, 5)
    presetCombo:SetValue("Low")
    presetCombo:SetTall(20)
    
    for preset, _ in pairs(PRESETS) do
        presetCombo:AddChoice(preset)
    end
    
    presetCombo.OnSelect = function(_, _, presetName)
        ApplyPreset(presetName)
    end
    
    -- Description text (combined to save space)
    local descText = vgui.Create("DLabel", boundsPanel)
    descText:SetText("The forced render bounds dictate how far entities should be culled around the player.\n \nThe higher the values, the further they cull, at the cost of performance depending on the map.")
    descText:SetTextColor(Color(0, 0, 0))
    descText:SetWrap(true)
    descText:SetTall(100)
    descText:Dock(TOP)
    descText:DockMargin(0, 0, 0, 5)
    
    -- Create a more compact form for the sliders
    local slidersForm = vgui.Create("DForm", boundsPanel)
    slidersForm:Dock(TOP)
    slidersForm:DockMargin(0, 0, 0, 5)
    slidersForm:SetName("")
    slidersForm:SetSpacing(2)
    slidersForm:SetPadding(2)
    
    -- More compact sliders
    local entitySlider = slidersForm:NumSlider("Regular Entity Bounds", "rtx_fr_bounds_size", 256, 16384, 0)
    entitySlider:DockMargin(0, 0, 0, 2)
    
    local lightSlider = slidersForm:NumSlider("Standard Light Bounds", "rtx_fr_rtx_distance", 256, 4096, 0)
    lightSlider:DockMargin(0, 0, 0, 2)
    
    local envLightSlider = slidersForm:NumSlider("Environment Light Bounds", "rtx_fr_environment_light_distance", 4096, 65536, 0)
    envLightSlider:DockMargin(0, 0, 0, 2)
    
    -- Map Preset Management
    local presetMgmtLabel = vgui.Create("DLabel", boundsPanel)
    presetMgmtLabel:SetText("Map Presets")
    presetMgmtLabel:SetTextColor(Color(0, 0, 0))
    presetMgmtLabel:Dock(TOP)
    presetMgmtLabel:DockMargin(0, 10, 0, 3)
    
    -- Map list (slightly shorter)
    local mapList = vgui.Create("DListView", boundsPanel)
    mapList:Dock(TOP)
    mapList:SetTall(120)
    mapList:AddColumn("Map")
    mapList:AddColumn("Preset")
    
    -- Populate the map list
    local function RefreshMapList()
        mapList:Clear()
        for map, preset in pairs(MAP_PRESETS) do
            if type(preset) == "table" and preset.type == "custom" then
                mapList:AddLine(map, "Custom")
            else
                mapList:AddLine(map, preset)
            end
        end
    end
    
    RefreshMapList()
    
    -- Buttons panel (more compact)
    local buttonsPanel = vgui.Create("DPanel", boundsPanel)
    buttonsPanel:Dock(TOP)
    buttonsPanel:SetPaintBackground(false)
    buttonsPanel:SetTall(30)
    buttonsPanel:DockMargin(0, 3, 0, 10)
    
    -- Add Current Map button
    local addMapBtn = vgui.Create("DButton", buttonsPanel)
    addMapBtn:SetText("Add Current Map")
    addMapBtn:Dock(LEFT)
    addMapBtn:SetWide(120)
    addMapBtn:DockMargin(0, 0, 5, 0)
    
    addMapBtn.DoClick = function()
        local currentMap = game.GetMap()
        
        -- Get current values from ConVars
        local entityBounds = cv_bounds_size:GetFloat()
        local lightDistance = cv_rtx_updater_distance:GetFloat()
        local envLightDistance = cv_environment_light_distance:GetFloat()
        
        -- Try to find matching preset
        local matchingPreset = nil
        for name, preset in pairs(PRESETS) do
            if preset.entity == entityBounds and 
               preset.light == lightDistance and 
               preset.environment == envLightDistance then
                matchingPreset = name
                break
            end
        end
        
        -- If no exact match, save as custom with the actual values
        if not matchingPreset then
            MAP_PRESETS[currentMap] = {
                type = "custom",
                entity = entityBounds,
                light = lightDistance,
                environment = envLightDistance
            }
        else
            -- Save predefined preset by name
            MAP_PRESETS[currentMap] = matchingPreset
        end
        
        SaveMapPresets()
        RefreshMapList()
        
        -- Show a notification
        notification.AddLegacy("Saved current settings for " .. currentMap, NOTIFY_GENERIC, 3)
    end
    
    -- Remove Selected button
    local removeBtn = vgui.Create("DButton", buttonsPanel)
    removeBtn:SetText("Remove Selected")
    removeBtn:Dock(RIGHT)
    removeBtn:SetWide(120)
    removeBtn:DockMargin(5, 0, 0, 0)
    
    removeBtn.DoClick = function()
        local selected = mapList:GetSelectedLine()
        if selected then
            local mapName = mapList:GetLine(selected):GetValue(1)
            MAP_PRESETS[mapName] = nil
            SaveMapPresets()
            mapList:RemoveLine(selected)
        end
    end
    -- Init - load saved map presets
    LoadMapPresets()
    
    -- Apply current map preset if exists, otherwise use Low preset
    local currentMap = game.GetMap()
    if MAP_PRESETS[currentMap] then
        -- Check if it's a custom preset (table) or predefined (string)
        if type(MAP_PRESETS[currentMap]) == "table" and MAP_PRESETS[currentMap].type == "custom" then
            -- Apply custom settings
            local customSettings = MAP_PRESETS[currentMap]
            RunConsoleCommand("rtx_fr_bounds_size", tostring(customSettings.entity))
            RunConsoleCommand("rtx_fr_rtx_distance", tostring(customSettings.light))
            RunConsoleCommand("rtx_fr_environment_light_distance", tostring(customSettings.environment))
            presetCombo:SetValue("Custom")
        else
            -- It's a predefined preset by name
            ApplyPreset(MAP_PRESETS[currentMap])
            presetCombo:SetValue(MAP_PRESETS[currentMap])
        end
    else
        -- Default to Low preset for maps without configuration
        ApplyPreset("Low")
        presetCombo:SetValue("Low")
    end
end

-- Add to Utilities menu
hook.Add("PopulateToolMenu", "RTXFrustumOptimizationMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "User", "RTX_FVF", "#RTX - Force View Frustum", "", "", function(panel)
        CreateSettingsPanel(panel)
    end)
end)

-- Initialize state
if cv_enabled:GetBool() then
    -- Make sure we activate on initial load
    timer.Simple(1, function()
        RTXFrustumState:ActivateSystem()
    end)
end