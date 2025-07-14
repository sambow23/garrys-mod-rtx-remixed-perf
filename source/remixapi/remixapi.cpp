#ifdef _WIN64
#include "remixapi.h"
#include <tier0/dbg.h>
#include <algorithm>
#include <filesystem>

// Lua bindings are implemented in separate .cpp files that are compiled independently
// No need to include them here since they define their own functions

// External global variables
extern remix::Interface* g_remix;
extern IDirect3DDevice9Ex* g_d3dDevice;

using namespace GarrysMod::Lua;

namespace RemixAPI {

//=============================================================================
// RemixAPI Main Class
//=============================================================================
RemixAPI& RemixAPI::Instance() {
    static RemixAPI instance;
    return instance;
}

RemixAPI::RemixAPI() 
    : m_remixInterface(nullptr)
    , m_lua(nullptr)
    , m_initialized(false) {
}

RemixAPI::~RemixAPI() {
    Shutdown();
}

bool RemixAPI::Initialize(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA) {
    if (m_initialized) {
        Msg("[RemixAPI] Already initialized\n");
        return false;
    }

    if (!remixInterface || !LUA) {
        Error("[RemixAPI] Invalid parameters for initialization\n");
        return false;
    }

    m_remixInterface = remixInterface;
    m_lua = LUA;

            // Initialize all managers
        m_materialManager = std::make_unique<MaterialManager>(remixInterface, LUA);
        m_meshManager = std::make_unique<MeshManager>(remixInterface, LUA);
        m_cameraManager = std::make_unique<CameraManager>(remixInterface, LUA);
        m_instanceManager = std::make_unique<InstanceManager>(remixInterface, LUA);
        m_lightManager = std::make_unique<LightManager>(remixInterface, LUA);
        m_configManager = std::make_unique<ConfigManager>(remixInterface, LUA);
        m_resourceManager = std::make_unique<ResourceManager>(remixInterface, LUA);

            // Initialize Lua bindings for all managers
        m_materialManager->InitializeLuaBindings();
        m_meshManager->InitializeLuaBindings();
        m_cameraManager->InitializeLuaBindings();
        m_instanceManager->InitializeLuaBindings();
        m_lightManager->InitializeLuaBindings();
        m_configManager->InitializeLuaBindings();
        m_resourceManager->InitializeLuaBindings();

    m_initialized = true;
    Msg("[RemixAPI] Initialization complete\n");
    return true;
}

void RemixAPI::Shutdown() {
    if (!m_initialized) return;

    m_resourceManager.reset();
    m_configManager.reset();
    m_lightManager.reset();
    m_instanceManager.reset();
    m_cameraManager.reset();
    m_meshManager.reset();
    m_materialManager.reset();

    m_remixInterface = nullptr;
    m_lua = nullptr;
    m_initialized = false;
    
    Msg("[RemixAPI] Shutdown complete\n");
}

void RemixAPI::BeginFrame() {
    if (!m_initialized) return;
    m_lightManager->BeginFrame();
}

void RemixAPI::EndFrame() {
    if (!m_initialized) return;
    m_lightManager->EndFrame();
}

void RemixAPI::Present() {
    if (!m_initialized || !m_remixInterface) return;
    
    remixapi_PresentInfo presentInfo = {};
    presentInfo.sType = REMIXAPI_STRUCT_TYPE_PRESENT_INFO;
    presentInfo.pNext = nullptr;
    presentInfo.hwndOverride = nullptr;
    
    m_remixInterface->Present(&presentInfo);
}

//=============================================================================
// MaterialManager
//=============================================================================
MaterialManager::MaterialManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA)
    : m_remixInterface(remixInterface)
    , m_lua(LUA)
    , m_nextMaterialId(1) {
}

MaterialManager::~MaterialManager() {
    // Clean up all materials
    for (auto& pair : m_materials) {
        if (pair.second.handle) {
            m_remixInterface->DestroyMaterial(pair.second.handle);
        }
    }
    m_materials.clear();
}

