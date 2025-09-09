if not CLIENT then return end
local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

local renderDisplacements = CreateClientConVar("rtx_cdr_enable", "1", true, false, "Enable/disable custom displacement rendering")
local renderDistance = CreateClientConVar("rtx_cdr_distance", "10000", true, false, "Maximum distance to render displacements")
local debugMode = CreateClientConVar("rtx_cdr_debug", "0", true, false, "Enable debug mode")
local wireframeMode = CreateClientConVar("rtx_cdr_wireframe", "0", true, false, "Enable wireframe rendering")
local cvarWhitelist = CreateClientConVar("rtx_cdr_mat_whitelist", "", true, false, "Comma-separated material name substrings to include")
local cvarBlacklist = CreateClientConVar("rtx_cdr_mat_blacklist", "", true, false, "Comma-separated material name substrings to exclude")

local dispFaces = {}
local dispMeshes = {}
local loadProgress = 0
local totalDisplacements = 0
local hasLoaded = false
local shouldReload = false
local dispStats = { rendered = 0, total = 0 }
-- PVS cache for displacements
local lastLeafDisp = nil
local pvsCacheDisp = nil

-- Debug helper function
local DebugPrint = (RenderCore and RenderCore.CreateDebugPrint)
    and RenderCore.CreateDebugPrint("Displacement Render Debug", debugMode)
    or function(...)
        if debugMode:GetBool() then
            print("[Displacement Render Debug]", ...)
        end
    end

local wireframeMaterial = Material("models/wireframe")

local function IsMaterialAllowedName(matName)
    if not matName then return false end
    if RenderCore and RenderCore.IsMaterialAllowed then
        return RenderCore.IsMaterialAllowed(matName, cvarWhitelist:GetString(), cvarBlacklist:GetString())
    end
    -- Fallback if core helper missing: allow
    return true
end

function LoadDisplacements(cancelToken)
    if not NikNaks or not NikNaks.CurrentMap then
        print("[Displacement Renderer] ERROR: NikNaks not available or map not loaded")
        return
    end

    dispFaces = {}
    dispMeshes = {}
    hasLoaded = false
    
    local okFaces, dispFacesList = pcall(function() return NikNaks.CurrentMap:GetDisplacmentFaces() end)
    if not okFaces or not dispFacesList then
        print("[Displacement Renderer] ERROR: GetDisplacmentFaces failed")
        hasLoaded = true
        return
    end
    totalDisplacements = #dispFacesList
    
    if totalDisplacements == 0 then
        print("[Displacement Renderer] No displacements found in map")
        hasLoaded = true
        return
    end
    
    print("[Displacement Renderer] Found " .. totalDisplacements .. " displacements")
    
    -- Coroutine-based loader to avoid freezing
    local co
    co = coroutine.create(function()
        local startTime = SysTime()
        local frameBudget = 0.003
        for i = 1, totalDisplacements do
            if cancelToken and cancelToken.cancelled then return end
            local face = dispFacesList[i]
            if face then
                table.insert(dispFaces, face)
                loadProgress = i / totalDisplacements
            end
            if SysTime() - startTime > frameBudget then
                coroutine.yield()
                startTime = SysTime()
            end
        end
        if cancelToken and cancelToken.cancelled then return end
        CreateDispMeshes(cancelToken)
    end)
    local function Step()
        if not co then return end
        if coroutine.status(co) == "dead" then return end
        local ok, err = coroutine.resume(co)
        if not ok then
            ErrorNoHalt("[Displacement Renderer] Load coroutine error: " .. tostring(err) .. "\n")
            return
        end
        if coroutine.status(co) ~= "dead" then
            timer.Simple(0, Step)
        end
    end
    timer.Simple(0.05, Step)
end

