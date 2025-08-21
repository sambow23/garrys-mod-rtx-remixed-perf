-- Custom Static Prop Renderer -- disabled due to engine culling patches.
-- Re-Renders all static props to bypass engine culling 
-- Author: CR

local convar_Enable = CreateClientConVar("rtx_spr_enable", "1", true, false, "Enable custom rendering of static props")
local convar_Debug = CreateClientConVar("rtx_spr_debug", "0", true, false, "Enable debug prints for static prop renderer")
local convar_RenderDistance = CreateClientConVar("rtx_spr_distance", "10000", true, false, "Maximum distance to render static props (0 = no limit)")

-- Global state
local isDataReady = false
local isCachingInProgress = false
local cachedStaticProps = {}
local materialsCache = {}
local meshCache = {}  -- Maps model path to IMesh objects
local lastDebugFrame = 0
local bDrawingSkybox = false
local skyboxProps = {}
local worldProps = {}

-- Debug helper function
local function DebugPrint(...)
    if convar_Debug:GetBool() then
        print("[Static Render Debug]", ...)
    end
end

-- Material cache helper
local function GetCachedMaterial(matName)
    if not matName or matName == "" then
        matName = "debug/debugwhite"
    end
    
    if materialsCache[matName] then
        return materialsCache[matName]
    end
    
    local mat = Material(matName)
    materialsCache[matName] = mat
    return mat
end

-- Get mesh data directly using GetModelMeshes
local function GetModelMeshes(modelPath)
    -- Load the model if not already loaded
    if not util.IsModelLoaded(modelPath) then
        util.PrecacheModel(modelPath)
    end
    
    -- Try to get mesh data directly
    return util.GetModelMeshes(modelPath)
end