uint64_t MaterialManager::CreateMaterial(const std::string& name, const remix::MaterialInfo& info) {
    if (!m_remixInterface) return 0;

    auto result = m_remixInterface->CreateMaterial(info);
    if (!result) {
        Error("[MaterialManager] Failed to create material '%s': %d\n", name.c_str(), result.status());
        return 0;
    }

    uint64_t materialId = m_nextMaterialId++;
    ManagedMaterial material = {
        result.value(),
        name,
        info
    };
    
    m_materials[materialId] = material;
    Msg("[MaterialManager] Created material '%s' with ID %llu\n", name.c_str(), materialId);
    return materialId;
}

uint64_t MaterialManager::CreateOpaqueMaterial(const std::string& name, const remix::MaterialInfo& info, const remix::MaterialInfoOpaqueEXT& opaqueInfo) {
    if (!m_remixInterface) return 0;

    remix::MaterialInfo materialInfo = info;
    materialInfo.pNext = const_cast<remix::MaterialInfoOpaqueEXT*>(&opaqueInfo);

    return CreateMaterial(name, materialInfo);
}

uint64_t MaterialManager::CreateTranslucentMaterial(const std::string& name, const remix::MaterialInfo& info, const remix::MaterialInfoTranslucentEXT& translucentInfo) {
    if (!m_remixInterface) return 0;

    remix::MaterialInfo materialInfo = info;
    materialInfo.pNext = const_cast<remix::MaterialInfoTranslucentEXT*>(&translucentInfo);

    return CreateMaterial(name, materialInfo);
}

bool MaterialManager::UpdateMaterial(uint64_t materialId, const remix::MaterialInfo& info) {
    auto it = m_materials.find(materialId);
    if (it == m_materials.end()) {
        Error("[MaterialManager] Material ID %llu not found\n", materialId);
        return false;
    }

    // For now, we need to recreate the material
    // TODO: Check if Remix API supports material updates
    auto oldHandle = it->second.handle;
    auto result = m_remixInterface->CreateMaterial(info);
    if (!result) {
        Error("[MaterialManager] Failed to update material ID %llu: %d\n", materialId, result.status());
        return false;
    }

    m_remixInterface->DestroyMaterial(oldHandle);
    it->second.handle = result.value();
    it->second.info = info;
    
    return true;
}

bool MaterialManager::DestroyMaterial(uint64_t materialId) {
    auto it = m_materials.find(materialId);
    if (it == m_materials.end()) {
        Error("[MaterialManager] Material ID %llu not found\n", materialId);
        return false;
    }

    if (it->second.handle) {
        m_remixInterface->DestroyMaterial(it->second.handle);
    }
    
    m_materials.erase(it);
    Msg("[MaterialManager] Destroyed material ID %llu\n", materialId);
    return true;
}

bool MaterialManager::HasMaterial(uint64_t materialId) const {
    return m_materials.find(materialId) != m_materials.end();
}

//=============================================================================
// MeshManager
//=============================================================================
MeshManager::MeshManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA)
    : m_remixInterface(remixInterface)
    , m_lua(LUA)
    , m_nextMeshId(1) {
}

MeshManager::~MeshManager() {
    // Clean up all meshes
    for (auto& pair : m_meshes) {
        if (pair.second.handle) {
            m_remixInterface->DestroyMesh(pair.second.handle);
        }
    }
    m_meshes.clear();
}

uint64_t MeshManager::CreateMesh(const std::string& name, const remix::MeshInfo& info) {
    if (!m_remixInterface) return 0;

    auto result = m_remixInterface->CreateMesh(info);
    if (!result) {
        Error("[MeshManager] Failed to create mesh '%s': %d\n", name.c_str(), result.status());
        return 0;
    }

    uint64_t meshId = m_nextMeshId++;
    ManagedMesh mesh = {
        result.value(),
        name,
        info
    };
    
    m_meshes[meshId] = mesh;
    Msg("[MeshManager] Created mesh '%s' with ID %llu\n", name.c_str(), meshId);
    return meshId;
}

bool MeshManager::UpdateMesh(uint64_t meshId, const remix::MeshInfo& info) {
    auto it = m_meshes.find(meshId);
    if (it == m_meshes.end()) {
        Error("[MeshManager] Mesh ID %llu not found\n", meshId);
        return false;
    }

    // For now, we need to recreate the mesh
    // TODO: Check if Remix API supports mesh updates
    auto oldHandle = it->second.handle;
    auto result = m_remixInterface->CreateMesh(info);
        if (!result) {
        Error("[MeshManager] Failed to update mesh ID %llu: %d\n", meshId, result.status());
        return false;
    }

    m_remixInterface->DestroyMesh(oldHandle);
    it->second.handle = result.value();
    it->second.info = info;
    
    return true;
}

