-- Disables source engine world rendering and replaces it with chunked mesh rendering instead, fixes engine culling issues. 
-- MAJOR THANK YOU to the creator of NikNaks, a lot of this would not be possible without it.
if not CLIENT then return end
require("niknaks")
local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

-- ConVars
local CONVARS = {
    ENABLED = CreateClientConVar("rtx_mwr", "1", true, false, "Forces custom mesh rendering of map"),
    DEBUG = CreateClientConVar("rtx_mwr_debug", "0", true, false, "Shows debug info for mesh rendering"),
    CHUNK_SIZE = CreateClientConVar("rtx_mwr_chunk_size", "65536", true, false, "Size of chunks for mesh combining"),
    CAPTURE_MODE = CreateClientConVar("rtx_mwr_capture_mode", "0", true, false, "Toggles r_drawworld for capture mode"),
    MAT_WHITELIST = CreateClientConVar("rtx_mwr_mat_whitelist", "", true, false, "Comma-separated material name substrings to include"),
    MAT_BLACKLIST = CreateClientConVar("rtx_mwr_mat_blacklist", "toolsskybox,skybox/", true, false, "Comma-separated material name substrings to exclude"),
    DISTANCE = CreateClientConVar("rtx_mwr_distance", "0", true, false, "World chunk distance limit (0 = off)")
}

-- Local Variables and Caches
local mapMeshes = {
    opaque = {},
    translucent = {},
}
local isEnabled = false
local renderStats = {draws = 0}
local Vector = Vector
local math_min = math.min
local math_max = math.max
local math_huge = math.huge
local math_floor = math.floor
local table_insert = table.insert
local MAX_VERTICES = 10000
local MAX_CHUNK_VERTS = 32768
-- PVS culling removed

-- Deprecated BuildMatcherList removed; use RenderCore.IsMaterialAllowed

local function IsMaterialAllowed(matName)
    if not matName then return false end
    if RenderCore and RenderCore.IsMaterialAllowed then
        return RenderCore.IsMaterialAllowed(matName, CONVARS.MAT_WHITELIST:GetString(), CONVARS.MAT_BLACKLIST:GetString())
    end
    return true -- fallback allow
end

-- Pre-allocate common vectors and tables for reuse
local vertexBuffer = {
    positions = {},
    normals = {},
    uvs = {}
}