-- Process a static prop and prepare rendering data
local function ProcessStaticProp(propData)
    local modelPath = propData.PropType
    if not modelPath or modelPath == "" then
        DebugPrint("Static prop has no model path")
        return nil
    end
    
    -- Create the prop data structure
    local prop = {
        model = modelPath,
        origin = propData.Origin,
        angles = propData.Angles,
        skin = propData.Skin or 0,
        color = propData.DiffuseModulation or Color(255, 255, 255)
    }

    -- Check if this is a skybox prop
    local isSkyboxProp = false
    if NikNaks and NikNaks.CurrentMap and NikNaks.CurrentMap:HasSkyBox() then
        local skyPos = NikNaks.CurrentMap:GetSkyBoxPos()
        local skyMinBounds, skyMaxBounds = NikNaks.CurrentMap:GetSkyboxSize()
        
        -- Check if the prop is within skybox bounds
        if skyMinBounds and skyMaxBounds and propData.Origin then
            isSkyboxProp = propData.Origin:WithinAABox(skyMinBounds, skyMaxBounds)
        end
    end
    
    -- Store this information in the prop data
    prop.isSkybox = isSkyboxProp
    
    -- Check if we already cached this model's mesh
    local cacheKey = modelPath .. "_skin" .. prop.skin
    if not meshCache[cacheKey] then
        -- Get the mesh data
        local meshData = GetModelMeshes(modelPath)
        
        if not meshData or #meshData == 0 then
            DebugPrint("Failed to get mesh data for:", modelPath)
            -- Store an empty entry to avoid repeatedly trying to process it
            meshCache[cacheKey] = {
                meshes = nil,
                error = true
            }
            return nil
        end
        
        -- Process mesh groups and maintain their material relationships
        local processedMeshes = {}
        local mins = Vector(math.huge, math.huge, math.huge)
        local maxs = Vector(-math.huge, -math.huge, -math.huge)
        
        -- Process each mesh group
        for _, group in ipairs(meshData) do
            if group.triangles and #group.triangles > 0 then
                local material = group.material or "models/debug/debugwhite"
                
                -- Create or get cached material
                local mat = GetCachedMaterial(material)
                
                -- Create mesh for this group
                local mesh = Mesh()
                mesh:BuildFromTriangles(group.triangles)
                
                -- Add to processed meshes
                table.insert(processedMeshes, {
                    mesh = mesh,
                    material = mat
                })
                
                -- Update bounds
                for _, vert in ipairs(group.triangles) do
                    if vert.pos.x < mins.x then mins.x = vert.pos.x end
                    if vert.pos.y < mins.y then mins.y = vert.pos.y end
                    if vert.pos.z < mins.z then mins.z = vert.pos.z end
                    if vert.pos.x > maxs.x then maxs.x = vert.pos.x end
                    if vert.pos.y > maxs.y then maxs.y = vert.pos.y end
                    if vert.pos.z > maxs.z then maxs.z = vert.pos.z end
                end
            end
        end
        
        if #processedMeshes > 0 then
            -- Store in the cache
            meshCache[cacheKey] = {
                meshes = processedMeshes,
                mins = mins,
                maxs = maxs
            }
            
            DebugPrint("Cached mesh for model:", modelPath, "#mesh groups:", #processedMeshes)
        else
            DebugPrint("No valid mesh groups found for model:", modelPath)
            meshCache[cacheKey] = {
                meshes = nil,
                error = true
            }
            return nil
        end
    elseif meshCache[cacheKey].error then
        return nil  -- Skip previously failed models
    end
    
    -- Link to the cached mesh data
    prop.cachedMesh = meshCache[cacheKey]
    return prop
end

-- Separate skybox props from world props
local function SeparateSkyboxProps()
    skyboxProps = {}
    worldProps = {}
    
    for _, prop in ipairs(cachedStaticProps) do
        if prop.isSkybox then
            table.insert(skyboxProps, prop)
        else
            table.insert(worldProps, prop)
        end
    end
    
    print(string.format("[Static Render] Separated props: %d world props, %d skybox props", 
                        #worldProps, #skyboxProps))
end

-- Cache static props from NikNaks data
local function CacheMapStaticProps()
    if isCachingInProgress then return end
    
    DebugPrint("Checking NikNaks availability...")
    
    if not NikNaks then
        DebugPrint("NikNaks module not found!")
        timer.Simple(1, CacheMapStaticProps)
        return
    end
    
    if not NikNaks.CurrentMap then
        DebugPrint("NikNaks.CurrentMap not available yet.")
        timer.Simple(1, CacheMapStaticProps)
        return
    end
    
    if not NikNaks.CurrentMap.GetStaticProps then
        DebugPrint("NikNaks.CurrentMap.GetStaticProps function doesn't exist!")
        DebugPrint("Available functions:", table.concat(table.GetKeys(NikNaks.CurrentMap), ", "))
        timer.Simple(1, CacheMapStaticProps)
        return
    end
    
    isCachingInProgress = true
    print("[Static Render] Starting static prop data caching...")
    
    -- Clear previous caches
    table.Empty(cachedStaticProps)
    
    -- Get static props data from NikNaks
    local staticPropsRaw = NikNaks.CurrentMap:GetStaticProps()
    if not staticPropsRaw or type(staticPropsRaw) ~= "table" then
        print("[Static Render] GetStaticProps() returned invalid data:", staticPropsRaw)
        isCachingInProgress = false
        isDataReady = true -- Mark as ready to prevent retries
        return
    end
    
    -- Debug output
    print("[Static Render] Retrieved", #staticPropsRaw, "static props")
    
    -- Process in batches
    local processedSoFar = 0
    local skippedSoFar = 0
    
    -- Process a batch of props (to avoid freezing the game)
    local function ProcessBatch(startIndex, batchSize)
        local endIndex = math.min(startIndex + batchSize - 1, #staticPropsRaw)
        local processed = 0
        local skipped = 0
        
        for i = startIndex, endIndex do
            local propData = staticPropsRaw[i]
            local prop = ProcessStaticProp(propData)
            
            if prop then
                table.insert(cachedStaticProps, prop)
                processed = processed + 1
            else
                skipped = skipped + 1
            end
        end
        
        processedSoFar = processedSoFar + processed
        skippedSoFar = skippedSoFar + skipped
        
        DebugPrint(string.format("Processed batch %d-%d: %d processed, %d skipped", 
                                 startIndex, endIndex, processed, skipped))
        
        -- If there are more props to process, schedule the next batch
        if endIndex < #staticPropsRaw then
            timer.Simple(0.05, function()
                ProcessBatch(endIndex + 1, batchSize)
            end)
        else
            -- All done
            SeparateSkyboxProps() -- Separate skybox props from world props
            isDataReady = true
            isCachingInProgress = false
            print(string.format("[Static Render] Caching complete. %d static props processed, %d skipped.", 
                               processedSoFar, skippedSoFar))
        end
    end
    
    -- Start processing in batches of 100
    ProcessBatch(1, 100)
end

-- Skybox detection hooks
hook.Add("PreDrawSkyBox", "RTXStaticPropsSkyboxDetection", function()
    bDrawingSkybox = true
end)

hook.Add("PostDrawSkyBox", "RTXStaticPropsSkyboxDetection", function()
    bDrawingSkybox = false
end)

-- Hook to initiate caching when the map is ready
hook.Add("InitPostEntity", "CustomStaticRender_InitCache", function()
    -- Delay slightly to ensure NikNaks has loaded its data
    timer.Simple(3, CacheMapStaticProps)
end)

-- Clean up caches on disconnect/map change
hook.Add("ShutDown", "CustomStaticRender_Cleanup", function()
    print("[Static Render] Cleaning up caches.")
    
    -- Clean up meshes
    for modelPath, meshData in pairs(meshCache) do
        if meshData.meshes then
            for _, meshInfo in ipairs(meshData.meshes) do
                if meshInfo.mesh then
                    meshInfo.mesh:Destroy()
                end
            end
        end
    end
    
    table.Empty(cachedStaticProps)
    table.Empty(skyboxProps)
    table.Empty(worldProps)
    table.Empty(materialsCache)
    table.Empty(meshCache)
    
    isDataReady = false
    isCachingInProgress = false
end)

-- Render the static props
hook.Add("PostDrawOpaqueRenderables", "CustomStaticRender_DrawProps", function(bDrawingDepth, bDrawingSkybox_param)
    if not convar_Enable:GetBool() or not isDataReady or isCachingInProgress then
        return
    end
    
    -- Choose which prop list to render based on skybox state
    local propsToRender = bDrawingSkybox and skyboxProps or worldProps
    
    if #propsToRender == 0 then
        if convar_Debug:GetBool() then
            local frameCount = FrameNumber()
            if lastDebugFrame ~= frameCount then
                lastDebugFrame = frameCount
            end
        end
        return
    end
    
    local renderedProps = 0
    local skippedProps = 0
    local distanceSkipped = 0
    
    -- Get player position for distance check
    local playerPos = LocalPlayer():GetPos()
    local maxDistance = convar_RenderDistance:GetFloat()
    local useDistanceLimit = (maxDistance > 0)
    local maxDistanceSqr = maxDistance * maxDistance
    
    -- Debug stats only calculated once per frame
    local shouldDebug = convar_Debug:GetBool()
    local frameCount = FrameNumber()
    local isNewFrame = lastDebugFrame ~= frameCount
    
    if shouldDebug and isNewFrame then
        DebugPrint("Attempting to render", #propsToRender, "props in " .. (bDrawingSkybox and "skybox" or "world"), 
                  useDistanceLimit and ("with distance limit " .. maxDistance) or "with no distance limit")
        lastDebugFrame = frameCount
    end
    
    -- Render each static prop mesh
    for _, prop in ipairs(propsToRender) do
        local meshData = prop.cachedMesh
        if not meshData or not meshData.meshes then
            skippedProps = skippedProps + 1
            continue
        end
        
        -- Check distance if distance limit is enabled
        if useDistanceLimit then
            local distSqr = playerPos:DistToSqr(prop.origin)
            if distSqr > maxDistanceSqr then
                distanceSkipped = distanceSkipped + 1
                continue
            end
        end
        
        -- Set up transformation matrix
        local matrix = Matrix()
        matrix:Translate(prop.origin)
        matrix:Rotate(prop.angles)
        
        -- Apply color modulation if present
        if prop.color then
            render.SetColorModulation(prop.color.r/255, prop.color.g/255, prop.color.b/255)
        end
        
        -- Draw each mesh group with its proper material
        cam.PushModelMatrix(matrix)
        for _, meshInfo in ipairs(meshData.meshes) do
            if meshInfo.mesh and meshInfo.material then
                render.SetMaterial(meshInfo.material)
                meshInfo.mesh:Draw()
            end
        end
        cam.PopModelMatrix()
        
        -- Reset color modulation
        render.SetColorModulation(1, 1, 1)
        
        renderedProps = renderedProps + 1
    end
    
    -- Debug output
    if shouldDebug and isNewFrame then
        if useDistanceLimit then
            DebugPrint("Rendered", renderedProps, "props in " .. (bDrawingSkybox and "skybox" or "world"),
                      skippedProps, "skipped due to errors,", 
                      distanceSkipped, "skipped due to distance")
        else
            DebugPrint("Rendered", renderedProps, "props in " .. (bDrawingSkybox and "skybox" or "world"),
                      skippedProps, "skipped")
        end
    end
end)

-- Add reload command
concommand.Add("rtx_spr_reload", function()
    print("[Static Render] Manually reloading cache...")
    isDataReady = false
    isCachingInProgress = false
    
    -- Clean up meshes
    for modelPath, meshData in pairs(meshCache) do
        if meshData.meshes then
            for _, meshInfo in ipairs(meshData.meshes) do
                if meshInfo.mesh then
                    meshInfo.mesh:Destroy()
                end
            end
        end
    end
    
    table.Empty(cachedStaticProps)
    table.Empty(skyboxProps)
    table.Empty(worldProps)
    table.Empty(materialsCache)
    table.Empty(meshCache)
    
    timer.Simple(0.1, CacheMapStaticProps)
end)

-- Disable engine props
RunConsoleCommand("r_drawstaticprops", "0")

print("[Custom Static Renderer] Loaded.")