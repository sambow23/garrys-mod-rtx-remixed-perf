if not CLIENT then return end

-- Helper to create a simple test material for BSP Geometry testing
-- Run this FIRST before test_bsp_geometry.lua

print("[BSP Material Test] Creating test material...")

-- Store the material ID globally for testing
_G.TEST_MATERIAL_ID = _G.TEST_MATERIAL_ID or nil

local function CreateTestMaterial()
    -- Create a simple white material for testing using RemixMaterial API
    
    if not RemixMaterial or not RemixMaterial.CreateMaterial then
        print("[BSP Material Test] ERROR: RemixMaterial.CreateMaterial not found!")
        print("  Make sure the material bindings are loaded")
        return nil
    end
    
    print("[BSP Material Test] Creating basic white material...")
    
    -- Generate unique hash for material (REQUIRED! Cannot be 0)
    local materialName = "bsp_test_white"
    local hash = tonumber(util.CRC(materialName))  -- util.CRC returns string, must convert!
    
    print(string.format("[BSP Material Test] Material hash: %d", hash))
    
    -- Base material info
    local materialInfo = {
        hash = hash,  -- CRITICAL: Must be non-zero!
        albedoTexture = "",
        normalTexture = "",
        tangentTexture = "",
        emissiveTexture = "",
        emissiveIntensity = 100,  -- Make it glow!
        emissiveColorConstant = { x = 1, y = 0, z = 1 },  -- Bright magenta!
        spriteSheetRows = 1,
        spriteSheetCols = 1,
        spriteSheetFPS = 0,
        filterMode = 0,
        wrapModeU = 0,
        wrapModeV = 0
    }
    
    -- Opaque material extension (required for solid materials)
    local opaqueInfo = {
        roughnessTexture = "",
        metallicTexture = "",
        anisotropy = 0,
        albedoConstant = { x = 1, y = 0, z = 1 },  -- Bright magenta albedo!
        opacityConstant = 1.0,
        roughnessConstant = 0.1,  -- Very smooth/shiny
        metallicConstant = 0.0,
        thinFilmThickness_hasvalue = false,
        alphaIsThinFilmThickness = false,
        heightTexture = "",
        displaceIn = 0,
        useDrawCallAlphaState = false,
        blendType_hasvalue = false,
        invertedBlend = false,
        alphaTestType = 0,
        alphaReferenceValue = 0,
        displaceOut = 0
    }
    
    local matId = RemixMaterial.CreateOpaqueMaterial(materialName, materialInfo, opaqueInfo)
    
    if matId and matId > 0 then
        print(string.format("[BSP Material Test] ✓ Material created with ID: %d", matId))
        return matId
    else
        print("[BSP Material Test] ✗ Material creation failed")
        return nil
    end
end

local matId = CreateTestMaterial()

if matId then
    _G.TEST_MATERIAL_ID = matId
    print("  Stored in _G.TEST_MATERIAL_ID for testing")
    print("\nNow run the geometry test:")
    print("  lua_run_cl include(\"autorun/client/test_bsp_geometry.lua\")")
else
    print("\n[TROUBLESHOOTING]")
    print("If material creation failed, check:")
    print("1. Is RemixMaterial table available? Run: lua_run_cl PrintTable(RemixMaterial)")
    print("2. Are there any console errors?")
    print("3. Try creating with explicit paths to textures")
end