bool MeshManager::DestroyMesh(uint64_t meshId) {
    auto it = m_meshes.find(meshId);
    if (it == m_meshes.end()) {
        Error("[MeshManager] Mesh ID %llu not found\n", meshId);
        return false;
    }

    if (it->second.handle) {
        m_remixInterface->DestroyMesh(it->second.handle);
    }
    
    m_meshes.erase(it);
    Msg("[MeshManager] Destroyed mesh ID %llu\n", meshId);
    return true;
}

bool MeshManager::HasMesh(uint64_t meshId) const {
    return m_meshes.find(meshId) != m_meshes.end();
}

//=============================================================================
// CameraManager
//=============================================================================
CameraManager::CameraManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA)
    : m_remixInterface(remixInterface)
    , m_lua(LUA) {
}

CameraManager::~CameraManager() {
}

bool CameraManager::SetupCamera(const remix::CameraInfo& info) {
    if (!m_remixInterface) return false;

    auto result = m_remixInterface->SetupCamera(info);
    if (!result) {
        Error("[CameraManager] Failed to setup camera: %d\n", result.status());
        return false;
    }
    
    return true;
}

bool CameraManager::SetupParameterizedCamera(const remix::CameraInfoParameterizedEXT& info) {
    if (!m_remixInterface) return false;

    remix::CameraInfo cameraInfo;
    cameraInfo.sType = REMIXAPI_STRUCT_TYPE_CAMERA_INFO;
    cameraInfo.pNext = const_cast<remix::CameraInfoParameterizedEXT*>(&info);
    cameraInfo.type = REMIXAPI_CAMERA_TYPE_WORLD;

    return SetupCamera(cameraInfo);
}

//=============================================================================
// InstanceManager
//=============================================================================
InstanceManager::InstanceManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA)
    : m_remixInterface(remixInterface)
    , m_lua(LUA) {
}

InstanceManager::~InstanceManager() {
}

bool InstanceManager::DrawInstance(const remix::InstanceInfo& info) {
    if (!m_remixInterface) return false;

    auto result = m_remixInterface->DrawInstance(info);
    if (!result) {
        Error("[InstanceManager] Failed to draw instance: %d\n", result.status());
        return false;
    }
    
    return true;
}

bool InstanceManager::DrawInstanceWithBlend(const remix::InstanceInfo& info, const remix::InstanceInfoBlendEXT& blendInfo) {
    if (!m_remixInterface) return false;

    remix::InstanceInfo instanceInfo = info;
    instanceInfo.pNext = const_cast<remix::InstanceInfoBlendEXT*>(&blendInfo);

    return DrawInstance(instanceInfo);
}

bool InstanceManager::DrawInstanceWithBones(const remix::InstanceInfo& info, const remix::InstanceInfoBoneTransformsEXT& boneInfo) {
    if (!m_remixInterface) return false;

    remix::InstanceInfo instanceInfo = info;
    instanceInfo.pNext = const_cast<remix::InstanceInfoBoneTransformsEXT*>(&boneInfo);

    return DrawInstance(instanceInfo);
}

//=============================================================================
// LightManager
//=============================================================================
LightManager::LightManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA)
    : m_remixInterface(remixInterface)
    , m_lua(LUA)
    , m_nextLightId(1) {
}

LightManager::~LightManager() {
    ClearAllLights();
}

uint64_t LightManager::CreateSphereLight(const remix::LightInfo& baseInfo, const remix::LightInfoSphereEXT& sphereInfo, uint64_t entityID) {
    if (!m_remixInterface) return 0;

    remix::LightInfo lightInfo = baseInfo;
    lightInfo.pNext = const_cast<remix::LightInfoSphereEXT*>(&sphereInfo);

    auto result = m_remixInterface->CreateLight(lightInfo);
    if (!result) {
        Error("[LightManager] Failed to create sphere light: %d\n", result.status());
        return 0;
    }

    uint64_t lightId = m_nextLightId++;
    ManagedLight light = {
        result.value(),
        baseInfo,
        "sphere",
        entityID,
        baseInfo.hash
    };
    
    m_lights[lightId] = light;
    LogMessage("Created sphere light with ID %llu (entity: %llu)", lightId, entityID);
    return lightId;
}

