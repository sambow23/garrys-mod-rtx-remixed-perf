if not CLIENT then return end
local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

local renderDisplacements = CreateClientConVar("rtx_cdr_enable", "1", true, false, "Enable/disable custom displacement rendering")
local renderDistance = CreateClientConVar("rtx_cdr_distance", "10000", true, false, "Maximum distance to render displacements")
local debugMode = CreateClientConVar("rtx_cdr_debug", "0", true, false, "Enable debug mode")
local wireframeMode = CreateClientConVar("rtx_cdr_wireframe", "0", true, false, "Enable wireframe rendering")
local cvarWhitelist = CreateClientConVar("rtx_cdr_mat_whitelist", "", true, false, "Comma-separated material name substrings to include")
local cvarBlacklist = CreateClientConVar("rtx_cdr_mat_blacklist", "", true, false, "Comma-separated material name substrings to exclude")
local cvarBinSize = CreateClientConVar("rtx_cdr_bin_size", "8192", true, false, "Displacement bin size for culling")

local dispFaces = {}
local dispMeshes = {}
local loadProgress = 0
local totalDisplacements = 0
local hasLoaded = false
local shouldReload = false
local dispStats = { rendered = 0, total = 0 }
local dispBins = {}

-- Material to use for displacements
local defaultMaterial = Material("nature/blendsandsand008b")
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
    
    dispBins = {}
    local binSize = cvarBinSize:GetFloat()

    for i, face in ipairs(dispFaces) do
        if cancelToken and cancelToken.cancelled then break end
        local okVerts, vertexData = pcall(function() return face:GenerateVertexTriangleData() end)
        if not okVerts then vertexData = nil end
        
        if vertexData then
            local mat = face:GetMaterial()
            local matName = mat and mat:GetName()
            if matName and not IsMaterialAllowedName(matName) then
                continue
            end
            if RenderCore and RenderCore.GetMaterial and matName then
                mat = RenderCore.GetMaterial(matName)
            end
            local faceMesh = Mesh(mat)
            
            mesh.Begin(faceMesh, MATERIAL_TRIANGLES, #vertexData / 3)
            local mins = Vector(math.huge, math.huge, math.huge)
            local maxs = Vector(-math.huge, -math.huge, -math.huge)
            
            for _, vert in ipairs(vertexData) do
                mesh.Position(vert.pos)
                mesh.Normal(vert.normal)
                mesh.TexCoord(0, vert.u, vert.v)
                mesh.TexCoord(1, vert.u1, vert.v1)
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
                if vert.pos.x < mins.x then mins.x = vert.pos.x end
                if vert.pos.y < mins.y then mins.y = vert.pos.y end
                if vert.pos.z < mins.z then mins.z = vert.pos.z end
                if vert.pos.x > maxs.x then maxs.x = vert.pos.x end
                if vert.pos.y > maxs.y then maxs.y = vert.pos.y end
                if vert.pos.z > maxs.z then maxs.z = vert.pos.z end
            end
            
            mesh.End()
            
            local center = (mins + maxs) * 0.5
            table.insert(dispMeshes, {
                mesh = faceMesh,
                material = mat,
                mins = mins,
                maxs = maxs,
                center = center,
                face = face
            })
            local key = (RenderCore and RenderCore.GetBinKey) and RenderCore.GetBinKey(center, binSize)
                or (math.floor(center.x / binSize) .. "," .. math.floor(center.y / binSize) .. "," .. math.floor(center.z / binSize))
            local bin = dispBins[key]
            if not bin then
                bin = (RenderCore and RenderCore.CreateBin) and RenderCore.CreateBin() or { mins = Vector(math.huge, math.huge, math.huge), maxs = Vector(-math.huge, -math.huge, -math.huge), items = {} }
                dispBins[key] = bin
            end
            table.insert(bin.items, dispMeshes[#dispMeshes])
            if RenderCore and RenderCore.UpdateBinBounds then
                RenderCore.UpdateBinBounds(bin, mins, maxs)
            else
                if mins.x < bin.mins.x then bin.mins.x = mins.x end
                if mins.y < bin.mins.y then bin.mins.y = mins.y end
                if mins.z < bin.mins.z then bin.mins.z = mins.z end
                if maxs.x > bin.maxs.x then bin.maxs.x = maxs.x end
                if maxs.y > bin.maxs.y then bin.maxs.y = maxs.y end
                if maxs.z > bin.maxs.z then bin.maxs.z = maxs.z end
            end

            if RenderCore and RenderCore.TrackMesh then
                RenderCore.TrackMesh(faceMesh)
            end
        end
    end
    
    print("[Displacement Renderer] Created " .. #dispMeshes .. " displacement meshes")
    hasLoaded = true
    dispStats.total = #dispMeshes
end

-- Handle rendering
RenderCore.Register("PostDrawOpaqueRenderables", "DisplacementRenderer", function(bDrawingDepth)
    if not renderDisplacements:GetBool() or not hasLoaded then return end
    
    local playerPos = LocalPlayer():GetPos()
    local maxDistance = renderDistance:GetFloat()
    local useDistanceLimit = (maxDistance > 0)
    local renderDistSqr = maxDistance * maxDistance
    local renderedCount = 0
    
    render.SetColorModulation(1, 1, 1)
    
    local hasCullBox = (render and type(render.CullBox) == "function")
    if hasCullBox then
        for key, bin in pairs(dispBins) do
            if render.CullBox(bin.mins, bin.maxs) then continue end
            for _, dispData in ipairs(bin.items) do
                if useDistanceLimit then
                    local distSqr = dispData.center:DistToSqr(playerPos)
                    if distSqr > renderDistSqr then
                        continue
                    end
                end
                if wireframeMode:GetBool() then
                    render.SetMaterial(wireframeMaterial)
                else
                    render.SetMaterial(dispData.material)
                end
                dispData.mesh:Draw()
                renderedCount = renderedCount + 1
            end
        end
    else
        for _, dispData in ipairs(dispMeshes) do
            if useDistanceLimit then
                local distSqr = dispData.center:DistToSqr(playerPos)
                if distSqr > renderDistSqr then
                    continue
                end
            end
            if wireframeMode:GetBool() then
                render.SetMaterial(wireframeMaterial)
            else
                render.SetMaterial(dispData.material)
            end
            dispData.mesh:Draw()
            renderedCount = renderedCount + 1
        end
    end
    
    dispStats.rendered = renderedCount
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
    return string.format("Displacements: %d/%d", dispStats.rendered or 0, dispStats.total or 0)
end)