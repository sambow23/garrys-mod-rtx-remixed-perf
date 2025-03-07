if not CLIENT then return end

-- ConVars
local cv_enabled = CreateClientConVar("fr_enabled", "1", true, false, "Enable large render bounds for all entities")
local cv_bounds_size = CreateClientConVar("fr_bounds_size", "4096", true, false, "Size of render bounds")
local cv_rtx_updater_distance = CreateClientConVar("fr_rtx_distance", "2048", true, false, "Maximum render distance for regular RTX light updaters")
local cv_environment_light_distance = CreateClientConVar("fr_environment_light_distance", "32768", true, false, "Maximum render distance for environment light updaters")
local cv_debug = CreateClientConVar("fr_debug_messages", "0", true, false, "Enable debug messages for RTX view frustum optimization")
local cv_show_advanced = CreateClientConVar("fr_show_advanced", "0", true, false, "Show advanced RTX view frustum settings")
local cv_use_pvs = CreateClientConVar("fr_use_pvs", "1", true, false, "Use Potentially Visible Set for render bounds optimization")
local cv_pvs_update_interval = CreateClientConVar("fr_pvs_update_interval", "0.5", true, false, "How often to update the PVS data (seconds)")
local cv_pvs_hud = CreateClientConVar("fr_pvs_hud", "0", true, false, "Show HUD information about PVS optimization")
local cv_static_props_pvs = CreateClientConVar("fr_static_props_pvs", "1", true, false, "Use PVS for static prop optimization")
local cv_pvs_update_interval = CreateClientConVar("fr_pvs_update_interval", "1.5", true, false, "How often to update the PVS data (seconds)")


-- Cache the bounds vectors
local boundsSize = cv_bounds_size:GetFloat()
local mins = Vector(-boundsSize, -boundsSize, -boundsSize)
local maxs = Vector(boundsSize, boundsSize, boundsSize)

-- Cache RTXMath functions
local RTXMath_IsWithinBounds = RTXMath.IsWithinBounds
local RTXMath_DistToSqr = RTXMath.DistToSqr
local RTXMath_LerpVector = RTXMath.LerpVector
local RTXMath_GenerateChunkKey = RTXMath.GenerateChunkKey
local RTXMath_ComputeNormal = RTXMath.ComputeNormal
local RTXMath_CreateVector = RTXMath.CreateVector
local RTXMath_NegateVector = RTXMath.NegateVector
local RTXMath_MultiplyVector = RTXMath.MultiplyVector

-- Constants and caches
local Vector = Vector
local IsValid = IsValid
local pairs = pairs
local ipairs = ipairs
local DEBOUNCE_TIME = 0.1
local boundsUpdateTimer = "FR_BoundsUpdate"
local rtxUpdateTimer = "FR_RTXUpdate"
local rtxUpdaterCache = {}
local rtxUpdaterCount = 0
local staticProps = {}
local originalBounds = {}
local mapBounds = {
    min = Vector(-16384, -16384, -16384),
    max = Vector(16384, 16384, 16384)
}
local boundsInitialized = false
local patternCache = {}
local weakEntityTable = {__mode = "k"} -- Allows garbage collection of invalid entities
originalBounds = setmetatable({}, weakEntityTable)
rtxUpdaterCache = setmetatable({}, weakEntityTable)
local managedTimers = {}
local currentPVS = nil
local lastPVSUpdateTime = 0
local entitiesInPVS = setmetatable({}, weakEntityTable)  -- Track which entities were in PVS
local pvs_update_in_progress = false


-- RTX Light Updater model list
local RTX_UPDATER_MODELS = {
    ["models/hunter/plates/plate.mdl"] = true,
    ["models/hunter/blocks/cube025x025x025.mdl"] = true
}

-- Cache for static props
local staticProps = {}
local originalBounds = {} -- Store original render bounds

local SPECIAL_ENTITIES = {
    ["hdri_cube_editor"] = true,
    ["rtx_lightupdater"] = true,
    ["rtx_lightupdatermanager"] = true
}

local LIGHT_TYPES = {
    POINT = "light",
    SPOT = "light_spot",
    DYNAMIC = "light_dynamic",
    ENVIRONMENT = "light_environment",
    DIRECTIONAL = "light_directional"
}

local REGULAR_LIGHT_TYPES = {
    [LIGHT_TYPES.POINT] = true,
    [LIGHT_TYPES.SPOT] = true,
    [LIGHT_TYPES.DYNAMIC] = true,
    [LIGHT_TYPES.DIRECTIONAL] = true
}

local SPECIAL_ENTITY_BOUNDS = {
    ["prop_door_rotating"] = {
        size = 512, -- Default size for doors
        description = "Door entities", -- For debug/documentation
    },

    ["func_door_rotating"] = {
        size = 512, -- Default size for doors
        description = "func_ entities", -- For debug/documentation
    },

    ["func_physbox"] = {
        size = 512, -- Default size for doors
        description = "func_ entities", -- For debug/documentation
    },

    ["func_breakable"] = {
        size = 512, -- Default size for doors
        description = "func_ entities", -- For debug/documentation
    },

    ["^npc_%w+"] = {
        size = 512,
        description = "All npc_ entities",
        isPattern = true
    },

    ["^_rope%w+"] = {
        size = 512,
        description = "All _rope entities",
        isPattern = true
    },

    ["prop_physics"] = {
        size = 512, -- Default size for doors
        description = "Prop entities", -- For debug/documentation
    },
    -- Add more entities here as needed:
    -- ["entity_class"] = { size = number, description = "description" }
}

