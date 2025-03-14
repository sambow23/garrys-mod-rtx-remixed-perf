-- Disables source engine world rendering and replaces it with chunked mesh rendering instead, fixes engine culling issues. 
-- MAJOR THANK YOU to the creator of NikNaks, a lot of this would not be possible without it.
-- This addon is pretty heavy but it's the best compromise between performance and visual quality we have until better solutions arrive.

if not CLIENT then return end

-- ConVars
local cv_enabled = CreateClientConVar("rtx_fr_enabled", "1", true, false, "Enable large render bounds for all entities")
local cv_bounds_size = CreateClientConVar("rtx_fr_bounds_size", "256", true, false, "Size of render bounds")
local cv_rtx_updater_distance = CreateClientConVar("rtx_fr_rtx_distance", "256", true, false, "Maximum render distance for regular RTX light updaters")
local cv_environment_light_distance = CreateClientConVar("rtx_fr_environment_light_distance", "32768", true, false, "Maximum render distance for environment light updaters")
local cv_debug = CreateClientConVar("rtx_fr_debug_messages", "0", true, false, "Enable debug messages for RTX view frustum optimization")
local cv_use_pvs = CreateClientConVar("rtx_fr_use_pvs", "1", true, false, "Use Potentially Visible Set for render bounds optimization")
local cv_pvs_update_interval = CreateClientConVar("rtx_fr_pvs_update_interval", "5", true, false, "How often to update the PVS data when the player isnt moving (seconds)")
local cv_pvs_hud = CreateClientConVar("rtx_fr_pvs_hud", "0", true, false, "Show HUD information about PVS optimization")
local cv_static_props_pvs = CreateClientConVar("rtx_fr_static_props_pvs", "1", true, false, "Use PVS for static prop optimization")

-- Cache the bounds vectors
local boundsSize = cv_bounds_size:GetFloat()
local mins = Vector(-boundsSize, -boundsSize, -boundsSize)
local maxs = Vector(boundsSize, boundsSize, boundsSize)

-- Cache RTXMath functions
local RTXMath_IsWithinBounds = RTXMath.IsWithinBounds
local RTXMath_DistToSqr = RTXMath.DistToSqr
local RTXMath_CreateVector = RTXMath.CreateVector
local RTXMath_NegateVector = RTXMath.NegateVector

-- Constants and caches
local Vector = Vector
local IsValid = IsValid
local pairs = pairs
local ipairs = ipairs
local DEBOUNCE_TIME = 0.1
local boundsUpdateTimer = "FR_BoundsUpdate"
local rtxUpdaterCache = {}
local rtxUpdaterCount = 0
local mapBounds = {
    min = Vector(-16384, -16384, -16384),
    max = Vector(16384, 16384, 16384)
}
local patternCache = {}
local weakEntityTable = {__mode = "k"} -- Allows garbage collection of invalid entities
originalBounds = setmetatable({}, weakEntityTable)
rtxUpdaterCache = setmetatable({}, weakEntityTable)
local currentPVS = nil
local lastPVSUpdateTime = 0
local entitiesInPVS = setmetatable({}, weakEntityTable)  -- Track which entities were in PVS
local pvs_update_in_progress = false
local MAP_PRESETS = {}
local managedTimers = managedTimers or {}
local currentPVSProgress = 0
local lastTrackedPosition = Vector(0,0,0)
local positionUpdateThreshold = 128  -- Units player must move to trigger update
local bDrawingSkybox = false

-- RTX Light Updater model list
local RTX_UPDATER_MODELS = {
    ["models/hunter/plates/plate.mdl"] = true,
    ["models/hunter/blocks/cube025x025x025.mdl"] = true
}

-- Cache for static props
local staticProps = {}
local originalBounds = {} -- Store original render bounds

