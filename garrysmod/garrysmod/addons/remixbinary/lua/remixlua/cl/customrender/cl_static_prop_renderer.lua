if not CLIENT then return end
local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore
-- Custom Static Prop Renderer -- disabled due to engine culling patches.
-- Re-Renders all static props to bypass engine culling 
-- Author: CR

local convar_Enable = CreateClientConVar("rtx_spr_enable", "1", true, false, "Enable custom rendering of static props")
local convar_Debug = CreateClientConVar("rtx_spr_debug", "0", true, false, "Enable debug prints for static prop renderer")
local convar_RenderDistance = CreateClientConVar("rtx_spr_distance", "10000", true, false, "Maximum distance to render static props (0 = no limit)")
local convar_Whitelist = CreateClientConVar("rtx_spr_mat_whitelist", "", true, false, "Comma-separated material name substrings to include")
local convar_Blacklist = CreateClientConVar("rtx_spr_mat_blacklist", "", true, false, "Comma-separated material name substrings to exclude")

-- Global state
local isDataReady = false
local isCachingInProgress = false
local cachedStaticProps = {}
local meshCache = {}  -- Maps model path to IMesh objects
local lastDebugFrame = 0
local bDrawingSkybox = false
local skyboxProps = {}
local worldProps = {}
local sprStats = { rendered = 0, total = 0 }
local sprBuildStats = { startTime = 0, endTime = 0, built = 0 }

-- Debug helper function
local DebugPrint = (RenderCore and RenderCore.CreateDebugPrint)
    and RenderCore.CreateDebugPrint("Static Render Debug", convar_Debug)
    or function(...)
        if convar_Debug:GetBool() then
            print("[Static Render Debug]", ...)
        end
    end

-- Use RenderCore material cache directly
local function GetCachedMaterial(matName)
    return (RenderCore and RenderCore.GetMaterial) and RenderCore.GetMaterial(matName) or Material(matName or "debug/debugwhite")
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