-- For statistics tracking
local stats = {
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

local pvs_stats = {
    processedEntities = 0,
    totalEntities = 0,
    inProgress = false,
    startTime = 0,
    processingTime = 0,
    lastUpdateTime = 0,
    updateDelay = 1.5 -- Only update every 1.5 seconds minimum
}

-- Helper Functions
local function UpdateStaticPropBounds(prop, inPVS)
    if not IsValid(prop) then return false end
    
    if inPVS then
        -- In PVS: use large bounds for RTX lighting
        prop:SetRenderBounds(mins, maxs)
        prop:SetNoDraw(false)
    else
        -- Out of PVS: use small bounds for performance
        local smallBounds = Vector(64, 64, 64)
        prop:SetRenderBounds(-smallBounds, smallBounds)
        -- Alternative: prop:SetNoDraw(true) for maximum performance
    end
    
    return true
end

local function CreateManagedTimer(name, delay, repetitions, func)
    -- Remove existing timer if it exists
    if timer.Exists(name) then
        timer.Remove(name)
    end
    
    -- Create new timer
    timer.Create(name, delay, repetitions, func)
    managedTimers[name] = true
end

local function CleanupInvalidEntities()
    local removed = 0
    for ent in pairs(originalBounds) do
        if not IsValid(ent) then
            originalBounds[ent] = nil
            removed = removed + 1
        end
    end
    
    for ent in pairs(rtxUpdaterCache) do
        if not IsValid(ent) then
            RemoveFromRTXCache(ent)
            removed = removed + 1
        end
    end
    
    if cv_debug:GetBool() and removed > 0 then
        print("[RTX Fixes] Cleaned up " .. removed .. " invalid entity references")
    end
end

local function IsPointWithinBounds(point)
    return point:WithinAABox(mapBounds.min, mapBounds.max)
end

local function UpdateBoundsVectors(size)
    boundsSize = size
    local vec = RTXMath_CreateVector(size, size, size)
    mins = RTXMath_NegateVector(vec)
    maxs = vec
end

local function IsInBounds(pos, mins, maxs)
    return RTXMath_IsWithinBounds(pos, mins, maxs)
end

-- Distance check using native implementation
local function GetDistanceSqr(pos1, pos2)
    return RTXMath_DistToSqr(pos1, pos2)
end

-- Helper function to add new special entities
function AddSpecialEntityBounds(class, size, description)
    SPECIAL_ENTITY_BOUNDS[class] = {
        size = size,
        description = description
    }
    
    -- Update existing entities of this class if the optimization is enabled
    if cv_enabled:GetBool() then
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) then
                SetEntityBounds(ent, false)
            end
        end
    end
end

local function GetSpecialBoundsForClass(className)
    -- First try direct lookup (fastest)
    local directMatch = SPECIAL_ENTITY_BOUNDS[className]
    if directMatch then
        return directMatch
    end
    
    -- Check cache for previous pattern match
    if patternCache[className] then
        return patternCache[className]
    end
    
    -- Try pattern matching
    for pattern, boundsInfo in pairs(SPECIAL_ENTITY_BOUNDS) do
        if boundsInfo.isPattern and string.match(className, pattern) then
            -- Cache the result for future lookups
            patternCache[className] = boundsInfo
            return boundsInfo
        end
    end
    
    -- No match found
    return nil
end