local SPECIAL_ENTITIES = {
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

local PRESETS = {
    ["Very Low"] = { entity = 64, light = 256, environment = 32768 },
    ["Low"] = { entity = 256, light = 512, environment = 32768 },
    ["Medium"] = { entity = 512, light = 767, environment = 32768 },
    ["High"] = { entity = 2048, light = 1024, environment = 32768 },
    ["Very High"] = { entity = 4096, light = 2048, environment = 65536 }
}

local SPECIAL_ENTITY_BOUNDS = {
    ["prop_door_rotating"] = {
        size = 512,
        description = "Door entities",
    },

    ["func_door_rotating"] = {
        size = 512,
        description = "func_ entities",
    },

    ["func_physbox"] = {
        size = 512,
        description = "func_ entities",
    },

    ["func_breakable"] = {
        size = 512,
        description = "func_ entities",
    },

    ["func_brush"] = {
        size = 32768, -- this is so cursed, but it prevents rendering issues
        description = "func_ entities",
    },

    ["func_lod"] = {
        size = 32768, -- this is so cursed, but it prevents rendering issues
        description = "func_ entities",
    },

    ["^npc_%w+"] = {
        size = 512,
        description = "All npc_ entities",
        isPattern = true
    },

    ["hdri_cube_editor"] = {
        size = 32768,
        description = "HDRI Editor",
        isPattern = false
    }
    -- Add more entities here as needed:
    -- ["entity_class"] = { size = number, description = "description" }
}

-- Statistics tracking
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

-- Hook Management
local managedHooks = {}

local function AddManagedHook(event, name, func)
    -- Remove existing hook if present
    hook.Remove(event, name)
    
    -- Add the new hook
    hook.Add(event, name, func)
    
    -- Track it
    managedHooks[event .. "." .. name] = true
end

local function RemoveAllManagedHooks()
    for hookID in pairs(managedHooks) do
        local event, name = string.match(hookID, "([^.]+)%.(.+)")
        if event and name then
            hook.Remove(event, name)
        end
    end
    managedHooks = {}
end

-- State Management
local processingState = {
    pvs = { active = false, startTime = 0, lastCompleteTime = 0 },
    staticProps = { active = false, startTime = 0, lastCompleteTime = 0 },
    entities = { active = false, startTime = 0, lastCompleteTime = 0 }
}

local RTX_SYSTEM = {
    active = false,           -- Whether the system is turned on
    initialized = false,      -- If initial setup was completed
    lastPVSUpdate = 0,        -- Last PVS update timestamp
    processingUpdate = false  -- Flag to prevent concurrent updates
}

function SafeCall(funcName, func, ...)
    if not func then
        if cv_debug:GetBool() then
            print("[RTX Remix Fixes 2 - Force View Frustrum] Error: Function '" .. funcName .. "' not available")
        end
        return nil
    end
    
    local success, result = pcall(func, ...)
    if not success then
        if cv_debug:GetBool() then
            print("[RTX Remix Fixes 2 - Force View Frustrum] Error in '" .. funcName .. "': " .. tostring(result))
        end
        return nil
    end
    
    return result
end

function ClearTable(tbl)
    local mt = getmetatable(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
    return tbl
end

local function beginProcessing(category)
    -- Check if any other critical process is running
    if processingState.pvs.active or 
       (category ~= "pvs" and processingState[category].active) then
        return false
    end
    
    processingState[category].active = true
    processingState[category].startTime = SysTime()
    return true
end

local function endProcessing(category)
    processingState[category].active = false
    processingState[category].lastCompleteTime = SysTime()
end

-- Helper Functions

function IsEntityNearPlayer(ent, maxDistance)
    if not IsValid(ent) or not IsValid(LocalPlayer()) then return false end
    
    local playerPos = LocalPlayer():GetPos()
    local entPos = ent:GetPos()
    local distSq = playerPos:DistToSqr(entPos)
    
    return distSq < (maxDistance * maxDistance)
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
    -- Default to "Low" if no preset specified
    presetName = presetName or "Low"
    
    local preset = PRESETS[presetName]
    if not preset then return end
    
    RunConsoleCommand("rtx_fr_bounds_size", tostring(preset.entity))
    RunConsoleCommand("rtx_fr_rtx_distance", tostring(preset.light))
    RunConsoleCommand("rtx_fr_environment_light_distance", tostring(preset.environment))
end

local function UpdateStaticPropBounds(prop, inPVS)
    if not IsValid(prop) then return false end
    
    if inPVS then
        -- In PVS: use large bounds for RTX lighting
        prop:SetRenderBounds(mins, maxs)
        prop:SetNoDraw(false)
    else
        -- Out of PVS: use small bounds for performance
        local smallBounds = Vector(1, 1, 1)
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
        print("[RTX Remix Fixes 2 - Force View Frustrum] Cleaned up " .. removed .. " invalid entity references")
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
                print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Static prop PVS update complete: %.2f ms, %d props, %d in PVS",
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

                if className:find("prop_physics") then
                    -- Force it to be considered in PVS
                    entitiesInPVS[ent] = true
                    -- Apply large bounds
                    ent:SetRenderBounds(mins, maxs)
                    -- Skip normal PVS processing
                    continue
                end

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
    if not RTX_SYSTEM.active or not cv_use_pvs:GetBool() then return end
    if pvs_update_in_progress then return end
    
    local player = LocalPlayer()
    if not IsValid(player) then return end
    local playerPos = player:GetPos()
    
    -- Debug output with player position
    if cv_debug:GetBool() then
        print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] PVS update initiated from position: %.1f, %.1f, %.1f", 
            playerPos.x, playerPos.y, playerPos.z))
    end
    
    -- Set flags to prevent concurrent updates
    pvs_update_in_progress = true
    
    -- Always update tracked position
    lastPlayerPos = playerPos
    
    -- Generate fresh PVS data directly from current position
    local pvs = NikNaks.CurrentMap:PVSForOrigin(playerPos)
    if not pvs then
        pvs_update_in_progress = false
        if cv_debug:GetBool() then
            print("[RTX Remix Fixes 2 - Force View Frustrum] Failed to generate PVS - NikNaks returned nil")
        end
        return
    end
    
    -- Store the new PVS
    currentPVS = pvs
    
    -- Get leaf data
    local leafPositions = {}
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
                table.insert(leafPositions, center)
            end
        end
    end
    
    -- Update statistics
    stats.pvsLeafCount = #leafPositions
    stats.totalLeafCount = table.Count(NikNaks.CurrentMap:GetLeafs())
    
    -- Push leafs to optimized system
    EntityManager.SetPVSLeafData_Optimized(leafPositions, playerPos)
    
    -- Process entities
    pvs_stats.startTime = SysTime()
    pvs_stats.processedEntities = 0
    StartEntityProcessingTimer()
    
    -- Also force update for static props
    if cv_static_props_pvs:GetBool() then
        timer.Simple(0.1, function() 
            UpdateStaticPropsPVS() 
        end)
    end
    
    pvs_update_in_progress = false
    lastPVSUpdateTime = CurTime()
end

-- Replace the original UpdatePlayerPVS function with the new one
UpdatePlayerPVS = UpdatePVSWithNative