uint64_t LightManager::CreateRectLight(const remix::LightInfo& baseInfo, const remix::LightInfoRectEXT& rectInfo, uint64_t entityID) {
    if (!m_remixInterface) return 0;

    remix::LightInfo lightInfo = baseInfo;
    lightInfo.pNext = const_cast<remix::LightInfoRectEXT*>(&rectInfo);

    auto result = m_remixInterface->CreateLight(lightInfo);
    if (!result) {
        Error("[LightManager] Failed to create rect light: %d\n", result.status());
            return 0;
        }
        
    uint64_t lightId = m_nextLightId++;
    ManagedLight light = {
        result.value(),
        baseInfo,
        "rect",
        entityID,
        baseInfo.hash
    };
    
    m_lights[lightId] = light;
    LogMessage("Created rect light with ID %llu (entity: %llu)", lightId, entityID);
    return lightId;
}

uint64_t LightManager::CreateDiskLight(const remix::LightInfo& baseInfo, const remix::LightInfoDiskEXT& diskInfo, uint64_t entityID) {
    if (!m_remixInterface) return 0;

    remix::LightInfo lightInfo = baseInfo;
    lightInfo.pNext = const_cast<remix::LightInfoDiskEXT*>(&diskInfo);

    auto result = m_remixInterface->CreateLight(lightInfo);
    if (!result) {
        Error("[LightManager] Failed to create disk light: %d\n", result.status());
            return 0;
        }
        
    uint64_t lightId = m_nextLightId++;
    ManagedLight light = {
        result.value(),
        baseInfo,
        "disk",
        entityID,
        baseInfo.hash
    };
    
    m_lights[lightId] = light;
    LogMessage("Created disk light with ID %llu (entity: %llu)", lightId, entityID);
    return lightId;
}

uint64_t LightManager::CreateCylinderLight(const remix::LightInfo& baseInfo, const remix::LightInfoCylinderEXT& cylinderInfo, uint64_t entityID) {
    if (!m_remixInterface) return 0;

    remix::LightInfo lightInfo = baseInfo;
    lightInfo.pNext = const_cast<remix::LightInfoCylinderEXT*>(&cylinderInfo);

    auto result = m_remixInterface->CreateLight(lightInfo);
        if (!result) {
        Error("[LightManager] Failed to create cylinder light: %d\n", result.status());
            return 0;
        }

    uint64_t lightId = m_nextLightId++;
    ManagedLight light = {
        result.value(),
        baseInfo,
        "cylinder",
        entityID,
        baseInfo.hash
    };
    
    m_lights[lightId] = light;
    LogMessage("Created cylinder light with ID %llu (entity: %llu)", lightId, entityID);
    return lightId;
}

uint64_t LightManager::CreateDistantLight(const remix::LightInfo& baseInfo, const remix::LightInfoDistantEXT& distantInfo, uint64_t entityID) {
    if (!m_remixInterface) return 0;

    remix::LightInfo lightInfo = baseInfo;
    lightInfo.pNext = const_cast<remix::LightInfoDistantEXT*>(&distantInfo);

    auto result = m_remixInterface->CreateLight(lightInfo);
    if (!result) {
        Error("[LightManager] Failed to create distant light: %d\n", result.status());
        return 0;
    }

    uint64_t lightId = m_nextLightId++;
    ManagedLight light = {
        result.value(),
        baseInfo,
        "distant",
        entityID,
        baseInfo.hash
    };
    
    m_lights[lightId] = light;
    LogMessage("Created distant light with ID %llu (entity: %llu)", lightId, entityID);
    return lightId;
}

