-- Optimize the view frustrum to work better with RTX Remix. This code is pretty heavy but it's the current solution we have until we get proper engine patches.
-- MAJOR THANK YOU to the creator of NikNaks, a lot of this would not be possible without it.
if not CLIENT then return end

-- ConVars
local cv_disable_culling = CreateClientConVar("fr_disable", "1", true, false, "Disable frustum culling")
local cv_bounds_size = CreateClientConVar("fr_bounds_size", "10000", true, false, "Size of render bounds when culling is disabled")
local cv_update_frequency = CreateClientConVar("fr_update_frequency", "0.5", true, false, "How often to update entities")
local cv_rtx_updater_distance = CreateClientConVar("fr_updater_distance", "16384", true, false, "Maximum render distance for RTX light updaters")
local cv_batch_size = CreateClientConVar("fr_batch_size", "50", true, false, "How many entities to process per frame")
local cv_static_prop_cell_size = CreateClientConVar("fr_static_prop_cell_size", "1024", true, false, "Size of spatial partitioning cells")
local cv_rtx_update_frequency = CreateClientConVar("fr_update_frequency", "1", true, false, "How often to update RTX light updaters (in seconds)")
local cv_rtx_batch_enabled = CreateClientConVar("fr_batch_enabled", "1", true, false, "Enable batched updates for RTX light updaters")

-- RTX Light Updater model list
local RTX_UPDATER_MODELS = {
    ["models/hunter/plates/plate.mdl"] = true,
    ["models/hunter/blocks/cube025x025x025.mdl"] = true
}

-- Cache system
local Cache = {
    processQueue = {},
    isProcessing = false,
    lastUpdate = 0,
    boundsSize = cv_bounds_size:GetFloat(),
    mins = Vector(-cv_bounds_size:GetFloat(), -cv_bounds_size:GetFloat(), -cv_bounds_size:GetFloat()),
    maxs = Vector(cv_bounds_size:GetFloat(), cv_bounds_size:GetFloat(), cv_bounds_size:GetFloat()),
    -- Spatial partitioning grid
    grid = {},
    gridSize = cv_static_prop_cell_size:GetFloat(),
    mapBounds = { mins = Vector(0,0,0), maxs = Vector(0,0,0) },
    activeProps = {},
    precomputedData = {},
    rtxQueue = {},
    lastRTXUpdate = 0,
    boundUpdateTimes = {},
    boundUpdateStates = {},
    nextBoundUpdate = 0,
    updateInterval = 0.1,
    distanceThresholds = {
        {dist = 1000, interval = 0.1},
        {dist = 2000, interval = 0.25},
        {dist = 4000, interval = 0.5},
        {dist = 8000, interval = 1.0},
        {dist = 16000, interval = 2.0}
    }
}

-- Helper functions
local function IsGameReady()
    return LocalPlayer() and IsValid(LocalPlayer())
end

local function ShouldUpdateBounds(ent)
    if not IsValid(ent) then return false end
    
    local curTime = CurTime()
    
    -- Global throttle check
    if curTime < Cache.nextBoundUpdate then return false end
    
    -- Check entity's last update time
    local lastUpdate = Cache.boundUpdateTimes[ent] or 0
    local playerPos = LocalPlayer():GetPos()
    local entPos = ent:GetPos()
    local distance = playerPos:Distance(entPos)
    
    -- Determine update interval based on distance
    local updateInterval = Cache.updateInterval
    for _, threshold in ipairs(Cache.distanceThresholds) do
        if distance > threshold.dist then
            updateInterval = threshold.interval
        else
            break
        end
    end
    
    -- Check if enough time has passed for this entity
    return curTime - lastUpdate >= updateInterval
end