function UpdateStaticPropsPVS()
    if not RTX_SYSTEM.active or not cv_static_props_pvs:GetBool() then return end
    
    -- Exit early if no static props
    local propCount = 0
    for _ in pairs(staticProps) do propCount = propCount + 1 end
    
    if propCount == 0 then 
        stats.staticPropsInPVS = 0
        stats.staticPropsTotal = 0
        if cv_debug:GetBool() then
            print("[RTX Remix Fixes 2 - Force View Frustrum] No static props to process")
        end
        return 
    end
    
    -- Build prop arrays for batch processing
    local propPositions = {}
    local propEntities = {}
    
    for prop, data in pairs(staticProps) do
        if IsValid(prop) then
            table.insert(propEntities, prop)
            table.insert(propPositions, data.pos)
        end
    end
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Processing %d static props for PVS", #propEntities))
    end
    
    -- Do direct PVS testing if EntityManager isn't available or working
    if not EntityManager or not EntityManager.BeginPVSEntityBatchProcessing then
        -- Fallback direct method
        local playerPos = LocalPlayer():GetPos()
        local updateCount = 0
        local inPVSCount = 0
        
        for i, prop in ipairs(propEntities) do
            local pos = propPositions[i]
            -- First check distance - anything close to player is automatically in PVS
            local inPVS = pos:DistToSqr(playerPos) < (1024 * 1024) -- Reduced distance threshold
            
            -- If not close, try using PVS system
            if not inPVS and currentPVS then
                inPVS = currentPVS:TestPosition(pos)
            end
            
            if IsValid(prop) and staticProps[prop] then
                if inPVS then inPVSCount = inPVSCount + 1 end
                
                if inPVS ~= staticProps[prop].inPVS then
                    UpdateStaticPropBounds(prop, inPVS)
                    staticProps[prop].inPVS = inPVS
                    updateCount = updateCount + 1
                end
            end
        end
        
        -- Force stats update
        stats.staticPropsInPVS = inPVSCount
        stats.staticPropsTotal = #propEntities
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Static prop PVS update complete (direct): %d props, %d in PVS, %d changed",
                stats.staticPropsTotal,
                stats.staticPropsInPVS,
                updateCount))
        end
        return
    end
    
    -- Use batched processing if EntityManager is available
    local batchSize = 250
    EntityManager.BeginPVSEntityBatchProcessing(propEntities, propPositions, mins, maxs, batchSize)
    
    -- Process all batches for static props
    local processedCount = 0
    local changedCount = 0
    
    while EntityManager.IsPVSUpdateInProgress() do
        local results, complete = EntityManager.ProcessNextEntityBatch()
        
        for i, isInPVS in ipairs(results) do
            local prop = propEntities[processedCount + i]
            if IsValid(prop) and staticProps[prop] then
                if isInPVS ~= staticProps[prop].inPVS then
                    UpdateStaticPropBounds(prop, isInPVS)
                    staticProps[prop].inPVS = isInPVS
                    changedCount = changedCount + 1
                end
            end
        end
        
        processedCount = processedCount + #results
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
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Static prop PVS update complete: %d props, %d in PVS, %d changed",
            stats.staticPropsTotal,
            stats.staticPropsInPVS,
            changedCount))
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
    
    -- First check if this is a light entity we haven't identified yet
    if not rtxUpdaterCache[ent] and not useOriginal then
        local className = ent:GetClass()
        local model = ent:GetModel()
        
        -- Check for light entities that were previously missed
        if SPECIAL_ENTITIES[className] or 
           (model and RTX_UPDATER_MODELS[model]) or
           string.find(className or "", "light") or
           ent.lightType then
            
            -- Add to cache and apply bounds right away
            rtxUpdaterCache[ent] = true
            rtxUpdaterCount = rtxUpdaterCount + 1
            
            -- Skip further processing - UpdateRTXLightUpdaters handles this now
            if cv_debug:GetBool() then
                print("[RTX Remix Fixes 2 - Force View Frustrum] Late-detected light entity: " .. className)
            end
            
            -- Force an immediate update
            local envSize = cv_environment_light_distance:GetFloat()
            local rtxDistance = cv_rtx_updater_distance:GetFloat()
            
            if ent.lightType == LIGHT_TYPES.ENVIRONMENT then
                local envBounds = Vector(envSize, envSize, envSize)
                ent:SetRenderBounds(-envBounds, envBounds)
            else
                local rtxBounds = Vector(rtxDistance, rtxDistance, rtxDistance)
                ent:SetRenderBounds(-rtxBounds, rtxBounds)
            end
            ent:SetRenderMode(GetConVar("rtx_lightupdater_show"):GetBool() and 0 or 2)
            ent:SetColor(Color(255, 255, 255, GetConVar("rtx_lightupdater_show"):GetBool() and 255 or 1))
            ent:DisableMatrix("RenderMultiply")
            ent:SetNoDraw(false)
            return
        end
    end
    
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
            print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Special entity bounds applied (%s): %d%s", 
                className, size, patternText))
        end
        return
        
    -- RTX updaters - always handle separately
    elseif rtxUpdaterCache[ent] then
    -- Completely separate handling for environment lights
    if ent.lightType == LIGHT_TYPES.ENVIRONMENT then
        local envSize = cv_environment_light_distance:GetFloat()
        local envBounds = RTXMath_CreateVector(envSize, envSize, envSize)
        local negEnvBounds = RTXMath_NegateVector(envBounds)
        
        -- Always use full bounds regardless of distance
        ent:SetRenderBounds(negEnvBounds, envBounds)
        
        -- Only print if debug is enabled
        if cv_enabled:GetBool() and cv_debug:GetBool() then
            print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Environment light bounds: %d", envSize))
        end
        
    elseif REGULAR_LIGHT_TYPES[ent.lightType] then
        local rtxDistance = cv_rtx_updater_distance:GetFloat()
        local rtxBounds = RTXMath_CreateVector(rtxDistance, rtxDistance, rtxDistance)
        local negRtxBounds = RTXMath_NegateVector(rtxBounds)
        
        -- Always use full bounds regardless of distance
        ent:SetRenderBounds(negRtxBounds, rtxBounds)
        
        -- Only print if debug is enabled
        if cv_enabled:GetBool() and cv_debug:GetBool() then
            print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Regular light bounds (%s): %d", 
                ent.lightType, rtxDistance))
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

            local nearPlayerDistance = 2048 -- Adjust as needed
            if IsEntityNearPlayer(ent, nearPlayerDistance) then
                ent:SetRenderBounds(mins, maxs)
                return
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
    
    -- Prioritize entities by importance
    local function SortByPriority(entities)
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
            if rtxUpdaterCache[ent] or 
               SPECIAL_ENTITIES[className] or 
               GetSpecialBoundsForClass(className) or
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
        
        -- Combine in priority order
        local result = {}
        for _, ent in ipairs(highPriority) do table.insert(result, ent) end
        for _, ent in ipairs(normalPriority) do table.insert(result, ent) end
        for _, ent in ipairs(lowPriority) do table.insert(result, ent) end
        
        return result, #highPriority, #normalPriority
    end
    
    -- Sort entities by priority
    local sortedEntities, highCount, normalCount = SortByPriority(allEntities)
    
    -- Use adaptive batch sizing based on system performance
    local baseSize = 250 -- Larger base batch size
    local batchSize = baseSize
    local frameTimeHistory = {}
    local maxProcessTime = 8 -- ms per frame max to spend on processing
    local interBatchDelay = 0.01 -- Reduced delay between batches
    
    -- Start with aggressive batch size, then adapt
    local currentBatch = 1
    local totalBatches = math.ceil(#sortedEntities / batchSize)
    
    local function ProcessNextBatch()
        local startTime = SysTime()
        
        -- Calculate current batch range
        local startIdx = (currentBatch - 1) * batchSize + 1
        local endIdx = math.min(startIdx + batchSize - 1, #sortedEntities)
        
        -- Process this batch
        for i = startIdx, endIdx do
            local ent = sortedEntities[i]
            if IsValid(ent) then
                SetEntityBounds(ent, useOriginal)
            end
        end
        
        -- Measure processing time
        local processingTime = (SysTime() - startTime) * 1000 -- ms
        table.insert(frameTimeHistory, processingTime)
        if #frameTimeHistory > 5 then table.remove(frameTimeHistory, 1) end
        
        -- Calculate average processing time
        local avgTime = 0
        for _, time in ipairs(frameTimeHistory) do
            avgTime = avgTime + time
        end
        avgTime = avgTime / #frameTimeHistory
        
        -- Adapt batch size based on performance
        if avgTime < maxProcessTime * 0.5 then
            -- Processing is very fast, increase batch size
            batchSize = math.min(batchSize * 1.5, 1000)
            -- Reduce delay for fast systems
            interBatchDelay = 0
        elseif avgTime > maxProcessTime then
            -- Too slow, reduce batch size
            batchSize = math.max(batchSize * 0.75, 50)
            -- Add small delay to prevent stuttering
            interBatchDelay = 0.02
        end
        
        -- Update progress for high-priority entities
        if startIdx <= highCount then
            local progress = math.min(endIdx, highCount) / highCount
            if cv_debug:GetBool() then
                print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Processing high-priority entities: %.0f%%", progress * 100))
            end
        end
        
        -- Advance to next batch
        currentBatch = currentBatch + 1
        
        -- Continue processing if more batches remain
        if currentBatch <= totalBatches then
            -- Use adaptive delay
            if interBatchDelay > 0 then
                timer.Simple(interBatchDelay, ProcessNextBatch)
            else
                -- For high-end systems, process immediately
                ProcessNextBatch()
            end
        else
            if cv_debug:GetBool() then
                print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Entity processing complete: %d entities in %.1f ms per batch", 
                    #sortedEntities, avgTime))
            end
        end
    end
    
    -- Start processing
    ProcessNextBatch()
end

-- Create clientside static props
local function CreateStaticProps()
    -- Clean up existing props
    for _, prop in pairs(staticProps) do
        if IsValid(prop) then prop:Remove() end
    end
    staticProps = setmetatable({}, weakEntityTable)
    
    -- Skip if disabled or dependencies missing
    if not (cv_enabled:GetBool() and NikNaks and NikNaks.CurrentMap) then return end
    
    -- Detect system capabilities (FPS-based adaptive limit)
    local systemPerformance = 1.0
    if stats.frameTimeAvg > 0 then
        systemPerformance = math.Clamp(16.7 / stats.frameTimeAvg, 0.5, 2.0)
    end
    
    -- Apply limits based on performance
    local props = NikNaks.CurrentMap:GetStaticProps()
    local batchSize = math.floor(50 * systemPerformance)
    local maxProps = math.floor(1000 * systemPerformance)
    local propCount = 0
    
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
                print("[RTX Remix Fixes 2 - Force View Frustrum] Created " .. propCount .. " static props")
            end
        end
    end
    
    -- Start batch processing
    ProcessBatch(1)
    
    -- Save original setting in a global to restore later
    RTX_FRUSTUM_ORIGINAL_PROP_SETTING = originalPropSetting
end


function ResetAndUpdateBounds(preserveOriginals)
    -- Stop any ongoing processing
    RTX_SYSTEM.processingUpdate = true
    
    -- Cancel any pending update timers
    for timerName in pairs(managedTimers) do
        if timer.Exists(timerName) then
            timer.Remove(timerName)
        end
    end
    
    -- First restore all original bounds to prevent leaks
    local entitiesWithOriginals = {}
    for ent, bounds in pairs(originalBounds) do
        if IsValid(ent) then
            -- Store for later if we need to update them
            table.insert(entitiesWithOriginals, ent)
            
            -- Restore original bounds temporarily
            ent:SetRenderBounds(bounds.mins, bounds.maxs)
        end
    end
    
    -- Clear caches while preserving weak tables
    if not preserveOriginals then
        for k in pairs(originalBounds) do originalBounds[k] = nil end
    end
    for k in pairs(entitiesInPVS) do entitiesInPVS[k] = nil end
    
    -- Update cached vectors for new bounds size
    boundsSize = cv_bounds_size:GetFloat()
    mins = Vector(-boundsSize, -boundsSize, -boundsSize)
    maxs = Vector(boundsSize, boundsSize, boundsSize)
    
    -- Reset PVS data
    currentPVS = nil
    lastPVSUpdateTime = 0
    pvs_update_in_progress = false
    
    -- If system is active, update all bounds
    if RTX_SYSTEM.active then
        -- First update RTX light updaters with new settings
        UpdateRTXLightUpdaters()
        
        -- Then batch update all entities
        UpdateAllEntitiesBatched(false)
        
        -- Recreate static props if needed
        CreateStaticProps()
    end
    
    -- Allow processing again
    RTX_SYSTEM.processingUpdate = false
    
    if cv_debug:GetBool() then
        print("[RTX Remix Fixes 2 - Force View Frustrum] Reset and updated all entity bounds with new settings")
    end
end

function ScanEntireMapForLights()
    if not RTX_SYSTEM.active then return end
    
    local startTime = SysTime()
    local newLightsFound = 0
    local totalEntities = 0
    
    -- Check ALL entities on the map
    for _, ent in ipairs(ents.GetAll()) do
        totalEntities = totalEntities + 1
        
        if IsValid(ent) and not rtxUpdaterCache[ent] then
            local className = ent:GetClass()
            local model = ent:GetModel()
            
            -- Check if it's a light entity we missed
            if SPECIAL_ENTITIES[className] or 
               (model and RTX_UPDATER_MODELS[model]) or
               string.find(className or "", "light") or
               ent.lightType then
                
                -- Add to our cache and apply bounds immediately
                rtxUpdaterCache[ent] = true
                rtxUpdaterCount = rtxUpdaterCount + 1
                newLightsFound = newLightsFound + 1
                
                -- Apply appropriate bounds based on light type
                if ent.lightType == LIGHT_TYPES.ENVIRONMENT then
                    local envSize = cv_environment_light_distance:GetFloat()
                    local envBounds = Vector(envSize, envSize, envSize)
                    ent:SetRenderBounds(-envBounds, envBounds)
                else
                    local rtxDistance = cv_rtx_updater_distance:GetFloat()
                    local rtxBounds = Vector(rtxDistance, rtxDistance, rtxDistance)
                    ent:SetRenderBounds(-rtxBounds, rtxBounds)
                end
                
                -- Force visibility settings
                ent:DisableMatrix("RenderMultiply")
                ent:SetNoDraw(false)
                
                if GetConVar("rtx_lightupdater_show"):GetBool() then
                    ent:SetRenderMode(0)
                    ent:SetColor(Color(255, 255, 255, 255))
                else
                    ent:SetRenderMode(2)
                    ent:SetColor(Color(255, 255, 255, 1))
                end
            end
        end
    end
    
    local endTime = SysTime()
    
    if cv_debug:GetBool() or newLightsFound > 0 then
        print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Full map light scan: Found %d new lights out of %d entities (%.2f ms)",
            newLightsFound, totalEntities, (endTime - startTime) * 1000))
    end
    
    return newLightsFound
