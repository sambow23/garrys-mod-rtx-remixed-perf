-- Custom Mesh Renderer using RTX Remix API
-- This bypasses GMod's IMesh and speaks directly to Remix via our binary module

if not CLIENT then return end

local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore
if not RenderCore then
    ErrorNoHalt("[RTX Remix] RenderCore not found!\n")
    return
end

-- Check for required modules
if not remixapi then
    ErrorNoHalt("[RTX Remix] remixapi module not loaded!\n")
    return
end

if not RemixMaterial then
    ErrorNoHalt("[RTX Remix] RemixMaterial module not loaded!\n")
    return
end

-- ConVars
local CONVARS = {
    ENABLED = CreateClientConVar("rtx_remix_mesh_enable", "0", true, false, "Enable RTX Remix API mesh rendering"),
    DEBUG = CreateClientConVar("rtx_remix_mesh_debug", "0", true, false, "Debug info for Remix meshes"),
    CHUNK_SIZE = CreateClientConVar("rtx_remix_mesh_chunk_size", "32768", true, false, "Chunk size for mesh combining")
}

-- State
local isEnabled = false
local mapMeshes = {
    opaque = {},
    translucent = {}
}
local activeInstances = {} -- List of { meshId, transform }
local buildState = { active = false, processed = 0, total = 0 }
local keepAliveMaterials = {} -- Materials that need to be rendered to stay resident in Remix

-- Helper: Validate Vertex
local function ValidateVertex(pos)
    if not pos or not pos.x or not pos.y or not pos.z then return false end
    if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then return false end -- NaN check
    return true
end

-- Helper: Get Chunk Key
local function GetChunkKey(x, y, z)
    return string.format("%d,%d,%d", x, y, z)
end

-- Cleanup
local function CleanupMeshes()
    remixapi.ClearAllBSPMeshes()
    mapMeshes = { opaque = {}, translucent = {} }
    activeInstances = {}
    keepAliveMaterials = {}
    
    -- Also clear materials? No, MaterialManager persists, but we might want to track our own
end

-- Create Material Wrapper
local materialCache = {}
local function GetOrCreateRemixMaterial(matName)
    if materialCache[matName] then return materialCache[matName] end
    
    -- Try to get hash
    local hash, hashStr = RemixMaterial.GetTextureHash(matName)
    
    -- If not found, force track it
    if not hash or hash == 0 then
        -- print("Force tracking " .. matName)
        RemixMaterial.TrackMaterial(matName)
        -- Try again immediately
        hash, hashStr = RemixMaterial.GetTextureHash(matName)
    end
    
    local useHash = hashStr
    if not useHash and hash and hash > 0 then
        useHash = hash
    end
    
    -- If still no hash, generate a stable fallback hash from the name
    -- so the geometry can at least be created and rendered (will be untextured in Remix)
    if not useHash or useHash == 0 then
         -- Use CRC of name to generate a pseudo-unique hash
         -- Remix expects 64-bit int.
         -- util.CRC returns a string decimal. 
         -- Let's just use a large constant offset + CRC
         local crc = tonumber(util.CRC(matName)) or 0
         useHash = 0xF000000000000000 + crc -- "Fake" range
         
         -- Warning only once per material
         -- print("[RTX Remix] Warning: Using fake hash for " .. matName)
    end
    
    local info = {
        hash = useHash,
        -- Try passing the hash string as the texture path to see if Remix picks it up
        -- This is a long shot but worth trying before modifying the runtime
        albedoTexture = hashStr, 
        normalTexture = "",
        roughnessTexture = "",
        metallicTexture = ""
    }
    
    local matId = RemixMaterial.CreateMaterial(matName .. "_remix", info)
    
    if matId and matId > 0 then
        materialCache[matName] = matId
        -- Add to keep-alive list
        if not keepAliveMaterials[matName] then
            local mat = Material(matName)
            if mat and not mat:IsError() then
                keepAliveMaterials[matName] = mat
            end
        end
        return matId
    end
    
    return nil
end

