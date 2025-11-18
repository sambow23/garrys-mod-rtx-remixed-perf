if not CLIENT then return end

print("\n=== Remix Texture Workflow Guide ===\n")

print([[
TEXTURE FORMAT REQUIREMENTS:
Remix expects standard image formats, NOT GMod's VTF files.

Supported formats (likely):
- DDS (preferred for Remix)
- PNG
- JPG
- TGA

WORKFLOW OPTIONS:

1. MANUAL TEXTURE CONVERSION:
   - Use VTFEdit to export GMod .vtf files to .png/.tga
   - Place converted textures in a known directory
   - Reference them with absolute paths

2. USE REMIX TEXTURE REPLACEMENT:
   - Let Remix runtime handle texture replacement
   - Use Remix's texture replacement system
   - This is the recommended approach for production

3. SIMPLE TEST WITH SOLID COLORS:
   - Use albedoConstant instead of albedoTexture
   - No texture files needed
   - Good for testing geometry/lighting

Let's test option 3 (solid colors) first:
]])

concommand.Add("rtx_create_colored_mesh", function(ply, cmd, args)
    if not remixapi or not RemixMaterial then
        print("ERROR: Remix API not loaded!")
        return
    end
    
    local colorName = args[1] or "red"
    local colors = {
        red = { x = 1, y = 0, z = 0 },
        green = { x = 0, y = 1, z = 0 },
        blue = { x = 0, y = 0, z = 1 },
        yellow = { x = 1, y = 1, z = 0 },
        cyan = { x = 0, y = 1, z = 1 },
        magenta = { x = 1, y = 0, z = 1 },
        white = { x = 1, y = 1, z = 1 },
        orange = { x = 1, y = 0.5, z = 0 },
    }
    
    local color = colors[colorName] or colors.red
    
    print(string.format("\n[Color Test] Creating %s triangle...", colorName))
    
    -- 1. Create material with solid color (no textures!)
    local hash = tonumber(util.CRC("test_color_" .. colorName))
    
    local materialInfo = {
        hash = hash,
        -- No texture paths - using constants only!
        emissiveIntensity = 0,
        emissiveColorConstant = { x = 0, y = 0, z = 0 },
    }
    
    local opaqueInfo = {
        albedoConstant = color,  -- Solid color!
        opacityConstant = 1.0,
        roughnessConstant = 0.5,
        metallicConstant = 0.0,
    }
    
    local matId = RemixMaterial.CreateOpaqueMaterial("test_color_" .. colorName, materialInfo, opaqueInfo)
    
    if not matId or matId == 0 then
        print("✗ Material creation failed!")
        return
    end
    
    print(string.format("✓ Material ID: %d", matId))
    
    -- 2. Create double-sided quad (2 triangles, both sides)
    local size = 50
    local vertices = {
        -- Front face (CCW winding)
        { pos = Vector(-size, -size, 0), normal = Vector(0, 0, 1), u = 0, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(size, -size, 0), normal = Vector(0, 0, 1), u = 1, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(size, size, 0), normal = Vector(0, 0, 1), u = 1, v = 1, color = 0xFFFFFFFF },
        { pos = Vector(-size, size, 0), normal = Vector(0, 0, 1), u = 0, v = 1, color = 0xFFFFFFFF },
        -- Back face (CW winding = flipped normals)
        { pos = Vector(-size, -size, 0), normal = Vector(0, 0, -1), u = 0, v = 0, color = 0xFFFFFFFF },
        { pos = Vector(-size, size, 0), normal = Vector(0, 0, -1), u = 0, v = 1, color = 0xFFFFFFFF },
        { pos = Vector(size, size, 0), normal = Vector(0, 0, -1), u = 1, v = 1, color = 0xFFFFFFFF },
        { pos = Vector(size, -size, 0), normal = Vector(0, 0, -1), u = 1, v = 0, color = 0xFFFFFFFF },
    }
    
    local indices = {
        0, 1, 2,  -- Front triangle 1
        0, 2, 3,  -- Front triangle 2
        4, 5, 6,  -- Back triangle 1
        4, 6, 7,  -- Back triangle 2
    }
    
    local meshId = remixapi.UploadStaticPropMesh("color_quad_" .. colorName, vertices, indices, matId)
    
    if not meshId or meshId == 0 then
        print("✗ Mesh creation failed!")
        return
    end
    
    print(string.format("✓ Mesh ID: %d", meshId))
    
    -- 3. Set up continuous rendering
    local hookName = "ColoredMeshRender_" .. colorName
    
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
    
    print(string.format("✓ Rendering %s quad!", colorName))
    print(string.format("  Remove with: hook.Remove('PreDrawOpaqueRenderables', '%s')", hookName))
    
    -- Store for reference
    _G["REMIX_TEST_MESH_" .. colorName:upper()] = {
        materialId = matId,
        meshId = meshId,
        hookName = hookName,
    }
end)

print("\n[Texture Workflow] Commands available:")
print("  rtx_create_colored_mesh <color>")
print("    Colors: red, green, blue, yellow, cyan, magenta, white, orange")
print("\nExample: rtx_create_colored_mesh red")
print("\nThis creates a DOUBLE-SIDED quad so you can see it from both sides!")