end

-- Hooks
AddManagedHook("Initialize", "LoadRTXFrustumMapPresets", LoadMapPresets)

AddManagedHook("InitPostEntity", "ApplyMapRTXPreset", function()
    timer.Simple(1, function()
        local currentMap = game.GetMap()
        if MAP_PRESETS[currentMap] then
            ApplyPreset(MAP_PRESETS[currentMap])
        else
            -- Default to Low preset for maps without configuration
            ApplyPreset("Low")
        end
    end)
end)

AddManagedHook("OnEntityCreated", "SetLargeRenderBounds", function(ent)
    if not RTX_SYSTEM.active or not IsValid(ent) then return end
    
    timer.Simple(0, function()
        if IsValid(ent) then
            AddToRTXCache(ent)
            SetEntityBounds(ent, not cv_enabled:GetBool())
        end
    end)
end)

-- Initial setup
AddManagedHook("InitPostEntity", "InitialBoundsSetup", function()
    timer.Simple(1, function()
        RTX_SYSTEM.active = cv_enabled:GetBool()
        RTX_SYSTEM.initialized = true
        
        if RTX_SYSTEM.active then
            -- Initial PVS update if PVS optimization is enabled
            if cv_use_pvs:GetBool() and NikNaks and NikNaks.CurrentMap then
                UpdatePlayerPVS()
            end
            
            UpdateAllEntitiesBatched(false)
            CreateStaticProps()
        end
    end)
end)