function CreateDispMeshes(cancelToken)
    print("[Displacement Renderer] Creating meshes for " .. #dispFaces .. " displacements")

    local co
    co = coroutine.create(function()
        local startTime = SysTime()
        local frameBudget = 0.003
        -- Batch by chunk and material; flush around ~30000 vertices per IMesh
        local chunkSize = (GetConVar and GetConVar("rtx_mwr_chunk_size") and GetConVar("rtx_mwr_chunk_size"):GetInt()) or 65536
        local MAX_VERTS = 30000
        local groups = {}

        local function getChunkKey(center)
            local cx = math.floor(center.x / chunkSize)
            local cy = math.floor(center.y / chunkSize)
            local cz = math.floor(center.z / chunkSize)
            return cx .. "," .. cy .. "," .. cz
        end

        local function newGroup(mat)
            return {
                material = mat,
                verts = {},
                count = 0,
                bmins = Vector(math.huge, math.huge, math.huge),
                bmaxs = Vector(-math.huge, -math.huge, -math.huge)
            }
        end

        local function flushGroup(g)
            if not g or g.count <= 0 then return end
            local m = Mesh(g.material)
            mesh.Begin(m, MATERIAL_TRIANGLES, g.count / 3)
            for i = 1, g.count do
                local v = g.verts[i]
                mesh.Position(v.pos)
                mesh.Normal(v.normal)
                mesh.TexCoord(0, v.u or 0, v.v or 0)
                mesh.TexCoord(1, v.u1 or 0, v.v1 or 0)
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
            end
            mesh.End()
            local center = (g.bmins + g.bmaxs) * 0.5
            table.insert(dispMeshes, {
                mesh = m,
                material = g.material,
                mins = g.bmins,
                maxs = g.bmaxs,
                center = center
            })
            if RenderCore and RenderCore.TrackMesh then
                RenderCore.TrackMesh(m)
            end
            -- reset batch
            g.verts = {}
            g.count = 0
            g.bmins = Vector(math.huge, math.huge, math.huge)
            g.bmaxs = Vector(-math.huge, -math.huge, -math.huge)
        end

        for i, face in ipairs(dispFaces) do
            if cancelToken and cancelToken.cancelled then return end
            local okVerts, vertexData = pcall(function() return face:GenerateVertexTriangleData() end)
            if not okVerts then vertexData = nil end
            if vertexData and #vertexData > 0 then
                local valid = true
                if RenderCore and RenderCore.ValidateVertex then
                    for _, v in ipairs(vertexData) do
                        if not RenderCore.ValidateVertex(v.pos) then
                            valid = false
                            break
                        end
                    end
                end
                if valid then
                    local mat = face:GetMaterial()
                    local matName = mat and mat:GetName()
                    if matName and IsMaterialAllowedName(matName) then
                        if RenderCore and RenderCore.GetMaterial then
                            mat = RenderCore.GetMaterial(matName)
                        end
                        -- compute face bounds and center
                        local fmins = Vector(math.huge, math.huge, math.huge)
                        local fmaxs = Vector(-math.huge, -math.huge, -math.huge)
                        for _, vv in ipairs(vertexData) do
                            if vv.pos.x < fmins.x then fmins.x = vv.pos.x end
                            if vv.pos.y < fmins.y then fmins.y = vv.pos.y end
                            if vv.pos.z < fmins.z then fmins.z = vv.pos.z end
                            if vv.pos.x > fmaxs.x then fmaxs.x = vv.pos.x end
                            if vv.pos.y > fmaxs.y then fmaxs.y = vv.pos.y end
                            if vv.pos.z > fmaxs.z then fmaxs.z = vv.pos.z end
                        end
                        local center = (fmins + fmaxs) * 0.5
                        local gkey = (matName or "") .. "|" .. getChunkKey(center)
                        local g = groups[gkey]
                        if not g then
                            g = newGroup(mat)
                            groups[gkey] = g
                        end
                        -- append face triangles to group
                        for _, v in ipairs(vertexData) do
                            g.count = g.count + 1
                            g.verts[g.count] = v
                            if v.pos.x < g.bmins.x then g.bmins.x = v.pos.x end
                            if v.pos.y < g.bmins.y then g.bmins.y = v.pos.y end
                            if v.pos.z < g.bmins.z then g.bmins.z = v.pos.z end
                            if v.pos.x > g.bmaxs.x then g.bmaxs.x = v.pos.x end
                            if v.pos.y > g.bmaxs.y then g.bmaxs.y = v.pos.y end
                            if v.pos.z > g.bmaxs.z then g.bmaxs.z = v.pos.z end
                            if g.count >= (MAX_VERTS - 3) then
                                flushGroup(g)
                            end
                        end
                    end
                end
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

        -- Flush remaining batches
        for _, g in pairs(groups) do
            flushGroup(g)
        end

        print("[Displacement Renderer] Created " .. #dispMeshes .. " displacement meshes")
        hasLoaded = true
        dispStats.total = #dispMeshes
    end)

    local jobId = "DispMeshBuildJob"
    RenderCore.ScheduleJob(jobId, function()
        if not co or coroutine.status(co) == "dead" then return false end
        local ok, err = coroutine.resume(co)
        if not ok then
            ErrorNoHalt("[Displacement Renderer] Build coroutine error: " .. tostring(err) .. "\n")
            return false
        end
        return coroutine.status(co) ~= "dead"
    end)
end

-- Handle rendering
RenderCore.Register("PreDrawOpaqueRenderables", "DisplacementRenderer", function(bDrawingDepth)
    if not renderDisplacements:GetBool() or not hasLoaded then return end
    
    local playerPos = LocalPlayer():GetPos()
    local maxDistance = renderDistance:GetFloat()
    local useDistanceLimit = (maxDistance > 0)
    local renderedCount = 0
    local distanceSkipped = 0
    
    -- Compute 3D sky bounds once per call
    local hasSkyAABB, skyMins, skyMaxs = false, nil, nil
    if NikNaks and NikNaks.CurrentMap and NikNaks.CurrentMap.HasSkyBox and NikNaks.CurrentMap:HasSkyBox() and NikNaks.CurrentMap.GetSkyboxSize then
        local okSky, mins, maxs = pcall(function() return NikNaks.CurrentMap:GetSkyboxSize() end)
        if okSky and mins and maxs then
            hasSkyAABB, skyMins, skyMaxs = true, mins, maxs
        end
    end

    -- Build PVS once per call with caching
    local pvs
    if NikNaks and NikNaks.CurrentMap then
        if NikNaks.CurrentMap.PointInLeafCache then
            local leaf, changed = NikNaks.CurrentMap:PointInLeafCache(0, playerPos, lastLeafDisp)
            if changed or not pvsCacheDisp then
                pvsCacheDisp = NikNaks.CurrentMap:PVSForOrigin(playerPos)
                lastLeafDisp = leaf
            end
            pvs = pvsCacheDisp
        elseif NikNaks.CurrentMap.PVSForOrigin then
            pvs = NikNaks.CurrentMap:PVSForOrigin(playerPos)
        end
    end

    for _, dispData in ipairs(dispMeshes) do
        if hasSkyAABB and dispData.center and dispData.center.WithinAABox and dispData.center:WithinAABox(skyMins, skyMaxs) then
            -- Skip miniature 3D sky displacements
            continue
        end
        -- PVS test (lazy-compute cluster set from AABB)
        if pvs then
            if not dispData._clusters and NikNaks and NikNaks.CurrentMap and NikNaks.CurrentMap.AABBInLeafs then
                local leaves = NikNaks.CurrentMap:AABBInLeafs(0, dispData.mins or dispData.center, dispData.maxs or dispData.center)
                local clusters = {}
                if leaves then
                    for i = 1, #leaves do
                        local leaf = leaves[i]
                        local cl = leaf and leaf:GetCluster() or -1
                        if cl and cl >= 0 then clusters[cl] = true end
                    end
                end
                dispData._clusters = clusters
            end
            if dispData._clusters then
                local anyVisible = false
                for cl, _ in pairs(dispData._clusters) do
                    if pvs[cl] then anyVisible = true break end
                end
                if not anyVisible then
                    continue
                end
            end
        end
        if useDistanceLimit and RenderCore and RenderCore.ShouldCullByDistance and RenderCore.ShouldCullByDistance(dispData.center, playerPos, maxDistance) then
            distanceSkipped = distanceSkipped + 1
            continue
        end
        local mat = wireframeMode:GetBool() and wireframeMaterial or dispData.material
        if dispData.mesh and mat then
            RenderCore.Submit({
                material = mat,
                mesh = dispData.mesh,
                translucent = false
            })
        end
        renderedCount = renderedCount + 1
    end
    
    dispStats.rendered = renderedCount
    dispStats.distance = distanceSkipped
    if debugMode:GetBool() then
        draw.SimpleText("Rendered Displacements: " .. renderedCount .. "/" .. #dispMeshes, "DermaDefault", 10, 30, Color(255, 255, 255))
        draw.SimpleText("Loading Progress: " .. math.floor(loadProgress * 100) .. "%", "DermaDefault", 10, 50, Color(255, 255, 255))
    end
end)

-- Check if map has changed
RenderCore.Register("InitPostEntity", "DisplacementRendererMapLoad", function()
    timer.Simple(2, function()
        LoadDisplacements()
    end)
end)

-- Cleanup on shutdown
RenderCore.Register("ShutDown", "DisplacementRenderer_Cleanup", function()
    if RenderCore and RenderCore.DestroyTrackedMeshes then
        RenderCore.DestroyTrackedMeshes()
    end
    dispFaces = {}
    dispMeshes = {}
    hasLoaded = false
    loadProgress = 0
    lastLeafDisp = nil
    pvsCacheDisp = nil
end)

concommand.Add("disp_reload", function()
    LoadDisplacements()
end)


-- Warning message when loading
RenderCore.Register("HUDPaint", "DisplacementRendererLoading", function()
    if not hasLoaded and loadProgress > 0 then
        local w, h = ScrW(), ScrH()
        draw.SimpleText("Loading Custom Displacements: " .. math.floor(loadProgress * 100) .. "%", "DermaLarge", w/2, h/2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

print("[Displacement Renderer] Initialized")

-- Stats provider
RenderCore.RegisterStats("Displacements", function()
    return string.format("Displacements: %d/%d (-D:%d)", dispStats.rendered or 0, dispStats.total or 0, dispStats.distance or 0)
end)

-- Rebuild sink and debounced cvar watchers
RenderCore.RegisterRebuildSink("DisplacementsRebuild", function(token, reason)
    hasLoaded = false
    loadProgress = 0
    dispFaces = {}
    dispMeshes = {}
    lastLeafDisp = nil
    pvsCacheDisp = nil
    if RenderCore and RenderCore.DestroyTrackedMeshes then
        RenderCore.DestroyTrackedMeshes()
    end
    timer.Simple(0.1, function()
        LoadDisplacements(token)
    end)
end)

local function DebounceRebuildOnCvar(name)
    cvars.AddChangeCallback(name, function()
        if RenderCore and RenderCore.RequestRebuild then
            RenderCore.RequestRebuild(name)
        end
    end, "DisplacementsRebuild-" .. name)
end

DebounceRebuildOnCvar("rtx_cdr_mat_whitelist")
DebounceRebuildOnCvar("rtx_cdr_mat_blacklist")
DebounceRebuildOnCvar("rtx_cdr_distance")