#ifdef _WIN64
#include "remixapi.h"
#include <tier0/dbg.h>

using namespace GarrysMod::Lua;

namespace RemixAPI {

// Helper function to extract MaterialInfo from Lua table
static remix::MaterialInfo LuaToMaterialInfo(ILuaBase* LUA, int index) {
    remix::MaterialInfo info;
    
    if (!LUA->IsType(index, Type::Table)) {
        LUA->ThrowError("Expected table for MaterialInfo");
        return info;
    }
    
    // Get hash
    LUA->GetField(index, "hash");
    if (LUA->IsType(-1, Type::Number)) {
        info.hash = static_cast<uint64_t>(LUA->GetNumber(-1));
    }
    LUA->Pop();
    
    // Get albedo texture
    LUA->GetField(index, "albedoTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        info.set_albedoTexture(texture);
    }
    LUA->Pop();
    
    // Get normal texture
    LUA->GetField(index, "normalTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        info.set_normalTexture(texture);
    }
    LUA->Pop();
    
    // Get tangent texture
    LUA->GetField(index, "tangentTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        info.set_tangentTexture(texture);
    }
    LUA->Pop();
    
    // Get emissive texture
    LUA->GetField(index, "emissiveTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        info.set_emissiveTexture(texture);
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
    
    // Get roughness texture
    LUA->GetField(index, "roughnessTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        info.set_roughnessTexture(texture);
    }
    LUA->Pop();
    
    // Get metallic texture
    LUA->GetField(index, "metallicTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        info.set_metallicTexture(texture);
    }
    LUA->Pop();
    
    // Get height texture
    LUA->GetField(index, "heightTexture");
    if (LUA->IsType(-1, Type::String)) {
        std::string texture = LUA->GetString(-1);
        info.set_heightTexture(texture);
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
    
    // Set the table as a global field
    m_lua->SetField(-2, "RemixMaterial");
    
    // Pop the global table
    m_lua->Pop();
    
    Msg("[MaterialManager] Lua bindings initialized\n");
}

} // namespace RemixAPI

#endif // _WIN64 