-- Catch all map lights
hook.Add("InitPostEntity", "RTXLightsMultiPhaseInitialization", function()
    -- Initial scan - soon after map loads
    timer.Simple(1, function()
        if RTX_SYSTEM.active then
            UpdateRTXLightUpdaters()
        end
    end)
    
    -- Secondary scan to catch entities that initialize later
    timer.Simple(3, function()
        if RTX_SYSTEM.active then
            ScanEntireMapForLights()
        end
    end)
    
    -- Tertiary scan for really late-initializing entities
    timer.Simple(7, function()
        if RTX_SYSTEM.active then
            ScanEntireMapForLights()
        end
    end)
end)

AddManagedHook("Think", "RTX_PVS_BatchProcessor", function()
    if not RTX_SYSTEM.active or not cv_use_pvs:GetBool() then return end
    
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
                    if ent:GetClass():find("prop_physics") then
                        entitiesInPVS[ent] = true
                        SetEntityBounds(ent, false)
                        continue
                    end
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
                print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] PVS update complete: %.2f ms, %d entities", 
                    pvs_stats.processingTime * 1000, pvs_stats.totalEntities))
            end
            
            -- Also update static props if enabled
            if cv_static_props_pvs:GetBool() then
                UpdateStaticPropsPVS()
            end
        end
    end
