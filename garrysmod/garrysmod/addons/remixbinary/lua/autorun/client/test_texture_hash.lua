if not CLIENT then return end

print("\n[Texture Hash Test] Loading...")

-- This test script demonstrates how to get Remix texture hashes from Source Engine materials

concommand.Add("rtx_test_texture_hash", function(ply, cmd, args)
    if not RemixMaterial or not RemixMaterial.GetTextureHash then
        print("[Texture Hash Test] ERROR: RemixMaterial.GetTextureHash not available!")
        print("  Make sure the binary module is loaded and compiled with the new function.")
        return
    end
    
    -- Test with a common GMod material
    local materialName = args[1] or "concrete/concretefloor001a"
    
    print(string.format("\n[Texture Hash Test] Testing material: %s", materialName))
    
    -- Try to get the hash
    local hash = RemixMaterial.GetTextureHash(materialName)
    
    if hash and hash > 0 then
        print(string.format("[Texture Hash Test] ✓ SUCCESS! Hash: 0x%X (decimal: %.0f)", hash, hash))
        print(string.format("[Texture Hash Test]   This hash can now be used in CreateMaterial:"))
        print(string.format("     local matInfo = { hash = %.0f, ... }", hash))
        
        -- Store it globally for convenient reuse
        _G.LAST_TEXTURE_HASH = hash
        _G.LAST_TEXTURE_MATERIAL = materialName
        print(string.format("[Texture Hash Test]   Stored in _G.LAST_TEXTURE_HASH for reuse"))
    else
        print("[Texture Hash Test] ✗ FAILED! Hash is 0 or nil")
        print("[Texture Hash Test]   Possible reasons:")
        print("    1. Material doesn't exist")
        print("    2. Material hasn't been loaded/drawn yet")
        print("    3. Texture hasn't been uploaded to GPU")
        print("    4. Material has no $basetexture")
        print("\n[Texture Hash Test]   Try these steps:")
        print("    1. Look at the material in-game first (render it)")
        print("    2. Use a different material name")
        print("    3. Check console for warnings")
    end
end)

-- Test with multiple common materials
concommand.Add("rtx_test_texture_hash_batch", function()
    if not RemixMaterial or not RemixMaterial.GetTextureHash then
        print("[Texture Hash Test] ERROR: RemixMaterial.GetTextureHash not available!")
        return
    end
    
    local testMaterials = {
        "concrete/concretefloor001a",
        "brick/brickwall003a",
        "metal/metalpipe001a",
        "dev/dev_measuregeneric01b",
        "models/debug/debugwhite",
        "vgui/white",
    }
    
    print("\n[Texture Hash Test] Batch testing common materials...")
    print(string.rep("=", 70))
    
    local results = {}
    
    for _, matName in ipairs(testMaterials) do
        local hash = RemixMaterial.GetTextureHash(matName)
        table.insert(results, {
            name = matName,
            hash = hash,
            success = (hash and hash > 0)
        })
    end
    
    -- Print results table
    print(string.format("%-40s | %-20s | %s", "Material", "Hash", "Status"))
    print(string.rep("-", 70))
    
    for _, result in ipairs(results) do
        local hashStr = result.success and string.format("0x%X", result.hash) or "FAILED"
        local status = result.success and "✓" or "✗"
        print(string.format("%-40s | %-20s | %s", result.name, hashStr, status))
    end
    
    print(string.rep("=", 70))
    
    -- Summary
    local successCount = 0
    for _, result in ipairs(results) do
        if result.success then successCount = successCount + 1 end
    end
    
    print(string.format("\n[Texture Hash Test] Results: %d/%d successful", successCount, #results))
end)

-- Helper: Create a test mesh with a material hash
concommand.Add("rtx_create_mesh_with_material_hash", function(ply, cmd, args)
    local materialName = args[1] or "concrete/concretefloor001a"
    
    if not RemixMaterial or not RemixMaterial.GetTextureHash then
        print("[Test] ERROR: RemixMaterial.GetTextureHash not available!")
        return
    end
    
    if not remixapi or not remixapi.UploadStaticPropMesh then
        print("[Test] ERROR: remixapi not available!")
        return
    end
    
    print(string.format("\n[Test] Creating mesh with texture from: %s", materialName))
    
    -- Step 1: Get the texture hash
    local textureHash = RemixMaterial.GetTextureHash(materialName)
    
    if not textureHash or textureHash == 0 then
        print("[Test] ✗ Failed to get texture hash!")
        return
    end
    
    print(string.format("[Test] ✓ Got texture hash: 0x%X", textureHash))
    
    -- Step 2: Create a material that references this hash
    local matInfo = {
        hash = textureHash,  -- Reuse the existing texture's hash!
        emissiveIntensity = 0,
        emissiveColorConstant = { x = 0, y = 0, z = 0 },
    }
    
    local opaqueInfo = {
        albedoConstant = { x = 1, y = 1, z = 1 },  -- White tint
        opacityConstant = 1.0,
        roughnessConstant = 0.8,
        metallicConstant = 0.0,
    }
    
    local matId = RemixMaterial.CreateOpaqueMaterial("reused_texture_" .. materialName, matInfo, opaqueInfo)
    
    if not matId or matId == 0 then
        print("[Test] ✗ Failed to create Remix material!")
        return
    end
    
    print(string.format("[Test] ✓ Created Remix material ID: %d", matId))
    
    -- Step 3: Create a simple quad mesh
    local size = 50
    local vertices = {
        { pos = Vector(-size, -size, 0), normal = Vector(0, 0, 1), u = 0, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(size, -size, 0), normal = Vector(0, 0, 1), u = 1, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(size, size, 0), normal = Vector(0, 0, 1), u = 1, v = 1, color = 0xFFFFFFFF },
        { pos = Vector(-size, size, 0), normal = Vector(0, 0, 1), u = 0, v = 1, color = 0xFFFFFFFF },
    }
    
    local indices = { 0, 1, 2, 0, 2, 3 }
    
    local meshId = remixapi.UploadStaticPropMesh("reused_texture_mesh", vertices, indices, matId)
    
    if not meshId or meshId == 0 then
        print("[Test] ✗ Failed to create mesh!")
        return
    end
    
    print(string.format("[Test] ✓ Created mesh ID: %d", meshId))
    
    -- Step 4: Set up rendering
    local hookName = "ReusedTextureMesh_" .. materialName:gsub("[^%w]", "_")
    
    hook.Add("PreDrawOpaqueRenderables", hookName, function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        
        local eyePos = ply:EyePos()
        local forward = ply:EyeAngles():Forward()
        local targetPos = eyePos + forward * 100
        
        local matrix = Matrix()
        matrix:Translate(targetPos)
        
        remixapi.DrawMeshInstance(meshId, matrix, 0)
    end)
    
    print(string.format("[Test] ✓ Rendering quad with Source Engine texture!"))
    print(string.format("[Test]   Remove with: hook.Remove('PreDrawOpaqueRenderables', '%s')", hookName))
    
    _G.REUSED_TEXTURE_TEST = {
        materialName = materialName,
        textureHash = textureHash,
        materialId = matId,
        meshId = meshId,
        hookName = hookName,
    }
end)

print("[Texture Hash Test] Commands loaded:")
print("  rtx_test_texture_hash <material_name>")
print("  rtx_test_texture_hash_batch")
print("  rtx_create_mesh_with_material_hash <material_name>")
print("\nExample: rtx_test_texture_hash concrete/concretefloor001a")

