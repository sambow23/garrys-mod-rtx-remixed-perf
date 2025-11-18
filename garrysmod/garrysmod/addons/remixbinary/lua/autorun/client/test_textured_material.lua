if not CLIENT then return end

print("\n[Textured Material Test] Creating material with real textures...")

-- Helper to convert GMod material path to absolute file path
local function GetTexturePath(matPath)
    -- GMod materials are in: garrysmod/materials/
    -- Remove .vmt extension and add texture extension
    local basePath = matPath:gsub("%.vmt$", ""):gsub("materials/", "")
    
    -- Try common texture extensions
    local extensions = {".vtf", ".png", ".jpg", ".tga"}
    
    for _, ext in ipairs(extensions) do
        local fullPath = string.format("materials/%s%s", basePath, ext)
        -- Convert to absolute path
        -- Note: This is a simplified version - you may need to adjust based on your setup
        local absPath = string.format("C:/Users/cr/downloads/testt/garrysmod/%s", fullPath)
        
        if file.Exists(fullPath, "GAME") then
            print(string.format("[Texture] Found: %s", absPath))
            return absPath
        end
    end
    
    print(string.format("[Texture] NOT FOUND: %s", basePath))
    return nil
end

-- Create material with a simple GMod texture
local function CreateTexturedMaterial()
    if not RemixMaterial then
        print("[Textured Test] ERROR: RemixMaterial not available!")
        return nil
    end
    
    -- Try to use a common GMod texture (concrete)
    local texturePath = "materials/concrete/concretefloor001a.vtf"
    
    -- Convert to absolute path for Remix
    -- Remix needs Windows-style absolute paths
    local gameDir = string.gsub(string.GetPathFromFilename(debug.getinfo(1).source), "@", "")
    local gmodRoot = "C:/Users/cr/downloads/testt/garrysmod/"  -- Adjust this to your GMod path!
    
    -- Common test textures in GMod
    local testTextures = {
        gmodRoot .. "materials/concrete/concretefloor001a.vtf",
        gmodRoot .. "materials/brick/brickwall003a.vtf",
        gmodRoot .. "materials/metal/metalpipe001a.vtf",
        gmodRoot .. "materials/dev/dev_measuregeneric01b.vtf",
    }
    
    -- Use first available texture
    local albedoPath = testTextures[1]
    print(string.format("[Textured Test] Using albedo texture: %s", albedoPath))
    
    -- Create material with texture
    local hash = tonumber(util.CRC("test_textured_concrete"))
    
    local materialInfo = {
        hash = hash,
        albedoTexture = albedoPath,  -- Set actual texture path!
        emissiveIntensity = 0,
        emissiveColorConstant = { x = 0, y = 0, z = 0 },
    }
    
    local opaqueInfo = {
        albedoConstant = { x = 1, y = 1, z = 1 },  -- White tint (neutral)
        opacityConstant = 1.0,
        roughnessConstant = 0.8,  -- Rough concrete
        metallicConstant = 0.0,   -- Non-metallic
    }
    
    local matId = RemixMaterial.CreateOpaqueMaterial("test_textured_concrete", materialInfo, opaqueInfo)
    
    if matId and matId > 0 then
        print(string.format("[Textured Test] ✓ Created textured material ID: %d", matId))
        _G.TEST_TEXTURED_MATERIAL_ID = matId
        return matId
    else
        print("[Textured Test] ✗ Failed to create textured material")
        print("  This might be because:")
        print("  1. Texture path is incorrect")
        print("  2. Remix requires absolute paths")
        print("  3. Texture format not supported (needs DDS/PNG)")
        return nil
    end
end

-- Create the material
local matId = CreateTexturedMaterial()

if matId then
    print("\n[Textured Test] Success! Now create a mesh with this material:")
    print("  lua_run_cl local verts = {")
    print("    { pos = Vector(-50, -50, 0), normal = Vector(0, 0, 1), u = 0, v = 0, color = 0xFFFFFFFF },")
    print("    { pos = Vector(50, -50, 0), normal = Vector(0, 0, 1), u = 1, v = 0, color = 0xFFFFFFFF },")
    print("    { pos = Vector(0, 50, 0), normal = Vector(0, 0, 1), u = 0.5, v = 1, color = 0xFFFFFFFF },")
    print("  }")
    print(string.format("  local meshId = remixapi.UploadStaticPropMesh('textured_triangle', verts, {0,1,2}, %d)", matId))
    print("  Then use test_bsp_geometry.lua's render hook to draw it")
end
