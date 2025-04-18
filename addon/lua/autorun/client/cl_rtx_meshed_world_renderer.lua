-- Disables source engine world rendering and replaces it with chunked mesh rendering instead, fixes engine culling issues. 
-- MAJOR THANK YOU to the creator of NikNaks, a lot of this would not be possible without it.

if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end
require("niknaks")

-- ConVars
local CONVARS = {
    ENABLED = CreateClientConVar("rtx_mwr_enable", "1", true, false, "Forces custom mesh rendering of map"),
    DEBUG = CreateClientConVar("rtx_mwr_enable_debug", "0", true, false, "Shows debug info for mesh rendering"),
    CHUNK_SIZE = CreateClientConVar("rtx_mwr_chunk_size", "65536", true, false, "Size of chunks for mesh combining"),
    SHOW_3DSKY_WARNING = CreateClientConVar("rtx_mwr_show_3dsky_warning", "1", true, false, "Show warning when enabling r_3dsky"),
}

-- Local Variables and Caches
local mapMeshes = {
    opaque = {},
    translucent = {},
}
local isEnabled = false
local renderStats = {draws = 0}
local materialCache = {}
local Vector = Vector
local math_min = math.min
local math_max = math.max
local math_huge = math.huge
local math_floor = math.floor
local table_insert = table.insert
local MAX_VERTICES = 10000
local MAX_CHUNK_VERTS = 32768
local bDrawingSkybox = false
local mapBounds = {
    min = Vector(0, 0, 0),
    max = Vector(0, 0, 0),
    initialized = false
}
local ignoreTexture = Material("rtx/ignore")

-- Get native functions
local MeshRenderer = MeshRenderer or {}
local CreateOptimizedMeshBatch = MeshRenderer.CreateOptimizedMeshBatch or function() error("MeshRenderer module not loaded") end
local ProcessRegionBatch = MeshRenderer.ProcessRegionBatch or function() error("MeshRenderer module not loaded") end
local GenerateChunkKey = MeshRenderer.GenerateChunkKey or function(x, y, z) return x .. "," .. y .. "," .. z end
local CalculateEntityBounds = MeshRenderer.CalculateEntityBounds or function() error("MeshRenderer module not loaded") end
local FilterEntitiesByDistance = MeshRenderer.FilterEntitiesByDistance or function() error("MeshRenderer module not loaded") end

-- Pre-allocate common vectors and tables for reuse
local vertexBuffer = {
    positions = {},
    normals = {},
    uvs = {}
}

-- Helper Functions
local function Show3DSkyWarning()
    -- Don't show if user has disabled warnings
    if not CONVARS.SHOW_3DSKY_WARNING:GetBool() then return end
    
    -- Create the warning panel
    local frame = vgui.Create("DFrame")
    frame:SetTitle("RTX Meshed World Renderer Warning")
    frame:SetSize(400, 200)
    frame:Center()
    frame:MakePopup()
    
    local warningText = vgui.Create("DLabel", frame)
    warningText:SetPos(20, 40)
    warningText:SetSize(360, 80)
    warningText:SetText("You have enabled r_3dsky which may cause rendering issues with RTX Remix due how the engine culls the skybox. It's recommended to keep r_3dsky disabled for best results.")
    warningText:SetWrap(true)
    
    local dontShowAgain = vgui.Create("DCheckBoxLabel", frame)
    dontShowAgain:SetPos(20, 130)
    dontShowAgain:SetText("Don't show this warning again")
    dontShowAgain:SetValue(false)
    dontShowAgain.OnChange = function(self, val)
        if val then
            RunConsoleCommand("rtx_mwr_show_3dsky_warning", "0")
        else
            RunConsoleCommand("rtx_mwr_show_3dsky_warning", "1")
        end
    end
    
    local okButton = vgui.Create("DButton", frame)
    okButton:SetText("OK")
    okButton:SetPos(150, 160)
    okButton:SetSize(100, 25)
    okButton.DoClick = function()
        frame:Close()
    end
end

