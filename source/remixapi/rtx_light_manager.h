#pragma once
#include <d3d9.h>
#include <remix/remix.h>
#include <remix/remix_c.h>
#include <vector>
#include <queue>
#include <unordered_map>
#include <functional>
#include <Windows.h>
#include "GarrysMod/Lua/Interface.h"
#include "./rtxlights/rtx_light_base.h"
#include "./rtxlights/rtx_light_sphere.h"
#include "./rtxlights/rtx_light_rect.h"
#include "./rtxlights/rtx_light_disk.h"
#include "./rtxlights/rtx_light_distant.h"

class RTXLightManager {
public:
    static RTXLightManager& Instance();

    // Light creation functions for different types
    remixapi_LightHandle CreateSphereLight(const RTX::SphereProperties& props, uint64_t entityID = 0);
    remixapi_LightHandle CreateRectLight(const RTX::RectProperties& props, uint64_t entityID = 0);
    remixapi_LightHandle CreateDiskLight(const RTX::DiskProperties& props, uint64_t entityID = 0);
    remixapi_LightHandle CreateDistantLight(const RTX::DistantProperties& props, uint64_t entityID = 0);
    
    // Generic update and management functions
    bool UpdateLight(remixapi_LightHandle handle, const void* props, int lightType, remixapi_LightHandle* newHandle = nullptr);
    bool IsValidHandle(remixapi_LightHandle handle) const;
    void DestroyLight(remixapi_LightHandle handle);
    void DrawLights();
    bool HasLightForEntity(uint64_t entityID) const;
    void ValidateState();
    void RegisterLuaEntityValidator(std::function<bool(uint64_t)> validator);

    // Frame synchronization
    void BeginFrame();
    void EndFrame();
    void ProcessPendingUpdates();
    
    // Utility functions
    void Initialize(remix::Interface* remixInterface);
    void Shutdown();
    void CleanupInvalidLights();
    static void InitializeLuaBindings(GarrysMod::Lua::ILuaBase* LUA);

private:
    RTXLightManager();
    ~RTXLightManager();

    // Light tracking structure
    struct ManagedLight {
        remixapi_LightHandle handle;
        std::shared_ptr<RTX::ILight> lightObject;
        uint64_t entityID;
        float lastUpdateTime;
        bool needsUpdate;
    };

    // Update tracking
    struct PendingUpdate {
        remixapi_LightHandle handle;
        std::shared_ptr<RTX::ILight> newLightObject;
        bool needsUpdate;
        bool requiresRecreation;
    };

    // Internal helper functions
    void LogMessage(const char* format, ...);
    uint64_t GenerateLightHash() const;

    // Member variables
    remix::Interface* m_remix;
    std::vector<ManagedLight> m_lights;
    std::vector<ManagedLight> m_lightsToDestroy;
    std::queue<PendingUpdate> m_pendingUpdates;
    std::unordered_map<uint64_t, ManagedLight> m_lightsByEntityID;
    std::function<bool(uint64_t)> m_luaEntityValidator;
    mutable CRITICAL_SECTION m_lightCS;
    mutable CRITICAL_SECTION m_updateCS;
    bool m_initialized;
    bool m_isFrameActive;

    // Delete copy constructor and assignment operator
    RTXLightManager(const RTXLightManager&) = delete;
    RTXLightManager& operator=(const RTXLightManager&) = delete;
};