uint64_t LightManager::CreateDomeLight(const remix::LightInfo& baseInfo, const remix::LightInfoDomeEXT& domeInfo, uint64_t entityID) {
    if (!m_remixInterface) return 0;

    remix::LightInfo lightInfo = baseInfo;
    lightInfo.pNext = const_cast<remix::LightInfoDomeEXT*>(&domeInfo);

    auto result = m_remixInterface->CreateLight(lightInfo);
    if (!result) {
        Error("[LightManager] Failed to create dome light: %d\n", result.status());
        return 0;
    }

    uint64_t lightId = m_nextLightId++;
    ManagedLight light = {
        result.value(),
        baseInfo,
        "dome",
        entityID,
        baseInfo.hash
    };
    
    m_lights[lightId] = light;
    LogMessage("Created dome light with ID %llu (entity: %llu)", lightId, entityID);
    return lightId;
}

bool LightManager::UpdateLight(uint64_t lightId, const remix::LightInfo& baseInfo) {
    auto it = m_lights.find(lightId);
    if (it == m_lights.end()) {
        Error("[LightManager] Light ID %llu not found\n", lightId);
        return false;
    }

    // For now, we need to recreate the light since Remix API doesn't support direct updates
    // TODO: Check if future Remix API versions support light updates
    LogMessage("Light updates require recreation - feature not yet implemented");
    return false;
}

bool LightManager::DestroyLight(uint64_t lightId) {
    auto it = m_lights.find(lightId);
    if (it == m_lights.end()) {
        Error("[LightManager] Light ID %llu not found\n", lightId);
        return false;
    }

    if (it->second.handle) {
        m_remixInterface->DestroyLight(it->second.handle);
    }
    
    LogMessage("Destroyed %s light with ID %llu", it->second.lightType.c_str(), lightId);
    m_lights.erase(it);
    return true;
}

bool LightManager::HasLight(uint64_t lightId) const {
    return m_lights.find(lightId) != m_lights.end();
}

bool LightManager::HasLightForEntity(uint64_t entityID) const {
    if (entityID == 0) return false;
    
    for (const auto& pair : m_lights) {
        if (pair.second.entityID == entityID) {
            return true;
        }
    }
    return false;
}

std::vector<uint64_t> LightManager::GetLightsForEntity(uint64_t entityID) const {
    std::vector<uint64_t> lightIds;
    if (entityID == 0) return lightIds;
    
    for (const auto& pair : m_lights) {
        if (pair.second.entityID == entityID) {
            lightIds.push_back(pair.first);
        }
    }
    return lightIds;
}

void LightManager::DestroyLightsForEntity(uint64_t entityID) {
    if (entityID == 0) return;
    
    auto lightIds = GetLightsForEntity(entityID);
    for (uint64_t lightId : lightIds) {
        DestroyLight(lightId);
    }
    
    if (!lightIds.empty()) {
        LogMessage("Destroyed %zu lights for entity %llu", lightIds.size(), entityID);
    }
}

void LightManager::SetEntityValidator(std::function<bool(uint64_t)> validator) {
    m_entityValidator = validator;
}

void LightManager::CleanupInvalidEntities() {
    if (!m_entityValidator) return;
    
    std::vector<uint64_t> toRemove;
    for (const auto& pair : m_lights) {
        if (pair.second.entityID != 0 && !m_entityValidator(pair.second.entityID)) {
            toRemove.push_back(pair.first);
        }
    }
    
    for (uint64_t lightId : toRemove) {
        DestroyLight(lightId);
    }
    
    if (!toRemove.empty()) {
        LogMessage("Cleaned up %zu lights with invalid entities", toRemove.size());
    }
}

void LightManager::BeginFrame() {
    // Clean up invalid entities at the start of each frame
    CleanupInvalidEntities();
}

void LightManager::EndFrame() {
    // Draw all lights
    DrawLights();
}

void LightManager::DrawLights() {
    if (!m_remixInterface) return;
    
    for (const auto& pair : m_lights) {
        if (pair.second.handle) {
            auto result = m_remixInterface->DrawLightInstance(pair.second.handle);
            if (!result) {
                Error("[LightManager] Failed to draw light %llu: %d\n", pair.first, result.status());
            }
        }
    }
}

size_t LightManager::GetLightCount() const {
    return m_lights.size();
}

