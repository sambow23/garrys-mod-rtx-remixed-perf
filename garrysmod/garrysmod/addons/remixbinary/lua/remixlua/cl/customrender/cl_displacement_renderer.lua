if not CLIENT then return end
require("niknaks")
local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

-- ConVars
local CONVARS = {
    ENABLED = CreateClientConVar("rtx_dpr_enable", "1", true, false, "Enable custom displacement rendering"),
    DEBUG = CreateClientConVar("rtx_dpr_debug", "0", true, false, "Debug prints for displacement renderer"),
    CHUNK_SIZE = CreateClientConVar("rtx_dpr_chunk_size", "65536", true, false, "Size of chunks for displacement grouping"),
    MAT_WHITELIST = CreateClientConVar("rtx_dpr_mat_whitelist", "", true, false, "Comma-separated material name substrings to include"),
    MAT_BLACKLIST = CreateClientConVar("rtx_dpr_mat_blacklist", "toolsskybox,skybox/", true, false, "Comma-separated material name substrings to exclude"),
    DISTANCE = CreateClientConVar("rtx_dpr_distance", "0", true, false, "Displacement chunk distance limit (0 = off)"),
    USE_PVS = CreateClientConVar("rtx_dpr_use_pvs", "1", true, false, "Enable PVS culling for displacement chunks")
}

local function DebugPrint(...)
    if CONVARS.DEBUG:GetBool() then
        print("[DispRenderer]", ...)
    end
end

-- Local state
local dispMeshes = {}
-- dispMeshes[chunkKey] = {
--   _mins=Vector,_maxs=Vector,_clusters={ [cluster]=true },
--   [matKey] = { material=IMaterial, meshes=IMesh[] }
-- }

local buildState = { active = false, processed = 0, total = 0 }
-- Expose build state for progress tracking
if RemixRenderCore then RemixRenderCore._dispBuildState = buildState end
local stats = { draws = 0, chunksVisited = 0 }

-- PVS cache for displacement renderer
local lastLeaf = nil
local pvsCache = nil
local pvsLastValid = 0
local pvsUnavailable = false -- Track if PVS is broken for this map

local function IsPVSValid(pvs)
    if not pvs then return false end
    for _, v in pairs(pvs) do
        if v then return true end
    end
    return false
end

local function IsMaterialAllowed(matName)
    if not matName then return false end
    if RenderCore and RenderCore.IsMaterialAllowed then
        return RenderCore.IsMaterialAllowed(matName, CONVARS.MAT_WHITELIST:GetString(), CONVARS.MAT_BLACKLIST:GetString())
    end
    return true
end

local function GetChunkKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

-- Try to get or build a material that supports 2-texture blending.
-- Prefer the face's material if it already has $basetexture2; otherwise try a dynamic WorldVertexTransition.
local dispMatCache = {}
local function GetDispBlendMaterial(faceMat)
    if not faceMat then return nil end
    -- Normalize to a shared material instance by name so adjacent faces use the same IMaterial object
    local matName = faceMat.GetName and faceMat:GetName() or nil
    local shared = (RenderCore and RenderCore.GetMaterial and matName) and RenderCore.GetMaterial(matName) or faceMat

    local baseTex = shared.GetTexture and shared:GetTexture("$basetexture")
    if not baseTex then return shared end
    local baseName = baseTex.GetName and baseTex:GetName() or nil
    if not baseName or baseName == "" then return shared end

    local second = shared.GetTexture and shared:GetTexture("$basetexture2")
    if second then
        -- Ensure the material uses vertex alpha/color so our per-vertex alpha blends
        pcall(function()
            shared:SetInt("$vertexalpha", 1)
            shared:SetInt("$vertexcolor", 1)
        end)
        return shared
    end

    -- Try to find $basetexture2 via material proxies or alternatives; fallback: none
    local secondName = nil
    if second and second.GetName then secondName = second:GetName() end
    if not secondName or secondName == "" then
        return shared
    end

    -- Dynamic WorldVertexTransition (best-effort); cache per combo
    local key = string.format("rtx_dispblend[%s|%s]", baseName, secondName)
    local cached = dispMatCache[key]
    if cached ~= nil then return cached end
    local dyn
    -- CreateMaterial can take a unique name and shader; this may fail on some branches so guard with pcall
    local ok, err = pcall(function()
        dyn = CreateMaterial(key, "WorldVertexTransition", {
            ["$basetexture"] = baseName,
            ["$basetexture2"] = secondName,
            ["$vertexalpha"] = 1,
            ["$vertexcolor"] = 1,
            ["$translucent"] = 0
        })
    end)
    if not ok or not dyn then
        DebugPrint("Failed to create WorldVertexTransition material:", err)
        dispMatCache[key] = shared
        return shared
    end
    dispMatCache[key] = dyn
    return dyn
