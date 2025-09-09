-- if not CLIENT then return end

-- -- Sky Depth Mask: writes skybrush geometry into depth only, so any geometry behind sky won't render.
-- -- Author: CR

-- require("niknaks")
-- local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

-- local cv_enable = CreateClientConVar("rtx_sky_clip_enable", "1", true, false, "Enable depth-only sky clipping (mask outside 2D sky)")
-- local cv_debug  = CreateClientConVar("rtx_sky_clip_debug", "0", true, false, "Debug prints for sky depth mask")
-- local cv_depthNear = CreateClientConVar("rtx_sky_clip_depthnear", "1", true, false, "DepthRange near bound for sky mask (0..1, 1=off)")

-- local DebugPrint = (RenderCore and RenderCore.CreateDebugPrint)
--     and RenderCore.CreateDebugPrint("SkyDepthMask", cv_debug)
--     or function(...) if cv_debug:GetBool() then print("[SkyDepthMask]", ...) end end

-- -- Safe cull constants (fallbacks for branches that don't export MATERIAL_CULLMODE_*)
-- local CULL_CCW  = _G.MATERIAL_CULLMODE_CCW  or 0
-- local CULL_CW   = _G.MATERIAL_CULLMODE_CW   or 1
-- local CULL_NONE = _G.MATERIAL_CULLMODE_NONE or 2

-- -- Storage for depth meshes
-- local skyDepthMeshes = {}
-- local triCountBuilt = 0
-- local hasBuilt = false

-- local function IsSkyboxFace(face)
--     if not face then return false end
--     local material = face:GetMaterial()
--     if not material then return false end
--     local matName = string.lower(material:GetName() or "")
--     return matName:find("tools/toolsskybox", 1, true)
--         or matName:find("skybox/", 1, true)
--         or matName:find("sky_", 1, true) or false
-- end

-- local function ValidateVertex(pos)
--     if RenderCore and RenderCore.ValidateVertex then
--         return RenderCore.ValidateVertex(pos)
--     end
--     if not pos or not pos.x or not pos.y or not pos.z then return false end
--     if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then return false end
--     if math.abs(pos.x) > 16384 or math.abs(pos.y) > 16384 or math.abs(pos.z) > 16384 then return false end
--     return true
-- end

-- local function DestroySkyDepthMeshes()
--     for i = 1, #skyDepthMeshes do
--         local m = skyDepthMeshes[i]
--         if m and m.Destroy then pcall(function() m:Destroy() end) end
--     end
--     table.Empty(skyDepthMeshes)
-- end

-- local function BuildSkyDepthMeshes(cancelToken)
--     DestroySkyDepthMeshes()
--     hasBuilt = false
--     triCountBuilt = 0

--     if not NikNaks or not NikNaks.CurrentMap then
--         DebugPrint("NikNaks or CurrentMap not available; delaying build")
--         timer.Simple(1, function() BuildSkyDepthMeshes(cancelToken) end)
--         return
--     end

--     local okLeafs, allLeafs = pcall(function() return NikNaks.CurrentMap:GetLeafs() end)
--     if not okLeafs or not allLeafs then
--         ErrorNoHalt("[SkyDepthMask] GetLeafs failed\n")
--         hasBuilt = true
--         return
--     end

--     local triCount = 0
--     for _, leaf in pairs(allLeafs) do
--         if not leaf or leaf:IsOutsideMap() then continue end
--         local okFaces, faces = pcall(function() return leaf:GetFaces(true) end)
--         if not okFaces or not faces then continue end
--         for _, face in pairs(faces) do
--             if not face or not IsSkyboxFace(face) then continue end
--             local verts = face.GenerateVertexTriangleData and face:GenerateVertexTriangleData() or nil
--             if not verts or #verts == 0 then continue end

--             -- Validate verts and build a mesh
--             local valid = true
--             for i = 1, #verts do
--                 local v = verts[i]
--                 if not v or not ValidateVertex(v.pos) then valid = false break end
--             end
--             if not valid then continue end

--             local m = Mesh()
--             mesh.Begin(m, MATERIAL_TRIANGLES, #verts / 3)
--             for i = 1, #verts do
--                 local v = verts[i]
--                 mesh.Position(v.pos)
--                 mesh.Normal(v.normal or Vector(0,0,1))
--                 mesh.TexCoord(0, v.u or 0, v.v or 0) -- not used; color writes disabled
--                 mesh.AdvanceVertex()
--             end
--             mesh.End()

--             table.insert(skyDepthMeshes, m)
--             if RenderCore and RenderCore.TrackMesh then
--                 RenderCore.TrackMesh(m)
--             end
--             triCount = triCount + (#verts / 3)

--             if cancelToken and cancelToken.cancelled then break end
--         end
--         if cancelToken and cancelToken.cancelled then break end
--     end

--     hasBuilt = true
--     DebugPrint("Built sky depth mask meshes:", #skyDepthMeshes, "meshes, ~", triCount, "tris")
--     triCountBuilt = triCount
-- end

-- -- Early pass: draw depth-only sky mask before world/props/displacements submit to the queue
-- RenderCore.Register("PreDrawOpaqueRenderables", "RTX_SkyDepthMask", { fn = function(bDrawingDepth, bDrawingSkybox)
--     -- Do not run during the engine's depth prepass or while drawing the skybox
--     if bDrawingDepth then return end
--     if bDrawingSkybox then return end
--     -- Only run when engine world is hidden OR our custom world renderer is active
--     local cv_mwr = GetConVar("rtx_mwr")
--     local cv_world = GetConVar("r_drawworld")
--     local cv_opaque = GetConVar("r_drawopaqueworld")
--     local cv_capture = GetConVar("rtx_capture_mode")
--     local worldHidden = false
--     if cv_mwr and cv_mwr:GetBool() then worldHidden = true end
--     if cv_world and cv_world:GetInt() == 0 then worldHidden = true end
--     if cv_opaque and cv_opaque:GetInt() == 0 then worldHidden = true end
--     if cv_capture and cv_capture:GetInt() == 1 then worldHidden = true end
--     if not worldHidden then return end

--     if not cv_enable:GetBool() then return end
--     if not hasBuilt then return end
--     if #skyDepthMeshes == 0 then return end

--     -- Disable color writes, enable depth test + depth write
--     render.OverrideColorWriteEnable(true, false, false, false, false)
--     -- Enable depth testing and WRITES (second arg = disable writes -> false)
--     render.OverrideDepthEnable(true, false)

--     -- Optionally push depth range towards far plane
--     local dn = math.Clamp(cv_depthNear:GetFloat() or 1, 0, 1)
--     local pushedRange = dn < 0.999999
--     if pushedRange then
--         render.DepthRange(dn, 1)
--     end

--     -- Bind a simple material to ensure deterministic depth state
--     local mat = (RenderCore and RenderCore.GetMaterial) and RenderCore.GetMaterial("debug/debugwhite") or Material("debug/debugwhite")
--     render.SetMaterial(mat)
    
--     -- Draw meshes (protected). Disable culling so backfaces still write depth.
--     local ok, err = pcall(function()
--         render.CullMode(CULL_NONE)
--         for i = 1, #skyDepthMeshes do
--             local m = skyDepthMeshes[i]
--             if m then m:Draw() end
--         end
--         render.CullMode(CULL_CCW)
--     end)

--     -- Restore state
--     render.OverrideDepthEnable(false, false)
--     render.OverrideColorWriteEnable(false)
--     if pushedRange then
--         render.DepthRange(0, 1)
--     end
--     if not ok then ErrorNoHalt("[SkyDepthMask] Draw error: " .. tostring(err) .. "\n") end
-- end, prio = 10 })

-- -- Safety resets: ensure no lingering overrides after opaque/translucent passes
-- RenderCore.Register("PostDrawOpaqueRenderables", "RTX_SkyDepthMask_ResetOpaque", { fn = function()
--     render.OverrideDepthEnable(false, false)
--     render.OverrideColorWriteEnable(false)
-- end, prio = 2000 })

-- RenderCore.Register("PostDrawTranslucentRenderables", "RTX_SkyDepthMask_ResetTrans", { fn = function()
--     render.OverrideDepthEnable(false, false)
--     render.OverrideColorWriteEnable(false)
-- end, prio = 2000 })

-- -- Frame-end failsafe: clear overrides in 2D HUD pass as a last resort
-- RenderCore.Register("HUDPaint", "RTX_SkyDepthMask_FailsafeReset", function()
--     render.OverrideDepthEnable(false, false)
--     render.OverrideColorWriteEnable(false)
-- end)

-- -- Block engine 3D skybox when enabled; the engine draws it with a cleared depth buffer
-- RenderCore.Register("PreDrawSkyBox", "RTX_SkyDepthMask_Block3DSky", function()
--     if not cv_enable:GetBool() then return end
--     return true
-- end)

-- -- Disable 3D sky while sky-clip is enabled (engine draws 3D sky in a separate pass)
-- cvars.AddChangeCallback("rtx_sky_clip_enable", function(_, _, new)
--     RunConsoleCommand("r_3dsky", (new == "1") and "0" or "1")
-- end, "SkyDepthMask_3DSkyToggle")

-- -- Build after map init
-- RenderCore.Register("InitPostEntity", "RTX_SkyDepthMaskBuild", function()
--     local tok = RenderCore and RenderCore.NewToken and RenderCore.NewToken("SkyDepthMask") or { cancelled = false }
--     timer.Simple(2, function()
--         -- Enforce r_3dsky based on current enable state
--         if cv_enable:GetBool() then
--             RunConsoleCommand("r_3dsky", "0")
--         end
--         if tok.cancelled then return end
--         BuildSkyDepthMeshes(tok)
--     end)
-- end)

-- -- Rebuild on cleanup and explicit rebuild requests
-- RenderCore.Register("PostCleanupMap", "RTX_SkyDepthMaskRebuild", function()
--     if RenderCore and RenderCore.RequestRebuild then
--         RenderCore.RequestRebuild("SkyDepthMask-PostCleanupMap")
--     else
--         BuildSkyDepthMeshes()
--     end
-- end)

-- RenderCore.RegisterRebuildSink("SkyDepthMask-Rebuild", function(token)
--     BuildSkyDepthMeshes(token)
-- end)

-- -- Cleanup
-- RenderCore.Register("ShutDown", "RTX_SkyDepthMask_Cleanup", function()
--     DestroySkyDepthMeshes()
--     hasBuilt = false
-- end)

-- -- Stats line
-- RenderCore.RegisterStats("SkyMask", function()
--     return string.format("Sky mask meshes: %d (~%d tris)", #skyDepthMeshes, triCountBuilt)
-- end)

-- print("[Sky Depth Mask] Loaded.")
