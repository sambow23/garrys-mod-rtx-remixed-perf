#ifdef _WIN64
#include "remixapi.h"
#include <tier0/dbg.h>
#include <materialsystem/imaterialsystem.h>
#include <materialsystem/imaterial.h>
#include <materialsystem/imaterialvar.h>
#include <materialsystem/itexture.h>
#include <d3d9.h>
#include <Windows.h>
#include "../d3d9_texture_tracker.h"

using namespace GarrysMod::Lua;

// Forward declarations for global symbols (defined in module.cpp)
extern IMaterialSystem* materials;
extern remix::Interface* g_remix;

namespace RemixAPI {

// Helper function to extract MaterialInfo from Lua table
static remix::MaterialInfo LuaToMaterialInfo(ILuaBase* LUA, int index) {
    remix::MaterialInfo info;
    
    if (!LUA->IsType(index, Type::Table)) {
        LUA->ThrowError("Expected table for MaterialInfo");
        return info;
    }
    
    // Get hash (CRITICAL: This must be set to non-zero value!)
#ifdef _DEBUG
    Msg("[MaterialInfo] Looking for hash field at stack index %d\n", index);
    Msg("[MaterialInfo] Table check: %d\n", LUA->IsType(index, Type::Table));
#endif
    
    LUA->GetField(index, "hash");
    
#ifdef _DEBUG
    Msg("[MaterialInfo] After GetField, type at -1: %d (Number=%d)\n", LUA->GetType(-1), Type::Number);
#endif
    
    if (LUA->IsType(-1, Type::Number)) {
        double hashValue = LUA->GetNumber(-1);
        info.hash = static_cast<uint64_t>(hashValue);
#ifdef _DEBUG
        Msg("[MaterialInfo] Extracted hash from Lua: %.0f -> %llu\n", hashValue, info.hash);
#endif
    } else {
#ifdef _DEBUG
        Msg("[MaterialInfo] WARNING: No hash field found in material table!\n");
        Msg("[MaterialInfo] Type at stack -1: %d\n", LUA->GetType(-1));
#endif
    }
    LUA->Pop();
    
    // Get albedo texture (skip if empty string)
    LUA->GetField(index, "albedoTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        if (!texture.empty()) {
            info.set_albedoTexture(texture);
        }
    }
    LUA->Pop();
    