end

-- Build a batch of IMesh objects from a streamed triangle vertex list, preserving per-vertex alpha via mesh.Color
local MAX_VERTICES = 60000
local function CreateMeshBatchWithAlpha(vertices, material, maxVertsPerMesh)
    local meshes = {}
    local currentVerts = {}
    local currentAlphas = {}
    local vertCount = 0

    maxVertsPerMesh = maxVertsPerMesh or MAX_VERTICES

    local function flush()
        if #currentVerts == 0 then return end
        local newMesh = Mesh(material)
        mesh.Begin(newMesh, MATERIAL_TRIANGLES, #currentVerts / 3)
        for i = 1, #currentVerts do
            local v = currentVerts[i]
            local a = currentAlphas[i] or 1
            mesh.Position(v.pos)
            mesh.Normal(v.normal or Vector(0, 0, 1))
            mesh.TexCoord(0, v.u or 0, v.v or 0)
            if v.u1 and v.v1 then
                mesh.TexCoord(1, v.u1, v.v1)
            end
            -- Use base UVs on channel 2 so WorldVertexTransition $blendmodulatetexture is stable across seams
            mesh.TexCoord(2, v.u or 0, v.v or 0)
            local ia = math.Clamp(math.floor((a or 1) * 255 + 0.5), 0, 255)
            mesh.Color(255, 255, 255, ia)
            mesh.AdvanceVertex()
        end
        mesh.End()
        if RenderCore and RenderCore.TrackMesh then RenderCore.TrackMesh(newMesh) end
        table.insert(meshes, newMesh)
        currentVerts = {}
        currentAlphas = {}
        vertCount = 0
    end

    for i = 1, #vertices do
        local v = vertices[i]
        currentVerts[#currentVerts + 1] = v
        currentAlphas[#currentAlphas + 1] = v._alpha or 1
        vertCount = vertCount + 1
        if vertCount >= (maxVertsPerMesh - 3) then
            flush()
        end
    end
    flush()
    return meshes
end

-- Triangulate a displacement grid (width x height) into a flat triangle vertex list, copying per-vertex alpha
local function GridToTriangles(grid, alphas)
    local tri = {}
    if not grid or #grid == 0 then return tri end
    local width = math.sqrt(#grid)
    
    -- Validate that grid is a perfect square
    if width ~= math.floor(width) then
        ErrorNoHalt("[DispRenderer] Invalid grid size: " .. #grid .. " is not a perfect square\\n")
        return tri
    end
    
    if width <= 1 then return tri end
    local height = #grid / width
    local n = 0
    for i = 1, height - 1 do
        for j = 1, width - 1 do
            local idx1 = (i - 1) * width + j
            local idx2 = i * width + j
            local idx3 = i * width + j + 1
            local idx4 = (i - 1) * width + j + 1

            local v1, v2, v3 = grid[idx1], grid[idx2], grid[idx3]
            v1 = { pos = v1.pos, normal = v1.normal, u = v1.u, v = v1.v, u1 = v1.u1, v1 = v1.v1, _alpha = (alphas and alphas[idx1]) or 1 }
            v2 = { pos = v2.pos, normal = v2.normal, u = v2.u, v = v2.v, u1 = v2.u1, v1 = v2.v1, _alpha = (alphas and alphas[idx2]) or 1 }
            v3 = { pos = v3.pos, normal = v3.normal, u = v3.u, v = v3.v, u1 = v3.u1, v1 = v3.v1, _alpha = (alphas and alphas[idx3]) or 1 }
            tri[#tri + 1] = v1
            tri[#tri + 1] = v2
            tri[#tri + 1] = v3

            local v4 = grid[idx4]
            v1 = { pos = grid[idx1].pos, normal = grid[idx1].normal, u = grid[idx1].u, v = grid[idx1].v, u1 = grid[idx1].u1, v1 = grid[idx1].v1, _alpha = (alphas and alphas[idx1]) or 1 }
            v3 = { pos = v3.pos, normal = v3.normal, u = v3.u, v = v3.v, u1 = v3.u1, v1 = v3.v1, _alpha = (alphas and alphas[idx3]) or 1 }
            v4 = { pos = v4.pos, normal = v4.normal, u = v4.u, v = v4.v, u1 = v4.u1, v1 = v4.v1, _alpha = (alphas and alphas[idx4]) or 1 }
            tri[#tri + 1] = v1
            tri[#tri + 1] = v3
            tri[#tri + 1] = v4
        end
    end
    return tri
end

-- Build all displacement meshes in a coroutine with a frame budget
local function BuildDisplacementMeshes(cancelToken)
    -- Cleanup existing
    for chunkKey, materials in pairs(dispMeshes) do
        for matKey, group in pairs(materials) do
            if type(group) == "table" and group.meshes then
                for _, m in ipairs(group.meshes) do
                    if m and m.Destroy then pcall(function() m:Destroy() end) end
                end
            end
        end
    end
    dispMeshes = {}

    if not NikNaks or not NikNaks.CurrentMap then return end

    DebugPrint("Building displacement meshes...")

    local co
    co = coroutine.create(function()
        local startTime = SysTime()
        local frameBudget = 0.003

        -- Prepare chunk table
        local chunks = {}
        local chunkSize = CONVARS.CHUNK_SIZE:GetInt()
        if not chunkSize or chunkSize <= 0 then chunkSize = 65536 end
        -- For seam-free blending, collect vertex alphas across all displacements and average by position
        local faceRecords = {}
        local alphaSumByKey = {}
        local alphaCountByKey = {}
        -- Use epsilon-based position snapping for better seam matching
        local POSITION_EPSILON = 0.01 -- 0.01 units
        local function posKey(p)
            local x = math.floor((p.x / POSITION_EPSILON) + 0.5) * POSITION_EPSILON
            local y = math.floor((p.y / POSITION_EPSILON) + 0.5) * POSITION_EPSILON
            local z = math.floor((p.z / POSITION_EPSILON) + 0.5) * POSITION_EPSILON
            return string.format("%.2f,%.2f,%.2f", x, y, z)
        end

        -- Iterate leafs and include displacements (may insert duplicates across leaves)
        local okLeafs, allLeafs = pcall(function() return NikNaks.CurrentMap:GetLeafs() end)
        if not okLeafs or not allLeafs then
            ErrorNoHalt("[DispRenderer] GetLeafs failed\n")
            return
        end
        local seenFaces = {}
        buildState.active = true
        buildState.processed = 0
        buildState.total = 0
        for _ in pairs(allLeafs) do buildState.total = buildState.total + 1 end
        local faceCheckCounter = 0
        for _, leaf in pairs(allLeafs) do
            if cancelToken and cancelToken.cancelled then return end
            if leaf and not leaf:IsOutsideMap() then
                local okFaces, leafFaces = pcall(function() return leaf:GetFaces(true) end) -- include displacements
                if leafFaces then
                    local leafCluster = leaf.GetCluster and leaf:GetCluster() or -1
                    for _, face in pairs(leafFaces) do
                        -- Check cancellation every 100 faces to avoid long delays
                        faceCheckCounter = faceCheckCounter + 1
                        if faceCheckCounter >= 100 then
                            faceCheckCounter = 0
                            if cancelToken and cancelToken.cancelled then return end
                        end
                        repeat
                            if not face or not face.IsDisplacement or not face:IsDisplacement() then break end
                            local faceId = face.GetIndex and face:GetIndex() or tostring(face)
                            if seenFaces[faceId] then break end
                            seenFaces[faceId] = true
                            if not face.ShouldRender or not face:ShouldRender() then break end

                            local mat = face.GetMaterial and face:GetMaterial() or nil
                            if not mat then break end
                            local matName = mat.GetName and mat:GetName() or ""
                            if not IsMaterialAllowed(matName) then break end

                            -- Determine center from base quad (use vertex grid average)
                            local grid = face.GenerateVertexData and face:GenerateVertexData() or nil
                            if not grid or #grid == 0 then break end
                            local cx, cy, cz = 0, 0, 0
                            for i = 1, #grid do local p = grid[i].pos cx = cx + p.x cy = cy + p.y cz = cz + p.z end
                            cx = cx / #grid cy = cy / #grid cz = cz / #grid
                            local center = Vector(cx, cy, cz)

                            local chunkX = math.floor(center.x / chunkSize)
                            local chunkY = math.floor(center.y / chunkSize)
                            local chunkZ = math.floor(center.z / chunkSize)
                            local chunkKey = GetChunkKey(chunkX, chunkY, chunkZ)

                            chunks[chunkKey] = chunks[chunkKey] or {}
                            local chunkData = chunks[chunkKey]
                            if leafCluster and leafCluster >= 0 then
                                chunkData._clusters = chunkData._clusters or {}
                                chunkData._clusters[leafCluster] = true
                            end

                            -- Build per-vertex alpha from disp verts (pass 1: accumulate by position)
                            local dispInfo = face.GetDisplacementInfo and face:GetDisplacementInfo() or nil
                            local power = dispInfo and dispInfo.power or 2
                            local w = (2 ^ power) + 1
                            local vertStart = dispInfo and dispInfo.DispVertStart or 0
                            local vertEnd = vertStart + (w * w)
                            local dispVerts = NikNaks.CurrentMap:GetDispVerts()
                            local alphaKeys = {}
                            for v = vertStart, vertEnd - 1 do
                                local dv = dispVerts[v]
                                local idx = (v - vertStart) + 1
                                local a = math.Clamp((dv and dv.alpha) or 0, 0, 1)
                                local pk = posKey(grid[idx].pos)
                                alphaKeys[idx] = pk
                                alphaSumByKey[pk] = (alphaSumByKey[pk] or 0) + a
                                alphaCountByKey[pk] = (alphaCountByKey[pk] or 0) + 1
                            end

                            -- Choose material now and record for pass 2
                            local useMat = GetDispBlendMaterial(mat)
                            local useName = (useMat and useMat.GetName and useMat:GetName()) or matName or "__unnamed__"

                            faceRecords[#faceRecords + 1] = {
                                grid = grid,
                                alphaKeys = alphaKeys,
                                mat = useMat,
                                matName = useName,
                                chunkKey = chunkKey
                            }
                        until true

                        if SysTime() - startTime > frameBudget then
                            coroutine.yield()
                            local spent = SysTime() - startTime
                            if RenderCore and RenderCore.UpdateFrameBudget then
                                frameBudget = RenderCore.UpdateFrameBudget(spent, frameBudget)
                            else
                                if spent > frameBudget * 1.2 then
                                    frameBudget = math.max(0.001, frameBudget * 0.95)
                                elseif spent < frameBudget * 0.8 then
                                    frameBudget = math.min(0.006, frameBudget * 1.05)
                                end
                            end
                            startTime = SysTime()
                        end
                    end
                end
            end
            buildState.processed = buildState.processed + 1
            if SysTime() - startTime > frameBudget then
                coroutine.yield()
                local spent = SysTime() - startTime
                if RenderCore and RenderCore.UpdateFrameBudget then
                    frameBudget = RenderCore.UpdateFrameBudget(spent, frameBudget)
                else
                    if spent > frameBudget * 1.2 then
                        frameBudget = math.max(0.001, frameBudget * 0.95)
                    elseif spent < frameBudget * 0.8 then
                        frameBudget = math.min(0.006, frameBudget * 1.05)
                    end
                end
                startTime = SysTime()
            end
        end

        -- Average alpha per shared vertex position across all faces
        local alphaAvgByKey = {}
        for k, sum in pairs(alphaSumByKey) do
            local c = alphaCountByKey[k] or 1
            alphaAvgByKey[k] = sum / c
        end

        -- Pass 2: stream triangles using averaged alphas into chunk/material groups
        for i = 1, #faceRecords do
            local rec = faceRecords[i]
            local grid = rec.grid
            local alphas = {}
            for gi = 1, #grid do
                local k = rec.alphaKeys[gi]
                alphas[gi] = alphaAvgByKey[k] or 0
            end
            local triangles = GridToTriangles(grid, alphas)

            local chunkKey = rec.chunkKey
            local materials = chunks[chunkKey] or {}
            chunks[chunkKey] = materials

            local useName = rec.matName
            local useMat = rec.mat
            materials[useName] = materials[useName] or { material = useMat, _stream = {}, _mins = Vector(math.huge, math.huge, math.huge), _maxs = Vector(-math.huge, -math.huge, -math.huge) }
            local group = materials[useName]

            for t = 1, #triangles do
                local v = triangles[t]
                group._stream[#group._stream + 1] = v
                local p = v.pos
                if p.x < group._mins.x then group._mins.x = p.x end
                if p.y < group._mins.y then group._mins.y = p.y end
                if p.z < group._mins.z then group._mins.z = p.z end
                if p.x > group._maxs.x then group._maxs.x = p.x end
                if p.y > group._maxs.y then group._maxs.y = p.y end
                if p.z > group._maxs.z then group._maxs.z = p.z end
            end

            if cancelToken and cancelToken.cancelled then return end
            if SysTime() - startTime > frameBudget then
                coroutine.yield()
                local spent = SysTime() - startTime
                if RenderCore and RenderCore.UpdateFrameBudget then
                    frameBudget = RenderCore.UpdateFrameBudget(spent, frameBudget)
                else
                    if spent > frameBudget * 1.2 then
                        frameBudget = math.max(0.001, frameBudget * 0.9)
                    elseif spent < frameBudget * 0.8 then
                        frameBudget = math.min(0.006, frameBudget * 1.1)
                    end
                end
                startTime = SysTime()
            end
        end

        -- Build IMeshes per chunk/material
        for chunkKey, materials in pairs(chunks) do
            dispMeshes[chunkKey] = { _clusters = materials._clusters }
            for matKey, group in pairs(materials) do
                if matKey ~= "_clusters" then
                    local material = group.material
                    local triStream = group._stream
                    if triStream and #triStream > 0 and material then
                        local meshes = CreateMeshBatchWithAlpha(triStream, material, MAX_VERTICES)
                        dispMeshes[chunkKey][matKey] = {
                            meshes = meshes,
                            material = material
                        }
                        -- Merge bounds into chunk level
                        local c = dispMeshes[chunkKey]
                        if not c._mins then
                            c._mins = group._mins
                            c._maxs = group._maxs
                        else
                            local cmins = c._mins
                            local cmaxs = c._maxs
                            local gmins = group._mins
                            local gmaxs = group._maxs
                            if gmins.x < cmins.x then cmins.x = gmins.x end
                            if gmins.y < cmins.y then cmins.y = gmins.y end
                            if gmins.z < cmins.z then cmins.z = gmins.z end
                            if gmaxs.x > cmaxs.x then cmaxs.x = gmaxs.x end
                            if gmaxs.y > cmaxs.y then cmaxs.y = gmaxs.y end
                            if gmaxs.z > cmaxs.z then cmaxs.z = gmaxs.z end
                        end
                    end
                end
                if cancelToken and cancelToken.cancelled then return end
                if SysTime() - startTime > frameBudget then
                    coroutine.yield()
                    local spent = SysTime() - startTime
                    if RenderCore and RenderCore.UpdateFrameBudget then
                        frameBudget = RenderCore.UpdateFrameBudget(spent, frameBudget)
                    else
                        if spent > frameBudget * 1.2 then
                            frameBudget = math.max(0.001, frameBudget * 0.95)
                        elseif spent < frameBudget * 0.8 then
                            frameBudget = math.min(0.006, frameBudget * 1.05)
                        end
                    end
                    startTime = SysTime()
                end
            end
        end

        buildState.active = false
        DebugPrint("Built displacement meshes")
    end)

    -- Drive coroutine
    local jobId = "RTXDispMeshBuildJob"
    RenderCore.ScheduleJob(jobId, function()
        if not co or coroutine.status(co) == "dead" then
            buildState.active = false
            return false
        end
        
        local ok, err = coroutine.resume(co)
        if not ok then
            ErrorNoHalt("[DispRenderer] Build coroutine error: " .. tostring(err) .. "\n")
            buildState.active = false
            buildState.processed = 0
            buildState.total = 0
            -- Clean up partial meshes
            for chunkKey, materials in pairs(dispMeshes) do
                for matKey, group in pairs(materials) do
                    if type(group) == "table" and group.meshes then
                        for _, m in ipairs(group.meshes) do
                            if m then
                                if RenderCore and RenderCore.DestroyMesh then
                                    RenderCore.DestroyMesh(m)
                                else
                                    pcall(function() if m.Destroy then m:Destroy() end end)
                                end
                            end
                        end
                    end
                end
            end
            dispMeshes = {}
            return false
        end
        
        -- Check if cancelled
        if cancelToken and cancelToken.cancelled then
            buildState.active = false
            DebugPrint("Build cancelled")
            return false
        end
        
        local isDead = coroutine.status(co) == "dead"
        if isDead then
            buildState.active = false
        end
        return not isDead
    end)
end

-- Render
local function RenderDisplacements()
    if not CONVARS.ENABLED:GetBool() then return end
    local maxDist = CONVARS.DISTANCE:GetFloat()
    local useDist = maxDist > 0
    local ply = LocalPlayer and LocalPlayer() or nil
    local eyePos = ply and ((ply.EyePos and ply:EyePos()) or (ply.GetPos and ply:GetPos())) or nil

    -- Build PVS
    local pvs
    if CONVARS.USE_PVS:GetBool() and not pvsUnavailable and NikNaks and NikNaks.CurrentMap and eyePos then
        if NikNaks.CurrentMap.PointInLeafCache then
            local leaf, changed = NikNaks.CurrentMap:PointInLeafCache(0, eyePos, lastLeaf)
            if changed or not IsPVSValid(pvsCache) then
                local ok, newPVS = pcall(function() return NikNaks.CurrentMap:PVSForOrigin(eyePos) end)
                if ok and IsPVSValid(newPVS) then
                    pvsCache = newPVS
                    lastLeaf = leaf
                    pvsLastValid = SysTime()
                elseif not ok then
                    -- PVS is broken for this map, disable it permanently
                    pvsUnavailable = true
                    pvsCache = nil
                    print("[DispRenderer] PVS unavailable for this map (invalid cluster data), disabling PVS culling")
                end
            end
            -- Only use cache if it's valid
            if IsPVSValid(pvsCache) then
                pvs = pvsCache
            else
                pvs = nil
            end
        elseif NikNaks.CurrentMap.PVSForOrigin then
            local ok, tmp = pcall(function() return NikNaks.CurrentMap:PVSForOrigin(eyePos) end)
            if ok and IsPVSValid(tmp) then
                pvs = tmp
                pvsCache = tmp
                pvsLastValid = SysTime()
            elseif not ok then
                -- PVS is broken for this map, disable it permanently
                pvsUnavailable = true
                pvsCache = nil
                print("[DispRenderer] PVS unavailable for this map (invalid cluster data), disabling PVS culling")
            else
                pvs = nil
            end
        end
    end

    local draws = 0
    local chunksVisited = 0
    for _, chunkMaterials in pairs(dispMeshes) do
        chunksVisited = chunksVisited + 1
        local cmins, cmaxs = chunkMaterials._mins, chunkMaterials._maxs
        local skipChunk = false
        if cmins and cmaxs and useDist and eyePos then
            local center = (cmins + cmaxs) * 0.5
            if RenderCore and RenderCore.ShouldCullByDistance and RenderCore.ShouldCullByDistance(center, eyePos, maxDist) then
                skipChunk = true
            end
        end
        -- Compute clusters for chunk on demand
        local clusters = chunkMaterials._clusters
        if not skipChunk and pvs and cmins and cmaxs and (not clusters or next(clusters) == nil) and NikNaks and NikNaks.CurrentMap and NikNaks.CurrentMap.AABBInLeafs then
            local leaves = NikNaks.CurrentMap:AABBInLeafs(0, cmins, cmaxs)
            clusters = {}
            if leaves then
                for i = 1, #leaves do
                    local leaf = leaves[i]
                    local cl = leaf and leaf:GetCluster() or -1
                    if cl and cl >= 0 then clusters[cl] = true end
                end
            end
            chunkMaterials._clusters = clusters
        end
        -- PVS culling
        if not skipChunk and pvs and clusters and next(clusters) ~= nil then
            local anyVisible = false
            for cl, _ in pairs(clusters) do
                if pvs[cl] then anyVisible = true break end
            end
            if not anyVisible then skipChunk = true end
        end

        if not skipChunk then
            for key, group in pairs(chunkMaterials) do
                if key ~= "_mins" and key ~= "_maxs" and key ~= "_clusters" then
                    if group and group.meshes then
                        local meshes = group.meshes
                        for i = 1, #meshes do
                            local m = meshes[i]
                            if m then
                                RenderCore.Submit({
                                    material = group.material,
                                    mesh = m,
                                    translucent = false
                                })
                                draws = draws + 1
                            end
                        end
                    end
                end
            end
        end
    end

    stats.draws = draws
    stats.chunksVisited = chunksVisited
end

-- Enable/Disable
local isEnabled = false
local function EnableRendering()
    if isEnabled then return end
    isEnabled = true
    RenderCore.Register("PreDrawOpaqueRenderables", "RTXDisp_Draw", function()
        RenderDisplacements()
    end)
end

local function DisableRendering()
    if not isEnabled then return end
    isEnabled = false
    RenderCore.Unregister("PreDrawOpaqueRenderables", "RTXDisp_Draw")
end

-- Init / Rebuild
local function Initialize(token)
    local ok, err = pcall(BuildDisplacementMeshes, token)
    if not ok then
        ErrorNoHalt("[DispRenderer] Failed to build: " .. tostring(err) .. "\n")
        DisableRendering()
        return
    end
    timer.Simple(1, function()
        if CONVARS.ENABLED:GetBool() then
            local success, e = pcall(EnableRendering)
            if not success then
                ErrorNoHalt("[DispRenderer] Failed to enable: " .. tostring(e) .. "\n")
                DisableRendering()
            end
        end
    end)
end

RenderCore.Register("InitPostEntity", "RTXDisp_Init", Initialize)

RenderCore.Register("PostCleanupMap", "RTXDisp_Rebuild", function()
    pvsUnavailable = false -- Reset PVS flag for new map
    pvsCache = nil
    lastLeaf = nil
    RenderCore.RequestRebuild("PostCleanupMap")
end)

RenderCore.Register("ShutDown", "RTXDisp_Shutdown", function()
    DisableRendering()
    for _, mats in pairs(dispMeshes) do
        for _, group in pairs(mats) do
            if type(group) == "table" and group.meshes then
                for _, m in ipairs(group.meshes) do
                    if m and m.Destroy then pcall(function() m:Destroy() end) end
                end
            end
        end
    end
    dispMeshes = {}
    pvsUnavailable = false -- Reset PVS flag
    pvsCache = nil
    lastLeaf = nil
end)

-- Stats
RenderCore.RegisterStats("Displacements", function()
    local extra = ""
    if buildState.active and (buildState.total or 0) > 0 then
        extra = string.format(" | build: %d/%d", buildState.processed or 0, buildState.total or 0)
    end
    return string.format("Disp draws: %d | chunks: %d%s", stats.draws or 0, stats.chunksVisited or 0, extra)
end)

-- Rebuild sink and debounced cvars
RenderCore.RegisterRebuildSink("RTXDispRebuildSink", function(token, reason)
    Initialize(token)
end)

local function DebounceRebuildOnCvar(name)
    cvars.AddChangeCallback(name, function()
        RenderCore.RequestRebuild(name)
    end, "RTXDispRebuild-" .. name)
end

DebounceRebuildOnCvar("rtx_dpr_chunk_size")
DebounceRebuildOnCvar("rtx_dpr_mat_whitelist")
DebounceRebuildOnCvar("rtx_dpr_mat_blacklist")
DebounceRebuildOnCvar("rtx_dpr_distance")

-- Console helper
concommand.Add("rtx_rebuild_displacements", function()
    Initialize(RenderCore and RenderCore.NewToken and RenderCore.NewToken("RTXDispRebuildManual") or {})
end)

print("[Custom Displacement Renderer] Loaded.")