void LightManager::ClearAllLights() {
    if (!m_remixInterface) {
        m_lights.clear();
        return;
    }
    
    for (auto& pair : m_lights) {
        if (pair.second.handle) {
            m_remixInterface->DestroyLight(pair.second.handle);
        }
    }
    
    size_t count = m_lights.size();
    m_lights.clear();
    
    if (count > 0) {
        LogMessage("Cleared %zu lights", count);
    }
}

void LightManager::LogMessage(const char* format, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsprintf_s(buffer, sizeof(buffer), format, args);
    va_end(args);
    Msg("[LightManager] %s\n", buffer);
}

//=============================================================================
// ConfigManager
//=============================================================================
ConfigManager::ConfigManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA)
    : m_remixInterface(remixInterface)
    , m_lua(LUA) {
    
    // Capture default values on initialization
    CaptureCurrentValues();
}

ConfigManager::~ConfigManager() {
}

bool ConfigManager::SetConfigVariable(const std::string& key, const std::string& value) {
    if (!m_remixInterface) return false;

    // Handle deprecated/invalid config variables with suggestions
    if (key == "rtx.enableAdvancedMode") {
        Warning("[ConfigManager] 'rtx.enableAdvancedMode' is not a valid RTX option. Use 'rtx.showUI' (0=Don't Show, 1=Show Simple, 2=Show Advanced) or 'rtx.defaultToAdvancedUI' (True/False) instead.\n");
        
        // Auto-convert to the correct option
        if (value == "1" || value == "true" || value == "True") {
            // Try to set advanced UI as default
            auto result = m_remixInterface->SetConfigVariable("rtx.defaultToAdvancedUI", "True");
            if (result) {
                m_configCache["rtx.defaultToAdvancedUI"] = "True";
                return true;
            }
        }
        return false;
    }

    auto result = m_remixInterface->SetConfigVariable(key.c_str(), value.c_str());
    if (!result) {
        Error("[ConfigManager] Failed to set config variable '%s': %d\n", key.c_str(), result.status());
        return false;
    }
    
    m_configCache[key] = value;
    return true;
}

std::string ConfigManager::GetConfigVariable(const std::string& key) {
    auto it = m_configCache.find(key);
    if (it != m_configCache.end()) {
        return it->second;
    }
    
    // Return empty string if not in cache
    // Note: RTX Remix API doesn't support reading config variables back
    Warning("[ConfigManager] Config variable '%s' not found in cache. Use CaptureCurrentValues() to populate cache with current settings.\n", key.c_str());
    return "";
}

void ConfigManager::CaptureCurrentValues() {
    // Since RTX Remix API doesn't support reading config variables,
    // we'll populate the cache with reasonable default values that users can then modify
    
    // Core lighting defaults
    m_configCache["rtx.enableRaytracing"] = "True";
    m_configCache["rtx.enableDirectLighting"] = "True"; 
    m_configCache["rtx.enableSecondaryBounces"] = "True";
    m_configCache["rtx.pathMaxBounces"] = "4";
    m_configCache["rtx.pathMinBounces"] = "1";
    
    // Denoising defaults
    m_configCache["rtx.useDenoiser"] = "True";
    m_configCache["rtx.denoiseDirectAndIndirectLightingSeparately"] = "True";
    m_configCache["rtx.denoiserMode"] = "14";
    
    // Upscaling defaults
    m_configCache["rtx.upscalerType"] = "1";
    m_configCache["rtx.resolutionScale"] = "0.75";
    m_configCache["rtx.qualityDLSS"] = "2";
    
    // Volumetrics defaults
    m_configCache["rtx.volumetrics.enable"] = "True";
    m_configCache["rtx.volumetrics.enableAtmosphere"] = "False";
    m_configCache["rtx.volumetrics.froxelMaxDistanceMeters"] = "100";
    
    // Auto exposure defaults
    m_configCache["rtx.autoExposure.enabled"] = "True";
    m_configCache["rtx.autoExposure.evMinValue"] = "-2";
    m_configCache["rtx.autoExposure.evMaxValue"] = "4";
    
    // Tonemapping defaults
    m_configCache["rtx.tonemap.exposureBias"] = "0";
    m_configCache["rtx.tonemap.dynamicRange"] = "15";
    m_configCache["rtx.tonemappingMode"] = "1";
    
    // Performance defaults
    m_configCache["rtx.risLightSampleCount"] = "6";
    m_configCache["rtx.di.initialSampleCount"] = "4";
    m_configCache["rtx.primaryRayMaxInteractions"] = "32";
    
    // Visual effects defaults
    m_configCache["rtx.bloom.enable"] = "True";
    m_configCache["rtx.bloom.burnIntensity"] = "1";
    m_configCache["rtx.postfx.enable"] = "True";
    m_configCache["rtx.enableFog"] = "False";
    
    // UI defaults
    m_configCache["rtx.defaultToAdvancedUI"] = "True";
    m_configCache["rtx.showUI"] = "0";
    
    Msg("[ConfigManager] Captured default config values into cache\n");
}