local function IsRTXUpdater(ent)
    if not IsValid(ent) then return false end
    -- Cache the result on the entity to avoid repeated checks
    if ent.isRTXUpdaterCached ~= nil then
        return ent.isRTXUpdaterCached
    end
    
    local class = ent:GetClass()
    local isUpdater = (class == "rtx_lightupdater" or class == "rtx_lightupdatermanager" or
                      (ent:GetModel() and RTX_UPDATER_MODELS[ent:GetModel()]))
    
    ent.isRTXUpdaterCached = isUpdater
    return isUpdater
end


local function UpdateRTXEntity(ent)
    if not IsValid(ent) then return end
    
    local playerPos = LocalPlayer():GetPos()
    local distance = playerPos:Distance(ent:GetPos())
    local maxDistance = cv_rtx_updater_distance:GetFloat()
    
    -- Dynamically adjust render bounds based on distance
    local boundsSize = math.min(distance + 1000, maxDistance)
    local bounds = Vector(boundsSize, boundsSize, boundsSize)
    ent:SetRenderBounds(-bounds, bounds)
    
    -- Only enable rendering if within maximum distance
    ent:SetNoDraw(distance > maxDistance)
end

local function ProcessRTXUpdaters()
    if not IsGameReady() then return end
    
    local curTime = CurTime()
    if curTime < Cache.lastRTXUpdate + cv_rtx_update_frequency:GetFloat() then return end
    Cache.lastRTXUpdate = curTime
    
    -- Collect all RTX updaters if queue is empty
    if #Cache.rtxQueue == 0 then
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and IsRTXUpdater(ent) then
                table.insert(Cache.rtxQueue, ent)
            end
        end
    end
    
    if #Cache.rtxQueue == 0 then return end
    
    if cv_rtx_batch_enabled:GetBool() then
        -- Process in batches
        local batchSize = math.min(cv_batch_size:GetInt(), #Cache.rtxQueue)
        for i = 1, batchSize do
            local ent = table.remove(Cache.rtxQueue, 1)
            if IsValid(ent) then
                UpdateRTXEntity(ent)
            end
            if #Cache.rtxQueue == 0 then break end
        end
    else
        -- Process all at once
        for _, ent in ipairs(Cache.rtxQueue) do
            if IsValid(ent) then
                UpdateRTXEntity(ent)
            end
        end
        Cache.rtxQueue = {}
    end
end

-- Spatial partitioning helpers
local function GetGridCell(pos)
    local cellSize = Cache.gridSize
    return {
        math.floor(pos.x / cellSize),
        math.floor(pos.y / cellSize),
        math.floor(pos.z / cellSize)
    }
end

local function GetGridKey(x, y, z)
    return string.format("%d:%d:%d", x, y, z)
end

local function PrecomputePropData()
    if not NikNaks or not NikNaks.CurrentMap then return end
    
    local staticProps = NikNaks.CurrentMap:GetStaticProps()
    local mapMins, mapMaxs = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    
    -- First pass: Get map bounds and precompute prop data
    for _, prop in pairs(staticProps) do
        local pos = prop:GetPos()
        local model = prop:GetModel()
        
        -- Update map bounds
        mapMins.x = math.min(mapMins.x, pos.x)
        mapMins.y = math.min(mapMins.y, pos.y)
        mapMins.z = math.min(mapMins.z, pos.z)
        mapMaxs.x = math.max(mapMaxs.x, pos.x)
        mapMaxs.y = math.max(mapMaxs.y, pos.y)
        mapMaxs.z = math.max(mapMaxs.z, pos.z)
        
        -- Use NikNaks' model size function instead of util.GetModelBounds
        local modelMins, modelMaxs = NikNaks.ModelSize(model)
        Cache.precomputedData[model] = Cache.precomputedData[model] or {
            bounds = { mins = modelMins, maxs = modelMaxs },
            vertices = nil  -- Remove vertices as they're not needed
        }
    end
    
    Cache.mapBounds.mins = mapMins
    Cache.mapBounds.maxs = mapMaxs
    
    -- Second pass: Build spatial grid
    local cellSize = Cache.gridSize
    for _, prop in pairs(staticProps) do
        local pos = prop:GetPos()
        local gridCell = GetGridCell(pos)
        local key = GetGridKey(gridCell[1], gridCell[2], gridCell[3])
        
        Cache.grid[key] = Cache.grid[key] or {}
        table.insert(Cache.grid[key], {
            model = prop:GetModel(),
            pos = pos,
            ang = prop:GetAngles(),
            color = prop:GetColor(),
            scale = prop:GetScale(),
            entity = nil -- Will be populated when needed
        })
    end
end

-- Visibility management
local function GetVisibleCells(playerPos, radius)
    local visibleCells = {}
    local minCell = GetGridCell(playerPos - Vector(radius, radius, radius))
    local maxCell = GetGridCell(playerPos + Vector(radius, radius, radius))
    
    for x = minCell[1], maxCell[1] do
        for y = minCell[2], maxCell[2] do
            for z = minCell[3], maxCell[3] do
                local key = GetGridKey(x, y, z)
                if Cache.grid[key] then
                    visibleCells[key] = true
                end
            end
        end
    end
    
    return visibleCells
end

local function UpdateVisibleProps()
    if not IsGameReady() then return end
    
    local playerPos = LocalPlayer():GetPos()
    local visibleRange = cv_bounds_size:GetFloat()
    local visibleCells = GetVisibleCells(playerPos, visibleRange)
    local newActiveProps = {}
    
    -- Create/update props in visible cells
    for key in pairs(visibleCells) do
        local cell = Cache.grid[key]
        if not cell then continue end
        
        for _, propData in ipairs(cell) do
            if propData.pos:DistToSqr(playerPos) > visibleRange * visibleRange then
                continue
            end
            
            -- Create or reuse entity
            if not IsValid(propData.entity) then
                propData.entity = ClientsideModel(propData.model)
                if IsValid(propData.entity) then
                    propData.entity:SetPos(propData.pos)
                    propData.entity:SetAngles(propData.ang)
                    propData.entity:SetColor(propData.color)
                    propData.entity:SetModelScale(propData.scale)
                    propData.entity:SetRenderBounds(Cache.mins, Cache.maxs)
                    propData.entity.IsStaticProp = true
                end
            end
            
            if IsValid(propData.entity) then
                newActiveProps[propData.entity] = true
            end
        end
    end
    
    -- Remove props that are no longer visible
    for ent in pairs(Cache.activeProps) do
        if not newActiveProps[ent] and IsValid(ent) then
            ent:Remove()
        end
    end
    
    Cache.activeProps = newActiveProps
end

-- Entity Bounds Management
local function SetEntityBounds(ent)
    if not IsValid(ent) or not cv_disable_culling:GetBool() then return end
    
    -- Only update if necessary
    if not ShouldUpdateBounds(ent) then return end
    
    -- Special handling for RTX updaters
    if IsRTXUpdater(ent) then
        local huge_bounds = Vector(cv_rtx_updater_distance:GetFloat(), cv_rtx_updater_distance:GetFloat(), cv_rtx_updater_distance:GetFloat())
        
        -- Check if bounds have changed
        local currentState = Cache.boundUpdateStates[ent]
        local newState = tostring(huge_bounds)
        
        if currentState ~= newState then
            ent:SetRenderBounds(-huge_bounds, huge_bounds)
            ent:DisableMatrix("RenderMultiply")
            ent:SetNoDraw(false)
            Cache.boundUpdateStates[ent] = newState
        end
    else
        -- Regular entities
        local currentState = Cache.boundUpdateStates[ent]
        local newState = tostring(Cache.mins) .. tostring(Cache.maxs)
        
        if currentState ~= newState then
            ent:SetRenderBounds(Cache.mins, Cache.maxs)
            Cache.boundUpdateStates[ent] = newState
        end
    end
    
    -- Update the last update time
    Cache.boundUpdateTimes[ent] = CurTime()
    Cache.nextBoundUpdate = CurTime() + 0.016 -- Limit to roughly once per frame maximum
end

-- Batch processing
local function ProcessBatch()
    if #Cache.processQueue == 0 then
        Cache.isProcessing = false
        return
    end
    
    local batchSize = math.min(cv_batch_size:GetInt(), #Cache.processQueue)
    local processed = 0
    local startTime = SysTime()
    
    while processed < batchSize and (SysTime() - startTime) < 0.002 do
        local ent = table.remove(Cache.processQueue, 1)
        if IsValid(ent) then
            SetEntityBounds(ent)
            processed = processed + 1
        end
    end
    
    if #Cache.processQueue > 0 then
        timer.Simple(0, ProcessBatch)
    else
        Cache.isProcessing = false
    end
end

local function QueueEntities()
    if not IsGameReady() then return end
    
    table.Empty(Cache.processQueue)
    
    -- Only queue non-RTX entities here
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not IsRTXUpdater(ent) and not ent.IsStaticProp then
            table.insert(Cache.processQueue, ent)
        end
    end
    
    if not Cache.isProcessing and #Cache.processQueue > 0 then
        Cache.isProcessing = true
        ProcessBatch()
    end
end

-- Hooks
hook.Add("Think", "UpdateRenderBounds", function()
    if not cv_disable_culling:GetBool() then return end
    if not IsGameReady() then return end
    
    local curTime = CurTime()
    if curTime < Cache.lastUpdate + cv_update_frequency:GetFloat() then return end
    
    Cache.lastUpdate = curTime
    QueueEntities()
    UpdateVisibleProps()
    ProcessRTXUpdaters() -- Add RTX processing
end)

hook.Add("InitPostEntity", "InitializeRTXOptimization", function()
    timer.Simple(2, function()
        PrecomputePropData()
        RunConsoleCommand("r_drawstaticprops", "0")
    end)
end)

hook.Add("OnEntityCreated", "HandleNewEntity", function(ent)
    if not IsValid(ent) then return end
    
    timer.Simple(0, function()
        if IsValid(ent) then
            SetEntityBounds(ent)
        end
    end)
end)

-- Map changes
hook.Add("OnReloaded", "RefreshRTXOptimization", function()
    for ent in pairs(Cache.activeProps) do
        if IsValid(ent) then ent:Remove() end
    end
    Cache.activeProps = {}
    Cache.grid = {}
    Cache.precomputedData = {}
    Cache.boundUpdateTimes = {}
    Cache.boundUpdateStates = {}
    Cache.nextBoundUpdate = 0
    PrecomputePropData()
end)

hook.Add("EntityRemoved", "CleanupBoundsCache", function(ent)
    Cache.boundUpdateTimes[ent] = nil
    Cache.boundUpdateStates[ent] = nil
end)

-- Debug command
concommand.Add("fr_debug", function()
    print("\nRTX Frustum Optimization Debug:")
    print("Culling Disabled:", cv_disable_culling:GetBool())
    print("Bounds Size:", cv_bounds_size:GetFloat())
    print("Update Frequency:", cv_update_frequency:GetFloat())
    print("RTX Updater Distance:", cv_rtx_updater_distance:GetFloat())
    print("Grid Cell Size:", Cache.gridSize)
    print("\nCurrent State:")
    print("Queue Size:", #Cache.processQueue)
    print("Is Processing:", Cache.isProcessing)
    print("Active Props:", table.Count(Cache.activeProps))
    print("Precomputed Models:", table.Count(Cache.precomputedData))
    
    local cellCount = 0
    for _ in pairs(Cache.grid) do cellCount = cellCount + 1 end
    print("Grid Cells:", cellCount)
    
    local rtxCount = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and IsRTXUpdater(ent) then
            rtxCount = rtxCount + 1
        end
    end
    print("RTX Updaters:", rtxCount)
end)