function StartStaticPropProcessingTimer()
    if timer.Exists("RTX_PVS_StaticPropProcessing") then
        timer.Remove("RTX_PVS_StaticPropProcessing")
    end
    
    local propList = {}
    for prop, data in pairs(staticProps) do
        if IsValid(prop) then
            table.insert(propList, {
                prop = prop,
                pos = data.pos,
                inPVS = data.inPVS
            })
        end
    end
    
    local propStats = {
        totalProps = #propList,
        currentIndex = 1,
        inProgress = true,
        startTime = SysTime()
    }
    
    timer.Create("RTX_PVS_StaticPropProcessing", 0, 0, function()
        -- Process a small batch each frame
        local batchSize = 50
        local startIdx = propStats.currentIndex
        local endIdx = math.min(startIdx + batchSize - 1, #propList)
        
        for i = startIdx, endIdx do
            local propData = propList[i]
            local prop = propData.prop
            
            if IsValid(prop) then
                -- Use the optimized position check
                local isInPVS = EntityManager.TestPositionInPVS_Optimized(propData.pos)
                
                if isInPVS ~= propData.inPVS then
                    UpdateStaticPropBounds(prop, isInPVS)
                    if staticProps[prop] then
                        staticProps[prop].inPVS = isInPVS
                    end
                end
            end
        end
        
        propStats.currentIndex = endIdx + 1
        
        -- Check if we're done
        if propStats.currentIndex > #propList then
            timer.Remove("RTX_PVS_StaticPropProcessing")
            propStats.inProgress = false
            
            -- Update statistics
            stats.staticPropsInPVS = 0
            stats.staticPropsTotal = 0
            
            for prop, data in pairs(staticProps) do
                if IsValid(prop) then
                    stats.staticPropsTotal = stats.staticPropsTotal + 1
                    if data.inPVS then
                        stats.staticPropsInPVS = stats.staticPropsInPVS + 1
                    end
                end
            end
            
            if cv_debug:GetBool() then
                print(string.format("[RTX Fixes] Static prop PVS update complete: %.2f ms, %d props, %d in PVS",
                    (SysTime() - propStats.startTime) * 1000,
                    stats.staticPropsTotal,
                    stats.staticPropsInPVS))
            end
        end
    end)
end

function StartEntityProcessingTimer()
    if timer.Exists("RTX_PVS_EntityProcessing") then
        timer.Remove("RTX_PVS_EntityProcessing")
    end
    
    local allEntities = ents.GetAll()
    pvs_stats.totalEntities = #allEntities
    pvs_stats.currentIndex = 1
    pvs_stats.inProgress = true
    
    timer.Create("RTX_PVS_EntityProcessing", 0, 0, function()
        -- Process a small batch each frame
        local batchSize = 50
        local startIdx = pvs_stats.currentIndex
        local endIdx = math.min(startIdx + batchSize - 1, #allEntities)
        
        for i = startIdx, endIdx do
            local ent = allEntities[i]
            if IsValid(ent) then
                local className = ent:GetClass()
                if not GetSpecialBoundsForClass(className) and 
                   not SPECIAL_ENTITIES[className] and 
                   not rtxUpdaterCache[ent] then
                    
                    -- Use the optimized single-entity check
                    local isInPVS = EntityManager.ProcessEntityPVS_Optimized(ent)
                    
                    if isInPVS then
                        -- In PVS: set large bounds
                        entitiesInPVS[ent] = true
                        SetEntityBounds(ent, false)
                    else
                        -- Out of PVS: reset to original bounds
                        entitiesInPVS[ent] = nil
                        if originalBounds[ent] then
                            ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
                        end
                    end
                end
            end
        end
        
        pvs_stats.currentIndex = endIdx + 1
        pvs_stats.processedEntities = endIdx
        
        -- Update stats for HUD
        if cv_pvs_hud:GetBool() then
            stats.entitiesInPVS = 0
            for ent in pairs(entitiesInPVS) do
                if IsValid(ent) then
                    stats.entitiesInPVS = stats.entitiesInPVS + 1
                end
            end
            stats.totalEntities = pvs_stats.totalEntities
        end
        
        -- Check if we're done
        if pvs_stats.currentIndex > #allEntities then
            timer.Remove("RTX_PVS_EntityProcessing")
            pvs_stats.inProgress = false
            pvs_stats.processingTime = SysTime() - pvs_stats.startTime
            
            -- Handle static props
            if cv_static_props_pvs:GetBool() then
                StartStaticPropProcessingTimer()
            end
        end
    end)
end

local function UpdatePVSWithNative()
    if not cv_enabled:GetBool() or not cv_use_pvs:GetBool() or not NikNaks or not NikNaks.CurrentMap then return end
    if pvs_update_in_progress then return end
    
    -- Only update after sufficient delay
    local updateInterval = cv_pvs_update_interval:GetFloat()
    if lastPVSUpdateTime > 0 and (CurTime() - lastPVSUpdateTime < updateInterval) then
        return
    end
    
    local player = LocalPlayer()
    if not IsValid(player) then return end
    
    local playerPos = player:GetPos()
    
    -- Check if player has moved significantly
    if currentPVS and lastPlayerPos then
        local moveDist = playerPos:Distance(lastPlayerPos)
        if moveDist < 200 then
            return
        end
    end
    
    pvs_update_in_progress = true
    lastPlayerPos = playerPos
    
    -- Generate PVS - still done in Lua but only once per interval
    currentPVS = NikNaks.CurrentMap:PVSForOrigin(playerPos)
    
    if currentPVS then
        local leafPositions = {}
        local leafs = currentPVS:GetLeafs()
        
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
                    table.insert(leafPositions, center)
                end
            end
        end
        
        -- Store this data in the fast spatial grid
        EntityManager.SetPVSLeafData_Optimized(leafPositions, playerPos)
        
        -- Update leaf statistics for HUD display
        stats.pvsLeafCount = #leafPositions
        stats.totalLeafCount = table.Count(NikNaks.CurrentMap:GetLeafs())
        
        -- Start a timer to process entities gradually
        pvs_stats.startTime = SysTime()
        pvs_stats.processedEntities = 0
        
        StartEntityProcessingTimer()
    end
    
    pvs_update_in_progress = false
    lastPVSUpdateTime = CurTime()
end

-- Replace the original UpdatePlayerPVS function with the new one
UpdatePlayerPVS = UpdatePVSWithNative

function UpdateStaticPropsPVS()
    if not cv_enabled:GetBool() or not cv_static_props_pvs:GetBool() then return end
    if #staticProps == 0 then return end
    
    local propPositions = {}
    local propEntities = {}
    
    for prop, data in pairs(staticProps) do
        if IsValid(prop) then
            table.insert(propEntities, prop)
            table.insert(propPositions, data.pos)
        end
    end
    
    -- Use batched processing similar to regular entities
    local batchSize = 250
    EntityManager.BeginPVSEntityBatchProcessing(propEntities, propPositions, mins, maxs, batchSize)
    
    -- Process all batches at once for static props (they're less important for frame pacing)
    while EntityManager.IsPVSUpdateInProgress() do
        local results, complete = EntityManager.ProcessNextEntityBatch()
        
        for i, isInPVS in ipairs(results) do
            local prop = propEntities[i]
            if IsValid(prop) and staticProps[prop] then
                if isInPVS ~= staticProps[prop].inPVS then
                    UpdateStaticPropBounds(prop, isInPVS)
                    staticProps[prop].inPVS = isInPVS
                end
            end
        end
        
        if complete then break end
    end
    
    -- Update statistics
    stats.staticPropsInPVS = 0
    stats.staticPropsTotal = 0
    
    for prop, data in pairs(staticProps) do
        if IsValid(prop) then
            stats.staticPropsTotal = stats.staticPropsTotal + 1
            if data.inPVS then
                stats.staticPropsInPVS = stats.staticPropsInPVS + 1
            end
        end
    end
end

-- Helper function to identify RTX updaters
local function IsRTXUpdater(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    return SPECIAL_ENTITIES[class] or 
           (ent:GetModel() and RTX_UPDATER_MODELS[ent:GetModel()])
end

-- Store original bounds for an entity
local function StoreOriginalBounds(ent)
    if not IsValid(ent) or originalBounds[ent] then return end
    local mins, maxs = ent:GetRenderBounds()
    originalBounds[ent] = {mins = mins, maxs = maxs}
end

-- RTX updater cache management functions
local function AddToRTXCache(ent)
    if not IsValid(ent) or rtxUpdaterCache[ent] then return end
    if IsRTXUpdater(ent) then
        rtxUpdaterCache[ent] = true
        rtxUpdaterCount = rtxUpdaterCount + 1
        
        -- Set initial RTX bounds
        local rtxDistance = cv_rtx_updater_distance:GetFloat()
        local rtxBoundsSize = Vector(rtxDistance, rtxDistance, rtxDistance)
        ent:SetRenderBounds(-rtxBoundsSize, rtxBoundsSize)
        ent:DisableMatrix("RenderMultiply")
        ent:SetNoDraw(false)
        
        -- Special handling for hdri_cube_editor to ensure it's never culled
        if ent:GetClass() == "hdri_cube_editor" then
            -- Using a very large value for HDRI cube editor
            local hdriSize = 32768 -- Maximum recommended size
            local hdriBounds = Vector(hdriSize, hdriSize, hdriSize)
            ent:SetRenderBounds(-hdriBounds, hdriBounds)
        end
    end
end

local function RemoveFromRTXCache(ent)
    if rtxUpdaterCache[ent] then
        rtxUpdaterCache[ent] = nil
        rtxUpdaterCount = rtxUpdaterCount - 1
    end
end

-- Set bounds for a single entity
function SetEntityBounds(ent, useOriginal)
    if not IsValid(ent) then return end
    
    -- Original bounds restoration code
    if useOriginal then
        if originalBounds[ent] then
            ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
        end
        return
    end
    
    StoreOriginalBounds(ent)
    
    local entPos = ent:GetPos()
    if not entPos then return end
    
    -- Get entity class for special handling
    local className = ent:GetClass()
    local specialBounds = GetSpecialBoundsForClass(className)
    
    -- Special entities - Always use custom bounds regardless of PVS
    if specialBounds then
        local size = specialBounds.size
        
        -- For doors, use our native implementation
        if className == "prop_door_rotating" then
            EntityManager.CalculateSpecialEntityBounds(ent, size)
        else
            -- Regular special entities
            local bounds = RTXMath_CreateVector(size, size, size)
            local negBounds = RTXMath_NegateVector(bounds)
            ent:SetRenderBounds(negBounds, bounds)
        end
        
        -- Debug output if enabled
        if cv_debug:GetBool() then
            local patternText = specialBounds.isPattern and " (via pattern)" or ""
            print(string.format("[RTX Fixes] Special entity bounds applied (%s): %d%s", 
                className, size, patternText))
        end
        return
        
    -- HDRI cube editor - always visible
    elseif ent:GetClass() == "hdri_cube_editor" then
        local hdriSize = 32768
        local hdriBounds = RTXMath_CreateVector(hdriSize, hdriSize, hdriSize)
        local negHdriBounds = RTXMath_NegateVector(hdriBounds)
            
        -- Use native bounds check
        if RTXMath_IsWithinBounds(entPos, negHdriBounds, hdriBounds) then
            ent:SetRenderBounds(negHdriBounds, hdriBounds)
            ent:DisableMatrix("RenderMultiply")
            ent:SetNoDraw(false)
        end
        
    -- RTX updaters - always handle separately
    elseif rtxUpdaterCache[ent] then
        -- Completely separate handling for environment lights
        if ent.lightType == LIGHT_TYPES.ENVIRONMENT then
            local envSize = cv_environment_light_distance:GetFloat()
            local envBounds = RTXMath_CreateVector(envSize, envSize, envSize)
            local negEnvBounds = RTXMath_NegateVector(envBounds)
            
            -- Use native bounds and distance check
            if RTXMath_IsWithinBounds(entPos, negEnvBounds, envBounds) then
                ent:SetRenderBounds(negEnvBounds, envBounds)
                
                -- Only print if debug is enabled
                if cv_enabled:GetBool() and cv_debug:GetBool() then
                    local distSqr = RTXMath_DistToSqr(entPos, vector_origin)
                    print(string.format("[RTX Fixes] Environment light bounds: %d (Distance: %.2f)", 
                        envSize, math.sqrt(distSqr)))
                end
            end
            
        elseif REGULAR_LIGHT_TYPES[ent.lightType] then
            local rtxDistance = cv_rtx_updater_distance:GetFloat()
            local rtxBounds = RTXMath_CreateVector(rtxDistance, rtxDistance, rtxDistance)
            local negRtxBounds = RTXMath_NegateVector(rtxBounds)
            
            -- Use native bounds and distance check
            if RTXMath_IsWithinBounds(entPos, negRtxBounds, rtxBounds) then
                ent:SetRenderBounds(negRtxBounds, rtxBounds)
                
                -- Only print if debug is enabled
                if cv_enabled:GetBool() and cv_debug:GetBool() then
                    local distSqr = RTXMath_DistToSqr(entPos, vector_origin)
                    print(string.format("[RTX Fixes] Regular light bounds (%s): %d (Distance: %.2f)", 
                        ent.lightType, rtxDistance, math.sqrt(distSqr)))
                end
            end
        end
        
        ent:DisableMatrix("RenderMultiply")
        if GetConVar("rtx_lightupdater_show"):GetBool() then
            ent:SetRenderMode(0)
            ent:SetColor(Color(255, 255, 255, 255))
        else
            ent:SetRenderMode(2)
            ent:SetColor(Color(255, 255, 255, 1))
        end
    
    -- Regular entities - Check PVS if enabled
    else
        if cv_use_pvs:GetBool() and not pvs_update_in_progress then -- Don't check during an update
            -- Ensure PVS is updated
            if not currentPVS or (CurTime() - lastPVSUpdateTime > cv_pvs_update_interval:GetFloat()) then
                UpdatePlayerPVS()
            end
            
            -- If entity is not in PVS, use original bounds
            if currentPVS and not currentPVS:TestPosition(entPos) then
                if originalBounds[ent] then
                    ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
                end
                return
            end
        end
        
        -- Entity is in PVS or PVS optimization is disabled, use large bounds
        if RTXMath_IsWithinBounds(entPos, mins, maxs) then
            ent:SetRenderBounds(mins, maxs)
        end
    end
end

local function UpdateAllEntitiesBatched(useOriginal)
    local allEntities = ents.GetAll()
    local totalEntities = #allEntities
    local batchSize = 100
    local batches = math.ceil(totalEntities / batchSize)
    
    local function ProcessEntityBatch(batchNum)
        local startIdx = (batchNum - 1) * batchSize + 1
        local endIdx = math.min(batchNum * batchSize, totalEntities)
        
        local batchEntities = {}
        for i = startIdx, endIdx do
            local ent = allEntities[i]
            if IsValid(ent) then
                SetEntityBounds(ent, useOriginal)
            end
        end
        
        -- Process next batch if more remain
        if batchNum < batches then
            timer.Simple(0.05, function()
                ProcessEntityBatch(batchNum + 1)
            end)
        end
    end
    
    -- Start batch processing
    ProcessEntityBatch(1)
end

-- Create clientside static props
local function CreateStaticProps()
    -- Clean up existing props first
    for _, prop in pairs(staticProps) do
        if IsValid(prop) then prop:Remove() end
    end
    staticProps = setmetatable({}, weakEntityTable)
    
    -- Store original ConVar value
    local originalPropSetting = GetConVar("r_drawstaticprops"):GetInt()
    
    if not (cv_enabled:GetBool() and NikNaks and NikNaks.CurrentMap) then 
        return 
    end
    
    -- Create props in batches to prevent frame drops
    local props = NikNaks.CurrentMap:GetStaticProps()
    local batchSize = 50
    local propCount = 0
    local totalProps = #props
    local batches = math.ceil(totalProps / batchSize)
    
    local function ProcessBatch(batchNum)
        local startIndex = (batchNum - 1) * batchSize + 1
        local endIndex = math.min(batchNum * batchSize, totalProps)
        
        local playerPos = LocalPlayer():GetPos()
        local maxDistance = 16384
        local maxDistSqr = maxDistance * maxDistance
        
        for i = startIndex, endIndex do
            local propData = props[i]
            if propData then
                local propPos = propData:GetPos()
                if RTXMath_DistToSqr(propPos, playerPos) <= maxDistSqr then
                    -- Stagger individual prop creation to further reduce stuttering
                    timer.Simple((i - startIndex) * 0.01, function()
                        local prop = ClientsideModel(propData:GetModel())
                        if IsValid(prop) then
                            prop:SetPos(propPos)
                            prop:SetAngles(propData:GetAngles())
                            
                            -- Check if in PVS and set bounds accordingly
                            local inPVS = not cv_static_props_pvs:GetBool() or 
                                         (currentPVS and currentPVS:TestPosition(propPos))
                            
                            UpdateStaticPropBounds(prop, inPVS)
                            
                            prop:SetColor(propData:GetColor())
                            prop:SetSkin(propData:GetSkin())
                            local scale = propData:GetScale()
                            if scale != 1 then
                                prop:SetModelScale(scale)
                            end
                            
                            -- Store with position information
                            staticProps[prop] = {
                                pos = propPos,
                                inPVS = inPVS
                            }
                            propCount = propCount + 1
                        end
                    end)
                end
            end
        end
        
        -- Process next batch if there are more
        if batchNum < batches then
            timer.Simple(0.5, function() ProcessBatch(batchNum + 1) end)
        else
            if cv_debug:GetBool() then
                print("[RTX Fixes] Created " .. propCount .. " static props")
            end
        end
    end
    
    -- Start batch processing
    ProcessBatch(1)
    
    -- Save original setting in a global to restore later
    RTX_FRUSTUM_ORIGINAL_PROP_SETTING = originalPropSetting
end

-- Update all entities
local function UpdateAllEntities(useOriginal)
    for _, ent in ipairs(ents.GetAll()) do
        SetEntityBounds(ent, useOriginal)
    end
end

-- Hook for new entities
hook.Add("OnEntityCreated", "SetLargeRenderBounds", function(ent)
    if not IsValid(ent) then return end
    
    timer.Simple(0, function()
        if IsValid(ent) then
            AddToRTXCache(ent)
            SetEntityBounds(ent, not cv_enabled:GetBool())
        end
    end)
end)

-- Initial setup
hook.Add("InitPostEntity", "InitialBoundsSetup", function()
    timer.Simple(1, function()
        if cv_enabled:GetBool() then
            -- Initial PVS update if PVS optimization is enabled
            if cv_use_pvs:GetBool() and NikNaks and NikNaks.CurrentMap then
                UpdatePlayerPVS()
            end
            
            UpdateAllEntitiesBatched(false)
            CreateStaticProps()
        end
    end)
end)

hook.Add("Think", "RTX_PVS_BatchProcessor", function()
    if not cv_enabled:GetBool() or not cv_use_pvs:GetBool() then return end
    
    -- Check if there's batch processing to do
    if EntityManager.IsPVSUpdateInProgress() then
        -- Process just one batch per frame to avoid hitches
        local results, complete = EntityManager.ProcessNextEntityBatch()
        
        -- Apply results to entities
        if #results > 0 then
            local batchStart = pvs_stats.processedEntities + 1
            local batchEnd = batchStart + #results - 1
            
            for i, isInPVS in ipairs(results) do
                local entityIdx = batchStart + i - 1
                local entities = ents.GetAll()
                local ent = entities[entityIdx]
                
                if IsValid(ent) then
                    if isInPVS then
                        -- In PVS: set large bounds
                        entitiesInPVS[ent] = true
                        SetEntityBounds(ent, false)
                    else
                        -- Out of PVS: reset to original bounds
                        entitiesInPVS[ent] = nil
                        if originalBounds[ent] then
                            ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
                        end
                    end
                end
            end
            
            pvs_stats.processedEntities = pvs_stats.processedEntities + #results
            
            -- Update stats for HUD
            if cv_pvs_hud:GetBool() then
                stats.entitiesInPVS = 0
                for ent in pairs(entitiesInPVS) do
                    if IsValid(ent) then
                        stats.entitiesInPVS = stats.entitiesInPVS + 1
                    end
                end
                stats.totalEntities = pvs_stats.totalEntities
            end
        end
        
        -- Handle completion
        if complete then
            pvs_stats.inProgress = false
            pvs_stats.processingTime = SysTime() - pvs_stats.startTime
            
            if cv_debug:GetBool() then
                print(string.format("[RTX Fixes] PVS update complete: %.2f ms, %d entities", 
                    pvs_stats.processingTime * 1000, pvs_stats.totalEntities))
            end
            
            -- Also update static props if enabled
            if cv_static_props_pvs:GetBool() then
                UpdateStaticPropsPVS()
            end
        end
    end
end)

hook.Add("Think", "UpdateRTXPVSState", function()
    if not cv_enabled:GetBool() or not cv_use_pvs:GetBool() then return end
    
    if CurTime() - lastPVSUpdateTime > cv_pvs_update_interval:GetFloat() then
        UpdatePlayerPVS()
    end
end)

-- Map cleanup/reload handler
hook.Add("OnReloaded", "RefreshStaticProps", function()
    -- Clear bounds cache
    originalBounds = {}
    
    -- Reset PVS cache
    currentPVS = nil
    lastPVSUpdateTime = 0
    
    -- Remove existing static props
    for _, prop in pairs(staticProps) do
        if IsValid(prop) then
            prop:Remove()
        end
    end
    staticProps = {}
    
    -- Recreate if enabled
    if cv_enabled:GetBool() then
        timer.Simple(1, CreateStaticProps)
    end
end)

hook.Add("OnMapChange", "ClearRTXPVSCache", function()
    currentPVS = nil
    lastPVSUpdateTime = 0
end)

-- Track frame times when HUD is enabled
hook.Add("Think", "RTXPVSFrameTimeTracker", function()
    if cv_pvs_hud:GetBool() then
        local frameTime = FrameTime() * 1000 -- Convert to ms
        
        -- Track in history for moving average
        table.insert(stats.frameTimeHistory, frameTime)
        if #stats.frameTimeHistory > 60 then -- Keep last 60 frames
            table.remove(stats.frameTimeHistory, 1)
        end
        
        -- Calculate average
        local sum = 0
        for _, time in ipairs(stats.frameTimeHistory) do
            sum = sum + time
        end
        stats.frameTimeAvg = sum / #stats.frameTimeHistory
        
        stats.frameTime = frameTime
    end
end)

hook.Add("HUDPaint", "RTXPVSDebugHUD", function()
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
        {text = "RTX View Frustum PVS Statistics", color = headerColor},
        {text = "PVS Optimization: " .. (cv_use_pvs:GetBool() and "Enabled" or "Disabled"), 
         color = cv_use_pvs:GetBool() and goodColor or badColor},
        {text = string.format("Entities in PVS: %d / %d (%.1f%%)", 
            stats.entitiesInPVS, stats.totalEntities, 
            stats.totalEntities > 0 and (stats.entitiesInPVS / stats.totalEntities * 100) or 0)},
        {text = string.format("Leafs in PVS: %d / %d (%.1f%%)", 
            stats.pvsLeafCount, stats.totalLeafCount,
            stats.totalLeafCount > 0 and (stats.pvsLeafCount / stats.totalLeafCount * 100) or 0)},
        {text = string.format("Current leaf: %s", currentLeaf)},
        {text = string.format("Frame time: %.2f ms (avg: %.2f ms)", stats.frameTime, stats.frameTimeAvg),
         color = stats.frameTimeAvg < 16.67 and goodColor or badColor}, -- 60fps threshold
        {text = string.format("PVS update time: %.2f ms", stats.updateTime * 1000)},
        {text = string.format("Last update: %.1f sec ago", CurTime() - lastPVSUpdateTime)},
        {text = string.format("Static Props in PVS: %d / %d (%.1f%%)", 
        stats.staticPropsInPVS, stats.staticPropsTotal, 
        stats.staticPropsTotal > 0 and (stats.staticPropsInPVS / stats.staticPropsTotal * 100) or 0),
     color = cv_static_props_pvs:GetBool() and textColor or Color(150, 150, 150, 220)},
        {text = string.format("Position: %.1f, %.1f, %.1f", 
            player:GetPos().x, player:GetPos().y, player:GetPos().z)}
    }
    if pvs_stats.inProgress then
        local progress = EntityManager.GetPVSProgress() * 100
        table.insert(infoLines, {text = string.format("PVS Update: %.1f%% complete", progress),
                                color = Color(255, 200, 100, 220)})
    end
    
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

-- Handle ConVar changes
cvars.AddChangeCallback("fr_static_props_pvs", function(_, _, new)
    local enabled = tobool(new)
    
    -- If toggling static prop PVS, update all static props
    if cv_enabled:GetBool() then
        if enabled then
            print("[RTX Fixes] Static prop PVS optimization enabled")
            -- PVS will be applied on next update
        else
            print("[RTX Fixes] Static prop PVS optimization disabled, using large bounds for all props")
            
            -- Set all props to use large bounds
            for prop, data in pairs(staticProps) do
                if IsValid(prop) then
                    UpdateStaticPropBounds(prop, true)
                    data.inPVS = true
                end
            end
        end
    end
end)

cvars.AddChangeCallback("fr_use_pvs", function(_, _, new)
    local enabled = tobool(new)
    
    -- If disabling PVS, reset all entities to large bounds
    if not enabled and cv_enabled:GetBool() then
        print("[RTX Fixes] PVS optimization disabled, resetting all entities to large bounds")
        
        -- Clear PVS tracking
        entitiesInPVS = setmetatable({}, weakEntityTable)
        currentPVS = nil
        
        -- Reset all entities to use large bounds
        UpdateAllEntitiesBatched(false)
    elseif enabled and cv_enabled:GetBool() then
        -- If enabling PVS, immediately update the PVS
        print("[RTX Fixes] PVS optimization enabled, updating bounds based on PVS")
        UpdatePlayerPVS()
        UpdateAllEntitiesBatched(false)
    end
end)

cvars.AddChangeCallback("fr_enabled", function(_, _, new)
    local enabled = tobool(new)
    
    if enabled then
        -- System is being enabled
        
        -- Reset PVS tracking when enabling
        entitiesInPVS = setmetatable({}, weakEntityTable)
        
        -- Initial PVS update if PVS optimization is enabled
        if cv_use_pvs:GetBool() and NikNaks and NikNaks.CurrentMap then
            UpdatePlayerPVS()
        end
        
        -- Store original static prop setting
        if not RTX_FRUSTUM_ORIGINAL_PROP_SETTING then
            RTX_FRUSTUM_ORIGINAL_PROP_SETTING = GetConVar("r_drawstaticprops"):GetInt()
        end
        
        -- Make sure hooks are installed properly
        ReinstallSafeHooks()
        
        UpdateAllEntitiesBatched(false)
        CreateStaticProps()
    else
        -- System is being disabled - use complete shutdown
        CompleteRTXSystemShutdown()
    end
end)

cvars.AddChangeCallback("fr_bounds_size", function(_, _, new)
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        UpdateBoundsVectors(tonumber(new))
        
        if cv_enabled:GetBool() then
            UpdateAllEntitiesBatched(false)
            CreateStaticProps()
        end
    end)
end)


cvars.AddChangeCallback("fr_rtx_distance", function(_, _, new)
    if not cv_enabled:GetBool() then return end
    
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        local rtxDistance = tonumber(new)
        local rtxBoundsSize = Vector(rtxDistance, rtxDistance, rtxDistance)
        
        -- Only update non-environment light updaters
        for ent in pairs(rtxUpdaterCache) do
            if IsValid(ent) then
                -- Explicitly skip environment lights
                if ent.lightType ~= "light_environment" then
                    ent:SetRenderBounds(-rtxBoundsSize, rtxBoundsSize)
                end
            else
                RemoveFromRTXCache(ent)
            end
        end
    end)
end)

-- Separate callback for environment light distance changes
cvars.AddChangeCallback("fr_environment_light_distance", function(_, _, new)
    if not cv_enabled:GetBool() then return end
    
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        local envDistance = tonumber(new)
        local envBoundsSize = Vector(envDistance, envDistance, envDistance)
        
        -- Only update environment light updaters
        for ent in pairs(rtxUpdaterCache) do
            if IsValid(ent) and ent.lightType == "light_environment" then
                ent:SetRenderBounds(-envBoundsSize, envBoundsSize)
                
                -- Only print if debug is enabled
                if cv_enabled:GetBool() and cv_debug:GetBool() then
                    print(string.format("[RTX Fixes] Updating environment light bounds to %d", envDistance))
                end
            end
        end
    end)
end)

-- ConCommand to refresh all entities' bounds
concommand.Add("fr_refresh", function()
    -- Clear bounds cache
    originalBounds = {}
    
    if cv_enabled:GetBool() then
        boundsSize = cv_bounds_size:GetFloat()
        mins = Vector(-boundsSize, -boundsSize, -boundsSize)
        maxs = Vector(boundsSize, boundsSize, boundsSize)
        
        UpdateAllEntitiesBatched(false)
        CreateStaticProps()
    else
        UpdateAllEntitiesBatched(true)
    end
    
    print("Refreshed render bounds for all entities" .. (cv_enabled:GetBool() and " with large bounds" or " with original bounds"))
end)

-- Entity cleanup
hook.Add("EntityRemoved", "CleanupRTXCache", function(ent)
    RemoveFromRTXCache(ent)
    originalBounds[ent] = nil
end)

-- Cleanup Timer
timer.Create("FR_EntityCleanup", 60, 0, CleanupInvalidEntities)

-- Debug command
concommand.Add("fr_debug", function()
    print("\nRTX Frustum Optimization Debug:")
    print("Enabled:", cv_enabled:GetBool())
    print("Bounds Size:", cv_bounds_size:GetFloat())
    print("RTX Updater Distance:", cv_rtx_updater_distance:GetFloat())
    print("Static Props Count:", #staticProps)
    print("Stored Original Bounds:", table.Count(originalBounds))
    print("RTX Updaters (Cached):", rtxUpdaterCount)
    
    -- Special entities debug info
    print("\nSpecial Entity Classes:")
    for class, data in pairs(SPECIAL_ENTITY_BOUNDS) do
        print(string.format("  %s: %d units (%s)", 
            class, 
            data.size, 
            data.description))
    end
end)

local function CreateSettingsPanel(panel)
    -- Clear the panel first
    panel:ClearControls()
    
    -- Main toggle
    panel:CheckBox("Enable RTX View Frustum", "fr_enabled")
    panel:ControlHelp("Enables optimized render bounds for all entities")
    
    panel:Help("")
    
    -- Advanced settings toggle
    local advancedToggle = panel:CheckBox("Show Advanced Settings", "fr_show_advanced")
    panel:ControlHelp("Enable manual control of render bounds (Use with caution!)")
    
    -- Create a container for advanced settings
    local advancedPanel = vgui.Create("DPanel", panel)
    advancedPanel:Dock(TOP)
    advancedPanel:DockMargin(8, 8, 8, 8)
    advancedPanel:SetPaintBackground(false)
    advancedPanel:SetVisible(cv_show_advanced:GetBool())
    advancedPanel:SetTall(200) -- Adjust height as needed
    
    -- Advanced settings content
    local advancedContent = vgui.Create("DScrollPanel", advancedPanel)
    advancedContent:Dock(FILL)
    
    -- Regular entity bounds
    local boundsGroup = vgui.Create("DForm", advancedContent)
    boundsGroup:Dock(TOP)
    boundsGroup:DockMargin(0, 0, 0, 5)
    boundsGroup:SetName("Entity Bounds")
    
    local boundsSlider = boundsGroup:NumSlider("Regular Entity Bounds", "fr_bounds_size", 256, 32000, 0)
    boundsSlider:SetTooltip("Size of render bounds for regular entities")

    -- Light settings
    local lightGroup = vgui.Create("DForm", advancedContent)
    lightGroup:Dock(TOP)
    lightGroup:DockMargin(0, 0, 0, 5)
    lightGroup:SetName("Light Settings")
    
    local rtxDistanceSlider = lightGroup:NumSlider("Regular Light Distance", "fr_rtx_distance", 256, 32000, 0)
    rtxDistanceSlider:SetTooltip("Maximum render distance for regular RTX light updaters")
    
    local envLightSlider = lightGroup:NumSlider("Environment Light Distance", "fr_environment_light_distance", 16384, 65536, 0)
    envLightSlider:SetTooltip("Maximum render distance for environment light updaters")
    
    -- Warning text
    local warningLabel = vgui.Create("DLabel", advancedContent)
    warningLabel:Dock(TOP)
    warningLabel:DockMargin(5, 5, 5, 5)
    warningLabel:SetTextColor(Color(255, 200, 0))
    warningLabel:SetText("Warning: Changing these values may affect performance and visual quality.")
    warningLabel:SetWrap(true)
    warningLabel:SetTall(40)
    
    -- Tools section
    local toolsGroup = vgui.Create("DForm", advancedContent)
    toolsGroup:Dock(TOP)
    toolsGroup:DockMargin(0, 0, 0, 5)
    toolsGroup:SetName("Tools")
    
    local refreshBtn = toolsGroup:Button("Refresh All Bounds")
    function refreshBtn:DoClick()
        RunConsoleCommand("fr_refresh")
        surface.PlaySound("buttons/button14.wav")
    end
    
    -- Debug settings
    panel:Help("\nDebug Settings")
    panel:CheckBox("Show Debug Messages", "fr_debug_messages")
    panel:ControlHelp("Show detailed debug messages in console")
    
    -- Update advanced panel visibility when the ConVar changes
    cvars.AddChangeCallback("fr_show_advanced", function(_, _, new)
        if IsValid(advancedPanel) then
            advancedPanel:SetVisible(tobool(new))
        end
    end)
end

-- Add to Utilities menu
hook.Add("PopulateToolMenu", "RTXFrustumOptimizationMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "User", "RTX_OVF", "#RTX View Frustum", "", "", function(panel)
        CreateSettingsPanel(panel)
    end)
end)

concommand.Add("fr_add_special_entity", function(ply, cmd, args)
    if not args[1] or not args[2] then
        print("Usage: fr_add_special_entity <class> <size> [description]")
        return
    end
    
    local class = args[1]
    local size = tonumber(args[2])
    local description = args[3] or "Custom entity bounds"
    
    if not size then
        print("Size must be a number!")
        return
    end
    
    AddSpecialEntityBounds(class, size, description)
    print(string.format("Added special entity bounds for %s: %d units", class, size))
end)

local function CountEntitiesByPVSStatus()
    local inPVS = 0
    local outsidePVS = 0
    local specialEntities = 0
    local rtxUpdaters = 0
    
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        
        local entPos = ent:GetPos()
        if not entPos then continue end
        
        if IsRTXUpdater(ent) then
            rtxUpdaters = rtxUpdaters + 1
        elseif GetSpecialBoundsForClass(ent:GetClass()) then
            specialEntities = specialEntities + 1
        elseif currentPVS and currentPVS:TestPosition(entPos) then
            inPVS = inPVS + 1
        else
            outsidePVS = outsidePVS + 1
        end
    end
    
    return inPVS, outsidePVS, specialEntities, rtxUpdaters
end

concommand.Add("fr_debug_pvs", function()
    if not cv_enabled:GetBool() then
        print("[RTX Fixes] PVS optimization system not enabled")
        return
    end

    if not cv_use_pvs:GetBool() then
        print("[RTX Fixes] PVS optimization feature not enabled")
        return
    end
    
    -- Update PVS if needed
    if not currentPVS then
        UpdatePlayerPVS()
        if not currentPVS then
            print("[RTX Fixes] Failed to generate PVS data - NikNaks may not be working")
            return
        end
    end
    
    local inPVS, outsidePVS, specialEntities, rtxUpdaters = CountEntitiesByPVSStatus()
    local total = inPVS + outsidePVS + specialEntities + rtxUpdaters
    
    print("\n--- RTX View Frustum PVS Debug ---")
    print("PVS Optimization: ACTIVE")
    print("Last PVS Update: " .. math.Round(CurTime() - lastPVSUpdateTime, 1) .. " seconds ago")
    print("Total Entities: " .. total)
    print("  • Entities in PVS (large bounds): " .. inPVS .. " (" .. math.Round(inPVS/total*100) .. "%)")
    print("  • Entities outside PVS (original bounds): " .. outsidePVS .. " (" .. math.Round(outsidePVS/total*100) .. "%)")
    print("  • Special entities (always large bounds): " .. specialEntities .. " (" .. math.Round(specialEntities/total*100) .. "%)")
    print("  • RTX updaters (custom bounds): " .. rtxUpdaters .. " (" .. math.Round(rtxUpdaters/total*100) .. "%)")
    
    if outsidePVS > 0 then
        print("\nPerformance Impact:")
        print("  • " .. outsidePVS .. " entities are using original render bounds")
        print("  • This should improve performance while maintaining RTX quality")
    end
    
    print("----------------------------------")
end)

concommand.Add("fr_reset_bounds", function()
    print("[RTX Fixes] Performing complete bounds reset...")
    
    -- First restore original bounds for everything
    UpdateAllEntitiesBatched(true)
    
    -- Clear all tracking
    entitiesInPVS = setmetatable({}, weakEntityTable)
    currentPVS = nil
    lastPVSUpdateTime = 0
    
    -- Then if enabled, reapply based on current settings
    if cv_enabled:GetBool() then
        -- Update PVS if using PVS optimization
        if cv_use_pvs:GetBool() and NikNaks and NikNaks.CurrentMap then
            UpdatePlayerPVS()
        end
        
        -- Apply new bounds
        UpdateAllEntitiesBatched(false)
    end
    
    print("[RTX Fixes] Bounds reset complete")
end)

function CompleteRTXSystemShutdown()
    print("[RTX Fixes] Performing COMPLETE SYSTEM SHUTDOWN...")
    
    -- 1. Remove all hooks first to prevent any further processing
    local hooksToRemove = {
        "OnEntityCreated.SetLargeRenderBounds",
        "Think.RTX_PVS_BatchProcessor",
        "Think.UpdateRTXPVSState",
        "Think.RTXPVSFrameTimeTracker",
        "HUDPaint.RTXPVSDebugHUD"
    }
    
    for _, hookName in ipairs(hooksToRemove) do
        local event, identifier = string.match(hookName, "([^.]+)%.(.+)")
        if event and identifier then
            hook.Remove(event, identifier)
            print("  • Removed hook: " .. event .. "." .. identifier)
        end
    end
    
    -- 2. Clear all timers
    local timersToRemove = {
        "FR_BoundsUpdate", 
        "FR_RTXUpdate", 
        "FR_EntityCleanup",
        "RTX_PVS_EntityProcessing", 
        "RTX_PVS_StaticPropProcessing"
    }
    
    for _, timerName in ipairs(timersToRemove) do
        if timer.Exists(timerName) then
            timer.Remove(timerName)
            print("  • Removed timer: " .. timerName)
        end
    end
    
    -- 3. Reset all entity bounds
    local resetCount = 0
    for ent, bounds in pairs(originalBounds) do
        if IsValid(ent) then
            ent:SetRenderBounds(bounds.mins, bounds.maxs)
            -- Also ensure no matrices or rendering states are left
            ent:DisableMatrix("RenderMultiply")
            ent:SetNoDraw(false)
            resetCount = resetCount + 1
        end
    end
    
    -- 4. Apply conservative bounds to all other entities
    local fallbackCount = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not originalBounds[ent] then
            -- Skip special entities
            if not SPECIAL_ENTITIES[ent:GetClass()] then
                -- Use smaller bounds for better culling
                local defaultBounds = Vector(16, 16, 16)
                ent:SetRenderBounds(-defaultBounds, defaultBounds)
                fallbackCount = fallbackCount + 1
            end
        end
    end
    
    -- 5. Remove all static props
    local propsRemoved = 0
    for prop, _ in pairs(staticProps) do
        if IsValid(prop) then
            prop:Remove()
            propsRemoved = propsRemoved + 1
        end
    end
    staticProps = {}
    
    -- 6. Clear all caches and state
    entitiesInPVS = setmetatable({}, weakEntityTable)
    rtxUpdaterCache = setmetatable({}, weakEntityTable)
    rtxUpdaterCount = 0
    currentPVS = nil
    lastPVSUpdateTime = 0
    originalBounds = setmetatable({}, weakEntityTable)
    patternCache = {}
    pvs_update_in_progress = false
    boundsInitialized = false
    
    -- 7. Reset engine static props setting
    if RTX_FRUSTUM_ORIGINAL_PROP_SETTING then
        RunConsoleCommand("r_drawstaticprops", tostring(RTX_FRUSTUM_ORIGINAL_PROP_SETTING))
    else
        RunConsoleCommand("r_drawstaticprops", "1")
    end
    
    -- 8. Reset NikNaks integration if possible
    if NikNaks and NikNaks.ResetPVSCache then
        NikNaks.ResetPVSCache()
    end
    
    -- 9. Reset EntityManager if it exists
    if EntityManager then
        if EntityManager.Reset then
            EntityManager.Reset()
        end
        
        -- Force-clear any other EntityManager state that might exist
        if EntityManager.ClearAllPVSData then EntityManager.ClearAllPVSData() end
        if EntityManager.StopAllProcessing then EntityManager.StopAllProcessing() end
    end
    
    print(string.format("[RTX Fixes] System shutdown complete: %d entities reset to original bounds, %d given fallback bounds, %d static props removed", 
        resetCount, fallbackCount, propsRemoved))
    
    -- 10. Re-add necessary hooks with safety checks
    -- This ensures the hooks will only run when the system is enabled
    ReinstallSafeHooks()
end

-- Function to reinstall hooks with proper safety checks
function ReinstallSafeHooks()
    -- OnEntityCreated hook with safety check
    hook.Add("OnEntityCreated", "SetLargeRenderBounds", function(ent)
        if not cv_enabled:GetBool() then return end
        if not IsValid(ent) then return end
        
        timer.Simple(0, function()
            if not cv_enabled:GetBool() then return end
            if IsValid(ent) then
                AddToRTXCache(ent)
                SetEntityBounds(ent, not cv_enabled:GetBool())
            end
        end)
    end)
    
    -- Other hooks with safety checks...
    
    print("[RTX Fixes] Reinstalled hooks with safety checks")
end

concommand.Add("fr_force_reset", CompleteRTXSystemShutdown)