-- Main Stuff
local function InitializeMapBounds()
    if mapBounds.initialized then return true end
    
    if NikNaks and NikNaks.CurrentMap then
        local min, max
        
        -- Try WorldMin/Max first
        if NikNaks.CurrentMap.WorldMin and NikNaks.CurrentMap.WorldMax then
            min = NikNaks.CurrentMap:WorldMin()
            max = NikNaks.CurrentMap:WorldMax()
        end
        
        -- If that failed, try GetBrushBounds
        if (not min or not max) and NikNaks.CurrentMap.GetBrushBounds then
            min, max = NikNaks.CurrentMap:GetBrushBounds()
        end
        
        if min and max then
            mapBounds.min = min
            mapBounds.max = max
            mapBounds.initialized = true
            
            -- Add some padding to avoid edge clipping
            mapBounds.min = mapBounds.min - Vector(128, 128, 128)
            mapBounds.max = mapBounds.max + Vector(128, 128, 128)
            
            print("[RTX Remix Fixes 2 - Meshed World Renderer] Map boundaries loaded:")
            print("  Min: " .. tostring(mapBounds.min))
            print("  Max: " .. tostring(mapBounds.max))
            return true
        end
    end
    
    -- Try next frame
    timer.Simple(0, InitializeMapBounds)
    return false
end

local function IsPositionInMapBounds(pos)
    if not mapBounds.initialized then return true end
    
    return pos.x >= mapBounds.min.x and pos.x <= mapBounds.max.x and
           pos.y >= mapBounds.min.y and pos.y <= mapBounds.max.y and
           pos.z >= mapBounds.min.z and pos.z <= mapBounds.max.z
end

local function IsFaceInMapBounds(face)
    if not mapBounds.initialized then return true end
    
    local vertices = face:GetVertexs()
    if not vertices or #vertices == 0 then return false end
    
    -- Check if any vertex is inside the bounds
    for _, vert in ipairs(vertices) do
        if IsPositionInMapBounds(vert) then
            return true
        end
    end
    
    return false
end

local function ValidateVertex(pos)
    -- First check if pos exists
    if not pos then return false end
    
    -- Check vertex bounds (16384 is the Source engine map limit)
    local mapLimits = Vector(16384, 16384, 16384)
    local negLimits = Vector(-16384, -16384, -16384)
    
    -- Check if pos has valid numbers before IsWithinBounds
    if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then -- NaN check
        return false
    end
    
    return RTXMath.IsWithinBounds(pos, negLimits, mapLimits)
end

local function IsBrushEntity(face)
    if not face then return false end
    
    -- First check if it's a brush model
    if face.__bmodel and face.__bmodel > 0 then
        return true -- Any non-zero bmodel index indicates it's a brush entity
    end
    
    -- Secondary check for brush entities using parent entity
    local parent = face.__parent
    if parent and isentity(parent) and parent:GetClass() then
        -- If the face has a valid parent entity, it's likely a brush entity
        return true
    end
    
    return false
end

local function IsSkyboxFace(face)
    if not face then return false end
    
    local material = face:GetMaterial()
    if not material then return false end
    
    local matName = material:GetName():lower()
    
    return matName:find("tools/toolsskybox") or
           matName:find("skybox/") or
           matName:find("sky_") or
           false
end

