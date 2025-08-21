local renderDisplacements = CreateClientConVar("rtx_cdr_enable", "1", true, false, "Enable/disable custom displacement rendering")
local renderDistance = CreateClientConVar("rtx_cdr_distance", "10000", true, false, "Maximum distance to render displacements")
local debugMode = CreateClientConVar("rtx_cdr_debug", "0", true, false, "Enable debug mode")
local wireframeMode = CreateClientConVar("rtx_cdr_wireframe", "0", true, false, "Enable wireframe rendering")

local dispFaces = {}
local dispMeshes = {}
local loadProgress = 0
local totalDisplacements = 0
local hasLoaded = false
local shouldReload = false

-- Material to use for displacements
local defaultMaterial = Material("nature/blendsandsand008b")
local wireframeMaterial = Material("models/wireframe")

function LoadDisplacements()
    if not NikNaks or not NikNaks.CurrentMap then
        print("[Displacement Renderer] ERROR: NikNaks not available or map not loaded")
        return
    end

    dispFaces = {}
    dispMeshes = {}
    hasLoaded = false
    
    local dispFacesList = NikNaks.CurrentMap:GetDisplacmentFaces()
    totalDisplacements = #dispFacesList
    
    if totalDisplacements == 0 then
        print("[Displacement Renderer] No displacements found in map")
        hasLoaded = true
        return
    end
    
    print("[Displacement Renderer] Found " .. totalDisplacements .. " displacements")
    
    -- Process displacements in batches to avoid freezing
    local batchSize = 20
    local currentBatch = 0
    
    local function ProcessBatch()
        local startIndex = currentBatch * batchSize + 1
        local endIndex = math.min(startIndex + batchSize - 1, totalDisplacements)
        
        for i = startIndex, endIndex do
            local face = dispFacesList[i]
            if face then
                table.insert(dispFaces, face)
                loadProgress = i / totalDisplacements
            end
        end
        
        currentBatch = currentBatch + 1
        
        if startIndex <= totalDisplacements then
            timer.Simple(0.05, ProcessBatch)
        else
            -- All displacements processed, now create meshes
            CreateDispMeshes()
        end
    end
    
    timer.Simple(0.1, ProcessBatch)
end

function CreateDispMeshes()
    print("[Displacement Renderer] Creating meshes for " .. #dispFaces .. " displacements")
    
    for i, face in ipairs(dispFaces) do
        local vertexData = face:GenerateVertexTriangleData()
        
        if vertexData then
            local faceMesh = Mesh(face:GetMaterial())
            
            mesh.Begin(faceMesh, MATERIAL_TRIANGLES, #vertexData / 3)
            
            for _, vert in ipairs(vertexData) do
                mesh.Position(vert.pos)
                mesh.Normal(vert.normal)
                mesh.TexCoord(0, vert.u, vert.v)
                mesh.TexCoord(1, vert.u1, vert.v1)
                mesh.Color(255, 255, 255, 255)
                mesh.AdvanceVertex()
            end
            
            mesh.End()
            
            table.insert(dispMeshes, {
                mesh = faceMesh,
                material = face:GetMaterial(),
                mins = face:GetDisplacementInfo().startPosition,
                center = face:GetDisplacementInfo().startPosition,
                face = face
            })
        end
    end
    
    print("[Displacement Renderer] Created " .. #dispMeshes .. " displacement meshes")
    hasLoaded = true
end

-- Handle rendering
hook.Add("PostDrawOpaqueRenderables", "DisplacementRenderer", function(bDrawingDepth)
    if not renderDisplacements:GetBool() or not hasLoaded then return end
    
    local playerPos = LocalPlayer():GetPos()
    local renderDistSqr = renderDistance:GetFloat() ^ 2
    local renderedCount = 0
    
    render.SetColorModulation(1, 1, 1)
    
    for _, dispData in ipairs(dispMeshes) do
        local distSqr = dispData.center:DistToSqr(playerPos)
        
        if distSqr < renderDistSqr then
            if wireframeMode:GetBool() then
                render.SetMaterial(wireframeMaterial)
            else
                render.SetMaterial(dispData.material)
            end
            
            dispData.mesh:Draw()
            renderedCount = renderedCount + 1
        end
    end
    
    if debugMode:GetBool() then
        draw.SimpleText("Rendered Displacements: " .. renderedCount .. "/" .. #dispMeshes, "DermaDefault", 10, 30, Color(255, 255, 255))
        draw.SimpleText("Loading Progress: " .. math.floor(loadProgress * 100) .. "%", "DermaDefault", 10, 50, Color(255, 255, 255))
    end
end)

-- Check if map has changed
hook.Add("InitPostEntity", "DisplacementRendererMapLoad", function()
    timer.Simple(2, function()
        LoadDisplacements()
    end)
end)

concommand.Add("disp_reload", function()
    LoadDisplacements()
end)


-- Warning message when loading
hook.Add("HUDPaint", "DisplacementRendererLoading", function()
    if not hasLoaded and loadProgress > 0 then
        local w, h = ScrW(), ScrH()
        draw.SimpleText("Loading Custom Displacements: " .. math.floor(loadProgress * 100) .. "%", "DermaLarge", w/2, h/2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

print("[Displacement Renderer] Initialized")