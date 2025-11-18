if not CLIENT then return end

-- Test BSP Geometry Manager
-- Run this in console: lua_run_cl include("autorun/client/test_bsp_geometry.lua")

print("[BSP Geometry Test] Starting...")

-- Wait for RemixAPI to be available
if not remixapi then
    print("[BSP Geometry Test] ERROR: remixapi table not found! Module may not be loaded.")
    return
end

-- Check if our functions exist
local requiredFuncs = {
    "UploadStaticPropMesh",
    "DrawMeshInstance",
    "GetBSPGeometryStats",
    "ClearAllBSPMeshes"
}

for _, funcName in ipairs(requiredFuncs) do
    if not remixapi[funcName] then
        print(string.format("[BSP Geometry Test] ERROR: remixapi.%s not found!", funcName))
        return
    end
end

print("[BSP Geometry Test] All functions found!")

-- Test 1: Create a simple triangle
local function TestSimpleTriangle()
    print("\n[Test 1] Creating simple triangle...")
    
    -- Define a BIG triangle in 3D space (make it huge and emissive!)
    local vertices = {
        { pos = Vector(-50, -50, 0), normal = Vector(0, 0, 1), u = 0, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(50, -50, 0), normal = Vector(0, 0, 1), u = 1, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(0, 50, 0), normal = Vector(0, 0, 1), u = 0.5, v = 1, color = 0xFFFFFFFF },
    }
    
    -- Indices (simple sequential)
    local indices = { 0, 1, 2 }
    
    -- Use the test material ID if available, otherwise 0
    local materialId = _G.TEST_MATERIAL_ID or 0
    
    if materialId == 0 then
        print("[Test 1] WARNING: No test material! Run test_bsp_create_material.lua first")
        print("  Attempting with materialId = 0 anyway (will likely fail)")
    end
    
    -- Try to upload
    local meshId = remixapi.UploadStaticPropMesh("test_triangle", vertices, indices, materialId)
    
    if meshId and meshId > 0 then
        print(string.format("[Test 1] ✓ SUCCESS! Mesh uploaded with ID: %d", meshId))
        return meshId
    else
        print("[Test 1] ✗ FAILED! Mesh upload returned 0 or nil")
        print("  This likely means material ID 0 is invalid - we need to create a material first")
        return nil
    end
end

-- Test 2: Get statistics
local function TestGetStats()
    print("\n[Test 2] Getting statistics...")
    
    local stats = remixapi.GetBSPGeometryStats()
    
    if stats then
        print("[Test 2] ✓ Statistics retrieved:")
        print(string.format("  Total meshes: %d", stats.totalMeshes or 0))
        print(string.format("  Total vertices: %d", stats.totalVertices or 0))
        print(string.format("  Total indices: %d", stats.totalIndices or 0))
        print(string.format("  Static prop meshes: %d", stats.staticPropMeshes or 0))
        print(string.format("  Displacement meshes: %d", stats.displacementMeshes or 0))
        print(string.format("  Instances drawn this frame: %d", stats.instancesDrawnThisFrame or 0))
    else
        print("[Test 2] ✗ FAILED! No statistics returned")
    end
end

-- Test 3: Clear all meshes
local function TestClearMeshes()
    print("\n[Test 3] Clearing all meshes...")
    
    remixapi.ClearAllBSPMeshes()
    
    local stats = remixapi.GetBSPGeometryStats()
    if stats and stats.totalMeshes == 0 then
        print("[Test 3] ✓ SUCCESS! All meshes cleared")
    else
        print("[Test 3] ✗ FAILED! Meshes not cleared properly")
    end
end

-- Run tests
print("\n" .. string.rep("=", 60))
print("BSP Geometry Manager - Function Tests")
print(string.rep("=", 60))

-- Test basic functionality
TestGetStats()  -- Should show 0 meshes
local meshId = TestSimpleTriangle()  -- Try to create a mesh
TestGetStats()  -- Should show 1 mesh if successful
TestClearMeshes()  -- Clear everything
TestGetStats()  -- Should show 0 meshes again

-- Recreate mesh for rendering test
print("\n[Render Setup] Recreating triangle for rendering...")
meshId = TestSimpleTriangle()
if meshId then
    print("[Render Setup] ✓ Triangle recreated with ID:", meshId)
end

print("\n" .. string.rep("=", 60))
print("[BSP Geometry Test] Tests complete!")
print(string.rep("=", 60))

-- Create a simple material test (if upload failed due to material)
if not meshId then
    print("\n[NEXT STEP] Need to create a material first!")
    print("Try this in console:")
    print('  lua_run_cl local matId = remixapi.CreateMaterial(...)')
    print("  Then modify test_bsp_geometry.lua to use that material ID")
end

-- Optional: Set up a render hook to test DrawMeshInstance
if meshId then
    print("\n[Render Test] Setting up render hook to draw the triangle...")
    
    local frameCount = 0
    local lastMeshId = meshId  -- Store locally to verify it persists
    
    hook.Add("PreDrawOpaqueRenderables", "TestBSPGeometryRender", function()
        -- Debug: Is hook even being called?
        frameCount = frameCount + 1
        
        if not lastMeshId then 
            if frameCount <= 3 then
                print(string.format("[Render Hook Frame %d] ERROR: No meshId!", frameCount))
            end
            return 
        end
        
        -- Create a transform matrix (position in front of player)
        local ply = LocalPlayer()
        if not IsValid(ply) then 
            if frameCount <= 3 then
                print(string.format("[Render Hook Frame %d] ERROR: No valid player!", frameCount))
            end
            return 
        end
        
        local eyePos = ply:EyePos()
        local eyeAngles = ply:EyeAngles()
        local forward = eyeAngles:Forward()
        
        -- Position 100 units in front of player (closer!)
        local targetPos = eyePos + forward * 100
        
        local matrix = Matrix()
        matrix:Translate(targetPos)
        matrix:Rotate(eyeAngles)
        
        -- Try to draw instance
        local success = remixapi.DrawMeshInstance(lastMeshId, matrix, 0)
        
        -- Debug logging (first 10 frames only)
        if frameCount <= 10 then
            print(string.format("[Render Hook Frame %d] DrawMeshInstance(meshId=%s, pos=%s) = %s", 
                frameCount, tostring(lastMeshId), tostring(targetPos), tostring(success)))
        end
        
        -- Uncomment for debug spam:
        -- if success then
        --     print("[Render Test] Drew instance successfully")
        -- else
        --     print("[Render Test] Failed to draw instance")
        -- end
    end)
    
    print("  Hook registered! You should see a triangle floating in front of you.")
    print("  To remove: hook.Remove('PreDrawOpaqueRenderables', 'TestBSPGeometryRender')")
end
