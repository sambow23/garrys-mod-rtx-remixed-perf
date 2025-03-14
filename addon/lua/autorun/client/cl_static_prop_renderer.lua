-- -- addon/lua/autorun/client/custom_prop_renderer.lua

-- local RENDER_TYPE_MODEL = 1
-- local RENDER_TYPE_MESH = 2

-- -- Configuration
-- local config = {
--     enabled = CreateClientConVar("custom_staticprop_enabled", "1", true, false),
--     debug = CreateClientConVar("custom_staticprop_debug", "0", true, false),
--     force_mesh = CreateClientConVar("custom_staticprop_force_mesh", "0", true, false),
--     reload_meshes = CreateClientConVar("custom_staticprop_reload_meshes", "0", true, false),
--     render_distance = CreateClientConVar("custom_staticprop_render_distance", "20000", true, false)
-- }

-- -- Storage
-- local staticProps = {}
-- local meshCache = {}
-- local isInitialized = false
-- local renderCount = 0

-- -- Utility functions
-- local function GetModelMeshes(modelPath)
--     if meshCache[modelPath] then return meshCache[modelPath] end
    
--     local meshData = util.GetModelMeshes(modelPath)
--     if not meshData then return nil end
    
--     -- Process mesh data
--     local processedMeshes = {}
--     for _, mesh in ipairs(meshData) do
--         if mesh.triangles and #mesh.triangles > 0 and mesh.vertices and #mesh.vertices > 0 then
--             table.insert(processedMeshes, {
--                 material = Material(mesh.material),
--                 vertices = mesh.vertices,
--                 triangles = mesh.triangles
--             })
--         end
--     end
    
--     meshCache[modelPath] = processedMeshes
--     return processedMeshes
-- end

-- -- Material modification helper
-- local function PrepareMaterial(material)
--     if not material then return nil end
    
--     -- Create a unique version of the material to avoid interfering with other renderers
--     local uniqueName = "CustomPropRenderer_" .. material:GetName()
--     local uniqueMat = Material(uniqueName, material:GetShader())
    
--     -- Copy parameters
--     local params = material:GetKeyValues()
--     for k, v in pairs(params) do
--         uniqueMat:SetFloat(k, v)
--     end
    
--     -- Ensure prop will render
--     uniqueMat:SetInt("$nocull", 1)
    
--     return uniqueMat
-- end

-- -- Initialize system
-- local function Initialize()
--     if not NikNaks or not NikNaks.CurrentMap then
--         print("[Custom Prop Renderer] Error: NikNaks library or map data not found!")
--         timer.Simple(1, Initialize) -- Retry after a delay
--         return
--     end
    
--     local map = NikNaks.CurrentMap
--     local props = map:GetStaticProps()
--     print("[Custom Prop Renderer] Processing " .. table.Count(props) .. " static props")
    
--     staticProps = {}
    
--     -- Process each static prop
--     for i, prop in pairs(props) do
--         local modelPath = prop:GetModel()
        
--         -- Determine render method
--         local renderType = RENDER_TYPE_MODEL
--         if config.force_mesh:GetBool() then
--             renderType = RENDER_TYPE_MESH
--         end
        
--         -- Add to our list
--         table.insert(staticProps, {
--             model = modelPath,
--             pos = prop:GetPos(),
--             ang = prop:GetAngles(),
--             skin = prop:GetSkin(),
--             color = prop:GetColor(),
--             scale = prop:GetScale(),
--             renderType = renderType,
--             originalEntity = prop
--         })
        
--         -- Pre-cache mesh data if using mesh rendering
--         if renderType == RENDER_TYPE_MESH then
--             GetModelMeshes(modelPath)
--         end
--     end
    
--     -- Disable engine rendering of static props
--     RunConsoleCommand("cl_drawstaticprops", "0")
    
--     isInitialized = true
--     print("[Custom Prop Renderer] Initialization complete!")
-- end

-- -- Draw a model-based static prop
-- local function RenderModelProp(propData)
--     render.SuppressEngineLighting(true)
    
--     local matrix = Matrix()
--     matrix:SetTranslation(propData.pos)
--     matrix:SetAngles(propData.ang)
    
--     if propData.scale and propData.scale ~= 1 then
--         matrix:Scale(Vector(propData.scale, propData.scale, propData.scale))
--     end
    