end)

AddManagedHook("Think", "UpdateRTXPVSState", function()
    if not RTX_SYSTEM.active or not cv_use_pvs:GetBool() then return end
    
    local currentTime = CurTime()
    local updateInterval = cv_pvs_update_interval:GetFloat()
    
    -- Check if it's time for a PVS update
    if currentTime - lastPVSUpdateTime > updateInterval then
        -- Save time before update for accurate displays
        local updateStartTime = SysTime()
        
        -- Run the update
        UpdatePlayerPVS()
        
        -- If we have the HUD enabled, update stats
        if cv_pvs_hud:GetBool() then
            stats.updateTime = SysTime() - updateStartTime
        end
        
        -- Force static prop update after a regular PVS update
        if cv_static_props_pvs:GetBool() and not pvs_update_in_progress then
            UpdateStaticPropsPVS()
        end
    end
    
    -- Update the progress display for HUD if entities are being processed
    if cv_pvs_hud:GetBool() and pvs_stats.inProgress then
        -- We need to manually calculate progress
        local progress = pvs_stats.processedEntities / math.max(1, pvs_stats.totalEntities)
        currentPVSProgress = progress
    end
end)

AddManagedHook("Think", "RTX_PlayerPositionTracking", function()
    if not RTX_SYSTEM.active or not cv_use_pvs:GetBool() then return end
    
    local player = LocalPlayer()
    if not IsValid(player) then return end
    
    local currentPos = player:GetPos()
    local moveDistance = currentPos:Distance(lastTrackedPosition)
    
    -- Force PVS update if player moved enough
    if moveDistance > positionUpdateThreshold then
        if cv_debug:GetBool() then
            print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Player moved %.1f units - forcing PVS update", moveDistance))
        end
        
        -- Clear cached states to force fresh calculation
        currentPVS = nil
        lastPlayerPos = nil
        lastPVSUpdateTime = 0
        
        -- Force immediate update
        UpdatePlayerPVS()
        
        -- Update tracked position
        lastTrackedPosition = currentPos
    end
end)

-- Map cleanup/reload handler
AddManagedHook("OnReloaded", "RefreshStaticProps", function()
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

AddManagedHook("OnMapChange", "ClearRTXPVSCache", function()
    currentPVS = nil
    lastPVSUpdateTime = 0
end)

-- Track frame times when HUD is enabled
AddManagedHook("Think", "RTXPVSFrameTimeTracker", function()
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

AddManagedHook("HUDPaint", "RTXPVSDebugHUD", function()
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
        local progress = EntityManager.GetPVSProgress and EntityManager.GetPVSProgress() or currentPVSProgress
        progress = progress * 100
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


-- Hook States
function UpdateRTXLightUpdaters()
    if not RTX_SYSTEM.active then return end
    
    -- Clear existing cache but maintain the weak table
    for k in pairs(rtxUpdaterCache) do rtxUpdaterCache[k] = nil end
    rtxUpdaterCount = 0
    
    local updatedCount = 0
    local environmentLightCount = 0
    local regularLightCount = 0
    
    -- Find and process all potential RTX updaters
    for className, _ in pairs(SPECIAL_ENTITIES) do
        for _, ent in ipairs(ents.FindByClass(className)) do
            if IsValid(ent) then
                rtxUpdaterCache[ent] = true
                rtxUpdaterCount = rtxUpdaterCount + 1
                updatedCount = updatedCount + 1
                
                if ent.lightType == LIGHT_TYPES.ENVIRONMENT then
                    -- Use environment light size
                    local envSize = cv_environment_light_distance:GetFloat()
                    local envBounds = Vector(envSize, envSize, envSize)
                    ent:SetRenderBounds(-envBounds, envBounds)
                    environmentLightCount = environmentLightCount + 1
                else
                    -- Default to regular light size for all other lights
                    local rtxDistance = cv_rtx_updater_distance:GetFloat()
                    local rtxBounds = Vector(rtxDistance, rtxDistance, rtxDistance)
                    ent:SetRenderBounds(-rtxBounds, rtxBounds)
                    regularLightCount = regularLightCount + 1
                end
                
                -- Apply render settings
                ent:DisableMatrix("RenderMultiply")
                
                -- Force visibility
                ent:SetNoDraw(false)
                ent:SetRenderMode(GetConVar("rtx_lightupdater_show"):GetBool() and 0 or 2)
                ent:SetColor(Color(255, 255, 255, GetConVar("rtx_lightupdater_show"):GetBool() and 255 or 1))
            end
        end
    end
    
    -- Find by model with no distance checking
    for model, _ in pairs(RTX_UPDATER_MODELS) do
        for _, ent in ipairs(ents.FindByModel(model)) do
            if IsValid(ent) and not rtxUpdaterCache[ent] then
                rtxUpdaterCache[ent] = true
                rtxUpdaterCount = rtxUpdaterCount + 1
                updatedCount = updatedCount + 1
                
                -- Always apply maximum bounds
                local rtxDistance = cv_rtx_updater_distance:GetFloat()
                local rtxBounds = Vector(rtxDistance, rtxDistance, rtxDistance)
                ent:SetRenderBounds(-rtxBounds, rtxBounds)
                
                -- Force visibility
                ent:DisableMatrix("RenderMultiply")
                ent:SetNoDraw(false)
                regularLightCount = regularLightCount + 1
            end
        end
    end
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Updated bounds for %d RTX light updaters (%d environment, %d regular)", 
            updatedCount, environmentLightCount, regularLightCount))
    end
end

function ResetRTXSystem()
    -- Reset data structures while maintaining weak tables
    for k in pairs(entitiesInPVS) do entitiesInPVS[k] = nil end
    for k in pairs(rtxUpdaterCache) do rtxUpdaterCache[k] = nil end
    rtxUpdaterCount = 0
    
    -- Reset PVS tracking
    currentPVS = nil
    lastPVSUpdateTime = 0
    pvs_update_in_progress = false
    
    -- Reset stats
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
    }
    
    -- Update system state
    RTX_SYSTEM.active = cv_enabled:GetBool()
    RTX_SYSTEM.initialized = true
    RTX_SYSTEM.lastPVSUpdate = 0
    RTX_SYSTEM.processingUpdate = false