local function SplitChunk(faces, chunkSize)
    local subChunks = {}
    for _, face in ipairs(faces) do
        local vertices = face:GetVertexs()
        if not vertices or #vertices == 0 then continue end
        
        -- Calculate face center
        local center = Vector(0, 0, 0)
        for _, vert in ipairs(vertices) do
            center:Add(vert)
        end
        center:Div(#vertices)
        
        -- Use smaller chunk size for subdivision
        local subX = math_floor(center.x / (chunkSize/2))
        local subY = math_floor(center.y / (chunkSize/2))
        local subZ = math_floor(center.z / (chunkSize/2))
        local subKey = GetChunkKey(subX, subY, subZ)
        
        subChunks[subKey] = subChunks[subKey] or {}
        table_insert(subChunks[subKey], face)
    end
    return subChunks
end

local function DetermineOptimalChunkSize(totalFaces)
    -- Base chunk size on face density, but keep within reasonable bounds
    local density = totalFaces / (16384 * 16384 * 16384) -- Approximate map volume
    return math_max(4096, math_min(65536, math_floor(1 / density * 32768)))
end

local function CreateMeshBatch(vertices, material, maxVertsPerMesh)
    local meshes = {}
    local currentVerts = {}
    local vertCount = 0
    
    for i = 1, #vertices, 3 do -- Process in triangles
        -- Add all three vertices of the triangle
        for j = 0, 2 do
            if vertices[i + j] then
                table_insert(currentVerts, vertices[i + j])
                vertCount = vertCount + 1
            end
        end
        
        -- Create new mesh when we hit the vertex limit
        if vertCount >= maxVertsPerMesh - 3 then -- Leave room for one more triangle
            local newMesh = Mesh(material)
            mesh.Begin(newMesh, MATERIAL_TRIANGLES, #currentVerts)
            for _, vert in ipairs(currentVerts) do
                mesh.Position(vert.pos)
                mesh.Normal(vert.normal)
                mesh.TexCoord(0, vert.u or 0, vert.v or 0)
                mesh.AdvanceVertex()
            end
            mesh.End()
            
            table_insert(meshes, newMesh)
            currentVerts = {}
            vertCount = 0
        end
    end
    
    -- Handle remaining vertices
    if #currentVerts > 0 then
        local newMesh = Mesh(material)
        mesh.Begin(newMesh, MATERIAL_TRIANGLES, #currentVerts)
        for _, vert in ipairs(currentVerts) do
            mesh.Position(vert.pos)
            mesh.Normal(vert.normal)
            mesh.TexCoord(0, vert.u or 0, vert.v or 0)
            mesh.AdvanceVertex()
        end
        mesh.End()
        
        table_insert(meshes, newMesh)
    end
    
    return meshes
end

local function GetChunkKey(x, y, z)
    -- Use native RTXMath implementation for better performance
    return tostring(RTXMath.GenerateChunkKey(x, y, z))
end

-- Main Mesh Building Function
local function BuildMapMeshes()
    -- Clean up existing meshes first
    for renderType, chunks in pairs(mapMeshes) do
        for chunkKey, materials in pairs(chunks) do
            for matName, group in pairs(materials) do
                if group.meshes then
                    for _, mesh in ipairs(group.meshes) do
                        if mesh and mesh.Destroy then
                            mesh:Destroy()
                        end
                    end
                end
            end
        end
    end

    mapMeshes = {
        opaque = {},
        translucent = {},
    }
    materialCache = {}
    
    if not NikNaks or not NikNaks.CurrentMap then return end

    print("[RTX Remix Fixes 2 - Meshed World Renderer] Building chunked meshes...")
    local startTime = SysTime()
    
    -- Count total faces for chunk size optimization
    local totalFaces = 0
    for _, leaf in pairs(NikNaks.CurrentMap:GetLeafs()) do
        if not leaf or leaf:IsOutsideMap() then continue end
        local leafFaces = leaf:GetFaces(true)
        if leafFaces then
            totalFaces = totalFaces + #leafFaces
        end
    end
    
    local chunkSize = DetermineOptimalChunkSize(totalFaces)
    CONVARS.CHUNK_SIZE:SetInt(chunkSize)
    
    local chunks = {
        opaque = {},
        translucent = {},
    }
    
    -- Sort faces into chunks with optimized table operations
    for _, leaf in pairs(NikNaks.CurrentMap:GetLeafs()) do  
        if not leaf or leaf:IsOutsideMap() then continue end
        
        local leafFaces = leaf:GetFaces(true)
        if not leafFaces then continue end
    
        for _, face in pairs(leafFaces) do
            if not face or 
               face:IsDisplacement() or
               IsBrushEntity(face) or
               not face:ShouldRender() or 
               IsSkyboxFace(face) or
               not IsFaceInMapBounds(face) then -- Add this new check
                continue 
            end
            
            local vertices = face:GetVertexs()
            if not vertices or #vertices == 0 then continue end
            
            -- Optimized center calculation
            local center = Vector(0, 0, 0)
            local vertCount = #vertices
            for i = 1, vertCount do
                local vert = vertices[i]
                if not vert then continue end
                center:Add(vert)
            end
            center:Div(vertCount)
            
            local chunkX = math_floor(center.x / chunkSize)
            local chunkY = math_floor(center.y / chunkSize)
            local chunkZ = math_floor(center.z / chunkSize)
            local chunkKey = GetChunkKey(chunkX, chunkY, chunkZ)
            
            local material = face:GetMaterial()
            if not material then continue end
            
            local matName = material:GetName()
            if not matName then continue end
            
            if not materialCache[matName] then
                materialCache[matName] = material
            end
            
            local chunkGroup = face:IsTranslucent() and chunks.translucent or chunks.opaque
            
            chunkGroup[chunkKey] = chunkGroup[chunkKey] or {}
            chunkGroup[chunkKey][matName] = chunkGroup[chunkKey][matName] or {
                material = materialCache[matName],
                faces = {}
            }
            
            table_insert(chunkGroup[chunkKey][matName].faces, face)
        end
    end
    
    -- Create separate mesh creation functions for regular faces and displacements
    local function CreateRegularMeshGroup(faces, material)
        if not faces or #faces == 0 or not material then return nil end
        
        -- Track chunk bounds
        local minBounds = Vector(math_huge, math_huge, math_huge)
        local maxBounds = Vector(-math_huge, -math_huge, -math_huge)
        
        -- Collect and validate vertices
        local allVertices = {}
        for _, face in ipairs(faces) do
            local verts = face:GenerateVertexTriangleData()
            if verts then
                local faceValid = true
                for _, vert in ipairs(verts) do
                    if not ValidateVertex(vert.pos) then
                        faceValid = false
                        break
                    end
                    
                    -- Update bounds
                    minBounds.x = math_min(minBounds.x, vert.pos.x)
                    minBounds.y = math_min(minBounds.y, vert.pos.y)
                    minBounds.z = math_min(minBounds.z, vert.pos.z)
                    maxBounds.x = math_max(maxBounds.x, vert.pos.x)
                    maxBounds.y = math_max(maxBounds.y, vert.pos.y)
                    maxBounds.z = math_max(maxBounds.z, vert.pos.z)
                end
                
                if faceValid then
                    for _, vert in ipairs(verts) do
                        table_insert(allVertices, vert)
                    end
                end
            end
        end
        
        -- Check chunk size and split if needed
        local chunkSize = maxBounds - minBounds
        if chunkSize.x > MAX_CHUNK_VERTS or 
           chunkSize.y > MAX_CHUNK_VERTS or 
           chunkSize.z > MAX_CHUNK_VERTS then
            -- Split into sub-chunks and process each
            local subChunks = SplitChunk(faces, CONVARS.CHUNK_SIZE:GetInt())
            local allMeshes = {}
            
            for _, subFaces in pairs(subChunks) do
                local subMeshes = CreateRegularMeshGroup(subFaces, material)
                if subMeshes then
                    for _, mesh in ipairs(subMeshes) do
                        table_insert(allMeshes, mesh)
                    end
                end
            end
            
            return allMeshes
        end
        
        -- Create mesh batches for this chunk
        return CreateMeshBatch(allVertices, material, MAX_VERTICES)
    end

    -- Create combined meshes with separate handling
    for renderType, chunkGroup in pairs(chunks) do
        for chunkKey, materials in pairs(chunkGroup) do
            mapMeshes[renderType][chunkKey] = {}
            for matName, group in pairs(materials) do
                if group.faces and #group.faces > 0 then
                    local meshes = CreateRegularMeshGroup(group.faces, group.material)
                    
                    if meshes then
                        mapMeshes[renderType][chunkKey][matName] = {
                            meshes = meshes,
                            material = group.material
                        }
                    end
                end
            end
        end
    end

    print(string.format("[RTX Remix Fixes 2 - Meshed World Renderer] Built chunked meshes in %.2f seconds", SysTime() - startTime))
end

-- Rendering Functions
local function RenderCustomWorld(translucent)
    if not isEnabled then return end
    
    -- Initialize map bounds if not already done
    if not mapBounds.initialized then
        InitializeMapBounds()
    end

    local draws = 0
    local currentMaterial = nil
    
    -- Inline render state changes for speed
    if translucent then
        render.SetBlend(1)
        render.OverrideDepthEnable(true, true)
    end
    
    -- Get player position for culling
    local playerPos = LocalPlayer():GetPos()
    
    -- Regular faces - add safety check for nil
    local groupType = translucent and "translucent" or "opaque"
    local groups = mapMeshes[groupType]
    
    -- Make sure groups exists before trying to iterate
    if not groups then
        print("[RTX Remix Fixes 2 - Meshed World Renderer] Warning: No " .. groupType .. " mesh groups found")
        return
    end
    
    for chunkKey, chunkMaterials in pairs(groups) do
        -- Check if this chunk should be rendered
        local shouldRender = false
        
        -- Split the chunkKey back into coordinates
        local x, y, z = string.match(chunkKey, "([^,]+),([^,]+),([^,]+)")
        if x and y and z then
            x, y, z = tonumber(x), tonumber(y), tonumber(z)
            local chunkSize = CONVARS.CHUNK_SIZE:GetInt()
            
            -- Calculate chunk center position
            local chunkCenter = Vector(
                x * chunkSize + chunkSize/2,
                y * chunkSize + chunkSize/2,
                z * chunkSize + chunkSize/2
            )
            
            -- Check if chunk is inside map bounds
            if IsPositionInMapBounds(chunkCenter) then
                shouldRender = true
            end
        else
            shouldRender = true  -- If we can't parse the key, render anyway
        end
        
        if shouldRender then
            for _, group in pairs(chunkMaterials) do
                if not group.meshes then continue end
                
                if currentMaterial ~= group.material then
                    render.SetMaterial(group.material)
                    currentMaterial = group.material
                end
                
                local meshes = group.meshes
                for i = 1, #meshes do
                    meshes[i]:Draw()
                    draws = draws + 1
                end
            end
        end
    end
    
    if translucent then
        render.OverrideDepthEnable(false)
    end
    
    renderStats.draws = draws
end

-- Skybox Hooks
hook.Add("PreDrawSkyBox", "RTXSkyboxDetection", function()
    bDrawingSkybox = true
end)

hook.Add("PostDrawSkyBox", "RTXSkyboxDetection", function()
    bDrawingSkybox = false
end)

-- Enable/Disable Functions
local function EnableCustomRendering()
    if isEnabled then return end
    isEnabled = true

    hook.Add("RenderScene", "RTXWorldMaterialOverride", function()
        if not bDrawingSkybox then
            render.WorldMaterialOverride(ignoreTexture)
        end
    end)

    hook.Add("PreDrawWorld", "RTXHideWorld", function()
        if render.GetRenderTarget() then return end
        if bDrawingSkybox then return end
        render.OverrideDepthEnable(true, false)
        return true
    end)
    
    hook.Add("PostDrawWorld", "RTXHideWorld", function()
        if render.GetRenderTarget() then return end
        if bDrawingSkybox then return end
        render.OverrideDepthEnable(false)
    end)
    
    hook.Add("PreDrawOpaqueRenderables", "RTXCustomWorld", function()
        if bDrawingSkybox then return end
        if render.GetRenderTarget() then return end
        RenderCustomWorld(false)
    end)
    
    hook.Add("PreDrawTranslucentRenderables", "RTXCustomWorld", function()
        if bDrawingSkybox then return end
        if render.GetRenderTarget() then return end
        RenderCustomWorld(true)
    end)
end

local function DisableCustomRendering()
    if not isEnabled then return end
    isEnabled = false

    hook.Remove("RenderScene", "RTXWorldMaterialOverride")
    hook.Remove("PreDrawWorld", "RTXHideWorld")
    hook.Remove("PostDrawWorld", "RTXHideWorld")
    hook.Remove("PreDrawOpaqueRenderables", "RTXCustomWorld")
    hook.Remove("PreDrawTranslucentRenderables", "RTXCustomWorld")
    
    -- Make sure the world material override is cleared when disabling
    render.WorldMaterialOverride()
end

-- Initialization and Cleanup
local function Initialize()
    InitializeMapBounds()
    local success, err = pcall(BuildMapMeshes)
    if not success then
        ErrorNoHalt("[RTX Remix Fixes 2 - Meshed World Renderer] Failed to build meshes: " .. tostring(err) .. "\n")
        DisableCustomRendering()
        return
    end
    
    timer.Simple(1, function()
        if CONVARS.ENABLED:GetBool() then
            local success, err = pcall(EnableCustomRendering)
            if not success then
                ErrorNoHalt("[RTX Remix Fixes 2 - Meshed World Renderer] Failed to enable custom rendering: " .. tostring(err) .. "\n")
                DisableCustomRendering()
            end
        end
    end)
end

-- Hooks
hook.Add("InitPostEntity", "RTXMeshInit", Initialize)

hook.Add("PostCleanupMap", "RTXMeshRebuild", Initialize)

hook.Add("PreDrawParticles", "ParticleSkipper", function()
    return true
end)

hook.Add("ShutDown", "RTXCustomWorld", function()
    DisableCustomRendering()
    
    for renderType, chunks in pairs(mapMeshes) do
        for chunkKey, materials in pairs(chunks) do
            for matName, group in pairs(materials) do
                if group.meshes then
                    for _, mesh in ipairs(group.meshes) do
                        if mesh.Destroy then
                            mesh:Destroy()
                        end
                    end
                end
            end
        end
    end
    
    mapMeshes = {
        opaque = {},
        translucent = {}
    }
    materialCache = {}
end)

-- ConVar Changes
cvars.AddChangeCallback("rtx_mwr_enable", function(_, _, new)
    if tobool(new) then
        EnableCustomRendering()
    else
        DisableCustomRendering()
    end
end)

cvars.AddChangeCallback("r_3dsky", function(_, _, newValue)
    if newValue == "1" then
        Show3DSkyWarning()
    end
end)

hook.Add("InitPostEntity", "RTXCheck3DSky", function()
    timer.Simple(2, function()
        if GetConVar("r_3dsky"):GetBool() then
            Show3DSkyWarning()
        end
    end)
end)

-- Console Commands
concommand.Add("rtx_mwr_rebuild_meshes", BuildMapMeshes)