void ConfigManager::SetCachedValue(const std::string& key, const std::string& value) {
    m_configCache[key] = value;
}

remix::UIState ConfigManager::GetUIState() {
    if (!m_remixInterface) return remix::UIState::None;

    auto result = m_remixInterface->GetUIState();
    if (!result) {
        Error("[ConfigManager] Failed to get UI state: %d\n", result.status());
        return remix::UIState::None;
    }
    
    return result.value();
}

bool ConfigManager::SetUIState(remix::UIState state) {
    if (!m_remixInterface) return false;

    auto result = m_remixInterface->SetUIState(state);
    if (!result) {
        Error("[ConfigManager] Failed to set UI state: %d\n", result.status());
        return false;
    }
    
    return true;
}

//=============================================================================
// ResourceManager
//=============================================================================
ResourceManager::ResourceManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA)
    : m_remixInterface(remixInterface)
    , m_lua(LUA) {
}

ResourceManager::~ResourceManager() {
}

void ResourceManager::ClearResources() {
    if (!m_remixInterface) return;

    // Force a present cycle to clear resources
    remixapi_PresentInfo presentInfo = {};
    presentInfo.sType = REMIXAPI_STRUCT_TYPE_PRESENT_INFO;
    presentInfo.pNext = nullptr;
    presentInfo.hwndOverride = nullptr;
    
    m_remixInterface->Present(&presentInfo);
    
    // Clear D3D9 managed resources if available
    if (g_d3dDevice) {
        g_d3dDevice->EvictManagedResources();
    }
}

void ResourceManager::ForceCleanup() {
    if (!m_remixInterface) return;

    // Force cleanup through config
    m_remixInterface->SetConfigVariable("rtx.resourceLimits.forceCleanup", "1");
    
    ClearResources();
    
    // Reset to normal cleanup behavior
    m_remixInterface->SetConfigVariable("rtx.resourceLimits.forceCleanup", "0");
}

void ResourceManager::SetMemoryLimits(size_t maxCacheSize, size_t maxVRAM) {
    if (!m_remixInterface) return;

    m_remixInterface->SetConfigVariable("rtx.resourceLimits.maxCacheSize", std::to_string(maxCacheSize).c_str());
    m_remixInterface->SetConfigVariable("rtx.resourceLimits.maxVRAM", std::to_string(maxVRAM).c_str());
}

//=============================================================================
// Lua Bindings - Implementation will be in separate files
//=============================================================================

// All Lua bindings are implemented in their respective separate .cpp files:
// - material_lua_bindings.cpp
// - config_lua_bindings.cpp  
// - resource_lua_bindings.cpp
// - light_lua_bindings.cpp

void MeshManager::InitializeLuaBindings() {
    // TODO: Implement mesh Lua bindings
}

void CameraManager::InitializeLuaBindings() {
    // TODO: Implement camera Lua bindings
}

void InstanceManager::InitializeLuaBindings() {
    // TODO: Implement instance Lua bindings
}

//=============================================================================
// Legacy Functions for Backwards Compatibility
//=============================================================================
void Initialize(GarrysMod::Lua::ILuaBase* LUA) {
    // Legacy initialization - use the new API
    if (g_remix && LUA) {
        RemixAPI::Instance().Initialize(g_remix, LUA);
    }
}

void ClearRemixResources() {
    RemixAPI::Instance().GetResourceManager().ClearResources();
}

} // namespace RemixAPI

#endif // _WIN64