    // Get normal texture (skip if empty string)
    LUA->GetField(index, "normalTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        if (!texture.empty()) {
            info.set_normalTexture(texture);
        }
    }
    LUA->Pop();
    
    // Get tangent texture (skip if empty string)
    LUA->GetField(index, "tangentTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        if (!texture.empty()) {
            info.set_tangentTexture(texture);
        }
    }
    LUA->Pop();
    
    // Get emissive texture (skip if empty string)
    LUA->GetField(index, "emissiveTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        if (!texture.empty()) {
            info.set_emissiveTexture(texture);
        }
    }
    LUA->Pop();
    
    // Get emissive intensity
    LUA->GetField(index, "emissiveIntensity");
    if (LUA->IsType(-1, Type::Number)) {
        info.emissiveIntensity = static_cast<float>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get emissive color constant
    LUA->GetField(index, "emissiveColorConstant");
    if (LUA->IsType(-1, Type::Table)) {
        LUA->GetField(-1, "x");
        if (LUA->IsType(-1, Type::Number)) {
            info.emissiveColorConstant.x = static_cast<float>(LUA->GetNumber(-1));
        }
        LUA->Pop();
        
        LUA->GetField(-1, "y");
        if (LUA->IsType(-1, Type::Number)) {
            info.emissiveColorConstant.y = static_cast<float>(LUA->GetNumber(-1));
        }
        LUA->Pop();
        
        LUA->GetField(-1, "z");
        if (LUA->IsType(-1, Type::Number)) {
            info.emissiveColorConstant.z = static_cast<float>(LUA->GetNumber(-1));
        }
        LUA->Pop();
    }
    LUA->Pop();
    
    // Get sprite sheet properties
    LUA->GetField(index, "spriteSheetRow");
    if (LUA->IsType(-1, Type::Number)) {
        info.spriteSheetRow = static_cast<uint8_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    LUA->GetField(index, "spriteSheetCol");
    if (LUA->IsType(-1, Type::Number)) {
        info.spriteSheetCol = static_cast<uint8_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    LUA->GetField(index, "spriteSheetFps");
    if (LUA->IsType(-1, Type::Number)) {
        info.spriteSheetFps = static_cast<uint8_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get filtering and wrap modes
    LUA->GetField(index, "filterMode");
    if (LUA->IsType(-1, Type::Number)) {
        info.filterMode = static_cast<uint8_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    LUA->GetField(index, "wrapModeU");
    if (LUA->IsType(-1, Type::Number)) {
        info.wrapModeU = static_cast<uint8_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    LUA->GetField(index, "wrapModeV");
    if (LUA->IsType(-1, Type::Number)) {
        info.wrapModeV = static_cast<uint8_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    return info;
}

// Helper function to extract MaterialInfoOpaqueEXT from Lua table
static remix::MaterialInfoOpaqueEXT LuaToMaterialInfoOpaqueEXT(ILuaBase* LUA, int index) {
    remix::MaterialInfoOpaqueEXT info;
    
    if (!LUA->IsType(index, Type::Table)) {
        LUA->ThrowError("Expected table for MaterialInfoOpaqueEXT");
        return info;
    }
    
    // Get roughness texture (skip if empty string)
    LUA->GetField(index, "roughnessTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        if (!texture.empty()) {
            info.set_roughnessTexture(texture);
        }
    }
    LUA->Pop();
    
    // Get metallic texture (skip if empty string)
    LUA->GetField(index, "metallicTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        if (!texture.empty()) {
            info.set_metallicTexture(texture);
        }
    }
    LUA->Pop();
    
    // Get height texture (skip if empty string)
    LUA->GetField(index, "heightTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        if (!texture.empty()) {
            info.set_heightTexture(texture);
        }
    }
    LUA->Pop();
    
    // Get anisotropy
    LUA->GetField(index, "anisotropy");
    if (LUA->IsType(-1, Type::Number)) {
        info.anisotropy = static_cast<float>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get albedo constant
    LUA->GetField(index, "albedoConstant");
    if (LUA->IsType(-1, Type::Table)) {
        LUA->GetField(-1, "x");
        if (LUA->IsType(-1, Type::Number)) {
            info.albedoConstant.x = static_cast<float>(LUA->GetNumber(-1));
        }
        LUA->Pop();
        
        LUA->GetField(-1, "y");
        if (LUA->IsType(-1, Type::Number)) {
            info.albedoConstant.y = static_cast<float>(LUA->GetNumber(-1));
        }
        LUA->Pop();
        
        LUA->GetField(-1, "z");
        if (LUA->IsType(-1, Type::Number)) {
            info.albedoConstant.z = static_cast<float>(LUA->GetNumber(-1));
        }
        LUA->Pop();
    }
    LUA->Pop();
    
    // Get opacity constant
    LUA->GetField(index, "opacityConstant");
    if (LUA->IsType(-1, Type::Number)) {
        info.opacityConstant = static_cast<float>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get roughness constant
    LUA->GetField(index, "roughnessConstant");
    if (LUA->IsType(-1, Type::Number)) {
        info.roughnessConstant = static_cast<float>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get metallic constant
    LUA->GetField(index, "metallicConstant");
    if (LUA->IsType(-1, Type::Number)) {
        info.metallicConstant = static_cast<float>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get thin film thickness (optional)
    LUA->GetField(index, "thinFilmThickness");
    if (LUA->IsType(-1, Type::Number)) {
        info.set_thinFilmThickness(static_cast<float>(LUA->GetNumber(-1)));
    }
    LUA->Pop();
    
    // Get blend type (optional)
    LUA->GetField(index, "blendType");
    if (LUA->IsType(-1, Type::Number)) {
        info.set_blendType(static_cast<int>(LUA->GetNumber(-1)));
    }
    LUA->Pop();
    
    // Get boolean flags
    LUA->GetField(index, "alphaIsThinFilmThickness");
    if (LUA->IsType(-1, Type::Bool)) {
        info.alphaIsThinFilmThickness = LUA->GetBool(-1);
    }
    LUA->Pop();
    
    LUA->GetField(index, "useDrawCallAlphaState");
    if (LUA->IsType(-1, Type::Bool)) {
        info.useDrawCallAlphaState = LUA->GetBool(-1);
    }
    LUA->Pop();
    
    LUA->GetField(index, "invertedBlend");
    if (LUA->IsType(-1, Type::Bool)) {
        info.invertedBlend = LUA->GetBool(-1);
    }
    LUA->Pop();
    
    // Get alpha test properties
    LUA->GetField(index, "alphaTestType");
    if (LUA->IsType(-1, Type::Number)) {
        info.alphaTestType = static_cast<int>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    LUA->GetField(index, "alphaReferenceValue");
    if (LUA->IsType(-1, Type::Number)) {
        info.alphaReferenceValue = static_cast<uint8_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get displacement properties
    LUA->GetField(index, "displaceIn");
    if (LUA->IsType(-1, Type::Number)) {
        info.displaceIn = static_cast<float>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    LUA->GetField(index, "displaceOut");
    if (LUA->IsType(-1, Type::Number)) {
        info.displaceOut = static_cast<float>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    return info;
}

// Lua function: RemixMaterial.CreateMaterial(name, materialInfo)
LUA_FUNCTION(RemixMaterial_CreateMaterial) {
    if (!LUA->IsType(1, Type::String)) {
        LUA->ThrowError("Expected string for material name");
        return 0;
    }
    
    if (!LUA->IsType(2, Type::Table)) {
        LUA->ThrowError("Expected table for material info");
        return 0;
    }
    
    std::string name = LUA->GetString(1);
    remix::MaterialInfo info = LuaToMaterialInfo(LUA, 2);
    
    auto& materialManager = RemixAPI::Instance().GetMaterialManager();
    uint64_t materialId = materialManager.CreateMaterial(name, info);
    
    LUA->PushNumber(static_cast<double>(materialId));
    return 1;
}

// Lua function: RemixMaterial.CreateOpaqueMaterial(name, materialInfo, opaqueInfo)
LUA_FUNCTION(RemixMaterial_CreateOpaqueMaterial) {
    if (!LUA->IsType(1, Type::String)) {
        LUA->ThrowError("Expected string for material name");
        return 0;
    }
    
    if (!LUA->IsType(2, Type::Table)) {
        LUA->ThrowError("Expected table for material info");
        return 0;
    }
    
    if (!LUA->IsType(3, Type::Table)) {
        LUA->ThrowError("Expected table for opaque info");
        return 0;
    }
    
    std::string name = LUA->GetString(1);
    remix::MaterialInfo info = LuaToMaterialInfo(LUA, 2);
    remix::MaterialInfoOpaqueEXT opaqueInfo = LuaToMaterialInfoOpaqueEXT(LUA, 3);
    
    auto& materialManager = RemixAPI::Instance().GetMaterialManager();
    uint64_t materialId = materialManager.CreateOpaqueMaterial(name, info, opaqueInfo);
    
    LUA->PushNumber(static_cast<double>(materialId));
    return 1;
}

// Lua function: RemixMaterial.DestroyMaterial(materialId)
LUA_FUNCTION(RemixMaterial_DestroyMaterial) {
    if (!LUA->IsType(1, Type::Number)) {
        LUA->ThrowError("Expected number for material ID");
        return 0;
    }
    
    uint64_t materialId = static_cast<uint64_t>(LUA->GetNumber(1));
    
    auto& materialManager = RemixAPI::Instance().GetMaterialManager();
    bool result = materialManager.DestroyMaterial(materialId);
    
    LUA->PushBool(result);
    return 1;
}

// Lua function: RemixMaterial.HasMaterial(materialId)
LUA_FUNCTION(RemixMaterial_HasMaterial) {
    if (!LUA->IsType(1, Type::Number)) {
        LUA->ThrowError("Expected number for material ID");
        return 0;
    }
    
    uint64_t materialId = static_cast<uint64_t>(LUA->GetNumber(1));
    
    auto& materialManager = RemixAPI::Instance().GetMaterialManager();
    bool result = materialManager.HasMaterial(materialId);
    
    LUA->PushBool(result);
    return 1;
}

// Helper: Manually track a material (call this before rendering with a material)
LUA_FUNCTION(RemixMaterial_TrackMaterial) {
    if (!LUA->IsType(1, Type::String)) {
        LUA->ThrowError("Expected string for material name");
        return 0;
    }
    
    const char* materialName = LUA->GetString(1);
    
    Msg("[RemixMaterial] TrackMaterial: Attempting to track '%s'\n", materialName);
    
    // Try to find and "touch" the material to trigger loading
    if (materials) {
        IMaterial* pMaterial = materials->FindMaterial(materialName, TEXTURE_GROUP_MODEL);
        if (pMaterial && !pMaterial->IsErrorMaterial()) {
            Msg("[RemixMaterial] TrackMaterial: Found material, ensuring it's loaded...\n");
            
            // Force bind the material to trigger our Bind hook
            // This will update the D3D9TextureTracker with the correct material name
            IMatRenderContext* pContext = materials->GetRenderContext();
            if (pContext) {
                pContext->Bind(pMaterial);
            }

            // Get the base texture var
            bool bFound;
            IMaterialVar* pVar = pMaterial->FindVar("$basetexture", &bFound, false);
            if (bFound && pVar) {
                ITexture* pTex = pVar->GetTextureValue();
                if (pTex) {
                    // Force download to GPU (this should trigger SetTexture)
                    pTex->Download();
                    Msg("[RemixMaterial] TrackMaterial: Triggered texture download for '%s'\n", pTex->GetName());
                } else {
                    Warning("[RemixMaterial] TrackMaterial: Texture is null for '%s'\n", materialName);
                }
            } else {
                Warning("[RemixMaterial] TrackMaterial: No $basetexture found for '%s'\n", materialName);
            }
        } else {
            Warning("[RemixMaterial] TrackMaterial: Material '%s' not found or is error material\n", materialName);
        }
    }
    
    LUA->PushBool(true);
    return 1;
}

// Lua function: RemixMaterial.GetTextureHash(materialName)
// Returns the Remix texture hash for a Source Engine material's base texture
LUA_FUNCTION(RemixMaterial_GetTextureHash) {
    if (!LUA->IsType(1, Type::String)) {
        LUA->ThrowError("Expected string for material name");
        return 0;
    }
    
    const char* materialName = LUA->GetString(1);
    
    // Check Remix API is initialized
    if (!g_remix) {
        Warning("[RemixMaterial] GetTextureHash: Remix API not initialized\n");
        LUA->PushNumber(0);
        return 1;
    }
    
    // Get all texture variants for this material
    const std::vector<IDirect3DTexture9*>* variants = D3D9TextureTracker::Instance().GetTextureVariantsForMaterial(materialName);
    
    if (!variants || variants->empty()) {
        Warning("[RemixMaterial] GetTextureHash: Material '%s' not found in texture cache\n", materialName);
        Warning("[RemixMaterial]   The material may not have been rendered yet.\n");
        Warning("[RemixMaterial]   Try looking at a surface with this material first, then call this function again.\n");
        Warning("[RemixMaterial]   Cache size: %zu materials\n", D3D9TextureTracker::Instance().GetCacheSize());
        LUA->PushNumber(0);
        return 1;
    }
    
    Msg("[RemixMaterial] GetTextureHash: Found %zu texture variant(s) for '%s'\n", variants->size(), materialName);
    
    // Try all variants and collect their hashes
    uint64_t firstValidHash = 0;
    for (size_t i = 0; i < variants->size(); ++i) {
        IDirect3DTexture9* d3dTexture = (*variants)[i];
        auto result = g_remix->dxvk_GetTextureHash(d3dTexture);
        
        if (result) {
            uint64_t hash = result.value();
            Msg("[RemixMaterial]   Variant %zu (0x%p): Hash = 0x%llX\n", i, d3dTexture, hash);
            
            if (firstValidHash == 0) {
                firstValidHash = hash;
            }
        } else {
            Warning("[RemixMaterial]   Variant %zu (0x%p): Failed to get hash (error %d)\n", i, d3dTexture, result.status());
        }
    }
    
    if (firstValidHash == 0) {
        Warning("[RemixMaterial] GetTextureHash: No valid hashes found for '%s'\n", materialName);
        LUA->PushNumber(0);
        return 1;
    }
    
    // Return the first valid hash (for now)
    // TODO: We might want to let Lua choose which variant to use
    Msg("[RemixMaterial] GetTextureHash: Returning hash 0x%llX for '%s'\n", firstValidHash, materialName);
    
    // Push the hash as a string to preserve precision (Lua numbers are doubles, which lose precision for large 64-bit integers)
    // 0x2B35E18A60F3A52C is too large for double precision!
    // But wait, the user's script expects a number.
    // Let's check if we can push it as a double without losing too much info, or if we should push as string.
    // Actually, the user's script does: string.format("0x%X", hash)
    // If we push as double, 0x2B35E18A60F3A52C (3113666960980682028) becomes 3.1136669609807e18
    // Double has 53 bits of significand. 64-bit hash has 64 bits. We WILL lose precision.
    // The user reported: "Variant 0 and 1 have the hash that matches remix (0x2B35E18A60F3A52C), but the tracked one is 0x2B35E18A60F3A600"
    // 0x...52C vs 0x...600 -> This is exactly a floating point precision error!
    // 0x2B35E18A60F3A52C = 3113666960980682028
    // 0x2B35E18A60F3A600 = 3113666960980682240
    // Difference is 212.
    
    // We MUST push this as a string or split it into two 32-bit numbers if we want exact precision in Lua 5.1 (GMod).
    // However, to fix the immediate issue without breaking the Lua script's type check (if it checks for number),
    // we can't just change the type.
    // BUT, the user's script uses string.format("%X", hash).
    // If we change it to return a string, the script might break if it does math on it.
    // But for hashes, usually they are just treated as IDs.
    
    // Let's try pushing as a double for now but warn about it, OR better:
    // Since GMod Lua is LuaJIT, it might support 64-bit integers (cdata).
    // But standard Lua API PushNumber uses double.
    
    // The best fix for GMod is to return the hash as a string if it's too big, OR return it as a double and accept the loss.
    // BUT the user explicitly pointed out the mismatch.
    // "Variant 0 and 1 have the hash that matches remix (0x2B35E18A60F3A52C), but the tracked one is 0x2B35E18A60F3A600"
    // This confirms it IS a precision issue.
    
    // Let's return it as a double (standard behavior) BUT ALSO return the string version as a second return value.
    // This allows updated scripts to use the string version for exact matching.
    
    LUA->PushNumber(static_cast<double>(firstValidHash));
    
    // Push string version as second return value
    char hashStr[32];
    sprintf_s(hashStr, "0x%llX", firstValidHash);
    LUA->PushString(hashStr);
    
    return 2; // Return 2 values
}

// Lua function: RemixMaterial.GetCachedMaterials()
// Returns a table of all material names currently in the texture tracker cache
LUA_FUNCTION(RemixMaterial_GetCachedMaterials) {
    // Check Remix API is initialized
    if (!g_remix) {
        Warning("[RemixMaterial] GetCachedMaterials: Remix API not initialized\n");
        LUA->CreateTable();
        return 1;
    }
    
    std::vector<std::string> materials = D3D9TextureTracker::Instance().GetCachedMaterials();
    
    LUA->CreateTable();
    for (size_t i = 0; i < materials.size(); ++i) {
        LUA->PushNumber(static_cast<double>(i + 1)); // Lua arrays are 1-indexed
        LUA->PushString(materials[i].c_str());
        LUA->SetTable(-3);
    }
    
    return 1;
}

// Initialize Material Manager Lua bindings
void MaterialManager::InitializeLuaBindings() {
    if (!m_lua) return;
    
    // Get the global table
    m_lua->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
    
    // Create RemixMaterial table
    m_lua->CreateTable();
    
    // Add functions to the table
    m_lua->PushCFunction(RemixMaterial_CreateMaterial);
    m_lua->SetField(-2, "CreateMaterial");
    
    m_lua->PushCFunction(RemixMaterial_CreateOpaqueMaterial);
    m_lua->SetField(-2, "CreateOpaqueMaterial");
    
    m_lua->PushCFunction(RemixMaterial_DestroyMaterial);
    m_lua->SetField(-2, "DestroyMaterial");
    
    m_lua->PushCFunction(RemixMaterial_HasMaterial);
    m_lua->SetField(-2, "HasMaterial");
    
    m_lua->PushCFunction(RemixMaterial_GetTextureHash);
    m_lua->SetField(-2, "GetTextureHash");
    
    m_lua->PushCFunction(RemixMaterial_TrackMaterial);
    m_lua->SetField(-2, "TrackMaterial");

    m_lua->PushCFunction(RemixMaterial_GetCachedMaterials);
    m_lua->SetField(-2, "GetCachedMaterials");
    
    // Set the table as a global field
    m_lua->SetField(-2, "RemixMaterial");
    
    // Pop the global table
    m_lua->Pop();
    
    Msg("[MaterialManager] Lua bindings initialized\n");
}

} // namespace RemixAPI

#endif // _WIN64 