if not CLIENT then return end

-- Simple test: Draw triangle at world origin
concommand.Add("rtx_test_draw_triangle", function()
    if not remixapi then
        print("[Test] ERROR: remixapi not loaded!")
        return
    end
    
    print("\n[Test] Creating glowing triangle at world origin...")
    
    -- 1. Create emissive material (bright magenta glow)
    local hash = tonumber(util.CRC("test_glow_triangle"))
    local materialInfo = {
        hash = hash,
        emissiveIntensity = 200,  -- VERY bright!
        emissiveColorConstant = { x = 1, y = 0, z = 1 },  -- Magenta
    }
    local opaqueInfo = {
        albedoConstant = { x = 1, y = 1, z = 1 },  -- White albedo
        opacityConstant = 1.0,
        roughnessConstant = 0.5,
        metallicConstant = 0.0,
    }
    
    local matId = RemixMaterial.CreateOpaqueMaterial("test_glow_triangle", materialInfo, opaqueInfo)
    
    if not matId or matId == 0 then
        print("[Test] ✗ Failed to create material!")
        return
    end
    print(string.format("[Test] ✓ Created glowing material ID: %d", matId))
    
    -- 2. Create BIG triangle
    local vertices = {
        { pos = Vector(-100, -100, 0), normal = Vector(0, 0, 1), u = 0, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(100, -100, 0), normal = Vector(0, 0, 1), u = 1, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(0, 100, 0), normal = Vector(0, 0, 1), u = 0.5, v = 1, color = 0xFFFFFFFF },
    }
    local indices = { 0, 1, 2 }
    
    local meshId = remixapi.UploadStaticPropMesh("test_glow_triangle", vertices, indices, matId)
    
    if not meshId or meshId == 0 then
        print("[Test] ✗ Failed to create mesh!")
        return
    end
    print(string.format("[Test] ✓ Created mesh ID: %d", meshId))
    
    -- 3. Draw at player position + forward
    local ply = LocalPlayer()
    if not IsValid(ply) then
        print("[Test] ✗ No valid player!")
        return
    end
    
    local eyePos = ply:EyePos()
    local eyeAngles = ply:EyeAngles()
    local forward = eyeAngles:Forward()
    local targetPos = eyePos + forward * 150
    
    print(string.format("[Test] Drawing at position: %s", tostring(targetPos)))
    
    -- Create transform matrix
    local matrix = Matrix()
    matrix:Translate(targetPos)
    
    -- Draw it NOW
    local success = remixapi.DrawMeshInstance(meshId, matrix, 0)
    
    print(string.format("[Test] DrawMeshInstance result: %s", tostring(success)))
    
    if success then
        print("[Test] ✓ Triangle should be visible! Look for bright magenta glow.")
        print("[Test] Note: You need to call this command EVERY FRAME to keep it visible.")
        print("[Test] Try: bind p rtx_test_draw_triangle")
    else
        print("[Test] ✗ Draw failed!")
    end
end)

print("[Test Draw] Loaded! Use command: rtx_test_draw_triangle")
print("  Or bind it: bind p rtx_test_draw_triangle")