--     render.SetColorModulation(
--         propData.color.r / 255, 
--         propData.color.g / 255, 
--         propData.color.b / 255
--     )
--     render.SetBlend(propData.color.a / 255)
    
--     cam.PushModelMatrix(matrix)
--     render.Model({
--         model = propData.model,
--         skin = propData.skin or 0
--     })
--     cam.PopModelMatrix()
    
--     render.SetColorModulation(1, 1, 1)
--     render.SetBlend(1)
--     render.SuppressEngineLighting(false)
    
--     renderCount = renderCount + 1
-- end

-- -- Draw a mesh-based static prop
-- local function RenderMeshProp(propData)
--     local meshes = GetModelMeshes(propData.model)
--     if not meshes then return end
    
--     render.SuppressEngineLighting(true)
    
--     local matrix = Matrix()
--     matrix:SetTranslation(propData.pos)
--     matrix:SetAngles(propData.ang)
    
--     if propData.scale and propData.scale ~= 1 then
--         matrix:Scale(Vector(propData.scale, propData.scale, propData.scale))
--     end
    
--     cam.PushModelMatrix(matrix)
    
--     for _, meshData in ipairs(meshes) do
--         render.SetMaterial(meshData.material)
        
--         -- Set color
--         render.SetColorModulation(
--             propData.color.r / 255, 
--             propData.color.g / 255, 
--             propData.color.b / 255
--         )
--         render.SetBlend(propData.color.a / 255)
        
--         mesh.Begin(MATERIAL_TRIANGLES, #meshData.triangles / 3)
        
--         for i = 1, #meshData.triangles, 3 do
--             local v1 = meshData.vertices[meshData.triangles[i]]
--             local v2 = meshData.vertices[meshData.triangles[i+1]]
--             local v3 = meshData.vertices[meshData.triangles[i+2]]
            
--             mesh.Position(v1.pos)
--             mesh.Normal(v1.normal)
--             mesh.TexCoord(0, v1.u, v1.v)
--             mesh.AdvanceVertex()
            
--             mesh.Position(v2.pos)
--             mesh.Normal(v2.normal)
--             mesh.TexCoord(0, v2.u, v2.v)
--             mesh.AdvanceVertex()
            
--             mesh.Position(v3.pos)
--             mesh.Normal(v3.normal)
--             mesh.TexCoord(0, v3.u, v3.v)
--             mesh.AdvanceVertex()
--         end
        
--         mesh.End()
--     end
    
--     cam.PopModelMatrix()
    
--     render.SetColorModulation(1, 1, 1)
--     render.SetBlend(1)
--     render.SuppressEngineLighting(false)
    
--     renderCount = renderCount + 1
-- end

-- -- Main rendering hook
-- hook.Add("PostDrawOpaqueRenderables", "CustomStaticPropRenderer", function()
--     if not isInitialized or not config.enabled:GetBool() then return end
    
--     -- Reset counter
--     renderCount = 0
    
--     -- Get player position for distance check
--     local playerPos = LocalPlayer():GetPos()
--     local maxDistance = config.render_distance:GetFloat()
--     local maxDistanceSqr = maxDistance * maxDistance
    
--     -- Render all props
--     for _, propData in ipairs(staticProps) do
--         -- Skip props that are too far
--         if propData.pos:DistToSqr(playerPos) > maxDistanceSqr then
--             continue
--         end
        
--         if propData.renderType == RENDER_TYPE_MODEL then
--             RenderModelProp(propData)
--         else
--             RenderMeshProp(propData)
--         end
--     end
    
--     -- Debug display
--     if config.debug:GetBool() then
--         debugoverlay.Text(5, 5, "Custom Prop Renderer: " .. renderCount .. " props rendered", 0.5)
--     end
-- end)

-- -- Reload meshes if requested
-- cvars.AddChangeCallback("custom_staticprop_reload_meshes", function(_, _, new)
--     if tonumber(new) == 1 then
--         print("[Custom Prop Renderer] Reloading mesh cache...")
--         meshCache = {}
--         RunConsoleCommand("custom_staticprop_reload_meshes", "0")
--     end
-- end)

-- -- Initialize when the addon is loaded
-- hook.Add("InitPostEntity", "CustomStaticPropRenderer_Init", function()
--     timer.Simple(1, Initialize)
-- end)

-- -- Add console commands
-- concommand.Add("custom_staticprop_init", function()
--     Initialize()
-- end)