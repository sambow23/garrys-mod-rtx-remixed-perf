if not CLIENT then return end

-- Ultra-simple material test - minimal fields
print("\n[Simple Material Test] Testing minimal material creation...")

if not RemixMaterial then
    print("[Simple Material Test] ERROR: RemixMaterial not found!")
    return
end

print("[Simple Material Test] RemixMaterial table exists")
print("[Simple Material Test] Available functions:")
for k, v in pairs(RemixMaterial) do
    print("  -", k, type(v))
end

-- Test 1: Try CreateOpaqueMaterial with absolute minimum
print("\n[Test 1] Trying CreateOpaqueMaterial with minimal fields...")

local materialInfo = {
    hash = tonumber(util.CRC("test_minimal"))  -- REQUIRED! Must be non-zero, convert string to number
}
local opaqueInfo = {}

local matId = RemixMaterial.CreateOpaqueMaterial("test_minimal", materialInfo, opaqueInfo)

if matId and matId > 0 then
    print(string.format("[Test 1] ✓ SUCCESS! Material ID: %d", matId))
    _G.TEST_MATERIAL_ID = matId
else
    print("[Test 1] ✗ FAILED")
end

-- Test 2: Try with more complete structure
print("\n[Test 2] Trying with filled-in defaults...")

local materialInfo2 = {
    hash = tonumber(util.CRC("test_complete")),  -- REQUIRED! Convert to number
    albedoTexture = "",
    normalTexture = "",
    tangentTexture = "",
    emissiveTexture = "",
    emissiveIntensity = 0,
    emissiveColorConstant = { x = 0, y = 0, z = 0 },
    spriteSheetRows = 1,
    spriteSheetCols = 1,
    spriteSheetFPS = 0,
    filterMode = 0,
    wrapModeU = 0,
    wrapModeV = 0
}

local opaqueInfo2 = {
    roughnessTexture = "",
    metallicTexture = "",
    anisotropy = 0.0,
    albedoConstant = { x = 1.0, y = 1.0, z = 1.0 },
    opacityConstant = 1.0,
    roughnessConstant = 0.5,
    metallicConstant = 0.0,
    heightTexture = "",
    displaceIn = 0.0,
    displaceOut = 0.0,
    alphaTestType = 0,
    alphaReferenceValue = 0
}

local matId2 = RemixMaterial.CreateOpaqueMaterial("test_complete", materialInfo2, opaqueInfo2)

if matId2 and matId2 > 0 then
    print(string.format("[Test 2] ✓ SUCCESS! Material ID: %d", matId2))
    _G.TEST_MATERIAL_ID = matId2
else
    print("[Test 2] ✗ FAILED")
end

-- Test 3: Check if there are any existing materials we can reference
print("\n[Test 3] Checking if we can use an existing GMod material...")

local gmodMat = Material("debug/debugempty")
if gmodMat then
    print("[Test 3] Found GMod material: debug/debugempty")
    print("  Material name:", gmodMat:GetName())
    
    -- Try to create a Remix material that might match this
    local materialInfo3 = table.Copy(materialInfo2)
    materialInfo3.hash = tonumber(util.CRC("debug_debugempty"))  -- Unique hash, convert to number
    local matId3 = RemixMaterial.CreateOpaqueMaterial("debug_debugempty", materialInfo3, opaqueInfo2)
    
    if matId3 and matId3 > 0 then
        print(string.format("[Test 3] ✓ SUCCESS! Material ID: %d", matId3))
        _G.TEST_MATERIAL_ID = matId3
    else
        print("[Test 3] ✗ FAILED")
    end
end

if not _G.TEST_MATERIAL_ID then
    print("\n[Simple Material Test] All tests failed!")
    print("Material creation error code 3 = INVALID_ARGUMENTS")
    print("\nPossible issues:")
    print("1. Empty texture paths might be invalid (try NULL instead?)")
    print("2. Some required field is missing")
    print("3. Field types don't match expectations")
    print("4. Need to check material_lua_bindings.cpp conversion logic")
else
    print(string.format("\n[Simple Material Test] ✓ Material created! ID: %d", _G.TEST_MATERIAL_ID))
    print("Now you can run the geometry test!")
end
