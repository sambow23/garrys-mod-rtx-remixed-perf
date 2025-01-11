-- Optimize the view frustrum to work better with RTX Remix. This code is pretty heavy but it's the current solution we have until we get proper engine patches.
-- MAJOR THANK YOU to the creator of NikNaks, a lot of this would not be possible without it.
if not CLIENT then return end

-- ConVars
local cv_disable_culling = CreateClientConVar("fr_disable", "1", true, false, "Disable frustum culling")
local cv_bounds_size = CreateClientConVar("fr_bounds_size", "10000", true, false, "Size of render bounds when culling is disabled")
local cv_rtx_updater_distance = CreateClientConVar("fr_updater_distance", "16384", true, false, "Maximum render distance for RTX light updaters")
local cv_static_prop_cell_size = CreateClientConVar("fr_static_prop_cell_size", "1024", true, false, "Size of spatial partitioning cells")
local cv_update_frequency = CreateClientConVar("fr_update_frequency", "0.5", true, false, "How often to update static props visibility")

-- RTX Light Updater model list
local RTX_UPDATER_MODELS = {
    ["models/hunter/plates/plate.mdl"] = true,
    ["models/hunter/blocks/cube025x025x025.mdl"] = true
}

-- Cache system
local Cache = {
    grid = {},
    gridSize = cv_static_prop_cell_size:GetFloat(),
    mapBounds = { mins = Vector(0,0,0), maxs = Vector(0,0,0) },
    activeProps = {},
    precomputedData = {},
    boundsInitialized = {},
    lastBoundsSize = cv_bounds_size:GetFloat(),
    lastUpdaterDistance = cv_rtx_updater_distance:GetFloat(),
    mins = Vector(-cv_bounds_size:GetFloat(), -cv_bounds_size:GetFloat(), -cv_bounds_size:GetFloat()),
    maxs = Vector(cv_bounds_size:GetFloat(), cv_bounds_size:GetFloat(), cv_bounds_size:GetFloat()),
    lastUpdate = 0
}

-- Helper functions
local function IsGameReady()
    return LocalPlayer() and IsValid(LocalPlayer())
end

local function IsRTXUpdater(ent)
    if not IsValid(ent) then return false end
    if ent.isRTXUpdaterCached ~= nil then
        return ent.isRTXUpdaterCached
    end
    
    local class = ent:GetClass()
    local isUpdater = (class == "rtx_lightupdater" or class == "rtx_lightupdatermanager" or
                      (ent:GetModel() and RTX_UPDATER_MODELS[ent:GetModel()]))
    
    ent.isRTXUpdaterCached = isUpdater
    return isUpdater
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
        
        local modelMins, modelMaxs = NikNaks.ModelSize(model)
        Cache.precomputedData[model] = Cache.precomputedData[model] or {
            bounds = { mins = modelMins, maxs = modelMaxs }
        }
    end
    
    Cache.mapBounds.mins = mapMins
    Cache.mapBounds.maxs = mapMaxs
    
    -- Build spatial grid
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
            entity = nil
        })
    end
end

-- Entity Bounds Management
local function SetEntityBounds(ent)
    if not IsValid(ent) or not cv_disable_culling:GetBool() then return end
    
    -- Skip if already initialized and no relevant changes
    if Cache.boundsInitialized[ent] then
        if Cache.lastBoundsSize == cv_bounds_size:GetFloat() and
           (not IsRTXUpdater(ent) or Cache.lastUpdaterDistance == cv_rtx_updater_distance:GetFloat()) then
            return
        end
    end
    
    -- Set bounds
    if IsRTXUpdater(ent) then
        local huge_bounds = Vector(cv_rtx_updater_distance:GetFloat(), cv_rtx_updater_distance:GetFloat(), cv_rtx_updater_distance:GetFloat())
        ent:SetRenderBounds(-huge_bounds, huge_bounds)
        ent:DisableMatrix("RenderMultiply")
        ent:SetNoDraw(false)
    else
        ent:SetRenderBounds(Cache.mins, Cache.maxs)
    end
    
    Cache.boundsInitialized[ent] = true
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
    
    for key in pairs(visibleCells) do
        local cell = Cache.grid[key]
        if not cell then continue end
        
        for _, propData in ipairs(cell) do
            if propData.pos:DistToSqr(playerPos) > visibleRange * visibleRange then
                continue
            end
            
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
    
    for ent in pairs(Cache.activeProps) do
        if not newActiveProps[ent] and IsValid(ent) then
            ent:Remove()
        end
    end
    
    Cache.activeProps = newActiveProps
end

-- Hooks
hook.Add("Think", "UpdateRenderBounds", function()
    if not cv_disable_culling:GetBool() then return end
    if not IsGameReady() then return end
    
    local curTime = CurTime()
    if curTime < Cache.lastUpdate + cv_update_frequency:GetFloat() then return end
    
    Cache.lastUpdate = curTime
    UpdateVisibleProps()
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

hook.Add("EntityRemoved", "CleanupBoundsCache", function(ent)
    Cache.boundsInitialized[ent] = nil
end)

-- ConVar callbacks
cvars.AddChangeCallback("fr_bounds_size", function(_, _, new)
    local newSize = tonumber(new)
    Cache.lastBoundsSize = newSize
    Cache.mins = Vector(-newSize, -newSize, -newSize)
    Cache.maxs = Vector(newSize, newSize, newSize)
    Cache.boundsInitialized = {}
end)

cvars.AddChangeCallback("fr_updater_distance", function(_, _, new)
    Cache.lastUpdaterDistance = tonumber(new)
    for ent, _ in pairs(Cache.boundsInitialized) do
        if IsValid(ent) and IsRTXUpdater(ent) then
            Cache.boundsInitialized[ent] = false
        end
    end
end)

-- Debug command
concommand.Add("fr_debug", function()
    print("\nRTX Frustum Optimization Debug:")
    print("Culling Disabled:", cv_disable_culling:GetBool())
    print("Bounds Size:", cv_bounds_size:GetFloat())
    print("RTX Updater Distance:", cv_rtx_updater_distance:GetFloat())
    print("Grid Cell Size:", Cache.gridSize)
    print("\nCurrent State:")
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
    print("Initialized Bounds:", table.Count(Cache.boundsInitialized))
end)