local function IsMaterialAllowedName(matName)
    if not matName then return false end
    if RenderCore and RenderCore.IsMaterialAllowed then
        return RenderCore.IsMaterialAllowed(matName, convar_Whitelist:GetString(), convar_Blacklist:GetString())
    end
    -- Fallback: allow by default if core helper missing
    return true
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
                if material and not IsMaterialAllowedName(material) then
                    continue
                end
                
                -- Create or get cached material
                local mat = GetCachedMaterial(material)
                
                -- Validate vertices for this group
                local valid = true
                if RenderCore and RenderCore.ValidateVertex then
                    for _, vert in ipairs(group.triangles) do
                        if not RenderCore.ValidateVertex(vert.pos) then
                            valid = false
                            break
                        end
                    end
                end
                if not valid then
                    continue
                end

                -- Create mesh for this group
                local mesh = Mesh()
                mesh:BuildFromTriangles(group.triangles)
                
                -- Add to processed meshes
                table.insert(processedMeshes, {
                    mesh = mesh,
                    material = mat
                })

                if RenderCore and RenderCore.TrackMesh then
                    RenderCore.TrackMesh(mesh)
                end
                
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
    sprBuildStats.startTime = SysTime()
    sprBuildStats.endTime = 0
    sprBuildStats.built = 0
    
    -- Clear previous caches
    table.Empty(cachedStaticProps)
    
    -- Get static props data from NikNaks
    local okProps, staticPropsRaw = pcall(function() return NikNaks.CurrentMap:GetStaticProps() end)
    if not okProps then
        print("[Static Render] GetStaticProps() errored")
        isCachingInProgress = false
        isDataReady = true
        return
    end
    if not staticPropsRaw or type(staticPropsRaw) ~= "table" then
        print("[Static Render] GetStaticProps() returned invalid data:", staticPropsRaw)
        isCachingInProgress = false
        isDataReady = true -- Mark as ready to prevent retries
        return
    end
    
    -- Debug output
    print("[Static Render] Retrieved", #staticPropsRaw, "static props")
    
    -- Coroutine-driven processing within a per-frame budget
    local processedSoFar = 0
    local skippedSoFar = 0
    local co
    co = coroutine.create(function()
        local startTime = SysTime()
        local frameBudget = 0.003
        for i = 1, #staticPropsRaw do
            local propData = staticPropsRaw[i]
            local prop = ProcessStaticProp(propData)
            if prop then
                table.insert(cachedStaticProps, prop)
                processedSoFar = processedSoFar + 1
                sprBuildStats.built = sprBuildStats.built + 1
            else
                skippedSoFar = skippedSoFar + 1
            end
            if SysTime() - startTime > frameBudget then
                coroutine.yield()
                local spent = SysTime() - startTime
                if spent > frameBudget * 1.2 then
                    frameBudget = math.max(0.001, frameBudget * 0.9)
                elseif spent < frameBudget * 0.8 then
                    frameBudget = math.min(0.006, frameBudget * 1.1)
                end
                startTime = SysTime()
            end
        end
        SeparateSkyboxProps()
        isDataReady = true
        isCachingInProgress = false
        print(string.format("[Static Render] Caching complete. %d static props processed, %d skipped.", 
                           processedSoFar, skippedSoFar))
        sprStats.total = processedSoFar
        sprBuildStats.endTime = SysTime()
    end)
    local function Step()
        if not co then return end
        if coroutine.status(co) == "dead" then return end
        local ok, err = coroutine.resume(co)
        if not ok then
            ErrorNoHalt("[Static Render] Cache coroutine error: " .. tostring(err) .. "\n")
            isCachingInProgress = false
            return
        end
        if coroutine.status(co) ~= "dead" then
            timer.Simple(0, Step)
        end
    end
    Step()
end

-- Skybox detection hooks
RenderCore.Register("PreDrawSkyBox", "RTXStaticPropsSkyboxDetection", function()
    bDrawingSkybox = true
end)

RenderCore.Register("PostDrawSkyBox", "RTXStaticPropsSkyboxDetection", function()
    bDrawingSkybox = false
end)

-- Hook to initiate caching when the map is ready
RenderCore.Register("InitPostEntity", "CustomStaticRender_InitCache", function()
    -- Delay slightly to ensure NikNaks has loaded its data
    timer.Simple(3, CacheMapStaticProps)
end)

-- Clean up caches on disconnect/map change
RenderCore.Register("ShutDown", "CustomStaticRender_Cleanup", function()
    print("[Static Render] Cleaning up caches.")
    -- Rely on core to destroy tracked meshes
    if RenderCore and RenderCore.DestroyTrackedMeshes then
        RenderCore.DestroyTrackedMeshes()
    end
    table.Empty(cachedStaticProps)
    table.Empty(skyboxProps)
    table.Empty(worldProps)
    table.Empty(meshCache)
    
    isDataReady = false
    isCachingInProgress = false
end)

-- Render the static props
RenderCore.Register("PreDrawOpaqueRenderables", "CustomStaticRender_DrawProps", function(bDrawingDepth, bDrawingSkybox_param)
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
    
    -- Debug stats only calculated once per frame
    local shouldDebug = convar_Debug:GetBool()
    local frameCount = FrameNumber()
    local isNewFrame = lastDebugFrame ~= frameCount
    
    if shouldDebug and isNewFrame then
        DebugPrint("Attempting to render", #propsToRender, "props in " .. (bDrawingSkybox and "skybox" or "world"), 
                  useDistanceLimit and ("with distance limit " .. maxDistance) or "with no distance limit")
        lastDebugFrame = frameCount
    end
    
    for _, prop in ipairs(propsToRender) do
        local meshData = prop.cachedMesh
        if not meshData or not meshData.meshes then
            skippedProps = skippedProps + 1
            continue
        end
        if useDistanceLimit and RenderCore and RenderCore.ShouldCullByDistance and RenderCore.ShouldCullByDistance(prop.origin, playerPos, maxDistance) then
            distanceSkipped = distanceSkipped + 1
            continue
        end
        local matrix = Matrix()
        matrix:Translate(prop.origin)
        matrix:Rotate(prop.angles)
        for _, meshInfo in ipairs(meshData.meshes) do
            if meshInfo.mesh and meshInfo.material then
                RenderCore.Submit({
                    material = meshInfo.material,
                    mesh = meshInfo.mesh,
                    matrix = matrix,
                    translucent = false,
                    color = prop.color
                })
            end
        end
        renderedProps = renderedProps + 1
    end
    
    sprStats.rendered = renderedProps
    sprStats.distance = distanceSkipped
    sprStats.skipped = skippedProps
    
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
    
    if RenderCore and RenderCore.DestroyTrackedMeshes then
        RenderCore.DestroyTrackedMeshes()
    end
    table.Empty(cachedStaticProps)
    table.Empty(skyboxProps)
    table.Empty(worldProps)
    table.Empty(meshCache)
    
    timer.Simple(0.1, CacheMapStaticProps)
end)

-- Disable engine props
RunConsoleCommand("r_drawstaticprops", "0")

print("[Custom Static Renderer] Loaded.")

-- Stats provider
RenderCore.RegisterStats("StaticProps", function()
    local built = sprBuildStats.built or 0
    local t = (sprBuildStats.endTime > 0 and sprBuildStats.endTime or SysTime()) - (sprBuildStats.startTime or 0)
    local rate = (t > 0) and (built / t) or 0
    return string.format("Static props: %d/%d (-E:%d, -D:%d) | build: %.2fs, %.1f/s", sprStats.rendered or 0, sprStats.total or 0, sprStats.skipped or 0, sprStats.distance or 0, t, rate)
end)

-- Rebuild sink and debounced cvar watchers
RenderCore.RegisterRebuildSink("StaticPropsRebuild", function(token, reason)
    -- Best-effort: clear current caches and rebuild
    isDataReady = false
    isCachingInProgress = false
    if RenderCore and RenderCore.DestroyTrackedMeshes then
        RenderCore.DestroyTrackedMeshes()
    end
    table.Empty(cachedStaticProps)
    table.Empty(skyboxProps)
    table.Empty(worldProps)
    table.Empty(meshCache)
    timer.Simple(0.1, CacheMapStaticProps)
end)

local function DebounceRebuildOnCvar(name)
    cvars.AddChangeCallback(name, function()
        if RenderCore and RenderCore.RequestRebuild then
            RenderCore.RequestRebuild(name)
        end
    end, "StaticPropsRebuild-" .. name)
end

DebounceRebuildOnCvar("rtx_spr_mat_whitelist")
DebounceRebuildOnCvar("rtx_spr_mat_blacklist")
DebounceRebuildOnCvar("rtx_spr_distance")