-- Build Meshes
local function BuildMapMeshes(cancelToken)
    if not NikNaks then return end
    
    CleanupMeshes()
    materialCache = {}
    
    print("[RTX Remix] Building API meshes...")
    local startTime = SysTime()
    local totalVerts = 0
    
    -- Coroutine for building
    local co = coroutine.create(function()
        local frameStartTime = SysTime()
        local frameBudget = 0.005 -- 5ms
        
        -- Get Leafs
        local leafs = NikNaks.CurrentMap:GetLeafs()
        buildState.total = table.Count(leafs)
        buildState.processed = 0
        
        -- PHASE 1: Precache Materials
        -- Scan all materials first and ensure they are tracked
        print("[RTX Remix] Phase 1: Scanning for materials...")
        local neededMaterials = {}
        local scanCount = 0
        
        for _, leaf in pairs(leafs) do
            local faces = leaf:GetFaces(true)
            if faces then
                for _, face in pairs(faces) do
                    if face:ShouldRender() and not face:IsDisplacement() and not face:IsSkyBox() then
                        local mat = face:GetMaterial()
                        if mat then neededMaterials[mat:GetName()] = true end
                    end
                end
            end
            
            scanCount = scanCount + 1
            -- Yield check during scan
            if scanCount % 50 == 0 then
                if SysTime() - frameStartTime > frameBudget then
                    coroutine.yield()
                    frameStartTime = SysTime()
                end
            end
        end
        
        -- Check tracking status
        local missingMaterials = {}
        local missingCount = 0
        
        for matName, _ in pairs(neededMaterials) do
            local hash = RemixMaterial.GetTextureHash(matName)
            if hash == 0 then
                missingMaterials[matName] = true
                missingCount = missingCount + 1
            end
        end
        
        if missingCount > 0 then
            print("[RTX Remix] Phase 1: Found " .. missingCount .. " untracked materials. Tracking...")
            
            for matName, _ in pairs(missingMaterials) do
                RemixMaterial.TrackMaterial(matName)
            end
            
            print("[RTX Remix] Phase 1: Waiting 1.0s for textures to load...")
            local waitEnd = SysTime() + 1.0
            while SysTime() < waitEnd do
                coroutine.yield()
            end
            
            -- Re-verify (optional, for debug)
            local stillMissing = 0
            for matName, _ in pairs(missingMaterials) do
                 if RemixMaterial.GetTextureHash(matName) == 0 then stillMissing = stillMissing + 1 end
            end
            print("[RTX Remix] Phase 1: Resuming. " .. stillMissing .. " materials still missing (will use fallbacks).")
        end

        -- PHASE 2: Mesh Generation
        print("[RTX Remix] Phase 2: Generaring meshes...")
        
        local chunkSize = CONVARS.CHUNK_SIZE:GetInt()
        
        -- Temporary storage for batching faces by chunk and material
        local pendingChunks = {}
        
        buildState.processed = 0
        for _, leaf in pairs(leafs) do
            if cancelToken and cancelToken.cancelled then return end
            
            local faces = leaf:GetFaces(true) -- true = renderable faces
            if faces then
                for _, face in pairs(faces) do
                    -- Filter faces
                    if not face:ShouldRender() or face:IsDisplacement() or face:IsSkyBox() then
                        -- Handle displacements separately?
                        -- For now, skip displacements in static prop pass
                    else
                        local mat = face:GetMaterial()
                        if mat then
                            local matName = mat:GetName()
                            
                            -- Calculate center for chunking
                            local verts = face:GetVertexs()
                            if verts and #verts >= 3 then
                                local center = Vector(0,0,0)
                                for _, v in ipairs(verts) do center:Add(v) end
                                center:Div(#verts)
                                
                                local cx = math.floor(center.x / chunkSize)
                                local cy = math.floor(center.y / chunkSize)
                                local cz = math.floor(center.z / chunkSize)
                                local key = GetChunkKey(cx, cy, cz)
                                
                                pendingChunks[key] = pendingChunks[key] or {}
                                pendingChunks[key][matName] = pendingChunks[key][matName] or {}
                                table.insert(pendingChunks[key][matName], face)
                            end
                        end
                    end
                end
            end
            
            buildState.processed = buildState.processed + 1
            
            -- Yield check
            if SysTime() - frameStartTime > frameBudget then
                coroutine.yield()
                frameStartTime = SysTime()
            end
        end
        
        -- Process batches and upload
        print("[RTX Remix] Batching and uploading meshes...")
        
        for key, matGroups in pairs(pendingChunks) do
            for matName, faces in pairs(matGroups) do
                if cancelToken and cancelToken.cancelled then return end
                
                -- Get Material ID
                local matId = GetOrCreateRemixMaterial(matName)
                if matId then 
                    -- Build vertex/index buffers
                    local vertices = {}
                    local indices = {}
                    local indexOffset = 0
                    
                    for _, face in ipairs(faces) do
                        local triData = face:GenerateVertexTriangleData()
                        if triData then
                            -- TriData is just a list of vertices for triangles (unindexed)
                            -- We can simple add them and generate indices 0,1,2, 3,4,5...
                            
                            -- Calculate face normal if needed (NikNaks verts usually have normals)
                            local faceNormal = face:GetNormal()
                            
                            for _, vert in ipairs(triData) do
                                -- Convert to Remix format
                                -- NikNaks vert: pos (Vector), u, v, normal (Vector)
                                
                                local normal = vert.normal or faceNormal
                                
                                table.insert(vertices, {
                                    pos = vert.pos,
                                    normal = normal,
                                    u = vert.u,
                                    v = vert.v,
                                    color = 0xFFFFFFFF
                                })
                                
                                table.insert(indices, indexOffset)
                                indexOffset = indexOffset + 1
                            end
                            
                            -- Split mesh if too large (uint16 limit? Remix uses uint32 indices, but let's be safe)
                            if #vertices > 60000 then
                                local meshId = remixapi.UploadStaticPropMesh(
                                    "chunk_" .. key .. "_" .. matName,
                                    vertices,
                                    indices,
                                    matId
                                )
                                
                                if meshId > 0 then
                                    local isTranslucent = faces[1]:IsTranslucent()
                                    local list = isTranslucent and mapMeshes.translucent or mapMeshes.opaque
                                    table.insert(list, meshId)
                                    table.insert(activeInstances, { meshId = meshId, transform = Matrix() }) -- Identity transform for world
                                end
                                
                                vertices = {}
                                indices = {}
                                indexOffset = 0
                            end
                        end
                    end
                    
                    -- Upload remaining
                    if #vertices > 0 then
                        local meshId = remixapi.UploadStaticPropMesh(
                            "chunk_" .. key .. "_" .. matName,
                            vertices,
                            indices,
                            matId
                        )
                        
                        if meshId > 0 then
                            local isTranslucent = faces[1]:IsTranslucent()
                            local list = isTranslucent and mapMeshes.translucent or mapMeshes.opaque
                            table.insert(list, meshId)
                            table.insert(activeInstances, { meshId = meshId, transform = Matrix() })
                            totalVerts = totalVerts + #vertices
                        end
                    end
                end
            end
            
            -- Yield check
            if SysTime() - frameStartTime > frameBudget then
                coroutine.yield()
                frameStartTime = SysTime()
            end
        end
        
        buildState.active = false
        print(string.format("[RTX Remix] Mesh build complete. %d vertices uploaded.", totalVerts))
    end)
    
    -- Schedule coroutine
    buildState.active = true
    hook.Add("Think", "RTXRemixMeshBuild", function()
        if not buildState.active then
            hook.Remove("Think", "RTXRemixMeshBuild")
            return
        end
        
        local ok, err = coroutine.resume(co)
        if not ok then
            ErrorNoHalt("Mesh build error: " .. tostring(err) .. "\n")
            buildState.active = false
        end
        
        if coroutine.status(co) == "dead" then
            buildState.active = false
        end
    end)
end

-- Rendering
local function RenderRemixMeshes()
    if not isEnabled then return end
    
    -- Draw all instances
    -- Since we added them to activeInstances with identity transform, we just draw them
    -- NOTE: Ideally we'd use remixapi.DrawInstanceBatch if we exposed it properly with array of structs
    -- For now, DrawMeshInstance one by one is fine for Lua prototype
    
    local count = 0
    for _, inst in ipairs(activeInstances) do
        remixapi.DrawMeshInstance(inst.meshId, inst.transform, 0)
        count = count + 1
    end
    
    -- Keep textures alive for Remix by forcing a draw call
    if not table.IsEmpty(keepAliveMaterials) then
        -- Draw microscopic quads far away
        local dummyPos = Vector(0,0,-10000)
        local dummyNormal = Vector(0,0,1)
        local dummySize = 0.1
        local c = Color(255,255,255,255) -- Full opacity to ensure it's not culled by alpha
        
        cam.PushModelMatrix(Matrix())
        for _, mat in pairs(keepAliveMaterials) do
            if mat then
                render.SetMaterial(mat)
                render.DrawQuadEasy(dummyPos, dummyNormal, dummySize, dummySize, c, 0)
            end
        end
        cam.PopModelMatrix()
    end
    
    if CONVARS.DEBUG:GetBool() then
        -- Maybe print stats once a second?
    end
end

-- Hooks and Enable/Disable
local function Enable()
    if isEnabled then return end
    isEnabled = true
    
    -- Build meshes if empty
    if #mapMeshes.opaque == 0 and #mapMeshes.translucent == 0 then
        BuildMapMeshes()
    end
    
    -- Hook rendering
    hook.Add("PreDrawOpaqueRenderables", "RTXRemixRender", function()
        RenderRemixMeshes()
        -- Disable normal world rendering?
        -- If we return true here, it stops opaque renderables? No.
    end)
    
    -- Hide world
    RunConsoleCommand("r_drawworld", "0")
end

local function Disable()
    if not isEnabled then return end
    isEnabled = false
    
    hook.Remove("PreDrawOpaqueRenderables", "RTXRemixRender")
    RunConsoleCommand("r_drawworld", "1")
end

cvars.AddChangeCallback("rtx_remix_mesh_enable", function(_, _, new)
    if tobool(new) then Enable() else Disable() end
end)

concommand.Add("rtx_remix_rebuild", function()
    BuildMapMeshes()
end)

-- Auto enable if convar set
if CONVARS.ENABLED:GetBool() then
    Enable()
end