end

function DeactivateRTXSystem()
    print("[RTX Remix Fixes 2 - Force View Frustrum] Deactivating RTX view frustum system...")
    
    -- Update system state immediately
    RTX_SYSTEM.active = false
    
    -- 1. Stop all timers
    for timerName in pairs(managedTimers) do
        if timer.Exists(timerName) then
            timer.Remove(timerName)
        end
    end
    
    -- 2. Forcibly remove all clientside static props FIRST
    local propsRemoved = 0
    for prop, _ in pairs(staticProps) do
        if IsValid(prop) then
            -- Force immediate removal
            SafeCall("RemoveStaticProp", function()
                prop:Remove()
                prop = nil  -- Force cleanup
            end)
            propsRemoved = propsRemoved + 1
        end
    end
    
    -- Clear static props table completely and recreate with weak table
    staticProps = {}
    staticProps = setmetatable({}, weakEntityTable)
    
    -- 3. Reset entity bounds - create a complete entity list first
    local allEntities = ents.GetAll()
    local entitiesReset = 0
    
    for _, ent in ipairs(allEntities) do
        if IsValid(ent) then
            if originalBounds[ent] then
                -- Restore original bounds
                ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
                entitiesReset = entitiesReset + 1
            else
                -- For entities without stored bounds, use a reasonable default
                local defaultBounds = Vector(32, 32, 32)
                ent:SetRenderBounds(-defaultBounds, defaultBounds)
            end
            
            -- Remove any render modifiers that might have been applied
            ent:DisableMatrix("RenderMultiply")
            ent:SetNoDraw(false)
        end
    end
    
    -- 4. Clear all caches completely and recreate with weak tables
    entitiesInPVS = {}
    entitiesInPVS = setmetatable({}, weakEntityTable)
    
    rtxUpdaterCache = {}
    rtxUpdaterCache = setmetatable({}, weakEntityTable)
    rtxUpdaterCount = 0
    
    originalBounds = {}
    originalBounds = setmetatable({}, weakEntityTable)
    
    patternCache = {}
    
    -- 5. Reset other state variables
    currentPVS = nil
    lastPVSUpdateTime = 0
    pvs_update_in_progress = false
    
    -- 6. Reset engine static props setting
    if RTX_FRUSTUM_ORIGINAL_PROP_SETTING then
        RunConsoleCommand("r_drawstaticprops", tostring(RTX_FRUSTUM_ORIGINAL_PROP_SETTING))
    else
        RunConsoleCommand("r_drawstaticprops", "1")
    end
    
    -- 7. Force garbage collection
    collectgarbage("collect")
    
    print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] System deactivated: %d entities reset, %d static props removed", 
        entitiesReset, propsRemoved))
    
    -- Return values to help with debugging
    return {
        entitiesReset = entitiesReset,
        propsRemoved = propsRemoved
    }
end

-- Handle ConVar changes
cvars.AddChangeCallback("rtx_fr_static_props_pvs", function(_, _, new)
    local enabled = tobool(new)
    
    -- If toggling static prop PVS, update all static props
    if cv_enabled:GetBool() then
        if enabled then
            print("[RTX Remix Fixes 2 - Force View Frustrum] Static prop PVS optimization enabled")
            -- PVS will be applied on next update
        else
            print("[RTX Remix Fixes 2 - Force View Frustrum] Static prop PVS optimization disabled, using large bounds for all props")
            
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

cvars.AddChangeCallback("rtx_fr_use_pvs", function(_, _, new)
    local enabled = tobool(new)
    
    -- If disabling PVS, reset all entities to large bounds
    if not enabled and cv_enabled:GetBool() then
        print("[RTX Remix Fixes 2 - Force View Frustrum] PVS optimization disabled, resetting all entities to large bounds")
        
        -- Clear PVS tracking
        entitiesInPVS = setmetatable({}, weakEntityTable)
        currentPVS = nil
        
        -- Reset all entities to use large bounds
        UpdateAllEntitiesBatched(false)
    elseif enabled and cv_enabled:GetBool() then
        -- If enabling PVS, immediately update the PVS
        print("[RTX Remix Fixes 2 - Force View Frustrum] PVS optimization enabled, updating bounds based on PVS")
        UpdatePlayerPVS()
        UpdateAllEntitiesBatched(false)
    end
end)

cvars.AddChangeCallback("rtx_fr_enabled", function(_, oldValue, newValue)
    local oldEnabled = tobool(oldValue)
    local newEnabled = tobool(newValue)
    
    print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Enabled state changing: %s -> %s", 
        tostring(oldEnabled), tostring(newEnabled)))
    
    if newEnabled then
        -- System being enabled
        RTX_SYSTEM.active = true
        
        -- Reset PVS tracking
        for k in pairs(entitiesInPVS) do entitiesInPVS[k] = nil end
        
        -- Force immediate PVS update
        lastPVSUpdateTime = 0
        if cv_use_pvs:GetBool() and NikNaks and NikNaks.CurrentMap then
            UpdatePlayerPVS()
            -- Force static prop update immediately
            if cv_static_props_pvs:GetBool() then
                UpdateStaticPropsPVS()
            end
        end
        
        -- Initial PVS update if optimization is enabled
        if cv_use_pvs:GetBool() and NikNaks and NikNaks.CurrentMap then
            UpdatePlayerPVS()
        end
        
        -- Store original static prop setting
        if not RTX_FRUSTUM_ORIGINAL_PROP_SETTING then
            RTX_FRUSTUM_ORIGINAL_PROP_SETTING = GetConVar("r_drawstaticprops"):GetInt()
        end
        
        -- Update RTX light updaters
        UpdateRTXLightUpdaters()
        
        UpdateAllEntitiesBatched(false)
        CreateStaticProps()
        
        print("[RTX Remix Fixes 2 - Force View Frustrum] System activated")
    else
        -- System being disabled
        local result = DeactivateRTXSystem()
        print(string.format("[RTX Remix Fixes 2 - Force View Frustrum] Deactivation complete: %d entities reset, %d props removed", 
            result.entitiesReset, result.propsRemoved))
    end
