-- Custom Static Prop Renderer
-- Re-Renders all static props to bypass engine culling 
-- Author: CR

local convar_Enable = CreateClientConVar("rtx_spr_enable", "0", true, false, "Enable custom rendering of static props")
local convar_Debug = CreateClientConVar("rtx_spr_debug", "0", true, false, "Enable debug prints for static prop renderer")

-- Global state
local isDataReady = false
local isCachingInProgress = false
local cachedStaticProps = {}
local materialsCache = {}
local meshCache = {}  -- Maps model path to IMesh objects
local lastDebugFrame = 0

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

-- Get mesh data directly using our own extraction logic
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
        skin = propData.Skin or 0
    }
    
    -- Check if we already cached this model's mesh
    if not meshCache[modelPath] then
        -- First try util.GetModelMeshes
        local meshData = GetModelMeshes(modelPath)
        
        if not meshData or #meshData == 0 then
            DebugPrint("Failed to get mesh data for:", modelPath)
            -- Store an empty entry to avoid repeatedly trying to process it
            meshCache[modelPath] = {
                mesh = nil,
                error = true
            }
            return nil
        end
        
        -- Combine all mesh groups into a single set of vertices
        local vertices = {}
        local mins = Vector(math.huge, math.huge, math.huge)
        local maxs = Vector(-math.huge, -math.huge, -math.huge)
        
        -- Process each mesh group
        for _, group in ipairs(meshData) do
            if group.triangles then
                for _, vert in ipairs(group.triangles) do
                    table.insert(vertices, vert)
                    
                    -- Calculate bounds
                    if vert.pos.x < mins.x then mins.x = vert.pos.x end
                    if vert.pos.y < mins.y then mins.y = vert.pos.y end
                    if vert.pos.z < mins.z then mins.z = vert.pos.z end
                    if vert.pos.x > maxs.x then maxs.x = vert.pos.x end
                    if vert.pos.y > maxs.y then maxs.y = vert.pos.y end
                    if vert.pos.z > maxs.z then maxs.z = vert.pos.z end
                end
            end
        end
        
        if #vertices > 0 then
            -- Build an IMesh from the vertex data
            local mesh = Mesh()
            mesh:BuildFromTriangles(vertices)
            
            -- Store in the cache
            meshCache[modelPath] = {
                mesh = mesh,
                mins = mins,
                maxs = maxs
            }
            
            DebugPrint("Cached mesh for model:", modelPath, "#vertices:", #vertices)
        else
            DebugPrint("No vertices found for model:", modelPath)
            meshCache[modelPath] = {
                mesh = nil,
                error = true
            }
            return nil
        end
    elseif meshCache[modelPath].error then
        return nil  -- Skip previously failed models
    end
    
    -- Link to the cached mesh data
    prop.cachedMesh = meshCache[modelPath]
    return prop
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
            isDataReady = true
            isCachingInProgress = false
            print(string.format("[Static Render] Caching complete. %d static props processed, %d skipped.", 
                               processedSoFar, skippedSoFar))
        end
    end
    
    -- Start processing in batches of 100
    ProcessBatch(1, 100)
end

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
        if meshData.mesh then
            meshData.mesh:Destroy()
        end
    end
    
    table.Empty(cachedStaticProps)
    table.Empty(materialsCache)
    table.Empty(meshCache)
    
    isDataReady = false
    isCachingInProgress = false
end)

-- Render the static props
hook.Add("PostDrawOpaqueRenderables", "CustomStaticRender_DrawProps", function(bDrawingDepth, bDrawingSkybox)
    
    if not convar_Enable:GetBool() or not isDataReady or isCachingInProgress then
        return
    end
    
    if #cachedStaticProps == 0 then
        if convar_Debug:GetBool() then
            local frameCount = FrameNumber()
            if lastDebugFrame ~= frameCount then
                DebugPrint("No cached props to render")
                lastDebugFrame = frameCount
            end
        end
        return
    end
    
    local renderedProps = 0
    local skippedProps = 0
    
    -- Debug stats only calculated once per frame
    local shouldDebug = convar_Debug:GetBool()
    local frameCount = FrameNumber()
    local isNewFrame = lastDebugFrame ~= frameCount
    
    if shouldDebug and isNewFrame then
        DebugPrint("Attempting to render", #cachedStaticProps, "props")
        lastDebugFrame = frameCount
    end
    
    -- Render each static prop mesh
    for _, prop in ipairs(cachedStaticProps) do
        local meshData = prop.cachedMesh
        if not meshData or not meshData.mesh then
            skippedProps = skippedProps + 1
            continue
        end
        
        -- Set up transformation matrix
        local matrix = Matrix()
        matrix:Translate(prop.origin)
        matrix:Rotate(prop.angles)
        
        -- Set material
        render.SetMaterial(GetCachedMaterial("models/debug/debugwhite")) -- Default material
        
        -- Apply the transformation and draw the mesh
        cam.PushModelMatrix(matrix)
        meshData.mesh:Draw()
        cam.PopModelMatrix()
        
        renderedProps = renderedProps + 1
    end
    
    -- Debug output
    if shouldDebug and isNewFrame and renderedProps > 0 then
        DebugPrint("Rendered", renderedProps, "props,", skippedProps, "skipped")
    end
end)

-- Add reload command
concommand.Add("rtx_spr_reload", function()
    print("[Static Render] Manually reloading cache...")
    isDataReady = false
    isCachingInProgress = false
    
    -- Clean up meshes
    for modelPath, meshData in pairs(meshCache) do
        if meshData.mesh then
            meshData.mesh:Destroy()
        end
    end
    
    table.Empty(cachedStaticProps)
    table.Empty(materialsCache)
    table.Empty(meshCache)
    
    timer.Simple(0.1, CacheMapStaticProps)
end)

print("[Custom Static Renderer] Loaded.")