local function ValidateVertex(pos)
    if RenderCore and RenderCore.ValidateVertex then
        return RenderCore.ValidateVertex(pos)
    end
    if not pos or not pos.x or not pos.y or not pos.z then return false end
    if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then return false end
    if math.abs(pos.x) > 16384 or math.abs(pos.y) > 16384 or math.abs(pos.z) > 16384 then return false end
    return true
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
            mesh.Begin(newMesh, MATERIAL_TRIANGLES, #currentVerts / 3)
            for _, vert in ipairs(currentVerts) do
                mesh.Position(vert.pos)
                mesh.Normal(vert.normal)
                mesh.TexCoord(0, vert.u or 0, vert.v or 0)
                mesh.AdvanceVertex()
            end
            mesh.End()
            
            table_insert(meshes, newMesh)
            if RenderCore and RenderCore.TrackMesh then
                RenderCore.TrackMesh(newMesh)
            end
            currentVerts = {}
            vertCount = 0
        end
    end
    
    -- Handle remaining vertices
    if #currentVerts > 0 then
        local newMesh = Mesh(material)
        mesh.Begin(newMesh, MATERIAL_TRIANGLES, #currentVerts / 3)
        for _, vert in ipairs(currentVerts) do
            mesh.Position(vert.pos)
            mesh.Normal(vert.normal)
            mesh.TexCoord(0, vert.u or 0, vert.v or 0)
            mesh.AdvanceVertex()
        end
        mesh.End()
        
        table_insert(meshes, newMesh)
        if RenderCore and RenderCore.TrackMesh then
            RenderCore.TrackMesh(newMesh)
        end
    end
    
    return meshes
end

local function GetChunkKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

-- Main Mesh Building Function
local function BuildMapMeshes(cancelToken)
    -- Clean up existing meshes first (best-effort)
    for renderType, chunks in pairs(mapMeshes) do
        for chunkKey, materials in pairs(chunks) do
            for matName, group in pairs(materials) do
                if group.meshes then
                    for _, m in ipairs(group.meshes) do
                        if m and m.Destroy then
                            pcall(function() m:Destroy() end)
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
    
    if not NikNaks or not NikNaks.CurrentMap then return end

    print("[RTX Fixes] Building chunked meshes...")
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
    local okLeafs, allLeafs = pcall(function() return NikNaks.CurrentMap:GetLeafs() end)
    if not okLeafs or not allLeafs then
        ErrorNoHalt("[RTX Fixes] GetLeafs failed\n")
        return
    end
    for _, leaf in pairs(allLeafs) do  
        if not leaf or leaf:IsOutsideMap() then continue end
        
        local okFaces, leafFaces = pcall(function() return leaf:GetFaces(true) end)
        if not leafFaces then continue end
    
        for _, face in pairs(leafFaces) do
            if not face or 
               face:IsDisplacement() or -- Skip displacements early
               IsBrushEntity(face) or
               not face:ShouldRender() or 
               IsSkyboxFace(face) then 
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
            if not IsMaterialAllowed(matName) then continue end
            if RenderCore and RenderCore.GetMaterial then
                material = RenderCore.GetMaterial(matName)
            end
            
            local chunkGroup = face:IsTranslucent() and chunks.translucent or chunks.opaque
            
            chunkGroup[chunkKey] = chunkGroup[chunkKey] or {}
            chunkGroup[chunkKey][matName] = chunkGroup[chunkKey][matName] or {
                material = material,
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
        local meshes = CreateMeshBatch(allVertices, material, MAX_VERTICES)
        return meshes, minBounds, maxBounds
    end

    -- Create combined meshes with frame-budgeted coroutine
    local co
    co = coroutine.create(function()
        local startTime = SysTime()
        local frameBudget = 0.003 -- start ~3ms per frame
        local targetBudget = 0.003
        for renderType, chunkGroup in pairs(chunks) do
            for chunkKey, materials in pairs(chunkGroup) do
                mapMeshes[renderType][chunkKey] = {}
                for matName, group in pairs(materials) do
                    if cancelToken and cancelToken.cancelled then return end
                    if group.faces and #group.faces > 0 then
                        local meshes, mins, maxs = CreateRegularMeshGroup(group.faces, group.material)
                        if meshes then
                            mapMeshes[renderType][chunkKey][matName] = {
                                meshes = meshes,
                                material = group.material
                            }
                            -- update chunk bounds
                            local chunkTable = mapMeshes[renderType][chunkKey]
                            if mins and maxs then
                                local cmins = chunkTable._mins
                                local cmaxs = chunkTable._maxs
                                if not cmins or not cmaxs then
                                    chunkTable._mins = mins
                                    chunkTable._maxs = maxs
                                else
                                    cmins.x = math_min(cmins.x, mins.x)
                                    cmins.y = math_min(cmins.y, mins.y)
                                    cmins.z = math_min(cmins.z, mins.z)
                                    cmaxs.x = math_max(cmaxs.x, maxs.x)
                                    cmaxs.y = math_max(cmaxs.y, maxs.y)
                                    cmaxs.z = math_max(cmaxs.z, maxs.z)
                                end
                            end
                        end
                    end
                    if cancelToken and cancelToken.cancelled then return end
                    if SysTime() - startTime > frameBudget then
                        coroutine.yield()
                        local spent = SysTime() - startTime
                        -- simple adaptation: nudge budget toward target if we exceed a bit
                        if spent > frameBudget * 1.2 then
                            frameBudget = math.max(0.001, frameBudget * 0.9)
                        elseif spent < frameBudget * 0.8 then
                            frameBudget = math.min(0.006, frameBudget * 1.1)
                        end
                        startTime = SysTime()
                    end
                end
            end
        end
    end)

    -- Drive the coroutine over frames
    local function StepBuilder()
        if not co then return end
        if coroutine.status(co) == "dead" then return end
        local ok, err = coroutine.resume(co)
        if not ok then
            ErrorNoHalt("[RTX Fixes] Build coroutine error: " .. tostring(err) .. "\n")
            return
        end
        if coroutine.status(co) ~= "dead" then
            timer.Simple(0, StepBuilder)
        end
    end
    StepBuilder()

    print(string.format("[RTX Fixes] Built chunked meshes in %.2f seconds", SysTime() - startTime))
end

-- Rendering Functions
local function RenderCustomWorld(translucent)
    if not isEnabled then return end

    local draws = 0
    local currentMaterial = nil
    local chunksVisited = 0
    
    -- Regular faces
    local groups = translucent and mapMeshes.translucent or mapMeshes.opaque
    local maxDist = CONVARS.DISTANCE:GetFloat()
    local useDist = maxDist > 0
    local ply = LocalPlayer and LocalPlayer() or nil
    local eyePos = ply and ply.GetPos and ply:GetPos() or nil
    for _, chunkMaterials in pairs(groups) do
        chunksVisited = chunksVisited + 1
        local cmins, cmaxs = chunkMaterials._mins, chunkMaterials._maxs
        if cmins and cmaxs and useDist and eyePos then
            local center = (cmins + cmaxs) * 0.5
            if RenderCore and RenderCore.ShouldCullByDistance and RenderCore.ShouldCullByDistance(center, eyePos, maxDist) then
                continue
            end
        end
        for key, group in pairs(chunkMaterials) do
            if key == "_mins" or key == "_maxs" then continue end
            if not group or not group.meshes then continue end
            -- Submit meshes to central render queue
            local meshes = group.meshes
            for i = 1, #meshes do
                local m = meshes[i]
                if m then
                    RenderCore.Submit({
                        material = group.material,
                        mesh = m,
                        translucent = translucent
                    })
                    draws = draws + 1
                end
            end
        end
    end
    
    renderStats.draws = draws
    renderStats.chunksVisited = chunksVisited
end

-- Stats provider for unified overlay
RenderCore.RegisterStats("RTXWorld", function()
    return string.format("World draws: %d | chunks: %d",
        renderStats.draws or 0,
        renderStats.chunksVisited or 0)
end)

-- Enable/Disable Functions
local function EnableCustomRendering()
    if isEnabled then return end
    isEnabled = true

    -- Disable world rendering using render.OverrideDepthEnable
    RenderCore.Register("PreDrawWorld", "RTXHideWorld", function()
        render.OverrideDepthEnable(true, false)
        return true
    end)
    
    RenderCore.Register("PostDrawWorld", "RTXHideWorld", function()
        render.OverrideDepthEnable(false)
    end)
    
    RenderCore.Register("PreDrawOpaqueRenderables", "RTXCustomWorldOpaque", function()
        RenderCustomWorld(false)
    end)
    
    RenderCore.Register("PreDrawTranslucentRenderables", "RTXCustomWorldTranslucent", function()
        RenderCustomWorld(true)
    end)
end

local function DisableCustomRendering()
    if not isEnabled then return end
    isEnabled = false

    RemixRenderCore.Unregister("PreDrawWorld", "RTXHideWorld")
    RemixRenderCore.Unregister("PostDrawWorld", "RTXHideWorld")
    RemixRenderCore.Unregister("PreDrawOpaqueRenderables", "RTXCustomWorldOpaque")
    RemixRenderCore.Unregister("PreDrawTranslucentRenderables", "RTXCustomWorldTranslucent")
end

-- Initialization and Cleanup
local function Initialize(token)
    local success, err = pcall(BuildMapMeshes, token)
    if not success then
        ErrorNoHalt("[RTX Fixes] Failed to build meshes: " .. tostring(err) .. "\n")
        DisableCustomRendering()
        return
    end
    
    timer.Simple(1, function()
        if CONVARS.ENABLED:GetBool() then
            local success, err = pcall(EnableCustomRendering)
            if not success then
                ErrorNoHalt("[RTX Fixes] Failed to enable custom rendering: " .. tostring(err) .. "\n")
                DisableCustomRendering()
            end
        end
    end)
end

-- Hooks
RenderCore.Register("InitPostEntity", "RTXMeshInit", Initialize)

RenderCore.Register("PostCleanupMap", "RTXMeshRebuild", function()
    RenderCore.RequestRebuild("PostCleanupMap")
end)

RenderCore.Register("PreDrawParticles", "ParticleSkipper", function()
    return true
end)

RenderCore.Register("ShutDown", "RTXCustomWorldShutdown", function()
    DisableCustomRendering()
    -- Rely on RenderCore global cleanup for tracked meshes; just clear tables locally
    mapMeshes = { opaque = {}, translucent = {} }
end)

-- ConVar Changes
cvars.AddChangeCallback("rtx_mwr", function(_, _, new)
    if tobool(new) then
        EnableCustomRendering()
    else
        DisableCustomRendering()
    end
end)

cvars.AddChangeCallback("rtx_mwr_capture_mode", function(_, _, new)
    -- Invert the value: if capture_mode is 1, r_drawworld should be 0 and vice versa
    RunConsoleCommand("r_drawworld", new == "1" and "0" or "1")
end)

-- Rebuild sinks and debounce on relevant ConVars
RenderCore.RegisterRebuildSink("RTXMeshRebuildSink", function(token, reason)
    Initialize(token)
end)

local function DebounceRebuildOnCvar(name)
    cvars.AddChangeCallback(name, function()
        RenderCore.RequestRebuild(name)
    end, "RTXMeshRebuild-" .. name)
end

DebounceRebuildOnCvar("rtx_mwr_chunk_size")
DebounceRebuildOnCvar("rtx_mwr_mat_whitelist")
DebounceRebuildOnCvar("rtx_mwr_mat_blacklist")
DebounceRebuildOnCvar("rtx_mwr_distance")

-- Menu
hook.Add("PopulateToolMenu", "RTXCustomWorldMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "User", "RTX_ForceRender", "#RTX Custom World", "", "", function(panel)
        panel:ClearControls()
        
        panel:CheckBox("Enable Custom World Rendering", "rtx_mwr")
        panel:ControlHelp("Renders the world using chunked meshes")

        panel:CheckBox("Remix Capture Mode", "rtx_mwr_capture_mode")
        panel:ControlHelp("Enable this if you're taking a capture with RTX Remix")
        
        panel:CheckBox("Show Debug Info", "rtx_mwr_debug")
    end)
end)

-- Console Commands
concommand.Add("rtx_rebuild_meshes", BuildMapMeshes)