end)

cvars.AddChangeCallback("rtx_fr_bounds_size", function(_, _, new)
    -- Use debounce timer to avoid multiple rapid updates
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        ResetAndUpdateBounds(false)
    end)
end)

cvars.AddChangeCallback("rtx_fr_rtx_distance", function(_, _, new)
    if not RTX_SYSTEM.active then return end
    
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        -- We can do a targeted update for just RTX updaters
        local rtxDistance = tonumber(new)
        
        -- First restore all RTX updaters to original bounds
        for ent in pairs(rtxUpdaterCache) do
            if IsValid(ent) and ent.lightType ~= "light_environment" then
                if originalBounds[ent] then
                    ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
                end
            end
        end
        
        -- Then update them with new bounds
        UpdateRTXLightUpdaters()
    end)
end)

cvars.AddChangeCallback("rtx_fr_environment_light_distance", function(_, _, new)
    if not RTX_SYSTEM.active then return end
    
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        -- Targeted update for environment lights only
        local envDistance = tonumber(new)
        
        -- First restore environment lights to original bounds
        for ent in pairs(rtxUpdaterCache) do
            if IsValid(ent) and ent.lightType == "light_environment" then
                if originalBounds[ent] then
                    ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
                end
            end
        end
        
        -- Then update them with new bounds
        UpdateRTXLightUpdaters()
    end)
end)

-- ConCommand to refresh all entities' bounds
concommand.Add("rtx_fr_refresh", function()
    ResetAndUpdateBounds(false)
    print("Refreshed render bounds for all entities" .. (RTX_SYSTEM.active and " with large bounds" or " with original bounds"))
end)

-- Entity cleanup
AddManagedHook("EntityRemoved", "CleanupRTXCache", function(ent)
    RemoveFromRTXCache(ent)
    originalBounds[ent] = nil
end)

-- Cleanup Timer
timer.Create("fr_EntityCleanup", 60, 0, CleanupInvalidEntities)

-- Debug command
concommand.Add("rtx_fr_debug", function()
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
    boundsPanel:SetTall(650) -- Reduced height for more condensed layout
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
    presetCombo:SetTall(20) -- Smaller height
    
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
    descText:SetTall(100) -- Combined height for both texts
    descText:Dock(TOP)
    descText:DockMargin(0, 0, 0, 5)
    
    -- Create a more compact form for the sliders
    local slidersForm = vgui.Create("DForm", boundsPanel)
    slidersForm:Dock(TOP)
    slidersForm:DockMargin(0, 0, 0, 5)
    slidersForm:SetName("") -- Empty name to avoid duplicate heading
    slidersForm:SetSpacing(2) -- Reduce spacing between form elements
    slidersForm:SetPadding(2) -- Reduce padding
    
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
            mapList:AddLine(map, preset)
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
        
        -- If no exact match, use current settings as "Custom" preset
        if not matchingPreset then
            -- This will save the actual values but display as "Custom" in the list
            matchingPreset = "Custom"
        end
        
        -- Save to map presets
        MAP_PRESETS[currentMap] = matchingPreset
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
    
    -- Debug section
    local debugLabel = vgui.Create("DLabel", boundsPanel)
    debugLabel:SetText("Debug Options")
    debugLabel:SetTextColor(Color(0, 0, 0))
    debugLabel:Dock(TOP)
    debugLabel:DockMargin(0, 5, 0, 2)
    
    -- More compact debug form
    local debugForm = vgui.Create("DForm", boundsPanel)
    debugForm:Dock(TOP)
    debugForm:DockMargin(0, 0, 0, 0)
    debugForm:SetName("") -- Empty name to avoid duplicate heading
    debugForm:SetSpacing(2) -- Reduced spacing
    debugForm:SetPadding(2) -- Reduced padding
    
    debugForm:CheckBox("Show PVS Debug HUD", "rtx_fr_pvs_hud")
    debugForm:ControlHelp("Shows performance statistics in HUD")
    
    debugForm:CheckBox("Show Debug Messages", "rtx_fr_debug_messages")
    debugForm:ControlHelp("Shows detailed debug information in console")
    
    -- Init - load saved map presets
    LoadMapPresets()
    
    -- Apply current map preset if exists, otherwise use Low preset
    local currentMap = game.GetMap()
    if MAP_PRESETS[currentMap] then
        ApplyPreset(MAP_PRESETS[currentMap])
        presetCombo:SetValue(MAP_PRESETS[currentMap])
    else
        -- Default to Low preset
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

concommand.Add("rtx_fr_reset_bounds", function()
    print("[RTX Remix Fixes 2 - Force View Frustrum] Performing complete bounds reset...")
    
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
    
    print("[RTX Remix Fixes 2 - Force View Frustrum] Bounds reset complete")
end)