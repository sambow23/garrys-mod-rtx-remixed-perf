if not CLIENT then return end

print("\n[Table Debug] Testing material table structure...")

local materialInfo = {
    hash = util.CRC("test"),
    albedoTexture = "",
    test = 123
}

print("\n[Table Debug] materialInfo contents:")
PrintTable(materialInfo)

print("\n[Table Debug] Checking fields:")
print("  hash:", materialInfo.hash, type(materialInfo.hash))
print("  albedoTexture:", materialInfo.albedoTexture, type(materialInfo.albedoTexture))
print("  test:", materialInfo.test, type(materialInfo.test))

print("\n[Table Debug] util.CRC test:")
print("  util.CRC('test'):", util.CRC("test"), type(util.CRC("test")))

print("\n[Table Debug] Now trying RemixMaterial.CreateOpaqueMaterial with this table...")
if RemixMaterial and RemixMaterial.CreateOpaqueMaterial then
    local opaqueInfo = {}
    local result = RemixMaterial.CreateOpaqueMaterial("debug_test", materialInfo, opaqueInfo)
    print("[Table Debug] Result:", result)
else
    print("[Table Debug] RemixMaterial not available")
end
